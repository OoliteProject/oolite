/*	test_OOJSFunction.mm
	Unit tests for OOJSFunction (src/Core/Scripting/OOJSFunction.h/.mm): bead oo-3smy, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056; amendment oo-ppc for
	the scripting files).

	OOJSFunction keeps a JS function alive (a reference it owns) for Objective-C code: the AI's scan
	predicates (ShipEntityAI) and the regular-expression tester (OORegExpMatcher). The test runs it
	in a real QuickJS-ng context and links the game's own object for the class. What the rest of
	the engine would provide is defined below as the smallest stand-in that does the same thing
	(amendment oo-ppc item 6): the engine object (the sender of its reset notification), the script
	stack, the time limiter, the value converter, the string converter and the pending-exception
	reporter. The engine's and OOJSScript's headers are not imported, because the test defines
	those classes (amendment oo-z1s4 item 4). The expectations were written against the
	Objective-C class and run on it first; they pin: both initialisers (and when they answer nil),
	the name and the description, the function value, raw and object-wrapper evaluation (the
	script stack and the time limiter balanced around each call, the arguments converted), the
	predicate's truthiness, and what an engine reset does (commit 34d0592d1). They ran through the
	Objective-C facade until it was deleted; they now ask the C++ class with the same
	expectations. The facade's own contract (its description, identity and nil crossings) went
	with it. The object-wrapper evaluation (evaluatePredicateWithContext() of Objective-C
	arguments and scope; no game caller) is gone: the case predicate and cxxAndFacade's predicate
	check retired with it, with the TestNumber object and the OOJSValueFromNativeObject() stand-in.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSFunction.h"
#include "oofnd/objc/OOObject.h"
#include "OODescription.h"
#include "OOTypes.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <quickjs.h>

#include <cstring>
#include <string>
#include <vector>


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
int sScriptDepth = 0;
int sScriptPushes = 0;
int sLimiterDepth = 0;
int sLimiterStarts = 0;
} // namespace

JSContext *gOOJSMainThreadContext = nullptr;
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


std::optional<std::string> cxx_OOStringFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return std::nullopt;
	std::size_t length = 0;
	const char *chars = JS_ToCStringLen(context, &length, value);
	if (chars == nullptr)
	{
		JS_FreeValue(context, JS_GetException(context));
		return std::nullopt;
	}
	std::string result(chars, length);
	JS_FreeCString(context, chars);
	return result;
}


// As the engine's: the pending exception is reported (here, dropped) and cleared.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta)  { sLimiterDepth++; sLimiterStarts++; }
void OOJSStopTimeLimiter(void)  { sLimiterDepth--; }


// The engine (OOJavaScriptEngine.h; a C++ class since its facade was deleted), declared with the
// header's names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since the OOScript root's facade (a
// script's object once the OOJSScript facade went) is deleted, a script is the C++ object, so
// the stand-in is a C++ subclass of OOScript declaring the members that code calls.
class OOJSScript : public OOScript
{
public:
	static void pushScript(OOJSScript *script);
	static void popScript(OOJSScript *script);
};

void OOJSScript::pushScript(OOJSScript *script)  { (void)script; sScriptDepth++; sScriptPushes++; }
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


// Evaluates src in the global scope and gives the value, owned (undefined if it threw).
JSValue Evaluate(const char *src)
{
	JSValue result = JS_Eval(Context(), src, std::strlen(src), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(Context(), JS_GetException(Context()));
		return JS_UNDEFINED;
	}
	return result;
}


// The value as a string ("undefined", "null", ...); frees the value.
std::string String(JSValue value)
{
	std::string result;
	if (JS_IsNull(value) || JS_IsUndefined(value))  result = JS_IsNull(value) ? "null" : "undefined";
	else  result = cxx_OOStringFromJSValue(Context(), value).value_or("<none>");
	JS_FreeValue(Context(), value);
	return result;
}


// Whether two values are the same object (identity, as the object pointers were compared).
bool SameObject(JSValueConst a, JSValueConst b)
{
	return JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) == JS_VALUE_GET_PTR(b);
}


oo::Ref<OOJSFunction> Compile(const char *name, const char *code, std::vector<const char *> args)
{
	return OOJSFunction::initWithName((name != nullptr ? std::optional<std::string>(name) : std::nullopt),
									  JS_UNDEFINED,
									  (code != nullptr ? std::optional<std::string>(code) : std::nullopt),
									  args.size(),
									  (args.empty() ? NULL : args.data()),
									  std::string("test.js"),
									  1,
									  Context());
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(initWithFunction)
{
	{
		OO_CHECK(OOJSFunction::initWithFunction(JS_NULL, Context()) == nullptr);

		JSValue f = Evaluate("(function double(x) { return 2 * x; })");
		oo::Ref<OOJSFunction> function = OOJSFunction::initWithFunction(f, Context());
		OO_CHECK(function != nullptr);
		OO_CHECK(SameObject(function->function(), f));
		OO_CHECK_EQ(function->name().value_or("<none>"), "double");
		OO_CHECK_EQ(function->descriptionComponents().value_or("<none>"), "double()");
		JSValue functionValue = function->functionValue();
		OO_CHECK(JS_IsObject(functionValue));
		OO_CHECK(SameObject(functionValue, f));
		JS_FreeValue(Context(), functionValue);
		JS_FreeValue(Context(), f);

		JSValue anonymousFunction = Evaluate("(function () { return 1; })");
		oo::Ref<OOJSFunction> anonymous = OOJSFunction::initWithFunction(anonymousFunction, Context());
		JS_FreeValue(Context(), anonymousFunction);
		OO_CHECK(!anonymous->name().has_value());
		OO_CHECK_EQ(anonymous->descriptionComponents().value_or("<none>"), "<anonymous>()");
	}
}


OO_TEST(initWithName)
{
	{
		oo::Ref<OOJSFunction> function = Compile("add", "return a + b;", { "a", "b" });
		OO_CHECK(function != nullptr);
		OO_CHECK_EQ(function->name().value_or("<none>"), "add");
		JSValueConst argv[2] = { JS_NewInt32(Context(), 2), JS_NewInt32(Context(), 3) };
		JSValue result = JS_UNDEFINED;
		OO_CHECK(function->evaluateWithContext(Context(), JS_UNDEFINED, 2, argv, &result));
		OO_CHECK_EQ(String(result), "5");

		// No code, argument names missing, or a syntax error: nil.
		OO_CHECK(Compile("none", nullptr, {}) == nullptr);
		OO_CHECK(OOJSFunction::initWithName(std::string("x"), JS_UNDEFINED, std::string("return 1;"), 1, NULL, std::nullopt, 0, Context()) == nullptr);
		OO_CHECK(Compile("bad", "return (;", {}) == nullptr);
		JS_FreeValue(Context(), JS_GetException(Context()));

		// A NULL context: the main thread's is acquired and released.
		oo::Ref<OOJSFunction> withoutContext = OOJSFunction::initWithName(std::string("seven"), JS_UNDEFINED, std::string("return 7;"), 0, NULL, std::nullopt, 0, NULL);
		OO_CHECK(withoutContext != nullptr);
		OO_CHECK(withoutContext->evaluateWithContext(Context(), JS_UNDEFINED, 0, NULL, &result));
		OO_CHECK_EQ(String(result), "7");

		// An empty body answers undefined.
		oo::Ref<OOJSFunction> empty = Compile("empty", "", {});
		OO_CHECK(empty->evaluateWithContext(Context(), JS_UNDEFINED, 0, NULL, &result));
		OO_CHECK_EQ(String(result), "undefined");
	}
}


OO_TEST(evaluation)
{
	{
		oo::Ref<OOJSFunction> function = Compile("thisName", "return this.name + ':' + arguments.length;", {});
		JS_FreeValue(Context(), Evaluate("globalThis.named = { name: 'n' }; globalThis.name = 'global';"));
		JSValue result = JS_UNDEFINED;
		sScriptPushes = 0;
		sLimiterStarts = 0;
		JSValue named = Evaluate("named");
		OO_CHECK(function->evaluateWithContext(Context(), named, 0, NULL, &result));
		JS_FreeValue(Context(), named);
		OO_CHECK_EQ(String(result), "n:0");
		OO_CHECK(function->evaluateWithContext(Context(), JS_UNDEFINED, 0, NULL, &result));
		OO_CHECK_EQ(String(result), "global:0");	// no this: the global object (the function is not strict)
		OO_CHECK_EQ(sScriptPushes, 2);
		OO_CHECK_EQ(sLimiterStarts, 2);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);

		// A throwing function answers NO, with the stack and the limiter balanced.
		oo::Ref<OOJSFunction> thrower = Compile("thrower", "throw new Error('boom');", {});
		OO_CHECK(!thrower->evaluateWithContext(Context(), JS_UNDEFINED, 0, NULL, &result));
		JS_FreeValue(Context(), JS_GetException(Context()));
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);
	}
}


OO_TEST(engineReset)
{
	{
		oo::Ref<OOJSFunction> function = Compile("resettable", "return 1;", {});
		OO_CHECK(!JS_IsNull(function->function()));
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
		OO_CHECK(JS_IsNull(function->function()));
		OO_CHECK(JS_IsNull(function->functionValue()));
		OO_CHECK_EQ(function->name().value_or("<none>"), "resettable");	// the name stays
	}
}


OO_TEST(cxxAndFacade)
{
	{
		oo::Ref<OOJSFunction> function = OOJSFunction::initWithName(std::string("triple"), JS_UNDEFINED, std::string("return 3 * x;"), 1, (const char *[]){ "x" }, std::nullopt, 0, Context());
		OO_CHECK(function != nullptr);
		OO_CHECK(OOJSFunction::initWithFunction(JS_NULL, Context()) == nullptr);
		OO_CHECK(OOJSFunction::initWithName(std::string("bad"), JS_UNDEFINED, std::string("return (;"), 0, NULL, std::nullopt, 0, Context()) == nullptr);
		JS_FreeValue(Context(), JS_GetException(Context()));
		JSValueConst argv[1] = { JS_NewInt32(Context(), 4) };
		JSValue result = JS_UNDEFINED;
		OO_CHECK(function->evaluateWithContext(Context(), JS_UNDEFINED, 1, argv, &result));
		OO_CHECK_EQ(String(result), "12");
		OO_CHECK_EQ(function->descriptionComponents().value_or("<none>"), "triple()");
		OO_CHECK_EQ(function->name().value_or("<none>"), "triple");	// was asked of its facade
	}
}


OO_TEST_MAIN()
