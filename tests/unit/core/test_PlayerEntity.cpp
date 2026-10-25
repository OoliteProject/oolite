/*	test_PlayerEntity.mm
	Unit tests for PlayerEntity (src/Core/Entities/PlayerEntity.h), the player's ship: slice 1 of
	its slice plan (docs/phases/3-slices/PlayerEntity.md, bead oo-jx5np), the class shell, which
	moves the player's state into PlayerEntity and keeps the Objective-C PlayerEntity as its
	facade, a subclass of the ship's (proposed ADR-0056, amendments oo-bj8, oo-60fwo and
	oo-jx5np).

	Like the ship's, the player's object needs the game graph, so the test links the whole game but
	main (['*']) and uses a Universe that was never initialised and an empty JavaScript context for
	the events the ship sends its scripts. The player is made in two steps, as the game makes it:
	-init (+sharedPlayer) early in start-up, before there is ship data, and -deferredInit once there
	is. Setting the player up from shipdata, the session and the controls (slice 5 and
	PlayerEntityControls) need the game's data, so a subclass stands in for those three and only
	counts; the cases test the slice's own units: sharedPlayer(), the player made (the ship made
	the player's way, and the only player), deferredInit() (the ship's initialiser sent again over
	the same object, and the player's own defaults), and the object's -dealloc (it releases what the
	player held). The expectations were written against the Objective-C API and run on the
	unconverted class first.
	Since bead oo-9ht.177 deleted the Objective-C player (ADR-0056 amendment oo-9ht.177) the player
	is C++, made as the game makes it (oo::makeRef, its object the ship's facade, oo::NewEntityFacade),
	and the stand-ins are C++ subclasses overriding the members the Objective-C subclasses
	overrode; the test reads and sets the members directly. The case after those pins the crossing:
	the player's object is a ship whose C++ part is the player, and it answers the player's
	selectors called by name.
	Run: bash tools/check-core-tests.sh test_PlayerEntity
*/

#include "PlayerEntity.h"
#include "WormholeEntity.h"
#include "MyOpenGLView.h"
#include "OOConstToString.h"
#include "OODescription.h"
#include "Universe.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityKeyMapper.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityLoadSave.h"
#include "PlayerEntitySound.h"
#include "PlayerEntityStickMapper.h"
#include "OOJoystickManager.h"
#include "OOCallByName.h"	// oo::EntityRespondsToName / oo::CallEntityByName (bead oo-9ht.39.7.3)

#include "oo_test.hpp"

#include <cmath>
#include <string>


// The player's data members are private since bead oo-4yscj (they were @private in Objective-C):
// the test reaches each one it reads or sets through this friend, one accessor per member
// answering a reference, so every check reads and writes exactly what it did.
#define OO_PLAYER_MEMBER(name)	static auto &name(PlayerEntity *player)	{ return player->name; }

// A one-bit member has no reference: its accessor answers a proxy that reads as the member's value
// and assigns through to it.
template <class Get, class Set>
struct PlayerBitMember
{
	Get get;
	Set set;
	operator unsigned() const						{ return get(); }
	PlayerBitMember &operator=(unsigned value)		{ set(value); return *this; }
};
template <class Get, class Set>
PlayerBitMember<Get, Set> MakePlayerBitMember(Get get, Set set)	{ return { get, set }; }
#define OO_PLAYER_BIT(name)	static auto name(PlayerEntity *player)	{ return MakePlayerBitMember([player]() -> unsigned { return player->name; }, [player](unsigned value) { player->name = value; }); }

struct PlayerEntityTestAccess
{
	OO_PLAYER_MEMBER(ANA_mode)
	OO_PLAYER_MEMBER(_missionBackgroundSpecial)
	OO_PLAYER_MEMBER(aftViewOffset)
	OO_PLAYER_MEMBER(alertFlags)
	OO_PLAYER_MEMBER(cdrDetailArray)
	OO_PLAYER_MEMBER(chart_centre_coordinates)
	OO_PLAYER_MEMBER(chart_focus_coordinates)
	OO_PLAYER_MEMBER(chart_zoom)
	OO_PLAYER_MEMBER(compassTarget)
	OO_PLAYER_MEMBER(contracts)
	OO_PLAYER_MEMBER(credits)
	OO_PLAYER_MEMBER(current_cargo)
	OO_PLAYER_MEMBER(cursor_coordinates)
	OO_PLAYER_MEMBER(customDialSettings)
	OO_PLAYER_MEMBER(customViewOffset)
	OO_PLAYER_MEMBER(custom_chart_centre_coordinates)
	OO_PLAYER_MEMBER(custom_chart_zoom)
	OO_PLAYER_MEMBER(dockingClearanceStatus)
	OO_PLAYER_MEMBER(dockingReport)
	OO_PLAYER_MEMBER(eqScripts)
	OO_PLAYER_MEMBER(extraMissionKeys)
	OO_PLAYER_MEMBER(fleeing_status)
	OO_PLAYER_MEMBER(forwardViewOffset)
	OO_PLAYER_MEMBER(galaxy_coordinates)
	OO_PLAYER_MEMBER(galaxy_number)
	OO_PLAYER_MEMBER(gui_screen)
	OO_PLAYER_MEMBER(hud)
	OO_PLAYER_MEMBER(hyperspeedFactor)
	OO_PLAYER_MEMBER(info_system_id)
	OO_PLAYER_MEMBER(isSpeechOn)
	OO_PLAYER_MEMBER(legalStatusValue)
	OO_PLAYER_MEMBER(market_rnd)
	OO_PLAYER_MEMBER(maxFieldOfView)
	OO_PLAYER_MEMBER(max_passengers)
	OO_PLAYER_MEMBER(missile_entity)
	OO_PLAYER_MEMBER(mission_variables)
	OO_PLAYER_MEMBER(multiFunctionDisplaySettings)
	OO_PLAYER_MEMBER(multiFunctionDisplayText)
	OO_PLAYER_MEMBER(passengers)
	OO_PLAYER_MEMBER(pitch_delta)
	OO_PLAYER_MEMBER(planetSearchString)
	OO_PLAYER_MEMBER(portViewOffset)
	OO_PLAYER_MEMBER(reputation)
	OO_PLAYER_MEMBER(roll_delta)
	OO_PLAYER_MEMBER(save_path)
	OO_PLAYER_MEMBER(scenarioKey)
	OO_PLAYER_MEMBER(ship_clock)
	OO_PLAYER_MEMBER(ship_kills)
	OO_PLAYER_MEMBER(ship_trade_in_factor)
	OO_PLAYER_MEMBER(shipyard_record)
	OO_PLAYER_MEMBER(system_id)
	OO_PLAYER_MEMBER(target_memory_index)
	OO_PLAYER_MEMBER(target_system_id)
	OO_PLAYER_MEMBER(worldScripts)
	OO_PLAYER_MEMBER(wormhole)
	OO_PLAYER_MEMBER(yaw_delta)
	OO_PLAYER_BIT(afterburner_engaged)
	OO_PLAYER_BIT(autopilot_engaged)
	OO_PLAYER_BIT(galactic_witchjump)
	OO_PLAYER_BIT(hyperspeed_engaged)
	OO_PLAYER_BIT(ident_engaged)
	OO_PLAYER_BIT(scoopsActive)
	OO_PLAYER_BIT(suppressTargetLostFlag)
	OO_PLAYER_BIT(travelling_at_hyperspeed)
	OO_PLAYER_BIT(using_mining_laser)
};

#undef OO_PLAYER_MEMBER
#undef OO_PLAYER_BIT



// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;
extern ooscript::Context gOOJSMainThreadContext;


namespace {

// What the stand-ins were sent.
int sShipSetUps = 0;
oo::PList sShipSetUpDict;
int sPlayerSetUps = 0;
BOOL sPlayerSetUpStopOnError = YES;
int sInitControls = 0;

}	// namespace


// A player whose set-up from shipdata, session set-up and controls only count (slice 5's units and
// PlayerEntityControls', which need the game's data).
class TestPlayer : public PlayerEntity
{
public:
	using PlayerEntity::setUpAndConfirmOK;

	bool setUpShipFromDictionary(const oo::PList &dict) override
	{
		sShipSetUps++;
		sShipSetUpDict = dict;
		return YES;
	}


	bool setUpAndConfirmOK(bool stopOnError) override
	{
		sPlayerSetUps++;
		sPlayerSetUpStopOnError = stopOnError;
		return YES;
	}


	void initControls() override
	{
		sInitControls++;
	}
};


// A ship that stands in for a missile on a pylon.
class TestMissile : public ShipEntity	// C++ since bead oo-9ht.144 deleted the Objective-C ship
{
public:
	bool setUpShipFromDictionary(const oo::PList &dict) override	{ (void)dict; return YES; }
};


namespace {

void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = new Universe();	// never released
	}
	gSharedUniverse = universe;
	gOOPlayer = nullptr;	// making the player expects to make the only one
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
	sShipSetUps = 0;
	sShipSetUpDict = oo::PList();
	sPlayerSetUps = 0;
	sPlayerSetUpStopOnError = YES;
	sInitControls = 0;
}


#ifndef NDEBUG
// deferredInit() sends the ship's initialiser, and so the root's -init, a second time, which counts
// the entity again, as it did.
void UncountSecondInit(Entity *entity)
{
	gLiveEntityCount--;
	gTotalEntityMemory -= oo::EntityObjectSize(entity);	// its object's size (bead oo-dpyk8)
}
#endif


// A player made as the game makes one (PlayerEntity::newPlayerObject()): the C++ player, owned by
// its Objective-C object, the ship's facade, which the caller releases (+1).
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


void Release(PlayerEntity *player)
{
	oo::ReleaseEntity(player);
}

}	// namespace


// The player made: the ship made the player's way (no initialiser but the root's), not set up from
// shipdata, not yet the player, and not yet the shared player.
OO_TEST(initIsTheShipMadeThePlayersWay)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = NewTestPlayer<TestPlayer>();
		OO_CHECK(player != nullptr);
		OO_CHECK(sShipSetUps == 0 && sPlayerSetUps == 0 && sInitControls == 0);
		OO_CHECK(!player->getIsShip() && !player->getIsPlayer());
		OO_CHECK(player->status() == STATUS_COCKPIT_DISPLAY);
		OO_CHECK(player->shipDataKey() == std::nullopt);
		OO_CHECK(player->temperature() == 0 && player->weaponRechargeRate() == 0);
		OO_CHECK(PlayerEntityTestAccess::maxFieldOfView(player) == 0);
		OO_CHECK(gOOPlayer == nullptr);
		Release(player);
	}
}


// sharedPlayer(): made once, a PlayerEntity, and kept.
OO_TEST(sharedPlayer)
{
	PlayerEntity *player = nullptr;
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		player = PlayerEntity::sharedPlayer();
		OO_CHECK(player != nullptr && typeid(*player) == typeid(PlayerEntity));
		OO_CHECK(gOOPlayer == player);
		OO_CHECK(PlayerEntity::sharedPlayer() == player);
		OO_CHECK(!player->getIsPlayer() && player->status() == STATUS_COCKPIT_DISPLAY);
	}
	gOOPlayer = nullptr;
	Release(player);
}


// deferredInit(): the ship's initialiser sent again with the player's ship key and an empty
// definition, which keeps the object (and its C++ part) and runs the ship's body over it; then
// the player's own defaults, the session set-up, and the controls.
OO_TEST(deferredInit)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = NewTestPlayer<TestPlayer>();
		gOOPlayer = player;
		Entity *asEntity = player;
		void *part = asEntity;
		player->setFuel(5);
		PlayerEntityTestAccess::save_path(player) = std::string("some.oolite-save");

		player->deferredInit();
		OO_CHECK((void *)asEntity == part);
		OO_CHECK(sShipSetUps == 1 && sShipSetUpDict.isDict() && sShipSetUpDict.getIf<oo::PList::Dict>()->empty());
		OO_CHECK(player->shipDataKey() == std::optional<std::string>(std::string(PLAYER_SHIP_DESC)));
		OO_CHECK(player->getIsShip() && player->getIsPlayer());
		OO_CHECK(player->status() == STATUS_START_GAME);
		OO_CHECK(player->temperature() == SHIP_MIN_CABIN_TEMP && player->weaponRechargeRate() == 6.0f);
		OO_CHECK(player->getFuel() == 5);	// what the bodies do not set stays
		OO_CHECK(std::fabs(PlayerEntityTestAccess::maxFieldOfView(player) - MAX_FOV) < 1e-6);
		OO_CHECK(player->getCompassMode() == COMPASS_MODE_BASIC);
		OO_CHECK(!PlayerEntityTestAccess::scoopsActive(player) && PlayerEntityTestAccess::target_memory_index(player) == 0);
		OO_CHECK(!PlayerEntityTestAccess::save_path(player).has_value());
		for (int i = 0; i < PLAYER_MAX_MISSILES; i++)  OO_CHECK(PlayerEntityTestAccess::missile_entity(player)[i] == nil);
		OO_CHECK(sPlayerSetUps == 1 && sPlayerSetUpStopOnError == NO);
		OO_CHECK(sInitControls == 1);

		gOOPlayer = nullptr;
#ifndef NDEBUG
		UncountSecondInit(asEntity);
#endif
		Release(player);
	}
}


// The object's -dealloc releases what the player held (here, a missile on a pylon), and the ship's
// -dealloc runs after it.
OO_TEST(deallocReleasesWhatThePlayerHeld)
{
	// The missile's object (+1, as +alloc/-init's was):  would autorelease it again
	// (bead oo-9ht.144, where the missile became a C++ ship).
	Entity *missile = nil;
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		missile = oo::NewShipObject(oo::makeRef<TestMissile>(), "missile", oo::PList());
		TestPlayer *player = NewTestPlayer<TestPlayer>();
		PlayerEntityTestAccess::missile_entity(player)[2] = oo::EntityHold::adopt(oo::RetainEntity(missile));	// held by oo::ObjCRef since bead oo-5q11i, oo::EntityHold since bead oo-xn1j1
		OO_CHECK(missile->retainCount() == 2);
		OO_CHECK(PlayerEntityTestAccess::missile_entity(player)[2] == missile);
		Release(player);
	}
	OO_CHECK(missile->retainCount() == 1);
	oo::ReleaseEntity(missile);
}


// The crossing (bead oo-9ht.177): the player's object is a ship whose C++ part is the player; the
// player answers the player's selectors called by name (ADR-0056 amendment oo-9ht.177), which a
// ship does not (the by-name table's answer since bead oo-9ht.39.7.3, the object's until then).
OO_TEST(playerObjectIsAShipWhosePartIsThePlayer)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = NewTestPlayer<TestPlayer>();
		Entity *object = player;	// the drawable's facade since bead oo-9ht.144 (the ship's until then)
		OO_CHECK(object != nil && oo::ToShip(object) != nullptr);	// a ship's object (-isKindOfClass:[ShipEntity class] until bead oo-9ht.144)
		OO_CHECK(object == player);
		OO_CHECK(dynamic_cast<PlayerEntity *>(object) == player);
		OO_CHECK(oo::EntityRespondsToName(player, "commanderName_string"));
		OO_CHECK(oo::EntityRespondsToName(player, "credits_number"));
		OO_CHECK(!oo::EntityRespondsToName(player, "noSuchPlayerSelector"));

		::ShipEntity *ship = static_cast<TestMissile *>(oo::ToShip(oo::NewShipObject(oo::makeRef<TestMissile>(), "missile", oo::PList())));
		OO_CHECK(ship != nil && !oo::EntityRespondsToName(ship, "commanderName_string"));
		oo::ReleaseEntity(ship);
		Release(player);
	}
}


// Every member starts zeroed, as the runtime zeroed the ivars.
OO_TEST(membersStartZeroed)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = NewTestPlayer<TestPlayer>();
		PlayerEntity *part = player;
		OO_CHECK(PlayerEntityTestAccess::hud(part) == nil && PlayerEntityTestAccess::compassTarget(part).get() == nullptr && PlayerEntityTestAccess::wormhole(part) == nil);
		OO_CHECK(PlayerEntityTestAccess::system_id(part) == 0 && PlayerEntityTestAccess::ship_clock(part) == 0 && PlayerEntityTestAccess::scoopsActive(part) == NO);
		for (int i = 0; i < PLAYER_MAX_MISSILES; i++)  OO_CHECK(PlayerEntityTestAccess::missile_entity(part)[i] == nil);
		OO_CHECK(!PlayerEntityTestAccess::save_path(part).has_value() && PlayerEntityTestAccess::worldScripts(part).empty());
		Release(player);
	}
}


// --- Slice 2: cargo pods, commodity data and credits, galaxy and chart coordinates, the current and
// previous system (bead oo-m4tfc) ------------------------------------------------------------------

namespace {

// A player made the way sharedPlayer() makes one, but not the shared player (no ship data); its
// object is autoreleased.
TestPlayer *MakePlayer()
{
	gOOPlayer = nullptr;
	TestPlayer *player = NewTestPlayer<TestPlayer>();
	oo::AutoreleaseEntity(player);
	return player;
}

bool Near(NSPoint a, NSPoint b)	{ return std::fabs(a.x - b.x) < 1e-4 && std::fabs(a.y - b.y) < 1e-4; }

}	// namespace


// The player's ship can't be renamed; the base mass falls back to the Cobra III's while the ship has
// none.
OO_TEST(slice2NameAndBaseMass)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		const std::optional<std::string> before = player->getName();
		player->setName(std::string("Renamed"));
		OO_CHECK(player->getName() == before);
		OO_CHECK(player->baseMass() == 185580.0f);
	}
}


// The plain accessors read and write the members.
OO_TEST(slice2Accessors)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		OO_CHECK(player->getShipCommodityData() == nil);
		PlayerEntityTestAccess::credits(part) = 1234;
		OO_CHECK(player->deciCredits() == 1234);
		player->setRandom_factor(77);
		OO_CHECK(player->random_factor() == 77 && PlayerEntityTestAccess::market_rnd(part) == 77);
		PlayerEntityTestAccess::galaxy_number(part) = 3;
		OO_CHECK(player->galaxyNumber() == 3);
		player->setGalaxyCoordinates(NSMakePoint(12.5, 99.0));
		OO_CHECK(Near(player->getGalaxy_coordinates(), NSMakePoint(12.5, 99.0)));
		PlayerEntityTestAccess::cursor_coordinates(part) = NSMakePoint(4, 5);
		PlayerEntityTestAccess::chart_centre_coordinates(part) = NSMakePoint(6, 7);
		OO_CHECK(Near(player->getCursor_coordinates(), NSMakePoint(4, 5)) && Near(player->getChart_centre_coordinates(), NSMakePoint(6, 7)));
		player->setCustomChartZoom(2.5);
		OO_CHECK(player->getCustom_chart_zoom() == 2.5);
		player->setCustomChartCentre(NSMakePoint(30, 40));
		OO_CHECK(Near(player->getCustom_chart_centre_coordinates(), NSMakePoint(30, 40)));
		PlayerEntityTestAccess::ANA_mode(part) = OPTIMIZED_BY_TIME;
		OO_CHECK(player->ANAMode() == OPTIMIZED_BY_TIME);
		PlayerEntityTestAccess::system_id(part) = 42;
		OO_CHECK(player->systemID() == 42);
		player->setPreviousSystemID(17);
		OO_CHECK(player->previousSystemID() == 17);
	}
}


// The chart's zoom and centre follow a mission screen's chart background.
OO_TEST(slice2ChartZoomAndCentre)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::chart_zoom(part) = 1.0;
		PlayerEntityTestAccess::custom_chart_zoom(part) = 3.0;
		PlayerEntityTestAccess::galaxy_coordinates(part) = NSMakePoint(20, 30);
		PlayerEntityTestAccess::custom_chart_centre_coordinates(part) = NSMakePoint(50, 60);
		PlayerEntityTestAccess::chart_centre_coordinates(part) = NSMakePoint(100, 110);
		PlayerEntityTestAccess::chart_focus_coordinates(part) = NSMakePoint(100, 110);

		PlayerEntityTestAccess::_missionBackgroundSpecial(part) = GUI_BACKGROUND_SPECIAL_NONE;
		OO_CHECK(player->getChart_zoom() == 1.0);
		OO_CHECK(Near(player->adjusted_chart_centre(), NSMakePoint(100, 110)));
		PlayerEntityTestAccess::_missionBackgroundSpecial(part) = GUI_BACKGROUND_SPECIAL_SHORT;
		OO_CHECK(player->getChart_zoom() == 1.0);
		OO_CHECK(Near(player->adjusted_chart_centre(), NSMakePoint(20, 30)));
		PlayerEntityTestAccess::_missionBackgroundSpecial(part) = GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST;
		OO_CHECK(player->getChart_zoom() == (OOScalar)CHART_MAX_ZOOM);
		OO_CHECK(Near(player->adjusted_chart_centre(), NSMakePoint(128, 128)));
		PlayerEntityTestAccess::_missionBackgroundSpecial(part) = GUI_BACKGROUND_SPECIAL_CUSTOM;
		OO_CHECK(player->getChart_zoom() == 3.0);
		OO_CHECK(Near(player->adjusted_chart_centre(), NSMakePoint(50, 60)));
	}
}


// Unloading a commodity with no pods in the hold takes it from the manifest (here, none).
OO_TEST(slice2UnloadWithNoPods)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		player->unloadCargoPodsForType("food", 3);
		player->unloadAllCargoPodsForType("food", nullptr);
		OO_CHECK(player->cargo.empty());
	}
}

// --- Slice 3: target, next-hop and info systems, the wormhole, the commander data dictionary
// (bead oo-7pa3t) ---------------------------------------------------------------------------------

// The target and info systems; with no advanced navigational array the next hop is the target.
OO_TEST(slice3TargetAndInfoSystems)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::system_id(part) = 7;
		PlayerEntityTestAccess::target_system_id(part) = 9;
		PlayerEntityTestAccess::info_system_id(part) = 11;
		PlayerEntityTestAccess::ANA_mode(part) = OPTIMIZED_BY_JUMPS;
		OO_CHECK(player->targetSystemID() == 9);
		OO_CHECK(player->nextHopTargetSystemID() == 9);
		OO_CHECK(player->infoSystemID() == 11);
		player->setInfoSystemID(11, YES);	// the same system: nothing changes
		OO_CHECK(player->infoSystemID() == 11);
	}
}


// The wormhole is retained while the player holds it, and released when replaced.
OO_TEST(slice3Wormhole)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		OO_CHECK(player->getWormhole() == nil);
		// A C++ wormhole since bead oo-9ht.112: the player retains its Objective-C object.
		oo::Ref<WormholeEntity> holeRef = oo::makeRef<WormholeEntity>();
		Entity *object = oo::RetainEntity(oo::MadeEntity(holeRef));
		WormholeEntity *hole = holeRef.get();
		NSUInteger count = object->retainCount();
		player->setWormhole(hole);
		OO_CHECK(player->getWormhole() == hole && object->retainCount() == count + 1);
		player->setWormhole(nullptr);
		OO_CHECK(player->getWormhole() == nullptr && object->retainCount() == count);
		oo::ReleaseEntity(object);
	}
}

// --- Slice 4: setting the commander data from a dictionary (bead oo-qvnwb) ---------------------

// The multi-function displays and dials are reset first; a dictionary without the required keys
// is refused.
OO_TEST(slice4RefusesADictionaryWithoutTheRequiredKeys)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::multiFunctionDisplayText(part)["mfd"] = "text";
		PlayerEntityTestAccess::multiFunctionDisplaySettings(part).push_back(std::string("mfd"));
		PlayerEntityTestAccess::customDialSettings(part)["dial"] = oo::PList(1);
		OO_CHECK(!player->setCommanderDataFromDictionary(oo::PList(oo::PList::Dict{})));
		OO_CHECK(PlayerEntityTestAccess::multiFunctionDisplayText(part).empty() && PlayerEntityTestAccess::multiFunctionDisplaySettings(part).empty() && PlayerEntityTestAccess::customDialSettings(part).empty());
		OO_CHECK(!player->setCommanderDataFromDictionary(oo::PList(oo::PList::Dict{ { "ship_desc", oo::PList(std::string("cobra3-player")) } })));
	}
}

// --- Slice 5: set-up and start-up, ship set-up from the dictionary, the session, warning about
// hostiles (bead oo-mmcfq) -----------------------------------------------------------------------

// The player always belongs to the current session, and collides only in flight.
OO_TEST(slice5SessionAndCollisions)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		OO_CHECK(player->sessionID() == (UNIVERSE != nullptr ? UNIVERSE->sessionID() : 0));
		player->setStatus(STATUS_IN_FLIGHT);
		OO_CHECK(player->canCollide());
		player->setStatus(STATUS_DOCKED);
		OO_CHECK(!player->canCollide());
		player->setStatus(STATUS_DEAD);
		OO_CHECK(!player->canCollide());
		player->setStatus(STATUS_EXITING_WITCHSPACE);
		OO_CHECK(player->canCollide());
	}
}

// --- Slice 6: sun glare, the atmosphere, update: (bead oo-vzjco) --------------------------------

// The player is always the nearest entity and may always be added; outside an atmosphere the
// fraction inside it is zero.
OO_TEST(slice6NearestValidAndAtmosphere)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		OO_CHECK(player->compareZeroDistance(player) == OOOrderedDescending);
		OO_CHECK(player->validForAddToUniverse());
		OO_CHECK(player->insideAtmosphereFraction() == 0.0f);
		OO_CHECK(player->lookingAtSunWithThresholdAngleCos(0.5f) == 0.0f);	// no sun
	}
}

// --- Slice 7: the bookkeeping tick, movement flags (bead oo-5c466) ------------------------------

// The movement flags compare the position and orientation with the last frame's, which they then
// become.
OO_TEST(slice7MovementFlags)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		Entity *entity = player;
		entity->position = make_HPvector(1, 2, 3);
		entity->lastPosition = kZeroHPVector;
		entity->orientation = kIdentityQuaternion;
		entity->lastOrientation = kIdentityQuaternion;
		player->updateMovementFlags();
		OO_CHECK(entity->hasMoved && !entity->hasRotated);
		OO_CHECK(HPvector_equal(entity->lastPosition, entity->position));
		player->updateMovementFlags();
		OO_CHECK(!entity->hasMoved && !entity->hasRotated);
	}
}

// --- Slice 8: alert conditions, mass lock, fuel scoops, clocks, script and trumble ticks, the
// autopilot and docking requests (bead oo-ijf0s) ---------------------------------------------------

// The flight limits also set the player's control rates; without the autopilot engaged or a
// station, disengaging and cancelling a docking request change nothing.
OO_TEST(slice8FlightLimitsAndAutopilot)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		player->setMaxFlightPitch(1.5f);
		player->setMaxFlightRoll(2.0f);
		player->setMaxFlightYaw(0.5f);
		OO_CHECK(player->max_flight_pitch == 1.5f && PlayerEntityTestAccess::pitch_delta(part) == 3.0f);
		OO_CHECK(player->max_flight_roll == 2.0f && PlayerEntityTestAccess::roll_delta(part) == 4.0f);
		OO_CHECK(player->max_flight_yaw == 0.5f && PlayerEntityTestAccess::yaw_delta(part) == 1.0f);
		player->setStatus(STATUS_IN_FLIGHT);
		player->disengageAutopilot();
		OO_CHECK(!PlayerEntityTestAccess::autopilot_engaged(part) && player->status() == STATUS_IN_FLIGHT);
		player->cancelDockingRequest(nullptr);
		OO_CHECK(player->status() == STATUS_IN_FLIGHT);
	}
}

// --- Slice 9: the autopilot AI, hyperspeed, the per-status updates, game over, targeting
// (bead oo-qyjcv) ----------------------------------------------------------------------------------

// The injector and hyperspeed flags and the hyperspeed factor read the members.
OO_TEST(slice9HyperspeedFlags)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		OO_CHECK(!player->injectorsEngaged() && !player->hyperspeedEngaged());
		PlayerEntityTestAccess::afterburner_engaged(part) = YES;
		PlayerEntityTestAccess::hyperspeed_engaged(part) = YES;
		OO_CHECK(player->injectorsEngaged() && player->hyperspeedEngaged());
#if OO_VARIABLE_TORUS_SPEED
		PlayerEntityTestAccess::hyperspeedFactor(part) = 4.5f;
		OO_CHECK(player->getHyperspeedFactor() == 4.5f);
#endif
	}
}

// --- Slice 10: attitude, view matrices and viewpoints, drawing, mass lock, the docked station, the
// HUD and its custom dials, shield levels (bead oo-9u9w6) ----------------------------------------

// The normal orientation is the orientation with w negated, both ways; the flags and levels read and
// write the members; the shield level is clamped to its maximum.
OO_TEST(slice10OrientationFlagsAndShields)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		Quaternion q = make_quaternion(0.5, 0.5, 0.5, 0.5);
		player->setNormalOrientation(q);
		Quaternion n = player->normalOrientation();
		OO_CHECK(n.w == q.w && n.x == q.x && n.y == q.y && n.z == q.z);
		OO_CHECK(player->getOrientation().w == -q.w);
		player->setOcclusionLevel(0.75f);
		OO_CHECK(player->occlusionLevel() == 0.75f);
		player->setShowDemoShips(YES);
		OO_CHECK(player->getShowDemoShips());
		PlayerEntityTestAccess::travelling_at_hyperspeed(part) = YES;
		OO_CHECK(player->atHyperspeed());
		PlayerEntityTestAccess::alertFlags(part) = ALERT_FLAG_MASS_LOCK;
		OO_CHECK(player->massLocked());
		PlayerEntityTestAccess::alertFlags(part) = 0;
		OO_CHECK(!player->massLocked());
		OO_CHECK(!player->getMassLockable());
		player->setMaxForwardShieldLevel(100.0f);
		OO_CHECK(player->maxForwardShieldLevel() == 100.0f);
		player->setForwardShieldLevel(250.0f);
		OO_CHECK(player->forwardShieldLevel() == 100.0f);
		player->setForwardShieldLevel(-5.0f);
		OO_CHECK(player->forwardShieldLevel() == 0.0f);
	}
}


// The roll and speed dials are fractions of the maxima, clamped.
OO_TEST(slice10Dials)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		player->max_flight_roll = 2.0f;
		player->flightRoll = 1.0f;
		OO_CHECK(player->dialRoll() == 0.5f);
		player->flightRoll = -5.0f;
		OO_CHECK(player->dialRoll() == -1.0f);
		player->maxFlightSpeed = 100.0f;
		player->flightSpeed = 250.0f;
		OO_CHECK(player->dialSpeed() == 1.0f);
		player->flightSpeed = 25.0f;
		OO_CHECK(player->dialSpeed() == 0.25f);
	}
}

// --- Slice 11: the dials, fuel leak, the comm log, player roles, system memory, the compass target
// (bead oo-zxg1h) ---------------------------------------------------------------------------------

// The clock, its adjustment, the rescue time and the fuel leak (never negative) read and write the
// members; the number of player roles grows with the kills.
OO_TEST(slice11ClockFuelLeakAndRoles)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::ship_clock(part) = 1000.0;
		OO_CHECK(player->clockTime() == 1000.0 && !player->clockAdjusting());
		player->addToAdjustTime(60.0);
		OO_CHECK(player->clockAdjusting() && player->clockTimeAdjusted() == 1060.0);
		player->setEscapePodRescueTime(42.0);
		OO_CHECK(player->escapePodRescueTime() == 42.0);
		player->setFuelLeakRate(-1.0f);
		OO_CHECK(player->fuelLeakRate() == 0.0f);
		player->setFuelLeakRate(3.0f);
		OO_CHECK(player->fuelLeakRate() == 3.0f);
		PlayerEntityTestAccess::ship_kills(part) = 0;
		OO_CHECK(player->maxPlayerRoles() == 8);
		PlayerEntityTestAccess::ship_kills(part) = 128;
		OO_CHECK(player->maxPlayerRoles() == 16);
		PlayerEntityTestAccess::ship_kills(part) = 6400;
		OO_CHECK(player->maxPlayerRoles() == 32);
	}
}


// The missile count counts the occupied pylons up to the ship's maximum.
OO_TEST(slice11CountMissiles)
{
	TestMissile *missile = nil;
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		missile = static_cast<TestMissile *>(oo::ToShip(oo::NewShipObject(oo::makeRef<TestMissile>(), "missile", oo::PList())));
		TestPlayer *player = MakePlayer();
		player->max_missiles = 4;
		OO_CHECK(player->countMissiles() == 0);
		PlayerEntityTestAccess::missile_entity(player)[1] = oo::EntityHold::adopt(oo::RetainEntity(missile));	// held by oo::ObjCRef since bead oo-5q11i, oo::EntityHold since bead oo-xn1j1
		PlayerEntityTestAccess::missile_entity(player)[3] = oo::EntityHold::adopt(oo::RetainEntity(missile));	// held by oo::ObjCRef since bead oo-5q11i, oo::EntityHold since bead oo-xn1j1
		OO_CHECK(player->countMissiles() == 2);
		player->max_missiles = 2;
		OO_CHECK(player->countMissiles() == 1);
	}
	if (missile != nullptr)  oo::ReleaseEntity(missile);
}

// --- Slice 12: compass mode, missiles and pylons, special cargo, the multi-function displays, alert
// flags (bead oo-rqcfz) ---------------------------------------------------------------------------

// The compass mode, the ident flag, the maximum missiles and the alert flags read and write the
// members.
OO_TEST(slice12CompassIdentAndAlertFlags)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		player->setCompassMode(COMPASS_MODE_TARGET);
		OO_CHECK(player->getCompassMode() == COMPASS_MODE_TARGET);
		player->setDialIdentEngaged((BOOL)3);
		OO_CHECK(player->dialIdentEngaged());
		player->max_missiles = 5;
		OO_CHECK(player->dialMaxMissiles() == 5);
		player->setAlertFlag(ALERT_FLAG_MASS_LOCK, YES);
		OO_CHECK((player->getAlertFlags() & ALERT_FLAG_MASS_LOCK) != 0);
		player->setAlertFlag(ALERT_FLAG_MASS_LOCK, NO);
		OO_CHECK((player->getAlertFlags() & ALERT_FLAG_MASS_LOCK) == 0);
		PlayerEntityTestAccess::alertFlags(player) = 0x7;
		player->clearAlertFlags();
		OO_CHECK(player->getAlertFlags() == 0);
	}
}

// --- Slice 13: alert condition, AI messages, missiles and mines, the cloak, ECM, energy units, the
// main weapons (bead oo-30g73) ---------------------------------------------------------------------

// The fleeing status reads the member; taking the weapons offline makes every missile safe.
OO_TEST(slice13FleeingAndWeaponsOnline)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		TestPlayer *player = MakePlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::fleeing_status(part) = PLAYER_FLEEING_CARGO;
		OO_CHECK(player->fleeingStatus() == PLAYER_FLEEING_CARGO);
		player->setWeaponsOnline(YES);
		OO_CHECK(player->weaponsOnline());
		player->setWeaponsOnline(NO);
		OO_CHECK(!player->weaponsOnline());
	}
}

// --- Slices 14-28: a player whose sends to itself are recorded (beads oo-m8x1y ... oo-zn1vy) --------

namespace {

// What a RecordingPlayer was sent.
struct Sent
{
	int count = 0;
	OOCreditsQuantity amount = 0;
	std::string text;
	int number = 0;
	bool flag = false;
	std::optional<std::string> optionalText;
};
Sent sSent;

}	// namespace


/*	A player whose calls to itself that lead to the game's data (scripts, the GUI, the market) only
	record what they were sent, so that a slice's own logic is what the test sees, before and after
	the slice moves it into PlayerEntity (sends to self stay calls through the virtual members).
*/
class RecordingPlayer : public TestPlayer
{
public:
	using TestPlayer::setBounty;
	using TestPlayer::markAsOffender;
	using TestPlayer::setGuiToEquipShipScreen;
	using TestPlayer::noteGUIDidChangeFrom;
	using TestPlayer::setWeaponMount;
	using TestPlayer::addEquipmentItem;

	void setBounty(OOCreditsQuantity amount, const std::string &reason) override
	{
		sSent.count++; sSent.amount = amount; sSent.text = reason;
	}


	void markAsOffender(int offence_value, OOLegalStatusReason reason) override
	{
		sSent.count++; sSent.number = offence_value; sSent.text = cxx_OOStringFromLegalStatusReason(reason);
	}


	OOFuelQuantity fuelRequiredForJump() override
	{
		return (OOFuelQuantity)sSent.number;
	}


	void setGuiToSystemDataScreenRefreshBackground(bool refreshBackground) override
	{
		sSent.count++; sSent.flag = refreshBackground;
	}


	void setGuiToEquipShipScreen(int skip, const std::optional<std::string> &eqKey) override
	{
		sSent.count++; sSent.number = skip; sSent.optionalText = eqKey;
	}


	void showInformationForSelectedUpgradeWithFormatString(const std::optional<std::string> &formatString) override
	{
		sSent.count++; sSent.optionalText = formatString;
	}


	void noteGUIDidChangeFrom(OOGUIScreenID fromScreen, OOGUIScreenID toScreen, bool refresh) override
	{
		sSent.count++; sSent.number = (int)fromScreen * 100 + (int)toScreen; sSent.flag = refresh;
	}


	void noteSwitchToView(OOViewID toView, OOViewID fromView) override
	{
		sSent.count++; sSent.number = (int)fromView * 100 + (int)toView;
	}


	bool setWeaponMount(OOWeaponFacing facing, const std::string &eqKey, const std::optional<std::string> &context) override
	{
		sSent.count++; sSent.number = (int)facing; sSent.text = eqKey; sSent.optionalText = context;
		return YES;
	}


	OOCargoQuantity cargoQuantityOnBoard() override
	{
		return 7;
	}


	bool addEquipmentItem(const std::string &equipmentKey, bool validateAddition, const std::string &context) override
	{
		sSent.count++; sSent.text = equipmentKey + "/" + context; sSent.flag = validateAddition;
		return YES;
	}


	void setScoopsActive() override
	{
		sSent.count++;
		TestPlayer::setScoopsActive();
	}
};


namespace {

RecordingPlayer *MakeRecordingPlayer()
{
	sSent = Sent();
	gOOPlayer = nullptr;
	RecordingPlayer *player = NewTestPlayer<RecordingPlayer>();
	oo::AutoreleaseEntity(player);
	return player;
}

bool NearV(Vector a, Vector b)	{ return std::fabs(a.x - b.x) < 1e-4 && std::fabs(a.y - b.y) < 1e-4 && std::fabs(a.z - b.z) < 1e-4; }

}	// namespace


// --- Slice 14: hit testing, damage, the doppelganger, the escape capsule, dumping cargo, bounty
// (bead oo-m8x1y) ---------------------------------------------------------------------------------

// Setting the bounty with no reason sends the unknown reason's string; rotating an empty hold does
// nothing.
OO_TEST(slice14BountyAndRotateCargo)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		player->setBounty(25);
		OO_CHECK(sSent.count == 1 && sSent.amount == 25);
		OO_CHECK(sSent.text == cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonUnknown));
		player->setBounty(30, kOOLegalStatusReasonUnknown);
		OO_CHECK(sSent.count == 2 && sSent.amount == 30);
		player->rotateCargo();
		OO_CHECK(player->cargo.empty());
	}
}

// --- Slice 15: legal status, offences, bounties collected, internal damage, destruction, ending a
// scenario, docking and leaving dock (bead oo-2lpiu) ------------------------------------------------

// The bounty is the legal status; an offence with no reason sends the unknown reason; a scenario
// ends only with its own key.
OO_TEST(slice15LegalStatusOffenceAndScenario)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntityTestAccess::legalStatusValue(player) = 64;
		OO_CHECK(player->getBounty() == 64 && player->getLegalStatus() == 64);
		player->markAsOffender(8);
		OO_CHECK(sSent.count == 1 && sSent.number == 8);
		OO_CHECK(sSent.text == cxx_OOStringFromLegalStatusReason(kOOLegalStatusReasonUnknown));
		OO_CHECK(!player->endScenario("some-scenario"));
		PlayerEntityTestAccess::scenarioKey(player) = std::string("other-scenario");
		OO_CHECK(!player->endScenario("some-scenario"));
	}
}

// --- Slice 16: witchspace: start, end, checklist, jump type and distance, fuel, galactic and
// wormhole jumps (bead oo-vqjjb) -------------------------------------------------------------------

// The jump type sets the galactic flag; the fuel suffices when it reaches what the jump needs.
OO_TEST(slice16JumpTypeAndFuel)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		player->setJumpType(YES);
		OO_CHECK(PlayerEntityTestAccess::galactic_witchjump(player));
		player->setJumpType(NO);
		OO_CHECK(!PlayerEntityTestAccess::galactic_witchjump(player));
		player->fuel = 70;
		sSent.number = 50;
		OO_CHECK(player->hasSufficientFuelForJump());
		sSent.number = 70;
		OO_CHECK(player->hasSufficientFuelForJump());
		sSent.number = 71;
		OO_CHECK(!player->hasSufficientFuelForJump());
	}
}

// --- Slice 17: leaving witchspace, the status screen, the equipment list, primed and fast
// equipment, weapon types (bead oo-6tuef) ----------------------------------------------------------

// With no primable equipment nothing is primed; the fast equipment keys read and write the members.
OO_TEST(slice17PrimedAndFastEquipment)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		OO_CHECK(player->primedEquipmentCount() == 0);
		OO_CHECK(player->currentPrimedEquipment().empty());
		OO_CHECK(!player->fastEquipmentA().has_value() && !player->fastEquipmentB().has_value());
		player->setFastEquipmentA(std::string("EQ_FUEL_INJECTION"));
		player->setFastEquipmentB(std::string("EQ_ECM"));
		OO_CHECK(player->fastEquipmentA() == std::optional<std::string>("EQ_FUEL_INJECTION"));
		OO_CHECK(player->fastEquipmentB() == std::optional<std::string>("EQ_ECM"));
	}
}

// --- Slice 18: scripting lists, the system data screen, marked destinations, the chart screens
// (bead oo-3fzv5) ---------------------------------------------------------------------------------

// With no passengers, parcels or contracts the scripting lists are empty arrays; the system data
// screen is shown without refreshing the background.
OO_TEST(slice18ScriptingListsAndSystemData)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		const oo::PList passengers = player->passengerListForScripting();
		const oo::PList parcels = player->parcelListForScripting();
		const oo::PList contracts = player->contractListForScripting();
		OO_CHECK(passengers.isArray() && passengers.getIf<oo::PList::Array>()->empty());
		OO_CHECK(parcels.isArray() && parcels.getIf<oo::PList::Array>()->empty());
		OO_CHECK(contracts.isArray() && contracts.getIf<oo::PList::Array>()->empty());
		sSent.flag = true;
		player->setGuiToSystemDataScreen();
		OO_CHECK(sSent.count == 1 && !sSent.flag);
	}
}

// Slice 19 (the game options and load / save screens, the equip-screen key highlight, the available
// facings; bead oo-4tqku) has no unit case: every unit reads the GUI, the ship registry or the
// game's data, which the goldens cover.

// --- Slice 20: the equip-ship screen and upgrade information (bead oo-dycza) ------------------------

// The short forms send the long ones with no facing selection and no format string.
OO_TEST(slice20EquipShipScreenShortForms)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		sSent.optionalText = std::string("unset");
		player->setGuiToEquipShipScreen(3);
		OO_CHECK(sSent.count == 1 && sSent.number == 3 && !sSent.optionalText.has_value());
		sSent.optionalText = std::string("unset");
		player->showInformationForSelectedUpgrade();
		OO_CHECK(sSent.count == 2 && !sSent.optionalText.has_value());
	}
}

// --- Slice 21: the interfaces screen, the start screen and intro, the OXZ manager, GUI and view
// change notes (bead oo-a602n) ---------------------------------------------------------------------

// The short GUI change note sends the long one without a refresh; the view change note is the
// controls' view switch, arguments swapped.
OO_TEST(slice21ChangeNotes)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		sSent.flag = true;
		player->noteGUIDidChangeFrom(GUI_SCREEN_STATUS, GUI_SCREEN_MARKET);
		OO_CHECK(sSent.count == 1 && sSent.number == (int)GUI_SCREEN_STATUS * 100 + (int)GUI_SCREEN_MARKET && !sSent.flag);
		player->noteViewDidChangeFrom(VIEW_AFT, VIEW_FORWARD);
		OO_CHECK(sSent.count == 2 && sSent.number == (int)VIEW_AFT * 100 + (int)VIEW_FORWARD);
	}
}

// --- Slice 22: buying equipment, script price adjustment, weapon mounts, passenger berths, removing
// missiles, trade-in (bead oo-mv49m) ---------------------------------------------------------------

// Mounting a weapon is a purchase; no berth changes by zero, and none is removed when there is none.
OO_TEST(slice22WeaponMountAndBerths)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		OO_CHECK(player->setWeaponMount(WEAPON_FACING_AFT, "EQ_WEAPON_PULSE_LASER"));
		OO_CHECK(sSent.count == 1 && sSent.number == (int)WEAPON_FACING_AFT && sSent.text == "EQ_WEAPON_PULSE_LASER");
		OO_CHECK(sSent.optionalText == std::optional<std::string>("purchase"));
		OO_CHECK(!player->changePassengerBerths(0));
		PlayerEntityTestAccess::max_passengers(player) = 0;
		OO_CHECK(!player->changePassengerBerths(-1));
		OO_CHECK(PlayerEntityTestAccess::max_passengers(player) == 0);
	}
}

// --- Slice 23: cargo quantities, the local market, market filters and sorters, market screen rows
// (bead oo-wt5jv) ---------------------------------------------------------------------------------

// The current cargo is what is on board.
OO_TEST(slice23CalculateCurrentCargo)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntityTestAccess::current_cargo(player) = 0;
		player->calculateCurrentCargo();
		OO_CHECK(PlayerEntityTestAccess::current_cargo(player) == 7);
	}
}

// --- Slice 24: the market screens, buying and selling commodities, mining and speech flags, adding
// equipment (bead oo-bj7u8) ------------------------------------------------------------------------

// The screen, mining and speech flags read the members; adding equipment validates it.
OO_TEST(slice24FlagsAndAddEquipment)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::gui_screen(part) = GUI_SCREEN_MARKET;
		OO_CHECK(player->guiScreen() == GUI_SCREEN_MARKET);
		PlayerEntityTestAccess::using_mining_laser(part) = YES;
		OO_CHECK(player->isMining());
		PlayerEntityTestAccess::using_mining_laser(part) = NO;
		OO_CHECK(!player->isMining());
		PlayerEntityTestAccess::isSpeechOn(part) = OOSPEECHSETTINGS_ALL;
		OO_CHECK(player->getIsSpeechOn() == OOSPEECHSETTINGS_ALL);
		OO_CHECK(player->addEquipmentItem("EQ_ECM", "purchase"));
		OO_CHECK(sSent.count == 1 && sSent.text == "EQ_ECM/purchase" && sSent.flag);
	}
}

// --- Slice 25: equipment, pylons, parcels and passengers, comms, fines, trade-in factor, renovation,
// view offsets, trumbles (bead oo-hu1xk) -----------------------------------------------------------

// The counts read the members; the trade-in factor stays within 75..100; the view offsets come from
// the bounding box, and the weapon view offset follows the facing.
OO_TEST(slice25CountsTradeInAndViewOffsets)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntity *part = player;
		OO_CHECK(player->parcelCount() == 0 && player->passengerCount() == 0 && player->getTrumbleCount() == 0);
		PlayerEntityTestAccess::max_passengers(part) = 3;
		OO_CHECK(player->passengerCapacity() == 3);
		PlayerEntityTestAccess::ship_trade_in_factor(part) = 90;
		player->adjustTradeInFactorBy(5);
		OO_CHECK(player->tradeInFactor() == 95);
		player->adjustTradeInFactorBy(50);
		OO_CHECK(player->tradeInFactor() == 100);
		player->adjustTradeInFactorBy(-50);
		OO_CHECK(player->tradeInFactor() == 75);
		player->boundingBox.min = make_vector(-10.0f, -2.0f, -20.0f);
		player->boundingBox.max = make_vector(10.0f, 2.0f, 40.0f);
		player->setDefaultViewOffsets();
		OO_CHECK(NearV(PlayerEntityTestAccess::forwardViewOffset(part), make_vector(0.0f, 0.0f, 10.0f)));
		OO_CHECK(NearV(PlayerEntityTestAccess::aftViewOffset(part), make_vector(0.0f, 0.0f, 10.0f)));
		OO_CHECK(NearV(PlayerEntityTestAccess::portViewOffset(part), make_vector(0.0f, 0.0f, 0.0f)));
		OO_CHECK(NearV(PlayerEntityTestAccess::customViewOffset(part), kZeroVector));
		PlayerEntityTestAccess::aftViewOffset(part) = make_vector(1.0f, 2.0f, 3.0f);
		player->currentWeaponFacing = WEAPON_FACING_AFT;
		OO_CHECK(NearV(player->weaponViewOffset(), make_vector(1.0f, 2.0f, 3.0f)));
	}
}

// --- Slice 26: trumble values, checksums, screen modes, target memory, missile ident, rotating and
// panning the custom view (bead oo-cpam5) ----------------------------------------------------------

// The appetite and the flags read and write the members; clearing the target memory fills it with
// empty slots; zooming the custom view out scales its offset about the rotation centre, limited by
// the collision radius.
OO_TEST(slice26TargetMemoryAndCustomViewZoom)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntity *part = player;
		player->setTrumbleAppetiteAccumulator(2.5f);
		OO_CHECK(player->trumbleAppetiteAccumulator() == 2.5f);
		player->getSuppressTargetLost();
		OO_CHECK(PlayerEntityTestAccess::suppressTargetLostFlag(part));
		player->setScoopsActive();
		OO_CHECK(PlayerEntityTestAccess::scoopsActive(player));
		player->clearTargetMemory();
		OO_CHECK(player->targetMemory().size() == PLAYER_TARGET_MEMORY_SIZE && PlayerEntityTestAccess::target_memory_index(player) == 0);
		player->setCustomViewRotationCenter(make_vector(0.0f, 0.0f, 1.0f));
		player->setCustomViewOffset(make_vector(0.0f, 0.0f, 3.0f));
		OO_CHECK(NearV(player->getCustomViewRotationCenter(), make_vector(0.0f, 0.0f, 1.0f)));
		player->collision_radius = 10.0f;
		player->customViewZoomOut(2.0f);
		OO_CHECK(NearV(player->getCustomViewOffset(), make_vector(0.0f, 0.0f, 5.0f)));
		player->collision_radius = 0.01f;
		player->customViewZoomOut(2.0f);
		OO_CHECK(NearV(player->getCustomViewOffset(), make_vector(0.0f, 0.0f, 1.0f + CUSTOM_VIEW_MAX_ZOOM_OUT * 0.01f)));
	}
}

// --- Slice 27: custom view vectors and data, the mission overlay and background, world scripts and
// script events, galactic hyperspace, jump cause, names (bead oo-u1e9m) ------------------------------

// The custom view data follow the quaternion; the galactic hyperspace behaviour accepts only known
// values; the fixed coordinates are clamped; scoop override turns the scoops on; the names read and
// write the members.
OO_TEST(slice27CustomViewHyperspaceAndNames)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		player->setCustomViewQuaternion(kIdentityQuaternion);
		OO_CHECK(NearV(player->getCustomViewForwardVector(), vector_forward_from_quaternion(kIdentityQuaternion)));
		OO_CHECK(NearV(player->getCustomViewUpVector(), vector_up_from_quaternion(kIdentityQuaternion)));
		OO_CHECK(NearV(player->getCustomViewRightVector(), vector_right_from_quaternion(kIdentityQuaternion)));
		OO_CHECK(!player->scriptsLoaded() && player->worldScriptNames().empty());
		player->setGalacticHyperspaceBehaviour(GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES);
		OO_CHECK(player->getGalacticHyperspaceBehaviour() == GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES);
		player->setGalacticHyperspaceBehaviour(GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN);
		OO_CHECK(player->getGalacticHyperspaceBehaviour() == GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES);
		player->setGalacticHyperspaceFixedCoords(NSMakePoint(300.0, 12.4));
		OO_CHECK(Near(player->getGalacticHyperspaceFixedCoords(), NSMakePoint(255, 12)));
		player->setMissionExitScreen(GUI_SCREEN_STATUS);
		OO_CHECK(player->missionExitScreen() == GUI_SCREEN_STATUS);
		player->setScoopOverride(YES);
		OO_CHECK(player->getScoopOverride() && sSent.count == 1);
		player->setCommanderName(std::string("Jameson"));
		player->setLastsaveName(std::string("save1"));
		player->setJumpCause(std::string("standard jump"));
		OO_CHECK(player->commanderName() == std::optional<std::string>("Jameson"));
		OO_CHECK(player->lastsaveName() == std::optional<std::string>("save1"));
		OO_CHECK(player->jumpCause() == std::optional<std::string>("standard jump"));
	}
}

// --- Slice 28: docking clearance, scanned wormholes, mission destinations, the shipyard record, extra
// mission and GUI-screen keys, the state dump (bead oo-zn1vy) ---------------------------------------

// Cleared to dock once granted or not required; a marker's key is its system and name; the extra
// mission keys are cleared.
OO_TEST(slice28ClearanceMarkerKeyAndExtraKeys)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntity *part = player;
		PlayerEntityTestAccess::dockingClearanceStatus(part) = DOCKING_CLEARANCE_STATUS_REQUESTED;
		OO_CHECK(!player->clearedToDock() && player->getDockingClearanceStatus() == DOCKING_CLEARANCE_STATUS_REQUESTED);
		PlayerEntityTestAccess::dockingClearanceStatus(part) = DOCKING_CLEARANCE_STATUS_GRANTED;
		OO_CHECK(player->clearedToDock());
		PlayerEntityTestAccess::dockingClearanceStatus(part) = DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
		OO_CHECK(player->clearedToDock());
		const oo::PList marker(oo::PList::Dict{ { "system", oo::PList(7) }, { "name", oo::PList(std::string("beacon")) } });
		OO_CHECK(player->markerKey(marker) == std::optional<std::string>("7-beacon"));
		OO_CHECK(player->markerKey(oo::PList(oo::PList::Dict{})) == std::optional<std::string>("0-(null)"));
		PlayerEntityTestAccess::extraMissionKeys(part)["oolite-mission-key"] = oo::PList();
		player->clearExtraMissionKeys();
		OO_CHECK(PlayerEntityTestAccess::extraMissionKeys(part).empty());
		OO_CHECK(player->shipyardRecord() == &PlayerEntityTestAccess::shipyard_record(part));
		OO_CHECK(player->getScannedWormholes().empty());
	}
}

// --- The category files (the Convert-to-C++20 batch, bead oo-lmdi8): PlayerEntitySound.mm,
// PlayerEntityStickMapper.mm, PlayerEntityControls.mm, PlayerEntityKeyMapper.mm,
// PlayerEntityLegacyScriptEngine.mm, PlayerEntityContracts.mm, PlayerEntityLoadSave.mm. Each case
// pins units a player in a never-initialised universe can answer, written against the Objective-C
// categories and run on them first; the screens, the controls' polling and the load / save panels
// read the GUI, the keyboard or the game's files, which the goldens cover. ------------------------

namespace {
Entity *sCategoryTarget = nil;	// what a CategoryPlayer answers as its primary target (not retained)
}


/*	A recording player whose script events, roles, missiles and ident sounds only count, so that a
	category unit's own logic is what the case sees (sends to self stay calls through the virtual
	members after the move).
*/
class CategoryPlayer : public RecordingPlayer
{
public:
	using RecordingPlayer::doScriptEvent;
	using RecordingPlayer::addRoleToPlayer;

	void doScriptEvent(ooscript::PropertyId /*message*/, const std::vector<oo::PList> &arguments) override
	{
		sSent.count++; sSent.number = (int)arguments.size();
	}


	void addRoleToPlayer(const std::string &role) override
	{
		sSent.count++; sSent.text = role;
	}


	void safeAllMissiles() override	{ sSent.count++; }
	void noteLostTarget() override	{ sSent.count++; }
	void playIdentOn() override	{ sSent.count++; sSent.flag = true; }
	void playIdentLockedOn() override	{ sSent.count++; }
	void printIdentLockedOnForMissile(bool missile) override	{ sSent.count++; sSent.number = missile ? 1 : 2; }

	// The target the ident button finds: the unit test's universe has no descriptions to expand the
	// "ident-on" message with (expanding one exits), so the case keeps a target.
	Entity *primaryTarget() override	{ return sCategoryTarget; }	// the C++ entity since bead oo-9ht.39.23
};


namespace {

// A string value's text; a value that is not a string never matches.
std::string StringOf(const oo::PList &value)
{
	const std::string *text = value.getIf<std::string>();
	return text != nullptr ? *text : std::string("<not a string>");
}


CategoryPlayer *MakeCategoryPlayer()
{
	sSent = Sent();
	gOOPlayer = nullptr;
	CategoryPlayer *player = NewTestPlayer<CategoryPlayer>();
	oo::AutoreleaseEntity(player);
	return player;
}

}	// namespace


// PlayerEntitySound.mm (bead oo-xowh): with no interface source playing, the player is not beeping.
OO_TEST(soundIsNotBeepingWithNothingPlaying)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		OO_CHECK(!player->isBeeping());
	}
}


// PlayerEntityStickMapper.mm (bead oo-ibm8): hardware flags as words, and the GUI entries the
// function list is made of (a long description cut to 28 units and "...", absent functions left out).
OO_TEST(stickMapperHardwareAndGuiDicts)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		OO_CHECK(player->hwToString(HW_AXIS) == "axis");
		OO_CHECK(player->hwToString(HW_BUTTON) == "button");
		OO_CHECK(player->hwToString(HW_AXIS | HW_BUTTON) == "axis/button");
		const oo::PList dict = player->makeStickGuiDict("Roll", HW_AXIS, 3, -1);
		OO_CHECK(dict.get<std::string>(std::string(KEY_GUIDESC)) == "Roll");
		OO_CHECK(dict.get<long long>(std::string(KEY_ALLOWABLE)) == HW_AXIS && dict.get<long long>(std::string(KEY_AXISFN)) == 3);
		OO_CHECK(dict.find(KEY_BUTTONFN) == nullptr);
		const std::string longName(60, 'x');
		const oo::PList cut = player->makeStickGuiDict(longName, HW_BUTTON, -1, 4);
		OO_CHECK(cut.get<std::string>(std::string(KEY_GUIDESC)) == std::string(28, 'x') + "...");
		OO_CHECK(cut.find(KEY_AXISFN) == nullptr && cut.get<long long>(std::string(KEY_BUTTONFN)) == 4);
		const oo::PList header = player->makeStickGuiDictHeader("Flight");
		OO_CHECK(header.get<std::string>(std::string(KEY_HEADER)) == "Flight" && header.get<std::string>(std::string(KEY_AXISFN)).empty());
	}
}


// PlayerEntityControls.mm slice 1 (bead oo-hsilb): the first key code of a definition (0 for none),
// and clearing the planet search string.
OO_TEST(controlsSlice1FirstKeyCodeAndPlanetSearch)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		const oo::PList keyDef(oo::PList::Array{ oo::PList(oo::PList::Dict{ { "key", oo::PList(65) } }), oo::PList(oo::PList::Dict{ { "key", oo::PList(66) } }) });
		OO_CHECK(player->getFirstKeyCode(keyDef) == 65);
		OO_CHECK(player->getFirstKeyCode(oo::PList(oo::PList::Array{})) == 0);
		PlayerEntityTestAccess::planetSearchString(player) = std::string("Lave");
		player->clearPlanetSearchString();
		OO_CHECK(!PlayerEntityTestAccess::planetSearchString(player).has_value());
	}
}

// PlayerEntityControls.mm slices 2-6 (beads oo-56tmj, oo-4216h, oo-n8wn2, oo-uq8px, oo-fz3l8) have
// no unit case: every unit polls the keyboard, the joystick or the GUI, which the goldens cover.

// PlayerEntityControls.mm slice 7 (bead oo-lmdi8): the ident button safes the missiles, engages
// ident and, with a target, plays the locked-on sound and prints the lock (not for a missile);
// pressed again it first drops the target.
OO_TEST(controlsSlice7IdentButton)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		CategoryPlayer *player = MakeCategoryPlayer();
		sCategoryTarget = player;
		player->handleButtonIdent();
		OO_CHECK(PlayerEntityTestAccess::ident_engaged(player));
		OO_CHECK(sSent.count == 3 && !sSent.flag && sSent.number == 2);
		sSent = Sent();
		player->handleButtonIdent();
		OO_CHECK(sSent.count == 4 && !sSent.flag);
		sCategoryTarget = nil;
	}
}


// PlayerEntityKeyMapper.mm slice 1 (bead oo-5uo7): the key-function list's GUI entries (a long
// description cut to 48 units and "...").
OO_TEST(keyMapperSlice1GuiDicts)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		const oo::PList dict = player->makeKeyGuiDict("Fire laser", "key_fire_lasers");
		OO_CHECK(dict.get<std::string>(std::string(KEY_KC_GUIDESC)) == "Fire laser");
		OO_CHECK(dict.get<std::string>(std::string(KEY_KC_DEFINITION)) == "key_fire_lasers");
		const oo::PList cut = player->makeKeyGuiDict(std::string(51, 'y'), "k");
		OO_CHECK(cut.get<std::string>(std::string(KEY_KC_GUIDESC)) == std::string(48, 'y') + "...");
		const oo::PList header = player->makeKeyGuiDictHeader("Navigation");
		OO_CHECK(header.get<std::string>(std::string(KEY_KC_HEADER)) == "Navigation");
		OO_CHECK(header.get<std::string>(std::string(KEY_KC_DEFINITION)).empty());
	}
}


// PlayerEntityKeyMapper.mm slice 2 (bead oo-10jz): custom-equipment entries are activate_ and mode_
// keys, and their key-definition type.
OO_TEST(keyMapperSlice2CustomEquipEntries)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		OO_CHECK(player->entryIsCustomEquip("activate_EQ_ECM") && player->entryIsCustomEquip("mode_EQ_ECM"));
		OO_CHECK(!player->entryIsCustomEquip("key_ecm"));
		OO_CHECK(player->entryIsDictCustomEquip(oo::PList(oo::PList::Dict{ { std::string(KEY_KC_DEFINITION), oo::PList(std::string("mode_EQ_X")) } })));
		OO_CHECK(!player->entryIsDictCustomEquip(oo::PList(oo::PList::Dict{})));
		OO_CHECK(player->getCustomEquipKeyDefType("activate_EQ_ECM") == std::optional<std::string>(std::string(CUSTOMEQUIP_KEYACTIVATE)));
		OO_CHECK(player->getCustomEquipKeyDefType("mode_EQ_ECM") == std::optional<std::string>(std::string(CUSTOMEQUIP_KEYMODE)));
		OO_CHECK(player->getCustomEquipKeyDefType("key_ecm") == std::optional<std::string>(std::string()));
	}
}


// PlayerEntityKeyMapper.mm slice 3 (bead oo-mofd): two key entries are the same when the key and
// the three modifiers are.
OO_TEST(keyMapperSlice3CompareKeyEntries)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		const oo::PList a(oo::PList::Dict{ { "key", oo::PList(65) }, { "shift", oo::PList(true) } });
		const oo::PList b(oo::PList::Dict{ { "key", oo::PList(std::string("65")) }, { "shift", oo::PList(true) } });
		const oo::PList c(oo::PList::Dict{ { "key", oo::PList(65) } });
		OO_CHECK(player->compareKeyEntries(a, a));
		OO_CHECK(player->compareKeyEntries(a, b));
		OO_CHECK(!player->compareKeyEntries(a, c));
		OO_CHECK(!player->compareKeyEntries(c, oo::PList(oo::PList::Dict{ { "key", oo::PList(66) } })));
	}
}


// PlayerEntityLegacyScriptEngine.mm slice 1 (bead oo-130j): mission variables need the store
// (nothing is kept before set-up); a null value removes one; local variables are per mission.
OO_TEST(legacyScriptSlice1MissionAndLocalVariables)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntityTestAccess::mission_variables(player) = oo::PList();
		player->setMissionVariable(oo::PList(std::string("1")), "mission_x");
		OO_CHECK(player->missionVariableForKey("mission_x").isNull());
		PlayerEntityTestAccess::mission_variables(player) = oo::PList(oo::PList::Dict{});
		player->setMissionVariable(oo::PList(std::string("1")), "mission_x");
		OO_CHECK(StringOf(player->missionVariableForKey("mission_x")) == "1");
		OO_CHECK(player->missionVariables().count() == 1);
		player->setMissionVariable(oo::PList(), "mission_x");
		OO_CHECK(player->missionVariableForKey("mission_x").isNull());
		player->setLocalVariable(std::string("7"), "local_y", std::string("m1"));
		OO_CHECK(player->localVariableForKey("local_y", std::string("m1")) == std::optional<std::string>("7"));
		OO_CHECK(!player->localVariableForKey("local_y", std::string("m2")).has_value());
		OO_CHECK(!player->localVariableForKey("local_y", std::nullopt).has_value());
		OO_CHECK(player->localVariablesForMission(std::nullopt).isNull());
	}
}


// PlayerEntityLegacyScriptEngine.mm slice 2 (bead oo-ng9h): the credits query answers the balance.
OO_TEST(legacyScriptSlice2CreditsQuery)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		player->setCreditBalance(42.5);
		const oo::PList credits = player->credits_number();
		OO_CHECK(credits.isNumber() && credits.doubleValue() == 42.5);
	}
}


// PlayerEntityLegacyScriptEngine.mm slice 3 (bead oo-z1nv): set:, increment:, decrement: and reset:
// on a mission variable, and the mission title.
OO_TEST(legacyScriptSlice3VariableArithmeticAndTitle)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntityTestAccess::mission_variables(player) = oo::PList(oo::PList::Dict{});
		player->set("mission_count 5");
		OO_CHECK(StringOf(player->missionVariableForKey("mission_count")) == "5");
		player->increment("mission_count");
		OO_CHECK(StringOf(player->missionVariableForKey("mission_count")) == "6");
		player->decrement("mission_count");
		player->decrement("mission_count");
		OO_CHECK(StringOf(player->missionVariableForKey("mission_count")) == "4");
		player->set("no_prefix 1");
		OO_CHECK(player->missionVariableForKey("no_prefix").isNull());
		player->reset("mission_count");
		OO_CHECK(player->missionVariableForKey("mission_count").isNull());
		player->setMissionTitle(std::string("A title"));
		OO_CHECK(player->missionTitle() == std::optional<std::string>("A title"));
		player->setMissionTitle(std::nullopt);
		OO_CHECK(!player->missionTitle().has_value());
	}
}


// PlayerEntityLegacyScriptEngine.mm slice 4 (bead oo-vn3o): the mission screen's identifier, and
// the index of an equipment script that is not there (the count).
OO_TEST(legacyScriptSlice4MissionScreenIDAndEqScripts)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		player->setMissionScreenID(std::string("screen-1"));
		OO_CHECK(player->missionScreenID() == std::optional<std::string>("screen-1"));
		player->clearMissionScreenID();
		OO_CHECK(!player->missionScreenID().has_value());
		OO_CHECK(player->eqScriptIndexForKey("EQ_NONE") == PlayerEntityTestAccess::eqScripts(player).size());
	}
}


// PlayerEntityContracts.mm slice 1 (bead oo-6e3h): a passenger is added once (a risky one adds the
// courier role, and the event is sent with two arguments) and removed by name; contracted volume
// counts a good's contracts; the docking report joins messages with a blank line.
OO_TEST(contractsSlice1PassengersVolumeAndReport)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		CategoryPlayer *player = MakeCategoryPlayer();
		gOOPlayer = player;	// addPassenger() reads PLAYER's clock, which the debug build asserts is set (bead oo-vdw34)
		PlayerEntityTestAccess::max_passengers(player) = 2;
		OO_CHECK(player->addPassenger("Ann", 1, 2, 100.0, 10.0, 1.0, 2));
		OO_CHECK(sSent.count == 2 && sSent.text == "trader-courier+" && sSent.number == 2);
		OO_CHECK(!player->addPassenger("Ann", 1, 2, 100.0, 10.0, 1.0, 0));
		OO_CHECK(PlayerEntityTestAccess::passengers(player).size() == 1);
		OO_CHECK(!player->removePassenger("Bob"));
		OO_CHECK(player->removePassenger("Ann") && PlayerEntityTestAccess::passengers(player).empty());
		PlayerEntityTestAccess::contracts(player).push_back(oo::PList(oo::PList::Dict{ { std::string(CARGO_KEY_TYPE), oo::PList(std::string("food")) }, { std::string(CARGO_KEY_AMOUNT), oo::PList(3) } }));
		PlayerEntityTestAccess::contracts(player).push_back(oo::PList(oo::PList::Dict{ { std::string(CARGO_KEY_TYPE), oo::PList(std::string("food")) }, { std::string(CARGO_KEY_AMOUNT), oo::PList(4) } }));
		OO_CHECK(player->contractedVolumeForGood("food") == 7 && player->contractedVolumeForGood("gold") == 0);
		PlayerEntityTestAccess::dockingReport(player).clear();
		player->addMessageToReport("one");
		player->addMessageToReport("");
		player->addMessageToReport("two");
		OO_CHECK(PlayerEntityTestAccess::dockingReport(player) == "one\n\ntwo");
		gOOPlayer = nullptr;
	}
}


// PlayerEntityContracts.mm slice 2 (bead oo-t2t5): with no record each reputation is the middle of
// its range (unknown counts as the maximum), and the record is a dictionary.
OO_TEST(contractsSlice2Reputation)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntityTestAccess::reputation(player).clear();
		OO_CHECK(player->passengerReputation() == MAX_CONTRACT_REP / 2);
		OO_CHECK(player->parcelReputation() == MAX_CONTRACT_REP / 2);
		OO_CHECK(player->contractReputation() == MAX_CONTRACT_REP / 2);
		OO_CHECK(player->getReputation().isDict());
	}
}


// PlayerEntityContracts.mm slice 3 (bead oo-oo99): a ship with all its subentities loses nothing.
OO_TEST(contractsSlice3MissingSubEntities)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		OO_CHECK(player->missingSubEntitiesAdjustment() == 0);
	}
}


// PlayerEntityLoadSave.mm slice 1 (bead oo-xmvt) has no unit case: its units read the save files,
// the scenarios and the GUI, which the goldens cover.

// PlayerEntityLoadSave.mm slice 2 (bead oo-rczn): a commander is found by its save name, else its
// name; one not in the list is not found.
OO_TEST(loadSaveSlice2FindCommander)
{
	{
		oo::AutoreleaseScope scope;	// was @autoreleasepool (oo-31u.6)
		SetUp();
		RecordingPlayer *player = MakeRecordingPlayer();
		PlayerEntityTestAccess::cdrDetailArray(player).clear();
		OO_CHECK(player->findIndexOfCommander("Jameson") == -1);
		PlayerEntityTestAccess::cdrDetailArray(player).push_back(oo::PList(oo::PList::Dict{ { "player_name", oo::PList(std::string("Jameson")) } }));
		PlayerEntityTestAccess::cdrDetailArray(player).push_back(oo::PList(oo::PList::Dict{ { "player_save_name", oo::PList(std::string("Other")) }, { "player_name", oo::PList(std::string("Jameson")) } }));
		OO_CHECK(player->findIndexOfCommander("Jameson") == 0);
		OO_CHECK(player->findIndexOfCommander("Other") == 1);
		PlayerEntityTestAccess::cdrDetailArray(player).clear();
	}
}


OO_TEST_MAIN()
