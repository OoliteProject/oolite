/*	test_OOJSCall.mm
	Unit tests for OOJSCallObjCObjectMethod() (src/Core/Scripting/OOJSCall.h/.mm): bead oo-81hy,
	a Phase 3 scripting file (proposed ADR-0056 amendment oo-ppc).

	OOJSCallObjCObjectMethod() implements the debug-build callObjC(): it calls an Objective-C
	method by name on an object, choosing how by the method's signature, which it matches against
	the type encodings of a template class's methods. The test runs it in a real QuickJS-ng context
	and links the game's own objects for the file, the by-name dispatcher (OOCallByName.mm) and the
	signature reader (OOShaderUniformMethodType.mm). What the rest of the engine would provide is defined below as
	the smallest stand-in that does the same thing (amendment oo-ppc item 6): the error reporter,
	the string and property-list converters, Vector3D and Quaternion (plain arrays here), and the
	ship and player classes (the call makes a ship the player's script target). The game's
	headers for those are not imported, because the test defines those classes (amendment oo-z1s4
	item 4). The expectations were written against the Objective-C file and run on it first; they
	pin every signature it calls (void, string parameter, property-list result, integers, floats,
	vector, quaternion, object, "_bool" objects), the joined parameter string, and each error.
	Run: bash tools/check-core-tests.sh
*/

#import "OOJSCall.h"
#import "OOEntityCalledByName.h"	// oo::CallEntityByNameTyped, stood in below
#import "OOCallByName.h"
#import "OOShaderUniformMethodType.h"	// OOCallIntegerMethod (the typed call's stand-in)
#include <objc/runtime.h>
#include "oofnd/objc/OORuntime.h"
#import "oofnd/objc/OOObject.h"
#import "OOMaths.h"
#include <quickjs.h>
#import "OOJSEngineCore.h"	// with OOJSEngineNativeWrappers.h, for the profiler frame
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#import "OOObjCPList.h"
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


@class TestEntityObject;
namespace oo { ::TestEntityObject *ToObjC(Entity *entity); }	// below

// A property list as JS: strings, numbers and booleans as themselves; an object node as the
// string "<object CLASS>", which is enough to see which object came back. Owned by the caller.
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
			id object = entity != nullptr ? (id)oo::ToObjC(entity) : oo::ObjectIn(plist);
			text = "<object " + oo::DescriptionOf([object class]) + ">";
			break;
		}
		default:  return JS_NULL;
	}
	return JS_NewStringLen(context, text.data(), text.size());
}


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
// target. The ship is C++ (the Objective-C ship is deleted): a ship's object is the
// root's, which holds the C++ part (oo::ToCxx reads it); declared as Entity.h and ShipEntity.h
// declare them (the test imports neither).
class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();
};

__attribute__((objc_runtime_name("Entity")))
@interface TestEntityObject: OOObject
{
@public
	oo::Ref<Entity> _cxxEntity;
}
@end

@implementation TestEntityObject
@end

class ShipEntity : public Entity
{
};

Entity::~Entity() = default;

// The player is C++ (its Objective-C class is deleted): the C++ player as far as
// the call sees it (declared as PlayerEntity.h declares it; the test imports no game header that
// defines the class) and its Objective-C object, a ship (the ship's facade in the game), which
// oo::ToObjC answers.
@interface TestPlayerObject: TestEntityObject
@end

@implementation TestPlayerObject
- (BOOL) isPlayer  { return YES; }	// a name of callObjC()'s entity table
@end

class PlayerEntity : public ShipEntity
{
public:
	void setScriptTarget(::ShipEntity *target);

	::ShipEntity *scriptTarget = nullptr;
};

void PlayerEntity::setScriptTarget(::ShipEntity *target)  { scriptTarget = target; }

PlayerEntity *gOOPlayer = nullptr;
TestPlayerObject *sPlayerObject = nil;	// the player's Objective-C object

@class TestEntityObject;
class Entity;
namespace oo {
::TestEntityObject *ToObjC(Entity *entity)  { return entity != nullptr ? (::TestEntityObject *)sPlayerObject : nil; }	// only the player crosses
}
#import "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects

// OOEntityCalledByName.mm's, which the test does not link: the test's entities
// have no C++ table, so every name goes to the object by selector, the path callObjC() takes for a
// name that table does not hold.
bool oo::EntityRespondsToName(Entity *entity, const std::string &name)
{
	::TestEntityObject *object = oo::ToObjC(entity);
	return object != nil && [object respondsToSelector:OOSelectorFromName(name.c_str())];
}
oo::PList oo::CallEntityByName(Entity *entity, const std::string &name)  { return entity != nullptr ? OOCallByName(oo::ToObjC(entity), OOSelectorFromName(name.c_str())) : oo::PList(); }
oo::PList oo::CallEntityByName(Entity *entity, const std::string &name, const std::string &argument)  { return entity != nullptr ? OOCallByName(oo::ToObjC(entity), OOSelectorFromName(name.c_str()), argument) : oo::PList(); }
// The typed call on the C++ table, which callObjC() takes for every name of an entity's table (the
// call no longer has the entity's object): the test's
// entities have no C++ table, so it answers what the object's method answers, as the selector path
// read it (an integer result: the only kind the test's entity names have).
bool oo::CallEntityByNameTyped(Entity *entity, const std::string &name, OOEntityByNameValue &value)
{
	::TestEntityObject *object = oo::ToObjC(entity);
	SEL selector = OOSelectorFromName(name.c_str());
	if (object == nil || ![object respondsToSelector:selector])  return false;
	const OOShaderUniformType type = OOShaderUniformTypeFromMethod(class_getInstanceMethod(object_getClass(object), selector));
	value.integer = OOCallIntegerMethod(object, selector, [object methodForSelector:selector], type);
	return true;
}


// MARK: The object called -------------------------------------------------------------------------

@interface TestBoolean: OOObject
{
@public
	BOOL value;
}
- (BOOL) boolValue;
@end

@implementation TestBoolean
- (BOOL) boolValue  { return value; }
@end

@interface TestInteger: OOObject
{
@public
	int value;
}
- (int) intValue;
@end

@implementation TestInteger
- (int) intValue  { return value; }
@end


@interface TestTarget: OOObject
{
@public
	std::vector<std::string> calls;
}
@end

@implementation TestTarget

- (void) poke  { calls.push_back("poke"); }
- (void) say:(const std::string &)text  { calls.push_back("say:" + text); }
- (oo::PList) echo:(const std::string &)text  { return oo::PList("echo " + text); }
- (oo::PList) plist  { return oo::PList(12.5); }
- (oo::PList) plist_bool  { return oo::PList(std::string("yes")); }
- (oo::PList) nothing  { return oo::PList(); }
- (int) answer  { return 42; }
- (int) negative  { return -7; }
- (unsigned long) big  { return 4000000000UL; }
- (float) half  { return 0.5f; }
- (double) third  { return 1.0 / 4.0; }
- (Vector) vector  { return make_vector(1, 2, 3); }
- (Quaternion) quaternion  { return make_quaternion(1, 0, 0, 0); }
- (id) selfObject  { return self; }
- (id) nilObject  { return nil; }
- (id) true_bool  { TestBoolean *b = [[[TestBoolean alloc] init] autorelease]; b->value = YES; return b; }
- (id) false_bool  { TestBoolean *b = [[[TestBoolean alloc] init] autorelease]; b->value = NO; return b; }
- (id) seven_bool  { TestInteger *i = [[[TestInteger alloc] init] autorelease]; i->value = 7; return i; }
- (id) plain_bool  { return [[[OOObject alloc] init] autorelease]; }
- (NSPoint) point  { return NSMakePoint(1, 2); }
- (void) takesInt:(int)value  { calls.push_back(oo::str::format("int %d", value)); }

@end


@interface TestShip: TestEntityObject
- (int) answer;
@end

@implementation TestShip
// Every test ship has its C++ part (the ship).
- (id) init
{
	if ((self = [super init]))  _cxxEntity = oo::makeRef<ShipEntity>();
	return self;
}
- (int) answer  { return 1; }
@end


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
		sPlayerObject = [[TestPlayerObject alloc] init];
		sPlayerObject->_cxxEntity = player;
	}
	return sContext;
}


// A string value, owned by the caller.
JSValue StringValue(const char *text)
{
	return JS_NewStringLen(Context(), text, std::strlen(text));
}


// Calls selector (and arguments) on object; gives the result as a string ("<unchanged>" when the
// call left it alone), or "error: <message>". Frees the arguments.
std::string Call(id object, std::vector<JSValue> argv)
{
	sLastError.clear();
	const JSValue marker = StringValue("<unchanged>");	// a marker no call writes
	JSValue result = marker;
	bool OK = OOJSCallObjCObjectMethod(Context(), object, "Test", static_cast<int>(argv.size()), argv.data(), &result);
	std::string text = OK ? cxx_OOStringFromJSValueEvenIfNull(Context(), result).value_or("<none>") : "error: " + sLastError;
	// A result the call set is owned here, besides the marker.
	if (JS_VALUE_GET_TAG(result) != JS_VALUE_GET_TAG(marker) || JS_VALUE_GET_PTR(result) != JS_VALUE_GET_PTR(marker))  JS_FreeValue(Context(), result);
	JS_FreeValue(Context(), marker);
	for (JSValue argument : argv)  JS_FreeValue(Context(), argument);
	return text;
}


std::string Call(id object, const char *selector)
{
	return Call(object, std::vector<JSValue>{ StringValue(selector) });
}


// The same for an entity, by callObjC()'s entity name table. Frees the arguments.
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

OO_TEST(voidAndStringMethods)
{
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK_EQ(Call(target, "poke"), "<unchanged>");
		OO_CHECK_EQ(Call(target, { StringValue("say:"), StringValue("hello"), JS_NewInt32(Context(), 3), JS_NULL }), "<unchanged>");
		OO_CHECK_EQ(target->calls.size(), 2u);
		if (target->calls.size() == 2)
		{
			OO_CHECK_EQ(target->calls[0], "poke");
			OO_CHECK_EQ(target->calls[1], "say:hello 3 null");	// the parameters joined with spaces
		}
		OO_CHECK_EQ(Call(target, { StringValue("echo:"), StringValue("a"), StringValue("b") }), "echo a b");
		OO_CHECK_EQ(Call(target, "plist"), "12.5");
		OO_CHECK_EQ(Call(target, "plist_bool"), "true");	// a string read as a boolean
		OO_CHECK_EQ(Call(target, "nothing"), "<unchanged>");	// a null result leaves it
	}
}


OO_TEST(scalarMethods)
{
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK_EQ(Call(target, "answer"), "42");
		OO_CHECK_EQ(Call(target, "negative"), "-7");
		OO_CHECK_EQ(Call(target, "big"), "4000000000");
		OO_CHECK_EQ(Call(target, "half"), "0.5");
		OO_CHECK_EQ(Call(target, "third"), "0.25");
		OO_CHECK_EQ(Call(target, "vector"), "1,2,3");
		OO_CHECK_EQ(Call(target, "quaternion"), "1,0,0,0");
	}
}


OO_TEST(objectMethods)
{
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK_EQ(Call(target, "selfObject"), "<object TestTarget>");
		OO_CHECK_EQ(Call(target, "nilObject"), "<unchanged>");
		OO_CHECK_EQ(Call(target, "true_bool"), "true");
		OO_CHECK_EQ(Call(target, "false_bool"), "false");
		OO_CHECK_EQ(Call(target, "seven_bool"), "true");
		OO_CHECK_EQ(Call(target, "plain_bool"), "false");
	}
}


OO_TEST(errors)
{
	@autoreleasepool
	{
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK_EQ(Call(target, std::vector<JSValue>{}), "error: Test.callObjC(): no selector specified.");
		OO_CHECK_EQ(Call(target, "say:"), "error: Test.callObjC(): method say: requires a parameter.");
		OO_CHECK_EQ(Call(target, "point"), "error: Test.callObjC(): method point cannot be called from JavaScript.");
		OO_CHECK_EQ(Call(target, { StringValue("takesInt:"), JS_NewInt32(Context(), 1) }), "error: Test.callObjC(): method takesInt: cannot be called from JavaScript.");
		OO_CHECK(Call(target, "noSuchMethod").rfind("error: Test.callObjC(): <TestTarget ", 0) == 0);
		OO_CHECK(Call(target, "noSuchMethod").find("> does not respond to method noSuchMethod.") != std::string::npos);
		// Parameters after a selector with no colon are ignored.
		OO_CHECK_EQ(Call(target, { StringValue("answer"), StringValue("x") }), "42");
		OO_CHECK(target->calls.empty());
	}
}


OO_TEST(shipBecomesScriptTarget)
{
	@autoreleasepool
	{
		Context();
		TestShip *ship = [[[TestShip alloc] init] autorelease];
		gOOPlayer->scriptTarget = nullptr;
		OO_CHECK_EQ(Call(ship, "answer"), "1");
		TestTarget *target = [[[TestTarget alloc] init] autorelease];
		OO_CHECK_EQ(Call(target, "answer"), "42");
		// (That a ship's Objective-C object, called by the object path, made its C++ ship the script
		// target, and a non-ship left it: retired with the root facade, which was every entity's
		// object. The entity path's script target is checked below.)
	}
}


// callObjC() on an entity by its name table: a name of the table that the entity's
// object answers is called with the table's signature; any other name does not respond, even one
// the object answers (a root-class or lifetime selector, or one the facade does not define).
OO_TEST(entityMethodsByTable)
{
	@autoreleasepool
	{
		Context();
		gOOPlayer->scriptTarget = nullptr;
		OO_CHECK_EQ(CallEntity(gOOPlayer, "isPlayer"), "1");
		OO_CHECK_EQ(Call(sPlayerObject, "isPlayer"), "1");	// what the object's signature gave
		OO_CHECK(gOOPlayer->scriptTarget == gOOPlayer);	// the player is a ship: its own script target
		OO_CHECK(CallEntity(gOOPlayer, "retain").find("> does not respond to method retain.") != std::string::npos);
		OO_CHECK(CallEntity(gOOPlayer, "hash").find("> does not respond to method hash.") != std::string::npos);
		OO_CHECK(CallEntity(gOOPlayer, "noSuchMethod").find("> does not respond to method noSuchMethod.") != std::string::npos);
		OO_CHECK_EQ(CallEntity(gOOPlayer, std::vector<JSValue>{}), "error: Test.callObjC(): no selector specified.");
	}
}


#else

OO_TEST(releaseBuild)
{
	OO_CHECK(true);	// callObjC() is debug-only
}

#endif


OO_TEST_MAIN()
