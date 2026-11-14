/*	test_OOJSVector.mm
        Unit tests for the Vector3D JS binding
   (src/Core/Scripting/OOJSVector.h/.mm).

        A binding's test runs its JS class in a real QuickJS-ng context and
   links the game's own objects for the binding, the engine's class registration
   (OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm) and
   the maths they call. What the rest of the engine would provide (error
   reporting, the argument and string helpers, Quaternion, the Entity class, the
   universe, the profiler and the time limiter) is defined below as the smallest
   stand-in that does the same thing: reportError for an error, a plain array
   for a quaternion. The expectations were written against the file's behaviour:
   they pin the JS-visible behaviour: construction, x/y/z, every method and
   static method, the errors, Vector3D.prototype reading as zero, and how a
   native's exception reaches JS (an OOException and a C++ exception both become
   a JS error). Run: bash tools/check-core-tests.sh
*/

#include <quickjs.h>

#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>

#include "OOJSEntity.h"
#include "OOJSQuaternion.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "Universe.h"
#include "legacy_random.h"
#include "oo_test.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

// MARK: What the rest of the engine provides
// ------------------------------------------------------

JSContext* gOOJSMainThreadContext = nullptr;

void cxx_OOJSReportErrorWithArguments(JSContext* context, const char* format,
                                      va_list args) {
  std::string msg = oo::str::vformat(format, args);
  JS_ThrowPlainError(context, "%s", msg.c_str());
}

void cxx_OOJSReportError(JSContext* context, const char* format, ...) {
  va_list args;
  va_start(args, format);
  cxx_OOJSReportErrorWithArguments(context, format, args);
  va_end(args);
}

void cxx_OOJSReportBadArguments(
    JSContext* context, const std::optional<std::string>& scriptClass,
    const std::optional<std::string>& function, int argc, JSValueConst*,
    const std::optional<std::string>& message,
    const std::optional<std::string>& expectedArgsDescription) {
  cxx_OOJSReportError(context, "bad arguments: %s.%s (%d): %s; expected %s",
                      scriptClass.value_or("").c_str(),
                      function.value_or("").c_str(), argc,
                      message.value_or("").c_str(),
                      expectedArgsDescription.value_or("").c_str());
}

void OOJSReportBadPropertySelector(JSContext* context, JSValueConst, int,
                                   const JSCFunctionListEntry*, size_t) {
  cxx_OOJSReportError(context, "bad property selector");
}

void OOJSReportBadPropertyValue(JSContext* context, JSValueConst, int,
                                const JSCFunctionListEntry*, size_t,
                                JSValueConst) {
  cxx_OOJSReportError(context, "bad property value");
}

// As the engine's: the pending exception, else an uncatchable error that stops
// the script.
JSValue OOJSNativeFailure(JSContext* context) {
  if (JS_HasException(context)) return JS_EXCEPTION;
  JSValue error = JS_NewError(context);
  JS_SetUncatchableError(context, error);
  return JS_Throw(context, error);
}

// As the engine's: the pending exception is reported (here, dropped) and
// cleared.
void OOJSReportPendingException(JSContext* context) {
  JS_FreeValue(context, JS_GetException(context));
}

// Property IDs are interned for the life of the process (never freed).
JSAtom cxx_OOJSIDFromString(const std::string& string) {
  return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
}

std::optional<std::string> cxx_OOStringFromJSValue(JSContext* context,
                                                   JSValueConst value) {
  if (JS_IsNull(value) || JS_IsUndefined(value)) return std::nullopt;
  std::size_t length = 0;
  const char* chars = JS_ToCStringLen(context, &length, value);
  if (chars == nullptr) {
    JS_FreeValue(context, JS_GetException(context));
    return std::nullopt;
  }
  std::string result(chars, length);
  JS_FreeCString(context, chars);
  return result;
}

bool OOJSArgumentListGetNumberNoError(JSContext* context, int argc,
                                      JSValueConst* argv, double* outNumber,
                                      int* outConsumed) {
  if (argc == 0 || JS_ToFloat64(context, outNumber, argv[0]) < 0 ||
      std::isnan(*outNumber)) {
    if (JS_HasException(context))
      JS_FreeValue(context, JS_GetException(context));
    return false;
  }
  if (outConsumed != NULL) *outConsumed = 1;
  return true;
}

bool cxx_OOJSArgumentListGetNumber(
    JSContext* context, const std::optional<std::string>& scriptClass,
    const std::optional<std::string>& function, int argc, JSValueConst* argv,
    double* outNumber, int* outConsumed) {
  if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber,
                                       outConsumed))
    return true;
  cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv,
                             "Expected number, got", std::nullopt);
  return false;
}

JSValue OOJSValueFromPList(JSContext* context, const oo::PList& plist) {
  const std::string* str = plist.getIf<std::string>();
  return str != nullptr ? JS_NewStringLen(context, str->data(), str->size())
                        : JS_NULL;
}

// The Entity class, registered by the test (OOJSEntity.mm is not linked). No
// case makes an entity, so its private slot is never read.
namespace {
JSClassID sFakeEntityClassID;
JSClassDef sFakeEntityClass = {.class_name = "Entity"};
}  // namespace

JSClassID JSEntityClassID(void) { return sFakeEntityClassID; }

// OOJSEntity.mm's (not linked): the position of the entity an Entity JS object
// holds. No case here makes an entity.
HPVector OOJSEntityPositionOfJSObject(JSContext*, JSValueConst) {
  std::abort();
}

// A quaternion is the array [w, x, y, z] here: enough to see what OOJSVector
// hands over. (bool as OOJSQuaternion.h is: a stand-in has the signature of
// what it stands in for.)
bool QuaternionToJSValue(JSContext* context, Quaternion quaternion,
                         JSValue* outValue) {
  JSValue array = JS_NewArray(context);
  if (JS_IsException(array)) return false;
  const double parts[4] = {quaternion.w, quaternion.x, quaternion.y,
                           quaternion.z};
  for (std::uint32_t i = 0; i < 4; i++)
    JS_SetPropertyUint32(context, array, i, JS_NewFloat64(context, parts[i]));
  *outValue = array;
  return true;
}

bool QuaternionFromArgumentList(JSContext* context,
                                const std::string& scriptClass,
                                const std::string& function, int argc,
                                JSValueConst* argv, Quaternion* outQuaternion,
                                int* outConsumed) {
  double q[4] = {};
  if (argc >= 1 && JS_IsArray(argv[0])) {
    bool ok = true;
    for (std::uint32_t i = 0; i < 4 && ok; i++) {
      JSValue element = JS_GetPropertyUint32(context, argv[0], i);
      ok = !JS_IsException(element) &&
           JS_ToFloat64(context, &q[i], element) == 0;
      JS_FreeValue(context, element);
    }
    if (ok) {
      *outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
      if (outConsumed != NULL) *outConsumed = 1;
      return true;
    }
  }
  cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv,
                             "Could not construct quaternion from parameters",
                             "Quaternion");
  return false;
}

#if OOJS_PROFILE
namespace {
int sProfileDepth = 0;
}  // namespace

void OOJSProfileEnter(OOJSProfileStackFrame*, const char*) { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame*) { sProfileDepth--; }
#endif

namespace {
int sLimiterPauses = 0;
}  // namespace

void OOJSPauseTimeLimiter(void) { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void) { sLimiterPauses--; }

/*	The universe, as far as Vector3D's coordinate-system methods see it:
   -legacyPositionFrom:... and -coordinatesFromCoordinateSystemString:. A system
   name of "throw-objc" or "throw-cxx" makes the call throw, so the test sees
   what a native's exception becomes.
*/
/*	The universe is a C++ class. Universe.h is
   included (through the headers above) and Universe.mm is not linked, so the
   test defines the members the code under test calls, with the stand-in's
   bodies, and UNIVERSE is storage nothing constructs: those members read no
   state.
*/
HPVector Universe::legacyPositionFrom(HPVector pos, const std::string& system) {
  if (system == "throw-objc")
    OORaiseException(OOInvalidArgumentException, "legacy %s", "boom");
  if (system == "throw-cxx") throw std::runtime_error("cxx boom");
  return make_HPvector(pos.x + 1, pos.y + 2, pos.z + 3);
}

HPVector Universe::coordinatesFromCoordinateSystemString(
    const std::string& text) {
  if (text.rfind("throw-objc", 0) == 0)
    OORaiseException(OOInvalidArgumentException, "coords %s", "boom");
  return make_HPvector(static_cast<OOHPScalar>(text.size()), 0, 0);
}

alignas(Universe) unsigned char sUniverseStorage[sizeof(Universe)];

Universe* gSharedUniverse = nullptr;

// MARK: The context
// -------------------------------------------------------------------------------

namespace {

JSRuntime* sRuntime;
JSContext* sContext;
JSValue sGlobal = JS_UNDEFINED;  // owned for the life of the test

void SetUpContext() {
  if (sContext != nullptr) return;
  sRuntime = JS_NewRuntime();
  JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
  sContext = JS_NewContext(sRuntime);
  gOOJSMainThreadContext = sContext;
  sGlobal = JS_GetGlobalObject(sContext);
  OOJSRegisterClass(&sFakeEntityClassID, &sFakeEntityClass);
  InitOOJSVector(sContext, sGlobal);
  ranrot_srand(12345);  // the game seeds its generator at startup; unseeded,
                        // Vector3D.random() never ends
  gSharedUniverse = reinterpret_cast<Universe*>(sUniverseStorage);
}

// Evaluates src and gives its result as a string ("undefined", "null", ...), or
// "threw: <message>".
std::string Eval(const char* src) {
  SetUpContext();
  std::string wrapped = std::string("(function () { try { return String(") +
                        src +
                        "); } catch (e) { return 'threw: ' + (e && e.message "
                        "!== undefined ? e.message : e); } })()";
  JSValue result = JS_Eval(sContext, wrapped.c_str(), wrapped.size(), "test.js",
                           JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(result)) {
    JS_FreeValue(sContext, JS_GetException(sContext));
    return "<evaluation failed>";
  }
  std::string text =
      cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
  JS_FreeValue(sContext, result);
  return text;
}

double EvalNumber(const char* src) { return std::stod(Eval(src)); }

}  // namespace

// MARK: Tests
// -------------------------------------------------------------------------------------

OO_TEST(construction) {
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3)"), "(1, 2, 3)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toSource()"), "Vector3D(1, 2, 3)");
  OO_CHECK_EQ(Eval("new Vector3D()"), "(0, 0, 0)");
  OO_CHECK_EQ(Eval("new Vector3D([4, 5, 6])"), "(4, 5, 6)");
  OO_CHECK_EQ(Eval("new Vector3D(new Vector3D(7, 8, 9))"), "(7, 8, 9)");
  OO_CHECK_EQ(Eval("new Vector3D(0.5, -1.25, 1e3)"), "(0.5, -1.25, 1000)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2)"),
              "threw: bad arguments: . (2): Could not construct vector from "
              "parameters; expected Vector, Entity or array of three numbers");
  OO_CHECK_EQ(Eval("new Vector3D('a', 2, 3)"),
              "threw: bad arguments: . (3): Could not construct vector from "
              "parameters; expected Vector, Entity or array of three numbers");
  OO_CHECK_EQ(Eval("new Vector3D([1, 2])"),
              "threw: bad arguments: . (1): Could not construct vector from "
              "parameters; expected Vector, Entity or array of three numbers");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3) instanceof Vector3D"), "true");
}

OO_TEST(properties) {
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).x"), "1");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).y"), "2");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).z"), "3");
  OO_CHECK_EQ(Eval("(function () { var v = new Vector3D(1, 2, 3); v.x = 10; "
                   "v.y = '20'; v.z = -3.5; return v; })()"),
              "(10, 20, -3.5)");
  OO_CHECK_EQ(Eval("(function () { var v = new Vector3D(1, 2, 3); v.x = 'abc'; "
                   "return v.x; })()"),
              "NaN");
  OO_CHECK_EQ(Eval("Object.keys(new Vector3D(1, 2, 3)).join()"), "x,y,z");
  // Vector3D.prototype has no vector: it reads as zero and ignores writes.
  OO_CHECK_EQ(Eval("Vector3D.prototype.x"), "0");
  OO_CHECK_EQ(Eval("(function () { Vector3D.prototype.y = 5; return "
                   "Vector3D.prototype.y; })()"),
              "0");
  OO_CHECK_EQ(Eval("Vector3D.prototype.add([1, 2, 3])"), "(1, 2, 3)");
}

OO_TEST(methods) {
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).add([1, 1, 1])"), "(2, 3, 4)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).subtract(new Vector3D(1, 1, 1))"),
              "(0, 1, 2)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).multiply(2)"), "(2, 4, 6)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).dot([4, 5, 6])"), "32");
  OO_CHECK_EQ(Eval("new Vector3D(1, 0, 0).cross([0, 1, 0])"), "(0, 0, 1)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 0, 0).tripleProduct([0, 1, 0], [0, 0, 1])"),
              "1");
  OO_CHECK_EQ(Eval("new Vector3D(0, 0, 0).distanceTo([3, 4, 0])"), "5");
  OO_CHECK_EQ(Eval("new Vector3D(0, 0, 0).squaredDistanceTo([3, 4, 0])"), "25");
  OO_CHECK_EQ(Eval("new Vector3D(3, 4, 0).magnitude()"), "5");
  OO_CHECK_EQ(Eval("new Vector3D(3, 4, 0).squaredMagnitude()"), "25");
  OO_CHECK_EQ(Eval("new Vector3D(3, 4, 0).direction()"), "(0.6, 0.8, 0)");
  OO_CHECK(std::fabs(EvalNumber("new Vector3D(1, 0, 0).angleTo([0, 1, 0])") -
                     M_PI / 2) < 1e-9);
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toArray()"), "1,2,3");
  OO_CHECK_EQ(Eval("Array.isArray(new Vector3D(1, 2, 3).toArray())"), "true");
  OO_CHECK_EQ(Eval("new Vector3D(1, 0, 0).rotationTo([1, 0, 0])"), "1,0,0,0");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).rotateBy([1, 0, 0, 0])"),
              "(1, 2, 3)");
  OO_CHECK_EQ(
      Eval("new Vector3D(1, 2, 3).add('x')"),
      "threw: bad arguments: Vector3D.add (1): Could not construct vector from "
      "parameters; expected Vector, Entity or array of three numbers");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).multiply('x')"),
              "threw: bad arguments: Vector3D.multiply (1): Expected number, "
              "got; expected ");
  OO_CHECK_EQ(Eval("Vector3D.prototype.add.call({}, [1, 2, 3])"),
              "threw: bad arguments: Vector3D.add (1): Invalid target object; "
              "expected Vector3D");
}

OO_TEST(staticMethods) {
  OO_CHECK_EQ(Eval("Vector3D.interpolate([0, 0, 0], [10, 20, 30], 0.5)"),
              "(5, 10, 15)");
  OO_CHECK_EQ(
      Eval("Vector3D.interpolate([0, 0, 0], [10, 20, 30])"),
      "threw: bad arguments: Vector3D.interpolate (2): Insufficient "
      "parameters; expected vector expression, vector expression and number");
  OO_CHECK(EvalNumber("Vector3D.random(2).magnitude()") <= 2.0);
  OO_CHECK(std::fabs(EvalNumber("Vector3D.randomDirection(3).magnitude()") -
                     3.0) < 1e-9);
  OO_CHECK(EvalNumber("Vector3D.randomDirectionAndLength(4).magnitude()") <=
           4.0);
  OO_CHECK(std::fabs(EvalNumber("Vector3D.randomDirection().magnitude()") -
                     1.0) < 1e-9);
}

OO_TEST(nativeInterface) {
  SetUpContext();
  JSValue value = JS_UNDEFINED;
  OO_CHECK(HPVectorToJSValue(sContext, make_HPvector(1, 2, 3), &value));
  HPVector hp = kZeroHPVector;
  OO_CHECK(JSValueToHPVector(sContext, value, &hp) && hp.x == 1 && hp.y == 2 &&
           hp.z == 3);
  OO_CHECK(JSVectorSetHPVector(sContext, value, make_HPvector(4, 5, 6)));
  Vector v = kZeroVector;
  OO_CHECK(JSValueToVector(sContext, value, &v) && v.x == 4 && v.y == 5 &&
           v.z == 6);
  OO_CHECK(!JSValueToVector(sContext, JS_NewInt32(sContext, 3), &v));
  OO_CHECK(!JSObjectGetVector(sContext, JS_NULL, &hp));
  JS_FreeValue(sContext, value);
  value = JS_UNDEFINED;
  OO_CHECK(NSPointToVectorJSValue(sContext, NSMakePoint(7, 8), &value) &&
           JSValueToHPVector(sContext, value, &hp) && hp.x == 7 && hp.y == 8 &&
           hp.z == 0);
  int consumed = 99;
  OO_CHECK(VectorFromArgumentListNoError(sContext, 1, &value, &hp, &consumed) &&
           consumed == 1);
  JS_FreeValue(sContext, value);
  JSValueConst three[3] = {JS_NewInt32(sContext, 1), JS_NewInt32(sContext, 2),
                           JS_NewInt32(sContext, 3)};
  OO_CHECK(!VectorFromArgumentListNoError(sContext, 3, three, &hp, &consumed) &&
           consumed == 0);  // numbers only for the constructor
}

OO_TEST(nativeExceptions) {
  // toCoordinateSystem() and fromCoordinateSystem() call the universe inside
  // OOJS_NATIVE_ENTER.
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem('abc')"),
              "(2, 4, 6)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).fromCoordinateSystem('abc')"),
              "(30, 0, 0)");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem()"),
              "threw: bad arguments: Vector3D.toCoordinateSystem (0): ; "
              "expected coordinate system");
  // An OOException from a native is a JS error, and the time limiter is resumed
  // on the way out.
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem('throw-objc')"),
              "threw: Native exception: legacy boom");
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).fromCoordinateSystem('throw-objc')"),
              "threw: Native exception: coords boom");
  OO_CHECK_EQ(sLimiterPauses, 0);
#if OOJS_PROFILE
  OO_CHECK_EQ(sProfileDepth, 0);
#endif
}

OO_TEST(nativeCxxExceptions) {
  // A C++ exception from a native, which @catch (id) could not catch, is a JS
  // error too.
  OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem('throw-cxx')"),
              "threw: Native exception: cxx boom");
  OO_CHECK_EQ(sLimiterPauses, 0);
#if OOJS_PROFILE
  OO_CHECK_EQ(sProfileDepth, 0);
#endif
}

OO_TEST_MAIN()
