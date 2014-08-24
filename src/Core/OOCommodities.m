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

#import "ResourceManager.h"
#import "legacy_random.h"
#import "OOCollectionExtractors.h"

@interface OOCommodities (OOPrivate)

- (OOCargoQuantity) generateQuantityForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;
- (OOCreditsQuantity) generatePriceForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;

- (float) economicBiasForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;

@end


@implementation OOCommodities

/* Older save games store some commodity information by its old index. */
+ (OOCommodityType) legacyCommodityType:(NSUInteger)i
{
	switch (i)
	{
	case 0:
		return @"food";
	case 1:
		return @"textiles";
	case 2:
		return @"radioactives";
	case 3:
		return @"slaves";
	case 4:
		return @"liquor_wines";
	case 5:
		return @"luxuries";
	case 6:
		return @"narcotics";
	case 7:
		return @"computers";
	case 8:
		return @"machinery";
	case 9:
		return @"alloys";
	case 10:
		return @"firearms";
	case 11:
		return @"furs";
	case 12:
		return @"minerals";
	case 13:
		return @"gold";
	case 14:
		return @"platinum";
	case 15:
		return @"gem_stones";
	case 16:
		return @"alien_items";
	}
	// shouldn't happen
	return @"food";
}



- (id) init
{
	self = [super init];
	if (self == nil)  return nil;

	NSDictionary *rawCommodityLists = [ResourceManager dictionaryFromFilesNamed:@"trade-goods.plist" inFolder:@"Config" andMerge:YES];
/* // TODO: validation of inputs
	// TODO: convert 't', 'kg', 'g' in quantity_unit to 0, 1, 2
	// for now it needs them entering as the ints
	NSMutableDictionary *validatedCommodityLists = [NSMutableDictionary dictionaryWithCapacity:[rawCommodityLists count]];
	NSString *commodityName = nil;
	foreachkey (commodityName, rawCommodityLists)
	{
		// validate
	}

//	_commodityLists = [[NSDictionary dictionaryWithDictionary:validatedCommodityLists] retain];
*/

	_commodityLists = [[NSDictionary dictionaryWithDictionary:rawCommodityLists] retain];

	return self;
}


- (void) dealloc
{
	DESTROY(_commodityLists);


	[super dealloc];
}


- (OOCommodityMarket *) generateManifestForPlayer
{
	return [self generateBlankMarket];
}


- (OOCommodityMarket *) generateBlankMarket
{
	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];

	NSString *commodity = nil;
	NSDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [_commodityLists oo_dictionaryForKey:commodity];
		[market setGood:commodity toPrice:0 andQuantity:0 withInfo:good];
	}
	return [market autorelease];
}


- (OOCommodityMarket *) generateMarketForSystemWithEconomy:(OOEconomyID)economy
{
	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];

	NSString *commodity = nil;
	NSDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [_commodityLists oo_dictionaryForKey:commodity];
		OOCargoQuantity q = [self generateQuantityForGood:good inEconomy:economy];
		// main system market limited to 127 units of each item
		if (q > MAIN_SYSTEM_MARKET_LIMIT)
		{
			q = MAIN_SYSTEM_MARKET_LIMIT;
		}
		OOCreditsQuantity p = [self generatePriceForGood:good inEconomy:economy];
		[market setGood:commodity toPrice:p andQuantity:q withInfo:good];
	}
	return [market autorelease];
}


- (NSUInteger) count
{
	return [_commodityLists count];
}


- (NSArray *) goods
{
	return [_commodityLists allKeys];
}


- (BOOL) goodDefined:(NSString *)key
{
	return ([_commodityLists oo_dictionaryForKey:key] != nil);
}


- (NSString *) getRandomCommodity
{
	NSArray *keys = [_commodityLists allKeys];
	NSUInteger idx = Ranrot() % [keys count];
	return [keys oo_stringAtIndex:idx];
}


- (OOMassUnit) massUnitForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityLists oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return UNITS_TONS;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityContainer];
}




- (OOCargoQuantity) generateQuantityForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy
{
	float bias = [self economicBiasForGood:good inEconomy:economy];

	float base = [good oo_floatForKey:kOOCommodityQuantityAverage];
	float econ = base * [good oo_floatForKey:kOOCommodityQuantityEconomic] * bias;
	float random = base * [good oo_floatForKey:kOOCommodityQuantityRandom] * (randf() - randf());
	base += econ + random;
	if (base < 0.0)
	{
		return 0;
	}
	else
	{
		return (OOCargoQuantity)base;
	}
}


- (OOCreditsQuantity) generatePriceForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy
{
	float bias = [self economicBiasForGood:good inEconomy:economy];

	float base = [good oo_floatForKey:kOOCommodityPriceAverage];
	float econ = base * [good oo_floatForKey:kOOCommodityPriceEconomic] * -bias;
	float random = base * [good oo_floatForKey:kOOCommodityPriceRandom] * (randf() - randf());
	base += econ + random;
	if (base < 0.0)
	{
		return 0;
	}
	else
	{
		return (OOCreditsQuantity)base;
	}
}


- (OOCreditsQuantity) samplePriceForCommodity:(OOCommodityType)commodity inEconomy:(OOEconomyID)economy
{
	NSDictionary *data = [_commodityLists oo_dictionaryForKey:commodity];
	if (data == nil)
	{
		return 0;
	}
	return [self generatePriceForGood:data inEconomy:economy];
}


// positive = exporter; negative = importer; range -1.0 .. +1.0
- (float) economicBiasForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy
{
	OOEconomyID exporter = [good oo_intForKey:kOOCommodityPeakExport];
	OOEconomyID importer = [good oo_intForKey:kOOCommodityPeakImport];
	
	// *2 and /2 to work in ints at this stage
	int exDiff = abs(economy-exporter)*2;
	int imDiff = abs(economy-importer)*2;
	int distance = (exDiff+imDiff)/2;

	if (exDiff == imDiff)
	{
		// neutral economy
		return 0.0;
	}
	else if (exDiff > imDiff)
	{
		// closer to the importer, so return -ve
		return -(1.0-((float)imDiff/(float)distance));
	}
	else
	{
		// closer to the exporter, so return +ve
		return 1.0-((float)exDiff/(float)distance);
	}
}


@end
