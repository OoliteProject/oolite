/*	test_OOAsyncWorkManager.mm
	Unit tests for cxx::OOAsyncWorkManager (src/Core/OOAsyncWorkManager.h) and its Objective-C
	facade (OOAsyncWorkManager+ObjCBridge.h): bead oo-x2wy, a Phase 3 conversion in the OOColor
	house style (proposed ADR-0056; amendment oo-x2wy for the protocol and the private subclasses).

	Pins what the manager did before the conversion, with Objective-C tasks (its callers' tasks
	are Objective-C): one shared manager; nil is refused; a task is performed on a work thread
	and then completed on the thread that waits for it or collects pending tasks; a task without
	-completeAsyncTask is performed and never collected; waiting for a task that was never added
	returns at once; an exception thrown by -performAsyncTask is swallowed and the task still
	completes; every priority is accepted and performed. The facade's contract: one immortal facade
	for the one manager, the crossings, nil stays nil, and its methods reach the same manager.
	Run: bash tools/check-core-tests.sh
*/

#import "OOAsyncWorkManager.h"

#include "oo_test.hpp"

#include <atomic>
#include <chrono>
#include <thread>


@interface TestTask: OOObject <OOAsyncWorkTask>
{
@public
	std::atomic<bool>	performed;
	std::atomic<bool>	performedOnCallingThread;
	std::atomic<int>	completions;
	bool				completedAfterPerform;
	bool				completedOnCallingThread;
	bool				shouldThrow;
	std::thread::id		callingThread;
}
@end


@implementation TestTask

- (id) init
{
	if ((self = [super init]))
	{
		callingThread = std::this_thread::get_id();
	}
	return self;
}


- (void) performAsyncTask
{
	performedOnCallingThread = (std::this_thread::get_id() == callingThread);
	performed = true;
	if (shouldThrow)  @throw [[[OOObject alloc] init] autorelease];
}


- (void) completeAsyncTask
{
	completedAfterPerform = performed;
	completedOnCallingThread = (std::this_thread::get_id() == callingThread);
	completions++;
}

@end


// A task with no -completeAsyncTask (the method is optional).
@interface TestFireAndForgetTask: OOObject <OOAsyncWorkTask>
{
@public
	std::atomic<bool>	performed;
}
@end


@implementation TestFireAndForgetTask

- (void) performAsyncTask
{
	performed = true;
}

@end


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
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(cxx::OOAsyncWorkManager::sharedAsyncWorkManager() == manager);
	}
}


OO_TEST(nilIsRefused)
{
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		OO_CHECK(!manager->addTask(nil, kOOAsyncPriorityMedium));
		manager->waitForTaskToComplete(nil);	// returns at once
	}
}


OO_TEST(waitPerformsThenCompletesOnTheWaitingThread)
{
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		TestTask *task = [[[TestTask alloc] init] autorelease];
		OO_CHECK(manager->addTask(task, kOOAsyncPriorityMedium));
		manager->waitForTaskToComplete(task);
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
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		TestTask *task = [[[TestTask alloc] init] autorelease];
		OO_CHECK_EQ([task retainCount], 1u);
		OO_CHECK(manager->addTask(task, kOOAsyncPriorityHigh));
		OO_CHECK(WaitFor(task->performed));
		// Performed, but completed only when collected: poll until it is ready.
		for (int i = 0; i < 500 && task->completions == 0; i++)
		{
			manager->completePendingTasks();
			if (task->completions == 0)  std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
		OO_CHECK_EQ(task->completions.load(), 1);
		OO_CHECK(task->completedOnCallingThread);
		manager->waitForTaskToComplete(task);	// no longer pending: returns at once
		OO_CHECK_EQ(task->completions.load(), 1);
	}
}


OO_TEST(waitForATaskNeverAddedReturns)
{
	@autoreleasepool
	{
		TestTask *task = [[[TestTask alloc] init] autorelease];
		cxx::OOAsyncWorkManager::sharedAsyncWorkManager()->waitForTaskToComplete(task);
		OO_CHECK(!task->performed);
		OO_CHECK_EQ(task->completions.load(), 0);
	}
}


OO_TEST(taskWithoutCompletionIsPerformed)
{
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		TestFireAndForgetTask *task = [[[TestFireAndForgetTask alloc] init] autorelease];
		OO_CHECK(manager->addTask(task, kOOAsyncPriorityLow));
		OO_CHECK(WaitFor(task->performed));
		manager->completePendingTasks();	// nothing to collect for it; must not hang
	}
}


OO_TEST(exceptionInPerformIsSwallowed)
{
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		TestTask *task = [[[TestTask alloc] init] autorelease];
		task->shouldThrow = true;
		OO_CHECK(manager->addTask(task, kOOAsyncPriorityMedium));
		manager->waitForTaskToComplete(task);
		OO_CHECK(task->performed);
		OO_CHECK_EQ(task->completions.load(), 1);
	}
}


OO_TEST(everyPriorityIsPerformed)
{
	@autoreleasepool
	{
		cxx::OOAsyncWorkManager *manager = cxx::OOAsyncWorkManager::sharedAsyncWorkManager();
		TestTask *low = [[[TestTask alloc] init] autorelease];
		TestTask *medium = [[[TestTask alloc] init] autorelease];
		TestTask *high = [[[TestTask alloc] init] autorelease];
		OO_CHECK(manager->addTask(low, kOOAsyncPriorityLow));
		OO_CHECK(manager->addTask(medium, kOOAsyncPriorityMedium));
		OO_CHECK(manager->addTask(high, kOOAsyncPriorityHigh));
		manager->waitForTaskToComplete(low);
		manager->waitForTaskToComplete(medium);
		manager->waitForTaskToComplete(high);
		OO_CHECK(low->completions == 1 && medium->completions == 1 && high->completions == 1);
	}
}


OO_TEST(facadeIsTheSharedManager)
{
	@autoreleasepool
	{
		OOAsyncWorkManager *facade = [OOAsyncWorkManager sharedAsyncWorkManager];
		OO_CHECK(facade != nil);
		OO_CHECK([OOAsyncWorkManager sharedAsyncWorkManager] == facade);
		OO_CHECK(oo::ToCxx(facade) == cxx::OOAsyncWorkManager::sharedAsyncWorkManager());
		OO_CHECK(oo::ToObjC(cxx::OOAsyncWorkManager::sharedAsyncWorkManager()) == facade);
	}
	@autoreleasepool
	{
		// Kept across pools, as the immortal singleton was.
		OO_CHECK(oo::ToObjC(cxx::OOAsyncWorkManager::sharedAsyncWorkManager()) == [OOAsyncWorkManager sharedAsyncWorkManager]);
	}
}


OO_TEST(facadeNilStaysNil)
{
	OOAsyncWorkManager *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOAsyncWorkManager *>(nullptr)) == nil);
	OO_CHECK(![none addTask:nil priority:kOOAsyncPriorityMedium]);
}


OO_TEST(facadeForwards)
{
	@autoreleasepool
	{
		OOAsyncWorkManager *facade = [OOAsyncWorkManager sharedAsyncWorkManager];
		OO_CHECK(![facade addTask:nil priority:kOOAsyncPriorityMedium]);
		TestTask *task = [[[TestTask alloc] init] autorelease];
		OO_CHECK([facade addTask:task priority:kOOAsyncPriorityMedium]);
		[facade waitForTaskToComplete:task];
		OO_CHECK(task->performed);
		OO_CHECK_EQ(task->completions.load(), 1);
		[facade completePendingTasks];
		OO_CHECK_EQ(task->completions.load(), 1);
	}
}


OO_TEST_MAIN()
