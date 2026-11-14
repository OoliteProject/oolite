/*	test_OOFlasherEntity.mm
	Unit tests for OOFlasherEntity (src/Core/Entities/OOFlasherEntity.h), the blinking lights that
	ships and visual effects carry as subentities.

	The entity reads Universe and PLAYER, so the test links the whole game but main (['*']) and
	uses a Universe that was never initialised and a plain entity as PLAYER. The tests cover: a
	flasher reads its size, frequency (doubled), phase, bright fraction, colours and initial state
	from its dictionary (defaults 1, 1, 0, 0.5, none, on); its accessors; its colour is its current
	components; -update: cycles its colours on the wave's falling half and sets its brightness, or
	keeps it opaque at frequency 0; it draws only while active; it is a flasher (and an entity is
	not); its collision radius is half its diameter; -rescaleBy: scales the diameter and
	-rescaleBy:writeToCache: does nothing. The colour components, an ivar of OOLightParticleEntity,
	are read and set through the one block of helpers below. The flashers are made as the callers
	make them (flasherWithDictionary()). The cases ask the C++ class; the
	facade case pins the crossing (the object is OOLightParticleEntity's, whose C++ part is
	the flasher), and jsExtensions pins that the engine's selectors reach the C++ class's overrides
	through the root.
	Run: tests/run.sh unit
*/

#include "OOFlasherEntity.h"
#include "PlayerEntity.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOJSEntity.h"
#include "OOJSFlasher.h"
#include "OOColor.h"
#include "Universe.h"

#include "oo_test.hpp"

#include <cmath>


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
	HPVector viewpointPosition() override	{ return kZeroHPVector; }
};

// A C++ player under the ship's facade, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}


// UNIVERSE: never initialised.
class TestUniverse : public Universe
{
public:

};


namespace {

void SetUp()
{
	static Universe *universe = nullptr;
	if (universe == nullptr)
	{
		universe = new TestUniverse();	// never released
	}
	gSharedUniverse = universe;
	static TestPlayer *player = nullptr;
	if (player == nullptr)  player = NewTestPlayer<TestPlayer>();
	gOOPlayer = player;
}


// --- Ivars the test reads and sets, and nothing else -----------------------------------------------

const GLfloat *ColorComponents(OOFlasherEntity *e)			{ return e->_colorComponents; }
GLfloat CamZeroDistance(Entity *e)					{ return e->cam_zero_distance; }
void SetCamZeroDistance(Entity *e, GLfloat value)	{ e->cam_zero_distance = value; }

// --------------------------------------------------------------------------------------------------


// A flasher, made as the ships and the visual effects make one: its Objective-C object is
// autoreleased in the test's pool and holds it.
OOFlasherEntity *Flasher(const oo::PList &dictionary)
{
	return static_cast<OOFlasherEntity *>(oo::MadeEntity(OOFlasherEntity::flasherWithDictionary(dictionary)));
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-4;
}


bool RGBIs(OOFlasherEntity *e, GLfloat r, GLfloat g, GLfloat b)
{
	const GLfloat *c = ColorComponents(e);
	return Near(c[0], r) && Near(c[1], g) && Near(c[2], b);
}


oo::PList Dict(oo::PList::Dict entries)
{
	return oo::PList(std::move(entries));
}


oo::PList WhiteBlack(float frequency, float fraction)
{
	return Dict({
		{ "size", oo::PList(4.0) },
		{ "frequency", oo::PList(double(frequency)) },
		{ "bright_fraction", oo::PList(double(fraction)) },
		{ "colors", oo::PList(oo::PList::Array{ oo::PList(std::string("whiteColor")), oo::PList(std::string("blackColor")) }) },
	});
}

}	// namespace


OO_TEST(defaults)
{
	{
		SetUp();
		OOFlasherEntity *flasher = Flasher(Dict({}));
		OO_CHECK(flasher != nullptr);
		OO_CHECK(dynamic_cast<OOLightParticleEntity *>(flasher) != nullptr);
		OO_CHECK(flasher->diameter() == 1.0f);
		OO_CHECK(flasher->frequency() == 2.0f && flasher->phase() == 0.0f && flasher->fraction() == 0.5f);
		OO_CHECK(flasher->isActive());
		OO_CHECK(flasher->status() == STATUS_EFFECT && flasher->getScanClass() == CLASS_NO_DRAW);
		// No colours: the current colour is nil, which left the components white.
		OO_CHECK(RGBIs(flasher, 1, 1, 1) && ColorComponents(flasher)[3] == 1.0f);
		OO_CHECK(flasher->isFlasher());
		OO_CHECK(flasher->findCollisionRadius() == 0.5);
	}
}


OO_TEST(dictionary)
{
	{
		SetUp();
		OOFlasherEntity *flasher = Flasher(Dict({
			{ "size", oo::PList(6.0) },
			{ "frequency", oo::PList(1.5) },
			{ "phase", oo::PList(0.25) },
			{ "bright_fraction", oo::PList(0.75) },
			{ "initially_on", oo::PList(false) },
			{ "colors", oo::PList(oo::PList::Array{ oo::PList(std::string("blackColor")), oo::PList(std::string("whiteColor")) }) },
		}));
		OO_CHECK(flasher->diameter() == 6.0f && flasher->findCollisionRadius() == 3.0);
		OO_CHECK(flasher->frequency() == 3.0f && flasher->phase() == 0.25f && flasher->fraction() == 0.75f);
		OO_CHECK(!flasher->isActive());
		OO_CHECK(RGBIs(flasher, 0, 0, 0) && ColorComponents(flasher)[3] == 1.0f);	// the first colour

		oo::Ref<OOColor> color = flasher->color();
		float r = -1, g = -1, b = -1, a = -1;
		color->getRed(&r, &g, &b, &a);
		OO_CHECK(r == 0 && g == 0 && b == 0 && a == 1);
	}
}


OO_TEST(saturationFactor)
{
	{
		SetUp();
		OOFlasherEntity *flasher = Flasher(Dict({
			{ "colors", oo::PList(oo::PList::Array{ oo::PList(std::string("redColor")) }) },
		}));
		// Red at three quarters of its saturation.
		OO_CHECK(RGBIs(flasher, 1.0f, 0.25f, 0.25f));
	}
}


OO_TEST(accessors)
{
	{
		SetUp();
		OOFlasherEntity *flasher = Flasher(WhiteBlack(1, 0.5));
		flasher->setActive(false);
		OO_CHECK(!flasher->isActive());
		flasher->setActive(true);
		OO_CHECK(flasher->isActive());
		flasher->setFrequency(7.0f);
		OO_CHECK(flasher->frequency() == 7.0f);
		flasher->setPhase(0.5f);
		OO_CHECK(flasher->phase() == 0.5f);
		flasher->setFraction(0.125f);
		OO_CHECK(flasher->fraction() == 0.125f);
		flasher->setColor(OOColor::colorWithRed(0.5f, 0.25f, 0.125f, 0.75f).get(), 0.375f);
		float r = -1, g = -1, b = -1, a = -1;
		flasher->color()->getRed(&r, &g, &b, &a);
		OO_CHECK(r == 0.5f && g == 0.25f && b == 0.125f && a == 0.375f);
	}
}


OO_TEST(updateCyclesColours)
{
	{
		SetUp();
		// frequency 1 (stored 2): wave = sin(2 pi t), fraction 0.5: threshold cos(pi / 2) = 0.
		OOFlasherEntity *flasher = Flasher(WhiteBlack(1, 0.5));
		OO_CHECK(RGBIs(flasher, 1, 1, 1));

		flasher->update(0.125);		// t 0.125: wave sin(pi/4), rising half: brightness above the fraction
		double wave = std::sin(M_PI / 4);
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
		OO_CHECK(Near(ColorComponents(flasher)[3], 0.5 + (0.5 / 1.0) * wave));

		flasher->update(0.5);		// t 0.625: wave -sin(pi/4), falling: no switch (wave < _wave)
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
		OO_CHECK(Near(ColorComponents(flasher)[3], 0.5 + (0.5 / 1.0) * -wave));

		flasher->update(0.3125);	// t 0.9375: wave still negative and rising: the next colour
		OO_CHECK(RGBIs(flasher, 0, 0, 0));

		flasher->update(0.03125);	// t 0.96875: just switched, no second switch
		OO_CHECK(RGBIs(flasher, 0, 0, 0));

		flasher->update(0.0625);	// t 1.03125: positive again, the switch resets
		flasher->update(0.59375);	// t 1.625: negative but falling: no switch
		OO_CHECK(RGBIs(flasher, 0, 0, 0));
		flasher->update(0.3125);	// t 1.9375: rising below zero: back to the first colour
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
	}
}


OO_TEST(frequencyZeroIsOpaque)
{
	{
		SetUp();
		OOFlasherEntity *flasher = Flasher(WhiteBlack(0, 0.5));
		flasher->setColor(OOColor::whiteColor().get(), 0.25f);
		flasher->update(0.3);
		OO_CHECK(ColorComponents(flasher)[3] == 1.0f);
		OO_CHECK(RGBIs(flasher, 1, 1, 1));
	}
}


OO_TEST(drawsOnlyWhileActive)
{
	{
		SetUp();
		Entity *owner = oo::MadeEntity(oo::makeRef<Entity>());
		SetCamZeroDistance(owner, 1e30f);		// beyond any draw distance: the draw stops at the cut-off
		OOFlasherEntity *flasher = Flasher(WhiteBlack(1, 0.5));
		flasher->setOwner(owner);
		SetCamZeroDistance(flasher, 5.0f);

		flasher->setActive(false);
		flasher->drawSubEntityImmediate(true, true);
		OO_CHECK(CamZeroDistance(flasher) == 5.0f);	// not drawn

		flasher->setActive(true);
		flasher->drawSubEntityImmediate(true, true);
		OO_CHECK(CamZeroDistance(flasher) == 1e30f);	// OOLightParticleEntity's draw read the owner's distance
	}
}


OO_TEST(rescale)
{
	{
		SetUp();
		OOFlasherEntity *flasher = Flasher(WhiteBlack(1, 0.5));
		flasher->rescaleBy(2.5f);
		OO_CHECK(flasher->diameter() == 10.0f);
		flasher->rescaleBy(3.0f, true);
		OO_CHECK(flasher->diameter() == 10.0f);
	}
}


OO_TEST(isFlasher)
{
	{
		SetUp();
		// Callers ask the C++ part.
		Entity *plain = oo::MadeEntity(oo::makeRef<Entity>());
		OO_CHECK(dynamic_cast<OOFlasherEntity *>(plain) == nullptr);
		const oo::Ref<OOLightParticleEntity> lightParticle = oo::makeRef<OOLightParticleEntity>();
		Entity *particle = oo::MadeEntity(lightParticle);
		lightParticle->initWithDiameter(1.0f);
		OO_CHECK(dynamic_cast<OOFlasherEntity *>(particle) == nullptr);
		OOFlasherEntity *flasher = Flasher(Dict({}));
		OO_CHECK(flasher->isFlasher() && dynamic_cast<OOFlasherEntity *>(flasher) == flasher);
	}
}


OO_TEST(facade)
{
	{
		SetUp();
		// The object is the root's facade, whose C++ part is the flasher: a C++
    // entity.
		Entity *object = oo::MadeEntity(OOFlasherEntity::flasherWithDictionary(WhiteBlack(1, 0.5)));
		OO_CHECK(dynamic_cast<OOFlasherEntity *>(object) != nullptr);
		OO_CHECK(object == object);
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


// The C++ class's overrides of the root's JS members: what the engine asks a
// flasher's object for by selector is what OOJSFlasher.mm answers.
OO_TEST(jsExtensions)
{
	{
		SetUp();
		Entity *flasher = Flasher(WhiteBlack(1, 0.5));
		RegisterJSClasses(InitOOJSFlasher);
		const JSClassID jsClass = OOJSEntityJSClassID(flasher);
		const JSClassID expectedClass = JSFlasherClassID();
		OO_CHECK(jsClass != 0 && jsClass == expectedClass);
		OO_CHECK(OOJSEntityJSClassName(flasher) == std::optional<std::string>("Flasher"));
		OO_CHECK(OOJSEntityIsVisibleToScripts(flasher) == true);
	}
}


OO_TEST_MAIN()
