//
//  ShipEntity (AI).h
//  Oolite
//
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Tue Nov 1 2005.
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
//

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
- (void) wormholeEscorts;
- (void) wormholeGroup;
- (void) wormholeEntireGroup;

- (void) commsMessage:(NSString *)valueString;
- (void) broadcastDistressMessage;
- (void) acceptDistressMessageFrom:(ShipEntity *)other;

- (void) ejectCargo;

- (void) scanForThargoid;
- (void) scanForNonThargoid;

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

- (void) sendTargetCommsMessage:(NSString*) message;

- (void) markTargetForFines;

- (void) scanForRocks;

- (void) performMining;

- (void) setDestinationToDockingAbort;

- (void) requestNewTarget;

- (void) rollD:(NSString*) die_number;

- (void) scanForNearestShipWithRole:(NSString*) scanRole;

- (void) setCoordinates:(NSString *)system_x_y_z;

- (void) checkForNormalSpace;

- (void) recallDockingInstructions;

- (void) addFuel:(NSString*) fuel_number;

- (void) enterTargetWormhole;

- (void) scriptActionOnTarget:(NSString*) action;

@end
