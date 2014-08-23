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


@implementation OOCommodityMarket

- (id) init
{
	self = [super init];
	if (self == nil)  return nil;

	_commodityList = [[NSMutableDictionary dictionaryWithCapacity:24] retain];

	return self;
}


- (void) dealloc
{
	DESTROY(_commodityList);

	[super dealloc];
}


- (void) setGood:(NSString *)key toPrice:(OOCreditsQuantity)price andQuantity:(OOCargoQuantity)quantity withInfo:(NSDictionary *)info
{
	NSMutableDictionary *definition = [NSMutableDictionary dictionaryWithDictionary:info];
	[definition oo_setUnsignedInteger:price forKey:kOOCommodityPriceCurrent];
	[definition oo_setUnsignedInteger:quantity forKey:kOOCommodityQuantityCurrent];

	[_commodityList setObject:definition forKey:key];
}


- (NSArray *) goods
{
	return [_commodityList allKeys];
}


- (BOOL) setPrice:(OOCreditsQuantity)price forGood:(NSString *)good
{
	NSMutableDictionary *definition = [_commodityList oo_mutableDictionaryForKey:good];
	if (definition == nil)
	{
		return NO;
	}
	[definition oo_setUnsignedInteger:price forKey:kOOCommodityPriceCurrent];
	return YES;
}


- (BOOL) setQuantity:(OOCargoQuantity)quantity forGood:(NSString *)good
{
	NSMutableDictionary *definition = [_commodityList oo_mutableDictionaryForKey:good];
	if (definition == nil)
	{
		return NO;
	}
	[definition oo_setUnsignedInteger:quantity forKey:kOOCommodityQuantityCurrent];
	return YES;
}


- (NSString *) nameForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return OOExpand(@"[oolite-unknown-commodity-name]");
	}
	return OOExpand([definition oo_stringForKey:kOOCommodityName defaultValue:@"[oolite-unknown-commodity-name]"]);
}


- (OOCreditsQuantity) priceForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityPriceCurrent];
}


- (OOCargoQuantity) quantityForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityQuantityCurrent];
}


- (OOMassUnit) massUnitForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return UNITS_TONS;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityContainer];
}


- (NSUInteger) exportLegalityForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityLegalityExport];
}


- (NSUInteger) importLegalityForGood:(NSString *)good
{
	NSDictionary *definition = [_commodityList oo_dictionaryForKey:good];
	if (definition == nil)
	{
		return 0;
	}
	return [definition oo_unsignedIntegerForKey:kOOCommodityLegalityImport];
}


@end
