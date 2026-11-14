/*	test_OOCommodities.mm
	Unit tests for cxx::OOCommodities (src/Core/OOCommodities.h) and its Objective-C facade: bead oo-fqyw (Phase 3, proposed
	ADR-0056).

	OOCommodities reads trade-goods.plist and makes markets from it: the player's manifest, a blank
	market, a main-system market for an economy (quantities and prices from each good's averages,
	economic bias and random spread, capped at the good's capacity), a secondary station's market
	(the main market scaled to the station's capacity and adjusted by the first matching rule of its
	market definition), and a sample price. It also names, finds and picks goods.

	The game around it is replaced (ADR-0056 amendments oo-zffj, oo-8kx7): the resource manager
	returns the table below, UNIVERSE and the player answer from fields, stations are fakes, the
	string expander returns its input in angle brackets, and commodity scripts, which the test does
	not run, are aborting link stubs. The RNG is the game's own (legacy_random.c), reseeded by each
	test. The expectations were written against the Objective-C class and run on it first; that API is
	now the facade (OOCommodities+ObjCBridge.h), so they run through it, and the last tests pin the
	C++ API (whose markets are cxx::OOCommodityMarket) and the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCommodities.h"
#import "OOCommodityMarket.h"
#import "OOStringExpander.h"
#import "OOJSPropID.h"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>


// --- The game around the class --------------------------------------------------------------

static std::vector<std::string> gLog;

namespace {

oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


oo::PList Strings(std::initializer_list<const char *> strings)
{
	oo::PList::Array array;
	for (const char *s : strings)  array.push_back(oo::PList(s));
	return oo::PList(std::move(array));
}


// trade-goods.plist: food (exported by agricultural economies), furs (a luxury, capped at 30,
// illegal to export), gems (grams, no capacity), and one entry that is not a dictionary.
oo::PList TradeGoods()
{
	return Dict({
		{ "food", Dict({ { "name", oo::PList("Food") }, { "classes", Strings({ "oolite-edible" }) }, { "quantity_unit", oo::PList(0) },
			{ "peak_export", oo::PList(7) }, { "peak_import", oo::PList(0) },
			{ "price_average", oo::PList(50) }, { "price_economic", oo::PList(0.5) }, { "price_random", oo::PList(0.1) },
			{ "quantity_average", oo::PList(40) }, { "quantity_economic", oo::PList(0.5) }, { "quantity_random", oo::PList(0.1) } }) },
		{ "furs", Dict({ { "name", oo::PList("Furs") }, { "classes", Strings({ "oolite-luxury", "oolite-edible" }) }, { "quantity_unit", oo::PList(1) },
			{ "peak_export", oo::PList(2) }, { "peak_import", oo::PList(5) }, { "capacity", oo::PList(30) },
			{ "price_average", oo::PList(600) }, { "price_economic", oo::PList(0.3) }, { "price_random", oo::PList(0.2) },
			{ "quantity_average", oo::PList(50) }, { "quantity_economic", oo::PList(0.2) }, { "quantity_random", oo::PList(0.3) },
			{ "legality_export", oo::PList(1) }, { "legality_import", oo::PList(2) } }) },
		{ "gems", Dict({ { "name", oo::PList("Gem-stones") }, { "quantity_unit", oo::PList(2) },
			{ "peak_export", oo::PList(4) }, { "peak_import", oo::PList(4) },
			{ "price_average", oo::PList(160) }, { "price_economic", oo::PList(0.1) }, { "price_random", oo::PList(0.5) },
			{ "quantity_average", oo::PList(200) }, { "quantity_economic", oo::PList(0.1) }, { "quantity_random", oo::PList(0.5) } }) },
		{ "junk", oo::PList("not a dictionary") },
	});
}

}	// namespace


@interface ResourceManager: OOObject
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName mergeMode:(int)mergeMode cache:(BOOL)useCache;
@end

@implementation ResourceManager
+ (oo::PList) cxx_dictionaryFromFilesNamed:(const std::string &)fileName inFolder:(const std::optional<std::string> &)folderName mergeMode:(int)mergeMode cache:(BOOL)useCache
{
	gLog.push_back("resources " + fileName + " in " + folderName.value_or("-") + " merge " + std::to_string(mergeMode) + " cache " + std::to_string((int)useCache));
	return TradeGoods();
}
@end


@interface PlayerEntity: OOObject
- (id) cxx_commodityScriptNamed:(const std::optional<std::string> &)script;
@end

@implementation PlayerEntity
- (id) cxx_commodityScriptNamed:(const std::optional<std::string> &)script
{
	gLog.push_back("script " + script.value_or("(none)"));
	return nil;
}
@end

PlayerEntity *gOOPlayer = nil;


@interface Universe: OOObject
{
@public
	OOCommodityMarket *mainMarket;
}
- (OOSystemID) currentSystemID;
- (OOCommodityMarket *) commodityMarket;
@end

@implementation Universe
- (OOSystemID) currentSystemID				{ return 7; }
- (OOCommodityMarket *) commodityMarket		{ return mainMarket; }
@end

Universe *gSharedUniverse = nil;


@interface StationEntity: OOObject
{
@public
	oo::PList definition;
	std::optional<std::string> scriptName;
	OOCargoQuantity capacity;
	BOOL monitored;
}
- (oo::PList) cxx_marketDefinition;
- (std::optional<std::string>) cxx_marketScriptName;
- (OOCargoQuantity) marketCapacity;
- (BOOL) marketMonitored;
@end

@implementation StationEntity
- (oo::PList) cxx_marketDefinition					{ return definition; }
- (std::optional<std::string>) cxx_marketScriptName	{ return scriptName; }
- (OOCargoQuantity) marketCapacity					{ return capacity; }
- (BOOL) marketMonitored							{ return monitored; }
@end


// The expander: "<string>".
std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed seed, const std::string &string, const oo::PList &overrides, const oo::PList &legacyLocals, const std::optional<std::string> &systemName, OOExpandOptions options)
{
	return "<" + string + ">";
}

Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	return Random_Seed{};
}


// Link stubs: commodity scripts. The fakes answer no script, so the test never runs one.
JSContext *gOOJSMainThreadContext = nullptr;
JSAtom OOJSInternAtomPRIVATE(const char *)							{ std::abort(); }
JSValue OOJSValueFromNativeObject(JSContext *, id)					{ std::abort(); }
JSValue OOJSValueFromPList(JSContext *, const oo::PList &)				{ std::abort(); }
oo::PList cxx_OOJSPListFromJSObject(JSContext *, JSValueConst)			{ std::abort(); }


namespace {

void Reset()
{
	if (gSharedUniverse == nil)  gSharedUniverse = [[Universe alloc] init];
	if (gOOPlayer == nil)  gOOPlayer = [[PlayerEntity alloc] init];
	gLog.clear();
	ranrot_srand(20260930);
}


OOCommodities *Commodities()
{
	return [[[OOCommodities alloc] init] autorelease];
}


// A market, one good per entry: key quantity price capacity export/import legality unit.
std::string Describe(OOCommodityMarket *market)
{
	std::string result;
	for (const std::string &good : [market goods])
	{
		char buffer[256];
		std::snprintf(buffer, sizeof buffer, "%s q%u p%llu c%u l%zu/%zu u%d; ", good.c_str(), [market cxx_quantityForGood:good], (unsigned long long)[market cxx_priceForGood:good],
			[market cxx_capacityForGood:good], (size_t)[market cxx_exportLegalityForGood:good], (size_t)[market cxx_importLegalityForGood:good], (int)[market massUnitForGood:good]);
		result += buffer;
	}
	return result;
}


// The expected values of one test, in the order it checks them; a mismatch prints both sides.
class Expected
{
public:
	Expected(std::initializer_list<const char *> values) : values_(values.begin(), values.end()) {}
	~Expected()  { if (next_ != values_.size())  std::fprintf(stderr, "  %zu expected value(s) not checked\n", values_.size() - next_); }

	bool operator()(const std::string &actual)
	{
		const std::string expected = (next_ < values_.size()) ? values_[next_] : "(no more expected values)";
		next_++;
		if (actual == expected)  return true;
		std::fprintf(stderr, "  actual:   %s\n  expected: %s\n", actual.c_str(), expected.c_str());
		return false;
	}

private:
	std::vector<std::string>	values_;
	size_t						next_ = 0;
};


std::string Log()
{
	std::string result;
	for (const std::string &line : gLog)  result += line + "; ";
	return result;
}


StationEntity *Station(oo::PList definition, OOCargoQuantity capacity, BOOL monitored)
{
	StationEntity *station = [[[StationEntity alloc] init] autorelease];
	station->definition = std::move(definition);
	station->capacity = capacity;
	station->monitored = monitored;
	return station;
}

}	// namespace


OO_TEST(goods)
{
	Expected expect{
		"resources trade-goods.plist in Config merge 2 cache 1; ",
		"food furs gems junk ",
		"furs",
		"-",
		"furs junk food junk food food food junk ",
		"food textiles radioactives slaves liquor_wines luxuries narcotics computers machinery alloys firearms furs minerals gold platinum gem_stones alien_items food food ",
	};

	@autoreleasepool
	{
		Reset();
		OOCommodities *c = Commodities();
		OO_CHECK(expect(Log()));
		OO_CHECK([c count] == 4);
		std::string goods;
		for (const std::string &g : [c goods])  goods += g + " ";
		OO_CHECK(expect(goods));
		OO_CHECK([c cxx_goodDefined:"food"] && ![c cxx_goodDefined:"junk"] && ![c cxx_goodDefined:"unobtainium"]);
		OO_CHECK(expect([c cxx_goodNamed:"<Furs>"].value_or("-")));
		OO_CHECK(expect([c cxx_goodNamed:"Furs"].value_or("-")));
		OO_CHECK([c massUnitForGood:"food"] == UNITS_TONS && [c massUnitForGood:"furs"] == UNITS_KILOGRAMS && [c massUnitForGood:"gems"] == UNITS_GRAMS);
		OO_CHECK([c massUnitForGood:"junk"] == UNITS_TONS && [c massUnitForGood:"unobtainium"] == UNITS_TONS);
		std::string random;
		for (int i = 0; i < 8; i++)  random += [c getRandomCommodity] + " ";
		OO_CHECK(expect(random));
		std::string legacy;
		for (NSUInteger i = 0; i <= 18; i++)  legacy += [OOCommodities cxx_legacyCommodityType:i].value_or("-") + " ";
		OO_CHECK(expect(legacy));
	}
}


OO_TEST(markets)
{
	Expected expect{
		"food q0 p0 c4294967295 l0/0 u0; furs q0 p0 c4294967295 l1/2 u1; gems q0 p0 c4294967295 l0/0 u2; junk q0 p0 c4294967295 l0/0 u0; ",
		"food q0 p0 c0 l0/0 u0; furs q0 p0 c0 l1/2 u1; gems q0 p0 c0 l0/0 u2; junk q0 p0 c0 l0/0 u0; ",
		"food",
		"food q22 p76 c127 l0/0 u0; furs q30 p503 c30 l1/2 u1; gems q127 p132 c127 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"food q40 p54 c127 l0/0 u0; furs q30 p520 c30 l1/2 u1; gems q127 p132 c127 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"food q62 p26 c127 l0/0 u0; furs q30 p658 c30 l1/2 u1; gems q127 p132 c127 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"script (none); ",
		"script x.js; script x.js; script x.js; ",
	};

	@autoreleasepool
	{
		Reset();
		OOCommodities *c = Commodities();
		OO_CHECK(expect(Describe([c generateManifestForPlayer])));
		OO_CHECK(expect(Describe([c generateBlankMarket])));
		OO_CHECK(expect([[c generateManifestForPlayer] cxx_definitionForGood:"food"].get<std::string>("key")));
		for (OOEconomyID economy : { 0, 3, 7 })
		{
			Reset();
			OO_CHECK(expect(Describe([c cxx_generateMarketForSystemWithEconomy:economy andScript:std::nullopt])));
		}
		OO_CHECK(expect(Log()));
		Reset();
		// A sample price: a fresh price for one good (0 for one that is not a dictionary).
		struct { OOEconomyID economy; OOCreditsQuantity food, furs, gems; } const samples[] = { { 0, 78, 553, 178 }, { 4, 45, 659, 132 }, { 7, 23, 685, 159 } };
		for (const auto &sample : samples)
		{
			OO_CHECK([c cxx_samplePriceForCommodity:"food" inEconomy:sample.economy withScript:std::nullopt inSystem:3] == sample.food);
			OO_CHECK([c cxx_samplePriceForCommodity:"furs" inEconomy:sample.economy withScript:std::nullopt inSystem:3] == sample.furs);
			OO_CHECK([c cxx_samplePriceForCommodity:"gems" inEconomy:sample.economy withScript:"x.js" inSystem:3] == sample.gems);
			OO_CHECK([c cxx_samplePriceForCommodity:"junk" inEconomy:sample.economy withScript:std::nullopt inSystem:3] == 0);
		}
		OO_CHECK(expect(Log()));
	}
}


OO_TEST(stationMarkets)
{
	Expected expect{
		"food q34 p62 c127 l0/0 u0; furs q30 p400 c30 l1/2 u1; gems q127 p132 c127 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"food q0 p0 c0 l0/0 u0; furs q0 p0 c0 l1/2 u1; gems q0 p0 c0 l0/0 u2; junk q0 p0 c0 l0/0 u0; ",
		"food q16 p62 c60 l0/0 u0; furs q60 p400 c60 l1/2 u1; gems q60 p132 c60 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"food q7 p97 c50 l0/0 u0; furs q23 p457 c50 l0/0 u1; gems q8 p264 c8 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"food q73 p97 c500 l3/3 u0; furs q234 p457 c500 l3/3 u1; gems q8 p264 c8 l0/0 u2; junk q0 p0 c127 l0/0 u0; ",
		"script (none); ",
	};

	@autoreleasepool
	{
		Reset();
		OOCommodities *c = Commodities();
		gSharedUniverse->mainMarket = [c cxx_generateMarketForSystemWithEconomy:2 andScript:std::nullopt];
		OO_CHECK(expect(Describe(gSharedUniverse->mainMarket)));

		// No definition and no script: a blank market.
		Reset();
		OO_CHECK(expect(Describe([c generateMarketForStation:Station(oo::PList(), 100, YES)])));

		// A default rule; then rules for a good and a class, first match wins; unmonitored.
		Reset();
		OO_CHECK(expect(Describe([c generateMarketForStation:Station(oo::PList(oo::PList::Array{ Dict({ { "type", oo::PList("default") } }) }), 60, YES)])));
		Reset();
		oo::PList rules(oo::PList::Array{
			Dict({ { "type", oo::PList("good") }, { "name", oo::PList("gems") }, { "price_multiplier", oo::PList(2.0) }, { "quantity_adder", oo::PList(5) }, { "capacity", oo::PList(8) } }),
			Dict({ { "type", oo::PList("class") }, { "name", oo::PList("oolite-edible") }, { "price_adder", oo::PList(10) }, { "price_randomiser", oo::PList(0.5) },
				{ "quantity_multiplier", oo::PList(0.5) }, { "quantity_randomiser", oo::PList(0.2) }, { "legality_import", oo::PList(3) }, { "legality_export", oo::PList(0) } }),
			Dict({ { "type", oo::PList("default") }, { "price_multiplier", oo::PList(0) }, { "quantity_multiplier", oo::PList(0) } }),
			oo::PList("not a rule") });
		OO_CHECK(expect(Describe([c generateMarketForStation:Station(rules, 50, NO)])));
		Reset();
		OO_CHECK(expect(Describe([c generateMarketForStation:Station(rules, 500, YES)])));
		OO_CHECK(expect(Log()));
		gSharedUniverse->mainMarket = nil;
	}
}


OO_TEST(cxxClass)
{
	@autoreleasepool
	{
		Reset();
		oo::Ref<cxx::OOCommodities> c = oo::makeRef<cxx::OOCommodities>();
		OO_CHECK(c->count() == 4 && c->goods() == std::vector<std::string>({ "food", "furs", "gems", "junk" }));
		OO_CHECK(c->goodDefined("furs") && !c->goodDefined("junk"));
		OO_CHECK(c->goodNamed("<Gem-stones>") == std::optional<std::string>("gems"));
		OO_CHECK(c->massUnitForGood("gems") == UNITS_GRAMS);
		OO_CHECK(cxx::OOCommodities::legacyCommodityType(11) == std::optional<std::string>("furs"));

		// Its markets are C++ markets; the same answers as through the facade.
		oo::Ref<cxx::OOCommodityMarket> manifest = c->generateManifestForPlayer();
		OO_CHECK(manifest->count() == 4 && manifest->capacityForGood("food") == UINT32_MAX);
		OO_CHECK(Describe(oo::ToObjC(c->generateBlankMarket())) == "food q0 p0 c0 l0/0 u0; furs q0 p0 c0 l1/2 u1; gems q0 p0 c0 l0/0 u2; junk q0 p0 c0 l0/0 u0; ");
		Reset();
		OO_CHECK(Describe(oo::ToObjC(c->generateMarketForSystemWithEconomy(0, std::nullopt))) == "food q22 p76 c127 l0/0 u0; furs q30 p503 c30 l1/2 u1; gems q127 p132 c127 l0/0 u2; junk q0 p0 c127 l0/0 u0; ");
		Reset();
		OO_CHECK(c->samplePriceForCommodity("food", 0, std::nullopt, 3) == 78);

		// A station market reads the main market through Universe's facade.
		Reset();
		gSharedUniverse->mainMarket = oo::ToObjC(c->generateMarketForSystemWithEconomy(2, std::nullopt));
		Reset();
		OO_CHECK(Describe(oo::ToObjC(c->generateMarketForStation(Station(oo::PList(oo::PList::Array{ Dict({ { "type", oo::PList("default") } }) }), 60, YES))))
			== "food q16 p62 c60 l0/0 u0; furs q60 p400 c60 l1/2 u1; gems q60 p132 c60 l0/0 u2; junk q0 p0 c127 l0/0 u0; ");
		gSharedUniverse->mainMarket = nil;
	}
}


OO_TEST(facadeNilStaysNil)
{
	OOCommodities *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOCommodities *>(nullptr)) == nil);
	OO_CHECK([none count] == 0 && [none generateBlankMarket] == nil);
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		Reset();
		OOCommodities *c = Commodities();
		OO_CHECK(oo::ToObjC(oo::ToCxx(c)) == c);

		// A market it makes crosses as that market's one facade.
		OOCommodityMarket *manifest = [c generateManifestForPlayer];
		OO_CHECK(manifest != nil && oo::ToObjC(oo::ToCxx(manifest)) == manifest);
		OO_CHECK([c generateBlankMarket] != [c generateBlankMarket]);	// a new market each time, as before

		oo::Ref<cxx::OOCommodities> cxxCommodities = oo::makeRef<cxx::OOCommodities>();
		OOCommodities *facade = oo::ToObjC(cxxCommodities);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxCommodities.get()) && oo::ToCxx(facade) == cxxCommodities.get());
		OO_CHECK([facade count] == 4);
	}
}


OO_TEST_MAIN()
