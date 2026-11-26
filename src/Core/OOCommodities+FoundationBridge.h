/*

OOCommodities+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-3rb.154, chunk 1 of oo-19d2).
OOCommodities' Foundation-typed API as it was before its sweep, with the same selector names and
types, forwarding to the cxx_ API in OOCommodities.h. It exists so that OOCommodities' callers
compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds
no caller of anything declared here, the bridge bead deletes this file,
OOCommodities+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOCommodities.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOCommodities.h)

*/

// Imported only from the end of OOCommodities.h (which declares everything used here); never
// import it directly, and never import OOCommodities.h from it (a cycle).
#ifndef OOCOMMODITIES_FOUNDATIONBRIDGE_H
#define OOCOMMODITIES_FOUNDATIONBRIDGE_H

@interface OOCommodities (OOFoundationBridge)

+ (OOCommodityType)legacyCommodityType:(NSUInteger)i;

- (OOCommodityMarket*)generateMarketForSystemWithEconomy:(OOEconomyID)economy andScript:(NSString*)scriptName;

- (OOCreditsQuantity)samplePriceForCommodity:(OOCommodityType)commodity inEconomy:(OOEconomyID)economy withScript:(NSString*)scriptName inSystem:(OOSystemID)system;

- (BOOL)goodDefined:(NSString*)key;
- (NSString*)goodNamed:(NSString*)name;

@end

#endif // OOCOMMODITIES_FOUNDATIONBRIDGE_H
