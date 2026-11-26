/*

OOCommodityMarket+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-rvit). OOCommodityMarket's
Foundation-typed API as it was before its sweep, with the same selector names and types,
forwarding to the cxx_ API in OOCommodityMarket.h. It exists so that OOCommodityMarket's callers
compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds
no caller of anything declared here, the bridge bead deletes this file,
OOCommodityMarket+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOCommodityMarket.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOCommodityMarket.h)

*/

// Imported only from the end of OOCommodityMarket.h (which declares everything used here); never
// import it directly, and never import OOCommodityMarket.h from it (a cycle).
#ifndef OOCOMMODITYMARKET_FOUNDATIONBRIDGE_H
#define OOCOMMODITYMARKET_FOUNDATIONBRIDGE_H

@interface OOCommodityMarket (OOFoundationBridge)

- (void)setGood:(OOCommodityType)key withInfo:(NSDictionary*)info;

- (BOOL)setPrice:(OOCreditsQuantity)price forGood:(OOCommodityType)good;
- (BOOL)setQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good;
- (BOOL)addQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good;
- (BOOL)removeQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good;
- (BOOL)setComment:(NSString*)comment forGood:(OOCommodityType)good;
- (BOOL)setShortComment:(NSString*)comment forGood:(OOCommodityType)good;

- (NSString*)nameForGood:(OOCommodityType)good;
- (NSString*)commentForGood:(OOCommodityType)good;
- (NSString*)shortCommentForGood:(OOCommodityType)good;
- (OOCreditsQuantity)priceForGood:(OOCommodityType)good;
- (OOCargoQuantity)quantityForGood:(OOCommodityType)good;
- (NSUInteger)exportLegalityForGood:(OOCommodityType)good;
- (NSUInteger)importLegalityForGood:(OOCommodityType)good;
- (OOCargoQuantity)capacityForGood:(OOCommodityType)good;
- (float)trumbleOpinionForGood:(OOCommodityType)good;

- (NSDictionary*)definitionForGood:(OOCommodityType)good;

- (NSArray*)savePlayerAmounts;
- (void)loadPlayerAmounts:(NSArray*)amounts;

- (NSArray*)saveStationAmounts;
- (void)loadStationAmounts:(NSArray*)amounts;

@end

#endif // OOCOMMODITYMARKET_FOUNDATIONBRIDGE_H
