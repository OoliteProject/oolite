/*

OOCommodities.h

Commodity price and quantity manager

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOTypes.h"


#define MAIN_SYSTEM_MARKET_LIMIT  127

// keys in trade-goods.plist
static NSString * const kOOCommodityName			= @"name";
static NSString * const kOOCommodityClasses			= @"classes";
static NSString * const kOOCommodityContainer		= @"quantity_unit";
static NSString * const kOOCommodityPeakExport		= @"peak_export";
static NSString * const kOOCommodityPeakImport		= @"peak_import";
static NSString * const kOOCommodityPriceAverage	= @"price_average";
static NSString * const kOOCommodityPriceEconomic	= @"price_economic";
static NSString * const kOOCommodityPriceRandom		= @"price_random";
// next one cannot be set from file - named for compatibility
static NSString * const kOOCommodityPriceCurrent	= @"price";
static NSString * const kOOCommodityQuantityAverage	= @"quantity_average";
static NSString * const kOOCommodityQuantityEconomic= @"quantity_economic";
static NSString * const kOOCommodityQuantityRandom	= @"quantity_random";
// next one cannot be set from file - named for compatibility
static NSString * const kOOCommodityQuantityCurrent	= @"quantity";
static NSString * const kOOCommodityLegalityExport	= @"legality_export";
static NSString * const kOOCommodityLegalityImport	= @"legality_import";
static NSString * const kOOCommodityTrumbleOpinion	= @"trumble_opinion";
static NSString * const kOOCommoditySortOrder		= @"sort_order";
static NSString * const kOOCommodityCapacity		= @"capacity";

// keys in secondary market definitions
static NSString * const kOOCommodityMarketType					= @"type";
static NSString * const kOOCommodityMarketName					= @"name";
static NSString * const kOOCommodityMarketPriceAdder			= @"price_adder";
static NSString * const kOOCommodityMarketPriceMultiplier		= @"price_multiplier";
static NSString * const kOOCommodityMarketPriceRandomiser		= @"price_randomiser";
static NSString * const kOOCommodityMarketQuantityAdder			= @"quantity_adder";
static NSString * const kOOCommodityMarketQuantityMultiplier	= @"quantity_multiplier";
static NSString * const kOOCommodityMarketQuantityRandomiser	= @"quantity_randomiser";
static NSString * const kOOCommodityMarketLegalityExport		= @"legality_export";
static NSString * const kOOCommodityMarketLegalityImport		= @"legality_import";
static NSString * const kOOCommodityMarketCapacity				= @"capacity";

// values for "type" in the plist
static NSString * const kOOCommodityMarketTypeValueDefault		= @"default";
static NSString * const kOOCommodityMarketTypeValueClass		= @"class";
static NSString * const kOOCommodityMarketTypeValueGood			= @"good";



@class OOCommodityMarket, StationEntity;

@interface OOCommodities: NSObject
{
@private
	NSDictionary		*_commodityLists;
	

}

+ (OOCommodityType) legacyCommodityType:(NSUInteger)i;

- (OOCommodityMarket *) generateManifestForPlayer;
- (OOCommodityMarket *) generateBlankMarket;
- (OOCommodityMarket *) generateMarketForSystemWithEconomy:(OOEconomyID)economy;
- (OOCommodityMarket *) generateMarketForStation:(StationEntity *)station;

- (OOCreditsQuantity) samplePriceForCommodity:(OOCommodityType)commodity inEconomy:(OOEconomyID)economy;

- (NSUInteger) count;
- (NSArray *) goods;
- (BOOL) goodDefined:(NSString *)key;
- (NSString *) getRandomCommodity;
- (OOMassUnit) massUnitForGood:(NSString *)good;



@end
