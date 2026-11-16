/*

OOObjectGNUstepBridge.mm

TEMPORARY: oo-qps (libgnustep-base leaves the build) deletes this file.

Classes rerooted from NSObject onto the Foundation-free OOObject (proposed ADR-0029, bead
oo-3rb.2) have no -description: the floor deliberately leaves it out, because the String and
Logging seams remove %@. While gnustep-base is still linked, %@ and NSLog/OOLog of such an object
send it -description and raise without one (ADR-0029 measurement 11). This category gives
OOObject exactly NSObject's GNUstep descriptions, so log output is unchanged by a reroot:

    +description  "ClassName"                     (NSObject: the class name)
    -description  "<ClassName: 0xADDRESS>"        (NSObject: "<%s: %p>", class name, self)

A rerooted class that already overrides -description (OORoleSet does) is unaffected.

*/

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOObject (OOGNUstepBridge)

+ (NSString*)description;
- (NSString*)description;

@end

@implementation OOObject (OOGNUstepBridge)

+ (NSString*)description
{
    return [NSString stringWithUTF8String:class_getName(self)];
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"<%s: %p>", class_getName(object_getClass(self)), self];
}

@end
