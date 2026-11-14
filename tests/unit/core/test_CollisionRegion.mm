/*	test_CollisionRegion.mm
	Unit tests for CollisionRegion (src/Core/CollisionRegion.h): bead oo-44gg (Phase 3, house style
	of proposed ADR-0056). Its Objective-C facade was deleted by bead oo-9ht.11, which retired the
	facade's own cases under the standing approval oo-9n5p9 and ported the rest to the C++ class.

	CollisionRegion's object reads Entity and Universe ivars, so it links the whole game but main
	(tests/unit/core/meson.build entry ['*'], ADR-0056 amendment oo-44gg), and defines the one
	global main.mm did, gDebugFlags. The regions are driven
	with plain Entity objects and no Universe (UNIVERSE is nil: no sun, so no shadowing work).
	The expectations were written against the Objective-C API and run on the unconverted class
	first: the region tree (a sphere that fits goes into the subregion, one that crosses a border is
	left out), which region an entity is filed in (the first subregion within whose borders it
	lies, else the universe), the counts in -debugOut, the description text, the collision counters
	and the shadow geometry of shadowAtPointOcclusionToValue(). Run: bash tools/check-core-tests.sh
*/

#import "CollisionRegion.h"
#import "Entity.h"
#import "OOSunEntity.h"
#import "OODescription.h"

#include "oo_test.hpp"

#include <string>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


namespace {

Entity *MakeEntity(HPVector position, GLfloat radius)
{
	Entity *entity = [[[Entity alloc] init] autorelease];
	[entity setPosition:position];
	[entity setCollisionRadius:radius];
	return entity;
}


bool EndsWith(const std::string &text, const std::string &tail)
{
	return text.size() >= tail.size() && text.compare(text.size() - tail.size(), tail.size(), tail) == 0;
}


oo::Ref<CollisionRegion> MakeUniverse()
{
	return oo::makeRef<CollisionRegion>(CollisionRegion::AsUniverse{});
}


// The region an entity is filed in (the entity's C++ part holds it).
CollisionRegion *RegionOf(Entity *entity)
{
	return oo::ToCxx(entity)->getCollisionRegion();
}


// A universe with three regions: one at x = 1000 (radius 100) holding one at x = 1000 (radius 10),
// and one at x = 5000 (radius 100). A sphere crossing the first region's border is left out.
oo::Ref<CollisionRegion> MakeTree()
{
	oo::Ref<CollisionRegion> universe = MakeUniverse();
	universe->addSubregionAtPosition(make_HPvector(1000, 0, 0), 100);
	universe->addSubregionAtPosition(make_HPvector(1000, 0, 0), 10);		// fits: nested
	universe->addSubregionAtPosition(make_HPvector(1050, 0, 0), 100);	// crosses: left out
	universe->addSubregionAtPosition(make_HPvector(5000, 0, 0), 100);
	return universe;
}

}	// namespace


OO_TEST(universeAlone)
{
	@autoreleasepool
	{
		oo::Ref<CollisionRegion> universe = MakeUniverse();
		OO_CHECK(universe != nullptr);
		OO_CHECK(universe->debugOut() == std::optional<std::string>("0:"));
		OO_CHECK(universe->collisionDescription() == "p0 - c0");
		OO_CHECK(EndsWith(universe->descriptionComponents().value_or(""), ", 0 subregions, 0 ents"));
	}
}


OO_TEST(subregionTree)
{
	@autoreleasepool
	{
		oo::Ref<CollisionRegion> universe = MakeTree();
		OO_CHECK(universe->debugOut() == std::optional<std::string>("0:0:0:0:"));
		OO_CHECK(EndsWith(universe->descriptionComponents().value_or(""), ", 2 subregions, 0 ents"));

		universe->clearSubregions();
		OO_CHECK(universe->debugOut() == std::optional<std::string>("0:"));
		OO_CHECK(EndsWith(universe->descriptionComponents().value_or(""), ", 0 subregions, 0 ents"));
	}
}


OO_TEST(entitiesAreFiled)
{
	@autoreleasepool
	{
		oo::Ref<CollisionRegion> universe = MakeTree();
		Entity *inner = MakeEntity(make_HPvector(1000, 0, 0), 5);
		Entity *second = MakeEntity(make_HPvector(5000, 0, 0), 5);
		Entity *distant = MakeEntity(make_HPvector(1.0e7, 0, 0), 5);

		universe->clearEntityList();
		OO_CHECK(universe->checkEntity(inner));
		OO_CHECK(universe->checkEntity(second));
		OO_CHECK(universe->checkEntity(distant));

		// inner lies within the borders (radius + 32 km) of the first region's nested one, and so
		// does second (4 km away); distant is filed in the universe itself.
		OO_CHECK(universe->debugOut() == std::optional<std::string>("1:0:2:0:"));
		OO_CHECK(RegionOf(distant) == universe.get());
		OO_CHECK(RegionOf(inner) != nullptr && RegionOf(inner) != universe.get());
		OO_CHECK(RegionOf(inner) == RegionOf(second));
		OO_CHECK(RegionOf(inner)->debugOut() == std::optional<std::string>("2:"));
		OO_CHECK(EndsWith(RegionOf(inner)->descriptionComponents().value_or(""), ", 0 subregions, 2 ents"));
		OO_CHECK(EndsWith(universe->descriptionComponents().value_or(""), ", 2 subregions, 1 ents"));

		// A region that is not the universe refuses an entity outside its borders.
		OO_CHECK(!RegionOf(inner)->checkEntity(distant));

		// No collision chain (Universe builds it): nothing is checked.
		universe->findCollisions();
		OO_CHECK(universe->collisionDescription() == "p0 - c0");
		universe->findShadowedEntities();	// no Universe, so no sun: nothing to do

		universe->clearEntityList();
		OO_CHECK(universe->debugOut() == std::optional<std::string>("0:0:0:0:"));
	}
}


OO_TEST(entityListGrows)
{
	@autoreleasepool
	{
		oo::Ref<CollisionRegion> universe = MakeUniverse();
		for (unsigned i = 0; i < COLLISION_MAX_ENTITIES * 3; i++)
		{
			universe->addEntity(MakeEntity(make_HPvector(i, 0, 0), 1));
		}
		OO_CHECK(universe->debugOut() == std::optional<std::string>(std::to_string(COLLISION_MAX_ENTITIES * 3) + ":"));
	}
}


OO_TEST(shadowGeometry)
{
	@autoreleasepool
	{
		// The function reads only Entity members of the sun, which is C++ since bead oo-9ht.111 (a
		// cast entity before): a C++ sun with the same position and radius.
		oo::Ref<OOSunEntity> sunRef = oo::makeRef<OOSunEntity>();
		sunRef->position = make_HPvector(0, 0, 10000);
		sunRef->collision_radius = 10;
		OOSunEntity *sun = sunRef.get();
		Entity *between = MakeEntity(make_HPvector(0, 0, 100), 50);
		Entity *behind = MakeEntity(make_HPvector(0, 0, -100), 50);
		Entity *small = MakeEntity(make_HPvector(0, 0, 100), 0.5f);
		float value = 0;

		OO_CHECK(shadowAtPointOcclusionToValue(kZeroHPVector, 1, between, sun, &value));
		OO_CHECK(value == 0.0f);

		value = 0;
		OO_CHECK(!shadowAtPointOcclusionToValue(kZeroHPVector, 1, behind, sun, &value));
		OO_CHECK(value == 1.5f);

		value = 0;
		OO_CHECK(!shadowAtPointOcclusionToValue(kZeroHPVector, 1, small, sun, &value));	// smaller can't shade bigger
		OO_CHECK(value == 1.5f);
	}
}


OO_TEST(cxxRegion)
{
	@autoreleasepool
	{
		oo::Ref<CollisionRegion> universe = MakeUniverse();
		universe->addSubregionAtPosition(make_HPvector(1000, 0, 0), 100);
		universe->addSubregionAtPosition(make_HPvector(5000, 0, 0), 100);
		OO_CHECK(universe->debugOut() == std::optional<std::string>("0:0:0:"));
		OO_CHECK(EndsWith(*universe->descriptionComponents(), ", 2 subregions, 0 ents"));

		Entity *entity = MakeEntity(make_HPvector(1.0e7, 0, 0), 5);
		OO_CHECK(universe->checkEntity(entity));
		OO_CHECK(RegionOf(entity) == universe.get());
		OO_CHECK(universe->collisionDescription() == "p0 - c0");
	}
}


OO_TEST_MAIN()
