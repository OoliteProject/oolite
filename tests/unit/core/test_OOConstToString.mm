/*	test_OOConstToString.mm
	Unit tests for the OOConstToString functions that message converted classes: bead oo-3c81
	(Phase 3, proposed ADR-0056). OOConstToString.mm has no class; its sends to OOEquipmentType
	(oo-fg7i) and OOCommodityMarket (oo-ih7y) become C++ member calls, and its [UNIVERSE ...]
	sends wait for the Universe conversion (oo-pas).

	Pinned: a weapon type's identifier (none for no weapon, "EQ_WEAPON_NONE" for the string form),
	the sloppy lookup that tries an "EQ_" prefix and falls back to EQ_WEAPON_NONE, its strict,
	string and legacy (save-game number) forms, and the mass unit of a commodity in the universe's
	market (tons when there is no market or no such good).

	The game around them is replaced, as in test_OOEquipmentType (ADR-0056 amendments oo-zffj,
	oo-8kx7): UNIVERSE hands out the equipment data, the descriptions and a market; the cache
	manager, script loader, player and standards functions are the test's. OOEquipmentType,
	OOCommodityMarket and OOColor are the game's own. The expectations were written and run on the
	Objective-C sends first. Run: bash tools/check-core-tests.sh test_OOConstToString
*/

#import "OOConstToString.h"
#import "OOEquipmentType.h"
#import "OOCommodityMarket.h"
#import "OOStringExpander.h"

#include "oo_test.hpp"

#include <string>
#include <vector>


// ShipEntity.h's declarations (it imports the whole game).
typedef OOEquipmentType *OOWeaponType;
std::optional<std::string> cxx_OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon);
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(const std::string &string);
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierStrict(const std::string &string);
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(const std::string &string);
std::optional<std::string> cxx_OOStringFromWeaponType(OOWeaponType weapon);
OOWeaponType cxx_OOWeaponTypeFromString(const std::string &string);


// --- The game around the functions -----------------------------------------------------------

namespace {

oo::PList Item(int techLevel, int price, const char *name, const char *key)
{
	return oo::PList(oo::PList::Array{ oo::PList(techLevel), oo::PList(price), oo::PList(name), oo::PList(key), oo::PList("about it") });
}


oo::PList EquipmentData()
{
	return oo::PList(oo::PList::Array{
		Item(1, 0, "No weapon", "EQ_WEAPON_NONE"),
		Item(2, 4000, "Pulse laser", "EQ_WEAPON_PULSE_LASER"),
		Item(5, 10000, "Beam laser", "EQ_WEAPON_BEAM_LASER"),
		Item(3, 300, "Fuel", "EQ_FUEL"),
		Item(4, 500, "Laser without prefix", "LASER_WITHOUT_PREFIX"),
	});
}


oo::PList Good(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}

}	// namespace


@interface Universe: OOObject
{
@public
	OOCommodityMarket	*market;
}
- (oo::PList) cxx_equipmentData;
- (oo::PList) cxx_equipmentDataOutfitting;
- (const oo::PList *) cxx_descriptions;
- (std::optional<std::string>) cxx_descriptionForKey:(const std::string &)key;
- (OOCommodityMarket *) commodityMarket;
@end

@implementation Universe
- (oo::PList) cxx_equipmentData				{ return EquipmentData(); }
- (oo::PList) cxx_equipmentDataOutfitting	{ return EquipmentData(); }
- (const oo::PList *) cxx_descriptions
{
	static const oo::PList descriptions = oo::PList(oo::PList::Dict{});
	return &descriptions;
}
- (std::optional<std::string>) cxx_descriptionForKey:(const std::string &)key	{ return std::nullopt; }
- (OOCommodityMarket *) commodityMarket		{ return market; }
@end

Universe *gSharedUniverse = nil;


// The mass-unit symbols, as descriptions.plist spells them.
std::string cxx_OOLookUpDescriptionPRIV(const std::string &key)
{
	if (key == "cargo-tons-symbol")  return "t";
	if (key == "cargo-kilograms-symbol")  return "kg";
	if (key == "cargo-grams-symbol")  return "g";
	return key;
}


// The expander (a whole-game unit); the functions pinned here never expand.
std::optional<std::string> cxx_OOExpandDescriptionString(Random_Seed seed, const std::string &string, const oo::PList &overrides, const oo::PList &legacyLocals, const std::optional<std::string> &systemName, OOExpandOptions options)
{
	return string;
}

Random_Seed OOStringExpanderDefaultRandomSeed(void)
{
	return Random_Seed();
}


@interface OOCacheManager: OOObject
+ (OOCacheManager *) sharedCache;
- (void) cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache;
@end

@implementation OOCacheManager
+ (OOCacheManager *) sharedCache
{
	static OOCacheManager *cache = [[OOCacheManager alloc] init];
	return cache;
}
- (void) cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache	{}
@end


@interface OOScript: OOObject
+ (id) cxx_jsScriptFromFileNamed:(const std::string &)fileName properties:(const oo::PList &)properties;
@end

@implementation OOScript
+ (id) cxx_jsScriptFromFileNamed:(const std::string &)fileName properties:(const oo::PList &)properties	{ return nil; }
@end


@interface PlayerEntity: OOObject
- (oo::PList) cxx_processKeyCode:(const oo::PList &)key_def;
- (std::optional<std::string>) validateKey:(const std::string &)key checkKeys:(const oo::PList &)check_keys;
- (oo::PList) cxx_missionVariableForKey:(const std::string &)key;
@end

@implementation PlayerEntity
- (oo::PList) cxx_processKeyCode:(const oo::PList &)key_def	{ return key_def; }
- (std::optional<std::string>) validateKey:(const std::string &)key checkKeys:(const oo::PList &)check_keys	{ return std::nullopt; }
- (oo::PList) cxx_missionVariableForKey:(const std::string &)key	{ return oo::PList(); }
@end

PlayerEntity *gOOPlayer = nil;


void cxx_OOStandardsDeprecated(const std::string &message)	{}

extern "C" BOOL OOEnforceStandards(void)	{ return NO; }

oo::PList OOSanitizeLegacyScriptConditions(const oo::PList &conditions, const std::optional<std::string> &context)	{ return conditions; }


namespace {

void LoadEquipment()
{
	if (gSharedUniverse == nil)  gSharedUniverse = [[Universe alloc] init];
	if (gOOPlayer == nil)  gOOPlayer = [[PlayerEntity alloc] init];
	[OOEquipmentType loadEquipment];
}


std::string IdentifierOf(OOWeaponType weapon)
{
	return weapon != nil ? [weapon cxx_identifier].value_or("-") : "nil";
}

}	// namespace


// --- Weapon types ----------------------------------------------------------------------------

OO_TEST(weaponTypeIdentifiers)
{
	@autoreleasepool
	{
		LoadEquipment();
		OOWeaponType pulse = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_WEAPON_PULSE_LASER"];
		OO_CHECK(pulse != nil);

		OO_CHECK(cxx_OOStringFromWeaponType(pulse) == std::optional<std::string>("EQ_WEAPON_PULSE_LASER"));
		OO_CHECK(cxx_OOStringFromWeaponType(nil) == std::optional<std::string>("EQ_WEAPON_NONE"));

		OO_CHECK(cxx_OOEquipmentIdentifierFromWeaponType(pulse) == std::optional<std::string>("EQ_WEAPON_PULSE_LASER"));
		// A message to nil answered a zeroed std::optional: no identifier.
		OO_CHECK(cxx_OOEquipmentIdentifierFromWeaponType(nil) == std::nullopt);
	}
}


OO_TEST(sloppyLookUp)
{
	@autoreleasepool
	{
		LoadEquipment();
		OOWeaponType pulse = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_WEAPON_PULSE_LASER"];
		OOWeaponType none = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_WEAPON_NONE"];
		OO_CHECK(pulse != nil && none != nil && pulse != none);

		// The identifier itself, then with "EQ_" put in front, then EQ_WEAPON_NONE.
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_WEAPON_PULSE_LASER") == pulse);
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("WEAPON_PULSE_LASER") == pulse);
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("LASER_WITHOUT_PREFIX") == [OOEquipmentType cxx_equipmentTypeWithIdentifier:"LASER_WITHOUT_PREFIX"]);
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_FUEL") == [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"]);
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("PULSE_LASER") == none);
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("EQ_NO_SUCH_THING") == none);
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierSloppy("") == none);

		// The other spellings are the same look-up.
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierStrict("WEAPON_BEAM_LASER") == [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_WEAPON_BEAM_LASER"]);
		OO_CHECK(cxx_OOWeaponTypeFromString("WEAPON_PULSE_LASER") == pulse);
		OO_CHECK(cxx_OOWeaponTypeFromString("nonsense") == none);

		// Save games stored weapons as numbers.
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierLegacy("2") == pulse);
		OO_CHECK(IdentifierOf(cxx_OOWeaponTypeFromEquipmentIdentifierLegacy("3")) == "EQ_WEAPON_BEAM_LASER");
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierLegacy("4") == none);	// no mining laser here
		OO_CHECK(cxx_OOWeaponTypeFromEquipmentIdentifierLegacy("EQ_FUEL") == [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"]);
	}
}


// --- Mass units ------------------------------------------------------------------------------

OO_TEST(massUnitOfACommodity)
{
	@autoreleasepool
	{
		LoadEquipment();

		// No market: a message to nil answered 0, UNITS_TONS.
		gSharedUniverse->market = nil;
		OO_CHECK(cxx_DisplayStringForMassUnitForCommodity("gold") == std::optional<std::string>("t"));

		OOCommodityMarket *market = [[[OOCommodityMarket alloc] init] autorelease];
		[market cxx_setGood:"gold" withInfo:Good({ { "name", oo::PList("Gold") }, { "quantity_unit", oo::PList(1) } })];
		[market cxx_setGood:"gems" withInfo:Good({ { "name", oo::PList("Gem-stones") }, { "quantity_unit", oo::PList(2) } })];
		[market cxx_setGood:"food" withInfo:Good({ { "name", oo::PList("Food") }, { "quantity_unit", oo::PList(0) } })];
		[market cxx_setGood:"alloys" withInfo:Good({ { "name", oo::PList("Alloys") }, { "quantity_unit", oo::PList(7) } })];
		gSharedUniverse->market = market;

		OO_CHECK(cxx_DisplayStringForMassUnitForCommodity("gold") == std::optional<std::string>("kg"));
		OO_CHECK(cxx_DisplayStringForMassUnitForCommodity("gems") == std::optional<std::string>("g"));
		OO_CHECK(cxx_DisplayStringForMassUnitForCommodity("food") == std::optional<std::string>("t"));
		OO_CHECK(cxx_DisplayStringForMassUnitForCommodity("unobtainium") == std::optional<std::string>("t"));
		OO_CHECK(cxx_DisplayStringForMassUnitForCommodity("alloys") == cxx_DisplayStringForMassUnit(UNITS_UNKNOWN));

		gSharedUniverse->market = nil;
	}
}


OO_TEST_MAIN()
