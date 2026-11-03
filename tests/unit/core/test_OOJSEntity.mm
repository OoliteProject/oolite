/*	test_OOJSEntity.mm
	Unit tests for the Entity JS binding (src/Core/Scripting/OOJSEntity.h/.mm): bead oo-tq53,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment oo-ppc).

	As test_OOJSSun.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real QuickJS-ng
	context, links the game's own objects for the binding, the engine's class registration
	(OOJSClasses.mm), its exception translator (OOJSEngineNativeWrappers.mm), the constant strings
	(OOConstToJSString.cpp) and the maths it calls, and stands in for the entity classes
	(Entity and ShipEntity answer only the selectors the binding sends; the binding messages the
	Objective-C Entity, the façade every entity still is, and calls a ship's C++ part, C++ since
	bead oo-9ht.144), for the vector and quaternion conversions
	(a vector is the array [x, y, z] here, a quaternion [w, x, y, z]) and for the engine functions
	the binding links against, with the engine headers' signatures (OOJSEngineCore.h, upstream
	#768's QuickJS-ng API). The expectations were written
	against the Objective-C file and run on it first; they pin the JS-visible behaviour (every
	property both ways, the owner, a stale entity and the escape-pod player, the prototype,
	dumpState(), a native's exception) and the C functions other bindings call
	(JSValueToEntity(), EntityFromArgumentList()). Run: bash tools/check-core-tests.sh
*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"
#include <objc/runtime.h>
#include "OOMaths.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/String.hpp"
#import "OOConstToJSString.h"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

/*	An entity: its state is ivars here, answered as Entity's selectors answer it (GLfloat is float).
	One whose mass is 99 raises from -mass, one whose mass is 98 throws a C++ exception, so the test
	sees what an exception under a native becomes.
*/
namespace cxx {
class Entity : public oo::RefCounted	// the C++ root, as far as a ship's part needs it
{
public:
	virtual ~Entity();
};
}	// namespace cxx

@interface Entity: OOObject
{
@public
	oo::Ref<cxx::Entity> _cxxEntity;	// the C++ part (oo::ToCxx reads it): a ship's
	float _collisionRadius;
	HPVector _position;
	Quaternion _orientation;
	OOEntityStatus _status;
	OOScanClass _scanClass;
	float _mass;
	id _owner;
	float _energy;
	float _maxEnergy;
	float _distanceTravelled;
	float _spawnTime;
	BOOL _isShip, _isStation, _isDock, _isSubEntity, _isPlayer, _isPlanet, _isSun, _isSunlit;
	BOOL _isVisible, _isVisualEffect, _isWormhole, _isInSpace;
	int _dumps;
	int _positionSets;
}
- (id) weakRefUnderlyingObject;
- (float) collisionRadius;
- (HPVector) position;
- (void) setPosition:(HPVector)posn;
- (Quaternion) normalOrientation;
- (void) setNormalOrientation:(Quaternion)quat;
- (OOEntityStatus) status;
- (OOScanClass) scanClass;
- (void) setScanClass:(OOScanClass)sClass;
- (float) mass;
- (id) owner;
- (float) energy;
- (void) setEnergy:(float)amount;
- (float) maxEnergy;
- (void) setMaxEnergy:(float)amount;
- (float) distanceTravelled;
- (float) spawnTime;
- (BOOL) isShip;
- (BOOL) isStation;
- (BOOL) isDock;
- (BOOL) isSubEntity;
- (BOOL) isPlayer;
- (BOOL) isPlanet;
- (BOOL) isSun;
- (BOOL) isSunlit;
- (BOOL) isVisible;
- (BOOL) isVisualEffect;
- (BOOL) isWormhole;
- (BOOL) isInSpace;
- (void) dumpState;
@end

// A ship: C++ since bead oo-9ht.144 deleted the Objective-C ship this stood in for, the C++ part of
// an entity's object, declared as ShipEntity.h declares it (the test imports no game header that
// defines the class), with the stand-in's answers.
class ShipEntity : public cxx::Entity
{
public:
	void resetExhaustPlumes();
	void forceAegisCheck();

	int _plumeResets = 0;
	int _aegisChecks = 0;
};


#include "OOJSEngineCore.h"
#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


// The binding's C API (OOJSEntity.h, which imports the engine and universe headers, so the test
// names what it calls itself). They returned BOOL, which is returned as bool is.
void InitOOJSEntity(JSContext *context, JSValueConst global);
bool JSValueToEntity(JSContext *context, JSValueConst value, Entity **outEntity);
JSClassID JSEntityClassID(void);
bool EntityFromArgumentList(JSContext *context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, int argc, JSValueConst *argv, Entity **outEntity, int *outConsumed);


@implementation Entity

- (id) weakRefUnderlyingObject  { return self; }
- (float) collisionRadius  { return _collisionRadius; }
- (HPVector) position  { return _position; }
- (void) setPosition:(HPVector)posn  { _position = posn; _positionSets++; }
- (Quaternion) normalOrientation  { return _orientation; }
- (void) setNormalOrientation:(Quaternion)quat  { _orientation = quat; }
- (OOEntityStatus) status  { return _status; }
- (OOScanClass) scanClass  { return _scanClass; }
- (void) setScanClass:(OOScanClass)sClass  { _scanClass = sClass; }

- (float) mass
{
	if (_mass == 99)  [OOException raise:OOInvalidArgumentException format:"mass %s", "boom"];
	if (_mass == 98)  throw std::runtime_error("cxx boom");
	return _mass;
}

- (id) owner  { return _owner; }
- (float) energy  { return _energy; }
- (void) setEnergy:(float)amount  { _energy = amount; }
- (float) maxEnergy  { return _maxEnergy; }
- (void) setMaxEnergy:(float)amount  { _maxEnergy = amount; }
- (float) distanceTravelled  { return _distanceTravelled; }
- (float) spawnTime  { return _spawnTime; }
- (BOOL) isShip  { return _isShip; }
- (BOOL) isStation  { return _isStation; }
- (BOOL) isDock  { return _isDock; }
- (BOOL) isSubEntity  { return _isSubEntity; }
- (BOOL) isPlayer  { return _isPlayer; }
- (BOOL) isPlanet  { return _isPlanet; }
- (BOOL) isSun  { return _isSun; }
- (BOOL) isSunlit  { return _isSunlit; }
- (BOOL) isVisible  { return _isVisible; }
- (BOOL) isVisualEffect  { return _isVisualEffect; }
- (BOOL) isWormhole  { return _isWormhole; }
- (BOOL) isInSpace  { return _isInSpace; }
- (void) dumpState  { _dumps++; }

@end


cxx::Entity::~Entity() = default;
void ShipEntity::resetExhaustPlumes()  { _plumeResets++; }
void ShipEntity::forceAegisCheck()  { _aegisChecks++; }


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


namespace {
std::string sLastWarning;
int sParameterErrors = 0;
}

void cxx_OOJSReportWarning(JSContext *, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
	va_end(args);
}


// As the engine's: the pending exception is reported (here, dropped) and cleared.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// As the engine's: the pending exception, else an uncatchable error that stops the script.
JSValue OOJSNativeFailure(JSContext *context)
{
	if (JS_HasException(context))  return JS_EXCEPTION;
	JSValue error = JS_NewError(context);
	JS_SetUncatchableError(context, error);
	return JS_Throw(context, error);
}


// Property IDs are interned for the life of the process (never freed), as the class registry
// (OOJSClasses.mm, linked) interns the class's property names.
JSAtom cxx_OOJSIDFromString(const std::string &string)
{
	return JS_NewAtomLen(OOJSAcquireContext(), string.data(), string.size());
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


std::string cxx_OOJSDescribeValue(JSContext *context, JSValueConst value, BOOL abbreviateObjects)
{
	return std::string(abbreviateObjects ? "abbr:" : "full:") + cxx_OOStringFromJSValue(context, value).value_or("null");
}


void OOLogGenericParameterErrorForFunction(const char *inFunction)
{
	(void)inFunction;
	sParameterErrors++;
}


namespace {
std::map<JSClassID, int> sConverters;
std::map<Entity *, JSValue> sEntityObjects;	// each holds a reference for the life of the test
JSContext *sContext = nullptr;


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


// An entity's JS object, as -[Entity oo_jsValueInContext:] makes it: the Entity class, and the
// entity in the private slot. One per entity; owned by the caller.
JSValue JSValueForEntity(Entity *entity)
{
	auto found = sEntityObjects.find(entity);
	if (found == sEntityObjects.end())
	{
		JSValue object = JS_NewObjectClass(sContext, static_cast<int>(JSEntityClassID()));
		if (JS_IsException(object))  return JS_NULL;
		if (JS_SetOpaque(object, entity) != 0)
		{
			JS_FreeValue(sContext, object);
			return JS_NULL;
		}
		found = sEntityObjects.emplace(entity, object).first;
	}
	return JS_DupValue(sContext, found->second);
}

} // namespace

Entity *gOOJSPlayerIfStale = nil;


bool HPVectorToJSValue(JSContext *context, HPVector vector, JSValue *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool JSValueToHPVector(JSContext *context, JSValueConst value, HPVector *outVector)
{
	double v[3] = {};
	if (!JSValueToNumbers(context, value, v, 3))  return false;
	*outVector = make_HPvector(v[0], v[1], v[2]);
	return true;
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


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	cxx_OOJSReportError(context, "bad property value");
}


// The JS class check (OOJSIsSubclass) is the class registry's (OOJSClasses.mm, linked).

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
		const char *className = OOJSClassName(requiredClassID);
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", className != nullptr ? className : "(null)", cxx_OOStringFromJSValue(context, object).value_or("(null)").c_str());
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


// What the engine makes of a native object: an entity's own JS object, null for nil. Owned by the
// caller.
JSValue OOJSValueFromNativeObject(JSContext *, id object)
{
	if (object == nil)  return JS_NULL;
	if ([object isKindOfClass:[Entity class]])  return JSValueForEntity(object);
	return JS_UNDEFINED;
}


JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[Entity]");
}


JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	cxx_OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
}


void OOJSObjectWrapperFinalize(JSRuntime *, JSValueConst)
{
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

JSRuntime *sRuntime = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
Entity *sShip = nil;	// a ship's object and its C++ part (the Objective-C ship until bead oo-9ht.144)
ShipEntity *sShipPart = nullptr;
Entity *sRock = nil;
Entity *sMother = nil;


// Defines a global; takes value's reference.
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
	OOConstToJSStringInit(sContext);
	InitOOJSEntity(sContext, sGlobal);

	// Kept for the life of the test.
	sMother = [[Entity alloc] init];
	sMother->_cxxEntity = oo::makeRef<ShipEntity>();
	sMother->_isShip = YES;
	sMother->_isStation = YES;
	sMother->_status = STATUS_ACTIVE;
	sMother->_scanClass = CLASS_STATION;

	sShip = [[Entity alloc] init];
	sShip->_cxxEntity = oo::makeRef<ShipEntity>();
	sShipPart = static_cast<ShipEntity *>(sShip->_cxxEntity.get());
	sShip->_collisionRadius = 40.5f;
	sShip->_position = make_HPvector(1000, -2000, 3000.5);
	sShip->_orientation = kIdentityQuaternion;
	sShip->_status = STATUS_IN_FLIGHT;
	sShip->_scanClass = CLASS_NEUTRAL;
	sShip->_mass = 75000;
	sShip->_owner = sMother;
	sShip->_energy = 200;
	sShip->_maxEnergy = 256;
	sShip->_distanceTravelled = 12.5f;
	sShip->_spawnTime = 3.25f;
	sShip->_isShip = YES;
	sShip->_isSunlit = YES;
	sShip->_isVisible = YES;
	sShip->_isInSpace = YES;

	sRock = [[Entity alloc] init];
	sRock->_status = STATUS_ACTIVE;
	sRock->_scanClass = CLASS_ROCK;
	sRock->_maxEnergy = 10;
	sRock->_owner = sRock;	// its own owner: answered as null

	Define("ship", JSValueForEntity(sShip));
	Define("mother", JSValueForEntity(sMother));
	Define("rock", JSValueForEntity(sRock));
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
	OO_CHECK_EQ(sConverters[JSEntityClassID()], 1);
	OO_CHECK(OOJSClassName(JSEntityClassID()) != nullptr && std::strcmp(OOJSClassName(JSEntityClassID()), "Entity") == 0);
	OO_CHECK_EVAL("typeof Entity", "function");
	OO_CHECK_EVAL("new Entity()", "threw: unconstructable");
	OO_CHECK_EVAL("ship instanceof Entity && Object.getPrototypeOf(ship) === Entity.prototype", "true");
	OO_CHECK_EVAL("Object.keys(Entity.prototype).join()",
				  "collisionRadius,distanceTravelled,energy,heading,mass,maxEnergy,orientation,owner,position,scanClass,spawnTime,status,isPlanet,isPlayer,isShip,isDock,isStation,isSubEntity,isSun,isSunlit,isValid,isInSpace,isVisible,isVisualEffect,isWormhole");
	OO_CHECK_EVAL("String(ship)", "[Entity]");
}


OO_TEST(readProperties)
{
	SetUpContext();
	OO_CHECK_EVAL("ship.collisionRadius", "40.5");
	OO_CHECK_EVAL("JSON.stringify(ship.position)", "[1000,-2000,3000.5]");
	OO_CHECK_EVAL("JSON.stringify(ship.orientation)", "[1,0,0,0]");
	OO_CHECK_EVAL("JSON.stringify(ship.heading)", "[0,0,1]");
	OO_CHECK_EVAL("ship.status", "STATUS_IN_FLIGHT");
	OO_CHECK_EVAL("ship.scanClass", "CLASS_NEUTRAL");
	OO_CHECK_EVAL("rock.scanClass", "CLASS_ROCK");
	OO_CHECK_EVAL("ship.mass", "75000");
	OO_CHECK_EVAL("ship.energy + ':' + ship.maxEnergy", "200:256");
	OO_CHECK_EVAL("ship.distanceTravelled + ':' + ship.spawnTime", "12.5:3.25");
	OO_CHECK_EVAL("ship.owner === mother", "true");
	OO_CHECK_EVAL("rock.owner", "null");	// its own owner
	OO_CHECK_EVAL("mother.owner", "null");
	OO_CHECK_EVAL("[ship.isShip, ship.isStation, ship.isDock, ship.isSubEntity, ship.isPlayer, ship.isPlanet, ship.isSun].join()",
				  "true,false,false,false,false,false,false");
	OO_CHECK_EVAL("[ship.isSunlit, ship.isVisible, ship.isVisualEffect, ship.isWormhole, ship.isInSpace, ship.isValid].join()",
				  "true,true,false,false,true,true");
	OO_CHECK_EVAL("[mother.isShip, mother.isStation, rock.isShip, rock.isInSpace].join()", "true,true,false,false");
	// A dead entity is not valid, and says so.
	sRock->_status = STATUS_DEAD;
	OO_CHECK_EVAL("rock.isValid + ':' + rock.status", "false:STATUS_DEAD");
	sRock->_status = STATUS_ACTIVE;
}


OO_TEST(writeProperties)
{
	SetUpContext();
	OO_CHECK_EVAL("(function () { ship.position = [1, 2, 3]; return JSON.stringify(ship.position); })()", "[1,2,3]");
	OO_CHECK_EQ(sShipPart->_plumeResets, 1);	// a ship's plumes and aegis follow it
	OO_CHECK_EQ(sShipPart->_aegisChecks, 1);
	OO_CHECK_EVAL("(function () { rock.position = [4, 5, 6]; return JSON.stringify(rock.position); })()", "[4,5,6]");
	OO_CHECK_EQ(sRock->_positionSets, 1);
	OO_CHECK_EVAL("(function () { ship.position = 'here'; return 'set'; })()", "threw: bad property value");
	OO_CHECK_EQ(sShip->_positionSets, 1);

	OO_CHECK_EVAL("(function () { ship.orientation = [0, 1, 0, 0]; return JSON.stringify(ship.orientation); })()", "[0,1,0,0]");
	OO_CHECK_EVAL("(function () { ship.orientation = 7; return 'set'; })()", "threw: bad property value");
	sShip->_orientation = kIdentityQuaternion;

	OO_CHECK_EVAL("(function () { ship.energy = 100; return ship.energy; })()", "100");
	OO_CHECK_EVAL("(function () { ship.energy = 1000; return ship.energy; })()", "256");	// at most maxEnergy
	OO_CHECK_EVAL("(function () { ship.energy = -5; return ship.energy; })()", "0");
	OO_CHECK_EVAL("(function () { ship.energy = 'lots'; return ship.energy; })()", "256");	// NaN is a number, clamped to maxEnergy
	sShip->_energy = 200;

	OO_CHECK_EVAL("(function () { ship.maxEnergy = 300; return ship.maxEnergy; })()", "300");
	OO_CHECK_EVAL("(function () { ship.maxEnergy = 0; return 'set'; })()", "threw: entity.maxEnergy must be positive.");
	OO_CHECK_EVAL("ship.maxEnergy", "300");
	sShip->_maxEnergy = 256;

	OO_CHECK_EVAL("(function () { ship.scanClass = 'CLASS_POLICE'; return ship.scanClass; })()", "CLASS_POLICE");
	OO_CHECK_EVAL("(function () { ship.scanClass = 'CLASS_PLAYER'; return 'set'; })()", "threw: entity.scanClass cannot be set to that value.");
	OO_CHECK_EVAL("(function () { ship.scanClass = 'nonsense'; return 'set'; })()", "threw: entity.scanClass cannot be set to that value.");
	OO_CHECK_EVAL("(function () { rock.scanClass = 'CLASS_CARGO'; return 'set'; })()", "threw: entity.scanClass is read-only except on NPC ships.");
	sShip->_isPlayer = YES;
	OO_CHECK_EVAL("(function () { ship.scanClass = 'CLASS_CARGO'; return 'set'; })()", "threw: entity.scanClass is read-only except on NPC ships.");
	sShip->_isPlayer = NO;
	OO_CHECK_EVAL("ship.scanClass", "CLASS_POLICE");
	sShip->_scanClass = CLASS_NEUTRAL;

	// Read-only properties.
	OO_CHECK_EVAL("(function () { ship.mass = 1; return ship.mass; })()", "75000");
	OO_CHECK_EVAL("(function () { ship.isShip = false; return ship.isShip; })()", "true");
}


OO_TEST(staleEntities)
{
	SetUpContext();
	// The prototype has no entity: nothing but isValid, which is false.
	OO_CHECK_EVAL("Entity.prototype.isValid", "false");
	OO_CHECK_EVAL("Entity.prototype.position", "undefined");
	OO_CHECK_EVAL("(function () { Entity.prototype.energy = 5; return 'set'; })()", "set");
	// The player while the escape pod is in flight is stale too.
	gOOJSPlayerIfStale = sShip;
	OO_CHECK_EVAL("ship.isValid + ':' + ship.mass + ':' + ship.owner", "false:undefined:undefined");
	OO_CHECK_EVAL("(function () { ship.energy = 5; return 'set'; })()", "set");
	OO_CHECK(sShip->_energy == 200);
	gOOJSPlayerIfStale = nil;
	OO_CHECK_EVAL("ship.isValid", "true");
	// Not an entity at all.
	OO_CHECK_EVAL("Object.getOwnPropertyDescriptor(Entity.prototype, 'mass').get.call({})", "threw: Native method expected Entity, got [object Object].");
}


OO_TEST(dumpState)
{
	SetUpContext();
#ifndef NDEBUG
	OO_CHECK_EVAL("ship.dumpState()", "undefined");
	OO_CHECK_EQ(sShip->_dumps, 1);
	OO_CHECK_EVAL("Entity.prototype.dumpState()", "undefined");	// no entity: a message to nil
	OO_CHECK_EQ(sShip->_dumps, 1);
#else
	OO_CHECK_EVAL("typeof ship.dumpState", "undefined");
#endif
}


OO_TEST(cFunctions)
{
	SetUpContext();
	Entity *entity = nil;
	JSValue shipValue = JSValueForEntity(sShip);
	OO_CHECK(JSValueToEntity(sContext, shipValue, &entity) && entity == sShip);
	OO_CHECK(!JSValueToEntity(sContext, JS_NewNumber(sContext, 3), &entity));

	JSValueConst argv[2] = { shipValue, JS_NewNumber(sContext, 1) };
	int consumed = 9;
	entity = nil;
	OO_CHECK(EntityFromArgumentList(sContext, "Ship", "test", 2, argv, &entity, &consumed));
	OO_CHECK(entity == sShip && consumed == 1);

	// Not an entity: a warning when given a class and function, and false either way.
	JSValueConst bad[1] = { JS_NewNumber(sContext, 3) };
	sLastWarning.clear();
	consumed = 9;
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 1, bad, &entity, &consumed));
	OO_CHECK_EQ(sLastWarning, std::string("Ship.test(): expected entity, got (full:3)."));
	OO_CHECK_EQ(consumed, 0);
	sLastWarning.clear();
	// With no class and function: no warning, and (as before) success with nothing consumed.
	OO_CHECK(EntityFromArgumentList(sContext, std::nullopt, std::nullopt, 1, bad, &entity, &consumed));
	OO_CHECK(sLastWarning.empty());
	OO_CHECK_EQ(consumed, 1);

	// Bad parameters are an internal error.
	sParameterErrors = 0;
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 0, argv, &entity, &consumed));
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 1, nullptr, &entity, &consumed));
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 1, argv, nullptr, &consumed));
	OO_CHECK_EQ(sParameterErrors, 3);
	OO_CHECK(EntityFromArgumentList(sContext, "Ship", "test", 1, argv, &entity, nullptr));
	OO_CHECK_EQ(sProfileDepth, 0);
	JS_FreeValue(sContext, shipValue);
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	sShip->_mass = 99;
	OO_CHECK_EVAL("ship.mass", "threw: Native exception: mass boom");
	sShip->_mass = 98;
	OO_CHECK_EVAL("ship.mass", "threw: Native exception: cxx boom");
	sShip->_mass = 75000;
	OO_CHECK_EVAL("ship.mass", "75000");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
