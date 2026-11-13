/*	test_ProxyPlayerEntity.mm
        Unit tests for ProxyPlayerEntity
   (src/Core/Entities/ProxyPlayerEntity.h), the ship that stands in for the
   player's ship where only a ship can be shown (the shipyard, the doppelganger)
   and answers the player's dials to the shaders.

        As test_StationEntity's, the ship needs the game graph, so the test
   links the whole game but main (['*']) and uses a Universe that was never
   initialised and a plain entity as PLAYER. The proxy keeps ShipEntity's own
   set-up from an unpiloted definition. The cases test the class's units: the
   initialiser's defaults, each dial's accessors,
   -copyValuesFromPlayer: from a player whose dials answer fixed values, and
   -isPlayerLikeShip for the three classes that answer it. The cases after "The
   crossing" pin the C++ part. The proxy is made by
   newProxyObject(), the class's selectors are
   member calls, and the dials case pins the
   dials the ship answers by name for a proxy. The last case pins that
   the proxy and the player are visible to scripts. Every ship is C++ whose
   root category answers the dials by
   name. Run: bash tools/check-core-tests.sh
   test_ProxyPlayerEntity
*/

#include "ProxyPlayerEntity.h"
#include "Universe.h"
#include "PlayerEntity.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOCallByName.h"	// oo::EntityRespondsToName / oo::CallEntityByName
#include "OOEntityCalledByName.h"	// oo::CallEntityByNameTyped

#include "oo_test.hpp"

#include <string>
#include "EntityManualRefs.h"  // the tests' manual entity references
#include "oofnd/AutoreleaseScope.hpp"


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;
extern JSContext *gOOJSMainThreadContext;


class TestProxyPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>(): a C++ player, as PlayerEntity::sharedPlayer() makes the game's,
// retained (+1).
template <class T>
T *NewTestPlayer()
{
	std::shared_ptr<T> player = oo::makeShared<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


// A player whose dials answer fixed values (the real ones read the HUD, the universe and the
// player's equipment).
class TestDialPlayer : public PlayerEntity
{
public:
	float fuelLeakRate() override	{ return 2.5f; }
	bool massLocked() override	{ return true; }
	bool atHyperspeed() override	{ return true; }
	GLfloat dialForwardShield() override	{ return 0.25f; }
	GLfloat dialAftShield() override	{ return 0.75f; }
	OOMissileStatus dialMissileStatus() override	{ return OOMissileStatus::kTargetLocked; }
	OOFuelScoopStatus dialFuelScoopStatus() override	{ return OOFuelScoopStatus::kActive; }
	OOCompassMode getCompassMode() override	{ return OOCompassMode::kStation; }
	bool dialIdentEngaged() override	{ return true; }
	OOAlertCondition getAlertCondition() override	{ return OOAlertCondition::kRed; }
	std::size_t getTrumbleCount() override	{ return 7; }
	int tradeInFactor() override	{ return 80; }
};




namespace {

void SetUp()
{
	static Universe *universe = nullptr;
	if (universe == nullptr)
	{
		universe = new Universe();	// never released
	}
	gSharedUniverse = universe;
	static TestProxyPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestProxyPlayer>();
	gOOPlayer = player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it.
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
}


// An unpiloted ship (a crewed one would ask the universe for a pilot). The proxy, held by its
// ship.
ProxyPlayerEntity *MakeProxy(Entity **outObject = nullptr)
{
	oo::PList::Dict dict{ { "unpiloted", oo::PList(true) } };
	::ShipEntity *ship = oo::RetainedEntity(ProxyPlayerEntity::newProxyObject("proxy", oo::PList(std::move(dict))));
	Entity *object = oo::AutoreleaseEntity(ship);
	if (outObject != nullptr)  *outObject = object;
	return dynamic_cast<ProxyPlayerEntity *>(ship);
}


// The player -copyValuesFromPlayer: reads (-init asserts that it is the only player).
TestDialPlayer *MakeDialPlayer()
{
	PlayerEntity *saved = gOOPlayer;
	gOOPlayer = nullptr;
	TestDialPlayer *player = NewTestPlayer<TestDialPlayer>();
	oo::AutoreleaseEntity(player);	// as [[[TestDialPlayer alloc] init] autorelease]
	gOOPlayer = saved;
	return player;
}

}	// namespace


// The initialiser: the ship set up from its definition, then the proxy's defaults (no fuel scoop
// and no advanced compass in an empty definition).
OO_TEST(initDefaults)
{
	{
		SetUp();
		ProxyPlayerEntity *proxy = MakeProxy();
		OO_CHECK(proxy != nullptr && proxy->getIsShip());
		OO_CHECK(proxy->dialForwardShield() == 1.0f && proxy->dialAftShield() == 1.0f);
		OO_CHECK(proxy->dialFuelScoopStatus() == OOFuelScoopStatus::kNotInstalled);
		OO_CHECK(proxy->compassMode() == OOCompassMode::kBasic);
		OO_CHECK(proxy->tradeInFactor() == 95);
		OO_CHECK(proxy->fuelLeakRate() == 0 && !proxy->massLocked() && !proxy->atHyperspeed());
		OO_CHECK(proxy->dialMissileStatus() == OOMissileStatus::kSafe && !proxy->dialIdentEngaged());
		OO_CHECK(proxy->alertCondition() == OOAlertCondition::kDocked && proxy->trumbleCount() == 0);
	}
}


// Each dial's setter and getter; the fuel leak rate is never negative, and the flags are YES or NO.
OO_TEST(accessors)
{
	{
		SetUp();
		ProxyPlayerEntity *proxy = MakeProxy();
		proxy->setFuelLeakRate(-3.0f);
		OO_CHECK(proxy->fuelLeakRate() == 0);
		proxy->setFuelLeakRate(1.5f);
		OO_CHECK(proxy->fuelLeakRate() == 1.5f);
		proxy->setMassLocked((bool)4);
		OO_CHECK(proxy->massLocked() == true);
		proxy->setMassLocked(false);
		OO_CHECK(proxy->massLocked() == false);
		proxy->setAtHyperspeed((bool)2);
		OO_CHECK(proxy->atHyperspeed() == true);
		proxy->setDialForwardShield(0.5f);
		proxy->setDialAftShield(0.125f);
		OO_CHECK(proxy->dialForwardShield() == 0.5f && proxy->dialAftShield() == 0.125f);
		proxy->setDialMissileStatus(OOMissileStatus::kArmed);
		OO_CHECK(proxy->dialMissileStatus() == OOMissileStatus::kArmed);
		proxy->setDialFuelScoopStatus(OOFuelScoopStatus::kFullHold);
		OO_CHECK(proxy->dialFuelScoopStatus() == OOFuelScoopStatus::kFullHold);
		proxy->setCompassMode(OOCompassMode::kTarget);
		OO_CHECK(proxy->compassMode() == OOCompassMode::kTarget);
		proxy->setDialIdentEngaged((bool)9);
		OO_CHECK(proxy->dialIdentEngaged() == true);
		proxy->setAlertCondition(OOAlertCondition::kYellow);
		OO_CHECK(proxy->alertCondition() == OOAlertCondition::kYellow);
		proxy->setTrumbleCount(12);
		OO_CHECK(proxy->trumbleCount() == 12);
		proxy->setTradeInFactor(42);
		OO_CHECK(proxy->tradeInFactor() == 42);
	}
}


// -copyValuesFromPlayer: takes every dial from the player; nil changes nothing.
OO_TEST(copyValuesFromPlayer)
{
	{
		SetUp();
		ProxyPlayerEntity *proxy = MakeProxy();
		proxy->copyValuesFromPlayer(nullptr);
		OO_CHECK(proxy->tradeInFactor() == 95 && proxy->dialForwardShield() == 1.0f);

		proxy->copyValuesFromPlayer(MakeDialPlayer());
		OO_CHECK(proxy->fuelLeakRate() == 2.5f);
		OO_CHECK(proxy->massLocked() && proxy->atHyperspeed());
		OO_CHECK(proxy->dialForwardShield() == 0.25f && proxy->dialAftShield() == 0.75f);
		OO_CHECK(proxy->dialMissileStatus() == OOMissileStatus::kTargetLocked);
		OO_CHECK(proxy->dialFuelScoopStatus() == OOFuelScoopStatus::kActive);
		OO_CHECK(proxy->compassMode() == OOCompassMode::kStation);
		OO_CHECK(proxy->dialIdentEngaged());
		OO_CHECK(proxy->alertCondition() == OOAlertCondition::kRed);
		OO_CHECK(proxy->trumbleCount() == 7);
		OO_CHECK(proxy->tradeInFactor() == 80);
	}
}


// -isPlayerLikeShip: YES for the proxy.
OO_TEST(isPlayerLikeShip)
{
	{
		SetUp();
		OO_CHECK(MakeProxy()->isPlayerLikeShip());
	}
}


// --- The crossing
// --------------------------------------------------------------------------------

// A proxy's C++ part is a ProxyPlayerEntity under its object, and the ship
// itself; the ship's virtual
// alertCondition() answers the proxy's.
OO_TEST(objCProxyPartIsAProxy)
{
	{
		SetUp();
		Entity *object = nullptr;
		ProxyPlayerEntity *part = MakeProxy(&object);
		Entity *asEntity = object;
		OO_CHECK(part != nullptr);
		OO_CHECK(dynamic_cast<ProxyPlayerEntity *>(asEntity) == part);
		OO_CHECK(part == object);

		part->setAlertCondition(OOAlertCondition::kGreen);
		ShipEntity *asShip = part;
		OO_CHECK(asShip->alertCondition() == OOAlertCondition::kGreen);
		OO_CHECK(part->tradeInFactor() == 95 && part->isPlayerLikeShip());
	}
}


// The proxy's dials by name: the shaders bind them to the proxy's object, which
// answers them for a proxy's part (and a plain ship's object does not); the
// by-name table's rows are answered and called on the C++ proxy.
OO_TEST(dialsAnsweredByNameForAProxy)
{
	{
		SetUp();
		Entity *object = nullptr;
		ProxyPlayerEntity *proxy = MakeProxy(&object);
		proxy->setDialForwardShield(0.5f);
		proxy->setTradeInFactor(42);
		OO_CHECK(oo::EntityRespondsToName(proxy, "dialForwardShield") && oo::EntityRespondsToName(proxy, "tradeInFactor"));
		OOEntityByNameValue dial, factor, condition;
		OO_CHECK(oo::CallEntityByNameTyped(proxy, "dialForwardShield", dial) && static_cast<GLfloat>(dial.real) == 0.5f);
		OO_CHECK(oo::CallEntityByNameTyped(proxy, "tradeInFactor", factor) && factor.integer == 42);
		OO_CHECK(oo::CallEntityByNameTyped(proxy, "alertCondition", condition) && static_cast<OOAlertCondition>(condition.integer) == OOAlertCondition::kDocked);

		ShipEntity *ship = oo::ToShip(oo::autorelease(oo::NewShipObject(oo::makeShared<::ShipEntity>(), "ship", oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } }))));
		OO_CHECK(ship != nullptr && !(ship != nullptr ? oo::EntityRespondsToName(ship, "dialForwardShield") : false));
	}
}

// Visible to scripts: the player and the proxy are ships made in C++ under
// their objects, which ask their C++ parts; they answer YES, and so does a
// plain ship.
OO_TEST(playerAndProxyAreVisibleToScripts)
{
	{
		SetUp();
		Entity *object = nullptr;
		ProxyPlayerEntity *proxy = MakeProxy(&object);
		OO_CHECK(proxy->isVisibleToScripts());
		OO_CHECK(OOJSEntityIsVisibleToScripts(object));

		ShipEntity *player = gOOPlayer;
		OO_CHECK(player->isVisibleToScripts());
		OO_CHECK(OOJSEntityIsVisibleToScripts(player));

		ShipEntity *ship = oo::ToShip(oo::autorelease(oo::NewShipObject(oo::makeShared<::ShipEntity>(), "ship", oo::PList(oo::PList::Dict{ { "unpiloted", oo::PList(true) } }))));
		OO_CHECK(OOJSEntityIsVisibleToScripts(ship));
	}
}


OO_TEST_MAIN()
