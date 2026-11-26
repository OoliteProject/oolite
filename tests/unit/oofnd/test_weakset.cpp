/*	test_weakset.cpp
	Unit tests for oofnd/WeakSet.hpp (bead oo-qpa): oo::WeakSet<T>, the replacement for OOWeakSet,
	checked against the semantics OOWeakSet.h documents (members leave silently when they die,
	identity not equality, adding nil is a no-op, removing a non-member is fine, copies hold the
	live members) plus insertion-order iteration and mutation-safe forEach().
*/

#include "oofnd/WeakSet.hpp"

#include "oo_test.hpp"

#include <string>
#include <vector>

namespace {

int gLive = 0;

class Ship : public oo::RefCounted
{
public:
	explicit Ship(std::string name) : name(std::move(name)) { ++gLive; }
	~Ship() override { --gLive; }

	// Value-equal ships are still different members: WeakSet uniques by identity.
	bool operator==(const Ship& other) const { return name == other.name; }

	std::string name;
	int pinged = 0;
};

class Cruiser : public Ship
{
public:
	using Ship::Ship;
};

std::vector<std::string> names(const oo::WeakSet<Ship>& set)
{
	std::vector<std::string> out;
	for (const oo::Ref<Ship>& s : set.allObjects())  out.push_back(s->name);
	return out;
}

OO_TEST(addContainsCount)
{
	oo::WeakSet<Ship> set;
	OO_CHECK(set.empty());
	oo::Ref<Ship> a = oo::makeRef<Ship>("a");
	oo::Ref<Ship> b = oo::makeRef<Ship>("b");
	set.add(a.get());
	set.add(b);
	OO_CHECK_EQ(set.count(), 2u);
	OO_CHECK(set.contains(a.get()));
	OO_CHECK(set.contains(b.get()));
	OO_CHECK_EQ(a->retainCount(), 1u);          // membership does not retain

	set.add(a.get());                           // a set: adding twice is one member
	OO_CHECK_EQ(set.count(), 2u);

	oo::Ref<Ship> twin = oo::makeRef<Ship>("a");
	OO_CHECK(*twin == *a);
	OO_CHECK(!set.contains(twin.get()));        // equal value, different identity
	set.add(twin.get());
	OO_CHECK_EQ(set.count(), 3u);
}

OO_TEST(addingNullIsIgnored)
{
	oo::WeakSet<Ship> set;
	set.add(static_cast<Ship*>(nullptr));
	set.add(oo::Ref<Ship>());
	OO_CHECK_EQ(set.count(), 0u);
	OO_CHECK(!set.contains(nullptr));
	set.remove(nullptr);                        // and so is removing it
}

OO_TEST(membersLeaveSilentlyWhenTheyDie)
{
	oo::WeakSet<Ship> set;
	oo::Ref<Ship> keep = oo::makeRef<Ship>("keep");
	set.add(keep.get());
	{
		oo::Ref<Ship> brief = oo::makeRef<Ship>("brief");
		set.add(brief.get());
		OO_CHECK_EQ(set.count(), 2u);
	}
	OO_CHECK_EQ(set.count(), 1u);               // no notification; the count just drops
	OO_CHECK(names(set) == std::vector<std::string>{"keep"});
	keep.reset();
	OO_CHECK_EQ(set.count(), 0u);
	OO_CHECK(set.empty());
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(aNewObjectAtADeadMembersAddressIsNotAMember)
{
	oo::WeakSet<Ship> set;
	{
		oo::Ref<Ship> dead = oo::makeRef<Ship>("dead");
		set.add(dead.get());
	}
	for (int i = 0; i < 16; ++i)
	{
		oo::Ref<Ship> fresh = oo::makeRef<Ship>("dead");   // same size: the allocator may reuse it
		OO_CHECK(!set.contains(fresh.get()));
	}
	OO_CHECK_EQ(set.count(), 0u);
}

OO_TEST(removeMembersAndNonMembers)
{
	oo::WeakSet<Ship> set;
	oo::Ref<Ship> a = oo::makeRef<Ship>("a");
	oo::Ref<Ship> b = oo::makeRef<Ship>("b");
	oo::Ref<Ship> outsider = oo::makeRef<Ship>("outsider");
	set.add(a.get());
	set.add(b.get());
	set.remove(outsider.get());                 // not a member: no complaint, no change
	OO_CHECK_EQ(set.count(), 2u);
	OO_CHECK(oo::detail::WeakAccess::existingControl(outsider.get()) == nullptr);   // and no side effect
	set.remove(a.get());
	OO_CHECK(!set.contains(a.get()));
	OO_CHECK_EQ(set.count(), 1u);
	set.remove(a.get());
	OO_CHECK_EQ(set.count(), 1u);
	set.add(a.get());                           // re-adding goes to the end
	OO_CHECK(names(set) == (std::vector<std::string>{"b", "a"}));
	set.removeAll();
	OO_CHECK(set.empty());
	OO_CHECK_EQ(a->retainCount(), 1u);
}

OO_TEST(allObjectsIsLiveRetainedAndInInsertionOrder)
{
	oo::WeakSet<Ship> set;
	std::vector<oo::Ref<Ship>> ships;
	for (const char* n : {"c", "a", "d", "b"})
	{
		ships.push_back(oo::makeRef<Ship>(n));
		set.add(ships.back().get());
	}
	OO_CHECK(names(set) == (std::vector<std::string>{"c", "a", "d", "b"}));
	ships[2].reset();                           // "d" dies
	std::vector<oo::Ref<Ship>> all = set.allObjects();
	OO_CHECK_EQ(all.size(), 3u);
	OO_CHECK_EQ(all[0]->retainCount(), 2u);     // the snapshot retains, as NSArray did
	OO_CHECK(names(set) == (std::vector<std::string>{"c", "a", "b"}));
}

OO_TEST(forEachIsMakeObjectsPerformSelector)
{
	oo::WeakSet<Ship> set;
	oo::Ref<Ship> a = oo::makeRef<Ship>("a");
	oo::Ref<Ship> b = oo::makeRef<Ship>("b");
	set.add(a.get());
	set.add(b.get());
	set.forEach([](Ship& s) { ++s.pinged; });
	OO_CHECK_EQ(a->pinged, 1);
	OO_CHECK_EQ(b->pinged, 1);
}

OO_TEST(forEachSurvivesMutationAndDeathInTheCallback)
{
	oo::WeakSet<Ship> set;
	std::vector<oo::Ref<Ship>> owners;
	for (int i = 0; i < 4; ++i)
	{
		owners.push_back(oo::makeRef<Ship>("s" + std::to_string(i)));
		set.add(owners.back().get());
	}
	oo::Ref<Ship> late = oo::makeRef<Ship>("late");
	int visited = 0;
	set.forEach([&](Ship& s) {
		++visited;
		if (s.name == "s0")
		{
			owners.clear();                     // every member loses its last external owner...
			set.remove(&s);                     // ...the set is mutated...
			set.add(late.get());                // ...and grows, mid-iteration
		}
		OO_CHECK(!s.name.empty());              // ...yet each visited object is still alive (ASan)
	});
	OO_CHECK_EQ(visited, 4);                    // the snapshot taken at the start
	OO_CHECK(names(set) == std::vector<std::string>{"late"});
	OO_CHECK_EQ(gLive, 1);
}

OO_TEST(copiesHoldTheLiveMembers)
{
	oo::WeakSet<Ship> set(8);
	oo::Ref<Ship> a = oo::makeRef<Ship>("a");
	set.add(a.get());
	{
		oo::Ref<Ship> gone = oo::makeRef<Ship>("gone");
		set.add(gone.get());
	}
	oo::WeakSet<Ship> copy = set;               // -copyWithZone: compacts first
	OO_CHECK_EQ(copy.count(), 1u);
	OO_CHECK(copy.contains(a.get()));
	oo::Ref<Ship> b = oo::makeRef<Ship>("b");
	copy.add(b.get());
	OO_CHECK(!set.contains(b.get()));           // independent sets

	oo::WeakSet<Ship> assigned;
	assigned = copy;
	OO_CHECK_EQ(assigned.count(), 2u);
	oo::WeakSet<Ship>& self = assigned;
	assigned = self;
	OO_CHECK_EQ(assigned.count(), 2u);

	oo::WeakSet<Ship> moved = std::move(assigned);
	OO_CHECK_EQ(moved.count(), 2u);
	b.reset();
	OO_CHECK_EQ(moved.count(), 1u);
	OO_CHECK_EQ(copy.count(), 1u);
}

OO_TEST(equalityIsSameLiveMembers)
{
	oo::Ref<Ship> a = oo::makeRef<Ship>("a");
	oo::Ref<Ship> b = oo::makeRef<Ship>("b");
	oo::WeakSet<Ship> x, y;
	x.add(a.get());
	x.add(b.get());
	y.add(b.get());
	y.add(a.get());
	OO_CHECK(x == y);                           // order does not matter for equality
	{
		oo::Ref<Ship> c = oo::makeRef<Ship>("c");
		x.add(c.get());
		OO_CHECK(x != y);
	}
	OO_CHECK(x == y);                           // c died: the sets are equal again
	oo::Ref<Ship> twin = oo::makeRef<Ship>("a");
	oo::WeakSet<Ship> z;
	z.add(twin.get());
	z.add(b.get());
	OO_CHECK(x != z);                           // identity, not isEqual:
}

OO_TEST(addAllFromARange)
{
	std::vector<oo::Ref<Ship>> refs{oo::makeRef<Ship>("r1"), oo::makeRef<Ship>("r2")};
	std::vector<Ship*> raws{refs[0].get(), nullptr, refs[1].get()};
	oo::WeakSet<Ship> set;
	set.addAll(refs);
	set.addAll(raws);                           // duplicates and nulls are ignored
	OO_CHECK_EQ(set.count(), 2u);

	oo::WeakSet<Ship> other;
	other.addAll(set.allObjects());             // -addObjectsByEnumerating:
	OO_CHECK(other == set);
}

OO_TEST(subclassMembers)
{
	oo::WeakSet<Ship> set;
	oo::Ref<Cruiser> c = oo::makeRef<Cruiser>("cruiser");
	set.add(c.get());
	OO_CHECK(set.contains(c.get()));
	std::vector<oo::Ref<Cruiser>> cruisers{c};
	set.addAll(cruisers);
	OO_CHECK_EQ(set.count(), 1u);
	c.reset();
	cruisers.clear();
	OO_CHECK(set.empty());
}

OO_TEST(aMemberCanOwnTheSetThatWatchesIt)
{
	// OOWeakSet's common shape: an object keeps a weak set of things that may point back to it.
	struct Group : oo::RefCounted
	{
		oo::WeakSet<Group> peers;
		~Group() override { --gLive; }
		Group() { ++gLive; }
	};
	int before = gLive;
	{
		oo::Ref<Group> g1 = oo::makeRef<Group>();
		oo::Ref<Group> g2 = oo::makeRef<Group>();
		g1->peers.add(g2.get());
		g2->peers.add(g1.get());
		g1->peers.add(g1.get());                // even itself
		OO_CHECK_EQ(g1->peers.count(), 2u);
	}
	OO_CHECK_EQ(gLive, before);                 // weak edges: no cycle, both freed
}

} // namespace

OO_TEST_MAIN()
