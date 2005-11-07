//
//  PlayerEntity (contracts).m
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
#import "Universe.h"
#import "AI.h"

//@interface PlayerEntity (Contracts)
//
//- (NSDictionary*) reputation;
//
//- (int) passengerReputation;
//- (void) increasePassengerReputation;
//- (void) decreasePassengerReputation;
//
//@end

//--------------------------------------------------------------------------------//

@implementation PlayerEntity (Contracts)

- (NSString *) checkPassengerContracts	// returns messages from any passengers whose status have changed
{
	NSString* result = nil;
	
	if (docked_station != [universe station])	// only drop off passengers or fulfil contracts at main station
		return nil;
	
	// check passenger contracts
	int i;
	for (i = 0; i < [passengers count]; i++)
	{
		NSDictionary* passenger_info = (NSDictionary *)[passengers objectAtIndex:i];
		NSString* passenger_name = (NSString *)[passenger_info objectForKey:PASSENGER_KEY_NAME];
		NSString* passenger_dest_name = (NSString *)[passenger_info objectForKey:PASSENGER_KEY_DESTINATION_NAME];
		int dest = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_DESTINATION] intValue];
		int dest_eta = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
		
		if (equal_seeds( system_seed, [universe systemSeedForSystemNumber:dest]))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				int fee = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_FEE] intValue];
				while ((randf() < 0.75)&&(dest_eta > 3600))	// delivered with more than an hour to spare and a decent customer?
				{
					fee *= 110;	// tip + 10%
					fee /= 100;
					dest_eta *= 0.5;
				}
				credits += 10 * fee;
				if (!result)
					result = @"";
				result = [NSString stringWithFormat:@"%@\n%@ thanks you, and pays you %d Cr for delivering them to %@.", result, passenger_name, fee, passenger_dest_name];
				[passengers removeObjectAtIndex:i--];
				[self increasePassengerReputation];
			}
			else
			{
				// but we're late!
				int fee = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_FEE] intValue] / 2;	// halve fare
				while (randf() < 0.5)	// maybe halve fare a few times!
					fee /= 2;
				credits += 10 * fee;
				if (!result)
					result = @"";
				result = [NSString stringWithFormat:@"%@\n%@ pays you %d Cr for eventually delivering them to %@.", result, passenger_name, fee, passenger_dest_name];
				[passengers removeObjectAtIndex:i--];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				if (!result)
					result = @"";
				result = [NSString stringWithFormat:@"%@\n%@ leaves your ship, annoyed that you have wasted so much of their time.", result, passenger_name];
				[passengers removeObjectAtIndex:i--];
				[self decreasePassengerReputation];
			}
		}
	}
	
	// check cargo contracts
	for (i = 0; i < [contracts count]; i++)
	{
		NSDictionary* contract_info = (NSDictionary *)[contracts objectAtIndex:i];
		NSString* contract_cargo_desc = (NSString *)[contract_info objectForKey:CONTRACT_KEY_CARGO_DESCRIPTION];
		int dest = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_DESTINATION] intValue];
		int dest_eta = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
		
		int premium = 10 * [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_PREMIUM] floatValue];
		int fee = 10 * [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_FEE] floatValue];
		
		int contract_cargo_type = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_CARGO_TYPE] intValue];
		int contract_amount = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_CARGO_AMOUNT] intValue];
		
		NSMutableArray* manifest = [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* commodityInfo = [NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:contract_cargo_type]];
		int quantity_on_hand =  [(NSNumber *)[commodityInfo objectAtIndex:MARKET_QUANTITY] intValue];
		
		if (equal_seeds( system_seed, [universe systemSeedForSystemNumber:dest]))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				if (quantity_on_hand >= contract_amount)
				{
					// with the goods too!
					//
					// remove the goods...
					quantity_on_hand -= contract_amount;
					[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity_on_hand]];
					[manifest replaceObjectAtIndex:contract_cargo_type withObject:commodityInfo];
					if (shipCommodityData)
						[shipCommodityData release];
					shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
					// pay the premium and fee
					credits += fee + premium;
					if (!result)
						result = @"";
					result = [NSString stringWithFormat:@"%@\nDroids unload the %@ and you are paid %.1f Cr.", result, contract_cargo_desc, (float)(fee + premium) / 10.0];
					[contracts removeObjectAtIndex:i--];
					// repute++
					[self increaseContractReputation];
				}
			}
			else
			{
				// but we're late!
				if (!result)
					result = @"";
				result = [NSString stringWithFormat:@"%@\nYou fail to deliver the %@ on time, and no-one wants to pay for it.", result, contract_cargo_desc];
				[contracts removeObjectAtIndex:i--];
				// repute--
				[self decreaseContractReputation];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				if (!result)
					result = @"";
				result = [NSString stringWithFormat:@"%@\nYou fail to deliver the %@ on time, and no-one will want to pay for it.", result, contract_cargo_desc];
				[contracts removeObjectAtIndex:i--];
				// repute--
				[self decreaseContractReputation];
			}
		}
	}
	
	// check passenger_record for expired contracts
	NSArray* names = [passenger_record allKeys];
	for (i = 0; i < [names count]; i++)
	{
		double dest_eta = [(NSNumber*)[passenger_record objectForKey:[names objectAtIndex:i]] doubleValue] - ship_clock;
		if (dest_eta < 0)
		{
			// check they're not STILL on board
			BOOL on_board = NO;
			int j;
			for (j = 0; j < [passengers count]; j++)
			{
				NSDictionary* passenger_info = (NSDictionary *)[passengers objectAtIndex:j];
				if ([[passenger_info objectForKey:PASSENGER_KEY_NAME] isEqual:[names objectAtIndex:i]])
					on_board = YES;
			}
			if (!on_board)
			{
				[passenger_record removeObjectForKey:[names objectAtIndex:i]];
			}
		}
	}
	
	// check contract_record for expired contracts
	NSArray* ids = [contract_record allKeys];
	for (i = 0; i < [ids count]; i++)
	{
		double dest_eta = [(NSNumber*)[contract_record objectForKey:[ids objectAtIndex:i]] doubleValue] - ship_clock;
		if (dest_eta < 0)
			[contract_record removeObjectForKey:[ids objectAtIndex:i]];
	}
	
	return result;
}

- (NSDictionary*) reputation
{
	return reputation;
}

- (int) passengerReputation
{
	int good = [(NSNumber*)[reputation objectForKey:PASSAGE_GOOD_KEY] intValue];
	int bad = [(NSNumber*)[reputation objectForKey:PASSAGE_BAD_KEY] intValue];
	int unknown = [(NSNumber*)[reputation objectForKey:PASSAGE_UNKNOWN_KEY] intValue];
	
	if (unknown > 0)
		unknown = 7 - (market_rnd % unknown);
	else
		unknown = 7;
	
	return (good + unknown - 2 * bad) / 2;	// return a number from -7 to +7
}

- (void) increasePassengerReputation
{
	int good = [(NSNumber*)[reputation objectForKey:PASSAGE_GOOD_KEY] intValue];
	int bad = [(NSNumber*)[reputation objectForKey:PASSAGE_BAD_KEY] intValue];
	int unknown = [(NSNumber*)[reputation objectForKey:PASSAGE_UNKNOWN_KEY] intValue];
	
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < 7)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < 7)
			good++;
	}
	[reputation setObject:[NSNumber numberWithInt:good]		forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:bad]		forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:unknown]	forKey:PASSAGE_UNKNOWN_KEY];
}

- (void) decreasePassengerReputation
{
	int good = [(NSNumber*)[reputation objectForKey:PASSAGE_GOOD_KEY] intValue];
	int bad = [(NSNumber*)[reputation objectForKey:PASSAGE_BAD_KEY] intValue];
	int unknown = [(NSNumber*)[reputation objectForKey:PASSAGE_UNKNOWN_KEY] intValue];
	
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < 7)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < 7)
			bad++;
	}
	[reputation setObject:[NSNumber numberWithInt:good]		forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:bad]		forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:unknown]	forKey:PASSAGE_UNKNOWN_KEY];
}

- (int) contractReputation
{
	int good = [(NSNumber*)[reputation objectForKey:CONTRACTS_GOOD_KEY] intValue];
	int bad = [(NSNumber*)[reputation objectForKey:CONTRACTS_BAD_KEY] intValue];
	int unknown = [(NSNumber*)[reputation objectForKey:CONTRACTS_UNKNOWN_KEY] intValue];
	
	if (unknown > 0)
		unknown = 7 - (market_rnd % unknown);
	else
		unknown = 7;
	
	return (good + unknown - 2 * bad) / 2;	// return a number from -7 to +7
}

- (void) increaseContractReputation
{
	int good = [(NSNumber*)[reputation objectForKey:CONTRACTS_GOOD_KEY] intValue];
	int bad = [(NSNumber*)[reputation objectForKey:CONTRACTS_BAD_KEY] intValue];
	int unknown = [(NSNumber*)[reputation objectForKey:CONTRACTS_UNKNOWN_KEY] intValue];
	
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < 7)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < 7)
			good++;
	}
	[reputation setObject:[NSNumber numberWithInt:good]		forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:bad]		forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:unknown]	forKey:CONTRACTS_UNKNOWN_KEY];
}

- (void) decreaseContractReputation
{
	int good = [(NSNumber*)[reputation objectForKey:CONTRACTS_GOOD_KEY] intValue];
	int bad = [(NSNumber*)[reputation objectForKey:CONTRACTS_BAD_KEY] intValue];
	int unknown = [(NSNumber*)[reputation objectForKey:CONTRACTS_UNKNOWN_KEY] intValue];
	
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < 7)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < 7)
			bad++;
	}
	[reputation setObject:[NSNumber numberWithInt:good]		forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:bad]		forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:unknown]	forKey:CONTRACTS_UNKNOWN_KEY];
}

- (void) erodeReputation
{
	int c_good = [(NSNumber*)[reputation objectForKey:CONTRACTS_GOOD_KEY] intValue];
	int c_bad = [(NSNumber*)[reputation objectForKey:CONTRACTS_BAD_KEY] intValue];
	int c_unknown = [(NSNumber*)[reputation objectForKey:CONTRACTS_UNKNOWN_KEY] intValue];
	int p_good = [(NSNumber*)[reputation objectForKey:PASSAGE_GOOD_KEY] intValue];
	int p_bad = [(NSNumber*)[reputation objectForKey:PASSAGE_BAD_KEY] intValue];
	int p_unknown = [(NSNumber*)[reputation objectForKey:PASSAGE_UNKNOWN_KEY] intValue];
	
	if (c_unknown < 7)
	{
		if (c_bad > 0)
			c_bad--;
		else
		{
			if (c_good > 0)
				c_good--;
		}
		c_unknown++;
	}
	
	if (p_unknown < 7)
	{
		if (p_bad > 0)
			p_bad--;
		else
		{
			if (p_good > 0)
				p_good--;
		}
		p_unknown++;
	}
	
	[reputation setObject:[NSNumber numberWithInt:c_good]		forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_bad]		forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_unknown]	forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_good]		forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_bad]		forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_unknown]	forKey:PASSAGE_UNKNOWN_KEY];
	
}

- (void) setGuiToContractsScreen
{
	int i;
	NSMutableArray*		row_info = [NSMutableArray arrayWithCapacity:5];
	
	// set up initial markets if there are none
	StationEntity* the_station = [universe station];
	if (![the_station localPassengers])
		[the_station setLocalPassengers:[NSMutableArray arrayWithArray:[universe passengersForSystem:system_seed atTime:ship_clock]]];
	if (![the_station localContracts])
		[the_station setLocalContracts:[NSMutableArray arrayWithArray:[universe contractsForSystem:system_seed atTime:ship_clock]]];
		
	NSMutableArray* passenger_market = [the_station localPassengers];
	NSMutableArray* contract_market = [the_station localContracts];
	
	// remove passenger contracts that the player has already agreed to or done
	for (i = 0; i < [passenger_market count]; i++)
	{
		NSDictionary* info = (NSDictionary *)[passenger_market objectAtIndex:i];
		NSString* p_name = (NSString *)[info objectForKey:PASSENGER_KEY_NAME];
		if ([passenger_record objectForKey:p_name])
			[passenger_market removeObjectAtIndex:i--];
	}

	// remove cargo contracts that the player has already agreed to or done
	for (i = 0; i < [contract_market count]; i++)
	{
		NSDictionary* info = (NSDictionary *)[contract_market objectAtIndex:i];
		NSString* cid = (NSString *)[info objectForKey:CONTRACT_KEY_ID];
		if ([contract_record objectForKey:cid])
			[contract_market removeObjectAtIndex:i--];
	}
		
	// if there are more than 5 contracts remove cargo contracts that are larger than the space available or cost more than can be afforded
	for (i = 0; ([contract_market count] > 5) && (i < [contract_market count]); i++)
	{
		NSDictionary* info = (NSDictionary *)[contract_market objectAtIndex:i];
		int cargo_space_required = [(NSNumber *)[info objectForKey:CONTRACT_KEY_CARGO_AMOUNT] intValue];
		int cargo_units = [universe unitsForCommodity:[(NSNumber *)[info objectForKey:CONTRACT_KEY_CARGO_TYPE] intValue]];
		if (cargo_units == UNITS_KILOGRAMS)
			cargo_space_required /= 1000;
		if (cargo_units == UNITS_GRAMS)
			cargo_space_required /= 1000000;
		float premium = [(NSNumber *)[info objectForKey:CONTRACT_KEY_PREMIUM] floatValue];
		if ((cargo_space_required > max_cargo - current_cargo)||(premium * 10 > credits))
			[contract_market removeObjectAtIndex:i--];
	}
		
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		int tab_stops[GUI_MAX_COLUMNS]; 
		int n_passengers = [passenger_market count];
		if (n_passengers > 5)
			n_passengers = 5;
		int n_contracts = [contract_market count];
		if (n_contracts > 5)
			n_contracts = 5;
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"%@ Carrier Market",[universe getSystemName:system_seed]]];
		//
		tab_stops[0] = 0;
		tab_stops[1] = 160;
		tab_stops[2] = 240;
		tab_stops[3] = 360;
		tab_stops[4] = 440;
		//
		[gui setTabStops:tab_stops];
		//
		[row_info addObject:@"Passenger Name:"];
		[row_info addObject:@"To:"];
		[row_info addObject:@"Within:"];
		[row_info addObject:@"Advance:"];
		[row_info addObject:@"Fee:"];
		//
		[gui setColor:[NSColor greenColor] forRow:GUI_ROW_PASSENGERS_LABELS];
		[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_PASSENGERS_LABELS];
		//
		for (i = 0; i < n_passengers; i++)
		{
			NSDictionary* passenger_info = (NSDictionary*)[passenger_market objectAtIndex:i];
			int dest_eta = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
			[row_info removeAllObjects];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[passenger_info objectForKey:PASSENGER_KEY_NAME]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[passenger_info objectForKey:PASSENGER_KEY_DESTINATION_NAME]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[universe shortTimeDescription:dest_eta]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_PREMIUM] stringValue]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_FEE] stringValue]]];
			[gui setColor:[NSColor yellowColor] forRow:GUI_ROW_PASSENGERS_START + i];
			[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_PASSENGERS_START + i];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_PASSENGERS_START + i];
		}
		//
		[row_info removeAllObjects];
		[row_info addObject:@"Cargo:"];
		[row_info addObject:@"To:"];
		[row_info addObject:@"Within:"];
		[row_info addObject:@"Premium:"];
		[row_info addObject:@"Pays:"];
		//
		[gui setColor:[NSColor greenColor] forRow:GUI_ROW_CARGO_LABELS];
		[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_CARGO_LABELS];
		//
		for (i = 0; i < n_contracts; i++)
		{
			NSDictionary* contract_info = (NSDictionary*)[contract_market objectAtIndex:i];
			int dest_eta = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
			[row_info removeAllObjects];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[contract_info objectForKey:CONTRACT_KEY_CARGO_DESCRIPTION]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[contract_info objectForKey:CONTRACT_KEY_DESTINATION_NAME]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[universe shortTimeDescription:dest_eta]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_PREMIUM] stringValue]]];
			[row_info addObject:[NSString stringWithFormat:@" %@ ",[(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_FEE] stringValue]]];
			[gui setColor:[NSColor yellowColor] forRow:GUI_ROW_CARGO_START + i];
			[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_CARGO_START + i];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_CARGO_START + i];
		}
		//
		[gui setText:[NSString stringWithFormat:@"Cash:\t%.1f Cr.\t\tLoad %d of %d t.\tPassengers %d of %d berths.", 0.1*credits, current_cargo, max_cargo, [passengers count], max_passengers]  forRow: GUI_ROW_MARKET_CASH];
		//
		for (i = GUI_ROW_CARGO_START + n_contracts; i < GUI_ROW_MARKET_CASH; i++)
		{
			[gui setText:@"" forRow:i];
			[gui setColor:[NSColor greenColor] forRow:i];
		}
		
		if (n_passengers > 0)
		{
			if (n_contracts > 0)
			{
				[gui setSelectableRange:NSMakeRange(GUI_ROW_PASSENGERS_START, GUI_ROW_CARGO_START + n_contracts)];
			}
			else
			{
				[gui setSelectableRange:NSMakeRange(GUI_ROW_PASSENGERS_START, GUI_ROW_PASSENGERS_START + n_passengers)];
			}
			if (([gui selectedRow] < GUI_ROW_PASSENGERS_START)||([gui selectedRow] >= GUI_ROW_CARGO_START + n_contracts))
				[gui setSelectedRow:GUI_ROW_PASSENGERS_START];
		}
		else
		{
			if (n_contracts > 0)
			{
				[gui setSelectableRange:NSMakeRange(GUI_ROW_CARGO_START, GUI_ROW_CARGO_START + n_contracts)];
				if (([gui selectedRow] < GUI_ROW_CARGO_START)||([gui selectedRow] >= GUI_ROW_CARGO_START + n_contracts))
					[gui setSelectedRow:GUI_ROW_CARGO_START];
			}
			else
			{
				// nothing to select
				[gui setNoSelectedRow];
			}
		}
		//
		if (([gui selectedRow] >= GUI_ROW_PASSENGERS_START)&&([gui selectedRow] < GUI_ROW_PASSENGERS_START + n_passengers))
		{
			NSString* long_info = (NSString*)[(NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START] objectForKey:PASSENGER_KEY_LONG_DESCRIPTION];
			[gui addLongText:long_info startingAtRow:GUI_ROW_CONTRACT_INFO_START align:GUI_ALIGN_LEFT];
		}
		if (([gui selectedRow] >= GUI_ROW_CARGO_START)&&([gui selectedRow] < GUI_ROW_CARGO_START + n_contracts))
		{
			NSString* long_info = (NSString*)[(NSDictionary*)[contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START] objectForKey:CONTRACT_KEY_LONG_DESCRIPTION];
			[gui addLongText:long_info startingAtRow:GUI_ROW_CONTRACT_INFO_START align:GUI_ALIGN_LEFT];
		}
		//
		[gui setShowTextCursor:NO];
	}
	
	gui_screen = GUI_SCREEN_CONTRACTS;

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_DOCKED];
}


- (BOOL) pickFromGuiContractsScreen
{
	GuiDisplayGen* gui = [universe gui];
	
	NSMutableArray* passenger_market = [[universe station] localPassengers];
	NSMutableArray* contract_market = [[universe station] localContracts];
	
	if (([gui selectedRow] >= GUI_ROW_PASSENGERS_START)&&([gui selectedRow] < GUI_ROW_CARGO_START))
	{
		NSDictionary* passenger_info = (NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START];
		NSString* passenger_name = (NSString *)[passenger_info objectForKey:PASSENGER_KEY_NAME];
		NSNumber* passenger_arrival_time = (NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_ARRIVAL_TIME];
		int passenger_premium = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_PREMIUM] intValue];
		if ([passengers count] >= max_passengers)
			return NO;
		[passengers addObject:passenger_info];
		[passenger_record setObject:passenger_arrival_time forKey:passenger_name];
		[passenger_market removeObject:passenger_info];
		credits += 10 * passenger_premium;
		
//		NSLog(@"DEBUG passengers:\n%@", [passengers description]);
		
		return YES;
	}
	
	if (([gui selectedRow] >= GUI_ROW_CARGO_START)&&([gui selectedRow] < GUI_ROW_MARKET_CASH))
	{
		NSDictionary* contract_info = (NSDictionary*)[contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START];
		NSString* contract_id = (NSString *)[contract_info objectForKey:CONTRACT_KEY_ID];
		NSNumber* contract_arrival_time = (NSNumber*)[contract_info objectForKey:CONTRACT_KEY_ARRIVAL_TIME];
		int contract_premium = [(NSNumber*)[contract_info objectForKey:PASSENGER_KEY_PREMIUM] intValue];
		int contract_amount = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_CARGO_AMOUNT] intValue];
		int contract_cargo_type = [(NSNumber*)[contract_info objectForKey:CONTRACT_KEY_CARGO_TYPE] intValue];
		int contract_cargo_units = [universe unitsForCommodity:contract_cargo_type];
		int cargo_space_required = contract_amount;
		if (contract_cargo_units == UNITS_KILOGRAMS)
			cargo_space_required /= 1000;
		if (contract_cargo_units == UNITS_GRAMS)
			cargo_space_required /= 1000000;
		
		// tests for refusal ...
		
		if (cargo_space_required > max_cargo - current_cargo)	// no room for cargo
			return NO;
			
		if (contract_premium * 10 > credits)					// can't afford contract
			return NO;
			
		// okay passed all tests ...
		
		// pay the premium
		credits -= 10 * contract_premium;
		// add commodity to what's being carried
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:contract_cargo_type]];
		int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		manifest_quantity += contract_amount;
		current_cargo += cargo_space_required;
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[manifest replaceObjectAtIndex:contract_cargo_type withObject:[NSArray arrayWithArray:manifest_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];

		[contracts addObject:contract_info];
		[contract_record setObject:contract_arrival_time forKey:contract_id];
		[contract_market removeObject:contract_info];
		
//		NSLog(@"DEBUG contracts:\n%@", [contracts description]);
		
		return YES;
	}
	return NO;
}

- (void) highlightSystemFromGuiContractsScreen
{
	MyOpenGLView*	gameView = (MyOpenGLView *)[universe gameView];
	GuiDisplayGen*	gui = [universe gui];
	
	NSMutableArray*	passenger_market = [[universe station] localPassengers];
	NSMutableArray*	contract_market = [[universe station] localContracts];
	
	if (([gui selectedRow] >= GUI_ROW_PASSENGERS_START)&&([gui selectedRow] < GUI_ROW_CARGO_START))
	{
		NSDictionary* passenger_info = (NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START];
		NSString* passenger_dest_name = (NSString *)[passenger_info objectForKey:PASSENGER_KEY_DESTINATION_NAME];
		[gameView setTypedString:[passenger_dest_name lowercaseString]];
		[self setGuiToLongRangeChartScreen];
	}
	
	if (([gui selectedRow] >= GUI_ROW_CARGO_START)&&([gui selectedRow] < GUI_ROW_MARKET_CASH))
	{
		NSDictionary* contract_info = (NSDictionary*)[contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START];
		NSString* contract_dest_name = (NSString *)[contract_info objectForKey:CONTRACT_KEY_DESTINATION_NAME];
		[gameView setTypedString:[contract_dest_name lowercaseString]];
		[self setGuiToLongRangeChartScreen];
	}
}

- (NSArray*) passengerList
{
	NSMutableArray* result = [NSMutableArray arrayWithCapacity:5];
	// check passenger contracts
	int i;
	for (i = 0; i < [passengers count]; i++)
	{
		NSDictionary* passenger_info = (NSDictionary *)[passengers objectAtIndex:i];
		NSString* passenger_name = (NSString *)[passenger_info objectForKey:PASSENGER_KEY_NAME];
		NSString* passenger_dest_name = (NSString *)[passenger_info objectForKey:PASSENGER_KEY_DESTINATION_NAME];
		int dest_eta = [(NSNumber*)[passenger_info objectForKey:PASSENGER_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
		
		NSString* short_desc = [NSString stringWithFormat:@"\t%@ travelling to %@ to arrive within %@.",
			passenger_name, passenger_dest_name, [universe shortTimeDescription:dest_eta]];
		
		[result addObject:short_desc];
	}
	return result;
}

- (NSArray*) contractList
{
	NSMutableArray* result = [NSMutableArray arrayWithCapacity:5];
	// check cargo contracts
	int i;
	for (i = 0; i < [contracts count]; i++)
	{
		NSDictionary* contract_info = (NSDictionary *)[contracts objectAtIndex:i];
		NSString* contract_cargo_desc = (NSString *)[contract_info objectForKey:CONTRACT_KEY_CARGO_DESCRIPTION];
		NSString* contract_dest_name = (NSString *)[contract_info objectForKey:PASSENGER_KEY_DESTINATION_NAME];
		int dest_eta = [(NSNumber*)[contract_info objectForKey:PASSENGER_KEY_ARRIVAL_TIME] doubleValue] - ship_clock;
		
		NSString* short_desc = [NSString stringWithFormat:@"\tDeliver %@ to %@ within %@.",
			contract_cargo_desc, contract_dest_name, [universe shortTimeDescription:dest_eta]];
		
		[result addObject:short_desc];
	}
	return result;
}

- (void) setGuiToManifestScreen
{	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		int i = 0;
		
		int n_manifest_rows = 8;
		int cargo_row = 2;
		int passenger_row = 2;
		int contracts_row = 2;
		int missions_row = 2;
		
		int tab_stops[GUI_MAX_COLUMNS]; 
		tab_stops[0] = 20;
		tab_stops[1] = 256;
		[gui setTabStops:tab_stops];
		
		NSArray*	cargoManifest = [self cargoList];
		NSArray*	passengerManifest = [self passengerList];
		NSArray*	contractManifest = [self contractList];
		NSArray*	missionsManifest = [self missionsList];

		int legal_index = 0;
		if (legal_status != 0)
			legal_index = (legal_status <= 50) ? 1 : 2;
		int rating = 0;
		int kills[8] = { 0x0008,  0x0010,  0x0020,  0x0040,  0x0080,  0x0200,  0x0A00,  0x1900 };
		while ((rating < 8)&&(kills[rating] <= ship_kills))
		{
			rating ++;
		}
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"Ship's Manifest",   player_name]];
		//
		[gui setText:[NSString stringWithFormat:@"Cargo %dt (%dt):", (status == STATUS_DOCKED)? current_cargo : [cargo count], max_cargo]	forRow:cargo_row - 1];
		[gui setText:@"\tNone."				forRow:cargo_row];
		[gui setColor:[NSColor yellowColor]	forRow:cargo_row - 1];
		[gui setColor:[NSColor greenColor]	forRow:cargo_row];
		//
		if ([cargoManifest count] > 0)
		{
			for (i = 0; i < n_manifest_rows; i++)
			{
				NSMutableArray*		row_info = [NSMutableArray arrayWithCapacity:2];
				if (i < [cargoManifest count])
					[row_info addObject:[cargoManifest objectAtIndex:i]];
				else
					[row_info addObject:@""];
				if (i + n_manifest_rows < [cargoManifest count])
					[row_info addObject:[cargoManifest objectAtIndex:i + n_manifest_rows]];
				else
					[row_info addObject:@""];
				[gui setArray:(NSArray *)row_info forRow:cargo_row + i];
				[gui setColor:[NSColor greenColor] forRow:cargo_row + i];
			}
		}
		
		if ([cargoManifest count] < n_manifest_rows)
			passenger_row = cargo_row + [cargoManifest count] + 2;
		else
			passenger_row = cargo_row + n_manifest_rows + 2;
		//
		[gui setText:[NSString stringWithFormat:@"Passengers %d (%d):", [passengerManifest count], max_passengers]	forRow:passenger_row - 1];
		[gui setText:@"\tNone."				forRow:passenger_row];
		[gui setColor:[NSColor yellowColor]	forRow:passenger_row - 1];
		[gui setColor:[NSColor greenColor]	forRow:passenger_row];
		//
		if ([passengerManifest count] > 0)
		{
			for (i = 0; i < [passengerManifest count]; i++)
			{
				[gui setText:(NSString*)[passengerManifest objectAtIndex:i] forRow:passenger_row + i];
				[gui setColor:[NSColor greenColor] forRow:passenger_row + i];
			}
		}
				
		contracts_row = passenger_row + [passengerManifest count] + 2;
		//
		[gui setText:@"Contracts:"			forRow:contracts_row - 1];
		[gui setText:@"\tNone."				forRow:contracts_row];
		[gui setColor:[NSColor yellowColor]	forRow:contracts_row - 1];
		[gui setColor:[NSColor greenColor]	forRow:contracts_row];
		//
		if ([contractManifest count] > 0)
		{
			for (i = 0; i < [contractManifest count]; i++)
			{
				[gui setText:(NSString*)[contractManifest objectAtIndex:i] forRow:contracts_row + i];
				[gui setColor:[NSColor greenColor] forRow:contracts_row + i];
			}
		}
		
		if ([missionsManifest count] > 0)
		{
			missions_row = contracts_row + [contractManifest count] + 2;
			//
			[gui setText:@"Missions:"			forRow:missions_row - 1];
			[gui setColor:[NSColor yellowColor]	forRow:missions_row - 1];
			//
			if ([missionsManifest count] > 0)
			{
				for (i = 0; i < [missionsManifest count]; i++)
				{
					[gui setText:(NSString*)[missionsManifest objectAtIndex:i] forRow:missions_row + i];
					[gui setColor:[NSColor greenColor] forRow:missions_row + i];
				}
			}
		}
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	gui_screen = GUI_SCREEN_MANIFEST;

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) setGuiToDeliveryReportScreenWithText:(NSString*) report
{
	GuiDisplayGen* gui = [universe gui];
	
	int text_row = 1;
	
	// GUI stuff
	{
		[gui clear];
		[gui setTitle:@"Delivery Report"];
		//
		[gui addLongText:report startingAtRow:text_row align:GUI_ALIGN_LEFT];

		[gui setText:[NSString stringWithFormat:@"Cash:\t%.1f Cr.\t\tLoad %d of %d t.\tPassengers %d of %d berths.", 0.1*credits, current_cargo, max_cargo, [passengers count], max_passengers]  forRow: GUI_ROW_MARKET_CASH];
		//
		[gui setText:@"Press Space Commander" forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[NSColor yellowColor] forRow:21];
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	

	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	gui_screen = GUI_SCREEN_REPORT;

	[self setShowDemoShips: NO];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: NO];
	[universe setViewDirection: VIEW_DOCKED];
}

// ---------------------------------------------------------------------- //

static NSMutableDictionary* currentShipyard = nil;

- (void) setGuiToShipyardScreen:(int) skip
{
	int i;
	
	// set up initial market if there is none
	StationEntity* the_station = [universe station];
	if (![the_station localShipyard])
		[the_station setLocalShipyard:[universe shipsForSaleForSystem:system_seed atTime:ship_clock]];
		
	NSMutableArray* shipyard = [the_station localShipyard];
		
	// remove ships that the player has already bought
	for (i = 0; i < [shipyard count]; i++)
	{
		NSDictionary* info = (NSDictionary *)[shipyard objectAtIndex:i];
		NSString* ship_id = (NSString *)[info objectForKey:SHIPYARD_KEY_ID];
		if ([shipyard_record objectForKey:ship_id])
			[shipyard removeObjectAtIndex:i--];
	}
	
	if (currentShipyard)	[currentShipyard release];
	currentShipyard = [[NSMutableDictionary alloc] initWithCapacity:[shipyard count]];

	for (i = 0; i < [shipyard count]; i++)
	{
		[currentShipyard	setObject:[shipyard objectAtIndex:i]
							forKey:(NSString *)[(NSDictionary *)[shipyard objectAtIndex:i] objectForKey:SHIPYARD_KEY_ID]];
	}
	
	NSString* shipName = (NSString*)[[universe getDictionaryForShip:ship_desc] objectForKey:KEY_NAME];
		
	int n_ships = [shipyard count];

	//error check
	if (skip < 0 )
		skip = 0;
	if (skip >= n_ships)
		skip = n_ships - 1;
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [universe gui];
		
		int tab_stops[GUI_MAX_COLUMNS]; 
		
		[gui clear];
		[gui setTitle:[NSString stringWithFormat:@"%@ Ships For Sale",[universe getSystemName:system_seed]]];
		//
		tab_stops[0] = 0;
		tab_stops[1] = 160;
		tab_stops[2] = 270;
		tab_stops[3] = 370;
		tab_stops[4] = 450;
		//
		[gui setTabStops:tab_stops];
		//
		int n_rows, start_row, previous = 0;
		//
		if (n_ships < MAX_ROWS_SHIPS_FOR_SALE)
		{
			skip = 0;
			previous = 0;
			n_rows = MAX_ROWS_SHIPS_FOR_SALE;
			start_row = GUI_ROW_SHIPYARD_START;
		}
		else
		{
			n_rows = MAX_ROWS_SHIPS_FOR_SALE - 1;
			start_row = GUI_ROW_SHIPYARD_START;
			if (skip > 0)
			{
				n_rows -= 1;
				start_row += 1;
				if (skip > MAX_ROWS_SHIPS_FOR_SALE)
					previous = skip - MAX_ROWS_SHIPS_FOR_SALE - 2;
				else
					previous = 0;
			}
		}
		
//		NSLog(@"DEBUG Ships for sale n_ships:%d MAX_ROWS_SHIPS_FOR_SALE:%d n_rows:%d skip:%d", n_ships, MAX_ROWS_SHIPS_FOR_SALE, n_rows, skip);
				
		//
		if (n_ships > 0)
		{
			[gui setColor:[NSColor greenColor] forRow:GUI_ROW_SHIPYARD_LABELS];
			[gui setArray:[NSArray arrayWithObjects: @"Ship Type:", @"Price:", @"Cargo:", @"Speed:", nil] forRow:GUI_ROW_SHIPYARD_LABELS];
			//
			if (skip > 0)
			{
				[gui setColor:[NSColor greenColor] forRow:GUI_ROW_SHIPYARD_START];
				[gui setArray:[NSArray arrayWithObjects:@" Back ", @" <-- ", nil] forRow:GUI_ROW_SHIPYARD_START];
				[gui setKey:[NSString stringWithFormat:@"More:%d", previous] forRow:GUI_ROW_SHIPYARD_START];
			}
			for (i = 0; (i < n_ships - skip)&(i < n_rows); i++)
			{
				NSDictionary* ship_info = (NSDictionary*)[shipyard objectAtIndex:i + skip];
				int ship_price = [(NSNumber*)[ship_info objectForKey:SHIPYARD_KEY_PRICE] intValue];
				[gui setColor:[NSColor yellowColor] forRow:start_row + i];
				[gui setArray:[NSArray arrayWithObjects:
						[NSString stringWithFormat:@" %@ ",[(NSDictionary*)[ship_info objectForKey:SHIPYARD_KEY_SHIP] objectForKey:KEY_NAME]],
						[NSString stringWithFormat:@" %d Cr. ",ship_price],
						nil]
					forRow:start_row + i];
				[gui setKey:(NSString*)[ship_info objectForKey:SHIPYARD_KEY_ID] forRow:start_row + i];
			}
			if (i < n_ships - skip)
			{
				[gui setColor:[NSColor greenColor] forRow:start_row + i];
				[gui setArray:[NSArray arrayWithObjects:@" More ", @" --> ", nil] forRow:start_row + i];
				[gui setKey:[NSString stringWithFormat:@"More:%d", n_rows + skip] forRow:start_row + i];
				i++;
			}
			//
			[gui setSelectableRange:NSMakeRange( GUI_ROW_SHIPYARD_START, i + start_row - GUI_ROW_SHIPYARD_START)];
			[self showShipyardInfoForSelection];
		}
		else
		{
			[gui setText:@"No ships available for purchase." forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
			[gui setColor:[NSColor greenColor] forRow:GUI_ROW_NO_SHIPS];
			//
			[gui setNoSelectedRow];
		}
		//
		int trade_in = [self yourTradeInValue];
		[gui setText:[NSString stringWithFormat:@"Your %@'s trade-in value: %d.0 Cr.", shipName, trade_in]  forRow: GUI_ROW_MARKET_CASH - 1];
		[gui setText:[NSString stringWithFormat:@"Total available: %.1f Cr.\t(%.1f Cr. Cash + %d.0 Cr. Trade.)", 0.1*credits + (float)trade_in, 0.1*credits, trade_in]  forRow: GUI_ROW_MARKET_CASH];
		//
		[gui setShowTextCursor:NO];
	}
	
	gui_screen = GUI_SCREEN_SHIPYARD;
	
	// the following are necessary...

	[self setShowDemoShips: (n_ships > 0)];
	[universe setDisplayText: YES];
	[universe setDisplayCursor: YES];
	[universe setViewDirection: VIEW_DOCKED];
}

- (void) showShipyardInfoForSelection
{
	int i;
	GuiDisplayGen* gui = [universe gui];
	int sel_row = [gui selectedRow];
	
//	NSLog(@"-- %d %d %d", sel_row, [gui selectableRange].location, [gui selectableRange].length);
	
	if (sel_row <= 0)
		return;
	
	NSMutableArray* row_info = [NSMutableArray arrayWithArray:(NSArray*)[gui objectForRow:GUI_ROW_SHIPYARD_LABELS]];
	while ([row_info count] < 4)
		[row_info addObject:@""];
	
	NSString* key = [gui keyForRow:sel_row];
	
//	NSDictionary* info = (NSDictionary *)[[docked_station localShipyard] objectAtIndex:sel_row - GUI_ROW_SHIPYARD_START];
	NSDictionary* info = (NSDictionary *)[currentShipyard objectForKey:key];
	
	if (info)
	{
		// the key is a particular ship - show the details
		NSString* sales_pitch = (NSString*)[info objectForKey:KEY_SHORT_DESCRIPTION];
		
		int cargo_rating = [(NSNumber*)[(NSDictionary *)[info objectForKey:SHIPYARD_KEY_SHIP] objectForKey:@"max_cargo"] intValue];
		float speed_rating = 0.001 * [(NSNumber*)[(NSDictionary *)[info objectForKey:SHIPYARD_KEY_SHIP] objectForKey:@"max_flight_speed"] intValue];
		NSArray* ship_extras = (NSArray*)[info objectForKey:KEY_EQUIPMENT_EXTRAS];
		for (i = 0; i < [ship_extras count]; i++)
		{
			if ([(NSString*)[ship_extras objectAtIndex:i] isEqual:@"EQ_CARGO_BAY"])
				cargo_rating += 15;
			if ([(NSString*)[ship_extras objectAtIndex:i] isEqual:@"EQ_PASSENGER_BERTH"])
				cargo_rating -= 5;
		}
		
		[row_info replaceObjectAtIndex:2 withObject:[NSString stringWithFormat:@"Cargo: %d TC", cargo_rating]];
		[row_info replaceObjectAtIndex:3 withObject:[NSString stringWithFormat:@"Speed: %.3f LS", speed_rating]];
		[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_SHIPYARD_LABELS];
		
		for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++)
		{
			[gui setText:@"" forRow:i];
			[gui setColor:[NSColor greenColor] forRow:i];
		}
		[gui addLongText:sales_pitch startingAtRow:GUI_ROW_SHIPYARD_INFO_START align:GUI_ALIGN_LEFT];
			
		// now display the ship
		[universe removeDemoShips];
		[self showShipyardModel:(NSDictionary*)[info objectForKey:SHIPYARD_KEY_SHIP]];
	}
	else
	{
		// the key is a particular model of ship which we must expand...
		// build an array from the entries for that model in the currentShipyard TODO
		// 
	}
}

- (void) showShipyardModel: (NSDictionary *)shipDict
{
	ShipEntity		*ship;
		
	if (!docked_station)
		return;
	
    quaternion_into_gl_matrix(q_rotation, rotMatrix);

	Quaternion		q2 = q_rotation;
	q2.w = -q2.w;
	Vector			pos = position;
	quaternion_rotate_about_axis(&q2,vector_right_from_quaternion(q2), 0.5 * PI);
	
	ship = [[ShipEntity alloc] init];	//retained
	
//	NSLog(@"DEBUG :>:>:> universe = %@", universe);
	
	[ship setUniverse:universe];
	[ship setUpShipFromDictionary:shipDict];
	
	double cr = ship->collision_radius;
	if (debug)
		NSLog(@"::::: showShipModel:'%@'.", [ship name]);
	[ship setQRotation: q2];
	// forward - right - up ...
	double	d1 = 6.4;
	double	dr = 1.2;
	double	du = 0.8;
	//
	pos.x += d1 * cr * v_forward.x;
	pos.y += d1 * cr * v_forward.y;
	pos.z += d1 * cr * v_forward.z;
	//	
	pos.x += dr * cr * v_right.x;
	pos.y += dr * cr * v_right.y;
	pos.z += dr * cr * v_right.z;
	//	
	pos.x += du * cr * v_up.x;
	pos.y += du * cr * v_up.y;
	pos.z += du * cr * v_up.z;
		
	[ship setStatus: STATUS_DEMO];
	[ship setPosition: pos];
	[ship setScanClass: CLASS_NO_DRAW];
	[ship setRoll: PI/10.0];
	[ship setPitch: PI/25.0];
	[universe addEntity: ship];
	[[ship getAI] setStateMachine: @"nullAI.plist"];
	
//	[universe setDisplayText:YES];	// tryout for lighting
//	ship->isSunlit = NO;	// DEBUG TEST
//
//	NSLog(@"DEBUG demo ship %@ %@", ship, (ship->isSunlit)? @"is SUNLIT.":@"is not sunlit.");

	[ship release];
	//
}

- (int) yourTradeInValue
{
	// returns down to 75% of the full credit value of your ship
	return ship_trade_in_factor * [universe tradeInValueForCommanderDictionary:[self commanderDataDictionary]] / 100;
}

- (BOOL) buySelectedShip
{
	GuiDisplayGen* gui = [universe gui];
	int sel_row = [gui selectedRow];
	
	if (sel_row <= 0)
		return NO;
	
	NSString* key = [gui keyForRow:sel_row];

	if ([key hasPrefix:@"More:"])
	{
//		NSLog(@"DEBUG Key is '%@'", key);
		
		int from_ship = [(NSString*)[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];

//		NSLog(@"DEBUG skipping %d", from_ship);

		[self setGuiToShipyardScreen:from_ship];
		if ([[universe gui] selectedRow] < 0)
			[[universe gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
		if (from_ship == 0)
			[[universe gui] setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
		return YES;
	}
	
	// first check you can afford it!
	NSDictionary* ship_info = (NSDictionary *)[currentShipyard objectForKey:key];
	int price = [(NSNumber*)[ship_info objectForKey:SHIPYARD_KEY_PRICE] intValue];
	int trade_in = [self yourTradeInValue];
	
	if ((price - trade_in) * 10 > credits)
		return NO;	// you can't afford it!
	
	// sell all the commodities carried
	int i;
	for (i = 0; i < [shipCommodityData count]; i++)
	{
		while ([self trySellingCommodity:i]);	// empty loop
	}
	
	// drop all passengers
	[passengers removeAllObjects];
		
	// contracts stay the same, so if you default - tough!
	
	// okay we need to switch the model used, lots of the stats, and add all the extras
	//
	////
	///
	//
	
	// pay over the mazoolah
	credits -= 10 * (price - trade_in);
	
	// change ship_desc
	if (ship_desc) [ship_desc release];
	ship_desc = [(NSString *)[ship_info objectForKey:SHIPYARD_KEY_SHIPDATA_KEY] retain];
		
	// get a full tank for free
	fuel = 70;
	
	// this ship has a clean record
	legal_status = 0;
	
	// get forward_weapon aft_weapon port_weapon starboard_weapon from ship_info
	aft_weapon = WEAPON_NONE;
	port_weapon = WEAPON_NONE;
	starboard_weapon = WEAPON_NONE;
	forward_weapon = [universe weaponForEquipmentKey:(NSString*)[(NSDictionary*)[ship_info objectForKey:SHIPYARD_KEY_SHIP] objectForKey:@"forward_weapon_type"]];
	
//	NSLog(@"%@ (%d) from %@",[(NSDictionary*)[ship_info objectForKey:SHIPYARD_KEY_SHIP] objectForKey:@"forward_weapon_type"],forward_weapon,[[ship_info objectForKey:SHIPYARD_KEY_SHIP] description]);
	
	// get basic max_cargo
	max_cargo = [universe maxCargoForShip:ship_desc];
	
	// reset BOOLS (has_ecm, has_scoop, has_energy_unit, has_docking_computer, has_galactic_hyperdrive, has_energy_bomb, has_escape_pod, has_fuel_injection)
	// and int (energy_unit)
	has_docking_computer = NO;
	has_ecm = NO;
	has_energy_bomb = NO;
	has_energy_unit = NO;
	has_escape_pod = NO;
	has_fuel_injection = NO;
	has_galactic_hyperdrive = NO;
	has_scoop = NO;
	energy_unit = ENERGY_UNIT_NONE;
	
	// ensure all missiles are tidied up and start at pylon 0
	[self tidyMissilePylons];

	// get missiles from ship_info
	missiles = [(NSNumber*)[(NSDictionary*)[ship_info objectForKey:SHIPYARD_KEY_SHIP] objectForKey:@"missiles"] intValue];
	
	// clear legal_status for free
	legal_status = 0;
	
	// reset max_passengers
	max_passengers = 0;
	
	// reset and refill extra_equipment then set flags from it
	[extra_equipment removeAllObjects];
	[self set_flags_from_extra_equipment];
	
	// refill from ship_info
	NSArray* extras = (NSArray*)[ship_info objectForKey:KEY_EQUIPMENT_EXTRAS];
	for (i = 0; i < [extras count]; i++)
	{
		NSString* eq_key = (NSString*)[extras objectAtIndex:i];
		if ([eq_key isEqual:@"EQ_PASSENGER_BERTH"])
		{
			max_passengers++;
			max_cargo -= 5;
		}
		else
		{
			[self add_extra_equipment:eq_key];	// BOOL flags are automatically set by this
		}
	}
	
	// add bought ship to shipyard_record
	[shipyard_record setObject:ship_desc forKey:[ship_info objectForKey:SHIPYARD_KEY_ID]];
	
	// remove the ship from the localShipyard
	[[docked_station localShipyard] removeObjectAtIndex:sel_row - GUI_ROW_SHIPYARD_START];
	
	// perform the transformation
	NSDictionary* cmdr_dict = [self commanderDataDictionary];	// gather up all the info
	[self setCommanderDataFromDictionary:cmdr_dict];			// apply all the info

	status = STATUS_DOCKED;
	
	// adjust the clock forward by an hour
	ship_clock_adjust += 3600.0;
	
	// finally we can get full hock if we sell it back
	ship_trade_in_factor = 100;
	
	return YES;
}


@end

