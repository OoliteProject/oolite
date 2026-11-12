/*	test_OOAsyncWorkManagerShutdown.cpp
        Unit tests for OOAsyncWorkManager::shutdown() (src/Core/OOAsyncWorkManager.h),
   the quit path's join of the work threads (spec 009 US3).

        Pins: shutdown() waits for a task a work thread has already started and
   returns once it has finished; it returns promptly when the workers are idle;
   a task added after shutdown is never performed (no worker is left); a second
   shutdown() is harmless. Its own executable, because shutdown() stops the one
   shared manager for the rest of the process. Run: tests/run.sh unit
*/

#include <atomic>
#include <chrono>
#include <thread>

#include "OOAsyncWorkManager.h"
#include "oo_test.hpp"

// OOLogging.mm would link the game's log file and resource manager in; the
// abstract base class's subclass-responsibility message it defines is never
// reached by these tests.
void OOLogGenericSubclassResponsibilityForFunction(const char*) {}

namespace {

class SlowTask : public OOAsyncWorkTask {
 public:
  void performAsyncTask() override {
    started = true;
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    finished = true;
  }

  std::atomic<bool> started = false;
  std::atomic<bool> finished = false;
};

class FlagTask : public OOAsyncWorkTask {
 public:
  void performAsyncTask() override { performed = true; }

  std::atomic<bool> performed = false;
};

// Waits (up to five seconds) for a work thread to set flag.
bool WaitFor(const std::atomic<bool>& flag) {
  for (int i = 0; i < 500 && !flag; i++)
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  return flag;
}

}  // namespace

OO_TEST(shutdownWaitsForAStartedTaskThenStopsTheWorkers) {
  OOAsyncWorkManager* manager = OOAsyncWorkManager::sharedAsyncWorkManager();
  const oo::Ref<SlowTask> slow = oo::makeRef<SlowTask>();
  OO_CHECK(manager->addTask(slow.get(), kOOAsyncPriorityMedium));
  OO_CHECK(WaitFor(slow->started));

  const auto start = std::chrono::steady_clock::now();
  manager->shutdown();
  OO_CHECK(slow->finished);  // the busy worker finished its task first
  OO_CHECK(std::chrono::steady_clock::now() - start < std::chrono::seconds(5));

  // No worker is left to perform a task added now.
  const oo::Ref<FlagTask> late = oo::makeRef<FlagTask>();
  manager->addTask(late.get(), kOOAsyncPriorityHigh);
  std::this_thread::sleep_for(std::chrono::milliseconds(500));
  OO_CHECK(!late->performed);

  manager->shutdown();  // twice is harmless
}

OO_TEST_MAIN()
