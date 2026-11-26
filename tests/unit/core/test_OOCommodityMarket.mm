/*	test_OOCommodityMarket.mm
	Unit tests for OOCommodityMarket (src/Core/OOCommodityMarket.h): bead oo-ih7y (Phase 3, proposed
	ADR-0056).

	A market is a table of goods, each a trade-goods.plist definition (a dictionary): the goods in
	sort_order, prices and quantities set within the good's capacity (127 where it has none), the
	definitions' texts expanded, the mass unit, legality and trumble opinion read back, and the
	player's and a station's amounts saved and loaded, including 1.80-era saves that name goods by
	their display name. The string expander is replaced (ADR-0056 amendment oo-8kx7): it returns
	its input in angle brackets.
	The expectations were written against the Objective-C class and run on it first; bead oo-9ht.21
	deleted that facade, and the same expectations now ask the C++ class (held as oo::Ref where the
	autoreleased facade was); the last tests pin the C++ API.
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
oo::Ref<OOCommodityMarket> Market()
{
	oo::Ref<OOCommodityMarket> market = oo::makeRef<OOCommodityMarket>();
	market->setGood("gems", Good({ { "name", oo::PList("Gem-stones") }, { "sort_order", oo::PList(2) }, { "quantity_unit", oo::PList(2) }, { "price", oo::PList(500) }, { "quantity", oo::PList(3) }, { "capacity", oo::PList(10) } }));
	market->setGood("food", Good({ { "name", oo::PList("Food") }, { "sort_order", oo::PList(1) }, { "quantity_unit", oo::PList(0) }, { "price", oo::PList(40) }, { "quantity", oo::PList(20) }, { "trumble_opinion", oo::PList(1.0) }, { "comment", oo::PList("Tasty") }, { "short_comment", oo::PList("yum") } }));
	market->setGood("furs", Good({ { "name", oo::PList("Furs") }, { "sort_order", oo::PList(2) }, { "quantity_unit", oo::PList(1) }, { "price", oo::PList(560) }, { "quantity", oo::PList(0) }, { "legality_export", oo::PList(1) }, { "legality_import", oo::PList(2) }, { "trumble_opinion", oo::PList(0.5) } }));
	market->setGood("alloys", Good({ { "name", oo::PList("Alloys") }, { "sort_order", oo::PList(0) }, { "quantity_unit", oo::PList(7) } }));
	market->setGood("radioactives", oo::PList("not a dictionary"));
	return market;
}


using Goods = std::vector<std::string>;

}	// namespace


OO_TEST(goodsAndDefinitions)
{
	@autoreleasepool
	{
		oo::Ref<OOCommodityMarket> m = Market();
		OO_CHECK(m->count() == 5);
		OO_CHECK(m->goods() == Goods({ "alloys", "radioactives", "food", "furs", "gems" }));
		OO_CHECK(m->dictionaryForScripting().count() == 5);
		OO_CHECK(m->definitionForGood("radioactives") == oo::PList(oo::PList::Dict{}));	// not a dictionary: an empty one
		OO_CHECK(m->definitionForGood("unobtainium").isNull());
		OO_CHECK(m->definitionForGood("furs").get<int>("legality_import") == 2);

		// Names and comments, expanded; the defaults for a missing text or good.
		OO_CHECK(m->nameForGood("food") == std::optional<std::string>("<Food>"));
		OO_CHECK(m->nameForGood("radioactives") == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));
		OO_CHECK(m->nameForGood("unobtainium") == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));
		OO_CHECK(m->commentForGood("food") == std::optional<std::string>("<Tasty>"));
		OO_CHECK(m->commentForGood("furs") == std::optional<std::string>("<[oolite-commodity-no-comment]>"));
		OO_CHECK(m->commentForGood("unobtainium") == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));
		OO_CHECK(m->shortCommentForGood("food") == std::optional<std::string>("<yum>"));
		OO_CHECK(m->shortCommentForGood("furs") == std::optional<std::string>("<[oolite-commodity-no-short-comment]>"));
		OO_CHECK(m->shortCommentForGood("unobtainium") == std::optional<std::string>("<[oolite-unknown-commodity-name]>"));

		// Numbers, and what an unknown good answers.
		OO_CHECK(m->priceForGood("furs") == 560 && m->priceForGood("alloys") == 0 && m->priceForGood("unobtainium") == 0);
		OO_CHECK(m->quantityForGood("food") == 20 && m->quantityForGood("unobtainium") == 0);
		OO_CHECK(m->massUnitForGood("food") == UNITS_TONS && m->massUnitForGood("furs") == UNITS_KILOGRAMS && m->massUnitForGood("gems") == UNITS_GRAMS);
		OO_CHECK(m->massUnitForGood("alloys") == UNITS_UNKNOWN && m->massUnitForGood("unobtainium") == UNITS_TONS);
		OO_CHECK(m->exportLegalityForGood("furs") == 1 && m->importLegalityForGood("furs") == 2);
		OO_CHECK(m->exportLegalityForGood("food") == 0 && m->importLegalityForGood("unobtainium") == 0);
		OO_CHECK(m->capacityForGood("gems") == 10 && m->capacityForGood("food") == MAIN_SYSTEM_MARKET_LIMIT && m->capacityForGood("unobtainium") == 0);
		OO_CHECK(m->trumbleOpinionForGood("food") == 1.0f && m->trumbleOpinionForGood("furs") == 0.5f && m->trumbleOpinionForGood("gems") == 0.0f);
		OO_CHECK(m->trumbleOpinionForGood("unobtainium") == 0.0f);

		// A new good resorts; replacing one keeps the count.
		m->setGood("aardvarks", Good({ { "sort_order", oo::PList(1) } }));
		OO_CHECK(m->goods() == Goods({ "alloys", "radioactives", "aardvarks", "food", "furs", "gems" }));
		m->setGood("gems", Good({ { "sort_order", oo::PList(-1) } }));
		OO_CHECK(m->count() == 6 && m->goods().front() == "gems");
	}
}


OO_TEST(pricesAndQuantities)
{
	@autoreleasepool
	{
		oo::Ref<OOCommodityMarket> m = Market();
		OO_CHECK(m->setPrice(99, "food") && m->priceForGood("food") == 99);
		OO_CHECK(!m->setPrice(99, "unobtainium"));

		OO_CHECK(m->setQuantity(10, "gems") && m->quantityForGood("gems") == 10);
		OO_CHECK(!m->setQuantity(11, "gems") && m->quantityForGood("gems") == 10);	// over capacity
		OO_CHECK(!m->setQuantity(1, "unobtainium"));
		OO_CHECK(!m->addQuantity(1, "gems"));
		OO_CHECK(m->removeQuantity(4, "gems") && m->quantityForGood("gems") == 6);
		OO_CHECK(m->addQuantity(4, "gems") && m->quantityForGood("gems") == 10);
		OO_CHECK(!m->removeQuantity(11, "gems") && m->quantityForGood("gems") == 10);
		OO_CHECK(m->addQuantity(107, "food") && m->quantityForGood("food") == 127);
		OO_CHECK(!m->addQuantity(1, "food"));
		OO_CHECK(!m->addQuantity(1, "unobtainium") && !m->removeQuantity(1, "unobtainium"));

		OO_CHECK(m->setComment("New", "furs") && m->commentForGood("furs") == std::optional<std::string>("<New>"));
		OO_CHECK(m->setShortComment("new", "furs") && m->shortCommentForGood("furs") == std::optional<std::string>("<new>"));
		OO_CHECK(!m->setComment("x", "unobtainium") && !m->setShortComment("x", "unobtainium"));

		m->removeAllGoods();
		for (const std::string &good : m->goods())  OO_CHECK(m->quantityForGood(good) == 0);
		OO_CHECK(m->priceForGood("food") == 99);
	}
}


OO_TEST(savedAmounts)
{
	@autoreleasepool
	{
		oo::Ref<OOCommodityMarket> m = Market();
		OO_CHECK(m->savePlayerAmounts() == oo::PList(oo::PList::Array{
			oo::PList(oo::PList::Array{ oo::PList("alloys"), oo::PList::unsignedInteger(0) }),
			oo::PList(oo::PList::Array{ oo::PList("radioactives"), oo::PList::unsignedInteger(0) }),
			oo::PList(oo::PList::Array{ oo::PList("food"), oo::PList::unsignedInteger(20) }),
			oo::PList(oo::PList::Array{ oo::PList("furs"), oo::PList::unsignedInteger(0) }),
			oo::PList(oo::PList::Array{ oo::PList("gems"), oo::PList::unsignedInteger(3) }) }));
		OO_CHECK(m->saveStationAmounts().at(2) != nullptr && *m->saveStationAmounts().at(2) == oo::PList(oo::PList::Array{ oo::PList("food"), oo::PList::unsignedInteger(20), oo::PList::unsignedInteger(40) }));

		// Loading zeroes the goods a save does not mention; a 1.80 save names a good by its
		// (expanded) name; a good that no longer exists, or too much of one, is skipped.
		oo::Ref<OOCommodityMarket> player = Market();
		player->loadPlayerAmounts(oo::PList(oo::PList::Array{ oo::PList(oo::PList::Array{ oo::PList("furs"), oo::PList(5) }), oo::PList(oo::PList::Array{ oo::PList("<Gem-stones>"), oo::PList(2), oo::PList("extra") }), oo::PList(oo::PList::Array{ oo::PList("unobtainium"), oo::PList(1) }), oo::PList(oo::PList::Array{ oo::PList("alloys"), oo::PList(500) }), oo::PList(oo::PList::Array{ oo::PList(7), oo::PList(1) }) }));
		OO_CHECK(player->quantityForGood("furs") == 5 && player->quantityForGood("gems") == 2);
		OO_CHECK(player->quantityForGood("food") == 0 && player->quantityForGood("alloys") == 0);
		player->loadPlayerAmounts(oo::PList());
		OO_CHECK(player->quantityForGood("furs") == 0);

		oo::Ref<OOCommodityMarket> station = Market();
		station->loadStationAmounts(oo::PList(oo::PList::Array{ oo::PList(oo::PList::Array{ oo::PList("furs"), oo::PList(5), oo::PList(600) }), oo::PList(oo::PList::Array{ oo::PList("<Food>"), oo::PList(6), oo::PList(41) }), oo::PList(oo::PList::Array{ oo::PList("unobtainium"), oo::PList(1), oo::PList(1) }) }));
		OO_CHECK(station->quantityForGood("furs") == 5 && station->priceForGood("furs") == 600);
		OO_CHECK(station->quantityForGood("food") == 6 && station->priceForGood("food") == 41);
		OO_CHECK(station->quantityForGood("gems") == 3 && station->priceForGood("gems") == 500);	// untouched
	}
}


OO_TEST(cxxClass)
{
	oo::Ref<OOCommodityMarket> m = oo::makeRef<OOCommodityMarket>();
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


OO_TEST(facadeIdentity)
{
	@autoreleasepool
	{
		// A C++ market sees its goods.
		oo::Ref<OOCommodityMarket> cxxMarket = oo::makeRef<OOCommodityMarket>();
		cxxMarket->setGood("food", Good({ { "price", oo::PList(3) } }));
		OO_CHECK(cxxMarket->priceForGood("food") == 3);
		cxxMarket->setPrice(4, "food");
		OO_CHECK(cxxMarket->priceForGood("food") == 4);

		OO_CHECK(oo::makeRef<OOCommodityMarket>() != oo::makeRef<OOCommodityMarket>());	// distinct objects, as before
	}
}


OO_TEST_MAIN()
