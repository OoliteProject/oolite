/*

OOAsyncWorkManager.m


Copyright (C) 2009-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOAsyncWorkManager.h"
#include "OOCPUInfo.h"
#include "oofnd/Thread.hpp"
#include "oofnd/objc/OOException.h"

// OOCocoa.h defines true/false as macros; the standard headers want the keywords (oofnd/Data.hpp).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <vector>
#include <algorithm>
#pragma pop_macro("false")
#pragma pop_macro("true")

#define USE_PTHREAD_ONCE (!OOLITE_WINDOWS)

#if USE_PTHREAD_ONCE
#include <pthread.h>
#endif
#include "oofnd/objc/OOAssert.h"
#include "oofnd/Defaults.hpp"


namespace {

OOAsyncWorkManager *sSingleton = nullptr;


/*	A first-in-first-out queue of tasks whose dequeue() blocks until one is there: the part of
	OOAsyncQueue the manager used, holding tasks (bead oo-9ht.14; OOAsyncQueue holds Objective-C
	objects). A queued task is retained, as OOAsyncQueue retained it.
*/
class TaskQueue
{
public:
	bool enqueue(OOAsyncWorkTask *task)	// false if task is null
	{
		if (task == nullptr)  return false;
		{
			std::lock_guard<std::mutex> lock(_mutex);
			_tasks.emplace_back(task);
		}
		_available.notify_one();
		return true;
	}

	oo::Ref<OOAsyncWorkTask> dequeue()	// blocks until the queue is non-empty
	{
		std::unique_lock<std::mutex> lock(_mutex);
		while (_tasks.empty())  _available.wait(lock);
		oo::Ref<OOAsyncWorkTask> task = std::move(_tasks.front());
		_tasks.pop_front();
		return task;
	}

	oo::Ref<OOAsyncWorkTask> tryDequeue()	// null if empty
	{
		std::lock_guard<std::mutex> lock(_mutex);
		if (_tasks.empty())  return {};
		oo::Ref<OOAsyncWorkTask> task = std::move(_tasks.front());
		_tasks.pop_front();
		return task;
	}

private:
	std::mutex								_mutex;
	std::condition_variable					_available;
	std::deque<oo::Ref<OOAsyncWorkTask>>	_tasks;
};


/*	OOAsyncWorkManagerInternal: shared superclass of our two implementations,
	which implements shared functionality but is not itself concrete.
*/
class OOAsyncWorkManagerInternal : public OOAsyncWorkManager
{
public:
	void completePendingTasks() override;
	void waitForTaskToComplete(OOAsyncWorkTask *task) override;

protected:
	OOAsyncWorkManagerInternal();

	void queueResult(OOAsyncWorkTask *task);

	void noteTaskQueued(OOAsyncWorkTask *task);

private:
	TaskQueue				_readyQueue;

	// Tasks awaiting completion, a set by identity (the task classes did not override -isEqual:).
	std::vector<oo::Ref<OOAsyncWorkTask>>	_pendingCompletableOperations = {};
	std::mutex				_pendingOpsLock;
};


class OOManualDispatchAsyncWorkManager : public OOAsyncWorkManagerInternal
{
public:
	OOManualDispatchAsyncWorkManager();

	bool addTask(OOAsyncWorkTask *task, OOAsyncWorkPriority priority) override;

private:
	void queueTask(unsigned threadNumber);

	TaskQueue				_taskQueue;
};


/*	The prioritised task queue Foundation's operation queue was (bead oo-3rb.6): highest priority
	first and first-in-first-out within a priority, as the operation queue ordered operations by
	queuePriority. A queued task is retained until a work thread has dispatched it, as the
	invocation operation retained its argument.
*/
struct OOPrioritizedTaskQueue
{
	std::mutex				mutex;
	std::condition_variable	available;
	std::deque<oo::Ref<OOAsyncWorkTask>>	tasks[3];	// indexed by OOAsyncWorkPriority: low, medium, high
};


class OOOperationQueueAsyncWorkManager : public OOAsyncWorkManagerInternal
{
public:
	OOOperationQueueAsyncWorkManager();

	static bool canBeUsed();

	bool addTask(OOAsyncWorkTask *task, OOAsyncWorkPriority priority) override;

private:
	void workThread(unsigned threadNumber);
	void dispatchTask(OOAsyncWorkTask *task);

	OOPrioritizedTaskQueue	*_operationQueue = {};
};

}	// namespace


enum
{
	kMaxWorkThreads			= 8
};


namespace {

unsigned WorkThreadCount(void)
{
#if OO_DEBUG
	return kMaxWorkThreads;
#else
	return MIN(OOCPUCount(), (unsigned)kMaxWorkThreads);
#endif
}


/*	Starts `count` detached work threads running body(threadNumber), numbered from 1, as
	Foundation's detachNewThreadSelector:toTarget:withObject: did with [manager selector:threadNumber].
	The thread number is a plain unsigned now (proposed ADR-0043). The manager is an immortal
	singleton, so a thread needs no retain on it; the thread body opens its own pool.
*/
template <class Body>
void StartWorkThreads(Body body, unsigned count)
{
	for (unsigned threadNumber = 1; threadNumber <= count; threadNumber++)
	{
		oo::thread::detach([body, threadNumber]()
		{
			{
				oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
				body(threadNumber);
			}
		});
	}
}


void SetUpWorkThread(unsigned threadNumber)
{
	oo::thread::setCurrentPriority(0.5);
	oo::thread::setCurrentName("OOAsyncWorkManager thread " + std::to_string(threadNumber));
}


bool PendingContains(const std::vector<oo::Ref<OOAsyncWorkTask>> &pending, OOAsyncWorkTask *task)
{
	return std::find(pending.begin(), pending.end(), task) != pending.end();
}


void PendingRemove(std::vector<oo::Ref<OOAsyncWorkTask>> &pending, OOAsyncWorkTask *task)
{
	const auto it = std::find(pending.begin(), pending.end(), task);	// removes the one entry, as the set did
	if (it != pending.end())  pending.erase(it);
}


#if !USE_PTHREAD_ONCE
std::mutex sInitLock;
#endif

}	// namespace


/*	The manager is made once, here, and its +1 is never released (ADR-0056 amendment oo-r7m0):
	the Objective-C class's +allocWithZone: refused a second instance and its -retain/-release/
	-retainCount made the one immortal, so that boilerplate is not translated. The class name is
	logged as oo::DescriptionOf([sSingleton class]) logged it.
*/
static void InitAsyncWorkManager(void)
{
	OOCAssert(sSingleton == nullptr, "Async Work Manager singleton not nil in one-time init");

	const char *className = nullptr;
	if (OOOperationQueueAsyncWorkManager::canBeUsed())
	{
		sSingleton = oo::makeRef<OOOperationQueueAsyncWorkManager>().leakRef();
		className = "OOOperationQueueAsyncWorkManager";
	}
	if (sSingleton == nullptr)
	{
		sSingleton = oo::makeRef<OOManualDispatchAsyncWorkManager>().leakRef();
		className = "OOManualDispatchAsyncWorkManager";
	}

	if (sSingleton == nullptr)
	{
		OO_LOG("asyncWorkManager.setUpDispatcher.failed", "{}", "***** FATAL ERROR: could not set up async work manager!");
		exit(EXIT_FAILURE);
	}

	OO_LOG("asyncWorkManager.dispatchMethod", "Selected async work manager: {}", className);
}


OOAsyncWorkManager *OOAsyncWorkManager::sharedAsyncWorkManager()
{
#if USE_PTHREAD_ONCE
	static pthread_once_t once = PTHREAD_ONCE_INIT;
	pthread_once(&once, InitAsyncWorkManager);
	OOCAssert(sSingleton != nullptr, "Async Work Manager init failed");
#else
	sInitLock.lock();
	if (sSingleton == nullptr)
	{
		InitAsyncWorkManager();
		OOCAssert(sSingleton != nullptr, "Async Work Manager init failed");
	}
	sInitLock.unlock();
#endif

	return sSingleton;
}


OOAsyncWorkManager::~OOAsyncWorkManager()
{
	abort();
}


bool OOAsyncWorkManager::addTask(OOAsyncWorkTask * /*task*/, OOAsyncWorkPriority /*priority*/)
{
	OOLogGenericSubclassResponsibility();
	return false;
}


void OOAsyncWorkManager::completePendingTasks()
{
	OOLogGenericSubclassResponsibility();
}


void OOAsyncWorkManager::waitForTaskToComplete(OOAsyncWorkTask * /*task*/)
{
	OOLogGenericSubclassResponsibility();
	OORaiseException(OOInternalInconsistencyException, "%s called.", __PRETTY_FUNCTION__);
}


namespace {

OOAsyncWorkManagerInternal::OOAsyncWorkManagerInternal()
{
	// (The ready queue is a member, so -init's release-and-return-nil branch is gone.)
}


void OOAsyncWorkManagerInternal::completePendingTasks()
{
	oo::Ref<OOAsyncWorkTask> next;

	_pendingOpsLock.lock();
	for (;;)
	{
		next = _readyQueue.tryDequeue();
		if (next == nullptr)  break;

		PendingRemove(_pendingCompletableOperations, next.get());
		next->completeAsyncTask();
	}
	_pendingOpsLock.unlock();
}


void OOAsyncWorkManagerInternal::waitForTaskToComplete(OOAsyncWorkTask *task)
{
	if (task == nullptr)  return;

#if OO_DEBUG
	OOCParameterAssert(task->hasCompleteAsyncTask());
	OOCAssert(oo::thread::isMainThread(), "%s can only be called from the main thread.", __PRETTY_FUNCTION__);
#endif

	_pendingOpsLock.lock();
	bool exists = PendingContains(_pendingCompletableOperations, task);
	if (exists)  PendingRemove(_pendingCompletableOperations, task);
	_pendingOpsLock.unlock();

	if (!exists)  return;

	oo::Ref<OOAsyncWorkTask> next;
	do
	{
		// Dequeue a task and complete it.
		next = _readyQueue.dequeue();
		_pendingOpsLock.lock();
		PendingRemove(_pendingCompletableOperations, next.get());
		_pendingOpsLock.unlock();

		next->completeAsyncTask();

	}  while (next.get() != task);	// We don't control order, so keep looking until we get the one we care about.
}


void OOAsyncWorkManagerInternal::queueResult(OOAsyncWorkTask *task)
{
	if (task->hasCompleteAsyncTask())
	{
		_readyQueue.enqueue(task);
	}
}


void OOAsyncWorkManagerInternal::noteTaskQueued(OOAsyncWorkTask *task)
{
	_pendingOpsLock.lock();
	if (!PendingContains(_pendingCompletableOperations, task))  _pendingCompletableOperations.emplace_back(task);	// a set: added once
	_pendingOpsLock.unlock();
}



/******* OOManualDispatchAsyncWorkManager - manual thread management *******/

OOManualDispatchAsyncWorkManager::OOManualDispatchAsyncWorkManager()
{
	// (The work queue is a member, so -init's failure branch is gone.)

	// Set up loading threads.
	StartWorkThreads([this](unsigned threadNumber) { queueTask(threadNumber); }, WorkThreadCount());
}


bool OOManualDispatchAsyncWorkManager::addTask(OOAsyncWorkTask *task, OOAsyncWorkPriority /*priority*/)
{
	if (EXPECT_NOT(task == nullptr))  return false;

	noteTaskQueued(task);

	// Priority is ignored.
	return _taskQueue.enqueue(task);
}


void OOManualDispatchAsyncWorkManager::queueTask(unsigned threadNumber)
{
	{
		oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
		SetUpWorkThread(threadNumber);

		for (;;)
		{
			{
				oo::AutoreleaseScope taskPool;	// was @autoreleasepool (oo-31u.8)
				const oo::Ref<OOAsyncWorkTask> task = _taskQueue.dequeue();
				try
				{
					task->performAsyncTask();
				}
				catch (...) { if (!oo::CurrentOOException())  throw; }	// was @catch (id exception) {}: the game's exceptions only (oo::Exception since oo-rskgl.1)
				queueResult(task.get());
			}
		}
	}
}


/******* OOOperationQueueAsyncWorkManager - a prioritised queue on its own work threads *******/
/*	This was Foundation's operation queue; it is now an OOPrioritizedTaskQueue served by
	WorkThreadCount() detached std::threads (bead oo-3rb.6). The class name is kept: it is what the
	asyncWorkManager.dispatchMethod log line prints.
*/

bool OOOperationQueueAsyncWorkManager::canBeUsed()
{
	return !oo::Defaults::standard().boolForKey("disable-operation-queue-work-manager");
}


OOOperationQueueAsyncWorkManager::OOOperationQueueAsyncWorkManager()
{
	_operationQueue = new OOPrioritizedTaskQueue;
	StartWorkThreads([this](unsigned threadNumber) { workThread(threadNumber); }, WorkThreadCount());
}


bool OOOperationQueueAsyncWorkManager::addTask(OOAsyncWorkTask *task, OOAsyncWorkPriority priority)
{
	if (EXPECT_NOT(task == nullptr))  return false;

	unsigned index = kOOAsyncPriorityMedium;
	if (priority == kOOAsyncPriorityLow)  index = kOOAsyncPriorityLow;
	else if (priority == kOOAsyncPriorityHigh)  index = kOOAsyncPriorityHigh;

	{
		std::lock_guard<std::mutex> lock(_operationQueue->mutex);
		_operationQueue->tasks[index].emplace_back(task);
	}
	_operationQueue->available.notify_one();

	noteTaskQueued(task);
	return true;
}


void OOOperationQueueAsyncWorkManager::workThread(unsigned threadNumber)
{
	SetUpWorkThread(threadNumber);

	for (;;)
	{
		oo::Ref<OOAsyncWorkTask> task;
		{
			std::unique_lock<std::mutex> lock(_operationQueue->mutex);
			while (task == nullptr)
			{
				for (int index = kOOAsyncPriorityHigh; index >= (int)kOOAsyncPriorityLow && task == nullptr; index--)
				{
					std::deque<oo::Ref<OOAsyncWorkTask>> &queue = _operationQueue->tasks[index];
					if (!queue.empty())
					{
						task = std::move(queue.front());
						queue.pop_front();
					}
				}
				if (task == nullptr)  _operationQueue->available.wait(lock);
			}
		}

		{
			oo::AutoreleaseScope pool;	// was @autoreleasepool (oo-31u.8)
			dispatchTask(task.get());
		}
		task = nullptr;	// the queue's retain, released after the pool as before
	}
}


void OOOperationQueueAsyncWorkManager::dispatchTask(OOAsyncWorkTask *task)
{
	try
	{
		task->performAsyncTask();
	}
	catch (...) { if (!oo::CurrentOOException())  throw; }	// was @catch (id exception) {}: the game's exceptions only (oo::Exception since oo-rskgl.1)
	queueResult(task);
}

}	// namespace
