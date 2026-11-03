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
	the scripts made planets with alloc/-initFromDictionary:withAtmosphere:andSeed:forSystem:,
	which the conversion kept on the facade; bead oo-9ht.129 deleted the facade (standing approval
	oo-9n5p9): the cases make the C++ planet and its Objective-C object (oo::NewEntityFacade) and
	ask the C++ class, and the facade case pins the new crossing: its object is the root Entity's,
	which answers the shader binding selectors for a planet only.
	Run: bash tools/check-core-tests.sh
*/

#import "OOPlanetEntity.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#import "OOPlanetDrawable.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSEntity.h"
#import "OOJSPlanet.h"
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

class PlayerEntity;
extern PlayerEntity *gOOPlayer;
extern Universe *gSharedUniverse;


class TestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	double	_clock = {};
	OOPlanetEntity	*_nearestPlanet = {};	// the C++ planet since bead oo-9ht.129

	HPVector viewpointPosition() override	{ return kZeroHPVector; }
	double clockTimeAdjusted() override	{ return _clock; }
	::OOPlanetEntity * findNearestPlanet() override	{ return _nearestPlanet; }
	OOSystemID systemID() override	{ return 7; }
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
TestPlayer *sPlayer = nullptr;
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
		sUniverse->_cxxUniverse = oo::makeRef<cxx::Universe>(sUniverse);	// what -initWithGameView: makes first (ADR-0056 amendment oo-riqmz)
		new (&sUniverse->_systemData) oo::PList();
		sPlayer = NewTestPlayer<TestPlayer>();
		Method load = class_getClassMethod([OOTexture class], sel_registerName("cxx_textureWithConfiguration:"));
		method_setImplementation(load, (IMP)NoTexture);
	}
	sUniverse->_systemData = oo::PList(oo::PList::Dict{ { "air_density", oo::PList(0.4) }, { "planet_name", oo::PList("Lave") } });
	sUniverse->_time = 0;
	sUniverse->_airResistance = -1;
	gSharedUniverse = sUniverse;
	gOOPlayer = sPlayer;
	sPlayer->_clock = 0;
	sPlayer->_nearestPlanet = nullptr;
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


// alloc/initFromDictionary:withAtmosphere:andSeed:forSystem:/autorelease: a new C++ planet, owned by
// its autoreleased Objective-C object.
OOPlanetEntity *Planet(BOOL atmosphere, int radiusKm = 5000)
{
	Random_Seed seed = { 1, 2, 3, 4, 5, 6 };
	oo::Ref<OOPlanetEntity> planet = oo::makeRef<OOPlanetEntity>();
	(void)oo::NewEntityFacade(planet);
	planet->initFromDictionary(PlanetDict(radiusKm), atmosphere, seed, 7);
	return planet.get();
}


// -miniatureVersion: a new C++ planet, owned by its autoreleased Objective-C object.
OOPlanetEntity *Miniature(OOPlanetEntity *planet)
{
	oo::Ref<OOPlanetEntity> mini = planet->miniatureVersion();
	(void)oo::NewEntityFacade(mini);
	return mini.get();
}

}	// namespace


OO_TEST(moon)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		OO_CHECK(moon != nullptr && dynamic_cast<OOPlanetEntity *>(static_cast<cxx::Entity *>(moon)) != nullptr);
		OO_CHECK(moon->radius() == 50000.0);
		OO_CHECK(moon->collisionRadius() == 50000.0f);
		OO_CHECK(moon->getEnergy() == 50000.0f * 1000.0f);
		OO_CHECK(moon->status() == STATUS_ACTIVE);
		OO_CHECK(moon->getScanClass() == CLASS_NO_DRAW);
		OO_CHECK(moon->isPlanet() && moon->isVisible());
		OO_CHECK(moon->planetType() == STELLAR_TYPE_MOON);
		OO_CHECK(!moon->hasAtmosphere());
		OO_CHECK(moon->rotationalVelocity() == (double)0.02f);
		OO_CHECK(QuaternionNear(moon->getOrientation(), (Quaternion){ (float)M_SQRT1_2, (float)M_SQRT1_2, 0, 0 }));
		OO_CHECK(moon->airColor() == nil);
		OO_CHECK(moon->airColorMixRatio() == 0.5f && moon->airDensity() == 0.75f);
		// The land parameters always set an illumination colour.
		OO_CHECK(moon->illuminationColor() != nil);
		Vector threshold = moon->terminatorThresholdVector();
		OO_CHECK(Near(threshold.x, 0.105) && Near(threshold.y, 0.18) && Near(threshold.z, 0.28));
		// The texture was asked for as a cube map of the dictionary's name, and not found.
		OO_CHECK(sTexturesAsked.size() == 1 && sTexturesAsked[0] == "missing.png");
		OO_CHECK(!moon->textureFileName().has_value());
		OO_CHECK(moon->material() == nil && moon->atmosphereMaterial() == nil && moon->atmosphereShaderMaterial() == nil);
		OO_CHECK(moon->isFinishedLoading());
		// The system data's planet name, expanded.
		OO_CHECK(moon->name() == std::optional<std::string>("Lave"));
	}
}


OO_TEST(planetWithAtmosphere)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *planet = Planet(YES);
		OO_CHECK(planet->planetType() == STELLAR_TYPE_NORMAL_PLANET);
		OO_CHECK(planet->hasAtmosphere());
		// The dictionary's air colour, through its hue, saturation and brightness.
		OOColor *air = planet->airColor();
		OO_CHECK(air != nil);
		OO_CHECK(air != nil && Near(air->redComponent(), 0.2, 1e-3) && Near(air->greenComponent(), 0.4, 1e-3) && Near(air->blueComponent(), 0.6, 1e-3));
		Vector airVector = planet->airColorAsVector();
		OO_CHECK(Near(airVector.x, 0.2, 1e-3) && Near(airVector.y, 0.4, 1e-3) && Near(airVector.z, 0.6, 1e-3));
		OO_CHECK(Near(planet->airColorMixRatio(), 0.6));
		// The system data's air density.
		OO_CHECK(Near(planet->airDensity(), 0.4));
		OO_CHECK(planet->rotationalVelocity() == (double)0.02f);
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
		OO_CHECK(QuaternionNear(planet->getOrientation(), expected));
	}
}


OO_TEST(shaderValues)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *planet = Planet(NO);

		oo::Ref<OOColor>	red = OOColor::colorWithRed(1.0f, 0.0f, 0.0f, 1.0f);
		planet->setAirColor(red.get());
		OO_CHECK(planet->airColor() == red);
		planet->setAirColor(nullptr);		// ignored
		OO_CHECK(planet->airColor() == red);
		Vector v = planet->airColorAsVector();
		OO_CHECK(v.x == 1.0f && v.y == 0.0f && v.z == 0.0f);

		oo::Ref<OOColor>	blue = OOColor::colorWithRed(0.0f, 0.0f, 1.0f, 1.0f);
		planet->setIlluminationColor(blue.get());
		OO_CHECK(planet->illuminationColor() == blue);
		planet->setIlluminationColor(nullptr);	// ignored
		OO_CHECK(planet->illuminationColor() == blue);
		v = planet->illuminationColorAsVector();
		OO_CHECK(v.x == 0.0f && v.y == 0.0f && v.z == 1.0f);

		planet->setAirColorMixRatio(1.5f);
		OO_CHECK(planet->airColorMixRatio() == 1.0f);
		planet->setAirColorMixRatio(0.25f);
		OO_CHECK(planet->airColorMixRatio() == 0.25f);
		planet->setAirDensity(-1.0f);
		OO_CHECK(planet->airDensity() == 0.0f);
		planet->setAirDensity(0.5f);
		OO_CHECK(planet->airDensity() == 0.5f);

		planet->setTerminatorThresholdVector(make_vector(1, 2, 3));
		Vector t = planet->terminatorThresholdVector();
		OO_CHECK(t.x == 1 && t.y == 2 && t.z == 3);

		planet->setRotationalVelocity(0.5);
		OO_CHECK(planet->rotationalVelocity() == (double)0.5f);

		planet->setName(std::string("Diso"));
		OO_CHECK(planet->name() == std::optional<std::string>("Diso"));
	}
}


OO_TEST(miniature)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *planet = Planet(YES);
		OOPlanetEntity *mini = Miniature(planet);
		OO_CHECK(mini != nullptr && mini != planet && dynamic_cast<OOPlanetEntity *>(static_cast<cxx::Entity *>(mini)) != nullptr);
		OO_CHECK(mini->planetType() == STELLAR_TYPE_MINIATURE);
		OO_CHECK(mini->status() == STATUS_COCKPIT_DISPLAY);
		OO_CHECK(mini->getScanClass() == CLASS_NO_DRAW);
		OO_CHECK(Near(mini->radius(), 50000.0 * PLANET_MINIATURE_FACTOR));
		OO_CHECK(mini->rotationalVelocity() == (double)0.04f);
		OO_CHECK(QuaternionNear(mini->getOrientation(), planet->getOrientation()));
		OO_CHECK(mini->hasAtmosphere());
		Vector t = mini->terminatorThresholdVector();
		OO_CHECK(Near(t.x, 0.105) && Near(t.y, 0.18) && Near(t.z, 0.28));
		// The original is unchanged.
		OO_CHECK(planet->radius() == 50000.0 && planet->planetType() == STELLAR_TYPE_NORMAL_PLANET);
	}
}


OO_TEST(updateTurnsThePlanet)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		Quaternion before = moon->getOrientation();
		moon->update(10.0);
		Quaternion expected = before;
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(before), 0.02f * 10.0f);
		OO_CHECK(QuaternionNear(moon->getOrientation(), expected));

		// The nearest planet, out of its atmosphere, sets no air resistance.
		sPlayer->_nearestPlanet = moon;
		moon->update(1.0);
		OO_CHECK(sUniverse->_airResistance == 0.0f);
		sPlayer->_nearestPlanet = nullptr;

		// A miniature turns at its own rate.
		OOPlanetEntity *mini = Miniature(moon);
		before = mini->getOrientation();
		mini->update(2.0);
		expected = before;
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(before), 0.04f * 2.0f);
		OO_CHECK(QuaternionNear(mini->getOrientation(), expected));
	}
}


OO_TEST(orientationSetsTheAxis)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		Quaternion q = kIdentityQuaternion;
		moon->setOrientation(q);
		moon->update(5.0);
		// Turned about the new up axis.
		Quaternion expected = q;
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(q), 0.02f * 5.0f);
		OO_CHECK(QuaternionNear(moon->getOrientation(), expected));
	}
}


OO_TEST(closeCollision)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		OO_CHECK(!moon->checkCloseCollisionWith(nullptr));
		Entity *rock = [[[Entity alloc] init] autorelease];
		OO_CHECK(moon->checkCloseCollisionWith(oo::ToCxx(rock)));
	}
}


OO_TEST(description)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO, 3000);
		std::string description = oo::DescriptionOf(oo::ToObjC(moon));
		OO_CHECK(description.find("OOPlanetEntity") != std::string::npos);
		OO_CHECK(description.find("radius: 30000 m") != std::string::npos);
	}
}


// The facade was deleted by bead oo-9ht.129 (ADR-0056 amendment oo-9ht.12 item 6): a planet's
// object is the root Entity's facade, whose C++ part is the planet; that object answers the shader
// binding selectors (Entity (OOPlanetShaderBindings)) for a planet only.
OO_TEST(facade)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		Entity *object = oo::ToObjC(moon);
		OO_CHECK(object != nil && [object class] == [Entity class]);
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(oo::ToCxx(object) == moon);
		OO_CHECK(oo::AsObjCEntity(moon) == nullptr);
		OOPlanetEntity *mini = Miniature(moon);
		OO_CHECK([oo::ToObjC(mini) class] == [Entity class] && oo::ToCxx(oo::ToObjC(mini)) == mini);

		// The shader bindings, by selector: the planet's values, and no other entity binds them.
		OO_CHECK([object respondsToSelector:@selector(airColorAsVector)] && [object respondsToSelector:@selector(terminatorThresholdVector)]);
		OO_CHECK([object respondsToSelector:@selector(airColorMixRatio)] && [object respondsToSelector:@selector(airDensity)] && [object respondsToSelector:@selector(illuminationColorAsVector)]);
		moon->setAirDensity(0.5f);
		moon->setTerminatorThresholdVector(make_vector(1, 2, 3));
		// Called as the uniforms call them: the implementation found by selector.
		float (*floatValue)(id, SEL) = (float (*)(id, SEL))[object methodForSelector:@selector(airDensity)];
		OO_CHECK(floatValue(object, @selector(airDensity)) == 0.5f);
		floatValue = (float (*)(id, SEL))[object methodForSelector:@selector(airColorMixRatio)];
		OO_CHECK(floatValue(object, @selector(airColorMixRatio)) == moon->airColorMixRatio());
		Vector (*vectorValue)(id, SEL) = (Vector (*)(id, SEL))[object methodForSelector:@selector(terminatorThresholdVector)];
		Vector t = vectorValue(object, @selector(terminatorThresholdVector));
		OO_CHECK(t.x == 1 && t.y == 2 && t.z == 3);
		Entity *rock = [[[Entity alloc] init] autorelease];
		OO_CHECK(![rock respondsToSelector:@selector(airColorAsVector)] && ![rock respondsToSelector:@selector(airDensity)]);
		OO_CHECK([rock respondsToSelector:@selector(relativePosition)]);
	}
}


// Registers Entity's JS class and the given class (a child of Entity) in the test's context, as the
// engine's start does; the context is made here if the test has none yet.
static void RegisterJSClasses(void (*initClass)(JSContext *, JSValueConst))
{
	extern JSContext *gOOJSMainThreadContext;
	if (gOOJSMainThreadContext == nullptr)  gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
	JSContext *context = OOJSAcquireContext();
	JSValue global = JS_GetGlobalObject(context);
	InitOOJSEntity(context, global);
	initClass(context, global);
	JS_FreeValue(context, global);
}


// The binding's category, which the facade carried and the C++ planet's overrides answer now:
// what the engine asks a planet's object for by selector is what OOJSPlanet.mm answers.
OO_TEST(jsExtensions)
{
	@autoreleasepool
	{
		SetUp();
		OOPlanetEntity *moon = Planet(NO);
		RegisterJSClasses(InitOOJSPlanet);
		Entity *object = oo::ToObjC(moon);
		const JSClassID jsClass = [object oo_jsClassID];
		const JSClassID expectedClass = JSPlanetClassID();
		OO_CHECK(jsClass != 0 && jsClass == expectedClass);
		OO_CHECK([object cxx_oo_jsClassName] == std::optional<std::string>("Moon"));
		OO_CHECK([object isVisibleToScripts] == YES);
	}
}


OO_TEST_MAIN()
