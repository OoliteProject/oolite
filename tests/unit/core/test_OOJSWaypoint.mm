/*	test_OOJSWaypoint.mm
	Unit tests for the Waypoint JS binding (src/Core/Scripting/OOJSWaypoint.h/.mm) and its
	OOWaypointEntity category (OOJSWaypoint+ObjCBridge.mm): bead oo-mae5, converted the way bead
	oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, its bridge, the engine's
	class registration (OOJSClasses.mm) and the engine's exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the classes the binding messages (Entity and
	OOWaypointEntity, and the universe's beacon list and the player's compass, answer only the
	selectors the binding sends), for the Quaternion conversions (a quaternion is the array
	[w, x, y, z] here) and for the engine functions the binding links against, with the engine
	headers' linkage. The expectations were written against the Objective-C file and run on it
	first; they pin the JS-visible behaviour (the four properties, a beacon code that registers or
	clears a beacon, an unoriented waypoint, a non-waypoint, a native's exception) and what the
	category answers the engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOMaths.h"
#include "OOTypes.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

@class Universe, PlayerEntity;

@interface Entity: OOObject
{
@public
	std::optional<std::string> _beaconCode;
	std::optional<std::string> _beaconLabel;
	Quaternion _orientation;
}
- (id) weakRefUnderlyingObject;
- (std::optional<std::string>) beaconCode;
- (void) setBeaconCode:(const std::optional<std::string> &)bcode;
- (std::optional<std::string>) beaconLabel;
- (void) setBeaconLabel:(const std::optional<std::string> &)blabel;
- (BOOL) isBeacon;
- (Quaternion) orientation;
- (void) setNormalOrientation:(Quaternion)quat;
@end

/*	A waypoint whose size is 99 raises from -size, one whose size is 98 throws a C++ exception, so
	the test sees what an exception under a native becomes.
*/
@interface OOWaypointEntity: Entity
{
@public
	BOOL _oriented;
	OOScalar _size;
}
- (BOOL) oriented;
- (OOScalar) size;
- (void) setSize:(OOScalar)newSize;
@end

// The universe's beacon list and the player's compass: what the binding tells them.
@interface FakeGame: OOObject
{
@public
	id _nextBeacon;
	int _cleared;
	int _added;
	int _compassMode;
}
- (void) setNextBeacon:(Entity *)beacon;
- (void) clearBeacon:(Entity *)beacon;
- (Entity *) nextBeacon;
- (void) setCompassMode:(OOCompassMode)mode;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
- (BOOL) isVisibleToScripts;
@end


#import "OOJSWaypoint.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


@implementation Entity

- (id) weakRefUnderlyingObject  { return self; }
- (std::optional<std::string>) beaconCode  { return _beaconCode; }
- (void) setBeaconCode:(const std::optional<std::string> &)bcode  { _beaconCode = bcode; }
- (std::optional<std::string>) beaconLabel  { return _beaconLabel; }
- (void) setBeaconLabel:(const std::optional<std::string> &)blabel  { _beaconLabel = blabel; }
- (BOOL) isBeacon  { return _beaconCode.has_value() && !_beaconCode->empty(); }
- (Quaternion) orientation  { return _orientation; }
- (void) setNormalOrientation:(Quaternion)quat  { _orientation = quat; }

@end


@implementation OOWaypointEntity

- (BOOL) oriented  { return _oriented; }
- (void) setSize:(OOScalar)newSize  { _size = newSize; }

- (OOScalar) size
{
	if (_size == 99)  [OOException raise:OOInvalidArgumentException format:"size %s", "boom"];
	if (_size == 98)  throw std::runtime_error("cxx boom");
	return _size;
}

@end


@implementation FakeGame

- (void) setNextBeacon:(Entity *)beacon  { _added++; (void)beacon; }
- (void) clearBeacon:(Entity *)beacon  { _cleared++; beacon->_beaconCode = std::nullopt; }
- (Entity *) nextBeacon  { return _nextBeacon; }
- (void) setCompassMode:(OOCompassMode)mode  { _compassMode = static_cast<int>(mode); }

@end


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;	// the engine's


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


// What the class registration (OOJSClasses.mm) asks of the engine.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
}


// As the engine's: a native that fails with nothing reported ends the script with an uncatchable
// error.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
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


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (const double *number = plist.getIf<double>())  return JS_NewNumber(context, *number);
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t index = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, object, index++, OOJSValueFromPList(context, element));
		return object;
	}
	return JS_NULL;
}


namespace {
JSClassID sFakeEntityClassID = 0;
JSClassDef sFakeEntityClass = { .class_name = "Entity" };
std::map<JSClassID, int> sConverters;
} // namespace

Universe *gSharedUniverse = nil;
PlayerEntity *gOOPlayer = nil;


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter: the JS class must be a subclass of the required one, and the
// underlying object must be of the required Objective-C class.
BOOL OOJSObjectGetterImplPRIVATE(JSContext *context, JSValueConst object, JSClassID requiredClassID, Class requiredObjCClass, const char *, id *outObject)
{
	if (!OOJSIsSubclass(JS_GetClassID(object), requiredClassID))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", OOJSClassName(requiredClassID), cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
		return NO;
	}
	JSClassID ignored;
	*outObject = [(id)JS_GetAnyOpaque(object, &ignored) weakRefUnderlyingObject];
	if (*outObject != nil && ![*outObject isKindOfClass:requiredObjCClass])
	{
		cxx_OOJSReportError(context, "Native method expected %s from %s.", class_getName(requiredObjCClass), OOJSClassName(requiredClassID));
		*outObject = nil;
		return NO;
	}
	return YES;
}


JSValue OOJSValueFromNativeObject(JSContext *, id)
{
	return JS_UNDEFINED;
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


// A quaternion is the array [w, x, y, z] here: enough to see what the binding hands over and takes.
bool QuaternionToJSValue(JSContext *context, Quaternion quaternion, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	JS_SetPropertyUint32(context, array, 0, JS_NewNumber(context, quaternion.w));
	JS_SetPropertyUint32(context, array, 1, JS_NewNumber(context, quaternion.x));
	JS_SetPropertyUint32(context, array, 2, JS_NewNumber(context, quaternion.y));
	JS_SetPropertyUint32(context, array, 3, JS_NewNumber(context, quaternion.z));
	*outValue = array;
	return true;
}


bool JSValueToQuaternion(JSContext *context, JSValueConst value, Quaternion *outQuaternion)
{
	double q[4] = {};
	if (!JS_IsArray(value))  return false;
	for (std::uint32_t i = 0; i < 4; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &q[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	*outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
	return true;
}



int sLimiterPauses = 0;
int sProfileDepth = 0;

void OOJSProfileEnter(struct OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(struct OOJSProfileStackFrame *)  { sProfileDepth--; }

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
OOWaypointEntity *sWaypoint = nil;
FakeGame *sGame = nil;


// A JS object of the class, with the class's prototype and the entity in the private slot; owned
// by the caller.
JSValue JSValueForObject(JSClassID jsClass, Entity *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (JS_IsException(object) || JS_SetOpaque(object, entity) != 0)
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
	return object;
}


// A JS object for an entity, as -[Entity oo_jsValueInContext:] makes it: the class the entity's
// category names, and the entity in the private slot.
JSValue JSValueForEntity(Entity *entity)
{
	return JSValueForObject([entity oo_jsClassID], entity);
}


// Defines a global; takes value's reference.
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;	// the class registration's runtime
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeEntityClassID, &sFakeEntityClass);
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	InitOOJSWaypoint(sContext, sGlobal);

	sGame = [[FakeGame alloc] init];	// kept for the life of the test
	gSharedUniverse = (Universe *)sGame;
	gOOPlayer = (PlayerEntity *)sGame;
	sWaypoint = [[OOWaypointEntity alloc] init];
	sWaypoint->_beaconLabel = "Label";
	sWaypoint->_orientation = make_quaternion(0, 1, 0, 0);
	sWaypoint->_oriented = YES;
	sWaypoint->_size = 20;
	Define("waypoint", JSValueForEntity(sWaypoint));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, [[Entity alloc] init]));
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

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	JSClassID waypointClass = [sWaypoint oo_jsClassID];
	OO_CHECK(waypointClass != 0 && OOJSClassName(waypointClass) != nullptr && std::strcmp(OOJSClassName(waypointClass), "Waypoint") == 0);
	JSValue prototype = JS_GetClassProto(sContext, waypointClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(waypointClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[waypointClass], 1);
	OO_CHECK([sWaypoint cxx_oo_jsClassName] == std::optional<std::string>("Waypoint"));
	OO_CHECK([sWaypoint isVisibleToScripts]);
	OO_CHECK_EVAL("typeof Waypoint", "function");
	OO_CHECK_EVAL("new Waypoint()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Waypoint.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("waypoint instanceof Waypoint", "true");
}


OO_TEST(properties)
{
	OO_CHECK_EVAL("waypoint.beaconCode", "null");
	OO_CHECK_EVAL("waypoint.beaconLabel", "Label");
	OO_CHECK_EVAL("waypoint.orientation", "0,1,0,0");
	OO_CHECK_EVAL("waypoint.size", "20");
	OO_CHECK_EVAL("Object.keys(Waypoint.prototype).join()", "beaconCode,beaconLabel,orientation,size");
	sWaypoint->_oriented = NO;
	OO_CHECK_EVAL("waypoint.orientation", "0,0,0,0");	// unoriented: the zero quaternion
	sWaypoint->_oriented = YES;
}


OO_TEST(setters)
{
	OO_CHECK_EVAL("(function () { waypoint.beaconLabel = 'Other'; return waypoint.beaconLabel; })()", "Other");
	OO_CHECK_EVAL("(function () { waypoint.beaconLabel = null; return waypoint.beaconLabel; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { waypoint.orientation = [1, 0, 0, 0]; return waypoint.orientation; })()", "1,0,0,0");
	OO_CHECK_EVAL("(function () { waypoint.orientation = 'up'; return waypoint.orientation; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { waypoint.size = 5.5; return waypoint.size; })()", "5.5");
	OO_CHECK_EVAL("(function () { waypoint.size = 0; return waypoint.size; })()", "threw: bad property value");
	OO_CHECK_EVAL("waypoint.size", "5.5");
}


OO_TEST(beaconCode)
{
	SetUpContext();
	// Not a beacon yet: setting a code makes it one and tells the universe.
	int added = sGame->_added;
	OO_CHECK_EVAL("(function () { waypoint.beaconCode = 'W'; return waypoint.beaconCode; })()", "W");
	OO_CHECK_EQ(sGame->_added, added + 1);
	// Already a beacon: a new code is just set.
	OO_CHECK_EVAL("(function () { waypoint.beaconCode = 'X'; return waypoint.beaconCode; })()", "X");
	OO_CHECK_EQ(sGame->_added, added + 1);
	// An empty code clears the beacon; the compass leaves it if it pointed there.
	sGame->_nextBeacon = sWaypoint;
	sGame->_compassMode = -1;
	int cleared = sGame->_cleared;
	OO_CHECK_EVAL("(function () { waypoint.beaconCode = ''; return waypoint.beaconCode; })()", "null");
	OO_CHECK_EQ(sGame->_cleared, cleared + 1);
	OO_CHECK_EQ(sGame->_compassMode, static_cast<int>(COMPASS_MODE_PLANET));
	// Clearing a waypoint that is not a beacon does nothing.
	OO_CHECK_EVAL("(function () { waypoint.beaconCode = null; return waypoint.beaconCode; })()", "null");
	OO_CHECK_EQ(sGame->_cleared, cleared + 1);
	sGame->_nextBeacon = nil;
}


OO_TEST(otherObjects)
{
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Waypoint.prototype, 'size').get.call(plainEntity)", "<evaluation failed>");
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Waypoint.prototype, 'size').get.call({})", "threw: Native method expected Entity, got [object Object].");
	OO_CHECK_EVAL("Waypoint.prototype.size", "<evaluation failed>");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sWaypoint->_size = 99;
	OO_CHECK_EVAL("waypoint.size", "threw: Native exception: size boom");
	sWaypoint->_size = 98;
	OO_CHECK_EVAL("waypoint.size", "threw: Native exception: cxx boom");
	sWaypoint->_size = 20;
	OO_CHECK_EVAL("waypoint.size", "20");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
