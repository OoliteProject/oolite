/*	test_OOShipGroup.mm
	Unit tests for OOShipGroup and OOShipGroupCursor (src/Core/OOShipGroup.h): bead oo-bwrq,
	converted in the Phase 3 house style (proposed ADR-0056).

	A group holds weak references to its ships (and to its leader), so a ship that dies leaves it.
	The group's own objects are linked; ShipEntity, which reaches the whole game, is replaced by a
	minimal weak-referenceable class of the same name that records what the group asks of it
	(amendment oo-z1s4 item 4). The expectations were written against the Objective-C API and run
	on the unconverted class first: naming, adding (no duplicates, growth past the initial
	capacity), the leader (added as a member, dropped when it dies), removing (the ship is told to
	leave), dead members leaving, the two member arrays, the cursor (and its mutation check), and
	the description text. The C++ test then pins the same through cxx::OOShipGroup, and the last
	test the facade's contract (alloc/init from Objective-C, one facade per group, nil stays nil,
	the cursor's transitional constructor). A dying group lets go of its weak reference to its
	leader as it does of its members' (bead oo-9ht.24).
	Run: bash tools/check-core-tests.sh
*/

#import "OOShipGroup.h"
#import "OOWeakReference.h"

#include "oo_test.hpp"
#include "oofnd/objc/OOException.h"
#include "OODescription.h"

#include <algorithm>
#include <string>
#include <vector>


// --- A stand-in for ShipEntity (see the banner) ---------------------------------------------------

@interface ShipEntity: OOWeakRefObject
{
@public
	id		lastGroup;
	id		lastOwner;
	int		setGroupCalls;
}
- (void) setGroup:(id)group;
- (void) setOwner:(id)owner;
@end

@implementation ShipEntity

- (void) setGroup:(id)group
{
	setGroupCalls++;
	lastGroup = group;
}


- (void) setOwner:(id)owner
{
	lastOwner = owner;
}

@end


// A ship that says whether a weak reference to it is still alive: OOWeakRefObject keeps one
// (weakSelf) while any -weakRetain is unbalanced, and clears it when the reference deallocates.
@interface WatchedShip: ShipEntity
- (BOOL) hasLiveWeakReference;
@end

@implementation WatchedShip
- (BOOL) hasLiveWeakReference  { return weakSelf != nil; }
@end


namespace {

ShipEntity *NewShip()
{
	return [[[ShipEntity alloc] init] autorelease];
}


bool HasMembers(const std::vector<oo::ObjCRef<ShipEntity *>> &members, std::vector<ShipEntity *> expected)
{
	std::vector<ShipEntity *> got;
	for (const oo::ObjCRef<ShipEntity *> &ship : members)  got.push_back(ship.get());
	std::sort(got.begin(), got.end());
	std::sort(expected.begin(), expected.end());
	return got == expected;
}

}	// namespace


OO_TEST(namesAndEmptyGroups)
{
	@autoreleasepool
	{
		OOShipGroup *unnamed = [[[OOShipGroup alloc] init] autorelease];
		OO_CHECK(unnamed != nil && ![unnamed cxx_name].has_value());
		OO_CHECK([unnamed count] == 0 && [unnamed isEmpty] && [unnamed leader] == nil);
		OO_CHECK([unnamed cxx_memberArray].empty() && [unnamed cxx_memberArrayExcludingLeader].empty());

		OOShipGroup *named = [OOShipGroup cxx_groupWithName:std::string("escort group")];
		OO_CHECK([named cxx_name] == std::optional<std::string>("escort group"));
		[named cxx_setName:std::string("renamed")];
		OO_CHECK([named cxx_name] == std::optional<std::string>("renamed"));
		[named cxx_setName:std::nullopt];
		OO_CHECK(![named cxx_name].has_value());

		OOShipGroup *made = [[[OOShipGroup alloc] cxx_initWithName:std::string("ship group")] autorelease];
		OO_CHECK([made cxx_name] == std::optional<std::string>("ship group") && [made isEmpty]);
	}
}


OO_TEST(addingAndGrowing)
{
	@autoreleasepool
	{
		OOShipGroup *group = [OOShipGroup cxx_groupWithName:std::nullopt];
		std::vector<ShipEntity *> ships;
		for (int i = 0; i < 20; i++)  ships.push_back(NewShip());	// past kMinSize (4): the array grows

		for (ShipEntity *ship : ships)  OO_CHECK([group addShip:ship]);
		OO_CHECK([group count] == 20 && ![group isEmpty]);
		OO_CHECK([group addShip:ships[3]]);	// already in: YES, and not added twice
		OO_CHECK([group count] == 20);
		OO_CHECK([group containsShip:ships[19]] && ![group containsShip:NewShip()]);
		OO_CHECK(HasMembers([group cxx_memberArray], ships));
		OO_CHECK(HasMembers([group cxx_memberArrayExcludingLeader], ships));	// no leader
	}
}


OO_TEST(leader)
{
	@autoreleasepool
	{
		ShipEntity *leader = NewShip();
		ShipEntity *wingman = NewShip();
		OOShipGroup *group = [OOShipGroup cxx_groupWithName:std::string("g") leader:leader];
		OO_CHECK([group leader] == leader && [group containsShip:leader] && [group count] == 1);
		[group addShip:wingman];
		OO_CHECK(HasMembers([group cxx_memberArrayExcludingLeader], { wingman }));
		OO_CHECK(HasMembers([group cxx_memberArray], { leader, wingman }));

		[group setLeader:wingman];
		OO_CHECK([group leader] == wingman && [group count] == 2);
		[group setLeader:nil];
		OO_CHECK([group leader] == nil && [group count] == 2);	// still members
	}
}


OO_TEST(removing)
{
	@autoreleasepool
	{
		ShipEntity *a = NewShip(), *b = NewShip(), *c = NewShip();
		OOShipGroup *group = [OOShipGroup cxx_groupWithName:std::nullopt leader:a];
		[group addShip:b];
		[group addShip:c];

		OO_CHECK([group removeShip:b]);
		OO_CHECK(![group containsShip:b] && [group count] == 2);
		OO_CHECK(b->setGroupCalls == 1 && b->lastGroup == nil && b->lastOwner == b);	// told to leave
		OO_CHECK(![group removeShip:b]);	// not a member

		OO_CHECK([group removeShip:a]);	// the leader: no longer leads
		OO_CHECK([group leader] == nil && [group count] == 1 && [group containsShip:c]);
	}
}


OO_TEST(deadShipsLeave)
{
	@autoreleasepool
	{
		OOShipGroup *group = [OOShipGroup cxx_groupWithName:std::nullopt];
		ShipEntity *survivor = NewShip();
		ShipEntity *doomed = [[ShipEntity alloc] init];
		ShipEntity *doomedLeader = [[ShipEntity alloc] init];
		[group addShip:survivor];
		[group addShip:doomed];
		[group setLeader:doomedLeader];
		OO_CHECK([group count] == 3);

		[doomed release];
		[doomedLeader release];
		OO_CHECK([group leader] == nil);
		OO_CHECK([group count] == 1 && ![group isEmpty]);
		OO_CHECK(HasMembers([group cxx_memberArray], { survivor }));
	}
}


OO_TEST(cursor)
{
	@autoreleasepool
	{
		OOShipGroup *group = [OOShipGroup cxx_groupWithName:std::nullopt];
		std::vector<ShipEntity *> ships = { NewShip(), NewShip(), NewShip() };
		for (ShipEntity *ship : ships)  [group addShip:ship];

		std::vector<ShipEntity *> seen;
		OOShipGroupCursor cursor(group);
		while (ShipEntity *ship = cursor.next())  seen.push_back(ship);
		OO_CHECK(seen == ships);	// internal order: the order added
		OO_CHECK(cursor.index() == 3);

		OOShipGroupCursor mutated(group);
		OO_CHECK(mutated.next() == ships[0]);
		[group addShip:NewShip()];
		bool raised = false;
		@try
		{
			mutated.next();
		}
		@catch (OOException *exception)
		{
			raised = true;
		}
		OO_CHECK(raised);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		OOShipGroup *group = [OOShipGroup cxx_groupWithName:std::string("pirates")];
		[group addShip:NewShip()];
		OO_CHECK([group cxx_descriptionComponents] == std::optional<std::string>("\"pirates\", 1 ships"));
		ShipEntity *leader = NewShip();
		[group setLeader:leader];
		std::optional<std::string> text = [group cxx_descriptionComponents];
		OO_CHECK(text.has_value() && *text == "\"pirates\", 2 ships, leader: " + oo::ShortDescriptionOf(leader));
		OO_CHECK([[OOShipGroup cxx_groupWithName:std::nullopt] cxx_descriptionComponents] == std::optional<std::string>("0 ships"));
	}
}


OO_TEST(cxxGroup)
{
	@autoreleasepool
	{
		ShipEntity *leader = NewShip(), *wingman = NewShip();
		oo::Ref<cxx::OOShipGroup> group = cxx::OOShipGroup::groupWithName(std::string("g"), leader);
		OO_CHECK(group != nullptr && group->name() == std::optional<std::string>("g"));
		OO_CHECK(group->leader() == leader && group->count() == 1);
		OO_CHECK(group->addShip(wingman) && group->addShip(wingman) && group->count() == 2);
		OO_CHECK(HasMembers(group->memberArray(), { leader, wingman }));
		OO_CHECK(HasMembers(group->memberArrayExcludingLeader(), { wingman }));
		OO_CHECK(group->descriptionComponents() == std::optional<std::string>("\"g\", 2 ships, leader: " + oo::ShortDescriptionOf(leader)));

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


OO_TEST(facadeContract)
{
	OO_CHECK(oo::ToCxx(static_cast<OOShipGroup *>(nil)) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOShipGroup *>(nullptr)) == nil);
	@autoreleasepool
	{
		// alloc/init from Objective-C: the facade is its C++ group's one peer.
		OOShipGroup *made = [[[OOShipGroup alloc] cxx_initWithName:std::string("made")] autorelease];
		cxx::OOShipGroup *group = oo::ToCxx(made);
		OO_CHECK(group != nullptr && oo::ToObjC(group) == made);
		ShipEntity *ship = NewShip();
		[made addShip:ship];
		OO_CHECK(group->containsShip(ship));	// one object on both sides
		OOShipGroupCursor fromFacade(made);	// the transitional constructor
		OO_CHECK(fromFacade.next() == ship && fromFacade._group.get() == group);

		// A C++ group crossing: one facade, kept while it lives.
		oo::Ref<cxx::OOShipGroup> cxxGroup = cxx::OOShipGroup::groupWithName(std::nullopt);
		OOShipGroup *facade = oo::ToObjC(cxxGroup);
		OO_CHECK([facade isKindOfClass:[OOShipGroup class]] && [facade isKindOfClass:[OOWeakRefObject class]]);
		OO_CHECK(oo::ToObjC(cxxGroup) == facade && oo::ToCxx(facade) == cxxGroup.get());
		OO_CHECK([OOShipGroup cxx_groupWithName:std::nullopt] != [OOShipGroup cxx_groupWithName:std::nullopt]);	// distinct groups, as before
	}
}


OO_TEST(dyingGroupReleasesLeaderReference)
{
	// The group weak-retains its leader (setLeader) as it does each member (addShip); its
	// destructor must balance both, or every group that dies with a leader leaks one
	// OOWeakReference (bead oo-9ht.24).
	WatchedShip *leader = [[WatchedShip alloc] init];
	WatchedShip *member = [[WatchedShip alloc] init];
	@autoreleasepool
	{
		oo::Ref<cxx::OOShipGroup> group = cxx::OOShipGroup::groupWithName(std::string("doomed"));
		group->addShip(member);
		group->setLeader(leader);
		OO_CHECK(group->leader() == leader && group->count() == 2);
		OO_CHECK([leader hasLiveWeakReference] && [member hasLiveWeakReference]);
	}
	OO_CHECK(![member hasLiveWeakReference]);
	OO_CHECK(![leader hasLiveWeakReference]);

	// The same through the facade, the way Objective-C callers make and drop groups.
	@autoreleasepool
	{
		OOShipGroup *group = [[OOShipGroup alloc] cxx_initWithName:std::string("doomed too")];
		[group setLeader:leader];
		OO_CHECK([group leader] == leader && [leader hasLiveWeakReference]);
		[group release];
	}
	OO_CHECK(![leader hasLiveWeakReference]);
	[leader release];
	[member release];
}


OO_TEST_MAIN()
