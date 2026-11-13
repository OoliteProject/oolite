/*	test_SaveEnumValues.cpp
	Spec 009 (T010, FR-016): the numbers a saved game holds for the player's enums, pinned before the
	enums change. A player is saved (PlayerEntity::commanderDataDictionary()) and the numbers it
	writes for chart_ana_mode, chart_colour_mode and speech_on are asserted, and each is read back
	with the conversion setCommanderDataFromDictionary() uses (the number cast to its enum): the
	whole load needs the game's data and add-ons, which a unit test does not have. The legacy
	energy_unit numbers a pre-1.80 save holds are pinned, and the long-range chart modes' ordinals
	(OOLRC_MODE_UNKNOWN 0, OOLRC_MODE_TECHLEVEL 4: not the value column of
	OOLongRangeChartMode.tbl). A ship's behaviour is not in a saved game; its number leaves the
	program through the by-name "behaviour" call, which is pinned instead.

	The player is made as test_PlayerEntity makes it (the whole game linked but main, a Universe
	never initialised), with an OpenGL context for the trumbles' textures; the save's script events
	make the JavaScript engine's own context. Run: tests/run.sh unit
*/

#include "OOCallByName.h"
#include "OOConstToString.h"
#include "OOEntityCalledByName.h"
#include "PlayerEntity.h"
#include "ShipEntity.h"
#include "Universe.h"

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"
#include "oofnd/Defaults.hpp"

#include <format>
#include <string>
#include "EntityManualRefs.h"  // the tests' manual entity references (T095)


#define OO_PLAYER_MEMBER(name)	static auto &name(PlayerEntity *player)	{ return player->name; }

struct PlayerEntityTestAccess
{
	OO_PLAYER_MEMBER(ANA_mode)
	OO_PLAYER_MEMBER(longRangeChartMode)
	OO_PLAYER_MEMBER(isSpeechOn)
};

#undef OO_PLAYER_MEMBER

#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;

namespace {

// A player whose set-up from shipdata, session set-up and controls do nothing (they need the
// game's data).
class TestPlayer : public PlayerEntity
{
public:
	bool setUpShipFromDictionary(const oo::PList &) override	{ return true; }
	bool setUpAndConfirmOK(bool) override	{ return true; }
	void initControls() override	{}
};

class TestShip : public ShipEntity
{
public:
	bool setUpShipFromDictionary(const oo::PList &) override	{ return true; }
};

void SetUp()
{
	static Universe *universe = nullptr;
	if (universe == nullptr)  universe = new Universe();	// never released
	gSharedUniverse = universe;
	gOOPlayer = nullptr;
}

template <class T>
T *NewEntity()
{
	std::shared_ptr<T> made = oo::makeShared<T>();
	{
		oo::AutoreleaseScope scope;
		oo::RetainEntity(oo::MadeEntity(made));
	}
	return made.get();
}

// The number a save holds under key, as the game reads it back (-oo_intForKey:); a missing key
// reads as -12345, which no pinned value is.
int Saved(const oo::PList &save, const char *key)
{
	return save.find(key) != nullptr ? save.get<int>(key) : -12345;
}

}	// namespace


OO_TEST(savedChartAndSpeechNumbers)
{
	OO_CHECK(OOTestGLContext());	// the trumbles' set-up loads their textures
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestPlayer *player = NewEntity<TestPlayer>();
		gOOPlayer = player;
		player->setUpTrumbles();	// deferredInit()'s, which the save reads
		const struct { int route, chart, speech; } kCases[] = { {0, 0, 0}, {1, 1, 2}, {2, 4, 1} };
		for (const auto &c : kCases)
		{
			PlayerEntityTestAccess::ANA_mode(player) = static_cast<OORouteType>(c.route);
			PlayerEntityTestAccess::longRangeChartMode(player) = static_cast<OOLongRangeChartMode>(c.chart);
			PlayerEntityTestAccess::isSpeechOn(player) = static_cast<OOSpeechSettings>(c.speech);
			const oo::PList save = player->commanderDataDictionary();
			// The save also records the trumbles' hash in the defaults: removed again.
			oo::Defaults::standard().removeObject(std::format("{}-humbletrash", player->commanderName().value_or("(null)")));
			OO_CHECK(Saved(save, "chart_ana_mode") == c.route);
			OO_CHECK(Saved(save, "chart_colour_mode") == c.chart);
			OO_CHECK(Saved(save, "speech_on") == c.speech);
			// Read back as setCommanderDataFromDictionary() converts them.
			OO_CHECK(static_cast<OORouteType>(Saved(save, "chart_ana_mode")) == PlayerEntityTestAccess::ANA_mode(player));
			OO_CHECK(static_cast<OOLongRangeChartMode>(Saved(save, "chart_colour_mode")) == PlayerEntityTestAccess::longRangeChartMode(player));
			OO_CHECK(static_cast<OOSpeechSettings>(Saved(save, "speech_on")) == PlayerEntityTestAccess::isSpeechOn(player));
		}
		// The route and speech numbers name what they did.
		OO_CHECK(cxx_RouteTypeToString(static_cast<OORouteType>(2)) == "OPTIMIZED_BY_TIME");
		OO_CHECK(cxx_RouteTypeToString(static_cast<OORouteType>(1)) == "OPTIMIZED_BY_JUMPS");
		gOOPlayer = nullptr;
		oo::ReleaseEntity(player);
	}
}

OO_TEST(longRangeChartModeOrdinals)
{
	// The program's ordinals, which saves hold, read through the names JS and saves use.
	const char *const kModes[] = { "OOLRC_MODE_UNKNOWN", "OOLRC_MODE_SUNCOLOR", "OOLRC_MODE_ECONOMY", "OOLRC_MODE_GOVERNMENT", "OOLRC_MODE_TECHLEVEL" };
	for (int i = 0; i < 5; i++)
	{
		OO_CHECK(static_cast<int>(cxx_OOLongRangeChartModeFromString(kModes[i])) == i);
		OO_CHECK(cxx_OOStringFromLongRangeChartMode(static_cast<OOLongRangeChartMode>(i)) == kModes[i]);
	}
}

OO_TEST(legacyEnergyUnitNumbers)
{
	// A pre-1.80 save's energy_unit: 15 was the normal unit and 20 the naval one, which
	// setCommanderDataFromDictionary() turns into EQ_ENERGY_UNIT and EQ_NAVAL_ENERGY_UNIT; the
	// current units are 8 and 16, the damaged ones 1 and 2.
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kOldNormal) == 15);
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kOldNaval) == 20);
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kNormal) == 8);
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kNaval) == 16);
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kNormalDamaged) == 1);
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kNavalDamaged) == 2);
	OO_CHECK(static_cast<int>(OOEnergyUnitType::kNone) == 0);
	OO_CHECK(cxx_EnergyUnitTypeToString(static_cast<OOEnergyUnitType>(8)) == "ENERGY_UNIT_NORMAL");
	OO_CHECK(cxx_EnergyUnitTypeToString(static_cast<OOEnergyUnitType>(16)) == "ENERGY_UNIT_NAVAL");
}

OO_TEST(shipBehaviourNumbersByName)
{
	SetUp();
	{
		oo::AutoreleaseScope pool;
		TestShip *ship = NewEntity<TestShip>();
		const struct { int number; const char *name; } kBehaviours[] = {
			{0, "BEHAVIOUR_IDLE"}, {101, "BEHAVIOUR_ATTACK_TARGET"}, {125, "BEHAVIOUR_CLOSE_WITH_TARGET"},
			{201, "BEHAVIOUR_FLY_TO_DESTINATION"}, {811, "BEHAVIOUR_SCRIPTED_ATTACK_AI"} };
		for (const auto &b : kBehaviours)
		{
			ship->setBehaviour(static_cast<OOBehaviour>(b.number));
			OOEntityByNameValue value;
			OO_CHECK(oo::CallEntityByNameTyped(ship, "behaviour", value) && value.integer == b.number);
			OO_CHECK(cxx_OOStringFromBehaviour(static_cast<OOBehaviour>(b.number)) == b.name);
		}
		oo::ReleaseEntity(ship);
	}
}

OO_TEST_MAIN()
