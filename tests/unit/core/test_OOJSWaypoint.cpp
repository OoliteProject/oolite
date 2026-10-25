/*	test_OOJSWaypoint.mm
	Unit tests for the Waypoint JS binding (src/Core/Scripting/OOJSWaypoint.h/.mm) and its
	OOWaypointEntity category (whose forwarders are on the OOWaypointEntity facade since bead
	oo-9ht.50; this test's stand-in OOWaypointEntity forwards the same way): bead oo-mae5, converted
	the way bead oo-ppc converted OOJSVector (proposed ADR-0056 amendments oo-ppc and oo-ykoy).

	As test_OOJSWormhole.mm does (amendment oo-ykoy, item 4), it runs the JS class in a real
	context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp), links the game's own
	objects for the binding and the engine's exception translator
	(OOJSEngineNativeWrappers.mm), and stands in for the classes the binding messages (Entity and
	OOWaypointEntity, and the universe's beacon list and the player's compass, answer only the
	selectors the binding sends; since bead oo-9ht.108 deleted the OOWaypointEntity facade the
	waypoint is a C++ stand-in under the root's object, which answers the beacon selectors and
	asks the C++ part the JS questions, as the game's does), for the Quaternion conversions (a quaternion is the array
	[w, x, y, z] here) and for the engine functions the binding links against, with the engine
	headers' linkage. The expectations were written against the Objective-C file and run on it
	first; they pin the JS-visible behaviour (the four properties, a beacon code that registers or
	clears a beacon, an unoriented waypoint, a non-waypoint, a native's exception) and what the
	category answers the engine. Run: bash tools/check-core-tests.sh
*/

#include "OOCocoa.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "ooscript/JSEngine.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The classes, as far as the binding sees them ----------------------------------------------

class Universe;
class PlayerEntity;

// The C++ root, as far as the binding and the root's JS category reach it.
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
	virtual void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	virtual std::optional<std::string> jsClassName();
	virtual bool isVisibleToScripts();
	Quaternion getOrientation();	// the binding calls these since bead oo-9ht.39.8.18 (its object's selectors did)
	void setNormalOrientation(Quaternion quat);
};

/*	The waypoint (C++ since bead oo-9ht.108). One whose size is 99 raises from size(), one whose
	size is 98 throws a C++ exception, so the test sees what an exception under a native becomes.
*/
class OOWaypointEntity : public Entity
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override;
	std::optional<std::string> jsClassName() override;
	bool isVisibleToScripts() override;

	bool getOriented();
	OOScalar size();
	void setSize(OOScalar newSize);
	std::optional<std::string> beaconCode();	// the binding calls these since bead oo-9ht.39.8.18 (its object's selectors did)
	void setBeaconCode(const std::optional<std::string> &bcode);
	std::optional<std::string> beaconLabel();
	void setBeaconLabel(const std::optional<std::string> &blabel);
	bool isBeacon();

	BOOL _oriented = NO;
	OOScalar _size = 0;
};

// The root's object, which holds the waypoint's C++ part (oo::ToCxx reads it) and answers the
// beacon selectors for it (the game's Entity (OOWaypointBeacon)).
// What an entity's JS object holds since bead oo-9ht.39.3: a weak reference to the C++ entity.
#include "OOJSEntityHolder.h"


// C++ since bead oo-4aq6a.11 (it was rooted on the Objective-C root class OOObject, which Phase 4
// deletes); its category's selectors are members of the same names.
class TestEntityObject final : public oo::RefCounted
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype);
	std::optional<std::string> cxx_oo_jsClassName();
	bool isVisibleToScripts();

	oo::Ref<Entity> _cxxEntity;
	std::optional<std::string> _beaconCode;
	std::optional<std::string> _beaconLabel;
	Quaternion _orientation = {};	// zeroed, as the object's ivar was
};

// The universe's beacon list and the player's compass: what the binding tells them.
#include "UniverseStandIn.h"

// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade FakeGame stood in for). It answers virtual members, so it has the game's
// vtable (UniverseStandIn.h) and FakeGame overrides them; FakeGame also answers the player's
// compass (the player stand-in calls it).
class Universe : public oo::RefCounted
{
public:
	OO_UNIVERSE_STAND_IN_VIRTUAL_MEMBERS
};

::TestEntityObject *TestObjectOf(Entity *entity);	// defined below (oo::ToObjC until bead oo-4aq6a.11)

class FakeGame : public Universe
{
public:
	::TestEntityObject *_nextBeacon = nullptr;
	int _cleared = 0;
	int _added = 0;
	int _compassMode = 0;

	// The C++ waypoint since bead oo-9ht.39.8.10 (it was the waypoint's object, which holds the code here).
	void setNextBeacon(Entity *beacon) override  { _added++; (void)beacon; }
	void clearBeacon(Entity *beacon) override  { _cleared++; TestObjectOf(beacon)->_beaconCode = std::nullopt; }
	TestEntityObject *nextBeacon()  { return _nextBeacon; }
	void setCompassMode(OOCompassMode mode)  { _compassMode = static_cast<int>(mode); }
};

// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player the fake game stood in for: the
// compass members the binding calls (declared as the game headers declare them; the test imports
// none that defines the classes), which ask the fake game as the binding asked it.
class ShipEntity : public Entity	// C++ since bead oo-9ht.144
{
public:
	::TestEntityObject *nextBeacon();
	Entity *nextBeaconEntity();
};

class PlayerEntity : public ShipEntity
{
public:
	void setCompassMode(OOCompassMode value);

	FakeGame *_game = nil;
};

#include "OOJSWaypoint.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>





// The root's JS category, as the game's asks the C++ part (EntityOOJavaScriptExtensions+ObjCBridge.mm,
// bead oo-9ht.107): the engine sends these selectors to the wrapped object.
void TestEntityObject::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { _cxxEntity->getJSClass(outClass, outPrototype); }
std::optional<std::string> TestEntityObject::cxx_oo_jsClassName()  { return _cxxEntity->jsClassName(); }
bool TestEntityObject::isVisibleToScripts()  { return _cxxEntity->isVisibleToScripts(); }


Entity::~Entity()  {}
void Entity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { *outClass = nullptr; *outPrototype = nullptr; }
std::optional<std::string> Entity::jsClassName()  { return std::string("Entity"); }
bool Entity::isVisibleToScripts()  { return false; }

// The binding's category, as the C++ class's overrides call it (OOWaypointEntity.mm, bead oo-9ht.108).
void OOWaypointEntity::getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype)  { ::OOJSWaypointGetJSClass(outClass, outPrototype); }
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


// A property list as JavaScript, as far as the binding hands one over: null, a string, a number,
// or an array of those.
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())
	{
		ooscript::String js = ooscript::newStringCopyN(context, str->data(), str->size());
		return js != nullptr ? ooscript::stringValue(js) : ooscript::nullValue();
	}
	if (const double *number = plist.getIf<double>())  return ooscript::numberValue(*number);
	if (const oo::PList::Array *array = plist.getIf<oo::PList::Array>())
	{
		std::vector<ooscript::Value> values;
		for (const oo::PList &element : *array)  values.push_back(OOJSValueFromPList(context, element));
		ooscript::Object object = ooscript::newArrayObject(context, static_cast<unsigned>(values.size()), values.data());
		return object != nullptr ? ooscript::objectValue(object) : ooscript::nullValue();
	}
	return ooscript::nullValue();
}


namespace {
ooscript::ClassDef sFakeEntityClass = { "Entity", ooscript::ClassFlag::HasPrivate };
std::map<ooscript::ClassDef *, ooscript::ClassDef *> sSuperclasses;
std::map<ooscript::ClassDef *, int> sConverters;
} // namespace

ooscript::Object gOOEntityJSPrototype = nullptr;
Universe *gSharedUniverse = nil;
PlayerEntity *gOOPlayer = nullptr;


extern "C" {

ooscript::ClassDef *JSEntityClass(void)
{
	return &sFakeEntityClass;
}


void OOJSReportBadPropertySelector(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *)
{
	cxx_OOJSReportError(context, "bad property selector");
}


void OOJSReportBadPropertyValue(ooscript::Context context, ooscript::Object, ooscript::PropertyId, ooscript::PropertySpec *, ooscript::Value)
{
	cxx_OOJSReportError(context, "bad property value");
}


void OOJSRegisterSubclass(ooscript::ClassDef *subclass, ooscript::ClassDef *superclass)
{
	sSuperclasses[subclass] = superclass;
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


// The engine's object getter is OOJSPrivateObject.cpp's (linked) since bead oo-9ht.39.3: the JS
// class must be a subclass of the required one, and the slot holds the entity's holder.

// The shared toString(), which OOJSCxxObjectWrapperToString() hands a `this` of another class.
bool OOJSObjectWrapperToString(ooscript::Context context, ooscript::CallArgs &args)
{
	const std::string text = "[object]";
	args.setRval(ooscript::stringValue(ooscript::newStringCopyN(context, text.data(), text.size())));
	return true;
}




bool OOJSUnconstructableConstruct(ooscript::Context context, ooscript::CallArgs &)
{
	cxx_OOJSReportError(context, "unconstructable");
	return false;
}



// A quaternion is the array [w, x, y, z] here: enough to see what the binding hands over and takes.
bool QuaternionToJSValue(ooscript::Context context, Quaternion quaternion, ooscript::Value *outValue)
{
	ooscript::Value parts[4] = { ooscript::numberValue(quaternion.w), ooscript::numberValue(quaternion.x), ooscript::numberValue(quaternion.y), ooscript::numberValue(quaternion.z) };
	ooscript::Object array = ooscript::newArrayObject(context, 4, parts);
	if (array == nullptr)  return false;
	*outValue = ooscript::objectValue(array);
	return true;
}


bool JSValueToQuaternion(ooscript::Context context, ooscript::Value value, Quaternion *outQuaternion)
{
	double q[4] = {};
	ooscript::Value element;
	if (!ooscript::isObject(value) || !ooscript::isArrayObject(context, ooscript::toObject(value)))  return false;
	for (int i = 0; i < 4; i++)
	{
		if (!ooscript::getElement(context, ooscript::toObject(value), i, &element) || !ooscript::valueToNumber(context, element, &q[i]))  return false;
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

}	// extern "C"


oo::PList OOJSEntityObjectConverter(ooscript::Context, ooscript::Object)
{
	return oo::PList();
}


// The holder's glue is OOJSEntity.mm's, which the test does not link; the binding never asks it.
ooscript::Value OOJSEntityHolder::jsValueInContext(ooscript::Context)  { return ooscript::undefinedValue(); }
void OOJSEntityHolder::clearJSSelf(ooscript::Object)  {}
std::optional<std::string> OOJSEntityHolder::jsDescription()  { return std::nullopt; }


// oo::ToObjC (Entity+ObjCBridge.mm): the object of each C++ part the test wrapped, nil for any
// other (the binding asks it where its natives still message the object, bead oo-9ht.39.3).
namespace {
std::map<Entity *, TestEntityObject *> sObjects;
}
::TestEntityObject *TestObjectOf(Entity *entity);	// oo::ToObjC until bead oo-4aq6a.11
::TestEntityObject *TestObjectOf(Entity *entity)
{
	auto found = sObjects.find(entity);
	return found != sObjects.end() ? found->second : nullptr;
}


// The waypoint's beacon and orientation, on its object's fields, as the object's selectors answered
// them until bead oo-9ht.39.8.18.
std::optional<std::string> OOWaypointEntity::beaconCode()  { return TestObjectOf(this)->_beaconCode; }
void OOWaypointEntity::setBeaconCode(const std::optional<std::string> &bcode)  { TestObjectOf(this)->_beaconCode = bcode; }
std::optional<std::string> OOWaypointEntity::beaconLabel()  { return TestObjectOf(this)->_beaconLabel; }
void OOWaypointEntity::setBeaconLabel(const std::optional<std::string> &blabel)  { TestObjectOf(this)->_beaconLabel = blabel; }
bool OOWaypointEntity::isBeacon()  { const std::optional<std::string> &code = TestObjectOf(this)->_beaconCode; return code.has_value() && !code->empty(); }
Quaternion Entity::getOrientation()  { return TestObjectOf(this)->_orientation; }
void Entity::setNormalOrientation(Quaternion quat)  { TestObjectOf(this)->_orientation = quat; }


// MARK: The context -------------------------------------------------------------------------------

namespace {

ooscript::Runtime sRuntime;
ooscript::Context sContext;
ooscript::Object sGlobal;
TestEntityObject *sWaypoint = nullptr;			// the waypoint's object
OOWaypointEntity *sWaypointPart = nullptr;	// its C++ part
FakeGame *sGame = nil;


ooscript::Value JSValueForObject(ooscript::ClassDef *jsClass, ooscript::Object prototype, TestEntityObject *entity)
{
	ooscript::Object object = ooscript::newObject(sContext, jsClass, prototype, nullptr);
	if (entity->_cxxEntity == nullptr)  entity->_cxxEntity = oo::makeRef<Entity>();	// a plain entity's C++ part
	if (object == nullptr || !OOJSSetCxxPrivate(sContext, object, oo::makeRef<OOJSEntityHolder>(entity->_cxxEntity.get()).get()))  return ooscript::nullValue();	// the slot holds the C++ entity (bead oo-9ht.39.3)
	sObjects[entity->_cxxEntity.get()] = entity;
	return ooscript::objectValue(object);
}


// A JS object for an entity, as -[TestEntityObject oo_jsValueInContext:] makes it: the class and prototype
// the entity's category names, and the entity in the private slot.
ooscript::Value JSValueForEntity(TestEntityObject *entity)
{
	ooscript::ClassDef *jsClass = nullptr;
	ooscript::Object prototype = nullptr;
	entity->getJSClass(&jsClass, &prototype);
	return JSValueForObject(jsClass, prototype, entity);
}


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
	gOOEntityJSPrototype = ooscript::initClass(sContext, sGlobal, nullptr, &sFakeEntityClass, OOJSUnconstructableConstruct, 0, nullptr, nullptr, nullptr, nullptr);
	InitOOJSWaypoint(sContext, sGlobal);

	sGame = new FakeGame();	// kept for the life of the test
	gSharedUniverse = sGame;
	gOOPlayer = new PlayerEntity;	// never deleted
	gOOPlayer->_game = sGame;
	sWaypoint = oo::makeRef<TestEntityObject>().leakRef();	// kept for the life of the test
	sWaypoint->_cxxEntity = oo::makeRef<OOWaypointEntity>();
	sWaypointPart = static_cast<OOWaypointEntity *>(sWaypoint->_cxxEntity.get());
	sWaypoint->_beaconLabel = "Label";
	sWaypoint->_orientation = make_quaternion(0, 1, 0, 0);
	sWaypointPart->_oriented = YES;
	sWaypointPart->_size = 20;
	Define("waypoint", JSValueForEntity(sWaypoint));
	Define("plainEntity", JSValueForObject(&sFakeEntityClass, gOOEntityJSPrototype, oo::makeRef<TestEntityObject>().leakRef()));
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
	ooscript::ClassDef *waypointClass = nullptr;
	ooscript::Object prototype = nullptr;
	sWaypoint->getJSClass(&waypointClass, &prototype);
	OO_CHECK(waypointClass != nullptr && std::strcmp(waypointClass->name, "Waypoint") == 0);
	OO_CHECK(prototype != nullptr);
	OO_CHECK(OOJSIsSubclass(waypointClass, &sFakeEntityClass));
	OO_CHECK_EQ(sConverters[waypointClass], 1);
	OO_CHECK(sWaypoint->cxx_oo_jsClassName() == std::optional<std::string>("Waypoint"));
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
	sWaypointPart->_oriented = NO;
	OO_CHECK_EVAL("waypoint.orientation", "0,0,0,0");	// unoriented: the zero quaternion
	sWaypointPart->_oriented = YES;
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
	OO_CHECK(ooscript::isInRequest(sContext));
}


OO_TEST_MAIN()
