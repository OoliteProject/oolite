/*

StationEntity.h

ShipEntity subclass representing a space station or dockable ship.

The state is C++ since slice 1 of its slice plan (docs/phases/3-slices/StationEntity.md, bead
oo-64ako; proposed ADR-0056, amendments oo-60fwo and oo-64ako): cxx::StationEntity, a
cxx::ShipEntity, holds the ivars as public data members with the same names, and the class shell's
methods (accessors, market, shipyard, flags, set-up, descriptions). StationEntity+ObjCBridge.h,
imported at the end of this header, keeps the Objective-C StationEntity, whose methods of slices
2-4 stay Objective-C until their slices move them. The bridge's deletion bead moves the class out
of namespace cxx.

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

@class OOWeakSet, StationEntity;

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

namespace cxx {

/*	The station's state, and the members its slices have moved (docs/phases/3-slices/StationEntity.md).

        The ivars are data members with the same names, every one zero-initialised as the runtime
        zeroed them (amendment oo-bj8 item 1). The facade's unconverted methods reach them through the
        facade's _cxxStation, by the same names (amendment oo-64ako), so each later slice gets its
        bodies back verbatim by deleting "_cxxStation->". Pointers to Objective-C objects stay what
        they were, retained by hand where they were (amendment oo-bj8 item 4).
*/
class StationEntity : public ShipEntity {
public:
    // Slice 1: class shell, market and shipyard, flags and accessors.
    bool isUnpiloted() override;
    OOTechLevelID getEquivalentTechLevel();
    void setEquivalentTechLevel(OOTechLevelID value);
    Vector virtualPortDimensions();
    ::DockEntity* playerReservedDock();
    HPVector beaconPosition();
    float getEquipmentPriceFactor();
    OOCargoQuantity getMarketCapacity();
    oo::PList getMarketDefinition(); // null: none
    std::optional<std::string> getMarketScriptName();
    bool getMarketMonitored();
    bool getMarketBroadcast();
    OOCreditsQuantity legalStatusOfManifest(::OOCommodityMarket* manifest, bool isExport);
    ::OOCommodityMarket* getLocalMarket();
    void setLocalMarket(const oo::PList& some_market);
    oo::PList localMarketForScripting();
    void setPrice(OOCreditsQuantity price, const std::string& commodity);
    void setQuantity(OOCargoQuantity quantity, const std::string& commodity);
    std::vector<oo::PList>* getLocalShipyard();
    void setLocalShipyard(const std::vector<oo::PList>& some_market);
    std::map<std::string, oo::ObjCRef<::OOJSInterfaceDefinition*>, std::less<>>* getLocalInterfaces();
    void setInterfaceDefinition(::OOJSInterfaceDefinition* definition, const std::string& key);
    ::OOCommodityMarket* initialiseLocalMarket();
    void setPlanet(::OOPlanetEntity* planet_entity);
    ::OOPlanetEntity* getPlanet();
    unsigned countOfDockedContractors();
    unsigned countOfDockedPolice();
    unsigned countOfDockedDefenders();
    std::vector<oo::ObjCRef<::DockEntity*>> dockSubEntities();
    bool setUpShipFromDictionary(const oo::PList& dict) override;
    bool setUpSubEntities() override;
    bool getInterstellarUndockingAllowed();
    bool getHasNPCTraffic();
    void setHasNPCTraffic(bool flag);
    bool getRequiresDockingClearance();
    void setRequiresDockingClearance(bool newValue);
    bool getAllowsFastDocking();
    void setAllowsFastDocking(bool newValue);
    bool getAllowsAutoDocking();
    void setAllowsAutoDocking(bool newValue);
    bool getAllowsSaving();
    bool isRotatingStation();
    std::optional<std::string> marketOverrideName();
    bool hasShipyard();
    void generateShipyard();
    void generateShipyard(OOTechLevelID stationTechLevel);
    bool suppressArrivalReports();
    void setSuppressArrivalReports(bool newValue);
    bool getHasBreakPattern();
    void setHasBreakPattern(bool newValue);
    std::optional<std::string> descriptionComponents() const override;
    void dumpSelfState() override;

    // ShipEntityAI.mm slice 1 (bead oo-iebuz): the category StationEntity (OOAIPrivate).
    void acceptDistressMessageFrom(::ShipEntity* other) override;

    // Slice 2: docking traffic control and the launch queue.
    void sanityCheckShipsOnApproach();
    void launchShip(::ShipEntity* ship);
    void abortAllDockings();
    void autoDockShipsOnHold();
    void autoDockShipsOnApproach();
    Vector portUpVectorForShip(::ShipEntity* ship);
    oo::PList dockingInstructionsForShip(::ShipEntity* ship);
    oo::PList holdPositionInstructionForShip(::ShipEntity* ship);
    void abortDockingForShip(::ShipEntity* ship);
    bool shipIsInDockingCorridor(::ShipEntity* ship);
    void pullInShipIfPermitted(::ShipEntity* ship);
    bool dockingCorridorIsEmpty();
    void clearDockingCorridor();
    void update(OOTimeDelta delta_t) override;
    void clear();
    bool hasMultipleDocks();
    bool hasClearDock();
    bool hasEligibleDock();
    bool hasLaunchDock();
    ::DockEntity* selectDockForDocking();
    void addShipToLaunchQueue(::ShipEntity* ship, bool priority);
    unsigned countOfShipsInLaunchQueueWithPrimaryRole(const std::string& role);
    bool fitsInDock(::ShipEntity* ship);
    bool fitsInDock(::ShipEntity* ship, bool logNoFit);
    void noteDockedShip(::ShipEntity* ship);
    void addShipToStationCount(::ShipEntity* ship);

    // Slice 3: docking clearance, damage, allegiance and alert level.
    bool collideWithShip(::ShipEntity* other) override;
    bool hasHostileTarget() override;
    void takeEnergyDamage(double amount, cxx::Entity* ent, cxx::Entity* other, const std::string& weaponIdentifier) override;
    void adjustVelocity(Vector xVel) override;
    void takeScrapeDamage(double amount, ::Entity* ent) override;
    void takeHeatDamage(double amount) override;
    std::optional<std::string> getAllegiance();
    void setAllegiance(const std::optional<std::string>& newAllegiance);
    OOStationAlertLevel getAlertLevel();
    void setAlertLevel(OOStationAlertLevel level, bool signallingScript);
    void increaseAlertLevel();
    void decreaseAlertLevel();
    void becomeExplosion() override;
    void becomeEnergyBlast() override;
    void becomeLargeExplosion(double factor) override;
    void acceptPatrolReportFrom(::ShipEntity* patrol_ship);
    std::optional<std::string> acceptDockingClearanceRequestFrom(::ShipEntity* other);
    unsigned currentlyInDockingQueues();
    unsigned currentlyInLaunchingQueues();

    // @private in Objective-C: private once StationEntity is converted; public while the facade's
    // unconverted methods read them, since an Objective-C class cannot be a C++ friend
    ::OOWeakSet* _shipsOnHold = { };
    ::DockEntity* player_reserved_dock = { };
    double last_launch_time = { };
    double approach_spacing = { };
    OOStationAlertLevel alertLevel = { };

    unsigned max_police = { }; // max no. of police ships allowed
    unsigned max_defense_ships = { }; // max no. of defense ships allowed
    unsigned defenders_launched = { };

    unsigned max_scavengers = { }; // max no. of scavenger ships allowed
    unsigned scavengers_launched = { };

    OOTechLevelID equivalentTechLevel = { };
    float equipmentPriceFactor = { };

    Vector port_dimensions = { };
    double port_radius = { };

    unsigned no_docking_while_launching : 1 = 0,
                                          hasNPCTraffic : 1 = 0;
    BOOL hasPatrolShips = { };

    OOUniversalID planet = { };

    std::optional<std::string> allegiance; // nullopt: none (was nil)

    ::OOCommodityMarket* localMarket = { };
    OOCargoQuantity marketCapacity = { };
    oo::PList marketDefinition; // an array; null: none (was nil)
    std::optional<std::string> marketScriptName; // nullopt: none (was nil)
    std::optional<std::vector<oo::PList>> localShipyard; // nullopt: not generated yet (was nil)

    std::map<std::string, oo::ObjCRef<::OOJSInterfaceDefinition*>, std::less<>> localInterfaces;

    unsigned docked_shuttles = { };
    double last_shuttle_launch_time = { };
    double shuttle_launch_interval = { };

    unsigned docked_traders = { };
    double last_trader_launch_time = { };
    double trader_launch_interval = { };

    double last_patrol_report_time = { };
    double patrol_launch_interval = { };

    unsigned suppress_arrival_reports : 1 = 0,
                                        requiresDockingClearance : 1 = 0,
                                        interstellarUndockingAllowed : 1 = 0,
                                        allowsFastDocking : 1 = 0,
                                        allowsSaving : 1 = 0,
                                        allowsAutoDocking : 1 = 0,
                                        hasBreakPattern : 1 = 0,
                                        marketMonitored : 1 = 0,
                                        marketBroadcast : 1 = 0;
};

} // namespace cxx

// A mixed configuration (proposed ADR-0043 Amendment 2): "station" is an Object node holding the
// station's weak reference; ai_message / comms_message absent when nullopt.
oo::PList cxx_OOMakeDockingInstructions(StationEntity* station, HPVector coords, float speed, float range, const std::optional<std::string>& ai_message, const std::optional<std::string>& comms_message, BOOL match_rotation, int docking_stage);

// Transitional: the Objective-C StationEntity, for its unconverted methods and its callers.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "StationEntity+ObjCBridge.h"
