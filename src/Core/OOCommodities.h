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
#include "oofnd/PList.hpp"

#include <map>
#include <optional>
#include <string>

#define MAIN_SYSTEM_MARKET_LIMIT 127

// A trade-goods.plist quantity_unit as an OOMassUnit: 0-2 are the units, anything else is
// UNITS_UNKNOWN (ADR-0036; the bare cast this replaces was undefined for those values).
static inline OOMassUnit OOMassUnitFromNumber(unsigned n)
{
    return (n <= UNITS_GRAMS) ? (OOMassUnit)n : UNITS_UNKNOWN;
}

@class OOCommodityMarket, StationEntity;

@interface OOCommodities : OOObject {
@private
    std::map<std::string, oo::PList, std::less<>> _commodityLists; // trade-goods.plist: commodity key -> its info (a Dict)
}

+ (std::optional<std::string>)cxx_legacyCommodityType:(NSUInteger)i; // always a key (the old method never returned nil)

- (OOCommodityMarket*)generateManifestForPlayer;
- (OOCommodityMarket*)generateBlankMarket;
- (OOCommodityMarket*)cxx_generateMarketForSystemWithEconomy:(OOEconomyID)economy andScript:(const std::optional<std::string>&)scriptName; // nullopt: no script (was nil)
- (OOCommodityMarket*)generateMarketForStation:(StationEntity*)station;

- (OOCreditsQuantity)cxx_samplePriceForCommodity:(const std::string&)commodity inEconomy:(OOEconomyID)economy withScript:(const std::optional<std::string>&)scriptName inSystem:(OOSystemID)system;

- (NSUInteger)count;
- (std::vector<std::string>)goods; // commodity keys, in key order
- (BOOL)cxx_goodDefined:(const std::string&)key;
- (std::optional<std::string>)cxx_goodNamed:(const std::string&)name; // nullopt: no good has that (expanded) name
- (std::string)getRandomCommodity; // a commodity key
- (OOMassUnit)massUnitForGood:(const std::string&)good;

@end
