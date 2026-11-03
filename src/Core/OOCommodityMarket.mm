/*

OOCommodityMarket.m

Oolite
Copyright (C) 2004-2014 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCommodityMarket.h"
#import "OOCommodities.h"
#import "OOPListView.h"
#import "OOStringExpander.h"

static NSComparisonResult goodsSorter(id a, id b, void* context);

@implementation OOCommodityMarket

- (id)init
{
    self = [super init];
    if (self == nil)
        return nil;

    _commodityList = [[NSMutableDictionary dictionaryWithCapacity:24] retain];

    _sortedKeys = nil;

    return self;
}

- (void)dealloc
{
    DESTROY(_commodityList);
    DESTROY(_sortedKeys);
    [super dealloc];
}

- (NSUInteger)count
{
    return [_commodityList count];
}

- (void)setGood:(OOCommodityType)key withInfo:(NSDictionary*)info
{
    NSMutableDictionary* definition = [NSMutableDictionary dictionaryWithDictionary:info];
    [_commodityList setObject:definition forKey:key];
    DESTROY(_sortedKeys); // reset
}

- (NSArray*)goods
{
    if (_sortedKeys == nil) {
        NSArray* keys = [_commodityList allKeys];
        _sortedKeys = [[keys sortedArrayUsingFunction:OOSortFunction(goodsSorter) context:_commodityList] retain];
    }
    return _sortedKeys;
}

- (NSDictionary*)dictionaryForScripting
{
    return [[_commodityList copy] autorelease];
}

- (BOOL)setPrice:(OOCreditsQuantity)price forGood:(OOCommodityType)good
{
    NSMutableDictionary* definition = oo::PListView(_commodityList).get<NSMutableDictionary*>(good);
    if (definition == nil) {
        return NO;
    }
    [definition oo_setUnsignedInteger:price forKey:kOOCommodityPriceCurrent];
    return YES;
}

- (BOOL)setQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
    NSMutableDictionary* definition = oo::PListView(_commodityList).get<NSMutableDictionary*>(good);
    if (definition == nil || quantity > [self capacityForGood:good]) {
        return NO;
    }
    [definition oo_setUnsignedInteger:quantity forKey:kOOCommodityQuantityCurrent];
    return YES;
}

- (BOOL)addQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
    OOCargoQuantity current = [self quantityForGood:good];
    if (current + quantity > [self capacityForGood:good]) {
        return NO;
    }
    [self setQuantity:(current + quantity) forGood:good];
    return YES;
}

- (BOOL)removeQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
    OOCargoQuantity current = [self quantityForGood:good];
    if (current < quantity) {
        return NO;
    }
    [self setQuantity:(current - quantity) forGood:good];
    return YES;
}

- (void)removeAllGoods
{
    OOCommodityType good = nil;
    foreach (good, [_commodityList allKeys]) {
        [self setQuantity:0 forGood:good];
    }
}

- (BOOL)setComment:(NSString*)comment forGood:(OOCommodityType)good
{
    NSMutableDictionary* definition = oo::PListView(_commodityList).get<NSMutableDictionary*>(good);
    if (definition == nil) {
        return NO;
    }
    [definition setObject:comment forKey:kOOCommodityComment];
    return YES;
}

- (BOOL)setShortComment:(NSString*)comment forGood:(OOCommodityType)good
{
    NSMutableDictionary* definition = oo::PListView(_commodityList).get<NSMutableDictionary*>(good);
    if (definition == nil) {
        return NO;
    }
    [definition setObject:comment forKey:kOOCommodityShortComment];
    return YES;
}

- (NSString*)nameForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return OOExpand(@"[oolite-unknown-commodity-name]");
    }
    return OOExpand(oo::PListView(definition).get<NSString*>(kOOCommodityName, @"[oolite-unknown-commodity-name]"));
}

- (NSString*)commentForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return OOExpand(@"[oolite-unknown-commodity-name]");
    }
    return OOExpand(oo::PListView(definition).get<NSString*>(kOOCommodityComment, @"[oolite-commodity-no-comment]"));
}

- (NSString*)shortCommentForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return OOExpand(@"[oolite-unknown-commodity-name]");
    }
    return OOExpand(oo::PListView(definition).get<NSString*>(kOOCommodityShortComment, @"[oolite-commodity-no-short-comment]"));
}

- (OOCreditsQuantity)priceForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return 0;
    }
    return oo::PListView(definition).get<NSUInteger>(kOOCommodityPriceCurrent);
}

- (OOCargoQuantity)quantityForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return 0;
    }
    return oo::PListView(definition).get<unsigned int>(kOOCommodityQuantityCurrent);
}

- (OOMassUnit)massUnitForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return UNITS_TONS;
    }
    return OOMassUnitFromNumber(oo::PListView(definition).get<unsigned int>(kOOCommodityContainer));
}

- (NSUInteger)exportLegalityForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return 0;
    }
    return oo::PListView(definition).get<NSUInteger>(kOOCommodityLegalityExport);
}

- (NSUInteger)importLegalityForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return 0;
    }
    return oo::PListView(definition).get<NSUInteger>(kOOCommodityLegalityImport);
}

- (OOCargoQuantity)capacityForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return 0;
    }
    // should only be undefined for main system markets, not secondary stations
    // meaningless for player ship, though
    return oo::PListView(definition).get<unsigned int>(kOOCommodityCapacity, MAIN_SYSTEM_MARKET_LIMIT);
}

- (float)trumbleOpinionForGood:(OOCommodityType)good
{
    NSDictionary* definition = oo::PListView(_commodityList).get<NSDictionary*>(good);
    if (definition == nil) {
        return 0;
    }
    return oo::PListView(definition).get<float>(kOOCommodityTrumbleOpinion);
}

- (NSDictionary*)definitionForGood:(OOCommodityType)good
{
    return [[oo::PListView(_commodityList).get<NSDictionary*>(good) copy] autorelease];
}

- (NSArray*)savePlayerAmounts
{
    NSMutableArray* amounts = [NSMutableArray arrayWithCapacity:[self count]];
    OOCommodityType good = nil;
    foreach (good, [self goods]) {
        [amounts addObject:[NSArray arrayWithObjects:good, [NSNumber numberWithUnsignedInt:[self quantityForGood:good]], nil]];
    }
    return [NSArray arrayWithArray:amounts];
}

- (void)loadPlayerAmounts:(NSArray*)amounts
{
    OOCargoQuantity q;
    BOOL loadedOK;
    NSString* good = nil;
    foreach (good, [self goods]) {
        // make sure that any goods not defined in the save game are zeroed
        [self setQuantity:0 forGood:good];
    }

    NSArray* loaded = nil;
    foreach (loaded, amounts) {
        loadedOK = NO;
        good = oo::PListView(loaded).at<NSString*>(0);
        q = oo::PListView(loaded).at<unsigned int>(1);
        // old save games might have more in the array, but we don't care
        if (![self setQuantity:q forGood:good]) {
            // then it's an array from a 1.80-or-earlier save game and
            // the good name is the description string (maybe a
            // translated one)
            OOCommodityType key = nil;
            foreach (key, [self goods]) {
                if ([good isEqualToString:[self nameForGood:key]]) {
                    [self setQuantity:q forGood:key];
                    loadedOK = YES;
                    break;
                }
            }
        } else {
            loadedOK = YES;
        }
        if (!loadedOK) {
            OOLog(@"setCommanderDataFromDictionary.warning.cargo", @"Cargo %@ (%u units) could not be loaded from the saved game, as it is no longer defined", good, q);
        }
    }
}

- (NSArray*)saveStationAmounts
{
    NSMutableArray* amounts = [NSMutableArray arrayWithCapacity:[self count]];
    OOCommodityType good = nil;
    foreach (good, [self goods]) {
        [amounts addObject:[NSArray arrayWithObjects:good, [NSNumber numberWithUnsignedInt:[self quantityForGood:good]], [NSNumber numberWithUnsignedInteger:[self priceForGood:good]], nil]];
    }
    return [NSArray arrayWithArray:amounts];
}

- (void)loadStationAmounts:(NSArray*)amounts
{
    OOCargoQuantity q;
    OOCreditsQuantity p;
    BOOL loadedOK;
    NSString* good = nil;

    NSArray* loaded = nil;
    foreach (loaded, amounts) {
        loadedOK = NO;
        good = oo::PListView(loaded).at<NSString*>(0);
        q = oo::PListView(loaded).at<unsigned int>(1);
        p = oo::PListView(loaded).at<NSUInteger>(2);
        // old save games might have more in the array, but we don't care
        if (![self setQuantity:q forGood:good]) {
            // then it's an array from a 1.80-or-earlier save game and
            // the good name is the description string (maybe a
            // translated one)
            OOCommodityType key = nil;
            foreach (key, [self goods]) {
                if ([good isEqualToString:[self nameForGood:key]]) {
                    [self setQuantity:q forGood:key];
                    [self setPrice:p forGood:key];
                    loadedOK = YES;
                    break;
                }
            }
        } else {
            [self setPrice:p forGood:good];
            loadedOK = YES;
        }
        if (!loadedOK) {
            OOLog(@"load.warning.cargo", @"Station market good %@ (%u units) could not be loaded from the saved game, as it is no longer defined", good, q);
        }
    }
}

@end

static NSComparisonResult goodsSorter(id a, id b, void* context)
{
    NSDictionary* commodityList = (NSDictionary*)context;
    int v1 = oo::PListView(oo::PListView(commodityList).get<NSDictionary*>((NSString*)a)).get<int>(kOOCommoditySortOrder);
    int v2 = oo::PListView(oo::PListView(commodityList).get<NSDictionary*>((NSString*)b)).get<int>(kOOCommoditySortOrder);

    if (v1 < v2) {
        return NSOrderedAscending;
    } else if (v1 > v2) {
        return NSOrderedDescending;
    } else {
        return NSOrderedSame;
    }
}
