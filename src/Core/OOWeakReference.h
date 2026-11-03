/*

OOWeakReference.h

Weak reference class for Cocoa/GNUstep/OpenStep: the C++ side (proposed ADR-0056, bead
oo-3kqi). cxx::OOWeakReference holds a weak reference's state, the object it refers to (not
retained), and answers every message its Objective-C facade forwards. The facade,
OOWeakReference in OOWeakReference+ObjCBridge.h, is the reference's identity: it makes and owns
its C++ object, and callers compare, hash and hold the facade (ADR-0056 amendment oo-3kqi). That
header also has the OOWeakReferenceSupport protocol, OOWeakRefObject and the usage notes.

A class converted to C++ does not use this: it derives from oo::RefCounted and is held weakly
with oo::WeakRef (oofnd/Ref.hpp). Converted code that holds an Objective-C object weakly keeps the
facade (oo::ObjCRef<OOWeakReference *>) and reaches the C++ object through oo::ToCxx.


Copyright (C) 2007-2013 Jens Ayton
This code is hereby placed in the public domain.

*/

#ifndef OOWEAKREFERENCE_H
#define OOWEAKREFERENCE_H

#import "OOFoundation.h"
#import "OOFunctionAttributes.h"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include <quickjs.h>

namespace cxx {

class OOWeakReference : public oo::RefCounted {
public:
    explicit OOWeakReference(id object); // object: conforms to OOWeakReferenceSupport; nil gives a dead reference

    id weakRefUnderlyingObject();

    id weakRetain() OO_RETURNS_RETAINED; // Returns the facade, retained: [self retain] for weakrefs.

    // For referred object only:
    void weakRefDrop();

    // What "%@" prints for the reference: the object's description, or <Dead ...> once it has gone.
    std::optional<std::string> description();

    // Forwarding: what the facade answers for the Objective-C runtime's questions.
    Class class_(); // -class (a C++ keyword)
    bool isProxy();
    bool respondsToSelector(SEL selector);
    id forwardingTargetForSelector(SEL selector);
    uintptr_t hash();

    // What the old proxy root forwarded and OOObject (or one of its categories) answers itself.
    bool isKindOfClass(Class aClass);
    bool isMemberOfClass(Class aClass);
    bool conformsToProtocol(Protocol* protocol);
    std::optional<std::string> descriptionComponents() const;
    std::optional<std::string> shortDescription();
    std::optional<std::string> shortDescriptionComponents();
    id className();
    size_t oo_objectSize();
    JSValue oo_jsValueInContext(JSContext* context); // owned
    std::optional<std::string> oo_jsDescription();
    std::optional<std::string> oo_jsDescriptionWithClassName(const std::optional<std::string>& className);
    std::optional<std::string> oo_jsClassName();
    void oo_clearJSSelf(JSValueConst selfVal);

private:
    id _object = { }; // id<OOWeakReferenceSupport>
};

} // namespace cxx

// Transitional: the Objective-C OOWeakReference (the reference callers hold), the
// OOWeakReferenceSupport protocol and OOWeakRefObject. Deleted, with namespace cxx above, by the
// bridge's deletion bead.
#import "OOWeakReference+ObjCBridge.h"

#endif // OOWEAKREFERENCE_H
