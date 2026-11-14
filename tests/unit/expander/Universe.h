// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOTypes.h"
#ifdef __cplusplus
#include "oofnd/PList.hpp"
#include <optional>
#include <string>
#endif
@interface OOHarnessSystemManager : NSObject
- (Random_Seed) getRandomSeedForCurrentSystem;
@end
@interface Universe : NSObject
- (NSDictionary *) descriptions;
- (NSString *) getSystemName:(OOSystemID)sys;
- (NSString *) getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gal;
- (OOHarnessSystemManager *) systemManager;
// The C++ forms the expander calls since the Universe bridge callers moved (bead oo-3rb.311),
// over the same stub data (bead oo-qqz6: stub-API tracking; the lines above are unchanged).
#ifdef __cplusplus
- (const oo::PList *) cxx_descriptions;
- (std::optional<std::string>) cxx_getSystemName:(OOSystemID)sys;
- (std::optional<std::string>) cxx_getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gal;
#endif
@end
#ifdef __cplusplus
extern "C" {
#endif
Universe *OOGetUniverse(void);
#ifdef __cplusplus
}
#endif
#define UNIVERSE OOGetUniverse()
