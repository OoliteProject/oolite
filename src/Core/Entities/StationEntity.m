/*

StationEntity.m

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

#import "StationEntity.h"
#import "DockEntity.h"
#import "ShipEntityAI.h"
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"
#import "OOFilteringEnumerator.h"

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


@interface StationEntity (OOPrivate)

- (BOOL) fitsInDock:(ShipEntity *)ship;
- (void) pullInShipIfPermitted:(ShipEntity *)ship;
- (void) addShipToStationCount:(ShipEntity *)ship;

- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority;
- (unsigned) countShipsInLaunchQueueWithPrimaryRole:(NSString *)role;

@end


#ifndef NDEBUG
@interface StationEntity (mwDebug)

- (NSArray *) dbgGetShipsOnApproach;
- (NSArray *) dbgGetIdLocks;
- (NSString *) dbgDumpIdLocks;
@end
#endif


@implementation StationEntity

- (OOTechLevelID) equivalentTechLevel
{
	return equivalentTechLevel;
}


- (void) setEquivalentTechLevel:(OOTechLevelID) value
{
	equivalentTechLevel = value;
}


- (double) port_radius
{
	return port_radius;
}


- (Vector) getBeaconPosition
{
	double buoy_distance = 10000.0;				// distance from station entrance
	Vector result = position;
	Vector v_f = vector_forward_from_quaternion(orientation);
	result.x += buoy_distance * v_f.x;
	result.y += buoy_distance * v_f.y;
	result.z += buoy_distance * v_f.z;
	return result;
}


- (float) equipmentPriceFactor
{
	return equipmentPriceFactor;
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


- (NSMutableArray *) initialiseLocalMarketWithRandomFactor:(int) random_factor
{
	return [self initialiseMarketWithSeed:[PLAYER system_seed] andRandomFactor:random_factor];
}


- (NSMutableArray *) initialiseMarketWithSeed:(Random_Seed) s_seed andRandomFactor:(int) random_factor
{
	int tmp_seed = ranrot_rand();
	int rf = (random_factor ^ universalID) & 0xff;
	int economy = [[UNIVERSE generateSystemData:s_seed] oo_intForKey:KEY_ECONOMY];
	if (localMarket)
		[localMarket release];
	localMarket = [[NSMutableArray alloc] initWithArray:[UNIVERSE commodityDataForEconomy:economy andStation:self andRandomFactor:rf]];
	ranrot_srand(tmp_seed);
	return localMarket;
}


- (void) setPlanet:(OOPlanetEntity *)planet_entity
{
	if (planet_entity)
		planet = [planet_entity universalID];
	else
		planet = NO_TARGET;
}


- (OOPlanetEntity *) planet
{
	return [UNIVERSE entityForUniversalID:planet];
}


- (unsigned) dockedContractors
{
	return max_scavengers > scavengers_launched ? max_scavengers - scavengers_launched : 0;
}


- (unsigned) dockedPolice
{
	return max_police > defenders_launched ? max_police - defenders_launched : 0;
}


- (unsigned) dockedDefenders
{
	return max_defense_ships > defenders_launched ? max_defense_ships - defenders_launched : 0;
}


- (NSEnumerator *)dockSubEntityEnumerator
{
	return [[self subEntities] objectEnumeratorFilteredWithSelector:@selector(isDock)];
}


- (void) sanityCheckShipsOnApproach
{

	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	unsigned soa = 0;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		soa += [sub sanityCheckShipsOnApproach];
	}

	if (soa == 0)
	{ // if all docks have no ships on approach
		[shipAI message:@"DOCKING_COMPLETE"];
	}
	
	NSArray *ships = [shipsOnHold allKeys];
	for (unsigned i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ((sid == NO_TARGET)||(![UNIVERSE entityForUniversalID:sid]))
		{
			[shipsOnHold removeObjectForKey:[ships objectAtIndex:i]];
		}
	}
}


// only used by player - everything else ends up in a Dock's launch queue
- (void) launchShip:(ShipEntity*)ship
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	
// try to find an unused dock first
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsLaunching] && [sub launchQueueSize] == 0) 
		{
			[sub launchShip:ship];
			return;
		}
	}
// otherwise any launchable dock will do
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsLaunching]) 
		{
			[sub launchShip:ship];
			return;
		}
	}

// ship has no launch	docks specified; just use the last one
	if (sub != nil)
	{
		[sub launchShip:ship];
		return;
	}
	// case where ship has no docks specified at all
	// legacy situation, so virtual dock will be at 0,0,0 and aligned to station

	Vector launchPos = position;
	Vector launchVel = [self velocity];
	double launchSpeed = 0.5 * [ship maxFlightSpeed];
	if ([self maxFlightSpeed] > 0 && [self flightSpeed] > 0) // is self a carrier in flight.
	{
		launchSpeed = 0.5 * [ship maxFlightSpeed] * (1.0 + [self flightSpeed]/[self maxFlightSpeed]);
	}
	Vector launchVector = vector_forward_from_quaternion(orientation);
	launchPos = vector_add(launchPos,vector_multiply_scalar(launchVector,port_radius));
	Quaternion q1 = orientation;
	if ([ship isPlayer]) q1.w = -q1.w; // need this as a fix for the player and before shipWillLaunchFromStation.
	[ship setOrientation:q1];
	[ship setPosition:launchPos];
	if([ship pendingEscortCount] > 0) [ship setPendingEscortCount:0]; // Make sure no extra escorts are added after launch. (e.g. for miners etc.)
	if ([ship hasEscorts]) no_docking_while_launching = YES;
		launchVel = vector_add(launchVel, vector_multiply_scalar(launchVector, launchSpeed));
	launchSpeed = magnitude(launchVel);
	[ship setSpeed:launchSpeed];
	[ship setVelocity:launchVel];
	// launch roll/pitch
	[ship setRoll: flightRoll];
	[ship setPitch:0.0];
	[UNIVERSE addEntity:ship];
	[ship setStatus: STATUS_LAUNCHING];
	[ship setDesiredSpeed:launchSpeed]; // must be set after initialising the AI to correct any speed set by AI
	last_launch_time = [UNIVERSE getTime];
	double delay = 1.1*collision_radius/launchSpeed;
	[ship setLaunchDelay:delay];
	[[ship getAI] setNextThinkTime:last_launch_time + delay]; // pause while launching
	
	[ship resetExhaustPlumes];	// resets stuff for tracking/exhausts
	
	[ship doScriptEvent:OOJSID("shipWillLaunchFromStation") withArgument:self];
	[self doScriptEvent:OOJSID("stationLaunchedShip") withArgument:ship andReactToAIMessage: @"STATION_LAUNCHED_SHIP"];
}


// Exposed to AI
- (void) abortAllDockings
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub abortAllDockings];
	}

	NSArray *ships = [shipsOnHold allKeys];
	for (unsigned i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
			[[[UNIVERSE entityForUniversalID:sid] getAI] message:@"DOCKING_ABORTED"];
	}
	[shipsOnHold removeAllObjects];
	
	[shipAI message:@"DOCKING_COMPLETE"];

}


- (void) autoDockShipsInQueue:(NSMutableDictionary *)queue
{
	NSArray		*ships = [queue allKeys];
	unsigned	i, count = [ships count];
	
	for (i = 0; i < count; i++)
	{
		ShipEntity *ship = [UNIVERSE entityForUniversalID:[ships oo_unsignedIntAtIndex:i]];
		if ([ship isShip])
		{
			[self pullInShipIfPermitted:ship];
		}
	}
	
	[queue removeAllObjects];
}


- (void) autoDockShipsOnApproach
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub autoDockShipsOnApproach];
	}

	[self autoDockShipsInQueue:shipsOnHold];
	
	[shipAI message:@"DOCKING_COMPLETE"];
}


- (Vector) portUpVectorForShip:(ShipEntity*) ship
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub shipIsInDockingQueue:ship])
		{
			return [sub portUpVectorForShipsBoundingBox:[ship totalBoundingBox]];
		}
	}
	return kZeroVector;
}


NSDictionary *OOMakeDockingInstructions(OOUInteger station_id, Vector coords, float speed, float range, NSString *ai_message, NSString *comms_message, BOOL match_rotation)
{
	NSMutableDictionary *acc = [NSMutableDictionary dictionaryWithCapacity:8];
	[acc setObject:[NSString stringWithFormat:@"%.2f %.2f %.2f", coords.x, coords.y, coords.z] forKey:@"destination"];
	[acc oo_setFloat:speed forKey:@"speed"];
	[acc oo_setFloat:range forKey:@"range"];
	[acc oo_setInteger:station_id forKey:@"station_id"];
	[acc oo_setBool:match_rotation forKey:@"match_rotation"];
	if (ai_message)
	{
		[acc setObject:ai_message forKey:@"ai_message"];
	}
	if (comms_message)
	{
		[acc setObject:comms_message forKey:@"comms_message"];
	}
	return [NSDictionary dictionaryWithDictionary:acc];
}


// this routine does more than set coordinates - it provides a whole set of docking instructions and messages at each stage..
//
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *) ship
{	
	int			ship_id = [ship universalID];
	NSNumber	*shipID = [NSNumber numberWithUnsignedShort:ship_id];

	if (!ship)
		return nil;
	
	if (ship->isPlayer)
	{
		player_reserved_dock = nil; // clear any dock reservation for manual docking
	}

	if ((ship->isPlayer)&&([ship legalStatus] > 50))	// note: non-player fugitives dock as normal
	{
		// refuse docking to the fugitive player
		return OOMakeDockingInstructions(universalID, ship->position, 0, 100, @"DOCKING_REFUSED", @"[station-docking-refused-to-fugitive]", NO);
	}
	
	if	(magnitude2(velocity) > 1.0)		// no docking while moving
	{
		if (![shipsOnHold objectForKey:shipID])
			[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
		[shipsOnHold setObject: shipID forKey: shipID];
		return OOMakeDockingInstructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	if	(fabs(flightPitch) > 0.01 || fabs(flightYaw) > 0.01)		// no docking while pitching or yawing
	{
		if (![shipsOnHold objectForKey:shipID])
			[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
		[shipsOnHold setObject: shipID forKey: shipID];
		return OOMakeDockingInstructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
	}
	
	NSEnumerator	*subEnum = nil;
	DockEntity *chosenDock = nil;
	NSString *docking = nil;
	DockEntity* sub = nil;
	unsigned queue = 100;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub shipIsInDockingQueue:ship]) 
		{ // if already claimed a docking queue, use that one
			chosenDock = sub;
			break;
		}
		if (sub != player_reserved_dock)
		{
			docking = [sub canAcceptShipForDocking:ship];
			if ([docking isEqualToString:@"DOCKING_POSSIBLE"] && [sub dockingQueueSize] < queue) {
// try to select the dock with the fewest ships already enqueued
				chosenDock = sub;
				queue = [sub dockingQueueSize];
			}
		}
	}	
	if (chosenDock == nil) { // no docks accept this ship (or the player is blocking them)
		return OOMakeDockingInstructions(universalID, ship->position, 0, 100, docking, nil, NO);
	}

	// rolling is okay for some
	if	(fabs(flightRoll) > 0.01)		// rolling
	{
		BOOL isOffCentre = [chosenDock isOffCentre];

		if (isOffCentre)
		{
			if (![shipsOnHold objectForKey:shipID])
				[self sendExpandedMessage: @"[station-acknowledges-hold-position]" toShip: ship];
			[shipsOnHold setObject: shipID forKey: shipID];
			return OOMakeDockingInstructions(universalID, ship->position, 0, 100, @"HOLD_POSITION", nil, NO);
		}
	}
	
	// we made it through holding!
	//
	if ([shipsOnHold objectForKey:shipID])
		[shipsOnHold removeObjectForKey:shipID];
	
	[shipAI reactToMessage:@"DOCKING_REQUESTED" context:@"requestDockingCoordinates"];	// react to the request	

	return [chosenDock dockingInstructionsForShip:ship];
}


- (void) abortDockingForShip:(ShipEntity *) ship
{
	int			ship_id = [ship universalID];
	NSNumber	*shipID = [NSNumber numberWithUnsignedShort:ship_id];
	if ([UNIVERSE entityForUniversalID:[ship universalID]])
		[[[UNIVERSE entityForUniversalID:[ship universalID]] getAI] message:@"DOCKING_ABORTED"];
	
	if ([shipsOnHold objectForKey:shipID])
		[shipsOnHold removeObjectForKey:shipID];
	
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub abortDockingForShip:ship];
	}
	
	if ([ship isPlayer])
	{
		player_reserved_dock = nil;
	}

	[self sanityCheckShipsOnApproach];
}


//////////////////////////////////////////////// from superclass

- (id)initWithKey:(NSString *)key definition:(NSDictionary *)dict
{
	OOJS_PROFILE_ENTER
	
	self = [super initWithKey:key definition:dict];
	if (self != nil)
	{
		isStation = YES;
		
		shipsOnHold = [[NSMutableDictionary alloc] init];
		player_reserved_dock = nil;
	}
	
	return self;
	
	OOJS_PROFILE_EXIT
}


- (void) dealloc
{
	DESTROY(shipsOnHold);
	
	DESTROY(localMarket);
	DESTROY(localPassengers);
	DESTROY(localContracts);
	DESTROY(localShipyard);
	
	[super dealloc];
}


- (BOOL) setUpShipFromDictionary:(NSDictionary *) dict
{
	OOJS_PROFILE_ENTER
	
	isShip = YES;
	isStation = YES;
	alertLevel = STATION_ALERT_LEVEL_GREEN;
	
	port_radius = [dict oo_nonNegativeDoubleForKey:@"port_radius" defaultValue:500.0];
	
	// port_dimensions can be set for rock-hermits and other specials
	port_dimensions = make_vector(69, 69, 250);
	NSString *portDimensionsStr = [dict oo_stringForKey:@"port_dimensions"];
	if (portDimensionsStr != nil)   // this can be set for rock-hermits and other specials
	{
		NSArray* tokens = [portDimensionsStr componentsSeparatedByString:@"x"];
		if ([tokens count] == 3)
		{
			port_dimensions = make_vector([[tokens objectAtIndex:0] floatValue],
										  [[tokens objectAtIndex:1] floatValue],
										  [[tokens objectAtIndex:2] floatValue]);
		}
	}
	
	if (![super setUpShipFromDictionary:dict])  return NO;
	
	equivalentTechLevel = [dict oo_unsignedIntegerForKey:@"equivalent_tech_level" defaultValue:NSNotFound];
	max_scavengers = [dict oo_unsignedIntForKey:@"max_scavengers" defaultValue:3];
	max_defense_ships = [dict oo_unsignedIntForKey:@"max_defense_ships" defaultValue:3];
	max_police = [dict oo_unsignedIntForKey:@"max_police" defaultValue:STATION_MAX_POLICE];
	equipmentPriceFactor = [dict oo_nonNegativeFloatForKey:@"equipment_price_factor" defaultValue:1.0];
	equipmentPriceFactor = fmaxf(equipmentPriceFactor, 0.5f);
	hasNPCTraffic = [dict oo_fuzzyBooleanForKey:@"has_npc_traffic" defaultValue:(maxFlightSpeed == 0)]; // carriers default to NO
	hasPatrolShips = [dict oo_fuzzyBooleanForKey:@"has_patrol_ships" defaultValue:NO];
	suppress_arrival_reports = [dict oo_boolForKey:@"suppress_arrival_reports" defaultValue:NO];
	NSDictionary *universalInfo = [[UNIVERSE planetInfo] oo_dictionaryForKey:PLANETINFO_UNIVERSAL_KEY];
	
	// Non main stations may have requiresDockingClearance set to yes as a result of the code below,
	// but this variable should be irrelevant for them, as they do not make use of it anyway.
	requiresDockingClearance = [dict oo_boolForKey:@"requires_docking_clearance" defaultValue:
		universalInfo != nil ?	[universalInfo oo_boolForKey:@"stations_require_docking_clearance" defaultValue:NO] : NO];
	
	allowsFastDocking = [dict oo_boolForKey:@"allows_fast_docking" defaultValue:NO];
	
	allowsAutoDocking = [dict oo_boolForKey:@"allows_auto_docking" defaultValue:YES];
	
	interstellarUndockingAllowed = [dict oo_boolForKey:@"interstellar_undocking" defaultValue:NO];
	
	double unitime = [UNIVERSE getTime];

	if ([self hasNPCTraffic])  // removed the 'isRotatingStation' restriction.
	{
		docked_shuttles = ranrot_rand() & 3;   // 0..3;
		shuttle_launch_interval = 15.0 * 60.0;  // every 15 minutes
		last_shuttle_launch_time = unitime - (ranrot_rand() & 63) * shuttle_launch_interval / 60.0;
		
		docked_traders = 3 + (ranrot_rand() & 7);   // 1..3;
		trader_launch_interval = 3600.0 / docked_traders;  // every few minutes
		last_trader_launch_time = unitime + 60.0 - trader_launch_interval; // in one minute's time
	}
	else
	{
		docked_shuttles = 0;
		docked_traders = 0;   // 1..3;
	}
	
	patrol_launch_interval = 300.0;	// 5 minutes
	last_patrol_report_time = unitime - patrol_launch_interval;
	
	if ([self crew] == nil)
	{
		[self setCrew:[NSArray arrayWithObject:[OOCharacter characterWithRole:@"police" andOriginalSystem:[UNIVERSE systemSeed]]]];
	}
	
	if ([self group] == nil)
	{
		[self setGroup:[self stationGroup]];
	}
	return YES;
	
	OOJS_PROFILE_EXIT
}


/*- (void) setDockingPortModel:(ShipEntity*) dock_model :(Vector) dock_pos :(Quaternion) dock_q
{
	port_model = dock_model;
	
	port_position = dock_pos;
	port_orientation = dock_q;

	BoundingBox bb = [port_model boundingBox];
	port_dimensions = make_vector(bb.max.x - bb.min.x, bb.max.y - bb.min.y, bb.max.z - bb.min.z);

	Vector vk = vector_forward_from_quaternion(dock_q);
	
	if (bb.max.z > 0.0)
	{
		port_position.x += bb.max.z * vk.x;
		port_position.y += bb.max.z * vk.y;
		port_position.z += bb.max.z * vk.z;
	}
	
	// check if start is within bounding box...
	Vector start = port_position;
	while (	(start.x > boundingBox.min.x)&&(start.x < boundingBox.max.x)&&
		   (start.y > boundingBox.min.y)&&(start.y < boundingBox.max.y)&&
		   (start.z > boundingBox.min.z)&&(start.z < boundingBox.max.z) )
	{
		start = vector_add(start, vector_multiply_scalar(vk, port_dimensions.z));
	}
	port_corridor = start.z - port_position.z; // length of the docking tunnel.
	}*/


- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship
{
	if (![ship isShip])  return NO;
	if ([ship isPlayer] && [ship status] == STATUS_DEAD)  return NO;

	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	unsigned docks = 0;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub shipIsInDockingCorridor:ship])
		{
			return YES;
		}
		docks++;
	}
	if (docks > 0) 
	{
		return NO;
	}
// handle case where station has no dock subentities (legacy case)
	
	Vector vi = vector_right_from_quaternion(orientation);
	Vector vj = vector_up_from_quaternion(orientation);
	Vector vk = vector_forward_from_quaternion(orientation);
	Vector port_pos = vector_add(position,vector_multiply_scalar(vk,port_radius));

	BoundingBox shipbb = [ship boundingBox];
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: port_pos InVectors: vi : vj : vk];
	
	// port dimensions..
	GLfloat ww = port_dimensions.x;
	GLfloat hh = port_dimensions.y;
	GLfloat dd = port_dimensions.z;

	while (shipbb.max.x - shipbb.min.x > ww * 0.90)	ww *= 1.25;
	while (shipbb.max.y - shipbb.min.y > hh * 0.90)	hh *= 1.25;
	
	ww *= 0.5;
	hh *= 0.5;

	if (arbb.max.z < -dd)
		return NO;

	if ((arbb.max.x < ww)&&(arbb.min.x > -ww)&&(arbb.max.y < hh)&&(arbb.min.y > -hh))
	{
		if (0.90 * arbb.max.z + 0.10 * arbb.min.z < 0.0)	// we're 90% in docking position!
		{
			[self pullInShipIfPermitted:ship];
		}
		return YES;
	}

	return NO;
}

	


- (void) pullInShipIfPermitted:(ShipEntity *)ship
{
#if 0
	/*
		Experiment: allow station script to deny physical docking capability.
		Doesn't work properly because the collision detection for docking ports
		isn't designed to support this, and you can fly past the back and
		sometimes straight through.
		-- Ahruman 2011-01-29
	*/
/* allow_docking on DockEntity now gives working collision detection
 * for this case, so it could be resurrected that way - CIM */
	if (EXPECT_NOT(ship == nil))  return;
	
	JSContext	*context = OOJSAcquireContext();
	jsval		rval = JSVAL_VOID;
	jsval		args[] = { OOJSValueFromNativeObject(context, ship) };
	JSBool		permit = YES;
	
	BOOL OK = [[self script] callMethod:OOJSID("permitDocking") inContext:context withArguments:args count:1 result:&rval];
	if (OK)  OK = JS_ValueToBoolean(context, rval, &permit);
	if (!OK)  permit = YES; // In case of error, default to common behaviour.
#else
	BOOL permit = YES;
#endif
	if (permit)  [ship enterDock:self];
}


- (BOOL) dockingCorridorIsEmpty
{
	if (!UNIVERSE)
		return NO;

	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub dockingCorridorIsEmpty])
		{
			return YES; // if any are
		}
	}
	return NO;
}


- (void) clearDockingCorridor
{
	if (!UNIVERSE)
		return;

	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub clearDockingCorridor];
	}		

	return;
}


- (void) update:(OOTimeDelta) delta_t
{
	BOOL isRockHermit = (scanClass == CLASS_ROCK);
	BOOL isMainStation = (self == [UNIVERSE station]);
	
	double unitime = [UNIVERSE getTime];
	
	[super update:delta_t];

	PlayerEntity *player = PLAYER;

	BOOL isDockingStation = (self == [player getTargetDockStation]);
	if (isDockingStation && [player status] == STATUS_IN_FLIGHT)
	{
		if ([player getDockingClearanceStatus] >= DOCKING_CLEARANCE_STATUS_GRANTED)
		{
			if (last_launch_time-30 < unitime && [player getDockingClearanceStatus] != DOCKING_CLEARANCE_STATUS_TIMING_OUT)
			{
				[self sendExpandedMessage:DESC(@"station-docking-clearance-about-to-expire") toShip:player];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_TIMING_OUT];
			}
			else if (last_launch_time < unitime)
			{
				[self sendExpandedMessage:DESC(@"station-docking-clearance-expired") toShip:player];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];	// Docking clearance for player has expired.
				if ([self currentlyInDockingQueues] == 0) [[self getAI] message:@"DOCKING_COMPLETE"];
				player_reserved_dock = nil;
			}
		}

		else if ([player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED)
		{
			if (last_launch_time < unitime)
			{
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
				if ([self currentlyInDockingQueues] == 0) [[self getAI] message:@"DOCKING_COMPLETE"];
			}
		}

		else if ([player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED &&
				[self hasClearDock])
		{
			DockEntity* dock = [self getClearDock];
			last_launch_time = unitime + DOCKING_CLEARANCE_WINDOW;
			if ([self hasMultipleDocks]) 
			{
				[self sendExpandedMessage:[NSString stringWithFormat:
								DESC(@"station-docking-clearance-granted-in-@-until-@"),
								[dock displayName],
								ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO)]
					toShip:player];
			}
			else
			{
				[self sendExpandedMessage:[NSString stringWithFormat:
								DESC(@"station-docking-clearance-granted-until-@"),
								ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO)]
					toShip:player];
			}
			player_reserved_dock = dock;
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
		}
	}
	
	
	if (approach_spacing > 0.0)
	{
		approach_spacing -= delta_t * 10.0;	// reduce by 10 m/s
		if (approach_spacing < 0.0)   approach_spacing = 0.0;
	}
	if ((docked_shuttles > 0)&&(!isRockHermit))
	{
		if (unitime > last_shuttle_launch_time + shuttle_launch_interval)
		{
			if (([self hasNPCTraffic])&&(aegis_status != AEGIS_NONE))
			{
				[self launchShuttle];
			}
			last_shuttle_launch_time = unitime;
		}
	}

	if ((docked_traders > 0)&&(!isRockHermit))
	{
		if (unitime > last_trader_launch_time + trader_launch_interval)
		{
			if ([self hasNPCTraffic])
			{
				[self launchIndependentShip:@"trader"];
				docked_traders--;
			}
			last_trader_launch_time = unitime;
		}
	}
	
	// testing patrols
	if (unitime > (last_patrol_report_time + patrol_launch_interval))
	{
		if (!((isMainStation && [self hasNPCTraffic]) || hasPatrolShips) || [self launchPatrol] != nil)
			last_patrol_report_time = unitime;
	}
}


- (void) clear
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub clear];
	}
	
	[shipsOnHold removeAllObjects];
}


- (BOOL) hasMultipleDocks
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	unsigned docks = 0;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		docks++;
		if (docks > 1) {
			return YES;
		}
	}
	return NO;
}


// is there a dock free for the player to dock manually?
- (BOOL) hasClearDock
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsDocking] && [sub launchQueueSize] == 0 && [sub dockingQueueSize] == 0)
		{
			return YES;
		}
	}
	return NO;
}


// is there any dock which may launch ships?
- (BOOL) hasLaunchDock
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsLaunching])
		{
			return YES;
		}
	}
	return NO;
}


- (DockEntity*) getClearDock
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsDocking] && [sub launchQueueSize] == 0 && [sub dockingQueueSize] == 0)
		{
			return sub;
		}
	}
	return nil;
}


- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority
{
	NSEnumerator	*subEnum = nil;
	DockEntity		*sub = nil;
	unsigned			threshold = 0;

	// quickest launch if we assign ships to those bays with no incoming ships
	// and spread the ships evenly around those bays
  // much easier if the station has at least one launch-only dock
	while (threshold < 16)
	{
		for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
		{
			if (sub != player_reserved_dock)
			{
				if ([sub dockingQueueSize] == 0)
				{
					if ([sub allowsLaunching] && [sub launchQueueSize] <= threshold)
					{
						if ([sub fitsInDock:ship])
						{
							[sub addShipToLaunchQueue:ship withPriority:priority];
							return;
						}
					}
				}
			}
		}
		threshold++;
	}
	// if we get this far, all docks have at least some incoming traffic.
	// usually most efficient (since launching is far faster than docking)
	// to assign all ships to the *same* dock with the smallest incoming queue
  // rather than to try spreading them out across several queues
  // also stops escorts being launched before their mothership 
	threshold = 0;
	while (threshold < 16)
	{
		for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
		{
			if (sub != player_reserved_dock)
			{
// so this time as long as it allows launching only check the docking queue size
// so long as enumerator order is deterministic, this will assign
// every launch this update to the same dock
// (edge case where new docking ship appears in the middle, probably
// not a problem)
				if ([sub allowsLaunching] && [sub dockingQueueSize] <= threshold)
				{
					if ([sub fitsInDock:ship])
					{
						[sub addShipToLaunchQueue:ship withPriority:priority];
						return;
					}
				}
			}
		}
		threshold++;
	}
	
	OOLog(@"station.launchShip.failed", @"Cancelled launch for a %@ with role %@, as the %@ has too many ships in its launch queue(s) or no suitable launch docks.",
			  [ship displayName], [ship primaryRole], [self displayName]);
}


- (unsigned) countShipsInLaunchQueueWithPrimaryRole:(NSString *)role
{
	unsigned result = 0;
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		result += [sub countShipsInLaunchQueueWithPrimaryRole:role];
	}
	return result;
}


- (BOOL) fitsInDock:(ShipEntity *) ship
{
	if (![ship isShip])  return NO;
	
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub fitsInDock:ship])
		{
			return YES;
		}
	}

	OOLog(@"station.launchShip.failed", @"Cancelled launch for a %@ with role %@, as it is too large for the docking port of the %@.",
			  [ship displayName], [ship primaryRole], [self displayName]);
	return NO;
}	

	
- (void) noteDockedShip:(ShipEntity *) ship
{
	if (ship == nil)  return;	
	
	PlayerEntity *player = PLAYER;
	// set last launch time to avoid clashes with outgoing ships
	if ([player getDockingClearanceStatus] != DOCKING_CLEARANCE_STATUS_GRANTED)
	{ // avoid interfering with docking clearance on another bay
		last_launch_time = [UNIVERSE getTime];
	}
	[self addShipToStationCount: ship];
	
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub noteDockingForShip:ship];
	}
	[self sanityCheckShipsOnApproach];
	
	[self doScriptEvent:OOJSID("otherShipDocked") withArgument:ship];
	
	BOOL isDockingStation = (self == [player getTargetDockStation]);
	if (isDockingStation && [player status] == STATUS_IN_FLIGHT &&
			[player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		if (![self hasClearDock])
		{ // then say why
			if ([self currentlyInDockingQueues])
			{
				[self sendExpandedMessage:[NSString stringWithFormat:
																														 DESC(@"station-docking-clearance-holding-d-ships-approaching"),
																													 [self currentlyInDockingQueues]+1] toShip:player];
			}
			else if([self currentlyInLaunchingQueues])
			{
				[self sendExpandedMessage:[NSString stringWithFormat:
																														 DESC(@"station-docking-clearance-holding-d-ships-departing"),
																													 [self currentlyInLaunchingQueues]+1] toShip:player];
			}
		} 
	}


	if ([ship isPlayer])
	{
		player_reserved_dock = nil;
	}
}

- (void) addShipToStationCount:(ShipEntity *) ship
{
 	if ([ship isShuttle])  docked_shuttles++;
	else if ([ship isTrader] && ![ship isPlayer])  docked_traders++;
	else if (([ship isPolice] && ![ship isEscort]) || [ship hasPrimaryRole:@"defense_ship"])
	{
		if (0 < defenders_launched)  defenders_launched--;
	}
	else if ([ship hasPrimaryRole:@"scavenger"] || [ship hasPrimaryRole:@"miner"])	// treat miners and scavengers alike!
	{
		if (0 < scavengers_launched)  scavengers_launched--;
	}
}


- (BOOL) interstellarUndockingAllowed
{
	return interstellarUndockingAllowed;
}


- (BOOL)hasNPCTraffic
{
	return hasNPCTraffic;
}


- (void)setHasNPCTraffic:(BOOL)flag
{
	hasNPCTraffic = flag != NO;
}


- (BOOL) collideWithShip:(ShipEntity *)other
{
	// 2010.06.10 - Micha. Commented out as there doesn't appear to be a good
	//				reason for it and it interferes with docking clearance.
	//[self abortAllDockings];
	return [super collideWithShip:other];
}


- (BOOL) hasHostileTarget
{
	return [super hasHostileTarget] || (alertLevel == STATION_ALERT_LEVEL_YELLOW) || (alertLevel == STATION_ALERT_LEVEL_RED);
}

- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	//stations must ignore friendly fire, otherwise the defenders' AI gets stuck.
	BOOL			isFriend = NO;
	OOShipGroup		*group = [self group];
	
	if ([other isShip] && group != nil)
	{
		OOShipGroup *otherGroup = [(ShipEntity *)other group];
		isFriend = otherGroup == group || [otherGroup leader] == self;
	}
	
	// If this is the system's main station...
	if (self == [UNIVERSE station] && !isFriend)
	{
		//...get angry

		BOOL isEnergyMine = [ent isCascadeWeapon];
		unsigned b=isEnergyMine ? 96 : 64;
		if ([(ShipEntity*)other bounty] >= b)	//already a hardened criminal?
		{
			b *= 1.5; //bigger bounty!
		}
		[(ShipEntity*)other markAsOffender:b withReason:kOOLegalStatusReasonAttackedMainStation];
		
		[self setPrimaryAggressor:other];
		found_target = primaryAggressor;
		[self launchPolice];

		if (isEnergyMine) //don't blow up!
		{
			[self increaseAlertLevel];
			[self respondToAttackFrom:ent becauseOf:other];
			return;
		}
	}
	// Stop damage if main station & close to death!
	if (!isFriend && (self != [UNIVERSE station] || amount < energy) )
	{
		// Handle damage like a ship.
		[super takeEnergyDamage:amount from:ent becauseOf:other];
	}
}

- (void) adjustVelocity:(Vector) xVel
{
	if (self != [UNIVERSE station])  [super adjustVelocity:xVel]; //dont get moved
}

- (void)takeScrapeDamage:(double)amount from:(Entity *)ent
{
	// Stop damage if main station
	if (self != [UNIVERSE station])  [super takeScrapeDamage:amount from:ent];
}


- (void) takeHeatDamage:(double)amount
{
	// Stop damage if main station
	if (self != [UNIVERSE station])  [super takeHeatDamage:amount];
}


- (OOStationAlertLevel) alertLevel
{
	return alertLevel;
}


- (void) setAlertLevel:(OOStationAlertLevel)level signallingScript:(BOOL)signallingScript
{
	if (level < STATION_ALERT_LEVEL_GREEN)  level = STATION_ALERT_LEVEL_GREEN;
	if (level > STATION_ALERT_LEVEL_RED)  level = STATION_ALERT_LEVEL_RED;
	
	if (alertLevel != level)
	{
		OOStationAlertLevel oldLevel = alertLevel;
		alertLevel = level;
		if (signallingScript)
		{
			ShipScriptEventNoCx(self, "alertConditionChanged", INT_TO_JSVAL(level), INT_TO_JSVAL(oldLevel));
		}
		switch (level)
		{
			case STATION_ALERT_LEVEL_GREEN:
				[shipAI reactToMessage:@"GREEN_ALERT" context:nil];
				break;
				
			case STATION_ALERT_LEVEL_YELLOW:
				[shipAI reactToMessage:@"YELLOW_ALERT" context:nil];
				break;
				
			case STATION_ALERT_LEVEL_RED:
				[shipAI reactToMessage:@"RED_ALERT" context:nil];
				break;
		}
	}
}


// Exposed to AI
- (ShipEntity *) launchIndependentShip:(NSString*) role
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a ship with role %@, as the %@ has no launch docks.",
			  role, [self displayName]);
		return nil;
	}

	BOOL			trader = [role isEqualToString:@"trader"];
	BOOL			sunskimmer = ([role isEqualToString:@"sunskim-trader"]);
	ShipEntity		*ship = nil;
	NSString		*defaultRole = @"escort";
	NSString		*escortRole = nil;
	NSString		*escortShipKey = nil;
	NSDictionary	*traderDict = nil;

	if((trader && (randf() < 0.1)) || sunskimmer) 
	{
		ship = [UNIVERSE newShipWithRole:@"sunskim-trader"];
		sunskimmer = true;
		trader = true;
		role = @"trader"; // make sure also sunskimmers get trader role.
	}
	else
	{
		ship = [UNIVERSE newShipWithRole:role];
	}

	if (![self fitsInDock:ship])
	{
		[ship release];
		return nil;
	}
	
	if (ship)
	{
		traderDict = [ship shipInfoDictionary];
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: role
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[ship setPrimaryRole:role];

		if(trader || ship->scanClass == CLASS_NOT_SET) [ship setScanClass: CLASS_NEUTRAL]; // keep defined scanclasses for non-traders.
		
		if (trader)
		{
			[ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
			[ship setCargoFlag:CARGO_FLAG_FULL_PLENTIFUL];
			if (sunskimmer) 
			{
				[UNIVERSE makeSunSkimmer:ship andSetAI:YES];
			}
			else
			{
				[ship switchAITo:@"exitingTraderAI.plist"];
				if([ship fuel] == 0) [ship setFuel:70];
				if ([ship hasRole:@"sunskim-trader"]) [UNIVERSE makeSunSkimmer:ship andSetAI:NO];
			}
		}
		
		[self addShipToLaunchQueue:ship withPriority:NO];

		OOShipGroup *escortGroup = [ship escortGroup];
		if ([ship group] == nil) [ship setGroup:escortGroup];
		// Eric: Escorts are defined both as _group and as _escortGroup because friendly attacks are only handled within _group.
		[escortGroup setLeader:ship];
				
		// add escorts to the trader
		unsigned escorts = [ship pendingEscortCount];
		if(escorts > 0)
		{
			escortRole = [traderDict oo_stringForKey:@"escort_role" defaultValue:nil];
			if (escortRole == nil)
				escortRole = [traderDict oo_stringForKey:@"escort-role" defaultValue:defaultRole];
			if (![escortRole isEqualToString: defaultRole])
			{
				if (![[UNIVERSE newShipWithRole:escortRole] autorelease])
				{
					escortRole = defaultRole;
				}
			}
			
			escortShipKey = [traderDict oo_stringForKey:@"escort_ship" defaultValue:nil];
			if (escortShipKey == nil)
				escortShipKey = [traderDict oo_stringForKey:@"escort-ship"];
			
			if (escortShipKey != nil)
			{
				if (![[UNIVERSE newShipWithName:escortShipKey] autorelease])
				{
					escortShipKey = nil;
				}
			}
				
			while (escorts--)
			{
				ShipEntity  *escort_ship;

				if (escortShipKey)
				{
					escort_ship = [UNIVERSE newShipWithName:escortShipKey];	// retained
				}
				else
				{
					escort_ship = [UNIVERSE newShipWithRole:escortRole];	// retained
				}
				
				if (escort_ship && [self fitsInDock:escort_ship])
				{
					if (![escort_ship crew] && ![escort_ship isUnpiloted])
						[escort_ship setCrew:[NSArray arrayWithObject:
							[OOCharacter randomCharacterWithRole: @"hunter"
							andOriginalSystem: [UNIVERSE systemSeed]]]];
							
					[escort_ship setScanClass: [ship scanClass]];
					[escort_ship setCargoFlag: CARGO_FLAG_FULL_PLENTIFUL];
					[escort_ship setPrimaryRole:@"escort"];					
					if ((sunskimmer || trader) && [escort_ship heatInsulation] < [ship heatInsulation]) 
							[escort_ship setHeatInsulation:[ship heatInsulation]];

					[escort_ship setGroup:escortGroup];
					[escort_ship setOwner:ship];
					
					[escort_ship switchAITo:@"escortAI.plist"];
					[self addShipToLaunchQueue:escort_ship withPriority:NO];
					
				}
				[escort_ship release];
			}
		}
		
		[ship setPendingEscortCount:0];
		[ship autorelease];
	}
	return ship;
}


//////////////////////////////////////////////// extra AI routines


// Exposed to AI
- (void) increaseAlertLevel
{
	[self setAlertLevel:[self alertLevel] + 1 signallingScript:YES];
}


// Exposed to AI
- (void) decreaseAlertLevel
{
	[self setAlertLevel:[self alertLevel] - 1 signallingScript:YES];
}


// Exposed to AI
- (NSArray *) launchPolice
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a police ship, as the %@ has no launch docks.",
			  [self displayName]);
		return [NSArray array];
	}

	OOUniversalID	police_target = primaryTarget;
	unsigned		i;
	NSMutableArray	*result = nil;
	OOTechLevelID	techlevel = [self equivalentTechLevel];
	if (techlevel == NSNotFound)  techlevel = 6;
	
	result = [NSMutableArray arrayWithCapacity:4];
	
	for (i = 0; (i < 4)&&(defenders_launched < max_police) ; i++)
	{
		ShipEntity  *police_ship = nil;
		if (![UNIVERSE entityForUniversalID:police_target])
		{
			[self noteLostTarget];
			return [NSArray array];
		}
		
		if ((Ranrot() & 7) + 6 <= techlevel)
		{
			police_ship = [UNIVERSE newShipWithRole:@"interceptor"];   // retain count = 1
		}
		else
		{
			police_ship = [UNIVERSE newShipWithRole:@"police"];   // retain count = 1
		}
		
		if (police_ship && [self fitsInDock:police_ship])
		{
			if (![police_ship crew])
			{
				[police_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole: @"police"
									   andOriginalSystem: [UNIVERSE systemSeed]]]];
			}
			
			[police_ship setGroup:[self stationGroup]];	// who's your Daddy
			[police_ship setPrimaryRole:@"police"];
			[police_ship addTarget:[UNIVERSE entityForUniversalID:police_target]];
			if ([police_ship scanClass] == CLASS_NOT_SET)
				[police_ship setScanClass: CLASS_POLICE];
			[police_ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
			if ([police_ship heatInsulation] < [self heatInsulation])
				[police_ship setHeatInsulation:[self heatInsulation]];
			[police_ship switchAITo:@"policeInterceptAI.plist"];
			[self addShipToLaunchQueue:police_ship withPriority:YES];
			defenders_launched++;
			[result addObject:police_ship];
		}
		[police_ship autorelease];
	}
	[self abortAllDockings];
	return result;
}


// Exposed to AI
- (ShipEntity *) launchDefenseShip
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a defense ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}

	OOUniversalID	defense_target = primaryTarget;
	ShipEntity	*defense_ship = nil;
	NSString	*defense_ship_key = nil,
				*defense_ship_role = nil,
				*default_defense_ship_role = nil;
	NSString	*defense_ship_ai = @"policeInterceptAI.plist";
	
	OOTechLevelID	techlevel;
	
	techlevel = [self equivalentTechLevel];
	if (techlevel == NSNotFound)  techlevel = 6;
	if ((Ranrot() & 7) + 6 <= techlevel)
		default_defense_ship_role	= @"interceptor";
	else
		default_defense_ship_role	= @"police";
		
	if (scanClass == CLASS_ROCK)
		default_defense_ship_role	= @"hermit-ship";
	
	if (defenders_launched >= max_defense_ships)   // shuttles are to rockhermits what police ships are to stations
		return nil;
	
	if (![UNIVERSE entityForUniversalID:defense_target])
	{
		[self noteLostTarget];
		return nil;
	}
	
	defense_ship_key = [shipinfoDictionary oo_stringForKey:@"defense_ship"];
	if (defense_ship_key != nil)
	{
		defense_ship = [UNIVERSE newShipWithName:defense_ship_key];
	}
	if (!defense_ship)
	{
		defense_ship_role = [shipinfoDictionary oo_stringForKey:@"defense_ship_role" defaultValue:default_defense_ship_role];
		defense_ship = [UNIVERSE newShipWithRole:defense_ship_role];
	}
	
	if (!defense_ship && default_defense_ship_role != defense_ship_role)
		defense_ship = [UNIVERSE newShipWithRole:default_defense_ship_role];

	if (!defense_ship || ![self fitsInDock:defense_ship])
	{
		[defense_ship release];
		return nil;
	}
	
	if ([defense_ship isPolice] || [defense_ship hasPrimaryRole:@"hermit-ship"])
	{
		[defense_ship switchAITo:defense_ship_ai];
	}
	
	[defense_ship setPrimaryRole:@"defense_ship"];
	
	defenders_launched++;
	
	if (![defense_ship crew])
	{
		[defense_ship setCrew:[NSArray arrayWithObject:
			[OOCharacter randomCharacterWithRole: @"hunter"
			andOriginalSystem: [UNIVERSE systemSeed]]]];
	}
				
	[defense_ship setOwner: self];
	if ([self group] == nil)
	{
		[self setGroup:[self stationGroup]];	
	}
	[defense_ship setGroup:[self stationGroup]];	// who's your Daddy
	
	[defense_ship addTarget:[UNIVERSE entityForUniversalID:defense_target]];

	if ((scanClass != CLASS_ROCK)&&(scanClass != CLASS_STATION))
	{
		[defense_ship setScanClass: scanClass];	// same as self
	}
	else if ([defense_ship scanClass] == CLASS_NOT_SET)
	{
		[defense_ship setScanClass: CLASS_NEUTRAL];
	}

	if ([defense_ship heatInsulation] < [self heatInsulation])
	{
		[defense_ship setHeatInsulation:[self heatInsulation]];
	}

	[self addShipToLaunchQueue:defense_ship withPriority:YES];
	[defense_ship autorelease];
	[self abortAllDockings];
	
	return defense_ship;
}


// Exposed to AI
- (ShipEntity *) launchScavenger
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a scavenger ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}

	ShipEntity  *scavenger_ship;
	
	unsigned scavs = [UNIVERSE countShipsWithPrimaryRole:@"scavenger" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countShipsInLaunchQueueWithPrimaryRole:@"scavenger"];
	
	if (scavs >= max_scavengers)  return nil;
	if (scavengers_launched >= max_scavengers)  return nil;
			
	scavenger_ship = [UNIVERSE newShipWithRole:@"scavenger"];   // retain count = 1
	
	if (![self fitsInDock:scavenger_ship])
	{
		[scavenger_ship release];
		return nil;
	}
	
	if (scavenger_ship)
	{
		if (![scavenger_ship crew])
			[scavenger_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		scavengers_launched++;
		[scavenger_ship setScanClass: CLASS_NEUTRAL];
		if ([scavenger_ship heatInsulation] < [self heatInsulation])
			[scavenger_ship setHeatInsulation:[self heatInsulation]];
		[scavenger_ship setGroup:[self stationGroup]];	// who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
		[scavenger_ship switchAITo:@"scavengerAI.plist"];
		[self addShipToLaunchQueue:scavenger_ship withPriority:NO];
		[scavenger_ship autorelease];
	}
	return scavenger_ship;
}


// Exposed to AI
- (ShipEntity *) launchMiner
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a miner ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}

	ShipEntity  *miner_ship;
	
	int		n_miners = [UNIVERSE countShipsWithPrimaryRole:@"miner" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countShipsInLaunchQueueWithPrimaryRole:@"miner"];
	
	if (n_miners >= 1)	// just the one
		return nil;
	
	// count miners as scavengers...
	if (scavengers_launched >= max_scavengers)  return nil;
	
	miner_ship = [UNIVERSE newShipWithRole:@"miner"];   // retain count = 1

	if (![self fitsInDock:miner_ship])
	{
		[miner_ship release];
		return nil;
	}
	
	if (miner_ship)
	{
		if (![miner_ship crew])
			[miner_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"miner"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		scavengers_launched++;
		[miner_ship setScanClass:CLASS_NEUTRAL];
		if ([miner_ship heatInsulation] < [self heatInsulation])
			[miner_ship setHeatInsulation:[self heatInsulation]];
		[miner_ship setGroup:[self stationGroup]];	// who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
		[miner_ship switchAITo:@"minerAI.plist"];
		[self addShipToLaunchQueue:miner_ship withPriority:NO];
		[miner_ship autorelease];
	}
	return miner_ship;
}

/**Lazygun** added the following method. A complete rip-off of launchDefenseShip. 
 */
// Exposed to AI
- (ShipEntity *) launchPirateShip
{
	if ([self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a pirate ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}
	//Pirate ships are launched from the same pool as defence ships.
	OOUniversalID	defense_target = primaryTarget;
	ShipEntity		*pirate_ship = nil;
	
	if (defenders_launched >= max_defense_ships)  return nil;   // shuttles are to rockhermits what police ships are to stations
	
	if (![UNIVERSE entityForUniversalID:defense_target])
	{
		[self noteLostTarget];
		return nil;
	}
	
	// Yep! The standard hermit defence ships, even if they're the aggressor.
	pirate_ship = [UNIVERSE newShipWithRole:@"pirate"];   // retain count = 1
	// Nope, use standard pirates in a generic method.
	
	if (![self fitsInDock:pirate_ship])
	{
		[pirate_ship release];
		return nil;
	}
		
	if (pirate_ship)
	{
		if (![pirate_ship crew])
		{
			[pirate_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"pirate"
								   andOriginalSystem: [UNIVERSE systemSeed]]]];
		}
				
		defenders_launched++;
		
		// set the owner of the ship to the station so that it can check back for docking later
		[pirate_ship setOwner:self];
		[pirate_ship setGroup:[self stationGroup]];	// who's your Daddy
		[pirate_ship setPrimaryRole:@"defense_ship"];
		[pirate_ship addTarget:[UNIVERSE entityForUniversalID:defense_target]];
		[pirate_ship setScanClass: CLASS_NEUTRAL];
		if ([pirate_ship heatInsulation] < [self heatInsulation])
			[pirate_ship setHeatInsulation:[self heatInsulation]];
		//**Lazygun** added 30 Nov 04 to put a bounty on those pirates' heads.
		[pirate_ship setBounty: 10 + floor(randf() * 20) withReason:kOOLegalStatusReasonSetup];	// modified for variety

		[self addShipToLaunchQueue:pirate_ship withPriority:NO];
		[pirate_ship autorelease];
		[self abortAllDockings];
	}
	return pirate_ship;
}


// Exposed to AI
- (ShipEntity *) launchShuttle
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a shuttle ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}
	ShipEntity  *shuttle_ship;
		
	shuttle_ship = [UNIVERSE newShipWithRole:@"shuttle"];   // retain count = 1
	
	if (![self fitsInDock:shuttle_ship])
	{
		[shuttle_ship release];
		return nil;
	}
	
	if (shuttle_ship)
	{
		if (![shuttle_ship crew])
			[shuttle_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"trader"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		docked_shuttles--;
		[shuttle_ship setScanClass: CLASS_NEUTRAL];
		[shuttle_ship setCargoFlag:CARGO_FLAG_FULL_SCARCE];
		[shuttle_ship switchAITo:@"fallingShuttleAI.plist"];
		[self addShipToLaunchQueue:shuttle_ship withPriority:NO];
		
		[shuttle_ship autorelease];
	}
	return shuttle_ship;
}


// Exposed to AI
- (void) launchEscort
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for an escort ship, as the %@ has no launch docks.",
			  [self displayName]);
		return;
	}
	ShipEntity  *escort_ship;
		
	escort_ship = [UNIVERSE newShipWithRole:@"escort"];   // retain count = 1
	
	if (escort_ship && [self fitsInDock:escort_ship])
	{
		if (![escort_ship crew] && ![escort_ship isUnpiloted])
			[escort_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		[escort_ship setScanClass: CLASS_NEUTRAL];
		[escort_ship setCargoFlag: CARGO_FLAG_FULL_PLENTIFUL];
		[escort_ship switchAITo:@"escortAI.plist"];
		[self addShipToLaunchQueue:escort_ship withPriority:NO];
		
	}
	[escort_ship release];
}


// Exposed to AI
- (ShipEntity *) launchPatrol
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a patrol ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}
	if (defenders_launched < max_police)
	{
		ShipEntity		*patrol_ship = nil;
		OOTechLevelID	techlevel;
		
		techlevel = [self equivalentTechLevel];
		if (techlevel == NSNotFound)
			techlevel = 6;
			
		if ((Ranrot() & 7) + 6 <= techlevel)
			patrol_ship = [UNIVERSE newShipWithRole:@"interceptor"];   // retain count = 1
		else
			patrol_ship = [UNIVERSE newShipWithRole:@"police"];   // retain count = 1

		if (![self fitsInDock:patrol_ship])
		{
			[patrol_ship release];
			return nil;
		}
		
		if (patrol_ship)
		{
			if (![patrol_ship crew])
				[patrol_ship setCrew:[NSArray arrayWithObject:
					[OOCharacter randomCharacterWithRole: @"police"
					andOriginalSystem: [UNIVERSE systemSeed]]]];
				
			defenders_launched++;
			[patrol_ship switchLightsOff];
			if ([patrol_ship scanClass] == CLASS_NOT_SET)
				[patrol_ship setScanClass: CLASS_POLICE];
			if ([patrol_ship heatInsulation] < [self heatInsulation])
				[patrol_ship setHeatInsulation:[self heatInsulation]];
			[patrol_ship setPrimaryRole:@"police"];
			[patrol_ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
			[patrol_ship setGroup:[self stationGroup]];	// who's your Daddy
			[patrol_ship switchAITo:@"planetPatrolAI.plist"];
			[self addShipToLaunchQueue:patrol_ship withPriority:NO];
			[self acceptPatrolReportFrom:patrol_ship];
			[patrol_ship autorelease];
			return patrol_ship;
		}
	}
	return nil;
}


// Exposed to AI
- (void) launchShipWithRole:(NSString*) role
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.failed", @"Cancelled launch for a ship with role %@, as the %@ has no launch docks.",
			  role, [self displayName]);
		return;
	}
	ShipEntity  *ship = [UNIVERSE newShipWithRole: role];   // retain count = 1
	if (ship && [self fitsInDock:ship])
	{
		if (![ship crew])
			[ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: role
				andOriginalSystem: [UNIVERSE systemSeed]]]];
		if (ship->scanClass == CLASS_NOT_SET) [ship setScanClass: CLASS_NEUTRAL];
		[ship setPrimaryRole:role];
		[ship setGroup:[self stationGroup]];	// who's your Daddy
		[self addShipToLaunchQueue:ship withPriority:NO];
	}
	[ship release];
}


// Exposed to AI
- (void) becomeExplosion
{
	if (self == [UNIVERSE station])  return;
	
	// launch docked ships if possible
	PlayerEntity* player = PLAYER;
	if ((player)&&([player status] == STATUS_DOCKED)&&([player dockedStation] == self))
	{
		// undock the player!
		[player leaveDock:self];
		[UNIVERSE setViewDirection:VIEW_FORWARD];
		[UNIVERSE setDisplayCursor:NO];
		[player warnAboutHostiles];	// sound a klaxon
	}
	
	if (scanClass == CLASS_ROCK)	// ie we're a rock hermit or similar
	{
		// set the role so that we break up into rocks!
		[self setPrimaryRole:@"asteroid"];
		being_mined = YES;
	}
	
	// finally bite the bullet
	[super becomeExplosion];
}


// Exposed to AI
- (void) becomeEnergyBlast
{
	if (self == [UNIVERSE station])  return;
	[super becomeEnergyBlast];
}


- (void) becomeLargeExplosion:(double) factor
{
	if (self == [UNIVERSE station])  return;
	[super becomeLargeExplosion:factor];
}


- (void) acceptPatrolReportFrom:(ShipEntity*) patrol_ship
{
	last_patrol_report_time = [UNIVERSE getTime];
}


// used by player
- (NSString *) acceptDockingClearanceRequestFrom:(ShipEntity *)other
{
	NSString	*result = nil;
	double		timeNow = [UNIVERSE getTime];
	PlayerEntity	*player = PLAYER;
	
	[UNIVERSE clearPreviousMessage];

	[self sanityCheckShipsOnApproach];

	// Docking clearance not required - clear it just in case it's been
	// set for another nearby station.
	if (![self requiresDockingClearance])
	{
		// TODO: We're potentially cancelling docking at another station, so
		//       ensure we clear the timer to allow NPC traffic.  If we
		//       don't, normal traffic will resume once the timer runs out.
		
		// No clearance is needed, but don't send friendly messages to hostile ships!
		if (!(([other isPlayer] && [other hasHostileTarget]) || (self == [UNIVERSE station] && [other bounty] > 50)))
			[self sendExpandedMessage:DESC(@"station-docking-clearance-not-required") toShip:other];
		if ([other isPlayer])
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NOT_REQUIRED];
		[shipAI reactToMessage:@"DOCKING_REQUESTED" context:nil];	// react to the request	
		last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
		result = @"DOCKING_CLEARANCE_NOT_REQUIRED";
	}

	// Docking clearance already granted for this station - check for
	// time-out or cancellation (but only for the Player).
	if( result == nil && [other isPlayer] && self == [player getTargetDockStation])
	{
		switch( [player getDockingClearanceStatus] )
		{
			case DOCKING_CLEARANCE_STATUS_TIMING_OUT:
				if (!no_docking_while_launching)
				{
					last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
					[self sendExpandedMessage:[NSString stringWithFormat:
						DESC(@"station-docking-clearance-extended-until-@"),
							ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO)]
						toShip:other];
					[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
					result = @"DOCKING_CLEARANCE_EXTENDED";
					break;
				}
				// else, continue with canceling.
			case DOCKING_CLEARANCE_STATUS_REQUESTED:
			case DOCKING_CLEARANCE_STATUS_GRANTED:
				last_launch_time = timeNow;
				[self sendExpandedMessage:DESC(@"station-docking-clearance-cancelled") toShip:other];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
				result = @"DOCKING_CLEARANCE_CANCELLED";
				player_reserved_dock = nil;
				if ([self currentlyInDockingQueues] == 0) [shipAI message:@"DOCKING_COMPLETE"];
				break;
			case DOCKING_CLEARANCE_STATUS_NONE:
			case DOCKING_CLEARANCE_STATUS_NOT_REQUIRED:
				break;
		}
	}

	// First we must set the status to REQUESTED to avoid problems when 
	// switching docking targets - even if we later set it back to NONE.
	if (result == nil && [other isPlayer] && self != [player getTargetDockStation])
	{
		player_reserved_dock = nil; // and clear any previously reserved dock
		[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_REQUESTED];
	}

	// Deny docking for fugitives at the main station
	// TODO: Should this be another key in shipdata.plist and/or should this
	//  apply to all stations?
	if (result == nil && self == [UNIVERSE station] && [other bounty] > 50)	// do not grant docking clearance to fugitives
	{
		[self sendExpandedMessage:DESC(@"station-docking-clearance-H-clearance-refused") toShip:other];
		if ([other isPlayer])
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		result = @"DOCKING_CLEARANCE_DENIED_SHIP_FUGITIVE";
	}
	
	if (result == nil && [other hasHostileTarget]) // do not grant docking clearance to hostile ships.
	{
		[self sendExpandedMessage:DESC(@"station-docking-clearance-denied") toShip:other];
		if ([other isPlayer])
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		result = @"DOCKING_CLEARANCE_DENIED_SHIP_HOSTILE";
	}

	if (![self hasClearDock]) // skip check if at least one dock clear
	{
		// Put ship in queue if we've got incoming or outgoing traffic
		if (result == nil && [self currentlyInDockingQueues] && last_launch_time < timeNow)
		{
			[self sendExpandedMessage:[NSString stringWithFormat:
																						DESC(@"station-docking-clearance-acknowledged-d-ships-approaching"),
																					[self currentlyInDockingQueues]+1] toShip:other];
			// No need to set status to REQUESTED as we've already done that earlier.
			result = @"DOCKING_CLEARANCE_DENIED_TRAFFIC_INBOUND";
		}
		if (result == nil && [self currentlyInLaunchingQueues])
		{
			[self sendExpandedMessage:[NSString stringWithFormat:
																						DESC(@"station-docking-clearance-acknowledged-d-ships-departing"),
																					[self currentlyInLaunchingQueues]+1] toShip:other];
			// No need to set status to REQUESTED as we've already done that earlier.
			result = @"DOCKING_CLEARANCE_DENIED_TRAFFIC_OUTBOUND";
		}
	}

	// Ship has passed all checks - grant docking!
	if (result == nil)
	{
		last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
		if ([other isPlayer]) 
		{
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
			player_reserved_dock = [self getClearDock];
		}

		if ([self hasMultipleDocks] && [other isPlayer])
		{
			[self sendExpandedMessage:[NSString stringWithFormat:
				DESC(@"station-docking-clearance-granted-in-@-until-@"),
					[player_reserved_dock displayName],
					ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO)]
				toShip:other];
		}
		else
		{
			[self sendExpandedMessage:[NSString stringWithFormat:
				DESC(@"station-docking-clearance-granted-until-@"),
					ClockToString([player clockTime] + DOCKING_CLEARANCE_WINDOW, NO)]
				toShip:other];
		}

		result = @"DOCKING_CLEARANCE_GRANTED";
		[shipAI reactToMessage:@"DOCKING_REQUESTED" context:nil];	// react to the request	
	}
	return result;
}


- (unsigned) currentlyInDockingQueues
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	unsigned soa = 0;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		soa += [sub dockingQueueSize];
	}
	return soa;
}


- (unsigned) currentlyInLaunchingQueues
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	unsigned soa = 0;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		soa += [sub launchQueueSize];
	}
	return soa;
}


- (BOOL) requiresDockingClearance
{
	return requiresDockingClearance;
}


- (void) setRequiresDockingClearance:(BOOL)newValue
{
	requiresDockingClearance = !!newValue;	// Ensure yes or no
}


- (BOOL) allowsFastDocking
{
	return allowsFastDocking;
}


- (void) setAllowsFastDocking:(BOOL)newValue
{
	allowsFastDocking = !!newValue;	// Ensure yes or no
}


- (BOOL) allowsAutoDocking
{
	return allowsAutoDocking;
}


- (void) setAllowsAutoDocking:(BOOL)newValue
{
	allowsAutoDocking = !!newValue; // Ensure yes or no
}


- (BOOL) isRotatingStation
{
	if ([shipinfoDictionary oo_boolForKey:@"rotating" defaultValue:NO])  return YES;
	return [[shipinfoDictionary objectForKey:@"roles"] rangeOfString:@"rotating-station"].location != NSNotFound;	// legacy
}


- (NSString *) marketOverrideName
{
	// 2010.06.14 - Micha - we can't default to the primary role as otherwise the logic
	//				generating the market in [Universe commodityDataForEconomy:] doesn't
	//				work properly with the various overrides.  The primary role will get
	//				used if either there is no market override, or the market wasn't
	//				defined.
	return [shipinfoDictionary oo_stringForKey:@"market"];
}


- (BOOL) hasShipyard
{
	if ([UNIVERSE strict])
		return NO;
	if ([UNIVERSE station] == self)
		return YES;
	id	determinant = [shipinfoDictionary objectForKey:@"has_shipyard"];

	if (!determinant)
		determinant = [shipinfoDictionary objectForKey:@"hasShipyard"];
		
	// NOTE: non-standard capitalization is documented and entrenched.
	if (determinant)
	{		
		if ([determinant isKindOfClass:[NSArray class]])
		{
			return [PLAYER scriptTestConditions:OOSanitizeLegacyScriptConditions(determinant, nil)];
		}
		else
		{
			return OOFuzzyBooleanFromObject(determinant, 0.0f);
		}
	}
	else
	{
		return NO;
	}
}


- (BOOL) suppressArrivalReports
{
	return suppress_arrival_reports;
}


- (void) setSuppressArrivalReports:(BOOL)newValue
{
	suppress_arrival_reports = !!newValue;	// ensure YES or NO
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\" %@", name, [super descriptionComponents]];
}


- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	NSString			*alertString = nil;
	
	[super dumpSelfState];
	
	switch (alertLevel)
	{
		case STATION_ALERT_LEVEL_GREEN:
			alertString = @"green";
			break;
		
		case STATION_ALERT_LEVEL_YELLOW:
			alertString = @"yellow";
			break;
		
		case STATION_ALERT_LEVEL_RED:
			alertString = @"red";
			break;
		
		default:
			alertString = @"*** ERROR: UNKNOWN ALERT LEVEL ***";
	}
	
	OOLog(@"dumpState.stationEntity", @"Alert level: %@", alertString);
	OOLog(@"dumpState.stationEntity", @"Max police: %u", max_police);
	OOLog(@"dumpState.stationEntity", @"Max defense ships: %u", max_defense_ships);
	OOLog(@"dumpState.stationEntity", @"Defenders launched: %u", defenders_launched);
	OOLog(@"dumpState.stationEntity", @"Max scavengers: %u", max_scavengers);
	OOLog(@"dumpState.stationEntity", @"Scavengers launched: %u", scavengers_launched);
	OOLog(@"dumpState.stationEntity", @"Docked shuttles: %u", docked_shuttles);
	OOLog(@"dumpState.stationEntity", @"Docked traders: %u", docked_traders);
	OOLog(@"dumpState.stationEntity", @"Equivalent tech level: %i", equivalentTechLevel);
	OOLog(@"dumpState.stationEntity", @"Equipment price factor: %g", equipmentPriceFactor);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(no_docking_while_launching);
	if ([self isRotatingStation]) { [flags addObject:@"rotatingStation"]; }
	if (![self dockingCorridorIsEmpty]) { [flags addObject:@"dockingCorridorIsBusy"]; }
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : (NSString *)@"none";
	OOLog(@"dumpState.stationEntity", @"Flags: %@", flagsString);
	
	// approach and hold lists.
	unsigned i;
	ShipEntity		*ship = nil;
	/*	NSArray*	ships = [shipsOnApproach allKeys];
	if([ships count] > 0 ) OOLog(@"dumpState.stationEntity", @"%i Ships on approach (unsorted):", [ships count]);
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
		{
			ship = [UNIVERSE entityForUniversalID:sid];
			OOLog(@"dumpState.stationEntity", @"Nr %i: %@ at distance %g with role: %@", i+1, [ship displayName], 
																			sqrtf(distance2(position, [ship position])),
																					[ship primaryRole]);
		}
		} */

	NSArray* ships = [shipsOnHold allKeys];  // only used with moving stations (= carriers)
	if([ships count] > 0 ) OOLog(@"dumpState.stationEntity", @"%i Ships on hold (unsorted):", [ships count]);
	for (i = 0; i < [ships count]; i++)
	{
		int sid = [[ships objectAtIndex:i] intValue];
		if ([UNIVERSE entityForUniversalID:sid])
		{
			ship = [UNIVERSE entityForUniversalID:sid];
			OOLog(@"dumpState.stationEntity", @"Nr %i: %@ at distance %g with role: %@", i+1, [ship displayName], 
																			sqrtf(distance2(position, [ship position])),
																					[ship primaryRole]);
		}
	}
}

@end


#ifndef NDEBUG

@implementation StationEntity (OOWireframeDockingBox)

- (void)drawEntity:(BOOL)immediate :(BOOL)translucent
{
	[super drawEntity:immediate:translucent];
	
/*	if (gDebugFlags & DEBUG_BOUNDING_BOXES)
	{
	Vector				adjustedPosition;
	Vector				halfDimensions;

		OODebugDrawBasisAtOrigin(50.0f);
		
		OOMatrix matrix;
		matrix = OOMatrixForQuaternionRotation(port_orientation);
		OOGL(glPushMatrix());
		GLMultOOMatrix(matrix);
		
		halfDimensions = vector_multiply_scalar(port_dimensions, 0.5f);
		adjustedPosition = port_position;
		adjustedPosition.z -= halfDimensions.z;
		
		OODebugDrawColoredBoundingBoxBetween(vector_subtract(adjustedPosition, halfDimensions), vector_add(adjustedPosition, halfDimensions), [OOColor redColor]);
		OODebugDrawBasisAtOrigin(30.0f);
		
		OOGL(glPopMatrix());
		} */
}


// Added to test exception wrapping in JS engine. If this is an ancient issue, delete this method. -- Ahruman 2010-06-21
- (void) TEMPExceptionTest
{
	[NSException raise:@"TestException" format:@"This is a test exception which shouldn't crash the game."];
}

@end

#endif
