/*	test_OOSystemDescriptionManager.mm
	Unit tests for OOSystemDescriptionManager and OOSystemDescriptionEntry
	(src/Core/OOSystemDescriptionManager.h): bead oo-0sr1, a Phase 3 conversion in the house style
	of the OOColor exemplar (proposed ADR-0056).

	The manager is the planetinfo store: per-system property dictionaries in four layers, universal
	and interstellar properties, a per-system cache, the route cache, and the scripted changes a
	saved game keeps. This pins what it computed before the conversion: the layer order (priority,
	dynamic, static, universal, core), the property validation (coordinates, numbers given as
	strings, names), the cache kept up to date by each setter, interstellar keys, scripted changes
	saved, removed, exported and imported (an OXP that is not installed is skipped), the legacy
	nova import and its sun-radius fix, the route cache, the current system, the random seeds and the
	invalid-system answers. The game around it is replaced (ADR-0056 amendments oo-zffj and oo-8kx7):
	UNIVERSE, PLAYER and ResourceManager are fakes that answer the one question each is asked, and
	the two string parsers it calls are given here. The expectations were written against the
	Objective-C API and run on the unconverted class first (commit 465174df9); they ran through the
	facade until bead oo-9ht.32 deleted it, and now ask the C++ class (held as oo::Ref where the
	autoreleased facade was) with every expectation kept. The C++ API and the entry on its own
	follow.
	Run: bash tools/check-core-tests.sh
*/

#import "OOSystemDescriptionManager.h"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>


// --- The game around the class --------------------------------------------------------------

// UNIVERSE: the current system (settable), and PLAYER: the galaxy (settable).
static OOSystemID gCurrentSystem = 7;
static OOGalaxyID gGalaxy = 0;

@interface Universe: OOObject
- (OOSystemID) currentSystemID;
@end

@implementation Universe
- (OOSystemID) currentSystemID  { return gCurrentSystem; }
@end

Universe *gSharedUniverse = nil;


// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for; the members
// the code under test calls, declared as PlayerEntity.h declares them (the test imports no game
// header that defines the class), with the same answers.
class PlayerEntity
{
public:
	OOGalaxyID galaxyNumber();
};

OOGalaxyID PlayerEntity::galaxyNumber()  { return gGalaxy; }

PlayerEntity *gOOPlayer = nullptr;


// ResourceManager: one installed OXP, org.test.installed.
@interface ResourceManager: OOObject
+ (oo::PList) cxx_manifestForIdentifier:(const std::string &)identifier;
@end

@implementation ResourceManager
+ (oo::PList) cxx_manifestForIdentifier:(const std::string &)identifier
{
	if (identifier != "org.test.installed")  return oo::PList();
	return oo::PList(oo::PList::Dict{ { "identifier", oo::PList(identifier) } });
}
@end


/*	OOStringParsing.mm reaches the JavaScript engine, so it is not linked. Its two parsers are
	given here for the inputs the test uses: "x y" is that point (anything else the zero point),
	and "1 2 3 4 5 6" is that seed (anything else, nil included, is all zeroes, as kNilRandomSeed).
*/
NSPoint cxx_PointFromString(const std::string &xyString)
{
	double x = 0, y = 0;
	if (std::sscanf(xyString.c_str(), "%lf %lf", &x, &y) != 2)  return NSMakePoint(0, 0);
	return NSMakePoint(x, y);
}


Random_Seed cxx_RandomSeedFromString(const std::optional<std::string> &abcdefString)
{
	if (abcdefString == "1 2 3 4 5 6")  return Random_Seed{ 1, 2, 3, 4, 5, 6 };
	return Random_Seed{};
}


namespace {

void Fake()
{
	if (gSharedUniverse == nil)  gSharedUniverse = [[Universe alloc] init];
	if (gOOPlayer == nullptr)  gOOPlayer = new PlayerEntity;	// never deleted
	gCurrentSystem = 7;
	gGalaxy = 0;
}


oo::PList Str(const char *string)
{
	return oo::PList(std::string(string));
}


oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict result;
	for (const auto &[key, value] : entries)  result.emplace(key, value);
	return oo::PList(std::move(result));
}


oo::PList Get(const oo::PList &dict, const char *key)
{
	const oo::PList *value = dict.find(key);
	return value != nullptr ? *value : oo::PList();
}


bool SameSeed(Random_Seed a, Random_Seed b)
{
	return a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d && a.e == b.e && a.f == b.f;
}


oo::Ref<OOSystemDescriptionManager> NewManager()
{
	return oo::makeRef<OOSystemDescriptionManager>();
}

}	// namespace


// --- The Objective-C API, as it was before the conversion ------------------------------------

OO_TEST(emptyManager)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		OO_CHECK(manager != nil);
		OO_CHECK(manager->getPropertiesForSystem(7, 0) == oo::PList(oo::PList::Dict()));
		OO_CHECK(manager->getPropertiesForSystem(255, 7) == oo::PList(oo::PList::Dict()));
		OO_CHECK(manager->getPropertiesForSystemKey("0 7") == oo::PList(oo::PList::Dict()));
		OO_CHECK(manager->getProperty("name", "0 7").isNull());
		OO_CHECK(manager->getProperty("name", 7, 0).isNull());
		OO_CHECK(manager->exportScriptedChanges() == oo::PList(oo::PList::Dict()));
		OO_CHECK(manager->getPropertiesForCurrentSystem() == oo::PList(oo::PList::Dict()));
		OO_CHECK(manager->getNeighbourIDsForSystem(7, 0).empty());
		const NSPoint origin = manager->getCoordinatesForSystem(7, 0);
		OO_CHECK(origin.x == 0 && origin.y == 0);
		OO_CHECK(SameSeed(manager->getRandomSeedForSystem(7, 0), kNilRandomSeed));
	}
}


OO_TEST(invalidSystems)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		manager->setUniversalProperties(Dict({ { "economy", oo::PList(3) } }));

		// A negative system, and one past the last galaxy.
		OO_CHECK(manager->getProperty("economy", -1, 0).isNull());
		OO_CHECK(manager->getProperty("economy", 0, 8).isNull());
		OO_CHECK(manager->getPropertiesForSystem(0, 8) == oo::PList(oo::PList::Dict()));
		OO_CHECK(manager->getNeighbourIDsForSystem(-1, 0).empty());
		OO_CHECK(manager->getNeighbourIDsForSystem(0, 8).empty());
		NSPoint p = manager->getCoordinatesForSystem(-1, 0);
		OO_CHECK(p.x == 0 && p.y == 0);
		p = manager->getCoordinatesForSystem(0, 8);
		OO_CHECK(p.x == 0 && p.y == 0);
		OO_CHECK(SameSeed(manager->getRandomSeedForSystem(-1, 0), kNilRandomSeed));
		OO_CHECK(SameSeed(manager->getRandomSeedForSystem(0, 8), kNilRandomSeed));

		// In interstellar space, and in a galaxy past the last: an empty dictionary, a nil seed.
		gCurrentSystem = -1;
		OO_CHECK(manager->getPropertiesForCurrentSystem() == oo::PList(oo::PList::Dict()));
		OO_CHECK(SameSeed(manager->getRandomSeedForCurrentSystem(), kNilRandomSeed));
		gCurrentSystem = 7;
		gGalaxy = 8;
		OO_CHECK(manager->getPropertiesForCurrentSystem() == oo::PList(oo::PList::Dict()));
		OO_CHECK(SameSeed(manager->getRandomSeedForCurrentSystem(), kNilRandomSeed));
		gGalaxy = 0;

		// A system key that is out of range is not cached: it is computed, as an interstellar key
		// would be, and a key with no description of its own has no properties at all.
		OO_CHECK(manager->getPropertiesForSystemKey("9 7") == oo::PList(oo::PList::Dict()));
	}
}


OO_TEST(layersAndUniversal)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		manager->setUniversalProperties(Dict({ { "economy", oo::PList(3) }, { "sky", Str("blue") } }));
		// Universal properties reach only systems that have a description of their own.
		OO_CHECK(manager->getProperty("economy", 7, 0).isNull());
		OO_CHECK(manager->getProperty("economy", 255, 7).isNull());

		// Core layer (0): below the universal properties.
		manager->setProperties(Dict({ { "layer", oo::PList(0) }, { "economy", oo::PList(5) }, { "name", Str("Lave") } }), "0 7");
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(3));
		OO_CHECK(manager->getProperty("name", 7, 0) == Str("Lave"));
		// The layer key itself is not a property.
		OO_CHECK(manager->getProperty("layer", 7, 0).isNull());

		// Static layer (the default, 1): above them.
		manager->setProperties(Dict({ { "economy", oo::PList(6) } }), "0 7");
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(6));
		OO_CHECK(manager->getProperty("economy", "0 7") == oo::PList(6));

		// Priority (3) over dynamic (2) over static.
		manager->setProperty("economy", "0 7", OO_LAYER_OXP_DYNAMIC, oo::PList(7), std::nullopt);
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(7));
		manager->setProperties(Dict({ { "layer", oo::PList(3) }, { "economy", oo::PList(8) } }), "0 7");
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(8));
		// A layer number past the last is the priority layer.
		manager->setProperties(Dict({ { "layer", oo::PList(9) }, { "economy", oo::PList(9) } }), "0 7");
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(9));

		// Removing the top layers' values uncovers the ones below.
		manager->setProperty("economy", "0 7", OO_LAYER_OXP_PRIORITY, oo::PList(), std::nullopt);
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(7));
		manager->setProperty("economy", "0 7", OO_LAYER_OXP_DYNAMIC, oo::PList(), std::nullopt);
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(6));

		// The system's whole dictionary, and the same by key and by the current system.
		const oo::PList expected = Dict({ { "economy", oo::PList(6) }, { "name", Str("Lave") }, { "sky", Str("blue") } });
		OO_CHECK(manager->getPropertiesForSystem(7, 0) == expected);
		OO_CHECK(manager->getPropertiesForSystemKey("0 7") == expected);
		OO_CHECK(manager->getPropertiesForCurrentSystem() == expected);
		// Systems with no description have none, universal ones included.
		OO_CHECK(manager->getPropertiesForSystem(8, 0) == oo::PList(oo::PList::Dict()));
	}
}


OO_TEST(validation)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		manager->setProperties(Dict({ { "coordinates", Str("20 173") }, { "radius", oo::PList(5000) }, { "government", oo::PList(2.5) }, { "name", Str("Lave") }, { "inhabitants", Str("Humans") }, }), "0 7");
		OO_CHECK(manager->getProperty("coordinates", 7, 0) == Str("20 173"));
		// Numbers where a string is read become their text.
		OO_CHECK(manager->getProperty("radius", 7, 0) == Str("5000"));
		OO_CHECK(manager->getProperty("government", 7, 0) == Str("2.5"));

		// Rejected values leave the property as it was.
		manager->setProperties(Dict({ { "coordinates", Str("1 2 3") }, { "name", oo::PList(12) }, { "inhabitants", oo::PList(oo::PList::Array{ Str("x") }) }, { "radius", oo::PList(oo::PList::Array{}) }, }), "0 7");
		OO_CHECK(manager->getProperty("coordinates", 7, 0) == Str("20 173"));
		OO_CHECK(manager->getProperty("name", 7, 0) == Str("Lave"));
		OO_CHECK(manager->getProperty("inhabitants", 7, 0) == Str("Humans"));
		OO_CHECK(manager->getProperty("radius", 7, 0) == Str("5000"));
		manager->setProperties(Dict({ { "coordinates", oo::PList(5) } }), "0 7");
		OO_CHECK(manager->getProperty("coordinates", 7, 0) == Str("20 173"));
		// Other properties are not checked.
		manager->setProperties(Dict({ { "economy", Str("rich") } }), "0 7");
		OO_CHECK(manager->getProperty("economy", 7, 0) == Str("rich"));
	}
}


OO_TEST(interstellar)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		manager->setUniversalProperties(Dict({ { "economy", oo::PList(3) } }));
		manager->setInterstellarProperties(Dict({ { "sky_n_stars", oo::PList(100) }, { "economy", oo::PList(1) } }));
		// A system is not affected by the interstellar properties.
		OO_CHECK(manager->getProperty("sky_n_stars", 7, 0).isNull());

		// An interstellar region with no properties of its own: the interstellar ones, which beat
		// the universal ones (interstellar space's static layer is above them).
		OO_CHECK(manager->getPropertiesForSystemKey("interstellar: 0 7 8") == Dict({ { "economy", oo::PList(1) }, { "sky_n_stars", oo::PList(100) } }));
		OO_CHECK(manager->getProperty("sky_n_stars", "interstellar") == oo::PList(100));

		// A region's own properties win, and are not cached as a system.
		manager->setProperty("sky_n_stars", "interstellar: 0 7 8", OO_LAYER_OXP_STATIC, oo::PList(5), std::nullopt);
		OO_CHECK(manager->getPropertiesForSystemKey("interstellar: 0 7 8") == Dict({ { "economy", oo::PList(1) }, { "sky_n_stars", oo::PList(5) } }));
		OO_CHECK(manager->getProperty("sky_n_stars", "interstellar: 0 7 8") == oo::PList(5));
		OO_CHECK(manager->getPropertiesForSystemKey("interstellar: 0 7 9") == Dict({ { "economy", oo::PList(1) }, { "sky_n_stars", oo::PList(100) } }));
	}
}


OO_TEST(scriptedChanges)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		// Saved under manifest~|~key~|~property~|~layer; not saved without a manifest.
		manager->setProperty("description", "0 7", OO_LAYER_OXP_DYNAMIC, Str("A nice place."), std::string("org.test.installed"));
		manager->setProperty("economy", "0 7", OO_LAYER_OXP_DYNAMIC, oo::PList(4), std::nullopt);
		manager->setProperty("sky_n_stars", "interstellar: 0 7 8", OO_LAYER_OXP_PRIORITY, oo::PList(9), std::string("org.test.gone"));
		// A key that is neither a system nor an interstellar region: set, not saved.
		manager->setProperty("economy", "elsewhere", OO_LAYER_OXP_DYNAMIC, oo::PList(4), std::string("org.test.installed"));
		const oo::PList exported = manager->exportScriptedChanges();
		OO_CHECK(exported == Dict({
			{ "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") },
			{ "org.test.gone~|~interstellar: 0 7 8~|~sky_n_stars~|~3", oo::PList(9) },
		}));
		OO_CHECK(manager->getProperty("description", 7, 0) == Str("A nice place."));
		OO_CHECK(manager->getProperty("economy", "elsewhere") == oo::PList(4));

		// Removing the value removes the saved change.
		manager->setProperty("sky_n_stars", "interstellar: 0 7 8", OO_LAYER_OXP_PRIORITY, oo::PList(), std::string("org.test.gone"));
		OO_CHECK(manager->exportScriptedChanges() == Dict({ { "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") } }));

		// Importing into a new manager: an installed OXP's changes are applied (and kept for the
		// next export); another's are skipped; a key of the wrong shape is skipped; a layer past the
		// last is the priority layer.
		oo::Ref<OOSystemDescriptionManager> loaded = NewManager();
		loaded->importScriptedChanges(Dict({ { "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") }, { "org.test.installed~|~0 8~|~economy~|~9", oo::PList(2) }, { "org.test.gone~|~0 9~|~economy~|~2", oo::PList(1) }, { "not a scripted change", oo::PList(1) }, }));
		OO_CHECK(loaded->getProperty("description", 7, 0) == Str("A nice place."));
		OO_CHECK(loaded->getProperty("economy", 8, 0) == oo::PList(2));
		OO_CHECK(loaded->getProperty("economy", 9, 0).isNull());
		OO_CHECK(loaded->exportScriptedChanges() == Dict({
			{ "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") },
			{ "org.test.installed~|~0 8~|~economy~|~3", oo::PList(2) },
		}));
		// Not a dictionary: nothing.
		loaded->importScriptedChanges(Str("x"));
		OO_CHECK(loaded->exportScriptedChanges().count() == 2);
	}
}


OO_TEST(legacyScriptedChanges)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		manager->importLegacyScriptedChanges(Dict({
			{ "0 7", Dict({ { "sun_gone_nova", oo::PList(true) }, { "sun_radius", oo::PList(1000) }, { "economy", oo::PList(1) } }) },
			{ "0 8", Dict({ { "economy", oo::PList(2) } }) },	// not a nova: not imported
			{ "0 9", Dict({ { "sun_gone_nova", oo::PList(true) }, { "sun_radius", oo::PList(700000) } }) },
		}));
		OO_CHECK(manager->getProperty("economy", 7, 0) == oo::PList(1));
		OO_CHECK(manager->getProperty("sun_gone_nova", 7, 0) == oo::PList(true));
		// A sun radius under 600000 is raised by 600000, as a single-precision real.
		OO_CHECK(manager->getProperty("sun_radius", 7, 0) == oo::PList::singleReal(601000.0f));
		OO_CHECK(manager->getProperty("sun_radius", 9, 0) == oo::PList(700000));
		OO_CHECK(manager->getProperty("economy", 8, 0).isNull());
		// Saved as changes of the core game's manifest, in the dynamic layer.
		const oo::PList exported = manager->exportScriptedChanges();
		OO_CHECK(Get(exported, "org.oolite.oolite~|~0 7~|~sun_radius~|~2") == oo::PList::singleReal(601000.0f));
		OO_CHECK(Get(exported, "org.oolite.oolite~|~0 7~|~economy~|~2") == oo::PList(1));
		OO_CHECK(Get(exported, "org.oolite.oolite~|~0 9~|~sun_radius~|~2") == oo::PList(700000));
		OO_CHECK(exported.count() == 5);
	}
}


OO_TEST(routeCacheAndSeeds)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = NewManager();
		// Distances are 0.4 * the truncated distance with dy halved: 4 (10 apart) and 8 (20 apart).
		manager->setProperties(Dict({ { "coordinates", Str("100 100") }, { "random_seed", Str("1 2 3 4 5 6") } }), "0 0");
		manager->setProperties(Dict({ { "coordinates", Str("110 100") } }), "0 1");
		manager->setProperties(Dict({ { "coordinates", Str("120 100") } }), "0 2");
		manager->setProperties(Dict({ { "coordinates", Str("100 114") } }), "0 3");
		manager->setProperties(Dict({ { "coordinates", Str("100 100") } }), "1 5");
		manager->buildRouteCache();

		const NSPoint p = manager->getCoordinatesForSystem(1, 0);
		OO_CHECK(p.x == 110 && p.y == 100);
		OO_CHECK((manager->getNeighbourIDsForSystem(0, 0) == std::vector<OOSystemID>{ 1, 3 }));
		OO_CHECK((manager->getNeighbourIDsForSystem(1, 0) == std::vector<OOSystemID>{ 0, 2, 3 }));
		OO_CHECK((manager->getNeighbourIDsForSystem(2, 0) == std::vector<OOSystemID>{ 1 }));
		// Systems with no coordinates are all at the zero point, so they are each other's
		// neighbours: every other system of the galaxy.
		OO_CHECK(manager->getNeighbourIDsForSystem(4, 0).size() == 251);
		// Galaxies are separate.
		OO_CHECK(manager->getNeighbourIDsForSystem(5, 1).size() == 0);

		OO_CHECK(SameSeed(manager->getRandomSeedForSystem(0, 0), Random_Seed{ 1, 2, 3, 4, 5, 6 }));
		OO_CHECK(SameSeed(manager->getRandomSeedForSystem(1, 0), kNilRandomSeed));
		gCurrentSystem = 0;
		OO_CHECK(SameSeed(manager->getRandomSeedForCurrentSystem(), Random_Seed{ 1, 2, 3, 4, 5, 6 }));
		gCurrentSystem = 7;
	}
}


// --- The C++ classes, and the facade's contract --------------------------------------------

OO_TEST(cxxApi)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<OOSystemDescriptionManager> manager = oo::makeRef<OOSystemDescriptionManager>();
		manager->setUniversalProperties(Dict({ { "economy", oo::PList(3) } }));
		manager->setProperties(Dict({ { "name", Str("Lave") }, { "coordinates", Str("100 100") } }), "0 7");
		manager->setProperties(Dict({ { "coordinates", Str("105 100") } }), "0 8");
		OO_CHECK(manager->getPropertiesForSystem(7, 0) == Dict({ { "coordinates", Str("100 100") }, { "economy", oo::PList(3) }, { "name", Str("Lave") } }));
		OO_CHECK(manager->getProperty("name", "0 7") == Str("Lave"));
		OO_CHECK(manager->getProperty("name", 7, 0) == Str("Lave"));
		OO_CHECK(manager->getPropertiesForCurrentSystem() == manager->getPropertiesForSystemKey("0 7"));
		manager->setProperty("name", "0 7", OO_LAYER_OXP_PRIORITY, Str("Leesti"), std::string("org.test.installed"));
		OO_CHECK(manager->getProperty("name", 7, 0) == Str("Leesti"));
		OO_CHECK(manager->exportScriptedChanges() == Dict({ { "org.test.installed~|~0 7~|~name~|~3", Str("Leesti") } }));
		manager->buildRouteCache();
		OO_CHECK((manager->getNeighbourIDsForSystem(7, 0) == std::vector<OOSystemID>{ 8 }));
		const NSPoint p = manager->getCoordinatesForSystem(8, 0);
		OO_CHECK(p.x == 105 && p.y == 100);
		OO_CHECK(SameSeed(manager->getRandomSeedForSystem(7, 0), kNilRandomSeed));
		OO_CHECK(SameSeed(manager->getRandomSeedForCurrentSystem(), kNilRandomSeed));
	}
}


OO_TEST(entry)
{
	oo::Ref<OOSystemDescriptionEntry> entry = oo::makeRef<OOSystemDescriptionEntry>();
	OO_CHECK(entry->getProperty("name", OO_LAYER_CORE).isNull());
	entry->setProperty("name", OO_LAYER_CORE, Str("Lave"));
	entry->setProperty("name", OO_LAYER_OXP_STATIC, Str("Diso"));
	OO_CHECK(entry->getProperty("name", OO_LAYER_CORE) == Str("Lave"));
	OO_CHECK(entry->getProperty("name", OO_LAYER_OXP_STATIC) == Str("Diso"));
	OO_CHECK(entry->getProperty("name", OO_LAYER_OXP_DYNAMIC).isNull());
	// Validated as the manager's setters validate; null removes.
	entry->setProperty("radius", OO_LAYER_CORE, oo::PList(4000));
	OO_CHECK(entry->getProperty("radius", OO_LAYER_CORE) == Str("4000"));
	entry->setProperty("name", OO_LAYER_CORE, oo::PList(1));
	OO_CHECK(entry->getProperty("name", OO_LAYER_CORE) == Str("Lave"));
	entry->setProperty("name", OO_LAYER_CORE, oo::PList());
	OO_CHECK(entry->getProperty("name", OO_LAYER_CORE).isNull());
}


OO_TEST_MAIN()
