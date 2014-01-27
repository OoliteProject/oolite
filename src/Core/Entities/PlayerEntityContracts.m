/*

PlayerEntityContracts.m

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

#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "ProxyPlayerEntity.h"
#import "HeadUpDisplay.h"

#import "ShipEntityAI.h"
#import "Universe.h"
#import "AI.h"
#import "OOColor.h"
#import "OOCharacter.h"
#import "StationEntity.h"
#import "GuiDisplayGen.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "MyOpenGLView.h"
#import "NSStringOOExtensions.h"
#import "OOShipRegistry.h"
#import "OOEquipmentType.h"
#import "OOTexture.h"
#import "OOJavaScriptEngine.h"


static NSString * const kOOLogNoteShowShipyardModel = @"script.debug.note.showShipyardModel";
static unsigned RepForRisk(unsigned risk);

@interface PlayerEntity (ContractsPrivate)

- (OOCreditsQuantity) tradeInValue;
- (NSArray*) contractsListFromArray:(NSArray *) contracts_array forCargo:(BOOL) forCargo forParcels:(BOOL)forParcels;

@end


@implementation PlayerEntity (Contracts)

- (NSString *) processEscapePods // removes pods from cargo bay and treats categories of characters carried
{
	unsigned		i;
	BOOL added_entry = NO; // to prevent empty lines for slaves and the rare empty report.
	NSMutableString	*result = [NSMutableString string];
	NSMutableArray	*rescuees = [NSMutableArray array];
	OOGovernmentID	government = [[[UNIVERSE currentSystemData] objectForKey:KEY_GOVERNMENT] intValue];
	if ([UNIVERSE inInterstellarSpace])  government = 1;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
	
	// step through the cargo removing crew from any escape pods
	// No enumerator because we're mutating the array -- Ahruman
	for (i = 0; i < [cargo count]; i++)
	{
		ShipEntity	*cargoItem = [cargo objectAtIndex:i];
		NSArray		*podCrew = [cargoItem crew];
		
		if (podCrew != nil)
		{
			// Has crew -> is escape pod.
			[rescuees addObjectsFromArray:podCrew];
			[cargoItem setCrew:nil];
			[cargo removeObjectAtIndex:i];
			i--;
		}
	}
	
	// step through the rescuees awarding insurance or bounty or adding to slaves
	for (i = 0; i < [rescuees count]; i++)
	{
		OOCharacter *rescuee = [rescuees objectAtIndex:i];
		if ([rescuee script])
		{
			[rescuee doScriptEvent:OOJSID("unloadCharacter")];
		}
		else if ([rescuee legacyScript])
		{
			[self runUnsanitizedScriptActions:[rescuee legacyScript]
							allowingAIMethods:YES
							  withContextName:[NSString stringWithFormat:@"<character \"%@\" script>", [rescuee name]]
									forTarget:nil];
		}
		else if ([rescuee insuranceCredits] && [rescuee legalStatus])
		{
			float reward = (5.0 + government) * [rescuee legalStatus];
			float insurance = 10 * [rescuee insuranceCredits];
			if (government > (Ranrot() & 7) || reward >= insurance)
			{
				// claim bounty for capture, ignore insurance
				[result appendFormat:DESC(@"capture-reward-for-@@-@-credits-@-alt"),
				 [rescuee name], [rescuee shortDescription], OOStringFromDeciCredits(reward, YES, NO),
				 OOStringFromDeciCredits(insurance, YES, NO)];
				
			}
			else
			{
				// claim insurance reward with reduction of bounty
				[result appendFormat:DESC(@"rescue-reward-for-@@-@-credits-@-alt"),
				 [rescuee name], [rescuee shortDescription], OOStringFromDeciCredits(insurance - reward, YES, NO),
				 OOStringFromDeciCredits(reward, YES, NO)];
				reward = insurance - reward;
			}
			credits += reward;
			added_entry = YES;
		}
		else if ([rescuee insuranceCredits])
		{
			// claim insurance reward
			[result appendFormat:DESC(@"rescue-reward-for-@@-@-credits"),
				[rescuee name], [rescuee shortDescription], OOStringFromDeciCredits([rescuee insuranceCredits] * 10, YES, NO)];
			credits += 10 * [rescuee insuranceCredits];
			added_entry = YES;
		}
		else if ([rescuee legalStatus])
		{
			// claim bounty for capture
			float reward = (5.0 + government) * [rescuee legalStatus];
			[result appendFormat:DESC(@"capture-reward-for-@@-@-credits"),
				[rescuee name], [rescuee shortDescription], OOStringFromDeciCredits(reward, YES, NO)];
			credits += reward;
			added_entry = YES;
		}
		else
		{
			// sell as slave - increase no. of slaves in manifest
			[self awardCargo:@"1 Slaves"];
		}
		if ((i < [rescuees count] - 1) && added_entry)
			[result appendString:@"\n"];
		added_entry = NO;
	}
	
	[self calculateCurrentCargo];
	
	return result;
}


- (NSString *) checkPassengerContracts	// returns messages from any passengers whose status have changed
{
	if ([self dockedStation] != [UNIVERSE station])	// only drop off passengers or fulfil contracts at main station
		return nil;
	
	// check escape pods...
	// TODO
	
	NSMutableString		*result = [NSMutableString string];
	unsigned			i;
	
	// check passenger contracts
	for (i = 0; i < [passengers count]; i++)
	{
		NSDictionary* passenger_info = [passengers oo_dictionaryAtIndex:i];
		NSString* passenger_name = [passenger_info oo_stringForKey:PASSENGER_KEY_NAME];
		int dest = [passenger_info oo_intForKey:CONTRACT_KEY_DESTINATION];
		Random_Seed dest_seed = [UNIVERSE systemSeedForSystemNumber:dest];
		// the system name can change via script
		NSString* passenger_dest_name = [UNIVERSE getSystemName: dest_seed];
		int dest_eta = [passenger_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		
		if (equal_seeds( system_seed, dest_seed))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				long long fee = [passenger_info oo_longLongForKey:CONTRACT_KEY_FEE];
				while ((randf() < 0.75)&&(dest_eta > 3600))	// delivered with more than an hour to spare and a decent customer?
				{
					fee *= 110;	// tip + 10%
					fee /= 100;
					dest_eta *= 0.5;
				}
				credits += 10 * fee;
				
				[result appendFormatLine:DESC(@"passenger-delivered-okay-@-@-@"), passenger_name, OOIntCredits(fee), passenger_dest_name];
				[self addRoleToPlayer:@"trader-courier+"];

				[self increasePassengerReputation:RepForRisk([passenger_info oo_unsignedIntForKey:CONTRACT_KEY_RISK defaultValue:0])];
				[passengers removeObjectAtIndex:i--];
			}
			else
			{
				// but we're late!
				long long fee = [passenger_info oo_longLongForKey:CONTRACT_KEY_FEE] / 2;	// halve fare
				while (randf() < 0.5)	// maybe halve fare a few times!
					fee /= 2;
				credits += 10 * fee;
				
				[result appendFormatLine:DESC(@"passenger-delivered-late-@-@-@"), passenger_name, OOIntCredits(fee), passenger_dest_name];
				[self addRoleToPlayer:@"trader-courier+"];

				[passengers removeObjectAtIndex:i--];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				[result appendFormatLine:DESC(@"passenger-failed-@"), passenger_name];
				
				[self decreasePassengerReputation:RepForRisk([passenger_info oo_unsignedIntForKey:CONTRACT_KEY_RISK defaultValue:0])];
				[passengers removeObjectAtIndex:i--];
			}
		}
	}

	// check parcel contracts
	for (i = 0; i < [parcels count]; i++)
	{
		NSDictionary* parcel_info = [parcels oo_dictionaryAtIndex:i];
		NSString* parcel_name = [parcel_info oo_stringForKey:PASSENGER_KEY_NAME];
		int dest = [parcel_info oo_intForKey:CONTRACT_KEY_DESTINATION];
		Random_Seed dest_seed = [UNIVERSE systemSeedForSystemNumber:dest];
		int dest_eta = [parcel_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		
		if (equal_seeds( system_seed, dest_seed))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				long long fee = [parcel_info oo_longLongForKey:CONTRACT_KEY_FEE];
				while ((randf() < 0.75)&&(dest_eta > 86400))	// delivered with more than a day to spare and a decent customer?
				{
					// lower tips than passengers
					fee *= 110;	// tip + 10%
					fee /= 100;
					dest_eta *= 0.5;
				}
				credits += 10 * fee;
				
				[result appendFormatLine:DESC(@"parcel-delivered-okay-@-@"), parcel_name, OOIntCredits(fee)];
				
				[self increaseParcelReputation:RepForRisk([parcel_info oo_unsignedIntForKey:CONTRACT_KEY_RISK defaultValue:0])];

				[parcels removeObjectAtIndex:i--];
				[self addRoleToPlayer:@"trader-courier+"];
			}
			else
			{
				// but we're late!
				long long fee = [parcel_info oo_longLongForKey:CONTRACT_KEY_FEE] / 2;	// halve fare
				while (randf() < 0.5)	// maybe halve fare a few times!
					fee /= 2;
				credits += 10 * fee;
				
				[result appendFormatLine:DESC(@"parcel-delivered-late-@-@"), parcel_name, OOIntCredits(fee)];
				[self addRoleToPlayer:@"trader-courier+"];
				[parcels removeObjectAtIndex:i--];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				[result appendFormatLine:DESC(@"parcel-failed-@"), parcel_name];
				
				[self decreaseParcelReputation:RepForRisk([parcel_info oo_unsignedIntForKey:CONTRACT_KEY_RISK defaultValue:0])];
				[parcels removeObjectAtIndex:i--];
			}
		}
	}

	
	// check cargo contracts
	for (i = 0; i < [contracts count]; i++)
	{
		NSDictionary* contract_info = [contracts oo_dictionaryAtIndex:i];
		NSString* contract_cargo_desc = [contract_info oo_stringForKey:CARGO_KEY_DESCRIPTION];
		int dest = [contract_info oo_intForKey:CONTRACT_KEY_DESTINATION];
		int dest_eta = [contract_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
	
		// no longer needed
		// int premium = 10 * [contract_info oo_floatForKey:CONTRACT_KEY_PREMIUM];
		int fee = 10 * [contract_info oo_floatForKey:CONTRACT_KEY_FEE];
		
		int contract_cargo_type = [contract_info oo_intForKey:CARGO_KEY_TYPE];
		int contract_amount = [contract_info oo_intForKey:CARGO_KEY_AMOUNT];
		
		NSMutableArray* manifest = [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* commodityInfo = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:contract_cargo_type]];
		int quantity_on_hand =  [commodityInfo oo_intAtIndex:MARKET_QUANTITY];
		
		if (equal_seeds(system_seed, [UNIVERSE systemSeedForSystemNumber:dest]))
		{
			// we've arrived in system!
			if (dest_eta > 0)
			{
				// and in good time
				if (quantity_on_hand >= contract_amount)
				{
					// with the goods too!
					
					// remove the goods...
					quantity_on_hand -= contract_amount;
					[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:quantity_on_hand]];
					[manifest replaceObjectAtIndex:contract_cargo_type withObject:commodityInfo];
					if (shipCommodityData)
						[shipCommodityData release];
					shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
					// pay the premium and fee
					// credits += fee + premium;
					// not any more: all contracts initially awarded by JS, so fee
					// is now all that needs to be paid - CIM

					if ([UNIVERSE legalStatusOfCommodity:[commodityInfo objectAtIndex:MARKET_NAME]] > 0)
					{
						[self addRoleToPlayer:@"trader-smuggler"];
					}
					else
					{
						[self addRoleToPlayer:@"trader"];
					}
					
					credits += fee;
					[result appendFormatLine:DESC(@"cargo-delivered-okay-@-@"), contract_cargo_desc, OOCredits(fee)];
					
					[contracts removeObjectAtIndex:i--];
					// repute++
					// +10 as cargo contracts don't have risk modifiers
					[self increaseContractReputation:10];
				}
				else
				{
					// see if the amount of goods delivered is acceptable
					
					float percent_delivered = 100.0 * (float)quantity_on_hand/(float)contract_amount;
					float acceptable_ratio = 100.0 - 10.0 * system_seed.a / 256.0; // down to 90%
					
					if (percent_delivered >= acceptable_ratio)
					{
						// remove the goods...
						[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
						[manifest replaceObjectAtIndex:contract_cargo_type withObject:commodityInfo];
						[shipCommodityData release];
						shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
						// pay the fee
						int shortfall = 100 - percent_delivered;
						int payment = percent_delivered * (fee) / 100.0;
						credits += payment;
						
						if ([UNIVERSE legalStatusOfCommodity:[commodityInfo objectAtIndex:MARKET_NAME]] > 0)
						{
							[self addRoleToPlayer:@"trader-smuggler"];
						}
						else
						{
							[self addRoleToPlayer:@"trader"];
						}

						[result appendFormatLine:DESC(@"cargo-delivered-short-@-@-d"), contract_cargo_desc, OOCredits(payment), shortfall];
						
						[contracts removeObjectAtIndex:i--];
						// repute unchanged
					}
					else
					{
						[result appendFormatLine:DESC(@"cargo-refused-short-%@"), contract_cargo_desc];
						// The player has still time to buy the missing goods elsewhere and fulfil the contract.
					}
				}
			}
			else
			{
				// but we're late!
				[result appendFormatLine:DESC(@"cargo-delivered-late-@"), contract_cargo_desc];

				[contracts removeObjectAtIndex:i--];
				// repute--
				[self decreaseContractReputation:10];
			}
		}
		else
		{
			if (dest_eta < 0)
			{
				// we've run out of time!
				[result appendFormatLine:DESC(@"cargo-failed-@"), contract_cargo_desc];
				
				[contracts removeObjectAtIndex:i--];
				// repute--
				[self decreaseContractReputation:10];
			}
		}
	}
	
	// check passenger_record for expired contracts
	NSArray* names = [passenger_record allKeys];
	for (i = 0; i < [names count]; i++)
	{
		double dest_eta = [passenger_record oo_doubleForKey:[names objectAtIndex:i]] - ship_clock;
		if (dest_eta < 0)
		{
			// check they're not STILL on board
			BOOL on_board = NO;
			unsigned j;
			for (j = 0; j < [passengers count]; j++)
			{
				NSDictionary* passenger_info = [passengers oo_dictionaryAtIndex:j];
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
		{
			[contract_record removeObjectForKey:[ids objectAtIndex:i]];
		}
	}

	// check parcel_record for expired deliveries
	ids = [parcel_record allKeys];
	for (i = 0; i < [ids count]; i++)
	{
		double dest_eta = [(NSNumber*)[parcel_record objectForKey:[ids objectAtIndex:i]] doubleValue] - ship_clock;
		if (dest_eta < 0)
		{
			[parcel_record removeObjectForKey:[ids objectAtIndex:i]];
		}
	}

	
	if ([result length] == 0)
	{
		result = nil;
	}
	else
	{
		// Should have a trailing \n
		[result deleteCharacterAtIndex:[result length] - 1];
	}
	
	return result;
}


- (void) addMessageToReport:(NSString*) report
{
	if ([report length] != 0)
	{
		if ([dockingReport length] == 0)
			[dockingReport appendString:report];
		else
			[dockingReport appendFormat:@"\n\n%@", report];
	}
}


- (NSDictionary*) reputation
{
	return reputation;
}


- (int) passengerReputation
{
	int good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];

	if (unknown > 0)
		unknown = MAX_CONTRACT_REP - (((2*unknown)+(market_rnd % unknown))/3);
	else
		unknown = MAX_CONTRACT_REP;
	
	return (good + unknown - 3 * bad) / 2;	// return a number from -MAX_CONTRACT_REP to +MAX_CONTRACT_REP
}


- (void) increasePassengerReputation:(unsigned)amount
{
	int good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	
	for (unsigned i=0;i<amount;i++)
	{
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < MAX_CONTRACT_REP)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < MAX_CONTRACT_REP)
			good++;
	}
	}
	[reputation oo_setInteger:good		forKey:PASSAGE_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:PASSAGE_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:PASSAGE_UNKNOWN_KEY];
}


- (void) decreasePassengerReputation:(unsigned)amount
{
	int good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	
for (unsigned i=0;i<amount;i++)
	{
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < MAX_CONTRACT_REP)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < MAX_CONTRACT_REP)
			bad++;
	}
	}
	[reputation oo_setInteger:good		forKey:PASSAGE_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:PASSAGE_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:PASSAGE_UNKNOWN_KEY];
}


- (int) parcelReputation
{
	int good = [reputation oo_intForKey:PARCEL_GOOD_KEY];
	int bad = [reputation oo_intForKey:PARCEL_BAD_KEY];
	int unknown = [reputation oo_intForKey:PARCEL_UNKNOWN_KEY];
	
	if (unknown > 0)
		unknown = MAX_CONTRACT_REP - (((2*unknown)+(market_rnd % unknown))/3);
	else
		unknown = MAX_CONTRACT_REP;
	
	return (good + unknown - 3 * bad) / 2;	// return a number from -MAX_CONTRACT_REP to +MAX_CONTRACT_REP
}


- (void) increaseParcelReputation:(unsigned)amount
{
	int good = [reputation oo_intForKey:PARCEL_GOOD_KEY];
	int bad = [reputation oo_intForKey:PARCEL_BAD_KEY];
	int unknown = [reputation oo_intForKey:PARCEL_UNKNOWN_KEY];

		for (unsigned i=0;i<amount;i++)
	{
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < MAX_CONTRACT_REP)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < MAX_CONTRACT_REP)
			good++;
	}
	}
	[reputation oo_setInteger:good		forKey:PARCEL_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:PARCEL_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:PARCEL_UNKNOWN_KEY];
}


- (void) decreaseParcelReputation:(unsigned)amount
{
	int good = [reputation oo_intForKey:PARCEL_GOOD_KEY];
	int bad = [reputation oo_intForKey:PARCEL_BAD_KEY];
	int unknown = [reputation oo_intForKey:PARCEL_UNKNOWN_KEY];
	
	for (unsigned i=0;i<amount;i++)
	{
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < MAX_CONTRACT_REP)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < MAX_CONTRACT_REP)
			bad++;
	}
	}
	[reputation oo_setInteger:good		forKey:PARCEL_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:PARCEL_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:PARCEL_UNKNOWN_KEY];
}


- (int) contractReputation
{
	int good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	
	if (unknown > 0)
		unknown = MAX_CONTRACT_REP - (((2*unknown)+(market_rnd % unknown))/3);
	else
		unknown = MAX_CONTRACT_REP;
	
	return (good + unknown - 3 * bad) / 2;	// return a number from -MAX_CONTRACT_REP to +MAX_CONTRACT_REP
}


- (void) increaseContractReputation:(unsigned)amount
{
	int good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	
	for (unsigned i=0;i<amount;i++)
	{
	if (bad > 0)
	{
		// shift a bean from bad to unknown
		bad--;
		if (unknown < MAX_CONTRACT_REP)
			unknown++;
	}
	else
	{
		// shift a bean from unknown to good
		if (unknown > 0)
			unknown--;
		if (good < MAX_CONTRACT_REP)
			good++;
	}
	}
	[reputation oo_setInteger:good		forKey:CONTRACTS_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:CONTRACTS_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:CONTRACTS_UNKNOWN_KEY];
}


- (void) decreaseContractReputation:(unsigned)amount
{
	int good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	
	for (unsigned i=0;i<amount;i++)
	{
	if (good > 0)
	{
		// shift a bean from good to bad
		good--;
		if (bad < MAX_CONTRACT_REP)
			bad++;
	}
	else
	{
		// shift a bean from unknown to bad
		if (unknown > 0)
			unknown--;
		if (bad < MAX_CONTRACT_REP)
			bad++;
	}
	}
	[reputation oo_setInteger:good		forKey:CONTRACTS_GOOD_KEY];
	[reputation oo_setInteger:bad		forKey:CONTRACTS_BAD_KEY];
	[reputation oo_setInteger:unknown	forKey:CONTRACTS_UNKNOWN_KEY];
}


- (void) erodeReputation
{
	int c_good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int c_bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int c_unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	int p_good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int p_bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int p_unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	int pl_good = [reputation oo_intForKey:PARCEL_GOOD_KEY];
	int pl_bad = [reputation oo_intForKey:PARCEL_BAD_KEY];
	int pl_unknown = [reputation oo_intForKey:PARCEL_UNKNOWN_KEY];
	
	if (c_unknown < MAX_CONTRACT_REP)
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
	
	if (p_unknown < MAX_CONTRACT_REP)
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

	if (pl_unknown < MAX_CONTRACT_REP)
	{
		if (pl_bad > 0)
			pl_bad--;
		else
		{
			if (pl_good > 0)
				pl_good--;
		}
		pl_unknown++;
	}
	
	[reputation setObject:[NSNumber numberWithInt:c_good]		forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_bad]		forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_unknown]	forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_good]		forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_bad]		forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_unknown]	forKey:PASSAGE_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:pl_good]		forKey:PARCEL_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:pl_bad]		forKey:PARCEL_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:pl_unknown]	forKey:PARCEL_UNKNOWN_KEY];
	
}


/* Update reputation levels in case of change in MAX_CONTRACT_REP */
- (void) normaliseReputation
{
	int c_good = [reputation oo_intForKey:CONTRACTS_GOOD_KEY];
	int c_bad = [reputation oo_intForKey:CONTRACTS_BAD_KEY];
	int c_unknown = [reputation oo_intForKey:CONTRACTS_UNKNOWN_KEY];
	int p_good = [reputation oo_intForKey:PASSAGE_GOOD_KEY];
	int p_bad = [reputation oo_intForKey:PASSAGE_BAD_KEY];
	int p_unknown = [reputation oo_intForKey:PASSAGE_UNKNOWN_KEY];
	int pl_good = [reputation oo_intForKey:PARCEL_GOOD_KEY];
	int pl_bad = [reputation oo_intForKey:PARCEL_BAD_KEY];
	int pl_unknown = [reputation oo_intForKey:PARCEL_UNKNOWN_KEY];

	int c = c_good + c_bad + c_unknown;
	if (c == 0)
	{
		c_unknown = MAX_CONTRACT_REP;
	}
	else if (c != MAX_CONTRACT_REP)
	{
		c_good = c_good * MAX_CONTRACT_REP / c;
		c_bad = c_bad * MAX_CONTRACT_REP / c;
		c_unknown = MAX_CONTRACT_REP - c_good - c_bad;
	}

	int p = p_good + p_bad + p_unknown;
	if (p == 0)
	{
		p_unknown = MAX_CONTRACT_REP;
	}
	else if (p != MAX_CONTRACT_REP)
	{
		p_good = p_good * MAX_CONTRACT_REP / p;
		p_bad = p_bad * MAX_CONTRACT_REP / p;
		p_unknown = MAX_CONTRACT_REP - p_good - p_bad;
	}
	
	int pl = pl_good + pl_bad + pl_unknown;
	if (pl == 0)
	{
		pl_unknown = MAX_CONTRACT_REP;
	}
	else if (pl != MAX_CONTRACT_REP)
	{
		pl_good = pl_good * MAX_CONTRACT_REP / pl;
		pl_bad = pl_bad * MAX_CONTRACT_REP / pl;
		pl_unknown = MAX_CONTRACT_REP - pl_good - pl_bad;
	}

	[reputation setObject:[NSNumber numberWithInt:c_good]		forKey:CONTRACTS_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_bad]		forKey:CONTRACTS_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:c_unknown]	forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_good]		forKey:PASSAGE_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_bad]		forKey:PASSAGE_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:p_unknown]	forKey:PASSAGE_UNKNOWN_KEY];
	[reputation setObject:[NSNumber numberWithInt:pl_good]		forKey:PARCEL_GOOD_KEY];
	[reputation setObject:[NSNumber numberWithInt:pl_bad]		forKey:PARCEL_BAD_KEY];
	[reputation setObject:[NSNumber numberWithInt:pl_unknown]	forKey:PARCEL_UNKNOWN_KEY];
	
}


- (BOOL) addPassenger:(NSString*)Name start:(unsigned)start destination:(unsigned)Destination eta:(double)eta fee:(double)fee advance:(double)advance risk:(unsigned)risk
{
	NSDictionary* passenger_info = [NSDictionary dictionaryWithObjectsAndKeys:
		Name,											PASSENGER_KEY_NAME,
		[NSNumber numberWithInt:start],					CONTRACT_KEY_START,
		[NSNumber numberWithInt:Destination],			CONTRACT_KEY_DESTINATION,
		[NSNumber numberWithDouble:[PLAYER clockTime]],	CONTRACT_KEY_DEPARTURE_TIME,
		[NSNumber numberWithDouble:eta],				CONTRACT_KEY_ARRIVAL_TIME,
		[NSNumber numberWithDouble:fee],				CONTRACT_KEY_FEE,
		[NSNumber numberWithDouble:advance],			CONTRACT_KEY_PREMIUM,
		[NSNumber numberWithUnsignedInt:risk],			CONTRACT_KEY_RISK,

		NULL];
	
	// extra checks, just in case.
	if ([passengers count] >= max_passengers || [passenger_record objectForKey:Name] != nil) return NO;
		
	[self addRoleToPlayer:@"trader-courier+"];

	[passengers addObject:passenger_info];
	[passenger_record setObject:[NSNumber numberWithDouble:eta] forKey:Name];
	return YES;
}


- (BOOL) removePassenger:(NSString*)Name	// removes the first passenger that answers to Name, returns NO if none found
{	
	// extra check, just in case.
	if ([passengers count] == 0) return NO;
	
	unsigned			i;
	
	for (i = 0; i < [passengers count]; i++)
	{
		NSString		*this_name = [[passengers oo_dictionaryAtIndex:i] oo_stringForKey:PASSENGER_KEY_NAME];
		
		if ([Name isEqualToString:this_name])
		{
			[passengers removeObjectAtIndex:i];
			[passenger_record removeObjectForKey:Name];
			return YES;
		}
	}
	
	return NO;
}


- (BOOL) addParcel:(NSString*)Name start:(unsigned)start destination:(unsigned)Destination eta:(double)eta fee:(double)fee premium:(double)premium risk:(unsigned)risk
{
	NSDictionary* parcel_info = [NSDictionary dictionaryWithObjectsAndKeys:
		Name,											PASSENGER_KEY_NAME,
		[NSNumber numberWithInt:start],					CONTRACT_KEY_START,
		[NSNumber numberWithInt:Destination],			CONTRACT_KEY_DESTINATION,
		[NSNumber numberWithDouble:[PLAYER clockTime]],	CONTRACT_KEY_DEPARTURE_TIME,
		[NSNumber numberWithDouble:eta],				CONTRACT_KEY_ARRIVAL_TIME,
		[NSNumber numberWithDouble:fee],				CONTRACT_KEY_FEE,
		[NSNumber numberWithDouble:premium],			CONTRACT_KEY_PREMIUM,
		[NSNumber numberWithUnsignedInt:risk],			CONTRACT_KEY_RISK,
		NULL];
	
	// extra checks, just in case.
	if ([parcel_record objectForKey:Name] != nil) return NO;

	if ([parcels count] == 0 || risk > 0)
	{
		[self addRoleToPlayer:@"trader-courier+"];
	}
		
	[parcels addObject:parcel_info];
	[parcel_record setObject:[NSNumber numberWithDouble:eta] forKey:Name];
	return YES;
}


- (BOOL) removeParcel:(NSString*)Name	// removes the first parcel that answers to Name, returns NO if none found
{	
	// extra check, just in case.
	if ([parcels count] == 0) return NO;
	
	unsigned			i;
	
	for (i = 0; i < [parcels count]; i++)
	{
		NSString		*this_name = [[parcels oo_dictionaryAtIndex:i] oo_stringForKey:PASSENGER_KEY_NAME];
		
		if ([Name isEqualToString:this_name])
		{
			[parcels removeObjectAtIndex:i];
			[parcel_record removeObjectForKey:Name];
			return YES;
		}
	}
	
	return NO;
}


- (BOOL) awardContract:(unsigned)qty commodity:(NSString*)commodity start:(unsigned)start
					 destination:(unsigned)Destination eta:(double)eta fee:(double)fee premium:(double)premium
{
	OOCommodityType	type = [UNIVERSE commodityForName: commodity];
	Random_Seed		r_seed = [UNIVERSE marketSeed];
	int				sr1 = r_seed.a * 0x10000 + r_seed.c * 0x100 + r_seed.e;
	int				sr2 = r_seed.b * 0x10000 + r_seed.d * 0x100 + r_seed.f;
	NSString		*cargo_ID =[NSString stringWithFormat:@"%06x-%06x", sr1, sr2];
	
	if (type == COMMODITY_UNDEFINED)  return NO;
	if (qty < 1)  return NO;
	
	// avoid duplicate cargo_IDs
	while ([contract_record objectForKey:cargo_ID] != nil)
	{
		sr2++;
		cargo_ID =[NSString stringWithFormat:@"%06x-%06x", sr1, sr2];
	}

	NSDictionary* cargo_info = [NSDictionary dictionaryWithObjectsAndKeys:
		cargo_ID,										CARGO_KEY_ID,
		[NSNumber numberWithInteger:type],				CARGO_KEY_TYPE,
		[NSNumber numberWithInt:qty],					CARGO_KEY_AMOUNT,
		[UNIVERSE describeCommodity:type amount:qty],	CARGO_KEY_DESCRIPTION,
		[NSNumber numberWithInt:start],					CONTRACT_KEY_START,
		[NSNumber numberWithInt:Destination],			CONTRACT_KEY_DESTINATION,
		[NSNumber numberWithDouble:[PLAYER clockTime]],	CONTRACT_KEY_DEPARTURE_TIME,
		[NSNumber numberWithDouble:eta],				CONTRACT_KEY_ARRIVAL_TIME,
		[NSNumber numberWithDouble:fee],				CONTRACT_KEY_FEE,
		[NSNumber numberWithDouble:premium],						CONTRACT_KEY_PREMIUM,
		NULL];
	
	// check available space
	
	OOCargoQuantity		cargoSpaceRequired = qty;
	OOMassUnit			contractCargoUnits	= [UNIVERSE unitsForCommodity:type];
	
	if (contractCargoUnits == UNITS_KILOGRAMS)  cargoSpaceRequired /= 1000;
	if (contractCargoUnits == UNITS_GRAMS)  cargoSpaceRequired /= 1000000;
	
	if (cargoSpaceRequired > [self availableCargoSpace]) return NO;
	
	NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
	NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:type]];
	qty += [manifest_commodity oo_intAtIndex:MARKET_QUANTITY];
	[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:qty]];
	[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];

	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];

	current_cargo = [self cargoQuantityOnBoard];

	if ([UNIVERSE legalStatusOfCommodity:[manifest_commodity objectAtIndex:MARKET_NAME]] > 0)
	{
		[self addRoleToPlayer:@"trader-smuggler"];
		[roleWeightFlags setObject:[NSNumber numberWithInt:1] forKey:@"bought-illegal"];
	}
	else
	{
		[self addRoleToPlayer:@"trader"];
		[roleWeightFlags setObject:[NSNumber numberWithInt:1] forKey:@"bought-legal"];
	}

	[contracts addObject:cargo_info];
	[contract_record setObject:[NSNumber numberWithDouble:eta] forKey:cargo_ID];

	return YES;
}


- (BOOL) removeContract:(NSString*)commodity destination:(unsigned)dest	// removes the first match found, returns NO if none found
{
	if ([contracts count] == 0 || dest > 255)  return NO;

	OOCommodityType	findType = [UNIVERSE commodityForName: commodity];

	if (findType == COMMODITY_UNDEFINED)  return NO;
	
	unsigned			i;
	
	for (i = 0; i < [contracts count]; i++)
	{
		NSDictionary		*contractInfo = [contracts oo_dictionaryAtIndex:i];
		unsigned 			cargoDest = [contractInfo oo_intForKey:CONTRACT_KEY_DESTINATION];
		OOCommodityType		cargoType = [contractInfo oo_intForKey:CARGO_KEY_TYPE];
		
		if (cargoType == findType && cargoDest == dest)
		{
			[contract_record removeObjectForKey:[contractInfo oo_stringForKey:CARGO_KEY_ID]];
			[contracts removeObjectAtIndex:i];
			return YES;
		}
	}
	
	return NO;
}

/*
- (BOOL) pickFromGuiContractsScreen
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	
	NSMutableArray* passenger_market = [[UNIVERSE station] localPassengers];
	NSMutableArray* contract_market = [[UNIVERSE station] localContracts];
	
	if (([gui selectedRow] >= GUI_ROW_PASSENGERS_START)&&([gui selectedRow] < GUI_ROW_CARGO_START))
	{
		NSDictionary* passenger_info = (NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START];
		NSString* passenger_name = [passenger_info oo_stringForKey:PASSENGER_KEY_NAME];
		NSNumber* passenger_arrival_time = (NSNumber*)[passenger_info objectForKey:CONTRACT_KEY_ARRIVAL_TIME];
		int passenger_premium = [passenger_info oo_intForKey:CONTRACT_KEY_PREMIUM];
		if ([passengers count] >= max_passengers)
			return NO;
		[passengers addObject:passenger_info];
		[passenger_record setObject:passenger_arrival_time forKey:passenger_name];
		[passenger_market removeObject:passenger_info];
		credits += 10 * passenger_premium;
		
		if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
		
		return YES;
	}
	
	if (([gui selectedRow] >= GUI_ROW_CARGO_START)&&([gui selectedRow] < GUI_ROW_MARKET_CASH))
	{
		NSDictionary		*contractInfo = nil;
		NSString			*contractID = nil;
		NSNumber			*contractArrivalTime = nil;
		OOCreditsQuantity	contractPremium;
		OOCargoQuantity		contractAmount;
		OOCommodityType		contractCommodityType;
		OOMassUnit			contractCargoUnits;
		OOCargoQuantity		cargoSpaceRequired;
		
		contractInfo			= [contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START];
		contractID				= [contractInfo oo_stringForKey:CARGO_KEY_ID];
		contractArrivalTime		= [contractInfo oo_objectOfClass:[NSNumber class] forKey:CONTRACT_KEY_ARRIVAL_TIME];
		contractPremium			= [contractInfo oo_intForKey:CONTRACT_KEY_PREMIUM];
		contractAmount			= [contractInfo oo_intForKey:CARGO_KEY_AMOUNT];
		contractCommodityType	= [contractInfo oo_intForKey:CARGO_KEY_TYPE];
		contractCargoUnits		= [UNIVERSE unitsForCommodity:contractCommodityType];
		
		cargoSpaceRequired = contractAmount;
		if (contractCargoUnits == UNITS_KILOGRAMS)  cargoSpaceRequired /= 1000;
		if (contractCargoUnits == UNITS_GRAMS)  cargoSpaceRequired /= 1000000;
		
		// tests for refusal...
		if (cargoSpaceRequired > [self availableCargoSpace])	// no room for cargo
		{
			return NO;
		}
			
		if (contractPremium * 10 > credits)					// can't afford contract
		{
			return NO;
		}
			
		// okay passed all tests ...
		
		// pay the premium
		credits -= 10 * contractPremium;
		// add commodity to what's being carried
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:[manifest objectAtIndex:contractCommodityType]];
		int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
		manifest_quantity += contractAmount;
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[manifest replaceObjectAtIndex:contractCommodityType withObject:[NSArray arrayWithArray:manifest_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
		current_cargo = [self cargoQuantityOnBoard];
		
		[contracts addObject:contractInfo];
		[contract_record setObject:contractArrivalTime forKey:contractID];
		[contract_market removeObject:contractInfo];
		
		if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
		
		return YES;
	}
	return NO;
}
*/

 /*
- (void) highlightSystemFromGuiContractsScreen
{
	GuiDisplayGen	*gui = [UNIVERSE gui];

	NSArray			*passenger_market = [[UNIVERSE station] localPassengers];
	NSArray			*contract_market = [[UNIVERSE station] localContracts];

	NSDictionary	*contract_info = nil;
	NSString 		*dest_name = nil;
	
	if (([gui selectedRow] < GUI_ROW_CARGO_START) && ([gui selectedRow] >= GUI_ROW_PASSENGERS_START))
	{
		contract_info = (NSDictionary*)[passenger_market objectAtIndex:[gui selectedRow] - GUI_ROW_PASSENGERS_START];
	}
	else if (([gui selectedRow] >= GUI_ROW_CARGO_START) && ([gui selectedRow] < GUI_ROW_MARKET_CASH))
	{
		contract_info = (NSDictionary*)[contract_market objectAtIndex:[gui selectedRow] - GUI_ROW_CARGO_START];
	}
	dest_name = [contract_info oo_stringForKey:CONTRACT_KEY_DESTINATION_NAME];
	
	[self setGuiToLongRangeChartScreen];
	[UNIVERSE findSystemCoordinatesWithPrefix:[dest_name lowercaseString] exactMatch:YES]; // if dest_name is 'Ra', make sure there's only 1 result.
	[self targetNewSystem:1]; // now highlight the 1 result found.
} */


- (NSArray*) passengerList
{
	return [self contractsListFromArray:passengers forCargo:NO forParcels:NO];
}


- (NSArray*) parcelList
{
	return [self contractsListFromArray:parcels forCargo:NO forParcels:YES];
}


- (NSArray*) contractList
{
	return [self contractsListFromArray:contracts forCargo:YES forParcels:NO];
}


- (NSArray*) contractsListFromArray:(NSArray *) contracts_array forCargo:(BOOL) forCargo forParcels:(BOOL)forParcels
{
	// check  contracts
	NSMutableArray	*result = [NSMutableArray arrayWithCapacity:5];
	NSString		*formatString = (forCargo||forParcels) ? DESC(@"manifest-deliver-@-to-@within-@")
											: DESC(@"manifest-@-travelling-to-@-to-arrive-within-@");
	unsigned i;
	for (i = 0; i < [contracts_array count]; i++)
	{
		NSDictionary* contract_info = (NSDictionary *)[contracts_array objectAtIndex:i];
		NSString* label = [contract_info oo_stringForKey:forCargo ? CARGO_KEY_DESCRIPTION : PASSENGER_KEY_NAME];
		// the system name can change via script. The following PASSENGER_KEYs are identical to the corresponding CONTRACT_KEYs
		NSString* dest_name = [UNIVERSE getSystemName: [UNIVERSE systemSeedForSystemNumber:[contract_info oo_intForKey:CONTRACT_KEY_DESTINATION]]];
		int dest_eta = [contract_info oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		[result addObject:[NSString stringWithFormat:formatString, label, dest_name, [UNIVERSE shortTimeDescription:dest_eta]]];
	}
	
	return result;
}


- (void) setGuiToManifestScreen
{
	OOGUIScreenID	oldScreen = gui_screen;
	
	GuiDisplayGen	*gui = [UNIVERSE gui];
	gui_screen = GUI_SCREEN_MANIFEST;
	BOOL			guiChanged = (oldScreen != gui_screen);
	if (guiChanged)
	{
		[gui setStatusPage:0]; // need to do this earlier than the rest
	}
	
	// GUI stuff
	{
		NSArray*	cargoManifest = [self cargoList];
		NSArray*	missionsManifest = [self missionsList];
		NSArray*	passengerManifest = [self passengerList];
		NSArray*	contractManifest = [self contractList];
		NSArray*	parcelManifest = [self parcelList];
		
		NSUInteger	i = 0;
		NSUInteger	max_rows = 20;
		NSUInteger	manifestCount = [cargoManifest count];
		NSUInteger	cargoRowCount = (manifestCount + 1)/2;
		OOGUIRow	cargoRow = 2;
		OOGUIRow	passengersRow = 2;
		OOGUIRow	contractsRow = 2;
		OOGUIRow	parcelsRow = 2;
		OOGUIRow	missionsRow = 2;
		
		// show extra lines if no HUD is displayed.
		if ([[self hud] isHidden]) max_rows += 7;
		
		NSInteger page_offset = 0;
		BOOL multi_page = NO;
		NSUInteger total_rows = cargoRowCount + [passengerManifest count] + [contractManifest count] + [missionsManifest count] + [parcelManifest count] + 5;
		if (total_rows > max_rows)
		{
			max_rows -= 2;
			page_offset = ([gui statusPage]-1) * max_rows;
			if (page_offset < 0 || (NSUInteger)page_offset >= total_rows)
			{
				[gui setStatusPage:0];
				page_offset = 0;
			}
			multi_page = YES;
		}


		OOGUITabSettings tab_stops;
		tab_stops[0] = 20;
		tab_stops[1] = 256;
		[gui setTabStops:tab_stops];
		
		// Cargo Manifest
		current_cargo = [self cargoQuantityOnBoard];

		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:DESC(@"manifest-title")];
		
		SET_MANIFEST_ROW( ([NSString stringWithFormat:DESC(@"manifest-cargo-d-d"), current_cargo, [self maxAvailableCargoSpace]]) , yellowColor, cargoRow - 1);
		
		if (manifestCount > 0)
		{
			for (i = 0; i < cargoRowCount; i++)
			{
				NSMutableArray*		row_info = [NSMutableArray arrayWithCapacity:2];
				// i is always smaller than manifest_count, no need to test.
				[row_info addObject:[cargoManifest objectAtIndex:i]];
				if (i + cargoRowCount < manifestCount)
					[row_info addObject:[cargoManifest objectAtIndex:i + cargoRowCount]];
				else
					[row_info addObject:@""];
				SET_MANIFEST_ROW( (NSArray *)row_info, greenColor, cargoRow + i);
			}
		}
		else
		{
			SET_MANIFEST_ROW( (DESC(@"manifest-none")), greenColor, cargoRow);
			cargoRowCount=1;
		}
		
		passengersRow = cargoRow + cargoRowCount + 1;
		
		// Passengers Manifest
		manifestCount = [passengerManifest count];
		
		SET_MANIFEST_ROW( ([NSString stringWithFormat:DESC(@"manifest-passengers-d-d"), manifestCount, max_passengers]) , yellowColor, passengersRow - 1);

		if (manifestCount > 0)
		{
			for (i = 0; i < manifestCount; i++)
			{
				SET_MANIFEST_ROW( ((NSString*)[passengerManifest objectAtIndex:i]) , greenColor, passengersRow + i);
			}
		}
		else
		{
			SET_MANIFEST_ROW( (DESC(@"manifest-none")), greenColor, passengersRow);
			manifestCount = 1;
		}

		parcelsRow = passengersRow + manifestCount + 1;

		// Parcels Manifest
		manifestCount = [parcelManifest count];
		
		SET_MANIFEST_ROW( (DESC(@"manifest-parcels")) , yellowColor, parcelsRow - 1);

		if (manifestCount > 0)
		{
			for (i = 0; i < manifestCount; i++)
			{
				SET_MANIFEST_ROW( ((NSString*)[parcelManifest objectAtIndex:i]) , greenColor, parcelsRow + i);
			}
		}
		else
		{
			SET_MANIFEST_ROW( (DESC(@"manifest-none")), greenColor, parcelsRow);
			manifestCount = 1;
		}


		contractsRow = parcelsRow + manifestCount + 1;
		
		// Contracts Manifest
		manifestCount = [contractManifest count];
		SET_MANIFEST_ROW( (DESC(@"manifest-contracts")) , yellowColor, contractsRow - 1);
			
		if (manifestCount > 0)
		{
			for (i = 0; i < manifestCount; i++)
			{
				SET_MANIFEST_ROW( ((NSString*)[contractManifest objectAtIndex:i]) , greenColor, contractsRow + i);
			}
		}
		else
		{
			SET_MANIFEST_ROW( (DESC(@"manifest-none")), greenColor, contractsRow);
			manifestCount = 1;
		}

		missionsRow = contractsRow + manifestCount + 1;
		
		// Missions Manifest
		manifestCount = [missionsManifest count];
		
		if (manifestCount > 0)
		{
			SET_MANIFEST_ROW( (DESC(@"manifest-missions")) , yellowColor, missionsRow - 1);
			
			for (i = 0; i < manifestCount; i++)
			{
				SET_MANIFEST_ROW( ((NSString*)[missionsManifest objectAtIndex:i]) , greenColor, missionsRow + i);
			}
		}
		
/*		if (missions_row + manifest_count >= max_rows )
		{
			[gui setText:@" . . ."				forRow:max_rows];
			[gui setColor:[OOColor greenColor]	forRow:max_rows];
			} */
		if (multi_page)
		{
			OOGUIRow r_start = MANIFEST_SCREEN_ROW_BACK;
			OOGUIRow r_end = MANIFEST_SCREEN_ROW_NEXT;
			if (page_offset > 0)
			{
				[gui setColor:[OOColor greenColor] forRow:MANIFEST_SCREEN_ROW_BACK];
				[gui setKey:GUI_KEY_OK forRow:MANIFEST_SCREEN_ROW_BACK];
			}
			else
			{
				[gui setColor:[OOColor darkGrayColor] forRow:MANIFEST_SCREEN_ROW_BACK];
				r_start = MANIFEST_SCREEN_ROW_NEXT;
			}
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ",nil] forRow:MANIFEST_SCREEN_ROW_BACK];

			if (total_rows > max_rows + page_offset)
			{
				[gui setColor:[OOColor greenColor] forRow:MANIFEST_SCREEN_ROW_NEXT];
				[gui setKey:GUI_KEY_OK forRow:MANIFEST_SCREEN_ROW_NEXT];
			}
			else
			{
				[gui setColor:[OOColor darkGrayColor] forRow:MANIFEST_SCREEN_ROW_NEXT];
				r_end = MANIFEST_SCREEN_ROW_BACK;
			}
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ",nil] forRow:MANIFEST_SCREEN_ROW_NEXT];

			[gui setSelectableRange:NSMakeRange(r_start,r_end+1-r_start)];
			[gui setSelectedRow:r_start];

		}

		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	
	if (guiChanged)
	{
		[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
		[gui setBackgroundTextureKey:@"manifest"];
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	}
}


- (void) setManifestScreenRow:(id)object inColor:(OOColor*)color forRow:(OOGUIRow)row ofRows:(OOGUIRow)max_rows andOffset:(OOGUIRow)offset inMultipage:(BOOL)multi
{
	OOGUIRow disp_row = row - offset;
	if (disp_row < 1 || disp_row > max_rows) return;
	if (multi) disp_row++;
	GuiDisplayGen	*gui = [UNIVERSE gui];
	if ([object isKindOfClass:[NSString class]])
	{
		[gui setText:(NSString*)object forRow:disp_row];
	}
	else if ([object isKindOfClass:[NSArray class]])
	{
		[gui setArray:(NSArray*)object forRow:disp_row];
	}
	[gui setColor:color forRow:disp_row];
}


- (void) setGuiToDockingReportScreen
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	
	OOGUIScreenID	oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_REPORT;
	BOOL			guiChanged = (oldScreen != gui_screen);	
	
	OOGUIRow		text_row = 1;
	
	[dockingReport setString:[dockingReport stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
	
	// GUI stuff
	{
		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:OOExpandKey(@"arrival-report-title")];
		
		// dockingReport might be a multi-line message
		
		while (([dockingReport length] > 0)&&(text_row < 18))
		{
			if ([dockingReport rangeOfString:@"\n"].location != NSNotFound)
			{
				while (([dockingReport rangeOfString:@"\n"].location != NSNotFound)&&(text_row < 18))
				{
					NSUInteger line_break = [dockingReport rangeOfString:@"\n"].location;
					NSString* line = [dockingReport substringToIndex:line_break];
					[dockingReport deleteCharactersInRange: NSMakeRange( 0, line_break + 1)];
					text_row = [gui addLongText:line startingAtRow:text_row align:GUI_ALIGN_LEFT];
				}
				[dockingReport setString:[dockingReport stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
			}
			else
			{
				text_row = [gui addLongText:[NSString stringWithString:dockingReport] startingAtRow:text_row align:GUI_ALIGN_LEFT];
				[dockingReport setString:@""];
			}
		}
		
		[gui setText:[NSString stringWithFormat:DESC_PLURAL(@"contracts-cash-@-load-d-of-d-passengers-d-of-d-berths", max_passengers), OOCredits(credits), current_cargo, [self maxAvailableCargoSpace], [passengers count], max_passengers]  forRow: GUI_ROW_MARKET_CASH];
		
		[gui setText:DESC(@"press-space-commander") forRow:21 align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor yellowColor] forRow:21];
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	if (lastTextKey)
	{
		[lastTextKey release];
		lastTextKey = nil;
	}
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	
	if (guiChanged)
	{
		[gui setForegroundTextureKey:@"docked_overlay"];	// has to be docked!
		
		NSDictionary *bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"report"];
		if (bgDescriptor == nil) bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"status_docked"];
		if (bgDescriptor == nil) bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"status"];
		[gui setBackgroundTextureDescriptor:bgDescriptor];
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	}
}

// ---------------------------------------------------------------------- 

static NSMutableDictionary *currentShipyard = nil;

- (void) setGuiToShipyardScreen:(NSUInteger)skip
{
	OOGUIScreenID	oldScreen = gui_screen;
	
	GuiDisplayGen	*gui = [UNIVERSE gui];
	gui_screen = GUI_SCREEN_SHIPYARD;
	BOOL			guiChanged = (oldScreen != gui_screen);	
	
	unsigned		i;
	
	// set up initial market if there is none
	OOTechLevelID stationTechLevel;
	StationEntity *station = [self dockedStation];
	
	if (station != nil)
	{
		stationTechLevel = [station equivalentTechLevel];
	}
	else
	{
		station  = [UNIVERSE station];
		stationTechLevel = NSNotFound;
	}
	if ([station localShipyard] == nil)
	{
		[station setLocalShipyard:[UNIVERSE shipsForSaleForSystem:system_seed withTL:stationTechLevel atTime:ship_clock]];
	}
		
	NSMutableArray *shipyard = [station localShipyard];
		
	// remove ships that the player has already bought
	for (i = 0; i < [shipyard count]; i++)
	{
		NSString *shipID = [[shipyard oo_dictionaryAtIndex:i] oo_stringForKey:SHIPYARD_KEY_ID];
		if ([shipyard_record objectForKey:shipID])
		{
			[shipyard removeObjectAtIndex:i--];
		}
	}
	
	[currentShipyard release];
	currentShipyard = [[NSMutableDictionary alloc] initWithCapacity:[shipyard count]];

	for (i = 0; i < [shipyard count]; i++)
	{
		[currentShipyard setObject:[shipyard objectAtIndex:i]
							forKey:[[shipyard oo_dictionaryAtIndex:i] oo_stringForKey:SHIPYARD_KEY_ID]];
	}
	
	NSUInteger shipCount = [shipyard count];

	//error check
	if (skip >= shipCount)  skip = shipCount - 1;
	if (skip < 2)  skip = 0;
	
	// GUI stuff
	{
		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:[NSString stringWithFormat:DESC(@"@-shipyard-title"),[UNIVERSE getSystemName:system_seed]]];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -258;
		tab_stops[2] = 270;
		tab_stops[3] = 370;
		tab_stops[4] = 450;
		[gui setTabStops:tab_stops];
		
		int rowCount = MAX_ROWS_SHIPS_FOR_SALE;
		int startRow = GUI_ROW_SHIPYARD_START;
		NSInteger previous = 0;
		
		if (shipCount <= MAX_ROWS_SHIPS_FOR_SALE)
			skip = 0;
		else
		{
			if (skip > 0)
			{
				rowCount -= 1;
				startRow += 1;
				previous = skip - MAX_ROWS_SHIPS_FOR_SALE + 2;
				if (previous < 2)
					previous = 0;
			}
			if (skip + rowCount < shipCount)
				rowCount -= 1;
		}
		
		if (shipCount > 0)
		{
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_SHIPYARD_LABELS];
			[gui setArray:[NSArray arrayWithObjects:DESC(@"shipyard-shiptype"), DESC(@"shipyard-price"),
					DESC(@"shipyard-cargo"), DESC(@"shipyard-speed"), nil] forRow:GUI_ROW_SHIPYARD_LABELS];

			if (skip > 0)
			{
				[gui setColor:[OOColor greenColor] forRow:GUI_ROW_SHIPYARD_START];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:GUI_ROW_SHIPYARD_START];
				[gui setKey:[NSString stringWithFormat:@"More:%ld", previous] forRow:GUI_ROW_SHIPYARD_START];
			}
			for (i = 0; i < (shipCount - skip) && (int)i < rowCount; i++)
			{
				NSDictionary* ship_info = [shipyard oo_dictionaryAtIndex:i + skip];
				OOCreditsQuantity ship_price = [ship_info oo_unsignedLongLongForKey:SHIPYARD_KEY_PRICE];
				[gui setColor:[OOColor yellowColor] forRow:startRow + i];
				[gui setArray:[NSArray arrayWithObjects:
						[NSString stringWithFormat:@" %@ ",[[ship_info oo_dictionaryForKey:SHIPYARD_KEY_SHIP] oo_stringForKey:@"display_name" defaultValue:[[ship_info oo_dictionaryForKey:SHIPYARD_KEY_SHIP] oo_stringForKey:KEY_NAME]]],
						OOIntCredits(ship_price),
						nil]
					forRow:startRow + i];
				[gui setKey:(NSString*)[ship_info objectForKey:SHIPYARD_KEY_ID] forRow:startRow + i];
			}
			if (i < shipCount - skip)
			{
				[gui setColor:[OOColor greenColor] forRow:startRow + i];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:startRow + i];
				[gui setKey:[NSString stringWithFormat:@"More:%ld", rowCount + skip] forRow:startRow + i];
				i++;
			}

			[gui setSelectableRange:NSMakeRange( GUI_ROW_SHIPYARD_START, i + startRow - GUI_ROW_SHIPYARD_START)];
			[self showShipyardInfoForSelection];
		}
		else
		{
			[gui setText:DESC(@"shipyard-no-ships-available-for-purchase") forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_NO_SHIPS];
			
			[gui setNoSelectedRow];
		}
		
		[self showTradeInInformationFooter];
		
		[gui setShowTextCursor:NO];
	}
	
	// the following are necessary...

	[self setShowDemoShips:(shipCount > 0)];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
	
	if (guiChanged)
	{
		[gui setForegroundTextureKey:@"docked_overlay"];
		[gui setBackgroundTextureKey:@"shipyard"];
	}
}


- (void) showShipyardInfoForSelection
{
	NSUInteger		i;
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIRow		sel_row = [gui selectedRow];
	
	if (sel_row <= 0)  return;
	
	NSMutableArray *row_info = [NSMutableArray arrayWithArray:(NSArray*)[gui objectForRow:GUI_ROW_SHIPYARD_LABELS]];
	while ([row_info count] < 4)
	{
		[row_info addObject:@""];
	}
	
	NSString *key = [gui keyForRow:sel_row];
	
	NSDictionary *info = [currentShipyard oo_dictionaryForKey:key];

	// clean up the display ready for the newly-selected ship (if there is one)
	[row_info replaceObjectAtIndex:2 withObject:@""];
	[row_info replaceObjectAtIndex:3 withObject:@""];
	for (i = GUI_ROW_SHIPYARD_INFO_START; i < GUI_ROW_MARKET_CASH - 1; i++)
	{
		[gui setText:@"" forRow:i];
		[gui setColor:[OOColor greenColor] forRow:i];
	}
	[UNIVERSE removeDemoShips];

	if (info)
	{
		// the key is a particular ship - show the details
		NSString *salesPitch = [info oo_stringForKey:KEY_SHORT_DESCRIPTION];
		NSDictionary *shipDict = [info oo_dictionaryForKey:SHIPYARD_KEY_SHIP];
		
		int cargo_rating = [shipDict oo_intForKey:@"max_cargo"];
		int cargo_extra;
		cargo_extra = [shipDict oo_intForKey:@"extra_cargo" defaultValue:15];
		float speed_rating = 0.001 * [shipDict oo_intForKey:@"max_flight_speed"];
		
		NSArray *shipExtras = [info oo_arrayForKey:KEY_EQUIPMENT_EXTRAS];
		for (i = 0; i < [shipExtras count]; i++)
		{
			if ([[shipExtras oo_stringAtIndex:i] isEqualToString:@"EQ_CARGO_BAY"])
			{
				cargo_rating += cargo_extra;
			}
			else if ([[shipExtras oo_stringAtIndex:i] isEqualToString:@"EQ_PASSENGER_BERTH"])
			{
				cargo_rating -= PASSENGER_BERTH_SPACE;
			}
		}
		
		[row_info replaceObjectAtIndex:2 withObject:[NSString stringWithFormat:DESC(@"shipyard-cargo-d-tc"), cargo_rating]];
		[row_info replaceObjectAtIndex:3 withObject:[NSString stringWithFormat:DESC(@"shipyard-speed-f-ls"), speed_rating]];
		
		// Show footer first. It'll be overwritten by the sales_pitch if that text is longer than usual.
		[self showTradeInInformationFooter];
		i = [gui addLongText:salesPitch startingAtRow:GUI_ROW_SHIPYARD_INFO_START align:GUI_ALIGN_LEFT];
		if (i - 1 >= GUI_ROW_MARKET_CASH - 1)
		{
			[gui setColor:[OOColor greenColor] forRow:i - 1];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_MARKET_CASH - 1];
		}
		
		// now display the ship
		[self showShipyardModel:[info oo_stringForKey:SHIPYARD_KEY_SHIPDATA_KEY]
					   shipData:shipDict
					personality:[info oo_unsignedShortForKey:SHIPYARD_KEY_PERSONALITY]];
	}
	else
	{
		// the key is a particular model of ship which we must expand...
		// build an array from the entries for that model in the currentShipyard TODO
		// 
	}

	[gui setArray:[NSArray arrayWithArray:row_info] forRow:GUI_ROW_SHIPYARD_LABELS];
}


- (void) showTradeInInformationFooter
{
	GuiDisplayGen *gui = [UNIVERSE gui];
	OOCreditsQuantity tradeIn = [self tradeInValue];
	[gui setColor:[OOColor yellowColor] forRow:GUI_ROW_MARKET_CASH - 1];
	[gui setColor:[OOColor yellowColor] forRow:GUI_ROW_MARKET_CASH];
	[gui setText:[NSString stringWithFormat:DESC(@"shipyard-your-@-trade-in-value-@"), [self displayName], OOIntCredits(tradeIn/10)]  forRow: GUI_ROW_MARKET_CASH - 1];
	[gui setText:[NSString stringWithFormat:DESC(@"shipyard-total-available-%@-%@-plus-%@-trade"), OOCredits(credits + tradeIn), OOCredits(credits), OOIntCredits(tradeIn/10)]  forRow: GUI_ROW_MARKET_CASH];
}


- (void) showShipyardModel:(NSString *)shipKey shipData:(NSDictionary *)shipData personality:(uint16_t)personality
{
	if (shipKey == nil || [self dockedStation] == nil)  return;
	[self showShipModelWithKey:shipKey shipData:shipData personality:personality factorX:1.2 factorY:0.8 factorZ:6.4 inContext:@"shipyard"];
}


- (NSInteger) missingSubEntitiesAdjustment
{
	// each missing subentity depreciates the ship by 5%, up to a maximum of 35% depreciation.
	NSUInteger percent = 5 * ([self maxShipSubEntities] - [[[self shipSubEntityEnumerator] allObjects] count]);
	return (percent > 35 ? 35 : percent);
}


- (OOCreditsQuantity) tradeInValue
{
	// returns down to ship_trade_in_factor% of the full credit value of your ship
	
	/*	FIXME: the trade-in value can be more than the sale value, and
		ship_trade_in_factor starts at 100%, so it can be profitable to sit
		and buy the same ship over and over again. This bug predates Oolite
		1.65.
		Partial fix: make effective trade-in value 75% * ship_trade_in_factor%
		of the "raw" trade-in value. This still allows profitability! A better
		solution would be to unify the price calculation for trade-in and
		for-sale ships.
		-- Ahruman 20070707, fix applied 20070708
	*/
	unsigned long long value = [UNIVERSE tradeInValueForCommanderDictionary:[self commanderDataDictionary]];
	value -= value * 0.006 * [self missingSubEntitiesAdjustment];	// TODO: 0.006 might need rethinking.
	value = cunningFee(((value * 75 * ship_trade_in_factor) + 5000) / 10000, 0.005);	// Multiply by two percentages, divide by 100*100. The +5000 is to get normal rounding.
	return value * 10;
}


- (BOOL) buySelectedShip
{

	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIRow		selectedRow = [gui selectedRow];
	
	if (selectedRow <= 0)  return NO;
	
	NSString *key = [gui keyForRow:selectedRow];

	if ([key hasPrefix:@"More:"])
	{
		NSInteger fromShip = [[key componentsSeparatedByString:@":"] oo_integerAtIndex:1];
		if (fromShip < 0)  fromShip = 0;
		
		[self setGuiToShipyardScreen:fromShip];
		if ([[UNIVERSE gui] selectedRow] < 0)
		{
			[[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
		}
		if (fromShip == 0)
		{
			[[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
		}
		return YES;
	}

	// first check you can afford it!
	NSDictionary *shipInfo = [currentShipyard oo_dictionaryForKey:key];
	OOCreditsQuantity price = [shipInfo oo_unsignedLongLongForKey:SHIPYARD_KEY_PRICE];
	OOCreditsQuantity tradeIn = [self tradeInValue];


	if (credits + tradeIn < price * 10)
		return NO;	// you can't afford it!
	
	// sell all the commodities carried
	NSUInteger i;
	for (i = 0; i < [shipCommodityData count]; i++)
	{
		[self trySellingCommodity:i all:YES];
	}
	// We tried to sell everything. If there are still items present in our inventory, it
	// means that the market got saturated (quantity in station > 127 t) before we could sell
	// it all. Everything that could not be sold will be lost. -- Nikos 20083012

	// pay over the mazoolah
	credits -= 10 * price - tradeIn;
	
	NSDictionary *shipDict = [shipInfo oo_dictionaryForKey:SHIPYARD_KEY_SHIP];
	[self newShipCommonSetup:[shipInfo oo_stringForKey:SHIPYARD_KEY_SHIPDATA_KEY] yardInfo:shipInfo baseInfo:shipDict];

	// this ship has a clean record
	legalStatus = 0;

	NSArray* extras = [shipInfo oo_arrayForKey:KEY_EQUIPMENT_EXTRAS];
	for (i = 0; i < [extras count]; i++)
	{
		NSString* eq_key = [extras oo_stringAtIndex:i];
		if ([eq_key isEqualToString:@"EQ_PASSENGER_BERTH"])
		{
			max_passengers++;
			max_cargo -= PASSENGER_BERTH_SPACE;
		}
		else
		{
			[self addEquipmentItem:eq_key withValidation:YES inContext:@"newShip"]; 
		}
	}

	// add bought ship to shipyard_record
	[shipyard_record setObject:[self shipDataKey] forKey:[shipInfo objectForKey:SHIPYARD_KEY_ID]];
	
	// remove the ship from the localShipyard
	[[[self dockedStation] localShipyard] removeObjectAtIndex:selectedRow - GUI_ROW_SHIPYARD_START];
	
	// perform the transformation
	NSDictionary* cmdr_dict = [self commanderDataDictionary];	// gather up all the info
	if (![self setCommanderDataFromDictionary:cmdr_dict])  return NO;

	[self setStatus:STATUS_DOCKED];
	[self setEntityPersonalityInt:[shipInfo oo_unsignedShortForKey:SHIPYARD_KEY_PERSONALITY]];
	
	// adjust the clock forward by an hour
	ship_clock_adjust += 3600.0;
	
	// finally we can get full hock if we sell it back
	ship_trade_in_factor = 100;
	
	if ([UNIVERSE autoSave])  [UNIVERSE setAutoSaveNow:YES];
	
	return YES;
}

- (BOOL) buyNamedShip:(NSString *)shipKey
{

	NSDictionary *ship_info = [[OOShipRegistry sharedRegistry] shipyardInfoForKey:shipKey];
	
	NSDictionary *ship_base_dict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];

	if (ship_info == nil || ship_base_dict == nil) {
		return NO;
	}
	
	[self newShipCommonSetup:shipKey yardInfo:ship_info baseInfo:ship_base_dict];

	// perform the transformation
	NSDictionary* cmdr_dict = [self commanderDataDictionary];	// gather up all the info
	if (![self setCommanderDataFromDictionary:cmdr_dict])  return NO;

	// refill from ship_info
	NSArray* extras = [NSMutableArray arrayWithArray:[[ship_info oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_arrayForKey:KEY_EQUIPMENT_EXTRAS]];
	for (unsigned i = 0; i < [extras count]; i++)
	{
		NSString* eq_key = [extras oo_stringAtIndex:i];
		if ([eq_key isEqualToString:@"EQ_PASSENGER_BERTH"])
		{
			max_passengers++;
			max_cargo -= PASSENGER_BERTH_SPACE;
		}
		else
		{
			[self addEquipmentItem:eq_key withValidation:YES inContext:@"newShip"]; 
		}
	}

	[self setEntityPersonalityInt:[ship_info oo_unsignedShortForKey:SHIPYARD_KEY_PERSONALITY]];
	
	return YES;
}

- (void) newShipCommonSetup:(NSString *)shipKey yardInfo:(NSDictionary *)ship_info baseInfo:(NSDictionary *)ship_base_dict 
{

	unsigned i;
	if (current_cargo)
	{
		// Zero out our manifest.
		NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
		for (i = 0; i < [manifest count]; i++)
		{
			NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:i]];
			[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
			[manifest replaceObjectAtIndex:i withObject:manifest_commodity];
		}
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
		current_cargo = 0;
	}
	
	// drop all passengers
	[passengers removeAllObjects];
	[passenger_record removeAllObjects]; 
		
	// parcels stay the same; easy to transfer between ships
	// contracts stay the same, so if you default - tough!
	// okay we need to switch the model used, lots of the stats, and add all the extras
	
	[self clearSubEntities];

	[self setShipDataKey:shipKey];

	NSDictionary *shipDict = ship_base_dict;


	// get a full tank for free
	[self setFuel:[self fuelCapacity]];
	
	// get forward_weapon aft_weapon port_weapon starboard_weapon from ship_info
	int base_facings = [shipDict oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:15];
	int available_facings = [ship_info oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:base_facings];

	if (available_facings & WEAPON_FACING_AFT)
		aft_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy([shipDict oo_stringForKey:@"aft_weapon_type"]);
	else
		aft_weapon_type = WEAPON_NONE;

	if (available_facings & WEAPON_FACING_PORT)
		port_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy([shipDict oo_stringForKey:@"port_weapon_type"]);
	else
		port_weapon_type = WEAPON_NONE;

	if (available_facings & WEAPON_FACING_STARBOARD)
		starboard_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy([shipDict oo_stringForKey:@"starboard_weapon_type"]);
	else
		starboard_weapon_type = WEAPON_NONE;

	if (available_facings & WEAPON_FACING_FORWARD)
		forward_weapon_type = OOWeaponTypeFromEquipmentIdentifierSloppy([shipDict oo_stringForKey:@"forward_weapon_type"]);
	else
		forward_weapon_type = WEAPON_NONE;
	
	// new ships start with weapons online
	weapons_online = 1;

	// get basic max_cargo
	max_cargo = [UNIVERSE maxCargoForShip:[self shipDataKey]];

	// ensure all missiles are tidied up and start at pylon 0
	[self tidyMissilePylons];

	// get missiles from ship_info
	missiles = [shipDict oo_unsignedIntForKey:@"missiles"];
	
	// reset max_passengers
	max_passengers = 0;
	
	// reset and refill extra_equipment then set flags from it
	
	// keep track of portable equipment..

	NSMutableSet	*portable_equipment = [NSMutableSet set];
	NSEnumerator	*eqEnum = nil;
	NSString		*eq_desc = nil;
	OOEquipmentType	*item = nil;
	
	for (eqEnum = [self equipmentEnumerator]; (eq_desc = [eqEnum nextObject]);)
	{
		item = [OOEquipmentType equipmentTypeWithIdentifier:eq_desc];
		if ([item isPortableBetweenShips])  [portable_equipment addObject:eq_desc];
	}
	
	// remove ALL
	[self removeAllEquipment];
	
	// restore  portable equipment
	for (eqEnum = [portable_equipment objectEnumerator]; (eq_desc = [eqEnum nextObject]); )
	{
		[self addEquipmentItem:eq_desc withValidation:NO inContext:@"portable"];
	}


	// set up subentities from scratch; new ship could carry more or fewer than the old one
	[self setUpSubEntities];

	// clear old ship names
	[self setShipClassName:[shipDict oo_stringForKey:@"name"]];
	[self setShipUniqueName:@""];

	// new ship, so lose some memory of actions
	// new ship, so lose some memory of player actions
	if (ship_kills >= 6400)
	{
		[self clearRolesFromPlayer:0.1];
	}
	else if (ship_kills >= 2560)
	{
		[self clearRolesFromPlayer:0.25];
	}
	else
	{
		[self clearRolesFromPlayer:0.5];
	}	

}

@end

static unsigned RepForRisk(unsigned risk)
{
	switch (risk)
	{
	case 0:
		return 1;
	case 1:
		return 2;
	case 2:
	default:
		return 4;
	}
}
