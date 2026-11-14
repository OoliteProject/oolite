// Stub for tests/unit/sysdesc (bead oo-vjwp): only what src/Core/OOConvertSystemDescriptions.mm uses.
#import "OOFoundation.h"
#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS	1
#endif
@interface Universe : NSObject
- (NSDictionary *) descriptions;
@end
Universe *OOGetUniverse(void);
#define UNIVERSE OOGetUniverse()
