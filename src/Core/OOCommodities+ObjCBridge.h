/*

OOCommodities+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-fqyw): the Objective-C OOCommodities, a facade over the
C++ cxx::OOCommodities (OOCommodities.h), for callers that are not converted yet (Universe, which
makes it and asks it for markets; PlayerEntity and its categories, which ask it about goods). Its
interface is the one OOCommodities.h declared before the conversion, copied exactly (same
selectors, same types), so those callers compile and behave unchanged; each method forwards to its
C++ member, and a market it makes crosses back as that market's facade (oo::ToObjC). Imported as
the last line of OOCommodities.h; do not import it directly.

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

#ifndef OOCOMMODITIES_OBJCBRIDGE_H
#define OOCOMMODITIES_OBJCBRIDGE_H

#import "oofnd/objc/OOObject.h"

@class OOCommodityMarket, StationEntity;

@interface OOCommodities : OOObject {
@private
    oo::Ref<cxx::OOCommodities> _cxxCommodities;
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

namespace oo {

// The commodities' Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOCommodities* ToObjC(cxx::OOCommodities* commodities);
inline OOCommodities* ToObjC(const Ref<cxx::OOCommodities>& commodities) { return ToObjC(commodities.get()); }

// The C++ commodities behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOCommodities* ToCxx(OOCommodities* commodities);

} // namespace oo

#endif // OOCOMMODITIES_OBJCBRIDGE_H
