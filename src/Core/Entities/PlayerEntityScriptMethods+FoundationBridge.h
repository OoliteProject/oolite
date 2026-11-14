/*

PlayerEntityScriptMethods+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-8mxr). PlayerEntity
(ScriptMethods)'s Foundation-typed API as it was before its sweep, with the same selector names
and types, forwarding to the cxx_ API in PlayerEntityScriptMethods.h. It exists so that the
category's callers (PlayerEntity.mm, PlayerEntityControls.mm, PlayerEntityLegacyScriptEngine.mm,
PlayerEntityKeyMapper.mm, OOStringExpander.mm, OOJSMission.mm, OOJSGlobal.mm, Universe.mm) compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller
of anything declared here, the bridge bead deletes this file, PlayerEntityScriptMethods+
FoundationBridge.mm, its line in Core/Entities/meson.build and the #import at the end of
PlayerEntityScriptMethods.h. Never add to it; never call it from migrated code. oo-qps (the removal
of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (PlayerEntityScriptMethods.h)

*/

// Imported only from the end of PlayerEntityScriptMethods.h (which declares everything used here);
// never import it directly, and never import PlayerEntityScriptMethods.h from it (a cycle).
#ifndef PLAYERENTITYSCRIPTMETHODS_FOUNDATIONBRIDGE_H
#define PLAYERENTITYSCRIPTMETHODS_FOUNDATIONBRIDGE_H

@interface PlayerEntity (ScriptMethodsFoundationBridge)

- (NSString*)dockedStationName; // -> -cxx_dockedStationName
- (NSString*)dockedStationDisplayName; // -> -cxx_dockedStationDisplayName

- (void)awardCommodityType:(NSString*)type amount:(OOCargoQuantity)amount; // -> -cxx_awardCommodityType:amount:

- (void)setMissionChoice:(NSString*)newChoice; // -> -cxx_setMissionChoice:
- (void)setMissionChoice:(NSString*)newChoice withEvent:(BOOL)withEvent; // -> -cxx_setMissionChoice:withEvent:
- (void)setMissionChoice:(NSString*)newChoice keyPress:(NSString*)keyPress; // -> -cxx_setMissionChoice:keyPress:
- (void)setMissionChoice:(NSString*)newChoice keyPress:(NSString*)keyPress withEvent:(BOOL)withEvent; // -> -cxx_setMissionChoice:keyPress:withEvent:

- (NSDictionary*)passengerContractMarker:(OOSystemID)system; // -> -cxx_passengerContractMarker:
- (NSDictionary*)parcelContractMarker:(OOSystemID)system; // -> -cxx_parcelContractMarker:
- (NSDictionary*)cargoContractMarker:(OOSystemID)system; // -> -cxx_cargoContractMarker:
- (NSDictionary*)defaultMarker:(OOSystemID)system; // -> -cxx_defaultMarker:
- (NSDictionary*)validatedMarker:(NSDictionary*)marker; // -> -cxx_validatedMarker:

- (NSString*)keyBindingDescription2:(NSString*)binding; // -> -cxx_keyBindingDescription2:
- (NSString*)getKeyBindingDescription:(NSArray*)keyList; // -> -cxx_getKeyBindingDescription:
- (NSString*)keyCodeDescription:(OOKeyCode)code; // -> -cxx_keyCodeDescription:
- (NSString*)keyCodeDescriptionShort:(OOKeyCode)code; // -> -cxx_keyCodeDescriptionShort:

- (NSString*)commanderKillsAsString; // -> -cxx_commanderKillsAsString
- (NSString*)commanderBountyAsString; // -> -cxx_commanderBountyAsString
- (NSString*)creditsFormattedForSubstitution; // -> -cxx_creditsFormattedForSubstitution
- (NSString*)creditsFormattedForLegacySubstitution; // -> -cxx_creditsFormattedForLegacySubstitution

@end

#endif // PLAYERENTITYSCRIPTMETHODS_FOUNDATIONBRIDGE_H
