/*	test_OOEntityCalledByName.mm

        Unit tests for the entities' by-name C++ table
   (src/Core/Entities/OOEntityCalledByNameTable.h, generated;
   OOEntityCalledByName.mm). The table is
   the source: its own checks stay, and the calls are compared with the C++
   members the rows' bodies call. A name outside the by-name table is answered
   without the entity's object (OOEntityObjectNamesTable.h), and each kind of
   name is answered and logged as OOCallByName answers and logs it, but for the
   root-class and lifetime methods, which are not called. The test links the
   whole game but main (['*']). Run: tests/run.sh unit
   test_OOEntityCalledByName
*/

#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "DockEntity.h"
#include "Entity.h"
#include "OOCallByName.h"
#include "OOEntityCalledByName.h"
#include "OOVisualEffectEntity.h"
#include "OOWaypointEntity.h"
#include "PlayerEntity.h"
#include "ProxyPlayerEntity.h"
#include "ShipEntity.h"
#include "StationEntity.h"
#include "oo_test.hpp"
#include "oofnd/Log.hpp"

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

namespace {

// One entity of each kind the name sets name, and one they do not (a waypoint),
// each under the root's facade; the facades live for the test.
struct Sample {
  const char* kind;
  Entity* entity;
  Entity* object;
};

template <class T>
Sample Make(const char* kind) {
  oo::Ref<T> entity = oo::makeRef<T>();
  Entity* object = oo::RetainEntity(oo::MadeEntity(entity));
  return Sample{kind, entity.get(), object};
}

const std::vector<Sample>& Samples() {
  static const std::vector<Sample> samples = [] {
    std::vector<Sample> result;
    {
      result.push_back(Make<ShipEntity>("ship"));
      result.push_back(Make<StationEntity>("station"));
      result.push_back(Make<DockEntity>("dock"));
      result.push_back(Make<PlayerEntity>("player"));
      result.push_back(Make<ProxyPlayerEntity>("proxy"));
      result.push_back(Make<OOVisualEffectEntity>("effect"));
      result.push_back(Make<OOWaypointEntity>("waypoint"));
    }
    return result;
  }();
  return samples;
}

}  // namespace

// Each row has a result and argument types (OOCallByName reads these); the
// table's own checks stay.
OO_TEST(rowsAreTheFacadesMethodsWithTheirTypes) {
  std::set<std::string> names;
  for (const OOEntityByNameRow& row : oo::EntityByNameRows()) {
    OO_CHECK(names.insert(row.name).second);  // no name twice
    OO_CHECK(oo::EntityByNameRowNamed(row.name) == &row);
  }
  OO_CHECK(names.size() > 900);  // the five categories' 968 methods
  OO_CHECK(oo::EntityByNameRowNamed("noSuchSelector") == nullptr);
}

// oo::EntityRespondsToName answers each row exactly as the row applies.
OO_TEST(appliesToIsTheFacadesAnswer) {
  {
    std::string different;
    for (const OOEntityByNameRow& row : oo::EntityByNameRows()) {
      for (const Sample& sample : Samples()) {
        if (oo::EntityRespondsToName(sample.entity, row.name) !=
            oo::EntityByNameRowApplies(row, sample.entity)) {
          different += std::string(" ") + row.name + "/" + sample.kind;
        }
      }
    }
    OO_CHECK_EQ(different, std::string());
  }
}

// The log the calls below write.
namespace {

std::vector<std::string> gLog;

void Capture(std::string_view line) { gLog.emplace_back(line); }

int LogLinesContaining(std::string_view text) {
  int count = 0;
  for (const std::string& line : gLog) {
    if (line.find(text) != std::string::npos) count++;
  }
  return count;
}

}  // namespace

// A name outside the by-name table is answered without the object: (a) a
// method whose signature the call cannot use is answered and logged; (b) a
// root-class or lifetime method is answered and logged, never called; a facade
// row's method is its body; (c) any other name does not respond. The texts are
// OOCallByName's, for the class of a C++ entity's object (Entity).
OO_TEST(objectNamesAnsweredWithoutTheObject) {
  {
    oo::log::logger().setInitialized(true);
    oo::log::logger().setSink(&Capture);
    const Sample& ship = Samples()[0];
    const Sample& waypoint = Samples()[6];

    // (a) the facade's own method with an argument, and a facade row's struct
    // result
    gLog.clear();
    OO_CHECK(oo::EntityRespondsToName(ship.entity, "setOwner:"));
    OO_CHECK(oo::CallEntityByName(ship.entity, "setOwner:", std::string("x"))
                 .isNull());
    OO_CHECK(oo::CallEntityByName(ship.entity, "position").isNull());
    OO_CHECK_EQ(
        LogLinesContaining("-[Entity setOwner:] has no signature a by-name "
                           "call can use (type encoding v24@0:8@16)."),
        1);
    OO_CHECK_EQ(
        LogLinesContaining("-[Entity position] has no signature a by-name call "
                           "can use (type encoding {HPVector=ddd}16@0:8)."),
        1);

    // (b) answered, logged, never called: the entity is not released
    gLog.clear();
    const auto references = ship.entity->retainCount();
    for (const char* name : {"release", "autorelease", "dealloc", "retain",
                             "init", "weakRetain", "hash"}) {
      OO_CHECK(oo::EntityRespondsToName(ship.entity, name));
      OO_CHECK(oo::CallEntityByName(ship.entity, name).isNull());
    }
    OO_CHECK_EQ(ship.entity->retainCount(), references);
    OO_CHECK_EQ(
        LogLinesContaining("-[Entity release] has no signature a by-name call "
                           "can use (type encoding Vv16@0:8)."),
        1);
    OO_CHECK_EQ(
        LogLinesContaining(
            "-[Entity dealloc] has no signature a by-name call can use"),
        1);
    OO_CHECK_EQ(LogLinesContaining("has no signature a by-name call can use"),
                7);

    // a facade row's method with no argument is its body (nothing logged); with
    // an argument it is logged
    gLog.clear();
    OO_CHECK(oo::CallEntityByName(ship.entity, "isShip").isNull());
    OO_CHECK(oo::CallEntityByName(waypoint.entity, "isBeacon").isNull());
    OO_CHECK(gLog.empty());
    OO_CHECK(
        oo::CallEntityByName(ship.entity, "isShip", std::string("x")).isNull());
    OO_CHECK_EQ(
        LogLinesContaining("-[Entity isShip] has no signature a by-name call "
                           "can use (type encoding c16@0:8)."),
        1);
    OO_CHECK_EQ(gLog.size(), size_t(1));

    // (c) any other name, a beacon's name for an entity that is no beacon's
    // part, and the JS glue the facade no longer answered: does not respond
    gLog.clear();
    OO_CHECK(!oo::EntityRespondsToName(ship.entity, "noSuchMethod"));
    OO_CHECK(oo::CallEntityByName(ship.entity, "noSuchMethod").isNull());
    OO_CHECK(oo::CallEntityByName(ship.entity, "deleteJSSelf").isNull());
    OO_CHECK(oo::CallEntityByName(waypoint.entity, "isHulk").isNull());
    OO_CHECK_EQ(LogLinesContaining("Entity does not respond to noSuchMethod."),
                1);
    OO_CHECK_EQ(LogLinesContaining("Entity does not respond to deleteJSSelf."),
                1);
    OO_CHECK_EQ(LogLinesContaining("Entity does not respond to isHulk."), 1);
    oo::log::logger().setSink(nullptr);
  }
}

// The call answers what the player's C++ member answers, which the row's body
// calls.
OO_TEST(callAnswersAsTheSelectorPath) {
  {
    const Sample& player = Samples()[3];
    const Sample& ship = Samples()[0];
    PlayerEntity* playerPart = dynamic_cast<PlayerEntity*>(player.entity);
    OO_CHECK(playerPart != nullptr);
    OO_CHECK(playerPart != nullptr &&
             oo::CallEntityByName(player.entity, "commanderName_string") ==
                 playerPart->commanderName_string());
    OO_CHECK(playerPart != nullptr &&
             oo::CallEntityByName(player.entity, "credits_number") ==
                 playerPart->credits_number());
    for (const char* name : {"commanderName_string", "credits_number"}) {
      // not a ship's: nothing, as the facade's path answered (it logs that the
      // object does not respond)
      OO_CHECK(oo::CallEntityByName(ship.entity, name).isNull());
    }
    OO_CHECK(!oo::CallEntityByName(player.entity, "credits_number").isNull());
    OO_CHECK(!oo::EntityRespondsToName(nullptr, "credits_number"));
    OO_CHECK(oo::CallEntityByName(nullptr, "credits_number").isNull());
  }
}

// A method with no argument has a typed adaptor, and its result is read by
// type: an integer, a float, a vector, an object.
OO_TEST(typedCallAnswersAsTheMethod) {
  {
    for (const OOEntityByNameRow& row : oo::EntityByNameRows()) {
      OO_CHECK((row.typed != nullptr) ==
               (row.argument == OOEntityByNameArgument::None));
    }

    // Each result is compared with the ship's C++ member the method's body
    // called.
    const Sample& ship = Samples()[0];
    ShipEntity* shipPart = dynamic_cast<ShipEntity*>(ship.entity);
    OO_CHECK(shipPart != nullptr);
    if (shipPart == nullptr) return;
    const std::pair<const char*, bool> flags[] = {
        {"isFrangible", shipPart->getIsFrangible()},
        {"isHulk", shipPart->getIsHulk()},
        {"isCloaked", shipPart->isCloaked()},
    };
    for (const auto& [name, expected] : flags) {
      OOEntityByNameValue value;
      OO_CHECK(oo::CallEntityByNameTyped(ship.entity, name, value));
      OO_CHECK_EQ(value.integer, static_cast<long long>(expected));
    }
    const std::pair<const char*, float> reals[] = {
        {"maxThrust", shipPart->maxThrust()},
        {"heatInsulation", shipPart->heatInsulation()}};
    for (const auto& [name, expected] : reals) {
      OOEntityByNameValue value;
      OO_CHECK(oo::CallEntityByNameTyped(ship.entity, name, value));
      OO_CHECK_EQ(value.real, static_cast<double>(expected));
    }
    {
      OOEntityByNameValue value;
      OO_CHECK(oo::CallEntityByNameTyped(ship.entity, "forwardVector", value));
      const Vector v = shipPart->forwardVector();
      OO_CHECK(value.vector.x == v.x && value.vector.y == v.y &&
               value.vector.z == v.z);
    }
    {
      OOEntityByNameValue value;
      OO_CHECK(
          oo::CallEntityByNameTyped(ship.entity, "primaryAggressor", value));
      OO_CHECK(value.entity == shipPart->primaryAggressor());  // the C++ entity
    }

    // Not tabled, not the entity's, or taking an argument: nothing is called.
    OOEntityByNameValue value;
    OO_CHECK(!oo::CallEntityByNameTyped(ship.entity, "noSuchSelector", value));
    OO_CHECK(!oo::CallEntityByNameTyped(Samples()[6].entity, "isHulk", value));
    OO_CHECK(!oo::CallEntityByNameTyped(Samples()[3].entity,
                                        "awardCredits:", value));
  }
}

OO_TEST_MAIN()
