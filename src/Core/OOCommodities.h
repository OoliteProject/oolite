/*

OOCommodities.h

Commodity price and quantity manager

The universe
holds it as std::shared_ptr, and the markets it makes are
std::shared_ptr<OOCommodityMarket>.

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

#include <map>
#include <optional>
#include <string>

#include "OOTypes.h"
#include "oofnd/Object.hpp"
#include "oofnd/PList.hpp"

#define MAIN_SYSTEM_MARKET_LIMIT 127

// A trade-goods.plist quantity_unit as an OOMassUnit: 0-2 are the units,
// anything else is OOMassUnit::kUnknown (a bare cast would be undefined for
// those values).
static inline OOMassUnit OOMassUnitFromNumber(unsigned n) {
  return (n <= oo::ToUnderlying(OOMassUnit::kGrams))
             ? static_cast<OOMassUnit>(n)
             : OOMassUnit::kUnknown;
}

class StationEntity;
class OOScript;
class OOCommodityMarket;

class OOCommodities : public oo::Object {
 public:
  OOCommodities();  // reads trade-goods.plist

  static std::optional<std::string> legacyCommodityType(
      std::size_t i);  // always a key (the old method never returned nil)

  std::shared_ptr<OOCommodityMarket> generateManifestForPlayer();
  std::shared_ptr<OOCommodityMarket> generateBlankMarket();
  std::shared_ptr<OOCommodityMarket> generateMarketForSystemWithEconomy(
      OOEconomyID economy, const std::optional<std::string>&
                               scriptName);  // nullopt: no script (was nil)
  std::shared_ptr<OOCommodityMarket> generateMarketForStation(
      ::StationEntity* station);

  OOCreditsQuantity samplePriceForCommodity(
      const std::string& commodity, OOEconomyID economy,
      const std::optional<std::string>& scriptName, OOSystemID system);

  std::size_t count();
  std::vector<std::string> goods();  // commodity keys, in key order
  bool goodDefined(const std::string& key);
  std::optional<std::string> goodNamed(
      const std::string& name);  // nullopt: no good has that (expanded) name
  std::string getRandomCommodity();  // a commodity key
  OOMassUnit massUnitForGood(const std::string& good);

 private:
  oo::PList modifyGood(const oo::PList& good, ::OOScript* script,
                       ::StationEntity* station, OOSystemID system, bool local);
  oo::PList createDefinitionFrom(const oo::PList& good, OOCreditsQuantity p,
                                 OOCargoQuantity q, const std::string& key,
                                 ::StationEntity* station, OOSystemID system);

  OOCargoQuantity generateQuantityForGood(const oo::PList& good,
                                          OOEconomyID economy);
  OOCreditsQuantity generatePriceForGood(const oo::PList& good,
                                         OOEconomyID economy);

  float economicBiasForGood(const oo::PList& good, OOEconomyID economy);
  oo::PList firstModifierForGood(const std::string& good,
                                 const oo::PList& classes,
                                 const oo::PList& definitions);
  OOCreditsQuantity adjustPrice(OOCreditsQuantity price, const oo::PList& rule);
  OOCargoQuantity adjustQuantity(OOCargoQuantity quantity,
                                 const oo::PList& rule);
  oo::PList updateInfoFor(const oo::PList& good, const oo::PList& rule,
                          OOCargoQuantity maxCapacity);

  std::map<std::string, oo::PList, std::less<>>
      _commodityLists;  // trade-goods.plist: commodity key -> its info (a Dict)
};
