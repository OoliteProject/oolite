/*	test_ScriptFinalisationRelease.cpp
        Pins two ownership facts on today's code (oo::RefCounted and oo::Ref),
   so that the move to std::shared_ptr (spec 009 US2) can be shown to keep
   them:

        - A native object that a script object refers to is released when the
          engine finalises the script object, and not before: a ship group's JS
          wrapper (the game's own binding, InitOOJSShipGroup) keeps the group
          alive after the C++ reference has gone, and the group is released
          when the wrapper is freed and collected.
        - An entity's disposal runs once, at its last release, after its
          removal from the universe: a waypoint's removal hook
          (wasRemovedFromUniverse()) runs when the universe removes it; the
          universe's dead list keeps it until the update ends and the
          autorelease pool drains; its weak references read it until then;
          and that last release destroys it once, without a second removal.

        The test links the whole game but main (['*']) and uses a Universe that
   was never initialised, a plain player and a bare QuickJS context holding
   only the ShipGroup class, as test_OOWaypointEntity and test_OOJSShipGroup
   do. Run: tests/run.sh unit
*/

#include <string>
#include <vector>

#include <quickjs.h>

#include "OOJSShipGroup.h"
#include "OOShipGroup.h"
#include "OOWaypointEntity.h"
#include "PlayerEntity.h"
#include "Universe.h"
#include "oo_test.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;
extern JSContext* gOOJSMainThreadContext;

class TestPlayer : public PlayerEntity {
 public:
  HPVector viewpointPosition() override { return kZeroHPVector; }
};

namespace {

std::vector<std::string> sLog;  // what the recording waypoint saw, in order

}  // namespace

// A waypoint that logs its removal and its destruction.
class RecordingWaypoint : public OOWaypointEntity {
 public:
  ~RecordingWaypoint() override { sLog.push_back("destroyed"); }
  void wasRemovedFromUniverse() override {
    sLog.push_back("removed");
    OOWaypointEntity::wasRemovedFromUniverse();
  }
};

namespace {

TestPlayer* NewTestPlayer() {
  oo::Ref<TestPlayer> player = oo::makeRef<TestPlayer>();
  {
    oo::AutoreleaseScope scope;
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

Universe* SetUpUniverse() {
  Universe* universe = new Universe();  // never released
  gSharedUniverse = universe;
  static TestPlayer* player = nullptr;
  if (player == nullptr) player = NewTestPlayer();
  gOOPlayer = player;
  return universe;
}

JSContext* sContext = nullptr;

JSContext* Context() {
  if (sContext == nullptr) {
    JSRuntime* runtime = JS_NewRuntime();
    sContext = JS_NewContext(runtime);
    gOOJSMainThreadContext = sContext;
    JSValue global = JS_GetGlobalObject(sContext);
    InitOOJSShipGroup(sContext, global);
    JS_FreeValue(sContext, global);
  }
  return sContext;
}

}  // namespace

OO_TEST(aScriptObjectKeepsItsNativeObjectUntilFinalised) {
  {
    oo::AutoreleaseScope scope;
    JSContext* context = Context();
    oo::WeakRef<OOShipGroup> watched;
    JSValue wrapper = JS_UNDEFINED;
    {
      oo::Ref<OOShipGroup> group =
          OOShipGroup::groupWithName(std::string("finalised"));
      watched = group.get();
      wrapper = group->jsValueInContext(context);
      OO_CHECK(JS_IsObject(wrapper));
    }  // the C++ reference goes; the wrapper's remains
    {
      oo::AutoreleaseScope drained;
    }
    JS_RunGC(JS_GetRuntime(context));
    OO_CHECK(watched.get() != nullptr);  // not before the wrapper is finalised

    JS_FreeValue(context, wrapper);
    JS_RunGC(JS_GetRuntime(context));
    OO_CHECK(watched.get() == nullptr);  // released by the finaliser
  }
}

OO_TEST(anEntityIsDisposedOnceAtItsLastReleaseAfterRemoval) {
  {
    oo::AutoreleaseScope scope;
    Universe* u = SetUpUniverse();
    sLog.clear();
    Entity* waypoint = nullptr;
    {
      oo::AutoreleaseScope made;
      oo::Ref<RecordingWaypoint> part = oo::makeRef<RecordingWaypoint>();
      part->initWithDictionary(
          oo::PList(oo::PList::Dict{{"beaconCode", oo::PList("R")}}));
      waypoint = oo::RetainEntity(oo::MadeEntity(part));
    }
    oo::WeakRef<Entity> watched(waypoint);
    OO_CHECK(u->addEntity(waypoint));
    OO_CHECK(sLog.empty());

    u->removeEntity(waypoint);
    OO_CHECK((sLog == std::vector<std::string>{"removed"}));
    OO_CHECK(watched.get() == waypoint);  // the test's hold keeps it

    oo::ReleaseEntity(waypoint);  // the test's hold; the universe's dead list
                                  // keeps it until the update ends
    OO_CHECK((sLog == std::vector<std::string>{"removed"}));
    OO_CHECK(watched.get() == waypoint);

    {
      oo::AutoreleaseScope frame;
      u->no_update = true;
      u->update(1.0);  // the dead are autoreleased
      OO_CHECK(u->entitiesDeadThisUpdate.empty());
      OO_CHECK((sLog == std::vector<std::string>{"removed"}));
    }  // the pool drains: the last release, and disposal
    OO_CHECK((sLog == std::vector<std::string>{"removed", "destroyed"}));
    OO_CHECK(watched.get() == nullptr);
  }
}

OO_TEST_MAIN()
