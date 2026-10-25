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

#ifndef OOASYNCWORKMANAGER_H
#define OOASYNCWORKMANAGER_H

#include "OOCocoa.h"
#include "oofnd/Ref.hpp"


typedef enum
{
	kOOAsyncPriorityLow,
	kOOAsyncPriorityMedium,
	kOOAsyncPriorityHigh
} OOAsyncWorkPriority;


/*	A task: performed on a work thread by performAsyncTask(), then, if it has a completion
	(hasCompleteAsyncTask()), completed on the main thread by completeAsyncTask(). This was the
	Objective-C protocol OOAsyncWorkTask, whose -completeAsyncTask was optional; the manager's
	-respondsToSelector: test is hasCompleteAsyncTask() (bead oo-9ht.14). The manager retains a
	task while it is queued or pending, as it retained the Objective-C object.
*/
class OOAsyncWorkTask : public oo::RefCounted
{
public:
	// Called on a work thread. There may be multiple work threads.
	virtual void performAsyncTask() = 0;

	// Whether the task has a completion (the protocol's optional method was implemented).
	virtual bool hasCompleteAsyncTask() const  { return false; }

	// Called on the main thread some time after performAsyncTask() completes.
	virtual void completeAsyncTask()  {}

protected:
	OOAsyncWorkTask() = default;
	~OOAsyncWorkTask() override = default;
};


/*	The concrete managers are private to OOAsyncWorkManager.mm.
*/
class OOAsyncWorkManager : public oo::RefCounted
{
public:
	// The one manager, made on first use and never destroyed (borrowed).
	static OOAsyncWorkManager *sharedAsyncWorkManager();

	virtual bool addTask(OOAsyncWorkTask *task, OOAsyncWorkPriority priority);

	/*	Complete any tasks whose asynchronous portion is ready, but without waiting.
	*/
	virtual void completePendingTasks();

	/*	Wait for a task to complete.
		
		WARNING: if task is not an existing task, or does not implement
		completeAsyncTask(), this will never return.
		
		IMPORTANT: May only be called on the main thread.
	*/
	virtual void waitForTaskToComplete(OOAsyncWorkTask *task);

protected:
	OOAsyncWorkManager() = default;
	~OOAsyncWorkManager() override;
};

#endif	// OOASYNCWORKMANAGER_H
