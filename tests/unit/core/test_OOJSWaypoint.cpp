/*	test_OOJSWaypoint.mm
	Unit tests for the Waypoint JS binding (src/Core/Scripting/OOJSWaypoint.h/.mm) and its
	OOWaypointEntity category (this test's stand-in OOWaypointEntity forwards the binding's calls).

	As test_OOJSWormhole.mm does, it runs the JS class in a real QuickJS-ng context, links the
	game's own objects for the binding, the engine's class registration (OOJSClasses.mm) and the
	engine's exception translator (OOJSEngineNativeWrappers.mm), and stands in for the classes the
	binding messages (Entity and OOWaypointEntity, and the universe's beacon list and the player's
	compass, answer only the selectors the binding sends; the waypoint is a C++ stand-in under the
	root's object, which answers the beacon selectors and asks the C++ part the JS questions, as the
	game's does), for the Quaternion conversions (a quaternion is the array [w, x, y, z] here) and
	for the engine functions the binding links against, with the engine headers' linkage. The
	expectations were written to pin the JS-visible behaviour (the four properties, a beacon code
	that registers or clears a beacon, an unoriented waypoint, a non-waypoint, a native's exception)
	and what the category answers the engine. Run: tests/run.sh unit
*/

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "EntityManualRefs.h"  // the tests' manual references (T097)


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class Universe;
class PlayerEntity;

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::Object
{
public:
	virtual ~Entity();
	virtual JSClassID jsClassID();
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
	Quaternion getOrientation();	// the binding calls these
	void setNormalOrientation(Quaternion quat);
};

/*	The waypoint. One whose size is 99 raises
   from size(), one whose size is 98 throws a C++ exception, so the test sees
   what an exception under a native becomes.
*/
class OOWaypointEntity : public Entity
{
public:
	JSClassID jsClassID() override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	bool getOriented();
	OOScalar size();
	void setSize(OOScalar newSize);
	std::optional<std::string> beaconCode();	// the binding calls these
	void setBeaconCode(const std::optional<std::string> &bcode);
	std::optional<std::string> beaconLabel();
	void setBeaconLabel(const std::optional<std::string> &blabel);
	bool isBeacon();

	bool _oriented = false;
	OOScalar _size = 0;
};

// The root's object, which holds the waypoint's C++ part (oo::ToCxx reads it) and answers the
// beacon selectors for it (the game's Entity (OOWaypointBeacon)).
// What an entity's JS object holds: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// Its category's selectors are members of the same names.
class TestEntityObject final : public oo::Object
{
public:
	JSClassID oo_jsClassID();
	std::optional<std::string> oo_jsClassName();
	bool isVisibleToScripts();

	std::shared_ptr<Entity> _cxxEntity;
	std::optional<std::string> _beaconCode;
	std::optional<std::string> _beaconLabel;
	Quaternion _orientation = {};	// zeroed, as the object's ivar was
};

// The universe's beacon list and the player's compass: what the binding tells them.
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class. It
// answers virtual members, so it has the game's vtable (UniverseStandIn.h) and
// FakeGame overrides them; FakeGame also answers the player's compass (the
// player stand-in calls it).
class Universe : public oo::Object
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS
};

::TestEntityObject *TestObjectOf(Entity *entity);	// defined below

class FakeGame : public Universe
{
public:
	::TestEntityObject *_nextBeacon = nullptr;
	int _cleared = 0;
	int _added = 0;
	int _compassMode = 0;

	// The C++ waypoint (the waypoint's object holds it).
	void setNextBeacon(Entity *beacon) override  { _added++; (void)beacon; }
	void clearBeacon(Entity *beacon) override  { _cleared++; TestObjectOf(beacon)->_beaconCode = std::nullopt; }
	TestEntityObject *nextBeacon()  { return _nextBeacon; }
	void setCompassMode(OOCompassMode mode)  { _compassMode = static_cast<int>(mode); }
};

// PLAYER: the compass members the binding calls (declared as the game headers
// declare them; the test imports none that defines the classes), which ask the
// fake game as the binding asked it.
class ShipEntity : public Entity
{
public:
	::TestEntityObject *nextBeacon();
	Entity *nextBeaconEntity();
};

class PlayerEntity : public ShipEntity
{
public:
	void setCompassMode(OOCompassMode value);

	FakeGame *_game = nullptr;
};

#include "OOJSWaypoint.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstdint>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>





// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions.cpp): the
// engine sends these selectors to the wrapped object.
JSClassID TestEntityObject::oo_jsClassID()  { return _cxxEntity->jsClassID(); }
std::optional<std::string> TestEntityObject::oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
JSClassID Entity::jsClassID()  { return 0; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }

// The binding's category, as the C++ class's overrides call it
// (OOWaypointEntity.mm).
JSClassID OOWaypointEntity::jsClassID()  { return ::JSWaypointClassID(); }
std::optional<std::string> OOWaypointEntity::jsClassName()  { return ::OOJSWaypointJSClassName(); }
bool OOWaypointEntity::isVisibleToScripts()  { return ::OOJSWaypointIsVisibleToScripts(); }

bool OOWaypointEntity::getOriented()  { return _oriented; }
void OOWaypointEntity::setSize(OOScalar newSize)  { _size = newSize; }
OOScalar OOWaypointEntity::size()
{
	if (_size == 99)  OORaiseException(OOInvalidArgumentException, "size %s", "boom");
	if (_size == 98)  throw std::runtime_error("cxx boom");
	return _size;
}



::TestEntityObject *ShipEntity::nextBeacon()  { return static_cast<PlayerEntity *>(this)->_game->nextBeacon(); }
Entity *ShipEntity::nextBeaconEntity()  { ::TestEntityObject *object = nextBeacon(); return object != nullptr ? object->_cxxEntity.get() : nullptr; }	// as the game's (oo::ToCxx of it)
void PlayerEntity::setCompassMode(OOCompassMode value)  { static_cast<PlayerEntity *>(this)->_game->setCompassMode(value); }


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;	// the engine's


void OOJSReportErrorWithArguments(JSContext *context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
}


void OOJSReportError(JSContext *context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


// What the class registration (OOJSClasses.mm) asks of the engine.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom OOJSIDFromString(const std::string &string)
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


std::optional<std::string> OOStringFromJSValue(JSContext *context, JSValueConst value)
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

Universe *gSharedUniverse = nullptr;
PlayerEntity *gOOPlayer = nullptr;


JSClassID JSEntityClassID(void)
{
	return sFakeEntityClassID;
}


void OOJSReportBadPropertySelector(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t)
{
	OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(JSContext *context, JSValueConst, int, const JSCFunctionListEntry *, size_t, JSValueConst)
{
	OOJSReportError(context, "bad property value");
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


// The engine's object getter is OOJSPrivateObject.cpp's (linked): the JS class must be a subclass
// of the required one, and the slot holds the entity's holder.

// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of another class.
JSValue OOJSObjectWrapperToString(JSContext *context, JSValueConst, int, JSValueConst *)
{
	return JS_NewString(context, "[object]");
}




JSValue OOJSUnconstructableConstruct(JSContext *context, JSValueConst, int, JSValueConst *)
{
	OOJSReportError(context, "unconstructable");
	return JS_EXCEPTION;
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


oo::PList OOJSEntityObjectConverter(JSContext *, JSValueConst)
{
	return oo::PList();
}


// The holder's glue is OOJSEntity.mm's, which the test does not link; the binding never asks it.
JSValue OOJSEntityHolder::jsValueInContext(JSContext *)  { return JS_UNDEFINED; }
void OOJSEntityHolder::clearJSSelf(JSValueConst)  {}
std::optional<std::string> OOJSEntityHolder::jsDescription()  { return std::nullopt; }


// oo::ToObjC: the object of each C++ part the test wrapped, nil for any
// other (the binding asks it where its natives still message the object).
namespace {
std::map<Entity *, TestEntityObject *> sObjects;
}
::TestEntityObject *TestObjectOf(Entity *entity);
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}


// The waypoint's beacon and orientation, on its object's fields.
std::optional<std::string> OOWaypointEntity::beaconCode()  { return TestObjectOf(this)->_beaconCode; }
void OOWaypointEntity::setBeaconCode(const std::optional<std::string> &bcode)  { TestObjectOf(this)->_beaconCode = bcode; }
std::optional<std::string> OOWaypointEntity::beaconLabel()  { return TestObjectOf(this)->_beaconLabel; }
void OOWaypointEntity::setBeaconLabel(const std::optional<std::string> &blabel)  { TestObjectOf(this)->_beaconLabel = blabel; }
bool OOWaypointEntity::isBeacon()  { const std::optional<std::string> &code = TestObjectOf(this)->_beaconCode; return code.has_value() && !code->empty(); }
Quaternion Entity::getOrientation()  { return TestObjectOf(this)->_orientation; }
void Entity::setNormalOrientation(Quaternion quat)  { TestObjectOf(this)->_orientation = quat; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSRuntime *sRuntime = nullptr;
JSContext *sContext = nullptr;
JSValue sGlobal = JS_UNDEFINED;	// held for the life of the test
TestEntityObject *sWaypoint = nullptr;			// the waypoint's object
OOWaypointEntity *sWaypointPart = nullptr;	// its C++ part
FakeGame *sGame = nullptr;


// A JS object of the class, with the class's prototype and a holder of the entity's C++ part in
// the private slot; owned by the caller.
JSValue JSValueForObject(JSClassID jsClass, TestEntityObject *entity)
{
	JSValue object = JS_NewObjectClass(sContext, static_cast<int>(jsClass));
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeShared<Entity>();	// a plain entity's C++ part
	if (JS_IsException(object) || !OOJSSetCxxPrivate(object, oo::makeShared<OOJSEntityHolder>(entity->_cxxEntity.get())))	// the slot holds the C++ entity
	{
		JS_FreeValue(sContext, object);
		return JS_NULL;
	}
	sObjects[entity->_cxxEntity.get()] = entity;
	return object;
}


// A JS object for an entity, as EntityJSValueInContext() makes it: the class the entity's
// category names, and a holder of the entity in the private slot.
JSValue JSValueForEntity(TestEntityObject *entity)
{
	return JSValueForObject(entity->oo_jsClassID(), entity);
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

	sGame = new FakeGame();	// kept for the life of the test
	gSharedUniverse = sGame;
	gOOPlayer = new PlayerEntity;	// never deleted
	gOOPlayer->_game = sGame;
	sWaypoint = oo::test::NewRetained<TestEntityObject>();	// kept for the life of the test
	sWaypoint->_cxxEntity = oo::makeShared<OOWaypointEntity>();
	sWaypointPart = static_cast<OOWaypointEntity *>(sWaypoint->_cxxEntity.get());
	sWaypoint->_beaconLabel = "Label";
	sWaypoint->_orientation = make_quaternion(0, 1, 0, 0);
	sWaypointPart->_oriented = true;
	sWaypointPart->_size = 20;
	Define("waypoint", JSValueForEntity(sWaypoint));
	Define("plainEntity", JSValueForObject(sFakeEntityClassID, oo::test::NewRetained<TestEntityObject>()));
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
	std::string text = OOStringFromJSValue(sContext, result).value_or("<not a string>");
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
	JSClassID waypointClass = sWaypoint->oo_jsClassID();
	OO_CHECK(waypointClass != 0 && OOJSClassName(waypointClass) != nullptr && std::strcmp(OOJSClassName(waypointClass), "Waypoint") == 0);
	JSValue prototype = JS_GetClassProto(sContext, waypointClass);
	OO_CHECK(JS_IsObject(prototype));
	JS_FreeValue(sContext, prototype);
	OO_CHECK(OOJSIsSubclass(waypointClass, sFakeEntityClassID));
	OO_CHECK_EQ(sConverters[waypointClass], 1);
	OO_CHECK(sWaypoint->oo_jsClassName() == std::optional<std::string>("Waypoint"));
	OO_CHECK(sWaypoint->isVisibleToScripts());
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
	sWaypointPart->_oriented = false;
	OO_CHECK_EVAL("waypoint.orientation", "0,0,0,0");	// unoriented: the zero quaternion
	sWaypointPart->_oriented = true;
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
	OO_CHECK_EQ(sGame->_compassMode, static_cast<int>(OOCompassMode::kPlanet));
	// Clearing a waypoint that is not a beacon does nothing.
	OO_CHECK_EVAL("(function () { waypoint.beaconCode = null; return waypoint.beaconCode; })()", "null");
	OO_CHECK_EQ(sGame->_cleared, cleared + 1);
	sGame->_nextBeacon = nullptr;
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
	sWaypointPart->_size = 99;
	OO_CHECK_EVAL("waypoint.size", "threw: Native exception: size boom");
	sWaypointPart->_size = 98;
	OO_CHECK_EVAL("waypoint.size", "threw: Native exception: cxx boom");
	sWaypointPart->_size = 20;
	OO_CHECK_EVAL("waypoint.size", "20");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
