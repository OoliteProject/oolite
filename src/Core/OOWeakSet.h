/*

OOWeakSet.h

A mutable set of weak references to objects conforming to OOWeakReferenceSupport.

Semantics:
 * When an object in the set is deallocated, the object is removed from the
   set and the set's count drops. There is no notification for this. As such,
   there is no such thing as an immutable weak set.
 * Objects are uniqued by pointer equality, not isEquals:.
 * OOWeakSet is not thread-safe. It not only requires that all operations on
   it happen on one thread, but also that objects it's watching are (finally)
   released on that thread.


LIMITATION: fast enumeration and Oolite's foreach() macro are not supported.


Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakReference.h"


@interface OOWeakSet: NSObject <NSCopying, NSMutableCopying>
{
@private
	NSMutableSet			*_objects;
}

- (id) init;
- (id) initWithCapacity:(NSUInteger)capacity;				// As with Foundation collections, capacity is only a hint.

+ (id) set;
+ (id) setWithCapacity:(NSUInteger)capacity;

- (NSUInteger) count;
- (BOOL) containsObject:(id<OOWeakReferenceSupport>)object;
- (NSEnumerator *) objectEnumerator;

- (void) addObject:(id<OOWeakReferenceSupport>)object;		// Unlike NSSet, adding nil fails silently.
- (void) removeObject:(id<OOWeakReferenceSupport>)object;	// Like NSSet, does not complain if object is not already a member.

- (void) addObjectsByEnumerating:(NSEnumerator *)enumerator;

- (void) makeObjectsPerformSelector:(SEL)selector;
- (void) makeObjectsPerformSelector:(SEL)selector withObject:(id)argument;

- (NSArray *) allObjects;

- (void) removeAllObjects;

@end
