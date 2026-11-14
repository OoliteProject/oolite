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

No caller: the ships and stations hold their sets as oo::WeakSet<Entity>
(oofnd/WeakSet.hpp). It stays, built and tested by test_OOWeakSet, until it is deleted with
OOWeakReference.


Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#ifndef OOWEAKSET_H
#define OOWEAKSET_H

#import "OOFoundation.h"
#import "OOWeakReference.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

/*	The members are Objective-C objects conforming to OOWeakReferenceSupport (id). The set holds
        their weak references' facades, which are the references (ADR-0056 amendment oo-3kqi).
*/
class OOWeakSet : public oo::RefCounted {
public:
    explicit OOWeakSet(NSUInteger capacity = 0); // As with Foundation collections, capacity is only a hint.
    ~OOWeakSet() override;

    static oo::Ref<OOWeakSet> set();
    static oo::Ref<OOWeakSet> setWithCapacity(NSUInteger capacity);

    NSUInteger count();
    bool containsObject(id object);
    std::vector<oo::ObjCRef<id>> objectEnumerator(); // a snapshot of the live objects, for C++ iteration

    void addObject(id object); // Unlike a Foundation set, adding nil fails silently.
    void removeObject(id object); // Like a Foundation set, does not complain if object is not already a member.

    void makeObjectsPerformSelector(SEL selector);
    void makeObjectsPerformSelector(SEL selector, id argument);

    std::vector<oo::ObjCRef<id>> allObjects(); // the live objects, in the set's order

    void removeAllObjects();

    // -copyWithZone: (and -mutableCopyWithZone:, which was the same): a new set of the live members.
    oo::Ref<OOWeakSet> copyWithZone(OOZone* zone);
    bool isEqual(OOWeakSet* other); // the same live members; false for null

    // What "%@" prints: <OOWeakSet 0x...>{each member's short description}.
    std::optional<std::string> description();

private:
    void compact(); // Remove any zeroed entries.

    std::vector<oo::ObjCRef<::OOWeakReference*>> _objects = { }; // each once (identity), in insertion order; ::OOWeakReference is the facade
};

#endif // OOWEAKSET_H
