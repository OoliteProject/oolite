// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
#import "OOMaths.h"
#import "OOTypes.h"
@interface OOHarnessSystemManager : NSObject
- (Random_Seed) getRandomSeedForCurrentSystem;
@end
@interface Universe : NSObject
- (NSDictionary *) descriptions;
- (NSString *) getSystemName:(OOSystemID)sys;
- (NSString *) getSystemName:(OOSystemID)sys forGalaxy:(OOGalaxyID)gal;
- (OOHarnessSystemManager *) systemManager;
@end
#ifdef __cplusplus
extern "C" {
#endif
Universe *OOGetUniverse(void);
#ifdef __cplusplus
}
#endif
#define UNIVERSE OOGetUniverse()
