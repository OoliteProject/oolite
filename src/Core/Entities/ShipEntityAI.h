/*

ShipEntityAI.h

Additional methods relating to behaviour/artificial intelligence.


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

#import "ShipEntity.h"

@class AI, Universe, OOPlanetEntity;

@interface ShipEntity (AI)

//	AI methods also used in other code.

- (void) setAITo:(NSString *)aiString;
- (void) setAIScript:(NSString *)aiString;
- (void) switchAITo:(NSString *)aiString;

- (void) scanForHostiles;
- (BOOL) performHyperSpaceToSpecificSystem:(OOSystemID)systemID;
- (void) scanForNearestIncomingMissile;

- (void) enterTargetWormhole;
- (void) enterPlayerWormhole;

- (void) wormholeEscorts;

- (BOOL) suggestEscortTo:(ShipEntity *)mother;

- (void) groupAttackTarget;

- (void) performAttack;
- (void) performCollect;
- (void) performEscort;
- (void) performFaceDestination;
- (void) performFlee;
- (void) performFlyToRangeFromDestination;
- (void) performHold;
- (void) performIdle;
- (void) performIntercept;
- (void) performLandOnPlanet;
- (void) performMining;
- (void) performScriptedAI;
- (void) performScriptedAttackAI;
- (void) performStop;
- (void) performTumble;

- (void) broadcastDistressMessage;
- (void) broadcastDistressMessageWithDumping:(BOOL)dumpCargo;

- (void) requestDockingCoordinates;
- (void) recallDockingInstructions;


@end
