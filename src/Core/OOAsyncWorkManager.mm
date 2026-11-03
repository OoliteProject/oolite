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

#import "OOAsyncWorkManager.h"
#import "OOAsyncQueue.h"
#import "OOCPUInfo.h"
#include "oofnd/Thread.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/objc/OOObjCRef.h"

// OOFoundation.h defines true/false as macros; the standard headers want the keywords (oofnd/Data.hpp).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false
#include <algorithm>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#include <vector>
#pragma pop_macro("false")
#pragma pop_macro("true")

#define USE_PTHREAD_ONCE (!OOLITE_WINDOWS)

#if USE_PTHREAD_ONCE
#include <pthread.h>
#endif
#include "oofnd/Defaults.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OORuntime.h"

namespace {

cxx::OOAsyncWorkManager* sSingleton = nullptr;

/*	OOAsyncWorkManagerInternal: shared superclass of our two implementations,
        which implements shared functionality but is not itself concrete.
*/
class OOAsyncWorkManagerInternal : public cxx::OOAsyncWorkManager {
public:
    void completePendingTasks() override;
    void waitForTaskToComplete(id task) override;

protected:
    OOAsyncWorkManagerInternal();

    void queueResult(id task);

    void noteTaskQueued(id task);

private:
    oo::Ref<OOAsyncQueue> _readyQueue = { };

    // Tasks awaiting completion, a set by identity (the task classes do not override -isEqual:).
    std::vector<oo::ObjCRef<id>> _pendingCompletableOperations = { };
    std::mutex _pendingOpsLock;
};

class OOManualDispatchAsyncWorkManager : public OOAsyncWorkManagerInternal {
public:
    OOManualDispatchAsyncWorkManager();

    bool addTask(id task, OOAsyncWorkPriority priority) override;

private:
    void queueTask(unsigned threadNumber);

    oo::Ref<OOAsyncQueue> _taskQueue = { };
};

/*	The prioritised task queue Foundation's operation queue was (bead oo-3rb.6): highest priority
        first and first-in-first-out within a priority, as the operation queue ordered operations by
        queuePriority. A queued task is retained until a work thread has dispatched it, as the
        invocation operation retained its argument.
*/
struct OOPrioritizedTaskQueue {
    std::mutex mutex;
    std::condition_variable available;
    std::deque<id> tasks[3]; // indexed by OOAsyncWorkPriority: low, medium, high
};

class OOOperationQueueAsyncWorkManager : public OOAsyncWorkManagerInternal {
public:
    OOOperationQueueAsyncWorkManager();

    static bool canBeUsed();

    bool addTask(id task, OOAsyncWorkPriority priority) override;

private:
    void workThread(unsigned threadNumber);
    void dispatchTask(id task);

    OOPrioritizedTaskQueue* _operationQueue = { };
};

} // namespace

enum {
    kMaxWorkThreads = 8
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
    for (unsigned threadNumber = 1; threadNumber <= count; threadNumber++) {
        oo::thread::detach([body, threadNumber]() {
            @autoreleasepool {
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

bool PendingContains(const std::vector<oo::ObjCRef<id>>& pending, id task)
{
    return std::find(pending.begin(), pending.end(), task) != pending.end();
}

void PendingRemove(std::vector<oo::ObjCRef<id>>& pending, id task)
{
    const auto it = std::find(pending.begin(), pending.end(), task); // removes the one entry, as the set did
    if (it != pending.end())
        pending.erase(it);
}

#if !USE_PTHREAD_ONCE
std::mutex sInitLock;
#endif

} // namespace

/*	The manager is made once, here, and its +1 is never released (ADR-0056 amendment oo-r7m0):
        the Objective-C class's +allocWithZone: refused a second instance and its -retain/-release/
        -retainCount made the one immortal, so that boilerplate is not translated. The class name is
        logged as oo::DescriptionOf([sSingleton class]) logged it.
*/
static void InitAsyncWorkManager(void)
{
    OOCAssert(sSingleton == nullptr, "Async Work Manager singleton not nil in one-time init");

    const char* className = nullptr;
    if (OOOperationQueueAsyncWorkManager::canBeUsed()) {
        sSingleton = oo::makeRef<OOOperationQueueAsyncWorkManager>().leakRef();
        className = "OOOperationQueueAsyncWorkManager";
    }
    if (sSingleton == nullptr) {
        sSingleton = oo::makeRef<OOManualDispatchAsyncWorkManager>().leakRef();
        className = "OOManualDispatchAsyncWorkManager";
    }

    if (sSingleton == nullptr) {
        OO_LOG("asyncWorkManager.setUpDispatcher.failed", "{}", "***** FATAL ERROR: could not set up async work manager!");
        exit(EXIT_FAILURE);
    }

    OO_LOG("asyncWorkManager.dispatchMethod", "Selected async work manager: {}", className);
}

namespace cxx {

OOAsyncWorkManager* OOAsyncWorkManager::sharedAsyncWorkManager()
{
#if USE_PTHREAD_ONCE
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, InitAsyncWorkManager);
    OOCAssert(sSingleton != nullptr, "Async Work Manager init failed");
#else
    sInitLock.lock();
    if (sSingleton == nullptr) {
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

bool OOAsyncWorkManager::addTask(id /*task*/, OOAsyncWorkPriority /*priority*/)
{
    OOLogGenericSubclassResponsibility();
    return false;
}

void OOAsyncWorkManager::completePendingTasks()
{
    OOLogGenericSubclassResponsibility();
}

void OOAsyncWorkManager::waitForTaskToComplete(id /*task*/)
{
    OOLogGenericSubclassResponsibility();
    [OOException raise:OOInternalInconsistencyException format:"%s called.", __PRETTY_FUNCTION__];
}

} // namespace cxx

namespace {

OOAsyncWorkManagerInternal::OOAsyncWorkManagerInternal()
{
    // (oo::makeRef cannot answer null, so -init's release-and-return-nil branch is gone.)
    _readyQueue = oo::makeRef<OOAsyncQueue>();
}

void OOAsyncWorkManagerInternal::completePendingTasks()
{
    id next = nil;

    _pendingOpsLock.lock();
    for (;;) {
        next = _readyQueue->tryDequeue();
        if (next == nil)
            break;

        PendingRemove(_pendingCompletableOperations, next);
        [next completeAsyncTask];
    }
    _pendingOpsLock.unlock();
}

void OOAsyncWorkManagerInternal::waitForTaskToComplete(id task)
{
    if (task == nil)
        return;

#if OO_DEBUG
    OOCParameterAssert([(id)task respondsToSelector:OOSelectorFromName("completeAsyncTask")]);
    OOCAssert(oo::thread::isMainThread(), "%s can only be called from the main thread.", __PRETTY_FUNCTION__);
#endif

    _pendingOpsLock.lock();
    bool exists = PendingContains(_pendingCompletableOperations, task);
    if (exists)
        PendingRemove(_pendingCompletableOperations, task);
    _pendingOpsLock.unlock();

    if (!exists)
        return;

    id next = nil;
    do {
        // Dequeue a task and complete it.
        next = _readyQueue->dequeue();
        _pendingOpsLock.lock();
        PendingRemove(_pendingCompletableOperations, next);
        _pendingOpsLock.unlock();

        [next completeAsyncTask];

    } while (next != task); // We don't control order, so keep looking until we get the one we care about.
}

void OOAsyncWorkManagerInternal::queueResult(id task)
{
    if ([task respondsToSelector:OOSelectorFromName("completeAsyncTask")]) {
        _readyQueue->enqueue(task);
    }
}

void OOAsyncWorkManagerInternal::noteTaskQueued(id task)
{
    _pendingOpsLock.lock();
    if (!PendingContains(_pendingCompletableOperations, task))
        _pendingCompletableOperations.emplace_back(task); // a set: added once
    _pendingOpsLock.unlock();
}

/******* OOManualDispatchAsyncWorkManager - manual thread management *******/

OOManualDispatchAsyncWorkManager::OOManualDispatchAsyncWorkManager()
{
    // Set up work queue. (oo::makeRef cannot answer null, so -init's failure branch is gone.)
    _taskQueue = oo::makeRef<OOAsyncQueue>();

    // Set up loading threads.
    StartWorkThreads([this](unsigned threadNumber) { queueTask(threadNumber); }, WorkThreadCount());
}

bool OOManualDispatchAsyncWorkManager::addTask(id task, OOAsyncWorkPriority /*priority*/)
{
    if (EXPECT_NOT(task == nil))
        return false;

    noteTaskQueued(task);

    // Priority is ignored.
    return _taskQueue->enqueue(task);
}

void OOManualDispatchAsyncWorkManager::queueTask(unsigned threadNumber)
{
    @autoreleasepool {
        SetUpWorkThread(threadNumber);

        for (;;) {
            @autoreleasepool {
                id<OOAsyncWorkTask> task = _taskQueue->dequeue();
                @try {
                    [task performAsyncTask];
                }
                @catch (id exception) {
                }
                queueResult(task);
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

bool OOOperationQueueAsyncWorkManager::addTask(id task, OOAsyncWorkPriority priority)
{
    if (EXPECT_NOT(task == nil))
        return false;

    unsigned index = kOOAsyncPriorityMedium;
    if (priority == kOOAsyncPriorityLow)
        index = kOOAsyncPriorityLow;
    else if (priority == kOOAsyncPriorityHigh)
        index = kOOAsyncPriorityHigh;

    {
        std::lock_guard<std::mutex> lock(_operationQueue->mutex);
        _operationQueue->tasks[index].push_back([task retain]);
    }
    _operationQueue->available.notify_one();

    noteTaskQueued(task);
    return true;
}

void OOOperationQueueAsyncWorkManager::workThread(unsigned threadNumber)
{
    SetUpWorkThread(threadNumber);

    for (;;) {
        id<OOAsyncWorkTask> task = nil;
        {
            std::unique_lock<std::mutex> lock(_operationQueue->mutex);
            while (task == nil) {
                for (int index = kOOAsyncPriorityHigh; index >= (int)kOOAsyncPriorityLow && task == nil; index--) {
                    std::deque<id>& queue = _operationQueue->tasks[index];
                    if (!queue.empty()) {
                        task = queue.front();
                        queue.pop_front();
                    }
                }
                if (task == nil)
                    _operationQueue->available.wait(lock);
            }
        }

        @autoreleasepool {
            dispatchTask(task);
        }
        [task release];
    }
}

void OOOperationQueueAsyncWorkManager::dispatchTask(id task)
{
    @try {
        [task performAsyncTask];
    }
    @catch (id exception) {
    }
    queueResult(task);
}

} // namespace
