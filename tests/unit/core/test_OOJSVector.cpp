/*	test_OOJSVector.mm
	Unit tests for the Vector3D JS binding (src/Core/Scripting/OOJSVector.h/.mm): bead oo-ppc, the
	Phase 3 scripting-bindings pattern (proposed ADR-0056 amendment oo-ppc).

	A binding's test runs its JS class in a real context on the game's own façade backend
	(ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the binding, the engine's
	exception translator (OOJSEngineNativeWrappers.mm) and the maths they call. What the rest of
	the engine would provide (error reporting, the argument and string helpers, Quaternion, the
	Entity class, the universe, the profiler and the time limiter) is defined below as the
	smallest stand-in that does the same thing: reportError for an error, a plain array for a
	quaternion. The expectations were written against the Objective-C file and run on it first;
	they pin the JS-visible behaviour: construction, x/y/z, every method and static method, the
	errors, Vector3D.prototype reading as zero, and how a native's exception reaches JS (an
	Objective-C OOException and a C++ exception both become a JS error). Run:
	bash tools/check-core-tests.sh
*/

#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
#include "OOJSQuaternion.h"
#include "OOJSEntity.h"
#include "Universe.h"
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

void cxx_OOJSReportErrorWithArguments(ooscript::Context context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	ooscript::reportError(context, msg.c_str());
}


void cxx_OOJSReportError(ooscript::Context context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	cxx_OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


void cxx_OOJSReportBadArguments(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *, const std::optional<std::string> &message, const std::optional<std::string> &expectedArgsDescription)
{
	cxx_OOJSReportError(context, "bad arguments: %s.%s (%u): %s; expected %s", scriptClass.value_or("").c_str(), function.value_or("").c_str(), argc, message.value_or("").c_str(), expectedArgsDescription.value_or("").c_str());
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


std::optional<std::string> cxx_OOStringFromJSValue(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNullOrUndefined(value))  return std::nullopt;
	ooscript::String str = ooscript::valueToString(context, value);
	if (str == nullptr)  return std::nullopt;
	std::size_t length = 0;
	const ooscript::Char16 *chars = ooscript::getStringCharsAndLength(context, str, &length);
	std::string result;
	for (std::size_t i = 0; i < length; i++)  result += static_cast<char>(chars[i]);	// the test's strings are ASCII
	return result;
}


BOOL cxx_OOJSArgumentListGetNumber(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed))  return YES;
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Expected number, got", std::nullopt);
	return NO;
}


BOOL OOJSArgumentListGetNumberNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	if (argc == 0 || !ooscript::valueToNumber(context, argv[0], outNumber) || std::isnan(*outNumber))  return NO;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
}


ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	const std::string *str = plist.getIf<std::string>();
	ooscript::String js = str != nullptr ? ooscript::newStringCopyN(context, str->data(), str->size()) : nullptr;
	return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
}


BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	return putativeSubclass == superclass;
}


namespace {
ooscript::ClassDef sFakeEntityClass = { "Entity", ooscript::ClassFlag::HasPrivate };
} // namespace

ooscript::ClassDef *JSEntityClass(void)
{
	return &sFakeEntityClass;
}


// OOJSEntity.mm's (not linked): the position of the entity an Entity JS object holds (bead oo-9ht.39.8.12; it
// was the object, whose -position the conversion sent). No case here makes an entity.
HPVector OOJSEntityPositionOfJSObject(ooscript::Context, ooscript::Object)  { std::abort(); }


// A quaternion is the array [w, x, y, z] here: enough to see what OOJSVector hands over. (bool since
// OOJSQuaternion.h is, bead oo-hwae: a stand-in has the signature of what it stands in for.)
bool QuaternionToJSValue(ooscript::Context context, Quaternion quaternion, ooscript::Value *outValue)
{
	ooscript::Value parts[4] = { ooscript::numberValue(quaternion.w), ooscript::numberValue(quaternion.x), ooscript::numberValue(quaternion.y), ooscript::numberValue(quaternion.z) };
	ooscript::Object array = ooscript::newArrayObject(context, 4, parts);
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool QuaternionFromArgumentList(ooscript::Context context, const std::string &scriptClass, const std::string &function, unsigned argc, ooscript::Value *argv, Quaternion *outQuaternion, unsigned *outConsumed)
{
	double q[4] = {};
	ooscript::Value element;
	if (argc >= 1 && ooscript::isObject(argv[0]) && ooscript::isArrayObject(context, ooscript::toObject(argv[0])))
	{
		bool ok = true;
		for (int i = 0; i < 4; i++)  ok = ok && ooscript::getElement(context, ooscript::toObject(argv[0]), i, &element) && ooscript::valueToNumber(context, element, &q[i]);
		if (ok)
		{
			*outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
			if (outConsumed != NULL)  *outConsumed = 1;
			return true;
		}
	}
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Could not construct quaternion from parameters", "Quaternion");
	return false;
}


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


/*	The universe, as far as Vector3D's coordinate-system methods see it: -legacyPositionFrom:... and
	-coordinatesFromCoordinateSystemString:. A system name of "throw-objc" or "throw-cxx" makes the
	call throw, so the test sees what a native's exception becomes.
*/
/*	The universe is the C++ class since bead oo-ql9rn deleted its Objective-C facade, which the
	test's FakeUniverse stood in for. Universe.h is included (through the headers above) and
	Universe.mm is not linked, so the test defines the members the code under test calls, with the
	stand-in's bodies, and UNIVERSE is storage nothing constructs: those members read no state.
*/
HPVector Universe::legacyPositionFrom(HPVector pos, const std::string &system)
{
	if (system == "throw-objc")  OORaiseException(OOInvalidArgumentException, "legacy %s", "boom");
	if (system == "throw-cxx")  throw std::runtime_error("cxx boom");
	return make_HPvector(pos.x + 1, pos.y + 2, pos.z + 3);
}


HPVector Universe::coordinatesFromCoordinateSystemString(const std::string &text)
{
	if (text.rfind("throw-objc", 0) == 0)  OORaiseException(OOInvalidArgumentException, "coords %s", "boom");
	return make_HPvector(static_cast<OOHPScalar>(text.size()), 0, 0);
}

alignas(Universe) unsigned char sUniverseStorage[sizeof(Universe)];

Universe *gSharedUniverse = nil;


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	InitOOJSVector(sContext, sGlobal);
	ranrot_srand(12345);	// the game seeds its generator at startup; unseeded, Vector3D.random() never ends
	gSharedUniverse = reinterpret_cast<Universe *>(sUniverseStorage);
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	ooscript::Value result = ooscript::undefinedValue();
	if (!ooscript::evaluateScript(sContext, sGlobal, wrapped.c_str(), static_cast<unsigned>(wrapped.size()), "test.js", 1, &result))
	{
		ooscript::clearPendingException(sContext);
		return "<evaluation failed>";
	}
	return cxx_OOStringFromJSValue(sContext, result).value_or("<not a string>");
}


double EvalNumber(const char *src)
{
	return std::stod(Eval(src));
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(construction)
{
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3)"), "(1, 2, 3)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toSource()"), "Vector3D(1, 2, 3)");
	OO_CHECK_EQ(Eval("new Vector3D()"), "(0, 0, 0)");
	OO_CHECK_EQ(Eval("new Vector3D([4, 5, 6])"), "(4, 5, 6)");
	OO_CHECK_EQ(Eval("new Vector3D(new Vector3D(7, 8, 9))"), "(7, 8, 9)");
	OO_CHECK_EQ(Eval("new Vector3D(0.5, -1.25, 1e3)"), "(0.5, -1.25, 1000)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2)"), "threw: bad arguments: . (2): Could not construct vector from parameters; expected Vector, Entity or array of three numbers");
	OO_CHECK_EQ(Eval("new Vector3D('a', 2, 3)"), "threw: bad arguments: . (3): Could not construct vector from parameters; expected Vector, Entity or array of three numbers");
	OO_CHECK_EQ(Eval("new Vector3D([1, 2])"), "threw: bad arguments: . (1): Could not construct vector from parameters; expected Vector, Entity or array of three numbers");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3) instanceof Vector3D"), "true");
}


OO_TEST(properties)
{
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).x"), "1");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).y"), "2");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).z"), "3");
	OO_CHECK_EQ(Eval("(function () { var v = new Vector3D(1, 2, 3); v.x = 10; v.y = '20'; v.z = -3.5; return v; })()"), "(10, 20, -3.5)");
	OO_CHECK_EQ(Eval("(function () { var v = new Vector3D(1, 2, 3); v.x = 'abc'; return v.x; })()"), "NaN");
	OO_CHECK_EQ(Eval("Object.keys(new Vector3D(1, 2, 3)).join()"), "x,y,z");
	// Vector3D.prototype has no vector: it reads as zero and ignores writes.
	OO_CHECK_EQ(Eval("Vector3D.prototype.x"), "0");
	OO_CHECK_EQ(Eval("(function () { Vector3D.prototype.y = 5; return Vector3D.prototype.y; })()"), "0");
	OO_CHECK_EQ(Eval("Vector3D.prototype.add([1, 2, 3])"), "(1, 2, 3)");
}


OO_TEST(methods)
{
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).add([1, 1, 1])"), "(2, 3, 4)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).subtract(new Vector3D(1, 1, 1))"), "(0, 1, 2)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).multiply(2)"), "(2, 4, 6)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).dot([4, 5, 6])"), "32");
	OO_CHECK_EQ(Eval("new Vector3D(1, 0, 0).cross([0, 1, 0])"), "(0, 0, 1)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 0, 0).tripleProduct([0, 1, 0], [0, 0, 1])"), "1");
	OO_CHECK_EQ(Eval("new Vector3D(0, 0, 0).distanceTo([3, 4, 0])"), "5");
	OO_CHECK_EQ(Eval("new Vector3D(0, 0, 0).squaredDistanceTo([3, 4, 0])"), "25");
	OO_CHECK_EQ(Eval("new Vector3D(3, 4, 0).magnitude()"), "5");
	OO_CHECK_EQ(Eval("new Vector3D(3, 4, 0).squaredMagnitude()"), "25");
	OO_CHECK_EQ(Eval("new Vector3D(3, 4, 0).direction()"), "(0.6, 0.8, 0)");
	OO_CHECK(std::fabs(EvalNumber("new Vector3D(1, 0, 0).angleTo([0, 1, 0])") - M_PI / 2) < 1e-9);
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toArray()"), "1,2,3");
	OO_CHECK_EQ(Eval("Array.isArray(new Vector3D(1, 2, 3).toArray())"), "true");
	OO_CHECK_EQ(Eval("new Vector3D(1, 0, 0).rotationTo([1, 0, 0])"), "1,0,0,0");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).rotateBy([1, 0, 0, 0])"), "(1, 2, 3)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).add('x')"), "threw: bad arguments: Vector3D.add (1): Could not construct vector from parameters; expected Vector, Entity or array of three numbers");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).multiply('x')"), "threw: bad arguments: Vector3D.multiply (1): Expected number, got; expected ");
	OO_CHECK_EQ(Eval("Vector3D.prototype.add.call({}, [1, 2, 3])"), "threw: bad arguments: Vector3D.add (1): Invalid target object; expected Vector3D");
}


OO_TEST(staticMethods)
{
	OO_CHECK_EQ(Eval("Vector3D.interpolate([0, 0, 0], [10, 20, 30], 0.5)"), "(5, 10, 15)");
	OO_CHECK_EQ(Eval("Vector3D.interpolate([0, 0, 0], [10, 20, 30])"), "threw: bad arguments: Vector3D.interpolate (2): Insufficient parameters; expected vector expression, vector expression and number");
	OO_CHECK(EvalNumber("Vector3D.random(2).magnitude()") <= 2.0);
	OO_CHECK(std::fabs(EvalNumber("Vector3D.randomDirection(3).magnitude()") - 3.0) < 1e-9);
	OO_CHECK(EvalNumber("Vector3D.randomDirectionAndLength(4).magnitude()") <= 4.0);
	OO_CHECK(std::fabs(EvalNumber("Vector3D.randomDirection().magnitude()") - 1.0) < 1e-9);
}


OO_TEST(nativeInterface)
{
	SetUpContext();
	ooscript::Value value = ooscript::undefinedValue();
	OO_CHECK(HPVectorToJSValue(sContext, make_HPvector(1, 2, 3), &value));
	HPVector hp = kZeroHPVector;
	OO_CHECK(JSValueToHPVector(sContext, value, &hp) && hp.x == 1 && hp.y == 2 && hp.z == 3);
	OO_CHECK(JSVectorSetHPVector(sContext, ooscript::toObject(value), make_HPvector(4, 5, 6)));
	Vector v = kZeroVector;
	OO_CHECK(JSValueToVector(sContext, value, &v) && v.x == 4 && v.y == 5 && v.z == 6);
	OO_CHECK(!JSValueToVector(sContext, ooscript::int32Value(3), &v));
	OO_CHECK(!JSObjectGetVector(sContext, nullptr, &hp));
	OO_CHECK(NSPointToVectorJSValue(sContext, NSMakePoint(7, 8), &value) && JSValueToHPVector(sContext, value, &hp) && hp.x == 7 && hp.y == 8 && hp.z == 0);
	unsigned consumed = 99;
	OO_CHECK(VectorFromArgumentListNoError(sContext, 1, &value, &hp, &consumed) && consumed == 1);
	ooscript::Value three[3] = { ooscript::int32Value(1), ooscript::int32Value(2), ooscript::int32Value(3) };
	OO_CHECK(!VectorFromArgumentListNoError(sContext, 3, three, &hp, &consumed) && consumed == 0);	// numbers only for the constructor
}


OO_TEST(nativeExceptions)
{
	// toCoordinateSystem() and fromCoordinateSystem() call the universe inside OOJS_NATIVE_ENTER.
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem('abc')"), "(2, 4, 6)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).fromCoordinateSystem('abc')"), "(30, 0, 0)");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem()"), "threw: bad arguments: Vector3D.toCoordinateSystem (0): ; expected coordinate system");
	// An Objective-C exception from a native is a JS error, and the time limiter and request are
	// resumed on the way out.
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem('throw-objc')"), "threw: Native exception: legacy boom");
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).fromCoordinateSystem('throw-objc')"), "threw: Native exception: coords boom");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
#if OOJS_PROFILE
	OO_CHECK_EQ(sProfileDepth, 0);
#endif
}


OO_TEST(nativeCxxExceptions)
{
	// A C++ exception from a native, which @catch (id) could not catch, is a JS error too.
	OO_CHECK_EQ(Eval("new Vector3D(1, 2, 3).toCoordinateSystem('throw-cxx')"), "threw: Native exception: cxx boom");
	OO_CHECK_EQ(sLimiterPauses, 0);
#if OOJS_PROFILE
	OO_CHECK_EQ(sProfileDepth, 0);
#endif
}


#if OO_DEBUG
OO_TEST(statistics)
{
	clearJSVectorStatistics();
	Eval("new Vector3D(1, 2, 3).add(new Vector3D(1, 1, 1)).add([1, 2, 3]).add(Vector3D.prototype)");
	// The report is kept in a local: a pointer into the temporary would dangle once the statement
	// ends (oo-zdxtn, an ASan stack-use-after-scope).
	const oo::PList reportNode = reportJSVectorStatistics();
	const std::string *report = reportNode.getIf<std::string>();
	OO_CHECK(report != nullptr);
	if (report != nullptr)
	{
		OO_CHECK(report->find(" vector-to-vector conversions: ") == 0);
		OO_CHECK(report->find("  array-to-vector conversions: 1 (") != std::string::npos);
		OO_CHECK(report->find("prototype-to-zero conversions: 1 (") != std::string::npos);
	}
	clearJSVectorStatistics();
	const oo::PList clearedNode = reportJSVectorStatistics();
	report = clearedNode.getIf<std::string>();
	OO_CHECK(report != nullptr && report->find("total: 0") != std::string::npos);
}
#endif


OO_TEST_MAIN()
