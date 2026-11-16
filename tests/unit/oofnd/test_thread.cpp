/*	test_thread.cpp
	Unit tests for oofnd/Thread.hpp (bead oo-3rb.6): the std::thread replacements for NSThread.
	On Windows this TU includes <windows.h> AFTER the header, which also proves the header's
	kernel32 declarations are identical redeclarations.
*/

#include "oofnd/Thread.hpp"

#if defined(_WIN32)
#include <windows.h>
#endif

#include "oo_test.hpp"

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>

namespace {

// Runs `body` through oo::thread::detach and waits for it to finish. The wait is UNBOUNDED
// (bead oo-3rb.68): a 10 s bound flaked under a loaded ASan build, and a timed-out wait returned
// while the detached lambda still held references to this frame's m/cv/done - a use-after-return
// in the test itself. A hung thread is bounded by the run's own timeout (check-oofnd, ctest,
// accept.sh's budget) instead. Returns true once `body` has run, so callers still check it.
template <typename F>
bool RunDetachedAndWait(F body)
{
	std::mutex m;
	std::condition_variable cv;
	bool done = false;
	oo::thread::detach([&] {
		body();
		std::lock_guard<std::mutex> lock(m);
		done = true;
		cv.notify_one();
	});
	std::unique_lock<std::mutex> lock(m);
	cv.wait(lock, [&] { return done; });
	return done;
}

} // namespace

OO_TEST(mainThreadIsTheStaticInitThread)
{
	OO_CHECK(oo::thread::isMainThread());
	OO_CHECK(oo::thread::kMainThreadId == std::this_thread::get_id());
}

OO_TEST(detachedThreadRunsAndIsNotMain)
{
	std::atomic<int> ran{0};
	std::atomic<bool> wasMain{true};
	OO_CHECK(RunDetachedAndWait([&] {
		wasMain = oo::thread::isMainThread();
		++ran;
	}));
	OO_CHECK_EQ(ran.load(), 1);
	OO_CHECK(!wasMain.load());
}

OO_TEST(detachMovesItsCallable)
{
	std::string seen;
	std::string payload = "moved into the thread";
	OO_CHECK(RunDetachedAndWait([&seen, p = std::move(payload)] { seen = p; }));
	OO_CHECK_EQ(seen, std::string("moved into the thread"));
}

OO_TEST(setCurrentNameIsReadBack)
{
	bool ok = false;
	std::string readBack;
	OO_CHECK(RunDetachedAndWait([&] {
		ok = oo::thread::setCurrentName("OOAsyncWorkManager thread 1");
#if defined(_WIN32)
		PWSTR desc = nullptr;
		if (SUCCEEDED(GetThreadDescription(GetCurrentThread(), &desc)) && desc != nullptr)
		{
			for (const wchar_t *c = desc; *c != L'\0'; ++c)  readBack.push_back(static_cast<char>(*c));
			LocalFree(desc);
		}
#else
		char buf[64] = {};
		if (pthread_getname_np(pthread_self(), buf, sizeof buf) == 0)  readBack = buf;
#endif
	}));
	OO_CHECK(ok);
#if defined(_WIN32)
	OO_CHECK_EQ(readBack, std::string("OOAsyncWorkManager thread 1"));
#else
	OO_CHECK_EQ(readBack, std::string("OOAsyncWorkManager thread 1").substr(0, 15));
#endif
}

#if defined(_WIN32)
OO_TEST(priorityMappingIsGNUstepsMeasuredOne)
{
	// The table measured against gnustep-base 1.31's +[NSThread setThreadPriority:].
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(-1.0), THREAD_PRIORITY_IDLE);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.0), THREAD_PRIORITY_IDLE);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.01), THREAD_PRIORITY_LOWEST);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.25), THREAD_PRIORITY_LOWEST);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.26), THREAD_PRIORITY_BELOW_NORMAL);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.49), THREAD_PRIORITY_BELOW_NORMAL);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.5), THREAD_PRIORITY_NORMAL);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.51), THREAD_PRIORITY_ABOVE_NORMAL);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.74), THREAD_PRIORITY_ABOVE_NORMAL);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.75), THREAD_PRIORITY_HIGHEST);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(0.99), THREAD_PRIORITY_HIGHEST);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(1.0), THREAD_PRIORITY_TIME_CRITICAL);
	OO_CHECK_EQ(oo::thread::windowsPriorityFor(1.5), THREAD_PRIORITY_TIME_CRITICAL);
}
#endif

OO_TEST(setCurrentPriorityAppliesToTheCallingThread)
{
	bool ok = false;
	int observed = -99;
	OO_CHECK(RunDetachedAndWait([&] {
		ok = oo::thread::setCurrentPriority(0.4);
#if defined(_WIN32)
		observed = GetThreadPriority(GetCurrentThread());
#else
		observed = 0;
#endif
		oo::thread::setCurrentPriority(0.5);
	}));
	OO_CHECK(ok);
#if defined(_WIN32)
	OO_CHECK_EQ(observed, THREAD_PRIORITY_BELOW_NORMAL);
	OO_CHECK_EQ(GetThreadPriority(GetCurrentThread()), THREAD_PRIORITY_NORMAL);   // main untouched
#endif
}

OO_TEST_MAIN()
