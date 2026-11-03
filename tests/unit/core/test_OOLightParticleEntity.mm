/*	test_OOLightParticleEntity.mm
	Unit tests for OOLightParticleEntity (src/Core/Entities/OOLightParticleEntity.h), the textured
	glow that the sparks, flashes, flashers and plasma effects draw: bead oo-0otc, after the
	Entities pattern seam (amendment oo-bj8, test_OOEntityWithDrawable.mm).

	Like Entity's, its object needs the game graph, so the test links the whole game but main
	(['*']) and uses a Universe that was never initialised (detail level minimum, so reduced detail)
	of a test subclass that answers the time and records what is removed, and a plain entity as
	PLAYER. The expectations were written against the Objective-C API and run on the unconverted
	class first: -initWithDiameter: (draw distance, scan class, status, white), the colour and
	diameter setters, -drawSubEntityImmediate:translucent: (the owner's camera distance, the cut-off,
	and the draw it sends to self), and that the texture a subclass answers is the one the debug
	texture list reports. The colour components, a @protected ivar, are read through the one helper
	below. The tests after those pin the intermediate class's crossing (amendment oo-0otc): an
	Objective-C subclass's C++ part is over cxx::OOLightParticleEntity and its -texture override is
	reached from C++; a C++ subclass's facade is an OOLightParticleEntity.
	Run: bash tools/check-core-tests.sh
*/

#import "OOLightParticleEntity.h"
#import "OOColor.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>


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


// UNIVERSE: never initialised; answers the time the test sets.
@interface TestUniverse: Universe
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime		{ return 0; }

@end


// An unconverted subclass, as OOFlashEffectEntity is: counts its draws and answers its own texture.
@interface TestParticle: OOLightParticleEntity
{
@public
	int			_draws;
	OOTexture	*_texture;
}
@end


@implementation TestParticle

- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	_draws++;
}


- (OOTexture *) texture
{
	return _texture;
}

@end


// An owner whose camera distance the test sets.
@interface TestOwner: Entity
@end


@implementation TestOwner
@end


namespace {

// --- Ivars the game reads directly, and nothing else ------------------------------------------------

const GLfloat *ColorComponents(OOLightParticleEntity *e)	{ return oo::ToCxx(e)->_colorComponents; }
GLfloat NoDrawDistance(Entity *e)							{ return e->_cxxEntity->no_draw_distance; }
GLfloat CamZeroDistance(Entity *e)							{ return e->_cxxEntity->cam_zero_distance; }
void SetCamZeroDistance(Entity *e, GLfloat value)			{ e->_cxxEntity->cam_zero_distance = value; }

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([TestUniverse class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
}


bool ComponentsAre(OOLightParticleEntity *e, GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{
	const GLfloat *c = ColorComponents(e);
	return c[0] == r && c[1] == g && c[2] == b && c[3] == a;
}

}	// namespace


OO_TEST(initWithDiameter)
{
	@autoreleasepool
	{
		SetUp();
		OOLightParticleEntity *particle = [[[OOLightParticleEntity alloc] initWithDiameter:8.0f] autorelease];
		OO_CHECK(particle != nil && [particle class] == [OOLightParticleEntity class]);
		OO_CHECK([particle diameter] == 8.0f);
		OO_CHECK([particle scanClass] == CLASS_NO_DRAW && [particle status] == STATUS_EFFECT);
		OO_CHECK([particle isEffect] && ![particle canCollide]);
		OO_CHECK(ComponentsAre(particle, 1.0f, 1.0f, 1.0f, 1.0f));

		// The draw distance grows with the diameter; reduced detail (a minimum detail level) scales it by 12.
		GLfloat expected = pow(8.0f / 2.0, M_SQRT2) * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
		expected *= 12.0;
		OO_CHECK([UNIVERSE reducedDetail]);
		OO_CHECK(NoDrawDistance(particle) == expected);

		// An Objective-C subclass initialises the same way.
		TestParticle *sub = [[[TestParticle alloc] initWithDiameter:2.0f] autorelease];
		OO_CHECK([sub diameter] == 2.0f && [sub status] == STATUS_EFFECT && [sub isEffect]);
	}
}


OO_TEST(colorAndDiameter)
{
	@autoreleasepool
	{
		SetUp();
		OOLightParticleEntity *particle = [[[OOLightParticleEntity alloc] initWithDiameter:1.0f] autorelease];
		[particle setColor:[OOColor colorWithRed:0.25f green:0.5f blue:0.75f alpha:0.5f]];
		OO_CHECK(ComponentsAre(particle, 0.25f, 0.5f, 0.75f, 0.5f));
		[particle setColor:[OOColor colorWithRed:1.0f green:0.0f blue:0.5f alpha:1.0f] alpha:0.125f];
		OO_CHECK(ComponentsAre(particle, 1.0f, 0.0f, 0.5f, 0.125f));

		// nil changes nothing (a message to nil did nothing), except the alpha it is given.
		[particle setColor:nil];
		OO_CHECK(ComponentsAre(particle, 1.0f, 0.0f, 0.5f, 0.125f));
		[particle setColor:nil alpha:0.25f];
		OO_CHECK(ComponentsAre(particle, 1.0f, 0.0f, 0.5f, 0.25f));

		[particle setDiameter:3.0f];
		OO_CHECK([particle diameter] == 3.0f);
	}
}


OO_TEST(drawSubEntity)
{
	@autoreleasepool
	{
		SetUp();
		TestParticle *particle = [[[TestParticle alloc] initWithDiameter:1.0f] autorelease];
		TestOwner *owner = [[[TestOwner alloc] init] autorelease];
		[particle setOwner:owner];

		// Opaque pass: nothing.
		SetCamZeroDistance(owner, 5.0f);
		[particle drawSubEntityImmediate:false translucent:false];
		OO_CHECK(CamZeroDistance(particle) == 0.0f && particle->_draws == 0);

		// Beyond the draw distance: the owner's distance is taken, and nothing is drawn.
		SetCamZeroDistance(owner, NoDrawDistance(particle) * 2.0f);
		[particle drawSubEntityImmediate:false translucent:true];
		OO_CHECK(CamZeroDistance(particle) == NoDrawDistance(particle) * 2.0f && particle->_draws == 0);

		// Near: drawn through -drawImmediate:translucent:, which the subclass overrides.
		SetCamZeroDistance(owner, 5.0f);
		[particle drawSubEntityImmediate:false translucent:true];
		OO_CHECK(CamZeroDistance(particle) == 5.0f && particle->_draws == 1);

		// The base's own draw does nothing in the opaque pass, or beyond the draw distance.
		OOLightParticleEntity *plain = [[[OOLightParticleEntity alloc] initWithDiameter:1.0f] autorelease];
		[plain drawImmediate:false translucent:false];
		SetCamZeroDistance(plain, NoDrawDistance(plain));
		[plain drawImmediate:false translucent:true];
	}
}


#ifndef NDEBUG
OO_TEST(texturesListTheSubclassTexture)
{
	@autoreleasepool
	{
		SetUp();
		TestParticle *particle = [[[TestParticle alloc] initWithDiameter:1.0f] autorelease];
		OOTexture *texture = (OOTexture *)[[[OOObject alloc] init] autorelease];	// only retained and compared
		particle->_texture = texture;
		const std::vector<oo::ObjCRef<OOTexture *>> textures = [particle cxx_allTextures];
		OO_CHECK(textures.size() == 1 && textures[0].get() == texture);
	}
}
#endif


OO_TEST(description)
{
	@autoreleasepool
	{
		SetUp();
		TestParticle *particle = [[[TestParticle alloc] initWithDiameter:1.0f] autorelease];
		OO_CHECK(oo::DescriptionOf(particle).starts_with("<TestParticle 0x"));
		OO_CHECK(oo::DescriptionOf(particle).ends_with("scanClass: CLASS_NO_DRAW status: STATUS_EFFECT}"));
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

// A converted subclass, as OOSparkEntity is.
class TestCxxParticle : public cxx::OOLightParticleEntity
{
};


OO_TEST(objCSubclassPartIsTheIntermediateClass)
{
	@autoreleasepool
	{
		SetUp();
		TestParticle *particle = [[[TestParticle alloc] initWithDiameter:4.0f] autorelease];
		OOTexture *texture = (OOTexture *)[[[OOObject alloc] init] autorelease];
		particle->_texture = texture;

		cxx::OOLightParticleEntity *part = oo::ToCxx(particle);
		OO_CHECK(part != nullptr && dynamic_cast<cxx::OOLightParticleEntity *>(oo::ToCxx(static_cast<Entity *>(particle))) == part);
		OO_CHECK(oo::ToObjC(part) == particle && part->diameter() == 4.0f);

		// From C++, the Objective-C overrides run.
		OO_CHECK(part->texture() == texture);
		part->drawImmediate(false, true);
		OO_CHECK(particle->_draws == 1);
	}
}


OO_TEST(cxxSubclassFacade)
{
	@autoreleasepool
	{
		SetUp();
		const oo::Ref<TestCxxParticle> particle = oo::makeRef<TestCxxParticle>();
		particle->initWithDiameter(6.0f);
		Entity *facade = oo::NewEntityFacade(particle);
		OO_CHECK(facade != nil && [facade class] == [OOLightParticleEntity class]);
		OOLightParticleEntity *light = (OOLightParticleEntity *)facade;
		OO_CHECK(oo::ToCxx(light) == particle.get() && oo::ToObjC(particle.get()) == light);
		OO_CHECK([light diameter] == 6.0f && [facade isEffect] && ![facade canCollide] && [facade status] == STATUS_EFFECT);
		[light setColor:[OOColor colorWithRed:0.5f green:0.25f blue:0.0f alpha:1.0f] alpha:0.5f];
		OO_CHECK(ComponentsAre(light, 0.5f, 0.25f, 0.0f, 0.5f));
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<TestCxxParticle 0x"));
	}
}


OO_TEST_MAIN()
