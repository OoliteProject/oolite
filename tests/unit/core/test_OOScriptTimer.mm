/*	test_OOScriptTimer.mm
	Unit tests for OOScriptTimer (src/Core/Scripting/OOScriptTimer.h/.mm): bead oo-kdyh, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056).

	OOScriptTimer is the abstract base of script timers: it keeps the fire time and interval,
	schedules itself in a priority queue ordered by next fire time (OOPriorityQueue, bead oo-3lj8),
	and +updateTimers fires the due ones in order, rescheduling the repeating ones. This pins what
	it computed before the conversion: the initialisers (and the one that answers nil), the
	interval clamp, setNextTime's refusal while scheduled, the description, the firing order,
	one-shot and repeating timers, a timer scheduled while the timers are updating (deferred to the
	end of the update), a timer that stops itself when it fires, +noteGameReset, and the ordering
	selector the queue calls. The expectations were written against the Objective-C API, with an
	Objective-C subclass, and run on the unconverted class first (commit 709ecf5c8). The class
	keeps a facade, so the checks that use the base class alone still run through it (its
	forwarding test); the subclass is ported to a C++ one, because no Objective-C subclass of the
	facade can override the C++ virtual timerFired() (no adapter: ADR-0056 amendment 1 is not
	needed once OOJSTimer, the only subclass, is C++), and the checks that use it call the C++
	class. The facade's contract (identity, nil, the facade class) is checked last.
	Run: bash tools/check-core-tests.sh
*/

#import "OOScriptTimer.h"
#import "oofnd/objc/OOObject.h"
#import "OOLogging.h"
#import "OODescription.h"

#include "oo_test.hpp"

#include <string>
#include <vector>


/*	The game's OOLogging.mm reaches the resource manager, so it is not linked. The functions of it
	that the class calls are defined here instead, and count.
*/
static int gSubclassResponsibilities = 0;

void OOLogGenericSubclassResponsibilityForFunction(const char *inFunction)
{
	(void)inFunction;
	gSubclassResponsibilities++;
}

const char *const cxx_kOOLogException = "exception";


/*	The universe, as far as OOScriptTimer sees it: the game clock (-getTime), which the test sets.
*/
static double gNow = 100.0;

@interface FakeUniverse: OOObject
- (double) getTime;
@end

@implementation FakeUniverse
- (double) getTime  { return gNow; }
@end

@class Universe;
Universe *gSharedUniverse = nil;


// A timer that records its firings in a shared log, and can be told to stop itself or to start
// another timer when it fires.
static std::vector<std::string> gFired;

class TestTimer final : public cxx::OOScriptTimer
{
public:
	static oo::Ref<TestTimer> timerWithNextTime(OOTimeAbsolute nextTime, OOTimeDelta interval)
	{
		oo::Ref<TestTimer> timer = oo::adopt(new TestTimer);
		if (!timer->initWithNextTime(nextTime, interval))  return nullptr;
		return timer;
	}

	void timerFired() override
	{
		gFired.push_back(name);
		if (stopWhenFired)  unscheduleTimer();
		if (startWhenFired != nullptr)  startWhenFired->scheduleTimer();
	}

	std::string					name;
	bool						stopWhenFired = false;
	cxx::OOScriptTimer			*startWhenFired = nullptr;
};


namespace {

void SetUp(double now)
{
	if (gSharedUniverse == nil)  gSharedUniverse = (Universe *)[[FakeUniverse alloc] init];
	gNow = now;
	gFired.clear();
}


oo::Ref<TestTimer> MakeTimer(const char *name, double nextTime, double interval)
{
	oo::Ref<TestTimer> timer = TestTimer::timerWithNextTime(nextTime, interval);
	if (timer != nullptr)  timer->name = name;
	return timer;
}


std::string Fired()
{
	std::string result;
	for (const std::string &name : gFired)  result += (result.empty() ? "" : ",") + name;
	return result;
}

}	// namespace


OO_TEST(initialisers)
{
	@autoreleasepool
	{
		SetUp(100.0);
		OOScriptTimer *timer = [[[OOScriptTimer alloc] initWithNextTime:110.0 interval:5.0] autorelease];
		OO_CHECK(timer != nil);
		OO_CHECK_EQ([timer nextTime], 110.0);
		OO_CHECK_EQ([timer interval], 5.0);
		OO_CHECK(![timer isScheduled]);

		// A negative next time is "now + interval"; a non-positive interval is -1 (one-shot).
		timer = [[[OOScriptTimer alloc] initWithNextTime:-1.0 interval:5.0] autorelease];
		OO_CHECK_EQ([timer nextTime], 105.0);
		timer = [[[OOScriptTimer alloc] initWithNextTime:120.0 interval:0.0] autorelease];
		OO_CHECK_EQ([timer interval], -1.0);
		OO_CHECK_EQ([timer nextTime], 120.0);

		// A past (or negative) next time with no interval is meaningless: nil.
		OO_CHECK([[OOScriptTimer alloc] initWithNextTime:90.0 interval:-1.0] == nil);
		OO_CHECK([[OOScriptTimer alloc] initWithNextTime:-1.0 interval:0.0] == nil);
		OO_CHECK([[[OOScriptTimer alloc] initWithNextTime:100.0 interval:-1.0] autorelease] != nil);

		// A one-shot timer fires after the delay.
		timer = [[[OOScriptTimer alloc] initOneShotTimerWithDelay:2.5] autorelease];
		OO_CHECK_EQ([timer nextTime], 102.5);
		OO_CHECK_EQ([timer interval], -1.0);
	}
}


OO_TEST(accessors)
{
	@autoreleasepool
	{
		SetUp(100.0);
		OOScriptTimer *timer = [[[OOScriptTimer alloc] initWithNextTime:110.0 interval:5.0] autorelease];
		[timer setInterval:-3.0];
		OO_CHECK_EQ([timer interval], -1.0);
		[timer setInterval:7.0];
		OO_CHECK_EQ([timer interval], 7.0);
		OO_CHECK([timer setNextTime:130.0]);
		OO_CHECK_EQ([timer nextTime], 130.0);

		// While scheduled the next time cannot change.
		OO_CHECK([timer scheduleTimer]);
		OO_CHECK([timer isScheduled]);
		OO_CHECK([timer scheduleTimer]);	// already scheduled: YES, no second entry
		OO_CHECK(![timer setNextTime:140.0]);
		OO_CHECK_EQ([timer nextTime], 130.0);
		[timer unscheduleTimer];
		OO_CHECK(![timer isScheduled]);
		OO_CHECK([timer setNextTime:140.0]);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		SetUp(100.0);
		OOScriptTimer *timer = [[[OOScriptTimer alloc] initWithNextTime:110.0 interval:5.0] autorelease];
		OO_CHECK_EQ([timer cxx_descriptionComponents].value_or("<none>"), "nextTime: 110, interval: 5, not running");
		[timer scheduleTimer];
		OO_CHECK_EQ([timer cxx_descriptionComponents].value_or("<none>"), "nextTime: 110, interval: 5, running");
		[timer unscheduleTimer];
		timer = [[[OOScriptTimer alloc] initOneShotTimerWithDelay:1.5] autorelease];
		OO_CHECK_EQ([timer cxx_descriptionComponents].value_or("<none>"), "nextTime: 101.5, one-shot, not running");
		OO_CHECK(oo::DescriptionOf(timer).find("OOScriptTimer") != std::string::npos);
	}
}


OO_TEST(ordering)
{
	@autoreleasepool
	{
		SetUp(100.0);
		OOScriptTimer *early = [[[OOScriptTimer alloc] initWithNextTime:110.0 interval:5.0] autorelease];
		OOScriptTimer *late = [[[OOScriptTimer alloc] initWithNextTime:120.0 interval:5.0] autorelease];
		OO_CHECK_EQ([early compareByNextFireTime:late], OOOrderedAscending);
		OO_CHECK_EQ([late compareByNextFireTime:early], OOOrderedDescending);
		OO_CHECK_EQ([early compareByNextFireTime:early], OOOrderedSame);
		OO_CHECK_EQ([early compareByNextFireTime:nil], OOOrderedDescending);	// nil is -INFINITY
	}
}


OO_TEST(firing)
{
	@autoreleasepool
	{
		SetUp(100.0);
		oo::Ref<TestTimer> b = MakeTimer("b", 120.0, -1.0);
		oo::Ref<TestTimer> a = MakeTimer("a", 110.0, -1.0);
		oo::Ref<TestTimer> r = MakeTimer("r", 105.0, 10.0);
		OO_CHECK(b->scheduleTimer() && a->scheduleTimer() && r->scheduleTimer());

		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "");

		gNow = 112.0;
		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "r,a");
		OO_CHECK(!a->isScheduled());	// one-shot: done
		OO_CHECK(r->isScheduled());	// repeating: rescheduled at the next multiple of its interval
		OO_CHECK_EQ(r->nextTime(), 115.0);

		gNow = 130.0;
		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "r,a,r,b");
		OO_CHECK_EQ(r->nextTime(), 135.0);
		OO_CHECK(!b->isScheduled());

		// A one-shot that has run cannot be scheduled again once its time has passed.
		OO_CHECK(!a->scheduleTimer());
		OO_CHECK(!a->isScheduled());

		r->unscheduleTimer();
		gNow = 200.0;
		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "r,a,r,b");
	}
}


OO_TEST(scheduleMovesPastTimeForward)
{
	@autoreleasepool
	{
		SetUp(100.0);
		oo::Ref<TestTimer> r = MakeTimer("r", 101.0, 4.0);
		gNow = 110.0;
		OO_CHECK(r->isValidForScheduling());
		OO_CHECK_EQ(r->nextTime(), 113.0);	// the next 101 + 4n after now
		gNow = 113.0;
		oo::Ref<TestTimer> s = MakeTimer("s", 105.0, 4.0);
		OO_CHECK(s->isValidForScheduling());
		OO_CHECK_EQ(s->nextTime(), 113.0);	// exactly now: not run yet, so it may fire now
	}
}


OO_TEST(stopsItselfAndDefers)
{
	@autoreleasepool
	{
		SetUp(100.0);
		oo::Ref<TestTimer> stopper = MakeTimer("stopper", 101.0, 5.0);
		stopper->stopWhenFired = true;
		oo::Ref<TestTimer> later = MakeTimer("later", 102.0, -1.0);
		oo::Ref<TestTimer> starter = MakeTimer("starter", 101.5, -1.0);
		starter->startWhenFired = later.get();
		OO_CHECK(stopper->scheduleTimer() && starter->scheduleTimer());

		gNow = 103.0;
		cxx::OOScriptTimer::updateTimers();
		// "later" was due, but it was scheduled during the update, so it waits for the next one.
		OO_CHECK_EQ(Fired(), "stopper,starter");
		OO_CHECK(!stopper->isScheduled());
		OO_CHECK(later->isScheduled());

		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "stopper,starter,later");
		OO_CHECK(!later->isScheduled());
	}
}


OO_TEST(gameReset)
{
	@autoreleasepool
	{
		SetUp(100.0);
		oo::Ref<TestTimer> a = MakeTimer("a", 110.0, 5.0);
		oo::Ref<TestTimer> b = MakeTimer("b", 120.0, -1.0);
		OO_CHECK(a->scheduleTimer() && b->scheduleTimer());
		cxx::OOScriptTimer::noteGameReset();
		OO_CHECK(!a->isScheduled());
		OO_CHECK(!b->isScheduled());
		gNow = 200.0;
		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "");	// the queue was emptied
		OO_CHECK(a->scheduleTimer());	// and they can be scheduled again
		cxx::OOScriptTimer::updateTimers();
		OO_CHECK_EQ(Fired(), "a");
		a->unscheduleTimer();
	}
}


OO_TEST(baseTimerFired)
{
	@autoreleasepool
	{
		SetUp(100.0);
		OOScriptTimer *timer = [[[OOScriptTimer alloc] initWithNextTime:101.0 interval:-1.0] autorelease];
		OO_CHECK([timer scheduleTimer]);
		gSubclassResponsibilities = 0;
		gNow = 102.0;
		[OOScriptTimer updateTimers];
		OO_CHECK_EQ(gSubclassResponsibilities, 1);
		OO_CHECK(![timer isScheduled]);
	}
}


OO_TEST(scheduledTimerIsKept)
{
	// The timer subsystem retains a scheduled timer: one the caller has let go of still fires.
	SetUp(100.0);
	@autoreleasepool
	{
		OO_CHECK(MakeTimer("kept", 101.0, -1.0)->scheduleTimer());
	}
	gNow = 102.0;
	@autoreleasepool
	{
		cxx::OOScriptTimer::updateTimers();
	}
	OO_CHECK_EQ(Fired(), "kept");
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp(100.0);
		// A C++ timer crosses as one facade while it lives, of the root class (TestTimer has no
		// Objective-C class of its name), and back.
		oo::Ref<TestTimer> timer = MakeTimer("f", 110.0, 5.0);
		OOScriptTimer *facade = oo::ToObjC(timer.get());
		OO_CHECK(facade != nil);
		OO_CHECK(facade == oo::ToObjC(timer.get()));
		OO_CHECK([facade class] == [OOScriptTimer class]);
		OO_CHECK(oo::ToCxx(facade) == timer.get());
		OO_CHECK(oo::LiveObjC(timer.get()) == facade);
		OO_CHECK_EQ([facade nextTime], 110.0);
		OO_CHECK(oo::ToObjC(static_cast<cxx::OOScriptTimer *>(nullptr)) == nil);
		OO_CHECK(oo::ToCxx(static_cast<OOScriptTimer *>(nil)) == nullptr);

		// A facade's initialiser makes the C++ timer and is its facade; nil stays nil.
		OOScriptTimer *made = [[[OOScriptTimer alloc] initWithNextTime:120.0 interval:-1.0] autorelease];
		OO_CHECK(oo::ToObjC(oo::ToCxx(made)) == made);

		// The facade's -timerFired reaches the C++ override.
		gFired.clear();
		[facade timerFired];
		OO_CHECK_EQ(Fired(), "f");
	}
	@autoreleasepool
	{
		// No live facade: LiveObjC never makes one.
		oo::Ref<TestTimer> timer = MakeTimer("g", 110.0, 5.0);
		OO_CHECK(oo::LiveObjC(timer.get()) == nil);
	}
}


OO_TEST_MAIN()
