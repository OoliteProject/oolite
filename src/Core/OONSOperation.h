/*	NSOperationQueue was introduced in Mac OS X 10.5 and GNUstep 0.19.x
	(the current unstable series at the time of writing).
	
	This header helps us use it if it's available at runtime without requiring
	it (see OOTextureLoadOperationQueueDispatcher).
	-- Ahruman 2009-09-04
*/


#ifndef OO_HAVE_NSOPERATION
	#if OOLITE_MAC_OS_X
		#define OO_HAVE_NSOPERATION OOLITE_LEOPARD
	#elif OOLITE_GNUSTEP
		#if __NSOperation_h_GNUSTEP_BASE_INCLUDE
			#if OS_API_VERSION(100500, GS_API_LATEST)
				#define OO_HAVE_NSOPERATION 1
			#endif
		#endif
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

- (OOInteger) queuePriority;
- (void) setQueuePriority:(OOInteger)p;

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

- (OOInteger) maxConcurrentOperationCount;
- (void) setMaxConcurrentOperationCount:(OOInteger)cnt;

- (void) setSuspended:(BOOL)b;
- (BOOL) isSuspended;

- (void) cancelAllOperations;

- (void) waitUntilAllOperationsAreFinished;

@end

#else

#define OONSOperationQueue				NSOperationQueue
#define OONSOperation					NSOperation
#define OONSInvocationOperation			NSInvocationOperation

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
