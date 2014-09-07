/*

OOCommodities.m

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

#import "OOCommodities.h"
#import "OOCommodityMarket.h"
#import "OOCollectionExtractors.h"
#import "OOStringExpander.h"


NSComparisonResult goodsSorter(NSString *a, NSString *b, void *context);


@implementation OOCommodityMarket

- (id) init
{
	self = [super init];
	if (self == nil)  return nil;

	_commodityList = [[NSMutableDictionary dictionaryWithCapacity:24] retain];

	_sortedKeys = nil;

	return self;
}


- (void) dealloc
{
	DESTROY(_commodityList);
	DESTROY(_sortedKeys);
	[super dealloc];
}


- (NSUInteger) count
{
	return [_commodityList count];
}


- (void) setGood:(OOCommodityType)key withInfo:(NSDictionary *)info
{
	NSMutableDictionary *definition = [NSMutableDictionary dictionaryWithDictionary:info];
	[_commodityList setObject:definition forKey:key];
	DESTROY(_sortedKeys); // reset
}


- (NSArray *) goods
{
	if (_sortedKeys == nil)
	{
		NSArray *keys = [_commodityList allKeys];
		_sortedKeys = [[keys sortedArrayUsingFunction:goodsSorter context:_commodityList] retain];
	}
	return _sortedKeys;
}


- (NSDictionary *) dictionaryForScripting
{
	return [[_commodityList copy] autorelease];
}


- (BOOL) setPrice:(OOCreditsQuantity)price forGood:(OOCommodityType)good
{
	NSMutableDictionary *definition = [_commodityList oo_mutableDictionaryForKey:good];
	if (definition == nil)
	{
		return NO;
	}
	[definition oo_setUnsignedInteger:price forKey:kOOCommodityPriceCurrent];
	return YES;
}


- (BOOL) setQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
	NSMutableDictionary *definition = [_commodityList oo_mutableDictionaryForKey:good];
	if (definition == nil || quantity > [self capacityForGood:good])
	{
		return NO;
	}
	[definition oo_setUnsignedInteger:quantity forKey:kOOCommodityQuantityCurrent];
	return YES;
}


- (BOOL) addQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
	OOCargoQuantity current = [self quantityForGood:good];
	if (current + quantity > [self capacityForGood:good])
	{
		return NO;
	}
	[self setQuantity:(current+quantity) forGood:good];
	return YES;
}


- (BOOL) removeQuantity:(OOCargoQuantity)quantity forGood:(OOCommodityType)good
{
	OOCargoQuantity current = [self quantityForGood:good];
	if (current < quantity)
	{
		return NO;
	}
	[self setQuantity:(current-quantity) forGood:good];
	return YES;
}


- (void) removeAllGoods
{
	OOCommodityType good = nil;
	foreach (good, [_commodityList allKeys])
	{
		[self setQuantity:0 forGood:good];
	}
}


- (BOOL) setComment:(NSString *)comment forGood:(OOCommodityType)good
{
	NSMutableDictionary *definition = [_commodityList oo_mutableDictionaryForKey:good];
	if (definition == nil)
	{
		return NO;
	}
	[definition setObject:comment forKey:kOOCommodityComment];
	return YES;
}



- (NSString *) nameForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return OOExpand(@"[oolite-unknown-commodity-name]");
	}
	return OOExpand([definition oo_stringForKey:kOOCommodityName defaultValue:@"[oolite-unknown-commodity-name]"]);
}


- (NSString *) commentForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return OOExpand(@"[oolite-unknown-commodity-name]");
	}
	return OOExpand([definition oo_stringForKey:kOOCommodityComment defaultValue:@"[oolite-commodity-no-comment]"]);
}


- (OOCreditsQuantity) priceForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityPriceCurrent];
}


- (OOCargoQuantity) quantityForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityQuantityCurrent];
}


- (OOMassUnit) massUnitForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return UNITS_TONS;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityContainer];
}


- (NSUInteger) exportLegalityForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityLegalityExport];
}


- (NSUInteger) importLegalityForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityLegalityImport];
}


- (OOCargoQuantity) capacityForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	// should only be undefined for main system markets, not secondary stations
	// meaningless for player ship, though
	return [definition oo_unsignedIntegerForKey:kOOCommodityCapacity defaultValue:MAIN_SYSTEM_MARKET_LIMIT];
}


- (float) trumbleOpinionForGood:(OOCommodityType)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_floatForKey:kOOCommodityTrumbleOpinion];
}


- (NSDictionary *) definitionForGood:(OOCommodityType)good
{
	return [[[_commodityList oo_dictionaryForKey:good] copy] autorelease];
}



- (NSArray *) savePlayerAmounts
{
	NSMutableArray *amounts = [NSMutableArray arrayWithCapacity:[self count]];
	OOCommodityType good = nil;
	foreach (good, [self goods])
	{
		[amounts addObject:[NSArray arrayWithObjects:good,[NSNumber numberWithUnsignedInt:[self quantityForGood:good]],nil]];
	}
	return [NSArray arrayWithArray:amounts];
}


- (void) loadPlayerAmounts:(NSArray *)amounts
{
	OOCargoQuantity q;
	BOOL 			loadedOK;
	NSString 		*good = nil;
	foreach (good, [self goods])
	{
		// make sure that any goods not defined in the save game are zeroed
		[self setQuantity:0 forGood:good];
	}


	NSArray *loaded = nil;
	foreach (loaded, amounts)
	{
		loadedOK = NO;
		good = [loaded oo_stringAtIndex:0];
		q = [loaded oo_unsignedIntegerAtIndex:1];
		// old save games might have more in the array, but we don't care
		if (![self setQuantity:q forGood:good])
		{
			// then it's an array from a 1.80-or-earlier save game and
			// the good name is the description string (maybe a
			// translated one)
			OOCommodityType key = nil;
			foreach (key, [self goods])
			{
				if ([good isEqualToString:[self nameForGood:key]])
				{
					[self setQuantity:q forGood:key];
					loadedOK = YES;
					break;
				}
			}
		}
		else
		{
			loadedOK = YES;
		}
		if (!loadedOK)
		{
			OOLog(@"setCommanderDataFromDictionary.warning.cargo",@"Cargo %@ (%u units) could not be loaded from the saved game, as it is no longer defined",good,q);
		}
	}
}


- (NSArray *) saveStationAmounts
{
	NSMutableArray *amounts = [NSMutableArray arrayWithCapacity:[self count]];
	OOCommodityType good = nil;
	foreach (good, [self goods])
	{
		[amounts addObject:[NSArray arrayWithObjects:good,[NSNumber numberWithUnsignedInt:[self quantityForGood:good]],[NSNumber numberWithUnsignedInt:[self priceForGood:good]],nil]];
	}
	return [NSArray arrayWithArray:amounts];
}


- (void) loadStationAmounts:(NSArray *)amounts
{
	OOCargoQuantity 	q;
	OOCreditsQuantity	p;
	BOOL 				loadedOK;
	NSString 			*good = nil;

	NSArray *loaded = nil;
	foreach (loaded, amounts)
	{
		loadedOK = NO;
		good = [loaded oo_stringAtIndex:0];
		q = [loaded oo_unsignedIntegerAtIndex:1];
		p = [loaded oo_unsignedIntegerAtIndex:2];
		// old save games might have more in the array, but we don't care
		if (![self setQuantity:q forGood:good])
		{
			// then it's an array from a 1.80-or-earlier save game and
			// the good name is the description string (maybe a
			// translated one)
			OOCommodityType key = nil;
			foreach (key, [self goods])
			{
				if ([good isEqualToString:[self nameForGood:key]])
				{
					[self setQuantity:q forGood:key];
					[self setPrice:p forGood:key];
					loadedOK = YES;
					break;
				}
			}
		}
		else
		{
			[self setPrice:p forGood:good];
			loadedOK = YES;
		}
		if (!loadedOK)
		{
			OOLog(@"load.warning.cargo",@"Station market good %@ (%u units) could not be loaded from the saved game, as it is no longer defined",good,q);
		}
	}
}


@end


NSComparisonResult goodsSorter(NSString *a, NSString *b, void *context)
{
	NSDictionary *commodityList = (NSDictionary *)context;
	int v1 = [[commodityList oo_dictionaryForKey:a] oo_intForKey:kOOCommoditySortOrder];
    int v2 = [[commodityList oo_dictionaryForKey:b] oo_intForKey:kOOCommoditySortOrder];

    if (v1 < v2)
	{
        return NSOrderedAscending;
	}
    else if (v1 > v2)
	{
        return NSOrderedDescending;
	}
    else
	{
        return NSOrderedSame;
	}
}
