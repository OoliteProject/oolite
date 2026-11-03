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
#import "OOCollectionExtractors.h"
#include "oofnd/Thread.hpp"

// OOFoundation.h defines true/false as macros; the standard headers want the keywords (oofnd/Data.hpp).
#pragma push_macro("true")
#pragma push_macro("false")
#undef true
#undef false
#include <condition_variable>
#include <deque>
#include <mutex>
#include <string>
#pragma pop_macro("false")
#pragma pop_macro("true")

#define USE_PTHREAD_ONCE (!OOLITE_WINDOWS)

#if USE_PTHREAD_ONCE
#include <pthread.h>
#endif

static OOAsyncWorkManager* sSingleton = nil;

/*	OOAsyncWorkManagerInternal: shared superclass of our two implementations,
        which implements shared functionality but is not itself concrete.
*/
@interface OOAsyncWorkManagerInternal : OOAsyncWorkManager {
@private
    OOAsyncQueue* _readyQueue;

    NSMutableSet* _pendingCompletableOperations;
    std::mutex _pendingOpsLock;
}

- (void)queueResult:(id<OOAsyncWorkTask>)task;

- (void)noteTaskQueued:(id<OOAsyncWorkTask>)task;

@end

@interface OOManualDispatchAsyncWorkManager : OOAsyncWorkManagerInternal {
@private
    OOAsyncQueue* _taskQueue;
}

- (void)queueTask:(NSNumber*)threadNumber;

@end

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

@interface OOOperationQueueAsyncWorkManager : OOAsyncWorkManagerInternal {
@private
    OOPrioritizedTaskQueue* _operationQueue;
}

+ (BOOL)canBeUsed;

- (void)workThread:(NSNumber*)threadNumber;
- (void)dispatchTask:(id<OOAsyncWorkTask>)task;

@end

enum {
    kMaxWorkThreads = 8
};

static unsigned WorkThreadCount(void)
{
#if OO_DEBUG
    return kMaxWorkThreads;
#else
    return MIN(OOCPUCount(), (unsigned)kMaxWorkThreads);
#endif
}

/*	Starts `count` detached work threads running [manager selector:threadNumber], numbered from 1,
        as Foundation's detachNewThreadSelector:toTarget:withObject: did. The manager is an immortal
        singleton, so a thread needs no retain on it; the thread body opens its own pool.
*/
static void StartWorkThreads(OOAsyncWorkManager* manager, SEL selector, unsigned count)
{
    for (unsigned threadNumber = 1; threadNumber <= count; threadNumber++) {
        oo::thread::detach([manager, selector, threadNumber]() {
            @autoreleasepool {
                [manager performSelector:selector withObject:[NSNumber numberWithUnsignedInt:threadNumber]];
            }
        });
    }
}

static void SetUpWorkThread(NSNumber* threadNumber)
{
    oo::thread::setCurrentPriority(0.5);
    oo::thread::setCurrentName("OOAsyncWorkManager thread " + std::to_string([threadNumber unsignedIntValue]));
}

#if !USE_PTHREAD_ONCE
static std::mutex sInitLock;
#endif

static void InitAsyncWorkManager(void)
{
    NSCAssert(sSingleton == nil, @"Async Work Manager singleton not nil in one-time init");

    if ([OOOperationQueueAsyncWorkManager canBeUsed]) {
        sSingleton = [[OOOperationQueueAsyncWorkManager alloc] init];
    }
    if (sSingleton == nil) {
        sSingleton = [[OOManualDispatchAsyncWorkManager alloc] init];
    }

    if (sSingleton == nil) {
        OOLog(@"asyncWorkManager.setUpDispatcher.failed", @"%@", @"***** FATAL ERROR: could not set up async work manager!");
        exit(EXIT_FAILURE);
    }

    OOLog(@"asyncWorkManager.dispatchMethod", @"Selected async work manager: %@", [sSingleton class]);
}

@implementation OOAsyncWorkManager

+ (OOAsyncWorkManager*)sharedAsyncWorkManager
{
#if USE_PTHREAD_ONCE
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, InitAsyncWorkManager);
    NSAssert(sSingleton != nil, @"Async Work Manager init failed");
#else
    sInitLock.lock();
    if (sSingleton == nil) {
        InitAsyncWorkManager();
        NSAssert(sSingleton != nil, @"Async Work Manager init failed");
    }
    sInitLock.unlock();
#endif

    return sSingleton;
}

+ (id)allocWithZone:(OOZone*)inZone
{
    if (sSingleton == nil) {
        sSingleton = [super allocWithZone:inZone];
        return sSingleton;
    }
    return nil;
}

- (void)dealloc
{
    abort();
    [super dealloc];
}

- (oneway void)release
{
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return UINT_MAX;
}

- (BOOL)addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
    OOLogGenericSubclassResponsibility();
    return NO;
}

- (void)completePendingTasks
{
    OOLogGenericSubclassResponsibility();
}

- (void)waitForTaskToComplete:(id<OOAsyncWorkTask>)task
{
    OOLogGenericSubclassResponsibility();
    [NSException raise:NSInternalInconsistencyException format:@"%s called.", __PRETTY_FUNCTION__];
}

@end

@implementation OOAsyncWorkManagerInternal

- (id)init
{
    if ((self = [super init])) {
        _readyQueue = [[OOAsyncQueue alloc] init];

        if (_readyQueue == nil) {
            [self release];
            return nil;
        }

        _pendingCompletableOperations = [[NSMutableSet alloc] init];

        if (_pendingCompletableOperations == nil) {
            [self release];
            return nil;
        }
    }

    return self;
}

- (void)completePendingTasks
{
    id next = nil;

    _pendingOpsLock.lock();
    for (;;) {
        next = [_readyQueue tryDequeue];
        if (next == nil)
            break;

        [_pendingCompletableOperations removeObject:next];
        [next completeAsyncTask];
    }
    _pendingOpsLock.unlock();
}

- (void)waitForTaskToComplete:(id<OOAsyncWorkTask>)task
{
    if (task == nil)
        return;

#if OO_DEBUG
    NSParameterAssert([(id)task respondsToSelector:@selector(completeAsyncTask)]);
    NSAssert1(oo::thread::isMainThread(), @"%s can only be called from the main thread.", __PRETTY_FUNCTION__);
#endif

    _pendingOpsLock.lock();
    BOOL exists = [_pendingCompletableOperations containsObject:task];
    if (exists)
        [_pendingCompletableOperations removeObject:task];
    _pendingOpsLock.unlock();

    if (!exists)
        return;

    id next = nil;
    do {
        // Dequeue a task and complete it.
        next = [_readyQueue dequeue];
        _pendingOpsLock.lock();
        [_pendingCompletableOperations removeObject:next];
        _pendingOpsLock.unlock();

        [next completeAsyncTask];

    } while (next != task); // We don't control order, so keep looking until we get the one we care about.
}

- (void)queueResult:(id<OOAsyncWorkTask>)task
{
    if ([task respondsToSelector:@selector(completeAsyncTask)]) {
        [_readyQueue enqueue:task];
    }
}

- (void)noteTaskQueued:(id<OOAsyncWorkTask>)task
{
    _pendingOpsLock.lock();
    [_pendingCompletableOperations addObject:task];
    _pendingOpsLock.unlock();
}

@end

/******* OOManualDispatchAsyncWorkManager - manual thread management *******/

@implementation OOManualDispatchAsyncWorkManager

- (id)init
{
    if ((self = [super init])) {
        // Set up work queue.
        _taskQueue = [[OOAsyncQueue alloc] init];
        if (_taskQueue == nil) {
            [self release];
            return nil;
        }

        // Set up loading threads.
        StartWorkThreads(self, @selector(queueTask:), WorkThreadCount());
    }

    return self;
}

- (BOOL)addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
    if (EXPECT_NOT(task == nil))
        return NO;

    [super noteTaskQueued:task];

    // Priority is ignored.
    return [_taskQueue enqueue:task];
}

- (void)queueTask:(NSNumber*)threadNumber
{
    @autoreleasepool {
        SetUpWorkThread(threadNumber);

        for (;;) {
            @autoreleasepool {
                id<OOAsyncWorkTask> task = [_taskQueue dequeue];
                @try {
                    [task performAsyncTask];
                }
                @catch (id exception) {
                }
                [self queueResult:task];
            }
        }
    }
}

@end

/******* OOOperationQueueAsyncWorkManager - a prioritised queue on its own work threads *******/
/*	This was Foundation's operation queue; it is now an OOPrioritizedTaskQueue served by
        WorkThreadCount() detached std::threads (bead oo-3rb.6). The class name is kept: it is what the
        asyncWorkManager.dispatchMethod log line prints.
*/

@implementation OOOperationQueueAsyncWorkManager

+ (BOOL)canBeUsed
{
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"disable-operation-queue-work-manager"];
}

- (id)init
{
    if ((self = [super init])) {
        _operationQueue = new OOPrioritizedTaskQueue;
        StartWorkThreads(self, @selector(workThread:), WorkThreadCount());
    }

    return self;
}

- (BOOL)addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
    if (EXPECT_NOT(task == nil))
        return NO;

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

    [super noteTaskQueued:task];
    return YES;
}

- (void)workThread:(NSNumber*)threadNumber
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
            [self dispatchTask:task];
        }
        [task release];
    }
}

- (void)dispatchTask:(id<OOAsyncWorkTask>)task
{
    @try {
        [task performAsyncTask];
    }
    @catch (id exception) {
    }
    [self queueResult:task];
}

@end
