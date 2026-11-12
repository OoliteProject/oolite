/*
OOJSStation.m (QuickJS-ng)

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

 */

#include "OOJSStation.h"

#include <cstddef>
#include <cstdint>
#include <format>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "EntityOOJavaScriptExtensions.h"
#include "GameController.h"
#include "OOCommodities.h"
#include "OOCommodityMarket.h"
#include "OOConstToString.h"
#include "OODescription.h"
#include "OOEquipmentType.h"
#include "OOJSEntity.h"
#include "OOJSInterfaceDefinition.h"
#include "OOJSPlayer.h"
#include "OOJSShip.h"
#include "OOJavaScriptEngine.h"
#include "OOShipRegistry.h"
#include "PlayerEntityContracts.h"
#include "StationEntity.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOException.h"

/*
        Station is registered as a Ship subclass and object converter with
        sStationClassID, the class its instances are made with.
*/

static JSClassID sStationClassID;

static bool JSStationGetStationEntity(JSContext* context,
                                      JSValueConst stationObj,
                                      StationEntity** outEntity);

static JSValue StationGetProperty(OOJS_GETTER_ARGS);
static JSValue StationSetProperty(OOJS_SETTER_ARGS);

static JSValue StationAbortAllDockings(OOJS_NATIVE_ARGS);
static JSValue StationAbortDockingForShip(OOJS_NATIVE_ARGS);
static JSValue StationCanDockShip(OOJS_NATIVE_ARGS);
static JSValue StationDockPlayer(OOJS_NATIVE_ARGS);
static JSValue StationIncreaseAlertLevel(OOJS_NATIVE_ARGS);
static JSValue StationDecreaseAlertLevel(OOJS_NATIVE_ARGS);
static JSValue StationLaunchShipWithRole(OOJS_NATIVE_ARGS);
static JSValue StationLaunchDefenseShip(OOJS_NATIVE_ARGS);
static JSValue StationLaunchEscort(OOJS_NATIVE_ARGS);
static JSValue StationLaunchScavenger(OOJS_NATIVE_ARGS);
static JSValue StationLaunchMiner(OOJS_NATIVE_ARGS);
static JSValue StationLaunchPirateShip(OOJS_NATIVE_ARGS);
static JSValue StationLaunchShuttle(OOJS_NATIVE_ARGS);
static JSValue StationLaunchPatrol(OOJS_NATIVE_ARGS);
static JSValue StationLaunchPolice(OOJS_NATIVE_ARGS);
static JSValue StationSetInterface(OOJS_NATIVE_ARGS);
static JSValue StationSetMarketPrice(OOJS_NATIVE_ARGS);
static JSValue StationSetMarketQuantity(OOJS_NATIVE_ARGS);
static JSValue StationAddShipToShipyard(OOJS_NATIVE_ARGS);
static JSValue StationRemoveShipFromShipyard(OOJS_NATIVE_ARGS);

static JSClassDef sStationClass = {
    .class_name = "Station",
    .finalizer = OOJSCxxObjectWrapperFinalize,
};

enum {
  // Property IDs
  kStation_alertCondition,
  kStation_allegiance,
  kStation_allowsAutoDocking,
  kStation_allowsFastDocking,
  kStation_breakPattern,
  kStation_dockedContractors,  // miners and scavengers.
  kStation_dockedDefenders,
  kStation_dockedPolice,
  kStation_equipmentPriceFactor,
  kStation_equivalentTechLevel,
  kStation_hasNPCTraffic,
  kStation_hasShipyard,
  kStation_isMainStation,  // Is [UNIVERSE station], boolean, read-only
  kStation_market,
  kStation_requiresDockingClearance,
  kStation_roll,
  kStation_suppressArrivalReports,
  kStation_shipyard,
};

static const JSCFunctionListEntry sStationProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RW("alertCondition", StationGetProperty, StationSetProperty,
                     kStation_alertCondition),
    OOJS_PROPERTY_RW("allegiance", StationGetProperty, StationSetProperty,
                     kStation_allegiance),
    OOJS_PROPERTY_RW("allowsAutoDocking", StationGetProperty,
                     StationSetProperty, kStation_allowsAutoDocking),
    OOJS_PROPERTY_RW("allowsFastDocking", StationGetProperty,
                     StationSetProperty, kStation_allowsFastDocking),
    OOJS_PROPERTY_RW("breakPattern", StationGetProperty, StationSetProperty,
                     kStation_breakPattern),
    OOJS_PROPERTY_RO("dockedContractors", StationGetProperty,
                     kStation_dockedContractors),
    OOJS_PROPERTY_RO("dockedDefenders", StationGetProperty,
                     kStation_dockedDefenders),
    OOJS_PROPERTY_RO("dockedPolice", StationGetProperty, kStation_dockedPolice),
    OOJS_PROPERTY_RO("equipmentPriceFactor", StationGetProperty,
                     kStation_equipmentPriceFactor),
    OOJS_PROPERTY_RO("equivalentTechLevel", StationGetProperty,
                     kStation_equivalentTechLevel),
    OOJS_PROPERTY_RW("hasNPCTraffic", StationGetProperty, StationSetProperty,
                     kStation_hasNPCTraffic),
    OOJS_PROPERTY_RO("hasShipyard", StationGetProperty, kStation_hasShipyard),
    OOJS_PROPERTY_RO("isMainStation", StationGetProperty,
                     kStation_isMainStation),
    OOJS_PROPERTY_RO("market", StationGetProperty, kStation_market),
    OOJS_PROPERTY_RW("requiresDockingClearance", StationGetProperty,
                     StationSetProperty, kStation_requiresDockingClearance),
    OOJS_PROPERTY_RW("roll", StationGetProperty, StationSetProperty,
                     kStation_roll),
    OOJS_PROPERTY_RW("suppressArrivalReports", StationGetProperty,
                     StationSetProperty, kStation_suppressArrivalReports),
    OOJS_PROPERTY_RO("shipyard", StationGetProperty, kStation_shipyard),
};

static const JSCFunctionListEntry sStationMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("abortAllDockings", 0, StationAbortAllDockings),
    JS_CFUNC_DEF("abortDockingForShip", 1, StationAbortDockingForShip),
    JS_CFUNC_DEF("canDockShip", 1, StationCanDockShip),
    JS_CFUNC_DEF("dockPlayer", 0, StationDockPlayer),
    JS_CFUNC_DEF("increaseAlertLevel", 0, StationIncreaseAlertLevel),
    JS_CFUNC_DEF("decreaseAlertLevel", 0, StationDecreaseAlertLevel),
    JS_CFUNC_DEF("launchDefenseShip", 0, StationLaunchDefenseShip),
    JS_CFUNC_DEF("launchEscort", 0, StationLaunchEscort),
    JS_CFUNC_DEF("launchMiner", 0, StationLaunchMiner),
    JS_CFUNC_DEF("launchPatrol", 0, StationLaunchPatrol),
    JS_CFUNC_DEF("launchPirateShip", 0, StationLaunchPirateShip),
    JS_CFUNC_DEF("launchPolice", 0, StationLaunchPolice),
    JS_CFUNC_DEF("launchScavenger", 0, StationLaunchScavenger),
    JS_CFUNC_DEF("launchShipWithRole", 1, StationLaunchShipWithRole),
    JS_CFUNC_DEF("launchShuttle", 0, StationLaunchShuttle),
    JS_CFUNC_DEF("setInterface", 0, StationSetInterface),
    JS_CFUNC_DEF("setMarketPrice", 2, StationSetMarketPrice),
    JS_CFUNC_DEF("setMarketQuantity", 2, StationSetMarketQuantity),
    JS_CFUNC_DEF("addShipToShipyard", 1, StationAddShipToShipyard),
    JS_CFUNC_DEF("removeShipFromShipyard", 1, StationRemoveShipFromShipyard),
};

void InitOOJSStation(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sStationClassID, &sStationClass);

  JSValue parentPrototype = JS_GetClassProto(context, JSShipClassID());
  OOCAssert(JS_IsObject(parentPrototype),
            "Ship must be initialized before Station.");
  OOJSInitClass(context, global, sStationClassID, parentPrototype,
                OOJSUnconstructableConstruct, 0, sStationProperties,
                OOJS_COUNT(sStationProperties), sStationMethods,
                OOJS_COUNT(sStationMethods), nullptr, 0);
  JS_FreeValue(context, parentPrototype);

  OOJSRegisterObjectConverter(sStationClassID, OOJSEntityObjectConverter);
  OOJSRegisterSubclass(sStationClassID, JSShipClassID());
}

JSClassID JSStationClassID() { return sStationClassID; }

/*	As in the SpiderMonkey version, these return false without an exception
   for stale references (nil entity) and for entities of the wrong native class;
        OOJSEntityGetEntity() throws if the object is not an Entity at all.
*/
static bool JSStationGetStationEntity(JSContext* context,
                                      JSValueConst stationObj,
                                      StationEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, stationObj, &entity);
  if (!result) return false;

  // A station's object is a ship's: its C++ part says it is a station.
  StationEntity* station = oo::ToStation(entity);
  if (station == nullptr) return false;

  *outEntity = station;
  return true;

  OOJS_PROFILE_EXIT
}

static bool JSStationGetShipEntity(JSContext* context, JSValueConst shipObj,
                                   ShipEntity** outEntity) {
  OOJS_PROFILE_ENTER

  bool result;
  Entity* entity = nullptr;  // the slot holds the C++ entity

  if (outEntity == nullptr) return false;
  *outEntity = nullptr;

  result = OOJSEntityGetEntity(context, shipObj, &entity);
  if (!result) return false;

  if (!(oo::ToShip(entity) != nullptr)) return false;

  *outEntity = oo::ToShip(entity);
  return true;

  OOJS_PROFILE_EXIT
}

/*	The SpiderMonkey methods treated a failed lookup of this as a no-op (a
        stale reference). If the lookup failed because this is not an Entity, an
        error is pending, and QuickJS natives must not return normally with an
        exception pending.
*/
#define GET_THIS_STATION(THISENT)                                     \
  do {                                                                \
    if (!JSStationGetStationEntity(context, OOJS_THIS, &(THISENT))) { \
      if (JS_HasException(context)) return JS_EXCEPTION;              \
      OOJS_RETURN_VOID; /* stale reference, no-op */                  \
    }                                                                 \
  } while (0)

// The bodies of StationEntity (OOJavaScriptExtensions), which StationEntity's
// jsClassName calls.
std::optional<std::string> OOJSStationJSClassName() {
  return std::string("Station");
}

static JSValue StationGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* entity = nullptr;

  if (!JSStationGetStationEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) {
    return JS_UNDEFINED;
  }

  switch (magic) {
    case kStation_isMainStation:
      return OOJSValueFromBOOL(
          entity == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr));

    case kStation_hasNPCTraffic:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->getHasNPCTraffic() : false));

    case kStation_hasShipyard:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->hasShipyard() : false));

    case kStation_alertCondition:
      return JS_NewInt32(
          context, entity != nullptr
                       ? static_cast<std::int32_t>(entity->getAlertLevel())
                       : 0);  // 0: a message to nil's answer

    case kStation_allegiance: {
      const std::optional<std::string> allegiance =
          (entity != nullptr ? entity->getAllegiance()
                             : std::optional<std::string>());
      return OOJSValueFromPList(context, allegiance.has_value()
                                             ? oo::PList(*allegiance)
                                             : oo::PList());  // null for none
    }

    case kStation_requiresDockingClearance:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->getRequiresDockingClearance() : false));

    case kStation_roll:
      // same as in ship definition, but this time read/write below
      return JS_NewNumber(
          context,
          (entity != nullptr ? entity->ShipEntity::getFlightRoll()
                             : 0.0f));  // qualified: the final overrider, so
                                        // the binding test stands in for it

    case kStation_allowsFastDocking:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->getAllowsFastDocking() : false));

    case kStation_allowsAutoDocking:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->getAllowsAutoDocking() : false));

    case kStation_dockedContractors:
      return JS_NewInt32(context,
                         (entity != nullptr ? entity->countOfDockedContractors()
                                            : unsigned{}));

    case kStation_dockedPolice:
      return JS_NewInt32(
          context,
          (entity != nullptr ? entity->countOfDockedPolice() : unsigned{}));

    case kStation_dockedDefenders:
      return JS_NewInt32(
          context,
          (entity != nullptr ? entity->countOfDockedDefenders() : unsigned{}));

    case kStation_equivalentTechLevel:
      return JS_NewInt32(
          context,
          (int32_t)(entity != nullptr ? entity->getEquivalentTechLevel() : 0));

    case kStation_equipmentPriceFactor:
      return JS_NewNumber(
          context,
          (entity != nullptr ? entity->getEquipmentPriceFactor() : 0.0f));

    case kStation_suppressArrivalReports:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->suppressArrivalReports() : false));

    case kStation_breakPattern:
      return OOJSValueFromBOOL(
          (entity != nullptr ? entity->getHasBreakPattern() : false));

    case kStation_shipyard: {
      if (!(entity != nullptr ? entity->hasShipyard() : false)) {
        // return null if station has no shipyard
        return JS_NULL;
      } else {
        if ((entity != nullptr ? entity->getLocalShipyard()
                               : (std::vector<oo::PList>*)nullptr) == nullptr) {
          if (entity != nullptr) entity->generateShipyard();
        }
        std::vector<oo::PList>* shipyard =
            (entity != nullptr ? entity->getLocalShipyard()
                               : (std::vector<oo::PList>*)nullptr);
        return OOJSValueFromPList(
            context, shipyard != nullptr ? oo::PList(*shipyard) : oo::PList());
      }
    }

    case kStation_market: {
      return OOJSValueFromPList(
          context, (entity != nullptr ? entity->localMarketForScripting()
                                      : oo::PList()));
    }

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sStationProperties,
                                    OOJS_COUNT(sStationProperties));
      return OOJSNativeFailure(context);
  }

  OOJS_NATIVE_EXIT
}

static JSValue StationSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* entity = nullptr;
  int bValue;
  int32_t iValue;
  double fValue;
  std::optional<std::string> sValue;

  if (!JSStationGetStationEntity(context, thisObj, &entity))
    return OOJSNativeFailure(context);
  if (entity == nullptr) return JS_UNDEFINED;

  switch (magic) {
    case kStation_hasNPCTraffic:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setHasNPCTraffic(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_alertCondition:
      if (OOJSValueToInt32(context, value, &iValue)) {
        if (entity != nullptr)
          entity->setAlertLevel((OOStationAlertLevel)iValue,
                                false);  // Performs range checking
        return JS_UNDEFINED;
      }
      break;

    case kStation_allegiance:
      sValue = cxx_OOStringFromJSValue(context, value);
      if (sValue.has_value()) {
        if (entity != nullptr) entity->setAllegiance(sValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_requiresDockingClearance:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setRequiresDockingClearance(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_roll:
      if (JS_ToFloat64(context, &fValue, value) == 0) {
        /*				if (fValue < -2.0)  fValue = -2.0;
                                        if (fValue > 2.0)  fValue = 2.0;
           // clamping to -2.0...2.0 gives us ±M_PI actual maximum rotation
                                        [entity setRoll:fValue]; */
        // use setRawRoll to make the units here equal to those in kShip_roll
        if (fValue < -M_PI)
          fValue = -M_PI;
        else if (fValue > M_PI)
          fValue = M_PI;
        if (entity != nullptr) entity->setRawRoll(fValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_allowsFastDocking:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setAllowsFastDocking(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_allowsAutoDocking:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setAllowsAutoDocking(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_suppressArrivalReports:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setSuppressArrivalReports(bValue);
        return JS_UNDEFINED;
      }
      break;

    case kStation_breakPattern:
      if ((bValue = JS_ToBool(context, value)) >= 0) {
        if (entity != nullptr) entity->setHasBreakPattern(bValue);
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic, sStationProperties,
                                    OOJS_COUNT(sStationProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sStationProperties,
                             OOJS_COUNT(sStationProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

// *** Methods ***

static JSValue StationAbortAllDockings(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  JSStationGetStationEntity(context, OOJS_THIS, &station);
  // SpiderMonkey tolerated returning normally with an error pending; QuickJS
  // does not.
  if (JS_HasException(context)) return JS_EXCEPTION;
  if (station != nullptr) station->abortAllDockings();

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue StationAbortDockingForShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  JSStationGetStationEntity(context, OOJS_THIS, &station);
  if (JS_HasException(context)) return JS_EXCEPTION;
  if (argc == 0) {
    cxx_OOJSReportBadArguments(context, "Station", "abortDockingForShip",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "ship in docking queue");
    return OOJSNativeFailure(context);
  }
  // (null was an object to SpiderMonkey, but passing it was not meaningful; it
  // now fails like other non-objects.)
  if (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]))
    return OOJSNativeFailure(context);
  ShipEntity* ship = nullptr;
  JSStationGetShipEntity(context, OOJS_ARGV[0], &ship);
  if (JS_HasException(context)) return JS_EXCEPTION;
  if (ship != nullptr) {
    if (station != nullptr) station->abortDockingForShip(ship);
  }

  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

// canDockShip(shipEntity) : boolean
// Proposed by phkb (Nick Rogers) 20161206
static JSValue StationCanDockShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  bool result = true;
  ShipEntity* shipToCheck = nullptr;

  if (argc > 0) {
    if (JS_IsNull(OOJS_ARGV[0]) || !JS_IsObject(OOJS_ARGV[0]) ||
        !JSStationGetShipEntity(context, OOJS_ARGV[0], &shipToCheck)) {
      return OOJSNativeFailure(context);
    }
  }
  if (EXPECT_NOT(shipToCheck == nullptr)) {
    cxx_OOJSReportBadArguments(context, "Station", "canDockShip", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "shipEntity");
    return OOJSNativeFailure(context);
  }

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  OOJS_BEGIN_FULL_NATIVE(context)
  result =
      (station != nullptr ? station->fitsInDock(shipToCheck, false) : false);
  OOJS_END_FULL_NATIVE

  OOJS_RETURN_BOOL(result);
  OOJS_NATIVE_EXIT
}

// dockPlayer()
// Proposed and written by Frame 20090729
static JSValue StationDockPlayer(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  PlayerEntity* player = OOPlayerForScripting();
  GameController* gameController =
      (UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr);

  if (EXPECT_NOT((gameController != nullptr ? gameController->isGamePaused()
                                            : false))) {
    /*	Station.dockPlayer() was executed while the game was in pause.
            Do we want to return an error or just unpause and continue?
            I think unpausing is the sensible thing to do here - Nikos 20110208
    */
    if (gameController != nullptr) gameController->setGamePaused(false);
  }

  if (EXPECT(!(player != nullptr
                   ? player->PlayerEntity::isDocked()
                   : false)))  // qualified: the final overrider, so the binding
                               // test stands in for it
  {
    StationEntity* stationForDockingPlayer = nullptr;
    JSStationGetStationEntity(context, OOJS_THIS, &stationForDockingPlayer);
    // SpiderMonkey tolerated returning normally with an error pending; QuickJS
    // does not.
    if (JS_HasException(context)) return JS_EXCEPTION;
    if (player != nullptr)
      player->setDockingClearanceStatus(OODockingClearanceStatus::kGranted);
    if (player != nullptr)
      player->PlayerEntity::safeAllMissiles();  // qualified: the final
                                                // overrider, so the binding
                                                // test stands in for it
    if (UNIVERSE != nullptr) UNIVERSE->setViewDirection(OOViewID::kForward);
    if (player != nullptr)
      player->PlayerEntity::enterDock(
          stationForDockingPlayer);  // qualified: the final overrider, so the
                                     // binding test stands in for it
  }
  OOJS_RETURN_VOID;

  OOJS_NATIVE_EXIT
}

static JSValue StationIncreaseAlertLevel(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)
  StationEntity* station = nullptr;

  GET_THIS_STATION(station);

  OOJS_BEGIN_FULL_NATIVE(context)
  if (oo::ToUnderlying(station != nullptr
                           ? station->ShipEntity::alertCondition()
                           : OOAlertCondition{}) <
      3)  // qualified: the final overrider, so the
          // binding test stands in for it
  {
    if (station != nullptr) station->increaseAlertLevel();
  }
  OOJS_END_FULL_NATIVE
  OOJS_RETURN_VOID;
  OOJS_NATIVE_EXIT
}

static JSValue StationDecreaseAlertLevel(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)
  StationEntity* station = nullptr;

  GET_THIS_STATION(station);

  OOJS_BEGIN_FULL_NATIVE(context)
  if (oo::ToUnderlying(station != nullptr
                           ? station->ShipEntity::alertCondition()
                           : OOAlertCondition{}) >
      1)  // qualified: the final overrider, so the
          // binding test stands in for it
  {
    if (station != nullptr) station->decreaseAlertLevel();
  }
  OOJS_END_FULL_NATIVE
  OOJS_RETURN_VOID;
  OOJS_NATIVE_EXIT
}

// launchShipWithRole(role : String [, abortAllDockings : boolean]) : shipEntity
static JSValue StationLaunchShipWithRole(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> shipRole;
  StationEntity* station = nullptr;
  ShipEntity* result = nullptr;
  bool abortAllDockings = false;

  GET_THIS_STATION(station);

  if (argc > 0) shipRole = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (EXPECT_NOT(!shipRole.has_value())) {
    cxx_OOJSReportBadArguments(context, "Station", "launchShipWithRole",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "string (role)");
    return OOJSNativeFailure(context);
  }

  if (argc > 1) abortAllDockings = JS_ToBool(context, OOJS_ARGV[1]) > 0;

  OOJS_BEGIN_FULL_NATIVE(context)
  result = oo::ToShip(oo::EntityIn(
      (station != nullptr ? station->launchIndependentShip(*shipRole)
                          : oo::PList())));  // the ship's entity node
  if (abortAllDockings) {
    if (station != nullptr) station->abortAllDockings();
  }
  OOJS_END_FULL_NATIVE

  OOJS_RETURN(
      OOJSValueFromCxxObject(context, result));  // the C++ ship's JS value
  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchDefenseShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched = (station != nullptr ? station->launchDefenseShip()
                                 : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value

  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchEscort(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched =
      (station != nullptr ? station->launchEscort() : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value

  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchScavenger(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched = (station != nullptr ? station->launchScavenger()
                                 : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value

  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchMiner(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched =
      (station != nullptr ? station->launchMiner() : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value
  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchPirateShip(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched = (station != nullptr ? station->launchPirateShip()
                                 : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value

  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchShuttle(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched =
      (station != nullptr ? station->launchShuttle() : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value
  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchPatrol(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  ShipEntity* launched = nullptr;
  OOJS_BEGIN_FULL_NATIVE(context)
  launched =
      (station != nullptr ? station->launchPatrol() : (::ShipEntity*)nullptr);
  OOJS_END_FULL_NATIVE
  OOJS_RETURN(
      OOJSValueFromCxxObject(context, launched));  // the C++ ship's JS value
  OOJS_NATIVE_EXIT
}

static JSValue StationLaunchPolice(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  oo::PList::Array launched;  // the launched ships' entity nodes, in order
  OOJS_BEGIN_FULL_NATIVE(context)
  const oo::PList police =
      (station != nullptr ? station->launchPolice() : oo::PList());
  for (Entity* ship : oo::EntitiesIn(police))
    launched.push_back(oo::EntityObjectNode(ship));
  OOJS_END_FULL_NATIVE
  OOJS_RETURN_PLIST(oo::PList(std::move(launched)));
  OOJS_NATIVE_EXIT
}

// Get a property of a definition object. As before, a failed get is treated
// like a missing property.
static JSValue GetParam(JSContext* context, JSValueConst object,
                        const char* key) {
  JSValue value = JS_GetPropertyStr(context, object, key);
  if (JS_IsException(value)) {
    OOJSReportPendingException(context);
    return JS_UNDEFINED;
  }
  return value;
}

static JSValue StationSetInterface(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  if (argc < 1) {
    cxx_OOJSReportBadArguments(context, "Station", "setInterface", MIN(argc, 1),
                               OOJS_ARGV, std::nullopt, "key [, definition]");
    return OOJSNativeFailure(context);
  }
  std::optional<std::string> key =
      cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);

  if (argc < 2 || JS_IsNull(OOJS_ARGV[1])) {
    if (station != nullptr)
      station->setInterfaceDefinition(nullptr, key.value_or(""));
    OOJS_RETURN_VOID;
  }

  JSValue value = JS_UNDEFINED;
  JSValue callback = JS_UNDEFINED;
  JSValue params = JS_UNDEFINED;
  std::string errorDescription;

  std::optional<std::string> title;
  std::optional<std::string> summary;
  std::optional<std::string> category;
  oo::Ref<OOJSInterfaceDefinition> definition;
  OOJSInterfaceDefinition* cxxDefinition = nullptr;

  // SpiderMonkey's JS_ValueToObject() boxed primitives. (It gave no object for
  // undefined, which then could not work; treat it as invalid.)
  if (!JS_IsUndefined(OOJS_ARGV[1])) {
    params = JS_ToObject(context, OOJS_ARGV[1]);
    if (JS_IsException(params)) {
      JS_FreeValue(context, JS_GetException(context));
      params = JS_UNDEFINED;
    }
  }
  if (!JS_IsObject(params)) {
    errorDescription = "key [, definition]";
    goto fail;
  }

  // get and validate title
  value = GetParam(context, params, "title");
  if (JS_IsUndefined(value)) {
    errorDescription =
        "key [, definition]; if definition is set, it must have a 'title' "
        "property.";
    goto fail;
  }
  title = cxx_OOStringFromJSValue(context, value);
  JS_FreeValue(context, value);
  value = JS_UNDEFINED;
  if (!title.has_value() || title->empty()) {
    errorDescription =
        "key [, definition]; if definition is set, 'title' property must be a "
        "non-empty string.";
    goto fail;
  }

  // get category with default
  value = GetParam(context, params, "category");
  if (JS_IsUndefined(value)) {
    category = OO_DESC("interfaces-category-uncategorised");
  } else {
    category = cxx_OOStringFromJSValue(context, value);
    if (!category.has_value() || category->empty()) {
      category = OO_DESC("interfaces-category-uncategorised");
    }
  }
  JS_FreeValue(context, value);
  value = JS_UNDEFINED;

  // get and validate summary
  value = GetParam(context, params, "summary");
  if (JS_IsUndefined(value)) {
    errorDescription =
        "key [, definition]; if definition is set, it must have a 'summary' "
        "property.";
    goto fail;
  }
  summary = cxx_OOStringFromJSValue(context, value);
  JS_FreeValue(context, value);
  value = JS_UNDEFINED;
  if (!summary.has_value() || summary->empty()) {
    errorDescription =
        "key [, definition]; if definition is set, 'summary' property must be "
        "a non-empty string.";
    goto fail;
  }

  // get and validate callback
  callback = GetParam(context, params, "callback");
  if (JS_IsUndefined(callback)) {
    errorDescription =
        "key [, definition]; if definition is set, it must have a 'callback' "
        "property.";
    goto fail;
  }
  if (!OOJSValueIsFunction(context, callback)) {
    errorDescription =
        "key [, definition]; 'callback' property must be a function.";
    goto fail;
  }

  // C++ (its façade was deleted); the station keeps it (oo::Ref).
  definition = oo::makeRef<OOJSInterfaceDefinition>();
  cxxDefinition = definition.get();
  cxxDefinition->setTitle(title);
  cxxDefinition->setCategory(*category);
  cxxDefinition->setSummary(*summary);
  cxxDefinition->setCallback(callback);  // Takes its own reference.
  JS_FreeValue(context, callback);

  // get callback 'this'
  value = GetParam(context, params, "cbThis");
  if (!JS_IsUndefined(value)) {
    // As with SpiderMonkey's JS_ValueToObject(), null gives no object;
    // primitives are boxed.
    if (!JS_IsNull(value)) {
      JSValue callbackThis = JS_ToObject(context, value);
      if (JS_IsException(callbackThis)) {
        JS_FreeValue(context, JS_GetException(context));
      } else {
        cxxDefinition->setCallbackThis(
            callbackThis);  // Takes its own reference.
      }
      JS_FreeValue(context, callbackThis);
    }
    // can do .bind(this) for callback instead
  }
  JS_FreeValue(context, value);
  JS_FreeValue(context, params);

  if (station != nullptr)
    station->setInterfaceDefinition(definition.get(), key.value_or(""));

  OOJS_RETURN_VOID;

fail:
  JS_FreeValue(context, callback);
  JS_FreeValue(context, value);
  JS_FreeValue(context, params);
  cxx_OOJSReportBadArguments(context, "Station", "setInterface", MIN(argc, 1),
                             OOJS_ARGV, std::nullopt, errorDescription);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

static JSValue StationSetMarketPrice(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "Station", "setMarketPrice",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "commodity, credits");
    return OOJSNativeFailure(context);
  }

  std::optional<std::string> commodity =
      cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  OOCommodities* commodities =
      (UNIVERSE != nullptr
           ? UNIVERSE->getCommodities()
           : nullptr);  // null: no good is defined, as a message to nil
  if (EXPECT_NOT(commodities == nullptr ||
                 !commodities->goodDefined(commodity.value_or("")))) {
    cxx_OOJSReportBadArguments(context, "Station", "setMarketPrice",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "Unrecognised commodity type");
    return OOJSNativeFailure(context);
  }

  int32_t price;
  bool gotPrice = OOJSValueToInt32(context, OOJS_ARGV[1], &price);
  if (EXPECT_NOT(!gotPrice || price < 0)) {
    cxx_OOJSReportBadArguments(context, "Station", "setMarketPrice",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "Price must be at least 0 decicredits");
    return OOJSNativeFailure(context);
  }

  if (station != nullptr)
    station->setPrice((std::size_t)price, commodity.value_or(""));

  if (station == (PLAYER != nullptr ? PLAYER->PlayerEntity::dockedStation()
                                    : (StationEntity*)nullptr) &&
      (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) ==
          OOGUIScreenID::kMarket)  // qualified: the final overrider, so the
                                   // binding test stands in for it
  {
    if (PLAYER != nullptr) PLAYER->setGuiToMarketScreen();  // refresh screen
  }

  OOJS_RETURN_BOOL(true);

  OOJS_NATIVE_EXIT
}

static JSValue StationSetMarketQuantity(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  if (argc < 2) {
    cxx_OOJSReportBadArguments(context, "Station", "setMarketQuantity",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "commodity, units");
    return OOJSNativeFailure(context);
  }

  const std::string commodity =
      cxx_OOStringFromJSValue(context, OOJS_ARGV[0]).value_or("");
  OOCommodities* commodities =
      (UNIVERSE != nullptr
           ? UNIVERSE->getCommodities()
           : nullptr);  // null: no good is defined, as a message to nil
  if (EXPECT_NOT(commodities == nullptr ||
                 !commodities->goodDefined(commodity))) {
    cxx_OOJSReportBadArguments(context, "Station", "setMarketQuantity",
                               MIN(argc, 2), OOJS_ARGV, std::nullopt,
                               "Unrecognised commodity type");
    return OOJSNativeFailure(context);
  }

  int32_t quantity;
  bool gotQuantity = OOJSValueToInt32(context, OOJS_ARGV[1], &quantity);
  OOCommodityMarket* market =
      (station != nullptr
           ? station->getLocalMarket()
           : (OOCommodityMarket*)nullptr);  // null: no capacity, as a message
                                            // to nil
  if (EXPECT_NOT(
          !gotQuantity || quantity < 0 ||
          (OOCargoQuantity)quantity >
              ((market != nullptr) ? market->capacityForGood(commodity) : 0))) {
    cxx_OOJSReportBadArguments(
        context, "Station", "setMarketQuantity", MIN(argc, 2), OOJS_ARGV,
        std::nullopt,
        "Quantity must be between 0 and the station market capacity");
    return OOJSNativeFailure(context);
  }

  if (station != nullptr)
    station->setQuantity((OOCargoQuantity)quantity, commodity);

  if (station == (PLAYER != nullptr ? PLAYER->PlayerEntity::dockedStation()
                                    : (StationEntity*)nullptr) &&
      (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) ==
          OOGUIScreenID::kMarket)  // qualified: the final overrider, so the
                                   // binding test stands in for it
  {
    if (PLAYER != nullptr) PLAYER->setGuiToMarketScreen();  // refresh screen
  }

  OOJS_RETURN_BOOL(true);

  OOJS_NATIVE_EXIT
}

// -oo_stringForKey: with its nil: the string, a number's -stringValue, or
// nothing.
static std::optional<std::string> StringForKey(const oo::PList& dictionary,
                                               std::string_view key) {
  const oo::PList* value = dictionary.get<oo::PList>(key);
  if (value == nullptr || !(value->isString() || value->isNumber()))
    return std::nullopt;
  return dictionary.get<std::string>(key);
}

// -oo_stringAtIndex: with its nil.
static std::optional<std::string> StringAtIndex(const oo::PList& array,
                                                std::size_t index) {
  const oo::PList* value = array.at<oo::PList>(index);
  if (value == nullptr || !(value->isString() || value->isNumber()))
    return std::nullopt;
  return array.at<std::string>(index);
}

// A mutable dictionary's -setObject:forKey: given a nil value raised this
// (GNUstep 1.31.1's text), and the calling script saw it as "Native exception:
// <reason>".
static void RaiseNilValueForKey(std::string_view key) {
  OORaiseException(OOInvalidArgumentException,
                   "Tried to add nil value for key '%s' to dictionary",
                   std::string(key).c_str());
}

// A string value for -setObject:forKey:, which raised on nil.
static std::string ValueForKey(const std::optional<std::string>& value,
                               std::string_view key) {
  if (!value.has_value()) RaiseNilValueForKey(key);
  return *value;
}

// OOEquipmentType::weaponThreatAssessment() of a weapon: 0 for no weapon.
static GLfloat WeaponThreatAssessment(OOWeaponType weapon) {
  OOEquipmentType* type = weapon;
  return (type != nullptr) ? type->weaponThreatAssessment() : 0;
}

static JSValue StationAddShipToShipyard(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  /*	SpiderMonkey's JS_ValueToObject() accepted primitives (boxing them) and
          undefined, but the definition was then read from argv[0] as an object
          regardless, so only objects (and null) ever worked. Anything else is
          now rejected as bad arguments.
  */
  if (argc != 1 || (!JS_IsNull(OOJS_ARGV[0]) && !JS_IsObject(OOJS_ARGV[0]))) {
    cxx_OOJSReportBadArguments(context, "Station", "addShipToShipyard",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "shipyard item definition");
    return OOJSNativeFailure(context);
  }

  // make sure the station has a shipyard
  if (!(station != nullptr ? station->hasShipyard() : false)) {
    cxx_OOJSReportWarningForCaller(context, "Station", "removeShipFromShipyard",
                                   "Station does not have shipyard.");
    return OOJSNativeFailure(context);
  }
  // make sure the shipyard has been generated
  if (!(station != nullptr ? station->getLocalShipyard()
                           : (std::vector<oo::PList>*)nullptr)) {
    if (station != nullptr) station->generateShipyard();
  }
  std::vector<oo::PList>* shipyard =
      (station != nullptr ? station->getLocalShipyard()
                          : (std::vector<oo::PList>*)nullptr);

  if (JS_IsNull(OOJS_ARGV[0]))
    OOJS_RETURN_VOID;  // OK, do nothing for null ship.

  oo::PList::Dict result;
  const oo::PList shipyardDefinition =
      cxx_OOJSPListFromJSObject(context, OOJS_ARGV[0]);
  // validate each element of the dictionary
  if (shipyardDefinition.isNull()) {
    cxx_OOJSReportBadArguments(context, "Station", "addShipToShipyard",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "valid dictionary object");
    return OOJSNativeFailure(context);
  }
  // This first test is -objectForKey: on the converted object, as it was:
  // anything but a dictionary (a JavaScript array converts to an array) raised,
  // which OOJS_NATIVE_EXIT reported.
  if (!shipyardDefinition.isDict()) {
    cxx_OOJSReportError(context, "Unidentified native exception");
    return OOJSNativeFailure(context);
  }
  if (shipyardDefinition.find(KEY_SHORT_DESCRIPTION) == nullptr) {
    cxx_OOJSReportBadArguments(context, "Station", "addShipToShipyard",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "'short_description' in dictionary");
    return OOJSNativeFailure(context);
  }
  result[std::string(KEY_SHORT_DESCRIPTION)] =
      ValueForKey(StringForKey(shipyardDefinition, "short_description"),
                  KEY_SHORT_DESCRIPTION);
  if (!shipyardDefinition.get<oo::PList>(
          std::string(SHIPYARD_KEY_SHIPDATA_KEY))) {
    cxx_OOJSReportBadArguments(context, "Station", "addShipToShipyard",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "'shipdata_key' in dictionary");
    return OOJSNativeFailure(context);
  }
  // get the shipInfo and shipyardInfo for this key
  const std::optional<std::string> shipKey =
      StringForKey(shipyardDefinition, std::string(SHIPYARD_KEY_SHIPDATA_KEY));
  OOShipRegistry* registry = OOShipRegistry::sharedRegistry();
  // A copy of the registry's entry: -dictionaryWithDictionary: made an empty
  // one for an unknown key, never nil, so an unknown key goes on to the tests
  // below (its "Invalid shipdata_key" test could not fire and is gone).
  oo::PList shipInfo =
      (shipKey.has_value() ? registry->shipInfoForKey(*shipKey) : oo::PList());
  if (!shipInfo.isDict()) shipInfo = oo::PList(oo::PList::Dict());
  const oo::PList shipyardInfo =
      (shipKey.has_value() ? registry->shipyardInfoForKey(*shipKey)
                           : oo::PList());
  // make sure the ship is a player ship (no roles string searched as a nil
  // receiver: found at 0)
  const std::optional<std::string> roles = StringForKey(shipInfo, "roles");
  if (roles.has_value() && roles->find("player") == std::string::npos) {
    cxx_OOJSReportWarningForCaller(
        context, "Station", "addShipToShipyard",
        "shipdata_key not suitable for player role.");
    return OOJSNativeFailure(context);
  }
  if (!shipyardInfo) {
    cxx_OOJSReportWarningForCaller(
        context, "Station", "addShipToShipyard",
        "No shipyard information found for shipdata_key.");
    return OOJSNativeFailure(context);
  }
  // ok, feel pretty safe to include this ship now
  result[std::string(SHIPYARD_KEY_SHIPDATA_KEY)] =
      *shipKey;  // non-nil: a nil key found no shipyard information above

  // add an ID
  Random_Seed ship_seed =
      (UNIVERSE != nullptr ? UNIVERSE->marketSeed() : Random_Seed{});
  int superRand1 = ship_seed.a * 0x10000 + ship_seed.c * 0x100 + ship_seed.e;
  uint32_t superRand2 =
      ship_seed.b * 0x10000 + ship_seed.d * 0x100 + ship_seed.f;
  superRand2 &= Ranrot();
  std::string shipID = std::format("{:06x}-{:06x}", superRand1, superRand2);
  result[std::string(SHIPYARD_KEY_ID)] = shipID;

  if (!shipyardDefinition.get<oo::PList>(std::string(SHIPYARD_KEY_PRICE))) {
    // if not provided, get the price from the registry
    OOCreditsQuantity price =
        shipyardInfo.get<unsigned int>(std::string(KEY_PRICE));
    result[std::string(SHIPYARD_KEY_PRICE)] = oo::PList::unsignedInteger(price);
  } else {
    OOCreditsQuantity price =
        shipyardDefinition.get<unsigned int>(std::string(SHIPYARD_KEY_PRICE));
    if (price > 0) {
      result[std::string(SHIPYARD_KEY_PRICE)] =
          oo::PList::unsignedInteger(price);
    } else {
      cxx_OOJSReportBadArguments(context, "Station", "addShipToShipyard",
                                 MIN(argc, 1), OOJS_ARGV, std::nullopt,
                                 "'price' in dictionary");
      return OOJSNativeFailure(context);
    }
  }

  if (!shipyardDefinition.get<oo::PList>(
          std::string(SHIPYARD_KEY_PERSONALITY))) {
    // default to 0 if not supplied
    result[std::string(SHIPYARD_KEY_PERSONALITY)] =
        oo::PList::unsignedInteger(0);
  } else {
    result[std::string(SHIPYARD_KEY_PERSONALITY)] =
        oo::PList::unsignedInteger(shipyardDefinition.get<unsigned int>(
            std::string(SHIPYARD_KEY_PERSONALITY)));
  }

  const oo::PList* standardEquipment =
      shipyardInfo.get<oo::PList::Dict>(std::string(KEY_STANDARD_EQUIPMENT));
  oo::PList extras;
  if (const oo::PList* definedExtras = shipyardDefinition.get<oo::PList::Array>(
          std::string(KEY_EQUIPMENT_EXTRAS)))
    extras = *definedExtras;
  else {
    // pick up defaults if extras not supplied (-arrayWithArray: made an empty
    // array of a missing one)
    const oo::PList* standardExtras =
        (standardEquipment != nullptr)
            ? standardEquipment->get<oo::PList::Array>(
                  std::string(KEY_EQUIPMENT_EXTRAS))
            : nullptr;
    extras = (standardExtras != nullptr) ? *standardExtras
                                         : oo::PList(oo::PList::Array());
  }
  if (extras.count() > 0) {
    // go looking for lasers and add them directly to our shipInfo
    std::optional<std::string> fwdWeaponString =
        (standardEquipment != nullptr)
            ? StringForKey(*standardEquipment,
                           std::string(KEY_EQUIPMENT_FORWARD_WEAPON))
            : std::nullopt;
    std::optional<std::string> aftWeaponString =
        (standardEquipment != nullptr)
            ? StringForKey(*standardEquipment,
                           std::string(KEY_EQUIPMENT_AFT_WEAPON))
            : std::nullopt;
    OOWeaponFacingSet availableFacings =
        shipyardInfo.get<unsigned int>(std::string(KEY_WEAPON_FACINGS),
                                       kOOValidWeaponFacings) &
        kOOValidWeaponFacings;

    OOWeaponType fwdWeapon = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
        fwdWeaponString.value_or(""));
    OOWeaponType aftWeapon = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
        aftWeaponString.value_or(""));

    unsigned int i;
    std::optional<std::string> equipmentKey;
    for (i = 0; i < extras.count(); i++) {
      equipmentKey = StringAtIndex(extras, i);
      if (equipmentKey.has_value() &&
          oo::str::hasPrefix(*equipmentKey, "EQ_WEAPON")) {
        OOWeaponType new_weapon = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
            equipmentKey.value_or(""));
        // fit best weapon forward
        if (OOWeaponFacingIsIn(availableFacings, OOWeaponFacing::kForward) &&
            WeaponThreatAssessment(new_weapon) >
                WeaponThreatAssessment(fwdWeapon)) {
          // again remember to divide price by 10 to get credits from tenths of
          // credit
          fwdWeaponString = equipmentKey;
          fwdWeapon = new_weapon;
          (*shipInfo.getIf<oo::PList::Dict>())[std::string(
              KEY_EQUIPMENT_FORWARD_WEAPON)] = *fwdWeaponString;
        } else {
          // if less good than current forward, try fitting is to rear
          if (OOWeaponFacingIsIn(availableFacings, OOWeaponFacing::kAft) &&
              (isWeaponNone(aftWeapon) ||
               WeaponThreatAssessment(new_weapon) >
                   WeaponThreatAssessment(aftWeapon))) {
            aftWeaponString = equipmentKey;
            aftWeapon = new_weapon;
            (*shipInfo.getIf<oo::PList::Dict>())[std::string(
                KEY_EQUIPMENT_AFT_WEAPON)] = *aftWeaponString;
          }
        }
      }
    }
  }
  // add the extras
  result[std::string(KEY_EQUIPMENT_EXTRAS)] = extras;
  // add the ship spec
  result[std::string(SHIPYARD_KEY_SHIP)] = shipInfo;
  // add it to the station's shipyard
  if (shipyard != nullptr) shipyard->push_back(oo::PList(std::move(result)));

  // refresh the screen if the shipyard is currently being displayed
  if (station == (PLAYER != nullptr ? PLAYER->PlayerEntity::dockedStation()
                                    : (StationEntity*)nullptr) &&
      (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) ==
          OOGUIScreenID::kShipyard)  // qualified: the final overrider, so the
                                     // binding test stands in for it
  {
    if (PLAYER != nullptr) PLAYER->setGuiToShipyardScreen(0);
  }

  OOJS_RETURN_BOOL(true);

  OOJS_NATIVE_EXIT
}

static JSValue StationRemoveShipFromShipyard(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  StationEntity* station = nullptr;
  GET_THIS_STATION(station);

  // make sure the station has a shipyard
  if (!(station != nullptr ? station->hasShipyard() : false)) {
    cxx_OOJSReportWarningForCaller(context, "Station", "removeShipFromShipyard",
                                   "Station does not have shipyard.");
    return OOJSNativeFailure(context);
  }
  // make sure the shipyard has been generated
  if (!(station != nullptr ? station->getLocalShipyard()
                           : (std::vector<oo::PList>*)nullptr)) {
    if (station != nullptr) station->generateShipyard();
  }
  std::vector<oo::PList>* shipyard =
      (station != nullptr ? station->getLocalShipyard()
                          : (std::vector<oo::PList>*)nullptr);

  int32_t shipIndex = -1;
  bool gotIndex = true;
  gotIndex = OOJSValueToInt32(
      context, OOJS_ARGV[0],
      &shipIndex);  // argv[0] is undefined if argc is 0 (min args 1).

  if (argc != 1 || (!JS_IsNull(OOJS_ARGV[0]) && !gotIndex) || shipIndex < 0 ||
      static_cast<std::size_t>(shipIndex) + 1 >
          (shipyard != nullptr ? shipyard->size() : 0)) {
    cxx_OOJSReportBadArguments(context, "Station", "removeShipFromShipyard",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt,
                               "valid ship index");
    return OOJSNativeFailure(context);
  }

  shipyard->erase(shipyard->begin() + shipIndex);

  // refresh the screen if the shipyard is currently being displayed
  if (station == (PLAYER != nullptr ? PLAYER->PlayerEntity::dockedStation()
                                    : (StationEntity*)nullptr) &&
      (PLAYER != nullptr ? PLAYER->guiScreen() : OOGUIScreenID{}) ==
          OOGUIScreenID::kShipyard)  // qualified: the final overrider, so the
                                     // binding test stands in for it
  {
    if (PLAYER != nullptr) PLAYER->setGuiToShipyardScreen(0);
  }

  OOJS_RETURN_BOOL(true);

  OOJS_NATIVE_EXIT
}
