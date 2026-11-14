// Stub for tests/unit/expander (bead oo-3rb.61): only what src/Core/OOStringExpander.mm uses.
#import "OOFoundation.h"
#import "OOTypes.h"
#include "oofnd/PList.hpp"
#include <optional>
#include <string>
@interface PlayerEntity : NSObject
- (OOSystemID) systemID;
- (NSString *) missionVariableForKey:(NSString *)key;
- (NSString *) keyBindingDescription2:(NSString *)binding;
// The special keys are called by name (OOCallByName, ADR-0055 item 5), which reads an oo::PList
// result and ignores an object one: they answer the same text as a string PList (bead oo-qqz6:
// stub-API tracking, as PlayerEntityLegacyScriptEngine.h / PlayerEntityScriptMethods.h declare them).
- (oo::PList) commanderName_string;
- (oo::PList) commanderShip_string;
- (oo::PList) commanderShipDisplayName_string;
- (oo::PList) commanderRank_string;
- (oo::PList) commanderKillsAsString;
- (oo::PList) commanderLegalStatus_string;
- (oo::PList) commanderBountyAsString;
- (oo::PList) creditsFormattedForSubstitution;
- (oo::PList) creditsFormattedForLegacySubstitution;
// The C++ forms the expander calls since the PlayerEntity bridges went (beads oo-tj5w, oo-53in).
- (oo::PList) cxx_missionVariableForKey:(const std::string &)key;
- (std::optional<std::string>) cxx_keyBindingDescription2:(const std::string &)binding;
@end
#ifdef __cplusplus
extern "C" {
#endif
PlayerEntity *OOGetPlayer(void);
#ifdef __cplusplus
}
#endif
#define PLAYER OOGetPlayer()
