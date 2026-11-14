/*

OOCommodityMarket+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-ih7y): the Objective-C OOCommodityMarket, a facade over
the C++ cxx::OOCommodityMarket (OOCommodityMarket.h), for callers that are not converted yet
(OOCommodities, which makes markets; Universe, PlayerEntity and StationEntity, which keep and
trade in them). Its interface is the one OOCommodityMarket.h declared before the conversion,
copied exactly (same selectors, same types), so those callers compile and behave unchanged; each
method forwards to its C++ member. Imported as the last line of OOCommodityMarket.h; do not import
it directly.

oo::ToObjC gives the market's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(m)) == m. Never add to this file; converted code does not message the
facade. Deleted by its deletion bead once no file outside OOCommodityMarket.* names the
Objective-C OOCommodityMarket.

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

#ifndef OOCOMMODITYMARKET_OBJCBRIDGE_H
#define OOCOMMODITYMARKET_OBJCBRIDGE_H

#import "oofnd/objc/OOObject.h"

@interface OOCommodityMarket : OOObject {
@private
    oo::Ref<cxx::OOCommodityMarket> _cxxMarket;
}

- (NSUInteger)count;

- (void)cxx_setGood:(const std::string&)key withInfo:(const oo::PList&)info;

- (std::vector<std::string>)goods; // good keys, in sort_order
- (oo::PList)dictionaryForScripting; // a dictionary of the definitions, for JavaScript

- (BOOL)cxx_setPrice:(OOCreditsQuantity)price forGood:(const std::string&)good;
- (BOOL)cxx_setQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good;
- (BOOL)cxx_addQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good;
- (BOOL)cxx_removeQuantity:(OOCargoQuantity)quantity forGood:(const std::string&)good;
- (void)removeAllGoods;
- (BOOL)cxx_setComment:(const std::string&)comment forGood:(const std::string&)good;
- (BOOL)cxx_setShortComment:(const std::string&)comment forGood:(const std::string&)good;

- (std::optional<std::string>)cxx_nameForGood:(const std::string&)good;
- (std::optional<std::string>)cxx_commentForGood:(const std::string&)good;
- (std::optional<std::string>)cxx_shortCommentForGood:(const std::string&)good;
- (OOCreditsQuantity)cxx_priceForGood:(const std::string&)good;
- (OOCargoQuantity)cxx_quantityForGood:(const std::string&)good;
- (OOMassUnit)massUnitForGood:(const std::string&)good;
- (NSUInteger)cxx_exportLegalityForGood:(const std::string&)good;
- (NSUInteger)cxx_importLegalityForGood:(const std::string&)good;
- (OOCargoQuantity)cxx_capacityForGood:(const std::string&)good;
- (float)cxx_trumbleOpinionForGood:(const std::string&)good;

- (oo::PList)cxx_definitionForGood:(const std::string&)good; // null: no such good

- (oo::PList)cxx_savePlayerAmounts; // [[key, quantity], ...] in -goods order
- (void)cxx_loadPlayerAmounts:(const oo::PList&)amounts;

- (oo::PList)cxx_saveStationAmounts; // [[key, quantity, price], ...] in -goods order
- (void)cxx_loadStationAmounts:(const oo::PList&)amounts;

@end

namespace oo {

// The market's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOCommodityMarket* ToObjC(cxx::OOCommodityMarket* market);
inline OOCommodityMarket* ToObjC(const Ref<cxx::OOCommodityMarket>& market) { return ToObjC(market.get()); }

// The C++ market behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOCommodityMarket* ToCxx(OOCommodityMarket* market);

} // namespace oo

#endif // OOCOMMODITYMARKET_OBJCBRIDGE_H
