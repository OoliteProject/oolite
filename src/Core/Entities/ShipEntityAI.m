/*
 
 ShipEntityAI.m
 
 Oolite
 Copyright (C) 2004-2012 Giles C Williams and contributors
 
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

#import "ShipEntityAI.h"
#import "OOMaths.h"
#import "Universe.h"
#import "AI.h"

#import "StationEntity.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "WormholeEntity.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "OOJavaScriptEngine.h"
#import "OOJSFunction.h"
#import "OOShipGroup.h"

#import "OOStringParsing.h"
#import "OOEntityFilterPredicate.h"
#import "OOConstToString.h"
#import "OOConstToJSString.h"
#import "OOCollectionExtractors.h"

#define kOOLogUnconvertedNSLog @"unclassified.ShipEntityAI"


@interface ShipEntity (OOAIPrivate)

- (void) checkFoundTarget;

- (BOOL)performHyperSpaceExitReplace:(BOOL)replace;
- (BOOL)performHyperSpaceExitReplace:(BOOL)replace toSystem:(OOSystemID)systemID;

- (void)scanForNearestShipWithPredicate:(EntityFilterPredicate)predicate parameter:(void *)parameter;
- (void)scanForNearestShipWithNegatedPredicate:(EntityFilterPredicate)predicate parameter:(void *)parameter;

- (void) acceptDistressMessageFrom:(ShipEntity *)other;

@end


@interface StationEntity (OOAIPrivate)

- (void) acceptDistressMessageFrom:(ShipEntity *)other;

@end


@interface ShipEntity (PureAI)

// Methods used only by AI.

- (void) setStateTo:(NSString *)state;

- (void) pauseAI:(NSString *)intervalString;

- (void) randomPauseAI:(NSString *)intervalString;

- (void) dropMessages:(NSString *)messageString;

- (void) debugDumpPendingMessages;

- (void) setDestinationToCurrentLocation;

- (void) setDesiredRangeTo:(NSString *)rangeString;

- (void) setDesiredRangeForWaypoint;

- (void) setSpeedTo:(NSString *)speedString;

- (void) setSpeedFactorTo:(NSString *)speedString;

- (void) setSpeedToCruiseSpeed;

- (void) setThrustFactorTo:(NSString *)thrustFactorString;

- (void) performFlyToRangeFromDestination;

- (void) performIdle;

- (void) performHold;

- (void) setTargetToPrimaryAggressor;

- (void) performAttack;

- (void) scanForNearestMerchantman;
- (void) scanForRandomMerchantman;

- (void) scanForLoot;

- (void) scanForRandomLoot;

- (void) setTargetToFoundTarget;

- (void) checkForFullHold;

- (void) performCollect;

- (void) performIntercept;

- (void) performFlee;

- (void) performScriptedAI;
- (void) performScriptedAttackAI;

- (void) requestDockingCoordinates;

- (void) getWitchspaceEntryCoordinates;

- (void) setDestinationFromCoordinates;
- (void) setCoordinatesFromPosition;

- (void) performFaceDestination;

- (void) fightOrFleeMissile;

- (void) setCourseToPlanet;
- (void) performLandOnPlanet;
- (void) setTakeOffFromPlanet;
- (void) landOnPlanet;

- (void) checkTargetLegalStatus;
- (void) checkOwnLegalStatus;

- (void) exitAIWithMessage:(NSString *)message;

- (void) setDestinationToTarget;
- (void) setDestinationWithinTarget;

- (void) checkCourseToDestination;

- (void) checkAegis;

- (void) checkEnergy;
- (void) checkHeatInsulation;

- (void) scanForOffenders;

- (void) setCourseToWitchpoint;

- (void) setDestinationToWitchpoint;
- (void) setDestinationToStationBeacon;

- (void) performHyperSpaceExit;
- (void) performHyperSpaceExitWithoutReplacing;
- (void) wormholeGroup;
- (void) wormholeEntireGroup;

- (void) commsMessage:(NSString *)valueString;
- (void) commsMessageByUnpiloted:(NSString *)valueString;
- (void) broadcastDistressMessage;

- (void) ejectCargo;

- (void) scanForThargoid;
- (void) scanForNonThargoid;
- (void) thargonCheckMother;
- (void) becomeUncontrolledThargon;

- (void) checkDistanceTravelled;

- (void) fightOrFleeHostiles;

- (void) suggestEscort;

- (void) escortCheckMother;

- (void) performEscort;

- (void) checkGroupOddsVersusTarget;

- (void) groupAttackTarget;

- (void) scanForFormationLeader;

- (void) messageMother:(NSString *)msgString;

- (void) setPlanetPatrolCoordinates;

- (void) setSunSkimStartCoordinates;

- (void) setSunSkimEndCoordinates;

- (void) setSunSkimExitCoordinates;

- (void) patrolReportIn;

- (void) checkForMotherStation;

- (void) sendTargetCommsMessage:(NSString *) message;

- (void) markTargetForFines;

- (void) markTargetForOffence:(NSString *) valueString;

- (void) storeTarget;
- (void) recallStoredTarget;

- (void) scanForRocks;

- (void) performMining;

- (void) setDestinationToDockingAbort;

- (void) requestNewTarget;

- (void) rollD:(NSString *) die_number;

- (void) scanForNearestShipWithPrimaryRole:(NSString *)scanRole;
- (void) scanForNearestShipHavingRole:(NSString *)scanRole;
- (void) scanForNearestShipWithAnyPrimaryRole:(NSString *)scanRoles;
- (void) scanForNearestShipHavingAnyRole:(NSString *)scanRoles;
- (void) scanForNearestShipWithScanClass:(NSString *)scanScanClass;

- (void) scanForNearestShipWithoutPrimaryRole:(NSString *)scanRole;
- (void) scanForNearestShipNotHavingRole:(NSString *)scanRole;
- (void) scanForNearestShipWithoutAnyPrimaryRole:(NSString *)scanRoles;
- (void) scanForNearestShipNotHavingAnyRole:(NSString *)scanRoles;
- (void) scanForNearestShipWithoutScanClass:(NSString *)scanScanClass;

- (void) setCoordinates:(NSString *)system_x_y_z;

- (void) checkForNormalSpace;

- (void) setTargetToRandomStation;
- (void) setTargetToLastStation;
- (void) recallDockingInstructions;

- (void) addFuel:(NSString *) fuel_number;

- (void) enterPlayerWormhole;

- (void) scriptActionOnTarget:(NSString *) action;

- (void) sendScriptMessage:(NSString *)message;

- (void) ai_throwSparks;

- (void) explodeSelf;

- (void) ai_debugMessage:(NSString *)message;

// racing code.
- (void) targetFirstBeaconWithCode:(NSString *) code;
- (void) targetNextBeaconWithCode:(NSString *) code;
- (void) setRacepointsFromTarget;
- (void) performFlyRacepoints;

// defense targets 
- (void) addPrimaryAggressorAsDefenseTarget;
- (void) addFoundTargetAsDefenseTarget;
- (void) findNewDefenseTarget;

@end


@implementation ShipEntity (AI)


- (void) setAITo:(NSString *)aiString
{
	[[self getAI] setStateMachine:aiString];
}


- (void) switchAITo:(NSString *)aiString
{
	[[self getAI] setStateMachine:aiString];
	[[self getAI] clearStack];
}


- (void) scanForHostiles
{
	/*-- Locates all the ships in range targeting the receiver and chooses the nearest --*/
	DESTROY(_foundTarget);
	
	[self checkScanner];
	unsigned i;
	GLfloat found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *thing = scanned_ships[i];
		GLfloat d2 = distance2_scanned_ships[i];
		if ((d2 < found_d2) 
			&& ([thing isThargoid] || (([thing primaryTarget] == self) && [thing hasHostileTarget]) || [thing isDefenseTarget:self])
			&& ![thing isCloaked])
		{
			[self setFoundTarget:thing];
			found_d2 = d2;
		}
	}
	
	[self checkFoundTarget];
}


- (void) performTumble
{
	stick_roll = max_flight_roll*2.0*(randf() - 0.5);
	stick_pitch = max_flight_pitch*2.0*(randf() - 0.5);
	behaviour = BEHAVIOUR_TUMBLE;
	frustration = 0.0;
}


- (void) performStop
{
	behaviour = BEHAVIOUR_STOP_STILL;
	desired_speed = 0.0;
	frustration = 0.0;
}


- (BOOL) performHyperSpaceToSpecificSystem:(OOSystemID)systemID
{
	return [self performHyperSpaceExitReplace:NO toSystem:systemID];
}


- (void) scanForNearestIncomingMissile
{
	BinaryOperationPredicateParameter param =
	{
		HasScanClassPredicate, [NSNumber numberWithInt:CLASS_MISSILE],
		IsHostileAgainstTargetPredicate, self
	};
	[self scanForNearestShipWithPredicate:ANDPredicate parameter:&param];
}


- (void) enterTargetWormhole
{
	WormholeEntity *whole = nil;
	ShipEntity		*targEnt = [self primaryTarget];
	double found_d2 = scannerRange * scannerRange;
	
	if (targEnt && (distance2(position, [targEnt position]) < found_d2))
	{
		if ([targEnt isWormhole])
			whole = (WormholeEntity *)targEnt;
		else if ([targEnt isPlayer])
			whole = [PLAYER wormhole];
	}

	if (!whole)
	{
		// locate nearest wormhole
		int				ent_count =		UNIVERSE->n_entities;
		Entity**		uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
		WormholeEntity*	wormholes[ent_count];
		int i;
		int wh_count = 0;
		for (i = 0; i < ent_count; i++)
			if (uni_entities[i]->isWormhole)
				wormholes[wh_count++] = [(WormholeEntity *)uni_entities[i] retain];
		//
		//double found_d2 = scannerRange * scannerRange;
		for (i = 0; i < wh_count ; i++)
		{
			WormholeEntity *wh = wormholes[i];
			double d2 = distance2(position, wh->position);
			if (d2 < found_d2)
			{
				whole = wh;
				found_d2 = d2;
			}
			[wh release];
		}
	}
	
	[self enterWormhole:whole replacing:NO];
}


// FIXME: resolve this stuff.
- (void) wormholeEscorts
{
	NSEnumerator		*shipEnum = nil;
	ShipEntity			*ship = nil;
	NSString			*context = nil;
	WormholeEntity		*whole = nil;
	
	whole = [self primaryTarget];
	if (![whole isWormhole])  return;
	
#ifndef NDEBUG
	context = [NSString stringWithFormat:@"%@ wormholeEscorts", [self shortDescription]];
#endif
	
	for (shipEnum = [self escortEnumerator]; (ship = [shipEnum nextObject]); )
	{
		[ship addTarget:whole];
		[ship reactToAIMessage:@"ENTER WORMHOLE" context:context];
	}
	
	// We now have no escorts..
	[_escortGroup release];
	_escortGroup = nil;
	
}

@end


@implementation ShipEntity (PureAI)

- (void) setStateTo:(NSString *)state
{
	[[self getAI] setState:state];
}


- (void) pauseAI:(NSString *)intervalString
{
	[shipAI setNextThinkTime:[UNIVERSE getTime] + [intervalString doubleValue]];
}


- (void) randomPauseAI:(NSString *)intervalString
{
	NSArray*	tokens = ScanTokensFromString(intervalString);
	double start, end;
	
	if ([tokens count] != 2)
	{
		OOLog(@"ai.syntax.randomPauseAI", @"***** ERROR: cannot read min and max value for randomPauseAI:, needs 2 values: '%@'.", intervalString);
		return;
	}
	
	start = [tokens oo_doubleAtIndex:0];
	end   = [tokens oo_doubleAtIndex:1];
	
	[shipAI setNextThinkTime:[UNIVERSE getTime] + (start + (end - start)*randf())];
}


- (void) dropMessages:(NSString *)messageString
{
	NSArray				*messages = nil;
	NSEnumerator		*messageEnum = nil;
	NSString			*message = nil;
	NSCharacterSet		*whiteSpace = [NSCharacterSet whitespaceCharacterSet];
	
	messages = [messageString componentsSeparatedByString:@","];
	for (messageEnum = [messages objectEnumerator]; (message = [messageEnum nextObject]); )
	{
		[shipAI dropMessage:[message stringByTrimmingCharactersInSet:whiteSpace]];
	}
}


- (void) debugDumpPendingMessages
{
	[shipAI debugDumpPendingMessages];
}


- (void) setDestinationToCurrentLocation
{
	// randomly add a .5m variance
	destination = vector_add(position, OOVectorRandomSpatial(0.5));
}


- (void) setDestinationToJinkPosition
{
	Vector front = vector_multiply_scalar([self forwardVector], flightSpeed / max_flight_pitch * 2);
	destination = vector_add(position, vector_add(front, OOVectorRandomSpatial(100)));
	pitching_over = YES; // don't complete roll first, but immediately start with pitching. 
}


- (void) setDesiredRangeTo:(NSString *)rangeString
{
	desired_range = [rangeString doubleValue];
}

- (void) setDesiredRangeForWaypoint
{
	desired_range = fmax(maxFlightSpeed / max_flight_pitch / 6, 50.0); // some ships need a longer range to reach a waypoint.
}

- (void) performFlyToRangeFromDestination
{
	behaviour = BEHAVIOUR_FLY_RANGE_FROM_DESTINATION;
	frustration = 0.0;
}


- (void) setSpeedTo:(NSString *)speedString
{
	desired_speed = [speedString doubleValue];
}


- (void) setSpeedFactorTo:(NSString *)speedString
{
	desired_speed = maxFlightSpeed * [speedString doubleValue];
}

- (void) setSpeedToCruiseSpeed
{
	desired_speed = cruiseSpeed;
}

- (void) setThrustFactorTo:(NSString *)thrustFactorString
{
	thrust = OOClamp_0_1_f([thrustFactorString doubleValue]) * max_thrust;
}


- (void) performIdle
{
	behaviour = BEHAVIOUR_IDLE;
	frustration = 0.0;
}


- (void) performHold
{
	desired_speed = 0.0;
	behaviour = BEHAVIOUR_TRACK_TARGET;
	frustration = 0.0;
}


- (void) setTargetToPrimaryAggressor
{
	Entity *primeAggressor = [self primaryAggressor];
	if (!primeAggressor)
		return;
	if ([self primaryTarget] == primeAggressor)
		return;
	
	// a more considered approach here:
	// if we're already busy attacking a target we don't necessarily want to break off
	//
	if ([self hasHostileTarget] && randf() < 0.75)	// if I'm attacking, ignore 75% of new aggressor's attacks
	{
				// but add them as a secondary target anyway
		[self addDefenseTarget:(ShipEntity*)primeAggressor];
		return;
	}
	// react only if the primary aggressor is not a friendly ship, else ignore it
	if ([primeAggressor isShip] && ![(ShipEntity *)primeAggressor isFriendlyTo:self])
	{
		// inform our old target of our new target
		//
		Entity *primeTarget = [self primaryTarget];
		if ((primeTarget)&&(primeTarget->isShip))
		{
			ShipEntity *currentShip = [self primaryTarget];
			[[currentShip getAI] message:[NSString stringWithFormat:@"%@ %d %d", AIMS_AGGRESSOR_SWITCHED_TARGET, universalID, [[self primaryAggressor] universalID]]];
		}
		
		// okay, so let's now target the aggressor
		[self addTarget:[self primaryAggressor]];
	}
}


- (void) addPrimaryAggressorAsDefenseTarget
{
	Entity *primeAggressor = [self primaryAggressor];
	if (!primeAggressor)
		return;
	if ([self isDefenseTarget:primeAggressor])
		return;
	
	if ([primeAggressor isShip] && ![(ShipEntity*)primeAggressor isFriendlyTo:self])
	{
		[self addDefenseTarget:primeAggressor];
	}
}


- (void) performAttack
{
	behaviour = BEHAVIOUR_ATTACK_TARGET;
	desired_range = 1250 * randf() + 750; // 750 til 2000
	frustration = 0.0;
}


- (void) performBroadside
{
	behaviour = BEHAVIOUR_ATTACK_BROADSIDE;
	desired_range = 1250 * randf() + 750; // 750 til 2000
	frustration = 0.0;
}


- (void) scanForNearestMerchantman
{
	float				d2, found_d2;
	unsigned			i;
	ShipEntity			*ship = nil;
	
	//-- Locates the nearest merchantman in range.
	[self checkScanner];
	
	found_d2 = scannerRange * scannerRange;
	DESTROY(_foundTarget);
	
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ship = scanned_ships[i];
		if ([ship isPirateVictim] && ([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED) && ![ship isCloaked])
		{
			d2 = distance2_scanned_ships[i];
			if (PIRATES_PREFER_PLAYER && (d2 < desired_range * desired_range) && ship->isPlayer && [self isPirate])
			{
				d2 = 0.0;
			}
			else d2 = distance2_scanned_ships[i];
			if (d2 < found_d2)
			{
				found_d2 = d2;
				[self setFoundTarget:ship];
			}
		}
	}
	[self checkFoundTarget];
}


- (void) scanForRandomMerchantman
{
	unsigned			n_found, i;
	
	//-- Locates one of the merchantman in range.
	[self checkScanner];
	ShipEntity*		ids_found[n_scanned_ships];
	
	n_found = 0;
	DESTROY(_foundTarget);
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *ship = scanned_ships[i];
		if (([ship status] != STATUS_DEAD) && ([ship status] != STATUS_DOCKED) && [ship isPirateVictim] && ![ship isCloaked])
			ids_found[n_found++] = ship;
	}
	if (n_found == 0)
	{
		[shipAI message:@"NOTHING_FOUND"];
	}
	else
	{
		i = ranrot_rand() % n_found;	// pick a number from 0 -> (n_found - 1)
		[self setFoundTarget:ids_found[i]];
		[shipAI message:@"TARGET_FOUND"];
	}
}


- (void) scanForLoot
{
	/*-- Locates the nearest debris in range --*/
	if (!isStation)
	{
		if (![self hasScoop])
		{
			[shipAI message:@"NOTHING_FOUND"];		//can't collect loot if you have no scoop!
			return;
		}
		if ([cargo count] >= [self maxAvailableCargoSpace])
		{
			if (max_cargo)  [shipAI message:@"HOLD_FULL"];	//can't collect loot if holds are full!
			[shipAI message:@"NOTHING_FOUND"];		//can't collect loot if holds are full!
			return;
		}
	}
	else
	{
		if (magnitude2([self velocity]))
		{
			[shipAI message:@"NOTHING_FOUND"];		//can't collect loot if you're a moving station
			return;
		}
	}
	
	[self checkScanner];
	
	double found_d2 = scannerRange * scannerRange;
	DESTROY(_foundTarget);
	unsigned i;
	for (i = 0; i < n_scanned_ships; i++)
	{
		ShipEntity *other = (ShipEntity *)scanned_ships[i];
		if ([other scanClass] == CLASS_CARGO && [other cargoType] != CARGO_NOT_CARGO && [other status] != STATUS_BEING_SCOOPED)
		{
			if ((![self isPolice]) || ([other commodityType] == 3)) // police only rescue lifepods and slaves
			{
				GLfloat d2 = distance2_scanned_ships[i];
				if (d2 < found_d2)
				{
					found_d2 = d2;
					[self setFoundTarget:other];
				}
			}
		}
	}
	[self checkFoundTarget];
}


- (void) scanForRandomLoot
{
	/*-- Locates the all debris in range and chooses a piece at random from the first sixteen found --*/
	if (![self isStation] && ![self hasScoop])
	{
		[shipAI message:@"NOTHING_FOUND"];		//can't collect loot if you have no scoop!
		return;
	}
	//
	[self checkScanner];
	//
	ShipEntity* thing_uids_found[16];
	unsigned things_found = 0;
	DESTROY(_foundTarget);
	unsigned i;
	for (i = 0; (i < n_scanned_ships)&&(things_found < 16) ; i++)
	{
		ShipEntity *other = scanned_ships[i];
		if ([other scanClass] == CLASS_CARGO && [other cargoType] != CARGO_NOT_CARGO && [other status] != STATUS_BEING_SCOOPED)
		{
			thing_uids_found[things_found++] = other;
		}
	}
	
	if (things_found != 0)
	{
		[self setFoundTarget:thing_uids_found[ranrot_rand() % things_found]];
		[shipAI message:@"TARGET_FOUND"];
	}
	else
		[shipAI message:@"NOTHING_FOUND"];
}


- (void) setTargetToFoundTarget
{
	if ([self foundTarget] != nil)
	{
		[self addTarget:[self foundTarget]];
	}
	else
	{
		[shipAI message:@"TARGET_LOST"]; // to prevent the ship going for a wrong, previous target. Should not be a reactToMessage.
	}
}


- (void) addFoundTargetAsDefenseTarget
{
	Entity* fTarget = [self foundTarget];
	if (fTarget != nil)
	{
		if ([fTarget isShip] && ![(ShipEntity *)fTarget isFriendlyTo:self])
		{
			[self addDefenseTarget:fTarget];
		}
	}
}

- (void) checkForFullHold
{
	if (!max_cargo)
	{
		[shipAI message:@"NO_CARGO_BAY"];
	}
	else if ([cargo count] >= [self maxAvailableCargoSpace])
	{
		[shipAI message:@"HOLD_FULL"];
	}
	else
	{
		[shipAI message:@"HOLD_NOT_FULL"];
	}
}


- (void) performCollect
{
	behaviour = BEHAVIOUR_COLLECT_TARGET;
	frustration = 0.0;
}


- (void) performIntercept
{
	behaviour = BEHAVIOUR_INTERCEPT_TARGET;
	frustration = 0.0;
}


- (void) performFlee
{
	behaviour = BEHAVIOUR_FLEE_TARGET;

	[self setEvasiveJink:400.0];

	frustration = 0.0;
}


- (void) performScriptedAI
{
	behaviour = BEHAVIOUR_SCRIPTED_AI;
	frustration = 0.0;
}


- (void) performScriptedAttackAI
{
	behaviour = BEHAVIOUR_SCRIPTED_ATTACK_AI;
	frustration = 0.0;
}


- (void) getWitchspaceEntryCoordinates
{
	/*- calculates coordinates from the nearest station it can find, or just fly 10s forward -*/
	if (!UNIVERSE)
	{
		Vector  vr = vector_multiply_scalar(v_forward, maxFlightSpeed * 10.0);  // 10 second flying away
		coordinates = vector_add(position, vr);
		return;
	}
	//
	// find the nearest station...
	//
	// we don't use "checkScanner" because we must rely on finding a present station.
	//
	StationEntity	*station =  nil;
	station = [UNIVERSE nearestShipMatchingPredicate:IsStationPredicate
										   parameter:nil
									relativeToEntity:self];
	
	if (station && distance2([station position], position) < SCANNER_MAX_RANGE2) // there is a station in range.
	{
		Vector  vr = vector_multiply_scalar([station rightVector], 10000);  // 10km from station
		coordinates = vector_add([station position], vr);
	}
	else
	{
		Vector  vr = vector_multiply_scalar(v_forward, maxFlightSpeed * 10.0);  // 10 second flying away
		coordinates = vector_add(position, vr);
	}
}


- (void) setDestinationFromCoordinates
{
	destination = coordinates;
}


- (void) setCoordinatesFromPosition
{
	coordinates = position;
}


- (void) performFaceDestination
{
	behaviour = BEHAVIOUR_FACE_DESTINATION;
	frustration = 0.0;
}


- (void) fightOrFleeMissile
{
	// find an incoming missile...
	//
	ShipEntity			*missile =  nil;
	unsigned			i;
	NSEnumerator		*escortEnum = nil;
	ShipEntity			*escort = nil;
	ShipEntity			*target = nil;
	
	[self checkScanner];
	for (i = 0; (i < n_scanned_ships)&&(missile == nil); i++)
	{
		ShipEntity *thing = scanned_ships[i];
		if (thing->scanClass == CLASS_MISSILE)
		{
			target = [thing primaryTarget];
			
			if (target == self)
			{
				missile = thing;
			}
			else
			{
				for (escortEnum = [self escortEnumerator]; (escort = [escortEnum nextObject]); )
				{
					if (target == escort)
					{
						missile = thing;
					}
				}
			}
		}
	}
	
	if (missile == nil)  return;
	
	[self addTarget:missile];
	[self addDefenseTarget:missile];
	
	// Notify own ship script that we are being attacked.	
	ShipEntity *hunter = [missile owner];
	[self doScriptEvent:OOJSID("shipBeingAttacked") withArgument:hunter];
	[hunter doScriptEvent:OOJSID("shipAttackedOther") withArgument:self];
	
	if ([self isPolice])
	{
		// Notify other police in group of attacker.
		// Note: prior to 1.73 this was done only if we had ECM.
		NSEnumerator	*policeEnum = nil;
		ShipEntity		*police = nil;
		
		for (policeEnum = [[self group] mutationSafeEnumerator]; (police = [policeEnum nextObject]); )
		{
			[police setFoundTarget:hunter];
			[police setPrimaryAggressor:hunter];
		}
	}
	
	// if I'm a copper and you're not, then mark the other as an offender!
	if ([self isPolice] && ![hunter isPolice])  [hunter markAsOffender:64 withReason:kOOLegalStatusReasonAttackedPolice];

	if ([self hasECM])
	{
		// use the ECM and battle on
		
		[self setPrimaryAggressor:hunter];	// lets get them now for that!
		[self setFoundTarget:hunter];
		
		[self fireECM];
		return;
	}
	
	// RUN AWAY !!
	desired_range = 10000;
	[self performFlee];
	[shipAI message:@"FLEEING"];
}


- (void) setCourseToPlanet
{
	/*- selects the nearest planet it can find -*/
	OOPlanetEntity	*the_planet =  [self findNearestPlanetExcludingMoons];
	if (the_planet)
	{
		double variation = (aegis_status == AEGIS_NONE ? 0.5 : 0.2); // more random deviation when far from planet.
		Vector p_pos = the_planet->position;
		double p_cr = the_planet->collision_radius;		// the surface
		Vector p1 = vector_between(p_pos, position);
		p1 = vector_normal(p1);			// vector towards ship
		p1.x += variation * (randf() - variation);
		p1.y += variation * (randf() - variation);
		p1.z += variation * (randf() - variation);
		p1 = vector_normal(p1); 
		destination = vector_add(p_pos, vector_multiply_scalar(p1, p_cr));	// on surface
		desired_range = collision_radius + 100.0;	// +100m from the destination
	}
	else
	{
		[shipAI message:@"NO_PLANET_FOUND"];
	}
}


- (void) setTakeOffFromPlanet
{
	/*- selects the nearest planet it can find -*/
	OOPlanetEntity	*the_planet =  [self findNearestPlanet];
	if (the_planet)
	{
		destination = vector_add([the_planet position], vector_multiply_scalar(
																			   vector_normal(vector_subtract([the_planet position],position)),-10000.0-the_planet->collision_radius));// 10km straight up
		desired_range = 50.0;
	}
	else
	{
		OOLog(@"ai.setTakeOffFromPlanet.noPlanet", @"***** Error. Planet not found during take off!");
	}
}


- (void) performLandOnPlanet
{
	OOPlanetEntity	*nearest = [self findNearestPlanet];
	if (isNearPlanetSurface)
	{
		destination = [nearest position];
		behaviour = BEHAVIOUR_LAND_ON_PLANET;
		planetForLanding = [nearest universalID];
	}
	else
	{
		behaviour = BEHAVIOUR_IDLE;
		[shipAI message:@"NO_PLANET_NEARBY"];
	}
	
	frustration = 0.0;
}


- (void) landOnPlanet
{
	// Selects the nearest planet it can find.
	[self landOnPlanet:[self findNearestPlanet]];
}


- (void) checkTargetLegalStatus
{
	ShipEntity  *other_ship = [self primaryTarget];
	if (!other_ship)
	{
		[shipAI message:@"NO_TARGET"];
		return;
	}
	else
	{
		int ls = [other_ship legalStatus];
		if (ls > 50)
		{
			[shipAI message:@"TARGET_FUGITIVE"];
			return;
		}
		if (ls > 20)
		{
			[shipAI message:@"TARGET_OFFENDER"];
			return;
		}
		if (ls > 0)
		{
			[shipAI message:@"TARGET_MINOR_OFFENDER"];
			return;
		}
		[shipAI message:@"TARGET_CLEAN"];
	}
}


- (void) checkOwnLegalStatus
{
	if (scanClass == CLASS_THARGOID)
	{
		[shipAI message:@"SELF_THARGOID"];
		return;
	}
	int ls = [self legalStatus];
	if (ls > 50)
	{
		[shipAI message:@"SELF_FUGITIVE"];
		return;
	}
	if (ls > 20)
	{
		[shipAI message:@"SELF_OFFENDER"];
		return;
	}
	if (ls > 0)
	{
		[shipAI message:@"SELF_MINOR_OFFENDER"];
		return;
	}
	[shipAI message:@"SELF_CLEAN"];
}


- (void) exitAIWithMessage:(NSString *)message
{
	if ([message length] == 0)  message = @"RESTARTED";
	[shipAI exitStateMachineWithMessage:message];
}


- (void) setDestinationToTarget
{
	Entity *the_target = [self primaryTarget];
	if (the_target)
		destination = the_target->position;
}


- (void) setDestinationWithinTarget
{
	Entity *the_target = [self primaryTarget];
	if (the_target)
	{
		Vector pos = the_target->position;
		Quaternion q;	quaternion_set_random(&q);
		Vector v = vector_forward_from_quaternion(q);
		GLfloat d = (randf() - randf()) * the_target->collision_radius;
		destination = make_vector(pos.x + d * v.x, pos.y + d * v.y, pos.z + d * v.z);
	}
}


- (void) checkCourseToDestination
{
	Entity *hazard = [UNIVERSE hazardOnRouteFromEntity: self toDistance: desired_range fromPoint: destination];
	
	if (hazard == nil || ([hazard isShip] && distance(position, [hazard position]) > scannerRange) || ([hazard isPlanet] && aegis_status == AEGIS_NONE)) 
		[shipAI message:@"COURSE_OK"]; // Avoid going into a waypoint.plist for far away objects, it cripples the main AI a bit in its funtionality.
	else
	{
		if ([hazard isShip] && (weapon_damage * 24.0 > [hazard energy]))
		{
			[shipAI reactToMessage:@"HAZARD_CAN_BE_DESTROYED" context:@"checkCourseToDestination"];
		}
		
		destination = [UNIVERSE getSafeVectorFromEntity:self toDistance:desired_range fromPoint:destination];
		[shipAI message:@"WAYPOINT_SET"];
	}
}


- (void) checkAegis
{
	switch(aegis_status)
	{
		case AEGIS_CLOSE_TO_MAIN_PLANET: 
			[shipAI message:@"AEGIS_CLOSE_TO_MAIN_PLANET"];
			// It's been a few years since 1.71 - it should be safe enough to comment out the line below for 1.77/1.78 -- Kaks 20120917
			//[shipAI message:@"AEGIS_CLOSE_TO_PLANET"];	     // fires only for main planets, kept for compatibility with pre-1.72 AI plists.
			break;
		case AEGIS_CLOSE_TO_ANY_PLANET:
		{
			Entity<OOStellarBody> *nearest = [self findNearestStellarBody];
			
			if([nearest isSun])
			{
				[shipAI message:@"CLOSE_TO_SUN"];
			}
			else
			{
				[shipAI message:@"CLOSE_TO_PLANET"];
				if ([nearest planetType] == STELLAR_TYPE_MOON)
				{
					[shipAI message:@"CLOSE_TO_MOON"];
				}
				else
				{
					[shipAI message:@"CLOSE_TO_SECONDARY_PLANET"];
				}
			}
			break;
		}
		case AEGIS_IN_DOCKING_RANGE:
			[shipAI message:@"AEGIS_IN_DOCKING_RANGE"];
			break;
		case AEGIS_NONE:
		default: 
			[shipAI message:@"AEGIS_NONE"];
			break;
	}
}


- (void) checkEnergy
{
	if (energy == maxEnergy)
	{
		[shipAI message:@"ENERGY_FULL"];
		return;
	}
	if (energy >= maxEnergy * 0.75)
	{
		[shipAI message:@"ENERGY_HIGH"];
		return;
	}
	if (energy <= maxEnergy * 0.25)
	{
		[shipAI message:@"ENERGY_LOW"];
		return;
	}
	[shipAI message:@"ENERGY_MEDIUM"];
}

- (void) checkHeatInsulation
{
	float minInsulation = 1000 / [self maxFlightSpeed] + 1;
	
	if ([self heatInsulation] < minInsulation)
	{
		[shipAI message:@"INSULATION_POOR"];
		return;
	}
	[shipAI message:@"INSULATION_OK"];
}


- (void) findNewDefenseTarget
{
	[self checkScanner];
	unsigned i;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *ship = scanned_ships[i];
		if (![ship isCloaked] && (([ship primaryTarget] == self && [ship hasHostileTarget]) || [ship isMine] || ([ship isThargoid] != [self isThargoid])))
		{
			if (![self isDefenseTarget:ship])
			{
				[self addDefenseTarget:ship];
				return;
			}
		}
	}
}


- (void) scanForOffenders
{
	/*-- Locates all the ships in range and compares their legal status or bounty against ranrot_rand() & 255 - chooses the worst offender --*/
	NSDictionary		*systeminfo = [UNIVERSE currentSystemData];
	float gov_factor =	0.4 * [(NSNumber *)[systeminfo objectForKey:KEY_GOVERNMENT] intValue]; // 0 .. 7 (0 anarchic .. 7 most stable) --> [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8]
	//
	if ([UNIVERSE sun] == nil)
		gov_factor = 1.0;
	//
	DESTROY(_foundTarget);
	
	// find the worst offender on the scanner
	//
	[self checkScanner];
	unsigned i;
	float	worst_legal_factor = 0;
	GLfloat found_d2 = scannerRange * scannerRange;
	OOShipGroup *group = [self group];
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *ship = scanned_ships[i];
		if ((ship->scanClass != CLASS_CARGO)&&([ship status] != STATUS_DEAD)&&([ship status] != STATUS_DOCKED)&& ![ship isCloaked])
		{
			GLfloat	d2 = distance2_scanned_ships[i];
			float	legal_factor = [ship legalStatus] * gov_factor;
			int random_factor = ranrot_rand() & 255;   // 25% chance of spotting a fugitive in 15s
			if ((d2 < found_d2)&&(random_factor < legal_factor)&&(legal_factor > worst_legal_factor))
			{
				if (group == nil || group != [ship group])  // fellows with bounty can't be offenders
				{
					[self setFoundTarget:ship];
					worst_legal_factor = legal_factor;
				}
			}
		}
	}
	
	[self checkFoundTarget];
}


- (void) setCourseToWitchpoint
{
	if (UNIVERSE)
	{
		destination = [UNIVERSE getWitchspaceExitPosition];
		desired_range = 10000.0;   // 10km away
	}
}


- (void) setDestinationToWitchpoint
{
	destination = [UNIVERSE getWitchspaceExitPosition];
}


- (void) setDestinationToStationBeacon
{
	if ([UNIVERSE station])
	{
		destination = [[UNIVERSE station] beaconPosition];
	}
}


- (void) performHyperSpaceExit
{
	[self performHyperSpaceExitReplace:YES];
}


- (void) performHyperSpaceExitWithoutReplacing
{
	[self performHyperSpaceExitReplace:NO];
}


- (void) disengageAutopilot
{
	OOLogERR(@"ai.invalid.notPlayer", @"Error in %@:%@, AI method endAutoPilot is only applicable to the player.", [shipAI name], [shipAI state]);
}


- (void) wormholeGroup
{
	NSEnumerator		*shipEnum = nil;
	ShipEntity			*ship = nil;
	WormholeEntity		*whole = nil;
	
	whole = [self primaryTarget];
	if (![whole isWormhole])  return;
	
	for (shipEnum = [[self group] mutationSafeEnumerator]; (ship = [shipEnum nextObject]); )
	{
		[ship addTarget:whole];
		[ship reactToAIMessage:@"ENTER WORMHOLE" context:@"wormholeGroup"];
	}
}


- (void) wormholeEntireGroup
{
	[self wormholeGroup];
	[self wormholeEscorts];
}


- (void) commsMessage:(NSString *)valueString
{
	[self commsMessage:valueString withUnpilotedOverride:NO];
}


- (void) commsMessageByUnpiloted:(NSString *)valueString
{
	[self commsMessage:valueString withUnpilotedOverride:YES];
}


- (void) broadcastDistressMessage
{
	/*-- Locates all the stations, bounty hunters and police ships in range and tells them that you are under attack --*/
	
	[self checkScanner];
	DESTROY(_foundTarget);
	
	ShipEntity	*aggressor_ship = (ShipEntity*)[self primaryAggressor];
	if (aggressor_ship == nil)  return;
	
	// don't send too many distress messages at once, space them out semi-randomly
	if (messageTime > 2.0 * randf())  return;
	
	NSString	*distress_message = nil;
	BOOL		is_buoy = (scanClass == CLASS_BUOY);
	if (is_buoy)  distress_message = @"[buoy-distress-call]";
	else  distress_message = @"[distress-call]";
	
	unsigned i;
	for (i = 0; i < n_scanned_ships; i++)
	{
		ShipEntity*	ship = scanned_ships[i];

    // dump cargo if energy is low
		if (!is_buoy && [self primaryAggressor] == ship && energy < 0.375 * maxEnergy)
		{
			[self ejectCargo];
			[self performFlee];
		}
		
		// tell it!
		if (ship->isPlayer)
		{
			if (!is_buoy && [self primaryAggressor] == ship && energy < 0.375 * maxEnergy)
			{
				[self sendExpandedMessage:ExpandDescriptionForCurrentSystem(@"[beg-for-mercy]") toShip:ship];
			}
			else if ([self bounty] == 0)
			{
				// only send distress message to player if plausibly sending
				// one more generally
				[self sendExpandedMessage:ExpandDescriptionForCurrentSystem(distress_message) toShip:ship];
			}
			
			// reset the thanked_ship_id
			DESTROY(_thankedShip);
		}
		else if ([self bounty] == 0 && [ship crew]) // Only clean ships can have their distress calls accepted
		{
			[ship doScriptEvent:OOJSID("distressMessageReceived") withArgument:aggressor_ship andArgument:self];
			
			// we only can send distressMessages to ships that are known to have a "ACCEPT_DISTRESS_CALL" reaction
			// in their AI, or they might react wrong on the added found_target.

			// FIXME: this test only works with core AIs
			if (ship->isStation || [ship hasPrimaryRole:@"police"] || [ship hasPrimaryRole:@"hunter"])
			{
				[ship acceptDistressMessageFrom:self];
			}
		}
	}
}


- (void) ejectCargo
{
	unsigned i;
	if (cargo_flag == CARGO_FLAG_FULL_PLENTIFUL || cargo_flag == CARGO_FLAG_FULL_SCARCE)
	{
		NSArray *jetsam;
		int cargo_to_go = 0.1 * [self maxAvailableCargoSpace];
		while (cargo_to_go > 15)
		{
			cargo_to_go = ranrot_rand() % cargo_to_go;
		}
		
		jetsam = [UNIVERSE getContainersOfGoods:cargo_to_go scarce:cargo_flag == CARGO_FLAG_FULL_SCARCE];
		
		if (cargo == nil)
		{
			cargo = [[NSMutableArray alloc] initWithCapacity:max_cargo];
		}
		
		[cargo addObjectsFromArray:jetsam];
		cargo_flag = CARGO_FLAG_CANISTERS;
	}
	[self dumpCargo];
	for (i = 1; i < [cargo count]; i++)
	{
		[self performSelector:@selector(dumpCargo) withObject:nil afterDelay:0.75 * i];	// drop 3 canisters per 2 seconds
	}
}


- (void) scanForThargoid
{
	return [self scanForNearestShipWithPrimaryRole:@"thargoid"];
}


- (void) scanForNonThargoid
{
	/*-- Locates all the non thargoid ships in range and chooses the nearest --*/
	DESTROY(_foundTarget);
	
	[self checkScanner];
	unsigned i;
	GLfloat	found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *thing = scanned_ships[i];
		GLfloat d2 = distance2_scanned_ships[i];
		if (([thing scanClass] != CLASS_CARGO) && ([thing status] != STATUS_DOCKED) && ![thing isThargoid] && ![thing isCloaked] && (d2 < found_d2))
		{
			[self setFoundTarget:thing];
			if ([thing isPlayer]) d2 = 0.0;   // prefer the player
			found_d2 = d2;
		}
	}

	[self checkFoundTarget];
}


- (void) thargonCheckMother
{
	ShipEntity   *mother = [self owner];
	if (mother == nil && [self group])  mother = [[self group] leader];
	
	double	maxRange2 = scannerRange * scannerRange;
	
	if (mother && mother != self && magnitude2(vector_subtract(mother->position, position)) < maxRange2)
	{
		[shipAI message:@"TARGET_FOUND"]; // no need for scanning, we still have our mother.
	}
	else
	{
		// we lost the old mother, search for a new one
		[self scanForNearestShipHavingRole:@"thargoid-mothership"]; // the scan will send further AI messages.
		if ([self foundTarget] != nil)
		{
			mother = (ShipEntity*)[self foundTarget];
			[self setOwner:mother];
			if ([mother group] != [mother escortGroup]) // avoid adding thargon to an escort group.
			{
				[self setGroup:[mother group]];
			}
		};
	}
}


- (void) becomeUncontrolledThargon
{
	int			ent_count =		UNIVERSE->n_entities;
	Entity**	uni_entities =	UNIVERSE->sortedEntities;	// grab the public sorted list
	int i;
	for (i = 0; i < ent_count; i++) if (uni_entities[i]->isShip)
	{
		ShipEntity *other = (ShipEntity*)uni_entities[i];
		if ([other primaryTarget] == self)
		{
			[other removeTarget:self];
		}
		if ([other isDefenseTarget:self])
		{
			[other removeDefenseTarget:self];
		}
	}
	// now we're just a bunch of alien artefacts!
	scanClass = CLASS_CARGO;
	reportAIMessages = NO;
	[shipAI setStateMachine:@"dumbAI.plist"];
	DESTROY(_primaryTarget);
	[self setSpeed: 0.0];
	[self setGroup:nil];
}


- (void) checkDistanceTravelled
{
	if (distanceTravelled > desired_range)
		[shipAI message:@"GONE_BEYOND_RANGE"];
}


- (void) fightOrFleeHostiles
{
	[self addDefenseTarget:[self foundTarget]];
	
	if ([self hasEscorts])
	{
		Entity *leTarget = [self lastEscortTarget];
		if (leTarget != nil)
		{
			[self setFoundTarget:leTarget];
			[shipAI message:@"FLEEING"];
			return;
		}
		
		[self setPrimaryAggressor:[self foundTarget]];
		[self addTarget:[self foundTarget]];
		[self deployEscorts];
		[shipAI message:@"DEPLOYING_ESCORTS"];
		[shipAI message:@"FLEEING"];
		return;
	}
	
	// consider launching a missile
	if (missiles > 2)   // keep a reserve
	{
		if (randf() < 0.50)
		{
			[self setPrimaryAggressor:[self foundTarget]];
			[self addTarget:[self foundTarget]];
			[self fireMissile];
			[shipAI message:@"FLEEING"];
			return;
		}
	}
	
	// consider fighting
	if (energy > maxEnergy * 0.80)
	{
		[self setPrimaryAggressor:[self foundTarget]];
		//[self performAttack];
		[shipAI message:@"FIGHTING"];
		return;
	}
	
	[shipAI message:@"FLEEING"];
}


- (void) suggestEscort
{
	ShipEntity   *mother = [self primaryTarget];
	if (mother)
	{
#ifndef NDEBUG
		if (reportAIMessages)
		{
			OOLog(@"ai.suggestEscort", @"DEBUG: %@ suggests escorting %@", self, mother);
		}
#endif
		
		if ([mother acceptAsEscort:self])
		{
			// copy legal status across
			if (([mother legalStatus] > 0)&&(bounty <= 0))
			{
				int extra = 1 | (ranrot_rand() & 15);
//				[mother setBounty: [mother legalStatus] + extra withReason:kOOLegalStatusReasonAssistingOffender];
				[self markAsOffender:extra withReason:kOOLegalStatusReasonAssistingOffender];
				//				bounty += extra;	// obviously we're dodgier than we thought!
			}
			
			[self setOwner:mother];
			[self setGroup:[mother escortGroup]];
			[shipAI message:@"ESCORTING"];
			return;
		}
		
#ifndef NDEBUG
		if (reportAIMessages)
		{
			OOLog(@"ai.suggestEscort.refused", @"DEBUG: %@ refused by %@", self, mother);
		}
#endif
		
	}
	[self setOwner:self];
	[shipAI message:@"NOT_ESCORTING"];
}


- (void) escortCheckMother
{
	ShipEntity   *mother = [self owner];
	
	if ([mother acceptAsEscort:self])
	{
		[self setOwner:mother];
		[self setGroup:[mother escortGroup]];
		[shipAI message:@"ESCORTING"];
	}
	else
	{
		[self setOwner:self];
		if ([self group] == [mother escortGroup])  [self setGroup:nil];
		[shipAI message:@"NOT_ESCORTING"];
	}
}


- (void) performEscort
{
	if(behaviour != BEHAVIOUR_FORMATION_FORM_UP) 
	{
		behaviour = BEHAVIOUR_FORMATION_FORM_UP;
		frustration = 0.0; // behavior changed, reset frustration.
	}
}


- (void) checkGroupOddsVersusTarget
{
	NSUInteger ownGroupCount = [[self group] count] + (ranrot_rand() & 3);			// add a random fudge factor
	NSUInteger targetGroupCount = [[[self primaryTarget] group] count] + (ranrot_rand() & 3);	// add a random fudge factor
	
	if (ownGroupCount == targetGroupCount)
	{
		[shipAI message:@"ODDS_LEVEL"];
	}
	else if (ownGroupCount > targetGroupCount)
	{
		[shipAI message:@"ODDS_GOOD"];
	}
	else
	{
		[shipAI message:@"ODDS_BAD"];
	}
}


- (void) groupAttackTarget
{
	NSEnumerator		*shipEnum = nil;
	ShipEntity			*target = nil, *ship = nil;
	
	if ([self primaryTarget] == nil) return;
	
	if ([self group] == nil)		// ship is alone!
	{
		[self setFoundTarget:[self primaryTarget]];
		[shipAI reactToMessage:@"GROUP_ATTACK_TARGET" context:@"groupAttackTarget"];
		return;
	}
	
	target = [self primaryTarget];
	
	// -memberArray creates a new collection, which is needed because the group might be mutated by the members' AIs.
	NSArray *groupMembers = [[self group] memberArray];
	for (shipEnum = [groupMembers objectEnumerator]; (ship = [shipEnum nextObject]); )
	{
		[ship setFoundTarget:target];
		[ship reactToAIMessage:@"GROUP_ATTACK_TARGET" context:@"groupAttackTarget"];
		if ([ship escortGroup] != [ship group] && [[ship escortGroup] count] > 1) // Ship has a seperate escort group.
		{
			ShipEntity		*escort = nil;
			NSEnumerator	*shipEnum = nil;
			NSArray			*escortMembers = [[ship escortGroup] memberArrayExcludingLeader];
			for (shipEnum = [escortMembers objectEnumerator]; (escort = [shipEnum nextObject]); )
			{
				[escort setFoundTarget:target];
				[escort reactToAIMessage:@"GROUP_ATTACK_TARGET" context:@"groupAttackTarget"];
			}
		}
	}
}


- (void) scanForFormationLeader
{
	//-- Locates the nearest suitable formation leader in range --//
	DESTROY(_foundTarget);
	[self checkScanner];
	unsigned i;
	GLfloat	found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships; i++)
	{
		ShipEntity *ship = scanned_ships[i];
		if ((ship != self) && (!ship->isPlayer) && (ship->scanClass == scanClass) && [ship primaryTarget] != self && ![ship isCloaked])	// look for alike
		{
			GLfloat d2 = distance2_scanned_ships[i];
			if ((d2 < found_d2) && [ship canAcceptEscort:self])
			{
				found_d2 = d2;
				[self setFoundTarget:ship];
			}
		}
	}
	
	if ([self foundTarget] != nil)  [shipAI message:@"TARGET_FOUND"];
	else
	{
		[shipAI message:@"NOTHING_FOUND"];
		if ([self hasPrimaryRole:@"wingman"])
		{
			// become free-lance police :)
			[shipAI setStateMachine:@"route1patrolAI.plist"];	// use this to avoid referencing a released AI
			[self setPrimaryRole:@"police"]; // other wingman can now select this ship as leader.
		}
	}
	
}


- (void) messageMother:(NSString *)msgString
{
	ShipEntity *mother = [self owner];
	if (mother != nil && mother != self)
	{
		NSString *context = nil;
#ifndef NDEBUG
		context = [NSString stringWithFormat:@"%@ messageMother", [self shortDescription]];
#endif
		[mother reactToAIMessage:msgString context:context];
	}
}


- (void) messageSelf:(NSString *)msgString
{
	[self sendAIMessage:msgString];
}


- (void) setPlanetPatrolCoordinates
{
	// check we've arrived near the last given coordinates
	Vector r_pos = vector_subtract(position, coordinates);
	if (magnitude2(r_pos) < 1000000 || patrol_counter == 0)
	{
		Entity *the_sun = [UNIVERSE sun];
		ShipEntity *the_station = [[self group] leader];
		if(!the_station || ![the_station isStation]) the_station = [UNIVERSE station];
		if ((!the_sun)||(!the_station))
			return;
		Vector sun_pos = the_sun->position;
		Vector stn_pos = the_station->position;
		Vector sun_dir =  make_vector(sun_pos.x - stn_pos.x, sun_pos.y - stn_pos.y, sun_pos.z - stn_pos.z);
		Vector vSun = make_vector(0, 0, 1);
		if (sun_dir.x||sun_dir.y||sun_dir.z)
			vSun = vector_normal(sun_dir);
		Vector v0 = [the_station forwardVector];
		Vector v1 = cross_product(v0, vSun);
		Vector v2 = cross_product(v0, v1);
		switch (patrol_counter)
		{
			case 0:		// first go to 5km ahead of the station
				coordinates = make_vector(stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
				desired_range = 250.0;
				break;
			case 1:		// go to 25km N of the station
				coordinates = make_vector(stn_pos.x + 25000 * v1.x, stn_pos.y + 25000 * v1.y, stn_pos.z + 25000 * v1.z);
				desired_range = 250.0;
				break;
			case 2:		// go to 25km E of the station
				coordinates = make_vector(stn_pos.x + 25000 * v2.x, stn_pos.y + 25000 * v2.y, stn_pos.z + 25000 * v2.z);
				desired_range = 250.0;
				break;
			case 3:		// go to 25km S of the station
				coordinates = make_vector(stn_pos.x - 25000 * v1.x, stn_pos.y - 25000 * v1.y, stn_pos.z - 25000 * v1.z);
				desired_range = 250.0;
				break;
			case 4:		// go to 25km W of the station
				coordinates = make_vector(stn_pos.x - 25000 * v2.x, stn_pos.y - 25000 * v2.y, stn_pos.z - 25000 * v2.z);
				desired_range = 250.0;
				break;
			default:	// We should never come here
				coordinates = make_vector(stn_pos.x + 5000 * v0.x, stn_pos.y + 5000 * v0.y, stn_pos.z + 5000 * v0.z);
				desired_range = 250.0;
				break;
		}
		patrol_counter++;
		if (patrol_counter > 4)
		{
			if (randf() < .25)
			{
				// consider docking
				[self setTargetStation:the_station];
				[self setAITo:@"dockingAI.plist"];
				return;
			}
			else
			{
				// go around again
				patrol_counter = 1;
			}
		}
	}
	[shipAI message:@"APPROACH_COORDINATES"];
}


- (void) setSunSkimStartCoordinates
{
	if ([UNIVERSE sun] == nil)
	{
		[shipAI message:@"NO_SUN_FOUND"];
		return;
	}
	
	Vector v0 = [UNIVERSE getSunSkimStartPositionForShip:self];
	
	if (!vector_equal(v0, kZeroVector))
	{
		coordinates = v0;
		[shipAI message:@"APPROACH_COORDINATES"];
	}
	else
	{
		[shipAI message:@"WAIT_FOR_SUN"];
	}
}


- (void) setSunSkimEndCoordinates
{
	if ([UNIVERSE sun] == nil)
	{
		[shipAI message:@"NO_SUN_FOUND"];
		return;
	}
	
	coordinates = [UNIVERSE getSunSkimEndPositionForShip:self];
	[shipAI message:@"APPROACH_COORDINATES"];
}


- (void) setSunSkimExitCoordinates
{
	Entity *the_sun = [UNIVERSE sun];
	if (the_sun == nil)  return;
	Vector v1 = [UNIVERSE getSunSkimEndPositionForShip:self];
	Vector vs = the_sun->position;
	Vector vout = make_vector(v1.x - vs.x, v1.y - vs.y, v1.z - vs.z);
	if (vout.x||vout.y||vout.z)
		vout = vector_normal(vout);
	else
		vout.z = 1.0;
	v1.x += 10000 * vout.x;	v1.y += 10000 * vout.y;	v1.z += 10000 * vout.z;
	coordinates = v1;
	[shipAI message:@"APPROACH_COORDINATES"];
}


- (void) patrolReportIn
{
	// Set a report time in the patrolled station to delay a new launch.
	ShipEntity *the_station = [[self group] leader];
	if(!the_station || ![the_station isStation]) the_station = [UNIVERSE station];
	[(StationEntity*)the_station acceptPatrolReportFrom:self];
}


- (void) checkForMotherStation
{
	ShipEntity *motherStation = [[self group] leader];
	if ((!motherStation) || (!(motherStation->isStation)))
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	Vector v0 = motherStation->position;
	Vector rpos = make_vector(position.x - v0.x, position.y - v0.y, position.z - v0.z);
	double found_d2 = scannerRange * scannerRange;
	if (magnitude2(rpos) > found_d2)
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	[shipAI message:@"STATION_FOUND"];		
}


- (void) sendTargetCommsMessage:(NSString*) message
{
	ShipEntity *ship = [self primaryTarget];
	if ((ship == nil) || ([ship status] == STATUS_DEAD) || ([ship status] == STATUS_DOCKED))
	{
		[self noteLostTarget];
		return;
	}
	[self sendExpandedMessage:message toShip:[self primaryTarget]];
}


- (void) markTargetForFines
{
	ShipEntity *ship = [self primaryTarget];
	if ((ship == nil) || ([ship status] == STATUS_DEAD) || ([ship status] == STATUS_DOCKED))
	{
		[self noteLostTarget];
		return;
	}
	if ([ship markForFines])  [shipAI message:@"TARGET_MARKED"];
}


- (void) markTargetForOffence:(NSString*) valueString
{
	if ((isStation)||(scanClass == CLASS_POLICE))
	{
		ShipEntity *ship = [self primaryTarget];
		if ((ship == nil) || ([ship status] == STATUS_DEAD) || ([ship status] == STATUS_DOCKED))
		{
			[self noteLostTarget];
			return;
		}
		NSString* finalValue = ExpandDescriptionForCurrentSystem(valueString);	// expand values
		[ship markAsOffender:[finalValue intValue] withReason:kOOLegalStatusReasonSeenByPolice];
	}
}


- (void) storeTarget
{
	Entity	*target = [self primaryTarget];
	
	if (target)
	{
		[self setRememberedShip:target];
	}
	else
	{
		DESTROY(_rememberedShip);
	}
	
}

- (void) recallStoredTarget
{
	ShipEntity	*oldTarget = (ShipEntity*)[self rememberedShip];
	BOOL	found = NO;
	
	if (oldTarget && ![oldTarget isCloaked])
	{
		GLfloat range2 = distance2([oldTarget position], position);
		if (range2 <= scannerRange * scannerRange && range2 <= SCANNER_MAX_RANGE2)
		{
			found = YES;
		}
	}
	
	if (found)
	{
		[self setFoundTarget:oldTarget];
		[shipAI message:@"TARGET_FOUND"];
	}
	else
	{
		if (oldTarget == nil) DESTROY(_rememberedShip); // ship no longer exists
		[shipAI message:@"NOTHING_FOUND"];
	}
	
}

- (void) scanForRocks
{
	/*-- Locates the all boulders and asteroids in range and selects nearest --*/
	
	// find boulders then asteroids within range
	//
	DESTROY(_foundTarget);
	[self checkScanner];
	unsigned i;
	GLfloat found_d2 = scannerRange * scannerRange;
	for (i = 0; i < n_scanned_ships; i++)
	{
		ShipEntity *thing = scanned_ships[i];
		if ([thing isBoulder])
		{
			GLfloat d2 = distance2_scanned_ships[i];
			if (d2 < found_d2)
			{
				[self setFoundTarget:thing];
				found_d2 = d2;
			}
		}
	}
	if ([self foundTarget] == nil)
	{
		for (i = 0; i < n_scanned_ships; i++)
		{
			ShipEntity *thing = scanned_ships[i];
			if ([thing hasRole:@"asteroid"])
			{
				GLfloat d2 = distance2_scanned_ships[i];
				if (d2 < found_d2)
				{
					[self setFoundTarget:thing];
					found_d2 = d2;
				}
			}
		}
	}
	
	[self checkFoundTarget];
}


- (void) performMining
{
	Entity *target = [self primaryTarget];
	// mining is not seen as hostile behaviour, so ensure it is only used against rocks.
	if (target &&  [target scanClass] == CLASS_ROCK)
	{
		behaviour = BEHAVIOUR_ATTACK_MINING_TARGET;
		frustration = 0.0;
	}
	else
	{	
		[self noteLostTargetAndGoIdle];
	}
}


- (void) setDestinationToDockingAbort
{
	Entity *the_target = [self primaryTarget];
	double bo_distance = 8000; //	8km back off
	Vector v0 = position;
	Vector d0 = (the_target) ? the_target->position : kZeroVector;
	v0.x += (randf() - 0.5)*collision_radius;	v0.y += (randf() - 0.5)*collision_radius;	v0.z += (randf() - 0.5)*collision_radius;
	v0.x -= d0.x;	v0.y -= d0.y;	v0.z -= d0.z;
	v0 = vector_normal_or_fallback(v0, make_vector(0, 0, -1));
	
	v0.x *= bo_distance;	v0.y *= bo_distance;	v0.z *= bo_distance;
	v0.x += d0.x;	v0.y += d0.y;	v0.z += d0.z;
	coordinates = v0;
	destination = v0;
}


- (void) requestNewTarget
{
	ShipEntity *mother = [[self group] leader];
	if (mother == nil)
	{
		[shipAI message:@"MOTHER_LOST"];
		return;
	}
	
	/*-- Locates all the ships in range targeting the mother ship and chooses the nearest/biggest --*/
	DESTROY(_foundTarget);
	[self checkScanner];
	unsigned i;
	GLfloat found_d2 = scannerRange * scannerRange;
	GLfloat max_e = 0;
	for (i = 0; i < n_scanned_ships ; i++)
	{
		ShipEntity *thing = scanned_ships[i];
		GLfloat d2 = distance2_scanned_ships[i];
		GLfloat e1 = [thing energy];
		if ((d2 < found_d2) && ![thing isCloaked] && (([thing isThargoid] && ![mother isThargoid]) || (([thing primaryTarget] == mother) && [thing hasHostileTarget])))
		{
			if (e1 > max_e)
			{
				[self setFoundTarget:thing];
				max_e = e1;
			}
		}
	}
	
	[self checkFoundTarget];
}


- (void) rollD:(NSString*) die_number
{
	int die_sides = [die_number intValue];
	if (die_sides > 0)
	{
		int die_roll = 1 + (ranrot_rand() % die_sides);
		NSString* result = [NSString stringWithFormat:@"ROLL_%d", die_roll];
		[shipAI reactToMessage:result context:@"rollD:"];
	}
	else
	{
		OOLog(@"ai.rollD.invalidValue", @"***** ERROR: invalid value supplied to rollD: '%@'.", die_number);
	}
}


- (void) scanForNearestShipWithPrimaryRole:(NSString *)scanRole
{
	[self scanForNearestShipWithPredicate:HasPrimaryRolePredicate parameter:scanRole];
}


- (void) scanForNearestShipHavingRole:(NSString *)scanRole
{
	[self scanForNearestShipWithPredicate:HasRolePredicate parameter:scanRole];
}


- (void) scanForNearestShipWithAnyPrimaryRole:(NSString *)scanRoles
{
	NSSet *set = [NSSet setWithArray:ScanTokensFromString(scanRoles)];
	[self scanForNearestShipWithPredicate:HasPrimaryRoleInSetPredicate parameter:set];
}


- (void) scanForNearestShipHavingAnyRole:(NSString *)scanRoles
{
	NSSet *set = [NSSet setWithArray:ScanTokensFromString(scanRoles)];
	[self scanForNearestShipWithPredicate:HasRoleInSetPredicate parameter:set];
}


- (void) scanForNearestShipWithScanClass:(NSString *)scanScanClass
{
	NSNumber *parameter = [NSNumber numberWithInt:OOScanClassFromString(scanScanClass)];
	[self scanForNearestShipWithPredicate:HasScanClassPredicate parameter:parameter];
}


- (void) scanForNearestShipWithoutPrimaryRole:(NSString *)scanRole
{
	[self scanForNearestShipWithNegatedPredicate:HasPrimaryRolePredicate parameter:scanRole];
}


- (void) scanForNearestShipNotHavingRole:(NSString *)scanRole
{
	[self scanForNearestShipWithNegatedPredicate:HasRolePredicate parameter:scanRole];
}


- (void) scanForNearestShipWithoutAnyPrimaryRole:(NSString *)scanRoles
{
	NSSet *set = [NSSet setWithArray:ScanTokensFromString(scanRoles)];
	[self scanForNearestShipWithNegatedPredicate:HasPrimaryRoleInSetPredicate parameter:set];
}


- (void) scanForNearestShipNotHavingAnyRole:(NSString *)scanRoles
{
	NSSet *set = [NSSet setWithArray:ScanTokensFromString(scanRoles)];
	[self scanForNearestShipWithNegatedPredicate:HasRoleInSetPredicate parameter:set];
}


- (void) scanForNearestShipWithoutScanClass:(NSString *)scanScanClass
{
	NSNumber *parameter = [NSNumber numberWithInt:OOScanClassFromString(scanScanClass)];
	[self scanForNearestShipWithNegatedPredicate:HasScanClassPredicate parameter:parameter];
}


- (void) scanForNearestShipMatchingPredicate:(NSString *)predicateExpression
{
	/*	Takes a boolean-valued JS expression where "ship" is the ship being
	 evaluated and "this" is our ship's ship script. the expression is
	 turned into a JS function of the form:
	 
	 function _oo_AIScanPredicate(ship)
	 {
	 return $expression;
	 }
	 
	 Examples of expressions:
	 ship.isWeapon
	 this.someComplicatedPredicate(ship)
	 function (ship) { ...do something complicated... } ()
	 */
	
	static NSMutableDictionary	*scriptCache = nil;
	NSString					*aiName = nil;
	NSString					*key = nil;
	OOJSFunction				*function = nil;
	JSContext					*context = NULL;
	
	context = OOJSAcquireContext();
	
	if (predicateExpression == nil)  predicateExpression = @"false";
	
	aiName = [[self getAI] name];
#ifndef NDEBUG
	/*	In debug/test release builds, scripts are cached per AI in order to be
	 able to report errors correctly. For end-user releases, we only cache
	 one copy of each predicate, potentially leading to error messages for
	 the wrong AI.
	 */
	key = [NSString stringWithFormat:@"%@\n%@", aiName, predicateExpression];
#else
	key = predicateExpression;
#endif
	
	// Look for cached function
	function = [scriptCache objectForKey:key];
	if (function == nil)
	{
		NSString					*predicateCode = nil;
		const char					*argNames[] = { "ship" };
		
		// Stuff expression in a function.
		predicateCode = [NSString stringWithFormat:@"return %@;", predicateExpression];
		function = [[OOJSFunction alloc] initWithName:@"_oo_AIScanPredicate"
												scope:NULL
												 code:predicateCode
										argumentCount:1
										argumentNames:argNames
											 fileName:aiName
										   lineNumber:0
											  context:context];
		[function autorelease];
		
		// Cache function.
		if (function != nil)
		{
			if (scriptCache == nil)  scriptCache = [[NSMutableDictionary alloc] init];
			[scriptCache setObject:function forKey:key];
		}
	}
	
	if (function != nil)
	{
		JSFunctionPredicateParameter param =
		{
			.context = context,
			.function = [function functionValue],
			.jsThis = OOJSObjectFromNativeObject(context, self)
		};
		[self scanForNearestShipWithPredicate:JSFunctionPredicate parameter:&param];
	}
	else
	{
		// Report error (once per occurrence)
		static NSMutableSet			*errorCache = nil;
		
		if (![errorCache containsObject:key])
		{
			OOLog(@"ai.scanForNearestShipMatchingPredicate.compile.failed", @"Could not compile JavaScript predicate \"%@\" for AI %@.", predicateExpression, [[self getAI] name]);
			if (errorCache == nil)  errorCache = [[NSMutableSet alloc] init];
			[errorCache addObject:key];
		}
		
		// Select nothing
		DESTROY(_foundTarget);
		[[self getAI] message:@"NOTHING_FOUND"];
	}
	
	JS_ReportPendingException(context);
	OOJSRelinquishContext(context);
}


- (void) setCoordinates:(NSString *)system_x_y_z
{
	NSArray*	tokens = ScanTokensFromString(system_x_y_z);
	NSString*	systemString = nil;
	NSString*	xString = nil;
	NSString*	yString = nil;
	NSString*	zString = nil;
	
	if ([tokens count] != 4)
	{
		OOLog(@"ai.syntax.setCoordinates", @"***** ERROR: cannot setCoordinates: '%@'.",system_x_y_z);
		return;
	}
	
	systemString = (NSString *)[tokens objectAtIndex:0];
	xString = (NSString *)[tokens objectAtIndex:1];
	if ([xString hasPrefix:@"rand:"])
		xString = [NSString stringWithFormat:@"%.3f", bellf([(NSString*)[[xString componentsSeparatedByString:@":"] objectAtIndex:1] intValue])];
	yString = (NSString *)[tokens objectAtIndex:2];
	if ([yString hasPrefix:@"rand:"])
		yString = [NSString stringWithFormat:@"%.3f", bellf([(NSString*)[[yString componentsSeparatedByString:@":"] objectAtIndex:1] intValue])];
	zString = (NSString *)[tokens objectAtIndex:3];
	if ([zString hasPrefix:@"rand:"])
		zString = [NSString stringWithFormat:@"%.3f", bellf([(NSString*)[[zString componentsSeparatedByString:@":"] objectAtIndex:1] intValue])];
	
	Vector posn = make_vector([xString floatValue], [yString floatValue], [zString floatValue]);
	GLfloat	scalar = 1.0;
	
	coordinates = [UNIVERSE coordinatesForPosition:posn withCoordinateSystem:systemString returningScalar:&scalar];
	
	[shipAI message:@"APPROACH_COORDINATES"];
}


- (void) checkForNormalSpace
{
	if ([UNIVERSE sun] && [UNIVERSE planet])
		[shipAI message:@"NORMAL_SPACE"];
	else
		[shipAI message:@"INTERSTELLAR_SPACE"];
}


- (void) setTargetToRandomStation
{
	/*- selects the nearest station it can find -*/
	int				ent_count = UNIVERSE->n_entities;
	Entity			**uni_entities = UNIVERSE->sortedEntities;	// grab the public sorted list
	Entity			*my_entities[ent_count];
	StationEntity	*station = nil, *my_station = nil;
	double			maxRange2 = desired_range * desired_range;
	int				i;
	int				station_count = 0;
	
	for (i = 0; i < ent_count; i++)
	{
		// find stations within range but exclude carriers.
		if (uni_entities[i]->isStation)
		{
			my_station = (StationEntity*)uni_entities[i];
			if ([my_station maxFlightSpeed] == 0 && [my_station hasNPCTraffic] && distance2(position, [my_station position]) < maxRange2)
			{
				my_entities[station_count++] = [uni_entities[i] retain];		//	retained
			}
		}
	}
	
	if (station_count != 0)
	{
		// select a random station
		station = (StationEntity *)my_entities[ranrot_rand() % station_count];
		// if more than one candidate do not select main station
		if (station == [UNIVERSE station] && station_count > 1)
		{
			while (station == [UNIVERSE station])
			{
				station = (StationEntity *)my_entities[ranrot_rand() % station_count];
			}
		}
	}
	
	for (i = 0; i < station_count; i++)
		[my_entities[i] release];		//	released
	//
	if (station)
	{
		[self addTarget:station];
		[self setTargetStation:station];
		[shipAI message:@"STATION_FOUND"];
	}
	else
	{
		[shipAI message:@"NO_STATION_IN_RANGE"];
	}
}

- (void) setTargetToLastStation
{
	Entity	*station = [self targetStation];
	
	if (station != nil && [station isStation])
	{
		[self addTarget:station];
	}
	else
	{
		[shipAI message:@"NO_STATION_FOUND"];
		[self setTargetStation:nil];
	}
	
}

- (void) requestDockingCoordinates
{
	/*-	requests coordinates from the target station
	 if the target station can't be found
	 then use the nearest it can find (which may be a rock hermit) -*/
	
	StationEntity	*station =  nil;
	Entity			*targStation = nil;
	NSString		*message = nil;
	double		distanceToStation2 = 0.0;
	
	targStation = [self targetStation];
	if ([targStation isStation])
	{
		station = (StationEntity*)targStation;
	}
	else
	{
		station = [UNIVERSE nearestShipMatchingPredicate:IsStationPredicate
											   parameter:nil
										relativeToEntity:self];
	}
	
	distanceToStation2 = distance2([station position], [self position]);
	
	// Player check for being inside the aegis already exists in PlayerEntityControls. We just
	// check here that distance to station is less than 2.5 times scanner range to avoid problems with
	// NPC ships getting stuck with a dockingAI while just outside the aegis - Nikos 20090630, as proposed by Eric
	// On very busy systems (> 50 docking ships) docking ships can be sent to a hold position outside the range, 
	// so also test for presence of dockingInstructions. - Eric 20091130
	if (station != nil && (distanceToStation2 < SCANNER_MAX_RANGE2 * 6.25 || dockingInstructions != nil))
	{
		// remember the instructions
		[dockingInstructions release];
		dockingInstructions = [[station dockingInstructionsForShip:self] retain];
		if (dockingInstructions != nil)
		{
			[self recallDockingInstructions];
			
			message = [dockingInstructions objectForKey:@"ai_message"];
			if (message != nil)  [shipAI message:message];
			message = [dockingInstructions objectForKey:@"comms_message"];
			if (message != nil)  [station sendExpandedMessage:message toShip:self];
		}
		
	}
	else
	{
		DESTROY(dockingInstructions);
	}
	
	if (dockingInstructions == nil)
	{
		[shipAI message:@"NO_STATION_FOUND"];
	}
}


- (void) recallDockingInstructions
{
	if (dockingInstructions != nil)
	{
		destination = [dockingInstructions oo_vectorForKey:@"destination"];
		desired_speed = fmin([dockingInstructions oo_floatForKey:@"speed"], maxFlightSpeed);
		desired_range = [dockingInstructions oo_floatForKey:@"range"];
		if ([dockingInstructions objectForKey:@"station"])
		{
			StationEntity *targetStation = [[dockingInstructions objectForKey:@"station"] weakRefUnderlyingObject];
			if (targetStation != nil)
			{
				[self addTarget:targetStation];
				[self setTargetStation:targetStation];
			}
			else 
			{
				[self removeTarget:[self primaryTarget]];
			}
		}
		docking_match_rotation = [dockingInstructions oo_boolForKey:@"match_rotation"];
	}
}


- (void) addFuel:(NSString*) fuel_number
{
	[self setFuel:[self fuel] + [fuel_number intValue] * 10];
}


- (void) enterPlayerWormhole
{
	[self enterWormhole:[PLAYER wormhole] replacing:NO];
}


- (void) scriptActionOnTarget:(NSString *)action
{
	PlayerEntity	*player = PLAYER;
	ShipEntity		*targEnt = [self primaryTarget];
	ShipEntity		*oldTarget = nil;
	
#ifndef NDEBUG
	static BOOL		deprecationWarning = NO;
	
	if (!deprecationWarning)
	{
		deprecationWarning = YES;
		OOLog(@"script.deprecated.scriptActionOnTarget", @"----- WARNING in AI %@: the AI method scriptActionOnTarget: is deprecated and should not be used. It is slow and has unpredictable side effects. The recommended alternative is to use sendScriptMessage: to call a function in a ship's JavaScript ship script instead. scriptActionOnTarget: should not be used at all from scripts. An alternative is safeScriptActionOnTarget:, which is similar to scriptActionOnTarget: but has less side effects.", [AI currentlyRunningAIDescription]);
	}
	else
	{
		OOLog(@"script.deprecated.scriptActionOnTarget.repeat", @"----- WARNING in AI %@: the AI method scriptActionOnTarget: is deprecated and should not be used.", [AI currentlyRunningAIDescription]);
	}
#endif
	
	if ([targEnt isShip])
	{
		oldTarget = [player scriptTarget];
		[player setScriptTarget:(ShipEntity*)targEnt];
		[player runUnsanitizedScriptActions:[NSArray arrayWithObject:action]
						  allowingAIMethods:YES
							withContextName:[NSString stringWithFormat:@"<AI \"%@\" state %@ - scriptActionOnTarget:>", [[self getAI] name], [[self getAI] state]]
								  forTarget:targEnt];
		[player checkScript];	// react immediately to any changes this makes
		[player setScriptTarget:oldTarget];
	}
}


- (void) safeScriptActionOnTarget:(NSString *)action
{
	PlayerEntity	*player = PLAYER;
	ShipEntity		*targEnt = [self primaryTarget];
	ShipEntity		*oldTarget = nil;
	
	if ([targEnt isShip])
	{
		oldTarget = [player scriptTarget];
		[player setScriptTarget:(ShipEntity*)targEnt];
		[player runUnsanitizedScriptActions:[NSArray arrayWithObject:action]
						  allowingAIMethods:YES
							withContextName:[NSString stringWithFormat:@"<AI \"%@\" state %@ - safeScriptActionOnTarget:>", [[self getAI] name], [[self getAI] state]]
								  forTarget:targEnt];
		[player setScriptTarget:oldTarget];
	}
}


// Send own ship script a message.
- (void) sendScriptMessage:(NSString *)message
{
	NSArray *components = ScanTokensFromString(message);
	
	if ([components count] == 1)
	{
		[self doScriptEvent:OOJSIDFromString(message)];
	}
	else
	{
		NSString *function = [components objectAtIndex:0];
		components = [components subarrayWithRange:NSMakeRange(1, [components count] - 1)];
		[self doScriptEvent:OOJSIDFromString(function) withArgument:components];
	}
}


- (void) ai_throwSparks
{
	[self setThrowSparks:YES];
}


- (void) explodeSelf
{
	[self getDestroyedBy:nil damageType:kOODamageTypeEnergy];
}


- (void) ai_debugMessage:(NSString *)message
{
	NSString *desc = [NSString stringWithFormat:@"%@ %d", [self name], [self universalID]];
	if ([self isPlayer])  desc = @"player autopilot";
	OOLog(@"ai.takeAction.debugMessage", @"DEBUG: AI MESSAGE from %@: %@", desc, message);
}



// racing code TODO
- (void) targetFirstBeaconWithCode:(NSString*) code
{
	NSArray			*all_beacons = [UNIVERSE listBeaconsWithCode: code];
	if ([all_beacons count])
	{
		[self addTarget:(ShipEntity*)[all_beacons objectAtIndex:0]];
		[shipAI message:@"TARGET_FOUND"];
	}
	else
		[shipAI message:@"NOTHING_FOUND"];
}


- (void) targetNextBeaconWithCode:(NSString*) code
{
	NSArray			*all_beacons = [UNIVERSE listBeaconsWithCode: code];
	ShipEntity		*current_beacon = [self primaryTarget];
	
	if ((!current_beacon)||(![current_beacon isBeacon]))
	{
		[shipAI message:@"NO_CURRENT_BEACON"];
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	
	// find the current beacon in the list..
	NSUInteger i = [all_beacons indexOfObject:current_beacon];
	
	if (i == NSNotFound)
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	
	i++;	// next index
	
	if (i < [all_beacons count])
	{
		// locate current target in list
		[self addTarget:(ShipEntity*)[all_beacons objectAtIndex:i]];
		[shipAI message:@"TARGET_FOUND"];
	}
	else
	{
		[shipAI message:@"LAST_BEACON"];
		[shipAI message:@"NOTHING_FOUND"];
	}
}


- (void) setRacepointsFromTarget
{
	// two point - one at z - cr one at z + cr
	ShipEntity *ship = [self primaryTarget];
	if (ship == nil)
	{
		[shipAI message:@"NOTHING_FOUND"];
		return;
	}
	Vector k = ship->v_forward;
	GLfloat c = ship->collision_radius;
	Vector o = ship->position;
	navpoints[0] = make_vector(o.x - c * k.x, o.y - c * k.y, o.z - c * k.z);
	navpoints[1] = make_vector(o.x + c * k.x, o.y + c * k.y, o.z + c * k.z);
	navpoints[2] = make_vector(o.x + 2.0 * c * k.x, o.y + 2.0 * c * k.y, o.z + 2.0 * c * k.z);
	number_of_navpoints = 2;
	next_navpoint_index = 0;
	destination = navpoints[0];
	[shipAI message:@"RACEPOINTS_SET"];
}


- (void) performFlyRacepoints
{
	next_navpoint_index = 0;
	desired_range = collision_radius;
	behaviour = BEHAVIOUR_FLY_THRU_NAVPOINTS;
}

@end


@implementation ShipEntity (OOAIPrivate)

- (void) checkFoundTarget
{
	if ([self foundTarget] != nil) 
	{
		[shipAI message:@"TARGET_FOUND"];
	}
	else
	{
		[shipAI message:@"NOTHING_FOUND"];
	}
}


- (BOOL) performHyperSpaceExitReplace:(BOOL)replace
{
	return [self performHyperSpaceExitReplace:replace toSystem:-1];
}


- (BOOL) performHyperSpaceExitReplace:(BOOL)replace toSystem:(OOSystemID)systemID
{
	if(![self hasHyperspaceMotor])
	{
		[shipAI reactToMessage:@"WITCHSPACE UNAVAILABLE" context:@"performHyperSpaceExit"];
		return NO;
	}
	if([self status] == STATUS_ENTERING_WITCHSPACE)
	{
// already in a wormhole
		return NO;
	}
	
	NSArray			*sDests = nil;
	Random_Seed		targetSystem;
	NSUInteger		i = 0;
	
	// get a list of destinations within range
	sDests = [UNIVERSE nearbyDestinationsWithinRange: 0.1f * fuel];
	NSUInteger n_dests = [sDests count];
	
	// if none available report to the AI and exit
	if (n_dests == 0)
	{
		[shipAI reactToMessage:@"WITCHSPACE UNAVAILABLE" context:@"performHyperSpaceExit"];
		
		// If no systems exist near us, the AI is switched to a different state, so we do not need
		// the nearby destinations array anymore.
		return NO;
	}
	
	// check if we're clear of nearby masses
	ShipEntity *blocker = [UNIVERSE entityForUniversalID:[self checkShipsInVicinityForWitchJumpExit]];
	if (blocker)
	{
		[self setFoundTarget:blocker];
		[shipAI reactToMessage:@"WITCHSPACE BLOCKED" context:@"performHyperSpaceExit"];
		return NO;
	}
	
	if (systemID == -1)
	{
		// select one at random
		if (n_dests > 1)
		{
			i = ranrot_rand() % n_dests;
		}
		
		NSString *systemSeedKey = [[sDests oo_dictionaryAtIndex:i] objectForKey:@"system_seed"];
		targetSystem = RandomSeedFromString(systemSeedKey);
	}
	else
	{
		targetSystem = [UNIVERSE systemSeedForSystemNumber:systemID];
		
		for (i = 0; i < n_dests; i++)
		{
			if (systemID == [[sDests oo_dictionaryAtIndex:i] oo_intForKey:@"sysID"]) break;
		}
		
		if (i == n_dests)	// no match found
		{
			return NO;
		}
	}
	float dist = [[sDests oo_dictionaryAtIndex:i] oo_floatForKey:@"distance"];
	if (dist > [self maxHyperspaceDistance] || dist > fuel/10) 
	{
		OOLogWARN(@"script.debug", @"DEBUG: %@ Jumping %f which is further than allowed.  I have %d fuel", self, dist, fuel);
	}
	fuel -= 10 * dist;
	
	// create wormhole
	WormholeEntity  *whole = [[[WormholeEntity alloc] initWormholeTo: targetSystem fromShip:self] autorelease];
	[UNIVERSE addEntity: whole];
	
	[self enterWormhole:whole replacing:replace];
	
	// we've no need for the destinations array anymore.
	return YES;
}


- (void) scanForNearestShipWithPredicate:(EntityFilterPredicate)predicate parameter:(void *)parameter
{
	// Locates all the ships in range for which predicate returns YES, and chooses the nearest.
	unsigned		i;
	ShipEntity		*candidate;
	float			d2, found_d2 = scannerRange * scannerRange;
	
	DESTROY(_foundTarget);
	[self checkScanner];
	
	if (predicate == NULL)  return;
	
	for (i = 0; i < n_scanned_ships ; i++)
	{
		candidate = scanned_ships[i];
		d2 = distance2_scanned_ships[i];
		if ((d2 < found_d2) && (candidate->scanClass != CLASS_CARGO) && ([candidate status] != STATUS_DOCKED) 
					&& predicate(candidate, parameter) && ![candidate isCloaked])
		{
			[self setFoundTarget:candidate];
			found_d2 = d2;
		}
	}
	
	[self checkFoundTarget];
}


- (void) scanForNearestShipWithNegatedPredicate:(EntityFilterPredicate)predicate parameter:(void *)parameter
{
	ChainedEntityPredicateParameter param = { predicate, parameter };
	[self scanForNearestShipWithPredicate:NOTPredicate parameter:&param];
}


- (void) acceptDistressMessageFrom:(ShipEntity *)other
{
	[self setFoundTarget:[other primaryTarget]];
	if ([self isPolice])
	{
		[(ShipEntity*)[self foundTarget] markAsOffender:8 withReason:kOOLegalStatusReasonDistressCall];  // you have been warned!!
	}
	
	NSString *context = nil;
#ifndef NDEBUG
	context = [NSString stringWithFormat:@"%@ broadcastDistressMessage", [other shortDescription]];
#endif
	[shipAI reactToMessage:@"ACCEPT_DISTRESS_CALL" context:context];
	
}




@end


@implementation StationEntity (OOAIPrivate)

- (void) acceptDistressMessageFrom:(ShipEntity *)other
{
	if (self != [UNIVERSE station])  return;
	
	OOWeakReference *old_target = _primaryTarget;
	_primaryTarget = [[[other primaryTarget] weakRetain] autorelease];
	[(ShipEntity *)[other primaryTarget] markAsOffender:8 withReason:kOOLegalStatusReasonDistressCall];	// mark their card
	[self launchDefenseShip];
	_primaryTarget = old_target;
	
}

@end


@implementation ShipEntity (OOAIStationStubs)

// AI methods for stations, have no effect on normal ships.

#define STATION_STUB_BASE(PROTO, NAME)  PROTO { OOLog(@"ai.invalid.notAStation", @"Attempt to use station AI method \"%s\" on non-station %@.", NAME, self); }
#define STATION_STUB_NOARG(NAME)	STATION_STUB_BASE(- (void) NAME, #NAME)
#define STATION_STUB_ARG(NAME)		STATION_STUB_BASE(- (void) NAME (NSString *)param, #NAME)

STATION_STUB_NOARG(increaseAlertLevel)
STATION_STUB_NOARG(decreaseAlertLevel)
STATION_STUB_NOARG(launchPolice)
STATION_STUB_NOARG(launchDefenseShip)
STATION_STUB_NOARG(launchScavenger)
STATION_STUB_NOARG(launchMiner)
STATION_STUB_NOARG(launchPirateShip)
STATION_STUB_NOARG(launchShuttle)
STATION_STUB_NOARG(launchTrader)
STATION_STUB_NOARG(launchEscort)
- (BOOL) launchPatrol
{
	OOLog(@"ai.invalid.notAStation", @"Attempt to use station AI method \"%s\" on non-station %@.", "launchPatrol", self);
	return NO;
}
STATION_STUB_ARG(launchShipWithRole:)
STATION_STUB_NOARG(abortAllDockings)

@end

