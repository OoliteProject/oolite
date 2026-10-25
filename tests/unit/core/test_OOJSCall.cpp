/*	test_OOJSCall.mm
	Unit tests for OOJSCallEntityMethod() (src/Core/Scripting/OOJSCall.h/.mm): bead oo-81hy,
	a Phase 3 scripting file (proposed ADR-0056 amendment oo-ppc).

	OOJSCallObjCObjectMethod() implemented the debug-build callObjC(): it called an Objective-C
	method by name on an object, choosing how by the method's signature. The test runs the call in
	a real context on the game's own façade backend (ooscript/JSEngine_quickjs.cpp) and links the
	game's own objects for the file and the signature reader (OOShaderUniformMethodType.mm). What
	the rest of the engine would provide is defined below as the smallest stand-in that does the
	same thing (amendment oo-ppc item 6): the error reporter, the string and property-list
	converters, Vector3D and Quaternion (plain arrays here), and the ship and player classes (the
	call makes a ship the player's script target). The game's headers for those are not imported,
	because the test defines those classes (amendment oo-z1s4 item 4).

	Bead oo-4aq6a.5 deleted the Objective-C object path (OOJSCallObjCObjectMethod; the console's
	callObjC() is given only entities and monitors): its cases voidAndStringMethods, scalarMethods,
	objectMethods, errors and shipBecomesScriptTarget, and the object calls of entityMethodsByTable
	and playerStatisticsByName, retired with it (ADR-0062 item 2; std-2026-10-19 item 2), after the
	surviving entity call's signatures, results and errors were pinned (entityResultsByTable,
	ADR-0062 item 3). The test's entity objects are C++ (std-2026-10-19 item 1): its by-name
	stand-ins answer the names the entity's object answered from a table of the test's own.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJSCall.h"
#include "OOEntityCalledByName.h"	// oo::CallEntityByNameTyped, stood in below (bead oo-9ht.39.7.2)
#include "OOCallByName.h"
#include "OOMaths.h"
#include "ooscript/JSEngine.hpp"
#include "OOJSEngineNativeWrappers.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "EntityPListForeign.h"	// an entity's node (bead oo-dpyk8)
#include "OODescription.h"
#include <cstring>

#include "oo_test.hpp"

#include <cstdarg>
#include <string>
#include <vector>


#ifndef NDEBUG

// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
ooscript::Context sContext = nullptr;
std::string sLastError;
} // namespace


void cxx_OOJSReportError(ooscript::Context context, const char *format, ...)
{
	(void)context;
	va_list args;
	va_start(args, format);
	sLastError = oo::str::vformat(format, args);
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


std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(ooscript::Context context, ooscript::Value value)
{
	if (ooscript::isNull(value))  return std::string("null");
	if (ooscript::isUndefined(value))  return std::string("undefined");
	return cxx_OOStringFromJSValue(context, value);
}


class TestEntityObject;
::TestEntityObject *TestObjectOf(Entity *entity);	// below (oo::ToObjC until bead oo-4aq6a.5)

// A property list as JS: strings, numbers and booleans as themselves; an object node as the
// string "<object CLASS>", which is enough to see which object came back (an entity's node: its
// object's class; any other node held no Objective-C object, nil's class "(null)").
ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist);


namespace {

ooscript::Object ArrayOf(ooscript::Context context, std::vector<double> numbers)
{
	std::vector<ooscript::Value> values;
	for (double n : numbers)  values.push_back(ooscript::numberValue(n));
	return ooscript::newArrayObject(context, static_cast<unsigned>(values.size()), values.data());
}

} // namespace

extern "C" ooscript::Object JSVectorWithVector(ooscript::Context context, Vector vector)
{
	return ArrayOf(context, { vector.x, vector.y, vector.z });
}


extern "C" ooscript::Object JSQuaternionWithQuaternion(ooscript::Context context, Quaternion quaternion)
{
	return ArrayOf(context, { quaternion.w, quaternion.x, quaternion.y, quaternion.z });
}


// Link stub (amendment oo-zffj item 2): OOShaderUniformMethodType.mm's matrix reader answers it for
// a nil object; the test calls no matrix method, and OOMatrix.mm would bring OpenGL.
extern "C" const OOMatrix kZeroMatrix = {};


#if OOJS_PROFILE
extern "C" void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  {}
extern "C" void OOJSProfileExit(OOJSProfileStackFrame *)  {}
#endif

extern "C" void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}


// The ship and player classes, as far as the call sees them: a ship becomes the player's script
// target. Declared as Entity.h and ShipEntity.h declare them (the test imports neither).
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
};

// An entity's object, C++ since bead oo-4aq6a.5 (it was rooted on the Objective-C root class
// OOObject, which Phase 4 deletes): its class's runtime name, and the names it answered by selector,
// which the by-name stand-ins below answer from the test's own table.
class TestEntityObject : public oo::RefCounted
{
public:
	virtual const char *className() const  { return "Entity"; }

	oo::Ref<Entity> _cxxEntity;
};

class ShipEntity : public Entity
{
};

Entity::~Entity() = default;

// The player is C++ since bead oo-9ht.177 deleted its Objective-C class: the C++ player as far as
// the call sees it (declared as PlayerEntity.h declares it; the test imports no game header that
// defines the class) and its object, a ship (the ship's facade in the game).
class TestPlayerObject final : public TestEntityObject
{
public:
	const char *className() const override  { return "TestPlayerObject"; }
};

class PlayerEntity : public ShipEntity
{
public:
	void setScriptTarget(::ShipEntity *target);
#if OO_DEBUG
	// The statistics members, which callObjC's name table calls by name (bead oo-9ht.15), as far
	// as the table sees them: each records its call and answers a marker.
	static oo::PList reportJSVectorStatistics();
	static void clearJSVectorStatistics();
	static oo::PList reportJSQuaternionStatistics();
	static void clearJSQuaternionStatistics();
#endif

	::ShipEntity *scriptTarget = nullptr;
};

void PlayerEntity::setScriptTarget(::ShipEntity *target)  { scriptTarget = target; }

PlayerEntity *gOOPlayer = nullptr;
TestPlayerObject *sPlayerObject = nullptr;	// the player's object

::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? (::TestEntityObject *)sPlayerObject : nullptr; }	// only the player crosses
#define OO_ENTITY_HELPERS_STAND_IN_CXX 1
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)


ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	std::string text;
	switch (plist.type())
	{
		case oo::PList::Type::Bool:  return ooscript::booleanValue(plist.boolValue());
		case oo::PList::Type::Integer:
		case oo::PList::Type::Real:  return ooscript::numberValue(plist.doubleValue());
		case oo::PList::Type::String:  text = *plist.getIf<std::string>();  break;
		case oo::PList::Type::Object:
		{
			Entity *entity = oo::EntityIn(plist);	// an entity's node: its object (bead oo-dpyk8)
			::TestEntityObject *object = (entity != nullptr) ? TestObjectOf(entity) : nullptr;
			text = std::string("<object ") + (object != nullptr ? object->className() : "(null)") + ">";
			break;
		}
		default:  return ooscript::nullValue();
	}
	return ooscript::stringValue(ooscript::newStringCopyN(context, text.data(), text.size()));
}


/*	OOEntityCalledByName.mm's (bead oo-9ht.39.7.2), which the test does not link: the test's entities
	have no C++ table of the game's, so the names the player's object answered are answered from the
	test's own (what its Objective-C object's methods returned): the typed results, a void method and
	a string-argument method that record their calls, and a property-list method.
*/
namespace {

std::vector<std::string> sEntityCalls;
oo::PList sShipInfo;	// what cxx_shipInfoDictionary answers (null: a null result)
Entity *sOwner = nullptr;	// what owner answers

}	// namespace

bool oo::EntityRespondsToName(Entity *entity, const std::string &name)
{
	if (TestObjectOf(entity) == nullptr)  return false;
	static const char *const kNames[] = { "isPlayer", "speed", "thrust", "velocity", "orientation", "rotationMatrix", "owner", "removeScript", "addRole:", "cxx_shipInfoDictionary", "retain", "hash" };
	for (const char *known : kNames)
	{
		if (name == known)  return true;
	}
	return false;
}


oo::PList oo::CallEntityByName(Entity *entity, const std::string &name)
{
	if (entity == nullptr)  return oo::PList();
	sEntityCalls.push_back(name);
	if (name == "cxx_shipInfoDictionary")  return sShipInfo;
	return oo::PList();
}


oo::PList oo::CallEntityByName(Entity *entity, const std::string &name, const std::string &argument)
{
	if (entity == nullptr)  return oo::PList();
	sEntityCalls.push_back(name + argument);
	return oo::PList();
}


// The typed call on the C++ table (bead oo-9ht.39.7.2), which callObjC() takes for every typed name
// of an entity's table since bead oo-9ht.39.8.25: the values the object's methods answered.
bool oo::CallEntityByNameTyped(Entity *entity, const std::string &name, OOEntityByNameValue &value)
{
	if (!oo::EntityRespondsToName(entity, name))  return false;
	if (name == "isPlayer")  value.integer = 1;
	else if (name == "speed")  value.real = 1.0 / 4.0;
	else if (name == "thrust")  value.real = 0.5f;
	else if (name == "velocity")  value.vector = make_vector(1, 2, 3);
	else if (name == "orientation")  value.quaternion = make_quaternion(1, 0, 0, 0);
	else if (name == "owner")  value.entity = sOwner;
	return true;
}


#if OO_DEBUG

namespace {
std::vector<std::string> sStatisticsCalls;
}	// namespace

oo::PList PlayerEntity::reportJSVectorStatistics()		{ sStatisticsCalls.push_back("reportJSVectorStatistics"); return oo::PList(std::string("vector statistics")); }
void PlayerEntity::clearJSVectorStatistics()			{ sStatisticsCalls.push_back("clearJSVectorStatistics"); }
oo::PList PlayerEntity::reportJSQuaternionStatistics()	{ sStatisticsCalls.push_back("reportJSQuaternionStatistics"); return oo::PList(std::string("quaternion statistics")); }
void PlayerEntity::clearJSQuaternionStatistics()		{ sStatisticsCalls.push_back("clearJSQuaternionStatistics"); }
#endif


// MARK: Calling -----------------------------------------------------------------------------------

namespace {

ooscript::Context Context()
{
	if (sContext == nullptr)
	{
		ooscript::Runtime runtime = ooscript::newRuntime(8u * 1024u * 1024u);
		sContext = ooscript::newContext(runtime, 8192);
		ooscript::beginRequest(sContext);
		ooscript::initStandardClasses(sContext, ooscript::getGlobalObject(sContext));
		oo::Ref<PlayerEntity> player = oo::makeRef<PlayerEntity>();
		gOOPlayer = player.get();	// never deleted: its object holds it
		sPlayerObject = new TestPlayerObject();	// never released, as the Objective-C object was not
		sPlayerObject->_cxxEntity = player;
	}
	return sContext;
}


ooscript::Value StringValue(const char *text)
{
	return ooscript::stringValue(ooscript::newStringCopyN(Context(), text, std::strlen(text)));
}


// Calls the name (and arguments) on an entity by callObjC()'s entity name table (bead oo-9ht.44);
// gives the result as a string ("<unchanged>" when the call left it alone), or "error: <message>".
std::string CallEntity(Entity *entity, std::vector<ooscript::Value> argv)
{
	sLastError.clear();
	ooscript::Value result = StringValue("<unchanged>");	// a marker no call writes
	bool OK = OOJSCallEntityMethod(Context(), entity, "Test", static_cast<unsigned>(argv.size()), argv.data(), &result);
	if (!OK)  return "error: " + sLastError;
	return cxx_OOStringFromJSValueEvenIfNull(Context(), result).value_or("<none>");
}


std::string CallEntity(Entity *entity, const char *selector)
{
	return CallEntity(entity, std::vector<ooscript::Value>{ StringValue(selector) });
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

// callObjC() on an entity by its name table (bead oo-9ht.44): a name of the table that the entity's
// object answers is called with the table's signature; any other name does not respond, even one
// the object answers (a root-class or lifetime selector, or one the facade does not define).
OO_TEST(entityMethodsByTable)
{
	{
		oo::AutoreleaseScope pool;
		Context();
		gOOPlayer->scriptTarget = nullptr;
		OO_CHECK_EQ(CallEntity(gOOPlayer, "isPlayer"), "1");
		OO_CHECK(gOOPlayer->scriptTarget == gOOPlayer);	// the player is a ship: its own script target
		OO_CHECK(CallEntity(gOOPlayer, "retain").find("> does not respond to method retain.") != std::string::npos);
		OO_CHECK(CallEntity(gOOPlayer, "hash").find("> does not respond to method hash.") != std::string::npos);
		OO_CHECK(CallEntity(gOOPlayer, "noSuchMethod").find("> does not respond to method noSuchMethod.") != std::string::npos);
		OO_CHECK_EQ(CallEntity(gOOPlayer, std::vector<ooscript::Value>{}), "error: Test.callObjC(): no selector specified.");
	}
}


/*	The entity call's signatures, results and errors (bead oo-4aq6a.5, ADR-0062 item 3): what the
	deleted object path's cases (voidAndStringMethods, scalarMethods, objectMethods, errors) pinned
	for the forms the entity table uses, through the table: a void method, a string parameter (the
	parameters joined with spaces), a property-list result (a null one leaves the result), a
	boolean, a float and a double, a vector and a quaternion, an entity result and a null one, a
	matrix that cannot be called, a parameter missing, and parameters after a name with no colon.
*/
OO_TEST(entityResultsByTable)
{
	{
		oo::AutoreleaseScope pool;
		Context();
		sEntityCalls.clear();
		OO_CHECK_EQ(CallEntity(gOOPlayer, "removeScript"), "<unchanged>");
		OO_CHECK_EQ(CallEntity(gOOPlayer, { StringValue("addRole:"), StringValue("hello"), ooscript::int32Value(3), ooscript::nullValue() }), "<unchanged>");
		OO_CHECK_EQ(sEntityCalls.size(), 2u);
		if (sEntityCalls.size() == 2)
		{
			OO_CHECK_EQ(sEntityCalls[0], "removeScript");
			OO_CHECK_EQ(sEntityCalls[1], "addRole:hello 3 null");	// the parameters joined with spaces
		}
		sShipInfo = oo::PList(12.5);
		OO_CHECK_EQ(CallEntity(gOOPlayer, "cxx_shipInfoDictionary"), "12.5");
		sShipInfo = oo::PList();
		OO_CHECK_EQ(CallEntity(gOOPlayer, "cxx_shipInfoDictionary"), "<unchanged>");	// a null result leaves it

		OO_CHECK_EQ(CallEntity(gOOPlayer, "isPlayer"), "1");
		OO_CHECK_EQ(CallEntity(gOOPlayer, "thrust"), "0.5");
		OO_CHECK_EQ(CallEntity(gOOPlayer, "speed"), "0.25");
		OO_CHECK_EQ(CallEntity(gOOPlayer, "velocity"), "1,2,3");
		OO_CHECK_EQ(CallEntity(gOOPlayer, "orientation"), "1,0,0,0");

		sOwner = gOOPlayer;
		OO_CHECK_EQ(CallEntity(gOOPlayer, "owner"), "<object TestPlayerObject>");
		sOwner = nullptr;
		OO_CHECK_EQ(CallEntity(gOOPlayer, "owner"), "<unchanged>");

		OO_CHECK_EQ(CallEntity(gOOPlayer, "addRole:"), "error: Test.callObjC(): method addRole: requires a parameter.");
		OO_CHECK_EQ(CallEntity(gOOPlayer, "rotationMatrix"), "error: Test.callObjC(): method rotationMatrix cannot be called from JavaScript.");
		// Parameters after a name with no colon are ignored.
		OO_CHECK_EQ(CallEntity(gOOPlayer, { StringValue("isPlayer"), StringValue("x") }), "1");
		OO_CHECK_EQ(sEntityCalls.size(), 4u);
	}
}


#if OO_DEBUG
// The player's conversion statistics by name (PS.callObjC("reportJSVectorStatistics")): the
// categories' selectors, now C++ members reached through callObjC's name table (bead oo-9ht.15),
// with the categories' signatures; only the player answers them. The player is called as the C++
// entity it is (its object, which the case called, went with the root facade, bead oo-dpyk8).
OO_TEST(playerStatisticsByName)
{
	{
		oo::AutoreleaseScope pool;
		Context();
		sStatisticsCalls.clear();
		OO_CHECK_EQ(CallEntity(gOOPlayer, "reportJSVectorStatistics"), "vector statistics");
		OO_CHECK_EQ(CallEntity(gOOPlayer, "clearJSVectorStatistics"), "<unchanged>");	// void
		OO_CHECK_EQ(CallEntity(gOOPlayer, "reportJSQuaternionStatistics"), "quaternion statistics");
		OO_CHECK_EQ(CallEntity(gOOPlayer, { StringValue("clearJSQuaternionStatistics"), StringValue("x") }), "<unchanged>");	// parameters ignored
		OO_CHECK_EQ(sStatisticsCalls.size(), 4u);
		if (sStatisticsCalls.size() == 4)
		{
			OO_CHECK_EQ(sStatisticsCalls[0], "reportJSVectorStatistics");
			OO_CHECK_EQ(sStatisticsCalls[1], "clearJSVectorStatistics");
			OO_CHECK_EQ(sStatisticsCalls[2], "reportJSQuaternionStatistics");
			OO_CHECK_EQ(sStatisticsCalls[3], "clearJSQuaternionStatistics");
		}
		OO_CHECK(gOOPlayer->scriptTarget == gOOPlayer);	// the player is a ship: its own script target
		OO_CHECK_EQ(sStatisticsCalls.size(), 4u);
	}
}
#endif

#else

OO_TEST(releaseBuild)
{
	OO_CHECK(true);	// callObjC() is debug-only
}

#endif


OO_TEST_MAIN()
