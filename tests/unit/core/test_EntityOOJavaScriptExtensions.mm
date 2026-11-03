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


// A ship that answers what the functions ask a ship, and records the targets it was told. A C++
// subclass since bead oo-9ht.144 deleted the Objective-C ship this subclassed: its subentities, owner
// and being a subentity are the ship's own state, set by the test; its primary target and the
// targets it is told are its overrides (removeTarget() is virtual for it, a test seam: amendment
// oo-9ht.107 item 6).
class TestShip : public ShipEntity
{
public:
	id								_testPrimaryTarget = nil;
	std::vector<std::string>		_told;		// "add <name>" / "remove <name>"
	const char						*_name = "";

	id primaryTarget() override	{ return _testPrimaryTarget; }

	void addTarget(::Entity *targetEntity) override
	{
		_told.push_back(std::string("add ") + (targetEntity != nil ? static_cast<TestShip *>(oo::ToShip(targetEntity))->_name : "nil"));
	}

	void removeTarget(::Entity *targetEntity) override
	{
		_told.push_back(std::string("remove ") + (targetEntity != nil ? static_cast<TestShip *>(oo::ToShip(targetEntity))->_name : "nil"));
	}
};


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


// A ship made the way the test can: the C++ ship under its object (oo::NewEntityFacade, retained and
// never released), never set up from a definition, a ship (it answers -isShip, as the Objective-C
// class did, so shipSubEntities() keeps it).
TestShip *Ship(const char *name)
{
	oo::Ref<TestShip> ship = oo::makeRef<TestShip>();
	@autoreleasepool
	{
		[oo::NewEntityFacade(ship) retain];
	}
	ship->isShip = YES;
	ship->_name = name;
	return ship.get();
}


// A subentity's owner, and that it is one (the Objective-C ship answered -owner and -isSubEntity).
void SetSubEntityOf(TestShip *ship, Entity *owner)
{
	ship->isSubEntity = YES;
	ship->cxx::Entity::setOwner(oo::ToCxx(owner));
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
		OO_CHECK([oo::ToObjC(ship) isVisibleToScripts]);
		OO_CHECK([oo::ToObjC(ship) cxx_oo_jsClassName] == std::optional<std::string>("Ship"));

		SetUpContext();
		OO_CHECK([oo::ToObjC(ship) oo_jsClassID] == JSShipClassID());
	}
}


OO_TEST(subEntitiesForScript)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		OO_CHECK(ShipEntityJSSubEntitiesForScript(ship).empty());	// -subEntitiesForScript until bead oo-9ht.144

		TestShip *turret = Ship("turret");
		TestShip *hull = Ship("hull");
		ship->subEntities = { oo::ObjCRef<::Entity *>(oo::ToObjC(turret)), oo::ObjCRef<::Entity *>(oo::ToObjC(hull)) };
		std::vector<oo::ObjCRef<Entity *>> subs = ShipEntityJSSubEntitiesForScript(ship);
		OO_CHECK(subs.size() == 2);
		OO_CHECK(subs.size() == 2 && subs[0].get() == oo::ToObjC(turret) && subs[1].get() == oo::ToObjC(hull));
		ship->subEntities.clear();
	}
}


OO_TEST(setTarget)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		TestShip *other = Ship("other");
		ShipEntityJSSetTargetForScript(ship, other);	// -setTargetForScript: until bead oo-9ht.144
		OO_CHECK(Told(ship) == "add other");
	}
}


OO_TEST(setTargetNilRemovesPrimaryTarget)
{
	@autoreleasepool
	{
		TestShip *ship = Ship("ship");
		TestShip *current = Ship("current");
		ship->_testPrimaryTarget = oo::ToObjC(current);
		ShipEntityJSSetTargetForScript(ship, nullptr);	// -setTargetForScript: until bead oo-9ht.144
		OO_CHECK(Told(ship) == "remove current");

		// No primary target: remove nil.
		TestShip *idle = Ship("idle");
		ShipEntityJSSetTargetForScript(idle, nullptr);	// -setTargetForScript: until bead oo-9ht.144
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
		SetSubEntityOf(middle, oo::ToObjC(root));
		SetSubEntityOf(turret, oo::ToObjC(middle));

		TestShip *enemy = Ship("enemy");
		TestShip *enemyTurret = Ship("enemyTurret");
		SetSubEntityOf(enemyTurret, oo::ToObjC(enemy));

		ShipEntityJSSetTargetForScript(turret, enemyTurret);	// -setTargetForScript: until bead oo-9ht.144
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
		SetSubEntityOf(loop, oo::ToObjC(loop));
		TestShip *orphan = Ship("orphan");
		orphan->isSubEntity = YES;
		ShipEntityJSSetTargetForScript(loop, orphan);	// -setTargetForScript: until bead oo-9ht.144
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
		SetSubEntityOf(sub, notAShip);
		TestShip *target = Ship("target");
		ShipEntityJSSetTargetForScript(sub, target);	// -setTargetForScript: until bead oo-9ht.144
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
