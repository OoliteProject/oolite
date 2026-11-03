/*	test_OOJSGuiScreenKeyDefinition.mm
	Unit tests for OOJSGuiScreenKeyDefinition (src/Core/Scripting/OOJSGuiScreenKeyDefinition.h/.mm):
	bead oo-xg7g, a Phase 3 conversion in the house style of the OOColor exemplar (proposed
	ADR-0056; amendment oo-o89, as its superclass, the weak-reference root, was still Objective-C).

	A GUI screen key definition is a script's extra keys for a GUI screen: a name and the keys it
	registers, and a JS callback and its `this` that it keeps alive (owned references) and runs with the
	entry's key, pushing the script that made it. The test runs it in a real QuickJS-ng context
	and links the game's own objects for the
	class (the script's weak reference was the weak-reference class). What the rest of the engine would
	provide is defined below as the smallest stand-in that does the same thing: the engine object
	(which calls the function), the script stack (OOJSScript) and the property-list converter. The
	engine's and OOJSScript's headers are not imported, because the test defines those classes
	(amendment oo-z1s4 item 4); the class's header names OOScript with @class for that (amendment
	oo-fg7i item 5). The expectations were written against the Objective-C class and run on it
	first; since the façade (a weak-reference root subclass) was deleted they ask the C++ class. They
	pin the initial state, the name and the keys, the callback and its `this` (kept alive across a
	garbage collection), the run, the sort order (interfaceCompare(), with its null cases) and an
	engine reset.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSGuiScreenKeyDefinition.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <quickjs.h>

#include <cstring>
#include <string>
#include <vector>


// MARK: What the rest of the engine provides ------------------------------------------------------

class OOJSScript;

namespace {
std::vector<OOJSScript *> sPushed;
int sScriptDepth = 0;
int sCalls = 0;
} // namespace

JSContext *gOOJSMainThreadContext = nullptr;
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


// A property list as JS, as far as the definition hands one over: a string.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	const std::string *string = plist.getIf<std::string>();
	if (string == nullptr)  return JS_NULL;
	return JS_NewStringLen(context, string->data(), string->size());
}


// The engine (OOJavaScriptEngine.h; a C++ class since its facade was deleted), declared with the
// header's names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	bool callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult);
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}


// As the engine's: the call, its result owned by the caller, and an exception reported (here,
// dropped) and cleared.
bool OOJavaScriptEngine::callJSFunction(JSValueConst function, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *outResult)
{
	sCalls++;
	JSContext *context = gOOJSMainThreadContext;
	JSValue result = JS_Call(context, function, jsThis, argc, argv);
	if (JS_IsException(result))
	{
		JS_FreeValue(context, JS_GetException(context));
		if (outResult != NULL)  *outResult = JS_UNDEFINED;
		return NO;
	}
	if (outResult != NULL)  *outResult = result;
	else  JS_FreeValue(context, result);
	return YES;
}


// The script stack: the running script (set by the test) and what was pushed.
namespace {
OOJSScript *sRunningScript = nullptr;
} // namespace


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. A script is the C++ object (the
// OOScript root's facade was deleted), so the stand-in is a C++ subclass of OOScript declaring the
// members that code calls.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	static void pushScript(const oo::WeakRef<OOJSScript> &script);
	static void popScript(OOJSScript *script);
};

// OOScript's virtual members (OOScript.mm reaches the whole game), for the test's scripts' vtable.
std::optional<std::string> OOScript::descriptionComponents()	{ return std::nullopt; }
std::optional<std::string> OOScript::name()					{ return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription()		{ return std::nullopt; }
std::optional<std::string> OOScript::version()				{ return std::nullopt; }
bool OOScript::requiresTickle()								{ return false; }
void OOScript::runWithTarget(Entity *)						{}
bool OOScript::callMethod(JSAtom, JSContext *, JSValueConst *, int, JSValue *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
JSValue OOScript::jsValueInContext(JSContext *)				{ return JS_UNDEFINED; }
void OOScript::clearJSSelf(JSValueConst)						{}

OOJSScript *OOJSScript::currentlyRunningScript()  { return sRunningScript; }
void OOJSScript::pushScript(const oo::WeakRef<OOJSScript> &script)  { sPushed.push_back(script.get()); sScriptDepth++; }
void OOJSScript::popScript(OOJSScript *script)  { (void)script; sScriptDepth--; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSContext *Context()
{
	if (gOOJSMainThreadContext == nullptr)
	{
		JSRuntime *runtime = JS_NewRuntime();
		JS_SetMemoryLimit(runtime, 8u * 1024u * 1024u);
		gOOJSMainThreadContext = JS_NewContext(runtime);
	}
	return gOOJSMainThreadContext;
}


// An owned value, freed when it goes: what Evaluate() gives, so that a value handed to the
// definition has no other reference once the statement ends.
class Owned
{
public:
	explicit Owned(JSValue value): _value(value) {}
	~Owned()  { JS_FreeValue(Context(), _value); }
	Owned(const Owned &) = delete;
	Owned &operator=(const Owned &) = delete;
	operator JSValueConst() const  { return _value; }

private:
	JSValue _value;
};


Owned Evaluate(const char *src)
{
	JSValue result = JS_Eval(Context(), src, std::strlen(src), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(Context(), JS_GetException(Context()));
		result = JS_UNDEFINED;
	}
	return Owned(result);
}


std::string String(JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return JS_IsNull(value) ? "null" : "undefined";
	std::size_t length = 0;
	const char *chars = JS_ToCStringLen(Context(), &length, value);
	if (chars == nullptr)  return "<none>";
	std::string result(chars, length);
	JS_FreeCString(Context(), chars);
	return result;
}


// Whether an owned value (what -callback and -callbackThis answer) is undefined, or an object;
// the value is freed.
bool IsUndefined(JSValue value)
{
	bool result = JS_IsUndefined(value);
	JS_FreeValue(Context(), value);
	return result;
}


bool IsObject(JSValue value)
{
	bool result = JS_IsObject(value);
	JS_FreeValue(Context(), value);
	return result;
}


void CollectGarbage()
{
	JS_RunGC(JS_GetRuntime(Context()));
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(initialState)
{
	Context();
	const oo::Ref<OOJSGuiScreenKeyDefinition> definition = oo::makeRef<OOJSGuiScreenKeyDefinition>();
	OO_CHECK(definition != nullptr);
	OO_CHECK(IsUndefined(definition->callback()));
	OO_CHECK(!IsObject(definition->callbackThis()));
	OO_CHECK(!definition->name().has_value());
	OO_CHECK(definition->registerKeys().isNull());
	definition->setName(std::string("Name"));
	oo::PList::Dict keys;
	keys["key_a"] = oo::PList(std::string("a"));
	definition->setRegisterKeys(oo::PList(std::move(keys)));
	OO_CHECK_EQ(definition->name().value_or("<none>"), "Name");
	OO_CHECK(definition->registerKeys().isDict() && definition->registerKeys().count() == 1);
	definition->setName(std::nullopt);
	OO_CHECK(!definition->name().has_value());
}


OO_TEST(runCallback)
{
	{
		const oo::Ref<OOJSScript> owner = oo::makeRef<OOJSScript>();
		sRunningScript = owner.get();
		const oo::Ref<OOJSGuiScreenKeyDefinition> definition = oo::makeRef<OOJSGuiScreenKeyDefinition>();
		sRunningScript = nullptr;

		// Neither the function nor `this` has another reference: the definition keeps them alive.
		definition->setCallback(Evaluate("(function (key) { globalThis.ran = this.tag + ':' + key + ':' + arguments.length; })"));
		definition->setCallbackThis(Evaluate("({ tag: 'me' })"));
		OO_CHECK(IsObject(definition->callback()));
		OO_CHECK(IsObject(definition->callbackThis()));
		CollectGarbage();

		sPushed.clear();
		sCalls = 0;
		definition->runCallback("key_a");
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "me:key_a:1");
		OO_CHECK_EQ(sCalls, 1);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == owner.get());	// the script that made it

		// Replacing the callback and `this`: the new ones run.
		definition->setCallback(Evaluate("(function (key) { globalThis.ran = 'second ' + key + ' ' + (this === globalThis); })"));
		definition->setCallbackThis(JS_UNDEFINED);
		definition->runCallback("k");
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "second k true");
	}
}


namespace {
oo::Ref<OOJSGuiScreenKeyDefinition> Keys(std::optional<std::string> name)
{
	const oo::Ref<OOJSGuiScreenKeyDefinition> definition = oo::makeRef<OOJSGuiScreenKeyDefinition>();
	definition->setName(name);
	return definition;
}
} // namespace


OO_TEST(interfaceCompare)
{
	// By name, ignoring case.
	OO_CHECK_EQ(Keys("apple")->interfaceCompare(Keys("Banana").get()), OOOrderedAscending);
	OO_CHECK_EQ(Keys("banana")->interfaceCompare(Keys("APPLE").get()), OOOrderedDescending);
	OO_CHECK_EQ(Keys("same")->interfaceCompare(Keys("SAME").get()), OOOrderedSame);
	// No name of its own: the same as anything (a message to nil); the other's missing name is
	// the empty string, as is null's.
	OO_CHECK_EQ(Keys(std::nullopt)->interfaceCompare(Keys("a").get()), OOOrderedSame);
	OO_CHECK_EQ(Keys("a")->interfaceCompare(Keys(std::nullopt).get()), OOOrderedDescending);
	OO_CHECK_EQ(Keys("")->interfaceCompare(Keys(std::nullopt).get()), OOOrderedSame);
	OO_CHECK_EQ(Keys("a")->interfaceCompare(nullptr), OOOrderedDescending);
}


OO_TEST(engineReset)
{
	{
		const oo::Ref<OOJSGuiScreenKeyDefinition> definition = oo::makeRef<OOJSGuiScreenKeyDefinition>();
		definition->setCallback(Evaluate("(function () {})"));
		definition->setCallbackThis(Evaluate("({})"));
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
		OO_CHECK(IsUndefined(definition->callback()));
		OO_CHECK(!IsObject(definition->callbackThis()));
	}
	// A definition that is gone no longer observes: another reset is harmless.
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
	OO_CHECK(true);
}


OO_TEST_MAIN()
