/*

OOObjectGNUstepBridge.mm

TEMPORARY: oo-qps (libgnustep-base leaves the build) deletes this file.

Classes rerooted from NSObject onto the Foundation-free OOObject (proposed ADR-0029, bead
oo-3rb.2) lose what NSObject gave them. What the game's own NSObject categories give (the
-description of OOFoundation.h's OODescriptionComponents, JS conversion, weak references, ...) has an
OOObject twin next to each category. What gnustep-base's NSObject gives is here, until the bead
that removes each Foundation family replaces it:

    +description  "ClassName"            (NSObject: the class name; %@ of [self class])
    -methodSignatureForSelector:,        NSObject's own implementations (runtime lookups only),
    +instanceMethodSignatureForSelector:  called with an OOObject receiver; the NSInvocation
                                          follow-ups of oo-3rb.15 (OOWeakReference's proxy,
                                          OOOXZManager's filter) replace them
    -performSelector:...afterDelay:       again gnustep-base's own implementation (a timed performer
                                          on the current run loop, retaining receiver and argument);
                                          replaced when the run loop goes (NSTimer/NSRunLoop)
    -className                            NSObject's own implementation (the class name as an
                                          NSString; OOALSoundDecoder's -description); the
                                          String seam replaces it

-description is not here: in the game every NSObject's -description is OOCocoa.mm's
NSObject (OODescriptionComponents), and OOObject (OODescriptionComponents) is its twin.

Borrowing NSObject's IMPs keeps the behaviour identical: gnustep-base implements these with
runtime functions on object_getClass(self) (and, for the timed perform, -retain/-release/
-performSelector:withObject:, which OOObject has), never with NSObject's instance layout.

*/

#import "OOObjectGNUstepBridge.h"

static IMP NSObjectInstanceIMP(SEL selector)
{
    return method_getImplementation(class_getInstanceMethod([NSObject class], selector));
}

static IMP NSObjectClassIMP(SEL selector)
{
    return method_getImplementation(class_getClassMethod([NSObject class], selector));
}

@implementation OOObject (OOGNUstepBridge)

+ (NSString*)description
{
    return [NSString stringWithUTF8String:class_getName(self)];
}

+ (NSMethodSignature*)instanceMethodSignatureForSelector:(SEL)selector
{
    typedef NSMethodSignature* (*SignatureIMP)(id, SEL, SEL);
    return ((SignatureIMP)NSObjectClassIMP(_cmd))(self, _cmd, selector);
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector
{
    typedef NSMethodSignature* (*SignatureIMP)(id, SEL, SEL);
    return ((SignatureIMP)NSObjectInstanceIMP(_cmd))(self, _cmd, selector);
}

- (void)performSelector:(SEL)selector withObject:(id)argument afterDelay:(NSTimeInterval)delay
{
    typedef void (*PerformAfterDelayIMP)(id, SEL, SEL, id, NSTimeInterval);
    ((PerformAfterDelayIMP)NSObjectInstanceIMP(_cmd))(self, _cmd, selector, argument, delay);
}

- (NSString*)className
{
    typedef NSString* (*ClassNameIMP)(id, SEL);
    return ((ClassNameIMP)NSObjectInstanceIMP(_cmd))(self, _cmd);
}

@end
