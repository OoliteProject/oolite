/*

OOCommodities.h

Commodity price and quantity manager

C++20 since bead oo-fqyw (Phase 3, proposed ADR-0056). Its Objective-C facade was deleted by bead
oo-9ht.25 (batch E); the universe holds it as oo::Ref, and the markets it makes are C++
(oo::Ref<OOCommodityMarket>).

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

#ifndef OOCOMMODITIES_H
#define OOCOMMODITIES_H

#include "OOTypes.h"
#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"

#include <map>
#include <optional>
#include <string>


#define MAIN_SYSTEM_MARKET_LIMIT  127


// A trade-goods.plist quantity_unit as an OOMassUnit: 0-2 are the units, anything else is
// UNITS_UNKNOWN (ADR-0036; the bare cast this replaces was undefined for those values).
static inline OOMassUnit OOMassUnitFromNumber(unsigned n)
{
	return (n <= UNITS_GRAMS) ? (OOMassUnit)n : UNITS_UNKNOWN;
}

class StationEntity;
class OOScript;
class OOCommodityMarket;


class OOCommodities : public oo::RefCounted
{
public:
	OOCommodities();	// reads trade-goods.plist

	static std::optional<std::string> legacyCommodityType(NSUInteger i);	// always a key (the old method never returned nil)

	oo::Ref<OOCommodityMarket> generateManifestForPlayer();
	oo::Ref<OOCommodityMarket> generateBlankMarket();
	oo::Ref<OOCommodityMarket> generateMarketForSystemWithEconomy(OOEconomyID economy, const std::optional<std::string> &scriptName);	// nullopt: no script (was nil)
	oo::Ref<OOCommodityMarket> generateMarketForStation(::StationEntity *station);

	OOCreditsQuantity samplePriceForCommodity(const std::string &commodity, OOEconomyID economy, const std::optional<std::string> &scriptName, OOSystemID system);

	NSUInteger count();
	std::vector<std::string> goods();	// commodity keys, in key order
	bool goodDefined(const std::string &key);
	std::optional<std::string> goodNamed(const std::string &name);	// nullopt: no good has that (expanded) name
	std::string getRandomCommodity();	// a commodity key
	OOMassUnit massUnitForGood(const std::string &good);

private:
	oo::PList modifyGood(const oo::PList &good, ::OOScript *script, ::StationEntity *station, OOSystemID system, bool local);
	oo::PList createDefinitionFrom(const oo::PList &good, OOCreditsQuantity p, OOCargoQuantity q, const std::string &key, ::StationEntity *station, OOSystemID system);


	OOCargoQuantity generateQuantityForGood(const oo::PList &good, OOEconomyID economy);
	OOCreditsQuantity generatePriceForGood(const oo::PList &good, OOEconomyID economy);

	float economicBiasForGood(const oo::PList &good, OOEconomyID economy);
	oo::PList firstModifierForGood(const std::string &good, const oo::PList &classes, const oo::PList &definitions);
	OOCreditsQuantity adjustPrice(OOCreditsQuantity price, const oo::PList &rule);
	OOCargoQuantity adjustQuantity(OOCargoQuantity quantity, const oo::PList &rule);
	oo::PList updateInfoFor(const oo::PList &good, const oo::PList &rule, OOCargoQuantity maxCapacity);

	std::map<std::string, oo::PList, std::less<>>	_commodityLists;	// trade-goods.plist: commodity key -> its info (a Dict)
};



#endif	// OOCOMMODITIES_H
