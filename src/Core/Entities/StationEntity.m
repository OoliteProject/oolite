/*

	StationEntity.m

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

#import "StationEntity.h"
#import "DockEntity.h"
#import "ShipEntityAI.h"
#import "OOCollectionExtractors.h"
#import "OOStringParsing.h"
#import "OOFilteringEnumerator.h"

#import "Universe.h"
#import "GameController.h"
#import "HeadUpDisplay.h"
#import "OOConstToString.h"

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
#import "OOWeakSet.h"


@interface StationEntity (OOPrivate)

- (BOOL) fitsInDock:(ShipEntity *)ship;
- (void) pullInShipIfPermitted:(ShipEntity *)ship;
- (void) addShipToStationCount:(ShipEntity *)ship;

- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority;
- (unsigned) countOfShipsInLaunchQueueWithPrimaryRole:(NSString *)role;

- (NSDictionary *) holdPositionInstructionForShip:(ShipEntity *)ship;

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


- (Vector) virtualPortDimensions
{
	return port_dimensions;
}


- (DockEntity*) playerReservedDock
{
	return player_reserved_dock;
}


- (HPVector) beaconPosition
{
	double buoy_distance = 10000.0;				// distance from station entrance
	Vector v_f = vector_forward_from_quaternion([self orientation]);
	HPVector result = HPvector_add([self position], vectorToHPVector(vector_multiply_scalar(v_f, buoy_distance)));
	
	return result;
}


- (float) equipmentPriceFactor
{
	return equipmentPriceFactor;
}


- (NSMutableArray *) localMarket
{
	if (!localMarket)
	{
		[self initialiseLocalMarketWithRandomFactor:[PLAYER random_factor]];
	}
	return localMarket;
}


- (void) setLocalMarket:(NSArray *) some_market
{
	if (localMarket)
		[localMarket release];
	localMarket = [[NSMutableArray alloc] initWithArray:some_market];
}


- (NSDictionary *) localMarketForScripting
{
	if (!localMarket)
	{
		[self initialiseLocalMarketWithRandomFactor:[PLAYER random_factor]];
	}

	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:17];
	OOCommodityType cType;
	NSString *commodityKey = nil;

	NSArray *commodityKeys = [[NSArray alloc] initWithObjects:@"displayName",@"quantity",@"price",@"marketBasePrice",@"marketEcoAdjustPrice",@"marketEcoAdjustQuantity",@"marketBaseQuantity",@"marketMaskPrice",@"marketMaskQuantity",@"quantityUnit",nil];
	// displayName not numeric, price and quantity already are
	// have I missed an obvious "slice of array" function here? - CIM
	NSArray *numericKeys = [[NSArray alloc] initWithObjects:@"marketBasePrice",@"marketEcoAdjustPrice",@"marketEcoAdjustQuantity",@"marketBaseQuantity",@"marketMaskPrice",@"marketMaskQuantity",@"quantityUnit",nil]; 
	
	for (cType=COMMODITY_FOOD; cType <= COMMODITY_ALIEN_ITEMS; cType++)
	{
		NSArray *marketLine = [localMarket objectAtIndex:cType];
		NSMutableDictionary *commodity = [NSMutableDictionary dictionaryWithObjects:marketLine forKeys:commodityKeys];
		NSEnumerator	*keyEnum = [numericKeys objectEnumerator];
		while ((commodityKey = [keyEnum nextObject]))
		{
			// convert value to int from string
			[commodity setObject:[NSNumber numberWithInt:[commodity oo_intForKey:commodityKey]] forKey:commodityKey];
		}
		if (self == [UNIVERSE station])
		{
			[commodity setObject:[NSNumber numberWithInt:[UNIVERSE legalStatusOfCommodity:[commodity oo_stringForKey:@"displayName"]]] forKey:@"legalPenalty"];
		} 
		else
		{
			[commodity setObject:[NSNumber numberWithInt:0] forKey:@"legalPenalty"];
		}

		[result setObject:commodity forKey:CommodityTypeToString(cType)];
	}

	[commodityKeys release];
	[numericKeys release];

  return [NSDictionary dictionaryWithDictionary:result];
}


- (void) setPrice:(NSUInteger)price forCommodity:(OOCommodityType)commodity
{
	if (!localMarket)
	{
		[self initialiseLocalMarketWithRandomFactor:[PLAYER random_factor]];
	}
	
	NSMutableArray *commodityData = [[NSMutableArray alloc] initWithArray:[localMarket objectAtIndex:commodity]];
	[commodityData replaceObjectAtIndex:MARKET_PRICE withObject:[NSNumber numberWithUnsignedInteger:price]];
	[localMarket replaceObjectAtIndex:commodity withObject:[NSArray arrayWithArray:commodityData]];
	[commodityData release];
}


- (void) setQuantity:(NSUInteger)quantity forCommodity:(OOCommodityType)commodity
{
	if (!localMarket)
	{
		[self initialiseLocalMarketWithRandomFactor:[PLAYER random_factor]];
	}
	
	NSMutableArray *commodityData = [[NSMutableArray alloc] initWithArray:[localMarket objectAtIndex:commodity]];
	[commodityData replaceObjectAtIndex:MARKET_QUANTITY withObject:[NSNumber numberWithUnsignedInteger:quantity]];
	[localMarket replaceObjectAtIndex:commodity withObject:[NSArray arrayWithArray:commodityData]];
	[commodityData release];
}


/*- (NSMutableArray *) localPassengers
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
	} */


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


- (NSMutableDictionary *) localInterfaces
{
	return localInterfaces;
}


- (void) setInterfaceDefinition:(OOJSInterfaceDefinition *)definition forKey:(NSString *)key
{
	if (definition == nil)
	{
		[localInterfaces removeObjectForKey:key];
	}
	else
	{
		[localInterfaces setObject:definition forKey:key];
	}
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


- (unsigned) countOfDockedContractors
{
	return max_scavengers > scavengers_launched ? max_scavengers - scavengers_launched : 0;
}


- (unsigned) countOfDockedPolice
{
	return max_police > defenders_launched ? max_police - defenders_launched : 0;
}


- (unsigned) countOfDockedDefenders
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
		soa += [sub pruneAndCountShipsOnApproach];
	}

	if (soa == 0)
	{
		// if all docks have no ships on approach
		[shipAI message:@"DOCKING_COMPLETE"];
		[self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];	
	}
}


// only used by player - everything else ends up in a Dock's launch queue
- (void) launchShip:(ShipEntity *)ship
{
	NSEnumerator	*subEnum = nil;
	DockEntity		*sub = nil;
	
	// try to find an unused dock first
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsLaunching] && [sub countOfShipsInLaunchQueue] == 0) 
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

	// ship has no launch docks specified; just use the last one
	if (sub != nil)
	{
		[sub launchShip:ship];
		return;
	}
	// guaranteed to always be a dock as virtual dock will suffice
}


// Exposed to AI
- (void) abortAllDockings
{
	NSEnumerator	*subEnum = nil;
	DockEntity		*sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub abortAllDockings];
	}
	
	[_shipsOnHold makeObjectsPerformSelector:@selector(sendAIMessage:) withObject:@"DOCKING_ABORTED"];
	NSEnumerator *holdEnum = nil;
	ShipEntity *hold = nil;
	for (holdEnum = [_shipsOnHold objectEnumerator]; (hold = [holdEnum nextObject]); )
	{
		[hold doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
	}

	PlayerEntity *player = PLAYER;

	if ([player getTargetDockStation] == self && [player getDockingClearanceStatus] >= DOCKING_CLEARANCE_STATUS_REQUESTED)
	{
		// then docking clearance is requested but hasn't been cancelled
		// yet by a DockEntity
		[self sendExpandedMessage:@"[station-docking-clearance-abort-cancelled]" toShip:player];
		[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		[player doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
	}

	[_shipsOnHold removeAllObjects];
	
	[shipAI message:@"DOCKING_COMPLETE"];
	[self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];

}


- (void) autoDockShipsOnHold
{
	NSEnumerator	*onHoldEnum = [_shipsOnHold objectEnumerator];
	ShipEntity		*ship = nil;
	while ((ship = [onHoldEnum nextObject]))
	{
		[self pullInShipIfPermitted:ship];
	}
	
	[_shipsOnHold removeAllObjects];
}


- (void) autoDockShipsOnApproach
{
	NSEnumerator	*subEnum = nil;
	DockEntity		*sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub autoDockShipsOnApproach];
	}

	[self autoDockShipsOnHold];
	
	[shipAI message:@"DOCKING_COMPLETE"];
	[self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];

}


- (Vector) portUpVectorForShip:(ShipEntity*) ship
{
	NSEnumerator	*subEnum = nil;
	DockEntity		*sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub shipIsInDockingQueue:ship])
		{
			return [sub portUpVectorForShipsBoundingBox:[ship totalBoundingBox]];
		}
	}
	return kZeroVector;
}


NSDictionary *OOMakeDockingInstructions(StationEntity *station, HPVector coords, float speed, float range, NSString *ai_message, NSString *comms_message, BOOL match_rotation)
{
	NSMutableDictionary *acc = [NSMutableDictionary dictionaryWithCapacity:8];
	[acc oo_setHPVector:coords forKey:@"destination"];
	[acc oo_setFloat:speed forKey:@"speed"];
	[acc oo_setFloat:range forKey:@"range"];
	[acc setObject:[[station weakRetain] autorelease] forKey:@"station"];
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


// this method does initial traffic control, before passing the ship
// to an appropriate dock for docking coordinates and instructions.
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *) ship
{	
	if (ship == nil)  return nil;

	if ([ship isPlayer])
	{
		player_reserved_dock = nil; // clear any dock reservation for manual docking
	}

	if ([ship isPlayer] && [ship legalStatus] > 50)	// note: non-player fugitives dock as normal
	{
		// refuse docking to the fugitive player
		return OOMakeDockingInstructions(self, [ship position], 0, 100, @"DOCKING_REFUSED", @"[station-docking-refused-to-fugitive]", NO);
	}
	
	if	(magnitude2(velocity) > 1.0 ||
			 fabs(flightPitch) > 0.01 ||
			 fabs(flightYaw) > 0.01)
	{
		// no docking while station is moving, pitching or yawing
		return [self holdPositionInstructionForShip:ship];
	}
	PlayerEntity *player = PLAYER;
	BOOL player_is_ahead = (![ship isPlayer] && [player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED && (self == [player getTargetDockStation]));

	NSEnumerator	*subEnum = nil;
	DockEntity		*chosenDock = nil;
	NSString		*docking = nil;
	DockEntity		*sub = nil;
	NSUInteger		queue = 100;
	
	BOOL alldockstoosmall = YES;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub shipIsInDockingQueue:ship]) 
		{
			// if already claimed a docking queue, use that one
			chosenDock = sub;
			alldockstoosmall = NO;
			break;
		}
		if (player_is_ahead) {
			// can't allocate a new queue while player is manually docking
			continue;
		}
		if (sub != player_reserved_dock)
		{
			docking = [sub canAcceptShipForDocking:ship];
			if ([docking isEqualToString:@"DOCK_CLOSED"])
			{
				JSContext	*context = OOJSAcquireContext();
				jsval		rval = JSVAL_VOID;
				jsval		args[] = { OOJSValueFromNativeObject(context, sub),
													 OOJSValueFromNativeObject(context, ship) };
				JSBool tempreject = NO;

				BOOL OK = [[self script] callMethod:OOJSID("willOpenDockingPortFor") inContext:context withArguments:args count:2 result:&rval];
				if (OK)  OK = JS_ValueToBoolean(context, rval, &tempreject);
				if (!OK)  tempreject = NO; // default to permreject
				if (tempreject)
				{
					docking = @"TRY_AGAIN_LATER";
				}
				else
				{
					docking = @"TOO_BIG_TO_DOCK";
				}

				OOJSRelinquishContext(context);
			}

			if ([docking isEqualToString:@"DOCKING_POSSIBLE"] && [sub countOfShipsInDockingQueue] < queue) {
				// try to select the dock with the fewest ships already enqueued
				chosenDock = sub;
				queue = [sub countOfShipsInDockingQueue];
				alldockstoosmall = NO;
			}
			else if (![docking isEqualToString:@"TOO_BIG_TO_DOCK"])
			{
				alldockstoosmall = NO;
			}
		}
		else
		{
			alldockstoosmall = NO;
		}
	}	
	if (chosenDock == nil)
	{
		if (player_is_ahead || ([docking isEqualToString:@"TOO_BIG_TO_DOCK"] && !alldockstoosmall))
		{
			// either player is manually docking and we can't allocate new docks,
			// or the last dock was too small, and there may be an acceptable one
			// not tested yet or returning TRY_AGAIN_LATER
			docking = @"TRY_AGAIN_LATER";
		}
		// no docks accept this ship (or the player is blocking them)
		return OOMakeDockingInstructions(self, [ship position], 0, 100, docking, nil, NO);
	}


	// rolling is okay for some
	if	(fabs(flightRoll) > 0.01 && [chosenDock isOffCentre])
	{
		return [self holdPositionInstructionForShip:ship];
	}
	
	// we made it through holding!
	[_shipsOnHold removeObject:ship];
	
	[shipAI reactToMessage:@"DOCKING_REQUESTED" context:@"requestDockingCoordinates"];	// react to the request	
	[self doScriptEvent:OOJSID("stationReceivedDockingRequest") withArgument:ship];

	return [chosenDock dockingInstructionsForShip:ship];
}


- (NSDictionary *)holdPositionInstructionForShip:(ShipEntity *)ship
{
	if (![_shipsOnHold containsObject:ship])
	{
		[self sendExpandedMessage:@"[station-acknowledges-hold-position]" toShip:ship];
		[_shipsOnHold addObject:ship];
	}
	
	return OOMakeDockingInstructions(self, [ship position], 0, 100, @"HOLD_POSITION", nil, NO);
}


- (void) abortDockingForShip:(ShipEntity *) ship
{
	[ship sendAIMessage:@"DOCKING_ABORTED"];
	[ship doScriptEvent:OOJSID("stationWithdrewDockingClearance")];
	
	[_shipsOnHold removeObject:ship];
	
	NSEnumerator	*subEnum = nil;
	DockEntity		*sub = nil;
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
		_shipsOnHold = [[OOWeakSet alloc] init];
		hasBreakPattern = YES;
		localInterfaces = [[NSMutableDictionary alloc] init];
	}
	return self;
	
	OOJS_PROFILE_EXIT
		}


- (void) dealloc
{
	DESTROY(_shipsOnHold);
	DESTROY(localMarket);
	DESTROY(allegiance);
//	DESTROY(localPassengers);
//	DESTROY(localContracts);
	DESTROY(localShipyard);
	DESTROY(localInterfaces);

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
	equipmentPriceFactor = fmax(equipmentPriceFactor, 0.5f);
	hasNPCTraffic = [dict oo_fuzzyBooleanForKey:@"has_npc_traffic" defaultValue:(maxFlightSpeed == 0)]; // carriers default to NO
	hasPatrolShips = [dict oo_fuzzyBooleanForKey:@"has_patrol_ships" defaultValue:NO];
	suppress_arrival_reports = [dict oo_boolForKey:@"suppress_arrival_reports" defaultValue:NO];
	[self setAllegiance:[dict oo_stringForKey:@"allegiance"]];
	
	// Non main stations may have requiresDockingClearance set to yes as a result of the code below,
	// but this variable should be irrelevant for them, as they do not make use of it anyway.
	requiresDockingClearance = [dict oo_boolForKey:@"requires_docking_clearance" defaultValue:[UNIVERSE dockingClearanceProtocolActive]];
	
	allowsFastDocking = [dict oo_boolForKey:@"allows_fast_docking" defaultValue:NO];
	
	allowsAutoDocking = [dict oo_boolForKey:@"allows_auto_docking" defaultValue:YES];
	
	allowsSaving = [UNIVERSE deterministicPopulation];

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


// used to set up a virtual dock if necessary
- (BOOL) setUpSubEntities
{
	if (![super setUpSubEntities])
	{
		return NO;
	}

	NSEnumerator	*subEnum = nil;

#ifndef NDEBUG
	ShipEntity *subEntity = nil;
	for (subEnum = [self shipSubEntityEnumerator]; (subEntity = [subEnum nextObject]); )
	{
		if ([subEntity isStation])
		{
			OOLog(@"setup.ship.badType.subentities",@"Subentity %@ (%@) of station %@ is itself a StationEntity. This is an internal error - please report it. ",subEntity,[subEntity shipDataKey],[self displayName]);
		}
	}
#endif

	// and now check for docks
	DockEntity		*sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		return YES;
	}

	OOLog(@"ship.setup.docks",@"No docks set up for %@, making virtual dock",self);

	// no real docks, make a virtual one
	NSMutableDictionary *virtualDockDict = [NSMutableDictionary dictionaryWithCapacity:10];
	[virtualDockDict setObject:@"standard" forKey:@"type"];
	[virtualDockDict setObject:@"oolite-dock-virtual" forKey:@"subentity_key"];
	[virtualDockDict oo_setVector:make_vector(0,0,port_radius) forKey:@"position"];
	[virtualDockDict oo_setQuaternion:kIdentityQuaternion forKey:@"orientation"];
	[virtualDockDict oo_setBool:YES forKey:@"is_dock"];
	[virtualDockDict setObject:@"the docking bay" forKey:@"dock_label"];
	[virtualDockDict oo_setBool:YES forKey:@"allow_docking"];
	[virtualDockDict oo_setBool:NO forKey:@"disallowed_docking_collides"];
	[virtualDockDict oo_setBool:YES forKey:@"allow_launching"];
	[virtualDockDict oo_setBool:YES forKey:@"_is_virtual_dock"];

	if (![self setUpOneStandardSubentity:virtualDockDict asTurret:NO])
	{
		return NO;
	}
	return YES;
}




- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship
{
	if (![ship isShip])  return NO;
	if ([ship isPlayer] && [ship status] == STATUS_DEAD)  return NO;

	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub shipIsInDockingCorridor:ship])
		{
			return YES;
		}
	}
	return NO;
}

	


- (void) pullInShipIfPermitted:(ShipEntity *)ship
{
	[ship enterDock:self]; // dock performs permitted checks
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
				[self sendExpandedMessage:@"[station-docking-clearance-about-to-expire]" toShip:player];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_TIMING_OUT];
			}
			else if (last_launch_time < unitime)
			{
				[self sendExpandedMessage:@"[station-docking-clearance-expired]" toShip:player];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];	// Docking clearance for player has expired.
				if ([self currentlyInDockingQueues] == 0) 
				{
					[[self getAI] message:@"DOCKING_COMPLETE"];
					[self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
				}
				player_reserved_dock = nil;
			}
		}

		else if ([player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_NOT_REQUIRED)
		{
			if (last_launch_time < unitime)
			{
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
				if ([self currentlyInDockingQueues] == 0) 
				{
					[[self getAI] message:@"DOCKING_COMPLETE"];
					[self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
				}
			}
		}

		else if ([player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED &&
				[self hasClearDock])
		{
			DockEntity *dock = [self selectDockForDocking];
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

	/* JSAI: JS-based AIs handle their own traffic either alone or 
	 * in conjunction with the system repopulator */
	if (![self hasNewAI])
	{
		// begin launch of shuttles, traders, patrols
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
}


- (void) clear
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		[sub clear];
	}
	
	[_shipsOnHold removeAllObjects];
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
// not used for NPCs
- (BOOL) hasClearDock
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsDocking] && [sub countOfShipsInLaunchQueue] == 0 && [sub countOfShipsInDockingQueue] == 0)
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

// only used to pick a dock for the player
- (DockEntity *) selectDockForDocking
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		if ([sub allowsDocking] && [sub countOfShipsInLaunchQueue] == 0 && [sub countOfShipsInDockingQueue] == 0)
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
				if ([sub countOfShipsInDockingQueue] == 0)
				{
					if ([sub allowsLaunching] && [sub countOfShipsInLaunchQueue] <= threshold)
					{
						if ([sub allowsLaunchingOf:ship])
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
				if ([sub allowsLaunching] && [sub countOfShipsInDockingQueue] <= threshold)
				{
					if ([sub allowsLaunchingOf:ship])
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


- (unsigned) countOfShipsInLaunchQueueWithPrimaryRole:(NSString *)role
{
	unsigned result = 0;
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		result += [sub countOfShipsInLaunchQueueWithPrimaryRole:role];
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
		if ([sub allowsLaunchingOf:ship])
		{
			return YES;
		}
	}

	OOLog(@"station.launchShip.failed", @"Cancelled launch for a %@ with role %@, as it is too large for the docking port of the %@.",
			  [ship displayName], [ship primaryRole], self);
	return NO;
}	

	
- (void) noteDockedShip:(ShipEntity *) ship
{
	if (ship == nil)  return;	
	
	PlayerEntity *player = PLAYER;
	// set last launch time to avoid clashes with outgoing ships
	if ([player getDockingClearanceStatus] != DOCKING_CLEARANCE_STATUS_GRANTED)
	{
		// avoid interfering with docking clearance on another bay
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
		{
			// then say why
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
	/*
		There used to be a [self abortAllDockings] here. Removed as there
		doesn't appear to be a good reason for it and it interferes with
		docking clearance.
		-- Micha 2010-06-10
	       Reformatted, Ahruman 2012-08-26
	*/
	return [super collideWithShip:other];
}


- (BOOL) hasHostileTarget
{
	return [super hasHostileTarget] || ([self primaryTarget] != nil && ((alertLevel == STATION_ALERT_LEVEL_YELLOW) || (alertLevel == STATION_ALERT_LEVEL_RED)));
}

- (void) takeEnergyDamage:(double)amount from:(Entity *)ent becauseOf:(Entity *)other
{
	// stations must ignore friendly fire, otherwise the defenders' AI gets stuck.
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

		// JSAIs might ignore friendly fire from conventional weapons
		if ([self hasNewAI] || isEnergyMine)
		{
			unsigned b=isEnergyMine ? 96 : 64;
			if ([(ShipEntity*)other bounty] >= b)	//already a hardened criminal?
			{
				b *= 1.5; //bigger bounty!
			}
			[(ShipEntity*)other markAsOffender:b withReason:kOOLegalStatusReasonAttackedMainStation];
			[self setPrimaryAggressor:other];
			[self setFoundTarget:other];
			[self launchPolice];
		}

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


- (NSString *) allegiance
{
	return allegiance;
}


- (void) setAllegiance:(NSString *)newAllegiance
{
	[allegiance release];
	allegiance = [newAllegiance copy];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a ship with role %@, as the %@ has no launch docks.",
			  role, [self displayName]);
		return nil;
	}

	BOOL			trader = [role isEqualToString:@"trader"];
	BOOL			sunskimmer = ([role isEqualToString:@"sunskim-trader"]);
	ShipEntity		*ship = nil;

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
				[ship setFuel:(Ranrot()&31)];
				[UNIVERSE makeSunSkimmer:ship andSetAI:YES];
			}
			else
			{
// JSAI: not needed - oolite-traderAI.js handles exiting if full fuel and plentiful cargo
//				[ship switchAITo:@"exitingTraderAI.plist"];
				if([ship fuel] == 0) [ship setFuel:70];
//				if ([ship hasRole:@"sunskim-trader"]) [UNIVERSE makeSunSkimmer:ship andSetAI:NO];
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
			[ship setOwner:self]; // makes escorts get added to station launch queue
			[ship setUpEscorts];
			[ship setOwner:ship];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a police ship, as the %@ has no launch docks.",
			  [self displayName]);
		return [NSArray array];
	}

	OOUniversalID	police_target = [[self primaryTarget] universalID];
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
		/* this is more likely to give interceptors than the
		 * equivalent populator function: save them for defense
		 * ships */
		if ((Ranrot() & 3) + 9 < techlevel)
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
			[police_ship switchAITo:@"oolite-defenseShipAI.js"];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a defense ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}

	OOUniversalID	defense_target = [[self primaryTarget] universalID];
	ShipEntity	*defense_ship = nil;
	NSString	*defense_ship_key = nil,
				*defense_ship_role = nil,
				*default_defense_ship_role = nil;
	NSString	*defense_ship_ai = @"oolite-defenseShipAI.js";
	
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
		if ([defense_ship isPolice])
		{
			[defense_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"police"
				 andOriginalSystem: [UNIVERSE systemSeed]]]];
		}
		else
		{
			[defense_ship setCrew:[NSArray arrayWithObject:
				[OOCharacter randomCharacterWithRole: @"hunter"
				 andOriginalSystem: [UNIVERSE systemSeed]]]];
		}
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a scavenger ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}

	ShipEntity  *scavenger_ship;
	
	unsigned scavs = [UNIVERSE countShipsWithPrimaryRole:@"scavenger" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countOfShipsInLaunchQueueWithPrimaryRole:@"scavenger"];
	
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
				[OOCharacter randomCharacterWithRole: @"miner"
				andOriginalSystem: [UNIVERSE systemSeed]]]];
				
		scavengers_launched++;
		[scavenger_ship setScanClass: CLASS_NEUTRAL];
		if ([scavenger_ship heatInsulation] < [self heatInsulation])
			[scavenger_ship setHeatInsulation:[self heatInsulation]];
		[scavenger_ship setGroup:[self stationGroup]];	// who's your Daddy -- FIXME: should we have a separate group for non-escort auxiliaires?
		[scavenger_ship switchAITo:@"oolite-scavengerAI.js"];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a miner ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}

	ShipEntity  *miner_ship;
	
	int		n_miners = [UNIVERSE countShipsWithPrimaryRole:@"miner" inRange:SCANNER_MAX_RANGE ofEntity:self] + [self countOfShipsInLaunchQueueWithPrimaryRole:@"miner"];
	
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
		[miner_ship switchAITo:@"oolite-scavengerAI.js"];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a pirate ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
	}
	//Pirate ships are launched from the same pool as defence ships.
	OOUniversalID	defense_target = [[self primaryTarget] universalID];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a shuttle ship, as the %@ has no launch docks.",
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
		[shuttle_ship switchAITo:@"oolite-shuttleAI.js"];
		[self addShipToLaunchQueue:shuttle_ship withPriority:NO];
		
		[shuttle_ship autorelease];
	}
	return shuttle_ship;
}


// Exposed to AI
- (ShipEntity *) launchEscort
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for an escort ship, as the %@ has no launch docks.",
			  [self displayName]);
		return nil;
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
		[escort_ship switchAITo:@"oolite-escortAI.js"];
		[self addShipToLaunchQueue:escort_ship withPriority:NO];
		
	}
	[escort_ship release];
	return escort_ship;
}


// Exposed to AI
- (ShipEntity *) launchPatrol
{
	if (![self hasLaunchDock])
	{
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a patrol ship, as the %@ has no launch docks.",
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
			[patrol_ship setPrimaryRole:@"police-station-patrol"];
			[patrol_ship setBounty:0 withReason:kOOLegalStatusReasonSetup];
			[patrol_ship setGroup:[self stationGroup]];	// who's your Daddy
			[patrol_ship switchAITo:@"oolite-policeAI.js"];
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
		OOLog(@"station.launchShip.impossible", @"Cancelled launch for a ship with role %@, as the %@ has no launch docks.",
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
	if ((player)&&([player status] == STATUS_DOCKED || [player status] == STATUS_DOCKING)&&([player dockedStation] == self))
	{
		// undock the player!
		[player leaveDock:self];
		[UNIVERSE setViewDirection:VIEW_FORWARD];
		[[UNIVERSE gameController] setMouseInteractionModeForFlight];
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
			[self sendExpandedMessage:@"[station-docking-clearance-not-required]" toShip:other];
		if ([other isPlayer])
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NOT_REQUIRED];
		[shipAI reactToMessage:@"DOCKING_REQUESTED" context:nil];	// react to the request	
		[self doScriptEvent:OOJSID("stationReceivedDockingRequest") withArgument:other];

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
				[self sendExpandedMessage:@"[station-docking-clearance-cancelled]" toShip:other];
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
				result = @"DOCKING_CLEARANCE_CANCELLED";
				player_reserved_dock = nil;
				if ([self currentlyInDockingQueues] == 0)
				{
					[shipAI message:@"DOCKING_COMPLETE"];
					[self doScriptEvent:OOJSID("stationDockingQueuesAreEmpty")];
				}
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
		[self sendExpandedMessage:@"[station-docking-clearance-H-clearance-refused]" toShip:other];
		if ([other isPlayer])
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		result = @"DOCKING_CLEARANCE_DENIED_SHIP_FUGITIVE";
	}
	
	if (result == nil && [other hasHostileTarget]) // do not grant docking clearance to hostile ships.
	{
		[self sendExpandedMessage:@"[station-docking-clearance-denied]" toShip:other];
		if ([other isPlayer])
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
		result = @"DOCKING_CLEARANCE_DENIED_SHIP_HOSTILE";
	}

	if (![self hasClearDock]) // skip check if at least one dock clear
	{
		// Put ship in queue if we've got incoming or outgoing traffic or
		// if the player is waiting for manual clearance and we are not
		// the player
		if (result == nil && (([self currentlyInDockingQueues] && last_launch_time < timeNow) || (![other isPlayer] && [player getDockingClearanceStatus] == DOCKING_CLEARANCE_STATUS_REQUESTED)))
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
		if (result == nil)
		{
			// if this happens, the station has no docks which allow
			// docking, so deny clearance
			if ([other isPlayer])
			{
				[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_NONE];
			}
			result = @"DOCKING_CLEARANCE_DENIED_NO_DOCKS";
			// but can check to see if we'll open some for later.
			NSEnumerator	*subEnum = nil;
			DockEntity* sub = nil;
			BOOL openLater = NO;
			for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
			{
				NSString *docking = [sub canAcceptShipForDocking:other];
				if ([docking isEqualToString:@"DOCK_CLOSED"])
				{
					JSContext	*context = OOJSAcquireContext();
					jsval		rval = JSVAL_VOID;
					jsval		args[] = { OOJSValueFromNativeObject(context, sub),
														 OOJSValueFromNativeObject(context, other) };
					JSBool tempreject = NO;

					BOOL OK = [[self script] callMethod:OOJSID("willOpenDockingPortFor") inContext:context withArguments:args count:2 result:&rval];
					if (OK)  OK = JS_ValueToBoolean(context, rval, &tempreject);
					if (!OK)  tempreject = NO; // default to permreject
					if (tempreject)
					{
						openLater = YES;
					}
					OOJSRelinquishContext(context);			
				}
				if (openLater) break;
			}

			if (openLater)
			{
				[self sendExpandedMessage:@"[station-docking-clearance-denied-no-docks-yet]" toShip:other];
			} 
			else
			{
				[self sendExpandedMessage:@"[station-docking-clearance-denied-no-docks]" toShip:other];
			}

		}
	}

	// Ship has passed all checks - grant docking!
	if (result == nil)
	{
		last_launch_time = timeNow + DOCKING_CLEARANCE_WINDOW;
		if ([other isPlayer]) 
		{
			[player setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
			player_reserved_dock = [self selectDockForDocking];
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
		[self doScriptEvent:OOJSID("stationReceivedDockingRequest") withArgument:other];

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
		soa += [sub countOfShipsInDockingQueue];
	}
	soa += [_shipsOnHold count];
	return soa;
}


- (unsigned) currentlyInLaunchingQueues
{
	NSEnumerator	*subEnum = nil;
	DockEntity* sub = nil;
	unsigned soa = 0;
	for (subEnum = [self dockSubEntityEnumerator]; (sub = [subEnum nextObject]); )
	{
		soa += [sub countOfShipsInLaunchQueue];
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


- (BOOL) allowsSaving
{
	// fixed stations only, not carriers!
	return allowsSaving && ([self maxFlightSpeed] == 0);
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


- (BOOL) hasBreakPattern
{
	return hasBreakPattern;
}


- (void) setHasBreakPattern:(BOOL)newValue
{
	hasBreakPattern = !!newValue;
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\" %@", name, [super descriptionComponents]];
}


- (void)dumpSelfState
{
	NSMutableArray		*flags = nil;
	NSString			*flagsString = nil;
	NSString			*alertString = @"*** ERROR: UNKNOWN ALERT LEVEL ***";
	
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
	}
	
	OOLog(@"dumpState.stationEntity", @"Alert level: %@", alertString);
	OOLog(@"dumpState.stationEntity", @"Max police: %u", max_police);
	OOLog(@"dumpState.stationEntity", @"Max defense ships: %u", max_defense_ships);
	OOLog(@"dumpState.stationEntity", @"Defenders launched: %u", defenders_launched);
	OOLog(@"dumpState.stationEntity", @"Max scavengers: %u", max_scavengers);
	OOLog(@"dumpState.stationEntity", @"Scavengers launched: %u", scavengers_launched);
	OOLog(@"dumpState.stationEntity", @"Docked shuttles: %u", docked_shuttles);
	OOLog(@"dumpState.stationEntity", @"Docked traders: %u", docked_traders);
	OOLog(@"dumpState.stationEntity", @"Equivalent tech level: %li", equivalentTechLevel);
	OOLog(@"dumpState.stationEntity", @"Equipment price factor: %g", equipmentPriceFactor);
	
	flags = [NSMutableArray array];
	#define ADD_FLAG_IF_SET(x)		if (x) { [flags addObject:@#x]; }
	ADD_FLAG_IF_SET(no_docking_while_launching);
	if ([self isRotatingStation]) { [flags addObject:@"rotatingStation"]; }
	if (![self dockingCorridorIsEmpty]) { [flags addObject:@"dockingCorridorIsBusy"]; }
	flagsString = [flags count] ? [flags componentsJoinedByString:@", "] : (NSString *)@"none";
	OOLog(@"dumpState.stationEntity", @"Flags: %@", flagsString);
	
	// approach and hold lists.
	
	// Ships on hold list, only used with moving stations (= carriers)
	if([_shipsOnHold count] > 0)
	{
		OOLog(@"dumpState.stationEntity", @"%li Ships on hold (unsorted):", [_shipsOnHold count]);
		
		OOLogIndent();
		NSEnumerator	*onHoldEnum = [_shipsOnHold objectEnumerator];
		ShipEntity		*ship = nil;
		unsigned		i = 1;
		while ((ship = [onHoldEnum nextObject]))
		{
			OOLog(@"dumpState.stationEntity", @"Nr %i: %@ at distance %g with role: %@", i++, [ship displayName], HPdistance([self position], [ship position]), [ship primaryRole]);
		}
		OOLogOutdent();
	}
}

@end
