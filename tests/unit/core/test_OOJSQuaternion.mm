/*	test_OOJSQuaternion.mm
	Unit tests for the Quaternion JS binding (src/Core/Scripting/OOJSQuaternion.h/.mm): bead
	oo-hwae, converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment
	oo-ppc).

	Like test_OOJSVector.mm, it runs the JS class in a real QuickJS-ng context and links the game's
	own objects for the binding, the Vector3D binding it hands vectors to, the engine's class
	registry (OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm) and the maths
	they call. What the rest of the engine would
	provide (error reporting, the argument and string helpers, the Entity class, the profiler and
	the time limiter) is defined below as the smallest stand-in that does the same thing. The
	expectations were written against the Objective-C file and run on it first; they pin the
	JS-visible behaviour: construction, w/x/y/z, every method and static method, the errors,
	Quaternion.prototype reading as zero, an entity read as its orientation, and how an exception
	under a native reaches JS. Run: bash tools/check-core-tests.sh
*/

#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "OOJSEntity.h"
#import "Universe.h"
#include "legacy_random.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <cmath>
#include <cstdarg>
#include <cstring>
#include <stdexcept>
#include <string>


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;


void cxx_OOJSReportErrorWithArguments(JSContext *context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
}


void cxx_OOJSReportError(JSContext *context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportBadArguments(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


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


BOOL OOJSArgumentListGetNumberNoError(JSContext *context, int argc, JSValueConst *argv, double *outNumber, int *outConsumed)
{
	if (argc < 1)  return NO;
	if (JS_ToFloat64(context, outNumber, argv[0]) < 0)
	{
		JS_FreeValue(context, JS_GetException(context));
		return NO;
	}
	if (std::isnan(*outNumber))  return NO;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
}


BOOL cxx_OOJSArgumentListGetNumber(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *argv, double *outNumber, int *outConsumed)
{
	if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed))  return YES;
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Expected number, got", std::nullopt);
	return NO;
}


JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	const std::string *str = plist.getIf<std::string>();
	return str != nullptr ? JS_NewStringLen(context, str->data(), str->size()) : JS_NULL;
}


// The atom cache and the pending-exception reporter, which the class registry calls.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(gOOJSMainThreadContext, string.data(), string.size());
}


void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// As the engine's: the pending exception, else an uncatchable one that ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


namespace {
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
JSClassID sFakeEntityClassID = 0;
} // namespace

JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


// OOJSEntity.mm's (not linked): the position and orientation of the entity an Entity JS object
// holds (it was the object, whose -position/-orientation the conversions sent). The test's
// fake entities are put in the slot themselves; the orientation is the fake's (below). No case converts
// an entity to a vector here.
HPVector OOJSEntityPositionOfJSObject(JSContext *, JSValueConst)  { std::abort(); }
Quaternion OOJSEntityOrientationOfJSObject(JSContext *context, JSValueConst object);


#if OOJS_PROFILE
namespace {
int sProfileDepth = 0;
} // namespace

void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif


namespace {
int sLimiterPauses = 0;
} // namespace

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


/*	An entity, as far as the conversion sees one: a JS object of the Entity class whose private
	slot answers -weakRefUnderlyingObject with something that has an -orientation. A fake entity
	made with orientation w = -1 raises from -orientation, one made with w = -2 throws a C++
	exception, so the test sees what an exception under a native becomes.
*/
@interface FakeEntity: OOObject
{
@public
	Quaternion _orientation;
}
@end

@implementation FakeEntity

- (id) weakRefUnderlyingObject
{
	return self;
}


- (Quaternion) orientation
{
	if (_orientation.w == -1)  [OOException raise:OOInvalidArgumentException format:"orientation %s", "boom"];
	if (_orientation.w == -2)  throw std::runtime_error("cxx boom");
	return _orientation;
}

@end


// The fake entity's orientation, as the conversion asked its object (nil: zero).
Quaternion OOJSEntityOrientationOfJSObject(JSContext *, JSValueConst object)
{
	JSClassID ignored;
	FakeEntity *entity = [(id)JS_GetAnyOpaque(object, &ignored) weakRefUnderlyingObject];
	return [entity orientation];
}

Universe *gSharedUniverse = nil;	// OOJSVector.mm's coordinate-system methods read it; not called here

// Link stubs, never reached: OOJSVector.mm's coordinate-system methods call them on the universe,
// which stays nil here (bead oo-ql9rn: they were messages to nil).
HPVector Universe::legacyPositionFrom(HPVector, const std::string &)  { std::abort(); }
HPVector Universe::coordinatesFromCoordinateSystemString(const std::string &)  { std::abort(); }


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal;


// makeEntity(w, x, y, z): a JS Entity whose orientation is the given quaternion.
JSValue MakeEntity(JSContext *context, JSValueConst, int argc, JSValueConst *argv)
{
	double q[4] = {};
	for (int i = 0; i < 4 && i < argc; i++)
	{
		if (JS_ToFloat64(context, &q[i], argv[i]) < 0)  return JS_EXCEPTION;
	}
	FakeEntity *entity = [[FakeEntity alloc] init];	// kept for the life of the test
	entity->_orientation = make_quaternion(q[0], q[1], q[2], q[3]);
	JSValue object = JS_NewObjectClass(context, static_cast<int>(sFakeEntityClassID));
	if (JS_IsException(object))  return object;
	if (JS_SetOpaque(object, entity) < 0)
	{
		JS_FreeValue(context, object);
		return JS_ThrowInternalError(context, "makeEntity failed");
	}
	return object;
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeEntityClassID, &sFakeEntityClass);
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, nullptr, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	InitOOJSVector(sContext, sGlobal);
	InitOOJSQuaternion(sContext, sGlobal);
	JS_SetPropertyStr(sContext, sGlobal, "makeEntity", JS_NewCFunction(sContext, MakeEntity, "makeEntity", 4));
	ranrot_srand(12345);	// the game seeds its generator at startup
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	JSValue result = JS_Eval(sContext, wrapped.c_str(), wrapped.size(), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));
		return "<evaluation failed>";
	}
	std::string text = cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
	JS_FreeValue(sContext, result);
	return text;
}


// Eval, and print what came back when it is not what the check expects.
std::string EvalShown(const char *src, const char *expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src, result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)


double EvalNumber(const char *src)
{
	return std::stod(Eval(src));
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(construction)
{
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4)", "(1 + 2i + 3j + 4k)");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).toSource()", "Quaternion(1, 2, 3, 4)");
	OO_CHECK_EVAL("new Quaternion()", "(1 + 0i + 0j + 0k)");
	OO_CHECK_EVAL("new Quaternion([4, 5, 6, 7])", "(4 + 5i + 6j + 7k)");
	OO_CHECK_EVAL("new Quaternion(new Quaternion(0.5, -1.25, 1e3, 0))", "(0.5 - 1.25i + 1000j + 0k)");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3)", "threw: bad arguments: . (3): Could not construct quaternion from parameters; expected Quaternion, Entity or array of four numbers");
	OO_CHECK_EVAL("new Quaternion('a', 2, 3, 4)", "threw: bad arguments: . (4): Could not construct quaternion from parameters; expected Quaternion, Entity or array of four numbers");
	OO_CHECK_EVAL("new Quaternion([1, 2, 3])", "threw: bad arguments: . (1): Could not construct quaternion from parameters; expected Quaternion, Entity or array of four numbers");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4) instanceof Quaternion", "true");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).w", "1");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).x", "2");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).y", "3");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).z", "4");
	OO_CHECK_EVAL("(function () { var q = new Quaternion(1, 2, 3, 4); q.w = 10; q.x = '20'; q.y = -3.5; q.z = 0.25; return q.toSource(); })()", "Quaternion(10, 20, -3.5, 0.25)");
	OO_CHECK_EVAL("(function () { var q = new Quaternion(1, 2, 3, 4); q.x = 'abc'; return q.x; })()", "NaN");
	OO_CHECK_EVAL("Object.keys(new Quaternion(1, 2, 3, 4)).join()", "w,x,y,z");
	// Quaternion.prototype has no quaternion: it reads as zero and ignores writes.
	OO_CHECK_EVAL("Quaternion.prototype.w", "0");
	OO_CHECK_EVAL("(function () { Quaternion.prototype.y = 5; return Quaternion.prototype.y; })()", "0");
	OO_CHECK_EVAL("Quaternion.prototype.toSource()", "Quaternion(0, 0, 0, 0)");
}


OO_TEST(methods)
{
	OO_CHECK_EVAL("new Quaternion(1, 0, 0, 0).multiply([0, 1, 0, 0]).toSource()", "Quaternion(0, 1, 0, 0)");
	OO_CHECK_EVAL("new Quaternion(0, 1, 0, 0).multiply(new Quaternion(0, 0, 1, 0)).toSource()", "Quaternion(0, 0, 0, 1)");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).dot([4, 3, 2, 1])", "20");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).conjugate().toSource()", "Quaternion(1, -2, -3, -4)");
	OO_CHECK_EVAL("new Quaternion(2, 0, 0, 0).normalize().toSource()", "Quaternion(1, 0, 0, 0)");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).toArray()", "1,2,3,4");
	OO_CHECK_EVAL("Array.isArray(new Quaternion(1, 2, 3, 4).toArray())", "true");
	OO_CHECK_EVAL("new Quaternion().vectorForward()", "(0, 0, 1)");
	OO_CHECK_EVAL("new Quaternion().vectorUp()", "(0, 1, 0)");
	OO_CHECK_EVAL("new Quaternion().vectorRight()", "(1, 0, 0)");
	OO_CHECK_EVAL("new Quaternion().vectorForward() instanceof Vector3D", "true");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).rotate([0, 0, 1])", "(1 + 2i + 3j + 4k)");	// no angle: unchanged
	OO_CHECK(std::fabs(EvalNumber("new Quaternion().rotate([0, 0, 1], Math.PI).w")) < 1e-6);
	OO_CHECK(std::fabs(std::fabs(EvalNumber("new Quaternion().rotate([0, 0, 1], Math.PI).z")) - 1) < 1e-6);
	OO_CHECK(std::fabs(std::fabs(EvalNumber("new Quaternion().rotateX(Math.PI).x")) - 1) < 1e-6);
	OO_CHECK(std::fabs(std::fabs(EvalNumber("new Quaternion().rotateY(Math.PI).y")) - 1) < 1e-6);
	OO_CHECK(std::fabs(std::fabs(EvalNumber("new Quaternion().rotateZ(Math.PI).z")) - 1) < 1e-6);
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).multiply('x')", "threw: bad arguments: Quaternion.multiply (1): Could not construct quaternion from parameters; expected Quaternion, Entity or four numbers");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).rotateX('x')", "threw: bad arguments: Quaternion.rotateX (1): Expected number, got; expected ");
	OO_CHECK_EVAL("new Quaternion(1, 2, 3, 4).rotate('x', 1)", "threw: bad arguments: Quaternion.rotate (2): Could not construct vector from parameters; expected Vector, Entity or array of three numbers");
	OO_CHECK_EVAL("Quaternion.prototype.dot.call({}, [1, 2, 3, 4])", "threw: bad arguments: Quaternion.dot (1): Invalid target object; expected Quaternion");
}


OO_TEST(staticMethods)
{
	OO_CHECK(std::fabs(EvalNumber("(function () { var q = Quaternion.random(); return q.dot(q); })()") - 1.0) < 1e-5);
	OO_CHECK_EVAL("Quaternion.random() instanceof Quaternion", "true");
}


OO_TEST(entities)
{
	// An entity converts to its orientation.
	OO_CHECK_EVAL("new Quaternion(makeEntity(0, 1, 0, 0)).toSource()", "Quaternion(0, 1, 0, 0)");
	OO_CHECK_EVAL("new Quaternion(1, 0, 0, 0).multiply(makeEntity(0, 0, 1, 0)).toSource()", "Quaternion(0, 0, 1, 0)");
}


OO_TEST(nativeInterface)
{
	SetUpContext();
	JSValue value = JS_UNDEFINED;
	OO_CHECK(QuaternionToJSValue(sContext, make_quaternion(1, 2, 3, 4), &value));
	Quaternion q = kZeroQuaternion;
	OO_CHECK(JSValueToQuaternion(sContext, value, &q) && q.w == 1 && q.x == 2 && q.y == 3 && q.z == 4);
	OO_CHECK(JSQuaternionSetQuaternion(sContext, value, make_quaternion(5, 6, 7, 8)));
	OO_CHECK(JSObjectGetQuaternion(sContext, value, &q) && q.w == 5 && q.x == 6 && q.y == 7 && q.z == 8);
	OO_CHECK(!JSValueToQuaternion(sContext, JS_NewInt32(sContext, 3), &q));
	OO_CHECK(!JSObjectGetQuaternion(sContext, JS_NULL, &q));
	JSValue made = JSQuaternionWithQuaternion(sContext, make_quaternion(0, 0, 0, 1));
	OO_CHECK(JS_IsObject(made) && JSObjectGetQuaternion(sContext, made, &q) && q.z == 1);
	JS_FreeValue(sContext, made);
	int consumed = 99;
	OO_CHECK(QuaternionFromArgumentList(sContext, "Test", "test", 1, &value, &q, &consumed) && consumed == 1 && q.w == 5);
	JSValue four[4] = { JS_NewInt32(sContext, 1), JS_NewInt32(sContext, 2), JS_NewInt32(sContext, 3), JS_NewInt32(sContext, 4) };
	OO_CHECK(!QuaternionFromArgumentList(sContext, "Test", "test", 4, four, &q, &consumed) && consumed == 0);	// numbers only for the constructor
	JS_FreeValue(sContext, JS_GetException(sContext));
	JS_FreeValue(sContext, value);
}


OO_TEST(nativeExceptions)
{
	// toString() is a native (OOJS_NATIVE_ENTER); an entity's -orientation that raises there is a
	// JS error, and a C++ exception is too.
	OO_CHECK_EVAL("Quaternion.prototype.toString.call(makeEntity(-1, 0, 0, 0))", "threw: Native exception: orientation boom");
	OO_CHECK_EVAL("Quaternion.prototype.toSource.call(makeEntity(-2, 0, 0, 0))", "threw: Native exception: cxx boom");
	OO_CHECK_EQ(sLimiterPauses, 0);
#if OOJS_PROFILE
	OO_CHECK_EQ(sProfileDepth, 0);
#endif
}



OO_TEST_MAIN()
