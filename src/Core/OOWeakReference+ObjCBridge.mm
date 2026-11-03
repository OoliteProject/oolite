/*

OOWeakReference+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-3kqi): the Objective-C OOWeakReference facade over
cxx::OOWeakReference, which it makes and owns (amendment oo-3kqi); every method forwards to its
C++ member. Also, unchanged from OOWeakReference.mm: the OOObject (OOWeakReference) category,
OOWeakRefObject and OOWeakReferenceNilTarget. Deleted with OOWeakReference+ObjCBridge.h.

Written by Jens Ayton in 2007-2013 for Oolite.
This code is hereby placed in the public domain.

*/

#import "NSObjectOOExtensions.h"
#import "OODescription.h"
#import "OOJavaScriptEngine.h" // OOObject (OOJavaScript)
#import "OOWeakReference.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

// -className as the GNUstep bridge declared it (the object may answer it; nothing declares it since
// oo-3rb.4 deleted OOObjectGNUstepBridge). The Objective-C -className forwarded it unchanged.
@protocol OOWeakReferenceClassName
- (id)className;
@end

id oo::SendClassName(id object)
{
    return [(id<OOWeakReferenceClassName>)object className];
}

@interface OOWeakReference (OOObjCBridgePrivate)

- (id)initWithObject:(id<OOWeakReferenceSupport>)object;

@end

@implementation OOWeakReference

// Inside the @implementation for the private ivar.
OOWeakReference* oo::ToObjC(cxx::OOWeakReference* weakRef)
{
    // The live facade or nil: a new facade would be a new reference (amendment oo-3kqi).
    return Peers().peerFor(weakRef, [] { return (id)nil; });
}

cxx::OOWeakReference* oo::ToCxx(OOWeakReference* weakRef)
{
    if (weakRef == nil)
        return nullptr;
    return weakRef->_cxxWeakReference.get();
}

// *** Core functionality.

- (id)init
{
    return [self initWithObject:nil]; // a dead reference, as [[OOWeakReference alloc] init] was
}

- (id)initWithObject:(id<OOWeakReferenceSupport>)object
{
    // The facade makes and owns its C++ object, and records itself as its one peer.
    _cxxWeakReference = oo::makeRef<cxx::OOWeakReference>(object);
    @autoreleasepool {
        Peers().peerFor(_cxxWeakReference.get(), [self] { return [self retain]; });
    }
    return [super init];
}

+ (id)weakRefWithObject:(id<OOWeakReferenceSupport>)object
{
    if (object == nil)
        return nil;

    OOWeakReference* result = [[OOWeakReference alloc] initWithObject:object];
    return [result autorelease];
}

- (void)dealloc
{
    // The old -dealloc body. It stays here because it hands the object the reference, which is
    // this facade (the peer table already reads it as dead).
    [_cxxWeakReference->weakRefUnderlyingObject() weakRefDied:self];

    Peers().forget(_cxxWeakReference.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_description
{
    return _cxxWeakReference->description();
}
- (id)weakRefUnderlyingObject
{
    return _cxxWeakReference->weakRefUnderlyingObject();
}
- (id)weakRetain
{
    return _cxxWeakReference->weakRetain();
}
- (void)weakRefDrop
{
    _cxxWeakReference->weakRefDrop();
}

// *** Forwarding.

- (Class)class
{
    return _cxxWeakReference->class_();
}
- (BOOL)isProxy
{
    return _cxxWeakReference->isProxy();
}
- (BOOL)respondsToSelector:(SEL)selector
{
    return _cxxWeakReference->respondsToSelector(selector);
}
- (id)forwardingTargetForSelector:(SEL)selector
{
    return _cxxWeakReference->forwardingTargetForSelector(selector);
}
- (uintptr_t)hash
{
    return _cxxWeakReference->hash();
}

// What the old proxy root forwarded and OOObject (or one of its categories) answers itself.

- (BOOL)isKindOfClass:(Class)aClass
{
    return _cxxWeakReference->isKindOfClass(aClass);
}
- (BOOL)isMemberOfClass:(Class)aClass
{
    return _cxxWeakReference->isMemberOfClass(aClass);
}
- (BOOL)conformsToProtocol:(Protocol*)protocol
{
    return _cxxWeakReference->conformsToProtocol(protocol);
}
- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxWeakReference->descriptionComponents();
}
- (std::optional<std::string>)cxx_shortDescription
{
    return _cxxWeakReference->shortDescription();
}
- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return _cxxWeakReference->shortDescriptionComponents();
}
- (id)className
{
    return _cxxWeakReference->className();
}
- (size_t)oo_objectSize
{
    return _cxxWeakReference->oo_objectSize();
}

- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    return _cxxWeakReference->oo_jsValueInContext(context);
}

- (std::optional<std::string>)cxx_oo_jsDescription
{
    return _cxxWeakReference->oo_jsDescription();
}

- (std::optional<std::string>)cxx_oo_jsDescriptionWithClassName:(const std::optional<std::string>&)className
{
    return _cxxWeakReference->oo_jsDescriptionWithClassName(className);
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return _cxxWeakReference->oo_jsClassName();
}
- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    _cxxWeakReference->oo_clearJSSelf(selfVal);
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
