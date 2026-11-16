/*

OOObjectGNUstepBridge.h

TEMPORARY: oo-qps (libgnustep-base leaves the build) deletes this file and its import in
OOFoundation.h. See OOObjectGNUstepBridge.mm.

*/

// Imported only by OOFoundation.h, after Foundation: the Foundation types used here come from there
// (importing OOFoundation.h back from here was an include cycle, misc-header-include-cycle).
#import "oofnd/objc/OOObject.h"

@interface OOObject (OOGNUstepBridge)

+ (NSString*)description;

// NSObject's own implementations, applied to an OOObject (see OOObjectGNUstepBridge.mm).
- (NSString*)className;

@end
