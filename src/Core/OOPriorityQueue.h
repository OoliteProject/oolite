/*

OOPriorityQueue.h

A prority queue is a collection into which objects may be inserted in any
order, but (primarily) extracted in sorted order. The order is defined by the
comparison selector specified at creation time, which is assumed to have the
same signature as a compare method used for array sorting:
- (NSComparisonResult)compare:(id)other
and must define a partial order on the objects in the priority queue. The
behaviour when provided with an inconsistent comparison method is undefined.

The implementation is the standard one, a binary heap. It is described in
detail in most algorithm textbooks.

This collection is *not* thread-safe.


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

#import "OOCocoa.h"


@interface OOPriorityQueue: NSObject <NSCopying>
{
@private
	SEL						_comparator;
	id						*_heap;
	NSUInteger				_count,
							_capacity;
}

// Note: -init is equivalent to -initWithComparator:@selector(compare:)
+ (instancetype) queueWithComparator:(SEL)comparator;
- (id) initWithComparator:(SEL)comparator;

- (void) addObject:(id)object;			// May throw NSInvalidArgumentException or NSMallocException.
- (void) removeObject:(id)object;		// Uses comparator (looking for NSOrderedEqual) to find object. Note: relatively expensive.
- (void) removeExactObject:(id)object;	// Uses pointer comparison to find object. Note: still relatively expensive.

- (NSUInteger) count;

- (id) nextObject;
- (id) peekAtNextObject;				// Returns next object without removing it.
- (void) removeNextObject;

- (void) addObjects:(id)collection;		// collection must respond to -nextObject, or implement -objectEnumerator to return something that implements -nextObject -- such as an NSEnumerator.

- (NSArray *) sortedObjects;			// Returns the objects in -nextObject order and empties the heap. To get the objects without emptying the heap, copy the priority queue first.
- (NSEnumerator *) objectEnumerator;	// Enumerator which pulls objects off the heap until it's empty. Note however that the queue itself behaves like an enumerator, as -nextObject has similar semantics (except that the enumerator's -nextObject can never start returning objects after it returns nil).

@end
