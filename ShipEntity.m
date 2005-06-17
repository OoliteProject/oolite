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
#import "entities.h"

#import "vector.h"
#import "Universe.h"

#import "AI.h"


@implementation ShipEntity

- (id) init
{    
    self = [super init];
	//
	// scripting
	launch_actions = [[NSMutableArray alloc] initWithCapacity:4];
	script_actions = [[NSMutableArray alloc] initWithCapacity:4];
	death_actions = [[NSMutableArray alloc] initWithCapacity:4];
	//
	// escorts
	//escorts = [[NSMutableArray alloc] initWithCapacity:4];
	last_escort_target = NO_TARGET;
	n_escorts = 0;
    escortsAreSetUp = YES;
	//accepts_escorts = NO;
	//
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	//
	velocity = make_vector( 0.0, 0.0, 0.0);
	momentum = make_vector( 0.0, 0.0, 0.0);
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
	condition = CONDITION_IDLE;
	frustration = 0.0;
	//
	shipAI = [[AI alloc] init]; // alloc retains
	[shipAI setOwner:self];
	[shipAI setState:@"GLOBAL"];
	//
	max_cargo = RAIDER_MAX_CARGO;
	likely_cargo = 0;
	cargo_type = 0;
	cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	cargo_flag = CARGO_FLAG_NONE;
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
	laser_color = [[NSColor redColor] retain];
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
	return self;
}

- (void) dealloc
{
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
	
	if (collisionVectorForEntity)
							[collisionVectorForEntity release];
	[super dealloc];
}

- (NSString*) description
{
	NSString* result = [[NSString alloc] initWithFormat:@"<ShipEntity %@ %d (%@) %@>", name, universal_id, roles, (universe == nil)? @" (not in universe)":@""];
	return [result autorelease];
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
		}
	}
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
		[escorter setBounty:0];
		[escorter setStatus:STATUS_IN_FLIGHT];
		
		[escorter setRoles:escortRole];
		
		[escorter setScanClass:scan_class];		// you are the same as I
		
		//[escorter setReportAImessages: (i == 0) ? YES:NO ]; // debug

		[universe addEntity:escorter];
		[[escorter getAI] setStateMachine:@"escortAI.plist"];	// must happen after adding to the universe!
		
		[escorter setGroup_id:universal_id];
		[self setGroup_id:universal_id];		// make self part of same group
		
		[[escorter getAI] setState:@"FLYING_ESCORT"];	// begin immediately
		
//		NSLog(@"DEBUG set up escort ship %@ %d for %@ %@ %d", [escorter name], [escorter universal_id], roles, name, universal_id);
						
		[escorter release];
		n_escorts--;
	}
}


- (void) reinit
{
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
	position = make_vector( 0.0, 0.0, 0.0);
	velocity = make_vector( 0.0, 0.0, 0.0);
	momentum = make_vector( 0.0, 0.0, 0.0);
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
	condition = CONDITION_IDLE;
	frustration = 0.0;
	//
	if (!shipAI)
		shipAI = [[AI alloc] init]; // alloc retains
	[shipAI setOwner:self];
	[shipAI setState:@"GLOBAL"];
	//
	max_cargo = 0;
	likely_cargo = 0;
	cargo_type = 0;
	cargo_flag = CARGO_FLAG_NONE;
	if (!cargo)
		cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	[cargo removeAllObjects];
	//
	owner = NO_TARGET;
	//
	reportAImessages = NO;
	//
	if (previousCondition) [previousCondition release];
	previousCondition = nil;
	//
	if (sub_entities) [sub_entities release];
	sub_entities = nil;
	//
	scanner_range = 25600.0;
	//
	if (shipinfoDictionary)
		[shipinfoDictionary release];
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
	[collisionVectorForEntity removeAllObjects];
	//
	beaconChar = 0;
	//
	isShip = YES;
	//
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
	position = make_vector( 0.0, 0.0, 0.0);
	velocity = make_vector( 0.0, 0.0, 0.0);
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
	condition = CONDITION_IDLE;
	frustration = 0.0;
	//
	patrol_counter = 0;
	//
	scan_class = CLASS_NOT_SET;
	//
	[self setUpShipFromDictionary:dict];
	//
	reportAImessages = NO;
	//
	being_fined = NO;
	//
	isShip = YES;
	//
	return self;
}


- (void) setUpShipFromDictionary:(NSDictionary *) dict
{
    NSString*   cargo_type_string;
    //NSString*   ai_type_string;
    NSString*   weapon_type_string;
	
	// reset all settings
	[self reinit];
	
	if (collisionVectorForEntity)
		[collisionVectorForEntity removeAllObjects];
	else
		collisionVectorForEntity = [[NSMutableDictionary alloc] initWithCapacity:12];
	
	shipinfoDictionary = [[NSDictionary alloc] initWithDictionary:dict];	// retained
	
	//
	// set things from dictionary from here out
	//
	if ([dict objectForKey:@"max_flight_speed"])
		max_flight_speed = [(NSNumber *)[dict objectForKey:@"max_flight_speed"] doubleValue];
	if ([dict objectForKey:@"max_flight_roll"])
		max_flight_roll = [(NSNumber *)[dict objectForKey:@"max_flight_roll"] doubleValue];
	if ([dict objectForKey:@"max_flight_pitch"])
		max_flight_pitch = [(NSNumber *)[dict objectForKey:@"max_flight_pitch"] doubleValue];
	//
	if ([dict objectForKey:@"thrust"])
		thrust = [(NSNumber *)[dict objectForKey:@"thrust"] doubleValue];
	//
	if ([dict objectForKey:@"accuracy"])
	{
		int accuracy = [(NSNumber *)[dict objectForKey:@"accuracy"] intValue];
		if ((accuracy >= -5)&&(accuracy <= 10))
			pitch_tolerance = 0.01 * (85 + accuracy);
	}
	//
	if ([dict objectForKey:@"max_energy"])
		max_energy = [(NSNumber *)[dict objectForKey:@"max_energy"] doubleValue];
	if ([dict objectForKey:@"energy_recharge_rate"])
		energy_recharge_rate = [(NSNumber *)[dict objectForKey:@"energy_recharge_rate"] doubleValue];
	energy = max_energy;
	//
	if ([dict objectForKey:@"weapon_offset_x"])
		weapon_offset_x = [(NSNumber *)[dict objectForKey:@"weapon_offset_x"] doubleValue];
	//
	if ([dict objectForKey:@"aft_weapon_type"])
	{
		weapon_type_string = (NSString *)[dict objectForKey:@"aft_weapon_type"];
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
	if ([dict objectForKey:@"forward_weapon_type"])
	{
		weapon_type_string = (NSString *)[dict objectForKey:@"forward_weapon_type"];
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
	if ([dict objectForKey:@"weapon_energy"])
		weapon_energy = [(NSNumber *)[dict objectForKey:@"weapon_energy"] doubleValue];
	//
	if ([dict objectForKey:@"scanner_range"])
		scanner_range = [(NSNumber *)[dict objectForKey:@"scanner_range"] doubleValue];
	//
	if ([dict objectForKey:@"missiles"])
		missiles = [(NSNumber *)[dict objectForKey:@"missiles"] intValue];
		
	// upgrades:	
	//		did use [NSNumber boolValue], but now have a random chance instead
	//
	if ([dict objectForKey:@"has_ecm"])
		has_ecm = (randf() < [(NSNumber *)[dict objectForKey:@"has_ecm"] floatValue]);
	if ([dict objectForKey:@"has_scoop"])
		has_scoop = (randf() < [(NSNumber *)[dict objectForKey:@"has_scoop"] floatValue]);
	if ([dict objectForKey:@"has_escape_pod"])
		has_escape_pod = (randf() < [(NSNumber *)[dict objectForKey:@"has_escape_pod"] floatValue]);
	if ([dict objectForKey:@"has_energy_bomb"])
		has_energy_bomb = (randf() < [(NSNumber *)[dict objectForKey:@"has_energy_bomb"] floatValue]);
	if ([dict objectForKey:@"has_fuel_injection"])
		has_fuel_injection = (randf() < [(NSNumber *)[dict objectForKey:@"has_fuel_injection"] floatValue]);
	//
	if ([dict objectForKey:@"has_shield_booster"])
		max_energy += (randf() < [(NSNumber *)[dict objectForKey:@"has_shield_booster"] floatValue])? 256:0;
	if ([dict objectForKey:@"has_shield_enhancer"])
	{
		max_energy += (randf() < [(NSNumber *)[dict objectForKey:@"has_shield_enhancer"] floatValue])? 256:0;
		energy_recharge_rate *= 1.5;
	}
	//
	if ([dict objectForKey:@"has_cloaking_device"])
		has_cloaking_device = (randf() < [(NSNumber *)[dict objectForKey:@"has_cloaking_device"] floatValue]);
	//
	cloaking_device_active = NO;
	//
	if ([dict objectForKey:@"has_military_jammer"])
		has_military_jammer = (randf() < [(NSNumber *)[dict objectForKey:@"has_military_jammer"] floatValue]);
	//
	military_jammer_active = NO;
	//
	if ([dict objectForKey:@"has_military_scanner_filter"])
		has_military_scanner_filter = (randf() < [(NSNumber *)[dict objectForKey:@"has_military_scanner_filter"] floatValue]);
	//
	// /upgrades
	
	if ([dict objectForKey:@"fuel"])
		fuel = [(NSNumber *)[dict objectForKey:@"fuel"] intValue];
		
	//
	if ([dict objectForKey:@"bounty"])
		bounty = [(NSNumber *)[dict objectForKey:@"bounty"] intValue];
	//
	if ([dict objectForKey:@"ai_type"])
	{
		if (shipAI)
			[shipAI autorelease];
		shipAI = [[AI alloc] init]; // alloc retains
		[shipAI setOwner:self];
		[shipAI setStateMachine:(NSString *)[dict objectForKey:@"ai_type"]];
		[shipAI setState:@"GLOBAL"];
	}
	//
	if ([dict objectForKey:@"max_cargo"])
		max_cargo = [(NSNumber *)[dict objectForKey:@"max_cargo"] intValue];
	if ([dict objectForKey:@"likely_cargo"])
		likely_cargo = [(NSNumber *)[dict objectForKey:@"likely_cargo"] intValue];
	//
	if ([dict objectForKey:@"cargo_carried"])
	{
		cargo_flag = CARGO_FLAG_FULL_UNIFORM;
	}
	//
	if ([dict objectForKey:@"cargo_type"])
	{
		cargo_type_string = (NSString *)[dict objectForKey:@"cargo_type"];
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
		if ([cargo_type_string isEqual:@"CARGO_RANDOM"])
			cargo_type = CARGO_RANDOM;
		if ([cargo_type_string isEqual:@"CARGO_SCRIPTED_ITEM"])
			cargo_type = CARGO_SCRIPTED_ITEM;
		if (cargo)
			[cargo autorelease];
		cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo]; // alloc retains;
	}
	//
	// A HACK!! - must do this before the model is set
	if ([dict objectForKey:@"smooth"])
		is_smooth_shaded = YES;
	else
		is_smooth_shaded = NO;
	//
	if ([dict objectForKey:@"model"])
		[self setModel:(NSString *)[dict objectForKey:@"model"]];
	//
	if ([dict objectForKey:KEY_NAME])
	{
		if (name)
			[name release];
		name = [[NSString stringWithString:(NSString *)[dict objectForKey:KEY_NAME]] retain];
	}
	//
	if ([dict objectForKey:@"roles"])
	{
		if (roles)
			[roles release];
		roles = [[NSString stringWithString:(NSString *)[dict objectForKey:@"roles"]] retain];
	}
	//
	[self setOwner:self];
	//
	if ([dict objectForKey:@"exhaust"])
	{
		int i;
		NSArray *plumes = (NSArray *)[dict objectForKey:@"exhaust"];
		for (i = 0; i < [plumes count]; i++)
		{
			ParticleEntity *exhaust = [[ParticleEntity alloc] initExhaustFromShip:self details:(NSString *)[plumes objectAtIndex:i]];
			[self addExhaust:exhaust];
			[exhaust release];
		}
	}		
	//	
	if ((universe)&&([dict objectForKey:@"subentities"]))
	{
		//NSLog(@"DEBUG adding subentity...");
		int i;
		NSArray *subs = (NSArray *)[dict objectForKey:@"subentities"];
		for (i = 0; i < [subs count]; i++)
		{
			NSArray* details = [(NSString *)[subs objectAtIndex:i] componentsSeparatedByString:@" "];
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
					[(ParticleEntity*)subent setColor:[NSColor colorWithCalibratedHue: sub_q.w/360.0 saturation:1.0 brightness:1.0 alpha:1.0]];
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
					
					subent = [universe getShip:subdesc];	// retained -- ODDLY UNIVERSE SEEMS SOMETIMES TO BE NIL HERE ?!!! - FIXED
					
//					NSLog(@"DEBUG adding subentity %@ %@ to new %@ at %.3f,%.3f,%.3f", subent, [(ShipEntity*)subent name], name, sub_pos.x, sub_pos.y, sub_pos.z );
					[(ShipEntity*)subent setStatus:STATUS_INACTIVE];
					if ([[(ShipEntity*)subent roles] isEqual:@"docking-slit"])
						[subent setStatus:STATUS_EFFECT];			// hack keeps docking slit visible when at reduced detail
					//
					ref = vector_forward_from_quaternion(sub_q);	// VECTOR FORWARD
					//
					[(ShipEntity*)subent setReference: ref];
					[(ShipEntity*)subent setPosition:sub_pos];
					[(ShipEntity*)subent setQRotation:sub_q];
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
	//	
	if ([dict objectForKey:@"laser_color"])
	{
		NSString *laser_color_string = (NSString *)[dict objectForKey:@"laser_color"];
		SEL color_selector = NSSelectorFromString(laser_color_string);
		if ([NSColor respondsToSelector:color_selector])
		{
			id  color_thing = [NSColor performSelector:color_selector];
			if ([color_thing isKindOfClass:[NSColor class]])
				[self setLaserColor:(NSColor *)color_thing];
		}
	}   
	else
		[self setLaserColor:[NSColor redColor]];
	//
	// scan class
	if ([dict objectForKey:@"scanClass"])
	{
		NSString *s_class= (NSString *)[dict objectForKey:@"scanClass"];
		
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
		if ([s_class isEqual:@"CLASS_NEUTRAL"])
			scan_class = CLASS_NEUTRAL;
		if ([s_class isEqual:@"CLASS_ROCK"])
			scan_class = CLASS_ROCK;
	}
	else
		scan_class = CLASS_NOT_SET;
	//
	// scripting	
	if ([dict objectForKey:KEY_LAUNCH_ACTIONS])
		[launch_actions addObjectsFromArray:(NSArray *)[dict objectForKey:KEY_LAUNCH_ACTIONS]];
	if ([dict objectForKey:KEY_SCRIPT_ACTIONS])
		[script_actions addObjectsFromArray:(NSArray *)[dict objectForKey:KEY_SCRIPT_ACTIONS]];
	if ([dict objectForKey:KEY_DEATH_ACTIONS])
		[death_actions addObjectsFromArray:(NSArray *)[dict objectForKey:KEY_DEATH_ACTIONS]];
	if ([dict objectForKey:KEY_SETUP_ACTIONS])
	{
		PlayerEntity* player = (PlayerEntity*)[universe entityZero];
		[player setScript_target:self];
		NSArray * setup_actions = (NSArray *)[dict objectForKey:KEY_SETUP_ACTIONS];
		int i;
		for (i = 0; i < [setup_actions count]; i++)
		{
			if ([[setup_actions objectAtIndex:i] isKindOfClass:[NSDictionary class]])
				[player checkCouplet:(NSDictionary *)[setup_actions objectAtIndex:i] onEntity:self];
			if ([[setup_actions objectAtIndex:i] isKindOfClass:[NSString class]])
				[player scriptAction:(NSString *)[setup_actions objectAtIndex:i] onEntity:self];
		}
	}
	
	//  escorts
	//
	if ([dict objectForKey:@"escorts"])
	{
		n_escorts = [(NSNumber *)[dict objectForKey:@"escorts"] intValue];
		//NSLog(@"DEBUG adding %d escorts for new %@", n_escorts, name);
		escortsAreSetUp = (n_escorts == 0);
	}
	
	// beacons
	//
	if ([dict objectForKey:@"beacon"])
	{
		NSString* beaconCode = (NSString*)[dict objectForKey:@"beacon"];
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
	if ([dict objectForKey:@"rotational_velocity"])
	{
		subentity_rotational_velocity = [Entity quaternionFromString: (NSString*)[dict objectForKey:@"rotational_velocity"]];
	}
	else
	{
		quaternion_set_identity(&subentity_rotational_velocity);
	}

}

- (int) scanClass
{
	if (cloaking_device_active)
		return CLASS_NO_DRAW;
	else
		return scan_class;
}

//////////////////////////////////////////////

- (BOOL) canCollide
{
	if ((status == STATUS_DEMO)||(status == STATUS_DEAD))
		return NO;
	if ((scan_class == CLASS_MISSILE)&&(shot_time < 0.25)) // not yet fused
		return NO;
	if ((shot_time < 0.25)&&([roles isEqual:@"tharglet"])) // not yet fused
		return NO;
	return YES;
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (!other)
		return NO;
	if ([collidingEntities containsObject:other])	// we know about this already!
		return NO;
	if (other->isShip)
	{
		// check bounding boxes ...
		//
		// get bounding box relative to this ship's orientation
		BoundingBox arbb = [other findBoundingBoxRelativeTo:self InVectors: v_right: v_up: v_forward];
		
		// construct 6 rectangles based on the sides of the possibly overlapping bounding boxes
		NSRect  ship_x_rect = NSMakeRect(boundingBox.min_z, boundingBox.min_y, boundingBox.max_z - boundingBox.min_z, boundingBox.max_y - boundingBox.min_y);
		NSRect  ship_y_rect = NSMakeRect(boundingBox.min_x, boundingBox.min_z, boundingBox.max_x - boundingBox.min_x, boundingBox.max_z - boundingBox.min_z);
		NSRect  ship_z_rect = NSMakeRect(boundingBox.min_x, boundingBox.min_y, boundingBox.max_x - boundingBox.min_x, boundingBox.max_y - boundingBox.min_y);

		NSRect  other_x_rect = NSMakeRect(arbb.min_z, arbb.min_y, arbb.max_z - arbb.min_z, arbb.max_y - arbb.min_y);
		NSRect  other_y_rect = NSMakeRect(arbb.min_x, arbb.min_z, arbb.max_x - arbb.min_x, arbb.max_z - arbb.min_z);
		NSRect  other_z_rect = NSMakeRect(arbb.min_x, arbb.min_y, arbb.max_x - arbb.min_x, arbb.max_y - arbb.min_y);

		if (NSIntersectsRect(ship_x_rect,other_x_rect) && NSIntersectsRect(ship_y_rect,other_y_rect) && NSIntersectsRect(ship_z_rect,other_z_rect))
//			return [self checkPerPolyCollisionWithShip:(ShipEntity*)other];
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
		if	((r_pos.x + cr > boundingBox.min_x)&&
				(r_pos.x - cr < boundingBox.max_x)&&
				(r_pos.y + cr > boundingBox.min_y)&&
				(r_pos.y - cr < boundingBox.max_y)&&
				(r_pos.z + cr > boundingBox.min_z)&&
				(r_pos.z - cr < boundingBox.max_z))
//			return [self checkPerPolyCollisionWithParticle:(ParticleEntity*)other];
			return YES;
		else
			return NO;
	}
	return YES;
}

- (BOOL) checkPerPolyCollisionWithShip:(ShipEntity *)other
{
//	NSLog(@"DEBUG checking per poly collision %@ %d versus %@ %d", name, universal_id, [other name], [other universal_id]);
//	NSLog(@"DEBUG %@ %d n_faces %d n_vertices %d", name, universal_id, n_faces, n_vertices);
	
	// DEBUG - TEMPORARY
//	return YES;
	
	// check each surface versus the other's particle cloud ...
	//
	int f;
	BOOL all_clear =	YES;
	int surfs_hit =		0;
	Vector	incidence = make_vector( 0, 0, 0);
	Vector	direction = make_vector( 0, 0, 0);
	for (f = 0; f < n_faces; f++)
	{
		face_hit[f] = NO;
		
		Vector v0 = vertices[faces[f].vertex[0]];
		Vector v1 = vertices[faces[f].vertex[1]];
		Vector v2 = vertices[faces[f].vertex[2]];

		mult_vector_gl_matrix(&v0, rotMatrix);
		mult_vector_gl_matrix(&v1, rotMatrix);
		mult_vector_gl_matrix(&v2, rotMatrix);

		Vector vi = make_vector(v1.x - v0.x, v1.y - v0.y, v1.z - v0.z);
		Vector vj = make_vector(v2.x - v0.x, v2.y - v0.y, v2.z - v0.z);
		Vector vs = faces[f].normal;
		mult_vector_gl_matrix(&vs, rotMatrix);
		
		// get bounding box relative to this surface's orientation
		BoundingBox arbb = [other findBoundingBoxRelativeToPosition:make_vector(position.x+v0.x,position.y+v0.y, position.z+v0.z) InVectors: vi : vj : vs];
		
		if	((arbb.max_x < 0.0)					// all p.vi < 0
			||(arbb.min_x > 1.0)				// all p.vi > 1
			||(arbb.max_y < 0.0)				// all p.vj < 0
			||(arbb.min_y > 1.0)				// all p.vj > 1
			||(arbb.min_x + arbb.min_y > 1.0)	// all p.vi + p.vj > 1
			||(arbb.min_z > 0.0)				// all p.vs > 0
			||(arbb.max_z < 0.0))				// all p.vs < 0
			continue;							// this surface doesn't intersect the point cloud;
		else
		{
			// this surface intersects the point cloud
			incidence.x += vs.x;	incidence.y += vs.y;	incidence.z += vs.z;
			
			Vector	 dir = make_vector( v0.x + v1.x + v2.x, v0.y + v1.y + v2.y, v0.z + v1.z + v2.z);
			dir = unit_vector(&dir);
			direction.x += dir.x;	direction.y += dir.y;	direction.z += dir.z;
			
			face_hit[f] = YES;
			all_clear = NO;
			surfs_hit++;
		}
	}
	if (!all_clear)
	{
		collision_vector = unit_vector(&incidence);
		if (isnan(collision_vector.x)||isnan(collision_vector.y)||isnan(collision_vector.z))
			collision_vector = unit_vector(&direction);
		
//		NSLog(	@"Ship %@ %d versus other %@ %d collision, %d surfaces intersected, incidence [%.3f, %.3f, %.3f]",
//				name, universal_id, [other name], [other universal_id],
//				surfs_hit, collision_vector.x, collision_vector.y, collision_vector.z);
		
		[collisionVectorForEntity
			setObject:[NSArray arrayWithObjects:	[NSNumber numberWithFloat:collision_vector.x],
													[NSNumber numberWithFloat:collision_vector.y],
													[NSNumber numberWithFloat:collision_vector.z], nil]
			forKey:[NSString stringWithFormat:@"%@", other]];
		
		return YES;
	}	
	return NO;
}

- (BOOL) checkPerPolyCollisionWithParticle:(ParticleEntity *)other
{
//	NSLog(@"DEBUG checking per poly collision %@ %d versus particle", name, universal_id);
	
	if (!other)
		return NO;
	
	// check bounding boxes ...
	//
	// get position relative to this ship's orientation
	Vector	o_pos = other->position;
	o_pos.x -= position.x;	o_pos.y -= position.y;	o_pos.z -= position.z;
	double	cr = other->collision_radius;

	int f;
	BOOL all_clear =	YES;
	int surfs_hit =		0;
	Vector	incidence = make_vector( 0, 0, 0);
	Vector	direction = make_vector( 0, 0, 0);
	for (f = 0; f < n_faces; f++)
	{
		Vector v0 = vertices[faces[f].vertex[0]];
		Vector v1 = vertices[faces[f].vertex[1]];
		Vector v2 = vertices[faces[f].vertex[2]];

		mult_vector_gl_matrix(&v0, rotMatrix);
		mult_vector_gl_matrix(&v1, rotMatrix);
		mult_vector_gl_matrix(&v2, rotMatrix);

		Vector vs = faces[f].normal;
		mult_vector_gl_matrix(&vs, rotMatrix);
					
		Vector q0 = make_vector( o_pos.x - v0.x, o_pos.y - v0.y, o_pos.z - v0.z);
		GLfloat dist = dot_product( q0, vs);

		if	(dist < cr)	// p2 inside sphere
		{
			// this surface intersects the sphere
			incidence.x += vs.x;	incidence.y += vs.y;	incidence.z += vs.z;

			Vector	 dir = make_vector( v0.x + v1.x + v2.x, v0.y + v1.y + v2.y, v0.z + v1.z + v2.z);
			dir = unit_vector(&dir);
			direction.x += dir.x;	direction.y += dir.y;	direction.z += dir.z;
			
			all_clear = NO;
			surfs_hit++;
		}

	}
	if (!all_clear)
	{
		collision_vector = unit_vector(&incidence);
		if (isnan(collision_vector.x)||isnan(collision_vector.y)||isnan(collision_vector.z))
			collision_vector = unit_vector(&direction);
		
//			NSLog(	@"Ship %@ %d versus particle collision, %d surfaces intersected, incidence [%.3f, %.3f, %.3f]",
//					name, universal_id, surfs_hit, collision_vector.x, collision_vector.y, collision_vector.z);
		
		[collisionVectorForEntity
			setObject:[NSArray arrayWithObjects:	[NSNumber numberWithFloat:collision_vector.x],
													[NSNumber numberWithFloat:collision_vector.y],
													[NSNumber numberWithFloat:collision_vector.z], nil]
			forKey:[NSString stringWithFormat:@"%@", other]];
		
		return YES;
	}
	return NO;
}

- (Vector) collisionVectorForEntity:(Entity *)other
{
	Vector v = make_vector (0,0,0);
	if ([collisionVectorForEntity objectForKey:[NSString stringWithFormat:@"%@", other]])
	{
		NSArray* va = (NSArray*)[collisionVectorForEntity objectForKey:[NSString stringWithFormat:@"%@", other]];
		v.x = [(NSNumber*)[ va objectAtIndex:0] floatValue];
		v.y = [(NSNumber*)[ va objectAtIndex:1] floatValue];
		v.z = [(NSNumber*)[ va objectAtIndex:2] floatValue];
	}
	return v;
}

- (void) update:(double) delta_t
{
	double  damping = 0.5 * delta_t;
	double confidenceFactor;
	double targetCR;
#ifdef GNUSTEP
   int missile_chance=0;
   int rhs=(int)(32 * 0.1 / delta_t);
   if(rhs)
   {
      missile_chance = 1 + (ranrot_rand() % rhs);
   }
#else   
	int missile_chance = 1 + (ranrot_rand() % (int)( 32 * 0.1 / delta_t));
#endif   
	double	hurt_factor = 16 * pow(energy/max_energy, 4.0);
	double	last_success_factor = success_factor;
	//
	BOOL	canBurn = has_fuel_injection && (fuel > 0);
	BOOL	isUsingAfterburner = canBurn && (flight_speed > max_flight_speed);
	//
	double	max_available_speed = (canBurn)? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	//
	
	//
	// deal with collisions
	//
	[self manageCollisions];
	[self saveToLastFrame];

	// super update
	//
	[super update:delta_t];
	
	// DEBUGGING
	//
	if (reportAImessages && (debug_condition != condition))
	{
		NSLog(@"DEBUG %@ condition is now %d", self, condition);
		debug_condition = condition;
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
	
	
	// burning effects
	//
	if ((throw_sparks)||(energy < max_energy * 0.20))
	{
		if (energy_recharge_rate > 0.0)	// prevents asteroid etc. from burning
		{
			next_spark_time -= delta_t;
			if (next_spark_time < 0.0)
				[self throwSparks];
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
		int i;
		[(PlayerEntity *)[universe entityZero] setScript_target:self];
		for (i = 0; i < [launch_actions count]; i++)
			[(PlayerEntity *)[universe entityZero] scriptAction:(NSString *)[launch_actions objectAtIndex:i] onEntity:self];
		[launch_actions removeAllObjects];
	}
	
	// behaviours according to status and condition
    //
	if (status == STATUS_LAUNCHING)
	{
		if ([universe getTime] > launch_time + LAUNCH_DELAY)		// move for while before thinking
		{
			status = STATUS_IN_FLIGHT;
			//accepts_escorts = YES;
		}
		else
		{
			// ignore condition just keep moving...
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
	if (status == STATUS_DEMO)
    {
        [self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
		position.x += delta_t*velocity.x;
		position.y += delta_t*velocity.y;
		position.z += delta_t*velocity.z;
		if (position.z <= collision_radius * 3.6)
		{
			position.z = collision_radius * 3.6;
			velocity.z = 0.0;
		}
		return;
    }
	else
	{
		double  range = [self rangeToPrimaryTarget];
		double  distance = [self rangeToDestination];
		double  target_speed = max_flight_speed;
		double	slow_down_range = weapon_range * COMBAT_WEAPON_RANGE_FACTOR * ((isUsingAfterburner)? 2.0 * AFTERBURNER_FACTOR : 1.0);
		
		if (reportAImessages)
		{
			NSLog(@"DEBUG SPEED %@ [:%d:] range %.1f/%.1f slow_down_range (isUsingAfterBurner :%@:) (canBurn :%@:)",
				self, condition, range, slow_down_range, (isUsingAfterburner)?@"YES":@"NO", (canBurn)?@"YES":@"NO");
		}
		
		ShipEntity*	target = (ShipEntity*)[universe entityForUniversalID:primaryTarget];
		
		targetCR = (target)? target->collision_radius: 0;
		
		if ((target == nil)||(target->scan_class == CLASS_NO_DRAW))
		{
			 // It's no longer a parrot, it has ceased to be, it has joined the choir invisible...
			if (primaryTarget != NO_TARGET)
			{
//				NSLog(@"---> %@ %d has lost its target.", name, universal_id);
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
				
		switch (condition)
		{
			case CONDITION_IDLE :
				if ((scan_class != CLASS_STATION)&&(scan_class != CLASS_BUOY))
				{
					// damp roll and pitch
					if (flight_roll < 0)
						flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
					if (flight_roll > 0)
						flight_roll -= (flight_roll > damping) ? damping : flight_roll;
					if (flight_pitch < 0)
						flight_pitch += (flight_pitch < -damping) ? damping : -flight_pitch;
					if (flight_pitch > 0)
						flight_pitch -= (flight_pitch > damping) ? damping : flight_pitch;
				}
			case CONDITION_TUMBLE :
				break;

			case CONDITION_TRACK_TARGET :
				[self trackPrimaryTarget:delta_t:NO];
				if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
					[self avoidCollision];
				break;
				
			case CONDITION_INTERCEPT_TARGET :
			case CONDITION_COLLECT_TARGET :
				if (condition == CONDITION_INTERCEPT_TARGET)
				{
					desired_speed = max_flight_speed;
					if (range < desired_range)
						[shipAI reactToMessage:@"DESIRED_RANGE_ACHIEVED"];
					desired_speed = max_flight_speed * [self trackPrimaryTarget:delta_t:NO];
				}
				else
				{
					target_speed = [[self getPrimaryTarget] getVelocityAsSpeed];
					double eta = range / (flight_speed - target_speed);
					double last_distance = last_success_factor;
					success_factor = distance;
					//
					if ((eta < 3.0)&&(flight_speed > max_flight_speed * 0.02))
						desired_speed = flight_speed * 0.75;   // cut speed to a minimum of 2 % speed
					else
						desired_speed = max_flight_speed;
					if (desired_speed < target_speed)
					{
						desired_speed += target_speed;
						if (target_speed > max_flight_speed)
							[shipAI reactToMessage:@"TARGET_LOST"];
					}
					//
					[self trackPrimaryTarget:delta_t:NO];
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
//							[self setReportAImessages:YES];	//debug
							[shipAI reactToMessage:@"FRUSTRATED"];
//							NSLog(@"DEBUG %@ flight_speed %.6f distance %.6f last_distance %.6f", self, flight_speed, distance, last_distance);
//							[self setReportAImessages:NO];	//debug
							frustration -= 5.0;	//repeat after another five seconds' frustration
						}
					}
				}
				if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
					[self avoidCollision];
				break;
				
			case CONDITION_ATTACK_TARGET :
				[self activateCloakingDevice];
				desired_speed = max_available_speed;
				if (range < 0.035 * weapon_range)
					condition = CONDITION_ATTACK_FLY_FROM_TARGET;
				else
					if (universal_id & 1)	// 50% of ships are smart S.M.R.T. smart!
					{
						if (randf() < 0.75)
							condition = CONDITION_ATTACK_FLY_TO_TARGET_SIX;
						else
							condition = CONDITION_ATTACK_FLY_TO_TARGET_TWELVE;
					}
					else
					{
						condition = CONDITION_ATTACK_FLY_TO_TARGET;
					}
				frustration = 0.0;	// condition changed, so reset frustration
				break;
				
			case CONDITION_ATTACK_FLY_TO_TARGET_SIX :
			case CONDITION_ATTACK_FLY_TO_TARGET_TWELVE :
				
				// deal with collisions and lost targets
				//
				if (proximity_alert != NO_TARGET)
					[self avoidCollision];
				if (range > SCANNER_MAX_RANGE)
				{
					condition = CONDITION_IDLE;
					frustration = 0.0;
					[shipAI reactToMessage:@"TARGET_LOST"];
				}
				
				// control speed
				//
				if (range < slow_down_range)
				{
					desired_speed = target_speed;
					// avoid head-on collision
					//
					if ((range < 0.5 * distance)&&(condition == CONDITION_ATTACK_FLY_TO_TARGET_SIX))
						condition = CONDITION_ATTACK_FLY_TO_TARGET_TWELVE;
				}
				else
					desired_speed = max_available_speed; // use afterburner to approach
				
				
				// if within 0.75km of the target's six or twelve then vector in attack
				//
				if (distance < 750.0)
				{
					condition = CONDITION_ATTACK_FLY_TO_TARGET;
					frustration = 0.0;
					desired_speed = target_speed;   // within the weapon's range don't use afterburner
				}
				
				// target-six
				if (condition == CONDITION_ATTACK_FLY_TO_TARGET_SIX)
				{
					// head for a point weapon-range * 0.5 to the six of the target
					//
					destination = [target distance_six:0.5 * weapon_range];
				}
				// target-twelve
				if (condition == CONDITION_ATTACK_FLY_TO_TARGET_TWELVE)
				{
					// head for a point 1.25km above the target
					//
					destination = [target distance_twelve:1250];
				}
				
				[self trackDestination:delta_t :NO];
				
				// use weaponry
				//
				if (missiles > missile_chance * hurt_factor)
				{
					//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
					[self fireMissile];
				}
				[self activateCloakingDevice];
				[self fireMainWeapon:range];
				break;
				
			case CONDITION_ATTACK_MINING_TARGET :
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
						condition = CONDITION_IDLE;
						[shipAI reactToMessage:@"TARGET_LOST"];
					}
					desired_speed = max_flight_speed * 0.375;
				}
				[self trackPrimaryTarget:delta_t:NO];
				[self fireMainWeapon:range];
				break;				
				
			case CONDITION_ATTACK_FLY_TO_TARGET :
				if ((range < COMBAT_IN_RANGE_FACTOR * weapon_range)||(proximity_alert != NO_TARGET))
				{
					if (proximity_alert == NO_TARGET)
					{
						if (aft_weapon_type == WEAPON_NONE)
						{
							jink.x = (ranrot_rand() % 256) - 128.0;
							jink.y = (ranrot_rand() % 256) - 128.0;
							jink.z = 1000.0;
							condition = CONDITION_ATTACK_FLY_FROM_TARGET;
							frustration = 0.0;
							desired_speed = max_available_speed;
						}
						else
						{
							//NSLog(@"DEBUG >>>>> %@ %d entering running defense mode", name, universal_id);
							
							jink = make_vector( 0.0, 0.0, 0.0);
							condition = CONDITION_RUNNING_DEFENSE;
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
						condition = CONDITION_IDLE;
						frustration = 0.0;
						[shipAI reactToMessage:@"TARGET_LOST"];
					}
				}
				
				// control speed
				//
				if (range <= slow_down_range)
					desired_speed = target_speed;   // within the weapon's range don't use afterburner
				else
					desired_speed = max_available_speed; // use afterburner to approach
				
				last_success_factor = success_factor;
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
						condition = CONDITION_ATTACK_FLY_FROM_TARGET;
						frustration = 0.0;
						desired_speed = max_flight_speed;
					}
				}
				
				if (missiles > missile_chance * hurt_factor)
				{
					//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
					[self fireMissile];
				}
				[self activateCloakingDevice];
				[self fireMainWeapon:range];
				break;
				
			case CONDITION_ATTACK_FLY_FROM_TARGET :
				if (range > COMBAT_OUT_RANGE_FACTOR * weapon_range + 15.0 * jink.x)
				{
					jink.x = 0.0;
					jink.y = 0.0;
					jink.z = 0.0;
					condition = CONDITION_ATTACK_TARGET;
					frustration = 0.0;
				}
				[self trackPrimaryTarget:delta_t:YES];
				if (missiles > missile_chance * hurt_factor)
				{
					//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
					[self fireMissile];
				}
				[self activateCloakingDevice];
				break;
				
			case CONDITION_RUNNING_DEFENSE :
				if (range > weapon_range)
				{
					jink.x = 0.0;
					jink.y = 0.0;
					jink.z = 0.0;
					condition = CONDITION_ATTACK_FLY_TO_TARGET;
					frustration = 0.0;
				}
				[self trackPrimaryTarget:delta_t:YES];
				[self fireAftWeapon:range];
				[self activateCloakingDevice];
				break;
				
			case CONDITION_FLEE_TARGET :
				if (range > desired_range)
				{
					[shipAI message:@"REACHED_SAFETY"];
				}
				else
				{
					desired_speed = max_available_speed;
				}
				[self trackPrimaryTarget:delta_t:YES];
				if (([(ShipEntity *)[self getPrimaryTarget] getPrimaryTarget] == self)&&(missiles > missile_chance * hurt_factor))
				{
					//NSLog(@"]==> firing missile : missiles %d, missile_chance %d, hurt_factor %.3f", missiles, missile_chance, hurt_factor);
					[self fireMissile];
				}
				[self activateCloakingDevice];
				break;
			
			case CONDITION_FLY_RANGE_FROM_DESTINATION :
				if (distance < desired_range)
					condition = CONDITION_FLY_FROM_DESTINATION;
				else
					condition = CONDITION_FLY_TO_DESTINATION;
				frustration = 0.0;
				break;
				
			case CONDITION_FACE_DESTINATION :
				desired_speed = 0.0;
//				NSLog(@"DEBUG >>>>> distance %.1f desired_range %.1f", distance, desired_range);
				confidenceFactor = [self trackDestination:delta_t:NO];
				if (confidenceFactor > 0.995)	// 0.995 - cos(5 degrees) is close enough
				{
					// desired facing achieved
					[shipAI message:@"FACING_DESTINATION"];
					condition = CONDITION_IDLE;
					frustration = 0.0;
				}
				if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
					[self avoidCollision];
				break;
			
			case CONDITION_FORMATION_FORM_UP :
				// get updated destination from owner
				{
					double eta = (distance - desired_range) / flight_speed;
					if (eta < 5.0)
						desired_speed = [(ShipEntity *)[universe entityForUniversalID:owner] flight_speed] * 1.25;
					else
						desired_speed = max_flight_speed;
				}
			case CONDITION_FLY_TO_DESTINATION :
				if (distance < desired_range + collision_radius)
				{
					// desired range achieved
					[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
					condition = CONDITION_IDLE;
					frustration = 0.0;
					desired_speed = 0.0;
				}
				else
				{
					double last_distance = last_success_factor;
					double eta = (distance - desired_range) / flight_speed;
					success_factor = distance;
					
					// do the actual piloting!!
					[self trackDestination:delta_t:NO];
					
					if ((eta < 2.0)&&(flight_speed > max_flight_speed * 0.10))
						desired_speed = flight_speed * 0.50;   // cut speed to a minimum of 10 % speed
					
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
//							[self setReportAImessages:YES];	//debug
							[shipAI reactToMessage:@"FRUSTRATED"];
//							NSLog(@"DEBUG %@ flight_speed %.6f distance %.6f last_distance %.6f", self, flight_speed, distance, last_distance);
//							[self setReportAImessages:NO];	//debug
							frustration -= 5.0;	//repeat after another five seconds' frustration
						}
					}
				}
				if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
					[self avoidCollision];
				break;
			
			case CONDITION_FORMATION_BREAK :
			case CONDITION_FLY_FROM_DESTINATION :
				if (distance > desired_range)
				{
					// desired range achieved
					[shipAI message:@"DESIRED_RANGE_ACHIEVED"];
					condition = CONDITION_IDLE;
					frustration = 0.0;
					desired_speed = 0.0;
				}
				else
				{
					double eta = (desired_range - distance) / flight_speed;
					desired_speed = max_flight_speed;
					if ((eta < 1.0)&&(flight_speed > max_flight_speed*0.25))
						desired_speed = flight_speed * 0.5;   // cut speed to a minimum of 1/4 speed
				}
				[self trackDestination:delta_t:YES];
				if ((proximity_alert != NO_TARGET)&&(proximity_alert != primaryTarget))
					[self avoidCollision];
				break;
				
			case CONDITION_AVOID_COLLISION :
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
						destination.x += position.x;	destination.y += position.y;	destination.z += position.z;
						destination.x *= 0.5;	destination.y *= 0.5;	destination.z *= 0.5;	// point between us and them
					}
					double dq = [self trackDestination:delta_t:YES];
					if (dq >= 0)
						dq = 0.5 * dq + 0.5;
					else
						dq = 0.0;
					desired_speed = max_flight_speed * dq;
				}
				break;
				
			case CONDITION_TRACK_AS_TURRET :
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
						{
							[self fireTurretCannon: sqrt( magnitude2( p1)) - cr];
//							NSLog(@"DEBUG BANG! BANG! BANG!");
						}
					}
				}
				break;
				
			case CONDITION_EXPERIMENTAL :
				{
					double aim = [self ballTrackTarget:delta_t];
					if (aim > .95)
					{
						NSLog(@"DEBUG BANG! BANG! BANG!");
					}
				}
				break;
				
		}
		//
		// in (almost) every case...
		//
		if (condition != CONDITION_TRACK_AS_TURRET)
		{
			[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
			[self applyThrust:delta_t];
		}
		//
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
		//
//		if (isStation && (sub_entities))
//			NSLog(@"DEBUG %@ sub_entities %@", [self name], [sub_entities description]);
		if (sub_entities)
		{
			int i;
			for (i = 0; i < [sub_entities count]; i++)
			{
//				if (isStation && (sub_entities))
//					NSLog(@"DEBUG %@ going to update sub_entity %@", [self name], [sub_entities objectAtIndex:i]);
				[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
			}
		}
		//
		// update destination position for escorts
		if (n_escorts > 0)
		{
			int i;
			for (i = 0; i < n_escorts; i++)
			{
				ShipEntity *escorter = (ShipEntity *)[universe entityForUniversalID:escort_ids[i]];
				[escorter setDestination:[self getCoordinatesForEscortPosition:i]];
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
	float	nose = boundingBox.max_z - 36.0;
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
	//debug
	//NSLog(@"DEBUG drawn ship (%@ %d)", name, universal_id);
	
	//
	checkGLErrors([NSString stringWithFormat:@"ShipEntity after drawing Entity (main) %@", self]);
	//
	
	if (immediate)
		return;		// don't draw sub-entities when constructing a displayList
	
//	if ((sub_entities)&&(status != STATUS_DEMO))
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
	double max_available_speed = (has_fuel_injection && (fuel > 0))? max_flight_speed * AFTERBURNER_FACTOR : max_flight_speed;
	
	velocity.x += momentum.x / mass;	momentum.x = 0;
	velocity.y += momentum.y / mass;	momentum.y = 0;
	velocity.z += momentum.z / mass;	momentum.z = 0;

	position.x += delta_t*velocity.x;
	position.y += delta_t*velocity.y;
	position.z += delta_t*velocity.z;
	
	if (velocity.x > 0.0)
		velocity.x -= (velocity.x > delta_t*thrust) ? delta_t*thrust : velocity.x;
	if (velocity.y > 0.0)
		velocity.y -= (velocity.y > delta_t*thrust) ? delta_t*thrust : velocity.y;
	if (velocity.z > 0.0)
		velocity.z -= (velocity.z > delta_t*thrust) ? delta_t*thrust : velocity.z;
	if (velocity.x < 0.0)
		velocity.x -= (velocity.x < -delta_t*thrust) ? -delta_t*thrust : velocity.x;
	if (velocity.y < 0.0)
		velocity.y -= (velocity.y < -delta_t*thrust) ? -delta_t*thrust : velocity.y;
	if (velocity.z < 0.0)
		velocity.z -= (velocity.z < -delta_t*thrust) ? -delta_t*thrust : velocity.z;

	if (condition == CONDITION_TUMBLE)  return; //testing

	
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
		fuel_accumulator -= delta_t * AFTERBURNER_BURNRATE;
		while (fuel_accumulator <= 0)
		{
			fuel--;
			fuel_accumulator += 1.0;
		}
		//NSLog(@"DEBUG %@ %d fuel %d", name, universal_id, fuel);
	}
}

- (void) applyRoll:(GLfloat) roll1 andClimb:(GLfloat) climb1
{	
	Quaternion q1;
	
	if ((roll1 == 0.0)&&(climb1 == 0.0)&&(!has_rotated))
		return;
	
	quaternion_set_identity(&q1);
	
	if (roll1 != 0.0)
		quaternion_rotate_about_z( &q1, -roll1);
	if (climb1 != 0.0)
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
	if ([roles isEqual:@"missile"])
		return;						// missiles are SUPPOSED to collide!
	
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
		
		previousCondition = [[NSMutableDictionary alloc] initWithCapacity:16];
		
		[previousCondition setObject:[NSNumber numberWithInt:condition] forKey:@"condition"];
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
		
		condition = CONDITION_AVOID_COLLISION;
	}
}

- (void) resumePostProximityAlert
{
	if (!previousCondition)
		return;
		
//	NSLog(@"DEBUG ***** proximity alert for %@ %d over", name, universal_id, proximity_alert);
		
	condition =		[(NSNumber*)[previousCondition objectForKey:@"condition"] intValue];
	primaryTarget =	[(NSNumber*)[previousCondition objectForKey:@"primaryTarget"] intValue];
	desired_range =	[(NSNumber*)[previousCondition objectForKey:@"desired_range"] floatValue];
	desired_speed =	[(NSNumber*)[previousCondition objectForKey:@"desired_speed"] floatValue];
	destination.x =	[(NSNumber*)[previousCondition objectForKey:@"destination.x"] floatValue];
	destination.y =	[(NSNumber*)[previousCondition objectForKey:@"destination.y"] floatValue];
	destination.z =	[(NSNumber*)[previousCondition objectForKey:@"destination.z"] floatValue];
		
	[previousCondition release];
	previousCondition = nil;
	frustration = 0.0;
	
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
	if ((other)&&(!(other->isStation)))	// don't be alarmed close to stations
		proximity_alert = [other universal_id];
	else
		proximity_alert = NO_TARGET;
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
	if ((condition == CONDITION_AVOID_COLLISION)&&(previousCondition))
	{
		int old_condition = [(NSNumber*)[previousCondition objectForKey:@"condition"] intValue];
		return IS_CONDITION_HOSTILE(old_condition);
	}
	return IS_CONDITION_HOSTILE(condition);
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
			weapon_energy =			0.0;
			weapon_recharge_rate =	30;
			weapon_range =			0;
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
	int result = AEGIS_NONE;
	p1.x -= position.x;	p1.y -= position.y;	p1.z -= position.z;
	double d2 = p1.x*p1.x + p1.y*p1.y + p1.z*p1.z - cr * cr * 9.0; // 3x radius of planet
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
	//if (status == STATUS_IN_FLIGHT)
	//	accepts_escorts = YES;
}

- (void) setAI:(AI *) ai
{
	if (shipAI) [shipAI release];
	shipAI = [ai retain];
}

- (AI *) getAI
{
	return shipAI;
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
	if ([roles isEqual:@"asteroid"])
		return 0;
	if ([roles isEqual:@"boulder"])
		return 0;
	if ([roles isEqual:@"splinter"])
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
			p2.x -= position.x;	p2.y -= position.y;	p2.z -= position.z;
			double d2 = p2.x*p2.x + p2.y*p2.y + p2.z*p2.z;
			double damage = weapon_energy*desired_range/d2;
			[e2 takeEnergyDamage:damage from:self becauseOf:[self owner]];
			//if ((e2)&&(e2->isShip))
			//	//NSLog(@"Doing %.1f damage to %@ %d",damage,[(ShipEntity *)e2 name],[(ShipEntity *)e2 universal_id]);
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
		
		// tell ourselves we've been attacked
		if (energy > 0)
			[shipAI reactToMessage:@"ATTACKED"];	// note use the reactToMessage: method NOT the think-delayed message: method
		
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
			if ([hunter condition] == CONDITION_ATTACK_FLY_TO_TARGET)	// avoid me please!
			{
				[hunter setCondition:CONDITION_ATTACK_FLY_FROM_TARGET];
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
			condition = CONDITION_IDLE;
			frustration = 0.0;
			[self launchEscapeCapsule];
			[self setScanClass: CLASS_NEUTRAL];			// we're unmanned now!
		}
	}
}

- (void) becomeExplosion
{
	Vector	xposition = position;
	ParticleEntity  *fragment;
	int i;
	Vector v;
	Quaternion q;
	int speed_low = 200;
	int n_alloys = floor((boundingBox.max_z - boundingBox.min_z) / 50.0);
	
	if (status == STATUS_DEAD)
		return;
	status = STATUS_DEAD;
	//scripting
	if ([death_actions count])
	{
		int i;
		PlayerEntity* player = (PlayerEntity *)[universe entityZero];
		[player setScript_target:self];
		for (i = 0; i < [death_actions count]; i++)
		{
			NSObject* action = [death_actions objectAtIndex:i];
			if ([action isKindOfClass:[NSDictionary class]])
				[player checkCouplet:(NSDictionary *)action onEntity:self];
			if ([action isKindOfClass:[NSString class]])
				[player scriptAction:(NSString *)action onEntity:self];
		}
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
	
	// two parts to the explosion:
	// 1. fast sparks
	fragment = [[ParticleEntity alloc] initFragburstFromPosition:xposition];
	[universe addEntity:fragment];
	[fragment release];
	// 2. slow clouds
	fragment = [[ParticleEntity alloc] initBurst2FromPosition:xposition];
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
	if (cargo_flag == CARGO_FLAG_FULL_UNIFORM)
	{
		int cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		NSString* commodity_name = (NSString*)[shipinfoDictionary objectForKey:@"cargo_carried"];
		jetsam = [[universe getContainersOfCommodity:commodity_name :cargo_to_go] retain];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
	}
	if (cargo_flag == CARGO_FLAG_FULL_PLENTIFUL)
	{
		int cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		jetsam = [[universe getContainersOfPlentifulGoods:cargo_to_go] retain];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
	}
	if (cargo_flag == CARGO_FLAG_FULL_SCARCE)
	{
		int cargo_to_go = max_cargo * cargo_chance / 100;
		while (cargo_to_go > 15)
			cargo_to_go = ranrot_rand() % cargo_to_go;
		jetsam = [[universe getContainersOfScarceGoods:cargo_to_go] retain];
		cargo_chance = 100;  //  chance of any given piece of cargo surviving decompression
	}
	if (cargo_flag == CARGO_FLAG_CANISTERS)
	{
		jetsam = [[NSArray arrayWithArray:cargo] retain];   // what the ship is carrying
		[cargo removeAllObjects];   // dispense with it!
	}
	if (jetsam)
	{
		for (i = 0; i < [jetsam count]; i++)
		{
			if (ranrot_rand() % 100 < cargo_chance)  //  chance of any given piece of cargo surviving decompression
			{
				ShipEntity* container = [[jetsam objectAtIndex:i] retain];
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
				[container release];
			}
		}
		[jetsam release];   // done with this now!
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
		[plate setStatus:STATUS_TEST];
		[plate setScanClass: CLASS_CARGO];
		[plate setCommodity:9 andAmount:1];
		[universe addEntity:plate];
		[[plate getAI] setState:@"GLOBAL"];
		[plate release];
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
				Vector  origin = se->position;
				Entity*		father = self;
				GLfloat*	r_mat = [father rotationMatrix];
				while (father)
				{
					mult_vector_gl_matrix(&origin, r_mat);
					Vector pos = father->position;
					origin.x += pos.x;	origin.y += pos.y;	origin.z += pos.z;
					father = [father owner];
					r_mat = [father rotationMatrix];
				}
				[se setPosition:origin];	// is this what's messing thing up??
				[(ShipEntity *)se becomeExplosion];
			}
		}
		[sub_entities release]; // releases each subentity too!
		sub_entities = nil;
	}

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
	result.x = bb.min_x + randf() * (bb.max_x - bb.min_x);
	result.y = bb.min_y + randf() * (bb.max_y - bb.min_y);
	result.z = bb.min_z + randf() * (bb.max_z - bb.min_z);
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
		int i;
		PlayerEntity* player = (PlayerEntity *)[universe entityZero];
		[player setScript_target:self];
		for (i = 0; i < [death_actions count]; i++)
		{
			NSObject* action = [death_actions objectAtIndex:i];
			if ([action isKindOfClass:[NSDictionary class]])
				[player checkCouplet:(NSDictionary *)action onEntity:self];
			if ([action isKindOfClass:[NSString class]])
				[player scriptAction:(NSString *)action onEntity:self];
		}
		[death_actions removeAllObjects];
	}
	
	// two parts to the explosion:
	// 1. fast sparks
	float how_many = factor;
	while (how_many > 0.5f)
	{
		fragment = [[ParticleEntity alloc] initFragburstFromPosition:xposition];
		[universe addEntity:fragment];
		[fragment release];
		how_many -= 1.0f;
	}
	// 2. slow clouds
	how_many = factor;
	while (how_many > 0.5f)
	{
		fragment = [[ParticleEntity alloc] initBurst2FromPosition:xposition];
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
			[container setStatus:STATUS_TEST];
			[container setPosition:rpos];
			[container setScanClass: CLASS_CARGO];
			[universe addEntity:container];
			[[container getAI] setState:@"GLOBAL"];
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
	//if ((targetentity)&&(targetEntity->isShip))
	//	NSLog(@"DEBUG %@ now targetting %@", [self name], [(ShipEntity *)targetEntity name]);
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

- (int) condition
{
	return condition;
}

- (void) setCondition:(int) cond
{
	if (cond !=condition)
		frustration = 0.0;	// change is a GOOD thing
	condition = cond;
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
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father rotationMatrix];
	while (father)
	{
		mult_vector_gl_matrix(&my_position, r_mat);
		mult_vector_gl_matrix(&my_ref, r_mat);
		Vector pos = father->position;
		my_position.x += pos.x;	my_position.y += pos.y;	my_position.z += pos.z;
		
		father = [father owner];
		r_mat = [father rotationMatrix];
	}
	
	if (targent)
	{
		vector_to_target = targent->position;
		//
		vector_to_target.x -= my_position.x;	vector_to_target.y -= my_position.y;	vector_to_target.z -= my_position.z;
		vector_to_target = unit_vector(&vector_to_target);	
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

- (void) trackOntoTarget:(double) delta_t
{
	Vector vector_to_target;
	Vector my_aim = v_forward;
	Quaternion q_minarc;
	quaternion_set_identity(&q_minarc);
	double fraction = (10.0 * delta_t < 1.0)? 10.0 * delta_t : 1.0;
	//
	Entity* targent = [self getPrimaryTarget];
	//
	if (!targent)
		return;
	
	vector_to_target = targent->position;
	vector_to_target.x -= position.x;	vector_to_target.y -= position.y;	vector_to_target.z -= position.z;
	//
	vector_to_target = unit_vector(&vector_to_target);
	
	// section copied from GPG1
	//
	Vector xp = make_vector(	(my_aim.y * vector_to_target.z) - (my_aim.z * vector_to_target.y),
								(my_aim.z * vector_to_target.x) - (my_aim.x * vector_to_target.z),
								(my_aim.x * vector_to_target.y) - (my_aim.y * vector_to_target.x));
	GLfloat d = dot_product( my_aim, vector_to_target);
	GLfloat s = sqrt((1.0 + d) * 2.0);
	if (s)
	{
		q_minarc.x = xp.x / s;
		q_minarc.y = xp.y / s;
		q_minarc.z = xp.z / s;
		q_minarc.w = s / 2.0;
	}
	//
	////
	
	// average with unit vector
	q_minarc.x *= fraction;
	q_minarc.y *= fraction;
	q_minarc.z *= fraction;
	q_minarc.w = fraction * q_minarc.w + (1.0 - fraction);

//	NSLog(@"DEBUG q_minarc x %.4f y %.4f z %.4f w %.4f",
//		q_minarc.x, q_minarc.y, q_minarc.z, q_minarc.w);

	q_rotation = quaternion_multiply( q_minarc, q_rotation);
    quaternion_normalise(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
	
	flight_roll = 0.0;
	flight_pitch = 0.0;
	
//	my_aim = vector_forward_from_quaternion(q_rotation);	// DEBUG ONLY
//	GLfloat d2 = dot_product( vector_to_target, my_aim);
//	NSLog(@"DEBUG ::::: BEFORE: (%.6f) AFTER: (%.6f) :%@: ", d, d2, (d2 > d)? @"SUCCESS" : @"failure");
	
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
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father rotationMatrix];
	while (father)
	{
		mult_vector_gl_matrix(&my_position, r_mat);
		mult_vector_gl_matrix(&my_ref, r_mat);
		Vector pos = father->position;
		my_position.x += pos.x;	my_position.y += pos.y;	my_position.z += pos.z;
		
		father = [father owner];
		r_mat = [father rotationMatrix];
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
		vector_to_target = unit_vector(&vector_to_target);	
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
	Vector  relativePosition;	
	GLfloat  d_forward, d_up, d_right, range2;
	Entity  *target;
	BOOL isMining = ((condition == CONDITION_ATTACK_MINING_TARGET)&&(forward_weapon_type == WEAPON_MINING_LASER));
	
	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;
	
	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;
	
	double pitch_pitch = 0.0;
	double roll_roll = 0.0;
	
	double reverse = 1.0;
	
	double tolerance1 = pitch_tolerance;
	
	target = [self getPrimaryTarget];
	
	if (target == nil)   // leave now!
		return 0.0;
	
	if (retreat)
		reverse = -1.0;
	
	relativePosition = target->position;
	relativePosition.x -= position.x;
	relativePosition.y -= position.y;
	relativePosition.z -= position.z;
	
	range2 = magnitude2(relativePosition);
	
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
	
	relativePosition = unit_vector(&relativePosition);
	
	d_right		=   dot_product(relativePosition, v_right);		// = cosine of angle between angle to target and v_right
	d_up		=   dot_product(relativePosition, v_up);		// = cosine of angle between angle to target and v_up
	d_forward   =   dot_product(relativePosition, v_forward);	// = cosine of angle between angle to target and v_forward

	if ((d_forward > 0.995)&&(d_forward < 0.9999)&&(!retreat)&&(!isMining))
	{
		[self trackOntoTarget: delta_t];
		return d_forward;
	}

	// begin rule-of-thumb manoeuvres
	
	stick_roll = 0.0;
	
	if (pitching_over)
		pitching_over = (stick_pitch != 0.0);
	
	if ((d_forward*reverse < -tolerance1) && (!pitching_over))
	{
		pitching_over = YES;
		pitch_pitch = 1.0;
		//NSLog(@"Pitch - over");
		if (d_up >= 0)
			stick_pitch = -max_flight_pitch * pitch_pitch * reverse;
		if (d_up < 0)
			stick_pitch = max_flight_pitch * pitch_pitch * reverse;
	}
	
			
	if (pitching_over)
	{
		pitching_over = (d_forward * reverse < 0.5);
	}
	else
	{
		stick_pitch = 0.0;
		pitch_pitch = d_up;
		if (pitch_pitch < 0.0)
			pitch_pitch = -pitch_pitch;
		roll_roll = d_right;
		if (roll_roll < 0.0)
			roll_roll = -roll_roll;
		
		if (retreat)
			pitch_pitch = 1.0 - pitch_pitch;
				
		if (d_up > 0.0)
			stick_pitch = -max_flight_pitch * pitch_pitch * reverse;
		if (d_up < 0.0)
			stick_pitch = max_flight_pitch * pitch_pitch * reverse;

		if (d_right > 0.0)
			stick_roll = -max_flight_roll * roll_roll;
		if (d_right < 0.0)
			stick_roll = max_flight_roll * roll_roll;
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
	
	Entity*	primeTarget = [self getPrimaryTarget];
	BOOL	we_are_docking = ((primeTarget)&&(primeTarget->isStation));
	
	double  damping = 0.5 * delta_t;
	double  rate2 = 4.0 * delta_t;
	double  rate1 = 2.0 * delta_t;
	
	double stick_roll = 0.0;	//desired roll and pitch
	double stick_pitch = 0.0;
		
	double reverse = 1.0;
	
	double min_d = 0.004;
	
	if (we_are_docking &&(desired_speed = 50.0))	// test for docking stuff
		min_d = 0.012;	// less accuracy required - better to match spin
	
	if (retreat)
		reverse = -reverse;

	if (isPlayer)
		reverse = -reverse;
		
	relativePosition = destination;
	relativePosition.x -= position.x;
	relativePosition.y -= position.y;
	relativePosition.z -= position.z;
	
	relativePosition = unit_vector(&relativePosition);
	
	d_right		=   dot_product(relativePosition, v_right);
	d_up		=   dot_product(relativePosition, v_up);
	d_forward   =   dot_product(relativePosition, v_forward);

	// begin rule-of-thumb manoeuvres
	
	if (d_forward < -0.99)  // hack to avoid just flying away from the destination
	{
		d_up = min_d * 2.0;
	}
	
	stick_pitch = 0.0;
	stick_roll = 0.0;
		
	if (d_up > min_d)
	{
		if (d_right > min_d)
			stick_roll = stick_roll - max_flight_roll * reverse * 0.25;  //roll_roll * reverse;
		if (d_right < -min_d)
			stick_roll = stick_roll + max_flight_roll * reverse * 0.25; //roll_roll * reverse;
	}
	if (d_up < -min_d) // half a meter
	{
		if (d_right > min_d)
			stick_roll = stick_roll + max_flight_roll * reverse * 0.25;  //roll_roll * reverse;
		if (d_right < -min_d)
			stick_roll = stick_roll - max_flight_roll * reverse * 0.25; //roll_roll * reverse;
	}
	
	if (stick_roll == 0.0)
	{
		if (d_up > min_d)
			stick_pitch = -max_flight_pitch * reverse * 0.25;  //pitch_pitch * reverse;
		if (d_up < -min_d)
			stick_pitch = max_flight_pitch * reverse * 0.25;  //pitch_pitch * reverse;
	}
	
	if (we_are_docking)
	{
		/* we are docking and need to consider the rotation/orientation of the space station */
		Vector up_vec = [(StationEntity *)[self getPrimaryTarget] portUpVector];
		double rot_up = dot_product(up_vec, v_up);
		double fast_slow = dot_product(up_vec, v_right);
//		if (self == [universe entityZero])
//			NSLog(@"DEBUG docking rot_up %.3f %.3f",rot_up, fast_slow);
		if (fast_slow*rot_up < 0)
			fast_slow = 0.0;
		else
			fast_slow = 1.0;
		double station_roll = [(StationEntity *)[self getPrimaryTarget] flight_roll];
		rot_up *= rot_up;
		if ((stick_pitch == 0.0)&&(stick_roll == 0.0))
		{
			if (rot_up > 0.975)
				stick_roll = station_roll;
			else
			{
				if (fabs(station_roll) > 0.1)
				{
					// station is rotating
					if (max_flight_roll > fabs(station_roll))
					{
						if (rot_up > 0.8)
							stick_roll = (station_roll > 0)? max_flight_roll*fast_slow: -max_flight_roll*fast_slow;
						else
							stick_roll = 0;	// flip over
					}
					else
						stick_roll = 0;	// flip over
				}
				else
				{
					// station is not rotating
					if (fast_slow > 0.0)
						stick_roll = 0.5;
					else
						stick_roll = -0.5;	// flip over
				}
			}
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
	if (!we_are_docking)
	{
		if (flight_roll < 0)
			flight_roll += (flight_roll < -damping) ? damping : -flight_roll;
		if (flight_roll > 0)
			flight_roll -= (flight_roll > damping) ? damping : flight_roll;
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
	urp = unit_vector(&rel_pos);
	dq = dot_product(urp, v_forward);				// cosine of angle between v_forward and unit relative position
	if (((fwd_weapon)&&(dq < 0.0)) || ((!fwd_weapon)&&(dq > 0.0)))
		return NO;
	astq = sqrt(d2) / sqrt (d2 + radius * radius);	// cosine of half angle subtended by target
//	if ([roles isEqual:@"miner"])
//		NSLog(@"DEBUG ..... dq: %.5f astq: %.5f onTarget: %@", dq, astq, (dq > astq)?@"YES":@"NO");
	return (dq >= astq);
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
	switch (forward_weapon_type)
	{
		case WEAPON_PLASMA_CANNON :
			[self firePlasmaShot:weapon_offset_x:1500.0:[NSColor yellowColor]];
			[self firePlasmaShot:weapon_offset_x:1500.0:[NSColor yellowColor]];
			return YES;
			break;
			
		case WEAPON_PULSE_LASER :
		case WEAPON_BEAM_LASER :
		case WEAPON_MINING_LASER :
		case WEAPON_MILITARY_LASER :
			[self fireLaserShot];
			return YES;
			break;
			
		case WEAPON_THARGOID_LASER :
			[self fireDirectLaserShot];
			return YES;
			break;
			
	}
	return NO;
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
	Entity*		father = [self owner];
	GLfloat*	r_mat = [father rotationMatrix];
	Vector		vel = vector_forward_from_quaternion(q_rotation);
//	Vector		vel_father = [father getVelocity];
	while (father)
	{
		mult_vector_gl_matrix(&origin, r_mat);
		Vector pos = father->position;
		origin.x += pos.x;	origin.y += pos.y;	origin.z += pos.z;
		father = [father owner];
		r_mat = [father rotationMatrix];
	}
	double  start = collision_radius + 0.5;
	double  speed = TURRET_SHOT_SPEED;
	NSColor* color = laser_color;
	
	origin.x += vel.x * start;
	origin.y += vel.y * start;
	origin.z += vel.z * start;
	
	vel.x *= speed;
	vel.y *= speed;
	vel.z *= speed;
	
//	vel.x += vel_father.x;
//	vel.y += vel_father.y;
//	vel.z += vel_father.z;
//	
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
//	NSLog(@"DEBUG Plasma cannon shot owner is %@", [shot owner]);
	
	[shot release]; //release
	
	shot_time = 0.0;
	return YES;
}

- (void) setLaserColor:(NSColor *) color
{
	if (color)
	{
		[laser_color release];
		laser_color = [color retain];
	}
}

- (BOOL) fireLaserShot
{
	ParticleEntity  *shot;
	int				direction = VIEW_FORWARD;
	//double			range_limit = PARTICLE_LASER_RANGE_LIMIT;
	double			range_limit2 = weapon_range*weapon_range;
	Vector  vel;
	target_laser_hit = NO_TARGET;
	
	vel.x = v_forward.x * flight_speed;
	vel.y = v_forward.y * flight_speed;
	vel.z = v_forward.z * flight_speed;

	if (isPlayer)		// only the player has weapons on other facings
		direction = [universe viewDir];					// set the weapon facing here

	target_laser_hit = [universe getFirstEntityHitByLaserFromEntity:self inView:direction];

	shot = [[ParticleEntity alloc] initLaserFromShip:self view:direction];	// alloc retains!
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	if (target_laser_hit != NO_TARGET)
	{
		Entity *victim = [universe entityForUniversalID:target_laser_hit];
		if (victim)
		{
			Vector p0 = shot->position;
			Vector p1 = victim->position;
			p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
			double dist2 = magnitude2(p1);
			if ((victim->isShip)&&(dist2 < range_limit2))
			{
				[(ShipEntity *)victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit
				[shot setCollisionRadius:sqrt(dist2)];
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

- (BOOL) fireDirectLaserShot
{
//	NSLog(@"DEBUG %@ %d laser fired direct shot on %@ %d", name, universal_id, [(ShipEntity*)[self getPrimaryTarget] name], primaryTarget);
	
	Entity*	my_target = [self getPrimaryTarget];
	if (!my_target)
		return NO;
	ParticleEntity*	shot;
	double			range_limit2 = weapon_range*weapon_range;
	Vector			r_pos = my_target->position;
	r_pos.x -= position.x;	r_pos.y -= position.y;	r_pos.z -= position.z;
	r_pos = unit_vector(&r_pos);

//	target_laser_hit = primaryTarget;

	Quaternion		q_laser = quaternion_rotation_between(r_pos, make_vector(0.0f,0.0f,1.0f));
	q_laser.x += 0.01 * (randf() - 0.5);	// randomise aim a little (+/- 0.005)
	q_laser.y += 0.01 * (randf() - 0.5);
	q_laser.z += 0.01 * (randf() - 0.5);
	quaternion_normalise(&q_laser);
	
	Quaternion q_save = q_rotation;	// save rotation
	q_rotation = q_laser;			// face in direction of laser
	target_laser_hit = [universe getFirstEntityHitByLaserFromEntity:self];
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
		if (victim)
		{
			Vector p0 = shot->position;
			Vector p1 = victim->position;
			p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
			double dist2 = magnitude2(p1);
			if ((victim->isShip)&&(dist2 < range_limit2))
			{
				[(ShipEntity *)victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit
				[shot setCollisionRadius:sqrt(dist2)];
				//
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
	Vector  vel;
	target_laser_hit = NO_TARGET;
	
	vel.x = v_forward.x * flight_speed;
	vel.y = v_forward.y * flight_speed;
	vel.z = v_forward.z * flight_speed;

	target_laser_hit = [universe getFirstEntityHitByLaserFromEntity:self inView:direction];

	shot = [[ParticleEntity alloc] initLaserFromShip:self view:direction];	// alloc retains!
	[shot setColor:laser_color];
	[shot setScanClass: CLASS_NO_DRAW];
	[shot setVelocity: vel];
	if (target_laser_hit != NO_TARGET)
	{
		Entity *victim = [universe entityForUniversalID:target_laser_hit];
		if (victim)
		{
			Vector p0 = shot->position;
			Vector p1 = victim->position;
			p1.x -= p0.x;	p1.y -= p0.y;	p1.z -= p0.z;
			double dist2 = magnitude2(p1);
			if ((victim->isShip)&&(dist2 < range_limit2))
			{
				[(ShipEntity *)victim takeEnergyDamage:weapon_energy from:self becauseOf:self];	// a very palpable hit
				[shot setCollisionRadius:sqrt(dist2)];
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
	
	GLfloat lr	= randf() * (boundingBox.max_x - boundingBox.min_x) + boundingBox.min_x;
	GLfloat ud	= randf() * (boundingBox.max_y - boundingBox.min_y) + boundingBox.min_y;
	GLfloat fb	= randf() * boundingBox.max_z + boundingBox.min_z;	// rear section only
	
	origin.x += fb * v_forward.x;
	origin.y += fb * v_forward.y;
	origin.z += fb * v_forward.z;

	origin.x += ud * v_up.x;
	origin.y += ud * v_up.y;
	origin.z += ud * v_up.z;

	origin.x += lr * v_right.x;
	origin.y += lr * v_right.y;
	origin.z += lr * v_right.z;
	
	float	sz = 8.0 + randf() * 16.0;
	
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
	[spark setColor:[NSColor colorWithCalibratedHue:0.08 + 0.17 * randf() saturation:1.0 brightness:1.0 alpha:1.0]];
	[spark setOwner:self];
	[universe addEntity:spark];
	[spark release]; //release
		
	next_spark_time = randf();
}

- (BOOL) firePlasmaShot:(double) offset :(double) speed :(NSColor *) color
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
	ShipEntity *missile;
	Vector  vel;
	Vector  origin = position;
	Vector  start;
	start.x = 0.0;						// in the middle
	start.y = boundingBox.min_y - 4.0;	// 4m below bounding box
	start.z = boundingBox.max_z + 1.0;	// 1m ahead of bounding box
	double  throw_speed = 250.0;
	Quaternion q1 = q_rotation;
	Entity  *target = [self getPrimaryTarget];
	
	if	((missiles <= 0)||(target == nil)||(target->scan_class == CLASS_NO_DRAW)||
		((target->isShip)&&(!has_military_scanner_filter)&&([(ShipEntity*)target isJammingScanning])))	// no missile lock!
		return NO;
		
	if ([roles isEqual:@"thargoid"])
		return [self fireTharglet];
	
	missiles--;
	
	if (isPlayer)
		q1.w = -q1.w;   // player view is reversed remember!
		
	vel.x = (flight_speed + throw_speed) * v_forward.x;
	vel.y = (flight_speed + throw_speed) * v_forward.y;
	vel.z = (flight_speed + throw_speed) * v_forward.z;
	
	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;
	
	//vel.x *= throw_speed;	vel.y *= throw_speed;	vel.z *= throw_speed;
	if (randf() < 0.90)	// choose a standard missile 90% of the time
		missile = [universe getShipWithRole:@"EQ_MISSILE"];   // retained
	else				// otherwise choose any with the role 'missile' - which may include alternative weapons
		missile = [universe getShipWithRole:@"missile"];   // retained
	[missile setPosition:origin];						// directly below
	[missile setScanClass: CLASS_MISSILE];
	[missile addTarget:target];
	[missile setQRotation:q1];
	[missile setStatus: STATUS_IN_FLIGHT];  // necessary to get it going!
	[missile setVelocity: vel];
	[missile setSpeed:150.0];
	[missile setOwner:self];
	[missile setDistanceTravelled:0.0];
	//debug
	//[missile setReportAImessages:YES];
	//
	[universe addEntity:missile];
	//NSLog(@"Missile collision radius is %.1f",missile->collision_radius);
	[missile release]; //release
	
	[(ShipEntity *)target setPrimaryAggressor:self];
	[[(ShipEntity *)target getAI] reactToMessage:@"INCOMING_MISSILE"];
	
	return YES;
}

- (BOOL) fireTharglet
{
	ShipEntity *tharglet;
	Vector  vel;
	Vector  origin = position;
	Vector  start;
	start.x = 0.0;						// in the middle
	start.y = boundingBox.min_y - 10.0;	// 10m below bounding box
	start.z = 1.0;	// 1m ahead of bounding box
	double  throw_speed = 500.0;
	Quaternion q1 = q_rotation;
	Entity  *target = [self getPrimaryTarget];
	
	if ((missiles <= 0)||(target == nil))
		return NO;
	
	missiles--;
	
	if (isPlayer)
		q1.w = -q1.w;   // player view is reversed remember!
		
	vel.x = (flight_speed + throw_speed) * v_forward.x;
	vel.y = (flight_speed + throw_speed) * v_forward.y;
	vel.z = (flight_speed + throw_speed) * v_forward.z;
	
	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;
		
	tharglet = [universe getShipWithRole:@"tharglet"];   // retain count = 1
	[tharglet setPosition:origin];						// directly below
	[tharglet setScanClass: CLASS_THARGOID];
	[tharglet addTarget:target];
	[tharglet setQRotation:q1];
	[tharglet setStatus: STATUS_IN_FLIGHT];  // necessary to get it going!
	[tharglet setVelocity: vel];
	[tharglet setSpeed:350.0];
	[tharglet setOwner:self];
	//[tharglet setReportAImessages:YES]; // debug
	[universe addEntity:tharglet];
	//NSLog(@"tharglet collision radius is %.1f",tharglet->collision_radius);
	
	[tharglet setGroup_id:group_id];
	
	[tharglet release]; //release
	
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
	[bomb setCondition: CONDITION_ENERGY_BOMB_COUNTDOWN];
	[bomb setOwner: self];
	[universe addEntity:bomb];
	[[bomb getAI] setState:@"GLOBAL"];
	[bomb release];
	if (self != [universe entityZero])	// get the heck out of here
	{
		[self addTarget:bomb];
		condition = CONDITION_FLEE_TARGET;
		frustration = 0.0;
	}
	return YES;
}

- (int) launchEscapeCapsule
{
	ShipEntity *pod;
	Vector  vel;
	Vector  origin = position;
	double  start = boundingBox.min_y - 10.0;
	double  throw_speed = 20.0;
	int co_type, co_amount;
	Quaternion q1 = q_rotation;
	
	if (isPlayer)
		q1.w = -q1.w;   // player view is reversed remember!
		
	vel.x = (-v_forward.x) * throw_speed + flight_speed * v_forward.x;
	vel.y = (-v_forward.y) * throw_speed + flight_speed * v_forward.y;
	vel.z = (-v_forward.z) * throw_speed + flight_speed * v_forward.z;
	
	origin.x += vel.x * start / throw_speed;
	origin.y += vel.y * start / throw_speed;
	origin.z += vel.z * start / throw_speed;
	
	pod = [universe getShipWithRole:@"escape-capsule"];   // retain count = 1
	[pod setPosition:origin];						// directly below
	[pod setScanClass: CLASS_CARGO];
	co_type = [universe commodityForName:@"Slaves"];
	co_amount = 1;
	[pod setCommodity:co_type andAmount:co_amount];
	[pod setQRotation:q1];
	[pod setVelocity: vel];
	[pod setOwner:self];
	[[pod getAI] setState:@"GLOBAL"];   // set the AI going
	[pod setStatus: STATUS_IN_FLIGHT];  // necessary to get it going!
	[universe addEntity:pod];
	[pod release]; //release
		
	return [pod universal_id];
}

- (int) dumpCargo
{
	if (status == STATUS_DEAD)
		return 0;
	
	int result = CARGO_NOT_CARGO;
	if (([cargo count] > 0)&&([universe getTime] - cargo_dump_time > 0.5))  // space them 0.5s or 10m apart
	{
		ShipEntity* jetto = [[cargo objectAtIndex:0] retain];
		if (!jetto)
			return 0;
		double  start = collision_radius + jetto->collision_radius;
		double  eject_speed = -20.0;
		Quaternion  random_direction;
		Vector  vel;
		Vector  rpos = position;
		double random_roll =	((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
		double random_pitch =   ((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
		quaternion_set_random(&random_direction);
		rpos.x -= v_forward.x * start;
		rpos.y -= v_forward.y * start;
		rpos.z -= v_forward.z * start;
		vel.x = v_forward.x * flight_speed;
		vel.y = v_forward.y * flight_speed;
		vel.z = v_forward.z * flight_speed;

		vel.x += v_forward.x * eject_speed;
		vel.y += v_forward.y * eject_speed;
		vel.z += v_forward.z * eject_speed;
		eject_speed *= 0.1 * ((ranrot_rand() % 10) - 5);   //  -0.5x .. +0.5x
		vel.x += v_up.x * eject_speed;
		vel.y += v_up.y * eject_speed;
		vel.z += v_up.z * eject_speed;
		eject_speed *= 0.1 * ((ranrot_rand() % 10) - 5);   //  -0.25x .. +0.25x
		vel.x += v_right.x * eject_speed;
		vel.y += v_right.y * eject_speed;
		vel.z += v_right.z * eject_speed;
		
		result = [jetto getCommodityType];
		[jetto setStatus:STATUS_TEST];
		[jetto setPosition:rpos];
		[jetto setQRotation:random_direction];
		[jetto setRoll:random_roll];
		[jetto setPitch:random_pitch];
		[jetto setVelocity:vel];
		[jetto setScanClass: CLASS_CARGO];
		[jetto setStatus: STATUS_IN_FLIGHT];
		[universe addEntity:jetto];
		[[jetto getAI] setState:@"GLOBAL"];
		[jetto release];
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
	double  start = collision_radius + jetto->collision_radius;
	double  eject_speed = -20.0;
	Quaternion  random_direction;
	Vector  vel;
	Vector  rpos = position;
	double random_roll =	((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	double random_pitch =   ((ranrot_rand() % 1024) - 512.0)/1024.0;  //  -0.5 to +0.5
	quaternion_set_random(&random_direction);
	rpos.x -= v_forward.x * start;
	rpos.y -= v_forward.y * start;
	rpos.z -= v_forward.z * start;
	vel.x = v_forward.x * flight_speed;
	vel.y = v_forward.y * flight_speed;
	vel.z = v_forward.z * flight_speed;

	vel.x += v_forward.x * eject_speed;
	vel.y += v_forward.y * eject_speed;
	vel.z += v_forward.z * eject_speed;
	eject_speed *= 0.1 * ((ranrot_rand() % 10) - 5);   //  -0.5x .. +0.5x
	vel.x += v_up.x * eject_speed;
	vel.y += v_up.y * eject_speed;
	vel.z += v_up.z * eject_speed;
	eject_speed *= 0.1 * ((ranrot_rand() % 10) - 5);   //  -0.25x .. +0.25x
	vel.x += v_right.x * eject_speed;
	vel.y += v_right.y * eject_speed;
	vel.z += v_right.z * eject_speed;
	[jetto setPosition:rpos];
	[jetto setQRotation:random_direction];
	[jetto setRoll:random_roll];
	[jetto setPitch:random_pitch];
	[jetto setVelocity:vel];
	[jetto setScanClass: CLASS_CARGO];
	[jetto setStatus: STATUS_IN_FLIGHT];
	[universe addEntity:jetto];
	[[jetto getAI] setState:@"GLOBAL"];
	[jetto release];
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
		[ent release];
	}	
}

- (BOOL) collideWithShip:(ShipEntity *)other
{
	Vector  loc, opos, pos;
	double  inc1, dam1;
	
//	NSLog(@"DEBUG %@ %d colliding with other %@ %d", name, universal_id, [other name], [other universal_id]);
	if (!other)
		return NO;
	
	// calculate line of centers using centres
	opos = other->position;
	loc = opos;
	loc.x -= position.x;	loc.y -= position.y;	loc.z -= position.z;
	double back_dist = 0.5 * (collision_radius + other->collision_radius - sqrt(magnitude2(loc)));
	
	loc = unit_vector(&loc);
	Vector back = make_vector( back_dist * loc.x, back_dist * loc.y, back_dist * loc.z);
	
	inc1 = (v_forward.x*loc.x)+(v_forward.y*loc.y)+(v_forward.z*loc.z);
	
	if ([self canScoop:other])
	{
		[self scoopUp:other];
		return NO;
	}
	if ([other canScoop:self])
	{
		[other scoopUp:self];
		return NO;
	}
	
	// back-off minimum distance
	pos = position;
	[self setPosition: pos.x - back.x :pos.y - back.y :pos.z - back.z];
	pos = other->position;
	[other setPosition: pos.x + back.x :pos.y + back.y :pos.z + back.z];
	
	// find velocity along line of centers
	// 
	// momentum = mass x velocity
	// ke = mass x velocity x velocity
	//
	GLfloat m1 = mass;
	GLfloat m2 = [other mass];
	//
	Vector	vel1 =	[self getVelocity];		// mass of self
	Vector	vel2 =	[other getVelocity];	// mass of other
	//
	GLfloat	v1 = dot_product( vel1, loc);	// velocity of self in direction of line of centers
	GLfloat	v2 = dot_product( vel2, loc);	// velocity of other in direction of line of centers
	//
	GLfloat v1a = (2 * m2 * v2 + (m1 - m2) * v1) / ( m1 + m2);	// velocity of self along loc after elastic collision
	GLfloat v2a = v1 - v2 + v1a;								// velocity of other along loc after elastic collision
	//
	Vector vel1a = make_vector( vel1.x + (v1a - v1) * loc.x, vel1.y + (v1a - v1) * loc.y, vel1.z + (v1a - v1) * loc.z);
	Vector vel2a = make_vector( vel2.x + (v2a - v2) * loc.x, vel2.y + (v2a - v2) * loc.y, vel2.z + (v2a - v2) * loc.z);
	//
	[self setVelocity:vel1a];
	[other setVelocity:vel2a];
	//
	// convert some velocity into damage energy
	//
	dam1 = (m1 + m2) * (v1 - v2) * (v1 - v2) / 100000000;
	//
	[self	takeScrapeDamage: dam1 from:other];
	[other	takeScrapeDamage: dam1 from:self];
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

- (void) addImpactMoment:(Vector) moment fraction:(GLfloat) howmuch
{
	momentum.x += howmuch * moment.x; 
	momentum.y += howmuch * moment.y; 
	momentum.z += howmuch * moment.z;
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
	Vector  loc = other->position;
	loc.x -= position.x;	loc.y -= position.y;	loc.z -= position.z;
	loc = unit_vector(&loc);
	double inc1 = (v_forward.x*loc.x)+(v_forward.y*loc.y)+(v_forward.z*loc.z);
	if (inc1 < 0)									return NO;
//	NSLog(@"DEBUG incidence 1 okay");
	double inc2 = (v_up.x*loc.x)+(v_up.y*loc.y)+(v_up.z*loc.z);
	if ((inc2 > 0)&&(scan_class == CLASS_PLAYER))	return NO;
//	NSLog(@"DEBUG incidence 2 okey dokey --> SHOULD SCOOP");
	return YES;
}

- (void) scoopUp:(ShipEntity *)other
{
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
					int i;
					PlayerEntity* player = (PlayerEntity *)[universe entityZero];
					[player setScript_target:self];
					for (i = 0; i < [actions count]; i++)
					{
						if ([[actions objectAtIndex:i] isKindOfClass:[NSDictionary class]])
							[player checkCouplet:	(NSDictionary *)[actions objectAtIndex:i]	onEntity:other];
						if ([[actions objectAtIndex:i] isKindOfClass:[NSString class]])
							[player scriptAction:	(NSString *)	[actions objectAtIndex:i]	onEntity:other];
					}
//						[(PlayerEntity *)[universe entityZero] scriptAction:(NSString *)[actions objectAtIndex:i] onEntity:other];
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
//		[[other collisionArray] removeObject:self];			// so it can't be scooped twice!
		[shipAI message:@"CARGO_SCOOPED"];
		if ([cargo count] == max_cargo)
			[shipAI message:@"HOLD_FULL"];
	}
	[[other collisionArray] removeObject:self];			// so it can't be scooped twice!
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

- (void) enterDock:(StationEntity *)station
{
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
//	position.x += SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5); // randomise exit position
//	position.y += SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
//	position.z += SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
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
	if (![roles isEqual:@"police"])
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

- (BOOL) acceptAsEscort:(ShipEntity *) other_ship
{
	BOOL pairing_okay = NO;
	
	// check status
	//if (!accepts_escorts)
	//	return NO;
	
	// if not in standard ai mode reject approach
	//NSLog(@"%@ %d asked to accept %@ %d as escort when ai_stack_depth is %d", name, universal_id, [other_ship name], [other_ship universal_id], [shipAI ai_stack_depth]);
	if ([shipAI ai_stack_depth] > 1)
		return NO;
	
//	pairing_okay |= (([roles isEqual:@"trader"])&&([[other_ship roles] isEqual:@"escort"]));
	pairing_okay |= (([roles isEqual:@"trader"])&&([[other_ship roles] isEqual:@"escort"]));
	pairing_okay |= (([roles isEqual:@"police"])&&([[other_ship roles] isEqual:@"wingman"]));
	pairing_okay |= (([roles isEqual:@"interceptor"])&&([[other_ship roles] isEqual:@"wingman"]));
	
	if (pairing_okay)
	{
		// check it's not already been accepted
		int i;
		for (i = 0; i < n_escorts; i++)
		{
			if (escort_ids[i] == [other_ship universal_id])
			{
				//NSLog(@"DEBUG trader %@ %d has already accepted escort %@ %d", name, universal_id, [other_ship name], [other_ship universal_id]);
				[other_ship setGroup_id:universal_id];
				[self setGroup_id:universal_id];		// make self part of same group
				return YES;
			}
		}
		
		if (n_escorts < MAX_ESCORTS)
		{
			escort_ids[n_escorts] = [other_ship universal_id];
			[other_ship setGroup_id:universal_id];
			[self setGroup_id:universal_id];		// make self part of same group
			n_escorts++;
			
			//debug
			//NSLog(@"DEBUG %@ %@ %d accepts escort %@ %d", roles, name, universal_id, [other_ship name], [other_ship universal_id]);
			
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
		NSLog(@"DEBUG attempting to deploy more escorts onto same target - denied");
		return;
	}
	
	last_escort_target = primaryTarget;
	
	int n_deploy = ranrot_rand() % n_escorts;
	if (n_deploy == 0)
		n_deploy = 1;
	
	//NSLog(@"DEBUG %@ %d deploying %d escorts", name, universal_id, n_deploy);
	
	int i_deploy = n_escorts - 1;
	while (n_deploy > 0)
	{
		int escort_id = escort_ids[i_deploy];
		ShipEntity  *escorter = (ShipEntity *)[universe entityForUniversalID:escort_id];
		if (escorter)
		{
			[escorter setGroup_id:NO_TARGET];	// act individually now!
			[escorter addTarget:[self getPrimaryTarget]];
			[[escorter getAI] setStateMachine:@"interceptAI.plist"];
			[[escorter getAI] setState:@"GLOBAL"];
			
			//debug
			//NSLog(@"DEBUG trader %@ %d deploys escort %@ %d", name, universal_id, [escorter name], [escorter universal_id]);
			//[escorter setReportAImessages:YES];
		}
		escort_ids[i_deploy] = NO_TARGET;
		i_deploy--;
		n_deploy--;
		n_escorts--;
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
		if (escorter)
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
	[[universe comm_log_gui] setTextColor:[NSColor colorWithCalibratedHue:hue saturation:0.375 brightness:1.0 alpha:1.0]];
	if (scan_class == CLASS_THARGOID)
		[[universe comm_log_gui] setTextColor:[NSColor greenColor]];
	if (scan_class == CLASS_POLICE)
		[[universe comm_log_gui] setTextColor:[NSColor cyanColor]];
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
	return ((condition == CONDITION_ATTACK_MINING_TARGET)&&(forward_weapon_type == WEAPON_MINING_LASER));
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
		NSArray* tokens = [ms componentsSeparatedByString:@" "];
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
	Vector pv, rv;
	Vector  rpos = position;
	Vector  opv = (other)? other->position : position;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < n_vertices; i++)
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

- (BoundingBox) findBoundingBoxRelativeToPosition:(Vector)opv InVectors:(Vector) _i :(Vector) _j :(Vector) _k
{
	Vector pv, rv;
	Vector  rpos = position;
	rpos.x -= opv.x;	rpos.y -= opv.y;	rpos.z -= opv.z;
	rv.x = dot_product(_i,rpos);
	rv.y = dot_product(_j,rpos);
	rv.z = dot_product(_k,rpos);
	BoundingBox result;
	bounding_box_reset_to_vector(&result,rv);
	int i;
    for (i = 0; i < n_vertices; i++)
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
	NSMutableArray*	tokens = [NSMutableArray arrayWithArray:[roles_number componentsSeparatedByString:@" "]];
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
	
	if (debug)
		NSLog(@"DEBUG ..... Going to spawn %d x '%@' near %@ %d", number, roleString, name, universal_id);

	while (number--)
		[universe spawnShipWithRole:roleString near:self];
}

//- (Vector) getVelocity
//{
//	return make_vector( velocity.x + v_forward.x * flight_speed, velocity.y + v_forward.y * flight_speed, velocity.z + v_forward.z * flight_speed);
//}

- (BOOL *) face_hit
{
	return face_hit;
}

@end
