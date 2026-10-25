/*	test_OOAsyncWorkManager.mm
	Unit tests for OOAsyncWorkManager (src/Core/OOAsyncWorkManager.h): bead oo-x2wy, a Phase 3
	conversion in the OOColor house style (proposed ADR-0056; amendment oo-x2wy for the protocol
	and the private subclasses).

	Pins what the manager did before the conversion: one shared manager; nil is refused; a task is
	performed on a work thread
	and then completed on the thread that waits for it or collects pending tasks; a task without
	-completeAsyncTask is performed and never collected; waiting for a task that was never added
	returns at once; an exception thrown by -performAsyncTask is swallowed and the task still
	completes; every priority is accepted and performed. The tasks were Objective-C objects
	adopting OOAsyncWorkTask until bead oo-9ht.14 made the protocol a C++ interface; they are C++
	tasks with the same behaviour, and the facade's tests went with the facade (standing approval
	oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#include "OOAsyncWorkManager.h"

#include "oofnd/objc/OOException.h"	// oo::Exception (bead oo-rskgl.1)
#include "oo_test.hpp"

#include <atomic>
#include <chrono>
#include <thread>


class TestTask : public OOAsyncWorkTask
{
public:
	TestTask()  { callingThread = std::this_thread::get_id(); }

	void performAsyncTask() override
	{
		performedOnCallingThread = (std::this_thread::get_id() == callingThread);
		performed = true;
		if (shouldThrow)  throw oo::Exception(OOGenericException, "");	// was @throw of an OOObject: the managers swallow the game's exception (bead oo-rskgl.1)
	}

	bool hasCompleteAsyncTask() const override  { return true; }

	void completeAsyncTask() override
	{
		completedAfterPerform = performed;
		completedOnCallingThread = (std::this_thread::get_id() == callingThread);
		completions++;
	}

	std::atomic<bool>	performed = false;
	std::atomic<bool>	performedOnCallingThread = false;
	std::atomic<int>	completions = 0;
	bool				completedAfterPerform = false;
	bool				completedOnCallingThread = false;
	bool				shouldThrow = false;
	std::thread::id		callingThread;
};


// A task with no completion (the method was optional).
class TestFireAndForgetTask : public OOAsyncWorkTask
{
public:
	void performAsyncTask() override
	{
		performed = true;
	}

	std::atomic<bool>	performed = false;
};


// OOLogging.mm would link the game's log file and resource manager in; the abstract base
// class's subclass-responsibility message it defines is never reached by these tests.
void OOLogGenericSubclassResponsibilityForFunction(const char *)
{
}


namespace {

// Waits (up to five seconds) for a work thread to set flag.
bool WaitFor(const std::atomic<bool> &flag)
{
	for (int i = 0; i < 500 && !flag; i++)  std::this_thread::sleep_for(std::chrono::milliseconds(10));
	return flag;
}

}	// namespace


OO_TEST(oneSharedManager)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(OOAsyncWorkManager::sharedAsyncWorkManager() == manager);
	}
}


OO_TEST(nilIsRefused)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		OO_CHECK(!manager->addTask(nullptr, kOOAsyncPriorityMedium));
		manager->waitForTaskToComplete(nullptr);	// returns at once
	}
}


OO_TEST(waitPerformsThenCompletesOnTheWaitingThread)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		const oo::Ref<TestTask> task = oo::makeRef<TestTask>();
		OO_CHECK(manager->addTask(task.get(), kOOAsyncPriorityMedium));
		manager->waitForTaskToComplete(task.get());
		OO_CHECK(task->performed);
		OO_CHECK(!task->performedOnCallingThread);	// on a work thread
		OO_CHECK_EQ(task->completions.load(), 1);
		OO_CHECK(task->completedAfterPerform);
		OO_CHECK(task->completedOnCallingThread);
		manager->completePendingTasks();
		OO_CHECK_EQ(task->completions.load(), 1);	// completed once only
	}
}


OO_TEST(completePendingTasksCollectsReadyTasks)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		const oo::Ref<TestTask> task = oo::makeRef<TestTask>();
		OO_CHECK_EQ(task->retainCount(), 1u);
		OO_CHECK(manager->addTask(task.get(), kOOAsyncPriorityHigh));
		OO_CHECK(WaitFor(task->performed));
		// Performed, but completed only when collected: poll until it is ready.
		for (int i = 0; i < 500 && task->completions == 0; i++)
		{
			manager->completePendingTasks();
			if (task->completions == 0)  std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
		OO_CHECK_EQ(task->completions.load(), 1);
		OO_CHECK(task->completedOnCallingThread);
		manager->waitForTaskToComplete(task.get());	// no longer pending: returns at once
		OO_CHECK_EQ(task->completions.load(), 1);
	}
}


OO_TEST(waitForATaskNeverAddedReturns)
{
	{
		const oo::Ref<TestTask> task = oo::makeRef<TestTask>();
		OOAsyncWorkManager::sharedAsyncWorkManager()->waitForTaskToComplete(task.get());
		OO_CHECK(!task->performed);
		OO_CHECK_EQ(task->completions.load(), 0);
	}
}


OO_TEST(taskWithoutCompletionIsPerformed)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		const oo::Ref<TestFireAndForgetTask> task = oo::makeRef<TestFireAndForgetTask>();
		OO_CHECK(manager->addTask(task.get(), kOOAsyncPriorityLow));
		OO_CHECK(WaitFor(task->performed));
		manager->completePendingTasks();	// nothing to collect for it; must not hang
	}
}


OO_TEST(exceptionInPerformIsSwallowed)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		const oo::Ref<TestTask> task = oo::makeRef<TestTask>();
		task->shouldThrow = true;
		OO_CHECK(manager->addTask(task.get(), kOOAsyncPriorityMedium));
		manager->waitForTaskToComplete(task.get());
		OO_CHECK(task->performed);
		OO_CHECK_EQ(task->completions.load(), 1);
	}
}


OO_TEST(everyPriorityIsPerformed)
{
	{
		OOAsyncWorkManager *manager = OOAsyncWorkManager::sharedAsyncWorkManager();
		const oo::Ref<TestTask> low = oo::makeRef<TestTask>();
		const oo::Ref<TestTask> medium = oo::makeRef<TestTask>();
		const oo::Ref<TestTask> high = oo::makeRef<TestTask>();
		OO_CHECK(manager->addTask(low.get(), kOOAsyncPriorityLow));
		OO_CHECK(manager->addTask(medium.get(), kOOAsyncPriorityMedium));
		OO_CHECK(manager->addTask(high.get(), kOOAsyncPriorityHigh));
		manager->waitForTaskToComplete(low.get());
		manager->waitForTaskToComplete(medium.get());
		manager->waitForTaskToComplete(high.get());
		OO_CHECK(low->completions == 1 && medium->completions == 1 && high->completions == 1);
	}
}


OO_TEST_MAIN()
