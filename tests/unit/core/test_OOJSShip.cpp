/*	test_OOJSShip.mm
	Unit tests for the ship JS binding (src/Core/Scripting/OOJSShip.h/.mm): the test-first half of
	its slice beads (oo-18mg2, slice 1 of docs/phases/3-slices/OOJSShip.md, and the slices after
	it), converted the way bead oo-ppc converted OOJSVector (proposed ADR-0056, amendments oo-ppc,
	oo-luhd, oo-ft5n and oo-9ht.139).

	The Ship object is made by the real engine for a real ship, so the test links every game object
	but main's (tests/unit/core/meson.build entry ['*'], as test_OOJSPlayerShip does) and runs the
	binding in the engine's own context. The ship is a ShipEntity set up by ShipEntity's own
	-setUpShipFromDictionary: from a definition in the test (PlainShip, as test_ShipEntity.mm's),
	in a Universe that was never initialised and with a plain entity as PLAYER (amendment oo-bj8
	item 11); the player branches of the getter read the engine's own player, whose class the test
	swaps for a subclass that answers -availableFacings and -fleeingStatus itself. The expectations
	were written against the Objective-C file and run on it first; slice 1 pins the property
	getter (every property) and the weapon offsets and colours its helpers give JavaScript.
	Run: bash tools/check-core-tests.sh test_OOJSShip
*/

#include "OOJavaScriptEngine.h"
#include "OOJSShip.h"
#include "OOJSPlayer.h"
#include "Universe.h"
#include "ShipEntity.h"
#include "PlayerEntity.h"
#include "ResourceManager.h"
#include "EntityOOJavaScriptExtensions.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/String.hpp"
#include "oo_test.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


// What UNIVERSE and PLAYER read (Universe.mm, PlayerEntity.mm).
extern Universe *gSharedUniverse;
extern PlayerEntity *gOOPlayer;


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


// MARK: The stand-ins -----------------------------------------------------------------------------

namespace {

// What the stand-ins were told, in order (slice 2 on).
std::vector<std::string> sLog;
Entity *sNextBeacon = nil;
BOOL sPlayerDocked = NO;	// what the engine's player answers -isDocked (slice 3)

}	// namespace


// PLAYER while ships are made (test_ShipEntity.mm's), and the beacon the player's compass was on.
class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
	Entity *nextBeacon() override	{ return sNextBeacon; }	// the C++ entity since bead oo-9ht.39.23
	void setCompassMode(OOCompassMode value) override	{ sLog.push_back(oo::str::format("setCompassMode %d", static_cast<int>(value))); }
	void setScriptTarget(::ShipEntity * ship) override	{ sLog.push_back("setScriptTarget " + (ship != nullptr ? ship->getName() : std::optional<std::string>()).value_or("(nil)")); }
	unsigned score() override	{ return 1000; }
	void runUnsanitizedScriptActions(const oo::PList & unsanitizedActions, bool allowAIMethods, const std::optional<std::string> & contextName, ::ShipEntity * target) override	{ sLog.push_back(oo::str::format("runUnsanitizedScriptActions %s %d %s %s", oo::DescriptionOf(unsanitizedActions).c_str(), allowAIMethods ? 1 : 0, contextName.value_or("(nil)").c_str(), (target != nullptr ? target->getName() : std::optional<std::string>()).value_or("(nil)").c_str())); }
};




// The universe: never initialised (test_ShipEntity.mm's), recording what the beacon setter tells it.
class TestUniverse : public Universe
{
public:
	// The C++ entity since bead oo-9ht.39.8.10 (its object's -beaconCode was the ship's).
	void setNextBeacon(Entity *beacon) override	{ ShipEntity *ship = dynamic_cast<ShipEntity *>(beacon); sLog.push_back("setNextBeacon " + (ship != nullptr ? ship->beaconCode() : std::optional<std::string>()).value_or("(none)")); }
	void clearBeacon(Entity *beacon) override	{ (void)beacon; sLog.push_back("clearBeacon"); }
	void unMagicMainStation() override	{ sLog.push_back("unMagicMainStation"); }
	Entity *hazardOnRouteFromEntity(Entity * /*e1*/, double dist, HPVector p2) override	// the C++ entities since bead oo-9ht.39.8.6
	{
		sLog.push_back(oo::str::format("hazardOnRoute %g (%g, %g, %g)", dist, p2.x, p2.y, p2.z));
		return nullptr;
	}
	bool role(const std::string &role, const std::string &category) override
	{
		sLog.push_back("role " + role + " isInCategory " + category);
		return role == "trader";
	}
	std::vector<oo::EntityHold> getContainersOfCommodity(const std::string &commodity_name, OOCargoQuantity how_many) override	// held C++ entities since bead oo-9ht.39.26
	{
		sLog.push_back(oo::str::format("getContainersOfCommodity %s %u", commodity_name.c_str(), static_cast<unsigned>(how_many)));
		return {};
	}
	HPVector getSafeVectorFromEntity(Entity * /*e1*/, double dist, HPVector p2) override	// the C++ entity since bead oo-9ht.39.8.6
	{
		sLog.push_back(oo::str::format("getSafeVector %g (%g, %g, %g)", dist, p2.x, p2.y, p2.z));
		return make_HPvector(10, 20, 30);
	}
};


// A ship that keeps ShipEntity's own set-up (test_ShipEntity.mm's).
class PlainShip : public ShipEntity	// C++ since bead oo-9ht.144 deleted the Objective-C ship
{
};


namespace {

OOWeaponFacingSet sAvailableFacings = 0;
OOPlayerFleeingStatus sFleeingStatus = PLAYER_FLEEING_NONE;

}	// namespace


// The engine's player, with the two answers the getter's player branches ask for set by the test.
class TestPlayerShip : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	OOWeaponFacingSet availableFacings() override	{ return sAvailableFacings; }
	OOPlayerFleeingStatus fleeingStatus() override	{ return sFleeingStatus; }
	bool isDocked() override	{ return sPlayerDocked; }
	bool setWeaponMount(OOWeaponFacing facing, const std::string & eqKey, const std::optional<std::string> & context) override
	{
		sLog.push_back(oo::str::format("player setWeaponMount %d %s %s", static_cast<int>(facing), eqKey.c_str(), context.value_or("(nil)").c_str()));
		return YES;
	}
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}




namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
PlayerEntity *sRealPlayer = nullptr;
PlainShip *sShip = nil;
PlainShip *sOther = nil;	// a second ship, for the setters that take one (slice 2)


// The definition the test's ship is set up from.
oo::PList ShipDefinition()
{
	return oo::PList(oo::PList::Dict{
		{ "name", oo::PList(std::string("Viper")) },
		{ "ship_name", oo::PList(std::string("Bob")) },
		{ "display_name", oo::PList(std::string("Police Viper")) },
		{ "roles", oo::PList(std::string("police trader")) },
		{ "scan_class", oo::PList(std::string("CLASS_POLICE")) },
		{ "scan_description", oo::PList(std::string("Cop")) },
		{ "max_flight_speed", oo::PList(300.0) },
		{ "max_flight_roll", oo::PList(3.0) },
		{ "max_flight_pitch", oo::PList(1.5) },
		{ "max_flight_yaw", oo::PList(0.5) },
		{ "thrust", oo::PList(20.0) },
		{ "injector_burn_rate", oo::PList(0.5) },
		{ "injector_speed_factor", oo::PList(4.0) },
		{ "max_energy", oo::PList(500.0) },
		{ "energy_recharge_rate", oo::PList(4.0) },
		{ "weapon_facings", oo::PList(5) },
		{ "max_missiles", oo::PList(3) },
		{ "max_cargo", oo::PList(20) },
		{ "extra_cargo", oo::PList(5) },
		{ "accuracy", oo::PList(3.0) },
		{ "fuel", oo::PList(70) },
		{ "heat_insulation", oo::PList(1.5) },
		{ "beacon", oo::PList(std::string("B")) },
		{ "beacon_label", oo::PList(std::string("Beacon B")) },
		{ "reaction_time", oo::PList(2.0) },
		{ "sun_glare_filter", oo::PList(0.5) },
		{ "scanner_range", oo::PList(30000.0) },
		{ "hyperspace_motor_spin_time", oo::PList(10.0) },
		{ "escorts", oo::PList(4) },
		{ "script_info", oo::PList(oo::PList::Dict{ { "a", oo::PList(1) } }) },
		{ "weapon_mount_mode", oo::PList(std::string("multiply")) },
		{ "weapon_position_forward", oo::PList(oo::PList::Array{ oo::PList(std::string("1 0 0")), oo::PList(std::string("-1 0 0")) }) },
		{ "weapon_position_aft", oo::PList(std::string("0 0 -2")) },
		{ "scanner_display_color1", oo::PList(std::string("redColor")) },
		{ "scanner_display_color2", oo::PList(oo::PList::Array{ oo::PList(0.0), oo::PList(0.5), oo::PList(1.0) }) },
		{ "exhaust_emissive_color", oo::PList(std::string("greenColor")) },
	});
}


// The scratch home and game folder, the engine, the universe, PLAYER and the ship; made once.
void SetUp()
{
	if (!sRoot.empty())  return;
	std::setvbuf(stdout, nullptr, _IONBF, 0);	// a crash keeps the results so far
	sRoot = stdfs::temp_directory_path() / ("oo-test-jsship-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot / "Resources");
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	const std::string info = "{ CFBundleVersion = \"9.9.9-test\"; }";
	OO_CHECK(oo::fs::writeFile(sRoot / "Resources" / "Info-gnustep.plist", oo::Data(info.data(), info.size()), oo::fs::WriteMode::direct).has_value());
	ResourceManager::setUseAddOns(std::string(SCENARIO_OXP_DEFINITION_NONE));	// strict: the built-in Resources alone
	// The engine's player is a TestPlayerShip: made first, so InitOOJSPlayerShip()'s
	// PlayerEntity::sharedPlayer() answers it (the C++ player cannot change class, as
	// object_setClass() made the Objective-C one a TestPlayerShip; bead oo-9ht.177).
	gOOPlayer = NewTestPlayer<TestPlayerShip>();
	(void)OOJavaScriptEngine::sharedEngine();

	sRealPlayer = gOOPlayer;	// the one InitOOJSPlayerShip() made, which player.ship holds
	sRealPlayer->isPlayer = true;	// what the player's set-up sets, which the engine's player has not run

	Universe *universe = new TestUniverse();	// never released
	gSharedUniverse = universe;
	gOOPlayer = NewTestPlayer<TestPlayer>();

	sShip = static_cast<PlainShip *>(oo::ToShip(oo::NewShipObject(oo::makeRef<PlainShip>(), "jsship", ShipDefinition())));
	OO_CHECK(sShip != nil);
	if (sShip != nullptr)  sShip->setTemperature(64.0f);
	if (sShip != nullptr)  sShip->setDestination(make_HPvector(1, 2, 3));
	if (sShip != nullptr)  sShip->setDesiredSpeed(100);
	if (sShip != nullptr)  sShip->setDesiredRange(500);
	if (sShip != nullptr)  sShip->setVelocity(make_vector(4, 5, 6));
	if (sShip != nullptr)  sShip->setHomeSystem(7);
	if (sShip != nullptr)  sShip->setDestinationSystem(9);
	if (sShip != nullptr)  sShip->setScriptedMisjump(YES);
	if (sShip != nullptr)  sShip->setScriptedMisjumpRange(0.75f);
	if (sShip != nullptr)  sShip->setSpeed(50);
	if (sShip != nullptr)  sShip->setReportAIMessages(YES);
	if (sShip != nullptr)  sShip->setTrackCloseContacts(YES);
	if (sShip != nullptr)  sShip->setAIScriptWakeTime(12.5);
	if (sShip != nullptr)  sShip->setBounty(25, kOOLegalStatusReasonSetup);
	sOther = static_cast<PlainShip *>(oo::ToShip(oo::NewShipObject(oo::makeRef<PlainShip>(), "other", oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Other")) } }))));
	OO_CHECK(sOther != nil);
}


// Evaluates src in the engine's context, with the test's ship as the global `ship`, and gives its
// result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const std::string &src)
{
	SetUp();
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Object global = OOJavaScriptEngine::sharedEngine()->globalObject();
	ooscript::Value shipValue = sShip->jsValueInContext(context);
	ooscript::setProperty(context, global, "ship", &shipValue);
	ooscript::Value otherValue = sOther->jsValueInContext(context);
	ooscript::setProperty(context, global, "other", &otherValue);
	std::string wrapped = "(function () { try { return String(" + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	ooscript::Value result = ooscript::undefinedValue();
	std::string text;
	if (!ooscript::evaluateScript(context, global, wrapped.c_str(), static_cast<unsigned>(wrapped.size()), "test.js", 1, &result))
	{
		ooscript::clearPendingException(context);
		text = "<evaluation failed>";
	}
	else
	{
		text = cxx_OOStringFromJSValue(context, result).value_or("<not a string>");
	}
	OOJSRelinquishContext(context);
	return text;
}


std::string EvalShown(const std::string &src, const std::string &expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src.c_str(), result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)


// Whether src threw (a setter refusing a value reports an error, which the engine throws).
bool Threw(const std::string &src)
{
	std::string result = Eval(src);
	bool threw = result.rfind("threw: ", 0) == 0;
	if (!threw)  std::printf("    %s\n    did not throw, gave: %s\n", src.c_str(), result.c_str());
	return threw;
}


std::string Log()
{
	std::string result;
	for (const std::string &line : sLog)  result += (result.empty() ? "" : "; ") + line;
	sLog.clear();
	return result;
}


std::string LogShown(const std::string &expected)
{
	std::string result = Log();
	if (result != expected)  std::printf("    log gave: %s\n", result.c_str());
	return result;
}
#define OO_CHECK_LOG(expected)  OO_CHECK_EQ(LogShown(expected), expected)

}	// namespace


// MARK: Slice 1: the property getter and its helpers (bead oo-18mg2) -----------------------------

OO_TEST(registration)
{
	SetUp();
	OO_CHECK(std::strcmp(JSShipClass()->name, "Ship") == 0);
	OO_CHECK(JSShipPrototype() != nullptr);
	OO_CHECK_EVAL("typeof ship", "object");
	OO_CHECK_EVAL("ship instanceof Ship", "true");
	OO_CHECK_EVAL("Ship.prototype.name", "undefined");	// the prototype has no ship
}


OO_TEST(getterNamesAndRoles)
{
	SetUp();
	OO_CHECK_EVAL("ship.name", "Viper");
	OO_CHECK_EVAL("ship.displayName", "Police Viper");
	OO_CHECK_EVAL("ship.shipUniqueName", "Bob");
	OO_CHECK_EVAL("ship.shipClassName", "Viper");
	OO_CHECK_EVAL("ship.scanDescription", "Cop");
	OO_CHECK_EVAL("JSON.stringify(ship.roles)", "[\"[jsship]\",\"police\",\"trader\"]");	// the ship's key is one of its roles
	OO_CHECK_EVAL("JSON.stringify(ship.roleWeights)", "{\"[jsship]\":1,\"police\":1,\"trader\":1}");
	OO_CHECK_EVAL("ship.primaryRole", "police");
	OO_CHECK_EVAL("ship.dataKey", "jsship");
	OO_CHECK_EVAL("ship.beaconCode", "B");
	OO_CHECK_EVAL("ship.beaconLabel", "Beacon B");
	OO_CHECK_EVAL("ship.isBeacon", "true");
	OO_CHECK_EVAL("ship.entityPersonality === ship.entityPersonality && typeof ship.entityPersonality", "number");
}


OO_TEST(getterAIAndTargets)
{
	SetUp();
	OO_CHECK_EVAL("ship.AI", "<no AI>");	// no AI plist to load in the test's game
	OO_CHECK_EVAL("ship.AIState", "null");
	OO_CHECK_EVAL("ship.AIFoundTarget", "null");
	OO_CHECK_EVAL("ship.AIPrimaryAggressor", "null");
	OO_CHECK_EVAL("ship.hasSuspendedAI", "false");
	OO_CHECK_EVAL("ship.alertCondition", "2");
	OO_CHECK_EVAL("ship.autoAI", "true");
	OO_CHECK_EVAL("ship.autoWeapons", "false");
	OO_CHECK_EVAL("ship.target", "null");
	OO_CHECK_EVAL("JSON.stringify(ship.defenseTargets)", "[]");
	OO_CHECK_EVAL("ship.potentialCollider", "null");
	OO_CHECK_EVAL("ship.hasHostileTarget", "false");
	OO_CHECK_EVAL("ship.reportAIMessages", "true");
	OO_CHECK_EVAL("ship.script", "null");
	OO_CHECK_EVAL("ship.AIScript", "null");
	OO_CHECK_EVAL("ship.AIScriptWakeTime", "12.5");
	OO_CHECK_EVAL("JSON.stringify(ship.scriptInfo)", "{\"a\":1}");
	OO_CHECK_EVAL("ship.trackCloseContacts", "true");
	OO_CHECK_EVAL("ship.markedForFines", "false");
	OO_CHECK_EVAL("ship.withinStationAegis", "false");
}


OO_TEST(getterFlight)
{
	SetUp();
	OO_CHECK_EVAL("ship.accuracy", "3");
	OO_CHECK_EVAL("ship.fuel", "7");
	OO_CHECK_EVAL("ship.fuelChargeRate", "1");
	OO_CHECK_EVAL("ship.bounty", "0");	// a police ship keeps no bounty
	OO_CHECK_EVAL("ship.temperature", "0.25");
	OO_CHECK_EVAL("ship.heatInsulation", "1.5");
	OO_CHECK_EVAL("ship.heading", "(0, 0, 1)");
	OO_CHECK_EVAL("ship.energyRechargeRate", "4");
	OO_CHECK_EVAL("ship.speed", "50");
	OO_CHECK_EVAL("ship.cruiseSpeed", "240");
	OO_CHECK_EVAL("ship.desiredRange", "500");
	OO_CHECK_EVAL("ship.desiredSpeed", "100");
	OO_CHECK_EVAL("ship.destination", "(1, 2, 3)");
	OO_CHECK_EVAL("ship.maxEscorts", "4");
	OO_CHECK_EVAL("ship.maxPitch", "1.5");
	OO_CHECK_EVAL("ship.maxSpeed", "300");
	OO_CHECK_EVAL("ship.maxRoll", "3");
	OO_CHECK_EVAL("ship.maxYaw", "0.5");
	OO_CHECK_EVAL("ship.injectorBurnRate", "0.5");
	OO_CHECK_EVAL("ship.injectorSpeedFactor", "4");
	OO_CHECK_EVAL("ship.maxThrust", "20");
	OO_CHECK_EVAL("ship.thrust", "20");
	OO_CHECK_EVAL("ship.lightsActive", "true");
	OO_CHECK_EVAL("ship.vectorRight", "(1, 0, 0)");
	OO_CHECK_EVAL("ship.vectorForward", "(0, 0, 1)");
	OO_CHECK_EVAL("ship.vectorUp", "(0, 1, 0)");
	OO_CHECK_EVAL("ship.velocity", "(4, 5, 56)");	// with the thrust of its speed
	OO_CHECK_EVAL("ship.thrustVector", "(0, 0, 50)");
	OO_CHECK_EVAL("ship.pitch", "0");
	OO_CHECK_EVAL("ship.roll", "0");
	OO_CHECK_EVAL("ship.yaw", "0");
	OO_CHECK_EVAL("ship.boundingBox", "(0, 0, 0)");
	OO_CHECK_EVAL("ship.savedCoordinates", "(0, 0, 0)");
	OO_CHECK_EVAL("ship.subEntityRotation", "(1 + 0i + 0j + 0k)");
	OO_CHECK_EVAL("ship.hasHyperspaceMotor", "true");
	OO_CHECK_EVAL("ship.hyperspaceSpinTime", "10");
	OO_CHECK_EVAL("ship.scriptedMisjump", "true");
	OO_CHECK_EVAL("ship.scriptedMisjumpRange", "0.75");
	OO_CHECK_EVAL("ship.sunGlareFilter", "0.5");
	OO_CHECK_EVAL("ship.destinationSystem", "9");
	OO_CHECK_EVAL("ship.homeSystem", "7");
	OO_CHECK_EVAL("ship.scannerRange", "30000");
	OO_CHECK_EVAL("ship.reactionTime", "2");
}


OO_TEST(getterKind)
{
	SetUp();
	OO_CHECK_EVAL("ship.isPirate", "false");
	OO_CHECK_EVAL("ship.isPolice", "true");
	OO_CHECK_EVAL("ship.isThargoid", "false");
	OO_CHECK_EVAL("ship.isTurret", "false");
	OO_CHECK_EVAL("ship.isTrader", "false");
	OO_CHECK_EVAL("ship.isPirateVictim", "false");
	OO_CHECK_EVAL("ship.isMissile", "false");
	OO_CHECK_EVAL("ship.isMine", "false");
	OO_CHECK_EVAL("ship.isWeapon", "false");
	OO_CHECK_EVAL("ship.isRock", "false");
	OO_CHECK_EVAL("ship.isMinable", "false");
	OO_CHECK_EVAL("ship.isBoulder", "false");
	OO_CHECK_EVAL("ship.isFleeing", "false");
	OO_CHECK_EVAL("ship.isCargo", "false");
	OO_CHECK_EVAL("ship.isDerelict", "false");
	OO_CHECK_EVAL("ship.isPiloted", "false");	// no crew
	OO_CHECK_EVAL("ship.isFrangible", "true");
	OO_CHECK_EVAL("ship.isCloaked", "false");
	OO_CHECK_EVAL("ship.cloakAutomatic", "true");
	OO_CHECK_EVAL("ship.isJamming", "false");
}


OO_TEST(getterCargoAndCrew)
{
	SetUp();
	OO_CHECK_EVAL("ship.cargoSpaceCapacity", "20");
	OO_CHECK_EVAL("ship.cargoSpaceUsed", "0");
	OO_CHECK_EVAL("ship.cargoSpaceAvailable", "20");
	OO_CHECK_EVAL("JSON.stringify(ship.cargoList)", "[]");
	OO_CHECK_EVAL("ship.extraCargo", "5");
	OO_CHECK_EVAL("ship.commodity", "null");
	OO_CHECK_EVAL("ship.commodityAmount", "0");
	OO_CHECK_EVAL("JSON.stringify(ship.crew)", "null");
	OO_CHECK_EVAL("ship.passengerCount", "0");
	OO_CHECK_EVAL("ship.parcelCount", "0");
	OO_CHECK_EVAL("ship.passengerCapacity", "0");
	OO_CHECK_EVAL("JSON.stringify(ship.passengers)", "[]");
	OO_CHECK_EVAL("JSON.stringify(ship.parcels)", "[]");
	OO_CHECK_EVAL("JSON.stringify(ship.contracts)", "[]");
	OO_CHECK_EVAL("ship.dockingInstructions", "null");
}


OO_TEST(getterGroupsAndSubentities)
{
	SetUp();
	OO_CHECK_EVAL("JSON.stringify(ship.escorts)", "[]");	// its escort group holds only itself
	OO_CHECK_EVAL("ship.group", "null");
	OO_CHECK_EVAL("ship.escortGroup.name + ' ' + ship.escortGroup.count + ' ' + (ship.escortGroup.leader === ship)", "escort group 1 true");
	OO_CHECK_EVAL("JSON.stringify(ship.subEntities)", "[]");
	OO_CHECK_EVAL("JSON.stringify(ship.exhausts)", "[]");
	OO_CHECK_EVAL("JSON.stringify(ship.flashers)", "[]");
	OO_CHECK_EVAL("ship.subEntityCapacity", "0");
	OO_CHECK_EVAL("JSON.stringify(ship.collisionExceptions)", "[]");
}


OO_TEST(getterWeaponsAndEquipment)
{
	SetUp();
	OO_CHECK_EVAL("ship.weaponRange", "0");
	OO_CHECK_EVAL("ship.weaponFacings", "5");
	OO_CHECK_EVAL("String(ship.weaponPositionAft)", "(0, 0, 0)");	// a lone string is not a mount list in multiply mode
	OO_CHECK_EVAL("String(ship.weaponPositionForward)", "(1, 0, 0),(-1, 0, 0)");
	OO_CHECK_EVAL("String(ship.weaponPositionPort)", "(0, 0, 0)");
	OO_CHECK_EVAL("String(ship.weaponPositionStarboard)", "(0, 0, 0)");
	OO_CHECK_EVAL("ship.weaponPositionForward[1] instanceof Vector3D", "true");
	OO_CHECK_EVAL("JSON.stringify(ship.equipment)", "[]");
	OO_CHECK_EVAL("ship.currentWeapon", "null");
	OO_CHECK_EVAL("ship.forwardWeapon", "null");
	OO_CHECK_EVAL("ship.aftWeapon", "null");
	OO_CHECK_EVAL("ship.portWeapon", "null");
	OO_CHECK_EVAL("ship.starboardWeapon", "null");
	OO_CHECK_EVAL("ship.laserHeatLevel", "0");
	OO_CHECK_EVAL("ship.laserHeatLevelAft", "0");
	OO_CHECK_EVAL("ship.laserHeatLevelForward", "0");
	OO_CHECK_EVAL("ship.laserHeatLevelPort", "0");
	OO_CHECK_EVAL("ship.laserHeatLevelStarboard", "0");
	OO_CHECK_EVAL("JSON.stringify(ship.missiles)", "[]");
	OO_CHECK_EVAL("ship.missileCapacity", "3");
	OO_CHECK_EVAL("ship.missileLoadTime", "2");
}


OO_TEST(getterColours)
{
	SetUp();
	OO_CHECK_EVAL("JSON.stringify(ship.scannerDisplayColor1)", "[1,0,0,1]");
	OO_CHECK_EVAL("JSON.stringify(ship.scannerDisplayColor2)", "[0,0.5,1,1]");
	OO_CHECK_EVAL("ship.scannerHostileDisplayColor1", "null");
	OO_CHECK_EVAL("ship.scannerHostileDisplayColor2", "null");
	OO_CHECK_EVAL("JSON.stringify(ship.exhaustEmissiveColor)", "[0,1,0,1]");
}


// The player's ship reads two answers of PlayerEntity's own.
OO_TEST(getterPlayerBranches)
{
	SetUp();
	sAvailableFacings = WEAPON_FACING_FORWARD | WEAPON_FACING_AFT;
	OO_CHECK_EVAL("player.ship.weaponFacings", "3");
	sFleeingStatus = PLAYER_FLEEING_CARGO;
	OO_CHECK_EVAL("player.ship.isFleeing", "true");
	sFleeingStatus = PLAYER_FLEEING_MAYBE;
	OO_CHECK_EVAL("player.ship.isFleeing", "false");
	sFleeingStatus = PLAYER_FLEEING_NONE;
	OO_CHECK_EVAL("player.ship.isPiloted", "true");
}


// MARK: Slice 2: the property setter (bead oo-chjz4) ----------------------------------------------

// A setter's value read back through the getter: "(ship.<prop> = <value>, ship.<prop>)".
#define SET(prop, value)  "(ship." prop " = " value ", ship." prop ")"


OO_TEST(setterNames)
{
	SetUp();
	OO_CHECK_EVAL(SET("name", "'Asp'"), "Asp");
	OO_CHECK_EVAL(SET("displayName", "'Asp Mk II'"), "Asp Mk II");
	OO_CHECK_EVAL(SET("shipUniqueName", "'Jim'"), "Jim");
	OO_CHECK_EVAL(SET("shipClassName", "'Asp'"), "Asp");
	OO_CHECK_EVAL(SET("scanDescription", "'Hunter'"), "Hunter");
	OO_CHECK_EVAL(SET("scanDescription", "null"), "null");	// can be cleared
	OO_CHECK_EVAL(SET("primaryRole", "'hunter'"), "hunter");
	OO_CHECK_EVAL(SET("beaconLabel", "'Label'"), "Label");
	OO_CHECK_EVAL(SET("AIState", "'ATTACK'"), "null");	// as the Objective-C setter answered (oo-lk92s)
}


OO_TEST(setterBeaconCode)
{
	SetUp();
	Log();
	OO_CHECK_EVAL(SET("beaconCode", "'C'"), "C");	// already a beacon: only the code changes
	OO_CHECK_LOG("");
	sNextBeacon = sShip;	// the compass is on this beacon
	OO_CHECK_EVAL(SET("beaconCode", "''"), "C");	// cleared from the universe's list, code kept
	OO_CHECK_LOG("clearBeacon; setCompassMode " + std::to_string(static_cast<int>(COMPASS_MODE_PLANET)));
	sNextBeacon = nil;
	OO_CHECK_EVAL(SET("beaconCode", "null"), "C");
	OO_CHECK_LOG("clearBeacon");
	OO_CHECK_EVAL("(other.beaconCode = 'D', other.beaconCode)", "D");	// not a beacon yet: the universe lists it
	OO_CHECK_LOG("setNextBeacon D");
	OO_CHECK_EVAL("(other.beaconCode = '', other.isBeacon)", "true");	// now a beacon: cleared from the list
	OO_CHECK_LOG("clearBeacon");
}


OO_TEST(setterNumbers)
{
	SetUp();
	OO_CHECK_EVAL(SET("accuracy", "4"), "4");
	OO_CHECK_EVAL(SET("fuel", "3.5"), "3.5");
	OO_CHECK_EVAL(SET("fuel", "99"), "7");	// at most MAX_JUMP_RANGE
	OO_CHECK_EVAL(SET("entityPersonality", "5"), "5");
	OO_CHECK(Threw("ship.entityPersonality = -1"));
	OO_CHECK_EVAL(SET("hyperspaceSpinTime", "12"), "12");
	OO_CHECK_EVAL(SET("bounty", "-5"), "0");
	OO_CHECK_EVAL(SET("bounty", "30"), "0");	// as the Objective-C setter answered (oo-lk92s)
	OO_CHECK_EVAL(SET("cargoSpaceCapacity", "10"), "10");
	OO_CHECK_EVAL(SET("cargoSpaceCapacity", "-3"), "0");
	OO_CHECK_EVAL(SET("destinationSystem", "-3"), "0");
	OO_CHECK_EVAL(SET("homeSystem", "4"), "4");
	OO_CHECK_EVAL(SET("AIScriptWakeTime", "3"), "3");
	OO_CHECK_EVAL(SET("temperature", "-1"), "0");
	OO_CHECK_EVAL(SET("temperature", "0.5"), "0.5");
	OO_CHECK_EVAL(SET("heatInsulation", "0"), "0.125");
	OO_CHECK_EVAL(SET("missileLoadTime", "-2"), "0");
	OO_CHECK_EVAL(SET("missileLoadTime", "1.5"), "1.5");
	OO_CHECK_EVAL(SET("reactionTime", "1.5"), "1.5");
	OO_CHECK_EVAL(SET("desiredSpeed", "-1"), "0");
	OO_CHECK_EVAL(SET("desiredSpeed", "80"), "80");
	OO_CHECK_EVAL(SET("speed", "60"), "60");
	OO_CHECK(Threw("ship.speed = -1"));
	OO_CHECK(Threw("ship.speed = NaN"));
	OO_CHECK_EVAL(SET("desiredRange", "-4"), "0");
	OO_CHECK_EVAL(SET("desiredRange", "250"), "250");
	OO_CHECK_EVAL(SET("scriptedMisjumpRange", "0.25"), "0.25");
	OO_CHECK(Threw("ship.scriptedMisjumpRange = 2"));
	OO_CHECK_EVAL(SET("sunGlareFilter", "0.25"), "0.25");
	OO_CHECK(Threw("ship.sunGlareFilter = 2"));
	OO_CHECK_EVAL(SET("thrust", "100"), "20");	// at most maxThrust
	OO_CHECK_EVAL(SET("thrust", "5"), "5");
	OO_CHECK_EVAL(SET("maxPitch", "2"), "2");
	OO_CHECK(Threw("ship.maxPitch = -1"));
	OO_CHECK_EVAL(SET("maxSpeed", "350"), "350");
	OO_CHECK(Threw("ship.maxSpeed = -1"));
	OO_CHECK_EVAL(SET("maxRoll", "4"), "4");
	OO_CHECK(Threw("ship.maxRoll = -1"));
	OO_CHECK_EVAL(SET("maxYaw", "1"), "1");
	OO_CHECK(Threw("ship.maxYaw = -1"));
	OO_CHECK_EVAL(SET("injectorBurnRate", "0.25"), "0.25");
	OO_CHECK(Threw("ship.injectorBurnRate = -1"));
	OO_CHECK_EVAL(SET("injectorSpeedFactor", "2"), "2");
	OO_CHECK(Threw("ship.injectorSpeedFactor = 0.5"));
	OO_CHECK(Threw("ship.injectorSpeedFactor = 1000"));
	OO_CHECK_EVAL(SET("maxThrust", "30"), "30");
	OO_CHECK(Threw("ship.maxThrust = -1"));
	OO_CHECK_EVAL(SET("energyRechargeRate", "6"), "6");
	OO_CHECK(Threw("ship.energyRechargeRate = -1"));
	OO_CHECK_EVAL(SET("maxEscorts", "2"), "2");
	OO_CHECK(Threw("ship.maxEscorts = 20"));
	OO_CHECK(!Threw("ship.fuel = 'lots'"));	// the Objective-C setter did not throw (oo-lk92s)
}


OO_TEST(setterFlags)
{
	SetUp();
	OO_CHECK_EVAL(SET("isCloaked", "false"), "false");
	OO_CHECK_EVAL(SET("cloakAutomatic", "false"), "false");
	OO_CHECK_EVAL(SET("reportAIMessages", "false"), "false");
	OO_CHECK_EVAL(SET("trackCloseContacts", "false"), "false");
	OO_CHECK_EVAL(SET("isBoulder", "true"), "true");
	OO_CHECK_EVAL(SET("scriptedMisjump", "false"), "false");
	OO_CHECK_EVAL(SET("lightsActive", "false"), "false");
	OO_CHECK_EVAL(SET("lightsActive", "true"), "true");
}


OO_TEST(setterVectors)
{
	SetUp();
	OO_CHECK_EVAL(SET("destination", "[7, 8, 9]"), "(7, 8, 9)");
	OO_CHECK_EVAL(SET("savedCoordinates", "[1, 1, 1]"), "(1, 1, 1)");
	OO_CHECK_EVAL(SET("subEntityRotation", "[0, 1, 0, 0]"), "(0 + 1i + 0j + 0k)");
	OO_CHECK_EVAL("(ship.speed = 0, " SET("velocity", "[1, 2, 3]") ")", "(1, 2, 3)");
	OO_CHECK(Threw("ship.destination = 'nowhere'"));
}


OO_TEST(setterColours)
{
	SetUp();
	OO_CHECK_EVAL("JSON.stringify(" SET("scannerDisplayColor1", "'blueColor'") ")", "[0,0,1,1]");
	OO_CHECK_EVAL(SET("scannerDisplayColor1", "null"), "1,0,0,1");	// as the Objective-C setter answered (oo-lk92s)
	OO_CHECK_EVAL("JSON.stringify(" SET("scannerDisplayColor2", "[1, 1, 0]") ")", "[1,1,0,1]");
	OO_CHECK_EVAL("JSON.stringify(" SET("scannerHostileDisplayColor1", "'whiteColor'") ")", "[1,1,1,1]");
	OO_CHECK_EVAL("JSON.stringify(" SET("scannerHostileDisplayColor2", "'blackColor'") ")", "[0,0,0,1]");
	OO_CHECK_EVAL("JSON.stringify(" SET("exhaustEmissiveColor", "'redColor'") ")", "[1,0,0,1]");
	OO_CHECK(Threw("ship.exhaustEmissiveColor = true"));
}


OO_TEST(setterTargetsAndGroups)
{
	SetUp();
	OO_CHECK_EVAL(SET("AIFoundTarget", "other") " === other", "true");
	OO_CHECK_EVAL(SET("AIFoundTarget", "null"), "null");
	OO_CHECK_EVAL(SET("AIPrimaryAggressor", "other") " === other", "true");
	OO_CHECK_EVAL(SET("AIPrimaryAggressor", "null"), "null");
	OO_CHECK(Threw("ship.AIFoundTarget = 7"));
	OO_CHECK_EVAL(SET("target", "null"), "null");
	OO_CHECK_EVAL("(ship.group = new ShipGroup('wing'), ship.group.name)", "wing");
	OO_CHECK_EVAL(SET("group", "null"), "null");
	OO_CHECK(Threw("ship.group = 'wing'"));
}


OO_TEST(setterWeapons)
{
	SetUp();
	OO_CHECK_EVAL("(ship.forwardWeapon = 'EQ_WEAPON_NONE', ship.forwardWeapon)", "null");
	OO_CHECK_EVAL("(ship.aftWeapon = null, ship.aftWeapon)", "null");
	Log();
	OO_CHECK_EVAL("(player.ship.portWeapon = 'EQ_WEAPON_PULSE_LASER', 'set')", "set");
	OO_CHECK_LOG(oo::str::format("player setWeaponMount %d EQ_WEAPON_PULSE_LASER scripted", static_cast<int>(WEAPON_FACING_PORT)));
	OO_CHECK_EVAL("(player.ship.starboardWeapon = null, 'set')", "set");
	OO_CHECK_LOG(oo::str::format("player setWeaponMount %d EQ_WEAPON_NONE scripted", static_cast<int>(WEAPON_FACING_STARBOARD)));
}


// The player's ship refuses what is the player's to fly.
OO_TEST(setterPlayerReadOnly)
{
	SetUp();
	for (const char *prop : { "name", "displayName", "primaryRole", "AIState", "beaconCode", "beaconLabel", "accuracy", "AIFoundTarget", "AIPrimaryAggressor", "reactionTime", "isBoulder", "destination", "desiredSpeed", "speed", "desiredRange", "maxEscorts" })
	{
		const std::string src = std::string("player.ship.") + prop + " = 1";
		std::string result = Eval(src);
		const std::string expected = std::string("threw: player.ship.") + prop + " is read-only.";
		if (result != expected)  std::printf("    %s\n    gave: %s\n", src.c_str(), result.c_str());
		OO_CHECK_EQ(result, expected);
	}
}


// MARK: Slice 3: AI and script, escorts, roles, cargo, spawn, damage, removal, comms (bead oo-08plt)

// Whether src threw with the message expected (the message printed when not).
bool ThrewWith(const std::string &src, const std::string &message)
{
	std::string result = Eval(src);
	if (result != "threw: " + message)  std::printf("    %s\n    gave: %s\n", src.c_str(), result.c_str());
	return result == "threw: " + message;
}


OO_TEST(methodsAI)
{
	SetUp();
	OO_CHECK(Threw("ship.setScript()"));
	OO_CHECK(ThrewWith("player.ship.setScript('a.js')", "Ship.setScript: Not valid for player ship."));
	OO_CHECK(Threw("ship.setAI()"));
	OO_CHECK(ThrewWith("player.ship.setAI('nullAI.plist')", "Ship.setAI: Not valid for player ship."));
	OO_CHECK_EVAL("(ship.setAI('route1patrolAI.plist'), ship.AI)", "<no AI>");	// as the Objective-C natives answered (oo-lk92s)
	OO_CHECK(Threw("ship.switchAI()"));
	OO_CHECK(ThrewWith("player.ship.switchAI('nullAI.plist')", "Ship.switchAI: Not valid for player ship."));
	OO_CHECK_EVAL("(ship.switchAI('nullAI.plist'), ship.AI)", "<no AI>");	// as the Objective-C natives answered (oo-lk92s)
	OO_CHECK(ThrewWith("player.ship.exitAI()", "Ship.exitAI: Not valid for player ship."));
	OO_CHECK_EVAL("ship.exitAI()", "undefined");	// no suspended machines: a warning only
	OO_CHECK(Threw("ship.reactToAIMessage()"));
	OO_CHECK(ThrewWith("player.ship.reactToAIMessage('X')", "Ship.reactToAIMessage: Not valid for player ship."));
	OO_CHECK_EVAL("ship.reactToAIMessage('NOTHING_HERE')", "undefined");
	OO_CHECK(Threw("ship.sendAIMessage()"));
	OO_CHECK(ThrewWith("player.ship.sendAIMessage('X')", "Ship.sendAIMessage: Not valid for player ship."));
	OO_CHECK_EVAL("ship.sendAIMessage('NOTHING_HERE')", "undefined");
	OO_CHECK_EVAL("ship.AI", "<no AI>");	// as the Objective-C natives answered (oo-lk92s)
}


OO_TEST(methodsEscortsRolesEquipment)
{
	SetUp();
	OO_CHECK_EVAL("ship.deployEscorts()", "undefined");
	OO_CHECK_EVAL("ship.dockEscorts()", "undefined");
	OO_CHECK(Threw("ship.hasEquipmentProviding()"));
	OO_CHECK_EVAL("ship.hasEquipmentProviding('EQ_NONE_SUCH')", "false");
	OO_CHECK(Threw("ship.hasRole()"));
	OO_CHECK_EVAL("ship.hasRole('police')", "true");
	OO_CHECK_EVAL("ship.hasRole('pirate')", "false");
	OO_CHECK_EVAL("ship.fireECM()", "false");	// no ECM: a warning
	OO_CHECK_EVAL("ship.abandonShip()", "false");	// no escape pod
}


OO_TEST(methodsCargoAndSpawnArguments)
{
	SetUp();
	OO_CHECK(Threw("ship.ejectItem()"));
	OO_CHECK(Threw("ship.ejectSpecificItem()"));
	OO_CHECK(Threw("ship.spawn()"));
	OO_CHECK(Threw("ship.spawn('trader', 0)"));
	OO_CHECK(Threw("ship.spawn('trader', 65)"));
	OO_CHECK(Threw("ship.dumpCargo(0)"));
	OO_CHECK(Threw("ship.dumpCargo(65)"));
	sPlayerDocked = YES;
	OO_CHECK_EVAL("player.ship.dumpCargo()", "null");	// docked: a warning
	sPlayerDocked = NO;
	OO_CHECK(Threw("ship.addCargoEntity()"));
	OO_CHECK(Threw("ship.addCargoEntity(7)"));
	OO_CHECK_EVAL("(function () { try { return ship.addCargoEntity(other); } catch (e) { return 'refused'; } })()", "<evaluation failed>");	// as the Objective-C native answered (oo-lk92s)
	OO_CHECK(Threw("ship.dealEnergyDamage(5)"));
	OO_CHECK(Threw("ship.dealEnergyDamage(-5, 100)"));
	OO_CHECK(Threw("ship.dealEnergyDamage(5, -100)"));
	OO_CHECK(Threw("ship.dealEnergyDamage(5, 100, 'fast')"));
}


OO_TEST(methodsCommsAndLegacyActions)
{
	SetUp();
	OO_CHECK(Threw("ship.commsMessage()"));
	OO_CHECK(Threw("ship.commsMessage('hello', 5)"));
	OO_CHECK(Threw("ship.commsMessage('hello', null)"));
	OO_CHECK(Threw("ship.__runLegacyScriptActions(other)"));
	OO_CHECK(Threw("ship.__runLegacyScriptActions(other, 'not an array')"));
	Log();
	OO_CHECK_EVAL("ship.__runLegacyScriptActions(other, ['doNothing'])", "undefined");
	OO_CHECK_LOG("setScriptTarget (nil); setScriptTarget " + (sShip != nullptr ? sShip->getName() : std::optional<std::string>()).value_or("(nil)") + "; runUnsanitizedScriptActions (doNothing) 1 <ship \"" + (sShip != nullptr ? sShip->getName() : std::optional<std::string>()).value_or("(null)") + "\" legacy actions> Other");
}


OO_TEST(methodsRemoveAndExplode)
{
	SetUp();
	OO_CHECK(ThrewWith("player.ship.remove()", "Cannot remove() player's ship."));
	sPlayerDocked = YES;
	OO_CHECK(ThrewWith("player.ship.explode()", "Cannot explode() player's ship while docked."));
	sPlayerDocked = NO;

	// A ship still in a launch queue (docked) is only marked dead.
	PlainShip *queued = static_cast<PlainShip *>(oo::ToShip(oo::NewShipObject(oo::makeRef<PlainShip>(), "queued", oo::PList(oo::PList::Dict{ { "name", oo::PList(std::string("Queued")) } }))));
	if (queued != nullptr)  queued->setStatus(STATUS_DOCKED);
	ooscript::Context context = OOJSAcquireContext();
	ooscript::Value queuedValue = queued->jsValueInContext(context);
	ooscript::setProperty(context, OOJavaScriptEngine::sharedEngine()->globalObject(), "queued", &queuedValue);
	OOJSRelinquishContext(context);
	Log();
	OO_CHECK_EVAL("queued.remove(true)", "undefined");
	OO_CHECK((queued != nullptr ? queued->status() : OOEntityStatus{}) == STATUS_DEAD);
	OO_CHECK((queued != nullptr ? queued->shipScript() : (OOScript *)nullptr) == nil);	// suppressing the death event drops the script
	OO_CHECK_LOG("");
	if (queued != nullptr)  oo::ReleaseEntity(queued);
}


// MARK: Slice 4: equipment, missiles, bounty, cargo and crew, materials and shaders (bead oo-hqe5l)

// The test's game has no equipment types (no Resources), so the equipment natives see unknown keys.
OO_TEST(methodsEquipment)
{
	SetUp();
	OO_CHECK(Threw("ship.canAwardEquipment()"));
	OO_CHECK_EVAL("ship.canAwardEquipment('EQ_NONE_SUCH')", "false");
	OO_CHECK(Threw("ship.awardEquipment()"));
	OO_CHECK(Threw("ship.awardEquipment('EQ_NONE_SUCH')"));
	OO_CHECK(Threw("ship.removeEquipment()"));
	OO_CHECK(Threw("ship.removeEquipment('EQ_NONE_SUCH')"));
	OO_CHECK(Threw("ship.setEquipmentStatus('EQ_NONE_SUCH')"));
	OO_CHECK(Threw("ship.setEquipmentStatus('EQ_NONE_SUCH', 'EQUIPMENT_OK')"));
	OO_CHECK(Threw("ship.equipmentStatus()"));
	OO_CHECK_EVAL("ship.equipmentStatus('EQ_NONE_SUCH')", "EQUIPMENT_UNKNOWN");
	OO_CHECK_EVAL("JSON.stringify(ship.equipmentStatus('EQ_NONE_SUCH', true))", "{\"EQUIPMENT_UNKNOWN\":1}");
	OO_CHECK_EVAL("ship.restoreSubEntities()", "false");	// none to restore
}


OO_TEST(methodsMissilesAndStations)
{
	SetUp();
	OO_CHECK_EVAL("ship.selectNewMissile()", "threw: Native exception: Could not load any ship data.");	// as the Objective-C native answered (oo-lk92s)
	OO_CHECK_EVAL("ship.fireMissile()", "null");	// none aboard
	OO_CHECK_EVAL("ship.findNearestStation()", "null");	// none in the universe
}


OO_TEST(methodsBountyCargoCrew)
{
	SetUp();
	OO_CHECK_EVAL("(ship.setBounty(12, 'test'), ship.bounty)", "12");
	OO_CHECK(Threw("ship.setBounty(12)"));
	OO_CHECK(Threw("ship.setBounty(-1, 'test')"));
	OO_CHECK(Threw("ship.setCargo()"));
	OO_CHECK(Threw("ship.setCargo('food', 0)"));
	OO_CHECK_EVAL("ship.setCargo('food')", "false");	// the universe has no commodities
	OO_CHECK(Threw("ship.setCrew()"));
	// ship.setCrew(7) is not run here (oo-lk92s): the Objective-C native does not throw but takes the
	// number as an empty character definition, and making that character expands descriptions (its
	// random name), which ends this test's process, whose universe has none. The goldens cover it.
	OO_CHECK_EVAL("(ship.setCrew(null) + ' ' + ship.crew)", "true null");
	OO_CHECK(Threw("ship.setCargoType()"));
	OO_CHECK_EVAL("ship.setCargoType('SCARCE_GOODS')", "true");
	OO_CHECK_EVAL("ship.setCargoType('PIRATE_GOODS')", "true");
	OO_CHECK_EVAL("ship.setCargoType('NONSENSE_GOODS')", "false");
}


OO_TEST(methodsMaterials)
{
	SetUp();
	OO_CHECK_EVAL("JSON.stringify(ship.getMaterials())", "{}");	// no mesh
	OO_CHECK_EVAL("JSON.stringify(ship.getShaders())", "{}");
	OO_CHECK(Threw("ship.setMaterials()"));
	OO_CHECK(Threw("ship.setShaders()"));
	OO_CHECK_EVAL("ship.setMaterials(null)", "false");	// a warning
	OO_CHECK_EVAL("ship.setShaders(7)", "false");
	OO_CHECK_EVAL("ship.setMaterials({}, 7)", "false");	// no model to make a mesh of
}


// MARK: Slice 5: exit, escorts, defence targets, collision exceptions, wormholes, docking, course (bead oo-qzn25)

OO_TEST(methodsExitAndEscorts)
{
	SetUp();
	OO_CHECK(ThrewWith("player.ship.exitSystem()", "Ship.exitSystem: Not valid for player ship."));
	OO_CHECK(Threw("ship.exitSystem(-5)"));
	OO_CHECK(Threw("ship.exitSystem(300)"));
	OO_CHECK_EVAL("ship.updateEscortFormation()", "undefined");
	OO_CHECK(Threw("ship.offerToEscort()"));
	OO_CHECK(Threw("ship.offerToEscort(7)"));
	OO_CHECK_EVAL("ship.requestHelpFromGroup()", "undefined");	// no group
	OO_CHECK(Threw("ship.patrolReportIn()"));
	OO_CHECK_EVAL("ship.patrolReportIn(other)", "undefined");	// not a station: nothing
	OO_CHECK_EVAL("(ship.target = null, ship.markTargetForFines())", "false");	// no target
}


OO_TEST(methodsDefenseTargetsAndCollisionExceptions)
{
	SetUp();
	OO_CHECK(Threw("ship.addDefenseTarget()"));
	OO_CHECK(Threw("ship.addDefenseTarget(7)"));
	OO_CHECK(Threw("ship.removeDefenseTarget(null)"));
	OO_CHECK_EVAL("(ship.clearDefenseTargets(), ship.defenseTargets.length)", "0");
	OO_CHECK_EVAL("(ship.addDefenseTarget(other), ship.defenseTargets.length)", "1");
	OO_CHECK_EVAL("(ship.removeDefenseTarget(other), ship.defenseTargets.length)", "0");
	OO_CHECK_EVAL("(ship.addDefenseTarget(other), ship.clearDefenseTargets(), ship.defenseTargets.length)", "0");
	OO_CHECK(Threw("ship.addCollisionException()"));
	OO_CHECK(Threw("ship.removeCollisionException('other')"));
	OO_CHECK_EVAL("(ship.addCollisionException(other), ship.collisionExceptions.length + ' ' + other.collisionExceptions.length)", "1 1");
	OO_CHECK_EVAL("ship.collisionExceptions[0] === other && other.collisionExceptions[0] === ship", "true");
	OO_CHECK_EVAL("(ship.removeCollisionException(other), ship.collisionExceptions.length + ' ' + other.collisionExceptions.length)", "0 0");
}


OO_TEST(methodsWormholesDockingCourse)
{
	SetUp();
	OO_CHECK(ThrewWith("ship.enterWormhole()", "Cannot use this function while player's ship not entering witchspace."));
	OO_CHECK_EVAL("ship.notifyGroupOfWormhole()", "undefined");	// no group
	OO_CHECK_EVAL("ship.throwSpark()", "undefined");
	OO_CHECK_EVAL("ship.recallDockingInstructions()", "null");
	Log();
	OO_CHECK_EVAL("(ship.desiredRange = 250, ship.destination = [1, 2, 3], ship.checkCourseToDestination())", "null");
	OO_CHECK_LOG("hazardOnRoute 250 (1, 2, 3)");
	OO_CHECK_EVAL("ship.getSafeCourseToDestination()", "(10, 20, 30)");
	OO_CHECK_LOG("getSafeVector 250 (1, 2, 3)");
}


// MARK: Slice 6: AI behaviours, scanner, cargo adjustment, damage and threat assessment, statics (bead oo-ljuy1)

OO_TEST(methodsBehaviours)
{
	SetUp();
	for (const char *behaviour : { "performAttack", "performCollect", "performEscort", "performFaceDestination", "performFlyToRangeFromDestination", "performHold", "performIdle", "performIntercept", "performScriptedAI", "performScriptedAttackAI", "performTumble", "performStop" })
	{
		OO_CHECK_EVAL(std::string("ship.") + behaviour + "()", "undefined");
	}
	OO_CHECK_EVAL("(ship.performFlee(), ship.isFleeing)", "true");
	OO_CHECK_EVAL("(ship.performStop(), ship.isFleeing)", "false");
}


OO_TEST(methodsScannerAndCargo)
{
	SetUp();
	OO_CHECK_EVAL("JSON.stringify(ship.checkScanner())", "[]");	// nothing in the universe
	OO_CHECK_EVAL("JSON.stringify(ship.checkScanner(true))", "[]");
	OO_CHECK(Threw("ship.adjustCargo('food')"));
	OO_CHECK(Threw("ship.adjustCargo('food', {})"));
	OO_CHECK(ThrewWith("player.ship.adjustCargo('food', 1)", "ship.adjustCargo may only be used on NPC cargo carriers"));
	Log();
	OO_CHECK_EVAL("ship.adjustCargo('food', 2)", "true");
	OO_CHECK_LOG("getContainersOfCommodity food 2");
	OO_CHECK_EVAL("ship.adjustCargo('food', -1)", "false");	// none aboard
	OO_CHECK_EVAL("ship.adjustCargo('food', 0)", "true");
}


OO_TEST(methodsAssessments)
{
	SetUp();
	OO_CHECK_EVAL("ship.damageAssessment()", "1");	// missile pylons but no missiles
	OO_CHECK_EVAL("ship.threatAssessment()", "3.850000012665987");	// as the Objective-C native answered (oo-lk92s)
	OO_CHECK_EVAL("ship.threatAssessment(true)", "1.650000024586916");	// as the Objective-C native answered (oo-lk92s)
	OO_CHECK_EVAL("player.ship.threatAssessment(true)", "0.1");	// as the Objective-C native answered (oo-lk92s)
	sFleeingStatus = PLAYER_FLEEING_CARGO;
	OO_CHECK_EVAL("player.ship.threatAssessment()", "0.4199999958276749");	// as the Objective-C native answered (oo-lk92s)
	sFleeingStatus = PLAYER_FLEEING_NONE;
}


OO_TEST(staticMethods)
{
	SetUp();
	Log();
	OO_CHECK_EVAL("Ship.roleIsInCategory('trader', 'oolite-trader')", "true");
	OO_CHECK_LOG("role trader isInCategory oolite-trader");
	OO_CHECK_EVAL("Ship.roleIsInCategory('pirate', 'oolite-trader')", "false");
	OO_CHECK_LOG("role pirate isInCategory oolite-trader");
	OO_CHECK_EVAL("Ship.roleIsInCategory(null, 'oolite-trader')", "false");	// matched nothing, without asking
	OO_CHECK_LOG("");
	OO_CHECK(Threw("Ship.roleIsInCategory('trader')"));
	OO_CHECK(Threw("Ship.keysForRole()"));
	OO_CHECK(Threw("Ship.shipDataForKey()"));
	OO_CHECK(Threw("Ship.setShipDataForKey('k')"));
	OO_CHECK_EVAL("JSON.stringify(Ship.keys())", "[]");
	OO_CHECK_EVAL("JSON.stringify(Ship.roles())", "[]");
	OO_CHECK_EVAL("Ship.keysForRole('trader')", "null");
	OO_CHECK_EVAL("Ship.shipDataForKey('nothing')", "null");
	OO_CHECK_EVAL("Ship.shipDataForKey(null)", "null");
	OO_CHECK_EVAL("Ship.setShipDataForKey('testship', { name: 'Test' })", "true");
	OO_CHECK_EVAL("Ship.shipDataForKey('testship').name", "Test");
}


OO_TEST(cleanUp)
{
	stdfs::current_path(stdfs::temp_directory_path());
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
	OO_CHECK(true);
}


OO_TEST_MAIN()
