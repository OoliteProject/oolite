/*

PlayerEntityScriptMethods.m

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

#import "PlayerEntityScriptMethods.h"
#import "PlayerEntityLoadSave.h"

#import "Universe.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOStringParsing.h"

#import "OOStringExpander.h"
#import "OOStringParsing.h"

#import "StationEntity.h"

@implementation PlayerEntity (ScriptMethods)

- (unsigned) score
{
	return ship_kills;
}


- (void) setScore:(unsigned)value
{
	ship_kills = value;
}


- (double) creditBalance
{
	return 0.1 * credits;
}


- (void) setCreditBalance:(double)value
{
	credits = OODeciCreditsFromDouble(value * 10.0);
}


- (NSString *) dockedStationName
{
	return [[self dockedStation] name];
}


- (NSString *) dockedStationDisplayName
{
	return [[self dockedStation] displayName];
}


- (BOOL) dockedAtMainStation
{
	return [self status] == STATUS_DOCKED && [self dockedStation] == [UNIVERSE station];
}


- (BOOL) canAwardCommodityType:(OOCommodityType)type amount:(OOCargoQuantity)amount
{
	if (type == CARGO_NOT_CARGO)  return NO;
	if ([UNIVERSE unitsForCommodity:type] == UNITS_TONS)
	{
		if ([self specialCargo] != nil)  return NO;
		if (amount > [self availableCargoSpace])  return NO;
	}
	
	return YES;
}


- (void) awardCommodityType:(OOCommodityType)type amount:(OOCargoQuantity)amount
{
	OOMassUnit				unit;
	NSArray					*commodityArray = nil;
	
	commodityArray = [UNIVERSE commodityDataForType:type];
	if (commodityArray == nil)  return;
	
	OOLog(@"script.debug.note.awardCargo", @"Going to award cargo: %d x '%@'", amount, CommodityDisplayNameForCommodityArray(commodityArray));
	
	unit = [UNIVERSE unitsForCommodity:type];
	
	if ([self status] != STATUS_DOCKED)
	{
		// in-flight
		while (amount)
		{
			if (unit != UNITS_TONS)
			{
				if (specialCargo)
				{
					NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
					NSMutableArray* manifest_commodity =	[NSMutableArray arrayWithArray:(NSArray *)[manifest objectAtIndex:type]];
					int manifest_quantity = [(NSNumber *)[manifest_commodity objectAtIndex:MARKET_QUANTITY] intValue];
					manifest_quantity += amount;
					amount = 0;
					[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
					[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
					[shipCommodityData release];
					shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
				}
				else
				{
					int amount_per_container = (unit == UNITS_KILOGRAMS)? 1000 : 1000000;
					while (amount > 0)
					{
						int smaller_quantity = 1 + ((amount - 1) % amount_per_container);
						if ([cargo count] < [self maxAvailableCargoSpace])
						{
							ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
							if (container)
							{
								// the cargopod ship is just being set up. If ejected,  will call UNIVERSE addEntity
								// [container wasAddedToUniverse]; // seems to be not needed anymore for pods
								[container setScanClass: CLASS_CARGO];
								[container setStatus:STATUS_IN_HOLD];
								[container setCommodity:type andAmount:smaller_quantity];
								[cargo addObject:container];
								[container release];
							}
						}
						amount -= smaller_quantity;
					}
				}
			}
			else
			{
				// put each ton in a separate container
				while (amount)
				{
					if ([cargo count] < [self maxAvailableCargoSpace])
					{
						ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
						if (container)
						{
							// the cargopod ship is just being set up. If ejected, will call UNIVERSE addEntity
							// [container wasAddedToUniverse]; // seems to be not needed anymore for pods
							[container setScanClass: CLASS_CARGO];
							[container setStatus:STATUS_IN_HOLD];
							[container setCommodity:type andAmount:1];
							[cargo addObject:container];
							[container release];
						}
					}
					amount--;
				}
			}
		}
	}
	else
	{	// docked
		// like purchasing a commodity
		NSMutableArray* manifest = [NSMutableArray arrayWithArray:shipCommodityData];
		NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:type]];
		int manifest_quantity = [manifest_commodity oo_intAtIndex:MARKET_QUANTITY];
		while ((amount)&&(current_cargo < [self maxAvailableCargoSpace]))
		{
			manifest_quantity++;
			amount--;
			if (unit == UNITS_TONS)  current_cargo++;
		}
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
		[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	}
	[self calculateCurrentCargo];
}


- (OOGalaxyID) currentGalaxyID
{
	return galaxy_number;
}


- (OOSystemID) currentSystemID
{
	if ([UNIVERSE sun] == nil)  return -1;	// Interstellar space
	return [UNIVERSE currentSystemID];
}


- (void) setMissionChoice:(NSString *)newChoice
{
	[self setMissionChoice:newChoice withEvent:YES];
}


- (void) setMissionChoice:(NSString *)newChoice withEvent:(BOOL)withEvent
{
	BOOL equal = [newChoice isEqualToString:missionChoice] || (newChoice == missionChoice);	// Catch both being nil as well
	if (!equal)
	{
		if (newChoice == nil)
		{
			NSString *oldChoice = missionChoice;
			[missionChoice autorelease];
			missionChoice = nil;
			if (withEvent) [self doScriptEvent:OOJSID("missionChoiceWasReset") withArgument:oldChoice];
		}
		else
		{
			[missionChoice autorelease];
			missionChoice = [newChoice copy];
		}
	}
}


- (void) allowMissionInterrupt
{
	_missionAllowInterrupt = YES;
}


- (OOTimeDelta) scriptTimer
{
	return script_time;
}


- (unsigned) systemPseudoRandom100
{
	seed_RNG_only_for_planet_description(system_seed);
	return (gen_rnd_number() * 256 + gen_rnd_number()) % 100;
}


- (unsigned) systemPseudoRandom256
{
	seed_RNG_only_for_planet_description(system_seed);
	return gen_rnd_number();
}


- (double) systemPseudoRandomFloat
{
	Random_Seed seed = system_seed;
	seed_RNG_only_for_planet_description(system_seed);
	unsigned a = gen_rnd_number();
	unsigned b = gen_rnd_number();
	unsigned c = gen_rnd_number();
	system_seed = seed;
	
	a = (a << 16) | (b << 8) | c;
	return (double)a / (double)0x01000000;
	
}


- (NSDictionary *) passengerContractMarker:(OOSystemID)system
{
	return [[[NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithInt:system], @"system",
								MISSION_DEST_LEGACY, @"name",
								@"orangeColor", @"markerColor",
								@"MARKER_DIAMOND", @"markerShape",
								nil] retain] autorelease];
}


- (NSDictionary *) parcelContractMarker:(OOSystemID)system
{
	return [[[NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithInt:system], @"system",
								MISSION_DEST_LEGACY, @"name",
								@"orangeColor", @"markerColor",
								@"MARKER_PLUS", @"markerShape",
								nil] retain] autorelease];
}


- (NSDictionary *) cargoContractMarker:(OOSystemID)system
{
	return [[[NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithInt:system], @"system",
								MISSION_DEST_LEGACY, @"name",
								@"orangeColor", @"markerColor",
								@"MARKER_SQUARE", @"markerShape",
								nil] retain] autorelease];
}


- (NSDictionary *) defaultMarker:(OOSystemID)system
{
	return [[[NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithInt:system], @"system",
								MISSION_DEST_LEGACY, @"name",
								@"redColor", @"markerColor",
								@"MARKER_X", @"markerShape",
								nil] retain] autorelease];
}


- (NSDictionary *) validatedMarker:(NSDictionary *)marker
{
	OOSystemID dest = [marker oo_intForKey:@"system"];
// FIXME: parameters
	if (dest < 0 || dest > kOOMaximumSystemID)
	{
		return nil;
	}
	NSString *group = [marker oo_stringForKey:@"name" defaultValue:MISSION_DEST_LEGACY];

	return [[[NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithInt:dest], @"system",
								group, @"name",
								[marker oo_stringForKey:@"markerColor" defaultValue:@"redColor"], @"markerColor",
								[marker oo_stringForKey:@"markerShape" defaultValue:@"MARKER_X"], @"markerShape",
							  [NSNumber numberWithFloat:[marker oo_floatForKey:@"markerScale" defaultValue:1.0]], @"markerScale",
								nil] retain] autorelease];

}


// Implements string expansion code [credits_number].
- (NSString *) creditsFormattedForSubstitution
{
	return OOStringFromDeciCredits([self deciCredits], YES, NO);
}


/*	Implements string expansion code [_oo_legacy_credits_number].
	
	Literal uses of [credits_number] in legacy scripts are converted to
	[_oo_legacy_credits_number] in the script sanitizer. These are shown
	unlocalized because legacy scripts may use it for arithmetic.
*/
- (NSString *) creditsFormattedForLegacySubstitution
{
	OOCreditsQuantity	tenthsOfCredits = [self deciCredits];
	unsigned long long	integerCredits = tenthsOfCredits / 10;
	unsigned long long	tenths = tenthsOfCredits % 10;
	
	return [NSString stringWithFormat:@"%llu.%llu", integerCredits, tenths];
}


// Implements string expansion code [commander_bounty].
- (NSString *) commanderBountyAsString
{
	return [NSString stringWithFormat:@"%i", [self legalStatus]];
}


// Implements string expansion code [commander_kills].
- (NSString *) commanderKillsAsString
{
	return [NSString stringWithFormat:@"%i", [self score]];
}


- (NSString *) keyBindingDescription:(NSString *)binding
{
	if ([keyconfig_settings objectForKey:binding] == nil)
	{
		// no such setting
		return nil;
	}
	OOKeyCode key = (OOKeyCode)[keyconfig_settings oo_unsignedCharForKey:binding];
	// 0 = key not set
	return [self keyCodeDescription:key];
}


- (NSString *) keyCodeDescription:(OOKeyCode)code
{
	switch (code)
	{
	case 0:
		return DESC(@"oolite-keycode-unset");
	case 9:
		return DESC(@"oolite-keycode-tab");
	case 27:
		return DESC(@"oolite-keycode-esc");
	case 32:
		return DESC(@"oolite-keycode-space");
	case gvFunctionKey1:
		return DESC(@"oolite-keycode-f1");
	case gvFunctionKey2:
		return DESC(@"oolite-keycode-f2");
	case gvFunctionKey3:
		return DESC(@"oolite-keycode-f3");
	case gvFunctionKey4:
		return DESC(@"oolite-keycode-f4");
	case gvFunctionKey5:
		return DESC(@"oolite-keycode-f5");
	case gvFunctionKey6:
		return DESC(@"oolite-keycode-f6");
	case gvFunctionKey7:
		return DESC(@"oolite-keycode-f7");
	case gvFunctionKey8:
		return DESC(@"oolite-keycode-f8");
	case gvFunctionKey9:
		return DESC(@"oolite-keycode-f9");
	case gvFunctionKey10:
		return DESC(@"oolite-keycode-f10");
	case gvFunctionKey11:
		return DESC(@"oolite-keycode-f11");
	case gvArrowKeyRight:
		return DESC(@"oolite-keycode-right");
	case gvArrowKeyLeft:
		return DESC(@"oolite-keycode-left");
	case gvArrowKeyDown:
		return DESC(@"oolite-keycode-down");
	case gvArrowKeyUp:
		return DESC(@"oolite-keycode-up");
	case gvHomeKey:
		return DESC(@"oolite-keycode-home");
	case gvEndKey:
		return DESC(@"oolite-keycode-end");
	case gvInsertKey:
		return DESC(@"oolite-keycode-insert");
	case gvDeleteKey:
		return DESC(@"oolite-keycode-delete");
	case gvPageUpKey:
		return DESC(@"oolite-keycode-pageup");
	case gvPageDownKey:
		return DESC(@"oolite-keycode-pagedown");
	default:
		return [NSString stringWithFormat:@"%C",code];
	}
}


@end


Vector OOGalacticCoordinatesFromInternal(NSPoint internalCoordinates)
{
	return (Vector){ (float)internalCoordinates.x * 0.4f, (float)internalCoordinates.y * 0.2f, 0.0f };
}


NSPoint OOInternalCoordinatesFromGalactic(Vector galacticCoordinates)
{
	return (NSPoint){ (float)galacticCoordinates.x * 2.5f, (float)galacticCoordinates.y * 5.0f };
}
