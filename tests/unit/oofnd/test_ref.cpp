/*	test_ref.cpp
        Unit tests for the game's shared ownership: oo::Object, oo::makeShared,
   oo::share and the weak-reference helpers (oofnd/Object.hpp) over
   std::shared_ptr / std::weak_ptr, and oo::AutoreleaseScope, against the
   Objective-C retain/release/autorelease contract they replace and the
   OOWeakReference semantics.

        Every test object records its destruction in a log, so the tests assert
   not just counts but WHEN and in WHAT ORDER objects die. Running
   this file under AddressSanitizer also helps: it turns any over-release or
   use of a dead object into a failure.
*/

#include <atomic>
#include <memory>
#include <set>
#include <string>
#include <thread>
#include <type_traits>
#include <unordered_set>
#include <utility>
#include <vector>

#include "oo_test.hpp"
#include "oofnd/AutoreleaseScope.hpp"
#include "oofnd/Object.hpp"

namespace {

std::vector<std::string> gDeathLog;
int gLive = 0;

class Thing : public oo::Object {
 public:
  explicit Thing(std::string name) : name_(std::move(name)) { ++gLive; }
  Thing(const Thing& other) : oo::Object(other), name_(other.name_ + "-copy") {
    ++gLive;
  }
  Thing& operator=(const Thing&) = default;
  ~Thing() override {
    --gLive;
    gDeathLog.push_back(name_);
  }

  const std::string& name() const { return name_; }
  int frob() const { return static_cast<int>(name_.size()); }

  std::shared_ptr<Thing> strong;  // a retained ivar
  std::weak_ptr<Thing> weak;      // a weakRetain'd ivar

 private:
  std::string name_;
};

class Derived : public Thing {
 public:
  explicit Derived(std::string name) : Thing(std::move(name)) {}
  int extra = 7;
};

// A -dealloc that does work: it autoreleases a new object and observes weak
// refs to itself.
class Dealloc : public oo::Object {
 public:
  explicit Dealloc(std::weak_ptr<Dealloc>* watcher, bool* sawSelfNull)
      : watcher_(watcher), sawSelfNull_(sawSelfNull) {
    ++gLive;
  }
  ~Dealloc() override {
    if (watcher_ != nullptr && sawSelfNull_ != nullptr)
      *sawSelfNull_ = watcher_->lock() == nullptr && watcher_->expired();
    oo::autorelease(oo::makeShared<Thing>("born-in-dealloc"));
    --gLive;
    gDeathLog.push_back("dealloc");
  }

 private:
  std::weak_ptr<Dealloc>* watcher_;
  bool* sawSelfNull_;
};

// Records what the shared_ptr that held it contains while it is being
// destroyed.
class Watched : public oo::Object {
 public:
  static inline std::shared_ptr<Watched>* holder = nullptr;
  static inline std::string seenDuringDealloc;

  explicit Watched(std::string n) : name(std::move(n)) {}
  ~Watched() override {
    if (holder != nullptr)
      seenDuringDealloc = *holder ? (*holder)->name : std::string("null");
  }

  std::string name;
};

void reset() { gDeathLog.clear(); }

// --- compile-time contract
// --------------------------------------------------------------------

static_assert(sizeof(std::shared_ptr<Thing>) == sizeof(std::shared_ptr<Thing>),
              "an owning reference is a std::shared_ptr<T> and nothing more");
static_assert(std::is_nothrow_move_constructible_v<std::shared_ptr<Thing>>);
static_assert(std::is_nothrow_move_assignable_v<std::shared_ptr<Thing>>);
static_assert(!std::is_convertible_v<Thing*, std::shared_ptr<Thing>>,
              "raw -> owner takes ownership, so it is explicit (oo::share)");
static_assert(
    std::is_convertible_v<std::shared_ptr<Derived>, std::shared_ptr<Thing>>);
static_assert(
    !std::is_convertible_v<std::shared_ptr<Thing>, std::shared_ptr<Derived>>);
static_assert(
    std::is_convertible_v<std::shared_ptr<Thing>, std::weak_ptr<Thing>>,
    "thing = [aThing weakRetain] stays one line");
static_assert(
    std::is_convertible_v<std::weak_ptr<Derived>, std::weak_ptr<Thing>>);
static_assert(!std::is_copy_constructible_v<oo::AutoreleaseScope>);

// An owning reference to an incomplete type can be declared as a member, like
// an ivar of a @class.
class Incomplete;
struct HoldsIncomplete {
  std::shared_ptr<Incomplete>* p = nullptr;
};

// --- ownership counts
// ---------------------------------------------------

OO_TEST(countStartsAtOneAndDeletesAtZero) {
  reset();
  std::shared_ptr<Thing> t = oo::makeShared<Thing>("a");  // [[Thing alloc] init]
  OO_CHECK_EQ(t.use_count(), 1);
  std::shared_ptr<Thing> another = t;
  OO_CHECK_EQ(t.use_count(), 2);
  another.reset();
  OO_CHECK_EQ(t.use_count(), 1);
  OO_CHECK_EQ(gLive, 1);
  t.reset();  // dealloc
  OO_CHECK_EQ(gLive, 0);
  OO_CHECK(gDeathLog == std::vector<std::string>{"a"});
}

OO_TEST(nullSafeFreeFunctions) {
  // [nil autorelease] is nil.
  OO_CHECK(oo::autorelease(std::shared_ptr<Thing>()) == nullptr);
  OO_CHECK(oo::share(static_cast<Thing*>(nullptr)) == nullptr);
}

OO_TEST(copyingAnObjectGivesAFreshCount) {
  std::shared_ptr<Thing> a = oo::makeShared<Thing>("orig");
  std::shared_ptr<Thing> alias = a;
  OO_CHECK_EQ(a.use_count(), 2);
  std::weak_ptr<Thing> weakA = a;
  std::shared_ptr<Thing> b = oo::makeShared<Thing>(*a);  // -copyWithZone:
  OO_CHECK_EQ(b.use_count(), 1);
  OO_CHECK(b != a);
  std::weak_ptr<Thing> weakB = b;
  OO_CHECK(!oo::sameObject(weakA, weakB));  // the copy has its own identity
  *b = *a;                                  // assignment leaves counts alone
  OO_CHECK_EQ(a.use_count(), 2);
  OO_CHECK_EQ(b.use_count(), 1);
  b.reset();
  OO_CHECK(weakB.expired());
  OO_CHECK(!weakA.expired());
}

// --- std::shared_ptr<T>: copy / move / share
// ----------------------------------------------------------------

OO_TEST(refRetainsAndReleases) {
  reset();
  std::shared_ptr<Thing> owner = oo::makeShared<Thing>("r");
  Thing* raw = owner.get();
  {
    std::shared_ptr<Thing> a = oo::share(raw);  // retains: 2
    OO_CHECK_EQ(owner.use_count(), 2);
    {
      std::shared_ptr<Thing> b = a;  // copy retains: 3
      OO_CHECK_EQ(owner.use_count(), 3);
      OO_CHECK(b == a);
      OO_CHECK(b.get() == raw);
    }
    OO_CHECK_EQ(owner.use_count(), 2);
  }
  OO_CHECK_EQ(owner.use_count(), 1);  // the alloc's +1 is still ours
  OO_CHECK_EQ(gLive, 1);
  owner.reset();
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(adoptAndMakeRefTakeTheAllocPlusOne) {
  {
    std::shared_ptr<Thing> a = oo::makeShared<Thing>("adopted");
    OO_CHECK_EQ(a.use_count(), 1);
    std::shared_ptr<Thing> b = oo::makeShared<Thing>("made");
    OO_CHECK_EQ(b.use_count(), 1);
    OO_CHECK_EQ(gLive, 2);
  }
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(moveStealsWithoutTouchingTheCount) {
  std::shared_ptr<Thing> a = oo::makeShared<Thing>("m");
  Thing* raw = a.get();
  std::shared_ptr<Thing> b = std::move(a);
  OO_CHECK(a == nullptr);
  OO_CHECK(!a);
  OO_CHECK(b.get() == raw);
  OO_CHECK_EQ(b.use_count(), 1);

  std::shared_ptr<Thing> c;
  c = std::move(b);
  OO_CHECK(b == nullptr);
  OO_CHECK_EQ(c.use_count(), 1);

  std::shared_ptr<Thing>& self = c;
  c = std::move(self);  // self-move leaves it intact
  OO_CHECK(c.get() == raw);
  c = self;  // self-copy too
  OO_CHECK_EQ(c.use_count(), 1);
  OO_CHECK_EQ(gLive, 1);
  c = nullptr;
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(assignmentInstallsNewBeforeReleasingOld) {
  // The old object's destructor must observe the holder's NEW value, like a
  // retaining setter.
  Watched::holder = nullptr;
  std::shared_ptr<Watched> slot;
  Watched::holder = &slot;
  slot = oo::makeShared<Watched>("old");
  slot = oo::makeShared<Watched>("new");
  OO_CHECK_EQ(Watched::seenDuringDealloc, std::string("new"));
  slot.reset();
  OO_CHECK_EQ(Watched::seenDuringDealloc, std::string("null"));
  Watched::holder = nullptr;
}

OO_TEST(convertingAndComparing) {
  std::shared_ptr<Derived> d = oo::makeShared<Derived>("d");
  std::shared_ptr<Thing> t = d;  // upcast copy retains
  OO_CHECK_EQ(d.use_count(), 2);
  OO_CHECK(t == d);
  OO_CHECK(t.get() == d.get());
  std::shared_ptr<Thing> moved = std::move(d);  // upcast move steals
  OO_CHECK(d == nullptr);
  OO_CHECK_EQ(moved.use_count(), 2);
  OO_CHECK(t != nullptr);
  OO_CHECK_EQ(static_cast<Derived&>(*t).extra, 7);

  std::shared_ptr<Thing> x = oo::makeShared<Thing>("x");
  OO_CHECK((t < x) != (x < t));  // a strict order, for std::set / std::map
  std::set<std::shared_ptr<Thing>> ordered{t, x, moved};
  OO_CHECK_EQ(ordered.size(), 2u);
  std::unordered_set<std::shared_ptr<Thing>> hashed{t, x, moved};
  OO_CHECK_EQ(hashed.size(), 2u);
  OO_CHECK_EQ(x.use_count(), 3);  // x, ordered, hashed
}

OO_TEST(resetAndSwap) {
  std::shared_ptr<Thing> a = oo::makeShared<Thing>("a");
  std::shared_ptr<Thing> b = oo::makeShared<Thing>("b");
  Thing* ra = a.get();
  swap(a, b);
  OO_CHECK(b.get() == ra);
  std::shared_ptr<Thing> owner = oo::makeShared<Thing>("c");
  Thing* raw = owner.get();
  a = oo::share(raw);  // retains, like the constructor
  OO_CHECK_EQ(owner.use_count(), 2);
  owner.reset();
  a.reset();
  b.reset();
  OO_CHECK_EQ(gLive, 0);
}

// --- cycles
// ---------------------------------------------------------------------------------

OO_TEST(strongCyclesAreNotCollected) {
  reset();
  std::weak_ptr<Thing> watchA, watchB;
  {
    std::shared_ptr<Thing> a = oo::makeShared<Thing>("cycle-a");
    std::shared_ptr<Thing> b = oo::makeShared<Thing>("cycle-b");
    a->strong = b;
    b->strong = a;
    watchA = a;
    watchB = b;
  }
  // Both external references are gone, and both objects are still alive:
  // exactly what two objects that retain each other do. Nothing collects
  // them.
  OO_CHECK_EQ(gLive, 2);
  OO_CHECK(gDeathLog.empty());
  OO_CHECK(!watchA.expired() && !watchB.expired());
  OO_CHECK_EQ(watchA.use_count(), 1);
  OO_CHECK_EQ(watchB.use_count(), 1);

  // Only breaking an edge by hand frees them (and keeps the rest of this file
  // leak-free).
  watchA.lock()->strong.reset();
  OO_CHECK(watchA.expired() && watchB.expired());
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(breakingACycleByHandFreesIt) {
  reset();
  std::weak_ptr<Thing> watchA, watchB;
  {
    std::shared_ptr<Thing> a = oo::makeShared<Thing>("a");
    std::shared_ptr<Thing> b = oo::makeShared<Thing>("b");
    a->strong = b;
    b->strong = a;
    watchA = a;
    watchB = b;
    a->strong.reset();  // break it, as -dealloc-time teardown code does
  }
  OO_CHECK(watchA.expired());
  OO_CHECK(watchB.expired());
  OO_CHECK(
      gDeathLog ==
      (std::vector<std::string>{
          "b",
          "a"}));  // locals die in reverse order; b's destructor releases a
}

OO_TEST(aWeakBackEdgeMeansNoCycle) {
  reset();
  int before = gLive;
  {
    std::shared_ptr<Thing> parent = oo::makeShared<Thing>("parent");
    std::shared_ptr<Thing> child = oo::makeShared<Thing>("child");
    parent->strong = child;  // owner -> owned: strong
    child->weak = parent;    // owned -> owner: weak, as in the entity graph
    OO_CHECK(child->weak.lock() == parent);
  }
  OO_CHECK_EQ(gLive, before);
  OO_CHECK(gDeathLog == (std::vector<std::string>{"parent", "child"}));
}

// --- std::weak_ptr<T>: OOWeakReference semantics
// ----------------------------------------------------

OO_TEST(weakRefNullsOnDealloc) {
  std::weak_ptr<Thing> w;
  OO_CHECK(w.expired());
  OO_CHECK(w.lock() == nullptr);
  {
    std::shared_ptr<Thing> t = oo::makeShared<Thing>("w");
    w = t;  // thing = [aThing weakRetain]
    OO_CHECK(!w.expired());
    OO_CHECK(w.lock() == t);         // weakRefUnderlyingObject
    OO_CHECK_EQ(t.use_count(), 1);   // a weak reference does not retain
    std::shared_ptr<Thing> locked = w.lock();
    OO_CHECK(locked == t);
    OO_CHECK_EQ(t.use_count(), 2);
  }
  OO_CHECK(w.expired());
  OO_CHECK(w.lock() == nullptr);  // messages to it now act like messages to nil
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(weakRefsAreZeroedBeforeTheDestructorRuns) {
  reset();
  std::weak_ptr<Dealloc> watcher;
  bool sawSelfNull = false;
  {
    oo::AutoreleaseScope scope;
    std::shared_ptr<Dealloc> d = oo::makeShared<Dealloc>(&watcher, &sawSelfNull);
    watcher = d;
    d.reset();
    OO_CHECK(sawSelfNull);  // inside ~Dealloc, the weak ref already read null
    OO_CHECK_EQ(scope.pendingCount(), 1u);  // what the destructor autoreleased
  }
  OO_CHECK(gDeathLog ==
           (std::vector<std::string>{"dealloc", "born-in-dealloc"}));
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(manyWeakRefsOneControl) {
  std::shared_ptr<Thing> t = oo::makeShared<Thing>("shared");
  std::vector<std::weak_ptr<Thing>> refs(50, std::weak_ptr<Thing>(t));
  std::weak_ptr<Thing> another = t;
  for (const auto& r : refs)
    OO_CHECK(oo::sameObject(r, another));  // one identity, like the one
                                           // weakSelf proxy
  OO_CHECK_EQ(t.use_count(), 1);
  t.reset();
  bool allExpired = true;
  for (const auto& r : refs) allExpired = allExpired && r.expired();
  OO_CHECK(allExpired);
  refs.clear();  // the control block goes with the last weak_ptr (ASan)
  OO_CHECK(another.expired());
}

OO_TEST(weakRefCopyMoveAndConversion) {
  std::shared_ptr<Derived> d = oo::makeShared<Derived>("d");
  std::weak_ptr<Derived> wd = d;
  std::weak_ptr<Thing> wt = wd;             // upcast copy
  std::weak_ptr<Thing> wm = std::move(wd);  // upcast move
  OO_CHECK(wd.expired());
  OO_CHECK(wd.lock() == nullptr);
  OO_CHECK(wt.lock() == d);
  OO_CHECK(wm.lock() == d);
  OO_CHECK(oo::sameObject(wt, wm));

  std::weak_ptr<Thing> copy = wt;
  std::weak_ptr<Thing> moved;
  moved = std::move(copy);
  OO_CHECK(copy.expired());
  OO_CHECK(oo::sameObject(moved, wt));
  std::weak_ptr<Thing>& self = moved;
  moved = self;
  moved = std::move(self);
  OO_CHECK(oo::sameObject(moved, wt));
  moved.reset();
  OO_CHECK(moved.expired());
  d.reset();
  OO_CHECK(wt.expired() && wm.expired());
}

OO_TEST(weakIdentitySurvivesDeathAndAddressReuse) {
  std::shared_ptr<Thing> a = oo::makeShared<Thing>("a");
  std::weak_ptr<Thing> w = a;
  const std::weak_ptr<Thing> before = w;
  OO_CHECK(oo::sameObject(w, std::weak_ptr<Thing>(a)));
  a.reset();
  OO_CHECK(oo::sameObject(w, before));
  OO_CHECK(oo::sameObject(w, w));
  // However the allocator reuses the address, a new object is never the dead
  // referent.
  for (int i = 0; i < 16; ++i) {
    std::shared_ptr<Thing> n = oo::makeShared<Thing>("a");
    std::weak_ptr<Thing> wn = n;
    OO_CHECK(!oo::sameObject(w, wn));
  }
  OO_CHECK(!oo::isUnset(w));
}

OO_TEST(weakRefOnlyComparisonCreatesNoControl) {
  std::shared_ptr<Thing> a = oo::makeShared<Thing>("a");
  std::shared_ptr<Thing> b = oo::makeShared<Thing>("b");
  std::weak_ptr<Thing> w = a;
  OO_CHECK(!oo::sameObject(w, b->weak_from_this()));
  OO_CHECK_EQ(b.use_count(), 1);  // comparing took no ownership of b
}

// willDispose(): the last owner's release runs it once, with the object whole
// and its weak references already empty, before the destructor runs.
class Disposing : public Thing {
 public:
  explicit Disposing(std::string name, std::vector<std::string>* log)
      : Thing(std::move(name)), _log(log) {}
  ~Disposing() override { _log->push_back("destructor"); }
  std::weak_ptr<Thing> watcher;

 protected:
  void willDispose() noexcept override {
    _log->push_back(std::string("willDispose, weak ") +
                    (watcher.lock().get() == this ? "live" : "dead") +
                    ", name " + name());
  }

 private:
  std::vector<std::string>* _log;
};

OO_TEST(willDisposeRunsOnceWithTheObjectWhole) {
  std::vector<std::string> log;
  std::shared_ptr<Disposing> d = oo::makeShared<Disposing>("d", &log);
  d->watcher = d;
  std::weak_ptr<Thing> outside = d;
  {
    std::shared_ptr<Disposing> extra = d;  // a balanced retain and release
  }
  OO_CHECK(log.empty());
  d.reset();
  OO_CHECK((log == std::vector<std::string>{"willDispose, weak dead, name d",
                                            "destructor"}));
  OO_CHECK(outside.expired());
}

// --- AutoreleaseScope: the autorelease pool
// ----------------------------------------------------

OO_TEST(autoreleaseReleasesAtScopeEnd) {
  reset();
  OO_CHECK(oo::AutoreleaseScope::current() == nullptr);
  {
    oo::AutoreleaseScope scope;
    OO_CHECK(oo::AutoreleaseScope::current() == &scope);
    Thing* t = oo::autorelease(
        oo::makeShared<Thing>("ar"));  // [[[Thing alloc] init] autorelease]
    OO_CHECK_EQ(scope.pendingCount(), 1u);
    std::shared_ptr<Thing> keep = oo::share(t);  // a retain that outlives
                                                 // the pool
    OO_CHECK_EQ(keep.use_count(), 2);            // the pool's and keep's
    OO_CHECK_EQ(gLive, 1);
  }
  OO_CHECK_EQ(gLive, 0);  // keep died first, then the pool's release
  OO_CHECK(oo::AutoreleaseScope::current() == nullptr);

  std::shared_ptr<Thing> survivor;
  {
    oo::AutoreleaseScope scope;
    survivor = oo::share(oo::autorelease(oo::makeShared<Thing>("survivor")));
  }
  OO_CHECK_EQ(gLive, 1);  // retained past the pool: alive
  OO_CHECK_EQ(survivor.use_count(), 1);
  survivor.reset();
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(autoreleaseScopesNest) {
  reset();
  {
    oo::AutoreleaseScope outer;
    oo::autorelease(oo::makeShared<Thing>("outer-1"));
    {
      oo::AutoreleaseScope inner;
      OO_CHECK(oo::AutoreleaseScope::current() == &inner);
      oo::autorelease(oo::makeShared<Thing>("inner-1"));
      oo::autorelease(oo::makeShared<Thing>("inner-2"));
      OO_CHECK_EQ(inner.pendingCount(), 2u);
      OO_CHECK_EQ(outer.pendingCount(),
                  1u);  // the innermost scope receives them
    }
    OO_CHECK(oo::AutoreleaseScope::current() == &outer);
    OO_CHECK(gDeathLog ==
             (std::vector<std::string>{"inner-2", "inner-1"}));  // LIFO
    OO_CHECK_EQ(gLive, 1);
    oo::autorelease(oo::makeShared<Thing>("outer-2"));
  }
  OO_CHECK(gDeathLog == (std::vector<std::string>{"inner-2", "inner-1",
                                                  "outer-2", "outer-1"}));
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(drainReleasesInOrderAndKeepsTheScopeOpen) {
  reset();
  oo::AutoreleaseScope scope;
  for (int i = 0; i < 3; ++i)
    oo::autorelease(oo::makeShared<Thing>("t" + std::to_string(i)));
  scope.drain();  // [pool release]; pool = [[... alloc] init]
  OO_CHECK(gDeathLog == (std::vector<std::string>{
                            "t2", "t1", "t0"}));  // the game's order: LIFO
  OO_CHECK_EQ(scope.pendingCount(), 0u);
  OO_CHECK(oo::AutoreleaseScope::current() == &scope);
  oo::autorelease(oo::makeShared<Thing>("after-drain"));
  OO_CHECK_EQ(scope.pendingCount(), 1u);
  scope.drain();
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(drainingCascades) {
  // Releasing a pooled object whose destructor autoreleases more objects drains
  // those too, in the same drain, as libobjc2's emptyPool loops until the pool
  // is empty. LIFO: the newest (sibling) goes first, and
  // born-in-dealloc lands on top, so it goes right after.
  reset();
  {
    oo::AutoreleaseScope scope;
    oo::autorelease(oo::makeShared<Dealloc>(
        nullptr, nullptr));  // no watcher: it would die before the drain
    oo::autorelease(oo::makeShared<Thing>("sibling"));
  }
  OO_CHECK(gDeathLog ==
           (std::vector<std::string>{"sibling", "dealloc", "born-in-dealloc"}));
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(autoreleaseAnOwnedRef) {
  reset();
  {
    oo::AutoreleaseScope scope;
    std::shared_ptr<Thing> r = oo::makeShared<Thing>("owned");
    Thing* t = oo::autorelease(std::move(r));  // return [[x retain] autorelease]
    OO_CHECK(r == nullptr);
    OO_CHECK_EQ(oo::share(t).use_count(), 2);  // the pool's, and this one
    OO_CHECK_EQ(t->frob(), 5);
  }
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(multipleAutoreleasesOfOneObject) {
  reset();
  {
    oo::AutoreleaseScope scope;
    std::shared_ptr<Thing> t = oo::makeShared<Thing>("twice");
    oo::autorelease(t);
    oo::autorelease(std::move(t));  // two owners handed over, two releases
    OO_CHECK_EQ(scope.pendingCount(), 2u);
  }
  OO_CHECK(gDeathLog == std::vector<std::string>{"twice"});
  OO_CHECK_EQ(gLive, 0);
}

OO_TEST(autoreleaseWithNoScopeLeaksAndIsCounted) {
  // Not a Thing: the object is kept forever, so it must stay out of gLive.
  class Orphan : public oo::Object {};
  std::size_t before = oo::AutoreleaseScope::leakedWithoutScope();
  std::shared_ptr<Orphan> t = oo::makeShared<Orphan>();
  std::weak_ptr<Orphan> watch = t;
  oo::autorelease(std::move(t));  // GNUstep: "autorelease called without pool"
  OO_CHECK_EQ(oo::AutoreleaseScope::leakedWithoutScope(), before + 1);
  OO_CHECK(!watch.expired());  // nothing will ever release that owner
  OO_CHECK_EQ(watch.use_count(), 1);
}

OO_TEST(scopesArePerThread) {
  reset();
  oo::AutoreleaseScope mainScope;
  std::atomic<bool> threadSawNoScope{false};
  std::atomic<bool> threadDrained{false};
  std::thread worker([&] {
    threadSawNoScope = oo::AutoreleaseScope::current() == nullptr;
    {
      oo::AutoreleaseScope workerScope;
      oo::autorelease(oo::makeShared<Thing>("worker"));
    }
    threadDrained = true;
  });
  worker.join();
  OO_CHECK(threadSawNoScope);
  OO_CHECK(threadDrained);
  OO_CHECK_EQ(mainScope.pendingCount(), 0u);
  OO_CHECK(oo::AutoreleaseScope::current() == &mainScope);
  OO_CHECK(gDeathLog == std::vector<std::string>{"worker"});
}

// --- thread safety of the count
// ----------------------------------------------------

OO_TEST(retainReleaseAreAtomicAcrossThreads) {
  class Counter : public oo::Object {
   public:
    explicit Counter(std::atomic<int>* deaths) : deaths_(deaths) {}
    ~Counter() override { deaths_->fetch_add(1); }

   private:
    std::atomic<int>* deaths_;
  };
  std::atomic<int> deaths{0};
  std::shared_ptr<Counter> shared = oo::makeShared<Counter>(&deaths);
  constexpr int kThreads = 8;
  constexpr int kIterations = 20000;
  std::vector<std::thread> threads;
  for (int i = 0; i < kThreads; ++i) {
    threads.emplace_back([shared] {  // each thread copies (retains) the owner
      for (int j = 0; j < kIterations; ++j) {
        std::shared_ptr<Counter> local = shared;
        std::shared_ptr<Counter> moved = std::move(local);
      }
    });
  }
  for (std::thread& t : threads) t.join();
  OO_CHECK_EQ(shared.use_count(), 1);
  OO_CHECK_EQ(deaths.load(), 0);
  shared.reset();
  OO_CHECK_EQ(deaths.load(), 1);  // exactly one dealloc

  // The final release may happen on another thread; the destructor runs there,
  // once.
  std::shared_ptr<Counter> handedOff = oo::makeShared<Counter>(&deaths);
  std::thread last([r = std::move(handedOff)]() mutable { r.reset(); });
  last.join();
  OO_CHECK_EQ(deaths.load(), 2);
}

}  // namespace

OO_TEST_MAIN()
