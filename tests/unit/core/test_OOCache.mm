/*	test_OOCache.mm
	Unit tests for OOCache (src/Core/OOCache.h): bead oo-rdfh, a Phase 3 conversion in the house
	style of the OOColor exemplar (proposed ADR-0056).

	It pins what the cache computed before the conversion: an empty cache's settings, storing,
	replacing and removing values (a null value is not stored), dirtiness, least-recently-used
	order (a lookup promotes), pruning (the threshold's floor, auto-pruning to 80%, manual pruning
	to the threshold, no pruning while loading), the property-list round trip, a live object held
	in an Object node, the name and the description. The expectations were written against the
	Objective-C API and run on the unconverted class first (commit f751759c8); both callers were
	adapted in the bead, so there is no facade and the calls here are the C++ class's.
	Run: bash tools/check-core-tests.sh
*/

#import "OOCache.h"
#import "OODescription.h"
#import "OOObjCPList.h"

#include "oo_test.hpp"


/*	The game's OOStringParsing.mm reaches the JavaScript engine, so it is not linked. The one
	function of it that the cache names (in its DEBUG_GRAPHVIZ dump, which no test calls) is
	defined here instead.
*/
std::string cxx_EscapedGraphVizString(const std::string &string)
{
	return string;
}


namespace {

oo::PList Str(const std::string &string)
{
	return oo::PList(string);
}


std::vector<std::string> Strings(const std::vector<oo::PList> &values)
{
	std::vector<std::string> result;
	for (const oo::PList &value : values)  result.push_back(value.isString() ? *value.getIf<std::string>() : std::string("?"));
	return result;
}


oo::PList Entry(const std::string &key, const oo::PList &value)
{
	oo::PList::Dict entry;
	entry.emplace("key", Str(key));
	entry.emplace("value", value);
	return oo::PList(std::move(entry));
}

}	// namespace


OO_TEST(emptyCache)
{
	@autoreleasepool
	{
		oo::Ref<OOCache> cache = OOCache::cacheWithPList(oo::PList());
		OO_CHECK(cache != nullptr);
		OO_CHECK(cache->pruneThreshold() == kOOCacheDefaultPruneThreshold);
		OO_CHECK(cache->autoPrune());
		OO_CHECK(!cache->dirty());
		OO_CHECK(!cache->name().has_value());
		OO_CHECK(cache->pListRepresentation().isNull());
		OO_CHECK(cache->pListsByAge().empty());
		OO_CHECK(cache->pListForKey("absent").isNull());

		OO_CHECK(cache->descriptionComponents() == std::optional<std::string>("\"(null)\", 0 elements, prune threshold=200, auto-prune=yes dirty=no"));
		cache->setName(std::string("Text encoding"));
		OO_CHECK(cache->name() == std::optional<std::string>("Text encoding"));
		OO_CHECK(cache->descriptionComponents() == std::optional<std::string>("\"Text encoding\", 0 elements, prune threshold=200, auto-prune=yes dirty=no"));
		cache->setName(std::nullopt);
		OO_CHECK(!cache->name().has_value());
	}
}


OO_TEST(storeReplaceRemove)
{
	@autoreleasepool
	{
		oo::Ref<OOCache> cache = OOCache::cacheWithPList(oo::PList());
		cache->setPList(oo::PList(), "null");	// a null value is not stored
		OO_CHECK(!cache->dirty() && cache->pListsByAge().empty());

		cache->setPList(Str("one"), "a");
		OO_CHECK(cache->dirty());
		OO_CHECK(cache->pListForKey("a") == Str("one"));
		cache->markClean();
		OO_CHECK(!cache->dirty());

		cache->setPList(Str("uno"), "a");	// replacing marks it dirty too
		OO_CHECK(cache->dirty() && cache->pListForKey("a") == Str("uno"));
		cache->markClean();

		cache->removePListForKey("b");	// absent: not dirty
		OO_CHECK(!cache->dirty());
		cache->removePListForKey("a");
		OO_CHECK(cache->dirty() && cache->pListForKey("a").isNull());
		OO_CHECK(cache->descriptionComponents() == std::optional<std::string>("\"(null)\", 0 elements, prune threshold=200, auto-prune=yes dirty=yes"));
	}
}


OO_TEST(leastRecentlyUsedOrder)
{
	@autoreleasepool
	{
		oo::Ref<OOCache> cache = OOCache::cacheWithPList(oo::PList());
		for (const char *key : { "d", "b", "a", "c" })  cache->setPList(Str(std::string("value ") + key), key);
		OO_CHECK(Strings(cache->pListsByAge()) == std::vector<std::string>({ "value c", "value a", "value b", "value d" }));	// youngest first

		(void)cache->pListForKey("d");	// a lookup promotes
		(void)cache->pListForKey("zz");	// a miss does not change the order
		cache->markClean();
		OO_CHECK(Strings(cache->pListsByAge()) == std::vector<std::string>({ "value d", "value c", "value a", "value b" }));
		OO_CHECK(!cache->dirty());	// reordering does not dirty it

		// The property list: {key, value} entries, oldest first.
		oo::PList::Array expected = { Entry("b", Str("value b")), Entry("a", Str("value a")), Entry("c", Str("value c")), Entry("d", Str("value d")) };
		OO_CHECK(cache->pListRepresentation() == oo::PList(expected));
	}
}


OO_TEST(pruning)
{
	@autoreleasepool
	{
		oo::Ref<OOCache> cache = OOCache::cacheWithPList(oo::PList());
		cache->setPruneThreshold(3);
		OO_CHECK(cache->pruneThreshold() == kOOCacheMinimumPruneThreshold);	// the floor

		// Auto-pruning: past the threshold, down to 80% of it, oldest first.
		for (int i = 0; i < 25; i++)  cache->setPList(Str(std::to_string(i)), std::to_string(100 + i));
		OO_CHECK(cache->pListsByAge().size() == 25);
		cache->setPList(Str("25"), "125");
		OO_CHECK(cache->pListsByAge().size() == 20);
		OO_CHECK(cache->pListForKey("105").isNull() && cache->pListForKey("106") == Str("6"));

		// Manual pruning: nothing until -prune, then down to the threshold itself.
		cache->setAutoPrune(false);
		OO_CHECK(!cache->autoPrune());
		for (int i = 26; i < 40; i++)  cache->setPList(Str(std::to_string(i)), std::to_string(100 + i));
		OO_CHECK(cache->pListsByAge().size() == 34);
		cache->prune();
		OO_CHECK(cache->pListsByAge().size() == 25);

		// Raising the threshold prunes nothing; lowering it with auto-prune on prunes at once.
		cache->setPruneThreshold(30);
		OO_CHECK(cache->pListsByAge().size() == 25);
		cache->setAutoPrune(true);	// turning it on prunes (under the threshold: nothing)
		OO_CHECK(cache->pListsByAge().size() == 25);
		cache->setPruneThreshold(kOOCacheMinimumPruneThreshold);
		OO_CHECK(cache->pListsByAge().size() == 25);	// not over the threshold
		cache->setPList(Str("x"), "x");
		OO_CHECK(cache->pListsByAge().size() == 20);

		cache->setPruneThreshold(kOOCacheNoPrune);
		for (int i = 0; i < 40; i++)  cache->setPList(Str("y"), "y" + std::to_string(i));
		cache->prune();
		OO_CHECK(cache->pListsByAge().size() == 60);
	}
}


OO_TEST(propertyListRoundTrip)
{
	@autoreleasepool
	{
		oo::PList::Array entries;
		for (int i = 0; i < 250; i++)  entries.push_back(Entry("k" + std::to_string(i), oo::PList(std::int64_t(i))));
		entries.push_back(Str("not an entry"));
		entries.push_back(oo::PList(oo::PList::Dict({ { "key", oo::PList(std::int64_t(7)) }, { "value", Str("key not a string") } })));
		entries.push_back(oo::PList(oo::PList::Dict({ { "key", Str("no value") } })));

		oo::Ref<OOCache> loaded = OOCache::cacheWithPList(oo::PList(entries));
		OO_CHECK(loaded != nullptr);
		OO_CHECK(loaded->pListsByAge().size() == 250);	// loading does not prune, even past the threshold
		OO_CHECK(loaded->dirty());
		OO_CHECK(loaded->pruneThreshold() == kOOCacheDefaultPruneThreshold && loaded->autoPrune());
		OO_CHECK(loaded->pListForKey("k0") == oo::PList(std::int64_t(0)));
		OO_CHECK(loaded->pListForKey("no value").isNull());

		oo::Ref<OOCache> again = OOCache::cacheWithPList(loaded->pListRepresentation());
		OO_CHECK(again->pListRepresentation() == loaded->pListRepresentation());

		OO_CHECK(OOCache::cacheWithPList(oo::PList())->pListsByAge().empty());
		OO_CHECK(OOCache::cacheWithPList(Str("not an array")) == nullptr);
		OO_CHECK(OOCache::cacheWithPList(oo::PList(oo::PList::Dict())) == nullptr);
	}
}


OO_TEST(holdsALiveObject)
{
	OOObject *object = [[OOObject alloc] init];
	oo::Ref<OOCache> cache = OOCache::cacheWithPList(oo::PList());
	@autoreleasepool
	{
		cache->setPList(oo::PListObject(object), "texture");
		OO_CHECK(oo::ObjectIn(cache->pListForKey("texture")) == object);
		OO_CHECK([object retainCount] == 2);	// the cache retains it
	}
	cache->removePListForKey("texture");
	OO_CHECK([object retainCount] == 1);
	cache = nullptr;
	[object release];
}


OO_TEST_MAIN()
