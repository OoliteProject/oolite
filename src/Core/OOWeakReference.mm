/*

OOWeakReference.m

Written by Jens Ayton in 2007-2013 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakReference.h"
#import "NSObjectOOExtensions.h"
#import "OOFoundation.h" // OOObject's -description components
#import "OOJavaScriptEngine.h" // OOObject (OOJavaScript)

#include "oofnd/String.hpp"
#include "oofnd/objc/OORuntime.h"

/*	The members here are the bodies of OOWeakReference's methods; its facade
        (OOWeakReference+ObjCBridge.mm) forwards each method to its member, and keeps what depends on
        the facade being the reference: -dealloc's -weakRefDied: (sent with the facade as the
        reference), +weakRefWithObject:'s nil check, and OOWeakReferenceNilTarget (bead oo-3kqi).

        OOWeakReference was a gnustep-base proxy-root subclass that forwarded every message as an invocation
        (bead oo-3rb.54, ADR-0029 Decision 5). It is now an OOObject that forwards with
        -forwardingTargetForSelector:, which both libobjc2 hooks in use (gnustep-base's while it is
        linked, then the floor's OOObjCInstallFloor()) consult before any invocation machinery.

        A dead reference (the object is gone) must still answer every message like nil. The target
        is then OOWeakReferenceNilTarget's single instance, which answers any selector it is sent
        with 0 (a method added on first use by +resolveInstanceMethod: under gnustep-base's hook,
        an ignored -doesNotRecognizeSelector: under the floor's). As before,
        a floating-point or struct result from a dead reference is undefined (see the header).

        That proxy root implemented only a few methods itself and forwarded the rest; OOObject and its
        categories implement more, so the ones the proxy forwarded are forwarded here explicitly
        (isKindOfClass: and friends, the description components, the JavaScript conversions, the
        deep copy, the GNUstep bridge's -className, the object size). -hash is
        the proxy root's value (the address shifted right by 3, measured against gnustep-base 1.31.1), so
        a set of weak references (OOWeakSet) keeps its iteration order.
*/

namespace cxx {

// *** Core functionality.

// The old +weakRefWithObject:'s assignment (its nil check and allocation are the facade's).
OOWeakReference::OOWeakReference(id object)
{
    _object = object;
}

std::optional<std::string> OOWeakReference::description()
{
    if (_object != nil)
        return [(id)_object cxx_description]; // -description is not in the OOObject protocol (the Logging seam)
    else
        return oo::str::format("<Dead %s %s>", oo::DescriptionOf(class_()).c_str(), oo::str::pointerDescription(oo::ToObjC(this)).c_str());
}

id OOWeakReference::weakRefUnderlyingObject()
{
    return _object;
}

id OOWeakReference::weakRetain()
{
    return [oo::ToObjC(this) retain];
}

void OOWeakReference::weakRefDrop()
{
    _object = nil;
}

// *** Forwarding.

Class OOWeakReference::class_()
{
    return [_object class];
}

bool OOWeakReference::isProxy()
{
    return true;
}

bool OOWeakReference::respondsToSelector(SEL selector)
{
    if (__builtin_expect(_object != nil && !OOSelectorsEqual(selector, OOSelectorFromName("weakRefDrop")) && !OOSelectorsEqual(selector, OOSelectorFromName("weakRefUnderlyingObject")), 1)) {
        // _object exists and it's not one of our methods, ask _object.
        return [_object respondsToSelector:selector];
    } else {
        // Selector we responds to, or _object is nil and therefore responds to everything.
        return true;
    }
}

id OOWeakReference::forwardingTargetForSelector(SEL /*selector*/)
{
    if (__builtin_expect(_object != nil, 1))
        return _object;
    return [OOWeakReferenceNilTarget sharedNilTarget];
}

uintptr_t OOWeakReference::hash()
{
    // The old proxy root's -hash (measured): the address (of the facade, the reference) shifted right by 3.
    return reinterpret_cast<uintptr_t>(oo::ToObjC(this)) >> 3;
}

// What the old proxy root forwarded and OOObject (or one of its categories) answers itself.

bool OOWeakReference::isKindOfClass(Class aClass)
{
    return [(id)_object isKindOfClass:aClass];
}

bool OOWeakReference::isMemberOfClass(Class aClass)
{
    return [(id)_object isMemberOfClass:aClass];
}

bool OOWeakReference::conformsToProtocol(Protocol* protocol)
{
    return [(id)_object conformsToProtocol:protocol];
}

std::optional<std::string> OOWeakReference::descriptionComponents() const
{
    return [(id)_object cxx_descriptionComponents];
}

std::optional<std::string> OOWeakReference::shortDescription()
{
    return [(id)_object cxx_shortDescription];
}

std::optional<std::string> OOWeakReference::shortDescriptionComponents()
{
    return [(id)_object cxx_shortDescriptionComponents];
}

id OOWeakReference::className()
{
    return oo::SendClassName(_object); // the message send is the bridge's (bead oo-9ht.66)
}

size_t OOWeakReference::oo_objectSize()
{
    return [(id)_object oo_objectSize];
}

// The engine asks the C++ entity of a weak reference to an entity's object itself
// (OOObject+OOJavaScript.mm), so these two are sent only to other objects.
JSValue OOWeakReference::oo_jsValueInContext(JSContext* context)
{
    if (_object == nil)
        return JS_UNDEFINED;
    return [(id)_object oo_jsValueInContext:context];
}

std::optional<std::string> OOWeakReference::oo_jsDescription()
{
    if (_object == nil)
        return std::nullopt;
    return [(id)_object cxx_oo_jsDescription];
}

std::optional<std::string> OOWeakReference::oo_jsDescriptionWithClassName(const std::optional<std::string>& className)
{
    if (_object == nil)
        return std::nullopt;
    return [(id)_object cxx_oo_jsDescriptionWithClassName:className];
}

std::optional<std::string> OOWeakReference::oo_jsClassName()
{
    if (_object == nil)
        return std::nullopt;
    return [(id)_object cxx_oo_jsClassName];
}

void OOWeakReference::oo_clearJSSelf(JSValueConst selfVal)
{
    [(id)_object oo_clearJSSelf:selfVal];
}

} // namespace cxx
