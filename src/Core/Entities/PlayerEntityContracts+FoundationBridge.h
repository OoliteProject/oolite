/*

PlayerEntityContracts+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.179, chunk 1 of oo-ldqo's
split; the later chunks oo-3rb.180-.185 move their own selectors in). PlayerEntity (Contracts)'s
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in PlayerEntityContracts.h. It exists so that the callers in
PlayerEntity.mm, OOJSPlayer.mm and the other PlayerEntity files compile unchanged; each caller
moves to the cxx_ API in its own sweep bead. When `git grep` finds no caller of anything declared
here, the bridge bead deletes this file, PlayerEntityContracts+FoundationBridge.mm, its line in
Core/Entities/meson.build and the #import at the end of PlayerEntityContracts.h. Never add to it
outside the PlayerEntityContracts chunks; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (PlayerEntityContracts.h)

*/

// Imported only from the end of PlayerEntityContracts.h (which declares everything used here);
// never import it directly, and never import PlayerEntityContracts.h from it (a cycle).
#ifndef PLAYERENTITYCONTRACTS_FOUNDATIONBRIDGE_H
#define PLAYERENTITYCONTRACTS_FOUNDATIONBRIDGE_H

@interface PlayerEntity (ContractsFoundationBridge)

// oo-3rb.179 (chunk 1): report strings
- (NSString*)processEscapePods; // -> -cxx_processEscapePods
- (NSString*)checkPassengerContracts; // -> -cxx_checkPassengerContracts
- (void)addMessageToReport:(NSString*)report; // -> -cxx_addMessageToReport:

// oo-3rb.181 (chunk 3): passengers
- (BOOL)addPassenger:(NSString*)Name start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee advance:(double)advance risk:(unsigned)risk; // -> -cxx_addPassenger:start:destination:eta:fee:advance:risk:
- (BOOL)removePassenger:(NSString*)Name; // -> -cxx_removePassenger:

// oo-3rb.182 (chunk 4): parcels
- (BOOL)addParcel:(NSString*)Name start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee premium:(double)premium risk:(unsigned)risk; // -> -cxx_addParcel:start:destination:eta:fee:premium:risk:
- (BOOL)removeParcel:(NSString*)Name; // -> -cxx_removeParcel:

// oo-3rb.183 (chunk 5): cargo contracts and manifest lists
- (OOCargoQuantity)contractedVolumeForGood:(OOCommodityType)good; // -> -cxx_contractedVolumeForGood:
- (BOOL)awardContract:(unsigned)qty commodity:(NSString*)commodity start:(unsigned)start destination:(unsigned)destination eta:(double)eta fee:(double)fee premium:(double)premium; // -> -cxx_awardContract:commodity:start:destination:eta:fee:premium:
- (BOOL)removeContract:(NSString*)commodity destination:(unsigned)destination; // -> -cxx_removeContract:destination:
- (NSArray*)passengerList; // -> -cxx_passengerList
- (NSArray*)parcelList; // -> -cxx_parcelList
- (NSArray*)contractList; // -> -cxx_contractList

// oo-3rb.184 (chunk 6): shipyard
- (void)showShipyardModel:(NSString*)shipKey shipData:(NSDictionary*)shipDict personality:(uint16_t)personality; // -> -cxx_showShipyardModel:shipData:personality:
- (OOCreditsQuantity)priceForShipKey:(NSString*)key; // -> -cxx_priceForShipKey:
- (BOOL)replaceShipWithNamedShip:(NSString*)shipName; // -> -cxx_replaceShipWithNamedShip:

@end

#endif // PLAYERENTITYCONTRACTS_FOUNDATIONBRIDGE_H
