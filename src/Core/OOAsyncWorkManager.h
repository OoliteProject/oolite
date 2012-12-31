/*

OOAsyncWorkManager.h

Simple thread pool/work unit manager.


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

#import "OOCocoa.h"


@class OOAsyncQueue;

@protocol OOAsyncWorkTask;


typedef enum
{
	kOOAsyncPriorityLow,
	kOOAsyncPriorityMedium,
	kOOAsyncPriorityHigh
} OOAsyncWorkPriority;


@interface OOAsyncWorkManager: NSObject

+ (OOAsyncWorkManager *) sharedAsyncWorkManager;

- (BOOL) addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority;

/*	Complete any tasks whose asynchronous portion is ready, but without waiting.
*/
- (void) completePendingTasks;

/*	Wait for a task to complete.
	
	WARNING: if task is not an existing task, or does not implement
	-completeAsyncTask, this will never return.
	
	IMPORTANT: May only be called on the main thread.
*/
- (void) waitForTaskToComplete:(id<OOAsyncWorkTask>)task;

@end


@protocol OOAsyncWorkTask <NSObject>

// Called on a worker thread. There may be multiple worker threads.
- (void) performAsyncTask;

// @optional
OOLITE_OPTIONAL(OOAsyncWorkTask)

/*	Called on main thread some time after -performAsyncTask completes.
*/
- (void) completeAsyncTask;

@end
