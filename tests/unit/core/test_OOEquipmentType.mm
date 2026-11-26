/*	test_OOEquipmentType.mm
	Unit tests for cxx::OOEquipmentType (src/Core/OOEquipmentType.h) and its Objective-C facade:
	bead oo-fg7i (Phase 3, proposed ADR-0056).

	An equipment type is read from an equipment.plist entry, [tech level, price, name, key,
	description, {extra info}]: the implied attributes of missiles, mines, the berth removal and fuel;
	the extra info's flags, times, cargo space, provides, display colour, weapon info and its
	defaults, required and incompatible equipment (sorted, de-duplicated), legacy conditions and
	condition scripts, an equipment script with its fast affinities and default keys; and entries
	missing a name, key or description are refused. The class keeps the registry of types (the main
	and outfitting data sets, by identifier) and the missile registry.

	The game around it is replaced (ADR-0056 amendments oo-zffj, oo-8kx7): UNIVERSE hands out the
	equipment data below, the cache manager, script loader and player answer from fields and record
	what they are asked, and the standards and legacy-condition functions are test replacements.
	OOColor is the game's own. The expectations were written against the Objective-C class and run
	on it first; that API is now the facade (OOEquipmentType+ObjCBridge.h), so they run through it,
	and the last tests pin the C++ API and the facade's contract, including that a registered type's
	facade outlives the autorelease pool, as ships rely on. Run: bash tools/check-core-tests.sh
*/

#import "OOEquipmentType.h"
#import "OOColor.h"

#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>


// --- The game around the class --------------------------------------------------------------

static std::vector<std::string> gLog;
static BOOL gEnforceStandards = NO;

namespace {

oo::PList Dict(std::initializer_list<std::pair<const char *, oo::PList>> entries)
{
	oo::PList::Dict dict;
	for (const auto &[key, value] : entries)  dict[key] = value;
	return oo::PList(std::move(dict));
}


oo::PList Item(int techLevel, int price, const char *name, const char *key, const char *description, oo::PList extra = oo::PList())
{
	oo::PList::Array item{ oo::PList(techLevel), oo::PList(price), oo::PList(name), oo::PList(key), oo::PList(description) };
	if (!extra.isNull())  item.push_back(extra);
	return oo::PList(std::move(item));
}


oo::PList Strings(std::initializer_list<const char *> strings)
{
	oo::PList::Array array;
	for (const char *s : strings)  array.push_back(oo::PList(s));
	return oo::PList(std::move(array));
}


oo::PList EquipmentData()
{
	return oo::PList(oo::PList::Array{
		Item(1, 300, "Fuel", "EQ_FUEL", "Refuel"),
		Item(2, 250, "Missile", "EQ_MISSILE", "A missile", Dict({ { "damage_probability", oo::PList(0.5) } })),
		Item(3, 500, "Berth removal", "EQ_PASSENGER_BERTH_REMOVAL", "Remove a berth"),
		Item(5, 1000, "Mine", "EQ_QC_MINE", "A mine", Dict({ { "fx_weapon_launch_name", oo::PList(7) } })),
		Item(6, 4000, "Pulse laser", "EQ_WEAPON_PULSE_LASER", "Pew", Dict({
			{ "weapon_info", Dict({ { "range", oo::PList(15000) }, { "damage", oo::PList(10) }, { "is_turret_laser", oo::PList(true) }, { "color", oo::PList("redColor") }, { "fx_shot_hit_name", oo::PList("[zap]") } }) },
			{ "display_color", oo::PList("greenColor") } })),
		Item(99, 7000, "Shield booster", "EQ_SHIELD_BOOSTER", "More shield", Dict({
			{ "available_to_all", oo::PList(true) }, { "available_to_NPCs", oo::PList(false) }, { "requires_clean", oo::PList(true) },
			{ "requires_full_fuel", oo::PList(true) }, { "portable_between_ships", oo::PList(true) }, { "visible", oo::PList(false) },
			{ "can_carry_multiple", oo::PList(true) }, { "hide_values", oo::PList(true) }, { "requires_cargo_space", oo::PList(2) },
			{ "installation_time", oo::PList(600) }, { "provides", Strings({ "shields", "boost" }) },
			{ "requires_equipment", Strings({ "EQ_B", "EQ_A", "EQ_B" }) }, { "requires_any_equipment", oo::PList("EQ_ONE") },
			{ "incompatible_with_equipment", oo::PList(42) }, { "conditions", oo::PList("dockedAtMainStation_bool equal YES") },
			{ "condition_script", oo::PList("cond.js") }, { "script_info", Dict({ { "x", oo::PList(1) } }) },
			{ "script", oo::PList("good.js") }, { "fast_affinity_defensive", oo::PList(true) },
			{ "default_activate_key", oo::PList(oo::PList::Array{ Dict({ { "key", oo::PList("a") } }) }) },
			{ "default_mode_key", oo::PList(oo::PList::Array{ Dict({ { "key", oo::PList("taken") } }) }) } })),
		Item(4, 800, "Scooper", "EQ_SCOOPER", "Scoops", Dict({ { "script", oo::PList("missing.js") }, { "repair_time", oo::PList(30) },
			{ "installation_time", oo::PList(100) }, { "conditions", oo::PList(oo::PList::Array{ oo::PList("a"), oo::PList("b") }) },
			{ "condition_script", oo::PList("cond.js") }, { "requires_not_clean", oo::PList(true) }, { "requires_non_full_fuel", oo::PList(true) },
			{ "requires_mounted_pylon", oo::PList(true) }, { "requires_free_passenger_berth", oo::PList(true) }, { "available_to_player", oo::PList(false) } })),
		Item(1, 10, "Broken", "EQ_BROKEN", "Keys wrong", Dict({ { "script", oo::PList("good.js") }, { "default_activate_key", oo::PList("not an array") },
			{ "condition_script", oo::PList(3) }, { "conditions", Dict({}) }, { "requires_equipment", Dict({}) } })),
		oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(2), oo::PList(3), oo::PList("EQ_NO_NAME") }),	// too short
		Item(1, 2, "", "EQ_EMPTY_NAME", "fine"),
		oo::PList(oo::PList::Array{ oo::PList(1), oo::PList(2), oo::PList::Array{}, oo::PList("EQ_ARRAY_NAME"), oo::PList("x") }),	// a name that is not a string
		oo::PList("not an entry"),
	});
}

}	// namespace


@interface Universe: OOObject
- (oo::PList) cxx_equipmentData;
- (oo::PList) cxx_equipmentDataOutfitting;
@end

@implementation Universe
- (oo::PList) cxx_equipmentData				{ return EquipmentData(); }
- (oo::PList) cxx_equipmentDataOutfitting	{ return oo::PList(oo::PList::Array{ EquipmentData().at(0) != nullptr ? *EquipmentData().at(0) : oo::PList(), Item(9, 9, "Outfit", "EQ_OUTFIT", "Only outfitting") }); }
@end

Universe *gSharedUniverse = nil;


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
- (void) cxx_setPList:(const oo::PList &)value forKey:(const std::string &)key inCache:(const std::string &)cache
{
	std::string items;
	for (size_t i = 0; i < value.count(); i++)  items += value.at<std::string>(i) + ",";
	gLog.push_back("cache " + cache + "/" + key + " = " + items);
}
@end


// Only good.js loads.
@interface OOScript: OOObject
+ (id) cxx_jsScriptFromFileNamed:(const std::string &)fileName properties:(const oo::PList &)properties;
@end

@implementation OOScript
+ (id) cxx_jsScriptFromFileNamed:(const std::string &)fileName properties:(const oo::PList &)properties
{
	gLog.push_back("script " + fileName);
	return (fileName == "good.js") ? [[[OOScript alloc] init] autorelease] : nil;
}
@end


// Keys come back as given; "taken" is in use by "compass"; mission_TL_FOR_EQ_SHIELD_BOOSTER is 7.
@interface PlayerEntity: OOObject
- (oo::PList) cxx_processKeyCode:(const oo::PList &)key_def;
- (std::optional<std::string>) validateKey:(const std::string &)key checkKeys:(const oo::PList &)check_keys;
- (oo::PList) cxx_missionVariableForKey:(const std::string &)key;
@end

@implementation PlayerEntity
- (oo::PList) cxx_processKeyCode:(const oo::PList &)key_def	{ return key_def; }
- (std::optional<std::string>) validateKey:(const std::string &)key checkKeys:(const oo::PList &)check_keys
{
	gLog.push_back("validate " + key);
	const oo::PList *first = check_keys.at(0);
	return (first != nullptr && first->get<std::string>("key") == "taken") ? std::optional<std::string>("compass") : std::nullopt;
}
- (oo::PList) cxx_missionVariableForKey:(const std::string &)key
{
	return (key == "mission_TL_FOR_EQ_SHIELD_BOOSTER") ? oo::PList("7") : oo::PList();
}
@end

PlayerEntity *gOOPlayer = nil;


void cxx_OOStandardsDeprecated(const std::string &message)
{
	gLog.push_back("deprecated " + message);
}

extern "C" BOOL OOEnforceStandards(void)
{
	return gEnforceStandards;
}

oo::PList OOSanitizeLegacyScriptConditions(const oo::PList &conditions, const std::optional<std::string> &context)
{
	gLog.push_back("sanitize " + context.value_or("-"));
	return conditions;
}


namespace {

void Reset()
{
	if (gSharedUniverse == nil)  gSharedUniverse = [[Universe alloc] init];
	if (gOOPlayer == nil)  gOOPlayer = [[PlayerEntity alloc] init];
	gLog.clear();
	gEnforceStandards = NO;
}


std::string Keys(const std::optional<std::vector<std::string>> &keys)
{
	if (!keys.has_value())  return "-";
	std::string result = "[";
	for (const std::string &key : *keys)  result += key + " ";
	return result + "]";
}


std::string Colour(OOColor *color)
{
	if (color == nil)  return "nil";
	char buffer[64];
	std::snprintf(buffer, sizeof buffer, "(%g %g %g %g)", [color redComponent], [color greenComponent], [color blueComponent], [color alphaComponent]);
	return buffer;
}


// Everything an equipment type answers, in one line.
std::string Describe(OOEquipmentType *t)
{
	if (t == nil)  return "nil";
	char buffer[1024];
	std::snprintf(buffer, sizeof buffer,
		"%s/%s \"%s\" \"%s\" tl%llu/%llu cr%llu all%d empty%d mounted%d clean%d notclean%d berth%d full%d nonfull%d primary%d store%d portable%d multiple%d dmg%g canDmg%d vis%d hide%d player%d npc%d cargo%u def%d off%d install%zu repair%zu turret%d mining%d range%g energy%g damage%g recharge%g temp%g threat%g",
		[t cxx_identifier].value_or("-").c_str(), [t cxx_damagedIdentifier].value_or("-").c_str(), [t cxx_name].value_or("-").c_str(), [t cxx_descriptiveText].value_or("-").c_str(),
		(unsigned long long)[t techLevel], (unsigned long long)[t effectiveTechLevel], (unsigned long long)[t price], [t isAvailableToAll], [t requiresEmptyPylon], [t requiresMountedPylon],
		[t requiresCleanLegalRecord], [t requiresNonCleanLegalRecord], [t requiresFreePassengerBerth], [t requiresFullFuel], [t requiresNonFullFuel],
		[t isPrimaryWeapon], [t isMissileOrMine], [t isPortableBetweenShips], [t canCarryMultiple], [t damageProbability], [t canBeDamaged],
		[t isVisible], [t hideValues], [t isAvailableToPlayer], [t isAvailableToNPCs], [t requiredCargoSpace], [t fastAffinityDefensive], [t fastAffinityOffensive],
		(size_t)[t installTime], (size_t)[t repairTime], [t isTurretLaser], [t isMiningLaser], [t weaponRange], [t weaponEnergyUse], [t weaponDamage],
		[t weaponRechargeRate], [t weaponShotTemperature], [t weaponThreatAssessment]);
	std::string provides;
	for (const std::string &p : [t cxx_providesForScripting])  provides += p + " ";
	return std::string(buffer) + " requires " + Keys([t cxx_requiresEquipment]) + " any " + Keys([t cxx_requiresAnyEquipment]) + " incompatible " + Keys([t cxx_incompatibleEquipment])
		+ " provides " + provides + "conditions " + std::to_string([t cxx_conditions].count()) + (([t cxx_conditions].isNull()) ? "(null)" : "")
		+ " condition " + [t cxx_conditionScript].value_or("-") + " script " + [t cxx_scriptName].value_or("-") + " info " + std::to_string([t scriptInfo].count())
		+ " activate " + std::to_string([t cxx_defaultActivateKey].count()) + " mode " + std::to_string([t cxx_defaultModeKey].count())
		+ " display " + Colour([t displayColor]) + " weapon " + Colour([t weaponColor]) + " weaponInfo " + std::to_string([t cxx_weaponInfo].count())
		+ " fx " + [t cxx_fxShotMissName].value_or("-") + " " + [t cxx_fxShotHitName].value_or("-") + " " + [t cxx_fxShieldHitName].value_or("-") + " "
		+ [t cxx_fxUnshieldedHitName].value_or("-") + " " + [t cxx_fxWeaponLaunchedName].value_or("-");
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


std::string Identifiers(const std::vector<oo::ObjCRef<OOEquipmentType *>> &types)
{
	std::string result;
	for (const auto &t : types)  result += [t.get() cxx_identifier].value_or("-") + " ";
	return result;
}

}	// namespace


OO_TEST(loading)
{
	Expected expect{
		"deprecated The conditions key is deprecated for equipment Shield booster; sanitize <equipment type \"Shield booster\">; script good.js; validate activate_EQ_SHIELD_BOOSTER; validate mode_EQ_SHIELD_BOOSTER; deprecated The conditions key is deprecated for equipment Scooper; sanitize <equipment type \"Scooper\">; script missing.js; script good.js; cache condition scripts/equipment conditions = cond.js,; ",
		"EQ_FUEL EQ_MISSILE EQ_PASSENGER_BERTH_REMOVAL EQ_QC_MINE EQ_WEAPON_PULSE_LASER EQ_SHIELD_BOOSTER EQ_SCOOPER EQ_BROKEN EQ_EMPTY_NAME ",
		"EQ_FUEL EQ_OUTFIT ",
		"EQ_FUEL/EQ_FUEL_DAMAGED \"Fuel\" \"Refuel\" tl1/1 cr300 all0 empty0 mounted0 clean0 notclean0 berth0 full0 nonfull1 primary0 store0 portable0 multiple0 dmg1 canDmg1 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range0 energy0 damage0 recharge0 temp0 threat0 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"EQ_MISSILE/EQ_MISSILE_DAMAGED \"Missile\" \"A missile\" tl2/2 cr250 all0 empty1 mounted0 clean0 notclean0 berth0 full0 nonfull0 primary0 store1 portable0 multiple1 dmg0 canDmg0 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range12500 energy0.8 damage15 recharge0.5 temp7 threat1 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"EQ_PASSENGER_BERTH_REMOVAL/EQ_PASSENGER_BERTH_REMOVAL_DAMAGED \"Berth removal\" \"Remove a berth\" tl3/3 cr500 all0 empty0 mounted0 clean0 notclean0 berth1 full0 nonfull0 primary0 store0 portable0 multiple0 dmg1 canDmg1 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range0 energy0 damage0 recharge0 temp0 threat0 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"EQ_QC_MINE/EQ_QC_MINE_DAMAGED \"Mine\" \"A mine\" tl5/5 cr1000 all0 empty1 mounted0 clean0 notclean0 berth0 full0 nonfull0 primary0 store1 portable0 multiple1 dmg0 canDmg0 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range12500 energy0.8 damage15 recharge0.5 temp7 threat1 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [mine-launched]",
		"",
		"EQ_WEAPON_PULSE_LASER/EQ_WEAPON_PULSE_LASER_DAMAGED \"Pulse laser\" \"Pew\" tl6/6 cr4000 all0 empty0 mounted0 clean0 notclean0 berth0 full0 nonfull0 primary1 store0 portable0 multiple0 dmg1 canDmg1 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret1 mining0 range15000 energy0.8 damage10 recharge0.5 temp7 threat1 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display (0 1 0 1) weapon (1 0 0 1) weaponInfo 5 fx [player-laser-miss] [zap] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"EQ_SHIELD_BOOSTER/EQ_SHIELD_BOOSTER_DAMAGED \"Shield booster\" \"More shield\" tl99/7 cr7000 all1 empty0 mounted0 clean1 notclean0 berth0 full1 nonfull0 primary0 store0 portable1 multiple1 dmg1 canDmg1 vis0 hide1 player1 npc0 cargo2 def1 off0 install600 repair300 turret0 mining0 range12500 energy0.8 damage15 recharge0.5 temp7 threat1 requires [EQ_A EQ_B ] any [EQ_ONE ] incompatible - provides shields boost conditions 1 condition cond.js script good.js info 1 activate 1 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"deprecated TL99 is deprecated for EQ_SHIELD_BOOSTER; ",
		"EQ_SCOOPER/EQ_SCOOPER_DAMAGED \"Scooper\" \"Scoops\" tl4/4 cr800 all0 empty0 mounted1 clean0 notclean1 berth1 full0 nonfull1 primary0 store0 portable0 multiple0 dmg1 canDmg1 vis1 hide0 player0 npc1 cargo0 def0 off0 install100 repair30 turret0 mining0 range12500 energy0.8 damage15 recharge0.5 temp7 threat1 requires - any - incompatible - provides conditions 2 condition cond.js script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"EQ_BROKEN/EQ_BROKEN_DAMAGED \"Broken\" \"Keys wrong\" tl1/1 cr10 all0 empty0 mounted0 clean0 notclean0 berth0 full0 nonfull0 primary0 store0 portable0 multiple0 dmg1 canDmg1 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range12500 energy0.8 damage15 recharge0.5 temp7 threat1 requires - any - incompatible - provides conditions 0(null) condition - script good.js info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"EQ_EMPTY_NAME/EQ_EMPTY_NAME_DAMAGED \"\" \"fine\" tl1/1 cr2 all0 empty0 mounted0 clean0 notclean0 berth0 full0 nonfull0 primary0 store0 portable0 multiple0 dmg1 canDmg1 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range0 energy0 damage0 recharge0 temp0 threat0 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"",
		"nil",
		"",
		"nil",
		"",
		"EQ_SHIELD_BOOSTER \"Shield booster\"",
	};

	@autoreleasepool
	{
		Reset();
		[OOEquipmentType loadEquipment];
		OO_CHECK(expect(Log()));
		OO_CHECK(expect(Identifiers([OOEquipmentType cxx_allEquipmentTypes])));
		OO_CHECK(expect(Identifiers([OOEquipmentType cxx_allEquipmentTypesOutfitting])));
		for (const char *key : { "EQ_FUEL", "EQ_MISSILE", "EQ_PASSENGER_BERTH_REMOVAL", "EQ_QC_MINE", "EQ_WEAPON_PULSE_LASER", "EQ_SHIELD_BOOSTER", "EQ_SCOOPER", "EQ_BROKEN", "EQ_EMPTY_NAME", "EQ_NO_NAME", "EQ_OUTFIT" })
		{
			gLog.clear();
			OO_CHECK(expect(Describe([OOEquipmentType cxx_equipmentTypeWithIdentifier:key])));
			OO_CHECK(expect(Log()));
		}
		OO_CHECK(expect([[OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_SHIELD_BOOSTER"] cxx_descriptionComponents].value_or("-")));
	}
}


OO_TEST(registries)
{
	Expected expect{
		"EQ_FUEL EQ_MISSILE EQ_PASSENGER_BERTH_REMOVAL EQ_QC_MINE EQ_WEAPON_PULSE_LASER EQ_SHIELD_BOOSTER EQ_SCOOPER EQ_BROKEN EQ_EMPTY_NAME EQ_EXTRA_MISSILE ",
		"EQ_FUEL EQ_OUTFIT EQ_EXTRA_MISSILE ",
		"EQ_EXTRA_MISSILE/EQ_EXTRA_MISSILE_DAMAGED \"Extra\" \"Added\" tl3/3 cr30 all0 empty1 mounted0 clean0 notclean0 berth0 full0 nonfull0 primary0 store1 portable0 multiple1 dmg0 canDmg0 vis1 hide0 player1 npc1 cargo0 def0 off0 install0 repair0 turret0 mining0 range0 energy0 damage0 recharge0 temp0 threat0 requires - any - incompatible - provides conditions 0(null) condition - script - info 0 activate 0 mode 0 display nil weapon nil weaponInfo 0 fx [player-laser-miss] [player-laser-hit] [player-hit-by-weapon] [player-direct-hit] [missile-launched]",
		"(0 0 1 1)",
		"nil",
		"deprecated The conditions key is deprecated for equipment Shield booster; script good.js; validate activate_EQ_SHIELD_BOOSTER; validate mode_EQ_SHIELD_BOOSTER; deprecated The conditions key is deprecated for equipment Scooper; script missing.js; script good.js; cache condition scripts/equipment conditions = cond.js,; ",
	};

	OOEquipmentType *fuel = nil;
	@autoreleasepool
	{
		Reset();
		[OOEquipmentType loadEquipment];
		fuel = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"];	// not retained, as ShipEntity keeps weapon types
	}
	@autoreleasepool
	{
		// The registry keeps its types: the same object, pool after pool, and from every list.
		OO_CHECK(fuel != nil && [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"] == fuel);
		OO_CHECK([OOEquipmentType cxx_allEquipmentTypes].front().get() == fuel);
		OO_CHECK([fuel cxx_identifier] == std::optional<std::string>("EQ_FUEL"));
		OO_CHECK([[fuel copy] autorelease] == fuel);	// immutable: copy is retain
		OO_CHECK([OOEquipmentType cxx_allEquipmentTypesOutfitting].front().get() != fuel);	// its own objects

		// Added types go to both lists and the index.
		[OOEquipmentType cxx_addEquipmentWithInfo:Item(3, 30, "Extra", "EQ_EXTRA_MISSILE", "Added")];
		[OOEquipmentType cxx_addEquipmentWithInfo:oo::PList("not an entry")];
		OO_CHECK(expect(Identifiers([OOEquipmentType cxx_allEquipmentTypes])));
		OO_CHECK(expect(Identifiers([OOEquipmentType cxx_allEquipmentTypesOutfitting])));
		OO_CHECK(expect(Describe([OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_EXTRA_MISSILE"])));

		// The missile registry.
		OO_CHECK(![OOEquipmentType cxx_getMissileRegistryRoleForShip:"viper"].has_value());
		[OOEquipmentType cxx_setMissileRegistryRole:"EQ_MISSILE" forShip:"viper"];
		[OOEquipmentType cxx_setMissileRegistryRole:"EQ_MINE" forShip:""];
		OO_CHECK([OOEquipmentType cxx_getMissileRegistryRoleForShip:"viper"] == std::optional<std::string>("EQ_MISSILE"));
		OO_CHECK(![OOEquipmentType cxx_getMissileRegistryRoleForShip:""].has_value());

		// The display colour can be replaced.
		OOEquipmentType *laser = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_WEAPON_PULSE_LASER"];
		[laser setDisplayColor:[OOColor blueColor]];
		OO_CHECK(expect(Colour([laser displayColor])));
		[laser setDisplayColor:nil];
		OO_CHECK(expect(Colour([laser displayColor])));
	}
	@autoreleasepool
	{
		// Strict standards: legacy conditions are dropped and TL99 stays 99.
		Reset();
		gEnforceStandards = YES;
		[OOEquipmentType loadEquipment];
		OO_CHECK(expect(Log()));
		OOEquipmentType *booster = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_SHIELD_BOOSTER"];
		OO_CHECK([booster cxx_conditions].isNull() && [booster effectiveTechLevel] == 99);
		OO_CHECK([OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_EXTRA_MISSILE"] == nil);	// a reload starts again
		OO_CHECK([[OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"] cxx_identifier] == std::optional<std::string>("EQ_FUEL"));
	}
}


OO_TEST(cxxClass)
{
	@autoreleasepool
	{
		Reset();
		cxx::OOEquipmentType::loadEquipment();
		const std::vector<oo::Ref<cxx::OOEquipmentType>> all = cxx::OOEquipmentType::allEquipmentTypes();
		OO_CHECK(all.size() == 9 && cxx::OOEquipmentType::allEquipmentTypesOutfitting().size() == 2);
		oo::Ref<cxx::OOEquipmentType> laser = cxx::OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_PULSE_LASER");
		OO_CHECK(laser != nullptr && laser == all[4]);
		OO_CHECK(cxx::OOEquipmentType::equipmentTypeWithIdentifier("EQ_NO_NAME") == nullptr);
		OO_CHECK(laser->identifier() == std::optional<std::string>("EQ_WEAPON_PULSE_LASER") && laser->isPrimaryWeapon() && laser->isTurretLaser());
		OO_CHECK(laser->weaponRange() == 15000.0f && laser->weaponDamage() == 10.0f && laser->fxShotHitName() == std::optional<std::string>("[zap]"));
		OO_CHECK(laser->displayColor() != nullptr && laser->displayColor()->greenComponent() == 1.0f);
		OO_CHECK(laser->weaponColor()->redComponent() == 1.0f);
		laser->setDisplayColor(cxx::OOColor::blueColor().get());
		OO_CHECK(laser->displayColor()->blueComponent() == 1.0f);
		OO_CHECK(laser->descriptionComponents() == std::optional<std::string>("EQ_WEAPON_PULSE_LASER \"Pulse laser\""));

		oo::Ref<cxx::OOEquipmentType> booster = cxx::OOEquipmentType::equipmentTypeWithIdentifier("EQ_SHIELD_BOOSTER");
		OO_CHECK(booster->techLevel() == 99 && booster->effectiveTechLevel() == 7);
		OO_CHECK(booster->requiresEquipment() == std::optional<std::vector<std::string>>({ "EQ_A", "EQ_B" }));
		OO_CHECK(booster->provides("boost") && !booster->provides("speed") && booster->repairTime() == 300);

		cxx::OOEquipmentType::addEquipmentWithInfo(Item(3, 30, "Extra", "EQ_EXTRA_MINE", "Added"));
		OO_CHECK(cxx::OOEquipmentType::equipmentTypeWithIdentifier("EQ_EXTRA_MINE")->fxWeaponLaunchedName() == std::optional<std::string>("[mine-launched]"));
		cxx::OOEquipmentType::setMissileRegistryRole("EQ_EXTRA_MINE", "cobra");
		OO_CHECK(cxx::OOEquipmentType::getMissileRegistryRoleForShip("cobra") == std::optional<std::string>("EQ_EXTRA_MINE"));
	}
}


OO_TEST(facadeNilStaysNil)
{
	OOEquipmentType *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOEquipmentType *>(nullptr)) == nil);
	OO_CHECK(![none cxx_identifier].has_value() && [none price] == 0 && [none displayColor] == nil);
}


OO_TEST(facadeIdentity)
{
	OOEquipmentType *fuel = nil;
	OOColor *blue = nil;
	@autoreleasepool
	{
		Reset();
		[OOEquipmentType loadEquipment];
		fuel = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"];
		OO_CHECK(oo::ToObjC(oo::ToCxx(fuel)) == fuel);
		OO_CHECK(oo::ToCxx(fuel) == cxx::OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get());

		// The display colour crosses as the colour's own facade.
		blue = [[OOColor blueColor] retain];
		[fuel setDisplayColor:blue];
		OO_CHECK([fuel displayColor] == blue);
	}
	@autoreleasepool
	{
		// A registered type's facade outlives the pool (ships keep them unretained), and a C++
		// registration made behind the facade's back still crosses to one facade.
		OO_CHECK([OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_FUEL"] == fuel && [fuel displayColor] == blue);
		cxx::OOEquipmentType::addEquipmentWithInfo(Item(3, 30, "Quiet", "EQ_QUIET", "Added in C++"));
		OOEquipmentType *quiet = [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_QUIET"];
		OO_CHECK(quiet != nil && quiet == [OOEquipmentType cxx_equipmentTypeWithIdentifier:"EQ_QUIET"]);
		[blue release];
	}
}


OO_TEST_MAIN()
