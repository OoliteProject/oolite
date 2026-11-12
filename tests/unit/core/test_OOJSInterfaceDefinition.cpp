/*	test_OOJSInterfaceDefinition.mm
        Unit tests for OOJSInterfaceDefinition
   (src/Core/Scripting/OOJSInterfaceDefinition.h/.mm).

        An interface definition is a station's F4 interface entry made by a
   script: a title, category and summary, and a JS callback and its `this` that
   it keeps alive (owned references) and runs with the entry's key, pushing the
   script that made it. The test runs it in a real QuickJS-ng context and links
   the game's own objects for the class. What the rest of the engine would
        provide is defined below as the smallest stand-in that does the same
   thing: the engine object (which calls the function), the script stack
   (OOJSScript) and the property-list converter. The engine's and OOJSScript's
   headers are not imported, because the test defines those classes; the class's
   header names OOScript with @class for that. The tests pin the initial state
   and the text properties, the callback and its `this` (kept alive across a
   garbage collection), the run, the sort order (interfaceCompare(), with its
   null cases) and an engine reset. Run: tests/run.sh unit
*/

#include <quickjs.h>

#include <cstring>
#include <string>
#include <vector>

#include "OOJSInterfaceDefinition.h"
#include "oo_test.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

// MARK: What the rest of the engine provides
// ------------------------------------------------------

class OOJSScript;

namespace {
std::vector<OOJSScript*> sPushed;
int sScriptDepth = 0;
int sCalls = 0;
}  // namespace

JSContext* gOOJSMainThreadContext = nullptr;
extern const char* const kOOJavaScriptEngineWillResetNotificationName;
const char* const kOOJavaScriptEngineWillResetNotificationName =
    "org.aegidian.oolite OOJavaScriptEngine will reset";

// A property list as JS, as far as the definition hands one over: a string.
JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist) {
  const std::string* string = plist.getIf<std::string>();
  if (string == nullptr) return JS_NULL;
  return JS_NewStringLen(context, string->data(), string->size());
}

// The engine (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine {
 public:
  static OOJavaScriptEngine* sharedEngine();
  bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc,
                      JSValueConst* argv, JSValue* outResult);
};

OOJavaScriptEngine* OOJavaScriptEngine::sharedEngine() {
  static OOJavaScriptEngine* engine = new OOJavaScriptEngine;
  return engine;
}

// As the engine's: the call, its result owned by the caller, and an exception
// reported (here, dropped) and cleared.
bool OOJavaScriptEngine::callJSFunction(JSValueConst function,
                                        JSValueConst jsThis, int argc,
                                        JSValueConst* argv,
                                        JSValue* outResult) {
  sCalls++;
  JSContext* context = gOOJSMainThreadContext;
  JSValue result = JS_Call(context, function, jsThis, argc, argv);
  if (JS_IsException(result)) {
    JS_FreeValue(context, JS_GetException(context));
    if (outResult != NULL) *outResult = JS_UNDEFINED;
    return false;
  }
  if (outResult != NULL)
    *outResult = result;
  else
    JS_FreeValue(context, result);
  return true;
}

// The script stack: the running script (set by the test) and what was pushed.
namespace {
OOJSScript* sRunningScript = nullptr;
}  // namespace

#include "OOScript.h"

// OOJSScript (OOJSScript.h), which the code under test calls. A script is a
// C++ object, so the stand-in is a C++ subclass of OOScript declaring the
// members that code calls.
class OOJSScript : public OOScript {
 public:
  static OOJSScript* currentlyRunningScript();
  static void pushScript(const oo::WeakRef<OOJSScript>& script);
  static void popScript(OOJSScript* script);
};

// OOScript's virtual members (OOScript.mm reaches the whole game), for the
// test's scripts' vtable.
std::optional<std::string> OOScript::descriptionComponents() {
  return std::nullopt;
}
std::optional<std::string> OOScript::name() { return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription() {
  return std::nullopt;
}
std::optional<std::string> OOScript::version() { return std::nullopt; }
bool OOScript::requiresTickle() { return false; }
void OOScript::runWithTarget(Entity*) {}
bool OOScript::callMethod(JSAtom, JSContext*, JSValueConst*, int, JSValue*) {
  return false;
}
std::string OOScript::className() const { return "OOScript"; }
std::string OOScript::description() const { return "<OOScript>"; }
JSValue OOScript::jsValueInContext(JSContext*) { return JS_UNDEFINED; }
void OOScript::clearJSSelf(JSValueConst) {}

OOJSScript* OOJSScript::currentlyRunningScript() { return sRunningScript; }
void OOJSScript::pushScript(const oo::WeakRef<OOJSScript>& script) {
  sPushed.push_back(script.get());
  sScriptDepth++;
}
void OOJSScript::popScript(OOJSScript* script) {
  (void)script;
  sScriptDepth--;
}

// MARK: The context
// -------------------------------------------------------------------------------

namespace {

JSContext* Context() {
  if (gOOJSMainThreadContext == nullptr) {
    JSRuntime* runtime = JS_NewRuntime();
    JS_SetMemoryLimit(runtime, 8u * 1024u * 1024u);
    gOOJSMainThreadContext = JS_NewContext(runtime);
  }
  return gOOJSMainThreadContext;
}

// An owned value, freed when it goes: what Evaluate() gives, so that a value
// handed to the definition has no other reference once the statement ends.
class Owned {
 public:
  explicit Owned(JSValue value) : _value(value) {}
  ~Owned() { JS_FreeValue(Context(), _value); }
  Owned(const Owned&) = delete;
  Owned& operator=(const Owned&) = delete;
  operator JSValueConst() const { return _value; }

 private:
  JSValue _value;
};

Owned Evaluate(const char* src) {
  JSValue result =
      JS_Eval(Context(), src, std::strlen(src), "test.js", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(result)) {
    JS_FreeValue(Context(), JS_GetException(Context()));
    result = JS_UNDEFINED;
  }
  return Owned(result);
}

std::string String(JSValueConst value) {
  if (JS_IsNull(value) || JS_IsUndefined(value))
    return JS_IsNull(value) ? "null" : "undefined";
  std::size_t length = 0;
  const char* chars = JS_ToCStringLen(Context(), &length, value);
  if (chars == nullptr) return "<none>";
  std::string result(chars, length);
  JS_FreeCString(Context(), chars);
  return result;
}

// Whether an owned value (what -callback and -callbackThis answer) is
// undefined, or an object; the value is freed.
bool IsUndefined(JSValue value) {
  bool result = JS_IsUndefined(value);
  JS_FreeValue(Context(), value);
  return result;
}

bool IsObject(JSValue value) {
  bool result = JS_IsObject(value);
  JS_FreeValue(Context(), value);
  return result;
}

void CollectGarbage() { JS_RunGC(JS_GetRuntime(Context())); }

}  // namespace

// MARK: Tests
// -------------------------------------------------------------------------------------

OO_TEST(initialState) {
  Context();
  const oo::Ref<OOJSInterfaceDefinition> definition =
      oo::makeRef<OOJSInterfaceDefinition>();
  OO_CHECK(definition != nullptr);
  OO_CHECK(IsUndefined(definition->callback()));
  OO_CHECK(!IsObject(definition->callbackThis()));
  OO_CHECK(!definition->title().has_value());
  OO_CHECK(!definition->category().has_value());
  OO_CHECK(!definition->summary().has_value());
  definition->setTitle(std::string("Title"));
  definition->setCategory("Cat");
  definition->setSummary("Sum");
  OO_CHECK_EQ(definition->title().value_or("<none>"), "Title");
  OO_CHECK_EQ(definition->category().value_or("<none>"), "Cat");
  OO_CHECK_EQ(definition->summary().value_or("<none>"), "Sum");
  definition->setTitle(std::nullopt);
  OO_CHECK(!definition->title().has_value());
}

OO_TEST(runCallback) {
  {
    const oo::Ref<OOJSScript> owner = oo::makeRef<OOJSScript>();
    sRunningScript = owner.get();
    const oo::Ref<OOJSInterfaceDefinition> definition =
        oo::makeRef<OOJSInterfaceDefinition>();
    sRunningScript = nullptr;

    // Neither the function nor `this` has another reference: the definition
    // keeps them alive.
    definition->setCallback(
        Evaluate("(function (key) { globalThis.ran = this.tag + ':' + key + "
                 "':' + arguments.length; })"));
    definition->setCallbackThis(Evaluate("({ tag: 'me' })"));
    OO_CHECK(IsObject(definition->callback()));
    OO_CHECK(IsObject(definition->callbackThis()));
    CollectGarbage();

    sPushed.clear();
    sCalls = 0;
    definition->runCallback("dock");
    OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "me:dock:1");
    OO_CHECK_EQ(sCalls, 1);
    OO_CHECK_EQ(sScriptDepth, 0);
    OO_CHECK(sPushed.size() == 1 &&
             sPushed[0] == owner.get());  // the script that made it

    // Replacing the callback and `this`: the new ones run.
    definition->setCallback(
        Evaluate("(function (key) { globalThis.ran = 'second ' + key + ' ' + "
                 "(this === globalThis); })"));
    definition->setCallbackThis(JS_UNDEFINED);
    definition->runCallback("k");
    OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "second k true");
  }
}

namespace {
oo::Ref<OOJSInterfaceDefinition> Interface(std::optional<std::string> category,
                                           std::optional<std::string> title) {
  const oo::Ref<OOJSInterfaceDefinition> definition =
      oo::makeRef<OOJSInterfaceDefinition>();
  if (category.has_value()) definition->setCategory(*category);
  definition->setTitle(title);
  return definition;
}
}  // namespace

OO_TEST(interfaceCompare) {
  // By category, then by title, ignoring case.
  OO_CHECK_EQ(
      Interface("alpha", "z")->interfaceCompare(Interface("Beta", "a").get()),
      OOComparisonResult::kAscending);
  OO_CHECK_EQ(
      Interface("beta", "a")->interfaceCompare(Interface("ALPHA", "z").get()),
      OOComparisonResult::kDescending);
  OO_CHECK_EQ(Interface("same", "apple")
                  ->interfaceCompare(Interface("SAME", "Banana").get()),
              OOComparisonResult::kAscending);
  OO_CHECK_EQ(Interface("same", "Banana")
                  ->interfaceCompare(Interface("same", "apple").get()),
              OOComparisonResult::kDescending);
  OO_CHECK_EQ(
      Interface("same", "x")->interfaceCompare(Interface("same", "X").get()),
      OOComparisonResult::kSame);
  // No category of its own: the same category as anything (a message to nil);
  // then the titles.
  OO_CHECK_EQ(Interface(std::nullopt, "b")
                  ->interfaceCompare(Interface("cat", "a").get()),
              OOComparisonResult::kDescending);
  // The other's missing category or title is the empty string.
  OO_CHECK_EQ(Interface("cat", "a")
                  ->interfaceCompare(Interface(std::nullopt, "a").get()),
              OOComparisonResult::kDescending);
  OO_CHECK_EQ(Interface("", "a")->interfaceCompare(
                  Interface(std::nullopt, std::nullopt).get()),
              OOComparisonResult::kDescending);
  OO_CHECK_EQ(Interface("", std::nullopt)
                  ->interfaceCompare(Interface(std::nullopt, "a").get()),
              OOComparisonResult::kSame);
  // Null: its category and title are missing.
  OO_CHECK_EQ(Interface("cat", "a")->interfaceCompare(nullptr),
              OOComparisonResult::kDescending);
}

OO_TEST(engineReset) {
  {
    const oo::Ref<OOJSInterfaceDefinition> definition =
        oo::makeRef<OOJSInterfaceDefinition>();
    definition->setCallback(Evaluate("(function () {})"));
    definition->setCallbackThis(Evaluate("({})"));
    oo::NotificationCenter::defaultCenter().post(
        kOOJavaScriptEngineWillResetNotificationName,
        OOJavaScriptEngine::sharedEngine());
    OO_CHECK(IsUndefined(definition->callback()));
    OO_CHECK(!IsObject(definition->callbackThis()));
  }
  // A definition that is gone no longer observes: another reset is harmless.
  oo::NotificationCenter::defaultCenter().post(
      kOOJavaScriptEngineWillResetNotificationName,
      OOJavaScriptEngine::sharedEngine());
  OO_CHECK(true);
}

OO_TEST_MAIN()
