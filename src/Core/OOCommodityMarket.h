/*

OOCommodityMarket.h

Commodity price and quantity list for a particular station/system
Also used for the player ship's docked manifest

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

#import "OOCommodities.h"
#import "OOTypes.h"

@interface OOCommodityMarket: NSObject
{
@private
	NSMutableDictionary		*_commodityList;
	OOCargoQuantity			_capacity;
}

- (OOCargoQuantity) capacity;

- (NSUInteger) count;

- (void) setGood:(NSString *)key toPrice:(OOCreditsQuantity)price andQuantity:(OOCargoQuantity)quantity withInfo:(NSDictionary *)info;

- (NSArray *) goods;
- (BOOL) setPrice:(OOCreditsQuantity)price forGood:(NSString *)good;
- (BOOL) setQuantity:(OOCargoQuantity)quantity forGood:(NSString *)good;
- (BOOL) addQuantity:(OOCargoQuantity)quantity forGood:(NSString *)good;
- (BOOL) removeQuantity:(OOCargoQuantity)quantity forGood:(NSString *)good;

- (NSString *) nameForGood:(NSString *)good;
- (OOCreditsQuantity) priceForGood:(NSString *)good;
- (OOCargoQuantity) quantityForGood:(NSString *)good;
- (OOMassUnit) massUnitForGood:(NSString *)good;
- (NSUInteger) exportLegalityForGood:(NSString *)good;
- (NSUInteger) importLegalityForGood:(NSString *)good;

- (NSArray *) savePlayerAmounts;
- (void) loadPlayerAmounts:(NSArray *)amounts;

@end
