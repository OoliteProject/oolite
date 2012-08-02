/*

OOAsyncQueue.m
By Jens Ayton


Copyright (C) 2007-2012 Jens Ayton

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
#import "NSThreadOOExtensions.h"
#include <stdlib.h>


enum
{
	kConditionNoData		= 1,
	kConditionQueuedData,
	kConditionDead
};


enum
{
	kMaxPoolElements		= 5
};


typedef struct OOAsyncQueueElement OOAsyncQueueElement;
struct OOAsyncQueueElement
{
	OOAsyncQueueElement	*next;
	id					object;
};


OOINLINE OOAsyncQueueElement *AllocElement(void)
{
	return malloc(sizeof (OOAsyncQueueElement));
}


OOINLINE void FreeElement(OOAsyncQueueElement *element)
{
	free(element);
}


@interface OOAsyncQueue (OOPrivate)

- (void)doEmptyQueueWithAcquiredLock;
- (id)doDequeAndUnlockWithAcquiredLock;
- (void)recycleElementWithAcquiredLock:(OOAsyncQueueElement *)element;

@end


@implementation OOAsyncQueue

- (id)init
{
	self = [super init];
	if (self != nil)
	{
		_lock = [[NSConditionLock alloc] initWithCondition:kConditionNoData];
		[_lock setName:@"OOAsyncQueue lock"];
		if (_lock == nil)
		{
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void)dealloc
{
	OOAsyncQueueElement		*element = NULL;
	
	[_lock lock];
	
	if (_elemCount != 0)
	{
		OOLogWARN(@"asyncQueue.nonEmpty", @"%@ deallocated while non-empty, flushing.", self);
		[self doEmptyQueueWithAcquiredLock];
	}
	
	// Free element pool.
	while (_pool != NULL)
	{
		element = _pool;
		_pool = element->next;
		free(element);
	}
	
	[_lock unlockWithCondition:kConditionDead];
	[_lock release];
	
	[super dealloc];
}


- (NSString *)description
{
	// Don't bother locking, the value would be out of date immediately anyway.
	return [NSString stringWithFormat:@"<%@ %p>{%u elements}", [self class], self, _elemCount];
}


- (BOOL)enqueue:(id)object
{
	OOAsyncQueueElement		*element = NULL;
	BOOL					success = NO;
	
	if (EXPECT_NOT(object == nil))  return NO;
	
	[_lock lock];
	
	// Get an element.
	if (_pool != NULL)
	{
		element = _pool;
		_pool = element->next;
		--_poolCount;
	}
	else
	{
		element = AllocElement();
		if (element == NULL)  goto FAIL;
	}
	
	// Set element fields.
	element->object = [object retain];
	element->next = NULL;
	
	// Insert in queue.
	if (_head == NULL)
	{
		// Queue was empty, element is entire queue.
		_head = _tail = element;
		element->next = NULL;
		assert(_elemCount == 0);
		_elemCount = 1;
	}
	else
	{
		assert(_tail != NULL);
		assert(_tail->next == NULL);
		assert(_elemCount != 0);
		
		_tail->next = element;
		_tail = element;
		++_elemCount;
	}
	success = YES;
	
FAIL:
	[_lock unlockWithCondition:kConditionQueuedData];
	return success;
}


- (id)dequeue
{
	[_lock lockWhenCondition:kConditionQueuedData];
	return [self doDequeAndUnlockWithAcquiredLock];
}


- (id)tryDequeue
{
	if (![_lock tryLockWhenCondition:kConditionQueuedData])  return NO;
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
	[_lock lock];
	[self doEmptyQueueWithAcquiredLock];
	
	assert(_head == NULL && _tail == NULL && _elemCount == 0);
	[_lock unlockWithCondition:kConditionNoData];
}

@end


@implementation OOAsyncQueue (OOPrivate)

- (void)doEmptyQueueWithAcquiredLock
{
	OOAsyncQueueElement		*element = NULL;
	
	// Loop over queue.
	while (_head != NULL)
	{
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
	OOAsyncQueueElement		*element = NULL;
	id						result;
	
	if (_head == NULL)
	{
		// Can happen if you enter debugger.
		return nil;
	}
	
//	assert(_head != NULL);
	
	// Dequeue element.
	element = _head;
	_head = _head->next;
	if (_head == NULL)  _tail = NULL;
	--_elemCount;
	
	// Unpack payload.
	result = [element->object autorelease];
	
	// Recycle element.
	[self recycleElementWithAcquiredLock:element];
	
	// Ensure sane status.
	assert((_head == NULL && _tail == NULL && _elemCount == 0) || (_head != NULL && _tail != NULL && _elemCount != 0));
	
	// Unlock with appropriate state.
	[_lock unlockWithCondition:(_head == NULL) ? kConditionNoData : kConditionQueuedData];
	
	return result;
}


- (void)recycleElementWithAcquiredLock:(OOAsyncQueueElement *)element
{
	if (_poolCount < kMaxPoolElements)
	{
		// Add to pool for reuse.
		element->next = _pool;
		_pool = element;
		++_poolCount;
	}
	else
	{
		// Delete.
		FreeElement(element);
	}
}

@end
