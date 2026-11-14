/*	test_OOEntityWithDrawable.mm
	Unit tests for OOEntityWithDrawable (src/Core/Entities/OOEntityWithDrawable.h), the entity that
	draws through an OODrawable and the base of ShipEntity, SkyEntity and OOVisualEffectEntity:
	bead oo-bj8, the Entities pattern seam, with Entity (test_Entity.mm).

	Like Entity's, its object needs the game graph, so the test links the whole game but main
	(['*']) and uses a Universe that was never initialised (no frustum planes, so every sphere is in
	view; no wireframe) and a plain entity as PLAYER. The drawable is an Objective-C subclass of
	OODrawable that counts what it is asked. The expectations were written against the Objective-C
	API and run on the unconverted class first: -setDrawable: takes the drawable's radius, draw
	distance and bounding box and makes the entity its binding target; -findCollisionRadius and the
	debug texture list ask the drawable; -drawImmediate:translucent: skips an entity beyond its draw
	distance and draws the right parts otherwise. The tests after those pin the intermediate
	class's crossing (amendment oo-up4b item 2): an Objective-C subclass's C++ part is over
	cxx::OOEntityWithDrawable and its [super ...] reaches that class's members; a C++ subclass's
	facade is an OOEntityWithDrawable. Run: bash tools/check-core-tests.sh
*/

#import "OOEntityWithDrawable.h"
#import "OODrawable.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cstring>


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


// The drawable of an unconverted entity: OOMesh is an Objective-C subclass of OODrawable.
@interface TestDrawable: OODrawable
{
@public
	int		_opaqueRenders;
	int		_translucentRenders;
	id		_bindingTarget;
	GLfloat	_maxDrawDistance;
}
@end


@implementation TestDrawable

- (void)renderOpaqueParts							{ _opaqueRenders++; }
- (void)renderTranslucentParts						{ _translucentRenders++; }
- (GLfloat)collisionRadius							{ return 5.0f; }
- (GLfloat)maxDrawDistance							{ return _maxDrawDistance; }
- (BoundingBox)boundingBox							{ return (BoundingBox){ { -1, -2, -3 }, { 1, 2, 3 } }; }
- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target	{ _bindingTarget = target; }

@end


// An unconverted subclass, as ShipEntity is.
@interface TestObjCEntityWithDrawable: OOEntityWithDrawable
@end


@implementation TestObjCEntityWithDrawable
@end


// An unconverted subclass that overrides a member of the intermediate class and calls super.
@interface TestOverridingEntity: OOEntityWithDrawable
{
@public
	int		_draws;
}
@end


@implementation TestOverridingEntity

- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	_draws++;
	[super drawImmediate:immediate translucent:translucent];
}

@end


// A converted subclass.
class TestCxxEntityWithDrawable : public cxx::OOEntityWithDrawable
{
};


namespace {

// --- Ivars the game reads directly (ent->no_draw_distance), and nothing else ----------------------

GLfloat NoDrawDistance(Entity *e)					{ return e->_cxxEntity->no_draw_distance; }
BoundingBox EntityBoundingBox(Entity *e)			{ return [e boundingBox]; }
void SetSubEntity(Entity *e, bool value)			{ e->_cxxEntity->isSubEntity = value; }
void SetCamZeroDistance(Entity *e, GLfloat value)	{ e->_cxxEntity->cam_zero_distance = value; }

// --------------------------------------------------------------------------------------------------


void SetUp()
{
	static Universe *universe = nil;
	if (universe == nil)
	{
		universe = (Universe *)class_createInstance([Universe class], 0);	// never released
		universe->_cxxUniverse = oo::makeRef<cxx::Universe>(universe);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nil;
	if (player == nil)  player = [[TestPlayer alloc] init];
	gOOPlayer = (PlayerEntity *)player;
}

}	// namespace


OO_TEST(setDrawable)
{
	@autoreleasepool
	{
		SetUp();
		OOEntityWithDrawable *entity = [[[OOEntityWithDrawable alloc] init] autorelease];
		OO_CHECK([entity drawable] == nil);
		OO_CHECK([entity findCollisionRadius] == 0);
#ifndef NDEBUG
		OO_CHECK([entity cxx_allTextures].empty());
#endif

		TestDrawable *drawable = [[[TestDrawable alloc] init] autorelease];
		drawable->_maxDrawDistance = 1000.0f;
		[entity setDrawable:drawable];
		OO_CHECK([entity drawable] == drawable);
		OO_CHECK(drawable->_bindingTarget == entity);
		OO_CHECK([entity collisionRadius] == 5.0f && [entity findCollisionRadius] == 5.0);
		OO_CHECK(NoDrawDistance(entity) == 1000.0f);
		BoundingBox box = EntityBoundingBox(entity);
		OO_CHECK(box.min.x == -1 && box.min.y == -2 && box.min.z == -3 && box.max.x == 1 && box.max.y == 2 && box.max.z == 3);

		// Setting the same drawable again changes nothing.
		[entity setCollisionRadius:1.0f];
		[entity setDrawable:drawable];
		OO_CHECK([entity collisionRadius] == 1.0f);

		[entity setDrawable:nil];
		OO_CHECK([entity drawable] == nil && [entity collisionRadius] == 0 && NoDrawDistance(entity) == 0);
	}
}


OO_TEST(drawImmediate)
{
	@autoreleasepool
	{
		SetUp();
		TestObjCEntityWithDrawable *entity = [[[TestObjCEntityWithDrawable alloc] init] autorelease];
		TestDrawable *drawable = [[[TestDrawable alloc] init] autorelease];
		drawable->_maxDrawDistance = 1.0e9f;
		[entity setDrawable:drawable];
		[entity setPosition:make_HPvector(0, 0, 100)];

		// Near: drawn with no frustum test. (cam_zero_distance is a squared distance, compared with
		// the draw distance as it is.)
		SetCamZeroDistance(entity, 500.0f);
		[entity drawImmediate:false translucent:false];
		[entity drawImmediate:false translucent:true];
		OO_CHECK(drawable->_opaqueRenders == 1 && drawable->_translucentRenders == 1);

		// Far enough away for the frustum test, which a Universe with no planes always passes.
		SetCamZeroDistance(entity, 2.0e6f);
		[entity drawImmediate:false translucent:false];
		OO_CHECK(drawable->_opaqueRenders == 2);

		// A subentity takes the other branch.
		SetSubEntity(entity, true);
		[entity drawImmediate:true translucent:true];
		OO_CHECK(drawable->_translucentRenders == 2);
		SetSubEntity(entity, false);

		// Beyond the draw distance: not drawn.
		SetCamZeroDistance(entity, 2.0e9f);
		[entity drawImmediate:false translucent:false];
		OO_CHECK(drawable->_opaqueRenders == 2);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		SetUp();
		OOEntityWithDrawable *entity = [[[OOEntityWithDrawable alloc] init] autorelease];
		OO_CHECK(oo::DescriptionOf(entity).starts_with("<OOEntityWithDrawable 0x"));
		OO_CHECK(oo::DescriptionOf(entity).ends_with("{position: (0, 0, 0) scanClass: CLASS_NOT_SET status: STATUS_COCKPIT_DISPLAY}"));
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

OO_TEST(objCSubclassPartIsTheIntermediateClass)
{
	@autoreleasepool
	{
		SetUp();
		TestOverridingEntity *entity = [[[TestOverridingEntity alloc] init] autorelease];
		TestDrawable *drawable = [[[TestDrawable alloc] init] autorelease];
		drawable->_maxDrawDistance = 1.0e9f;
		[entity setDrawable:drawable];

		cxx::OOEntityWithDrawable *part = oo::ToCxx(entity);
		OO_CHECK(part != nullptr && dynamic_cast<cxx::OOEntityWithDrawable *>(oo::ToCxx(static_cast<Entity *>(entity))) == part);
		OO_CHECK(part->getDrawable() == drawable && oo::ToObjC(part) == entity);

		// From C++, the Objective-C override runs, and its [super ...] reaches the C++ member.
		part->drawImmediate(false, false);
		OO_CHECK(entity->_draws == 1 && drawable->_opaqueRenders == 1);
		[entity drawImmediate:false translucent:true];
		OO_CHECK(entity->_draws == 2 && drawable->_translucentRenders == 1);
		OO_CHECK(part->findCollisionRadius() == 5.0);
	}
}


OO_TEST(cxxSubclassFacade)
{
	@autoreleasepool
	{
		SetUp();
		const oo::Ref<TestCxxEntityWithDrawable> entity = oo::makeRef<TestCxxEntityWithDrawable>();
		Entity *facade = oo::NewEntityFacade(entity);
		OO_CHECK(facade != nil && [facade class] == [OOEntityWithDrawable class]);
		OOEntityWithDrawable *withDrawable = (OOEntityWithDrawable *)facade;
		OO_CHECK(oo::ToCxx(withDrawable) == entity.get() && oo::ToObjC(entity.get()) == withDrawable);

		TestDrawable *drawable = [[[TestDrawable alloc] init] autorelease];
		drawable->_maxDrawDistance = 1.0e9f;
		[withDrawable setDrawable:drawable];
		OO_CHECK([withDrawable drawable] == drawable && drawable->_bindingTarget == facade);
		OO_CHECK([facade findCollisionRadius] == 5.0 && [facade collisionRadius] == 5.0f);
		[facade drawImmediate:false translucent:false];
		OO_CHECK(drawable->_opaqueRenders == 1);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<TestCxxEntityWithDrawable 0x"));
	}
}


OO_TEST_MAIN()
