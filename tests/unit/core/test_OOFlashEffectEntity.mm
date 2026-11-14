/*	test_OOFlashEffectEntity.mm
	Unit tests for OOFlashEffectEntity (src/Core/Entities/OOFlashEffectEntity.h), the white flash
	of an explosion and the coloured flash where a laser hits: bead oo-wue8, a leaf of the Entities
	seam under OOLightParticleEntity (proposed ADR-0056, amendments oo-bj8 item 12, oo-0otc and
	oo-0mxi).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised, subclassed to answer the time the test sets and to
	record -removeEntity:, and a plain entity as PLAYER. The expectations were written against the
	Objective-C API and run on the unconverted class first: an explosion flash sits where its
	entity is, moves with it, starts at its collision radius, is white and grows at 150 times its
	size a second (at least 600) to half opacity; a laser flash starts at diameter 1 in the given
	colour and grows at 150 a second to full opacity; both fade in over two thirds of their life
	(0.4 and 0.3 seconds) and out over the rest, and remove themselves when their time is up. The
	diameter and colour components, ivars of OOLightParticleEntity, are read through the one block
	of helpers below. Its texture is loaded once, by name (the loader replaced as in
	test_OOParticleSystem). The flashes are made by the C++ factories the callers call and handed to
	Objective-C with oo::NewEntityFacade, as the callers do since bead oo-9ht.106 deleted the class's
	Objective-C facade: the class's own selectors are member calls,
	the root's are still sent to the object, and the last test pins that the object is a C++
	entity's (the root Entity's facade).
	Run: bash tools/check-core-tests.sh
*/

#import "OOFlashEffectEntity.h"
#import "PlayerEntity.h"	// PLAYER is C++
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

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// NewTestPlayer<TestPlayer>(): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	@autoreleasepool
	{
		[oo::NewEntityFacade(player) retain];
	}
	return player.get();
}


// UNIVERSE: never initialised; answers the test's time and records what is removed.
@interface TestUniverse: Universe
{
@public
	OOTimeAbsolute	_time;
	Entity			*_removed;
}
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return _time; }


- (BOOL) removeEntity:(Entity *)entity
{
	_removed = entity;
	return YES;
}

@end


namespace {

TestUniverse *sUniverse = nil;

// The texture loader's stand-in (as in test_OOParticleSystem).
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
		sUniverse->_cxxUniverse = oo::makeRef<cxx::Universe>(sUniverse);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
		sTexture = [[OOWeakRefObject alloc] init];	// never released
		Method loader = class_getClassMethod([OOTexture class], @selector(cxx_textureWithName:inFolder:options:anisotropy:lodBias:));
		method_setImplementation(loader, (IMP)LoadTexture);
	}
	sUniverse->_time = time;
	sUniverse->_removed = nil;
	gSharedUniverse = sUniverse;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
}


// --- Ivars of OOLightParticleEntity the test reads, and nothing else ------------------------------

const GLfloat *ColorComponents(Entity *e)	{ return static_cast<OOLightParticleEntity *>(oo::ToCxx(e))->_colorComponents; }
float Diameter(Entity *e)					{ return static_cast<OOLightParticleEntity *>(oo::ToCxx(e))->_diameter; }

// --------------------------------------------------------------------------------------------------


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


// The flash's object, as the ship and the universe hand it to Objective-C.
Entity *FlashObject(const oo::Ref<OOFlashEffectEntity> &flash)	{ return oo::NewEntityFacade(flash); }
OOFlashEffectEntity *Part(Entity *flash)						{ return dynamic_cast<OOFlashEffectEntity *>(oo::ToCxx(flash)); }


Entity *Exploding()
{
	Entity *e = [[[Entity alloc] init] autorelease];
	[e setPosition:make_HPvector(10, 20, 30)];
	[e setVelocity:make_vector(1, 2, 3)];
	[e setCollisionRadius:2.0f];
	return e;
}

}	// namespace


OO_TEST(explosionFlash)
{
	@autoreleasepool
	{
		SetUp(5.0);
		Entity *flash = FlashObject(OOFlashEffectEntity::explosionFlashFromEntity(Exploding()));
		OO_CHECK(flash != nil && Part(flash) != nullptr);
		OO_CHECK(HPvector_equal([flash position], make_HPvector(10, 20, 30)));
		Vector v = [flash velocity];
		OO_CHECK(v.x == 1 && v.y == 2 && v.z == 3);
		OO_CHECK(Part(flash)->diameter() == 2.0f && Diameter(flash) == 2.0f);
		OO_CHECK([flash collisionRadius] == 0.0f && [flash energy] == 0.0f);
		OO_CHECK([flash status] == STATUS_EFFECT && [flash scanClass] == CLASS_NO_DRAW && [flash isEffect] && ![flash canCollide]);
		const GLfloat *c = ColorComponents(flash);
		OO_CHECK(c[0] == 1.0f && c[1] == 1.0f && c[2] == 1.0f && c[3] == 1.0f);

		// Growth max(150 * 2, 600) = 600 a second; alpha 0.5, duration 0.4: fade in for 0.2668 s.
		sUniverse->_time = 5.1;
		[flash update:0.1];
		OO_CHECK(Near(Diameter(flash), 62.0));
		OO_CHECK(Near(c[3], 0.5 * 0.1 / (0.4 * 0.667)));
		OO_CHECK(sUniverse->_removed == nil);

		sUniverse->_time = 5.35;
		[flash update:0.25];
		OO_CHECK(Near(Diameter(flash), 212.0));
		OO_CHECK(Near(c[3], 0.5 * (0.4 - 0.35) / (0.4 - 0.4 * 0.667)));
		OO_CHECK(sUniverse->_removed == nil);

		sUniverse->_time = 5.41;
		[flash update:0.06];
		OO_CHECK(sUniverse->_removed == flash);
	}
}


OO_TEST(bigExplosionGrowsFaster)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *big = Exploding();
		[big setCollisionRadius:10.0f];
		Entity *flash = FlashObject(OOFlashEffectEntity::explosionFlashFromEntity(big));
		OO_CHECK(Part(flash)->diameter() == 10.0f);
		sUniverse->_time = 0.1;
		[flash update:0.1];
		OO_CHECK(Near(Diameter(flash), 10.0 + 0.1 * 1500.0));	// 150 * 10 > 600
	}
}


OO_TEST(laserFlash)
{
	@autoreleasepool
	{
		SetUp(1.0);
		Entity *flash = FlashObject(OOFlashEffectEntity::laserFlashWithPosition(make_HPvector(-1, -2, -3),
																				make_vector(4, 5, 6),
																				OOColor::colorWithRed(1.0f, 0.5f, 0.25f, 0.125f).get()));
		OO_CHECK(flash != nil && Part(flash) != nullptr);
		OO_CHECK(HPvector_equal([flash position], make_HPvector(-1, -2, -3)));
		Vector v = [flash velocity];
		OO_CHECK(v.x == 4 && v.y == 5 && v.z == 6);
		OO_CHECK(Part(flash)->diameter() == 1.0f);
		const GLfloat *c = ColorComponents(flash);
		OO_CHECK(c[0] == 1.0f && c[1] == 0.5f && c[2] == 0.25f && c[3] == 1.0f);	// opaque

		// Growth 150 a second; alpha 1, duration 0.3.
		sUniverse->_time = 1.1;
		[flash update:0.1];
		OO_CHECK(Near(Diameter(flash), 16.0));
		OO_CHECK(Near(c[3], 0.1 / (0.3 * 0.667)));

		sUniverse->_time = 1.25;
		[flash update:0.15];
		OO_CHECK(Near(c[3], (0.3 - 0.25) / (0.3 - 0.3 * 0.667)));
		OO_CHECK(sUniverse->_removed == nil);

		sUniverse->_time = 1.31;
		[flash update:0.06];
		OO_CHECK(sUniverse->_removed == flash);
	}
}


OO_TEST(nilColourKeepsWhite)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *flash = FlashObject(OOFlashEffectEntity::laserFlashWithPosition(kZeroHPVector, kZeroVector, nil));
		const GLfloat *c = ColorComponents(flash);
		OO_CHECK(c[0] == 1.0f && c[1] == 1.0f && c[2] == 1.0f && c[3] == 1.0f);
	}
}


OO_TEST(texture)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *flash = FlashObject(OOFlashEffectEntity::explosionFlashFromEntity(Exploding()));
		sTextureName.reset();
		OO_CHECK(Part(flash)->texture() == sTexture);
		OO_CHECK(sTextureName == std::optional<std::string>("oolite-particle-flash.png"));
		sTextureName.reset();
		OO_CHECK(Part(flash)->texture() == sTexture && !sTextureName.has_value());	// loaded once
		OOFlashEffectEntity::setUpTexture();
		OO_CHECK(!sTextureName.has_value());
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp(0.0);
		Entity *flash = FlashObject(OOFlashEffectEntity::explosionFlashFromEntity(Exploding()));
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<OOFlashEffectEntity *>(oo::ToCxx(flash)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(flash)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(flash)) == flash);
	}
}


OO_TEST_MAIN()
