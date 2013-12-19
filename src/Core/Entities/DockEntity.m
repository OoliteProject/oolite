/*

DockEntity.m

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

#import "DockEntity.h"
#import "StationEntity.h"
#import "ShipEntityAI.h"
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"

#import "Universe.h"
#import "HeadUpDisplay.h"

#import "PlayerEntityLegacyScriptEngine.h"
#import "OOLegacyScriptWhitelist.h"
#import "OOPlanetEntity.h"
#import "OOShipGroup.h"
#import "OOQuiriumCascadeEntity.h"

#import "AI.h"
#import "OOCharacter.h"

#import "OOJSScript.h"
#import "OODebugGLDrawing.h"
#import "OODebugFlags.h"


@interface DockEntity (OOPrivate)

- (void) clearIdLocks:(ShipEntity *)ship;
- (void) autoDockShipsInQueue:(NSMutableDictionary *)queue;
- (void) addShipToShipsOnApproach:(ShipEntity *)ship;
- (void) pullInShipIfPermitted:(ShipEntity *)ship;

@end


@implementation DockEntity

- (NSUInteger) pruneAndCountShipsOnApproach
{
	// Remove dead entities.
	// Enumerate over allKeys explicitly because we mutate the dictionary.
	NSNumber *idObj = nil;
	foreach (idObj, [shipsOnApproach allKeys])
	{
		ShipEntity *ship = [UNIVERSE entityForUniversalID:[idObj unsignedIntValue]];
		if (ship == nil)
		{
			[shipsOnApproach removeObjectForKey:idObj];
		}
	}
	
	if ([shipsOnApproach count] == 0)
	{
		if (last_launch_time < [UNIVERSE getTime])
		{
			last_launch_time = [UNIVERSE getTime];
		}
		approach_spacing = 0.0;
	}
	
	return [shipsOnApproach count];
}


- (void) abortAllDockings
{
	double		playerExtraTime = 0;
	
	no_docking_while_launching = YES;
	
	NSNumber *idObj = nil;
	foreach (idObj, [shipsOnApproach allKeys])
	{
		ShipEntity *ship = [UNIVERSE entityForUniversalID:[idObj unsignedIntValue]];
		if ([ship isShip])
		{
			[ship sendAIMessage:@"DOCKING_ABORTED"];
			[ship doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
		}
	}
	[shipsOnApproach removeAllObjects];
	
	PlayerEntity *player = PLAYER;
	StationEntity *station = (StationEntity*)[self parentEntity];
	BOOL isDockingStation = (station == [player getTargetDockStation]) && ([station playerReservedDock] == self);
	if (isDockingStation && [player status] == STATUS_IN_FLIGHT &&
			[player getDockingClearanceStatus] >= DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		if (HPmagnitude2(HPvector_subtract([player position], [self absolutePositionForSubentity])) > 2250000) // within 1500m of the dock
		{
			[station sendExpandedMessage:@"[station-docking-clearance-abort-cancelled]" toShip:player];
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
			[player doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
		}
		else
		{
			playerExtraTime = 10; // when very close to the port, give the player a few seconds to react on the abort message.
			[station sendExpandedMessage:[NSString stringWithFormat:DESC(@"station-docking-clearance-abort-cancelled-in-f"), playerExtraTime] toShip:player];
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_TIMING_OUT];
		}

	}
	
	last_launch_time = [UNIVERSE getTime] + playerExtraTime;
	approach_spacing = 0.0;
}


- (void) abortAllLaunches
{
	no_docking_while_launching = NO;
	[launchQueue removeAllObjects];
}


- (void) autoDockShipsInQueue:(NSMutableDictionary *)queue
{	
	NSNumber *idObj = nil;
	foreach (idObj, [queue allKeys])
	{
		ShipEntity *ship = [UNIVERSE entityForUniversalID:[idObj unsignedIntValue]];
		if ([ship isShip])
		{
			[self pullInShipIfPermitted:ship];
		}
	}
	
	[queue removeAllObjects];
}


- (void) autoDockShipsOnApproach
{
	[self autoDockShipsInQueue:shipsOnApproach];
}


- (BOOL) allowsDocking
{
	return allow_docking;
}


- (void) setAllowsDocking:(BOOL)allowed
{
	if (!allowed && allow_docking) 
	{
		[self abortAllDockings];
	}
	allow_docking = allowed;
}


- (BOOL) disallowedDockingCollides
{
	return disallowed_docking_collides;
}


- (BOOL) allowsLaunching
{
	return allow_launching;
}


- (void) setAllowsLaunching:(BOOL)allowed
{
	if (!allowed && allow_launching) 
	{
		[self abortAllLaunches];
	}
	allow_launching = allowed;
}


- (void) setDisallowedDockingCollides:(BOOL)ddc
{
	disallowed_docking_collides = ddc;
}


- (void) setVirtual
{
	virtual_dock = YES;
}


- (NSString*) canAcceptShipForDocking:(ShipEntity *) ship
{
	// First test permanent rejection reasons
	if (!allow_docking)
	{
		return @"DOCK_CLOSED"; // could be temp or perm reject
	}
	BoundingBox bb = [ship totalBoundingBox];
	if ((port_dimensions.x < (bb.max.x - bb.min.x) || port_dimensions.y < (bb.max.y - bb.min.y)) && 
		(port_dimensions.y < (bb.max.x - bb.min.x) || port_dimensions.x < (bb.max.y - bb.min.y)))
	{
		return @"TOO_BIG_TO_DOCK";
	}

	// callback to allow more complex filtering on accept/reject
	JSContext	*context = OOJSAcquireContext();
	jsval		rval = JSVAL_VOID;
	jsval		args[] = { OOJSValueFromNativeObject(context, ship) };
	JSBool accept = YES;
	
	BOOL OK = [[self script] callMethod:OOJSID("acceptDockingRequestFrom") inContext:context withArguments:args count:1 result:&rval];
	if (OK)  OK = JS_ValueToBoolean(context, rval, &accept);
	if (!OK)  accept = YES; // default to permreject
	OOJSRelinquishContext(context);

	if (!accept)
	{
		return @"TOO_BIG_TO_DOCK";
	}

	// Second test temporary rejection reasons
	if (no_docking_while_launching)
	{
		return @"TRY_AGAIN_LATER";
	}
	// if there are pending launches, temporarily don't accept docking requests
	if (allow_launching && [launchQueue count])
	{
		return @"TRY_AGAIN_LATER";
	}
	
	return @"DOCKING_POSSIBLE";
}


- (BOOL) isOffCentre
{
	if (fabs(position.x) + fabs(position.y) > 5.0f)
	{
		return YES;
	}
	Vector dir = vector_forward_from_quaternion(orientation);
	if (fabs(dir.x) + fabs(dir.y) > 0.1f)
	{
		return YES;
	}
	return NO;
}


- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *)ship
{	
	if (ship == nil)  return nil;
	
	OOUniversalID	ship_id = [ship universalID];
	NSNumber		*shipID = [NSNumber numberWithUnsignedShort:ship_id];
	StationEntity	*station = (StationEntity *)[self parentEntity];

	HPVector launchVector = HPvector_forward_from_quaternion(quaternion_multiply(orientation, [station orientation]));
	HPVector temp = (fabs(launchVector.x) < 0.8)? make_HPvector(1,0,0) : make_HPvector(0,1,0);
	temp = HPcross_product(launchVector, temp);	// 90 deg to launchVector & temp
	HPVector vi = HPcross_product(launchVector, temp);
	HPVector vj = HPcross_product(launchVector, vi);
	HPVector vk = launchVector;
	
	// check if this is a new ship on approach
	//
	if (![shipsOnApproach objectForKey:shipID])
	{
		HPVector	delta = HPvector_subtract([ship position], [self absolutePositionForSubentity]);
		float	ship_distance = HPmagnitude(delta);

		if (ship_distance > SCANNER_MAX_RANGE)
		{
			// too far away - don't claim a docking slot by not putting on approachlist for now.
			return OOMakeDockingInstructions(station, [self absolutePositionForSubentity], [ship maxFlightSpeed], 10000, @"APPROACH", nil, NO);
		}

		[self addShipToShipsOnApproach: ship];
		
		if (ship_distance < 1000.0 + [station collisionRadius] + ship->collision_radius)	// too close - back off
			return OOMakeDockingInstructions(station, [self absolutePositionForSubentity], [ship maxFlightSpeed], 5000, @"BACK_OFF", nil, NO);
		
		float dot = HPdot_product(launchVector, delta);
		if (dot < 0) // approaching from the wrong side of the station - construct a vector to the side of the station.
		{
			HPVector approachVector = HPcross_product(HPvector_normal(delta), launchVector);
			approachVector = HPcross_product(launchVector, approachVector); // vector, 90 degr rotated from launchVector towards target.
			return OOMakeDockingInstructions(station, OOHPVectorTowards([self absolutePositionForSubentity], approachVector, [station collisionRadius] + 5000) , [ship maxFlightSpeed], 1000, @"APPROACH", nil, NO);
		}
		
		if (ship_distance > 12500.0)
		{
			// long way off - approach more closely
			return OOMakeDockingInstructions(station, [self absolutePositionForSubentity], [ship maxFlightSpeed], 10000, @"APPROACH", nil, NO);
		}
	}
	
	if (![shipsOnApproach objectForKey:shipID])
	{
		// some error has occurred - log it, and send the try-again message
		OOLogERR(@"station.issueDockingInstructions.failed", @"couldn't addShipToShipsOnApproach:%@ in %@, retrying later -- shipsOnApproach:\n%@", ship, self, shipsOnApproach);
		
		return OOMakeDockingInstructions(station, [ship position], 0, 100, @"TRY_AGAIN_LATER", nil, NO);
	}


	//	shipsOnApproach now has an entry for the ship.
	//
	NSMutableArray* coordinatesStack = [shipsOnApproach objectForKey:shipID];

	if ([coordinatesStack count] == 0)
	{
		OOLogERR(@"station.issueDockingInstructions.failed", @" -- coordinatesStack = %@", coordinatesStack);
		
		return OOMakeDockingInstructions(station, [ship position], 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	// get the docking information from the instructions	
	NSMutableDictionary *nextCoords = (NSMutableDictionary *)[coordinatesStack objectAtIndex:0];
	int docking_stage = [nextCoords oo_intForKey:@"docking_stage"];
	float speedAdvised = [nextCoords oo_floatForKey:@"speed"];
	float rangeAdvised = [nextCoords oo_floatForKey:@"range"];
	
	// calculate world coordinates from relative coordinates
	HPVector rel_coords;
	rel_coords.x = [nextCoords oo_doubleForKey:@"rx"];
	rel_coords.y = [nextCoords oo_doubleForKey:@"ry"];
	rel_coords.z = [nextCoords oo_doubleForKey:@"rz"];
	HPVector coords = [self absolutePositionForSubentity];
	coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
	coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
	coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
	
	// check if the ship is at the control point
	double max_allowed_range = 2.0 * rangeAdvised + ship->collision_radius;	// maximum distance permitted from control point - twice advised range
	HPVector delta = HPvector_subtract(ship->position, coords);
	
	if (HPmagnitude2(delta) > max_allowed_range * max_allowed_range)	// too far from the coordinates - do not remove them from the stack!
	{
		if ((docking_stage == 1) &&(HPmagnitude2(delta) < 1000000.0))	// 1km*1km
			speedAdvised *= 0.5;	// half speed
		
		return OOMakeDockingInstructions(station, coords, speedAdvised, rangeAdvised, @"APPROACH_COORDINATES", nil, NO);
	}
	else
	{
		// reached the current coordinates okay..
	
		// get the NEXT coordinates
		nextCoords = (NSMutableDictionary *)[coordinatesStack oo_dictionaryAtIndex:1];
		if (nextCoords == nil)
		{
			return nil;
		}
		
		docking_stage = [nextCoords oo_intForKey:@"docking_stage"];
		speedAdvised = [nextCoords oo_floatForKey:@"speed"];
		rangeAdvised = [nextCoords oo_floatForKey:@"range"];
		BOOL match_rotation = [nextCoords oo_boolForKey:@"match_rotation"];
		NSString *comms_message = [nextCoords oo_stringForKey:@"comms_message"];
		
		if (comms_message)
		{
			[station sendExpandedMessage:comms_message toShip:ship];
		}
				
		// calculate world coordinates from relative coordinates
		rel_coords.x = [nextCoords oo_floatForKey:@"rx"];
		rel_coords.y = [nextCoords oo_floatForKey:@"ry"];
		rel_coords.z = [nextCoords oo_floatForKey:@"rz"];
		coords = [self absolutePositionForSubentity];
		coords.x += rel_coords.x * vi.x + rel_coords.y * vj.x + rel_coords.z * vk.x;
		coords.y += rel_coords.x * vi.y + rel_coords.y * vj.y + rel_coords.z * vk.y;
		coords.z += rel_coords.x * vi.z + rel_coords.y * vj.z + rel_coords.z * vk.z;
		
		if([id_lock[docking_stage] weakRefUnderlyingObject] == nil &&
		   [id_lock[docking_stage + 1] weakRefUnderlyingObject] == nil &&
		   [id_lock[docking_stage + 2] weakRefUnderlyingObject] == nil)	// check three stages ahead
		{
			// approach is clear - move to next position
			//
			
			// clear any previously owned docking stages
			[self clearIdLocks:ship];
					
			if (docking_stage > 1)	// don't claim first docking stage
			{
				[id_lock[docking_stage] release];
				id_lock[docking_stage] = [ship weakRetain];	// otherwise - claim this docking stage
			}
			
			//remove the previous stage from the stack
			[coordinatesStack removeObjectAtIndex:0];
			
			return OOMakeDockingInstructions(station, coords, speedAdvised, rangeAdvised, @"APPROACH_COORDINATES", nil, match_rotation);
		}
		else
		{
			// approach isn't clear - hold position..
			//
			[[ship getAI] message:@"HOLD_POSITION"];
			
			if (![nextCoords objectForKey:@"hold_message_given"])
			{
				// COMM-CHATTER
				[UNIVERSE clearPreviousMessage];
				[self sendExpandedMessage: @"[station-hold-position]" toShip: ship];
				[nextCoords setObject:@"YES" forKey:@"hold_message_given"];
			}

			return OOMakeDockingInstructions(station, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
		}
	}
	
	// we should never reach here.
	return OOMakeDockingInstructions(station, coords, 50, 10, @"APPROACH_COORDINATES", nil, NO);
}


- (void) addShipToShipsOnApproach:(ShipEntity *) ship
{		
	int			corridor_distance[] =	{	-1,	1,	3,	5,	7,	9,	11,	12,	12};
	int			corridor_offset[] =		{	0,	0,	0,	0,	0,	0,	1,	3,	12};
	/* Eric's improvements to the docking flight code seem to have
	 * made it safer to go quite a bit faster here. With the increased
	 * numbers of ships which might need to dock at the main station,
	 * faster docking will help avoid massive queues. Previous speed
	 * was mostly 48 - CIM: 27/8/2013*/
	int			corridor_speed[] =		{	96,	96,	128,	128,	96,	128,	128,	256,	512};	// how fast to approach the next point
	int			corridor_range[] =		{	24,	12,	6,	4,	4,	6,	15,	38,	96};	// how close you have to get to the target point
	int			corridor_rotate[] =		{	1,	1,	1,	1,	0,	0,	0,	0,	0};		// whether to match the station rotation
	int			corridor_count = 9;
	int			corridor_final_approach = 3;
	
	NSNumber		*shipID = [NSNumber numberWithUnsignedShort:[ship universalID]];
	StationEntity	*station = (StationEntity *)[self parentEntity];
	
	HPVector launchVector = HPvector_forward_from_quaternion(quaternion_multiply(orientation, [station orientation]));
	HPVector temp = (fabs(launchVector.x) < 0.8)? make_HPvector(1,0,0) : make_HPvector(0,1,0);
	temp = HPcross_product(launchVector, temp);	// 90 deg to launchVector & temp
	HPVector rightVector = HPcross_product(launchVector, temp);
	HPVector upVector = HPcross_product(launchVector, rightVector);
	
	// will select a direction for offset based on the entity personality (was ship ID)
	int offset_id = [ship entityPersonalityInt] & 0xf;	// 16  point compass
	float c = cos(offset_id * M_PI * ONE_EIGHTH);
	float s = sin(offset_id * M_PI * ONE_EIGHTH);
	
	// test if this points at the ship
	HPVector point1 = [self absolutePositionForSubentity];
	point1.x += launchVector.x * corridor_offset[corridor_count - 1];
	point1.y += launchVector.x * corridor_offset[corridor_count - 1];
	point1.z += launchVector.x * corridor_offset[corridor_count - 1];
	HPVector alt1 = point1;
	point1.x += c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	point1.y += c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	point1.z += c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	alt1.x -= c * upVector.x * corridor_offset[corridor_count - 1] + s * rightVector.x * corridor_offset[corridor_count - 1];
	alt1.y -= c * upVector.y * corridor_offset[corridor_count - 1] + s * rightVector.y * corridor_offset[corridor_count - 1];
	alt1.z -= c * upVector.z * corridor_offset[corridor_count - 1] + s * rightVector.z * corridor_offset[corridor_count - 1];
	if (HPdistance2(alt1, ship->position) < HPdistance2(point1, ship->position))
	{
		s = -s;
		c = -c;	// turn 180 degrees
	}
	
	//
	NSMutableArray *coordinatesStack = [NSMutableArray arrayWithCapacity: MAX_DOCKING_STAGES];
	float port_depth = port_dimensions.z;	// 250m deep standard port.
	
	int i;
	for (i = corridor_count - 1; i >= 0; i--)
	{
		NSMutableDictionary *nextCoords = [NSMutableDictionary dictionaryWithCapacity:3];
		int offset = corridor_offset[i];
		
		// space out first coordinate further if there are many ships
		if ((i == corridor_count - 1) && offset)
		{
			offset += approach_spacing / port_depth;
		}
		
		float corridor_length = port_depth * corridor_distance[i];
		// add the lenght inside the station to the corridor, except for the final position, inside the dock.
		if (corridor_distance[i] > 0)  corridor_length += port_corridor;
		
		[nextCoords oo_setInteger:corridor_count - i	forKey:@"docking_stage"];
		[nextCoords oo_setFloat:s * port_depth * offset	forKey:@"rx"];
		[nextCoords oo_setFloat:c * port_depth * offset	forKey:@"ry"];
		[nextCoords oo_setFloat:corridor_length			forKey:@"rz"];
		[nextCoords oo_setFloat:corridor_speed[i]		forKey:@"speed"];
		[nextCoords oo_setFloat:corridor_range[i]		forKey:@"range"];
		
		if (corridor_rotate[i])
		{
			[nextCoords setObject:@"YES" forKey:@"match_rotation"];
		}
		
		if (i == corridor_final_approach)
		{
			if (station == [UNIVERSE station])
			{
				[nextCoords setObject:@"[station-begin-final-aproach]" forKey:@"comms_message"];
			}
			else
			{
				[nextCoords setObject:@"[docking-begin-final-aproach]" forKey:@"comms_message"];
			}
		}
		
		[coordinatesStack addObject:nextCoords];
	}
	
	[shipsOnApproach setObject:coordinatesStack forKey:shipID];
	
	approach_spacing += 500;  // space out incoming ships by 500m
	
	// FIXME: Eric 23-10-2011: Below is a quick fix to prevent the approach_spacing from blowing up
	// to high values because of bad AI's for docking ships that keep requesting and aborting docking.
	// Post 1.76 this probably should replace it with a proper list of holding slots so  that close by slots
	// can be used again once the ship has left the Approach queue. In the current fix, resetting can
	// result in two ships getting the same holding position.
	if (approach_spacing > 2 * SCANNER_MAX_RANGE && approach_spacing / 500 > 5 * [shipsOnApproach count])
	{
		approach_spacing = 0;
	}
	
	// COMM-CHATTER
	if (station == [UNIVERSE station])
	{
		[station sendExpandedMessage:@"[station-welcome]" toShip:ship];
	}
	else
	{
		[station sendExpandedMessage:@"[docking-welcome]" toShip:ship];
	}
}


- (void) noteDockingForShip:(ShipEntity *) ship
{
	// safe to do this for now, as it just clears the ship from the docking queue
	[self abortDockingForShip:ship];
	
	// avoid clashes with outgoing ships
	last_launch_time = [UNIVERSE getTime];

}

- (void) abortDockingForShip:(ShipEntity *)ship
{
	OOUniversalID	ship_id = [ship universalID];
	NSNumber		*shipID = [NSNumber numberWithUnsignedShort:ship_id];
	
	if ([shipsOnApproach objectForKey:shipID])
	{
		[shipsOnApproach removeObjectForKey:shipID];
	}
	
	if ([ship isPlayer])
	{
		PlayerEntity* player = PLAYER;
		if ([player status] == STATUS_IN_FLIGHT &&
				[player getDockingClearanceStatus] >= DOCKING_CLEARANCE_STATUS_REQUESTED)
		{
			if (HPmagnitude2(HPvector_subtract([player position], [self absolutePositionForSubentity])) > 2250000) // within 1500m of the dock
			{
				[[self parentEntity] sendExpandedMessage:@"[station-docking-clearance-abort-cancelled]" toShip:player];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
			}
			else
			{
				int playerExtraTime = 10; // when very close to the port, give the player a few seconds to react on the abort message.
				[[self parentEntity] sendExpandedMessage:[NSString stringWithFormat:DESC(@"station-docking-clearance-abort-cancelled-in-f"), playerExtraTime] toShip:player];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_TIMING_OUT];
			}
		}
	}

	// clear any previously owned docking stages
	[self clearIdLocks:ship];
}


- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox)bb
{
	BOOL twist = ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y));

	if (!twist)
	{
		return vector_up_from_quaternion(quaternion_multiply(orientation, [[self parentEntity] orientation]));
	}
	else
	{
		return vector_right_from_quaternion(quaternion_multiply(orientation, [[self parentEntity] orientation]));
	}
}


- (BOOL) shipIsInDockingQueue:(ShipEntity *)ship
{
	if (![ship isShip])  return NO;
	if ([ship isPlayer] && [ship status] == STATUS_DEAD)  return NO;
	
	OOUniversalID	ship_id = [ship universalID];
	NSNumber		*shipID = [NSNumber numberWithUnsignedShort:ship_id];
	
	if ([shipsOnApproach objectForKey:shipID])
	{
		return YES;
	}
	// player docking manually
	if ([ship isPlayer] && [[self owner] playerReservedDock] == self)
	{
		return YES;
	}
	return NO;
}


- (NSUInteger) countOfShipsInDockingQueue
{
	return [shipsOnApproach count];
}


- (NSUInteger) countOfShipsInLaunchQueue
{
	return [launchQueue count];
}


- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship
{
	if (![ship isShip])  return NO;
	if ([ship isPlayer] && [ship status] == STATUS_DEAD)  return NO;

	BOOL allow_docking_thisship = allow_docking || !disallowed_docking_collides;
	// ships can physically dock here, and this routine is mainly for
	// collision detection, but will never be directed here by traffic
	// control, if allow_docking is false but d_d_c is also false
	
	StationEntity *station = (StationEntity *)[self parentEntity];
	if ([station status] == STATUS_DEAD)
	{
		return NO;
	}
	
	Quaternion q0 = quaternion_multiply(orientation, [station orientation]);
	Vector vi = vector_right_from_quaternion(q0);
	Vector vj = vector_up_from_quaternion(q0);
	Vector vk = vector_forward_from_quaternion(q0);
	
	HPVector port_pos = [self absolutePositionForSubentity];
	
	BoundingBox shipbb = [ship boundingBox];
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: port_pos InVectors: vi : vj : vk];
	
	// port dimensions..
	GLfloat ww = port_dimensions.x;
	GLfloat hh = port_dimensions.y;
	GLfloat dd = port_dimensions.z;

	BOOL rotatedPort = (ww >= hh) ? NO : YES;
	BOOL rotatedShip = ((shipbb.max.x - shipbb.min.x) >= (shipbb.max.y - shipbb.min.y)) ? NO : YES;
	if (rotatedShip == rotatedPort)
	{
		// the ship and port are both bigger in x than y
		while (shipbb.max.x - shipbb.min.x > ww * 0.90)	ww *= 1.25;
		while (shipbb.max.y - shipbb.min.y > hh * 0.90)	hh *= 1.25;
	}
	else
	{
		// the ship and port have different x/y biggerness
		while (shipbb.max.x - shipbb.min.x > hh * 0.90)	hh *= 1.25;
		while (shipbb.max.y - shipbb.min.y > ww * 0.90)	ww *= 1.25;
	}
	
	ww *= 0.5;
	hh *= 0.5;
	
#ifndef NDEBUG
	if ([ship isPlayer] && (gDebugFlags & DEBUG_DOCKING))
	{
		BOOL			inLane;
		float			range;
		unsigned		laneFlags = 0;
		
		if (arbb.max.x < ww)   laneFlags |= 1;
		if (arbb.min.x > -ww)  laneFlags |= 2;
		if (arbb.max.y < hh)   laneFlags |= 4;
		if (arbb.min.y > -hh)  laneFlags |= 8;
		inLane = laneFlags == 0xF;
		range = 0.90 * arbb.max.z + 0.10 * arbb.min.z;
		
		OOLog(@"docking.debug", @"Normalised port dimensions are %g x %g x %g.  Player bounding box is at %@-%@ -- %s (%X), range: %g",
			ww * 2.0, hh * 2.0, dd,
			VectorDescription(arbb.min), VectorDescription(arbb.max),
			inLane ? "in lane" : "out of lane", laneFlags,
			range);
	}
#endif
	
	if (arbb.max.z < -dd)
	{
		return NO;
	}
	
	if ((arbb.max.x < ww)&&(arbb.min.x > -ww)&&(arbb.max.y < hh)&&(arbb.min.y > -hh))
	{
		if ([ship status] != STATUS_LAUNCHING && !allow_docking_thisship)
		{ // launch-only dock: will collide!
			if (arbb.min.z < dd)
			{
				[ship takeScrapeDamage: 5 * [UNIVERSE getTimeDelta]*[ship flightSpeed] from:station];
				// and bounce
				HPVector rel = HPvector_subtract([ship position],port_pos);
				rel = HPvector_multiply_scalar(HPvector_normal(rel),[ship flightSpeed]*0.4);
				[ship adjustVelocity:HPVectorToVector(rel)];
			}

			if (arbb.max.z < 0.0)
			{ // give some warning before exploding...
				return NO;
			}
		}

		// in lane
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)	// we're 90% in docking position!
		{
			[self pullInShipIfPermitted:ship];
		}
		return YES;
	}
	
	if ([ship status] == STATUS_LAUNCHING)
	{
		return YES;
	}
	
	// if close enough (within 50%) correct and add damage
	//
	GLfloat safety = 1.0+(01.0/100.0);

	if  ((arbb.min.x > -safety * ww)&&(arbb.max.x < safety * ww)&&(arbb.min.y > -safety * hh)&&(arbb.max.y < safety * hh))
	{
		if (arbb.min.z < 0.0)	// got our nose inside
		{
			GLfloat correction_factor = -arbb.min.z / (arbb.max.z - arbb.min.z);	// proportion of ship inside
		
			// damage the ship according to velocity - don't send collision messages to AIs to avoid problems.
			[ship takeScrapeDamage: 5 * [UNIVERSE getTimeDelta]*[ship flightSpeed] from:station];
			[station doScriptEvent:OOJSID("shipCollided") withArgument:ship]; // no COLLISION message to station AI, carriers would move away!
			[ship doScriptEvent:OOJSID("shipCollided") withArgument:station]; // no COLLISION message to ship AI, dockingAI.plist would abort.
			
			Vector delta;
			delta.x = 0.5f * (arbb.max.x + arbb.min.x) * correction_factor;
			delta.y = 0.5f * (arbb.max.y + arbb.min.y) * correction_factor;
			
			if (arbb.max.x < ww && arbb.min.x > -ww)
			{
				// x is okay - no need to correct
				delta.x = 0.0f;
			}
			if (arbb.max.y > hh && arbb.min.x > -hh)
			{
				// y is okay - no need to correct
				delta.y = 0.0f;
			}
				
			// adjust the ship back to the center of the port
			HPVector pos = [ship position];
			pos.x -= delta.y * vj.x + delta.x * vi.x;
			pos.y -= delta.y * vj.y + delta.x * vi.y;
			pos.z -= delta.y * vj.z + delta.x * vi.z;
			[ship setPosition:pos];
		}
		
		// if far enough in - dock
		if (0.90f * arbb.max.z + 0.10f * arbb.min.z < 0.0f)
		{
			[self pullInShipIfPermitted:ship];
		}
		
		return YES;	// okay NOW we're in the docking corridor!
	}
	
	return NO;
}


- (void) pullInShipIfPermitted:(ShipEntity *)ship
{
	// allow_docking: docking permitted and expected
	// disallowed_docking_collides: unauthorised docking does not result in explosion
	if (allow_docking || !disallowed_docking_collides)
	{
		[ship enterDock:(StationEntity*)[self parentEntity]];
	}
}


- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority
{
	[self pruneAndCountShipsOnApproach];
	
	if (ship == nil)  return;
	
	if (launchQueue == nil)
	{
		launchQueue = [[NSMutableArray alloc] init]; // retained
	}
	
	[ship setStatus:STATUS_DOCKED];
	if (priority)
	{
		[launchQueue insertObject:ship atIndex:0];
	}
	else
	{
		[launchQueue addObject:ship];
	}
}


- (void) launchShip:(ShipEntity *) ship
{
	if (![ship isShip])  return;
	
	BoundingBox		bb = [ship boundingBox];
	StationEntity	*station = (StationEntity *)[self parentEntity];
	
	HPVector launchPos = [self absolutePositionForSubentity];
	Vector launchVel = [station velocity];
	double launchSpeed = 0.5 * [ship maxFlightSpeed];
	if ([station maxFlightSpeed] > 0 && [station flightSpeed] > 0) // is self a carrier in flight.
	{
		launchSpeed = 0.5 * [ship maxFlightSpeed] * (1.0 + [station flightSpeed]/[station maxFlightSpeed]);
	}
	Quaternion q1 = [station orientation];
	q1 = quaternion_multiply(orientation, q1);
	Vector launchVector = vector_forward_from_quaternion(q1);
	
	// launch orientation
	if ((port_dimensions.x < port_dimensions.y) ^ (bb.max.x - bb.min.x < bb.max.y - bb.min.y))
	{
		quaternion_rotate_about_axis(&q1, launchVector, M_PI*0.5);  // to account for the slot being at 90 degrees to vertical
	}
	[ship setNormalOrientation:q1];
	// launch position
	[ship setPosition:launchPos];
	if([ship pendingEscortCount] > 0) [ship setPendingEscortCount:0]; // Make sure no extra escorts are added after launch. (e.g. for miners etc.)
	if ([ship hasEscorts]) no_docking_while_launching = YES;
	// launch speed
	launchVel = vector_add(launchVel, vector_multiply_scalar(launchVector, launchSpeed));
	launchSpeed = magnitude(launchVel);
	[ship setSpeed:launchSpeed];
	[ship setVelocity:launchVel];
	// launch roll/pitch
	[ship setRoll:[station flightRoll]];
	[ship setPitch:0.0];
	[ship setYaw:0.0];
	[UNIVERSE addEntity:ship];
	[ship setStatus: STATUS_LAUNCHING];
	[ship setDesiredSpeed:launchSpeed]; // must be set after initialising the AI to correct any speed set by AI
	last_launch_time = [UNIVERSE getTime];
	double delay = (port_corridor + 2 * port_dimensions.z)/launchSpeed; // pause until 2 portlengths outside of the station.
	[ship setLaunchDelay:delay];
	[[ship getAI] setNextThinkTime:last_launch_time + delay]; // pause while launching
	
	[ship resetExhaustPlumes];	// resets stuff for tracking/exhausts
	
	[ship doScriptEvent:OOJSID("shipWillLaunchFromStation") withArgument:station];
	[station doScriptEvent:OOJSID("stationLaunchedShip") withArgument:ship andReactToAIMessage: @"STATION_LAUNCHED_SHIP"];
}


- (NSUInteger) countOfShipsInLaunchQueueWithPrimaryRole:(NSString *)role
{
	NSUInteger count = 0;
	ShipEntity *ship = nil;
	foreach (ship, launchQueue)
	{
		if ([ship hasPrimaryRole:role])  count++;
	}
	return count;
}


- (BOOL) allowsLaunchingOf:(ShipEntity *) ship
{
	if (![ship isShip])  return NO;
	
	BoundingBox bb = [ship totalBoundingBox];
	if ((port_dimensions.x < (bb.max.x - bb.min.x) || port_dimensions.y < (bb.max.y - bb.min.y)) && 
		(port_dimensions.y < (bb.max.x - bb.min.x) || port_dimensions.x < (bb.max.y - bb.min.y)) && ![ship isPlayer])
	{
		return NO;
	}

	// callback to allow more complex filtering on accept/reject
	JSContext	*context = OOJSAcquireContext();
	jsval		rval = JSVAL_VOID;
	jsval		args[] = { OOJSValueFromNativeObject(context, ship) };
	JSBool accept = YES;
	
	BOOL OK = [[self script] callMethod:OOJSID("acceptLaunchingRequestFrom") inContext:context withArguments:args count:1 result:&rval];
	if (OK)  OK = JS_ValueToBoolean(context, rval, &accept);
	if (!OK)  accept = YES; // default to permreject
	OOJSRelinquishContext(context);
	if (!accept)
	{
		return NO;
	}

	return YES;
}	


- (void) clear
{
	[launchQueue removeAllObjects];
	[shipsOnApproach removeAllObjects];
}


- (BOOL) dockingCorridorIsEmpty
{
	double unitime = [UNIVERSE getTime];
	
	if (unitime < last_launch_time + STATION_DELAY_BETWEEN_LAUNCHES)
	{
		// leave sufficient pause between launches
		return NO;
	}
	
	// check against all ships
	StationEntity	*station = (StationEntity *)[self parentEntity];
	BOOL			isEmpty = YES;
	int				ent_count =		UNIVERSE->n_entities;
	Entity			**uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity			*my_entities[ent_count];
	int i;
	int ship_count = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		//on red alert, launch even if the player is trying block the corridor. Ignore cargopods or other small debris.
		if ([uni_entities[i] isShip] && ([station alertLevel] < STATION_ALERT_LEVEL_RED || ![uni_entities[i] isPlayer]) && [uni_entities[i] mass] > 1000)
		{
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
		}
	}

	for (i = 0; (i < ship_count)&&(isEmpty); i++)
	{
		ShipEntity*	ship = (ShipEntity*)my_entities[i];
		double		d2 = HPdistance2([station position], [ship position]);
		if ((ship != station) && (d2 < 25000000)&&([ship status] != STATUS_DOCKED))	// within 5km
		{
			HPVector ppos = [self absolutePositionForSubentity];
			d2 = HPdistance2(ppos, ship->position);
			if (d2 < 4000000)	// within 2km of the port entrance
			{
				Quaternion q1 = [station orientation];
				q1 = quaternion_multiply([self orientation], q1);
				//
				HPVector v_out = HPvector_forward_from_quaternion(q1);
				HPVector r_pos = make_HPvector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
				if (r_pos.x||r_pos.y||r_pos.z)
					r_pos = HPvector_normal(r_pos);
				else
					r_pos.z = 1.0;
				//
				double vdp = HPdot_product(v_out, r_pos); //== cos of the angle between r_pos and v_out
				//
				if (vdp > 0.86)
				{
					isEmpty = NO;
					last_launch_time = unitime - STATION_DELAY_BETWEEN_LAUNCHES + STATION_LAUNCH_RETRY_INTERVAL;
				}
			}
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		[my_entities[i] release];		//released
	}

	return isEmpty;
}


- (void) clearDockingCorridor
{
	// check against all ships
	StationEntity	*station = (StationEntity *)[self parentEntity];
	BOOL			isClear = YES;
	int				ent_count =			UNIVERSE->n_entities;
	Entity			**uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity			*my_entities[ent_count];
	int i;
	int ship_count = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		if (uni_entities[i]->isShip)
		{
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
		}
	}

	for (i = 0; i < ship_count; i++)
	{
		ShipEntity	*ship = (ShipEntity*)my_entities[i];
		double		d2 = HPdistance2([station position], [ship position]);
		if ((ship != station)&&(d2 < 25000000)&&([ship status] != STATUS_DOCKED))	// within 5km
		{
			HPVector ppos = [self absolutePositionForSubentity];
			float time_out = -15.00;	// 15 secs
			do
			{
				isClear = YES;
				d2 = HPdistance2(ppos, ship->position);
				if (d2 < 4000000)	// within 2km of the port entrance
				{
					Quaternion q1 = [station orientation];
					q1 = quaternion_multiply([self orientation], q1);
					//
					Vector v_out = vector_forward_from_quaternion(q1);
					Vector r_pos = make_vector(ship->position.x - ppos.x, ship->position.y - ppos.y, ship->position.z - ppos.z);
					if (r_pos.x||r_pos.y||r_pos.z)
						r_pos = vector_normal(r_pos);
					else
						r_pos.z = 1.0;
					//
					double vdp = dot_product(v_out, r_pos); //== cos of the angle between r_pos and v_out
					//
					if (vdp > 0.86)
					{
						isClear = NO;
						
						// okay it's in the way .. give it a wee nudge (0.25s)
						[ship update: 0.25];
						time_out += 0.25;
					}
					if (time_out > 0)
					{
						HPVector v1 = HPvector_forward_from_quaternion(orientation);
						HPVector spos = ship->position;
						spos.x += 3000.0 * v1.x;	spos.y += 3000.0 * v1.y;	spos.z += 3000.0 * v1.z; 
						[ship setPosition:spos]; // move 3km out of the way
					}
				}
			} while (!isClear);
		}
	}
	
	for (i = 0; i < ship_count; i++)
	{
		[my_entities[i] release];		//released
	}

}


- (void)setDimensionsAndCorridor:(BOOL)docking :(BOOL)ddc :(BOOL)launching
{
	StationEntity *station = (StationEntity*)[self parentEntity];
	if (virtual_dock)
	{
		port_dimensions = [station virtualPortDimensions];
	}
	else
	{
		BoundingBox bb = [self boundingBox];
		port_dimensions = make_vector(bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z);
	}

	HPVector vk = HPvector_forward_from_quaternion(orientation);
	
	BoundingBox stbb = [station boundingBox];
	HPVector start = position;
	while ((start.x > stbb.min.x)&&(start.x < stbb.max.x) &&
		   (start.y > stbb.min.y)&&(start.y < stbb.max.y) &&
		   (start.z > stbb.min.z)&&(start.z < stbb.max.z) )
	{
		start = HPvector_add(start, HPvector_multiply_scalar(vk, port_dimensions.z));
	}
	port_corridor = start.z - position.z;
	
	allow_docking = docking;
	disallowed_docking_collides = ddc;
	allow_launching = launching;
}



//////////////////////////////////////////////// from superclass

- (BOOL) isDock
{
	return YES;
}


- (id)initWithKey:(NSString *)key definition:(NSDictionary *)dict
{
	OOJS_PROFILE_ENTER
	
	self = [super initWithKey:key definition:dict];
	if (self != nil)
	{
		shipsOnApproach = [[NSMutableDictionary alloc] init];
		launchQueue = [[NSMutableArray alloc] init];
		allow_docking = YES;
		disallowed_docking_collides = NO;
		allow_launching = YES;
		virtual_dock = NO;
	}
	
	return self;
	
	OOJS_PROFILE_EXIT
}


- (void) dealloc
{
	DESTROY(shipsOnApproach);
	DESTROY(launchQueue);
	[self clearIdLocks:nil];
	
	[super dealloc];
}


- (void) clearIdLocks:(ShipEntity *)ship
{
	int i;
	for (i = 1; i < MAX_DOCKING_STAGES; i++)
	{
		if (ship == nil || ship == [id_lock[i] weakRefUnderlyingObject])
		{
			DESTROY(id_lock[i]);
		}
	}
}


- (BOOL) setUpShipFromDictionary:(NSDictionary *) dict
{
	OOJS_PROFILE_ENTER
	
	isShip = YES;
	isStation = NO;
	
	if (![super setUpShipFromDictionary:dict])  return NO;
	
	return YES;
	
	OOJS_PROFILE_EXIT
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	if (([launchQueue count] > 0)&&([shipsOnApproach count] == 0)&&[self dockingCorridorIsEmpty])
	{
		ShipEntity *se=(ShipEntity *)[launchQueue objectAtIndex:0];
		[self launchShip:se];
		[launchQueue removeObjectAtIndex:0];
	}
	if (([launchQueue count] == 0) && no_docking_while_launching)
	{
		no_docking_while_launching = NO;	// launching complete
	}
	
	if (approach_spacing > 0.0)
	{
		approach_spacing -= delta_t * 10.0;	// reduce by 10 m/s
		if (approach_spacing < 0.0)   approach_spacing = 0.0;
	}
}


// avoid possibility of shooting the virtual dock damaging the station
- (void) noteTakingDamage:(double)amount from:(Entity *)entity type:(OOShipDamageType)type
{
	if (virtual_dock) // can't be damaged
	{
		return;
	}
	[super noteTakingDamage:amount from:entity type:type];
}


- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	if (virtual_dock) // can't be damaged
	{
		return;
	}
	[super takeEnergyDamage:amount from:ent becauseOf:other];
}


// virtual docks are invisible
- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	if (virtual_dock) // not drawn
	{
		return;
	}
	[super drawImmediate:immediate translucent:translucent];
}

@end
