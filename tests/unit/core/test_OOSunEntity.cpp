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
	The camera-relative position is read through the one helper below. The universe made the sun
	with alloc/initSunWithColor:andDictionary:, which the conversion kept on the facade; bead
	oo-9ht.111 deleted the facade (standing approval oo-9n5p9): the cases make the C++ sun and its
	Objective-C object (oo::NewEntityFacade) and ask the C++ class, and the facade case pins the new
	crossing: its object is the root Entity's.
	Run: bash tools/check-core-tests.sh
*/

#include "OOSunEntity.h"
#include "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSSun.h"
#include "OOColor.h"
#include "OODescription.h"
#include "Universe.h"

#include "oo_test.hpp"
#include "oofnd/PListGet.hpp"

#include <cmath>
#include <map>
#include <string>


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
	HPVector	_viewpoint = {};

	HPVector viewpointPosition() override	{ return _viewpoint; }
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}




// UNIVERSE: never initialised; records what the sun sets.
class TestUniverse : public Universe
{
public:
	Vector _mainLight = {};
	GLfloat							_sky[4];
	int _skySets = {};
	std::map<std::string, oo::PList> _systemData = {};

	void setMainLightPosition(Vector sunPos) override	{ _mainLight = sunPos; }
	void setSkyColorRed(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) override
	{
		_sky[0] = red;  _sky[1] = green;  _sky[2] = blue;  _sky[3] = alpha;
		_skySets++;
	}
	void setSystemDataKey(const std::string &key, const oo::PList &value, const std::optional<std::string> &/*manifest*/) override	{ _systemData[key] = value; }
};


namespace {

TestUniverse *sUniverse = nil;
TestPlayer *sPlayer = nullptr;


void SetUp()
{
	if (sUniverse == nil)
	{
		sUniverse = new TestUniverse();	// never released
		new (&sUniverse->_systemData) std::map<std::string, oo::PList>();
		sPlayer = NewTestPlayer<TestPlayer>();
	}
	sUniverse->_skySets = 0;
	sUniverse->_systemData.clear();
	sUniverse->_mainLight = kZeroVector;
	gSharedUniverse = sUniverse;
	gOOPlayer = sPlayer;
	sPlayer->_viewpoint = kZeroHPVector;
}


// --- Ivars the test reads, and nothing else ---------------------------------------------------------

Vector CameraRelativePosition(Entity *e)	{ return e->cameraRelativePosition; }	// the C++ sun since bead oo-9ht.111

// --------------------------------------------------------------------------------------------------


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


// alloc/initSunWithColor:andDictionary:/autorelease: a new C++ sun, owned by its autoreleased
// Objective-C object.
OOSunEntity *Sun(OOColor *color, double radius)
{
	oo::Ref<OOSunEntity> sun = oo::makeRef<OOSunEntity>();
	(void)oo::MadeEntity(sun);
	sun->initSunWithColor(color, Dict({
		{ "sun_name", oo::PList("Sol") },
		{ "sun_radius", oo::PList(radius) },
		{ "corona_flare", oo::PList(0.5) },
		{ "corona_shimmer", oo::PList(0.5) },
	}));
	return sun.get();
}


OOSunEntity *RedSun()
{
	return Sun(OOColor::colorWithRed(1.0f, 0.0f, 0.0f, 1.0f).get(), 1000.0);
}

}	// namespace


OO_TEST(made)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		OO_CHECK(sun != nullptr && dynamic_cast<OOSunEntity *>(static_cast<Entity *>(sun)) != nullptr);
		OO_CHECK(sun->radius() == 1000.0 && sun->collisionRadius() == 1000.0f);
		OO_CHECK(sun->name() == std::optional<std::string>("Sol"));
		OO_CHECK(sun->planetType() == STELLAR_TYPE_SUN);
		OO_CHECK(sun->getScanClass() == CLASS_NO_DRAW);
		OO_CHECK(sun->isSun() && sun->isVisible() && sun->canCollide());
		OO_CHECK(!sun->willGoNova() && !sun->goneNova());
	}
}


OO_TEST(lightColours)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		// Red blended 30% with white: (1, 0.3, 0.3).
		GLfloat diffuse[4] = { -1, -1, -1, -1 };
		GLfloat specular[4] = { -1, -1, -1, -1 };
		sun->getDiffuseComponents(diffuse);
		sun->getSpecularComponents(specular);
		OO_CHECK(Near(specular[0], 1.0) && Near(specular[1], 0.3) && Near(specular[2], 0.3) && specular[3] == 1.0f);
		OO_CHECK(Near(diffuse[0], 1.0) && Near(diffuse[1], 0.65) && Near(diffuse[2], 0.65) && diffuse[3] == 1.0f);

		OO_CHECK(sun->setSunColor(OOColor::blueColor().get()));
		sun->getSpecularComponents(specular);
		OO_CHECK(Near(specular[0], 0.3) && Near(specular[1], 0.3) && Near(specular[2], 1.0));
		OO_CHECK(!sun->setSunColor(nullptr));
		sun->getSpecularComponents(specular);
		OO_CHECK(Near(specular[2], 1.0));
	}
}


OO_TEST(changeSunProperty)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		OO_CHECK(sun->changeSunProperty("sun_radius", Dict({ { "sun_radius", oo::PList(2500.0) } })));
		OO_CHECK(sun->radius() == 2500.0);
		OO_CHECK(sun->changeSunProperty("sun_name", Dict({ { "sun_name", oo::PList("Alpha") } })));
		OO_CHECK(sun->name() == std::optional<std::string>("Alpha"));
		OO_CHECK(sun->changeSunProperty("sun_name", Dict({})));
		OO_CHECK(!sun->name().has_value());
		OO_CHECK(sun->changeSunProperty("corona_flare", Dict({ { "corona_flare", oo::PList(0.25) } })));
		OO_CHECK(sun->radius() == 2500.0);
		OO_CHECK(sun->changeSunProperty("corona_shimmer", Dict({ { "corona_shimmer", oo::PList(0.5) } })));
		OO_CHECK(sun->changeSunProperty("corona_hues", Dict({ { "corona_hues", oo::PList(0.5) } })));

		OO_CHECK(sun->changeSunProperty("sun_gone_nova", Dict({ { "sun_gone_nova", oo::PList(true) } })));
		OO_CHECK(sun->willGoNova() && sun->goneNova());
		OO_CHECK(sun->changeSunProperty("sun_gone_nova", Dict({ { "sun_gone_nova", oo::PList(false) }, { "corona_flare", oo::PList(0.1) } })));
		OO_CHECK(!sun->willGoNova() && !sun->goneNova());
		OO_CHECK(sun->radius() == 2500.0);	// the radius it had before going nova

		OO_CHECK(!sun->changeSunProperty("sun_color", Dict({ { "sun_color", oo::PList("redColor") } })));
	}
}


OO_TEST(radiusAndPosition)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		sun->setRadius(300.0f, 0.0f);
		OO_CHECK(sun->radius() == 300.0);
		sun->setPosition(make_HPvector(10, 20, 30));
		OO_CHECK(HPvector_equal(sun->getPosition(), make_HPvector(10, 20, 30)));
		OO_CHECK(sUniverse->_mainLight.x == 10 && sUniverse->_mainLight.y == 20 && sUniverse->_mainLight.z == 30);
	}
}


OO_TEST(goingNova)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		sun->setGoingNova(YES, 1.0);
		OO_CHECK(sun->willGoNova() && !sun->goneNova());
		sun->update(0.5);
		OO_CHECK(!sun->goneNova() && sUniverse->_skySets == 0);
		sun->update(0.625);
		OO_CHECK(sun->goneNova() && sUniverse->_skySets == 0);

		// The expansion: the sky goes white and the nova is recorded.
		sun->update(0.125);
		OO_CHECK(sUniverse->_skySets == 1 && sUniverse->_sky[0] == 1.0f && sUniverse->_sky[3] == 1.0f);
		OO_CHECK(sUniverse->_systemData["sun_gone_nova"] == oo::PList(static_cast<bool>(true)));	// a boolean (OOCocoa.h defines true as 1)
		OO_CHECK(sUniverse->_systemData.count("corona_flare") == 1 && sUniverse->_systemData.count("corona_hues") == 1);
		OO_CHECK(Near(oo::PListGet<double>::from(&sUniverse->_systemData["sun_radius"], -1.0), 1000.0 + 0.125 * 10000.0));

		// Later in the minute: the sky fades, nothing more recorded but the radius.
		sUniverse->_systemData.clear();
		sun->update(1.0);
		OO_CHECK(sUniverse->_skySets == 2 && sUniverse->_sky[0] == 0.8125f && sUniverse->_sky[3] == 1.0f);
		OO_CHECK(sUniverse->_systemData.count("sun_gone_nova") == 0 && sUniverse->_systemData.count("sun_radius") == 1);
		// Then it goes black.
		sun->update(0.125);
		OO_CHECK(sUniverse->_skySets == 3 && sUniverse->_sky[0] == 0.0f && sUniverse->_sky[3] == 0.0f);

		sun->resetNova();
		OO_CHECK(sun->willGoNova() && sun->goneNova());	// reset keeps the higher temperature
		sun->setGoingNova(NO, 0);
		OO_CHECK(!sun->willGoNova());
	}
}


OO_TEST(description)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		sun->setGoingNova(YES, 10.0);
		const std::string description = oo::EntityDescription(sun);
		OO_CHECK(description.find("radius: 1.000km") != std::string::npos);
		OO_CHECK(description.find("(will go nova)") != std::string::npos);
	}
}


OO_TEST(cameraRelativePosition)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		sun->setPosition(make_HPvector(100, 0, 0));
		sPlayer->_viewpoint = make_HPvector(40, 0, 0);
		sun->updateCameraRelativePosition();
		Vector v = CameraRelativePosition(sun);
		OO_CHECK(v.x == 60.0f && v.y == 0.0f && v.z == 0.0f);

		sun->setPosition(make_HPvector(4e9, 0, 3e9));
		sPlayer->_viewpoint = kZeroHPVector;
		sun->updateCameraRelativePosition();
		v = CameraRelativePosition(sun);
		OO_CHECK(Near(v.x / 1e9, 0.8) && Near(v.z / 1e9, 0.6));
	}
}


OO_TEST(facade)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		// Its Objective-C object is the root's facade since bead oo-9ht.111 (amendment oo-9ht.107).
		Entity *object = sun;
		OO_CHECK(object != nil);	// (and its object's class, the root facade: retired with the facade, bead oo-dpyk8, under oo-9n5p9)
		// A C++ entity (amendment oo-0mxi), not an Objective-C entity's adapter.
		OO_CHECK(dynamic_cast<OOSunEntity *>(object) == sun);
	}
}


// The binding's category, which the facade carries since bead oo-9ht.51: what the engine asks a
// OOSunEntity for by selector is what OOJSSun.mm answers.
OO_TEST(jsExtensions)
{
	{
		SetUp();
		OOSunEntity *sun = RedSun();
		ooscript::ClassDef *jsClass = nullptr, *expectedClass = nullptr;
		ooscript::Object prototype = nullptr, expectedPrototype = nullptr;
		Entity *object = sun;	// what the engine asks (the root's facade since bead oo-9ht.111)
		OOJSEntityGetJSClass(object, &jsClass, &prototype);
		OOJSSunGetJSClass(&expectedClass, &expectedPrototype);
		OO_CHECK(jsClass != nullptr && jsClass == expectedClass && prototype == expectedPrototype);
		OO_CHECK(OOJSEntityJSClassName(object) == std::optional<std::string>("Sun"));
		OO_CHECK(OOJSEntityIsVisibleToScripts(object) == YES);
	}
}


OO_TEST_MAIN()
