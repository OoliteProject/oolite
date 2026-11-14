/*

OOAsyncWorkManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-x2wy): the Objective-C OOAsyncWorkManager, a facade over
the C++ cxx::OOAsyncWorkManager (OOAsyncWorkManager.h), for callers that are not converted yet,
and the OOAsyncWorkTask protocol their task classes adopt. The interface and the protocol are the
ones OOAsyncWorkManager.h declared before the conversion, copied exactly, so those callers
compile and behave unchanged; each method forwards to its C++ member. Imported as the last line
of OOAsyncWorkManager.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOAsyncWorkManager *            nothing: messages as before
        converted (C++)                        cxx::OOAsyncWorkManager *       oo::ToObjC / oo::ToCxx

The manager is an immortal singleton, and so is its facade: +sharedAsyncWorkManager answers the
same object for the life of the process, as it did. Tasks stay Objective-C objects conforming to
OOAsyncWorkTask until their classes convert (ADR-0056 amendment oo-x2wy). Never add to this file.
Deleted by its deletion bead once no file outside OOAsyncWorkManager.* names the Objective-C
OOAsyncWorkManager or OOAsyncWorkTask.


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

#ifndef OOASYNCWORKMANAGER_OBJCBRIDGE_H
#define OOASYNCWORKMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@protocol OOAsyncWorkTask;

@interface OOAsyncWorkManager : OOObject {
@private
    oo::Ref<cxx::OOAsyncWorkManager> _cxxManager;
}

+ (OOAsyncWorkManager*)sharedAsyncWorkManager;

- (BOOL)addTask:(id<OOAsyncWorkTask>)task priority:(OOAsyncWorkPriority)priority;

/*	Complete any tasks whose asynchronous portion is ready, but without waiting.
 */
- (void)completePendingTasks;

/*	Wait for a task to complete.

        WARNING: if task is not an existing task, or does not implement
        -completeAsyncTask, this will never return.

        IMPORTANT: May only be called on the main thread.
*/
- (void)waitForTaskToComplete:(id<OOAsyncWorkTask>)task;

@end

@protocol OOAsyncWorkTask <OOObject>

// Called on a worker thread. There may be multiple worker threads.
- (void)performAsyncTask;

// @optional
OOLITE_OPTIONAL(OOAsyncWorkTask)

/*	Called on main thread some time after -performAsyncTask completes.
 */
- (void)completeAsyncTask;

@end

namespace oo {

// The manager's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOAsyncWorkManager* ToObjC(cxx::OOAsyncWorkManager* manager);

// The C++ manager behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOAsyncWorkManager* ToCxx(OOAsyncWorkManager* manager);

} // namespace oo

#endif // OOASYNCWORKMANAGER_OBJCBRIDGE_H
