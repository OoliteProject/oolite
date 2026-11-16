/*	test_ref.cpp
	Unit tests for oofnd/Ref.hpp (bead oo-qpa): oo::RefCounted, oo::Ref<T>, oo::WeakRef<T> and
	oo::AutoreleaseScope, against the Objective-C retain/release/autorelease contract they mirror
	(ADR-0003) and the OOWeakReference semantics they replace.

	Every test object records its destruction in a log, so the tests assert not just counts but
	WHEN and in WHAT ORDER objects die. tools/check-oofnd.sh also runs this file under
	AddressSanitizer, which turns any over-release or use of a dead object into a failure.
*/

#include "oofnd/Ref.hpp"

#include "oo_test.hpp"

#include <atomic>
#include <map>
#include <set>
#include <string>
#include <thread>
#include <type_traits>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

std::vector<std::string> gDeathLog;
int gLive = 0;

class Thing : public oo::RefCounted
{
public:
	explicit Thing(std::string name) : name_(std::move(name)) { ++gLive; }
	Thing(const Thing& other) : oo::RefCounted(other), name_(other.name_ + "-copy") { ++gLive; }
	Thing& operator=(const Thing&) = default;
	~Thing() override
	{
		--gLive;
		gDeathLog.push_back(name_);
	}

	const std::string& name() const { return name_; }
	int frob() const { return static_cast<int>(name_.size()); }

	oo::Ref<Thing> strong;         // a retained ivar
	oo::WeakRef<Thing> weak;       // a weakRetain'd ivar

private:
	std::string name_;
};

class Derived : public Thing
{
public:
	explicit Derived(std::string name) : Thing(std::move(name)) {}
	int extra = 7;
};

// A -dealloc that does work: it autoreleases a new object and observes weak refs to itself.
class Dealloc : public oo::RefCounted
{
public:
	explicit Dealloc(oo::WeakRef<Dealloc>* watcher, bool* sawSelfNull) : watcher_(watcher), sawSelfNull_(sawSelfNull) { ++gLive; }
	~Dealloc() override
	{
		if (watcher_ != nullptr && sawSelfNull_ != nullptr)  *sawSelfNull_ = watcher_->get() == nullptr && watcher_->expired();
		oo::autorelease(new Thing("born-in-dealloc"));
		--gLive;
		gDeathLog.push_back("dealloc");
	}

private:
	oo::WeakRef<Dealloc>* watcher_;
	bool* sawSelfNull_;
};

// Records what the Ref that held it contains while it is being destroyed.
class Watched : public oo::RefCounted
{
public:
	static inline oo::Ref<Watched>* holder = nullptr;
	static inline std::string seenDuringDealloc;

	explicit Watched(std::string n) : name(std::move(n)) {}
	~Watched() override
	{
		if (holder != nullptr)  seenDuringDealloc = *holder ? (*holder)->name : std::string("null");
	}

	std::string name;
};

void reset()
{
	gDeathLog.clear();
}

// --- compile-time contract --------------------------------------------------------------------

static_assert(sizeof(oo::Ref<Thing>) == sizeof(Thing*), "Ref<T> is one pointer: no control block");
static_assert(std::is_nothrow_move_constructible_v<oo::Ref<Thing>>);
static_assert(std::is_nothrow_move_assignable_v<oo::Ref<Thing>>);
static_assert(!std::is_convertible_v<Thing*, oo::Ref<Thing>>, "raw -> Ref retains, so it is explicit");
static_assert(std::is_convertible_v<oo::Ref<Derived>, oo::Ref<Thing>>);
static_assert(!std::is_convertible_v<oo::Ref<Thing>, oo::Ref<Derived>>);
static_assert(std::is_convertible_v<Thing*, oo::WeakRef<Thing>>, "thing = [aThing weakRetain] stays one line");
static_assert(std::is_convertible_v<oo::WeakRef<Derived>, oo::WeakRef<Thing>>);
static_assert(!std::is_copy_constructible_v<oo::AutoreleaseScope>);

// A Ref to an incomplete type can be declared as a member, like an ivar of a @class.
class Incomplete;
struct HoldsIncomplete
{
	oo::Ref<Incomplete>* p = nullptr;
};

// --- RefCounted: retain / release / alloc ---------------------------------------------------

OO_TEST(countStartsAtOneAndDeletesAtZero)
{
	reset();
	Thing* t = new Thing("a");            // [[Thing alloc] init]
	OO_CHECK_EQ(t->retainCount(), 1u);
	t->retain();
	OO_CHECK_EQ(t->retainCount(), 2u);
	t->release();
	OO_CHECK_EQ(t->retainCount(), 1u);
	OO_CHECK_EQ(gLive, 1);
	t->release();                         // dealloc
	OO_CHECK_EQ(gLive, 0);
	OO_CHECK(gDeathLog == std::vector<std::string>{"a"});
}

OO_TEST(nullSafeFreeFunctions)
{
	Thing* none = nullptr;
	OO_CHECK(oo::retain(none) == nullptr);   // [nil retain] is nil
	oo::release(none);                       // [nil release] is a no-op
	OO_CHECK(oo::autorelease(none) == nullptr);

	Thing* t = new Thing("n");
	OO_CHECK(oo::retain(t) == t);
	OO_CHECK_EQ(t->retainCount(), 2u);
	oo::release(t);
	oo::release(t);
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(copyingAnObjectGivesAFreshCount)
{
	oo::Ref<Thing> a = oo::makeRef<Thing>("orig");
	oo::Ref<Thing> alias = a;
	OO_CHECK_EQ(a->retainCount(), 2u);
	oo::WeakRef<Thing> weakA = a;
	oo::Ref<Thing> b = oo::adopt(new Thing(*a));   // -copyWithZone:
	OO_CHECK_EQ(b->retainCount(), 1u);
	OO_CHECK(b != a);
	oo::WeakRef<Thing> weakB = b;
	OO_CHECK(!(weakA == weakB));                   // the copy has its own identity
	*b = *a;                                       // assignment leaves counts alone
	OO_CHECK_EQ(a->retainCount(), 2u);
	OO_CHECK_EQ(b->retainCount(), 1u);
	b.reset();
	OO_CHECK(weakB.expired());
	OO_CHECK(!weakA.expired());
}

// --- Ref<T>: copy / move / adopt ----------------------------------------------------------------

OO_TEST(refRetainsAndReleases)
{
	reset();
	Thing* raw = new Thing("r");
	{
		oo::Ref<Thing> a(raw);                     // retains: 2
		OO_CHECK_EQ(raw->retainCount(), 2u);
		{
			oo::Ref<Thing> b = a;                  // copy retains: 3
			OO_CHECK_EQ(raw->retainCount(), 3u);
			OO_CHECK(b == a);
			OO_CHECK(b.get() == raw);
		}
		OO_CHECK_EQ(raw->retainCount(), 2u);
	}
	OO_CHECK_EQ(raw->retainCount(), 1u);            // the alloc's +1 is still ours
	OO_CHECK_EQ(gLive, 1);
	raw->release();
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(adoptAndMakeRefTakeTheAllocPlusOne)
{
	{
		oo::Ref<Thing> a = oo::adopt(new Thing("adopted"));
		OO_CHECK_EQ(a->retainCount(), 1u);
		oo::Ref<Thing> b = oo::makeRef<Thing>("made");
		OO_CHECK_EQ(b->retainCount(), 1u);
		OO_CHECK_EQ(gLive, 2);
	}
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(moveStealsWithoutTouchingTheCount)
{
	oo::Ref<Thing> a = oo::makeRef<Thing>("m");
	Thing* raw = a.get();
	oo::Ref<Thing> b = std::move(a);
	OO_CHECK(a == nullptr);
	OO_CHECK(!a);
	OO_CHECK(b.get() == raw);
	OO_CHECK_EQ(raw->retainCount(), 1u);

	oo::Ref<Thing> c;
	c = std::move(b);
	OO_CHECK(b == nullptr);
	OO_CHECK_EQ(raw->retainCount(), 1u);

	oo::Ref<Thing>& self = c;
	c = std::move(self);                           // self-move leaves it intact
	OO_CHECK(c.get() == raw);
	c = self;                                      // self-copy too
	OO_CHECK_EQ(raw->retainCount(), 1u);
	OO_CHECK_EQ(gLive, 1);
	c = nullptr;
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(assignmentInstallsNewBeforeReleasingOld)
{
	// The old object's destructor must observe the holder's NEW value, like a retaining setter.
	Watched::holder = nullptr;
	oo::Ref<Watched> slot;
	Watched::holder = &slot;
	slot = oo::makeRef<Watched>("old");
	slot = oo::makeRef<Watched>("new");
	OO_CHECK_EQ(Watched::seenDuringDealloc, std::string("new"));
	slot.reset();
	OO_CHECK_EQ(Watched::seenDuringDealloc, std::string("null"));
	Watched::holder = nullptr;
}

OO_TEST(convertingAndComparing)
{
	oo::Ref<Derived> d = oo::makeRef<Derived>("d");
	oo::Ref<Thing> t = d;                          // upcast copy retains
	OO_CHECK_EQ(d->retainCount(), 2u);
	OO_CHECK(t == d);
	OO_CHECK(t == d.get());
	OO_CHECK(d.get() == t);
	oo::Ref<Thing> moved = std::move(d);           // upcast move steals
	OO_CHECK(d == nullptr);
	OO_CHECK_EQ(moved->retainCount(), 2u);
	OO_CHECK(t != nullptr);
	OO_CHECK_EQ(static_cast<Derived&>(*t).extra, 7);

	oo::Ref<Thing> x = oo::makeRef<Thing>("x");
	OO_CHECK((t < x) != (x < t));                  // a strict order, for std::set / std::map
	std::set<oo::Ref<Thing>> ordered{t, x, moved};
	OO_CHECK_EQ(ordered.size(), 2u);
	std::unordered_set<oo::Ref<Thing>> hashed{t, x, moved};
	OO_CHECK_EQ(hashed.size(), 2u);
	OO_CHECK_EQ(x->retainCount(), 3u);             // x, ordered, hashed
}

OO_TEST(leakRefHandsOverThePlusOne)
{
	oo::Ref<Thing> a = oo::makeRef<Thing>("leak");
	Thing* raw = a.leakRef();                      // an OO_RETURNS_RETAINED return
	OO_CHECK(a == nullptr);
	OO_CHECK_EQ(raw->retainCount(), 1u);
	OO_CHECK_EQ(gLive, 1);
	oo::Ref<Thing> back = oo::adopt(raw);
	back.reset();
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(resetAndSwap)
{
	oo::Ref<Thing> a = oo::makeRef<Thing>("a");
	oo::Ref<Thing> b = oo::makeRef<Thing>("b");
	Thing* ra = a.get();
	swap(a, b);
	OO_CHECK(b.get() == ra);
	Thing* raw = new Thing("c");
	a.reset(raw);                                  // retains, like the constructor
	OO_CHECK_EQ(raw->retainCount(), 2u);
	raw->release();
	a.reset();
	b.reset();
	OO_CHECK_EQ(gLive, 0);
}

// --- cycles ---------------------------------------------------------------------------------

OO_TEST(strongCyclesAreNotCollected)
{
	reset();
	oo::WeakRef<Thing> watchA, watchB;
	{
		oo::Ref<Thing> a = oo::makeRef<Thing>("cycle-a");
		oo::Ref<Thing> b = oo::makeRef<Thing>("cycle-b");
		a->strong = b;
		b->strong = a;
		watchA = a;
		watchB = b;
	}
	// Both external references are gone, and both objects are still alive: exactly what two
	// ObjC objects that retain each other do. Nothing collects them.
	OO_CHECK_EQ(gLive, 2);
	OO_CHECK(gDeathLog.empty());
	OO_CHECK(!watchA.expired() && !watchB.expired());
	OO_CHECK_EQ(watchA.get()->retainCount(), 1u);
	OO_CHECK_EQ(watchB.get()->retainCount(), 1u);

	// Only breaking an edge by hand frees them (and keeps the rest of this file leak-free).
	watchA.get()->strong.reset();
	OO_CHECK(watchA.expired() && watchB.expired());
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(breakingACycleByHandFreesIt)
{
	reset();
	oo::WeakRef<Thing> watchA, watchB;
	{
		oo::Ref<Thing> a = oo::makeRef<Thing>("a");
		oo::Ref<Thing> b = oo::makeRef<Thing>("b");
		a->strong = b;
		b->strong = a;
		watchA = a;
		watchB = b;
		a->strong.reset();                         // break it, as -dealloc-time teardown code does
	}
	OO_CHECK(watchA.expired());
	OO_CHECK(watchB.expired());
	OO_CHECK(gDeathLog == (std::vector<std::string>{"b", "a"}));   // locals die in reverse order; b's destructor releases a
}

OO_TEST(aWeakBackEdgeMeansNoCycle)
{
	reset();
	int before = gLive;
	{
		oo::Ref<Thing> parent = oo::makeRef<Thing>("parent");
		oo::Ref<Thing> child = oo::makeRef<Thing>("child");
		parent->strong = child;                    // owner -> owned: strong
		child->weak = parent.get();                // owned -> owner: weak, as in the entity graph
		OO_CHECK(child->weak.get() == parent.get());
	}
	OO_CHECK_EQ(gLive, before);
	OO_CHECK(gDeathLog == (std::vector<std::string>{"parent", "child"}));
}

// --- WeakRef<T>: OOWeakReference semantics ----------------------------------------------------

OO_TEST(weakRefNullsOnDealloc)
{
	oo::WeakRef<Thing> w;
	OO_CHECK(w.expired());
	OO_CHECK(w.get() == nullptr);
	{
		oo::Ref<Thing> t = oo::makeRef<Thing>("w");
		w = t.get();                               // thing = [aThing weakRetain]
		OO_CHECK(!w.expired());
		OO_CHECK(w.get() == t.get());              // weakRefUnderlyingObject
		OO_CHECK_EQ(t->retainCount(), 1u);         // a weak reference does not retain
		oo::Ref<Thing> locked = w.lock();
		OO_CHECK(locked == t);
		OO_CHECK_EQ(t->retainCount(), 2u);
	}
	OO_CHECK(w.expired());
	OO_CHECK(w.get() == nullptr);                  // messages to it now act like messages to nil
	OO_CHECK(w.lock() == nullptr);
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(weakRefsAreZeroedBeforeTheDestructorRuns)
{
	reset();
	oo::WeakRef<Dealloc> watcher;
	bool sawSelfNull = false;
	{
		oo::AutoreleaseScope scope;
		Dealloc* d = new Dealloc(&watcher, &sawSelfNull);
		watcher = d;
		d->release();
		OO_CHECK(sawSelfNull);                     // inside ~Dealloc, the weak ref already read null
		OO_CHECK_EQ(scope.pendingCount(), 1u);     // what the destructor autoreleased
	}
	OO_CHECK(gDeathLog == (std::vector<std::string>{"dealloc", "born-in-dealloc"}));
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(manyWeakRefsOneControl)
{
	oo::Ref<Thing> t = oo::makeRef<Thing>("shared");
	std::vector<oo::WeakRef<Thing>> refs(50, oo::WeakRef<Thing>(t.get()));
	oo::WeakRef<Thing> another = t;
	for (const auto& r : refs)  OO_CHECK(r == another);   // one identity, like the one weakSelf proxy
	OO_CHECK_EQ(t->retainCount(), 1u);
	t.reset();
	bool allExpired = true;
	for (const auto& r : refs)  allExpired = allExpired && r.expired();
	OO_CHECK(allExpired);
	refs.clear();                                  // the control block goes with the last WeakRef (ASan)
	OO_CHECK(another.expired());
}

OO_TEST(weakRefCopyMoveAndConversion)
{
	oo::Ref<Derived> d = oo::makeRef<Derived>("d");
	oo::WeakRef<Derived> wd = d;
	oo::WeakRef<Thing> wt = wd;                    // upcast copy
	oo::WeakRef<Thing> wm = std::move(wd);         // upcast move
	OO_CHECK(wd.expired());
	OO_CHECK(wd.get() == nullptr);
	OO_CHECK(wt.get() == d.get());
	OO_CHECK(wm.get() == d.get());
	OO_CHECK(wt == wm);

	oo::WeakRef<Thing> copy = wt;
	oo::WeakRef<Thing> moved;
	moved = std::move(copy);
	OO_CHECK(copy.expired());
	OO_CHECK(moved == wt);
	oo::WeakRef<Thing>& self = moved;
	moved = self;
	moved = std::move(self);
	OO_CHECK(moved == wt);
	moved = nullptr;
	OO_CHECK(moved.expired());
	d.reset();
	OO_CHECK(wt.expired() && wm.expired());
}

OO_TEST(weakIdentitySurvivesDeathAndAddressReuse)
{
	oo::Ref<Thing> a = oo::makeRef<Thing>("a");
	oo::WeakRef<Thing> w = a;
	std::size_t hashBefore = std::hash<oo::WeakRef<Thing>>{}(w);
	OO_CHECK(w == a.get());
	a.reset();
	OO_CHECK_EQ(std::hash<oo::WeakRef<Thing>>{}(w), hashBefore);
	OO_CHECK(w == w);
	// However the allocator reuses the address, a new object is never the dead referent.
	for (int i = 0; i < 16; ++i)
	{
		oo::Ref<Thing> n = oo::makeRef<Thing>("a");
		OO_CHECK(!(w == n.get()));
		oo::WeakRef<Thing> wn = n;
		OO_CHECK(!(w == wn));
	}
	OO_CHECK(!(w == static_cast<const Thing*>(nullptr)));
}

OO_TEST(weakRefOnlyComparisonCreatesNoControl)
{
	oo::Ref<Thing> a = oo::makeRef<Thing>("a");
	oo::Ref<Thing> b = oo::makeRef<Thing>("b");
	oo::WeakRef<Thing> w = a;
	OO_CHECK(!(w == b.get()));
	OO_CHECK(oo::detail::WeakAccess::existingControl(b.get()) == nullptr);
}

// --- AutoreleaseScope: the autorelease pool ----------------------------------------------------

OO_TEST(autoreleaseReleasesAtScopeEnd)
{
	reset();
	OO_CHECK(oo::AutoreleaseScope::current() == nullptr);
	{
		oo::AutoreleaseScope scope;
		OO_CHECK(oo::AutoreleaseScope::current() == &scope);
		Thing* t = oo::autorelease(new Thing("ar"));   // [[[Thing alloc] init] autorelease]
		OO_CHECK_EQ(t->retainCount(), 1u);
		OO_CHECK_EQ(scope.pendingCount(), 1u);
		oo::Ref<Thing> keep(t);                        // a retain that outlives the pool
		OO_CHECK_EQ(gLive, 1);
		(void)keep;
	}
	OO_CHECK_EQ(gLive, 0);                             // keep died first, then the pool's release
	OO_CHECK(oo::AutoreleaseScope::current() == nullptr);

	oo::Ref<Thing> survivor;
	{
		oo::AutoreleaseScope scope;
		survivor = oo::Ref<Thing>(oo::autorelease(new Thing("survivor")));
	}
	OO_CHECK_EQ(gLive, 1);                             // retained past the pool: alive
	OO_CHECK_EQ(survivor->retainCount(), 1u);
	survivor.reset();
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(autoreleaseScopesNest)
{
	reset();
	{
		oo::AutoreleaseScope outer;
		oo::autorelease(new Thing("outer-1"));
		{
			oo::AutoreleaseScope inner;
			OO_CHECK(oo::AutoreleaseScope::current() == &inner);
			oo::autorelease(new Thing("inner-1"));
			oo::autorelease(new Thing("inner-2"));
			OO_CHECK_EQ(inner.pendingCount(), 2u);
			OO_CHECK_EQ(outer.pendingCount(), 1u);     // the innermost scope receives them
		}
		OO_CHECK(oo::AutoreleaseScope::current() == &outer);
		OO_CHECK(gDeathLog == (std::vector<std::string>{"inner-2", "inner-1"}));   // LIFO (ADR-0045)
		OO_CHECK_EQ(gLive, 1);
		oo::autorelease(new Thing("outer-2"));
	}
	OO_CHECK(gDeathLog == (std::vector<std::string>{"inner-2", "inner-1", "outer-2", "outer-1"}));
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(drainReleasesInOrderAndKeepsTheScopeOpen)
{
	reset();
	oo::AutoreleaseScope scope;
	for (int i = 0; i < 3; ++i)  oo::autorelease(new Thing("t" + std::to_string(i)));
	scope.drain();                                     // [pool release]; pool = [[... alloc] init]
	OO_CHECK(gDeathLog == (std::vector<std::string>{"t2", "t1", "t0"}));   // the game's order: LIFO (ADR-0045)
	OO_CHECK_EQ(scope.pendingCount(), 0u);
	OO_CHECK(oo::AutoreleaseScope::current() == &scope);
	oo::autorelease(new Thing("after-drain"));
	OO_CHECK_EQ(scope.pendingCount(), 1u);
	scope.drain();
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(drainingCascades)
{
	// Releasing a pooled object whose destructor autoreleases more objects drains those too, in
	// the same drain, as libobjc2's emptyPool loops until the pool is empty. LIFO (ADR-0045): the
	// newest (sibling) goes first, and born-in-dealloc lands on top, so it goes right after.
	reset();
	{
		oo::AutoreleaseScope scope;
		oo::autorelease(new Dealloc(nullptr, nullptr));   // no watcher: it would die before the drain
		oo::autorelease(new Thing("sibling"));
	}
	OO_CHECK(gDeathLog == (std::vector<std::string>{"sibling", "dealloc", "born-in-dealloc"}));
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(autoreleaseAnOwnedRef)
{
	reset();
	{
		oo::AutoreleaseScope scope;
		oo::Ref<Thing> r = oo::makeRef<Thing>("owned");
		Thing* t = oo::autorelease(std::move(r));      // return [[x retain] autorelease]
		OO_CHECK(r == nullptr);
		OO_CHECK_EQ(t->retainCount(), 1u);
		OO_CHECK_EQ(t->frob(), 5);
	}
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(multipleAutoreleasesOfOneObject)
{
	reset();
	{
		oo::AutoreleaseScope scope;
		Thing* t = new Thing("twice");
		t->retain();
		oo::autorelease(t);
		oo::autorelease(t);                            // two +1s handed over, two releases
		OO_CHECK_EQ(scope.pendingCount(), 2u);
	}
	OO_CHECK(gDeathLog == std::vector<std::string>{"twice"});
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(autoreleaseWithNoScopeLeaksAndIsCounted)
{
	std::size_t before = oo::AutoreleaseScope::leakedWithoutScope();
	Thing* t = new Thing("orphan");
	t->retain();                                       // keep our own +1 so the test can clean up
	oo::autorelease(t);                                // GNUstep: "autorelease called without pool"
	OO_CHECK_EQ(oo::AutoreleaseScope::leakedWithoutScope(), before + 1);
	OO_CHECK_EQ(t->retainCount(), 2u);                 // nothing will ever release that +1
	t->release();
	t->release();                                      // the test pays the leaked +1 back
	OO_CHECK_EQ(gLive, 0);
}

OO_TEST(scopesArePerThread)
{
	reset();
	oo::AutoreleaseScope mainScope;
	std::atomic<bool> threadSawNoScope{false};
	std::atomic<bool> threadDrained{false};
	std::thread worker([&] {
		threadSawNoScope = oo::AutoreleaseScope::current() == nullptr;
		{
			oo::AutoreleaseScope workerScope;
			oo::autorelease(new Thing("worker"));
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

// --- thread safety of the count (ADR-0003) ----------------------------------------------------

OO_TEST(retainReleaseAreAtomicAcrossThreads)
{
	class Counter : public oo::RefCounted
	{
	public:
		explicit Counter(std::atomic<int>* deaths) : deaths_(deaths) {}
		~Counter() override { deaths_->fetch_add(1); }

	private:
		std::atomic<int>* deaths_;
	};
	std::atomic<int> deaths{0};
	oo::Ref<Counter> shared = oo::makeRef<Counter>(&deaths);
	constexpr int kThreads = 8;
	constexpr int kIterations = 20000;
	std::vector<std::thread> threads;
	for (int i = 0; i < kThreads; ++i)
	{
		threads.emplace_back([shared] {                // each thread copies (retains) the Ref
			for (int j = 0; j < kIterations; ++j)
			{
				oo::Ref<Counter> local = shared;
				oo::Ref<Counter> moved = std::move(local);
			}
		});
	}
	for (std::thread& t : threads)  t.join();
	OO_CHECK_EQ(shared->retainCount(), 1u);
	OO_CHECK_EQ(deaths.load(), 0);
	shared.reset();
	OO_CHECK_EQ(deaths.load(), 1);                     // exactly one dealloc

	// The final release may happen on another thread; the destructor runs there, once.
	oo::Ref<Counter> handedOff = oo::makeRef<Counter>(&deaths);
	std::thread last([r = std::move(handedOff)]() mutable { r.reset(); });
	last.join();
	OO_CHECK_EQ(deaths.load(), 2);
}

} // namespace

OO_TEST_MAIN()
