/*	test_OOExhaustPlumeEntity.mm
	Unit tests for OOExhaustPlumeEntity (src/Core/Entities/OOExhaustPlumeEntity.h), the engine
	plumes ships carry as subentities: bead oo-y86f, a leaf of the Entities seam with a facade
	(proposed ADR-0056, amendments oo-bj8 item 12, oo-0mxi and oo-2c6g).

	The entity reads Universe and its ship, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to answer the time the test sets, a
	plain entity as PLAYER, and as the ship an entity that answers the ShipEntity selectors the
	plume sends. The RNG is seeded, as the game seeds it, so the plume's random fluctuations repeat.
	The expectations were written against the Objective-C API and run on the unconverted class
	first: a plume is made for its ship from six tokens (position and scale, scaled by the ship's
	scale but for the scale's z, which outside 0.5..2 is 1), and from none is nil; its scale
	accessors; it is an exhaust (and an entity is not); its collision radius is what -update: last
	measured; -update: does nothing without a visible ship, measures nothing below a minimal speed,
	and otherwise measures the plume (the value the Objective-C class computed is pinned);
	-rescaleBy: scales it and -rescaleBy:writeToCache: does nothing; and its texture is loaded
	once, by name (the loader replaced as in test_OOParticleSystem). The collision radius is set
	through the one helper below. The plumes are made by the class method the ship sends, which the
	conversion kept on the facade: the last test pins that their object is a C++ entity whose
	Objective-C object is the OOExhaustPlumeEntity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "OOExhaustPlumeEntity.h"
#import "OOColor.h"
#import "OOTexture.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>
#include <optional>
#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


@interface TestPlayer: Entity
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }

@end


// UNIVERSE: never initialised; answers the test's time.
@interface TestUniverse: Universe
{
@public
	OOTimeAbsolute	_time;
}
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return _time; }

@end


// The plume's ship: answers what the plume asks a ShipEntity.
@interface TestShip: Entity
{
@public
	BOOL		_visible;
	GLfloat		_speedFactor;
}
@end


@implementation TestShip

- (BOOL) isVisible							{ return _visible; }
- (BOOL) suppressFlightNotifications		{ return NO; }
- (OOColor *) exhaustEmissiveColor			{ return [OOColor colorWithRed:0.7f green:0.9f blue:1.0f alpha:0.9f]; }
- (Vector) forwardVector					{ return make_vector(0, 0, 1); }
- (Vector) rightVector						{ return make_vector(1, 0, 0); }
- (Vector) upVector							{ return make_vector(0, 1, 0); }
- (int) damage								{ return 0; }
- (GLfloat) speedFactor						{ return _speedFactor; }
- (GLfloat) flightSpeed						{ return 100.0f * _speedFactor; }

@end


namespace {

TestUniverse *sUniverse = nil;

// The texture loader's stand-in.
std::optional<std::string> sTextureName;
id sTexture = nil;

id LoadTexture(id, SEL, const std::optional<std::string> &name, const std::optional<std::string> &, OOTextureFlags, GLfloat, GLfloat)
{
	sTextureName = name;
	return sTexture;
}


void SetUp(OOTimeAbsolute time)
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		sTexture = [[OOWeakRefObject alloc] init];	// never released
		Method loader = class_getClassMethod([OOTexture class], @selector(cxx_textureWithName:inFolder:options:anisotropy:lodBias:));
		method_setImplementation(loader, (IMP)LoadTexture);
	}
	sUniverse->_time = time;
	gSharedUniverse = sUniverse;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	ranrot_srand(12345);
}


// --- Ivars the test sets, and nothing else ---------------------------------------------------------

void SetCollisionRadius(Entity *e, GLfloat value)	{ e->_cxxEntity->collision_radius = value; }

// --------------------------------------------------------------------------------------------------


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-3;
}


bool VectorIs(Vector v, float x, float y, float z)
{
	return v.x == x && v.y == y && v.z == z;
}


TestShip *Ship()
{
	TestShip *ship = [[[TestShip alloc] init] autorelease];
	ship->_visible = YES;
	ship->_speedFactor = 1.0f;
	return ship;
}


OOExhaustPlumeEntity *Plume(Entity *ship, std::vector<std::string> tokens, float scale)
{
	return [OOExhaustPlumeEntity exhaustForShip:(ShipEntity *)ship withDefinition:tokens andScale:scale];
}

}	// namespace


OO_TEST(made)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *ship = Ship();
		OOExhaustPlumeEntity *plume = Plume(ship, { "1", "2", "3", "4", "5", "1.5" }, 2.0f);
		OO_CHECK(plume != nil && [plume isKindOfClass:[OOExhaustPlumeEntity class]]);
		OO_CHECK([plume owner] == ship);
		OO_CHECK(HPvector_equal([plume position], make_HPvector(2, 4, 6)));
		OO_CHECK(VectorIs([plume scale], 8, 10, 1.5f));	// z is not scaled
		OO_CHECK([plume isExhaust] && ![ship isExhaust]);
		OO_CHECK([plume findCollisionRadius] == 0.0);

		OO_CHECK(Plume(ship, {}, 1.0f) == nil);
	}
}


OO_TEST(scaleZ)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *ship = Ship();
		OO_CHECK(VectorIs([Plume(ship, { "0", "0", "0", "1", "1", "0.4" }, 1.0f) scale], 1, 1, 1));
		OO_CHECK(VectorIs([Plume(ship, { "0", "0", "0", "1", "1", "2.5" }, 1.0f) scale], 1, 1, 1));
		OOExhaustPlumeEntity *plume = Plume(ship, { "0", "0", "0", "1", "1", "2" }, 1.0f);
		OO_CHECK(VectorIs([plume scale], 1, 1, 2));
		[plume setScale:make_vector(3, 4, 0.5f)];
		OO_CHECK(VectorIs([plume scale], 3, 4, 0.5f));
		[plume setScale:make_vector(3, 4, 0.0f)];
		OO_CHECK(VectorIs([plume scale], 3, 4, 1));
	}
}


OO_TEST(rescale)
{
	@autoreleasepool
	{
		SetUp(0.0);
		OOExhaustPlumeEntity *plume = Plume(Ship(), { "0", "0", "0", "1", "2", "1.5" }, 1.0f);
		[plume rescaleBy:2.0f];
		OO_CHECK(VectorIs([plume scale], 2, 4, 3));		// z too: no clamp here
		[plume rescaleBy:5.0f writeToCache:YES];
		OO_CHECK(VectorIs([plume scale], 2, 4, 3));
	}
}


OO_TEST(updateWithoutVisibleShip)
{
	@autoreleasepool
	{
		SetUp(1.0);
		TestShip *ship = Ship();
		OOExhaustPlumeEntity *plume = Plume(ship, { "0", "0", "-10", "2", "2", "1" }, 1.0f);
		SetCollisionRadius(plume, 42.0f);
		ship->_visible = NO;
		[plume update:0.1];
		OO_CHECK([plume findCollisionRadius] == 42.0);

		[plume setOwner:nil];
		[plume update:0.1];
		OO_CHECK([plume findCollisionRadius] == 42.0);
	}
}


OO_TEST(updateBelowMinimalSpeed)
{
	@autoreleasepool
	{
		SetUp(1.0);
		TestShip *ship = Ship();
		OOExhaustPlumeEntity *plume = Plume(ship, { "0", "0", "-10", "2", "2", "1" }, 1.0f);
		SetCollisionRadius(plume, 42.0f);
		ship->_speedFactor = 0.0005f;
		[plume update:0.1];
		OO_CHECK([plume findCollisionRadius] == 0.0);
	}
}


OO_TEST(updateMeasures)
{
	@autoreleasepool
	{
		SetUp(1.0);
		TestShip *ship = Ship();
		OOExhaustPlumeEntity *plume = Plume(ship, { "0", "0", "-10", "2", "2", "1" }, 1.0f);
		[plume resetPlume];
		[plume update:0.1];
		// What the Objective-C class measured, with this seed.
		OO_CHECK(Near([plume findCollisionRadius], 14.464036));
	}
}


OO_TEST(texture)
{
	@autoreleasepool
	{
		SetUp(0.0);
		OOExhaustPlumeEntity *plume = Plume(Ship(), { "0", "0", "0", "1", "1", "1" }, 1.0f);
		sTextureName.reset();
		OO_CHECK([plume texture] == sTexture);
		OO_CHECK(sTextureName == std::optional<std::string>("oolite-exhaust-blur.png"));
		sTextureName.reset();
		OO_CHECK([plume texture] == sTexture && [OOExhaustPlumeEntity plumeTexture] == sTexture);
		OO_CHECK(!sTextureName.has_value());	// loaded once
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp(0.0);
		OOExhaustPlumeEntity *plume = Plume(Ship(), { "0", "0", "0", "1", "1", "1" }, 1.0f);
		OO_CHECK([plume class] == [OOExhaustPlumeEntity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<cxx::OOExhaustPlumeEntity *>(oo::ToCxx(plume)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(plume)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(plume)) == plume);
	}
}


OO_TEST_MAIN()
