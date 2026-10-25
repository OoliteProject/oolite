/*	test_OOJSQuaternion.mm
	Unit tests for the Quaternion JS binding (src/Core/Scripting/OOJSQuaternion.h/.mm): bead
	oo-hwae, converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment
	oo-ppc).

	Like test_OOJSVector.mm, it runs the JS class in a real context on the game's own façade
	backend (ooscript/JSEngine_quickjs.cpp) and links the game's own objects for the binding, the
	Vector3D binding it hands vectors to, the engine's exception translator
	(OOJSEngineNativeWrappers.mm) and the maths they call. What the rest of the engine would
	provide (error reporting, the argument and string helpers, the Entity class, the profiler and
	the time limiter) is defined below as the smallest stand-in that does the same thing. The
	expectations were written against the Objective-C file and run on it first; they pin the
	JS-visible behaviour: construction, w/x/y/z, every method and static method, the errors,
	Quaternion.prototype reading as zero, an entity read as its orientation, and how an exception
	under a native reaches JS. Run: bash tools/check-core-tests.sh
*/

#include "OOJSQuaternion.h"
#include "OOJSVector.h"
#include "OOJavaScriptEngine.h"
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


BOOL OOJSArgumentListGetNumberNoError(ooscript::Context context, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	if (argc == 0 || !ooscript::valueToNumber(context, argv[0], outNumber) || std::isnan(*outNumber))  return NO;
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
}


BOOL cxx_OOJSArgumentListGetNumber(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, double *outNumber, unsigned *outConsumed)
{
	if (OOJSArgumentListGetNumberNoError(context, argc, argv, outNumber, outConsumed))  return YES;
	cxx_OOJSReportBadArguments(context, scriptClass, function, argc, argv, "Expected number, got", std::nullopt);
	return NO;
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


// OOJSEntity.mm's (not linked): the position and orientation of the entity an Entity JS object
// holds (bead oo-9ht.39.8.12; it was the object, whose -position/-orientation the conversions sent). The test's
// fake entities are put in the slot themselves; the orientation is the fake's (below). No case converts
// an entity to a vector here.
HPVector OOJSEntityPositionOfJSObject(ooscript::Context, ooscript::Object)  { std::abort(); }
Quaternion OOJSEntityOrientationOfJSObject(ooscript::Context context, ooscript::Object object);


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
	slot holds something that has an -orientation. A fake entity
	made with orientation w = -1 raises from -orientation, one made with w = -2 throws a C++
	exception, so the test sees what an exception under a native becomes. C++ since bead oo-4aq6a.11
	(it was rooted on the Objective-C root class OOObject, which Phase 4 deletes); its selector is a
	member of the same name.
*/
class FakeEntity final : public oo::RefCounted
{
public:
	Quaternion orientation();

	Quaternion _orientation = {};
};


Quaternion FakeEntity::orientation()
{
	if (_orientation.w == -1)  OORaiseException(OOInvalidArgumentException, "orientation %s", "boom");
	if (_orientation.w == -2)  throw std::runtime_error("cxx boom");
	return _orientation;
}


// The fake entity's orientation, as the conversion asked its object (nil: zero) until bead oo-9ht.39.8.12.
Quaternion OOJSEntityOrientationOfJSObject(ooscript::Context context, ooscript::Object object)
{
	FakeEntity *entity = (FakeEntity *)ooscript::getPrivate(context, object);	// the slot's object itself (bead oo-9ht.22)
	return entity != nullptr ? entity->orientation() : Quaternion{};	// (a message to nil gave zero)
}

Universe *gSharedUniverse = nil;	// OOJSVector.mm's coordinate-system methods read it; not called here

// Link stubs, never reached: OOJSVector.mm's coordinate-system methods call them on the universe,
// which stays nil here (bead oo-ql9rn: they were messages to nil).
HPVector Universe::legacyPositionFrom(HPVector, const std::string &)  { std::abort(); }
HPVector Universe::coordinatesFromCoordinateSystemString(const std::string &)  { std::abort(); }


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;


// makeEntity(w, x, y, z): a JS Entity whose orientation is the given quaternion.
bool MakeEntity(ooscript::Context context, ooscript::CallArgs &args)
{
	double q[4] = {};
	for (unsigned i = 0; i < 4 && i < args.count(); i++)  ooscript::valueToNumber(context, args.argv()[i], &q[i]);
	FakeEntity *entity = oo::makeRef<FakeEntity>().leakRef();	// kept for the life of the test
	entity->_orientation = make_quaternion(q[0], q[1], q[2], q[3]);
	ooscript::Object object = ooscript::newObject(context, &sFakeEntityClass, nullptr, nullptr);
	if (object == nullptr || !ooscript::setPrivate(context, object, entity))  return false;
	args.setRval(ooscript::objectValue(object));
	return true;
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	InitOOJSVector(sContext, sGlobal);
	InitOOJSQuaternion(sContext, sGlobal);
	ooscript::defineFunction(sContext, sGlobal, "makeEntity", MakeEntity, 4, ooscript::PropertyFlag::None);
	ranrot_srand(12345);	// the game seeds its generator at startup
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
	ooscript::Value value = ooscript::undefinedValue();
	OO_CHECK(QuaternionToJSValue(sContext, make_quaternion(1, 2, 3, 4), &value));
	Quaternion q = kZeroQuaternion;
	OO_CHECK(JSValueToQuaternion(sContext, value, &q) && q.w == 1 && q.x == 2 && q.y == 3 && q.z == 4);
	OO_CHECK(JSQuaternionSetQuaternion(sContext, ooscript::toObject(value), make_quaternion(5, 6, 7, 8)));
	OO_CHECK(JSObjectGetQuaternion(sContext, ooscript::toObject(value), &q) && q.w == 5 && q.x == 6 && q.y == 7 && q.z == 8);
	OO_CHECK(!JSValueToQuaternion(sContext, ooscript::int32Value(3), &q));
	OO_CHECK(!JSObjectGetQuaternion(sContext, nullptr, &q));
	ooscript::Object made = JSQuaternionWithQuaternion(sContext, make_quaternion(0, 0, 0, 1));
	OO_CHECK(made != nullptr && JSObjectGetQuaternion(sContext, made, &q) && q.z == 1);
	unsigned consumed = 99;
	OO_CHECK(QuaternionFromArgumentList(sContext, "Test", "test", 1, &value, &q, &consumed) && consumed == 1 && q.w == 5);
	ooscript::Value four[4] = { ooscript::int32Value(1), ooscript::int32Value(2), ooscript::int32Value(3), ooscript::int32Value(4) };
	OO_CHECK(!QuaternionFromArgumentList(sContext, "Test", "test", 4, four, &q, &consumed) && consumed == 0);	// numbers only for the constructor
	ooscript::clearPendingException(sContext);
}


OO_TEST(nativeExceptions)
{
	// toString() is a native (OOJS_NATIVE_ENTER); an entity's -orientation that raises there is a
	// JS error, and a C++ exception is too.
	OO_CHECK_EVAL("Quaternion.prototype.toString.call(makeEntity(-1, 0, 0, 0))", "threw: Native exception: orientation boom");
	OO_CHECK_EVAL("Quaternion.prototype.toSource.call(makeEntity(-2, 0, 0, 0))", "threw: Native exception: cxx boom");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK(ooscript::isInRequest(sContext));
#if OOJS_PROFILE
	OO_CHECK_EQ(sProfileDepth, 0);
#endif
}


#if OO_DEBUG
OO_TEST(statistics)
{
	clearJSQuaternionStatistics();
	Eval("new Quaternion(1, 2, 3, 4).multiply(new Quaternion()).multiply([1, 2, 3, 4]).multiply(Quaternion.prototype)");
	// The report is kept in a local: a pointer into the temporary would dangle once the statement
	// ends (oo-zdxtn, an ASan stack-use-after-scope).
	const oo::PList reportNode = reportJSQuaternionStatistics();
	const std::string *report = reportNode.getIf<std::string>();
	OO_CHECK(report != nullptr);
	if (report != nullptr)
	{
		OO_CHECK(report->find("quaternion-to-quaternion conversions: ") == 0);
		OO_CHECK(report->find("     array-to-quaternion conversions: 1 (") != std::string::npos);
		OO_CHECK(report->find("       prototype-to-zero conversions: 1 (") != std::string::npos);
	}
	clearJSQuaternionStatistics();
	const oo::PList clearedNode = reportJSQuaternionStatistics();
	report = clearedNode.getIf<std::string>();
	OO_CHECK(report != nullptr && report->find("total: 0") != std::string::npos);
}
#endif


OO_TEST_MAIN()
