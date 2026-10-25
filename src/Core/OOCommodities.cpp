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

#include "OOCommodities.h"
#include "OOCommodityMarket.h"

#include "StationEntity.h"
#include "ResourceManager.h"
#include "legacy_random.h"
#include "OOJSScript.h"
#include "PlayerEntity.h"
#include "OOStringExpander.h"
#include "oofnd/PListGet.hpp"

#include <string_view>


namespace {

// keys in trade-goods.plist (moved from OOCommodities.h by bead oo-3rb.154; sort_order,
// trumble_opinion, comment and short_comment are read only by OOCommodityMarket.mm)
constexpr std::string_view kOOCommodityName			= "name";
constexpr std::string_view kOOCommodityClasses			= "classes";
constexpr std::string_view kOOCommodityContainer		= "quantity_unit";
constexpr std::string_view kOOCommodityPeakExport		= "peak_export";
constexpr std::string_view kOOCommodityPeakImport		= "peak_import";
constexpr std::string_view kOOCommodityPriceAverage	= "price_average";
constexpr std::string_view kOOCommodityPriceEconomic	= "price_economic";
constexpr std::string_view kOOCommodityPriceRandom		= "price_random";
// next one cannot be set from file - named for compatibility
constexpr std::string_view kOOCommodityPriceCurrent	= "price";
constexpr std::string_view kOOCommodityQuantityAverage	= "quantity_average";
constexpr std::string_view kOOCommodityQuantityEconomic= "quantity_economic";
constexpr std::string_view kOOCommodityQuantityRandom	= "quantity_random";
// next one cannot be set from file - named for compatibility
constexpr std::string_view kOOCommodityQuantityCurrent	= "quantity";
constexpr std::string_view kOOCommodityLegalityExport	= "legality_export";
constexpr std::string_view kOOCommodityLegalityImport	= "legality_import";
constexpr std::string_view kOOCommodityCapacity		= "capacity";
constexpr std::string_view kOOCommodityScript			= "market_script";
// next one cannot be set from file - named for compatibility
constexpr std::string_view kOOCommodityKey				= "key";


// keys in secondary market definitions
constexpr std::string_view kOOCommodityMarketType					= "type";
constexpr std::string_view kOOCommodityMarketName					= "name";
constexpr std::string_view kOOCommodityMarketPriceAdder			= "price_adder";
constexpr std::string_view kOOCommodityMarketPriceMultiplier		= "price_multiplier";
constexpr std::string_view kOOCommodityMarketPriceRandomiser		= "price_randomiser";
constexpr std::string_view kOOCommodityMarketQuantityAdder			= "quantity_adder";
constexpr std::string_view kOOCommodityMarketQuantityMultiplier	= "quantity_multiplier";
constexpr std::string_view kOOCommodityMarketQuantityRandomiser	= "quantity_randomiser";
constexpr std::string_view kOOCommodityMarketLegalityExport		= "legality_export";
constexpr std::string_view kOOCommodityMarketLegalityImport		= "legality_import";
constexpr std::string_view kOOCommodityMarketCapacity				= "capacity";

// values for "type" in the plist
constexpr std::string_view kOOCommodityMarketTypeValueDefault		= "default";
constexpr std::string_view kOOCommodityMarketTypeValueClass		= "class";
constexpr std::string_view kOOCommodityMarketTypeValueGood			= "good";


// oo_stringForKey: on a commodity's info: a string, or a number's -stringValue;
// nullopt (nil) otherwise.
std::optional<std::string> StringFor(const oo::PList &info, std::string_view key)
{
	const oo::PList *value = info.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return info.get<std::string>(key);
}

// -setObject:forKey: on a copy of an info dictionary (a Dict node; the per-good infos are).
void Set(oo::PList &info, std::string_view key, oo::PList value)
{
	if (oo::PList::Dict *entries = info.getIf<oo::PList::Dict>())  (*entries)[std::string(key)] = std::move(value);
}

// -oo_setUnsignedInteger:forKey: / -oo_setInteger:forKey: (+numberWithUnsignedInteger: /
// +numberWithInteger:, which oo::PListFrom reads as an unsigned / signed integer).
void SetUnsigned(oo::PList &info, std::string_view key, unsigned long long value)
{
	Set(info, key, oo::PList::unsignedInteger(value));
}

void SetSigned(oo::PList &info, std::string_view key, long long value)
{
	Set(info, key, oo::PList::signedInteger(value));
}

// [array containsObject:string] over a PList array (an equal string node).
bool ContainsString(const oo::PList &array, const std::string &string)
{
	const oo::PList::Array *elements = array.getIf<oo::PList::Array>();
	if (elements == nullptr)  return false;
	for (const oo::PList &element : *elements)
	{
		const std::string *text = element.getIf<std::string>();
		if (text != nullptr && *text == string)  return true;
	}
	return false;
}

} // namespace


std::optional<std::string> OOCommodities::legacyCommodityType(NSUInteger i)
{
	switch (i)
	{
	case 0:
		return "food";
	case 1:
		return "textiles";
	case 2:
		return "radioactives";
	case 3:
		return "slaves";
	case 4:
		return "liquor_wines";
	case 5:
		return "luxuries";
	case 6:
		return "narcotics";
	case 7:
		return "computers";
	case 8:
		return "machinery";
	case 9:
		return "alloys";
	case 10:
		return "firearms";
	case 11:
		return "furs";
	case 12:
		return "minerals";
	case 13:
		return "gold";
	case 14:
		return "platinum";
	case 15:
		return "gem_stones";
	case 16:
		return "alien_items";
	}
	// shouldn't happen
	return "food";
}

OOCommodities::OOCommodities()
{
	// ResourceManager's dictionary API is not migrated: the merged table arrives through oo::PListFrom.
	// TODO: validation of inputs; convert 't', 'kg', 'g' in quantity_unit to 0, 1, 2 (for now it
	// needs them entering as the ints).
	const oo::PList rawCommodityLists = ResourceManager::dictionaryFromFilesNamed("trade-goods.plist", "Config", MERGE_SMART, YES);
	if (const oo::PList::Dict *entries = rawCommodityLists.getIf<oo::PList::Dict>())  _commodityLists = *entries;
}


oo::Ref<OOCommodityMarket> OOCommodities::generateManifestForPlayer()
{
	oo::Ref<OOCommodityMarket> market = oo::makeRef<OOCommodityMarket>();

	for (const auto &[commodity, info] : _commodityLists)	// key order (bead oo-3rb.154)
	{
		oo::PList good = info.isDict() ? info : oo::PList(oo::PList::Dict{});	// +dictionaryWithDictionary: of the entry
		SetUnsigned(good, kOOCommodityPriceCurrent, 0);
		SetUnsigned(good, kOOCommodityQuantityCurrent, 0);
		/* The actual capacity of the player ship is a total, not
		 * per-good, so is managed separately through PlayerEntity */
		SetUnsigned(good, kOOCommodityCapacity, UINT32_MAX);
		Set(good, kOOCommodityKey, oo::PList(commodity));

		market->setGood(commodity, good);
	}
	return market;
}


oo::Ref<OOCommodityMarket> OOCommodities::generateBlankMarket()
{
	oo::Ref<OOCommodityMarket> market = oo::makeRef<OOCommodityMarket>();

	for (const auto &[commodity, info] : _commodityLists)	// key order (bead oo-3rb.154)
	{
		oo::PList good = info.isDict() ? info : oo::PList(oo::PList::Dict{});	// +dictionaryWithDictionary: of the entry
		SetUnsigned(good, kOOCommodityPriceCurrent, 0);
		SetUnsigned(good, kOOCommodityQuantityCurrent, 0);
		SetUnsigned(good, kOOCommodityCapacity, 0);
		Set(good, kOOCommodityKey, oo::PList(commodity));

		market->setGood(commodity, good);
	}
	return market;
}


oo::PList OOCommodities::createDefinitionFrom(const oo::PList & good, OOCreditsQuantity p, OOCargoQuantity q, const std::string &key, ::StationEntity *station, OOSystemID system)
{
	oo::PList definition = good;
	SetUnsigned(definition, kOOCommodityPriceCurrent, p);
	SetUnsigned(definition, kOOCommodityQuantityCurrent, q);
	if (station == nil && definition.find(kOOCommodityCapacity) == nullptr)
	{
		SetSigned(definition, kOOCommodityCapacity, MAIN_SYSTEM_MARKET_LIMIT);
	}

	Set(definition, kOOCommodityKey, oo::PList(key));
	if (station != nil && !(station != nullptr ? station->getMarketMonitored() : false))
	{
		// clear legal status indicators if the market is not monitored
		SetUnsigned(definition, kOOCommodityLegalityExport, 0);
		SetUnsigned(definition, kOOCommodityLegalityImport, 0);
	}

	const std::optional<std::string> goodScriptName = StringFor(definition, kOOCommodityScript);
	if (!goodScriptName.has_value())
	{
		return definition;
	}
	::OOScript *goodScript = (PLAYER != nullptr ? PLAYER->commodityScriptNamed(goodScriptName) : (OOScript *)nullptr);	// (has a value: checked above)
	if (goodScript == nil)
	{
		return definition;
	}
	return modifyGood(definition, goodScript, station, system, false);
}


oo::PList OOCommodities::modifyGood(const oo::PList &good, ::OOScript *script, ::StationEntity *station, OOSystemID system, bool localMode)
{
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value				rval;
	// The JS boundary takes and gives property-list objects: the info crosses as one, and an
	// accepted result comes back through oo::PListFrom (an exact round trip, Amendment 2 item 11).
	ooscript::Value				args[] = {
		OOJSValueFromPList(context, good),
		station != nullptr ? station->jsValueInContext(context) : ooscript::nullValue(),	// the C++ station's JS value, which OOJSValueFromNativeObject() of its object reached (bead oo-w9pi2)
		ooscript::int32Value(system)
	};
	BOOL				OK = YES;
	const char			*errorType = nullptr;

	if (localMode)
	{
		errorType = "local";
		OK = (script != nullptr ? script->callMethod(OOJSID("updateLocalCommodityDefinition"), context, args, 3, &rval) : false);
	}
	else
	{
		errorType = "general";
		OK = (script != nullptr ? script->callMethod(OOJSID("updateGeneralCommodityDefinition"), context, args, 3, &rval) : false);
	}

	if (!OK)
	{
		OO_LOG("script.commodityScript.error","Could not update {} commodity definition for {} - unable to call updateLocalCommodityDefinition",errorType,StringFor(good, kOOCommodityName).value_or("(null)"));
		OOJSRelinquishContext(context);
		return good;
	}

	if (!ooscript::isObjectOrNull(rval))
	{
		OO_LOG("script.commodityScript.error","Could not update {} commodity definition for {} - return value invalid",errorType,StringFor(good, kOOCommodityKey).value_or("(null)"));
		OOJSRelinquishContext(context);
		return good;
	}

	oo::PList result = cxx_OOJSPListFromJSObject(context, ooscript::toObject(rval));
	OOJSRelinquishContext(context);
	if (result.getIf<oo::PList::Dict>() == nullptr)
	{
		OO_LOG("script.commodityScript.error","Could not update {} commodity definition for {} - return value invalid",errorType,StringFor(good, kOOCommodityKey).value_or("(null)"));
		return good;
	}

	return result;
}


oo::Ref<OOCommodityMarket> OOCommodities::generateMarketForSystemWithEconomy(OOEconomyID economy, const std::optional<std::string> &scriptName)
{
	::OOScript *script = (PLAYER != nullptr ? PLAYER->commodityScriptNamed(scriptName) : (OOScript *)nullptr);

	oo::Ref<OOCommodityMarket> market = oo::makeRef<OOCommodityMarket>();

	for (const auto &[commodity, info] : _commodityLists)	// key order (bead oo-3rb.154)
	{
		oo::PList good = info;
		OOCargoQuantity q = generateQuantityForGood(good, economy);
		// main system market limited to 127 units of each item
		OOCargoQuantity cap = good.get<unsigned int>(kOOCommodityCapacity, MAIN_SYSTEM_MARKET_LIMIT);
		if (q > cap)
		{
			q = cap;
		}
		OOCreditsQuantity p = generatePriceForGood(good, economy);
		good = createDefinitionFrom(good, p, q, commodity, nullptr, (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0));

		if (script != nil)
		{
			good = modifyGood(good, script, nullptr, (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0), true);
		}
		market->setGood(commodity, good);
	}
	return market;
}


oo::Ref<OOCommodityMarket> OOCommodities::generateMarketForStation(::StationEntity *station)
{
	const oo::PList marketDefinition = (station != nullptr ? station->getMarketDefinition() : oo::PList());
	::OOScript *marketScript = (PLAYER != nullptr ? PLAYER->commodityScriptNamed((station != nullptr ? station->getMarketScriptName() : std::optional<std::string>())) : (OOScript *)nullptr);
	if (!marketDefinition && marketScript == nil)
	{
		oo::Ref<OOCommodityMarket> market = generateBlankMarket();
		return market;
	}

	oo::Ref<OOCommodityMarket> market = oo::makeRef<OOCommodityMarket>();
	OOCargoQuantity capacity = (station != nullptr ? station->getMarketCapacity() : 0);
	OOCommodityMarket *mainMarket = (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);

	for (const auto &[commodity, info] : _commodityLists)	// key order (bead oo-3rb.154)
	{
		oo::PList good = info;
		OOCargoQuantity baseCapacity = good.get<unsigned int>(kOOCommodityCapacity, MAIN_SYSTEM_MARKET_LIMIT);

		// important - ensure baseCapacity cannot be zero
		if (!baseCapacity)  baseCapacity = MAIN_SYSTEM_MARKET_LIMIT;

		OOCargoQuantity q = (mainMarket != nullptr) ? mainMarket->quantityForGood(commodity) : 0;
		OOCreditsQuantity p = (mainMarket != nullptr) ? mainMarket->priceForGood(commodity) : 0;

		if (marketScript == nil)
		{
			const oo::PList *classes = good.get<oo::PList::Array>(kOOCommodityClasses);
			const oo::PList modifier = firstModifierForGood(commodity, (classes != nullptr) ? *classes : oo::PList(), marketDefinition);
			good = updateInfoFor(good, modifier, capacity);
			p = adjustPrice(p, modifier);

			// first, scale to this station's capacity for this good
			OOCargoQuantity localCapacity = good.get<unsigned int>(kOOCommodityCapacity);
			if (localCapacity > capacity)
			{
				localCapacity = capacity;
			}
			q = (q * localCapacity) / baseCapacity;
			q = adjustQuantity(q, modifier);
			if (q > localCapacity)
			{
				q = localCapacity; // cap
			}
		}
		else
		{
			// only scale to market at this stage
			q = (q * capacity) / baseCapacity;
		}

		good = createDefinitionFrom(good, p, q, commodity, station, (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0));
		if (marketScript != nil)
		{
			good = modifyGood(good, marketScript, station, (UNIVERSE != nullptr ? UNIVERSE->currentSystemID() : 0), true);
		}

		market->setGood(commodity, good);
	}
	return market;
}


NSUInteger OOCommodities::count()
{
	return _commodityLists.size();
}


std::vector<std::string> OOCommodities::goods()
{
	// key order (was -allKeys, hash order)
	std::vector<std::string> keys;
	for (const auto &entry : _commodityLists)  keys.push_back(entry.first);
	return keys;
}


bool OOCommodities::goodDefined(const std::string &key)
{
	const auto entry = _commodityLists.find(key);
	return entry != _commodityLists.end() && entry->second.isDict();
}

std::optional<std::string> OOCommodities::goodNamed(const std::string &name)
{
	for (const auto &[key, info] : _commodityLists)	// key order (was hash order): the first match wins
	{
		const std::optional<std::string> commodityName = StringFor(info, kOOCommodityName);
		const std::optional<std::string> expanded = commodityName.has_value() ? cxx_OOExpand(*commodityName) : std::nullopt;
		if (expanded == name) {
			return key;
		}
	}
	return std::nullopt;
}



std::string OOCommodities::getRandomCommodity()
{
	// Ranrot() % count indexes the keys in key order (was -allKeys, hash order).
	NSUInteger idx = Ranrot() % _commodityLists.size();
	auto entry = _commodityLists.begin();
	std::advance(entry, idx);
	return entry->first;
}


OOMassUnit OOCommodities::massUnitForGood(const std::string &good)
{
	const auto entry = _commodityLists.find(good);
	if (entry == _commodityLists.end() || !entry->second.isDict())
	{
		return UNITS_TONS;
	}
	return OOMassUnitFromNumber(entry->second.get<unsigned int>(kOOCommodityContainer));
}




OOCargoQuantity OOCommodities::generateQuantityForGood(const oo::PList &good, OOEconomyID economy)
{
	float bias = economicBiasForGood(good, economy);

	float base = good.get<float>(kOOCommodityQuantityAverage);
	float econ = base * good.get<float>(kOOCommodityQuantityEconomic) * bias;
	// Two draws, in the order clang evaluated the operands of the former (randf() - randf()).
	float firstDraw = randf();
	float secondDraw = randf();
	float random = base * good.get<float>(kOOCommodityQuantityRandom) * (firstDraw - secondDraw);
	base += econ + random;
	if (base < 0.0)
	{
		return 0;
	}
	else
	{
		return (OOCargoQuantity)base;
	}
}


OOCreditsQuantity OOCommodities::generatePriceForGood(const oo::PList &good, OOEconomyID economy)
{
	float bias = economicBiasForGood(good, economy);

	float base = good.get<float>(kOOCommodityPriceAverage);
	float econ = base * good.get<float>(kOOCommodityPriceEconomic) * -bias;
	// Two draws, in the order clang evaluated the operands of the former (randf() - randf()).
	float firstDraw = randf();
	float secondDraw = randf();
	float random = base * good.get<float>(kOOCommodityPriceRandom) * (firstDraw - secondDraw);
	base += econ + random;
	if (base < 0.0)
	{
		return 0;
	}
	else
	{
		return (OOCreditsQuantity)base;
	}
}


OOCreditsQuantity OOCommodities::samplePriceForCommodity(const std::string &commodity, OOEconomyID economy, const std::optional<std::string> &scriptName, OOSystemID system)
{
	const auto entry = _commodityLists.find(commodity);
	if (entry == _commodityLists.end() || !entry->second.isDict())
	{
		return 0;
	}
	oo::PList good = entry->second;
	OOCreditsQuantity p = generatePriceForGood(good, economy);

	good = createDefinitionFrom(good, p, 0, commodity, nullptr, system);
	if (scriptName.has_value())
	{
		::OOScript *script = (PLAYER != nullptr ? PLAYER->commodityScriptNamed(scriptName) : (OOScript *)nullptr);	// (has a value: checked above)
		if (script != nil)
		{
			good = modifyGood(good, script, nullptr, system, true);
		}
	}
	return good.get<unsigned long long>(kOOCommodityPriceCurrent);
}


// positive = exporter; negative = importer; range -1.0 .. +1.0
float OOCommodities::economicBiasForGood(const oo::PList &good, OOEconomyID economy)
{
	OOEconomyID exporter = good.get<int>(kOOCommodityPeakExport);
	OOEconomyID importer = good.get<int>(kOOCommodityPeakImport);

	// *2 and /2 to work in ints at this stage
	int exDiff = abs(economy-exporter)*2;
	int imDiff = abs(economy-importer)*2;
	int distance = (exDiff+imDiff)/2;

	if (exDiff == imDiff)
	{
		// neutral economy
		return 0.0;
	}
	else if (exDiff > imDiff)
	{
		// closer to the importer, so return -ve
		return -(1.0-((float)imDiff/(float)distance));
	}
	else
	{
		// closer to the exporter, so return +ve
		return 1.0-((float)exDiff/(float)distance);
	}
}


oo::PList OOCommodities::firstModifierForGood(const std::string &good, const oo::PList &classes, const oo::PList &definitions)
{
	NSUInteger i;
	for (i = 0; i < definitions.count(); i++)
	{
		const oo::PList *definition = definitions.at(i);
		if (definition != nullptr && definition->isDict())
		{
			const std::string applicationType = StringFor(*definition, kOOCommodityMarketType).value_or(std::string(kOOCommodityMarketTypeValueDefault));
			const std::string applicationName = StringFor(*definition, kOOCommodityMarketName).value_or(std::string());

			if (
				applicationType == kOOCommodityMarketTypeValueDefault
				|| (applicationType == kOOCommodityMarketTypeValueGood && applicationName == good)
				|| (applicationType == kOOCommodityMarketTypeValueClass && ContainsString(classes, applicationName))
				)
			{
				return *definition;
			}
		}
	}
	// return a blank dictionary - default values will do the rest
	return oo::PList(oo::PList::Dict{});
}


OOCreditsQuantity OOCommodities::adjustPrice(OOCreditsQuantity price, const oo::PList &rule)
{
	float p = (float)price; // work in floats to avoid rounding problems
	float pa = rule.get<float>(kOOCommodityMarketPriceAdder, 0.0);
	float pm = rule.get<float>(kOOCommodityMarketPriceMultiplier, 1.0);
	if (pm <= 0.0 && pa <= 0.0)
	{
		// setting a price multiplier of 0 forces the price to zero
		return 0;
	}
	float pr = rule.get<float>(kOOCommodityMarketPriceRandomiser, 0.0);
	p += pa;
	p = (p * pm) + (p * pr * (randf()-randf()));
	if (p < 1.0)
	{
		// random variation and non-zero price multiplier can't reduce
		// price below 1 decicredit
		p = 1.0;
	}
	return (OOCreditsQuantity) p;
}


OOCargoQuantity OOCommodities::adjustQuantity(OOCargoQuantity quantity, const oo::PList &rule)
{
	float q = (float)quantity; // work in floats to avoid rounding problems
	float qa = rule.get<float>(kOOCommodityMarketQuantityAdder, 0.0);
	float qm = rule.get<float>(kOOCommodityMarketQuantityMultiplier, 1.0);
	if (qm <= 0.0 && qa <= 0.0)
	{
		// setting a price multiplier of 0 forces the price to zero
		return 0;
	}
	float qr = rule.get<float>(kOOCommodityMarketQuantityRandomiser, 0.0);
	q += qa;
	q = (q * qm) + (q * qr * (randf()-randf()));
	if (q < 0.0)
	{
		// random variation and non-zero price multiplier can't reduce
		// quantity below zero
		q = 0.0;
	}
	// may be over station capacity - that gets capped later
	return (OOCargoQuantity) q;
}


oo::PList OOCommodities::updateInfoFor(const oo::PList &good, const oo::PList &rule, OOCargoQuantity maxCapacity)
{
	oo::PList tmp = good;
	long long import = rule.get<long long>(kOOCommodityMarketLegalityImport, -1);
	if (import >= 0)
	{
		SetSigned(tmp, kOOCommodityLegalityImport, import);
	}

	long long exportValue = rule.get<long long>(kOOCommodityMarketLegalityExport, -1);
	if (exportValue >= 0)
	{
		SetSigned(tmp, kOOCommodityLegalityExport, import);	// (sic: upstream writes the import value here)
	}

	long long capacity = rule.get<long long>(kOOCommodityMarketCapacity, -1);
	if (capacity >= 0 && capacity <= (long long)maxCapacity)
	{
		SetSigned(tmp, kOOCommodityCapacity, capacity);
	}
	else
	{
		// set to the station max capacity
		SetSigned(tmp, kOOCommodityCapacity, maxCapacity);
	}

	return tmp;
}

