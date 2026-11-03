/*

OOCommodities+FoundationBridge.mm

TRANSITIONAL: see OOCommodities+FoundationBridge.h. Each method forwards to its cxx_ counterpart
and converts arguments and results at the boundary (nil for nil: a nil script name is nullopt,
since -[PlayerEntity commodityScriptNamed:] treats nil and @"" differently).

*/

#import "OOCommodities.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation OOCommodities (OOFoundationBridge)

+ (OOCommodityType)legacyCommodityType:(NSUInteger)i
{
    return oo::NSStringOrNil([self cxx_legacyCommodityType:i]);
}

- (OOCommodityMarket*)generateMarketForSystemWithEconomy:(OOEconomyID)economy andScript:(NSString*)scriptName
{
    return [self cxx_generateMarketForSystemWithEconomy:economy andScript:oo::OptionalString(scriptName)];
}

- (OOCreditsQuantity)samplePriceForCommodity:(OOCommodityType)commodity inEconomy:(OOEconomyID)economy withScript:(NSString*)scriptName inSystem:(OOSystemID)system
{
    return [self cxx_samplePriceForCommodity:oo::StdString(commodity) inEconomy:economy withScript:oo::OptionalString(scriptName) inSystem:system];
}

- (BOOL)goodDefined:(NSString*)key
{
    return [self cxx_goodDefined:oo::StdString(key)];
}

- (NSString*)goodNamed:(NSString*)name
{
    return oo::NSStringOrNil([self cxx_goodNamed:oo::StdString(name)]);
}

@end
