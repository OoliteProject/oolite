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
	predicate's truthiness, and what an engine reset does (commit 34d0592d1). They now run through
	the facade, which is its forwarding test; the C++ API and the facade's contract (identity, nil)
	are checked after them.
	Run: bash tools/check-core-tests.sh
*/

#import "OOJSFunction.h"
#import "oofnd/objc/OOObject.h"
#import "OODescription.h"
#import "OOTypes.h"
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


// An object that converts to a JS number (its value), as a wrapped native object converts to its
// JS object.
@interface TestNumber: OOObject
{
@public
	double value;
}
@end

@implementation TestNumber
@end


JSValue OOJSValueFromNativeObject(JSContext *context, id object)
{
	if (object == nil)  return JS_NULL;
	return JS_NewFloat64(context, static_cast<TestNumber *>(object)->value);
}


void OOJSStartTimeLimiterWithTimeLimit(OOTimeDelta)  { sLimiterDepth++; sLimiterStarts++; }
void OOJSStopTimeLimiter(void)  { sLimiterDepth--; }


@interface OOJavaScriptEngine: OOObject
+ (OOJavaScriptEngine *) sharedEngine;
@end

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *) sharedEngine
{
	static OOJavaScriptEngine *engine = nil;
	if (engine == nil)  engine = [[OOJavaScriptEngine alloc] init];
	return engine;
}

@end


@interface OOJSScript: OOObject
+ (void) pushScript:(OOJSScript *)script;
+ (void) popScript:(OOJSScript *)script;
@end

@implementation OOJSScript
+ (void) pushScript:(OOJSScript *)script  { (void)script; sScriptDepth++; sScriptPushes++; }
+ (void) popScript:(OOJSScript *)script  { (void)script; sScriptDepth--; }
@end


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


TestNumber *Number(double value)
{
	TestNumber *number = [[[TestNumber alloc] init] autorelease];
	number->value = value;
	return number;
}


OOJSFunction *Compile(const char *name, const char *code, std::vector<const char *> args)
{
	return [[[OOJSFunction alloc] initWithName:(name != nullptr ? std::optional<std::string>(name) : std::nullopt)
										 scope:JS_UNDEFINED
										  code:(code != nullptr ? std::optional<std::string>(code) : std::nullopt)
								 argumentCount:args.size()
								 argumentNames:(args.empty() ? NULL : args.data())
									  fileName:std::string("test.js")
									lineNumber:1
									   context:Context()] autorelease];
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(initWithFunction)
{
	@autoreleasepool
	{
		OO_CHECK([[OOJSFunction alloc] initWithFunction:JS_NULL context:Context()] == nil);

		JSValue f = Evaluate("(function double(x) { return 2 * x; })");
		OOJSFunction *function = [[[OOJSFunction alloc] initWithFunction:f context:Context()] autorelease];
		OO_CHECK(function != nil);
		OO_CHECK(SameObject([function function], f));
		OO_CHECK_EQ([function cxx_name].value_or("<none>"), "double");
		OO_CHECK_EQ([function cxx_descriptionComponents].value_or("<none>"), "double()");
		OO_CHECK(oo::DescriptionOf(function).find("OOJSFunction") != std::string::npos);
		JSValue functionValue = [function functionValue];
		OO_CHECK(JS_IsObject(functionValue));
		OO_CHECK(SameObject(functionValue, f));
		JS_FreeValue(Context(), functionValue);
		JS_FreeValue(Context(), f);

		JSValue anonymousFunction = Evaluate("(function () { return 1; })");
		OOJSFunction *anonymous = [[[OOJSFunction alloc] initWithFunction:anonymousFunction context:Context()] autorelease];
		JS_FreeValue(Context(), anonymousFunction);
		OO_CHECK(![anonymous cxx_name].has_value());
		OO_CHECK_EQ([anonymous cxx_descriptionComponents].value_or("<none>"), "<anonymous>()");
	}
}


OO_TEST(initWithName)
{
	@autoreleasepool
	{
		OOJSFunction *function = Compile("add", "return a + b;", { "a", "b" });
		OO_CHECK(function != nil);
		OO_CHECK_EQ([function cxx_name].value_or("<none>"), "add");
		JSValueConst argv[2] = { JS_NewInt32(Context(), 2), JS_NewInt32(Context(), 3) };
		JSValue result = JS_UNDEFINED;
		OO_CHECK([function evaluateWithContext:Context() scope:JS_UNDEFINED argc:2 argv:argv result:&result]);
		OO_CHECK_EQ(String(result), "5");

		// No code, argument names missing, or a syntax error: nil.
		OO_CHECK(Compile("none", nullptr, {}) == nil);
		OO_CHECK([[OOJSFunction alloc] initWithName:std::string("x") scope:JS_UNDEFINED code:std::string("return 1;") argumentCount:1 argumentNames:NULL fileName:std::nullopt lineNumber:0 context:Context()] == nil);
		OO_CHECK(Compile("bad", "return (;", {}) == nil);
		JS_FreeValue(Context(), JS_GetException(Context()));

		// A NULL context: the main thread's is acquired and released.
		OOJSFunction *withoutContext = [[[OOJSFunction alloc] initWithName:std::string("seven") scope:JS_UNDEFINED code:std::string("return 7;") argumentCount:0 argumentNames:NULL fileName:std::nullopt lineNumber:0 context:NULL] autorelease];
		OO_CHECK(withoutContext != nil);
		OO_CHECK([withoutContext evaluateWithContext:Context() scope:JS_UNDEFINED argc:0 argv:NULL result:&result]);
		OO_CHECK_EQ(String(result), "7");

		// An empty body answers undefined.
		OOJSFunction *empty = Compile("empty", "", {});
		OO_CHECK([empty evaluateWithContext:Context() scope:JS_UNDEFINED argc:0 argv:NULL result:&result]);
		OO_CHECK_EQ(String(result), "undefined");
	}
}


OO_TEST(evaluation)
{
	@autoreleasepool
	{
		OOJSFunction *function = Compile("thisName", "return this.name + ':' + arguments.length;", {});
		JS_FreeValue(Context(), Evaluate("globalThis.named = { name: 'n' }; globalThis.name = 'global';"));
		JSValue result = JS_UNDEFINED;
		sScriptPushes = 0;
		sLimiterStarts = 0;
		JSValue named = Evaluate("named");
		OO_CHECK([function evaluateWithContext:Context() scope:named argc:0 argv:NULL result:&result]);
		JS_FreeValue(Context(), named);
		OO_CHECK_EQ(String(result), "n:0");
		OO_CHECK([function evaluateWithContext:Context() scope:JS_UNDEFINED argc:0 argv:NULL result:&result]);
		OO_CHECK_EQ(String(result), "global:0");	// no this: the global object (the function is not strict)
		OO_CHECK_EQ(sScriptPushes, 2);
		OO_CHECK_EQ(sLimiterStarts, 2);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);

		// A throwing function answers NO, with the stack and the limiter balanced.
		OOJSFunction *thrower = Compile("thrower", "throw new Error('boom');", {});
		OO_CHECK(![thrower evaluateWithContext:Context() scope:JS_UNDEFINED argc:0 argv:NULL result:&result]);
		JS_FreeValue(Context(), JS_GetException(Context()));
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);
	}
}


OO_TEST(predicate)
{
	@autoreleasepool
	{
		OOJSFunction *greater = Compile("greater", "return a > b;", { "a", "b" });
		const std::vector<oo::ObjCRef<id>> threeTwo = { oo::ObjCRef<id>(Number(3)), oo::ObjCRef<id>(Number(2)) };
		const std::vector<oo::ObjCRef<id>> twoThree = { oo::ObjCRef<id>(Number(2)), oo::ObjCRef<id>(Number(3)) };
		OO_CHECK([greater evaluatePredicateWithContext:Context() scope:nil arguments:threeTwo]);
		OO_CHECK(![greater evaluatePredicateWithContext:Context() scope:nil arguments:twoThree]);

		// The scope object is converted too: a number is boxed.
		OOJSFunction *usesThis = Compile("usesThis", "return this.valueOf() === 4 && arguments.length === 0;", {});
		OO_CHECK([usesThis evaluatePredicateWithContext:Context() scope:Number(4) arguments:{}]);
		OO_CHECK(![usesThis evaluatePredicateWithContext:Context() scope:Number(5) arguments:{}]);

		// A nil argument is the zero value (a message to nil); truthiness is JS's.
		OOJSFunction *first = Compile("first", "return a;", { "a" });
		const std::vector<oo::ObjCRef<id>> nilArgument = { oo::ObjCRef<id>() };
		OO_CHECK(![first evaluatePredicateWithContext:Context() scope:nil arguments:nilArgument]);
		OO_CHECK([first evaluatePredicateWithContext:Context() scope:nil arguments:{ oo::ObjCRef<id>(Number(0.5)) }]);
		OO_CHECK(![first evaluatePredicateWithContext:Context() scope:nil arguments:{ oo::ObjCRef<id>(Number(0)) }]);

		// A throwing predicate is false.
		OOJSFunction *thrower = Compile("thrower", "throw 1;", {});
		OO_CHECK(![thrower evaluatePredicateWithContext:Context() scope:nil arguments:{}]);
		JS_FreeValue(Context(), JS_GetException(Context()));
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK_EQ(sLimiterDepth, 0);
	}
}


OO_TEST(engineReset)
{
	@autoreleasepool
	{
		OOJSFunction *function = Compile("resettable", "return 1;", {});
		OO_CHECK(!JS_IsNull([function function]));
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, [OOJavaScriptEngine sharedEngine]);
		OO_CHECK(JS_IsNull([function function]));
		OO_CHECK(JS_IsNull([function functionValue]));
		OO_CHECK_EQ([function cxx_name].value_or("<none>"), "resettable");	// the name stays
	}
}


OO_TEST(cxxAndFacade)
{
	@autoreleasepool
	{
		oo::Ref<cxx::OOJSFunction> function = cxx::OOJSFunction::initWithName(std::string("triple"), JS_UNDEFINED, std::string("return 3 * x;"), 1, (const char *[]){ "x" }, std::nullopt, 0, Context());
		OO_CHECK(function != nullptr);
		OO_CHECK(cxx::OOJSFunction::initWithFunction(JS_NULL, Context()) == nullptr);
		OO_CHECK(cxx::OOJSFunction::initWithName(std::string("bad"), JS_UNDEFINED, std::string("return (;"), 0, NULL, std::nullopt, 0, Context()) == nullptr);
		JS_FreeValue(Context(), JS_GetException(Context()));
		JSValueConst argv[1] = { JS_NewInt32(Context(), 4) };
		JSValue result = JS_UNDEFINED;
		OO_CHECK(function->evaluateWithContext(Context(), JS_UNDEFINED, 1, argv, &result));
		OO_CHECK_EQ(String(result), "12");
		OO_CHECK(function->evaluatePredicateWithContext(Context(), nil, { oo::ObjCRef<id>(Number(1)) }));
		OO_CHECK_EQ(function->descriptionComponents().value_or("<none>"), "triple()");

		// One facade per C++ object while it lives, and back; nil stays nil.
		OOJSFunction *facade = oo::ToObjC(function.get());
		OO_CHECK(facade != nil && facade == oo::ToObjC(function.get()));
		OO_CHECK(oo::ToCxx(facade) == function.get());
		OO_CHECK_EQ([facade cxx_name].value_or("<none>"), "triple");
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOJSFunction *>(nullptr)) == nil);
		OO_CHECK(oo::ToCxx(static_cast<OOJSFunction *>(nil)) == nullptr);

		// A facade made by alloc/init is its object's facade.
		OOJSFunction *made = Compile("made", "return 1;", {});
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);
	}
}


OO_TEST_MAIN()
