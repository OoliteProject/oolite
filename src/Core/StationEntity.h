/*

StationEntity.h

ShipEntity subclass representing a space station or dockable ship.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#define STATION_ALERT_LEVEL_GREEN		0
#define STATION_ALERT_LEVEL_YELLOW		1
#define STATION_ALERT_LEVEL_RED			2

#define STATION_MAX_POLICE				8

#define STATION_DELAY_BETWEEN_LAUNCHES  6.0

#define MAX_DOCKING_STAGES				16

@interface StationEntity: ShipEntity
{
	
	NSMutableDictionary		*shipsOnApproach;
	NSMutableDictionary		*shipsOnHold;
	NSMutableArray			*launchQueue;
	double					last_launch_time;
	double					approach_spacing;
	int						alert_level;
	
	OOUniversalID			id_lock[MAX_DOCKING_STAGES];	// ship id's or NO_TARGET's
	
	int						max_police;					// max no. of police ships allowed
	int						max_defense_ships;			// max no. of defense ships allowed
	int						police_launched;
	
	int						max_scavengers;				// max no. of scavenger ships allowed
	int						scavengers_launched;
	
	int						equivalent_tech_level;
	double					equipment_price_factor;

	Vector					port_position;
	Quaternion				port_qrotation;
	Vector  				port_dimensions;
	ShipEntity*				port_model;
	
	BOOL					no_docking_while_launching;
	
	int						planet;
	
	NSMutableArray			*localMarket;
	NSMutableArray			*localPassengers;
	NSMutableArray			*localContracts;
	NSMutableArray			*localShipyard;
	
	int						docked_shuttles;
	double					last_shuttle_launch_time;
	double					shuttle_launch_interval;
	
	int						docked_traders;
	double					last_trader_launch_time;
	double					trader_launch_interval;
	
	double					last_patrol_report_time;
	double					patrol_launch_interval;
	
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

- (NSMutableArray *) initialiseLocalMarketWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor;
- (NSMutableArray *) initialiseLocalPassengersWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor;
- (NSMutableArray *) initialiseLocalContractsWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor;

- (int) equivalent_tech_level;
- (void) set_equivalent_tech_level:(int) value;

- (double) port_radius;

- (Vector) getPortPosition;

- (Vector) getBeaconPosition;

- (double) equipment_price_factor;

- (void) setPlanet:(PlanetEntity *)planet_entity;

- (PlanetEntity *) planet;

- (void) sanityCheckShipsOnApproach;

- (void) autoDockShipsOnApproach;

NSDictionary* instructions(int station_id, Vector coords, float speed, float range, NSString* ai_message, NSString* comms_message, BOOL match_rotation);
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

- (int) countShipsInLaunchQueueWithRole:(NSString *) a_role;

- (void) launchShip:(ShipEntity *) ship;

- (void) noteDockedShip:(ShipEntity *) ship;

////////////////////////////////////////////////////////////// AI methods...

- (void) increaseAlertLevel;

- (void) decreaseAlertLevel;

- (void) launchPolice;

- (void) launchDefenseShip;

- (void) launchScavenger;

- (void) launchMiner;

/**Lazygun** added the following line*/
- (void) launchPirateShip;

- (void) launchShuttle;

- (void) launchTrader;

- (void) launchEscort;

- (BOOL) launchPatrol;

- (void) launchShipWithRole:(NSString*) role;

- (void) acceptPatrolReportFrom:(ShipEntity*) patrol_ship;

- (void) acceptDockingClearanceRequestFrom:(ShipEntity *)other;

- (BOOL) isRotatingStation;

- (BOOL) hasShipyard;

@end
