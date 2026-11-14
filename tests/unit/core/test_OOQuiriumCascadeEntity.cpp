/*	test_OOQuiriumCascadeEntity.mm
	Unit tests for OOQuiriumCascadeEntity (src/Core/Entities/OOQuiriumCascadeEntity.h), the
	expanding sphere of a quirium cascade.

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised, of a test subclass that records what is removed, and a
	plain entity as PLAYER. The ship it is made from is a plain entity too: the class asks it only
	for its position and owner (a C++ ship under its object, never set up). Nil from a nil ship;
	what it takes from the ship; that it is the cascade weapon (and other entities are not); the
	collision delay, the expansion, the energy it deals to what it collides with, and its removal
	after twenty seconds; its description. Making a cascade goes through the helper below: it is
	made by its factory as an Entity. Run: bash
	tools/check-core-tests.sh
*/

#include "OOQuiriumCascadeEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++
#include "OODescription.h"
#include "Universe.h"

#include "oo_test.hpp"

#include <cmath>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>(): a C++ player, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1).
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


static Entity *sRemoved = nil;


// UNIVERSE: never initialised; records what is removed.
class TestUniverse : public Universe
{
public:
	bool removeEntity(Entity *entity) override	{ sRemoved = entity; return YES; }	// the C++ entity; the record is its object
};


// What the cascade collides with: records the damage it is dealt (a C++ one
// overriding the member, recording the C++ entities).
class TestVictim : public Entity
{
public:
	void takeEnergyDamage(double amount, Entity *ent, Entity *other, const std::string &weaponIdentifier) override
	{
		_damage = amount;
		_from = ent;
		_becauseOf = other;
		_weapon = weaponIdentifier;
	}

	double			_damage = 0;
	Entity		*_from = nullptr;
	Entity		*_becauseOf = nullptr;
	std::string		_weapon;
};


extern JSContext *gOOJSMainThreadContext;	// the engine's (OOJavaScriptEngine.mm)


namespace {

// --- How a cascade is made, and nothing else --------------------------------------------------------

Entity *MakeCascade(ShipEntity *ship)	{ return oo::MadeEntity(OOQuiriumCascadeEntity::quiriumCascadeFromShip(ship)); }

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = new TestUniverse();	// never released
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request
  // on the main thread's context, so there is one, with nothing in it (the ship
  // stand-in is C++, as test_StationEntity's ships are).
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	sRemoved = nil;
}

}	// namespace


OO_TEST(fromShip)
{
	{
		SetUp();
		OO_CHECK(MakeCascade(nil) == nil);

		Entity *ship = oo::MadeEntity(oo::makeRef<::ShipEntity>());	// a C++ ship under its object, never set up
		Entity *shipOwner = oo::MadeEntity(oo::makeRef<Entity>());
		ship->setPosition(make_HPvector(5, 6, 7));
		ship->setOwner(shipOwner);

		Entity *cascade = MakeCascade(oo::ToShip(ship));
		OO_CHECK(cascade != nil);
		OO_CHECK(HPvector_equal(cascade->getPosition(), make_HPvector(5, 6, 7)));
		OO_CHECK(cascade->status() == STATUS_EFFECT && cascade->getScanClass() == CLASS_MINE);
		OO_CHECK(cascade->owner() == shipOwner);
		OO_CHECK(cascade->isEffect() && OOEntityIsCascadeWeapon(cascade));	// -isCascadeWeapon
		OO_CHECK(!OOEntityIsCascadeWeapon(ship));
		OO_CHECK(!cascade->canCollide() && cascade->checkCloseCollisionWith(nil) && cascade->checkCloseCollisionWith(ship));
		OO_CHECK(oo::EntityDescription(cascade).starts_with("<OOQuiriumCascadeEntity 0x"));
		OO_CHECK(oo::EntityDescription(cascade).ends_with("{0.000000 seconds passed of 20.000000}"));

		// Nothing is drawn in the opaque pass.
		cascade->drawImmediate(false, false);
	}
}


OO_TEST(update)
{
	{
		SetUp();
		Entity *ship = oo::MadeEntity(oo::makeRef<::ShipEntity>());	// a C++ ship under its object, never set up
		Entity *shipOwner = oo::MadeEntity(oo::makeRef<Entity>());
		ship->setOwner(shipOwner);
		Entity *cascade = MakeCascade(oo::ToShip(ship));
		TestVictim *victim = static_cast<TestVictim *>(oo::MadeEntity(oo::makeRef<TestVictim>()));
		cascade->getCollidingEntities()->emplace_back(victim);

		// A tenth of a second: past the collision delay, expanding, and dealing energy.
		cascade->update(0.1);
		OO_CHECK(cascade->canCollide());
		OO_CHECK(fabs(cascade->collisionRadius() - 100.0f) < 1e-3);
		const double energy = 0.1 * (100000 - 90000 * (0.1 / 20.0));
		OO_CHECK(fabs(cascade->getEnergy() - energy) < 1e-2);
		OO_CHECK(fabs(victim->_damage - energy) < 1e-2);
		OO_CHECK(victim->_from == cascade && victim->_becauseOf == shipOwner && victim->_weapon == "EQ_QC_MINE");
		OO_CHECK(oo::EntityDescription(cascade).ends_with("{0.100000 seconds passed of 20.000000}"));
		OO_CHECK(sRemoved == nil);

		// Twenty seconds: removed.
		cascade->update(20.0);
		OO_CHECK(sRemoved == cascade);
	}
}


OO_TEST_MAIN()
