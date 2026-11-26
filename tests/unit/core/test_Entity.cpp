/*	test_Entity.mm
        Unit tests for Entity (src/Core/Entities/Entity.h), the root of the
   entity hierarchy.

        Entity's object reads Universe and PlayerEntity, so the test links the
   whole game but main (tests/unit/core/meson.build entry ['*']) and defines
   the one global main.mm did, gDebugFlags. UNIVERSE is a Universe that was
   never initialised (zeroed by the runtime: session 0, time 0, no entities),
   whose ivars the test sets where a case needs them, and PLAYER is a plain
   entity that answers -viewpointPosition. The tests cover the defaults an
   entity starts with, the accessors and what they derive (camera ranges,
   speed, matrices), movement and rotation, -update: in the cockpit, in flight
   and as a subentity, owners (weak) and parents, the position-sorted linked
   lists, the session check, the shader bindings, the description, and which
   methods reach a subclass's overrides. Ivars the game reads directly (the
   lists, the motion flags) are read through the small block of helpers below,
   the one place that knows where they live. The tests after the first ones
   pin the crossing, as test_OODrawable.mm does: a C++ entity and the
   dump-state lines. Run: tests/run.sh unit
*/

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <type_traits>
#include <vector>

#include "Entity.h"
#include "OODebugFlags.h"
#include "OODescription.h"
#include "PlayerEntity.h"
#include "Universe.h"
#include "oo_test.hpp"
#include "oofnd/Log.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;

// PLAYER: a player whose viewpoint is set by the test (PlayerEntity's is its
// position plus an offset).
class TestPlayer : public PlayerEntity {
 public:
  HPVector _viewpoint = kZeroHPVector;

  HPVector viewpointPosition() override { return _viewpoint; }
};

// A C++ player made as PlayerEntity::sharedPlayer() makes the game's,
// retained (+1) as +alloc's object was.
template <class T>
T* NewTestPlayer() {
  oo::Ref<T> player = oo::makeRef<T>();
  {
    oo::AutoreleaseScope scope;
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

// A subclass whose overrides count, so the test sees which of the root's
// members reach it: a C++ subclass overriding the virtual members, with the
// same counts. Global and keeping its name, which the expected log and dump
// texts print.
class TestObjCEntity : public Entity {
 public:
  bool isPlanet() override { return true; }
  bool canCollide() override { return false; }
  GLfloat frustumRadius() override { return _frustumRadius; }
  NSUInteger sessionID() override { return _session; }
  bool isVisible() override { return _visible; }
  void updateCameraRelativePosition() override {
    _cameraUpdates++;
    Entity::updateCameraRelativePosition();
  }
  void orientationChanged() override {
    _orientationChanges++;
    Entity::orientationChanged();
  }
  void dumpSelfState() override {
    Entity::dumpSelfState();
    _selfStateDumps++;
  }
  void drawImmediate(bool, bool) override { _draws++; }

  int _cameraUpdates = 0;
  int _orientationChanges = 0;
  int _selfStateDumps = 0;
  int _draws = 0;
  GLfloat _frustumRadius = 0;
  NSUInteger _session = 0;
  bool _visible = false;
};

// A converted entity: a C++ subclass. Global, as a game class is, so that its
// description names it as the game's would.
class TestCxxEntity : public Entity {
 public:
  bool isPlanet() override { return true; }
  GLfloat frustumRadius() override { return 2.0f; }
  void updateCameraRelativePosition() override {
    cameraUpdates++;
    Entity::updateCameraRelativePosition();
  }
  std::optional<std::string> descriptionComponents() const override {
    return "test";
  }

  int cameraUpdates = 0;
};

namespace {

// --- Ivars the game reads directly (ent->x_next, ent->hasMoved), and nothing
// else -----------------

Entity* XPrevious(Entity* e) { return e->x_previous; }
Entity* XNext(Entity* e) { return e->x_next; }
Entity* YNext(Entity* e) { return e->y_next; }
Entity* ZNext(Entity* e) { return e->z_next; }
bool HasMoved(Entity* e) { return e->hasMoved; }
bool HasRotated(Entity* e) { return e->hasRotated; }
void SetSubEntity(Entity* e, bool value) { e->isSubEntity = value; }
void SetIsShip(Entity* e, bool value) { e->isShip = value; }
GLfloat NoDrawDistance(Entity* e) { return e->no_draw_distance; }
Vector CameraRelativePosition(Entity* e) { return e->cameraRelativePosition; }

// --------------------------------------------------------------------------------------------------

Universe* sUniverse = nullptr;

// What the entity logs: every class displayed, every line kept.
std::vector<std::string> sLog;

void CaptureLine(std::string_view line) {
  sLog.emplace_back(line);
  if (std::getenv("OO_TEST_ECHO_LOG") != nullptr)
    std::fprintf(stderr, "log: %s\n", sLog.back().c_str());
}

void CaptureLog() {
  oo::log::Logger& logger = oo::log::logger();
  logger.setInitialized(true);
  logger.setSink(CaptureLine);
  sLog.clear();
}

bool Logged(const std::string& text) {
  for (const std::string& line : sLog) {
    if (line.find(text) != std::string::npos) return true;
  }
  return false;
}

// Universe's ivars are members of its C++ part.
template <class T>
T& UniverseIvar(const char* name) {
  Universe* part = sUniverse;
  // Each name answers only the ivar's own type (GCC -Wstrict-aliasing on the
  // other cast).
  if constexpr (std::is_same_v<T, decltype(part->_sessionID)>) {
    if (std::strcmp(name, "_sessionID") == 0) return part->_sessionID;
  }
  if constexpr (std::is_same_v<T, decltype(part->universal_time)>) {
    if (std::strcmp(name, "universal_time") == 0) return part->universal_time;
  }
  std::abort();
}

// A Universe that was never initialised: the runtime zeroed it (session 0, time
// 0, no entities).
void SetUpUniverse() {
  if (sUniverse == nullptr) {
    sUniverse = new Universe();  // never released
  }
  gSharedUniverse = sUniverse;
  UniverseIvar<NSUInteger>("_sessionID") = 0;
  UniverseIvar<OOTimeAbsolute>("universal_time") = 0;
  sUniverse->n_entities = 0;
  sUniverse->x_list_start = sUniverse->y_list_start = sUniverse->z_list_start =
      nullptr;
}

TestPlayer* SetUpPlayer(HPVector position, HPVector viewpoint) {
  static TestPlayer* player = nullptr;
  if (player == nullptr)
    player =
        NewTestPlayer<TestPlayer>();  // never released, as the player is not
  gOOPlayer = player;  // before its position, which reads PLAYER (the debug
                       // build asserts it is set)
  player->setPosition(position);
  player->_viewpoint = viewpoint;
  return player;
}

Entity* MakeEntity(HPVector position, GLfloat radius) {
  Entity* entity = oo::MadeEntity(oo::makeRef<Entity>());
  entity->setPosition(position);
  entity->setCollisionRadius(radius);
  return entity;
}

bool VectorEqual(Vector a, Vector b) {
  return a.x == b.x && a.y == b.y && a.z == b.z;
}

bool Near(double a, double b) { return a - b < 1e-5 && b - a < 1e-5; }

bool QuaternionNear(Quaternion a, Quaternion b) {
  return Near(a.w, b.w) && Near(a.x, b.x) && Near(a.y, b.y) && Near(a.z, b.z);
}

}  // namespace

OO_TEST(defaults) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);
    UniverseIvar<NSUInteger>("_sessionID") = 7;
    UniverseIvar<OOTimeAbsolute>("universal_time") = 12.5;

    Entity* entity = oo::MadeEntity(oo::makeRef<Entity>());
    OO_CHECK(entity->sessionID() == 7);
    OO_CHECK(entity->getSpawnTime() == 12.5f);
    OO_CHECK(!entity->getIsShip() && !entity->isDock() &&
             !entity->getIsStation() && !entity->getIsSubEntity() &&
             !entity->getIsPlayer());
    OO_CHECK(!entity->isPlanet() && !entity->isSun() &&
             !entity->isStellarObject() && !entity->isSky() &&
             !entity->getIsWormhole());
    OO_CHECK(!entity->isEffect() && !entity->getIsVisualEffect() &&
             !entity->isWaypoint() && !entity->getIsImmuneToBreakPatternHide());
    OO_CHECK(entity->getIsSunlit());
    OO_CHECK(entity->status() == STATUS_COCKPIT_DISPLAY &&
             entity->getScanClass() == CLASS_NOT_SET);
    OO_CHECK(!entity->isInSpace());
    OO_CHECK(HPvector_equal(entity->getPosition(), kZeroHPVector));
    OO_CHECK(quaternion_equal(entity->getOrientation(), kIdentityQuaternion));
    OO_CHECK(OOMatrixEqual(entity->rotationMatrix(), kIdentityMatrix));
    OO_CHECK(entity->getEnergy() == 0 && entity->getMaxEnergy() == 0 &&
             entity->getMass() == 0);
    OO_CHECK(entity->collisionRadius() == 0 && entity->frustumRadius() == 0);
    OO_CHECK(entity->getUniversalID() == NO_TARGET &&
             entity->getLastDrawCounter() == 0);
    OO_CHECK(entity->owner() == nullptr && entity->parentEntity() == nullptr &&
             entity->rootShipEntity() == nullptr);
    OO_CHECK(entity->getCollisionRegion() == nullptr);
    OO_CHECK(entity->getCollidingEntities() != nullptr &&
             entity->getCollidingEntities()->empty());
    OO_CHECK(entity->canCollide() && entity->isVisible() &&
             !entity->throwingSparks());
    OO_CHECK(NoDrawDistance(entity) == 100000.0f);

    OOColor* fog = entity->fogUniform().get();
    OO_CHECK(fog != nullptr);
    OO_CHECK(fog->redComponent() == 0 && fog->greenComponent() == 0 &&
             fog->blueComponent() == 0 && fog->alphaComponent() == 0);

    // The components %@ prints.
    OO_CHECK(oo::EntityDescription(entity).ends_with(
        "{position: (0, 0, 0) scanClass: CLASS_NOT_SET status: "
        "STATUS_COCKPIT_DISPLAY}"));
    OO_CHECK(oo::EntityDescription(entity).starts_with("<Entity 0x"));
  }
}

OO_TEST(accessors) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(make_HPvector(1, 1, 1), make_HPvector(0, 0, 10));

    Entity* entity = MakeEntity(make_HPvector(3, 4, 10), 2.0f);
    OO_CHECK(HPvector_equal(entity->getPosition(), make_HPvector(3, 4, 10)));
    // -setPosition: updates the camera-relative position from PLAYER's
    // viewpoint.
    OO_CHECK(
        VectorEqual(entity->getCameraRelativePosition(), make_vector(3, 4, 0)));
    OO_CHECK(entity->cameraRangeFront() == 3.0f &&
             entity->cameraRangeBack() == 7.0f);
    OO_CHECK(VectorEqual(entity->relativePosition(), make_vector(2, 3, 9)));

    entity->setPositionX(-1, -2, -3);
    OO_CHECK(HPvector_equal(entity->getPosition(), make_HPvector(-1, -2, -3)));
    OO_CHECK(VectorEqual(entity->getCameraRelativePosition(),
                         make_vector(-1, -2, -13)));

    Entity* other = MakeEntity(make_HPvector(2, 2, 2), 1.0f);
    OO_CHECK(VectorEqual(entity->vectorTo(other), make_vector(3, 4, 5)));

    entity->setVelocity(make_vector(3, 0, 4));
    OO_CHECK(VectorEqual(entity->getVelocity(), make_vector(3, 0, 4)) &&
             entity->speed() == 5.0);
    entity->setEnergy(40);
    entity->setMaxEnergy(100);
    OO_CHECK(entity->getEnergy() == 40 && entity->getMaxEnergy() == 100);
    entity->setDistanceTravelled(9);
    OO_CHECK(entity->getDistanceTravelled() == 9);
    entity->setStatus(STATUS_IN_FLIGHT);
    OO_CHECK(entity->status() == STATUS_IN_FLIGHT && entity->isInSpace());
    entity->setStatus(STATUS_DEAD);
    OO_CHECK(!entity->isInSpace());
    entity->setScanClass(CLASS_BUOY);
    OO_CHECK(entity->getScanClass() == CLASS_BUOY);
    entity->setUniversalID(42);
    OO_CHECK(entity->getUniversalID() == 42);
    entity->setUniversalID(
        NO_TARGET);  // so that -dealloc does not ask the universe to remove it
    entity->setThrowSparks(true);
    OO_CHECK(entity->throwingSparks());
    entity->throwSparks();
    entity->setLastDrawCounter(17);
    OO_CHECK(entity->getLastDrawCounter() == 17);

    // -compareZeroDistance: sorts the nearer entity later.
    SetUpPlayer(kZeroHPVector, kZeroHPVector);
    entity->update(0);
    other->update(0);
    OO_CHECK(entity->zeroDistance() == 14.0 && other->zeroDistance() == 12.0);
    OO_CHECK(entity->compareZeroDistance(other) == OOOrderedAscending);
    OO_CHECK(other->compareZeroDistance(entity) == OOOrderedDescending);
    OO_CHECK(entity->compareZeroDistance(nullptr) == OOOrderedDescending);

    OO_CHECK(!entity->checkCloseCollisionWith(nullptr) &&
             entity->checkCloseCollisionWith(other));
    entity->takeEnergyDamage(10, other, other, "EQ_WEAPON_TEST");
    OO_CHECK(entity->getEnergy() == 40);  // the root takes no damage
    entity->warnAboutHostiles();
    entity->wasAddedToUniverse();
    entity->wasRemovedFromUniverse();
  }
}

OO_TEST(orientationAndMovement) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    Entity* entity = MakeEntity(kZeroHPVector, 1.0f);
    Quaternion q =
        make_quaternion(2, 0, 0, 0);  // normalised by -setOrientation:
    entity->setOrientation(q);
    OO_CHECK(quaternion_equal(entity->getOrientation(), kIdentityQuaternion));
    OO_CHECK(
        quaternion_equal(entity->normalOrientation(), kIdentityQuaternion));

    // No rotation and no rotation last frame: nothing happens.
    entity->applyRoll(0, 0);
    OO_CHECK(quaternion_equal(entity->getOrientation(), kIdentityQuaternion));

    Quaternion expected = kIdentityQuaternion;
    quaternion_rotate_about_z(&expected, -0.25f);
    quaternion_rotate_about_x(&expected, -0.5f);
    quaternion_normalize(&expected);
    entity->applyRoll(0.25f, 0.5f);
    OO_CHECK(QuaternionNear(entity->getOrientation(), expected));
    OO_CHECK(
        OOMatrixEqual(entity->rotationMatrix(),
                      OOMatrixForQuaternionRotation(entity->getOrientation())));
    OO_CHECK(
        OOMatrixEqual(entity->drawRotationMatrix(), entity->rotationMatrix()));

    quaternion_rotate_about_z(&expected, -0.1f);
    quaternion_rotate_about_x(&expected, -0.2f);
    quaternion_rotate_about_y(&expected, -0.3f);
    quaternion_normalize(&expected);
    entity->applyRoll(0.1f, 0.2f, 0.3f);
    OO_CHECK(QuaternionNear(entity->getOrientation(), expected));

    entity->setNormalOrientation(kIdentityQuaternion);
    OO_CHECK(quaternion_equal(entity->getOrientation(), kIdentityQuaternion));

    // Forward is +z for the identity orientation.
    entity->moveForward(5);
    OO_CHECK(HPvector_equal(entity->getPosition(), make_HPvector(0, 0, 5)));
    OO_CHECK(entity->getDistanceTravelled() == 5);

    OOMatrix translated =
        OOMatrixHPTranslate(kIdentityMatrix, make_HPvector(0, 0, 5));
    OO_CHECK(OOMatrixEqual(entity->transformationMatrix(), translated));
    OO_CHECK(OOMatrixEqual(entity->drawTransformationMatrix(), translated));

    // With no parent, the absolute position of an offset is position + offset
    // rotated.
    OO_CHECK(HPvector_equal(entity->absolutePositionForSubentity(),
                            make_HPvector(0, 0, 5)));
    OO_CHECK(HPvector_equal(
        entity->absolutePositionForSubentityOffset(make_HPvector(1, 2, 3)),
        make_HPvector(1, 2, 8)));
  }
}

OO_TEST(update) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(make_HPvector(0, 0, 1), make_HPvector(0, 0, 2));

    // In the cockpit display, the distances are from the origin and the entity
    // does not move.
    Entity* entity = MakeEntity(make_HPvector(3, 0, 4), 1.0f);
    entity->setVelocity(make_vector(1, 0, 0));
    entity->update(2);
    OO_CHECK(entity->zeroDistance() == 25.0 &&
             entity->camZeroDistance() == 25.0);
    OO_CHECK(VectorEqual(CameraRelativePosition(entity), make_vector(3, 0, 4)));
    OO_CHECK(HPvector_equal(entity->getPosition(), make_HPvector(3, 0, 4)));
    OO_CHECK(
        HasMoved(entity) &&
        HasRotated(entity));  // from the zeroed last position and orientation
    entity->update(2);
    OO_CHECK(!HasMoved(entity) && !HasRotated(entity));

    // In flight, from PLAYER's position and viewpoint, then the velocity
    // applies.
    entity->setStatus(STATUS_IN_FLIGHT);
    entity->update(2);
    OO_CHECK(entity->zeroDistance() == 18.0 &&
             entity->camZeroDistance() == 13.0);
    OO_CHECK(VectorEqual(CameraRelativePosition(entity), make_vector(3, 0, 2)));
    OO_CHECK(HPvector_equal(entity->getPosition(), make_HPvector(5, 0, 4)));
    OO_CHECK(HasMoved(entity));

    // A subentity takes its owner's distances.
    Entity* sub = MakeEntity(make_HPvector(100, 0, 0), 1.0f);
    sub->setOwner(entity);
    SetSubEntity(sub, true);
    sub->setStatus(STATUS_IN_FLIGHT);
    sub->update(0);
    OO_CHECK(sub->zeroDistance() == 18.0 && sub->camZeroDistance() == 13.0);
    OO_CHECK(sub->getIsSubEntity());
  }
}

OO_TEST(ownersAndParents) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    Entity* entity = MakeEntity(kZeroHPVector, 1.0f);
    {
      oo::AutoreleaseScope scope;
      Entity* owner = oo::RetainEntity(oo::MadeEntity(oo::makeRef<Entity>()));
      entity->setOwner(owner);
      OO_CHECK(entity->owner() == owner);
      // Not a ship with this as a subentity: no parent, and not a ship itself.
      OO_CHECK(entity->parentEntity() == nullptr &&
               entity->rootShipEntity() == nullptr);
      OO_CHECK(entity->superShaderBindingTarget() == nullptr);
      oo::ReleaseEntity(owner);
    }
    OO_CHECK(entity->owner() == nullptr);  // held weakly

    entity->setOwner(entity);
    OO_CHECK(entity->owner() == entity);
    entity->setOwner(nullptr);
    OO_CHECK(entity->owner() == nullptr);
    CaptureLog();
    entity->dumpState();
    OO_CHECK(Logged("State for <Entity 0x") && Logged("Universal ID: 0") &&
             Logged("Scan class: CLASS_NOT_SET"));
    OO_CHECK(Logged("Status: STATUS_COCKPIT_DISPLAY") &&
             Logged("Position: (0, 0, 0)") &&
             Logged("Orientation: (1 + 0i + 0j + 0k)"));
    OO_CHECK(Logged("Distance travelled: 0") && Logged("Energy: 0 of 0") &&
             Logged("Mass: 0"));
    // The owner line and those after it are not pinned here: the Objective-C
    // body described the literal @"none", and a tiny string's -description
    // could raise, which -dumpState swallowed, ending the dump.

    SetIsShip(entity, true);
    OO_CHECK(entity->getIsShip() && entity->rootShipEntity() == entity);
    SetIsShip(entity, false);
  }
}

OO_TEST(linkedLists) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    // Sorted by the low edge of each entity's sphere on each axis.
    Entity* a = MakeEntity(make_HPvector(10, 30, 20), 1.0f);
    Entity* b = MakeEntity(make_HPvector(20, 10, 30), 1.0f);
    Entity* c = MakeEntity(make_HPvector(30, 20, 10), 1.0f);

    a->updateLinkedLists();  // not in the lists: nothing happens
    OO_CHECK(XNext(a) == nullptr && sUniverse->x_list_start == nullptr);

    a->addToLinkedLists();
    b->addToLinkedLists();
    c->addToLinkedLists();
    sUniverse->n_entities = 3;
    OO_CHECK(sUniverse->x_list_start == a && XNext(a) == b && XNext(b) == c &&
             XNext(c) == nullptr);
    OO_CHECK(XPrevious(a) == nullptr && XPrevious(b) == a && XPrevious(c) == b);
    OO_CHECK(sUniverse->y_list_start == b && YNext(b) == c && YNext(c) == a &&
             YNext(a) == nullptr);
    OO_CHECK(sUniverse->z_list_start == c && ZNext(c) == a && ZNext(a) == b &&
             ZNext(b) == nullptr);

    // Moving b to the far end of x re-sorts it, and the lists still check.
#ifndef NDEBUG
    gDebugFlags = DEBUG_LINKED_LISTS;
    CaptureLog();
#endif
    b->setPosition(make_HPvector(40, 10, 30));
    b->updateLinkedLists();
    OO_CHECK(sUniverse->x_list_start == a && XNext(a) == c && XNext(c) == b &&
             XNext(b) == nullptr);
    OO_CHECK(XPrevious(b) == c && XPrevious(c) == a);
    OO_CHECK(sUniverse->y_list_start == b && YNext(b) == c);

    c->removeFromLinkedLists();
    sUniverse->n_entities = 2;
    OO_CHECK(sUniverse->x_list_start == a && XNext(a) == b &&
             XPrevious(b) == a);
    OO_CHECK(sUniverse->z_list_start == a && ZNext(a) == b);
    OO_CHECK(XNext(c) == nullptr && XPrevious(c) == nullptr);
    c->removeFromLinkedLists();  // removed already: nothing happens
#ifndef NDEBUG
    OO_CHECK(Logged("DEBUG removing entity <Entity 0x") &&
             Logged("from linked lists"));
    OO_CHECK(!Logged("Broken") && !Logged("problem encountered"));
    gDebugFlags = 0;
#endif

    // The head of a list that moves up the list stays the head the universe
    // knows (the universe's own check rebuilds it): pinned as it is.
    a->setPosition(make_HPvector(50, 30, 20));
    a->updateLinkedLists();
    OO_CHECK(sUniverse->x_list_start == a && XNext(b) == a &&
             XPrevious(a) == b && XPrevious(b) == nullptr);

    a->removeFromLinkedLists();
    b->removeFromLinkedLists();
    sUniverse->n_entities = 0;
  }
}

OO_TEST(sessionAndShaderBindings) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(make_HPvector(0, 1, 0), kZeroHPVector);
    UniverseIvar<OOTimeAbsolute>("universal_time") = 100;

    Entity* entity = MakeEntity(make_HPvector(0, 0, 3), 1.0f);
    OO_CHECK(entity->validForAddToUniverse());
    UniverseIvar<NSUInteger>("_sessionID") = 1;  // a new game started since
    OO_CHECK(!entity->validForAddToUniverse());

    UniverseIvar<OOTimeAbsolute>("universal_time") = 104.5;
    OO_CHECK(entity->universalTime() == 104.5f &&
             entity->getSpawnTime() == 100.0f);
    OO_CHECK(entity->timeElapsedSinceSpawn() == 4.5f);
    OO_CHECK(VectorEqual(entity->relativePosition(), make_vector(0, -1, 3)));

    entity->setAtmosphereFogging(
        OOColor::colorWithRed(0.25f, 0.5f, 0.75f, 1.0f).get());
    OO_CHECK(entity->fogUniform().get()->greenComponent() == 0.5f &&
             entity->fogUniform().get()->alphaComponent() == 1.0f);
    entity->setAtmosphereFogging(nullptr);
    OO_CHECK(entity->fogUniform().get() == nullptr);

#ifndef NDEBUG
    OO_CHECK(entity->allTextures().empty());
    OO_CHECK(entity->descriptionForObjDumpBasic() ==
             std::optional<std::string>(
                 "Entity position: (0, 0, 3) scanClass: CLASS_NOT_SET status: "
                 "STATUS_COCKPIT_DISPLAY"));
    OO_CHECK(entity->descriptionForObjDump() ==
             std::optional<std::string>(
                 "Entity position: (0, 0, 3) scanClass: CLASS_NOT_SET status: "
                 "STATUS_COCKPIT_DISPLAY range: 3.16228 (visible: yes)"));
#endif
  }
}

OO_TEST(objCSubclassOverrides) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    TestObjCEntity* entity = static_cast<TestObjCEntity*>(
        oo::MadeEntity(oo::makeRef<TestObjCEntity>()));
    entity->_frustumRadius = 1.5f;
    entity->_session = 3;

    // The root's own members call the virtual members, so they reach the
    // subclass's overrides.
    OO_CHECK(entity->isStellarObject());
    entity->setPosition(make_HPvector(0, 0, 10));
    OO_CHECK(entity->_cameraUpdates == 1);
    OO_CHECK(entity->cameraRangeFront() == 8.5f &&
             entity->cameraRangeBack() == 11.5f);
    entity->setOrientation(kIdentityQuaternion);
    entity->applyRoll(0.5f, 0);
    OO_CHECK(entity->_orientationChanges == 2);
    CaptureLog();
    OO_CHECK(
        !entity->validForAddToUniverse());  // session 3 is not the universe's 0
    OO_CHECK(Logged("from session 3 cannot be added to universe in session 0"));
    entity->_session = 0;
    OO_CHECK(entity->validForAddToUniverse());
    entity->dumpState();
    OO_CHECK(entity->_selfStateDumps == 1);
    OO_CHECK(Logged("State for <TestObjCEntity 0x") && Logged("Mass: 0"));
    entity->setStatus(STATUS_IN_FLIGHT);
    entity->update(0);
    OO_CHECK(entity->_cameraUpdates == 2);
    OO_CHECK(!entity->canCollide());
    entity->drawImmediate(false, false);
    OO_CHECK(entity->_draws == 1);
#ifndef NDEBUG
    entity->_visible = false;
    OO_CHECK(
        entity->descriptionForObjDump()->ends_with("range: 10 (visible: no)"));
    OO_CHECK(entity->descriptionForObjDumpBasic()->starts_with(
        "TestObjCEntity position: "));
#endif
  }
}

OO_TEST(rootDefaultsForSubclassResponsibilities) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    Entity* entity = MakeEntity(kZeroHPVector, 1.0f);
    CaptureLog();
    OO_CHECK(entity->findCollisionRadius() ==
             0);  // logs the subclass responsibility
    entity->drawImmediate(true, false);
    OO_CHECK(sLog.size() == 2);
    entity->warnAboutHostiles();
    OO_CHECK(Logged("***** Entity does nothing in warnAboutHostiles"));
    entity->subEntityReallyDied(nullptr);
    OO_CHECK(Logged("called for non-ship entity"));
  }
}

#ifndef NDEBUG
OO_TEST(liveEntityCount) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    const uint32_t count = gLiveEntityCount;
    const size_t memory = gTotalEntityMemory;
    Entity* entity = nullptr;
    {
      oo::AutoreleaseScope scope;
      entity = oo::RetainEntity(oo::MadeEntity(
          oo::makeRef<TestObjCEntity>()));  // +1, as +alloc's was
    }
    OO_CHECK(gLiveEntityCount == count + 1);
    OO_CHECK(gTotalEntityMemory ==
             memory + oo::EntityObjectSize(entity));  // its object's size
    oo::ReleaseEntity(entity);
    OO_CHECK(gLiveEntityCount == count && gTotalEntityMemory == memory);
  }
}
#endif

// --- The crossing
// ---------------------------------------------------------

OO_TEST(cxxEntityBehindItsFacade) {
#ifndef NDEBUG
  const uint32_t count = gLiveEntityCount;
#endif
  {
    oo::AutoreleaseScope scope;
    // The test's reference goes with the pool (the object's lifetime is the
    // entity's, so the live count below falls when the entity goes).
    const oo::Ref<TestCxxEntity> entity = oo::makeRef<TestCxxEntity>();
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);

    Entity* facade = oo::MadeEntity(entity);
    OO_CHECK(facade == entity.get());
#ifndef NDEBUG
    OO_CHECK(gLiveEntityCount == count + 1);
#endif

    // Messages reach the C++ overrides, and the root's members call them.
    OO_CHECK(facade->isPlanet() && facade->isStellarObject() &&
             !facade->isSun());
    facade->setPosition(make_HPvector(0, 0, 10));
    OO_CHECK(entity->cameraUpdates == 1);
    OO_CHECK(facade->cameraRangeFront() == 8.0f &&
             facade->cameraRangeBack() == 12.0f);
    OO_CHECK(HPvector_equal(entity->getPosition(), make_HPvector(0, 0, 10)));
    OO_CHECK(oo::EntityDescription(facade).starts_with("<TestCxxEntity 0x") &&
             oo::EntityDescription(facade).ends_with(">{test}"));
#ifndef NDEBUG
    OO_CHECK(facade->descriptionForObjDumpBasic() ==
             std::optional<std::string>("TestCxxEntity test"));
#endif

    // The lists link its facade, among Objective-C entities.
    Entity* other = MakeEntity(make_HPvector(20, 0, 0), 1.0f);
    facade->addToLinkedLists();
    other->addToLinkedLists();
    sUniverse->n_entities = 2;
    OO_CHECK(sUniverse->x_list_start == facade && XNext(facade) == other &&
             XPrevious(other) == facade);
    facade->removeFromLinkedLists();
    other->removeFromLinkedLists();
    sUniverse->n_entities = 0;
  }
  // The facade was the entity's identity and owner: gone with the pool.
#ifndef NDEBUG
  OO_CHECK(gLiveEntityCount == count);
#endif
}

// PlayerEntity's -deferredInit sends -init again (through -[ShipEntity
// cxx_initWithKey:...]) to an entity that is already initialised and has a
// script object: the body runs again over the same state, and what it does not
// set stays.
OO_TEST(initSentAgain) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);
    TestObjCEntity* entity = static_cast<TestObjCEntity*>(
        oo::MadeEntity(oo::makeRef<TestObjCEntity>()));
    entity->setPosition(make_HPvector(1, 2, 3));
    entity->setStatus(STATUS_IN_FLIGHT);
    entity->setEnergy(42);
    entity->setUniversalID(9);
    entity->init();  // the body -init ran again
    OO_CHECK(HPvector_equal(entity->getPosition(), kZeroHPVector) &&
             entity->status() == STATUS_COCKPIT_DISPLAY);
    OO_CHECK(entity->getEnergy() == 42 && entity->getUniversalID() == 9);
    entity->setUniversalID(NO_TARGET);
  }
}

// The Objective-C body described the literals @"self" and @"none", which could
// raise and end the dump; the C++ body prints them.
OO_TEST(dumpStateOwnerLines) {
  {
    oo::AutoreleaseScope scope;
    SetUpUniverse();
    SetUpPlayer(kZeroHPVector, kZeroHPVector);
    Entity* entity = MakeEntity(kZeroHPVector, 1.0f);
    CaptureLog();
    entity->dumpState();
    OO_CHECK(Logged("Owner: none") && Logged("Flags: isSunlit") &&
             Logged("Collision Test Filter: 0"));
    entity->setOwner(entity);
    sLog.clear();
    entity->dumpState();
    OO_CHECK(Logged("Owner: self") && Logged("Flags: isSunlit"));
    entity->setOwner(nullptr);
  }
}

OO_TEST_MAIN()
