// Stub for tests/unit/sysdesc (bead oo-vjwp): only what src/Core/OOConvertSystemDescriptions.mm uses.
#import "OOFoundation.h"
#include "oofnd/PList.hpp"
#ifndef OO_LOCALIZATION_TOOLS
#define OO_LOCALIZATION_TOOLS	1
#endif
@interface Universe : NSObject
- (NSDictionary *) descriptions;
// The C++ form OOConvertSystemDescriptions.mm calls since oo-3rb.310 (bead oo-3rb.335: stub-API tracking).
- (const oo::PList *) cxx_descriptions;
@end
Universe *OOGetUniverse(void);
#define UNIVERSE OOGetUniverse()
