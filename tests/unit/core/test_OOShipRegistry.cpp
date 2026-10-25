/*	test_OOShipRegistry.mm
	Unit tests for OOShipRegistry (src/Core/OOShipRegistry.h): bead oo-3bgz, slice 1 of the Phase 3
	slice plan docs/phases/3-slices/OOShipRegistry.md (the class shell, lifecycle, the lookups,
	OOConveniences and the singleton), in the house style of the OOColor exemplar (proposed
	ADR-0056).

	It pins what the registry answered before the conversion, through the Objective-C API its
	callers use, over a small ship data set that a stand-in ResourceManager serves: the shared
	instance, every lookup (ship, effect and shipyard entries, player ships, roles and their
	probability sets, keys with a role, a random key for a role, demo ships), replacing an entry,
	and +reload, which makes a new registry from the cache the first one filled. The data pipeline
	itself (OODataLoader, slices 2 and 3) runs as it is; this test only fixes its input. The
	expectations were written against the unconverted class and run on it first. After the
	conversion the class sat in namespace cxx behind an Objective-C facade, which bead oo-9ht.122
	deleted with its facade-contract case (standing approval oo-9n5p9); the cases ask the C++ class.
	Run: bash tools/check-core-tests.sh test_OOShipRegistry
*/

#include "OOShipRegistry.h"
#include "OOCacheManager.h"
#include "OOProbabilitySet.h"
#include "OODescription.h"

#include "oofnd/PListParsing.hpp"
#include "OOMaths.h"
#include "OOJSEngineCore.h"
#include "OOJSPropID.h"
#include "OODebugStandards.h"
#include "OOStringParsing.h"
#include "OOLegacyScriptWhitelist.h"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>


// Link stubs (ADR-0056 amendment oo-zffj item 2): what OOShipRegistry.mm and OOCacheManager.mm
// reference whose objects would link the game. The paths the test runs never reach the aborting
// ones: no ship has a condition script, a subentity, a vector or quaternion string, and nothing
// flushes the cache.
class Universe;
class PlayerEntity;
PlayerEntity *gOOPlayer = nullptr;
#include "OOEntityEnums.h"
class Entity { public: OOEntityStatus status(); };
OOEntityStatus Entity::status()  { std::abort(); }
Universe *gSharedUniverse = nil;

// UNIVERSE stays nil here, so the registry's guarded call never reaches it; the stand-in only links
// it (bead oo-ql9rn: it was a message to nil).
class OOScript;
class Universe
{
public:
	::OOScript *getConditionScript(const std::string &scriptname);
};
::OOScript *Universe::getConditionScript(const std::string &)  { return nullptr; }
ooscript::Context gOOJSMainThreadContext = nullptr;
void OOJSInitJSIDCachePRIVATE(const char *, ooscript::PropertyId *)  { std::abort(); }
ooscript::Value OOJSValueFromPList(ooscript::Context, const oo::PList &)  { std::abort(); }
oo::PList OOSanitizeLegacyScriptConditions(const oo::PList &, const std::optional<std::string> &)  { std::abort(); }
BOOL cxx_ScanVectorFromString(const std::optional<std::string> &, Vector *)  { std::abort(); }
BOOL cxx_ScanHPVectorFromString(const std::optional<std::string> &, HPVector *)  { std::abort(); }
BOOL cxx_ScanQuaternionFromString(const std::optional<std::string> &, Quaternion *)  { std::abort(); }
void cxx_OOStandardsDeprecated(const std::string &)  { std::abort(); }
void cxx_OOStandardsError(const std::string &)  { std::abort(); }

// Fakes the registry does call: standards are not enforced (the default), and the ship library's
// category names are a fixed table (the real one expands descriptions.plist through Universe).
bool OOEnforceStandards(void)  { return false; }
std::string OOShipLibraryCategoryPlural(const std::string &category)
{
	if (category == "ship")  return "Ships";
	if (category == "station")  return "Stations";
	return "";
}

// OOCacheManager.mm calls the asynchronous work manager for its flush, which the test never does
// (a C++ stand-in since bead oo-9ht.14 made the manager C++; it was an empty Objective-C class).
OOAsyncWorkManager *OOAsyncWorkManager::sharedAsyncWorkManager()  { std::abort(); }


// The stand-in ResourceManager: the files the registry reads, by name; everything else absent.
#include "ResourceManager.h"


namespace {

std::vector<std::string> sFilesRead;
bool sSubentityData = false;	// canonicalizesSubentityDeclarations: serve the subentity data set

oo::PList Parse(const char *text)
{
	auto result = oo::parsePropertyList(text);
	if (!result)  std::fprintf(stderr, "  could not parse test plist: %s\n", text);
	return result ? *result : oo::PList();
}


oo::PList FileNamed(const std::string &name)
{
	sFilesRead.push_back(name);
	// New-style subentity declarations only (an old-style string one is deprecated, which the
	// standards stub aborts on): a ball turret with out-of-range weapon values, a dock, flashers
	// (one colour, a colours list, one of size 0), a reference to no ship on an external dependency,
	// and a bad type on a frangible ship.
	if (name == "shipdata.plist" && sSubentityData)  return Parse(
		"{"
		"  \"cobra3-player\" = { name = Cobra; roles = player; model = \"adder.dat\"; };"
		"  mothership = { name = Mothership; roles = trader; model = \"adder.dat\"; subentities = ("
		"    { type = \"ball_turret\"; \"subentity_key\" = turret; position = (1, 2, 3); \"fire_rate\" = 0.1; \"weapon_range\" = 99999; \"weapon_energy\" = 200; },"
		"    { \"subentity_key\" = dock; \"is_dock\" = yes; position = (0, 0, 5); orientation = (2, 0, 0, 0); \"allow_launching\" = no; },"
		"    { type = flasher; position = (0, 0, 5); color = redColor; size = 4; phase = 1; },"
		"    { type = flasher; colors = (blueColor, greenColor); \"bright_fraction\" = 0.25; \"initially_on\" = no; },"
		"    { type = flasher; size = 0; }"
		"  ); };"
		"  turret = { name = Turret; model = \"adder.dat\"; };"
		"  dock = { name = Dock; model = \"adder.dat\"; };"
		"  orphan = { name = Orphan; roles = trader; model = \"adder.dat\"; \"is_external_dependency\" = yes; subentities = ( { \"subentity_key\" = nosuch; } ); };"
		"  wreck = { name = Wreck; roles = trader; model = \"adder.dat\"; frangible = yes; subentities = ( { type = weird; \"subentity_key\" = turret; }, { \"subentity_key\" = turret; } ); };"
		"}");
	if (name == "shipdata.plist")  return Parse(
		"{"
		"  adder = { name = Adder; roles = \"trader hunter(0.5)\"; model = \"adder.dat\"; max_flight_speed = 240; };"
		"  \"cobra3-player\" = { like_ship = adder; name = \"Cobra Mark III\"; roles = \"player trader(2)\"; };"
		"  \"coriolis-station\" = { name = \"Coriolis Station\"; roles = \"coriolis station\"; model = \"coriolis.dat\"; isCarrier = yes; };"
		"  \"template-ship\" = { is_template = yes; name = Template; model = \"adder.dat\"; roles = template; };"
		"}");
	if (name == "shipyard.plist")  return Parse(
		"{ \"cobra3-player\" = { price = 150000; techlevel = 1; chance = 1; optional_equipment = (); standard_equipment = { extras = (); forward_weapon_type = EQ_WEAPON_PULSE_LASER; }; weapon_facings = 15; }; }");
	if (name == "effectdata.plist")  return Parse(
		"{ puff = { model = \"puff.dat\"; scale = 2; }; }");
	if (name == "shiplibrary.plist")  return Parse(
		"( { ship = adder; }, { ship = \"coriolis-station\"; class = station; }, { ship = missing; } )");
	return oo::PList();
}

}	// namespace


// ResourceManager is C++ since bead oo-9ht.150 deleted its Objective-C facade: C++ definitions of the
// statics the code under test calls, with the Objective-C stand-in's answers.
oo::PList ResourceManager::dictionaryFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, OOResourceMergeMode mergeMode, bool useCache)
{
	(void)folderName; (void)mergeMode; (void)useCache;
	return FileNamed(fileName);
}


oo::PList ResourceManager::arrayFromFilesNamed(const std::string &fileName, const std::optional<std::string> &folderName, bool mergeFiles, bool useCache)
{
	(void)folderName; (void)mergeFiles; (void)useCache;
	return FileNamed(fileName);
}


std::optional<std::string> ResourceManager::pathForFileNamed(const std::string &fileName, const std::optional<std::string> &folderName)
{
	return folderName.value_or("") + "/" + fileName;
}



namespace {

std::string Join(const std::vector<std::string> &strings)
{
	std::string result;
	for (const std::string &string : strings)  result += (result.empty() ? "" : " ") + string;
	return result;
}


std::string Text(const oo::PList &plist)
{
	return plist.isNull() ? "(null)" : oo::DescriptionOf(plist);
}


bool Pinned(const char *what, const std::string &actual, const std::string &expected)
{
	if (OO_CHECK_EQ(actual, expected))  return true;
	std::fprintf(stderr, "  %s got: %s\n", what, actual.c_str());
	return false;
}

}	// namespace


OO_TEST(sharedRegistryLoadsOnce)
{
	OOShipRegistry *registry = OOShipRegistry::sharedRegistry();
	OO_CHECK(registry != nullptr);
	OO_CHECK(OOShipRegistry::sharedRegistry() == registry);
	Pinned("files", Join(sFilesRead), "shipdata.plist shipdata-overrides.plist shipyard.plist shipyard-overrides.plist effectdata.plist shiplibrary.plist shiplibrary.plist");
}


OO_TEST(looksUpShipsEffectsAndShipyards)
{
	OOShipRegistry *registry = OOShipRegistry::sharedRegistry();
	Pinned("ship keys", Join(registry->shipKeys()), "adder cobra3-player coriolis-station");
	Pinned("adder", Text(registry->shipInfoForKey("adder")), "{\"max_flight_speed\" = 240; model = \"adder.dat\"; name = Adder; roles = \"trader hunter(0.5)\"; }");
	Pinned("cobra", Text(registry->shipInfoForKey("cobra3-player")), "{\"_oo_shipyard\" = {chance = 1; \"optional_equipment\" = (); price = 150000; \"standard_equipment\" = {extras = (); \"forward_weapon_type\" = \"EQ_WEAPON_PULSE_LASER\"; }; techlevel = 1; \"weapon_facings\" = 15; }; \"max_flight_speed\" = 240; model = \"adder.dat\"; name = \"Cobra Mark III\"; roles = \"player trader(2)\"; }");
	Pinned("unknown", Text(registry->shipInfoForKey("viper")), "(null)");
	Pinned("effect", Text(registry->effectInfoForKey("puff")), "{model = \"puff.dat\"; scale = 2; }");
	Pinned("no effect", Text(registry->effectInfoForKey("adder")), "(null)");
	Pinned("shipyard", Text(registry->shipyardInfoForKey("cobra3-player")), "{chance = 1; \"optional_equipment\" = (); price = 150000; \"standard_equipment\" = {extras = (); \"forward_weapon_type\" = \"EQ_WEAPON_PULSE_LASER\"; }; techlevel = 1; \"weapon_facings\" = 15; }");
	Pinned("no shipyard", Text(registry->shipyardInfoForKey("adder")), "(null)");
	Pinned("player ships", Join(registry->playerShipKeys()), "cobra3-player");
	Pinned("demo ships", Text(registry->demoShipKeys()), "(({class = ship; name = Adder; ship = adder; }), ({class = station; name = \"Coriolis Station\"; ship = \"coriolis-station\"; }))");
}


OO_TEST(answersRoles)
{
	OOShipRegistry *registry = OOShipRegistry::sharedRegistry();
	Pinned("roles", Join(registry->shipRoles()), "[adder] [cobra3-player] [coriolis-station] coriolis hunter player station trader");
	Pinned("traders", Join(registry->shipKeysWithRole("trader")), "adder cobra3-player");
	Pinned("hunters", Join(registry->shipKeysWithRole("hunter")), "adder");
	Pinned("none", Join(registry->shipKeysWithRole("pirate")), "");
	OO_CHECK(registry->probabilitySetForRole("pirate") == nullptr);
	OOProbabilitySet *traders = registry->probabilitySetForRole("trader");
	OO_CHECK(traders != nullptr);
	if (traders != nullptr)
	{
		OO_CHECK_EQ(traders->count(), 2u);
		Pinned("trader weights", std::to_string(traders->weightForObject(oo::PList("adder"))) + " " + std::to_string(traders->weightForObject(oo::PList("cobra3-player"))), "1.000000 2.000000");
	}
	Pinned("random hunter", registry->randomShipKeyForRole("hunter").value_or("(nullopt)"), "adder");
	Pinned("random pirate", registry->randomShipKeyForRole("pirate").value_or("(nullopt)"), "(nullopt)");
}


OO_TEST(replacesAnEntry)
{
	OOShipRegistry *registry = OOShipRegistry::sharedRegistry();
	registry->setShipInfoForKey("viper", Parse("{ name = Viper; }"));
	Pinned("viper", Text(registry->shipInfoForKey("viper")), "{name = Viper; }");
	Pinned("ship keys", Join(registry->shipKeys()), "adder cobra3-player coriolis-station viper");
}


OO_TEST(reloadMakesANewRegistryFromTheCache)
{
	OOShipRegistry *before = OOShipRegistry::sharedRegistry();
	sFilesRead.clear();
	OOShipRegistry::reload();
	OOShipRegistry *after = OOShipRegistry::sharedRegistry();
	OO_CHECK(after != nullptr);
	OO_CHECK(after != before);
	Pinned("files", Join(sFilesRead), "shiplibrary.plist shiplibrary.plist");
	Pinned("ship keys", Join(after->shipKeys()), "adder cobra3-player coriolis-station");
	Pinned("player ships", Join(after->playerShipKeys()), "cobra3-player");
	Pinned("roles", Join(after->shipRoles()), "[adder] [cobra3-player] [coriolis-station] coriolis hunter player station trader");
	// The old registry was never released (its -release did nothing): it still answers.
	Pinned("old ship keys", Join(before->shipKeys()), "adder cobra3-player coriolis-station viper");
}


// Subentity declarations (slice 3 of the plan, the loader's canonicalisation and validation): a
// fresh load of the subentity data set, the registry's cache cleared first so that +reload reads
// the files again. Pinned on the unconverted loader (bead oo-r9gn) before slice 3 (bead oo-ugw3).
OO_TEST(canonicalizesSubentityDeclarations)
{
	sSubentityData = true;
	OOCacheManager::sharedCache()->clearCache("ship registry");
	OOShipRegistry::reload();
	OOShipRegistry *registry = OOShipRegistry::sharedRegistry();
	Pinned("ship keys", Join(registry->shipKeys()), "cobra3-player dock mothership turret wreck");
	Pinned("mothership", Text(registry->shipInfoForKey("mothership")), "{model = \"adder.dat\"; name = Mothership; roles = trader; subentities = ({\"fire_rate\" = \"0.25\"; orientation = {w = 1; x = 0; y = 0; z = 0; }; position = {x = 1; y = 2; z = 3; }; \"subentity_key\" = turret; type = \"ball_turret\"; \"weapon_energy\" = 100; \"weapon_range\" = \"7200.00048828125\"; }, {\"allow_docking\" = 1; \"allow_launching\" = 0; \"disallowed_docking_collides\" = 0; \"dock_label\" = \"the docking bay\"; \"is_dock\" = 1; orientation = {w = 1; x = 0; y = 0; z = 0; }; position = {x = 0; y = 0; z = 5; }; \"subentity_key\" = dock; type = standard; }, {\"bright_fraction\" = \"0.5\"; colors = ((1, 0, 0, 1)); frequency = 2; \"initially_on\" = 1; phase = 1; position = {x = 0; y = 0; z = 5; }; size = 4; type = flasher; }, {\"bright_fraction\" = \"0.25\"; colors = ((0, 0, 1, 1), (0, 1, 0, 1)); frequency = 2; \"initially_on\" = 0; position = {x = 0; y = 0; z = 0; }; size = 8; type = flasher; }); }");
	Pinned("turret", Text(registry->shipInfoForKey("turret")), "{\"_oo_is_subentity\" = 1; model = \"adder.dat\"; name = Turret; }");
	Pinned("wreck", Text(registry->shipInfoForKey("wreck")), "{frangible = yes; model = \"adder.dat\"; name = Wreck; roles = trader; subentities = ({orientation = {w = 1; x = 0; y = 0; z = 0; }; position = {x = 0; y = 0; z = 0; }; \"subentity_key\" = turret; type = standard; }); }");
	Pinned("orphan", Text(registry->shipInfoForKey("orphan")), "(null)");
	Pinned("roles", Join(registry->shipRoles()), "[cobra3-player] [dock] [mothership] [turret] [wreck] player trader");
	sSubentityData = false;
}


OO_TEST_MAIN()
