/*	test_OOPlanetEntity.mm
	Unit tests for OOPlanetEntity (src/Core/Entities/OOPlanetEntity.h), a planet or moon.

	The planet reads the universe, PLAYER and the textures, so the test links the whole game but
	main (['*']). UNIVERSE is a Universe that was never initialised, subclassed to answer the system
	data (the planet's name and air density only, so its colours are its own), the time and minimum
	detail (no shaders); PLAYER is an entity that answers the clock and the nearest planet. Texture
	loading is replaced (method_setImplementation, as test_OOParticleSystem does) by a stand-in that
	records the configuration it was given and finds nothing, so the planet stops before it makes
	materials, as it does in the game when a texture file is missing. The RNG is seeded, and the
	values that depend on it are given in the planet's dictionary. A planet's radius, energy,
	status, orientation and rotation from its dictionary, a moon and a planet with an atmosphere and
	its air colour, the shader-visible values and their setters, the miniature version, -update:
	turning the planet, close collisions and the description. The cases make the C++ planet and ask
	the C++ class, and the facade case pins the
	crossing: the root Entity answers the shader binding selectors for a
	planet only. Run: bash tools/check-core-tests.sh
*/

#include "OOPlanetEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++
#include "OOPlanetDrawable.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSPlanet.h"
#include "OOColor.h"
#include "OOTexture.h"
#include "OODescription.h"
#include "Universe.h"

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


class TestPlayer : public PlayerEntity
{
public:
	double	_clock = {};
	OOPlanetEntity	*_nearestPlanet = {};	// the C++ planet

	HPVector viewpointPosition() override	{ return kZeroHPVector; }
	double clockTimeAdjusted() override	{ return _clock; }
	::OOPlanetEntity * findNearestPlanet() override	{ return _nearestPlanet; }
	OOSystemID systemID() override	{ return 7; }
};

// A C++ player, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1).
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}




// UNIVERSE: never initialised; answers the system data, the time and the detail level.
class TestUniverse : public Universe
{
public:
	oo::PList _systemData = {};
	OOTimeAbsolute &_time = universal_time;	// the universe's own state, which its getter answers
	GLfloat &_airResistance = airResistanceFactor;	// the universe's own state, which setAirResistanceFactor() sets

	oo::PList generateSystemData(OOSystemID /*s*/, bool /*useCache*/) override	{ return _systemData; }
	bool reducedDetail() override	{ return true; }
};


namespace {

TestUniverse *sUniverse = nullptr;
TestPlayer *sPlayer = nullptr;
std::vector<std::string> sTexturesAsked;


// OOTexture::configurationFactory, the test-only loader hook: records the name,
// finds nothing.
oo::Ref<OOTexture> NoTexture(const oo::PList &configuration)
{
	sTexturesAsked.push_back(configuration.get<std::string>("name", "?"));
	return nullptr;
}


void SetUp()
{
	if (sUniverse == nullptr)
	{
		sUniverse = new TestUniverse();	// never released
		new (&sUniverse->_systemData) oo::PList();
		sPlayer = NewTestPlayer<TestPlayer>();
		OOTexture::configurationFactory = &NoTexture;
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


// A new C++ planet.
OOPlanetEntity *Planet(BOOL atmosphere, int radiusKm = 5000)
{
	Random_Seed seed = { 1, 2, 3, 4, 5, 6 };
	oo::Ref<OOPlanetEntity> planet = oo::makeRef<OOPlanetEntity>();
	(void)oo::MadeEntity(planet);
	planet->initFromDictionary(PlanetDict(radiusKm), atmosphere, seed, 7);
	return planet.get();
}


// The miniature version: a new C++ planet.
OOPlanetEntity *Miniature(OOPlanetEntity *planet)
{
	oo::Ref<OOPlanetEntity> mini = planet->miniatureVersion();
	(void)oo::MadeEntity(mini);
	return mini.get();
}

}	// namespace


OO_TEST(moon)
{
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false);
		OO_CHECK(moon != nullptr && dynamic_cast<OOPlanetEntity *>(static_cast<Entity *>(moon)) != nullptr);
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
		OO_CHECK(moon->airColor() == nullptr);
		OO_CHECK(moon->airColorMixRatio() == 0.5f && moon->airDensity() == 0.75f);
		// The land parameters always set an illumination colour.
		OO_CHECK(moon->illuminationColor() != nullptr);
		Vector threshold = moon->terminatorThresholdVector();
		OO_CHECK(Near(threshold.x, 0.105) && Near(threshold.y, 0.18) && Near(threshold.z, 0.28));
		// The texture was asked for as a cube map of the dictionary's name, and not found.
		OO_CHECK(sTexturesAsked.size() == 1 && sTexturesAsked[0] == "missing.png");
		OO_CHECK(!moon->textureFileName().has_value());
		OO_CHECK(moon->material() == nullptr && moon->atmosphereMaterial() == nullptr && moon->atmosphereShaderMaterial() == nullptr);
		OO_CHECK(moon->isFinishedLoading());
		// The system data's planet name, expanded.
		OO_CHECK(moon->name() == std::optional<std::string>("Lave"));
	}
}


OO_TEST(planetWithAtmosphere)
{
	{
		SetUp();
		OOPlanetEntity *planet = Planet(true);
		OO_CHECK(planet->planetType() == STELLAR_TYPE_NORMAL_PLANET);
		OO_CHECK(planet->hasAtmosphere());
		// The dictionary's air colour, through its hue, saturation and brightness.
		OOColor *air = planet->airColor();
		OO_CHECK(air != nullptr);
		OO_CHECK(air != nullptr && Near(air->redComponent(), 0.2, 1e-3) && Near(air->greenComponent(), 0.4, 1e-3) && Near(air->blueComponent(), 0.6, 1e-3));
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
	{
		SetUp();
		sPlayer->_clock = 86400.0 * 3 + 100.0;	// 100 s into the day
		OOPlanetEntity *planet = Planet(false);
		Quaternion expected = (Quaternion){ (float)M_SQRT1_2, (float)M_SQRT1_2, 0, 0 };
		quaternion_rotate_about_axis(&expected, vector_up_from_quaternion(expected), 0.02f * 100);
		OO_CHECK(QuaternionNear(planet->getOrientation(), expected));
	}
}


OO_TEST(shaderValues)
{
	{
		SetUp();
		OOPlanetEntity *planet = Planet(false);

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
	{
		SetUp();
		OOPlanetEntity *planet = Planet(true);
		OOPlanetEntity *mini = Miniature(planet);
		OO_CHECK(mini != nullptr && mini != planet && dynamic_cast<OOPlanetEntity *>(static_cast<Entity *>(mini)) != nullptr);
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
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false);
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
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false);
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
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false);
		OO_CHECK(!moon->checkCloseCollisionWith(nullptr));
		Entity *rock = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK(moon->checkCloseCollisionWith(rock));
	}
}


OO_TEST(description)
{
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false, 3000);
		std::string description = oo::EntityDescription(moon);
		OO_CHECK(description.find("OOPlanetEntity") != std::string::npos);
		OO_CHECK(description.find("radius: 30000 m") != std::string::npos);
	}
}


// A planet is the root Entity; it answers the shader binding selectors (Entity
// (OOPlanetShaderBindings)) for a planet only.
OO_TEST(facade)
{
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false);
		Entity *object = moon;
		OO_CHECK(object != nil);	// A C++ entity.
		OO_CHECK(object == moon);
		OOPlanetEntity *mini = Miniature(moon);
		OO_CHECK(mini == mini);	// The shader bindings: the planet's values, which its object's selectors
    // forward to.
		moon->setAirDensity(0.5f);
		moon->setTerminatorThresholdVector(make_vector(1, 2, 3));
		OO_CHECK(moon->airDensity() == 0.5f);
		Vector t = moon->terminatorThresholdVector();
		OO_CHECK(t.x == 1 && t.y == 2 && t.z == 3);
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


// The binding's category, which the C++ planet's overrides answer: what the
// engine asks a planet's object for by selector is what OOJSPlanet.mm answers.
OO_TEST(jsExtensions)
{
	{
		SetUp();
		OOPlanetEntity *moon = Planet(false);
		RegisterJSClasses(InitOOJSPlanet);
		Entity *object = moon;
		const JSClassID jsClass = OOJSEntityJSClassID(object);
		const JSClassID expectedClass = JSPlanetClassID();
		OO_CHECK(jsClass != 0 && jsClass == expectedClass);
		OO_CHECK(OOJSEntityJSClassName(object) == std::optional<std::string>("Moon"));
		OO_CHECK(OOJSEntityIsVisibleToScripts(object) == true);
	}
}


OO_TEST_MAIN()
