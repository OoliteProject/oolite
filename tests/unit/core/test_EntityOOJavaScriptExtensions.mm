/*	test_EntityOOJavaScriptExtensions.mm
	Unit tests for the categories Entity (OOJavaScriptExtensions) and ShipEntity
	(OOJavaScriptExtensions) (src/Core/Scripting/EntityOOJavaScriptExtensions.h/.mm): bead oo-g223,
	what the script engine asks an entity by selector (is it visible to scripts, its JS class
	name, its JS class, its JS object) and what scripts ask a ship (its subentities,
	and setting its target, which climbs from a subentity to its root ship on both sides).

	The categories reach the entity's C++ part (_jsSelf), so the test links the whole game but main
	(['*']) and uses the real Entity. A ship is the test's subclass of ShipEntity made with
	class_createInstance (never initialised, never released): it answers the ShipEntity selectors
	the category sends (its subentities, its owner, being a subentity, its targets) and records
	what it was told. The JS object the entity already has is a plain object of a QuickJS-ng
	context the test makes, the engine's main thread context, with Entity's and Ship's JS classes
	registered by their Init functions; the test owns that object and frees it. The expectations
	were written against the Objective-C categories and run on them first; they send only the
	categories' selectors, so the conversion (the bodies as free functions, the categories'
	forwarders in EntityOOJavaScriptExtensions+ObjCBridge.mm) changed no line here. On QuickJS-ng
	(upstream #768's binding) a JS class is its JSClassID, so the class checks compare IDs and the
	prototype checks are gone (the prototype is per context, JS_GetClassProto).
	Run: bash tools/check-core-tests.sh
*/

#import "EntityOOJavaScriptExtensions.h"
#import "ShipEntity.h"
#import "OOJSEntity.h"
#import "OOJSShip.h"

#include "oo_test.hpp"

#include <quickjs.h>

#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// A ship that answers what the category asks a ship, and records the targets it was told.
@interface TestShip: ShipEntity
{
@public
	BOOL							_testIsSubEntity;
	id								_testOwner;
	id								_testPrimaryTarget;
	std::vector<oo::ObjCRef<ShipEntity *>>	_testSubEntities;
	std::vector<std::string>		_told;		// "add <name>" / "remove <name>"
	const char						*_name;
}
@end


@implementation TestShip

- (BOOL) isSubEntity									{ return _testIsSubEntity; }
- (id) owner											{ return _testOwner; }
- (id) primaryTarget									{ return _testPrimaryTarget; }
- (std::vector<oo::ObjCRef<ShipEntity *>>) cxx_shipSubEntities	{ return _testSubEntities; }

- (void) addTarget:(Entity *)targetEntity
{
	_told.push_back(std::string("add ") + (targetEntity != nil ? ((TestShip *)targetEntity)->_name : "nil"));
}

- (void) removeTarget:(Entity *)targetEntity
{
	_told.push_back(std::string("remove ") + (targetEntity != nil ? ((TestShip *)targetEntity)->_name : "nil"));
}

@end


// An entity that scripts can see but that keeps Entity's JS class.
@interface TestVisibleEntity: Entity
@end


@implementation TestVisibleEntity

- (BOOL) isVisibleToScripts  { return YES; }

@end


extern JSContext *gOOJSMainThreadContext;	// the engine's


namespace {

JSContext *sContext = nullptr;


// The test's context is the engine's main thread context (the JS classes register with its
// runtime), with Entity's and Ship's classes registered by their Init functions, as the engine's
// start registers them.
void SetUpContext()
{
	if (sContext != nullptr)  return;
	sContext = JS_NewContext(JS_NewRuntime());
	gOOJSMainThreadContext = sContext;
	JSValue global = JS_GetGlobalObject(sContext);
	InitOOJSEntity(sContext, global);
	InitOOJSShip(sContext, global);
	JS_FreeValue(sContext, global);
}


// Whether two JS values are the same object.
bool SameObject(JSValueConst a, JSValueConst b)
{
	return JS_IsObject(a) && JS_IsObject(b) && JS_VALUE_GET_PTR(a) == JS_VALUE_GET_PTR(b);
}


// A ship made the way the test can (never initialised, never released), with C++ ivars built.
TestShip *Ship(const char *name)
{
	TestShip *ship = (TestShip *)class_createInstance([TestShip class], 0);
	new (&ship->_testSubEntities) std::vector<oo::ObjCRef<ShipEntity *>>();
	new (&ship->_told) std::vector<std::string>();
	ship->_name = name;
	return ship;
}


std::string Told(TestShip *ship)
{
	std::string result;
	for (const std::string &line : ship->_told)  result += (result.empty() ? "" : "; ") + line;
	return result;
}

}	// namespace


OO_TEST(entityIsNotVisible)
{
	@autoreleasepool
	{
		Entity *entity = [[[Entity alloc] init] autorelease];
		OO_CHECK(![entity isVisibleToScripts]);
		OO_CHECK([entity cxx_oo_jsClassName] == std::optional<std::string>("Entity"));

		SetUpContext();
		OO_CHECK([entity oo_jsClassID] == JSEntityClassID());

		// Not visible: no JS object is made, and the value is null.
		JSValue value = [entity oo_jsValueInContext:sContext];
		OO_CHECK(JS_IsNull(value));
		OO_CHECK(!JS_IsObject(entity->_cxxEntity->_jsSelf));

		// With no JS object, -deleteJSSelf does nothing.
		[entity deleteJSSelf];
		OO_CHECK(!JS_IsObject(entity->_cxxEntity->_jsSelf));
	}
}


OO_TEST(existingJSObject)
{
	@autoreleasepool
	{
		SetUpContext();
		JSValue object = JS_NewObject(sContext);
		OO_CHECK(JS_IsObject(object));

		// An entity that already has its JS object answers it, visible or not.
		Entity *entity = [[[Entity alloc] init] autorelease];
		entity->_cxxEntity->_jsSelf = object;
		JSValue value = [entity oo_jsValueInContext:sContext];
		OO_CHECK(JS_IsObject(value));
		OO_CHECK(SameObject(value, object));
		JS_FreeValue(sContext, value);

		TestVisibleEntity *visible = [[[TestVisibleEntity alloc] init] autorelease];
		visible->_cxxEntity->_jsSelf = object;
		value = [visible oo_jsValueInContext:sContext];
		OO_CHECK(SameObject(value, object));
		JS_FreeValue(sContext, value);

		// The test owns the object: the entities let go of it before they go.
		entity->_cxxEntity->_jsSelf = JS_UNDEFINED;
		visible->_cxxEntity->_jsSelf = JS_UNDEFINED;
		JS_FreeValue(sContext, object);
	}
}


OO_TEST(visibleEntityKeepsEntityClass)
{
	@autoreleasepool
	{
		TestVisibleEntity *visible = [[[TestVisibleEntity alloc] init] autorelease];
		OO_CHECK([visible isVisibleToScripts]);
		OO_CHECK([visible cxx_oo_jsClassName] == std::optional<std::string>("Entity"));
		SetUpContext();
		OO_CHECK([visible oo_jsClassID] == JSEntityClassID());
	}
}


OO_TEST(shipIsVisible)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		OO_CHECK([ship isVisibleToScripts]);
		OO_CHECK([ship cxx_oo_jsClassName] == std::optional<std::string>("Ship"));

		SetUpContext();
		OO_CHECK([ship oo_jsClassID] == JSShipClassID());
	}
}


OO_TEST(subEntitiesForScript)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		OO_CHECK([ship subEntitiesForScript].empty());

		TestShip *turret = Ship("turret");
		TestShip *hull = Ship("hull");
		ship->_testSubEntities = { oo::ObjCRef<ShipEntity *>(turret), oo::ObjCRef<ShipEntity *>(hull) };
		std::vector<oo::ObjCRef<Entity *>> subs = [ship subEntitiesForScript];
		OO_CHECK(subs.size() == 2);
		OO_CHECK(subs.size() == 2 && subs[0].get() == turret && subs[1].get() == hull);
		ship->_testSubEntities.clear();
	}
}


OO_TEST(setTarget)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		TestShip *other = Ship("other");
		[ship setTargetForScript:other];
		OO_CHECK(Told(ship) == "add other");
	}
}


OO_TEST(setTargetNilRemovesPrimaryTarget)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		TestShip *current = Ship("current");
		ship->_testPrimaryTarget = current;
		[ship setTargetForScript:nil];
		OO_CHECK(Told(ship) == "remove current");

		// No primary target: remove nil.
		TestShip *idle = Ship("idle");
		[idle setTargetForScript:nil];
		OO_CHECK(Told(idle) == "remove nil");
	}
}


OO_TEST(setTargetClimbsToRootShips)
{
	@autoreleasepool
	{
		// A subentity's target is set on its root ship, and a subentity target is replaced by its
		// root ship, however deep.
		TestShip *root = Ship("root");
		TestShip *middle = Ship("middle");
		TestShip *turret = Ship("turret");
		middle->_testIsSubEntity = YES;
		middle->_testOwner = root;
		turret->_testIsSubEntity = YES;
		turret->_testOwner = middle;

		TestShip *enemy = Ship("enemy");
		TestShip *enemyTurret = Ship("enemyTurret");
		enemyTurret->_testIsSubEntity = YES;
		enemyTurret->_testOwner = enemy;

		[turret setTargetForScript:enemyTurret];
		OO_CHECK(Told(root) == "add enemy");
		OO_CHECK(Told(turret).empty() && Told(middle).empty());
	}
}


OO_TEST(setTargetStopsAtSelfOwnedOrOwnerless)
{
	@autoreleasepool
	{
		// A subentity that owns itself, or has no owner, is where the climb stops.
		TestShip *loop = Ship("loop");
		loop->_testIsSubEntity = YES;
		loop->_testOwner = loop;
		TestShip *orphan = Ship("orphan");
		orphan->_testIsSubEntity = YES;
		[loop setTargetForScript:orphan];
		OO_CHECK(Told(loop) == "add orphan");
	}
}


OO_TEST(setTargetOnANonShipRootDoesNothing)
{
	@autoreleasepool
	{
		// A subentity whose owner is not a ship: nothing is told.
		Entity *notAShip = [[[Entity alloc] init] autorelease];
		TestShip *sub = Ship("sub");
		sub->_testIsSubEntity = YES;
		sub->_testOwner = notAShip;
		TestShip *target = Ship("target");
		[sub setTargetForScript:target];
		OO_CHECK(Told(sub).empty() && Told(target).empty());
	}
}


// The root category asks the entity's C++ part, so a C++ entity with no facade of its own answers
// the engine through its overrides, the defaults are the category's bodies, and an Objective-C
// class's own selectors still answer first.
namespace {

JSClassDef sTestScriptedClass = { .class_name = "TestScripted" };
JSClassID sTestScriptedClassID = 0;

class TestScriptedEntity : public cxx::Entity
{
public:
	JSClassID jsClassID() override  { return sTestScriptedClassID; }
	std::optional<std::string> jsClassName() override  { return std::string("TestScripted"); }
	bool isVisibleToScripts() override  { return true; }
};

}	// namespace


OO_TEST(cxxEntityAnswersThroughItsJSMembers)
{
	@autoreleasepool
	{
		SetUpContext();
		OOJSRegisterClass(&sTestScriptedClassID, &sTestScriptedClass);

		Entity *plain = oo::NewEntityFacade(oo::makeRef<cxx::Entity>());
		OO_CHECK(plain != nil && [plain class] == [Entity class]);
		OO_CHECK(![plain isVisibleToScripts] && !oo::ToCxx(plain)->isVisibleToScripts());
		OO_CHECK([plain cxx_oo_jsClassName] == std::optional<std::string>("Entity"));
		OO_CHECK([plain oo_jsClassID] == JSEntityClassID());

		Entity *scripted = oo::NewEntityFacade(oo::makeRef<TestScriptedEntity>());
		OO_CHECK(scripted != nil && [scripted class] == [Entity class]);
		OO_CHECK([scripted isVisibleToScripts]);
		OO_CHECK([scripted cxx_oo_jsClassName] == std::optional<std::string>("TestScripted"));
		OO_CHECK([scripted oo_jsClassID] == sTestScriptedClassID && sTestScriptedClassID != 0);

		// An Objective-C override answers first; the C++ part keeps the default.
		TestVisibleEntity *visible = [[[TestVisibleEntity alloc] init] autorelease];
		OO_CHECK([visible isVisibleToScripts] && !oo::ToCxx(visible)->isVisibleToScripts());
	}
}


OO_TEST_MAIN()
