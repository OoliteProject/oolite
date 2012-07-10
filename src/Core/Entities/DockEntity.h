/*

DockEntity.h

ShipEntity subclass representing a dock entity

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

#import "ShipEntity.h"
#import "StationEntity.h"
#import "Universe.h"
#import "legacy_random.h"


@interface DockEntity: ShipEntity
{
	
	NSMutableDictionary		*shipsOnApproach;
	NSMutableArray			*launchQueue;
	double					last_launch_time;
	double					approach_spacing;
	
	ShipEntity				*id_lock[MAX_DOCKING_STAGES];	// OOWeakReferences to a ShipEntity
	
	Vector  				port_dimensions;
	double					port_corridor;				// corridor length inside station.
	
	unsigned				no_docking_while_launching: 1;

}

- (void) clearIdLocks:(ShipEntity *)ship;
- (void) abortAllDockings;
- (unsigned) sanityCheckShipsOnApproach;
- (void) autoDockShipsOnApproach;
- (void) autoDockShipsInQueue:(NSMutableDictionary *)queue;
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *) ship;
- (NSString*) canAcceptShipForDocking:(ShipEntity *) ship;
- (BOOL) isOffCentre;
- (void) addShipToShipsOnApproach:(ShipEntity *) ship;
- (void) abortDockingForShip:(ShipEntity *) ship;
- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox) bb;
- (void) pullInShipIfPermitted:(ShipEntity *)ship;
- (unsigned) countShipsInLaunchQueueWithPrimaryRole:(NSString *)role;
- (void) launchShip:(ShipEntity *) ship;
- (void) addShipToLaunchQueue:(ShipEntity *) ship :(BOOL) priority;
- (BOOL) fitsInDock:(ShipEntity *) ship;
- (BOOL) dockingCorridorIsEmpty;
- (void) clearDockingCorridor;
- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship;
- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox) bb;
- (void) clear;
- (void) noteDockingForShip:(ShipEntity *) ship;
- (void)setDimensionsAndCorridor;



@end


