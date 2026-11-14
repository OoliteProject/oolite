/*

OOWeakSet+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-cc8a): the Objective-C OOWeakSet, a facade over the C++
cxx::OOWeakSet (OOWeakSet.h), for callers that are not converted yet (ShipEntity,
StationEntity). Its interface is the one OOWeakSet.h declared before the conversion, copied
exactly but for the one ivar, so those callers compile and behave unchanged; each method
forwards to its C++ member. Imported as the last line of OOWeakSet.h; do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOWeakSet * (this facade)       nothing: messages as before
        converted (C++), whose members are     oo::Ref<cxx::OOWeakSet>         oo::ToObjC(set)
          still Objective-C                                                    oo::ToCxx(objcSet)
        converted (C++), whose members are C++ oo::WeakSet<T> (oofnd/WeakSet.hpp): not this class

oo::ToObjC gives the set's one live facade (oo::ObjCPeers), so identity survives a round trip.
A facade made with +alloc and -init... is recorded as its set's facade at once. Never add to
this file. Deleted by its deletion bead once no file outside OOWeakSet.* names the Objective-C
OOWeakSet.

Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#ifndef OOWEAKSET_OBJCBRIDGE_H
#define OOWEAKSET_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "OOWeakReference.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@interface OOWeakSet : OOObject <OOCopying, OOMutableCopying> {
@private
    oo::Ref<cxx::OOWeakSet> _cxxWeakSet;
}

- (id)init;
- (id)initWithCapacity:(NSUInteger)capacity; // As with Foundation collections, capacity is only a hint.

+ (instancetype)set;
+ (instancetype)setWithCapacity:(NSUInteger)capacity;

- (NSUInteger)count;
- (BOOL)containsObject:(id<OOWeakReferenceSupport>)object;
- (std::vector<oo::ObjCRef<id>>)cxx_objectEnumerator; // a snapshot of the live objects, for C++ iteration

- (void)addObject:(id<OOWeakReferenceSupport>)object; // Unlike a Foundation set, adding nil fails silently.
- (void)removeObject:(id<OOWeakReferenceSupport>)object; // Like a Foundation set, does not complain if object is not already a member.

- (void)makeObjectsPerformSelector:(SEL)selector;
- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument;

- (std::vector<oo::ObjCRef<id>>)cxx_allObjects; // the live objects, in the set's order

- (void)removeAllObjects;

@end

namespace oo {

// The set's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOWeakSet* ToObjC(cxx::OOWeakSet* set);
inline OOWeakSet* ToObjC(const Ref<cxx::OOWeakSet>& set) { return ToObjC(set.get()); }

// The C++ set behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOWeakSet* ToCxx(OOWeakSet* set);

} // namespace oo

#endif // OOWEAKSET_OBJCBRIDGE_H
