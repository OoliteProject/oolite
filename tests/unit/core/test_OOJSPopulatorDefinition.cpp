/*	test_OOJSPopulatorDefinition.mm
	Unit tests for OOJSPopulatorDefinition (src/Core/Scripting/OOJSPopulatorDefinition.h/.mm):
	bead oo-1h0h, a Phase 3 conversion in the house style of the OOColor exemplar (proposed
	ADR-0056; amendment oo-o89, as its superclass, the weak-reference root, was still Objective-C).

	A populator definition keeps a JS callback and its `this` alive (GC roots) for the system
	populator, remembers the script that made it, and runs the callback with a location. The test
	runs it in a real context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp) and
	links the game's own objects for the class (its superclass, the weak-reference root, went with
	bead oo-9ht.22). What the rest of the engine would provide is defined below as the smallest stand-in
	that does the same thing: the engine object (which calls the function), the script stack
	(OOJSScript) and Vector3D (a plain array here). The engine's and OOJSScript's headers are not
	imported, because the test defines those classes (amendment oo-z1s4 item 4); the class's header
	names OOJSScript with @class for that (amendment oo-fg7i item 5). The expectations were written
	against the Objective-C class and run on it first (they now run through the facade, its
	forwarding test; the facade's own contract is checked last); they pin the initial state, the callback
	and its `this` (kept alive across a garbage collection), the run (its `this`, its location, the
	owning script pushed and popped), an engine reset, and the weak reference to a definition.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSPopulatorDefinition.h"
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


// A vector is the array [x, y, z] here: enough to see what the definition hands over.
extern "C" bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)
{
	ooscript::Value parts[3] = { ooscript::numberValue(vector.x), ooscript::numberValue(vector.y), ooscript::numberValue(vector.z) };
	ooscript::Object array = ooscript::newArrayObject(context, 3, parts);
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
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
	{
		Context();
		const oo::Ref<OOJSPopulatorDefinition> definition = oo::makeRef<OOJSPopulatorDefinition>();
		OO_CHECK(definition.get() != nullptr);
		OO_CHECK(ooscript::isUndefined(definition->callback()));
		OO_CHECK(definition->callbackThis() == NULL);
	}
}


OO_TEST(runCallback)
{
	{
		const oo::Ref<OOJSScript> owner = oo::makeRef<OOJSScript>();
		sRunningScript = owner.get();
		const oo::Ref<OOJSPopulatorDefinition> definition = oo::makeRef<OOJSPopulatorDefinition>();
		sRunningScript = nullptr;

		// Neither the function nor `this` has another reference: the definition keeps them alive.
		definition->setCallback(Evaluate("(function (where) { globalThis.ran = this.tag + ':' + where.join(); })"));
		definition->setCallbackThis(ooscript::toObject(Evaluate("({ tag: 'me' })")));
		OO_CHECK(ooscript::isObject(definition->callback()));
		OO_CHECK(definition->callbackThis() != NULL);
		ooscript::gc(Context());

		sPushed.clear();
		sCalls = 0;
		definition->runPopulatorCallback(make_HPvector(1, 2.5, -3));
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "me:1,2.5,-3");
		OO_CHECK_EQ(sCalls, 1);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == owner.get());	// the script that made it

		// Replacing the callback: the new one runs.
		definition->setCallback(Evaluate("(function () { globalThis.ran = 'second'; })"));
		definition->runPopulatorCallback(make_HPvector(0, 0, 0));
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "second");

		// A definition made with no running script pushes nil.
		const oo::Ref<OOJSPopulatorDefinition> orphan = oo::makeRef<OOJSPopulatorDefinition>();
		orphan->setCallback(Evaluate("(function () { globalThis.ran = 'orphan'; })"));
		sPushed.clear();
		orphan->runPopulatorCallback(make_HPvector(0, 0, 0));
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "orphan");
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == nullptr);
	}
}


OO_TEST(engineReset)
{
	{
		const oo::Ref<OOJSPopulatorDefinition> definition = oo::makeRef<OOJSPopulatorDefinition>();
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


OO_TEST(weakReference)
{
	oo::WeakRef<OOJSPopulatorDefinition> reference;
	{
		oo::Ref<OOJSPopulatorDefinition> definition = oo::makeRef<OOJSPopulatorDefinition>();
		reference = definition;
		OO_CHECK(reference.lock().get() == definition.get());
	}
	OO_CHECK(!reference.lock());
}


OO_TEST(plistCarrier)
{
	const oo::Ref<OOJSPopulatorDefinition> definition = oo::makeRef<OOJSPopulatorDefinition>();
	const oo::PList node = OOJSPopulatorDefinitionToPList(definition);
	OO_CHECK(node.isObject());
	OO_CHECK(OOJSPopulatorDefinitionIn(node) == definition.get());
	OO_CHECK(OOJSPopulatorDefinitionIn(oo::PList()) == nullptr);
	OO_CHECK(OOJSPopulatorDefinitionToPList(nullptr).isNull());
}


OO_TEST_MAIN()
