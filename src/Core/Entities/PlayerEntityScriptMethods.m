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
#import "OOSystemDescriptionManager.h"

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


- (void) awardCommodityType:(OOCommodityType)type amount:(OOCargoQuantity)amount
{
	OOMassUnit				unit;

	if (![[UNIVERSE commodities] goodDefined:type])
	{
		return;
	}
	
	OOLog(@"script.debug.note.awardCargo", @"Going to award cargo: %d x '%@'", amount, type);
	
	unit = [shipCommodityData massUnitForGood:type];
	
	if ([self status] != STATUS_DOCKED)
	{
		// in-flight
		while (amount)
		{
			if (unit != UNITS_TONS)
			{
				if (specialCargo)
				{
					// is this correct behaviour?
					[shipCommodityData addQuantity:amount forGood:type];
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
			else if (!specialCargo)
			// no adding TCs while special cargo in hold
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
		int manifest_quantity = [shipCommodityData quantityForGood:type];
		while ((amount)&&(current_cargo < [self maxAvailableCargoSpace]))
		{
			manifest_quantity++;
			amount--;
			if (unit == UNITS_TONS)  current_cargo++;
		}
		[shipCommodityData setQuantity:manifest_quantity forGood:type];
	}
	[self calculateCurrentCargo];
}


- (void) resetScannerZoom
{
	scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
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


/* FIXME: these next three functions seed the RNG when called. That
 * could cause unwanted effects - should save its state, and then
 * reset it after generating the number. */
- (unsigned) systemPseudoRandom100
{
	seed_RNG_only_for_planet_description([[UNIVERSE systemManager] getRandomSeedForCurrentSystem]);
	return (gen_rnd_number() * 256 + gen_rnd_number()) % 100;
}


- (unsigned) systemPseudoRandom256
{
	seed_RNG_only_for_planet_description([[UNIVERSE systemManager] getRandomSeedForCurrentSystem]);
	return gen_rnd_number();
}


- (double) systemPseudoRandomFloat
{
	seed_RNG_only_for_planet_description([[UNIVERSE systemManager] getRandomSeedForCurrentSystem]);
	unsigned a = gen_rnd_number();
	unsigned b = gen_rnd_number();
	unsigned c = gen_rnd_number();
	
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
	OOKeyCode key = (OOKeyCode)[keyconfig_settings oo_unsignedShortForKey:binding];
	// 0 = key not set
	return [self keyCodeDescription:key];
}

// utilising new keyconfig2.plist data
- (NSString *) keyBindingDescription2:(NSString *)binding
{
	if ([keyconfig2_settings objectForKey:binding] == nil)
	{
		// no such setting
		return nil;
	}
	NSMutableString *final = [NSMutableString string];
	NSArray *keyList = (NSArray*)[keyconfig2_settings objectForKey:binding];
	int i = 0;

	for (i = 0; i < [keyList count]; i++) {
		if (i != 0) final = [NSMutableString stringWithFormat:@"%@ / ", final];
		NSDictionary *def = [keyList objectAtIndex:i];
		NSString *key = [def objectForKey:@"key"];
		OOKeyCode k_int = (OOKeyCode)[key integerValue];
		NSString *desc = [self keyCodeDescription:k_int];
		// 0 = key not set
		if (k_int != 0) {
			if ([[def objectForKey:@"mod2"] boolValue] == YES) final = [NSMutableString stringWithFormat:@"%@Alt+", final];
			if ([[def objectForKey:@"mod1"] boolValue] == YES) final = [NSMutableString stringWithFormat:@"%@Ctrl+", final];
			if ([[def objectForKey:@"shift"] boolValue] == YES) final = [NSMutableString stringWithFormat:@"%@Shift+", final];
			final = [NSMutableString stringWithFormat:@"%@%@", final, desc];
		}
	}
	return final;
}


- (NSString *) keyCodeDescription:(OOKeyCode)code
{
	switch (code)
	{
	case 0:
		return DESC(@"oolite-keycode-unset");
	case 9:
		return DESC(@"oolite-keycode-tab");
	case 13:
		return DESC(@"oolite-keycode-enter");
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
	case gvNumberPadKey0:
		return DESC(@"oolite-keycode-numpad0");
	case gvNumberPadKey1:
		return DESC(@"oolite-keycode-numpad1");
	case gvNumberPadKey2:
		return DESC(@"oolite-keycode-numpad2");
	case gvNumberPadKey3:
		return DESC(@"oolite-keycode-numpad3");
	case gvNumberPadKey4:
		return DESC(@"oolite-keycode-numpad4");
	case gvNumberPadKey5:
		return DESC(@"oolite-keycode-numpad5");
	case gvNumberPadKey6:
		return DESC(@"oolite-keycode-numpad6");
	case gvNumberPadKey7:
		return DESC(@"oolite-keycode-numpad7");
	case gvNumberPadKey8:
		return DESC(@"oolite-keycode-numpad8");
	case gvNumberPadKey9:
		return DESC(@"oolite-keycode-numpad9");

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
