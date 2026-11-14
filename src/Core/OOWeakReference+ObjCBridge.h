/*

OOWeakReference+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-3kqi): the Objective-C OOWeakReference, a facade over
the C++ cxx::OOWeakReference (OOWeakReference.h), with the OOWeakReferenceSupport protocol and
OOWeakRefObject, for the Objective-C code that holds objects weakly. The interfaces are the ones
OOWeakReference.h declared before the conversion, copied exactly but for the facade's one ivar;
each facade method forwards to its C++ member. Imported as the last line of OOWeakReference.h;
do not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      OOWeakReference * (the facade)  nothing: messages as before
        converted (C++), holding an            oo::ObjCRef<OOWeakReference *>  oo::ToCxx(ref)->member()
          Objective-C object weakly
        converted (C++), holding a C++ object  oo::WeakRef<T> (oofnd/Ref.hpp)  not this class at all

The facade is the reference's identity (ADR-0056 amendment oo-3kqi): its callers compare it
(weakRef == weakSelf), hash it and keep it in sets, and the referred object keeps an unretained
pointer to it (weakSelf). So the facade makes and owns its C++ object, as a facade over a subclass
of an Objective-C class does (amendment oo-o89): oo::ToObjC answers the live facade or nil and
never makes one, and converted code holds the facade, never the C++ object alone. The protocol,
OOWeakRefObject (whose one subclass left is the root Entity facade) and
the OOObject category stay Objective-C here until the classes that use them are converted; then
they and this file go, and oo::WeakRef replaces them. Never add to this file.


Weak reference class for Cocoa/GNUstep/OpenStep. The usage notes before the conversion: -weakRetain
gave a retained proxy that forwarded messages while the object lived and acted like nil once it had
gone (use -weakRefUnderlyingObject, the object or nil, for floating-point or struct results); a
supporting class kept an unretained weakSelf, cleared it in -weakRefDied: and sent -weakRefDrop
from -dealloc. Nothing outside the root Entity facade and what reads its weak references uses
this (deleting that facade deletes them): a C++ object is held with oo::WeakRef
(oofnd/Ref.hpp, whose banner maps each idiom) and a weak set is an oo::WeakSet (oofnd/WeakSet.hpp).


Copyright (C) 2007-2013 Jens Ayton
This code is hereby placed in the public domain.

*/

#ifndef OOWEAKREFERENCE_OBJCBRIDGE_H
#define OOWEAKREFERENCE_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "OOFunctionAttributes.h"
#import "oofnd/objc/OOObject.h"

@class OOWeakReference;

@protocol OOWeakReferenceSupport <OOObject>

- (id)weakRetain OO_RETURNS_RETAINED; // Returns a retained OOWeakReference, which should be released when finished with.
- (void)weakRefDied:(OOWeakReference*)weakRef;

@end

@interface OOWeakReference : OOObject // forwards with -forwardingTargetForSelector: (bead oo-3rb.54)
{
@private
    oo::Ref<cxx::OOWeakReference> _cxxWeakReference;
}

- (id)weakRefUnderlyingObject;

- (id)weakRetain OO_RETURNS_RETAINED; // Returns [self retain] for weakrefs.

// For referred object only:
+ (id)weakRefWithObject:(id<OOWeakReferenceSupport>)object;
- (void)weakRefDrop;

@end

@interface OOObject (OOWeakReference)

- (id)weakRefUnderlyingObject; // Always self for non-weakrefs (and of course nil for nil).

@end

/*	OOWeakRefObject
        Simple object implementing OOWeakReferenceSupport, to subclass. This
        provides a full implementation for simplicity, but keep in mind that the
        protocol can be implemented by any class.
*/
@interface OOWeakRefObject : OOObject <OOWeakReferenceSupport> {
    OOWeakReference* weakSelf;
}

- (id)weakSelf; // Equivalent to [[self weakRetain] autorelease]

@end

/*	Private to OOWeakReference.mm and OOWeakReference+ObjCBridge.mm (it was private to
        OOWeakReference.mm): what a dead reference forwards to, answering every message with 0.
*/
@interface OOWeakReferenceNilTarget : OOObject

+ (id)sharedNilTarget;

@end

namespace oo {

// The reference's Objective-C facade, which made it, while that facade lives; else nil (never a
// new facade: the facade is the reference). Autoreleased. nil for null.
OOWeakReference* ToObjC(cxx::OOWeakReference* weakRef);
inline OOWeakReference* ToObjC(const Ref<cxx::OOWeakReference>& weakRef) { return ToObjC(weakRef.get()); }

// The C++ reference behind a facade, borrowed (the facade owns it); null for nil.
cxx::OOWeakReference* ToCxx(OOWeakReference* weakRef);

// [object className], for cxx::OOWeakReference::className(): the send needs a declaration of
// -className, which only Objective-C can write (ADR-0056 amendment oo-9ht.66).
id SendClassName(id object);

} // namespace oo

#endif // OOWEAKREFERENCE_OBJCBRIDGE_H
