// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
#ifdef __cplusplus
#include "oofnd/PList.hpp"
#endif
@interface ResourceManager : NSObject
+ (NSDictionary *) whitelistDictionary;
// The C++ form the expander calls since the ResourceManager bridge went (bead oo-0f7h), over the
// same stub data (bead oo-qqz6: stub-API tracking).
#ifdef __cplusplus
+ (oo::PList) cxx_whitelistDictionary;
#endif
@end
