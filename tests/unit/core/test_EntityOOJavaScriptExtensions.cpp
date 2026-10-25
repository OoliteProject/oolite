/*	test_EntityOOJavaScriptExtensions.mm
	Unit tests for the categories Entity (OOJavaScriptExtensions) and ShipEntity
	(OOJavaScriptExtensions) (src/Core/Scripting/EntityOOJavaScriptExtensions.h/.mm): bead oo-g223,
	what the script engine asks an entity by selector (is it visible to scripts, its JS class
	name, its JS class and prototype, its JS object) and what scripts ask a ship (its subentities,
	and setting its target, which climbs from a subentity to its root ship on both sides).

	The categories reach the entity's C++ part (_jsSelf), so the test links the whole game but main
	(['*']) and uses the real Entity. A ship is the test's subclass of ShipEntity made with
	class_createInstance (never initialised, never released): it answers the ShipEntity selectors
	the category sends (its subentities, its owner, being a subentity, its targets) and records
	what it was told. The JS object the entity already has is a plain object of a runtime the test
	makes. The expectations were written against the Objective-C categories and run on them
	first; they send only the categories' selectors, so the conversion (the bodies as free
	functions, the categories' forwarders in EntityOOJavaScriptExtensions+ObjCBridge.mm) changed no
	line here.
	Run: bash tools/check-core-tests.sh
*/

#include "EntityOOJavaScriptExtensions.h"
#include "ShipEntity.h"
#include "OOJSEntity.h"
#include "OOJSShip.h"

#include "oo_test.hpp"

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
	Entity						*_testPrimaryTarget = nullptr;
	std::vector<std::string>		_told;		// "add <name>" / "remove <name>"
	const char						*_name = "";

	Entity *primaryTarget() override	{ return _testPrimaryTarget; }	// the C++ entity since bead oo-9ht.39.23

	void addTarget(Entity *targetEntity) override
	{
		_told.push_back(std::string("add ") + (targetEntity != nullptr ? static_cast<TestShip *>(oo::ToShip(targetEntity))->_name : "nil"));
	}

	void removeTarget(Entity *targetEntity) override
	{
		_told.push_back(std::string("remove ") + (targetEntity != nullptr ? static_cast<TestShip *>(oo::ToShip(targetEntity))->_name : "nil"));
	}
};


// An entity that scripts can see but that keeps Entity's JS class (an Objective-C subclass until bead
// oo-j12i2; a C++ one overriding the member its selector became).
class TestVisibleEntity : public Entity
{
public:
	bool isVisibleToScripts() override  { return true; }
};


// A C++ entity made as the game makes one (its object made and autoreleased, oo::MadeEntity).
static TestVisibleEntity *NewVisibleEntity()  { return static_cast<TestVisibleEntity *>(oo::MadeEntity(oo::makeRef<TestVisibleEntity>())); }


namespace {

ooscript::Runtime sRuntime = nullptr;
ooscript::Context sContext = nullptr;


void SetUpContext()
{
	if (sContext != nullptr)  return;
	sRuntime = ooscript::newRuntime(8u * 1024u * 1024u);
	sContext = ooscript::newContext(sRuntime, 8192);
	ooscript::beginRequest(sContext);
}


// A ship made the way the test can: the C++ ship under its object (oo::NewEntityFacade, retained and
// never released), never set up from a definition, a ship (it answers -isShip, as the Objective-C
// class did, so shipSubEntities() keeps it).
TestShip *Ship(const char *name)
{
	oo::Ref<TestShip> ship = oo::makeRef<TestShip>();
	{
		oo::RetainEntity(oo::MadeEntity(ship));
	}
	ship->isShip = YES;
	ship->_name = name;
	return ship.get();
}


// A subentity's owner, and that it is one (the Objective-C ship answered -owner and -isSubEntity).
void SetSubEntityOf(TestShip *ship, Entity *owner)
{
	ship->isSubEntity = YES;
	ship->Entity::setOwner(owner);
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
	{
		Entity *entity = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK(!OOJSEntityIsVisibleToScripts(entity));
		OO_CHECK(OOJSEntityJSClassName(entity) == std::optional<std::string>("Entity"));

		ooscript::ClassDef *jsClass = nullptr;
		ooscript::Object prototype = reinterpret_cast<ooscript::Object>(1);
		OOJSEntityGetJSClass(entity, &jsClass, &prototype);
		OO_CHECK(jsClass == JSEntityClass());
		OO_CHECK(prototype == JSEntityPrototype());

		// Not visible: no JS object is made, and the value is null.
		SetUpContext();
		ooscript::Value value = OOJSEntityJSValue(entity, sContext);
		OO_CHECK(ooscript::isNull(value));
		OO_CHECK(entity->_jsSelf == nullptr);

		// With no JS object, -deleteJSSelf does nothing.
		entity->deleteJSSelf();
		OO_CHECK(entity->_jsSelf == nullptr);
	}
}


OO_TEST(existingJSObject)
{
	{
		SetUpContext();
		ooscript::Object object = ooscript::newObject(sContext, nullptr, nullptr, nullptr);
		OO_CHECK(object != nullptr);

		// An entity that already has its JS object answers it, visible or not.
		Entity *entity = oo::MadeEntity(oo::makeRef<Entity>());
		entity->_jsSelf = object;
		ooscript::Value value = OOJSEntityJSValue(entity, sContext);
		OO_CHECK(ooscript::isObject(value));
		ooscript::Object got = nullptr;
		OO_CHECK(ooscript::valueToObject(sContext, value, &got) && got == object);

		TestVisibleEntity *visible = NewVisibleEntity();
		visible->_jsSelf = object;
		got = nullptr;
		OO_CHECK(ooscript::valueToObject(sContext, OOJSEntityJSValue(visible, sContext), &got) && got == object);

		// The test's object is not rooted: the entities let go of it before they go.
		entity->_jsSelf = nullptr;
		visible->_jsSelf = nullptr;
	}
}


OO_TEST(visibleEntityKeepsEntityClass)
{
	{
		TestVisibleEntity *visible = NewVisibleEntity();
		OO_CHECK(OOJSEntityIsVisibleToScripts(visible));
		OO_CHECK(OOJSEntityJSClassName(visible) == std::optional<std::string>("Entity"));
		ooscript::ClassDef *jsClass = nullptr;
		ooscript::Object prototype = nullptr;
		OOJSEntityGetJSClass(visible, &jsClass, &prototype);
		OO_CHECK(jsClass == JSEntityClass());
	}
}


OO_TEST(shipIsVisible)
{
	{
		TestShip *ship = Ship("ship");
		OO_CHECK(OOJSEntityIsVisibleToScripts(ship));
		OO_CHECK(OOJSEntityJSClassName(ship) == std::optional<std::string>("Ship"));

		ooscript::ClassDef *jsClass = nullptr;
		ooscript::Object prototype = reinterpret_cast<ooscript::Object>(1);
		OOJSEntityGetJSClass(ship, &jsClass, &prototype);
		OO_CHECK(jsClass == JSShipClass());
		OO_CHECK(prototype == JSShipPrototype());
	}
}


OO_TEST(subEntitiesForScript)
{
	{
		TestShip *ship = Ship("ship");
		OO_CHECK(ShipEntityJSSubEntitiesForScript(ship).empty());	// -subEntitiesForScript until bead oo-9ht.144

		TestShip *turret = Ship("turret");
		TestShip *hull = Ship("hull");
		ship->subEntities = { oo::EntityHold(turret), oo::EntityHold(hull) };
		std::vector<oo::EntityHold> subs = ShipEntityJSSubEntitiesForScript(ship);
		OO_CHECK(subs.size() == 2);
		OO_CHECK(subs.size() == 2 && subs[0].get() == turret && subs[1].get() == hull);
		ship->subEntities.clear();
	}
}


OO_TEST(setTarget)
{
	{
		TestShip *ship = Ship("ship");
		TestShip *other = Ship("other");
		ShipEntityJSSetTargetForScript(ship, other);	// -setTargetForScript: until bead oo-9ht.144
		OO_CHECK(Told(ship) == "add other");
	}
}


OO_TEST(setTargetNilRemovesPrimaryTarget)
{
	{
		TestShip *ship = Ship("ship");
		TestShip *current = Ship("current");
		ship->_testPrimaryTarget = current;
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
	{
		// A subentity's target is set on its root ship, and a subentity target is replaced by its
		// root ship, however deep.
		TestShip *root = Ship("root");
		TestShip *middle = Ship("middle");
		TestShip *turret = Ship("turret");
		SetSubEntityOf(middle, root);
		SetSubEntityOf(turret, middle);

		TestShip *enemy = Ship("enemy");
		TestShip *enemyTurret = Ship("enemyTurret");
		SetSubEntityOf(enemyTurret, enemy);

		ShipEntityJSSetTargetForScript(turret, enemyTurret);	// -setTargetForScript: until bead oo-9ht.144
		OO_CHECK(Told(root) == "add enemy");
		OO_CHECK(Told(turret).empty() && Told(middle).empty());
	}
}


OO_TEST(setTargetStopsAtSelfOwnedOrOwnerless)
{
	{
		// A subentity that owns itself, or has no owner, is where the climb stops.
		TestShip *loop = Ship("loop");
		SetSubEntityOf(loop, loop);
		TestShip *orphan = Ship("orphan");
		orphan->isSubEntity = YES;
		ShipEntityJSSetTargetForScript(loop, orphan);	// -setTargetForScript: until bead oo-9ht.144
		OO_CHECK(Told(loop) == "add orphan");
	}
}


OO_TEST(setTargetOnANonShipRootDoesNothing)
{
	{
		// A subentity whose owner is not a ship: nothing is told.
		Entity *notAShip = oo::MadeEntity(oo::makeRef<Entity>());
		TestShip *sub = Ship("sub");
		SetSubEntityOf(sub, notAShip);
		TestShip *target = Ship("target");
		ShipEntityJSSetTargetForScript(sub, target);	// -setTargetForScript: until bead oo-9ht.144
		OO_CHECK(Told(sub).empty() && Told(target).empty());
	}
}


// Bead oo-9ht.107 (ADR-0056 amendment oo-9ht.107): the root category asks the entity's C++ part,
// so a C++ entity with no façade of its own answers the engine through its overrides, the defaults
// are the category's bodies, and an Objective-C class's own selectors still answer first.
namespace {

ooscript::ClassDef sTestScriptedClass = { "TestScripted", ooscript::ClassFlag::HasPrivate };

class TestScriptedEntity : public Entity
{
public:
	void getJSClass(ooscript::ClassDef **outClass, ooscript::Object *outPrototype) override
	{
		*outClass = &sTestScriptedClass;
		*outPrototype = nullptr;
	}
	std::optional<std::string> jsClassName() override  { return std::string("TestScripted"); }
	bool isVisibleToScripts() override  { return true; }
};

}	// namespace


OO_TEST(cxxEntityAnswersThroughItsJSMembers)
{
	{
		ooscript::ClassDef *jsClass = nullptr;
		ooscript::Object prototype = reinterpret_cast<ooscript::Object>(1);

		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK(plain != nil);	// (and its object's class, the root facade: retired with the facade, bead oo-dpyk8, under oo-9n5p9)
		OO_CHECK(!OOJSEntityIsVisibleToScripts(plain) && !plain->isVisibleToScripts());
		OO_CHECK(OOJSEntityJSClassName(plain) == std::optional<std::string>("Entity"));
		OOJSEntityGetJSClass(plain, &jsClass, &prototype);
		OO_CHECK(jsClass == JSEntityClass() && prototype == JSEntityPrototype());

		Entity *scripted = oo::MadeEntity(oo::makeRef<TestScriptedEntity>());
		OO_CHECK(scripted != nil);	// (and its object's class, the root facade: retired with the facade, bead oo-dpyk8, under oo-9n5p9)
		OO_CHECK(OOJSEntityIsVisibleToScripts(scripted));
		OO_CHECK(OOJSEntityJSClassName(scripted) == std::optional<std::string>("TestScripted"));
		OOJSEntityGetJSClass(scripted, &jsClass, &prototype);
		OO_CHECK(jsClass == &sTestScriptedClass && prototype == nullptr);
	}
}


// An entity's Object node (bead oo-9ht.39.5.3): it holds the object, as oo::PListObject()'s did,
// answers the C++ part, and its JS value is the part's JS object (through the object, as before).
// That the node holds the object (oo::ObjectIn()) and that a plain Object node of the object answers
// the same entity are retired with the facade (bead oo-dpyk8, under oo-9n5p9).
OO_TEST(entityObjectNodeHoldsTheEntity)
{
	{
		SetUpContext();
		ooscript::Object object = ooscript::newObject(sContext, nullptr, nullptr, nullptr);
		OO_CHECK(object != nullptr);
		Entity *entity = oo::MadeEntity(oo::makeRef<Entity>());
		Entity *part = entity;
		part->_jsSelf = object;

		const oo::PList node = oo::EntityObjectNode(part);
		OO_CHECK(node.type() == oo::PList::Type::Object);
		OO_CHECK(oo::EntityIn(node) == part);
		const oo::PList::Object *payload = node.getIf<oo::PList::Object>();
		OO_CHECK(payload != nullptr && (*payload)->className() == "Entity");
		OO_CHECK(payload != nullptr && (*payload)->description() == oo::EntityDescription(entity));
		ooscript::Object got = nullptr;
		OO_CHECK(ooscript::valueToObject(sContext, OOJSValueFromPList(sContext, node), &got) && got == object);

		// Anything else answers none.
		OO_CHECK(oo::EntityIn(oo::PList(1)) == nullptr);
		OO_CHECK(oo::EntityIn(oo::PList()) == nullptr);
		OO_CHECK(oo::EntityObjectNode(static_cast<Entity *>(nullptr)).isNull());

		// Arrays: one node per entity, in order.
		const std::vector<oo::EntityHold> refs{ oo::EntityHold(entity), oo::EntityHold(entity) };
		const std::vector<Entity *> parts = oo::EntitiesIn(oo::EntityNodesFrom(refs));
		OO_CHECK(parts.size() == 2 && parts[0] == part && parts[1] == part);

		part->_jsSelf = nullptr;	// the test's object is not rooted
	}
}


OO_TEST_MAIN()
