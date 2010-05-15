/*

StationEntity.h

ShipEntity subclass representing a space station or dockable ship.

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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
#import "legacy_random.h"

typedef enum
{
	STATION_ALERT_LEVEL_GREEN = ALERT_CONDITION_GREEN,
	STATION_ALERT_LEVEL_YELLOW = ALERT_CONDITION_YELLOW,
	STATION_ALERT_LEVEL_RED = ALERT_CONDITION_RED
} OOStationAlertLevel;

#define STATION_MAX_POLICE				8

#define STATION_DELAY_BETWEEN_LAUNCHES  6.0

#define MAX_DOCKING_STAGES				16

#define DOCKING_CLEARANCE_WINDOW	126.0

@interface StationEntity: ShipEntity
{
	
	NSMutableDictionary		*shipsOnApproach;
	NSMutableDictionary		*shipsOnHold;
	NSMutableArray			*launchQueue;
	double					last_launch_time;
	double					approach_spacing;
	OOStationAlertLevel		alertLevel;
	
	ShipEntity				*id_lock[MAX_DOCKING_STAGES];	// OOWeakReferences to a ShipEntity
	
	unsigned				max_police;					// max no. of police ships allowed
	unsigned				max_defense_ships;			// max no. of defense ships allowed
	unsigned				defenders_launched;
	
	unsigned				max_scavengers;				// max no. of scavenger ships allowed
	unsigned				scavengers_launched;
	
	OOTechLevelID			equivalentTechLevel;
	float					equipmentPriceFactor;

	Vector					port_position;
	Quaternion				port_orientation;
	Vector  				port_dimensions;
	ShipEntity				*port_model;
	
	NSString				*dockingPatternModelFileName;
	
	NSString				*local_market;
	
	unsigned				no_docking_while_launching: 1,
							hasNPCTraffic: 1;
	
	OOUniversalID			planet;
	
	NSMutableArray			*localMarket;
	NSMutableArray			*localPassengers;
	NSMutableArray			*localContracts;
	NSMutableArray			*localShipyard;
	
	unsigned				docked_shuttles;
	double					last_shuttle_launch_time;
	double					shuttle_launch_interval;
	
	unsigned				docked_traders;
	double					last_trader_launch_time;
	double					trader_launch_interval;
	
	double					last_patrol_report_time;
	double					patrol_launch_interval;
	
	BOOL				suppress_arrival_reports;			
	
#if DOCKING_CLEARANCE_ENABLED
	BOOL 				requiresDockingClearance;	
#endif
	
}

- (void) setDockingPortModel:(ShipEntity*) dock_model :(Vector) dock_pos :(Quaternion) dock_q;

- (NSMutableArray *) localMarket;
- (void) setLocalMarket:(NSArray *) some_market;
- (NSMutableArray *) localPassengers;
- (void) setLocalPassengers:(NSArray *) some_market;
- (NSMutableArray *) localContracts;
- (void) setLocalContracts:(NSArray *) some_market;
- (NSMutableArray *) localShipyard;
- (void) setLocalShipyard:(NSArray *) some_market;

- (NSMutableArray *) initialiseLocalMarketWithRandomFactor:(int) random_factor;
- (NSMutableArray *) initialiseMarketWithSeed:(Random_Seed) s_seed andRandomFactor:(int) random_factor;

- (OOTechLevelID) equivalentTechLevel;
- (void) setEquivalentTechLevel:(OOTechLevelID) value;

- (double) port_radius;

- (Vector) getPortPosition;

- (Vector) getBeaconPosition;

- (float) equipmentPriceFactor;

- (void) setPlanet:(OOPlanetEntity *)planet_entity;

- (OOPlanetEntity *) planet;

- (unsigned) dockedContractors;
- (unsigned) dockedPolice;
- (unsigned) dockedDefenders;

- (void) sanityCheckShipsOnApproach;

- (void) autoDockShipsOnApproach;

- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *) ship;
- (void) addShipToShipsOnApproach:(ShipEntity *) ship;

- (Vector) portUpVector;
- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox) bb;

- (BOOL) shipIsInDockingCorridor:(ShipEntity*) ship;

- (BOOL) dockingCorridorIsEmpty;

- (void) clearDockingCorridor;

- (void) clear;


- (void) abortAllDockings;

- (void) abortDockingForShip:(ShipEntity *) ship;

- (void) addShipToLaunchQueue:(ShipEntity *) ship;

- (unsigned) countShipsInLaunchQueueWithPrimaryRole:(NSString *)role;

- (void) launchShip:(ShipEntity *) ship;

- (ShipEntity *) launchIndependentShip:(NSString*) role;

- (void) noteDockedShip:(ShipEntity *) ship;

- (BOOL)hasNPCTraffic;
- (void)setHasNPCTraffic:(BOOL)flag;

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

- (void) launchShipWithRole:(NSString*) role;

- (void) acceptPatrolReportFrom:(ShipEntity*) patrol_ship;

#if DOCKING_CLEARANCE_ENABLED
- (NSString *) acceptDockingClearanceRequestFrom:(ShipEntity *)other;
- (BOOL) requiresDockingClearance;
- (void) setRequiresDockingClearance:(BOOL)newValue;
#endif

- (NSString *) dockingPatternModelFileName;
- (NSString *) marketName;
- (BOOL) isRotatingStation;
- (BOOL) hasShipyard;

- (BOOL) suppressArrivalReports;
- (void) setSuppressArrivalReports:(BOOL)newValue;

@end
