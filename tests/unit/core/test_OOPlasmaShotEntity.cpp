/*	test_OOPlasmaShotEntity.mm
	Unit tests for OOPlasmaShotEntity (src/Core/Entities/OOPlasmaShotEntity.h), a turret's plasma
	shot: bead oo-z9md, a leaf of the Entities seam under OOLightParticleEntity (proposed ADR-0056,
	amendments oo-bj8 item 12 and oo-peql).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to answer the time the test sets and to
	record -addEntity: and -removeEntity:, and a plain entity as PLAYER. The ship that fired is a
	plain entity marked as a ship (so it is its own root ship entity; a C++ ship under its object,
	never set up, since bead oo-9ht.144), and the entity hit is an
	entity subclass that records the damage. The expectations were written against the Objective-C
	API and run on the unconverted class first: a shot is a no-draw effect of diameter 12 and
	collision radius 2 with the given position, velocity, energy and colour (always opaque); it
	cannot collide for its first 0.05 seconds; it collides with anything but an effect or its
	owner's ship; it damages what it collides with (unless that is its owner's ship), removes
	itself and leaves a plasma burst where it was; and it removes itself when its time is up. The
	shots are made, and their colour read, through the one block of helpers below, the only lines
	the conversion ported: the shot is now a C++ entity whose Objective-C object is the
	OOLightParticleEntity facade oo::NewEntityFacade made.
	Run: bash tools/check-core-tests.sh
*/

#include "OOPlasmaShotEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#include "OOPlasmaBurstEntity.h"
#include "OOColor.h"
#include "Universe.h"

#include "oo_test.hpp"

#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>() (bead oo-9ht.177): a C++ player under the ship's facade, as
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


// UNIVERSE: never initialised; answers the test's time and records what is added and removed.
class TestUniverse : public Universe
{
public:
	OOTimeAbsolute &_time = universal_time;	// the universe's own state, which its getter answers (bead oo-ql9rn)
	Entity			*_removed = {};
	Entity			*_added = {};

	bool removeEntity(Entity *entity) override	// the C++ entity since bead oo-9ht.39.26; the record is its object, as before
	{
		_removed = entity;
		return YES;
	}
	bool addEntity(Entity *entity) override	// the C++ entity since bead oo-9ht.39.26; the record is its object, as before
	{
		oo::ReleaseEntity(_added);
		_added = oo::RetainEntity(entity);
		return YES;
	}
};


// What the shot hits: records the damage (an Objective-C subclass until bead oo-j12i2; a C++ one
// overriding the member its selector became, recording the C++ entities).
class TestTarget : public Entity
{
public:
	void takeEnergyDamage(double amount, Entity *ent, Entity *other, const std::string &weaponIdentifier) override
	{
		_hits++;
		_amount = amount;
		_from = ent;
		_becauseOf = other;
		_weapon = weaponIdentifier;
	}

	double			_amount = 0;
	Entity		*_from = nullptr;
	Entity		*_becauseOf = nullptr;
	std::string		_weapon;
	int				_hits = 0;
};


// An effect, for the collision test (an Objective-C subclass until bead oo-j12i2).
class TestEffect : public Entity
{
public:
	bool isEffect() override	{ return true; }
};


extern ooscript::Context gOOJSMainThreadContext;	// the engine's (OOJavaScriptEngine.mm)


namespace {

TestUniverse *sUniverse = nil;


void SetUp(OOTimeAbsolute time)
{
	if (sUniverse == nil)
	{
		sUniverse = new TestUniverse();	// never released
	}
	sUniverse->_time = time;
	sUniverse->_removed = nil;
	oo::ReleaseEntity(sUniverse->_added);
	sUniverse->_added = nil;
	gSharedUniverse = sUniverse;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it (the ship stand-in is C++ since bead
	// oo-9ht.144, as test_StationEntity's ships are).
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
}


// --- How the test makes a shot and reads its colour (ported by the conversion), and nothing else -

Entity *Shot(HPVector position, Vector velocity, float energy, OOTimeDelta duration, OOColor *color)
{
	return oo::MadeEntity(OOPlasmaShotEntity::shotWithPosition(position, velocity, energy, duration, color));
}

OOLightParticleEntity *Particle(Entity *shot)	{ return static_cast<OOLightParticleEntity *>(shot); }	// the root's facade since bead oo-9ht.76
const GLfloat *ColorComponents(Entity *shot)	{ return Particle(shot)->_colorComponents; }
void SetColliding(Entity *shot, Entity *other)	{ shot->collidingEntities.emplace_back(other); }
void SetIsShip(Entity *e)						{ e->isShip = true; }

// --------------------------------------------------------------------------------------------------


Entity *RedShot()
{
	return Shot(make_HPvector(1, 2, 3), make_vector(4, 5, 6), 7.0f, 2.0, OOColor::colorWithRed(1.0f, 0.0f, 0.0f, 0.5f).get());
}


// A ship: C++ since bead oo-9ht.144 (its root ship entity is the C++ ship), under its object
// (oo::NewEntityFacade, autoreleased as the plain entity was), never set up, marked as a ship.
Entity *Ship()
{
	Entity *ship = oo::MadeEntity(oo::makeRef<::ShipEntity>());
	SetIsShip(ship);
	return ship;
}

}	// namespace


OO_TEST(shotIsMade)
{
	{
		SetUp(10.0);
		Entity *shot = RedShot();
		OO_CHECK(shot != nil && dynamic_cast<OOLightParticleEntity *>(shot) != nullptr);
		OO_CHECK(HPvector_equal(shot->getPosition(), make_HPvector(1, 2, 3)));
		Vector v = shot->getVelocity();
		OO_CHECK(v.x == 4 && v.y == 5 && v.z == 6);
		OO_CHECK(shot->getEnergy() == 7.0f && shot->collisionRadius() == 2.0f);
		OO_CHECK(Particle(shot)->diameter() == 12.0f);
		OO_CHECK(shot->status() == STATUS_EFFECT && shot->getScanClass() == CLASS_NO_DRAW && shot->isEffect());
		OO_CHECK(shot->getSpawnTime() == 10.0f);
		const GLfloat *c = ColorComponents(shot);
		OO_CHECK(c[0] == 1.0f && c[1] == 0.0f && c[2] == 0.0f && c[3] == 1.0f);	// always opaque
	}
}


OO_TEST(activationDelay)
{
	{
		SetUp(10.0);
		Entity *shot = RedShot();
		OO_CHECK(!shot->canCollide());
		sUniverse->_time = 10.04;
		OO_CHECK(!shot->canCollide());
		sUniverse->_time = 10.06;
		OO_CHECK(shot->canCollide());
	}
}


OO_TEST(collisions)
{
	{
		SetUp(0.0);
		Entity *shot = RedShot();
		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		Entity *effect = oo::MadeEntity(oo::makeRef<TestEffect>());

		// No owner: a plain entity's root ship is nil too.
		OO_CHECK(!shot->checkCloseCollisionWith(plain));

		Entity *ship = Ship();
		shot->setOwner(ship);
		OO_CHECK(shot->checkCloseCollisionWith(plain));
		OO_CHECK(!shot->checkCloseCollisionWith(effect));
		OO_CHECK(!shot->checkCloseCollisionWith(ship));	// its own ship
		OO_CHECK(shot->checkCloseCollisionWith(Ship()));
		OO_CHECK(shot->checkCloseCollisionWith(nil));
	}
}


OO_TEST(hitDamagesAndBursts)
{
	{
		SetUp(0.0);
		Entity *shot = RedShot();
		Entity *ship = Ship();
		shot->setOwner(ship);

		// Its own ship is not hit.
		SetColliding(shot, ship);
		sUniverse->_time = 0.1;
		shot->update(0.1);
		OO_CHECK(sUniverse->_removed == nil && sUniverse->_added == nil);

		TestTarget *target = static_cast<TestTarget *>(oo::MadeEntity(oo::makeRef<TestTarget>()));
		SetColliding(shot, target);
		shot->update(0.1);
		OO_CHECK(target->_hits == 1 && target->_amount == 7.0 && target->_from == shot && target->_becauseOf == ship);
		OO_CHECK(target->_weapon == "EQ_WEAPON_PLASMA_SHOT");
		OO_CHECK(sUniverse->_removed == shot);
		Entity *burst = sUniverse->_added;
		OO_CHECK(burst != nil && burst != shot && dynamic_cast<OOPlasmaBurstEntity *>(burst) != nullptr);	// a C++ entity (oo-l2s5)
		OO_CHECK(HPvector_equal(burst->getPosition(), shot->getPosition()));
	}
}


OO_TEST(expires)
{
	{
		SetUp(0.0);
		Entity *shot = RedShot();
		sUniverse->_time = 1.0;
		shot->update(1.0);
		OO_CHECK(sUniverse->_removed == nil);
		sUniverse->_time = 2.5;
		shot->update(1.5);
		OO_CHECK(sUniverse->_removed == shot);
	}
}


OO_TEST_MAIN()
