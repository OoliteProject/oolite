/*

OOObjectGNUstepBridge.h

TEMPORARY: oo-qps (libgnustep-base leaves the build) deletes this file and its import in
OOFoundation.h. See OOObjectGNUstepBridge.mm.

*/

#import "OOFoundation.h" // imports this header after Foundation; the Foundation types used here come from there
#import "oofnd/objc/OOObject.h"

@interface OOObject (OOGNUstepBridge)

+ (NSString*)description;

// NSObject's own implementations, applied to an OOObject (see OOObjectGNUstepBridge.mm).
+ (NSMethodSignature*)instanceMethodSignatureForSelector:(SEL)selector;
- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector;
- (void)performSelector:(SEL)selector withObject:(id)argument afterDelay:(NSTimeInterval)delay;
- (NSString*)className;

@end
