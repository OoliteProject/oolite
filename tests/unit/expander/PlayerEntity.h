// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
#import "OOTypes.h"
@interface PlayerEntity : NSObject
- (OOSystemID) systemID;
- (NSString *) missionVariableForKey:(NSString *)key;
- (NSString *) keyBindingDescription2:(NSString *)binding;
- (NSString *) commanderName_string;
- (NSString *) commanderShip_string;
- (NSString *) commanderShipDisplayName_string;
- (NSString *) commanderRank_string;
- (NSString *) commanderKillsAsString;
- (NSString *) commanderLegalStatus_string;
- (NSString *) commanderBountyAsString;
- (NSString *) creditsFormattedForSubstitution;
- (NSString *) creditsFormattedForLegacySubstitution;
@end
#ifdef __cplusplus
extern "C" {
#endif
PlayerEntity *OOGetPlayer(void);
#ifdef __cplusplus
}
#endif
#define PLAYER OOGetPlayer()
