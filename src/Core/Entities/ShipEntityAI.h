/*

ShipEntityAI.h

Additional methods relating to behaviour/artificial intelligence.


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "ShipEntity.h"

@class AI, Universe, PlanetEntity;

@interface ShipEntity (AI)

/*-----------------------------------------

	methods for AI

-----------------------------------------*/

- (void) pauseAI:(NSString *)intervalString;

- (void) setDestinationToCurrentLocation;

- (void) setDesiredRangeTo:(NSString *)rangeString;

- (void) setSpeedTo:(NSString *)speedString;

- (void) setSpeedFactorTo:(NSString *)speedString;

- (void) performFlyToRangeFromDestination;

- (void) performIdle;

- (void) performStop;

- (void) performHold;

- (void) setTargetToPrimaryAggressor;

- (void) performAttack;

- (void) scanForNearestMerchantmen;
- (void) scanForRandomMerchantmen;

- (void) scanForLoot;

- (void) scanForRandomLoot;

- (void) setTargetToFoundTarget;

- (void) checkForFullHold;

- (void) performCollect;

- (void) performIntercept;

- (void) performFlee;

- (void) requestDockingCoordinates;

- (void) getWitchspaceEntryCoordinates;

- (void) setDestinationFromCoordinates;

- (void) performDocking;

- (void) performFaceDestination;

- (void) performTumble;

- (void) fightOrFleeMissile;

- (PlanetEntity *) findNearestPlanet;

- (void) setCourseToPlanet;

- (void) setTakeOffFromPlanet;

- (void) landOnPlanet;

- (void) setAITo:(NSString *)aiString;
- (void) switchAITo:(NSString *)aiString;

- (void) checkTargetLegalStatus;

- (void) exitAI;

- (void) setDestinationToTarget;
- (void) setDestinationWithinTarget;

- (void) checkCourseToDestination;

- (void) scanForOffenders;

- (void) setCourseToWitchpoint;

- (void) setDestinationToWitchpoint;
- (void) setDestinationToStationBeacon;

- (void) performHyperSpaceExit;
- (void) performHyperSpaceExitWithoutReplacing;
- (void) wormholeEscorts;
- (void) wormholeGroup;
- (void) wormholeEntireGroup;

- (void) commsMessage:(NSString *)valueString;
- (void) broadcastDistressMessage;
- (void) acceptDistressMessageFrom:(ShipEntity *)other;

- (void) ejectCargo;

- (void) scanForThargoid;
- (void) scanForNonThargoid;
- (void) becomeUncontrolledThargon;

- (void) initialiseTurret;

- (void) checkDistanceTravelled;

- (void) scanForHostiles;

- (void) fightOrFleeHostiles;

- (void) suggestEscort;

- (void) escortCheckMother;

- (void) performEscort;

- (int) numberOfShipsInGroup:(int) ship_group_id;

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

- (void) recallDockingInstructions;

- (void) addFuel:(NSString *) fuel_number;

- (void) enterTargetWormhole;

- (void) scriptActionOnTarget:(NSString *) action;

- (void) sendScriptMessage:(NSString *)message;

// racing code.
- (void) targetFirstBeaconWithCode:(NSString *) code;
- (void) targetNextBeaconWithCode:(NSString *) code;
- (void) setRacepointsFromTarget;
- (void) performFlyRacepoints;

/*	Other methods documented for AI use (may not be exhaustive):
	setPrimaryRole:
	dumpCargo
*/

@end
