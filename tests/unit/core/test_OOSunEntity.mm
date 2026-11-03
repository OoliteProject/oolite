/*	test_OOSunEntity.mm
	Unit tests for OOSunEntity (src/Core/Entities/OOSunEntity.h), a system's star: bead oo-ubjo, a
	leaf of the Entities seam with a facade (proposed ADR-0056, amendments oo-bj8 item 12 and
	oo-0mxi).

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised (minimum detail, so the corona never moves),
	subclassed to record the main light position, the sky colour and the system data the sun sets,
	and an entity that answers the viewpoint the test sets as PLAYER. The expectations were written
	against the Objective-C API and run on the unconverted class first: a sun's radius, name and
	corona come from its dictionary, it is a no-draw, visible, collidable sun; its light colours
	are its colour blended with white; -changeSunProperty:withDictionary: takes the radius, the
	name, the corona, and going nova or not, and refuses anything else; a new position moves the
	main light; going nova counts down, then whitens the sky and records the nova and the growing
	radius in the system data; and the camera-relative position is pulled in to 1e9 for a far sun.
	The camera-relative position is read through the one helper below. The universe makes the sun
	with alloc/initSunWithColor:andDictionary:, which the conversion kept on the facade: the last
	test pins that its object is a C++ entity whose Objective-C object is the OOSunEntity facade.
	Run: bash tools/check-core-tests.sh
*/

#import "OOSunEntity.h"
#import "OOColor.h"
#import "OODescription.h"
#import "Universe.h"

#include "oo_test.hpp"
#include "oofnd/PListGet.hpp"

#include <cmath>
#include <map>
#include <string>


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
	HPVector	_viewpoint;
}
@end


@implementation TestPlayer

- (HPVector) viewpointPosition	{ return _viewpoint; }

@end


// UNIVERSE: never initialised; records what the sun sets.
@interface TestUniverse: Universe
{
@public
	Vector							_mainLight;
	GLfloat							_sky[4];
	int								_skySets;
	std::map<std::string, oo::PList>	_systemData;
}
@end


@implementation TestUniverse

- (OOTimeAbsolute) getTime	{ return 0; }

- (void) setMainLightPosition:(Vector)sunPos	{ _mainLight = sunPos; }


- (void) setSkyColorRed:(GLfloat)red green:(GLfloat)green blue:(GLfloat)blue alpha:(GLfloat)alpha
{
	_sky[0] = red;  _sky[1] = green;  _sky[2] = blue;  _sky[3] = alpha;
	_skySets++;
}


- (void) cxx_setSystemDataKey:(const std::string &)key value:(const oo::PList &)value fromManifest:(const std::optional<std::string> &)manifest
{
	_systemData[key] = value;
}

@end


namespace {

TestUniverse *sUniverse = nil;
TestPlayer *sPlayer = nil;


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = (TestUniverse *)class_createInstance([TestUniverse class], 0);	// never released
		new (&sUniverse->_systemData) std::map<std::string, oo::PList>();
		sPlayer = [[TestPlayer alloc] init];
	}
	sUniverse->_skySets = 0;
	sUniverse->_systemData.clear();
	sUniverse->_mainLight = kZeroVector;
	gSharedUniverse = sUniverse;
	gOOPlayer = (PlayerEntity *)sPlayer;
	sPlayer->_viewpoint = kZeroHPVector;
}


// --- Ivars the test reads, and nothing else ---------------------------------------------------------

Vector CameraRelativePosition(Entity *e)	{ return e->_cxxEntity->cameraRelativePosition; }

// --------------------------------------------------------------------------------------------------


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


OOSunEntity *Sun(OOColor *color, double radius)
{
	return [[[OOSunEntity alloc] initSunWithColor:color andDictionary:Dict({
		{ "sun_name", oo::PList("Sol") },
		{ "sun_radius", oo::PList(radius) },
		{ "corona_flare", oo::PList(0.5) },
		{ "corona_shimmer", oo::PList(0.5) },
	})] autorelease];
}


OOSunEntity *RedSun()
{
	return Sun([OOColor colorWithRed:1.0f green:0.0f blue:0.0f alpha:1.0f], 1000.0);
}

}	// namespace


OO_TEST(made)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		OO_CHECK(sun != nil && [sun isKindOfClass:[OOSunEntity class]]);
		OO_CHECK([sun radius] == 1000.0 && [sun collisionRadius] == 1000.0f);
		OO_CHECK([sun cxx_name] == std::optional<std::string>("Sol"));
		OO_CHECK([sun planetType] == STELLAR_TYPE_SUN);
		OO_CHECK([sun scanClass] == CLASS_NO_DRAW);
		OO_CHECK([sun isSun] && [sun isVisible] && [sun canCollide]);
		OO_CHECK(![sun willGoNova] && ![sun goneNova]);
	}
}


OO_TEST(lightColours)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		// Red blended 30% with white: (1, 0.3, 0.3).
		GLfloat diffuse[4] = { -1, -1, -1, -1 };
		GLfloat specular[4] = { -1, -1, -1, -1 };
		[sun getDiffuseComponents:diffuse];
		[sun getSpecularComponents:specular];
		OO_CHECK(Near(specular[0], 1.0) && Near(specular[1], 0.3) && Near(specular[2], 0.3) && specular[3] == 1.0f);
		OO_CHECK(Near(diffuse[0], 1.0) && Near(diffuse[1], 0.65) && Near(diffuse[2], 0.65) && diffuse[3] == 1.0f);

		OO_CHECK([sun setSunColor:[OOColor blueColor]]);
		[sun getSpecularComponents:specular];
		OO_CHECK(Near(specular[0], 0.3) && Near(specular[1], 0.3) && Near(specular[2], 1.0));
		OO_CHECK(![sun setSunColor:nil]);
		[sun getSpecularComponents:specular];
		OO_CHECK(Near(specular[2], 1.0));
	}
}


OO_TEST(changeSunProperty)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		OO_CHECK([sun changeSunProperty:"sun_radius" withDictionary:Dict({ { "sun_radius", oo::PList(2500.0) } })]);
		OO_CHECK([sun radius] == 2500.0);
		OO_CHECK([sun changeSunProperty:"sun_name" withDictionary:Dict({ { "sun_name", oo::PList("Alpha") } })]);
		OO_CHECK([sun cxx_name] == std::optional<std::string>("Alpha"));
		OO_CHECK([sun changeSunProperty:"sun_name" withDictionary:Dict({})]);
		OO_CHECK(![sun cxx_name].has_value());
		OO_CHECK([sun changeSunProperty:"corona_flare" withDictionary:Dict({ { "corona_flare", oo::PList(0.25) } })]);
		OO_CHECK([sun radius] == 2500.0);
		OO_CHECK([sun changeSunProperty:"corona_shimmer" withDictionary:Dict({ { "corona_shimmer", oo::PList(0.5) } })]);
		OO_CHECK([sun changeSunProperty:"corona_hues" withDictionary:Dict({ { "corona_hues", oo::PList(0.5) } })]);

		OO_CHECK([sun changeSunProperty:"sun_gone_nova" withDictionary:Dict({ { "sun_gone_nova", oo::PList(true) } })]);
		OO_CHECK([sun willGoNova] && [sun goneNova]);
		OO_CHECK([sun changeSunProperty:"sun_gone_nova" withDictionary:Dict({ { "sun_gone_nova", oo::PList(false) }, { "corona_flare", oo::PList(0.1) } })]);
		OO_CHECK(![sun willGoNova] && ![sun goneNova]);
		OO_CHECK([sun radius] == 2500.0);	// the radius it had before going nova

		OO_CHECK(![sun changeSunProperty:"sun_color" withDictionary:Dict({ { "sun_color", oo::PList("redColor") } })]);
	}
}


OO_TEST(radiusAndPosition)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		[sun setRadius:300.0f andCorona:0.0f];
		OO_CHECK([sun radius] == 300.0);
		[sun setPosition:make_HPvector(10, 20, 30)];
		OO_CHECK(HPvector_equal([sun position], make_HPvector(10, 20, 30)));
		OO_CHECK(sUniverse->_mainLight.x == 10 && sUniverse->_mainLight.y == 20 && sUniverse->_mainLight.z == 30);
	}
}


OO_TEST(goingNova)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		[sun setGoingNova:YES inTime:1.0];
		OO_CHECK([sun willGoNova] && ![sun goneNova]);
		[sun update:0.5];
		OO_CHECK(![sun goneNova] && sUniverse->_skySets == 0);
		[sun update:0.625];
		OO_CHECK([sun goneNova] && sUniverse->_skySets == 0);

		// The expansion: the sky goes white and the nova is recorded.
		[sun update:0.125];
		OO_CHECK(sUniverse->_skySets == 1 && sUniverse->_sky[0] == 1.0f && sUniverse->_sky[3] == 1.0f);
		OO_CHECK(sUniverse->_systemData["sun_gone_nova"] == oo::PList(static_cast<bool>(true)));	// a boolean (OOCocoa.h defines true as 1)
		OO_CHECK(sUniverse->_systemData.count("corona_flare") == 1 && sUniverse->_systemData.count("corona_hues") == 1);
		OO_CHECK(Near(oo::PListGet<double>::from(&sUniverse->_systemData["sun_radius"], -1.0), 1000.0 + 0.125 * 10000.0));

		// Later in the minute: the sky fades, nothing more recorded but the radius.
		sUniverse->_systemData.clear();
		[sun update:1.0];
		OO_CHECK(sUniverse->_skySets == 2 && sUniverse->_sky[0] == 0.8125f && sUniverse->_sky[3] == 1.0f);
		OO_CHECK(sUniverse->_systemData.count("sun_gone_nova") == 0 && sUniverse->_systemData.count("sun_radius") == 1);
		// Then it goes black.
		[sun update:0.125];
		OO_CHECK(sUniverse->_skySets == 3 && sUniverse->_sky[0] == 0.0f && sUniverse->_sky[3] == 0.0f);

		[sun resetNova];
		OO_CHECK([sun willGoNova] && [sun goneNova]);	// reset keeps the higher temperature
		[sun setGoingNova:NO inTime:0];
		OO_CHECK(![sun willGoNova]);
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		[sun setGoingNova:YES inTime:10.0];
		const std::string description = oo::DescriptionOf(sun);
		OO_CHECK(description.find("radius: 1.000km") != std::string::npos);
		OO_CHECK(description.find("(will go nova)") != std::string::npos);
	}
}


OO_TEST(cameraRelativePosition)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		[sun setPosition:make_HPvector(100, 0, 0)];
		sPlayer->_viewpoint = make_HPvector(40, 0, 0);
		[sun updateCameraRelativePosition];
		Vector v = CameraRelativePosition(sun);
		OO_CHECK(v.x == 60.0f && v.y == 0.0f && v.z == 0.0f);

		[sun setPosition:make_HPvector(4e9, 0, 3e9)];
		sPlayer->_viewpoint = kZeroHPVector;
		[sun updateCameraRelativePosition];
		v = CameraRelativePosition(sun);
		OO_CHECK(Near(v.x / 1e9, 0.8) && Near(v.z / 1e9, 0.6));
	}
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		OO_CHECK([sun class] == [OOSunEntity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<cxx::OOSunEntity *>(oo::ToCxx(sun)) != nullptr);
		OO_CHECK(oo::AsObjCEntity(oo::ToCxx(sun)) == nullptr);
		OO_CHECK(oo::ToObjC(oo::ToCxx(sun)) == sun);
	}
}


OO_TEST_MAIN()
