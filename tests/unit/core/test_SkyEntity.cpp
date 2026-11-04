/*	test_SkyEntity.mm
        Unit tests for SkyEntity (src/Core/Entities/SkyEntity.h), the star field
   and nebulae behind a system, a leaf of the Entities seam under
   OOEntityWithDrawable.

        The entity reads Universe and PLAYER, so the test links the whole game
   but main (['*']) and uses a Universe that was never initialised (minimum
   detail, so no nebulae), subclassed to count -setLighting, and an entity that
   answers the viewpoint the test sets as PLAYER. Its drawable, OOSkyDrawable,
   loads star textures from the game's resources, which the test has not; the
        test replaces the drawable's star set-up with a stand-in that records
   the two colours the sky passed (through OOSkyDrawable's test seam). The
        expectations were written against the Objective-C API and run on the
   unconverted class first: the sky colour is the system's sun colour, else the
   blend of the two colours; the sky's colours come from "sky_rgb_colors" (six
   numbers) or "sky_color_1"/"sky_color_2" (premultiplied); the star count, the
   drawable, the status and the flags; -update: puts it at the viewpoint with
   the clear depth as its distance; and -changeProperty:withDictionary: takes a
   new sun colour (and relights) and refuses anything else. The distances are
   read through the one helper below. The sky is made as the universe makes it,
   in C++ with its object (the OOEntityWithDrawable facade) made by
   oo::NewEntityFacade: the class's own
   selectors are member calls, the root's are still sent to the object, and the
   last test pins that the object is a C++ entity's. Run: bash
   tools/check-core-tests.sh
*/

#include <cmath>

#include "MyOpenGLView.h"
#include "OOColor.h"
#include "OOSkyDrawable.h"
#include "PlayerEntity.h"
#include "SkyEntity.h"
#include "Universe.h"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;

class TestPlayer : public PlayerEntity {
 public:
  HPVector _viewpoint = {};

  HPVector viewpointPosition() override { return _viewpoint; }
};

// UNIVERSE: never initialised; counts -setLighting.
class TestUniverse : public Universe {
 public:
  int _lightings = {};

  void setLighting() override { _lightings++; }
};

namespace {

TestUniverse* sUniverse = nil;
TestPlayer* sPlayer = nullptr;

// The drawable's star set-up's stand-in: the colours the sky passed.
oo::Ref<OOColor> sStarColor1;
oo::Ref<OOColor> sStarColor2;

void SetUpStars(OOSkyDrawable*, OOColor* color1, OOColor* color2) {
  sStarColor1 = oo::Ref<OOColor>(color1);
  sStarColor2 = oo::Ref<OOColor>(color2);
}

}  // namespace

// The drawable's test seam for its star set-up.
struct OOSkyDrawableTestAccess {
  static void SetStarSetUpStandIn(void (*standIn)(OOSkyDrawable*, OOColor*,
                                                  OOColor*)) {
    OOSkyDrawable::sSetUpStarsStandIn = standIn;
  }
};

// A C++ player under the ship's facade, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1).
template <class T>
T* NewTestPlayer() {
  oo::Ref<T> player = oo::makeRef<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

namespace {

void SetUp() {
  if (sUniverse == nil) {
    sUniverse = new TestUniverse();  // never released
    sPlayer = NewTestPlayer<TestPlayer>();
    OOSkyDrawableTestAccess::SetStarSetUpStandIn(SetUpStars);
  }
  sUniverse->_lightings = 0;
  gSharedUniverse = sUniverse;
  gOOPlayer = sPlayer;
}

// --- Ivars the test reads, and nothing else
// ---------------------------------------------------------

GLfloat ZeroDistance(Entity* e) { return e->zero_distance; }
GLfloat CamZeroDistance(Entity* e) { return e->cam_zero_distance; }

// --------------------------------------------------------------------------------------------------

oo::PList Dict(oo::PList::Dict entries) {
  return oo::PList(std::move(entries));
}

bool Near(double a, double b) { return std::fabs(a - b) < 1e-4; }

bool ColorIs(OOColor* color, float r, float g, float b, float a) {
  if (color == nil) return false;
  float cr = -1, cg = -1, cb = -1, ca = -1;
  color->getRed(&cr, &cg, &cb, &ca);
  return Near(cr, r) && Near(cg, g) && Near(cb, b) && Near(ca, a);
}

// The object first, then the initialiser's body, as the universe makes the sky.
Entity* Sky(const oo::PList& info) {
  const oo::Ref<SkyEntity> sky = oo::makeRef<SkyEntity>();
  Entity* object = oo::MadeEntity(sky);
  sky->initWithColors(OOColor::redColor().get(), OOColor::blueColor().get(),
                      info);
  return object;
}

SkyEntity* SkyPart(Entity* object) { return dynamic_cast<SkyEntity*>(object); }

}  // namespace

OO_TEST(made) {
  {
    SetUp();
    Entity* sky = Sky(Dict({{"sky_n_stars", oo::PList(7)}}));
    OO_CHECK(sky != nil && SkyPart(sky) != nullptr &&
             dynamic_cast<OOEntityWithDrawable*>(sky) != nullptr);
    OO_CHECK(dynamic_cast<OOSkyDrawable*>(SkyPart(sky)->getDrawable()) !=
             nullptr);
    OO_CHECK(sky->status() == STATUS_EFFECT);
    OO_CHECK(sky->isSky() && sky->isVisible() && !sky->canCollide());
    OO_CHECK(sky->cameraRangeFront() == (GLfloat)MAX_CLEAR_DEPTH &&
             sky->cameraRangeBack() == (GLfloat)MAX_CLEAR_DEPTH);
    // No sun colour: the blend of the two.
    OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 0.5f, 0.0f, 0.5f, 1.0f));
    // The stars' colours are the ones given.
    OO_CHECK(ColorIs(sStarColor1.get(), 1, 0, 0, 1) &&
             ColorIs(sStarColor2.get(), 0, 0, 1, 1));
  }
}

OO_TEST(sunColour) {
  {
    SetUp();
    Entity* sky = Sky(Dict({{"sun_color", oo::PList("greenColor")},
                            {"sky_n_stars", oo::PList(0)}}));
    OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 0, 1, 0, 1));
  }
}

OO_TEST(rgbColours) {
  {
    SetUp();
    Sky(Dict({{"sky_rgb_colors", oo::PList("0.25 0.5 2 0 -1 0.75")},
              {"sky_n_stars", oo::PList(0)}}));
    OO_CHECK(ColorIs(sStarColor1.get(), 0.25f, 0.5f, 1.0f, 1.0f));  // clamped
    OO_CHECK(ColorIs(sStarColor2.get(), 0.0f, 0.0f, 0.75f, 1.0f));

    // Not six numbers: the colours given.
    Sky(Dict({{"sky_rgb_colors", oo::PList("0.25 0.5")},
              {"sky_n_stars", oo::PList(0)}}));
    OO_CHECK(ColorIs(sStarColor1.get(), 1, 0, 0, 1) &&
             ColorIs(sStarColor2.get(), 0, 0, 1, 1));
  }
}

OO_TEST(namedColours) {
  {
    SetUp();
    // Premultiplied by alpha.
    Sky(Dict({
        {"sky_color_1", oo::PList(oo::PList::Dict{{"red", oo::PList(1.0)},
                                                  {"green", oo::PList(0.5)},
                                                  {"blue", oo::PList(0.0)},
                                                  {"alpha", oo::PList(0.5)}})},
        {"sky_color_2", oo::PList("whiteColor")},
        {"sky_n_stars", oo::PList(0)},
    }));
    OO_CHECK(ColorIs(sStarColor1.get(), 0.5f, 0.25f, 0.0f, 1.0f));
    OO_CHECK(ColorIs(sStarColor2.get(), 1, 1, 1, 1));
  }
}

OO_TEST(update) {
  {
    SetUp();
    Entity* sky = Sky(Dict({{"sky_n_stars", oo::PList(0)}}));
    sPlayer->_viewpoint = make_HPvector(5, 6, 7);
    sky->update(0.1);
    OO_CHECK(HPvector_equal(sky->getPosition(), make_HPvector(5, 6, 7)));
    OO_CHECK(ZeroDistance(sky) == (GLfloat)(MAX_CLEAR_DEPTH * MAX_CLEAR_DEPTH));
    OO_CHECK(CamZeroDistance(sky) == ZeroDistance(sky));

    // No player: the position stays. Only a release-style build can ask with
    // none: the debug build asserts that PLAYER is set (OOGetPlayer()).
#if !OO_DEBUG
    gOOPlayer = nullptr;
    sPlayer->_viewpoint = make_HPvector(8, 8, 8);
    sky->update(0.1);
    OO_CHECK(HPvector_equal(sky->getPosition(), make_HPvector(5, 6, 7)));
    gOOPlayer = sPlayer;
#endif
  }
}

OO_TEST(changeProperty) {
  {
    SetUp();
    Entity* sky = Sky(Dict({{"sky_n_stars", oo::PList(0)}}));
    OO_CHECK(SkyPart(sky)->changeProperty(
        "sun_color", Dict({{"sun_color", oo::PList("yellowColor")}})));
    OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 1, 1, 0, 1));
    OO_CHECK(sUniverse->_lightings == 1);

    // Not a colour: kept, no relighting, but answered YES.
    OO_CHECK(SkyPart(sky)->changeProperty("sun_color", Dict({})));
    OO_CHECK(ColorIs(SkyPart(sky)->getSkyColor(), 1, 1, 0, 1));
    OO_CHECK(sUniverse->_lightings == 1);

    OO_CHECK(!SkyPart(sky)->changeProperty(
        "sky_n_stars", Dict({{"sky_n_stars", oo::PList(3)}})));
  }
}

OO_TEST(facade) {
  {
    SetUp();
    Entity* sky = Sky(Dict({{"sky_n_stars", oo::PList(0)}}));
    // A C++ entity, not an Objective-C entity's adapter.
    OO_CHECK(dynamic_cast<SkyEntity*>(sky) != nullptr);
    OO_CHECK(sky == sky);
  }
}

OO_TEST_MAIN()
