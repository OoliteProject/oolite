/*

PlayerEntity.m

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

#include <assert.h>

#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntitySound.h"
#import "PlayerEntityScriptMethods.h"

#import "StationEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "WormholeEntity.h"
#import "ProxyPlayerEntity.h"
#import "OOQuiriumCascadeEntity.h"
#import "OOLaserShotEntity.h"
#import "OOMesh.h"

#import "OOMaths.h"
#import "GameController.h"
#import "ResourceManager.h"
#import "Universe.h"
#import "AI.h"
#import "ShipEntityAI.h"
#import "MyOpenGLView.h"
#import "OOTrumble.h"
#import "PlayerEntityLoadSave.h"
#import "OOSound.h"
#import "OOColor.h"
#import "Octree.h"
#import "OOCacheManager.h"
#import "OOOXZManager.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOPListParsing.h"
#import "OOCollectionExtractors.h"
#import "OOConstToString.h"
#import "OOTexture.h"
#import "OORoleSet.h"
#import "HeadUpDisplay.h"
#import "OOOpenGLExtensionManager.h"
#import "OOMusicController.h"
#import "OOEntityFilterPredicate.h"
#import "OOShipRegistry.h"
#import "OOEquipmentType.h"
#import "NSFileManagerOOExtensions.h"
#import "OOFullScreenController.h"
#import "OODebugSupport.h"

#import "OOJSScript.h"
#import "OOScriptTimer.h"
#import "OOJSEngineTimeManagement.h"
#import "OOJSScript.h"
#import "OOJSInterfaceDefinition.h"
#import "OOConstToJSString.h"

#import "OOJoystickManager.h"
#import "PlayerEntityStickMapper.h"
#import "PlayerEntityStickProfile.h"


#define PLAYER_DEFAULT_NAME				@"Jameson"

enum
{
	// If comm log is kCommLogTrimThreshold or more lines long, it will be cut to kCommLogTrimSize.
	kCommLogTrimThreshold				= 15U,
	kCommLogTrimSize					= 10U
};


static NSString * const kOOLogBuyMountedOK			= @"equip.buy.mounted";
static NSString * const kOOLogBuyMountedFailed		= @"equip.buy.mounted.failed";
static float const 		kDeadResetTime				= 30.0f;

PlayerEntity		*gOOPlayer = nil;
static GLfloat		sBaseMass = 0.0;


@interface PlayerEntity (OOPrivate)

- (void) setExtraEquipmentFromFlags;
- (void) doTradeIn:(OOCreditsQuantity)tradeInValue forPriceFactor:(double)priceFactor;

// Subs of update:
- (void) updateMovementFlags;
- (void) updateAlertCondition;
- (void) updateFuelScoops:(OOTimeDelta)delta_t;
- (void) updateClocks:(OOTimeDelta)delta_t;
- (void) checkScriptsIfAppropriate;
- (void) updateTrumbles:(OOTimeDelta)delta_t;
- (void) performAutopilotUpdates:(OOTimeDelta)delta_t;
- (void) performInFlightUpdates:(OOTimeDelta)delta_t;
- (void) performWitchspaceCountdownUpdates:(OOTimeDelta)delta_t;
- (void) performWitchspaceExitUpdates:(OOTimeDelta)delta_t;
- (void) performLaunchingUpdates:(OOTimeDelta)delta_t;
- (void) performDockingUpdates:(OOTimeDelta)delta_t;
- (void) performDeadUpdates:(OOTimeDelta)delta_t;
- (void) updateTargeting;
- (void) showGameOver;
- (void) updateWormholes;

// Shopping
- (BOOL) tryBuyingItem:(NSString *)eqKey;

// Cargo & passenger contracts
- (NSArray*) contractsListForScriptingFromArray:(NSArray *)contractsArray forCargo:(BOOL)forCargo;

- (void) prepareMarkedDestination:(NSMutableDictionary *)markers :(NSDictionary *)marker;

- (void) witchStart;
- (void) witchJumpTo:(Random_Seed)sTo misjump:(BOOL)misjump;
- (void) witchEnd;

// Jump distance/cost calculations for selected target.
- (double) hyperspaceJumpDistance;
- (OOFuelQuantity) fuelRequiredForJump;

- (void) noteCompassLostTarget;

@end


@interface ShipEntity (Hax)

- (id) initBypassForPlayer;

@end


@implementation PlayerEntity

+ (PlayerEntity *) sharedPlayer
{
	if (EXPECT_NOT(gOOPlayer == nil))
	{
		gOOPlayer = [[PlayerEntity alloc] init];
	}
	return gOOPlayer;
}


- (void) setName:(NSString *)inName
{
	// Block super method; player ship can't be renamed.
}


- (GLfloat) baseMass
{
	if (sBaseMass <= 0.0)
	{
		// First call with initialised mass (in [UNIVERSE setUpInitialUniverse]) is always to the cobra 3, even when starting with a savegame.
		if ([self mass] > 0.0)	// bootstrap the base mass.
		{
			OOLog(@"fuelPrices", @"Setting Cobra3 base mass to: %.2f ", [self mass]);
			sBaseMass = [self mass];
		}
		else 
		{
			// This happened on startup when [UNIVERSE setUpSpace] was called before player init, inside [UNIVERSE setUpInitialUniverse].
			OOLog(@"fuelPrices", @"Player ship not initialised properly yet, using precalculated base mass.");
			return 185580.0;
		}
	}

	return sBaseMass;
}


- (void) unloadAllCargoPodsForType:(OOCommodityType)type fromArray:(NSMutableArray *) manifest
{
	NSInteger i, cargoCount = [cargo count];
	if (cargoCount == 0)  return;
	
	// step through the cargo pods adding in the quantities	
	for (i =  cargoCount - 1; i >= 0 ; i--)
	{
		ShipEntity *cargoItem = [cargo objectAtIndex:i];
		OOCommodityType commodityType = [cargoItem commodityType];
		if (commodityType == COMMODITY_UNDEFINED || commodityType == type)
		{
			if (commodityType == type)
			{
				NSMutableArray	*commodityInfo = [NSMutableArray arrayWithArray:[manifest objectAtIndex:commodityType]];	
				OOCargoQuantity amount = [commodityInfo oo_unsignedIntAtIndex:MARKET_QUANTITY] + [cargoItem commodityAmount];
				[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithUnsignedInt:amount]]; // enter the adjusted amount
				[manifest replaceObjectAtIndex:commodityType withObject:commodityInfo];
			}
			else	// undefined
			{
				OOLog(@"player.badCargoPod", @"Cargo pod %@ has bad commodity type (COMMODITY_UNDEFINED), rejecting.", cargoItem);
				continue;
			}
			[cargo removeObjectAtIndex:i];
		}
	}
}


- (void) unloadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity)quantity
{
	NSInteger			i, n_cargo = [cargo count];
	if (n_cargo == 0)  return;
	
	ShipEntity			*cargoItem = nil;
	OOCommodityType		co_type;
	OOCargoQuantity		amount;
	OOCargoQuantity		cargoToGo = quantity;

	// step through the cargo pods removing pods or quantities	
	for (i =  n_cargo - 1; (i >= 0 && cargoToGo > 0) ; i--)
	{
		cargoItem = [cargo objectAtIndex:i];
		co_type = [cargoItem commodityType];
		if (co_type == COMMODITY_UNDEFINED || co_type == type)
		{
			if (co_type == type)
			{
				amount =  [cargoItem commodityAmount];
				if (amount <= cargoToGo)
				{
					[cargo removeObjectAtIndex:i];
					cargoToGo -= amount;
				}
				else
				{
					// we only need to remove a part of the cargo to meet our target
					[cargoItem setCommodity:co_type andAmount:(amount - cargoToGo)];
					cargoToGo = 0;
					
				}
			}
			else	// undefined
			{
				OOLog(@"player.badCargoPod", @"Cargo pod %@ has bad commodity type (COMMODITY_UNDEFINED), rejecting.", cargoItem);
				continue;
			}
		}
	}
	
	// now check if we are ready. When not, proceed with quantities in the manifest.
	if (cargoToGo > 0)
	{
		NSMutableArray* manifest = [[NSMutableArray arrayWithArray:shipCommodityData] retain];
		NSMutableArray	*commodityInfo = [NSMutableArray arrayWithArray:[manifest objectAtIndex:type]];	
		amount = [commodityInfo oo_unsignedIntAtIndex:MARKET_QUANTITY] - cargoToGo;
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithUnsignedInt:amount]]; // enter the adjusted amount
		[manifest replaceObjectAtIndex:type withObject:commodityInfo];
		
		[shipCommodityData release];
		shipCommodityData = manifest;
	}
}


- (void) unloadCargoPods
{
	NSAssert([self isDocked], @"Cannot unload cargo pods unless docked.");
	
	/* loads commodities from the cargo pods onto the ship's manifest */
	NSUInteger i;
	NSMutableArray *localMarket = [[self dockedStation] localMarket];
	NSMutableArray *manifest = [[NSMutableArray arrayWithArray:localMarket] retain];  // retain
	
	// copy the quantities in ShipCommodityData to the manifest
	// (was: zero the quantities in the manifest, making a mutable array of mutable arrays)
	OOCargoQuantity amount = 0;
	
	for (i = 0; i < [manifest count]; i++)
	{
		NSMutableArray *commodityInfo = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:i]];
		NSArray *shipCommInfo = [NSArray arrayWithArray:[shipCommodityData oo_arrayAtIndex:i]];
		amount = [shipCommInfo oo_intAtIndex:MARKET_QUANTITY];
		[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:amount]];
		[manifest replaceObjectAtIndex:i withObject:commodityInfo];
		[self unloadAllCargoPodsForType:i fromArray:manifest];
	}
	
	[shipCommodityData release];
	shipCommodityData = manifest;
	
	[self calculateCurrentCargo];	// work out the correct value for current_cargo
}


// TODO: better feedback on the log as to why failing to create player cargo pods causes a CTD?
- (void) createCargoPodWithType:(OOCommodityType)type andAmount:(OOCargoQuantity)amount
{
	ShipEntity *container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
	if (container)
	{
		[container setScanClass: CLASS_CARGO];
		[container setStatus:STATUS_IN_HOLD];
		[container setCommodity:type andAmount:amount];
		[cargo addObject:container];
		[container release];
	}
	else
	{
		OOLogERR(@"player.loadCargoPods.noContainer", @"couldn't create a container in [PlayerEntity loadCargoPods]");
		// throw an exception here...
		[NSException raise:OOLITE_EXCEPTION_FATAL
								format:@"[PlayerEntity loadCargoPods] failed to create a container for cargo with role 'cargopod'"];
	}
}


- (void) loadCargoPodsForType:(OOCommodityType)type fromArray:(NSMutableArray *) manifest
{
	// load commodities from the ships manifest into individual cargo pods
	unsigned j;
	
	NSMutableArray	*commodityInfo = [[NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:type]] retain];  // retain
	OOCargoQuantity	quantity = [commodityInfo oo_unsignedIntAtIndex:MARKET_QUANTITY];
	OOMassUnit		units =	[UNIVERSE unitsForCommodity:type];
	
	if (quantity > 0)
	{
		if (units == UNITS_TONS)
		{
			// easy case
			for (j = 0; j < quantity; j++)
			{
				[self createCargoPodWithType:type andAmount:1];		// or CTD if unsuccesful (!)
			}
			// adjust manifest for this commodity
			[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:0]];
			[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:commodityInfo]];
		}
		else
		{
			OOCargoQuantity podsRequiredForQuantity, amountToLoadInCargopod, tmpQuantity;
			// reserve up to 1/2 ton of each commodity for the safe
			if (units == UNITS_KILOGRAMS) 
			{
				if (quantity <= MAX_KILOGRAMS_IN_SAFE)
				{
					tmpQuantity = quantity;
					 quantity = 0;
				}
				else
				{
					tmpQuantity = MAX_KILOGRAMS_IN_SAFE;
					quantity -= tmpQuantity;
				}
				amountToLoadInCargopod = KILOGRAMS_PER_POD;
			}
			else
			{
				if (quantity <= MAX_GRAMS_IN_SAFE) {
					tmpQuantity = quantity;
					quantity = 0;
				}
				else
				{
					tmpQuantity = MAX_GRAMS_IN_SAFE;
					quantity -= tmpQuantity;
				}
				amountToLoadInCargopod = GRAMS_PER_POD;
			}
			if (quantity > 0)
			{
				podsRequiredForQuantity = 1 + (quantity/amountToLoadInCargopod);
				
				// put each ton or part-ton beyond that in a separate container
				for (j = 0; j < podsRequiredForQuantity; j++)
				{
					if (amountToLoadInCargopod > quantity)
					{
						// last pod gets the dregs. :)
						amountToLoadInCargopod = quantity;
					}
					[self createCargoPodWithType:type andAmount:amountToLoadInCargopod];	// or CTD if unsuccesful (!)
					quantity -= amountToLoadInCargopod;
				}
				// adjust manifest for this commodity
				[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:tmpQuantity]];
				[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:commodityInfo]];
			}
		}
	}
	[commodityInfo release]; // release, done
}


- (void) loadCargoPodsForType:(OOCommodityType)type amount:(OOCargoQuantity)quantity
{
	OOMassUnit unit = [UNIVERSE unitsForCommodity:type];
	
	while (quantity)
	{
		if (unit != UNITS_TONS)
		{
			int amount_per_container = (unit == UNITS_KILOGRAMS)? KILOGRAMS_PER_POD : GRAMS_PER_POD;
			while (quantity > 0)
			{
				int smaller_quantity = 1 + ((quantity - 1) % amount_per_container);
				if ([cargo count] < [self maxAvailableCargoSpace])
				{
					ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
					if (container)
					{
						// the cargopod ship is just being set up. If ejected,  will call UNIVERSE addEntity
						[container setStatus:STATUS_IN_HOLD];
						[container setScanClass: CLASS_CARGO];
						[container setCommodity:type andAmount:smaller_quantity];
						[cargo addObject:container];
						[container release];
					}
				}
				else
				{
					// try to squeeze any surplus, up to half a ton, in the manifest.
					int amount;		
					NSMutableArray* manifest = [[NSMutableArray arrayWithArray:shipCommodityData] retain];
					NSMutableArray	*commodityInfo = [NSMutableArray arrayWithArray:[manifest objectAtIndex:type]];	
					amount = [commodityInfo oo_intAtIndex:MARKET_QUANTITY] + smaller_quantity;
					if (amount > MAX_GRAMS_IN_SAFE && unit == UNITS_GRAMS) amount = MAX_GRAMS_IN_SAFE;
					else if (amount > MAX_KILOGRAMS_IN_SAFE && unit == UNITS_KILOGRAMS) amount = MAX_KILOGRAMS_IN_SAFE;

					[commodityInfo replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:amount]]; // enter the adjusted amount
					[manifest replaceObjectAtIndex:type withObject:commodityInfo];
					
					[shipCommodityData release];
					shipCommodityData = manifest;
				}
				quantity -= smaller_quantity;
			}
		}
		else
		{
			// put each ton in a separate container
			while (quantity)
			{
				if ([cargo count] < [self maxAvailableCargoSpace])
				{
					ShipEntity* container = [UNIVERSE newShipWithRole:@"1t-cargopod"];
					if (container)
					{
						// the cargopod ship is just being set up. If ejected, will call UNIVERSE addEntity
						[container setScanClass: CLASS_CARGO];
						[container setStatus:STATUS_IN_HOLD];
						[container setCommodity:type andAmount:1];
						[cargo addObject:container];
						[container release];
					}
				}
				quantity--;
			}
		}
	}
}


- (void) loadCargoPods
{
	/* loads commodities from the ships manifest into individual cargo pods */
	unsigned i;

	NSMutableArray* manifest = [[NSMutableArray arrayWithArray:shipCommodityData] retain];  // retain
	
	if (cargo == nil)  cargo = [[NSMutableArray alloc] init];
	
	for (i = 0; i < [manifest count]; i++)
	{
		[self loadCargoPodsForType:i fromArray: manifest];
	}
	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	[manifest release]; // release, done
}


- (NSMutableArray *) shipCommodityData
{
	return shipCommodityData;
}


- (OOCreditsQuantity) deciCredits
{
	return credits;
}


- (int) random_factor
{
	return market_rnd;
}


- (void) setRandom_factor:(int)rf
{
	market_rnd = rf;
}


- (OOGalaxyID) galaxyNumber
{
	return galaxy_number;
}


- (Random_Seed) galaxy_seed
{
	return galaxy_seed;
}


- (NSPoint) galaxy_coordinates
{
	return galaxy_coordinates;
}


- (void) setGalaxyCoordinates:(NSPoint)newPosition
{
	galaxy_coordinates.x = newPosition.x;
	galaxy_coordinates.y = newPosition.y;
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


- (void) setTargetSystemSeed:(Random_Seed) s_seed
{
	target_system_seed = s_seed;
	cursor_coordinates = NSMakePoint(s_seed.d, s_seed.b);
}


- (WormholeEntity *) wormhole
{
	return wormhole;
}


- (void) setWormhole:(WormholeEntity*)newWormhole
{
	[wormhole release];
	if (newWormhole != nil)
	{
		wormhole = [newWormhole retain];
	}
	else
	{
		wormhole = nil;
	}
}


- (NSDictionary *) commanderDataDictionary
{
	NSAssert([self isDocked], @"Cannot create commander data dictionary unless docked.");
	
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	
	[result setObject:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"written_by_version"];

	NSString	*gal_seed = [NSString stringWithFormat:@"%d %d %d %d %d %d", galaxy_seed.a, galaxy_seed.b, galaxy_seed.c, galaxy_seed.d, galaxy_seed.e, galaxy_seed.f];
	NSString	*gal_coords = [NSString stringWithFormat:@"%d %d",(int)galaxy_coordinates.x,(int)galaxy_coordinates.y];
	NSString	*tgt_coords = [NSString stringWithFormat:@"%d %d",(int)cursor_coordinates.x,(int)cursor_coordinates.y];
	// Variable requiredCargoSpace not suitable for Oolite as it currently stands: it retroactively changes a savegame cargo space.
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	
	[result setObject:gal_seed		forKey:@"galaxy_seed"];
	[result setObject:gal_coords	forKey:@"galaxy_coordinates"];
	[result setObject:tgt_coords	forKey:@"target_coordinates"];
	
	if (!equal_seeds(found_system_seed,kNilRandomSeed))
	{
		NSString *found_seed = [NSString stringWithFormat:@"%d %d %d %d %d %d", found_system_seed.a, found_system_seed.b, found_system_seed.c, found_system_seed.d, found_system_seed.e, found_system_seed.f];
		[result setObject:found_seed	forKey:@"found_system_seed"];
	}
	
	// Write the name of the current system. Useful for looking up saved game information and for overlapping systems.
	[result setObject:[UNIVERSE getSystemName:[self system_seed]] forKey:@"current_system_name"];
	// Write the name of the targeted system. Useful for overlapping systems.
	[result setObject:[UNIVERSE getSystemName:[self target_system_seed]] forKey:@"target_system_name"];
	
	[result setObject:[self commanderName] forKey:@"player_name"];
	[result setObject:[self lastsaveName] forKey:@"player_save_name"];
	[result setObject:[self shipUniqueName] forKey:@"ship_unique_name"];
	[result setObject:[self shipClassName] forKey:@"ship_class_name"];

	/*
		BUG: GNUstep truncates integer values to 32 bits when loading XML plists.
		Workaround: store credits as a double. 53 bits of precision ought to
		be good enough for anybody. Besides, we display credits with double
		precision anyway.
		-- Ahruman 2011-02-15
	*/
	[result oo_setFloat:credits				forKey:@"credits"];
	[result oo_setUnsignedInteger:fuel		forKey:@"fuel"];
	
	[result oo_setInteger:galaxy_number	forKey:@"galaxy_number"];
	
	[result oo_setBool:[self weaponsOnline]	forKey:@"weapons_online"];
	
	[result oo_setInteger:forward_weapon_type	forKey:@"forward_weapon"];
	[result oo_setInteger:aft_weapon_type		forKey:@"aft_weapon"];
	[result oo_setInteger:port_weapon_type		forKey:@"port_weapon"];
	[result oo_setInteger:starboard_weapon_type	forKey:@"starboard_weapon"];
	[result setObject:[self serializeShipSubEntities] forKey:@"subentities_status"];
	
	[result oo_setInteger:max_cargo + PASSENGER_BERTH_SPACE * max_passengers	forKey:@"max_cargo"];
	
	[result setObject:shipCommodityData		forKey:@"shipCommodityData"];
	
	// sanitise commodity units - the savegame might contain the wrong units
	NSMutableArray *manifest = [NSMutableArray arrayWithArray:shipCommodityData];
	NSInteger i;
	for (i = [manifest count] - 1; i >= 0 ; i--)
	{
		NSMutableArray	*commodityInfo = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:i]];
		// manifest contains entries for all 17 commodities, whether their quantity is 0 or more.
		[commodityInfo replaceObjectAtIndex:MARKET_UNITS withObject:[NSNumber numberWithInt:[UNIVERSE unitsForCommodity:i]]];
		[manifest replaceObjectAtIndex:i withObject:[NSArray arrayWithArray:commodityInfo]];

	}
	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	
	// Deprecated equipment flags. New equipment shouldn't be added here (it'll be handled by the extra_equipment dictionary).
	[result oo_setBool:[self hasDockingComputer]		forKey:@"has_docking_computer"];
	[result oo_setBool:[self hasGalacticHyperdrive]		forKey:@"has_galactic_hyperdrive"];
	[result oo_setBool:[self hasEscapePod]				forKey:@"has_escape_pod"];
	[result oo_setBool:[self hasECM]					forKey:@"has_ecm"];
	[result oo_setBool:[self hasScoop]					forKey:@"has_scoop"];
	[result oo_setBool:[self hasFuelInjection]			forKey:@"has_fuel_injection"];
	
	if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"])
	{
		[result oo_setBool:YES forKey:@"has_energy_unit"];
		[result oo_setInteger:OLD_ENERGY_UNIT_NAVAL forKey:@"energy_unit"];
	}
	else if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT"])
	{
		[result oo_setBool:YES forKey:@"has_energy_unit"];
		[result oo_setInteger:OLD_ENERGY_UNIT_NORMAL forKey:@"energy_unit"];
	}
	
	NSMutableArray *missileRoles = [NSMutableArray arrayWithCapacity:max_missiles];
	
	for (i = 0; i < (int)max_missiles; i++)
	{
		if (missile_entity[i])
		{
			[missileRoles addObject:[missile_entity[i] primaryRole]];
		}
		else
		{
			[missileRoles addObject:@"NONE"];
		}
	}
	[result setObject:missileRoles forKey:@"missile_roles"];
	
	[result oo_setInteger:missiles forKey:@"missiles"];
	
	[result oo_setInteger:legalStatus forKey:@"legal_status"];
	[result oo_setInteger:market_rnd forKey:@"market_rnd"];
	[result oo_setInteger:ship_kills forKey:@"ship_kills"];

	// ship depreciation
	[result oo_setInteger:ship_trade_in_factor forKey:@"ship_trade_in_factor"];

	// mission variables
	if (mission_variables != nil)
	{
		[result setObject:[NSDictionary dictionaryWithDictionary:mission_variables] forKey:@"mission_variables"];
	}

	// communications log
	NSArray *log = [self commLog];
	if (log != nil)  [result setObject:log forKey:@"comm_log"];
	
	[result oo_setUnsignedInteger:entity_personality forKey:@"entity_personality"];
	
	// extra equipment flags
	NSMutableDictionary	*equipment = [NSMutableDictionary dictionary];
	NSEnumerator		*eqEnum = nil;
	NSString			*eqDesc = nil;
	for (eqEnum = [self equipmentEnumerator]; (eqDesc = [eqEnum nextObject]); )
	{
		[equipment oo_setBool:YES forKey:eqDesc];
	}
	if ([equipment count] != 0)
	{
		[result setObject:equipment forKey:@"extra_equipment"];
	}
	if (primedEquipment < [eqScripts count]) [result setObject:[[eqScripts oo_arrayAtIndex:primedEquipment] oo_stringAtIndex:0] forKey:@"primed_equipment"];
	
	[result setObject:[self fastEquipmentA] forKey:@"primed_equipment_a"];
	[result setObject:[self fastEquipmentB] forKey:@"primed_equipment_b"];

	// roles
	[result setObject:roleWeights forKey:@"role_weights"];

	// role information
	[result setObject:roleWeightFlags forKey:@"role_weight_flags"];

	// role information
	[result setObject:roleSystemList forKey:@"role_system_memory"];

	// reputation
	[result setObject:reputation forKey:@"reputation"];
	
	// initialise parcel reputations in dictionary if not set
	int pGood = [reputation oo_intForKey:PARCEL_GOOD_KEY];
	int pBad = [reputation oo_intForKey:PARCEL_BAD_KEY];
	int pUnknown = [reputation oo_intForKey:PARCEL_UNKNOWN_KEY];
	if (pGood+pBad+pUnknown != MAX_CONTRACT_REP)
	{
		[reputation oo_setInteger:0 forKey:PARCEL_GOOD_KEY];
		[reputation oo_setInteger:0 forKey:PARCEL_BAD_KEY];
		[reputation oo_setInteger:MAX_CONTRACT_REP forKey:PARCEL_UNKNOWN_KEY];
	}

	// passengers
	[result oo_setInteger:max_passengers forKey:@"max_passengers"];
	[result setObject:passengers forKey:@"passengers"];
	[result setObject:passenger_record forKey:@"passenger_record"];

	// parcels
	[result setObject:parcels forKey:@"parcels"];
	[result setObject:parcel_record forKey:@"parcel_record"];
	
	//specialCargo
	if (specialCargo)  [result setObject:specialCargo forKey:@"special_cargo"];
	
	// contracts
	[result setObject:contracts forKey:@"contracts"];
	[result setObject:contract_record forKey:@"contract_record"];

	[result setObject:missionDestinations forKey:@"mission_destinations"];

	//shipyard
	[result setObject:shipyard_record forKey:@"shipyard_record"];

	//ship's clock
	[result setObject:[NSNumber numberWithDouble:ship_clock] forKey:@"ship_clock"];

	//speech
	[result setObject:[NSNumber numberWithBool:isSpeechOn] forKey:@"speech_on"];
#if OOLITE_ESPEAK
	[result setObject:[UNIVERSE voiceName:voice_no] forKey:@"speech_voice"];
	[result setObject:[NSNumber numberWithBool:voice_gender_m] forKey:@"speech_gender"];
#endif

	// gamma control
	[result setObject:[NSNumber numberWithFloat:[[UNIVERSE gameView] gammaValue]] forKey:@"gamma_control"];
	
	// docking clearance
	[result setObject:[NSNumber numberWithBool:[UNIVERSE dockingClearanceProtocolActive]] forKey:@"docking_clearance_protocol"];

	//base ship description
	[result setObject:[self shipDataKey] forKey:@"ship_desc"];
	[result setObject:[[self shipInfoDictionary] oo_stringForKey:KEY_NAME] forKey:@"ship_name"];

	//custom view no.
	[result oo_setUnsignedInteger:_customViewIndex forKey:@"custom_view_index"];

	//local market for main station
	if ([[UNIVERSE station] localMarket])  [result setObject:[[UNIVERSE station] localMarket] forKey:@"localMarket"];

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

	// wormhole information
	NSMutableArray *wormholeDicts = [NSMutableArray arrayWithCapacity:[scannedWormholes count]];
	NSEnumerator *wormholes = [scannedWormholes objectEnumerator];
	WormholeEntity *wh = nil;
	foreach(wh, wormholes)
	{
		[wormholeDicts addObject:[wh getDict]];
	}
	[result setObject:wormholeDicts forKey:@"wormholes"];

	// docked station
	StationEntity *dockedStation = [self dockedStation];
	[result setObject:[dockedStation primaryRole] forKey:@"docked_station_role"];
	HPVector dpos = [dockedStation position];
	[result setObject:ArrayFromHPVector(dpos) forKey:@"docked_station_position"];
	[result setObject:[UNIVERSE getStationMarkets] forKey:@"station_markets"];

	// scenario information
	if (scenarioKey != nil)
	{
		[result setObject:scenarioKey forKey:@"scenario"];
	}

	// create checksum
	clear_checksum();
	munge_checksum(galaxy_seed.a);	munge_checksum(galaxy_seed.b);	munge_checksum(galaxy_seed.c);
	munge_checksum(galaxy_seed.d);	munge_checksum(galaxy_seed.e);	munge_checksum(galaxy_seed.f);
	munge_checksum(galaxy_coordinates.x);	munge_checksum(galaxy_coordinates.y);
	munge_checksum(credits);		munge_checksum(fuel);
	munge_checksum(max_cargo);		munge_checksum(missiles);
	munge_checksum(legalStatus);	munge_checksum(market_rnd);		munge_checksum(ship_kills);
	
	if (mission_variables != nil)
	{
		munge_checksum([[mission_variables description] length]);
	}
	if (equipment != nil)
	{
		munge_checksum([[equipment description] length]);
	}
	
	int final_checksum = munge_checksum([[self shipDataKey] length]);

	//set checksum
	[result oo_setInteger:final_checksum forKey:@"checksum"];
	
	return result;
}


- (BOOL)setCommanderDataFromDictionary:(NSDictionary *) dict
{
	NSUInteger	i;
	
	// multi-function displays
	// must be reset before ship setup
	[multiFunctionDisplayText release];
	multiFunctionDisplayText = [[NSMutableDictionary alloc] init];

	[multiFunctionDisplaySettings release];
	multiFunctionDisplaySettings = [[NSMutableArray alloc] init];

	[[UNIVERSE gameView] resetTypedString];
	// must do this on game load now caches an entire chart
	[UNIVERSE resetSystemDataCache];

	// Required keys
	if ([dict oo_stringForKey:@"ship_desc"] == nil)  return NO;
	if ([dict oo_stringForKey:@"galaxy_seed"] == nil)  return NO;
	if ([dict oo_stringForKey:@"galaxy_coordinates"] == nil)  return NO;
	
	BOOL strict = [dict oo_boolForKey:@"strict" defaultValue:NO];
	if (![UNIVERSE setStrict:strict fromSaveGame:YES]) return NO;
	
	//base ship description
	[self setShipDataKey:[dict oo_stringForKey:@"ship_desc"]];
	
	NSDictionary *shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:[self shipDataKey]];
	if (shipDict == nil)  return NO;
	if (![self setUpShipFromDictionary:shipDict])  return NO;
	OOLog(@"fuelPrices", @"Got \"%@\", fuel charge rate: %.2f", [self shipDataKey],[self fuelChargeRate]);
	
	// ship depreciation
	ship_trade_in_factor = [dict oo_intForKey:@"ship_trade_in_factor" defaultValue:95];
	
	galaxy_seed = RandomSeedFromString([dict oo_stringForKey:@"galaxy_seed"]);
	if (is_nil_seed(galaxy_seed))  return NO;
	[UNIVERSE setGalaxySeed: galaxy_seed andReinit:YES];
	
	NSArray *coord_vals = ScanTokensFromString([dict oo_stringForKey:@"galaxy_coordinates"]);
	galaxy_coordinates.x = [coord_vals oo_unsignedCharAtIndex:0];
	galaxy_coordinates.y = [coord_vals oo_unsignedCharAtIndex:1];
	cursor_coordinates = galaxy_coordinates;
	
	NSString *keyStringValue = [dict oo_stringForKey:@"target_coordinates"];
	if (keyStringValue != nil)
	{
		coord_vals = ScanTokensFromString(keyStringValue);
		cursor_coordinates.x = [coord_vals oo_unsignedCharAtIndex:0];
		cursor_coordinates.y = [coord_vals oo_unsignedCharAtIndex:1];
	}
	
	keyStringValue = [dict oo_stringForKey:@"found_system_seed"];
	found_system_seed = (keyStringValue != nil) ? RandomSeedFromString(keyStringValue) : kNilRandomSeed;
	
	NSString *cname = [dict oo_stringForKey:@"player_name" defaultValue:PLAYER_DEFAULT_NAME];
	[self setCommanderName:cname];
	[self setLastsaveName:[dict oo_stringForKey:@"player_save_name" defaultValue:cname]];

	[self setShipUniqueName:[dict oo_stringForKey:@"ship_unique_name" defaultValue:@""]];
	[self setShipClassName:[dict oo_stringForKey:@"ship_class_name" defaultValue:[shipDict oo_stringForKey:@"name"]]];
	
	[shipCommodityData autorelease];
	shipCommodityData = [[dict oo_arrayForKey:@"shipCommodityData" defaultValue:shipCommodityData] copy];
	
	// extra equipment flags
	[self removeAllEquipment];
	NSMutableDictionary *equipment = [NSMutableDictionary dictionaryWithDictionary:[dict oo_dictionaryForKey:@"extra_equipment"]];
	
	// Equipment flags	(deprecated in favour of equipment dictionary, keep for compatibility)
	if ([dict oo_boolForKey:@"has_docking_computer"])		[equipment oo_setBool:YES forKey:@"EQ_DOCK_COMP"];
	if ([dict oo_boolForKey:@"has_galactic_hyperdrive"])	[equipment oo_setBool:YES forKey:@"EQ_GAL_DRIVE"];
	if ([dict oo_boolForKey:@"has_escape_pod"])				[equipment oo_setBool:YES forKey:@"EQ_ESCAPE_POD"];
	if ([dict oo_boolForKey:@"has_ecm"])					[equipment oo_setBool:YES forKey:@"EQ_ECM"];
	if ([dict oo_boolForKey:@"has_scoop"])					[equipment oo_setBool:YES forKey:@"EQ_FUEL_SCOOPS"];
	if ([dict oo_boolForKey:@"has_energy_bomb"])			[equipment oo_setBool:YES forKey:@"EQ_ENERGY_BOMB"];
	if ([dict oo_boolForKey:@"has_fuel_injection"])		[equipment oo_setBool:YES forKey:@"EQ_FUEL_INJECTION"];
	
	
	// Legacy energy unit type -> energy unit equipment item
	if ([dict oo_boolForKey:@"has_energy_unit"] && [self installedEnergyUnitType] == ENERGY_UNIT_NONE)
	{
		OOEnergyUnitType eType = [dict oo_intForKey:@"energy_unit" defaultValue:ENERGY_UNIT_NORMAL];
		switch (eType)
		{
			// look for NEU first!
			case OLD_ENERGY_UNIT_NAVAL:
				[equipment oo_setBool:YES forKey:@"EQ_NAVAL_ENERGY_UNIT"];
				break;
			
			case OLD_ENERGY_UNIT_NORMAL:
				[equipment oo_setBool:YES forKey:@"EQ_ENERGY_UNIT"];
				break;

			default:
				break;
		}
	}
	
	/*	Energy bombs are no longer supported without OXPs. As compensation,
		we'll award either a Q-mine or some cash. We can't determine what to
		award until we've handled missiles later on, though.
	*/
	BOOL energyBombCompensation = NO;
	if ([equipment oo_boolForKey:@"EQ_ENERGY_BOMB"] && [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_ENERGY_BOMB"] == nil)
	{
		energyBombCompensation = YES;
		[equipment removeObjectForKey:@"EQ_ENERGY_BOMB"];
	}
	
	eqScripts = [[NSMutableArray alloc] init];
	[self addEquipmentFromCollection:equipment];
	primedEquipment = [self eqScriptIndexForKey:[dict oo_stringForKey:@"primed_equipment"]];	// if key not found primedEquipment is set to primed-none
	
	[self setFastEquipmentA:[dict oo_stringForKey:@"primed_equipment_a" defaultValue:@"EQ_CLOAKING_DEVICE"]];
	[self setFastEquipmentB:[dict oo_stringForKey:@"primed_equipment_b" defaultValue:@"EQ_ENERGY_BOMB"]]; // even though there isn't one, for compatibility.

	if ([self hasEquipmentItem:@"EQ_ADVANCED_COMPASS"])  compassMode = COMPASS_MODE_PLANET;
	else  compassMode = COMPASS_MODE_BASIC;
	DESTROY(compassTarget);
	
	// speech
	isSpeechOn = [dict oo_boolForKey:@"speech_on"];
#if OOLITE_ESPEAK
	voice_gender_m = [dict oo_boolForKey:@"speech_gender" defaultValue:YES];
	voice_no = [UNIVERSE setVoice:[UNIVERSE voiceNumber:[dict oo_stringForKey:@"speech_voice" defaultValue:nil]] withGenderM:voice_gender_m];
#endif
	
	// reputation
	[reputation release];
	reputation = [[dict oo_dictionaryForKey:@"reputation"] mutableCopy];
	if (reputation == nil)  reputation = [[NSMutableDictionary alloc] init];
	[self normaliseReputation];

	// passengers and contracts
	[parcels release];
	[parcel_record release];
	[passengers release];
	[passenger_record release];
	[contracts release];
	[contract_record release];
	
	max_passengers = [dict oo_intForKey:@"max_passengers" defaultValue:0];
	passengers = [[dict oo_arrayForKey:@"passengers"] mutableCopy];
	passenger_record = [[dict oo_dictionaryForKey:@"passenger_record"] mutableCopy];
	contracts = [[dict oo_arrayForKey:@"contracts"] mutableCopy];
	contract_record = [[dict oo_dictionaryForKey:@"contract_record"] mutableCopy];
	parcels = [[dict oo_arrayForKey:@"parcels"] mutableCopy];
	parcel_record = [[dict oo_dictionaryForKey:@"parcel_record"] mutableCopy];

	
	
	if (passengers == nil)  passengers = [[NSMutableArray alloc] init];
	if (passenger_record == nil)  passenger_record = [[NSMutableDictionary alloc] init];
	if (contracts == nil)  contracts = [[NSMutableArray alloc] init];
	if (contract_record == nil)  contract_record = [[NSMutableDictionary alloc] init];
	if (parcels == nil)  parcels = [[NSMutableArray alloc] init];
	if (parcel_record == nil)  parcel_record = [[NSMutableDictionary alloc] init];
	
	//specialCargo
	[specialCargo release];
	specialCargo = [[dict oo_stringForKey:@"special_cargo"] copy];
	
	// mission destinations
	NSArray *legacyDestinations = [dict oo_arrayForKey:@"missionDestinations"];

	NSDictionary *newDestinations = [dict oo_dictionaryForKey:@"mission_destinations"];
	[self initialiseMissionDestinations:newDestinations andLegacy:legacyDestinations];
	
	// shipyard
	shipyard_record = [[dict oo_dictionaryForKey:@"shipyard_record"] mutableCopy];
	if (shipyard_record == nil)  shipyard_record = [[NSMutableDictionary alloc] init];
	
	// Normalize cargo capacity
	unsigned	original_hold_size = [UNIVERSE maxCargoForShip:[self shipDataKey]];
	// Not Suitable For Oolite
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	
	max_cargo = [dict oo_unsignedIntForKey:@"max_cargo" defaultValue:max_cargo];
	if (max_cargo > original_hold_size)  [self addEquipmentItem:@"EQ_CARGO_BAY" inContext:@"loading"];
	max_cargo = original_hold_size + ([self hasExpandedCargoBay] ? extra_cargo : 0);
	if (max_cargo < max_passengers * PASSENGER_BERTH_SPACE)
	{
		// Something went wrong. Possibly the save file was hacked to contain more passenger cabins than the available cargo space would allow - Nikos 20110731
		unsigned originalMaxPassengers = max_passengers;
		max_passengers = (unsigned)(max_cargo / PASSENGER_BERTH_SPACE);
		OOLogWARN(@"setCommanderDataFromDictionary.inconsistency.max_passengers", @"player ship %@ had max_passengers set to a value requiring more cargo space than currently available (%u). Setting max_passengers to maximum possible value (%u).", [self name], originalMaxPassengers, max_passengers);
	}
	max_cargo -= max_passengers * PASSENGER_BERTH_SPACE;
	
	// Do we have extra passengers?
	if (passengers && ([passengers count] > max_passengers))
	{
		OOLogWARN(@"setCommanderDataFromDictionary.inconsistency.passengers", @"player ship %@ had more passengers (%lu) than passenger berths (%u). Removing extra passengers.", [self name], [passengers count], max_passengers);
		for (i = [passengers count] - 1; i >= max_passengers; i--)
		{
			[passenger_record removeObjectForKey:[[passengers oo_dictionaryAtIndex:i] oo_stringForKey:PASSENGER_KEY_NAME]];
			[passengers removeObjectAtIndex:i];
		}
	}
	
	// too much cargo?	
	int excessCargo = [self cargoQuantityOnBoard] - [self maxAvailableCargoSpace];
	if (excessCargo > 0)
	{
		OOLogWARN(@"setCommanderDataFromDictionary.inconsistency.cargo", @"player ship %@ had more cargo (%i) than it can hold (%u). Removing extra cargo.", [self name], [self cargoQuantityOnBoard], [self maxAvailableCargoSpace]);
		
		NSMutableArray		*manifest = [NSMutableArray arrayWithArray:shipCommodityData];
		OOCommodityType		type;
		OOMassUnit			units;
		OOCargoQuantity		oldAmount, toRemove;
		
		i = excessCargo;
		
		// manifest always contains entries for all 17 commodities, even if their quantity is 0.
		for (type = [manifest count]; i > 0 && type >= 0; type--)
		{
			units =	[UNIVERSE unitsForCommodity:type];
			NSMutableArray	*manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:type]];
			oldAmount = [manifest_commodity oo_intAtIndex:MARKET_QUANTITY];
			BOOL roundedTon = (units != UNITS_TONS) && ((units == UNITS_KILOGRAMS && oldAmount > MAX_KILOGRAMS_IN_SAFE) || (units == UNITS_GRAMS && oldAmount > MAX_GRAMS_IN_SAFE));
			if (roundedTon || (units == UNITS_TONS && oldAmount > 0))
			{
				// let's remove stuff
				OOCargoQuantity partAmount = oldAmount;
				toRemove = 0;
				while (i > 0 && partAmount > 0)
				{
					if (EXPECT_NOT(roundedTon && ((units == UNITS_KILOGRAMS && partAmount > MAX_KILOGRAMS_IN_SAFE) || (units == UNITS_GRAMS && partAmount > MAX_GRAMS_IN_SAFE))))
					{
						toRemove += (units == UNITS_KILOGRAMS) ? (partAmount > (KILOGRAMS_PER_POD + MAX_KILOGRAMS_IN_SAFE) ? KILOGRAMS_PER_POD : partAmount - MAX_KILOGRAMS_IN_SAFE)
									: (partAmount > (GRAMS_PER_POD + MAX_GRAMS_IN_SAFE) ? GRAMS_PER_POD : partAmount - MAX_GRAMS_IN_SAFE);
						partAmount = oldAmount - toRemove;
						i--;
					}
					else if (!roundedTon)
					{
						toRemove++;
						partAmount--;
						i--;
					}
					else
					{
						partAmount = 0;
					}
				}
				
				[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt: oldAmount - toRemove]];
				[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
			}
		}
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	}
	
	credits = OODeciCreditsFromObject([dict objectForKey:@"credits"]);
	
	fuel = [dict oo_unsignedIntForKey:@"fuel" defaultValue:fuel];
	galaxy_number = [dict oo_intForKey:@"galaxy_number"];
//
	NSDictionary *shipyard_info = [[OOShipRegistry sharedRegistry] shipyardInfoForKey:[self shipDataKey]];
	OOWeaponFacingSet available_facings = [shipyard_info oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:[self weaponFacings]];

	if (available_facings & WEAPON_FACING_FORWARD)
		forward_weapon_type = [dict oo_intForKey:@"forward_weapon"];
	else
		forward_weapon_type = WEAPON_NONE;

	if (available_facings & WEAPON_FACING_AFT)
		aft_weapon_type = [dict oo_intForKey:@"aft_weapon"];
	else
		aft_weapon_type = WEAPON_NONE;

	if (available_facings & WEAPON_FACING_PORT)
		port_weapon_type = [dict oo_intForKey:@"port_weapon"];
	else
		port_weapon_type = WEAPON_NONE;

	if (available_facings & WEAPON_FACING_STARBOARD)
		starboard_weapon_type = [dict oo_intForKey:@"starboard_weapon"];
	else
		starboard_weapon_type = WEAPON_NONE;
	
	weapons_online = [dict oo_boolForKey:@"weapons_online" defaultValue:YES];
	
	legalStatus = [dict oo_intForKey:@"legal_status"];
	market_rnd = [dict oo_intForKey:@"market_rnd"];
	ship_kills = [dict oo_intForKey:@"ship_kills"];
	
	ship_clock = [dict oo_doubleForKey:@"ship_clock" defaultValue:PLAYER_SHIP_CLOCK_START];
	fps_check_time = ship_clock;
	
	// role weights
	[roleWeights release];
	roleWeights = [[dict oo_arrayForKey:@"role_weights"] mutableCopy];
	NSUInteger rc = [self maxPlayerRoles];
	if (roleWeights == nil)
	{
		roleWeights = [[NSMutableArray alloc] initWithCapacity:rc];
		while (rc-- > 0)
		{
			[roleWeights addObject:@"player-unknown"];
		}
	}
	else
	{
		if ([roleWeights count] > rc)
		{
			[roleWeights removeObjectsInRange:(NSRange) {rc,[roleWeights count]-rc}];
		}
	}

	roleWeightFlags = [[dict oo_dictionaryForKey:@"role_weight_flags"] mutableCopy];
	if (roleWeightFlags == nil)
	{
		roleWeightFlags = [[NSMutableDictionary alloc] init];
	}

	roleSystemList = [[dict oo_arrayForKey:@"role_system_memory"] mutableCopy];
	if (roleSystemList == nil)
	{
		roleSystemList = [[NSMutableArray alloc] initWithCapacity:32];
	}


	// mission_variables
	[mission_variables release];
	mission_variables = [[dict oo_dictionaryForKey:@"mission_variables"] mutableCopy];
	if (mission_variables == nil)  mission_variables = [[NSMutableDictionary alloc] init];
	
	// persistant UNIVERSE info
	NSDictionary *planetInfoOverrides = [dict oo_dictionaryForKey:@"local_planetinfo_overrides"];
	if (planetInfoOverrides != nil)  [UNIVERSE setLocalPlanetInfoOverrides:planetInfoOverrides];
	
	// communications log
	[commLog release];
	commLog = [[NSMutableArray alloc] initWithCapacity:kCommLogTrimThreshold];
	
	NSArray *savedCommLog = [dict oo_arrayForKey:@"comm_log"];
	NSUInteger commCount = [savedCommLog count];
	for (i = 0; i < commCount; i++)
	{
		[UNIVERSE addCommsMessage:[savedCommLog objectAtIndex:i] forCount:0 andShowComms:NO logOnly:YES];
	}

	/*	entity_personality for scripts and shaders. If undefined, we fall back
		to old behaviour of using a random value each time game is loaded (set
		up in -setUp). Saving of entity_personality was added in 1.74.
		-- Ahruman 2009-09-13
	*/
	entity_personality = [dict oo_unsignedShortForKey:@"entity_personality" defaultValue:entity_personality];
	
	// set up missiles
	[self setActiveMissile:0];
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	NSArray *missileRoles = [dict oo_arrayForKey:@"missile_roles"];
	if (missileRoles != nil)
	{
		for (i = 0, missiles = 0; i < [missileRoles count] && missiles < max_missiles; i++)
		{
			NSString *missile_desc = [missileRoles oo_stringAtIndex:i];
			if (missile_desc != nil && ![missile_desc isEqualToString:@"NONE"])
			{
				ShipEntity *amiss = [UNIVERSE newShipWithRole:missile_desc];
				if (amiss)
				{
					missile_list[missiles] = [OOEquipmentType equipmentTypeWithIdentifier:missile_desc];
					missile_entity[missiles] = amiss;   // retain count = 1
					missiles++;
				}
				else
				{
					OOLogWARN(@"load.failed.missileNotFound", @"couldn't find missile with role '%@' in [PlayerEntity setCommanderDataFromDictionary:], missile entry discarded.", missile_desc);
				}
			}
		}
	}
	else	// no missile_roles
	{
		for (i = 0; i < missiles; i++)
		{
			missile_list[i] = [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_MISSILE"];
			missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];	// retain count = 1 - should be okay as long as we keep a missile with this role
																			// in the base package.
		}
	}
	
	if (energyBombCompensation)
	{
		/*
			Compensate energy bomb with either a QC mine or the cost of an
			energy bomb (900 credits). This must be done after missiles are
			set up.
		*/
		if ([self mountMissileWithRole:@"EQ_QC_MINE"])
		{
			OOLog(@"load.upgrade.replacedEnergyBomb", @"Replaced legacy energy bomb with Quirium cascade mine.");
		}
		else
		{
			credits += 9000;
			OOLog(@"load.upgrade.replacedEnergyBomb", @"Compensated legacy energy bomb with 900 credits.");
		}
	}
	
	[self setActiveMissile:0];
	
	forward_shield = [self maxForwardShieldLevel];
	aft_shield = [self maxAftShieldLevel];
	
	// Where are we? What system are we targeting?
	// current_system_name and target_system_name, if present on the savegame,
	// are the only way - at present - to distinguish between overlapping systems. Kaks 20100706
	
	// If we have the current system name, let's see if it matches the current system.
	NSString *sysName = [dict oo_stringForKey:@"current_system_name"];
	system_seed = [UNIVERSE findSystemFromName:sysName];
	
	if (is_nil_seed(system_seed) || (galaxy_coordinates.x != system_seed.d && galaxy_coordinates.y != system_seed.b))
	{
		// no match found, find the system from the coordinates.
		system_seed = [UNIVERSE findSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
	}
	
	// If we have a target system name, let's see if it matches the system at the cursor coordinates.
	sysName = [dict oo_stringForKey:@"target_system_name"];
	target_system_seed = [UNIVERSE findSystemFromName:sysName];
	
	if (is_nil_seed(target_system_seed) || (cursor_coordinates.x != target_system_seed.d && cursor_coordinates.y != target_system_seed.b))
	{
		// no match found, find the system from the coordinates.
		BOOL sameCoords = (cursor_coordinates.x == galaxy_coordinates.x && cursor_coordinates.y == galaxy_coordinates.y);
		if (sameCoords) target_system_seed = system_seed;
		else target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	}
	
	// restore subentities status
	[self deserializeShipSubEntitiesFrom:[dict oo_stringForKey:@"subentities_status"]];
	
	// wormholes
	NSArray * whArray;
	whArray = [dict objectForKey:@"wormholes"];
	NSEnumerator * whDicts = [whArray objectEnumerator];
	NSDictionary * whCurrDict;
	[scannedWormholes release];
	scannedWormholes = [[NSMutableArray alloc] initWithCapacity:[whArray count]];
	while ((whCurrDict = [whDicts nextObject]) != nil)
	{
		WormholeEntity * wh = [[WormholeEntity alloc] initWithDict:whCurrDict];
		[scannedWormholes addObject:wh];
		/* TODO - add to Universe if the wormhole hasn't expired yet; but in this case
		 * we need to save/load position and mass as well, which we currently 
		 * don't
		if (equal_seeds([wh origin], system_seed))
		{
			[UNIVERSE addEntity:wh];
		}
		*/
	}
	
	// custom view no.
	if (_customViews != nil)
		_customViewIndex = [dict oo_unsignedIntForKey:@"custom_view_index"] % [_customViews count];


	// gamma
	[[UNIVERSE gameView] setGammaValue:[dict oo_floatForKey:@"gamma_control" defaultValue:1.0]];

	// docking clearance protocol
	[UNIVERSE setDockingClearanceProtocolActive:[dict oo_boolForKey:@"docking_clearance_protocol" defaultValue:NO]];
	
	// trumble information
	[self setUpTrumbles];
	[self setTrumbleValueFrom:[dict objectForKey:@"trumbles"]];	// if it doesn't exist we'll check user-defaults

	return YES;
}



/////////////////////////////////////////////////////////


/*	Nasty initialization mechanism:
	PlayerEntity is alloced and inited on demand by +sharedPlayer. This
	initialization doesn't actually set anything up -- apart from the
	assertion, it's like doing a bare alloc. -deferredInit does the work
	that -init "should" be doing. It assumes that -[ShipEntity initWithKey:
	definition:] will not return an object other than self.
	This is necessary because we need a pointer to the PlayerEntity early in
	startup, when ship data hasn't been loaded yet. In particular, we need
	a pointer to the player to set up the JavaScript environment, we need the
	JavaScript environment to set up OpenGL, and we need OpenGL set up to load
	ships.
*/
- (id) init
{
	NSAssert(gOOPlayer == nil, @"Expected only one PlayerEntity to exist at a time.");
	return [super initBypassForPlayer];
}


- (void) deferredInit
{
	NSAssert(gOOPlayer == self, @"Expected only one PlayerEntity to exist at a time.");
	NSAssert([super initWithKey:PLAYER_SHIP_DESC definition:[NSDictionary dictionary]] == self, @"PlayerEntity requires -[ShipEntity initWithKey:definition:] to return unmodified self.");
	
	compassMode = COMPASS_MODE_BASIC;
	
	afterburnerSoundLooping = NO;
	
	isPlayer = YES;
	
	int i;
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		missile_entity[i] = nil;
	}
	[self setUpAndConfirmOK:NO];
	
	save_path = nil;
	
	[self setUpSound];
	
	scoopsActive = NO;
	
	target_memory_index = 0;
	
	dockingReport = [[NSMutableString alloc] init];
	[hud resetGuis:[NSDictionary dictionaryWithObjectsAndKeys:[NSDictionary dictionaryWithObjectsAndKeys:nil], @"message_gui",
														[NSDictionary dictionaryWithObjectsAndKeys:nil], @"comm_log_gui", nil]];
	
	[self initControls];
}


- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError
{
	return [self setUpAndConfirmOK:stopOnError saveGame:NO];
}


- (BOOL) setUpAndConfirmOK:(BOOL)stopOnError saveGame:(BOOL)saveGame
{
	unsigned i;
	Random_Seed gal_seed = {0x4a, 0x5a, 0x48, 0x02, 0x53, 0xb7};
	
	showDemoShips = NO;
	show_info_flag = NO;
	
	// Reset JavaScript.
	[OOScriptTimer noteGameReset];
	[OOScriptTimer updateTimers];
	
	GameController		*gc = [[UNIVERSE gameView] gameController];
	
	if (![gc inFullScreenMode] && stopOnError)	[gc stopAnimationTimer];	// start of critical section
	
	if (EXPECT_NOT(![[OOJavaScriptEngine sharedEngine] reset] && stopOnError)) // always (try to) reset the engine, then find out if we need to stop.
	{
		/*
			Occasionally there's a racing condition between timers being deleted
			and the js engine needing to be reset: the engine reset stops the timers
			from being deleted, and undeleted timers don't allow the engine to reset
			itself properly.
			
			If the engine can't reset, let's give ourselves an extra 20ms to allow the
			timers to delete themselves.
			
			We'll piggyback performDeadUpdates: when STATUS_DEAD, the engine waits until 
			kDeadResetTime then restarts Oolite via [UNIVERSE updateGameOver]
			The variable shot_time is used to keep track of how long ago we were
			shot.
			
			If we're loading a savegame the code will try a new JS reset immediately
			after failing this reset...
		*/
		
		// set up STATUS_DEAD
		[self setDockedStation:nil];	// needed for STATUS_DEAD
		[self setStatus:STATUS_DEAD];
		OOLog(@"script.javascript.init.error", @"Scheduling new JavaScript reset.");
		shot_time = kDeadResetTime - 0.02f;	// schedule reinit 20 milliseconds from now.
		
		if (![gc inFullScreenMode])	[gc startAnimationTimer];	// keep the game ticking over.
		return NO;
	}
	
	// end of critical section
	if (![gc inFullScreenMode] && stopOnError)	[gc startAnimationTimer];
	
	// Load locale script before any regular scripts.
	[OOJSScript jsScriptFromFileNamed:@"oolite-locale-functions.js"
						   properties:nil];
	
	[[GameController sharedController] logProgress:DESC(@"loading-scripts")];
	
	[UNIVERSE setBlockJSPlayerShipProps:NO];	// full access to player.ship properties!
	DESTROY(worldScripts);
	DESTROY(worldScriptsRequiringTickle);
	worldScripts = [[ResourceManager loadScripts] retain];
	[UNIVERSE loadConditionScripts];
	
	[[GameController sharedController] logProgress:OOExpandKeyRandomized(@"loading-miscellany")];
	
	// if there is cargo remaining from previously (e.g. a game restart), remove it
	if ([self cargoList] != nil)
	{
		[self removeAllCargo:YES];		// force removal of cargo
	}
	
	[self setShipDataKey:PLAYER_SHIP_DESC];
	ship_trade_in_factor = 95;
	
	// reset HUD & default commlog behaviour
	[UNIVERSE setAutoCommLog:YES];
	[UNIVERSE setPermanentCommLog:NO];
	
	[multiFunctionDisplayText release];
	multiFunctionDisplayText = [[NSMutableDictionary alloc] init];

	[multiFunctionDisplaySettings release];
	multiFunctionDisplaySettings = [[NSMutableArray alloc] init];

	[self switchHudTo:@"hud.plist"];	
	scanner_zoom_rate = 0.0f;
	longRangeChartMode = OOLRC_MODE_NORMAL;

	[mission_variables release];
	mission_variables = [[NSMutableDictionary alloc] init];
	
	[localVariables release];
	localVariables = [[NSMutableDictionary alloc] init];
	
	[self setScriptTarget:nil];
	[self resetMissionChoice];
	[[UNIVERSE gameView] resetTypedString];
	found_system_seed = kNilRandomSeed;
	
	[reputation release];
	reputation = [[NSMutableDictionary alloc] initWithCapacity:6];
	[reputation oo_setInteger:0 forKey:CONTRACTS_GOOD_KEY];
	[reputation oo_setInteger:0 forKey:CONTRACTS_BAD_KEY];
	[reputation oo_setInteger:MAX_CONTRACT_REP forKey:CONTRACTS_UNKNOWN_KEY];
	[reputation oo_setInteger:0 forKey:PASSAGE_GOOD_KEY];
	[reputation oo_setInteger:0 forKey:PASSAGE_BAD_KEY];
	[reputation oo_setInteger:MAX_CONTRACT_REP forKey:PASSAGE_UNKNOWN_KEY];
	[reputation oo_setInteger:0 forKey:PARCEL_GOOD_KEY];
	[reputation oo_setInteger:0 forKey:PARCEL_BAD_KEY];
	[reputation oo_setInteger:MAX_CONTRACT_REP forKey:PARCEL_UNKNOWN_KEY];
	
	roleWeights = [[NSMutableArray alloc] initWithCapacity:8];
	for (i = 0 ; i < 8 ; i++)
	{
		[roleWeights addObject:@"player-unknown"];
	}
	roleWeightFlags = [[NSMutableDictionary alloc] init];

	roleSystemList = [[NSMutableArray alloc] initWithCapacity:32];

	energy					= 256;
	weapon_temp				= 0.0f;
	forward_weapon_temp		= 0.0f;
	aft_weapon_temp			= 0.0f;
	port_weapon_temp		= 0.0f;
	starboard_weapon_temp	= 0.0f;
	lastShot = nil;
	forward_shot_time		= INITIAL_SHOT_TIME;
	aft_shot_time			= INITIAL_SHOT_TIME;
	port_shot_time			= INITIAL_SHOT_TIME;
	starboard_shot_time		= INITIAL_SHOT_TIME;
	ship_temperature		= 60.0f;
	alertFlags				= 0;
	hyperspeed_engaged		= NO;
	autopilot_engaged = NO;
	velocity = kZeroVector;
	
	flightRoll = 0.0f;
	flightPitch = 0.0f;
	flightYaw = 0.0f;

	max_passengers = 0;
	[passengers release];
	passengers = [[NSMutableArray alloc] init];
	[passenger_record release];
	passenger_record = [[NSMutableDictionary alloc] init];
	
	[contracts release];
	contracts = [[NSMutableArray alloc] init];
	[contract_record release];
	contract_record = [[NSMutableDictionary alloc] init];

	[parcels release];
	parcels = [[NSMutableArray alloc] init];
	[parcel_record release];
	parcel_record = [[NSMutableDictionary alloc] init];
	
	[missionDestinations release];
	missionDestinations = [[NSMutableDictionary alloc] init];
	
	[shipyard_record release];
	shipyard_record = [[NSMutableDictionary alloc] init];
	
	[target_memory release];
	target_memory = [[NSMutableArray alloc] initWithCapacity:PLAYER_TARGET_MEMORY_SIZE];
	[self clearTargetMemory]; // also does first-time initialisation

	[self setMissionOverlayDescriptor:nil];
	[self setMissionBackgroundDescriptor:nil];
	[self setMissionBackgroundSpecial:nil];
	[self setEquipScreenBackgroundDescriptor:nil];
	
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
#if OOLITE_ESPEAK
	voice_gender_m = YES;
	voice_no = [UNIVERSE setVoice:-1 withGenderM:voice_gender_m];
#endif
	
	[_customViews release];
	_customViews = nil;
	_customViewIndex = 0;
	
	mouse_control_on = NO;
	
	// player commander data
	// Most of this is probably also set more than once
	
	[self setCommanderName:PLAYER_DEFAULT_NAME];
	[self setLastsaveName:PLAYER_DEFAULT_NAME];
	
	galaxy_coordinates		= NSMakePoint(0x14,0xAD);	// 20,173
	galaxy_seed				= gal_seed;
	credits					= 1000;
	fuel					= PLAYER_MAX_FUEL;
	fuel_accumulator		= 0.0f;
	fuel_leak_rate			= 0.0f;
	
	galaxy_number			= 0;
	forward_weapon_type		= WEAPON_PULSE_LASER;
	aft_weapon_type			= WEAPON_NONE;
	port_weapon_type		= WEAPON_NONE;
	starboard_weapon_type	= WEAPON_NONE;
	scannerRange = (float)SCANNER_MAX_RANGE; 
	
	weapons_online			= YES;
	
	ecm_in_operation = NO;
	compassMode = COMPASS_MODE_BASIC;
	ident_engaged = NO;
	
	max_cargo				= 20; // will be reset later
	
	shipCommodityData = [[[ResourceManager dictionaryFromFilesNamed:@"commodities.plist" inFolder:@"Config" andMerge:YES] objectForKey:@"default"] retain];
	
	// set up missiles
	missiles				= PLAYER_STARTING_MISSILES;
	max_missiles			= PLAYER_STARTING_MAX_MISSILES;
	
	[eqScripts release];
	eqScripts = [[NSMutableArray alloc] init];
	primedEquipment = 0;
	[self setFastEquipmentA:@"EQ_CLOAKING_DEVICE"];
	[self setFastEquipmentB:@"EQ_ENERGY_BOMB"]; // for compatibility purposes

	[self setActiveMissile:0];
	for (i = 0; i < missiles; i++)
	{
		[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	[self safeAllMissiles];
	
	[self clearSubEntities];
	
	legalStatus				= 0;
	
	market_rnd				= 0;
	ship_kills				= 0;
	cursor_coordinates		= galaxy_coordinates;
	
	scripted_misjump		= NO;
	_scriptedMisjumpRange	= 0.5;
	scoopOverride			= NO;
	
	forward_shield			= [self maxForwardShieldLevel];
	aft_shield				= [self maxAftShieldLevel];
	
	scanClass				= CLASS_PLAYER;
	
	[UNIVERSE clearGUIs];
	
	dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_GRANTED;
	targetDockStation = nil;
	
	[self setDockedStation:[UNIVERSE station]];
	
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
	
	currentWeaponFacing		= WEAPON_FACING_FORWARD;
	[self currentWeaponStats];
	
	[save_path autorelease];
	save_path = nil;
	
	[scannedWormholes release];
	scannedWormholes = [[NSMutableArray alloc] init];
	
	[self setUpTrumbles];
	
	suppressTargetLost = NO;
	
	scoopsActive = NO;
	
	[dockingReport release];
	dockingReport = [[NSMutableString alloc] init];
	
	[shipAI release];
	shipAI = [[AI alloc] initWithStateMachine:PLAYER_DOCKING_AI_NAME andState:@"GLOBAL"];
	[self resetAutopilotAI];
	
	lastScriptAlertCondition = [self alertCondition];
	
	entity_personality = ranrot_rand() & 0x7FFF;
	
	[self setSystem_seed:[UNIVERSE findSystemAtCoords:[self galaxy_coordinates] withGalaxySeed:[self galaxy_seed]]];
	[UNIVERSE setSystemTo:[UNIVERSE findSystemAtCoords:[self galaxy_coordinates] withGalaxySeed:[self galaxy_seed]]];

	
	[self setGalacticHyperspaceBehaviourTo:[[UNIVERSE planetInfo] oo_stringForKey:@"galactic_hyperspace_behaviour" defaultValue:@"BEHAVIOUR_STANDARD"]];
	[self setGalacticHyperspaceFixedCoordsTo:[[UNIVERSE planetInfo] oo_stringForKey:@"galactic_hyperspace_fixed_coords" defaultValue:@"96 96"]];
	
	cloaking_device_active = NO;

	demoShip = nil;
	
	[[OOMusicController sharedController] justStop];
	[stickProfileScreen release];
	stickProfileScreen = [[StickProfileScreen alloc] init];
	return YES;
}


- (void) completeSetUp
{
	[self completeSetUpAndSetTarget:YES];
}


- (void) completeSetUpAndSetTarget:(BOOL)setTarget
{
	[OOSoundSource stopAll];

	[self setDockedStation:[UNIVERSE station]];
	[self setLastAegisLock:[UNIVERSE planet]];
		
	// If loading from a savegame don't reset the targetted system.
	if (setTarget) target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	
	JSContext *context = OOJSAcquireContext();
	[self doWorldScriptEvent:OOJSID("startUp") inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
	OOJSRelinquishContext(context);
}


- (void) startUpComplete
{
	JSContext *context = OOJSAcquireContext();
	[self doWorldScriptEvent:OOJSID("startUpComplete") inContext:context withArguments:NULL count:0 timeLimit:kOOJSLongTimeLimit];
	OOJSRelinquishContext(context);
}


- (BOOL) setUpShipFromDictionary:(NSDictionary *)shipDict
{
	DESTROY(compassTarget);
	[UNIVERSE setBlockJSPlayerShipProps:NO];	// full access to player.ship properties!
	
	if (![super setUpFromDictionary:shipDict]) return NO;
	
	// Player-only settings.
	//
	// set control factors..
	roll_delta =		2.0f * max_flight_roll;
	pitch_delta =		2.0f * max_flight_pitch;
	yaw_delta =			2.0f * max_flight_yaw;
	
	energy = maxEnergy;
	//if (forward_weapon_type == WEAPON_NONE) [self setWeaponDataFromType:forward_weapon_type]; 
	scannerRange = (float)SCANNER_MAX_RANGE; 
	
	[roleSet release];
	roleSet = nil;
	[self setPrimaryRole:@"player"];
	
	[self removeAllEquipment];
	[self addEquipmentFromCollection:[shipDict objectForKey:@"extra_equipment"]];

	[self resetHud];
	[hud setHidden:NO];
	
	// set up missiles
	// sanity check the number of missiles...
	if (max_missiles > PLAYER_MAX_MISSILES)  max_missiles = PLAYER_MAX_MISSILES;
	if (missiles > max_missiles)  missiles = max_missiles;
	// end sanity check

	unsigned i;
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	for (i = 0; i < missiles; i++)
	{
		missile_list[i] = [OOEquipmentType equipmentTypeWithIdentifier:@"EQ_MISSILE"];
		missile_entity[i] = [UNIVERSE newShipWithRole:@"EQ_MISSILE"];   // retain count = 1
	}
	
	DESTROY(_primaryTarget);
	[self safeAllMissiles];
	[self setActiveMissile:0];
	
	// set view offsets
	[self setDefaultViewOffsets];
	
	forwardViewOffset = [shipDict oo_vectorForKey:@"view_position_forward" defaultValue:forwardViewOffset];
	aftViewOffset = [shipDict oo_vectorForKey:@"view_position_aft" defaultValue:aftViewOffset];
	portViewOffset = [shipDict oo_vectorForKey:@"view_position_port" defaultValue:portViewOffset];
	starboardViewOffset = [shipDict oo_vectorForKey:@"view_position_starboard" defaultValue:starboardViewOffset];
	
	[self setDefaultCustomViews];
	
	NSArray *customViews = [shipDict oo_arrayForKey:@"custom_views"];
	if (customViews != nil)
	{
		[_customViews release];
		_customViews = [customViews retain];
		_customViewIndex = 0;
	}
	
	// Load js script
	[script autorelease];
	NSDictionary *scriptProperties = [NSDictionary dictionaryWithObject:self forKey:@"ship"];
	script = [OOScript jsScriptFromFileNamed:[shipDict oo_stringForKey:@"script"] 
										 properties:scriptProperties];
	if (script == nil)
	{
		// Do not switch to using a default value above; we want to use the default script if loading fails.
		script = [OOScript jsScriptFromFileNamed:@"oolite-default-player-script.js"
											 properties:scriptProperties];
	}
	[script retain];
	
	return YES;
}


- (void) dealloc
{
	DESTROY(compassTarget);
	DESTROY(hud);
	DESTROY(commLog);
	DESTROY(keyconfig_settings);
	DESTROY(target_memory);
	
	DESTROY(_fastEquipmentA);
	DESTROY(_fastEquipmentB);

	DESTROY(worldScripts);
	DESTROY(worldScriptsRequiringTickle);
	DESTROY(mission_variables);
	
	DESTROY(localVariables);
	
	DESTROY(lastTextKey);
	
	DESTROY(reputation);
	DESTROY(roleWeights);
	DESTROY(roleWeightFlags);
	DESTROY(roleSystemList);
	DESTROY(passengers);
	DESTROY(passenger_record);
	DESTROY(contracts);
	DESTROY(contract_record);
	DESTROY(parcels);
	DESTROY(parcel_record);
	DESTROY(missionDestinations);
	DESTROY(shipyard_record);
	
	DESTROY(_missionOverlayDescriptor);
	DESTROY(_missionBackgroundDescriptor);
	DESTROY(_equipScreenBackgroundDescriptor);
	
	DESTROY(_commanderName);
	DESTROY(_lastsaveName);
	DESTROY(shipCommodityData);
	
	DESTROY(specialCargo);
	
	DESTROY(save_path);
	DESTROY(scenarioKey);
	
	DESTROY(_customViews);
	
	DESTROY(dockingReport);
	
	[self destroySound];
	
	DESTROY(scannedWormholes);
	DESTROY(wormhole);
	
	int i;
	for (i = 0; i < PLAYER_MAX_MISSILES; i++)  DESTROY(missile_entity[i]);
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)  DESTROY(trumble[i]);
	
	[super dealloc];
}


- (NSUInteger) sessionID
{
	// The player ship always belongs to the current session.
	return [UNIVERSE sessionID];
} 


- (void) warnAboutHostiles
{
	[self playHostileWarning];
}


- (BOOL) canCollide
{
	switch ([self status])
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


- (NSComparisonResult) compareZeroDistance:(Entity *)otherEntity
{
	return NSOrderedDescending;  // always the most near
}


- (BOOL) validForAddToUniverse
{
	return YES;
}


- (GLfloat) lookingAtSunWithThresholdAngleCos:(GLfloat) thresholdAngleCos
{
		OOSunEntity	*sun = [UNIVERSE sun];
	GLfloat measuredCos = 999.0f, measuredCosAbs;
	GLfloat atmosphereReductionFactor = 1.0f, sunBrightness = 0.0f;
	Vector relativePosition, unitRelativePosition;
	
	if (!sun || !isSunlit)  return 0.0f;
	
	relativePosition = HPVectorToVector(HPvector_subtract([self viewpointPosition], [sun position]));
	unitRelativePosition = vector_normal_or_zbasis(relativePosition);
	switch ([UNIVERSE viewDirection])
	{
		case VIEW_FORWARD:
			measuredCos = -dot_product(unitRelativePosition, v_forward);
			break;
		case VIEW_AFT:
			measuredCos = +dot_product(unitRelativePosition, v_forward);
			break;
		case VIEW_PORT:
			measuredCos = +dot_product(unitRelativePosition, v_right);
			break;
		case VIEW_STARBOARD:
			measuredCos = -dot_product(unitRelativePosition, v_right);
			break;
		default:
			break;
	}
	measuredCosAbs = fabs(measuredCos);
	if (thresholdAngleCos <= measuredCosAbs && measuredCosAbs <= 1.0f)	// angle from viewpoint to sun <= desired threshold
	{
		sunBrightness =  (measuredCos - thresholdAngleCos) / (1.0f - thresholdAngleCos);
		if (sunBrightness < 0.0f)  sunBrightness = 0.0f;
	}
	
	if ([UNIVERSE airResistanceFactor] > 0.01)  // player is inside planetary atmosphere
	{
		atmosphereReductionFactor = OOClamp_0_1_f([self dialAltitude] * 10.0f);
	}
	
	return sunBrightness * sunBrightness * sunBrightness * atmosphereReductionFactor;
}


#ifndef NDEBUG
#define STAGE_TRACKING_BEGIN	{ \
									NSString * volatile updateStage = @"initialisation"; \
									@try {
#define STAGE_TRACKING_END			} \
									@catch (NSException *exception) \
									{ \
										OOLog(kOOLogException, @"***** Exception during [%@] in %s : %@ : %@ *****", updateStage, __PRETTY_FUNCTION__, [exception name], [exception reason]); \
										@throw exception; \
									} \
								}
#define UPDATE_STAGE(x) do { updateStage = (x); } while (0)
#else
#define STAGE_TRACKING_BEGIN	{
#define STAGE_TRACKING_END		}
#define UPDATE_STAGE(x) do { (void) (x); } while (0);
#endif


- (void) update:(OOTimeDelta)delta_t
{
	STAGE_TRACKING_BEGIN
	
	UPDATE_STAGE(@"updateMovementFlags");
	[self updateMovementFlags];
	UPDATE_STAGE(@"updateAlertCondition");
	[self updateAlertCondition];
	UPDATE_STAGE(@"updateFuelScoops:");
	[self updateFuelScoops:delta_t];
	
	UPDATE_STAGE(@"updateClocks:");
	[self updateClocks:delta_t];
	
	// scripting
	UPDATE_STAGE(@"updateTimers");
	[OOScriptTimer updateTimers];
	UPDATE_STAGE(@"checkScriptsIfAppropriate");
	[self checkScriptsIfAppropriate];
	
	// deal with collisions
	UPDATE_STAGE(@"manageCollisions");
	[self manageCollisions];
	
	UPDATE_STAGE(@"pollControls:");
	[self pollControls:delta_t];
	
	UPDATE_STAGE(@"updateTrumbles:");
	[self updateTrumbles:delta_t];
	
	OOEntityStatus status = [self status];
	if (EXPECT_NOT(status == STATUS_START_GAME && gui_screen != GUI_SCREEN_INTRO1 && gui_screen != GUI_SCREEN_INTRO2 && gui_screen != GUI_SCREEN_NEWGAME && gui_screen != GUI_SCREEN_OXZMANAGER && gui_screen != GUI_SCREEN_LOAD))
	{
		UPDATE_STAGE(@"setGuiToIntroFirstGo:");
		[self setGuiToIntroFirstGo:YES];	//set up demo mode
	}
	
	if (status == STATUS_AUTOPILOT_ENGAGED || status == STATUS_ESCAPE_SEQUENCE)
	{
		UPDATE_STAGE(@"performAutopilotUpdates:");
		[self performAutopilotUpdates:delta_t];
	}
	else  if (![self isDocked])
	{
		UPDATE_STAGE(@"performInFlightUpdates:");
		[self performInFlightUpdates:delta_t];
	}
	
	/*	NOTE: status-contingent updates are not a switch since they can
		cascade when status changes.
	*/
	if (status == STATUS_IN_FLIGHT)
	{
		UPDATE_STAGE(@"doBookkeeping:");
		[self doBookkeeping:delta_t];
	}
	if (status == STATUS_WITCHSPACE_COUNTDOWN)
	{
		UPDATE_STAGE(@"performWitchspaceCountdownUpdates:");
		[self performWitchspaceCountdownUpdates:delta_t];
	}
	if (status == STATUS_EXITING_WITCHSPACE)
	{
		UPDATE_STAGE(@"performWitchspaceExitUpdates:");
		[self performWitchspaceExitUpdates:delta_t];
	}
	if (status == STATUS_LAUNCHING)
	{
		UPDATE_STAGE(@"performLaunchingUpdates:");
		[self performLaunchingUpdates:delta_t];
	}
	if (status == STATUS_DOCKING)
	{
		UPDATE_STAGE(@"performDockingUpdates:");
		[self performDockingUpdates:delta_t];
	}
	if (status == STATUS_DEAD)
	{
		UPDATE_STAGE(@"performDeadUpdates:");
		[self performDeadUpdates:delta_t];
	}
	
	UPDATE_STAGE(@"updateWormholes");
	[self updateWormholes];
	
	STAGE_TRACKING_END
}


- (void) doBookkeeping:(double) delta_t
{
	STAGE_TRACKING_BEGIN
	
	double speed_delta = 5.0 * thrust;
	
	OOSunEntity	*sun = [UNIVERSE sun];
	double		external_temp = 0;
	GLfloat		air_friction = 0.0f;
	air_friction = 0.5f * [UNIVERSE airResistanceFactor];
	
	UPDATE_STAGE(@"updating weapon temperatures and shot times");
	// cool all weapons.
	float coolAmount = WEAPON_COOLING_FACTOR * delta_t;
	forward_weapon_temp = fdim(forward_weapon_temp, coolAmount);
	aft_weapon_temp = fdim(aft_weapon_temp, coolAmount);
	port_weapon_temp = fdim(port_weapon_temp, coolAmount);
	starboard_weapon_temp = fdim(starboard_weapon_temp, coolAmount);
	
	// update shot times.
	forward_shot_time += delta_t;
	aft_shot_time += delta_t;
	port_shot_time += delta_t;
	starboard_shot_time += delta_t;
		
	// copy new temp & shot time to main temp & shot time
	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			weapon_temp = forward_weapon_temp;
			shot_time = forward_shot_time;
			break;
		case WEAPON_FACING_AFT:
			weapon_temp = aft_weapon_temp;
			shot_time = aft_shot_time;
			break;
		case WEAPON_FACING_PORT:
			weapon_temp = port_weapon_temp;
			shot_time = port_shot_time;
			break;
		case WEAPON_FACING_STARBOARD:
			weapon_temp = starboard_weapon_temp;
			shot_time = starboard_shot_time;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}
	
	// cloaking device
	if ([self hasCloakingDevice] && cloaking_device_active)
	{
		UPDATE_STAGE(@"updating cloaking device");
		
		energy -= (float)delta_t * CLOAKING_DEVICE_ENERGY_RATE;
		if (energy < CLOAKING_DEVICE_MIN_ENERGY)
			[self deactivateCloakingDevice];
	}
	
	// military_jammer
	if ([self hasMilitaryJammer])
	{
		UPDATE_STAGE(@"updating military jammer");
		
		if (military_jammer_active)
		{
			energy -= (float)delta_t * MILITARY_JAMMER_ENERGY_RATE;
			if (energy < MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = NO;
		}
		else
		{
			if (energy > 1.5 * MILITARY_JAMMER_MIN_ENERGY)
				military_jammer_active = YES;
		}
	}
	
	// ecm
	if (ecm_in_operation)
	{
		UPDATE_STAGE(@"updating ECM");
		
		if (energy > 0.0)
			energy -= (float)(ECM_ENERGY_DRAIN_FACTOR * delta_t);		// drain energy because of the ECM
		else
		{
			ecm_in_operation = NO;
			[UNIVERSE addMessage:DESC(@"ecm-out-of-juice") forCount:3.0];
		}
		if ([UNIVERSE getTime] > ecm_start_time + ECM_DURATION)
		{
			ecm_in_operation = NO;
		}
	}
	
	// Energy Banks and Shields
	
	/* Shield-charging behaviour, as per Eric's proposal:
	   1. If shields are less than a threshold, recharge with all available energy
	   2. If energy banks are below threshold, recharge with generated energy
	   3. Charge shields with any surplus energy
	*/
	UPDATE_STAGE(@"updating energy and shield charges");
	
	// 1. (Over)charge energy banks (will get normalised later)
	energy += [self energyRechargeRate] * delta_t;
	
	// 2. Calculate shield recharge rates
	float fwdMax = [self maxForwardShieldLevel];
	float aftMax = [self maxAftShieldLevel];
	float shieldRecharge = [self shieldRechargeRate] * delta_t;
	float rechargeFwd = MIN(shieldRecharge, fwdMax - forward_shield);
	float rechargeAft = MIN(shieldRecharge, aftMax - aft_shield);
	
	// Note: we've simplified this a little, so if either shield is below
	//       the critical threshold, we allocate all energy.  Ideally we
	//       would only allocate the full recharge to the critical shield,
	//       but doing so would add another few levels of if-then below.
	float energyForShields = energy;
	if( (forward_shield > fwdMax * 0.25) && (aft_shield > aftMax * 0.25) )
	{
		// TODO: Can this be cached anywhere sensibly (without adding another member variable)?
		float minEnergyBankLevel = [[UNIVERSE planetInfo] oo_floatForKey:@"shield_charge_energybank_threshold" defaultValue:0.25];
		energyForShields = MAX(0.0, energy -0.1 - (maxEnergy * minEnergyBankLevel)); // NB: The - 0.1 ensures the energy value does not 'bounce' across the critical energy message and causes spurious energy-low warnings
	}
	
	if( forward_shield < aft_shield )
	{
		rechargeFwd = MIN(rechargeFwd, energyForShields);
		rechargeAft = MIN(rechargeAft, energyForShields - rechargeFwd);
	}
	else
	{
		rechargeAft = MIN(rechargeAft, energyForShields);
		rechargeFwd = MIN(rechargeFwd, energyForShields - rechargeAft);
	}
	
	// 3. Recharge shields, drain banks, and clamp values
	forward_shield += rechargeFwd;
	aft_shield += rechargeAft;
	energy -= rechargeFwd + rechargeAft;
	
	forward_shield = OOClamp_0_max_f(forward_shield, fwdMax);
	aft_shield = OOClamp_0_max_f(aft_shield, aftMax);
	energy = OOClamp_0_max_f(energy, maxEnergy);
	
	if (sun)
	{
		UPDATE_STAGE(@"updating sun effects");
		
		// set the ambient temperature here
		double  sun_zd = sun->zero_distance;	// square of distance
		double  sun_cr = sun->collision_radius;
		double	alt1 = sun_cr * sun_cr / sun_zd;
		external_temp = SUN_TEMPERATURE * alt1;
		if ([sun goneNova])
			external_temp *= 100;
		// fuel scooping during the nova mission very unlikely
		if ([sun willGoNova])
			external_temp *= 3;
			
		// do Revised sun-skimming check here...
		if ([self hasScoop] && alt1 > 0.75 && [self fuel] < [self fuelCapacity])
		{
			fuel_accumulator += (float)(delta_t * flightSpeed * 0.010 / [self fuelChargeRate]);
			// are we fast enough to collect any fuel?
			scoopsActive = YES && flightSpeed > 0.1f;
			while (fuel_accumulator > 1.0f)
			{
				[self setFuel:[self fuel] + 1];
				fuel_accumulator -= 1.0f;
				[self doScriptEvent:OOJSID("shipScoopedFuel")];
			}
			[UNIVERSE displayCountdownMessage:DESC(@"fuel-scoop-active") forCount:1.0];
		}
	}
	
	//Bug #11692 CmdrJames added Status entering witchspace
	OOEntityStatus status = [self status];
	if ((status != STATUS_ESCAPE_SEQUENCE) && (status != STATUS_ENTERING_WITCHSPACE))
	{
		UPDATE_STAGE(@"updating cabin temperature");
		
		// work on the cabin temperature
		float heatInsulation = [self heatInsulation]; // Optimisation, suggested by EricW
		float deltaInsulation = delta_t/heatInsulation;
		float heatThreshold = heatInsulation * 100.0f;
		ship_temperature += (float)( flightSpeed * air_friction * deltaInsulation);	// wind_speed
		
		if (external_temp > heatThreshold && external_temp > ship_temperature)
			ship_temperature += (float)((external_temp - ship_temperature) * SHIP_INSULATION_FACTOR  * deltaInsulation);
		else
		{
			if (ship_temperature > SHIP_MIN_CABIN_TEMP)
				ship_temperature += (float)((external_temp - heatThreshold - ship_temperature) * SHIP_COOLING_FACTOR  * deltaInsulation);
		}
		
		if (ship_temperature > SHIP_MAX_CABIN_TEMP)
			[self takeHeatDamage: delta_t * ship_temperature];
	}
	
	if ((status == STATUS_ESCAPE_SEQUENCE)&&(shot_time > ESCAPE_SEQUENCE_TIME))
	{
		UPDATE_STAGE(@"resetting after escape");
		ShipEntity	*doppelganger = (ShipEntity*)[self foundTarget];
		// reset legal status again! Could have changed if a previously launched missile hit a clean NPC while in the escape pod.
		[self setBounty:0 withReason:kOOLegalStatusReasonEscapePod];
		bounty = 0;
		thrust = max_thrust; // re-enable inertialess drives
		// no access to all player.ship properties while inside the escape pod,
		// we're not supposed to be inside our ship anymore! 
		[self doScriptEvent:OOJSID("escapePodSequenceOver")];	// allow oxps to override the escape pod target
		if (!equal_seeds(target_system_seed, system_seed)) // overridden: we're going to a nearby system!
		{
			system_seed = target_system_seed;
			[UNIVERSE setSystemTo:system_seed];
			galaxy_coordinates.x = system_seed.d;
			galaxy_coordinates.y = system_seed.b;
			
			[UNIVERSE setUpSpace];
			// run initial system population
			[UNIVERSE populateNormalSpace];

			[self setDockTarget:[UNIVERSE station]];
			// send world script events to let oxps know we're in a new system.
			// all player.ship properties are still disabled at this stage.
			[UNIVERSE setWitchspaceBreakPattern:YES];
			[self doScriptEvent:OOJSID("shipWillExitWitchspace")];
			[self doScriptEvent:OOJSID("shipExitedWitchspace")];
			
			[[UNIVERSE planet] update: 2.34375 * market_rnd];	// from 0..10 minutes
			[[UNIVERSE station] update: 2.34375 * market_rnd];	// from 0..10 minutes
		}
		
		Entity	*dockTargetEntity = [UNIVERSE entityForUniversalID:_dockTarget];	// main station in the original system, unless overridden.
		if ([dockTargetEntity isStation]) // fails if _dockTarget is NO_TARGET
		{
			[doppelganger becomeExplosion];	// blow up the doppelganger
			// restore player ship
			ShipEntity *player_ship = [UNIVERSE newShipWithName:[self shipDataKey]];	// retained
			if (player_ship)
			{
				// FIXME: this should use OOShipType, which should exist. -- Ahruman
				[self setMesh:[player_ship mesh]];
				[player_ship release];						// we only wanted it for its polygons!
			}
			[UNIVERSE setViewDirection:VIEW_FORWARD];
			[UNIVERSE setBlockJSPlayerShipProps:NO];	// re-enable player.ship!
			[self enterDock:(StationEntity *)dockTargetEntity];
		}
		else	// no dock target? dock target is not a station? game over!
		{
			[self setStatus:STATUS_DEAD];
			//[self playGameOver];	// no death explosion sounds for player pods
			// no shipDied events for player pods, either
			[UNIVERSE displayMessage:DESC(@"gameoverscreen-escape-pod") forCount:kDeadResetTime];
			[UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
			[self showGameOver];
		}
	}
	
	
	// MOVED THE FOLLOWING FROM PLAYERENTITY POLLFLIGHTCONTROLS:
	travelling_at_hyperspeed = (flightSpeed > maxFlightSpeed);
	if (hyperspeed_engaged)
	{
		UPDATE_STAGE(@"updating hyperspeed");
		
		// increase speed up to maximum hyperspeed
		if (flightSpeed < maxFlightSpeed * HYPERSPEED_FACTOR)
			flightSpeed += (float)(speed_delta * delta_t * HYPERSPEED_FACTOR);
		if (flightSpeed > maxFlightSpeed * HYPERSPEED_FACTOR)
			flightSpeed = (float)(maxFlightSpeed * HYPERSPEED_FACTOR);
		
		// check for mass lock
		hyperspeed_locked = [self massLocked];
		// check for mass lock & external temperature?
		//hyperspeed_locked = flightSpeed * air_friction > 40.0f+(ship_temperature - external_temp ) * SHIP_COOLING_FACTOR || [self massLocked];
		
		if (hyperspeed_locked)
		{
			[self playJumpMassLocked];
			[UNIVERSE addMessage:DESC(@"jump-mass-locked") forCount:4.5];
			hyperspeed_engaged = NO;
		}
	}
	else
	{
		if (afterburner_engaged)
		{
			UPDATE_STAGE(@"updating afterburner");
			
			float abFactor = [self afterburnerFactor];
			float maxInjectionSpeed = maxFlightSpeed * abFactor;
			if (flightSpeed > maxInjectionSpeed)
			{
				// decellerate to maxInjectionSpeed but slower than without afterburner.
				flightSpeed -= (float)(speed_delta * delta_t * abFactor);
			}
			else
			{
				if (flightSpeed < maxInjectionSpeed)
					flightSpeed += (float)(speed_delta * delta_t * abFactor);
				if (flightSpeed > maxInjectionSpeed)
					flightSpeed = maxInjectionSpeed;
			}
			fuel_accumulator -= (float)(delta_t * AFTERBURNER_BURNRATE);
			while ((fuel_accumulator < 0)&&(fuel > 0))
			{
				fuel_accumulator += 1.0f;
				if (--fuel <= MIN_FUEL)
					afterburner_engaged = NO;
			}
		}
		else
		{
			UPDATE_STAGE(@"slowing from hyperspeed");
			
			// slow back down...
			if (travelling_at_hyperspeed)
			{
				// decrease speed to maximum normal speed
				flightSpeed -= (float)(speed_delta * delta_t * HYPERSPEED_FACTOR);
				if (flightSpeed < maxFlightSpeed)
					flightSpeed = maxFlightSpeed;
			}
		}
	}
	
	
	
	// fuel leakage
	if ((fuel_leak_rate > 0.0)&&(fuel > 0))
	{
		UPDATE_STAGE(@"updating fuel leakage");
		
		fuel_accumulator -= (float)(fuel_leak_rate * delta_t);
		while ((fuel_accumulator < 0)&&(fuel > 0))
		{
			fuel_accumulator += 1.0f;
			fuel--;
		}
		if (fuel == 0)
			fuel_leak_rate = 0;
	}
	
	// smart_zoom
	UPDATE_STAGE(@"updating scanner zoom");
	if (scanner_zoom_rate)
	{
		double z = [hud scannerZoom];
		double z1 = z + scanner_zoom_rate * delta_t;
		if (scanner_zoom_rate > 0.0)
		{
			if (floor(z1) > floor(z))
			{
				z1 = floor(z1);
				scanner_zoom_rate = 0.0f;
			}
		}
		else
		{
			if (z1 < 1.0)
			{
				z1 = 1.0;
				scanner_zoom_rate = 0.0f;
			}
		}
		[hud setScannerZoom:z1];
	}
	
	// scanner sanity check - lose any targets further than maximum scanner range
	ShipEntity *primeTarget = [self primaryTarget];
	if (primeTarget && HPdistance2([primeTarget position], [self position]) > SCANNER_MAX_RANGE2 && !autopilot_engaged)
	{
		[UNIVERSE addMessage:DESC(@"target-lost") forCount:3.0];
		[self removeTarget:primeTarget];
	}
	// compass sanity check and update target for changed mode
	[self validateCompassTarget];
	
	// update subentities
	UPDATE_STAGE(@"updating subentities");
	totalBoundingBox = boundingBox; //	reset totalBoundingBox
	ShipEntity *se = nil;
	foreach (se, [self subEntities])
	{
		[se update:delta_t];
		if ([se isShip])
		{
			BoundingBox sebb = [se findSubentityBoundingBox];
			bounding_box_add_vector(&totalBoundingBox, sebb.max);
			bounding_box_add_vector(&totalBoundingBox, sebb.min);
		}
	}
	// and one thing which isn't a subentity. Fixes bug with
	// mispositioned laser beams particularly noticeable on side view.
	if (lastShot != nil)
	{
		[lastShot update:0.0];
		lastShot = nil;
	}
	
	STAGE_TRACKING_END
}


- (void) updateMovementFlags{
	hasMoved = !HPvector_equal(position, lastPosition);
	hasRotated = !quaternion_equal(orientation, lastOrientation);
	lastPosition = position;
	lastOrientation = orientation;
}


- (void) updateAlertCondition
{
	/*	TODO: update alert condition once per frame. Tried this before, but
		there turned out to be complications. See mailing list archive.
		-- Ahruman 20070802
	 */
	OOAlertCondition cond = [self alertCondition];
	OOTimeAbsolute t = [UNIVERSE getTime];
	if (cond != lastScriptAlertCondition)
	{
		ShipScriptEventNoCx(self, "alertConditionChanged", INT_TO_JSVAL(cond), INT_TO_JSVAL(lastScriptAlertCondition));
		lastScriptAlertCondition = cond;
	}
	/* Update heuristic assessment of whether player is fleeing */
	if (cond == ALERT_CONDITION_DOCKED || cond == ALERT_CONDITION_GREEN || (cond == ALERT_CONDITION_YELLOW && energy == maxEnergy))
	{
		fleeing_status = PLAYER_FLEEING_NONE;
	}
	else if (fleeing_status == PLAYER_FLEEING_UNLIKELY && (energy > maxEnergy*0.6 || cond != ALERT_CONDITION_RED))
	{
		fleeing_status = PLAYER_FLEEING_NONE;
	}
	else if ((fleeing_status == PLAYER_FLEEING_MAYBE || fleeing_status == PLAYER_FLEEING_UNLIKELY) && cargo_dump_time > last_shot_time)
	{
		fleeing_status = PLAYER_FLEEING_CARGO;
	}
	else if (fleeing_status == PLAYER_FLEEING_MAYBE && last_shot_time + 10 > t)
	{
		fleeing_status = PLAYER_FLEEING_NONE;
	}
	else if (fleeing_status == PLAYER_FLEEING_LIKELY && last_shot_time + 10 > t)
	{
		fleeing_status = PLAYER_FLEEING_UNLIKELY;
	}
	else if (fleeing_status == PLAYER_FLEEING_NONE && cond == ALERT_CONDITION_RED && last_shot_time + 10 < t && flightSpeed > 0.75*maxFlightSpeed)
	{
		fleeing_status = PLAYER_FLEEING_MAYBE;
	}
	else if ((fleeing_status == PLAYER_FLEEING_MAYBE || fleeing_status == PLAYER_FLEEING_CARGO) && cond == ALERT_CONDITION_RED && last_shot_time + 10 < t && flightSpeed > 0.75*maxFlightSpeed && energy < maxEnergy * 0.5 && (forward_shield < [self maxForwardShieldLevel]*0.25 || aft_shield < [self maxAftShieldLevel]*0.25))
	{
		fleeing_status = PLAYER_FLEEING_LIKELY;
	}
}


- (void) updateFuelScoops:(OOTimeDelta)delta_t
{
	if (scoopsActive)
	{
		[self updateFuelScoopSoundWithInterval:delta_t];
		if (![self scoopOverride])
		{
			scoopsActive = NO;
			[self updateFuelScoopSoundWithInterval:delta_t];
		}
	}
}


- (void) updateClocks:(OOTimeDelta)delta_t
{
	// shot time updates are still needed here for STATUS_DEAD!
	shot_time += delta_t;
	script_time += delta_t;
	unsigned prev_day = floor(ship_clock / 86400);
	ship_clock += delta_t;
	if (ship_clock_adjust > 0.0)				// adjust for coming out of warp (add LY * LY hrs)
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
	else 
		ship_clock_adjust = 0.0;
	
	unsigned now_day = floor(ship_clock / 86400.0);
	while (prev_day < now_day)
	{
		prev_day++;
		[self doScriptEvent:OOJSID("dayChanged") withArgument:[NSNumber numberWithUnsignedInt:prev_day]];
		// not impossible that at ultra-low frame rates two of these will
		// happen in a single update.
	}

	//fps
	if (ship_clock > fps_check_time)
	{
		if (![self clockAdjusting])
		{
			fps_counter = (int)([UNIVERSE timeAccelerationFactor] * floor([UNIVERSE framesDoneThisUpdate] / (fps_check_time - last_fps_check_time)));
			last_fps_check_time = fps_check_time;
			fps_check_time = ship_clock + MINIMUM_GAME_TICK;
		}
		else
		{
			// Good approximation for when the clock is adjusting and proper fps calculation
			// cannot be performed.
			fps_counter = (int)([UNIVERSE timeAccelerationFactor] * floor(1.0 / delta_t));
			fps_check_time = ship_clock + MINIMUM_GAME_TICK;
		}
		[UNIVERSE resetFramesDoneThisUpdate];	// Reset frame counter
	}
}


- (void) checkScriptsIfAppropriate
{
	if (script_time <= script_time_check)  return;
	
	if ([self status] != STATUS_IN_FLIGHT)
	{
		switch (gui_screen)
		{
			// Screens where no world script tickles are performed
			case GUI_SCREEN_MAIN:
			case GUI_SCREEN_INTRO1:
			case GUI_SCREEN_INTRO2:
			case GUI_SCREEN_NEWGAME:
			case GUI_SCREEN_OXZMANAGER:
			case GUI_SCREEN_MARKET:
			case GUI_SCREEN_OPTIONS:
			case GUI_SCREEN_GAMEOPTIONS:
			case GUI_SCREEN_LOAD:
			case GUI_SCREEN_SAVE:
			case GUI_SCREEN_SAVE_OVERWRITE:
			case GUI_SCREEN_STICKMAPPER:
			case GUI_SCREEN_STICKPROFILE:
			case GUI_SCREEN_MISSION:
			case GUI_SCREEN_REPORT:
				return;
				break;
			
			// Screens from which it's safe to jump to the mission screen
//			case GUI_SCREEN_CONTRACTS:
			case GUI_SCREEN_EQUIP_SHIP:
			case GUI_SCREEN_INTERFACES:
			case GUI_SCREEN_LONG_RANGE_CHART:
			case GUI_SCREEN_MANIFEST:
			case GUI_SCREEN_SHIPYARD:
			case GUI_SCREEN_SHORT_RANGE_CHART:
			case GUI_SCREEN_STATUS:
			case GUI_SCREEN_SYSTEM_DATA:
				// Test passed, we can run scripts. Nothing to do here.
				break;
		}
	}
	
	// Test either passed or never ran, run scripts.
	[self checkScript];
	script_time_check += script_time_interval;
}


- (void) updateTrumbles:(OOTimeDelta)delta_t
{
	OOTrumble	**trumbles = [self trumbleArray];
	NSUInteger	i;
	
	for (i = [self trumbleCount] ; i > 0; i--)
	{
		OOTrumble* trum = trumbles[i - 1];
		[trum updateTrumble:delta_t];
	}
}


- (void) performAutopilotUpdates:(OOTimeDelta)delta_t
{
	[self processBehaviour:delta_t];
	[self applyVelocity:delta_t];
	[self doBookkeeping:delta_t];
}


- (BOOL) engageAutopilotToStation:(StationEntity *)stationForDocking
{
	if (stationForDocking == nil)   return NO;
	if ([self isDocked])  return NO;
	
	if (autopilot_engaged && [self targetStation] == stationForDocking)
	{	
		return YES;
	}
		
	[self setTargetStation:stationForDocking];
	DESTROY(_primaryTarget);
	autopilot_engaged = YES;
	ident_engaged = NO;
	[self safeAllMissiles];
	velocity = kZeroVector;
	[self setStatus:STATUS_AUTOPILOT_ENGAGED];
	[self resetAutopilotAI];
	[shipAI setState:@"BEGIN_DOCKING"];	// reboot the AI
	[self playAutopilotOn];
	[self doScriptEvent:OOJSID("playerStartedAutoPilot") withArgument:stationForDocking];
	[self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
	[[OOMusicController sharedController] playDockingMusic];
		
	if (afterburner_engaged)
	{
		afterburner_engaged = NO;
		if (afterburnerSoundLooping)  [self stopAfterburnerSound];
	}
	return YES;
}



- (void) disengageAutopilot
{
	if (autopilot_engaged)
	{
		[self abortDocking];			// let the station know that you are no longer on approach
		behaviour = BEHAVIOUR_IDLE;
		frustration = 0.0;
		autopilot_engaged = NO;
		DESTROY(_primaryTarget);
		[self setTargetStation:nil];
		[self setStatus:STATUS_IN_FLIGHT];
		[self playAutopilotOff];
		[self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		[[OOMusicController sharedController] stopDockingMusic];
		[self doScriptEvent:OOJSID("playerCancelledAutoPilot")];
		
		[self resetAutopilotAI];
	}
}


- (void) resetAutopilotAI
{
	AI *myAI = [self getAI];
	// JSAI: will need changing if oolite-dockingAI.js written
	if (![[myAI name] isEqualToString:PLAYER_DOCKING_AI_NAME])
	{
		[self setAITo:PLAYER_DOCKING_AI_NAME ];
	}
	[myAI clearAllData];
	[myAI setState:@"GLOBAL"];
	[myAI setNextThinkTime:[UNIVERSE getTime] + 2];
	[myAI setOwner:self];
}


#define VELOCITY_CLEANUP_MIN	2000.0f	// Minimum speed for "power braking".
#define VELOCITY_CLEANUP_FULL	5000.0f	// Speed at which full "power braking" factor is used.
#define VELOCITY_CLEANUP_RATE	0.001f	// Factor for full "power braking".


- (void) performInFlightUpdates:(OOTimeDelta)delta_t
{
	STAGE_TRACKING_BEGIN
	
	// do flight routines
	//// velocity stuff
	UPDATE_STAGE(@"applying newtonian drift");
	assert(VELOCITY_CLEANUP_FULL > VELOCITY_CLEANUP_MIN);
	
	[self applyVelocity:delta_t];
	
	GLfloat thrust_factor = 1.0;
	if (flightSpeed > maxFlightSpeed)
	{
		if (afterburner_engaged)
		{
			thrust_factor = [self afterburnerFactor];
		}
		else
		{
			thrust_factor = HYPERSPEED_FACTOR;
		}
	}
	

	GLfloat velmag = magnitude(velocity);
	GLfloat velmag2 = velmag - (float)delta_t * thrust * thrust_factor;
	if (velmag > 0)
	{
		UPDATE_STAGE(@"applying power braking");
		
		if (velmag > VELOCITY_CLEANUP_MIN)
		{
			GLfloat rate;
			// Fix up extremely ridiculous speeds that can happen in collisions or explosions
			if (velmag > VELOCITY_CLEANUP_FULL)  rate = VELOCITY_CLEANUP_RATE;
			else  rate = (velmag - VELOCITY_CLEANUP_MIN) / (VELOCITY_CLEANUP_FULL - VELOCITY_CLEANUP_MIN) * VELOCITY_CLEANUP_RATE;
			velmag2 -= velmag * rate;
		}
		if (velmag2 < 0.0f)  velocity = kZeroVector;
		else  velocity = vector_multiply_scalar(velocity, velmag2 / velmag);
		
	}
	
	UPDATE_STAGE(@"updating joystick");
	[self applyRoll:(float)delta_t*flightRoll andClimb:(float)delta_t*flightPitch];
	if (flightYaw != 0.0)
	{
		[self applyYaw:(float)delta_t*flightYaw];
	}
	
	UPDATE_STAGE(@"applying para-newtonian thrust");
	[self moveForward:delta_t*flightSpeed];
	
	UPDATE_STAGE(@"updating targeting");
	[self updateTargeting];
	
	STAGE_TRACKING_END
}


- (void) performWitchspaceCountdownUpdates:(OOTimeDelta)delta_t
{
	STAGE_TRACKING_BEGIN
	
	UPDATE_STAGE(@"doing bookkeeping");
	[self doBookkeeping:delta_t];
	
	UPDATE_STAGE(@"updating countdown timer");
	witchspaceCountdown = fdim(witchspaceCountdown, delta_t);
	
	// damaged gal drive? abort!
	if (EXPECT_NOT(galactic_witchjump && ![self hasEquipmentItem:@"EQ_GAL_DRIVE"]))
	{
		galactic_witchjump = NO;
		[self setStatus:STATUS_IN_FLIGHT];
		[self playHyperspaceAborted];
		ShipScriptEventNoCx(self, "playerJumpFailed", OOJSSTR("malfunction"));
		return;
	}
	
	if (galactic_witchjump)
	{
		[UNIVERSE displayCountdownMessage:[NSString stringWithFormat:DESC(@"witch-galactic-in-f-seconds"), witchspaceCountdown] forCount:1.0];
	}
	else
	{
		[UNIVERSE displayCountdownMessage:[NSString stringWithFormat:DESC(@"witch-to-@-in-f-seconds"), [UNIVERSE getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
	}
	
	if (witchspaceCountdown == 0.0)
	{
		UPDATE_STAGE(@"preloading planet textures");
		if (!galactic_witchjump)
		{
			/*	Note: planet texture preloading is done twice for hyperspace jumps:
				once when starting the countdown and once at the beginning of the
				jump. The reason is that the preloading may have been skipped the
				first time because of rate limiting (see notes at
				-preloadPlanetTexturesForSystem:). There is no significant overhead
				from doing it twice thanks to the texture cache.
				-- Ahruman 2009-12-19
			*/
			[UNIVERSE preloadPlanetTexturesForSystem:target_system_seed];
		}
		else
		{
			// FIXME: preload target system for galactic jump?
		}

		UPDATE_STAGE(@"JUMP!");
		if (galactic_witchjump)  [self enterGalacticWitchspace];
		else  [self enterWitchspace];
		galactic_witchjump = NO;
	}
	
	STAGE_TRACKING_END
}


- (void) performWitchspaceExitUpdates:(OOTimeDelta)delta_t
{
	if ([UNIVERSE breakPatternOver])
	{
		[self resetExhaustPlumes];
		// time to check the script!
		[self checkScript];
		// next check in 10s
		[self resetScriptTimer];	// reset the in-system timer
		
		// announce arrival
		if ([UNIVERSE planet])
		{
			[UNIVERSE addMessage:[NSString stringWithFormat:@" %@. ",[UNIVERSE getSystemName:system_seed]] forCount:3.0];
			// and reset the compass
			if ([self hasEquipmentItem:@"EQ_ADVANCED_COMPASS"])
				compassMode = COMPASS_MODE_PLANET;
			else
				compassMode = COMPASS_MODE_BASIC;
		}
		else
		{
			if ([UNIVERSE inInterstellarSpace])  [UNIVERSE addMessage:DESC(@"witch-engine-malfunction") forCount:3.0]; // if sun gone nova, print nothing
		}
		
		[self setStatus:STATUS_IN_FLIGHT];
		
		// If we are exiting witchspace after a scripted misjump. then make sure it gets reset now.
		// Scripted misjump situations should have a lifespan of one jump only, to keep things
		// simple - Nikos 20090728
		if ([self scriptedMisjump])  [self setScriptedMisjump:NO];
		// similarly reset the misjump range to the traditional 0.5
		[self setScriptedMisjumpRange:0.5];

		[self doScriptEvent:OOJSID("shipExitedWitchspace")];

		[self doBookkeeping:delta_t]; // arrival frame updates

		suppressAegisMessages=NO;
	}
}


- (void) performLaunchingUpdates:(OOTimeDelta)delta_t
{
	if (![UNIVERSE breakPatternHide])
	{
		flightRoll = launchRoll;	// synchronise player's & launching station's spins.
		[self doBookkeeping:delta_t];	// don't show ghost exhaust plumes from previous docking!
	}
	
	if ([UNIVERSE breakPatternOver])
	{
		// time to check the legacy scripts!
		[self checkScript];
		// next check in 10s
		
		[self setStatus:STATUS_IN_FLIGHT];

		[self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		StationEntity *stationLaunchedFrom = [UNIVERSE nearestEntityMatchingPredicate:IsStationPredicate parameter:NULL relativeToEntity:self];
		[self doScriptEvent:OOJSID("shipLaunchedFromStation") withArgument:stationLaunchedFrom];
	}
}


- (void) performDockingUpdates:(OOTimeDelta)delta_t
{
	if ([UNIVERSE breakPatternOver])
	{
		[self docked];		// bookkeeping for docking
	}
}


- (void) performDeadUpdates:(OOTimeDelta)delta_t
{
	if ([self shotTime] > kDeadResetTime)
	{
		BOOL was_mouse_control_on = mouse_control_on;
		[UNIVERSE handleGameOver];				//  we restart the UNIVERSE
		mouse_control_on = was_mouse_control_on;
	}
}


// Target is valid if it's within Scanner range, AND
// Target is a ship AND is not cloaked or jamming, OR
// Target is a wormhole AND player has the Wormhole Scanner
- (BOOL)isValidTarget:(Entity*)target
{
	// Just in case we got called with a bad target.
	if (!target)
		return NO;

	// If target is beyond scanner range, it's lost
	if(target->zero_distance > SCANNER_MAX_RANGE2)
		return NO;

	// If target is a ship, check whether it's cloaked or is actively jamming our scanner
	if ([target isShip])
	{
		ShipEntity *targetShip = (ShipEntity*)target;
		if ([targetShip isCloaked] ||	// checks for cloaked ships
			([targetShip isJammingScanning] && ![self hasMilitaryScannerFilter]))	// checks for activated jammer
		{
			return NO;
		}
		OOEntityStatus tstatus = [targetShip status];
		if (tstatus == STATUS_ENTERING_WITCHSPACE || tstatus == STATUS_IN_HOLD || tstatus == STATUS_DOCKED)
		{ // checks for ships entering wormholes, docking, or been scooped
			return NO;
		}
		return YES;
	}

	// If target is an unexpired wormhole and the player has bought the Wormhole Scanner and we're in ID mode
	if ([target isWormhole] && [target scanClass] != CLASS_NO_DRAW && 
		[self hasEquipmentItem:@"EQ_WORMHOLE_SCANNER"] && ident_engaged)
	{
		return YES;
	}
	
	// Target is neither a wormhole nor a ship
	return NO;
}


- (void) showGameOver
{
	[hud resetGuis:[NSDictionary dictionaryWithObject:[NSDictionary dictionary] forKey:@"message_gui"]];
	NSString *scoreMS = [NSString stringWithFormat:OOExpandKey(@"gameoverscreen-score-@"),
							KillCountToRatingAndKillString(ship_kills)];
	
	[UNIVERSE displayMessage:OOExpandKey(@"gameoverscreen-game-over") forCount:kDeadResetTime];
	[UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
	[UNIVERSE displayMessage:scoreMS forCount:kDeadResetTime];
	[UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
	[UNIVERSE displayMessage:OOExpandKey(@"gameoverscreen-press-space") forCount:kDeadResetTime];
	[UNIVERSE displayMessage:@" " forCount:kDeadResetTime];
	[UNIVERSE displayMessage:@"" forCount:kDeadResetTime];
	[self resetShotTime];
}


- (void) showShipModelWithKey:(NSString *)shipKey shipData:(NSDictionary *)shipData personality:(uint16_t)personality factorX:(GLfloat)factorX factorY:(GLfloat)factorY factorZ:(GLfloat)factorZ inContext:(NSString *)context
{
	if (shipKey == nil)  return;
	if (shipData == nil)  shipData = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
	if (shipData == nil)  return;
	
	// Correct the position of the displayed model in the status screen when viewed in non-4/3 resolutions. Other screens displaying
	// demoship models remain unaltered - Nikos 20140129
	NSSize screenSize = [[UNIVERSE gameView] viewSize];
	GLfloat screenSizeCorrectionFactor = 1.0f;
	if ([context isEqualToString:@"GUI_SCREEN_STATUS"])
	{
		screenSizeCorrectionFactor = screenSize.height <= screenSize.width ?
										screenSize.height / screenSize.width * (4.0f/3.0f) :
										screenSize.height / screenSize.width * (3.0f/4.0f);
	}
	
	Quaternion		q2 = { (GLfloat)M_SQRT1_2, (GLfloat)M_SQRT1_2, (GLfloat)0.0f, (GLfloat)0.0f };
	// MKW - retrieve last demo ships' orientation and release it
	if( demoShip != nil )
	{
		q2 = [demoShip orientation];
		[demoShip release];
	}
	
	ShipEntity *ship = [[ProxyPlayerEntity alloc] initWithKey:shipKey definition:shipData];
	if (personality != ENTITY_PERSONALITY_INVALID)  [ship setEntityPersonalityInt:personality];
	
	[ship wasAddedToUniverse];
	
	if (context)  OOLog(@"script.debug.note.showShipModel", @"::::: showShipModel:'%@' in context: %@.", [ship name], context);
	
	GLfloat cr = [ship collisionRadius];
	[ship setOrientation: q2];
	[ship setPositionX:factorX * cr * screenSizeCorrectionFactor y:factorY * cr * screenSizeCorrectionFactor z:factorZ * cr];
	[ship setScanClass: CLASS_NO_DRAW];
	[ship setRoll: M_PI/10.0];
	[ship setPitch: M_PI/25.0];
	if([ship pendingEscortCount] > 0) [ship setPendingEscortCount:0];
	[ship setAITo: @"nullAI.plist"];
	id subEntStatus = [shipData objectForKey:@"subentities_status"];
	// show missing subentities if there's a subentities_status key
	if (subEntStatus != nil) [ship deserializeShipSubEntitiesFrom:(NSString *)subEntStatus];
	[UNIVERSE addEntity: ship];
	// MKW - save demo ship for its rotation
	demoShip = [ship retain];
	
	[ship setStatus: STATUS_COCKPIT_DISPLAY];
	
	[ship release];
}


// Game options and status screens (for now) may require an immediate window redraw after
// said window has been resized. This method must be called after such resize events, including
// toggle to/from full screen - Nikos 20140129
- (void) doGuiScreenResizeUpdates
{
	switch ([self guiScreen])
	{
		case GUI_SCREEN_GAMEOPTIONS:
			//refresh play windowed / full screen
			[self setGuiToGameOptionsScreen];
			break;
		case GUI_SCREEN_STATUS:
			// status screen must be redone in order to possibly
			// refresh displayed model's draw position
			[self setGuiToStatusScreen];
			break;
		default:
			break;
	}
}


// Check for lost targeting - both on the ships' main target as well as each
// missile.
// If we're actively scanning and we don't have a current target, then check
// to see if we've locked onto a new target.
// Finally, if we have a target and it's a wormhole, check whether we have more
// information
- (void) updateTargeting
{
	STAGE_TRACKING_BEGIN
	
	// check for lost ident target and ensure the ident system is actually scanning
	UPDATE_STAGE(@"checking ident target");
	if (ident_engaged && [self primaryTarget] != nil)
	{
		if (![self isValidTarget:[self primaryTarget]])
		{
			if (!suppressTargetLost)
			{
				[UNIVERSE addMessage:DESC(@"target-lost") forCount:3.0];
				[self playTargetLost];
				[self noteLostTarget];
			}
			else
			{
				suppressTargetLost = NO;
			}

			DESTROY(_primaryTarget);
		}
	}

	// check each unlaunched missile's target still exists and is in-range
	UPDATE_STAGE(@"checking missile targets");
	if (missile_status != MISSILE_STATUS_SAFE)
	{
		unsigned i;
		for (i = 0; i < max_missiles; i++)
		{
			if ([missile_entity[i] primaryTarget] != nil &&
					![self isValidTarget:[missile_entity[i] primaryTarget]])
			{
				[UNIVERSE addMessage:DESC(@"target-lost") forCount:3.0];
				[self playTargetLost];
				[missile_entity[i] removeTarget:nil];
				if (i == activeMissile)
				{
					[self noteLostTarget];
					DESTROY(_primaryTarget);
					missile_status = MISSILE_STATUS_ARMED;
				}
			} else if (i == activeMissile && [missile_entity[i] primaryTarget] == nil) {
				missile_status = MISSILE_STATUS_ARMED;
			}
		}
	}

	// if we don't have a primary target, and we're scanning, then check for a new
	// target to lock on to
	UPDATE_STAGE(@"looking for new target");
	if ([self primaryTarget] == nil && 
			(ident_engaged || missile_status != MISSILE_STATUS_SAFE) &&
			([self status] == STATUS_IN_FLIGHT || [self status] == STATUS_WITCHSPACE_COUNTDOWN))
	{
		Entity *target = [UNIVERSE firstEntityTargetedByPlayer];
		if ([self isValidTarget:target])
		{
			[self addTarget:target];
		}
	}
	
	// If our primary target is a wormhole, check to see if we have additional
	// information
	UPDATE_STAGE(@"checking for additional wormhole information");
	if ([[self primaryTarget] isWormhole])
	{
		WormholeEntity *wh = [self primaryTarget];
		switch ([wh scanInfo])
		{
			case WH_SCANINFO_NONE:
				OOLog(kOOLogInconsistentState, @"Internal Error - WH_SCANINFO_NONE reached in [PlayerEntity updateTargeting:]");
				[self dumpState];
				[wh dumpState];
				// Workaround a reported hit of the assert here.  We really
				// should work out how/why this could happen though and fix
				// the underlying cause.
				// - MKW 2011.03.11
				//assert([wh scanInfo] != WH_SCANINFO_NONE);
				[wh setScannedAt:[self clockTimeAdjusted]];
				break;
			case WH_SCANINFO_SCANNED:
				if ([self clockTimeAdjusted] > [wh scanTime] + 2)
				{
					[wh setScanInfo:WH_SCANINFO_COLLAPSE_TIME];
					//[UNIVERSE addCommsMessage:[NSString stringWithFormat:DESC(@"wormhole-collapse-time-computed"),
					//						   [UNIVERSE getSystemName:[wh destination]]] forCount:5.0];
				}
				break;
			case WH_SCANINFO_COLLAPSE_TIME:
				if([self clockTimeAdjusted] > [wh scanTime] + 4)
				{
					[wh setScanInfo:WH_SCANINFO_ARRIVAL_TIME];
					[UNIVERSE addCommsMessage:[NSString stringWithFormat:DESC(@"wormhole-arrival-time-computed-@"),
											   ClockToString([wh estimatedArrivalTime], NO)] forCount:5.0];
				}
				break;
			case WH_SCANINFO_ARRIVAL_TIME:
				if ([self clockTimeAdjusted] > [wh scanTime] + 7)
				{
					[wh setScanInfo:WH_SCANINFO_DESTINATION];
					[UNIVERSE addCommsMessage:[NSString stringWithFormat:DESC(@"wormhole-destination-computed-@"),
											   [UNIVERSE getSystemName:[wh destination]]] forCount:5.0];
				}
				break;
			case WH_SCANINFO_DESTINATION:
				if ([self clockTimeAdjusted] > [wh scanTime] + 10)
				{
					[wh setScanInfo:WH_SCANINFO_SHIP];
					// TODO: Extract last ship from wormhole and display its name
				}
				break;
			case WH_SCANINFO_SHIP:
				break;
		}
	}
	
	STAGE_TRACKING_END
}


- (void) orientationChanged
{
	quaternion_normalize(&orientation);
	rotMatrix = OOMatrixForQuaternionRotation(orientation);
	OOMatrixGetBasisVectors(rotMatrix, &v_right, &v_up, &v_forward);
	
	orientation.w = -orientation.w;
	playerRotMatrix = OOMatrixForQuaternionRotation(orientation);	// this is the rotation similar to ordinary ships
	orientation.w = -orientation.w;
}


- (void) applyAttitudeChanges:(double) delta_t
{
	[self applyRoll:flightRoll*delta_t andClimb:flightPitch*delta_t];
	[self applyYaw:flightYaw*delta_t];
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
	
	[self orientationChanged];
}

/*
 * This method should not be necessary, but when I replaced the above with applyRoll:andClimb:andYaw, the
 * ship went crazy. Perhaps applyRoll:andClimb is called from one of the subclasses and that was messing
 * things up.
 */
- (void) applyYaw:(GLfloat) yaw
{
	quaternion_rotate_about_y(&orientation, -yaw);
	
	[self orientationChanged];
}


- (OOMatrix) drawRotationMatrix	// override to provide the 'correct' drawing matrix
{
	return playerRotMatrix;
}


- (OOMatrix) drawTransformationMatrix
{
	OOMatrix result = playerRotMatrix;
	// HPVect: modify to use camera-relative positioning
	return OOMatrixTranslate(result, HPVectorToVector(position));
}


- (Quaternion) normalOrientation
{
	return make_quaternion(-orientation.w, orientation.x, orientation.y, orientation.z);
}


- (void) setNormalOrientation:(Quaternion) quat
{
	[self setOrientation:make_quaternion(-quat.w, quat.x, quat.y, quat.z)];
}


- (void) moveForward:(double) amount
{
	distanceTravelled += (float)amount;
	position = HPvector_add(position, vectorToHPVector(vector_multiply_scalar(v_forward, (float)amount)));
}


- (HPVector) breakPatternPosition
{
	return HPvector_add(position,vectorToHPVector(quaternion_rotate_vector(quaternion_conjugate(orientation),forwardViewOffset)));
}


- (Vector) viewpointOffset
{
//	if ([UNIVERSE breakPatternHide])
//		return kZeroVector;	// center view for break pattern
	// now done by positioning break pattern correctly

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


- (Vector) viewpointOffsetAft
{
	return aftViewOffset;
}

- (Vector) viewpointOffsetForward
{
	return forwardViewOffset;
}

- (Vector) viewpointOffsetPort
{
	return portViewOffset;
}

- (Vector) viewpointOffsetStarboard
{
	return starboardViewOffset;
}


/* TODO post 1.78: profiling suggests this gets called often enough
 * that it's worth caching the result per-frame - CIM */
- (HPVector) viewpointPosition
{
	HPVector		viewpoint = position;
	if (showDemoShips)
	{
		viewpoint = kZeroHPVector;
	}
	Vector		offset = [self viewpointOffset];
	
	// FIXME: this ought to be done with matrix or quaternion functions.
	OOMatrix r = rotMatrix;
	
	viewpoint.x += offset.x * r.m[0][0];	viewpoint.y += offset.x * r.m[1][0];	viewpoint.z += offset.x * r.m[2][0];
	viewpoint.x += offset.y * r.m[0][1];	viewpoint.y += offset.y * r.m[1][1];	viewpoint.z += offset.y * r.m[2][1];
	viewpoint.x += offset.z * r.m[0][2];	viewpoint.y += offset.z * r.m[1][2];	viewpoint.z += offset.z * r.m[2][2];
	
	return viewpoint;
}


- (void) drawImmediate:(bool)immediate translucent:(bool)translucent
{
	switch ([self status])
	{
		case STATUS_DEAD:
		case STATUS_COCKPIT_DISPLAY:
		case STATUS_DOCKED:
		case STATUS_START_GAME:
			return;
			
		default:
			if ([UNIVERSE breakPatternHide])  return;
	}
	
	[super drawImmediate:immediate translucent:translucent];
}


- (BOOL) massLocked
{
	return ((alertFlags & ALERT_FLAG_MASS_LOCK) != 0);
}


- (BOOL) atHyperspeed
{
	return travelling_at_hyperspeed;
}


- (float) occlusionLevel
{
	return occlusion_dial;
}


- (void) setOcclusionLevel:(float)level
{
	occlusion_dial = level;
}


- (void) setDockedAtMainStation
{
	[self setDockedStation:[UNIVERSE station]];
	if (_dockedStation != nil)  [self setStatus:STATUS_DOCKED];
}


- (StationEntity *) dockedStation
{
	return [_dockedStation weakRefUnderlyingObject];
}


- (void) setDockedStation:(StationEntity *)station
{
	[_dockedStation release];
	_dockedStation = [station weakRetain];
}


- (void) setTargetDockStationTo:(StationEntity *) value
{
	targetDockStation = value;
}


- (StationEntity *) getTargetDockStation
{
	return targetDockStation;
}


- (HeadUpDisplay *) hud
{
	return hud;
}


- (void) resetHud
{
	// set up defauld HUD for the ship
	NSDictionary *shipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:[self shipDataKey]];
	NSString *hud_desc = [shipDict oo_stringForKey:@"hud" defaultValue:@"hud.plist"];
	if (![self switchHudTo:hud_desc])  [self switchHudTo:@"hud.plist"];	// ensure we have a HUD to fall back to
}


- (BOOL) switchHudTo:(NSString *)hudFileName
{
	NSDictionary 	*hudDict = nil;
	BOOL 			wasHidden = NO;
	BOOL 			wasCompassActive = YES;
	double			scannerZoom = 1.0;
	int				i;

	if (!hudFileName)  return NO;
	
	// is the HUD in the process of being rendered? If yes, set it to defer state and abort the switching now
	if (hud != nil && [hud isUpdating])
	{
		[hud setDeferredHudName:hudFileName];
		return NO;
	}
	
	hudDict = [ResourceManager dictionaryFromFilesNamed:hudFileName inFolder:@"Config" andMerge:YES];
	// hud defined, but buggy?
	if (hudDict == nil)
	{
		OOLog(@"PlayerEntity.switchHudTo.failed", @"HUD dictionary file %@ to switch to not found or invalid.", hudFileName);
		return NO;
	}
	
	if (hud != nil)
	{
		// remember these values
		wasHidden = [hud isHidden];
		wasCompassActive = [hud isCompassActive];
		scannerZoom = [hud scannerZoom];
	}
	
	// buggy oxp could override hud.plist with a non-dictionary.
	if (hudDict != nil)
	{
		[hud setHidden:YES];	// hide the hud while rebuilding it.
		DESTROY(hud);
		hud = [[HeadUpDisplay alloc] initWithDictionary:hudDict inFile:hudFileName];
		[hud resetGuis:hudDict];
		// reset zoom & hidden to what they were before the swich
		[hud setScannerZoom:scannerZoom];
		[hud setCompassActive:wasCompassActive];
		[hud setHidden:wasHidden];
		activeMFD = 0;
		[multiFunctionDisplaySettings removeAllObjects];
		for (i = [hud mfdCount]-1 ; i >= 0 ; i--)
		{
			[multiFunctionDisplaySettings addObject:[NSNull null]];
		}
	}
	
	return YES;
}


- (void) setShowDemoShips:(BOOL)value
{
	showDemoShips = value;
}


- (BOOL) showDemoShips
{
	return showDemoShips;
}


- (GLfloat) forwardShieldLevel
{
	return forward_shield;
}


- (GLfloat) aftShieldLevel
{
	return aft_shield;
}


- (void) setForwardShieldLevel:(GLfloat)level
{
	forward_shield = OOClamp_0_max_f(level, [self maxForwardShieldLevel]);
}


- (void) setAftShieldLevel:(GLfloat)level
{
	aft_shield = OOClamp_0_max_f(level, [self maxAftShieldLevel]);
}


- (NSDictionary *) keyConfig
{
	return keyconfig_settings;
}


- (BOOL) isMouseControlOn
{
	return mouse_control_on;
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


- (GLfloat) dialYaw
{
	GLfloat result = -flightYaw / max_flight_yaw;
	if ((result < 1.0f)&&(result > -1.0f))
	return result;
	if (result > 0.0f)
		return 1.0f;
	return -1.0f;
}


- (GLfloat) dialSpeed
{
	GLfloat result = flightSpeed / maxFlightSpeed;
	return OOClamp_0_1_f(result);
}


- (GLfloat) dialHyperSpeed
{
	return flightSpeed / maxFlightSpeed;
}


- (GLfloat) dialForwardShield
{
	GLfloat result = forward_shield / [self maxForwardShieldLevel];
	return OOClamp_0_1_f(result);
}


- (GLfloat) dialAftShield
{
	GLfloat result = aft_shield / [self maxAftShieldLevel];
	return OOClamp_0_1_f(result);
}


- (GLfloat) dialEnergy
{
	GLfloat result = energy / maxEnergy;
	return OOClamp_0_1_f(result);
}


- (GLfloat) dialMaxEnergy
{
	return maxEnergy;
}


- (GLfloat) dialFuel
{
	if (fuel <= 0.0f)
		return 0.0f;
	if (fuel > [self fuelCapacity])
		return 1.0f;
	return (GLfloat)fuel / (GLfloat)[self fuelCapacity];
}


- (GLfloat) dialHyperRange
{
	if (equal_seeds(target_system_seed, system_seed) && ![UNIVERSE inInterstellarSpace])  return 0.0f;
	return [self fuelRequiredForJump] / (GLfloat)PLAYER_MAX_FUEL;
}


- (GLfloat) hullHeatLevel
{
	GLfloat result = (GLfloat)ship_temperature / (GLfloat)SHIP_MAX_CABIN_TEMP;
	return OOClamp_0_1_f(result);
}


- (GLfloat) laserHeatLevel
{
	GLfloat result = (GLfloat)weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


- (GLfloat)laserHeatLevelAft
{
	GLfloat result = aft_weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


- (GLfloat)laserHeatLevelForward
{
	GLfloat result = forward_weapon_temp / (GLfloat)PLAYER_MAX_WEAPON_TEMP;
// no need to check subents here
	return OOClamp_0_1_f(result);
}


- (GLfloat)laserHeatLevelPort
{
	GLfloat result = port_weapon_temp / PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}


- (GLfloat)laserHeatLevelStarboard
{
	GLfloat result = starboard_weapon_temp / PLAYER_MAX_WEAPON_TEMP;
	return OOClamp_0_1_f(result);
}




- (GLfloat) dialAltitude
{
	if ([self isDocked])  return 0.0f;
	
	// find nearest planet type entity...
	assert(UNIVERSE != nil);
	
	Entity	*nearestPlanet = [self findNearestStellarBody];
	if (nearestPlanet == nil)  return 1.0f;
	
	GLfloat	zd = nearestPlanet->zero_distance;
	GLfloat	cr = nearestPlanet->collision_radius;
	GLfloat	alt = sqrt(zd) - cr;
	
	return OOClamp_0_1_f(alt / (GLfloat)PLAYER_DIAL_MAX_ALTITUDE);
}


- (double) clockTime
{
	return ship_clock;
}


- (double) clockTimeAdjusted
{
	return ship_clock + ship_clock_adjust;
}


- (BOOL) clockAdjusting
{
	return ship_clock_adjust > 0;
}


- (void) addToAdjustTime:(double)seconds
{
	ship_clock_adjust += seconds;
}


- (NSString *) dial_clock
{
	return ClockToString(ship_clock, ship_clock_adjust > 0);
}


- (NSString *) dial_clock_adjusted
{
	return ClockToString(ship_clock + ship_clock_adjust, NO);
}


- (NSString *) dial_fpsinfo
{
	unsigned fpsVal = fps_counter;	
	return [NSString stringWithFormat:@"FPS: %3d", fpsVal];
}


- (NSString *) dial_objinfo
{
	NSString *result = [NSString stringWithFormat:@"Entities: %3ld", [UNIVERSE entityCount]];
#ifndef NDEBUG
	result = [NSString stringWithFormat:@"%@ (%d, %zu KiB, avg %lu bytes)", result, gLiveEntityCount, gTotalEntityMemory >> 10, gTotalEntityMemory / gLiveEntityCount];
#endif
	
	return result;
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
	if ([self weaponsOnline])
	{
		return missile_status;
	}
	else
	{
		// Invariant/safety interlock: weapons offline implies missiles safe. -- Ahruman 2012-07-21
		if (missile_status != MISSILE_STATUS_SAFE)
		{
			OOLogERR(@"player.missilesUnsafe", @"Missile state is not SAFE when weapons are offline. This is a bug, please report it.");
			[self safeAllMissiles];
		}
		return MISSILE_STATUS_SAFE;
	}
}


- (BOOL) canScoop:(ShipEntity *)other
{
	if (specialCargo)	return NO;
	return [super canScoop:other];
}


- (OOFuelScoopStatus) dialFuelScoopStatus
{
	if ([self hasScoop])
	{
		if (scoopsActive)
			return SCOOP_STATUS_ACTIVE;
		if ([cargo count] >= [self maxAvailableCargoSpace] || specialCargo)
			return SCOOP_STATUS_FULL_HOLD;
		return SCOOP_STATUS_OKAY;
	}
	else
	{
		return SCOOP_STATUS_NOT_INSTALLED;
	}
}


- (float) fuelLeakRate
{
	return fuel_leak_rate;
}


- (void) setFuelLeakRate:(float)value
{
	fuel_leak_rate = fmax(value, 0.0f);
}


- (NSMutableArray *) commLog
{
	assert(kCommLogTrimSize < kCommLogTrimThreshold);
	
	if (commLog != nil)
	{
		NSUInteger count = [commLog count];
		if (count >= kCommLogTrimThreshold)
		{
			[commLog removeObjectsInRange:NSMakeRange(0, count - kCommLogTrimSize)];
		}
	}
	else
	{
		commLog = [[NSMutableArray alloc] init];
	}
	
	return commLog;
}


- (NSMutableArray *) roleWeights
{
	return roleWeights;
}


- (void) addRoleForAggression:(ShipEntity *)victim
{
	if ([victim isExplicitlyUnpiloted] || [victim isHulk] || [victim hasHostileTarget] || [[victim primaryAggressor] isPlayer])
	{
		return;
	}
	NSString *role = nil;
	if ([[victim primaryRole] isEqualToString:@"escape-capsule"])
	{
		role = @"assassin-player";
	}
	else if ([victim bounty] > 0)
	{
		role = @"hunter";
	}
	else if ([victim isPirateVictim])
	{
		role = @"pirate";
	}
	else if ([UNIVERSE role:[self primaryRole] isInCategory:@"oolite-hunter"] || [victim scanClass] == CLASS_POLICE)
	{
		role = @"pirate-interceptor";
	}
	if (role == nil)
	{
		return;
	}
	NSUInteger times = [roleWeightFlags oo_intForKey:role defaultValue:0];
	times++;
	[roleWeightFlags setObject:[NSNumber numberWithInt:times] forKey:role];
	if ((times & (times-1)) == 0) // is power of 2
	{
		[self addRoleToPlayer:role];
	}
}


- (void) addRoleForMining
{
	NSString *role = @"miner";
	NSUInteger times = [roleWeightFlags oo_intForKey:role defaultValue:0];
	times++;
	[roleWeightFlags setObject:[NSNumber numberWithInt:times] forKey:role];
	if ((times & (times-1)) == 0) // is power of 2
	{
		[self addRoleToPlayer:role];
	}
}


- (void) addRoleToPlayer:(NSString *)role
{
	NSUInteger slot = Ranrot() & ([self maxPlayerRoles]-1);
	[self addRoleToPlayer:role inSlot:slot];
}


- (void) addRoleToPlayer:(NSString *)role inSlot:(NSUInteger)slot
{
	if (slot >= [self maxPlayerRoles])
	{
		slot = [self maxPlayerRoles];
	}
	if (slot > [roleWeights count])
	{
		[roleWeights addObject:role];
	}
	else
	{
		[roleWeights replaceObjectAtIndex:slot withObject:role];
	}
}


- (void) clearRoleFromPlayer:(BOOL)includingLongRange
{
	NSUInteger slot = Ranrot() % [roleWeights count];
	if (!includingLongRange)
	{
		NSString *role = [roleWeights objectAtIndex:slot];
		// long range roles cleared at 1/2 normal rate
		if ([role hasSuffix:@"+"] && randf() > 0.5)
		{
			return;
		}
	}
	[roleWeights replaceObjectAtIndex:slot withObject:@"player-unknown"];
}


- (void) clearRolesFromPlayer:(float)chance
{
	NSUInteger i, count=[roleWeights count];
	for (i = 0; i < count; i++)
	{
		if (randf() < chance)
		{
			[roleWeights replaceObjectAtIndex:i withObject:@"player-unknown"];
		}
	}
}


- (NSUInteger) maxPlayerRoles
{
	if (ship_kills >= 6400)
	{
		return 32;
	}
	else if (ship_kills >= 128)
	{
		return 16;
	}
	else
	{
		return 8;
	}
}


- (void) updateSystemMemory
{
	OOSystemID sys = [self currentSystemID];
	if (sys < 0)
	{
		return;
	}
	NSUInteger memory = 4;
	if (ship_kills >= 6400)
	{
		memory = 32;
	}
	else if (ship_kills >= 256)
	{
		memory = 16;
	}
	else if (ship_kills >= 64)
	{
		memory = 8;
	}
	if ([roleSystemList count] >= memory)
	{
		[roleSystemList removeObjectAtIndex:0];
	}
	[roleSystemList addObject:[NSNumber numberWithInt:sys]];
}


- (Entity *) compassTarget
{
	Entity *result = [compassTarget weakRefUnderlyingObject];
	if (result == nil)
	{
		DESTROY(compassTarget);
		return nil;
	}
	return result;
}


- (void) setCompassTarget:(Entity *)value
{
	[compassTarget release];
	compassTarget = [value weakRetain];
}


- (void) validateCompassTarget
{
	OOSunEntity		*the_sun = [UNIVERSE sun];
	OOPlanetEntity	*the_planet = [UNIVERSE planet];
	StationEntity	*the_station = [UNIVERSE station];
	Entity			*the_target = [self primaryTarget];
	Entity <OOBeaconEntity>		*beacon = [self nextBeacon];
	if ([self isInSpace] && the_sun && the_planet		// be in a system
		&& ![the_sun goneNova])			// and the system has not been novabombed
	{
		Entity *new_target = nil;
		OOAegisStatus	aegis = [self checkForAegis];
		
		switch ([self compassMode])
		{
			case COMPASS_MODE_INACTIVE:
				break;
			
			case COMPASS_MODE_BASIC:
				if ((aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE) && the_station)
				{
					new_target = the_station;
				}
				else
				{
					new_target = the_planet;
				}
				break;
				
			case COMPASS_MODE_PLANET:
				new_target = the_planet;
				break;
				
			case COMPASS_MODE_STATION:
				new_target = the_station;
				break;
				
			case COMPASS_MODE_SUN:
				new_target = the_sun;
				break;
				
			case COMPASS_MODE_TARGET:
				new_target = the_target;
				break;
				
			case COMPASS_MODE_BEACONS:
				new_target = beacon;
				break;
		}
		
		if (new_target == nil || [new_target status] < STATUS_ACTIVE || [new_target status] == STATUS_IN_HOLD)
		{
			[self setCompassMode:COMPASS_MODE_PLANET];
			new_target = the_planet;
		}
		
		if (EXPECT_NOT(new_target != [self compassTarget]))
		{
			[self setCompassTarget:new_target];
			[self doScriptEvent:OOJSID("compassTargetChanged") withArguments:[NSArray arrayWithObjects:new_target, OOStringFromCompassMode([self compassMode]), nil]];
		}
	}
}


- (NSString *) compassTargetLabel
{
	if (compassMode != COMPASS_MODE_BEACONS)
	{
		return @"";
	}
	Entity *target = [self compassTarget];
	if (target)
	{
		return [(Entity <OOBeaconEntity> *)target beaconLabel];
	}
	return @"";
}


- (OOCompassMode) compassMode
{
	return compassMode;
}


- (void) setCompassMode:(OOCompassMode) value
{
	compassMode = value;
}


- (void) setPrevCompassMode
{
	OOAegisStatus	aegis = AEGIS_NONE;
	Entity <OOBeaconEntity>		*beacon = nil;
	
	switch (compassMode)
	{
		case COMPASS_MODE_INACTIVE:
		case COMPASS_MODE_BASIC:
		case COMPASS_MODE_PLANET:
			beacon = [UNIVERSE lastBeacon];
			while (beacon != nil && [beacon isJammingScanning])
			{
				beacon = [beacon prevBeacon];
			}
			[self setNextBeacon:beacon];
			
			if (beacon != nil)
			{
				[self setCompassMode:COMPASS_MODE_BEACONS];
				break;
			}
			// else fall through to switch to target mode.

		case COMPASS_MODE_BEACONS:
			beacon = [self nextBeacon];
			do
			{
				beacon = [beacon prevBeacon];
			} while (beacon != nil && [beacon isJammingScanning]);
			[self setNextBeacon:beacon];
			
			if (beacon == nil)
			{
				if ([self primaryTarget])
				{
					[self setCompassMode:COMPASS_MODE_TARGET];
				}
				else
				{
					[self setCompassMode:COMPASS_MODE_SUN];
				}
				break;
			}
			break;

		case COMPASS_MODE_TARGET:
			[self setCompassMode:COMPASS_MODE_SUN];
			break;

		case COMPASS_MODE_SUN:
			aegis = [self checkForAegis];
			if (aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE)
			{ 
				[self setCompassMode:COMPASS_MODE_STATION];
			}
			else
			{
				[self setCompassMode:COMPASS_MODE_PLANET];
			} 
			break;

		case COMPASS_MODE_STATION:
			[self setCompassMode:COMPASS_MODE_PLANET];
			break;
	}
}


- (void) setNextCompassMode
{
	OOAegisStatus	aegis = AEGIS_NONE;
	Entity <OOBeaconEntity>		*beacon = nil;
	
	switch (compassMode)
	{
		case COMPASS_MODE_INACTIVE:
		case COMPASS_MODE_BASIC:
		case COMPASS_MODE_PLANET:
			aegis = [self checkForAegis];
			if ([UNIVERSE station] && (aegis == AEGIS_CLOSE_TO_MAIN_PLANET || aegis == AEGIS_IN_DOCKING_RANGE))
			{ 
				[self setCompassMode:COMPASS_MODE_STATION];
			}
			else
			{
				[self setCompassMode:COMPASS_MODE_SUN];
			}
			break;
			
		case COMPASS_MODE_STATION:
			[self setCompassMode:COMPASS_MODE_SUN];
			break;
			
		case COMPASS_MODE_SUN:
			if ([self primaryTarget])
			{
				[self setCompassMode:COMPASS_MODE_TARGET];
				break;
			}
			// else fall through to switch to beacon mode.
			
		case COMPASS_MODE_TARGET:
			beacon = [UNIVERSE firstBeacon];
			while (beacon != nil && [beacon isJammingScanning])
			{
				beacon = [beacon nextBeacon];
			}
			[self setNextBeacon:beacon];
			
			if (beacon != nil)  [self setCompassMode:COMPASS_MODE_BEACONS];
			else  [self setCompassMode:COMPASS_MODE_PLANET];
			break;

		case COMPASS_MODE_BEACONS:
			beacon = [self nextBeacon];
			do
			{
				beacon = [beacon nextBeacon];
			} while (beacon != nil && [beacon isJammingScanning]);
			[self setNextBeacon:beacon];
			
			if (beacon == nil)
			{
				[self setCompassMode:COMPASS_MODE_PLANET];
			}
			break;
	}
}


- (NSUInteger) activeMissile
{
	return activeMissile;
}


- (void) setActiveMissile:(NSUInteger)value
{
	activeMissile = value;
}


- (NSUInteger) dialMaxMissiles
{
	return max_missiles;
}


- (BOOL) dialIdentEngaged
{
	return ident_engaged;
}


- (void) setDialIdentEngaged:(BOOL)newValue
{
	ident_engaged = !!newValue;
}


- (NSString *) specialCargo
{
	return specialCargo;
}


- (NSString *) dialTargetName
{
	Entity		*target_entity = [self primaryTarget];
	NSString	*result = nil;
	
	if (target_entity == nil)
	{
		result = DESC(@"no-target-string");
	}
	
	if ([target_entity respondsToSelector:@selector(identFromShip:)])
	{
		result = [(ShipEntity*)target_entity identFromShip:self];
	}
	
	if (result == nil)  result = DESC(@"unknown-target");
	
	return result;
}


- (NSString *) multiFunctionText:(NSUInteger)i
{
	NSString *key = [multiFunctionDisplaySettings oo_stringAtIndex:i defaultValue:nil];
	if (key == nil)
	{
		return nil;
	}
	NSString *text = [multiFunctionDisplayText oo_stringForKey:key defaultValue:nil];
	return text;
}


- (void) setMultiFunctionText:(NSString *)text forKey:(NSString *)key
{
	if (text != nil)
	{
		[multiFunctionDisplayText setObject:text forKey:key];
	}
	else if (key != nil)
	{
		[multiFunctionDisplayText removeObjectForKey:key];
		// and blank any MFDs currently using it
		NSUInteger index;
		while ((index = [multiFunctionDisplaySettings indexOfObject:key]) != NSNotFound)
		{
			[multiFunctionDisplaySettings replaceObjectAtIndex:index withObject:[NSNull null]];
		}
	}
}


- (BOOL) setMultiFunctionDisplay:(NSUInteger)index toKey:(NSString *)key
{
	if (index >= [hud mfdCount])
	{
		// is first inactive display
		index = [multiFunctionDisplaySettings indexOfObject:[NSNull null]];
		if (index == NSNotFound)
		{
			return NO;
		}
	}

	if (index < [hud mfdCount])
	{
		if (key == nil)
		{
			[multiFunctionDisplaySettings replaceObjectAtIndex:index withObject:[NSNull null]];
		}
		else
		{
			[multiFunctionDisplaySettings replaceObjectAtIndex:index withObject:key];
		}
		return YES;
	}
	else
	{
		return NO;
	}
}


- (void) cycleMultiFunctionDisplay:(NSUInteger) index
{
	NSArray *keys = [multiFunctionDisplayText allKeys];
	if ([keys count] == 0)
	{
		[self setMultiFunctionDisplay:index toKey:nil];
		return;
	}
	id current = [multiFunctionDisplaySettings objectAtIndex:index];
	if (current == [NSNull null])
	{
		[self setMultiFunctionDisplay:index toKey:[keys objectAtIndex:0]];
	}
	else
	{
		NSUInteger cIndex = [keys indexOfObject:current];
		if (cIndex == NSNotFound || cIndex + 1 >= [keys count])
		{
			[self setMultiFunctionDisplay:index toKey:nil];
		}
		else 
		{
			[self setMultiFunctionDisplay:index toKey:[keys objectAtIndex:(cIndex+1)]];
		}
	}
}


- (void) selectNextMultiFunctionDisplay
{
	activeMFD = (activeMFD + 1) % [[self hud] mfdCount];
	[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"mfd-d-selected") ,activeMFD + 1] forCount:3.0 ];
}


- (NSUInteger) activeMFD
{
	return activeMFD;
}


- (ShipEntity *) missileForPylon:(NSUInteger)value
{
	if (value < max_missiles)  return missile_entity[value];
	return nil;
}



- (void) safeAllMissiles
{
	//	sets all missile targets to NO_TARGET
	
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i] && [missile_entity[i] primaryTarget] != nil)
			[missile_entity[i] removeTarget:nil];
	}
	missile_status = MISSILE_STATUS_SAFE;
}


- (void) tidyMissilePylons
{
	// Make sure there's no gaps between missiles, synchronise missile_entity & missile_list.
	int i, pylon = 0;
	for(i = 0; i < PLAYER_MAX_MISSILES; i++)
	{
		if(missile_entity[i] != nil)
		{
			missile_entity[pylon] = missile_entity[i];
			missile_list[pylon] = [OOEquipmentType equipmentTypeWithIdentifier:[missile_entity[i] primaryRole]];
			pylon++;
		}
	}

	// Now clean up the remainder of the pylons.
	for(i = pylon; i < PLAYER_MAX_MISSILES; i++)
	{
		missile_entity[i] = nil;
	}
}


- (void) selectNextMissile
{
	if (![self weaponsOnline])  return;
	
	unsigned i;
	for (i = 1; i < max_missiles; i++)
	{
		int next_missile = (activeMissile + i) % max_missiles;
		if (missile_entity[next_missile])
		{
			// If we don't have the multi-targeting module installed, clear the active missiles' target
			if( ![self hasEquipmentItem:@"EQ_MULTI_TARGET"] && [missile_entity[activeMissile] isMissile] )
			{
				[missile_entity[activeMissile] removeTarget:nil];
			}

			// Set next missile to active
			[self setActiveMissile:next_missile];

			if (missile_status != MISSILE_STATUS_SAFE)
			{
				missile_status = MISSILE_STATUS_ARMED;

				// If the newly active pylon contains a missile then work out its target, if any
				if( [missile_entity[activeMissile] isMissile] )
				{
					if( [self hasEquipmentItem:@"EQ_MULTI_TARGET"] &&
							([missile_entity[next_missile] primaryTarget] != nil))
					{
						// copy the missile's target
						[self addTarget:[missile_entity[next_missile] primaryTarget]];
						missile_status = MISSILE_STATUS_TARGET_LOCKED;
					}
					else if ([self primaryTarget] != nil)
					{
						// never inherit target if we have EQ_MULTI_TARGET installed! [ Bug #16221 : Targeting enhancement regression ]
						if([self hasEquipmentItem:@"EQ_MULTI_TARGET"])
						{
							[self noteLostTarget];
							DESTROY(_primaryTarget);
						}
						else
						{
							[missile_entity[activeMissile] addTarget:[self primaryTarget]];
							missile_status = MISSILE_STATUS_TARGET_LOCKED;
						}
					}
				}
			}
			return;
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


// used by Javascript and the distinction is important for NPCs
- (OOAlertCondition) realAlertCondition
{
	return [self alertCondition];
}


- (OOAlertCondition) alertCondition
{
	OOAlertCondition old_alert_condition = alertCondition;
	alertCondition = ALERT_CONDITION_GREEN;
	
	[self setAlertFlag:ALERT_FLAG_DOCKED to:[self status] == STATUS_DOCKED];
	
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


- (OOPlayerFleeingStatus) fleeingStatus
{
	return fleeing_status;
}

/////////////////////////////////////////////////////////////////////


- (void) interpretAIMessage:(NSString *)ms
{
	if ([ms isEqual:@"HOLD_FULL"])
	{
		[self playHoldFull];
		[UNIVERSE addMessage:DESC(@"hold-full") forCount:4.5];
	}

	if ([ms isEqual:@"INCOMING_MISSILE"])
	{
		if ([self primaryAggressor] != nil)
		{
			[self playIncomingMissile:HPVectorToVector([[self primaryAggressor] position])];
		}
		else
		{
			[self playIncomingMissile:kZeroVector];
		}
		[UNIVERSE addMessage:DESC(@"incoming-missile") forCount:4.5];
	}

	if ([ms isEqual:@"ENERGY_LOW"])
	{
		[UNIVERSE addMessage:DESC(@"energy-low") forCount:6.0];
	}

	if ([ms isEqual:@"ECM"] && ![self isDocked])  [self playHitByECMSound];

	if ([ms isEqual:@"DOCKING_REFUSED"] && [self status] == STATUS_AUTOPILOT_ENGAGED)
	{
		[self playDockingDenied];
		[UNIVERSE addMessage:DESC(@"autopilot-denied") forCount:4.5];
		autopilot_engaged = NO;
		[self resetAutopilotAI];
		DESTROY(_primaryTarget);
		[self setStatus:STATUS_IN_FLIGHT];
		[[OOMusicController sharedController] stopDockingMusic];
		[self doScriptEvent:OOJSID("playerDockingRefused")];
	}

	// aegis messages to advanced compass so in planet mode it behaves like the old compass
	if (compassMode != COMPASS_MODE_BASIC)
	{
		if ([ms isEqual:@"AEGIS_CLOSE_TO_MAIN_PLANET"]&&(compassMode == COMPASS_MODE_PLANET))
		{
			[self playAegisCloseToPlanet];
			[self setCompassMode:COMPASS_MODE_STATION];
		}
		if ([ms isEqual:@"AEGIS_IN_DOCKING_RANGE"]&&(compassMode == COMPASS_MODE_PLANET))
		{
			[self playAegisCloseToStation];
			[self setCompassMode:COMPASS_MODE_STATION];
		}
		if ([ms isEqual:@"AEGIS_NONE"]&&(compassMode == COMPASS_MODE_STATION))
		{
			[self setCompassMode:COMPASS_MODE_PLANET];
		}
	}
}


- (BOOL) mountMissile:(ShipEntity *)missile
{
	if (missile == nil)  return NO;
	
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if (missile_entity[i] == nil)
		{
			missile_entity[i] = [missile retain];
			missile_list[missiles] = [OOEquipmentType equipmentTypeWithIdentifier:[missile primaryRole]];
			missiles++;
			if (missiles == 1) [self setActiveMissile:0];	// auto select the first purchased missile
			return YES;
		}
	}
	
	return NO;
}


- (BOOL) mountMissileWithRole:(NSString *)role
{
	if ([self missileCount] >= [self missileCapacity]) return NO;
	return [self mountMissile:[[UNIVERSE newShipWithRole:role] autorelease]];
}


- (ShipEntity *) fireMissile
{
	ShipEntity	*missile = missile_entity[activeMissile];	// retain count is 1
	NSString	*identifier = [missile primaryRole];
	ShipEntity	*firedMissile = nil;

	if (missile == nil) return nil;
	
	if (![self weaponsOnline])  return nil;
	
	// check if we were cloaked before firing the missile - can't use
	// cloaking_device_active directly because fireMissilewithIdentifier: andTarget:
	// will reset it in case passive cloak is set - Nikos 20130313
	BOOL cloakedPriorToFiring = cloaking_device_active;
	
	launchingMissile = YES;
	replacingMissile = NO;

	if ([missile isMine] && (missile_status != MISSILE_STATUS_SAFE))
	{
		firedMissile = [self launchMine:missile];
		if (!replacingMissile) [self removeFromPylon:activeMissile];
		if (firedMissile != nil) [self playMineLaunched:[self missileLaunchPosition]];
	}
	else
	{
		if (missile_status != MISSILE_STATUS_TARGET_LOCKED) return nil;
		//  release this before creating it anew in fireMissileWithIdentifier
		firedMissile = [self fireMissileWithIdentifier:identifier andTarget:[missile primaryTarget]];

		if (firedMissile != nil)
		{
			if (!replacingMissile) [self removeFromPylon:activeMissile];
			[self playMissileLaunched:[self missileLaunchPosition]];
		}
	}
	
	if (cloakedPriorToFiring && cloakPassive)
	{
		// fireMissilewithIdentifier: andTarget: has already taken care of deactivating
		// the cloak in the case of missiles by the time we get here, but explicitly
		// calling deactivateCloakingDevice is needed in order to be covered fully with mines too
		[self deactivateCloakingDevice];
	}
	
	replacingMissile = NO;
	launchingMissile = NO;
	
	return firedMissile;
}


- (ShipEntity *) launchMine:(ShipEntity*) mine
{
	if (!mine)
		return nil;
		
	if (![self weaponsOnline])
		return nil;
		
	[mine setOwner: self];
	[mine setBehaviour: BEHAVIOUR_IDLE];
	[self dumpItem: mine];	// includes UNIVERSE addEntity: CLASS_CARGO, STATUS_IN_FLIGHT, AI state GLOBAL ( the last one starts the timer !)
	[mine setScanClass: CLASS_MINE];
	
	float  mine_speed = 500.0f;
	Vector mvel = vector_subtract([mine velocity], vector_multiply_scalar(v_forward, mine_speed));
	[mine setVelocity: mvel];
	[self doScriptEvent:OOJSID("shipReleasedEquipment") withArgument:mine];
	return mine;
}


- (BOOL) assignToActivePylon:(NSString *)equipmentKey
{
	if (!launchingMissile) return NO;
	
	OOEquipmentType			*eqType = nil;
	
	if ([equipmentKey hasSuffix:@"_DAMAGED"])
	{
		return NO;
	}
	else
	{
		eqType = [OOEquipmentType equipmentTypeWithIdentifier:equipmentKey];
	}
	
	// missiles with techlevel above 99 (kOOVariableTechLevel) are never available to the player
	if (![eqType isMissileOrMine] || [eqType effectiveTechLevel] > kOOVariableTechLevel)
	{
		return NO;
	}

	ShipEntity *amiss = [UNIVERSE newShipWithRole:equipmentKey];
	
	if (!amiss) return NO;

	// replace the missile now.
	[missile_entity[activeMissile] release];
	missile_entity[activeMissile] = amiss;
	missile_list[activeMissile] = eqType;
	
	// make sure the new missile is properly activated.
	if (activeMissile > 0) activeMissile--;
	else activeMissile = max_missiles - 1;
	[self selectNextMissile];
	
	replacingMissile = YES;
	
	return YES;
}


- (BOOL) activateCloakingDevice
{
	if (![self hasCloakingDevice])  return NO;
	
	if ([super activateCloakingDevice])
	{
		[UNIVERSE addMessage:DESC(@"cloak-on") forCount:2];
		[self playCloakingDeviceOn];
		return YES;
	}
	else
	{
		[UNIVERSE addMessage:DESC(@"cloak-low-juice") forCount:3];
		[self playCloakingDeviceInsufficientEnergy];
		return NO;
	}
}


- (void) deactivateCloakingDevice
{
	if (![self hasCloakingDevice])  return;

	[super deactivateCloakingDevice];
	[UNIVERSE addMessage:DESC(@"cloak-off") forCount:2];
	[self playCloakingDeviceOff];
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
	{
		return NO;
	}
}


- (OOEnergyUnitType) installedEnergyUnitType
{
	if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"])  return ENERGY_UNIT_NAVAL;
	if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT"])  return ENERGY_UNIT_NORMAL;
	return ENERGY_UNIT_NONE;
}

/* Is handled slightly differently for player */
- (float) energyRechargeRate
{
	double energy_multiplier = 1.0 + 0.1 * [self installedEnergyUnitType]; // 1.8x recharge with normal energy unit, 2.6x with naval!
	return energy_recharge_rate * energy_multiplier;
}


- (OOEnergyUnitType) energyUnitType
{
	if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"])  return ENERGY_UNIT_NAVAL;
	if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT"])  return ENERGY_UNIT_NORMAL;
	if ([self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT_DAMAGED"])  return ENERGY_UNIT_NAVAL_DAMAGED;
	if ([self hasEquipmentItem:@"EQ_ENERGY_UNIT_DAMAGED"])  return ENERGY_UNIT_NORMAL_DAMAGED;
	return ENERGY_UNIT_NONE;
}

- (float) heatInsulation
{
	return [self hasHeatShield] ? 2.0f : 1.0f;
}


- (void) currentWeaponStats
{
	OOWeaponType currentWeapon = [self currentWeapon];
	// Did find & correct a minor mismatch between player and NPC weapon stats. This is the resulting code - Kaks 20101027
	
	// Basic stats: weapon_damage & weaponRange (weapon_recharge_rate is not used by the player)
	[self setWeaponDataFromType:currentWeapon];
	
	// Advanced stats: all the other stats used by the player!
	switch (currentWeapon)
	{
		case WEAPON_PLASMA_CANNON:
			weapon_energy_use =		6.0f;
			weapon_reload_time =	0.25f;
			break;
			
		case WEAPON_PULSE_LASER:
			weapon_energy_use =		0.8f;
			weapon_reload_time =	0.5f;
			break;
			
		case WEAPON_BEAM_LASER:
			weapon_energy_use =		1.0f;
			weapon_reload_time =	0.1f;
			break;
			
		case WEAPON_MINING_LASER:
			weapon_energy_use =		1.4f;
			weapon_reload_time =	2.5f;
			break;
			
		case WEAPON_THARGOID_LASER:
		case WEAPON_MILITARY_LASER:
			weapon_energy_use =		1.2f;
			weapon_reload_time =	0.1f;
			break;
			
		case WEAPON_NONE:
		case WEAPON_UNDEFINED:
			weapon_energy_use =		0.0f;
			weapon_reload_time =	0.1f;
			break;
	}
}


- (BOOL) weaponsOnline
{
	return weapons_online;
}


- (void) setWeaponsOnline:(BOOL)newValue
{
	weapons_online = !!newValue;
	if (!weapons_online)  [self safeAllMissiles];
}


- (Vector) currentLaserOffset
{
	return [self laserPortOffset:currentWeaponFacing];
}


- (BOOL) fireMainWeapon
{
	int weapon_to_be_fired = [self currentWeapon];

	if (![self weaponsOnline])
	{
		return NO;
	}
	
	if (weapon_temp / PLAYER_MAX_WEAPON_TEMP >= WEAPON_COOLING_CUTOUT)
	{
		[self playWeaponOverheated:[self currentLaserOffset]];
		[UNIVERSE addMessage:DESC(@"weapon-overheat") forCount:3.0];
		return NO;
	}

	if (weapon_to_be_fired == WEAPON_NONE)
	{
		return NO;
	}

	[self currentWeaponStats];

	if (energy <= weapon_energy_use)
	{
		[UNIVERSE addMessage:DESC(@"weapon-out-of-juice") forCount:3.0];
		return NO;
	}

	using_mining_laser = (weapon_to_be_fired == WEAPON_MINING_LASER);

	energy -= weapon_energy_use;

	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			forward_weapon_temp += weapon_shot_temperature;
			forward_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_AFT:
			aft_weapon_temp += weapon_shot_temperature;
			aft_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_PORT:
			port_weapon_temp += weapon_shot_temperature;
			port_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_STARBOARD:
			starboard_weapon_temp += weapon_shot_temperature;
			starboard_shot_time = 0.0;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}
	
	BOOL	weaponFired = NO;
	switch (weapon_to_be_fired)
	{
		case WEAPON_PLASMA_CANNON:
			[self firePlasmaShotAtOffset:10.0 speed:PLAYER_PLASMA_SPEED color:[OOColor greenColor]];
			weaponFired = YES;
			break;

		case WEAPON_PULSE_LASER:
		case WEAPON_BEAM_LASER:
		case WEAPON_MINING_LASER:
		case WEAPON_MILITARY_LASER:
			[self fireLaserShotInDirection:currentWeaponFacing];
			weaponFired = YES;
			break;
		
		case WEAPON_THARGOID_LASER:
			break;
	}
	
	if (weaponFired && cloaking_device_active && cloakPassive)
	{
		[self deactivateCloakingDevice];
	}	
	
	return weaponFired;
}


- (OOWeaponType) weaponForFacing:(OOWeaponFacing)facing
{
	switch (facing)
	{
		case WEAPON_FACING_FORWARD:
			return forward_weapon_type;
			
		case WEAPON_FACING_AFT:
			return aft_weapon_type;
			
		case WEAPON_FACING_PORT:
			return port_weapon_type;
			
		case WEAPON_FACING_STARBOARD:
			return starboard_weapon_type;
			
		case WEAPON_FACING_NONE:
			break;
	}
	return WEAPON_NONE;
}


- (OOWeaponType) currentWeapon
{
	return [self weaponForFacing:currentWeaponFacing];
}


// override ShipEntity definition to ensure that 
// if shields are still up, always hit the main entity and take the damage
// on the shields
- (GLfloat) doesHitLine:(HPVector)v0 :(HPVector)v1 :(ShipEntity **)hitEntity
{
	if (hitEntity)
		hitEntity[0] = (ShipEntity*)nil;
	Vector u0 = HPVectorToVector(HPvector_between(position, v0));	// relative to origin of model / octree
	Vector u1 = HPVectorToVector(HPvector_between(position, v1));
	Vector w0 = make_vector(dot_product(u0, v_right), dot_product(u0, v_up), dot_product(u0, v_forward));	// in ijk vectors
	Vector w1 = make_vector(dot_product(u1, v_right), dot_product(u1, v_up), dot_product(u1, v_forward));
	GLfloat hit_distance = [octree isHitByLine:w0 :w1];
	if (hit_distance)
	{
		if (hitEntity)
			hitEntity[0] = self;
	}

	bool shields = false;
	if ((w0.z >= 0 && forward_shield > 1) || (w0.z <= 0 && aft_shield > 1))
	{
		shields = true;
	}
	
	NSEnumerator	*subEnum = nil;
	ShipEntity		*se = nil;
	for (subEnum = [self shipSubEntityEnumerator]; (se = [subEnum nextObject]); )
	{
		HPVector p0 = [se absolutePositionForSubentity];
		Triangle ijk = [se absoluteIJKForSubentity];
		u0 = HPVectorToVector(HPvector_between(p0, v0));
		u1 = HPVectorToVector(HPvector_between(p0, v1));
		w0 = resolveVectorInIJK(u0, ijk);
		w1 = resolveVectorInIJK(u1, ijk);
		
		GLfloat hitSub = [se->octree isHitByLine:w0 :w1];
		if (hitSub && (hit_distance == 0 || hit_distance > hitSub))
		{	
			hit_distance = hitSub;
			if (hitEntity && !shields)
			{
				*hitEntity = se;
			}
		}
	}
	
	return hit_distance;
}



- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	HPVector		rel_pos;
	double		d_forward, d_right, d_up;
	BOOL		internal_damage = NO;	// base chance
	
	OOLog(@"player.ship.damage",  @"Player took damage from %@ becauseOf %@", ent, other);
	
	if ([self status] == STATUS_DEAD)  return;
	if (amount == 0.0)  return;
	
	BOOL cascadeWeapon = [ent isCascadeWeapon];
	BOOL cascading = NO;
	if (cascadeWeapon)
	{
		cascading = [self cascadeIfAppropriateWithDamageAmount:amount cascadeOwner:[ent owner]];
	}
	
	// make sure ent (& its position) is the attacking _ship_/missile !
	if (ent && [ent isSubEntity]) ent = [ent owner];
	
	[[ent retain] autorelease];
	[[other retain] autorelease];
	
	rel_pos = (ent != nil) ? [ent position] : kZeroHPVector;
	rel_pos = HPvector_subtract(rel_pos, position);
	
	[self doScriptEvent:OOJSID("shipBeingAttacked") withArgument:ent];
	if ([ent isShip]) [(ShipEntity *)ent doScriptEvent:OOJSID("shipAttackedOther") withArgument:self];

	d_forward = dot_product(HPVectorToVector(rel_pos), v_forward);
	d_right = dot_product(HPVectorToVector(rel_pos), v_right);
	d_up = dot_product(HPVectorToVector(rel_pos), v_up);
	Vector relative = make_vector(d_right,d_up,d_forward);

	[self playShieldHit:relative];

	// firing on an innocent ship is an offence
	if ([other isShip])
	{
		[self broadcastHitByLaserFrom:(ShipEntity*) other];
	}

	if (d_forward >= 0)
	{
		forward_shield -= amount;
		if (forward_shield < 0.0)
		{
			amount = -forward_shield;
			forward_shield = 0.0f;
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
			aft_shield = 0.0f;
		}
		else
		{
			amount = 0.0;
		}
	}
	
	OOShipDamageType damageType = cascadeWeapon ? kOODamageTypeCascadeWeapon : kOODamageTypeEnergy;
	
	if (amount > 0.0)
	{
		internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems
		energy -= amount;
		[self playDirectHit:relative];
		ship_temperature += (amount / [self heatInsulation]);
	}
	[self noteTakingDamage:amount from:other type:damageType];
	if (cascading) energy = 0.0; // explicitly set energy to zero when cascading, in case an oxp raised the energy in noteTakingDamage.
	
	if (energy <= 0.0) //use normal ship temperature calculations for heat damage
	{
		if ([other isShip])
		{
			[(ShipEntity *)other noteTargetDestroyed:self];
		}
		
		[self getDestroyedBy:other damageType:damageType];
	}
	else
	{
		if (internal_damage)  [self takeInternalDamage];
	}
}


- (void) takeScrapeDamage:(double) amount from:(Entity *) ent
{
	HPVector  rel_pos;
	double  d_forward, d_right, d_up;
	BOOL	internal_damage = NO;	// base chance
	
	if ([self status] == STATUS_DEAD)  return;
	
	if (amount < 0) 
	{
		OOLog(@"player.ship.damage",  @"Player took negative scrape damage %.3f so we made it positive", amount);
		amount = -amount;
	}
	OOLog(@"player.ship.damage",  @"Player took %.3f scrape damage from %@", amount, ent);
	
	[[ent retain] autorelease];
	rel_pos = ent ? [ent position] : kZeroHPVector;
	rel_pos = HPvector_subtract(rel_pos, position);
	// rel_pos is now small
	d_forward = dot_product(HPVectorToVector(rel_pos), v_forward);
	d_right = dot_product(HPVectorToVector(rel_pos), v_right);
	d_up = dot_product(HPVectorToVector(rel_pos), v_up);
	Vector relative = make_vector(d_right,d_up,d_forward);

	[self playScrapeDamage:relative];
	if (d_forward >= 0)
	{
		forward_shield -= amount;
		if (forward_shield < 0.0)
		{
			amount = -forward_shield;
			forward_shield = 0.0f;
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
			aft_shield = 0.0f;
		}
		else
		{
			amount = 0.0;
		}
	}
	
	if (amount)
	{
		internal_damage = ((ranrot_rand() & PLAYER_INTERNAL_DAMAGE_FACTOR) < amount);	// base chance of damage to systems
	}
	
	[super takeScrapeDamage:amount from:ent];

	if (internal_damage)
	{
		[self takeInternalDamage];
	}
}


- (void) takeHeatDamage:(double) amount
{
	if ([self status] == STATUS_DEAD || amount < 0)  return;
	
	// hit the shields first!
	float fwd_amount = (float)(0.5 * amount);
	float aft_amount = (float)(0.5 * amount);

	forward_shield -= fwd_amount;
	if (forward_shield < 0.0)
	{
		fwd_amount = -forward_shield;
		forward_shield = 0.0f;
	}
	else
	{
		fwd_amount = 0.0f;
	}

	aft_shield -= aft_amount;
	if (aft_shield < 0.0)
	{
		aft_amount = -aft_shield;
		aft_shield = 0.0f;
	}
	else
	{
		aft_amount = 0.0f;
	}

	double residual_amount = fwd_amount + aft_amount;
	
	[super takeHeatDamage:residual_amount];
}


- (ProxyPlayerEntity *) createDoppelganger
{
	ProxyPlayerEntity *result = (ProxyPlayerEntity *)[[UNIVERSE newShipWithName:[self shipDataKey] usePlayerProxy:YES] autorelease];
	
	if (result != nil)
	{
		[result setPosition:[self position]];
		[result setScanClass:CLASS_NEUTRAL];
		[result setOrientation:[self normalOrientation]];
		[result setVelocity:[self velocity]];
		[result setSpeed:[self flightSpeed]];
		[result setDesiredSpeed:[self flightSpeed]];
		[result setRoll:flightRoll];
		[result setBehaviour:BEHAVIOUR_IDLE];
		[result switchAITo:@"nullAI.plist"];  // fly straight on
		[result setTemperature:[self temperature]];
		[result copyValuesFromPlayer:self];
	}
	
	return result;
}


- (ShipEntity *) launchEscapeCapsule
{
	ShipEntity		*doppelganger = nil;
	ShipEntity		*escapePod = nil;
	
	if ([UNIVERSE displayGUI]) [self switchToMainView];	// Clear the F7 screen!
	[UNIVERSE setViewDirection:VIEW_FORWARD];
	
	if ([self status] == STATUS_DEAD) return NO;
	
	/*
		While inside the escape pod, we need to block access to all player.ship properties,
		since we're not supposed to be inside our ship anymore! -- Kaks 20101114
	*/
	
	[UNIVERSE setBlockJSPlayerShipProps:YES]; 	// no player.ship properties while inside the pod!
	ship_clock_adjust += 43200 + 5400 * (ranrot_rand() & 127);	// add up to 8 days until rescue!
	dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
	flightSpeed = fmin(flightSpeed, maxFlightSpeed);
	
	doppelganger = [self createDoppelganger];
	if (doppelganger)
	{
		[doppelganger setVelocity:vector_multiply_scalar(v_forward, flightSpeed)];
		[doppelganger setSpeed:0.0];
		[doppelganger setDesiredSpeed:0.0];
		[doppelganger setRoll:0.2 * (randf() - 0.5)];
		[doppelganger setOwner:self];
		[doppelganger setThrust:0]; // drifts
		[UNIVERSE addEntity:doppelganger];
	}

	[self setFoundTarget:doppelganger]; // must do this before setting status
	[self setStatus:STATUS_ESCAPE_SEQUENCE];	// now set up the escape sequence.


	// must do this before next step or uses BBox of pod, not old ship!
	float sheight = (float)(boundingBox.max.y - boundingBox.min.y);
	position = HPvector_subtract(position, vectorToHPVector(vector_multiply_scalar(v_up, sheight)));
	float sdepth = (float)(boundingBox.max.z - boundingBox.min.z);
	position = HPvector_subtract(position, vectorToHPVector(vector_multiply_scalar(v_forward, sdepth/2.0)));

	// set up you
	escapePod = [UNIVERSE newShipWithName:@"escape-capsule"];	// retained
	if (escapePod != nil)
	{
		// FIXME: this should use OOShipType, which should exist. -- Ahruman
		[self setMesh:[escapePod mesh]];
	}
	
	/* These used to be non-zero, but BEHAVIOUR_IDLE levels off flight
	 * anyway, and inertial velocity is used instead of inertialess
	 * thrust - CIM */
	flightSpeed = 0.0f;
	flightPitch = 0.0f;
	flightRoll = 0.0f;
	flightYaw = 0.0f;
	// and turn off inertialess drive
	thrust = 0.0f;
	

	/*	Add an impulse upwards and backwards to the escape pod. This avoids
		flying straight through the doppelganger in interstellar space or when
		facing the main station/escape target, and generally looks cool.
		-- Ahruman 2011-04-02
	*/
	Vector launchVector = vector_add([doppelganger velocity],
							vector_add(vector_multiply_scalar(v_up, 15.0f),
									   vector_multiply_scalar(v_forward, -90.0f)));
	[self setVelocity:launchVector];
	

	
	//remove escape pod
	[self removeEquipmentItem:@"EQ_ESCAPE_POD"];
	
	// set up the standard location where the escape pod will dock.
	target_system_seed = system_seed;			// we're staying in this system
	[self setDockTarget:[UNIVERSE station]];	// we're docking at the main station, if there is one
	
	[self doScriptEvent:OOJSID("shipLaunchedEscapePod") withArgument:escapePod];	// no player.ship properties should be available to script

	// reset legal status
	[self setBounty:0 withReason:kOOLegalStatusReasonEscapePod];
	bounty = 0;

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

	// reset trumbles
	if (trumbleCount != 0)  trumbleCount = 1;
	
	// remove cargo
	[cargo removeAllObjects];
	
	energy = 25;
	[UNIVERSE addMessage:DESC(@"escape-sequence") forCount:4.5];
	[self resetShotTime];
	
	// need to zero out all facings shot_times too, otherwise we may end up
	// with a broken escape pod sequence - Nikos 20100909
	forward_shot_time = 0.0;
	aft_shot_time = 0.0;
	port_shot_time = 0.0;
	starboard_shot_time = 0.0;
	
	[escapePod release];
	
	return doppelganger;
}


- (OOCommodityType) dumpCargo
{
	if (flightSpeed > 4.0 * maxFlightSpeed)
	{
		[UNIVERSE addMessage:DESC(@"hold-locked") forCount:3.0];
		return COMMODITY_UNDEFINED;
	}

	OOCommodityType result = [super dumpCargo];
	if (result != COMMODITY_UNDEFINED)
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-ejected") ,[UNIVERSE displayNameForCommodity:result]] forCount:3.0 forceDisplay:YES];
		[self playCargoJettisioned];
	}
	return result;
}


- (void) rotateCargo
{
	NSInteger i, n_cargo = [cargo count];
	if (n_cargo == 0)  return;
	
	ShipEntity *pod = (ShipEntity *)[[cargo objectAtIndex:0] retain];
	OOCommodityType current_contents = [pod commodityType];
	OOCommodityType contents;
	NSInteger rotates = 0;
	
	do
	{
		[cargo removeObjectAtIndex:0];	// take it from the eject position
		[cargo addObject:pod];	// move it to the last position
		[pod release];
		pod = (ShipEntity*)[[cargo objectAtIndex:0] retain];
		contents = [pod commodityType];
		rotates++;
	} while ((contents == current_contents)&&(rotates < n_cargo));
	[pod release];
	
	if (contents != CARGO_NOT_CARGO)
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-ready-to-eject"), [UNIVERSE displayNameForCommodity:contents]] forCount:3.0];
	}
	else
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"ready-to-eject-@") ,[pod name]] forCount:3.0];
	}
	// now scan through the remaining 1..(n_cargo - rotates) places moving similar cargo to the last place
	// this means the cargo gets to be sorted as it is rotated through
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
	[self setBounty:amount withReason:kOOLegalStatusReasonUnknown];
}


- (void) setBounty:(OOCreditsQuantity)amount withReason:(OOLegalStatusReason)reason
{
	NSString *nReason = OOStringFromLegalStatusReason(reason);
	[self setBounty:amount withReasonAsString:nReason];
}


- (void) setBounty:(OOCreditsQuantity)amount withReasonAsString:(NSString *)reason
{
	JSContext *context = OOJSAcquireContext();
	
	jsval amountVal = JSVAL_VOID;
	int amountVal2 = (int)amount-(int)legalStatus;
	JS_NewNumberValue(context, amountVal2, &amountVal);

	legalStatus = (int)amount; // can't set the new bounty until the size of the change is known

	jsval reasonVal = OOJSValueFromNativeObject(context,reason);
		
	ShipScriptEvent(context, self, "shipBountyChanged", amountVal, reasonVal);
		
	OOJSRelinquishContext(context);
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
	[self markAsOffender:offence_value withReason:kOOLegalStatusReasonUnknown];
}


- (void) markAsOffender:(int)offence_value withReason:(OOLegalStatusReason)reason
{
	if (![self isCloaked])
	{
		JSContext *context = OOJSAcquireContext();
	
		jsval amountVal = JSVAL_VOID;
		int amountVal2 = (legalStatus | offence_value) - legalStatus;
		JS_NewNumberValue(context, amountVal2, &amountVal);

		legalStatus |= offence_value; // can't set the new bounty until the size of the change is known

		jsval reasonVal = OOJSValueFromLegalStatusReason(context, reason);
		
		ShipScriptEvent(context, self, "shipBountyChanged", amountVal, reasonVal);
		
		OOJSRelinquishContext(context);

	}
}


- (void) collectBountyFor:(ShipEntity *)other
{
	if (other == nil || [other isSubEntity])  return;
	
	if (other == [UNIVERSE station])
	{
		// there is no way the player can destroy the main station
		// and so the explosion will be cancelled, so there shouldn't
		// be a kill award
		return;
	}

	if ([self isCloaked])
	{
		// no-one knows about it; no award
		return;
	}

	OOCreditsQuantity	score = 10 * [other bounty];
	OOScanClass			killClass = [other scanClass]; // **tgape** change (+line)
	BOOL				killAward = [other countsAsKill];
	
	if ([other isPolice])   // oops, we shot a copper!
	{
		[self markAsOffender:64 withReason:kOOLegalStatusReasonAttackedPolice];
	}
	
	BOOL killIsCargo = ((killClass == CLASS_CARGO) && ([other commodityAmount] > 0) && ![other isHulk]);
	if ((killIsCargo) || (killClass == CLASS_BUOY) || (killClass == CLASS_ROCK))
	{
		// EMMSTRAN: no killaward (but full bounty) for tharglets?
		if (![other hasRole:@"tharglet"])	// okay, we'll count tharglets as proper kills
		{
			score /= 10;	// reduce bounty awarded
			killAward = NO;	// don't award a kill
		}
	}
	
	credits += score;
	
	if (score > 9)
	{
		NSString *bonusMsg = [NSString stringWithFormat:DESC(@"bounty-@-total-@"), OOCredits(score), OOCredits(credits)];
		
		[UNIVERSE addDelayedMessage:bonusMsg forCount:6 afterDelay:0.15];
	}
	
	if (killAward)
	{
		ship_kills++;
		if ((ship_kills % 256) == 0)
		{
			// congratulations method needs to be delayed a fraction of a second
			[UNIVERSE addDelayedMessage:DESC(@"right-on-commander") forCount:4 afterDelay:0.2];
		}
	}
}


- (BOOL) takeInternalDamage
{
	unsigned n_cargo = [self maxAvailableCargoSpace];
	unsigned n_mass = [self mass] / 10000;
	unsigned n_considered = (n_cargo + n_mass) * ship_trade_in_factor / 100; // a lower value of n_considered means more vulnerable to damage.
	unsigned damage_to = n_considered ? (ranrot_rand() % n_considered) : 0;	// n_considered can be 0 for small ships.
	BOOL     result = NO;
	// cargo damage
	if (damage_to < [cargo count])
	{
		ShipEntity* pod = (ShipEntity*)[cargo objectAtIndex:damage_to];
		NSString* cargo_desc = [UNIVERSE displayNameForCommodity:[pod commodityType]];
		if (!cargo_desc)
			return NO;
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-destroyed"), cargo_desc] forCount:4.5];
		[cargo removeObject:pod];
		return YES;
	}
	else
	{
		damage_to = n_considered - (damage_to + 1);	// reverse the die-roll
	}
	// equipment damage
	NSEnumerator *eqEnum = [self equipmentEnumerator];
	OOEquipmentType	*eqType = nil;
	NSString		*system_key;
	unsigned damageableCounter = 0;
	GLfloat damageableOdds = 0.0;
	while ((system_key = [eqEnum nextObject]) != nil)
	{
		eqType = [OOEquipmentType equipmentTypeWithIdentifier:system_key];
		if ([eqType canBeDamaged])
		{
			damageableCounter++;
			damageableOdds += [eqType damageProbability];
		}
	}

	if (damage_to < damageableCounter)
	{
		GLfloat target = randf() * damageableOdds;
		GLfloat accumulator = 0.0;
		eqEnum = [self equipmentEnumerator];
		while ((system_key = [eqEnum nextObject]) != nil)
		{
			eqType = [OOEquipmentType equipmentTypeWithIdentifier:system_key];
			accumulator += [eqType damageProbability];
			if (accumulator > target) 
			{
				[system_key retain];
				break;
			}
		}
		if (system_key == nil)
		{
			[system_key release];
			return NO;
		}

		NSString		*system_name = [eqType name];
		if (![eqType canBeDamaged] || system_name == nil)
		{
			[system_key release];
			return NO;
		}

		// set the following so removeEquipment works on the right entity
		[self setScriptTarget:self];
		[UNIVERSE clearPreviousMessage];
		[self removeEquipmentItem:system_key];

		NSString *damagedKey = [NSString stringWithFormat:@"%@_DAMAGED", system_key];
		[self addEquipmentItem:damagedKey withValidation: NO inContext:@"damage"];	// for possible future repair.
		[self doScriptEvent:OOJSID("equipmentDamaged") withArgument:system_key];
			
		if (![self hasEquipmentItem:system_name] && [self hasEquipmentItem:damagedKey])
		{
			/*
				Display "foo damaged" message only if no script has
				repaired or removed the equipment item. (If a script does
				either of those and wants a message, it can write it
				itself.)
			*/
			[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-damaged"), system_name] forCount:4.5];
		}
		
		// if Docking Computers have been selected to take damage and they happen to be on, switch them off
		if ([system_key isEqualToString:@"EQ_DOCK_COMP"] && autopilot_engaged)  
		{
			[self disengageAutopilot];
		}
		[system_key release];
		return YES;
	}
	//cosmetic damage
	if (((damage_to & 7) == 7)&&(ship_trade_in_factor > 75))
	{
		ship_trade_in_factor--;
		result = YES;
	}
	return result;
}


- (void) getDestroyedBy:(Entity *)whom damageType:(OOShipDamageType)type
{
	if ([self isDocked])  return;	// Can't die while docked. (Doing so would cause breakage elsewhere.)
	
	OOLog(@"player.ship.damage",  @"Player destroyed by %@ due to %@", whom, OOStringFromShipDamageType(type));	
	
	if (![[UNIVERSE gameController] playerFileToLoad])
	{
		[[UNIVERSE gameController] setPlayerFileToLoad: save_path];	// make sure we load the correct game
	}
	
	energy = 0.0f;
	afterburner_engaged = NO;
	[self disengageAutopilot];

	[UNIVERSE setDisplayText:NO];
	[UNIVERSE setViewDirection:VIEW_AFT];
	
	// Let scripts know the player died.
	[self noteKilledBy:whom damageType:type]; // called before exploding, consistant with npc ships.
	
	[self becomeLargeExplosion:4.0]; // also sets STATUS_DEAD
	[self moveForward:100.0];
	
	flightSpeed = 160.0f;
	velocity = kZeroVector;
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightYaw = 0.0;
	[[UNIVERSE messageGUI] clear];		// No messages for the dead.
	[self suppressTargetLost];			// No target lost messages when dead.
	[self playGameOver];
	[UNIVERSE setBlockJSPlayerShipProps:YES];	// Treat JS player as stale entity.
	[self removeAllEquipment];			// No scooping / equipment damage when dead.
	[self loseTargetStatus];
	[self showGameOver];
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
				[ship noteLostTarget];
			}
		}
	}
	for (i = 0; i < ent_count; i++)
	{
		[my_entities[i] release];		//	released
	}
}


- (BOOL) endScenario:(NSString *)key
{
	if (scenarioKey != nil && [key isEqualToString:scenarioKey])
	{
		[self setStatus:STATUS_RESTART_GAME];
		return YES;
	}
	return NO;
}


- (void) enterDock:(StationEntity *)station
{
	NSParameterAssert(station != nil);
	if ([self status] == STATUS_DEAD)  return;
	
	OOProfilerStartMarker(@"dock");
	
	[self setStatus:STATUS_DOCKING];
	[self setDockedStation:station];
	[self doScriptEvent:OOJSID("shipWillDockWithStation") withArgument:station];
	
	ident_engaged = NO;
	afterburner_engaged = NO;
	autopilot_engaged = NO;
	[self resetAutopilotAI];
	
	cloaking_device_active = NO;
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	[self safeAllMissiles];
	DESTROY(_primaryTarget); // must happen before showing break_pattern to supress active reticule.
	[self clearTargetMemory];
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0f;
	[UNIVERSE setDisplayText:NO];
	[[UNIVERSE gameController] setMouseInteractionModeForFlight];
	if ([self status] == STATUS_LAUNCHING)  return; // a JS script has aborted the docking.
	
	[self setOrientation: kIdentityQuaternion];	// reset orientation to dock
	[UNIVERSE setUpBreakPattern:[self breakPatternPosition] orientation:orientation forDocking:YES];
	[self playDockWithStation];
	[station noteDockedShip:self];
	
	[[UNIVERSE gameView] clearKeys];	// try to stop key bounces
}


- (void) docked
{
	OOProfilerPointMarker(@"-docked called");
	
	StationEntity *dockedStation = [self dockedStation];
	if (dockedStation == nil)
	{
		[self setStatus:STATUS_IN_FLIGHT];
		return;
	}
	
	[self setStatus:STATUS_DOCKED];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	
	[self loseTargetStatus];
	
	[self setPosition:[dockedStation position]];
	[self setOrientation:kIdentityQuaternion];	// reset orientation to dock
	
	flightRoll = 0.0f;
	flightPitch = 0.0f;
	flightYaw = 0.0f;
	flightSpeed = 0.0f;
	
	hyperspeed_engaged = NO;
	hyperspeed_locked = NO;
	
	forward_shield =	[self maxForwardShieldLevel];
	aft_shield =		[self maxAftShieldLevel];
	energy =			maxEnergy;
	weapon_temp =		0.0f;
	ship_temperature =	60.0f;

	[self setAlertFlag:ALERT_FLAG_DOCKED to:YES];

	if ([dockedStation localMarket] == nil)
	{
		[dockedStation initialiseLocalMarketWithRandomFactor:market_rnd];
	}

	NSString *escapepodReport = [self processEscapePods];
	[self addMessageToReport:escapepodReport];
	
	[self unloadCargoPods];	// fill up the on-ship commodities before...

	// check contracts
	NSString *passengerAndCargoReport = [self checkPassengerContracts]; // Is also processing cargo and parcel contracts.
	[self addMessageToReport:passengerAndCargoReport];
		
	[UNIVERSE setDisplayText:YES];
	
	[[OOMusicController sharedController] stopDockingMusic];
	[[OOMusicController sharedController] playDockedMusic];
	
	// Did we fail to observe traffic control regulations? However, due to the state of emergency,
	// apply no unauthorized docking penalties if a nova is ongoing.
	if ([dockedStation requiresDockingClearance] &&
			![self clearedToDock] && ![[UNIVERSE sun] willGoNova])
	{
		[self penaltyForUnauthorizedDocking];
	}
		
	// apply any pending fines. (No need to check gui_screen as fines is no longer an on-screen message).
	if (dockedStation == [UNIVERSE station])
	{
		// TODO: A proper system to allow some OXP stations to have a
		// galcop presence for fines. - CIM 18/11/2012
		if (being_fined && ![[UNIVERSE sun] willGoNova] && ![dockedStation suppressArrivalReports]) [self getFined];
	}

	// it's time to check the script - can trigger legacy missions
	if (gui_screen != GUI_SCREEN_MISSION)  [self checkScript]; // a scripted pilot could have created a mission screen.
	
	OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
	[self doScriptEvent:OOJSID("shipDockedWithStation") withArgument:dockedStation];
	OOJSStopTimeLimiter();
	if ([self status] == STATUS_LAUNCHING) return;

	// if we've not switched to the mission screen yet then proceed normally..
	if (gui_screen != GUI_SCREEN_MISSION)
	{
		[self setGuiToStatusScreen];
	}
	[[OOCacheManager sharedCache] flush];
	[[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];
	
	// When a mission screen is started, any on-screen message is removed immediately.
	[self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")];	// also displays docking reports first.
	
	OOProfilerEndMarker(@"dock");
}


- (void) leaveDock:(StationEntity *)station
{
	if (station == nil)  return;
	NSParameterAssert(station == [self dockedStation]);
	
	OOProfilerStartMarker(@"undock");
	
	// ensure we've not left keyboard entry on
	[[UNIVERSE gameView] allowStringInput: NO];
	
	if (gui_screen == GUI_SCREEN_MISSION)
	{
		[[UNIVERSE gui] clearBackground];
		if (_missionWithCallback)
		{
			[self doMissionCallback];
		}
		// notify older scripts, but do not trigger missionScreenOpportunity.
		[self doWorldEventUntilMissionScreen:OOJSID("missionScreenEnded")];
	}
	
	if (station == [UNIVERSE station])
	{
		// 'leaving with those guns were you sir?'
		OOCreditsQuantity oldbounty = [self bounty];
		[self markAsOffender:[UNIVERSE legalStatusOfManifest:shipCommodityData] withReason:kOOLegalStatusReasonIllegalExports];
		if ([self bounty] > oldbounty)
		{
			[self addRoleToPlayer:@"trader-smuggler"];
		}
	}
	OOGUIScreenID	oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_MAIN;
	[self noteGUIDidChangeFrom:oldScreen to:gui_screen];

	[self loadCargoPods];
	// do not do anything that calls JS handlers between now and calling
	// [station launchShip] below, or the cargo returned by JS may be off
	// CIM - 3.2.2012
	
	// clear the way
	[station autoDockShipsOnApproach];
	[station clearDockingCorridor];

//	[self setAlertFlag:ALERT_FLAG_DOCKED to:NO];
	[self clearAlertFlags];
	[self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0f;
	currentWeaponFacing = WEAPON_FACING_FORWARD;
	
	[self clearTargetMemory];
	[self setShowDemoShips:NO];
	[UNIVERSE setDisplayText:NO];
	[[UNIVERSE gameController] setMouseInteractionModeForFlight];

	[[UNIVERSE gameView] clearKeys];	// try to stop keybounces
	
	[[OOMusicController sharedController] stop];

	[UNIVERSE forceWitchspaceEntries];
	ship_clock_adjust += 600.0;			// 10 minutes to leave dock
	velocity = kZeroVector; // just in case

	[station launchShip:self];

	launchRoll = -flightRoll; // save the station's spin. (inverted for player)
	flightRoll = 0; // don't spin when showing the break pattern.
	[UNIVERSE setUpBreakPattern:[self breakPatternPosition] orientation:orientation forDocking:YES];

	[self setDockedStation:nil];
	
	suppressAegisMessages = YES;
	[self checkForAegis];
	suppressAegisMessages = NO;
	ident_engaged = NO;
	
	[UNIVERSE removeDemoShips];
	// MKW - ensure GUI Screen ship is removed
	[demoShip release];
	demoShip = nil;
	
	OOProfilerEndMarker(@"undock");
	
	[self playLaunchFromStation];
}


- (void) witchStart
{
	OOProfilerStartMarker(@"witchspace");
	
	// chances of entering witchspace with autopilot on are very low, but as Berlios bug #18307 has shown us, entirely possible
	// so in such cases we need to ensure that at least the docking music stops playing
	if (autopilot_engaged)  [self disengageAutopilot];
	
	[self safeAllMissiles];
	[UNIVERSE setViewDirection:VIEW_FORWARD];
	currentWeaponFacing = WEAPON_FACING_FORWARD;

	[self transitionToAegisNone];
	suppressAegisMessages=YES;
	hyperspeed_engaged = NO;
	
	if ([self primaryTarget] != nil)
	{
		[self noteLostTarget];	// losing target? Fire lost target event!
		DESTROY(_primaryTarget);
	}
	
	[hud setScannerZoom:1.0];
	scanner_zoom_rate = 0.0f;
	[UNIVERSE setDisplayText:NO];
	
	if ( ![self wormhole] && !galactic_witchjump)	// galactic hyperspace does not generate a wormhole
	{
		OOLog(kOOLogInconsistentState, @"Internal Error : Player entering witchspace with no wormhole.");
	}
	[UNIVERSE allShipsDoScriptEvent:OOJSID("playerWillEnterWitchspace") andReactToAIMessage:@"PLAYER WITCHSPACE"];
	
	// set the new market seed now!
	// reseeding the RNG should be completely unnecessary here
//	ranrot_srand((uint32_t)[[NSDate date] timeIntervalSince1970]);	// seed randomiser by time
	market_rnd = ranrot_rand() & 255;						// random factor for market values is reset
}


- (void) witchEnd
{
	[UNIVERSE setSystemTo:system_seed];
	galaxy_coordinates.x = system_seed.d;
	galaxy_coordinates.y = system_seed.b;
	[UNIVERSE setUpUniverseFromWitchspace];
	[[UNIVERSE planet] update: 2.34375 * market_rnd];	// from 0..10 minutes
	[[UNIVERSE station] update: 2.34375 * market_rnd];	// from 0..10 minutes
	
	OOProfilerEndMarker(@"witchspace");
}


- (BOOL) witchJumpChecklist:(BOOL)isGalacticJump
{
	// Perform this check only when doing the actual jump
	if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
	{
		// check nearby masses
		//UPDATE_STAGE(@"checking for mass blockage");
		ShipEntity* blocker = [UNIVERSE entityForUniversalID:[self checkShipsInVicinityForWitchJumpExit]];
		if (blocker)
		{
			[UNIVERSE clearPreviousMessage];
			[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"witch-blocked-by-@"), [blocker name]] forCount: 4.5];
			[self playWitchjumpBlocked];
			[self setStatus:STATUS_IN_FLIGHT];
			ShipScriptEventNoCx(self, "playerJumpFailed", OOJSSTR("blocked"));
			return NO;
		}
	}

	// For galactic hyperspace jumps we skip the remaining checks
	if (isGalacticJump)
	{
		return YES;
	}

	// Check we're not jumping into the current system
	if (!([UNIVERSE inInterstellarSpace]) && equal_seeds(system_seed,target_system_seed))
	{
		//dont allow player to hyperspace to current location.
		//Note interstellar space will have a system_seed place we came from
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:DESC(@"witch-no-target") forCount: 4.5];
		if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
		{
			[self playWitchjumpInsufficientFuel];
			[self setStatus:STATUS_IN_FLIGHT];
			ShipScriptEventNoCx(self, "playerJumpFailed", OOJSSTR("no target"));
		}
		else  [self playHyperspaceNoTarget];

		return NO;
	}

	// check max distance permitted
	if ([self hyperspaceJumpDistance] > [self maxHyperspaceDistance])
	{
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:DESC(@"witch-too-far") forCount: 4.5];
		if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
		{
			[self playWitchjumpDistanceTooGreat];
			[self setStatus:STATUS_IN_FLIGHT];
			ShipScriptEventNoCx(self, "playerJumpFailed", OOJSSTR("too far"));
		}
		else  [self playHyperspaceDistanceTooGreat];
		
		return NO;
	}

	// check fuel level
	if (![self hasSufficientFuelForJump])
	{
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:DESC(@"witch-no-fuel") forCount: 4.5];
		if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
		{
			[self playWitchjumpInsufficientFuel];
			[self setStatus:STATUS_IN_FLIGHT];
			ShipScriptEventNoCx(self, "playerJumpFailed", OOJSSTR("insufficient fuel"));
		}
		else  [self playHyperspaceNoFuel];
		
		return NO;
	}

	// All checks passed
	return YES;
}

- (void) setJumpType:(BOOL)isGalacticJump
{
	if (isGalacticJump)
	{
		galactic_witchjump = YES;
	}
	else
	{
		galactic_witchjump = NO;
	}
}

- (double) hyperspaceJumpDistance
{
	return distanceBetweenPlanetPositions(target_system_seed.d,target_system_seed.b,galaxy_coordinates.x,galaxy_coordinates.y);
}


- (OOFuelQuantity) fuelRequiredForJump
{
	return 10.0 * MAX(0.1, [self hyperspaceJumpDistance]);
}


- (BOOL) hasSufficientFuelForJump
{
	return fuel >= [self fuelRequiredForJump];
}


- (void) noteCompassLostTarget
{
	if ([[self hud] isCompassActive])
	{
		// "the compass, it says we're lost!" :)
		JSContext *context = OOJSAcquireContext();
		jsval jsmode = OOJSValueFromCompassMode(context, [self compassMode]);
		ShipScriptEvent(context, self, "compassTargetChanged", JSVAL_VOID, jsmode);
		OOJSRelinquishContext(context);
		
		[[self hud] setCompassActive:NO];	// ensure a target change when returning to normal space.
	}
}


- (void) enterGalacticWitchspace
{
	if (![self witchJumpChecklist:true])
		return;

	[self setStatus:STATUS_ENTERING_WITCHSPACE];
	ShipScriptEventNoCx(self, "shipWillEnterWitchspace", OOJSSTR("galactic jump"));
	[self noteCompassLostTarget];
	
	[self witchStart];
	
	[UNIVERSE removeAllEntitiesExceptPlayer];
	
	// clear system data cache for old galaxy
	[UNIVERSE resetSystemDataCache];

	// remove any contracts and parcels for the old galaxy
	if (contracts)
		[contracts removeAllObjects];

	if (parcels)
		[parcels removeAllObjects];
	
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
			NSMutableDictionary* passenger_info = [NSMutableDictionary dictionaryWithDictionary:[passengers oo_dictionaryAtIndex:i]];
			[passenger_info setObject:[NSNumber numberWithDouble:ship_clock] forKey:CONTRACT_KEY_ARRIVAL_TIME];
			[passengers replaceObjectAtIndex:i withObject:passenger_info];
		}
	}

	// clear a lot of memory of player actions
	if (ship_kills >= 6400)
	{
		[self clearRolesFromPlayer:0.25];
	}
	else if (ship_kills >= 2560)
	{
		[self clearRolesFromPlayer:0.5];
	}
	else
	{
		[self clearRolesFromPlayer:0.9];
	}	
	[roleWeightFlags removeAllObjects];
	[roleSystemList removeAllObjects];
	
	[self removeEquipmentItem:@"EQ_GAL_DRIVE"];
	
	galaxy_number++;
	galaxy_number &= 7;

	galaxy_seed.a = rotate_byte_left(galaxy_seed.a);
	galaxy_seed.b = rotate_byte_left(galaxy_seed.b);
	galaxy_seed.c = rotate_byte_left(galaxy_seed.c);
	galaxy_seed.d = rotate_byte_left(galaxy_seed.d);
	galaxy_seed.e = rotate_byte_left(galaxy_seed.e);
	galaxy_seed.f = rotate_byte_left(galaxy_seed.f);

	[UNIVERSE setGalaxySeed:galaxy_seed];

	// Choose the galactic hyperspace behaviour. Refers to where we may actually end up after an intergalactic jump.
	// The default behaviour is that the player cannot arrive on unreachable or isolated systems. The options
	// in planetinfo.plist, galactic_hyperspace_behaviour key can be used to allow arrival even at unreachable systems,
	// or at fixed coordinates on the galactic chart. The key galactic_hyperspace_fixed_coords in planetinfo.plist is
	// used in the fixed coordinates case and specifies the exact coordinates for the intergalactic jump.
	switch (galacticHyperspaceBehaviour)
	{
		case GALACTIC_HYPERSPACE_BEHAVIOUR_FIXED_COORDINATES:			
			system_seed = [UNIVERSE findSystemAtCoords:galacticHyperspaceFixedCoords withGalaxySeed:galaxy_seed];
			break;
		case GALACTIC_HYPERSPACE_BEHAVIOUR_ALL_SYSTEMS_REACHABLE:
			system_seed = [UNIVERSE findSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
			break;
		case GALACTIC_HYPERSPACE_BEHAVIOUR_STANDARD:
		default:
			// instead find a system connected to system 0 near the current coordinates...
			system_seed = [UNIVERSE findConnectedSystemAtCoords:galaxy_coordinates withGalaxySeed:galaxy_seed];
			break;
	}
	target_system_seed = system_seed;
	
	[self setBounty:0 withReason:kOOLegalStatusReasonNewGalaxy];	// let's make a fresh start!
	cursor_coordinates.x = system_seed.d;
	cursor_coordinates.y = system_seed.b;
	
	[self witchEnd];
	
	[self doScriptEvent:OOJSID("playerEnteredNewGalaxy") withArgument:[NSNumber numberWithUnsignedInt:galaxy_number]];
}


// now with added misjump goodness!
// If the wormhole generator misjumped, the player's ship misjumps too. Kaks 20110211
- (void) enterWormhole:(WormholeEntity *) w_hole
{
	if ([self status] == STATUS_ENTERING_WITCHSPACE
			|| [self status] == STATUS_EXITING_WITCHSPACE)
	{
		return; // has already entered a different wormhole
	}
	BOOL misjump = [self scriptedMisjump] || [w_hole withMisjump] || flightPitch == max_flight_pitch || randf() > 0.995;
	wormhole = [w_hole retain];
	[self addScannedWormhole:wormhole];
	[self setStatus:STATUS_ENTERING_WITCHSPACE];
	ShipScriptEventNoCx(self, "shipWillEnterWitchspace", OOJSSTR("wormhole"));
	if ([self scriptedMisjump]) 
	{
		misjump = YES; // a script could just have changed this to true;
	}
	if (misjump && [self scriptedMisjumpRange] != 0.5)
	{
		[w_hole setMisjumpWithRange:[self scriptedMisjumpRange]]; // overrides wormholes, if player also had non-default scriptedMisjumpRange
	}
	[self witchJumpTo:[w_hole destination] misjump:misjump];
}


- (void) enterWitchspace
{
	if (![self witchJumpChecklist:false])  return;
	
	//  perform any check here for forced witchspace encounters
	unsigned malfunc_chance = 253;
	if (ship_trade_in_factor < 80)
		    malfunc_chance -= (1 + ranrot_rand() % (81-ship_trade_in_factor)) / 2;	// increase chance of misjump in worn-out craft

	BOOL malfunc = ((ranrot_rand() & 0xff) > malfunc_chance);
	// 75% of the time a malfunction means a misjump
	BOOL misjump = [self scriptedMisjump] || (flightPitch == max_flight_pitch) || (malfunc && (randf() > 0.75));

	if (malfunc && !misjump)
	{
		// some malfunctions will start fuel leaks, some will result in no witchjump at all.
		if ([self takeInternalDamage])  // Depending on ship type and loaded cargo, this will be true for 20 - 50% of the time.
		{
			[self playWitchjumpFailure];
			[self setStatus:STATUS_IN_FLIGHT];
			ShipScriptEventNoCx(self, "playerJumpFailed", OOJSSTR("malfunction"));
			return;
		}
		else
		{
			[self setFuelLeak:[NSString stringWithFormat:@"%f", (randf() + randf()) * 5.0]];
		}
	}
	
	// From this point forward we are -definitely- witchjumping
	
	// burn the full fuel amount to create the wormhole
	fuel -= [self fuelRequiredForJump];
	
	// Create the players' wormhole
	wormhole = [[WormholeEntity alloc] initWormholeTo:target_system_seed fromShip:self];
	[UNIVERSE addEntity:wormhole]; // Add new wormhole to Universe to let other ships target it. Required for ships following the player.
	[self addScannedWormhole:wormhole];
	
	[self setStatus:STATUS_ENTERING_WITCHSPACE];
	ShipScriptEventNoCx(self, "shipWillEnterWitchspace", OOJSSTR("standard jump"));

	[self updateSystemMemory];
	NSUInteger legality = [self legalStatusOfCargoList];
	OOCargoQuantity maxSpace = [self maxAvailableCargoSpace];
	OOCargoQuantity availSpace = [self availableCargoSpace];
	if ([roleWeightFlags objectForKey:@"bought-legal"])
	{
		if (maxSpace != availSpace)
		{
			[self addRoleToPlayer:@"trader"];
			if (maxSpace - availSpace > 20 || availSpace == 0)
			{
				if (legality == 0)
				{
					[self addRoleToPlayer:@"trader"];
				}
			}
		}
	}
	if ([roleWeightFlags objectForKey:@"bought-illegal"])
	{
		if (maxSpace != availSpace && legality > 0)
		{
			[self addRoleToPlayer:@"trader-smuggler"];
			if (maxSpace - availSpace > 20 || availSpace == 0)
			{
				if (legality >= 20 || legality >= maxSpace)
				{
					[self addRoleToPlayer:@"trader-smuggler"];
				}
			}
		}
	}
	[roleWeightFlags removeAllObjects];

	[self noteCompassLostTarget];
	if ([self scriptedMisjump]) 
	{
		misjump = YES; // a script could just have changed this to true;
	}
	if (misjump)
	{
		[wormhole setMisjumpWithRange:[self scriptedMisjumpRange]];
	}
	[self witchJumpTo:target_system_seed misjump:misjump];
}


- (void) witchJumpTo:(Random_Seed)sTo misjump:(BOOL)misjump
{
	[self witchStart];

	//wear and tear on all jumps (inc misjumps, failures, and wormholes)
	if (2 * market_rnd < ship_trade_in_factor)
	{
		// every eight jumps or so drop the price down towards 75%
		[self adjustTradeInFactorBy:-(1 + (market_rnd & 3))];
	}
	
	// set clock after "playerWillEnterWitchspace" and before  removeAllEntitiesExceptPlayer, to allow escorts time to follow their mother. 
	double distance = distanceBetweenPlanetPositions(sTo.d,sTo.b,galaxy_coordinates.x,galaxy_coordinates.y);
	
	[UNIVERSE removeAllEntitiesExceptPlayer];
	
	if (!misjump)
	{
		ship_clock_adjust += distance * distance * 3600.0;
		system_seed = sTo;
		[self setBounty:(legalStatus/2) withReason:kOOLegalStatusReasonNewSystem];	// 'another day, another system'
		[self witchEnd];
		if (market_rnd < 8) [self erodeReputation];		// every 32 systems or so, drop back towards 'unknown'
	}
	else
	{
		// Misjump: move halfway there!
		// misjumps do not change legal status.
		if (randf() < 0.1) [self erodeReputation];		// once every 10 misjumps - should be much rarer than successful jumps!

		[wormhole setMisjump]; 
		// just in case, but this has usually been set already

		// and now the wormhole has travel time and coordinates calculated
		// so rather than duplicate the calculation we'll just ask it...
		NSPoint dest = [wormhole destinationCoordinates];
		galaxy_coordinates.x = dest.x;
		galaxy_coordinates.y = dest.y;

		ship_clock_adjust += [wormhole travelTime];

		[self playWitchjumpMisjump];
		[UNIVERSE setUpUniverseFromMisjump];
	}
}


- (void) leaveWitchspace
{
	float		d1 = (float)(SCANNER_MAX_RANGE*((Ranrot() & 255)/256.0 - 0.5));
	HPVector		pos = [UNIVERSE getWitchspaceExitPosition];		// no need to reset the PRNG
	Quaternion	q1;
	HPVector		whpos, exitpos;

	GLfloat min_d1 = [UNIVERSE safeWitchspaceExitDistance];
	quaternion_set_random(&q1);
	if (abs((int)d1) < min_d1)
	{
		d1 += ((d1 > 0.0)? min_d1: -min_d1); // not too close to the buoy.
	}
	HPVector		v1 = HPvector_forward_from_quaternion(q1);
	exitpos = HPvector_add(pos, HPvector_multiply_scalar(v1, d1)); // randomise exit position
	position = exitpos;
	[self setOrientation:[UNIVERSE getWitchspaceExitRotation]];

	// While setting the wormhole position to the player position looks very nice for ships following the player, 
	// the more common case of the player following other ships, the player tends to
	// ram the back of the ships, or even jump on top of is when the ship jumped without initial speed, which is messy. 
	// To avoid this problem, a small wormhole displacement is added.
	if (wormhole)	// will be nil for galactic jump
	{
		if ([[wormhole shipsInTransit] count] > 0)
		{
			// player is not allone in his wormhole, synchronise player and wormhole position.
			double	wh_arrival_time = ([PLAYER clockTimeAdjusted] - [wormhole arrivalTime]);
			if (wh_arrival_time > 0)
			{
				// Player is following other ship 
				whpos = HPvector_add(exitpos, vectorToHPVector(vector_multiply_scalar([self forwardVector], 1000.0f)));
				[wormhole setContainsPlayer:YES];
			}
			else
			{
				// Player is the leadship 
				whpos = HPvector_add(exitpos, vectorToHPVector(vector_multiply_scalar([self forwardVector], -500.0f)));
				// so it won't contain the player by the time they exit
				[wormhole setExitSpeed:maxFlightSpeed*WORMHOLE_LEADER_SPEED_FACTOR];
			} 

			HPVector distance = HPvector_subtract(whpos, pos);
			if (HPmagnitude2(distance) < min_d1*min_d1 ) // within safety distance from the buoy?
			{
				// the wormhole is to close to the buoy. Move both player and wormhole away from it in the x-y plane.
				distance.z = 0;
				distance = HPvector_multiply_scalar(HPvector_normal(distance), min_d1);
				whpos = HPvector_add(whpos, distance);
				position = HPvector_add(position, distance);
			}
			[wormhole setExitPosition: whpos];
		}
		else
		{
			// no-one else in the wormhole
			[wormhole setExitSpeed:maxFlightSpeed*WORMHOLE_LEADER_SPEED_FACTOR];
		}
	}

	/* there's going to be a slight pause at this stage anyway;
	 * there's also going to be a lot of stale ship scripts. Force a
	 * garbage collection while we have chance. - CIM */
	[[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];

	flightSpeed = wormhole ? [wormhole exitSpeed] : fmin(maxFlightSpeed,50.0f);
	[wormhole release];	// OK even if nil
	wormhole = nil;

	flightRoll = 0.0f;
	flightPitch = 0.0f;
	flightYaw = 0.0f;

	velocity = kZeroVector;
	[self setStatus:STATUS_EXITING_WITCHSPACE];
	gui_screen = GUI_SCREEN_MAIN;
	being_fined = NO;				// until you're scanned by a copper!
	[self clearTargetMemory];
	[self setShowDemoShips:NO];
	[[UNIVERSE gameController] setMouseInteractionModeForFlight];
	[UNIVERSE setDisplayText:NO];
	[UNIVERSE setWitchspaceBreakPattern:YES];
	[self playExitWitchspace];
	if ([self currentSystemID] >= 0)
	{
		if (![roleSystemList containsObject:[NSNumber numberWithInt:[self currentSystemID]]])
		{
			// going somewhere new?
			[self clearRoleFromPlayer:NO];
		}
	}
	[self doScriptEvent:OOJSID("shipWillExitWitchspace")];
	[UNIVERSE setUpBreakPattern:[self breakPatternPosition] orientation:orientation forDocking:NO];
}


///////////////////////////////////

- (void) setGuiToStatusScreen
{
	NSString		*systemName = nil;
	NSString		*targetSystemName = nil;
	NSString		*text = nil;
	
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIScreenID	oldScreen = gui_screen;
	if (oldScreen != GUI_SCREEN_STATUS)
	{
		[self noteGUIWillChangeTo:GUI_SCREEN_STATUS];
	}

	gui_screen = GUI_SCREEN_STATUS;
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
	
	// Both system_seed & target_system_seed are != nil at all times when this function is called.
	
	systemName = [UNIVERSE inInterstellarSpace] ? DESC(@"interstellar-space") : [UNIVERSE getSystemName:system_seed];
	if ([self isDocked] && [self dockedStation] != [UNIVERSE station])
	{
		systemName = [NSString stringWithFormat:@"%@ : %@", systemName, [[self dockedStation] displayName]];
	}

	targetSystemName =	[UNIVERSE getSystemName:target_system_seed];

	// GUI stuff
	{
		NSString			*shipName = [self displayName];
		NSString			*legal_desc = nil, *rating_desc = nil,
							*alert_desc = nil, *fuel_desc = nil,
							*credits_desc = nil;
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 20;
		tab_stops[1] = 160;
		tab_stops[2] = 290;
		[gui setTabStops:tab_stops];
		
		NSString	*lightYearsDesc = DESC(@"status-light-years-desc");
		
		legal_desc = OODisplayStringFromLegalStatus(legalStatus);
		rating_desc = KillCountToRatingAndKillString(ship_kills);
		alert_desc = OODisplayStringFromAlertCondition([self alertCondition]);
		fuel_desc = [NSString stringWithFormat:@"%.1f %@", fuel/10.0, lightYearsDesc];
		credits_desc = OOCredits(credits);
		
		[gui clearAndKeepBackground:!guiChanged];
		text = DESC(@"status-commander-@");
		[gui setTitle:[NSString stringWithFormat:text, [self commanderName]]];
		
		[gui setText:shipName forRow:0 align:GUI_ALIGN_CENTER];
		
		[gui setArray:[NSArray arrayWithObjects:DESC(@"status-present-system"), systemName, nil]	forRow:1];
		if ([self hasHyperspaceMotor]) [gui setArray:[NSArray arrayWithObjects:DESC(@"status-hyperspace-system"), targetSystemName, nil] forRow:2];
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
	
	[[UNIVERSE gameView] clearMouse];
	
	// Contributed by Pleb - show ship model if the appropriate user default key has been set - Nikos 20140127
	if (EXPECT_NOT([[NSUserDefaults standardUserDefaults] boolForKey:@"show-ship-model-in-status-screen"]))
	{
		[UNIVERSE removeDemoShips];
		[self showShipModelWithKey:[self shipDataKey] shipData:nil personality:[self entityPersonalityInt]
									factorX:2.5 factorY:1.7 factorZ:8.0 inContext:@"GUI_SCREEN_STATUS"];
		[self setShowDemoShips:YES];
	}
	else
	{
		[self setShowDemoShips:NO];
	}
	
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	
	if (guiChanged)
	{
		NSDictionary *fgDescriptor = nil, *bgDescriptor = nil;
		if ([self status] == STATUS_DOCKED)
		{
			fgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"docked_overlay"];
			bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"status_docked"];
		}
		else
		{
			fgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"overlay"];
			if (alertCondition == ALERT_CONDITION_RED) bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"status_red_alert"];
			else bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"status_in_flight"];
		}
		
		[gui setForegroundTextureDescriptor:fgDescriptor];
		
		if (bgDescriptor == nil)  bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"status"];
		[gui setBackgroundTextureDescriptor:bgDescriptor];
		
		[gui setStatusPage:0];
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	}
}


- (NSArray *) equipmentList
{
	NSMutableArray		*quip = [NSMutableArray array];
	NSEnumerator		*eqTypeEnum = nil;
	OOEquipmentType		*eqType = nil;
	NSString			*desc = nil;

	for (eqTypeEnum = [OOEquipmentType equipmentEnumerator]; (eqType = [eqTypeEnum nextObject]); )
	{
		if ([eqType isVisible])
		{
			if ([self hasEquipmentItem:[eqType identifier]])
			{
				[quip addObject:[NSArray arrayWithObjects:[eqType name], [NSNumber numberWithBool:YES], nil]];
			}
			else 
			{
				// Check for damaged version
				if ([self hasEquipmentItem:[[eqType identifier] stringByAppendingString:@"_DAMAGED"]])
				{
					desc = [NSString stringWithFormat:DESC(@"equipment-@-not-available"), [eqType name]];
					[quip addObject:[NSArray arrayWithObjects:desc, [NSNumber numberWithBool:NO], nil]];
				}
			}
		}
	}
	
	if (max_passengers > 0)
	{
		desc = [NSString stringWithFormat:DESC_PLURAL(@"equipment-pass-berth-@", max_passengers), max_passengers];
		[quip addObject:[NSArray arrayWithObjects:desc, [NSNumber numberWithBool:YES], nil]];
	}
	
	if (forward_weapon_type > WEAPON_NONE)
	{
		desc = [NSString stringWithFormat:DESC(@"equipment-fwd-weapon-@"),[[OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(forward_weapon_type)] name]];
		[quip addObject:[NSArray arrayWithObjects:desc, [NSNumber numberWithBool:YES], nil]];
	}
	if (aft_weapon_type > WEAPON_NONE)
	{
		desc = [NSString stringWithFormat:DESC(@"equipment-aft-weapon-@"),[[OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(aft_weapon_type)] name]];
		[quip addObject:[NSArray arrayWithObjects:desc, [NSNumber numberWithBool:YES], nil]];
	}
	if (port_weapon_type > WEAPON_NONE)
	{
		desc = [NSString stringWithFormat:DESC(@"equipment-port-weapon-@"),[[OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(port_weapon_type)] name]];
		[quip addObject:[NSArray arrayWithObjects:desc, [NSNumber numberWithBool:YES], nil]];
	}
	if (starboard_weapon_type > WEAPON_NONE)
	{
		desc = [NSString stringWithFormat:DESC(@"equipment-stb-weapon-@"),[[OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(starboard_weapon_type)] name]];
		[quip addObject:[NSArray arrayWithObjects:desc, [NSNumber numberWithBool:YES], nil]];
	}
	
	return quip;
}


- (NSUInteger) primedEquipmentCount
{
	return [eqScripts count];
}


- (NSString *) primedEquipmentName:(NSInteger)offset
{
	NSUInteger c = [self primedEquipmentCount];
	NSUInteger idx = (primedEquipment+offset)%(c+1);
	if (idx == c)
	{
		return DESC(@"equipment-primed-none-hud-label");
	}
	else
	{
		return [[OOEquipmentType equipmentTypeWithIdentifier:[[eqScripts oo_arrayAtIndex:idx] oo_stringAtIndex:0]] name];
	}
}


- (void) activatePrimableEquipment:(NSUInteger)index withMode:(OOPrimedEquipmentMode)mode
{
	// index == [eqScripts count] means we don't want to activate any equipment.
	if(index < [eqScripts count])
	{
		OOJSScript *eqScript = [[eqScripts oo_arrayAtIndex:index] objectAtIndex:1];
		JSContext *context = OOJSAcquireContext();
		NSAssert1(mode <= OOPRIMEDEQUIP_MODE, @"Primable equipment mode %i out of range", (int)mode);
		
		switch (mode)
		{
			case OOPRIMEDEQUIP_MODE:
				[eqScript callMethod:OOJSID("mode") inContext:context withArguments:NULL count:0 result:NULL];
				break;
			case OOPRIMEDEQUIP_ACTIVATED:
				[eqScript callMethod:OOJSID("activated") inContext:context withArguments:NULL count:0 result:NULL];
				break;
		}
		OOJSRelinquishContext(context);
	}

}


- (NSString *) fastEquipmentA
{
	return _fastEquipmentA;
}


- (NSString *) fastEquipmentB
{
	return _fastEquipmentB;
}


- (void) setFastEquipmentA:(NSString *)eqKey
{
	[_fastEquipmentA release];
	_fastEquipmentA = [eqKey copy];
}


- (void) setFastEquipmentB:(NSString *)eqKey
{
	[_fastEquipmentB release];
	_fastEquipmentB = [eqKey copy];
}


- (OOEquipmentType *) weaponTypeForFacing:(OOWeaponFacing)facing strict:(BOOL)strict
{
	OOWeaponType weaponType = WEAPON_NONE;
	
	switch (facing)
	{
		case WEAPON_FACING_FORWARD:
			weaponType = forward_weapon_type;
			break;
			
		case WEAPON_FACING_AFT:
			weaponType = aft_weapon_type;
			break;
			
		case WEAPON_FACING_PORT:
			weaponType = port_weapon_type;
			break;
			
		case WEAPON_FACING_STARBOARD:
			weaponType = starboard_weapon_type;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}

	return [OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(weaponType)];
}


- (NSArray *) missilesList
{
	[self tidyMissilePylons];	// just in case.
	return [super missilesList];
}


- (NSArray *) cargoList
{
	NSMutableArray	*manifest = [NSMutableArray array];
	NSArray			*list = [self cargoListForScripting];
	NSEnumerator	*cargoEnum = nil;
	NSDictionary	*commodity;
	
	if (specialCargo) [manifest addObject:specialCargo];
	
	for (cargoEnum = [list objectEnumerator]; (commodity = [cargoEnum nextObject]); )
	{
		NSString *desc = [commodity oo_stringForKey:@"displayName"];
		NSString *units = [commodity oo_stringForKey:@"unit"];
		[manifest addObject:[NSString stringWithFormat:DESC(@"manifest-cargo-quantity-format"),
							[commodity oo_intForKey:@"quantity"], units, desc]];
	}
	
	return manifest;
}


- (NSArray *) cargoListForScripting
{
	NSMutableArray		*list = [NSMutableArray array];
	
	NSUInteger			i, commodityCount = [shipCommodityData count];
	OOCargoQuantity		quantityInHold[commodityCount];
	
	// following changed to work whether docked or not
	for (i = 0; i < commodityCount; i++)
	{
		quantityInHold[i] = [[shipCommodityData oo_arrayAtIndex:i] oo_unsignedIntAtIndex:MARKET_QUANTITY];
	}
	for (i = 0; i < [cargo count]; i++)
	{
		ShipEntity *container = [cargo objectAtIndex:i];
		quantityInHold[[container commodityType]] += [container commodityAmount];
	}
	
	for (i = 0; i < commodityCount; i++)
	{
		if (quantityInHold[i] > 0)
		{
			NSMutableDictionary	*commodity = [NSMutableDictionary dictionaryWithCapacity:4];
			NSString *symName = [[shipCommodityData oo_arrayAtIndex:i] oo_stringAtIndex:MARKET_NAME];
			// commodity, quantity - keep consistency between .manifest and .contracts
			[commodity setObject:CommodityTypeToString(i) forKey:@"commodity"];
			[commodity setObject:[NSNumber numberWithUnsignedInt:quantityInHold[i]] forKey:@"quantity"];
			[commodity setObject:CommodityDisplayNameForSymbolicName(symName) forKey:@"displayName"]; 
			[commodity setObject:DisplayStringForMassUnitForCommodity(i)forKey:@"unit"]; 
			[list addObject:commodity];
		}
	}

	return [[list copy] autorelease];	// return an immutable copy
}


- (unsigned) legalStatusOfCargoList
{
	NSArray *list = [self cargoListForScripting];
	NSDictionary *entry = nil;
	unsigned penalty = 0;
	NSString *commodity = nil;
	OOCargoQuantity amount;

	foreach (entry, list)
	{
		commodity = [[shipCommodityData oo_arrayAtIndex:StringToCommodityType([entry oo_stringForKey:@"commodity"])] oo_stringAtIndex:MARKET_NAME];
		amount = [entry oo_intForKey:@"quantity"];
		penalty += [UNIVERSE legalStatusOfCommodity:commodity] * amount;
	}
	return penalty;
}


- (NSArray*) contractsListForScriptingFromArray:(NSArray *) contracts_array forCargo:(BOOL)forCargo
{
	NSMutableArray		*result = [NSMutableArray array];
	NSUInteger 			i;

	for (i = 0; i < [contracts_array count]; i++)
	{
		NSMutableDictionary	*contract = [NSMutableDictionary dictionaryWithCapacity:10];
		NSDictionary		*dict = [contracts_array oo_dictionaryAtIndex:i];
		if (forCargo)
		{
			// commodity, quantity - keep consistency between .manifest and .contracts
			[contract setObject:[[UNIVERSE symbolicNameForCommodity:[dict oo_intForKey:CARGO_KEY_TYPE]] lowercaseString] forKey:@"commodity"];
			[contract setObject:[NSNumber numberWithUnsignedInt:[dict oo_intForKey:CARGO_KEY_AMOUNT]] forKey:@"quantity"];
			[contract setObject:[dict oo_stringForKey:CARGO_KEY_DESCRIPTION] forKey:@"description"];
		}
		else
		{
			[contract setObject:[dict oo_stringForKey:PASSENGER_KEY_NAME] forKey:PASSENGER_KEY_NAME];
			[contract setObject:[NSNumber numberWithUnsignedInt:[dict oo_unsignedIntForKey:CONTRACT_KEY_RISK]] forKey:CONTRACT_KEY_RISK]; 
		}
		
		OOSystemID 	planet = [dict oo_intForKey:CONTRACT_KEY_DESTINATION];
		NSString 	*planetName = [UNIVERSE getSystemName: [UNIVERSE systemSeedForSystemNumber:planet]];
		[contract setObject:[NSNumber numberWithUnsignedInt:planet] forKey:CONTRACT_KEY_DESTINATION];
		[contract setObject:planetName forKey:@"destinationName"];
		planet = [dict oo_intForKey:CONTRACT_KEY_START];
		planetName = [UNIVERSE getSystemName: [UNIVERSE systemSeedForSystemNumber:planet]];
		[contract setObject:[NSNumber numberWithUnsignedInt:planet] forKey:CONTRACT_KEY_START];
		[contract setObject:planetName forKey:@"startName"];
		
		int 		dest_eta = [dict oo_doubleForKey:CONTRACT_KEY_ARRIVAL_TIME] - ship_clock;
		[contract setObject:[NSNumber numberWithInt:dest_eta] forKey:@"eta"];
		[contract setObject:[UNIVERSE shortTimeDescription:dest_eta] forKey:@"etaDescription"];
		[contract setObject:[NSNumber numberWithInt:[dict oo_intForKey:CONTRACT_KEY_PREMIUM]] forKey:CONTRACT_KEY_PREMIUM]; 
		[contract setObject:[NSNumber numberWithInt:[dict oo_intForKey:CONTRACT_KEY_FEE]] forKey:CONTRACT_KEY_FEE]; 
		[result addObject:contract];
	}

	return [[result copy] autorelease];	// return an immutable copy
}


- (NSArray *) passengerListForScripting
{
	return [self contractsListForScriptingFromArray:passengers forCargo:NO];
}


- (NSArray *) parcelListForScripting
{
	return [self contractsListForScriptingFromArray:parcels forCargo:NO];
}


- (NSArray *) contractListForScripting
{
	return [self contractsListForScriptingFromArray:contracts forCargo:YES];
}


- (void) setGuiToSystemDataScreen
{
	NSDictionary	*targetSystemData;
	NSString		*targetSystemName;
	
	targetSystemData = [[UNIVERSE generateSystemData:target_system_seed] retain];  // retained
	targetSystemName = [targetSystemData oo_stringForKey:KEY_NAME];
	
	BOOL			sunGoneNova = ([targetSystemData oo_boolForKey:@"sun_gone_nova"]);
	OOGUIScreenID	oldScreen = gui_screen;
	
	GuiDisplayGen	*gui = [UNIVERSE gui];
	gui_screen = GUI_SCREEN_SYSTEM_DATA;
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
	
	// GUI stuff
	{
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 96;
		tab_stops[2] = 144;
		[gui setTabStops:tab_stops];
		
		int techlevel =		[targetSystemData oo_intForKey:KEY_TECHLEVEL];
		int population =	[targetSystemData oo_intForKey:KEY_POPULATION];
		int productivity =	[targetSystemData oo_intForKey:KEY_PRODUCTIVITY];
		int radius =		[targetSystemData oo_intForKey:KEY_RADIUS];
		
		NSString	*government_desc =	OODisplayStringFromGovernmentID([targetSystemData oo_intForKey:KEY_GOVERNMENT]);
		NSString	*economy_desc =		OODisplayStringFromEconomyID([targetSystemData oo_intForKey:KEY_ECONOMY]);
		NSString	*inhabitants =		[targetSystemData oo_stringForKey:KEY_INHABITANTS];
		NSString	*system_desc =		[targetSystemData oo_stringForKey:KEY_DESCRIPTION];
		
		if (sunGoneNova)
		{
			population = 0;
			productivity = 0;
			radius = 0;
			techlevel = -1;	// So it dispalys as 0 on the system info screen
			government_desc = DESC(@"nova-system-government");
			economy_desc = DESC(@"nova-system-economy");
			inhabitants = DESC(@"nova-system-inhabitants");
			system_desc = OOExpandKeyWithSeed(@"nova-system-description", target_system_seed, nil);
		}
		
		[gui clearAndKeepBackground:!guiChanged];
		[UNIVERSE removeDemoShips];
		
		[gui setTitle:[NSString stringWithFormat:DESC(@"sysdata-planet-name-@"),   targetSystemName]];
		
		[gui setArray:[NSArray arrayWithObjects:DESC(@"sysdata-eco"), economy_desc, nil]					forRow:1];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"sysdata-govt"), government_desc, nil]				forRow:3];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"sysdata-tl"), [NSString stringWithFormat:@"%d", techlevel + 1], nil]	forRow:5];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"sysdata-pop"), [NSString stringWithFormat:@"%.1f %@", 0.1*population, DESC(@"sysdata-billion-word")], nil]	forRow:7];
		[gui setArray:[NSArray arrayWithObjects:@"", [NSString stringWithFormat:@"(%@)", inhabitants], nil]				forRow:8];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"sysdata-prod"), @"", [NSString stringWithFormat:DESC(@"sysdata-prod-worth"), productivity], nil]	forRow:10];
		[gui setArray:[NSArray arrayWithObjects:DESC(@"sysdata-radius"), @"", [NSString stringWithFormat:@"%5d km", radius], nil]	forRow:12];
		
		OOGUIRow i = [gui addLongText:system_desc startingAtRow:15 align:GUI_ALIGN_LEFT];
		missionTextRow = i;
		for (i-- ; i > 14 ; i--)
			[gui setColor:[OOColor greenColor] forRow:i];
		
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	[lastTextKey release];
	lastTextKey = nil;
	
	[[UNIVERSE gameView] clearMouse];
	
	[targetSystemData release];
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	
	// if the system has gone nova, there's no planet to display
	if (!sunGoneNova)
	{
		// The next code is generating the miniature planets.
		// When normal planets are displayed, the PRNG is reset. This happens not with procedural planet display.
		RANROTSeed ranrotSavedSeed = RANROTGetFullSeed();
		RNG_Seed saved_seed = currentRandomSeed();
		
		if ([targetSystemName isEqual: [UNIVERSE getSystemName:system_seed]])
		{
			[self setBackgroundFromDescriptionsKey:@"gui-scene-show-local-planet"];
		}
		else
		{
			[self setBackgroundFromDescriptionsKey:@"gui-scene-show-planet"];
		}
		
		setRandomSeed(saved_seed);
		RANROTSetFullSeed(ranrotSavedSeed);
	}
	
	if (guiChanged)
	{
		[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
		[gui setBackgroundTextureKey:sunGoneNova ? @"system_data_nova" : @"system_data"];
		
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
		[self checkScript];	// Still needed by some OXPs?
	}
}


- (void) prepareMarkedDestination:(NSMutableDictionary *)markers :(NSDictionary *)marker
{
	NSNumber *key = [NSNumber numberWithInt:[marker oo_intForKey:@"system"]];
	NSMutableArray *list = [markers objectForKey:key];
	if (list == nil)
	{
		list = [NSMutableArray arrayWithObject:marker];
	}
	else
	{
		[list addObject:marker];
	}
	[markers setObject:list forKey:key];
}


- (NSDictionary *) markedDestinations
{
	// get a list of systems marked as contract destinations
	NSMutableDictionary	*destinations = [NSMutableDictionary dictionaryWithCapacity:256];
	unsigned		i;
	OOSystemID sysid;
	NSDictionary *marker;

	for (i = 0; i < [passengers count]; i++)
	{
		sysid = [[passengers oo_dictionaryAtIndex:i]  oo_unsignedCharForKey:CONTRACT_KEY_DESTINATION];
		marker = [self passengerContractMarker:sysid];
		[self prepareMarkedDestination:destinations:marker];
	}
	for (i = 0; i < [parcels count]; i++)
	{
		sysid = [[parcels oo_dictionaryAtIndex:i]  oo_unsignedCharForKey:CONTRACT_KEY_DESTINATION];
		marker = [self parcelContractMarker:sysid];
		[self prepareMarkedDestination:destinations:marker];
	}
	for (i = 0; i < [contracts count]; i++)
	{
		sysid = [[contracts oo_dictionaryAtIndex:i]  oo_unsignedCharForKey:CONTRACT_KEY_DESTINATION];
		marker = [self cargoContractMarker:sysid];
		[self prepareMarkedDestination:destinations:marker];
	}

	NSEnumerator				*keyEnum = nil;
	NSString					*key = nil;

	for (keyEnum = [missionDestinations keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		marker = [missionDestinations objectForKey:key];
		[self prepareMarkedDestination:destinations:marker];
	}
	
	return destinations;
}


- (void) setGuiToLongRangeChartScreen
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIScreenID	oldScreen = gui_screen;
	
	gui_screen = GUI_SCREEN_LONG_RANGE_CHART;
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
	
	if ((target_system_seed.d != cursor_coordinates.x)||(target_system_seed.b != cursor_coordinates.y))
			target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	
	NSString *targetSystemName = [[UNIVERSE getSystemName:target_system_seed] retain];  // retained
	
	[UNIVERSE preloadPlanetTexturesForSystem:target_system_seed];
	
	// GUI stuff
	{
		[gui clearAndKeepBackground:!guiChanged];
		NSString *gal_key = [NSString stringWithFormat:@"long-range-chart-title-%d", galaxy_number];
		if ([[UNIVERSE descriptions] valueForKey:gal_key] == nil)
		{
			[gui setTitle:[NSString stringWithFormat:DESC(@"long-range-chart-title-d"), galaxy_number+1]];
		}
		else
		{
			[gui setTitle:[UNIVERSE descriptionForKey:gal_key]];
		}
		
		NSString *displaySearchString = planetSearchString ? [planetSearchString capitalizedString] : (NSString *)@"";
		[gui setText:[NSString stringWithFormat:DESC(@"long-range-chart-find-planet-@"), displaySearchString] forRow:17];
		[gui setColor:[OOColor cyanColor] forRow:17];
		
		[gui setShowTextCursor:YES];
		[gui setCurrentRow:17];
	}
	/* ends */
	
	[[UNIVERSE gameView] clearMouse];
	
	[targetSystemName release];
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
	
	if (guiChanged)
	{
		NSDictionary *bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:[NSString stringWithFormat:@"long_range_chart%d", galaxy_number+1]];
		if (bgDescriptor == nil)  bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"long_range_chart"];
		[gui setBackgroundTextureDescriptor:bgDescriptor];
		
		[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
		
		[UNIVERSE findSystemCoordinatesWithPrefix:[[UNIVERSE getSystemName:found_system_seed] lowercaseString] exactMatch:YES];
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	}
}


- (void) setGuiToShortRangeChartScreen
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIScreenID	oldScreen = gui_screen;
	
	gui_screen = GUI_SCREEN_SHORT_RANGE_CHART;
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
	
	// don't target planets outside the immediate vicinity.
	if ((abs(cursor_coordinates.x-galaxy_coordinates.x)>=20)||(abs(cursor_coordinates.y-galaxy_coordinates.y)>=38))
			cursor_coordinates = galaxy_coordinates;	// home
	
	if ((target_system_seed.d != cursor_coordinates.x)||(target_system_seed.b != cursor_coordinates.y))
	{
		target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
	}
	
	// now calculate the distance.
	double			distance = [self hyperspaceJumpDistance];
	double			estimatedTravelTime = distance * distance;
	
	NSString		*targetSystemName = [[UNIVERSE getSystemName:target_system_seed] retain];  // retained
	[UNIVERSE preloadPlanetTexturesForSystem:target_system_seed];
	
	// GUI stuff
	{
		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:DESC(@"short-range-chart-title")];
		// refresh the short range chart cache, in case we've just loaded a save game with different local overrides, etc.
		[gui refreshStarChart];
		[gui setText:targetSystemName forRow:19];
		// distance-f & est-travel-time-f are identical between short & long range charts in standard Oolite, however can be alterered separately via OXPs
		[gui setText:[NSString stringWithFormat:OOExpandKey(@"short-range-chart-distance-f"), distance] forRow:20];
		if ([self hasHyperspaceMotor]) [gui setText:(NSString *)((distance > 0.0 && distance <= (double)fuel/10.0) ? (NSString *)[NSString stringWithFormat:OOExpandKey(@"short-range-chart-est-travel-time-f"), estimatedTravelTime] : (NSString *)@"") forRow:21];
		[gui setShowTextCursor:NO];
	}
	/* ends */
	
	[[UNIVERSE gameView] clearMouse];
	
	[targetSystemName release]; // released
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
	
	if (guiChanged)
	{
		[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
		
		[gui setBackgroundTextureKey:@"short_range_chart"];
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	}
}


- (void) setGuiToGameOptionsScreen
{
#ifdef GNUSTEP
	MyOpenGLView	*gameView = [UNIVERSE gameView];
#endif
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];
		GUI_ROW_INIT(gui);

		int first_sel_row = GUI_FIRST_ROW(GAME)-5; // repositioned menu

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:DESC(@"status-commander-@"), [self commanderName]]]; // Same title as status screen.
		
#if OO_RESOLUTION_OPTION
		GameController	*controller = [UNIVERSE gameController];
		
		NSUInteger		displayModeIndex = [controller indexOfCurrentDisplayMode];
		if (displayModeIndex == NSNotFound)
		{
			OOLogWARN(@"display.currentMode.notFound", @"couldn't find current fullscreen setting, switching to default.");
			displayModeIndex = 0;
		}
		
		NSArray			*modeList = [controller displayModes];
		NSDictionary	*mode = nil;
		if ([modeList count])
		{
			mode = [modeList objectAtIndex:displayModeIndex];
		}
		if (mode == nil)  return;	// Got a better idea?
		
		unsigned modeWidth = [mode oo_unsignedIntForKey:kOODisplayWidth];
		unsigned modeHeight = [mode oo_unsignedIntForKey:kOODisplayHeight];
		float modeRefresh = [mode oo_floatForKey:kOODisplayRefreshRate];
		
		NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];
		[gui setText:displayModeString forRow:GUI_ROW(GAME,DISPLAY) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,DISPLAY)];
#endif

		if ([UNIVERSE autoSave])
			[gui setText:DESC(@"gameoptions-autosave-yes") forRow:GUI_ROW(GAME,AUTOSAVE) align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-autosave-no") forRow:GUI_ROW(GAME,AUTOSAVE) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,AUTOSAVE)];
	
		// volume control
		if ([OOSound respondsToSelector:@selector(masterVolume)])
		{
			double volume = 100.0 * [OOSound masterVolume];
			int vol = (volume / 5.0 + 0.5); // avoid rounding errors
			NSString* soundVolumeWordDesc = DESC(@"gameoptions-sound-volume");
			NSString* v1_string = @"|||||||||||||||||||||||||";
			NSString* v0_string = @".........................";
			v1_string = [v1_string substringToIndex:vol];
			v0_string = [v0_string substringToIndex:20 - vol];
			if (vol > 0)
				[gui setText:[NSString stringWithFormat:@"%@%@%@ ", soundVolumeWordDesc, v1_string, v0_string] forRow:GUI_ROW(GAME,VOLUME) align:GUI_ALIGN_CENTER];
			else
				[gui setText:DESC(@"gameoptions-sound-volume-mute") forRow:GUI_ROW(GAME,VOLUME) align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,VOLUME)];
		}
		else
		{
			[gui setText:DESC(@"gameoptions-volume-external-only") forRow:GUI_ROW(GAME,VOLUME) align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW(GAME,VOLUME)];
		}
		
#if OOLITE_SDL		
		// gamma control
		float gamma = [gameView gammaValue];
		int gamma5 = (gamma * 5);
		NSString* gammaWordDesc = DESC(@"gameoptions-gamma-value");
		NSString* v1_string = @"|||||||||||||||||||||||||";
		NSString* v0_string = @".........................";
		v1_string = [v1_string substringToIndex:gamma5];
		v0_string = [v0_string substringToIndex:20 - gamma5];
		[gui setText:[NSString stringWithFormat:@"%@%@%@ (%.1f) ", gammaWordDesc, v1_string, v0_string, gamma] forRow:GUI_ROW(GAME,GAMMA) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,GAMMA)];
#endif
		
#if OOLITE_SPEECH_SYNTH
		// Speech control
		if (isSpeechOn)
			[gui setText:DESC(@"gameoptions-spoken-messages-yes") forRow:GUI_ROW(GAME,SPEECH) align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-spoken-messages-no") forRow:GUI_ROW(GAME,SPEECH) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,SPEECH)];
#if OOLITE_ESPEAK
		{
			NSString *message = [NSString stringWithFormat:DESC(@"gameoptions-voice-@"), [UNIVERSE voiceName: voice_no]];
			[gui setText:message forRow:GUI_ROW(GAME,SPEECH_LANGUAGE) align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,SPEECH_LANGUAGE)];

			message = [NSString stringWithFormat:DESC(voice_gender_m ? @"gameoptions-voice-M" : @"gameoptions-voice-F")];
			[gui setText:message forRow:GUI_ROW(GAME,SPEECH_GENDER) align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,SPEECH_GENDER)];
		}
#endif
#endif
#if !OOLITE_MAC_OS_X
		// window/fullscreen
		if([gameView inFullScreenMode])
		{
			[gui setText:DESC(@"gameoptions-play-in-window") forRow:GUI_ROW(GAME,DISPLAYSTYLE) align:GUI_ALIGN_CENTER];
		}
		else
		{
			[gui setText:DESC(@"gameoptions-play-in-fullscreen") forRow:GUI_ROW(GAME,DISPLAYSTYLE) align:GUI_ALIGN_CENTER];
		}
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW(GAME,DISPLAYSTYLE)];
#endif
		
		[gui setText:DESC(@"gameoptions-joystick-configuration") forRow: GUI_ROW(GAME,STICKMAPPER) align: GUI_ALIGN_CENTER];
		if ([[OOJoystickManager sharedStickHandler] joystickCount])
		{
			[gui setKey: GUI_KEY_OK forRow: GUI_ROW(GAME,STICKMAPPER)];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW(GAME,STICKMAPPER)];
		}
		
		NSString *message = [NSString stringWithFormat:DESC(@"gameoptions-music-mode-@"), [UNIVERSE descriptionForArrayKey:@"music-mode" index:[[OOMusicController sharedController] mode]]];
		[gui setText:message forRow:GUI_ROW(GAME,MUSIC)  align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,MUSIC)];

		if ([UNIVERSE wireframeGraphics])
			[gui setText:DESC(@"gameoptions-wireframe-graphics-yes") forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS) align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-wireframe-graphics-no") forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS)];
		
#if !NEW_PLANETS
		if ([UNIVERSE doProcedurallyTexturedPlanets])
			[gui setText:DESC(@"gameoptions-procedurally-textured-planets-yes") forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS) align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-procedurally-textured-planets-no") forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS)];
#endif
		
		OOGraphicsDetail detail = [UNIVERSE detailLevel];
		NSString *shaderEffectsOptionsString = [NSString stringWithFormat:@"gameoptions-detaillevel-%d",detail];
		[gui setText:OOExpandKey(shaderEffectsOptionsString) forRow:GUI_ROW(GAME,SHADEREFFECTS) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,SHADEREFFECTS)];

		
		if ([UNIVERSE dockingClearanceProtocolActive])
		{
			[gui setText:DESC(@"gameoptions-docking-clearance-yes") forRow:GUI_ROW(GAME,DOCKINGCLEARANCE) align:GUI_ALIGN_CENTER];
		}
		else
		{
			[gui setText:DESC(@"gameoptions-docking-clearance-no") forRow:GUI_ROW(GAME,DOCKINGCLEARANCE) align:GUI_ALIGN_CENTER];
		}
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,DOCKINGCLEARANCE)];
		
		// Back menu option
		[gui setText:DESC(@"gui-back") forRow:GUI_ROW(GAME,BACK) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,BACK)];

		[gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_GAMEOPTIONS_END_OF_LIST)];
		[gui setSelectedRow: first_sel_row];

		[gui setShowTextCursor:NO];
		[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
		[gui setBackgroundTextureKey:@"settings"];
	}
	/* ends */

	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_GAMEOPTIONS;

	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}


- (void) setGuiToLoadSaveScreen
{
	BOOL			canLoadOrSave = NO;
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	OOGUIScreenID	oldScreen = gui_screen;
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

	if ([self status] == STATUS_DOCKED)
	{
		if ([self dockedStation] == nil)  [self setDockedAtMainStation];
		canLoadOrSave = (([self dockedStation] == [UNIVERSE station] || [[self dockedStation] allowsSaving]) && !([[UNIVERSE sun] goneNova] || [[UNIVERSE sun] willGoNova]));
	}
	
	BOOL canQuickSave = (canLoadOrSave && ([[gameView gameController] playerFileToLoad] != nil));
	
	// GUI stuff
	{
		GuiDisplayGen* gui = [UNIVERSE gui];
		GUI_ROW_INIT(gui);

		int first_sel_row = (canLoadOrSave)? GUI_ROW(,SAVE) : GUI_ROW(,GAMEOPTIONS);
		if (canQuickSave)
			first_sel_row = GUI_ROW(,QUICKSAVE);

		[gui clear];
		[gui setTitle:[NSString stringWithFormat:DESC(@"status-commander-@"), [self commanderName]]]; //Same title as status screen.
		
		[gui setText:DESC(@"options-quick-save") forRow:GUI_ROW(,QUICKSAVE) align:GUI_ALIGN_CENTER];
		if (canQuickSave)
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(,QUICKSAVE)];
		else
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW(,QUICKSAVE)];

		[gui setText:DESC(@"options-save-commander") forRow:GUI_ROW(,SAVE) align:GUI_ALIGN_CENTER];
		[gui setText:DESC(@"options-load-commander") forRow:GUI_ROW(,LOAD) align:GUI_ALIGN_CENTER];
		if (canLoadOrSave)
		{
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(,SAVE)];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(,LOAD)];
		}
		else
		{
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW(,SAVE)];
			[gui setColor:[OOColor grayColor] forRow:GUI_ROW(,LOAD)];
		}

		[gui setText:DESC(@"options-return-to-menu") forRow:GUI_ROW(,BEGIN_NEW) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(,BEGIN_NEW)];

		[gui setText:DESC(@"options-game-options") forRow:GUI_ROW(,GAMEOPTIONS) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(,GAMEOPTIONS)];
		
#if OOLITE_SDL
		// GNUstep needs a quit option at present (no Cmd-Q) but
		// doesn't need speech.
		
		// quit menu option
		[gui setText:DESC(@"options-exit-game") forRow:GUI_ROW(,QUIT) align:GUI_ALIGN_CENTER];
		[gui setKey:GUI_KEY_OK forRow:GUI_ROW(,QUIT)];
#endif
		
		[gui setSelectableRange:NSMakeRange(first_sel_row, GUI_ROW_OPTIONS_END_OF_LIST)];

		if ([[UNIVERSE gameController] isGamePaused] || (!canLoadOrSave && [self status] == STATUS_DOCKED))
		{
			[gui setSelectedRow: GUI_ROW(,GAMEOPTIONS)];
		}
		else
		{
			[gui setSelectedRow: first_sel_row];
		}
		
		[gui setShowTextCursor:NO];
		
		if ([gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"] && [UNIVERSE pauseMessageVisible])
					[[UNIVERSE messageGUI] clear];
		// Graphically, this screen is analogous to the various settings screens
		[gui setBackgroundTextureKey:@"settings"];
	}
	/* ends */
	
	[[UNIVERSE gameView] clearMouse];

	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_OPTIONS;

	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
	[self noteGUIDidChangeFrom:oldScreen to:gui_screen]; 
}


static NSString *last_outfitting_key=nil;


- (void) highlightEquipShipScreenKey:(NSString *)key
{
	int 			i=0;
	OOGUIRow		row;
	NSString 		*otherKey = @"";
	GuiDisplayGen	*gui = [UNIVERSE gui];
	[last_outfitting_key release];
	last_outfitting_key = [key copy];
	[self setGuiToEquipShipScreen:-1];
	key = last_outfitting_key;
	// TODO: redo the equipShipScreen in a way that isn't broken. this whole method 'works'
	// based on the way setGuiToEquipShipScreen  'worked' on 20090913 - Kaks 
	
	// setGuiToEquipShipScreen doesn't take a page number, it takes an offset from the beginning
	// of the dictionary, the first line will show the key at that offset...
	
	// try the last page first - 10 pages max.
	while (otherKey)
	{
		[self setGuiToEquipShipScreen:i];
		for (row = GUI_ROW_EQUIPMENT_START;row<=GUI_MAX_ROWS_EQUIPMENT+2;row++)
		{
			otherKey = [gui keyForRow:row];
			if (!otherKey)
			{
				[self setGuiToEquipShipScreen:0];
				return;
			}
			if ([otherKey isEqualToString:key])
			{
				[gui setSelectedRow:row];
				[self showInformationForSelectedUpgrade];
				return;
			}
		}
		if ([otherKey hasPrefix:@"More:"])
		{
			i = [[otherKey componentsSeparatedByString:@":"] oo_intAtIndex:1];
		}
		else
		{
			[self setGuiToEquipShipScreen:0];
			return;
		}
	}
}


- (OOWeaponFacingSet) availableFacings
{
	OOShipRegistry		*registry = [OOShipRegistry sharedRegistry];
	NSDictionary		*shipyardInfo = [registry shipyardInfoForKey:[self shipDataKey]];
	unsigned			available_facings = [shipyardInfo oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:[self weaponFacings]];	// use defaults  explicitly
	
	return available_facings & VALID_WEAPON_FACINGS;
}


- (void) setGuiToEquipShipScreen:(int)skipParam selectingFacingFor:(NSString *)eqKeyForSelectFacing
{
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
	
	missiles = [self countMissiles];
	OOEntityStatus searchStatus; // use STATUS_TEST, STATUS_DEAD & STATUS_ACTIVE
	NSString *showKey = nil;
	unsigned skip;

	if (skipParam < 0)
	{
		skip = 0;
		searchStatus = STATUS_TEST;
	}
	else
	{
		skip = skipParam;
		searchStatus = STATUS_ACTIVE;
	}

	// don't show a "Back" item if we're only skipping one item - just show the item
	if (skip == 1)
		skip = 0;

	double priceFactor = 1.0;
	OOTechLevelID techlevel = [[UNIVERSE generateSystemData:system_seed] oo_intForKey:KEY_TECHLEVEL];

	StationEntity *dockedStation = [self dockedStation];
	if (dockedStation)
	{
		priceFactor = [dockedStation equipmentPriceFactor];
		if ([dockedStation equivalentTechLevel] != NSNotFound)
			techlevel = [dockedStation equivalentTechLevel];
	}

	// build an array of all equipment - and take away that which has been bought (or is not permitted)
	NSMutableArray		*equipmentAllowed = [NSMutableArray array];
	
	// find options that agree with this ship
	OOShipRegistry		*registry = [OOShipRegistry sharedRegistry];
	NSDictionary		*shipyardInfo = [registry shipyardInfoForKey:[self shipDataKey]];
	NSMutableSet		*options = [NSMutableSet setWithArray:[shipyardInfo oo_arrayForKey:KEY_OPTIONAL_EQUIPMENT]];
	
	// add standard items too!
	[options addObjectsFromArray:[[shipyardInfo oo_dictionaryForKey:KEY_STANDARD_EQUIPMENT] oo_arrayForKey:KEY_EQUIPMENT_EXTRAS]];
	
	unsigned			i = 0;
	NSEnumerator		*eqEnum = nil;
	OOEquipmentType		*eqType = nil;
	unsigned			available_facings = [shipyardInfo oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:[self weaponFacings]];	// use defaults  explicitly

	
	if (eqKeyForSelectFacing != nil) // Weapons purchase subscreen.
	{
		skip = 1;	// show the back button
		// The 3 lines below are needed by the present GUI. TODO:create a sane GUI. Kaks - 20090915 & 201005
		[equipmentAllowed addObject:eqKeyForSelectFacing];
		[equipmentAllowed addObject:eqKeyForSelectFacing];
		[equipmentAllowed addObject:eqKeyForSelectFacing];
	}
	else for (eqEnum = [OOEquipmentType equipmentEnumerator]; (eqType = [eqEnum nextObject]); i++)
	{
		NSString			*eqKey = [eqType identifier];
		OOTechLevelID		minTechLevel = [eqType effectiveTechLevel];
		
		// set initial availability to NO
		BOOL isOK = NO;
		
		// check special availability
		if ([eqType isAvailableToAll])  [options addObject:eqKey];
		
		// if you have a damaged system you can get it repaired at a tech level one less than that required to buy it
		if (minTechLevel != 0 && [self hasEquipmentItem:[eqType damagedIdentifier]])  minTechLevel--;
		
		// reduce the minimum techlevel occasionally as a bonus..
		if (techlevel < minTechLevel && techlevel + 3 > minTechLevel)
		{
			unsigned day = i * 13 + (unsigned)floor([UNIVERSE getTime] / 86400.0);
			unsigned char dayRnd = (day & 0xff) ^ system_seed.a;
			OOTechLevelID originalMinTechLevel = minTechLevel;
			
			while (minTechLevel > 0 && minTechLevel > originalMinTechLevel - 3 && !(dayRnd & 7))	// bargain tech days every 1/8 days
			{
				dayRnd = dayRnd >> 2;
				minTechLevel--;	// occasional bonus items according to TL
			}
		}
		
		// check initial availability against options AND standard extras
		if ([options containsObject:eqKey])
		{
			isOK = YES;
			[options removeObject:eqKey];
		}

		if (isOK)
		{
			if (techlevel < minTechLevel) isOK = NO;
			if (![self canAddEquipment:eqKey inContext:@"purchase"]) isOK = NO;
			if (available_facings == 0 && [eqType isPrimaryWeapon]) isOK = NO;
			if (isOK)  [equipmentAllowed addObject:eqKey];
		}
		
		if (searchStatus == STATUS_DEAD && isOK)
		{
			showKey = eqKey;
			searchStatus = STATUS_ACTIVE;
		}
		if (searchStatus == STATUS_TEST)
		{
			if (isOK) showKey = eqKey;
			if ([eqKey isEqualToString:last_outfitting_key]) 
				searchStatus = isOK ? STATUS_ACTIVE : STATUS_DEAD;
		}
	}
	if (searchStatus != STATUS_TEST && showKey != nil)
	{
		[last_outfitting_key release];
		last_outfitting_key = [showKey copy];
	}
	
	// GUI stuff
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		OOGUIRow		start_row = GUI_ROW_EQUIPMENT_START;
		OOGUIRow		row = start_row;
		unsigned        facing_count = 0;
		BOOL			displayRow = YES;
		BOOL			weaponMounted = NO;
		BOOL			guiChanged = (gui_screen != GUI_SCREEN_EQUIP_SHIP);

		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:DESC(@"equip-title")];
		
		[gui setText:[NSString stringWithFormat:DESC(@"equip-cash-@"), OOCredits(credits)]  forRow: GUI_ROW_EQUIPMENT_CASH];
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -380;
		[gui setTabStops:tab_stops];
		
		unsigned n_rows = GUI_MAX_ROWS_EQUIPMENT;
		NSUInteger count = [equipmentAllowed count];

		if (count > 0)
		{
			if (skip > 0)	// lose the first row to Back <--
			{
				unsigned previous;

				if (count <= n_rows || skip < n_rows)
					previous = 0;					// single page
				else
				{
					previous = skip - (n_rows - 2);	// multi-page. 
					if (previous < 2)
						previous = 0;				// if only one previous item, just show it
				}

				if (eqKeyForSelectFacing != nil)
				{
					previous = 0;
					// keep weapon selected if we go back.
					[gui setKey:[NSString stringWithFormat:@"More:%d:%@", previous, eqKeyForSelectFacing] forRow:row];
				}
				else
				{
					[gui setKey:[NSString stringWithFormat:@"More:%d", previous] forRow:row];
				}
				[gui setColor:[OOColor greenColor] forRow:row];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:row];
				row++;
			}
			
			for (i = skip; i < count && (row - start_row < (OOGUIRow)n_rows); i++)
			{
				NSString			*eqKey = [equipmentAllowed oo_stringAtIndex:i];
				OOEquipmentType		*eqInfo = [OOEquipmentType equipmentTypeWithIdentifier:eqKey];
				OOCreditsQuantity	pricePerUnit = [eqInfo price];
				NSString			*desc = [NSString stringWithFormat:@" %@ ", [eqInfo name]];
				NSString			*eq_key_damaged	= [eqInfo damagedIdentifier];
				double				price;
				
				if ([eqKey isEqual:@"EQ_FUEL"])
				{
					price = (PLAYER_MAX_FUEL - fuel) * pricePerUnit * [self fuelChargeRate];
				}
				else if ([eqKey isEqualToString:@"EQ_RENOVATION"])
				{
					price = [self renovationCosts];
					[gui setColor:[OOColor orangeColor] forRow:row]; // color renovation in orange
				}
				else price = pricePerUnit;
				
				price *= priceFactor;  // increased prices at some stations
				
				// is this item damaged?
				if ([self hasEquipmentItem:eq_key_damaged])
				{
					desc = [NSString stringWithFormat:DESC(@"equip-repair-@"), desc];
					price /= 2.0;
					[gui setColor:[OOColor orangeColor] forRow:row];	// color repair items in orange
				}
				
				NSString *priceString = [NSString stringWithFormat:@" %@ ", OOCredits(price)];
				
				if ([eqKeyForSelectFacing isEqualToString:eqKey])
				{
					// Weapons purchase subscreen.
					while (facing_count < 5)
					{
						switch (facing_count)
						{
							case 0:
								break;
								
							case 1:
								displayRow = available_facings & WEAPON_FACING_FORWARD;
								desc = FORWARD_FACING_STRING;
								weaponMounted = forward_weapon_type > WEAPON_NONE;
								break;
								
							case 2:
								displayRow = available_facings & WEAPON_FACING_AFT;
								desc = AFT_FACING_STRING;
								weaponMounted = aft_weapon_type > WEAPON_NONE;
								break;
								
							case 3:
								displayRow = available_facings & WEAPON_FACING_PORT;
								desc = PORT_FACING_STRING;
								weaponMounted = port_weapon_type > WEAPON_NONE;
								break;
								
							case 4:
								displayRow = available_facings & WEAPON_FACING_STARBOARD;
								desc = STARBOARD_FACING_STRING;
								weaponMounted = starboard_weapon_type > WEAPON_NONE;
								break;
						}
						
						if(weaponMounted)
						{
							[gui setColor:[OOColor colorWithRed:0.0f green:0.6f blue:0.0f alpha:1.0f] forRow:row];
						}
						else
						{
							[gui setColor:[OOColor greenColor] forRow:row];
						}
						if (displayRow)	// Always true for the first pass. The first pass is used to display the name of the weapon being purchased.
						{
							[gui setKey:eqKey forRow:row];
							[gui setArray:[NSArray arrayWithObjects:desc, (facing_count > 0 ? priceString : (NSString *)@""), nil] forRow:row];
							row++;
						}
						facing_count++;
					}
				}
				else
				{
					// Normal equipment list.
					[gui setKey:eqKey forRow:row];
					[gui setArray:[NSArray arrayWithObjects:desc, priceString, nil] forRow:row];
					row++;
				}
			}

			if (i < count)
			{
				// just overwrite the last item :-)
				[gui setColor:[OOColor greenColor] forRow:row - 1];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:row - 1];
				[gui setKey:[NSString stringWithFormat:@"More:%d", i - 1] forRow:row - 1];
			}
			
			[gui setSelectableRange:NSMakeRange(start_row,row - start_row)];

			if ([gui selectedRow] != start_row)
				[gui setSelectedRow:start_row];

			if (eqKeyForSelectFacing != nil)
			{
				[gui setSelectedRow:start_row + 1];
				[self showInformationForSelectedUpgradeWithFormatString:DESC(@"@-select-where-to-install")];
			}
			else
			{
				[self showInformationForSelectedUpgrade];
			}
		}
		else
		{
			[gui setText:DESC(@"equip-no-equipment-available-for-purchase") forRow:GUI_ROW_NO_SHIPS align:GUI_ALIGN_CENTER];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_NO_SHIPS];
			
			[gui setSelectableRange:NSMakeRange(0,0)];
			[gui setNoSelectedRow];
			[self showInformationForSelectedUpgrade];
		}
		
		[gui setShowTextCursor:NO];
		
		// TODO: split the mount_weapon sub-screen into a separate screen, and use it for pylon mounted wepons as well?
		if (guiChanged)
		{
			[gui setForegroundTextureKey:@"docked_overlay"];
			NSDictionary *background = [UNIVERSE screenTextureDescriptorForKey:@"equip_ship"];
			[self setEquipScreenBackgroundDescriptor:background];
			[gui setBackgroundTextureDescriptor:background];
		}
		else if (eqKeyForSelectFacing != nil) // weapon purchase
		{
			NSDictionary *bgDescriptor = [UNIVERSE screenTextureDescriptorForKey:@"mount_weapon"];
			if (bgDescriptor != nil)  [gui setBackgroundTextureDescriptor:bgDescriptor];
		}
		else // Returning from a weapon purchase. (Also called, redundantly, when paging)
		{
			[gui setBackgroundTextureDescriptor:[self equipScreenBackgroundDescriptor]];
		}
	}
	/* ends */

	chosen_weapon_facing = WEAPON_FACING_NONE;
	[self setShowDemoShips:NO];
	gui_screen = GUI_SCREEN_EQUIP_SHIP;

	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}


- (void) setGuiToEquipShipScreen:(int)skip
{
	[self setGuiToEquipShipScreen:skip selectingFacingFor:nil];
}


- (void) showInformationForSelectedUpgrade
{
	[self showInformationForSelectedUpgradeWithFormatString:nil];
}

	
- (void) showInformationForSelectedUpgradeWithFormatString:(NSString *)formatString
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	NSString* eqKey = [gui selectedRowKey];
	int i;
	
	for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++)
	{
		[gui setText:@"" forRow:i];
		[gui setColor:[OOColor greenColor] forRow:i];
	}
	if (eqKey)
	{
		if (![eqKey hasPrefix:@"More:"])
		{
			NSString* desc = [[OOEquipmentType equipmentTypeWithIdentifier:eqKey] descriptiveText];
			NSString* eq_key_damaged = [NSString stringWithFormat:@"%@_DAMAGED", eqKey];
			int weight = [[OOEquipmentType equipmentTypeWithIdentifier:eqKey] requiredCargoSpace];
			if ([self hasEquipmentItem:eq_key_damaged])
			{
				desc = [NSString stringWithFormat:DESC(@"upgradeinfo-@-price-is-for-repairing"), desc];
			}
			else
			{
				if([eqKey hasSuffix:@"ENERGY_UNIT"] && ([self hasEquipmentItem:@"EQ_ENERGY_UNIT_DAMAGED"] || [self hasEquipmentItem:@"EQ_ENERGY_UNIT"] || [self hasEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT_DAMAGED"]))
					desc = [NSString stringWithFormat:DESC(@"@-will-replace-other-energy"), desc];
				if (weight > 0) desc = [NSString stringWithFormat:DESC(@"upgradeinfo-@-weight-d-of-equipment"), desc, weight];
			}
			if (formatString) desc = [NSString stringWithFormat:formatString, desc];
			[gui addLongText:desc startingAtRow:GUI_ROW_EQUIPMENT_DETAIL align:GUI_ALIGN_LEFT];
		}
	}
}


- (void) setGuiToInterfacesScreen:(int)skip
{
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
	if (gui_screen != GUI_SCREEN_INTERFACES)
	{
		[self noteGUIWillChangeTo:GUI_SCREEN_INTERFACES];
	}
	
	// build an array of available interfaces
	NSDictionary *interfaces = [[self dockedStation] localInterfaces];
	NSArray		*interfaceKeys = [interfaces keysSortedByValueUsingSelector:@selector(interfaceCompare:)]; // sorts by category, then title
	int i;
	
	// GUI stuff
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		OOGUIRow		start_row = GUI_ROW_INTERFACES_START;
		OOGUIRow		row = start_row;
		BOOL			guiChanged = (gui_screen != GUI_SCREEN_INTERFACES);

		[gui clearAndKeepBackground:!guiChanged];
		[gui setTitle:DESC(@"interfaces-title")];
		
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -480;
		[gui setTabStops:tab_stops];
		
		unsigned n_rows = GUI_MAX_ROWS_INTERFACES;
		NSUInteger count = [interfaceKeys count];

		if (count > 0)
		{
			if (skip > 0)	// lose the first row to Back <--
			{
				unsigned previous;
				
				if (count <= n_rows || skip < (NSInteger)n_rows)
				{
					previous = 0;					// single page
				}
				else
				{
					previous = skip - (n_rows - 2);	// multi-page. 
					if (previous < 2)
					{
						previous = 0;				// if only one previous item, just show it
					}
				}
				
				[gui setKey:[NSString stringWithFormat:@"More:%d", previous] forRow:row];
				[gui setColor:[OOColor greenColor] forRow:row];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:row];
				row++;
			}
			
			for (i = skip; i < (NSInteger)count && (row - start_row < (OOGUIRow)n_rows); i++)
			{
				NSString *interfaceKey = [interfaceKeys objectAtIndex:i];
				OOJSInterfaceDefinition *definition = [interfaces objectForKey:interfaceKey];

				[gui setKey:interfaceKey forRow:row];
				[gui setArray:[NSArray arrayWithObjects:[definition title],[definition category], nil] forRow:row];

				row++;
			}

			if (i < (NSInteger)count)
			{
				// just overwrite the last item :-)
				[gui setColor:[OOColor greenColor] forRow:row - 1];
				[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:row - 1];
				[gui setKey:[NSString stringWithFormat:@"More:%d", i - 1] forRow:row - 1];
			}
			
			[gui setSelectableRange:NSMakeRange(start_row,row - start_row)];

			if ([gui selectedRow] != start_row)
			{
				[gui setSelectedRow:start_row];
			}

			[self showInformationForSelectedInterface];
		}
		else
		{
			[gui setText:DESC(@"interfaces-no-interfaces-available-for-use") forRow:GUI_ROW_NO_INTERFACES align:GUI_ALIGN_LEFT];
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_NO_INTERFACES];
			
			[gui setSelectableRange:NSMakeRange(0,0)];
			[gui setNoSelectedRow];

		}
		
		[gui setShowTextCursor:NO];

		NSString *desc = [NSString stringWithFormat:DESC(@"interfaces-for-ship-@-and-station-@"), [self displayName], [[self dockedStation] displayName]];
		[gui setColor:[OOColor yellowColor] forRow:GUI_ROW_INTERFACES_HEADING];
		[gui setText:desc forRow:GUI_ROW_INTERFACES_HEADING];

		
		if (guiChanged)
		{
			[gui setForegroundTextureKey:@"docked_overlay"];
			NSDictionary *background = [UNIVERSE screenTextureDescriptorForKey:@"interfaces"];
			[gui setBackgroundTextureDescriptor:background];
		}
	}
	/* ends */


	[self setShowDemoShips:NO];
	
	OOGUIScreenID	oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_INTERFACES;
	[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

}


- (void) showInformationForSelectedInterface
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	NSString* interfaceKey = [gui selectedRowKey];
	
	int i;
	
	for (i = GUI_ROW_EQUIPMENT_DETAIL; i < GUI_MAX_ROWS; i++)
	{
		[gui setText:@"" forRow:i];
		[gui setColor:[OOColor greenColor] forRow:i];
	}
	
	if (interfaceKey && ![interfaceKey hasPrefix:@"More:"])
	{
		NSDictionary *interfaces = [[self dockedStation] localInterfaces];
		OOJSInterfaceDefinition *definition = [interfaces objectForKey:interfaceKey];
		if (definition)
		{
			[gui addLongText:[definition summary] startingAtRow:GUI_ROW_INTERFACES_DETAIL align:GUI_ALIGN_LEFT];
		}
	}

}


- (void) activateSelectedInterface
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	NSString* key = [gui selectedRowKey];

	if ([key hasPrefix:@"More:"])
	{
		int 		from_item = [[key componentsSeparatedByString:@":"] oo_intAtIndex:1];
		[self setGuiToInterfacesScreen:from_item];

		if ([gui selectedRow] < 0)
			[gui setSelectedRow:GUI_ROW_INTERFACES_START];
		if (from_item == 0)
			[gui setSelectedRow:GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1];
		[self showInformationForSelectedInterface];


		return;
	}

	NSDictionary *interfaces = [[self dockedStation] localInterfaces];
	OOJSInterfaceDefinition *definition = [interfaces objectForKey:key];
	if (definition)
	{
		[[UNIVERSE gameView] clearKeys];
		[definition runCallback:key];
	}
	else
	{
		OOLog(@"interface.missingCallback", @"Unable to find callback definition for key %@", key);
	}
}


- (void) setupStartScreenGui
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	NSString		*text = nil;

	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

	[gui clear];

	[gui setTitle:@"Oolite"];

	text = DESC(@"game-copyright");
	[gui setText:text forRow:15 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor whiteColor] forRow:15];
		
	text = DESC(@"theme-music-credit");
	[gui setText:text forRow:17 align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor grayColor] forRow:17];
		
	int row = 22;

	text = DESC(@"oolite-start-option-1");
	[gui setText:text forRow:row align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:row];
	[gui setKey:[NSString stringWithFormat:@"Start:%d", row] forRow:row];

	++row;

	text = DESC(@"oolite-start-option-2");
	[gui setText:text forRow:row align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:row];
	[gui setKey:[NSString stringWithFormat:@"Start:%d", row] forRow:row];

	++row;

	text = DESC(@"oolite-start-option-3");
	[gui setText:text forRow:row align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:row];
	[gui setKey:[NSString stringWithFormat:@"Start:%d", row] forRow:row];

	++row;

	text = DESC(@"oolite-start-option-4");
	[gui setText:text forRow:row align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:row];
	[gui setKey:[NSString stringWithFormat:@"Start:%d", row] forRow:row];

	++row;

	text = DESC(@"oolite-start-option-5");
	[gui setText:text forRow:row align:GUI_ALIGN_CENTER];
	[gui setColor:[OOColor yellowColor] forRow:row];
	[gui setKey:[NSString stringWithFormat:@"Start:%d", row] forRow:row];

	[gui setSelectableRange:NSMakeRange(22,5)];
	[gui setSelectedRow:22];

	[gui setBackgroundTextureKey:@"intro"];

}


- (void) setGuiToIntroFirstGo:(BOOL)justCobra
{
	NSString 		*text = nil;
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIRow 		msgLine = 2;
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
	[[UNIVERSE gameView] clearMouse];

	if (justCobra)
	{
		[UNIVERSE removeDemoShips];
		[[OOCacheManager sharedCache] flush];	// At first startup, a lot of stuff is cached
	}
	
	if (justCobra)
	{
		[self setupStartScreenGui];
		
		// check for error messages from Resource Manager
		//[ResourceManager paths]; done in Universe already
		NSString *errors = [ResourceManager errors];
		if (errors != nil)
		{
			OOGUIRow ms_start = msgLine;
			OOGUIRow i = msgLine = [gui addLongText:errors startingAtRow:ms_start align:GUI_ALIGN_LEFT];
			for (i-- ; i >= ms_start ; i--) [gui setColor:[OOColor redColor] forRow:i];
			msgLine++;
		}
		
		// check for messages from OXPs
		NSArray *OXPsWithMessages = [ResourceManager OXPsWithMessagesFound];
		if ([OXPsWithMessages count] > 0)
		{
			NSString *messageToDisplay = @"";
			
			// Show which OXPs were found with messages, but don't spam the screen if more than
			// a certain number of them exist
			if ([OXPsWithMessages count] < 5)
			{
				unsigned i;
				for (i = 0; i < [OXPsWithMessages count]; i++)
				{
					messageToDisplay = [messageToDisplay stringByAppendingString:
															[NSString stringWithFormat:([messageToDisplay isEqualToString:@""] ? @"%@" : @", %@"),
															[OXPsWithMessages oo_stringAtIndex:i]]];
				}
				messageToDisplay = [NSString stringWithFormat:DESC(@"oxp-containing-messages-list-@"), messageToDisplay];
			}
			messageToDisplay = [NSString stringWithFormat:@"%@%@",DESC(@"oxp-containing-messages-found"), messageToDisplay];
			OOGUIRow ms_start = msgLine;
			OOGUIRow i = msgLine = [gui addLongText:messageToDisplay startingAtRow:ms_start align:GUI_ALIGN_LEFT];
			for (i--; i >= ms_start; i--)
			{
				[gui setColor:[OOColor orangeColor] forRow:i];
			}
			msgLine++;
		}
		
		// check for messages from the command line
		NSArray* arguments = [[NSProcessInfo processInfo] arguments];
		unsigned i;
		for (i = 0; i < [arguments count]; i++)
		{
			if (([[arguments objectAtIndex:i] isEqual:@"-message"])&&(i < [arguments count] - 1))
			{
				OOGUIRow ms_start = msgLine;
				NSString* message = [arguments oo_stringAtIndex:i + 1];
				OOGUIRow i = msgLine = [gui addLongText:message startingAtRow:ms_start align:GUI_ALIGN_CENTER];
				for (i-- ; i >= ms_start; i--)
				{
					[gui setColor:[OOColor magentaColor] forRow:i];
				}
			}
			if ([[arguments objectAtIndex:i] isEqual:@"-showversion"])
			{
				OOGUIRow ms_start = msgLine;
				NSString *version = [NSString stringWithFormat:@"Version %@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
				OOGUIRow i = msgLine = [gui addLongText:version startingAtRow:ms_start align:GUI_ALIGN_CENTER];
				for (i-- ; i >= ms_start; i--)
				{
					[gui setColor:[OOColor magentaColor] forRow:i];
				}
			}
		}
	}
	else
	{
		[gui clear];

        text = DESC(@"oolite-ship-library-title");
		[gui setTitle:text];

        text = DESC(@"oolite-ship-library-exit");
        [gui setText:text forRow:23 align:GUI_ALIGN_CENTER];
        [gui setColor:[OOColor yellowColor] forRow:23];
	}
	
	[gui setShowTextCursor:NO];
	
	[UNIVERSE setupIntroFirstGo: justCobra];
	
	if (gui != nil)  
	{
		gui_screen = justCobra ? GUI_SCREEN_INTRO1 : GUI_SCREEN_INTRO2;
	}
	[[OOMusicController sharedController] playThemeMusic];
	
	[self setShowDemoShips:YES];
	[gui setBackgroundTextureKey:@"intro"];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}


- (void) setGuiToOXZManager
{

	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:NO];
	[[UNIVERSE gameView] clearMouse];
	[UNIVERSE removeDemoShips];

	gui_screen = GUI_SCREEN_OXZMANAGER;

	[[UNIVERSE gui] clearAndKeepBackground:NO];

	[[OOOXZManager sharedManager] gui];
	
	[[OOMusicController sharedController] playThemeMusic];
	[[UNIVERSE gui] setBackgroundTextureKey:@"oxz-manager"];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}





- (void) noteGUIWillChangeTo:(OOGUIScreenID)toScreen
{
	JSContext *context = OOJSAcquireContext();
	ShipScriptEvent(context, self, "guiScreenWillChange", OOJSValueFromGUIScreenID(context, toScreen), OOJSValueFromGUIScreenID(context, gui_screen));
	OOJSRelinquishContext(context);
}


- (void) noteGUIDidChangeFrom:(OOGUIScreenID)fromScreen to:(OOGUIScreenID)toScreen
{
	// No events triggered if we're changing screens while paused, or if screen never actually changed.
	if (fromScreen != toScreen)
	{
		// MKW - release GUI Screen ship, if we have one
		switch (fromScreen)
		{
			case GUI_SCREEN_SHIPYARD:
			case GUI_SCREEN_LOAD:
			case GUI_SCREEN_SAVE:
				[demoShip release];
				demoShip = nil;
				break;
			default:
				// Nothing
				break;

		}
		if (![[UNIVERSE gameController] isGamePaused])
		{
			JSContext *context = OOJSAcquireContext();
			ShipScriptEvent(context, self, "guiScreenChanged", OOJSValueFromGUIScreenID(context, toScreen), OOJSValueFromGUIScreenID(context, fromScreen));
			OOJSRelinquishContext(context);
		}
	}
}


- (void) noteViewDidChangeFrom:(OOViewID)fromView toView:(OOViewID)toView
{
	[self noteSwitchToView:toView fromView:fromView];
}


- (void) buySelectedItem
{
	GuiDisplayGen* gui = [UNIVERSE gui];
	NSString* key = [gui selectedRowKey];

	if ([key hasPrefix:@"More:"])
	{
		int 		from_item = [[key componentsSeparatedByString:@":"] oo_intAtIndex:1];
		NSString	*weaponKey = [[key componentsSeparatedByString:@":"] oo_stringAtIndex:2];

		[self setGuiToEquipShipScreen:from_item];
		if (weaponKey != nil)
		{
			[self highlightEquipShipScreenKey:weaponKey];
		}
		else
		{
			if ([gui selectedRow] < 0)
				[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
			if (from_item == 0)
				[gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
			[self showInformationForSelectedUpgrade];
		}

		return;
	}
	
	NSString		*itemText = [gui selectedRowText];
	
	// FIXME: this is nuts, should be associating lines with keys in some sensible way. --Ahruman 20080311
	if ([itemText isEqual:FORWARD_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_FORWARD;
	if ([itemText isEqual:AFT_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_AFT;
	if ([itemText isEqual:PORT_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_PORT;
	if ([itemText isEqual:STARBOARD_FACING_STRING])
		chosen_weapon_facing = WEAPON_FACING_STARBOARD;
	
	OOCreditsQuantity old_credits = credits;
	if ([self tryBuyingItem:key])
	{
		if (credits == old_credits)
		{
			// laser pre-purchase, or free equipment
			[self playMenuNavigationDown];
		}
		else
		{
			[self playBuyCommodity];
		}			
			
		if(credits != old_credits || ![key hasPrefix:@"EQ_WEAPON_"])
		{
			// adjust time before playerBoughtEquipment gets to change credits dynamically
			// wind the clock forward by 10 minutes plus 10 minutes for every 60 credits spent
			double time_adjust = (old_credits > credits) ? (old_credits - credits) : 0.0;
			[UNIVERSE forceWitchspaceEntries];
			ship_clock_adjust += time_adjust + 600.0;
			
			[self doScriptEvent:OOJSID("playerBoughtEquipment") withArgument:key];
			if (gui_screen == GUI_SCREEN_EQUIP_SHIP) //if we haven't changed gui screen inside playerBoughtEquipment
			{ 
				// show any change due to playerBoughtEquipment
				[self setGuiToEquipShipScreen:0];
				// then try to go back where we were
				[self highlightEquipShipScreenKey:key];
			}

			if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
		}
	}
	else
	{
		[self playCantBuyCommodity];
	}
}


- (BOOL) tryBuyingItem:(NSString *)eqKey
{
	// note this doesn't check the availability by tech-level
	OOEquipmentType			*eqType			= [OOEquipmentType equipmentTypeWithIdentifier:eqKey];
	OOCreditsQuantity		pricePerUnit	= [eqType price];
	NSString				*eqKeyDamaged	= [eqType damagedIdentifier];
	double					price			= pricePerUnit;
	double					priceFactor		= 1.0;
	OOCreditsQuantity		tradeIn			= 0;
	BOOL	isRepair = NO;
	
	// repairs cost 50%
	if ([self hasEquipmentItem:eqKeyDamaged])
	{
		price /= 2.0;
		isRepair = YES;
	}
	
	if ([eqKey isEqualToString:@"EQ_RENOVATION"])
	{
		price = [self renovationCosts];
	}
	
	StationEntity *dockedStation = [self dockedStation];
	if (dockedStation)
	{
		priceFactor = [dockedStation equipmentPriceFactor];
	}
	
	price *= priceFactor;  // increased prices at some stations
	
	if (price > credits)
	{
		return NO;
	}
	
	if ([eqType isPrimaryWeapon])
	{
		if (chosen_weapon_facing == WEAPON_FACING_NONE)
		{
			[self setGuiToEquipShipScreen:0 selectingFacingFor:eqKey];	// reset
			return YES;
		}
		
		OOWeaponType chosen_weapon = OOWeaponTypeFromEquipmentIdentifierStrict(eqKey);
		OOWeaponType current_weapon = WEAPON_NONE;
		
		switch (chosen_weapon_facing)
		{
			case WEAPON_FACING_FORWARD:
				current_weapon = forward_weapon_type;
				forward_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_AFT:
				current_weapon = aft_weapon_type;
				aft_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_PORT:
				current_weapon = port_weapon_type;
				port_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_STARBOARD:
				current_weapon = starboard_weapon_type;
				starboard_weapon_type = chosen_weapon;
				break;
				
			case WEAPON_FACING_NONE:
				break;
		}
		
		credits -= price;
		
		// Refund current_weapon
		if (current_weapon != WEAPON_NONE)
		{
			tradeIn = [UNIVERSE getEquipmentPriceForKey:OOEquipmentIdentifierFromWeaponType(current_weapon)];
		}
		
		[self doTradeIn:tradeIn forPriceFactor:priceFactor];
		// If equipped, remove damaged weapon after repairs. -- But there's no way we should get a damaged weapon. Ever.
		[self removeEquipmentItem:eqKeyDamaged];
		return YES;
	}
	
	if ([eqType isMissileOrMine] && missiles >= max_missiles)
	{
		OOLog(@"equip.buy.mounted.failed.full", @"rejecting missile because already full");
		return NO;
	}
	
	// NSFO!
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	
	if ([eqKey isEqualToString:@"EQ_PASSENGER_BERTH"] && [self availableCargoSpace] < PASSENGER_BERTH_SPACE)
	{
		return NO;
	}
	
	if ([eqKey isEqualToString:@"EQ_FUEL"])
	{
#if MASS_DEPENDENT_FUEL_PRICES
		OOCreditsQuantity creditsForRefuel = ([self fuelCapacity] - [self fuel]) * pricePerUnit * [self fuelChargeRate];
#else
		OOCreditsQuantity creditsForRefuel = ([self fuelCapacity] - [self fuel]) * pricePerUnit;
#endif
		if (credits >= creditsForRefuel)	// Ensure we don't overflow
		{
			credits -= creditsForRefuel;
			fuel = [self fuelCapacity];
			return YES;
		}
		else
		{
			return NO;
		}
	}
	
	// check energy unit replacement
	if ([eqKey hasSuffix:@"ENERGY_UNIT"] && [self energyUnitType] != ENERGY_UNIT_NONE)
	{
		switch ([self energyUnitType])
		{
			case ENERGY_UNIT_NAVAL :
				[self removeEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT"];
				tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_NAVAL_ENERGY_UNIT"] / 2;	// 50 % refund
				break;
			case ENERGY_UNIT_NAVAL_DAMAGED :
				[self removeEquipmentItem:@"EQ_NAVAL_ENERGY_UNIT_DAMAGED"];
				tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_NAVAL_ENERGY_UNIT"] / 4;	// half of the working one
				break;
			case ENERGY_UNIT_NORMAL :
				[self removeEquipmentItem:@"EQ_ENERGY_UNIT"];
				tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_ENERGY_UNIT"] * 3 / 4;		// 75 % refund
				break;
			case ENERGY_UNIT_NORMAL_DAMAGED :
				[self removeEquipmentItem:@"EQ_ENERGY_UNIT_DAMAGED"];
				tradeIn = [UNIVERSE getEquipmentPriceForKey:@"EQ_ENERGY_UNIT"] * 3 / 8;		// half of the working one
				break;

			default:
				break;
		}
		[self doTradeIn:tradeIn forPriceFactor:priceFactor];
	}
	
	// maintain ship
	if ([eqKey isEqualToString:@"EQ_RENOVATION"])
	{
		OOTechLevelID techLevel = NSNotFound;
		if (dockedStation != nil)  techLevel = [dockedStation equivalentTechLevel];
		if (techLevel == NSNotFound)  techLevel = [[UNIVERSE generateSystemData:system_seed] oo_unsignedIntForKey:KEY_TECHLEVEL];
		
		credits -= price;
		ship_trade_in_factor += 5 + techLevel;	// you get better value at high-tech repair bases
		if (ship_trade_in_factor > 100) ship_trade_in_factor = 100;
		
		[self clearSubEntities];
		[self setUpSubEntities];
		
		return YES;
	}
	
	if ([eqKey hasSuffix:@"MISSILE"] || [eqKey hasSuffix:@"MINE"])
	{
		ShipEntity* weapon = [[UNIVERSE newShipWithRole:eqKey] autorelease];
		if (weapon)  OOLog(kOOLogBuyMountedOK, @"Got ship for mounted weapon role %@", eqKey);
		else  OOLog(kOOLogBuyMountedFailed, @"Could not find ship for mounted weapon role %@", eqKey);
		
		BOOL mounted_okay = [self mountMissile:weapon];
		if (mounted_okay)
		{
			credits -= price;
			[self safeAllMissiles];
			[self tidyMissilePylons];
			[self setActiveMissile:0];
		}
		return mounted_okay;
	}
	
	if ([eqKey isEqualToString:@"EQ_PASSENGER_BERTH"])
	{
		[self changePassengerBerths:+1];
		credits -= price;
		return YES;
	}
	
	if ([eqKey isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
	{
		[self changePassengerBerths:-1];
		credits -= price;
		return YES;
	}
	
	if ([eqKey isEqualToString:@"EQ_MISSILE_REMOVAL"])
	{
		credits -= price;
		tradeIn += [self removeMissiles];
		[self doTradeIn:tradeIn forPriceFactor:priceFactor];
		return YES;
	}
	
	if ([self canAddEquipment:eqKey inContext:@"purchase"])
	{
		credits -= price;
		[self addEquipmentItem:eqKey withValidation:NO inContext:@"purchase"]; // no need to validate twice.
		if (isRepair)
		{
			[self doScriptEvent:OOJSID("equipmentRepaired") withArgument:eqKey];
		}
		return YES;
	}
	
	return NO;
}


- (BOOL) setWeaponMount:(OOWeaponFacing)facing toWeapon:(NSString *)eqKey
{
	NSDictionary		*shipyardInfo = [[OOShipRegistry sharedRegistry] shipyardInfoForKey:[self shipDataKey]];
	unsigned			available_facings = [shipyardInfo oo_unsignedIntForKey:KEY_WEAPON_FACINGS defaultValue:[self weaponFacings]];	// use defaults  explicitly
	
	// facing exists?
	if (!(available_facings & facing)) 
	{
		return NO;
	}
	
	// weapon allowed (or NONE)?
	if (![eqKey isEqualToString:@"EQ_WEAPON_NONE"]) 
	{
		if (![self canAddEquipment:eqKey inContext:@"purchase"]) 
		{
			return NO;
		}
	}
	
	// sets WEAPON_NONE if not recognised
	int chosen_weapon = OOWeaponTypeFromEquipmentIdentifierStrict(eqKey);
	
	switch (facing)
	{
		case WEAPON_FACING_FORWARD:
			forward_weapon_type = chosen_weapon;
			break;
			
		case WEAPON_FACING_AFT:
			aft_weapon_type = chosen_weapon;
			break;
			
		case WEAPON_FACING_PORT:
			port_weapon_type = chosen_weapon;
			break;
			
		case WEAPON_FACING_STARBOARD:
			starboard_weapon_type = chosen_weapon;
			break;
			
		case WEAPON_FACING_NONE:
			break;
	}
	
	return YES;
}


- (BOOL) changePassengerBerths:(int) addRemove
{
	if (addRemove == 0) return NO;
	addRemove = (addRemove > 0) ? 1 : -1;	// change only by one berth at a time!
	// NSFO!
	//unsigned 	passenger_space = [[OOEquipmentType equipmentTypeWithIdentifier:@"EQ_PASSENGER_BERTH"] requiredCargoSpace];
	//if (passenger_space == 0) passenger_space = PASSENGER_BERTH_SPACE;
	if ((max_passengers < 1 && addRemove == -1) || ([self maxAvailableCargoSpace] - current_cargo < PASSENGER_BERTH_SPACE && addRemove == 1)) return NO;
	max_passengers += addRemove;
	max_cargo -= PASSENGER_BERTH_SPACE * addRemove;
	return YES;
}


- (OOCreditsQuantity) removeMissiles
{
	[self safeAllMissiles];
	OOCreditsQuantity tradeIn = 0;
	unsigned i;
	for (i = 0; i < missiles; i++)
	{
		NSString *weapon_key = [missile_list[i] identifier];
		
		if (weapon_key != nil)
			tradeIn += (int)[UNIVERSE getEquipmentPriceForKey:weapon_key];
	}
	
	for (i = 0; i < max_missiles; i++)
	{
		[missile_entity[i] release];
		missile_entity[i] = nil;
	}
	
	missiles = 0;
	return tradeIn;
}


- (void) doTradeIn:(OOCreditsQuantity)tradeInValue forPriceFactor:(double)priceFactor
{
	if (tradeInValue != 0)
	{
		if (priceFactor < 1.0f)  tradeInValue *= priceFactor;
		credits += tradeInValue;
	}
}


- (OOCargoQuantity) cargoQuantityForType:(OOCommodityType)type
{
	OOCargoQuantity 	amount = [[shipCommodityData oo_arrayAtIndex:type] oo_intAtIndex:MARKET_QUANTITY];
	
	if  ([self status] != STATUS_DOCKED)
	{
		NSInteger		i;
		OOCommodityType co_type;
		ShipEntity		*cargoItem = nil;
		
		for (i = [cargo count] - 1; i >= 0 ; i--)
		{
			cargoItem = [cargo objectAtIndex:i];
			co_type = [cargoItem commodityType];
			if (co_type == type)
			{
				amount += [cargoItem commodityAmount];
			}
		}
	}
	
	return amount;
}


- (OOCargoQuantity) setCargoQuantityForType:(OOCommodityType)type amount:(OOCargoQuantity)amount
{
	OOMassUnit			unit = [UNIVERSE unitsForCommodity:type];
	if([self specialCargo] && unit == UNITS_TONS) return 0;	// don't do anything if we've got a special cargo...
	
	OOCargoQuantity		oldAmount = [self cargoQuantityForType:type];
	OOCargoQuantity		available = [self availableCargoSpace];
	BOOL				inPods = ([self status] != STATUS_DOCKED);
	
	// check it against the max amount.
	if (unit == UNITS_TONS && (available + oldAmount) < amount)
	{
		amount =  available + oldAmount;
	}
	// if we have 1499 kg the ship registers only 1 ton, so it's possible to exceed the max cargo:
	// eg: with maxAvailableCargoSpace 2 & gold 1499kg, you can still add 1 ton alloy. 
	else if (unit == UNITS_KILOGRAMS && amount > oldAmount)
	{
		// Allow up to 0.5 ton of kg (& g) goods above the cargo capacity but respect existing quantities.
		OOCargoQuantity		safeAmount = available * KILOGRAMS_PER_POD + MAX_KILOGRAMS_IN_SAFE;
		if (safeAmount < amount) amount = (safeAmount < oldAmount) ? oldAmount : safeAmount;
	}
	else if (unit == UNITS_GRAMS && amount > oldAmount)
	{
		OOCargoQuantity		safeAmount = available * GRAMS_PER_POD + MAX_GRAMS_IN_SAFE;
		if (safeAmount < amount) amount = (safeAmount < oldAmount) ? oldAmount : safeAmount;
	}
	
	if (inPods)
	{
		if (amount > oldAmount) // increase
		{
			[self loadCargoPodsForType:type amount:(amount - oldAmount)];
		}
		else
		{
			[self unloadCargoPodsForType:type amount:(oldAmount - amount)];
		}
	}
	else
	{
		NSMutableArray* manifest = [[NSMutableArray arrayWithArray:shipCommodityData] retain];
		NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:type]];
		[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:amount]];
		[manifest replaceObjectAtIndex:type withObject:[NSArray arrayWithArray:manifest_commodity]];
		[shipCommodityData release];
		shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
		[manifest release];
	}

	[self cargoQuantityOnBoard];
	return [[shipCommodityData oo_arrayAtIndex:type] oo_intAtIndex:MARKET_QUANTITY];
}


- (void) calculateCurrentCargo
{
	current_cargo = [self cargoQuantityOnBoard];
}


- (OOCargoQuantity) cargoQuantityOnBoard
{
	if ([self specialCargo] != nil)
	{
		return [self maxAvailableCargoSpace];
	}	
	
	/*
		The cargo array is nil when the player ship is docked, due to action in unloadCargopods. For
		this reason, we must use a slightly more complex method to determine the quantity of cargo
		carried in this case - Nikos 20090830
		
		Optimised this method, to compensate for increased usage - Kaks 20091002
	*/
	NSArray				*manifest = [NSArray arrayWithArray:[self shipCommodityData]];
	NSInteger			i, count = [manifest count];
	OOCargoQuantity		cargoQtyOnBoard = 0;
	
	for (i = count - 1; i >= 0 ; i--)
	{
		NSArray *commodityInfo = [NSArray arrayWithArray:[manifest objectAtIndex:i]];
		OOCargoQuantity quantity = [commodityInfo oo_intAtIndex:MARKET_QUANTITY];
		
		// manifest contains entries for all 17 commodities, even when their quantity is 0.
		OOMassUnit commodityUnits = [UNIVERSE unitsForCommodity:i];
		
		if (commodityUnits != UNITS_TONS)
		{
			// calculate the number of pods that would be used
			// we're using integer math, so 99/100 = 0 ,  100/100 = 1, etc...
			
			assert(KILOGRAMS_PER_POD > MAX_KILOGRAMS_IN_SAFE && GRAMS_PER_POD > MAX_GRAMS_IN_SAFE); // otherwise we're in trouble!
			
			if (commodityUnits == UNITS_KILOGRAMS)  quantity = ((KILOGRAMS_PER_POD - MAX_KILOGRAMS_IN_SAFE - 1) + quantity) / KILOGRAMS_PER_POD;
			else  quantity = ((GRAMS_PER_POD - MAX_GRAMS_IN_SAFE - 1) + quantity) / GRAMS_PER_POD;
		}
		cargoQtyOnBoard += quantity;
	}
	cargoQtyOnBoard += [[self cargo] count];
	
	return cargoQtyOnBoard;
}


- (NSMutableArray *) localMarket
{
	StationEntity *station = [self dockedStation];
	if (station == nil)  station = [UNIVERSE station];
	NSMutableArray *localMarket = [station localMarket];
	if (localMarket == nil)  localMarket = [station initialiseLocalMarketWithRandomFactor:market_rnd];
	
	return localMarket;
}


- (void) setGuiToMarketScreen
{
	NSArray			*localMarket = [self localMarket];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUIScreenID	oldScreen = gui_screen;
	
	gui_screen = GUI_SCREEN_MARKET;
	BOOL			guiChanged = (oldScreen != gui_screen);
	
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];
	
	// fix problems with economies in witchspace
	if ([UNIVERSE station] == nil)
	{
		unsigned i;
		NSMutableArray *ourEconomy = [NSMutableArray arrayWithArray:[UNIVERSE commodityDataForEconomy:0 andStation:(StationEntity*)nil andRandomFactor:0]];
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
		OOGUIRow			start_row = GUI_ROW_MARKET_START;
		OOGUIRow			row = start_row;
		NSUInteger			i, commodityCount = [shipCommodityData count];
		OOCargoQuantity		quantityInHold[commodityCount];
		NSArray				*marketDef = nil;
		
		// following changed to work whether docked or not
		
		for (i = 0; i < commodityCount; i++)
		{
			quantityInHold[i] = [[shipCommodityData oo_arrayAtIndex:i] oo_unsignedIntAtIndex:MARKET_QUANTITY];
		}
		for (i = 0; i < [cargo count]; i++)
		{
			ShipEntity *container = (ShipEntity *)[cargo objectAtIndex:i];
			quantityInHold[[container commodityType]] += [container commodityAmount];
		}
		
		[gui clearAndKeepBackground:!guiChanged];
		
		StationEntity *dockedStation = [self dockedStation];
		if (dockedStation == nil || dockedStation == [UNIVERSE station])
		{
			[gui setTitle:[UNIVERSE sun] != NULL ? (NSString *)[NSString stringWithFormat:DESC(@"@-commodity-market"), [UNIVERSE getSystemName:system_seed]] : DESC(@"commodity-market")];
		}
		else
		{
			[gui setTitle:[NSString stringWithFormat:DESC(@"@-station-commodity-market"), [dockedStation displayName]]];
		}
		
		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = 192;
		tab_stops[2] = 272;
		tab_stops[3] = 346;
		[gui setTabStops:tab_stops];
		
		[gui setColor:[OOColor greenColor] forRow:GUI_ROW_MARKET_KEY];
		[gui setArray:[NSArray arrayWithObjects: DESC(@"commodity-column-title"), OOPadStringTo(DESC(@"price-column-title"),7.0),
							 OOPadStringTo(DESC(@"for-sale-column-title"),11.0), OOPadStringTo(DESC(@"in-hold-column-title"),15.0), nil] forRow:GUI_ROW_MARKET_KEY];
		
		for (i = 0; i < commodityCount; i++)
		{
			marketDef = [localMarket oo_arrayAtIndex:i];
			
			NSString* desc = [NSString stringWithFormat:@" %@ ", CommodityDisplayNameForCommodityArray(marketDef)];
			OOCargoQuantity available_units = [marketDef oo_unsignedIntAtIndex:MARKET_QUANTITY];
			OOCargoQuantity units_in_hold = quantityInHold[i];
			OOCreditsQuantity pricePerUnit = [marketDef oo_unsignedIntAtIndex:MARKET_PRICE];
			OOMassUnit unit = [UNIVERSE unitsForCommodity:i];
			
			NSString *available = OOPadStringTo(((available_units > 0) ? (NSString *)[NSString stringWithFormat:@"%d",available_units] : DESC(@"commodity-quantity-none")), 6.0);
			NSString *price = OOPadStringTo([NSString stringWithFormat:@" %.1f ",0.1 * pricePerUnit],7.0);
			
			// this works with up to 9999 tons of gemstones. Any more than that, they deserve the formatting they get! :)
			
			NSString *owned = OOPadStringTo((units_in_hold > 0) ? (NSString *)[NSString stringWithFormat:@"%d",units_in_hold] : DESC(@"commodity-quantity-none"), 10.0);
			NSString *units = DisplayStringForMassUnit(unit);
			NSString *units_available = [NSString stringWithFormat:@" %@ %@ ",available, units];
			NSString *units_owned = [NSString stringWithFormat:@" %@ %@ ",owned, units];
			
			[gui setKey:[NSString stringWithFormat:@"%ld",i] forRow:row];
			[gui setArray:[NSArray arrayWithObjects: desc, price, units_available, units_owned, nil] forRow:row++];
		}
		 // actually count the containers and  valuables (may be > max_cargo)
		current_cargo = [self cargoQuantityOnBoard];
		if (current_cargo > [self maxAvailableCargoSpace]) current_cargo = [self maxAvailableCargoSpace]; 
		
		[gui setText:[NSString stringWithFormat:DESC(@"cash-@-load-d-of-d"), OOCredits(credits), current_cargo, [self maxAvailableCargoSpace]]  forRow: GUI_ROW_MARKET_CASH];
		
		if ([self status] == STATUS_DOCKED)	// can only buy or sell in dock
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
	
	[[UNIVERSE gameView] clearMouse];
	
	[self setShowDemoShips:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:[self status] == STATUS_DOCKED];
	
	if (guiChanged)
	{
		[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"overlay"];
		[gui setBackgroundTextureKey:@"market"];
		[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
	}
}


- (OOGUIScreenID) guiScreen
{
	return gui_screen;
}


- (BOOL) marketFlooded:(OOCommodityType)index
{
	NSArray *commodityArray = [[self localMarket] oo_arrayAtIndex:index];
	int available_units = [commodityArray oo_intAtIndex:MARKET_QUANTITY];
	
	return (available_units >= 127);
}


- (BOOL) tryBuyingCommodity:(OOCommodityType)index all:(BOOL)all
{
	if (![self isDocked])  return NO; // can't buy if not docked.
	
	NSMutableArray		*localMarket = [self localMarket];
	NSArray				*commodityArray	= [localMarket objectAtIndex:index];
	OOCreditsQuantity	pricePerUnit	= [commodityArray oo_unsignedIntAtIndex:MARKET_PRICE];
	OOMassUnit			unit			= [UNIVERSE unitsForCommodity:index];

	if (specialCargo != nil && unit == UNITS_TONS)
	{
		return NO;									// can't buy tons of stuff when carrying a specialCargo
	}
	NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
	NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:index]];
	NSMutableArray* market_commodity = [NSMutableArray arrayWithArray:[localMarket oo_arrayAtIndex:index]];
	int manifest_quantity = [manifest_commodity oo_intAtIndex:MARKET_QUANTITY];
	int market_quantity = [market_commodity oo_intAtIndex:MARKET_QUANTITY];
	
	int purchase = all ? 127 : 1;
	if (purchase > market_quantity)
	{
		purchase = market_quantity;					// limit to what's available
	}
	if (purchase * pricePerUnit > credits)
	{
		purchase = floor (credits / pricePerUnit);	// limit to what's affordable
	}
	// TODO - fix brokenness here...
	if (unit == UNITS_TONS && purchase + current_cargo > [self maxAvailableCargoSpace])
	{
		purchase = [self availableCargoSpace];		// limit to available cargo space
	}
	else
	{
		if (current_cargo == [self maxAvailableCargoSpace])
		{
			// other cases are fine so long as buying is limited to <1000kg / <1000000g
			// but if this case is true, we need to see if there is more space in
			// the manifest (safe) or an already-accounted-for pod
			if (unit == UNITS_KILOGRAMS)
			{
				if (manifest_quantity % KILOGRAMS_PER_POD <= MAX_KILOGRAMS_IN_SAFE && (manifest_quantity + purchase) % KILOGRAMS_PER_POD > MAX_KILOGRAMS_IN_SAFE)
				{
					// going from < n500 to >= n500 would increase pods needed by 1
					purchase = MAX_KILOGRAMS_IN_SAFE - manifest_quantity; // max possible
				}
			}
			else // UNITS_GRAMS
			{
				if (manifest_quantity % GRAMS_PER_POD <= MAX_GRAMS_IN_SAFE && (manifest_quantity + purchase) % GRAMS_PER_POD > MAX_GRAMS_IN_SAFE)
				{
					// going from < n500000 to >= n500000 would increase pods needed by 1
					purchase = MAX_GRAMS_IN_SAFE - manifest_quantity; // max possible
				}
			}
		}
	}
	if (purchase <= 0)
	{
		return NO;									// stop if that results in nothing to be bought
	}
	
	manifest_quantity += purchase;
	market_quantity -= purchase;
	credits -= pricePerUnit * purchase;
	
	[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
	[market_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:market_quantity]];
	[manifest replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:manifest_commodity]];
	[localMarket replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:market_commodity]];
	
	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	
	[self calculateCurrentCargo];
	
	if ([UNIVERSE autoSave])  [UNIVERSE setAutoSaveNow:YES];
	
	[self doScriptEvent:OOJSID("playerBoughtCargo") withArguments:[NSArray arrayWithObjects:CommodityTypeToString(index), [NSNumber numberWithInt:purchase], [NSNumber numberWithUnsignedLongLong:pricePerUnit], nil]];
	if ([UNIVERSE legalStatusOfCommodity:[market_commodity objectAtIndex:MARKET_NAME]] > 0)
	{
		[roleWeightFlags setObject:[NSNumber numberWithInt:1] forKey:@"bought-illegal"];
	}
	else
	{
		[roleWeightFlags setObject:[NSNumber numberWithInt:1] forKey:@"bought-legal"];
	}
	
	return YES;
}


- (BOOL) trySellingCommodity:(OOCommodityType)index all:(BOOL)all
{
	if (![self isDocked])  return NO; // can't sell if not docked.
	
	NSMutableArray *localMarket = [self localMarket];
	int available_units = [[shipCommodityData oo_arrayAtIndex:index] oo_intAtIndex:MARKET_QUANTITY];
	int pricePerUnit = [[localMarket oo_arrayAtIndex:index] oo_intAtIndex:MARKET_PRICE];
	
	if (available_units == 0)  return NO;
	
	NSMutableArray* manifest =  [NSMutableArray arrayWithArray:shipCommodityData];
	NSMutableArray* manifest_commodity = [NSMutableArray arrayWithArray:[manifest oo_arrayAtIndex:index]];
	NSMutableArray* market_commodity = [NSMutableArray arrayWithArray:[localMarket oo_arrayAtIndex:index]];
	int manifest_quantity = [manifest_commodity oo_intAtIndex:MARKET_QUANTITY];
	int market_quantity =   [market_commodity oo_intAtIndex:MARKET_QUANTITY];
	
	int sell = all ? 127 : 1;
	if (sell > available_units)
		sell = available_units;					// limit to what's in the hold
	if (sell + market_quantity > 127)
		sell = 127 - market_quantity;			// avoid flooding the market
	if (sell <= 0)
		return NO;								// stop if that results in nothing to be sold
	
	current_cargo -= sell;
	manifest_quantity -= sell;
	market_quantity += sell;
	credits += pricePerUnit * sell;
	
	[manifest_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:manifest_quantity]];
	[market_commodity replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithInt:market_quantity]];
	[manifest replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:manifest_commodity]];
	[localMarket replaceObjectAtIndex:index withObject:[NSArray arrayWithArray:market_commodity]];
	
	[shipCommodityData release];
	shipCommodityData = [[NSArray arrayWithArray:manifest] retain];
	
	if ([UNIVERSE autoSave]) [UNIVERSE setAutoSaveNow:YES];
	
	[self doScriptEvent:OOJSID("playerSoldCargo") withArguments:[NSArray arrayWithObjects:CommodityTypeToString(index), [NSNumber numberWithInt:sell], [NSNumber numberWithInt: pricePerUnit], nil]];
	
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


- (BOOL) canAddEquipment:(NSString *)equipmentKey inContext:(NSString *)context
{
	if ([equipmentKey isEqualToString:@"EQ_RENOVATION"] && !(ship_trade_in_factor < 85 || [[[self shipSubEntityEnumerator] allObjects] count] < [self maxShipSubEntities]))  return NO;
	if (![super canAddEquipment:equipmentKey inContext:context])  return NO;
	
	NSArray *conditions = [[OOEquipmentType equipmentTypeWithIdentifier:equipmentKey] conditions];
	if (conditions != nil && ![self scriptTestConditions:conditions])  return NO;
	
	return YES;
}


- (BOOL) addEquipmentItem:(NSString *)equipmentKey inContext:(NSString *)context
{
	return [self addEquipmentItem:equipmentKey withValidation:YES inContext:context];
}


- (BOOL) addEquipmentItem:(NSString *)equipmentKey withValidation:(BOOL)validateAddition inContext:(NSString *)context
{
	// deal with trumbles..
	if ([equipmentKey isEqualToString:@"EQ_TRUMBLE"])
	{
		/*	Bug fix: must return here if eqKey == @"EQ_TRUMBLE", even if
			trumbleCount >= 1. Otherwise, the player becomes immune to
			trumbles. See comment in -setCommanderDataFromDictionary: for more
			details.
		 -- Ahruman 2008-12-04
		 */
		// the old trumbles will kill the new one if there are enough of them.
		if ((trumbleCount < PLAYER_MAX_TRUMBLES / 6) || (trumbleCount < PLAYER_MAX_TRUMBLES / 3 && ranrot_rand() % 2 > 0))
		{
			[self addTrumble:trumble[ranrot_rand() % PLAYER_MAX_TRUMBLES]];	// randomise its looks.
			return YES;
		}
		return NO;
	}
	
	BOOL OK = [super addEquipmentItem:equipmentKey withValidation:validateAddition inContext:context];
	
	if (OK)
	{
		if ([equipmentKey isEqual:@"EQ_ADVANCED_COMPASS"])	[self setCompassMode:COMPASS_MODE_PLANET];
		
		[self addEqScriptForKey:equipmentKey];
	}
	return OK;
}


- (void) removeEquipmentItem:(NSString *)equipmentKey
{
	[self removeEqScriptForKey:equipmentKey];
	if([equipmentKey isEqualToString:@"EQ_ADVANCED_COMPASS"]) [self setCompassMode:COMPASS_MODE_BASIC];
	[super removeEquipmentItem:equipmentKey];
}


- (void) addEquipmentFromCollection:(id)equipment
{
	NSDictionary	*dict = nil;
	NSEnumerator	*eqEnum = nil;
	NSString	*eqDesc = nil;
	
	// Pass 1: Load the entire collection.
	if ([equipment isKindOfClass:[NSDictionary class]])
	{
		dict = equipment;
		eqEnum = [equipment keyEnumerator];
	}
	else if ([equipment isKindOfClass:[NSArray class]] || [equipment isKindOfClass:[NSSet class]])
	{
		eqEnum = [equipment objectEnumerator];
	}
	else if ([equipment isKindOfClass:[NSString class]])
	{
		eqEnum = [[NSArray arrayWithObject:equipment] objectEnumerator];
	}
	else
	{
		return;
	}
	
	while ((eqDesc = [eqEnum nextObject]))
	{
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
		if ([eqDesc isEqualToString:@"EQ_TRUMBLE"])  continue;
		
		// Traditional form is a dictionary of booleans; we only accept those where the value is true.
		if (dict != nil && ![dict oo_boolForKey:eqDesc])  continue;
		
		// We need to add the entire collection without validation first and then remove the items that are
		// not compliant (like items that do not satisfy the requiresEquipment criterion). This is to avoid
		// unintentionally excluding valid equipment, just because the required equipment existed but had
		// not been yet added to the equipment list at the time of the canAddEquipment validation check.
		// Nikos, 20080817.
		[self addEquipmentItem:eqDesc withValidation:NO inContext:@"loading"];
	}
	
	// Pass 2: Remove items that do not satisfy validation criteria (like requires_equipment etc.).
	if ([equipment isKindOfClass:[NSDictionary class]])
	{
		eqEnum = [equipment keyEnumerator];
	}
	else if ([equipment isKindOfClass:[NSArray class]] || [equipment isKindOfClass:[NSSet class]])
	{
		eqEnum = [equipment objectEnumerator];
	}
	else if ([equipment isKindOfClass:[NSString class]])
	{
		eqEnum = [[NSArray arrayWithObject:equipment] objectEnumerator];
	}
	// Now remove items that should not be in the equipment list.
	while ((eqDesc = [eqEnum nextObject]))
	{
		if (![self equipmentValidToAdd:eqDesc whileLoading:YES inContext:@"loading"])
		{
			[self removeEquipmentItem:eqDesc];
		}
	}
}


- (BOOL) hasOneEquipmentItem:(NSString *)itemKey includeMissiles:(BOOL)includeMissiles
{
	// Check basic equipment the normal way.
	if ([super hasOneEquipmentItem:itemKey includeMissiles:NO whileLoading:NO])  return YES;
	
	// Custom handling for player missiles.
	if (includeMissiles)
	{
		unsigned i;
		for (i = 0; i < max_missiles; i++)
		{
			if ([[self missileForPylon:i] hasPrimaryRole:itemKey])  return YES;
		}
	}
	
	if ([itemKey isEqualToString:@"EQ_TRUMBLE"])
	{
		return [self trumbleCount] > 0;
	}
	
	return NO;
}


- (BOOL) hasPrimaryWeapon:(OOWeaponType)weaponType
{
	if (forward_weapon_type == weaponType || aft_weapon_type == weaponType)  return YES;
	if (port_weapon_type == weaponType || starboard_weapon_type == weaponType)  return YES;
	
	return [super hasPrimaryWeapon:weaponType];
}


- (BOOL) removeExternalStore:(OOEquipmentType *)eqType
{
	NSString	*identifier = [eqType identifier];
	
	// Look for matching missile.
	unsigned i;
	for (i = 0; i < max_missiles; i++)
	{
		if ([[self missileForPylon:i] hasPrimaryRole:identifier])
		{
			[self removeFromPylon:i];
			
			// Just remove one at a time.
			return YES;
		}
	}
	return NO;
}


- (BOOL) removeFromPylon:(NSUInteger)pylon
{
	if (pylon >= max_missiles) return NO;
	
	if (missile_entity[pylon] != nil)
	{
		NSString	*identifier = [missile_entity[pylon] primaryRole];
		[super removeExternalStore:[OOEquipmentType equipmentTypeWithIdentifier:identifier]];

		// Remove the missile (must wait until we've finished with its identifier string!)
		[missile_entity[pylon] release];
		missile_entity[pylon] = nil;
		
		[self tidyMissilePylons];
		
		// This should be the currently selected missile, deselect it.
		if (pylon >= activeMissile)
		{
			if (activeMissile == missiles && missiles > 0) activeMissile--;
			if (activeMissile > 0) activeMissile--;
			else activeMissile = max_missiles - 1;
			
			[self selectNextMissile];
		}
		
		return YES;
	}

	return NO;
}


- (NSUInteger) parcelCount
{
	return [parcels count];
}


- (NSUInteger) passengerCount
{
	return [passengers count];
}


- (NSUInteger) passengerCapacity
{
	return max_passengers;
}


- (BOOL) hasHostileTarget
{
	ShipEntity *playersTarget = [self primaryTarget];
	return ([playersTarget isShip] && [playersTarget hasHostileTarget] && [playersTarget primaryTarget] == self);
}


- (void) receiveCommsMessage:(NSString *) message_text from:(ShipEntity *) other
{
	if ([self status] == STATUS_DEAD || [self status] == STATUS_DOCKED)
	{
		// only when in flight
		return;
	}
	[UNIVERSE addCommsMessage:[NSString stringWithFormat:@"%@:\n %@", [other displayName], message_text] forCount:4.5];
	[super receiveCommsMessage:message_text from:other];
}


- (void) getFined
{
	if (legalStatus == 0)  return;				// nothing to pay for
	
	OOGovernmentID local_gov = [[UNIVERSE currentSystemData] oo_intForKey:KEY_GOVERNMENT];
	if ([UNIVERSE inInterstellarSpace])  local_gov = 1;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
	OOCreditsQuantity fine = 500 + ((local_gov < 2 || local_gov > 5) ? 500 : 0);
	fine *= legalStatus;
	if (fine > credits)
	{
		int payback = (int)(legalStatus * credits / fine);
		[self setBounty:(legalStatus-payback) withReason:kOOLegalStatusReasonPaidFine];
		credits = 0;
	}
	else
	{
		[self setBounty:0 withReason:kOOLegalStatusReasonPaidFine];
		credits -= fine;
	}
	
	// one of the fined-@-credits strings includes expansion tokens
	NSString *fined_message = [NSString stringWithFormat:OOExpandKey(@"fined-@-credits"), OOCredits(fine)];
	[self addMessageToReport:fined_message];
	[UNIVERSE forceWitchspaceEntries];
	ship_clock_adjust += 24 * 3600;	// take up a day
}


- (void) adjustTradeInFactorBy:(int)value
{
	ship_trade_in_factor += value;
	if (ship_trade_in_factor < 75)  ship_trade_in_factor = 75;
	if (ship_trade_in_factor > 100)  ship_trade_in_factor = 100;
}


- (int) tradeInFactor
{
	return ship_trade_in_factor;
}


- (double) renovationCosts
{
	// 5% of value of ships wear + correction for missing subentities.
	OOCreditsQuantity shipValue = [UNIVERSE tradeInValueForCommanderDictionary:[self commanderDataDictionary]];

	OOShipRegistry		*registry = [OOShipRegistry sharedRegistry];
	NSDictionary		*shipyardInfo = [registry shipyardInfoForKey:[self shipDataKey]];
	double			renovationFactor = [shipyardInfo oo_doubleForKey:KEY_RENOVATION_MULTIPLIER defaultValue:1.0];

	double costs = 0.005 * (100 - ship_trade_in_factor) * shipValue;
	costs += 0.01 * shipValue * [self missingSubEntitiesAdjustment];
	costs *= renovationFactor;
	return cunningFee(costs, 0.05);
}


- (void) setDefaultViewOffsets
{
	float halfLength = 0.5f * (boundingBox.max.z - boundingBox.min.z);
	float halfWidth = 0.5f * (boundingBox.max.x - boundingBox.min.x);

	forwardViewOffset = make_vector(0.0f, 0.0f, boundingBox.max.z - halfLength);
	aftViewOffset = make_vector(0.0f, 0.0f, boundingBox.min.z + halfLength);
	portViewOffset = make_vector(boundingBox.min.x + halfWidth, 0.0f, 0.0f);
	starboardViewOffset = make_vector(boundingBox.max.x - halfWidth, 0.0f, 0.0f);
	customViewOffset = kZeroVector;
}


- (void) setDefaultCustomViews
{
	NSArray *customViews = [[[OOShipRegistry sharedRegistry] shipInfoForKey:PLAYER_SHIP_DESC] oo_arrayForKey:@"custom_views"];
	
	[_customViews release];
	_customViews = nil;
	_customViewIndex = 0;
	if (customViews != nil)
	{
		_customViews = [customViews retain];
	}
}


- (Vector) weaponViewOffset
{
	switch (currentWeaponFacing)
	{
		case WEAPON_FACING_FORWARD:
			return forwardViewOffset;
		case WEAPON_FACING_AFT:
			return aftViewOffset;
		case WEAPON_FACING_PORT:
			return portViewOffset;
		case WEAPON_FACING_STARBOARD:
			return starboardViewOffset;
			
		case WEAPON_FACING_NONE:
			// N.b.: this case should never happen.
			return customViewOffset;
	}
	return kZeroVector;
}


- (void) setUpTrumbles
{
	NSMutableString *trumbleDigrams = [NSMutableString stringWithCapacity:256];
	unichar	xchar = (unichar)0;
	unichar digramchars[2];

	while ([trumbleDigrams length] < PLAYER_MAX_TRUMBLES + 2)
	{
		NSString *commanderName = [self commanderName];
		if ([commanderName length] > 0)
		{
			[trumbleDigrams appendFormat:@"%@%@", commanderName, [[self mesh] modelName]];
		}
		else
		{
			[trumbleDigrams appendString:@"Some Random Text!"];
		}
	}
	int i;
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
	{
		digramchars[0] = ([trumbleDigrams characterAtIndex:i] & 0x007f) | 0x0020;
		digramchars[1] = (([trumbleDigrams characterAtIndex:i + 1] ^ xchar) & 0x007f) | 0x0020;
		xchar = digramchars[0];
		NSString *digramstring = [NSString stringWithCharacters:digramchars length:2];
		[trumble[i] release];
		trumble[i] = [[OOTrumble alloc] initForPlayer:self digram:digramstring];
	}
	
	trumbleCount = 0;
	
	[self setTrumbleAppetiteAccumulator:0.0f];
}


- (void) addTrumble:(OOTrumble *)papaTrumble
{
	if (trumbleCount >= PLAYER_MAX_TRUMBLES)
	{
		return;
	}
	OOTrumble *trumblePup = trumble[trumbleCount];
	[trumblePup spawnFrom:papaTrumble];
	trumbleCount++;
}


- (void) removeTrumble:(OOTrumble *)deadTrumble
{
	if (trumbleCount <= 0)
	{
		return;
	}
	NSUInteger	trumble_index = NSNotFound;
	NSUInteger	i;
	
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


- (NSUInteger) trumbleCount
{
	return trumbleCount;
}


- (id)trumbleValue
{
	NSString	*namekey = [NSString stringWithFormat:@"%@-humbletrash", [self commanderName]];
	int			trumbleHash;
	
	clear_checksum();
	[self mungChecksumWithNSString:[self commanderName]];
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(trumbleCount);
	
	[[NSUserDefaults standardUserDefaults] setInteger:trumbleHash forKey:namekey];
	
	int i;
	NSMutableArray *trumbleArray = [NSMutableArray arrayWithCapacity:PLAYER_MAX_TRUMBLES];
	for (i = 0; i < PLAYER_MAX_TRUMBLES; i++)
	{
		[trumbleArray addObject:[trumble[i] dictionary]];
	}
	
	return [NSArray arrayWithObjects:[NSNumber numberWithUnsignedInteger:trumbleCount], [NSNumber numberWithInt:trumbleHash], trumbleArray, nil];
}


- (void) setTrumbleValueFrom:(NSObject*) trumbleValue
{
	BOOL info_failed = NO;
	int trumbleHash;
	int putativeHash = 0;
	int putativeNTrumbles = 0;
	NSArray *putativeTrumbleArray = nil;
	int i;
	NSString *namekey = [NSString stringWithFormat:@"%@-humbletrash", [self commanderName]];
	
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
				putativeNTrumbles = [values oo_intAtIndex:0];
			if ([values count] >= 2)
				putativeHash = [values oo_intAtIndex:1];
			if ([values count] >= 3)
				putativeTrumbleArray = [values oo_arrayAtIndex:2];
		}
		// calculate a hash for the putative values
		clear_checksum();
		[self mungChecksumWithNSString:[self commanderName]];
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
			[self mungChecksumWithNSString:[self commanderName]];
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
		putativeHash = (int)[[NSUserDefaults standardUserDefaults] integerForKey:namekey];
		for (i = 1; (info_failed)&&(i < PLAYER_MAX_TRUMBLES); i++)
		{
			clear_checksum();
			[self mungChecksumWithNSString:[self commanderName]];
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
			[trumble[i] setFromDictionary:[putativeTrumbleArray oo_dictionaryAtIndex:i]];
	}
	
	clear_checksum();
	[self mungChecksumWithNSString:[self commanderName]];
	munge_checksum(credits);
	munge_checksum(ship_kills);
	trumbleHash = munge_checksum(trumbleCount);
	
	[[NSUserDefaults standardUserDefaults]  setInteger:trumbleHash forKey:namekey];
}


- (float) trumbleAppetiteAccumulator
{
	return _trumbleAppetiteAccumulator;
}


- (void) setTrumbleAppetiteAccumulator:(float)value
{
	_trumbleAppetiteAccumulator = value;
}


- (void) mungChecksumWithNSString:(NSString *)str
{
	if (str == nil)  return;
	
	NSUInteger i, length = [str length];
	for (i = 0; i < length; i++)
	{
		munge_checksum([str characterAtIndex:i]);
	}
}


- (NSString *) screenModeStringForWidth:(unsigned)inWidth height:(unsigned)inHeight refreshRate:(float)inRate
{
	if (0.0f != inRate)
	{
		return [NSString stringWithFormat:DESC(@"gameoptions-fullscreen-mode-d-by-d-at-g-hz"), inWidth, inHeight, inRate];
	}
	else
	{
		return [NSString stringWithFormat:DESC(@"gameoptions-fullscreen-mode-d-by-d"), inWidth, inHeight];
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


// override shipentity to stop foundTarget being changed during escape sequence
- (void) setFoundTarget:(Entity *) targetEntity
{
	/* Rare, but can happen, e.g. if a Q-mine goes off nearby during
	 * the sequence */
	if ([self status] == STATUS_ESCAPE_SEQUENCE)
	{
		return;
	}
	[_foundTarget release];
	_foundTarget = [targetEntity weakRetain];
}


// override shipentity addTarget to implement target_memory
- (void) addTarget:(Entity *) targetEntity
{
	if ([self status] != STATUS_IN_FLIGHT && [self status] != STATUS_WITCHSPACE_COUNTDOWN)  return;
	if (targetEntity == self)  return;
	
	[super addTarget:targetEntity];
	
	if ([targetEntity isWormhole])
	{
		assert ([self hasEquipmentItem:@"EQ_WORMHOLE_SCANNER"]);
		[self addScannedWormhole:(WormholeEntity*)targetEntity];
	}
	// wormholes don't go in target memory
	else if ([self hasEquipmentItem:@"EQ_TARGET_MEMORY"] && targetEntity != nil)
	{
		OOWeakReference *targetRef = [targetEntity weakSelf];
		NSUInteger i = [target_memory indexOfObject:targetRef];
		// if already in target memory, preserve that and just change the index
		if (i != NSNotFound)
		{
			target_memory_index = i;
		}		
		else
		{
			i = [target_memory indexOfObject:[NSNull null]];
			// find and use a blank space in memory
			if (i != NSNotFound)
			{
				[target_memory replaceObjectAtIndex:i withObject:targetRef];
				target_memory_index = i;
			}
			else
			{
				// use the next memory space
				target_memory_index = (target_memory_index + 1) % PLAYER_TARGET_MEMORY_SIZE;
				[target_memory replaceObjectAtIndex:target_memory_index withObject:targetRef];
			}
		}
	}
	
	if (ident_engaged)
	{
		[self playIdentLockedOn];
		[self printIdentLockedOnForMissile:NO];
	}
	else if ([targetEntity isShip] && [self weaponsOnline]) // Only let missiles target-lock onto ships
	{
		if ([missile_entity[activeMissile] isMissile])
		{
			missile_status = MISSILE_STATUS_TARGET_LOCKED;
			[missile_entity[activeMissile] addTarget:targetEntity];
			[self playMissileLockedOn];
			[self printIdentLockedOnForMissile:YES];
		}
		else // It's a mine or something
		{
			missile_status = MISSILE_STATUS_ARMED;
			[self playIdentLockedOn];
			[self printIdentLockedOnForMissile:NO];
		}
	}
}


- (void) clearTargetMemory
{
	int i = 0;
	int j = [target_memory count];
	for (i = 0; i < PLAYER_TARGET_MEMORY_SIZE; i++)
	{
		if (j > i)
		{
			[target_memory replaceObjectAtIndex:i withObject:[NSNull null]];
		}
		else
		{
			[target_memory addObject:[NSNull null]];
		}
	}
	target_memory_index = 0;
}


- (NSMutableArray *) targetMemory
{
	return target_memory;
}

- (BOOL) moveTargetMemoryBy:(int)delta
{
	unsigned i = 0;
	while (i++ < PLAYER_TARGET_MEMORY_SIZE)	// limit loops
	{
		target_memory_index += delta;
		while (target_memory_index < 0)  target_memory_index += PLAYER_TARGET_MEMORY_SIZE;
		while (target_memory_index >= PLAYER_TARGET_MEMORY_SIZE)  target_memory_index -= PLAYER_TARGET_MEMORY_SIZE;
		id targ_id = [target_memory objectAtIndex:target_memory_index];
		if ([targ_id isProxy])
		{
			ShipEntity *potential_target = [(OOWeakReference *)targ_id weakRefUnderlyingObject];
		
			if ((potential_target)&&(potential_target->isShip)&&([potential_target isInSpace]))
			{
				if (potential_target->zero_distance < SCANNER_MAX_RANGE2 && (![potential_target isCloaked]))
				{
					[super addTarget:potential_target];
					if (missile_status != MISSILE_STATUS_SAFE)
					{
						if( [missile_entity[activeMissile] isMissile])
						{
							[missile_entity[activeMissile] addTarget:potential_target];
							missile_status = MISSILE_STATUS_TARGET_LOCKED;
							[self printIdentLockedOnForMissile:YES];
						}
						else
						{
							missile_status = MISSILE_STATUS_ARMED;
							[self playIdentLockedOn];
							[self printIdentLockedOnForMissile:NO];
						}
					}
					else
					{
						ident_engaged = YES;
						[self printIdentLockedOnForMissile:NO];
					}
					[self playTargetSwitched];
					return YES;
				}
			}
			else
			{
				[target_memory replaceObjectAtIndex:target_memory_index withObject:[NSNull null]];
			}
		}
	}
	
	[self playNoTargetInMemory];
	return NO;
}


- (void) printIdentLockedOnForMissile:(BOOL)missile
{
	NSString			*fmt = nil;
	if ([self primaryTarget] == nil) return;
	
	if (missile)  fmt = DESC(@"missile-locked-onto-@");
	else  fmt = DESC(@"ident-locked-onto-@");
	
	[UNIVERSE addMessage:[NSString stringWithFormat:fmt, [[self primaryTarget] identFromShip:self]]
				forCount:4.5];
}


- (Quaternion) customViewQuaternion
{
	return customViewQuaternion;
}


- (OOMatrix) customViewMatrix
{
	return customViewMatrix;
}


- (Vector) customViewOffset
{
	return customViewOffset;
}


- (Vector) customViewForwardVector
{
	return customViewForwardVector;
}


- (Vector) customViewUpVector
{
	return customViewUpVector;
}


- (Vector) customViewRightVector
{
	return customViewRightVector;
}


- (NSString *) customViewDescription
{
	return customViewDescription;
}


- (void) resetCustomView
{
	[self setCustomViewDataFromDictionary:[_customViews oo_dictionaryAtIndex:_customViewIndex]];
}


- (void) setCustomViewDataFromDictionary:(NSDictionary *)viewDict
{
	customViewMatrix = kIdentityMatrix;
	customViewOffset = kZeroVector;
	if (viewDict == nil)  return;
	
	customViewQuaternion = [viewDict oo_quaternionForKey:@"view_orientation"];
	
	customViewRightVector = vector_right_from_quaternion(customViewQuaternion);
	customViewUpVector = vector_up_from_quaternion(customViewQuaternion);
	customViewForwardVector = vector_forward_from_quaternion(customViewQuaternion);
	
	Quaternion q1 = customViewQuaternion;
	q1.w = -q1.w;
	customViewMatrix = OOMatrixForQuaternionRotation(q1);
	
	customViewOffset = [viewDict oo_vectorForKey:@"view_position"];
	customViewDescription = [viewDict oo_stringForKey:@"view_description"];
	
	NSString *facing = [[viewDict oo_stringForKey:@"weapon_facing"] lowercaseString];
	if ([facing isEqual:@"aft"])
	{
		currentWeaponFacing = WEAPON_FACING_AFT;
	}
	else if ([facing isEqual:@"port"])
	{
		currentWeaponFacing = WEAPON_FACING_PORT;
	}
	else if ([facing isEqual:@"starboard"])
	{
		currentWeaponFacing = WEAPON_FACING_STARBOARD;
	}
	else if ([facing isEqual:@"forward"])
	{
		currentWeaponFacing = WEAPON_FACING_FORWARD;
	}
	// if the weapon facing is unset / unknown, 
	// don't change current weapon facing!
}


- (BOOL) showInfoFlag
{
	return show_info_flag;
}


- (NSDictionary *) missionOverlayDescriptor
{
	return _missionOverlayDescriptor;
}


- (NSDictionary *) missionOverlayDescriptorOrDefault
{
	NSDictionary *result = [self missionOverlayDescriptor];
	if (result == nil)
	{
		if ([[self missionTitle] length] == 0)
		{
			result = [UNIVERSE screenTextureDescriptorForKey:@"mission_overlay_no_title"];
		}
		else
		{
			result = [UNIVERSE screenTextureDescriptorForKey:@"mission_overlay_with_title"];
		}
	}
	
	return result;
}


- (void) setMissionOverlayDescriptor:(NSDictionary *)descriptor
{
	if (descriptor != _missionOverlayDescriptor)
	{
		[_missionOverlayDescriptor autorelease];
		_missionOverlayDescriptor = [descriptor copy];
	}
}


- (NSDictionary *) missionBackgroundDescriptor
{
	return _missionBackgroundDescriptor;
}


- (NSDictionary *) missionBackgroundDescriptorOrDefault
{
	NSDictionary *result = [self missionBackgroundDescriptor];
	if (result == nil)
	{
		result = [UNIVERSE screenTextureDescriptorForKey:@"mission"];
	}
	
	return result;
}


- (void) setMissionBackgroundDescriptor:(NSDictionary *)descriptor
{
	if (descriptor != _missionBackgroundDescriptor)
	{
		[_missionBackgroundDescriptor autorelease];
		_missionBackgroundDescriptor = [descriptor copy];
	}
}


- (OOGUIBackgroundSpecial) missionBackgroundSpecial
{
	return _missionBackgroundSpecial;
}


- (void) setMissionBackgroundSpecial:(NSString *)special
{
	if (special == nil) {
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;
	}
	else if ([special isEqualToString:@"SHORT_RANGE_CHART"])
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_SHORT;
	}
	else if ([special isEqualToString:@"LONG_RANGE_CHART"])
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
	}
	else if ([special isEqualToString:@"LONG_RANGE_CHART_SHORTEST"])
	{
		if ([self hasEquipmentItem:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG_ANA_SHORTEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
		}
	}
	else if ([special isEqualToString:@"LONG_RANGE_CHART_QUICKEST"])
	{
		if ([self hasEquipmentItem:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG_ANA_QUICKEST;
		}
		else
		{
			_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_LONG;
		}
	} 
	else 
	{
		_missionBackgroundSpecial = GUI_BACKGROUND_SPECIAL_NONE;
	}
}


- (void) setMissionExitScreen:(OOGUIScreenID)screen
{
	_missionExitScreen = screen;
}


- (OOGUIScreenID) missionExitScreen
{
	return _missionExitScreen;
}


- (NSDictionary *) equipScreenBackgroundDescriptor
{
	return _equipScreenBackgroundDescriptor;
}


- (void) setEquipScreenBackgroundDescriptor:(NSDictionary *)descriptor
{
	if (descriptor != _equipScreenBackgroundDescriptor)
	{
		[_equipScreenBackgroundDescriptor autorelease];
		_equipScreenBackgroundDescriptor = [descriptor copy];
	}
}


- (NSArray *) worldScriptNames
{
	return [worldScripts allKeys];
}


- (NSDictionary *) worldScriptsByName
{
	return [[worldScripts copy] autorelease];
}


- (void) doScriptEvent:(jsid)message inContext:(JSContext *)context withArguments:(jsval *)argv count:(uintN)argc
{
	[super doScriptEvent:message inContext:context withArguments:argv count:argc];
	[self doWorldScriptEvent:message inContext:context withArguments:argv count:argc timeLimit:0.0];
}


- (BOOL) doWorldEventUntilMissionScreen:(jsid)message
{
	NSEnumerator	*scriptEnum = [worldScripts objectEnumerator];
	OOScript		*theScript;

	// Check for the presence of report messages first.
	if (gui_screen != GUI_SCREEN_MISSION && [dockingReport length] > 0 && [self isDocked] && ![[self dockedStation] suppressArrivalReports])
	{
		[self setGuiToDockingReportScreen];	// go here instead!
		[[UNIVERSE messageGUI] clear];
		return YES;
	}
	
	JSContext *context = OOJSAcquireContext();
	while ((theScript = [scriptEnum nextObject]) && gui_screen != GUI_SCREEN_MISSION && [self isDocked])
	{
		[theScript callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
	}
	OOJSRelinquishContext(context);
	
	if (gui_screen == GUI_SCREEN_MISSION)
	{
		// remove any comms/console messages from the screen!
		[[UNIVERSE messageGUI] clear];
		return YES;
	}
	
	return NO;
}


- (void) doWorldScriptEvent:(jsid)message inContext:(JSContext *)context withArguments:(jsval *)argv count:(uintN)argc timeLimit:(OOTimeDelta)limit
{
	NSParameterAssert(context != NULL && JS_IsInRequest(context));
	
	NSEnumerator			*scriptEnum = nil;
	OOScript				*theScript = nil;
	
	for (scriptEnum = [worldScripts objectEnumerator]; (theScript = [scriptEnum nextObject]); )
	{
		OOJSStartTimeLimiterWithTimeLimit(limit);
		[theScript callMethod:message inContext:context withArguments:argv count:argc result:NULL];
		OOJSStopTimeLimiter();
	}
}


- (void) setGalacticHyperspaceBehaviour:(OOGalacticHyperspaceBehaviour)inBehaviour
{
	if (GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN < inBehaviour && inBehaviour <= GALACTIC_HYPERSPACE_MAX)
	{
		galacticHyperspaceBehaviour = inBehaviour;
	}
}


- (OOGalacticHyperspaceBehaviour) galacticHyperspaceBehaviour
{
	return galacticHyperspaceBehaviour;
}


- (void) setGalacticHyperspaceFixedCoords:(NSPoint)point
{
	return [self setGalacticHyperspaceFixedCoordsX:OOClamp_0_max_f(round(point.x), 255.0f) y:OOClamp_0_max_f(round(point.y), 255.0f)];
}


- (void) setGalacticHyperspaceFixedCoordsX:(unsigned char)x y:(unsigned char)y
{
	galacticHyperspaceFixedCoords.x = x;
	galacticHyperspaceFixedCoords.y = y;
}


- (NSPoint) galacticHyperspaceFixedCoords
{
	return galacticHyperspaceFixedCoords;
}


- (OOLongRangeChartMode) longRangeChartMode
{
	return longRangeChartMode;
}


- (void) setLongRangeChartMode:(OOLongRangeChartMode) mode
{
	longRangeChartMode = mode;
}


- (BOOL) scoopOverride
{
	return scoopOverride;
}


- (void) setScoopOverride:(BOOL)newValue
{
	scoopOverride = !!newValue;
	[self setScoopsActive];
}


#if MASS_DEPENDENT_FUEL_PRICES
- (GLfloat) fuelChargeRate
{
	GLfloat		rate = 1.0; // Standard charge rate.
	
	rate = [super fuelChargeRate];
	
	// Experimental: the state of repair affects the fuel charge rate - more fuel needed for jumps, etc... 
	if (EXPECT(ship_trade_in_factor <= 90 && ship_trade_in_factor >= 75))
	{
		rate *= 2.0 - (ship_trade_in_factor / 100); // between 1.1x and 1.25x
		//OOLog(@"fuelPrices", @"\"%@\" - repair status: %d%%, adjusted rate to:%.2f)", [self shipDataKey], ship_trade_in_factor, rate);
	}

	return rate;
}
#endif


- (void) setDockTarget:(ShipEntity *)entity
{
if ([entity isStation]) _dockTarget = [entity universalID];
else _dockTarget = NO_TARGET;
	//_dockTarget = [entity isStation] ? [entity universalID]: NO_TARGET;
}


- (NSString *) commanderName
{
	return _commanderName;
}


- (NSString *) lastsaveName
{
	return _lastsaveName;
}


- (void) setCommanderName:(NSString *)value
{
	NSParameterAssert(value != nil);
	[_commanderName autorelease];
	_commanderName = [value copy];
}


- (void) setLastsaveName:(NSString *)value
{
	NSParameterAssert(value != nil);
	[_lastsaveName autorelease];
	_lastsaveName = [value copy];
}


- (BOOL) isDocked
{
	BOOL isDockedStatus = NO;
	
	switch ([self status])
	{
		case STATUS_DOCKED:
		case STATUS_DOCKING:
        case STATUS_START_GAME:
            isDockedStatus = YES;
            break;   
			// special case - can be either docked or not, so avoid safety check below
		case STATUS_RESTART_GAME:
			return NO;
		case STATUS_EFFECT:
		case STATUS_ACTIVE:
		case STATUS_COCKPIT_DISPLAY:
		case STATUS_TEST:
		case STATUS_INACTIVE:
		case STATUS_DEAD:
		case STATUS_IN_FLIGHT:
		case STATUS_AUTOPILOT_ENGAGED:
		case STATUS_LAUNCHING:
		case STATUS_WITCHSPACE_COUNTDOWN:
		case STATUS_ENTERING_WITCHSPACE:
		case STATUS_EXITING_WITCHSPACE:
		case STATUS_ESCAPE_SEQUENCE:
		case STATUS_IN_HOLD:
		case STATUS_BEING_SCOOPED:
		case STATUS_HANDLING_ERROR:
            break;
		//no default, so that we get notified by the compiler if something is missing
	}
	
#ifndef NDEBUG
	// Sanity check
	if (isDockedStatus)
	{
		if ([self dockedStation] == nil)
		{
			//there are a number of possible current statuses, not just STATUS_DOCKED
			OOLogERR(kOOLogInconsistentState, @"status is %@, but dockedStation is nil; treating as not docked. %@", OOStringFromEntityStatus([self status]), @"This is an internal error, please report it.");
			[self setStatus:STATUS_IN_FLIGHT];
			isDockedStatus = NO;
		}
	}
	else
	{
		if ([self dockedStation] != nil && [self status] != STATUS_LAUNCHING)
		{
			OOLogERR(kOOLogInconsistentState, @"status is %@, but dockedStation is not nil; treating as docked. %@", OOStringFromEntityStatus([self status]), @"This is an internal error, please report it.");
			[self setStatus:STATUS_DOCKED];
			isDockedStatus = YES;
		}
	}
#endif
	
	return isDockedStatus;
}


- (BOOL)clearedToDock
{
	return dockingClearanceStatus > DOCKING_CLEARANCE_STATUS_REQUESTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED;
}


- (void)setDockingClearanceStatus:(OODockingClearanceStatus)newValue
{
	dockingClearanceStatus = newValue;
	if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NONE)
	{
		targetDockStation = nil;
	}
	else if (dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_REQUESTED || dockingClearanceStatus == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED)
	{
		if ([[self primaryTarget] isStation])
		{
			targetDockStation = [self primaryTarget];
		}
		else
		{
			OOLog(@"player.badDockingTarget", @"Attempt to dock at %@.", [self primaryTarget]);
			targetDockStation = nil;
			dockingClearanceStatus = DOCKING_CLEARANCE_STATUS_NONE;
		}
	}
}

- (OODockingClearanceStatus)getDockingClearanceStatus
{
	return dockingClearanceStatus;
}


- (void)penaltyForUnauthorizedDocking
{
	OOCreditsQuantity	amountToPay = 0;
	OOCreditsQuantity	calculatedFine = credits * 0.05;
	OOCreditsQuantity	maximumFine = 50000ULL;
	
	if ([self clearedToDock])
		return;
		
	amountToPay = MIN(maximumFine, calculatedFine);
	credits -= amountToPay;
	[self addMessageToReport:[NSString stringWithFormat:DESC(@"station-docking-clearance-fined-@-cr"), OOCredits(amountToPay)]];
}


//
// Wormhole Scanner support functions
//
- (void)addScannedWormhole:(WormholeEntity*)whole
{
	assert(scannedWormholes != nil);
	assert(whole != nil);
	
	// Only add if we don't have it already!
	NSEnumerator *wormholes = [scannedWormholes objectEnumerator];
	WormholeEntity *wh = nil;
	while ((wh = [wormholes nextObject]))
	{
		if (wh == whole)  return;
	}
	[whole setScannedAt:[self clockTimeAdjusted]];
	[scannedWormholes addObject:whole];
}

// Checks through our array of wormholes for any which have expired
// If it is in the current system, spawn ships
// Else remove it
- (void)updateWormholes
{
	assert(scannedWormholes != nil);
	
	if ([scannedWormholes count] == 0)
		return;

	double now = [self clockTimeAdjusted];

	NSMutableArray * savedWormholes = [[NSMutableArray alloc] initWithCapacity:[scannedWormholes count]];
	NSEnumerator * wormholes = [scannedWormholes objectEnumerator];
	WormholeEntity *wh;

	while ((wh = (WormholeEntity*)[wormholes nextObject]))
	{
		// TODO: Start drawing wormhole exit a few seconds before the first
		//       ship is disgorged.
		if ([wh arrivalTime] > now)
		{
			[savedWormholes addObject:wh];
		}
		else if (NSEqualPoints(galaxy_coordinates, [wh destinationCoordinates]))
		{
			[wh disgorgeShips];
			if ([[wh shipsInTransit] count] > 0)
			{
				[savedWormholes addObject:wh];
			}
		}
		// Else wormhole has expired in another system, let it expire
	}

	[scannedWormholes release];
	scannedWormholes = savedWormholes;
}


- (NSArray *) scannedWormholes
{
	return [NSArray arrayWithArray:scannedWormholes];
}


- (void) initialiseMissionDestinations:(NSDictionary *)destinations andLegacy:(NSArray *)legacy
{
	NSEnumerator				*keyEnum = nil;
	NSString					*key = nil;
	id							value = nil;

	/* same need to make inner objects mutable as in localPlanetInfoOverrides */

	[missionDestinations release];
	missionDestinations = [[NSMutableDictionary alloc] init];

	for (keyEnum = [destinations keyEnumerator]; (key = [keyEnum nextObject]); )
	{
		value = [destinations objectForKey:key];
		if (value != nil)
		{
			if ([value isKindOfClass:[NSDictionary class]])
			{
				value = [value mutableCopy];
				[missionDestinations setObject:value forKey:key];
				[value release];
			}
		}
	}
	
	if (legacy != nil)
	{
		OOSystemID dest;
		NSNumber *legacyMarker;
		for (keyEnum = [legacy objectEnumerator]; (legacyMarker = [keyEnum nextObject]); )
		{
			dest = [legacyMarker intValue];
			[self addMissionDestinationMarker:[self defaultMarker:dest]];
		}
	}

}


- (NSString *)markerKey:(NSDictionary *)marker
{
	return [NSString stringWithFormat:@"%d-%@",[marker oo_intForKey:@"system"], [marker oo_stringForKey:@"name"]];
}


- (void) addMissionDestinationMarker:(NSDictionary *)marker
{
	NSDictionary *validated = [self validatedMarker:marker];
	if (validated == nil) 
	{
		return;
	}
	
	[missionDestinations setObject:validated forKey:[self markerKey:validated]];
}


- (BOOL) removeMissionDestinationMarker:(NSDictionary *)marker
{
	NSDictionary *validated = [self validatedMarker:marker];
	if (validated == nil) 
	{
		return NO;
	}
	BOOL result = NO;
	if ([missionDestinations objectForKey:[self markerKey:validated]] != nil) {
		result = YES;
	}
	[missionDestinations removeObjectForKey:[self markerKey:validated]];
	return result;
}


- (NSMutableDictionary*) getMissionDestinations
{
	return missionDestinations;
}


- (void) setLastShot:(OOLaserShotEntity *)shot
{
	lastShot = shot; 
/* No need to retain it, since the universe will be for as long as we
 * reference it. This is needed because the laser shot update routine
 * is used to correct its position relative to the ship, but isn't
 * called by Universe on the frame the shot is added (because updates
 * never are)
 */
}

#ifndef NDEBUG
- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	
	[super dumpSelfState];
	
	OOLog(@"dumpState.playerEntity", @"Script time: %g", script_time);
	OOLog(@"dumpState.playerEntity", @"Script time check: %g", script_time_check);
	OOLog(@"dumpState.playerEntity", @"Script time interval: %g", script_time_interval);
	OOLog(@"dumpState.playerEntity", @"Roll/pitch/yaw delta: %g, %g, %g", roll_delta, pitch_delta, yaw_delta);
	OOLog(@"dumpState.playerEntity", @"Shield: %g fore, %g aft", forward_shield, aft_shield);
	OOLog(@"dumpState.playerEntity", @"Alert level: %u, flags: %#x", alertFlags, alertCondition);
	OOLog(@"dumpState.playerEntity", @"Missile status: %i", missile_status);
	OOLog(@"dumpState.playerEntity", @"Energy unit: %@", EnergyUnitTypeToString([self installedEnergyUnitType]));
	OOLog(@"dumpState.playerEntity", @"Fuel leak rate: %g", fuel_leak_rate);
	OOLog(@"dumpState.playerEntity", @"Trumble count: %lu", trumbleCount);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(found_equipment);
	ADD_FLAG_IF_SET(pollControls);
	ADD_FLAG_IF_SET(suppressTargetLost);
	ADD_FLAG_IF_SET(scoopsActive);
	ADD_FLAG_IF_SET(game_over);
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
	ADD_FLAG_IF_SET(keyboardRollOverride);   // Handle keyboard roll...
	ADD_FLAG_IF_SET(keyboardPitchOverride);  // ...and pitch override separately - (fix for BUG #17490)
	ADD_FLAG_IF_SET(keyboardYawOverride);
	ADD_FLAG_IF_SET(waitingForStickCallback);
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : (NSString *)@"none";
	OOLog(@"dumpState.playerEntity", @"Flags: %@", flagsString);
}


/*	This method exists purely to suppress Clang static analyzer warnings that
	these ivars are unused (but may be used by categories, which they are).
	FIXME: there must be a feature macro we can use to avoid actually building
	this into the app, but I can't find it in docs.
	
	Mind you, we could suppress some of this by using civilized accessors.
*/
- (BOOL) suppressClangStuff
{
	return missionChoice &&
	commanderNameString &&
	cdrDetailArray &&
	currentPage &&
	key_roll_left &&
	key_roll_right &&
	key_pitch_forward &&
	key_pitch_back &&
	key_yaw_left &&
	key_yaw_right &&
	key_view_forward &&
	key_view_aft &&
	key_view_port &&
	key_view_starboard &&
	key_gui_screen_status &&
	key_gui_chart_screens &&
	key_gui_system_data &&
	key_gui_market &&
	key_gui_arrow_left &&
	key_gui_arrow_right &&
	key_gui_arrow_up &&
	key_gui_arrow_down &&
	key_increase_speed &&
	key_decrease_speed &&
	key_inject_fuel &&
	key_fire_lasers &&
	key_launch_missile &&
	key_next_missile &&
	key_ecm &&
	key_prime_equipment &&
	key_activate_equipment &&
	key_mode_equipment &&
	key_fastactivate_equipment_a &&
	key_fastactivate_equipment_b &&
	key_target_missile &&
	key_untarget_missile &&
	key_target_incoming_missile &&
	key_ident_system &&
	key_scanner_zoom &&
	key_scanner_unzoom &&
	key_launch_escapepod &&
	key_galactic_hyperspace &&
	key_hyperspace &&
	key_jumpdrive &&
	key_dump_cargo &&
	key_rotate_cargo &&
	key_autopilot &&
	key_autodock &&
	key_snapshot &&
	key_docking_music &&
	key_advanced_nav_array &&
	key_map_home &&
	key_map_info &&
	key_pausebutton &&
	key_show_fps &&
	key_mouse_control &&
	key_hud_toggle &&
	key_comms_log &&
	key_prev_compass_mode &&
	key_next_compass_mode &&
	key_chart_highlight &&
	key_next_target &&
	key_previous_target &&
	key_custom_view &&
	key_cycle_mfd &&
	key_switch_mfd &&
	key_docking_clearance_request &&
	key_dump_target_state &&
	key_weapons_online_toggle &&
	_sysInfoLight.x &&
	selFunctionIdx &&
	stickFunctions &&
	showingLongRangeChart &&
	_missionAllowInterrupt &&
	_missionScreenID &&
	_missionTitle &&
	_missionTextEntry;
}
#endif

@end
