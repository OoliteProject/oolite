/*	test_OOJSPlanet.mm
	Unit tests for the Planet JS binding (src/Core/Scripting/OOJSPlanet.h/.mm) and its
	OOPlanetEntity category (whose forwarders are on the OOPlanetEntity facade since bead oo-9ht.92;
	this test's stand-in OOPlanetEntity forwards the same way): bead oo-7ixd, converted the way bead
	oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	QuickJS-ng context, links the game's own objects for the binding, the engine's
	class registry (OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm) and
	OOColor (a converted class, reached through its façade), and stands in for the classes the
	binding messages (Entity, OOPlanetEntity and the universe answer only the selectors the binding
	sends), for the Vector and Quaternion conversions (arrays [x, y, z] and [w, x, y, z] here) and
	for the engine functions the binding links against, with the engine headers' linkage. The expectations were written against the Objective-C file and run
	on it first; they pin the JS-visible behaviour (the twelve properties, the colours both ways, a
	texture that loads or does not, a moon, a non-planet, a native's exception) and what the
	category answers the engine. Run: tests/run.sh unit
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#import "OOColor.h"
#include "OOMaths.h"
#include "OOStellarBody.h"
#include "OOJSEngineCore.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

@class Universe;

@interface Entity: OOObject
{
@public
	Quaternion _orientation;
}
- (id) weakRefUnderlyingObject;
- (Quaternion) normalOrientation;
- (void) setOrientation:(Quaternion)quat;
@end

/*	A planet whose radius is 99 raises from -radius, one whose radius is 98 throws a C++ exception,
	so the test sees what an exception under a native becomes.
*/
@interface OOPlanetEntity: Entity
{
@public
	OOStellarBodyType _type;
	double _radius;
	std::optional<std::string> _name;
	OOColor *_airColor;
	OOColor *_illuminationColor;
	float _airColorMixRatio;
	float _airDensity;
	BOOL _hasAtmosphere;
	std::optional<std::string> _texture;
	double _rotationalVelocity;
	Vector _terminatorThresholdVector;
	int _textureLoads;
}
- (OOStellarBodyType) planetType;
- (double) radius;
- (std::optional<std::string>) cxx_name;
- (void) cxx_setName:(const std::optional<std::string> &)name;
- (OOColor *) airColor;
- (void) setAirColor:(OOColor *)newColor;
- (OOColor *) illuminationColor;
- (void) setIlluminationColor:(OOColor *)newColor;
- (float) airColorMixRatio;
- (void) setAirColorMixRatio:(float)newRatio;
- (float) airDensity;
- (void) setAirDensity:(float)newDensity;
- (BOOL) hasAtmosphere;
- (std::optional<std::string>) textureFileName;
- (BOOL) setUpPlanetFromTexture:(const std::optional<std::string> &)fileName;
- (double) rotationalVelocity;
- (void) setRotationalVelocity:(double)v;
- (Vector) terminatorThresholdVector;
- (void) setTerminatorThresholdVector:(Vector)newTerminatorThresholdVector;
@end

// The universe, as far as the binding asks it anything: its main planet.
@interface FakeUniverse: OOObject
{
@public
	id _planet;
}
- (id) planet;
@end

@interface Entity (OOJavaScriptExtensions)
- (JSClassID) oo_jsClassID;
- (std::optional<std::string>) cxx_oo_jsClassName;
- (BOOL) isVisibleToScripts;
@end


#import "OOJSPlanet.h"

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
- (Quaternion) normalOrientation  { return _orientation; }
- (void) setOrientation:(Quaternion)quat  { _orientation = quat; }

@end


@implementation OOPlanetEntity

- (OOStellarBodyType) planetType  { return _type; }
- (std::optional<std::string>) cxx_name  { return _name; }
- (void) cxx_setName:(const std::optional<std::string> &)name  { _name = name; }
- (OOColor *) airColor  { return _airColor; }
- (void) setAirColor:(OOColor *)newColor  { [_airColor release]; _airColor = [newColor retain]; }
- (OOColor *) illuminationColor  { return _illuminationColor; }
- (void) setIlluminationColor:(OOColor *)newColor  { [_illuminationColor release]; _illuminationColor = [newColor retain]; }
- (float) airColorMixRatio  { return _airColorMixRatio; }
- (void) setAirColorMixRatio:(float)newRatio  { _airColorMixRatio = newRatio; }
- (float) airDensity  { return _airDensity; }
- (void) setAirDensity:(float)newDensity  { _airDensity = newDensity; }
- (BOOL) hasAtmosphere  { return _hasAtmosphere; }
- (std::optional<std::string>) textureFileName  { return _texture; }
- (double) rotationalVelocity  { return _rotationalVelocity; }
- (void) setRotationalVelocity:(double)v  { _rotationalVelocity = v; }
- (Vector) terminatorThresholdVector  { return _terminatorThresholdVector; }
- (void) setTerminatorThresholdVector:(Vector)v  { _terminatorThresholdVector = v; }

- (BOOL) setUpPlanetFromTexture:(const std::optional<std::string> &)fileName
{
	_textureLoads++;
	if (!fileName.has_value() || *fileName == "missing.png")  return NO;
	_texture = fileName;
	return YES;
}

- (double) radius
{
	if (_radius == 99)  [OOException raise:OOInvalidArgumentException format:"radius %s", "boom"];
	if (_radius == 98)  throw std::runtime_error("cxx boom");
	return _radius;
}


// The binding's category, as the OOPlanetEntity facade forwards it (OOPlanetEntity+ObjCBridge.mm,
// bead oo-9ht.92): the engine sends these selectors to the wrapped object.
- (JSClassID) oo_jsClassID  { return ::JSPlanetClassID(); }
- (std::optional<std::string>) cxx_oo_jsClassName  { return ::OOJSPlanetJSClassName(self); }
- (BOOL) isVisibleToScripts  { return ::OOJSPlanetIsVisibleToScripts(self); }

@end


@implementation FakeUniverse

- (id) planet  { return _planet; }

@end


// MARK: What the rest of the engine provides ------------------------------------------------------

// The one context (OOJSAcquireContext(), which OOJSClasses.mm registers classes through).
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


// The engine's: the pending exception, else an uncatchable error, which ends the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// What the class registration (OOJSClasses.mm) asks of the engine: it reports what class set-up
// left pending (the test drops it), and records property IDs, interned for the life of the
// process, as the engine's.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
}


namespace {
std::string sLastWarning;
}

void cxx_OOJSReportWarning(JSContext *, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
	va_end(args);
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
// or an array of those. The value is owned by the caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		JSValue object = JS_NewArray(context);
		std::uint32_t i = 0;
		for (const oo::PList &element : *array)  JS_SetPropertyUint32(context, object, i++, OOJSValueFromPList(context, element));
		return object;
	}
	return JS_NULL;
}


// A JS value's plist form, as far as a colour description needs one: a string, a number, an array
// of those, or null.
oo::PList cxx_OOJSPListFromJSValue(JSContext *context, JSValueConst value)
{
	double number = 0;
	if (JS_IsString(value))  return oo::PList(cxx_OOStringFromJSValue(context, value).value_or(""));
	if (JS_IsNumber(value) && JS_ToFloat64(context, &number, value) == 0)  return oo::PList(number);
	if (JS_IsArray(value))
	{
		std::int64_t length = 0;
		JS_GetLength(context, value, &length);
		oo::PList::Array array;
		for (std::int64_t i = 0; i < length; i++)
		{
			JSValue element = JS_GetPropertyUint32(context, value, static_cast<std::uint32_t>(i));
			if (!JS_IsException(element))  array.push_back(cxx_OOJSPListFromJSValue(context, element));
			JS_FreeValue(context, element);
		}
		return oo::PList(std::move(array));
	}
	return oo::PList();
}


namespace {
JSClassID sFakeEntityClassID = 0;
JSClassDef sFakeEntityClass = {
	.class_name = "Entity",
	.finalizer = OOJSObjectWrapperFinalize,
};
std::map<JSClassID, int> sConverters;


// An array of numbers as JavaScript, and back: enough to see what the binding hands over and takes.
bool NumbersToJSValue(JSContext *context, const double *numbers, unsigned count, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	for (unsigned i = 0; i < count; i++)  JS_SetPropertyUint32(context, array, i, JS_NewNumber(context, numbers[i]));
	*outValue = array;
	return true;
}


bool JSValueToNumbers(JSContext *context, JSValueConst value, double *numbers, unsigned count)
{
	if (!JS_IsArray(value))  return false;
	for (unsigned i = 0; i < count; i++)
	{
		JSValue element = JS_GetPropertyUint32(context, value, i);
		const bool ok = !JS_IsException(element) && JS_ToFloat64(context, &numbers[i], element) == 0;
		JS_FreeValue(context, element);
		if (!ok)  return false;
	}
	return true;
}

} // namespace

Universe *gSharedUniverse = nil;


// A vector is the array [x, y, z] here, a quaternion [w, x, y, z].
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool JSValueToVector(JSContext *context, JSValueConst value, Vector *outVector)
{
	double v[3] = {};
	if (!JSValueToNumbers(context, value, v, 3))  return false;
	*outVector = make_vector(v[0], v[1], v[2]);
	return true;
}


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


// The engine's object getter: the JS class must be a subclass of the required one (the class
// registry's subclass table, OOJSClasses.mm), and the underlying object must be of the required
// Objective-C class.
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


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


// The test's entities live for the whole test; nothing is released when their objects go.
void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
}


bool QuaternionToJSValue(JSContext *context, Quaternion quaternion, JSValue *outValue)
{
	const double parts[4] = { quaternion.w, quaternion.x, quaternion.y, quaternion.z };
	return NumbersToJSValue(context, parts, 4, outValue);
}


bool JSValueToQuaternion(JSContext *context, JSValueConst value, Quaternion *outQuaternion)
{
	double q[4] = {};
	if (!JSValueToNumbers(context, value, q, 4))  return false;
	*outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
	return true;
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }
#endif

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


oo::PList OOJSBasicPrivateObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime;
JSContext *sContext;
JSValue sGlobal = JS_UNDEFINED;	// owned for the life of the test
OOPlanetEntity *sPlanet = nil;
OOPlanetEntity *sMoon = nil;
FakeUniverse *sUniverse = nil;


// An owned JS object of the class (its prototype the class's), the entity in its private slot.
JSValue JSValueForObject(JSClassID jsClass, Entity *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (JS_IsException(object))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));
		return JS_NULL;
	}
	JS_SetOpaque(object, entity);
	return object;
}


// A JS object for an entity, as -[Entity oo_jsValueInContext:] makes it: the class the entity's
// category names, and the entity in the private slot.
JSValue JSValueForEntity(Entity *entity)
{
	return JSValueForObject([entity oo_jsClassID], entity);
}


// Takes value.
void Define(const char *name, JSValue value)
{
	JS_SetPropertyStr(sContext, sGlobal, name, value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = JS_NewRuntime();
	JS_SetMemoryLimit(sRuntime, 8u * 1024u * 1024u);
	sContext = JS_NewContext(sRuntime);
	gOOJSMainThreadContext = sContext;
	sGlobal = JS_GetGlobalObject(sContext);
	OOJSRegisterClass(&sFakeEntityClassID, &sFakeEntityClass);
	OOJSInitClass(sContext, sGlobal, sFakeEntityClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0, nullptr, 0, nullptr, 0, nullptr, 0);
	InitOOJSPlanet(sContext, sGlobal);

	sPlanet = [[OOPlanetEntity alloc] init];	// kept for the life of the test
	sPlanet->_type = STELLAR_TYPE_NORMAL_PLANET;
	sPlanet->_radius = 5000;
	sPlanet->_name = "Lave";
	sPlanet->_airColor = [[OOColor colorWithRed:0.5f green:0.25f blue:1 alpha:1] retain];
	sPlanet->_airColorMixRatio = 0.5f;
	sPlanet->_airDensity = 0.75f;
	sPlanet->_hasAtmosphere = YES;
	sPlanet->_texture = "lave.png";
	sPlanet->_rotationalVelocity = 0.125;
	sPlanet->_terminatorThresholdVector = make_vector(0.25, 1, 2);
	sPlanet->_orientation = make_quaternion(1, 0, 0, 0);
	sMoon = [[OOPlanetEntity alloc] init];
	sMoon->_type = STELLAR_TYPE_MOON;
	sMoon->_radius = 1000;
	sUniverse = [[FakeUniverse alloc] init];
	sUniverse->_planet = sPlanet;
	gSharedUniverse = (Universe *)sUniverse;
	Define("planet", JSValueForEntity(sPlanet));
	Define("moon", JSValueForEntity(sMoon));
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
	const JSClassID planetClass = [sPlanet oo_jsClassID];
	OO_CHECK(planetClass != 0 && OOJSClassName(planetClass) != nullptr && std::strcmp(OOJSClassName(planetClass), "Planet") == 0);
	JSValue prototype = JS_GetClassProto(sContext, planetClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(planetClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[planetClass], 1);
	OO_CHECK_EVAL("typeof Planet", "function");
	OO_CHECK_EVAL("new Planet()", "threw: unconstructable");
	OO_CHECK_EVAL("Object.getPrototypeOf(Planet.prototype) === Entity.prototype", "true");
	OO_CHECK_EVAL("planet instanceof Planet && moon instanceof Planet", "true");
}


OO_TEST(category)
{
	SetUpContext();
	// A planet or a moon is visible to scripts and says which it is; any other stellar body is not.
	OO_CHECK([sPlanet cxx_oo_jsClassName] == std::optional<std::string>("Planet"));
	OO_CHECK([sPlanet isVisibleToScripts]);
	OO_CHECK([sMoon cxx_oo_jsClassName] == std::optional<std::string>("Moon"));
	OO_CHECK([sMoon isVisibleToScripts]);
	OOPlanetEntity *mini = [[[OOPlanetEntity alloc] init] autorelease];
	mini->_type = STELLAR_TYPE_MINIATURE;
	OO_CHECK([mini cxx_oo_jsClassName] == std::optional<std::string>("Unknown"));
	OO_CHECK(![mini isVisibleToScripts]);
	mini->_type = STELLAR_TYPE_SUN;
	OO_CHECK(![mini isVisibleToScripts]);
}


OO_TEST(properties)
{
	SetUpContext();
	OO_CHECK_EVAL("planet.airColor", "0.5,0.25,1,1");
	OO_CHECK_EVAL("planet.airColorMixRatio", "0.5");
	OO_CHECK_EVAL("planet.airDensity", "0.75");
	OO_CHECK_EVAL("planet.hasAtmosphere", "true");
	OO_CHECK_EVAL("planet.illuminationColor", "null");
	OO_CHECK_EVAL("planet.isMainPlanet", "true");
	OO_CHECK_EVAL("moon.isMainPlanet", "false");
	OO_CHECK_EVAL("planet.name", "Lave");
	OO_CHECK_EVAL("moon.name", "null");
	OO_CHECK_EVAL("planet.radius", "5000");
	OO_CHECK_EVAL("planet.rotationalVelocity", "0.125");
	OO_CHECK_EVAL("planet.texture", "lave.png");
	OO_CHECK_EVAL("moon.texture", "null");
	OO_CHECK_EVAL("planet.orientation", "1,0,0,0");
	OO_CHECK_EVAL("planet.terminatorThresholdVector", "0.25,1,2");
	OO_CHECK_EVAL("moon.hasAtmosphere", "false");
	OO_CHECK_EVAL("Object.keys(Planet.prototype).join()", "airColor,airColorMixRatio,airDensity,hasAtmosphere,illuminationColor,isMainPlanet,name,radius,rotationalVelocity,texture,orientation,terminatorThresholdVector");
	// Read-only.
	OO_CHECK_EVAL("(function () { planet.radius = 1; return planet.radius; })()", "5000");
	OO_CHECK_EVAL("(function () { planet.isMainPlanet = false; return planet.isMainPlanet; })()", "true");
}


OO_TEST(setters)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { planet.airColorMixRatio = 0.25; return planet.airColorMixRatio; })()", "0.25");
	OO_CHECK_EVAL("(function () { planet.airColorMixRatio = 'x'; return planet.airColorMixRatio; })()", "NaN");
	sPlanet->_airColorMixRatio = 0.5f;
	OO_CHECK_EVAL("(function () { planet.airDensity = 2; return planet.airDensity; })()", "2");
	OO_CHECK_EVAL("(function () { planet.rotationalVelocity = -0.5; return planet.rotationalVelocity; })()", "-0.5");
	OO_CHECK_EVAL("(function () { planet.name = 'Diso'; return planet.name; })()", "Diso");
	OO_CHECK_EVAL("(function () { planet.name = null; return planet.name; })()", "null");
	OO_CHECK_EVAL("(function () { planet.name = 7; return planet.name; })()", "7");
	sPlanet->_name = "Lave";
	// An orientation is normalised.
	OO_CHECK_EVAL("(function () { planet.orientation = [2, 0, 0, 0]; return planet.orientation; })()", "1,0,0,0");
	OO_CHECK_EVAL("(function () { planet.orientation = [0, 0, 0, -2]; return planet.orientation; })()", "0,0,0,-1");
	OO_CHECK_EVAL("(function () { planet.orientation = 'x'; return planet.orientation; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { planet.terminatorThresholdVector = [1, 2, 3]; return planet.terminatorThresholdVector; })()", "1,2,3");
	OO_CHECK_EVAL("(function () { planet.terminatorThresholdVector = 5; return planet.terminatorThresholdVector; })()", "threw: bad property value");
}


OO_TEST(colors)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { planet.airColor = [0, 1, 0]; return planet.airColor; })()", "0,1,0,1");
	OO_CHECK_EVAL("(function () { planet.airColor = 'redColor'; return planet.airColor; })()", "1,0,0,1");
	OO_CHECK_EVAL("(function () { planet.airColor = null; return planet.airColor; })()", "null");
	OO_CHECK_EVAL("(function () { planet.airColor = 'not a colour'; return planet.airColor; })()", "threw: bad property value");
	OO_CHECK_EVAL("(function () { planet.illuminationColor = [0.25, 0.5, 0.75, 0.5]; return planet.illuminationColor; })()", "0.25,0.5,0.75,0.5");
	OO_CHECK_EVAL("(function () { planet.illuminationColor = null; return planet.illuminationColor; })()", "null");
	OO_CHECK_EVAL("(function () { planet.illuminationColor = {}; return planet.illuminationColor; })()", "threw: bad property value");
}


OO_TEST(texture)
{
	SetUpContext();
	sPlanet->_textureLoads = 0;
	sLastWarning.clear();
	OO_CHECK_EVAL("(function () { planet.texture = 'diso.png'; return planet.texture; })()", "diso.png");
	OO_CHECK_EQ(sPlanet->_textureLoads, 1);
	OO_CHECK_EQ(sLastWarning, std::string());
	// A texture that is not found keeps the old one, with a warning; no exception.
	OO_CHECK_EVAL("(function () { planet.texture = 'missing.png'; return planet.texture; })()", "diso.png");
	OO_CHECK_EQ(sPlanet->_textureLoads, 2);
	OO_CHECK_EQ(sLastWarning, std::string("Cannot find texture \"missing.png\". Value not set."));
	// No texture name: nothing is loaded.
	OO_CHECK_EVAL("(function () { planet.texture = null; return planet.texture; })()", "diso.png");
	OO_CHECK_EQ(sPlanet->_textureLoads, 2);
	OO_CHECK_EQ(sLastWarning, std::string("Expected texture string. Value not set."));
	OO_CHECK_EQ(sLimiterPauses, 0);
	sPlanet->_texture = "lave.png";
}


OO_TEST(otherObjects)
{
	SetUpContext();
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Planet.prototype, 'radius').get.call(plainEntity)", "threw: Native method expected Planet, got [object Object].");
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Planet.prototype, 'name').set.call({}, 'x')", "threw: Native method expected Planet, got [object Object].");
	// No class tags its prototype with Symbol.toStringTag (the old scripting layer's backend did):
	// the object is described as QuickJS describes it.
	OO_CHECK_EVAL("Object.create(Planet.prototype).radius", "threw: Native method expected Planet, got [object Object].");
	OO_CHECK_EVAL("Planet.prototype.radius", "0");	// the prototype has no planet: a message to nil
	OO_CHECK_EVAL("Planet.prototype.name", "null");
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	// The property getter is a native (OOJS_NATIVE_ENTER): a raise from the entity is a JS error,
	// and so is a C++ exception.
	sPlanet->_radius = 99;
	OO_CHECK_EVAL("planet.radius", "threw: Native exception: radius boom");
	sPlanet->_radius = 98;
	OO_CHECK_EVAL("planet.radius", "threw: Native exception: cxx boom");
	sPlanet->_radius = 5000;
	OO_CHECK_EVAL("planet.radius", "5000");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
