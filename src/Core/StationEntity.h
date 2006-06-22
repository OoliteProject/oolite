//
//  StationEntity.h
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import <Foundation/Foundation.h>

#include "entities.h"

#define STATION_ALERT_LEVEL_GREEN		0
#define STATION_ALERT_LEVEL_YELLOW		1
#define STATION_ALERT_LEVEL_RED			2

#define STATION_MAX_POLICE				8

#define STATION_DELAY_BETWEEN_LAUNCHES  6.0

#define MAX_DOCKING_STAGES				16

@interface StationEntity : ShipEntity {
	
	NSMutableDictionary		*shipsOnApproach;
	NSMutableArray			*launchQueue;
	double					last_launch_time;
	double					approach_spacing;
	int						alert_level;
	
	int						id_lock[MAX_DOCKING_STAGES];	// ship id's or NO_TARGET's
	
	int						max_police;					// max no. of police ships allowed
	int						max_defense_ships;			// max no. of defense ships allowed
	int						police_launched;
	
	int						max_scavengers;				// max no. of scavenger ships allowed
	int						scavengers_launched;
	
	int						equivalent_tech_level;
	double					equipment_price_factor;

	double					port_radius;
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
