/*

PlayerEntity.m

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

#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntitySound.h"

#import "StationEntity.h"
#import "ParticleEntity.h"
#import "PlanetEntity.h"
#import "WormholeEntity.h"

#import "OOMaths.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "Universe.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "OOTrumble.h"
#import "PlayerEntityLoadSave.h"
#import "OOSound.h"
#import "OOColor.h"
#import "Octree.h"
#import "OOCacheManager.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOTexture.h"	// Required to properly release missionBackgroundTexture.
#import "OORoleSet.h"	// Required to properly release roleSet.
#import "HeadUpDisplay.h"
#import "OOOpenGLExtensionManager.h"

#import "OOScript.h"
#import "OOScriptTimer.h"

#ifndef GNUSTEP
#import "Groolite.h"
#else
#import "JoystickHandler.h"
#import "PlayerEntityStickMapper.h"
#endif

#define kOOLogUnconvertedNSLog @"unclassified.PlayerEntity"


// 10m/s forward drift
#define	OG_ELITE_FORWARD_DRIFT			10.0f


enum
{
	// If comm log is kCommLogTrimThreshold or more lines long, it will be cut to kCommLogTrimSize.
	kCommLogTrimThreshold				= 125,
	kCommLogTrimSize					= 100
};


static NSString * const kOOLogBuyMountedOK			= @"equip.buy.mounted";
static NSString * const kOOLogBuyMountedFailed		= @"equip.buy.mounted.failed";


static PlayerEntity *sSharedPlayer = nil;


@interface PlayerEntity (OOPrivate)

- (void) setExtraEquipmentFromFlags;
-(void) doTradeIn:(OOCreditsQuantity)tradeInValue forPriceFactor:(double)priceFactor;

@end


@implementation PlayerEntity

+ (id)sharedPlayer
{
	return sSharedPlayer;
}


- (void) setName:(NSString *)inName
{
	// Block super method; player ship can't be renamed.
}


- (void)completeInitialSetUp
{
	dockedStation = [UNIVERSE station];
	[self doWorldScriptEvent:@"startUp" withArguments:nil];
}


- (void) unloadCargoPods
{
	/* loads commodities from the cargo pods onto the ship's manifest */
	unsigned i;
	NSMutableArray* localMarket = [dockedStation localMarket];
	NSMutableArray* manifest = [[NSMutableArray arrayWithArray:localMarket] retain];  // retain
	
	// copy the quantities in ShipCommodityData to the manifest
	// (was: zero the quantities in the manifest, making a mutable array of mutable arrays)
	
	for (i = 0; i < [manifest count]; i++)
	{
		NSMutableArray* commodityInfo = [NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:i]];
		NSArray* shipCommInfo = [NSArray arrayWithArray:(NSArray *)[shipCommodityData objectAtIndex:i]];
		int amount = [(NSNumber*)[shipCommInfo objectAtIndex:MARKET_QUANTITY] intValue];
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:amount]];
		[manifest replaceObjectAtIndex:i withObject:commodityInfo];
	}
	
	NSEnumerator	*cargoEnumerator = nil;
	ShipEntity		*cargoItem = nil;
	
	// step through the cargo pods adding in the quantities
	for (cargoEnumerator = [cargo objectEnumerator]; (cargoItem = [cargoEnumerator nextObject]); )
	{
		NSMutableArray	*commodityInfo;
		int				co_type, co_amount, quantity;

		co_type = [cargoItem commodityType];
		co_amount = [cargoItem commodityAmount];
		
		if (co_type == NSNotFound)
		{
			OOLog(@"player.badCargoPod", @"Cargo pod %@ has bad commodity type (NSNotFound), rejecting.", cargoItem);
			continue;
		}
		commodityInfo = [manifest objectAtIndex:co_type];
		quantity =  [[commodityInfo objectAtIndex:MARKET_QUANTITY] intValue] + co_amount;
		
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity]]; // enter the adjusted quantity
	}
	
	[shipCommodityData release];
	shipCommodityData = manifest;
	
	[cargo removeAllObjects];   // empty the hold
	
	[self calculateCurrentCargo];	// work out the correct value for current_cargo
}


- (void) loadCargoPods
{
	/* loads commodities from the ships manifest into individual cargo pods */
	unsigned i,j;
	NSMutableArray* localMarket = [dockedStation localMarket];
	NSMutableArray* manifest = [[NSMutableArray arrayWithArray:shipCommodityData] retain];  // retain
	
	if (cargo == nil)  cargo = [[NSMutableArray alloc] init];
	
	for (i = 0; i < [manifest count]; i++)
	{
		NSMutableArray*	commodityInfo = [[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:i]] retain];  // retain
		OOCargoQuantity	quantity = [[commodityInfo objectAtIndex:MARKET_QUANTITY] intValue];
		OOMassUnit		units =	[UNIVERSE unitsForCommodity:i];
		if (quantity > 0)
		{
			if (units == UNITS_TONS)
			{
				// put each ton in a separate container
				for (j = 0; j < quantity; j++)
				{
					ShipEntity *container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
					if (container)
					{
						[container setScanClass: CLASS_CARGO];
						[container setStatus:STATUS_IN_HOLD];
						[container setCommodity:i andAmount:1];
						[cargo addObject:container];
						[container release];
					}
					else
					{
						OOLog(@"player.loadCargoPods.noContainer", @"***** ERROR couldn't find a container while trying to [PlayerEntity loadCargoPods] *****");
						// throw an exception here...
						[NSException raise:OOLITE_EXCEPTION_FATAL
							format:@"[PlayerEntity loadCargoPods] failed to create a container for cargo with role 'cargopod'"];
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
	galaxy_coordinates = NSMakePoint(s_seed.d, s_seed.b);
}


- (Random_Seed) target_system_seed
{
	return target_system_seed;
}


- (NSDictionary *) commanderDataDictionary
{
	NSMutableDictionary *result = [NSMutableDictionary dictionary];

	NSString *gal_seed = [NSString stringWithFormat:@"%d %d %d %d %d %d",galaxy_seed.a, galaxy_seed.b, galaxy_seed.c, galaxy_seed.d, galaxy_seed.e, galaxy_seed.f];
	NSString *gal_coords = [NSString stringWithFormat:@"%d %d",(int)galaxy_coordinates.x,(int)galaxy_coordinates.y];
	NSString *tgt_coords = [NSString stringWithFormat:@"%d %d",(int)cursor_coordinates.x,(int)cursor_coordinates.y];

	[result setObject:gal_seed		forKey:@"galaxy_seed"];
	[result setObject:gal_coords	forKey:@"galaxy_coordinates"];
	[result setObject:tgt_coords	forKey:@"target_coordinates"];
	
	[result setObject:player_name			forKey:@"player_name"];
	
	[result setObject:[NSNumber numberWithUnsignedLongLong:credits]	forKey:@"credits"];
	[result setObject:[NSNumber numberWithUnsignedInt:fuel]			forKey:@"fuel"];
	
	[result setObject:[NSNumber numberWithInt:galaxy_number]		forKey:@"galaxy_number"];
	
	[result setObject:[NSNumber numberWithInt:forward_weapon]		forKey:@"forward_weapon"];
	[result setObject:[NSNumber numberWithInt:aft_weapon]			forKey:@"aft_weapon"];
	[result setObject:[NSNumber numberWithInt:port_weapon]			forKey:@"port_weapon"];
	[result setObject:[NSNumber numberWithInt:starboard_weapon]		forKey:@"starboard_weapon"];
	
	[result setObject:[NSNumber numberWithInt:max_cargo + 5 * max_passengers]	forKey:@"max_cargo"];
	
	[result setObject:shipCommodityData		forKey:@"shipCommodityData"];
	
	// Deprecated equipment flags. New equipment shouldn't be added here (it'll be handled by the extra_equipment dictionary).
	[result setObject:[NSNumber numberWithBool:has_ecm]							forKey:@"has_ecm"];
	[result setObject:[NSNumber numberWithBool:has_scoop]						forKey:@"has_scoop"];
	[result setObject:[NSNumber numberWithBool:has_energy_bomb]					forKey:@"has_energy_bomb"];
	[result setObject:[NSNumber numberWithBool:has_energy_unit]					forKey:@"has_energy_unit"];
	[result setObject:[NSNumber numberWithInt:energy_unit]						forKey:@"energy_unit"];
	[result setObject:[NSNumber numberWithBool:has_docking_computer]			forKey:@"has_docking_computer"];
	[result setObject:[NSNumber numberWithBool:has_galactic_hyperdrive]			forKey:@"has_galactic_hyperdrive"];
	[result setObject:[NSNumber numberWithBool:has_escape_pod]					forKey:@"has_escape_pod"];
	[result setObject:[NSNumber numberWithBool:has_fuel_injection]				forKey:@"has_fuel_injection"];
	NSMutableArray* missile_roles = [NSMutableArray arrayWithCapacity:max_missiles];
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i])
		{
			[missile_roles addObject:[missile_entity[i] primaryRole]];
		}
		else
		{
			[missile_roles addObject:@"NONE"];
		}
	}
	[result setObject:missile_roles forKey:@"missile_roles"];
//	[self safeAllMissiles];	// affects missile_status!!
	
	[result setObject:[NSNumber numberWithInt:missiles]					forKey:@"missiles"];
	
	[result setObject:[NSNumber numberWithInt:legalStatus]				forKey:@"legal_status"];
	[result setObject:[NSNumber numberWithInt:market_rnd]				forKey:@"market_rnd"];
	[result setObject:[NSNumber numberWithInt:ship_kills]				forKey:@"ship_kills"];
	[result setObject:[NSNumber numberWithBool:saved]					forKey:@"saved"];

	// ship depreciation
	[result setObject:[NSNumber numberWithInt:ship_trade_in_factor]		forKey:@"ship_trade_in_factor"];

	// mission variables
	if (mission_variables)
		[result setObject:[NSDictionary dictionaryWithDictionary:mission_variables] forKey:@"mission_variables"];

	// communications log
	NSArray *log = [self commLog];
	if (log != nil)  [result setObject:commLog forKey:@"comm_log"];

	// extra equipment flags
	if (extra_equipment)
	{
		[self setExtraEquipmentFromFlags];
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

	[result setObject:missionDestinations forKey:@"missionDestinations"];

	//shipyard
	[result setObject:shipyard_record forKey:@"shipyard_record"];

	//ship's clock
	[result setObject:[NSNumber numberWithDouble:ship_clock] forKey:@"ship_clock"];

	//speech
	[result setObject:[NSNumber numberWithBool:isSpeechOn] forKey:@"speech_on"];

	//ootunes
	[result setObject:[NSNumber numberWithBool:ootunes_on] forKey:@"ootunes_on"];

	//base ship description
	[result setObject:ship_desc forKey:@"ship_desc"];
	[result setObject:[[UNIVERSE getDictionaryForShip:ship_desc] stringForKey:KEY_NAME] forKey:@"ship_name"];
	
	//local market
	if ([dockedStation localMarket])  [result setObject:[dockedStation localMarket] forKey:@"localMarket"];

	// reduced detail option
	[result setObject:[NSNumber numberWithBool:[UNIVERSE reducedDetail]] forKey:@"reducedDetail"];

	// strict UNIVERSE?
	if ([UNIVERSE strict])
	{
		[result setObject:[NSNumber numberWithBool:YES] forKey:@"strict"];
	}

	// persistant UNIVERSE information
	if ([UNIVERSE localPlanetInfoOverrides])
	{
		[result setObject:[UNIVERSE localPlanetInfoOverrides] forKey:@"local_planetinfo_overrides"];
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
	munge_checksum(legalStatus);	munge_checksum(market_rnd);		munge_checksum(ship_kills);
	if (mission_variables)
		munge_checksum([[mission_variables description] length]);
	if (extra_equipment)
		munge_checksum([[extra_equipment description] length]);
	int final_checksum = munge_checksum([[ship_desc description] length]);

	//set checksum
	[result setObject:[NSNumber numberWithInt:final_checksum] forKey:@"checksum"];
	
	return result;
}


- (BOOL)setCommanderDataFromDictionary:(NSDictionary *) dict
{
	// TODO: use CollectionExtractors for type-safety. -- Ahruman
	if ([dict boolForKey:@"strict" defaultValue:NO])
	{
		if (![UNIVERSE strict])
		{
			// reset to strict and reload player
			[UNIVERSE setStrict:YES];
		}
	}
	else
	{
		if ([UNIVERSE strict])
		{
			// reset to unrestricted and reload player
			[UNIVERSE setStrict:NO];
		}
	}
	
	#if 0
	// DISABLED -- this setting should be stored in preferences. Saving it in games makes no sense. -- Ahruman
	// texture experiments
	if ([dict objectForKey:@"procedural_planet_textures"])
		[UNIVERSE setDoProcedurallyTexturedPlanets: [[dict objectForKey:@"procedural_planet_textures"] boolValue]];
	#endif
	
	//base ship description
	if ([dict objectForKey:@"ship_desc"])
	{
		[ship_desc release];
		ship_desc = [[dict objectForKey:@"ship_desc"] copy];
		
		NSDictionary *shipDict = [UNIVERSE getDictionaryForShip:ship_desc];
		if (shipDict == nil)  return NO;
		
		if (![self setUpShipFromDictionary:shipDict])  return NO;
	}

	// ship depreciation
	if ([dict objectForKey:@"ship_trade_in_factor"])
		ship_trade_in_factor = [(NSNumber*)[dict objectForKey:@"ship_trade_in_factor"] intValue];
	else
		ship_trade_in_factor = 95;

	if ([dict objectForKey:@"galaxy_seed"])
	{
		NSArray *seed_vals = ScanTokensFromString([dict objectForKey:@"galaxy_seed"]);
		galaxy_seed.a = (unsigned char)[(NSString *)[seed_vals objectAtIndex:0] intValue];
		galaxy_seed.b = (unsigned char)[(NSString *)[seed_vals objectAtIndex:1] intValue];
		galaxy_seed.c = (unsigned char)[(NSString *)[seed_vals objectAtIndex:2] intValue];
		galaxy_seed.d = (unsigned char)[(NSString *)[seed_vals objectAtIndex:3] intValue];
		galaxy_seed.e = (unsigned char)[(NSString *)[seed_vals objectAtIndex:4] intValue];
		galaxy_seed.f = (unsigned char)[(NSString *)[seed_vals objectAtIndex:5] intValue];
	}

	if ([dict objectForKey:@"galaxy_coordinates"])
	{
		NSArray *coord_vals = ScanTokensFromString([dict objectForKey:@"galaxy_coordinates"]);
		galaxy_coordinates.x = (unsigned char)[(NSString *)[coord_vals objectAtIndex:0] intValue];
		galaxy_coordinates.y = (unsigned char)[(NSString *)[coord_vals objectAtIndex:1] intValue];
		cursor_coordinates = galaxy_coordinates;
	}

	if ([dict objectForKey:@"target_coordinates"])
	{
		NSArray *coord_vals = ScanTokensFromString([dict objectForKey:@"target_coordinates"]);
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
	[self setExtraEquipmentFromFlags];
	if ([dict objectForKey:@"extra_equipment"])
	{
		[extra_equipment addEntriesFromDictionary:(NSDictionary *)[dict objectForKey:@"extra_equipment"]];
		/*	Bug workaround: extra_equipment should never contain EQ_TRUMBLE,
			which is basically a magic flag passed to awardEquipment: to infect
			the player. However, prior to Oolite 1.70.1, if the player had a
			trumble infection and awardEquipment:EQ_TRUMBLE was called, an
			EQ_TRUMBLE would be added to the equipment list. Subsequent calls
			to awardEquipment:EQ_TRUMBLE would exit early because there was an
			EQ_TRUMBLE in the equipment list. as a result, it would no longer
			be possible to infect the player after the current infection ended.
			
			The bug is fixed in 1.70.1. The following line is to fix old saved
			games which had been "corrupted" by the bug.
			-- Ahruman 2007-12-04
		*/
		[extra_equipment removeObjectForKey:@"EQ_TRUMBLE"];
	}
	// bools	(mostly deprecated by use of the extra_equipment dictionary, keep for compatibility)
	
	if (([dict objectForKey:@"has_docking_computer"])&&([(NSNumber *)[dict objectForKey:@"has_docking_computer"] boolValue]))
		[self addExtraEquipment:@"EQ_DOCK_COMP"];
	if (([dict objectForKey:@"has_galactic_hyperdrive"])&&([(NSNumber *)[dict objectForKey:@"has_galactic_hyperdrive"] boolValue]))
		[self addExtraEquipment:@"EQ_GAL_DRIVE"];
	if (([dict objectForKey:@"has_escape_pod"])&&([(NSNumber *)[dict objectForKey:@"has_escape_pod"] boolValue]))
		[self addExtraEquipment:@"EQ_ESCAPE_POD"];
	if (([dict objectForKey:@"has_ecm"])&&([(NSNumber *)[dict objectForKey:@"has_ecm"] boolValue]))
		[self addExtraEquipment:@"EQ_ECM"];
	if (([dict objectForKey:@"has_scoop"])&&([(NSNumber *)[dict objectForKey:@"has_scoop"] boolValue]))
		[self addExtraEquipment:@"EQ_FUEL_SCOOPS"];
	if (([dict objectForKey:@"has_energy_bomb"])&&([(NSNumber *)[dict objectForKey:@"has_energy_bomb"] boolValue]))
		[self addExtraEquipment:@"EQ_ENERGY_BOMB"];
	
	if (([dict objectForKey:@"has_fuel_injection"])&&([(NSNumber *)[dict objectForKey:@"has_fuel_injection"] boolValue]))
		[self addExtraEquipment:@"EQ_FUEL_INJECTION"];
	if (([dict objectForKey:@"has_energy_unit"])&&([(NSNumber *)[dict objectForKey:@"has_energy_unit"] boolValue]))
	{
		if ([dict objectForKey:@"energy_unit"])
			energy_unit = [(NSNumber *)[dict objectForKey:@"energy_unit"]   intValue]; // load specials
		else
			energy_unit = (has_energy_unit) ? ENERGY_UNIT_NORMAL : ENERGY_UNIT_NONE;	// set default
		switch (energy_unit)
		{
			case ENERGY_UNIT_NORMAL :
			[self addExtraEquipment:@"EQ_ENERGY_UNIT"];
			break;
			case ENERGY_UNIT_NAVAL :
			[self addExtraEquipment:@"EQ_NAVAL_ENERGY_UNIT"];
			break;
			default :
			break;
		}
	}

	// speech
	if ([dict objectForKey:@"speech_on"])
		isSpeechOn = [(NSNumber *)[dict objectForKey:@"speech_on"] boolValue];

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

	// mission destinations
	if ([dict objectForKey:@"missionDestinations"])
	{
		if (missionDestinations)
			[missionDestinations release];
		missionDestinations = [[NSMutableArray arrayWithArray:(NSArray *)[dict objectForKey:@"missionDestinations"]] retain];
	}
	else
	{
		if (missionDestinations)
			[missionDestinations release];
		missionDestinations = [[NSMutableArray arrayWithCapacity:8] retain];
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
		[UNIVERSE setReducedDetail:[(NSNumber *)[dict objectForKey:@"reducedDetail"] boolValue]];

	if ([dict objectForKey:@"saved"])
		saved = [(NSNumber *)[dict objectForKey:@"saved"] boolValue];

	// ints
	
	unsigned original_hold_size = [UNIVERSE maxCargoForShip:ship_desc];
	if ([dict objectForKey:@"max_cargo"])
		max_cargo = [(NSNumber *)[dict objectForKey:@"max_cargo"]	intValue];
	if (max_cargo > original_hold_size)
		[self addExtraEquipment:@"EQ_CARGO_BAY"];
	max_cargo -= max_passengers * 5;
	
	credits = [dict unsignedLongLongForKey:@"credits" defaultValue:credits];
	fuel = [dict unsignedIntForKey:@"fuel" defaultValue:fuel];
	
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
	
	missiles = [dict unsignedIntForKey:@"missiles"];
	// sanity check the number of missiles...
	if (missiles > max_missiles)
		missiles = max_missiles;
	
	// end sanity check
	if ([dict objectForKey:@"legal_status"])
		legalStatus = [(NSNumber *)[dict objectForKey:@"legal_status"] intValue];
	if ([dict objectForKey:@"market_rnd"])
		market_rnd = [(NSNumber *)[dict objectForKey:@"market_rnd"]   intValue];
	if ([dict objectForKey:@"ship_kills"])
		ship_kills = [(NSNumber *)[dict objectForKey:@"ship_kills"]   intValue];

	// doubles
	
	if ([dict objectForKey:@"ship_clock"])
		ship_clock = [(NSNumber*)[dict objectForKey:@"ship_clock"] doubleValue];
	fps_check_time = ship_clock;

	// mission_variables
	[mission_variables removeAllObjects];
	if ([dict objectForKey:@"mission_variables"])
		[mission_variables addEntriesFromDictionary:(NSDictionary *)[dict objectForKey:@"mission_variables"]];

	// persistant UNIVERSE info
	if ([dict objectForKey:@"local_planetinfo_overrides"])
	{
		[UNIVERSE setLocalPlanetInfoOverrides:(NSDictionary *)[dict objectForKey:@"local_planetinfo_overrides"]];
	}

	// communications log
	[commLog release];
	commLog = [[dict arrayForKey:@"comm_log"] mutableCopy];

	// set up missiles
	unsigned i;
	[self setActiveMissile: 0];
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		if (missile_entity[i])
			[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	if ([dict objectForKey:@"missile_roles"])
	{
		NSArray *missile_roles = (NSArray*)[dict objectForKey:@"missile_roles"];
		if (max_missiles < [missile_roles count])
			missile_roles = [missile_roles subarrayWithRange:NSMakeRange(0, max_missiles)];
		if ((missiles) && (missiles != [missile_roles count]))
			missiles = [missile_roles count];	// sanity check the number of missiles
		for (i = 0; (i < max_missiles)&&(i < [missile_roles count]); i++)
		{
			NSString *missile_desc = [missile_roles objectAtIndex:i];
			if (![missile_desc isEqual:@"NONE"])
			{
				ShipEntity *amiss = [UNIVERSE newShipWithRole:missile_desc];
				if (amiss)
					missile_entity[i] = amiss;   // retain count = 1
				else
				{
					OOLog(@"load.failed.missileNotFound", @"***** ERROR couldn't find a missile of role '%@' while trying to [PlayerEntity setCommanderDataFromDictionary:] *****", missile_desc);
					[NSException raise:OOLITE_EXCEPTION_FATAL
								format:@"[PlayerEntity setCommanderDataFromDictionary:] failed to create a missile with role '%@'", missile_desc];
				}
			}
		}
	}
	else
	{
		for (i = 0; i < missiles; i++)
			missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];   // retain count = 1 - should be okay as long as we keep a missile with this role
																			// in the base package.
	}
	while ((missiles > 0)&&(missile_entity[activeMissile] == nil))
		[self selectNextMissile];
	

	
	[self setFlagsFromExtraEquipment];
	forward_shield = PLAYER_MAX_FORWARD_SHIELD;
	aft_shield = PLAYER_MAX_AFT_SHIELD;
	

	//  things...
	
	system_seed = [UNIVERSE findSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	

	// trumble information
	[self setUpTrumbles];
	[self setTrumbleValueFrom:[dict objectForKey:@"trumbles"]];	// if it doesn't exist we'll check user-defaults

	// finally
	missiles = [self countMissiles];
	
	return YES;
}

/////////////////////////////////////////////////////////

- (id) init
{
	if (sSharedPlayer != nil)
	{
		[NSException raise:NSInternalInconsistencyException format:@"%s: expected only one PlayerEntity to exist at a time.", __FUNCTION__];
	}
	
    self = [super init];
	sSharedPlayer = self;
	
	compassMode = COMPASS_MODE_BASIC;
	
	afterburnerSoundLooping = NO;
	
	int i;
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
		missile_entity[i] = nil;
	[self set_up];
	
	isPlayer = YES;
	
	save_path = nil;
	
	[self setUpSound];
	
	scoopsActive = NO;
	
	target_memory_index = 0;
	
	dockingReport = [[NSMutableString alloc] init];
	
	worldScripts = [[ResourceManager loadScripts] retain];

	[self initControls];
	
    return self;
}


- (void) set_up
{
	unsigned i;
	Random_Seed gal_seed = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	
	showDemoShips = NO;
	
	show_info_flag = NO;

	[ship_desc release];
	ship_desc = [[NSString stringWithString:PLAYER_SHIP_DESC] retain];
	ship_trade_in_factor = 95;
	
	NSDictionary *huddict = [ResourceManager dictionaryFromFilesNamed:@"hud.plist" inFolder:@"Config" andMerge:YES];
	[hud release];
	hud = [[HeadUpDisplay alloc] initWithDictionary:huddict];
	[hud setScannerZoom:1.0];
	[hud resizeGuis:huddict];
	scanner_zoom_rate = 0.0;
	
	[mission_variables release];
	mission_variables = [[NSMutableDictionary alloc] init];
	
	[localVariables release];
	localVariables = [[NSMutableDictionary alloc] init];
	
	[self setScriptTarget:nil];
	[self resetMissionChoice];
	
	[reputation release];
	reputation = [[NSMutableDictionary alloc] initWithCapacity:6];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:7] forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:0] forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:7] forKey:PASSAGE_UNKNOWN_KEY];
	
	energy					= 256;
	weapon_temp				= 0.0;
	forward_weapon_temp		= 0.0;
	aft_weapon_temp			= 0.0;
	port_weapon_temp		= 0.0;
	starboard_weapon_temp	= 0.0;
	ship_temperature		= 60.0;
	heat_insulation			= 1.0;
	alertFlags				= 0;
	
	max_passengers = 0;
	[passengers release];
	passengers = [[NSMutableArray alloc] init];
	[passenger_record release];
	passenger_record = [[NSMutableDictionary alloc] init];
	
	[contracts release];
	contracts = [[NSMutableArray alloc] init];
	[contract_record release];
	contract_record = [[NSMutableDictionary alloc] init];
	
	[missionDestinations release];
	missionDestinations = [[NSMutableArray alloc] init];
	
	[shipyard_record release];
	shipyard_record = [[NSMutableDictionary alloc] init];
	
	[extra_equipment release];
	extra_equipment =[[NSMutableDictionary alloc] init];
	
	[missionBackgroundTexture release];
	missionBackgroundTexture = nil;
	
	script_time = 0.0;
	script_time_check = SCRIPT_TIMER_INTERVAL;
	script_time_interval = SCRIPT_TIMER_INTERVAL;
	
	NSCalendarDate *nowDate = [NSCalendarDate calendarDate];
	ship_clock = PLAYER_SHIP_CLOCK_START;
	ship_clock += [nowDate hourOfDay] * 3600.0;
	ship_clock += [nowDate minuteOfHour] * 60.0;
	ship_clock += [nowDate secondOfMinute];
	fps_check_time = ship_clock;
	ship_clock_adjust = 0.0;
	
	isSpeechOn = NO;
	ootunes_on = NO;
	
	[custom_views release];
	custom_views = nil;
	
	mouse_control_on = NO;
	
	docking_music_on = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_DOCKING_MUSIC defaultValue:YES];

	// player commander data
	// Most of this is probably also set more than once
	
	player_name				= [[NSString alloc] initWithString:@"Jameson"];  // alloc retains
	galaxy_coordinates		= NSMakePoint(0x14,0xAD);	// 20,173
	galaxy_seed				= gal_seed;
	credits					= 1000;
	fuel					= PLAYER_MAX_FUEL;
	fuel_accumulator		= 0.0;

	galaxy_number			= 0;
	forward_weapon			= WEAPON_PULSE_LASER;
	aft_weapon				= WEAPON_NONE;
	port_weapon				= WEAPON_NONE;
	starboard_weapon		= WEAPON_NONE;

	max_cargo				= 20; // will be reset later

	shipCommodityData = [[[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] objectForKey:@"default"] retain];
	
	has_ecm					= NO;
	has_scoop				= NO;
	has_energy_bomb			= NO;
	has_energy_unit			= NO;
	has_docking_computer	= NO;
	has_galactic_hyperdrive	= NO;
	has_escape_pod			= NO;
	has_fuel_injection		= NO;

	shield_booster			= 1;
	shield_enhancer			= 0;

	// set up missiles
	missiles				= PLAYER_STARTING_MISSILES;
	max_missiles			= PLAYER_MAX_MISSILES;
	
	[self setActiveMissile: 0];
	for (i = 0; i < missiles; i++)
	{
		[missile_entity[i] release];
	//	missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];   // retain count = 1
		missile_entity[i] = nil;
	}
	[self safeAllMissiles];
	
	legalStatus			= 0;

	market_rnd				= 0;
	ship_kills				= 0;
	saved					= NO;
	cursor_coordinates		= galaxy_coordinates;
	
	
	shield_booster			= 1;
	shield_enhancer			= 0;
	forward_shield			= PLAYER_MAX_FORWARD_SHIELD;
	aft_shield				= PLAYER_MAX_AFT_SHIELD;
	
	scanClass				= CLASS_PLAYER;
	
	[UNIVERSE clearGUIs];
	
	dockedStation = [UNIVERSE station];
	
	[commLog release];
	commLog = nil;
	
	[specialCargo release];
	specialCargo = nil;
	
	// views
	forwardViewOffset		= kZeroVector;
	aftViewOffset			= kZeroVector;
	portViewOffset			= kZeroVector;
	starboardViewOffset		= kZeroVector;
	customViewOffset		= kZeroVector;
	
	currentWeaponFacing		= VIEW_FORWARD;

	[save_path autorelease];
	save_path = nil;

	[self setUpTrumbles];
	
	suppressTargetLost = NO;
	
	scoopsActive = NO;
	
	[dockingReport release];
	dockingReport = [[NSMutableString alloc] init];
	
	[shipAI release];
	shipAI = [[AI alloc] initWithStateMachine:PLAYER_DOCKING_AI_NAME andState:@"GLOBAL"];
	[shipAI setOwner:self];
	
	lastScriptAlertCondition = [self alertCondition];
	
	entity_personality = ranrot_rand() & 0x7FFF;
	
	[self setSystem_seed:[UNIVERSE findSystemAtCoords:[self galaxy_coordinates] withGalaxySeed:[self galaxy_seed]]];
	
	[OOScriptTimer noteGameReset];
	[self doScriptEvent:@"reset"];
}


- (BOOL) setUpShipFromDictionary:(NSDictionary *)shipDict
{
	[shipinfoDictionary release];
	shipinfoDictionary = [shipDict copy];
	
	// set things from dictionary from here out
	
	maxFlightSpeed = [shipDict floatForKey:@"max_flight_speed" defaultValue:160.0f];
	max_flight_roll = [shipDict floatForKey:@"max_flight_roll" defaultValue:2.0f];
	max_flight_pitch = [shipDict floatForKey:@"max_flight_pitch" defaultValue:1.0f];
	max_flight_yaw = [shipDict floatForKey:@"max_flight_yaw" defaultValue:max_flight_pitch];	// Note by default yaw == pitch
	
	// set control factors..
	roll_delta =		2.0 * max_flight_roll;
	pitch_delta =		2.0 * max_flight_pitch;
	yaw_delta =			2.0 * max_flight_yaw;
	
	thrust = [shipDict floatForKey:@"thrust" defaultValue:thrust];
	
	maxEnergy = [shipDict floatForKey:@"max_energy" defaultValue:maxEnergy];
	energy_recharge_rate = [shipDict floatForKey:@"energy_recharge_rate" defaultValue:energy_recharge_rate];
	energy = maxEnergy;
	
	forward_weapon_type = StringToWeaponType([shipDict stringForKey:@"forward_weapon_type" defaultValue:@"WEAPON_NONE"]);
	aft_weapon_type = StringToWeaponType([shipDict stringForKey:@"aft_weapon_type" defaultValue:@"WEAPON_NONE"]);
	
	missiles = [shipDict doubleForKey:@"missiles"];
	has_ecm = [shipDict fuzzyBooleanForKey:@"has_ecm"];
	has_scoop = [shipDict fuzzyBooleanForKey:@"has_scoop"];
	has_escape_pod = [shipDict fuzzyBooleanForKey:@"has_escape_pod"];
	
	max_cargo = [shipDict intForKey:@"max_cargo"];
	extra_cargo = [shipDict intForKey:@"extra_cargo" defaultValue:15];
	
	// Load the model (must be before subentities)
	NSString *modelName = [shipDict stringForKey:@"model"];
	if (modelName != nil)
	{
		OOMesh *mesh = [OOMesh meshWithName:modelName
						 materialDictionary:[shipDict dictionaryForKey:@"materials"]
						  shadersDictionary:[shipDict dictionaryForKey:@"shaders"]
									 smooth:[shipDict boolForKey:@"smooth" defaultValue:NO]
							   shaderMacros:DefaultShipShaderMacros()
						shaderBindingTarget:self];
		[self setMesh:mesh];
	}
	
	float density = [shipDict floatForKey:@"density" defaultValue:1.0];
	if (octree)  mass = density * 20.0 * [octree volume];
	
	[name autorelease];
	name = [[shipDict stringForKey:@"name" defaultValue:name] copy];
	
	[roleSet release];
	roleSet = nil;
	[self setPrimaryRole:@"player"];
	
	OOColor *color = [OOColor brightColorWithDescription:[shipDict objectForKey:@"laser_color"]];
	if (color == nil)  color = [OOColor redColor];
	[self setLaserColor:color];
	
	[extra_equipment removeAllObjects];
	if ([shipDict objectForKey:@"extra_equipment"])
	{
		[extra_equipment addEntriesFromDictionary:[shipDict dictionaryForKey:@"extra_equipment"]];
	}
	
	max_missiles = [shipDict intForKey:@"max_missiles" defaultValue:missiles];
	
	NSString *hud_desc = [shipDict stringForKey:@"hud"];
	if (hud_desc != nil)
	{
		NSDictionary *huddict = [ResourceManager dictionaryFromFilesNamed:hud_desc inFolder:@"Config" andMerge:YES];
		if (huddict)
		{
			[hud release];
			hud = [[HeadUpDisplay alloc] initWithDictionary:huddict];
			[hud setScannerZoom:1.0];
			[hud resizeGuis: huddict];
		}
	}
	

	// set up missiles
	unsigned i;
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)
	{
		[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	for (i = 0; i < missiles; i++)
	{
		missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];   // retain count = 1
	}
	[self setActiveMissile:0];
	

	// set view offsets
	[self setDefaultViewOffsets];
	
	ScanVectorFromString([shipDict stringForKey:@"view_position_forward"], &forwardViewOffset);
	ScanVectorFromString([shipDict stringForKey:@"view_position_aft"], &aftViewOffset);
	ScanVectorFromString([shipDict stringForKey:@"view_position_port"], &portViewOffset);
	ScanVectorFromString([shipDict stringForKey:@"view_position_starboard"], &starboardViewOffset);
	
	NSArray *customViews = [shipDict arrayForKey:@"custom_views"];
	if (customViews != nil)
	{
		[custom_views release];
		custom_views = [customViews mutableCopy];	// FIXME: This is mutable because it's used as a queue rather than using an index. Silly, fix. -- Ahruman
	}
	
	// set weapon offsets
	[self setDefaultWeaponOffsets];
	
	ScanVectorFromString([shipDict stringForKey:@"weapon_position_forward"], &forwardWeaponOffset);
	ScanVectorFromString([shipDict stringForKey:@"weapon_position_aft"], &aftWeaponOffset);
	ScanVectorFromString([shipDict stringForKey:@"weapon_position_port"], &portWeaponOffset);
	ScanVectorFromString([shipDict stringForKey:@"weapon_position_starboard"], &starboardWeaponOffset);
	
	// fuel scoop destination position (where cargo gets sucked into)
	tractor_position = kZeroVector;
	ScanVectorFromString([shipDict stringForKey:@"scoop_position"], &tractor_position);
	
	[sub_entities release];
	sub_entities = nil;

	// exhaust plumes
	NSArray *plumes = [shipDict arrayForKey:@"exhaust"];
	for (i = 0; i < [plumes count]; i++)
	{
		ParticleEntity *exhaust = [[ParticleEntity alloc] initExhaustFromShip:self details:[plumes objectAtIndex:i]];
		[self addExhaust:exhaust];
		[exhaust release];
	}
	
	// other subentities
	NSArray *subs = [shipDict arrayForKey:@"subentities"];
	for (i = 0; i < [subs count]; i++)
	{
		NSArray *details = ScanTokensFromString([subs objectAtIndex:i]);

		if ([details count] == 8)
		{
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

			if ([subdesc isEqual:@"*FLASHER*"])
			{
				ParticleEntity *flasher;
				flasher = [[ParticleEntity alloc]
							initFlasherWithSize:sub_q.z
									  frequency:sub_q.x
										  phase:2.0 * sub_q.y];
				[flasher setColor:[OOColor colorWithCalibratedHue:sub_q.w/360.0
														saturation:1.0
														brightness:1.0
															 alpha:1.0]];
				[flasher setPosition:sub_pos];
				subent = flasher;
			}
			else
			{
				quaternion_normalize(&sub_q);

				subent = [UNIVERSE newShipWithName:subdesc];	// retained
				if (subent == nil)
				{
					// Failing to find a subentity could result in a partial ship, which'd be, y'know, weird.
					return NO;
				}

				if ((self->isStation)&&([subdesc rangeOfString:@"dock"].location != NSNotFound))
					[(StationEntity*)self setDockingPortModel:(ShipEntity*)subent :sub_pos :sub_q];

				if (subent)
				{
					[(ShipEntity*)subent setStatus:STATUS_INACTIVE];
					
					ref = vector_forward_from_quaternion(sub_q);	// VECTOR FORWARD
					
					[(ShipEntity*)subent setReference: ref];
					[(ShipEntity*)subent setPosition: sub_pos];
					[(ShipEntity*)subent setOrientation: sub_q];
					
					[self addSolidSubentityToCollisionRadius:(ShipEntity*)subent];
					
					subent->isSubentity = YES;
				}
				
			}
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

			[subent release];
		}
	}
	
	// rotating subentities
	subentityRotationalVelocity = kIdentityQuaternion;
	ScanQuaternionFromString([shipDict objectForKey:@"rotational_velocity"], &subentityRotationalVelocity);
	
	// Load script
	[script release];			
	script = [OOScript nonLegacyScriptFromFileNamed:[shipDict stringForKey:@"script"] 
										 properties:[NSDictionary dictionaryWithObject:self forKey:@"ship"]];
	
	return YES;
}


- (void) dealloc
{
    [ship_desc release];
	[hud release];
	[commLog release];

    [worldScripts release];
    [mission_variables release];

	[localVariables release];

	[lastTextKey release];

    [extra_equipment release];

	[reputation release];
	[passengers release];
	[passenger_record release];
	[contracts release];
	[contract_record release];
	[missionDestinations release];
	[shipyard_record release];

	[missionBackgroundTexture release];

    [player_name release];
    [shipCommodityData release];

	[specialCargo release];

	[save_path release];

	[custom_views release];
	
	[dockingReport release];

	[self destroySound];

	int i;
	for (i = 0; i < SHIPENTITY_MAX_MISSILES; i++)  [missile_entity[i] release];

	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)  [trumble[i] release];
	
    [super dealloc];
}


- (void) warnAboutHostiles
{
	[self playHostileWarning];
}


- (BOOL) canCollide
{
	switch (status)
	{
		case STATUS_START_GAME:
		case STATUS_DOCKING:
		case STATUS_DOCKED:
		case STATUS_DEAD:
		case STATUS_ESCAPE_SEQUENCE:
			return NO;
		
		default:
			return YES;
	}
}


- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity;
{
	return NSOrderedDescending;  // always the most near
}


- (BOOL) validForAddToUniverse
{
	return YES;
}


double scoopSoundPlayTime = 0.0;
- (void) update:(double)delta_t
{
	unsigned i;
	// update flags
	
	hasMoved = !vector_equal(position, lastPosition);
	hasRotated = !quaternion_equal(orientation, lastOrientation);
	lastPosition = position;
	lastOrientation = orientation;
	
	/*	Moved here from -alertCondition to avoid alert condition checks in
		scripts triggering running of scripts. This wouldn't cause recursion,
		but did cause JS warnings.
		TODO: update alert condition once per frame. Tried this before, but
		there turned out to be complications. See mailing list archive.
		-- Ahruman 20070802
	*/
	if ([self alertCondition] != lastScriptAlertCondition)
	{
		[self doScriptEvent:@"alertConditionChanged"];
		lastScriptAlertCondition = [self alertCondition];
	}

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
	[OOScriptTimer updateTimers];
	
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
				case GUI_SCREEN_LONG_RANGE_CHART:
				case GUI_SCREEN_MANIFEST:
				case GUI_SCREEN_SHIPYARD:
				case GUI_SCREEN_SHORT_RANGE_CHART:
				case GUI_SCREEN_STATUS:
				case GUI_SCREEN_SYSTEM_DATA:
					[self checkScript];
					script_time_check += script_time_interval;
					break;
				
				case GUI_SCREEN_MAIN:
				case GUI_SCREEN_INTRO1:
				case GUI_SCREEN_INTRO2:
				case GUI_SCREEN_MARKET:
				case GUI_SCREEN_OPTIONS:
				case GUI_SCREEN_GAMEOPTIONS:
				case GUI_SCREEN_LOAD:
				case GUI_SCREEN_SAVE:
				case GUI_SCREEN_SAVE_OVERWRITE:
				case GUI_SCREEN_STICKMAPPER:
				case GUI_SCREEN_MISSION:
				case GUI_SCREEN_REPORT:
					break;
			}
		}
	}

	// deal with collisions
	
	[self manageCollisions];
	[self saveToLastFrame];

	[self pollControls:delta_t];

	// update trumbles (moved from end of update: to here)
	OOTrumble** trumbles = [self trumbleArray];
	for (i = [self trumbleCount] ; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
		[trum updateTrumble:delta_t];
	}
	
	if ((status == STATUS_START_GAME)&&(gui_screen != GUI_SCREEN_INTRO1)&&(gui_screen != GUI_SCREEN_INTRO2))
		[self setGuiToIntro1Screen];	//set up demo mode

	if ((status == STATUS_AUTOPILOT_ENGAGED)||(status == STATUS_ESCAPE_SEQUENCE))
	{
		[super update:delta_t];
		[self doBookkeeping:delta_t];
		return;
	}

	if (!dockedStation)
	{
		// do flight routines
		//// velocity stuff
		
		position = vector_add(position, vector_multiply_scalar(velocity, delta_t));
		
		GLfloat velmag = sqrt(magnitude2(velocity));
		if (velmag)
		{
			GLfloat velmag2 = velmag - delta_t * thrust;
			if (velmag2 < 0.0f)
				velmag2 = 0.0f;
			velocity.x *= velmag2 / velmag;
			velocity.y *= velmag2 / velmag;
			velocity.z *= velmag2 / velmag;
			if ([UNIVERSE strict])
			{
				if (velmag2 < OG_ELITE_FORWARD_DRIFT)
				{
					velocity.x += delta_t * v_forward.x * OG_ELITE_FORWARD_DRIFT * 20.0;	// add acceleration
					velocity.y += delta_t * v_forward.y * OG_ELITE_FORWARD_DRIFT * 20.0;
					velocity.z += delta_t * v_forward.z * OG_ELITE_FORWARD_DRIFT * 20.0;
				}
			}
		}

		[self applyRoll:delta_t*flightRoll andClimb:delta_t*flightPitch];
		if (flightYaw != 0.0)
			[self applyYaw:delta_t*flightYaw];
		[self moveForward:delta_t*flightSpeed];
	}

	if (status == STATUS_IN_FLIGHT)
	{
		[self doBookkeeping:delta_t];
	}

	if (status == STATUS_LAUNCHING)
	{
		if ([UNIVERSE breakPatternOver])
		{
			// time to check the script!
			[self checkScript];
			// next check in 10s

			status = STATUS_IN_FLIGHT;
			[self doScriptEvent:@"shipLaunchedFromStation"];
		}
	}

	if (status == STATUS_WITCHSPACE_COUNTDOWN)
	{
		[self doBookkeeping:delta_t];
		witchspaceCountdown -= delta_t;
		if (witchspaceCountdown < 0.0)  witchspaceCountdown = 0.0;
		if (galactic_witchjump)
			[UNIVERSE displayCountdownMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[witch-galactic-in-f-seconds]"), witchspaceCountdown] forCount:1.0];
		else
			[UNIVERSE displayCountdownMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[witch-to-@-in-f-seconds]"), [UNIVERSE getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
		if (witchspaceCountdown == 0.0)
		{
			BOOL go = YES;

			// check nearby masses
			ShipEntity* blocker = [UNIVERSE entityForUniversalID:[self checkShipsInVicinityForWitchJumpExit]];
			if (blocker)
			{
				[UNIVERSE clearPreviousMessage];
				[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[witch-blocked-by-@]"), [blocker name]] forCount: 4.5];
				if (![UNIVERSE playCustomSound:@"[witch-blocked-by-@]"])
					[witchAbortSound play];
				status = STATUS_IN_FLIGHT;
				[self doScriptEvent:@"playerJumpFailed" withArgument:@"blocked"];
				go = NO;
			}
			
			// check max distance permitted
			double jump_distance = 0.0;
			if (!galactic_witchjump)
			{
				jump_distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
				if (jump_distance > 7.0)
				{
					[UNIVERSE clearPreviousMessage];
					[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-too-far]") forCount: 4.5];
					if (![UNIVERSE playCustomSound:@"[witch-too-far]"])
						[witchAbortSound play];
					status = STATUS_IN_FLIGHT;
					[self doScriptEvent:@"playerJumpFailed" withArgument:@"too far"];
					go = NO;
				}
			}
			
			// check fuel level
			double		fuel_required = 10.0 * jump_distance;
			if (galactic_witchjump)
				fuel_required = 0.0;
			if (fuel < fuel_required)
			{
				[UNIVERSE clearPreviousMessage];
				[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-no-fuel]") forCount: 4.5];
				if (![UNIVERSE playCustomSound:@"[witch-no-fuel]"])
					[witchAbortSound play];
				status = STATUS_IN_FLIGHT;
				[self doScriptEvent:@"playerJumpFailed" withArgument:@"insufficient fuel"];
				go = NO;
			}

			if (go)
			{
				[self safeAllMissiles];
				[UNIVERSE setViewDirection:VIEW_FORWARD];
				currentWeaponFacing = VIEW_FORWARD;
				if (galactic_witchjump)
					[self enterGalacticWitchspace];
				else
					[self enterWitchspace];
			}
		}
	}

	if (status == STATUS_EXITING_WITCHSPACE)
	{
		if ([UNIVERSE breakPatternOver])
		{
			// time to check the script!
			[self checkScript];
			// next check in 10s
			[self resetScriptTimer];	// reset the in-system timer

			// announce arrival
			if ([UNIVERSE planet])
				[UNIVERSE addMessage:[NSString stringWithFormat:@" %@. ",[UNIVERSE getSystemName:system_seed]] forCount:3.0];
			else
				[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[witch-engine-malfunction]") forCount:3.0];

			status = STATUS_IN_FLIGHT;
			[self doScriptEvent:@"shipExitedWitchspace"];
		}
	}

	if (status == STATUS_DOCKING)
	{
		if ([UNIVERSE breakPatternOver])
		{
			[self docked];		// bookkeeping for docking
		}
	}

	if ((status == STATUS_DEAD)&&(shot_time > 30.0))
	{
		BOOL was_mouse_control_on = mouse_control_on;
		[UNIVERSE game_over];				//  we restart the UNIVERSE
		mouse_control_on = was_mouse_control_on;
	}

	
	// check for lost ident target and ensure the ident system is actually scanning
	
	if (ident_engaged)
	{
		if (missile_status == MISSILE_STATUS_TARGET_LOCKED)
		{
			ShipEntity*	e = [UNIVERSE entityForUniversalID:primaryTarget];
			if ((e == nil)||(e->zero_distance > SCANNER_MAX_RANGE2)||
				((e->isShip)&&([e isCloaked]))||	// checks for cloaked ships
				((e->isShip)&&(!has_military_scanner_filter)&&([e isJammingScanning])))	// checks for activated jammer
			{
				if (!suppressTargetLost)
				{
					[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[target-lost]") forCount:3.0];
					if (![UNIVERSE playCustomSound:@"[target-lost]"])
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

	
	// check each unlaunched missile's target still exists and is in-range
	
	for (i = 0; i < max_missiles; i++)
	{
		if ((missile_entity[i])&&([missile_entity[i] primaryTargetID] != NO_TARGET))
		{
			ShipEntity*	target_ship = (ShipEntity *)[missile_entity[i] primaryTarget];
			if ((!target_ship)||(target_ship->zero_distance > SCANNER_MAX_RANGE2))
			{
				[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[target-lost]") forCount:3.0];
				if (![UNIVERSE playCustomSound:@"[target-lost]"])
					[self boop];
				[missile_entity[i] removeTarget:nil];
				if ((i == activeMissile)&&(!ident_engaged))
				{
					primaryTarget = NO_TARGET;
					missile_status = MISSILE_STATUS_SAFE;
				}
			}
		}
	}

	if ((missile_status == MISSILE_STATUS_ARMED)&&(ident_engaged||[missile_entity[activeMissile] isMissile])&&((status == STATUS_IN_FLIGHT)||(status == STATUS_WITCHSPACE_COUNTDOWN)))
	{
		int first_target_id = [UNIVERSE getFirstEntityTargettedByPlayer:self];
		if (first_target_id != NO_TARGET)
		{
			Entity *first_target = [UNIVERSE entityForUniversalID:first_target_id];
			if ([first_target isKindOfClass:[ShipEntity class]])
			{
				[self addTarget: first_target];
				missile_status = MISSILE_STATUS_TARGET_LOCKED;
				if ((missile_entity[activeMissile])&&(!ident_engaged))
					[missile_entity[activeMissile] addTarget:first_target];
				[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-locked-onto-@]"), (ident_engaged)? @"Ident system": @"Missile", [(ShipEntity *)first_target name]] forCount:4.5];
				if (ident_engaged)
				{
					if (![UNIVERSE playCustomSound:@"[ident-locked-on]"])
						[self beep];
				}
				else
				{
					if (![UNIVERSE playCustomSound:@"[missile-locked-on]"])
						[self beep];
				}
			}
		}
	}
}


- (void) doBookkeeping:(double) delta_t
{
	// Bookeeping;
	
	double speed_delta = 5.0 * thrust;
	
	PlanetEntity*	sun = [UNIVERSE sun];
	double	external_temp = 0;
	GLfloat	air_friction = 0.0;
	if (UNIVERSE)
		air_friction = 0.5 * [UNIVERSE airResistanceFactor];

	// cool all weapons
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
	
	switch (currentWeaponFacing)
	{
		case VIEW_GUI_DISPLAY:
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
		case VIEW_CUSTOM:
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
			if (energy < maxEnergy)
			{
				energy += delta_t * CLOAKING_DEVICE_ENERGY_RATE;
				if (energy > maxEnergy)
					energy = maxEnergy;
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

	if (energy < maxEnergy)
	{
		double energy_multiplier = 1.0 + 0.1 * energy_unit; // 1.5x recharge with normal energy unit, 2x with naval!
		energy += energy_recharge_rate * energy_multiplier * delta_t;
		if (energy > maxEnergy)
			energy = maxEnergy;
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
			[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[ecm-out-of-juice]") forCount:3.0];
		}
		if ([UNIVERSE getTime] > ecm_start_time + ECM_DURATION)
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
		if ([[UNIVERSE sun] goneNova])
			external_temp *= 100;

		// do Revised sun-skimming check here...
		if ((has_scoop)&&(alt1 > 0.75)&&(fuel < PLAYER_MAX_FUEL))
		{
			fuel_accumulator += delta_t * flightSpeed * 0.010;
			scoopsActive = YES;
			while (fuel_accumulator > 1.0)
			{
				fuel ++;
				fuel_accumulator -= 1.0;
			}
			if (fuel > PLAYER_MAX_FUEL)	fuel = PLAYER_MAX_FUEL;
			[UNIVERSE displayCountdownMessage:ExpandDescriptionForCurrentSystem(@"[fuel-scoop-active]") forCount:1.0];
		}
	}

	if ((status != STATUS_AUTOPILOT_ENGAGED)&&(status != STATUS_ESCAPE_SEQUENCE))
	{
		// work on the cabin temperature
		
		ship_temperature += delta_t * flightSpeed * air_friction / heat_insulation;	// wind_speed
		
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
		[[UNIVERSE entityForUniversalID:found_target] becomeExplosion];	// blow up the doppelganger
		[self setTargetToStation];
		if ([self primaryTarget])
		{
			// restore player ship
			ShipEntity *player_ship = [UNIVERSE newShipWithName:ship_desc];	// retained
			if (player_ship)
			{
				// FIXME: this should use OOShipType, which should exist. -- Ahruman
				[self setMesh:[player_ship mesh]];
				[player_ship release];						// we only wanted it for its polygons!
			}
			[UNIVERSE setViewDirection:VIEW_FORWARD];
			[self enterDock:(StationEntity *)[self primaryTarget]];
		}
	}
	
	
	// MOVED THE FOLLOWING FROM PLAYERENTITY POLLFLIGHTCONTROLS:
	travelling_at_hyperspeed = (flightSpeed > maxFlightSpeed);
	if (hyperspeed_engaged)
	{
		// increase speed up to maximum hyperspeed
		if (flightSpeed < maxFlightSpeed * HYPERSPEED_FACTOR)
			flightSpeed += speed_delta * delta_t * HYPERSPEED_FACTOR;
		if (flightSpeed > maxFlightSpeed * HYPERSPEED_FACTOR)
			flightSpeed = maxFlightSpeed * HYPERSPEED_FACTOR;

		// check for mass lock
		hyperspeed_locked = [self massLocked];

		if (hyperspeed_locked)
		{
			if (![UNIVERSE playCustomSound:@"[jump-mass-locked]"])
				[self boop];
			[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[jump-mass-locked]") forCount:4.5];
			hyperspeed_engaged = NO;
		}
	}
	else
	{
		if (afterburner_engaged)
		{
			if (flightSpeed < maxFlightSpeed * AFTERBURNER_FACTOR)
				flightSpeed += speed_delta * delta_t * AFTERBURNER_FACTOR;
			if (flightSpeed > maxFlightSpeed * AFTERBURNER_FACTOR)
				flightSpeed = maxFlightSpeed * AFTERBURNER_FACTOR;
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
				flightSpeed -= speed_delta * delta_t * HYPERSPEED_FACTOR;
				if (flightSpeed < maxFlightSpeed)
					flightSpeed = maxFlightSpeed;
			}
		}
	}
	
	

	// fuel leakage
	
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
		unsigned i;
		for (i = 0; i < [sub_entities count]; i++)
			[(Entity *)[sub_entities objectAtIndex:i] update:delta_t];
	}
}


- (void) applyRoll:(GLfloat) roll1 andClimb:(GLfloat) climb1
{
	if (roll1 == 0.0 && climb1 == 0.0 && hasRotated == NO)
		return;

	if (roll1)
		quaternion_rotate_about_z(&orientation, -roll1);
	if (climb1)
		quaternion_rotate_about_x(&orientation, -climb1);
	
	/*	Bugginess may put us in a state where the orientation quat is all
		zeros, at which point it’s impossible to move.
	*/
	if (EXPECT_NOT(quaternion_equal(orientation, kZeroQuaternion)))
	{
		if (!quaternion_equal(lastOrientation, kZeroQuaternion))
		{
			orientation = lastOrientation;
		}
		else
		{
			orientation = kIdentityQuaternion;
		}
	}
	
    quaternion_normalize(&orientation);	// probably not strictly necessary but good to do to keep orientation sane
    quaternion_into_gl_matrix(orientation, rotMatrix);

	v_right.x = rotMatrix[0];
	v_right.y = rotMatrix[4];
	v_right.z = rotMatrix[8];

	v_up.x = rotMatrix[1];
	v_up.y = rotMatrix[5];
	v_up.z = rotMatrix[9];

	v_forward.x = rotMatrix[2];
	v_forward.y = rotMatrix[6];
	v_forward.z = rotMatrix[10];

	orientation.w = -orientation.w;
	quaternion_into_gl_matrix(orientation, playerRotMatrix);	// this is the rotation similar to ordinary ships
	orientation.w = -orientation.w;
}

/*
 * This method should not be necessary, but when I replaced the above with applyRoll:andClimb:andYaw, the
 * ship went crazy. Perhaps applyRoll:andClimb is called from one of the subclasses and that was messing
 * things up.
 */
- (void) applyYaw:(GLfloat) yaw
{
	quaternion_rotate_about_y(&orientation, -yaw);

    quaternion_normalize(&orientation);	// probably not strictly necessary but good to do to keep orientation sane
    quaternion_into_gl_matrix(orientation, rotMatrix);

	v_right.x = rotMatrix[0];
	v_right.y = rotMatrix[4];
	v_right.z = rotMatrix[8];

	v_up.x = rotMatrix[1];
	v_up.y = rotMatrix[5];
	v_up.z = rotMatrix[9];

	v_forward.x = rotMatrix[2];
	v_forward.y = rotMatrix[6];
	v_forward.z = rotMatrix[10];

	orientation.w = -orientation.w;
	quaternion_into_gl_matrix(orientation, playerRotMatrix);	// this is the rotation similar to ordinary ships
	orientation.w = -orientation.w;
}


- (GLfloat *) drawRotationMatrix	// override to provide the 'correct' drawing matrix
{
    return playerRotMatrix;
}


- (void) moveForward:(double) amount
{
	distanceTravelled += amount;
	position = vector_add(position, vector_multiply_scalar(v_forward, amount));
}


- (Vector) viewpointOffset
{
	if ([UNIVERSE breakPatternHide])
		return kZeroVector;	// center view for break pattern

	switch ([UNIVERSE viewDirection])
	{
		case VIEW_FORWARD:
			return forwardViewOffset;
		case VIEW_AFT:
			return aftViewOffset;
		case VIEW_PORT:
			return portViewOffset;
		case VIEW_STARBOARD:
			return starboardViewOffset;
		/* GILES custom viewpoints */
		case VIEW_CUSTOM:
			return customViewOffset;
		/* -- */
		
		default:
			break;
	}

	return kZeroVector;
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{
	if ((status == STATUS_DEAD)||(status == STATUS_COCKPIT_DISPLAY)||(status == STATUS_DOCKED)||(status == STATUS_START_GAME)||[UNIVERSE breakPatternHide])
		return;	// don't draw

	[super drawEntity: immediate : translucent];
}


- (BOOL) massLocked
{
	return ((alertFlags & ALERT_FLAG_MASS_LOCK) != 0);
}


- (BOOL) atHyperspeed
{
	return travelling_at_hyperspeed;
}


- (Vector) velocityVector
{
	Vector result = v_forward;
	result.x *= flightSpeed;
	result.y *= flightSpeed;
	result.z *= flightSpeed;
	return result;
}


//			dial routines = all return 0.0 .. 1.0 or -1.0 .. 1.0

- (NSString *) ship_desc
{
	return ship_desc;
}


- (StationEntity *) dockedStation
{
	return dockedStation;
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
	return showDemoShips;
}


- (GLfloat) dialRoll
{
	GLfloat result = flightRoll / max_flight_roll;
	if ((result < 1.0f)&&(result > -1.0f))
		return result;
	if (result > 0.0f)
		return 1.0f;
	return -1.0f;
}


- (GLfloat) dialPitch
{
	GLfloat result = flightPitch / max_flight_pitch;
	if ((result < 1.0f)&&(result > -1.0f))
		return result;
	if (result > 0.0f)
		return 1.0f;
	return -1.0f;
}


- (GLfloat) dialSpeed
{
	GLfloat result = flightSpeed / maxFlightSpeed;
	if (result < 1.0f)
		return result;
	return 1.0f;
}


- (GLfloat) dialHyperSpeed
{
	return flightSpeed / maxFlightSpeed;
}


- (GLfloat) dialForwardShield
{
	GLfloat result = forward_shield / (GLfloat)PLAYER_MAX_FORWARD_SHIELD;
	if (result < 1.0f)
		return result;
	return 1.0f;
}


- (GLfloat) dialAftShield
{
	GLfloat result = aft_shield / (GLfloat)PLAYER_MAX_AFT_SHIELD;
	if (result < 1.0f)
		return result;
	return 1.0f;
}


- (GLfloat) dialEnergy
{
	GLfloat result = energy / maxEnergy;
	if (result < 1.0f)
		return result;
	return 1.0f;
}


- (GLfloat) dialMaxEnergy
{
	return maxEnergy;
}


- (GLfloat) dialFuel
{
	if (fuel <= 0.0f)
		return 0.0f;
	if (fuel > (GLfloat)PLAYER_MAX_FUEL)
		return 1.0f;
	return (GLfloat)fuel / (GLfloat)PLAYER_MAX_FUEL;
}


- (GLfloat) dialHyperRange
{
	GLfloat distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
	return 10.0f * distance / (GLfloat)PLAYER_MAX_FUEL;
}


- (GLfloat) hullHeatLevel
{
	GLfloat result = (GLfloat)ship_temperature / (GLfloat)SHIP_MAX_CABIN_TEMP;
	if (result < 1.0)
		return result;
	return 1.0;
}


- (GLfloat) laserHeatLevel
{
	GLfloat result = (GLfloat)weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


- (GLfloat) dialAltitude
{
	// find nearest planet type entity...
	if (!UNIVERSE)
		return 1.0;

	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	PlanetEntity* nearest_planet = nil;
	int i;
	for (i = 0; ((i < ent_count)&&(!nearest_planet)); i++)
		if ((uni_entities[i]->isPlanet) && (uni_entities[i]->status != STATUS_COCKPIT_DISPLAY))
			nearest_planet = [uni_entities[i] retain];		//	retained

	if (!nearest_planet)
		return 1.0;

	double  zd = nearest_planet->zero_distance;
	GLfloat  cr = nearest_planet->collision_radius;
	GLfloat alt = sqrt(zd) - cr;

	[nearest_planet release];

	alt /= (GLfloat)PLAYER_DIAL_MAX_ALTITUDE;

	if (alt > 1.0)
		alt = 1.0;
	if (alt < 0.0)
		alt = 0.0;

	return alt;
}


- (double) clockTime
{
	return ship_clock;
}


- (BOOL) clockAdjusting
{
	return ship_clock_adjust != 0;
}


- (NSString*) dial_clock
{
	return ClockToString(ship_clock, ship_clock_adjust != 0);
}


- (NSString*) dial_clock_adjusted
{
	return ClockToString(ship_clock + ship_clock_adjust, NO);
}


- (NSString*) dial_fpsinfo
{
	return [NSString stringWithFormat:@"FPS: %3d", fps_counter];
}


- (NSString*) dial_objinfo
{
	return [NSString stringWithFormat:@"Objs: %3d", [UNIVERSE obj_count]];
}


- (unsigned) countMissiles
{
	unsigned n_missiles = 0;
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i])
			n_missiles++;
	}
	return n_missiles;
}


- (OOMissileStatus) dialMissileStatus
{
	return missile_status;
}


- (int) dialFuelScoopStatus
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


- (NSMutableArray*) commLog
{
	unsigned			count;
	
	assert(kCommLogTrimSize < kCommLogTrimThreshold);
	
	if (commLog != nil)
	{
		count = [commLog count];
		if (count >= kCommLogTrimThreshold)
		{
			[commLog removeObjectsInRange:NSMakeRange(kCommLogTrimSize, count - kCommLogTrimSize)];
		}
	}
	else
	{
		commLog = [[NSMutableArray alloc] init];
	}
	
	return commLog;
}


- (OOCompassMode) compassMode
{
	return compassMode;
}


- (void) setCompassMode:(OOCompassMode) value
{
	compassMode = value;
}


- (void) setNextCompassMode
{
	switch (compassMode)
	{
		case COMPASS_MODE_BASIC:
		case COMPASS_MODE_PLANET:
			if ([self checkForAegis] == AEGIS_NONE)
				[self setCompassMode:COMPASS_MODE_SUN];
			else
				[self setCompassMode:COMPASS_MODE_STATION];
			break;
		case COMPASS_MODE_STATION:
			[self setCompassMode:COMPASS_MODE_SUN];
			break;
		case COMPASS_MODE_SUN:
			if ([self primaryTarget])
				[self setCompassMode:COMPASS_MODE_TARGET];
			else
			{
				nextBeaconID = [[UNIVERSE firstBeacon] universalID];
				while ((nextBeaconID != NO_TARGET)&&[[UNIVERSE entityForUniversalID:nextBeaconID] isJammingScanning])
				{
					nextBeaconID = [[UNIVERSE entityForUniversalID:nextBeaconID] nextBeaconID];
				}
				
				if (nextBeaconID != NO_TARGET)
					[self setCompassMode:COMPASS_MODE_BEACONS];
				else
					[self setCompassMode:COMPASS_MODE_PLANET];
			}
			break;
		case COMPASS_MODE_TARGET:
			nextBeaconID = [[UNIVERSE firstBeacon] universalID];
			while ((nextBeaconID != NO_TARGET)&&[[UNIVERSE entityForUniversalID:nextBeaconID] isJammingScanning])
			{
				nextBeaconID = [[UNIVERSE entityForUniversalID:nextBeaconID] nextBeaconID];
			}
			
			if (nextBeaconID != NO_TARGET)
				[self setCompassMode:COMPASS_MODE_BEACONS];
			else
				[self setCompassMode:COMPASS_MODE_PLANET];
			break;
		case COMPASS_MODE_BEACONS:
			do
			{
				nextBeaconID = [[UNIVERSE entityForUniversalID:nextBeaconID] nextBeaconID];
			} while ((nextBeaconID != NO_TARGET)&&[[UNIVERSE entityForUniversalID:nextBeaconID] isJammingScanning]);
			
			if (nextBeaconID == NO_TARGET)
				[self setCompassMode:COMPASS_MODE_PLANET];
			break;
	}
}


- (unsigned) activeMissile
{
	return activeMissile;
}


- (void) setActiveMissile: (unsigned) value
{
	activeMissile = value;
}


- (unsigned) dialMaxMissiles
{
	return max_missiles;
}


- (BOOL) dialIdentEngaged
{
	return ident_engaged;
}


- (NSString *) dialTargetName
{
	Entity* target_entity = [UNIVERSE entityForUniversalID:primaryTarget];
	if ((target_entity)&&(target_entity->isShip))
		return [(ShipEntity*)target_entity identFromShip:self];
	else
		return @"No target";
}


- (ShipEntity *) missileForStation: (unsigned) value
{
	if (value < max_missiles)  return missile_entity[value];
	return nil;
}


- (void) sortMissiles
{
	//	puts all missiles into the first available slots
	
	unsigned i;
	missiles = [self countMissiles];
	for (i = 0; i < missiles; i++)
	{
		if (missile_entity[i] == nil)
		{
			unsigned j;
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


- (void) safeAllMissiles
{
	//	sets all missile targets to NO_TARGET
	
	unsigned i;
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


- (void) selectNextMissile
{
	unsigned i;
	for (i = 1; i < max_missiles; i++)
	{
		int next_missile = (activeMissile + i) % max_missiles;
		if (missile_entity[next_missile])
		{
			// if this is a missile then select it
			if (missile_entity[next_missile])	// if it exists
			{
				[self setActiveMissile:next_missile];
				if (([missile_entity[next_missile] isMissile])&&([missile_entity[next_missile] primaryTarget] != nil))
				{
					// copy the missile's target
					[self addTarget:[missile_entity[next_missile] primaryTarget]];
					missile_status = MISSILE_STATUS_TARGET_LOCKED;
				}
				else
					missile_status = MISSILE_STATUS_SAFE;
				return;
			}
		}
	}
}


- (void) clearAlertFlags
{
	alertFlags = 0;
}


- (int) alertFlags
{
	return alertFlags;
}


- (void) setAlertFlag:(int)flag to:(BOOL)value
{
	if (value)
	{
		alertFlags |= flag;
	}
	else
	{
		int comp = ~flag;
		alertFlags &= comp;
	}
}


- (OOAlertCondition) alertCondition
{
	OOAlertCondition old_alert_condition = alertCondition;
	alertCondition = ALERT_CONDITION_GREEN;
	[self setAlertFlag:ALERT_FLAG_DOCKED to:(status == STATUS_DOCKED)];
	if (alertFlags & ALERT_FLAG_DOCKED)
	{
		alertCondition = ALERT_CONDITION_DOCKED;
	}
	else
	{
		if (alertFlags != 0)
			alertCondition = ALERT_CONDITION_YELLOW;
		if (alertFlags > ALERT_FLAG_YELLOW_LIMIT)
			alertCondition = ALERT_CONDITION_RED;
	}
	if ((alertCondition == ALERT_CONDITION_RED)&&(old_alert_condition < ALERT_CONDITION_RED))
	{
		[self playAlertConditionRed];
	}
	
	return alertCondition;
}

/////////////////////////////////////////////////////////////////////


- (void) interpretAIMessage:(NSString *)ms
{
	if ([ms isEqual:@"HOLD_FULL"])
	{
		if (![UNIVERSE playCustomSound:@"[hold-full]"])
			[self beep];
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[hold-full]") forCount:4.5];
	}

	if ([ms isEqual:@"INCOMING_MISSILE"])
	{
		if (![UNIVERSE playCustomSound:@"[incoming-missile]"])  [warningSound play];
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[incoming-missile]") forCount:4.5];
	}

	if ([ms isEqual:@"ENERGY_LOW"])
	{
		[UNIVERSE playCustomSound:@"[energy-low]"];
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[energy-low]") forCount:6.0];
	}

	if ([ms isEqual:@"ECM"])  [self playECMSound];

	if ([ms isEqual:@"DOCKING_REFUSED"]&&(status == STATUS_AUTOPILOT_ENGAGED))
	{
		if (![UNIVERSE playCustomSound:@"[autopilot-denied]"])  [warningSound play];
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[autopilot-denied]") forCount:4.5];
		autopilot_engaged = NO;
		primaryTarget = NO_TARGET;
		status = STATUS_IN_FLIGHT;
		if (ootunes_on)
		{
			// ootunes - play inflight music
			[[UNIVERSE gameController] playiTunesPlaylist:@"Oolite-Inflight"];
			docking_music_on = NO;
		}
		[self doScriptEvent:@"playerDockingRefused"];
	}

	// aegis messages to advanced compass so in planet mode it behaves like the old compass
	if (compassMode != COMPASS_MODE_BASIC)
	{
		if ([ms isEqual:@"AEGIS_CLOSE_TO_PLANET"]&&(compassMode == COMPASS_MODE_PLANET))
		{
			[UNIVERSE playCustomSound:@"[aegis-planet]"];
			[self setCompassMode:COMPASS_MODE_STATION];
		}
		if ([ms isEqual:@"AEGIS_IN_DOCKING_RANGE"]&&(compassMode == COMPASS_MODE_PLANET))
		{
			[UNIVERSE playCustomSound:@"[aegis-station]"];
			[self setCompassMode:COMPASS_MODE_STATION];
		}
		if ([ms isEqual:@"AEGIS_NONE"]&&(compassMode == COMPASS_MODE_STATION))
		{
			[self setCompassMode:COMPASS_MODE_PLANET];
		}
	}
}


- (BOOL) mountMissile: (ShipEntity *)missile
{
	if (missile == nil)  return NO;
	
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i] == nil)
		{
			missile_entity[i] = [missile retain];
			return YES;
		}
	}
	missiles = [self countMissiles];
	return NO;
}


- (BOOL) fireMissile
{
	ShipEntity *missile = missile_entity[activeMissile];	// retain count is 1

	if (missile == nil)
		return NO;

	double mcr = missile->collision_radius;

	if ([missile isMine]&&((missile_status == MISSILE_STATUS_ARMED)||(missile_status == MISSILE_STATUS_TARGET_LOCKED)))
	{
		BOOL launchedOK = [self launchMine:missile];
		if (launchedOK)
		{
			[UNIVERSE playCustomSound:@"[mine-launched]"];
			[missile release];	//  release
		}
		missile_entity[activeMissile] = nil;
		[self selectNextMissile];
		missiles = [self countMissiles];
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
	ScanVectorFromString([shipinfoDictionary objectForKey:@"missile_launch_position"], &start);
	
	double  throw_speed = 250.0;
	Quaternion q1 = orientation;
	q1.w = -q1.w;   // player view is reversed remember!

	Entity  *target = [self primaryTarget];

	// select a new active missile and decrease the missiles count
	missile_entity[activeMissile] = nil;
	[self selectNextMissile];
	missiles = [self countMissiles];


	v_eject = unit_vector(&start);

	// check if start is within bounding box...
	while (	(start.x > boundingBox.min.x - mcr)&&(start.x < boundingBox.max.x + mcr)&&
			(start.y > boundingBox.min.y - mcr)&&(start.y < boundingBox.max.y + mcr)&&
			(start.z > boundingBox.min.z - mcr)&&(start.z < boundingBox.max.z + mcr))
	{
		start.x += mcr * v_eject.x;	start.y += mcr * v_eject.y;	start.z += mcr * v_eject.z;
	}

	vel.x = (flightSpeed + throw_speed) * v_forward.x;
	vel.y = (flightSpeed + throw_speed) * v_forward.y;
	vel.z = (flightSpeed + throw_speed) * v_forward.z;

	origin.x = position.x + v_right.x * start.x + v_up.x * start.y + v_forward.x * start.z;
	origin.y = position.y + v_right.y * start.x + v_up.y * start.y + v_forward.y * start.z;
	origin.z = position.z + v_right.z * start.x + v_up.z * start.y + v_forward.z * start.z;

	[missile setPosition:origin];
	[missile setScanClass: CLASS_MISSILE];
	[missile addTarget:target];
	[missile setOrientation:q1];
	[missile setStatus: STATUS_IN_FLIGHT];  // necessary to get it going!
	[missile setVelocity: vel];
	[missile setSpeed:150.0];
	[missile setOwner:self];
	[missile setDistanceTravelled:0.0];
	//debug
	[missile setReportAIMessages:YES];
	
	[UNIVERSE addEntity:missile];
	[missile release];

	[(ShipEntity *)target setPrimaryAggressor:self];
	[[(ShipEntity *)target getAI] reactToMessage:@"INCOMING_MISSILE"];

	[UNIVERSE playCustomSound:@"[missile-launched]"];

	return YES;
}


- (BOOL) launchMine:(ShipEntity*) mine
{
	if (!mine)
		return NO;
	double  mine_speed = 500.0;
	[self dumpItem: mine];
	Vector mvel = [mine velocity];
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
		ecm_start_time = [UNIVERSE getTime];
		return YES;
	}
	else
		return NO;
}


- (BOOL) fireEnergyBomb
{
	NSArray* targets = [UNIVERSE getEntitiesWithinRange:SCANNER_MAX_RANGE ofEntity:self];
	if ([targets count] > 0)
	{
		unsigned i;
		for (i = 0; i < [targets count]; i++)
		{
			Entity *e2 = [targets objectAtIndex:i];
			if (e2->isShip)
				[(ShipEntity *)e2 takeEnergyDamage:1000 from:self becauseOf:self];
		}
	}
	[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[energy-bomb-activated]") forCount:4.5];
	[destructionSound play];
	
	return YES;
}



- (BOOL) fireMainWeapon
{
	int weapon_to_be_fired = [self weaponForView: currentWeaponFacing];

	if (weapon_temp / PLAYER_MAX_WEAPON_TEMP >= 0.85)
	{
		[UNIVERSE playCustomSound:@"[weapon-overheat]"];
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[weapon-overheat]") forCount:3.0];
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
			weaponRange = 5000;
			break;
		case WEAPON_PULSE_LASER :
			weapon_energy =						15.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.5;
			weaponRange = 12500;
			break;
		case WEAPON_BEAM_LASER :
			weapon_energy =						15.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.1;
			weaponRange = 15000;
			break;
		case WEAPON_MINING_LASER :
			weapon_energy =						50.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				2.5;
			weaponRange = 12500;
			break;
		case WEAPON_THARGOID_LASER :
		case WEAPON_MILITARY_LASER :
			weapon_energy =						23.0;
			weapon_energy_per_shot =			1.0;
			weapon_heat_increment_per_shot =	8.0;
			weapon_reload_time =				0.1;
			weaponRange = 30000;
			break;
	}

	if (energy <= weapon_energy_per_shot)
	{
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[weapon-out-of-juice]") forCount:3.0];
		return NO;
	}

	using_mining_laser = (weapon_to_be_fired == WEAPON_MINING_LASER);

	energy -= weapon_energy_per_shot;

	switch (currentWeaponFacing)
	{
		case VIEW_GUI_DISPLAY:
		case VIEW_NONE:
		case VIEW_BREAK_PATTERN:
		case VIEW_FORWARD:
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
		case VIEW_CUSTOM:
			break;
	}
	
	switch (weapon_to_be_fired)
	{
		case WEAPON_PLASMA_CANNON :
			[self firePlasmaShot:10.0:1000.0:[OOColor greenColor]];
			return YES;
			break;

		case WEAPON_PULSE_LASER:
		case WEAPON_BEAM_LASER:
		case WEAPON_MINING_LASER:
		case WEAPON_MILITARY_LASER:
			[self fireLaserShotInDirection: currentWeaponFacing];
			return YES;
			break;
		
		case WEAPON_THARGOID_LASER:
			break;
	}
	return NO;
}


- (OOWeaponType) weaponForView:(OOViewID)view
{
	if (view == VIEW_CUSTOM)
		view = currentWeaponFacing;
	
	switch (view)
	{
		case VIEW_PORT :
			return port_weapon;
		case VIEW_STARBOARD :
			return starboard_weapon;
		case VIEW_AFT :
			return aft_weapon;
		case VIEW_FORWARD :
			return forward_weapon;
		default :
			return WEAPON_NONE;
	}
}


- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	Vector		rel_pos;
	double		d_forward;
	BOOL		internal_damage = NO;	// base chance

	if (status == STATUS_DEAD)  return;
	if (amount == 0.0)  return;

	[ent retain];
	[other retain];
	rel_pos = (ent != nil) ? [ent position] : kZeroVector;
	rel_pos = vector_subtract(rel_pos, position);
	
	d_forward = dot_product(rel_pos, v_forward);
	
	if (damageSound)
	{
		if ([damageSound isPlaying]) [damageSound stop];
		[damageSound play];
	}

	// firing on an innocent ship is an offence
	if ((other)&&(other->isShip))
	{
		[self broadcastHitByLaserFrom:(ShipEntity*) other];
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

	if (amount > 0.0)
	{
		internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems
		energy -= amount;
		if (scrapeDamageSound)
		{
			if ([scrapeDamageSound isPlaying])  [scrapeDamageSound stop];
			[scrapeDamageSound play];
		}
		ship_temperature += amount;
	}

	if ((energy <= 0.0)||(ship_temperature > SHIP_MAX_CABIN_TEMP))
	{
		if ((other)&&(other->isShip))
		{
			ShipEntity* hunter = (ShipEntity *)other;
			[hunter collectBountyFor:self];
			if ([hunter primaryTarget] == (Entity *)self)
			{
				[hunter removeTarget:(Entity *)self];
				[[hunter getAI] message:@"TARGET_DESTROYED"];
			}
		}
		
		[self getDestroyedBy:other context:@"energy damage"];
	}

	if (internal_damage)  [self takeInternalDamage];

	[ent release];
	[other release];
	
}


- (void) takeScrapeDamage:(double) amount from:(Entity *) ent
{
	Vector  rel_pos;
	double  d_forward;
	BOOL	internal_damage = NO;	// base chance

	if (status == STATUS_DEAD)
		return;

	[ent retain];
	rel_pos = (ent)? ent->position : kZeroVector;

	rel_pos.x -= position.x;
	rel_pos.y -= position.y;
	rel_pos.z -= position.z;

	d_forward   =   dot_product(rel_pos, v_forward);

	if (scrapeDamageSound)
	{
		if ([scrapeDamageSound isPlaying])  [scrapeDamageSound stop];
		[scrapeDamageSound play];
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
			if ([hunter primaryTarget] == (Entity *)self)
			{
				[hunter removeTarget:(Entity *)self];
				[[hunter getAI] message:@"TARGET_DESTROYED"];
			}
		}
		
		[self getDestroyedBy:ent context:@"scrape damage"];
	}

	if (internal_damage)  [self takeInternalDamage];

	
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
	{
		[self getDestroyedBy:nil context:@"heat damage"];
	}
	else
	{
		// warn if I'm low on energy
		if (energy < maxEnergy *0.25)
			[shipAI message:@"ENERGY_LOW"];
	}
}


- (int)launchEscapeCapsule
{
	ShipEntity		*doppelganger = nil;
	ShipEntity		*escapePod = nil;
	Vector			vel;
	Vector			origin = position;
	int				result = NO;
	Quaternion		q1 = orientation;

	status = STATUS_ESCAPE_SEQUENCE;	// firstly
	ship_clock_adjust += 43200 + 5400 * (ranrot_rand() & 127);	// add up to 8 days until rescue!

	q1.w = -q1.w;   // player view is reversed remember!

	flightSpeed = OOMax_f(flightSpeed, 50.0f);
	vel = vector_multiply_scalar(v_forward, flightSpeed);

	doppelganger = [UNIVERSE newShipWithName: ship_desc];   // retain count = 1
	if (doppelganger)
	{
		[doppelganger setPosition:origin];						// directly below
		[doppelganger setScanClass:CLASS_NEUTRAL];
		[doppelganger setOrientation:q1];
		[doppelganger setVelocity:vel];
		[doppelganger setSpeed:flightSpeed];
		[doppelganger setRoll:0.2 * (randf() - 0.5)];
		[doppelganger setDesiredSpeed:flightSpeed];
		[doppelganger setOwner:self];
		[doppelganger setStatus:STATUS_IN_FLIGHT];  // necessary to get it going!
		[doppelganger setBehaviour:BEHAVIOUR_IDLE];

		[UNIVERSE addEntity:doppelganger];

		[[doppelganger getAI] setStateMachine:@"nullAI.plist"];  // fly straight on

		result = [doppelganger universalID];

		[doppelganger release]; //release
	}

	// set up you
	escapePod = [UNIVERSE newShipWithName:@"escape-capsule"];	// retained
	if (escapePod != nil)
	{
		// FIXME: this should use OOShipType, which should exist. -- Ahruman
		[self setMesh:[escapePod mesh]];
		[escapePod release];
	}
	
	[UNIVERSE setViewDirection:VIEW_FORWARD];
	flightSpeed = 1.0;
	flightPitch = 0.2 * (randf() - 0.5);
	flightRoll = 0.2 * (randf() - 0.5);

	double sheight = (boundingBox.max.y - boundingBox.min.y);
	position = vector_subtract(position, vector_multiply_scalar(v_up, sheight));
	
	//remove escape pod
	[self removeExtraEquipment:@"EQ_ESCAPE_POD"];
	//has_escape_pod = NO;

	// reset legal status
	legalStatus = 0;
	bounty = 0;

	// reset trumbles
	if (trumbleCount != 0)  trumbleCount = 1;

	// remove cargo
	[cargo removeAllObjects];

	energy = 25;
	[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[escape-sequence]") forCount:4.5];
	shot_time = 0.0;
	
	[self doScriptEvent:@"shipLaunchedEscapePod" withArgument:escapePod];

	return result;
}


- (int) dumpCargo
{
	if (flightSpeed > 4.0 * maxFlightSpeed)
	{
		[UNIVERSE addMessage:ExpandDescriptionForCurrentSystem(@"[hold-locked]") forCount:3.0];
		return CARGO_NOT_CARGO;
	}

	int result = [super dumpCargo];
	if (result != CARGO_NOT_CARGO)
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-ejected]") ,[UNIVERSE nameForCommodity:result]] forCount:3.0];
	}
	return result;
}


- (void) rotateCargo
{
	int n_cargo = [cargo count];
	if (n_cargo == 0)
		return;
	ShipEntity* pod = (ShipEntity*)[[cargo objectAtIndex:0] retain];
	int current_contents = [pod commodityType];
	int contents = [pod commodityType];
	int rotates = 0;
	do	{
		[cargo removeObjectAtIndex:0];	// take it from the eject position
		[cargo addObject:pod];	// move it to the last position
		[pod release];
		pod = (ShipEntity*)[[cargo objectAtIndex:0] retain];
		contents = [pod commodityType];
		rotates++;
	}	while ((contents == current_contents)&&(rotates < n_cargo));
	[pod release];
	if (contents != CARGO_NOT_CARGO)
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-ready-to-eject]"), [UNIVERSE nameForCommodity:contents]] forCount:3.0];
	}
	else
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[ready-to-eject-@]") ,[pod name]] forCount:3.0];
	}
	// now scan through the remaining 1..(n_cargo - rotates) places moving similar cargo to the last place
	// this means the cargo gets to be sorted as it is rotated through
	int i;
	for (i = 1; i < (n_cargo - rotates); i++)
	{
		pod = [cargo objectAtIndex:i];
		if ([pod commodityType] == current_contents)
		{
			[pod retain];
			[cargo removeObjectAtIndex:i--];
			[cargo addObject:pod];
			[pod release];
			rotates++;
		}
	}
}


- (void) setBounty:(OOCreditsQuantity) amount
{
	legalStatus = amount;
}


- (OOCreditsQuantity) bounty		// overrides returning 'bounty'
{
	return legalStatus;
}


- (int) legalStatus
{
	return legalStatus;
}


- (void) markAsOffender:(int)offence_value
{
	legalStatus |= offence_value;
}


- (void) collectBountyFor:(ShipEntity *)other
{
	if (!other)
		return;
	OOCreditsQuantity	score = 10 * [other bounty];
	OOScanClass			killClass = other->scanClass; // **tgape** change (+line)
	BOOL				killAward = YES;
	
	if ([other isPolice])   // oops, we shot a copper!
		legalStatus |= 64;
	
	if (![UNIVERSE strict])	// only mess with the scores if we're not in 'strict' mode
	{
		BOOL killIsCargo = ((killClass == CLASS_CARGO) && ([other commodityAmount] > 0));
		if ((killIsCargo) || (killClass == CLASS_BUOY) || (killClass == CLASS_ROCK))
		{
			if (![other hasRole:@"tharglet"])	// okay, we'll count tharglets as proper kills
			{
				score /= 10;	// reduce bounty awarded
				killAward = NO;	// don't award a kill
			}
		}
	}
	
	credits += score;
	
	if (score)
	{
		NSString *bonusMS1 = [NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[bounty-d]"), score / 10];
		NSString *bonusMS2 = [NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[total-f-credits]"), 0.1 * credits];
		
		if (score > 9)
		{
			[UNIVERSE addDelayedMessage:bonusMS1 forCount:6 afterDelay:0.15];
			[UNIVERSE addDelayedMessage:bonusMS2 forCount:6 afterDelay:0.15];
		}
	}
	
	if (killAward)
	{
		ship_kills++;
		if ((ship_kills % 256) == 0)
		{
			// congratulations method needs to be delayed a fraction of a second
			NSString *roc = ExpandDescriptionForCurrentSystem(@"[right-on-commander]");
			[UNIVERSE addDelayedMessage:roc forCount:4 afterDelay:0.2];
		}
	}
}


- (void) takeInternalDamage
{
	unsigned n_cargo = max_cargo;
	unsigned n_mass = [self mass] / 10000;
	unsigned n_considered = n_cargo + n_mass;
	unsigned damage_to = ranrot_rand() % n_considered;
	// cargo damage
	if (damage_to < [cargo count])
	{
		ShipEntity* pod = (ShipEntity*)[cargo objectAtIndex:damage_to];
		NSString* cargo_desc = [UNIVERSE nameForCommodity:[pod commodityType]];
		if (!cargo_desc)
			return;
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-destroyed]"), cargo_desc] forCount:4.5];
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
		NSArray* eq = [UNIVERSE equipmentdata];
		unsigned i;
		for (i = 0; (i < [eq count])&&(!system_name); i++)
		{
			NSArray* eqd = [eq arrayAtIndex:i];
			if ([system_key isEqual:[eqd objectAtIndex:EQUIPMENT_KEY_INDEX]])
				system_name = [eqd stringAtIndex:EQUIPMENT_SHORT_DESC_INDEX];
		}
		if (!system_name)
			return;
		// set the following so removeEquipment works on the right entity
		[self setScriptTarget:self];
		[UNIVERSE clearPreviousMessage];
		[self removeEquipment:system_key];
		if (![UNIVERSE strict])
		{
			[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-damaged]"), system_name] forCount:4.5];
			[self addExtraEquipment:[NSString stringWithFormat:@"%@_DAMAGED", system_key]];	// for possible future repair
		}
		else
			[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-destroyed]"), system_name] forCount:4.5];
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


- (void) getDestroyedBy:(Entity *)whom context:(NSString *)why
{
	NSString *scoreMS = [NSString stringWithFormat:@"Score: %.1f Credits",credits/10.0];

	if (![[UNIVERSE gameController] playerFileToLoad])
		[[UNIVERSE gameController] setPlayerFileToLoad: save_path];	// make sure we load the correct game
	
	energy = 0.0;
	afterburner_engaged = NO;
	[UNIVERSE setDisplayText:NO];
	[UNIVERSE setDisplayCursor:NO];
	[UNIVERSE setViewDirection:VIEW_AFT];
	[self becomeLargeExplosion:4.0];
	[self moveForward:100.0];
	
	[UNIVERSE playCustomSound:@"[game-over]"];
	[destructionSound play];
	
	flightSpeed = 160.0;
	status = STATUS_DEAD;
	[UNIVERSE displayMessage:@"Game Over" forCount:30.0];
	[UNIVERSE displayMessage:@"" forCount:30.0];
	[UNIVERSE displayMessage:scoreMS forCount:30.0];
	[UNIVERSE displayMessage:@"" forCount:30.0];
	[UNIVERSE displayMessage:@"Press Space" forCount:30.0];
	shot_time = 0.0;
	
	if (whom == nil)  whom = (id)[NSNull null];
	[self doScriptEvent:@"shipDied" withArguments:[NSArray arrayWithObjects:whom, why, nil]];
	[self loseTargetStatus];
}


- (void) loseTargetStatus
{
	if (!UNIVERSE)
		return;
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
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
			if (self == [ship primaryTarget])
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
	if (status == STATUS_DEAD)
		return;
	
	status = STATUS_DOCKING;
	[self doScriptEvent:@"shipWillDockWithStation" withArgument:station];

	afterburner_engaged = NO;

	cloaking_device_active = NO;
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	missile_status = MISSILE_STATUS_SAFE;

	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;
	[UNIVERSE setDisplayText:NO];
	[UNIVERSE setDisplayCursor:NO];

	[self setOrientation: kIdentityQuaternion];	// reset orientation to dock

	[UNIVERSE set_up_break_pattern:position quaternion:orientation];
	[self playBreakPattern];

	[station noteDockedShip:self];
	dockedStation = station;

	[[UNIVERSE gameView] clearKeys];	// try to stop key bounces

}


- (void) docked
{
	status = STATUS_DOCKED;
	[UNIVERSE setViewDirection:VIEW_GUI_DISPLAY];

	[self loseTargetStatus];

	if (dockedStation)
	{
		Vector launchPos = dockedStation->position;
		position = launchPos;

		[self setOrientation: kIdentityQuaternion];	// reset orientation to dock

		v_forward = vector_forward_from_quaternion(orientation);
		v_right = vector_right_from_quaternion(orientation);
		v_up = vector_up_from_quaternion(orientation);
	}

	flightRoll = 0.0;
	flightPitch = 0.0;
	flightSpeed = 0.0;

	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	missile_status =	MISSILE_STATUS_SAFE;

	primaryTarget = NO_TARGET;
	[self clearTargetMemory];

	forward_shield =	PLAYER_MAX_FORWARD_SHIELD;
	aft_shield =		PLAYER_MAX_AFT_SHIELD;
	energy =			maxEnergy;
	weapon_temp =		0.0;
	ship_temperature =		60.0;

	[self setAlertFlag:ALERT_FLAG_DOCKED to:YES];

	if (![dockedStation localMarket])
		[dockedStation initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];

	NSString*	escapepodReport = [self processEscapePods];
	if ([escapepodReport length])
		[dockingReport appendString: escapepodReport];
	
	[self unloadCargoPods];	// fill up the on-ship commodities before...

	// check contracts
	NSString* passengerReport = [self checkPassengerContracts];
	if (passengerReport)
		[dockingReport appendFormat:@"\n\n%@", passengerReport];
		
	[UNIVERSE setDisplayText:YES];

	if (ootunes_on)
	{
		// ootunes - pause current music
		[[UNIVERSE gameController] pauseiTunes];
		// ootunes - play inflight music
		[[UNIVERSE gameController] playiTunesPlaylist:@"Oolite-Docked"];
		docking_music_on = NO;
	}

	// time to check the script!
	if (!being_fined)
		[self checkScript];

	// if we've not switched to the mission screen then proceed normally..
	if (gui_screen != GUI_SCREEN_MISSION)
	{
		// check for fines
		if (being_fined)
			[self getFined];

		[self setGuiToStatusScreen];
	}
	
	[[OOCacheManager sharedCache] flush];
	
	[self doScriptEvent:@"shipDockedWithStation" withArgument:dockedStation];
}


- (void) leaveDock:(StationEntity *)station
{
	if (station == nil)  return;	
	
	if (station == [UNIVERSE station])
		legalStatus |= [UNIVERSE legal_status_of_manifest:shipCommodityData];  // 'leaving with those guns were you sir?'
	[self loadCargoPods];
	
	// clear the way
	[station autoDockShipsOnApproach];
	[station clearDockingCorridor];

	[station launchShip:self];
	orientation.w = -orientation.w;   // need this as a fix...
	flightRoll = -flightRoll;

	[self setAlertFlag:ALERT_FLAG_DOCKED to:NO];

	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;
	gui_screen = GUI_SCREEN_MAIN;
	[self clearTargetMemory];
	[self setShowDemoShips:NO];
	[UNIVERSE setDisplayText:NO];
	[UNIVERSE setDisplayCursor:NO];
	[UNIVERSE set_up_break_pattern:position quaternion:orientation];

	[[UNIVERSE gameView] clearKeys];	// try to stop keybounces

	if (ootunes_on)
	{
		// ootunes - pause current music
		[[UNIVERSE gameController] pauseiTunes];
		// ootunes - play inflight music
		[[UNIVERSE gameController] playiTunesPlaylist:@"Oolite-Inflight"];
	}

	ship_clock_adjust = 600.0;			// 10 minutes to leave dock

	dockedStation = nil;
}


- (void) enterGalacticWitchspace
{
	status = STATUS_ENTERING_WITCHSPACE;
	[self doScriptEvent:@"shipWillEnterWitchspace" withArgument:@"galactic jump"];
	
	if (primaryTarget != NO_TARGET)
		primaryTarget = NO_TARGET;
	
	hyperspeed_engaged = NO;
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;
	
	[UNIVERSE setDisplayText:NO];
	
	[UNIVERSE allShipAIsReactToMessage:@"PLAYER WITCHSPACE"];
	
	[UNIVERSE removeAllEntitiesExceptPlayer:NO];
	
	// remove any contracts for the old galaxy
	if (contracts)
		[contracts removeAllObjects];
	
	// remove any mission destinations for the old galaxy
	if (missionDestinations)
		[missionDestinations removeAllObjects];
	
	// expire passenger contracts for the old galaxy
	if (passengers)
	{
		unsigned i;
		for (i = 0; i < [passengers count]; i++)
		{
			// set the expected arrival time to now, so they storm off the ship at the first port
			NSMutableDictionary* passenger_info = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[passengers objectAtIndex:i]];
			[passenger_info setObject:[NSNumber numberWithDouble:ship_clock] forKey:PASSENGER_KEY_ARRIVAL_TIME];
			[passengers replaceObjectAtIndex:i withObject:passenger_info];
		}
	}
	
	[self removeExtraEquipment:@"EQ_GAL_DRIVE"];
	
	galaxy_number++;
	galaxy_number &= 7;

	galaxy_seed.a = rotate_byte_left(galaxy_seed.a);
	galaxy_seed.b = rotate_byte_left(galaxy_seed.b);
	galaxy_seed.c = rotate_byte_left(galaxy_seed.c);
	galaxy_seed.d = rotate_byte_left(galaxy_seed.d);
	galaxy_seed.e = rotate_byte_left(galaxy_seed.e);
	galaxy_seed.f = rotate_byte_left(galaxy_seed.f);

	[UNIVERSE setGalaxy_seed:galaxy_seed];
	//system_seed = [UNIVERSE findSystemAtCoords:NSMakePoint(0x60, 0x60) withGalaxySeed:galaxy_seed];
	
	// instead find a system connected to system 0 near the current coordinates...
	system_seed = [UNIVERSE findConnectedSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	
	target_system_seed = system_seed;

	[UNIVERSE setSystemTo:system_seed];
	galaxy_coordinates.x = system_seed.d;
	galaxy_coordinates.y = system_seed.b;
    ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	market_rnd = ranrot_rand() & 255;						// random factor for market values is reset
	legalStatus = 0;
	[UNIVERSE set_up_universe_from_witchspace];
}


- (void) enterWormhole:(WormholeEntity *) w_hole replacing:(BOOL)replacing
{
	target_system_seed = [w_hole destination];
	status = STATUS_ENTERING_WITCHSPACE;
	[self doScriptEvent:@"shipWillEnterWitchspace" withArgument:@"wormhole"];

	hyperspeed_engaged = NO;

	if (primaryTarget != NO_TARGET)
		primaryTarget = NO_TARGET;
	
	//	reset the compass
	
	if ([self hasExtraEquipment:@"EQ_ADVANCED_COMPASS"])
		compassMode = COMPASS_MODE_PLANET;
	else
		compassMode = COMPASS_MODE_BASIC;

	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
	ship_clock_adjust = distance * distance * 3600.0;		// LY * LY hrs

	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;

	[UNIVERSE setDisplayText:NO];

	[UNIVERSE allShipAIsReactToMessage:@"PLAYER WITCHSPACE"];

	[UNIVERSE removeAllEntitiesExceptPlayer:NO];
	[UNIVERSE setSystemTo:target_system_seed];

	system_seed = target_system_seed;
	galaxy_coordinates.x = system_seed.d;
	galaxy_coordinates.y = system_seed.b;
	legalStatus /= 2;										// 'another day, another system'
	ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	market_rnd = ranrot_rand() & 255;						// random factor for market values is reset
	
	[UNIVERSE set_up_universe_from_witchspace];
	[[UNIVERSE planet] update: 2.34375 * market_rnd];	// from 0..10 minutes
	[[UNIVERSE station] update: 2.34375 * market_rnd];	// from 0..10 minutes
}


- (void) enterWitchspace
{
	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);

	status = STATUS_ENTERING_WITCHSPACE;
	[self doScriptEvent:@"shipWillEnterWitchspace" withArgument:@"standard jump"];

	hyperspeed_engaged = NO;

	if (primaryTarget != NO_TARGET)
		primaryTarget = NO_TARGET;

	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0;

	[UNIVERSE setDisplayText:NO];

	[UNIVERSE allShipAIsReactToMessage:@"PLAYER WITCHSPACE"];

	[UNIVERSE removeAllEntitiesExceptPlayer:NO];
	
	//	reset the compass
	
	if ([self hasExtraEquipment:@"EQ_ADVANCED_COMPASS"])
		compassMode = COMPASS_MODE_PLANET;
	else
		compassMode = COMPASS_MODE_BASIC;
	
	//  perform any check here for forced witchspace encounters
	
	unsigned malfunc_chance = 253;
    if (ship_trade_in_factor < 80)
		malfunc_chance -= (1 + ranrot_rand() % (81-ship_trade_in_factor)) / 2;	// increase chance of misjump in worn-out craft
	ranrot_srand([[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	BOOL malfunc = ((ranrot_rand() & 0xff) > malfunc_chance);
	// 75% of the time a malfunction means a misjump
	BOOL misjump = ((flightPitch == max_flight_pitch) || (malfunc && (randf() > 0.75)));

	fuel -= 10.0 * distance;								// fuel cost to target system
	ship_clock_adjust = distance * distance * 3600.0;		// LY * LY hrs
	if (!misjump)
	{
		[UNIVERSE setSystemTo:target_system_seed];
		system_seed = target_system_seed;
		galaxy_coordinates.x = system_seed.d;
		galaxy_coordinates.y = system_seed.b;
		legalStatus /= 2;								// 'another day, another system'
		market_rnd = ranrot_rand() & 255;				// random factor for market values is reset
		if (market_rnd < 8)
			[self erodeReputation];						// every 32 systems or so, drop back towards 'unknown'
		
		if (2 * market_rnd < ship_trade_in_factor)			// every eight jumps or so
			ship_trade_in_factor -= 1 + (market_rnd & 3);	// drop the price down towards 75%
		if (ship_trade_in_factor < 75)
			ship_trade_in_factor = 75;						// lower limit for trade in value is 75%
		
		[UNIVERSE set_up_universe_from_witchspace];
		[[UNIVERSE planet] update: 2.34375 * market_rnd];	// from 0..10 minutes
		[[UNIVERSE station] update: 2.34375 * market_rnd];	// from 0..10 minutes
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
		// move sort of halfway there...
		galaxy_coordinates.x += target_system_seed.d;
		galaxy_coordinates.y += target_system_seed.b;
		galaxy_coordinates.x /= 2;
		galaxy_coordinates.y /= 2;
		if (![UNIVERSE playCustomSound:@"[witchdrive-malfunction]"])
			[self playECMSound];
		[UNIVERSE set_up_universe_from_misjump];
	}
}


- (void) leaveWitchspace
{
	Vector		pos = [UNIVERSE getWitchspaceExitPosition];
	Quaternion  q_rtn = [UNIVERSE getWitchspaceExitRotation];
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
	orientation = q_rtn;
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightYaw = 0.0;
	flightSpeed = maxFlightSpeed * 0.25;
	status = STATUS_EXITING_WITCHSPACE;
	gui_screen = GUI_SCREEN_MAIN;
	being_fined = NO;				// until you're scanned by a copper!
	[self clearTargetMemory];
	[self setShowDemoShips:NO];
	[UNIVERSE setDisplayCursor:NO];
	[UNIVERSE setDisplayText:NO];
	[UNIVERSE set_up_break_pattern:position quaternion:orientation];
	[self playBreakPattern];
	[self doScriptEvent:@"shipWillExitWitchspace"];
}


- (void) performDocking
{
	// Huh? What is this? Doesn't seem to get called. -- ahruman
	[self abortDocking];			// let the station know that you are no longer on approach
	autopilot_engaged = NO;
	status = STATUS_IN_FLIGHT;
}


///////////////////////////////////

- (void) setGuiToStatusScreen
{
	// intercept any docking messages
	if ([dockingReport length] > 0)
	{
		[self setGuiToDockingReportScreen];	// go here instead!
		return;
	}

	NSString*		systemName = nil;
	NSString*		targetSystemName = nil;
	NSString*       text = nil;

	system_seed = [UNIVERSE findSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];

	systemName = [UNIVERSE getSystemName:system_seed];
	if (status == STATUS_DOCKED)
	{
		if ((dockedStation != [UNIVERSE station])&&(dockedStation != nil))
			systemName = [NSString stringWithFormat:@"%@ : %@", systemName, [dockedStation name]];
	}

	targetSystemName =	[UNIVERSE getSystemName:target_system_seed];

	// GUI stuff
	{
		GuiDisplayGen		*gui = [UNIVERSE gui];
		NSDictionary		*ship_dict = nil;
		NSString			*shipName = nil;
		NSString			*legal_desc = nil, *rating_desc = nil,
							*alert_desc = nil, *fuel_desc = nil,
							*credits_desc = nil;
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 20;
		tab_stops[1] = 160;
		tab_stops[2] = 256;
		[gui setTabStops:tab_stops];

		ship_dict = [UNIVERSE getDictionaryForShip:ship_desc];
		shipName = [ship_dict stringForKey:KEY_NAME];

		legal_desc = LegalStatusToString(legalStatus);
		rating_desc = KillCountToRatingAndKillString(ship_kills);
		alert_desc = AlertConditionToString([self alertCondition]);
		fuel_desc = [NSString stringWithFormat:@"%.1f Light Years", fuel/10.0];
		credits_desc = [NSString stringWithFormat:@"%.1f Cr", credits/10.0];
		
		[gui clear];

		text = DESC(@"status-commander-@");
		[gui setTitle:[NSString stringWithFormat:text, player_name]];
		
		[gui setText:shipName forRow:0 align:GUI_ALIGN_CENTER];
		
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-present-system"), systemName, nil]	forRow:1];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-hyperspace-system"), targetSystemName, nil] forRow:2];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-condition"), alert_desc, nil]			forRow:3];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-fuel"), fuel_desc, nil]				forRow:4];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-cash"), credits_desc, nil]			forRow:5];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-legal-status"), legal_desc, nil]		forRow:6];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-rating"), rating_desc, nil]			forRow:7];
		
		[gui setText:DESC(@"status-equipment") forRow:9];
		
		[gui setShowTextCursor:NO];
	}
	/* ends */

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}

	gui_screen = GUI_SCREEN_STATUS;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
	
#if 0
// DEBUG SCENE TEST ROUTINES
	[UNIVERSE removeDemoShips];
	[self debugOn];
	[self setBackgroundFromDescriptionsKey:@"test-scene"];
	[self debugOff];
	[self setShowDemoShips: YES];
// END TEST
#endif
}


- (NSArray *) equipmentList
{
	NSDictionary*   descriptions = [UNIVERSE descriptions];
	//int				original_hold_size = [UNIVERSE maxCargoForShip:ship_desc];
	NSMutableArray* quip = [NSMutableArray arrayWithCapacity:32];
	
	unsigned i;
	NSArray* equipmentinfo = [UNIVERSE equipmentdata];
	for (i =0; i < [equipmentinfo count]; i++)
	{
		NSString *w_key = (NSString *)[(NSArray *)[equipmentinfo objectAtIndex:i] objectAtIndex:EQUIPMENT_KEY_INDEX];
		NSString *w_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", w_key];
		if ([self hasExtraEquipment:w_key])
			[quip addObject:(NSString *)[(NSArray *)[equipmentinfo objectAtIndex:i] objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX]];
		if (![UNIVERSE strict])
		{
			if ([self hasExtraEquipment:w_key_damaged])
				[quip addObject:(NSString *)[[(NSArray *)[equipmentinfo objectAtIndex:i] objectAtIndex:EQUIPMENT_SHORT_DESC_INDEX] stringByAppendingString:@" (N/A)"]];
		}
	}

	if (forward_weapon > 0)
		[quip addObject:[NSString stringWithFormat:[descriptions objectForKey:@"equipment-fwd-weapon-@"],(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:forward_weapon]]];
	if (aft_weapon > 0)
		[quip addObject:[NSString stringWithFormat:[descriptions objectForKey:@"equipment-aft-weapon-@"],(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:aft_weapon]]];
	if (starboard_weapon > 0)
		[quip addObject:[NSString stringWithFormat:[descriptions objectForKey:@"equipment-stb-weapon-@"],(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:starboard_weapon]]];
	if (port_weapon > 0)
		[quip addObject:[NSString stringWithFormat:[descriptions objectForKey:@"equipment-port-weapon-@"],(NSString *)[(NSArray *)[descriptions objectForKey:@"weapon_name"] objectAtIndex:port_weapon]]];

	if (max_passengers > 0)
	{
		// Using distinct strings for single and multiple passenger berths because different languages
		// may have quite different ways of phrasing the two.
		if (max_passengers > 1)
			[quip addObject:[NSString stringWithFormat:[descriptions objectForKey:@"equipment-multiple-pass-berth-@"], max_passengers]];
		else
			[quip addObject:[descriptions objectForKey:@"equipment-single-pass-berth-@"]];
	}

	return [NSArray arrayWithArray:quip];
}


- (NSArray *) cargoList
{
	NSMutableArray* manifest = [NSMutableArray arrayWithCapacity:32];
	NSDictionary*   descriptions = [UNIVERSE descriptions];
	NSString *tons = (NSString *)[descriptions objectForKey:@"cargo-tons-symbol"];
	NSString *grams = (NSString *)[descriptions objectForKey:@"cargo-grams-symbol"];
	NSString *kilograms = (NSString *)[descriptions objectForKey:@"cargo-kilograms-symbol"];

	if (specialCargo)
		[manifest addObject:specialCargo];

	unsigned		n_commodities = [shipCommodityData count];
	OOCargoQuantity	in_hold[n_commodities];
	unsigned		i;
	
	// following changed to work whether docked or not
	for (i = 0; i < n_commodities; i++)
		in_hold[i] = [[shipCommodityData arrayAtIndex:i] unsignedIntAtIndex:MARKET_QUANTITY];
	for (i = 0; i < [cargo count]; i++)
	{
		ShipEntity *container = [cargo objectAtIndex:i];
		in_hold[[container commodityType]] += [container commodityAmount];
	}
	
	for (i = 0; i < n_commodities; i++)
	{
		if (in_hold[i] > 0)
		{
			int unit = [UNIVERSE unitsForCommodity:i];
			NSString* units = [NSString stringWithString:tons];
			if (unit == UNITS_KILOGRAMS)  units = [NSString stringWithString:kilograms];
			if (unit == UNITS_GRAMS)  units = [NSString stringWithString:grams];
			NSString* desc = (NSString *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_NAME];
			[manifest addObject:[NSString stringWithFormat:@"%d%@ x %@", in_hold[i], units, desc]];
		}
	}
	
	return [NSArray arrayWithArray:manifest];
}


- (void) setGuiToSystemDataScreen
{
	NSDictionary*   targetSystemData;
	NSString*		targetSystemName;
	NSDictionary*   descriptions = [UNIVERSE descriptions];

	targetSystemData =		[[UNIVERSE generateSystemData:target_system_seed] retain];  // retained
	targetSystemName =		[[UNIVERSE getSystemName:target_system_seed] retain];  // retained

	BOOL	sunGoneNova = NO;
	if ([targetSystemData objectForKey:@"sun_gone_nova"])
		sunGoneNova = YES;

	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 96;
		tab_stops[2] = 144;
		[gui setTabStops:tab_stops];

		int techlevel =		[targetSystemData intForKey:KEY_TECHLEVEL];
		int population =	[targetSystemData intForKey:KEY_POPULATION];
		int productivity =	[targetSystemData intForKey:KEY_PRODUCTIVITY];
		int radius =		[targetSystemData intForKey:KEY_RADIUS];

		NSString	*government_desc =	GovernmentToString([targetSystemData intForKey:KEY_GOVERNMENT]);
		NSString	*economy_desc =		EconomyToString([targetSystemData intForKey:KEY_ECONOMY]);
		NSString	*inhabitants =		[targetSystemData stringForKey:KEY_INHABITANTS];
		NSString	*system_desc =		[targetSystemData stringForKey:KEY_DESCRIPTION];

		if ((sunGoneNova && equal_seeds(target_system_seed, system_seed) && [[UNIVERSE sun] goneNova])||
			(sunGoneNova && (!equal_seeds(target_system_seed, system_seed))))
		{
			population = 0;
			productivity = 0;
			radius = 0;
			system_desc = ExpandDescriptionForCurrentSystem(@"[nova-system-description]");
		}

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:[descriptions objectForKey:@"sysdata-planet-name-@"],   targetSystemName]];
		
		[gui setArray:[NSArray arrayWithObjects:[descriptions objectForKey:@"sysdata-eco"], economy_desc, nil]						forRow:1];
		
		[gui setArray:[NSArray arrayWithObjects:[descriptions objectForKey:@"sysdata-govt"], government_desc, nil]				forRow:3];
		
		[gui setArray:[NSArray arrayWithObjects:[descriptions objectForKey:@"sysdata-tl"], [NSString stringWithFormat:@"%d", techlevel + 1], nil]	forRow:5];
		
		[gui setArray:[NSArray arrayWithObjects:[descriptions objectForKey:@"sysdata-pop"], [NSString stringWithFormat:@"%.1f Billion", 0.1*population], nil]	forRow:7];
		[gui setArray:[NSArray arrayWithObjects:@"", [NSString stringWithFormat:@"(%@)", inhabitants], nil]				forRow:8];
		
		[gui setArray:[NSArray arrayWithObjects:[descriptions objectForKey:@"sysdata-prod"], @"", [NSString stringWithFormat:@"%5d M Cr.", productivity], nil]	forRow:10];
		
		[gui setArray:[NSArray arrayWithObjects:[descriptions objectForKey:@"sysdata-radius"], @"", [NSString stringWithFormat:@"%5d km", radius], nil]	forRow:12];
		
		int i = [gui addLongText:system_desc startingAtRow:15 align:GUI_ALIGN_LEFT];
		missionTextRow = i;
		for (i-- ; i > 14 ; i--)
			[gui setColor:[OOColor greenColor] forRow:i];
		

		[gui setShowTextCursor:NO];

	}
	/* ends */

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}

	[targetSystemData release];
	[targetSystemName release];

	gui_screen = GUI_SCREEN_SYSTEM_DATA;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];

	[UNIVERSE removeDemoShips];
	[self setBackgroundFromDescriptionsKey:@"gui-scene-show-planet"];

}


- (NSArray *) markedDestinations
{
	// get a list of systems marked as contract destinations
	NSMutableArray	*destinations = [NSMutableArray arrayWithCapacity:256];
	BOOL			mark[256] = {0};
	unsigned		i;
	
	for (i = 0; i < [passengers count]; i++)
	{
		mark[[[passengers dictionaryAtIndex:i] unsignedCharForKey:PASSENGER_KEY_DESTINATION]] = YES;
	}
	for (i = 0; i < [contracts count]; i++)
	{
		mark[[[contracts dictionaryAtIndex:i] unsignedCharForKey:CONTRACT_KEY_DESTINATION]] = YES;
	}
	for (i = 0; i < [missionDestinations count]; i++)
	{
		mark[[missionDestinations unsignedCharAtIndex:i]] = YES;
	}
	for (i = 0; i < 256; i++)
	{
		[destinations addObject:[NSNumber numberWithBool:mark[i]]];
	}
	
	return destinations;
}


- (void) setGuiToLongRangeChartScreen
{
	NSString	*targetSystemName;
	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
	double		estimatedTravelTime = distance * distance;

	if ((target_system_seed.d != cursor_coordinates.x)||(target_system_seed.b != cursor_coordinates.y))
		target_system_seed =	[UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	targetSystemName =		[[UNIVERSE getSystemName:target_system_seed] retain];  // retained

	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Galactic Chart %d",   galaxy_number+1]];
		
		[gui setText:targetSystemName	forRow:17];
		[gui setText:[NSString stringWithFormat:@"Distance:\t%.1f Light Years", distance]   forRow:18];
		[gui setText:(distance <= (fuel/10.0f) ? [NSString stringWithFormat:@"Estimated Travel Time:\t%.1f Hours", estimatedTravelTime] : @"") forRow:19];
		
		if (planetSearchString)
			[gui setText:[NSString stringWithFormat:@"Find planet: %@", [planetSearchString capitalizedString]]  forRow:16];
		else
			[gui setText:@"Find planet: "  forRow:16];
		[gui setColor:[OOColor cyanColor] forRow:16];

		[gui setShowTextCursor:YES];
		[gui setCurrentRow:16];

		
	}
	/* ends */

	gui_screen = GUI_SCREEN_LONG_RANGE_CHART;

	[targetSystemName release];

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) setGuiToShortRangeChartScreen
{
	NSString*   targetSystemName;
	double		distance = distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
	double		estimatedTravelTime = distance * distance;

	if ((target_system_seed.d != cursor_coordinates.x)||(target_system_seed.b != cursor_coordinates.y))
		target_system_seed =	[UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	targetSystemName =		[[UNIVERSE getSystemName:target_system_seed] retain];  // retained

	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];

		if ((abs(cursor_coordinates.x-galaxy_coordinates.x)>=20)||(abs(cursor_coordinates.y-galaxy_coordinates.y)>=38))
			cursor_coordinates = galaxy_coordinates;	// home

		[gui clear];
		[gui setTitle:@"Short Range Chart"];
		
		[gui setText:targetSystemName														forRow:19];
		[gui setText:[NSString stringWithFormat:@"Distance:\t%.1f Light Years", distance]   forRow:20];
		[gui setText:(distance <= (fuel/10.0f) ? [NSString stringWithFormat:@"Estimated Travel Time:\t%.1f Hours", estimatedTravelTime] : @"") forRow:21];
		

		[gui setShowTextCursor:NO];
	}
	/* ends */

	gui_screen = GUI_SCREEN_SHORT_RANGE_CHART;

	[targetSystemName release]; // released

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}





- (void) setGuiToGameOptionsScreen
{
#ifdef GNUSTEP
	MyOpenGLView	*gameView = [UNIVERSE gameView];
#endif
	GameController	*controller = [UNIVERSE gameController];

	int displayModeIndex = [controller indexOfCurrentDisplayMode];
	if (displayModeIndex == NSNotFound)
	{
		OOLog(@"display.currentMode.notFound", @"***** couldn't find current display mode switching to basic 640x480");
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
	int modeWidth = [[mode objectForKey:kOODisplayWidth] intValue];
	int modeHeight = [[mode objectForKey:kOODisplayHeight] intValue];
	float modeRefresh = [[mode objectForKey:kOODisplayRefreshRate] doubleValue];

	NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];

	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];

		int first_sel_row = GUI_ROW_GAMEOPTIONS_VOLUME;

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Commander %@",   player_name]];
		
		[gui setText:displayModeString forRow:GUI_ROW_GAMEOPTIONS_DISPLAY align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_DISPLAY];

		// volume control
		if ([OOSound respondsToSelector:@selector(masterVolume)])
		{
			int volume = 20 * [OOSound masterVolume];
			NSString* v1_string = @"|||||||||||||||||||||||||";
			NSString* v0_string = @".........................";
			v1_string = [v1_string substringToIndex:volume];
			v0_string = [v0_string substringToIndex:20 - volume];
			if (volume > 0)
				[gui setText:[NSString stringWithFormat:@" Sound Volume: %@%@ ", v1_string, v0_string] forRow:GUI_ROW_GAMEOPTIONS_VOLUME align:GUI_ALIGN_CENTER];
			else
				[gui setText:@" Sound Volume: MUTE " forRow:GUI_ROW_GAMEOPTIONS_VOLUME align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_VOLUME];
		}
		else
		{
			[gui setText:@" Sound Volume: External Control Only" forRow:GUI_ROW_GAMEOPTIONS_VOLUME align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_GAMEOPTIONS_VOLUME];
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
			[gui setText:[NSString stringWithFormat:@" Show Growl Messages: %@ ", growl_priority_desc] forRow:GUI_ROW_GAMEOPTIONS_GROWL align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_GROWL];
		}

		// Speech control
		if (isSpeechOn)
			[gui setText:@" Spoken Messages: YES " forRow:GUI_ROW_GAMEOPTIONS_SPEECH align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Spoken Messages: NO " forRow:GUI_ROW_GAMEOPTIONS_SPEECH align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_SPEECH];

		// iTunes integration control
		if (ootunes_on)
			[gui setText:@" iTunes Integration: YES " forRow:GUI_ROW_GAMEOPTIONS_OOTUNES align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" iTunes Integration: NO " forRow:GUI_ROW_GAMEOPTIONS_OOTUNES align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_OOTUNES];

#else

		// window/fullscreen
		if([gameView inFullScreenMode])
		{
			[gui setText:@" Play in Window " forRow:GUI_ROW_GAMEOPTIONS_DISPLAYSTYLE align:GUI_ALIGN_CENTER];
		}
		else
		{
			[gui setText:@" Play in Full Screen " forRow:GUI_ROW_GAMEOPTIONS_DISPLAYSTYLE align:GUI_ALIGN_CENTER];
		}
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_GAMEOPTIONS_DISPLAYSTYLE];


		[gui setText:@" Joystick Configuration " forRow: GUI_ROW_GAMEOPTIONS_STICKMAPPER align: GUI_ALIGN_CENTER];
		if ([[gameView getStickHandler] getNumSticks])
		{
			// TODO: Modify input code to put this in a better place
			stickHandler=[gameView getStickHandler];
			numSticks=[stickHandler getNumSticks];
			// end TODO

			[gui setKey: GUI_KEY_OK forRow: GUI_ROW_GAMEOPTIONS_STICKMAPPER];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_GAMEOPTIONS_STICKMAPPER];
		}
#endif

		if ([UNIVERSE wireframeGraphics])
			[gui setText:@" Wireframe Graphics: YES " forRow:GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Wireframe Graphics: NO " forRow:GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_WIREFRAMEGRAPHICS];
		
		if ([UNIVERSE reducedDetail])
			[gui setText:@" Reduced Detail: YES " forRow:GUI_ROW_GAMEOPTIONS_DETAIL align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Reduced Detail: NO " forRow:GUI_ROW_GAMEOPTIONS_DETAIL align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_DETAIL];
	
		// Shader effects level.	
		int shaderEffects = [UNIVERSE shaderEffectsLevel];
		NSString* shaderEffectsOptionsString = nil;
		if (shaderEffects == SHADERS_NOT_SUPPORTED)
		{
			[gui setText:@" Shader Effects: Not available " forRow:GUI_ROW_GAMEOPTIONS_SHADEREFFECTS align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_GAMEOPTIONS_SHADEREFFECTS];
		}
		else
		{
			shaderEffectsOptionsString = [NSString stringWithFormat:@" Shader Effects: %@ ", ShaderSettingToDisplayString(shaderEffects)];
			[gui setText:shaderEffectsOptionsString forRow:GUI_ROW_GAMEOPTIONS_SHADEREFFECTS align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_SHADEREFFECTS];
		}
		
		// Back menu option
		[gui setText:@" Back " forRow:GUI_ROW_GAMEOPTIONS_BACK align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_GAMEOPTIONS_BACK];

			
		[gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_GAMEOPTIONS_END_OF_LIST - first_sel_row)];
		[gui setSelectedRow: first_sel_row];
		

		[gui setShowTextCursor:NO];
	}
	/* ends */

	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_GAMEOPTIONS;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}







- (void) setGuiToLoadSaveScreen
{
	BOOL			canLoadOrSave = NO;
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GameController	*controller = [UNIVERSE gameController];

	if (status == STATUS_DOCKED)
	{
		if (!dockedStation)
			dockedStation = [UNIVERSE station];
		canLoadOrSave = (dockedStation == [UNIVERSE station]);
	}

	BOOL canQuickSave = (canLoadOrSave && ([[gameView gameController] playerFileToLoad] != nil));
	int displayModeIndex = [controller indexOfCurrentDisplayMode];
	if (displayModeIndex == NSNotFound)
	{
		OOLog(@"display.currentMode.notFound", @"***** couldn't find current display mode switching to basic 640x480");
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

	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];

		int first_sel_row = (canLoadOrSave)? GUI_ROW_OPTIONS_SAVE : GUI_ROW_OPTIONS_GAMEOPTIONS;
		if (canQuickSave)
			first_sel_row = GUI_ROW_OPTIONS_QUICKSAVE;

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Commander %@",   player_name]];
		
		[gui setText:@" Quick-Save " forRow:GUI_ROW_OPTIONS_QUICKSAVE align:GUI_ALIGN_CENTER];		
		if (canQuickSave)
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_QUICKSAVE];
		else
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_QUICKSAVE];
		
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
		
		[gui setText:@" Begin New Game " forRow:GUI_ROW_OPTIONS_BEGIN_NEW align:GUI_ALIGN_CENTER];
		if (![[UNIVERSE gameController] gameIsPaused])
		{
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_BEGIN_NEW];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW_OPTIONS_BEGIN_NEW];
		}
		
		[gui setText:@" Game Options... " forRow:GUI_ROW_OPTIONS_GAMEOPTIONS align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_GAMEOPTIONS];
		
#if OOLITE_SDL
		// GNUstep needs a quit option at present (no Cmd-Q) but
		// doesn't need speech.
		
		// quit menu option
		[gui setText:@" Exit Game " forRow:GUI_ROW_OPTIONS_QUIT align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_QUIT];
#endif
		
		if ([UNIVERSE strict])
			[gui setText:@" Reset to Unrestricted Play " forRow:GUI_ROW_OPTIONS_STRICT align:GUI_ALIGN_CENTER];
		else
			[gui setText:@" Reset to Strict Play " forRow:GUI_ROW_OPTIONS_STRICT align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW_OPTIONS_STRICT];

		
		[gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_OPTIONS_END_OF_LIST - first_sel_row)];
		[gui setSelectedRow: first_sel_row];
		

		[gui setShowTextCursor:NO];
	}
	/* ends */

	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_OPTIONS;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}

static int last_outfitting_index;

- (void) setGuiToEquipShipScreen:(int) skipParam :(int) itemForSelectFacing
{
	missiles = [self countMissiles];
	
	unsigned skip;

	// if skip < 0 then use the last recorded index
	if (skipParam < 0)
	{
		if (last_outfitting_index >= 0)
			skip = last_outfitting_index;
		else
			skip = 0;
	}
	else
	{
		skip = skipParam;
	}
	
	last_outfitting_index = skip;

	NSArray		*equipdata = [UNIVERSE equipmentdata];

	OOCargoQuantity cargo_space = max_cargo - current_cargo;

	double price_factor = 1.0;
	OOTechLevelID techlevel = [[UNIVERSE generateSystemData:system_seed] intForKey:KEY_TECHLEVEL];

	if (dockedStation)
	{
		price_factor = [dockedStation equipmentPriceFactor];
		if ([dockedStation equivalentTechLevel] != NSNotFound)
			techlevel = [dockedStation equivalentTechLevel];
	}

	// build an array of all equipment - and take away that which has been bought (or is not permitted)
	NSMutableArray* equipment_allowed = [NSMutableArray array];
	
	// find options that agree with this ship
	NSMutableArray*	options = [NSMutableArray arrayWithArray:[(NSDictionary *)[[UNIVERSE shipyard] objectForKey:ship_desc] objectForKey:KEY_OPTIONAL_EQUIPMENT]];
	// add standard items too!
	[options addObjectsFromArray:[(NSDictionary *)[(NSDictionary *)[[UNIVERSE shipyard] objectForKey:ship_desc] objectForKey:KEY_STANDARD_EQUIPMENT] objectForKey:KEY_EQUIPMENT_EXTRAS]];
	
	unsigned i,j;
	for (i = 0; i < [equipdata count]; i++)
	{
		NSString		*eq_key = (NSString*)[(NSArray*)[equipdata objectAtIndex:i] objectAtIndex:EQUIPMENT_KEY_INDEX];
		NSString		*eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
		OOTechLevelID	min_techlevel   = [[equipdata arrayAtIndex:i] unsignedIntAtIndex:EQUIPMENT_TECH_LEVEL_INDEX];
		
		NSMutableDictionary	*eq_extra_info_dict = [NSMutableDictionary dictionary];
		if ([(NSArray *)[equipdata objectAtIndex:i] count] > 5)
			[eq_extra_info_dict addEntriesFromDictionary:(NSDictionary *)[(NSArray *)[equipdata objectAtIndex:i] objectAtIndex:EQUIPMENT_EXTRA_INFO_INDEX]];

		// set initial availability to NO
		BOOL isOK = NO;

		// check special availability
		if ([eq_extra_info_dict objectForKey:@"available_to_all"])
			[options addObject: eq_key];
		
		// check if this is a mission special ..
		if (min_techlevel == 99)
		{
			// check mission variables for the existence of a revised tech level (given when item is awarded)
			NSString* mission_eq_tl_key = [NSString stringWithFormat:@"mission_TL_FOR_%@", eq_key];
			min_techlevel = [mission_variables unsignedIntForKey:mission_eq_tl_key defaultValue:min_techlevel];
		}
		
		// if you have a dmaged system you can get it repaired at a tech level one less than that required to buy it
		if (min_techlevel != 0 && [self hasExtraEquipment:eq_key_damaged])
			min_techlevel--;
		
		// reduce the minimum techlevel occasionally as a bonus..
		
		if ((![UNIVERSE strict])&&(techlevel < min_techlevel)&&(techlevel + 3 > min_techlevel))
		{
			int day = i * 13 + floor([UNIVERSE getTime] / 86400.0);
			unsigned char day_rnd = (day & 0xff) ^ system_seed.a;
			OOTechLevelID original_min_techlevel = min_techlevel;
			
			while ((min_techlevel > 0)&&(min_techlevel > original_min_techlevel - 3)&&!(day_rnd & 7))	// bargain tech days every 1/8 days
			{
				day_rnd = day_rnd >> 2;
				min_techlevel--;	// occasional bonus items according to TL
			}
		}

		// check initial availability against options AND standard extras
		// FIXME: options should be a set.
		for (j = 0; j < [options count]; j++)
		{
			if ([eq_key isEqual:[options objectAtIndex:j]])
			{
				isOK = YES;
				[options removeObjectAtIndex:j];
				break;
			}
		}
		
		if (isOK)
		{
			BOOL					requiresEmptyPylon = NO,
									requiresMountedPylon = NO,
									requiresClean = NO,
									requiresNotClean = NO;
			OOCargoQuantity			requiresCargoSpace = 0;
			id						requiresEquipment = nil;
			id						incompatibleWithEquipment = nil;
			
			// check built-in requirements
			if ([self hasExtraEquipment:eq_key])  isOK = NO;
			if (([eq_key isEqualToString:@"EQ_FUEL"])&&(fuel >= PLAYER_MAX_FUEL))  isOK = NO;	// check if fuel space free
			if (([eq_key hasSuffix:@"MISSILE"]||[eq_key hasSuffix:@"MINE"]))  requiresEmptyPylon = YES;	// Kept for compatibility with existing missiles/mines that don't specify it.
			if (([eq_key isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])&&(max_passengers - [passengers count] < 1))  isOK = NO;
			if (techlevel < min_techlevel)  isOK = NO;
			if ([eq_key isEqual:@"EQ_RENOVATION"] && !((75 <= ship_trade_in_factor)&&(ship_trade_in_factor < 85))) isOK = NO;
			
			// check custom requirements
			requiresEmptyPylon = [eq_extra_info_dict boolForKey:@"requires_empty_pylon" defaultValue:requiresEmptyPylon];
			requiresMountedPylon = [eq_extra_info_dict boolForKey:@"requires_mounted_pylon" defaultValue:requiresMountedPylon];
			requiresCargoSpace = [eq_extra_info_dict unsignedIntForKey:@"requires_cargo_space" defaultValue:requiresCargoSpace];
			requiresEquipment = [eq_extra_info_dict objectForKey:@"requires_equipment" defaultValue:requiresEquipment];
			incompatibleWithEquipment = [eq_extra_info_dict objectForKey:@"incompatible_with_equipment" defaultValue:requiresEquipment];
			if ([eq_extra_info_dict objectForKey:@"requires_clean"])  requiresClean = YES;
			if ([eq_extra_info_dict objectForKey:@"requires_not_clean"])  requiresNotClean = YES;
			
			if (isOK)
			{
				if (requiresEmptyPylon && missiles >= max_missiles)  isOK = NO;
				else if (requiresMountedPylon && missiles == 0)  isOK = NO;
				else if (cargo_space < requiresCargoSpace)  isOK = NO;
				else if (requiresEquipment != nil && ![self hasExtraEquipment:requiresEquipment])  isOK = NO;
				else if (incompatibleWithEquipment != nil && [self hasExtraEquipment:incompatibleWithEquipment])  isOK = NO;
				else if (requiresClean && [self legalStatus] != 0)  isOK = NO;
				else if (requiresNotClean && [self legalStatus] == 0)  isOK = NO;
			}
		}
		
		if (isOK && [eq_extra_info_dict objectForKey:@"conditions"])
		{
			[self debugOn];
			id conds = [eq_extra_info_dict objectForKey:@"conditions"];
			if ([conds isKindOfClass:[NSString class]])
			{
				if (![self scriptTestCondition:(NSString *) conds])  isOK = NO;
			}
			else if ([conds isKindOfClass:[NSArray class]])
			{
				NSArray* conditions = (NSArray*)conds;
				unsigned i;
				for (i = 0; i < [conditions count]; i++)
					if (![self scriptTestCondition:(NSString *)[conditions objectAtIndex:i]])  isOK = NO;
			}
			[self debugOff];
		}
		
		if (isOK)
			[equipment_allowed addUnsignedInteger:i];
		
		if ((int)i == itemForSelectFacing)
		{
			skip = [equipment_allowed count] - 1;	// skip to this upgrade
			unsigned available_facings = [[[UNIVERSE shipyard] dictionaryForKey:ship_desc] unsignedIntForKey:KEY_WEAPON_FACINGS];
			if (available_facings & WEAPON_FACING_FORWARD)
				[equipment_allowed addUnsignedInteger:i];
			if (available_facings & WEAPON_FACING_AFT)
				[equipment_allowed addUnsignedInteger:i];
			if (available_facings & WEAPON_FACING_PORT)
				[equipment_allowed addUnsignedInteger:i];
			if (available_facings & WEAPON_FACING_STARBOARD)
				[equipment_allowed addUnsignedInteger:i];
		}
	}

	// GUI stuff
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		OOGUIRow		start_row = GUI_ROW_EQUIPMENT_START;
		OOGUIRow		row = start_row;
		unsigned		i;
		unsigned		facing_count = 0;

		[gui clear];
		[gui setTitle:@"Ship Outfitting"];
		
		[gui setText:[NSString stringWithFormat:@"Cash:\t%.1f Cr.", 0.1*credits]  forRow: GUI_ROW_EQUIPMENT_CASH];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 320;
		[gui setTabStops:tab_stops];
		
		unsigned n_rows = GUI_MAX_ROWS_EQUIPMENT;
		
		if ([equipment_allowed count] > 0)
		{
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
			for (i = skip; (i < [equipment_allowed count])&&(row - start_row < (int)n_rows - 1); i++)
			{
				unsigned			item = [equipment_allowed unsignedIntAtIndex:i];
				NSArray				*itemInfo = [equipdata arrayAtIndex:item];
				OOCreditsQuantity	price_per_unit = [itemInfo unsignedIntAtIndex:EQUIPMENT_PRICE_INDEX];
				NSString			*desc = [NSString stringWithFormat:@" %@ ", [itemInfo stringAtIndex:EQUIPMENT_SHORT_DESC_INDEX]];
				NSString			*eq_key = [(NSArray *)[equipdata objectAtIndex: item] stringAtIndex:EQUIPMENT_KEY_INDEX];
				NSString			*eq_key_damaged	= [eq_key stringByAppendingString:@"_DAMAGED"];
				double				price;
				
				if ([eq_key isEqual:@"EQ_FUEL"])
				{
					price = (PLAYER_MAX_FUEL - fuel) * price_per_unit;
				}
				else if ([eq_key isEqual:@"EQ_RENOVATION"])
				{
					price = cunningFee(0.1 * [UNIVERSE tradeInValueForCommanderDictionary:[self commanderDataDictionary]]);
				}
				else price = price_per_unit;
				
				price *= price_factor;  // increased prices at some stations
				
				// color repairs and renovation items orange
				if ([self hasExtraEquipment:eq_key_damaged])
				{
					desc = [NSString stringWithFormat:@" Repair:%@", desc];
					price /= 2.0;
					[gui setColor:[OOColor orangeColor] forRow:row];
				}
				if ([eq_key isEqual:@"EQ_RENOVATION"])
				{
					[gui setColor:[OOColor orangeColor] forRow:row];
				}

				NSString *priceString = [NSString stringWithFormat:@" %.1f ", 0.1 * price];

				if ((int)item == itemForSelectFacing)
				{
					switch (facing_count)
					{
						case 0:
							priceString = @"";
							break;
						
						case 1:
							desc = FORWARD_FACING_STRING;
							break;
						
						case 2:
							desc = AFT_FACING_STRING;
							break;
						
						case 3:
							desc = PORT_FACING_STRING;
							break;
						
						case 4:
							desc = STARBOARD_FACING_STRING;
							break;
					}
					
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
			
			[gui setSelectableRange:NSMakeRange(start_row,row - start_row)];

			if ([gui selectedRow] != start_row)
				[gui setSelectedRow:start_row];

			if (itemForSelectFacing >= 0)
				[gui setSelectedRow:start_row + ((skip > 0)? 1: 0)];

			[self showInformationForSelectedUpgrade];
			
		}
		else
		{
			[gui setText:@"No equipment available for purchase." forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_NO_SHIPS];
			
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
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: YES];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) showInformationForSelectedUpgrade
{
	GuiDisplayGen* gui = [UNIVERSE gui];
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
			NSString*   desc = (NSString *)[(NSArray *)[[UNIVERSE equipmentdata] objectAtIndex:item] objectAtIndex:EQUIPMENT_LONG_DESC_INDEX];
			NSString*   eq_key			= (NSString *)[(NSArray *)[[UNIVERSE equipmentdata] objectAtIndex:item] objectAtIndex:EQUIPMENT_KEY_INDEX];
			NSString*	eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
			if ([self hasExtraEquipment:eq_key_damaged])
				desc = [NSString stringWithFormat:@"%@ (Price is for repairing the existing system).", desc];
			[gui addLongText:desc startingAtRow:GUI_ROW_EQUIPMENT_DETAIL align:GUI_ALIGN_LEFT];
		}
	}
}


- (void) setGuiToIntro1Screen
{
	NSString *text;
	GuiDisplayGen* gui = [UNIVERSE gui];
	
	[[OOCacheManager sharedCache] flush];	// At first startup, a lot of stuff is cached
	
	// GUI stuff
	int ms_line = 2;
	
	[gui clear];
	[gui setTitle:@"Oolite"];
	
	text = ExpandDescriptionForCurrentSystem(@"[game-copyright]");
	[gui setText:text forRow:17 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor whiteColor] forRow:17];
	
	text = ExpandDescriptionForCurrentSystem(@"[theme-music-credit]");
	[gui setText:text forRow:19 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor grayColor] forRow:19];
	
	text = ExpandDescriptionForCurrentSystem(@"[load-previous-commander]");
	[gui setText:text forRow:21 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:21];
	
	
	// check for error messages from Resource Manager
	[ResourceManager paths];
	if ([ResourceManager errors])
	{
		int ms_start = ms_line;
		int i = ms_line = [gui addLongText:[ResourceManager errors] startingAtRow:ms_start align:GUI_ALIGN_LEFT];
		for (i-- ; i >= ms_start ; i--) [gui setColor:[OOColor redColor] forRow:i];
		ms_line++;
	}
	
	// check for messages from the command line
	NSArray* arguments = [[NSProcessInfo processInfo] arguments];
	unsigned i;
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

	[UNIVERSE set_up_intro1];

	if (gui)
		gui_screen = GUI_SCREEN_INTRO1;

	if (themeMusic)
	{
		[themeMusic playLooped];
	}


	[self setShowDemoShips: YES];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) setGuiToIntro2Screen
{
	NSString *text;
	GuiDisplayGen* gui = [UNIVERSE gui];

	[gui clear];
	[gui setTitle:@"Oolite"];
	
	text = ExpandDescriptionForCurrentSystem(@"[press-space-commander]");
	[gui setText:text forRow:21 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:21];
	
	[gui setShowTextCursor:NO];

	[UNIVERSE set_up_intro2];

	if (gui)
		gui_screen = GUI_SCREEN_INTRO2;

	[self setShowDemoShips: YES];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: NO];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (void) buySelectedItem
{
	GuiDisplayGen* gui = [UNIVERSE gui];
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
	
	OOCreditsQuantity old_credits = credits;
	if ([self tryBuyingItem:item])
	{
		if (credits == old_credits)
		{
			[[UNIVERSE gui] click];
		}
		else
		{
			[self playInterfaceBeep:kInterfaceBeep_Buy];
			
			// wind the clock forward by 10 minutes plus 10 minutes for every 60 credits spent
			
			double time_adjust = (old_credits > credits) ? (old_credits - credits) : 0.0;
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
	NSArray				*equipdata		= [UNIVERSE equipmentdata];
	OOCreditsQuantity	price_per_unit	= [[equipdata arrayAtIndex:index] unsignedLongLongAtIndex:EQUIPMENT_PRICE_INDEX];
	NSString			*eq_key			= [[equipdata arrayAtIndex:index] stringAtIndex:EQUIPMENT_KEY_INDEX];
	NSString			*eq_key_damaged	= [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
	double				price			= ([eq_key isEqual:@"EQ_FUEL"]) ? ((PLAYER_MAX_FUEL - fuel) * price_per_unit) : (price_per_unit);
	double				price_factor	= 1.0;
	OOCargoQuantity		cargo_space		= max_cargo - current_cargo;
	OOCreditsQuantity	tradeIn = 0;

	// repairs cost 50%
	if ([self hasExtraEquipment:eq_key_damaged])
	{
		price /= 2.0;
	}

	if ([eq_key isEqual:@"EQ_RENOVATION"])
	{
		price = cunningFee(0.1 * [UNIVERSE tradeInValueForCommanderDictionary:[self commanderDataDictionary]]);
	}

	if (dockedStation)
	{
		price_factor = [dockedStation equipmentPriceFactor];
	}

	price *= price_factor;  // increased prices at some stations

	if (price > credits)
	{
		return NO;
	}

	if ([eq_key hasPrefix:@"EQ_WEAPON"] && chosen_weapon_facing == WEAPON_FACING_NONE)
	{
		[self setGuiToEquipShipScreen:-1:index];	// reset
		return YES;
	}

	if ([eq_key hasPrefix:@"EQ_WEAPON"] && chosen_weapon_facing != WEAPON_FACING_NONE)
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

		// refund here for current_weapon
		/*	BUG: equipment_price_factor does not affect trade-ins. This means
			that an equipment_price_factor less than one can be exploited.
			Analysis: price factor simply not being applied here.
			Fix: trivial.
			Acknowledgment: bug and fix both reported by Cmdr James on forum.
			-- Ahruman 20070724
		*/
		switch (current_weapon)
		{
			case WEAPON_PLASMA_CANNON :
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_WEAPON_TWIN_PLASMA_CANNON"];
				break;
			case WEAPON_PULSE_LASER :
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_WEAPON_PULSE_LASER"];
				break;
			case WEAPON_BEAM_LASER :
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_WEAPON_BEAM_LASER"];
				break;
			case WEAPON_MINING_LASER :
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_WEAPON_MINING_LASER"];
				break;
			case WEAPON_MILITARY_LASER :
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_WEAPON_MILITARY_LASER"];
				break;
			case WEAPON_THARGOID_LASER :
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_WEAPON_THARGOID_LASER"];
				break;
			case WEAPON_NONE :
				break;
		}	
		[self doTradeIn:tradeIn forPriceFactor:price_factor];
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}

	if (([eq_key hasSuffix:@"MISSILE"] || [eq_key hasSuffix:@"MINE"]) && missiles >= max_missiles)
	{
		OOLog(@"equip.buy.mounted.failed.full", @"rejecting missile because already full");
		return NO;
	}

	if ([eq_key isEqual:@"EQ_PASSENGER_BERTH"] && cargo_space < 5)
	{
		return NO;
	}
	
	if ([eq_key isEqual:@"EQ_FUEL"])
	{
		fuel = PLAYER_MAX_FUEL;
		credits -= price;
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}
	
	// check energy unit replacement
	if ([eq_key hasSuffix:@"ENERGY_UNIT"] && energy_unit != ENERGY_UNIT_NONE)
	{
		switch (energy_unit)
		{
			case ENERGY_UNIT_NAVAL :
				[self removeEquipment:@"EQ_NAVAL_ENERGY_UNIT"];
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_NAVAL_ENERGY_UNIT"] / 2;	// 50 % refund
				break;

			case ENERGY_UNIT_NORMAL :
				[self removeEquipment:@"EQ_ENERGY_UNIT"];
				tradeIn = [UNIVERSE getPriceForWeaponSystemWithKey:@"EQ_ENERGY_UNIT"] * 3 / 4;	// 75 % refund
				break;

			case ENERGY_UNIT_NONE :
			default :
				break;
		}
		[self doTradeIn:tradeIn forPriceFactor:price_factor];
	}
	
	// maintain ship
	if ([eq_key isEqual:@"EQ_RENOVATION"])
	{
		OOTechLevelID techLevel = NSNotFound;
		if (dockedStation != nil)  techLevel = [dockedStation equivalentTechLevel];
		if (techLevel == NSNotFound)  techLevel = [[UNIVERSE generateSystemData:system_seed] unsignedIntForKey:KEY_TECHLEVEL];
		
		credits -= price;
		ship_trade_in_factor += 5 + techLevel;	// you get better value at high-tech repair bases
		if (ship_trade_in_factor > 100)
			ship_trade_in_factor = 100;
		
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}

	if ([eq_key hasSuffix:@"MISSILE"] || [eq_key hasSuffix:@"MINE"])
	{
		ShipEntity* weapon = [[UNIVERSE newShipWithRole:eq_key] autorelease];
		if (weapon)  OOLog(kOOLogBuyMountedOK, @"Got ship for mounted weapon role %@", eq_key);
		else  OOLog(kOOLogBuyMountedFailed, @"Could not find ship for mounted weapon role %@", eq_key);

		BOOL mounted_okay = [self mountMissile:weapon];
		if (mounted_okay)
		{
			credits -= price;
			[self safeAllMissiles];
			[self sortMissiles];
			[self selectNextMissile];
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
		[self safeAllMissiles];
		[self sortMissiles];
		unsigned i;
		for (i = 0; i < missiles; i++)
		{
			ShipEntity* weapon = missile_entity[i];
			missile_entity[i] = nil;
			if (weapon)
			{
				NSString* weapon_key = [weapon primaryRole];
				int weapon_value = [UNIVERSE getPriceForWeaponSystemWithKey:weapon_key];
				tradeIn += weapon_value;
				[weapon release];
			}
		}
		missiles = 0;
		[self doTradeIn:tradeIn forPriceFactor:price_factor];
		[self setGuiToEquipShipScreen:-1:-1];
		return YES;
	}

	unsigned i;
	for (i = 0; i < [equipdata count]; i++)
	{
		NSString *w_key = [[equipdata arrayAtIndex:i] stringAtIndex:EQUIPMENT_KEY_INDEX];
		if (([eq_key isEqual:w_key])&&(![self hasExtraEquipment:eq_key]))
		{
			credits -= price;
			[self addExtraEquipment:eq_key];
			[self setGuiToEquipShipScreen:-1:-1];

			return YES;
		}
	}

	return NO;
}


-(void) doTradeIn:(OOCreditsQuantity)tradeInValue forPriceFactor:(double)priceFactor
{
	if (tradeInValue != 0)
	{
		if (priceFactor < 1.0f)  tradeInValue *= priceFactor;
		credits += tradeInValue;
	}
}


- (void) calculateCurrentCargo
{
	unsigned i;
	unsigned n_commodities = [shipCommodityData count];
	OOCargoQuantity in_hold[n_commodities];

	// following works whether docked or not
	
	for (i = 0; i < n_commodities; i++)
		in_hold[i] = [(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
	for (i = 0; i < [cargo count]; i++)
	{
		ShipEntity *container = (ShipEntity *)[cargo objectAtIndex:i];
		in_hold[[container commodityType]] += [container commodityAmount];
	}

	current_cargo = 0;  // for calculating remaining hold space
	
	for (i = 0; i < n_commodities; i++)
	{
		if ([(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_UNITS] intValue] == UNITS_TONS)
			current_cargo += in_hold[i];
	}
}


- (void) setGuiToMarketScreen
{
	NSArray				*localMarket;
	StationEntity		*station = nil;
	
	if (status != STATUS_DOCKED || dockedStation == nil)  station = [UNIVERSE station];
	else  station = dockedStation;
	localMarket = [station localMarket];
	if (localMarket == nil)
	{
		localMarket = [station initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
	
	// fix problems with economies in witch-space
	if (![UNIVERSE station])
	{
		unsigned i;
		NSMutableArray* ourEconomy = [NSMutableArray arrayWithArray:[UNIVERSE commodityDataForEconomy:0 andStation:(StationEntity*)nil andRandomFactor:0]];
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
		GuiDisplayGen	*gui = [UNIVERSE gui];
		OOGUIRow		start_row = GUI_ROW_MARKET_START;
		OOGUIRow		row = start_row;
		unsigned		i;
		unsigned		n_commodities = [shipCommodityData count];
		OOCargoQuantity	in_hold[n_commodities];

		// following changed to work whether docked or not
		
		for (i = 0; i < n_commodities; i++)
			in_hold[i] = [(NSNumber *)[(NSArray *)[shipCommodityData objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
		for (i = 0; i < [cargo count]; i++)
		{
			ShipEntity *container = (ShipEntity *)[cargo objectAtIndex:i];
			in_hold[[container commodityType]] += [container commodityAmount];
		}

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"%@ Commodity Market",[UNIVERSE getSystemName:system_seed]]];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 192;
		tab_stops[2] = 288;
		tab_stops[3] = 384;
		[gui setTabStops:tab_stops];
		
		[gui setColor:[OOColor greenColor] forRow:GUI_ROW_MARKET_KEY];
		[gui setArray:[NSArray arrayWithObjects: @"Commodity:", @"Price:", @"For sale:", @"In hold:", nil] forRow:GUI_ROW_MARKET_KEY];
		
		current_cargo = 0;  // for calculating remaining hold space
		
		for (i = 0; i < n_commodities; i++)
		{
			NSString* desc = [NSString stringWithFormat:@" %@ ",(NSString *)[(NSArray *)[localMarket objectAtIndex:i] objectAtIndex:MARKET_NAME]];
			int available_units = [[[localMarket objectAtIndex:i] objectAtIndex:MARKET_QUANTITY] intValue];
			int units_in_hold = in_hold[i];
			int price_per_unit = [[[localMarket objectAtIndex:i] objectAtIndex:MARKET_PRICE] intValue];
			OOMassUnit unit = [[[localMarket objectAtIndex:i] objectAtIndex:MARKET_UNITS] intValue];
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
		
		if ([cargo count] > 0)
			current_cargo = ([cargo count] <= max_cargo) ? [cargo count] : max_cargo;  // actually count the containers and things (may be > max_cargo)
		
		[gui setText:[NSString stringWithFormat:@"Cash:\t%.1f Cr.\t\tLoad %d of %d t.", 0.1*credits, current_cargo, max_cargo]  forRow: GUI_ROW_MARKET_CASH];
		
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
		

		[gui setShowTextCursor:NO];
	}

	gui_screen = GUI_SCREEN_MARKET;

	[self setShowDemoShips: NO];
	[UNIVERSE setDisplayText: YES];
	[UNIVERSE setDisplayCursor: (status == STATUS_DOCKED)];
	[UNIVERSE setViewDirection: VIEW_GUI_DISPLAY];
}


- (OOGUIScreenID) guiScreen
{
	return gui_screen;
}


- (BOOL) marketFlooded:(int) index
{
	NSMutableArray*			localMarket;
	if (dockedStation == nil)
		dockedStation = [UNIVERSE station];
	if ([dockedStation localMarket])
		localMarket = [dockedStation localMarket];
	else
		localMarket = [dockedStation initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	NSArray *commodityArray = (NSArray *)[localMarket objectAtIndex:index];
	int available_units =   [(NSNumber *)[commodityArray objectAtIndex:MARKET_QUANTITY] intValue];
	return (available_units >= 127);
}


- (BOOL) tryBuyingCommodity:(int) index
{
	NSMutableArray*			localMarket;
	if (status == STATUS_DOCKED)
	{
		if (dockedStation == nil)
			dockedStation = [UNIVERSE station];
		if ([dockedStation localMarket])
			localMarket = [dockedStation localMarket];
		else
			localMarket = [dockedStation initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
	}
	else
	{
		return NO; // can't buy if not docked
	}

	NSArray				*commodityArray	= [localMarket objectAtIndex:index];
	OOCargoQuantity		available_units	= [commodityArray unsignedIntAtIndex:MARKET_QUANTITY];
	OOCreditsQuantity	price_per_unit	= [commodityArray unsignedIntAtIndex:MARKET_PRICE];
	OOMassUnit			unit			= [(NSNumber *)[commodityArray objectAtIndex:MARKET_UNITS] intValue];

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
		if (dockedStation == nil)
			dockedStation = [UNIVERSE station];
		if ([dockedStation localMarket])
			localMarket = [dockedStation localMarket];
		else
			localMarket = [dockedStation initialiseLocalMarketWithSeed:system_seed andRandomFactor:market_rnd];
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


- (BOOL) isSpeechOn
{
	return isSpeechOn;
}


- (BOOL) hasExtraEquipment:(id)equipmentKeys
{
	NSEnumerator				*keyEnum = nil;
	id							key = nil;
	
	// Make sure it's an array or set, using a single-object set if it's a string.
	if ([equipmentKeys isKindOfClass:[NSString class]])  equipmentKeys = [NSArray arrayWithObject:equipmentKeys];
	else if (![equipmentKeys isKindOfClass:[NSArray class]] && ![equipmentKeys isKindOfClass:[NSSet class]])  return NO;
	
	for (keyEnum = [equipmentKeys objectEnumerator]; (key = [keyEnum nextObject]); )
	{
		// No class test is needed here - it'll be an object, and if it's not a string it won't be a key in the dictionary.
		if ([extra_equipment objectForKey:key])  return YES;
	}
	
	return NO;
}


- (void) addExtraEquipment:(NSString *) eq_key
{
	// if we've got a damaged one of these - remove it first
	NSString* damaged_eq_key = [NSString stringWithFormat:@"%@_DAMAGED", eq_key];
	if ([extra_equipment objectForKey:damaged_eq_key])
		[extra_equipment removeObjectForKey:damaged_eq_key];
	
	// deal with trumbles..
	if ([eq_key isEqual:@"EQ_TRUMBLE"])
	{
		/*	Bug fix: must return here if eq_key == @"EQ_TRUMBLE", even if
			trumbleCount >= 1. Otherwise, the player becomes immune to
			trumbles. See comment in -setCommanderDataFromDictionary: for more
			details.
			-- Ahruman 2008-12-04
		*/
		if (trumbleCount < 1)
		{
			[self addTrumble:trumble[ranrot_rand() % PLAYER_MAX_TRUMBLES]];	// first one!
		}
		return;
	}
	
	// add the equipment and set the necessary flags and data accordingly
	[extra_equipment setObject:[NSNumber numberWithBool:YES] forKey:eq_key];
	[self setFlagsFromExtraEquipment];
}


- (void) removeExtraEquipment:(NSString *) eq_key
{
	if ([extra_equipment objectForKey:eq_key])
		[extra_equipment removeObjectForKey:eq_key];
	[self setFlagsFromExtraEquipment];
}


- (void) setExtraEquipmentFromFlags
{
	OOCargoQuantity original_hold_size = [UNIVERSE maxCargoForShip:ship_desc];
	
	if (max_cargo > original_hold_size)
		[self addExtraEquipment:@"EQ_CARGO_BAY"];
	if (has_escape_pod)
		[self addExtraEquipment:@"EQ_ESCAPE_POD"];
	if (has_scoop)
		[self addExtraEquipment:@"EQ_FUEL_SCOOPS"];
	if (has_fuel_injection)
		[self addExtraEquipment:@"EQ_FUEL_INJECTION"];
	if (has_ecm)
		[self addExtraEquipment:@"EQ_ECM"];
	if (has_energy_bomb)
		[self addExtraEquipment:@"EQ_ENERGY_BOMB"];
	if (has_energy_unit)
	{
		switch (energy_unit)
		{
			case ENERGY_UNIT_NONE:
				break;
			case ENERGY_UNIT_NORMAL :
				[self addExtraEquipment:@"EQ_ENERGY_UNIT"];
				break;
			case ENERGY_UNIT_NAVAL :
				[self addExtraEquipment:@"EQ_NAVAL_ENERGY_UNIT"];
				break;
		}
	}
	if (has_docking_computer)
		[self addExtraEquipment:@"EQ_DOCK_COMP"];
	if (has_galactic_hyperdrive)
		[self addExtraEquipment:@"EQ_GAL_DRIVE"];

	if (shield_booster > 1)
		[self addExtraEquipment:@"EQ_SHIELD_BOOSTER"];
	if (shield_enhancer)
		[self addExtraEquipment:@"EQ_NAVAL_SHIELD_BOOSTER"];
}


- (void) setFlagsFromExtraEquipment
{
	int original_hold_size = [UNIVERSE maxCargoForShip:ship_desc];
	
	if ([shipinfoDictionary objectForKey:@"extra_cargo"])
		extra_cargo = [(NSNumber*)[shipinfoDictionary objectForKey:@"extra_cargo"] intValue];
	else
		extra_cargo = 15;
	
	if ([self hasExtraEquipment:@"EQ_CARGO_BAY"])
		max_cargo = original_hold_size + extra_cargo - max_passengers * 5;
	
	has_escape_pod = [self hasExtraEquipment:@"EQ_ESCAPE_POD"];
	has_scoop = [self hasExtraEquipment:@"EQ_FUEL_SCOOPS"];
	has_fuel_injection = [self hasExtraEquipment:@"EQ_FUEL_INJECTION"];
	has_ecm = [self hasExtraEquipment:@"EQ_ECM"];
	has_energy_bomb = [self hasExtraEquipment:@"EQ_ENERGY_BOMB"];
	has_docking_computer = [self hasExtraEquipment:@"EQ_DOCK_COMP"];
	has_galactic_hyperdrive = [self hasExtraEquipment:@"EQ_GAL_DRIVE"];
	has_cloaking_device = [self hasExtraEquipment:@"EQ_CLOAKING_DEVICE"];
	has_military_jammer = [self hasExtraEquipment:@"EQ_MILITARY_JAMMER"];
	has_military_scanner_filter = [self hasExtraEquipment:@"EQ_MILITARY_SCANNER_FILTER"];

	has_energy_unit = ([self hasExtraEquipment:@"EQ_ENERGY_UNIT"]||[self hasExtraEquipment:@"EQ_NAVAL_ENERGY_UNIT"]);
	if (has_energy_unit)
		energy_unit = ([self hasExtraEquipment:@"EQ_NAVAL_ENERGY_UNIT"])? ENERGY_UNIT_NAVAL : ENERGY_UNIT_NORMAL;
	else
		energy_unit = ENERGY_UNIT_NONE;

	if ([self hasExtraEquipment:@"EQ_ADVANCED_COMPASS"])
		compassMode = COMPASS_MODE_PLANET;
	else
		compassMode = COMPASS_MODE_BASIC;

	shield_booster = ([self hasExtraEquipment:@"EQ_SHIELD_BOOSTER"])? 2:1;
	shield_enhancer = ([self hasExtraEquipment:@"EQ_NAVAL_SHIELD_BOOSTER"])? 1:0;
	heat_insulation = ([self hasExtraEquipment:@"EQ_HEAT_SHIELD"])? 2.0 : 1.0;	// new - provide extra heat_insulation
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
	
	[burnersound play];
	
	[self	performSelector:_loopAfterburnerSoundSelector
				withObject:NULL
				afterDelay:1.25];	// and swap sounds in 1.25s time
}


- (void) stopAfterburnerSound
{
	[burnersound stop];
}


- (BOOL) hasHostileTarget
{
	return NO;
}


- (void) receiveCommsMessage:(NSString *) message_text
{
	[UNIVERSE addCommsMessage:message_text forCount:4.5];
}


- (void) getFined
{
	if (legalStatus == 0)
		return;				// nothing to pay for
	int local_gov = [[UNIVERSE currentSystemData] intForKey:KEY_GOVERNMENT];
	OOCreditsQuantity fine = 500 + ((local_gov < 2)||(local_gov > 5))? 500:0;
	fine *= legalStatus;
	if (fine > credits)
	{
		int payback = legalStatus * credits / fine;
		legalStatus -= payback;
		credits = 0;
	}
	else
	{
		legalStatus = 0;
		credits -= fine;
	}
	fine /= 10;	// divide by ten for display
	NSString* fined_message = [NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[fined]"), fine];
	[UNIVERSE addMessage:fined_message forCount:6];
	ship_clock_adjust = 24 * 3600;	// take up a day
	if (gui_screen != GUI_SCREEN_STATUS)
		[self setGuiToStatusScreen];
}


- (void) setDefaultViewOffsets
{
	float halfLength = 0.5 * (boundingBox.max.z - boundingBox.min.z);
	float halfWidth = 0.5 * (boundingBox.max.x - boundingBox.min.x);

	forwardViewOffset = make_vector(0.0, 0.0, boundingBox.max.z - halfLength);
	aftViewOffset = make_vector(0.0, 0.0, boundingBox.min.z + halfLength);
	portViewOffset = make_vector(boundingBox.min.x + halfWidth, 0.0, 0.0);
	starboardViewOffset = make_vector(boundingBox.max.x - halfWidth, 0.0, 0.0);
	customViewOffset = kZeroVector;
}


- (Vector) weaponViewOffset
{
	switch (currentWeaponFacing)
	{
		case VIEW_FORWARD:
			return forwardViewOffset;
		case VIEW_AFT:
			return aftViewOffset;
		case VIEW_PORT:
			return portViewOffset;
		case VIEW_STARBOARD:
			return starboardViewOffset;
		case VIEW_CUSTOM:
			return customViewOffset;
		
		case VIEW_NONE:
		case VIEW_GUI_DISPLAY:
		case VIEW_BREAK_PATTERN:
			break;
	}
	return kZeroVector;
}


- (void) setDefaultWeaponOffsets
{
	float halfLength = 0.5 * (boundingBox.max.z - boundingBox.min.z);
	float halfWidth = 0.5 * (boundingBox.max.x - boundingBox.min.x);

	forwardWeaponOffset = make_vector(0.0, -5.0, boundingBox.max.z - halfLength);
	aftWeaponOffset = make_vector(0.0, -5.0, boundingBox.min.z + halfLength);
	portWeaponOffset = make_vector(boundingBox.min.x + halfWidth, -5.0, 0.0);
	starboardWeaponOffset = make_vector(boundingBox.max.x - halfWidth, -5.0, 0.0);
}


- (void) setUpTrumbles
{
	NSMutableString* trumbleDigrams = [NSMutableString stringWithCapacity:256];
	unichar	xchar = (unichar)0;
	unichar digramchars[2];

	while ([trumbleDigrams length] < PLAYER_MAX_TRUMBLES + 2)
	{
		if ((player_name)&&[player_name length])
			[trumbleDigrams appendFormat:@"%@%@", player_name, [[self mesh] modelName]];
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
	
	trumbleCount = 0;
	
	trumbleAppetiteAccumulator = 0.0;
}


- (void) addTrumble:(OOTrumble*) papaTrumble
{
	if (trumbleCount >= PLAYER_MAX_TRUMBLES)
	{
		return;
	}
	OOTrumble* trumblePup = trumble[trumbleCount];
	[trumblePup spawnFrom:papaTrumble];
	trumbleCount++;
}


- (void) removeTrumble:(OOTrumble*) deadTrumble
{
	if (trumbleCount <= 0)
	{
		return;
	}
	int trumble_index = NSNotFound;
	int i;
	for (i = 0; (trumble_index == NSNotFound)&&(i < trumbleCount); i++)
	{
		if (trumble[i] == deadTrumble)
			trumble_index = i;
	}
	if (trumble_index == NSNotFound)
	{
		OOLog(@"trumble.zombie", @"DEBUG can't get rid of inactive trumble %@", deadTrumble);
		return;
	}
	trumbleCount--;	// reduce number of trumbles
	trumble[trumble_index] = trumble[trumbleCount];	// swap with the current last trumble
	trumble[trumbleCount] = deadTrumble;				// swap with the current last trumble
}


- (OOTrumble**) trumbleArray
{
	return trumble;
}


- (int) trumbleCount
{
	return trumbleCount;
}


- (id)trumbleValue
{
	NSString	*namekey = [NSString stringWithFormat:@"%@-humbletrash", player_name];
	int			trumbleHash;
	
	clear_checksum();
	[self mungChecksumWithNSString:player_name];
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(trumbleCount);
	
	[[NSUserDefaults standardUserDefaults]  setInteger:trumbleHash forKey:namekey];
	
	int i;
	NSMutableArray* trumbleArray = [NSMutableArray arrayWithCapacity:PLAYER_MAX_TRUMBLES];
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
		[trumbleArray addObject:[trumble[i] dictionary]];
	
	return [NSArray arrayWithObjects:[NSNumber numberWithInt:trumbleCount],[NSNumber numberWithInt:trumbleHash], trumbleArray, nil];
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
	
	[self setUpTrumbles];
	
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
		[self mungChecksumWithNSString:player_name];
		munge_checksum(credits);
		munge_checksum(ship_kills);
		trumbleHash = munge_checksum(putativeNTrumbles);
		
		if (putativeHash != trumbleHash)
			info_failed = YES;
		
		if (info_failed)
		{
			OOLog(@"cheat.tentative", @"POSSIBLE CHEAT DETECTED");
			possible_cheat = YES;
		}
		
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			// try to determine trumbleCount from the key in the saved game
			clear_checksum();
			[self mungChecksumWithNSString:player_name];
			munge_checksum(credits);
			munge_checksum(ship_kills);
			trumbleHash = munge_checksum(i);
			if (putativeHash == trumbleHash)
			{
				info_failed = NO;
				putativeNTrumbles = i;
			}
		}
		
		if (possible_cheat && !info_failed)
			OOLog(@"cheat.verified", @"CHEAT DEFEATED - that's not the way to get rid of trumbles!");
	}
	
	if (info_failed && [[NSUserDefaults standardUserDefaults] objectForKey:namekey])
	{
		// try to determine trumbleCount from the key in user defaults
		putativeHash = [[NSUserDefaults standardUserDefaults] integerForKey:namekey];
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			clear_checksum();
			[self mungChecksumWithNSString:player_name];
			munge_checksum(credits);
			munge_checksum(ship_kills);
			trumbleHash = munge_checksum(i);
			if (putativeHash == trumbleHash)
			{
				info_failed = NO;
				putativeNTrumbles = i;
			}
		}
		
		if (!info_failed)
			OOLog(@"cheat.verified", @"CHEAT DEFEATED - that's not the way to get rid of trumbles!");
	}
	// at this stage we've done the best we can to stop cheaters
	trumbleCount = putativeNTrumbles;

	if ((putativeTrumbleArray != nil) && ([putativeTrumbleArray count] == PLAYER_MAX_TRUMBLES))
	{
		for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
			[trumble[i] setFromDictionary:(NSDictionary *)[putativeTrumbleArray objectAtIndex:i]];
	}
	
	clear_checksum();
	[self mungChecksumWithNSString:player_name];
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(trumbleCount);
	
	[[NSUserDefaults standardUserDefaults]  setInteger:trumbleHash forKey:namekey];
}


- (void) mungChecksumWithNSString:(NSString*) str
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
		return [NSString stringWithFormat:@" Full Screen Mode: %d x %d at %.3g Hz ", inWidth, inHeight, inRate];
	}
	else
	{
		return [NSString stringWithFormat:@" Full Screen Mode: %d x %d ", inWidth, inHeight];
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
- (void) addTarget:(Entity *) targetEntity
{
	[super addTarget:targetEntity];
	if ([self hasExtraEquipment:@"EQ_TARGET_MEMORY"])
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
		ShipEntity* potential_target = [UNIVERSE entityForUniversalID: targ_id];

		if ((potential_target)&&(potential_target->isShip))
		{
			if (potential_target->zero_distance < SCANNER_MAX_RANGE2)
			{
				[super addTarget:potential_target];
				missile_status = MISSILE_STATUS_TARGET_LOCKED;
				[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-locked-onto-@]"), (ident_engaged)? @"Ident system": @"Missile", [(ShipEntity *)potential_target name]] forCount:4.5];
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
		ShipEntity* potential_target = [UNIVERSE entityForUniversalID: targ_id];

		if ((potential_target)&&(potential_target->isShip))
		{
			if (potential_target->zero_distance < SCANNER_MAX_RANGE2)
			{
				[super addTarget:potential_target];
				missile_status = MISSILE_STATUS_TARGET_LOCKED;
				[UNIVERSE addMessage:[NSString stringWithFormat:ExpandDescriptionForCurrentSystem(@"[@-locked-onto-@]"), (ident_engaged)? @"Ident system": @"Missile", [(ShipEntity *)potential_target name]] forCount:4.5];
				return YES;
			}
		}
		else
			target_memory[target_memory_index] = NO_TARGET;	// tidy_up
	}
	return NO;
}


- (Quaternion)customViewQuaternion
{
	return customViewQuaternion;
}


- (GLfloat*)customViewMatrix
{
	return customViewMatrix;
}


- (Vector)customViewOffset
{
	return customViewOffset;
}


- (Vector)customViewForwardVector
{
	return customViewForwardVector;
}


- (Vector)customViewUpVector
{
	return customViewUpVector;
}


- (Vector)customViewRightVector
{
	return customViewRightVector;
}


- (NSString*)customViewDescription
{
	return customViewDescription;
}


- (void)setCustomViewDataFromDictionary:(NSDictionary*) viewDict
{
	Quaternion view_q = kIdentityQuaternion;
	
	quaternion_into_gl_matrix(view_q, customViewMatrix);
	customViewOffset = kZeroVector;
	if (!viewDict)  return;
	
	ScanQuaternionFromString([viewDict objectForKey:@"view_orientation"], &view_q);
		
	customViewQuaternion = view_q;
	
	customViewRightVector = vector_right_from_quaternion(view_q);
	customViewUpVector = vector_up_from_quaternion(view_q);
	customViewForwardVector = vector_forward_from_quaternion(view_q);
	
	Quaternion q1 = view_q;	q1.w = -q1.w;
		
	quaternion_into_gl_matrix(q1, customViewMatrix);
	
	ScanVectorFromString([viewDict objectForKey:@"view_position"], &customViewOffset);
	customViewDescription = [viewDict objectForKey:@"view_description"];
	
	if ([viewDict objectForKey:@"weapon_facing"])
	{
		NSString* facing = [(NSString *)[viewDict objectForKey:@"view_description"] lowercaseString];
		if ([facing isEqual:@"forward"])
			currentWeaponFacing = VIEW_FORWARD;
		if ([facing isEqual:@"aft"])
			currentWeaponFacing = VIEW_AFT;
		if ([facing isEqual:@"port"])
			currentWeaponFacing = VIEW_PORT;
		if ([facing isEqual:@"forward"])
			currentWeaponFacing = VIEW_STARBOARD;
	}
	
}


- (BOOL)showInfoFlag
{
	return show_info_flag;
}


- (NSArray *) worldScriptNames
{
	return [worldScripts allKeys];
}


- (NSDictionary *) worldScriptsByName
{
	return [[worldScripts copy] autorelease];
}


- (void) doScriptEvent:(NSString *)message withArguments:(NSArray *)arguments
{
	[super doScriptEvent:message withArguments:arguments];
	[self doWorldScriptEvent:message withArguments:arguments];
}


- (void) doWorldScriptEvent:(NSString *)message withArguments:(NSArray *)arguments
{
	NSEnumerator	*scriptEnum;
	OOScript		*theScript;
	
	for (scriptEnum = [worldScripts objectEnumerator]; (theScript = [scriptEnum nextObject]); )
	{
		[theScript doEvent:message withArguments:arguments];
	}
}


#ifndef NDEBUG
- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	[super dumpSelfState];
	
	OOLog(@"dumpState.playerEntity", @"Ship: %@", ship_desc);
	OOLog(@"dumpState.playerEntity", @"Script time: %g", script_time);
	OOLog(@"dumpState.playerEntity", @"Script time check: %g", script_time_check);
	OOLog(@"dumpState.playerEntity", @"Script time interval: %g", script_time_interval);
	OOLog(@"dumpState.playerEntity", @"Roll/pitch/yaw delta: %g, %g, %g", roll_delta, pitch_delta, yaw_delta);
	OOLog(@"dumpState.playerEntity", @"Shield: %g fore, %g aft", forward_weapon, aft_shield);
	OOLog(@"dumpState.playerEntity", @"Alert level: %u, flags: %#x", alertFlags, alertCondition);
	OOLog(@"dumpState.playerEntity", @"Missile status: %i", missile_status);
	OOLog(@"dumpState.playerEntity", @"Energy unit: %@", EnergyUnitTypeToString(energy_unit));
	OOLog(@"dumpState.playerEntity", @"Shield booster: %i", shield_booster);
	OOLog(@"dumpState.playerEntity", @"Shield enhancer: %i", shield_enhancer);
	OOLog(@"dumpState.playerEntity", @"Fuel leak rate: %g", fuel_leak_rate);
	OOLog(@"dumpState.playerEntity", @"Trumble count: %u", trumbleCount);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(found_equipment);
	ADD_FLAG_IF_SET(pollControls);
	ADD_FLAG_IF_SET(has_energy_unit);
	ADD_FLAG_IF_SET(has_docking_computer);
	ADD_FLAG_IF_SET(has_galactic_hyperdrive);
	ADD_FLAG_IF_SET(saved);
	ADD_FLAG_IF_SET(suppressTargetLost);
	ADD_FLAG_IF_SET(scoopsActive);
	ADD_FLAG_IF_SET(game_over);
	ADD_FLAG_IF_SET(docked);
	ADD_FLAG_IF_SET(finished);
	ADD_FLAG_IF_SET(bomb_detonated);
	ADD_FLAG_IF_SET(autopilot_engaged);
	ADD_FLAG_IF_SET(afterburner_engaged);
	ADD_FLAG_IF_SET(afterburnerSoundLooping);
	ADD_FLAG_IF_SET(hyperspeed_engaged);
	ADD_FLAG_IF_SET(travelling_at_hyperspeed);
	ADD_FLAG_IF_SET(hyperspeed_locked);
	ADD_FLAG_IF_SET(ident_engaged);
	ADD_FLAG_IF_SET(galactic_witchjump);
	ADD_FLAG_IF_SET(ecm_in_operation);
	ADD_FLAG_IF_SET(show_info_flag);
	ADD_FLAG_IF_SET(showDemoShips);
	ADD_FLAG_IF_SET(rolling);
	ADD_FLAG_IF_SET(pitching);
	ADD_FLAG_IF_SET(yawing);
	ADD_FLAG_IF_SET(using_mining_laser);
	ADD_FLAG_IF_SET(mouse_control_on);
	ADD_FLAG_IF_SET(isSpeechOn);
	ADD_FLAG_IF_SET(ootunes_on);
	ADD_FLAG_IF_SET(docking_music_on);
	ADD_FLAG_IF_SET(keyboardRollPitchOverride);
	ADD_FLAG_IF_SET(waitingForStickCallback);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : @"none";
	OOLog(@"dumpState.playerEntity", @"Flags: %@", flagsString);
}
#endif

@end
