/*	oofnd/objc/OOObject.mm
        The Foundation-free root class (see OOObject.h and proposed ADR-0029).

        Memory management is libobjc2's, not a second count: +alloc is class_createInstance (which
        reserves the runtime's inline reference count in front of the object and runs .cxx_construct),
        -dealloc is object_dispose (which runs .cxx_destruct). The -_ARCCompliantRetainRelease marker
        tells libobjc2 that this class's -retain/-release/-autorelease are the runtime's own, so
        objc_retain()/objc_release()/objc_autorelease() take the fast inline path instead of sending
        the message back to us (which would recurse). A subclass that overrides -retain or -release
        (an immortal singleton) loses the fast path for itself only, and the runtime then sends it
        the message, exactly as with NSObject.
*/

#include "oofnd/objc/OOObject.h"
#include "oofnd/objc/OOConstantString.h"

#include <objc/hooks.h>
#include <objc/objc-arc.h>

#include <cstdio>
#include <cstdlib>

namespace {

typedef id (*OOObjectMethod0)(id, SEL);
typedef id (*OOObjectMethod1)(id, SEL, id);
typedef id (*OOObjectMethod2)(id, SEL, id, id);

// The IMP the runtime calls for a selector nothing implements (after forwardingTargetForSelector:
// declined). NSObject raises; OOObject sends -doesNotRecognizeSelector:, which aborts. Only an
// object-returning signature is modelled: a struct or floating-point return reads garbage, which
// is moot because the default handler never returns.
id OOUnrecognizedSelectorIMP(id self, SEL _cmd)
{
    Class cls = object_getClass(self);
    if (cls != Nil && class_respondsToSelector(cls, @selector(doesNotRecognizeSelector:))) {
        [self doesNotRecognizeSelector:_cmd];
    } else {
        std::fprintf(stderr, "oofnd: unrecognised selector -%s sent to %p (class %s), which has no -doesNotRecognizeSelector:\n",
            sel_getName(_cmd), static_cast<void*>(self), cls != Nil ? class_getName(cls) : "Nil");
        std::abort();
    }
    return nil;
}

IMP OOForwardingHook(id, SEL)
{
    return reinterpret_cast<IMP>(OOUnrecognizedSelectorIMP);
}

// -forwardingTargetForSelector:, consulted by libobjc2 before the forwarding hook.
id OOProxyLookup(id receiver, SEL selector)
{
    Class cls = object_getClass(receiver);
    if (cls == Nil || !class_respondsToSelector(cls, @selector(forwardingTargetForSelector:)))
        return nil;
    id target = [receiver forwardingTargetForSelector:selector];
    return target == receiver ? nil : target;
}

} // namespace

#if defined(_WIN32)
// clang's gnustep-2 code generator declares the constant-string class `dllimport` on COFF in
// every TU that does not define it (it assumes the class lives in a DLL, as NSConstantString
// did in gnustep-base), so each @"..." references __imp_$_OBJC_CLASS_OOConstantString. We link
// the class statically; left alone, lld synthesises that import slot and reports LNK4217
// ("locally defined symbol imported"), which meson's werror makes fatal. Defining the slot is
// exactly what an import library would provide, so there is nothing to synthesise and nothing to
// report. It lives here, not in OOConstantString.mm, because that TU defines the class symbol
// itself. Measured in ADR-0029.
extern "C" {
extern char OOConstantStringClassSymbol __asm__("$_OBJC_CLASS_OOConstantString");
extern void* const OOConstantStringImportSlot __asm__("__imp_$_OBJC_CLASS_OOConstantString");
void* const OOConstantStringImportSlot = &OOConstantStringClassSymbol;
}
#endif

void OOObjCInstallFloor(void)
{
    OOConstantStringInstall();
    objc_proxy_lookup = OOProxyLookup;
    __objc_msg_forward2 = OOForwardingHook;
}

@implementation OOObject

- (void)_ARCCompliantRetainRelease
{
    // Marker for libobjc2: see the banner.
}

+ (void)initialize
{
}

+ (id)alloc
{
    return class_createInstance(self, 0);
}

+ (id)allocWithZone:(OOZone*)zone
{
    (void)zone;
    return [self alloc];
}

+ (id)new
{
    return [[self alloc] init];
}

+ (Class)class
{
    return self;
}

+ (Class)superclass
{
    return class_getSuperclass(self);
}

+ (BOOL)isSubclassOfClass:(Class)aClass
{
    for (Class c = self; c != Nil; c = class_getSuperclass(c)) {
        if (c == aClass)
            return YES;
    }
    return NO;
}

+ (BOOL)instancesRespondToSelector:(SEL)selector
{
    return class_respondsToSelector(self, selector);
}

+ (IMP)instanceMethodForSelector:(SEL)selector
{
    return class_getMethodImplementation(self, selector);
}

+ (BOOL)conformsToProtocol:(Protocol*)protocol
{
    for (Class c = self; c != Nil; c = class_getSuperclass(c)) {
        if (class_conformsToProtocol(c, protocol))
            return YES;
    }
    return NO;
}

+ (id)retain
{
    return self;
}

+ (oneway void)release
{
}

+ (id)autorelease
{
    return self;
}

- (id)init
{
    return self;
}

- (void)dealloc
{
    object_dispose(self);
}

- (id)retain
{
    return objc_retain_fast_np(self);
}

- (oneway void)release
{
    objc_release_fast_np(self); // sends -dealloc when the count reaches zero
}

- (id)autorelease
{
    return objc_autorelease(self);
}

- (uintptr_t)retainCount
{
    return object_getRetainCount_np(self);
}

- (id)self
{
    return self;
}

- (Class)class
{
    return object_getClass(self);
}

- (Class)superclass
{
    return class_getSuperclass(object_getClass(self));
}

- (BOOL)isKindOfClass:(Class)aClass
{
    for (Class c = object_getClass(self); c != Nil; c = class_getSuperclass(c)) {
        if (c == aClass)
            return YES;
    }
    return NO;
}

- (BOOL)isMemberOfClass:(Class)aClass
{
    return object_getClass(self) == aClass;
}

- (BOOL)respondsToSelector:(SEL)selector
{
    return class_respondsToSelector(object_getClass(self), selector);
}

- (IMP)methodForSelector:(SEL)selector
{
    return class_getMethodImplementation(object_getClass(self), selector);
}

- (BOOL)conformsToProtocol:(Protocol*)protocol
{
    return [object_getClass(self) conformsToProtocol:protocol];
}

- (BOOL)isProxy
{
    return NO;
}

- (BOOL)isEqual:(id)other
{
    return self == other;
}

- (uintptr_t)hash
{
    const void* address = self;
    return reinterpret_cast<uintptr_t>(address);
}

- (id)performSelector:(SEL)selector
{
    IMP imp = class_getMethodImplementation(object_getClass(self), selector);
    return reinterpret_cast<OOObjectMethod0>(imp)(self, selector);
}

- (id)performSelector:(SEL)selector withObject:(id)object
{
    IMP imp = class_getMethodImplementation(object_getClass(self), selector);
    return reinterpret_cast<OOObjectMethod1>(imp)(self, selector, object);
}

- (id)performSelector:(SEL)selector withObject:(id)object1 withObject:(id)object2
{
    IMP imp = class_getMethodImplementation(object_getClass(self), selector);
    return reinterpret_cast<OOObjectMethod2>(imp)(self, selector, object1, object2);
}

- (id)copy
{
    return [(id<OOCopying>)self copyWithZone:nullptr];
}

- (id)mutableCopy
{
    return [(id<OOMutableCopying>)self mutableCopyWithZone:nullptr];
}

- (id)forwardingTargetForSelector:(SEL)selector
{
    (void)selector;
    return nil;
}

- (void)doesNotRecognizeSelector:(SEL)selector
{
    std::fprintf(stderr, "oofnd: -[%s %s]: unrecognised selector sent to instance %p\n",
        class_getName(object_getClass(self)), sel_getName(selector), static_cast<void*>(self));
    std::abort();
}

@end
