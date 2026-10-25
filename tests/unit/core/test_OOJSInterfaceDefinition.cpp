/*	test_OOJSInterfaceDefinition.mm
	Unit tests for OOJSInterfaceDefinition (src/Core/Scripting/OOJSInterfaceDefinition.h/.mm):
	bead oo-8fpc, a Phase 3 conversion in the house style of the OOColor exemplar (proposed
	ADR-0056; amendment oo-o89, as its superclass, the weak-reference root, was still Objective-C).

	An interface definition is a station's F4 interface entry made by a script: a title, category
	and summary, and a JS callback and its `this` that it keeps alive (GC roots) and runs with the
	entry's key, pushing the script that made it. The test runs it in a real context on the game's
	own façade backend (ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the
	class (the script's weak reference was the weak-reference class until bead oo-9ht.22). What the rest of the engine would
	provide is defined below as the smallest stand-in that does the same thing: the engine object
	(which calls the function), the script stack (OOJSScript) and the property-list converter. The
	engine's and OOJSScript's headers are not imported, because the test defines those classes
	(amendment oo-z1s4 item 4); the class's header names OOScript with @class for that (amendment
	oo-fg7i item 5). The expectations were written against the Objective-C class and run on it
	first; since bead oo-9ht.61 deleted the façade (a weak-reference root subclass) they ask the C++ class. They
	pin the initial state and the text properties, the callback and its `this` (kept alive across a
	garbage collection), the run, the sort order (interfaceCompare(), with its null cases) and an
	engine reset.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSInterfaceDefinition.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstring>
#include <string>
#include <vector>


// MARK: What the rest of the engine provides ------------------------------------------------------

class OOJSScript;

namespace {
ooscript::Object sGlobal;
std::vector<OOJSScript *> sPushed;
int sScriptDepth = 0;
int sCalls = 0;
} // namespace

ooscript::Context gOOJSMainThreadContext = nullptr;
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


// A property list as JS, as far as the definition hands one over: a string.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	const std::string *string = plist.getIf<std::string>();
	if (string == nullptr)  return ooscript::nullValue();
	return ooscript::stringValue(ooscript::newStringCopyN(context, string->data(), string->size()));
}


// The engine (OOJavaScriptEngine.h; a C++ class since bead oo-wdqw1 deleted its facade), declared
// with the header's names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	bool callJSFunction(ooscript::Value function, ooscript::Object jsThis, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult);
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}


bool OOJavaScriptEngine::callJSFunction(ooscript::Value function, ooscript::Object jsThis, unsigned argc, ooscript::Value *argv, ooscript::Value *outResult)
{
	sCalls++;
	bool OK = ooscript::callFunctionValue(gOOJSMainThreadContext, jsThis, function, argc, argv, outResult);
	if (!OK)  ooscript::clearPendingException(gOOJSMainThreadContext);
	return OK;
}


// The script stack: the running script (set by the test) and what was pushed.
namespace {
OOJSScript *sRunningScript = nullptr;
} // namespace


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since bead oo-9ht.133 deleted the
// OOScript root's facade (a script's object since bead oo-9ht.137) a script is the C++ object, so
// the stand-in is a C++ subclass of OOScript declaring the members that code calls.
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
bool OOScript::callMethod(ooscript::PropertyId, ooscript::Context, ooscript::Value *, int, ooscript::Value *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
ooscript::Value OOScript::jsValueInContext(ooscript::Context)	{ return ooscript::undefinedValue(); }
void OOScript::clearJSSelf(ooscript::Object)					{}

OOJSScript *OOJSScript::currentlyRunningScript()  { return sRunningScript; }
void OOJSScript::pushScript(const oo::WeakRef<OOJSScript> &script)  { sPushed.push_back(script.get()); sScriptDepth++; }
void OOJSScript::popScript(OOJSScript *script)  { (void)script; sScriptDepth--; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Context Context()
{
	if (gOOJSMainThreadContext == nullptr)
	{
		ooscript::Runtime runtime = ooscript::newRuntime(8u * 1024u * 1024u);
		gOOJSMainThreadContext = ooscript::newContext(runtime, 8192);
		ooscript::beginRequest(gOOJSMainThreadContext);
		sGlobal = ooscript::getGlobalObject(gOOJSMainThreadContext);
		ooscript::initStandardClasses(gOOJSMainThreadContext, sGlobal);
	}
	return gOOJSMainThreadContext;
}


ooscript::Value Evaluate(const char *src)
{
	ooscript::Value result = ooscript::undefinedValue();
	if (!ooscript::evaluateScript(Context(), sGlobal, src, static_cast<unsigned>(std::strlen(src)), "test.js", 1, &result))  ooscript::clearPendingException(Context());
	return result;
}


std::string String(ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return ooscript::isNull(value) ? "null" : "undefined";
	ooscript::String str = ooscript::valueToString(Context(), value);
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(Context(), str, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);
	return result;
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(initialState)
{
	Context();
	const oo::Ref<OOJSInterfaceDefinition> definition = oo::makeRef<OOJSInterfaceDefinition>();
	OO_CHECK(definition != nullptr);
	OO_CHECK(ooscript::isUndefined(definition->callback()));
	OO_CHECK(definition->callbackThis() == NULL);
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


OO_TEST(runCallback)
{
	{
		const oo::Ref<OOJSScript> owner = oo::makeRef<OOJSScript>();
		sRunningScript = owner.get();
		const oo::Ref<OOJSInterfaceDefinition> definition = oo::makeRef<OOJSInterfaceDefinition>();
		sRunningScript = nullptr;

		// Neither the function nor `this` has another reference: the definition keeps them alive.
		definition->setCallback(Evaluate("(function (key) { globalThis.ran = this.tag + ':' + key + ':' + arguments.length; })"));
		definition->setCallbackThis(ooscript::toObject(Evaluate("({ tag: 'me' })")));
		OO_CHECK(ooscript::isObject(definition->callback()));
		OO_CHECK(definition->callbackThis() != NULL);
		ooscript::gc(Context());

		sPushed.clear();
		sCalls = 0;
		definition->runCallback("dock");
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "me:dock:1");
		OO_CHECK_EQ(sCalls, 1);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == owner.get());	// the script that made it

		// Replacing the callback and `this`: the new ones run.
		definition->setCallback(Evaluate("(function (key) { globalThis.ran = 'second ' + key + ' ' + (this === globalThis); })"));
		definition->setCallbackThis(NULL);
		definition->runCallback("k");
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "second k true");
	}
}


namespace {
oo::Ref<OOJSInterfaceDefinition> Interface(std::optional<std::string> category, std::optional<std::string> title)
{
	const oo::Ref<OOJSInterfaceDefinition> definition = oo::makeRef<OOJSInterfaceDefinition>();
	if (category.has_value())  definition->setCategory(*category);
	definition->setTitle(title);
	return definition;
}
} // namespace


OO_TEST(interfaceCompare)
{
	// By category, then by title, ignoring case.
	OO_CHECK_EQ(Interface("alpha", "z")->interfaceCompare(Interface("Beta", "a").get()), OOOrderedAscending);
	OO_CHECK_EQ(Interface("beta", "a")->interfaceCompare(Interface("ALPHA", "z").get()), OOOrderedDescending);
	OO_CHECK_EQ(Interface("same", "apple")->interfaceCompare(Interface("SAME", "Banana").get()), OOOrderedAscending);
	OO_CHECK_EQ(Interface("same", "Banana")->interfaceCompare(Interface("same", "apple").get()), OOOrderedDescending);
	OO_CHECK_EQ(Interface("same", "x")->interfaceCompare(Interface("same", "X").get()), OOOrderedSame);
	// No category of its own: the same category as anything (a message to nil); then the titles.
	OO_CHECK_EQ(Interface(std::nullopt, "b")->interfaceCompare(Interface("cat", "a").get()), OOOrderedDescending);
	// The other's missing category or title is the empty string.
	OO_CHECK_EQ(Interface("cat", "a")->interfaceCompare(Interface(std::nullopt, "a").get()), OOOrderedDescending);
	OO_CHECK_EQ(Interface("", "a")->interfaceCompare(Interface(std::nullopt, std::nullopt).get()), OOOrderedDescending);
	OO_CHECK_EQ(Interface("", std::nullopt)->interfaceCompare(Interface(std::nullopt, "a").get()), OOOrderedSame);
	// Null: its category and title are missing.
	OO_CHECK_EQ(Interface("cat", "a")->interfaceCompare(nullptr), OOOrderedDescending);
}


OO_TEST(engineReset)
{
	{
		const oo::Ref<OOJSInterfaceDefinition> definition = oo::makeRef<OOJSInterfaceDefinition>();
		definition->setCallback(Evaluate("(function () {})"));
		definition->setCallbackThis(ooscript::toObject(Evaluate("({})")));
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
		OO_CHECK(ooscript::isUndefined(definition->callback()));
		OO_CHECK(definition->callbackThis() == NULL);
	}
	// A definition that is gone no longer observes: another reset is harmless.
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
	OO_CHECK(true);
}


OO_TEST_MAIN()
