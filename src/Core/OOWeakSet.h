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

#import "OOFoundation.h"
#import "OOWeakReference.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@interface OOWeakSet : OOObject <OOCopying, OOMutableCopying> {
@private
    std::vector<oo::ObjCRef<OOWeakReference*>> _objects; // each once (identity), in insertion order
}

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity; // As with Foundation collections, capacity is only a hint.

+ (instancetype)set;
+ (instancetype)setWithCapacity:(NSUInteger)capacity;

- (NSUInteger)count;
- (BOOL)containsObject:(id<OOWeakReferenceSupport>)object;
- (id)objectEnumerator; // shared selector: an enumerator over a snapshot of the live objects
- (std::vector<oo::ObjCRef<id>>)cxx_objectEnumerator; // the same snapshot, for C++ iteration

- (void)addObject:(id<OOWeakReferenceSupport>)object; // Unlike a Foundation set, adding nil fails silently.
- (void)removeObject:(id<OOWeakReferenceSupport>)object; // Like a Foundation set, does not complain if object is not already a member.

- (void)addObjectsByEnumerating:(id)enumerator; // anything answering -nextObject

- (void)makeObjectsPerformSelector:(SEL)selector;
- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument;

- (id)allObjects; // shared selector: an immutable array of the live objects
- (std::vector<oo::ObjCRef<id>>)cxx_allObjects; // the live objects, in the set's order

- (void)removeAllObjects;

@end
