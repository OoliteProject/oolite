/*	test_OOShipGroup.mm
	Unit tests for OOShipGroup and OOShipGroupCursor (src/Core/OOShipGroup.h): bead oo-bwrq,
	converted in the Phase 3 house style (proposed ADR-0056).

	A group holds weak references to its ships (and to its leader), so a ship that dies leaves it.
	The group's own objects are linked; ShipEntity, which reaches the whole game, is replaced by a
	minimal weak-referenceable class of the same name that records what the group asks of it
	(amendment oo-z1s4 item 4); since bead oo-9ht.144 the ship is C++, so the stand-in is a C++
	ship under a stand-in root object, and the cases hold the ships (amendment oo-9ht.144). The expectations were written against the Objective-C API and run
	on the unconverted class first: naming, adding (no duplicates, growth past the initial
	capacity), the leader (added as a member, dropped when it dies), removing (the ship is told to
	leave), dead members leaving, the two member arrays, the cursor (and its mutation check), and
	the description text. The C++ test then pins the same through OOShipGroup. A dying group lets
	go of its weak reference to its leader as it does of its members' (bead oo-9ht.24). The
	group's facade was deleted by bead oo-9ht.19: the cases ask the C++ group, holding the
	factory's oo::Ref where the autoreleased facade was; the facade-contract case went with it
	(standing approval oo-9n5p9), and objectNode pins how a group now travels in plist data.
	Run: bash tools/check-core-tests.sh
*/

#include "OOShipGroup.h"

#include "oo_test.hpp"
#include "oofnd/objc/OOException.h"
#include "OODescription.h"

#include <algorithm>
#include <string>
#include <vector>


// The JS glue of OOShipGroup, which OOJSShipGroup.mm defines (bead oo-6symp.1) and this test
// does not link: the vtable names them. Nothing here reaches the JS engine.
ooscript::Value OOShipGroup::jsValueInContext(ooscript::Context)  { return ooscript::nullValue(); }
void OOShipGroup::clearJSSelf(ooscript::Object)  {}
std::optional<std::string> OOShipGroup::jsDescription()  { return std::nullopt; }


// --- A stand-in for ShipEntity (see the banner) ---------------------------------------------------

/*	The ship is C++ since bead oo-9ht.144 deleted the Objective-C ship: the group holds weak
	references to the ships' objects (the root's, which hold their C++ parts, oo::ToCxx reads them,
	and which oo::ToObjC answers for them) and calls the ships' members. Declared as Entity.h and
	ShipEntity.h declare them (the test imports neither); every object the test makes holds a ship
	that records what the group asks of it. The object is C++ since bead oo-4aq6a.2 (it was rooted on
	the Objective-C root class OOObject, which Phase 4 deletes), answering as it did.
*/
class TestEntityObject;

class Entity : public oo::RefCounted
{
public:
	virtual ~Entity();

	::TestEntityObject *_object = nullptr;	// its object (not retained)
};

class ShipEntity : public Entity
{
public:
	void setGroup(::OOShipGroup *group);
	void setOwner(Entity *who_owns_entity);

	::OOShipGroup *lastGroup = nullptr;
	Entity *lastOwner = nullptr;
	int setGroupCalls = 0;
};

// The group holds its ships' C++ parts weakly since bead oo-9ht.22.1.
class TestEntityObject final : public oo::RefCounted
{
public:
	// Every object the test makes holds its ship.
	TestEntityObject() : _cxxEntity(oo::makeRef<ShipEntity>())  { _cxxEntity->_object = this; }
	const char *className() const  { return "Entity"; }	// its Objective-C class's runtime name

	oo::Ref<Entity> _cxxEntity;
};

Entity::~Entity() = default;

void ShipEntity::setGroup(::OOShipGroup *group)
{
	setGroupCalls++;
	lastGroup = group;
}


void ShipEntity::setOwner(Entity *who_owns_entity)
{
	lastOwner = who_owns_entity;
}

// The test's object of an entity (oo::ToObjC() until the stand-in became C++, bead oo-4aq6a.2; the
// game's went with its facade, bead oo-dpyk8).
::TestEntityObject *TestObjectOf(Entity *entity)  { return entity != nullptr ? entity->_object : nullptr; }

#define OO_ENTITY_HELPERS_STAND_IN_CXX
#include "EntityHelpersStandIn.h"	// EntityHelpers.mm's, on the test's objects (bead oo-dpyk8)


namespace {

ShipEntity *Ship(::TestEntityObject *object)  { return static_cast<ShipEntity *>(object->_cxxEntity.get()); }


// A ship, its object autoreleased (as [[[ShipEntity alloc] init] autorelease] was).
ShipEntity *NewShip()
{
	return Ship(oo::autorelease(oo::makeRef<::TestEntityObject>()));
}


bool HasMembers(const std::vector<oo::EntityHold> &members, std::vector<ShipEntity *> expected)
{
	std::vector<ShipEntity *> got;
	for (const oo::EntityHold &object : members)  got.push_back(Ship(TestObjectOf(object.get())));
	std::sort(got.begin(), got.end());
	std::sort(expected.begin(), expected.end());
	return got == expected;
}

}	// namespace


OO_TEST(namesAndEmptyGroups)
{
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> unnamed = OOShipGroup::groupWithName(std::nullopt);	// -init
		OO_CHECK(unnamed != nil && !unnamed->name().has_value());
		OO_CHECK(unnamed->count() == 0 && unnamed->isEmpty() && unnamed->leader() == nil);
		OO_CHECK(unnamed->memberArray().empty() && unnamed->memberArrayExcludingLeader().empty());

		oo::Ref<OOShipGroup> named = OOShipGroup::groupWithName(std::string("escort group"));
		OO_CHECK(named->name() == std::optional<std::string>("escort group"));
		named->setName(std::string("renamed"));
		OO_CHECK(named->name() == std::optional<std::string>("renamed"));
		named->setName(std::nullopt);
		OO_CHECK(!named->name().has_value());

		oo::Ref<OOShipGroup> made = OOShipGroup::groupWithName(std::string("ship group"));	// -cxx_initWithName:
		OO_CHECK(made->name() == std::optional<std::string>("ship group") && made->isEmpty());
	}
}


OO_TEST(addingAndGrowing)
{
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::nullopt);
		std::vector<ShipEntity *> ships;
		for (int i = 0; i < 20; i++)  ships.push_back(NewShip());	// past kMinSize (4): the array grows

		for (ShipEntity *ship : ships)  OO_CHECK(group->addShip(ship));
		OO_CHECK(group->count() == 20 && !group->isEmpty());
		OO_CHECK(group->addShip(ships[3]));	// already in: YES, and not added twice
		OO_CHECK(group->count() == 20);
		OO_CHECK(group->containsShip(ships[19]) && !group->containsShip(NewShip()));
		OO_CHECK(HasMembers(group->memberArray(), ships));
		OO_CHECK(HasMembers(group->memberArrayExcludingLeader(), ships));	// no leader
	}
}


OO_TEST(leader)
{
	{
		oo::AutoreleaseScope pool;
		ShipEntity *leader = NewShip();
		ShipEntity *wingman = NewShip();
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("g"), leader);
		OO_CHECK(group->leader() == leader && group->containsShip(leader) && group->count() == 1);
		group->addShip(wingman);
		OO_CHECK(HasMembers(group->memberArrayExcludingLeader(), { wingman }));
		OO_CHECK(HasMembers(group->memberArray(), { leader, wingman }));

		group->setLeader(wingman);
		OO_CHECK(group->leader() == wingman && group->count() == 2);
		group->setLeader(nullptr);
		OO_CHECK(group->leader() == nil && group->count() == 2);	// still members
	}
}


OO_TEST(removing)
{
	{
		oo::AutoreleaseScope pool;
		ShipEntity *a = NewShip(), *b = NewShip(), *c = NewShip();
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::nullopt, a);
		group->addShip(b);
		group->addShip(c);

		OO_CHECK(group->removeShip(b));
		OO_CHECK(!group->containsShip(b) && group->count() == 2);
		OO_CHECK(b->setGroupCalls == 1 && b->lastGroup == nil && b->lastOwner == b);	// told to leave
		OO_CHECK(!group->removeShip(b));	// not a member

		OO_CHECK(group->removeShip(a));	// the leader: no longer leads
		OO_CHECK(group->leader() == nil && group->count() == 1 && group->containsShip(c));
	}
}


OO_TEST(deadShipsLeave)
{
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::nullopt);
		ShipEntity *survivor = NewShip();
		::TestEntityObject *doomedObject = oo::makeRef<::TestEntityObject>().leakRef();
		::TestEntityObject *doomedLeaderObject = oo::makeRef<::TestEntityObject>().leakRef();
		ShipEntity *doomed = Ship(doomedObject);
		ShipEntity *doomedLeader = Ship(doomedLeaderObject);
		group->addShip(survivor);
		group->addShip(doomed);
		group->setLeader(doomedLeader);
		OO_CHECK(group->count() == 3);

		doomedObject->release();
		doomedLeaderObject->release();
		OO_CHECK(group->leader() == nil);
		OO_CHECK(group->count() == 1 && !group->isEmpty());
		OO_CHECK(HasMembers(group->memberArray(), { survivor }));
	}
}


OO_TEST(cursor)
{
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::nullopt);
		std::vector<ShipEntity *> ships = { NewShip(), NewShip(), NewShip() };
		for (ShipEntity *ship : ships)  group->addShip(ship);

		std::vector<ShipEntity *> seen;
		OOShipGroupCursor cursor(group.get());
		while (ShipEntity *ship = cursor.next())  seen.push_back(ship);
		OO_CHECK(seen == ships);	// internal order: the order added
		OO_CHECK(cursor.index() == 3);

		OOShipGroupCursor mutated(group.get());
		OO_CHECK(mutated.next() == ships[0]);
		group->addShip(NewShip());
		bool raised = false;
		try
		{
			mutated.next();
		}
		catch (const oo::Exception &)	// was @catch (OOException *exception) (bead oo-rskgl.1)
		{
			raised = true;
		}
		OO_CHECK(raised);
	}
}


OO_TEST(description)
{
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("pirates"));
		group->addShip(NewShip());
		OO_CHECK(group->descriptionComponents() == std::optional<std::string>("\"pirates\", 1 ships"));
		ShipEntity *leader = NewShip();
		group->setLeader(leader);
		std::optional<std::string> text = group->descriptionComponents();
		OO_CHECK(text.has_value() && *text == "\"pirates\", 2 ships, leader: " + TestEntityObjectDescription(TestObjectOf(leader)));
		OO_CHECK(OOShipGroup::groupWithName(std::nullopt)->descriptionComponents() == std::optional<std::string>("0 ships"));
	}
}


OO_TEST(cxxGroup)
{
	{
		oo::AutoreleaseScope pool;
		ShipEntity *leader = NewShip(), *wingman = NewShip();
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("g"), leader);
		OO_CHECK(group != nullptr && group->name() == std::optional<std::string>("g"));
		OO_CHECK(group->leader() == leader && group->count() == 1);
		OO_CHECK(group->addShip(wingman) && group->addShip(wingman) && group->count() == 2);
		OO_CHECK(HasMembers(group->memberArray(), { leader, wingman }));
		OO_CHECK(HasMembers(group->memberArrayExcludingLeader(), { wingman }));
		OO_CHECK(group->descriptionComponents() == std::optional<std::string>("\"g\", 2 ships, leader: " + TestEntityObjectDescription(TestObjectOf(leader))));

		std::vector<ShipEntity *> seen;
		OOShipGroupCursor cursor(group.get());
		while (ShipEntity *ship = cursor.next())  seen.push_back(ship);
		OO_CHECK(seen == std::vector<ShipEntity *>({ leader, wingman }));

		OO_CHECK(group->removeShip(leader) && group->leader() == nullptr && wingman->setGroupCalls == 0);
		OO_CHECK(leader->setGroupCalls == 1 && leader->lastOwner == leader);
		group->setName(std::nullopt);
		OO_CHECK(!group->name().has_value() && !group->isEmpty());
	}
}


OO_TEST(objectNode)
{
	// A group is its own PList Object node payload (bead oo-9ht.19), as its facade was the node's
	// object: the node gives the same group back, and describes it as "%@" printed the facade.
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("node"));
		const oo::PList node = OOShipGroupObjectNode(group.get());
		OO_CHECK(OOShipGroupInObjectNode(node) == group.get());
		OO_CHECK(OOShipGroupObjectNode(nullptr).isNull() && OOShipGroupInObjectNode(oo::PList("node")) == nullptr);
		OO_CHECK(group->className() == "OOShipGroup");
		const std::string text = group->description();
		OO_CHECK(text.rfind("<OOShipGroup 0x", 0) == 0 && text.find(">{\"node\", 0 ships}") != std::string::npos);
		OO_CHECK(OOShipGroup::groupWithName(std::nullopt) != OOShipGroup::groupWithName(std::nullopt));	// distinct groups, as before
	}
}


OO_TEST(dyingGroupReleasesLeaderReference)
{
	// The group weak-retains its leader (setLeader) as it does each member (addShip); its
	// destructor must balance both, or every group that dies with a leader leaks one
	// weak-reference proxy (bead oo-9ht.24). Since bead oo-9ht.22.1 the references are oo::WeakRef
	// members, released with the group; the checks of the objects' weak-reference proxy (weakSelf)
	// retired with it (ADR-0049, standing approval oo-9n5p9).
	::TestEntityObject *leaderObject = oo::makeRef<::TestEntityObject>().leakRef();
	::TestEntityObject *memberObject = oo::makeRef<::TestEntityObject>().leakRef();
	ShipEntity *leader = Ship(leaderObject), *member = Ship(memberObject);
	{
		oo::AutoreleaseScope pool;
		oo::Ref<OOShipGroup> group = OOShipGroup::groupWithName(std::string("doomed"));
		group->addShip(member);
		group->setLeader(leader);
		OO_CHECK(group->leader() == leader && group->count() == 2);
	}
	leaderObject->release();
	memberObject->release();
}


OO_TEST_MAIN()
