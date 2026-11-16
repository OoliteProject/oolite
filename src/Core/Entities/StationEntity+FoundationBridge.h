/*

StationEntity+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.172, chunk 1 of oo-e7ab's
split; the later chunks oo-3rb.173-.175 move their own selectors in). StationEntity's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in StationEntity.h. It exists so that StationEntity's callers compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller
of anything declared here, the bridge bead deletes this file, StationEntity+FoundationBridge.mm,
its line in Core/Entities/meson.build and the #import at the end of StationEntity.h. Never add to
it outside the StationEntity chunks; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (StationEntity.h)

*/

// Imported only from the end of StationEntity.h (which declares everything used here); never
// import it directly, and never import StationEntity.h from it (a cycle).
#ifndef STATIONENTITY_FOUNDATIONBRIDGE_H
#define STATIONENTITY_FOUNDATIONBRIDGE_H

@interface StationEntity (OOFoundationBridge)

- (NSEnumerator*)dockSubEntityEnumerator; // -> -cxx_dockSubEntities

// oo-3rb.173 (chunk 2): market, allegiance, docking clearance
- (NSArray*)marketDefinition; // -> -cxx_marketDefinition
- (NSString*)marketScriptName; // -> -cxx_marketScriptName
- (void)setLocalMarket:(NSArray*)market; // -> -cxx_setLocalMarket:
- (NSDictionary*)localMarketForScripting; // -> -cxx_localMarketForScripting
- (void)setPrice:(OOCreditsQuantity)price forCommodity:(OOCommodityType)commodity; // -> -cxx_setPrice:forCommodity:
- (void)setQuantity:(OOCargoQuantity)quantity forCommodity:(OOCommodityType)commodity; // -> -cxx_setQuantity:forCommodity:
- (void)setAllegiance:(NSString*)newAllegiance; // -> -cxx_setAllegiance:
- (NSString*)allegiance; // -> -cxx_allegiance
- (NSString*)acceptDockingClearanceRequestFrom:(ShipEntity*)other; // -> -cxx_acceptDockingClearanceRequestFrom:

// oo-3rb.174 (chunk 3): shipyard and interfaces. -localShipyard is NOT bridged: its callers edit
// the live array, which a snapshot would silently drop (they use -cxx_localShipyard).
- (void)setLocalShipyard:(NSArray*)market; // -> -cxx_setLocalShipyard:
- (NSMutableDictionary*)localInterfaces; // -> -cxx_localInterfaces (a fresh snapshot per call; its callers only read it)

@end

NSDictionary* OOMakeDockingInstructions(StationEntity* station, HPVector coords, float speed, float range, NSString* ai_message, NSString* comms_message, BOOL match_rotation, int docking_stage); // -> cxx_OOMakeDockingInstructions

#endif // STATIONENTITY_FOUNDATIONBRIDGE_H
