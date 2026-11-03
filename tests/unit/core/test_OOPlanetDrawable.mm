/*	test_OOPlanetDrawable.mm
	Unit tests for OOPlanetDrawable (src/Core/OOPlanetDrawable.h), the sphere that draws a planet's
	surface or its atmosphere: bead oo-mw4u, a subclass of the converted drawable root OODrawable
	(proposed ADR-0056, amendments oo-smy and oo-zffj).

	The drawable reads the universe for its level of detail, so the test links the whole game but
	main (['*']) and uses a Universe that was never initialised, subclassed to answer the detail
	setting and a game view of the test's size. The expectations were written against the
	Objective-C API and run on the unconverted class first: a planet's and an atmosphere's defaults
	(radius 1, half detail), the radius (its magnitude), the level of detail (clamped, rounded to
	the planet data's levels, and computed from the view distance and the screen width), which
	parts are opaque or translucent, the bounds, the material and its name, and a copy. Drawing
	needs OpenGL and is left to the goldens. The class has one caller, OOPlanetEntity, so the
	conversion left no facade (amendment oo-zffj); the drawable is made and read through the one
	block of helpers below, the only lines the conversion ported.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPlanetDrawable.h"
#import "OOPlanetData.h"
#import "OOBasicMaterial.h"
#import "Universe.h"

#include "oo_test.hpp"

#include <cmath>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern Universe *gSharedUniverse;


// The game view, as far as the drawable asks it.
@interface TestView: OOObject
{
@public
	NSSize	_size;
}
- (NSSize) viewSize;
@end


@implementation TestView

- (NSSize) viewSize  { return _size; }

@end


// UNIVERSE: never initialised; answers the detail setting and the game view.
@interface TestUniverse: Universe
{
@public
	BOOL		_reduced;
	TestView	*_view;
}
@end


@implementation TestUniverse

- (BOOL) reducedDetail				{ return _reduced; }
- (MyOpenGLView *) gameView			{ return (MyOpenGLView *)_view; }

@end


namespace {

TestUniverse *sUniverse = nil;


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		sUniverse->_view = [[TestView alloc] init];
	}
	sUniverse->_reduced = NO;
	sUniverse->_view->_size = NSMakeSize(800, 600);
	gSharedUniverse = sUniverse;
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-5;
}


const float kGranularity = (float)(kOOPlanetDataLevels - 1);


float Level(float lod)
{
	return roundf(lod * kGranularity) / kGranularity;
}


OOMaterial *NamedMaterial(const char *name)
{
	return oo::ToObjC(static_cast<cxx::OOMaterial *>(OOBasicMaterial::materialWithName(std::string(name), oo::PList()).get()));
}


// --- The drawable, made and read; the only lines the conversion ported ------------------------------

using Planet = oo::Ref<OOPlanetDrawable>;

Planet NewPlanet()												{ return oo::makeRef<OOPlanetDrawable>(); }
Planet NewAtmosphere()											{ return OOPlanetDrawable::initAsAtmosphere(); }
Planet AtmosphereWithRadius(float radius)						{ return OOPlanetDrawable::atmosphereWithRadius(radius); }
Planet Copy(const Planet &d)									{ return d->copy(); }
float Radius(const Planet &d)									{ return d->radius(); }
void SetRadius(const Planet &d, float radius)					{ d->setRadius(radius); }
float LevelOfDetail(const Planet &d)							{ return d->levelOfDetail(); }
void SetLevelOfDetail(const Planet &d, float lod)				{ d->setLevelOfDetail(lod); }
void CalculateLevelOfDetail(const Planet &d, float distance)	{ d->calculateLevelOfDetailForViewDistance(distance); }
bool HasOpaqueParts(const Planet &d)							{ return d->hasOpaqueParts(); }
bool HasTranslucentParts(const Planet &d)						{ return d->hasTranslucentParts(); }
GLfloat CollisionRadius(const Planet &d)						{ return d->collisionRadius(); }
GLfloat MaxDrawDistance(const Planet &d)						{ return d->maxDrawDistance(); }
BoundingBox Bounds(const Planet &d)								{ return d->boundingBox(); }
OOMaterial *Material(const Planet &d)							{ return d->material(); }
void SetMaterial(const Planet &d, OOMaterial *material)			{ d->setMaterial(material); }
std::optional<std::string> TextureName(const Planet &d)		{ return d->textureName(); }
void SetTextureName(const Planet &d, const std::string &name)	{ d->setTextureName(name); }

// --------------------------------------------------------------------------------------------------

}	// namespace


OO_TEST(planetDefaults)
{
	@autoreleasepool
	{
		SetUp();
		Planet planet = NewPlanet();
		OO_CHECK(Radius(planet) == 1.0f);
		OO_CHECK(CollisionRadius(planet) == 1.0f);
		OO_CHECK(Near(LevelOfDetail(planet), Level(0.5f)));
		OO_CHECK(HasOpaqueParts(planet) && !HasTranslucentParts(planet));
		OO_CHECK(std::isinf(MaxDrawDistance(planet)));
		OO_CHECK(Material(planet) == nil);
		OO_CHECK(!TextureName(planet).has_value());
	}
}


OO_TEST(atmosphere)
{
	@autoreleasepool
	{
		SetUp();
		Planet atmosphere = NewAtmosphere();
		OO_CHECK(Radius(atmosphere) == 1.0f);
		OO_CHECK(!HasOpaqueParts(atmosphere) && HasTranslucentParts(atmosphere));

		Planet sized = AtmosphereWithRadius(-250.0f);
		OO_CHECK(Radius(sized) == 250.0f);
		OO_CHECK(!HasOpaqueParts(sized) && HasTranslucentParts(sized));
		OO_CHECK(Near(LevelOfDetail(sized), Level(0.5f)));
	}
}


OO_TEST(radiusAndBounds)
{
	@autoreleasepool
	{
		SetUp();
		Planet planet = NewPlanet();
		SetRadius(planet, -5000.0f);
		OO_CHECK(Radius(planet) == 5000.0f);
		OO_CHECK(CollisionRadius(planet) == 5000.0f);
		BoundingBox box = Bounds(planet);
		OO_CHECK(box.min.x == -5000.0f && box.min.y == -5000.0f && box.min.z == -5000.0f);
		OO_CHECK(box.max.x == 5000.0f && box.max.y == 5000.0f && box.max.z == 5000.0f);
	}
}


OO_TEST(levelOfDetail)
{
	@autoreleasepool
	{
		SetUp();
		Planet planet = NewPlanet();
		SetLevelOfDetail(planet, 0.3f);
		OO_CHECK(Near(LevelOfDetail(planet), Level(0.3f)));
		SetLevelOfDetail(planet, -2.0f);
		OO_CHECK(LevelOfDetail(planet) == 0.0f);
		SetLevelOfDetail(planet, 7.0f);
		OO_CHECK(LevelOfDetail(planet) == 1.0f);
		SetLevelOfDetail(planet, 0.8f);
		OO_CHECK(Near(LevelOfDetail(planet), Level(0.8f)));
	}
}


OO_TEST(levelOfDetailForViewDistance)
{
	@autoreleasepool
	{
		SetUp();
		Planet planet = NewPlanet();
		SetRadius(planet, 100.0f);

		// Full detail: sqrt(width / 40 * radius / sqrt(distance) / 4), clamped to [0, 1].
		float distance = 1.0e6f;
		float expected = sqrtf((800.0f / 40.0f) * 100.0f / sqrtf(distance) * 0.25f);
		CalculateLevelOfDetail(planet, distance);
		OO_CHECK(Near(LevelOfDetail(planet), Level(fminf(expected, 1.0f))));

		// Close by: the highest level.
		CalculateLevelOfDetail(planet, 1.0f);
		OO_CHECK(LevelOfDetail(planet) == 1.0f);

		// Far away: the lowest.
		CalculateLevelOfDetail(planet, 1.0e20f);
		OO_CHECK(LevelOfDetail(planet) == 0.0f);

		// Reduced detail: a narrower budget, earlier transitions, and never the highest level.
		sUniverse->_reduced = YES;
		CalculateLevelOfDetail(planet, 1.0f);
		OO_CHECK(Near(LevelOfDetail(planet), (kGranularity - 1.0f) / kGranularity));
		expected = sqrtf((800.0f / 100.0f) * 100.0f / sqrtf(distance) * 0.25f) - 0.5f / kGranularity;
		CalculateLevelOfDetail(planet, distance);
		OO_CHECK(Near(LevelOfDetail(planet), Level(fminf(fmaxf(expected, 0.0f), (kGranularity - 1.0f) / kGranularity))));

		// A wider screen: more detail at the same distance.
		sUniverse->_reduced = NO;
		sUniverse->_view->_size = NSMakeSize(1600, 1200);
		expected = sqrtf((1600.0f / 40.0f) * 100.0f / sqrtf(distance) * 0.25f);
		CalculateLevelOfDetail(planet, distance);
		OO_CHECK(Near(LevelOfDetail(planet), Level(fminf(expected, 1.0f))));
	}
}


OO_TEST(material)
{
	@autoreleasepool
	{
		SetUp();
		Planet planet = NewPlanet();
		OOMaterial *material = NamedMaterial("rock");
		SetMaterial(planet, material);
		OO_CHECK(Material(planet) == material);
		OO_CHECK(TextureName(planet) == std::optional<std::string>("rock"));

		// The same name keeps the material.
		SetTextureName(planet, "rock");
		OO_CHECK(Material(planet) == material);

		SetMaterial(planet, nil);
		OO_CHECK(Material(planet) == nil);
		OO_CHECK(!TextureName(planet).has_value());
	}
}


OO_TEST(copy)
{
	@autoreleasepool
	{
		SetUp();
		Planet atmosphere = AtmosphereWithRadius(321.0f);
		OOMaterial *material = NamedMaterial("air");
		SetMaterial(atmosphere, material);
		SetLevelOfDetail(atmosphere, 0.2f);

		Planet copy = Copy(atmosphere);
		OO_CHECK(copy != atmosphere);
		OO_CHECK(Radius(copy) == 321.0f);
		OO_CHECK(Material(copy) == material);
		OO_CHECK(!HasOpaqueParts(copy) && HasTranslucentParts(copy));
		OO_CHECK(Near(LevelOfDetail(copy), Level(0.2f)));
		BoundingBox box = Bounds(copy);
		OO_CHECK(box.max.x == 321.0f);

		// The copy is its own drawable.
		SetRadius(copy, 10.0f);
		OO_CHECK(Radius(atmosphere) == 321.0f && Radius(copy) == 10.0f);
	}
}


OO_TEST_MAIN()
