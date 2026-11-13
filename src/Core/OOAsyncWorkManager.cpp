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

// OOFoundation.h defines true/false as macros; the standard headers want the
// keywords (oofnd/Data.hpp).
#include <algorithm>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <stop_token>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "oofnd/Defaults.hpp"
#include "oofnd/objc/OOAssert.h"

namespace {

/*	A first-in-first-out queue of tasks whose dequeue() blocks until one is
   there, holding tasks. A queued task is retained.
*/
class TaskQueue {
 public:
  bool enqueue(OOAsyncWorkTask* task)  // false if task is null
  {
    if (task == nullptr) return false;
    {
      std::lock_guard<std::mutex> lock(_mutex);
      _tasks.emplace_back(task);
    }
    _available.notify_one();
    return true;
  }

  oo::Ref<OOAsyncWorkTask> dequeue()  // blocks until the queue is non-empty
  {
    std::unique_lock<std::mutex> lock(_mutex);
    while (_tasks.empty()) _available.wait(lock);
    oo::Ref<OOAsyncWorkTask> task = std::move(_tasks.front());
    _tasks.pop_front();
    return task;
  }

  // Blocks until the queue is non-empty or stop is requested; null on stop.
  oo::Ref<OOAsyncWorkTask> dequeue(const std::stop_token& stop) {
    std::unique_lock<std::mutex> lock(_mutex);
    if (!_available.wait(lock, stop, [this] { return !_tasks.empty(); }))
      return {};
    oo::Ref<OOAsyncWorkTask> task = std::move(_tasks.front());
    _tasks.pop_front();
    return task;
  }

  oo::Ref<OOAsyncWorkTask> tryDequeue()  // null if empty
  {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_tasks.empty()) return {};
    oo::Ref<OOAsyncWorkTask> task = std::move(_tasks.front());
    _tasks.pop_front();
    return task;
  }

 private:
  std::mutex _mutex;
  std::condition_variable_any _available;
  std::deque<oo::Ref<OOAsyncWorkTask>> _tasks;
};

/*	OOAsyncWorkManagerInternal: shared superclass of our two
   implementations, which implements shared functionality but is not itself
   concrete.
*/
class OOAsyncWorkManagerInternal : public OOAsyncWorkManager {
 public:
  void completePendingTasks() override;
  void waitForTaskToComplete(OOAsyncWorkTask* task) override;
  void shutdown() noexcept override;

 protected:
  OOAsyncWorkManagerInternal();

  // The work threads, owned here and joined by shutdown().
  std::vector<std::jthread> _workers;

  void queueResult(OOAsyncWorkTask* task);

  void noteTaskQueued(OOAsyncWorkTask* task);

 private:
  TaskQueue _readyQueue;

  // Tasks awaiting completion, a set by identity (the task classes did not
  // override -isEqual:).
  std::vector<oo::Ref<OOAsyncWorkTask>> _pendingCompletableOperations = {};
  std::mutex _pendingOpsLock;
};

class OOManualDispatchAsyncWorkManager : public OOAsyncWorkManagerInternal {
 public:
  OOManualDispatchAsyncWorkManager();

  bool addTask(OOAsyncWorkTask* task, OOAsyncWorkPriority priority) override;

 private:
  void queueTask(unsigned threadNumber, const std::stop_token& stop);

  TaskQueue _taskQueue;
};

/*	The prioritised task queue Foundation's operation queue was: highest
   priority first and first-in-first-out within a priority,
   as the operation queue ordered operations by queuePriority. A queued task is
   retained until a work thread has dispatched it, as the invocation operation
   retained its argument.
*/
struct OOPrioritizedTaskQueue {
  std::mutex mutex;
  std::condition_variable_any available;
  std::deque<oo::Ref<OOAsyncWorkTask>>
      tasks[3];  // indexed by OOAsyncWorkPriority: low, medium, high
};

class OOOperationQueueAsyncWorkManager : public OOAsyncWorkManagerInternal {
 public:
  OOOperationQueueAsyncWorkManager();

  static bool canBeUsed();

  bool addTask(OOAsyncWorkTask* task, OOAsyncWorkPriority priority) override;

 private:
  void workThread(unsigned threadNumber, const std::stop_token& stop);
  void dispatchTask(OOAsyncWorkTask* task);

  OOPrioritizedTaskQueue* _operationQueue = {};
};

}  // namespace

constexpr unsigned kMaxWorkThreads = 8;

namespace {

unsigned WorkThreadCount() {
#if OO_DEBUG
  return kMaxWorkThreads;
#else
  return MIN(OOCPUCount(), static_cast<unsigned>(kMaxWorkThreads));
#endif
}

/*	Starts `count` work threads running body(threadNumber, stopToken),
   numbered from 1, as Foundation's detachNewThreadSelector:toTarget:withObject:
   did with [manager selector:threadNumber]. The threads are owned by the
   returned jthreads, which shutdown() stops and joins. The manager is never
   destroyed, so a thread needs no retain on it; the thread body opens its own
   pool.
*/
template <class Body>
std::vector<std::jthread> StartWorkThreads(Body body, unsigned count) {
  std::vector<std::jthread> workers;
  workers.reserve(count);
  for (unsigned threadNumber = 1; threadNumber <= count; threadNumber++) {
    workers.emplace_back([body, threadNumber](const std::stop_token& stop) {
      {
        oo::AutoreleaseScope pool;  // was @autoreleasepool
        body(threadNumber, stop);
      }
    });
  }
  return workers;
}

void SetUpWorkThread(unsigned threadNumber) {
  oo::thread::setCurrentPriority(0.5);
  oo::thread::setCurrentName("OOAsyncWorkManager thread " +
                             std::to_string(threadNumber));
}

bool PendingContains(const std::vector<oo::Ref<OOAsyncWorkTask>>& pending,
                     OOAsyncWorkTask* task) {
  return std::find(pending.begin(), pending.end(), task) != pending.end();
}

void PendingRemove(std::vector<oo::Ref<OOAsyncWorkTask>>& pending,
                   OOAsyncWorkTask* task) {
  const auto it = std::find(pending.begin(), pending.end(),
                            task);  // removes the one entry, as the set did
  if (it != pending.end()) pending.erase(it);
}

}  // namespace

/*	The manager is made once, here, and its +1 is never released, so the one
   instance is never destroyed.
*/
static OOAsyncWorkManager* MakeAsyncWorkManager() {
  OOAsyncWorkManager* manager = nullptr;
  std::string_view className;
  if (OOOperationQueueAsyncWorkManager::canBeUsed()) {
    manager = (*new std::shared_ptr<OOOperationQueueAsyncWorkManager>(
                   oo::makeShared<OOOperationQueueAsyncWorkManager>()))
                  .get();
    className = "OOOperationQueueAsyncWorkManager";
  }
  if (manager == nullptr) {
    manager = (*new std::shared_ptr<OOManualDispatchAsyncWorkManager>(
                   oo::makeShared<OOManualDispatchAsyncWorkManager>()))
                  .get();
    className = "OOManualDispatchAsyncWorkManager";
  }

  if (manager == nullptr) {
    OO_LOG("asyncWorkManager.setUpDispatcher.failed", "{}",
           "***** FATAL ERROR: could not set up async work manager!");
    exit(EXIT_FAILURE);
  }

  OO_LOG("asyncWorkManager.dispatchMethod", "Selected async work manager: {}",
         className);
  return manager;
}

OOAsyncWorkManager* OOAsyncWorkManager::sharedAsyncWorkManager() {
  // A function-local static is initialised once, thread-safely (what
  // the POSIX once-call and the Windows mutex did).
  static OOAsyncWorkManager* const sSingleton = MakeAsyncWorkManager();
  OOCAssert(sSingleton != nullptr, "Async Work Manager init failed");
  return sSingleton;
}

OOAsyncWorkManager::~OOAsyncWorkManager() { abort(); }

bool OOAsyncWorkManager::addTask(OOAsyncWorkTask* /*task*/,
                                 OOAsyncWorkPriority /*priority*/) {
  OOLogGenericSubclassResponsibility();
  return false;
}

void OOAsyncWorkManager::completePendingTasks() {
  OOLogGenericSubclassResponsibility();
}

void OOAsyncWorkManager::waitForTaskToComplete(OOAsyncWorkTask* /*task*/) {
  OOLogGenericSubclassResponsibility();
  OORaiseException(OOInternalInconsistencyException, "%s called.",
                   __PRETTY_FUNCTION__);
}

namespace {

OOAsyncWorkManagerInternal::OOAsyncWorkManagerInternal() {
  // (The ready queue is a member, so -init's release-and-return-nil branch is
  // gone.)
}

void OOAsyncWorkManagerInternal::shutdown() noexcept {
  for (std::jthread& worker : _workers) worker.request_stop();
  // A waiting worker wakes on its stop request (condition_variable_any with a
  // stop token); a busy one finishes its task first.
  for (std::jthread& worker : _workers)
    if (worker.joinable()) worker.join();
  _workers.clear();
}

void OOAsyncWorkManagerInternal::completePendingTasks() {
  oo::Ref<OOAsyncWorkTask> next;

  _pendingOpsLock.lock();
  for (;;) {
    next = _readyQueue.tryDequeue();
    if (next == nullptr) break;

    PendingRemove(_pendingCompletableOperations, next.get());
    next->completeAsyncTask();
  }
  _pendingOpsLock.unlock();
}

void OOAsyncWorkManagerInternal::waitForTaskToComplete(OOAsyncWorkTask* task) {
  if (task == nullptr) return;

#if OO_DEBUG
  OOCParameterAssert(task->hasCompleteAsyncTask());
  OOCAssert(oo::thread::isMainThread(),
            "%s can only be called from the main thread.", __PRETTY_FUNCTION__);
#endif

  _pendingOpsLock.lock();
  bool exists = PendingContains(_pendingCompletableOperations, task);
  if (exists) PendingRemove(_pendingCompletableOperations, task);
  _pendingOpsLock.unlock();

  if (!exists) return;

  oo::Ref<OOAsyncWorkTask> next;
  do {
    // Dequeue a task and complete it.
    next = _readyQueue.dequeue();
    _pendingOpsLock.lock();
    PendingRemove(_pendingCompletableOperations, next.get());
    _pendingOpsLock.unlock();

    next->completeAsyncTask();

  } while (next.get() != task);  // We don't control order, so keep looking
                                 // until we get the one we care about.
}

void OOAsyncWorkManagerInternal::queueResult(OOAsyncWorkTask* task) {
  if (task->hasCompleteAsyncTask()) {
    _readyQueue.enqueue(task);
  }
}

void OOAsyncWorkManagerInternal::noteTaskQueued(OOAsyncWorkTask* task) {
  _pendingOpsLock.lock();
  if (!PendingContains(_pendingCompletableOperations, task))
    _pendingCompletableOperations.emplace_back(task);  // a set: added once
  _pendingOpsLock.unlock();
}

/******* OOManualDispatchAsyncWorkManager - manual thread management *******/

OOManualDispatchAsyncWorkManager::OOManualDispatchAsyncWorkManager() {
  // (The work queue is a member, so -init's failure branch is gone.)

  // Set up loading threads.
  _workers = StartWorkThreads(
      [this](unsigned threadNumber, const std::stop_token& stop) {
        queueTask(threadNumber, stop);
      },
      WorkThreadCount());
}

bool OOManualDispatchAsyncWorkManager::addTask(
    OOAsyncWorkTask* task, OOAsyncWorkPriority /*priority*/) {
  if (EXPECT_NOT(task == nullptr)) return false;

  noteTaskQueued(task);

  // Priority is ignored.
  return _taskQueue.enqueue(task);
}

void OOManualDispatchAsyncWorkManager::queueTask(unsigned threadNumber,
                                                 const std::stop_token& stop) {
  {
    oo::AutoreleaseScope pool;  // was @autoreleasepool
    SetUpWorkThread(threadNumber);

    while (!stop.stop_requested()) {
      {
        oo::AutoreleaseScope taskPool;  // was @autoreleasepool
        const oo::Ref<OOAsyncWorkTask> task = _taskQueue.dequeue(stop);
        if (task == nullptr) break;  // stop requested
        try {
          task->performAsyncTask();
        } catch (...) {
          if (!oo::CurrentOOException()) throw;
        }  // was @catch (id exception) {}: the game's exceptions only
        queueResult(task.get());
      }
    }
  }
}

/******* OOOperationQueueAsyncWorkManager - a prioritised queue on its own work
 * threads *******/
/*	This was Foundation's operation queue; it is now an
   OOPrioritizedTaskQueue served by WorkThreadCount() detached std::threads
   The class name is kept: it is what the asyncWorkManager.dispatchMethod
   log line prints.
*/

bool OOOperationQueueAsyncWorkManager::canBeUsed() {
  return !oo::Defaults::standard().boolForKey(
      "disable-operation-queue-work-manager");
}

OOOperationQueueAsyncWorkManager::OOOperationQueueAsyncWorkManager() {
  _operationQueue = new OOPrioritizedTaskQueue;
  _workers = StartWorkThreads(
      [this](unsigned threadNumber, const std::stop_token& stop) {
        workThread(threadNumber, stop);
      },
      WorkThreadCount());
}

bool OOOperationQueueAsyncWorkManager::addTask(OOAsyncWorkTask* task,
                                               OOAsyncWorkPriority priority) {
  if (EXPECT_NOT(task == nullptr)) return false;

  unsigned index = oo::ToUnderlying(OOAsyncWorkPriority::kMedium);
  if (priority == OOAsyncWorkPriority::kLow)
    index = oo::ToUnderlying(OOAsyncWorkPriority::kLow);
  else if (priority == OOAsyncWorkPriority::kHigh)
    index = oo::ToUnderlying(OOAsyncWorkPriority::kHigh);

  {
    std::lock_guard<std::mutex> lock(_operationQueue->mutex);
    _operationQueue->tasks[index].emplace_back(task);
  }
  _operationQueue->available.notify_one();

  noteTaskQueued(task);
  return true;
}

void OOOperationQueueAsyncWorkManager::workThread(unsigned threadNumber,
                                                  const std::stop_token& stop) {
  SetUpWorkThread(threadNumber);

  while (!stop.stop_requested()) {
    oo::Ref<OOAsyncWorkTask> task;
    {
      std::unique_lock<std::mutex> lock(_operationQueue->mutex);
      while (task == nullptr && !stop.stop_requested()) {
        for (int index = oo::ToUnderlying(OOAsyncWorkPriority::kHigh);
             index >= oo::ToUnderlying(OOAsyncWorkPriority::kLow) &&
             task == nullptr;
             index--) {
          std::deque<oo::Ref<OOAsyncWorkTask>>& queue =
              _operationQueue->tasks[index];
          if (!queue.empty()) {
            task = std::move(queue.front());
            queue.pop_front();
          }
        }
        if (task == nullptr)
          _operationQueue->available.wait(lock, stop, [this] {
            return !_operationQueue->tasks[0].empty() ||
                   !_operationQueue->tasks[1].empty() ||
                   !_operationQueue->tasks[2].empty();
          });
      }
    }
    if (task == nullptr) break;  // stop requested

    {
      oo::AutoreleaseScope pool;  // was @autoreleasepool
      dispatchTask(task.get());
    }
    task = nullptr;  // the queue's retain, released after the pool as before
  }
}

void OOOperationQueueAsyncWorkManager::dispatchTask(OOAsyncWorkTask* task) {
  try {
    task->performAsyncTask();
  } catch (...) {
    if (!oo::CurrentOOException()) throw;
  }  // was @catch (id exception) {}: the game's exceptions only
  queueResult(task);
}

}  // namespace
