/*	test_OOCommodityMarket.mm
	Unit tests for cxx::OOCommodityMarket (src/Core/OOCommodityMarket.h) and its Objective-C facade:
	bead oo-ih7y (Phase 3,
	proposed ADR-0056).

	A market is a table of goods, each a trade-goods.plist definition (a dictionary): the goods in
	sort_order, prices and quantities set within the good's capacity (127 where it has none), the
	definitions' texts expanded, the mass unit, legality and trumble opinion read back, and the
	player's and a station's amounts saved and loaded, including 1.80-era saves that name goods by
	their display name. The string expander is replaced (ADR-0056 amendment oo-8kx7): it returns
	its input in angle brackets.
	The expectations were written against the Objective-C class and run on it first; that API is
	now the facade (OOCommodityMarket+ObjCBridge.h), so they run through it, and the last tests pin
	the C++ API and the facade's contract.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCommodityMarket.h"
#import "OOStringExpander.h"

#include "oo_test.hpp"

#include <string>
#include <vector>


// The expander: "<string>". A test replacement, not a stub: the names and comments go through it.
std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed seed, const std::string &string, const oo::PList &overrides, const oo::PList &legacyLocals, const std::optional<std::string> &systemName, OOExpandOptions options)
{
	return "<" + string + ">";
}

Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	return Random_Seed{};
}


namespace {

oo::PList Good(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


// food (sort 1), furs and gems (both sort 2: key order), alloys (sort 0), radioactives (no sort
// order: 0, and after alloys by key).
OOCommodityMarket *Market()
{
	OOCommodityMarket *market = [[[OOCommodityMarket alloc] init] autorelease];
	[market cxx_setGood:"gems" withInfo:Good({ { "name", oo::PList("Gem-stones") }, { "sort_order", oo::PList(2) }, { "quantity_unit", oo::PList(2) }, { "price", oo::PList(500) }, { "quantity", oo::PList(3) }, { "capacity", oo::PList(10) } })];
	[market cxx_setGood:"food" withInfo:Good({ { "name", oo::PList("Food") }, { "sort_order", oo::PList(1) }, { "quantity_unit", oo::PList(0) }, { "price", oo::PList(40) }, { "quantity", oo::PList(20) }, { "trumble_opinion", oo::PList(1.0) }, { "comment", oo::PList("Tasty") }, { "short_comment", oo::PList("yum") } })];
	[market cxx_setGood:"furs" withInfo:Good({ { "name", oo::PList("Furs") }, { "sort_order", oo::PList(2) }, { "quantity_unit", oo::PList(1) }, { "price", oo::PList(560) }, { "quantity", oo::PList(0) }, { "legality_export", oo::PList(1) }, { "legality_import", oo::PList(2) }, { "trumble_opinion", oo::PList(0.5) } })];
	[market cxx_setGood:"alloys" withInfo:Good({ { "name", oo::PList("Alloys") }, { "sort_order", oo::PList(0) }, { "quantity_unit", oo::PList(7) } })];
	[market cxx_setGood:"radioactives" withInfo:oo::PList("not a dictionary")];
	return market;
}


using Goods = std::vector<std::string>;

}	// namespace


OO_TEST(goodsAndDefinitions)
{
	@autoreleasepool
	{
		OOCommodityMarket *m = Market();
		OO_CHECK([m count] == 5);
		OO_CHECK([m goods] == Goods({ "alloys", "radioactives", "food", "furs", "gems" }));
		OO_CHECK([m dictionaryForScripting].count() == 5);
		OO_CHECK([m cxx_definitionForGood:"radioactives"] == oo::PList(oo::PList::Dict{}));	// not a dictionary: an empty one
		OO_CHECK([m cxx_definitionForGood:"unobtainium"].isNull());
		OO_CHECK([m cxx_definitionForGood:"furs"].get<int>("legality_import") == 2);

		// Names and comments, expanded; the defaults for a missing text or good.
		OO_CHECK([m cxx_nameForGood:"food"] == std::optional<std::string>("<Food>"));
		OO_CHECK([m cxx_nameForGood:"radioactives"] == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));
		OO_CHECK([m cxx_nameForGood:"unobtainium"] == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));
		OO_CHECK([m cxx_commentForGood:"food"] == std::optional<std::string>("<Tasty>"));
		OO_CHECK([m cxx_commentForGood:"furs"] == std::optional<std::string>("<[oolite-commodity-no-comment]>"));
		OO_CHECK([m cxx_commentForGood:"unobtainium"] == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));
		OO_CHECK([m cxx_shortCommentForGood:"food"] == std::optional<std::string>("<yum>"));
		OO_CHECK([m cxx_shortCommentForGood:"furs"] == std::optional<std::string>("<[oolite-commodity-no-short-comment]>"));
		OO_CHECK([m cxx_shortCommentForGood:"unobtainium"] == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));

		// Numbers, and what an unknown good answers.
		OO_CHECK([m cxx_priceForGood:"furs"] == 560 && [m cxx_priceForGood:"alloys"] == 0 && [m cxx_priceForGood:"unobtainium"] == 0);
		OO_CHECK([m cxx_quantityForGood:"food"] == 20 && [m cxx_quantityForGood:"unobtainium"] == 0);
		OO_CHECK([m massUnitForGood:"food"] == UNITS_TONS && [m massUnitForGood:"furs"] == UNITS_KILOGRAMS && [m massUnitForGood:"gems"] == UNITS_GRAMS);
		OO_CHECK([m massUnitForGood:"alloys"] == UNITS_UNKNOWN && [m massUnitForGood:"unobtainium"] == UNITS_TONS);
		OO_CHECK([m cxx_exportLegalityForGood:"furs"] == 1 && [m cxx_importLegalityForGood:"furs"] == 2);
		OO_CHECK([m cxx_exportLegalityForGood:"food"] == 0 && [m cxx_importLegalityForGood:"unobtainium"] == 0);
		OO_CHECK([m cxx_capacityForGood:"gems"] == 10 && [m cxx_capacityForGood:"food"] == MAIN_SYSTEM_MARKET_LIMIT && [m cxx_capacityForGood:"unobtainium"] == 0);
		OO_CHECK([m cxx_trumbleOpinionForGood:"food"] == 1.0f && [m cxx_trumbleOpinionForGood:"furs"] == 0.5f && [m cxx_trumbleOpinionForGood:"gems"] == 0.0f);
		OO_CHECK([m cxx_trumbleOpinionForGood:"unobtainium"] == 0.0f);

		// A new good resorts; replacing one keeps the count.
		[m cxx_setGood:"aardvarks" withInfo:Good({ { "sort_order", oo::PList(1) } })];
		OO_CHECK([m goods] == Goods({ "alloys", "radioactives", "aardvarks", "food", "furs", "gems" }));
		[m cxx_setGood:"gems" withInfo:Good({ { "sort_order", oo::PList(-1) } })];
		OO_CHECK([m count] == 6 && [m goods].front() == "gems");
	}
}


OO_TEST(pricesAndQuantities)
{
	@autoreleasepool
	{
		OOCommodityMarket *m = Market();
		OO_CHECK([m cxx_setPrice:99 forGood:"food"] && [m cxx_priceForGood:"food"] == 99);
		OO_CHECK(![m cxx_setPrice:99 forGood:"unobtainium"]);

		OO_CHECK([m cxx_setQuantity:10 forGood:"gems"] && [m cxx_quantityForGood:"gems"] == 10);
		OO_CHECK(![m cxx_setQuantity:11 forGood:"gems"] && [m cxx_quantityForGood:"gems"] == 10);	// over capacity
		OO_CHECK(![m cxx_setQuantity:1 forGood:"unobtainium"]);
		OO_CHECK(![m cxx_addQuantity:1 forGood:"gems"]);
		OO_CHECK([m cxx_removeQuantity:4 forGood:"gems"] && [m cxx_quantityForGood:"gems"] == 6);
		OO_CHECK([m cxx_addQuantity:4 forGood:"gems"] && [m cxx_quantityForGood:"gems"] == 10);
		OO_CHECK(![m cxx_removeQuantity:11 forGood:"gems"] && [m cxx_quantityForGood:"gems"] == 10);
		OO_CHECK([m cxx_addQuantity:107 forGood:"food"] && [m cxx_quantityForGood:"food"] == 127);
		OO_CHECK(![m cxx_addQuantity:1 forGood:"food"]);
		OO_CHECK(![m cxx_addQuantity:1 forGood:"unobtainium"] && ![m cxx_removeQuantity:1 forGood:"unobtainium"]);

		OO_CHECK([m cxx_setComment:"New" forGood:"furs"] && [m cxx_commentForGood:"furs"] == std::optional<std::string>("<New>"));
		OO_CHECK([m cxx_setShortComment:"new" forGood:"furs"] && [m cxx_shortCommentForGood:"furs"] == std::optional<std::string>("<new>"));
		OO_CHECK(![m cxx_setComment:"x" forGood:"unobtainium"] && ![m cxx_setShortComment:"x" forGood:"unobtainium"]);

		[m removeAllGoods];
		for (const std::string &good : [m goods])  OO_CHECK([m cxx_quantityForGood:good] == 0);
		OO_CHECK([m cxx_priceForGood:"food"] == 99);
	}
}


OO_TEST(savedAmounts)
{
	@autoreleasepool
	{
		OOCommodityMarket *m = Market();
		OO_CHECK([m cxx_savePlayerAmounts] == oo::PList(oo::PList::Array{
			oo::PList(oo::PList::Array{ oo::PList("alloys"), oo::PList::unsignedInteger(0) }),
			oo::PList(oo::PList::Array{ oo::PList("radioactives"), oo::PList::unsignedInteger(0) }),
			oo::PList(oo::PList::Array{ oo::PList("food"), oo::PList::unsignedInteger(20) }),
			oo::PList(oo::PList::Array{ oo::PList("furs"), oo::PList::unsignedInteger(0) }),
			oo::PList(oo::PList::Array{ oo::PList("gems"), oo::PList::unsignedInteger(3) }) }));
		OO_CHECK([m cxx_saveStationAmounts].at(2) != nullptr && *[m cxx_saveStationAmounts].at(2) == oo::PList(oo::PList::Array{ oo::PList("food"), oo::PList::unsignedInteger(20), oo::PList::unsignedInteger(40) }));

		// Loading zeroes the goods a save does not mention; a 1.80 save names a good by its
		// (expanded) name; a good that no longer exists, or too much of one, is skipped.
		OOCommodityMarket *player = Market();
		[player cxx_loadPlayerAmounts:oo::PList(oo::PList::Array{
			oo::PList(oo::PList::Array{ oo::PList("furs"), oo::PList(5) }),
			oo::PList(oo::PList::Array{ oo::PList("<Gem-stones>"), oo::PList(2), oo::PList("extra") }),
			oo::PList(oo::PList::Array{ oo::PList("unobtainium"), oo::PList(1) }),
			oo::PList(oo::PList::Array{ oo::PList("alloys"), oo::PList(500) }),
			oo::PList(oo::PList::Array{ oo::PList(7), oo::PList(1) }) })];
		OO_CHECK([player cxx_quantityForGood:"furs"] == 5 && [player cxx_quantityForGood:"gems"] == 2);
		OO_CHECK([player cxx_quantityForGood:"food"] == 0 && [player cxx_quantityForGood:"alloys"] == 0);
		[player cxx_loadPlayerAmounts:oo::PList()];
		OO_CHECK([player cxx_quantityForGood:"furs"] == 0);

		OOCommodityMarket *station = Market();
		[station cxx_loadStationAmounts:oo::PList(oo::PList::Array{
			oo::PList(oo::PList::Array{ oo::PList("furs"), oo::PList(5), oo::PList(600) }),
			oo::PList(oo::PList::Array{ oo::PList("<Food>"), oo::PList(6), oo::PList(41) }),
			oo::PList(oo::PList::Array{ oo::PList("unobtainium"), oo::PList(1), oo::PList(1) }) })];
		OO_CHECK([station cxx_quantityForGood:"furs"] == 5 && [station cxx_priceForGood:"furs"] == 600);
		OO_CHECK([station cxx_quantityForGood:"food"] == 6 && [station cxx_priceForGood:"food"] == 41);
		OO_CHECK([station cxx_quantityForGood:"gems"] == 3 && [station cxx_priceForGood:"gems"] == 500);	// untouched
	}
}


OO_TEST(cxxClass)
{
	oo::Ref<cxx::OOCommodityMarket> m = oo::makeRef<cxx::OOCommodityMarket>();
	OO_CHECK(m->count() == 0 && m->goods().empty() && m->savePlayerAmounts() == oo::PList(oo::PList::Array{}));
	m->setGood("gems", Good({ { "name", oo::PList("Gem-stones") }, { "sort_order", oo::PList(2) }, { "capacity", oo::PList(10) }, { "price", oo::PList(500) } }));
	m->setGood("food", Good({ { "name", oo::PList("Food") }, { "sort_order", oo::PList(1) } }));
	OO_CHECK(m->goods() == Goods({ "food", "gems" }));
	OO_CHECK(m->setQuantity(10, "gems") && !m->addQuantity(1, "gems") && m->removeQuantity(3, "gems"));
	OO_CHECK(m->quantityForGood("gems") == 7 && m->priceForGood("gems") == 500 && m->capacityForGood("food") == MAIN_SYSTEM_MARKET_LIMIT);
	OO_CHECK(m->nameForGood("gems") == std::optional<std::string>("<Gem-stones>"));
	OO_CHECK(m->definitionForGood("unobtainium").isNull());
	OO_CHECK(m->saveStationAmounts() == oo::PList(oo::PList::Array{
		oo::PList(oo::PList::Array{ oo::PList("food"), oo::PList::unsignedInteger(0), oo::PList::unsignedInteger(0) }),
		oo::PList(oo::PList::Array{ oo::PList("gems"), oo::PList::unsignedInteger(7), oo::PList::unsignedInteger(500) }) }));
}


OO_TEST(facadeNilStaysNil)
{
	OOCommodityMarket *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOCommodityMarket *>(nullptr)) == nil);
	OO_CHECK([none count] == 0 && [none goods].empty());
	OO_CHECK(![none cxx_setPrice:1 forGood:"food"]);
	OO_CHECK(![none cxx_nameForGood:"food"].has_value());
}


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		OOCommodityMarket *m = Market();
		OO_CHECK(oo::ToObjC(oo::ToCxx(m)) == m);

		// A C++ market crosses to one facade, and back to itself; the facade sees its goods.
		oo::Ref<cxx::OOCommodityMarket> cxxMarket = oo::makeRef<cxx::OOCommodityMarket>();
		cxxMarket->setGood("food", Good({ { "price", oo::PList(3) } }));
		OOCommodityMarket *facade = oo::ToObjC(cxxMarket);
		OO_CHECK(facade != nil && facade == oo::ToObjC(cxxMarket.get()));
		OO_CHECK(oo::ToCxx(facade) == cxxMarket.get());
		OO_CHECK([facade cxx_priceForGood:"food"] == 3);
		[facade cxx_setPrice:4 forGood:"food"];
		OO_CHECK(cxxMarket->priceForGood("food") == 4);

		OO_CHECK([[[OOCommodityMarket alloc] init] autorelease] != [[[OOCommodityMarket alloc] init] autorelease]);	// distinct objects, as before
	}
}


OO_TEST_MAIN()
