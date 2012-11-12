/*

StationEntity.h

ShipEntity subclass representing a space station or dockable ship.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "ShipEntity.h"
#import "OOJSInterfaceDefinition.h"
#import "Universe.h"

@class OOWeakSet;


typedef enum
{
	STATION_ALERT_LEVEL_GREEN	= ALERT_CONDITION_GREEN,
	STATION_ALERT_LEVEL_YELLOW	= ALERT_CONDITION_YELLOW,
	STATION_ALERT_LEVEL_RED		= ALERT_CONDITION_RED
} OOStationAlertLevel;

#define STATION_MAX_POLICE				8

#define STATION_DELAY_BETWEEN_LAUNCHES  6.0

#define STATION_LAUNCH_RETRY_INTERVAL   2.0

#define MAX_DOCKING_STAGES				16

#define DOCKING_CLEARANCE_WINDOW		126.0


@interface StationEntity: ShipEntity
{
@private
	OOWeakSet				*_shipsOnHold;
	DockEntity				*player_reserved_dock;
	double					last_launch_time;
	double					approach_spacing;
	OOStationAlertLevel		alertLevel;
	
	unsigned				max_police;					// max no. of police ships allowed
	unsigned				max_defense_ships;			// max no. of defense ships allowed
	unsigned				defenders_launched;
	
	unsigned				max_scavengers;				// max no. of scavenger ships allowed
	unsigned				scavengers_launched;
	
	OOTechLevelID			equivalentTechLevel;
	float					equipmentPriceFactor;
	
	Vector  				port_dimensions;
	double					port_radius;
	
	unsigned				no_docking_while_launching: 1,
							hasNPCTraffic: 1;
	BOOL					hasPatrolShips;
	
	OOUniversalID			planet;
	
	NSMutableArray			*localMarket;
//	NSMutableArray			*localPassengers;
//	NSMutableArray			*localContracts;
	NSMutableArray			*localShipyard;
	
	NSMutableDictionary *localInterfaces;

	unsigned				docked_shuttles;
	double					last_shuttle_launch_time;
	double					shuttle_launch_interval;
	
	unsigned				docked_traders;
	double					last_trader_launch_time;
	double					trader_launch_interval;
	
	double					last_patrol_report_time;
	double					patrol_launch_interval;
	
	unsigned				suppress_arrival_reports: 1,
							requiresDockingClearance: 1,
							interstellarUndockingAllowed: 1,
							allowsFastDocking: 1,
							allowsAutoDocking: 1,
							hasBreakPattern: 1;
}

- (NSMutableArray *) localMarket;
- (void) setLocalMarket:(NSArray *)market;
- (NSDictionary *) localMarketForScripting;
- (void) setPrice:(NSUInteger) price forCommodity:(OOCommodityType) commodity;
- (void) setQuantity:(NSUInteger) quantity forCommodity:(OOCommodityType) commodity;

/*- (NSMutableArray *) localPassengers;
- (void) setLocalPassengers:(NSArray *)market;
- (NSMutableArray *) localContracts;
- (void) setLocalContracts:(NSArray *)market; */
- (NSMutableArray *) localShipyard;
- (void) setLocalShipyard:(NSArray *)market;
- (NSMutableDictionary *) localInterfaces;
- (void) setInterfaceDefinition:(OOJSInterfaceDefinition *)definition forKey:(NSString *)key;

- (NSMutableArray *) initialiseLocalMarketWithRandomFactor:(int)random_factor;
- (NSMutableArray *) initialiseMarketWithSeed:(Random_Seed)seed andRandomFactor:(int)random_factor;

- (OOTechLevelID) equivalentTechLevel;
- (void) setEquivalentTechLevel:(OOTechLevelID)value;

- (NSEnumerator *) dockSubEntityEnumerator;
- (Vector) virtualPortDimensions;
- (DockEntity*) playerReservedDock;

- (Vector) beaconPosition;

- (float) equipmentPriceFactor;

- (void) setPlanet:(OOPlanetEntity *)planet;

- (OOPlanetEntity *) planet;

- (unsigned) countOfDockedContractors;
- (unsigned) countOfDockedPolice;
- (unsigned) countOfDockedDefenders;

- (void) sanityCheckShipsOnApproach;

- (void) autoDockShipsOnApproach;

- (Vector) portUpVectorForShip:(ShipEntity *)ship;

- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *)ship;

- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship;

- (BOOL) dockingCorridorIsEmpty;

- (void) clearDockingCorridor;

- (void) clear;


- (void) abortAllDockings;

- (void) abortDockingForShip:(ShipEntity *)ship;

- (BOOL) hasMultipleDocks;
- (BOOL) hasClearDock;
- (BOOL) hasLaunchDock;
- (DockEntity *) selectDockForDocking;
- (unsigned) currentlyInLaunchingQueues;
- (unsigned) currentlyInDockingQueues;


- (void) launchShip:(ShipEntity *)ship;

- (ShipEntity *) launchIndependentShip:(NSString *)role;

- (void) noteDockedShip:(ShipEntity *)ship;

- (BOOL) interstellarUndockingAllowed;
- (BOOL) hasNPCTraffic;
- (void) setHasNPCTraffic:(BOOL)flag;

- (OOStationAlertLevel) alertLevel;
- (void) setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript;

////////////////////////////////////////////////////////////// AI methods...

- (void) increaseAlertLevel;
- (void) decreaseAlertLevel;

- (NSArray *) launchPolice;
- (ShipEntity *) launchDefenseShip;
- (ShipEntity *) launchScavenger;
- (ShipEntity *) launchMiner;
/**Lazygun** added the following line*/
- (ShipEntity *) launchPirateShip;
- (ShipEntity *) launchShuttle;
- (void) launchEscort;
- (ShipEntity *) launchPatrol;

- (void) launchShipWithRole:(NSString *)role;

- (void) acceptPatrolReportFrom:(ShipEntity *)patrol_ship;

- (NSString *) acceptDockingClearanceRequestFrom:(ShipEntity *)other;
- (BOOL) requiresDockingClearance;
- (void) setRequiresDockingClearance:(BOOL)newValue;

- (BOOL) allowsFastDocking;
- (void) setAllowsFastDocking:(BOOL)newValue;

- (BOOL) allowsAutoDocking;
- (void) setAllowsAutoDocking:(BOOL)newValue;

- (NSString *) marketOverrideName;
- (BOOL) isRotatingStation;
- (BOOL) hasShipyard;

- (BOOL) suppressArrivalReports;
- (void) setSuppressArrivalReports:(BOOL)newValue;

- (BOOL) hasBreakPattern;
- (void) setHasBreakPattern:(BOOL)newValue;


@end



NSDictionary *OOMakeDockingInstructions(StationEntity *station, Vector coords, float speed, float range, NSString *ai_message, NSString *comms_message, BOOL match_rotation);
