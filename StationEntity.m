//
//  StationEntity.m
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

#import "StationEntity.h"
#import "entities.h"

#import "AI.h"


@implementation StationEntity

- (void) acceptDistressMessageFrom:(ShipEntity *)other
{
	if (self != [universe station])
	{
		//NSLog(@"DEBUG acceptDistressMessageFrom rejected from sub-station '%@'", name);
		return;
	}
	
	//NSLog(@"DEBUG %@ %d responding to distress message from %@ %d", name, universal_id, [other name], [other universal_id]);
	{
		int police_target = [[other getPrimaryTarget] universal_id];
		[(ShipEntity *)[universe entityForUniversalID:police_target] markAsOffender:8];
		if (police_launched < STATION_MAX_POLICE)
		{
			ShipEntity  *police_ship;
			if (![universe entityForUniversalID:police_target])
			{
				[shipAI reactToMessage:@"TARGET_LOST"];
				return;
			}
				
			//NSLog(@"DEBUG Launching Police Ship to intercept %@",[universe entityForUniversalID:police_target]);
				
			police_ship = [universe getShipWithRole:@"police"];   // retain count = 1
			[police_ship addTarget:[universe entityForUniversalID:police_target]];
			[police_ship setScanClass: CLASS_POLICE];
			
			//[police_ship setReportAImessages:YES]; // debug
			
			[[police_ship getAI] setStateMachine:@"policeInterceptAI.plist"];
			[self addShipToLaunchQueue:police_ship];
			[police_ship release];
			police_launched++;
		}
		no_docking_while_launching = YES;
		[self abortAllDockings];
	}
}

- (int) equivalent_tech_level
{
	return equivalent_tech_level;
}

- (void) set_equivalent_tech_level:(int) value
{
	equivalent_tech_level = value;
}

- (double) port_radius
{
	return port_radius;
}

- (Vector) getPortPosition
{
	Vector result = position;
	result.x += port_position.x * v_right.x + port_position.y * v_up.x + port_position.z * v_forward.x;
	result.y += port_position.x * v_right.y + port_position.y * v_up.y + port_position.z * v_forward.y;
	result.z += port_position.x * v_right.z + port_position.y * v_up.z + port_position.z * v_forward.z;
	return result;
}

- (double) equipment_price_factor
{
	return equipment_price_factor;
}


- (NSMutableArray *) localMarket
{
	return localMarket;
}

- (void) setLocalMarket:(NSArray *) some_market
{
	if (localMarket)
		[localMarket release];
	localMarket = [[NSMutableArray alloc] initWithArray:some_market];
}

- (NSMutableArray *) localPassengers
{
	return localPassengers;
}

- (void) setLocalPassengers:(NSArray *) some_market
{
	if (localPassengers)
		[localPassengers release];
	localPassengers = [[NSMutableArray alloc] initWithArray:some_market];
}

- (NSMutableArray *) localContracts
{
	return localContracts;
}

- (void) setLocalContracts:(NSArray *) some_market
{
	if (localContracts)
		[localContracts release];
	localContracts = [[NSMutableArray alloc] initWithArray:some_market];
}

- (NSMutableArray *) localShipyard
{
	return localShipyard;
}

- (void) setLocalShipyard:(NSArray *) some_market
{
	if (localShipyard)
		[localShipyard release];
	localShipyard = [[NSMutableArray alloc] initWithArray:some_market];
}

- (NSMutableArray *) initialiseLocalMarketWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor
{
	//NSLog(@"///// Initialising local market for station %@ with roles %@",self,[self roles]);
	int rf = (random_factor ^ universal_id) & 0xff;
	int economy = [(NSNumber *)[[universe generateSystemData:s_seed] objectForKey:KEY_ECONOMY] intValue];
	if (localMarket)
		[localMarket release];
	localMarket = [[NSMutableArray alloc] initWithArray:[universe commodityDataForEconomy:economy andStation:self andRandomFactor:rf]];
	return localMarket;
}

- (NSMutableArray *) initialiseLocalPassengersWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor
{
	//NSLog(@"///// Initialising local market for station %@ with roles %@",self,[self roles]);
	if (localPassengers)
		[localPassengers release];
	localPassengers = [[NSMutableArray alloc] initWithArray:[universe passengersForSystem:s_seed atTime:[[(PlayerEntity*)[universe entityZero] clock_number] intValue]]];
	return localPassengers;
}

- (NSMutableArray *) initialiseLocalContractsWithSeed: (Random_Seed) s_seed andRandomFactor: (int) random_factor
{
	//NSLog(@"///// Initialising local market for station %@ with roles %@",self,[self roles]);
	if (localContracts)
		[localContracts release];
	localContracts = [[NSMutableArray alloc] initWithArray:[universe contractsForSystem:s_seed atTime:[[(PlayerEntity*)[universe entityZero] clock_number] intValue]]];
	return localContracts;
}

- (void) setUniverse:(Universe *)univ
{
    if (univ)
    {
        if (universe)	[universe release];
        universe = [univ retain];
    }
	else
	{
        if (universe)	[universe release];
        universe = nil;
		[localMarket release];
		localMarket = nil;
    }
	//
	// if we have a universal id then we can proceed to set up any
	// stuff that happens when we get added to the universe
	//
	if (universal_id != NO_TARGET)
	{
		// set up escorts
		//
		if (status == STATUS_IN_FLIGHT)	// just popped into existence
		{
			if ((!escortsAreSetUp)&&(n_escorts > 0))
				[self setUpEscorts];
		}
		else
		{
			escortsAreSetUp = YES;	// we don't do this ourself!
		}
	}
	
	//
	//	set subentities universe
	//
	if (sub_entities != nil)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			[(Entity *)[sub_entities objectAtIndex:i] setUniverse:univ];
			[(Entity *)[sub_entities objectAtIndex:i] setOwner:self];
		}
	}
}

- (void) setPlanet:(PlanetEntity *)planet_entity
{
	if (planet_entity)
		planet = [planet_entity universal_id];
	else
		planet = NO_TARGET;
}

- (PlanetEntity *) planet
{
	return (PlanetEntity *)[universe entityForUniversalID:planet];
}

- (void) sanityCheckShipsOnApproach
{
	int i;
	NSArray*	ships = [shipsOnApproach allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ((sid == NO_TARGET)||(![universe entityForUniversalID:sid]))
		{
			[shipsOnApproach removeObjectForKey:[ships objectAtIndex:i]];
			if ([shipsOnApproach count] == 0)
				[shipAI message:@"DOCKING_COMPLETE"];
		}
	}
	if ([shipsOnApproach count] == 0)
	{
		last_launch_time = [universe getTime];
		approach_spacing = 0.0;
	}
}

- (void) abortAllDockings
{
	int i;
	NSArray*	ships = [shipsOnApproach allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ([universe entityForUniversalID:sid])
			[[(ShipEntity *)[universe entityForUniversalID:sid] getAI] message:@"DOCKING_ABORTED"];
		[shipsOnApproach removeObjectForKey:[ships objectAtIndex:i]];
	}
	[shipAI message:@"DOCKING_COMPLETE"];
	last_launch_time = [universe getTime];
	approach_spacing = 0.0;
}


- (void) autoDockShipsOnApproach
{
	int i;
	NSArray*	ships = [shipsOnApproach allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ([universe entityForUniversalID:sid])
			[(ShipEntity *)[universe entityForUniversalID:sid] enterDock:self];
		[shipsOnApproach removeObjectForKey:[ships objectAtIndex:i]];
	}
	[shipAI message:@"DOCKING_COMPLETE"];
}


- (Vector) nextDockingCoordinatesForShip:(ShipEntity *) ship
{
	Vector		coords;
	int			ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];
	
	if (!ship)
		return position;
	
	if ((ship->isPlayer)&&([ship legal_status] > 50))
	{
		[[ship getAI] message:@"DOCKING_REFUSED"];
		[self sendExpandedMessage:@"[station-docking-refused-to-fugitive]" toShip:ship];
		return ship->position;  // hold position
	}
	
	
	if (![shipsOnApproach objectForKey:shipID])
	{
//		NSLog(@"DEBUG %@ %d noting docking request", name, universal_id);
		[shipAI message:@"DOCKING_REQUESTED"];	// note the request.
	}
	
	if (no_docking_while_launching)
	{
//		NSLog(@"DEBUG %@ %d refusing because of no docking while launching", name, universal_id);
		[[ship getAI] message:@"TRY_AGAIN_LATER"];
		return ship->position;  // hold position
	}
	
	if	((magnitude2(velocity) > 1.0)||
		((scan_class != CLASS_STATION)&&((fabs(flight_pitch) > 0.01)||(fabs(flight_roll) > 0.01))))		// no docking while moving
	{
//		NSLog(@"DEBUG %@ %d refusing docking to %@ because of motion", name, universal_id, [ship name]);
		[shipAI message:@"DOCKING_REQUESTED"];	// note the request.
		[[ship getAI] message:@"HOLD_POSITION"];// send HOLD
		return ship->position;  // hold position
	}
	
	if (![shipsOnApproach objectForKey:shipID])
	{		
		Vector v_off;
		// will select a direction for offset based on the shipID
		//
		int offset_id = ship_id & 0xf;	// 16  point compass
		double c = cos(offset_id * PI * ONE_EIGHTH);
		double s = sin(offset_id * PI * ONE_EIGHTH);
		v_off.x = c * v_up.x + s * v_right.x;
		v_off.y = c * v_up.y + s * v_right.y;
		v_off.z = c * v_up.z + s * v_right.z;
		//
		NSMutableArray*		coordinatesStack =  [NSMutableArray arrayWithCapacity:3];
		NSString*			speedMessage = @"SLOW";
		double offset = 6 * port_radius;
		double offset2 = 6 * port_radius + approach_spacing;
		approach_spacing += 500;  // space out incoming ships by 500m
		//
		int docking_stage = 0;
		//
		while (offset >= 0.0)
		{
			//
			NSMutableDictionary*	nextCoords =	[NSMutableDictionary dictionaryWithCapacity:3];
			
			Vector rel_coords = make_vector( s * offset2, c * offset2, offset - port_radius);

			Vector coords = [self getPortPosition];	// docking slit exit position

			coords.x -= port_radius*v_forward.x;	// correct back to 'center'
			coords.y -= port_radius*v_forward.y;	//
			coords.z -= port_radius*v_forward.z;	//
			coords.x += offset*v_forward.x;
			coords.y += offset*v_forward.y;
			coords.z += offset*v_forward.z;
			if (offset2 > 0)
			{
				Vector c0 = coords;
				Vector c1 = coords;
				c0.x += offset2*v_off.x;
				c0.y += offset2*v_off.y;
				c0.z += offset2*v_off.z;
				c1.x -= offset2*v_off.x;
				c1.y -= offset2*v_off.y;
				c1.z -= offset2*v_off.z;
				if (distance2(c0,ship->position) < distance2(c1,ship->position))
				{
					coords = c0;
				}
				else
				{
					coords = c1;
					rel_coords = make_vector( -s * offset2, -c * offset2, offset - port_radius);
				}
				offset2 = 0;	// only the first one is offset to one side
			}
//			//NSLog(@"docking coordinates [%d] = (%.2f, %.2f, %.2f)", 3-i, coords.x, coords.y, coords.z);
			[nextCoords setObject:[NSNumber numberWithInt:docking_stage++] forKey:@"docking_stage"];
//			//
			[nextCoords setObject:[NSNumber numberWithFloat:rel_coords.x] forKey:@"rx"];
			[nextCoords setObject:[NSNumber numberWithFloat:rel_coords.y] forKey:@"ry"];
			[nextCoords setObject:[NSNumber numberWithFloat:rel_coords.z] forKey:@"rz"];

			[nextCoords setObject:[NSString stringWithFormat:@"%@",speedMessage] forKey:@"speed"];
			[coordinatesStack addObject:nextCoords];
			offset -= port_radius;
			if (offset <= 3 * port_radius)
				speedMessage = @"DEAD_SLOW";
		}
				
		[shipsOnApproach setObject:coordinatesStack forKey:shipID];
		
		// COMM-CHATTER
		if (self == [universe station])
			[self sendExpandedMessage: @"[station-welcome]" toShip: ship];
		else
			[self sendExpandedMessage: @"[docking-welcome]" toShip: ship];

	}

	//
	//	shipsOnApproach now has an entry for the ship.
	//
	if ([shipsOnApproach objectForKey:shipID])
	{
		NSMutableArray* coordinatesStack = (NSMutableArray *)[shipsOnApproach objectForKey:shipID];
//		NSLog(@"DEBUG coordinatesStack = %@", [coordinatesStack description]);

		if ([coordinatesStack count] == 0)
		{
			[[ship getAI] message:@"HOLD_POSITION"];	// not docked - try again
			return ship->position;
		}
			
		NSMutableDictionary* nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:0];
		int docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
		NSString* speedMessage = (NSString *)[nextCoords objectForKey:@"speed"];

		Vector rel_coords;
		rel_coords.x = [(NSNumber *)[nextCoords objectForKey:@"rx"] floatValue];
		rel_coords.y = [(NSNumber *)[nextCoords objectForKey:@"ry"] floatValue];
		rel_coords.z = [(NSNumber *)[nextCoords objectForKey:@"rz"] floatValue];
		
//		NSLog(@"DEBUG New system coordinates [%.3f, %.3f, %.3f]", rel_coords.x, rel_coords.y, rel_coords.z);
		Vector vi = v_right;
		Vector vj = v_up;
		Vector vk = v_forward;
		if (scan_class == CLASS_STATION)
		{
			Entity* the_sun = [universe sun];
			Vector v0 = (the_sun)? the_sun->position : make_vector(1,0,0);
			vi = cross_product(vk,v0);
			vj = cross_product(vk,vi);
		}
		coords = [self getPortPosition];
		coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
		coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
		coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
		
		double allowed_range = 100.0 + ship->collision_radius;
		
		Vector ship_position = ship->position;
		Vector delta = coords;
		delta.x -= ship_position.x;	delta.y -= ship_position.y;	delta.z -= ship_position.z;
	
		if (magnitude2(delta) > allowed_range * allowed_range)	// further than 100m from the coordinates - do not remove them from the stack!
		{
//			NSLog(@"DEBUG ::::: %@ %d is %.1fm from its docking coordinates for docking stage %d.", [ship name], ship_id, sqrt(magnitude2(delta)), docking_stage);
//			NSLog(@"DEBUG ::::: %@ %d Continue to given coordinates...", [ship name], ship_id);
			
//			// debug
//			[ship setReportAImessages:YES];
			

//			NSLog(@">>:::: %@ %d docking stage %d", [ship name], [ship universal_id], docking_stage);
					
			if (docking_stage == 0)
			{
//				// COMM-CHATTER
//				if (self == [universe station])
//					[self sendExpandedMessage: @"[station-welcome]" toShip: ship];
//				else
//					[self sendExpandedMessage: @"[docking-welcome]" toShip: ship];
//
				[[ship getAI] message:@"APPROACH_START"];
			}
			else
			{
				if ([speedMessage isEqual:@"DEAD_SLOW"])
					[[ship getAI] message:@"APPROACH_STATION"];
				else
					[[ship getAI] message:@"APPROACH_COORDINATES"];
			}
			
			return coords;
		}
		else
		{
			// save the current coordinates
			Vector oldCoords = coords;

//			NSLog(@"::>>:: %@ %d docking stage %d", [ship name], [ship universal_id], docking_stage);
					
			if (docking_stage == 1)
			{
				// COMM-CHATTER
				if (self == [universe station])
					[self sendExpandedMessage: @"[station-begin-final-aproach]" toShip: ship];
				else
					[self sendExpandedMessage: @"[docking-begin-final-aproach]" toShip: ship];
			}
			
			if ([coordinatesStack count] < 2)
			{
//				NSLog(@"DEBUG ::::: %@ %d Final docking coordinates ---> (%.2f, %.2f, %.2f)", [ship name], ship_id, coords.x, coords.y, coords.z);
				[[ship getAI] message:@"APPROACH_STATION"];
				return coords;
			}

			// get the NEXT coordinates
			nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:1];
			docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
			speedMessage = (NSString *)[nextCoords objectForKey:@"speed"];
			
			// set the docking coordinates
			rel_coords.x = [(NSNumber *)[nextCoords objectForKey:@"rx"] floatValue];
			rel_coords.y = [(NSNumber *)[nextCoords objectForKey:@"ry"] floatValue];
			rel_coords.z = [(NSNumber *)[nextCoords objectForKey:@"rz"] floatValue];
			Vector vi = v_right;
			Vector vj = v_up;
			Vector vk = v_forward;
			if (scan_class == CLASS_STATION)
			{
				Entity* the_sun = [universe sun];
				Vector v0 = (the_sun)? the_sun->position : make_vector(1,0,0);
				vi = cross_product(vk,v0);
				vj = cross_product(vk,vi);
			}
			coords = [self getPortPosition];
			coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
			coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
			coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
			
			int i;	// clear any previously owned docking stages
			for (i = 1; i < MAX_DOCKING_STAGES; i++)
				if ((id_lock[i] == ship_id)||([universe entityForUniversalID:id_lock[i]] == nil))
					id_lock[i] = NO_TARGET;
					
			if ((id_lock[docking_stage] == NO_TARGET)&&(id_lock[docking_stage + 1] == NO_TARGET))	// check two stages ahead
			{
				id_lock[docking_stage] = ship_id;	// claim this docking stage
				
				//remove the previous stage from the stack
				[coordinatesStack removeObjectAtIndex:0];

//				NSLog(@"DEBUG ::::: %@ %d Next docking coordinates ---> (%.2f, %.2f, %.2f)", [ship name], ship_id, coords.x, coords.y, coords.z);
				
				//determine the approach speed advice
				if ([speedMessage isEqual:@"DEAD_SLOW"])
					[[ship getAI] message:@"APPROACH_STATION"];
				else
					[[ship getAI] message:@"APPROACH_COORDINATES"];
				
				// show the locked approach positions
//				NSLog(@"DEBUG ::::: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d <<",
//					id_lock[10],id_lock[9],id_lock[8],id_lock[7],id_lock[6],id_lock[5],id_lock[4],id_lock[3],id_lock[2],id_lock[1]);
				
				return coords;
			}
			else
			{
//				NSLog(@"DEBUG ::::: %@ %d Hold position ...", [ship name], ship_id);
				[[ship getAI] message:@"HOLD_POSITION"];
				
				if (![nextCoords objectForKey:@"hold_message_given"])
				{
					// COMM-CHATTER
					[universe clearPreviousMessage];
					[self sendExpandedMessage: @"[station-hold-position]" toShip: ship];
					[nextCoords setObject:@"YES" forKey:@"hold_message_given"];
				}
				
				return oldCoords;
			}
		}
	}
	
	return coords;
}

- (double) approachSpeedForShip:(ShipEntity *) ship
{
	int			ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];

	double approach_speed = 50.0;
	if ([shipsOnApproach objectForKey:shipID])
	{
		NSMutableArray* coordinatesStack = (NSMutableArray *)[shipsOnApproach objectForKey:shipID];
		NSDictionary* nextCoords = (NSDictionary *)[coordinatesStack objectAtIndex:0];
		NSString* speedMessage = (NSString *)[nextCoords objectForKey:@"speed"];
		if ([coordinatesStack count] > 0)
		{
			int next_docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
			
			if (id_lock[next_docking_stage] == NO_TARGET)
			{
				if ([speedMessage isEqual:@"DEAD_SLOW"])
					approach_speed = 25.0;
				else
					approach_speed = 50.0;
			}
			else
				approach_speed = 1.0;	// the next docking stage is not clear - go slow
		}
	}
	return approach_speed;
}

- (void) abortDockingForShip:(ShipEntity *) ship
{
	int ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d",ship_id];
	if ([universe entityForUniversalID:[ship universal_id]])
		[[(ShipEntity *)[universe entityForUniversalID:[ship universal_id]] getAI] message:@"DOCKING_ABORTED"];
	if ([shipsOnApproach objectForKey:shipID])
	{
		[shipsOnApproach removeObjectForKey:shipID];
		if ([shipsOnApproach count] == 0)
			[shipAI message:@"DOCKING_COMPLETE"];
	}
		
	int i;	// clear any previously owned docking stages
	for (i = 1; i < MAX_DOCKING_STAGES; i++)
		if ((id_lock[i] == ship_id)||([universe entityForUniversalID:id_lock[i]] == nil))
			id_lock[i] = NO_TARGET;
			
//	NSLog(@"DEBUG ::::: %@ %d Aborted docking", [ship name], ship_id);
//	NSLog(@"DEBUG ::::: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d <<",
//		id_lock[10],id_lock[9],id_lock[8],id_lock[7],id_lock[6],id_lock[5],id_lock[4],id_lock[3],id_lock[2],id_lock[1]);
				
}

- (Vector) portUpVector
{
	if (scan_class == CLASS_STATION)
		return v_right; // because the slot is horizontal dammit
	
	Vector result = vector_right_from_quaternion( quaternion_multiply( port_qrotation, q_rotation));
	
	result.x = - result.x;	result.y = - result.y;	result.z = - result.z;
	
//	NSLog(@"DEBUG %@ portUpVector = [%.3f, %.3f, %.3f] v_up = [%.3f, %.3f, %.3f]", self,
//		result.x, result.y, result.z, v_up.x, v_up.y, v_up.z);
	
	return result;
}

//////////////////////////////////////////////// from superclass

- (id) init
{
	self = [super init];
	
	shipsOnApproach = [[NSMutableDictionary alloc] initWithCapacity:5]; // alloc retains
	launchQueue = [[NSMutableArray alloc] initWithCapacity:16]; // retained
		
	int i;
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		id_lock[i] = NO_TARGET;

	alert_level = 0;
	police_launched = 0;
	last_launch_time = 0.0;
	no_docking_while_launching = NO;
	
	localMarket = nil;
	
	// local specials
	equivalent_tech_level = NSNotFound;
	equipment_price_factor = 1.0;
	port_radius = 500.0;
	approach_spacing = 0.0;
	
	max_scavengers = 3;
	max_defense_ships = 3;
	max_police = STATION_MAX_POLICE;
	police_launched = 0;
	scavengers_launched = 0;
	
	docked_shuttles = ranrot_rand() % 4;   // 0..3;
	last_shuttle_launch_time = 0.0;
	shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
	last_shuttle_launch_time = - (ranrot_rand() % 60) * shuttle_launch_interval / 60.0;
	
	docked_traders = 1 + (ranrot_rand() % 3);   // 1..3;
	last_trader_launch_time = 0.0;
	trader_launch_interval = ((ranrot_rand() % 10) + 20.0) * 60.0;  // every few minutes
	last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	
	last_patrol_report_time = 0.0;
	patrol_launch_interval = 300.0;	// 5 minutes
	last_patrol_report_time -= patrol_launch_interval;
	//
	isShip = YES;
	isStation = YES;
	
	return self;
}

- (void) reinit
{
	[super reinit];
	
	if (localMarket) [localMarket release];
	localMarket = nil;
	
	if (localPassengers) [localPassengers release];
	localPassengers = nil;
	
	if (localContracts) [localContracts release];
	localContracts = nil;
	
	if (localShipyard) [localShipyard release];
	localShipyard = nil;
	
	if (shipsOnApproach) [shipsOnApproach release];
	shipsOnApproach = [[NSMutableDictionary alloc] initWithCapacity:5]; // alloc retains
	
	if (launchQueue) [launchQueue release];
	launchQueue = [[NSMutableArray alloc] initWithCapacity:16]; // retained

	int i;
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		id_lock[i] = NO_TARGET;

	alert_level = 0;
	police_launched = 0;
	last_launch_time = 0.0;
	no_docking_while_launching = NO;
	//
	isShip = YES;
	isStation = YES;
}

- (id) initWithDictionary:(NSDictionary *) dict
{
	port_radius = 500.0;	// may be overwritten by [super initWithDictionary:dict]
	
	self = [super initWithDictionary:dict];
	
	//NSLog(@"DEBUG setting up station '%@' from dict:%@",name,[dict description]);
	
	if ([dict objectForKey:@"equivalent_tech_level"])
		equivalent_tech_level = [(NSNumber *)[dict objectForKey:@"equivalent_tech_level"] intValue];
	else
		equivalent_tech_level = NSNotFound;
	
	if ([dict objectForKey:@"equipment_price_factor"])
		equipment_price_factor = [(NSNumber *)[dict objectForKey:@"equipment_price_factor"] doubleValue];
	else
		equipment_price_factor = 1.0;
	
	
	shipsOnApproach = [[NSMutableDictionary alloc] initWithCapacity:16]; // alloc retains
	launchQueue = [[NSMutableArray alloc] initWithCapacity:16]; // retained
	alert_level = 0;
	police_launched = 0;
	last_launch_time = 0.0;
	approach_spacing = 0.0;
	
	localMarket = nil;
	
	docked_shuttles = ranrot_rand() % 4;   // 0..3;
	last_shuttle_launch_time = 0.0;
	shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
	last_shuttle_launch_time = - (ranrot_rand() % 60) * shuttle_launch_interval / 60.0;
	
	docked_traders = 1 + (ranrot_rand() % 3);   // 1..3;
	last_trader_launch_time = 0.0;
	trader_launch_interval = ((ranrot_rand() % 10) + 20.0) * 60.0;  // every few minutes
	last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	
	int i;
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		id_lock[i] = NO_TARGET;

	isShip = YES;
	isStation = YES;

	return self;
}

- (void) setUpShipFromDictionary:(NSDictionary *) dict
{
	[super setUpShipFromDictionary:dict];
	
	if ([dict objectForKey:@"port_radius"])   // this gets set for rock-hermits and other specials, otherwise it's 500m
		port_radius = [(NSNumber *)[dict objectForKey:@"port_radius"] doubleValue];
	else
		port_radius = 500.0;
	
	// set up a the docking port
	//
	port_position = make_vector( 0, 0, port_radius);	// forward
	quaternion_set_identity(&port_qrotation);
	port_dimensions = make_vector( 69, 69, 250);		// base port size (square)
	if ([dict objectForKey:@"subentities"])
	{
		int i;
		NSArray *subs = (NSArray *)[dict objectForKey:@"subentities"];
		for (i = 0; i < [subs count]; i++)
		{
			NSArray* details = [(NSString *)[subs objectAtIndex:i] componentsSeparatedByString:@" "];
			if (([details count] == 8)&&([(NSString *)[details objectAtIndex:0] isEqual:@"dock"]))
			{
				port_position.x = [(NSString *)[details objectAtIndex:1] floatValue];
				port_position.y = [(NSString *)[details objectAtIndex:2] floatValue];
				port_position.z = [(NSString *)[details objectAtIndex:3] floatValue];
				port_qrotation.w = [(NSString *)[details objectAtIndex:4] floatValue];
				port_qrotation.x = [(NSString *)[details objectAtIndex:5] floatValue];
				port_qrotation.y = [(NSString *)[details objectAtIndex:6] floatValue];
				port_qrotation.z = [(NSString *)[details objectAtIndex:7] floatValue];
				port_dimensions = make_vector( 32, 96, 250);	// coriolis/icos/dodec port size (oblong)
			}
			quaternion_normalise(&port_qrotation);
		}
	}

	if ([dict objectForKey:@"port_dimensions"])   // this can be set for rock-hermits and other specials
	{
		NSArray* tokens = [(NSString*)[dict objectForKey:@"port_dimensions"] componentsSeparatedByString:@"x"];
		if ([tokens count] == 3)
		{
			port_dimensions = make_vector(	[(NSString*)[tokens objectAtIndex:0] floatValue],
											[(NSString*)[tokens objectAtIndex:1] floatValue],
											[(NSString*)[tokens objectAtIndex:2] floatValue]);
		}
	}

	if ([dict objectForKey:@"equivalent_tech_level"])
		equivalent_tech_level = [(NSNumber *)[dict objectForKey:@"equivalent_tech_level"] intValue];
	else
		equivalent_tech_level = NSNotFound;
	
	if ([dict objectForKey:@"max_scavengers"])
		max_scavengers = [(NSNumber *)[dict objectForKey:@"max_scavengers"] intValue];
	else
		max_scavengers = 3;
	
	if ([dict objectForKey:@"max_defense_ships"])
		max_defense_ships = [(NSNumber *)[dict objectForKey:@"max_defense_ships"] intValue];
	else
		max_defense_ships = 3;
	
	if ([dict objectForKey:@"max_police"])
		max_police = [(NSNumber *)[dict objectForKey:@"max_police"] intValue];
	else
		max_police = STATION_MAX_POLICE;
	
	if ([dict objectForKey:@"equipment_price_factor"])
		equipment_price_factor = [(NSNumber *)[dict objectForKey:@"equipment_price_factor"] doubleValue];
	else
		equipment_price_factor = 1.0;
		
	police_launched = 0;
	scavengers_launched = 0;
	approach_spacing = 0.0;
	[shipsOnApproach removeAllObjects];
	[launchQueue removeAllObjects];
	last_launch_time = 0.0;
	
	int i;
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		id_lock[i] = NO_TARGET;

	//localMarket = nil;

	if (([roles isEqual:@"coriolis"])||([roles isEqual:@"dodecahedron"])||([roles isEqual:@"icosahedron"]))
	{
		docked_shuttles = ranrot_rand() % 4;   // 0..3;
		last_shuttle_launch_time = 0.0;
		shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
		last_shuttle_launch_time = - (ranrot_rand() % 60) * shuttle_launch_interval / 60.0;
		docked_traders = 1 + (ranrot_rand() % 3);   // 1..3;
		last_trader_launch_time = 0.0;
		trader_launch_interval = ((ranrot_rand() % 10) + 20.0) * 60.0;  // every few minutes
		last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	}
	else
	{
		docked_shuttles = 0;
		docked_traders = 0;   // 1..3;
	}
	
}

- (void) dealloc
{
	if (shipsOnApproach)	[shipsOnApproach release];
	if (launchQueue)		[launchQueue release];
	
	if (localMarket)		[localMarket release];
	if (localPassengers)	[localPassengers release];
	if (localContracts)		[localContracts release];
	if (localShipyard)		[localShipyard release];
	
    [super dealloc];
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (!other)
		return NO;
	//
	//  check if other is within docking corridor
	//
	//NSLog(@"Checking Station CloseContact...");
	//
	if ([universe strict]&&(self != [universe station])&&(other->isPlayer))
	{
		// in a strict universe the player can only dock with the main station
		return [super checkCloseCollisionWith:other];
	}
	//
	if (other->isShip)
	{
		Vector rel_pos, delta, prt_pos;
		// port dimensions..
		double ww = port_dimensions.x;
		double hh = port_dimensions.y;
		double dd = port_dimensions.z;
		// reduced dimensions for fudging..
		double w1 = ww * 0.75;
		double h1 = hh * 0.75;
		ShipEntity* ship =  (ShipEntity *) other;
		double radius =		ship->collision_radius;
		
		// check if the ship is too big for the port and fudge things accordingly
		BoundingBox shipbb = [ship getBoundingBox];
		float ff = 1.0;
		while	((shipbb.max_y * ff > w1)||(shipbb.min_y * ff < -w1)
				||(shipbb.max_x * ff > h1)||(shipbb.min_x * ff < -h1))
			ff /= 1.25;
				
		//NSLog(@"DEBUG Checking docking corridor...");
		prt_pos = [self getPortPosition];
		rel_pos = ship->position;
		rel_pos.x -= prt_pos.x;
		rel_pos.y -= prt_pos.y;
		rel_pos.z -= prt_pos.z;
		delta.x = dot_product(rel_pos, v_right);
		delta.y = dot_product(rel_pos, v_up);
		delta.z = dot_product(rel_pos, v_forward);
		BOOL in_lane = YES;
		
		if ((delta.x > boundingBox.max_x + radius)||(delta.x < boundingBox.min_x - radius))
			in_lane = NO;
		if ((delta.y > boundingBox.max_y + radius)||(delta.y < boundingBox.min_y - radius))
			in_lane = NO;
		if ((delta.z > boundingBox.max_z + radius)||(delta.z < boundingBox.min_z - radius))
			in_lane = NO;
			
		if (!in_lane)
			return [super checkCloseCollisionWith:other];
		//
		// within bounding box at this point
		//
		// get bounding box relative to the port in this station's orientation
		Quaternion q0 = quaternion_multiply(port_qrotation, q_rotation);
		Vector vi = vector_right_from_quaternion(q0);
		Vector vj = vector_up_from_quaternion(q0);
		Vector vk = vector_forward_from_quaternion(q0);
		BoundingBox arbb = [other findBoundingBoxRelativeToPosition:prt_pos InVectors: vi: vj: vk];
		//
		// apply fudge factor
		arbb.max_x *= ff;
		arbb.max_y *= ff;
		arbb.min_x *= ff;
		arbb.min_y *= ff;
		//
//		if (other == [universe entityZero])
//			NSLog(@"DEBUG Docking corridor placement (%3.2f,%3.2f,%3.2f) <[%3.1f,%3.1f,%3.1f]-[%3.1f,%3.1f,%3.1f] (/%1.3f)>",
//				delta.x, delta.y, delta.z,
//				arbb.max_x, arbb.max_y, arbb.max_z,
//				arbb.min_x, arbb.min_y, arbb.min_z,
//				1.0 / ff);
		if  (	(arbb.min_x > -ww)&&	(arbb.max_x < ww)	// docking slit is 90 degrees to vertical
			&&	(arbb.min_y > -hh)&&	(arbb.max_y < hh)	// docking slit is 90 degrees to vertical
			&&	(arbb.min_z > -dd))
		{
			if (arbb.max_z < 0)
				[ship enterDock:self];
			return NO;
		}
		else
		{
//			NSLog(@"DEBUG Outside the lane!");
			if  (	(arbb.min_x > -1.5 * ww)&&	(arbb.max_x < 1.5 * ww)
				&&	(arbb.min_y > -1.5 * hh)&&	(arbb.max_y < 1.5 * hh)
				&&	(arbb.min_z > -dd)&&		(arbb.min_z < 0))	// inside the station
			{
				// damage the ship according to velocity but don't collide
				[ship takeScrapeDamage: 5 * [universe getTimeDelta]*[ship flight_speed] from:self];
				
				// adjust the ship back to the center of the port
				if ((arbb.max_x < 32)&&(arbb.min_x > - 32))
					delta.x = 0;
				if ((arbb.max_y > 96)&&(arbb.min_x > - 96))
					delta.y = 0;
				Vector pos = ship->position;
				pos.x -= delta.y * v_up.x + delta.x * v_right.x;
				pos.y -= delta.y * v_up.y + delta.x * v_right.y;
				pos.z -= delta.y * v_up.z + delta.x * v_right.z;
				[ship setPosition:pos];
				
//				// give it some roll
//				if ((flight_roll > 0.0)&&([ship flight_roll] < flight_roll))
//				{
//					double roll_adjust = 5 * [universe getTimeDelta] * (flight_roll - [ship flight_roll]);
//					[ship setRoll:[ship flight_roll] + roll_adjust];
//				}
				
				// if far enough in - dock
				if (arbb.max_z < 0)
					[ship enterDock:self];
				return NO;
			}
		}
		// perform bounding box versus bounding box check
		return [super checkCloseCollisionWith:other];
	}
	return YES;
}

- (void) update:(double) delta_t
{
	BOOL isRockHermit = (scan_class == CLASS_ROCK);
	BOOL isMainStation = (self == [universe station]);
	
	double unitime = [universe getTime];
	
//	if (sub_entities)
//		NSLog(@"DEBUG %@ sub_entities %@", [self name], [sub_entities description]);
	
	[super update:delta_t];
	
	if (([launchQueue count] > 0)&&([shipsOnApproach count] == 0)&&(unitime > last_launch_time + STATION_DELAY_BETWEEN_LAUNCHES))
	{
		[self launchShip:(ShipEntity *)[launchQueue objectAtIndex:0]];
		[launchQueue removeObjectAtIndex:0];
	}
	if (([launchQueue count] == 0)&&(no_docking_while_launching))
		no_docking_while_launching = NO;	// launching complete
	if (approach_spacing > 0.0)
	{
		approach_spacing -= delta_t * 10.0;	// reduce by 10 m/s
		if (approach_spacing < 0.0)   approach_spacing = 0.0;
	}
	if ((docked_shuttles > 0)&&(!isRockHermit))
	{
		if (unitime > last_shuttle_launch_time + shuttle_launch_interval)
		{
			[self launchShuttle];
			docked_shuttles--;
			last_shuttle_launch_time = unitime;
		}
	}
	if ((docked_traders > 0)&&(!isRockHermit))
	{
		if (unitime > last_trader_launch_time + trader_launch_interval)
		{
			//NSLog(@"O ---> %d docked traders  at %.1f (%.1f and every %.1f)", docked_traders, [universe getTime], last_trader_launch_time + trader_launch_interval, trader_launch_interval);
			[self launchTrader];
			docked_traders--;
			last_trader_launch_time = unitime;
		}
	}
	
	// testing patrols
	if ((unitime > last_patrol_report_time + patrol_launch_interval)&&(isMainStation))
	{
//		NSLog(@"%@ %d (%@) launching a patrol...", name, universal_id, roles);
		if (![self launchPatrol])
			last_patrol_report_time = unitime;
	}
	
}

- (void) clear
{
	if (launchQueue)
		[launchQueue removeAllObjects];
	if (shipsOnApproach)
		[shipsOnApproach removeAllObjects];
}

- (void) addShipToLaunchQueue:(ShipEntity *) ship
{
	[self sanityCheckShipsOnApproach];
	if (!launchQueue)
		launchQueue = [[NSMutableArray alloc] initWithCapacity:16]; // retained
	if (ship)
		[launchQueue addObject:ship];
}

- (int) countShipsInLaunchQueueWithRole:(NSString *) a_role
{
	if ([launchQueue count] == 0)
		return 0;
	int i;
	int result = 0;
	for (i = 0; i < [launchQueue count]; i++)
	{
		if ([[(ShipEntity *)[launchQueue objectAtIndex:i] roles] isEqual:a_role])
			result++;
	}
	return result;
}

- (void) launchShip:(ShipEntity *) ship
{
	Vector launchPos = position;
	Vector launchVel = velocity;
	double launchSpeed = 0.5 * [ship max_flight_speed];
	if ((max_flight_speed > 0)&&(flight_speed > 0))
		launchSpeed = 0.5 * [ship max_flight_speed] * (1.0 + flight_speed/max_flight_speed);
	Quaternion q1 = q_rotation;
	q1 = quaternion_multiply(port_qrotation, q1);
	quaternion_rotate_about_axis(&q1, vector_forward_from_quaternion(q1),PI*0.5);  // to account for the slot being at 90 degrees to vertical
	// launch position
	launchPos.x += port_position.x * v_right.x + port_position.y * v_up.x + port_position.z * v_forward.x;
	launchPos.y += port_position.x * v_right.y + port_position.y * v_up.y + port_position.z * v_forward.y;
	launchPos.z += port_position.x * v_right.z + port_position.y * v_up.z + port_position.z * v_forward.z;
    [ship setPosition:launchPos];
	// launch speed
	Vector launchVector = vector_forward_from_quaternion(q1);
	launchVel.x += launchSpeed * launchVector.x;	launchVel.y += launchSpeed * launchVector.y;	launchVel.z += launchSpeed * launchVector.z;
	[ship setSpeed:sqrt(magnitude2(launchVel))];
	[ship setVelocity:launchVel];
	// orientation
	[ship setQRotation:q1];
	[ship setRoll:flight_roll];
	[ship setPitch:0.0];
	[ship setStatus:STATUS_LAUNCHING];
	[[ship getAI] reactToMessage:@"pauseAI: 2.0"]; // pause while launching
	[universe addEntity:ship];
	last_launch_time = [universe getTime];
}

- (void) noteDockedShip:(ShipEntity *) ship
{
	// set last launch time to avoid clashes with outgoing ships
	last_launch_time = [universe getTime];
	if ([[ship roles] isEqual:@"shuttle"])
		docked_shuttles++;
	if ([[ship roles] isEqual:@"trader"])
		docked_traders++;
	if ([[ship roles] isEqual:@"police"])
		police_launched--;
	if ([[ship roles] isEqual:@"hermit-ship"])
		police_launched--;
	if ([[ship roles] isEqual:@"defense_ship"])
		police_launched--;
	if ([[ship roles] isEqual:@"scavenger"]||[[ship roles] isEqual:@"miner"])	// treat miners and scavengers alike!
		scavengers_launched--;

	int			ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];
	[shipsOnApproach removeObjectForKey:shipID];
	if ([shipsOnApproach count] == 0)
		[shipAI message:@"DOCKING_COMPLETE"];
	
	int i;	// clear any previously owned docking stages
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		if ((id_lock[i] == ship_id)||([universe entityForUniversalID:id_lock[i]] == nil))
			id_lock[i] = NO_TARGET;
	
	if (ship == [universe entityZero])	// ie. the player
	{
		//scripting
		if ([script_actions count])
		{
			int i;
			[(PlayerEntity *)ship setScript_target:self];
			for (i = 0; i < [script_actions count]; i++)
			{
				NSObject*	action = [script_actions objectAtIndex:i];
				if ([action isKindOfClass:[NSDictionary class]])
					[(PlayerEntity *)ship checkCouplet:(NSDictionary *)action onEntity:ship];
				if ([action isKindOfClass:[NSString class]])
					[(PlayerEntity *)ship scriptAction:(NSString *)action onEntity:ship];
			}
		}
	}
			
//	NSLog(@"DEBUG ::::: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d :: %d <<",
//		id_lock[10],id_lock[9],id_lock[8],id_lock[7],id_lock[6],id_lock[5],id_lock[4],id_lock[3],id_lock[2],id_lock[1]);
	
}


- (BOOL) collideWithShip:(ShipEntity *)other
{
	[self abortAllDockings];
	return [super collideWithShip:other];
}

- (BOOL) hasHostileTarget
{
	if (primaryTarget == NO_TARGET)
		return NO;
	if ((condition == CONDITION_AVOID_COLLISION)&&(previousCondition))
	{
		int old_condition = [(NSNumber*)[previousCondition objectForKey:@"condition"] intValue];
		return IS_CONDITION_HOSTILE(old_condition);
	}
	return IS_CONDITION_HOSTILE(condition)||(alert_level == STATION_ALERT_LEVEL_YELLOW)||(alert_level == STATION_ALERT_LEVEL_RED);
}

//////////////////////////////////////////////// extra AI routines


- (void) increaseAlertLevel
{
	switch (alert_level)
	{
		case STATION_ALERT_LEVEL_GREEN :
			alert_level = STATION_ALERT_LEVEL_YELLOW;
			[shipAI reactToMessage:@"YELLOW_ALERT"];
			break;
		case STATION_ALERT_LEVEL_YELLOW :
			alert_level = STATION_ALERT_LEVEL_RED;
			[shipAI reactToMessage:@"RED_ALERT"];
			break;
	}
}

- (void) decreaseAlertLevel
{
	switch (alert_level)
	{
		case STATION_ALERT_LEVEL_RED :
			alert_level = STATION_ALERT_LEVEL_YELLOW;
			[shipAI reactToMessage:@"CONDITION_YELLOW"];
			break;
		case STATION_ALERT_LEVEL_YELLOW :
			alert_level = STATION_ALERT_LEVEL_GREEN;
			[shipAI reactToMessage:@"CONDITION_GREEN"];
			break;
	}
}

- (void) launchPolice
{
	int techlevel = [self equivalent_tech_level];
	if (techlevel == NSNotFound)
		techlevel = 6;
	int police_target = primaryTarget;
	int i;
	for (i = 0; (i < 4)&&(police_launched < max_police) ; i++)
	{
		ShipEntity  *police_ship;
		if (![universe entityForUniversalID:police_target])
		{
			[shipAI reactToMessage:@"TARGET_LOST"];
			return;
		}
			
		//NSLog(@"Launching Police Ship to intercept %@",[universe entityForUniversalID:police_target]);
		
		if ((ranrot_rand() & 7) + 6 <= techlevel)
			police_ship = [universe getShipWithRole:@"interceptor"];   // retain count = 1
		else
			police_ship = [universe getShipWithRole:@"police"];   // retain count = 1
		[police_ship setRoles:@"police"];
		[police_ship addTarget:[universe entityForUniversalID:police_target]];
		[police_ship setScanClass: CLASS_POLICE];
		[police_ship setBounty:0];
		
		//[police_ship setReportAImessages:YES]; // debug
		
		[[police_ship getAI] setStateMachine:@"policeInterceptAI.plist"];
		[self addShipToLaunchQueue:police_ship];
		[police_ship release];
		police_launched++;
	}
	no_docking_while_launching = YES;
	[self abortAllDockings];
}

- (void) launchDefenseShip
{
	int defense_target = primaryTarget;
	//int n_ships = [universe countShipsWithRole:@"hermit-ship"] + [self countShipsInLaunchQueueWithRole:@"hermit-ship"];
	ShipEntity  *defense_ship;
	NSString* defense_ship_key		= nil;
	NSString* defense_ship_role_key	= nil;
	NSString* defense_ship_ai		= nil;
	
	if ([shipinfoDictionary objectForKey:@"defense_ship"])
	{
//		NSLog(@"DEBUG Defense ship key found: %@", [shipinfoDictionary objectForKey:@"defense_ship"]);
		defense_ship_key = (NSString*)[shipinfoDictionary objectForKey:@"defense_ship"];
	}
	if ([shipinfoDictionary objectForKey:@"defense_ship_role"])
	{
//		NSLog(@"DEBUG Defense ship role key found: %@", [shipinfoDictionary objectForKey:@"defense_ship_role"]);
		defense_ship_role_key = (NSString*)[shipinfoDictionary objectForKey:@"defense_ship_role"];
	}
	
	if (police_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return;
	
	if (![universe entityForUniversalID:defense_target])
	{
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
		
//	NSLog(@"DEBUG Launching defense ship to intercept %@",[(ShipEntity *)[universe entityForUniversalID:defense_target] name]);
	
	police_launched++;
	
	if (defense_ship_key)
	{
		defense_ship = [universe getShip:defense_ship_key];
//		NSLog(@"DEBUG launchDefenseShip Got ship with defense_ship '%@' : %@", defense_ship_key, defense_ship);
		[defense_ship setRoles:@"defense_ship"];
	}
	else
	{
		if (defense_ship_role_key)
		{
			defense_ship = [universe getShipWithRole:defense_ship_role_key];
//			NSLog(@"DEBUG launchDefenseShip Got ship with defense_ship_role '%@' : %@", defense_ship_role_key, defense_ship);
			[defense_ship setRoles:@"defense_ship"];
		}
		else
		{
			defense_ship = [universe getShipWithRole:@"hermit-ship"];   // retain count = 1
			defense_ship_ai = @"policeInterceptAI.plist";
		}
	}
	
	[defense_ship setGroup_id:universal_id];	// who's your Daddy
	[defense_ship addTarget:[universe entityForUniversalID:defense_target]];

	if ((scan_class != CLASS_ROCK)&&(scan_class != CLASS_STATION))
		[defense_ship setScanClass: scan_class];	// same as self
	else
		[defense_ship setScanClass: CLASS_NEUTRAL];	// or neutral
	
	//[defense_ship setReportAImessages:YES]; // debug
	
//	NSLog(@"DEBUG Launching defense ship %@ %@", defense_ship, [defense_ship name]);

	if (defense_ship_ai)
		[[defense_ship getAI] setStateMachine:defense_ship_ai];
	[self addShipToLaunchQueue:defense_ship];
	[defense_ship release];
	no_docking_while_launching = YES;
	[self abortAllDockings];

//	NSLog(@"DEBUG Launchqueue : %@",[launchQueue description]);

}

- (void) launchScavenger
{
	ShipEntity  *scavenger_ship;
	
	int		scavs = [universe countShipsWithRole:@"scavenger" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countShipsInLaunchQueueWithRole:@"scavenger"];
	
	if (scavs >= max_scavengers)
		return;
	
	if (scavengers_launched >= max_scavengers)
		return;
		
	//NSLog(@"Launching Scavenger");
	
	scavengers_launched++;
		
	scavenger_ship = [universe getShipWithRole:@"scavenger"];   // retain count = 1
	[scavenger_ship setScanClass: CLASS_NEUTRAL];

	//[scavenger_ship setReportAImessages:YES]; // debug

	[scavenger_ship setGroup_id:universal_id];	// who's your Daddy
	[[scavenger_ship getAI] setStateMachine:@"scavengerAI.plist"];
	[self addShipToLaunchQueue:scavenger_ship];
	[scavenger_ship release];
}

- (void) launchMiner
{
	ShipEntity  *miner_ship;
	
	int		n_miners = [universe countShipsWithRole:@"miner" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countShipsInLaunchQueueWithRole:@"miner"];
	
	if (n_miners >= 1)	// just the one
		return;
	
	// count miners as scavengers...
	//
	if (scavengers_launched >= max_scavengers)
		return;
	//	
//	NSLog(@"Launching Miner");
	//
	scavengers_launched++;
		
	miner_ship = [universe getShipWithRole:@"miner"];   // retain count = 1
	[miner_ship setScanClass: CLASS_NEUTRAL];

//	[miner_ship setReportAImessages:YES]; // debug

	[miner_ship setGroup_id:universal_id];	// who's your Daddy
	[[miner_ship getAI] setStateMachine:@"minerAI.plist"];
	[self addShipToLaunchQueue:miner_ship];
	[miner_ship release];
}

/**Lazygun** added the following method. A complete rip-off of launchDefenseShip. 
*/
- (void) launchPirateShip
{
	//Pirate ships are launched from the same pool as defence ships.
	int defense_target = primaryTarget;
	ShipEntity  *pirate_ship;
	if (police_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return;
	if (![universe entityForUniversalID:defense_target])
	{
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
	
	//NSLog(@"Launching pirate Ship to intercept %@",[(ShipEntity *)[universe entityForUniversalID:defense_target] name]); //debug
	
	police_launched++;
	
//	pirate_ship = [universe getShipWithRole:@"hermit-ship"];   // retain count = 1
	// Yep! The standard hermit defence ships, even if they're the aggressor.
	pirate_ship = [universe getShipWithRole:@"pirate"];   // retain count = 1
	// Nope, use standard pirates in a generic method.
	
	// set the owner of the ship to the station so that it can check back for docking later
	[pirate_ship setOwner:self];
	[pirate_ship setGroup_id:universal_id];	// who's your Daddy
	
	[pirate_ship addTarget:[universe entityForUniversalID:defense_target]];
	[pirate_ship setScanClass: CLASS_NEUTRAL];
	//**Lazygun** added 30 Nov 04 to put a bounty on those pirates' heads.
	[pirate_ship setBounty: 10 + floor(randf() * 20)];	// modified for variety
	
	//[pirate_ship setReportAImessages:YES]; // debug
//	//**Lazygun** changed name of the AI on 30 Nov 04 from "pirateAI.plist"
//	[[pirate_ship getAI] setStateMachine:@"launchedPirateAI.plist"];
	
	[self addShipToLaunchQueue:pirate_ship];
	[pirate_ship release];
	no_docking_while_launching = YES;
	[self abortAllDockings];
}


- (void) launchShuttle
{
	ShipEntity  *shuttle_ship;
		
	shuttle_ship = [universe getShipWithRole:@"shuttle"];   // retain count = 1
	[shuttle_ship setScanClass: CLASS_NEUTRAL];
	
	[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];

//	[shuttle_ship setReportAImessages:YES]; // debug

	[[shuttle_ship getAI] setStateMachine:@"fallingShuttleAI.plist"];
	[self addShipToLaunchQueue:shuttle_ship];

	//NSLog(@"%@ Prepping shuttle: %@ %d for launch.", [self name], [shuttle_ship name], [shuttle_ship universal_id]);
	
	[shuttle_ship release];
}

- (void) launchTrader
{
	BOOL		sunskimmer = (randf() < 0.1);	// 10%
	ShipEntity  *trader_ship;
	
	if (sunskimmer)
		trader_ship = [universe getShipWithRole:@"trader"];   // retain count = 1
	else
		trader_ship = [universe getShipWithRole:@"sunskim_trader"];   // retain count = 1
	
	[trader_ship setRoles:@"trader"];
	[trader_ship setScanClass: CLASS_NEUTRAL];
	[trader_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];

	//[trader_ship setReportAImessages:YES]; // debug

	if (sunskimmer)
	{
		int escorts = [trader_ship n_escorts];
		[[trader_ship getAI] setStateMachine:@"route2sunskimAI.plist"];
		[trader_ship setN_escorts:0];
		while (escorts--)
		{
			[self launchEscort];
		}
	}
	else
	{
		[[trader_ship getAI] setStateMachine:@"exitingTraderAI.plist"];
	}
	
	[self addShipToLaunchQueue:trader_ship];

	//NSLog(@"%@ Prepping trader: %@ %d for launch.", [self name], [trader_ship name], [trader_ship universal_id]);
		
	[trader_ship release];
}

- (void) launchEscort
{
	ShipEntity  *escort_ship;
		
	escort_ship = [universe getShipWithRole:@"escort"];   // retain count = 1
	[escort_ship setScanClass: CLASS_NEUTRAL];
	
	[escort_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];

	//[escort_ship setReportAImessages:YES]; // debug

	[[escort_ship getAI] setStateMachine:@"escortAI.plist"];
	[self addShipToLaunchQueue:escort_ship];

	//NSLog(@"%@ Prepping escort: %@ %d for launch.", [self name], [escort_ship name], [escort_ship universal_id]);
		
	[escort_ship release];
}

- (BOOL) launchPatrol
{
	
	if (police_launched < max_police)
	{
		ShipEntity  *patrol_ship;
		int techlevel = [self equivalent_tech_level];
		if (techlevel == NSNotFound)
			techlevel = 6;
			
		police_launched++;
		
		if ((ranrot_rand() & 7) + 6 <= techlevel)
			patrol_ship = [universe getShipWithRole:@"interceptor"];   // retain count = 1
		else
			patrol_ship = [universe getShipWithRole:@"police"];   // retain count = 1
		[patrol_ship switchLightsOff];
		[patrol_ship setScanClass: CLASS_POLICE];
		[patrol_ship setRoles:@"police"];
		[patrol_ship setBounty:0];

//		[patrol_ship setReportAImessages:YES]; // debug

		[patrol_ship setGroup_id:universal_id];	// who's your Daddy
		[[patrol_ship getAI] setStateMachine:@"planetPatrolAI.plist"];
		[self addShipToLaunchQueue:patrol_ship];

		[self acceptPatrolReportFrom:patrol_ship];

//		NSLog(@"%@ Prepping patrol: %@ %d for launch.", [self name], [patrol_ship name], [patrol_ship universal_id]);
			
		[patrol_ship release];
		
		return YES;
	}
	else
		return NO;
}

- (void) becomeExplosion
{
	// launch docked ships if possible
	PlayerEntity* player = (PlayerEntity*)[universe entityZero];
	if ((player)&&(player->status == STATUS_DOCKED)&&([player docked_station] == self))
	{
		// undock the player!
		[player leaveDock:self];
		[universe setViewDirection:VIEW_FORWARD];
		[universe setDisplayCursor:NO];
		[player warnAboutHostiles];	// sound a klaxon
	}
	
	if (scan_class == CLASS_ROCK)	// ie we're a rock hermit or similar
	{
		// set the roles so that we break up into rocks!
		roles = @"asteroid";
		being_mined = YES;
	}
	
	// finally bite the bullet
	[super becomeExplosion];
}

- (void) acceptPatrolReportFrom:(ShipEntity*) patrol_ship
{
	last_patrol_report_time = [universe getTime];
//	NSLog(@"..... patrol report received from %@ %d at %3.2f", [patrol_ship name], [patrol_ship universal_id], [universe getTime]);
}

- (void) acceptDockingClearanceRequestFrom:(ShipEntity *)other
{
	if (self != [universe station])
	{
		//NSLog(@"DEBUG acceptDistressMessageFrom rejected from sub-station '%@'", name);
		return;
	}
	
	// check
	//
	if ([shipsOnApproach count])
	{
		[self sendExpandedMessage:@"Please wait until all ships have completed their approach." toShip:other];
		return;
	}
	if ([launchQueue count])
	{
		[self sendExpandedMessage:@"Please wait until launching ships have cleared %H Station." toShip:other];
		return;
	}
	if (last_launch_time < [universe getTime])
	{
		last_launch_time = [universe getTime] + 126;
		[self sendExpandedMessage:@"You are cleared to dock within the next two minutes. Please proceeed." toShip:other];
	}
}

- (NSString *) roles
{
	NSString* all_roles = [shipinfoDictionary objectForKey:@"roles"];
	return [[all_roles componentsSeparatedByString:@" "] objectAtIndex:0];
}

@end
