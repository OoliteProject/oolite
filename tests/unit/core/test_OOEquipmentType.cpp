/*	test_OOEquipmentType.mm
	Unit tests for OOEquipmentType (src/Core/OOEquipmentType.h) and its Objective-C facade:
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
	on it first; since its facade was deleted (bead oo-9ht.28) they ask the C++ class, and the last
	tests pin the C++ API and that a registered type outlives the autorelease pool, as ships rely
	on (the facade-contract cases went with the facade, standing approval oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#include "OOEquipmentType.h"
#include "OOColor.h"

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


// The universe as the code under test sees it: a stand-in for the C++ class (bead oo-ql9rn deleted
// the Objective-C facade this stood in for), with the header's names and signatures.
class Universe
{
public:
	oo::PList getEquipmentData();
	oo::PList getEquipmentDataOutfitting();
};

oo::PList Universe::getEquipmentData()	{ return EquipmentData(); }
oo::PList Universe::getEquipmentDataOutfitting()	{ return oo::PList(oo::PList::Array{ EquipmentData().at(0) != nullptr ? *EquipmentData().at(0) : oo::PList(), Item(9, 9, "Outfit", "EQ_OUTFIT", "Only outfitting") }); }


Universe *gSharedUniverse = nil;


#include "OOCacheManager.h"

// The cache manager is C++ since bead oo-9ht.31 deleted its facade: a C++ stand-in with the Objective-C
// stand-in's answers.
OOCacheManager *OOCacheManager::sharedCache()
{
	static OOCacheManager *shared = new OOCacheManager;
	return shared;
}
OOCacheManager::~OOCacheManager()  {}
void OOCacheManager::setPList(const oo::PList &value, const std::string &key, const std::string &cache)
{
	std::string items;
	for (size_t i = 0; i < value.count(); i++)  items += value.at<std::string>(i) + ",";
	gLog.push_back("cache " + cache + "/" + key + " = " + items);
}


#include "OOScript.h"


// OOScript's members that OOEquipmentType.mm calls (the Objective-C OOScript stand-in until bead
// oo-9ht.133 deleted the facade), and the rest of its virtual members, for the vtable.
std::optional<std::string> OOScript::descriptionComponents()	{ return std::nullopt; }
std::optional<std::string> OOScript::name()					{ return std::nullopt; }
std::optional<std::string> OOScript::scriptDescription()		{ return std::nullopt; }
std::optional<std::string> OOScript::version()				{ return std::nullopt; }
bool OOScript::requiresTickle()								{ return false; }
void OOScript::runWithTarget(Entity *)						{}
bool OOScript::callMethod(ooscript::PropertyId, ooscript::Context, ooscript::Value *, int, ooscript::Value *)	{ return false; }
std::string OOScript::className() const						{ return "OOScript"; }
std::string OOScript::description() const						{ return "<OOScript>"; }
ooscript::Value OOScript::jsValueInContext(ooscript::Context)	{ std::abort(); }	// never reached (no engine is linked)
void OOScript::clearJSSelf(ooscript::Object)					{}
void OOScriptAutorelease(oo::Ref<OOScript>)					{}

// Only good.js loads.
oo::Ref<OOScript> OOScript::jsScriptFromFileNamed(const std::string &fileName, const oo::PList &)
{
	gLog.push_back("script " + fileName);
	return (fileName == "good.js") ? oo::makeRef<OOScript>() : nullptr;
}


// Keys come back as given; "taken" is in use by "compass"; mission_TL_FOR_EQ_SHIELD_BOOSTER is 7.
// PLAYER: C++ since bead oo-9ht.177 deleted the Objective-C player this stood in for; the members
// the code under test calls, declared as PlayerEntity.h declares them (the test imports no game
// header that defines the class), with the same answers.
class PlayerEntity
{
public:
	oo::PList processKeyCode(const oo::PList &key_def);
	std::optional<std::string> validateKey(const std::string &key, const oo::PList &check_keys);
	oo::PList missionVariableForKey(const std::string &key);
};

oo::PList PlayerEntity::processKeyCode(const oo::PList &key_def)	{ return key_def; }
std::optional<std::string> PlayerEntity::validateKey(const std::string &key, const oo::PList &check_keys)
{
	gLog.push_back("validate " + key);
	const oo::PList *first = check_keys.at(0);
	return (first != nullptr && first->get<std::string>("key") == "taken") ? std::optional<std::string>("compass") : std::nullopt;
}
oo::PList PlayerEntity::missionVariableForKey(const std::string &key)
{
	return (key == "mission_TL_FOR_EQ_SHIELD_BOOSTER") ? oo::PList("7") : oo::PList();
}

PlayerEntity *gOOPlayer = nullptr;


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
	if (gSharedUniverse == nil)  gSharedUniverse = new Universe();
	if (gOOPlayer == nullptr)  gOOPlayer = new PlayerEntity;	// never deleted
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
	std::snprintf(buffer, sizeof buffer, "(%g %g %g %g)", color->redComponent(), color->greenComponent(), color->blueComponent(), color->alphaComponent());
	return buffer;
}


// Everything an equipment type answers, in one line.
std::string Describe(OOEquipmentType *t)
{
	if (t == nil)  return "nil";
	char buffer[1024];
	std::snprintf(buffer, sizeof buffer,
		"%s/%s \"%s\" \"%s\" tl%llu/%llu cr%llu all%d empty%d mounted%d clean%d notclean%d berth%d full%d nonfull%d primary%d store%d portable%d multiple%d dmg%g canDmg%d vis%d hide%d player%d npc%d cargo%u def%d off%d install%zu repair%zu turret%d mining%d range%g energy%g damage%g recharge%g temp%g threat%g",
		t->identifier().value_or("-").c_str(), t->damagedIdentifier().value_or("-").c_str(), t->name().value_or("-").c_str(), t->descriptiveText().value_or("-").c_str(),
		(unsigned long long)t->techLevel(), (unsigned long long)t->effectiveTechLevel(), (unsigned long long)t->price(), t->isAvailableToAll(), t->requiresEmptyPylon(), t->requiresMountedPylon(),
		t->requiresCleanLegalRecord(), t->requiresNonCleanLegalRecord(), t->requiresFreePassengerBerth(), t->requiresFullFuel(), t->requiresNonFullFuel(),
		t->isPrimaryWeapon(), t->isMissileOrMine(), t->isPortableBetweenShips(), t->canCarryMultiple(), t->damageProbability(), t->canBeDamaged(),
		t->isVisible(), t->hideValues(), t->isAvailableToPlayer(), t->isAvailableToNPCs(), t->requiredCargoSpace(), t->fastAffinityDefensive(), t->fastAffinityOffensive(),
		(size_t)t->installTime(), (size_t)t->repairTime(), t->isTurretLaser(), t->isMiningLaser(), t->weaponRange(), t->weaponEnergyUse(), t->weaponDamage(),
		t->weaponRechargeRate(), t->weaponShotTemperature(), t->weaponThreatAssessment());
	std::string provides;
	for (const std::string &p : t->providesForScripting())  provides += p + " ";
	return std::string(buffer) + " requires " + Keys(t->requiresEquipment()) + " any " + Keys(t->requiresAnyEquipment()) + " incompatible " + Keys(t->incompatibleEquipment())
		+ " provides " + provides + "conditions " + std::to_string(t->conditions().count()) + ((t->conditions().isNull()) ? "(null)" : "")
		+ " condition " + t->conditionScript().value_or("-") + " script " + t->scriptName().value_or("-") + " info " + std::to_string(t->scriptInfo().count())
		+ " activate " + std::to_string(t->defaultActivateKey().count()) + " mode " + std::to_string(t->defaultModeKey().count())
		+ " display " + Colour(t->displayColor().get()) + " weapon " + Colour((t->weaponColor()).get()) + " weaponInfo " + std::to_string(t->weaponInfo().count())
		+ " fx " + t->fxShotMissName().value_or("-") + " " + t->fxShotHitName().value_or("-") + " " + t->fxShieldHitName().value_or("-") + " "
		+ t->fxUnshieldedHitName().value_or("-") + " " + t->fxWeaponLaunchedName().value_or("-");
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


std::string Identifiers(const std::vector<oo::Ref<OOEquipmentType>> &types)
{
	std::string result;
	for (const auto &t : types)  result += t->identifier().value_or("-") + " ";
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

	{
		Reset();
		OOEquipmentType::loadEquipment();
		OO_CHECK(expect(Log()));
		OO_CHECK(expect(Identifiers(OOEquipmentType::allEquipmentTypes())));
		OO_CHECK(expect(Identifiers(OOEquipmentType::allEquipmentTypesOutfitting())));
		for (const char *key : { "EQ_FUEL", "EQ_MISSILE", "EQ_PASSENGER_BERTH_REMOVAL", "EQ_QC_MINE", "EQ_WEAPON_PULSE_LASER", "EQ_SHIELD_BOOSTER", "EQ_SCOOPER", "EQ_BROKEN", "EQ_EMPTY_NAME", "EQ_NO_NAME", "EQ_OUTFIT" })
		{
			gLog.clear();
			OO_CHECK(expect(Describe(OOEquipmentType::equipmentTypeWithIdentifier(key).get())));
			OO_CHECK(expect(Log()));
		}
		OO_CHECK(expect(OOEquipmentType::equipmentTypeWithIdentifier("EQ_SHIELD_BOOSTER").get()->descriptionComponents().value_or("-")));
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
	{
		Reset();
		OOEquipmentType::loadEquipment();
		fuel = OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get();	// not retained, as ShipEntity keeps weapon types
	}
	{
		// The registry keeps its types: the same object, pool after pool, and from every list.
		OO_CHECK(fuel != nil && OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get() == fuel);
		OO_CHECK(OOEquipmentType::allEquipmentTypes().front().get() == fuel);
		OO_CHECK(fuel->identifier() == std::optional<std::string>("EQ_FUEL"));
		OO_CHECK(OOEquipmentType::allEquipmentTypesOutfitting().front().get() != fuel);	// its own objects

		// Added types go to both lists and the index.
		OOEquipmentType::addEquipmentWithInfo(Item(3, 30, "Extra", "EQ_EXTRA_MISSILE", "Added"));
		OOEquipmentType::addEquipmentWithInfo(oo::PList("not an entry"));
		OO_CHECK(expect(Identifiers(OOEquipmentType::allEquipmentTypes())));
		OO_CHECK(expect(Identifiers(OOEquipmentType::allEquipmentTypesOutfitting())));
		OO_CHECK(expect(Describe(OOEquipmentType::equipmentTypeWithIdentifier("EQ_EXTRA_MISSILE").get())));

		// The missile registry.
		OO_CHECK(!OOEquipmentType::getMissileRegistryRoleForShip("viper").has_value());
		OOEquipmentType::setMissileRegistryRole("EQ_MISSILE", "viper");
		OOEquipmentType::setMissileRegistryRole("EQ_MINE", "");
		OO_CHECK(OOEquipmentType::getMissileRegistryRoleForShip("viper") == std::optional<std::string>("EQ_MISSILE"));
		OO_CHECK(!OOEquipmentType::getMissileRegistryRoleForShip("").has_value());

		// The display colour can be replaced.
		OOEquipmentType *laser = OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_PULSE_LASER").get();
		laser->setDisplayColor(OOColor::blueColor().get());
		OO_CHECK(expect(Colour(laser->displayColor().get())));
		laser->setDisplayColor(nullptr);
		OO_CHECK(expect(Colour(laser->displayColor().get())));
	}
	{
		// Strict standards: legacy conditions are dropped and TL99 stays 99.
		Reset();
		gEnforceStandards = YES;
		OOEquipmentType::loadEquipment();
		OO_CHECK(expect(Log()));
		OOEquipmentType *booster = OOEquipmentType::equipmentTypeWithIdentifier("EQ_SHIELD_BOOSTER").get();
		OO_CHECK(booster->conditions().isNull() && booster->effectiveTechLevel() == 99);
		OO_CHECK(OOEquipmentType::equipmentTypeWithIdentifier("EQ_EXTRA_MISSILE").get() == nil);	// a reload starts again
		OO_CHECK(OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get()->identifier() == std::optional<std::string>("EQ_FUEL"));
	}
}


OO_TEST(cxxClass)
{
	{
		Reset();
		OOEquipmentType::loadEquipment();
		const std::vector<oo::Ref<OOEquipmentType>> all = OOEquipmentType::allEquipmentTypes();
		OO_CHECK(all.size() == 9 && OOEquipmentType::allEquipmentTypesOutfitting().size() == 2);
		oo::Ref<OOEquipmentType> laser = OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_PULSE_LASER");
		OO_CHECK(laser != nullptr && laser == all[4]);
		OO_CHECK(OOEquipmentType::equipmentTypeWithIdentifier("EQ_NO_NAME") == nullptr);
		OO_CHECK(laser->identifier() == std::optional<std::string>("EQ_WEAPON_PULSE_LASER") && laser->isPrimaryWeapon() && laser->isTurretLaser());
		OO_CHECK(laser->weaponRange() == 15000.0f && laser->weaponDamage() == 10.0f && laser->fxShotHitName() == std::optional<std::string>("[zap]"));
		OO_CHECK(laser->displayColor() != nullptr && laser->displayColor()->greenComponent() == 1.0f);
		OO_CHECK(laser->weaponColor()->redComponent() == 1.0f);
		laser->setDisplayColor(OOColor::blueColor().get());
		OO_CHECK(laser->displayColor()->blueComponent() == 1.0f);
		OO_CHECK(laser->descriptionComponents() == std::optional<std::string>("EQ_WEAPON_PULSE_LASER \"Pulse laser\""));

		oo::Ref<OOEquipmentType> booster = OOEquipmentType::equipmentTypeWithIdentifier("EQ_SHIELD_BOOSTER");
		OO_CHECK(booster->techLevel() == 99 && booster->effectiveTechLevel() == 7);
		OO_CHECK(booster->requiresEquipment() == std::optional<std::vector<std::string>>({ "EQ_A", "EQ_B" }));
		OO_CHECK(booster->provides("boost") && !booster->provides("speed") && booster->repairTime() == 300);

		OOEquipmentType::addEquipmentWithInfo(Item(3, 30, "Extra", "EQ_EXTRA_MINE", "Added"));
		OO_CHECK(OOEquipmentType::equipmentTypeWithIdentifier("EQ_EXTRA_MINE")->fxWeaponLaunchedName() == std::optional<std::string>("[mine-launched]"));
		OOEquipmentType::setMissileRegistryRole("EQ_EXTRA_MINE", "cobra");
		OO_CHECK(OOEquipmentType::getMissileRegistryRoleForShip("cobra") == std::optional<std::string>("EQ_EXTRA_MINE"));
	}
}


OO_TEST(objectNode)
{
	// A type is its own PList Object node payload (bead oo-9ht.28), as its facade was the node's
	// object: the node gives the same type back, and describes it as "%@" printed the facade.
	{
		Reset();
		OOEquipmentType::loadEquipment();
		OOEquipmentType *fuel = OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get();
		const oo::PList node = OOEquipmentTypeObjectNode(fuel);
		OO_CHECK(OOEquipmentTypeInObjectNode(node) == fuel);
		OO_CHECK(OOEquipmentTypeObjectNode(nullptr).isNull() && OOEquipmentTypeInObjectNode(oo::PList("EQ_FUEL")) == nullptr);
		OO_CHECK(fuel->className() == "OOEquipmentType");
		const std::string text = fuel->description();
		OO_CHECK(text.rfind("<OOEquipmentType 0x", 0) == 0 && text.find(">{EQ_FUEL \"Fuel\"}") != std::string::npos);
		const oo::PList nodes = OOEquipmentTypeObjectNodes({ oo::Ref<OOEquipmentType>(fuel), oo::Ref<OOEquipmentType>(), oo::Ref<OOEquipmentType>(fuel) });
		OO_CHECK(nodes.count() == 2 && OOEquipmentTypeInObjectNode((*nodes.getIf<oo::PList::Array>())[1]) == fuel);
	}
}


OO_TEST(facadeIdentity)
{
	OOEquipmentType *fuel = nil;
	oo::Ref<OOColor> blue;	// the C++ colour since bead oo-9ht.1
	{
		Reset();
		OOEquipmentType::loadEquipment();
		fuel = OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get();

		// The display colour comes back as the same colour.
		blue = OOColor::blueColor();
		fuel->setDisplayColor(blue.get());
		OO_CHECK(fuel->displayColor().get() == blue);
	}
	{
		// A registered type outlives the pool (ships keep them unretained), and a type registered
		// later is the same object each time it is looked up.
		OO_CHECK(OOEquipmentType::equipmentTypeWithIdentifier("EQ_FUEL").get() == fuel && fuel->displayColor().get() == blue);
		OOEquipmentType::addEquipmentWithInfo(Item(3, 30, "Quiet", "EQ_QUIET", "Added in C++"));
		OOEquipmentType *quiet = OOEquipmentType::equipmentTypeWithIdentifier("EQ_QUIET").get();
		OO_CHECK(quiet != nil && quiet == OOEquipmentType::equipmentTypeWithIdentifier("EQ_QUIET").get());
		blue = nullptr;
	}
}


// The JS glue of OOEquipmentType (OOJSPrivateObject), defined in OOJSEquipmentInfo.mm, which
// this test does not link (bead oo-6symp.3): the vtable names these.
ooscript::Value OOEquipmentType::jsValueInContext(ooscript::Context)  { return ooscript::Value(); }
void OOEquipmentType::clearJSSelf(ooscript::Object)  {}
std::optional<std::string> OOEquipmentType::jsDescription()  { return std::nullopt; }


OO_TEST_MAIN()
