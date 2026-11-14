/*	test_OOProfilingStopwatch.mm
	Unit tests for OOProfilingStopwatch (src/Core/OOProfilingStopwatch.h): bead oo-m7aj, a Phase 3
	conversion in the OOColor house style (proposed ADR-0056). Its only callers (OOCacheManager,
	OOMesh; both behind profiling switches that are off) were converted with it, so it has no
	Objective-C facade and the class is global.

	Pins what the stopwatch measured before the conversion: a new stopwatch is running; while
	running, currentTime() is now - start and grows; stop() freezes it; reset() returns the current
	value and restarts from zero (drift-free while running); start() restarts a stopped watch; and
	OOHighResTimeDeltaInSeconds() converts this build's microsecond readings. Timings sleep and
	compare against generous bounds, so a loaded machine cannot fail them.
	Run: bash tools/check-core-tests.sh
*/

#import "OOProfilingStopwatch.h"

#include "oo_test.hpp"

#include <chrono>
#include <thread>


namespace {

void Sleep(int milliseconds)
{
	std::this_thread::sleep_for(std::chrono::milliseconds(milliseconds));
}

}	// namespace


OO_TEST(deltaInSeconds)
{
	OOHighResTimeValue start = OOGetHighResTime();
	OOHighResTimeValue end = OOCopyHighResTime(start);
	OO_CHECK_EQ(OOHighResTimeDeltaInSeconds(start, end), 0.0);
	Sleep(20);
	end = OOGetHighResTime();
	OOTimeDelta delta = OOHighResTimeDeltaInSeconds(start, end);
	OO_CHECK(delta >= 0.015 && delta < 5.0);
	OO_CHECK(OOHighResTimeDeltaInSeconds(end, start) == -delta);
#if OO_PROFILING_STOPWATCH_MICROSECONDS
	OO_CHECK_EQ(OOHighResTimeDeltaInSeconds(0, 1500000), 1.5);	// microseconds
#endif
}


OO_TEST(newStopwatchIsRunning)
{
	oo::Ref<OOProfilingStopwatch> watch = OOProfilingStopwatch::stopwatch();
	OO_CHECK(watch != nullptr);
	OOTimeDelta first = watch->currentTime();
	OO_CHECK(first >= 0.0 && first < 5.0);
	Sleep(20);
	OOTimeDelta second = watch->currentTime();
	OO_CHECK(second >= first + 0.015);
}


OO_TEST(stopFreezesTheTime)
{
	oo::Ref<OOProfilingStopwatch> watch = oo::makeRef<OOProfilingStopwatch>();
	Sleep(20);
	watch->stop();
	OOTimeDelta stopped = watch->currentTime();
	OO_CHECK(stopped >= 0.015 && stopped < 5.0);
	Sleep(20);
	OO_CHECK_EQ(watch->currentTime(), stopped);
}


OO_TEST(resetWhileStopped)
{
	oo::Ref<OOProfilingStopwatch> watch = OOProfilingStopwatch::stopwatch();
	Sleep(20);
	watch->stop();
	OOTimeDelta stopped = watch->currentTime();
	OO_CHECK_EQ(watch->reset(), stopped);	// the value it had
	OO_CHECK_EQ(watch->currentTime(), 0.0);	// and zero after
	Sleep(10);
	OO_CHECK_EQ(watch->currentTime(), 0.0);	// still stopped
}


OO_TEST(resetWhileRunningIsDriftFree)
{
	OOHighResTimeValue before = OOGetHighResTime();
	oo::Ref<OOProfilingStopwatch> watch = OOProfilingStopwatch::stopwatch();
	Sleep(20);
	OOTimeDelta firstLap = watch->reset();
	OO_CHECK(firstLap >= 0.015 && firstLap < 5.0);
	Sleep(20);
	OOTimeDelta secondLap = watch->reset();
	OO_CHECK(secondLap >= 0.015 && secondLap < 5.0);
	OOHighResTimeValue after = OOGetHighResTime();
	// The laps add up to no more than the time around both (the restart is the reading).
	OO_CHECK(firstLap + secondLap <= OOHighResTimeDeltaInSeconds(before, after) + 1e-6);
	OO_CHECK(watch->currentTime() < secondLap);	// running again from the second reset
}


OO_TEST(startRestartsAStoppedWatch)
{
	oo::Ref<OOProfilingStopwatch> watch = OOProfilingStopwatch::stopwatch();
	Sleep(30);
	watch->stop();
	OOTimeDelta stopped = watch->currentTime();
	watch->start();
	OOTimeDelta restarted = watch->currentTime();
	OO_CHECK(restarted < stopped);	// measured from the new start
	Sleep(20);
	OO_CHECK(watch->currentTime() >= restarted + 0.015);	// and running
}


OO_TEST_MAIN()
