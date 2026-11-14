/*	test_DustEntity.mm
	Unit tests for DustEntity (src/Core/Entities/DustEntity.h), the space dust drawn around the
	player: bead oo-0mxi, a leaf of the Entities pattern seam (amendment oo-bj8 item 12).

	Its object needs the game graph, so the test links the whole game but main (['*']) and uses a
	Universe that was never initialised (detail level minimum, so no dust shader) and an entity as
	PLAYER whose viewpoint, velocity and hyperspeed factor the test sets. -init asks the OpenGL
	extension manager about point sprites, which needs a current context (oo_gl_test_context.hpp). The expectations were
	written against the Objective-C API and run on the unconverted class first: what -init sets
	(status, the collision radius the draw pass uses, the pale cyan colour), the dust colour
	setter, the camera-relative position (the viewpoint wrapped to the dust cube), the two vectors the
	dust shader binds by selector (-warpVector, -offsetPlayerPosition), and that the universe can
	still find the dust. Bead oo-9ht.77 deleted the Objective-C facade (proposed ADR-0056 amendment
	oo-0mxi): the universe makes it with oo::makeRef<DustEntity>() and init() and hands it over with
	oo::NewEntityFacade, so the test does the same and asks the C++ class; the facade checks
	(class, selectors) went with the facade (ADR-0049, oo-9n5p9).
	Run: bash tools/check-core-tests.sh
*/

#import "DustEntity.h"
#import "OOColor.h"
#import "OODescription.h"
#import "Universe.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)

#include "oo_gl_test_context.hpp"
#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


// PLAYER: a player whose viewpoint and hyperspeed factor the test sets (C++ since bead oo-9ht.177
// deleted the Objective-C player).
class TestPlayer : public PlayerEntity
{
public:
	HPVector	_viewpoint = kZeroHPVector;

	HPVector viewpointPosition() override	{ return _viewpoint; }
	GLfloat getHyperspeedFactor() override	{ return 32.0f; }
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
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


namespace {

TestPlayer *SetUp()
{
	OO_CHECK(OOTestGLContext());
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([Universe class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
	player->_viewpoint = kZeroHPVector;
	player->setVelocity(kZeroVector);
	return player;
}


// What the universe does: a dust entity, and its root facade.
Entity *MakeDust(DustEntity **outDust)
{
	oo::Ref<DustEntity> dust = oo::makeRef<DustEntity>();
	dust->init();
	*outDust = dust.get();
	return oo::NewEntityFacade(dust);
}


bool ColorIs(OOColor *color, float r, float g, float b, float a)
{
	float cr, cg, cb, ca;
	color->getRed(&cr, &cg, &cb, &ca);
	return cr == r && cg == g && cb == b && ca == a;
}

}	// namespace


OO_TEST(init)
{
	@autoreleasepool
	{
		SetUp();
		DustEntity *dust = nullptr;
		Entity *object = MakeDust(&dust);
		OO_CHECK(object != nil && dust != nullptr && dynamic_cast<DustEntity *>(oo::ToCxx(object)) == dust);
		OO_CHECK(dust->status() == STATUS_ACTIVE);
		OO_CHECK(dust->collisionRadius() == DUST_SCALE && !dust->canCollide());
		OO_CHECK(ColorIs(dust->dustColor(), 0.5f, 1.0f, 1.0f, 1.0f));
		OO_CHECK(oo::EntityClassName(dust) == "DustEntity");

		oo::Ref<OOColor>	color = OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 1.0f);
		dust->setDustColor(color.get());
		OO_CHECK(dust->dustColor() == color);

		// Nothing is drawn in the opaque pass.
		dust->drawImmediate(false, false);
		// A graphics reset is safe at any time.
		dust->resetGraphicsState();
	}
}


OO_TEST(cameraRelativePosition)
{
	@autoreleasepool
	{
		TestPlayer *player = SetUp();
		DustEntity *dust = nullptr;
		Entity *object = MakeDust(&dust);
		player->_viewpoint = make_HPvector(2500, -100, 4000);
		dust->updateCameraRelativePosition();
		Vector relative = [object cameraRelativePosition];
		OO_CHECK(relative.x == -500 && relative.y == 100 && relative.z == 0);

		// update(): puts the dust at zero distance (it is always around the player).
		dust->update(0.1);
		OO_CHECK(dust->zeroDistance() == 0.0);
	}
}


OO_TEST(shaderBindings)
{
	@autoreleasepool
	{
		TestPlayer *player = SetUp();
		DustEntity *dust = nullptr;
		MakeDust(&dust);
		player->setVelocity(make_vector(0, 64, 320));
		OO_CHECK(vector_equal(dust->warpVector(), make_vector(0, 2, 10)));

#if OO_SHADERS
		player->_viewpoint = make_HPvector(2500, -100, 0);
		Vector offset = dust->offsetPlayerPosition();
		OO_CHECK(offset.x == -500 && offset.y == -1100 && offset.z == -1000);
#endif
	}
}


OO_TEST_MAIN()
