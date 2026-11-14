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
	Objective-C API and run on the unconverted class first (commit 465174df9); they now run
	through the facade, which is its forwarding test (amendment oo-8kx7 item 6). The C++ API, the
	entry on its own, and the facade's contract (identity both ways, nil and null, a facade made by
	alloc/init) follow.
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


@interface PlayerEntity: OOObject
- (OOGalaxyID) galaxyNumber;
@end

@implementation PlayerEntity
- (OOGalaxyID) galaxyNumber  { return gGalaxy; }
@end

PlayerEntity *gOOPlayer = nil;


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
	if (gOOPlayer == nil)  gOOPlayer = [[PlayerEntity alloc] init];
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


OOSystemDescriptionManager *NewManager()
{
	return [[[OOSystemDescriptionManager alloc] init] autorelease];
}

}	// namespace


// --- The Objective-C API, as it was before the conversion ------------------------------------

OO_TEST(emptyManager)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		OO_CHECK(manager != nil);
		OO_CHECK([manager cxx_getPropertiesForSystem:7 inGalaxy:0] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager cxx_getPropertiesForSystem:255 inGalaxy:7] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager cxx_getPropertiesForSystemKey:"0 7"] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager cxx_getProperty:"name" forSystemKey:"0 7"].isNull());
		OO_CHECK([manager cxx_getProperty:"name" forSystem:7 inGalaxy:0].isNull());
		OO_CHECK([manager cxx_exportScriptedChanges] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager cxx_getPropertiesForCurrentSystem] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager cxx_getNeighbourIDsForSystem:7 inGalaxy:0].empty());
		const NSPoint origin = [manager getCoordinatesForSystem:7 inGalaxy:0];
		OO_CHECK(origin.x == 0 && origin.y == 0);
		OO_CHECK(SameSeed([manager getRandomSeedForSystem:7 inGalaxy:0], kNilRandomSeed));
	}
}


OO_TEST(invalidSystems)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		[manager cxx_setUniversalProperties:Dict({ { "economy", oo::PList(3) } })];

		// A negative system, and one past the last galaxy.
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:-1 inGalaxy:0].isNull());
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:0 inGalaxy:8].isNull());
		OO_CHECK([manager cxx_getPropertiesForSystem:0 inGalaxy:8] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager cxx_getNeighbourIDsForSystem:-1 inGalaxy:0].empty());
		OO_CHECK([manager cxx_getNeighbourIDsForSystem:0 inGalaxy:8].empty());
		NSPoint p = [manager getCoordinatesForSystem:-1 inGalaxy:0];
		OO_CHECK(p.x == 0 && p.y == 0);
		p = [manager getCoordinatesForSystem:0 inGalaxy:8];
		OO_CHECK(p.x == 0 && p.y == 0);
		OO_CHECK(SameSeed([manager getRandomSeedForSystem:-1 inGalaxy:0], kNilRandomSeed));
		OO_CHECK(SameSeed([manager getRandomSeedForSystem:0 inGalaxy:8], kNilRandomSeed));

		// In interstellar space, and in a galaxy past the last: an empty dictionary, a nil seed.
		gCurrentSystem = -1;
		OO_CHECK([manager cxx_getPropertiesForCurrentSystem] == oo::PList(oo::PList::Dict()));
		OO_CHECK(SameSeed([manager getRandomSeedForCurrentSystem], kNilRandomSeed));
		gCurrentSystem = 7;
		gGalaxy = 8;
		OO_CHECK([manager cxx_getPropertiesForCurrentSystem] == oo::PList(oo::PList::Dict()));
		OO_CHECK(SameSeed([manager getRandomSeedForCurrentSystem], kNilRandomSeed));
		gGalaxy = 0;

		// A system key that is out of range is not cached: it is computed, as an interstellar key
		// would be, and a key with no description of its own has no properties at all.
		OO_CHECK([manager cxx_getPropertiesForSystemKey:"9 7"] == oo::PList(oo::PList::Dict()));
	}
}


OO_TEST(layersAndUniversal)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		[manager cxx_setUniversalProperties:Dict({ { "economy", oo::PList(3) }, { "sky", Str("blue") } })];
		// Universal properties reach only systems that have a description of their own.
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0].isNull());
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:255 inGalaxy:7].isNull());

		// Core layer (0): below the universal properties.
		[manager cxx_setProperties:Dict({ { "layer", oo::PList(0) }, { "economy", oo::PList(5) }, { "name", Str("Lave") } }) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(3));
		OO_CHECK([manager cxx_getProperty:"name" forSystem:7 inGalaxy:0] == Str("Lave"));
		// The layer key itself is not a property.
		OO_CHECK([manager cxx_getProperty:"layer" forSystem:7 inGalaxy:0].isNull());

		// Static layer (the default, 1): above them.
		[manager cxx_setProperties:Dict({ { "economy", oo::PList(6) } }) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(6));
		OO_CHECK([manager cxx_getProperty:"economy" forSystemKey:"0 7"] == oo::PList(6));

		// Priority (3) over dynamic (2) over static.
		[manager cxx_setProperty:"economy" forSystemKey:"0 7" andLayer:OO_LAYER_OXP_DYNAMIC toValue:oo::PList(7) fromManifest:std::nullopt];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(7));
		[manager cxx_setProperties:Dict({ { "layer", oo::PList(3) }, { "economy", oo::PList(8) } }) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(8));
		// A layer number past the last is the priority layer.
		[manager cxx_setProperties:Dict({ { "layer", oo::PList(9) }, { "economy", oo::PList(9) } }) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(9));

		// Removing the top layers' values uncovers the ones below.
		[manager cxx_setProperty:"economy" forSystemKey:"0 7" andLayer:OO_LAYER_OXP_PRIORITY toValue:oo::PList() fromManifest:std::nullopt];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(7));
		[manager cxx_setProperty:"economy" forSystemKey:"0 7" andLayer:OO_LAYER_OXP_DYNAMIC toValue:oo::PList() fromManifest:std::nullopt];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(6));

		// The system's whole dictionary, and the same by key and by the current system.
		const oo::PList expected = Dict({ { "economy", oo::PList(6) }, { "name", Str("Lave") }, { "sky", Str("blue") } });
		OO_CHECK([manager cxx_getPropertiesForSystem:7 inGalaxy:0] == expected);
		OO_CHECK([manager cxx_getPropertiesForSystemKey:"0 7"] == expected);
		OO_CHECK([manager cxx_getPropertiesForCurrentSystem] == expected);
		// Systems with no description have none, universal ones included.
		OO_CHECK([manager cxx_getPropertiesForSystem:8 inGalaxy:0] == oo::PList(oo::PList::Dict()));
	}
}


OO_TEST(validation)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		[manager cxx_setProperties:Dict({
			{ "coordinates", Str("20 173") },
			{ "radius", oo::PList(5000) },
			{ "government", oo::PList(2.5) },
			{ "name", Str("Lave") },
			{ "inhabitants", Str("Humans") },
		}) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"coordinates" forSystem:7 inGalaxy:0] == Str("20 173"));
		// Numbers where a string is read become their text.
		OO_CHECK([manager cxx_getProperty:"radius" forSystem:7 inGalaxy:0] == Str("5000"));
		OO_CHECK([manager cxx_getProperty:"government" forSystem:7 inGalaxy:0] == Str("2.5"));

		// Rejected values leave the property as it was.
		[manager cxx_setProperties:Dict({
			{ "coordinates", Str("1 2 3") },
			{ "name", oo::PList(12) },
			{ "inhabitants", oo::PList(oo::PList::Array{ Str("x") }) },
			{ "radius", oo::PList(oo::PList::Array{}) },
		}) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"coordinates" forSystem:7 inGalaxy:0] == Str("20 173"));
		OO_CHECK([manager cxx_getProperty:"name" forSystem:7 inGalaxy:0] == Str("Lave"));
		OO_CHECK([manager cxx_getProperty:"inhabitants" forSystem:7 inGalaxy:0] == Str("Humans"));
		OO_CHECK([manager cxx_getProperty:"radius" forSystem:7 inGalaxy:0] == Str("5000"));
		[manager cxx_setProperties:Dict({ { "coordinates", oo::PList(5) } }) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"coordinates" forSystem:7 inGalaxy:0] == Str("20 173"));
		// Other properties are not checked.
		[manager cxx_setProperties:Dict({ { "economy", Str("rich") } }) forSystemKey:"0 7"];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == Str("rich"));
	}
}


OO_TEST(interstellar)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		[manager cxx_setUniversalProperties:Dict({ { "economy", oo::PList(3) } })];
		[manager cxx_setInterstellarProperties:Dict({ { "sky_n_stars", oo::PList(100) }, { "economy", oo::PList(1) } })];
		// A system is not affected by the interstellar properties.
		OO_CHECK([manager cxx_getProperty:"sky_n_stars" forSystem:7 inGalaxy:0].isNull());

		// An interstellar region with no properties of its own: the interstellar ones, which beat
		// the universal ones (interstellar space's static layer is above them).
		OO_CHECK([manager cxx_getPropertiesForSystemKey:"interstellar: 0 7 8"] == Dict({ { "economy", oo::PList(1) }, { "sky_n_stars", oo::PList(100) } }));
		OO_CHECK([manager cxx_getProperty:"sky_n_stars" forSystemKey:"interstellar"] == oo::PList(100));

		// A region's own properties win, and are not cached as a system.
		[manager cxx_setProperty:"sky_n_stars" forSystemKey:"interstellar: 0 7 8" andLayer:OO_LAYER_OXP_STATIC toValue:oo::PList(5) fromManifest:std::nullopt];
		OO_CHECK([manager cxx_getPropertiesForSystemKey:"interstellar: 0 7 8"] == Dict({ { "economy", oo::PList(1) }, { "sky_n_stars", oo::PList(5) } }));
		OO_CHECK([manager cxx_getProperty:"sky_n_stars" forSystemKey:"interstellar: 0 7 8"] == oo::PList(5));
		OO_CHECK([manager cxx_getPropertiesForSystemKey:"interstellar: 0 7 9"] == Dict({ { "economy", oo::PList(1) }, { "sky_n_stars", oo::PList(100) } }));
	}
}


OO_TEST(scriptedChanges)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		// Saved under manifest~|~key~|~property~|~layer; not saved without a manifest.
		[manager cxx_setProperty:"description" forSystemKey:"0 7" andLayer:OO_LAYER_OXP_DYNAMIC toValue:Str("A nice place.") fromManifest:std::string("org.test.installed")];
		[manager cxx_setProperty:"economy" forSystemKey:"0 7" andLayer:OO_LAYER_OXP_DYNAMIC toValue:oo::PList(4) fromManifest:std::nullopt];
		[manager cxx_setProperty:"sky_n_stars" forSystemKey:"interstellar: 0 7 8" andLayer:OO_LAYER_OXP_PRIORITY toValue:oo::PList(9) fromManifest:std::string("org.test.gone")];
		// A key that is neither a system nor an interstellar region: set, not saved.
		[manager cxx_setProperty:"economy" forSystemKey:"elsewhere" andLayer:OO_LAYER_OXP_DYNAMIC toValue:oo::PList(4) fromManifest:std::string("org.test.installed")];
		const oo::PList exported = [manager cxx_exportScriptedChanges];
		OO_CHECK(exported == Dict({
			{ "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") },
			{ "org.test.gone~|~interstellar: 0 7 8~|~sky_n_stars~|~3", oo::PList(9) },
		}));
		OO_CHECK([manager cxx_getProperty:"description" forSystem:7 inGalaxy:0] == Str("A nice place."));
		OO_CHECK([manager cxx_getProperty:"economy" forSystemKey:"elsewhere"] == oo::PList(4));

		// Removing the value removes the saved change.
		[manager cxx_setProperty:"sky_n_stars" forSystemKey:"interstellar: 0 7 8" andLayer:OO_LAYER_OXP_PRIORITY toValue:oo::PList() fromManifest:std::string("org.test.gone")];
		OO_CHECK([manager cxx_exportScriptedChanges] == Dict({ { "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") } }));

		// Importing into a new manager: an installed OXP's changes are applied (and kept for the
		// next export); another's are skipped; a key of the wrong shape is skipped; a layer past the
		// last is the priority layer.
		OOSystemDescriptionManager *loaded = NewManager();
		[loaded cxx_importScriptedChanges:Dict({
			{ "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") },
			{ "org.test.installed~|~0 8~|~economy~|~9", oo::PList(2) },
			{ "org.test.gone~|~0 9~|~economy~|~2", oo::PList(1) },
			{ "not a scripted change", oo::PList(1) },
		})];
		OO_CHECK([loaded cxx_getProperty:"description" forSystem:7 inGalaxy:0] == Str("A nice place."));
		OO_CHECK([loaded cxx_getProperty:"economy" forSystem:8 inGalaxy:0] == oo::PList(2));
		OO_CHECK([loaded cxx_getProperty:"economy" forSystem:9 inGalaxy:0].isNull());
		OO_CHECK([loaded cxx_exportScriptedChanges] == Dict({
			{ "org.test.installed~|~0 7~|~description~|~2", Str("A nice place.") },
			{ "org.test.installed~|~0 8~|~economy~|~3", oo::PList(2) },
		}));
		// Not a dictionary: nothing.
		[loaded cxx_importScriptedChanges:Str("x")];
		OO_CHECK([loaded cxx_exportScriptedChanges].count() == 2);
	}
}


OO_TEST(legacyScriptedChanges)
{
	Fake();
	@autoreleasepool
	{
		OOSystemDescriptionManager *manager = NewManager();
		[manager cxx_importLegacyScriptedChanges:Dict({
			{ "0 7", Dict({ { "sun_gone_nova", oo::PList(true) }, { "sun_radius", oo::PList(1000) }, { "economy", oo::PList(1) } }) },
			{ "0 8", Dict({ { "economy", oo::PList(2) } }) },	// not a nova: not imported
			{ "0 9", Dict({ { "sun_gone_nova", oo::PList(true) }, { "sun_radius", oo::PList(700000) } }) },
		})];
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:7 inGalaxy:0] == oo::PList(1));
		OO_CHECK([manager cxx_getProperty:"sun_gone_nova" forSystem:7 inGalaxy:0] == oo::PList(true));
		// A sun radius under 600000 is raised by 600000, as a single-precision real.
		OO_CHECK([manager cxx_getProperty:"sun_radius" forSystem:7 inGalaxy:0] == oo::PList::singleReal(601000.0f));
		OO_CHECK([manager cxx_getProperty:"sun_radius" forSystem:9 inGalaxy:0] == oo::PList(700000));
		OO_CHECK([manager cxx_getProperty:"economy" forSystem:8 inGalaxy:0].isNull());
		// Saved as changes of the core game's manifest, in the dynamic layer.
		const oo::PList exported = [manager cxx_exportScriptedChanges];
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
		OOSystemDescriptionManager *manager = NewManager();
		// Distances are 0.4 * the truncated distance with dy halved: 4 (10 apart) and 8 (20 apart).
		[manager cxx_setProperties:Dict({ { "coordinates", Str("100 100") }, { "random_seed", Str("1 2 3 4 5 6") } }) forSystemKey:"0 0"];
		[manager cxx_setProperties:Dict({ { "coordinates", Str("110 100") } }) forSystemKey:"0 1"];
		[manager cxx_setProperties:Dict({ { "coordinates", Str("120 100") } }) forSystemKey:"0 2"];
		[manager cxx_setProperties:Dict({ { "coordinates", Str("100 114") } }) forSystemKey:"0 3"];
		[manager cxx_setProperties:Dict({ { "coordinates", Str("100 100") } }) forSystemKey:"1 5"];
		[manager buildRouteCache];

		const NSPoint p = [manager getCoordinatesForSystem:1 inGalaxy:0];
		OO_CHECK(p.x == 110 && p.y == 100);
		OO_CHECK(([manager cxx_getNeighbourIDsForSystem:0 inGalaxy:0] == std::vector<OOSystemID>{ 1, 3 }));
		OO_CHECK(([manager cxx_getNeighbourIDsForSystem:1 inGalaxy:0] == std::vector<OOSystemID>{ 0, 2, 3 }));
		OO_CHECK(([manager cxx_getNeighbourIDsForSystem:2 inGalaxy:0] == std::vector<OOSystemID>{ 1 }));
		// Systems with no coordinates are all at the zero point, so they are each other's
		// neighbours: every other system of the galaxy.
		OO_CHECK([manager cxx_getNeighbourIDsForSystem:4 inGalaxy:0].size() == 251);
		// Galaxies are separate.
		OO_CHECK([manager cxx_getNeighbourIDsForSystem:5 inGalaxy:1].size() == 0);

		OO_CHECK(SameSeed([manager getRandomSeedForSystem:0 inGalaxy:0], Random_Seed{ 1, 2, 3, 4, 5, 6 }));
		OO_CHECK(SameSeed([manager getRandomSeedForSystem:1 inGalaxy:0], kNilRandomSeed));
		gCurrentSystem = 0;
		OO_CHECK(SameSeed([manager getRandomSeedForCurrentSystem], Random_Seed{ 1, 2, 3, 4, 5, 6 }));
		gCurrentSystem = 7;
	}
}


// --- The C++ classes, and the facade's contract --------------------------------------------

OO_TEST(cxxApi)
{
	Fake();
	@autoreleasepool
	{
		oo::Ref<cxx::OOSystemDescriptionManager> manager = oo::makeRef<cxx::OOSystemDescriptionManager>();
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


OO_TEST(facadeContract)
{
	Fake();
	@autoreleasepool
	{
		// A facade made by alloc/init is the C++ manager's peer.
		OOSystemDescriptionManager *facade = NewManager();
		cxx::OOSystemDescriptionManager *manager = oo::ToCxx(facade);
		OO_CHECK(manager != nullptr);
		OO_CHECK(oo::ToObjC(manager) == facade);
		OO_CHECK(oo::ToObjC(nullptr) == nil);
		OO_CHECK(oo::ToCxx(nil) == nullptr);

		// One store: what either side writes, the other reads.
		manager->setProperties(Dict({ { "name", Str("Lave") } }), "0 7");
		OO_CHECK([facade cxx_getProperty:"name" forSystem:7 inGalaxy:0] == Str("Lave"));
		[facade cxx_setProperties:Dict({ { "name", Str("Zaonce") } }) forSystemKey:"0 8"];
		OO_CHECK(manager->getProperty("name", 8, 0) == Str("Zaonce"));

		// A C++ manager crossing for the first time gets one facade, the same each time.
		oo::Ref<cxx::OOSystemDescriptionManager> other = oo::makeRef<cxx::OOSystemDescriptionManager>();
		OOSystemDescriptionManager *otherFacade = oo::ToObjC(other.get());
		OO_CHECK(otherFacade != nil);
		OO_CHECK(otherFacade != facade);
		OO_CHECK(oo::ToObjC(other.get()) == otherFacade);
		OO_CHECK(oo::ToCxx(otherFacade) == other.get());
	}
}


OO_TEST_MAIN()
