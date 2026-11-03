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

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-rvit): goods are keyed by UTF-8 std::strings
        (the commodity keys); each good's definition is an oo::PList dictionary (trade-goods.plist
        data, as OOCommodities and commodity scripts build it). -goods and -massUnitForGood: are
        shared selectors (OOCommodities) and keep Objective-C object types; -dictionaryForScripting
        hands JavaScript an Objective-C dictionary.
*/
@interface OOCommodityMarket : OOObject {
@private
    std::map<std::string, oo::PList, std::less<>> _commodityList;
    std::optional<std::vector<std::string>> _sortedKeys; // -goods, built on first use
}

- (NSUInteger)count;

- (void)cxx_setGood:(const std::string&)key withInfo:(const oo::PList&)info;

- (id)goods; // shared selector (proposed ADR-0043): an array of the good keys, in sort_order
- (id)dictionaryForScripting; // an immutable dictionary of the definitions, for JavaScript

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
- (OOMassUnit)massUnitForGood:(id)good; // shared selector (proposed ADR-0043): good is an Objective-C string
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

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before bead oo-rvit, forwarding to the cxx_ methods above, so unmigrated callers compile
        unchanged. Callers move to the cxx_ API in their own sweep beads; the bridge goes in its own bead.
*/
#import "OOCommodityMarket+FoundationBridge.h"
