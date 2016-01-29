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

#import "StationEntity.h"
#import "ResourceManager.h"
#import "legacy_random.h"
#import "OOCollectionExtractors.h"
#import "OOJSScript.h"
#import "PlayerEntity.h"
#import "OOStringExpander.h"

@interface OOCommodities (OOPrivate)

- (NSDictionary *) modifyGood:(NSDictionary *)good withScript:(OOScript *)script atStation:(StationEntity *)station inSystem:(OOSystemID)system localMode:(BOOL)local;
- (NSDictionary *) createDefinitionFrom:(NSDictionary *) good price:(OOCreditsQuantity)p andQuantity:(OOCargoQuantity)q forKey:(OOCommodityType)key atStation:(StationEntity *)station inSystem:(OOSystemID)system;


- (OOCargoQuantity) generateQuantityForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;
- (OOCreditsQuantity) generatePriceForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;

- (float) economicBiasForGood:(NSDictionary *)good inEconomy:(OOEconomyID)economy;
- (NSDictionary *) firstModifierForGood:(OOCommodityType)good inClasses:(NSArray *)classes fromList:(NSArray *)definitions;
- (OOCreditsQuantity) adjustPrice:(OOCreditsQuantity)price byRule:(NSDictionary *)rule;
- (OOCargoQuantity) adjustQuantity:(OOCargoQuantity)quantity byRule:(NSDictionary *)rule;
- (NSDictionary *) updateInfoFor:(NSDictionary *)good byRule:(NSDictionary *)rule maxCapacity:(OOCargoQuantity)maxCapacity;

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

	NSDictionary *rawCommodityLists = [ResourceManager dictionaryFromFilesNamed:@"trade-goods.plist" inFolder:@"Config" mergeMode:MERGE_SMART cache:YES];
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
	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];

	NSString *commodity = nil;
	NSMutableDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [NSMutableDictionary dictionaryWithDictionary:[_commodityLists oo_dictionaryForKey:commodity]];
		[good oo_setUnsignedInteger:0 forKey:kOOCommodityPriceCurrent];
		[good oo_setUnsignedInteger:0 forKey:kOOCommodityQuantityCurrent];
		/* The actual capacity of the player ship is a total, not
		 * per-good, so is managed separately through PlayerEntity */
		[good oo_setUnsignedInteger:UINT32_MAX forKey:kOOCommodityCapacity];
		[good setObject:commodity forKey:kOOCommodityKey];
		
		[market setGood:commodity withInfo:good];
	}
	return [market autorelease];
}


- (OOCommodityMarket *) generateBlankMarket
{
	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];

	NSString *commodity = nil;
	NSMutableDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [NSMutableDictionary dictionaryWithDictionary:[_commodityLists oo_dictionaryForKey:commodity]];
		[good oo_setUnsignedInteger:0 forKey:kOOCommodityPriceCurrent];
		[good oo_setUnsignedInteger:0 forKey:kOOCommodityQuantityCurrent];
		[good oo_setUnsignedInteger:0 forKey:kOOCommodityCapacity];
		[good setObject:commodity forKey:kOOCommodityKey];
		
		[market setGood:commodity withInfo:good];
	}
	return [market autorelease];
}


- (NSDictionary *) createDefinitionFrom:(NSDictionary *) good price:(OOCreditsQuantity)p andQuantity:(OOCargoQuantity)q forKey:(OOCommodityType)key atStation:(StationEntity *)station inSystem:(OOSystemID)system
{
	NSMutableDictionary *definition = [NSMutableDictionary dictionaryWithDictionary:good];
	[definition oo_setUnsignedInteger:p forKey:kOOCommodityPriceCurrent];
	[definition oo_setUnsignedInteger:q forKey:kOOCommodityQuantityCurrent];
	if (station == nil && [definition objectForKey:kOOCommodityCapacity] == nil)
	{
		[definition oo_setInteger:MAIN_SYSTEM_MARKET_LIMIT forKey:kOOCommodityCapacity];
	}

	[definition setObject:key forKey:kOOCommodityKey];
	if (station != nil && ![station marketMonitored])
	{
		// clear legal status indicators if the market is not monitored
		[definition oo_setUnsignedInteger:0 forKey:kOOCommodityLegalityExport];		
		[definition oo_setUnsignedInteger:0 forKey:kOOCommodityLegalityImport];
	}

	NSString *goodScriptName = [definition oo_stringForKey:kOOCommodityScript];
	if (goodScriptName == nil)
	{
		return definition;
	}
	OOScript *goodScript = [PLAYER commodityScriptNamed:goodScriptName];
	if (goodScript == nil)
	{
		return definition;
	}
	return [self modifyGood:definition withScript:goodScript atStation:station inSystem:system localMode:NO];
}


- (NSDictionary *) modifyGood:(NSDictionary *)good withScript:(OOScript *)script atStation:(StationEntity *)station inSystem:(OOSystemID)system localMode:(BOOL)localMode
{
	NSDictionary 		*result = nil;
	JSContext			*context = OOJSAcquireContext();
	jsval				rval;
	jsval				args[] = { 
		[good oo_jsValueInContext:context], 
		[station oo_jsValueInContext:context], 
		INT_TO_JSVAL(system) 
	};
	BOOL				OK = YES;
	NSString			*errorType = nil;

	if (localMode)
	{
		errorType = @"local";
		OK = [script callMethod:OOJSID("updateLocalCommodityDefinition")
					  inContext:context
				  withArguments:args
						  count:3
						 result:&rval];
	}
	else
	{
		errorType = @"general";
		OK = [script callMethod:OOJSID("updateGeneralCommodityDefinition")
					  inContext:context
				  withArguments:args
						  count:3
						 result:&rval];
	}

	if (!OK)
	{
		OOLog(@"script.commodityScript.error",@"Could not update %@ commodity definition for %@ - unable to call updateLocalCommodityDefinition",errorType,[good oo_stringForKey:kOOCommodityName]);
		OOJSRelinquishContext(context);
		return good;
	}

	if (!JSVAL_IS_OBJECT(rval))
	{
		OOLog(@"script.commodityScript.error",@"Could not update %@ commodity definition for %@ - return value invalid",errorType,[good oo_stringForKey:kOOCommodityKey]);
		OOJSRelinquishContext(context);
		return good;
	}

	result = OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(rval));
	OOJSRelinquishContext(context);
	if (![result isKindOfClass:[NSDictionary class]])
	{
		OOLog(@"script.commodityScript.error",@"Could not update %@ commodity definition for %@ - return value invalid",errorType,[good oo_stringForKey:kOOCommodityKey]);
		return good;
	}
	
	return result;
}


- (OOCommodityMarket *) generateMarketForSystemWithEconomy:(OOEconomyID)economy andScript:(NSString *)scriptName
{
	OOScript *script = [PLAYER commodityScriptNamed:scriptName];

	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];

	NSString *commodity = nil;
	NSDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [_commodityLists oo_dictionaryForKey:commodity];
		OOCargoQuantity q = [self generateQuantityForGood:good inEconomy:economy];
		// main system market limited to 127 units of each item
		OOCargoQuantity cap = [good oo_unsignedIntegerForKey:kOOCommodityCapacity defaultValue:MAIN_SYSTEM_MARKET_LIMIT];
		if (q > cap)
		{
			q = cap;
		}
		OOCreditsQuantity p = [self generatePriceForGood:good inEconomy:economy];
		good = [self createDefinitionFrom:good price:p andQuantity:q forKey:commodity atStation:nil inSystem:[UNIVERSE currentSystemID]];

		if (script != nil)
		{
			good = [self modifyGood:good withScript:script atStation:nil inSystem:[UNIVERSE currentSystemID] localMode:YES];
		}
		[market setGood:commodity withInfo:good];
	}
	return [market autorelease];
}


- (OOCommodityMarket *) generateMarketForStation:(StationEntity *)station
{
	NSArray *marketDefinition = [station marketDefinition];
	NSString *marketScriptName = [station marketScriptName];
	OOScript *marketScript = [PLAYER commodityScriptNamed:marketScriptName];
	if (marketDefinition == nil && marketScript == nil)
	{
		OOCommodityMarket *market = [self generateBlankMarket];
		return market;
	}
	
	OOCommodityMarket *market = [[OOCommodityMarket alloc] init];
	OOCargoQuantity capacity = [station marketCapacity];
	OOCommodityMarket *mainMarket = [UNIVERSE commodityMarket];

	NSString *commodity = nil;
	NSDictionary *good = nil;
	foreachkey (commodity, _commodityLists)
	{
		good = [_commodityLists oo_dictionaryForKey:commodity];
		OOCargoQuantity baseCapacity = [good oo_unsignedIntegerForKey:kOOCommodityCapacity defaultValue:MAIN_SYSTEM_MARKET_LIMIT];
		
		// important - ensure baseCapacity cannot be zero
		if (!baseCapacity)  baseCapacity = MAIN_SYSTEM_MARKET_LIMIT;

		OOCargoQuantity q = [mainMarket quantityForGood:commodity];
		OOCreditsQuantity p = [mainMarket priceForGood:commodity];
		
		if (marketScript == nil)
		{
			NSDictionary *modifier = [self firstModifierForGood:commodity inClasses:[good oo_arrayForKey:kOOCommodityClasses] fromList:marketDefinition];
			good = [self updateInfoFor:good byRule:modifier maxCapacity:capacity];
			p = [self adjustPrice:p byRule:modifier];
		
			// first, scale to this station's capacity for this good
			OOCargoQuantity localCapacity = [good oo_unsignedIntegerForKey:kOOCommodityCapacity];
			if (localCapacity > capacity)
			{
				localCapacity = capacity;
			}
			q = (q * localCapacity) / baseCapacity;
			q = [self adjustQuantity:q byRule:modifier];
			if (q > localCapacity)
			{
				q = localCapacity; // cap
			}
		}
		else
		{
			// only scale to market at this stage
			q = (q * capacity) / baseCapacity;
		}

		good = [self createDefinitionFrom:good price:p andQuantity:q forKey:commodity atStation:station inSystem:[UNIVERSE currentSystemID]];
		if (marketScript != nil)
		{
			good = [self modifyGood:good withScript:marketScript atStation:station inSystem:[UNIVERSE currentSystemID] localMode:YES];
		}

		[market setGood:commodity withInfo:good];
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

- (NSString *) goodNamed:(NSString *)name
{
	NSString *commodity = nil;
	foreachkey (commodity, _commodityLists)
	{
		NSDictionary *good = [_commodityLists oo_dictionaryForKey:commodity];
		if ([OOExpand([good oo_stringForKey:kOOCommodityName]) isEqualToString:name]) {
			return commodity;
		}
	}
	return nil;
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


- (OOCreditsQuantity) samplePriceForCommodity:(OOCommodityType)commodity inEconomy:(OOEconomyID)economy withScript:(NSString *)scriptName inSystem:(OOSystemID)system
{
	NSDictionary *good = [_commodityLists oo_dictionaryForKey:commodity];
	if (good == nil)
	{
		return 0;
	}
	OOCreditsQuantity p = [self generatePriceForGood:good inEconomy:economy];

	good = [self createDefinitionFrom:good price:p andQuantity:0 forKey:commodity atStation:nil inSystem:system];
	if (scriptName != nil)
	{
		OOScript *script = [PLAYER commodityScriptNamed:scriptName];
		if (script != nil)
		{
			good = [self modifyGood:good withScript:script atStation:nil inSystem:system localMode:YES];
		}
	}
	return [good oo_unsignedIntegerForKey:kOOCommodityPriceCurrent];
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


- (NSDictionary *) firstModifierForGood:(OOCommodityType)good inClasses:(NSArray *)classes fromList:(NSArray *)definitions
{
	NSUInteger i;
	for (i = 0; i < [definitions count]; i++)
	{
		NSDictionary *definition = [definitions oo_dictionaryAtIndex:i];
		if (definition != nil)
		{
			NSString *applicationType = [definition oo_stringForKey:kOOCommodityMarketType defaultValue:kOOCommodityMarketTypeValueDefault];
			NSString *applicationName = [definition oo_stringForKey:kOOCommodityMarketName defaultValue:@""];

			if (
				[applicationType isEqualToString:kOOCommodityMarketTypeValueDefault]
				|| ([applicationType isEqualToString:kOOCommodityMarketTypeValueGood] && [applicationName isEqualToString:good])
				|| ([applicationType isEqualToString:kOOCommodityMarketTypeValueClass] && [classes containsObject:applicationName])
				)
			{
				return definition;
			}
		}
	}
	// return a blank dictionary - default values will do the rest
	return [NSDictionary dictionary];
}


- (OOCreditsQuantity) adjustPrice:(OOCreditsQuantity)price byRule:(NSDictionary *)rule
{
	float p = (float)price; // work in floats to avoid rounding problems
	float pa = [rule oo_floatForKey:kOOCommodityMarketPriceAdder defaultValue:0.0];
	float pm = [rule oo_floatForKey:kOOCommodityMarketPriceMultiplier defaultValue:1.0];
	if (pm <= 0.0 && pa <= 0.0)
	{
		// setting a price multiplier of 0 forces the price to zero
		return 0;
	}
	float pr = [rule oo_floatForKey:kOOCommodityMarketPriceRandomiser defaultValue:0.0];
	p += pa;
	p = (p * pm) + (p * pr * (randf()-randf()));
	if (p < 1.0)
	{
		// random variation and non-zero price multiplier can't reduce
		// price below 1 decicredit
		p = 1.0;
	}
	return (OOCreditsQuantity) p;
}


- (OOCargoQuantity) adjustQuantity:(OOCargoQuantity)quantity byRule:(NSDictionary *)rule
{
	float q = (float)quantity; // work in floats to avoid rounding problems
	float qa = [rule oo_floatForKey:kOOCommodityMarketQuantityAdder defaultValue:0.0];
	float qm = [rule oo_floatForKey:kOOCommodityMarketQuantityMultiplier defaultValue:1.0];
	if (qm <= 0.0 && qa <= 0.0)
	{
		// setting a price multiplier of 0 forces the price to zero
		return 0;
	}
	float qr = [rule oo_floatForKey:kOOCommodityMarketQuantityRandomiser defaultValue:0.0];
	q += qa;
	q = (q * qm) + (q * qr * (randf()-randf()));
	if (q < 0.0)
	{
		// random variation and non-zero price multiplier can't reduce
		// quantity below zero
		q = 0.0;
	}
	// may be over station capacity - that gets capped later
	return (OOCargoQuantity) q;
}


- (NSDictionary *) updateInfoFor:(NSDictionary *)good byRule:(NSDictionary *)rule maxCapacity:(OOCargoQuantity)maxCapacity
{
	NSMutableDictionary *tmp = [NSMutableDictionary dictionaryWithDictionary:good];
	NSInteger import = [rule oo_integerForKey:kOOCommodityMarketLegalityImport defaultValue:-1];
	if (import >= 0)
	{
		[tmp oo_setInteger:import forKey:kOOCommodityLegalityImport];
	}

	NSInteger export = [rule oo_integerForKey:kOOCommodityMarketLegalityExport defaultValue:-1];
	if (export >= 0)
	{
		[tmp oo_setInteger:import forKey:kOOCommodityLegalityExport];
	}

	NSInteger capacity = [rule oo_integerForKey:kOOCommodityMarketCapacity defaultValue:-1];
	if (capacity >= 0 && capacity <= (NSInteger)maxCapacity)
	{
		[tmp oo_setInteger:capacity forKey:kOOCommodityCapacity];
	}
	else
	{
		// set to the station max capacity
		[tmp oo_setInteger:maxCapacity forKey:kOOCommodityCapacity];
	}

	return [[tmp copy] autorelease];
}



@end
