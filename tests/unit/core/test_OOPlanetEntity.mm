/*	test_OOPlanetEntity.mm
	Unit tests for OOPlanetEntity (src/Core/Entities/OOPlanetEntity.h), a planet or moon: bead
	oo-mp0d, a leaf of the Entities seam with a facade (proposed ADR-0056, amendments oo-bj8
	item 12, oo-0mxi and oo-ubjo).

	The planet reads the universe, PLAYER and the textures, so the test links the whole game but
	main (['*']). UNIVERSE is a Universe that was never initialised, subclassed to answer the system
	data (the planet's name and air density only, so its colours are its own), the time and minimum detail
	(no shaders); PLAYER is an entity that answers the clock and the nearest planet. Texture
	loading is replaced (method_setImplementation, as test_OOParticleSystem does) by a stand-in
	that records the configuration it was given and finds nothing, so the planet stops before it
	makes materials, as it does in the game when a texture file is missing. The RNG is seeded, and
	the values that depend on it are given in the planet's dictionary. The expectations were
	written against the Objective-C API and run on the unconverted class first: a planet's radius,
	energy, status, orientation and rotation from its dictionary, a moon and a planet with an
	atmosphere and its air colour, the shader-visible values and their setters, the miniature
	version, -update: turning the planet, close collisions and the description. The universe and
	the scripts make planets with alloc/-initFromDictionary:withAtmosphere:andSeed:forSystem:,
	which the conversion kept on the facade: the last test pins that its object is a C++ entity
	whose Objective-C object is the OOPlanetEntity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPlanetEntity.h"
#import "OOColor.h"
#import "OOTexture.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"
#include "legacy_random.h"

#include <cmath>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

@class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


@interface TestPlayer: Entity
{
@public
	double	_clock;
	id		_nearestPlanet;
}
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return kZeroHPVector; }
- (double) clockTimeAdjusted	{ return _clock; }
- (id) findNearestPlanet		{ return _nearestPlanet; }
- (OOSystemID) systemID			{ return 7; }

@end


// UNIVERSE: never initialised; answers the system data, the time and the detail level.
@interface TestUniverse: Universe
{
@public
	oo::PList	_systemData;
	double		_time;
	float		_airResistance;
}
@end


@implementation TestUniverse

- (oo::PList) cxx_generateSystemData:(OOSystemID)s		{ return _systemData; }
- (OOTimeAbsolute) getTime								{ return _time; }
- (OOGraphicsDetail) detailLevel						{ return DETAIL_LEVEL_MINIMUM; }
- (BOOL) reducedDetail									{ return YES; }
- (void) setAirResistanceFactor:(GLfloat)factor			{ _airResistance = factor; }

@end


namespace {

TestUniverse *sUniverse = nil;
TestPlayer *sPlayer = nil;
std::vector<std::string> sTexturesAsked;


// +[OOTexture cxx_textureWithConfiguration:]: records the name, finds nothing.
id NoTexture(id, SEL, const oo::PList &configuration)
{
	sTexturesAsked.push_back(configuration.get<std::string>("name", "?"));
	return nil;
}


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		new (&sUniverse->_systemData) oo::PList();
		sPlayer = [[TestPlayer alloc] init];
		Method load = class_getClassMethod([OOTexture class], sel_registerName("cxx_textureWithConfiguration:"));
		method_setImplementation(load, (IMP)NoTexture);
	}
	sUniverse->_systemData = oo::PList(oo::PList::Dict{ { "air_density", oo::PList(0.4) }, { "planet_name", oo::PList("Lave") } });
	sUniverse->_time = 0;
	sUniverse->_airResistance = -1;
	gSharedUniverse = sUniverse;
	gOOPlayer = (PlayerEntity *)sPlayer;
	sPlayer->_clock = 0;
	sPlayer->_nearestPlanet = nil;
	sTexturesAsked.clear();
	ranrot_srand(12345);
}


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


bool Near(double a, double b, double epsilon = 1e-4)
{
	return std::fabs(a - b) < epsilon;
}


bool QuaternionNear(Quaternion a, Quaternion b)
{
	return Near(a.w, b.w) && Near(a.x, b.x) && Near(a.y, b.y) && Near(a.z, b.z);
}


oo::PList PlanetDict(int radiusKm)
{
	return Dict({
		{ "radius", oo::PList(radiusKm) },
		{ "techlevel", oo::PList(8) },
		{ "texture", oo::PList("missing.png") },
		{ "rotational_velocity", oo::PList(0.02) },
		{ "atmosphere_rotational_velocity", oo::PList(0.01) },
		{ "air_color", oo::PList("0.2 0.4 0.6") },
		{ "air_color_mix_ratio", oo::PList(0.6) },
		{ "percent_cloud", oo::PList(40) },
	});
}


OOPlanetEntity *Planet(BOOL atmosphere, int radiusKm = 5000)
{
	Random_Seed seed = { 1, 2, 3, 4, 5, 6 };
	return [[[OOPlanetEntity alloc] initFromDictionary:PlanetDict(radiusKm) withAtmosphere:atmosphere andSeed:seed forSystem:7] autorelease];
}

}	// namespace


OO_TEST(moon)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		OO_CHECK(moon != nil && [moon isKindOfClass:[OOPlanetEntity class]]);
		OO_CHECK([moon radius] == 50000.0);
		OO_CHECK([moon collisionRadius] == 50000.0f);
		OO_CHECK([moon energy] == 50000.0f * 1000.0f);
		OO_CHECK([moon status] == STATUS_ACTIVE);
		OO_CHECK([moon scanClass] == CLASS_NO_DRAW);
		OO_CHECK([moon isPlanet] && [moon isVisible]);
		OO_CHECK([moon planetType] == STELLAR_TYPE_MOON);
		OO_CHECK(![moon hasAtmosphere]);
		OO_CHECK([moon rotationalVelocity] == (double)0.02f);
		OO_CHECK(QuaternionNear([moon orientation], (Quaternion){ (float)M_SQRT1_2, (float)M_SQRT1_2, 0, 0 }));
		OO_CHECK([moon airColor] == nil);
		OO_CHECK([moon airColorMixRatio] == 0.5f && [moon airDensity] == 0.75f);
		// The land parameters always set an illumination colour.
		OO_CHECK([moon illuminationColor] != nil);
		Vector threshold = [moon terminatorThresholdVector];
		OO_CHECK(Near(threshold.x, 0.105) && Near(threshold.y, 0.18) && Near(threshold.z, 0.28));
		// The texture was asked for as a cube map of the dictionary's name, and not found.
		OO_CHECK(sTexturesAsked.size() == 1 && sTexturesAsked[0] == "missing.png");
		OO_CHECK(![moon textureFileName].has_value());
		OO_CHECK([moon material] == nil && [moon atmosphereMaterial] == nil && [moon atmosphereShaderMaterial] == nil);
		OO_CHECK([moon isFinishedLoading]);
		// The system data's planet name, expanded.
		OO_CHECK([moon cxx_name] == std::optional<std::string>("Lave"));
	}
}


OO_TEST(planetWithAtmosphere)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *planet = Planet(YES);
		OO_CHECK([planet planetType] == STELLAR_TYPE_NORMAL_PLANET);
		OO_CHECK([planet hasAtmosphere]);
		// The dictionary's air colour, through its hue, saturation and brightness.
		OOColor *air = [planet airColor];
		OO_CHECK(air != nil);
		OO_CHECK(air != nil && Near([air redComponent], 0.2, 1e-3) && Near([air greenComponent], 0.4, 1e-3) && Near([air blueComponent], 0.6, 1e-3));
		Vector airVector = [planet airColorAsVector];
		OO_CHECK(Near(airVector.x, 0.2, 1e-3) && Near(airVector.y, 0.4, 1e-3) && Near(airVector.z, 0.6, 1e-3));
		OO_CHECK(Near([planet airColorMixRatio], 0.6));
		// The system data's air density.
		OO_CHECK(Near([planet airDensity], 0.4));
		OO_CHECK([planet rotationalVelocity] == (double)0.02f);
		OO_CHECK(sTexturesAsked.size() == 1);
	}
}


OO_TEST(clockTurnsThePlanet)
{
	@autoreleasepool
	{
		SetUp();
		sPlayer->_clock = 86400.0 * 3 + 100.0;	// 100 s into the day
		OOPlanetEntity *planet = Planet(NO);
		Quaternion expected = (Quaternion){ (float)M_SQRT1_2, (float)M_SQRT1_2, 0, 0 };
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(expected), 0.02f * 100);
		OO_CHECK(QuaternionNear([planet orientation], expected));
	}
}


OO_TEST(shaderValues)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *planet = Planet(NO);

		OOColor *red = [OOColor colorWithRed:1.0f green:0.0f blue:0.0f alpha:1.0f];
		[planet setAirColor:red];
		OO_CHECK([planet airColor] == red);
		[planet setAirColor:nil];		// ignored
		OO_CHECK([planet airColor] == red);
		Vector v = [planet airColorAsVector];
		OO_CHECK(v.x == 1.0f && v.y == 0.0f && v.z == 0.0f);

		OOColor *blue = [OOColor colorWithRed:0.0f green:0.0f blue:1.0f alpha:1.0f];
		[planet setIlluminationColor:blue];
		OO_CHECK([planet illuminationColor] == blue);
		[planet setIlluminationColor:nil];	// ignored
		OO_CHECK([planet illuminationColor] == blue);
		v = [planet illuminationColorAsVector];
		OO_CHECK(v.x == 0.0f && v.y == 0.0f && v.z == 1.0f);

		[planet setAirColorMixRatio:1.5f];
		OO_CHECK([planet airColorMixRatio] == 1.0f);
		[planet setAirColorMixRatio:0.25f];
		OO_CHECK([planet airColorMixRatio] == 0.25f);
		[planet setAirDensity:-1.0f];
		OO_CHECK([planet airDensity] == 0.0f);
		[planet setAirDensity:0.5f];
		OO_CHECK([planet airDensity] == 0.5f);

		[planet setTerminatorThresholdVector:make_vector(1, 2, 3)];
		Vector t = [planet terminatorThresholdVector];
		OO_CHECK(t.x == 1 && t.y == 2 && t.z == 3);

		[planet setRotationalVelocity:0.5];
		OO_CHECK([planet rotationalVelocity] == (double)0.5f);

		[planet cxx_setName:std::string("Diso")];
		OO_CHECK([planet cxx_name] == std::optional<std::string>("Diso"));
	}
}


OO_TEST(miniature)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *planet = Planet(YES);
		OOPlanetEntity *mini = [planet miniatureVersion];
		OO_CHECK(mini != nil && mini != planet && [mini isKindOfClass:[OOPlanetEntity class]]);
		OO_CHECK([mini planetType] == STELLAR_TYPE_MINIATURE);
		OO_CHECK([mini status] == STATUS_COCKPIT_DISPLAY);
		OO_CHECK([mini scanClass] == CLASS_NO_DRAW);
		OO_CHECK(Near([mini radius], 50000.0 * PLANET_MINIATURE_FACTOR));
		OO_CHECK([mini rotationalVelocity] == (double)0.04f);
		OO_CHECK(QuaternionNear([mini orientation], [planet orientation]));
		OO_CHECK([mini hasAtmosphere]);
		Vector t = [mini terminatorThresholdVector];
		OO_CHECK(Near(t.x, 0.105) && Near(t.y, 0.18) && Near(t.z, 0.28));
		// The original is unchanged.
		OO_CHECK([planet radius] == 50000.0 && [planet planetType] == STELLAR_TYPE_NORMAL_PLANET);
	}
}


OO_TEST(updateTurnsThePlanet)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		Quaternion before = [moon orientation];
		[moon update:10.0];
		Quaternion expected = before;
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(before), 0.02f * 10.0f);
		OO_CHECK(QuaternionNear([moon orientation], expected));

		// The nearest planet, out of its atmosphere, sets no air resistance.
		sPlayer->_nearestPlanet = moon;
		[moon update:1.0];
		OO_CHECK(sUniverse->_airResistance == 0.0f);
		sPlayer->_nearestPlanet = nil;

		// A miniature turns at its own rate.
		OOPlanetEntity *mini = [moon miniatureVersion];
		before = [mini orientation];
		[mini update:2.0];
		expected = before;
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(before), 0.04f * 2.0f);
		OO_CHECK(QuaternionNear([mini orientation], expected));
	}
}


OO_TEST(orientationSetsTheAxis)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		Quaternion q = kIdentityQuaternion;
		[moon setOrientation:q];
		[moon update:5.0];
		// Turned about the new up axis.
		Quaternion expected = q;
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(q), 0.02f * 5.0f);
		OO_CHECK(QuaternionNear([moon orientation], expected));
	}
}


OO_TEST(closeCollision)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		OO_CHECK(![moon checkCloseCollisionWith:nil]);
		Entity *rock = [[[Entity alloc] init] autorelease];
		OO_CHECK([moon checkCloseCollisionWith:rock]);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO, 3000);
		std::string description = oo::DescriptionOf(moon);
		OO_CHECK(description.find("OOPlanetEntity") != std::string::npos);
		OO_CHECK(description.find("radius: 30000 m") != std::string::npos);
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		OO_CHECK([moon class] == [OOPlanetEntity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<cxx::OOPlanetEntity *>(oo::ToCxx(moon)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(moon)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(moon)) == moon);
		OOPlanetEntity *mini = [moon miniatureVersion];
		OO_CHECK([mini class] == [OOPlanetEntity class] && dynamic_cast<cxx::OOPlanetEntity *>(oo::ToCxx(mini)) != nullptr);
	}
}


OO_TEST_MAIN()
