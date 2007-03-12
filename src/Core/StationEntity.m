/*

StationEntity.m

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

#import "StationEntity.h"
#import "ShipEntityAI.h"
#import "entities.h"
#import "OOCollectionExtractors.h"

#import "AI.h"
#import "OOCharacter.h"


@implementation StationEntity

- (void) acceptDistressMessageFrom:(ShipEntity *)other
{
	if (self != [universe station])
	{
		//NSLog(@"DEBUG acceptDistressMessageFrom rejected from sub-station '%@'", name);
		return;
	}
	
	int old_target = primaryTarget;
	primaryTarget = [[other getPrimaryTarget] universal_id];
	[(ShipEntity *)[other getPrimaryTarget] markAsOffender:8];	// mark their card
	[self launchDefenseShip];
	primaryTarget = old_target;

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
	return magnitude(port_position);
}

- (Vector) getPortPosition
{
	Vector result = position;
	result.x += port_position.x * v_right.x + port_position.y * v_up.x + port_position.z * v_forward.x;
	result.y += port_position.x * v_right.y + port_position.y * v_up.y + port_position.z * v_forward.y;
	result.z += port_position.x * v_right.z + port_position.y * v_up.z + port_position.z * v_forward.z;
	return result;
}

- (Vector) getBeaconPosition
{
	double buoy_distance = 10000.0;				// distance from station entrance
	Vector result = position;
	Vector v_f = vector_forward_from_quaternion(q_rotation);
	result.x += buoy_distance * v_f.x;
	result.y += buoy_distance * v_f.y;
	result.z += buoy_distance * v_f.z;
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
    [super setUniverse: univ];
	if (localMarket) {
		[localMarket release];
		localMarket = nil;
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
		int sid = [[ships objectAtIndex:i] intValue];
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
	ships = [shipsOnHold allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ((sid == NO_TARGET)||(![universe entityForUniversalID:sid]))
		{
			[shipsOnHold removeObjectForKey:[ships objectAtIndex:i]];
		}
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
	ships = [shipsOnHold allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ([universe entityForUniversalID:sid])
			[[(ShipEntity *)[universe entityForUniversalID:sid] getAI] message:@"DOCKING_ABORTED"];
		[shipsOnHold removeObjectForKey:[ships objectAtIndex:i]];
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
	ships = [shipsOnHold allKeys];
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [(NSString *)[ships objectAtIndex:i] intValue];
		if ([universe entityForUniversalID:sid])
			[(ShipEntity *)[universe entityForUniversalID:sid] enterDock:self];
		[shipsOnHold removeObjectForKey:[ships objectAtIndex:i]];
	}
	[shipAI message:@"DOCKING_COMPLETE"];
}

NSDictionary* instructions(int station_id, Vector coords, float speed, float range, NSString* ai_message, NSString* comms_message, BOOL match_rotation)
{
	NSMutableDictionary* acc = [NSMutableDictionary dictionaryWithCapacity:8];
	[acc setObject:[NSString stringWithFormat:@"%.2f %.2f %.2f", coords.x, coords.y, coords.z] forKey:@"destination"];
	[acc setObject:[NSNumber numberWithFloat:speed] forKey:@"speed"];
	[acc setObject:[NSNumber numberWithFloat:range] forKey:@"range"];
	[acc setObject:[NSNumber numberWithInt:station_id] forKey:@"station_id"];
	[acc setObject:[NSNumber numberWithBool:match_rotation] forKey:@"match_rotation"];
	if (ai_message)
		[acc setObject:ai_message forKey:@"ai_message"];
	if (comms_message)
		[acc setObject:comms_message forKey:@"comms_message"];
	//
	return [NSDictionary dictionaryWithDictionary:acc];
}

// this routine does more than set coordinates - it provides a whole set of docking instructions and messages at each stage..
//
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *) ship
{	
	Vector		coords;
	
	int			ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];

	Vector launchVector = vector_forward_from_quaternion( quaternion_multiply(port_qrotation, q_rotation));
	Vector temp = (fabsf(launchVector.x) < 0.8)? make_vector(1,0,0) : make_vector(0,1,0);
	temp = cross_product( launchVector, temp);	// 90 deg to launchVector & temp
	Vector vi = cross_product( launchVector, temp);
	Vector vj = cross_product( launchVector, vi);
	Vector vk = launchVector;
	
	if (!ship)
		return nil;
	
	if ((ship->isPlayer)&&([ship legal_status] > 50))	// note: non-player fugitives dock as normal
	{
		// refuse docking to the fugitive player
		return instructions( universal_id, ship->position, 0, 100, @"DOCKING_REFUSED", @"[station-docking-refused-to-fugitive]", NO);
	}
	
	if (no_docking_while_launching)
	{
		return instructions( universal_id, ship->position, 0, 100, @"TRY_AGAIN_LATER", nil, NO);
	}
	
	[shipAI reactToMessage:@"DOCKING_REQUESTED"];	// react to the request	
	
	if	(magnitude2([self getVelocity]) > 1.0)		// no docking while moving
	{
		if (![shipsOnHold objectForKey:shipID])
			[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
		[shipsOnHold setObject: shipID forKey: shipID];
		[self performStop];
		return instructions( universal_id, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	if	(fabs(flight_pitch) > 0.01)		// no docking while pitching
	{
		if (![shipsOnHold objectForKey:shipID])
			[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
		[shipsOnHold setObject: shipID forKey: shipID];
		[self performStop];
		return instructions( universal_id, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	// rolling is okay for some
	if	(fabs(flight_pitch) > 0.01)		// rolling
	{
		Vector portPos = [self getPortPosition];
		Vector portDir = vector_forward_from_quaternion(port_qrotation);		
		BOOL isOffCentre = (fabs(portPos.x) + fabs(portPos.y) > 0.0f)|(fabs(portDir.x) + fabs(portDir.y) > 0.0f);
		BOOL isRotatingStation = NO;
		if ([shipinfoDictionary objectForKey:@"rotating"])
			isRotatingStation = [[shipinfoDictionary objectForKey:@"rotating"] boolValue];
		if ((!isRotatingStation)&&(isOffCentre))
		{
			if (![shipsOnHold objectForKey:shipID])
				[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
			[shipsOnHold setObject: shipID forKey: shipID];
			[self performStop];
			return instructions( universal_id, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
		}
	}
	
	// we made it thorugh holding!
	//
	if ([shipsOnHold objectForKey:shipID])
		[shipsOnHold removeObjectForKey:shipID];
	
	// check if this is a new ship on approach
	//
	if (![shipsOnApproach objectForKey:shipID])
	{
		Vector	delta = ship->position;
		delta.x -= position.x;	delta.y -= position.y;	delta.z -= position.z;
		float	ship_distance = sqrt( magnitude2( delta));

		[self addShipToShipsOnApproach: ship];
		
		if (ship_distance < 1000.0 + collision_radius + ship->collision_radius)	// too close - back off
			return instructions( universal_id, position, 0, 5000, @"BACK_OFF", nil, NO);
		
		if (ship_distance > 12500.0)	// long way off - approach more closely
			return instructions( universal_id, position, 0, 10000, @"APPROACH", nil, NO);
	}
	
	if (![shipsOnApproach objectForKey:shipID])
	{
		// some error has occurred - log it, and send the try-again message
		NSLog(@"ERROR - couldn't addShipToShipsOnApproach:%@ in %@ for some reason.", ship, self);
		//
		return instructions( universal_id, ship->position, 0, 100, @"TRY_AGAIN_LATER", nil, NO);
	}


	//	shipsOnApproach now has an entry for the ship.
	//
	NSMutableArray* coordinatesStack = (NSMutableArray *)[shipsOnApproach objectForKey:shipID];

	if ([coordinatesStack count] == 0)
	{
		NSLog(@"DEBUG ERROR! -- coordinatesStack = %@", [coordinatesStack description]);
		
		return instructions( universal_id, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	// get the docking information from the instructions	
	NSMutableDictionary* nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:0];
	int docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
	float speedAdvised = [(NSNumber *)[nextCoords objectForKey:@"speed"] floatValue];
	float rangeAdvised = [(NSNumber *)[nextCoords objectForKey:@"range"] floatValue];
	BOOL match_rotation = ([nextCoords objectForKey:@"match_rotation"] != nil);
	NSString* comms_message = (NSString*)[nextCoords objectForKey:@"comms_message"];
	
	// calculate world coordinates from relative coordinates
	Vector rel_coords;
	rel_coords.x = [(NSNumber *)[nextCoords objectForKey:@"rx"] floatValue];
	rel_coords.y = [(NSNumber *)[nextCoords objectForKey:@"ry"] floatValue];
	rel_coords.z = [(NSNumber *)[nextCoords objectForKey:@"rz"] floatValue];
	coords = [self getPortPosition];
	coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
	coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
	coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
	
	// check if the ship is at the control point
	double max_allowed_range = 2.0 * rangeAdvised + ship->collision_radius;	// maximum distance permitted from control point - twice advised range
	Vector delta = ship->position;
	delta.x -= coords.x;	delta.y -= coords.y;	delta.z -= coords.z;

//	if (ship->isPlayer)
//		NSLog(@"DEBUG docking_stage %d: ship is %.2fm from control point ( %.2f, %.2f, %.2f)",
//			docking_stage, sqrt(magnitude2(delta)), coords.x, coords.y, coords.z);

	if (magnitude2(delta) > max_allowed_range * max_allowed_range)	// too far from the coordinates - do not remove them from the stack!
	{
		if ((docking_stage == 1) &&(magnitude2(delta) < 1000000.0))	// 1km*1km
			speedAdvised *= 0.5;	// half speed
		
		return instructions( universal_id, coords, speedAdvised, rangeAdvised, @"APPROACH_COORDINATES", nil, NO);
	}
	else
	{
		// reached the current coordinates okay..
	
		// get the NEXT coordinates
		nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:1];
		docking_stage = [(NSNumber *)[nextCoords objectForKey:@"docking_stage"] intValue];
		speedAdvised = [(NSNumber *)[nextCoords objectForKey:@"speed"] floatValue];
		rangeAdvised = [(NSNumber *)[nextCoords objectForKey:@"range"] floatValue];
		match_rotation = ([nextCoords objectForKey:@"match_rotation"] != nil);
		comms_message = (NSString*)[nextCoords objectForKey:@"comms_message"];
		
		if (comms_message)
			[self sendExpandedMessage: comms_message toShip: ship];
				
		// calculate world coordinates from relative coordinates
		rel_coords.x = [(NSNumber *)[nextCoords objectForKey:@"rx"] floatValue];
		rel_coords.y = [(NSNumber *)[nextCoords objectForKey:@"ry"] floatValue];
		rel_coords.z = [(NSNumber *)[nextCoords objectForKey:@"rz"] floatValue];
		coords = [self getPortPosition];
		coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
		coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
		coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
		
		if ((id_lock[docking_stage] == NO_TARGET)
			&&(id_lock[docking_stage + 1] == NO_TARGET)	
			&&(id_lock[docking_stage + 2] == NO_TARGET))	// check three stages ahead
		{
			// approach is clear - move to next position
			//
			int i;	// clear any previously owned docking stages
			for (i = 1; i < MAX_DOCKING_STAGES; i++)
				if ((id_lock[i] == ship_id)||([universe entityForUniversalID:id_lock[i]] == nil))
					id_lock[i] = NO_TARGET;
					
			if (docking_stage > 1)	// don't claim first docking stage
				id_lock[docking_stage] = ship_id;	// otherwise - claim this docking stage
			
			//remove the previous stage from the stack
			[coordinatesStack removeObjectAtIndex:0];
			
			return instructions( universal_id, coords, speedAdvised, rangeAdvised, @"APPROACH_COORDINATES", nil, match_rotation);
		}
		else
		{
			// approach isn't clear - hold position..
			//
			[[ship getAI] message:@"HOLD_POSITION"];
			
			if (![nextCoords objectForKey:@"hold_message_given"])
			{
				// COMM-CHATTER
				[universe clearPreviousMessage];
				[self sendExpandedMessage: @"[station-hold-position]" toShip: ship];
				[nextCoords setObject:@"YES" forKey:@"hold_message_given"];
			}

			return instructions( universal_id, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
		}
	}
	
	// we should never reach here.
	return instructions( universal_id, coords, 50, 10, @"APPROACH_COORDINATES", nil, NO);
}

- (void) addShipToShipsOnApproach:(ShipEntity *) ship
{		
	int			corridor_distance[] =	{	-1,	1,	3,	5,	7,	9,	11,	12,	12};
	int			corridor_offset[] =		{	0,	0,	0,	0,	0,	0,	1,	3,	12};
	int			corridor_speed[] =		{	48,	48,	48,	48,	36,	48,	64,	128, 512};	// how fast to approach the next point
	int			corridor_range[] =		{	24,	12,	6,	4,	4,	6,	15,	38,	96};	// how close you have to get to the target point
	int			corridor_rotate[] =		{	1,	1,	1,	1,	0,	0,	0,	0,	0};		// whether to match the station rotation
	int			corridor_count = 9;
	int			corridor_final_approach = 3;
	
//	NSLog(@"DEBUG adding %@ to shipsOnApproach", ship);
	
	int			ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d", ship_id];

	Vector launchVector = vector_forward_from_quaternion( quaternion_multiply(port_qrotation, q_rotation));
	Vector temp = (fabsf(launchVector.x) < 0.8)? make_vector(1,0,0) : make_vector(0,1,0);
	temp = cross_product( launchVector, temp);	// 90 deg to launchVector & temp
	Vector rightVector = cross_product( launchVector, temp);
	Vector upVector = cross_product( launchVector, rightVector);
	
	// will select a direction for offset based on the shipID
	//
	int offset_id = ship_id & 0xf;	// 16  point compass
	double c = cos(offset_id * PI * ONE_EIGHTH);
	double s = sin(offset_id * PI * ONE_EIGHTH);
	
	// test if this points at the ship
	Vector point1 = [self getPortPosition];
	point1.x += launchVector.x * corridor_offset[corridor_count - 1];
	point1.y += launchVector.x * corridor_offset[corridor_count - 1];
	point1.z += launchVector.x * corridor_offset[corridor_count - 1];
	Vector alt1 = point1;
	point1.x += c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	point1.y += c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	point1.z += c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	alt1.x -= c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	alt1.y -= c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	alt1.z -= c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	if (distance2( alt1, ship->position) < distance2( point1, ship->position))
	{
		s = -s;
		c = -c;	// turn 180 degrees
	}
	
	//
	NSMutableArray*		coordinatesStack =  [NSMutableArray arrayWithCapacity: MAX_DOCKING_STAGES];
	double port_depth = 250;	// 250m deep standard port
	//
	int i;
	for (i = corridor_count - 1; i >= 0; i--)
	{
		NSMutableDictionary*	nextCoords =	[NSMutableDictionary dictionaryWithCapacity:3];
		
		int offset = corridor_offset[i];
		
		// space out first coordinate further if there are many ships
		if ((i == corridor_count - 1) && offset)
			offset += approach_spacing / port_depth;
		
		[nextCoords setObject:[NSNumber numberWithInt: corridor_count - i] forKey:@"docking_stage"];

		[nextCoords setObject:[NSNumber numberWithFloat: s * port_depth * offset]				forKey:@"rx"];
		[nextCoords setObject:[NSNumber numberWithFloat: c * port_depth * offset]				forKey:@"ry"];
		[nextCoords setObject:[NSNumber numberWithFloat: port_depth * corridor_distance[i]]		forKey:@"rz"];

		[nextCoords setObject:[NSNumber numberWithFloat: corridor_speed[i]] forKey:@"speed"];

		[nextCoords setObject:[NSNumber numberWithFloat: corridor_range[i]] forKey:@"range"];
		
		if (corridor_rotate[i])
			[nextCoords setObject:@"YES" forKey:@"match_rotation"];
		
		if (i == corridor_final_approach)
		{
			if (self == [universe station])
				[nextCoords setObject:@"[station-begin-final-aproach]" forKey:@"comms_message"];
			else
				[nextCoords setObject:@"[docking-begin-final-aproach]" forKey:@"comms_message"];
		}

		[coordinatesStack addObject:nextCoords];
	}
					
	[shipsOnApproach setObject:coordinatesStack forKey:shipID];
	
	approach_spacing += 500;  // space out incoming ships by 500m
	
	// COMM-CHATTER
	if (self == [universe station])
		[self sendExpandedMessage: @"[station-welcome]" toShip: ship];
	else
		[self sendExpandedMessage: @"[docking-welcome]" toShip: ship];

}

- (void) abortDockingForShip:(ShipEntity *) ship
{
	int ship_id = [ship universal_id];
	NSString*   shipID = [NSString stringWithFormat:@"%d",ship_id];
	if ([universe entityForUniversalID:[ship universal_id]])
		[[(ShipEntity *)[universe entityForUniversalID:[ship universal_id]] getAI] message:@"DOCKING_ABORTED"];
	
	if ([shipsOnHold objectForKey:shipID])
		[shipsOnHold removeObjectForKey:shipID];
	
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
			
}

- (Vector) portUpVector
{
//	NSLog(@"DEBUG docking port for %@ is %@ dimensions ( %.2f, %.2f, %.2f)", self, port_model,
//		port_dimensions.x, port_dimensions.y, port_dimensions.z);
	if (port_dimensions.x > port_dimensions.y)
	{
//		NSLog(@"DEBUG returning UP !");
		return vector_up_from_quaternion( quaternion_multiply( port_qrotation, q_rotation));
	}
	else
	{
//		NSLog(@"DEBUG returning RIGHT !");
		return vector_right_from_quaternion( quaternion_multiply( port_qrotation, q_rotation));
	}
}

- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox) bb
{
	BOOL twist = ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y));

//	NSLog(@"DEBUG docking: port_twist:%@ ship_twist:%@ twist:%@", (port_dimensions.x < port_dimensions.y)?@"YES":@"NO", (bb.max.x - bb.min.x < bb.max.y - bb.min.y)?@"YES":@"NO", twist?@"YES":@"NO");

	if (!twist)
	{
		return vector_up_from_quaternion( quaternion_multiply( port_qrotation, q_rotation));
	}
	else
	{
		return vector_right_from_quaternion( quaternion_multiply( port_qrotation, q_rotation));
	}
}


//////////////////////////////////////////////// from superclass

- (id) init
{
	self = [super init];
	
	shipsOnApproach = [[NSMutableDictionary alloc] initWithCapacity:5]; // alloc retains
	shipsOnHold = [[NSMutableDictionary alloc] initWithCapacity:5]; // alloc retains
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

	docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
	trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
	last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	
	last_patrol_report_time = 0.0;
	patrol_launch_interval = 300.0;	// 5 minutes
	last_patrol_report_time -= patrol_launch_interval;
	//
	isShip = YES;
	isStation = YES;
	
	port_model = nil;
	
	return self;
}

- (void) reinit
{
	[super reinit];
	
	if (localMarket) [localMarket autorelease];
	localMarket = nil;
	
	if (localPassengers) [localPassengers autorelease];
	localPassengers = nil;
	
	if (localContracts) [localContracts autorelease];
	localContracts = nil;
	
	if (localShipyard) [localShipyard autorelease];
	localShipyard = nil;
	
	if (shipsOnApproach) [shipsOnApproach autorelease];
	shipsOnApproach = [[NSMutableDictionary alloc] initWithCapacity:5]; // alloc retains
	
	if (shipsOnHold) [shipsOnHold autorelease];
	shipsOnHold = [[NSMutableDictionary alloc] initWithCapacity:5]; // alloc retains
	
	if (launchQueue) [launchQueue autorelease];
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

	port_model = nil;
	
}

- (id) initWithDictionary:(NSDictionary *) dict
{
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
	shipsOnHold = [[NSMutableDictionary alloc] initWithCapacity:16]; // alloc retains
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

	docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
	trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
	last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	
	int i;
	for (i = 0; i < MAX_DOCKING_STAGES; i++)
		id_lock[i] = NO_TARGET;

	isShip = YES;
	isStation = YES;

	return self;
}

- (void) setDockingPortModel:(ShipEntity*) dock_model :(Vector) dock_pos :(Quaternion) dock_q
{
	port_model = dock_model;
		
	port_position = dock_pos;
	port_qrotation = dock_q;

	BoundingBox bb = [port_model getBoundingBox];
	port_dimensions = make_vector( bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z);

	if (bb.max.z > 0.0)
	{
		Vector vk = vector_forward_from_quaternion(dock_q);
		port_position.x += bb.max.z * vk.x;
		port_position.y += bb.max.z * vk.y;
		port_position.z += bb.max.z * vk.z;
	}
	
}

- (void) setUpShipFromDictionary:(NSDictionary *) dict
{
	// ** Set up a the docking port
	// Look for subentity specifying position
	int			i;
	NSArray		*subs = (NSArray *)[dict objectForKey:@"subentities"];
	NSArray		*dockSubEntity = nil;
	for (i = 0; i < [subs count]; i++)
	{
		NSArray* details = [Entity scanTokensFromString:[subs objectAtIndex:i]];
		if (([details count] == 8) && ([[details objectAtIndex:0] hasPrefix:@"dock"]))  dockSubEntity = details;
	}
	
	if (dockSubEntity != nil)
	{
		port_position.x = [(NSString *)[dockSubEntity objectAtIndex:1] floatValue];
		port_position.y = [(NSString *)[dockSubEntity objectAtIndex:2] floatValue];
		port_position.z = [(NSString *)[dockSubEntity objectAtIndex:3] floatValue];
		port_qrotation.w = [(NSString *)[dockSubEntity objectAtIndex:4] floatValue];
		port_qrotation.x = [(NSString *)[dockSubEntity objectAtIndex:5] floatValue];
		port_qrotation.y = [(NSString *)[dockSubEntity objectAtIndex:6] floatValue];
		port_qrotation.z = [(NSString *)[dockSubEntity objectAtIndex:7] floatValue];
		quaternion_normalise(&port_qrotation);
	}
	else
	{
		// No dock* subentity found, use defaults.
		double port_radius = [dict doubleForKey:@"port_radius" defaultValue:500.0];
		port_position = make_vector( 0, 0, port_radius);
		quaternion_set_identity(&port_qrotation);
	}
	
	// port_dimensions can be set for rock-hermits and other specials
	NSArray* tokens = [(NSString*)[dict objectForKey:@"port_dimensions"] componentsSeparatedByString:@"x"];
	if ([tokens count] == 3)
	{
		port_dimensions = make_vector(	[(NSString*)[tokens objectAtIndex:0] floatValue],
										[(NSString*)[tokens objectAtIndex:1] floatValue],
										[(NSString*)[tokens objectAtIndex:2] floatValue]);
	}
	else
	{
		port_dimensions = make_vector( 69, 69, 250);		// base port size (square)
	}
	
	[super setUpShipFromDictionary:dict];
	
	equivalent_tech_level = [dict intForKey:@"equivalent_tech_level" defaultValue:NSNotFound];
	max_scavengers = [dict intForKey:@"max_scavengers" defaultValue:3];
	max_defense_ships = [dict intForKey:@"max_defense_ships" defaultValue:3];
	max_police = [dict intForKey:@"max_police" defaultValue:STATION_MAX_POLICE];
	equipment_price_factor = [dict doubleForKey:@"equipment_price_factor" defaultValue:1.0];
		
	police_launched = 0;
	scavengers_launched = 0;
	approach_spacing = 0.0;
	[shipsOnApproach removeAllObjects];
	[shipsOnHold removeAllObjects];
	[launchQueue removeAllObjects];
	last_launch_time = 0.0;
	
	for (i = 0; i < MAX_DOCKING_STAGES; i++)  id_lock[i] = NO_TARGET;

	if ([self isRotatingStation])
	{
		docked_shuttles = ranrot_rand() & 3;   // 0..3;
		last_shuttle_launch_time = 0.0;
		shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
		last_shuttle_launch_time = - (ranrot_rand() & 63) * shuttle_launch_interval / 60.0;

		docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
		trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
		last_trader_launch_time = 60.0 - trader_launch_interval; // in one minute's time
	}
	else
	{
		docked_shuttles = 0;
		docked_traders = 0;   // 1..3;
	}
	
	[self setCrew:[NSArray arrayWithObject:[OOCharacter characterWithRole:@"police" andOriginalSystem:[universe systemSeed] inUniverse:universe]]];
}

- (void) dealloc
{
	[shipsOnApproach release];
	[shipsOnHold release];
	[launchQueue release];
	
	[localMarket release];
	[localPassengers release];
	[localContracts release];
	[localShipyard release];
	
    [super dealloc];
}

- (BOOL) shipIsInDockingCorridor:(ShipEntity*) ship
{
	if ((!ship)||(!ship->isShip))
		return NO;
	
	Quaternion q0 = quaternion_multiply(port_qrotation, q_rotation);
	Vector vi = vector_right_from_quaternion(q0);
	Vector vj = vector_up_from_quaternion(q0);
	Vector vk = vector_forward_from_quaternion(q0);
	
	Vector port_pos = [self getPortPosition];
	
	BoundingBox shipbb = [ship getBoundingBox];
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: port_pos InVectors: vi : vj : vk];
	
	// port dimensions..
	GLfloat ww = port_dimensions.x;
	GLfloat hh = port_dimensions.y;
	GLfloat dd = port_dimensions.z;

	while (shipbb.max.x - shipbb.min.x > ww * 0.90)	ww *= 1.25;
	while (shipbb.max.y - shipbb.min.y > hh * 0.90)	hh *= 1.25;
	
	if ((ship->isPlayer)&&(debug & DEBUG_COLLISIONS))
		NSLog(@"DEBUG normalised port dimensions are %.2fx%.2fx%.2f", ww, hh, dd);

	ww *= 0.5;
	hh *= 0.5;
	
	if ((ship->isPlayer)&&(debug & DEBUG_COLLISIONS))
		NSLog(@"DEBUG player bounding box is at ( %.2f, %.2f, %.2f)-( %.2f, %.2f, %.2f)",
			arbb.min.x, arbb.min.y, arbb.min.z, arbb.max.x, arbb.max.y, arbb.max.z);

	if (arbb.max.z < -dd)
		return NO;

	if ((arbb.max.x < ww)&&(arbb.min.x > -ww)&&(arbb.max.y < hh)&&(arbb.min.y > -hh))
	{
		// in lane
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)	// we're 90% in docking position!
			[ship enterDock:self];
		//
		return YES;
		//
	}
	
	if (ship->status == STATUS_LAUNCHING)
		return YES;
	
	// if close enough (within 50%) correct and add damage
	//
	if  ((arbb.min.x > -1.5 * ww)&&(arbb.max.x < 1.5 * ww)&&(arbb.min.y > -1.5 * hh)&&(arbb.max.y < 1.5 * hh))
	{
		if (arbb.min.z < 0.0)	// got our nose inside
		{
			GLfloat correction_factor = -arbb.min.z / (arbb.max.z - arbb.min.z);	// proportion of ship inside
		
			// damage the ship according to velocity but don't collide
			[ship takeScrapeDamage: 5 * [universe getTimeDelta]*[ship flight_speed] from:self];
			
			Vector delta;
			delta.x = 0.5 * (arbb.max.x + arbb.min.x) * correction_factor;
			delta.y = 0.5 * (arbb.max.y + arbb.min.y) * correction_factor;
			
			if ((arbb.max.x < ww)&&(arbb.min.x > -ww))	// x is okay - no need to correct
				delta.x = 0;
			if ((arbb.max.y > hh)&&(arbb.min.x > -hh))	// y is okay - no need to correct
				delta.y = 0;
				
			// adjust the ship back to the center of the port
			Vector pos = ship->position;
			pos.x -= delta.y * vj.x + delta.x * vi.x;
			pos.y -= delta.y * vj.y + delta.x * vi.y;
			pos.z -= delta.y * vj.z + delta.x * vi.z;
			[ship setPosition:pos];
		}
		
		// if far enough in - dock
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)
			[ship enterDock:self];
		
		return YES;	// okay NOW we're in the docking corridor!
	}	
	//
	//
	return NO;
}

- (BOOL) dockingCorridorIsEmpty
{
	if (!universe)
		return NO;
	
	double unitime = [universe getTime];
	
	if (unitime < last_launch_time + STATION_DELAY_BETWEEN_LAUNCHES)	// leave sufficient pause between launches
		return NO;
	
	// check against all ships
	BOOL		isEmpty = YES;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained

	for (i = 0; (i < ship_count)&&(isEmpty); i++)
	{
		ShipEntity*	ship = (ShipEntity*)my_entities[i];
		double		d2 = distance2( position, ship->position);
		if ((ship != self)&&(d2 < 25000000)&&(ship->status != STATUS_DOCKED))	// within 5km
		{
			Vector ppos = [self getPortPosition];
			d2 = distance2( ppos, ship->position);
			if (d2 < 4000000)	// within 2km of the port entrance
			{
				Quaternion q1 = q_rotation;
				q1 = quaternion_multiply(port_qrotation, q1);
				//
				Vector v_out = vector_forward_from_quaternion(q1);
				Vector r_pos = make_vector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
				if (r_pos.x||r_pos.y||r_pos.z)
					r_pos = unit_vector(&r_pos);
				else
					r_pos.z = 1.0;
				//
				double vdp = dot_product( v_out, r_pos); //== cos of the angle between r_pos and v_out
				//
				if (vdp > 0.86)
				{
					isEmpty = NO;
//					NSLog(@"DEBUG %@ is blocking %@ launch corridor distance = %.0f (%.0f).", ship, self, sqrt(d2), d2);
					last_launch_time = unitime;
				}
			}
		}
	}
	
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//released

	return isEmpty;
}

- (void) clearDockingCorridor
{
	if (!universe)
		return;
		
	// check against all ships
	BOOL		isClear = YES;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained

	for (i = 0; i < ship_count; i++)
	{
		ShipEntity*	ship = (ShipEntity*)my_entities[i];
		double		d2 = distance2( position, ship->position);
		if ((ship != self)&&(d2 < 25000000)&&(ship->status != STATUS_DOCKED))	// within 5km
		{
			Vector ppos = [self getPortPosition];
			float time_out = -15.00;	// 15 secs
			do
			{
				isClear = YES;
				d2 = distance2( ppos, ship->position);
				if (d2 < 4000000)	// within 2km of the port entrance
				{
					Quaternion q1 = q_rotation;
					q1 = quaternion_multiply(port_qrotation, q1);
					//
					Vector v_out = vector_forward_from_quaternion(q1);
					Vector r_pos = make_vector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
					if (r_pos.x||r_pos.y||r_pos.z)
						r_pos = unit_vector(&r_pos);
					else
						r_pos.z = 1.0;
					//
					double vdp = dot_product( v_out, r_pos); //== cos of the angle between r_pos and v_out
					//
					if (vdp > 0.86)
					{
						isClear = NO;
						// okay it's in the way .. give it a wee nudge (0.25s)
//						NSLog(@"DEBUG [StationEntity clearDockingCorridor] nudging %@", ship);
						[ship update: 0.25];
						time_out += 0.25;
					}
					if (time_out > 0)
					{
						Vector v1 = vector_forward_from_quaternion(port_qrotation);
						Vector spos = ship->position;
						spos.x += 3000.0 * v1.x;	spos.y += 3000.0 * v1.y;	spos.z += 3000.0 * v1.z; 
						[ship setPosition:spos]; // move 3km out of the way
					}
				}
			} while (!isClear);
		}
	}
	
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//released

	return;
}

- (void) update:(double) delta_t
{
	BOOL isRockHermit = (scan_class == CLASS_ROCK);
	BOOL isMainStation = (self == [universe station]);
	
	double unitime = [universe getTime];
	
//	if (sub_entities)
//		NSLog(@"DEBUG %@ sub_entities %@", [self name], [sub_entities description]);
	
	[super update:delta_t];
	
	if (([launchQueue count] > 0)&&([shipsOnApproach count] == 0)&&[self dockingCorridorIsEmpty])
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
//		NSLog(@"DEBUG1 %f %f", unitime, last_trader_launch_time + trader_launch_interval);
		if (unitime > last_trader_launch_time + trader_launch_interval)
		{
//			NSLog(@"DEBUG O ---> %d docked traders  at %.1f (%.1f and every %.1f)", docked_traders, [universe getTime], last_trader_launch_time + trader_launch_interval, trader_launch_interval);
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
	if (shipsOnHold)
		[shipsOnHold removeAllObjects];
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
	if ((!ship)||(!ship->isShip))
		return;
	
	Vector launchPos = position;
	Vector launchVel = velocity;
	double launchSpeed = 0.5 * [ship max_flight_speed];
	if ((max_flight_speed > 0)&&(flight_speed > 0))
		launchSpeed = 0.5 * [ship max_flight_speed] * (1.0 + flight_speed/max_flight_speed);
	Quaternion q1 = q_rotation;
	q1 = quaternion_multiply(port_qrotation, q1);
	Vector launchVector = vector_forward_from_quaternion(q1);
	BoundingBox bb = [ship getBoundingBox];
	if ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y))
		quaternion_rotate_about_axis(&q1, launchVector, PI*0.5);  // to account for the slot being at 90 degrees to vertical
	[ship setQRotation:q1];
	// launch position
	launchPos.x += port_position.x * v_right.x + port_position.y * v_up.x + port_position.z * v_forward.x;
	launchPos.y += port_position.x * v_right.y + port_position.y * v_up.y + port_position.z * v_forward.y;
	launchPos.z += port_position.x * v_right.z + port_position.y * v_up.z + port_position.z * v_forward.z;
    [ship setPosition:launchPos];
	// launch speed
	launchVel.x += launchSpeed * launchVector.x;	launchVel.y += launchSpeed * launchVector.y;	launchVel.z += launchSpeed * launchVector.z;
	[ship setSpeed:sqrt(magnitude2(launchVel))];
	[ship setVelocity:launchVel];
	// orientation
	[ship setRoll:flight_roll];
	[ship setPitch:0.0];
	[ship setStatus: STATUS_LAUNCHING];
	[[ship getAI] reactToMessage:@"pauseAI: 2.0"]; // pause while launching
	[universe addEntity:ship];
	last_launch_time = [universe getTime];
	[ship resetTracking];	// resets stuff for tracking/exhausts
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
			[(PlayerEntity *)ship setScript_target:self];
			[(PlayerEntity *)ship scriptActions: script_actions forTarget: ship];
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
	if ((behaviour == BEHAVIOUR_AVOID_COLLISION)&&(previousCondition))
	{
		int old_behaviour = [(NSNumber*)[previousCondition objectForKey:@"behaviour"] intValue];
		return IS_BEHAVIOUR_HOSTILE(old_behaviour);
	}
	return IS_BEHAVIOUR_HOSTILE(behaviour)||(alert_level == STATION_ALERT_LEVEL_YELLOW)||(alert_level == STATION_ALERT_LEVEL_RED);
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
		if (police_ship)
		{
			if (![police_ship crew])
				[police_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole: @"police"
					andOriginalSystem: [universe systemSeed]
					inUniverse: universe]]];
				
			[police_ship setRoles:@"police"];
			[police_ship addTarget:[universe entityForUniversalID:police_target]];
			[police_ship setScanClass: CLASS_POLICE];
			[police_ship setBounty:0];
			[[police_ship getAI] setStateMachine:@"policeInterceptAI.plist"];
			[self addShipToLaunchQueue:police_ship];
			[police_ship release];
			police_launched++;
		}
	}
	no_docking_while_launching = YES;
	[self abortAllDockings];
}

- (void) launchDefenseShip
{
	int defense_target = primaryTarget;
	ShipEntity  *defense_ship;
	NSString* defense_ship_key		= nil;
	NSString* defense_ship_role_key	= nil;
	NSString* defense_ship_ai		= @"policeInterceptAI.plist";
	
	int techlevel = [self equivalent_tech_level];
	if (techlevel == NSNotFound)
	techlevel = 6;
	if ((ranrot_rand() & 7) + 6 <= techlevel)
		defense_ship_role_key	= @"interceptor";
	else
		defense_ship_role_key	= @"police";
	
	if (police_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return;
	
	if (![universe entityForUniversalID:defense_target])
	{
		[shipAI reactToMessage:@"TARGET_LOST"];
		return;
	}
		
	if ([shipinfoDictionary objectForKey:@"defense_ship"])
	{
//		NSLog(@"DEBUG Defense ship key found: %@", [shipinfoDictionary objectForKey:@"defense_ship"]);
		defense_ship_key = (NSString*)[shipinfoDictionary objectForKey:@"defense_ship"];
		defense_ship_ai = nil;
	}
	if ([shipinfoDictionary objectForKey:@"defense_ship_role"])
	{
//		NSLog(@"DEBUG Defense ship role key found: %@", [shipinfoDictionary objectForKey:@"defense_ship_role"]);
		defense_ship_role_key = (NSString*)[shipinfoDictionary objectForKey:@"defense_ship_role"];
		defense_ship_ai = nil;
	}
	
//	NSLog(@"DEBUG Launching defense ship to intercept %@",[(ShipEntity *)[universe entityForUniversalID:defense_target] name]);

	if (defense_ship_key)
	{
		defense_ship = [universe getShip:defense_ship_key];
//		NSLog(@"DEBUG launchDefenseShip Got ship with defense_ship '%@' : %@", defense_ship_key, defense_ship);
		[defense_ship setRoles:@"defense_ship"];
	}
	else
	{
		defense_ship = [universe getShipWithRole:defense_ship_role_key];
//		NSLog(@"DEBUG launchDefenseShip Got ship with defense_ship_role '%@' : %@", defense_ship_role_key, defense_ship);
		[defense_ship setRoles:@"defense_ship"];
	}
	
	if (!defense_ship)
		return;
	
	police_launched++;
	
	if (![defense_ship crew])
		[defense_ship setCrew:[NSArray arrayWithObject:
			[OOCharacter randomCharacterWithRole: @"hunter"
			andOriginalSystem: [universe systemSeed]
			inUniverse: universe]]];
				
	[defense_ship setOwner: self];
	[defense_ship setGroup_id:universal_id];	// who's your Daddy
	
	if (defense_ship_ai)
		[[defense_ship getAI] setStateMachine:defense_ship_ai];
	[defense_ship addTarget:[universe entityForUniversalID:defense_target]];

	if ((scan_class != CLASS_ROCK)&&(scan_class != CLASS_STATION))
		[defense_ship setScanClass: scan_class];	// same as self
	
	//[defense_ship setReportAImessages:YES]; // debug
	
//	NSLog(@"DEBUG Launching defense ship %@ %@", defense_ship, [defense_ship name]);

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
	if (scavenger_ship)
	{
		if (![scavenger_ship crew])
			[scavenger_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		[scavenger_ship setScanClass: CLASS_NEUTRAL];
		[scavenger_ship setGroup_id:universal_id];	// who's your Daddy
		[[scavenger_ship getAI] setStateMachine:@"scavengerAI.plist"];
		[self addShipToLaunchQueue:scavenger_ship];
		[scavenger_ship release];
	}
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
	miner_ship = [universe getShipWithRole:@"miner"];   // retain count = 1
	if (miner_ship)
	{
		if (![miner_ship crew])
			[miner_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"miner"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		scavengers_launched++;
		[miner_ship setScanClass: CLASS_NEUTRAL];
		[miner_ship setGroup_id:universal_id];	// who's your Daddy
		[[miner_ship getAI] setStateMachine:@"minerAI.plist"];
		[self addShipToLaunchQueue:miner_ship];
		[miner_ship release];
	}
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
	
	// Yep! The standard hermit defence ships, even if they're the aggressor.
	pirate_ship = [universe getShipWithRole:@"pirate"];   // retain count = 1
	// Nope, use standard pirates in a generic method.
	
	if (pirate_ship)
	{
		if (![pirate_ship crew])
			[pirate_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"pirate"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		// set the owner of the ship to the station so that it can check back for docking later
		[pirate_ship setOwner:self];
		[pirate_ship setGroup_id:universal_id];	// who's your Daddy
		
		[pirate_ship addTarget:[universe entityForUniversalID:defense_target]];
		[pirate_ship setScanClass: CLASS_NEUTRAL];
		//**Lazygun** added 30 Nov 04 to put a bounty on those pirates' heads.
		[pirate_ship setBounty: 10 + floor(randf() * 20)];	// modified for variety

		[self addShipToLaunchQueue:pirate_ship];
		[pirate_ship release];
		no_docking_while_launching = YES;
		[self abortAllDockings];
	}
}


- (void) launchShuttle
{
	ShipEntity  *shuttle_ship;
		
	shuttle_ship = [universe getShipWithRole:@"shuttle"];   // retain count = 1
	
	if (shuttle_ship)
	{
		if (![shuttle_ship crew])
			[shuttle_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		[shuttle_ship setScanClass: CLASS_NEUTRAL];
		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
		[[shuttle_ship getAI] setStateMachine:@"fallingShuttleAI.plist"];
		[self addShipToLaunchQueue:shuttle_ship];

//		NSLog(@"%@ Prepping shuttle: %@ %d for launch.", [self name], [shuttle_ship name], [shuttle_ship universal_id]);
//		[shuttle_ship setReportAImessages:YES];	//DEBUG
		
		[shuttle_ship release];
	}
}

- (void) launchTrader
{
	BOOL		sunskimmer = (randf() < 0.1);	// 10%
	ShipEntity  *trader_ship = nil;
	
//	NSLog(@"DEBUG %@ [StationEntity launchTrader]", self);
	
//	do {
//	[trader_ship release];
	//
	if (!sunskimmer)
		trader_ship = [universe getShipWithRole:@"trader"];   // retain count = 1
	else
		trader_ship = [universe getShipWithRole:@"sunskim-trader"];   // retain count = 1
	//
//	} while (![trader_ship n_escorts]);	// DEBUG we NEED escorts
	
//	NSLog(@"DEBUG [StationEntity launchTrader] ---> %@ ", trader_ship);
	
	if (trader_ship)
	{
		if (![trader_ship crew])
			[trader_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		[trader_ship setRoles:@"trader"];
		[trader_ship setScanClass: CLASS_NEUTRAL];
		[trader_ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
		
		if (sunskimmer)
		{
			[[trader_ship getAI] setStateMachine:@"route2sunskimAI.plist"];
		}
		else
		{
			[[trader_ship getAI] setStateMachine:@"exitingTraderAI.plist"];
		}
		[self addShipToLaunchQueue:trader_ship];

		// add escorts to the trader
		int escorts = [trader_ship n_escorts];
		//
		[trader_ship setN_escorts:0];
		while (escorts--)
			[self launchEscort];

//		NSLog(@"%@ Prepping trader: %@ %d for launch.", [self name], [trader_ship name], [trader_ship universal_id]);
			
		[trader_ship release];
	}
}

- (void) launchEscort
{
	ShipEntity  *escort_ship;
		
	escort_ship = [universe getShipWithRole:@"escort"];   // retain count = 1
	
	if (escort_ship)
	{
		if (![escort_ship crew])
			[escort_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
				
		[escort_ship setScanClass: CLASS_NEUTRAL];
		[escort_ship setCargoFlag: CARGO_FLAG_FULL_PLENTIFUL];
		[[escort_ship getAI] setStateMachine:@"escortAI.plist"];
		[self addShipToLaunchQueue:escort_ship];
		
//		[escort_ship setReportAImessages: YES];
		
		[escort_ship release];
	}
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
		if (patrol_ship)
		{
			if (![patrol_ship crew])
				[patrol_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole: @"police"
					andOriginalSystem: [universe systemSeed]
					inUniverse: universe]]];
				
			[patrol_ship switchLightsOff];
			[patrol_ship setScanClass: CLASS_POLICE];
			[patrol_ship setRoles:@"police"];
			[patrol_ship setBounty:0];
			[patrol_ship setGroup_id:universal_id];	// who's your Daddy
			[[patrol_ship getAI] setStateMachine:@"planetPatrolAI.plist"];
			[self addShipToLaunchQueue:patrol_ship];
			[self acceptPatrolReportFrom:patrol_ship];
			[patrol_ship release];
			return YES;
		}
	}
	return NO;
}

- (void) launchShipWithRole:(NSString*) role
{
	ShipEntity  *ship = [universe getShipWithRole: role];   // retain count = 1
	if (ship)
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: role
				andOriginalSystem: [universe systemSeed]
				inUniverse: universe]]];
		[ship setRoles: role];
		[ship setGroup_id: universal_id];	// who's your Daddy
		[self addShipToLaunchQueue:ship];
		[ship release];
	}
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
	NSArray* all_roles = [Entity scanTokensFromString:[shipinfoDictionary objectForKey:@"roles"]];
	if ([all_roles count])
		return (NSString *)[all_roles objectAtIndex:0];
	else
		return @"station";
}

- (BOOL) isRotatingStation
{
	NSString*	shipRoles = (NSString *)[shipinfoDictionary objectForKey:@"roles"];
	BOOL		isRotatingStation = NO;
	if ([shipinfoDictionary objectForKey:@"rotating"])
		isRotatingStation = [[shipinfoDictionary objectForKey:@"rotating"] boolValue];
	isRotatingStation |= ([shipRoles rangeOfString:@"rotating-station"].location != NSNotFound);	// legacy
	return isRotatingStation;
}


- (BOOL) hasShipyard
{
	if ([universe strict])
		return NO;
	if ([universe station] == self)
		return YES;
	if ([shipinfoDictionary objectForKey:@"hasShipyard"])
	{
		PlayerEntity	*player = (PlayerEntity*)[universe entityZero];
		NSObject		*determinant = [shipinfoDictionary objectForKey:@"hasShipyard"];
		if ([determinant isKindOfClass:[NSArray class]])
		{
			NSArray *conditions = (NSArray *)determinant;
			BOOL success = YES;
			int i;
			for (i = 0; (i < [conditions count])&&(success); i++)
				success &= [player scriptTestCondition:(NSString *)[conditions objectAtIndex:i]];
			return success;
		}
		if ([determinant isKindOfClass:[NSNumber class]])
		{
			float chance = [(NSNumber*)determinant floatValue];;
			return (randf() < chance);
		}
	}
	return NO;
}


- (NSString*) description
{
	if (debug & DEBUG_ENTITIES)
	{
		NSString* result = [[NSString alloc] initWithFormat:@"<StationEntity %@ %d (%@)%@%@ // %@>",
			name, universal_id, roles, (universe == nil)? @" (not in universe)":@"", ([self isRotatingStation])? @" (rotating)":@"", collision_region];
		return [result autorelease];
	}
	else
		return [NSString stringWithFormat:@"<StationEntity %@ %d>", name, universal_id];
}

@end
