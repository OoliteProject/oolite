/*

OOCommodityMarket.h

Commodity price and quantity list for a particular station/system
Also used for the player ship's docked manifest

The universe, the player and the stations hold markets as oo::Ref.

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

#pragma once

#include "OOCommodities.h"
#include "OOTypes.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	Goods are keyed by UTF-8 std::strings
        (the commodity keys); each good's definition is an oo::PList dictionary
   (trade-goods.plist data, as OOCommodities and commodity scripts build it).
   -goods returns std::vector<std::string>; -massUnitForGood: takes const
   std::string &; -dictionaryForScripting hands JavaScript a PList dictionary.
*/
class OOCommodityMarket : public oo::RefCounted {
 public:
  NSUInteger count();

  void setGood(const std::string& key, const oo::PList& info);

  std::vector<std::string> goods();  // good keys, in sort_order
  oo::PList
  dictionaryForScripting();  // a dictionary of the definitions, for JavaScript

  bool setPrice(OOCreditsQuantity price, const std::string& good);
  bool setQuantity(OOCargoQuantity quantity, const std::string& good);
  bool addQuantity(OOCargoQuantity quantity, const std::string& good);
  bool removeQuantity(OOCargoQuantity quantity, const std::string& good);
  void removeAllGoods();
  bool setComment(const std::string& comment, const std::string& good);
  bool setShortComment(const std::string& comment, const std::string& good);

  std::optional<std::string> nameForGood(const std::string& good);
  std::optional<std::string> commentForGood(const std::string& good);
  std::optional<std::string> shortCommentForGood(const std::string& good);
  OOCreditsQuantity priceForGood(const std::string& good);
  OOCargoQuantity quantityForGood(const std::string& good);
  OOMassUnit massUnitForGood(const std::string& good);
  NSUInteger exportLegalityForGood(const std::string& good);
  NSUInteger importLegalityForGood(const std::string& good);
  OOCargoQuantity capacityForGood(const std::string& good);
  float trumbleOpinionForGood(const std::string& good);

  oo::PList definitionForGood(const std::string& good);  // null: no such good

  oo::PList savePlayerAmounts();  // [[key, quantity], ...] in goods() order
  void loadPlayerAmounts(const oo::PList& amounts);

  oo::PList
  saveStationAmounts();  // [[key, quantity, price], ...] in goods() order
  void loadStationAmounts(const oo::PList& amounts);

 private:
  // nullptr: no such good (a nil definition).
  oo::PList* definitionPointerForGood(const std::string& good);
  std::vector<std::string> sortedGoodKeys();

  std::map<std::string, oo::PList, std::less<>> _commodityList;
  std::optional<std::vector<std::string>>
      _sortedKeys;  // goods(), built on first use
};
