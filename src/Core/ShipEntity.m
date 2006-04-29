//
//  ShipEntity.m
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

#import "ShipEntity.h"
#import "ShipEntity (AI).h"
#import "entities.h"

#import "vector.h"
#import "Universe.h"

#import "AI.h"
#import "OOCharacter.h"
#import "Geometry.h"
#import "Octree.h"
#import "ScannerExtension.h"
#import "OOColor.h"


@implementation ShipEntity

- (id) init
{
    self = [super init];
	//
	// scripting
	launch_actions = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:4];
	script_actions = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:4];
	death_actions = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:4];
	//
	// escorts
	last_escort_target = NO_TARGET;
	n_escorts = 0;
    escortsAreSetUp = YES;
	//
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	//
	velocity = make_vector( 0.0f, 0.0f, 0.0f);
	quaternion_set_identity(&subentity_rotational_velocity);
	//
	v_forward   = vector_forward_from_quaternion(q_rotation);
	v_up		= vector_up_from_quaternion(q_rotation);
	v_right		= vector_right_from_quaternion(q_rotation);
	//
	reference = v_forward;  // reference vector for (* turrets *)
	owner_id = NO_TARGET;   // owner_id for (* turrets *)
	//
	group_id = NO_TARGET;
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
	//
	max_flight_speed = 200.0;
	max_flight_roll = 3.0;
	max_flight_pitch = 1.5;
	//
	flight_speed = 0.0;
	flight_roll = 0.0;
	flight_pitch = 0.0;
	//
	thrust = 0.0;
	//
	pitching_over = NO;
	//
	energy = 100.0;
	max_energy = 100.0;
	energy_recharge_rate = 2.0;
	//
	forward_weapon_type = WEAPON_NONE;
	aft_weapon_type = WEAPON_NONE;
	weapon_energy = 8.0;
	weapon_recharge_rate = 6.0;
	weapon_offset_x = 10.0;
	shot_time = 0.0;
	//
	launch_time = 0.0;
	//
	cargo_dump_time = 0.0;
	//
	missiles = 3;
	has_ecm = NO;
	has_scoop = NO;
	has_escape_pod = NO;
	has_energy_bomb = NO;
	has_fuel_injection = NO;
	has_cloaking_device = NO;
	has_military_jammer = NO;
	has_military_scanner_filter = NO;
	fuel_accumulator = 1.0;
	//
	bounty = 0;
	//
	primaryTarget = NO_TARGET;
	//
	targetStation = NO_TARGET;
	//
	proximity_alert = NO_TARGET;
	//
	behaviour = BEHAVIOUR_IDLE;
	frustration = 0.0;
	//
	shipAI = [[AI alloc] init]; // alloc retains
	[shipAI setOwner:self];
	[shipAI setState:@"GLOBAL"];
	//
	max_cargo = RAIDER_MAX_CARGO;
	extra_cargo = 15;
	likely_cargo = 0;
	cargo_type = 0;
	cargo = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	cargo_flag = CARGO_FLAG_NONE;
	[self setCommodity:NSNotFound andAmount:0];
	//
	[self setOwner:self];
	//
	reportAImessages = NO;
	//
	sub_entities = nil;
	//
	previousCondition = nil;
	//
	patrol_counter = 0;
	//
	laser_color = [[OOColor redColor] retain];
	//
	scanner_range = 25600;
	//
	shipinfoDictionary = nil;
	//
	being_fined = NO;
	//
	message_time = 0.0;
	//
	next_spark_time = 0.0;
	//
	throw_sparks = NO;
	//
	pitch_tolerance = 0.01 * (80 +(ranrot_rand() & 15));	// 80%..95% accuracy in trackPrimaryTarget
	//
 	thanked_ship_id = NO_TARGET;
	//
	scan_class = CLASS_NOT_SET;
	//
	beaconChar = 0;
	//
	isShip = YES;
	//
	isFrangible = YES;
	subentity_taking_damage = nil;
	//
	dockingInstructions = nil;
	//
	crew = nil;
	//
	[self setTrackCloseContacts:NO];
	//
	isNearPlanetSurface = NO;
	//
	tractor_position = make_vector( 0.0f, 0.0f, 0.0f);
	//
	ship_temperature = 60.0;
	//
	heat_insulation = 1.0;
	//
	return self;
}

- (void) dealloc
{
	[self setTrackCloseContacts:NO];	// deallocs tracking dictionary

	if (shipinfoDictionary)	[shipinfoDictionary release];
	if (shipAI)				[shipAI release];
	if (cargo)				[cargo release];
	if (name)				[name release];
	if (roles)				[roles release];
	if (sub_entities)		[sub_entities release];
	if (laser_color)		[laser_color release];
	//scripting
	if (launch_actions)		[launch_actions release];
	if (script_actions)		[script_actions release];
	if (death_actions)		[death_actions release];

	if (previousCondition)	[previousCondition release];

	if (collisionInfoForEntity)
							[collisionInfoForEntity release];

	if (dockingInstructions)
							[dockingInstructions release];

	if (crew)				[crew release];

	if (lastRadioMessage)	[lastRadioMessage autorelease];

	[super dealloc];
}

NSString* describeBehaviour(int some_behaviour)
{
	switch (some_behaviour)
	{
		case BEHAVIOUR_IDLE:
			return @"BEHAVIOUR_IDLE";
		case BEHAVIOUR_TRACK_TARGET:
			return @"BEHAVIOUR_TRACK_TARGET";
		case BEHAVIOUR_FLY_TO_TARGET:
			return @"BEHAVIOUR_FLY_TO_TARGET";
		case BEHAVIOUR_HANDS_OFF:
			return @"BEHAVIOUR_HANDS_OFF";
		case BEHAVIOUR_TUMBLE:
			return @"BEHAVIOUR_TUMBLE";
		case BEHAVIOUR_STOP_STILL:
			return @"BEHAVIOUR_STOP_STILL";
		case BEHAVIOUR_STATION_KEEPING:
			return @"BEHAVIOUR_STATION_KEEPING";
		case BEHAVIOUR_ATTACK_TARGET:
			return @"BEHAVIOUR_ATTACK_TARGET";
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET:
			return @"BEHAVIOUR_ATTACK_FLY_TO_TARGET";
		case BEHAVIOUR_ATTACK_FLY_FROM_TARGET:
			return @"BEHAVIOUR_ATTACK_FLY_FROM_TARGET";
		case BEHAVIOUR_RUNNING_DEFENSE:
			return @"BEHAVIOUR_RUNNING_DEFENSE";
		case BEHAVIOUR_FLEE_TARGET:
			return @"BEHAVIOUR_FLEE_TARGET";
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX:
			return @"BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX";
		case BEHAVIOUR_ATTACK_MINING_TARGET:
			return @"BEHAVIOUR_ATTACK_MINING_TARGET";
		case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE:
			return @"BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE";
		case BEHAVIOUR_AVOID_COLLISION:
			return @"BEHAVIOUR_AVOID_COLLISION";
		case BEHAVIOUR_TRACK_AS_TURRET:
			return @"BEHAVIOUR_TRACK_AS_TURRET";
		case BEHAVIOUR_FLY_RANGE_FROM_DESTINATION:
			return @"BEHAVIOUR_FLY_RANGE_FROM_DESTINATION";
		case BEHAVIOUR_FLY_TO_DESTINATION:
			return @"BEHAVIOUR_FLY_TO_DESTINATION";
		case BEHAVIOUR_FLY_FROM_DESTINATION:
			return @"BEHAVIOUR_FLY_FROM_DESTINATION";
		case BEHAVIOUR_FACE_DESTINATION:
			return @"BEHAVIOUR_FACE_DESTINATION";
		case BEHAVIOUR_COLLECT_TARGET:
			return @"BEHAVIOUR_COLLECT_TARGET";
		case BEHAVIOUR_INTERCEPT_TARGET:
			return @"BEHAVIOUR_INTERCEPT_TARGET";
		case BEHAVIOUR_MISSILE_FLY_TO_TARGET:
			return @"BEHAVIOUR_MISSILE_FLY_TO_TARGET";
		case BEHAVIOUR_FORMATION_FORM_UP:
			return @"BEHAVIOUR_FORMATION_FORM_UP";
		case BEHAVIOUR_FORMATION_BREAK:
			return @"BEHAVIOUR_FORMATION_BREAK";
		case BEHAVIOUR_ENERGY_BOMB_COUNTDOWN:
			return @"BEHAVIOUR_ENERGY_BOMB_COUNTDOWN";
		case BEHAVIOUR_TRACTORED:
			return @"BEHAVIOUR_TRACTORED";
		case BEHAVIOUR_EXPERIMENTAL:
			return @"BEHAVIOUR_EXPERIMENTAL";
	}
	return @"** BEHAVIOUR UNKNOWN **";
}

NSString* describeStatus(int some_status)
{
	switch(some_status)
	{
		case STATUS_AUTOPILOT_ENGAGED :
			return @"STATUS_AUTOPILOT_ENGAGED";
		case STATUS_DEAD :
			return @"STATUS_DEAD";
		case STATUS_START_GAME :
			return @"STATUS_START_GAME";
		case STATUS_COCKPIT_DISPLAY :
			return @"STATUS_COCKPIT_DISPLAY";
		case STATUS_DOCKING :
			return @"STATUS_DOCKING";
		case STATUS_DOCKED :
			return @"STATUS_DOCKED";
		case STATUS_EFFECT :
			return @"STATUS_EFFECT";
		case STATUS_ENTERING_WITCHSPACE :
			return @"STATUS_ENTERING_WITCHSPACE";
		case STATUS_ESCAPE_SEQUENCE :
			return @"STATUS_ESCAPE_SEQUENCE";
		case STATUS_EXITING_WITCHSPACE :
			return @"STATUS_EXITING_WITCHSPACE";
		case STATUS_EXPERIMENTAL :
			return @"STATUS_EXPERIMENTAL";
		case STATUS_IN_FLIGHT :
			return @"STATUS_IN_FLIGHT";
		case STATUS_IN_HOLD :
			return @"STATUS_IN_HOLD";
		case STATUS_INACTIVE :
			return @"STATUS_INACTIVE";
		case STATUS_LAUNCHING :
			return @"STATUS_LAUNCHING";
		case STATUS_TEST :
			return @"STATUS_TEST";
		case STATUS_WITCHSPACE_COUNTDOWN :
			return @"STATUS_WITCHSPACE_COUNTDOWN";
	}
	return @"** STATUS UNKNOWN **";
}

- (NSString*) description
{
	if (debug & DEBUG_ENTITIES)
	{
		NSMutableString* result = [NSMutableString stringWithFormat:@"\n<ShipEntity %@ %d>", name, universal_id];
		[result appendFormat:@"\n isPlayer: %@", (isPlayer)? @"YES":@"NO"];
		[result appendFormat:@"\n isShip: %@", (isShip)? @"YES":@"NO"];
		[result appendFormat:@"\n isStation: %@", (isStation)? @"YES":@"NO"];
		[result appendFormat:@"\n isSubentity: %@", (isSubentity)? @"YES":@"NO"];
		[result appendFormat:@"\n canCollide: %@", ([self canCollide])? @"YES":@"NO"];
		[result appendFormat:@"\n behaviour: %d %@", behaviour, describeBehaviour(behaviour)];
		[result appendFormat:@"\n status: %d %@", status, describeStatus(status)];
		[result appendFormat:@"\n collisionRegion: %@", collision_region];
		return result;
	}
	else
		return [NSString stringWithFormat:@"<ShipEntity %@ %d>", name, universal_id];
}

static NSMutableDictionary* smallOctreeDict = nil;
- (void) setModel:(NSString*) modelName
{
	[super setModel:modelName];
	// TESTING
	NSMutableDictionary* octreeCache = [(NSMutableDictionary *)[NSMutableDictionary alloc] initWithCapacity:30];
	if ([Entity dataStore])
	{
		octreeCache = (NSMutableDictionary*)[[[Entity dataStore] preloadedDataFiles] objectForKey:@"**octrees**"];
		if (!octreeCache)
		{
			NSLog(@"DEBUG creating octree cache......");
			octreeCache = [(NSMutableDictionary *)[NSMutableDictionary alloc] initWithCapacity:30];
			[[[Entity dataStore] preloadedDataFiles] setObject:octreeCache forKey:@"**octrees**"];
		}
	}

	if (smallOctreeDict == nil)
		smallOctreeDict = [(NSMutableDictionary *)[NSMutableDictionary alloc] initWithCapacity:30];
	if ([smallOctreeDict objectForKey: modelName])
	{
		octree = (Octree*)[smallOctreeDict objectForKey: modelName];
		return;
	}
	//
	if ([octreeCache objectForKey: modelName])
	{
		octree = [[[Octree alloc] initWithDictionary:(NSDictionary*)[octreeCache objectForKey: modelName]] autorelease];
		[smallOctreeDict setObject: octree forKey: modelName];	//retained
	}
	else
	{
//		NSLog(@"DEBUG deriving octree for %@ ... model mass is %.2f", modelName, [self mass]);
		octree = [[self getGeometry] findOctreeToDepth: OCTREE_MAX_DEPTH];	// depth 5 or 6 seems optimum
		[smallOctreeDict setObject: octree forKey: modelName];	//retained
		[octreeCache setObject: [octree dict] forKey: modelName];
	}
}

- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1;
{
	Vector u0 = vector_between(position, v0);	// relative to origin of model / octree
	Vector u1 = vector_between(position, v1);
	Vector w0 = make_vector( dot_product( u0, v_right), dot_product( u0, v_up), dot_product( u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector( dot_product( u1, v_right), dot_product( u1, v_up), dot_product( u1, v_forward));
	return [octree isHitByLine:w0 :w1];
}

- (GLfloat) doesHitLine:(Vector) v0: (Vector) v1 withPosition:(Vector) o andIJK:(Vector) i :(Vector) j :(Vector) k;
{
	Vector u0 = vector_between( o, v0);	// relative to origin of model / octree
	Vector u1 = vector_between( o, v1);
	Vector w0 = make_vector( dot_product( u0, i), dot_product( u0, j), dot_product( u0, k));	// in ijk vectors
	Vector w1 = make_vector( dot_product( u1, j), dot_product( u1, j), dot_product( u1, k));
	return [octree isHitByLine:w0 :w1];
}

- (void) setUniverse:(Universe *)univ
{
	[super setUniverse: univ];

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
		}
	}
	//
	[self resetTracking];	// resets stuff for tracking/exhausts
}

- (Vector)	absoluteTractorPosition
{
	Vector result = position;
	result.x += v_right.x * tractor_position.x + v_up.x * tractor_position.y + v_forward.x * tractor_position.z;
	result.y += v_right.y * tractor_position.x + v_up.y * tractor_position.y + v_forward.y * tractor_position.z;
	result.z += v_right.z * tractor_position.x + v_up.z * tractor_position.y + v_forward.z * tractor_position.z;
	return result;
}

- (BOOL)	isBeacon
{
	return (beaconChar != 0);
}

- (char)	beaconChar
{
	return beaconChar;
}

- (void)	setBeaconChar:(char) bchar
{
	beaconChar = bchar;
}

- (int)		nextBeaconID
{
	return nextBeaconID;
}

- (void)	setNextBeacon:(ShipEntity*) beaconShip
{
	if (beaconShip == nil)
		nextBeaconID = NO_TARGET;
	else
		nextBeaconID = [beaconShip universal_id];
}

- (void) setUpEscorts
{
	NSString *escortRole = @"escort";
	NSString *escortShipKey = nil;

	if ([roles isEqual:@"trader"])
		escortRole = @"escort";

	if ([roles isEqual:@"police"])
		escortRole = @"wingman";

	if ([shipinfoDictionary objectForKey:@"escort-role"])
	{
		escortRole = (NSString*)[shipinfoDictionary objectForKey:@"escort-role"];
		if (![[universe getShipWithRole:escortRole] autorelease])
			escortRole = @"escort";
	}

	if ([shipinfoDictionary objectForKey:@"escort-ship"])
	{
		escortShipKey = (NSString*)[shipinfoDictionary objectForKey:@"escort-ship"];
		if (![[universe getShip:escortShipKey] autorelease])
			escortShipKey = nil;
	}

//	NSLog(@"DEBUG Setting up escorts for %@", self);

	while (n_escorts > 0)
	{
		Vector ex_pos = [self getCoordinatesForEscortPosition:n_escorts - 1];

		ShipEntity *escorter;

		if (escortShipKey)
			escorter = [universe getShip:escortShipKey];	// retained
		else
			escorter = [universe getShipWithRole:escortRole];	// retained

		if (!escorter)
			break;

		// spread them around a little randomly
		double dd = escorter->collision_radius;
		ex_pos.x += dd * 6.0 * (randf() - 0.5);
		ex_pos.y += dd * 6.0 * (randf() - 0.5);
		ex_pos.z += dd * 6.0 * (randf() - 0.5);


		[escorter setScanClass: CLASS_NEUTRAL];
		[escorter setPosition:ex_pos];

		[escorter setStatus:STATUS_IN_FLIGHT];

		[escorter setRoles:escortRole];

		[escorter setScanClass:scan_class];		// you are the same as I

		//[escorter setReportAImessages: (i == 0) ? YES:NO ]; // debug

		[universe addEntity:escorter];
		[[escorter getAI] setStateMachine:@"escortAI.plist"];	// must happen after adding to the universe!

		[escorter setGroup_id:universal_id];
		[self setGroup_id:universal_id];		// make self part of same group

		[escorter setOwner: self];	// make self group leader

		[[escorter getAI] setState:@"FLYING_ESCORT"];	// begin immediately

		if (bounty)
		{
			int extra = 1 | (ranrot_rand() & 15);
			bounty += extra;	// obviously we're dodgier than we thought!
			[escorter setBounty: extra];
//			NSLog(@"DEBUG setting bounty for %@ escorting %@ to %d", escorter, self, extra);

//			[escorter setReportAImessages: YES ]; // debug
		}
		else
		{
			[escorter setBounty:0];
		}

//		NSLog(@"DEBUG set up escort ship %@ for %@", escorter, self);

		[escorter release];
		n_escorts--;
	}
}


- (void) reinit
{
	//
	isSubentity = NO;
	//
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	//
	v_forward   = vector_forward_from_quaternion(q_rotation);
	v_up		= vector_up_from_quaternion(q_rotation);
	v_right		= vector_right_from_quaternion(q_rotation);
    //
	reference = v_forward;  // reference vector for (* turrets *)
	owner_id = NO_TARGET;   // owner_id for (* turrets *)
	//
	group_id = NO_TARGET;
    //
	if (launch_actions)
		[launch_actions removeAllObjects];
	if (script_actions)
		[script_actions removeAllObjects];
	if (death_actions)
		[death_actions removeAllObjects];
	//
	last_escort_target = NO_TARGET;
 	n_escorts = 0;
	escortsAreSetUp = YES;
	//
	position = make_vector( 0.0f, 0.0f, 0.0f);
	velocity = make_vector( 0.0f, 0.0f, 0.0f);
	quaternion_set_identity(&subentity_rotational_velocity);
	//
	zero_distance = SCANNER_MAX_RANGE2 * 2.0;   // beyond scanner range to avoid the momentary blip
	//
	max_flight_speed = 0.0;
	max_flight_roll = 0.0;
	max_flight_pitch = 0.0;
	//
	flight_speed = 0.0;
	flight_roll = 0.0;
	flight_pitch = 0.0;
	//
	thrust = 0.0;
	//
	pitching_over = NO;
	//
	energy = 0.0;
	max_energy = 0.0;
	energy_recharge_rate = 0.0;
	//
	forward_weapon_type = WEAPON_NONE;
	aft_weapon_type = WEAPON_NONE;
	weapon_energy = 0.0;
	weapon_recharge_rate = 6.0;
	weapon_offset_x = 0.0;
	shot_time = 0.0;
	//
	launch_time = 0.0;
	//
	cargo_dump_time = 0.0;
	//
	missiles = 0;
	has_ecm = NO;
	has_scoop = NO;
	has_escape_pod = NO;
	has_energy_bomb = NO;
	has_fuel_injection = NO;
	has_cloaking_device = NO;
	has_military_jammer = NO;
	has_military_scanner_filter = NO;
	fuel_accumulator = 1.0;
	//
	bounty = 0;
	//
	primaryTarget = NO_TARGET;
	//
	targetStation = NO_TARGET;
	//
	proximity_alert = NO_TARGET;
	//
	behaviour = BEHAVIOUR_IDLE;
	frustration = 0.0;
	//
	if (shipAI)
		[shipAI autorelease];
	shipAI = [[AI alloc] init]; // alloc retains
	[shipAI setOwner:self];
	[shipAI setState:@"GLOBAL"];
	//
	max_cargo = 0;
	extra_cargo = 15;
	likely_cargo = 0;
	cargo_type = 0;
	cargo_flag = CARGO_FLAG_NONE;
	if (!cargo)
		cargo = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	[cargo removeAllObjects];
	[self setCommodity:NSNotFound andAmount:0];
	//
	owner = NO_TARGET;
	//
	reportAImessages = NO;
	//
	if (previousCondition) [previousCondition autorelease];
	previousCondition = nil;
	//
	if (sub_entities) [sub_entities autorelease];
	sub_entities = nil;
	//
	scanner_range = 25600.0;
	//
	if (shipinfoDictionary)
		[shipinfoDictionary autorelease];
	shipinfoDictionary = nil;
	//
	being_fined = NO;
	//
	message_time = 0.0;
	//
	next_spark_time = 0.0;
	//
	throw_sparks = NO;
	//
	thanked_ship_id = NO_TARGET;
	//
	scan_class = CLASS_NOT_SET;
	//
	[collisionInfoForEntity removeAllObjects];
	//
	beaconChar = 0;
	//
	isShip = YES;
	//
	isFrangible = YES;
	subentity_taking_damage = nil;
	//
	if (dockingInstructions)
		[dockingInstructions autorelease];
	dockingInstructions = nil;
	//
	if (crew)
		[crew autorelease];
	crew = nil;
	//
	[self setTrackCloseContacts:NO];
	//
	isNearPlanetSurface = NO;
	//
	if (lastRadioMessage)
		[lastRadioMessage autorelease];
	lastRadioMessage = nil;
	//
	tractor_position = make_vector( 0.0f, 0.0f, 0.0f);
	//
	ship_temperature = 60.0;
	//
	heat_insulation = 1.0;
	//
	[self setCollisionRegion:nil];
}

- (id) initWithDictionary:(NSDictionary *) dict
{
	self = [super init];
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	//
	v_forward   = vector_forward_from_quaternion(q_rotation);
	v_up		= vector_up_from_quaternion(q_rotation);
	v_right		= vector_right_from_quaternion(q_rotation);
    //
	position = make_vector( 0.0f, 0.0f, 0.0f);
	velocity = make_vector( 0.0f, 0.0f, 0.0f);
	//
	flight_speed = 0.0;
	flight_roll = 0.0;
	flight_pitch = 0.0;
	//
	pitching_over = NO;
	//
	primaryTarget = NO_TARGET;
	//
	targetStation = NO_TARGET;
	//
	proximity_alert = NO_TARGET;
	//
	behaviour = BEHAVIOUR_IDLE;
	frustration = 0.0;
	//
	patrol_counter = 0;
	//
	scan_class = CLASS_NOT_SET;
	//
	crew = nil;
	//
	[self setUpShipFromDictionary:dict];
	//
	reportAImessages = NO;
	//
	being_fined = NO;
	//
	isShip = YES;
	//
	isFrangible = YES;
	subentity_taking_damage = nil;
	//
	isNearPlanetSurface = NO;
	//
	return self;
}


- (void) setUpShipFromDictionary:(NSDictionary *) dict
{
    NSString*   cargo_type_string;
    NSString*   weapon_type_string;
	NSMutableDictionary* shipdict = [NSMutableDictionary dictionaryWithDictionary:dict];

	// reset all settings
	[self reinit];

	if (collisionInfoForEntity)
		[collisionInfoForEntity removeAllObjects];
	else
		collisionInfoForEntity = [(NSMutableDictionary *)[NSMutableDictionary alloc] initWithCapacity:12];

	// check if this is based upon a different ship
	while ([shipdict objectForKey:@"like_ship"])
	{
		if (universe)
		{
			NSString*		other_shipdesc = (NSString *)[shipdict objectForKey:@"like_ship"];
			NSDictionary*	other_shipdict = nil;
			if (other_shipdesc)
			{
				NS_DURING
					other_shipdict = [universe getDictionaryForShip:other_shipdesc];	// handle OOLITE_EXCEPTION_SHIP_NOT_FOUND
				NS_HANDLER
					if ([[localException name] isEqual: OOLITE_EXCEPTION_SHIP_NOT_FOUND])
					{
						NSLog(@"***** Oolite Exception : '%@' in [ShipEntity setUpShipFromDictionary:] while basing a ship upon '%@' *****", [localException reason], other_shipdesc);
						other_shipdict = nil;
					}
					else
						[localException raise];
				NS_ENDHANDLER
			}
			if (other_shipdict)
			{
				[shipdict removeObjectForKey:@"like_ship"];	// so it may inherit a new one from the like_ship

//				NSLog(@"DEBUG setting up ship alike unto : %@", other_shipdesc);

				NSMutableDictionary* this_shipdict = [NSMutableDictionary dictionaryWithDictionary:other_shipdict]; // basics from that one
				[this_shipdict addEntriesFromDictionary:shipdict];	// overrides from this one
				shipdict = [NSMutableDictionary dictionaryWithDictionary:this_shipdict];	// synthesis'

//				NSLog(@"DEBUG resulting shipdict is :\n%@", shipdict);
			}
		}
	}

	shipinfoDictionary = [[NSDictionary alloc] initWithDictionary:shipdict];	// retained

	//
	// set things from dictionary from here out
	//
	if ([shipdict objectForKey:@"max_flight_speed"])
		max_flight_speed = [(NSNumber *)[shipdict objectForKey:@"max_flight_speed"] doubleValue];
	if ([shipdict objectForKey:@"max_flight_roll"])
		max_flight_roll = [(NSNumber *)[shipdict objectForKey:@"max_flight_roll"] doubleValue];
	if ([shipdict objectForKey:@"max_flight_pitch"])
		max_flight_pitch = [(NSNumber *)[shipdict objectForKey:@"max_flight_pitch"] doubleValue];
	//
	if ([shipdict objectForKey:@"thrust"])
		thrust = [(NSNumber *)[shipdict objectForKey:@"thrust"] doubleValue];
	//
	if ([shipdict objectForKey:@"accuracy"])
	{
		int accuracy = [(NSNumber *)[shipdict objectForKey:@"accuracy"] intValue];
		if ((accuracy >= -5)&&(accuracy <= 10))
			pitch_tolerance = 0.01 * (85 + accuracy);
	}
	//
	if ([shipdict objectForKey:@"max_energy"])
		max_energy = [(NSNumber *)[shipdict objectForKey:@"max_energy"] doubleValue];
	if ([shipdict objectForKey:@"energy_recharge_rate"])
		energy_recharge_rate = [(NSNumber *)[shipdict objectForKey:@"energy_recharge_rate"] doubleValue];
	energy = max_energy;
	//
	if ([shipdict objectForKey:@"weapon_offset_x"])
		weapon_offset_x = [(NSNumber *)[shipdict objectForKey:@"weapon_offset_x"] doubleValue];
	//
	if ([shipdict objectForKey:@"aft_weapon_type"])
	{
		weapon_type_string = (NSString *)[shipdict objectForKey:@"aft_weapon_type"];
		if ([weapon_type_string isEqual:@"WEAPON_PULSE_LASER"])
			aft_weapon_type = WEAPON_PULSE_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_BEAM_LASER"])
			aft_weapon_type = WEAPON_BEAM_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_MINING_LASER"])
			aft_weapon_type = WEAPON_MINING_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_MILITARY_LASER"])
			aft_weapon_type = WEAPON_MILITARY_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_THARGOID_LASER"])
			aft_weapon_type = WEAPON_THARGOID_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_PLASMA_CANNON"])
			aft_weapon_type = WEAPON_PLASMA_CANNON;
		if ([weapon_type_string isEqual:@"WEAPON_NONE"])
			aft_weapon_type = WEAPON_NONE;
	}
	//
	if ([shipdict objectForKey:@"forward_weapon_type"])
	{
		weapon_type_string = (NSString *)[shipdict objectForKey:@"forward_weapon_type"];
		if ([weapon_type_string isEqual:@"WEAPON_PULSE_LASER"])
			forward_weapon_type = WEAPON_PULSE_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_BEAM_LASER"])
			forward_weapon_type = WEAPON_BEAM_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_MINING_LASER"])
			forward_weapon_type = WEAPON_MINING_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_MILITARY_LASER"])
			forward_weapon_type = WEAPON_MILITARY_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_THARGOID_LASER"])
			forward_weapon_type = WEAPON_THARGOID_LASER;
		if ([weapon_type_string isEqual:@"WEAPON_PLASMA_CANNON"])
			forward_weapon_type = WEAPON_PLASMA_CANNON;
		if ([weapon_type_string isEqual:@"WEAPON_NONE"])
			forward_weapon_type = WEAPON_NONE;
		[self set_weapon_data_from_type:forward_weapon_type];
	}
	//
	if ([shipdict objectForKey:@"weapon_energy"])
		weapon_energy = [(NSNumber *)[shipdict objectForKey:@"weapon_energy"] doubleValue];
	//
	if ([shipdict objectForKey:@"scanner_range"])
		scanner_range = [(NSNumber *)[shipdict objectForKey:@"scanner_range"] doubleValue];
	//
	if ([shipdict objectForKey:@"missiles"])
		missiles = [(NSNumber *)[shipdict objectForKey:@"missiles"] intValue];

	// upgrades:
	//		did use [NSNumber boolValue], but now have a random chance instead
	//
	if ([shipdict objectForKey:@"has_ecm"])
		has_ecm = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_ecm"] floatValue]);
	if ([shipdict objectForKey:@"has_scoop"])
		has_scoop = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_scoop"] floatValue]);
	if ([shipdict objectForKey:@"has_escape_pod"])
		has_escape_pod = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_escape_pod"] floatValue]);
	if ([shipdict objectForKey:@"has_energy_bomb"])
		has_energy_bomb = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_energy_bomb"] floatValue]);
	if ([shipdict objectForKey:@"has_fuel_injection"])
		has_fuel_injection = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_fuel_injection"] floatValue]);
	//
	if ([shipdict objectForKey:@"has_shield_booster"])
		max_energy += (randf() < [(NSNumber *)[shipdict objectForKey:@"has_shield_booster"] floatValue])? 256:0;
	if ([shipdict objectForKey:@"has_shield_enhancer"])
	{
		max_energy += (randf() < [(NSNumber *)[shipdict objectForKey:@"has_shield_enhancer"] floatValue])? 256:0;
		energy_recharge_rate *= 1.5;
	}
	//
	if ([shipdict objectForKey:@"has_cloaking_device"])
		has_cloaking_device = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_cloaking_device"] floatValue]);
	//
	cloaking_device_active = NO;
	//
	if ([shipdict objectForKey:@"has_military_jammer"])
		has_military_jammer = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_military_jammer"] floatValue]);
	//
	military_jammer_active = NO;
	//
	if ([shipdict objectForKey:@"has_military_scanner_filter"])
		has_military_scanner_filter = (randf() < [(NSNumber *)[shipdict objectForKey:@"has_military_scanner_filter"] floatValue]);
	//
	// /upgrades

	if ([shipdict objectForKey:@"fuel"])
		fuel = [(NSNumber *)[shipdict objectForKey:@"fuel"] intValue];

	//
	if ([shipdict objectForKey:@"bounty"])
		bounty = [(NSNumber *)[shipdict objectForKey:@"bounty"] intValue];
	//
	if ([shipdict objectForKey:@"ai_type"])
	{
		if (shipAI)
			[shipAI autorelease];
		shipAI = [[AI alloc] init]; // alloc retains
		[shipAI setOwner:self];
		[shipAI setStateMachine:(NSString *)[shipdict objectForKey:@"ai_type"]];
		[shipAI setState:@"GLOBAL"];
	}
	//
	if ([shipdict objectForKey:@"max_cargo"])
		max_cargo = [(NSNumber *)[shipdict objectForKey:@"max_cargo"] intValue];
	if ([shipdict objectForKey:@"likely_cargo"])
		likely_cargo = [(NSNumber *)[shipdict objectForKey:@"likely_cargo"] intValue];
	if ([dict objectForKey:@"extra_cargo"])
		extra_cargo = [(NSNumber*)[dict objectForKey:@"extra_cargo"] intValue];
	else
		extra_cargo = 15;
	//
	if ([shipdict objectForKey:@"cargo_carried"])
	{
		cargo_flag = CARGO_FLAG_FULL_UNIFORM;

		[self setCommodity:NSNotFound andAmount:0];
		int c_commodity = NSNotFound;
		int c_amount = 1;
		NSScanner*	scanner = [NSScanner scannerWithString: (NSString*)[shipdict objectForKey:@"cargo_carried"]];
		if ([scanner scanInt: &c_amount])
		{
			[scanner ooliteScanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:(NSString * *)nil];	// skip whitespace
			c_commodity = [universe commodityForName: [[scanner string] substringFromIndex:[scanner scanLocation]]];
		}
		else
		{
			c_amount = 1;
			c_commodity = [universe commodityForName: (NSString*)[shipdict objectForKey:@"cargo_carried"]];
		}

		if (c_commodity != NSNotFound)
			[self setCommodity:c_commodity andAmount:c_amount];
	}
	//
	if ([shipdict objectForKey:@"cargo_type"])
	{
		cargo_type_string = (NSString *)[shipdict objectForKey:@"cargo_type"];
		if ([cargo_type_string isEqual:@"CARGO_THARGOID"])
			cargo_type = CARGO_THARGOID;
		if ([cargo_type_string isEqual:@"CARGO_ALLOY"])
			cargo_type = CARGO_ALLOY;
		if ([cargo_type_string isEqual:@"CARGO_MINERALS"])
			cargo_type = CARGO_MINERALS;
		if ([cargo_type_string isEqual:@"CARGO_SLAVES"])
			cargo_type = CARGO_SLAVES;
		if ([cargo_type_string isEqual:@"CARGO_NOT_CARGO"])
			cargo_type = CARGO_NOT_CARGO;
		if ([cargo_type_string isEqual:@"CARGO_RANDOM"]||[cargo_type_string isEqual:@"CARGO_CARRIED"])
			cargo_type = CARGO_RANDOM;
		if ([cargo_type_string isEqual:@"CARGO_SCRIPTED_ITEM"])
			cargo_type = CARGO_SCRIPTED_ITEM;
		if (cargo)
			[cargo autorelease];
		cargo = [(NSMutableArray *)[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	}
	//
	// A HACK!! - must do this before the model is set
	if ([shipdict objectForKey:@"smooth"])
		is_smooth_shaded = YES;
	else
		is_smooth_shaded = NO;
	//
	// must do this next one before checking subentities
	if ([shipdict objectForKey:@"model"])
		[self setModel:(NSString *)[shipdict objectForKey:@"model"]];
	//
	if ([shipdict objectForKey:KEY_NAME])
	{
		if (name)
			[name release];
		name = [[NSString stringWithString:(NSString *)[shipdict objectForKey:KEY_NAME]] retain];
	}
	//
	if ([shipdict objectForKey:@"roles"])
	{
		if (roles)
			[roles release];
		roles = [[NSString stringWithString:(NSString *)[shipdict objectForKey:@"roles"]] retain];
	}
	//
	[self setOwner:self];
	//
	if ([shipdict objectForKey:@"exhaust"])
	{
		int i;
		NSArray *plumes = (NSArray *)[shipdict objectForKey:@"exhaust"];
		for (i = 0; i < [plumes count]; i++)
		{
			ParticleEntity *exhaust = [[ParticleEntity alloc] initExhaustFromShip:self details:(NSString *)[plumes objectAtIndex:i]];
			[self addExhaust:exhaust];
			[exhaust release];
		}
	}
	//
	if ([shipdict objectForKey:@"subentities"])
	{
		if (universe)
		{
			//NSLog(@"DEBUG adding subentity...");
			int i;
			NSArray *subs = (NSArray *)[shipdict objectForKey:@"subentities"];
			for (i = 0; i < [subs count]; i++)
			{
	//			NSArray* details = [(NSString *)[subs objectAtIndex:i] componentsSeparatedByString:@" "];
				NSArray* details = [Entity scanTokensFromString:(NSString *)[subs objectAtIndex:i]];

				if ([details count] == 8)
				{
					//NSLog(@"DEBUG adding subentity...");
					Vector sub_pos, ref;
					Quaternion sub_q;
					Entity* subent;
					NSString* subdesc = (NSString *)[details objectAtIndex:0];
					sub_pos.x = [(NSString *)[details objectAtIndex:1] floatValue];
					sub_pos.y = [(NSString *)[details objectAtIndex:2] floatValue];
					sub_pos.z = [(NSString *)[details objectAtIndex:3] floatValue];
					sub_q.w = [(NSString *)[details objectAtIndex:4] floatValue];
					sub_q.x = [(NSString *)[details objectAtIndex:5] floatValue];
					sub_q.y = [(NSString *)[details objectAtIndex:6] floatValue];
					sub_q.z = [(NSString *)[details objectAtIndex:7] floatValue];

	//				NSLog(@"DEBUG adding subentity... %@ %f %f %f - %f %f %f %f", subdesc, sub_pos.x, sub_pos.y, sub_pos.z, sub_q.w, sub_q.x, sub_q.y, sub_q.z);

					if ([subdesc isEqual:@"*FLASHER*"])
					{
						subent = [[ParticleEntity alloc] init];	// retained
						[(ParticleEntity*)subent setColor:[OOColor colorWithCalibratedHue: sub_q.w/360.0 saturation:1.0 brightness:1.0 alpha:1.0]];
						[(ParticleEntity*)subent setDuration: sub_q.x];
						[(ParticleEntity*)subent setEnergy: 2.0 * sub_q.y];
						[(ParticleEntity*)subent setSize:NSMakeSize( sub_q.z, sub_q.z)];
						[(ParticleEntity*)subent setParticleType:PARTICLE_FLASHER];
						[(ParticleEntity*)subent setStatus:STATUS_EFFECT];
						[(ParticleEntity*)subent setPosition:sub_pos];
						[subent setUniverse:universe];
					}
					else
					{
						quaternion_normalise(&sub_q);

	//					NSLog(@"DEBUG universe = %@", universe);

						subent = [universe getShip:subdesc];	// retained

						if ((self->isStation)&&([subdesc rangeOfString:@"dock"].location != NSNotFound))
							[(StationEntity*)self setDockingPortModel:(ShipEntity*)subent :sub_pos :sub_q];

						if (subent)
						{
	//					NSLog(@"DEBUG adding subentity %@ %@ to new %@ at %.3f,%.3f,%.3f", subent, [(ShipEntity*)subent name], name, sub_pos.x, sub_pos.y, sub_pos.z );
							[(ShipEntity*)subent setStatus:STATUS_INACTIVE];
							//
							ref = vector_forward_from_quaternion(sub_q);	// VECTOR FORWARD
							//
							[(ShipEntity*)subent setReference: ref];
							[(ShipEntity*)subent setPosition: sub_pos];
							[(ShipEntity*)subent setQRotation: sub_q];
							//
							[self addSolidSubentityToCollisionRadius:(ShipEntity*)subent];
							//
							subent->isSubentity = YES;
						}
						//
					}
					//NSLog(@"DEBUG reference (%.1f,%.1f,%.1f)", ref.x, ref.y, ref.z);
					if (sub_entities == nil)
						sub_entities = [[NSArray arrayWithObject:subent] retain];
					else
					{
						NSMutableArray *temp = [NSMutableArray arrayWithArray:sub_entities];
	//					if (subent != nil)
							[temp addObject:subent];
						[sub_entities release];
						sub_entities = [[NSArray arrayWithArray:temp] retain];
					}

					[subent setOwner: self];

	//				NSLog(@"DEBUG added subentity %@ to position %.3f,%.3f,%.3f", subent, subent->position.x, subent->position.y, subent->position.z );

					[subent release];
				}
			}
	//		NSLog(@"DEBUG %@ subentities : %@", name, sub_entities);
		}
	}
	//
	if ([shipdict objectForKey:@"frangible"])	// if an object has frangible == YES then it can have its subentities shot away!
		isFrangible = [(NSNumber *)[shipdict objectForKey:@"frangible"] boolValue];
	subentity_taking_damage = nil;
	//
	if ([shipdict objectForKey:@"laser_color"])
	{
		NSString *laser_color_string = (NSString *)[shipdict objectForKey:@"laser_color"];
		SEL color_selector = NSSelectorFromString(laser_color_string);
		if ([OOColor respondsToSelector:color_selector])
		{
			id  color_thing = [OOColor performSelector:color_selector];
			if ([color_thing isKindOfClass:[OOColor class]])
				[self setLaserColor:(OOColor *)color_thing];
		}
	}
	else
		[self setLaserColor:[OOColor redColor]];
	//
	// scan class
	if ([shipdict objectForKey:@"scanClass"])
	{
		NSString *s_class= (NSString *)[shipdict objectForKey:@"scanClass"];

		//NSLog(@"----- initialising ship with scan class '%@'",s_class);

		scan_class = CLASS_NEUTRAL;
		if ([s_class isEqual:@"CLASS_STATION"])
			scan_class = CLASS_STATION;
		if ([s_class isEqual:@"CLASS_THARGOID"])
			scan_class = CLASS_THARGOID;
		if ([s_class isEqual:@"CLASS_TARGET"])
			scan_class = CLASS_TARGET;
		if ([s_class isEqual:@"CLASS_CARGO"])
			scan_class = CLASS_CARGO;
		if ([s_class isEqual:@"CLASS_POLICE"])
			scan_class = CLASS_POLICE;
		if ([s_class isEqual:@"CLASS_MILITARY"])
			scan_class = CLASS_MILITARY;
		if ([s_class isEqual:@"CLASS_BUOY"])
			scan_class = CLASS_BUOY;
		if ([s_class isEqual:@"CLASS_NO_DRAW"])
			scan_class = CLASS_NO_DRAW;
		if ([s_class isEqual:@"CLASS_MISSILE"])
			scan_class = CLASS_MISSILE;
		if ([s_class isEqual:@"CLASS_NEUTRAL"])
			scan_class = CLASS_NEUTRAL;
		if ([s_class isEqual:@"CLASS_ROCK"])
			scan_class = CLASS_ROCK;
	}
	else
		scan_class = CLASS_NOT_SET;
	//
	// scripting
	if ([shipdict objectForKey:KEY_LAUNCH_ACTIONS])
		[launch_actions addObjectsFromArray:(NSArray *)[shipdict objectForKey:KEY_LAUNCH_ACTIONS]];
	if ([shipdict objectForKey:KEY_SCRIPT_ACTIONS])
		[script_actions addObjectsFromArray:(NSArray *)[shipdict objectForKey:KEY_SCRIPT_ACTIONS]];
	if ([shipdict objectForKey:KEY_DEATH_ACTIONS])
		[death_actions addObjectsFromArray:(NSArray *)[shipdict objectForKey:KEY_DEATH_ACTIONS]];
	if ([shipdict objectForKey:KEY_SETUP_ACTIONS])
	{
		if (universe)
		{
			PlayerEntity* player = (PlayerEntity*)[universe entityZero];
			[player setScript_target:self];
			NSArray * setup_actions = (NSArray *)[shipdict objectForKey:KEY_SETUP_ACTIONS];

			[player scriptActions: setup_actions forTarget: self];

		}
	}

	//  escorts
	//
	if ([shipdict objectForKey:@"escorts"])
	{
		n_escorts = [(NSNumber *)[shipdict objectForKey:@"escorts"] intValue];
		//NSLog(@"DEBUG adding %d escorts for new %@", n_escorts, name);
		escortsAreSetUp = (n_escorts == 0);
	}

	// beacons
	//
	if ([shipdict objectForKey:@"beacon"])
	{
		NSString* beaconCode = (NSString*)[shipdict objectForKey:@"beacon"];
		const char* bcode = [beaconCode lossyCString];
		beaconChar = bcode[0];
//		NSLog(@"DEBUG new %@ is a beacon with code: %s", name, bcode);
	}
	else
	{
		beaconChar = 0;
	}

	// rotating subentities
	//
	if ([shipdict objectForKey:@"rotational_velocity"])
	{
		subentity_rotational_velocity = [Entity quaternionFromString: (NSString*)[shipdict objectForKey:@"rotational_velocity"]];
	}
	else
	{
		quaternion_set_identity(&subentity_rotational_velocity);
	}

	// contact tracking entities
	//
	if ([shipdict objectForKey:@"track_contacts"])
	{
		[self setTrackCloseContacts:[[shipdict objectForKey:@"track_contacts"] boolValue]];
		// DEBUG....
		[self setReportAImessages:YES];
	}
	else
	{
		[self setTrackCloseContacts:NO];
	}

	// set weapon offsets
	[self setDefaultWeaponOffsets];
	//
	if ([shipdict objectForKey:@"weapon_position_forward"])
		forwardWeaponOffset = [Entity vectorFromString: (NSString *)[shipdict objectForKey:@"weapon_position_forward"]];
	if ([shipdict objectForKey:@"weapon_position_aft"])
		aftWeaponOffset = [Entity vectorFromString: (NSString *)[shipdict objectForKey:@"weapon_position_aft"]];
	if ([shipdict objectForKey:@"weapon_position_port"])
		portWeaponOffset = [Entity vectorFromString: (NSString *)[shipdict objectForKey:@"weapon_position_port"]];
	if ([shipdict objectForKey:@"weapon_position_starboard"])
		starboardWeaponOffset = [Entity vectorFromString: (NSString *)[shipdict objectForKey:@"weapon_position_starboard"]];

	// fuel scoop destination position (where cargo gets sucked into)
	tractor_position = make_vector( 0.0f, 0.0f, 0.0f);
	if ([shipdict objectForKey:@"scoop_position"])
		tractor_position = [Entity vectorFromString: (NSString *)[shipdict objectForKey:@"scoop_position"]];

	// ship skin insulation factor (1.0 is normal)
	heat_insulation = 1.0;
	if ([shipdict objectForKey:@"heat_insulation"])
		heat_insulation = [[shipdict objectForKey:@"heat_insulation"] doubleValue];
}


- (void) setDefaultWeaponOffsets
{
	forwardWeaponOffset = make_vector( 0.0f, 0.0f, 0.0f);
	aftWeaponOffset = make_vector( 0.0f, 0.0f, 0.0f);
	portWeaponOffset = make_vector( 0.0f, 0.0f, 0.0f);
	starboardWeaponOffset = make_vector( 0.0f, 0.0f, 0.0f);
}

- (int) scanClass
{
	if (cloaking_device_active)
		return CLASS_NO_DRAW;
	else
		return scan_class;
}

//////////////////////////////////////////////

BOOL ship_canCollide (ShipEntity* ship)
{
	int		s_status =		ship->status;
	int		s_scan_class =	ship->scan_class;
	if ((s_status == STATUS_COCKPIT_DISPLAY)||(s_status == STATUS_DEAD)||(s_status == STATUS_BEING_SCOOPED))
		return NO;
	if ((s_scan_class == CLASS_MISSILE) && (ship->shot_time < 0.25)) // not yet fused
		return NO;
	return YES;
}

- (BOOL) canCollide
{
	return ship_canCollide(self);
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
//	if (isPlayer||(other->isPlayer))
//		NSLog(@"DEBUG %@ Checking close collision with %@", self, other);

	if (!other)
		return NO;
	if ([collidingEntities containsObject:other])	// we know about this already!
		return NO;

	if ((other->isShip)&&[self canScoop: (ShipEntity*)other])	// quick test - could this improve scooping for small ships? I think so!
		return YES;

	if (trackCloseContacts)
	{
		// in update we check if close contacts have gone out of touch range (origin within our collision_radius)
		// here we check if something has come within that range
		NSString* other_key = [NSString stringWithFormat:@"%d", other->universal_id];
		if ((![closeContactsInfo objectForKey: other_key]) && (distance2( position, other->position) < collision_radius * collision_radius))
		{
			// calculate position with respect to our own position and orientation
			Vector	dpos = vector_between( position, other->position);
			Vector  rpos = make_vector( dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
			[closeContactsInfo setObject:[NSString stringWithFormat:@"%f %f %f", rpos.x, rpos.y, rpos.z] forKey: other_key];
			// send AI a message about the touch
			int	temp_id = primaryTarget;
			primaryTarget = other->universal_id;
			[shipAI reactToMessage:@"CLOSE CONTACT"];
			primaryTarget = temp_id;
		}
	}

	if (zero_distance > CLOSE_COLLISION_CHECK_MAX_RANGE2)	// don't work too hard on entities that are far from the player
		return YES;

	if (other->isShip)
	{
		// check bounding spheres versus bounding spheres
		ShipEntity* other_ship = (ShipEntity*)other;
		
		// octree check
//		debug_octree = ((isPlayer)||(other->isPlayer));
		Octree* other_octree = other_ship->octree;
		Triangle own_ijk;
		own_ijk.v[0] = v_right;
		own_ijk.v[1] = v_up;
		own_ijk.v[2] = v_forward;
		Vector other_position = resolveVectorInIJK( vector_between(position, other_ship->position), own_ijk);
		Triangle other_ijk;
		other_ijk.v[0] = resolveVectorInIJK( other_ship->v_right, own_ijk);
		other_ijk.v[1] = resolveVectorInIJK( other_ship->v_up, own_ijk);
		other_ijk.v[2] = resolveVectorInIJK( other_ship->v_forward, own_ijk);
		
		if ([octree isHitByOctree: other_octree withOrigin: other_position andIJK: other_ijk])
			return YES;
//		else
//			return NO;
//		debug_octree = NO;

		// check our solid subentities against the other ship's
		//
		int i,j;
		NSArray* other_subs = other_ship->sub_entities;
		int n_subs1 = [sub_entities count];
		int n_subs2 = [other_subs count];
		ShipEntity* entity1[ 1 + n_subs1 ];
		ShipEntity* entity2[ 1 + n_subs2 ];
		Vector sphere_positions1[ 1 + n_subs1 ];
		Vector sphere_positions2[ 1 + n_subs2 ];
		double sphere_rad1[ 1 + n_subs1 ];
		double sphere_rad2[ 1 + n_subs2 ];
		Triangle sphere_ijk1[ 1 + n_subs1 ];
		Triangle sphere_ijk2[ 1 + n_subs2 ];
		int n_spheres1 = 1;
		int n_spheres2 = 1;
		sphere_positions1[0] = position;
		sphere_rad1[0] = actual_radius;
		sphere_ijk1[0] = own_ijk;
		entity1[0] = self;
		sphere_positions2[0] = other->position;
		sphere_rad2[0] = other->actual_radius;
		sphere_ijk2[0] = make_triangle( other_ship->v_right, other_ship->v_up, other_ship->v_forward);
		entity2[0] = other_ship;
		for (i = 0; i < n_subs1; i++)
		{
			Entity* se = [sub_entities objectAtIndex:i];
			if ((se)&&[se canCollide]&&(se->isShip))
			{
				entity1[n_spheres1] = (ShipEntity*)se;
				sphere_positions1[n_spheres1] = [(ShipEntity*)se absolutePositionForSubentity];
				sphere_rad1[n_spheres1] = se->actual_radius;
				sphere_ijk1[n_spheres1] = [(ShipEntity*)se absoluteIJKForSubentity];
				n_spheres1++;
			}
		}
		for (i = 0; i < n_subs2; i++)
		{
			Entity* se = [other_subs objectAtIndex:i];
			if ((se)&&[se canCollide]&&(se->isShip))
			{
				entity2[n_spheres2] = (ShipEntity*)se;
				sphere_positions2[n_spheres2] = [(ShipEntity*)se absolutePositionForSubentity];
				sphere_rad2[n_spheres2] = se->actual_radius;
				sphere_ijk2[n_spheres2] = [(ShipEntity*)se absoluteIJKForSubentity];
				n_spheres2++;
			}
		}
		for (i = 0; i < n_spheres1; i++)
		{
			for (j = 0; j < n_spheres2; j++)
			{
				double d1 = sphere_rad1[i] + sphere_rad2[j];
				double d2 = distance2( sphere_positions1[i], sphere_positions2[j]);
				if (d2 < d1 * d1)
				{
//					NSLog(@"DEBUG performing further checks for collision between %@ and %@", entity1[i], entity2[j]);

					BOOL collision = YES;
										
					if ((i == 0)&&(j == 0))
						collision = NO;	// already established
					else
					{
						Octree* oct1 = entity1[i]->octree;
						Octree* oct2 = entity2[j]->octree;
						Vector rp = resolveVectorInIJK( vector_between( sphere_positions1[i], sphere_positions2[j]), sphere_ijk1[i]);
						Triangle other_ijk;
						other_ijk.v[0] = resolveVectorInIJK( sphere_ijk2[j].v[0], sphere_ijk1[i]);
						other_ijk.v[1] = resolveVectorInIJK( sphere_ijk2[j].v[1], sphere_ijk1[i]);
						other_ijk.v[2] = resolveVectorInIJK( sphere_ijk2[j].v[2], sphere_ijk1[i]);
						if ([oct1 isHitByOctree: oct2 withOrigin: rp andIJK: other_ijk])
							collision = YES;
					}
					
//					if (i == 0)
//					{
//						if (j == 0)
//							collision = [self checkBoundingBoxCollisionWith: other];
//					}
//					else
//					{
//						if (j == 0)
//							collision = [entity1[i] subentityCheckBoundingBoxCollisionWith: other];
//					}
					if (collision)
					{
						collider = entity2[j];
						return YES;
					}
				}
			}
		}
		return NO;
	}
	collider = other;
	return YES;
}

- (BOOL) checkBoundingBoxCollisionWith:(Entity *)other
{
	if (other->isShip)
	{
		// check bounding boxes ...
		//
		// get bounding box relative to this ship's orientation
		BoundingBox arbb = [other findBoundingBoxRelativeTo:self InVectors: v_right: v_up: v_forward];

		// construct 6 rectangles based on the sides of the possibly overlapping bounding boxes
		NSRect  other_x_rect = NSMakeRect(arbb.min.z, arbb.min.y, arbb.max.z - arbb.min.z, arbb.max.y - arbb.min.y);
		NSRect  other_y_rect = NSMakeRect(arbb.min.x, arbb.min.z, arbb.max.x - arbb.min.x, arbb.max.z - arbb.min.z);
		NSRect  other_z_rect = NSMakeRect(arbb.min.x, arbb.min.y, arbb.max.x - arbb.min.x, arbb.max.y - arbb.min.y);

		NSRect  ship_x_rect = NSMakeRect(boundingBox.min.z, boundingBox.min.y, boundingBox.max.z - boundingBox.min.z, boundingBox.max.y - boundingBox.min.y);
		NSRect  ship_y_rect = NSMakeRect(boundingBox.min.x, boundingBox.min.z, boundingBox.max.x - boundingBox.min.x, boundingBox.max.z - boundingBox.min.z);
		NSRect  ship_z_rect = NSMakeRect(boundingBox.min.x, boundingBox.min.y, boundingBox.max.x - boundingBox.min.x, boundingBox.max.y - boundingBox.min.y);

		if (NSIntersectsRect(ship_x_rect,other_x_rect) && NSIntersectsRect(ship_y_rect,other_y_rect) && NSIntersectsRect(ship_z_rect,other_z_rect))
			return YES;
		else
			return NO;
	}
	if (other->isParticle)
	{
		// check bounding boxes ...
		//
		// get position relative to this ship's orientation
		Vector	r_pos = other->position;
		double	cr = other->collision_radius;
		r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
		if	((r_pos.x + cr > boundingBox.min.x)&&
				(r_pos.x - cr < boundingBox.max.x)&&
				(r_pos.y + cr > boundingBox.min.y)&&
				(r_pos.y - cr < boundingBox.max.y)&&
				(r_pos.z + cr > boundingBox.min.z)&&
				(r_pos.z - cr < boundingBox.max.z))
			return YES;
		else
			return NO;
	}
	return YES;
}

- (BOOL) subentityCheckBoundingBoxCollisionWith:(Entity *)other
{
//	NSLog(@"DEBUG [%@ subentityCheckBoundingBoxCollisionWith:%@]", self, other);

	BoundingBox sebb = [self findSubentityBoundingBox];

//	NSLog(@"DEBUG bounding box for subentity: %@ [%.1fm %.1fm]x [%.1fm %.1fm]y [%.1fm %.1fm]z", self,
//		sebb.min.x, sebb.max.x, sebb.min.y, sebb.max.y, sebb.min.z, sebb.max.z);

	if (other->isShip)
	{
		// check bounding boxes ...
		Entity* parent = [self owner];
		if (!parent)
			return NO;
		Vector i = vector_right_from_quaternion(parent->q_rotation);
		Vector j = vector_up_from_quaternion(parent->q_rotation);
		Vector k = vector_forward_from_quaternion(parent->q_rotation);

		//
		// get bounding box relative to this ship's orientation
		BoundingBox arbb = [other findBoundingBoxRelativeTo:parent InVectors: i: j: k];

//		NSLog(@"DEBUG bounding box for other: %@ [%.1fm %.1fm]x [%.1fm %.1fm]y [%.1fm %.1fm]z", other,
//			arbb.min.x, arbb.max.x, arbb.min.y, arbb.max.y, arbb.min.z, arbb.max.z);

		// construct 6 rectangles based on the sides of the possibly overlapping bounding boxes
		NSRect  x_rect = NSMakeRect(sebb.min.z, sebb.min.y, sebb.max.z - sebb.min.z, sebb.max.y - sebb.min.y);
		NSRect  y_rect = NSMakeRect(sebb.min.x, sebb.min.z, sebb.max.x - sebb.min.x, sebb.max.z - sebb.min.z);
		NSRect  z_rect = NSMakeRect(sebb.min.x, sebb.min.y, sebb.max.x - sebb.min.x, sebb.max.y - sebb.min.y);
		NSRect  other_x_rect = NSMakeRect(arbb.min.z, arbb.min.y, arbb.max.z - arbb.min.z, arbb.max.y - arbb.min.y);
		NSRect  other_y_rect = NSMakeRect(arbb.min.x, arbb.min.z, arbb.max.x - arbb.min.x, arbb.max.z - arbb.min.z);
		NSRect  other_z_rect = NSMakeRect(arbb.min.x, arbb.min.y, arbb.max.x - arbb.min.x, arbb.max.y - arbb.min.y);

//		NSLog(@"DEBUG intersects in x:%@: y:%@: z:%@",
//			NSIntersectsRect(x_rect,other_x_rect)? @"YES": @"NO ",
//			NSIntersectsRect(y_rect,other_y_rect)? @"YES": @"NO ",
//			NSIntersectsRect(z_rect,other_z_rect)? @"YES": @"NO ");

		if (NSIntersectsRect(x_rect,other_x_rect) && NSIntersectsRect(y_rect,other_y_rect) && NSIntersectsRect(z_rect,other_z_rect))
			return YES;
		else
			return NO;
	}
	if (other->isParticle)
	{
		// check bounding boxes ...
		//
		// get position relative to this ship's orientation
		Vector	r_pos = other->position;
		double	cr = other->collision_radius;
		r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
		if	((r_pos.x + cr > sebb.min.x)&&
				(r_pos.x - cr < sebb.max.x)&&
				(r_pos.y + cr > sebb.min.y)&&
				(r_pos.y - cr < sebb.max.y)&&
				(r_pos.z + cr > sebb.min.z)&&
				(r_pos.z - cr < sebb.max.z))
			return YES;
		else
			return NO;
	}
	return YES;
}

- (BoundingBox) findSubentityBoundingBox
{
	BoundingBox result;
	Vector  v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	bounding_box_reset_to_vector(&result,v);
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		bounding_box_add_vector(&result,v);
    }

//	NSLog(@"DEBUG subentity bounding box for %@ of %@ is [%.1fm %.1fm]x [%.1fm %.1fm]y [%.1fm %.1fm]z", self, [self owner],
//		result.min.x, result.max.x, result.min.y, result.max.y, result.min.z, result.max.z);

	return result;
}

- (BoundingBox) findSubentityBoundingBoxRelativeTo: (Entity*)other inVectors: (Vector)vi: (Vector)vj: (Vector)vk
{
	Entity* parent = [self owner];
	Vector	othpos = other->position;
	Vector	parent_pos = parent->position;
	Vector	relpos = make_vector( parent_pos.x - othpos.x, parent_pos.y - othpos.y, parent_pos.z - othpos.z);
	GLfloat*	parent_rotmatrix = [parent drawRotationMatrix];
	BoundingBox result;
	Vector	v,	w;
	v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	mult_vector_gl_matrix(&v, parent_rotmatrix);
	v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
	w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
	bounding_box_reset_to_vector(&result,w);
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		mult_vector_gl_matrix(&v, parent_rotmatrix);
		v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
		w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
		bounding_box_add_vector(&result,w);
    }

	return result;
}

- (BoundingBox) findSubentityBoundingBoxRelativeToPosition: (Vector)othpos inVectors: (Vector)vi: (Vector)vj: (Vector)vk
{
	Entity* parent = [self owner];
	Vector	parent_pos = parent->position;
	Vector	relpos = make_vector( parent_pos.x - othpos.x, parent_pos.y - othpos.y, parent_pos.z - othpos.z);
	GLfloat*	parent_rotmatrix = [parent drawRotationMatrix];
	BoundingBox result;
	Vector	v,	w;
	v = vertices[0];
	mult_vector_gl_matrix(&v, rotMatrix);
	v.x += position.x;	v.y += position.y;	v.z += position.z;
	mult_vector_gl_matrix(&v, parent_rotmatrix);
	v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
	w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
	bounding_box_reset_to_vector(&result,w);
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		v = vertices[i];
		mult_vector_gl_matrix(&v, rotMatrix);
		v.x += position.x;	v.y += position.y;	v.z += position.z;
		mult_vector_gl_matrix(&v, parent_rotmatrix);
		v.x += relpos.x;	v.y += relpos.y;	v.z += relpos.z;
		w = make_vector( dot_product( v, vi), dot_product( v, vj), dot_product( v, vk));
		bounding_box_add_vector(&result,w);
    }
	return result;
}


- (Vector) absolutePositionForSubentity
{
	Vector		abspos = position;
	Entity*		last = nil;
	Entity*		father = [self owner];
	while ((father)&&(father != last))
	{
		GLfloat* r_mat = [father drawRotationMatrix];
		mult_vector_gl_matrix(&abspos, r_mat);
		Vector pos = father->position;
		abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
		last = father;
		father = [father owner];
	}
	return abspos;
}

- (Vector) absolutePositionForSubentityOffset:(Vector) offset
{

	Vector		off = offset;
	mult_vector_gl_matrix(&off, rotMatrix);
	Vector		abspos = make_vector( position.x + off.x, position.y + off.y, position.z + off.z);
	Entity*		last = nil;
	Entity*		father = [self owner];
	while ((father)&&(father != last))
	{
		GLfloat* r_mat = [father drawRotationMatrix];
		mult_vector_gl_matrix(&abspos, r_mat);
		Vector pos = father->position;
		abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
		last = father;
		father = [father owner];
	}
	return abspos;
}

- (Triangle) absoluteIJKForSubentity;
{
	Triangle	result;
	result.v[0] = make_vector( 1.0, 0.0, 0.0);
	result.v[1] = make_vector( 0.0, 1.0, 0.0);
	result.v[2] = make_vector( 0.0, 0.0, 1.0);
	Entity*		last = nil;
	Entity*		father = self;
	while ((father)&&(father != last))
	{
		GLfloat* r_mat = [father drawRotationMatrix];
		mult_vector_gl_matrix(&result.v[0], r_mat);
		mult_vector_gl_matrix(&result.v[1], r_mat);
		mult_vector_gl_matrix(&result.v[2], r_mat);
		last = father;
		father = [father owner];
	}
	return result;
}

- (void) addSolidSubentityToCollisionRadius:(ShipEntity*) subent
{
	if (!subent)
		return;

	double distance = sqrt(magnitude2(subent->position)) + [subent findCollisionRadius];
	if (distance > collision_radius)
		collision_radius = distance;
}


- (void) update:(double) delta_t
{
	//
	// deal with collisions
	//
	[self manageCollisions];
	[self saveToLastFrame];

	//
	// reset any inadvertant legal mishaps
	//
	if (scan_class == CLASS_POLICE)
	{
		if (bounty > 0)
			bounty = 0;
		ShipEntity* targEnt = (ShipEntity*)[universe entityForUniversalID:primaryTarget];
		if ((targEnt)&&(targEnt->scan_class == CLASS_POLICE))
		{
			primaryTarget = NO_TARGET;
			[shipAI reactToMessage:@"TARGET_LOST"];
		}
	}
	//

	if (trackCloseContacts)
	{
		// in checkCloseCollisionWith: we check if some thing has come within touch range (origin within our collision_radius)
		// here we check if it has gone outside that range
		NSArray* shipIDs = [closeContactsInfo allKeys];
		int i = 0;
		int n_ships = [shipIDs count];
		for (i = 0; i < n_ships; i++)
		{
			NSString*	other_key = (NSString*)[shipIDs objectAtIndex:i];
			ShipEntity* other = (ShipEntity*)[universe entityForUniversalID:[other_key intValue]];
			if ((other != nil) && (other->isShip))
			{
				if (distance2( position, other->position) > collision_radius * collision_radius)	// moved beyond our sphere!
				{
					// calculate position with respect to our own position and orientation
					Vector	dpos = vector_between( position, other->position);
					Vector  pos1 = make_vector( dot_product(dpos, v_right), dot_product(dpos, v_up), dot_product(dpos, v_forward));
					Vector	pos0 = [Entity vectorFromString:(NSString *)[closeContactsInfo objectForKey: other_key]];
					// send AI messages about the contact
					int	temp_id = primaryTarget;
					primaryTarget = other->universal_id;
					if ((pos0.x < 0.0)&&(pos1.x > 0.0))
						[shipAI reactToMessage:@"POSITIVE X TRAVERSE"];
					if ((pos0.x > 0.0)&&(pos1.x < 0.0))
						[shipAI reactToMessage:@"NEGATIVE X TRAVERSE"];
					if ((pos0.y < 0.0)&&(pos1.y > 0.0))
						[shipAI reactToMessage:@"POSITIVE Y TRAVERSE"];
					if ((pos0.y > 0.0)&&(pos1.y < 0.0))
						[shipAI reactToMessage:@"NEGATIVE Y TRAVERSE"];
					if ((pos0.z < 0.0)&&(pos1.z > 0.0))
						[shipAI reactToMessage:@"POSITIVE Z TRAVERSE"];
					if ((pos0.z > 0.0)&&(pos1.z < 0.0))
						[shipAI reactToMessage:@"NEGATIVE Z TRAVERSE"];
					primaryTarget = temp_id;
					[closeContactsInfo removeObjectForKey: other_key];
				}
			}
			else
				[closeContactsInfo removeObjectForKey: other_key];
		}
	}

	// super update
	//
	[super update:delta_t];

	// DEBUGGING
	//
	if (reportAImessages && (debug_condition != behaviour))
	{
		NSLog(@"DEBUG %@ behaviour is now %d", self, behaviour);
		debug_condition = behaviour;
	}

	// update time between shots
	//
	shot_time +=delta_t;

	// handle radio message effects
	//
	if (message_time > 0.0)
	{
		message_time -= delta_t;
		if (message_time < 0.0)
			message_time = 0.0;
	}

	// temperature factors
	//
	double external_temp = 0.0;
	if ([universe sun])
	{
		PlanetEntity* sun = [universe sun];
		// set the ambient temperature here
		double  sun_zd = magnitude2(vector_between( position, sun->position));	// square of distance
		double  sun_cr = sun->collision_radius;
		double	alt1 = sun_cr * sun_cr / sun_zd;
		external_temp = SUN_TEMPERATURE * alt1;
		if ([sun goneNova])
			external_temp *= 100;
	}

	// work on the ship temperature
	//
	if (external_temp > ship_temperature)
		ship_temperature += (external_temp - ship_temperature) * delta_t * SHIP_INSULATION_FACTOR / heat_insulation;
	else
	{
		if (ship_temperature > SHIP_MIN_CABIN_TEMP)
			ship_temperature += (external_temp - ship_temperature) * delta_t * SHIP_COOLING_FACTOR / heat_insulation;
	}

	if (ship_temperature > SHIP_MAX_CABIN_TEMP)
		[self takeHeatDamage: delta_t * ship_temperature];

	// are we burning due to low energy
	if ((energy < max_energy * 0.20)&&(energy_recharge_rate > 0.0))	// prevents asteroid etc. from burning
		throw_sparks = YES;

	// burning effects
	//
	if (throw_sparks)
	{
		next_spark_time -= delta_t;
		if (next_spark_time < 0.0)
		{
			[self throwSparks];
			throw_sparks = NO;	// until triggered again
		}
	}

	// cloaking device
	if (has_cloaking_device)
	{
		if (cloaking_device_active)
		{
			energy -= delta_t * CLOAKING_DEVICE_ENERGY_RATE;
			if (energy < CLOAKING_DEVICE_MIN_ENERGY)
				[self deactivateCloakingDevice];
		}
		else
		{
			if (energy < max_energy)
			{
				energy += delta_t * CLOAKING_DEVICE_ENERGY_RATE;
				if (energy > max_energy)
				{
					energy = max_energy;
					[shipAI message:@"ENERGY_FULL"];
				}
			}
		}
	}

	// military_jammer
	if (has_military_jammer)
	{
		if (military_jammer_active)
		{
			energy -= delta_t * MILITARY_JAMMER_ENERGY_RATE;
			if (energy < MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = NO;
		}
		else
		{
			if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = YES;
		}
	}

	// check outside factors
	//
	aegis_status = [self checkForAegis];   // is a station or something nearby??

	//scripting
	if ((status == STATUS_IN_FLIGHT)&&([launch_actions count]))
	{
		[(PlayerEntity *)[universe entityZero] setScript_target:self];
		[(PlayerEntity *)[universe entityZero] scriptActions: launch_actions forTarget: self];
		[launch_actions removeAllObjects];
	}

	// behaviours according to status and behaviour
    //
	if (status == STATUS_LAUNCHING)
	{
		if ([universe getTime] > launch_time + LAUNCH_DELAY)		// move for while before thinking
		{
			status = STATUS_IN_FLIGHT;
			[shipAI reactToMessage: @"LAUNCHED OKAY"];
			//accepts_escorts = YES;
		}
		else
		{
			// ignore behaviour just keep moving...
			[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
			[self applyThrust:delta_t];
			if (energy < max_energy)
			{
				energy += energy_recharge_rate * delta_t;
				if (energy > max_energy)
				{
					energy = max_energy;
					[shipAI message:@"ENERGY_FULL"];
				}
			}
			return;
		}
	}
	//
	// double check scooped behaviour
	//
	if (status == STATUS_BEING_SCOOPED)
	{
		if (behaviour != BEHAVIOUR_TRACTORED)
		{
			// escaped tractor beam
			status = STATUS_IN_FLIGHT;	// should correct 'uncollidable objects' bug
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
		}
	}
	//
	if (status == STATUS_COCKPIT_DISPLAY)
    {
		[self applyRoll: delta_t * flight_roll andClimb: delta_t * flight_pitch];
		GLfloat range2 = 0.1 * distance2( position, destination) / (collision_radius * collision_radius);
		if ((range2 > 1.0)||(velocity.z > 0.0))	range2 = 1.0;
		position.x += range2 * delta_t * velocity.x;
		position.y += range2 * delta_t * velocity.y;
		position.z += range2 * delta_t * velocity.z;
//		return;	// here's our problem!
    }
	else
	{
		double  target_speed = max_flight_speed;

		ShipEntity*	target = (ShipEntity*)[universe entityForUniversalID:primaryTarget];

		if ((target == nil)||(target->scan_class == CLASS_NO_DRAW)||(!target->isShip))
		{
			 // It's no longer a parrot, it has ceased to be, it has joined the choir invisible...
			if (primaryTarget != NO_TARGET)
			{
				[shipAI reactToMessage:@"TARGET_LOST"];
				primaryTarget = NO_TARGET;
			}
			else
			{
				target_speed = [(ShipEntity *)[universe entityForUniversalID:primaryTarget] flight_speed];
				if (target_speed < max_flight_speed)
				{
					target_speed += max_flight_speed;
					target_speed /= 2.0;
				}
			}
		}

		switch (behaviour)
		{
			case BEHAVIOUR_TUMBLE :
				[self behaviour_tumble: delta_t];
				break;

			case BEHAVIOUR_STOP_STILL :
			case BEHAVIOUR_STATION_KEEPING :
				[self behaviour_stop_still: delta_t];
				break;

			case BEHAVIOUR_IDLE :
				[self behaviour_idle: delta_t];
				break;

			case BEHAVIOUR_TRACTORED :
				[self behaviour_tractored: delta_t];
				break;

			case BEHAVIOUR_TRACK_TARGET :
				[self behaviour_track_target: delta_t];
				break;

			case BEHAVIOUR_INTERCEPT_TARGET :
			case BEHAVIOUR_COLLECT_TARGET :
				[self behaviour_intercept_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_TARGET :
				[self behaviour_attack_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX :
			case BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE :
				[self behaviour_fly_to_target_six: delta_t];
				break;

			case BEHAVIOUR_ATTACK_MINING_TARGET :
				[self behaviour_attack_mining_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_TO_TARGET :
				[self behaviour_attack_fly_to_target: delta_t];
				break;

			case BEHAVIOUR_ATTACK_FLY_FROM_TARGET :
				[self behaviour_attack_fly_from_target: delta_t];
				break;

			case BEHAVIOUR_RUNNING_DEFENSE :
				[self behaviour_running_defense: delta_t];
				break;

			case BEHAVIOUR_FLEE_TARGET :
				[self behaviour_flee_target: delta_t];
				break;

			case BEHAVIOUR_FLY_RANGE_FROM_DESTINATION :
				[self behaviour_fly_range_from_destination: delta_t];
				break;

			case BEHAVIOUR_FACE_DESTINATION :
				[self behaviour_face_destination: delta_t];
				break;

			case BEHAVIOUR_FORMATION_FORM_UP :
				[self behaviour_formation_form_up: delta_t];
				break;

			case BEHAVIOUR_FLY_TO_DESTINATION :
				[self behaviour_fly_to_destination: delta_t];
				break;

			case BEHAVIOUR_FLY_FROM_DESTINATION :
			case BEHAVIOUR_FORMATION_BREAK :
				[self behaviour_fly_from_destination: delta_t];
				break;

			case BEHAVIOUR_AVOID_COLLISION :
				[self behaviour_avoid_collision: delta_t];
				break;

			case BEHAVIOUR_TRACK_AS_TURRET :
				[self behaviour_track_as_turret: delta_t];
				break;

			case BEHAVIOUR_EXPERIMENTAL :
				[self behaviour_experimental: delta_t];
				break;

		}
		//
		// manage energy
		//
		if (energy < max_energy)
		{
			energy += energy_recharge_rate * delta_t;
			if (energy > max_energy)
			{
				energy = max_energy;
				[shipAI message:@"ENERGY_FULL"];
			}
		}
//		//
//		// subentity rotation
//		//
//		if ((subentity_rotational_velocity.x)||(subentity_rotational_velocity.y)||(subentity_rotational_velocity.z)||(subentity_rotational_velocity.w != 1.0))
//		{
//			Quaternion qf = subentity_rotational_velocity;
//			qf.w *= (1.0 - delta_t);
//			qf.x *= delta_t;
//			qf.y *= delta_t;
//			qf.z *= delta_t;
//			q_rotation = quaternion_multiply( qf, q_rotation);
//		}
//		//
//		//
//		if (sub_entities)
//		{
//			int i;
//			for (i = 0; i < [sub_entities count]; i++)
//				[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
//		}
		//
		// update destination position for escorts
		if (n_escorts > 0)
		{
			int i;
			for (i = 0; i < n_escorts; i++)
			{
				ShipEntity *escorter = (ShipEntity *)[universe entityForUniversalID:escort_ids[i]];
				// check it's still an escort ship
				BOOL escorter_okay = YES;
				if (!escorter)
					escorter_okay = NO;
				else
					escorter_okay = escorter->isShip;
				if (escorter_okay)
					[escorter setDestination:[self getCoordinatesForEscortPosition:i]];	// update its destination
				else
					escort_ids[i--] = escort_ids[--n_escorts];	// remove the escort
			}
		}
    }

	//
	// subentity rotation
	//
	if ((subentity_rotational_velocity.x)||(subentity_rotational_velocity.y)||(subentity_rotational_velocity.z)||(subentity_rotational_velocity.w != 1.0))
	{
		Quaternion qf = subentity_rotational_velocity;
		qf.w *= (1.0 - delta_t);
		qf.x *= delta_t;
		qf.y *= delta_t;
		qf.z *= delta_t;
		q_rotation = quaternion_multiply( qf, q_rotation);
	}

	//
	// update subentities
	//
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
			[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
	}

}


// override Entity version...
//
- (double) getVelocityAsSpeed
{
	return sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z + flight_speed * flight_speed);
}


////////////////
//            //
// behaviours //
//            //
- (void) behaviour_stop_still:(double) delta_t
{
	double		damping = 0.5 * delta_t;
	// damp roll
	if (flight_roll < 0)
		flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
	if (flight_roll > 0)
		flight_roll -= (flight_roll > damping) ? damping : flight_roll;
	// damp pitch
	if (flight_pitch < 0)
		flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
	if (flight_pitch > 0)
		flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_idle:(double) delta_t
{
	double		damping = 0.5 * delta_t;
	if ((!isStation)&&(scan_class != CLASS_BUOY))
	{
		// damp roll
		if (flight_roll < 0)
			flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
		if (flight_roll > 0)
			flight_roll -= (flight_roll > damping) ? damping : flight_roll;
	}
	if (scan_class != CLASS_BUOY)
	{
		// damp pitch
		if (flight_pitch < 0)
			flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
		if (flight_pitch > 0)
			flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;
	}
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_tumble:(double) delta_t
{
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_tractored:(double) delta_t
{
	double  distance = [self rangeToDestination];
	ShipEntity* hauler = (ShipEntity*)[self owner];
	if ((hauler)&&(hauler->isShip))
	{
		GLfloat tf = TRACTOR_FORCE / mass;
		desired_speed = 0.0;
		desired_range = collision_radius;
		destination = [hauler absoluteTractorPosition];
		// adjust for difference in velocity (spring rule)
		Vector dv = vector_between( [self getVelocity], [hauler getVelocity]);
		velocity.x += delta_t * dv.x * 0.25 * tf;
		velocity.y += delta_t * dv.y * 0.25 * tf;
		velocity.z += delta_t * dv.z * 0.25 * tf;
		// acceleration = force / mass
		// force proportional to distance (spring rule)
		Vector dp = vector_between( position, destination);
		velocity.x += delta_t * dp.x * tf;
		velocity.y += delta_t * dp.y * tf;
		velocity.z += delta_t * dp.z * tf;
		// force inversely proportional to distance
		GLfloat d2 = magnitude2(dp);
		if (d2 > 0.0)
		{
			velocity.x += delta_t * dp.x * tf / d2;
			velocity.y += delta_t * dp.y * tf / d2;
			velocity.z += delta_t * dp.z * tf / d2;
		}

		thrust = 10.0;	// used to damp velocity
		if (status == STATUS_BEING_SCOOPED)
		{
			if (hauler->isPlayer)
				[(PlayerEntity*)hauler setScoopsActive];
			if (distance > hauler->collision_radius + collision_radius + 250.f)	// 250m range for tractor beam
			{
				// escaped tractor beam
				status = STATUS_IN_FLIGHT;
				behaviour = BEHAVIOUR_IDLE;
				frustration = 0.0;
				[shipAI exitStateMachine];	// exit nullAI.plist
			}
			if (distance < desired_range)
			{
				[hauler scoopUp:self];
			}
		}
	}
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_track_target:(double) delta_t
{
	[self trackPrimaryTarget:delta_t:NO];
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_intercept_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (behaviour == BEHAVIOUR_INTERCEPT_TARGET)
	{
		desired_speed = max_flight_speed;
		if (range < desired_range)
			[shipAI reactToMessage:@"DESIRED_RANGE_ACHIEVED"];
		desired_speed = max_flight_speed * [self trackPrimaryTarget:delta_t:NO];
	}
	else
	{
		ShipEntity*	target = (ShipEntity*)[universe entityForUniversalID:primaryTarget];
		double target_speed = [target getVelocityAsSpeed];
		double eta = range / (flight_speed - target_speed);
		double last_success_factor = success_factor;
		double last_distance = last_success_factor;
		double  distance = [self rangeToDestination];
		success_factor = distance;
		//
		double slowdownTime = 96.0 / thrust;	// more thrust implies better slowing
		double minTurnSpeedFactor = 0.005 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if ((eta < slowdownTime)&&(flight_speed > max_flight_speed * minTurnSpeedFactor))
			desired_speed = flight_speed * 0.75;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed
		else
			desired_speed = max_flight_speed;

		if (desired_speed < target_speed)
		{
			desired_speed += target_speed;
			if (target_speed > max_flight_speed)
				[shipAI reactToMessage:@"TARGET_LOST"];
		}
		//
		if (target)	// check introduced to stop crash at next line
		{
			destination = target->position;		/* HEISENBUG crash here */
			desired_range = 0.5 * target->actual_radius;
			[self trackDestination: delta_t : NO];
		}
		//
		if (distance < last_distance)	// improvement
		{
			frustration -= delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if (frustration > 10.0)	// 10s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= 5.0;	//repeat after another five seconds' frustration
			}
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_target:(double) delta_t
{
	BOOL	canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double	max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	[self activateCloakingDevice];
	desired_speed = max_available_speed;
	if (range < 0.035 * weapon_range)
		behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
	else
		if (universal_id & 1)	// 50% of ships are smart S.M.R.T. smart!
		{
			if (randf() < 0.75)
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX;
			else
				behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
		}
		else
		{
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		}
	frustration = 0.0;	// behaviour changed, so reset frustration
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_fly_to_target_six:(double) delta_t
{
	BOOL canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	// deal with collisions and lost targets
	//
	if (proximity_alert != NO_TARGET)
		[self avoidCollision];
	if (range > SCANNER_MAX_RANGE)
	{
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		[shipAI reactToMessage:@"TARGET_LOST"];
	}

	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flight_speed > max_flight_speed);
	double	slow_down_range = weapon_range * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * AFTERBURNER_FACTOR : 1.0);
	ShipEntity*	target = (ShipEntity*)[universe entityForUniversalID:primaryTarget];
	double target_speed = [target getVelocityAsSpeed];
	double distance = [self rangeToDestination];
	if (range < slow_down_range)
	{
		desired_speed = MAX(target_speed, 0.25 * max_flight_speed);
		// avoid head-on collision
		//
		if ((range < 0.5 * distance)&&(behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX))
			behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE;
	}
	else
		desired_speed = max_available_speed; // use afterburner to approach


	// if within 0.75km of the target's six or twelve then vector in attack
	//
	if (distance < 750.0)
	{
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
		desired_speed = MAX(target_speed, 0.25 * max_flight_speed);   // within the weapon's range don't use afterburner
	}

	// target-six
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX)
	{
		// head for a point weapon-range * 0.5 to the six of the target
		//
		destination = [target distance_six:0.5 * weapon_range];
	}
	// target-twelve
	if (behaviour == BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE)
	{
		// head for a point 1.25km above the target
		//
		destination = [target distance_twelve:1250];
	}

	[self trackDestination:delta_t :NO];

	// use weaponry
	//
	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/max_energy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_mining_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if ((range < 650)||(proximity_alert != NO_TARGET))
	{
		if (proximity_alert == NO_TARGET)
		{
			desired_speed = range * max_flight_speed / (650.0 * 16.0);
		}
		else
		{
			[self avoidCollision];
		}
	}
	else
	{
		if (range > SCANNER_MAX_RANGE)
		{
			behaviour = BEHAVIOUR_IDLE;
			[shipAI reactToMessage:@"TARGET_LOST"];
		}
		desired_speed = max_flight_speed * 0.375;
	}
	[self trackPrimaryTarget:delta_t:NO];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_fly_to_target:(double) delta_t
{
	BOOL canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	if ((range < COMBAT_IN_RANGE_FACTOR * weapon_range)||(proximity_alert != NO_TARGET))
	{
		if (proximity_alert == NO_TARGET)
		{
			if (aft_weapon_type == WEAPON_NONE)
			{
				jink.x = (ranrot_rand() % 256) - 128.0;
				jink.y = (ranrot_rand() % 256) - 128.0;
				jink.z = 1000.0;
				behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
				frustration = 0.0;
				desired_speed = max_available_speed;
			}
			else
			{
				//NSLog(@"DEBUG >>>>> %@ %d entering running defense mode", name, universal_id);

				jink = make_vector( 0.0f, 0.0f, 0.0f);
				behaviour = BEHAVIOUR_RUNNING_DEFENSE;
				frustration = 0.0;
				desired_speed = max_flight_speed;
			}
		}
		else
		{
			[self avoidCollision];
		}
	}
	else
	{
		if (range > SCANNER_MAX_RANGE)
		{
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[shipAI reactToMessage:@"TARGET_LOST"];
		}
	}

	// control speed
	//
	BOOL isUsingAfterburner = canBurn && (flight_speed > max_flight_speed);
	double slow_down_range = weapon_range * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 3.0 * AFTERBURNER_FACTOR : 1.0);
	ShipEntity*	target = (ShipEntity*)[universe entityForUniversalID:primaryTarget];
	double target_speed = [target getVelocityAsSpeed];
	if (range <= slow_down_range)
		desired_speed = MAX(target_speed, 0.25 * max_flight_speed);   // within the weapon's range match speed
	else
		desired_speed = max_available_speed; // use afterburner to approach

	double last_success_factor = success_factor;
	success_factor = [self trackPrimaryTarget:delta_t:NO];	// do the actual piloting
	if ((success_factor > 0.999)||(success_factor > last_success_factor))
	{
		frustration -= delta_t;
		if (frustration < 0.0)
			frustration = 0.0;
	}
	else
	{
		frustration += delta_t;
		if (frustration > 3.0)	// 3s of frustration
		{
			[shipAI reactToMessage:@"FRUSTRATED"];
			// THIS IS HERE AS A TEST ONLY
			// BREAK OFF
			jink.x = (ranrot_rand() % 256) - 128.0;
			jink.y = (ranrot_rand() % 256) - 128.0;
			jink.z = 1000.0;
			behaviour = BEHAVIOUR_ATTACK_FLY_FROM_TARGET;
			frustration = 0.0;
			desired_speed = max_flight_speed;
		}
	}

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/max_energy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self fireMainWeapon:range];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_attack_fly_from_target:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (range > COMBAT_OUT_RANGE_FACTOR * weapon_range + 15.0 * jink.x)
	{
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 0.0;
		behaviour = BEHAVIOUR_ATTACK_TARGET;
		frustration = 0.0;
	}
	[self trackPrimaryTarget:delta_t:YES];

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	double hurt_factor = 16 * pow(energy/max_energy, 4.0);
	if (missiles > missile_chance * hurt_factor)
	{
		//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
		[self fireMissile];
	}
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_running_defense:(double) delta_t
{
	double  range = [self rangeToPrimaryTarget];
	if (range > weapon_range)
	{
		jink.x = 0.0;
		jink.y = 0.0;
		jink.z = 0.0;
		behaviour = BEHAVIOUR_ATTACK_FLY_TO_TARGET;
		frustration = 0.0;
	}
	[self trackPrimaryTarget:delta_t:YES];
	[self fireAftWeapon:range];
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_flee_target:(double) delta_t
{
	BOOL canBurn = has_fuel_injection && (fuel > 1);	// was &&(fuel > 0)
	double max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	double  range = [self rangeToPrimaryTarget];
	if (range > desired_range)
		[shipAI message:@"REACHED_SAFETY"];
	else
		desired_speed = max_available_speed;
	[self trackPrimaryTarget:delta_t:YES];

	int missile_chance = 0;
	int rhs = 3.2 / delta_t;
	if (rhs)	missile_chance = 1 + (ranrot_rand() % rhs);

	if ((has_energy_bomb) && (range < 10000.0))
	{
		float	qbomb_chance = 0.01 * delta_t;
		if (randf() < qbomb_chance)
		{
			[self launchEnergyBomb];
		}
	}

	double hurt_factor = 16 * pow(energy/max_energy, 4.0);
	if (([(ShipEntity *)[self getPrimaryTarget] getPrimaryTarget] == self)&&(missiles > missile_chance * hurt_factor))
		[self fireMissile];
	[self activateCloakingDevice];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_fly_range_from_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance < desired_range)
		behaviour = BEHAVIOUR_FLY_FROM_DESTINATION;
	else
		behaviour = BEHAVIOUR_FLY_TO_DESTINATION;
	frustration = 0.0;
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_face_destination:(double) delta_t
{
	double max_cos = 0.995;
	double distance = [self rangeToDestination];
	desired_speed = 0.0;
	if (desired_range > 1.0)
		max_cos = sqrt(1 - desired_range*desired_range/(distance * distance));
	else
		max_cos = 0.995;	// 0.995 - cos(5 degrees) is close enough
	double confidenceFactor = [self trackDestination:delta_t:NO];
	if (confidenceFactor > max_cos)
	{
		// desired facing achieved
		[shipAI message:@"FACING_DESTINATION"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_formation_form_up:(double) delta_t
{
	// get updated destination from owner
	ShipEntity* leadShip = (ShipEntity *)[universe entityForUniversalID:owner];
	double distance = [self rangeToDestination];
	double eta = (distance - desired_range) / flight_speed;
	if ((eta < 5.0)&&(leadShip)&&(leadShip->isShip))
		desired_speed = [leadShip flight_speed] * 1.25;
	else
		desired_speed = max_flight_speed;
	[self behaviour_fly_to_destination: delta_t];
}
//            //
- (void) behaviour_fly_to_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance < desired_range)// + collision_radius)
	{
		// desired range achieved
		[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		desired_speed = 0.0;
	}
	else
	{
		double last_success_factor = success_factor;
		double last_distance = last_success_factor;
		double eta = distance / flight_speed;

		success_factor = distance;

		// do the actual piloting!!
		[self trackDestination:delta_t:NO];

		double slowdownTime = (thrust > 0.0)? flight_speed / thrust : 4.0;	// 10% safety margin
		double minTurnSpeedFactor = 0.05 * max_flight_pitch * max_flight_roll;	// faster turning implies higher speeds

		if ((eta < slowdownTime)&&(flight_speed > max_flight_speed * minTurnSpeedFactor))
			desired_speed = flight_speed * 0.50;   // cut speed by 50% to a minimum minTurnSpeedFactor of speed

		if (distance < last_distance)	// improvement
		{
			frustration -= delta_t;
			if (frustration < 0.0)
				frustration = 0.0;
		}
		else
		{
			frustration += delta_t;
			if ((frustration > slowdownTime * 10.0)||(frustration > 15.0))	// 10x slowdownTime or 15s of frustration
			{
				[shipAI reactToMessage:@"FRUSTRATED"];
				frustration -= slowdownTime * 5.0;	//repeat after another five units of frustration
			}
		}
	}
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_fly_from_destination:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance > desired_range)
	{
		// desired range achieved
		[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		desired_speed = 0.0;
	}
	else
	{
		desired_speed = max_flight_speed;
	}
	[self trackDestination:delta_t:YES];
	if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
		[self avoidCollision];
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_avoid_collision:(double) delta_t
{
	double distance = [self rangeToDestination];
	if (distance > desired_range)
	{
		[self resumePostProximityAlert];
	}
	else
	{
		ShipEntity* prox_ship = [self proximity_alert];
		if (prox_ship)
		{
			desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE;
			destination = prox_ship->position;
		}
		double dq = [self trackDestination:delta_t:YES];
		if (dq >= 0)
			dq = 0.5 * dq + 0.5;
		else
			dq = 0.0;
		desired_speed = max_flight_speed * dq;
	}
	[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
	[self applyThrust:delta_t];
}
//            //
- (void) behaviour_track_as_turret:(double) delta_t
{
	double aim = [self ballTrackLeadingTarget:delta_t];
	ShipEntity* turret_owner = (ShipEntity *)[self owner];
	ShipEntity* turret_target = (ShipEntity *)[turret_owner getPrimaryTarget];
	//
	if ((turret_owner)&&(turret_target)&&[turret_owner hasHostileTarget])
	{
		Vector p1 = turret_target->position;
		Vector p0 = turret_owner->position;
		double cr = turret_owner->collision_radius;
		p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
		if (aim > .95)
			[self fireTurretCannon: sqrt( magnitude2( p1)) - cr];
	}
}
//            //
- (void) behaviour_experimental:(double) delta_t
{
	double aim = [self ballTrackTarget:delta_t];
	if (aim > .95)
	{
		NSLog(@"DEBUG BANG! BANG! BANG!");
	}
}
//            //
////////////////

// override Entity saveToLastFrame
//
- (void) saveToLastFrame
{
	double t_now = [universe getTime];
	if (t_now >= track_time + 0.1)		// update every 1/10 of a second
	{
		// save previous data
		Quaternion qrot = q_rotation;
		if (isPlayer)	qrot.w = -qrot.w;	// correct player's q_rotation
		track_time = t_now;
		track[track_index].position =	position;
		track[track_index].q_rotation =	qrot;
		track[track_index].timeframe =	track_time;
		track[track_index].k =	v_forward;
		//
		if (sub_entities)
		{
//			NSLog(@"DEBUG %@'s subentities ...", self);
			int i;
			int n = [sub_entities count];
			Frame thisFrame;
			thisFrame.q_rotation = qrot;
			thisFrame.timeframe = track_time;
			thisFrame.k = v_forward;
			for (i = 0; i < n; i++)
			{
				Entity* se = (Entity*)[sub_entities objectAtIndex:i];
				Vector	sepos = se->position;
				if ((se->isParticle)&&([(ParticleEntity*)se particleType] == PARTICLE_EXHAUST))
				{
					thisFrame.position = make_vector(
						position.x + v_right.x * sepos.x + v_up.x * sepos.y + v_forward.x * sepos.z,
						position.y + v_right.y * sepos.x + v_up.y * sepos.y + v_forward.y * sepos.z,
						position.z + v_right.z * sepos.x + v_up.z * sepos.y + v_forward.z * sepos.z);
					[se saveFrame:thisFrame atIndex:track_index];	// syncs subentity track_index to this entity
//					NSLog(@"DEBUG ... %@ %@ [%.2f %.2f %.2f]", self, se, thisFrame.position.x - position.x, thisFrame.position.y - position.y, thisFrame.position.z - position.z);
				}
			}
		}
		//
		track_index = (track_index + 1 ) & 0xff;
		//
	}
}

// reset position tracking
//
- (void) resetTracking
{
	Quaternion qrot = q_rotation;
	if (isPlayer)	qrot.w = -qrot.w;	// correct player's q_rotation
	Frame resetFrame;
	resetFrame.position = position;
	resetFrame.q_rotation = qrot;
	resetFrame.k = v_forward;
	Vector vel = make_vector( v_forward.x * flight_speed, v_forward.y * flight_speed, v_forward.z * flight_speed);
	[self resetFramesFromFrame:resetFrame withVelocity:vel];
	if (sub_entities)
	{
		int i;
		int n = [sub_entities count];
		for (i = 0; i < n; i++)
		{
			Entity* se = (Entity*)[sub_entities objectAtIndex:i];
			Vector	sepos = se->position;
			if ((se->isParticle)&&([(ParticleEntity*)se particleType] == PARTICLE_EXHAUST))
			{
				resetFrame.position = make_vector(
					position.x + v_right.x * sepos.x + v_up.x * sepos.y + v_forward.x * sepos.z,
					position.y + v_right.y * sepos.x + v_up.y * sepos.y + v_forward.y * sepos.z,
					position.z + v_right.z * sepos.x + v_up.z * sepos.y + v_forward.z * sepos.z);
				[se resetFramesFromFrame:resetFrame withVelocity:vel];
			}
		}
	}
}

// return a point 36u back from the front of the ship
// this equates with the centre point of a cobra mk3
//
- (Vector) getViewpointPosition
{
	Vector	viewpoint = position;
	float	nose = boundingBox.max.z - 36.0;
	viewpoint.x += nose * v_forward.x;	viewpoint.y += nose * v_forward.y;	viewpoint.z += nose * v_forward.z;
	return viewpoint;
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if (zero_distance > no_draw_distance)	return;	// TOO FAR AWAY

	if ([universe breakPatternHide])	return;	// DON'T DRAW

	if (cloaking_device_active && (randf() > 0.10))			return;	// DON'T DRAW

	if (!translucent)
		[super drawEntity:immediate:translucent];

//	// test octree drawing
//	if (translucent && (octree))
//		if (status == STATUS_COCKPIT_DISPLAY)
//			[octree drawOctree];

	//
	checkGLErrors([NSString stringWithFormat:@"ShipEntity after drawing Entity (main) %@", self]);
	//

	if (immediate)
		return;		// don't draw sub-entities when constructing a displayList

	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity  *se = (Entity *)[sub_entities objectAtIndex:i];
			[se setOwner:self]; // refresh ownership
			[se drawSubEntity:immediate:translucent];
		}
	}

	//
	checkGLErrors([NSString stringWithFormat:@"ShipEntity after drawing Entity (subentities) %@", self]);
	//
}

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
	Entity* my_owner = [universe entityForUniversalID:owner];
	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		//
		zero_distance = my_owner->zero_distance;
		if (zero_distance > no_draw_distance)
		{
			//NSLog(@"DEBUG - sub entity '%@' too far away to draw", self);
			return; // TOO FAR AWAY
		}
	}
	if (status == STATUS_ACTIVE)
	{
		Vector abspos = position;  // STATUS_ACTIVE means it is in control of it's own orientation
		Entity*		last = nil;
		Entity*		father = my_owner;
		GLfloat*	r_mat = [father drawRotationMatrix];
		while ((father)&&(father != last))
		{
			mult_vector_gl_matrix(&abspos, r_mat);
			Vector pos = father->position;
			abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
			last = father;
			father = [father owner];
			r_mat = [father drawRotationMatrix];
		}
		glPopMatrix();  // one down
		glPushMatrix();
				// position and orientation is absolute
		glTranslated( abspos.x, abspos.y, abspos.z);

		glMultMatrixf(rotMatrix);

		[self drawEntity:immediate :translucent];

//		NSLog(@"drawn active entity : %@", basefile);

	}
	else
	{
			glPushMatrix();

			glTranslated( position.x, position.y, position.z);
			glMultMatrixf(rotMatrix);

			[self drawEntity:immediate :translucent];

			glPopMatrix();
	}
}

static GLfloat cargo_color[4] =		{ 0.9, 0.9, 0.9, 1.0};	// gray
static GLfloat hostile_color[4] =	{ 1.0, 0.25, 0.0, 1.0};	// red/orange
static GLfloat neutral_color[4] =	{ 1.0, 1.0, 0.0, 1.0};	// yellow
static GLfloat friendly_color[4] =	{ 0.0, 1.0, 0.0, 1.0};	// green
static GLfloat missile_color[4] =	{ 0.0, 1.0, 1.0, 1.0};	// cyan
static GLfloat police_color1[4] =	{ 0.5, 0.0, 1.0, 1.0};	// purpley-blue
static GLfloat police_color2[4] =	{ 1.0, 0.0, 0.5, 1.0};	// purpley-red
static GLfloat jammed_color[4] =	{ 0.0, 0.0, 0.0, 0.0};	// clear black
static GLfloat mascem_color1[4] =	{ 0.3, 0.3, 0.3, 1.0};	// dark gray
static GLfloat mascem_color2[4] =	{ 0.4, 0.1, 0.4, 1.0};	// purple

- (GLfloat *) scannerDisplayColorForShip:(ShipEntity*)otherShip :(BOOL)isHostile :(BOOL)flash
{

	if (has_military_jammer && military_jammer_active)
	{
		if (![otherShip hasMilitaryScannerFilter])
			return jammed_color;
		else
		{
			if (flash)
				return mascem_color1;
			else
			{
				if (isHostile)
					return hostile_color;
				else
					return mascem_color2;
			}
		}
	}

	switch (scan_class)
	{
		case CLASS_ROCK :
		case CLASS_CARGO :
			return cargo_color;
		case CLASS_THARGOID :
			if (flash)
				return hostile_color;
			else
				return friendly_color;
		case CLASS_MISSILE :
			return missile_color;
		case CLASS_STATION :
			return friendly_color;
		case CLASS_BUOY :
			if (flash)
				return friendly_color;
			else
				return neutral_color;
		case CLASS_POLICE :
		case CLASS_MILITARY :
			if ((isHostile)&&(flash))
				return police_color2;
			else
				return police_color1;
		case CLASS_MINE :
			if (flash)
				return neutral_color;
			else
				return hostile_color;
		default :
			if (isHostile)
				return hostile_color;
	}
	return neutral_color;
}

- (BOOL) isJammingScanning
{
	return (has_military_jammer && military_jammer_active);
}

- (BOOL) hasMilitaryScannerFilter
{
	return has_military_scanner_filter;
}

- (void) addExhaust:(ParticleEntity *)exhaust
{
	if (!exhaust)
		return;
	if (sub_entities == nil)
		sub_entities = [[NSArray arrayWithObject:exhaust] retain];
	else
	{
		NSMutableArray *temp = [NSMutableArray arrayWithArray:sub_entities];
		[temp addObject:exhaust];
		[sub_entities release];
		sub_entities = [[NSArray arrayWithArray:temp] retain];
	}
}

- (void) addExhaustAt:(Vector) ex_position withScale:(Vector) ex_scale
{
	ParticleEntity *exhaust = [[ParticleEntity alloc] initExhaustFromShip:self offsetVector:ex_position scaleVector:ex_scale];  //retained
	[exhaust setStatus:STATUS_EFFECT];
	[self addExhaust:exhaust];
	[exhaust release];  // released
}


- (void) applyThrust:(double) delta_t
{
	double max_available_speed = (has_fuel_injection && (fuel > 1))? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;

	position.x += delta_t*velocity.x;
	position.y += delta_t*velocity.y;
	position.z += delta_t*velocity.z;

	//
	if (thrust)
	{
		GLfloat velmag = sqrt(magnitude2(velocity));
		if (velmag)
		{
			GLfloat velmag2 = velmag - delta_t * thrust;
			if (velmag2 < 0.0)
				velmag2 = 0.0;
			velocity.x *= velmag2 / velmag;
			velocity.y *= velmag2 / velmag;
			velocity.z *= velmag2 / velmag;
		}
	}

	if (behaviour == BEHAVIOUR_TUMBLE)  return; //testing


	// check for speed
	if (desired_speed > max_available_speed)
		desired_speed = max_available_speed;

	if (flight_speed > desired_speed)
	{
		[self decrease_flight_speed:delta_t*thrust];
		if (flight_speed < desired_speed)   flight_speed = desired_speed;
	}
	if (flight_speed < desired_speed)
	{
		[self increase_flight_speed:delta_t*thrust];
		if (flight_speed > desired_speed)   flight_speed = desired_speed;
	}
	[self moveForward:delta_t*flight_speed];

	// burn fuel at the appropriate rate
	if ((flight_speed > max_flight_speed) && has_fuel_injection && (fuel > 0))
	{
		fuel_accumulator -= delta_t * AFTERBURNER_NPC_BURNRATE;
		while (fuel_accumulator < 0.0)
		{
			if (fuel-- < 1)
				max_available_speed = max_flight_speed;
			fuel_accumulator += 1.0;
		}
	}
}

- (void) applyRoll:(GLfloat) roll1 andClimb:(GLfloat) climb1
{
	Quaternion q1;

	if ((!roll1)&&(!climb1)&&(!has_rotated))
		return;

	quaternion_set_identity(&q1);

	if (roll1)
		quaternion_rotate_about_z( &q1, -roll1);

	if (climb1)
		quaternion_rotate_about_x( &q1, -climb1);

	q_rotation = quaternion_multiply( q1, q_rotation);
	quaternion_normalise(&q_rotation);	// probably not strictly necessary but good to do to keep q_rotation sane
    quaternion_into_gl_matrix(q_rotation, rotMatrix);

	v_forward   = vector_forward_from_quaternion(q_rotation);
	v_up		= vector_up_from_quaternion(q_rotation);
	v_right		= vector_right_from_quaternion(q_rotation);
}


- (void) avoidCollision
{
	if (scan_class == CLASS_MISSILE)
		return;						// missiles are SUPPOSED to collide!

//	NSLog(@"DEBUG ***** %@ in AVOID COLLISION!", self);


	ShipEntity* prox_ship = [self proximity_alert];

	if (prox_ship)
	{
//		if (self == [universe entityZero])
//			NSLog(@"DEBUG ***** proximity alert for %@ %d against target %d", name, universal_id, proximity_alert);

		if (previousCondition)
		{
			//
//			NSLog(@"DEBUG ***** avoidCollision dropping previousCondition");
			//
			[previousCondition release];
			previousCondition = nil;
		}

		previousCondition = [(NSMutableDictionary *)[NSMutableDictionary alloc] initWithCapacity:16];

		[previousCondition setObject:[NSNumber numberWithInt:behaviour] forKey:@"behaviour"];
		[previousCondition setObject:[NSNumber numberWithInt:primaryTarget] forKey:@"primaryTarget"];
		[previousCondition setObject:[NSNumber numberWithFloat:desired_range] forKey:@"desired_range"];
		[previousCondition setObject:[NSNumber numberWithFloat:desired_speed] forKey:@"desired_speed"];
		[previousCondition setObject:[NSNumber numberWithFloat:destination.x] forKey:@"destination.x"];
		[previousCondition setObject:[NSNumber numberWithFloat:destination.y] forKey:@"destination.y"];
		[previousCondition setObject:[NSNumber numberWithFloat:destination.z] forKey:@"destination.z"];

		destination = prox_ship->position;
		destination.x += position.x;	destination.y += position.y;	destination.z += position.z;
		destination.x *= 0.5;	destination.y *= 0.5;	destination.z *= 0.5;	// point between us and them

		desired_range = prox_ship->collision_radius * PROXIMITY_AVOID_DISTANCE;

		behaviour = BEHAVIOUR_AVOID_COLLISION;
	}
}

- (void) resumePostProximityAlert
{
	if (!previousCondition)
		return;

//	NSLog(@"DEBUG ***** proximity alert for %@ %d over", name, universal_id, proximity_alert);

	behaviour =		[(NSNumber*)[previousCondition objectForKey:@"behaviour"] intValue];
	primaryTarget =	[(NSNumber*)[previousCondition objectForKey:@"primaryTarget"] intValue];
	desired_range =	[(NSNumber*)[previousCondition objectForKey:@"desired_range"] floatValue];
	desired_speed =	[(NSNumber*)[previousCondition objectForKey:@"desired_speed"] floatValue];
	destination.x =	[(NSNumber*)[previousCondition objectForKey:@"destination.x"] floatValue];
	destination.y =	[(NSNumber*)[previousCondition objectForKey:@"destination.y"] floatValue];
	destination.z =	[(NSNumber*)[previousCondition objectForKey:@"destination.z"] floatValue];

	[previousCondition release];
	previousCondition = nil;
	frustration = 0.0;

	proximity_alert = NO_TARGET;

	//[shipAI message:@"RESTART_DOCKING"];	// if docking, start over, other AIs will ignore this message
}

- (double) message_time
{
	return message_time;
}

- (void) setMessage_time:(double) value
{
	message_time = value;
}

- (int) group_id
{
	return group_id;
}

- (void) setGroup_id:(int) value
{
	group_id = value;
}

- (int) n_escorts
{
	return n_escorts;
}

- (void) setN_escorts:(int) value
{
	n_escorts = value;
	escortsAreSetUp = (n_escorts == 0);
}

- (ShipEntity*) proximity_alert
{
	return (ShipEntity*)[universe entityForUniversalID:proximity_alert];
}

- (void) setProximity_alert:(ShipEntity*) other
{
	if (!other)
	{
		proximity_alert = NO_TARGET;
		return;
	}

	if (isStation||(other->isStation))	// don't be alarmed close to stations
		return;

	if ((scan_class == CLASS_CARGO)||(scan_class == CLASS_BUOY)||(scan_class == CLASS_MISSILE)||(scan_class == CLASS_ROCK))	// rocks and stuff don't get alarmed easily
		return;

	// check vectors
	Vector vdiff = vector_between( position, other->position);
	GLfloat d_forward = dot_product( vdiff, v_forward);
	GLfloat d_up = dot_product( vdiff, v_up);
	GLfloat d_right = dot_product( vdiff, v_right);
	if ((d_forward > 0.0)&&(flight_speed > 0.0))	// it's ahead of us and we're moving forward
		d_forward *= 0.25 * max_flight_speed / flight_speed;	// extend the collision zone forward up to 400%
	double d2 = d_forward * d_forward + d_up * d_up + d_right * d_right;
	double cr2 = collision_radius * 2.0 + other->collision_radius;	cr2 *= cr2;	// check with twice the combined radius

	if (d2 > cr2) // we're okay
		return;

	if (behaviour == BEHAVIOUR_AVOID_COLLISION)	//	already avoiding something
	{
		ShipEntity* prox = (ShipEntity*)[universe entityForUniversalID:proximity_alert];
		if ((prox)&&(prox != other))
		{
			// check which subtends the greatest angle
			GLfloat sa_prox = prox->collision_radius * prox->collision_radius / distance2(position, prox->position);
			GLfloat sa_other = other->collision_radius *  other->collision_radius / distance2(position, other->position);
			if (sa_prox < sa_other)
			{
//				NSLog(@"DEBUG %@ is already avoiding %@", self, prox);
				return;
			}
		}
	}
	proximity_alert = [other universal_id];
	other->proximity_alert = universal_id;
//	NSLog(@"DEBUG PROXIMITY ALERT FOR %@  VS %@ == %d", self, other, proximity_alert);
}

- (NSString *) name
{
	return name;
}

- (NSString *) identFromShip:(ShipEntity*) otherShip
{
	if (has_military_jammer && military_jammer_active && (![otherShip hasMilitaryScannerFilter]))
		return @"Unknown Target";
	return name;
}

- (NSString *) roles
{
	return roles;
}

- (void) setRoles:(NSString *) value
{
	if (roles)
		[roles release];
	roles = [[NSString stringWithString:value] retain];
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
	return IS_BEHAVIOUR_HOSTILE(behaviour);
}

- (NSMutableArray *) launch_actions
{
	return launch_actions;
}

- (NSMutableArray *) script_actions
{
	return script_actions;
}

- (NSMutableArray *) death_actions
{
	return death_actions;
}

- (double) weapon_range
{
	return weapon_range;
}

- (void) setWeaponRange: (double) value
{
	weapon_range = value;
}

- (void) set_weapon_data_from_type: (int) weapon_type
{
	switch (weapon_type)
	{
		case WEAPON_PLASMA_CANNON :
			weapon_energy =			6.0;
			weapon_recharge_rate =	0.25;
			weapon_range =			5000;
			break;
		case WEAPON_PULSE_LASER :
			weapon_energy =			15.0;
			weapon_recharge_rate =	0.33;
			weapon_range =			12500;
			break;
		case WEAPON_BEAM_LASER :
			weapon_energy =			15.0;
			weapon_recharge_rate =	0.25;
			weapon_range =			15000;
			break;
		case WEAPON_MINING_LASER :
			weapon_energy =			50.0;
			weapon_recharge_rate =	0.5;
			weapon_range =			12500;
			break;
		case WEAPON_THARGOID_LASER :		// omni directional lasers FRIGHTENING!
			weapon_energy =			12.5;
			weapon_recharge_rate =	0.5;
			weapon_range =			17500;
			break;
		case WEAPON_MILITARY_LASER :
			weapon_energy =			23.0;
			weapon_recharge_rate =	0.20;
			weapon_range =			30000;
			break;
		case WEAPON_NONE :
			weapon_energy =			0.0;	// indicating no weapon!
			weapon_recharge_rate =	0.20;	// maximum rate
			weapon_range =			32000;
			break;
	}
}

- (double) scanner_range
{
	return scanner_range;
}

- (void) setScannerRange: (double) value
{
	scanner_range = value;
}

- (Vector) reference
{
	return reference;
}

- (void) setReference:(Vector) v
{
	reference.x = v.x;	reference.y = v.y;	reference.z = v.z;
}

- (BOOL) reportAImessages
{
	return reportAImessages;
}

- (void) setReportAImessages:(BOOL) yn
{
	reportAImessages = yn;
}

- (int) checkForAegis
{
	PlanetEntity* the_planet = [universe planet];

	if (!the_planet)
	{
		if (aegis_status != AEGIS_NONE)
			[shipAI message:@"AEGIS_NONE"];
		return AEGIS_NONE;
	}

	// check planet
	Vector p1 = the_planet->position;
	double cr = the_planet->collision_radius;
	double cr2 = cr * cr;
	int result = AEGIS_NONE;
	p1.x -= position.x;	p1.y -= position.y;	p1.z -= position.z;
	double d2 = p1.x*p1.x + p1.y*p1.y + p1.z*p1.z;
	// check if nearing surface
	//
//	if (reportAImessages)
//		NSLog(@"DEBUG reporting altitude d2(%.2f) - cr2(%.2f) = %.2f", d2, cr2, d2 - cr2);
	BOOL wasNearPlanetSurface = isNearPlanetSurface;
	isNearPlanetSurface = (d2 - cr2 < 3600000.0);
	if ((!wasNearPlanetSurface)&&(isNearPlanetSurface))
		[shipAI reactToMessage:@"APPROACHING_SURFACE"];
	if ((wasNearPlanetSurface)&&(!isNearPlanetSurface))
		[shipAI reactToMessage:@"LEAVING_SURFACE"];
	//
	d2 -= cr2 * 9.0; // to 3x radius of planet
	if (d2 < 0.0)
		result = AEGIS_CLOSE_TO_PLANET;
	// check station
	StationEntity* the_station = [universe station];
	if (!the_station)
	{
		if (aegis_status != AEGIS_NONE)
			[shipAI message:@"AEGIS_NONE"];
		return AEGIS_NONE;
	}
	p1 = the_station->position;
	p1.x -= position.x;	p1.y -= position.y;	p1.z -= position.z;
	d2 = p1.x*p1.x + p1.y*p1.y + p1.z*p1.z - SCANNER_MAX_RANGE2*4.0; // double scanner range
	if (d2 < 0.0)
		result = AEGIS_IN_DOCKING_RANGE;
	within_station_aegis = (d2 < 0.0);

	// ai messages on change in status
	// approaching..
	if ((aegis_status == AEGIS_NONE)&&(result == AEGIS_CLOSE_TO_PLANET))
		[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];
	if (((aegis_status == AEGIS_CLOSE_TO_PLANET)||(aegis_status == AEGIS_NONE))&&(result == AEGIS_IN_DOCKING_RANGE))
		[shipAI message:@"AEGIS_IN_DOCKING_RANGE"];
	// leaving..
	if ((aegis_status == AEGIS_IN_DOCKING_RANGE)&&(result == AEGIS_CLOSE_TO_PLANET))
		[shipAI message:@"AEGIS_LEAVING_DOCKING_RANGE"];
	if ((aegis_status != AEGIS_NONE)&&(result == AEGIS_NONE))
		[shipAI message:@"AEGIS_NONE"];

	aegis_status = result;	// put this here

	return result;
}

- (BOOL) within_station_aegis
{
	return within_station_aegis;
}

- (void) setStatus:(int) stat
{
	status = stat;
	if ((status == STATUS_LAUNCHING)&&(universe))
		launch_time = [universe getTime];
}

- (NSArray*) crew
{
	return crew;
}

- (void) setCrew: (NSArray*) crewArray
{
	if (crew)
		[crew autorelease];
	if (crewArray)
		crew = [[NSArray arrayWithArray:crewArray] retain];
	else
		crew = nil;
}

- (void) setStateMachine:(NSString *) ai_desc
{
	[shipAI setStateMachine: ai_desc];
}

- (void) setAI:(AI *) ai
{
	[ai retain];
	if (shipAI)
	{
		[shipAI clearAllData];
		[shipAI autorelease];
	}
	shipAI = ai;
}

- (AI *) getAI
{
	return shipAI;
}

- (int) fuel
{
	return fuel;
}

- (void) setFuel:(int) amount
{
	fuel = amount;
	if (fuel < 0)
		fuel = 0;
	if (fuel > 70)
		fuel = 70;
}

- (void) setRoll:(double) amount
{
	flight_roll = amount * PI / 2.0;
}

- (void) setPitch:(double) amount
{
	flight_pitch = amount * PI / 2.0;
}


- (void) setThrust:(double) amount
{
	thrust = amount;
}


- (void) setBounty:(int) amount
{
	bounty = amount;
}

- (int) getBounty
{
	return bounty;
}

- (int) legal_status
{
	if (scan_class == CLASS_THARGOID)
		return 5 * collision_radius;
	if (scan_class == CLASS_ROCK)
		return 0;
	return bounty;
}

- (void) setCommodity:(int) co_type andAmount:(int) co_amount;
{
	commodity_type = co_type;
	commodity_amount = co_amount;
}
- (int) getCommodityType
{
	return commodity_type;
}
- (int) getCommodityAmount
{
	return commodity_amount;
}

- (int) getMaxCargo
{
	return max_cargo;
}

- (int) getCargoType
{
	return cargo_type;
}

- (NSMutableArray*) cargo
{
	return cargo;
}

- (void) setCargo:(NSArray *) some_cargo
{
	[cargo removeAllObjects];
	[cargo addObjectsFromArray:some_cargo];
}

- (int) cargoFlag
{
	return cargo_flag;
}

- (void) setCargoFlag:(int) flag
{
	cargo_flag = flag;
}

- (void) setSpeed:(double) amount
{
	flight_speed = amount;
}

- (void) setDesiredSpeed:(double) amount
{
	desired_speed = amount;
}

- (void) increase_flight_speed:(double) delta
{
	double factor = ((desired_speed > max_flight_speed)&&(has_fuel_injection)&&(fuel > 0)) ? AFTERBURNER_FACTOR : 1.0;

	if (flight_speed < max_flight_speed * factor)
		flight_speed += delta * factor;
	else
		flight_speed = max_flight_speed * factor;
}

- (void) decrease_flight_speed:(double) delta
{
	if (flight_speed > -max_flight_speed)
		flight_speed -= delta;
	else
		flight_speed = -max_flight_speed;
}


- (void) increase_flight_roll:(double) delta
{
	if (flight_roll < max_flight_roll)
		flight_roll += delta;
	if (flight_roll > max_flight_roll)
		flight_roll = max_flight_roll;
}

- (void) decrease_flight_roll:(double) delta
{
	if (flight_roll > -max_flight_roll)
		flight_roll -= delta;
	if (flight_roll < -max_flight_roll)
		flight_roll = -max_flight_roll;
}


- (void) increase_flight_pitch:(double) delta
{
	if (flight_pitch < max_flight_pitch)
		flight_pitch += delta;
	if (flight_pitch > max_flight_pitch)
		flight_pitch = max_flight_pitch;
}


- (void) decrease_flight_pitch:(double) delta
{
	if (flight_pitch > -max_flight_pitch)
		flight_pitch -= delta;
	if (flight_pitch < -max_flight_pitch)
		flight_pitch = -max_flight_pitch;
}

- (double) flight_roll
{
	return flight_roll;
}

- (double) flight_pitch
{
	return flight_pitch;
}

- (double) flight_speed
{
	return flight_speed;
}

- (double) max_flight_speed
{
	return max_flight_speed;
}

- (double) speed_factor
{
	if (max_flight_speed <= 0.0)
		return 0.0;
	return flight_speed / max_flight_speed;
}

- (int) damage
{
	return (int)(100 - (100 * energy / max_energy));
}


- (void) dealEnergyDamageWithinDesiredRange
{
	NSArray* targets = [universe getEntitiesWithinRange:desired_range ofEntity:self];
	if ([targets count] > 0)
	{
		int i;
		for (i = 0; i < [targets count]; i++)
		{
			Entity *e2 = [targets objectAtIndex:i];
			Vector p2 = e2->position;
			double ecr = e2->collision_radius;
			p2.x -= position.x;	p2.y -= position.y;	p2.z -= position.z;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - ecr*ecr;
			double damage = weapon_energy*desired_range/d2;
			[e2 takeEnergyDamage:damage from:self becauseOf:[self owner]];

//			if ((e2)&&(e2->isShip))
//				NSLog(@"DEBUG Doing %.1f damage to %@ %d",damage,[(ShipEntity *)e2 name],[(ShipEntity *)e2 universal_id]);
		}
	}
}

- (void) dealMomentumWithinDesiredRange:(double)amount
{
	NSArray* targets = [universe getEntitiesWithinRange:desired_range ofEntity:self];
	if ([targets count] > 0)
	{
		int i;
		for (i = 0; i < [targets count]; i++)
		{
			ShipEntity *e2 = (ShipEntity*)[targets objectAtIndex:i];
			if (e2->isShip)
			{
				Vector p2 = e2->position;
				double ecr = e2->collision_radius;
				p2.x -= position.x;	p2.y -= position.y;	p2.z -= position.z;
				double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z - ecr*ecr;
				while (d2 <= 0.0)
				{
					p2 = make_vector( randf() - 0.5, randf() - 0.5, randf() - 0.5);
					d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z;
				}
				double moment = amount*desired_range/d2;
				[e2 addImpactMoment:unit_vector(&p2) fraction:moment];
			}
		}
	}
}

- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other
{
	if (status == STATUS_DEAD)  // it's too late for this one!
		return;
	if (amount == 0.0)
		return;
	if ((ent)&&(ent->isParticle)&&(ent->scan_class == CLASS_MINE))
	{
		if (self == [universe station])
		{
			if ((other)&&(other->isShip))
			{
				[(ShipEntity*)other markAsOffender:96];
				[self setPrimaryAggressor:other];
				found_target = primaryAggressor;
			}
			[(StationEntity*)self increaseAlertLevel];
			[shipAI reactToMessage:@"ATTACKED"];	// note use the reactToMessage: method NOT the think-delayed message: method
			return;	// Main stations are energy-bomb-proof!
		}

		// otherwise start a chain-reaction
		//
		if ((amount > energy)&&(energy > 10))
		{
				ParticleEntity* chain_reaction = [[ParticleEntity alloc] initEnergyMineFromShip:self];
				[universe addEntity:chain_reaction];
				[chain_reaction setOwner:[ent owner]];
				[chain_reaction release];
//			}
		}
	}
	//
	BOOL iAmTheLaw = (scan_class == CLASS_POLICE);
	BOOL uAreTheLaw = ((other)&&(other->scan_class == CLASS_POLICE));
	//
	energy -= amount;
	being_mined = NO;
	//
	// if the other entity is a ship note it as an aggressor
	if ((other)&&(other->isShip))
	{
		ShipEntity* hunter = (ShipEntity *)other;
		//
		last_escort_target = NO_TARGET;	// we're being attacked, escorts can scramble!
		//
		primaryAggressor = [hunter universal_id];
		found_target = primaryAggressor;

		// firing on an innocent ship is an offence
		[self broadcastHitByLaserFrom: hunter];

		// tell ourselves we've been attacked
		if (energy > 0)
			[shipAI reactToMessage:@"ATTACKED"];	// note use the reactToMessage: method NOT the think-delayed message: method

		// firing on an innocent ship is an offence
		[self broadcastHitByLaserFrom:(ShipEntity*) other];

		// tell our group we've been attacked
		if (group_id != NO_TARGET)
		{
			if ([roles isEqual:@"escort"]||[roles isEqual:@"trader"])
			{
				ShipEntity *group_leader = (ShipEntity *)[universe entityForUniversalID:group_id];
				if (group_leader)
				{
					//NSLog(@"DEBUG %@ %d informs group leader %@ %d of attack by %@ %d", name, universal_id, [group_leader name], [group_leader universal_id], [hunter name], [hunter universal_id]);

					//[group_leader setReportAImessages:YES];
					[group_leader setFound_target:hunter];
					[group_leader setPrimaryAggressor:hunter];
					[[group_leader getAI] reactToMessage:@"ATTACKED"];
				}
			}
			if ([roles isEqual:@"pirate"])
			{
				NSArray	*fellow_pirates = [self shipsInGroup:group_id];
				int i;
				for (i = 0; i < [fellow_pirates count]; i++)
				{
					ShipEntity *other_pirate = (ShipEntity *)[fellow_pirates objectAtIndex:i];
					if (randf() < 0.5)	// 50% chance they'll help
					{
						[other_pirate setFound_target:hunter];
						[other_pirate setPrimaryAggressor:hunter];
						[[other_pirate getAI] reactToMessage:@"ATTACKED"];
					}
				}
			}
			if (iAmTheLaw)
			{
				NSArray	*fellow_police = [self shipsInGroup:group_id];
				int i;
				for (i = 0; i < [fellow_police count]; i++)
				{
					ShipEntity *other_police = (ShipEntity *)[fellow_police objectAtIndex:i];
					[other_police setFound_target:hunter];
					[other_police setPrimaryAggressor:hunter];
					[[other_police getAI] reactToMessage:@"ATTACKED"];
				}
			}
		}

		// if I'm a copper and you're not, then mark the other as an offender!
		if ((iAmTheLaw)&&(!uAreTheLaw))
			[hunter markAsOffender:64];

		// avoid shooting each other
		if (([hunter group_id] == group_id)||(iAmTheLaw && uAreTheLaw))
		{
			if ([hunter behaviour] == BEHAVIOUR_ATTACK_FLY_TO_TARGET)	// avoid me please!
			{
				[hunter setBehaviour:BEHAVIOUR_ATTACK_FLY_FROM_TARGET];
				[hunter setDesiredSpeed:[hunter max_flight_speed]];
			}
		}

		if ((other)&&(other->isShip))
			being_mined = [(ShipEntity *)other isMining];
	}
	// die if I'm out of energy
	if (energy <= 0.0)
	{
		if ((other)&&(other->isShip))
		{
			ShipEntity* hunter = (ShipEntity *)other;
			[hunter collectBountyFor:self];
			if ([hunter getPrimaryTarget] == (Entity *)self)
			{
				[hunter removeTarget:(Entity *)self];
				[[hunter getAI] message:@"TARGET_DESTROYED"];
			}
		}

		[self becomeExplosion];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < max_energy *0.25)
			[shipAI reactToMessage:@"ENERGY_LOW"];
		if ((energy < max_energy *0.125)&&(has_escape_pod)&&((ranrot_rand() & 3) == 0))  // 25% chance he gets to an escape pod
		{
			has_escape_pod = NO;
			//NSLog(@"Escape Pod launched");
			[shipAI setStateMachine:@"nullAI.plist"];
			[shipAI setState:@"GLOBAL"];
			behaviour = BEHAVIOUR_IDLE;
			frustration = 0.0;
			[self launchEscapeCapsule];
			[self setScanClass: CLASS_CARGO];			// we're unmanned now!
			thrust = thrust * 0.5;
			desired_speed = 0.0;
			max_flight_speed = 0.0;
		}
	}
}

- (void) becomeExplosion
{
	// check if we're destroying a subentity
	ShipEntity* parent = (ShipEntity*)[self owner];
	if ((parent)&&(parent != self)&&(parent->isShip)&&[parent->sub_entities containsObject:self])
	{
		ShipEntity* this_ship = [self retain];
		Vector this_pos = [self absolutePositionForSubentity];
		// remove this ship from its parent's subentity list
		NSMutableArray *temp = [NSMutableArray arrayWithArray:parent->sub_entities];
		[temp removeObject:this_ship];
		[parent->sub_entities autorelease];
		parent->sub_entities = [[NSArray arrayWithArray:temp] retain];
		[universe addEntity:this_ship];
		this_ship->position = this_pos;
		[this_ship release];
	}

	Vector	xposition = position;
	ParticleEntity  *fragment;
	int i;
	Vector v;
	Quaternion q;
	int speed_low = 200;
	int n_alloys = floor((boundingBox.max.z - boundingBox.min.z) / 50.0);

	if (status == STATUS_DEAD)
	{
		[universe removeEntity:self];
		return;
	}
	status = STATUS_DEAD;
	//scripting
	if ([death_actions count])
	{
		PlayerEntity* player = (PlayerEntity *)[universe entityZero];

		[player setScript_target:self];
		[player scriptActions: death_actions forTarget: self];

		[death_actions removeAllObjects];
	}


	if ([roles isEqual:@"thargoid"])
		[self broadcastThargoidDestroyed];

	if (collision_radius > 49.9) // big!
	{
		// quick test of hyperring
		ParticleEntity *ring = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
		Vector ring_vel = [ring getVelocity];
		ring_vel.x *= 0.25;	ring_vel.y *= 0.25;	ring_vel.z *= 0.25;	// quarter velocity
		[ring setVelocity:ring_vel];
		[universe addEntity:ring];
		[ring release];
	}

	// several parts to the explosion:
	// 1. fast sparks
	fragment = [[ParticleEntity alloc] initFragburstSize: collision_radius FromPosition: xposition];
	[universe addEntity:fragment];
	[fragment release];
	// 2. slow clouds
	fragment = [[ParticleEntity alloc] initBurst2Size: collision_radius FromPosition: xposition];
	[universe addEntity:fragment];
	[fragment release];
	// 3. flash
	fragment = [[ParticleEntity alloc] initFlashSize: collision_radius FromPosition: xposition];
	[universe addEntity:fragment];
	[fragment release];

	// we need to throw out cargo at this point.
	NSArray *jetsam = nil;  // this will contain the stuff to get thrown out
	int cargo_chance = 10;
	if ([[name lowercaseString] rangeOfString:@"medical"].location != NSNotFound)
	{
		int cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[universe getContainersOfDrugs:cargo_to_go]];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
		cargo_flag = CARGO_FLAG_CANISTERS;
	}

	int cargo_to_go = max_cargo * cargo_chance / 100;
	while (cargo_to_go > 15)
		cargo_to_go = ranrot_rand() % cargo_to_go;
	cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
	switch (cargo_flag)
	{
		case	CARGO_FLAG_FULL_UNIFORM :
//			NSLog(@"DEBUG dropping uniform cargo (CARGO_FLAG_FULL_UNIFORM)");
			{
				NSString* commodity_name = (NSString*)[shipinfoDictionary objectForKey:@"cargo_carried"];
				jetsam = [universe getContainersOfCommodity:commodity_name :cargo_to_go];
			}
			break;

		case	CARGO_FLAG_FULL_PLENTIFUL :
//			NSLog(@"DEBUG dropping plentiful cargo (CARGO_FLAG_FULL_PLENTIFUL)");
			jetsam = [universe getContainersOfPlentifulGoods:cargo_to_go];
			break;

		case	CARGO_FLAG_PIRATE :
//			NSLog(@"DEBUG dropping pirated cargo (CARGO_FLAG_PIRATE)");
			cargo_to_go = likely_cargo;
			while (cargo_to_go > 15)
				cargo_to_go = ranrot_rand() % cargo_to_go;
			cargo_chance = 65;	// 35% chance of spoilage
			jetsam = [universe getContainersOfScarceGoods:cargo_to_go];
			break;

		case	CARGO_FLAG_FULL_SCARCE :
//			NSLog(@"DEBUG dropping scarce cargo (CARGO_FLAG_FULL_SCARCE)");
			jetsam = [universe getContainersOfScarceGoods:cargo_to_go];
			break;

		case	CARGO_FLAG_CANISTERS:
//			NSLog(@"DEBUG dropping ship's scooped cargo (CARGO_FLAG_CANISTERS)");
			jetsam = [NSArray arrayWithArray:cargo];   // what the ship is carrying
			[cargo removeAllObjects];   // dispense with it!
			break;
	}

	if (jetsam)
	{
		for (i = 0; i < [jetsam count]; i++)
		{
			if (ranrot_rand() % 100 < cargo_chance)  //  chance of any given piece of cargo surviving decompression
			{
				ShipEntity* container = [jetsam objectAtIndex:i];
				Vector  rpos = xposition;
				Vector	rrand = randomPositionInBoundingBox(boundingBox);
				rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
				rpos.x += (ranrot_rand() % 7) - 3;
				rpos.y += (ranrot_rand() % 7) - 3;
				rpos.z += (ranrot_rand() % 7) - 3;
				[container setPosition:rpos];
				v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
				v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
				v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
				[container setVelocity:v];
				quaternion_set_random(&q);
				[container setQRotation:q];
				[container setStatus:STATUS_IN_FLIGHT];
				[container setScanClass: CLASS_CARGO];
				[universe addEntity:container];
				[[container getAI] setState:@"GLOBAL"];
				//NSLog(@"Launched %@ %d with %@",[container name], [container universal_id], [universe describeCommodity:[container getCommodityType] amount:[container getCommodityAmount]]);
			}
		}
	}

	//
	//  Throw out rocks and alloys to be scooped up
	//
	if ([roles isEqual:@"asteroid"])
	{
		if ((being_mined)||(randf() < 0.20))
		{
			// if hit by a mining laser, break up into 2..6 boulders
//			int n_rocks = 2 + (ranrot_rand() % 5);
			int n_rocks = likely_cargo;
//			NSLog(@"DEBUG %@ %d Throwing %d boulders", name, universal_id, n_rocks);
//			NSLog(@"DEBUG At (%.1f, %.1f, %.1f)", xposition.x, xposition.y, xposition.z);
			for (i = 0; i < n_rocks; i++)
			{
				ShipEntity* rock = [universe getShipWithRole:@"boulder"];   // retain count = 1
				if (rock)
				{
					Vector  rpos = xposition;
					int  r_speed = 20.0 * [rock max_flight_speed];
					int cr = 3 * rock->collision_radius;
					rpos.x += (ranrot_rand() % cr) - cr/2;
					rpos.y += (ranrot_rand() % cr) - cr/2;
					rpos.z += (ranrot_rand() % cr) - cr/2;
					[rock setPosition:rpos];
	//				NSLog(@"DEBUG Spawned Boulder At (%.1f, %.1f, %.1f)", rpos.x, rpos.y, rpos.z);
					v.x = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
					v.y = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
					v.z = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
					[rock setVelocity:v];
					quaternion_set_random(&q);
					[rock setQRotation:q];
					[rock setStatus:STATUS_IN_FLIGHT];
					[rock setScanClass: CLASS_ROCK];
					[universe addEntity:rock];
					[[rock getAI] setState:@"GLOBAL"];
					[rock release];
				}
			}
		}
		[universe removeEntity:self];
		return; // don't do anything more
	}

	if ([roles isEqual:@"boulder"])
	{
		if ((being_mined)||(ranrot_rand() % 100 < 20))
		{
			// if hit by a mining laser, break up into 2..6 splinters
			int n_rocks = 2 + (ranrot_rand() % 5);
			//NSLog(@"Throwing %d splinters", n_rocks);
			for (i = 0; i < n_rocks; i++)
			{
				ShipEntity* rock = [universe getShipWithRole:@"splinter"];   // retain count = 1
				if (rock)
				{
					Vector  rpos = xposition;
					int  r_speed = 20.0 * [rock max_flight_speed];
					int cr = 3 * rock->collision_radius;
					rpos.x += (ranrot_rand() % cr) - cr/2;
					rpos.y += (ranrot_rand() % cr) - cr/2;
					rpos.z += (ranrot_rand() % cr) - cr/2;
					[rock setPosition:rpos];
					v.x = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
					v.y = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
					v.z = 0.1 *((ranrot_rand() % r_speed) - r_speed / 2);
					[rock setBounty: 0];
					[rock setVelocity:v];
					quaternion_set_random(&q);
					[rock setQRotation:q];
					[rock setStatus:STATUS_IN_FLIGHT];
					[rock setScanClass: CLASS_CARGO];
					[universe addEntity:rock];
					[[rock getAI] setState:@"GLOBAL"];
					[rock release];
				}
			}
		}
		[universe removeEntity:self];
		return; // don't do anything more
	}

	//NSLog(@"Throwing %d pieces of alloy", n_alloys);
	for (i = 0; i < n_alloys; i++)
	{
		ShipEntity* plate = [universe getShipWithRole:@"alloy"];   // retain count = 1
		if (plate)
		{
			Vector  rpos = xposition;
			Vector	rrand = randomPositionInBoundingBox(boundingBox);
			rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
			rpos.x += (ranrot_rand() % 7) - 3;
			rpos.y += (ranrot_rand() % 7) - 3;
			rpos.z += (ranrot_rand() % 7) - 3;
			[plate setPosition:rpos];
			v.x = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
			v.y = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
			v.z = 0.1 *((ranrot_rand() % speed_low) - speed_low / 2);
			[plate setVelocity:v];
			quaternion_set_random(&q);
			[plate setQRotation:q];
			[plate setScanClass: CLASS_CARGO];
			[plate setCommodity:9 andAmount:1];
			[universe addEntity:plate];
			[plate setStatus:STATUS_IN_FLIGHT];
			[[plate getAI] setState:@"GLOBAL"];
			[plate release];
		}
	}
	//
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity*		se = (Entity *)[sub_entities objectAtIndex:i];
			if (se->isShip)
			{
				Vector  origin = [(ShipEntity*)se absolutePositionForSubentity];
				[se setPosition:origin];	// is this what's messing thing up??
				[universe addEntity:se];
				[(ShipEntity *)se becomeExplosion];
			}
		}
		[sub_entities release]; // releases each subentity too!
		sub_entities = nil;
	}

	// momentum from explosions
	desired_range = collision_radius * 2.5;
	[self dealMomentumWithinDesiredRange: 0.125 * mass];

	//
	if (!isPlayer)
		[universe removeEntity:self];
}

- (void) becomeEnergyBlast
{
	ParticleEntity* blast = [[ParticleEntity alloc] initEnergyMineFromShip:self];
	[universe addEntity:blast];
	[blast setOwner: [self owner]];
	[blast release];
	[universe removeEntity:self];
}

Vector randomPositionInBoundingBox(BoundingBox bb)
{
	Vector result;
	result.x = bb.min.x + randf() * (bb.max.x - bb.min.x);
	result.y = bb.min.y + randf() * (bb.max.y - bb.min.y);
	result.z = bb.min.z + randf() * (bb.max.z - bb.min.z);
	return result;
}

- (Vector) positionOffsetForAlignment:(NSString*) align
{
	NSString* padAlign = [NSString stringWithFormat:@"%@---", align];
	Vector result = make_vector( 0.0f, 0.0f, 0.0f);
	switch ([padAlign characterAtIndex:0])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.x = 0.5 * (boundingBox.min.x + boundingBox.max.x);
			break;
		case (unichar)'M':
			result.x = boundingBox.max.x;
			break;
		case (unichar)'m':
			result.x = boundingBox.min.x;
			break;
	}
	switch ([padAlign characterAtIndex:1])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.y = 0.5 * (boundingBox.min.y + boundingBox.max.y);
			break;
		case (unichar)'M':
			result.y = boundingBox.max.y;
			break;
		case (unichar)'m':
			result.y = boundingBox.min.y;
			break;
	}
	switch ([padAlign characterAtIndex:2])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.z = 0.5 * (boundingBox.min.z + boundingBox.max.z);
			break;
		case (unichar)'M':
			result.z = boundingBox.max.z;
			break;
		case (unichar)'m':
			result.z = boundingBox.min.z;
			break;
	}
	return result;
}

Vector positionOffsetForShipInRotationToAlignment(ShipEntity* ship, Quaternion q, NSString* align)
{
	NSString* padAlign = [NSString stringWithFormat:@"%@---", align];
	Vector i = vector_right_from_quaternion(q);
	Vector j = vector_up_from_quaternion(q);
	Vector k = vector_forward_from_quaternion(q);
	BoundingBox arbb = [ship findBoundingBoxRelativeToPosition: make_vector(0,0,0) InVectors: i : j : k];
	Vector result = make_vector( 0.0f, 0.0f, 0.0f);
	switch ([padAlign characterAtIndex:0])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.x = 0.5 * (arbb.min.x + arbb.max.x);
			break;
		case (unichar)'M':
			result.x = arbb.max.x;
			break;
		case (unichar)'m':
			result.x = arbb.min.x;
			break;
	}
	switch ([padAlign characterAtIndex:1])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.y = 0.5 * (arbb.min.y + arbb.max.y);
			break;
		case (unichar)'M':
			result.y = arbb.max.y;
			break;
		case (unichar)'m':
			result.y = arbb.min.y;
			break;
	}
	switch ([padAlign characterAtIndex:2])
	{
		case (unichar)'c':
		case (unichar)'C':
			result.z = 0.5 * (arbb.min.z + arbb.max.z);
			break;
		case (unichar)'M':
			result.z = arbb.max.z;
			break;
		case (unichar)'m':
			result.z = arbb.min.z;
			break;
	}
	return result;
}

- (void) becomeLargeExplosion:(double) factor
{
	Vector xposition = position;
	ParticleEntity  *fragment;
	int n_cargo = (ranrot_rand() % (likely_cargo + 1));

	if (status == STATUS_DEAD)
		return;

	status = STATUS_DEAD;
	//scripting
	if ([death_actions count])
	{
		PlayerEntity* player = (PlayerEntity *)[universe entityZero];

		[player setScript_target:self];
		[player scriptActions: death_actions forTarget: self];

		[death_actions removeAllObjects];
	}

	// two parts to the explosion:
	// 1. fast sparks
	float how_many = factor;
	while (how_many > 0.5f)
	{
	//	fragment = [[ParticleEntity alloc] initFragburstFromPosition:xposition];
		fragment = [[ParticleEntity alloc] initFragburstSize: collision_radius FromPosition:xposition];
		[universe addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}
	// 2. slow clouds
	how_many = factor;
	while (how_many > 0.5f)
	{
		fragment = [[ParticleEntity alloc] initBurst2Size: collision_radius FromPosition:xposition];
		[universe addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}


	// we need to throw out cargo at this point.
	int cargo_chance = 10;
	if ([[name lowercaseString] rangeOfString:@"medical"].location != NSNotFound)
	{
		int cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		[self setCargo:[universe getContainersOfDrugs:cargo_to_go]];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
		cargo_flag = CARGO_FLAG_CANISTERS;
	}
	if (cargo_flag == CARGO_FLAG_FULL_PLENTIFUL)
	{
		int cargo_to_go = max_cargo / 10;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		//NSLog(@"explosion in %@ %d will launch %d pieces of cargo (max_cargo = %d)", name, universal_id, cargo_to_go, max_cargo);
		[self setCargo:[universe getContainersOfPlentifulGoods:cargo_to_go]];
		cargo_chance = 100;
	}
	if (cargo_flag == CARGO_FLAG_FULL_SCARCE)
	{
		int cargo_to_go = max_cargo / 10;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		//NSLog(@"explosion in %@ %d will launch %d pieces of cargo (max_cargo = %d)", name, universal_id, cargo_to_go, max_cargo);
		[self setCargo:[universe getContainersOfScarceGoods:cargo_to_go]];
		cargo_chance = 100;
	}
	while ([cargo count] > 0)
	{
		if (ranrot_rand() % 100 < cargo_chance)  //  10% chance of any given piece of cargo surviving decompression
		{
			ShipEntity* container = [[cargo objectAtIndex:0] retain];
			Vector  rpos = xposition;
			Vector	rrand = randomPositionInBoundingBox(boundingBox);
			rpos.x += rrand.x;	rpos.y += rrand.y;	rpos.z += rrand.z;
			rpos.x += (ranrot_rand() % 7) - 3;
			rpos.y += (ranrot_rand() % 7) - 3;
			rpos.z += (ranrot_rand() % 7) - 3;
			[container setPosition:rpos];
			[container setScanClass: CLASS_CARGO];
			[universe addEntity:container];
			[[container getAI] setState:@"GLOBAL"];
			[container setStatus:STATUS_IN_FLIGHT];
			[container release];
			if (n_cargo > 0)
				n_cargo--;  // count down extra cargo
		}
		[cargo removeObjectAtIndex:0];
	}
	//

	if (!isPlayer)
		[universe removeEntity:self];
}

- (void) collectBountyFor:(ShipEntity *)other
{
	if ([roles isEqual:@"pirate"])
		bounty += [other getBounty];
}

/*-----------------------------------------

	AI piloting methods

-----------------------------------------*/

- (void) setFound_target:(Entity *) targetEntity
{
	if (targetEntity)
		found_target = [targetEntity universal_id];
}

- (void) setPrimaryAggressor:(Entity *) targetEntity
{
	if (targetEntity)
		primaryAggressor = [targetEntity universal_id];
}

- (void) addTarget:(Entity *) targetEntity
{
	if (targetEntity)
		primaryTarget = [targetEntity universal_id];
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity* se = [sub_entities objectAtIndex:i];
			if (se->isShip)
				[(ShipEntity *)se addTarget:targetEntity];
		}
	}
}

- (void) removeTarget:(Entity *) targetEntity
{
	if (primaryTarget != NO_TARGET)
		[shipAI reactToMessage:@"TARGET_LOST"];
	primaryTarget = NO_TARGET;
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
		{
			Entity* se = [sub_entities objectAtIndex:i];
			if (se->isShip)
				[(ShipEntity *)se removeTarget:targetEntity];
		}
	}
}

- (Entity *) getPrimaryTarget
{
	return [universe entityForUniversalID:primaryTarget];
}

- (int) getPrimaryTargetID
{
	return primaryTarget;
}

- (int) behaviour
{
	return behaviour;
}

- (void) setBehaviour:(int) cond
{
	if (cond !=behaviour)
		frustration = 0.0;	// change is a GOOD thing
	behaviour = cond;
}

- (Vector) destination
{
	return destination;
}

- (Vector) one_km_six
{
	Vector six = position;
	six.x -= 1000 * v_forward.x;	six.y -= 1000 * v_forward.y;	six.z -= 1000 * v_forward.z;
	return six;
}

- (Vector) distance_six: (GLfloat) dist
{
	Vector six = position;
	six.x -= dist * v_forward.x;	six.y -= dist * v_forward.y;	six.z -= dist * v_forward.z;
	return six;
}

- (Vector) distance_twelve: (GLfloat) dist
{
	Vector twelve = position;
	twelve.x += dist * v_up.x;	twelve.y += dist * v_up.y;	twelve.z += dist * v_up.z;
	return twelve;
}

- (double) ballTrackTarget:(double) delta_t
{
	Vector vector_to_target;
	Vector axis_to_track_by;
	Vector my_position = position;  // position relative to parent
	Vector my_aim = vector_forward_from_quaternion(q_rotation);
	Vector my_ref = reference;
	double aim_cos, ref_cos;
	//
	Entity* targent = [self getPrimaryTarget];
	//
	//
	//NSLog(@"DEBUG ball_tracking (before rotation) my_aim (%.2f,%.2f,%.2f) my_ref (%.2f,%.2f,%.2f)", my_aim.x, my_aim.y, my_aim.z,  my_ref.x, my_ref.y, my_ref.z);
	Entity*		last = nil;
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father drawRotationMatrix];
	while ((father)&&(father != last))
	{
		mult_vector_gl_matrix(&my_position, r_mat);
		mult_vector_gl_matrix(&my_ref, r_mat);
		Vector pos = father->position;
		my_position.x += pos.x;	my_position.y += pos.y;	my_position.z += pos.z;
		last = father;
		father = [father owner];
		r_mat = [father drawRotationMatrix];
	}

	if (targent)
	{
		vector_to_target = targent->position;
		//
		vector_to_target.x -= my_position.x;	vector_to_target.y -= my_position.y;	vector_to_target.z -= my_position.z;
		if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
			vector_to_target = unit_vector(&vector_to_target);
		else
			vector_to_target.z = 1.0;
		//
		// do the tracking!
		aim_cos = dot_product(vector_to_target, my_aim);
		ref_cos = dot_product(vector_to_target, my_ref);
	}
	else
	{
		aim_cos = 0.0;
		ref_cos = -1.0;
	}
	//
	//NSLog(@"DEBUG ball_tracking vtt (%.2f,%.2f,%.2f)", vector_to_target.x, vector_to_target.y, vector_to_target.z);
	//NSLog(@"DEBUG ball_tracking target %@ aim_cos = %.3f ref_cos = %.3f", [(ShipEntity *)targent name], aim_cos, ref_cos);

	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		aim_cos = 0.0;
		axis_to_track_by = cross_product(my_ref, my_aim);	//	return to center
	}

	quaternion_rotate_about_axis( &q_rotation, axis_to_track_by, thrust * delta_t);

	quaternion_normalise(&q_rotation);
	quaternion_into_gl_matrix(q_rotation, rotMatrix);

	status = STATUS_ACTIVE;

	return aim_cos;
}

- (void) trackOntoTarget:(double) delta_t withDForward: (GLfloat) dp
{
	Vector vector_to_target;
	Quaternion q_minarc;
	//
	Entity* targent = [self getPrimaryTarget];
	//
	if (!targent)
		return;

	vector_to_target = targent->position;
	vector_to_target.x -= position.x;	vector_to_target.y -= position.y;	vector_to_target.z -= position.z;
	//
	GLfloat range2 =		magnitude2( vector_to_target);
	GLfloat	targetRadius =	0.75 * targent->actual_radius;
	GLfloat	max_cos =		sqrt(1 - targetRadius*targetRadius/range2);
	//
	if (dp > max_cos)
		return;	// ON TARGET!
	//
	if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
		vector_to_target = unit_vector(&vector_to_target);
	else
		vector_to_target.z = 1.0;
	//
	q_minarc = quaternion_rotation_between( v_forward, vector_to_target);
	//
	q_rotation = quaternion_multiply( q_minarc, q_rotation);
    quaternion_normalise(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	//
	flight_roll = 0.0;
	flight_pitch = 0.0;
}

- (double) ballTrackLeadingTarget:(double) delta_t
{
	Vector vector_to_target;
	Vector axis_to_track_by;
	Vector my_position = position;  // position relative to parent
	Vector my_aim = vector_forward_from_quaternion(q_rotation);
	Vector my_ref = reference;
	double aim_cos, ref_cos;
	//
	Entity* targent = [self getPrimaryTarget];
	//
	Vector leading = [targent getVelocity];
//	leading.x *= lead_t;	leading.y *= lead_t;	leading.z *= lead_t;
	//
	//
	//NSLog(@"DEBUG ball_tracking (before rotation) my_aim (%.2f,%.2f,%.2f) my_ref (%.2f,%.2f,%.2f)", my_aim.x, my_aim.y, my_aim.z,  my_ref.x, my_ref.y, my_ref.z);
	Entity*		last = nil;
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father drawRotationMatrix];
	while ((father)&&(father != last))
	{
		mult_vector_gl_matrix(&my_position, r_mat);
		mult_vector_gl_matrix(&my_ref, r_mat);
		Vector pos = father->position;
		my_position.x += pos.x;	my_position.y += pos.y;	my_position.z += pos.z;
		last = father;
		father = [father owner];
		r_mat = [father drawRotationMatrix];
	}

	if (targent)
	{
		vector_to_target = targent->position;
		//
		vector_to_target.x -= my_position.x;	vector_to_target.y -= my_position.y;	vector_to_target.z -= my_position.z;
		//
		float lead = sqrt(magnitude2(vector_to_target)) / TURRET_SHOT_SPEED;
		//
		vector_to_target.x += lead * leading.x;	vector_to_target.y += lead * leading.y;	vector_to_target.z += lead * leading.z;
		if (vector_to_target.x||vector_to_target.y||vector_to_target.z)
			vector_to_target = unit_vector(&vector_to_target);
		else
			vector_to_target.z = 1.0;
		//
		// do the tracking!
		aim_cos = dot_product(vector_to_target, my_aim);
		ref_cos = dot_product(vector_to_target, my_ref);
	}
	else
	{
		aim_cos = 0.0;
		ref_cos = -1.0;
	}
	//
	//NSLog(@"DEBUG ball_tracking vtt (%.2f,%.2f,%.2f)", vector_to_target.x, vector_to_target.y, vector_to_target.z);
	//NSLog(@"DEBUG ball_tracking target %@ aim_cos = %.3f ref_cos = %.3f", [(ShipEntity *)targent name], aim_cos, ref_cos);

	if (ref_cos > TURRET_MINIMUM_COS)  // target is forward of self
	{
		axis_to_track_by = cross_product(vector_to_target, my_aim);
	}
	else
	{
		aim_cos = 0.0;
		axis_to_track_by = cross_product(my_ref, my_aim);	//	return to center
	}

	quaternion_rotate_about_axis( &q_rotation, axis_to_track_by, thrust * delta_t);

	quaternion_normalise(&q_rotation);
	quaternion_into_gl_matrix(q_rotation, rotMatrix);

	status = STATUS_ACTIVE;

	return aim_cos;
}


- (double) trackPrimaryTarget:(double) delta_t :(BOOL) retreat
{
	Entity*	target = [self getPrimaryTarget];

	if (!target)   // leave now!
	{
		[shipAI message:@"TARGET_LOST"];
		return 0.0;
	}

	if (scan_class == CLASS_MISSILE)
		return [self missileTrackPrimaryTarget: delta_t];

	GLfloat  d_forward, d_up, d_right;

	Vector  relativePosition = target->position;
	relativePosition.x -= position.x;
	relativePosition.y -= position.y;
	relativePosition.z -= position.z;

	double	range2 = magnitude2(relativePosition);

	if (range2 > SCANNER_MAX_RANGE2)
	{
		[shipAI message:@"TARGET_LOST"];
		return 0.0;
	}

	//jink if retreating
	if (retreat && (range2 > 250000.0))	// don't jink if closer than 500m - just RUN
	{
		Vector vx, vy, vz;
		if (target->isShip)
		{
			ShipEntity* targetShip = (ShipEntity*)target;
			vx = targetShip->v_right;
			vy = targetShip->v_up;
			vz = targetShip->v_forward;
		}
		else
		{
			Quaternion q = target->q_rotation;
			vx = vector_right_from_quaternion(q);
			vy = vector_up_from_quaternion(q);
			vz = vector_forward_from_quaternion(q);
		}
		relativePosition.x += jink.x * vx.x + jink.y * vy.x + jink.z * vz.x;
		relativePosition.y += jink.x * vx.y + jink.y * vy.y + jink.z * vz.y;
		relativePosition.z += jink.x * vx.z + jink.y * vy.z + jink.z * vz.z;
	}

	if (relativePosition.x||relativePosition.y||relativePosition.z)
		relativePosition = unit_vector(&relativePosition);
	else
		relativePosition.z = 1.0;

	double	targetRadius = 0.75 * target->actual_radius;

	double	max_cos = sqrt(1 - targetRadius*targetRadius/range2);

	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double reverse = (retreat)? -1.0: 1.0;

	double min_d = 0.004;

	d_right		=   dot_product(relativePosition, v_right);
	d_up		=   dot_product(relativePosition, v_up);
	d_forward   =   dot_product(relativePosition, v_forward);	// == cos of angle between v_forward and vector to target

	if (d_forward * reverse > max_cos)	// on_target!
		return d_forward;

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;


	if ((reverse * d_forward < -0.5) && !pitching_over) // we're going the wrong way!
		pitching_over = YES;

	if (pitching_over)
	{
		if (reverse * d_up > 0) // pitch up
			stick_pitch = -max_flight_pitch;
		else
			stick_pitch = max_flight_pitch;
		pitching_over = (reverse * d_forward < 0.707);
	}

	// treat missiles specially
	if ((scan_class == CLASS_MISSILE) && (d_forward > cos( delta_t * max_flight_pitch)))
	{
		NSLog(@"missile %@ in tracking mode", self);
		[self trackOntoTarget: delta_t withDForward: d_forward];
		return d_forward;
	}

	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{
		if (d_forward < -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;
		}
		if (d_up < -min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt( fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;
		}
	}

	// end rule-of-thumb manoeuvres

	// apply stick movement limits
	if (flight_roll < stick_roll - rate1)
		stick_roll = flight_roll + rate1;
	if (flight_roll > stick_roll + rate1)
		stick_roll = flight_roll - rate1;
	if (flight_pitch < stick_pitch - rate2)
		stick_pitch = flight_pitch + rate2;
	if (flight_pitch > stick_pitch + rate2)
		stick_pitch = flight_pitch - rate2;

	// apply damping
	double damproll = (flight_speed > 2.0)? damping : 2.0 * damping;	// double damping if we're going very slowly
	if (flight_roll < 0)
		flight_roll += (flight_roll < -damproll)? damproll : -flight_roll;
	if (flight_roll > 0)
		flight_roll -= (flight_roll > damproll)? damproll : flight_roll;
	if (flight_pitch < 0)
		flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
	if (flight_pitch > 0)
		flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;

	// apply stick to attitude control
	flight_roll = stick_roll;
	flight_pitch = stick_pitch;

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flight_roll)&&(!flight_pitch))	// no correction
		return 1.0;

	return d_forward;
}

- (double) missileTrackPrimaryTarget:(double) delta_t
{
	Vector  relativePosition;
	GLfloat  d_forward, d_up, d_right, range2;
	Entity  *target = [self getPrimaryTarget];

	if (!target)   // leave now!
		return 0.0;

	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double tolerance1 = pitch_tolerance;

	relativePosition = target->position;
	relativePosition.x -= position.x;
	relativePosition.y -= position.y;
	relativePosition.z -= position.z;

	range2 = magnitude2(relativePosition);

	if (relativePosition.x||relativePosition.y||relativePosition.z)
		relativePosition = unit_vector(&relativePosition);
	else
		relativePosition.z = 1.0;

	d_right		=   dot_product(relativePosition, v_right);		// = cosine of angle between angle to target and v_right
	d_up		=   dot_product(relativePosition, v_up);		// = cosine of angle between angle to target and v_up
	d_forward   =   dot_product(relativePosition, v_forward);	// = cosine of angle between angle to target and v_forward

	// begin rule-of-thumb manoeuvres

	stick_roll = 0.0;

	if (pitching_over)
		pitching_over = (stick_pitch != 0.0);

	if ((d_forward < -tolerance1) && (!pitching_over))
	{
		pitching_over = YES;
		if (d_up >= 0)
			stick_pitch = -max_flight_pitch;
		if (d_up < 0)
			stick_pitch = max_flight_pitch;
	}

	if (pitching_over)
	{
		pitching_over = (d_forward < 0.5);
	}
	else
	{
		stick_pitch = -max_flight_pitch * d_up;
		stick_roll = -max_flight_roll * d_right;
	}

	// end rule-of-thumb manoeuvres

	// apply damping
	if (flight_roll < 0)
		flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
	if (flight_roll > 0)
		flight_roll -= (flight_roll > damping) ? damping : flight_roll;
	if (flight_pitch < 0)
		flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
	if (flight_pitch > 0)
		flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;

	// apply stick movement limits
	if (flight_roll + rate1 < stick_roll)
		stick_roll = flight_roll + rate1;
	if (flight_roll - rate1 > stick_roll)
		stick_roll = flight_roll - rate1;
	if (flight_pitch + rate2 < stick_pitch)
		stick_pitch = flight_pitch + rate2;
	if (flight_pitch - rate2 > stick_pitch)
		stick_pitch = flight_pitch - rate2;

	// apply stick to attitude
	flight_roll = stick_roll;
	flight_pitch = stick_pitch;

	//
	//  return target confidence 0.0 .. 1.0
	//
	if (d_forward < 0.0)
		return 0.0;
	return d_forward;
}

- (double) trackDestination:(double) delta_t :(BOOL) retreat
{
	Vector  relativePosition;
	GLfloat  d_forward, d_up, d_right;

	BOOL	we_are_docking = (nil != dockingInstructions);

	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;

	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;

	double reverse = 1.0;

	double min_d = 0.004;
	double max_cos = 0.85;

	if (retreat)
		reverse = -reverse;

	if (isPlayer)
		reverse = -reverse;

	relativePosition = destination;
	relativePosition.x -= position.x;
	relativePosition.y -= position.y;
	relativePosition.z -= position.z;

	double range2 = magnitude2(relativePosition);

	max_cos = sqrt(1 - desired_range*desired_range/range2);

	if (relativePosition.x||relativePosition.y||relativePosition.z)
		relativePosition = unit_vector(&relativePosition);
	else
		relativePosition.z = 1.0;

	d_right		=   dot_product(relativePosition, v_right);
	d_up		=   dot_product(relativePosition, v_up);
	d_forward   =   dot_product(relativePosition, v_forward);	// == cos of angle between v_forward and vector to target

	// begin rule-of-thumb manoeuvres
	stick_pitch = 0.0;
	stick_roll = 0.0;

//	if (isPlayer)
//		NSLog(@"DEBUG trackDestination:: max_cos %.4f, d_forward %.4f, we_are_docking %@", max_cos, d_forward, (we_are_docking)? @":YES:" : @":NO:");

	// check if we are flying toward the destination..
	if ((d_forward < max_cos)||(retreat))	// not on course so we must adjust controls..
	{

		if (d_forward < -max_cos)  // hack to avoid just flying away from the destination
		{
			d_up = min_d * 2.0;
		}

		if (d_up > min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor;  //roll_roll * reverse;
			if (d_right < -min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor; //roll_roll * reverse;
		}
		if (d_up < -min_d)
		{
			int factor = sqrt( fabs(d_right) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_right > min_d)
				stick_roll = + max_flight_roll * reverse * 0.125 * factor;  //roll_roll * reverse;
			if (d_right < -min_d)
				stick_roll = - max_flight_roll * reverse * 0.125 * factor; //roll_roll * reverse;
		}

		if (stick_roll == 0.0)
		{
			int factor = sqrt( fabs(d_up) / fabs(min_d));
			if (factor > 8)
				factor = 8;
			if (d_up > min_d)
				stick_pitch = - max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
			if (d_up < -min_d)
				stick_pitch = + max_flight_pitch * reverse * 0.125 * factor;  //pitch_pitch * reverse;
		}
	}

	if (we_are_docking && docking_match_rotation && (d_forward > max_cos))
	{
		/* we are docking and need to consider the rotation/orientation of the docking port */

//		NSLog(@"DEBUG DOCKING MATCH ROTATION %@ targetStation = %d %@ primaryTarget = %d %@",
//			self, targetStation, [universe entityForUniversalID:targetStation], primaryTarget, [universe entityForUniversalID:primaryTarget]);
		StationEntity* station_for_docking = (StationEntity*)[universe entityForUniversalID:targetStation];

		if ((station_for_docking)&&(station_for_docking->isStation))
		{
			Vector up_vec = [station_for_docking portUpVector];
			double cosTheta = dot_product(up_vec, v_up);	// == cos of angle between up vectors
			double sinTheta = dot_product(up_vec, v_right);

			double station_roll = [station_for_docking flight_roll];

			if (!isPlayer)
			{
				station_roll = -station_roll;	// make necessary corrections for a different viewpoint
				sinTheta = -sinTheta;
			}

			if (cosTheta < 0)
			{
				cosTheta = -cosTheta;
				sinTheta = -sinTheta;
			}

			if (sinTheta > 0.0)
			{
				// increase roll rate
				stick_roll = cosTheta * cosTheta * station_roll + sinTheta * sinTheta * max_flight_roll;
			}
			else
			{
				// decrease roll rate
				stick_roll = cosTheta * cosTheta * station_roll - sinTheta * sinTheta * max_flight_roll;
			}

	//		NSLog(@"DEBUG %@ docking with %@ -- matching rotation .. docking cosTheta %.3f sinTheta %.3f station_roll %.3f stick_roll %.3f",
	//			self, [self getPrimaryTarget], cosTheta, sinTheta, station_roll, stick_roll);
		}
	}

	// end rule-of-thumb manoeuvres

	// apply stick movement limits
	if (flight_roll < stick_roll - rate1)
		stick_roll = flight_roll + rate1;
	if (flight_roll > stick_roll + rate1)
		stick_roll = flight_roll - rate1;
	if (flight_pitch < stick_pitch - rate2)
		stick_pitch = flight_pitch + rate2;
	if (flight_pitch > stick_pitch + rate2)
		stick_pitch = flight_pitch - rate2;

	// apply damping
	if ((!docking_match_rotation)||(!we_are_docking))
	{
		double damproll = (flight_speed > 2.0)? damping : 2.0 * damping;	// double damping if we're going very slowly
		if (flight_roll < 0)
			flight_roll += (flight_roll < -damproll)? damproll : -flight_roll;
		if (flight_roll > 0)
			flight_roll -= (flight_roll > damproll)? damproll : flight_roll;
	}
	if (flight_pitch < 0)
		flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
	if (flight_pitch > 0)
		flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;

	// apply stick to attitude control
	flight_roll = stick_roll;
	flight_pitch = stick_pitch;

	if (retreat)
		d_forward *= d_forward;	// make positive AND decrease granularity

	if (d_forward < 0.0)
		return 0.0;

	if ((!flight_roll)&&(!flight_pitch))	// no correction
		return 1.0;

	return d_forward;
}

- (double) rangeToDestination
{
	double dist;
	Vector delta = destination;
	delta.x -= position.x;
	delta.y -= position.y;
	delta.z -= position.z;
	dist = sqrt(delta.x*delta.x + delta.y*delta.y + delta.z*delta.z);
	return dist;
}

- (double) rangeToPrimaryTarget
{
	double dist;
	Vector delta;
	Entity  *target = [self getPrimaryTarget];
	if (target == nil)   // leave now!
		return 0.0;
	delta = target->position;
	delta.x -= position.x;
	delta.y -= position.y;
	delta.z -= position.z;
	dist = sqrt(delta.x*delta.x + delta.y*delta.y + delta.z*delta.z);
	dist -= target->collision_radius;
	dist -= collision_radius;
	return dist;
}

- (BOOL) onTarget:(BOOL) fwd_weapon
{
	GLfloat d2, radius, dq, astq;
	Vector rel_pos, urp;
	int weapon_type = (fwd_weapon)? forward_weapon_type : aft_weapon_type;
	if (weapon_type == WEAPON_THARGOID_LASER)
		return (randf() < 0.05);	// one in twenty shots on target
	Entity  *target = [self getPrimaryTarget];
	if (target == nil)   // leave now!
		return NO;
	if (target->status == STATUS_DEAD)
		return NO;
	if (isSunlit && (target->isSunlit == NO) && (randf() < 0.75))
		return NO;	// 3/4 of the time you can't see from a lit place into a darker place
	radius = target->collision_radius;
	rel_pos = target->position;
	rel_pos.x -= position.x;
	rel_pos.y -= position.y;
	rel_pos.z -= position.z;
	d2 = magnitude2(rel_pos);
	if (d2)
		urp = unit_vector(&rel_pos);
	else
		urp = make_vector( 0, 0, 1);
	dq = dot_product(urp, v_forward);				// cosine of angle between v_forward and unit relative position
	if (((fwd_weapon)&&(dq < 0.0)) || ((!fwd_weapon)&&(dq > 0.0)))
		return NO;

	astq = sqrt(1.0 - radius * radius / d2);	// cosine of half angle subtended by target

	return (fabs(dq) >= astq);
}

- (BOOL) fireMainWeapon:(double) range
{
	//
	// set the values for the forward weapon
	//
	[self set_weapon_data_from_type:forward_weapon_type];
	//
	if (shot_time < weapon_recharge_rate)
		return NO;
	int accuracy = 1;
	if ([shipinfoDictionary objectForKey:@"accuracy"])
		accuracy = [(NSNumber *)[shipinfoDictionary objectForKey:@"accuracy"] intValue];
	if (accuracy < 1)
		accuracy = 1;
	if (range > randf() * weapon_range * accuracy)
		return NO;
	if (range > weapon_range)
		return NO;
	if (![self onTarget:YES])
		return NO;
	//
	BOOL fired = NO;
	switch (forward_weapon_type)
	{
		case WEAPON_PLASMA_CANNON :
			[self firePlasmaShot:weapon_offset_x:1500.0:[OOColor yellowColor]];
			[self firePlasmaShot:weapon_offset_x:1500.0:[OOColor yellowColor]];
			fired = YES;
			break;

		case WEAPON_PULSE_LASER :
		case WEAPON_BEAM_LASER :
		case WEAPON_MINING_LASER :
		case WEAPON_MILITARY_LASER :
			[self fireLaserShotInDirection: VIEW_FORWARD];
			fired = YES;
			break;

		case WEAPON_THARGOID_LASER :
			[self fireDirectLaserShot];
			fired = YES;
			break;

	}

	//can we fire lasers from our subentities?
	int n_subs = [sub_entities count];
	if (n_subs)
	{
		int i = 0;
		for (i = 0; i < n_subs; i++)
		{
			ShipEntity* subent = (ShipEntity*)[sub_entities objectAtIndex:i];
			if ((subent)&&(subent->isShip))
				fired |= [subent fireSubentityLaserShot: range];
		}
	}

	return fired;
}

- (BOOL) fireAftWeapon:(double) range
{
	BOOL result = YES;
	//
	// save the existing weapon values
	//
	double weapon_energy1 = weapon_energy;
	double weapon_recharge_rate1 = weapon_recharge_rate;
	double weapon_range1 = weapon_range;
	//
	// set new values from aft_weapon_type
	//
	[self set_weapon_data_from_type:aft_weapon_type];
	//
	//

	//NSLog(@"DEBUG %@ should fire aft weapon",name);

	if (shot_time < weapon_recharge_rate)
		return NO;
	if (![self onTarget:NO])
		return NO;
	if (range > randf() * weapon_range)
		return NO;

	//NSLog(@"DEBUG %@ firing aft weapon",name);

	if (result)
	{
		switch (aft_weapon_type)
		{
			case WEAPON_PULSE_LASER :
			case WEAPON_BEAM_LASER :
			case WEAPON_MINING_LASER :
			case WEAPON_MILITARY_LASER :
				[self fireLaserShotInDirection:VIEW_AFT];
				break;
			case WEAPON_THARGOID_LASER :
				[self fireDirectLaserShot];
				return YES;
				break;

		}
	}
	//
	// restore previous values
	//
	weapon_energy = weapon_energy1;
	weapon_recharge_rate = weapon_recharge_rate1;
	weapon_range = weapon_range1;
	//
	return result;
}

- (BOOL) fireTurretCannon:(double) range
{
	if (shot_time < weapon_recharge_rate)
		return NO;
	if (range > 5000)
		return NO;

	ParticleEntity *shot;
	Vector  origin = position;
	Entity*		last = nil;
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father drawRotationMatrix];
	Vector		vel = vector_forward_from_quaternion(q_rotation);
	while ((father)&&(father != last))
	{
		mult_vector_gl_matrix(&origin, r_mat);
		Vector pos = father->position;
		origin.x += pos.x;	origin.y += pos.y;	origin.z += pos.z;
		last = father;
		father = [father owner];
		r_mat = [father drawRotationMatrix];
	}
	double  start = collision_radius + 0.5;
	double  speed = TURRET_SHOT_SPEED;
	OOColor* color = laser_color;

	origin.x += vel.x * start;
	origin.y += vel.y * start;
	origin.z += vel.z * start;

	vel.x *= speed;
	vel.y *= speed;
	vel.z *= speed;

	shot = [[ParticleEntity alloc] init];	// alloc retains!
	[shot setPosition:origin]; // directly ahead
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	[shot setDuration: 3.0];
	[shot setCollisionRadius: 2.0];
	[shot setEnergy: weapon_energy];
	[shot setParticleType: PARTICLE_SHOT_PLASMA];
	[shot setColor:color];
	[shot setSize:NSMakeSize(12,12)];
	[universe addEntity:shot];

	[shot setOwner:[self owner]];	// has to be done AFTER adding shot to the universe

	[shot release]; //release

	shot_time = 0.0;
	return YES;
}

- (void) setLaserColor:(OOColor *) color
{
	if (color)
	{
		[laser_color release];
		laser_color = [color retain];
	}
}


- (BOOL) fireSubentityLaserShot: (double) range
{
	ParticleEntity  *shot;
	int				direction = VIEW_FORWARD;
	GLfloat			hit_at_range;
	target_laser_hit = NO_TARGET;

	if (forward_weapon_type == WEAPON_NONE)
		return NO;
	[self set_weapon_data_from_type:forward_weapon_type];

	ShipEntity* parent = (ShipEntity*)[self owner];

	if (shot_time < weapon_recharge_rate)
		return NO;

	if (range > weapon_range)
		return NO;

	hit_at_range = weapon_range;
	target_laser_hit = [universe getFirstEntityHitByLaserFromEntity:self inView:direction offset: make_vector(0,0,0) rangeFound: &hit_at_range];

//	NSLog(@"DEBUG target hit by SubEntityLaserShot: %d %@", target_laser_hit, [universe entityForUniversalID:target_laser_hit]);

	shot = [[ParticleEntity alloc] initLaserFromSubentity:self view:direction];	// alloc retains!
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	if (target_laser_hit != NO_TARGET)
	{
		Entity *victim = [universe entityForUniversalID:target_laser_hit];
		if (victim)
		{
			Vector p0 = shot->position;
			Vector p1 = victim->position;
			if (victim->isShip)
			{
				ShipEntity* ship_hit = ((ShipEntity*)victim);
				ShipEntity* subent = ship_hit->subentity_taking_damage;
				if ((subent) && [ship_hit->sub_entities containsObject:subent])
				{
					if (ship_hit->isFrangible)
					{
						p1 = [subent absolutePositionForSubentity];
						victim = subent;
						// do 1% bleed-through damage...
						[ship_hit takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf:self];
					}
				}
			}
			//
			double dist2 = distance2( p0, p1);
			if ((victim->isShip)&&(dist2 < weapon_range*weapon_range))
			{
				[(ShipEntity *)victim takeEnergyDamage:weapon_energy from:self becauseOf:parent];	// a very palpable hit
//				[shot setCollisionRadius:sqrt(dist2)];	// so it's drawn to the right size

				// calculate where to draw flash
//				double cr = shot->collision_radius - victim->collision_radius;
				double cr = hit_at_range;
				[shot setCollisionRadius: cr];
				Vector vd = vector_forward_from_quaternion(shot->q_rotation);
				Vector p0 = shot->position;
				p0.x += vd.x * cr;	p0.y += vd.y * cr;	p0.z += vd.z * cr;
				ParticleEntity* laserFlash = [[ParticleEntity alloc] initFlashSize:1.0 FromPosition: p0 Color:laser_color];
				[laserFlash setVelocity:[victim getVelocity]];
				[universe addEntity:laserFlash];
				[laserFlash release];
			}
		}
	}
	[universe addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	return YES;
}

- (BOOL) fireDirectLaserShot
{
//	NSLog(@"DEBUG %@ %d laser fired direct shot on %@ %d", name, universal_id, [(ShipEntity*)[self getPrimaryTarget] name], primaryTarget);

	GLfloat			hit_at_range;
	Entity*	my_target = [self getPrimaryTarget];
	if (!my_target)
		return NO;
	ParticleEntity*	shot;
	double			range_limit2 = weapon_range*weapon_range;
	Vector			r_pos = my_target->position;
	r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
	if (r_pos.x||r_pos.y||r_pos.z)
		r_pos = unit_vector(&r_pos);
	else
		r_pos.z = 1.0;

//	target_laser_hit = primaryTarget;

	Quaternion		q_laser = quaternion_rotation_between(r_pos, make_vector(0.0f,0.0f,1.0f));
	q_laser.x += 0.01 * (randf() - 0.5);	// randomise aim a little (+/- 0.005)
	q_laser.y += 0.01 * (randf() - 0.5);
	q_laser.z += 0.01 * (randf() - 0.5);
	quaternion_normalise(&q_laser);

	Quaternion q_save = q_rotation;	// save rotation
	q_rotation = q_laser;			// face in direction of laser
	target_laser_hit = [universe getFirstEntityHitByLaserFromEntity:self inView:VIEW_FORWARD offset: make_vector(0,0,0) rangeFound: &hit_at_range];
	q_rotation = q_save;			// restore rotation

	Vector  vel = make_vector( v_forward.x * flight_speed, v_forward.y * flight_speed, v_forward.z * flight_speed);

	// do special effects laser line
	shot = [[ParticleEntity alloc] initLaserFromShip:self view:VIEW_FORWARD];	// alloc retains!
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setPosition: position];
	[shot setQRotation: q_laser];
	[shot setVelocity: vel];
	if (target_laser_hit != NO_TARGET)
	{
		Entity *victim = [universe entityForUniversalID:target_laser_hit];

		if ((victim) && (victim->isShip))
		{
			ShipEntity* parent = (ShipEntity*)[victim owner];
			if ((parent) && (parent != victim) && [parent->sub_entities containsObject:victim])
			{
				if (parent->isFrangible)
				{
//					NSLog(@"DEBUG Direct Laser hit on subentity %@ of frangible entity %@", victim, parent);
				}
				else
				{
//					NSLog(@"DEBUG Direct Laser hit on subentity %@ of NON-frangible entity %@", victim, parent);
					victim = parent;
				}
			}
		}

		if (victim)
		{
			Vector p0 = shot->position;
			Vector p1 = victim->position;
			p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
			double dist2 = magnitude2(p1);
			if ((victim->isShip)&&(dist2 < range_limit2))
			{
				[(ShipEntity *)victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit
//				[shot setCollisionRadius:sqrt(dist2)];

				// calculate where to draw flash
//				double cr = shot->collision_radius - victim->collision_radius;
				double cr = hit_at_range;
				[shot setCollisionRadius: cr];
				Vector vd = vector_forward_from_quaternion(shot->q_rotation);
				Vector p0 = shot->position;
				p0.x += vd.x * cr;	p0.y += vd.y * cr;	p0.z += vd.z * cr;
				ParticleEntity* laserFlash = [[ParticleEntity alloc] initFlashSize:1.0 FromPosition: p0 Color:laser_color];
				[laserFlash setVelocity:[victim getVelocity]];
				[universe addEntity:laserFlash];
				[laserFlash release];
			}
		}
	}
	[universe addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	// random laser over-heating for AI ships
	if ((!isPlayer)&&((ranrot_rand() & 255) < weapon_energy)&&(![self isMining]))
		shot_time -= (randf() * weapon_energy);

	return YES;
}

- (BOOL) fireLaserShotInDirection: (int) direction
{
	ParticleEntity  *shot;
	double			range_limit2 = weapon_range*weapon_range;
	GLfloat			hit_at_range;
	Vector  vel;
	target_laser_hit = NO_TARGET;

	vel.x = v_forward.x * flight_speed;
	vel.y = v_forward.y * flight_speed;
	vel.z = v_forward.z * flight_speed;

	Vector	laserPortOffset = forwardWeaponOffset;

	switch(direction)
	{
		case VIEW_AFT:
			laserPortOffset = aftWeaponOffset;
			break;
		case VIEW_PORT:
			laserPortOffset = portWeaponOffset;
			break;
		case VIEW_STARBOARD:
			laserPortOffset = starboardWeaponOffset;
			break;
		default:
			laserPortOffset = forwardWeaponOffset;
	}

	target_laser_hit = [universe getFirstEntityHitByLaserFromEntity:self inView:direction offset:laserPortOffset rangeFound: &hit_at_range];

//	if (isPlayer)
//		NSLog(@"DEBUG target double-check range = %.2f victim = %d --> %@\n\n", hit_at_range, target_laser_hit, [universe entityForUniversalID:target_laser_hit]);

	shot = [[ParticleEntity alloc] initLaserFromShip:self view:direction offset:laserPortOffset];	// alloc retains!

	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	if (target_laser_hit != NO_TARGET)
	{
		Entity *victim = [universe entityForUniversalID:target_laser_hit];

		if ((victim) && (victim->isShip))
		{
			ShipEntity* parent = (ShipEntity*)[victim owner];
			if ((parent) && (parent != victim) && [parent->sub_entities containsObject:victim])
			{
				if (!(parent->isFrangible))
					victim = parent;
			}
		}

		if (victim)
		{
			Vector p0 = shot->position;
			Vector p1 = victim->position;
			p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;

			if (victim->isShip)
			{
				ShipEntity* ship_hit = ((ShipEntity*)victim);
				ShipEntity* subent = ship_hit->subentity_taking_damage;
				if ((subent) && [ship_hit->sub_entities containsObject:subent])
				{
					if (ship_hit->isFrangible)
					{
						p1 = [subent absolutePositionForSubentity];
						victim = subent;
						// do 1% bleed-through damage...
						[ship_hit takeEnergyDamage: 0.01 * weapon_energy from:subent becauseOf:self];
					}
				}
			}

			double dist2 = magnitude2(p1);
			if ((victim->isShip)&&(dist2 < range_limit2))
			{
				[(ShipEntity *)victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit

				GLfloat cr = hit_at_range;

//				if (isPlayer)
//					NSLog(@"DEBUG distance double check = %.2f", cr);

				[shot setCollisionRadius: cr];
				Vector vd = vector_forward_from_quaternion(shot->q_rotation);
				Vector p0 = shot->position;
				p0.x += vd.x * cr;	p0.y += vd.y * cr;	p0.z += vd.z * cr;
				ParticleEntity* laserFlash = [[ParticleEntity alloc] initFlashSize:1.0 FromPosition: p0 Color:laser_color];
				[laserFlash setVelocity:[victim getVelocity]];
				[universe addEntity:laserFlash];
				[laserFlash release];
			}
		}
	}
	[universe addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	// random laser over-heating for AI ships
	if ((!isPlayer)&&((ranrot_rand() & 255) < weapon_energy)&&(![self isMining]))
		shot_time -= (randf() * weapon_energy);

	return YES;
}

- (void) throwSparks
{
	ParticleEntity*	spark;
	Vector  vel;
	Vector  origin = position;

	GLfloat lr	= randf() * (boundingBox.max.x - boundingBox.min.x) + boundingBox.min.x;
	GLfloat ud	= randf() * (boundingBox.max.y - boundingBox.min.y) + boundingBox.min.y;
	GLfloat fb	= randf() * boundingBox.max.z + boundingBox.min.z;	// rear section only

	origin.x += fb * v_forward.x;
	origin.y += fb * v_forward.y;
	origin.z += fb * v_forward.z;

	origin.x += ud * v_up.x;
	origin.y += ud * v_up.y;
	origin.z += ud * v_up.z;

	origin.x += lr * v_right.x;
	origin.y += lr * v_right.y;
	origin.z += lr * v_right.z;

	float	w = boundingBox.max.x - boundingBox.min.x;
	float	h = boundingBox.max.y - boundingBox.min.y;
	float	m = (w < h) ? 0.25 * w: 0.25 * h;

	float	sz = m * (1 + randf() + randf());	// half minimum dimension on average

	vel = make_vector( 2.0 * (origin.x - position.x), 2.0 * (origin.y - position.y), 2.0 * (origin.z - position.z));

	spark = [[ParticleEntity alloc] init];	// alloc retains!
	[spark setPosition:origin]; // directly ahead
	[spark setScanClass: CLASS_NO_DRAW];
	[spark setVelocity: vel];
	[spark setDuration: 2.0 + 3.0 * randf()];
	[spark setCollisionRadius: 2.0];
	[spark setSize:NSMakeSize( sz, sz)];
	[spark setEnergy: 0.0];
	[spark setParticleType: PARTICLE_SPARK];
	[spark setColor:[OOColor colorWithCalibratedHue:0.08 + 0.17 * randf() saturation:1.0 brightness:1.0 alpha:1.0]];
	[spark setOwner:self];
	[universe addEntity:spark];
	[spark release]; //release

	next_spark_time = randf();
}

- (BOOL) firePlasmaShot:(double) offset :(double) speed :(OOColor *) color
{
	ParticleEntity *shot;
	Vector  vel, rt;
	Vector  origin = position;
	double  start = collision_radius + 0.5;

	speed += flight_speed;

	if (++shot_counter % 2)
		offset = -offset;

	vel = v_forward;
	rt = v_right;

	if (isPlayer)					// player can fire into multiple views!
	{
		switch ([universe viewDir])
		{
			case VIEW_AFT :
				vel = v_forward;
				vel.x = -vel.x; vel.y = -vel.y; vel.z = -vel.z; // reverse
				rt = v_right;
				rt.x = -rt.x;   rt.y = -rt.y;   rt.z = -rt.z; // reverse
				break;
			case VIEW_STARBOARD :
				vel = v_right;
				rt = v_forward;
				rt.x = -rt.x;   rt.y = -rt.y;   rt.z = -rt.z; // reverse
				break;
			case VIEW_PORT :
				vel = v_right;
				vel.x = -vel.x; vel.y = -vel.y; vel.z = -vel.z; // reverse
				rt = v_forward;
				break;
		}
	}

	origin.x += vel.x * start;
	origin.y += vel.y * start;
	origin.z += vel.z * start;

	origin.x += rt.x * offset;
	origin.y += rt.y * offset;
	origin.z += rt.z * offset;

	vel.x *= speed;
	vel.y *= speed;
	vel.z *= speed;

	shot = [[ParticleEntity alloc] init];	// alloc retains!
	[shot setPosition:origin]; // directly ahead
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	[shot setDuration: 5.0];
	[shot setCollisionRadius: 2.0];
	[shot setEnergy: weapon_energy];
	[shot setParticleType: PARTICLE_SHOT_GREEN_PLASMA];
	[shot setColor:color];
	[shot setOwner:self];
	[universe addEntity:shot];
	[shot release]; //release

	shot_time = 0.0;

	return YES;
}

- (BOOL) fireMissile
{
	ShipEntity *missile = nil;
	Vector  vel;
	Vector  origin = position;
	Vector  start, v_eject;

	// default launching position
	start.x = 0.0;						// in the middle
	start.y = boundingBox.min.y - 4.0;	// 4m below bounding box
	start.z = boundingBox.max.z + 1.0;	// 1m ahead of bounding box
	// custom launching position
	if ([shipinfoDictionary objectForKey:@"missile_launch_position"])
	{
		start = [Entity vectorFromString:(NSString *)[shipinfoDictionary objectForKey:@"missile_launch_position"]];
	}

	double  throw_speed = 250.0;
	Quaternion q1 = q_rotation;
	Entity  *target = [self getPrimaryTarget];

	if	((missiles <= 0)||(target == nil)||(target->scan_class == CLASS_NO_DRAW)||
		((target->isShip)&&(!has_military_scanner_filter)&&([(ShipEntity*)target isJammingScanning])))	// no missile lock!
		return NO;

//	if (scan_class == CLASS_THARGOID)
//		return [self fireTharglet];

	// custom missiles
	if ([shipinfoDictionary objectForKey:@"missile_role"])
		missile = [universe getShipWithRole:(NSString*)[shipinfoDictionary objectForKey:@"missile_role"]];
	if (!missile)	// no custom role
	{
		if (randf() < 0.90)	// choose a standard missile 90% of the time
			missile = [universe getShipWithRole:@"EQ_MISSILE"];   // retained
		else				// otherwise choose any with the role 'missile' - which may include alternative weapons
			missile = [universe getShipWithRole:@"missile"];   // retained
	}

	if (!missile)
		return NO;

	missiles--;

	double mcr = missile->collision_radius;

	v_eject = unit_vector( &start);

	vel = make_vector( 0.0f, 0.0f, 0.0f);	// starting velocity

	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - mcr)&&(start.x < boundingBox.max.x + mcr)&&
			(start.y > boundingBox.min.y - mcr)&&(start.y < boundingBox.max.y + mcr)&&
			(start.z > boundingBox.min.z - mcr)&&(start.z < boundingBox.max.z + mcr))
	{
		start.x += mcr * v_eject.x;	start.y += mcr * v_eject.y;	start.z += mcr * v_eject.z;
		vel.x += 10.0f * mcr * v_eject.x;	vel.y += 10.0f * mcr * v_eject.y;	vel.z += 10.0f * mcr * v_eject.z;	// throw it outward a bit harder
	}

	if (isPlayer)
		q1.w = -q1.w;   // player view is reversed remember!

	vel.x += (flight_speed + throw_speed) * v_forward.x;
	vel.y += (flight_speed + throw_speed) * v_forward.y;
	vel.z += (flight_speed + throw_speed) * v_forward.z;

	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;

	[missile addTarget:		target];
	[missile setOwner:		self];
	[missile setGroup_id:	group_id];
	[missile setPosition:	origin];
	[missile setQRotation:	q1];
	[missile setVelocity:	vel];
	[missile setSpeed:		150.0];
	[missile setDistanceTravelled:	0.0];
	[missile setStatus:		STATUS_IN_FLIGHT];  // necessary to get it going!
	//
	[universe addEntity:	missile];
	//
	[missile release]; //release

	if ([missile scanClass] == CLASS_MISSILE)
	{
		[(ShipEntity *)target setPrimaryAggressor:self];
		[[(ShipEntity *)target getAI] reactToMessage:@"INCOMING_MISSILE"];
	}

	return YES;
}

- (BOOL) fireECM
{
	if (!has_ecm)
		return NO;
	else
	{
		ParticleEntity  *ecmDevice = [[ParticleEntity alloc] initECMMineFromShip:self]; // retained
		[universe addEntity:ecmDevice];
		[ecmDevice release];
	}
	return YES;
}

- (BOOL) activateCloakingDevice
{
	if (!has_cloaking_device)
		return NO;
	if (!cloaking_device_active)
		cloaking_device_active = (energy > CLOAKING_DEVICE_START_ENERGY * max_energy);
	return cloaking_device_active;
}

- (void) deactivateCloakingDevice
{
	cloaking_device_active = NO;
}

- (BOOL) launchEnergyBomb
{
	if (!has_energy_bomb)
		return NO;
	has_energy_bomb = NO;
	[self setSpeed: max_flight_speed + 300];
	ShipEntity*	bomb = [universe getShipWithRole:@"energy-bomb"];
	if (!bomb)
		return NO;
	double  start = collision_radius + bomb->collision_radius;
	double  eject_speed = -800.0;
	Quaternion  random_direction;
	Vector  vel;
	Vector  rpos = position;
	double random_roll =	randf() - 0.5;  //  -0.5 to +0.5
	double random_pitch = 	randf() - 0.5;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);
	rpos.x -= v_forward.x * start;
	rpos.y -= v_forward.y * start;
	rpos.z -= v_forward.z * start;
	vel.x = v_forward.x * (flight_speed + eject_speed);
	vel.y = v_forward.y * (flight_speed + eject_speed);
	vel.z = v_forward.z * (flight_speed + eject_speed);
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.25x .. +0.25x
	vel.x += v_up.x * eject_speed;
	vel.y += v_up.y * eject_speed;
	vel.z += v_up.z * eject_speed;
	eject_speed *= 0.5 * (randf() - 0.5);   //  -0.0625x .. +0.0625x
	vel.x += v_right.x * eject_speed;
	vel.y += v_right.y * eject_speed;
	vel.z += v_right.z * eject_speed;
	[bomb setPosition:rpos];
	[bomb setQRotation:random_direction];
	[bomb setRoll:random_roll];
	[bomb setPitch:random_pitch];
	[bomb setVelocity:vel];
	[bomb setScanClass: CLASS_MINE];	// TODO should be CLASS_ENERGY_BOMB
	[bomb setStatus: STATUS_IN_FLIGHT];
	[bomb setEnergy: 5.0];	// 5 second countdown
	[bomb setBehaviour: BEHAVIOUR_ENERGY_BOMB_COUNTDOWN];
	[bomb setOwner: self];
	[universe addEntity:bomb];
	[[bomb getAI] setState:@"GLOBAL"];
	[bomb release];
	if (self != [universe entityZero])	// get the heck out of here
	{
		[self addTarget:bomb];
		behaviour = BEHAVIOUR_FLEE_TARGET;
		frustration = 0.0;
	}
	return YES;
}

- (int) launchEscapeCapsule
{
	ShipEntity *pod;

	pod = [universe getShipWithRole:@"escape-capsule"];   // retain count = 1
	if (pod)
	{
		[pod setOwner:self];
		[pod setScanClass: CLASS_CARGO];
		[pod setCommodity:[universe commodityForName:@"Slaves"] andAmount:1];
		if (crew)	// transfer crew
		{
			[pod setCrew: crew];
			[crew autorelease];
			crew = nil;
		}
		[[pod getAI] setStateMachine:@"homeAI.plist"];
		[self dumpItem:pod];
		[[pod getAI] setState:@"GLOBAL"];
		[pod release]; //release
		return [pod universal_id];
	}
	return NO_TARGET;
}

- (int) dumpCargo
{
	if (status == STATUS_DEAD)
		return 0;

	int result = CARGO_NOT_CARGO;
	if (([cargo count] > 0)&&([universe getTime] - cargo_dump_time > 0.5))  // space them 0.5s or 10m apart
	{
		ShipEntity* jetto = [cargo objectAtIndex:0];
		if (!jetto)
			return 0;
		result = [jetto getCommodityType];
		[self dumpItem:jetto];
		[cargo removeObjectAtIndex:0];
		cargo_dump_time = [universe getTime];
	}
	return result;
}

- (int) dumpItem: (ShipEntity*) jetto
{
	if (!jetto)
		return 0;
	int result = [jetto getCargoType];
	Vector start;

	double  eject_speed = 20.0;
	double  eject_reaction = -eject_speed * [jetto mass] / [self mass];
	double	jcr = jetto->collision_radius;

	Quaternion  random_direction;
	Vector  vel, v_eject;
	Vector  rpos = position;
	double random_roll =	((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	double random_pitch =   ((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);

	// default launching position
	start.x = 0.0;						// in the middle
	start.y = 0.0;						//
	start.z = boundingBox.min.z - jcr;	// 1m behind of bounding box

	// custom launching position
	if ([shipinfoDictionary objectForKey:@"aft_eject_position"])
	{
		start = [Entity vectorFromString:(NSString *)[shipinfoDictionary objectForKey:@"aft_eject_position"]];
	}

	v_eject = unit_vector( &start);

	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - jcr)&&(start.x < boundingBox.max.x + jcr)&&
			(start.y > boundingBox.min.y - jcr)&&(start.y < boundingBox.max.y + jcr)&&
			(start.z > boundingBox.min.z - jcr)&&(start.z < boundingBox.max.z + jcr))
	{
		start.x += jcr * v_eject.x;	start.y += jcr * v_eject.y;	start.z += jcr * v_eject.z;
	}

	v_eject = make_vector(	v_right.x * start.x +	v_up.x * start.y +	v_forward.x * start.z,
							v_right.y * start.x +	v_up.y * start.y +	v_forward.y * start.z,
							v_right.z * start.x +	v_up.z * start.y +	v_forward.z * start.z);

	rpos.x +=	v_eject.x;
	rpos.y +=	v_eject.y;
	rpos.z +=	v_eject.z;

	v_eject = unit_vector( &v_eject);

	v_eject.x += (randf() - randf())/eject_speed;
	v_eject.y += (randf() - randf())/eject_speed;
	v_eject.z += (randf() - randf())/eject_speed;

	vel.x =	v_forward.x * flight_speed + v_eject.x * eject_speed;
	vel.y = v_forward.y * flight_speed + v_eject.y * eject_speed;
	vel.z = v_forward.z * flight_speed + v_eject.z * eject_speed;

	velocity.x += v_eject.x * eject_reaction;
	velocity.y += v_eject.y * eject_reaction;
	velocity.z += v_eject.z * eject_reaction;

	[jetto setPosition:rpos];
	[jetto setQRotation:random_direction];
	[jetto setRoll:random_roll];
	[jetto setPitch:random_pitch];
	[jetto setVelocity:vel];
	[jetto setScanClass: CLASS_CARGO];
	[jetto setStatus: STATUS_IN_FLIGHT];
	[universe addEntity:jetto];
	[[jetto getAI] setState:@"GLOBAL"];
	cargo_dump_time = [universe getTime];
	return result;
}

- (void) manageCollisions
{
	// deal with collisions
	//
	Entity*		ent;
	ShipEntity* other_ship;

	while ([collidingEntities count] > 0)
	{
		ent = [(Entity *)[collidingEntities objectAtIndex:0] retain];
		[collidingEntities removeObjectAtIndex:0];
		if (ent)
		{
			if (ent->isShip)
			{
				other_ship = (ShipEntity *)ent;
				[self collideWithShip:other_ship];
			}
			if (ent->isPlanet)
			{
				if (isPlayer)
				{
					[(PlayerEntity *)self getDestroyed];
					return;
				}
				[self becomeExplosion];
			}
			if (ent->isWormhole)
			{
				WormholeEntity* whole = (WormholeEntity*)ent;
				if (isPlayer)
				{
					[(PlayerEntity*)self enterWormhole: whole];
					return;
				}
				else
				{
					[whole suckInShip: self];
				}
			}
			[ent release];
		}
	}
}

- (BOOL) collideWithShip:(ShipEntity *)other
{
	Vector  loc, opos, pos;
	double  inc1, dam1, dam2;
	
	if (!other)
		return NO;

//	if ((self->isPlayer)||(other->isPlayer))
//		NSLog(@"DEBUG %@ %d colliding with other %@ %d", name, universal_id, [other name], [other universal_id]);
	
	ShipEntity* otherParent = (ShipEntity*)[other owner];
	BOOL otherIsSubentity = ((otherParent)&&(otherParent != other)&&([otherParent->sub_entities containsObject:other]));

	// calculate line of centers using centres
	if (otherIsSubentity)
		opos = [other absolutePositionForSubentity];
	else
		opos = other->position;
	loc = opos;
	loc.x -= position.x;	loc.y -= position.y;	loc.z -= position.z;

	if (loc.x||loc.y||loc.z)
		loc = unit_vector(&loc);
	else
		loc.z = 1.0;

	inc1 = (v_forward.x*loc.x)+(v_forward.y*loc.y)+(v_forward.z*loc.z);

	if ([self canScoop:other])
	{
		[self scoopIn:other];
		return NO;
	}
	if ([other canScoop:self])
	{
		[other scoopIn:self];
		return NO;
	}
	if (universal_id == NO_TARGET)
		return NO;
	if (other->universal_id == NO_TARGET)
		return NO;

	// find velocity along line of centers
	//
	// momentum = mass x velocity
	// ke = mass x velocity x velocity
	//
	GLfloat m1 = mass;			// mass of self
	GLfloat m2 = [other mass];	// mass of other

	// starting velocities:
	Vector	vel1b =	[self getVelocity];
	// calculate other's velocity relative to self
	Vector	v =	[other getVelocity];
	if (otherIsSubentity)
	{
		if (otherParent)
		{
			v = [otherParent getVelocity];
			// if the subentity is rotating (subentity_rotational_velocity is not 1 0 0 0)
			// we should calculate the tangential velocity from the other's position
			// relative to our absolute position and add that in. For now this is a TODO
		}
		else
			v = make_vector( 0.0f, 0.0f, 0.0f);
	}

	//
	v = make_vector( vel1b.x - v.x, vel1b.y - v.y, vel1b.z - v.z);	// velocity of self relative to other

	//
	GLfloat	v2b = dot_product( v, loc);			// velocity of other along loc before collision
	//
	GLfloat v1a = sqrt(v2b * v2b * m2 / m1);	// velocity of self along loc after elastic collision
	if (v2b < 0.0f)	v1a = -v1a;					// in same direction as v2b


	// are they moving apart at over 1m/s already?
	if (v2b < 0.0f)
	{
		if (v2b < -1.0f)
		{
//			NSLog(@"MOVING APART! %@ >%.3f %.3f< %@", self, sqrt(distance2(position, opos)), v2b, other);
			return NO;
		}
		else
		{
//			NSLog(@"MOVING APART TOO SLOW! %@ >%.3f %.3f< %@", self, sqrt(distance2(position, opos)), v2b, other);
			position = make_vector( position.x - loc.x, position.y - loc.y, position.z - loc.z);	// adjust self position
			v = make_vector( 0.0f, 0.0f, 0.0f);	// go for the 1m/s solution
		}
	}
//	else
//	{
//		NSLog(@"MOVING CLOSER %@ >%.3f %.3f< %@", self, sqrt(distance2(position, opos)), v2b, other);
//	}
	//

	// convert change in velocity into damage energy (KE)
	//
	dam1 = m2 * v2b * v2b / 50000000;
	dam2 = m1 * v2b * v2b / 50000000;

	// calculate adjustments to velocity after collision
	Vector vel1a = make_vector( -v1a * loc.x, -v1a * loc.y, -v1a * loc.z);
	Vector vel2a = make_vector( v2b * loc.x, v2b * loc.y, v2b * loc.z);

	if (magnitude2(v) <= 0.1)	// virtually no relative velocity - we must provide at least 1m/s to avoid conjoined objects
	{
			vel1a = make_vector( -loc.x, -loc.y, -loc.z);
			vel2a = make_vector( loc.x, loc.y, loc.z);
	}

	// apply change in velocity
	if ((otherIsSubentity)&&(otherParent))
		[otherParent adjustVelocity:vel1a];	// move the otherParent not the subentity
	else
		[self adjustVelocity:vel1a];
	[other adjustVelocity:vel2a];

	//
	//
	BOOL selfDestroyed = (dam1 > energy);
	BOOL otherDestroyed = (dam2 > [other getEnergy]);
	//
	if (dam1 > 0.05)
	{
		[self	takeScrapeDamage: dam1 from:other];
		if (selfDestroyed)	// inelastic! - take xplosion velocity damage instead
		{
			vel2a.x = -vel2a.x;	vel2a.y = -vel2a.y;	vel2a.z = -vel2a.z;
			[other adjustVelocity:vel2a];
		}
	}
	//
	if (dam2 > 0.05)
	{
		if ((otherIsSubentity) && (otherParent) && !(otherParent->isFrangible))
			[otherParent takeScrapeDamage: dam2 from:self];
		else
			[other	takeScrapeDamage: dam2 from:self];
		if (otherDestroyed)	// inelastic! - take explosion velocity damage instead
		{
			vel1a.x = -vel1a.x;	vel1a.y = -vel1a.y;	vel1a.z = -vel1a.z;
			[other adjustVelocity:vel1a];
		}
	}

//	NSLog(@"DEBUG back-off distance is %.3fm\n\n", back_dist);
	//
	if ((!selfDestroyed)&&(!otherDestroyed))
	{
		float t = 10.0 * [universe getTimeDelta];	// 10 ticks
		//
		pos = self->position;
		opos = other->position;
		//
		Vector pos1a = make_vector(pos.x + t * v1a * loc.x, pos.y + t * v1a * loc.y, pos.z + t * v1a * loc.z);
		Vector pos2a = make_vector(opos.x - t * v2b * loc.x, opos.y - t * v2b * loc.y, opos.z - t * v2b * loc.z);
		//
		[self setPosition:pos1a];
		[other setPosition:pos2a];
	}

	//
	// remove self from other's collision list
	//
	[[other collisionArray] removeObject:self];
	//
	////

	[shipAI reactToMessage:@"COLLISION"];

	return YES;
}

- (Vector) getVelocity	// overrides Entity getVelocity
{
	Vector v = velocity;
	v.x += flight_speed * v_forward.x;	v.y += flight_speed * v_forward.y;	v.z += flight_speed * v_forward.z;
	return v;
}

- (void) adjustVelocity:(Vector) xVel
{
	velocity.x += xVel.x;
	velocity.y += xVel.y;
	velocity.z += xVel.z;
}

- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch
{
	velocity.x += howmuch * moment.x / mass;
	velocity.y += howmuch * moment.y / mass;
	velocity.z += howmuch * moment.z / mass;
}

- (BOOL) canScoop:(ShipEntity*)other
{
//	NSLog(@"DEBUG Checking if %@ %d can scoop %@ %d", name, universal_id, [other name], [other universal_id]);
	if (!other)										return NO;
	//
	if (!has_scoop)									return NO;
//	NSLog(@"DEBUG scoop okay");
	if ([cargo count] >= max_cargo)					return NO;
//	NSLog(@"DEBUG cargo space okay");
	if (other->scan_class != CLASS_CARGO)			return NO;
//	NSLog(@"DEBUG other scan class is CLASS_CARGO okay");
	if ([other getCargoType] == CARGO_NOT_CARGO)	return NO;
//	NSLog(@"DEBUG other cargo type is not CARGO_NOT_CARGO okay");

	if (other->isStation)
		return NO;

	Vector  loc = vector_between( position, other->position);

	GLfloat inc1 = (v_forward.x*loc.x)+(v_forward.y*loc.y)+(v_forward.z*loc.z);
	if (inc1 < 0.0f)									return NO;
	GLfloat inc2 = (v_up.x*loc.x)+(v_up.y*loc.y)+(v_up.z*loc.z);
	if ((inc2 > 0.0f)&&(isPlayer))	return NO;	// player has to scoop ro underside, give more flexibility to NPCs
	return YES;
}

- (void) getTractoredBy:(ShipEntity *)other
{
	desired_speed = 0.0;
	[self setAITo:@"nullAI.plist"];	// prevent AI from changing status or behaviour
	behaviour = BEHAVIOUR_TRACTORED;
	status = STATUS_BEING_SCOOPED;
	[self addTarget: other];
	[self setOwner: other];
}

- (void) scoopIn:(ShipEntity *)other
{
	[other getTractoredBy:self];
}

- (void) scoopUp:(ShipEntity *)other
{
	if (!other)
		return;
	int		co_type,co_amount;
	switch ([other getCargoType])
	{
		case	CARGO_RANDOM :
			co_type = [other getCommodityType];
			co_amount = [other getCommodityAmount];
			break;
		case	CARGO_SLAVES :
			co_amount = 1;
			co_type = [universe commodityForName:@"Slaves"];
			if (co_type == NSNotFound)  // No 'Slaves' in this game, get something else instead...
			{
				co_type = [universe getRandomCommodity];
				co_amount = [universe getRandomAmountOfCommodity:co_type];
			}
			break;
		case	CARGO_ALLOY :
			co_amount = 1;
			co_type = [universe commodityForName:@"Alloys"];
			break;
		case	CARGO_MINERALS :
			co_amount = 1;
			co_type = [universe commodityForName:@"Minerals"];
			break;
		case	CARGO_THARGOID :
			co_amount = 1;
			co_type = [universe commodityForName:@"Alien Items"];
			break;
		case	CARGO_SCRIPTED_ITEM :
			{
				NSArray* actions = [other script_actions];
				//scripting
				if ([actions count])
				{
					PlayerEntity* player = (PlayerEntity *)[universe entityZero];

					[player setScript_target:self];
					[player scriptActions: actions forTarget: other];

				}
//				NSLog(@"DEBUG Scooped scripted item %@ %@ %d", other, [other name], [other universal_id]);
				if (isPlayer)
				{
					Random_Seed s_seed;
					NSString* scoopedMS = [NSString stringWithFormat:[universe expandDescription:@"[@-scooped]" forSystem:s_seed], [other name]];
					[universe clearPreviousMessage];
					[universe addMessage:scoopedMS forCount:4];
				}
			}
		default :
			co_amount = 0;
			co_type = 0;
			break;
	}
	if (co_amount > 0)
	{
		[other setCommodity:co_type andAmount:co_amount];   // belt and braces setting this!
		if (cargo_flag !=CARGO_FLAG_CANISTERS)
			cargo_flag = CARGO_FLAG_CANISTERS;
		//NSLog(@"---> %@ %d scooped %@", name, universal_id, [universe describeCommodity:co_type amount:co_amount]);
		if (isPlayer)
		{
			[universe clearPreviousMessage];
			[universe addMessage:[universe describeCommodity:co_type amount:co_amount] forCount:4.5];
		}
		[cargo addObject:other];
		[other setStatus:STATUS_IN_HOLD];					// prevents entity from being recycled!
		[shipAI message:@"CARGO_SCOOPED"];
		if ([cargo count] == max_cargo)
			[shipAI message:@"HOLD_FULL"];
	}
	[[other collisionArray] removeObject:self];			// so it can't be scooped twice!
	if (isPlayer)
		[(PlayerEntity*)self suppressTargetLost];
	[universe removeEntity:other];
}

- (void) takeScrapeDamage:(double) amount from:(Entity *) ent
{
	if (status == STATUS_DEAD)					// it's too late for this one!
		return;

	if ([universe station] == self)				// main stations are indestructible
		return;

	if (status == STATUS_LAUNCHING)					// no collisions during launches please
		return;
	if ((ent)&&(ent->status == STATUS_LAUNCHING))	// no collisions during launches please
		return;

	//
	energy -= amount;
	// oops we hit too hard!!!
	if (energy <= 0.0)
	{
		being_mined = YES;  // same as using a mining laser
		if ((ent)&&(ent->isShip))
		{
			ShipEntity* hunter = (ShipEntity *)ent;
			[hunter collectBountyFor:self];
			if ([hunter getPrimaryTarget] == (Entity *)self)
			{
				[hunter removeTarget:(Entity *)self];
				[[hunter getAI] message:@"TARGET_DESTROYED"];
			}
		}
		[self becomeExplosion];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < max_energy *0.25)
			[shipAI message:@"ENERGY_LOW"];
	}
}

- (void) takeHeatDamage:(double) amount
{
	if (status == STATUS_DEAD)					// it's too late for this one!
		return;

	if (amount < 0.0)
		return;

	energy -= amount;

	throw_sparks = YES;

	// oops we're burning up!
	if (energy <= 0.0)
		[self becomeExplosion];
	else
	{
		// warn if I'm low on energy
		if (energy < max_energy *0.25)
			[shipAI message:@"ENERGY_LOW"];
	}
}

- (void) enterDock:(StationEntity *)station
{
	// throw these away now we're docked...
	if (dockingInstructions)
		[dockingInstructions autorelease];
	dockingInstructions = nil;

	[shipAI message:@"DOCKED"];
	[station noteDockedShip:self];
	[universe removeEntity:self];
}

- (void) leaveDock:(StationEntity *)station
{
	if (station)
	{
		Vector launchPos = station->position;
		Vector stat_f = vector_forward_from_quaternion(station->q_rotation);
		launchPos.x += 500.0*stat_f.x;
		launchPos.y += 500.0*stat_f.y;
		launchPos.z += 500.0*stat_f.z;
		position = launchPos;
		q_rotation = station->q_rotation;
		flight_roll = [station flight_roll];
	}
	flight_pitch = 0.0;
	flight_speed = max_flight_speed * 0.5;
	status = STATUS_LAUNCHING;
	[shipAI message:@"LAUNCHED"];
	[universe addEntity:self];
}

- (void) enterWormhole:(WormholeEntity *) w_hole
{
	if (![[universe sun] willGoNova])				// if the sun's not going nova
		[universe witchspaceShipWithRole:roles];	// then add a new ship like this one leaving!

	[w_hole suckInShip: self];	// removes ship from universe
}

- (void) enterWitchspace
{
	// witchspace entry effects here
	ParticleEntity *ring1 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[universe addEntity:ring1];
	[ring1 release];
	ParticleEntity *ring2 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[ring2 setSize:NSMakeSize([ring2 size].width * -2.5 ,[ring2 size].height * -2.0 )]; // shrinking!
	[universe addEntity:ring2];
	[ring2 release];

	[shipAI message:@"ENTERED_WITCHSPACE"];

	if (![[universe sun] willGoNova])				// if the sun's not going nova
		[universe witchspaceShipWithRole:roles];	// then add a new ship like this one leaving!

	[universe removeEntity:self];
}

- (void) leaveWitchspace
{
	Vector		pos = [universe getWitchspaceExitPosition];
	Quaternion  q_rtn = [universe getWitchspaceExitRotation];
	position = pos;
	double		d1 = SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
	if (abs(d1) < 500.0)	// no closer than 500m
		d1 += ((d1 > 0.0)? 500.0: -500.0);
	Quaternion	q1 = q_rtn;
	quaternion_set_random(&q1);
	Vector		v1 = vector_forward_from_quaternion(q1);

	position.x += v1.x * d1; // randomise exit position
	position.y += v1.y * d1;
	position.z += v1.z * d1;
	q_rotation = q_rtn;
	flight_roll = 0.0;
	flight_pitch = 0.0;
	flight_speed = max_flight_speed * 0.25;
	status = STATUS_LAUNCHING;
	[shipAI message:@"EXITED_WITCHSPACE"];
	[universe addEntity:self];

	//NSLog(@"DEBUG Ship: %@ %d exiting witchspace now!", name, universal_id);

	// witchspace exit effects here
	ParticleEntity *ring1 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[universe addEntity:ring1];
	[ring1 release];
	ParticleEntity *ring2 = [[ParticleEntity alloc] initHyperringFromShip:self]; // retained
	[ring2 setSize:NSMakeSize([ring2 size].width * -2.5 ,[ring2 size].height * -2.0 )]; // shrinking!
	[universe addEntity:ring2];
	[ring2 release];
}

- (void) markAsOffender:(int)offence_value
{
//	if (![roles isEqual:@"police"])
	if (scan_class != CLASS_POLICE)
		bounty |= offence_value;
}

- (void) switchLightsOn
{
	if (!sub_entities) return;
	int i;
	for (i = 0; i < [sub_entities count]; i++)
	{
		Entity* subent = (Entity*)[sub_entities objectAtIndex:i];
		if (subent->isParticle)
		{
			if ([(ParticleEntity*)subent particleType] == PARTICLE_FLASHER)
				[subent setStatus:STATUS_EFFECT];
		}
	}
}

- (void) switchLightsOff
{
	if (!sub_entities) return;
	int i;
	for (i = 0; i < [sub_entities count]; i++)
	{
		Entity* subent = (Entity*)[sub_entities objectAtIndex:i];
		if (subent->isParticle)
		{
			if ([(ParticleEntity*)subent particleType] == PARTICLE_FLASHER)
				[subent setStatus:STATUS_INACTIVE];
		}
	}
}

- (void) setDestination:(Vector) dest
{
	destination = dest;
	frustration = 0.0;	// new destination => no frustration!
}

inline BOOL pairOK(NSString* my_role, NSString* their_role)
{
	BOOL pairing_okay = NO;

	pairing_okay |= (![my_role isEqual:@"escort"] && ![my_role isEqual:@"wingman"] && [their_role isEqual:@"escort"]);
	pairing_okay |= (([my_role isEqual:@"police"]||[my_role isEqual:@"interceptor"]) && [their_role isEqual:@"wingman"]);

//	NSLog(@"checking if pairOK for ( %@, %@) >> %@", my_role, their_role, (pairing_okay)? @"YES":@"NO");

	return pairing_okay;
}

- (BOOL) acceptAsEscort:(ShipEntity *) other_ship
{
	// can't pair with self
	if (self == other_ship)
		return NO;

//	NSLog(@"DEBUG %@ %d asked to accept %@ %d as escort when ai_stack_depth is %d", name, universal_id, [other_ship name], [other_ship universal_id], [shipAI ai_stack_depth]);

	// if not in standard ai mode reject approach
	if ([shipAI ai_stack_depth] > 1)
		return NO;

//	NSLog(@"DEBUG pairOK( %@, %@) = %@", roles, [other_ship roles], (pairOK( roles, [other_ship roles]))? @"YES":@"NO");

	if (pairOK( roles, [other_ship roles]))
	{
		// check total number acceptable
		int max_escorts = [(NSNumber *)[shipinfoDictionary objectForKey:@"escorts"] intValue];

		// check it's not already been accepted
		int i;
		for (i = 0; i < n_escorts; i++)
		{
			if (escort_ids[i] == [other_ship universal_id])
			{
				[other_ship setGroup_id:universal_id];
				[self setGroup_id:universal_id];		// make self part of same group
				return YES;
			}
		}

		if ((n_escorts < MAX_ESCORTS)&&(n_escorts < max_escorts))
		{
			escort_ids[n_escorts] = [other_ship universal_id];
			[other_ship setGroup_id:universal_id];
			[self setGroup_id:universal_id];		// make self part of same group
			n_escorts++;

			//debug
//			NSLog(@"DEBUG ::YES:: %@ accepts escort %@", self, other_ship);

			return YES;
		}
	}
	return NO;
}

- (Vector) getCoordinatesForEscortPosition:(int) f_pos
{
	int f_hi = 1 + (f_pos >> 2);
	int f_lo = f_pos & 3;

	int fp = f_lo * 3;
	int escort_positions[12] = {	-2,0,-1,   2,0,-1,  -3,0,-3,	3,0,-3  };
	Vector pos = position;
	double spacing = collision_radius * ESCORT_SPACING_FACTOR;
	double xx = f_hi * spacing * escort_positions[fp++];
	double yy = f_hi * spacing * escort_positions[fp++];
	double zz = f_hi * spacing * escort_positions[fp];
	pos.x += v_right.x * xx;	pos.y += v_right.y * xx;	pos.z += v_right.z * xx;
	pos.x += v_up.x * yy;		pos.y += v_up.y * yy;		pos.z += v_up.z * yy;
	pos.x += v_forward.x * zz;	pos.y += v_forward.y * zz;	pos.z += v_forward.z * zz;

	return pos;
}

- (void) deployEscorts
{
	if (n_escorts < 1)
		return;

	if (![self getPrimaryTarget])
		return;

	if (primaryTarget == last_escort_target)
	{
		// already deployed escorts onto this target!
//		NSLog(@"DEBUG attempting to deploy more escorts onto same target - denied");
		return;
	}

	last_escort_target = primaryTarget;

	int n_deploy = ranrot_rand() % n_escorts;
	if (n_deploy == 0)
		n_deploy = 1;

	//NSLog(@"DEBUG %@ %d deploying %d escorts", name, universal_id, n_deploy);

	int i_deploy = n_escorts - 1;
	while ((n_deploy > 0)&&(n_escorts > 0))
	{
		int escort_id = escort_ids[i_deploy];
		ShipEntity  *escorter = (ShipEntity *)[universe entityForUniversalID:escort_id];
		// check it's still an escort ship
		BOOL escorter_okay = YES;
		if (!escorter)
			escorter_okay = NO;
		else
			escorter_okay = escorter->isShip;
		if (escorter_okay)
		{
			[escorter setGroup_id:NO_TARGET];	// act individually now!
			[escorter addTarget:[self getPrimaryTarget]];
			[[escorter getAI] setStateMachine:@"interceptAI.plist"];
			[[escorter getAI] setState:@"GLOBAL"];

			escort_ids[i_deploy] = NO_TARGET;
			i_deploy--;
			n_deploy--;
			n_escorts--;
			//debug
			//NSLog(@"DEBUG trader %@ %d deploys escort %@ %d", name, universal_id, [escorter name], [escorter universal_id]);
			//[escorter setReportAImessages:YES];
		}
		else
		{
			escort_ids[i_deploy--] = escort_ids[--n_escorts];	// remove the escort
		}
	}

}

- (void) dockEscorts
{
	if (n_escorts < 1)
		return;

	int i;
	for (i = 0; i < n_escorts; i++)
	{
		int escort_id = escort_ids[i];
		ShipEntity  *escorter = (ShipEntity *)[universe entityForUniversalID:escort_id];
		// check it's still an escort ship
		BOOL escorter_okay = YES;
		if (!escorter)
			escorter_okay = NO;
		else
			escorter_okay = escorter->isShip;
		if (escorter_okay)
		{
			SEL _setSM =	@selector(setStateMachine:);
			SEL _setSt =	@selector(setState:);
			float delay = i * 3.0 + 1.5;		// send them off at three second intervals
			[escorter setGroup_id:NO_TARGET];	// act individually now!
			[[escorter getAI] performSelector:_setSM withObject:@"dockingAI.plist" afterDelay:delay];
			[[escorter getAI] performSelector:_setSt withObject:@"ABORT" afterDelay:delay + 0.25];
		}
		escort_ids[i] = NO_TARGET;
	}
	n_escorts = 0;

}

- (void) setTargetToStation
{
	// check if the group_id (parent ship) points to a station...
	Entity* mother = [universe entityForUniversalID:group_id];
	if ((mother)&&(mother->isStation))
	{
		primaryTarget = group_id;
		targetStation = primaryTarget;
		return;	// head for mother!
	}

	/*- selects the nearest station it can find -*/
	if (!universe)
		return;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int station_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isStation)
			my_entities[station_count++] = [uni_entities[i] retain];		//	retained
	//
	StationEntity* station =  nil;
	double nearest2 = SCANNER_MAX_RANGE2 * 1000000.0; // 1000x scanner range (25600 km), squared.
	for (i = 0; i < station_count; i++)
	{
		StationEntity* thing = (StationEntity*)my_entities[i];
		double range2 = distance2( position, thing->position);
		if (range2 < nearest2)
		{
			station = (StationEntity *)thing;
			nearest2 = range2;
		}
	}
	for (i = 0; i < station_count; i++)
		[my_entities[i] release];		//	released
	//
	if (station)
	{
		primaryTarget = [station universal_id];
		targetStation = primaryTarget;
	}
}

- (PlanetEntity *) findNearestLargeBody
{
	/*- selects the nearest planet it can find -*/
	if (!universe)
		return nil;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int planet_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isPlanet)
			my_entities[planet_count++] = [uni_entities[i] retain];		//	retained
	//
	PlanetEntity	*the_planet =  nil;
	double nearest2 = SCANNER_MAX_RANGE2 * 10000000000.0; // 100 000x scanner range (2 560 000 km), squared.
	for (i = 0; i < planet_count; i++)
	{
		PlanetEntity  *thing = (PlanetEntity*)my_entities[i];
		double range2 = distance2( position, thing->position);
		if ((!the_planet)||(range2 < nearest2))
		{
			the_planet = (PlanetEntity *)thing;
			nearest2 = range2;
		}
	}
	for (i = 0; i < planet_count; i++)
		[my_entities[i] release];		//	released
	//
	return the_planet;
}

- (void) abortDocking
{
	if (!universe)
		return;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	int i;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isStation)
			[(StationEntity *)uni_entities[i] abortDockingForShip:self];	// action
}

- (void) broadcastThargoidDestroyed
{
	/*-- Locates all tharglets in range and tells them you've gone --*/
	if (!universe)
		return;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
	//
	double d2;
	double found_d2 = SCANNER_MAX_RANGE2;
	for (i = 0; i < ship_count ; i++)
	{
		ShipEntity* ship = (ShipEntity *)my_entities[i];
		d2 = distance2( position, ship->position);
		if ((d2 < found_d2)&&([[ship roles] isEqual:@"tharglet"]))
			[[ship getAI] message:@"THARGOID_DESTROYED"];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//	released
}

- (void) broadcastHitByLaserFrom:(ShipEntity*) aggressor_ship
{
	/*-- If you're clean, locates all police and stations in range and tells them OFFENCE_COMMITTED --*/
//	NSLog(@"DEBUG IN [%@ broadcastHitByLaserFrom:%@]", self, aggressor_ship);
	if (!universe)
		return;
	if (bounty)
		return;
	if (!aggressor_ship)
		return;
	if (	(scan_class == CLASS_NEUTRAL)||
			(scan_class == CLASS_STATION)||
			(scan_class == CLASS_BUOY)||
			(scan_class == CLASS_POLICE)||
			(scan_class == CLASS_MILITARY)||
			(scan_class == CLASS_PLAYER))	// only for active ships...
	{
//		NSLog(@"DEBUG IN [%@ broadcastHitByLaserFrom:%@]", self, aggressor_ship);
		int			ent_count =		universe->n_entities;
		Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
		Entity*		my_entities[ent_count];
		int i;
		int ship_count = 0;
		StationEntity* mainStation = [universe station];
		for (i = 0; i < ent_count; i++)
			if ((uni_entities[i]->isShip)&&((uni_entities[i]->scan_class == CLASS_POLICE)||(uni_entities[i] == mainStation)))
				my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
		//
		for (i = 0; i < ship_count ; i++)
		{
			ShipEntity* ship = (ShipEntity *)my_entities[i];
			if (((ship == mainStation) && (within_station_aegis)) || (distance2( position, ship->position) < SCANNER_MAX_RANGE2))
			{
//				NSLog(@"DEBUG SENDING %@'s AI \"OFFENCE_COMMITTED\"", ship);
				[ship setFound_target: aggressor_ship];
				[[ship getAI] reactToMessage: @"OFFENCE_COMMITTED"];
			}
			[my_entities[i] release];		//	released
		}
	}
}
- (NSArray *) shipsInGroup:(int) ship_group_id
{
	//-- Locates all the ships with this particular group id --//
	NSMutableArray* result = [NSMutableArray arrayWithCapacity:20];	// is autoreleased
	if (!universe)
		return (NSArray *)result;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
	//
	for (i = 0; i < ship_count ; i++)
	{
		ShipEntity* ship = (ShipEntity *)my_entities[i];
		if ([ship group_id] == ship_group_id)
			[result addObject: ship];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//	released
	return (NSArray *)result;
}

- (void) sendExpandedMessage:(NSString *) message_text toShip:(ShipEntity*) other_ship
{
	if (!other_ship)
		return;
	if ((lastRadioMessage) && (message_time > 0.0) && [message_text isEqual:lastRadioMessage])
		return;	// don't send the same message too often
	[lastRadioMessage autorelease];
	lastRadioMessage = [message_text retain];
	Vector delta = other_ship->position;
	delta.x -= position.x;  delta.y -= position.y;  delta.z -= position.z;
	double d2 = delta.x*delta.x + delta.y*delta.y + delta.z*delta.z;
	if (d2 > scanner_range * scanner_range)
		return;					// out of comms range
	if (!other_ship)
		return;
	NSMutableString* localExpandedMessage = [NSMutableString stringWithString:message_text];
	[localExpandedMessage	replaceOccurrencesOfString:@"[self:name]"
							withString:name
							options:NSLiteralSearch range:NSMakeRange( 0, [localExpandedMessage length])];
	[localExpandedMessage	replaceOccurrencesOfString:@"[target:name]"
							withString:[other_ship identFromShip: self]
							options:NSLiteralSearch range:NSMakeRange( 0, [localExpandedMessage length])];

	Random_Seed very_random_seed;
	very_random_seed.a = rand() & 255;
	very_random_seed.b = rand() & 255;
	very_random_seed.c = rand() & 255;
	very_random_seed.d = rand() & 255;
	very_random_seed.e = rand() & 255;
	very_random_seed.f = rand() & 255;
	seed_RNG_only_for_planet_description(very_random_seed);
	NSString* expandedMessage = [universe expandDescription:localExpandedMessage forSystem:[universe systemSeed]];
	[self setCommsMessageColor];
	[other_ship receiveCommsMessage:[NSString stringWithFormat:@"%@:\n %@", name, expandedMessage]];
	if (other_ship->isPlayer)
		message_time = 6.0;
	[universe resetCommsLogColor];
}

- (void) broadcastMessage:(NSString *) message_text
{
	/*-- Locates all the stations, bounty hunters and police ships in range and tells them your message --*/
	NSString* expandedMessage = [NSString stringWithFormat:@"%@:\n %@", name, [universe expandDescription:message_text forSystem:[universe systemSeed]]];

	if (!universe)
		return;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if (uni_entities[i]->isShip)
			my_entities[ship_count++] = [uni_entities[i] retain];		//	retained
	//
	double d2;
	double found_d2 = scanner_range * scanner_range;
	found_target = NO_TARGET;
	[self setCommsMessageColor];
	for (i = 0; i < ship_count ; i++)
	{
		ShipEntity* ship = (ShipEntity *)my_entities[i];
		d2 = distance2( position, ship->position);
		if (d2 < found_d2)
		{
			[ship receiveCommsMessage: expandedMessage];
			if (ship->isPlayer)
				message_time = 6.0;
		}
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];		//	released
	[universe resetCommsLogColor];
}

- (void) setCommsMessageColor
{
	float hue = 0.0625 * (universal_id & 15);
	[[universe comm_log_gui] setTextColor:[OOColor colorWithCalibratedHue:hue saturation:0.375 brightness:1.0 alpha:1.0]];
	if (scan_class == CLASS_THARGOID)
		[[universe comm_log_gui] setTextColor:[OOColor greenColor]];
	if (scan_class == CLASS_POLICE)
		[[universe comm_log_gui] setTextColor:[OOColor cyanColor]];
}

- (void) receiveCommsMessage:(NSString *) message_text
{
	// ignore messages for now
}

- (BOOL) markForFines
{
	if (being_fined)
		return NO;	// can't mark twice
	being_fined = ([self legal_status] > 0);
	return being_fined;
}

- (BOOL) isMining
{
	return ((behaviour == BEHAVIOUR_ATTACK_MINING_TARGET)&&(forward_weapon_type == WEAPON_MINING_LASER));
}

- (void) setNumberOfMinedRocks:(int) value
{
	if (![roles isEqual:@"asteroid"])
		return;
	likely_cargo = value;
}

- (void) interpretAIMessage:(NSString *)ms
{
	if ([ms hasPrefix:AIMS_AGGRESSOR_SWITCHED_TARGET])
	{
		// if I'm under attack send a thank-you message to the rescuer
		//
		NSArray* tokens = [Entity scanTokensFromString:ms];
		int switcher_id = [(NSString*)[tokens objectAtIndex:1] intValue];
		Entity* switcher = [universe entityForUniversalID:switcher_id];
		int rescuer_id = [(NSString*)[tokens objectAtIndex:2] intValue];
		Entity* rescuer = [universe entityForUniversalID:rescuer_id];
		if ((switcher_id == primaryAggressor)&&(switcher_id == primaryTarget)&&(switcher)&&(rescuer)&&(rescuer->isShip)&&(thanked_ship_id != rescuer_id)&&(scan_class != CLASS_THARGOID))
		{
			if (scan_class == CLASS_POLICE)
				[self sendExpandedMessage:@"[police-thanks-for-assist]" toShip:(ShipEntity*)rescuer];
			else
				[self sendExpandedMessage:@"[thanks-for-assist]" toShip:(ShipEntity*)rescuer];
			thanked_ship_id = rescuer_id;
			[(ShipEntity*)switcher setBounty:[(ShipEntity*)switcher getBounty] + 5 + (ranrot_rand() & 15)];	// reward
		}
	}
}

- (BoundingBox) findBoundingBoxRelativeTo:(Entity *)other InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector  opv = (other)? other->position : position;
	return [self findBoundingBoxRelativeToPosition:opv InVectors:_i :_j :_k];
}

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector	pv, rv;
	Vector  rpos = position;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;	// model origin relative to opv
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);	// model origin rel to opv in ijk
	BoundingBox result;
	if (n_vertices < 1)
		bounding_box_reset_to_vector(&result,rv);
	else
	{
		pv.x = rpos.x + v_right.x * vertices[0].x + v_up.x * vertices[0].y + v_forward.x * vertices[0].z;
		pv.y = rpos.y + v_right.y * vertices[0].x + v_up.y * vertices[0].y + v_forward.y * vertices[0].z;
		pv.z = rpos.z + v_right.z * vertices[0].x + v_up.z * vertices[0].y + v_forward.z * vertices[0].z;	// vertices[0] position rel to opv
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);	// vertices[0] position rel to opv in ijk
		bounding_box_reset_to_vector(&result,rv);
    }
	int i;
    for (i = 1; i < n_vertices; i++)
    {
		pv.x = rpos.x + v_right.x * vertices[i].x + v_up.x * vertices[i].y + v_forward.x * vertices[i].z;
		pv.y = rpos.y + v_right.y * vertices[i].x + v_up.y * vertices[i].y + v_forward.y * vertices[i].z;
		pv.z = rpos.z + v_right.z * vertices[i].x + v_up.z * vertices[i].y + v_forward.z * vertices[i].z;
		rv.x = dot_product(_i,pv);
		rv.y = dot_product(_j,pv);
		rv.z = dot_product(_k,pv);
		bounding_box_add_vector(&result,rv);
    }

	return result;
}

- (void) spawn:(NSString *)roles_number
{
	NSArray*	tokens = [Entity scanTokensFromString:roles_number];
	NSString*   roleString = nil;
	NSString*	numberString = nil;

	if ([tokens count] != 2)
	{
		NSLog(@"***** CANNOT SPAWN: '%@'",roles_number);
		return;
	}

	roleString = (NSString *)[tokens objectAtIndex:0];
	numberString = (NSString *)[tokens objectAtIndex:1];

	int number = [numberString intValue];

	if (debug & DEBUG_SCRIPT)
		NSLog(@"DEBUG ..... Going to spawn %d x '%@' near %@ %d", number, roleString, name, universal_id);

	while (number--)
		[universe spawnShipWithRole:roleString near:self];
}

- (int) checkShipsInVicinityForWitchJumpExit
{
	// checks if there are any large masses close by
	// since we want to place the space station at least 10km away
	// the formula we'll use is K x m / d2 < 1.0
	// (m = mass, d2 = distance squared)
	// coriolis station is mass 1,000,000,000
	// 10km is 10,000m,
	// 10km squared is 100,000,000
	// therefore K is 0.10

	int result = NO_TARGET;

	GLfloat k = 0.1;

	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	ShipEntity*	my_entities[ent_count];
	int i;

	int ship_count = 0;
	for (i = 0; i < ent_count; i++)
		if ((uni_entities[i]->isShip)&&(uni_entities[i] != self))
			my_entities[ship_count++] = (ShipEntity*)[uni_entities[i] retain];		//	retained
	//
	for (i = 0; (i < ship_count)&&(result == NO_TARGET) ; i++)
	{
		ShipEntity* ship = my_entities[i];
		Vector delta = ship->position;
		delta.x -= position.x;	delta.y -= position.y;	delta.z -= position.z;
		if ((delta.x < 10000.0)&&(delta.y < 10000.0)&&(delta.z < 10000.0)&&( k * [ship mass] / magnitude2(delta) > 1.0))
			result = [ship universal_id];
	}
	for (i = 0; i < ship_count; i++)
		[my_entities[i] release];	//		released

	return result;
}

- (void) setTrackCloseContacts:(BOOL) value
{
	if (value == trackCloseContacts)
		return;
	trackCloseContacts = value;
	if (trackCloseContacts)
	{
		if (closeContactsInfo)
			[closeContactsInfo removeAllObjects];
		else
			closeContactsInfo = [[NSMutableDictionary dictionaryWithCapacity:16] retain];
	}
	else
	{
		if (closeContactsInfo)
			[closeContactsInfo release];
		closeContactsInfo = nil;
	}
}

#ifdef WIN32
// No over-ride of Entity's version of the method is required for non-Win32 platforms.
- (void) reloadTextures
{
	//NSLog(@"ShipEntity::reloadTextures called, resetting subentities and calling super");
	int i;
	for (i = 0; i < [sub_entities count]; i++)
	{
		Entity *e = (Entity *)[sub_entities objectAtIndex:i];
		//NSLog(@"ShipEntity::reloadTextures calling reloadTextures on: %@", [e description]);
		[e reloadTextures];
	}

	// Reset the entity display list.
	[super reloadTextures];
}

#endif

@end
