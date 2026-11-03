/*

OOWeakReference.m

Written by Jens Ayton in 2007-2013 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakReference.h"
#import "NSObjectOOExtensions.h"
#import "OODeepCopy.h"
#import "OOFoundation.h" // OOObject's -description components
#import "OOJavaScriptEngine.h" // OOObject (OOJavaScript)
#import "OOStringBridge.h"

#include "oofnd/String.hpp"

/*	OOWeakReference was a gnustep-base proxy-root subclass that forwarded every message as an invocation
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
@interface OOWeakReferenceNilTarget : OOObject

+ (id)sharedNilTarget;

@end

@implementation OOWeakReference

// *** Core functionality.

+ (id)weakRefWithObject:(id<OOWeakReferenceSupport>)object
{
    if (object == nil)
        return nil;

    OOWeakReference* result = [[OOWeakReference alloc] init];
    result->_object = object;
    return [result autorelease];
}

- (void)dealloc
{
    [_object weakRefDied:self];

    [super dealloc];
}

- (id)description
{
    if (_object != nil)
        return [_object description];
    else
        return oo::NSStringFrom(oo::str::format("<Dead %s %s>", oo::StdString([[self class] description]).c_str(), oo::str::pointerDescription(self).c_str()));
}

- (id)weakRefUnderlyingObject
{
    return _object;
}

- (id)weakRetain
{
    return [self retain];
}

- (void)weakRefDrop
{
    _object = nil;
}

// *** Forwarding.

- (Class)class
{
    return [_object class];
}

- (BOOL)isProxy
{
    return YES;
}

- (BOOL)respondsToSelector:(SEL)selector
{
    if (__builtin_expect(_object != nil && selector != @selector(weakRefDrop) && selector != @selector(weakRefUnderlyingObject), 1)) {
        // _object exists and it's not one of our methods, ask _object.
        return [_object respondsToSelector:selector];
    } else {
        // Selector we responds to, or _object is nil and therefore responds to everything.
        return YES;
    }
}

- (id)forwardingTargetForSelector:(SEL)selector
{
    if (__builtin_expect(_object != nil, 1))
        return _object;
    return [OOWeakReferenceNilTarget sharedNilTarget];
}

- (uintptr_t)hash
{
    // The old proxy root's -hash (measured): the address shifted right by 3.
    return reinterpret_cast<uintptr_t>(self) >> 3;
}

// What the old proxy root forwarded and OOObject (or one of its categories) answers itself.

- (BOOL)isKindOfClass:(Class)aClass
{
    return [(id)_object isKindOfClass:aClass];
}

- (BOOL)isMemberOfClass:(Class)aClass
{
    return [(id)_object isMemberOfClass:aClass];
}

- (BOOL)conformsToProtocol:(Protocol*)protocol
{
    return [(id)_object conformsToProtocol:protocol];
}

- (id)descriptionComponents
{
    return [(id)_object descriptionComponents];
}

- (id)shortDescription
{
    return [(id)_object shortDescription];
}

- (id)shortDescriptionComponents
{
    return [(id)_object shortDescriptionComponents];
}

- (id)className
{
    return [(id)_object className];
}

- (id)ooDeepCopyWithSharedObjects:(id)objects
{
    return [(id)_object ooDeepCopyWithSharedObjects:objects];
}

- (size_t)oo_objectSize
{
    return [(id)_object oo_objectSize];
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    if (_object == nil)
        return JS_UNDEFINED;
    return [(id)_object oo_jsValueInContext:context];
}

- (id)oo_jsDescription
{
    return [(id)_object oo_jsDescription];
}

- (id)oo_jsDescriptionWithClassName:(id)className
{
    return [(id)_object oo_jsDescriptionWithClassName:className];
}

- (id)oo_jsClassName
{
    return [(id)_object oo_jsClassName];
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    [(id)_object oo_clearJSSelf:selfVal];
}

@end

@implementation NSObject (OOWeakReference)

- (id)weakRefUnderlyingObject
{
    return self;
}

@end

@implementation OOObject (OOWeakReference)

- (id)weakRefUnderlyingObject
{
    return self;
}

@end

@implementation OOWeakRefObject

- (id)weakRetain
{
    if (weakSelf == nil)
        weakSelf = [OOWeakReference weakRefWithObject:self];
    return [weakSelf retain]; // Each caller releases this, as -weakRetain must be balanced with -release.
}

- (void)weakRefDied:(OOWeakReference*)weakRef
{
    if (weakRef == weakSelf)
        weakSelf = nil;
}

- (void)dealloc
{
    [weakSelf weakRefDrop]; // Very important!
    [super dealloc];
}

- (id)weakSelf
{
    return [[self weakRetain] autorelease];
}

@end

namespace {

// Every selector sent to a dead weak reference: answers like a message to nil (an integer or
// pointer 0; a floating-point or struct result is undefined, as it was).
id OOWeakReferenceNilIMP(id, SEL)
{
    return nil;
}

} // namespace

@implementation OOWeakReferenceNilTarget

+ (id)sharedNilTarget
{
    static OOWeakReferenceNilTarget* sShared = nil;
    if (sShared == nil)
        sShared = [[OOWeakReferenceNilTarget alloc] init];
    return sShared;
}

// gnustep-base's forwarding hook (while it is linked) asks the class to resolve the selector:
// add the nil method for it.
+ (BOOL)resolveInstanceMethod:(SEL)selector
{
    const char* types = sel_getType_np(selector);
    class_addMethod(self, selector, reinterpret_cast<IMP>(OOWeakReferenceNilIMP), (types != NULL) ? types : "@@:");
    return YES;
}

// The floor's hook (OOObjCInstallFloor()) does not resolve: its unrecognised-selector method sends
// this and then returns nil, which is the answer wanted (tests/unit/oofnd/test_objc_floor.mm,
// forwardingAndUnrecognizedSelectors, checks that path).
- (void)doesNotRecognizeSelector:(SEL)selector
{
}

@end
