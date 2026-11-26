/*	test_weakset.cpp
        Unit tests for oofnd/WeakSet.hpp: oo::WeakSet<T>, the
   replacement for OOWeakSet, checked against the semantics OOWeakSet.h
   documents (members leave silently when they die, identity not equality,
   adding nil is a no-op, removing a non-member is fine, copies hold the live
   members) plus insertion-order iteration and mutation-safe forEach().
*/

#include <memory>
#include <string>
#include <vector>

#include "oo_test.hpp"
#include "oofnd/Object.hpp"
#include "oofnd/WeakSet.hpp"

namespace {

int gLive = 0;

class Ship : public oo::Object {
 public:
  explicit Ship(std::string name) : name(std::move(name)) { ++gLive; }
  ~Ship() override { --gLive; }

  // Value-equal ships are still different members: WeakSet uniques by identity.
  bool operator==(const Ship& other) const { return name == other.name; }

  std::string name;
  int pinged = 0;
};

class Cruiser : public Ship {
 public:
  using Ship::Ship;
};

std::vector<std::string> names(const oo::WeakSet<Ship>& set) {
  std::vector<std::string> out;
  for (const std::shared_ptr<Ship>& s : set.allObjects()) out.push_back(s->name);
  return out;
}

OO_TEST(addContainsCount) {
  oo::WeakSet<Ship> set;
  OO_CHECK(set.empty());
  std::shared_ptr<Ship> a = oo::makeShared<Ship>("a");
  std::shared_ptr<Ship> b = oo::makeShared<Ship>("b");
  set.add(a.get());
  set.add(b);
  OO_CHECK_EQ(set.count(), 2u);
  OO_CHECK(set.contains(a.get()));
  OO_CHECK(set.contains(b.get()));
  OO_CHECK_EQ(a.use_count(), 1);  // membership does not retain

  set.add(a.get());  // a set: adding twice is one member
  OO_CHECK_EQ(set.count(), 2u);

  std::shared_ptr<Ship> twin = oo::makeShared<Ship>("a");
  OO_CHECK(*twin == *a);
  OO_CHECK(!set.contains(twin.get()));  // equal value, different identity
  set.add(twin.get());
  OO_CHECK_EQ(set.count(), 3u);
}

OO_TEST(addingNullIsIgnored) {
  oo::WeakSet<Ship> set;
  set.add(static_cast<Ship*>(nullptr));
  set.add(std::shared_ptr<Ship>());
  OO_CHECK_EQ(set.count(), 0u);
  OO_CHECK(!set.contains(nullptr));
  set.remove(nullptr);  // and so is removing it
}

OO_TEST(membersLeaveSilentlyWhenTheyDie) {
  oo::WeakSet<Ship> set;
  std::shared_ptr<Ship> keep = oo::makeShared<Ship>("keep");
  set.add(keep.get());
  {
    std::shared_ptr<Ship> brief = oo::makeShared<Ship>("brief");
    set.add(brief.get());
    OO_CHECK_EQ(set.count(), 2u);
  }
  OO_CHECK_EQ(set.count(), 1u);  // no notification; the count just drops
  OO_CHECK(names(set) == std::vector<std::string>{"keep"});
  keep.reset();
  OO_CHECK_EQ(set.count(), 0u);
  OO_CHECK(set.empty());
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(aNewObjectAtADeadMembersAddressIsNotAMember) {
  oo::WeakSet<Ship> set;
  {
    std::shared_ptr<Ship> dead = oo::makeShared<Ship>("dead");
    set.add(dead.get());
  }
  for (int i = 0; i < 16; ++i) {
    std::shared_ptr<Ship> fresh =
        oo::makeShared<Ship>("dead");  // same size: the allocator may reuse it
    OO_CHECK(!set.contains(fresh.get()));
  }
  OO_CHECK_EQ(set.count(), 0u);
}

OO_TEST(removeMembersAndNonMembers) {
  oo::WeakSet<Ship> set;
  std::shared_ptr<Ship> a = oo::makeShared<Ship>("a");
  std::shared_ptr<Ship> b = oo::makeShared<Ship>("b");
  std::shared_ptr<Ship> outsider = oo::makeShared<Ship>("outsider");
  set.add(a.get());
  set.add(b.get());
  set.remove(outsider.get());  // not a member: no complaint, no change
  OO_CHECK_EQ(set.count(), 2u);
  OO_CHECK_EQ(outsider.use_count(), 1);  // and no side effect
  set.remove(a.get());
  OO_CHECK(!set.contains(a.get()));
  OO_CHECK_EQ(set.count(), 1u);
  set.remove(a.get());
  OO_CHECK_EQ(set.count(), 1u);
  set.add(a.get());  // re-adding goes to the end
  OO_CHECK(names(set) == (std::vector<std::string>{"b", "a"}));
  set.removeAll();
  OO_CHECK(set.empty());
  OO_CHECK_EQ(a.use_count(), 1);
}

OO_TEST(allObjectsIsLiveRetainedAndInInsertionOrder) {
  oo::WeakSet<Ship> set;
  std::vector<std::shared_ptr<Ship>> ships;
  for (const char* n : {"c", "a", "d", "b"}) {
    ships.push_back(oo::makeShared<Ship>(n));
    set.add(ships.back().get());
  }
  OO_CHECK(names(set) == (std::vector<std::string>{"c", "a", "d", "b"}));
  ships[2].reset();  // "d" dies
  std::vector<std::shared_ptr<Ship>> all = set.allObjects();
  OO_CHECK_EQ(all.size(), 3u);
  OO_CHECK_EQ(all[0].use_count(),
              2);  // the snapshot retains, as NSArray did
  OO_CHECK(names(set) == (std::vector<std::string>{"c", "a", "b"}));
}

OO_TEST(forEachIsMakeObjectsPerformSelector) {
  oo::WeakSet<Ship> set;
  std::shared_ptr<Ship> a = oo::makeShared<Ship>("a");
  std::shared_ptr<Ship> b = oo::makeShared<Ship>("b");
  set.add(a.get());
  set.add(b.get());
  set.forEach([](Ship& s) { ++s.pinged; });
  OO_CHECK_EQ(a->pinged, 1);
  OO_CHECK_EQ(b->pinged, 1);
}

OO_TEST(forEachSurvivesMutationAndDeathInTheCallback) {
  oo::WeakSet<Ship> set;
  std::vector<std::shared_ptr<Ship>> owners;
  for (int i = 0; i < 4; ++i) {
    owners.push_back(oo::makeShared<Ship>("s" + std::to_string(i)));
    set.add(owners.back().get());
  }
  std::shared_ptr<Ship> late = oo::makeShared<Ship>("late");
  int visited = 0;
  set.forEach([&](Ship& s) {
    ++visited;
    if (s.name == "s0") {
      owners.clear();       // every member loses its last external owner...
      set.remove(&s);       // ...the set is mutated...
      set.add(late.get());  // ...and grows, mid-iteration
    }
    OO_CHECK(
        !s.name.empty());  // ...yet each visited object is still alive (ASan)
  });
  OO_CHECK_EQ(visited, 4);  // the snapshot taken at the start
  OO_CHECK(names(set) == std::vector<std::string>{"late"});
  OO_CHECK_EQ(gLive, 1);
}

OO_TEST(copiesHoldTheLiveMembers) {
  oo::WeakSet<Ship> set(8);
  std::shared_ptr<Ship> a = oo::makeShared<Ship>("a");
  set.add(a.get());
  {
    std::shared_ptr<Ship> gone = oo::makeShared<Ship>("gone");
    set.add(gone.get());
  }
  oo::WeakSet<Ship> copy = set;  // -copyWithZone: compacts first
  OO_CHECK_EQ(copy.count(), 1u);
  OO_CHECK(copy.contains(a.get()));
  std::shared_ptr<Ship> b = oo::makeShared<Ship>("b");
  copy.add(b.get());
  OO_CHECK(!set.contains(b.get()));  // independent sets

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

OO_TEST(equalityIsSameLiveMembers) {
  std::shared_ptr<Ship> a = oo::makeShared<Ship>("a");
  std::shared_ptr<Ship> b = oo::makeShared<Ship>("b");
  oo::WeakSet<Ship> x, y;
  x.add(a.get());
  x.add(b.get());
  y.add(b.get());
  y.add(a.get());
  OO_CHECK(x == y);  // order does not matter for equality
  {
    std::shared_ptr<Ship> c = oo::makeShared<Ship>("c");
    x.add(c.get());
    OO_CHECK(x != y);
  }
  OO_CHECK(x == y);  // c died: the sets are equal again
  std::shared_ptr<Ship> twin = oo::makeShared<Ship>("a");
  oo::WeakSet<Ship> z;
  z.add(twin.get());
  z.add(b.get());
  OO_CHECK(x != z);  // identity, not isEqual:
}

OO_TEST(addAllFromARange) {
  std::vector<std::shared_ptr<Ship>> refs{oo::makeShared<Ship>("r1"),
                                  oo::makeShared<Ship>("r2")};
  std::vector<Ship*> raws{refs[0].get(), nullptr, refs[1].get()};
  oo::WeakSet<Ship> set;
  set.addAll(refs);
  set.addAll(raws);  // duplicates and nulls are ignored
  OO_CHECK_EQ(set.count(), 2u);

  oo::WeakSet<Ship> other;
  other.addAll(set.allObjects());  // -addObjectsByEnumerating:
  OO_CHECK(other == set);
}

OO_TEST(subclassMembers) {
  oo::WeakSet<Ship> set;
  std::shared_ptr<Cruiser> c = oo::makeShared<Cruiser>("cruiser");
  set.add(c.get());
  OO_CHECK(set.contains(c.get()));
  std::vector<std::shared_ptr<Cruiser>> cruisers{c};
  set.addAll(cruisers);
  OO_CHECK_EQ(set.count(), 1u);
  c.reset();
  cruisers.clear();
  OO_CHECK(set.empty());
}

OO_TEST(aMemberCanOwnTheSetThatWatchesIt) {
  // OOWeakSet's common shape: an object keeps a weak set of things that may
  // point back to it.
  struct Group : oo::Object {
    oo::WeakSet<Group> peers;
    ~Group() override { --gLive; }
    Group() { ++gLive; }
  };
  int before = gLive;
  {
    std::shared_ptr<Group> g1 = oo::makeShared<Group>();
    std::shared_ptr<Group> g2 = oo::makeShared<Group>();
    g1->peers.add(g2.get());
    g2->peers.add(g1.get());
    g1->peers.add(g1.get());  // even itself
    OO_CHECK_EQ(g1->peers.count(), 2u);
  }
  OO_CHECK_EQ(gLive, before);  // weak edges: no cycle, both freed
}

}  // namespace

OO_TEST_MAIN()
