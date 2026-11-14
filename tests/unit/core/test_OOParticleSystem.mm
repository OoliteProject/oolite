/*	test_OOParticleSystem.mm
	Unit tests for OOParticleSystem and its subclasses OOSmallFragmentBurstEntity,
	OOBigFragmentBurstEntity (src/Core/Entities/OOParticleSystem.h) and OOExplosionCloudEntity
	(OOExplosionCloudEntity.h), the particle clouds of an explosion: bead oo-cenx, which converts the
	class with all its subclasses (proposed ADR-0056, amendments oo-bj8 item 12 and oo-kdyh item 1),
	so bead oo-ui7h's class is tested here too.

	The entities read Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to record -removeEntity:, and a plain
	entity as PLAYER. The explosion cloud loads its texture by name: the test replaces OOTexture's
	loader with one that records the name and answers a stand-in object (or nil, for "not found").
	The particles themselves are random (the RNG is seeded, as the game seeds it) and private; what
	the game sees is checked. The expectations were written against the Objective-C API and run on
	the unconverted classes first (but for "not made without its texture", which crashed there in
	the Entity facade's -dealloc of an entity whose -init never ran, bead oo-s6ic6): each cloud
	starts at its source with the source's velocity (the big burst's slowed, the cloud's capped at
	1000), is a no-draw effect that cannot collide, collides with anything but an effect, grows its
	collision radius at its fastest particle's speed, describes its time to live, and removes
	itself when that runs out; the cloud reads its settings (duration, size, spread, texture) and is
	not made without its texture. The clouds are made through the one block of helpers below, the
	only lines the conversion ported: each is now a C++ entity whose Objective-C object is the
	Entity facade oo::NewEntityFacade made.
	Run: bash tools/check-core-tests.sh
*/

#import "OOParticleSystem.h"
#import "OOExplosionCloudEntity.h"
#import "OOTexture.h"
#import "OODescription.h"
#import "Universe.h"
#import "legacy_random.h"

#include "oo_test.hpp"
#include "oofnd/PList.hpp"

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


// UNIVERSE: never initialised; records what is removed.
@interface TestUniverse: Universe
{
@public
	Entity	*_removed;
}
@end


@implementation TestUniverse

- (BOOL) removeEntity:(Entity *)entity
{
	_removed = entity;
	return YES;
}

@end


// An effect, for the collision test.
@interface TestEffect: Entity
@end


@implementation TestEffect

- (BOOL) isEffect	{ return YES; }

@end


namespace {

TestUniverse *sUniverse = nil;

// The texture loader's stand-in.
std::optional<std::string> sTextureName;
bool sTextureFound = true;
id sTexture = nil;

id LoadTexture(id, SEL, const std::optional<std::string> &name, const std::optional<std::string> &, OOTextureFlags, GLfloat, GLfloat)
{
	sTextureName = name;
	return sTextureFound ? sTexture : nil;
}


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		sUniverse->_cxxUniverse = oo::makeRef<cxx::Universe>(sUniverse);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
		sTexture = [[OOWeakRefObject alloc] init];	// never released
		Method loader = class_getClassMethod([OOTexture class], @selector(cxx_textureWithName:inFolder:options:anisotropy:lodBias:));
		method_setImplementation(loader, (IMP)LoadTexture);
	}
	sUniverse->_removed = nil;
	gSharedUniverse = sUniverse;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
	sTextureName.reset();
	sTextureFound = true;
	ranrot_srand(12345);	// the game seeds its RNG at start-up; unseeded, OORandomUnitVector() never ends
}


// --- How the test makes a cloud (ported by the conversion), and nothing else ---------------------

Entity *SmallBurst(Entity *source)	{ return oo::NewEntityFacade(OOSmallFragmentBurstEntity::fragmentBurstFromEntity(source)); }
Entity *BigBurst(Entity *source)	{ return oo::NewEntityFacade(OOBigFragmentBurstEntity::fragmentBurstFromEntity(source)); }
Entity *Cloud(Entity *source, const oo::PList &settings)	{ return oo::NewEntityFacade(OOExplosionCloudEntity::explosionCloudFromEntity(source, settings)); }
Entity *SizedCloud(Entity *source, float size, const oo::PList &settings)	{ return oo::NewEntityFacade(OOExplosionCloudEntity::explosionCloudFromEntity(source, size, settings)); }

// --------------------------------------------------------------------------------------------------


Entity *Source(Vector velocity)
{
	Entity *source = [[[Entity alloc] init] autorelease];
	[source setCollisionRadius:10.0f];
	[source setPosition:make_HPvector(1, 2, 3)];
	[source setVelocity:velocity];
	return source;
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


bool VectorNear(Vector a, Vector b)
{
	return Near(a.x, b.x) && Near(a.y, b.y) && Near(a.z, b.z);
}


// What every particle cloud is.
bool IsParticleEffect(Entity *cloud)
{
	return cloud != nil && HPvector_equal([cloud position], make_HPvector(1, 2, 3)) && [cloud status] == STATUS_EFFECT
		&& [cloud scanClass] == CLASS_NO_DRAW && [cloud isEffect] && ![cloud canCollide] && [cloud collisionRadius] == 0
		&& [cloud owner] == nil;
}


// Grows at the given speed, lives the given time, then removes itself.
bool GrowsAndExpires(Entity *cloud, double speed, double duration)
{
	[cloud update:0.5];
	bool ok = Near([cloud collisionRadius], 0.5 * speed) && sUniverse->_removed == nil;
	[cloud update:duration - 0.5];
	ok = ok && sUniverse->_removed == nil;
	[cloud update:0.01];
	return ok && sUniverse->_removed == cloud;
}

}	// namespace


OO_TEST(smallFragmentBurst)
{
	@autoreleasepool
	{
		SetUp();
		Entity *burst = SmallBurst(Source(make_vector(4, 5, 6)));
		OO_CHECK(IsParticleEffect(burst));
		OO_CHECK(VectorNear([burst velocity], make_vector(4, 5, 6)));
		OO_CHECK(oo::DescriptionOf(burst).starts_with("<OOSmallFragmentBurstEntity 0x"));
		OO_CHECK(oo::DescriptionOf(burst).ends_with("{ttl: 1.500s}"));
		OO_CHECK(GrowsAndExpires(burst, 400, 1.5));
	}
}


OO_TEST(bigFragmentBurst)
{
	@autoreleasepool
	{
		SetUp();
		Entity *burst = BigBurst(Source(make_vector(100, 0, 0)));
		OO_CHECK(IsParticleEffect(burst));
		OO_CHECK(VectorNear([burst velocity], make_vector(85, 0, 0)));
		OO_CHECK(oo::DescriptionOf(burst).starts_with("<OOBigFragmentBurstEntity 0x"));
		OO_CHECK(oo::DescriptionOf(burst).ends_with("{ttl: 1.000s}"));
		OO_CHECK(GrowsAndExpires(burst, 4.0 * (1.0 + 10.0 * 0.5), 1.0));	// four times 1 + half the radius
	}
}


OO_TEST(collisions)
{
	@autoreleasepool
	{
		SetUp();
		Entity *burst = SmallBurst(Source(kZeroVector));
		Entity *other = Source(kZeroVector);
		Entity *effect = [[[TestEffect alloc] init] autorelease];
		OO_CHECK([burst checkCloseCollisionWith:other]);
		OO_CHECK(![burst checkCloseCollisionWith:effect]);
		OO_CHECK(![burst checkCloseCollisionWith:nil]);	// nil is its (nil) owner
		OO_CHECK(![burst checkCloseCollisionWith:BigBurst(other)]);
	}
}


OO_TEST(explosionCloudDefaults)
{
	@autoreleasepool
	{
		SetUp();
		Entity *cloud = Cloud(Source(make_vector(0, 3000, 4000)), oo::PList());
		OO_CHECK(IsParticleEffect(cloud));
		OO_CHECK(sTextureName == std::optional<std::string>("oolite-particle-cloud2.png"));
		OO_CHECK(VectorNear([cloud velocity], make_vector(0, 600, 800)));	// capped at 1000
		OO_CHECK(oo::DescriptionOf(cloud).starts_with("<OOExplosionCloudEntity 0x"));
		OO_CHECK(oo::DescriptionOf(cloud).ends_with("{ttl: 0.900s}"));
		// Size 2.5 radii, particles up to 1.2 times as fast.
		OO_CHECK(GrowsAndExpires(cloud, 10.0 * 2.5 * 1.2, 0.9));

		// A slow source keeps its velocity.
		OO_CHECK(VectorNear([Cloud(Source(make_vector(0, 30, 40)), oo::PList()) velocity], make_vector(0, 30, 40)));
	}
}


OO_TEST(explosionCloudSettings)
{
	@autoreleasepool
	{
		SetUp();
		oo::PList::Dict settings;
		settings["duration"] = oo::PList(2.0);
		settings["size"] = oo::PList(4.0);
		settings["spread"] = oo::PList(0.5);
		settings["texture"] = oo::PList(std::string("test-cloud.png"));
		Entity *cloud = Cloud(Source(kZeroVector), oo::PList(settings));
		OO_CHECK(IsParticleEffect(cloud));
		OO_CHECK(sTextureName == std::optional<std::string>("test-cloud.png"));
		OO_CHECK(oo::DescriptionOf(cloud).ends_with("{ttl: 2.000s}"));
		OO_CHECK(GrowsAndExpires(cloud, 10.0 * 4.0 * 1.2 * 0.5, 2.0));

		// An explicit size wins over the settings' factor.
		SetUp();
		Entity *sized = SizedCloud(Source(kZeroVector), 50.0f, oo::PList(settings));
		OO_CHECK(GrowsAndExpires(sized, 50.0 * 1.2 * 0.5, 2.0));
	}
}


OO_TEST(explosionCloudNeedsItsTexture)
{
	@autoreleasepool
	{
		SetUp();
		sTextureFound = false;
		OO_CHECK(Cloud(Source(kZeroVector), oo::PList()) == nil);
		OO_CHECK(SizedCloud(Source(kZeroVector), 5.0f, oo::PList()) == nil);
	}
}


OO_TEST_MAIN()
