/*	test_OOJSCall.cpp
	Unit tests for OOJSCallEntityMethod() (src/Core/Scripting/OOJSCall.h/.cpp), a Phase 3
	scripting file.

	OOJSCallObjCObjectMethod() implemented the debug-build callObjC(): it called an Objective-C
	method by name on an object, choosing how by the method's signature. The test runs the call in
	a real QuickJS-ng context and links the game's own objects for the file and the signature
	reader (OOShaderUniformMethodType.cpp). What the rest of the engine would provide is defined
	below as the smallest stand-in that does the same thing: the error reporter, the string and
	property-list converters, Vector3D and Quaternion (plain arrays here), and the ship and player
	classes (the call makes a ship the player's script target). The game's headers for those are
	not included, because the test defines those classes.

	The Objective-C object path (OOJSCallObjCObjectMethod; the console's callObjC() is given only
	entities and monitors) is gone: its cases voidAndStringMethods, scalarMethods, objectMethods,
	errors and shipBecomesScriptTarget, and the object call of entityMethodsByTable, retired with
	it, after the surviving entity call's signatures, results and errors were pinned
	(entityResultsByTable). The test's entity objects are C++: its by-name stand-ins answer the
	names the entity's object answered from a table of the test's own.
	Run: bash tools/check-core-tests.sh
*/

#import "OOJSCall.h"
#import "OOEntityCalledByName.h"	// oo::CallEntityByNameTyped, stood in below
#import "OOCallByName.h"
#import "OOMaths.h"
#include <quickjs.h>
#include "OOJSEngineCore.h"	// with OOJSEngineNativeWrappers.h, for the profiler frame
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "EntityPListForeign.h"	// an entity's node
#import "OODescription.h"
#include <cstring>

#include "oo_test.hpp"

#include <cstdarg>
#include <string>
#include <vector>


#ifdef OO_DEBUG_MONITOR_ENABLED	// the condition OOJSCall.h declares the call under

// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
JSContext *sContext = nullptr;
std::string sLastError;
} // namespace


void cxx_OOJSReportError(JSContext *context, const char *format, ...)
{
	(void)context;
	va_list args;
	va_start(args, format);
	sLastError = oo::str::vformat(format, args);
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


std::optional<std::string> cxx_OOStringFromJSValueEvenIfNull(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value))  return std::string("null");
	if (JS_IsUndefined(value))  return std::string("undefined");
	return cxx_OOStringFromJSValue(context, value);
}


class TestEntityObject;
::TestEntityObject *TestObjectOf(Entity *entity);	// below

// A property list as JS: strings, numbers and booleans as themselves; an object node as the
// string "<object CLASS>", which is enough to see which object came back (an entity's node: its
// object's class; any other node held no Objective-C object, nil's class "(null)"). Owned by the
// caller.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist);


namespace {

// An array of the numbers, owned by the caller.
JSValue ArrayOf(JSContext *context, std::vector<double> numbers)
{
	JSValue array = JS_NewArray(context);
	std::uint32_t index = 0;
	for (double n : numbers)  JS_SetPropertyUint32(context, array, index++, JS_NewNumber(context, n));
	return array;
}

} // namespace

JSValue JSVectorWithVector(JSContext *context, Vector vector)
{
	return ArrayOf(context, { vector.x, vector.y, vector.z });
}


JSValue JSQuaternionWithQuaternion(JSContext *context, Quaternion quaternion)
{
	return ArrayOf(context, { quaternion.w, quaternion.x, quaternion.y, quaternion.z });
}


// Link stub (amendment oo-zffj item 2): OOShaderUniformMethodType.mm's matrix reader answers it for
// a nil object; the test calls no matrix method, and OOMatrix.mm would bring OpenGL.
extern "C" const OOMatrix kZeroMatrix = {};


#if OOJS_PROFILE
void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  {}
void OOJSProfileExit(OOJSProfileStackFrame *)  {}
#endif


// The ship and player classes, as far as the call sees them: a ship becomes the player's script
// target. Declared as Entity.h and ShipEntity.h declare them (the test includes neither).
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
};

// An entity's object, C++ (it was rooted on the Objective-C root class OOObject, which is gone):
// its class's runtime name, and the names it answered by selector, which the by-name stand-ins
// below answer from the test's own table.
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

// The player is C++ (its Objective-C class is deleted): the C++ player as far as
// the call sees it (declared as PlayerEntity.h declares it; the test includes no game header that
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

	::ShipEntity *scriptTarget = nullptr;
};

void PlayerEntity::setScriptTarget(::ShipEntity *target)  { scriptTarget = target; }

PlayerEntity *gOOPlayer = nullptr;
TestPlayerObject *sPlayerObject = nullptr;	// the player's object

::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? (::TestEntityObject *)sPlayerObject : nullptr; }	// only the player crosses
#define OO_ENTITY_HELPERS_STAND_IN_CXX 1
#import "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects


JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	std::string text;
	switch (plist.type())
	{
		case oo::PList::Type::Bool:  return JS_NewBool(context, plist.boolValue());
		case oo::PList::Type::Integer:
		case oo::PList::Type::Real:  return JS_NewNumber(context, plist.doubleValue());
		case oo::PList::Type::String:  text = *plist.getIf<std::string>();  break;
		case oo::PList::Type::Object:
		{
			Entity *entity = oo::EntityIn(plist);	// an entity's node: its object
			::TestEntityObject *object = (entity != nullptr) ? TestObjectOf(entity) : nullptr;
			text = std::string("<object ") + (object != nullptr ? object->className() : "(null)") + ">";
			break;
		}
		default:  return JS_NULL;
	}
	return JS_NewStringLen(context, text.data(), text.size());
}


/*	OOEntityCalledByName.mm's, which the test does not link: the test's entities have no C++ table
	of the game's, so the names the player's object answered are answered from the test's own (what
	its Objective-C object's methods returned): the typed results, a void method and a
	string-argument method that record their calls, and a property-list method.
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


// The typed call on the C++ table, which callObjC() takes for every typed name of an entity's
// table: the values the object's methods answered.
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


// MARK: Calling -----------------------------------------------------------------------------------

namespace {

JSContext *Context()
{
	if (sContext == nullptr)
	{
		JSRuntime *runtime = JS_NewRuntime();
		JS_SetMemoryLimit(runtime, 8u * 1024u * 1024u);
		sContext = JS_NewContext(runtime);
		oo::Ref<PlayerEntity> player = oo::makeRef<PlayerEntity>();
		gOOPlayer = player.get();	// never deleted: its object holds it
		sPlayerObject = new TestPlayerObject();	// never released, as the Objective-C object was not
		sPlayerObject->_cxxEntity = player;
	}
	return sContext;
}


// A string value, owned by the caller.
JSValue StringValue(const char *text)
{
	return JS_NewStringLen(Context(), text, std::strlen(text));
}


// Calls the name (and arguments) on an entity by callObjC()'s entity name table; gives the result
// as a string ("<unchanged>" when the call left it alone), or "error: <message>". Frees the
// arguments.
std::string CallEntity(Entity *entity, std::vector<JSValue> argv)
{
	sLastError.clear();
	const JSValue marker = StringValue("<unchanged>");	// a marker no call writes
	JSValue result = marker;
	bool OK = OOJSCallEntityMethod(Context(), entity, "Test", static_cast<int>(argv.size()), argv.data(), &result);
	std::string text = OK ? cxx_OOStringFromJSValueEvenIfNull(Context(), result).value_or("<none>") : "error: " + sLastError;
	// A result the call set is owned here, besides the marker.
	if (JS_VALUE_GET_TAG(result) != JS_VALUE_GET_TAG(marker) || JS_VALUE_GET_PTR(result) != JS_VALUE_GET_PTR(marker))  JS_FreeValue(Context(), result);
	JS_FreeValue(Context(), marker);
	for (JSValue argument : argv)  JS_FreeValue(Context(), argument);
	return text;
}


std::string CallEntity(Entity *entity, const char *selector)
{
	return CallEntity(entity, std::vector<JSValue>{ StringValue(selector) });
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

// callObjC() on an entity by its name table: a name of the table that the entity's
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
		OO_CHECK_EQ(CallEntity(gOOPlayer, std::vector<JSValue>{}), "error: Test.callObjC(): no selector specified.");
	}
}


/*	The entity call's signatures, results and errors: what the deleted object path's cases
	(voidAndStringMethods, scalarMethods, objectMethods, errors) pinned for the forms the entity
	table uses, through the table: a void method, a string parameter (the parameters joined with
	spaces), a property-list result (a null one leaves the result), a boolean, a float and a double,
	a vector and a quaternion, an entity result and a null one, a matrix that cannot be called, a
	parameter missing, and parameters after a name with no colon.
*/
OO_TEST(entityResultsByTable)
{
	{
		oo::AutoreleaseScope pool;
		Context();
		sEntityCalls.clear();
		OO_CHECK_EQ(CallEntity(gOOPlayer, "removeScript"), "<unchanged>");
		OO_CHECK_EQ(CallEntity(gOOPlayer, { StringValue("addRole:"), StringValue("hello"), JS_NewInt32(Context(), 3), JS_NULL }), "<unchanged>");
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


#else

OO_TEST(releaseBuild)
{
	OO_CHECK(true);	// callObjC() is debug-only
}

#endif


OO_TEST_MAIN()
