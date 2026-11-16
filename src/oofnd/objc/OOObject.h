/*	oofnd/objc/OOObject.h
        The Foundation-free Objective-C root class (proposed ADR-0029, bead oo-3rb.1). Phase 2 ends
        with libgnustep-base gone while game classes are still Objective-C++; this is what they
        inherit from instead of NSObject, on libobjc2 (the GNUstep runtime) and nothing else.

            NSObject                                  OOObject
            ----------------------------------------  -------------------------------------------------
            @interface Foo : NSObject                 @interface Foo : OOObject
            @protocol P <NSObject>                    @protocol P <OOObject>
            [[Foo alloc] init], +new, +allocWithZone: the same (class_createInstance; C++ ivars are
                                                      constructed and destroyed, -fobjc-call-cxx-cdtors)
            -retain / -release / -autorelease         the same; the count is libobjc2's own inline
                                                      count (objc_retain_fast_np and friends), so
                                                      objc_retain()/objc_release() and __weak agree
            the Foundation autorelease pool class     @autoreleasepool { } or objc_autoreleasePoolPush/
                                                      Pop: libobjc2's own pool, no class needed
            -isEqual: / -hash                         identity, as NSObject's
            -respondsToSelector:, -isKindOfClass:,    the same, on the runtime's introspection
            -conformsToProtocol:, -performSelector:*
            -copy / -mutableCopy                      the same; they send -copyWithZone: /
                                                      -mutableCopyWithZone: (OOCopying/OOMutableCopying)
            -forwardingTargetForSelector:             the same, once OOObjCInstallFloor() has run
            unrecognised selector -> exception        -doesNotRecognizeSelector: logs and aborts
            NSZone *                                  OOZone * (opaque; always nil, as on GNUstep today)
            NSUInteger (retainCount, hash)            uintptr_t (GNUstep's own NSUInteger typedef)

        Deliberately NOT here (each has its own bead under oo-3rb): -description and %@ (the String and
        Logging seams), exceptions (the NSException bead), NSInvocation forwarding, NSValue, locks,
        threads, timers, notifications, dates, zones beyond the opaque typedef.

        OOObjCInstallFloor() must run once at start-up, before the first message to a short string
        literal: it registers the small-object class clang's short @"..." literals need
        (oofnd/objc/OOConstantString.h) and installs the runtime's forwarding hooks. It is explicit,
        not a +load, because until oo-qps deletes libgnustep-base the game links gnustep-base, which
        installs its own hooks and small-string class; the two must never be mixed (see the ADR).

        Build requirements, measured on MSYS2 UCRT64 clang 22 + libobjc2 2.3 (see ADR-0029):
        -fobjc-runtime=gnustep-2.2 (the game's), -fuse-ld=lld (GNU ld cannot resolve the gnustep-2
        ABI's COFF selector symbols), -lobjc and nothing from gnustep-base.
*/

#ifndef OOFND_OBJC_OOOBJECT_H
#define OOFND_OBJC_OOOBJECT_H

#include <objc/runtime.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Registers OOTinyString for clang's short-literal tag and installs the forwarding hooks.
// Idempotent. Aborts if another library already owns the small-string tag (gnustep-base).
void OOObjCInstallFloor(void);

#ifdef __cplusplus
}
#endif

// NSZone is a GNUstep-only concept Oolite never uses beyond passing it through; always nil.
typedef struct OOZone OOZone;

@protocol OOCopying
- (id)copyWithZone:(OOZone*)zone;
@end

@protocol OOMutableCopying
- (id)mutableCopyWithZone:(OOZone*)zone;
@end

/*	Protocol form of the floor (oo-9evb). Protocols that inherited <NSObject>
        inherit <OOObject> so id<P> can send -retain / -respondsToSelector: and the
        rest without "method not found in protocol" once gnustep-base is gone.
        No -description here: that is the Logging seam.
*/
@protocol OOObject

- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (uintptr_t)retainCount;

- (id)self;
- (Class)class;
- (Class)superclass;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isMemberOfClass:(Class)aClass;
- (BOOL)respondsToSelector:(SEL)selector;
- (BOOL)conformsToProtocol:(Protocol*)protocol;
- (BOOL)isProxy;

- (BOOL)isEqual:(id)other;
- (uintptr_t)hash;

- (id)performSelector:(SEL)selector;
- (id)performSelector:(SEL)selector withObject:(id)object;
- (id)performSelector:(SEL)selector withObject:(id)object1 withObject:(id)object2;

@end

__attribute__((objc_root_class))
@interface OOObject<OOObject> {
@protected
    Class isa;
}

+ (void)initialize;
+ (id)alloc;
+ (id)allocWithZone:(OOZone*)zone;
+ (id)new;

+ (Class)class;
+ (Class)superclass;
+ (BOOL)isSubclassOfClass:(Class)aClass;
+ (BOOL)instancesRespondToSelector:(SEL)selector;
+ (IMP)instanceMethodForSelector:(SEL)selector;
+ (BOOL)conformsToProtocol:(Protocol*)protocol;

// A class object is not refcounted; these make [SomeClass retain] etc. harmless, as on NSObject.
+ (id)retain;
+ (oneway void)release;
+ (id)autorelease;

- (id)init;
- (void)dealloc;

- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (uintptr_t)retainCount;

- (id)self;
- (Class)class;
- (Class)superclass;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)isMemberOfClass:(Class)aClass;
- (BOOL)respondsToSelector:(SEL)selector;
- (IMP)methodForSelector:(SEL)selector;
- (BOOL)conformsToProtocol:(Protocol*)protocol;
- (BOOL)isProxy;

- (BOOL)isEqual:(id)other;
- (uintptr_t)hash;

- (id)performSelector:(SEL)selector;
- (id)performSelector:(SEL)selector withObject:(id)object;
- (id)performSelector:(SEL)selector withObject:(id)object1 withObject:(id)object2;

- (OOZone*)zone; // always nil: the zone -copy and -mutableCopy pass
- (id)copy;
- (id)mutableCopy;

- (id)forwardingTargetForSelector:(SEL)selector;
- (void)doesNotRecognizeSelector:(SEL)selector;

@end

#endif // OOFND_OBJC_OOOBJECT_H
