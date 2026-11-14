/*

OOAsyncQueue.m
By Jens Ayton


Copyright (C) 2007-2013 Jens Ayton

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

#include <assert.h>

#import "OOAsyncQueue.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"
#import "OOStringBridge.h"
#include <stdlib.h>

#import "OOFoundationBridge.h"
#include "oofnd/String.hpp"

#ifndef OO_BUGGY_PTHREADS
#if OOLITE_WINDOWS
// Maybe add #if OOLITE_64_BIT too?
#define OO_BUGGY_PTHREADS 1
#else
#define OO_BUGGY_PTHREADS 0
#endif
#endif

/*	The queue's state, as the Foundation condition lock's condition value was (bead oo-3rb.7).
        _lock guards it; whoever changes it broadcasts _conditionChanged before unlocking, as
        -unlockWithCondition: did, and a waiter for a value loops on the broadcast, as
        -lockWhenCondition: did. A plain unlock leaves the value and wakes nobody, as -unlock did.
*/
enum {
    kConditionNoData = 1,
    kConditionQueuedData,
    kConditionDead
};

enum {
    kMaxPoolElements = 5
};

typedef struct OOAsyncQueueElement OOAsyncQueueElement;
struct OOAsyncQueueElement {
    OOAsyncQueueElement* next;
    id object;
};

OOINLINE OOAsyncQueueElement* AllocElement(void)
{
    return (OOAsyncQueueElement*)malloc(sizeof(OOAsyncQueueElement));
}

OOINLINE void FreeElement(OOAsyncQueueElement* element)
{
    free(element);
}

@interface OOAsyncQueue (OOPrivate)

- (void)doEmptyQueueWithAcquiredLock;
- (id)doDequeAndUnlockWithAcquiredLock;
- (void)recycleElementWithAcquiredLock:(OOAsyncQueueElement*)element;

@end

@implementation OOAsyncQueue

- (id)init
{
    self = [super init];
    if (self != nil) {
        _condition = kConditionNoData;
    }

    return self;
}

- (void)dealloc
{
    OOAsyncQueueElement* element = NULL;

    _lock.lock();

    if (_elemCount != 0) {
        OO_LOG_WARN("asyncQueue.nonEmpty", "{} deallocated while non-empty, flushing.", oo::DescriptionOf(self));
        [self doEmptyQueueWithAcquiredLock];
    }

    // Free element pool.
    while (_pool != NULL) {
        element = _pool;
        _pool = element->next;
        free(element);
    }

    _condition = kConditionDead;
    _conditionChanged.notify_all();
    _lock.unlock();

    [super dealloc];
}

// OOObject's -description wraps this as "<OOAsyncQueue 0x...>{n elements}", which is what this
// class's own -description printed.
- (id)descriptionComponents
{
    // Don't bother locking, the value would be out of date immediately anyway.
    return oo::NSStringFrom(oo::str::format("%u elements", _elemCount));
}

- (BOOL)enqueue:(id)object
{
    OOAsyncQueueElement* element = NULL;
    BOOL success = NO;

    if (EXPECT_NOT(object == nil))
        return NO;

    _lock.lock();

    // Get an element.
    if (_pool != NULL) {
        element = _pool;
        _pool = element->next;
        --_poolCount;
    } else {
        element = AllocElement();
        if (element == NULL)
            goto FAIL;
    }

    // Set element fields.
    element->object = [object retain];
    element->next = NULL;

    // Insert in queue.
    if (_head == NULL) {
        // Queue was empty, element is entire queue.
        _head = _tail = element;
        element->next = NULL;
        assert(_elemCount == 0);
        _elemCount = 1;
    } else {
        assert(_tail != NULL);
        assert(_tail->next == NULL);
        assert(_elemCount != 0);

        _tail->next = element;
        _tail = element;
        ++_elemCount;
    }
    success = YES;

FAIL:
    _condition = kConditionQueuedData;
    _conditionChanged.notify_all();
    _lock.unlock();
    return success;
}

- (id)dequeue
{
    std::unique_lock<std::mutex> lock(_lock);
    while (_condition != kConditionQueuedData)
        _conditionChanged.wait(lock);
    lock.release(); // Held until -doDequeAndUnlockWithAcquiredLock, as before.
    return [self doDequeAndUnlockWithAcquiredLock];
}

- (id)tryDequeue
{
#if OO_BUGGY_PTHREADS
    /* pthread_mutex_trylock is buggy on 64-bit windows with the pthread
     * library in use, so avoid doing things which use it This is a little
     * more blocking, but no thread should be hanging on to _lock for very
     * long, so hopefully it won't be noticeable.
     */
    _lock.lock();
    if (_condition != kConditionQueuedData) {
        _lock.unlock();
        return nil;
    }
#else
    // Mac and Linux can do it properly
    if (!_lock.try_lock())
        return nil;
    if (_condition != kConditionQueuedData) {
        _lock.unlock();
        return nil;
    }
#endif
    return [self doDequeAndUnlockWithAcquiredLock];
}

- (BOOL)empty
{
    return _head != NULL;
}

- (unsigned)count
{
    return _elemCount;
}

- (void)emptyQueue
{
    _lock.lock();
    [self doEmptyQueueWithAcquiredLock];

    assert(_head == NULL && _tail == NULL && _elemCount == 0);
    _condition = kConditionNoData;
    _conditionChanged.notify_all();
    _lock.unlock();
}

@end

@implementation OOAsyncQueue (OOPrivate)

- (void)doEmptyQueueWithAcquiredLock
{
    OOAsyncQueueElement* element = NULL;

    // Loop over queue.
    while (_head != NULL) {
        // Dequeue element.
        element = _head;
        _head = _head->next;
        --_elemCount;

        // We don't need the payload any longer.
        [element->object release];

        // Or the element.
        [self recycleElementWithAcquiredLock:element];
    }

    _tail = NULL;
}

- (id)doDequeAndUnlockWithAcquiredLock
{
    OOAsyncQueueElement* element = NULL;
    id result;

    if (_head == NULL) {
        // Can happen if you enter debugger.
        return nil;
    }

    //	assert(_head != NULL);

    // Dequeue element.
    element = _head;
    _head = _head->next;
    if (_head == NULL)
        _tail = NULL;
    --_elemCount;

    // Unpack payload.
    result = [element->object autorelease];

    // Recycle element.
    [self recycleElementWithAcquiredLock:element];

    // Ensure sane status.
    assert((_head == NULL && _tail == NULL && _elemCount == 0) || (_head != NULL && _tail != NULL && _elemCount != 0));

    // Unlock with appropriate state.
    _condition = (_head == NULL) ? kConditionNoData : kConditionQueuedData;
    _conditionChanged.notify_all();
    _lock.unlock();

    return result;
}

- (void)recycleElementWithAcquiredLock:(OOAsyncQueueElement*)element
{
    if (_poolCount < kMaxPoolElements) {
        // Add to pool for reuse.
        element->next = _pool;
        _pool = element;
        ++_poolCount;
    } else {
        // Delete.
        FreeElement(element);
    }
}

@end
