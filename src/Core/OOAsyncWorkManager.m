/*

OOAsyncWorkManager.m


Copyright (C) 2009-2012 Jens Ayton

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
#import "NSThreadOOExtensions.h"
#import "OONSOperation.h"

#define USE_PTHREAD_ONCE (!OOLITE_WINDOWS)

#if USE_PTHREAD_ONCE
#include <pthread.h>
#endif


static OOAsyncWorkManager *sSingleton = nil;


@interface NSThread (MethodsThatMayExistDependingOnSystem)

- (BOOL) isMainThread;
+ (BOOL) isMainThread;

@end


/*	OOAsyncWorkManagerInternal: shared superclass of our two implementations,
	which implements shared functionality but is not itself concrete.
*/
@interface OOAsyncWorkManagerInternal: OOAsyncWorkManager
{
@private
	OOAsyncQueue			*_readyQueue;
	
	NSMutableSet			*_pendingCompletableOperations;
	NSLock					*_pendingOpsLock;
}

- (void) queueResult:(id<OOAsyncWorkTask>)task;

- (void) noteTaskQueued:(id<OOAsyncWorkTask>)task;

@end


#if !OO_HAVE_NSOPERATION
@interface OOManualDispatchAsyncWorkManager: OOAsyncWorkManagerInternal
{
@private
	OOAsyncQueue			*_taskQueue;
}

- (void) queueTask:(NSNumber *)threadNumber;

@end
#endif


@interface OOOperationQueueAsyncWorkManager: OOAsyncWorkManagerInternal
{
@private
	OONSOperationQueue		_operationQueue;
}

#if !OO_HAVE_NSOPERATION
+ (BOOL) canBeUsed;
#endif

- (void) dispatchTask:(id<OOAsyncWorkTask>)task;

@end


#if !USE_PTHREAD_ONCE
static NSLock *sInitLock = nil;
#endif


static void InitAsyncWorkManager(void)
{
	NSCAssert(sSingleton == nil, @"Async Work Manager singleton not nil in one-time init");
	
#if !OO_HAVE_NSOPERATION
	if ([OOOperationQueueAsyncWorkManager canBeUsed])
	{
		sSingleton = [[OOOperationQueueAsyncWorkManager alloc] init];
	}
	if (sSingleton == nil)
	{
		sSingleton = [[OOManualDispatchAsyncWorkManager alloc] init];
	}
#else
	sSingleton = [[OOOperationQueueAsyncWorkManager alloc] init];
#endif
	
	if (sSingleton == nil)
	{
		OOLog(@"asyncWorkManager.setUpDispatcher.failed", @"***** FATAL ERROR: could not set up async work manager!");
		exit(EXIT_FAILURE);
	}
	
	OOLog(@"asyncWorkManager.dispatchMethod", @"Selected async work manager: %@", [sSingleton class]);
}


@implementation OOAsyncWorkManager

#if !USE_PTHREAD_ONCE
+ (void) initialize
{
	if (sInitLock == nil)
	{
		sInitLock = [[NSLock alloc] init];
		NSAssert(sInitLock != nil, @"Async Work Manager init failed");
	}
}
#endif


+ (OOAsyncWorkManager *) sharedAsyncWorkManager
{
#if USE_PTHREAD_ONCE
	static pthread_once_t once = PTHREAD_ONCE_INIT;
	pthread_once(&once, InitAsyncWorkManager);
	NSAssert(sSingleton != nil, @"Async Work Manager init failed");
#else
	[sInitLock lock];
	if (sSingleton == nil)
	{
		InitAsyncWorkManager();
		NSAssert(sSingleton != nil, @"Async Work Manager init failed");
	}
	[sInitLock unlock];
#endif
	
	return sSingleton;
}


+ (id) allocWithZone:(NSZone *)inZone
{
	if (sSingleton == nil)
	{
		sSingleton = [super allocWithZone:inZone];
		return sSingleton;
	}
	return nil;
}


- (void) dealloc
{
	abort();
	[super dealloc];
}


- (oneway void) release
{}


- (id) retain
{
	return self;
}


- (OOUInteger) retainCount
{
	return UINT_MAX;
}


- (BOOL) addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
	OOLogGenericSubclassResponsibility();
	return NO;
}


- (void) completePendingTasks
{
	OOLogGenericSubclassResponsibility();
}


- (void) waitForTaskToComplete:(id<OOAsyncWorkTask>)task
{
	OOLogGenericSubclassResponsibility();
	[NSException raise:NSInternalInconsistencyException format:@"%s called.", __PRETTY_FUNCTION__];
}

@end


@implementation OOAsyncWorkManagerInternal


- (id) init
{
	if ((self = [super init]))
	{
		_readyQueue = [[OOAsyncQueue alloc] init];
		
		if (_readyQueue == nil)
		{
			[self release];
			return nil;
		}
		
		_pendingCompletableOperations = [[NSMutableSet alloc] init];
		_pendingOpsLock = [[NSLock alloc] init];
		
		if (_pendingCompletableOperations == nil || _pendingOpsLock == nil)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) completePendingTasks
{
	id next = nil;
	
	[_pendingOpsLock lock];
	for (;;)
	{
		next = [_readyQueue tryDequeue];
		if (next == nil)  break;
		
		[_pendingCompletableOperations removeObject:next];
		[next completeAsyncTask];
	}
	[_pendingOpsLock unlock];
}


- (void) waitForTaskToComplete:(id<OOAsyncWorkTask>)task
{
	if (task == nil)  return;
	
#if OO_DEBUG
	NSParameterAssert([(id)task respondsToSelector:@selector(completeAsyncTask)]);
	NSAssert1(![NSThread respondsToSelector:@selector(isMainThread)] || [[NSThread self] isMainThread], @"%s can only be called from the main thread.", __PRETTY_FUNCTION__);
#endif
	
	[_pendingOpsLock lock];
	BOOL exists = [_pendingCompletableOperations containsObject:task];
	if (exists)  [_pendingCompletableOperations removeObject:task];
	[_pendingOpsLock unlock];
	
	if (!exists)  return;
	
	id next = nil;
	do
	{
		// Dequeue a task and complete it.
		next = [_readyQueue dequeue];
		[_pendingCompletableOperations removeObject:next];
		[next completeAsyncTask];
		
	}  while (next != task);	// We don't control order, so keep looking until we get the one we care about.
}


- (void) queueResult:(id<OOAsyncWorkTask>)task
{
	if ([task respondsToSelector:@selector(completeAsyncTask)])
	{
		[_readyQueue enqueue:task];
	}
}


- (void) noteTaskQueued:(id<OOAsyncWorkTask>)task
{
	[_pendingOpsLock lock];
	[_pendingCompletableOperations addObject:task];
	[_pendingOpsLock unlock];
}

@end



/******* OOManualDispatchAsyncWorkManager - manual thread management *******/

enum
{
	kMaxWorkThreads			= 8
};


#if !OO_HAVE_NSOPERATION
@implementation OOManualDispatchAsyncWorkManager

- (id) init
{
	if ((self = [super init]))
	{
		// Set up work queue.
		_taskQueue = [[OOAsyncQueue alloc] init];
		if (_taskQueue == nil)
		{
			[self release];
			return nil;
		}
		
		// Set up loading threads.
		OOUInteger threadCount, threadNumber = 1;
#if OO_DEBUG
		threadCount = kMaxWorkThreads;
#else
		threadCount = MIN(OOCPUCount(), (unsigned)kMaxWorkThreads);
#endif
		do
		{
			[NSThread detachNewThreadSelector:@selector(queueTask:) toTarget:self withObject:[NSNumber numberWithInt:threadNumber++]];
		}  while (--threadCount > 0);
	}
	
	return self;
}


- (BOOL) addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
	if (EXPECT_NOT(task == nil))  return NO;
	
	[super noteTaskQueued:task];
	
	// Priority is ignored.
	return [_taskQueue enqueue:task];
}


- (void) queueTask:(NSNumber *)threadNumber
{
	NSAutoreleasePool			*rootPool = nil, *pool = nil;
	
	rootPool = [[NSAutoreleasePool alloc] init];
	
	[NSThread setThreadPriority:0.5];
	[NSThread ooSetCurrentThreadName:[NSString stringWithFormat:@"OOAsyncWorkManager thread %@", threadNumber]];
	
	for (;;)
	{
		pool = [[NSAutoreleasePool alloc] init];
		
		id<OOAsyncWorkTask> task = [_taskQueue dequeue];
		NS_DURING
			[task performAsyncTask];
		NS_HANDLER
		NS_ENDHANDLER
		[self queueResult:task];
		
		[pool release];
	}
	
	[rootPool release];
}

@end
#endif


/******* OOOperationQueueAsyncWorkManager - dispatch through NSOperationQueue if available *******/


@implementation OOOperationQueueAsyncWorkManager

#if !OO_HAVE_NSOPERATION
+ (BOOL) canBeUsed
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"disable-operation-queue-work-manager"])  return NO;
	return [OONSInvocationOperationClass() class] != Nil;
}
#endif


- (id) init
{
	if ((self = [super init]))
	{
		_operationQueue = [[OONSOperationQueueClass() alloc] init];
		
		if (_operationQueue == nil)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	[_operationQueue release];
	
	[super dealloc];
}


- (BOOL) addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority
{
	if (EXPECT_NOT(task == nil))  return NO;
	
	id operation = [[OONSInvocationOperationClass() alloc] initWithTarget:self selector:@selector(dispatchTask:) object:task];
	if (operation == nil)  return NO;
	
	if (priority == kOOAsyncPriorityLow)  [operation setQueuePriority:OONSOperationQueuePriorityLow];
	else if (priority == kOOAsyncPriorityHigh)  [operation setQueuePriority:OONSOperationQueuePriorityHigh];
	
	[_operationQueue addOperation:operation];
	[operation release];
	
	[super noteTaskQueued:task];
	return YES;
}


- (void) dispatchTask:(id<OOAsyncWorkTask>)task
{
	NS_DURING
		[task performAsyncTask];
	NS_HANDLER
	NS_ENDHANDLER
	[self queueResult:task];
}

@end
