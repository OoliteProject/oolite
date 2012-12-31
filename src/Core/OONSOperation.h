/*
 
NSOperationQueue was introduced in Mac OS X 10.5 and GNUstep 0.19.x.

This header helps us use it if it's available at runtime without requiring
it (see OOAsyncWorkManager.m).
-- Ahruman 2009-09-04


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


#ifndef OO_HAVE_NSOPERATION
	#if OOLITE_MAC_OS_X
		#define OO_HAVE_NSOPERATION (1)
	#elif OOLITE_GNUSTEP
//		#define OO_HAVE_NSOPERATION OOLITE_GNUSTEP_1_20 && OS_API_VERSION(100500, GS_API_LATEST)
		// GNUstep (even current trunk - 1.21 @ 2010.06.06) only contains an
		// incomplete implementation of NSOperation. Namely, it's missing
		// NSInvocationOperation which is used in OOAsyncWorkManager.m
		#define OO_HAVE_NSOPERATION (0)
	#endif
#endif

#ifndef OO_ALLOW_NSOPERATION
#define OO_ALLOW_NSOPERATION 1
#endif


#if OO_ALLOW_NSOPERATION
#if !OO_HAVE_NSOPERATION

#import "OOFunctionAttributes.h"

#define OONSOperationQueue				id
#define OONSOperation					id
#define OONSInvocationOperation			id

/*	NOTE: if OO_HAVE_NSOPERATION, these will compile to class names, which are
	not values. If you want an actual Class object, use [OONSOperationClass() class].
*/
OOINLINE Class OONSOperationQueueClass() PURE_FUNC;
OOINLINE Class OONSOperationClass() PURE_FUNC;
OOINLINE Class OONSInvocationOperationClass() PURE_FUNC;

OOINLINE Class OONSOperationQueueClass()
{
	return NSClassFromString(@"NSOperationQueue");
}

OOINLINE Class OONSOperationClass()
{
	return NSClassFromString(@"NSOperation");
}


OOINLINE Class OONSInvocationOperationClass()
{
	return NSClassFromString(@"NSInvocationOperation");
}


@class NSOperationQueue;
@class NSOperation;
@class NSInvocationOperation;


enum {
	OONSOperationQueuePriorityVeryLow = -8,
	OONSOperationQueuePriorityLow = -4,
	OONSOperationQueuePriorityNormal = 0,
	OONSOperationQueuePriorityHigh = 4,
	OONSOperationQueuePriorityVeryHigh = 8
};


/*	These classes are (deliberately) not implemented. Their declarations exist
	only so that the type system will know about the methods when they're used
	on id variables.
*/

@interface OONSOperationProto

- (void) start;
- (void) main;

- (BOOL) isCancelled;
- (void) cancel;

- (BOOL) isExecuting;
- (BOOL) isFinished;

- (BOOL) isConcurrent;

- (BOOL) isReady;

- (void) addDependency:(NSOperation *)op;
- (void) removeDependency:(NSOperation *)op;

- (NSArray *) dependencies;

- (NSInteger) queuePriority;
- (void) setQueuePriority:(NSInteger)p;

@end


@interface OONSInvocationOperationProto

- (id) initWithTarget:(id)target selector:(SEL)sel object:(id)arg;
- (id) initWithInvocation:(NSInvocation *)inv;

- (NSInvocation *) invocation;

- (id) result;

@end


@interface OONSOperationQueueProto

- (void) addOperation:(NSOperation *)op;

- (NSArray *) operations;

- (NSInteger) maxConcurrentOperationCount;
- (void) setMaxConcurrentOperationCount:(NSInteger)cnt;

- (void) setSuspended:(BOOL)b;
- (BOOL) isSuspended;

- (void) cancelAllOperations;

- (void) waitUntilAllOperationsAreFinished;

@end

#else

#define OONSOperationQueue				NSOperationQueue *
#define OONSOperation					NSOperation *
#define OONSInvocationOperation			NSInvocationOperation *

#define OONSOperationQueueClass()		NSOperationQueue
#define OONSOperationClass()			NSOperation
#define OONSInvocationOperationClass()  NSInvocationOperation


enum {
	OONSOperationQueuePriorityVeryLow = NSOperationQueuePriorityVeryLow,
	OONSOperationQueuePriorityLow = NSOperationQueuePriorityLow,
	OONSOperationQueuePriorityNormal = NSOperationQueuePriorityNormal,
	OONSOperationQueuePriorityHigh = NSOperationQueuePriorityHigh,
	OONSOperationQueuePriorityVeryHigh = NSOperationQueuePriorityVeryHigh
};

#endif
#endif
