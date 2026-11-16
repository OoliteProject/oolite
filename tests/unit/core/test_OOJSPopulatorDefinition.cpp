/*	test_OOJSPopulatorDefinition.mm
	Unit tests for OOJSPopulatorDefinition (src/Core/Scripting/OOJSPopulatorDefinition.h/.mm).

	A populator definition keeps a JS callback and its `this` alive (owned references) for the
	system populator, remembers the script that made it, and runs the callback with a location. The
	test runs it in a real QuickJS-ng context and links the game's own objects for the class. What
	the rest of the engine would provide is defined below as the smallest stand-in that does the
	same thing: the engine object (which calls the function), the script stack (OOJSScript) and
	Vector3D (a plain array here). The engine's and OOJSScript's headers are not imported, because
	the test defines those classes; the class's header names OOJSScript with @class for that. The tests pin the
	initial state, the callback and its `this` (kept alive across a garbage collection), the run
	(its `this`, its location, the owning script pushed and popped), an engine reset, and the weak
	reference to a definition. Run: tests/run.sh unit
*/

#include "OOJSPopulatorDefinition.h"
#include "oofnd/Notification.hpp"

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


// A vector is the array [x, y, z] here: enough to see what the definition hands over.
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	JS_SetPropertyUint32(context, array, 0, JS_NewFloat64(context, vector.x));
	JS_SetPropertyUint32(context, array, 1, JS_NewFloat64(context, vector.y));
	JS_SetPropertyUint32(context, array, 2, JS_NewFloat64(context, vector.z));
	*outValue = array;
	return true;
}


// The engine (OOJavaScriptEngine.h), declared with the header's names and
// signatures but not its class; the stand-in's answers are kept.
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
		return false;
	}
	if (outResult != NULL)  *outResult = result;
	else  JS_FreeValue(context, result);
	return true;
}


// The script stack: the running script (set by the test) and what was pushed.
namespace {
OOJSScript *sRunningScript = nullptr;
} // namespace


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. A script is a C++
// object, so the stand-in is a C++ subclass of OOScript declaring the members
// that code calls.
class OOJSScript : public OOScript
{
public:
	static OOJSScript *currentlyRunningScript();
	static void pushScript(const std::weak_ptr<OOJSScript> &script);
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
void OOJSScript::pushScript(const std::weak_ptr<OOJSScript> &script)  { sPushed.push_back(script.lock().get()); sScriptDepth++; }
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
	{
		Context();
		const std::shared_ptr<OOJSPopulatorDefinition> definition = oo::makeShared<OOJSPopulatorDefinition>();
		OO_CHECK(definition.get() != nullptr);
		OO_CHECK(IsUndefined(definition->callback()));
		OO_CHECK(!IsObject(definition->callbackThis()));
	}
}


OO_TEST(runCallback)
{
	{
		const std::shared_ptr<OOJSScript> owner = oo::makeShared<OOJSScript>();
		sRunningScript = owner.get();
		const std::shared_ptr<OOJSPopulatorDefinition> definition = oo::makeShared<OOJSPopulatorDefinition>();
		sRunningScript = nullptr;

		// Neither the function nor `this` has another reference: the definition keeps them alive.
		definition->setCallback(Evaluate("(function (where) { globalThis.ran = this.tag + ':' + where.join(); })"));
		definition->setCallbackThis(Evaluate("({ tag: 'me' })"));
		OO_CHECK(IsObject(definition->callback()));
		OO_CHECK(IsObject(definition->callbackThis()));
		CollectGarbage();

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
		const std::shared_ptr<OOJSPopulatorDefinition> orphan = oo::makeShared<OOJSPopulatorDefinition>();
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
		const std::shared_ptr<OOJSPopulatorDefinition> definition = oo::makeShared<OOJSPopulatorDefinition>();
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


OO_TEST(weakReference)
{
	std::weak_ptr<OOJSPopulatorDefinition> reference;
	{
		std::shared_ptr<OOJSPopulatorDefinition> definition = oo::makeShared<OOJSPopulatorDefinition>();
		reference = definition;
		OO_CHECK(reference.lock().get() == definition.get());
	}
	OO_CHECK(!reference.lock());
}


OO_TEST(plistCarrier)
{
	const std::shared_ptr<OOJSPopulatorDefinition> definition = oo::makeShared<OOJSPopulatorDefinition>();
	const oo::PList node = OOJSPopulatorDefinitionToPList(definition);
	OO_CHECK(node.isObject());
	OO_CHECK(OOJSPopulatorDefinitionIn(node) == definition.get());
	OO_CHECK(OOJSPopulatorDefinitionIn(oo::PList()) == nullptr);
	OO_CHECK(OOJSPopulatorDefinitionToPList(nullptr).isNull());
}


OO_TEST_MAIN()
