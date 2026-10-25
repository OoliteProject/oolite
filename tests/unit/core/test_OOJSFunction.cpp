/*	test_OOJSFunction.mm
	Unit tests for OOJSFunction (src/Core/Scripting/OOJSFunction.h/.mm): bead oo-3smy, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056; amendment oo-ppc for
	the scripting files).

	OOJSFunction keeps a JS function alive (a GC root) for Objective-C code: the AI's scan
	predicates (ShipEntityAI) and the regular-expression tester (OORegExpMatcher). The test runs it
	in a real context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp) and links
	the game's own object for the class. What the rest of the engine would provide is defined below
	as the smallest stand-in that does the same thing (amendment oo-ppc item 6): the engine object
	(its global object), the script stack, the time limiter, the value converter and the string
	converter. The engine's and OOJSScript's headers are not imported, because the test defines
	those classes (amendment oo-z1s4 item 4). The expectations were written against the
	Objective-C class and run on it first; they pin: both initialisers (and when they answer nil),
	the name and the description, the function value, raw and object-wrapper evaluation (the
	script stack and the time limiter balanced around each call, the arguments converted), the
	predicate's truthiness, and what an engine reset does (commit 34d0592d1). They ran through the
	Objective-C facade until bead oo-9ht.41 deleted it; they now ask the C++ class with the same
	expectations. The facade's own contract (its description, identity and nil crossings) went
	with it (ADR-0049, standing approval oo-9n5p9). Bead oo-4aq6a.6.2 deleted the object-wrapper
	evaluation (evaluatePredicateWithContext() of Objective-C arguments and scope; no game caller):
	the case predicate and cxxAndFacade's predicate check retired with it (std-2026-10-19 item 2,
	ADR-0062 item 2), with the TestNumber object and the OOJSValueFromNativeObject() stand-in.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSFunction.h"
#include "oofnd/objc/OOObject.h"
#include "OODescription.h"
#include "OOTypes.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cstring>
#include <string>
#include <vector>


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
int sScriptDepth = 0;
int sScriptPushes = 0;
int sLimiterDepth = 0;
int sLimiterStarts = 0;
ooscript::Object sGlobal;
} // namespace

ooscript::Context gOOJSMainThreadContext = nullptr;
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


std::optional<std::string> cxx_OOStringFromJSString(ooscript::Context context, ooscript::String string)
{
	if (string == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, string, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);	// the test's strings are ASCII
	return result;
}


#ifndef NDEBUG
extern "C" void OOJSStartTimeLimiterWithTimeLimit_(OOTimeDelta, const char *, unsigned)  { sLimiterDepth++; sLimiterStarts++; }
extern "C" void OOJSStopTimeLimiter_(const char *, unsigned)  { sLimiterDepth--; }
#else
void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta)  { sLimiterDepth++; sLimiterStarts++; }
void OOJSStopTimeLimiter(void)  { sLimiterDepth--; }
#endif


// The engine (OOJavaScriptEngine.h; a C++ class since bead oo-wdqw1 deleted its facade), declared
// with the header's names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
	ooscript::Object globalObject();
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	static OOJavaScriptEngine *engine = new OOJavaScriptEngine;
	return engine;
}


ooscript::Object OOJavaScriptEngine::globalObject()
{
	return sGlobal;
}


#include "OOScript.h"


// OOJSScript (OOJSScript.h), which the code under test calls. Since bead oo-9ht.133 deleted the
// OOScript root's facade (a script's object since bead oo-9ht.137) a script is the C++ object, so
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


// Evaluates src in the global scope and gives the value.
ooscript::Value Evaluate(const char *src)
{
	ooscript::Value result = ooscript::undefinedValue();
	if (!ooscript::evaluateScript(Context(), sGlobal, src, static_cast<unsigned>(std::strlen(src)), "test.js", 1, &result))  ooscript::clearPendingException(Context());
	return result;
}


ooscript::Function FunctionFrom(const char *src)
{
	return ooscript::valueToFunction(Context(), Evaluate(src));
}


std::string String(ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return ooscript::isNull(value) ? "null" : "undefined";
	return cxx_OOStringFromJSString(Context(), ooscript::valueToString(Context(), value)).value_or("<none>");
}


oo::Ref<OOJSFunction> Compile(const char *name, const char *code, std::vector<const char *> args)
{
	return OOJSFunction::initWithName((name != nullptr ? std::optional<std::string>(name) : std::nullopt),
									  NULL,
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
		OO_CHECK(OOJSFunction::initWithFunction(NULL, Context()) == nullptr);

		ooscript::Function f = FunctionFrom("(function double(x) { return 2 * x; })");
		oo::Ref<OOJSFunction> function = OOJSFunction::initWithFunction(f, Context());
		OO_CHECK(function != nullptr);
		OO_CHECK(function->function() == f);
		OO_CHECK_EQ(function->name().value_or("<none>"), "double");
		OO_CHECK_EQ(function->descriptionComponents().value_or("<none>"), "double()");
		OO_CHECK(ooscript::isObject(function->functionValue()));
		OO_CHECK(ooscript::toObject(function->functionValue()) == ooscript::getFunctionObject(f));

		oo::Ref<OOJSFunction> anonymous = OOJSFunction::initWithFunction(FunctionFrom("(function () { return 1; })"), Context());
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
		ooscript::Value argv[2] = { ooscript::int32Value(2), ooscript::int32Value(3) };
		ooscript::Value result = ooscript::undefinedValue();
		OO_CHECK(function->evaluateWithContext(Context(), NULL, 2, argv, &result));
		OO_CHECK_EQ(String(result), "5");

		// No code, argument names missing, or a syntax error: nil.
		OO_CHECK(Compile("none", nullptr, {}) == nullptr);
		OO_CHECK(OOJSFunction::initWithName(std::string("x"), NULL, std::string("return 1;"), 1, NULL, std::nullopt, 0, Context()) == nullptr);
		OO_CHECK(Compile("bad", "return (;", {}) == nullptr);
		ooscript::clearPendingException(Context());

		// A NULL context: the main thread's is acquired and released.
		oo::Ref<OOJSFunction> withoutContext = OOJSFunction::initWithName(std::string("seven"), NULL, std::string("return 7;"), 0, NULL, std::nullopt, 0, NULL);
		OO_CHECK(withoutContext != nullptr);
		OO_CHECK(ooscript::isInRequest(Context()));
		OO_CHECK(withoutContext->evaluateWithContext(Context(), NULL, 0, NULL, &result));
		OO_CHECK_EQ(String(result), "7");

		// An empty body answers undefined.
		oo::Ref<OOJSFunction> empty = Compile("empty", "", {});
		OO_CHECK(empty->evaluateWithContext(Context(), NULL, 0, NULL, &result));
		OO_CHECK_EQ(String(result), "undefined");
	}
}


OO_TEST(evaluation)
{
	{
		oo::Ref<OOJSFunction> function = Compile("thisName", "return this.name + ':' + arguments.length;", {});
		Evaluate("globalThis.named = { name: 'n' }; globalThis.name = 'global';");
		ooscript::Value result = ooscript::undefinedValue();
		sScriptPushes = 0;
		sLimiterStarts = 0;
		OO_CHECK(function->evaluateWithContext(Context(), ooscript::toObject(Evaluate("named")), 0, NULL, &result));
		OO_CHECK_EQ(String(result), "n:0");
		OO_CHECK(function->evaluateWithContext(Context(), NULL, 0, NULL, &result));
		OO_CHECK_EQ(String(result), "global:0");	// no this: the global object (the function is not strict)
		OO_CHECK_EQ(sScriptPushes, 2);
		OO_CHECK_EQ(sLimiterStarts, 2);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);

		// A throwing function answers NO, with the stack and the limiter balanced.
		oo::Ref<OOJSFunction> thrower = Compile("thrower", "throw new Error('boom');", {});
		OO_CHECK(!thrower->evaluateWithContext(Context(), NULL, 0, NULL, &result));
		ooscript::clearPendingException(Context());
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);
	}
}


OO_TEST(engineReset)
{
	{
		oo::Ref<OOJSFunction> function = Compile("resettable", "return 1;", {});
		OO_CHECK(function->function() != NULL);
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, OOJavaScriptEngine::sharedEngine());
		OO_CHECK(function->function() == NULL);
		OO_CHECK(ooscript::isNull(function->functionValue()));
		OO_CHECK_EQ(function->name().value_or("<none>"), "resettable");	// the name stays
	}
}


OO_TEST(cxxAndFacade)
{
	{
		oo::Ref<OOJSFunction> function = OOJSFunction::initWithName(std::string("triple"), NULL, std::string("return 3 * x;"), 1, (const char *[]){ "x" }, std::nullopt, 0, Context());
		OO_CHECK(function != nullptr);
		OO_CHECK(OOJSFunction::initWithFunction(NULL, Context()) == nullptr);
		OO_CHECK(OOJSFunction::initWithName(std::string("bad"), NULL, std::string("return (;"), 0, NULL, std::nullopt, 0, Context()) == nullptr);
		ooscript::clearPendingException(Context());
		ooscript::Value argv[1] = { ooscript::int32Value(4) };
		ooscript::Value result = ooscript::undefinedValue();
		OO_CHECK(function->evaluateWithContext(Context(), NULL, 1, argv, &result));
		OO_CHECK_EQ(String(result), "12");
		OO_CHECK_EQ(function->descriptionComponents().value_or("<none>"), "triple()");
		OO_CHECK_EQ(function->name().value_or("<none>"), "triple");	// was asked of its facade
	}
}


OO_TEST_MAIN()
