//
//  PlayerEntity.m
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

#import "PlayerEntity.h"
#import "PlayerEntity Additions.h"
#import "PlayerEntity (contracts).h"
#import "PlayerEntity (Controls).h"
#import "PlayerEntity (Sound).h"
#import "entities.h"

#import "OOXMLExtensions.h"

#import "vector.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "Universe.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "OOTrumble.h"
#import "LoadSave.h"
#import "OOSound.h"
#import "OOColor.h"

#ifndef GNUSTEP
#import "Groolite.h"
#else
#import "JoystickHandler.h"
#import "PlayerEntity_StickMapper.h"
#endif

// 10m/s forward drift
#define	OG_ELITE_FORWARD_DRIFT			10.0f


@implementation PlayerEntity

static Quaternion quaternion_identity = { (GLfloat)1.0, (GLfloat)0.0, (GLfloat)0.0, (GLfloat)0.0};

- (void) init_keys
{
	NSDictionary	*kdic = [ResourceManager dictionaryFromFilesNamed:@"keyconfig.plist" inFolder:@"Config" andMerge:YES];
	//
	key_roll_left = gvArrowKeyLeft;
	key_roll_right = gvArrowKeyRight;
	key_pitch_forward = gvArrowKeyUp;
	key_pitch_back = gvArrowKeyDown;
	key_increase_speed = 119;		// 'w'
	key_inject_fuel = 105;			// 'i'
	key_decrease_speed = 115;		// 's'
	key_fire_lasers = 97;			// 'a'
	key_target_missile = 116;		// 't'
	key_untarget_missile = 117;		// 'u'
	key_launch_missile = 109;		// 'm'
	key_ecm = 101;					// 'e'
	key_launch_escapepod = 27;		// 'esc'
	key_energy_bomb = 9;			// 'tab'
	key_galactic_hyperspace = 103;	// 'g'
	key_hyperspace = 104;			// 'h'
	key_jumpdrive = 106;			// 'j'
	key_dump_cargo = 100;			// 'd'
	key_rotate_cargo = 82;			// 'R'
	key_autopilot = 99;				// 'c'
	//
	key_autopilot_target = 67;		// 'C'
	//
	key_autodock = 68;				// 'D'
	key_snapshot = 42;				// '*'
	key_docking_music = 115;		// 's'
	key_scanner_zoom = 122;			// 'z'
	key_scanner_unzoom = 90;		// 'Z'
	//
	key_map_dump = 33;				// '!'
	key_map_home = gvHomeKey;		// 'home'
	key_map_info = 105;				// 'i'
	//
	key_pausebutton = 112;			// 'p'
	key_show_fps = 70;				// 'F'
	key_mouse_control = 77;			// 'M'
	//
	key_emergency_hyperdrive = 72;	// 'H'
	//
	key_next_missile = 121;			// 'y'
	key_ident_system = 114;			// 'r'
	//
	key_comms_log = 96;				// '`'
	//
	key_next_compass_mode = 92;		// '\'
	//
	key_cloaking_device = 48;		// '0'
	//
	key_contract_info = 63;			// '?'
	//
	key_next_target = 45;			// '+'
	key_previous_target = 43;		// '-'
	//
	// now check the keyconfig dictionary...
	if ([kdic objectForKey:@"key_roll_left"])		key_roll_left = [(NSNumber *)[kdic objectForKey:@"key_roll_left"] intValue];
	if ([kdic objectForKey:@"key_roll_right"])		key_roll_right = [(NSNumber *)[kdic objectForKey:@"key_roll_right"] intValue];
	if ([kdic objectForKey:@"key_pitch_forward"])   key_pitch_forward = [(NSNumber *)[kdic objectForKey:@"key_pitch_forward"] intValue];
	if ([kdic objectForKey:@"key_pitch_back"])		key_pitch_back = [(NSNumber *)[kdic objectForKey:@"key_pitch_back"] intValue];
	if ([kdic objectForKey:@"key_increase_speed"])  key_increase_speed = [(NSNumber *)[kdic objectForKey:@"key_increase_speed"] intValue];
	if ([kdic objectForKey:@"key_decrease_speed"])  key_decrease_speed = [(NSNumber *)[kdic objectForKey:@"key_decrease_speed"] intValue];
	if ([kdic objectForKey:@"key_inject_fuel"])		key_inject_fuel = [(NSNumber *)[kdic objectForKey:@"key_inject_fuel"] intValue];
	if ([kdic objectForKey:@"key_fire_lasers"])		key_fire_lasers = [(NSNumber *)[kdic objectForKey:@"key_fire_lasers"] intValue];
	if ([kdic objectForKey:@"key_target_missile"])  key_target_missile = [(NSNumber *)[kdic objectForKey:@"key_target_missile"] intValue];
	if ([kdic objectForKey:@"key_untarget_missile"])	key_untarget_missile = [(NSNumber *)[kdic objectForKey:@"key_untarget_missile"] intValue];
	if ([kdic objectForKey:@"key_launch_missile"])  key_launch_missile = [(NSNumber *)[kdic objectForKey:@"key_launch_missile"] intValue];
	if ([kdic objectForKey:@"key_ecm"])				key_ecm = [(NSNumber *)[kdic objectForKey:@"key_ecm"] intValue];
	if ([kdic objectForKey:@"key_launch_escapepod"])	key_launch_escapepod = [(NSNumber *)[kdic objectForKey:@"key_launch_escapepod"] intValue];
	if ([kdic objectForKey:@"key_energy_bomb"])		key_energy_bomb = [(NSNumber *)[kdic objectForKey:@"key_energy_bomb"] intValue];
	if ([kdic objectForKey:@"key_galactic_hyperspace"]) key_galactic_hyperspace = [(NSNumber *)[kdic objectForKey:@"key_galactic_hyperspace"] intValue];
	if ([kdic objectForKey:@"key_hyperspace"])		key_hyperspace = [(NSNumber *)[kdic objectForKey:@"key_hyperspace"] intValue];
	if ([kdic objectForKey:@"key_jumpdrive"])		key_jumpdrive = [(NSNumber *)[kdic objectForKey:@"key_jumpdrive"] intValue];
	if ([kdic objectForKey:@"key_dump_cargo"])		key_dump_cargo = [(NSNumber *)[kdic objectForKey:@"key_dump_cargo"] intValue];
	if ([kdic objectForKey:@"key_rotate_cargo"])	key_rotate_cargo = [(NSNumber *)[kdic objectForKey:@"key_rotate_cargo"] intValue];
	if ([kdic objectForKey:@"key_autopilot"])		key_autopilot = [(NSNumber *)[kdic objectForKey:@"key_autopilot"] intValue];
	if ([kdic objectForKey:@"key_autodock"])		key_autodock = [(NSNumber *)[kdic objectForKey:@"key_autodock"] intValue];
	if ([kdic objectForKey:@"key_snapshot"])		key_snapshot = [(NSNumber *)[kdic objectForKey:@"key_snapshot"] intValue];
	if ([kdic objectForKey:@"key_docking_music"])   key_docking_music = [(NSNumber *)[kdic objectForKey:@"key_docking_music"] intValue];
	if ([kdic objectForKey:@"key_scanner_zoom"])	key_scanner_zoom = [(NSNumber *)[kdic objectForKey:@"key_scanner_zoom"] intValue];
	if ([kdic objectForKey:@"key_scanner_unzoom"])	key_scanner_unzoom = [(NSNumber *)[kdic objectForKey:@"key_scanner_unzoom"] intValue];
	//
	if ([kdic objectForKey:@"key_next_target"])		key_next_target = [(NSNumber *)[kdic objectForKey:@"key_next_target"] intValue];
	if ([kdic objectForKey:@"key_previous_target"])	key_previous_target = [(NSNumber *)[kdic objectForKey:@"key_previous_target"] intValue];
	//
	if ([kdic objectForKey:@"key_map_dump"])		key_map_dump = [(NSNumber *)[kdic objectForKey:@"key_map_dump"] intValue];
	if ([kdic objectForKey:@"key_map_home"])		key_map_home = [(NSNumber *)[kdic objectForKey:@"key_map_home"] intValue];
	//
	if ([kdic objectForKey:@"key_mouse_control"])
		key_mouse_control = [(NSNumber *)[kdic objectForKey:@"key_mouse_control"] intValue];
	if ([kdic objectForKey:@"key_pausebutton"])
		key_pausebutton = [(NSNumber *)[kdic objectForKey:@"key_pausebutton"] intValue];
	if ([kdic objectForKey:@"key_show_fps"])
		key_show_fps = [(NSNumber *)[kdic objectForKey:@"key_show_fps"] intValue];
	//
	if ([kdic objectForKey:@"key_next_missile"])
		key_next_missile = [(NSNumber *)[kdic objectForKey:@"key_next_missile"] intValue];
	if ([kdic objectForKey:@"key_ident_system"])
		key_ident_system = [(NSNumber *)[kdic objectForKey:@"key_ident_system"] intValue];
	//
	if ([kdic objectForKey:@"key_comms_log"])
		key_comms_log = [(NSNumber *)[kdic objectForKey:@"key_comms_log"] intValue];
	//
	if ([kdic objectForKey:@"key_next_compass_mode"])
		key_next_compass_mode = [(NSNumber *)[kdic objectForKey:@"key_next_compass_mode"] intValue];
	//
	if ([kdic objectForKey:@"key_cloaking_device"])
		key_cloaking_device = [(NSNumber *)[kdic objectForKey:@"key_cloaking_device"] intValue];
	//
	if ([kdic objectForKey:@"key_contract_info"])
		key_contract_info = [(NSNumber *)[kdic objectForKey:@"key_contract_info"] intValue];
	//
	if ([kdic objectForKey:@"key_next_target"])
		key_next_target = [(NSNumber *)[kdic objectForKey:@"key_next_target"] intValue];
	if ([kdic objectForKey:@"key_previous_target"])
		key_previous_target = [(NSNumber *)[kdic objectForKey:@"key_previous_target"] intValue];
	//
	if ([kdic objectForKey:@"key_map_info"])
		key_map_info = [(NSNumber *)[kdic objectForKey:@"key_map_info"] intValue];
	//
	// other keys are SET and cannot be varied

   // Enable polling
   pollControls=YES;
}

- (void) unloadCargoPods
{
	/* loads commodities from the cargo pods onto the ship's manifest */
	int i;
	NSMutableArray* localMarket = [docked_station localMarket]; 
	NSMutableArray* manifest = [[NSMutableArray arrayWithArray:localMarket] retain];  // retain
	//
	// copy the quantities in ShipCommodityData to the manifest
	// (was: zero the quantities in the manifest, making a mutable array of mutable arrays)
	//
	for (i = 0; i < [manifest count]; i++)
	{
		NSMutableArray* commodityInfo = [NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:i]];
		NSArray* shipCommInfo = [NSArray arrayWithArray:(NSArray *)[shipCommodityData objectAtIndex:i]];
		int amount = [(NSNumber*)[shipCommInfo objectAtIndex:MARKET_QUANTITY] intValue];
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:amount]];
		[manifest replaceObjectAtIndex:i withObject:commodityInfo];
	}
	//
	NSArray* cargoArray = [[NSArray arrayWithArray:cargo] retain];  // retain
	//
	// step through the cargo pods adding in the quantities
	//
	for (i = 0; i < [cargoArray count]; i++)
	{
		NSMutableArray* commodityInfo;
		int co_type, co_amount, quantity;

		co_type = [(ShipEntity *)[cargoArray objectAtIndex:i] getCommodityType];
		co_amount = [(ShipEntity *)[cargoArray objectAtIndex:i] getCommodityAmount];

//		NSLog(@"unloading a %@ with %@", [(ShipEntity *)[cargoArray objectAtIndex:i] name], [universe describeCommodity:co_type amount:co_amount]);

		commodityInfo = (NSMutableArray *)[manifest objectAtIndex:co_type];
		quantity =  [(NSNumber *)[commodityInfo objectAtIndex:MARKET_QUANTITY] intValue] + co_amount;
		
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity]]; // enter the adjusted quantity
	}
	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	[manifest release]; // release, done
	[cargoArray release]; // release, done
	for (i = 0; i < [cargoArray count]; i++)	// recycle these entities rather than leave them to be garbage collected
	{
		[(Entity *)[cargoArray objectAtIndex:i] setStatus:STATUS_DEAD];
		[universe recycleOrDiscard:(Entity *)[cargoArray objectAtIndex:i]];
	}
	[cargo removeAllObjects];   // empty the hold
}

- (void) loadCargoPods
{
	/* loads commodities from the ships manifest into individual cargo pods */
	int i,j;
	NSMutableArray* localMarket = [docked_station localMarket]; 
	NSMutableArray* manifest = [[NSMutableArray arrayWithArray:shipCommodityData] retain];  // retain
	for (i = 0; i < [manifest count]; i++)
	{
		NSMutableArray* commodityInfo = [[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:i]] retain];  // retain
		int quantity =  [(NSNumber *)[commodityInfo objectAtIndex:MARKET_QUANTITY] intValue];
		int units =		[universe unitsForCommodity:i];
//		NSLog(@"DEBUG Commodity index:%d %@ units:%d", i, [commodityInfo objectAtIndex:MARKET_NAME], units);
		if (quantity > 0)
		{
			//NSLog(@"loading containers with %@",[universe describeCommodity:i amount:quantity]);

			if (units == UNITS_TONS)
			{
				// put each ton in a separate container
				for (j = 0; j < quantity; j++)
				{
					ShipEntity* container = [universe getShipWithRole:@"1t-cargopod"];
					if (container)
					{
						[container setUniverse:universe];
						[container setScanClass: CLASS_CARGO];
						[container setStatus:STATUS_IN_HOLD];
						[container setCommodity:i andAmount:1];
						[cargo addObject:container];
						[container release];
					}
					else
					{
						NSLog(@"***** ERROR couldn't find a container while trying to [PlayerEntity loadCargoPods] *****");
						// throw an exception here...
						NSException* myException = [NSException
							exceptionWithName: OOLITE_EXCEPTION_FATAL
							reason:@"[PlayerEntity loadCargoPods] failed to create a container for cargo with role 'cargopod'"
							userInfo:nil];
						[myException raise];
					}
				}
				// zero this commodity
				[commodityInfo setArray:(NSArray *)[localMarket objectAtIndex:i]];
				[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
				[manifest replaceObjectAtIndex:i withObject:[NSArray arrayWithArray:commodityInfo]];
			}
		}
		[commodityInfo release]; // release, done
	}
	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	[manifest release]; // release, done
}

- (int) random_factor
{
	return market_rnd;
}

- (Random_Seed) galaxy_seed
{
	return galaxy_seed;
}

- (NSPoint) galaxy_coordinates
{
	return galaxy_coordinates;
}

- (NSPoint) cursor_coordinates
{
	return cursor_coordinates;
}

- (Random_Seed) system_seed
{
	return system_seed;
}

- (void) setSystem_seed:(Random_Seed) s_seed
{
	system_seed = s_seed;
	galaxy_coordinates = NSMakePoint( s_seed.d, s_seed.b);
}

- (Random_Seed) target_system_seed
{
	return target_system_seed;
}

- (NSDictionary *) commanderDataDictionary
{
	NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:20]; // retained

	NSString *gal_seed = [NSString stringWithFormat:@"%d %d %d %d %d %d",galaxy_seed.a, galaxy_seed.b, galaxy_seed.c, galaxy_seed.d, galaxy_seed.e, galaxy_seed.f]; 
	NSString *gal_coords = [NSString stringWithFormat:@"%d %d",(int)galaxy_coordinates.x,(int)galaxy_coordinates.y]; 
	NSString *tgt_coords = [NSString stringWithFormat:@"%d %d",(int)cursor_coordinates.x,(int)cursor_coordinates.y]; 
	
	[result setObject:gal_seed		forKey:@"galaxy_seed"];
	[result setObject:gal_coords	forKey:@"galaxy_coordinates"];
	[result setObject:tgt_coords	forKey:@"target_coordinates"];
	//
	[result setObject:player_name			forKey:@"player_name"];
	//
	[result setObject:[NSNumber numberWithInt:credits]				forKey:@"credits"];
	[result setObject:[NSNumber numberWithInt:fuel]					forKey:@"fuel"];
	//
	[result setObject:[NSNumber numberWithInt:galaxy_number]		forKey:@"galaxy_number"];
	//
	[result setObject:[NSNumber numberWithInt:forward_weapon]		forKey:@"forward_weapon"];
	[result setObject:[NSNumber numberWithInt:aft_weapon]			forKey:@"aft_weapon"];
	[result setObject:[NSNumber numberWithInt:port_weapon]			forKey:@"port_weapon"];
	[result setObject:[NSNumber numberWithInt:starboard_weapon]		forKey:@"starboard_weapon"];
	//
	[result setObject:[NSNumber numberWithInt:max_cargo + 5 * max_passengers]	forKey:@"max_cargo"];
	//
	[result setObject:shipCommodityData		forKey:@"shipCommodityData"];
	//
	[result setObject:[NSNumber numberWithBool:has_ecm]					forKey:@"has_ecm"];
	[result setObject:[NSNumber numberWithBool:has_scoop]				forKey:@"has_scoop"];
	[result setObject:[NSNumber numberWithBool:has_energy_bomb]			forKey:@"has_energy_bomb"];
	[result setObject:[NSNumber numberWithBool:has_energy_unit]			forKey:@"has_energy_unit"];
	[result setObject:[NSNumber numberWithInt:energy_unit]				forKey:@"energy_unit"];
	[result setObject:[NSNumber numberWithBool:has_docking_computer]	forKey:@"has_docking_computer"];
	[result setObject:[NSNumber numberWithBool:has_galactic_hyperdrive] forKey:@"has_galactic_hyperdrive"];
	[result setObject:[NSNumber numberWithBool:has_escape_pod]			forKey:@"has_escape_pod"];
	[result setObject:[NSNumber numberWithBool:has_fuel_injection]		forKey:@"has_fuel_injection"];
	NSMutableArray* missile_roles = [NSMutableArray arrayWithCapacity:max_missiles];
	int i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i])
		{
			[missile_roles addObject:[missile_entity[i] roles]];
		}
		else
			[missile_roles addObject:@"NONE"];
	}
	[result setObject:missile_roles forKey:@"missile_roles"];
//	[self safe_all_missiles];	// affects missile_status!!
	//
	[result setObject:[NSNumber numberWithInt:[self calc_missiles]]		forKey:@"missiles"];
	//
	[result setObject:[NSNumber numberWithInt:legal_status]				forKey:@"legal_status"];
	[result setObject:[NSNumber numberWithInt:market_rnd]				forKey:@"market_rnd"];
	[result setObject:[NSNumber numberWithInt:ship_kills]				forKey:@"ship_kills"];
	[result setObject:[NSNumber numberWithBool:saved]					forKey:@"saved"];
	
	// ship depreciation
	[result setObject:[NSNumber numberWithInt:ship_trade_in_factor]		forKey:@"ship_trade_in_factor"];
	
	// mission variables
	if (mission_variables)
		[result setObject:[NSDictionary dictionaryWithDictionary:mission_variables] forKey:@"mission_variables"];

	// communications log
	if (comm_log)
	{
		while ([comm_log count] > 200)			// only keep the last 200 lines
			[comm_log removeObjectAtIndex:0];			
		[result setObject:comm_log forKey:@"comm_log"];
	}
	
	// extra equipment flags
	if (extra_equipment)
	{
		[self set_extra_equipment_from_flags];
		[result setObject:[NSDictionary dictionaryWithDictionary:extra_equipment] forKey:@"extra_equipment"];
	}
	
	// reputation
	[result setObject:reputation forKey:@"reputation"];
	
	// passengers
	[result setObject:[NSNumber numberWithInt:max_passengers] forKey:@"max_passengers"];
	[result setObject:passengers forKey:@"passengers"];
	[result setObject:passenger_record forKey:@"passenger_record"];
	
	// contracts
	[result setObject:contracts forKey:@"contracts"];
	[result setObject:contract_record forKey:@"contract_record"];
	
	//shipyard
	[result setObject:shipyard_record forKey:@"shipyard_record"];
	
	//ship's clock
	[result setObject:[NSNumber numberWithDouble:ship_clock] forKey:@"ship_clock"];
	
	//speech
	[result setObject:[NSNumber numberWithBool:speech_on] forKey:@"speech_on"];
	
	//ootunes
	[result setObject:[NSNumber numberWithBool:ootunes_on] forKey:@"ootunes_on"];
	
	//base ship description
	[result setObject:ship_desc forKey:@"ship_desc"];
	
	//local market
	if ([docked_station localMarket])
		[result setObject:[docked_station localMarket] forKey:@"localMarket"];
	
	// reduced detail option
	[result setObject:[NSNumber numberWithBool:[universe reducedDetail]] forKey:@"reducedDetail"];
	
	// strict universe?
	if ([universe strict])
	{
		[result setObject:[NSNumber numberWithBool:YES] forKey:@"strict"];
	}
	
	// persistant universe information
	if ([universe local_planetinfo_overrides])
	{
		[result setObject:[universe local_planetinfo_overrides] forKey:@"local_planetinfo_overrides"];
	}
	
	// trumble information
	[result setObject:[self trumbleValue] forKey:@"trumbles"];
	
	// create checksum
	clear_checksum();
	munge_checksum(galaxy_seed.a);	munge_checksum(galaxy_seed.b);	munge_checksum(galaxy_seed.c);
	munge_checksum(galaxy_seed.d);	munge_checksum(galaxy_seed.e);	munge_checksum(galaxy_seed.f);
	munge_checksum((int)galaxy_coordinates.x);	munge_checksum((int)galaxy_coordinates.y);
	munge_checksum(credits);		munge_checksum(fuel);
	munge_checksum(max_cargo);		munge_checksum(missiles);
	munge_checksum(legal_status);	munge_checksum(market_rnd);		munge_checksum(ship_kills);
	if (mission_variables)
		munge_checksum([[mission_variables description] length]);
	if (extra_equipment)
		munge_checksum([[extra_equipment description] length]);
	int final_checksum = munge_checksum([[ship_desc description] length]);
	
	//set checksum
	[result setObject:[NSNumber numberWithInt:final_checksum] forKey:@"checksum"];
		
	//NSLog(@"Player Dictionary :\n%@",[result description]);
	
	//DEBUG TEST
//	NSLog(@"DEBUG TESTING OOXML Export Dictionary:-\n%@", [result OOXMLdescription]);

	return [NSDictionary dictionaryWithDictionary:[result autorelease]];
}

- (void) setCommanderDataFromDictionary:(NSDictionary *) dict
{
	if ([dict objectForKey:@"strict"])
	{
		if (![universe strict])
		{
			// reset to strict and reload player
			NSLog(@"DEBUG loading a STRICT player dictionary ..1");
			[universe setStrict:YES];
			NSLog(@"DEBUG loading a STRICT player dictionary ..2");
		}
	}
	else
	{
		if ([universe strict])
		{
			// reset to unrestricted and reload player
			NSLog(@"DEBUG loading a UNRESTRICTED player dictionary ..1");
			[universe setStrict:NO];
			NSLog(@"DEBUG loading a UNRESTRICTED player dictionary ..2");
		}
	}
	//base ship description
	if ([dict objectForKey:@"ship_desc"])
	{
		NSDictionary*	ship_dict = nil;
		if (ship_desc) [ship_desc release];
		ship_desc = [(NSString *)[dict objectForKey:@"ship_desc"] retain];
		NS_DURING
			ship_dict = [universe getDictionaryForShip:ship_desc];
		NS_HANDLER
			if ([[localException name] isEqual: OOLITE_EXCEPTION_SHIP_NOT_FOUND])
				ship_dict = nil;
			else
				[localException raise];
		NS_ENDHANDLER
		if (ship_dict)
			[self setUpShipFromDictionary:ship_dict];
		else
		{
			NSException* myException = [NSException
				exceptionWithName: OOLITE_EXCEPTION_SHIP_NOT_FOUND
				reason:[NSString stringWithFormat:@"Couldn't set player ship to '%@' (it couldn't be found)", ship_desc]
				userInfo:nil];
			[myException raise];
			return;
		}
	}
	
	// ship depreciation
	if ([dict objectForKey:@"ship_trade_in_factor"])
		ship_trade_in_factor = [(NSNumber*)[dict objectForKey:@"ship_trade_in_factor"] intValue];
	else
		ship_trade_in_factor = 95;
	
	if ([dict objectForKey:@"galaxy_seed"])
	{
		NSArray *seed_vals = [Entity scanTokensFromString:(NSString *)[dict objectForKey:@"galaxy_seed"]];
		galaxy_seed.a = (unsigned char)[(NSString *)[seed_vals objectAtIndex:0] intValue];
		galaxy_seed.b = (unsigned char)[(NSString *)[seed_vals objectAtIndex:1] intValue];
		galaxy_seed.c = (unsigned char)[(NSString *)[seed_vals objectAtIndex:2] intValue];
		galaxy_seed.d = (unsigned char)[(NSString *)[seed_vals objectAtIndex:3] intValue];
		galaxy_seed.e = (unsigned char)[(NSString *)[seed_vals objectAtIndex:4] intValue];
		galaxy_seed.f = (unsigned char)[(NSString *)[seed_vals objectAtIndex:5] intValue];
	}
	
	if ([dict objectForKey:@"galaxy_coordinates"])
	{
		NSArray *coord_vals = [Entity scanTokensFromString:(NSString *)[dict objectForKey:@"galaxy_coordinates"]];
		galaxy_coordinates.x = (unsigned char)[(NSString *)[coord_vals objectAtIndex:0] intValue];
		galaxy_coordinates.y = (unsigned char)[(NSString *)[coord_vals objectAtIndex:1] intValue];
		cursor_coordinates = galaxy_coordinates;
	}
	
	if ([dict objectForKey:@"target_coordinates"])
	{
		NSArray *coord_vals = [Entity scanTokensFromString:(NSString *)[dict objectForKey:@"target_coordinates"]];
		cursor_coordinates.x = (unsigned char)[(NSString *)[coord_vals objectAtIndex:0] intValue];
		cursor_coordinates.y = (unsigned char)[(NSString *)[coord_vals objectAtIndex:1] intValue];
	}
	
	if ([dict objectForKey:@"player_name"])
	{
		if (player_name)	[player_name release];
		player_name = [(NSString *)[dict objectForKey:@"player_name"] retain];
	}
	
	if ([dict objectForKey:@"shipCommodityData"])
	{
		if (shipCommodityData)  [shipCommodityData release];
		shipCommodityData = [(NSArray *)[dict objectForKey:@"shipCommodityData"] retain];
	}

	// extra equipment flags
	[extra_equipment removeAllObjects];
	[self set_extra_equipment_from_flags];
	if ([dict objectForKey:@"extra_equipment"])
	{
		[extra_equipment addEntriesFromDictionary:(NSDictionary *)[dict objectForKey:@"extra_equipment"]];
	}
	// bools	(mostly deprecated by use of the extra_equipment dictionary, keep for compatibility)
	//
	if (([dict objectForKey:@"has_docking_computer"])&&([(NSNumber *)[dict objectForKey:@"has_docking_computer"] boolValue]))
		[self add_extra_equipment:@"EQ_DOCK_COMP"];
	if (([dict objectForKey:@"has_galactic_hyperdrive"])&&([(NSNumber *)[dict objectForKey:@"has_galactic_hyperdrive"] boolValue]))
		[self add_extra_equipment:@"EQ_GAL_DRIVE"];
	if (([dict objectForKey:@"has_escape_pod"])&&([(NSNumber *)[dict objectForKey:@"has_escape_pod"] boolValue]))
		[self add_extra_equipment:@"EQ_ESCAPE_POD"];
	if (([dict objectForKey:@"has_ecm"])&&([(NSNumber *)[dict objectForKey:@"has_ecm"] boolValue]))
		[self add_extra_equipment:@"EQ_ECM"];
	if (([dict objectForKey:@"has_scoop"])&&([(NSNumber *)[dict objectForKey:@"has_scoop"] boolValue]))
		[self add_extra_equipment:@"EQ_FUEL_SCOOPS"];
	if (([dict objectForKey:@"has_energy_bomb"])&&([(NSNumber *)[dict objectForKey:@"has_energy_bomb"] boolValue]))
		[self add_extra_equipment:@"EQ_ENERGY_BOMB"];
	//
	if (([dict objectForKey:@"has_fuel_injection"])&&([(NSNumber *)[dict objectForKey:@"has_fuel_injection"] boolValue]))
		[self add_extra_equipment:@"EQ_FUEL_INJECTION"];
	if (([dict objectForKey:@"has_energy_unit"])&&([(NSNumber *)[dict objectForKey:@"has_energy_unit"] boolValue]))
	{
		if ([dict objectForKey:@"energy_unit"])
			energy_unit = [(NSNumber *)[dict objectForKey:@"energy_unit"]   intValue]; // load specials
		else
			energy_unit = (has_energy_unit) ? ENERGY_UNIT_NORMAL : ENERGY_UNIT_NONE;	// set default
		switch (energy_unit)
		{
			case ENERGY_UNIT_NORMAL :
			[self add_extra_equipment:@"EQ_ENERGY_UNIT"];
			break;
			case ENERGY_UNIT_NAVAL :
			[self add_extra_equipment:@"EQ_NAVAL_ENERGY_UNIT"];
			break;
			default :
			break;
		}
	}
	
	// speech
	if ([dict objectForKey:@"speech_on"])
		speech_on = [(NSNumber *)[dict objectForKey:@"speech_on"] boolValue];
	
	// reputation
	if ([dict objectForKey:@"reputation"])
	{
		if (reputation)
			[reputation release];
		reputation = [[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[dict objectForKey:@"reputation"]] retain];
	}
	
	// passengers
	if ([dict objectForKey:@"max_passengers"])
		max_passengers = [(NSNumber *)[dict objectForKey:@"max_passengers"] intValue];
	else
		max_passengers = 0;
	if ([dict objectForKey:@"passengers"])
	{
		if (passengers)
			[passengers release];
		passengers = [[NSMutableArray arrayWithArray:(NSArray *)[dict objectForKey:@"passengers"]] retain];
	}
	else
	{
		if (passengers)
			[passengers release];
		passengers = [[NSMutableArray arrayWithCapacity:8] retain];
	}
	if ([dict objectForKey:@"passenger_record"])
	{
		if (passenger_record)
			[passenger_record release];
		passenger_record = [[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[dict objectForKey:@"passenger_record"]] retain];
	}
	else
	{
		if (passenger_record)
			[passenger_record release];
		passenger_record = [[NSMutableDictionary dictionaryWithCapacity:8] retain];
	}
	
	// contracts
	if ([dict objectForKey:@"contracts"])
	{
		if (contracts)
			[contracts release];
		contracts = [[NSMutableArray arrayWithArray:(NSArray *)[dict objectForKey:@"contracts"]] retain];
	}
	else
	{
		if (contracts)
			[contracts release];
		contracts = [[NSMutableArray arrayWithCapacity:8] retain];
	}
	if ([dict objectForKey:@"contract_record"])
	{
		if (contract_record)
			[contract_record release];
		contract_record = [[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[dict objectForKey:@"contract_record"]] retain];
	}
	else
	{
		if (contract_record)
			[contract_record release];
		contract_record = [[NSMutableDictionary dictionaryWithCapacity:8] retain];
	}
	
	// shipyard
	if ([dict objectForKey:@"shipyard_record"])
	{
		if (shipyard_record)
			[shipyard_record release];
		shipyard_record = [[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[dict objectForKey:@"shipyard_record"]] retain];
	}
	else
	{
		if (shipyard_record)
			[shipyard_record release];
		shipyard_record = [[NSMutableDictionary dictionaryWithCapacity:4] retain];
	}
	
	// ootunes
	if ([dict objectForKey:@"ootunes_on"])
		ootunes_on = [(NSNumber *)[dict objectForKey:@"ootunes_on"] boolValue];

	// reducedDetail
	if ([dict objectForKey:@"reducedDetail"])
		[universe setReducedDetail:[(NSNumber *)[dict objectForKey:@"reducedDetail"] boolValue]];

	if ([dict objectForKey:@"saved"])
		saved = [(NSNumber *)[dict objectForKey:@"saved"] boolValue];
		
	// ints
	//
	int original_hold_size = [universe maxCargoForShip:ship_desc];
	if ([dict objectForKey:@"max_cargo"])
		max_cargo = [(NSNumber *)[dict objectForKey:@"max_cargo"]	intValue];
	if (max_cargo > original_hold_size)
		[self add_extra_equipment:@"EQ_CARGO_BAY"];
	max_cargo -= max_passengers * 5;
	//
	if ([dict objectForKey:@"credits"])
		credits = [(NSNumber *)[dict objectForKey:@"credits"]		intValue];
	if ([dict objectForKey:@"fuel"])
		fuel = [(NSNumber *)[dict objectForKey:@"fuel"]			intValue];
	//
	if ([dict objectForKey:@"galaxy_number"])
		galaxy_number = [(NSNumber *)[dict objectForKey:@"galaxy_number"]	intValue];
	if ([dict objectForKey:@"forward_weapon"])
		forward_weapon = [(NSNumber *)[dict objectForKey:@"forward_weapon"]   intValue];
	if ([dict objectForKey:@"aft_weapon"])
		aft_weapon = [(NSNumber *)[dict objectForKey:@"aft_weapon"]		intValue];
	if ([dict objectForKey:@"port_weapon"])
		port_weapon = [(NSNumber *)[dict objectForKey:@"port_weapon"]		intValue];
	if ([dict objectForKey:@"starboard_weapon"])
		starboard_weapon = [(NSNumber *)[dict objectForKey:@"starboard_weapon"] intValue];
	//
	if ([dict objectForKey:@"missiles"])
		missiles = [(NSNumber *)[dict objectForKey:@"missiles"] intValue];
	// sanity check the number of missiles...
	if (missiles < 0)
		missiles = 0;
	if (missiles > max_missiles)
		missiles = max_missiles;
	// end sanity check
	if ([dict objectForKey:@"legal_status"])
		legal_status = [(NSNumber *)[dict objectForKey:@"legal_status"] intValue];
	if ([dict objectForKey:@"market_rnd"])
		market_rnd = [(NSNumber *)[dict objectForKey:@"market_rnd"]   intValue];
	if ([dict objectForKey:@"ship_kills"])
		ship_kills = [(NSNumber *)[dict objectForKey:@"ship_kills"]   intValue];
	
	// doubles
	//
	if ([dict objectForKey:@"ship_clock"])
		ship_clock = [(NSNumber*)[dict objectForKey:@"ship_clock"] doubleValue];
	fps_check_time = ship_clock;
	
	// mission_variables
	[mission_variables removeAllObjects];
	if ([dict objectForKey:@"mission_variables"])
		[mission_variables addEntriesFromDictionary:(NSDictionary *)[dict objectForKey:@"mission_variables"]];
	
	// persistant universe info
	if ([dict objectForKey:@"local_planetinfo_overrides"])
	{
		[universe setLocal_planetinfo_overrides:(NSDictionary *)[dict objectForKey:@"local_planetinfo_overrides"]];
	}
	
	// communications log
	if ([dict objectForKey:@"comm_log"])
	{
		if (comm_log)	[comm_log release];
		comm_log = [[NSMutableArray alloc] initWithArray:(NSArray*)[dict objectForKey:@"comm_log"]];	// retained
	}
	
	// set up missiles
	int i;
	[self setActive_missile: 0];
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		if (missile_entity[i])
			[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	if ([dict objectForKey:@"missile_roles"])
	{
		NSArray* missile_roles = (NSArray*)[dict objectForKey:@"missile_roles"];
		if (max_missiles < [missile_roles count])
			missile_roles = [missile_roles subarrayWithRange:NSMakeRange(0, max_missiles)];
//		if (missiles != [missile_roles count])
		if ((missiles) && (missiles != [missile_roles count]))
			missiles = [missile_roles count];	// sanity check the number of missiles
		for (i = 0; (i < max_missiles)&&(i < [missile_roles count]); i++)
		{
			NSString* missile_desc = (NSString*)[missile_roles objectAtIndex:i];
			if (![missile_desc isEqual:@"NONE"])
			{
				ShipEntity* amiss = [universe getShipWithRole:missile_desc];
				if (amiss)
					missile_entity[i] = amiss;   // retain count = 1
				else
				{
					NSLog(@"***** ERROR couldn't find a missile of role '%@' while trying to [PlayerEntity setCommanderDataFromDictionary:] *****", missile_desc);
					// throw an exception here...
					NSException* myException = [NSException
						exceptionWithName: OOLITE_EXCEPTION_FATAL
						reason: [NSString stringWithFormat:@"[PlayerEntity setCommanderDataFromDictionary:] failed to create a missile with role '%@'", missile_desc]
						userInfo:nil];
					[myException raise];
				}
			}
		}
	}
	else
	{
		for (i = 0; i < missiles; i++)
			missile_entity[i] = [universe getShipWithRole:@"EQ_MISSILE"];   // retain count = 1 - should be okay as long as we keep a missile with this role
																			// in the base package.
	}
	while ((missiles > 0)&&(missile_entity[active_missile] == nil))
		[self select_next_missile];
	//
	
	//
	[self set_flags_from_extra_equipment];
	forward_shield = PLAYER_MAX_FORWARD_SHIELD;
	aft_shield = PLAYER_MAX_AFT_SHIELD;
	//
	
	//  things...
	//
	system_seed = [universe findSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	target_system_seed = [universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	//
	
	// trumble information
	[self setUpTrumbles];
	[self setTrumbleValueFrom:[dict objectForKey:@"trumbles"]];	// if it doesn't exist we'll check user-defaults
	
	// finally
	missiles = [self calc_missiles];
}

/////////////////////////////////////////////////////////////

- (id) init
{    
    self = [super init];
	//
	compass_mode = COMPASS_MODE_BASIC;
	//
	//
	afterburnerSoundLooping = NO;
	//
	int i;
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
		missile_entity[i] = nil;
	[self set_up];
	//
	drawDebugParticle = [[ParticleEntity alloc] init];
	[drawDebugParticle setParticleType:PARTICLE_MARKER];
	//
	isPlayer = YES;
	//
	save_path = nil;
	//
	[self setUpSound];
	//
	scoopsActive = NO;
	//
	target_memory_index = 0;
	//
    return self;
}

- (void) set_up
{    
	int i;
	Random_Seed gal_seed = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	//
	showDemoShips = NO;
	//
	show_info_flag = NO;
	
	if (ship_desc)
		[ship_desc release];
	ship_desc = [[NSString stringWithString:PLAYER_SHIP_DESC] retain];
	ship_trade_in_factor = 95;
	//
	NSDictionary *huddict = [ResourceManager dictionaryFromFilesNamed:@"hud.plist" inFolder:@"Config" andMerge:YES];
	if (hud)
		[hud release];
	hud = [[HeadUpDisplay alloc] initWithDictionary:huddict];
	[hud setPlayer:self];
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;
	//
	script = [[ResourceManager dictionaryFromFilesNamed:@"script.plist" inFolder:@"Config" andMerge:YES] retain];
	mission_variables =[[NSMutableDictionary dictionaryWithCapacity:16] retain];
	[self setScript_target:nil];
	[self resetMissionChoice];
	//
	reputation = [[NSMutableDictionary alloc] initWithCapacity:6];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:7] forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:7] forKey:PASSAGE_UNKNOWN_KEY];
	//
	max_passengers = 0;
	if (passengers)
		[passengers release];
	passengers = [[NSMutableArray alloc] initWithCapacity:8];
	if (passenger_record)
		[passenger_record release];
	passenger_record = [[NSMutableDictionary dictionaryWithCapacity:16] retain];
	//
	if (contracts)
		[contracts release];
	contracts = [[NSMutableArray alloc] initWithCapacity:8];
	if (contract_record)
		[contract_record release];
	contract_record = [[NSMutableDictionary dictionaryWithCapacity:16] retain];
	//
	if (shipyard_record)
		[shipyard_record release];
	shipyard_record = [[NSMutableDictionary dictionaryWithCapacity:4] retain];
	//
	if (extra_equipment)
		[extra_equipment release];
	extra_equipment =[[NSMutableDictionary dictionaryWithCapacity:16] retain];
	//
	missionBackgroundImage = nil;
	//
	script_time = 0.0;
	script_time_check = SCRIPT_TIMER_INTERVAL;
	script_time_interval = SCRIPT_TIMER_INTERVAL;
	//
	NSCalendarDate *nowDate = [NSCalendarDate calendarDate];
	ship_clock = PLAYER_SHIP_CLOCK_START;
	ship_clock += [nowDate hourOfDay] * 3600.0;
	ship_clock += [nowDate minuteOfHour] * 60.0;
	ship_clock += [nowDate secondOfMinute];
	fps_check_time = ship_clock;
	ship_clock_adjust = 0.0;
	//
	speech_on = NO;
	ootunes_on = NO;
	//
	mouse_control_on = NO;
	//
	docking_music_on = YES;	// check user defaults for whether we like docking music or not...
	if ([[NSUserDefaults standardUserDefaults] objectForKey:KEY_DOCKING_MUSIC])
		docking_music_on = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_DOCKING_MUSIC];
	//
	if (name)
		[name release];
	name = [[NSString stringWithString:@"Player"] retain];
	rolling = NO;
	pitching = NO;
	galactic_witchjump = NO;
	//
	flight_speed =		0.0;
	max_flight_speed =  160.0;
	max_flight_roll =   2.0;
	max_flight_pitch =  1.0;
	//
	// control factors
	//
	thrust =			32.0;
	roll_delta =		2.0 * max_flight_roll;
	pitch_delta =		2.0 * max_flight_pitch;
    //
    displayListName =   0;
    //
    status =			STATUS_TEST;
	//
	shield_booster =			1;
	shield_enhancer =			0;
	forward_shield =	PLAYER_MAX_FORWARD_SHIELD;
	aft_shield =		PLAYER_MAX_AFT_SHIELD;
	//
	energy =			256;
	weapon_temp =			0.0;
	forward_weapon_temp =	0.0;
	aft_weapon_temp =		0.0;
	port_weapon_temp =		0.0;
	starboard_weapon_temp =	0.0;
	ship_temperature =		60.0;
	heat_insulation = 1.0;
	alert_flags =		0;
	//
	game_over =				NO;
	docked =				NO;
	finished =				NO;
	bomb_detonated =		NO;
	has_docking_computer =  NO;
	autopilot_engaged =		NO;
	afterburner_engaged =   NO;
	hyperspeed_engaged =	NO;
	hyperspeed_locked =		NO;
	//
	ident_engaged = NO;
	//
	ecm_in_operation =		NO;
	ecm_start_time =		0.0;
	//
	fuel_leak_rate =	0.0;
	//
	witchspaceCountdown = 0.0;
	
	collision_radius =  50.0;
	//
	[self setModel:PLAYER_MODEL];
	//
	shot_time =			0.0;
	shot_counter =		0;
    //
	if (shipAI)		[shipAI release];
	shipAI = [[AI alloc] initWithStateMachine:AI_DOCKING_COMPUTER andState:@"GLOBAL"]; // alloc retains dealloc'd by ShipEntity
	[shipAI setOwner:self];
	//
	
	// player commander data
	//
	player_name =			[[NSString alloc] initWithString:@"Jameson"];  // alloc retains
	galaxy_coordinates =	NSMakePoint(0x14,0xAD);	// 20,173
	galaxy_seed =			gal_seed;
	credits =				1000;
	fuel =					PLAYER_MAX_FUEL;
	fuel_accumulator =		0.0;
	
	galaxy_number =			0;
	forward_weapon =		WEAPON_PULSE_LASER;
	aft_weapon =			WEAPON_NONE;
	port_weapon =			WEAPON_NONE;
	starboard_weapon =		WEAPON_NONE;
	
	max_cargo =				20; // will be reset later

	shipCommodityData = [(NSArray *)[(NSDictionary *)[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] objectForKey:@"default"] retain];
	
	has_ecm =					NO;
	has_scoop =					NO;
	has_energy_bomb =			NO;
	has_energy_unit =			NO;
	has_docking_computer =		NO;
	has_galactic_hyperdrive =   NO;
	has_escape_pod =			NO;
	has_fuel_injection =		NO;
	
	shield_booster =			1;
	shield_enhancer =			0;
	
	// set up missiles
	missiles =				PLAYER_STARTING_MISSILES;
	max_missiles =			PLAYER_MAX_MISSILES;
	[self setActive_missile: 0];
	for (i = 0; i < missiles; i++)
	{
		if (missile_entity[i])
			[missile_entity[i] release];
		missile_entity[i] = [universe getShipWithRole:@"EQ_MISSILE"];   // retain count = 1
	}
	[self safe_all_missiles];
	
	legal_status =			0;

	market_rnd =			0;
	ship_kills =			0;
	saved =					NO;
	cursor_coordinates = galaxy_coordinates;
	
	[self init_keys];
	
	scan_class = CLASS_PLAYER;
	
	[universe clearGUIs];
	
	docked_station = [universe station];
	
	if (comm_log)	[comm_log release];
	comm_log = [[NSMutableArray alloc] initWithCapacity:200];	// retained
	//
	
	if (specialCargo)
		[specialCargo release];
	specialCargo = nil;
	
	debugShipID = NO_TARGET;
	
	// views
	//
	forwardViewOffset = make_vector( 0.0f, 0.0f, 0.0f);
	aftViewOffset = make_vector( 0.0f, 0.0f, 0.0f);
	portViewOffset = make_vector( 0.0f, 0.0f, 0.0f);
	starboardViewOffset = make_vector( 0.0f, 0.0f, 0.0f);
	
	if (save_path)
		[save_path autorelease];
	save_path = nil;
	
	[self setUpTrumbles];
	
	suppressTargetLost = NO;

	scoopsActive = NO;
}

- (void) setUpShipFromDictionary:(NSDictionary *) dict
{	
	if (shipinfoDictionary)
		[shipinfoDictionary release];
	shipinfoDictionary = [[NSDictionary alloc] initWithDictionary:dict];	// retained

	//NSLog(@"DEBUG Playerentity - setUpShipFromDictionary:(NSDictionary *) dict");
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
	// set control factors..
	//
	roll_delta =		2.0 * max_flight_roll;
	pitch_delta =		2.0 * max_flight_pitch;
    //

	//
	if ([dict objectForKey:@"thrust"])
	{
		thrust = [(NSNumber *)[dict objectForKey:@"thrust"] doubleValue];
	}
	//
	if ([dict objectForKey:@"max_energy"])
		max_energy = [(NSNumber *)[dict objectForKey:@"max_energy"] doubleValue];
	if ([dict objectForKey:@"energy_recharge_rate"])
		energy_recharge_rate = [(NSNumber *)[dict objectForKey:@"energy_recharge_rate"] doubleValue];
	energy = max_energy;
	//
	if ([dict objectForKey:@"forward_weapon_type"])
	{
		NSString *weapon_type_string = (NSString *)[dict objectForKey:@"forward_weapon_type"];
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
	}
	//
	if ([dict objectForKey:@"missiles"])
		missiles = [(NSNumber *)[dict objectForKey:@"missiles"] intValue];
	if ([dict objectForKey:@"has_ecm"])
		has_ecm = [(NSNumber *)[dict objectForKey:@"has_ecm"] boolValue];
	if ([dict objectForKey:@"has_scoop"])
		has_scoop = [(NSNumber *)[dict objectForKey:@"has_scoop"] boolValue];
	if ([dict objectForKey:@"has_escape_pod"])
		has_escape_pod = [(NSNumber *)[dict objectForKey:@"has_escape_pod"] boolValue];
	//
	if ([dict objectForKey:@"max_cargo"])
		max_cargo = [(NSNumber *)[dict objectForKey:@"max_cargo"] intValue];
	if ([dict objectForKey:@"extra_cargo"])
		extra_cargo = [(NSNumber*)[dict objectForKey:@"extra_cargo"] intValue];
	else
		extra_cargo = 15;
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
	if ([dict objectForKey:@"laser_color"])
	{
		NSString *laser_color_string = (NSString *)[dict objectForKey:@"laser_color"];
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
	if ([dict objectForKey:@"extra_equipment"])
	{
		[extra_equipment removeAllObjects];
		[extra_equipment addEntriesFromDictionary:(NSDictionary *)[dict objectForKey:@"extra_equipment"]];
	}
	//
	if ([dict objectForKey:@"max_missiles"])
	{
//		NSLog(@"DEBUG setting max_missiles %@",[dict objectForKey:@"max_missiles"]);
		max_missiles = [(NSNumber *)[dict objectForKey:@"max_missiles"] intValue];
	}
	//
	if ([dict objectForKey:@"hud"])
	{
		//NSLog(@"DEBUG setting hud %@",[dict objectForKey:@"hud"]);
		NSString *hud_desc = (NSString *)[dict objectForKey:@"hud"];
		NSDictionary *huddict = [ResourceManager dictionaryFromFilesNamed:hud_desc inFolder:@"Config" andMerge:YES];
		if (huddict)
		{
			if (hud)	[hud release];
			hud = [[HeadUpDisplay alloc] initWithDictionary:huddict];
			[hud setPlayer:self];
			[hud setScannerZoom:1.0];
		}
	}
	//
	
	// set up missiles
	int i;
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		if (missile_entity[i])
			[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	for (i = 0; i < missiles; i++)
		missile_entity[i] = [universe getShipWithRole:@"EQ_MISSILE"];   // retain count = 1
	[self setActive_missile: 0];
	//
	
	// set view offsets
	[self setDefaultViewOffsets];
	//
	if ([dict objectForKey:@"view_position_forward"])
		forwardViewOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"view_position_forward"]];
	if ([dict objectForKey:@"view_position_aft"])
		aftViewOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"view_position_aft"]];
	if ([dict objectForKey:@"view_position_port"])
		portViewOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"view_position_port"]];
	if ([dict objectForKey:@"view_position_starboard"])
		starboardViewOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"view_position_starboard"]];

//	NSLog(@"DEBUG in PlayerEntity setUpShipFromDictionary");

	// set weapon offsets
	[self setDefaultWeaponOffsets];
	//
	if ([dict objectForKey:@"weapon_position_forward"])
		forwardWeaponOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"weapon_position_forward"]];
	if ([dict objectForKey:@"weapon_position_aft"])
		aftWeaponOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"weapon_position_aft"]];
	if ([dict objectForKey:@"weapon_position_port"])
		portWeaponOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"weapon_position_port"]];
	if ([dict objectForKey:@"weapon_position_starboard"])
		starboardWeaponOffset = [Entity vectorFromString: (NSString *)[dict objectForKey:@"weapon_position_starboard"]];
	//
	
	// fuel scoop destination position (where cargo gets sucked into)
	tractor_position = make_vector( 0.0f, 0.0f, 0.0f);
	if ([dict objectForKey:@"scoop_position"])
		tractor_position = [Entity vectorFromString: (NSString *)[dict objectForKey:@"scoop_position"]];
	//

	if (sub_entities)
		[sub_entities release];
	sub_entities = nil;

	// exhaust plumes
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
		
	// other subentities
	if ([dict objectForKey:@"subentities"])
	{
		if (universe)
		{
//			NSLog(@"DEBUG adding PlayerEntity subentities");
			int i;
			NSArray *subs = (NSArray *)[dict objectForKey:@"subentities"];
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
							if ([[(ShipEntity*)subent roles] isEqual:@"docking-slit"])
								[subent setStatus:STATUS_EFFECT];			// hack keeps docking slit visible when at reduced detail
							else
								[self addSolidSubentityToCollisionRadius:(ShipEntity*)subent];	// hack - ignore docking-slit for collision radius
						}
						//
					}
					//NSLog(@"DEBUG reference (%.1f,%.1f,%.1f)", ref.x, ref.y, ref.z);
					if (sub_entities == nil)
						sub_entities = [[NSArray arrayWithObject:subent] retain];
					else
					{
						NSMutableArray *temp = [NSMutableArray arrayWithArray:sub_entities];
						[temp addObject:subent];
						[sub_entities release];
						sub_entities = [[NSArray arrayWithArray:temp] retain];
					}
					
					[subent setOwner: self];
					
	//				NSLog(@"DEBUG added subentity %@ to position %.3f,%.3f,%.3f", subent, subent->position.x, subent->position.y, subent->position.z );
													
					[subent release];
				}
			}
//			NSLog(@"DEBUG subentities for player:\n%@\n", sub_entities);
		}
	}
	//
}

- (void) dealloc
{
    if (ship_desc)				[ship_desc release];
	
	if (hud)					[hud release];
	
	if (comm_log)				[comm_log release];

    if (script)					[script release];
    if (mission_variables)		[mission_variables release];
	if (lastTextKey)			[lastTextKey release];
	
    if (extra_equipment)		[extra_equipment release];

	if (reputation)				[reputation release];
	if (passengers)				[passengers release];
	if (passenger_record)		[passenger_record release];
	if (contracts)				[contracts release];
	if (contract_record)		[contract_record release];
	if (shipyard_record)		[shipyard_record release];

    if (missionBackgroundImage) [missionBackgroundImage release];

    if (player_name)			[player_name release];
    if (shipCommodityData)		[shipCommodityData release];

	if (specialCargo)			[specialCargo release];
	
	if (save_path)				[save_path release];
		
	[self destroySound];
	
	int i;
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		if (missile_entity[i])
			[missile_entity[i] release];
	}
	
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
	{
		if (trumble[i])
			[trumble[i] release];
	}

    [super dealloc];
}


- (void) warnAboutHostiles
{
	// make a warningSound
//	NSLog(@"player warned about hostiles!");
#ifdef HAVE_SOUND  
	if (![warningSound isPlaying])
		[warningSound play];
#endif   
}

- (BOOL) canCollide
{
	switch (status)
	{
		case STATUS_IN_FLIGHT :
		case STATUS_AUTOPILOT_ENGAGED :
		case STATUS_WITCHSPACE_COUNTDOWN :
			return YES;
			break;
		
		case STATUS_DEAD :
		case STATUS_ESCAPE_SEQUENCE :
		default :
			return NO;
	}
}

- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;
{
	return NSOrderedDescending;  // always the most near
}

double scoopSoundPlayTime = 0.0;
- (void) update:(double) delta_t
{
	int i;
	// update flags
	//
	has_moved = ((position.x != last_position.x)||(position.y != last_position.y)||(position.z != last_position.z));
	last_position = position;
	has_rotated = ((q_rotation.w != last_q_rotation.w)||(q_rotation.x != last_q_rotation.x)||(q_rotation.y != last_q_rotation.y)||(q_rotation.z != last_q_rotation.z));
	last_q_rotation = q_rotation;
	
	if (scoopsActive)
	{
		scoopSoundPlayTime -= delta_t;
		if (scoopSoundPlayTime < 0.0)
		{
			[fuelScoopSound play];
			scoopSoundPlayTime = 0.5;
		}
		scoopsActive = NO;
	}
	
	// update timers
	//
	shot_time += delta_t;
	script_time += delta_t;
	ship_clock += delta_t;
	if (ship_clock_adjust != 0.0)				// adjust for coming out of warp (add LY * LY hrs)
	{
		double fine_adjust = delta_t * 7200.0;
		if (ship_clock_adjust > 86400)			// more than a day
			fine_adjust = delta_t * 115200.0;	// 16 times faster
		if (ship_clock_adjust > 0)
		{
			if (fine_adjust > ship_clock_adjust)
				fine_adjust = ship_clock_adjust;
			ship_clock += fine_adjust;
			ship_clock_adjust -= fine_adjust;
		}
		else
		{
			if (fine_adjust < ship_clock_adjust)
				fine_adjust = ship_clock_adjust;
			ship_clock -= fine_adjust;
			ship_clock_adjust += fine_adjust;
		}
	}
	
	//fps
	if (ship_clock > fps_check_time)
	{
		fps_counter = floor(1.0 / delta_t);
		fps_check_time = ship_clock + 0.25;
	}
	
	// scripting
	if (script_time > script_time_check)
	{
		if (status == STATUS_IN_FLIGHT)	// check as we're flying
		{
			[self checkScript];
			script_time_check += script_time_interval;
		}
		else	// check at other times
		{
			switch (gui_screen)
			{
				// screens from which it's safe to jump to the mission screen
				case GUI_SCREEN_CONTRACTS:
				case GUI_SCREEN_EQUIP_SHIP:
				case GUI_SCREEN_INVENTORY:
				case GUI_SCREEN_LONG_RANGE_CHART:
				case GUI_SCREEN_MANIFEST:
				case GUI_SCREEN_SHIPYARD:
				case GUI_SCREEN_SHORT_RANGE_CHART:
				case GUI_SCREEN_STATUS:
				case GUI_SCREEN_SYSTEM_DATA:		
					[self checkScript];
					script_time_check += script_time_interval;
					break;
			}
		}
	}
	
	// deal with collisions
	//
	[self manageCollisions];
	[self saveToLastFrame];

	[self pollControls:delta_t];
	
	// update trumbles (moved from end of update: to here)
	OOTrumble** trumbles = [self trumbleArray];
	for (i = [self n_trumbles] ; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
		[trum updateTrumble:delta_t];
	}

	if ((status == STATUS_DEMO)&&(gui_screen != GUI_SCREEN_INTRO1)&&(gui_screen != GUI_SCREEN_INTRO2)&&(gui_screen != GUI_SCREEN_MISSION)&&(gui_screen != GUI_SCREEN_SHIPYARD))
		[self setGuiToIntro1Screen];	//set up demo mode
	
	if ((status == STATUS_AUTOPILOT_ENGAGED)||(status == STATUS_ESCAPE_SEQUENCE))
	{
		[super update:delta_t];
		[self doBookkeeping:delta_t];
		return;
	}
	
	if (!docked_station)
	{
		// do flight routines
		//

		//// velocity stuff
		//
		position.x += delta_t * velocity.x;
		position.y += delta_t * velocity.y;
		position.z += delta_t * velocity.z;
		//
		GLfloat velmag = sqrt(magnitude2(velocity));
		if (velmag)
		{
			GLfloat velmag2 = velmag - delta_t * thrust;
			if (velmag2 < 0.0f)
				velmag2 = 0.0f;
			velocity.x *= velmag2 / velmag;
			velocity.y *= velmag2 / velmag;
			velocity.z *= velmag2 / velmag;
			if ([universe strict])
			{
				if (velmag2 < OG_ELITE_FORWARD_DRIFT)
				{
					velocity.x += delta_t * v_forward.x * OG_ELITE_FORWARD_DRIFT * 20.0;	// add acceleration
					velocity.y += delta_t * v_forward.y * OG_ELITE_FORWARD_DRIFT * 20.0;
					velocity.z += delta_t * v_forward.z * OG_ELITE_FORWARD_DRIFT * 20.0;
				}
			}
		}
		//
		////
		
		[self applyRoll:delta_t*flight_roll andClimb:delta_t*flight_pitch];
		[self moveForward:delta_t*flight_speed];
	}
	
	if (status == STATUS_IN_FLIGHT)
	{
		[self doBookkeeping:delta_t];
	}
	
	if (status == STATUS_LAUNCHING)
	{
		if ([universe breakPatternOver])
		{
			// time to check the script!
			[self checkScript];
			// next check in 10s
			
			status = STATUS_IN_FLIGHT;
		}
	}
	
	if (status == STATUS_WITCHSPACE_COUNTDOWN)
	{
		[self doBookkeeping:delta_t];
		witchspaceCountdown -= delta_t;
		if (witchspaceCountdown < 0.0)  witchspaceCountdown = 0.0;
		if (galactic_witchjump)
			[universe displayCountdownMessage:[NSString stringWithFormat:[universe expandDescription:@"[witch-galactic-in-f-seconds]" forSystem:system_seed], witchspaceCountdown] forCount:1.0];
		else
			[universe displayCountdownMessage:[NSString stringWithFormat:[universe expandDescription:@"[witch-to-@-in-f-seconds]" forSystem:system_seed], [universe getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
		if (witchspaceCountdown == 0.0)
		{
			BOOL go = YES;
			
			// check nearby masses
			ShipEntity* blocker = (ShipEntity*)[universe entityForUniversalID:[self checkShipsInVicinityForWitchJumpExit]];
			if (blocker)
			{
				[universe clearPreviousMessage];
				[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[witch-blocked-by-@]" forSystem:system_seed], [blocker name]] forCount: 4.5];
				if (![universe playCustomSound:@"[witch-blocked-by-@]"])
					[witchAbortSound play];
				status = STATUS_IN_FLIGHT;
				go = NO;
			}
			
			// check fuel level
			double		fuel_required = 10.0 * distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y); 
			if (galactic_witchjump)
				fuel_required = 0.0;
			if (fuel < fuel_required)
			{
				[universe clearPreviousMessage];
				[universe addMessage:[universe expandDescription:@"[witch-no-fuel]" forSystem:system_seed] forCount: 4.5];
				if (![universe playCustomSound:@"[witch-no-fuel]"])
					[witchAbortSound play];
				status = STATUS_IN_FLIGHT;
				go = NO;
			}
			
			if (go)
			{
				[self safe_all_missiles];
				if (galactic_witchjump)
					[self enterGalacticWitchspace];
				else
					[self enterWitchspace];
			}
		}
	}
	
	if (status == STATUS_EXITING_WITCHSPACE)
	{
		if ([universe breakPatternOver])
		{
			// time to check the script!
			[self checkScript];
			// next check in 10s
			[self resetScriptTimer];	// reset the in-system timer
			
			// announce arrival
			if ([universe planet])
				[universe addMessage:[NSString stringWithFormat:@" %@. ",[universe getSystemName:system_seed]] forCount:3.0];
			else
				[universe addMessage:[universe expandDescription:@"[witch-engine-malfunction]" forSystem:system_seed] forCount:3.0];
			
			status = STATUS_IN_FLIGHT;
		}
	}
	
	if (status == STATUS_DOCKING)
	{
		if ([universe breakPatternOver])
		{
			[self docked];		// bookkeeping for docking
		}
	}
	
	if ((status == STATUS_DEAD)&&(shot_time > 30.0))
	{
		BOOL was_mouse_control_on = mouse_control_on;
		[universe game_over];				//  we restart the universe
		mouse_control_on = was_mouse_control_on;
	}
	
	//
	// check for lost ident target and ensure the ident system is actually scanning
	//
	if (ident_engaged)
	{
		if (missile_status == MISSILE_STATUS_TARGET_LOCKED)
		{
			Entity*	e = [universe entityForUniversalID:primaryTarget];
			if ((e == nil)||(e->zero_distance > SCANNER_MAX_RANGE2)||
				(e->scan_class == CLASS_NO_DRAW)||						// checking scanClass checks for cloaked ships
				((e->isShip)&&(!has_military_scanner_filter)&&([(ShipEntity*)e isJammingScanning])))	// checks for activated jammer
			{
				if (!suppressTargetLost)
				{
					[universe addMessage:[universe expandDescription:@"[target-lost]" forSystem:system_seed] forCount:3.0];
					[self boop];
				}
				else
				{
					suppressTargetLost = NO;
				}
				primaryTarget = NO_TARGET;
				missile_status = MISSILE_STATUS_SAFE;
			}
		}
		else
		{
			missile_status = MISSILE_STATUS_ARMED;
		}
	}
	
	//
	// check each unlaunched missile's target still exists and is in-range
	//
	for (i = 0; i < max_missiles; i++)
	{
		if ((missile_entity[i])&&([missile_entity[i] getPrimaryTargetID] != NO_TARGET))
		{
			ShipEntity*	target_ship = (ShipEntity *)[missile_entity[i] getPrimaryTarget];
			if ((!target_ship)||(target_ship->zero_distance > SCANNER_MAX_RANGE2))
			{
				[universe addMessage:[universe expandDescription:@"[target-lost]" forSystem:system_seed] forCount:3.0];
				[self boop];
				[missile_entity[i] removeTarget:nil];
				if ((i == active_missile)&&(!ident_engaged))
				{
					primaryTarget = NO_TARGET;
					missile_status = MISSILE_STATUS_SAFE;
				}
			}
		}
	}
	
	if ((missile_status == MISSILE_STATUS_ARMED)&&(ident_engaged||[[missile_entity[active_missile] roles] hasSuffix:@"MISSILE"])&&((status == STATUS_IN_FLIGHT)||(status == STATUS_WITCHSPACE_COUNTDOWN)))
	{
		int first_target_id = [universe getFirstEntityTargettedByPlayer:self];
		if (first_target_id != NO_TARGET)
		{
			Entity *first_target = [universe entityForUniversalID:first_target_id];
			if ([first_target isKindOfClass:[ShipEntity class]])
			{
				[self addTarget: first_target];
				missile_status = MISSILE_STATUS_TARGET_LOCKED;
				if ((missile_entity[active_missile])&&(!ident_engaged))
					[missile_entity[active_missile] addTarget:first_target];
				[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-locked-onto-@]" forSystem:system_seed], (ident_engaged)? @"Ident system": @"Missile", [(ShipEntity *)first_target name]] forCount:4.5];
				[self beep];
			}
		}
	}
}

- (void) doBookkeeping:(double) delta_t
{
	// Bookeeping;
	//
	double speed_delta = 5.0 * thrust;
	//
	PlanetEntity*	sun = [universe sun];
	double	external_temp = 0;
	GLfloat	air_friction = 0.0;
	if (universe)
		air_friction = 0.5 * universe->air_resist_factor;
		
	// cool all weapons
	//
	if (forward_weapon_temp > 0.0)
	{
		forward_weapon_temp -= WEAPON_COOLING_FACTOR * delta_t;
		if (forward_weapon_temp < 0.0)
			forward_weapon_temp = 0.0;
	}
	if (aft_weapon_temp > 0.0)
	{
		aft_weapon_temp -= WEAPON_COOLING_FACTOR * delta_t;
		if (aft_weapon_temp < 0.0)
			aft_weapon_temp = 0.0;
	}
	if (port_weapon_temp > 0.0)
	{
		port_weapon_temp -= WEAPON_COOLING_FACTOR * delta_t;
		if (port_weapon_temp < 0.0)
			port_weapon_temp = 0.0;
	}
	if (starboard_weapon_temp > 0.0)
	{
		starboard_weapon_temp -= WEAPON_COOLING_FACTOR * delta_t;
		if (starboard_weapon_temp < 0.0)
			starboard_weapon_temp = 0.0;
	}
	// copy new temp to main temp
	//
	switch ([universe viewDir])
	{
		case VIEW_DOCKED:
		case VIEW_NONE:
		case VIEW_BREAK_PATTERN:
		case VIEW_FORWARD:
			weapon_temp = forward_weapon_temp;
			break;
		case VIEW_AFT:
			weapon_temp = aft_weapon_temp;
			break;
		case VIEW_PORT:
			weapon_temp = port_weapon_temp;
			break;
		case VIEW_STARBOARD:
			weapon_temp = starboard_weapon_temp;
			break;
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
					energy = max_energy;
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

	if (energy < max_energy)
	{
		double energy_multiplier = 1.0 + 0.1 * energy_unit; // 1.5x recharge with normal energy unit, 2x with naval!
		energy += energy_recharge_rate * energy_multiplier * delta_t;
		if (energy > max_energy)
			energy = max_energy;
	}
	if (forward_shield < PLAYER_MAX_FORWARD_SHIELD)
	{
		forward_shield += SHIELD_RECHARGE_FACTOR * delta_t;
		energy -= SHIELD_RECHARGE_FACTOR * delta_t;
		if (forward_shield > PLAYER_MAX_FORWARD_SHIELD)
		{
			energy += forward_shield - PLAYER_MAX_FORWARD_SHIELD;
			forward_shield = PLAYER_MAX_FORWARD_SHIELD;
		}
	}
	if (aft_shield < PLAYER_MAX_AFT_SHIELD)
	{
		aft_shield += SHIELD_RECHARGE_FACTOR * delta_t;
		energy -= SHIELD_RECHARGE_FACTOR * delta_t;
		if (aft_shield > PLAYER_MAX_FORWARD_SHIELD)
		{
			energy += aft_shield - PLAYER_MAX_AFT_SHIELD;
			aft_shield = PLAYER_MAX_AFT_SHIELD;
		}
	}
	if (forward_shield > PLAYER_MAX_FORWARD_SHIELD)
		forward_shield = PLAYER_MAX_FORWARD_SHIELD;
	if (aft_shield > PLAYER_MAX_FORWARD_SHIELD)
		aft_shield = PLAYER_MAX_AFT_SHIELD;
	if (ecm_in_operation)
	{
		if (energy > 0.0)
			energy -= ECM_ENERGY_DRAIN_FACTOR * delta_t;		// drain energy because of the ECM
		else
		{
			ecm_in_operation = NO;
			[self stopECMSound];
			//[universe displayMessage:@"ECM system deactivated (no energy left)." forCount:3.0];
			[universe addMessage:[universe expandDescription:@"[ecm-out-of-juice]" forSystem:system_seed] forCount:3.0];
		}
		if ([universe getTime] > ecm_start_time + ECM_DURATION)
		{
			ecm_in_operation = NO;
		}
	}
	
	if (sun)
	{
		// set the ambient temperature here
		double  sun_zd = sun->zero_distance;	// square of distance
		double  sun_cr = sun->collision_radius;
		double	alt1 = sun_cr * sun_cr / sun_zd;
		external_temp = SUN_TEMPERATURE * alt1;
		if ([[universe sun] goneNova])
			external_temp *= 100;

		// do Revised sun-skimming check here...
		if ((has_scoop)&&(alt1 > 0.75)&&(fuel < 70))
		{
			fuel_accumulator += delta_t * flight_speed * 0.010;
			scoopsActive = YES;
			while (fuel_accumulator > 1.0)
			{
				fuel ++;
				fuel_accumulator -= 1.0;
			}
			if (fuel > 70)	fuel = 70;
			[universe displayCountdownMessage:[universe expandDescription:@"[fuel-scoop-active]" forSystem:system_seed] forCount:1.0];
		}
	}
	
	if ((status != STATUS_AUTOPILOT_ENGAGED)&&(status != STATUS_ESCAPE_SEQUENCE))
	{
		// work on the cabin temperature
		//
		ship_temperature += delta_t * flight_speed * air_friction / heat_insulation;	// wind_speed
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
	}

	if ((status == STATUS_ESCAPE_SEQUENCE)&&(shot_time > ESCAPE_SEQUENCE_TIME))
	{
		[(ShipEntity *)[universe entityForUniversalID:found_target] becomeExplosion];	// blow up the doppelganger
		[self setTargetToStation];
		if ([self getPrimaryTarget])
		{
			// restore player ship
			ShipEntity *player_ship = [universe getShip: ship_desc];	// retained
			if (player_ship)
			{
				[self setModel:[player_ship getModel]];
				[player_ship release];						// we only wanted it for its polygons!
			}
			[universe setViewDirection:VIEW_FORWARD];
			[self enterDock:(StationEntity *)[self getPrimaryTarget]];
		}
	}
	////
	//
	// MOVED THE FOLLOWING FROM PLAYERENTITY POLLFLIGHTCONTROLS:
	travelling_at_hyperspeed = (flight_speed > max_flight_speed);
	if (hyperspeed_engaged)
	{
		// increase speed up to maximum hyperspeed
		if (flight_speed < max_flight_speed * HYPERSPEED_FACTOR)
			flight_speed += speed_delta * delta_t * HYPERSPEED_FACTOR;
		if (flight_speed > max_flight_speed * HYPERSPEED_FACTOR)
			flight_speed = max_flight_speed * HYPERSPEED_FACTOR;

		// check for mass lock
		hyperspeed_locked = [self massLocked];
		
			if (hyperspeed_locked)
		{
			[self boop];
			[universe addMessage:[universe expandDescription:@"[jump-mass-locked]" forSystem:system_seed] forCount:4.5];
			hyperspeed_engaged = NO;
		}
	}
	else
	{
		if (afterburner_engaged)
		{
			if (flight_speed < max_flight_speed * AFTERBURNER_FACTOR)
				flight_speed += speed_delta * delta_t * AFTERBURNER_FACTOR;
			if (flight_speed > max_flight_speed * AFTERBURNER_FACTOR)
				flight_speed = max_flight_speed * AFTERBURNER_FACTOR;
			fuel_accumulator -= delta_t * AFTERBURNER_BURNRATE;
			while ((fuel_accumulator < 0)&&(fuel > 0))
			{
				fuel_accumulator += 1.0;
				fuel --;
				if (fuel <= 0)
					afterburner_engaged = NO;
			}
		}
		else
		{
			// slow back down...
			if (travelling_at_hyperspeed)
			{
				// decrease speed to maximum normal speed
				flight_speed -= speed_delta * delta_t * HYPERSPEED_FACTOR;
				if (flight_speed < max_flight_speed)
					flight_speed = max_flight_speed;
			}
		}
	}
	//
	////
	
	// fuel leakage
	//
	if ((fuel_leak_rate > 0.0)&&(fuel > 0))
	{
		fuel_accumulator -= fuel_leak_rate * delta_t;
		while ((fuel_accumulator < 0)&&(fuel > 0))
		{
			fuel_accumulator += 1.0;
			fuel--;
		}
		if (fuel == 0)
			fuel_leak_rate = 0;
	}
	
	// smart_zoom
	if (scanner_zoom_rate)
	{
		double z = [hud scanner_zoom];
		double z1 = z + scanner_zoom_rate * delta_t;
		if (scanner_zoom_rate > 0.0)
		{
			if (floor(z1) > floor(z))
			{
				z1 = floor(z1);
				scanner_zoom_rate = 0.0;
			}
		}
		else
		{
			if (z1 < 1.0)
			{
				z1 = 1.0;
				scanner_zoom_rate = 0.0;
			}
		}
		[hud setScannerZoom:z1];
	}
	
	// update subentities
	if (sub_entities)
	{
		int i;
		for (i = 0; i < [sub_entities count]; i++)
			[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
	}
}

- (void) applyRoll:(GLfloat) roll1 andClimb:(GLfloat) climb1
{	
	if ((roll1 == 0.0)&&(climb1 == 0.0)&&(!has_rotated))
		return;
	
	if (roll1)
		quaternion_rotate_about_z( &q_rotation, -roll1);
	if (climb1)
		quaternion_rotate_about_x( &q_rotation, -climb1);
	
    quaternion_normalise(&q_rotation);	// probably not strictly necessary but good to do to keep q_rotation sane
    quaternion_into_gl_matrix(q_rotation, rotMatrix);

	v_right.x = rotMatrix[0];
	v_right.y = rotMatrix[4];
	v_right.z = rotMatrix[8];

	v_up.x = rotMatrix[1];
	v_up.y = rotMatrix[5];
	v_up.z = rotMatrix[9];

	v_forward.x = rotMatrix[2];
	v_forward.y = rotMatrix[6];
	v_forward.z = rotMatrix[10];
	
	q_rotation.w = -q_rotation.w;
	quaternion_into_gl_matrix(q_rotation, playerRotMatrix);	// this is the rotation similar to ordinary ships
	q_rotation.w = -q_rotation.w;
}

- (GLfloat *) drawRotationMatrix	// override to provide the 'correct' drawing matrix
{
    return playerRotMatrix;
}

- (void) moveForward:(double) amount
{
	distance_travelled += amount;
	position.x += amount * v_forward.x;
	position.y += amount * v_forward.y;
	position.z += amount * v_forward.z;
}

// originally:
// return a point 36u back from the front of the ship
// this equates with the centre point of a cobra mk3
//
// now:
// return the viewpoint set by the relevant view Offset
//
- (Vector) getViewpointPosition
{
	Vector	viewpoint = position;
	if ([universe breakPatternHide])
		return viewpoint;	// center view for break pattern
	
	Vector offset = make_vector ( 0, 0, 0);
	switch ([universe viewDir])
	{
		case VIEW_FORWARD:
			offset = forwardViewOffset;	break;
		case VIEW_AFT:
			offset = aftViewOffset;	break;
		case VIEW_PORT:
			offset = portViewOffset;	break;
		case VIEW_STARBOARD:
			offset = starboardViewOffset;	break;
	}
	if (offset.x)
	{
		viewpoint.x += offset.x * v_right.x;	viewpoint.y += offset.x * v_right.y;	viewpoint.z += offset.x * v_right.z;
	}
	if (offset.y)
	{
		viewpoint.x += offset.y * v_up.x;		viewpoint.y += offset.y * v_up.y;		viewpoint.z += offset.y * v_up.z;
	}
	if (offset.z)
	{
		viewpoint.x += offset.z * v_forward.x;	viewpoint.y += offset.z * v_forward.y;	viewpoint.z += offset.z * v_forward.z;
	}
	
	return viewpoint;
}

- (Vector) getViewpointOffset
{
	if ([universe breakPatternHide])
		return make_vector( 0.0f, 0.0f, 0.0f);	// center view for break pattern
	
	switch ([universe viewDir])
	{
		case VIEW_FORWARD:
			return forwardViewOffset;
		case VIEW_AFT:
			return aftViewOffset;
		case VIEW_PORT:
			return portViewOffset;
		case VIEW_STARBOARD:
			return starboardViewOffset;
	}
	
	return make_vector( 0.0f, 0.0f, 0.0f);
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if ((status == STATUS_DEAD)||(status == STATUS_DEMO)||(status == STATUS_DOCKED)||[universe breakPatternHide])
		return;	// don't draw
	
	[super drawEntity: immediate : translucent];

	checkGLErrors([NSString stringWithFormat:@"after drawing PlayerEntity %@", self]);
}

- (BOOL) massLocked
{
	return ((alert_flags & ALERT_FLAG_MASS_LOCK) != 0);
}

- (BOOL) atHyperspeed
{
	return travelling_at_hyperspeed;
}

- (Vector) velocityVector
{
	Vector result = v_forward;
	result.x *= flight_speed;
	result.y *= flight_speed;
	result.z *= flight_speed;
	return result;
}

//
//			dial routines = all return 0.0 .. 1.0 or -1.0 .. 1.0
//
- (NSString *) ship_desc
{
	return ship_desc;
}

- (StationEntity *) docked_station
{
	return docked_station;
}

- (HeadUpDisplay *) hud
{
	return hud;
}

- (void) setShowDemoShips:(BOOL) value
{
	showDemoShips = value;
}

- (BOOL) showDemoShips
{
	return showDemoShips || (status == STATUS_DEMO);
}

- (double) dial_roll
{
	return flight_roll / max_flight_roll;
}
- (double) dial_pitch
{
	return flight_pitch / max_flight_pitch;
}
- (double) dial_speed
{
	if (flight_speed < max_flight_speed)
		return flight_speed/max_flight_speed;
	else
		return 1.0;
}
- (double) dial_hyper_speed
{
	return flight_speed/max_flight_speed;
}

- (double) dial_forward_shield
{
	return forward_shield / PLAYER_MAX_FORWARD_SHIELD;
}
- (double) dial_aft_shield
{
	return aft_shield / PLAYER_MAX_AFT_SHIELD;
}

- (double) dial_energy
{
	return energy / max_energy;
}

- (double) dial_max_energy
{
	return max_energy;
}

- (double) dial_fuel
{
	return fuel / PLAYER_MAX_FUEL;
}
- (double) dial_hyper_range
{
	double distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
	return 10.0 * distance / PLAYER_MAX_FUEL;
}
- (double) dial_ship_temperature
{
	return ship_temperature / SHIP_MAX_CABIN_TEMP;
}
- (double) dial_weapon_temp
{
	return weapon_temp / PLAYER_MAX_WEAPON_TEMP;
}
- (double) dial_altitude
{
	// find nearest planet type entity...
	if (!universe)
		return 1.0;
	
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	PlanetEntity* nearest_planet = nil;
	int i;
	for (i = 0; ((i < ent_count)&&(!nearest_planet)); i++)
		if (uni_entities[i]->isPlanet)
			nearest_planet = [uni_entities[i] retain];		//	retained
	
	if (!nearest_planet)
		return 1.0;

	double  zd = nearest_planet->zero_distance;
	double  cr = nearest_planet->collision_radius;
	double alt = sqrt(zd) - cr;
	
	[nearest_planet release];
	
//	PlanetEntity	*planet =   [universe planet];
//	PlanetEntity	*sun =		[universe sun];
//	double  planet_zd = (planet)? planet->zero_distance : PLAYER_SUPER_ALTITUDE2;
//	double  sun_zd = (sun)? sun->zero_distance : PLAYER_SUPER_ALTITUDE2;
//	double  planet_cr = (planet)? planet->collision_radius : 0;
//	double  sun_cr = (sun)? sun->collision_radius : 0;
//	double alt = (planet_zd < sun_zd) ? (sqrt(planet_zd) - planet_cr) : (sqrt(sun_zd) - sun_cr);
	
	alt /= PLAYER_DIAL_MAX_ALTITUDE;
		
	if (alt > 1.0)
		alt = 1.0;
	if (alt < 0.0)
		alt = 0.0;
	
	return alt;
}

- (NSString*) dial_clock
{
	int days = floor(ship_clock / 86400.0); // days
	int secs = floor(ship_clock - days * 86400.0);
	int hrs = floor(secs / 3600.0); // hrs
	secs %= 3600;
	int mins = floor(secs / 60.0);	// mins
	secs %= 60;
	if (ship_clock_adjust == 0.0)
		return [NSString stringWithFormat:@"%07d:%02d:%02d:%02d", days, hrs, mins, secs];
	else
		return [NSString stringWithFormat:@"%07d:%02d:%02d:%02d (adjusting)", days, hrs, mins, secs];
}

- (NSString*) dial_clock_adjusted
{
	double ship_time = ship_clock + ship_clock_adjust;
	int days = floor(ship_time / 86400.0); // days
	int secs = floor(ship_time - days * 86400.0);
	int hrs = floor(secs / 3600.0); // hrs
	secs %= 3600;
	int mins = floor(secs / 60.0);	// mins
	secs %= 60;
	return [NSString stringWithFormat:@"%07d:%02d:%02d:%02d", days, hrs, mins, secs];
}

- (NSString*) dial_fpsinfo
{
	return [NSString stringWithFormat:@"FPS: %3d", fps_counter];
}

- (NSString*) dial_objinfo
{
	return [NSString stringWithFormat:@"Objs: %3d", [universe obj_count]];
}

- (int) dial_missiles
{
	return missiles;
}

- (int) calc_missiles
{
	int n_missiles = 0;
	int i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i])
			n_missiles++;
	}
	return n_missiles;
}

- (int) dial_missile_status
{
	return missile_status;
}

- (int) dial_fuelscoops_status
{
	if (has_scoop)
	{
		if (scoopsActive)
			return SCOOP_STATUS_ACTIVE;
		if ([cargo count] >= max_cargo)
			return SCOOP_STATUS_FULL_HOLD;
		return SCOOP_STATUS_OKAY;
	}
	else
		return SCOOP_STATUS_NOT_INSTALLED;
}

- (NSMutableArray*) comm_log
{
	return comm_log;
}

- (int) compass_mode
{
	return compass_mode;
}

- (void) setCompass_mode:(int) value
{
	compass_mode = value;
}

- (void) setNextCompassMode
{
	if COMPASS_MODE_ADVANCED_OKAY
	{
		switch (compass_mode)
		{
			case COMPASS_MODE_PLANET:
				if ([self checkForAegis] == AEGIS_NONE)
					[self setCompass_mode:COMPASS_MODE_SUN];
				else
					[self setCompass_mode:COMPASS_MODE_STATION];
				break;
			case COMPASS_MODE_STATION:
				[self setCompass_mode:COMPASS_MODE_SUN];
				break;
			case COMPASS_MODE_SUN:
				if ([self getPrimaryTarget])
					[self setCompass_mode:COMPASS_MODE_TARGET];
				else
				{
					nextBeaconID = [[universe firstBeacon] universal_id];
					while ((nextBeaconID != NO_TARGET)&&[(ShipEntity*)[universe entityForUniversalID:nextBeaconID] isJammingScanning])
					{
						nextBeaconID = [(ShipEntity*)[universe entityForUniversalID:nextBeaconID] nextBeaconID];
					}
					//
					if (nextBeaconID != NO_TARGET)
						[self setCompass_mode:COMPASS_MODE_BEACONS];
					else
						[self setCompass_mode:COMPASS_MODE_PLANET];
				}
				break;
			case COMPASS_MODE_TARGET:
				nextBeaconID = [[universe firstBeacon] universal_id];
				while ((nextBeaconID != NO_TARGET)&&[(ShipEntity*)[universe entityForUniversalID:nextBeaconID] isJammingScanning])
				{
					nextBeaconID = [(ShipEntity*)[universe entityForUniversalID:nextBeaconID] nextBeaconID];
				}
				//
				if (nextBeaconID != NO_TARGET)
					[self setCompass_mode:COMPASS_MODE_BEACONS];
				else
					[self setCompass_mode:COMPASS_MODE_PLANET];
				break;
			case COMPASS_MODE_BEACONS:
				do
				{
					nextBeaconID = [(ShipEntity*)[universe entityForUniversalID:nextBeaconID] nextBeaconID];
				} while ((nextBeaconID != NO_TARGET)&&[(ShipEntity*)[universe entityForUniversalID:nextBeaconID] isJammingScanning]);
				//
				if (nextBeaconID == NO_TARGET)
					[self setCompass_mode:COMPASS_MODE_PLANET];
				break;
		}
	}
}

- (int) active_missile
{
	return active_missile;
}

- (void) setActive_missile: (int) value
{
	active_missile = value;
}

- (int) dial_max_missiles
{
	return max_missiles;
}

- (BOOL) dial_ident_engaged
{
	return ident_engaged;
}

- (NSString *) dial_target_name
{
	Entity* target_entity = [universe entityForUniversalID:primaryTarget];
	if ((target_entity)&&(target_entity->isShip))
		return [(ShipEntity*)target_entity identFromShip:self];
	else
		return @"No target";
}

- (ShipEntity *) missile_for_station: (int) value
{
	if ((value < 0)||(value >= max_missiles))
		return nil;
	return missile_entity[value];
}

- (void) sort_missiles
{
	//
	//	puts all missiles into the first available slots
	//
	int i;
	missiles = [self calc_missiles];
	for (i = 0; i < missiles; i++)
	{
		if (missile_entity[i] == nil)
		{
			int j;
			for (j = i + 1; j < max_missiles; j++)
			{
				if (missile_entity[j])
				{
					missile_entity[i] = missile_entity[j];
					missile_entity[j] = nil;
					j = max_missiles;
				}
			}
		}
	}
}

- (void) safe_all_missiles
{
	//
	//	sets all missile targets to NO_TARGET
	//
	int i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i])
			[missile_entity[i] removeTarget:nil];
	}
	missile_status = MISSILE_STATUS_SAFE;
}

- (void) tidyMissilePylons
{
	// Shuffle missiles up so there's:
	// no gaps between missiles
	// the first missile is in the first pylon
	int i;
	int pylon=0;
	for(i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		if(missile_entity[i])
			{
			missile_entity[pylon]=missile_entity[i];
			pylon++;
			}
	}

	// missiles have been shoved up, now make sure the remainder
	// of the pylons are cleaned up.
	for(i = pylon; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		missile_entity[i]=nil;
	}
}

- (void) select_next_missile
{
	int i;
	for (i = 1; i < max_missiles; i++)
	{
		int next_missile = (active_missile + i) % max_missiles;
		if (missile_entity[next_missile])
		{
			// if this is a missile then select it
//			if ([[missile_entity[next_missile] roles] isEqual:@"EQ_MISSILE"])
			if (missile_entity[next_missile])	// if it exists
			{
				[self setActive_missile:next_missile];
				if (([[missile_entity[next_missile] roles] hasSuffix:@"MISSILE"])&&([missile_entity[next_missile] getPrimaryTarget] != nil))
				{
					// copy the missile's target
					[self addTarget:[missile_entity[next_missile] getPrimaryTarget]];
					missile_status = MISSILE_STATUS_TARGET_LOCKED;
				}
				else
					missile_status = MISSILE_STATUS_SAFE;
				return;
			}
		}
	}
}


- (void) clearAlert_flags
{
	alert_flags = 0;
}

- (void) setAlert_flag:(int) flag :(BOOL) value
{
	if (value)
	{
		alert_flags |= flag;
	}
	else
	{
		int comp = ~flag;
		alert_flags &= comp;
	}
}

- (int) alert_condition
{	
	int old_alert_condition = alert_condition;
	alert_condition = ALERT_CONDITION_GREEN;
	[self setAlert_flag:ALERT_FLAG_DOCKED :(status == STATUS_DOCKED)];
	if (alert_flags & ALERT_FLAG_DOCKED)
	{
		alert_condition = ALERT_CONDITION_DOCKED;
	}
	else
	{
		if (alert_flags != 0)
			alert_condition = ALERT_CONDITION_YELLOW;
		if (alert_flags > ALERT_FLAG_YELLOW_LIMIT)
			alert_condition = ALERT_CONDITION_RED;
	}
	if ((alert_condition == ALERT_CONDITION_RED)&&(old_alert_condition < ALERT_CONDITION_RED))
	{
		// give an audible warning
//		NSLog(@"WARNING! %d %x", alert_condition, alert_flags);
#ifdef HAVE_SOUND
		if ([warningSound isPlaying])
			[warningSound stop];
		[warningSound play];
#endif      
	}
	
	return alert_condition;
}

/////////////////////////////////////////////////////////////////////////


- (void) interpretAIMessage:(NSString *)ms
{
	if ([ms isEqual:@"HOLD_FULL"])
	{
		[self beep];
		[universe addMessage:[universe expandDescription:@"[hold-full]" forSystem:system_seed] forCount:4.5];
	}
	
	if ([ms isEqual:@"INCOMING_MISSILE"])
	{
#ifdef HAVE_SOUND     
		if (![universe playCustomSound:@"[incoming-missile]"])
			[warningSound play];
#endif      
		[universe addMessage:[universe expandDescription:@"[incoming-missile]" forSystem:system_seed] forCount:4.5];
	}
	
	if ([ms isEqual:@"ENERGY_LOW"])
	{
		[universe playCustomSound:@"[energy-low]"];
		[universe addMessage:[universe expandDescription:@"[energy-low]" forSystem:system_seed] forCount:6.0];
	}
	
	if ([ms isEqual:@"ECM"])
		[self playECMSound];
	
	if ([ms isEqual:@"DOCKING_REFUSED"]&&(status == STATUS_AUTOPILOT_ENGAGED))
	{
#ifdef HAVE_SOUND     
		if (![universe playCustomSound:@"[autopilot-denied]"])
			[warningSound play];
#endif      
		[universe addMessage:[universe expandDescription:@"[autopilot-denied]" forSystem:system_seed] forCount:4.5];
		autopilot_engaged = NO;
		primaryTarget = NO_TARGET;
		status = STATUS_IN_FLIGHT;
		if (ootunes_on)
		{
			// ootunes - play inflight music
			[[universe gameController] playiTunesPlaylist:@"Oolite-Inflight"];
			docking_music_on = NO;
		}
	}
	
	// aegis messages to advanced compass so in planet mode it behaves like the old compass
	if (compass_mode != COMPASS_MODE_BASIC)
	{
		if ([ms isEqual:@"AEGIS_CLOSE_TO_PLANET"]&&(compass_mode == COMPASS_MODE_PLANET))
		{
			[universe playCustomSound:@"[aegis-planet]"];
			[self setCompass_mode:COMPASS_MODE_STATION];
		}
		if ([ms isEqual:@"AEGIS_IN_DOCKING_RANGE"]&&(compass_mode == COMPASS_MODE_PLANET))
		{
			[universe playCustomSound:@"[aegis-station]"];
			[self setCompass_mode:COMPASS_MODE_STATION];
		}
		if ([ms isEqual:@"AEGIS_NONE"]&&(compass_mode == COMPASS_MODE_STATION))
		{
			[self setCompass_mode:COMPASS_MODE_PLANET];
		}
	}
}

- (BOOL) mountMissile: (ShipEntity *)missile
{
	if (!missile)
		return NO;
	int i;	
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i] == nil)
		{
			missile_entity[i] = [missile retain];
			return YES;
		}
	}
	missiles = [self calc_missiles];
	return NO;
}

- (BOOL) fireMissile
{
	ShipEntity *missile = missile_entity[active_missile];	// retain count is 1
	
	if (missile == nil)
		return NO;
	
	double mcr = missile->collision_radius;
	
	if ([[missile roles] hasSuffix:@"MINE"]&&((missile_status == MISSILE_STATUS_ARMED)||(missile_status == MISSILE_STATUS_TARGET_LOCKED)))
	{
		BOOL launchedOK = [self launchMine:missile];
		if (launchedOK)
		{
			[universe playCustomSound:@"[mine-launched]"];
			[missile release];	//  release
		}
		missile_entity[active_missile] = nil;
		[self select_next_missile];
		missiles = [self calc_missiles];
		return launchedOK;
	}
		
	if ((missile_status != MISSILE_STATUS_TARGET_LOCKED)||(ident_engaged))
		return NO;
		
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
	q1.w = -q1.w;   // player view is reversed remember!
	
	Entity  *target = [self getPrimaryTarget];
	
	// select a new active missile and decrease the missiles count
	missile_entity[active_missile] = nil;
	[self select_next_missile];
	missiles = [self calc_missiles];
	

	v_eject = unit_vector( &start);
	
	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - mcr)&&(start.x < boundingBox.max.x + mcr)&&
			(start.y > boundingBox.min.y - mcr)&&(start.y < boundingBox.max.y + mcr)&&
			(start.z > boundingBox.min.z - mcr)&&(start.z < boundingBox.max.z + mcr))
	{
		start.x += mcr * v_eject.x;	start.y += mcr * v_eject.y;	start.z += mcr * v_eject.z;
	}
			
	vel.x = (flight_speed + throw_speed) * v_forward.x;
	vel.y = (flight_speed + throw_speed) * v_forward.y;
	vel.z = (flight_speed + throw_speed) * v_forward.z;
	
	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;
	
	[missile setPosition:origin];
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
	
	[universe playCustomSound:@"[missile-launched]"];
	
	return YES;
}

- (BOOL) launchMine:(ShipEntity*) mine
{
	if (!mine)
		return NO;
	double  mine_speed = 500.0;
	[self dumpItem: mine];
	Vector mvel = [mine getVelocity];
	mvel.x -= mine_speed * v_forward.x;
	mvel.y -= mine_speed * v_forward.y;
	mvel.z -= mine_speed * v_forward.z;
	[mine setVelocity: mvel];
	[mine setScanClass: CLASS_MINE];
	[mine setStatus: STATUS_IN_FLIGHT];
	[mine setBehaviour: BEHAVIOUR_IDLE];
	[mine setOwner: self];
	[[mine getAI] setState:@"GLOBAL"];	// start the timer !!!!
	return YES;
}

- (BOOL) fireECM
{
	if ([super fireECM])
	{
		ecm_in_operation = YES;
		ecm_start_time = [universe getTime];
		return YES;
	}
	else
		return NO;
}

- (BOOL) fireEnergyBomb
{
	NSArray* targets = [universe getEntitiesWithinRange:SCANNER_MAX_RANGE ofEntity:self];
	if ([targets count] > 0)
	{
		int i;
		for (i = 0; i < [targets count]; i++)
		{
			Entity *e2 = [targets objectAtIndex:i];
			if (e2->isShip)
				[(ShipEntity *)e2 takeEnergyDamage:1000 from:self becauseOf:self];
		}
	}
	[universe addMessage:[universe expandDescription:@"[energy-bomb-activated]" forSystem:system_seed] forCount:4.5];
#ifdef HAVE_SOUND   
	[destructionSound play];
#endif   
	return YES;
}



- (BOOL) fireMainWeapon
{
	int weapon_to_be_fired = [self weaponForView:[universe viewDir]];
	
	if (weapon_temp / PLAYER_MAX_WEAPON_TEMP >= 0.85)
	{
		[universe playCustomSound:@"[weapon-overheat]"];
		[universe addMessage:[universe expandDescription:@"[weapon-overheat]" forSystem:system_seed] forCount:3.0];
		return NO;
	}
	
	if (weapon_to_be_fired == WEAPON_NONE)
		return NO;
	
	switch (weapon_to_be_fired)
	{
		case WEAPON_PLASMA_CANNON :
			weapon_energy =						6.0;
			weapon_energy_per_shot =			6.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.25;
			weapon_range = 5000;
			break;
		case WEAPON_PULSE_LASER :
			weapon_energy =						15.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.5;
			weapon_range = 12500;
			break;
		case WEAPON_BEAM_LASER :
			weapon_energy =						15.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.1;
			weapon_range = 15000;
			break;
		case WEAPON_MINING_LASER :
			weapon_energy =						50.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				2.5;
			weapon_range = 12500;
			break;
		case WEAPON_THARGOID_LASER :
		case WEAPON_MILITARY_LASER :
			weapon_energy =						23.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.1;
			weapon_range = 30000;
			break;
	}
		
	if (energy <= weapon_energy_per_shot)
	{
		[universe addMessage:[universe expandDescription:@"[weapon-out-of-juice]" forSystem:system_seed] forCount:3.0];
		return NO;
	}
	
	using_mining_laser = (weapon_to_be_fired == WEAPON_MINING_LASER);
	
	energy -= weapon_energy_per_shot;

	switch ([universe viewDir])
	{
		case VIEW_DOCKED:
		case VIEW_NONE:
		case VIEW_BREAK_PATTERN:
		case VIEW_FORWARD:
//			NSLog(@"forward weapon offset = ( %.2f, %.2f, %.2f)", forwardWeaponOffset.x, forwardWeaponOffset.y, forwardWeaponOffset.z); 
			forward_weapon_temp += weapon_heat_increment_per_shot;
			break;
		case VIEW_AFT:
			aft_weapon_temp += weapon_heat_increment_per_shot;
			break;
		case VIEW_PORT:
			port_weapon_temp += weapon_heat_increment_per_shot;
			break;
		case VIEW_STARBOARD:
			starboard_weapon_temp += weapon_heat_increment_per_shot;
			break;
	}
	
	//NSLog(@"%@ firing weapon",name);
	switch (weapon_to_be_fired)
	{
		case WEAPON_PLASMA_CANNON :
			[self firePlasmaShot:10.0:1000.0:[OOColor greenColor]];
			return YES;
			break;
			
		case WEAPON_PULSE_LASER :
		case WEAPON_BEAM_LASER :
		case WEAPON_MINING_LASER :
		case WEAPON_MILITARY_LASER :
			[self fireLaserShotInDirection:[universe viewDir]];
			return YES;
			break;
		case WEAPON_THARGOID_LASER :
			[self fireDirectLaserShot];
			return YES;
			break;
	}
	return NO;
}

- (int) weaponForView:(int) view
{
	switch (view)
	{
		case VIEW_PORT :
			return port_weapon;
			break;
		case VIEW_STARBOARD :
			return starboard_weapon;
			break;
		case VIEW_AFT :
			return aft_weapon;
			break;
		case VIEW_FORWARD :
		default :
			return forward_weapon;
			break;
	}
}


- (void) takeEnergyDamage:(double) amount from:(Entity *) ent becauseOf:(Entity *) other
{
	Vector  rel_pos;
	double  d_forward;
	BOOL	internal_damage = NO;	// base chance
	
	if (status == STATUS_DEAD)
		return;
	if (amount == 0.0)
		return;
	
	[ent retain];
	[other retain];
	rel_pos = (ent)? ent->position: make_vector( 0.0f, 0.0f, 0.0f);
	
	rel_pos.x -= position.x;
	rel_pos.y -= position.y;
	rel_pos.z -= position.z;

	d_forward   =   dot_product(rel_pos, v_forward);

	if (damageSound)
	{
#ifdef HAVE_SOUND     
		if ([damageSound isPlaying])
			[damageSound stop];
		[damageSound play];
#endif      
	}
	
	// firing on an innocent ship is an offence
	if ((other)&&(other->isShip))
	{
		[self broadcastHitByLaserFrom:(ShipEntity*) other];
	}
		
	if (d_forward >= 0)
	{
		//NSLog(@"hit on FORWARD shields");
		forward_shield -= amount;
		if (forward_shield < 0.0)
		{
			amount = -forward_shield;
			forward_shield = 0.0;
		}
		else
		{
			amount = 0.0;
		}
	}
	else
	{
		//NSLog(@"hit on AFT shields");
		aft_shield -= amount;
		if (aft_shield < 0.0)
		{
			amount = -aft_shield;
			aft_shield = 0.0;
		}
		else
		{
			amount = 0.0;
		}
	}
	
	if (amount > 0.0)
	{
		internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems
		energy -= amount;
		if (scrapeDamageSound)
		{
#ifdef HAVE_SOUND        
			if ([scrapeDamageSound isPlaying])
				[scrapeDamageSound stop];
			[scrapeDamageSound play];
#endif         
		}
		ship_temperature += amount;
	}
	
	if ((energy <= 0.0)||(ship_temperature > SHIP_MAX_CABIN_TEMP))
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
		[self getDestroyed];
	}
	
	if (internal_damage)
	{
//		NSLog(@"DEBUG ***** triggered chance of internal damage! *****");
		[self takeInternalDamage];
	}
	
	[ent release];
	[other release];
	//
}

- (void) takeScrapeDamage:(double) amount from:(Entity *) ent
{
	Vector  rel_pos;
	double  d_forward;
	BOOL	internal_damage = NO;	// base chance
	
	if (status == STATUS_DEAD)
		return;
	
	[ent retain];
	rel_pos = (ent)? ent->position : make_vector( 0.0f, 0.0f, 0.0f);
	
	rel_pos.x -= position.x;
	rel_pos.y -= position.y;
	rel_pos.z -= position.z;

	d_forward   =   dot_product(rel_pos, v_forward);

	if (scrapeDamageSound)
	{
#ifdef HAVE_SOUND     
		if ([scrapeDamageSound isPlaying])
			[scrapeDamageSound stop];
		[scrapeDamageSound play];
#endif      
	}	
	if (d_forward >= 0)
	{
		forward_shield -= amount;
		if (forward_shield < 0.0)
		{
			amount = -forward_shield;
			forward_shield = 0.0;
		}
		else
		{
			amount = 0.0;
		}
	}
	else
	{
		aft_shield -= amount;
		if (aft_shield < 0.0)
		{
			amount = -aft_shield;
			aft_shield = 0.0;
		}
		else
		{
			amount = 0.0;
		}
	}
	
	if (amount)
		internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems

	energy -= amount;
	if (energy <= 0.0)
	{
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
		[self getDestroyed];
	}

	if (internal_damage)
	{
//		NSLog(@"DEBUG ***** triggered chance of internal damage! *****");
		[self takeInternalDamage];
	}
	
	//
	[ent release];
}

- (void) takeHeatDamage:(double) amount
{
	if (status == STATUS_DEAD)					// it's too late for this one!
		return;
	
	if (amount < 0.0)
		return;

	// hit the shields first!

	double fwd_amount = 0.5 * amount;
	double aft_amount = 0.5 * amount;
	
	forward_shield -= fwd_amount;
	if (forward_shield < 0.0)
	{
		fwd_amount = -forward_shield;
		forward_shield = 0.0;
	}
	else
		fwd_amount = 0.0;

	aft_shield -= aft_amount;
	if (aft_shield < 0.0)
	{
		aft_amount = -aft_shield;
		aft_shield = 0.0;
	}
	else
		aft_amount = 0.0;
	
	double residual_amount = fwd_amount + aft_amount;
	if (residual_amount <= 0.0)
		return;

	energy -= residual_amount;
	
	throw_sparks = YES;
	
	// oops we're burning up!
	if (energy <= 0.0)
		[self getDestroyed];
	else
	{
		// warn if I'm low on energy
		if (energy < max_energy *0.25)
			[shipAI message:@"ENERGY_LOW"];
	}
}

- (int) launchEscapeCapsule
{
	ShipEntity *doppelganger;
	Vector  vel;
	Vector  origin = position;
	int result = NO;
	Quaternion q1 = q_rotation;
	
	status = STATUS_ESCAPE_SEQUENCE;	// firstly
	ship_clock_adjust += 43200 + 5400 * (ranrot_rand() & 127);	// add up to 8 days until rescue!
	
	q1.w = -q1.w;   // player view is reversed remember!
	
	if (flight_speed < 50.0)
		flight_speed = 50.0;
	
	vel.x = flight_speed * v_forward.x;
	vel.y = flight_speed * v_forward.y;
	vel.z = flight_speed * v_forward.z;
	
	doppelganger = [universe getShip: ship_desc];   // retain count = 1
	if (doppelganger)
	{
		[doppelganger setPosition: origin];						// directly below
		[doppelganger setScanClass: CLASS_NEUTRAL];
		[doppelganger setQRotation: q1];
		[doppelganger setVelocity: vel];
		[doppelganger setSpeed: flight_speed];
		[doppelganger setRoll:0.2 * (randf() - 0.5)];
		[doppelganger setDesiredSpeed: flight_speed];
		[doppelganger setOwner: self];
		[doppelganger setStatus: STATUS_IN_FLIGHT];  // necessary to get it going!
		[doppelganger setBehaviour: BEHAVIOUR_IDLE];
		
		[universe addEntity:doppelganger];
		
		[[doppelganger getAI] setStateMachine:@"nullAI.plist"];  // fly straight on
		
		result = [doppelganger universal_id];
		
		[doppelganger release]; //release
	}
	
	// set up you
	[self setModel:@"escpod_redux.dat"];				// look right to anyone else (for multiplayer later)
	[universe setViewDirection:VIEW_FORWARD];
	flight_speed = 1.0;
	flight_pitch = 0.2 * (randf() - 0.5);
	flight_roll = 0.2 * (randf() - 0.5);

	double sheight = (boundingBox.max.y - boundingBox.min.y);
	position.x -= sheight * v_up.x;
	position.y -= sheight * v_up.y;
	position.z -= sheight * v_up.z;
	
	//remove escape pod
	[self remove_extra_equipment:@"EQ_ESCAPE_POD"];
	//has_escape_pod = NO;
	
	// reset legal status
	legal_status = 0;
	bounty = 0;
	
	// reset trumbles
	if (n_trumbles)
		n_trumbles = 1;
	
	// remove cargo
	[cargo removeAllObjects];
	
	energy = 25;
	[universe addMessage:[universe expandDescription:@"[escape-sequence]" forSystem:system_seed] forCount:4.5];
	shot_time = 0.0;
	
	return result;
}

- (int) dumpCargo
{
	if (flight_speed > 4.0 * max_flight_speed)
	{
		[universe addMessage:[universe expandDescription:@"[hold-locked]" forSystem:system_seed] forCount:3.0];
		return CARGO_NOT_CARGO;
	}
	
	int result = [super dumpCargo];
	if (result != CARGO_NOT_CARGO)
	{
		[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-ejected]" forSystem:system_seed],[universe nameForCommodity:result]] forCount:3.0];
	}
	return result;
}

- (void) rotateCargo
{
	int n_cargo = [cargo count];
	if (n_cargo == 0)
		return;
	ShipEntity* pod = (ShipEntity*)[[cargo objectAtIndex:0] retain];
	int current_contents = [pod getCommodityType];
	int contents = [pod getCommodityType];
	int rotates = 0;
	do	{
		[cargo removeObjectAtIndex:0];	// take it from the eject position
		[cargo addObject:pod];	// move it to the last position
		[pod release];
		pod = (ShipEntity*)[[cargo objectAtIndex:0] retain];
		contents = [pod getCommodityType];
		rotates++;
	}	while ((contents == current_contents)&&(rotates < n_cargo));
	[pod release];
	if (contents != CARGO_NOT_CARGO)
	{
		[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-ready-to-eject]" forSystem:system_seed],[universe nameForCommodity:contents]] forCount:3.0];
	}
	else
	{
		[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[ready-to-eject-@]" forSystem:system_seed],[pod name]] forCount:3.0];
	}
	// now scan through the remaining 1..(n_cargo - rotates) places moving similar cargo to the last place
	// this means the cargo gets to be sorted as it is rotated through
	int i;
	for (i = 1; i < (n_cargo - rotates); i++)
	{
		pod = (ShipEntity*)[cargo objectAtIndex:i];
		if ([pod getCommodityType] == current_contents)
		{
			[pod retain];
			[cargo removeObjectAtIndex:i--];
			[cargo addObject:pod];
			[pod release];
			rotates++;
		}
	}
	//
}

- (int) getBounty		// overrides returning 'bounty'
{
	return legal_status;
}
- (int) legal_status
{
	return legal_status;
}

- (void) markAsOffender:(int)offence_value
{
	legal_status |= offence_value;
}

- (void) collectBountyFor:(ShipEntity *)other
{
	if (!other)
		return;
	int score = 10 * [other getBounty];
	int killClass = other->scan_class; // **tgape** change (+line)
	int kill_award = 1;
	//
	if ([[other roles] isEqual:@"police"])   // oops, we shot a copper!
		legal_status |= 64;
	//
	if (![universe strict])	// only mess with the scores if we're not in 'strict' mode
	{
		BOOL killIsCargo = ((killClass == CLASS_CARGO)&&([other getCommodityAmount] > 0));
//		NSLog(@"DEBUG universe not strict killClass is %d", killClass);
		if ((killIsCargo)||(killClass == CLASS_BUOY)||(killClass == CLASS_ROCK))
		{
//			NSLog(@"DEBUG killClass not suitable for high reward");
			if (![[other roles] isEqual:@"tharglet"])	// okay, we'll count tharglets as proper kills
			{
//				NSLog(@"DEBUG reducing award");
				score /= 10;	// reduce bounty awarded
				kill_award = 0;	// don't award a kill
			}
		}
	}
	//
	credits += score;
	//
	if (score)
	{
		NSString* bonusMS1 = [NSString stringWithFormat:[universe expandDescription:@"[bounty-d]" forSystem:system_seed], score / 10];
		NSString* bonusMS2 = [NSString stringWithFormat:[universe expandDescription:@"[total-f-credits]" forSystem:system_seed], 0.1 * credits];
		//
		if (score > 9)
			[universe addDelayedMessage:bonusMS1 forCount:6 afterDelay:0.15];
		[universe addDelayedMessage:bonusMS2 forCount:6 afterDelay:0.15];
	}
	//
	while (kill_award > 0)
	{
		ship_kills++;
		kill_award--;
		if ((ship_kills % 256) == 0)
		{
			// congratulations method needs to be delayed a fraction of a second
			NSString* roc = [universe expandDescription:@"[right-on-commander]" forSystem:system_seed];
			[universe addDelayedMessage:roc forCount:4 afterDelay:0.2];
		}
	}
}

- (void) takeInternalDamage
{
	int n_cargo = max_cargo;
	int n_mass = [self mass] / 10000;
	int n_considered = n_cargo + n_mass;
	int damage_to = ranrot_rand() % n_considered;
	// cargo damage
	if (damage_to < [cargo count])
	{
		ShipEntity* pod = (ShipEntity*)[cargo objectAtIndex:damage_to];
		NSString* cargo_desc = [universe nameForCommodity:[pod getCommodityType]];
		if (!cargo_desc)
			return;
		[universe clearPreviousMessage];
		[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-destroyed]" forSystem:system_seed],cargo_desc] forCount:4.5];
		[cargo removeObject:pod];
		return;
	}
	else
	{
		damage_to = n_considered - (damage_to + 1);	// reverse the die-roll
	}
	// equipment damage
	if (damage_to < [extra_equipment count])
	{
		NSArray* systems = [extra_equipment allKeys];
		NSString* system_key = [systems objectAtIndex:damage_to];
		NSString* system_name = nil;
		if (([system_key hasSuffix:@"MISSILE"])||([system_key hasSuffix:@"MINE"])||([system_key isEqual:@"EQ_CARGO_BAY"]))
			return;
		NSArray* eq = [universe equipmentdata];
		int i;
		for (i = 0; (i < [eq count])&&(!system_name); i++)
		{
			NSArray* eqd = (NSArray*)[eq objectAtIndex:i];
			if ([system_key isEqual:[eqd objectAtIndex:EQUIPMENT_KEY_INDEX]])
				system_name = (NSString*)[eqd objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
		}
		if (!system_name)
			return;
		// set the following so removeEquipment works on the right entity
		[self setScript_target:self];
		[universe clearPreviousMessage];
		[self removeEquipment:system_key];
		if (![universe strict])
		{
			[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-damaged]" forSystem:system_seed],system_name] forCount:4.5];
			[self add_extra_equipment:[NSString stringWithFormat:@"%@_DAMAGED", system_key]];	// for possible future repair
		}
		else
			[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-destroyed]" forSystem:system_seed],system_name] forCount:4.5];
		return;
	}
	//cosmetic damage
	if (((damage_to & 7) == 7)&&(ship_trade_in_factor > 75))
		ship_trade_in_factor--;
}

- (NSDictionary*) damageInformation
{
//	int cost = 0;
	return nil;
}

- (void) getDestroyed
{
	NSString* scoreMS = [NSString stringWithFormat:@"Score: %.1f Credits",credits/10.0];

	if (![[universe gameController] playerFileToLoad])
		[[universe gameController] setPlayerFileToLoad: save_path];	// make sure we load the correct game

	energy = 0.0;
	afterburner_engaged = NO;
	[universe setDisplayText:NO];
	[universe setDisplayCursor:NO];
	[universe setViewDirection:VIEW_AFT];
	[self becomeLargeExplosion:4.0];
	[self moveForward:100.0];

#ifdef HAVE_SOUND
	[universe playCustomSound:@"[game-over]"];
	[destructionSound play];
#endif   
	flight_speed = 160.0;
	status = STATUS_DEAD;
	[universe displayMessage:@"Game Over" forCount:30.0];
	[universe displayMessage:@"" forCount:30.0];
	[universe displayMessage:scoreMS forCount:30.0];
	[universe displayMessage:@"" forCount:30.0];
	[universe displayMessage:@"Press Space" forCount:30.0];
	shot_time = 0.0;
	
	[self loseTargetStatus];
}

- (void) loseTargetStatus
{
	if (!universe)
		return;
	int			ent_count =		universe->n_entities;
	Entity**	uni_entities =	universe->sortedEntities;	// grab the public sorted list
	Entity*		my_entities[ent_count];
	int i;
	for (i = 0; i < ent_count; i++)
		my_entities[i] = [uni_entities[i] retain];		//	retained
	for (i = 0; i < ent_count ; i++)
	{
		Entity* thing = my_entities[i];
		if (thing->isShip)
		{
			ShipEntity* ship = (ShipEntity *)thing;
			if (self == [ship getPrimaryTarget])
			{
				[[ship getAI] message:@"TARGET_LOST"];
			}
		}
	}
	for (i = 0; i < ent_count; i++)
		[my_entities[i] release];		//	released
}

- (void) enterDock:(StationEntity *)station
{
	status = STATUS_DOCKING;
	
	afterburner_engaged = NO;
	
	cloaking_device_active = NO;
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	missile_status = MISSILE_STATUS_SAFE;
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;
	[universe setDisplayText:NO];
	[universe setDisplayCursor:NO];
	
	[self setQRotation: quaternion_identity];	// reset orientation to dock
	
	[universe set_up_break_pattern:position quaternion:q_rotation];
	[self playBreakPattern];
	
	[station noteDockedShip:self];
	docked_station = station;
	
	[[universe gameView] clearKeys];	// try to stop key bounces
	
}

- (void) docked
{
	status = STATUS_DOCKED;
	[universe setViewDirection:VIEW_DOCKED];
	
	[self loseTargetStatus];
	
	if (docked_station)
	{
		Vector launchPos = docked_station->position;
		position = launchPos;
		
		[self setQRotation: quaternion_identity];	// reset orientation to dock
	
		v_forward = vector_forward_from_quaternion(q_rotation);
		v_right = vector_right_from_quaternion(q_rotation);
		v_up = vector_up_from_quaternion(q_rotation);
	}
	
	flight_roll = 0.0;
	flight_pitch = 0.0;
	flight_speed = 0.0;	
	
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	missile_status =	MISSILE_STATUS_SAFE;
	
	primaryTarget = NO_TARGET;
	[self clearTargetMemory];
	
	forward_shield =	PLAYER_MAX_FORWARD_SHIELD;
	aft_shield =		PLAYER_MAX_AFT_SHIELD;
	energy =			max_energy;
	weapon_temp =		0.0;
	ship_temperature =		60.0;
	
	[self setAlert_flag:ALERT_FLAG_DOCKED :YES];
	
	if (![docked_station localMarket])
		[docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];

	[self unloadCargoPods];
	
	[universe setDisplayText:YES];
	
	if (ootunes_on)
	{
		// ootunes - pause current music
		[[universe gameController] pauseiTunes];
		// ootunes - play inflight music
		[[universe gameController] playiTunesPlaylist:@"Oolite-Docked"];
		docking_music_on = NO;
	}
	
	// time to check the script!
	[self checkScript];
	
	// if we've not switched to the mission screen then proceed normally..
	if (gui_screen != GUI_SCREEN_MISSION)
	{
		// check for fines
		if (being_fined)
			[self getFined];
		
		// check contracts
		NSString* deliveryReport = [self checkPassengerContracts];
		if (deliveryReport)
			[self setGuiToDeliveryReportScreenWithText:deliveryReport];
		else
			[self setGuiToStatusScreen];
	}
	
}

- (void) leaveDock:(StationEntity *)station
{
//	[universe setMessageGuiBackgroundColor:[OOColor clearColor]];	// clear the message gui background
	
	if (station == [universe station])
		legal_status |= [universe legal_status_of_manifest:shipCommodityData];  // 'leaving with those guns were you sir?'
	[self loadCargoPods];
	
	// clear the way
	[station autoDockShipsOnApproach];
	[station clearDockingCorridor];
	
	[station launchShip:self];
	q_rotation.w = -q_rotation.w;   // need this as a fix...
	flight_roll = -flight_roll;
	
	[self setAlert_flag:ALERT_FLAG_DOCKED :NO];
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;
	gui_screen = GUI_SCREEN_MAIN;
	[self clearTargetMemory];
	[self setShowDemoShips:NO];
	[universe setDisplayText:NO];
	[universe setDisplayCursor:NO];
	[universe set_up_break_pattern:position quaternion:q_rotation];
	[self playBreakPattern];
	
	[(MyOpenGLView *)[universe gameView] clearKeys];	// try to stop keybounces
	
	if (ootunes_on)
	{
		// ootunes - pause current music
		[[universe gameController] pauseiTunes];
		// ootunes - play inflight music
		[[universe gameController] playiTunesPlaylist:@"Oolite-Inflight"];
	}
	
	ship_clock_adjust = 600.0;			// 10 minutes to leave dock
	
	docked_station = nil;
}

- (void) enterGalacticWitchspace
{	
	status = STATUS_ENTERING_WITCHSPACE;
	
	if (primaryTarget != NO_TARGET)
		primaryTarget = NO_TARGET;
		
	hyperspeed_engaged = NO;
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;

	[universe setDisplayText:NO];

	[universe allShipAIsReactToMessage:@"PLAYER WITCHSPACE"];

	[universe removeAllEntitiesExceptPlayer:NO];
	
	// remove any contracts for the old galaxy
	if (contracts)
		[contracts removeAllObjects];
	
	// expire passenger contracts for the old galaxy
	if (passengers)
	{
		int i;
		for (i = 0; i < [passengers count]; i++)
		{
			// set the expected arrival time to now, so they storm off the ship at the first port
			NSMutableDictionary* passenger_info = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[passengers objectAtIndex:i]];
			[passenger_info setObject:[NSNumber numberWithDouble:ship_clock] forKey:PASSENGER_KEY_ARRIVAL_TIME];
			[passengers replaceObjectAtIndex:i withObject:passenger_info];
		}
	}
	
	[self remove_extra_equipment:@"EQ_GAL_DRIVE"];
	
	galaxy_number++;
	galaxy_number &= 7;
	
	galaxy_seed.a = rotate_byte_left(galaxy_seed.a);
	galaxy_seed.b = rotate_byte_left(galaxy_seed.b);
	galaxy_seed.c = rotate_byte_left(galaxy_seed.c);
	galaxy_seed.d = rotate_byte_left(galaxy_seed.d);
	galaxy_seed.e = rotate_byte_left(galaxy_seed.e);
	galaxy_seed.f = rotate_byte_left(galaxy_seed.f);
	
	[universe setGalaxy_seed:galaxy_seed];
	//system_seed = [universe findSystemAtCoords:NSMakePoint(0x60, 0x60) withGalaxySeed:galaxy_seed];
	//
	// instead find a system connected to system 0 near the current coordinates...
	system_seed = [universe findConnectedSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	//
	target_system_seed = system_seed;
	
	[universe setSystemTo:system_seed];
	galaxy_coordinates.x = system_seed.d;
	galaxy_coordinates.y = system_seed.b;
    ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	market_rnd = ranrot_rand() & 255;						// random factor for market values is reset
	legal_status = 0;
	[universe set_up_universe_from_witchspace];
}

- (void) enterWormhole:(WormholeEntity*) w_hole
{
	target_system_seed = [w_hole destination];
	status = STATUS_ENTERING_WITCHSPACE;
	
	hyperspeed_engaged = NO;
	
	if (primaryTarget != NO_TARGET)
		primaryTarget = NO_TARGET;
		
	//
	//	reset the compass
	//
	if ([self has_extra_equipment:@"EQ_ADVANCED_COMPASS"])
		compass_mode = COMPASS_MODE_PLANET;
	else
		compass_mode = COMPASS_MODE_BASIC;

	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y); 
	ship_clock_adjust = distance * distance * 3600.0;		// LY * LY hrs
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;

	[universe setDisplayText:NO];

	[universe allShipAIsReactToMessage:@"PLAYER WITCHSPACE"];

	[universe removeAllEntitiesExceptPlayer:NO];
	[universe setSystemTo:target_system_seed];
	
	system_seed = target_system_seed;
	galaxy_coordinates.x = system_seed.d;
	galaxy_coordinates.y = system_seed.b;
	legal_status /= 2;										// 'another day, another system'
	ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	market_rnd = ranrot_rand() & 255;						// random factor for market values is reset
	//
	[universe set_up_universe_from_witchspace];
	[[universe planet] update: 2.34375 * market_rnd];	// from 0..10 minutes
	[[universe station] update: 2.34375 * market_rnd];	// from 0..10 minutes
}

- (void) enterWitchspace
{
	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y); 
	
	status = STATUS_ENTERING_WITCHSPACE;	

	hyperspeed_engaged = NO;
	
	if (primaryTarget != NO_TARGET)
		primaryTarget = NO_TARGET;
		
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;

	[universe setDisplayText:NO];

	[universe allShipAIsReactToMessage:@"PLAYER WITCHSPACE"];

	[universe removeAllEntitiesExceptPlayer:NO];
	//
	//	reset the compass
	//
	if ([self has_extra_equipment:@"EQ_ADVANCED_COMPASS"])
		compass_mode = COMPASS_MODE_PLANET;
	else
		compass_mode = COMPASS_MODE_BASIC;
	//
	//  perform any check here for forced witchspace encounters
	//
	int malfunc_chance = 253;
    if (ship_trade_in_factor < 80)
		malfunc_chance -= (1 + ranrot_rand() % (81-ship_trade_in_factor)) / 2;	// increase chance of misjump in worn-out craft
	ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	BOOL malfunc = ((ranrot_rand() & 0xff) > malfunc_chance);
	// 75% of the time a malfunction means a misjump
	BOOL misjump = ((flight_pitch == max_flight_pitch) || (malfunc && (randf() > 0.75)));

//	malfunc = (malfunc || (flight_pitch == -max_flight_pitch));	// DEBUGGING
	
	fuel -= 10.0 * distance;								// fuel cost to target system
	ship_clock_adjust = distance * distance * 3600.0;		// LY * LY hrs
	if (!misjump)
	{	
		[universe setSystemTo:target_system_seed];
		system_seed = target_system_seed;
		galaxy_coordinates.x = system_seed.d;
		galaxy_coordinates.y = system_seed.b;
		legal_status /= 2;								// 'another day, another system'
		market_rnd = ranrot_rand() & 255;				// random factor for market values is reset
		if (market_rnd < 8)
			[self erodeReputation];						// every 32 systems or so, drop back towards 'unknown'
		//
		if (2 * market_rnd < ship_trade_in_factor)			// every eight jumps or so
			ship_trade_in_factor -= 1 + (market_rnd & 3);	// drop the price down towards 75%
		if (ship_trade_in_factor < 75)
			ship_trade_in_factor = 75;						// lower limit for trade in value is 75%
		//
		[universe set_up_universe_from_witchspace];
		[[universe planet] update: 2.34375 * market_rnd];	// from 0..10 minutes
		[[universe station] update: 2.34375 * market_rnd];	// from 0..10 minutes
		if (malfunc)
		{
			if (randf() > 0.5)
				[self setFuelLeak:[NSString stringWithFormat:@"%f", (randf() + randf()) * 5.0]];
			else
			{
				[warningSound play];
				[self takeInternalDamage];
			}
		}
	}
	else
	{
		//NSLog(@"---> Witchspace misjump");
		// move sort of halfway there...
		galaxy_coordinates.x += target_system_seed.d;
		galaxy_coordinates.y += target_system_seed.b;
		galaxy_coordinates.x /= 2;
		galaxy_coordinates.y /= 2;
		if (![universe playCustomSound:@"[witchdrive-malfunction]"])
			[self playECMSound];
		[universe set_up_universe_from_misjump];
	}
}

- (void) leaveWitchspace
{
	Vector		pos = [universe getWitchspaceExitPosition];
	Quaternion  q_rtn = [universe getWitchspaceExitRotation];
	Quaternion	q1;

	quaternion_set_random(&q1);
	double		d1 = SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
	if (abs(d1) < 500.0)	// no closer than 500m
		d1 += ((d1 > 0.0)? 500.0: -500.0);
	Vector		v1 = vector_forward_from_quaternion(q1);
	pos.x += v1.x * d1; // randomise exit position
	pos.y += v1.y * d1;
	pos.z += v1.z * d1;

	position = pos;
	q_rotation = q_rtn;
	flight_roll = 0.0;
	flight_pitch = 0.0;
	flight_speed = max_flight_speed * 0.25;
	status = STATUS_EXITING_WITCHSPACE;
	gui_screen = GUI_SCREEN_MAIN;
	being_fined = NO;				// until you're scanned by a copper!
	[self clearTargetMemory];
	[self setShowDemoShips:NO];
	[universe setDisplayCursor:NO];
	[universe setDisplayText:NO];
	[universe set_up_break_pattern:position quaternion:q_rotation];
	[self playBreakPattern];
}

- (void) performDocking
{
	[self abortDocking];			// let the station know that you are no longer on approach
	autopilot_engaged = NO;
	status = STATUS_IN_FLIGHT;
}

///////////////////////////////////////

- (void) quicksavePlayer
{
	NSString* filename = save_path;
	if (!filename)
		filename = [[(MyOpenGLView *)[universe gameView] gameController] playerFileToLoad];
	if (!filename)
	{
		NSBeep();
		NSLog(@"ERROR no filename returned by [[(MyOpenGLView *)[universe gameView] gameController] playerFileToLoad]");
		NSException* myException = [NSException
			exceptionWithName:@"GameNotSavedException"
			reason:@"ERROR no filename returned by [[(MyOpenGLView *)[universe gameView] gameController] playerFileToLoad]"
			userInfo:nil];
		[myException raise];
		return;
	}
	if (![[self commanderDataDictionary] writeOOXMLToFile:filename atomically:YES])
	{
		NSBeep();
		NSLog(@"***** ERROR: Save to %@ failed!", filename);
		NSException* myException = [NSException
			exceptionWithName:@"OoliteException"
			reason:[NSString stringWithFormat:@"Attempt to save game to file '%@' failed for some reason", filename]
			userInfo:nil];
		[myException raise];
		return;
	}
	else
	{
		// try saving the cache now...
		NSString*	cache_path = OOLITE_CACHE;
		NSLog(@"DEBUG ** saving cache ...**");
		[[[Entity dataStore] preloadedDataFiles] writeToFile: cache_path atomically: YES];
		//
		[universe clearPreviousMessage];	// allow this to be given time and again
		[universe addMessage:[universe expandDescription:@"[game-saved]" forSystem:system_seed] forCount:2];
		if (save_path)
			[save_path autorelease];
		save_path = [filename retain];
	}
	[self setGuiToStatusScreen];
}

- (void) savePlayer
{
	NSSavePanel *sp;
	int runResult;

	/* create or get the shared instance of NSSavePanel */
	sp = [NSSavePanel savePanel];

	/* set up new attributes */
	[sp setRequiredFileType:@"oolite-save"];

	/* display the NSSavePanel */
	
	runResult = [sp runModalForDirectory:nil file:player_name];

	/* if successful, save file under designated name */
	if (runResult == NSOKButton)
	{
		NSArray*	path_components = [[sp filename] pathComponents];
		NSString*   new_name = [[path_components objectAtIndex:[path_components count]-1] stringByDeletingPathExtension]; 
		
		//NSLog(@"Attempting to save to %@",[sp filename]);
		//NSLog(@"Will set Commander's name to %@", new_name);
		
		if (player_name)	[player_name release];
		player_name = [new_name retain];
		
		if (![[self commanderDataDictionary] writeOOXMLToFile:[sp filename] atomically:YES])
		{
			NSBeep();
			NSLog(@"***** ERROR: Save to %@ failed!", [sp filename]);
			NSException* myException = [NSException
				exceptionWithName:@"OoliteException"
				reason:[NSString stringWithFormat:@"Attempt to save game to file '%@' failed for some reason", [sp filename]]
				userInfo:nil];
			[myException raise];
			return;
		}
		else
		{
			// set this as the default file to load / save
			if (save_path)
				[save_path autorelease];
			save_path = [[NSString stringWithString:[sp filename]] retain];
			[[universe gameController] setPlayerFileToLoad:save_path];
			[[universe gameController] setPlayerFileDirectory:save_path];
		}
		// try saving the cache ...
		NSString*	cache_path = OOLITE_CACHE;
		NSLog(@"DEBUG ** saving cache ...**");
		[[[Entity dataStore] preloadedDataFiles] writeToFile: cache_path atomically: YES];
	}
	[self setGuiToStatusScreen];
}

- (void) loadPlayer
{
    int result;
    NSArray *fileTypes = [NSArray arrayWithObject:@"oolite-save"];
    NSOpenPanel *oPanel = [NSOpenPanel openPanel];

    [oPanel setAllowsMultipleSelection:NO];
    result = [oPanel runModalForDirectory:nil file:nil types:fileTypes];
    if (result == NSOKButton)
		[self loadPlayerFromFile:[oPanel filename]];
}

- (void) loadPlayerFromFile:(NSString *)fileToOpen
{
	BOOL loadedOK = YES;
	NSDictionary*	fileDic = nil;
	NSString*	fail_reason = nil;
	if (fileToOpen)
	{
		fileDic = [NSDictionary dictionaryWithContentsOfFile:fileToOpen];
		
		// FIX FOR WINDOWS GNUSTEP NOT PARSING XML PLISTS
		NS_DURING
			if (!fileDic)	// try parsing it using our home-grown XML parser
				fileDic = (NSDictionary*)[ResourceManager parseXMLPropertyList:[NSString stringWithContentsOfFile:fileToOpen]];
		NS_HANDLER
			fileDic = nil;
			loadedOK = NO;
			if ([[localException name] isEqual: OOLITE_EXCEPTION_XML_PARSING_FAILURE])	// note it happened here 
			{
				NSLog(@"***** [PlayerEntity loadPlayerFromFile:] encountered exception : %@ : %@ *****",[localException name], [localException reason]);
				fail_reason = [NSString stringWithFormat:@"Couldn't parse %@ as an Oolite saved game", fileToOpen];
			}
			else
				[localException raise];
		NS_ENDHANDLER
					
		if (fileDic)
		{
			[self set_up];
			NS_DURING
				[self setCommanderDataFromDictionary:fileDic];
			NS_HANDLER
				loadedOK = NO;
				if ([[localException name] isEqual: OOLITE_EXCEPTION_SHIP_NOT_FOUND])
				{
					NSLog(@"***** Oolite Exception : '%@' in [PlayerEntity loadPlayerFromFile: %@ ] *****", [localException reason], fileToOpen);
					fail_reason = @"Couldn't load Commander details for some reason (AddOns folder missing an OXP perhaps?)";
				}
				else
					[localException raise];
			NS_ENDHANDLER
		}
		else
			loadedOK = NO;
	}
	if (loadedOK)
	{
		if (save_path)
			[save_path autorelease];
		save_path = [fileToOpen retain];
		[[(MyOpenGLView *)[universe gameView] gameController] setPlayerFileToLoad:fileToOpen];
		[[(MyOpenGLView *)[universe gameView] gameController] setPlayerFileDirectory:fileToOpen];
	}
	else
	{
		NSLog(@"***** FILE LOADING ERROR!! *****");
		NSBeep();
		[[universe gameController] setPlayerFileToLoad:nil];
		[universe game_over];
		[universe clearPreviousMessage];
		[universe addMessage:@"Saved game failed to load." forCount: 9.0];
		if (fail_reason)
			[universe addMessage: fail_reason forCount: 9.0];
		return;
	}
	
	[universe setSystemTo:system_seed];
	[universe removeAllEntitiesExceptPlayer:NO];
	[universe set_up_space];
	
	status = STATUS_DOCKED;
	[universe setViewDirection:VIEW_DOCKED];
	
	docked_station = [universe station];
	if (docked_station)
	{
		position = docked_station->position;
		[self setQRotation: quaternion_identity];
		v_forward = vector_forward_from_quaternion(q_rotation);
		v_right = vector_right_from_quaternion(q_rotation);
		v_up = vector_up_from_quaternion(q_rotation);
	}
	
	flight_roll = 0.0;
	flight_pitch = 0.0;
	flight_speed = 0.0;
	
	if (![docked_station localMarket])
	{
		if ([fileDic objectForKey:@"localMarket"])
		{
			[docked_station setLocalMarket:(NSArray *)[fileDic objectForKey:@"localMarket"]];
		}
		else
		{
			[docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
		}
	}
	[self setGuiToStatusScreen];
}

- (void) changePlayerName
{
}


///////////////////////////////////////

- (void) setGuiToStatusScreen
{
	NSDictionary*   descriptions = [universe descriptions];
	NSString*		systemName;
	NSString*		targetSystemName;
	
	//NSLog(@"DEBUG original hold size = %d",original_hold_size);
	
	system_seed =			[universe findSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	target_system_seed =	[universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	
	systemName =	[universe getSystemName:system_seed];
	if (status == STATUS_DOCKED)
	{
		if ((docked_station != [universe station])&&(docked_station != nil))
			systemName = [NSString stringWithFormat:@"%@ : %@", systemName, [(ShipEntity*)docked_station name]];
	}
			
	targetSystemName =	[universe getSystemName:target_system_seed];
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		int equip_row = 10;
		int tab_stops[GUI_MAX_COLUMNS]; 
		tab_stops[0] = 20;
		tab_stops[1] = 160;
		tab_stops[2] = 256;
		[gui setTabStops:tab_stops];
		
		NSArray*	gear = [self equipmentList];

		int legal_index = 0;
		if (legal_status != 0)
			legal_index = (legal_status <= 50) ? 1 : 2;
		int rating = [self getRatingFromKills: ship_kills];
		
		NSDictionary *ship_dict = [universe getDictionaryForShip:ship_desc];
		NSString* shipName = (NSString*)[ship_dict objectForKey:KEY_NAME];
		
		NSString*   legal_desc = (NSString *)[(NSArray *)[descriptions objectForKey:@"legal_status"] objectAtIndex:legal_index];
//		NSString*   rating_desc = (NSString *)[(NSArray *)[descriptions objectForKey:@"rating"] objectAtIndex:rating];
		NSString*   rating_desc = [NSString stringWithFormat:@"%@ (%d)",[(NSArray *)[descriptions objectForKey:@"rating"] objectAtIndex:rating], ship_kills];
		NSString*   alert_desc = (NSString *)[(NSArray *)[descriptions objectForKey:@"condition"] objectAtIndex:[self alert_condition]];
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Commander %@",   player_name]];
		//
		[gui setText:shipName forRow:0 align:GUI_ALIGN_CENTER];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Present System:", systemName, nil]			forRow:1];
		[gui setArray:[NSArray arrayWithObjects:@"Hyperspace System:", targetSystemName, nil]	forRow:2];
		[gui setArray:[NSArray arrayWithObjects:@"Condition:", alert_desc, nil]					forRow:3];
		[gui setArray:[NSArray arrayWithObjects:@"Fuel:", [NSString stringWithFormat:@"%.1f Light Years", fuel/10.0], nil]	forRow:4];
		[gui setArray:[NSArray arrayWithObjects:@"Cash:", [NSString stringWithFormat:@"%.1f Cr", credits/10.0], nil]		forRow:5];
		[gui setArray:[NSArray arrayWithObjects:@"Legal Status:", legal_desc, nil]				forRow:6];
		[gui setArray:[NSArray arrayWithObjects:@"Rating:", rating_desc, nil]					forRow:7];
		//
		[gui setText:@"Equipment:"  forRow:9];
		
		int i = 0;
		int n_equip_rows = 5;
		while ([gear count] > n_equip_rows * 2)	// make room for larger numbers of items
			n_equip_rows++;						// by extending the length of the two columns
		for (i = 0; i < n_equip_rows; i++)
		{
			NSMutableArray*		row_info = [NSMutableArray arrayWithCapacity:3];
			if (i < [gear count])
				[row_info addObject:[gear objectAtIndex:i]];
			else
				[row_info addObject:@""];
				
			// add a blank
			[row_info addObject:@""];
				
			if (i + n_equip_rows < [gear count])
				[row_info addObject:[gear objectAtIndex:i + n_equip_rows]];
			else
				[row_info addObject:@""];
			[gui setArray:(NSArray *)row_info forRow:equip_row + i];
		}

		
		[gui setShowTextCursor:NO];
		
	}
	/* ends */
	
	//NSLog(@"gui_screen = GUI_SCREEN_STATUS");
	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	gui_screen = GUI_SCREEN_STATUS;

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[universe setViewDirection: VIEW_DOCKED];


	// DEBUG TEST ROUTINES
		NSLog(@"DEBUG Player q_rotation = (%.2f %.2f %.2f %.2f)",
			q_rotation.w, q_rotation.x, q_rotation.y, q_rotation.z);
		[universe removeDemoShips];
		[self debugOn];
		[self setBackgroundFromDescriptionsKey:@"test-scene"];
		[self setShowDemoShips: YES];
		[self debugOff];
		NSLog(@"DEBUG Player q_rotation = (%.2f %.2f %.2f %.2f)",
			q_rotation.w, q_rotation.x, q_rotation.y, q_rotation.z);
		NSLog(@"DEBUG status %d showDemoShips:%@", status, [self showDemoShips]? @"YES":@"NO");
	// END TEST
	
}

// DJS: moved from the above method because there are
// now two places where the rating needs to be calculated.
// (The other place is in LoadSave.m - tag to help find
// this change if this is integrated with OS X - 
// #define LOADSAVEGUI ...)
- (int) getRatingFromKills: (int)shipKills
{
   int rating = 0;
	int kills[8] = { 0x0008,  0x0010, 0x0020,  0x0040,  0x0080,  0x0200,  0x0A00,  0x1900 };
	while ((rating < 8)&&(kills[rating] <= shipKills))
	{
		rating ++;
	}
   return rating;
}

- (NSArray *) equipmentList
{
	NSDictionary*   descriptions = [universe descriptions];
	//int				original_hold_size = [universe maxCargoForShip:ship_desc];
	NSMutableArray* quip = [NSMutableArray arrayWithCapacity:32];
	//
	int i;
	NSArray* equipmentinfo = [universe equipmentdata];
	for (i =0; i < [equipmentinfo count]; i++)
	{
		NSString *w_key = (NSString *)[(NSArray *)[equipmentinfo objectAtIndex:i] objectAtIndex:EQUIPMENT_KEY_INDEX];
		if ([self has_extra_equipment:w_key])
			[quip addObject:(NSString *)[(NSArray *)[equipmentinfo objectAtIndex:i] objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX]];
	}

	if (forward_weapon > 0)
		[quip addObject:[NSString stringWithFormat:@"Forward %@",(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:forward_weapon]]];
	if (aft_weapon > 0)
		[quip addObject:[NSString stringWithFormat:@"Aft %@",(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:aft_weapon]]];
	if (starboard_weapon > 0)
		[quip addObject:[NSString stringWithFormat:@"Starboard %@",(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:starboard_weapon]]];
	if (port_weapon > 0)
		[quip addObject:[NSString stringWithFormat:@"Port %@",(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:port_weapon]]];
	
	if (max_passengers > 0)
		[quip addObject:[NSString stringWithFormat:@"%d Passenger Berth%@", max_passengers, (max_passengers > 1)? @"s" : @""]];
	
	return [NSArray arrayWithArray:quip];
}

- (NSArray *) cargoList
{
	NSMutableArray* manifest = [NSMutableArray arrayWithCapacity:32];
	//
//	NSLog(@"DEBUG ::::: %@", [shipCommodityData description]);
	
	if (specialCargo)
		[manifest addObject:specialCargo];
	
	int n_commodities = [shipCommodityData count];
	int in_hold[n_commodities];
	int i;
	//
	// following changed to work whether docked or not
	for (i = 0; i < n_commodities; i++)
		in_hold[i] = [(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
	for (i = 0; i < [cargo count]; i++)
	{
		ShipEntity *container = (ShipEntity *)[cargo objectAtIndex:i];
		in_hold[[container getCommodityType]] += [container getCommodityAmount];
	}
	//
	for (i = 0; i < n_commodities; i++)
	{
		if (in_hold[i] > 0)
		{
			int unit = [universe unitsForCommodity:i];
			NSString* units = @"t";
			if (unit == UNITS_KILOGRAMS)  units = @"kg";
			if (unit == UNITS_GRAMS)  units = @"g"; 
			NSString* desc = (NSString *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_NAME];
			[manifest addObject:[NSString stringWithFormat:@"%d%@ x %@", in_hold[i], units, desc]];
		}
	}

//	// debug
//	NSLog(@"DEBUG shipCommodityData:-\n%@", [shipCommodityData description]);
//	NSLog(@"DEBUG manifest:-\n%@", [manifest description]);

	//
	return [NSArray arrayWithArray:manifest];
}

- (void) setGuiToSystemDataScreen
{
	NSDictionary*   targetSystemData;
	NSString*		targetSystemName;
	NSDictionary*   descriptions = [universe descriptions];
	
	target_system_seed =	[universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	
	targetSystemData =		[[universe generateSystemData:target_system_seed] retain];  // retained
	targetSystemName =		[[universe getSystemName:target_system_seed] retain];  // retained
	
	BOOL	sun_gone_nova = NO;
	if ([targetSystemData objectForKey:@"sun_gone_nova"])
		sun_gone_nova = YES;
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		int tab_stops[GUI_MAX_COLUMNS]; 
		tab_stops[0] = 0;
		tab_stops[1] = 96;
		tab_stops[2] = 144;
		[gui setTabStops:tab_stops];

		int government =	[(NSNumber *)[targetSystemData objectForKey:KEY_GOVERNMENT] intValue];
		int economy =		[(NSNumber *)[targetSystemData objectForKey:KEY_ECONOMY] intValue];
		int techlevel =		[(NSNumber *)[targetSystemData objectForKey:KEY_TECHLEVEL] intValue];
		int population =	[(NSNumber *)[targetSystemData objectForKey:KEY_POPULATION] intValue];
		int productivity =	[(NSNumber *)[targetSystemData objectForKey:KEY_PRODUCTIVITY] intValue];
		int radius =		[(NSNumber *)[targetSystemData objectForKey:KEY_RADIUS] intValue];
		
		NSString*   government_desc =   (NSString *)[(NSArray *)[descriptions objectForKey:KEY_GOVERNMENT] objectAtIndex:government];
		NSString*   economy_desc =		(NSString *)[(NSArray *)[descriptions objectForKey:KEY_ECONOMY] objectAtIndex:economy];
		NSString*   inhabitants =		(NSString *)[targetSystemData objectForKey:KEY_INHABITANTS];
		NSString*   system_desc =		(NSString *)[targetSystemData objectForKey:KEY_DESCRIPTION];

		if ((sun_gone_nova && equal_seeds( target_system_seed, system_seed) && [[universe sun] goneNova])||
			(sun_gone_nova && (!equal_seeds( target_system_seed, system_seed))))
		{
			population = 0;
			productivity = 0;
			radius = 0;
			system_desc = [universe expandDescription:@"[nova-system-description]" forSystem:target_system_seed];
		}
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Data on %@",   targetSystemName]];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Economy:", economy_desc, nil]						forRow:1];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Government:", government_desc, nil]				forRow:3];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Tech Level:", [NSString stringWithFormat:@"%d", techlevel + 1], nil]	forRow:5];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Population:", [NSString stringWithFormat:@"%.1f Billion", 0.1*population], nil]	forRow:7];
		[gui setArray:[NSArray arrayWithObjects:@"", [NSString stringWithFormat:@"(%@)", inhabitants], nil]				forRow:8];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Gross Productivity:", @"", [NSString stringWithFormat:@"%5d M Cr.", productivity], nil]	forRow:10];
		//
		[gui setArray:[NSArray arrayWithObjects:@"Average radius:", @"", [NSString stringWithFormat:@"%5d km", radius], nil]	forRow:12];
		//
		int i = [gui addLongText:system_desc startingAtRow:15 align:GUI_ALIGN_LEFT];
		missionTextRow = i;
		for (i-- ; i > 14 ; i--)
			[gui setColor:[OOColor greenColor] forRow:i];
		//
		
		[gui setShowTextCursor:NO];
		
	}
	/* ends */
	
	//NSLog(@"gui_screen = GUI_SCREEN_SYSTEM_DATA for system %@ at (%d,%d)",targetSystemName,target_system_seed.d,target_system_seed.b);

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	[targetSystemData release]; // released
	[targetSystemName release]; // released
	
	gui_screen = GUI_SCREEN_SYSTEM_DATA;

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[universe setViewDirection: VIEW_DOCKED];
}

- (NSArray *) markedDestinations
{
	NSMutableArray* destinations = [NSMutableArray arrayWithCapacity:256];
	// get a list of systems marked as contract destinations
	BOOL mark[256];
	int i;
	for (i = 0; i < 256; i++)
		mark[i] = NO;
	for (i = 0; i < [passengers count]; i++)
		mark[[(NSNumber*)[(NSDictionary*)[passengers objectAtIndex:i] objectForKey:PASSENGER_KEY_DESTINATION] intValue]] = YES;
	for (i = 0; i < [contracts count]; i++)
		mark[[(NSNumber*)[(NSDictionary*)[contracts objectAtIndex:i] objectForKey:CONTRACT_KEY_DESTINATION] intValue]] = YES;
	for (i = 0; i < 256; i++)
		[destinations addObject:[NSNumber numberWithBool:mark[i]]];

	return destinations;
}

- (void) setGuiToLongRangeChartScreen
{
	NSString*   targetSystemName;
	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y); 
	int			i;
	
	if ((target_system_seed.d != cursor_coordinates.x)||(target_system_seed.b != cursor_coordinates.y))
		target_system_seed =	[universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	targetSystemName =		[[universe getSystemName:target_system_seed] retain];  // retained
		
	// get a list of systems marked as contract destinations
	BOOL mark[256];
	for (i = 0; i < 256; i++)
		mark[i] = NO;
	for (i = 0; i < [passengers count]; i++)
		mark[[(NSNumber*)[(NSDictionary*)[passengers objectAtIndex:i] objectForKey:PASSENGER_KEY_DESTINATION] intValue]] = YES;
	for (i = 0; i < [contracts count]; i++)
		mark[[(NSNumber*)[(NSDictionary*)[contracts objectAtIndex:i] objectForKey:CONTRACT_KEY_DESTINATION] intValue]] = YES;
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Galactic Chart %d",   galaxy_number+1]];
		//
		[gui setText:targetSystemName														forRow:17];
		[gui setText:[NSString stringWithFormat:@"Distance:\t%.1f Light Years", distance]   forRow:18];
		//
		if (planetSearchString)
			[gui setText:[NSString stringWithFormat:@"Find planet: %@", [planetSearchString capitalizedString]]  forRow:16];
		else
			[gui setText:@"Find planet: "  forRow:16];
		[gui setColor:[OOColor cyanColor] forRow:16];
		
		[gui setShowTextCursor:YES];
		[gui setCurrentRow:16];
		
		//
	}
	/* ends */
	
	//NSLog(@"gui_screen = GUI_SCREEN_LONG_RANGE_CHART");
	
	gui_screen = GUI_SCREEN_LONG_RANGE_CHART;
	
	[targetSystemName release]; // released

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) starChartDump
{
	NSString	*filepath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
	NSString	*pathToPic = [filepath stringByAppendingPathComponent:[NSString stringWithFormat:@"StarChart-Galaxy-%03d.tiff",galaxy_number]];
	BOOL		dumpPic = (![[NSFileManager defaultManager] fileExistsAtPath:pathToPic]);
	NSString	*pathToData = [filepath stringByAppendingPathComponent:[NSString stringWithFormat:@"StarChartData-Galaxy-%03d.txt",galaxy_number]];
	BOOL		dumpData = (![[NSFileManager defaultManager] fileExistsAtPath:pathToData]);
	
	NSString*   targetSystemName;
	Random_Seed	g_seed = galaxy_seed;
	
	target_system_seed =	[universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	targetSystemName =		[[universe getSystemName:target_system_seed] retain];  // retained
	
	int star_x[256];
	int star_y[256];
	
	NSPoint nudge[256];
	
	NSMutableString *stardump = [NSMutableString stringWithString:@"\nStar List\n"];
	g_seed = galaxy_seed;
	int i;
	for (i = 0; i < 256; i++)
	{
		NSDictionary* systemDataDic = [universe generateSystemData:g_seed];
		int government =	[(NSNumber *)[systemDataDic objectForKey:KEY_GOVERNMENT] intValue];
		int techlevel =		[(NSNumber *)[systemDataDic objectForKey:KEY_TECHLEVEL] intValue];
		NSString*   government_desc =   (NSString *)[(NSArray *)[[universe descriptions] objectForKey:KEY_GOVERNMENT] objectAtIndex:government];
		NSString*   inhabitants =		(NSString *)[systemDataDic objectForKey:KEY_INHABITANTS];
		NSString*   system_desc =		(NSString *)[systemDataDic objectForKey:KEY_DESCRIPTION];
		
		star_x[i] = g_seed.d;
		star_y[i] = g_seed.b;
		
		nudge[i] = NSMakePoint(0.0,0.0);
		
		[stardump appendFormat:@"System %d,\t%@\t(%d,%d)\tTL: %d\t%@\t%@\n\t\"%@\"\n", i, [universe getSystemName:g_seed], g_seed.d, g_seed.b, techlevel, inhabitants, government_desc, system_desc];
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
		rotate_seed(&g_seed);
	}
	if (dumpData)
		[stardump writeToFile:pathToData atomically:YES];
		
	
	// drawing stuff
	if (dumpPic)
	{
		NSMutableDictionary *textAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
			[NSFont systemFontOfSize:9.0], NSFontAttributeName,
			[OOColor blueColor], NSForegroundColorAttributeName, NULL];

		NSSize  imageSize = NSMakeSize(1088,576);
		NSSize  chartSize = NSMakeSize(1024,512);

		NSImage*	drawImage = [[NSImage alloc] initWithSize:imageSize];
		
		NSPoint		star;
		
		g_seed = galaxy_seed;
		double		hscale = chartSize.width / 256.0;
		double		vscale = chartSize.height / 256.0;
		double		hoffset = (imageSize.width - chartSize.width) / 2.0;
		double		voffset = (imageSize.height - chartSize.height) / 2.0;
		
		[drawImage lockFocus];
		
		[[NSColor darkGrayColor] set];
		NSRectFill(NSMakeRect(0.0,0.0,imageSize.width,imageSize.height));
		
		[[NSColor grayColor] set];
		[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
		[NSBezierPath setDefaultLineWidth:36.0];
		//draw connectivity map
		int j;
		for (i = 0; i < 256; i++) for (j = i + 1; j < 256; j++)
		{
			double d = distanceBetweenPlanetPositions(star_x[i],star_y[i],star_x[j],star_y[j]);
			
			if (d <= 7.0)
			{
				NSPoint p1 = NSMakePoint(star_x[i] * hscale + hoffset,(256 - star_y[i]) * vscale + voffset);
				NSPoint p2 = NSMakePoint(star_x[j] * hscale + hoffset,(256 - star_y[j]) * vscale + voffset);
				
				nudge[i].x += (d != 0.0) ? hscale * (star_x[i] - star_x[j])/(d*d*4.0) : 10.0;
				nudge[i].y += (d != 0.0) ? vscale * (star_y[i] - star_y[j])/(d*d*4.0) : 10.0;
				nudge[j].x -= (d != 0.0) ? hscale * (star_x[i] - star_x[j])/(d*d*4.0) : 10.0;
				nudge[j].y -= (d != 0.0) ? vscale * (star_y[i] - star_y[j])/(d*d*4.0) : 10.0;
				
				[NSBezierPath strokeLineFromPoint:p1 toPoint:p2];
				
			}
		}
		
		[[NSColor lightGrayColor] set];
		[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
		[NSBezierPath setDefaultLineWidth:32.0];
		//draw connectivity map
		for (i = 0; i < 256; i++) for (j = i + 1; j < 256; j++)
		{
			double d = distanceBetweenPlanetPositions(star_x[i],star_y[i],star_x[j],star_y[j]);
			
			if (d <= 7.0)
			{
				NSPoint p1 = NSMakePoint(star_x[i] * hscale + hoffset,(256 - star_y[i]) * vscale + voffset);
				NSPoint p2 = NSMakePoint(star_x[j] * hscale + hoffset,(256 - star_y[j]) * vscale + voffset);
				
				[NSBezierPath strokeLineFromPoint:p1 toPoint:p2];
				
			}
		}
		
		[[NSColor whiteColor] set];
		[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
		[NSBezierPath setDefaultLineWidth:28.0];
		//draw connectivity map
		for (i = 0; i < 256; i++) for (j = i + 1; j < 256; j++)
		{
			double d = distanceBetweenPlanetPositions(star_x[i],star_y[i],star_x[j],star_y[j]);
			
			if (d <= 7.0)
			{
				NSPoint p1 = NSMakePoint(star_x[i] * hscale + hoffset,(256 - star_y[i]) * vscale + voffset);
				NSPoint p2 = NSMakePoint(star_x[j] * hscale + hoffset,(256 - star_y[j]) * vscale + voffset);
				
				[NSBezierPath strokeLineFromPoint:p1 toPoint:p2];
				
			}
		}
		
		[[NSColor yellowColor] set];
		[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
		[NSBezierPath setDefaultLineWidth:4.0];
		//draw connectivity map
		for (i = 0; i < 256; i++) for (j = i + 1; j < 256; j++)
		{
			double d = distanceBetweenPlanetPositions(star_x[i],star_y[i],star_x[j],star_y[j]);
			
			if (d <= 7.0)
			{
				NSPoint p1 = NSMakePoint(star_x[i] * hscale + hoffset,(256 - star_y[i]) * vscale + voffset);
				NSPoint p2 = NSMakePoint(star_x[j] * hscale + hoffset,(256 - star_y[j]) * vscale + voffset);
				
				[NSBezierPath strokeLineFromPoint:p1 toPoint:p2];
				
			}
		}
				
		g_seed = galaxy_seed;   // keep for sizing!
		for (i = 0; i < 256; i++)
		{
			double sz = ((g_seed.e | 0x50) < 0x90) ? 1.0 : 1.5;
			star.x = star_x[i] * hscale + hoffset;
			star.y = (256 - star_y[i]) * vscale + voffset;
			
			if (nudge[i].x*nudge[i].x > 100.0)
				nudge[i].x = (nudge[i].x < 0.0) ? -10.0 : 10.0;
			if (nudge[i].y*nudge[i].y > 100.0)
				nudge[i].y = (nudge[i].y < 0.0) ? -10.0 : 10.0;
			
			[[NSColor blackColor] set];
			[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(star.x - sz, star.y - sz, sz * 2.0, sz * 2.0)] fill];

			[[NSString  stringWithFormat:@"%d",i] drawAtPoint:NSMakePoint(star.x + 1.0 + nudge[i].x, star.y - 4.5 - nudge[i].y) withAttributes:textAttributes];

			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
			rotate_seed(&g_seed);
		}
		
		//
		[drawImage unlockFocus];
		// write to file
		[[drawImage TIFFRepresentation] writeToFile:pathToPic atomically:YES];
		//	
		[drawImage release];
		[NSBezierPath setDefaultLineCapStyle:NSRoundLineCapStyle];
		[NSBezierPath setDefaultLineWidth:1.0];
	}
	/* ends */
}


- (void) setGuiToShortRangeChartScreen
{
	NSString*   targetSystemName;
	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y); 
	
	if ((target_system_seed.d != cursor_coordinates.x)||(target_system_seed.b != cursor_coordinates.y))
		target_system_seed =	[universe findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	targetSystemName =		[[universe getSystemName:target_system_seed] retain];  // retained
	
	//NSLog(@"found %@ at (%d, %d)",targetSystemName,(int)cursor_coordinates.x,(int)cursor_coordinates.y);
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		if ((abs(cursor_coordinates.x-galaxy_coordinates.x)>=20)||(abs(cursor_coordinates.y-galaxy_coordinates.y)>=38))
			cursor_coordinates = galaxy_coordinates;	// home
		
		[gui clear];
		[gui setTitle:@"Short Range Chart"];
		//
		[gui setText:targetSystemName														forRow:19];
		[gui setText:[NSString stringWithFormat:@"Distance:\t%.1f Light Years", distance]   forRow:20];
		//
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	//NSLog(@"gui_screen = GUI_SCREEN_LONG_RANGE_CHART");
	
	gui_screen = GUI_SCREEN_SHORT_RANGE_CHART;
	
	[targetSystemName release]; // released

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) setGuiToLoadSaveScreen
{
	BOOL			canLoadOrSave = NO;
	MyOpenGLView	*gameView = [universe gameView];
	GameController	*controller = [universe gameController];
	
	if (status == STATUS_DOCKED)
	{
		if (!docked_station)
			docked_station = [universe station];
		canLoadOrSave = (docked_station == [universe station]);
	}
	
	BOOL canQuickSave = (canLoadOrSave && ([[gameView gameController] playerFileToLoad] != nil));
	int displayModeIndex = [controller indexOfCurrentDisplayMode];
	if (displayModeIndex == NSNotFound)
	{
		NSLog(@"***** couldn't find current display mode switching to basic 640x480");
		displayModeIndex = 0;
	}
	
	// oolite-linux:
	// Check that there are display modes listed before trying to
	// get them or an exception occurs.
	NSArray			*modeList;
	NSDictionary	*mode = nil;
	
	modeList = [controller displayModes];
	if ([modeList count])
	{
		mode = [modeList objectAtIndex:displayModeIndex];
	}
	int modeWidth = [[mode objectForKey: (NSString *)kCGDisplayWidth] intValue];
	int modeHeight = [[mode objectForKey: (NSString *)kCGDisplayHeight] intValue];
	float modeRefresh = [[mode objectForKey: (NSString *)kCGDisplayRefreshRate] doubleValue];
	
	NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		int first_sel_row = (canLoadOrSave)? GUI_ROW_OPTIONS_SAVE : GUI_ROW_OPTIONS_DISPLAY;
		if (canQuickSave)
			first_sel_row = GUI_ROW_OPTIONS_QUICKSAVE;
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Commander %@",   player_name]];
		//
		if (canQuickSave)
		{
			[gui setText:@" Quick-Save " forRow:GUI_ROW_OPTIONS_QUICKSAVE align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_QUICKSAVE];
		}
		//
		[gui setText:@" Save Commander " forRow:GUI_ROW_OPTIONS_SAVE align:GUI_ALIGN_CENTER];
		[gui setText:@" Load Commander " forRow:GUI_ROW_OPTIONS_LOAD align:GUI_ALIGN_CENTER];
		if (canLoadOrSave)
		{
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_SAVE];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_LOAD];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_SAVE];
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_LOAD];
		}
		//
		[gui setText:@" Begin New Game " forRow:GUI_ROW_OPTIONS_BEGIN_NEW align:GUI_ALIGN_CENTER];
		if (![[universe gameController] game_is_paused])
		{
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_BEGIN_NEW];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_BEGIN_NEW];
		}
		//
		[gui setText:@"Game Options:" forRow:GUI_ROW_OPTIONS_OPTIONS align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_OPTIONS];
		//
		[gui setText:displayModeString forRow:GUI_ROW_OPTIONS_DISPLAY align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_DISPLAY];
		
		// volume control
		if ([OOSound respondsToSelector:@selector(masterVolume)])
		{
			int volume = 20 * [OOSound masterVolume];
			NSString* v1_string = @"|||||||||||||||||||||||||";
			NSString* v0_string = @".........................";
			v1_string = [v1_string substringToIndex:volume];
			v0_string = [v0_string substringToIndex:20 - volume];
			if (volume > 0)
				[gui setText:[NSString stringWithFormat:@" Sound Volume: %@%@", v1_string, v0_string] forRow:GUI_ROW_OPTIONS_VOLUME align:GUI_ALIGN_CENTER];
			else
				[gui setText:@" Sound Volume: MUTE " forRow:GUI_ROW_OPTIONS_VOLUME align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_VOLUME];
		}
		else
		{
			[gui setText:@" Sound Volume: External Control Only" forRow:GUI_ROW_OPTIONS_VOLUME align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_VOLUME];
		}
		
#ifndef GNUSTEP
		// Growl priority control
		{
			NSUserDefaults* prefs = [NSUserDefaults standardUserDefaults];
			NSString* growl_priority_desc;
			int growl_min_priority = 3;
			if ([prefs objectForKey:@"groolite-min-priority"])
				growl_min_priority = [prefs integerForKey:@"groolite-min-priority"];
			if ((growl_min_priority < -2)||(growl_min_priority > 3))
			{
				growl_min_priority = 3;
				[prefs setInteger:3 forKey:@"groolite-min-priority"];
			}
			growl_priority_desc = [Groolite priorityDescription:growl_min_priority];
			[gui setText:[NSString stringWithFormat:@" Show Growl messages: %@ ", growl_priority_desc] forRow:GUI_ROW_OPTIONS_GROWL align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_GROWL];
		}
		
		// Speech control
		if (speech_on)
			[gui setText:@" Spoken messages: ON " forRow:GUI_ROW_OPTIONS_SPEECH align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Spoken messages: OFF " forRow:GUI_ROW_OPTIONS_SPEECH align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_SPEECH];
		
		// iTunes integration control
		if (ootunes_on)
			[gui setText:@" iTunes integration: ON " forRow:GUI_ROW_OPTIONS_OOTUNES align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" iTunes integration: OFF " forRow:GUI_ROW_OPTIONS_OOTUNES align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_OOTUNES];

#else

		// GNUstep needs a quit option at present (no Cmd-Q) but
		// doesn't need speech.
		
		// quit menu option
		[gui setText:@" Exit game " forRow:GUI_ROW_OPTIONS_QUIT align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_QUIT];
		
		// window/fullscreen
		if([gameView inFullScreenMode])
		{
			[gui setText:@" Windowed mode " forRow:GUI_ROW_OPTIONS_DISPLAYSTYLE align:GUI_ALIGN_CENTER];
		}
		else
		{
			[gui setText:@" Fullscreen mode " forRow:GUI_ROW_OPTIONS_DISPLAYSTYLE align:GUI_ALIGN_CENTER];
		}
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_OPTIONS_DISPLAYSTYLE];
		
		[gui setText:@" Joystick setup" forRow: GUI_ROW_OPTIONS_STICKMAPPER align: GUI_ALIGN_CENTER];
		if ([[gameView getStickHandler] getNumSticks])
		{
			// TODO: Modify input code to put this in a better place
			stickHandler=[gameView getStickHandler];
			numSticks=[stickHandler getNumSticks];
			// end TODO
			
			[gui setKey: GUI_KEY_OK forRow: GUI_ROW_OPTIONS_STICKMAPPER];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_STICKMAPPER];
		}
#endif
		
		if ([universe reducedDetail])
			[gui setText:@" Reduced detail: ON " forRow:GUI_ROW_OPTIONS_DETAIL align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Reduced detail: OFF " forRow:GUI_ROW_OPTIONS_DETAIL align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_DETAIL];
		//
		if ([universe strict])
			[gui setText:@" Reset to unrestricted play. " forRow:GUI_ROW_OPTIONS_STRICT align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Reset to strict gameplay. " forRow:GUI_ROW_OPTIONS_STRICT align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_STRICT];
		
		//
		[gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_OPTIONS_END_OF_LIST - first_sel_row)];
		[gui setSelectedRow: first_sel_row];
		//
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	//NSLog(@"gui_screen = GUI_SCREEN_OPTIONS");
	
	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_OPTIONS;
	
	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_DOCKED];
}

static int last_outfitting_index;

- (void) setGuiToEquipShipScreen:(int) skip :(int) itemForSelectFacing
{
	missiles = [self calc_missiles];
	
//	NSLog(@"DEBUG EquipShipScreen missiles = %d", missiles);
	
	// if skip < 0 then use the last recorded index
	if (skip < 0)
	{
		if (last_outfitting_index >= 0)
			skip = last_outfitting_index;
		else
			skip = 0;
	}
	last_outfitting_index = skip;
	
	NSArray*	equipdata = [universe equipmentdata];
	
	int cargo_space = max_cargo - current_cargo;
	
	double price_factor = 1.0;
	int techlevel =		[(NSNumber *)[[universe generateSystemData:system_seed] objectForKey:KEY_TECHLEVEL] intValue];

	if (docked_station)
	{
		price_factor = [docked_station equipment_price_factor];
		if ([docked_station equivalent_tech_level] != NSNotFound)
			techlevel = [docked_station equivalent_tech_level];
	}
	
	// build an array of all equipment - and take away that which has been bought (or is not permitted)
	NSMutableArray* equipment_allowed = [NSMutableArray arrayWithCapacity:120];
	//	
	// find options that agree with this ship
	BOOL		option_okay[[equipdata count]];
	NSMutableArray*	options = [NSMutableArray arrayWithArray:(NSArray*)[(NSDictionary*)[[universe shipyard] objectForKey:ship_desc] objectForKey:KEY_OPTIONAL_EQUIPMENT]];
//	[options addObject:@"EQ_FUEL"];
//	[options addObject:@"EQ_PASSENGER_BERTH"];
//	[options addObject:@"EQ_PASSENGER_BERTH_REMOVAL"];
//	[options addObject:@"EQ_ADVANCED_COMPASS"];	// available to all ships
//	[options addObject:@"EQ_GAL_DRIVE"];	// available to all ships
//	[options addObject:@"EQ_MISSILE_REMOVAL"];	// available to all ships
	int i,j;
	for (i = 0; i < [equipdata count]; i++)
	{
		NSString*	eq_key = (NSString*)[(NSArray*)[equipdata objectAtIndex:i] objectAtIndex:EQUIPMENT_KEY_INDEX];
		NSString*	eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
		int			min_techlevel   = [(NSNumber *)[(NSArray *)[equipdata objectAtIndex:i] objectAtIndex:EQUIPMENT_TECH_LEVEL_INDEX] intValue];
		NSMutableDictionary*	eq_extra_info_dict = [NSMutableDictionary dictionary];
		if ([(NSArray *)[equipdata objectAtIndex:i] count] > 5)
			[eq_extra_info_dict addEntriesFromDictionary:(NSDictionary *)[(NSArray *)[equipdata objectAtIndex:i] objectAtIndex:EQUIPMENT_EXTRA_INFO_INDEX]];
		
		// set initial availability to NO
		option_okay[i] = NO;
		
		// check special availability
		if ([eq_extra_info_dict objectForKey:@"available_to_all"])
			[options addObject: eq_key];
		
		// check if this is a mission special ..
		if (min_techlevel == 99)
		{
			// check mission variables for the existence of a revised tech level (given when item is awarded)
			NSString* mission_eq_tl_key = [NSString stringWithFormat:@"mission_TL_FOR_%@", eq_key];
			if ([mission_variables objectForKey:mission_eq_tl_key])
				min_techlevel = [[mission_variables objectForKey:mission_eq_tl_key] intValue];
		}
		
		// if you have a dmaged system you can get it repaired at a tech level one less than that required to buy it
		if ([self has_extra_equipment:eq_key_damaged])
			min_techlevel--;

		// reduce the minimum techlevel occasionally as a bonus..
		//
		if ((![universe strict])&&(techlevel < min_techlevel)&&(techlevel > min_techlevel - 3))
		{
			int day = i * 13 + floor([universe getTime] / 86400.0);
			unsigned char day_rnd = (day & 0xff) ^ system_seed.a;
			int original_min_techlevel = min_techlevel;
			//
			while ((min_techlevel > 0)&&(min_techlevel > original_min_techlevel - 3)&&!(day_rnd & 7))	// bargain tech days every 1/8 days
			{
				day_rnd = day_rnd >> 2;
				min_techlevel--;	// occasional bonus items according to TL
			}
		}
		
		// check initial availability against options
		for (j = 0; j < [options count]; j++)
		{
			if ([eq_key isEqual:[options objectAtIndex:j]])
			{
				option_okay[i] = YES;
				[options removeObjectAtIndex:j];
				j = [options count];
			}
		}
		//
		// check usual requirements
		if (([eq_key isEqual:@"EQ_FUEL"])&&(fuel >= 70))	// check if fuel space free
			option_okay[i] &= NO;
		if (([eq_key hasSuffix:@"MISSILE"]||[eq_key hasSuffix:@"MINE"]))	// check if pylon is free
			option_okay[i] &= (missiles < max_missiles);
		if ([eq_key isEqual:@"EQ_MISSILE_REMOVAL"])
			option_okay[i] &= (missiles > 0);
		if (([eq_key isEqual:@"EQ_PASSENGER_BERTH"])&&(cargo_space < 5))
			option_okay[i] &= NO;
		if (([eq_key isEqual:@"EQ_PASSENGER_BERTH_REMOVAL"])&&(max_passengers - [passengers count] < 1))
			option_okay[i] &= NO;
		if ([self has_extra_equipment:eq_key])
			option_okay[i] &= NO;
		if ([eq_key isEqual:@"EQ_ENERGY_UNIT"]&&[self has_extra_equipment:@"EQ_NAVAL_ENERGY_UNIT"])
			option_okay[i] &= NO;
		if (techlevel < min_techlevel)
			option_okay[i] &= NO;
		//
		// check special requirements
		if ([eq_extra_info_dict objectForKey:@"requires_empty_pylon"])
			option_okay[i] &= (missiles < max_missiles);
		if ([eq_extra_info_dict objectForKey:@"requires_mounted_pylon"])
			option_okay[i] &= (missiles > 0);
		if ([eq_extra_info_dict objectForKey:@"requires_equipment"])
			option_okay[i] &= [self has_extra_equipment:(NSString*)[eq_extra_info_dict objectForKey:@"requires_equipment"]];
		if ([eq_extra_info_dict objectForKey:@"requires_cargo_space"])
			option_okay[i] &= (cargo_space >= [[eq_extra_info_dict objectForKey:@"requires_cargo_space"] intValue]);
		if ([eq_extra_info_dict objectForKey:@"requires_clean"])
			option_okay[i] &= ([self legal_status] == 0);
		if ([eq_extra_info_dict objectForKey:@"requires_not_clean"])
			option_okay[i] &= ([self legal_status] != 0);
			
		if ([eq_key isEqual:@"EQ_RENOVATION"])
		{
//			NSLog(@"DEBUG : ship trade in factor is %d%", ship_trade_in_factor);
			option_okay[i] &= ((75 <= ship_trade_in_factor)&&(ship_trade_in_factor < 85));
		}
		
		if (option_okay[i])
			[equipment_allowed addObject: [NSNumber numberWithInt:i]];
			
		if (i == itemForSelectFacing)
		{
			skip = [equipment_allowed count] - 1;	// skip to this upgrade
			int available_facings = [(NSNumber*)[(NSDictionary*)[[universe shipyard] objectForKey:ship_desc] objectForKey:KEY_WEAPON_FACINGS] intValue];
			if (available_facings & WEAPON_FACING_FORWARD)
				[equipment_allowed addObject: [NSNumber numberWithInt:i]];
			if (available_facings & WEAPON_FACING_AFT)
				[equipment_allowed addObject: [NSNumber numberWithInt:i]];
			if (available_facings & WEAPON_FACING_PORT)
				[equipment_allowed addObject: [NSNumber numberWithInt:i]];
			if (available_facings & WEAPON_FACING_STARBOARD)
				[equipment_allowed addObject: [NSNumber numberWithInt:i]];
		}
	}
		
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		int start_row =		GUI_ROW_EQUIPMENT_START;
		int row = start_row;
		int i;
		int tab_stops[GUI_MAX_COLUMNS];
		int facing_count = 0;
		
		[gui clear];
		[gui setTitle:@"Ship Outfitting"];
		//
		[gui setText:[NSString stringWithFormat:@"Cash:\t%.1f Cr.", 0.1*credits]  forRow: GUI_ROW_EQUIPMENT_CASH];
		//
		tab_stops[0] = 0;
		tab_stops[1] = 320;
		//
		[gui setTabStops:tab_stops];
		//
		int n_rows = GUI_MAX_ROWS_EQUIPMENT;
		//
		if ([equipment_allowed count] > 0)
		{ 
			// double check for sound values of skip
			if ((skip < 0)||(skip >= [equipment_allowed count]))
				skip = 0;
			//
			if (skip > 0)	// lose the first row to Back <--
			{
				int	previous = skip - n_rows;
				if (previous < 0)	previous = 0;
				if (itemForSelectFacing >= 0)
					previous = -1;	// ie. last index!
				[gui setColor:[OOColor greenColor] forRow:row];
				[gui setArray:[NSArray arrayWithObjects:@" Back ", @" <-- ", nil] forRow:row];
				[gui setKey:[NSString stringWithFormat:@"More:%d", previous] forRow:row];
				row++;
			}
			for (i = skip; (i < [equipment_allowed count])&&(row - start_row < n_rows - 1); i++)
			{
				int			item   = [(NSNumber *)[equipment_allowed objectAtIndex:i] intValue];

				int			price_per_unit  = [(NSNumber *)[(NSArray *)[equipdata objectAtIndex:item] objectAtIndex:EQUIPMENT_PRICE_INDEX] intValue];
				NSString*   desc			= [NSString stringWithFormat:@" %@ ",[(NSArray *)[equipdata objectAtIndex:item] objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX]];
				NSString*   eq_key			= (NSString *)[(NSArray *)[equipdata objectAtIndex:item] objectAtIndex:EQUIPMENT_KEY_INDEX];
				double		price			= ([eq_key isEqual:@"EQ_FUEL"]) ? ((70 - fuel) * price_per_unit) : (price_per_unit) ;
				NSString*	eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];

				if ([eq_key isEqual:@"EQ_RENOVATION"])
				{
					price = cunningFee(0.1 * [universe tradeInValueForCommanderDictionary:[self commanderDataDictionary]]);
				}
				
				price *= price_factor;  // increased prices at some stations
				
				// color repairs and renovation items orange
				//
				if ([self has_extra_equipment:eq_key_damaged])
				{
					desc = [NSString stringWithFormat:@" Repair:%@", desc];
					price /= 2.0;
					[gui setColor:[OOColor orangeColor] forRow:row];
				}
				if ([eq_key isEqual:@"EQ_RENOVATION"])
					[gui setColor:[OOColor orangeColor] forRow:row];
				
				NSString*	priceString		= [NSString stringWithFormat:@" %.1f ",0.1*price];

				if (item == itemForSelectFacing)
				{
					if (facing_count == 0)
						priceString = @"";
					if (facing_count == 1)
						desc = FORWARD_FACING_STRING;
					if (facing_count == 1)
						desc = FORWARD_FACING_STRING;
					if (facing_count == 2)
						desc = AFT_FACING_STRING;
					if (facing_count == 3)
						desc = PORT_FACING_STRING;
					if (facing_count == 4)
						desc = STARBOARD_FACING_STRING;
					facing_count++;
					[gui setColor:[OOColor greenColor] forRow:row];
				}
				[gui setKey:[NSString stringWithFormat:@"%d",item] forRow:row];			// save the index of the item as the key for the row
				[gui setArray:[NSArray arrayWithObjects:desc, priceString, nil] forRow:row];
				row++;
			}
			if (i < [equipment_allowed count])
			{
				[gui setColor:[OOColor greenColor] forRow:row];
				[gui setArray:[NSArray arrayWithObjects:@" More ", @" --> ", nil] forRow:row];
				[gui setKey:[NSString stringWithFormat:@"More:%d", i] forRow:row];
				row++;
			}
			//
			[gui setSelectableRange:NSMakeRange(start_row,row - start_row)];

			if ([gui selectedRow] < start_row)
				[gui setSelectedRow:start_row];

			if (itemForSelectFacing >= 0)
				[gui setSelectedRow:start_row + ((skip > 0)? 1: 0)];

			[self showInformationForSelectedUpgrade];
			//
		}
		else
		{
			[gui setText:@"No equipment available for purchase." forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_NO_SHIPS];
			//
			[gui setSelectableRange:NSMakeRange(0,0)];
			[gui setNoSelectedRow];
			[self showInformationForSelectedUpgrade];
		}
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
		
	chosen_weapon_facing = WEAPON_FACING_NONE;
	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_EQUIP_SHIP;
	
	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) showInformationForSelectedUpgrade
{
	GuiDisplayGen* gui = [universe gui];
	NSString* key = [gui selectedRowKey];
	int i;
	for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++)
	{
		[gui setText:@"" forRow:i];
		[gui setColor:[OOColor greenColor] forRow:i];
	}
	if (key)
	{
		if (![key hasPrefix:@"More:"])
		{
			int item = [key intValue];
			NSString*   desc = (NSString *)[(NSArray *)[[universe equipmentdata] objectAtIndex:item] objectAtIndex:EQUIPMENT_LONG_DESC_INDEX];
			NSString*   eq_key			= (NSString *)[(NSArray *)[[universe equipmentdata] objectAtIndex:item] objectAtIndex:EQUIPMENT_KEY_INDEX];
			NSString*	eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
			if ([self has_extra_equipment:eq_key_damaged])
				desc = [NSString stringWithFormat:@"%@ (Price is for repairing the existing system).", desc];
			[gui addLongText:desc startingAtRow:GUI_ROW_EQUIPMENT_DETAIL align:GUI_ALIGN_LEFT];
		}
	}
}

- (void) setGuiToIntro1Screen
{
	GuiDisplayGen* gui = [universe gui];

	// GUI stuff
	{
		int ms_line = 2;
		
		[gui clear];
		[gui setTitle:@"Oolite"];
		//
		[gui setText:@"by Giles Williams (C) 2003-2005" forRow:17 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor whiteColor] forRow:17];
		//
		[gui setText:@"Oolite Theme Music by No Sleep (C) 2004" forRow:19 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor grayColor] forRow:19];
		//
		[gui setText:@"Load Previous Commander (Y/N)?" forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor yellowColor] forRow:21];
		
		//
		// check for error messages from Resource Manager
		//
		if (([ResourceManager pathsUsingAddOns:YES])&&([ResourceManager errors]))
		{
			int ms_start = ms_line;
			int i = ms_line = [gui addLongText:[ResourceManager errors] startingAtRow:ms_start align:GUI_ALIGN_LEFT];
			for (i-- ; i >= ms_start ; i--) [gui setColor:[OOColor redColor] forRow:i];
			ms_line++;
		}
		
		//NSLog(@"<<<<< DEBUG1");
		
		//
		// check for messages from the command line
		//
		NSArray* arguments = [[NSProcessInfo processInfo] arguments];
		//NSLog(@"DEBUG arguments:\n%@",[arguments description]);
		int i;
		for (i = 0; i < [arguments count]; i++)
		{
			if (([[arguments objectAtIndex:i] isEqual:@"-message"])&&(i < [arguments count] - 1))
			{
				int ms_start = ms_line;
				NSString* message = (NSString*)[arguments objectAtIndex: i + 1];
				int i = ms_line = [gui addLongText:message startingAtRow:ms_start align:GUI_ALIGN_CENTER];
				for (i-- ; i >= ms_start; i--) [gui setColor:[OOColor magentaColor] forRow:i];
			}
			if ([[arguments objectAtIndex:i] isEqual:@"-showversion"])
			{
				int ms_start = ms_line;
				NSString *version = [NSString stringWithFormat:@"Version %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
				int i = ms_line = [gui addLongText:version startingAtRow:ms_start align:GUI_ALIGN_CENTER];
				for (i-- ; i >= ms_start; i--) [gui setColor:[OOColor magentaColor] forRow:i];
			}
		}
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	//NSLog(@"<<<<< DEBUG2");

	[universe set_up_intro1];
		
	if (gui)
		gui_screen = GUI_SCREEN_INTRO1;
		
	if (themeMusic)
	{
		[themeMusic play];
	}

	
	[self setShowDemoShips: YES];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) setGuiToIntro2Screen
{
	GuiDisplayGen* gui = [universe gui];

	// GUI stuff
	{
		[gui clear];
		[gui setTitle:@"Oolite"];
		//
		[gui setText:@"Press Space Commander" forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor yellowColor] forRow:21];
		//
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	[universe set_up_intro2];
		
	if (gui)
		gui_screen = GUI_SCREEN_INTRO2;

	[self setShowDemoShips: YES];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) buySelectedItem
{
	GuiDisplayGen* gui = [universe gui];
	NSString* key = [gui selectedRowKey];
	
	if ([key hasPrefix:@"More:"])
	{		
		int from_item = [(NSString*)[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];

		[self setGuiToEquipShipScreen:from_item:-1];
		if ([gui selectedRow] < 0)
			[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
		if (from_item == 0)
			[gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
		return;
	}
	//
	int item = [key intValue];
	NSString	*item_text = [gui selectedRowText];
	if ([item_text isEqual:FORWARD_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_FORWARD;
	if ([item_text isEqual:AFT_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_AFT;
	if ([item_text isEqual:PORT_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_PORT;
	if ([item_text isEqual:STARBOARD_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_STARBOARD;
	//NSLog(@"Try Buying Item %d",item);
	int old_credits = credits;
	if ([self tryBuyingItem:item])
	{
		if (credits == old_credits)
		{
			[[universe gui] click];
		}
		else
		{
			[self playInterfaceBeep:kInterfaceBeep_Buy];
			//
			// wind the clock forward by 10 minutes plus 10 minutes for every 60 credits spent
			//
			double time_adjust = (old_credits > credits)? (old_credits - credits): 0.0;
			ship_clock_adjust += time_adjust + 600.0;
		}
	}
	else
	{
		[self boop];
	}
}

- (BOOL) tryBuyingItem:(int) index
{
	// note this doesn't check the availability by tech-level
	//
	NSArray*	equipdata = [universe equipmentdata];
	int			price_per_unit  = [(NSNumber *)[(NSArray *)[equipdata objectAtIndex:index] objectAtIndex:EQUIPMENT_PRICE_INDEX] intValue];
	NSString*   eq_key			= (NSString *)[(NSArray *)[equipdata objectAtIndex:index] objectAtIndex:EQUIPMENT_KEY_INDEX];
	NSString*	eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
	double		price			= ([eq_key isEqual:@"EQ_FUEL"]) ? ((70 - fuel) * price_per_unit) : (price_per_unit) ;
	double		price_factor	= 1.0;
	int			cargo_space = max_cargo - current_cargo;

	// repairs cost 50%
	if ([self has_extra_equipment:eq_key_damaged])
	{
		price /= 2.0;
	}

	if ([eq_key isEqual:@"EQ_RENOVATION"])
	{
		price = cunningFee(0.1 * [universe tradeInValueForCommanderDictionary:[self commanderDataDictionary]]);
	}
				
	if (docked_station)
	{
		price_factor = [docked_station equipment_price_factor];
	}
	
	price *= price_factor;  // increased prices at some stations
	
	if (price > credits)
	{
		return NO;
	}
	
	if (([eq_key hasPrefix:@"EQ_WEAPON"])&&(chosen_weapon_facing == WEAPON_FACING_NONE))
	{
		[self setGuiToEquipShipScreen:-1:index];											// reset
		return YES;
	}

	if (([eq_key hasPrefix:@"EQ_WEAPON"])&&(chosen_weapon_facing != WEAPON_FACING_NONE))
	{
		int chosen_weapon = WEAPON_NONE;
		int current_weapon = WEAPON_NONE;
		
		if ([eq_key isEqual:@"EQ_WEAPON_TWIN_PLASMA_CANNON"])
			chosen_weapon = WEAPON_PLASMA_CANNON;
		if ([eq_key isEqual:@"EQ_WEAPON_PULSE_LASER"])
			chosen_weapon = WEAPON_PULSE_LASER;
		if ([eq_key isEqual:@"EQ_WEAPON_BEAM_LASER"])
			chosen_weapon = WEAPON_BEAM_LASER;
		if ([eq_key isEqual:@"EQ_WEAPON_MINING_LASER"])
			chosen_weapon = WEAPON_MINING_LASER;
		if ([eq_key isEqual:@"EQ_WEAPON_MILITARY_LASER"])
			chosen_weapon = WEAPON_MILITARY_LASER;
		if ([eq_key isEqual:@"EQ_WEAPON_THARGOID_LASER"])
			chosen_weapon = WEAPON_THARGOID_LASER;
			
		switch (chosen_weapon_facing)
		{
			case WEAPON_FACING_FORWARD :
				current_weapon = forward_weapon;
				forward_weapon = chosen_weapon;
				break;
			case WEAPON_FACING_AFT :
				current_weapon = aft_weapon;
				aft_weapon = chosen_weapon;
				break;
			case WEAPON_FACING_PORT :
				current_weapon = port_weapon;
				port_weapon = chosen_weapon;
				break;
			case WEAPON_FACING_STARBOARD :
				current_weapon = starboard_weapon;
				starboard_weapon = chosen_weapon;
				break;
		}
		
		credits -= price;
		
		// refund here for current_weapon;
		switch (current_weapon)
		{
			case WEAPON_PLASMA_CANNON :
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_WEAPON_TWIN_PLASMA_CANNON"];
				break;
			case WEAPON_PULSE_LASER :
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_WEAPON_PULSE_LASER"];
				break;
			case WEAPON_BEAM_LASER :
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_WEAPON_BEAM_LASER"];
				break;
			case WEAPON_MINING_LASER :
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_WEAPON_MINING_LASER"];
				break;
			case WEAPON_MILITARY_LASER :
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_WEAPON_MILITARY_LASER"];
				break;
			case WEAPON_THARGOID_LASER :
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_WEAPON_THARGOID_LASER"];
				break;
			case WEAPON_NONE :
				break;
		}
			
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
	
	if (([eq_key hasSuffix:@"MISSILE"]||[eq_key hasSuffix:@"MINE"])&&(missiles >= max_missiles))
		return NO;	

	if (([eq_key isEqual:@"EQ_PASSENGER_BERTH"])&&(cargo_space < 5))
		return NO;	

	if ([eq_key isEqual:@"EQ_FUEL"])
	{
		fuel = 70;
		credits -= price;
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
	
	// check energy unit replacement
	if ([eq_key hasSuffix:@"ENERGY_UNIT"]&&(energy_unit != ENERGY_UNIT_NONE))
	{
		switch (energy_unit)
		{
			case ENERGY_UNIT_NAVAL :
				[self removeEquipment:@"EQ_NAVAL_ENERGY_UNIT"];
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_NAVAL_ENERGY_UNIT"] / 2;	// 50 % refund
				break;
				
			case ENERGY_UNIT_NORMAL :
				[self removeEquipment:@"EQ_ENERGY_UNIT"];
				credits += [universe getPriceForWeaponSystemWithKey:@"EQ_ENERGY_UNIT"] * 3 / 4;	// 75 % refund
				break;
				
			case ENERGY_UNIT_NONE :
			default :
				break;
		}
	}
	
	// maintain ship
	if ([eq_key isEqual:@"EQ_RENOVATION"])
	{
		int techlevel =		[(NSNumber *)[[universe generateSystemData:system_seed] objectForKey:KEY_TECHLEVEL] intValue];
		if ((docked_station)&&([docked_station equivalent_tech_level] != NSNotFound))
			techlevel = [docked_station equivalent_tech_level];
		credits -= price;
		ship_trade_in_factor += 5 + techlevel;	// you get better value at high-tech repair bases
		if (ship_trade_in_factor > 100)
			ship_trade_in_factor = 100;
//		NSLog(@"DEBUG : Ship trade in value now %d\%", ship_trade_in_factor);
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
				
	if ([eq_key hasSuffix:@"MISSILE"]||[eq_key hasSuffix:@"MINE"])
	{
		ShipEntity* weapon = [[universe getShipWithRole:eq_key] autorelease];
		BOOL mounted_okay = [self mountMissile:weapon];
		if (mounted_okay)
		{
			credits -= price;
			[self safe_all_missiles];
			[self sort_missiles];
			[self select_next_missile];
		}
		[self setGuiToEquipShipScreen:-1:-1];
		return mounted_okay;
	}
		
	if ([eq_key isEqual:@"EQ_PASSENGER_BERTH"])
	{
		max_passengers++;
		max_cargo -= 5;
		credits -= price;
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
			
	if ([eq_key isEqual:@"EQ_PASSENGER_BERTH_REMOVAL"])
	{
		max_passengers--;
		max_cargo += 5;
		credits -= price;
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
			
	if ([eq_key isEqual:@"EQ_MISSILE_REMOVAL"])
	{
		credits -= price;
		[self safe_all_missiles];
		[self sort_missiles];
		int i;
		for (i = 0; i < missiles; i++)
		{
			ShipEntity* weapon = missile_entity[i];
			missile_entity[i] = nil;
			if (weapon)
			{
				NSString* weapon_key = [weapon roles];
				int weapon_value = [universe getPriceForWeaponSystemWithKey:weapon_key];
//				NSLog(@"..... selling a %@ worth %f", weapon_key, 0.1 * weapon_value);
				credits += weapon_value;
				[universe recycleOrDiscard: weapon];
				[weapon release];
			}
		}
		missiles = 0;
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
			
	int i;
	for (i =0; i < [equipdata count]; i++)
	{
		NSString *w_key = (NSString *)[(NSArray *)[equipdata objectAtIndex:i] objectAtIndex:EQUIPMENT_KEY_INDEX];
		if (([eq_key isEqual:w_key])&&(![self has_extra_equipment:eq_key]))
		{
			//NSLog(@"adding %@",eq_key);
			credits -= price;
			[self add_extra_equipment:eq_key];
			[self setGuiToEquipShipScreen:-1:-1];
			
			return YES;
		}
	}

	return NO;
}

- (void) setGuiToMarketScreen
{
	NSArray*			localMarket;
	
	if (status == STATUS_DOCKED)
	{
		if (docked_station == nil)
			docked_station = [universe station];
		if ([docked_station localMarket])
			localMarket = [docked_station localMarket];
		else
			localMarket = [docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
	else
	{
		if ([[universe station] localMarket])
			localMarket = [[universe station] localMarket];
		else
			localMarket = [[universe station] initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
		
//	NSLog(@"DEBUG local market = %@  [universe station] = %@", [localMarket description], [universe station]);
	// fix problems with economies in witch-space
	if (![universe station])
	{
		int i;
		NSMutableArray* ourEconomy = [NSMutableArray arrayWithArray:[universe commodityDataForEconomy:0 andStation:(StationEntity*)nil andRandomFactor:0]];
		for (i = 0; i < [ourEconomy count]; i++)
		{
			NSMutableArray *commodityInfo = [NSMutableArray arrayWithArray:[ourEconomy objectAtIndex:i]];
			[commodityInfo replaceObjectAtIndex:MARKET_PRICE withObject:[NSNumber numberWithInt: 0]];
			[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt: 0]];
			[ourEconomy replaceObjectAtIndex:i withObject:[NSArray arrayWithArray:commodityInfo]];
		}
		localMarket = [NSArray arrayWithArray:ourEconomy];
	}
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		int start_row =		GUI_ROW_MARKET_START;
		int row = start_row;
		int i;
		int tab_stops[GUI_MAX_COLUMNS]; 
		int n_commodities = [shipCommodityData count];
		int in_hold[n_commodities];
		
		// following changed to work whether docked or not
		//
		for (i = 0; i < n_commodities; i++)
			in_hold[i] = [(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		for (i = 0; i < [cargo count]; i++)
		{
			ShipEntity *container = (ShipEntity *)[cargo objectAtIndex:i];
			in_hold[[container getCommodityType]] += [container getCommodityAmount];
		}
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"%@ Commodity Market",[universe getSystemName:system_seed]]];
		//
		tab_stops[0] = 0;
		tab_stops[1] = 192;
		tab_stops[2] = 288;
		tab_stops[3] = 384;
		//
		[gui setTabStops:tab_stops];
		//
		[gui setColor:[OOColor greenColor] forRow:GUI_ROW_MARKET_KEY];
		[gui setArray:[NSArray arrayWithObjects: @"Commodity:", @"Price:", @"For sale:", @"In hold:", nil] forRow:GUI_ROW_MARKET_KEY];
		//
		current_cargo = 0;  // for calculating remaining hold space
		//
		for (i = 0; i < n_commodities; i++)
		{
			NSString* desc = [NSString stringWithFormat:@" %@ ",(NSString *)[(NSArray *)[localMarket objectAtIndex:i] objectAtIndex:MARKET_NAME]];
			int available_units = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
			int units_in_hold = in_hold[i];
			int price_per_unit = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:i] objectAtIndex:MARKET_PRICE] intValue];
			int unit = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:i] objectAtIndex:MARKET_UNITS] intValue];
			NSString* available = (available_units > 0) ? [NSString stringWithFormat:@"%d",available_units] : @"-";
			NSString* price = [NSString stringWithFormat:@" %.1f ",0.1*price_per_unit];
			NSString* owned = (units_in_hold > 0) ? [NSString stringWithFormat:@"%d",units_in_hold] : @"-";
			NSString* units = @"t";
			if (unit == UNITS_KILOGRAMS)  units = @"kg";
			if (unit == UNITS_GRAMS)  units = @"g"; 
			NSString* units_available = [NSString stringWithFormat:@" %@ %@ ",available,units];
			NSString* units_owned = [NSString stringWithFormat:@" %@ %@ ",owned,units];
			
			if (unit == UNITS_TONS)
				current_cargo += units_in_hold;
			
			[gui setKey:[NSString stringWithFormat:@"%d",i] forRow:row];
			[gui setArray:[NSArray arrayWithObjects: desc, price, units_available, units_owned, nil] forRow:row++];
		}
		//
		if ([cargo count] > 0)
			current_cargo = ([cargo count] <= max_cargo) ? [cargo count] : max_cargo;  // actually count the containers and things (may be > max_cargo)
		//
		[gui setText:[NSString stringWithFormat:@"Cash:\t%.1f Cr.\t\tLoad %d of %d t.", 0.1*credits, current_cargo, max_cargo]  forRow: GUI_ROW_MARKET_CASH];
		//
		if (status == STATUS_DOCKED)	// can only buy or sell in dock
		{
			[gui setSelectableRange:NSMakeRange(start_row,row - start_row)];
			if (([gui selectedRow] < start_row)||([gui selectedRow] >=row))
				[gui setSelectedRow:start_row];
		}
		else
		{
			[gui setNoSelectedRow];
		}
		//
		
		[gui setShowTextCursor:NO];
	}
	
	gui_screen = GUI_SCREEN_MARKET;

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: (status == STATUS_DOCKED)];
	[universe setViewDirection: VIEW_DOCKED];
}

- (int) gui_screen
{
	return gui_screen;
}

- (BOOL) marketFlooded:(int) index
{
	NSMutableArray*			localMarket;
	if (docked_station == nil)
		docked_station = [universe station];
	if ([docked_station localMarket])
		localMarket = [docked_station localMarket];
	else
		localMarket = [docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	NSArray *commodityArray = (NSArray *)[localMarket objectAtIndex:index];
	int available_units =   [(NSNumber *)[commodityArray objectAtIndex:MARKET_QUANTITY] intValue];
	return (available_units >= 127);
}

- (BOOL) tryBuyingCommodity:(int) index
{
	NSMutableArray*			localMarket;
	if (status == STATUS_DOCKED)
	{
		if (docked_station == nil)
			docked_station = [universe station];
		if ([docked_station localMarket])
			localMarket = [docked_station localMarket];
		else
			localMarket = [docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
	else
	{
		return NO; // can't buy if not docked
	}
	
	NSArray *commodityArray = (NSArray *)[localMarket objectAtIndex:index];
	int available_units =   [(NSNumber *)[commodityArray objectAtIndex:MARKET_QUANTITY] intValue];
	int price_per_unit =	[(NSNumber *)[commodityArray objectAtIndex:MARKET_PRICE] intValue];
	int unit =				[(NSNumber *)[commodityArray objectAtIndex:MARKET_UNITS] intValue];

	if ((specialCargo != nil)&&(unit == 0))
		return NO;									// can't buy tons of stuff when carrying a specialCargo
	
	if ((available_units == 0)||(price_per_unit > credits)||((unit == 0)&&(current_cargo >= max_cargo)))		return NO;
	{
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:index]];
		NSMutableArray* market_commodity =		[NSMutableArray arrayWithArray:(NSArray *)[localMarket objectAtIndex:index]];
		int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		int market_quantity =   [(NSNumber *)[market_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		manifest_quantity++;
		market_quantity--;
		credits -= price_per_unit;
		if (unit == UNITS_TONS)
			current_cargo++;
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[market_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:market_quantity]];
		[manifest replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:manifest_commodity]];
		[localMarket replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:market_commodity]];

		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	}
	return YES;
}

- (BOOL) trySellingCommodity:(int) index
{
	NSMutableArray*			localMarket;
	if (status == STATUS_DOCKED)
	{
		if (docked_station == nil)
			docked_station = [universe station];
		if ([docked_station localMarket])
			localMarket = [docked_station localMarket];
		else
			localMarket = [docked_station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
	else
	{
		return NO; // can't sell if not docked
	}
	int available_units = [(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:index] objectAtIndex:MARKET_QUANTITY] intValue];
	int price_per_unit = [(NSNumber *)[(NSArray *)[localMarket objectAtIndex:index] objectAtIndex:MARKET_PRICE] intValue];
	if (available_units == 0)		return NO;
	{
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:index]];
		NSMutableArray* market_commodity =		[NSMutableArray arrayWithArray:(NSArray *)[localMarket objectAtIndex:index]];
		int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		int market_quantity =   [(NSNumber *)[market_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		// check the market's not flooded
		if (market_quantity >= 127)
			return NO;
		manifest_quantity--;
		market_quantity++;
		credits += price_per_unit;
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[market_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:market_quantity]];
		[manifest replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:manifest_commodity]];
		[localMarket replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:market_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	}
	return YES;
}

- (BOOL) isMining
{
	return using_mining_laser;
}

- (BOOL) speech_on
{
	return speech_on;
}

// new extra equipment routines
- (BOOL) has_extra_equipment:(NSString *) eq_key
{
	if ([extra_equipment objectForKey:eq_key])
		return YES;
	else
		return NO;
}

- (void) add_extra_equipment:(NSString *) eq_key
{
	// if we've got a damaged one of these - remove it first
	NSString* damaged_eq_key = [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
	if ([extra_equipment objectForKey:damaged_eq_key])
		[extra_equipment removeObjectForKey:damaged_eq_key];
	//
	// deal with trumbles..
	if ([eq_key isEqual:@"EQ_TRUMBLE"] && (n_trumbles < 1))
	{
		[self addTrumble:trumble[ranrot_rand() % PLAYER_MAX_TRUMBLES]];	// first one!
		return;
	}
	//
	// add the equipment and set the necessary flags and data accordingly
	[extra_equipment setObject:[NSNumber numberWithBool:YES] forKey:eq_key];
	[self set_flags_from_extra_equipment];
}

- (void) remove_extra_equipment:(NSString *) eq_key
{
	if ([extra_equipment objectForKey:eq_key])
		[extra_equipment removeObjectForKey:eq_key];
	[self set_flags_from_extra_equipment];
}

- (void) set_extra_equipment_from_flags
{
	int original_hold_size = [universe maxCargoForShip:ship_desc];
	//
	if (max_cargo > original_hold_size)
		[self add_extra_equipment:@"EQ_CARGO_BAY"];
	if (has_escape_pod)
		[self add_extra_equipment:@"EQ_ESCAPE_POD"];
	if (has_scoop)
		[self add_extra_equipment:@"EQ_FUEL_SCOOPS"];
	if (has_fuel_injection)
		[self add_extra_equipment:@"EQ_FUEL_INJECTION"];
	if (has_ecm)
		[self add_extra_equipment:@"EQ_ECM"];
	if (has_energy_bomb)
		[self add_extra_equipment:@"EQ_ENERGY_BOMB"];
	if (has_energy_unit)
	{
		switch (energy_unit)
		{
			case ENERGY_UNIT_NORMAL :
				[self add_extra_equipment:@"EQ_ENERGY_UNIT"];
				break;
			case ENERGY_UNIT_NAVAL :
				[self add_extra_equipment:@"EQ_NAVAL_ENERGY_UNIT"];
				break;
		}
	}
	if (has_docking_computer)
		[self add_extra_equipment:@"EQ_DOCK_COMP"];
	if (has_galactic_hyperdrive)
		[self add_extra_equipment:@"EQ_GAL_DRIVE"];
	
	if (shield_booster > 1)
		[self add_extra_equipment:@"EQ_SHIELD_BOOSTER"];
	if (shield_enhancer)
		[self add_extra_equipment:@"EQ_NAVAL_SHIELD_BOOSTER"];
}

- (void) set_flags_from_extra_equipment
{
	int original_hold_size = [universe maxCargoForShip:ship_desc];
	//
	if ([shipinfoDictionary objectForKey:@"extra_cargo"])
		extra_cargo = [(NSNumber*)[shipinfoDictionary objectForKey:@"extra_cargo"] intValue];
	else
		extra_cargo = 15;
	//
	if ([self has_extra_equipment:@"EQ_CARGO_BAY"])
		max_cargo = original_hold_size + extra_cargo - max_passengers * 5;
	//
	has_escape_pod = [self has_extra_equipment:@"EQ_ESCAPE_POD"];
	has_scoop = [self has_extra_equipment:@"EQ_FUEL_SCOOPS"];
	has_fuel_injection = [self has_extra_equipment:@"EQ_FUEL_INJECTION"];
	has_ecm = [self has_extra_equipment:@"EQ_ECM"];
	has_energy_bomb = [self has_extra_equipment:@"EQ_ENERGY_BOMB"];
	has_docking_computer = [self has_extra_equipment:@"EQ_DOCK_COMP"];
	has_galactic_hyperdrive = [self has_extra_equipment:@"EQ_GAL_DRIVE"];
	has_cloaking_device = [self has_extra_equipment:@"EQ_CLOAKING_DEVICE"];
	has_military_jammer = [self has_extra_equipment:@"EQ_MILITARY_JAMMER"];
	has_military_scanner_filter = [self has_extra_equipment:@"EQ_MILITARY_SCANNER_FILTER"];

	has_energy_unit = ([self has_extra_equipment:@"EQ_ENERGY_UNIT"]||[self has_extra_equipment:@"EQ_NAVAL_ENERGY_UNIT"]);
	if (has_energy_unit)
		energy_unit = ([self has_extra_equipment:@"EQ_NAVAL_ENERGY_UNIT"])? ENERGY_UNIT_NAVAL : ENERGY_UNIT_NORMAL;
	else
		energy_unit = ENERGY_UNIT_NONE;
	
	if ([self has_extra_equipment:@"EQ_ADVANCED_COMPASS"])
		compass_mode = COMPASS_MODE_PLANET;
	else
		compass_mode = COMPASS_MODE_BASIC;
	
	shield_booster = ([self has_extra_equipment:@"EQ_SHIELD_BOOSTER"])? 2:1;
	shield_enhancer = ([self has_extra_equipment:@"EQ_NAVAL_SHIELD_BOOSTER"])? 1:0;
	heat_insulation = ([self has_extra_equipment:@"EQ_HEAT_SHIELD"])? 2.0 : 1.0;	// new - provide extra heat_insulation
}


//	time delay method for playing afterburner sounds
// this overlaps two sounds each 2 seconds long, but with a .5s
// crossfade
OOSound* burnersound;
- (void) loopAfterburnerSound
{
	SEL _loopAfterburnerSoundSelector = @selector(loopAfterburnerSound);
		
	if (!afterburner_engaged)				// end the loop cycle
	{
		afterburnerSoundLooping = NO;
		return;
	}
	
	afterburnerSoundLooping = YES;
		
	if (burnersound == afterburner1Sound)
		burnersound = afterburner2Sound;
	else
		burnersound = afterburner1Sound;
	
//	NSLog(@"DEBUG loopAfterburnerSound playing sound %@", burnersound);
#ifdef HAVE_SOUND	
	[burnersound play];
#endif   
	[self	performSelector:_loopAfterburnerSoundSelector
				withObject:NULL
				afterDelay:1.25];	// and swap sounds in 1.25s time
}

- (void) stopAfterburnerSound
{
	[burnersound stop];
}

- (void) setScript_target:(ShipEntity *)ship
{
	script_target = ship;
}

- (ShipEntity*) script_target
{
	return script_target;
}
 
- (BOOL) hasHostileTarget
{
	return NO;
}

- (void) receiveCommsMessage:(NSString *) message_text
{
	[universe addCommsMessage:message_text forCount:4.5];
}

- (void) getFined
{
	if (legal_status == 0)
		return;				// nothing to pay for
	int local_gov = [(NSNumber*)[[universe currentSystemData] objectForKey:KEY_GOVERNMENT] intValue];
	int fine = 500 + ((local_gov < 2)||(local_gov > 5))? 500:0;
	fine *= legal_status;
	if (fine > credits)
	{
		int payback = legal_status * credits / fine;
		legal_status -= payback;
		credits = 0;
	}
	else
	{
		legal_status = 0;
		credits -= fine;
	}
	fine /= 10;	// divide by ten for display
	NSString* fined_message = [NSString stringWithFormat:[universe expandDescription:@"[fined]" forSystem:system_seed], fine];
	[universe addMessage:fined_message forCount:6];
	ship_clock_adjust = 24 * 3600;	// take up a day
	if (gui_screen != GUI_SCREEN_STATUS)
		[self setGuiToStatusScreen];
}

- (void) setDefaultViewOffsets
{
	float halfLength = 0.5 * (boundingBox.max.z - boundingBox.min.z);
	float halfWidth = 0.5 * (boundingBox.max.x - boundingBox.min.x);
	
	forwardViewOffset = make_vector( 0.0, 0.0, boundingBox.max.z - halfLength);
	aftViewOffset = make_vector( 0.0, 0.0, boundingBox.min.z + halfLength);
	portViewOffset = make_vector( boundingBox.min.x + halfWidth, 0.0, 0.0);
	starboardViewOffset = make_vector( boundingBox.max.x - halfWidth, 0.0, 0.0);
}

- (Vector) viewOffset
{
	switch ([universe viewDir])
	{
		case VIEW_FORWARD:
			return forwardViewOffset;
		case VIEW_AFT:
			return aftViewOffset;	break;
		case VIEW_PORT:
			return portViewOffset;	break;
		case VIEW_STARBOARD:
			return starboardViewOffset;	break;
	}
	return make_vector ( 0, 0, 0);
}

- (void) setDefaultWeaponOffsets
{
	float halfLength = 0.5 * (boundingBox.max.z - boundingBox.min.z);
	float halfWidth = 0.5 * (boundingBox.max.x - boundingBox.min.x);
		
	forwardWeaponOffset = make_vector( 0.0, -5.0, boundingBox.max.z - halfLength);
	aftWeaponOffset = make_vector( 0.0, -5.0, boundingBox.min.z + halfLength);
	portWeaponOffset = make_vector( boundingBox.min.x + halfWidth, -5.0, 0.0);
	starboardWeaponOffset = make_vector( boundingBox.max.x - halfWidth, -5.0, 0.0);
}

- (void) setUpTrumbles
{
//	NSLog(@"DEBUG setting up trumbles for %@%@", player_name, basefile);
	
	NSMutableString* trumbleDigrams = [NSMutableString stringWithCapacity:256];
	unichar	xchar = (unichar)0;
	unichar digramchars[2];
	
	while ([trumbleDigrams length] < PLAYER_MAX_TRUMBLES + 2)
	{
		if ((player_name)&&[player_name length])
			[trumbleDigrams appendFormat:@"%@%@", player_name, basefile];
		else
			[trumbleDigrams appendString:@"Some Random Text!"];
	}
	int i;
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
	{
		digramchars[0] = ([trumbleDigrams characterAtIndex:i] & 0x007f) | 0x0020;
		digramchars[1] = (([trumbleDigrams characterAtIndex:i + 1] ^ xchar) & 0x007f) | 0x0020;
		xchar = digramchars[0];
		NSString* digramstring = [NSString stringWithCharacters:digramchars length:2];
		if (trumble[i])
			[trumble[i] release];
		trumble[i] = [[OOTrumble alloc] initForPlayer:self digram:digramstring];
	}
	//
	n_trumbles = 0;
	//
	trumbleAppetiteAccumulator = 0.0;
}

- (void) addTrumble:(OOTrumble*) papaTrumble
{
	if (n_trumbles >= PLAYER_MAX_TRUMBLES)
	{
		NSLog(@"DEBUG trumble maximum population reached!");
		return;
	}
	OOTrumble* trumblePup = trumble[n_trumbles];
	[trumblePup spawnFrom:papaTrumble];
	n_trumbles++;
}

- (void) removeTrumble:(OOTrumble*) deadTrumble
{
	if (n_trumbles <= 0)
	{
		NSLog(@"DEBUG trumble minimum population reached!");
		return;
	}
	int trumble_index = NSNotFound;
	int i;
	for (i = 0; (trumble_index == NSNotFound)&&(i < n_trumbles); i++)
	{
		if (trumble[i] == deadTrumble)
			trumble_index = i;
	}
	if (trumble_index == NSNotFound)
	{
		NSLog(@"DEBUG can't get rid of inactive trumble %@", deadTrumble);
		return;
	}
	n_trumbles--;	// reduce number of trumbles
	trumble[trumble_index] = trumble[n_trumbles];	// swap with the current last trumble
	trumble[n_trumbles] = deadTrumble;				// swap with the current last trumble
}


- (OOTrumble**) trumbleArray
{
	return trumble;
}

- (int) n_trumbles
{
	return n_trumbles;
}

- (NSObject*) trumbleValue
{
	// debugging - force an increase in the trumble population
	if ([[player_name lowercaseString] hasPrefix:@"trumble"])
		n_trumbles = PLAYER_MAX_TRUMBLES / 2;
	//
	NSString* namekey = [NSString stringWithFormat:@"%@-humbletrash", player_name];
	int trumbleHash;
	clear_checksum();
	[self munge_checksum_with_NSString:player_name];
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(n_trumbles);
	//
	[[NSUserDefaults standardUserDefaults]  setInteger:trumbleHash forKey:namekey];
	//
	int i;
	NSMutableArray* trumbleArray = [NSMutableArray arrayWithCapacity:PLAYER_MAX_TRUMBLES];
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
		[trumbleArray addObject:[trumble[i] dictionary]];
	//
	return [NSArray arrayWithObjects:[NSNumber numberWithInt:n_trumbles],[NSNumber numberWithInt:trumbleHash], trumbleArray, nil];
}

- (void) setTrumbleValueFrom:(NSObject*) trumbleValue
{
	BOOL info_failed = NO;
	int trumbleHash;
	int putativeHash = 0;
	int putativeNTrumbles = 0;
	NSArray* putativeTrumbleArray = nil;
	int i;
	NSString* namekey = [NSString stringWithFormat:@"%@-humbletrash", player_name];
	//
	[self setUpTrumbles];
//	NSLog(@"DEBUG setting trumble values from %@", trumbleValue);
	//
	if (trumbleValue)
	{
		BOOL possible_cheat = NO;
		if (![trumbleValue isKindOfClass:[NSArray class]])
			info_failed = YES;
		else
		{
			NSArray* values = (NSArray*) trumbleValue;
			if ([values count] >= 1)
				putativeNTrumbles = [[values objectAtIndex:0] intValue];
			if ([values count] >= 2)
				putativeHash = [[values objectAtIndex:1] intValue];
			if ([values count] >= 3)
				putativeTrumbleArray = (NSArray*)[values objectAtIndex:2];
		}
		// calculate a hash for the putative values
		clear_checksum();
		[self munge_checksum_with_NSString:player_name];
		munge_checksum(credits);
		munge_checksum(ship_kills);
		trumbleHash = munge_checksum(putativeNTrumbles);
		//
		if (putativeHash != trumbleHash)
			info_failed = YES;
		//
		if (info_failed)
		{
			NSLog(@"POSSIBLE CHEAT DETECTED");
			possible_cheat = YES;
		}
		//
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			// try to determine n_trumbles from the key in the saved game
			clear_checksum();
			[self munge_checksum_with_NSString:player_name];
			munge_checksum(credits);
			munge_checksum(ship_kills);
			trumbleHash = munge_checksum(i);
			if (putativeHash == trumbleHash)
			{
				info_failed = NO;
				putativeNTrumbles = i;
			}
		}
		//
		if (possible_cheat && !info_failed)
			NSLog(@"CHEAT DEFEATED - that's not the way to get rid of trumbles!");
	}
	//
	if (info_failed && [[NSUserDefaults standardUserDefaults] objectForKey:namekey])
	{
		// try to determine n_trumbles from the key in user defaults
		putativeHash = [[NSUserDefaults standardUserDefaults] integerForKey:namekey];
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			clear_checksum();
			[self munge_checksum_with_NSString:player_name];
			munge_checksum(credits);
			munge_checksum(ship_kills);
			trumbleHash = munge_checksum(i);
			if (putativeHash == trumbleHash)
			{
				info_failed = NO;
				putativeNTrumbles = i;
			}
		}
		//
		if (!info_failed)
			NSLog(@"CHEAT DEFEATED - that's not the way to get rid of trumbles!");
	}
	// at this stage we've done the best we can to stop cheaters
	n_trumbles = putativeNTrumbles;
	
//	NSLog(@"DEBUG putativeTrumbleArray = \n%@", putativeTrumbleArray);
	
	if ((putativeTrumbleArray != nil) && ([putativeTrumbleArray count] == PLAYER_MAX_TRUMBLES))
	{
		for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
			[trumble[i] setFromDictionary:(NSDictionary *)[putativeTrumbleArray objectAtIndex:i]];
	}
	//
	clear_checksum();
	[self munge_checksum_with_NSString:player_name];
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(n_trumbles);
	//
	[[NSUserDefaults standardUserDefaults]  setInteger:trumbleHash forKey:namekey];
}

- (void) munge_checksum_with_NSString:(NSString*) str
{
	if (!str)
		return;
	int i;
	int len = [str length];
	for (i = 0; i < len; i++)
		munge_checksum((int)[str characterAtIndex:i]);
}

- (NSString *)screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate
{
	if (0.0f != inRate)
	{
		return [NSString stringWithFormat:@" Fullscreen: %d x %d at %.3g Hz ", inWidth, inHeight, inRate];
	}
	else
	{
		return [NSString stringWithFormat:@" Fullscreen: %d x %d ", inWidth, inHeight];
	}
}

- (void) suppressTargetLost
{
	suppressTargetLost = YES;
}

- (void) setScoopsActive
{
	scoopsActive = YES;
}

// override shipentity addTarget to implement target_memory
//
- (void) addTarget:(Entity *) targetEntity
{
	[super addTarget:targetEntity];
	if ([self has_extra_equipment:@"EQ_TARGET_MEMORY"])
	{
		int i = 0;
		// if targetted previously use that memory space
		for (i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
		{
			if (primaryTarget == target_memory[i])
			{
				target_memory_index = i;
				return;
			}
		}
		// find and use a blank space in memory
		for (i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
		{
			if (target_memory[target_memory_index] == NO_TARGET)
			{
				target_memory[target_memory_index] = primaryTarget;
				return;
			}
			target_memory_index = (target_memory_index + 1) % PLAYER_TARGET_MEMORY_SIZE;
		}
		// use the next memory space
		target_memory_index = (target_memory_index + 1) % PLAYER_TARGET_MEMORY_SIZE;
		target_memory[target_memory_index] = primaryTarget;
		return;
	}
}

- (void) clearTargetMemory
{
	int i = 0;
	for (i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
		target_memory[i] = NO_TARGET;
	target_memory_index = 0;
}

- (BOOL) selectNextTargetFromMemory
{
	int i = 0;
	while (i++ < PLAYER_TARGET_MEMORY_SIZE)	// limit loops
	{
		if (++target_memory_index >= PLAYER_TARGET_MEMORY_SIZE)
			target_memory_index -= PLAYER_TARGET_MEMORY_SIZE;
		int targ_id = target_memory[target_memory_index];
		ShipEntity* potential_target = (ShipEntity*)[universe entityForUniversalID: targ_id];
				
		if ((potential_target)&&(potential_target->isShip))
		{
			if (potential_target->zero_distance < SCANNER_MAX_RANGE2)
			{
				[super addTarget:potential_target];
				missile_status = MISSILE_STATUS_TARGET_LOCKED;
				[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-locked-onto-@]" forSystem:system_seed], (ident_engaged)? @"Ident system": @"Missile", [(ShipEntity *)potential_target name]] forCount:4.5];
				return YES;
			}
		}
		else
			target_memory[target_memory_index] = NO_TARGET;	// tidy up
	}
	return NO;
}

- (BOOL) selectPreviousTargetFromMemory;
{
	int i = 0;
	while (i++ < PLAYER_TARGET_MEMORY_SIZE)	// limit loops
	{
		if (--target_memory_index < 0)
			target_memory_index += PLAYER_TARGET_MEMORY_SIZE;
		int targ_id = target_memory[target_memory_index];
		ShipEntity* potential_target = (ShipEntity*)[universe entityForUniversalID: targ_id];
		
		if ((potential_target)&&(potential_target->isShip))
		{
			if (potential_target->zero_distance < SCANNER_MAX_RANGE2)
			{
				[super addTarget:potential_target];
				missile_status = MISSILE_STATUS_TARGET_LOCKED;
				[universe addMessage:[NSString stringWithFormat:[universe expandDescription:@"[@-locked-onto-@]" forSystem:system_seed], (ident_engaged)? @"Ident system": @"Missile", [(ShipEntity *)potential_target name]] forCount:4.5];
				return YES;
			}
		}
		else
			target_memory[target_memory_index] = NO_TARGET;	// tidy_up
	}
	return NO;
}



@end
