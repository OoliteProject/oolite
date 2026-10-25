/*	test_OOJSEntity.mm
	Unit tests for the Entity JS binding (src/Core/Scripting/OOJSEntity.h/.mm): bead oo-tq53,
	converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendment oo-ppc).

	As test_OOJSSun.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real context on
	the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own objects for
	the binding, the engine's exception translator (OOJSEngineNativeWrappers.mm), the constant
	strings (OOConstToJSString.cpp) and the maths it calls, and stands in for the entity classes
	(Entity and ShipEntity answer only the selectors the binding sends; the binding messages the
	Objective-C Entity, the façade every entity still is, and calls a ship's C++ part, C++ since
	bead oo-9ht.144), for the vector and quaternion conversions
	(a vector is the array [x, y, z] here, a quaternion [w, x, y, z]) and for the engine functions
	the binding links against, with the engine headers' linkage. The expectations were written
	against the Objective-C file and run on it first; they pin the JS-visible behaviour (every
	property both ways, the owner, a stale entity and the escape-pod player, the prototype,
	dumpState(), a native's exception) and the C functions other bindings call
	(JSValueToEntity(), EntityFromArgumentList()). Run: bash tools/check-core-tests.sh

	Since bead oo-9ht.39.3 (ADR-0056 amendment oo-9ht.39.3) an entity's JS object holds its C++ part
	(an OOJSEntityHolder) and the getters answer it. Since bead oo-9ht.39.8.21 the property blocks call
	the C++ entity's members, the root facade's selectors' bodies: the stand-in for the C++ class has
	the game's vtable (EntityStandIn.h) and answers as the Objective-C stand-in, its object, did (the
	stand-ins re-based under the standing approval oo-9n5p9; no expectation changed). The engine's C++ slot glue (OOJSPrivateObject.h) is stood in
	for as the Objective-C glue was (the same class check and error, the same toString()).
*/

#include "OOCocoa.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/String.hpp"
#include "OOConstToJSString.h"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

/*	An entity: its state is ivars here, answered as Entity's selectors answer it (GLfloat is float).
	One whose mass is 99 raises from -mass, one whose mass is 98 throws a C++ exception, so the test
	sees what an exception under a native becomes.
*/
#include "EntityStandIn.h"
class Entity : public oo::RefCounted, public ::OOJSPrivateObject	// the C++ root, with the game's vtable (bead oo-9ht.39.8.21)
{
public:
	OO_ENTITY_STAND_IN_VIRTUAL_MEMBERS
	virtual ~Entity();
	void dumpState();	// the binding calls it since bead oo-9ht.39.8.2 (the object's -dumpState did)
	HPVector getPosition();	// OOJSEntityPositionOfJSObject's (bead oo-9ht.39.8.12), and the position property's
	Quaternion getOrientation();	// OOJSEntityOrientationOfJSObject's (bead oo-9ht.39.8.12); no case reaches it
	// The non-virtual members the property blocks call since bead oo-9ht.39.8.21; each answers what
	// the entity's object (the Objective-C stand-in below) answered.
	OOEntityStatus status();
	GLfloat getMass();
	Entity *ownerEntity();
	GLfloat getEnergy();
	void setEnergy(GLfloat amount);
	GLfloat getMaxEnergy();
	void setMaxEnergy(GLfloat amount);
	void setScanClass(OOScanClass sClass);
	GLfloat getDistanceTravelled();
	GLfloat getSpawnTime();
	bool getIsShip();
	bool getIsStation();
	bool getIsSubEntity();
	bool getIsPlayer();
	bool getIsSunlit();
	bool getIsWormhole();
	bool isInSpace();
};

// The C++ part of each of the test's entities: the virtual members the property blocks call (bead
// oo-9ht.39.8.21), each answering what the entity's object answered.
class TestEntityPart : public Entity
{
public:
	GLfloat collisionRadius() override;
	void setPosition(HPVector posn) override;
	Quaternion normalOrientation() override;
	void setNormalOrientation(Quaternion quat) override;
	OOScanClass getScanClass() override;
	bool isDock() override;
	bool isPlanet() override;
	bool isSun() override;
	bool isVisible() override;
	bool getIsVisualEffect() override;
};

// C++ since bead oo-4aq6a.12 (it was rooted on the Objective-C root class OOObject, which Phase 4
// deletes): its selectors are members of the same names, its ivars zeroed members.
class TestEntityObject final : public oo::RefCounted
{
public:
	const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name
	float collisionRadius();
	HPVector position();
	void setPosition(HPVector posn);
	Quaternion normalOrientation();
	void setNormalOrientation(Quaternion quat);
	OOEntityStatus status();
	OOScanClass scanClass();
	void setScanClass(OOScanClass sClass);
	float mass();
	::TestEntityObject *owner();
	float energy();
	void setEnergy(float amount);
	float maxEnergy();
	void setMaxEnergy(float amount);
	float distanceTravelled();
	float spawnTime();
	bool isShip();
	bool isStation();
	bool isDock();
	bool isSubEntity();
	bool isPlayer();
	bool isPlanet();
	bool isSun();
	bool isSunlit();
	bool isVisible();
	bool isVisualEffect();
	bool isWormhole();
	bool isInSpace();

	oo::Ref<Entity> _cxxEntity;	// the C++ part (oo::ToCxx reads it): a ship's
	float _collisionRadius = {};
	HPVector _position = {};
	Quaternion _orientation = {};
	OOEntityStatus _status = {};
	OOScanClass _scanClass = {};
	float _mass = {};
	::TestEntityObject *_owner = nullptr;
	float _energy = {};
	float _maxEnergy = {};
	float _distanceTravelled = {};
	float _spawnTime = {};
	bool _isShip = false, _isStation = false, _isDock = false, _isSubEntity = false, _isPlayer = false, _isPlanet = false, _isSun = false, _isSunlit = false;
	bool _isVisible = false, _isVisualEffect = false, _isWormhole = false, _isInSpace = false;
	int _dumps = {};
	int _positionSets = {};
};

// A ship: C++ since bead oo-9ht.144 deleted the Objective-C ship this stood in for, the C++ part of
// an entity's object, declared as ShipEntity.h declares it (the test imports no game header that
// defines the class), with the stand-in's answers.
class ShipEntity : public TestEntityPart
{
public:
	void resetExhaustPlumes();
	void forceAegisCheck();

	int _plumeResets = 0;
	int _aegisChecks = 0;
};


// What an entity's JS object holds since bead oo-9ht.39.3: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>


// The binding's C API (OOJSEntity.h, which imports the engine and universe headers, so the test
// names what it calls itself). They returned BOOL, which is returned as bool is.
extern "C" {
void InitOOJSEntity(ooscript::Context context, ooscript::Object global);
bool JSValueToEntity(ooscript::Context context, ooscript::Value value, Entity **outEntity);
ooscript::ClassDef *JSEntityClass(void);
}
extern ooscript::Object gOOEntityJSPrototype;
bool EntityFromArgumentList(ooscript::Context context, const std::optional<std::string> &scriptClass, const std::optional<std::string> &function, unsigned argc, ooscript::Value *argv, Entity **outEntity, unsigned *outConsumed);


float TestEntityObject::collisionRadius()  { return _collisionRadius; }
HPVector TestEntityObject::position()  { return _position; }
void TestEntityObject::setPosition(HPVector posn)  { _position = posn; _positionSets++; }
Quaternion TestEntityObject::normalOrientation()  { return _orientation; }
void TestEntityObject::setNormalOrientation(Quaternion quat)  { _orientation = quat; }
OOEntityStatus TestEntityObject::status()  { return _status; }
OOScanClass TestEntityObject::scanClass()  { return _scanClass; }
void TestEntityObject::setScanClass(OOScanClass sClass)  { _scanClass = sClass; }

float TestEntityObject::mass()
{
	if (_mass == 99)  OORaiseException(OOInvalidArgumentException, "mass %s", "boom");
	if (_mass == 98)  throw std::runtime_error("cxx boom");
	return _mass;
}

::TestEntityObject *TestEntityObject::owner()  { return _owner; }
float TestEntityObject::energy()  { return _energy; }
void TestEntityObject::setEnergy(float amount)  { _energy = amount; }
float TestEntityObject::maxEnergy()  { return _maxEnergy; }
void TestEntityObject::setMaxEnergy(float amount)  { _maxEnergy = amount; }
float TestEntityObject::distanceTravelled()  { return _distanceTravelled; }
float TestEntityObject::spawnTime()  { return _spawnTime; }
bool TestEntityObject::isShip()  { return _isShip; }
bool TestEntityObject::isStation()  { return _isStation; }
bool TestEntityObject::isDock()  { return _isDock; }
bool TestEntityObject::isSubEntity()  { return _isSubEntity; }
bool TestEntityObject::isPlayer()  { return _isPlayer; }
bool TestEntityObject::isPlanet()  { return _isPlanet; }
bool TestEntityObject::isSun()  { return _isSun; }
bool TestEntityObject::isSunlit()  { return _isSunlit; }
bool TestEntityObject::isVisible()  { return _isVisible; }
bool TestEntityObject::isVisualEffect()  { return _isVisualEffect; }
bool TestEntityObject::isWormhole()  { return _isWormhole; }
bool TestEntityObject::isInSpace()  { return _isInSpace; }


Entity::~Entity() = default;
void ShipEntity::resetExhaustPlumes()  { _plumeResets++; }
void ShipEntity::forceAegisCheck()  { _aegisChecks++; }


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


namespace {
std::string sLastWarning;
int sParameterErrors = 0;
}

void cxx_OOJSReportWarning(ooscript::Context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	sLastWarning = oo::str::vformat(format, args);
	va_end(args);
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


std::string cxx_OOJSDescribeValue(ooscript::Context context, ooscript::Value value, BOOL abbreviateObjects)
{
	return std::string(abbreviateObjects ? "abbr:" : "full:") + cxx_OOStringFromJSValue(context, value).value_or("null");
}


void OOLogGenericParameterErrorForFunction(const char *inFunction)
{
	(void)inFunction;
	sParameterErrors++;
}


namespace {
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;
std::map<TestEntityObject *, ooscript::Object> sEntityObjects;
std::map<Entity *, TestEntityObject *> sObjects;	// what TestObjectOf answers (oo::ToObjC until bead oo-4aq6a.12): each wrapped entity's object
ooscript::Context sContext;


// An array of numbers as JavaScript, and back: enough to see what the binding hands over and takes.
bool NumbersToJSValue(ooscript::Context context, const double *numbers, unsigned count, ooscript::Value *outValue)
{
	std::vector<ooscript::Value> parts;
	for (unsigned i = 0; i < count; i++)  parts.push_back(ooscript::numberValue(numbers[i]));
	ooscript::Object array = ooscript::newArrayObject(context, count, parts.data());
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool JSValueToNumbers(ooscript::Context context, ooscript::Value value, double *numbers, unsigned count)
{
	ooscript::Value element;
	if (!ooscript::isObject(value) || !ooscript::isArrayObject(context, ooscript::toObject(value)))  return false;
	for (unsigned i = 0; i < count; i++)
	{
		if (!ooscript::getElement(context, ooscript::toObject(value), static_cast<std::int32_t>(i), &element) || !ooscript::valueToNumber(context, element, &numbers[i]))  return false;
	}
	return true;
}


// An entity's JS object, as EntityJSValueInContext() makes it: the Entity class, and a holder of the
// entity's C++ part in the private slot (bead oo-9ht.39.3; a plain one for an entity made without).
// One per entity.
ooscript::Value JSValueForEntity(TestEntityObject *entity)
{
	ooscript::Object &object = sEntityObjects[entity];
	if (object == nullptr)
	{
		if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeRef<TestEntityPart>();
		sObjects[entity->_cxxEntity.get()] = entity;
		object = ooscript::newObject(sContext, JSEntityClass(), gOOEntityJSPrototype, nullptr);
		if (object == nullptr || !OOJSSetCxxPrivate(sContext, object, oo::makeRef<OOJSEntityHolder>(entity->_cxxEntity.get()).get()))  return ooscript::nullValue();
		ooscript::addNamedObjectRoot(sContext, &object, "test entity");	// std::map keeps the slot where it is
	}
	return ooscript::objectValue(object);
}

} // namespace

Entity *gOOJSPlayerIfStale = nullptr;	// the player's C++ entity (bead oo-9ht.39.25)



// What the object's -dumpState counted until bead oo-9ht.39.8.2.
// oo::ToObjC (Entity+ObjCBridge.mm) until bead oo-4aq6a.12: the object of a C++ part the test
// wrapped, null for any other.
::TestEntityObject *TestObjectOf(Entity *entity);
#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}


// [object message] where object may be nil (bead oo-4aq6a.12): nil answered zero and did nothing.
template <class Result, class... Parameters, class... Arguments>
Result Send(::TestEntityObject *object, Result (::TestEntityObject::*method)(Parameters...), Arguments... arguments)
{
	if (object == nullptr)
	{
		if constexpr (std::is_void_v<Result>)  return;
		else  return Result{};
	}
	return (object->*method)(arguments...);
}


void Entity::dumpState()  { TestObjectOf(this)->_dumps++; }
// What the object's -position/-orientation answered for the vector and quaternion conversions, which
// read the C++ entity since bead oo-9ht.39.8.12 (link stand-ins: no case here converts an entity).
HPVector Entity::getPosition()  { return TestObjectOf(this)->_position; }
Quaternion Entity::getOrientation()  { return TestObjectOf(this)->_orientation; }

// What the object's selectors answered, which the property blocks call the C++ members for since bead
// oo-9ht.39.8.21: each asks the object, so the stand-in's state, its counters and -mass's raise and
// throw are what they were.
OOEntityStatus Entity::status()  { return Send(TestObjectOf(this), &TestEntityObject::status); }
GLfloat Entity::getMass()  { return Send(TestObjectOf(this), &TestEntityObject::mass); }
GLfloat Entity::getEnergy()  { return Send(TestObjectOf(this), &TestEntityObject::energy); }
void Entity::setEnergy(GLfloat amount)  { Send(TestObjectOf(this), &TestEntityObject::setEnergy, amount); }
GLfloat Entity::getMaxEnergy()  { return Send(TestObjectOf(this), &TestEntityObject::maxEnergy); }
void Entity::setMaxEnergy(GLfloat amount)  { Send(TestObjectOf(this), &TestEntityObject::setMaxEnergy, amount); }
void Entity::setScanClass(OOScanClass sClass)  { Send(TestObjectOf(this), &TestEntityObject::setScanClass, sClass); }
GLfloat Entity::getDistanceTravelled()  { return Send(TestObjectOf(this), &TestEntityObject::distanceTravelled); }
GLfloat Entity::getSpawnTime()  { return Send(TestObjectOf(this), &TestEntityObject::spawnTime); }
bool Entity::getIsShip()  { return Send(TestObjectOf(this), &TestEntityObject::isShip); }
bool Entity::getIsStation()  { return Send(TestObjectOf(this), &TestEntityObject::isStation); }
bool Entity::getIsSubEntity()  { return Send(TestObjectOf(this), &TestEntityObject::isSubEntity); }
bool Entity::getIsPlayer()  { return Send(TestObjectOf(this), &TestEntityObject::isPlayer); }
bool Entity::getIsSunlit()  { return Send(TestObjectOf(this), &TestEntityObject::isSunlit); }
bool Entity::getIsWormhole()  { return Send(TestObjectOf(this), &TestEntityObject::isWormhole); }
bool Entity::isInSpace()  { return Send(TestObjectOf(this), &TestEntityObject::isInSpace); }

// The owner's C++ part, as -owner answered its object (nil: none).
Entity *Entity::ownerEntity()
{
	::TestEntityObject *owner = Send(TestObjectOf(this), &TestEntityObject::owner);
	return owner != nullptr ? owner->_cxxEntity.get() : nullptr;
}

GLfloat TestEntityPart::collisionRadius()  { return Send(TestObjectOf(this), &TestEntityObject::collisionRadius); }
void TestEntityPart::setPosition(HPVector posn)  { Send(TestObjectOf(this), &TestEntityObject::setPosition, posn); }
Quaternion TestEntityPart::normalOrientation()  { return Send(TestObjectOf(this), &TestEntityObject::normalOrientation); }
void TestEntityPart::setNormalOrientation(Quaternion quat)  { Send(TestObjectOf(this), &TestEntityObject::setNormalOrientation, quat); }
OOScanClass TestEntityPart::getScanClass()  { return Send(TestObjectOf(this), &TestEntityObject::scanClass); }
bool TestEntityPart::isDock()  { return Send(TestObjectOf(this), &TestEntityObject::isDock); }
bool TestEntityPart::isPlanet()  { return Send(TestObjectOf(this), &TestEntityObject::isPlanet); }
bool TestEntityPart::isSun()  { return Send(TestObjectOf(this), &TestEntityObject::isSun); }
bool TestEntityPart::isVisible()  { return Send(TestObjectOf(this), &TestEntityObject::isVisible); }
bool TestEntityPart::getIsVisualEffect()  { return Send(TestObjectOf(this), &TestEntityObject::isVisualEffect); }


extern "C" {

bool HPVectorToJSValue(ooscript::Context context, HPVector vector, ooscript::Value *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool VectorToJSValue(ooscript::Context context, Vector vector, ooscript::Value *outValue)
{
	const double parts[3] = { vector.x, vector.y, vector.z };
	return NumbersToJSValue(context, parts, 3, outValue);
}


bool JSValueToHPVector(ooscript::Context context, ooscript::Value value, HPVector *outVector)
{
	double v[3] = {};
	if (!JSValueToNumbers(context, value, v, 3))  return false;
	*outVector = make_HPvector(v[0], v[1], v[2]);
	return true;
}


bool QuaternionToJSValue(ooscript::Context context, Quaternion quaternion, ooscript::Value *outValue)
{
	const double parts[4] = { quaternion.w, quaternion.x, quaternion.y, quaternion.z };
	return NumbersToJSValue(context, parts, 4, outValue);
}


bool JSValueToQuaternion(ooscript::Context context, ooscript::Value value, Quaternion *outQuaternion)
{
	double q[4] = {};
	if (!JSValueToNumbers(context, value, q, 4))  return false;
	*outQuaternion = make_quaternion(q[0], q[1], q[2], q[3]);
	return true;
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


BOOL OOJSIsSubclass(ooscript::ClassDef *putativeSubclass, ooscript::ClassDef *superclass)
{
	for (ooscript::ClassDef *c = putativeSubclass; c != nullptr; c = sSuperclasses.count(c) != 0 ? sSuperclasses[c] : nullptr)
	{
		if (c == superclass)  return YES;
	}
	return NO;
}


void OOJSRegisterObjectConverter(ooscript::ClassDef *theClass, oo::PList (*)(ooscript::Context, ooscript::Object))
{
	sConverters[theClass]++;
}




bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
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

}	// extern "C"


// The engine's C++ slot glue (OOJSPrivateObject.h, bead oo-9ht.39.3), as the Objective-C glue was stood
// in for: the getter's JS class check and error, the slot's retain, a finalizer that does nothing and
// the same toString().
bool OOJSGetCxxPrivateImpl(ooscript::Context context, ooscript::Object object, ooscript::ClassDef *requiredJSClass, oo::RefCounted **outObject)
{
	ooscript::ClassDef *actualClass = const_cast<ooscript::ClassDef *>(ooscript::getObjectClass(context, object));
	if (!OOJSIsSubclass(actualClass, requiredJSClass))
	{
		cxx_OOJSReportError(context, "Native method expected %s, got %s.", requiredJSClass->name, cxx_OOStringFromJSValue(context, ooscript::objectValue(object)).value_or("(null)").c_str());
		return false;
	}
	*outObject = static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object));
	return true;
}


bool OOJSSetCxxPrivate(ooscript::Context context, ooscript::Object jsObject, oo::RefCounted *object)
{
	if (object != nullptr)  object->retain();
	if (ooscript::setPrivate(context, jsObject, object))  return true;
	if (object != nullptr)  object->release();
	return false;
}


void OOJSCxxObjectWrapperFinalize(ooscript::Context, ooscript::Object)
{
}


bool OOJSCxxObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &args, ooscript::ClassDef *)
{
	ooscript::String string = ooscript::newStringCopyZ(context, "[TestEntityObject]");
	args.setRval(ooscript::stringValue(string));
	return true;
}


// The JS value of a C++ object: an entity's own JS object (the owner property's since bead
// oo-9ht.39.8.21, what OOJSValueFromNativeObject made of its object), null for null; a holder's glue
// is never reached (no case wraps a holder's value).
ooscript::Value OOJSValueFromCxxObject(ooscript::Context, OOJSPrivateObject *object)
{
	if (object == nullptr)  return ooscript::nullValue();
	if (auto *entity = dynamic_cast<Entity *>(object))
	{
		if (::TestEntityObject *entityObject = TestObjectOf(entity))  return JSValueForEntity(entityObject);
	}
	return ooscript::undefinedValue();
}


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Object sGlobal;
TestEntityObject *sShip = nullptr;	// a ship's object and its C++ part (the Objective-C ship until bead oo-9ht.144)
ShipEntity *sShipPart = nullptr;
TestEntityObject *sRock = nullptr;
TestEntityObject *sMother = nullptr;


void Define(const char *name, ooscript::Value value)
{
	ooscript::setProperty(sContext, sGlobal, name, &value);
}


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
	sGlobal = ooscript::getGlobalObject(sContext);
	ooscript::initStandardClasses(sContext, sGlobal);
	OOConstToJSStringInit(sContext);
	InitOOJSEntity(sContext, sGlobal);

	// Kept for the life of the test.
	sMother = oo::makeRef<TestEntityObject>().leakRef();
	sMother->_cxxEntity = oo::makeRef<ShipEntity>();
	sMother->_isShip = YES;
	sMother->_isStation = YES;
	sMother->_status = STATUS_ACTIVE;
	sMother->_scanClass = CLASS_STATION;

	sShip = oo::makeRef<TestEntityObject>().leakRef();
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

	sRock = oo::makeRef<TestEntityObject>().leakRef();
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

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EQ(sConverters[JSEntityClass()], 1);
	OO_CHECK(std::strcmp(JSEntityClass()->name, "Entity") == 0);
	OO_CHECK_EVAL("typeof Entity", "function");
	OO_CHECK_EVAL("new Entity()", "threw: unconstructable");
	OO_CHECK_EVAL("ship instanceof Entity && Object.getPrototypeOf(ship) === Entity.prototype", "true");
	OO_CHECK_EVAL("Object.keys(Entity.prototype).join()",
				  "collisionRadius,distanceTravelled,energy,heading,mass,maxEnergy,orientation,owner,position,scanClass,spawnTime,status,isPlanet,isPlayer,isShip,isDock,isStation,isSubEntity,isSun,isSunlit,isValid,isInSpace,isVisible,isVisualEffect,isWormhole");
	OO_CHECK_EVAL("String(ship)", "[TestEntityObject]");
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
	gOOJSPlayerIfStale = sShipPart;	// its C++ part (bead oo-9ht.39.25)
	OO_CHECK_EVAL("ship.isValid + ':' + ship.mass + ':' + ship.owner", "false:undefined:undefined");
	OO_CHECK_EVAL("(function () { ship.energy = 5; return 'set'; })()", "set");
	OO_CHECK(sShip->_energy == 200);
	gOOJSPlayerIfStale = nullptr;
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
	Entity *entity = nullptr;
	ooscript::Value shipValue = JSValueForEntity(sShip);
	OO_CHECK(JSValueToEntity(sContext, shipValue, &entity) && TestObjectOf(entity) == sShip);
	OO_CHECK(!JSValueToEntity(sContext, ooscript::numberValue(3), &entity));

	ooscript::Value argv[2] = { shipValue, ooscript::numberValue(1) };
	unsigned consumed = 9;
	entity = nullptr;
	OO_CHECK(EntityFromArgumentList(sContext, "Ship", "test", 2, argv, &entity, &consumed));
	OO_CHECK(TestObjectOf(entity) == sShip && consumed == 1);

	// Not an entity: a warning when given a class and function, and false either way.
	ooscript::Value bad[1] = { ooscript::numberValue(3) };
	sLastWarning.clear();
	consumed = 9;
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 1, bad, &entity, &consumed));
	OO_CHECK_EQ(sLastWarning, std::string("Ship.test(): expected entity, got (full:3)."));
	OO_CHECK_EQ(consumed, 0u);
	sLastWarning.clear();
	// With no class and function: no warning, and (as before) success with nothing consumed.
	OO_CHECK(EntityFromArgumentList(sContext, std::nullopt, std::nullopt, 1, bad, &entity, &consumed));
	OO_CHECK(sLastWarning.empty());
	OO_CHECK_EQ(consumed, 1u);

	// Bad parameters are an internal error.
	sParameterErrors = 0;
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 0, argv, &entity, &consumed));
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 1, nullptr, &entity, &consumed));
	OO_CHECK(!EntityFromArgumentList(sContext, "Ship", "test", 1, argv, nullptr, &consumed));
	OO_CHECK_EQ(sParameterErrors, 3);
	OO_CHECK(EntityFromArgumentList(sContext, "Ship", "test", 1, argv, &entity, nullptr));
	OO_CHECK_EQ(sProfileDepth, 0);
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
