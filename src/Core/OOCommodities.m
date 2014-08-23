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

#import "ResourceManager.h"
#import "legacy_random.h"
#import "OOCollectionExtractors.h"

@interface OOCommodities (OOPrivate)

- (OOCargoQuantity) generateQuantityForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;
- (OOCreditsQuantity) generatePriceForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;

- (float) economicBiasForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;

@end


@implementation OOCommodities

- (id) init
{
	self = [super init];
	if (self == nil)  return nil;

	NSDictionary *rawCommodityLists = [ResourceManager dictionaryFromFilesNamed:@"trade-goods.plist" inFolder:@"Config" andMerge:YES];
/* // TODO: validation of inputs
	// TODO: convert 't', 'kg', 'g' in container to 0, 1, 2
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


- (OOCommodityMarket *) generateMarketForSystemWithEconomy:(OOEconomyID)economy
{
	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];

	NSString *commodity = nil;
	NSDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [_commodityLists oo_dictionaryForKey:commodity];
		OOCargoQuantity q = [self generateQuantityForGood:good inEconomy:economy];
		OOCreditsQuantity p = [self generatePriceForGood:good inEconomy:economy];
		[market setGood:commodity toPrice:p andQuantity:q withInfo:good];
	}
	return [market autorelease];
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
		return (OOCreditsQuantity)base;
	}
}


// positive = exporter; negative = importer; range -1.0 .. +1.0
- (float) economicBiasForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy
{
	OOEconomyID exporter = [good oo_intForKey:kOOCommodityPeakExport];
	OOEconomyID importer = [good oo_intForKey:kOOCommodityPeakImport];
	
	int exDiff = abs(economy-exporter)*2;
	int imDiff = abs(economy-importer)*2;
	int distance = abs(exporter-importer);

	if (exDiff == imDiff)
	{
		// neutral economy
		return 0.0;
	}
	else if (exDiff > imDiff)
	{
		// closer to the importer, so return -ve
		return -((float)imDiff/(float)distance);
	}
	else
	{
		// closer to the exporter, so return -ve
		return ((float)exDiff/(float)distance);
	}
}


@end
