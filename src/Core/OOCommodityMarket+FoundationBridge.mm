/*

OOCommodityMarket+FoundationBridge.mm

TRANSITIONAL: see OOCommodityMarket+FoundationBridge.h. Each method forwards to its cxx_
counterpart and converts arguments and results at the boundary (nil for nil; property-list data
through oo::PListFrom / oo::ObjectFromPList).

*/

#import "OOCommodityMarket.h" // declares the bridge category at its end
#import "OOFoundationBridge.h"

@implementation OOCommodityMarket (OOFoundationBridge)

- (void)setGood:(OOCommodityType)key withInfo:(NSDictionary*)info
{
    [self cxx_setGood:oo::StdString(key) withInfo:oo::PListFrom(info)];
}

- (BOOL)setPrice:(OOCreditsQuantity)price forGood:(OOCommodityType)good
{
    return [self cxx_setPrice:price forGood:oo::StdString(good)];
}

- (BOOL)setQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
    return [self cxx_setQuantity:quantity forGood:oo::StdString(good)];
}

- (BOOL)addQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
    return [self cxx_addQuantity:quantity forGood:oo::StdString(good)];
}

- (BOOL)removeQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
    return [self cxx_removeQuantity:quantity forGood:oo::StdString(good)];
}

- (BOOL)setComment:(NSString*)comment forGood:(OOCommodityType)good
{
    return [self cxx_setComment:oo::StdString(comment) forGood:oo::StdString(good)];
}

- (BOOL)setShortComment:(NSString*)comment forGood:(OOCommodityType)good
{
    return [self cxx_setShortComment:oo::StdString(comment) forGood:oo::StdString(good)];
}

- (NSString*)nameForGood:(OOCommodityType)good
{
    return oo::NSStringOrNil([self cxx_nameForGood:oo::StdString(good)]);
}

- (NSString*)commentForGood:(OOCommodityType)good
{
    return oo::NSStringOrNil([self cxx_commentForGood:oo::StdString(good)]);
}

- (NSString*)shortCommentForGood:(OOCommodityType)good
{
    return oo::NSStringOrNil([self cxx_shortCommentForGood:oo::StdString(good)]);
}

- (OOCreditsQuantity)priceForGood:(OOCommodityType)good
{
    return [self cxx_priceForGood:oo::StdString(good)];
}

- (OOCargoQuantity)quantityForGood:(OOCommodityType)good
{
    return [self cxx_quantityForGood:oo::StdString(good)];
}

- (NSUInteger)exportLegalityForGood:(OOCommodityType)good
{
    return [self cxx_exportLegalityForGood:oo::StdString(good)];
}

- (NSUInteger)importLegalityForGood:(OOCommodityType)good
{
    return [self cxx_importLegalityForGood:oo::StdString(good)];
}

- (OOCargoQuantity)capacityForGood:(OOCommodityType)good
{
    return [self cxx_capacityForGood:oo::StdString(good)];
}

- (float)trumbleOpinionForGood:(OOCommodityType)good
{
    return [self cxx_trumbleOpinionForGood:oo::StdString(good)];
}

- (NSDictionary*)definitionForGood:(OOCommodityType)good
{
    return oo::ObjectFromPList([self cxx_definitionForGood:oo::StdString(good)]);
}

- (NSArray*)savePlayerAmounts
{
    return oo::ObjectFromPList([self cxx_savePlayerAmounts]);
}

- (void)loadPlayerAmounts:(NSArray*)amounts
{
    [self cxx_loadPlayerAmounts:oo::PListFrom(amounts)];
}

- (NSArray*)saveStationAmounts
{
    return oo::ObjectFromPList([self cxx_saveStationAmounts]);
}

- (void)loadStationAmounts:(NSArray*)amounts
{
    [self cxx_loadStationAmounts:oo::PListFrom(amounts)];
}

@end
