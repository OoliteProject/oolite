/*

StationEntity.h

ShipEntity subclass representing a space station or dockable ship.

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

#pragma once

#import "OOJSInterfaceDefinition.h"
#import "ShipEntity.h"
#import "Universe.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOWeakSet;

typedef enum {
    STATION_ALERT_LEVEL_GREEN = ALERT_CONDITION_GREEN,
    STATION_ALERT_LEVEL_YELLOW = ALERT_CONDITION_YELLOW,
    STATION_ALERT_LEVEL_RED = ALERT_CONDITION_RED
} OOStationAlertLevel;

#define STATION_MAX_POLICE 8

#define STATION_DELAY_BETWEEN_LAUNCHES 6.0

#define STATION_LAUNCH_RETRY_INTERVAL 2.0

#define MAX_DOCKING_STAGES 16

#define DOCKING_CLEARANCE_WINDOW 126.0

@interface StationEntity : ShipEntity {
@private
    OOWeakSet* _shipsOnHold;
    DockEntity* player_reserved_dock;
    double last_launch_time;
    double approach_spacing;
    OOStationAlertLevel alertLevel;

    unsigned max_police; // max no. of police ships allowed
    unsigned max_defense_ships; // max no. of defense ships allowed
    unsigned defenders_launched;

    unsigned max_scavengers; // max no. of scavenger ships allowed
    unsigned scavengers_launched;

    OOTechLevelID equivalentTechLevel;
    float equipmentPriceFactor;

    Vector port_dimensions;
    double port_radius;

    unsigned no_docking_while_launching : 1,
        hasNPCTraffic : 1;
    BOOL hasPatrolShips;

    OOUniversalID planet;

    std::optional<std::string> allegiance; // nullopt: none (was nil)

    OOCommodityMarket* localMarket;
    OOCargoQuantity marketCapacity;
    oo::PList marketDefinition; // an array; null: none (was nil)
    std::optional<std::string> marketScriptName; // nullopt: none (was nil)
    std::optional<std::vector<oo::PList>> localShipyard; // nullopt: not generated yet (was nil)

    std::map<std::string, oo::ObjCRef<OOJSInterfaceDefinition*>, std::less<>> localInterfaces;

    unsigned docked_shuttles;
    double last_shuttle_launch_time;
    double shuttle_launch_interval;

    unsigned docked_traders;
    double last_trader_launch_time;
    double trader_launch_interval;

    double last_patrol_report_time;
    double patrol_launch_interval;

    unsigned suppress_arrival_reports : 1,
        requiresDockingClearance : 1,
        interstellarUndockingAllowed : 1,
        allowsFastDocking : 1,
        allowsSaving : 1,
        allowsAutoDocking : 1,
        hasBreakPattern : 1,
        marketMonitored : 1,
        marketBroadcast : 1;
}

- (OOCargoQuantity)marketCapacity;
- (oo::PList)cxx_marketDefinition; // null: none
- (std::optional<std::string>)cxx_marketScriptName;
- (BOOL)marketMonitored;
- (BOOL)marketBroadcast;
- (OOCreditsQuantity)legalStatusOfManifest:(OOCommodityMarket*)manifest export:(BOOL)isExport;

- (OOCommodityMarket*)localMarket;
- (void)cxx_setLocalMarket:(const oo::PList&)market; // [[key, quantity, price], ...] (OOCommodityMarket -cxx_loadStationAmounts:)
- (oo::PList)cxx_localMarketForScripting;
- (void)cxx_setPrice:(OOCreditsQuantity)price forCommodity:(const std::string&)commodity;
- (void)cxx_setQuantity:(OOCargoQuantity)quantity forCommodity:(const std::string&)commodity;

// The live shipyard, which callers edit in place (proposed ADR-0043 item 22): nullptr on a nil
// receiver or before -generateShipyard.
- (std::vector<oo::PList>*)cxx_localShipyard;
- (void)cxx_setLocalShipyard:(const std::vector<oo::PList>&)shipyard;
- (void)generateShipyard;
- (void)generateShipyard:(OOTechLevelID)stationTechLevel;
- (std::map<std::string, oo::ObjCRef<OOJSInterfaceDefinition*>, std::less<>>*)cxx_localInterfaces; // the live map; nullptr on nil
- (void)cxx_setInterfaceDefinition:(OOJSInterfaceDefinition*)definition forKey:(const std::string&)key; // nil removes

- (OOCommodityMarket*)initialiseLocalMarket;

- (OOTechLevelID)equivalentTechLevel;
- (void)setEquivalentTechLevel:(OOTechLevelID)value;

- (std::vector<oo::ObjCRef<DockEntity*>>)cxx_dockSubEntities; // the -isDock subentities, in subentity order (a snapshot)
- (Vector)virtualPortDimensions;
- (DockEntity*)playerReservedDock;

- (HPVector)beaconPosition;

- (float)equipmentPriceFactor;

- (void)setPlanet:(OOPlanetEntity*)planet;

- (OOPlanetEntity*)planet;

- (void)cxx_setAllegiance:(const std::optional<std::string>&)newAllegiance;
- (std::optional<std::string>)cxx_allegiance; // nullopt: none

- (unsigned)countOfDockedContractors;
- (unsigned)countOfDockedPolice;
- (unsigned)countOfDockedDefenders;

- (void)sanityCheckShipsOnApproach;

- (void)autoDockShipsOnApproach;

- (Vector)portUpVectorForShip:(ShipEntity*)ship;

- (oo::PList)dockingInstructionsForShip:(ShipEntity*)ship; // null: none (bead oo-3rb.262)

- (BOOL)shipIsInDockingCorridor:(ShipEntity*)ship;

- (BOOL)dockingCorridorIsEmpty;

- (void)clearDockingCorridor;

- (void)clear;

- (void)abortAllDockings;

- (void)abortDockingForShip:(ShipEntity*)ship;

- (BOOL)hasMultipleDocks;
- (BOOL)hasClearDock;
- (BOOL)hasLaunchDock;
- (DockEntity*)selectDockForDocking;
- (unsigned)currentlyInLaunchingQueues;
- (unsigned)currentlyInDockingQueues;

- (void)launchShip:(ShipEntity*)ship;

- (oo::PList)launchIndependentShip:(const std::string&)role; // called by name (ADR-0055 item 5): the ship launched, as an Object node (null: none)

- (void)noteDockedShip:(ShipEntity*)ship;

- (BOOL)interstellarUndockingAllowed;
- (BOOL)hasNPCTraffic;
- (void)setHasNPCTraffic:(BOOL)flag;

- (OOStationAlertLevel)alertLevel;
- (void)setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript;

////////////////////////////////////////////////////////////// AI methods...

- (void)increaseAlertLevel;
- (void)decreaseAlertLevel;

- (oo::PList)launchPolice; // called by name (ADR-0055 item 5): the ships launched, as Object nodes
- (ShipEntity*)launchDefenseShip;
- (ShipEntity*)launchScavenger;
- (ShipEntity*)launchMiner;
/**Lazygun** added the following line*/
- (ShipEntity*)launchPirateShip;
- (ShipEntity*)launchShuttle;
- (ShipEntity*)launchEscort;
- (ShipEntity*)launchPatrol;

- (void)launchShipWithRole:(const std::string&)role; // called by name (ADR-0055 item 5)

- (void)acceptPatrolReportFrom:(ShipEntity*)patrol_ship;

- (std::optional<std::string>)cxx_acceptDockingClearanceRequestFrom:(ShipEntity*)other;
- (BOOL)requiresDockingClearance;
- (void)setRequiresDockingClearance:(BOOL)newValue;

- (BOOL)allowsFastDocking;
- (void)setAllowsFastDocking:(BOOL)newValue;

- (BOOL)allowsAutoDocking;
- (void)setAllowsAutoDocking:(BOOL)newValue;

- (BOOL)allowsSaving;
// no setting this after station creation

- (std::optional<std::string>)marketOverrideName; // nullopt: no "market" key
- (BOOL)isRotatingStation;
- (BOOL)hasShipyard;

- (BOOL)suppressArrivalReports;
- (void)setSuppressArrivalReports:(BOOL)newValue;

- (BOOL)hasBreakPattern;
- (void)setHasBreakPattern:(BOOL)newValue;

- (BOOL)fitsInDock:(ShipEntity*)ship;
- (BOOL)fitsInDock:(ShipEntity*)ship andLogNoFit:(BOOL)logNoFit;

@end

// A mixed configuration (proposed ADR-0043 Amendment 2): "station" is an Object node holding the
// station's weak reference; ai_message / comms_message absent when nullopt.
oo::PList cxx_OOMakeDockingInstructions(StationEntity* station, HPVector coords, float speed, float range, const std::optional<std::string>& ai_message, const std::optional<std::string>& comms_message, BOOL match_rotation, int docking_stage);
