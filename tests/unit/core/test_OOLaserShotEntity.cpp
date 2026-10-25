/*	test_OOLaserShotEntity.mm
	Unit tests for OOLaserShotEntity (src/Core/Entities/OOLaserShotEntity.h), the beam a ship's laser
	draws for one shot: bead oo-5zpq, a leaf of the Entities pattern seam (amendment oo-bj8 item 12).

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised, of a test subclass that records what is removed, and a plain
	entity as PLAYER. The ship that fires is an entity of the test's own that answers the selectors
	the class sends a ship (its root ship, speed and weapon range); the class asserts that it is a
	ship, so the test sets that flag. Since bead oo-9ht.144 it is a C++ ship whose fields give the
	same answers. The expectations were written against the Objective-C API and
	run on the unconverted class first (bead oo-9ht.78 then deleted the Objective-C facade, ADR-0049
	and the standing approval oo-9n5p9: the cases ask the C++ class what they asked the facade, with
	every expectation kept except the facade's own class check, [shot class] == [OOLaserShotEntity
	class]; the shots are made as the ship makes them, laserFromShip() then oo::NewEntityFacade): where the shot starts and how it is turned for each facing,
	its velocity, owner, range and status; its colour (default red, a set colour brightened, the
	alpha constant); the lifetime in its description; following the player's ship; removal when its
	lifetime has run out. The colour is private; the test reads it through the access struct below,
	the only lines the conversion ported (amendment oo-862e item 2).
	Run: bash tools/check-core-tests.sh
*/

#include "OOLaserShotEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#include "OOColor.h"
#include "OODescription.h"
#include "Universe.h"

#include "oo_test.hpp"

#include <cmath>


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


static Entity *sRemoved = nil;


// UNIVERSE: never initialised; records what is removed.
class TestUniverse : public Universe
{
public:
	bool removeEntity(Entity *entity) override	{ sRemoved = entity; return YES; }	// the C++ entity since bead oo-9ht.39.26; the record is its object, as before
};




// --- The private colour, and nothing else ---------------------------------------------------------

struct OOLaserShotEntityTestAccess
{
	static const GLfloat *Color(OOLaserShotEntity *e)	{ return e->_color; }
};

// --------------------------------------------------------------------------------------------------


extern ooscript::Context gOOJSMainThreadContext;	// the engine's (OOJavaScriptEngine.mm)


namespace {

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
	// The ship's -dealloc sends its (absent) scripts entityDestroyed in a request on the main
	// thread's context, so there is one, with nothing in it (the ship stand-in is C++ since bead
	// oo-9ht.144, as test_StationEntity's ships are).
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
	sRemoved = nil;
}


// The ship that fires: what OOLaserShotEntity asks of a ShipEntity (its root ship, itself; its speed
// and weapon range). C++ since bead oo-9ht.144 deleted the Objective-C ship: the class calls the
// ship's members, so it is a C++ ship (never set up) under its object (oo::NewEntityFacade,
// autoreleased as the test's entity was) whose fields give those answers.
Entity *MakeShip()
{
	oo::Ref<::ShipEntity> part = oo::makeRef<::ShipEntity>();
	Entity *ship = oo::MadeEntity(part);
	part->isShip = YES;
	part->flightSpeed = 50.0f;
	part->weaponRange = 1000.0f;
	ship->setPosition(make_HPvector(100, 0, 0));
	return ship;
}


// A shot, made as the ship makes one: its Objective-C object is autoreleased in the test's pool and
// holds it.
oo::Ref<OOLaserShotEntity> Shot(Entity *ship, OOWeaponFacing direction, Vector offset)
{
	oo::Ref<OOLaserShotEntity> shot = OOLaserShotEntity::laserFromShip(oo::ToShip(ship), direction, offset);
	oo::MadeEntity(shot);
	return shot;
}


bool Near(double a, double b)  { return fabs(a - b) < 1e-4; }


bool ColorIs(OOLaserShotEntity *e, GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
	const GLfloat *c = OOLaserShotEntityTestAccess::Color(e);
	return Near(c[0], r) && Near(c[1], g) && Near(c[2], b) && Near(c[3], a);
}

}	// namespace


OO_TEST(laserFromShip)
{
	{
		SetUp();
		Entity *ship = MakeShip();
		oo::Ref<OOLaserShotEntity> shot = Shot(ship, WEAPON_FACING_FORWARD, make_vector(0, 0, 10));
		OO_CHECK(shot != nullptr);
		OO_CHECK(HPvector_equal(shot->getPosition(), make_HPvector(100, 0, 10)));
		OO_CHECK(vector_equal(shot->getVelocity(), make_vector(0, 0, 50)));
		OO_CHECK(quaternion_equal(shot->getOrientation(), kIdentityQuaternion));
		OO_CHECK(shot->owner() == ship);
		OO_CHECK(shot->collisionRadius() == 1000.0f);
		OO_CHECK(shot->status() == STATUS_EFFECT && shot->isEffect() && !shot->canCollide());
		OO_CHECK(ColorIs(shot.get(), 1.0f / 3.0f, 0.0f, 0.0f, 0.09f));
		OO_CHECK(oo::EntityDescription(shot.get()).starts_with("<OOLaserShotEntity 0x"));
		OO_CHECK(oo::EntityDescription(shot.get()).find("{ttl: 0.090s - position: (100, 0, 10)") != std::string::npos);

		// The other facings turn the shot about the ship's up axis.
		oo::Ref<OOLaserShotEntity> aft = Shot(ship, WEAPON_FACING_AFT, kZeroVector);
		Vector forward = vector_forward_from_quaternion(aft->getOrientation());
		OO_CHECK(Near(forward.x, 0) && Near(forward.z, -1));
		oo::Ref<OOLaserShotEntity> port = Shot(ship, WEAPON_FACING_PORT, kZeroVector);
		oo::Ref<OOLaserShotEntity> starboard = Shot(ship, WEAPON_FACING_STARBOARD, kZeroVector);
		Vector portForward = vector_forward_from_quaternion(port->getOrientation());
		Vector starboardForward = vector_forward_from_quaternion(starboard->getOrientation());
		OO_CHECK(Near(fabs(portForward.x), 1) && Near(portForward.x, -starboardForward.x) && Near(portForward.z, 0));
	}
}


OO_TEST(color)
{
	{
		SetUp();
		oo::Ref<OOLaserShotEntity> shot = Shot(MakeShip(), WEAPON_FACING_FORWARD, kZeroVector);
		// Brightened five times, then a third; the alpha stays.
		shot->setColor(OOColor::colorWithRed(0.3f, 0.6f, 0.9f, 0.1f).get());
		OO_CHECK(ColorIs(shot.get(), 0.5f, 1.0f, 1.5f, 0.09f));
		shot->setColor(nullptr);
		OO_CHECK(ColorIs(shot.get(), 0.0f, 0.0f, 0.0f, 0.09f));

		shot->setRange(250.0f);
		OO_CHECK(shot->collisionRadius() == 250.0f);

		// Nothing is drawn in the opaque pass.
		shot->drawImmediate(false, false);
	}
}


OO_TEST(update)
{
	{
		SetUp();
		Entity *ship = MakeShip();
		oo::Ref<OOLaserShotEntity> shot = Shot(ship, WEAPON_FACING_FORWARD, make_vector(0, 0, 10));

		// An NPC's shot moves by its velocity.
		shot->update(0.05);
		OO_CHECK(HPvector_equal(shot->getPosition(), make_HPvector(100, 0, 12.5)));
		OO_CHECK(sRemoved == nil);
		shot->update(0.05);
		OO_CHECK(sRemoved == shot.get());

		// The player's shot is put back where its ship's laser is.
		sRemoved = nil;
		ship->isPlayer = YES;
		oo::Ref<OOLaserShotEntity> playerShot = Shot(ship, WEAPON_FACING_FORWARD, make_vector(0, 0, 10));
		ship->setPosition(make_HPvector(200, 0, 0));
		playerShot->update(0.05);
		OO_CHECK(HPvector_equal(playerShot->getPosition(), make_HPvector(200, 0, 10)));
		OO_CHECK(quaternion_equal(playerShot->getOrientation(), kIdentityQuaternion));
		OO_CHECK(sRemoved == nil);
	}
}


OO_TEST_MAIN()
