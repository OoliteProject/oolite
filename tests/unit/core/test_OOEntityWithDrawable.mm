/*	test_OOEntityWithDrawable.mm
	Unit tests for OOEntityWithDrawable (src/Core/Entities/OOEntityWithDrawable.h), the entity that
	draws through an OODrawable and the base of ShipEntity, SkyEntity and OOVisualEffectEntity:
	bead oo-bj8, the Entities pattern seam, with Entity (test_Entity.mm).

	Like Entity's, its object needs the game graph, so the test links the whole game but main
	(['*']) and uses a Universe that was never initialised (no frustum planes, so every sphere is in
	view; no wireframe) and a plain entity as PLAYER. The drawable is a subclass of OODrawable that
	counts what it is asked (an Objective-C one until bead oo-hahfg moved the entity's drawable to
	C++; a C++ one since, with the same answers). The expectations were written against the Objective-C
	API and run on the unconverted class first: -setDrawable: takes the drawable's radius, draw
	distance and bounding box and makes the entity its binding target; -findCollisionRadius and the
	debug texture list ask the drawable; -drawImmediate:translucent: skips an entity beyond its draw
	distance and draws the right parts otherwise. The tests after those pin the intermediate
	class's crossing (amendment oo-up4b item 2): a C++ subclass's object holds it. Since bead
	oo-9ht.40 deleted the class's Objective-C facade (ADR-0056 amendment oo-9ht.40) the entities are
	C++ under the root's facade (oo::NewEntityFacade): the class's own selectors (-drawable,
	-setDrawable:) are member calls and the root's are still sent to the object; the Objective-C
	subclasses and their crossing case went with the facade. Run: bash tools/check-core-tests.sh
*/

#import "OOEntityWithDrawable.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#import "OODrawable.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cstring>


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
	@autoreleasepool
	{
		[oo::NewEntityFacade(player) retain];
	}
	return player.get();
}


// The drawable: a C++ subclass of OODrawable since bead oo-hahfg (every drawable is C++), with the
// answers the Objective-C one gave.
class TestDrawable : public OODrawable
{
public:
	void renderOpaqueParts() override								{ _opaqueRenders++; }
	void renderTranslucentParts() override							{ _translucentRenders++; }
	GLfloat collisionRadius() override								{ return 5.0f; }
	GLfloat maxDrawDistance() override								{ return _maxDrawDistance; }
	BoundingBox boundingBox() override								{ return (BoundingBox){ { -1, -2, -3 }, { 1, 2, 3 } }; }
	void setBindingTarget(id<OOWeakReferenceSupport> target) override	{ _bindingTarget = target; }

	int		_opaqueRenders = 0;
	int		_translucentRenders = 0;
	id		_bindingTarget = nil;
	GLfloat	_maxDrawDistance = 0.0f;
};


// A converted subclass.
class TestCxxEntityWithDrawable : public OOEntityWithDrawable
{
};


namespace {

// --- Ivars the game reads directly (ent->no_draw_distance), and nothing else ----------------------

GLfloat NoDrawDistance(Entity *e)					{ return e->_cxxEntity->no_draw_distance; }
BoundingBox EntityBoundingBox(Entity *e)			{ return [e boundingBox]; }
void SetSubEntity(Entity *e, bool value)			{ e->_cxxEntity->isSubEntity = value; }
void SetCamZeroDistance(Entity *e, GLfloat value)	{ e->_cxxEntity->cam_zero_distance = value; }

// An entity with a drawable and its object, as the game makes a C++ one ([[OOEntityWithDrawable
// alloc] init] until bead oo-9ht.40 deleted that facade): the root's facade, autoreleased.
template <class T = OOEntityWithDrawable>
T *NewWithDrawable(Entity **outObject)
{
	const oo::Ref<T> part = oo::makeRef<T>();
	*outObject = oo::NewEntityFacade(part);
	return part.get();
}

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
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
}

}	// namespace


OO_TEST(setDrawable)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = nil;
		OOEntityWithDrawable *part = NewWithDrawable(&entity);
		OO_CHECK(part->getDrawable() == nullptr);
		OO_CHECK([entity findCollisionRadius] == 0);
#ifndef NDEBUG
		OO_CHECK([entity cxx_allTextures].empty());
#endif

		const oo::Ref<TestDrawable> drawable = oo::makeRef<TestDrawable>();
		drawable->_maxDrawDistance = 1000.0f;
		part->setDrawable(drawable.get());
		OO_CHECK(part->getDrawable() == drawable.get());
		OO_CHECK(drawable->_bindingTarget == entity);
		OO_CHECK([entity collisionRadius] == 5.0f && [entity findCollisionRadius] == 5.0);
		OO_CHECK(NoDrawDistance(entity) == 1000.0f);
		BoundingBox box = EntityBoundingBox(entity);
		OO_CHECK(box.min.x == -1 && box.min.y == -2 && box.min.z == -3 && box.max.x == 1 && box.max.y == 2 && box.max.z == 3);

		// Setting the same drawable again changes nothing.
		[entity setCollisionRadius:1.0f];
		part->setDrawable(drawable.get());
		OO_CHECK([entity collisionRadius] == 1.0f);

		part->setDrawable(nullptr);
		OO_CHECK(part->getDrawable() == nullptr && [entity collisionRadius] == 0 && NoDrawDistance(entity) == 0);
	}
}


OO_TEST(drawImmediate)
{
	@autoreleasepool
	{
		SetUp();
		Entity *entity = nil;
		TestCxxEntityWithDrawable *part = NewWithDrawable<TestCxxEntityWithDrawable>(&entity);	// a subclass, as a ship is
		const oo::Ref<TestDrawable> drawable = oo::makeRef<TestDrawable>();
		drawable->_maxDrawDistance = 1.0e9f;
		part->setDrawable(drawable.get());
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
		Entity *entity = nil;
		(void)NewWithDrawable(&entity);
		OO_CHECK(oo::DescriptionOf(entity).starts_with("<OOEntityWithDrawable 0x"));
		OO_CHECK(oo::DescriptionOf(entity).ends_with("{position: (0, 0, 0) scanClass: CLASS_NOT_SET status: STATUS_COCKPIT_DISPLAY}"));
	}
}


// --- The crossing (after the conversion) ---------------------------------------------------------

OO_TEST(cxxSubclassFacade)
{
	@autoreleasepool
	{
		SetUp();
		const oo::Ref<TestCxxEntityWithDrawable> entity = oo::makeRef<TestCxxEntityWithDrawable>();
		Entity *facade = oo::NewEntityFacade(entity);
		OO_CHECK(facade != nil);
		OO_CHECK(oo::ToCxx(facade) == entity.get() && oo::ToObjC(entity.get()) == facade);

		const oo::Ref<TestDrawable> drawable = oo::makeRef<TestDrawable>();
		drawable->_maxDrawDistance = 1.0e9f;
		entity->setDrawable(drawable.get());
		OO_CHECK(entity->getDrawable() == drawable.get() && drawable->_bindingTarget == facade);
		OO_CHECK([facade findCollisionRadius] == 5.0 && [facade collisionRadius] == 5.0f);
		[facade drawImmediate:false translucent:false];
		OO_CHECK(drawable->_opaqueRenders == 1);
		OO_CHECK(oo::DescriptionOf(facade).starts_with("<TestCxxEntityWithDrawable 0x"));
	}
}


OO_TEST_MAIN()
