/*	test_EntityScriptEvents.cpp
        Unit tests for how the player, the ship and the station send the script
   events that upstream #780 (engine-neutral JavaScript names outside the
   scripting layer) moved from the raw-value macros (ShipScriptEventNoCx() with
   OOJSSTR(), ShipScriptEvent() with numbers) to the ship's own
   doScriptEvent(): -doScriptEvent:withArgument: and
   -doScriptEvent:withArgument:andArgument: in Objective-C, the
   doScriptEvent(message, arguments) and doScriptEvent(message) members here.

        As test_PlayerEntity's, the entities need the game graph, so the test
   links the whole game but main (['*']) and uses a Universe that was never
   initialised (and answers no descriptions) and an empty JavaScript context.
   Each entity is a subclass that records the events it is sent through those
   members (the cases see what the game's scripts would be sent) and stands in
   for the set-up that needs the game's data. Run: bash meson test -C
   build/meson_test test_EntityScriptEvents
*/

#include <optional>
#include <string>
#include <vector>

#include "OOJSPropID.h"
#include "PlayerEntity.h"
#include "ShipEntity.h"
#include "StationEntity.h"
#include "Universe.h"
#include "oo_test.hpp"
#include "EntityManualRefs.h"  // the tests' manual entity references (T095)

// The player's system ids are private: the test sets them through this friend.
struct PlayerEntityTestAccess {
  static OOSystemID& system_id(PlayerEntity* player) {
    return player->system_id;
  }
  static OOSystemID& target_system_id(PlayerEntity* player) {
    return player->target_system_id;
  }
  static NSPoint& galaxy_coordinates(PlayerEntity* player) {
    return player->galaxy_coordinates;
  }
  static std::optional<std::string>& save_path(PlayerEntity* player) {
    return player->save_path;
  }
  static OOAlertCondition& lastScriptAlertCondition(PlayerEntity* player) {
    return player->lastScriptAlertCondition;
  }
};

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

extern PlayerEntity* gOOPlayer;
extern Universe* gSharedUniverse;
extern JSContext* gOOJSMainThreadContext;

// A universe that was never initialised and has no descriptions (the game's
// own exits when it has none to look a message up in).
class TestUniverse : public Universe {
 public:
  const oo::PList* descriptions() override { return &_descriptions; }
  std::optional<std::string> descriptionForKey(
      const std::string& /*key*/) override {
    return std::nullopt;
  }

 private:
  oo::PList _descriptions = oo::PList(oo::PList::Dict{});
};

namespace {

// An event an entity was sent: its name and its arguments.
struct Event {
  OOJSPropID message;
  std::vector<oo::PList> arguments;
};
std::vector<Event> sEvents;

// The events named message, in the order they were sent.
std::vector<Event> EventsNamed(OOJSPropID message) {
  std::vector<Event> result;
  for (const Event& event : sEvents)
    if (event.message == message) result.push_back(event);
  return result;
}

void SetUp() {
  static Universe* universe = nullptr;
  if (universe == nullptr) {
    universe = new TestUniverse();  // never released
  }
  gSharedUniverse = universe;
  gOOPlayer = nullptr;  // making the player expects to make the only one
  // The ship's -dealloc sends its (absent) scripts entityDestroyed on the main
  // thread's context, so there is one, with nothing in it.
  if (gOOJSMainThreadContext == nullptr)
    gOOJSMainThreadContext = JS_NewContext(JS_NewRuntime());
  sEvents.clear();
}

}  // namespace

// A player whose set-up from shipdata, session set-up and controls do nothing
// (those need the game's data), whose events are recorded, whose jump needs
// more fuel than it has, and whose save data cannot be made (so a save stops
// after its event, with the exception a failed save raises).
class EventPlayer : public PlayerEntity {
 public:
  using PlayerEntity::doScriptEvent;

  bool setUpShipFromDictionary(const oo::PList& /*dict*/) override {
    return true;
  }
  bool setUpAndConfirmOK(bool /*stopOnError*/) override { return true; }
  void initControls() override {}

  void doScriptEvent(OOJSPropID message,
                     const std::vector<oo::PList>& arguments) override {
    sEvents.push_back({message, arguments});
  }

  OOFuelQuantity fuelRequiredForJump() override { return 5; }
  oo::PList commanderDataDictionary() override { return oo::PList(); }
};

// A ship whose argument-less events are recorded.
class EventShip : public ShipEntity {
 public:
  using ShipEntity::doScriptEvent;

  bool setUpShipFromDictionary(const oo::PList& /*dict*/) override {
    return true;
  }
  void doScriptEvent(OOJSPropID message) override {
    sEvents.push_back({message, {}});
  }
};

// A station whose events with arguments are recorded, and which makes no
// virtual dock (that is a shipdata entry).
class EventStation : public StationEntity {
 public:
  using StationEntity::doScriptEvent;

  bool setUpOneStandardSubentity(const oo::PList& /*subentDict*/,
                                 bool /*asTurret*/) override {
    return false;
  }
  void doScriptEvent(OOJSPropID message,
                     const std::vector<oo::PList>& arguments) override {
    sEvents.push_back({message, arguments});
  }
};

namespace {

// A C++ entity under its object, as the game makes one, retained (+1).
template <class T>
T* NewTestEntity() {
  std::shared_ptr<T> entity = oo::makeShared<T>();
  {
    oo::AutoreleaseScope scope;
    oo::RetainEntity(oo::MadeEntity(entity));
  }
  return entity.get();
}

// A string value's text; a value that is not a string never matches.
std::string StringOf(const oo::PList& value) {
  const std::string* text = value.getIf<std::string>();
  return text != nullptr ? *text : std::string("<not a string>");
}

}  // namespace

// Upstream #780: saving a game sends playerWillSaveGame through the player's
// doScriptEvent() with one argument, the kind of save ("STANDARD_SAVE"), as
// -doScriptEvent:withArgument: does; the event comes before the save is
// written.
OO_TEST(saveSendsPlayerWillSaveGame) {
  {
    SetUp();
    EventPlayer* player = NewTestEntity<EventPlayer>();
    bool raised = false;
    try {
      player->nativeSavePlayer("unit-test-commander");
    } catch (...) {
      raised = true;  // the save data could not be made
    }
    OO_CHECK(raised);
    std::vector<Event> events = EventsNamed(OOJSID("playerWillSaveGame"));
    OO_CHECK_EQ(events.size(), (size_t)1);
    if (events.size() == 1) {
      OO_CHECK_EQ(events[0].arguments.size(), (size_t)1);
      if (events[0].arguments.size() == 1)
        OO_CHECK_EQ(StringOf(events[0].arguments[0]),
                    std::string("STANDARD_SAVE"));
    }
    gOOPlayer = nullptr;
    oo::ReleaseEntity(player);
  }
}

// Upstream #780: a witchspace countdown that fails its checklist (here, not
// enough fuel) sends playerJumpFailed with the reason as its one argument
// through the player's doScriptEvent(), and drops back to flight.
OO_TEST(failedJumpSendsPlayerJumpFailed) {
  {
    SetUp();
    EventPlayer* player = NewTestEntity<EventPlayer>();
    // A jump to another system (the universe that was never initialised has
    // no system data, so it is no distance away), with no fuel: the countdown
    // fails "insufficient fuel".
    PlayerEntityTestAccess::system_id(player) = 7;
    PlayerEntityTestAccess::target_system_id(player) = 8;
    player->setStatus(OOEntityStatus::kWitchspaceCountdown);
    player->setFuel(0);
    OO_CHECK(!player->witchJumpChecklist(false));
    OO_CHECK(player->status() == OOEntityStatus::kInFlight);
    std::vector<Event> events = EventsNamed(OOJSID("playerJumpFailed"));
    OO_CHECK_EQ(events.size(), (size_t)1);
    if (events.size() == 1) {
      OO_CHECK_EQ(events[0].arguments.size(), (size_t)1);
      if (events[0].arguments.size() == 1)
        OO_CHECK_EQ(StringOf(events[0].arguments[0]),
                    std::string("insufficient fuel"));
    }
    gOOPlayer = nullptr;
    oo::ReleaseEntity(player);
  }
}

// The one playerWillSaveGame event a save sent, and its kind of save.
std::string SaveKindSent() {
  std::vector<Event> events = EventsNamed(OOJSID("playerWillSaveGame"));
  if (events.size() != 1 || events[0].arguments.size() != 1)
    return "<not one event with one argument>";
  return StringOf(events[0].arguments[0]);
}

// Upstream #780: an autosave of a commander that was saved before sends
// playerWillSaveGame with "AUTO_SAVE" (a failed autosave is not reported, so
// nothing is raised).
OO_TEST(autosaveSendsPlayerWillSaveGame) {
  {
    SetUp();
    EventPlayer* player = NewTestEntity<EventPlayer>();
    player->setLastsaveName(std::string("unit-test-commander"));
    player->autosavePlayer();
    OO_CHECK_EQ(SaveKindSent(), std::string("AUTO_SAVE"));
    gOOPlayer = nullptr;
    oo::ReleaseEntity(player);
  }
}

// Upstream #780: a quicksave to the current save file sends
// playerWillSaveGame with "QUICK_SAVE" before it writes the file.
OO_TEST(quicksaveSendsPlayerWillSaveGame) {
  {
    SetUp();
    EventPlayer* player = NewTestEntity<EventPlayer>();
    PlayerEntityTestAccess::save_path(player) =
        std::string("unit-test-quicksave.oolite-save");
    bool raised = false;
    try {
      player->quicksavePlayer();
    } catch (...) {
      raised = true;  // the save data could not be made
    }
    OO_CHECK(raised);
    OO_CHECK_EQ(SaveKindSent(), std::string("QUICK_SAVE"));
    gOOPlayer = nullptr;
    oo::ReleaseEntity(player);
  }
}

// Upstream #780: a countdown to a system beyond the drive's range fails with
// playerJumpFailed "too far".
OO_TEST(tooFarJumpSendsPlayerJumpFailed) {
  {
    SetUp();
    EventPlayer* player = NewTestEntity<EventPlayer>();
    PlayerEntityTestAccess::system_id(player) = 7;
    PlayerEntityTestAccess::target_system_id(player) = 8;
    // The target has no data (no coordinates, the origin): the player is far
    // from it.
    PlayerEntityTestAccess::galaxy_coordinates(player) = NSMakePoint(200, 200);
    player->setStatus(OOEntityStatus::kWitchspaceCountdown);
    player->setFuel(70);
    OO_CHECK(!player->witchJumpChecklist(false));
    OO_CHECK(player->status() == OOEntityStatus::kInFlight);
    std::vector<Event> events = EventsNamed(OOJSID("playerJumpFailed"));
    OO_CHECK_EQ(events.size(), (size_t)1);
    if (events.size() == 1 && events[0].arguments.size() == 1)
      OO_CHECK_EQ(StringOf(events[0].arguments[0]), std::string("too far"));
    gOOPlayer = nullptr;
    oo::ReleaseEntity(player);
  }
}

// Upstream #780: the player's alert condition changing sends
// alertConditionChanged with the new and the old condition, as
// -doScriptEvent:withArgument:andArgument: does; no change, no event.
OO_TEST(playerAlertChangeSendsAlertConditionChanged) {
  {
    SetUp();
    EventPlayer* player = NewTestEntity<EventPlayer>();
    const OOAlertCondition stale = (OOAlertCondition)99;
    PlayerEntityTestAccess::lastScriptAlertCondition(player) = stale;
    player->updateAlertCondition();
    const OOAlertCondition now =
        PlayerEntityTestAccess::lastScriptAlertCondition(player);
    OO_CHECK(now != stale);
    std::vector<Event> events = EventsNamed(OOJSID("alertConditionChanged"));
    OO_CHECK_EQ(events.size(), (size_t)1);
    if (events.size() == 1 && events[0].arguments.size() == 2) {
      OO_CHECK(events[0].arguments[0] == oo::PList((int)now));
      OO_CHECK(events[0].arguments[1] == oo::PList((int)stale));
    } else {
      OO_CHECK(false);  // two arguments, the new and the old condition
    }
    player->updateAlertCondition();
    OO_CHECK_EQ(EventsNamed(OOJSID("alertConditionChanged")).size(), (size_t)1);
    gOOPlayer = nullptr;
    oo::ReleaseEntity(player);
  }
}

// Upstream #780: a station whose alert level changes, signalling its script,
// sends alertConditionChanged through doScriptEvent() with the new and the old
// level, as -doScriptEvent:withArgument:andArgument: does.
OO_TEST(stationAlertChangeSendsAlertConditionChanged) {
  {
    SetUp();
    EventStation* station = NewTestEntity<EventStation>();
    station->setAlertLevel(OOStationAlertLevel::kGreen, false);  // no event
    OO_CHECK(sEvents.empty());
    station->setAlertLevel(OOStationAlertLevel::kRed, true);
    std::vector<Event> events = EventsNamed(OOJSID("alertConditionChanged"));
    OO_CHECK_EQ(events.size(), (size_t)1);
    if (events.size() == 1 && events[0].arguments.size() == 2) {
      OO_CHECK(events[0].arguments[0] ==
               oo::PList((int)OOStationAlertLevel::kRed));
      OO_CHECK(events[0].arguments[1] ==
               oo::PList((int)OOStationAlertLevel::kGreen));
    } else {
      OO_CHECK(false);  // two arguments, the new and the old level
    }
    // No change, no event.
    station->setAlertLevel(OOStationAlertLevel::kRed, true);
    OO_CHECK_EQ(EventsNamed(OOJSID("alertConditionChanged")).size(), (size_t)1);
    oo::ReleaseEntity(station);
  }
}

// Upstream #780: a ship going away sends entityDestroyed through its own
// doScriptEvent(message), as [self doScriptEvent:OOJSID("entityDestroyed")]
// does.
OO_TEST(shipDeallocSendsEntityDestroyed) {
  {
    SetUp();
    EventShip* ship = NewTestEntity<EventShip>();
    OO_CHECK(EventsNamed(OOJSID("entityDestroyed")).empty());
    oo::ReleaseEntity(ship);
    OO_CHECK_EQ(EventsNamed(OOJSID("entityDestroyed")).size(), (size_t)1);
  }
}

OO_TEST_MAIN()
