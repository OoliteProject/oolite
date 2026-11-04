/*	test_Universe.mm
        Unit tests for Universe (src/Core/Universe.h), the game's world.

        -initWithGameView: needs the whole game (a window, the resources, the
   player), so the test links the whole game but main
   (tests/unit/core/meson.build entry ['*']) and
   uses Universes that were never initialised, as the entity tests do: zeroed,
   as the runtime zeroed the ivars. The drawing is pinned by the goldens, not
   here. The expectations were written against the Objective-C API and run on
   the unconverted class first: the state a universe starts with, the settings
   and flags a headless universe can answer and their clamping, the post-FX and
        colour-blind modes, and the public members other classes read directly
   (the entity list, the collision lists, the cursor row, the ambient star
   light), which go through the small block of helpers below, the one place that
   knows where they live. The universe is one C++ object (new Universe(), never
   released) and the cases call its members; facadeAndPart pins the accessors
   over the members and a new universe's zeroes. Run: bash
   tools/check-core-tests.sh
*/

#include "PlayerEntity.h"
#include "Universe.h"
#include "oofnd/objc/OOException.h"  // -handleOoliteException:

extern PlayerEntity* gOOPlayer;  // the early cases run before the later ones
                                 // stand-in player is installed

#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern Universe* gSharedUniverse;
extern PlayerEntity* gOOPlayer;

namespace {

// A Universe that was never initialised, made UNIVERSE (-setAmbientLightLevel:
// asserts there is one).
Universe* NewUniverse() {
  Universe* universe = new Universe();  // never released
  gSharedUniverse = universe;
  return universe;
}

// The members other classes read directly.
unsigned EntityListCount(Universe* u) { return u->n_entities; }
Entity* SortedEntity(Universe* u, unsigned i) { return u->sortedEntities[i]; }
int CursorRow(Universe* u) { return u->cursor_row; }
GLfloat StarsAmbient(Universe* u, int i) { return u->stars_ambient[i]; }
bool ListHeadsEmpty(Universe* u) {
  return u->x_list_start == nil && u->y_list_start == nil &&
         u->z_list_start == nil;
}

}  // namespace

OO_TEST(defaults) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    OO_CHECK(u->sessionID() == 0);
    OO_CHECK(!u->doingStartUp());
    OO_CHECK(u->entityCount() == 0);
    OO_CHECK(u->getTime() == 0.0 && u->getTimeDelta() == 0.0);
    OO_CHECK(u->currentSystemID() == 0);
    OO_CHECK(u->getViewDirection() == VIEW_FORWARD);
    OO_CHECK(u->getAmbientLightLevel() == 0.0f);
    OO_CHECK(u->getAirResistanceFactor() == 0.0f);
    GLfloat* sky = u->getSkyClearColor();
    OO_CHECK(sky[0] == 0.0f && sky[1] == 0.0f && sky[2] == 0.0f &&
             sky[3] == 0.0f);

    OO_CHECK(u->getDetailLevel() == DETAIL_LEVEL_MINIMUM);
    OO_CHECK(u->reducedDetail() && !u->useShaders());
    OO_CHECK(!u->bloom());
    OO_CHECK(u->currentPostFX() == OO_POSTFX_NONE &&
             u->colorblindMode() == OO_POSTFX_NONE);

    OO_CHECK(!u->getDisplayGUI() && !u->getDisplayFPS());
    OO_CHECK(!u->getAutoSave() && !u->getAutoSaveNow() &&
             !u->getWireframeGraphics());
    OO_CHECK(!u->getDoProcedurallyTexturedPlanets());
    OO_CHECK(!u->getECMVisualFXEnabled());
    OO_CHECK(u->getFramesDoneThisUpdate() == 0);
    OO_CHECK(!u->pauseMessageVisible());
    OO_CHECK(!u->permanentCommLog() && !u->permanentMessageLog() &&
             !u->autoMessageLogBg());
    OO_CHECK(!u->witchspaceBreakPattern() &&
             !u->dockingClearanceProtocolActive());
    OO_CHECK(u->breakPatternOver());
#ifndef NDEBUG
    OO_CHECK(u->getTimeAccelerationFactor() ==
             0.0);  // the zeroed ivar; -initWithGameView: never set it
#else
    OO_CHECK(u->getTimeAccelerationFactor() == 1.0);
#endif
  }
}

OO_TEST(publicMembers) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    OO_CHECK(EntityListCount(u) == 0);
    OO_CHECK(SortedEntity(u, 0) == nil &&
             SortedEntity(u, UNIVERSE_MAX_ENTITIES) == nil);
    OO_CHECK(ListHeadsEmpty(u));
    OO_CHECK(CursorRow(u) == 0);
    OO_CHECK(StarsAmbient(u, 0) == 0.0f && StarsAmbient(u, 3) == 0.0f);
  }
}

OO_TEST(lightAndAir) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    u->setAmbientLightLevel(3.5f);
    OO_CHECK(u->getAmbientLightLevel() == 3.5f);
    u->setAmbientLightLevel(12.0f);
    OO_CHECK(u->getAmbientLightLevel() == 10.0f);  // clamped to 0 ... 10
    u->setAmbientLightLevel(-1.0f);
    OO_CHECK(u->getAmbientLightLevel() == 0.0f);

    u->setAirResistanceFactor(0.25f);
    OO_CHECK(u->getAirResistanceFactor() == 0.25f);
    u->setAirResistanceFactor(2.0f);
    OO_CHECK(u->getAirResistanceFactor() == 1.0f);  // clamped to 0 ... 1
    u->setAirResistanceFactor(-1.0f);
    OO_CHECK(u->getAirResistanceFactor() == 0.0f);

    // The sky colour's alpha is also the air resistance, clamped there but not
    // in the colour.
    u->setSkyColorRed(0.1f, 0.2f, 0.3f, 0.5f);
    GLfloat* sky = u->getSkyClearColor();
    OO_CHECK(sky[0] == 0.1f && sky[1] == 0.2f && sky[2] == 0.3f &&
             sky[3] == 0.5f);
    OO_CHECK(u->getAirResistanceFactor() == 0.5f);
    u->setSkyColorRed(0.0f, 0.0f, 0.0f, 3.0f);
    OO_CHECK(sky[3] == 3.0f && u->getAirResistanceFactor() == 1.0f);
    OO_CHECK(sky == u->getSkyClearColor());  // the live array
  }
}

OO_TEST(postFX) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    u->setCurrentPostFX(OO_POSTFX_COLORBLINDNESS_DEUTER);
    OO_CHECK(u->currentPostFX() == OO_POSTFX_COLORBLINDNESS_DEUTER &&
             u->colorblindMode() == OO_POSTFX_COLORBLINDNESS_DEUTER);

    // A non-colour-blind effect leaves the colour-blind mode, which ending the
    // effect restores.
    u->setCurrentPostFX(OO_POSTFX_CLOAK);
    OO_CHECK(u->currentPostFX() == OO_POSTFX_CLOAK &&
             u->colorblindMode() == OO_POSTFX_COLORBLINDNESS_DEUTER);
    u->terminatePostFX(OO_POSTFX_GRAYSCALE);  // not the current one: nothing
    OO_CHECK(u->currentPostFX() == OO_POSTFX_CLOAK);
    u->terminatePostFX(OO_POSTFX_CLOAK);
    OO_CHECK(u->currentPostFX() == OO_POSTFX_COLORBLINDNESS_DEUTER);

    // Out of range (and 0) is none, which is also the colour-blind mode none.
    u->setCurrentPostFX(OO_POSTFX_ENDOFLIST);
    OO_CHECK(u->currentPostFX() == OO_POSTFX_NONE &&
             u->colorblindMode() == OO_POSTFX_NONE);
    u->setCurrentPostFX(OO_POSTFX_CRT);
    u->setCurrentPostFX(-3);
    OO_CHECK(u->currentPostFX() == OO_POSTFX_NONE &&
             u->colorblindMode() == OO_POSTFX_NONE);

    // The colour-blind modes cycle through none, protan, deuter, tritan.
    OO_CHECK(u->nextColorblindMode(OO_POSTFX_NONE) ==
             OO_POSTFX_COLORBLINDNESS_PROTAN);
    OO_CHECK(u->nextColorblindMode(OO_POSTFX_COLORBLINDNESS_TRITAN) ==
             OO_POSTFX_NONE);
    OO_CHECK(u->prevColorblindMode(OO_POSTFX_NONE) ==
             OO_POSTFX_COLORBLINDNESS_TRITAN);
    OO_CHECK(u->prevColorblindMode(OO_POSTFX_COLORBLINDNESS_DEUTER) ==
             OO_POSTFX_COLORBLINDNESS_PROTAN);

    // Bloom needs the extras detail level; a universe never initialised is at
    // the minimum.
    u->setBloom(YES);
    OO_CHECK(!u->bloom());
  }
}

OO_TEST(flags) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    u->setDisplayFPS(7);
    OO_CHECK(u->getDisplayFPS() == YES);  // normalised
    u->setAutoSaveNow(YES);
    OO_CHECK(u->getAutoSaveNow());
    u->setPauseMessageVisible(YES);
    OO_CHECK(u->pauseMessageVisible());
    u->setPermanentMessageLog(YES);
    u->setAutoMessageLogBg(2);
    u->setPermanentCommLog(YES);
    OO_CHECK(u->permanentMessageLog() && u->autoMessageLogBg() == YES &&
             u->permanentCommLog());
    u->setWitchspaceBreakPattern(2);
    OO_CHECK(u->witchspaceBreakPattern() == YES);
    u->setECMVisualFXEnabled(YES);
    OO_CHECK(u->getECMVisualFXEnabled());
    u->resetFramesDoneThisUpdate();
    OO_CHECK(u->getFramesDoneThisUpdate() == 0);

#ifndef NDEBUG
    u->setTimeAccelerationFactor(2.0);
    OO_CHECK(u->getTimeAccelerationFactor() == 2.0);
    u->setTimeAccelerationFactor(TIME_ACCELERATION_FACTOR_MAX * 2);
    OO_CHECK(u->getTimeAccelerationFactor() ==
             TIME_ACCELERATION_FACTOR_DEFAULT);
    u->setTimeAccelerationFactor(TIME_ACCELERATION_FACTOR_MIN / 2);
    OO_CHECK(u->getTimeAccelerationFactor() ==
             TIME_ACCELERATION_FACTOR_DEFAULT);
#endif

    // Each universe has its own state.
    Universe* other = NewUniverse();
    OO_CHECK(!other->getDisplayFPS() && !other->pauseMessageVisible() &&
             u->getDisplayFPS());
  }
}

// The universe is one C++ object, whose accessors answer its members and which
// starts zeroed.
OO_TEST(facadeAndPart) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    // The accessors answer the part's members, and the setters set them.
    u->setAmbientLightLevel(2.5f);
    OO_CHECK(part->ambientLightLevel == 2.5f);
    part->universal_time = 42.0;
    part->_sessionID = 3;
    OO_CHECK(u->getTime() == 42.0 && u->sessionID() == 3);
    u->setCurrentPostFX(OO_POSTFX_COLORBLINDNESS_TRITAN);
    OO_CHECK(part->_currentPostFX == OO_POSTFX_COLORBLINDNESS_TRITAN &&
             part->_colorblindMode == OO_POSTFX_COLORBLINDNESS_TRITAN);

    // A new universe is zeroed, as the runtime zeroed the ivars.
    Universe* fresh =
        new Universe();  // never released: its teardown is the facade's
                         // -dealloc, which clears UNIVERSE
    OO_CHECK(fresh->n_entities == 0 && fresh->x_list_start == nil &&
             fresh->gameView == nil);
    OO_CHECK(fresh->sortedEntities[UNIVERSE_MAX_ENTITIES] == nil &&
             fresh->frustum[5][3] == 0.0f);
    OO_CHECK(fresh->entities.empty() && fresh->demo_ships.isNull() &&
             !fresh->currentMessage.has_value());
    OO_CHECK(gSharedUniverse == u);
  }
}

// The units a universe that was never initialised can answer,
// written against the Objective-C API and run on the unconverted class first.
// Pausing, quitting and the set-up from a station or witchspace need
// the player, the GUI and the game controller, and is pinned by the goldens.

OO_TEST(slice2StartUpFlagsAddOnsAndEntityList) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    part->_doingStartUp = YES;
    part->_sessionID = 7;
    OO_CHECK(u->doingStartUp() && u->sessionID() == 7);

    // The add-ons in use: a universe never initialised has the empty string,
    // not none.
    std::optional<std::string> addOns = u->getUseAddOns();
    OO_CHECK(addOns.has_value() && addOns->empty());
    part->useAddOns = "strict";
    OO_CHECK(u->getUseAddOns() == std::optional<std::string>("strict"));
    // The same add-ons without forcing: nothing to reinitialise, YES.
    OO_CHECK(u->setUseAddOns("strict", YES));
    OO_CHECK(u->setUseAddOns("strict", NO, NO));
    OO_CHECK(part->useAddOns == "strict");

    OO_CHECK(u->entityCount() == 0 && u->entityList().empty());

    // The colour-blind modes step through the four in both directions, and
    // wrap.
    int mode = OO_POSTFX_NONE;
    for (int i = 0; i < 4; i++) mode = u->nextColorblindMode(mode);
    OO_CHECK(mode == OO_POSTFX_NONE);
    for (int i = 0; i < 4; i++) mode = u->prevColorblindMode(mode);
    OO_CHECK(mode == OO_POSTFX_NONE);
    OO_CHECK(u->nextColorblindMode(OO_POSTFX_COLORBLINDNESS_PROTAN) ==
             OO_POSTFX_COLORBLINDNESS_DEUTER);

    // Bloom is the flag at the extras detail level only.
    u->setBloom(YES);
    OO_CHECK(part->_bloom == YES && !u->bloom());
  }
}

OO_TEST(slice4PopulatorSettings) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    OO_CHECK(u->getPopulatorSettings().isNull());  // none until cleared or set
    OO_CHECK(!u->deterministicPopulation());
    part->deterministic_population = YES;
    OO_CHECK(u->deterministicPopulation());

    u->setPopulatorSetting("pirates", oo::PList(std::string("some")));
    oo::PList settings = u->getPopulatorSettings();
    OO_CHECK(settings.isDict() &&
             settings.getIf<oo::PList::Dict>()->size() == 1);
    OO_CHECK(settings.find("pirates") != nullptr &&
             settings.get<std::string>("pirates") == "some");

    // A null setting removes the key.
    u->setPopulatorSetting("traders", oo::PList(std::string("more")));
    u->setPopulatorSetting("pirates", oo::PList());
    settings = u->getPopulatorSettings();
    OO_CHECK(settings.getIf<oo::PList::Dict>()->size() == 1 &&
             settings.find("pirates") == nullptr &&
             settings.find("traders") != nullptr);

    u->clearSystemPopulator();
    settings = u->getPopulatorSettings();
    OO_CHECK(settings.isDict() && settings.getIf<oo::PList::Dict>()->empty());
  }
}

OO_TEST(slice5MainLightPosition) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    u->setMainLightPosition(make_vector(1.0f, -2.0f, 3.5f));
    OO_CHECK(part->main_light_position[0] == 1.0f &&
             part->main_light_position[1] == -2.0f);
    OO_CHECK(part->main_light_position[2] == 3.5f &&
             part->main_light_position[3] == 1.0f);

    u->setAmbientLightLevel(4.0f);
    OO_CHECK(u->getAmbientLightLevel() == 4.0f &&
             part->ambientLightLevel == 4.0f);
  }
}

OO_TEST(slice6CoordinateSystemStrings) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    // Anything but four tokens is the origin, not an error.
    HPVector v = u->coordinatesFromCoordinateSystemString("wpu 1 2");
    OO_CHECK(v.x == 0.0 && v.y == 0.0 && v.z == 0.0);
    v = u->coordinatesFromCoordinateSystemString("");
    OO_CHECK(v.x == 0.0 && v.y == 0.0 && v.z == 0.0);
    v = u->coordinatesFromCoordinateSystemString("wpu 1 2 3 4");
    OO_CHECK(v.x == 0.0 && v.y == 0.0 && v.z == 0.0);
  }
}

OO_TEST(slice7RoleCategoriesAndFlags) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    OO_CHECK(!u->roleIsPirateVictim("trader"));  // no categories loaded
    part->roleCategories = oo::PList(oo::PList::Dict{
        {"oolite-pirate-victim",
         oo::PList(oo::PList::Array{oo::PList(std::string("trader")),
                                    oo::PList(std::string("courier"))})},
        {"oolite-hunters",
         oo::PList(oo::PList::Array{oo::PList(std::string("hunter"))})},
    });
    OO_CHECK(u->roleIsPirateVictim("trader") &&
             u->roleIsPirateVictim("courier"));
    OO_CHECK(!u->roleIsPirateVictim("hunter") && !u->roleIsPirateVictim(""));
    OO_CHECK(u->role("hunter", "oolite-hunters"));
    OO_CHECK(!u->role("hunter", "oolite-nothing"));

    // No witchpoint buoy among no entities: the minimum.
    OO_CHECK(u->safeWitchspaceExitDistance() == MIN_DISTANCE_TO_BUOY);

    part->_dockingClearanceProtocolActive = YES;
    OO_CHECK(u->dockingClearanceProtocolActive());
    u->setWitchspaceBreakPattern(NO);
    OO_CHECK(!u->witchspaceBreakPattern());
  }
}

OO_TEST(slice8StationsAndPlanets) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    // No sun: no main station is looked for; no planets, no stations.
    OO_CHECK(u->station() == nil && u->planet() == nil);
    OO_CHECK(u->planets().empty() && u->stations().empty());
    OO_CHECK(u->stationWithRole("", make_HPvector(0, 0, 0)) == nil);
    OO_CHECK(u->stationWithRole("coriolis", make_HPvector(0, 0, 0)) == nil);
  }
}

OO_TEST(slice9BeaconsWaypointsBreakPatternAndAIs) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    OO_CHECK(u->firstBeacon() == nil && u->lastBeacon() == nil);
    u->resetBeacons();
    OO_CHECK(u->firstBeacon() == nil && u->lastBeacon() == nil);
    OO_CHECK(u->wormholes().empty() && u->currentWaypoints().empty());

    part->breakPatternCounter = 3;
    OO_CHECK(!u->breakPatternOver());
#if !OO_DEBUG  // the debug build asserts that PLAYER is set (OOGetPlayer()), so
               // only a release-style build can ask with none
    PlayerEntity* standIn = gOOPlayer;
    gOOPlayer = nullptr;  // no player: an earlier case leaves its stand-in
                          // (SetUpTestPlayer())
    OO_CHECK(u->breakPatternHide());  // no player
    gOOPlayer = standIn;
#endif
    part->breakPatternCounter = 0;
    OO_CHECK(u->breakPatternOver());

    OO_CHECK(!u->defaultAIForRole("pirate").has_value());
    part->autoAIMap = oo::PList(
        oo::PList::Dict{{"pirate", oo::PList(std::string("pirateAI.plist"))}});
    OO_CHECK(u->defaultAIForRole("pirate") ==
             std::optional<std::string>("pirateAI.plist"));
    OO_CHECK(!u->defaultAIForRole("trader").has_value());

    u->setSkyColorRed(0.5f, 0.25f, 0.125f, 0.75f);
    OO_CHECK(part->skyClearColor[0] == 0.5f &&
             part->skyClearColor[3] == 0.75f &&
             u->getAirResistanceFactor() == 0.75f);
  }
}

OO_TEST(slice10GameViewAndCommodities) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    OO_CHECK(u->getGameView() == nil && u->gameController() == nil);
    u->setGameView(nullptr);
    OO_CHECK(u->getGameView() == nil);
    OO_CHECK(u->getCommodities() == nil);
  }
}

OO_TEST(slice11ViewFrustum) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    // A zeroed frustum: every plane's distance is 0, which a sphere of radius r
    // > 0 is not behind.
    OO_CHECK(
        u->viewFrustumIntersectsSphereAt(make_vector(1.0f, 2.0f, 3.0f), 1.0f));
    OO_CHECK(
        !u->viewFrustumIntersectsSphereAt(make_vector(1.0f, 2.0f, 3.0f), 0.0f));

    // One plane, x >= 0 (the others pass everything): a sphere is outside only
    // when wholly behind it.
    for (int p = 0; p < 6; p++) {
      part->frustum[p][0] = part->frustum[p][1] = part->frustum[p][2] = 0.0f;
      part->frustum[p][3] = 1000.0f;
    }
    part->frustum[2][0] = 1.0f;
    part->frustum[2][3] = 0.0f;
    OO_CHECK(
        u->viewFrustumIntersectsSphereAt(make_vector(5.0f, 0.0f, 0.0f), 1.0f));
    OO_CHECK(
        u->viewFrustumIntersectsSphereAt(make_vector(-0.5f, 0.0f, 0.0f), 1.0f));
    OO_CHECK(!u->viewFrustumIntersectsSphereAt(make_vector(-5.0f, 0.0f, 0.0f),
                                               1.0f));
  }
}

OO_TEST(slice12FrameCounterAndViewMatrix) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Universe* part = u;

    part->framesDoneThisUpdate = 4;
    OO_CHECK(u->getFramesDoneThisUpdate() == 4);
    u->resetFramesDoneThisUpdate();
    OO_CHECK(u->getFramesDoneThisUpdate() == 0 &&
             part->framesDoneThisUpdate == 0);

    part->viewMatrix = kIdentityMatrix;
    OO_CHECK(OOMatrixEqual(u->getViewMatrix(), kIdentityMatrix));
  }
}

namespace {
void SetUpTestPlayer();
}  // namespace

OO_TEST(slice13EntityLookUp) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    SetUpTestPlayer();  // PLAYER, which the debug build asserts is set; id 100
                        // answers it

    // No target, an empty slot and out of range are nil; 100 is the player's.
    OO_CHECK(u->entityForUniversalID(NO_TARGET) == nil);
    OO_CHECK(u->entityForUniversalID(MIN_ENTITY_UID + 1) == nil);
    OO_CHECK(u->entityForUniversalID(MAX_ENTITY_UID + 1) == nil);
    OO_CHECK(u->entityForUniversalID(100) == PLAYER);

    // No demo ships among no entities: the demo ship is cleared.
    u->removeDemoShips();
    OO_CHECK(u->demo_ship == nil && u->entityCount() == 0);
  }
}

// Demo ships, safe vectors, hazards on route, laser
// hits. Written against the Objective-C API and run on the unconverted class
// first. The entities sit in the universe's sorted list by hand (no
// -addEntity:, which needs the whole game).

// PLAYER: a stand-in (OOGetPlayer() asserts there is a player, and an entity's
// position is kept relative to the player's viewpoint, as test_Entity's
// TestPlayer). It answers the player messages the tests reach as an absent
// player's nil did.
class UniverseTestPlayer : public PlayerEntity {
 public:
  HPVector viewpointPosition() override { return kZeroHPVector; }
  ::StationEntity* dockedStation() override { return nil; }
};

// A C++ player under the ship's facade, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1).
template <class T>
T* NewTestPlayer() {
  oo::Ref<T> player = oo::makeRef<T>();
  {
    oo::AutoreleaseScope scope;
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

namespace {

void SetUpTestPlayer() {
  static UniverseTestPlayer* player = nullptr;
  if (player == nullptr)
    player = NewTestPlayer<UniverseTestPlayer>();  // never released, as the
                                                   // player is not
  gOOPlayer = player;
}

void SetSortedEntities(Universe* u, std::initializer_list<Entity*> list) {
  unsigned n = 0;
  for (Entity* e : list) u->sortedEntities[n++] = e;
  u->sortedEntities[n] = nil;
  u->n_entities = n;
}

Entity* MakeEntity(HPVector position, GLfloat radius) {
  SetUpTestPlayer();
  Entity* entity = oo::MadeEntity(oo::makeRef<Entity>());
  entity->setPosition(position);
  entity->setCollisionRadius(radius);
  return entity;
}

}  // namespace

class Slice14GhostEntity : public Entity  // an entity nothing collides with
{
 public:
  bool canCollide() override { return false; }
};

OO_TEST(slice14NoEntity) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    HPVector p2 = make_HPvector(0, 0, 1000);

    OO_CHECK(!u->isVectorClearFromEntity(nullptr, 0, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(nullptr, 0, p2) == nullptr);
    OO_CHECK(HPvector_equal(u->getSafeVectorFromEntity(nullptr, 0, p2),
                            kZeroHPVector));
    OO_CHECK(u->firstShipHitByLaserFromShip(nullptr, WEAPON_FACING_FORWARD,
                                            kZeroVector, NULL) == nil);
    // The demo ship needs a docked player; with none there is no ship.
    SetUpTestPlayer();
    OO_CHECK(u->makeDemoShipWithRole("oolite-test", YES) == nil);
  }
}

OO_TEST(slice14ClearRoute) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Entity* e1 = MakeEntity(make_HPvector(0, 0, 0), 10);
    HPVector p2 = make_HPvector(0, 0, 1000);

    // Nothing else in the universe: clear, no hazard, the destination is safe
    // as it is.
    SetSortedEntities(u, {e1});
    OO_CHECK(u->isVectorClearFromEntity(e1, 0, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(e1, 0, p2) == nullptr);
    OO_CHECK(HPvector_equal(u->getSafeVectorFromEntity(e1, 0, p2), p2));

    // An entity off the route, behind the start, or beyond the destination is
    // no hazard.
    Entity* aside = MakeEntity(make_HPvector(500, 0, 500), 50);
    Entity* behind = MakeEntity(make_HPvector(0, 0, -300), 50);
    Entity* beyond = MakeEntity(make_HPvector(0, 0, 1500), 50);
    SetSortedEntities(u, {e1, aside, behind, beyond});
    OO_CHECK(u->isVectorClearFromEntity(e1, 0, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(e1, 0, p2) == nullptr);
    OO_CHECK(HPvector_equal(u->getSafeVectorFromEntity(e1, 0, p2), p2));

    // An entity nothing collides with is no hazard either.
    Entity* ghost = oo::MadeEntity(oo::makeRef<Slice14GhostEntity>());
    ghost->setPosition(make_HPvector(0, 0, 500));
    ghost->setCollisionRadius(50);
    SetSortedEntities(u, {e1, ghost});
    OO_CHECK(u->isVectorClearFromEntity(e1, 0, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(e1, 0, p2) == nullptr);
    u->n_entities = 0;
  }
}

OO_TEST(slice14Hazard) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Entity* e1 = MakeEntity(make_HPvector(0, 0, 0), 10);
    Entity* rock = MakeEntity(make_HPvector(20, 0, 500), 50);
    HPVector p2 = make_HPvector(0, 0, 1000);
    SetSortedEntities(u, {e1, rock});

    OO_CHECK(!u->isVectorClearFromEntity(e1, 0, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(e1, 0, p2) == rock);

    // The safe vector steers short of the rock and away from the side it is on.
    HPVector safe = u->getSafeVectorFromEntity(e1, 0, p2);
    OO_CHECK(!HPvector_equal(safe, p2));
    OO_CHECK(safe.z < 500 && safe.x < 20);

    // Within range of the destination already: clear, whatever is in the way.
    OO_CHECK(u->isVectorClearFromEntity(e1, 2000, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(e1, 2000, p2) == nullptr);

    // Stopping short of the rock: the route is clear.
    OO_CHECK(u->isVectorClearFromEntity(e1, 600, p2));
    OO_CHECK(u->hazardOnRouteFromEntity(e1, 600, p2) == nullptr);
    u->n_entities = 0;
  }
}

// Counting and finding entities by predicate, time,
// collisions, the view direction. Written against the Objective-C API and run
// on the unconverted class first; the entities sit in the sorted list by hand,
// as the demo-ship cases do. Counts as a ship for the ship predicates (a C++
// entity whose ship flag, which -isShip and the predicates read, is set).
class Slice15ShipLike : public Entity {
 public:
  Slice15ShipLike() { isShip = YES; }
};

namespace {

Entity* MakeShipLike(HPVector position, GLfloat radius) {
  Entity* entity = oo::MadeEntity(oo::makeRef<Slice15ShipLike>());
  entity->setPosition(position);
  entity->setCollisionRadius(radius);
  return entity;
}

BOOL IsFarPredicate(Entity* entity,
                    void* parameter)  // x beyond *(double *)parameter
{
  return entity->getPosition().x > *(double*)parameter;
}

}  // namespace

OO_TEST(slice15CountAndFind) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Entity* a = MakeEntity(make_HPvector(0, 0, 0), 10);
    Entity* b = MakeEntity(make_HPvector(100, 0, 0), 10);
    Entity* c = MakeShipLike(make_HPvector(1000, 0, 0), 10);
    SetSortedEntities(u, {a, b, c});

    // No predicate is every entity; no entity counts from the origin; the
    // reference itself never counts.
    OO_CHECK(u->countEntitiesMatchingPredicate(NULL, NULL, -1, nullptr) == 3);
    OO_CHECK(u->countEntitiesMatchingPredicate(NULL, NULL, -1, a) == 2);
    // The range reaches the other entity's surface: b's is 90 away from a, c's
    // 990.
    OO_CHECK(u->countEntitiesMatchingPredicate(NULL, NULL, 95, a) == 1);
    OO_CHECK(u->countEntitiesMatchingPredicate(NULL, NULL, 85, a) == 0);
    double limit = 50;
    OO_CHECK(u->countEntitiesMatchingPredicate(IsFarPredicate, &limit, -1,
                                               nullptr) == 2);

    // Ships: only c.
    OO_CHECK(u->countShipsMatchingPredicate(NULL, NULL, -1, a) == 1);
    OO_CHECK(u->countShipsMatchingPredicate(IsFarPredicate, &limit, -1,
                                            nullptr) == 1);
    OO_CHECK(u->countShipsMatchingPredicate(NULL, NULL, 500, a) == 0);

    std::vector<oo::EntityHold> found =
        u->findEntitiesMatchingPredicate(NULL, NULL, -1, a);
    OO_CHECK(found.size() == 2 && found[0].get() == b &&
             found[1].get() == c);  // in the sorted list's order
    found = u->findEntitiesMatchingPredicate(IsFarPredicate, &limit, 95, a);
    OO_CHECK(found.size() == 1 && found[0].get() == b);
    found = u->findShipsMatchingPredicate(NULL, NULL, -1, nullptr);
    OO_CHECK(found.size() == 1 && found[0].get() == c);
    OO_CHECK(
        u->findVisualEffectsMatchingPredicate(NULL, NULL, -1, nullptr).empty());

    // Within range of an entity: the ships only; none for no entity.
    OO_CHECK(u->entitiesWithinRange(2000, a).size() == 1);
    OO_CHECK(u->entitiesWithinRange(500, a).empty());
    OO_CHECK(u->entitiesWithinRange(2000, nullptr).empty());

    // The scan class.
    c->setScanClass(CLASS_ROCK);
    OO_CHECK(u->countShipsWithScanClass(CLASS_ROCK, -1, nullptr) == 1);
    OO_CHECK(u->countShipsWithScanClass(CLASS_NEUTRAL, -1, nullptr) == 0);

    u->n_entities = 0;
  }
}

OO_TEST(slice15FindOneAndNearest) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Entity* a = MakeEntity(make_HPvector(0, 0, 0), 10);
    Entity* b = MakeEntity(make_HPvector(300, 0, 0), 10);
    Entity* c = MakeShipLike(make_HPvector(200, 0, 0), 10);
    Entity* d = MakeShipLike(make_HPvector(-500, 0, 0), 10);
    SetSortedEntities(u, {a, b, c, d});
    double limit = 250;

    OO_CHECK(u->findOneEntityMatchingPredicate(NULL, NULL) == a);
    OO_CHECK(u->findOneEntityMatchingPredicate(IsFarPredicate, &limit) == b);
    limit = 5000;
    OO_CHECK(u->findOneEntityMatchingPredicate(IsFarPredicate, &limit) == nil);

    OO_CHECK(u->nearestEntityMatchingPredicate(NULL, NULL, a) == c);
    OO_CHECK(u->nearestEntityMatchingPredicate(NULL, NULL, nullptr) == a);
    limit = 250;
    OO_CHECK(u->nearestEntityMatchingPredicate(IsFarPredicate, &limit, a) == b);
    OO_CHECK(u->nearestShipMatchingPredicate(NULL, NULL, b) == c);
    OO_CHECK(u->nearestShipMatchingPredicate(IsFarPredicate, &limit, a) == nil);
    limit = -1000;
    OO_CHECK(u->nearestShipMatchingPredicate(IsFarPredicate, &limit, c) == d);

    u->n_entities = 0;
  }
}

OO_TEST(slice15TimeAndCollisions) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->universal_time = 12.5;
    u->time_delta = 0.25;
    OO_CHECK(u->getTime() == 12.5 && u->getTimeDelta() == 0.25);

    // No collision region yet: the description is a dash.
    OO_CHECK(u->collisionDescription() == "-");
    u->dumpCollisions();
    OO_CHECK(u->dumpCollisionInfo);

    u->viewDirection = VIEW_AFT;
    OO_CHECK(u->getViewDirection() == VIEW_AFT);
  }
}

// The view direction, custom sounds, screen
// backgrounds, messages. Written against the Objective-C API and run on the
// unconverted class first. A headless universe has no GUIs and no player (the
// messages that reach the player's script events are left to the goldens), so
// the messages are seen in the members that remember them (the current message
// and its repeat times).
namespace {

std::optional<std::string> CurrentMessage(Universe* u) {
  return u->currentMessage;
}
OOTimeAbsolute MessageRepeatTime(Universe* u) { return u->messageRepeatTime; }
OOTimeAbsolute CountdownRepeatTime(Universe* u) {
  return u->countdown_messageRepeatTime;
}

}  // namespace

OO_TEST(slice16Messages) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->universal_time = 10.0;

    u->displayMessage(std::string("a"), 3);
    OO_CHECK(CurrentMessage(u) == "a" && MessageRepeatTime(u) == 16.0);
    u->universal_time = 12.0;
    u->displayMessage(std::string("a"),
                      3);  // the same message, too soon: nothing
    OO_CHECK(MessageRepeatTime(u) == 16.0);
    u->displayMessage(std::string("b"), 3);
    OO_CHECK(CurrentMessage(u) == "b" && MessageRepeatTime(u) == 18.0);
    u->universal_time = 20.0;
    u->displayMessage(std::string("b"),
                      3);  // the same, once the repeat time has passed
    OO_CHECK(CurrentMessage(u) == "b" && MessageRepeatTime(u) == 26.0);

    // A countdown message waits for its own repeat time, whatever the message.
    u->displayCountdownMessage(std::string("c"), 5);
    OO_CHECK(CurrentMessage(u) == "c" && CountdownRepeatTime(u) == 25.0);
    u->displayCountdownMessage(std::string("d"), 5);
    OO_CHECK(CurrentMessage(u) == "c" && CountdownRepeatTime(u) == 25.0);
    u->displayCountdownMessage(std::string("c"),
                               5);  // the same message: nothing
    OO_CHECK(CountdownRepeatTime(u) == 25.0);

    u->clearPreviousMessage();
    OO_CHECK(!CurrentMessage(u).has_value());
  }
}

OO_TEST(slice16ViewDirection) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    // The view it already has, with no GUI shown: nothing changes and nothing
    // is said. (A change speaks through the player's script events, which need
    // the whole game.)
    u->viewDirection = VIEW_AFT;
    u->setViewDirection(VIEW_AFT);
    OO_CHECK(u->getViewDirection() == VIEW_AFT &&
             !CurrentMessage(u).has_value() && !u->getDisplayGUI());
  }
}

OO_TEST(slice16SoundsAndBackgrounds) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->customSounds = oo::PList(oo::PList::Dict{
        {"[slice16-boom]", oo::PList("boom.ogg")},
        {"[slice16-alias]", oo::PList("[slice16-boom]")},
        {"[slice16-loop1]", oo::PList("[slice16-loop2]")},
        {"[slice16-loop2]", oo::PList("[slice16-loop1]")},
    });

    OO_CHECK(u->soundNameForCustomSoundKey("[slice16-boom]") == "boom.ogg");
    OO_CHECK(u->soundNameForCustomSoundKey("[slice16-alias]") == "boom.ogg");
    OO_CHECK(!u->soundNameForCustomSoundKey("[slice16-missing]").has_value());
    OO_CHECK(!u->soundNameForCustomSoundKey("[slice16-loop1]")
                  .has_value());  // recursion: no sound

    // Backgrounds: none loaded, setting changes nothing; loaded, set and remove
    // by key.
    u->setScreenTextureDescriptorForKey("slice16", oo::PList("x.png"));
    OO_CHECK(u->screenBackgrounds.isNull());
    u->screenBackgrounds = oo::PList(oo::PList::Dict{});
    u->setScreenTextureDescriptorForKey("slice16", oo::PList("x.png"));
    const oo::PList* set = u->screenBackgrounds.find("slice16");
    OO_CHECK(set != nullptr && set->isString());
    u->setScreenTextureDescriptorForKey("slice16", oo::PList());
    OO_CHECK(u->screenBackgrounds.find("slice16") == nullptr);
    // With no GUI to preload it, no descriptor is answered.
    u->setScreenTextureDescriptorForKey("slice16", oo::PList("x.png"));
    OO_CHECK(u->screenTextureDescriptorForKey("slice16").isNull());
  }
}

// Update:, time acceleration, ECM visual effects.
// Written against the Objective-C API and run on the unconverted class first. A
// full update needs the whole game (the player, the JavaScript engine); a
// universe whose updates are off only lets go of the dead.
OO_TEST(slice17UpdateOff) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    SetUpTestPlayer();  // a player that is not dead: no dead player's update
    u->no_update = YES;
    u->universal_time = 5.0;
    u->time_delta = 0.5;
    Entity* dead = nil;
    {
      oo::AutoreleaseScope scope;  // the making's autoreleases drain here
      dead = oo::RetainEntity(oo::MadeEntity(oo::makeRef<Entity>()));
      u->entitiesDeadThisUpdate.emplace_back(dead);
    }
    oo::ReleaseEntity(dead);

    {
      oo::AutoreleaseScope scope;
      u->update(1.0);
      OO_CHECK(u->getTime() == 5.0 &&
               u->getTimeDelta() == 0.5);  // no time passes
      OO_CHECK(u->entitiesDeadThisUpdate.empty());
      OO_CHECK(dead->retainCount() == 1);  // alive until the pool drains
    }
  }
}

OO_TEST(slice17Settings) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    u->setECMVisualFXEnabled(YES);
    OO_CHECK(u->getECMVisualFXEnabled() && u->ECMVisualFXEnabled);
    u->setECMVisualFXEnabled(NO);
    OO_CHECK(!u->getECMVisualFXEnabled());

    u->setTimeAccelerationFactor(4.0);
#ifndef NDEBUG
    OO_CHECK(u->getTimeAccelerationFactor() == 4.0);
    u->setTimeAccelerationFactor(100.0);
    OO_CHECK(u->getTimeAccelerationFactor() ==
             TIME_ACCELERATION_FACTOR_DEFAULT);
#else
    OO_CHECK(u->getTimeAccelerationFactor() == 1.0);
#endif
  }
}

// FilterSortedLists, which marks the entities that
// cannot meet another on the z axis and chains the rest for the collision test.
// Written against the Objective-C API and run on the unconverted class first.
// The x, y and z lists are linked by hand in one order.
namespace {

void LinkLists(Universe* u, std::initializer_list<Entity*> list) {
  Entity* previous = nil;
  for (Entity* e : list) {
    Entity* part = e;
    part->x_previous = part->y_previous = part->z_previous = previous;
    part->x_next = part->y_next = part->z_next = nil;
    if (previous != nil)
      previous->x_next = previous->y_next = previous->z_next = part;
    previous = e;
  }
  Entity* first = list.size() > 0 ? *list.begin() : nil;
  u->x_list_start = u->y_list_start = u->z_list_start = first;
}

}  // namespace

OO_TEST(slice18FilterSortedLists) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Entity* a = MakeEntity(make_HPvector(0, 0, 0), 10);
    Entity* ghost = oo::MadeEntity(oo::makeRef<Slice14GhostEntity>());
    ghost->setPosition(make_HPvector(0, 0, 5));
    ghost->setCollisionRadius(10);
    Entity* b = MakeEntity(make_HPvector(0, 0, 15), 10);
    Entity* c = MakeEntity(make_HPvector(0, 0, 1000), 10);
    a->collision_chain = c;  // stale chains are cleared
    c->collision_chain = a;
    LinkLists(u, {a, ghost, b, c});

    u->filterSortedLists();

    // a and b overlap on z: chained, past the entity that cannot collide; c is
    // alone.
    OO_CHECK(a->collision_chain == b);
    OO_CHECK(b->collision_chain == nil);
    OO_CHECK(c->collision_chain == nil && ghost->collision_chain == nil);
    OO_CHECK(a->collisionTestFilter == 0 && b->collisionTestFilter == 0);
    OO_CHECK(c->collisionTestFilter == 1);
    OO_CHECK(ghost->collisionTestFilter == 3);

    LinkLists(u, {});
    u->filterSortedLists();  // no entities: nothing to do
    OO_CHECK(u->z_list_start == nil);
  }
}

// Galaxy and system changes, descriptions, scenarios,
// characters, mission text, system data and names, finding systems. Written
// against the Objective-C API and run on the unconverted class first. A
// headless universe has no system manager, so the state these answer is set in
// the members by hand.
OO_TEST(slice19Descriptions) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->_descriptions = oo::PList(oo::PList::Dict{
        {"slice19-text", oo::PList("Hello")},
        {"slice19-array",
         oo::PList(oo::PList::Array{oo::PList("zero"), oo::PList("one")})},
        {"slice19-flag", oo::PList(true)},
    });
    u->_descriptionsGeneration = 7;

    const oo::PList* descriptions = u->descriptions();
    OO_CHECK(descriptions == &u->_descriptions);
    OO_CHECK(u->descriptionsGeneration() == 7);
    OO_CHECK(u->descriptionForKey("slice19-text") == "Hello");
    OO_CHECK(!u->descriptionForKey("slice19-missing").has_value());
    OO_CHECK(u->descriptionForArrayKey("slice19-array", 1) == "one");
    OO_CHECK(!u->descriptionForArrayKey("slice19-array", 2).has_value());
    OO_CHECK(!u->descriptionForArrayKey("slice19-text", 0).has_value());
    OO_CHECK(u->descriptionBooleanForKey("slice19-flag"));
    OO_CHECK(!u->descriptionBooleanForKey("slice19-missing"));
    OO_CHECK(cxx_OOLookUpDescriptionPRIV("slice19-text") == "Hello");
  }
}

OO_TEST(slice19DataAndNames) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->explosionSettings = oo::PList(oo::PList::Dict{
        {"slice19-boom",
         oo::PList(oo::PList::Dict{{"size", oo::PList(2.0)}})}});
    u->_scenarios = oo::PList(oo::PList::Array{oo::PList("s")});
    u->characters = oo::PList(oo::PList::Dict{{"c", oo::PList("x")}});
    u->missiontext = oo::PList(oo::PList::Dict{{"m", oo::PList("y")}});
    u->systemID = 42;

    OO_CHECK(u->explosionSetting("slice19-boom").get<double>("size") == 2.0);
    OO_CHECK(u->explosionSetting("slice19-missing").isNull());
    OO_CHECK(u->scenarios().count() == 1);
    OO_CHECK(u->getCharacters().get<std::string>("c") == "x");
    OO_CHECK(u->getMissiontext().get<std::string>("m") == "y");
    OO_CHECK(u->currentSystemID() == 42);
    OO_CHECK(u->getSystemManager() == nil);

    OO_CHECK(u->keyForPlanetOverridesForSystem(7, 2) == "2 7");
    OO_CHECK(u->keyForInterstellarOverridesForSystems(3, 4, 2) ==
             "interstellar: 2 3 4");

    // Names are found whatever their case; a missing name matches nothing.
    u->system_names[5] = std::string("Lave");
    u->system_names[9] = std::string("Diso");
    OO_CHECK(u->findSystemFromName("lave") == 5);
    OO_CHECK(u->findSystemFromName("DISO") == 9);
    OO_CHECK(u->findSystemFromName("Zaonce") == -1);

    // No sun in the universe: interstellar space.
    OO_CHECK(u->inInterstellarSpace());
  }
}

// Neighbouring systems, system-name look-up, routes,
// planet textures, global and equipment data, the commodity market, time
// descriptions. Written against the Objective-C API and run on the unconverted
// class first; with no system manager, what needs the galaxy's data is left to
// the goldens.
OO_TEST(slice20NamesAndRoutes) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->system_names[5] = std::string("Lave");
    OO_CHECK(u->systemNameIndex(5) == "Lave");
    OO_CHECK(u->systemNameIndex(256 + 5) == "Lave");  // the index wraps at 256
    OO_CHECK(!u->systemNameIndex(6).has_value());
    OO_CHECK(u->systemsFound() == (BOOL*)u->system_found);

    // No route from or to interstellar space, or outside the galaxy.
    OO_CHECK(u->routeFromSystem(-1, 7, OPTIMIZED_BY_JUMPS).isNull());
    OO_CHECK(u->routeFromSystem(7, -1, OPTIMIZED_BY_TIME).isNull());
    OO_CHECK(u->routeFromSystem(300, 7, OPTIMIZED_BY_JUMPS).isNull());

    // The current system's neighbours, once cached, are the cache.
    u->systemID = 3;
    u->closeSystems = std::vector<OOSystemID>{1, 2};
    OO_CHECK(u->neighboursToSystem(3) == (std::vector<OOSystemID>{1, 2}));

    u->preloadPlanetTexturesForSystem(3);  // disabled: does nothing
  }
}

OO_TEST(slice20DataAndTime) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->globalSettings = oo::PList(oo::PList::Dict{{"g", oo::PList("1")}});
    u->equipmentData = oo::PList(oo::PList::Array{oo::PList("e")});
    u->equipmentDataOutfitting =
        oo::PList(oo::PList::Array{oo::PList("o"), oo::PList("p")});
    OO_CHECK(u->getGlobalSettings().get<std::string>("g") == "1");
    OO_CHECK(u->getEquipmentData().count() == 1);
    OO_CHECK(u->getEquipmentDataOutfitting().count() == 2);
    OO_CHECK(u->getCommodityMarket() == nil);

    OO_CHECK(u->timeDescription(90061) == "1 day 1 hour 1 minute 1 second");
    OO_CHECK(u->timeDescription(2 * 86400 + 7200 + 120 + 2.5) ==
             "2 days 2 hours 2 minutes 2 seconds");
    OO_CHECK(u->timeDescription(3600) ==
             "60 minutes");  // not more than an hour
    OO_CHECK(u->timeDescription(0) == "");
  }
}

// Short time descriptions, sun skimmers, station
// markets. Written against the Objective-C API and run on the unconverted class
// first; the words come from descriptions set in the member by hand (no plural
// rules: "%0" is the singular, "%1" the plural).
OO_TEST(slice21ShortTimeAndMarkets) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    oo::PList::Dict words{{"contracts-no-time", oo::PList("no time")}};
    for (const char* unit : {"day", "hour", "minute", "second"}) {
      words[std::string("contracts-") + unit + "-word%0"] =
          oo::PList(std::string(unit));
      words[std::string("contracts-") + unit + "-word%1"] =
          oo::PList(std::string(unit) + "s");
    }
    u->_descriptions = oo::PList(std::move(words));

    OO_CHECK(u->shortTimeDescription(0) == "no time");
    OO_CHECK(u->shortTimeDescription(-5) == "no time");
    OO_CHECK(u->shortTimeDescription(90061) ==
             "1 day 1 hour");  // two parts at most
    OO_CHECK(u->shortTimeDescription(2 * 3600 + 5) == "2 hours 5 seconds");
    OO_CHECK(u->shortTimeDescription(125) == "2 minutes 5 seconds");
    OO_CHECK(u->shortTimeDescription(1) == "1 second");

    // No stations: no markets to save, and none to load into.
    const oo::PList saved = u->getStationMarkets();
    OO_CHECK(saved.isArray() && saved.count() == 0);
    u->loadStationMarkets(oo::PList());
    u->loadStationMarkets(
        oo::PList(oo::PList::Array{oo::PList(oo::PList::Dict{})}));
  }
}

// Witchspace exit and sun-skim positions, beacons by
// code, script events to all ships, the GUIs and display flags. Written against
// the Objective-C API and run on the unconverted class first; trade-in values
// and brochures need the ship registry (the goldens).
OO_TEST(slice23PositionsAndLists) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    OO_CHECK(HPvector_equal(u->getWitchspaceExitPosition(), kZeroHPVector));
    Quaternion q =
        u->getWitchspaceExitRotation();  // close to the identity, normalised
    OO_CHECK(fabs(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z - 1.0) < 1e-5);
    OO_CHECK(q.w > 0.9f);

    // No ship, or no sun: the origin.
    OO_CHECK(HPvector_equal(u->getSunSkimStartPositionForShip(nullptr),
                            kZeroHPVector));
    OO_CHECK(HPvector_equal(u->getSunSkimEndPositionForShip(nullptr),
                            kZeroHPVector));

    // No beacons.
    OO_CHECK(u->listBeaconsWithCode("A").empty());
  }
}

OO_TEST(slice23GUIsAndFlags) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    OO_CHECK(u->getGui() == nil && u->commLogGUI() == nil &&
             u->messageGUI() == nil);

    u->setDisplayText(YES);
    OO_CHECK(u->getDisplayGUI() == YES && u->displayGUI == YES);
    u->setDisplayText(NO);
    OO_CHECK(!u->getDisplayGUI());
    u->setDisplayFPS(YES);
    OO_CHECK(u->getDisplayFPS());
    u->setDisplayFPS(NO);
    OO_CHECK(!u->getDisplayFPS());
    u->setAutoSaveNow(YES);
    OO_CHECK(u->autoSaveNow == YES);
    u->autoSave = YES;
    OO_CHECK(u->getAutoSave());
  }
}

// Autosave, wireframe and detail levels, shaders,
// exceptions, speech (eSpeak and none), message logs, settings, session IDs.
// Written against the Objective-C API and run on the unconverted class first.
// The setters that write the user's preferences
// (-setWireframeGraphics:, -setDetailLevel:) and the set-up that loads the
// game's files are left to the goldens; their state is set in the members by
// hand.
OO_TEST(slice24DetailAndLogs) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();

    u->detailLevel = DETAIL_LEVEL_SHADERS;
    OO_CHECK(u->getDetailLevel() == DETAIL_LEVEL_SHADERS && u->useShaders() &&
             !u->reducedDetail());
    u->detailLevel = DETAIL_LEVEL_MINIMUM;
    OO_CHECK(u->reducedDetail() && !u->useShaders());
    u->wireframeGraphics = YES;
    OO_CHECK(u->getWireframeGraphics());

    u->setAutoSaveNow(YES);
    OO_CHECK(u->getAutoSaveNow());
    u->setAutoSaveNow(NO);
    OO_CHECK(!u->getAutoSaveNow());

    u->setPauseMessageVisible(YES);
    OO_CHECK(u->pauseMessageVisible());
    u->setPauseMessageVisible(NO);
    OO_CHECK(!u->pauseMessageVisible());
    u->setAutoCommLog(YES);
    OO_CHECK(u->_autoCommLog);
    u->setPermanentCommLog(NO);
    u->setPermanentMessageLog(NO);
    u->setAutoMessageLogBg(NO);
    OO_CHECK(!u->permanentCommLog() && !u->permanentMessageLog() &&
             !u->autoMessageLogBg());

    // Blocking remembers the player as stale.
    SetUpTestPlayer();
    u->setBlockJSPlayerShipProps(YES);
    OO_CHECK(u->blockJSPlayerShipProps());
    u->setBlockJSPlayerShipProps(NO);
    OO_CHECK(!u->blockJSPlayerShipProps());

    // A non-fatal exception is only logged; nil is ignored.
    const oo::Exception exception("OoliteSlice24Exception", "test");
    u->handleOoliteException(&exception);
    u->handleOoliteException(nullptr);
  }
}

#if OOLITE_ESPEAK
OO_TEST(slice24Voices) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    espeak_VOICE v0 = {}, v1 = {}, v2 = {};
    v0.name = "zero";
    v1.name = "one";
    v2.name = "two";
    const espeak_VOICE* voices[] = {&v0, &v1, &v2, NULL};
    u->espeak_voices = voices;
    u->espeak_voice_count = 3;

    OO_CHECK(u->nextVoice(0) == 1 && u->nextVoice(2) == 0);
    OO_CHECK(u->prevVoice(1) == 0 && u->prevVoice(0) == 2);
    OO_CHECK(u->voiceName(1) == "one" && u->voiceName(3) == "-");
    OO_CHECK(u->voiceNumber("two") == 2 && u->voiceNumber("nine") == UINT_MAX);

    u->espeak_voices = nullptr;
    u->espeak_voice_count = 0;
  }
}
#endif

// Reinitialising and the demo, the initial universe,
// random positions, removing entities, preloading sounds, wormhole population,
// graph dumps. Written against the Objective-C API and run on the unconverted
// class first; the selectors only the private category declared are declared
// here, as test_Entity's (TestPrivate). Reinitialising and the initial universe
// need the whole game (the goldens).

OO_TEST(slice25RandomPositions) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    const double half = SCANNER_MAX_RANGE / 2;
    for (int i = 0; i < 20; i++) {
      float d = u->randomDistanceWithinScanner();
      OO_CHECK(d >= -half && d < half);

      Vector v = u->randomPlaceWithinScannerFrom(make_vector(10, 20, 30),
                                                 make_vector(1, 0, 0), 100);
      OO_CHECK(v.x >= 110 - half && v.x < 110 + half && v.y >= 20 - half &&
               v.y < 20 + half && v.z >= 30 - half && v.z < 30 + half);

      HPVector h = u->fractionalPositionFrom(make_HPvector(0, 0, 0),
                                             make_HPvector(1000, 0, 0), 0.5);
      OO_CHECK(
          h.x >= 500 - SCANNER_MAX_RANGE && h.x <= 500 + SCANNER_MAX_RANGE &&
          fabs(h.y) <= SCANNER_MAX_RANGE && fabs(h.z) <= SCANNER_MAX_RANGE);
    }
  }
}

OO_TEST(slice25ChooseStringAndWormholes) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    const oo::PList dict(oo::PList::Dict{
        {"one", oo::PList("only")},
        {"some", oo::PList(oo::PList::Array{oo::PList("a"), oo::PList("b")})},
        {"none", oo::PList(oo::PList::Array{})},
        {"number", oo::PList(3.0)},
    });
    OO_CHECK(u->chooseStringForKey("one", dict) == "only");
    std::optional<std::string> some = u->chooseStringForKey("some", dict);
    OO_CHECK(some == "a" || some == "b");
    OO_CHECK(!u->chooseStringForKey("none", dict).has_value());
    OO_CHECK(!u->chooseStringForKey("number", dict).has_value());
    OO_CHECK(!u->chooseStringForKey("missing", dict).has_value());

    u->populateSpaceFromActiveWormholes();  // none: nothing to do
    OO_CHECK(u->activeWormholes.empty());
  }
}

OO_TEST(slice25DoRemoveEntity) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    Entity* a = MakeEntity(make_HPvector(0, 0, 0), 1);
    Entity* b = MakeEntity(make_HPvector(5, 0, 0), 1);
    SetSortedEntities(u, {a, b});
    a->zero_index = 0;
    b->zero_index = 1;
    u->entities.emplace_back(a);
    u->entities.emplace_back(b);

    OO_CHECK(u->doRemoveEntity(a));
    OO_CHECK(u->n_entities == 1 && SortedEntity(u, 0) == b &&
             SortedEntity(u, 1) == nil);
    OO_CHECK(b->zero_index == 0 && a->zero_index == -1);
    OO_CHECK(u->entities.size() == 1 && u->entities[0].get() == b);
    OO_CHECK(
        !u->doRemoveEntity(a));  // gone already: not in the definitive list

    u->n_entities = 0;
    u->entities.clear();
  }
}

// Graph-viz references, localisation tools,
// planet-material pruning, condition scripts, the custom-sound categories of
// OOSound and OOSoundSource, description look-ups. Written against the
// Objective-C API and run on the unconverted class first. Loading a condition
// script or a sound file needs the JavaScript engine and the game's files (the
// goldens): here only what is missing.

OO_TEST(slice26GraphVizAndTools) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
#if OO_LOCALIZATION_TOOLS
    std::string graphViz = "start\n";
    u->addNumericRefsInString("a [3] b %H", graphViz, "from", 10);
    OO_CHECK(graphViz ==
             "start\n"
             "\tfrom -> n3_0 [color=\"0.300000,0.75,0.8\" lhead=cluster_3]\n"
             "\tfrom -> percent_H [color=\"0,0,0.45\"]\n");
    graphViz.clear();
    u->addNumericRefsInString("%I %R %J %G", graphViz, "x", 4);
    OO_CHECK(graphViz ==
             "\tx -> percent_I [color=\"0,0,0.25\"]\n"
             "\tx -> percent_RN [color=\"0,0,0.65\"]\n"
             "\tx -> percent_J [color=\"0,0,0.75\"]\n"
             "\tx -> percent_G [color=\"0,0,0.85\"]\n");
    graphViz.clear();
    u->addNumericRefsInString("no refs [unclosed", graphViz, "x", 4);
    OO_CHECK(graphViz.empty());

    u->runLocalizationTools();  // no --compile-sysdesc / --export-sysdesc:
                                // nothing
#endif

    u->prunePreloadingPlanetMaterials();  // none preloading
    OO_CHECK(u->_preloadingPlanetMaterials.empty());
  }
}

OO_TEST(slice26ConditionScriptsAndSounds) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->addConditionScripts(std::vector<std::string>());
    OO_CHECK(u->conditionScripts.empty());
    OO_CHECK(u->getConditionScript("slice26-missing.js") == nil);

    // A key with no custom sound makes no sound.
    u->customSounds = oo::PList(oo::PList::Dict{});
    OO_CHECK(OOSoundWithCustomSoundKey("[slice26-missing]") == nullptr);
  }
}

OO_TEST(slice26PluralDescriptions) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = NewUniverse();
    u->_descriptions = oo::PList(oo::PList::Dict{
        {"plural-rules", oo::PList(oo::PList::Array{oo::PList("=1")})},
        {"slice26-apple%0", oo::PList("apple")},
        {"slice26-apple%1", oo::PList("apples")},
        {"slice26-word", oo::PList("word")},
    });
    OO_CHECK(cxx_OOLookUpPluralDescriptionPRIV("slice26-apple", 1) == "apple");
    OO_CHECK(cxx_OOLookUpPluralDescriptionPRIV("slice26-apple", 3) == "apples");
    OO_CHECK(cxx_OOLookUpPluralDescriptionPRIV("slice26-apple", 0) == "apples");
    OO_CHECK(cxx_OOLookUpDescriptionPRIV("slice26-word") == "word");
    OO_CHECK(cxx_OOLookUpDescriptionPRIV("slice26-none") ==
             "slice26-none");  // the key itself
  }
}

OO_TEST_MAIN()
