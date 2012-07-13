/*

DockEntity.h

ShipEntity subclass representing a dock.

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
#import "StationEntity.h"	// For MAX_DOCKING_STAGES


@interface DockEntity: ShipEntity
{
@private
	NSMutableDictionary		*shipsOnApproach;
	NSMutableArray			*launchQueue;
	double					last_launch_time;
	double					approach_spacing;
	
	ShipEntity				*id_lock[MAX_DOCKING_STAGES];	// OOWeakReferences to a ShipEntity
	
	Vector  				port_dimensions;
	double					port_corridor;				// corridor length inside station.
	
	BOOL					no_docking_while_launching;
	BOOL					allow_launching;
	BOOL					allow_docking;
	BOOL					allow_player_docking;
	BOOL					virtual_dock;
}

- (void) clear;

// Docking
- (BOOL) allowsDocking;
- (void) setAllowsDocking:(BOOL)allow;
- (BOOL) allowsPlayerDocking;
- (unsigned) countOfShipsInDockingQueue;
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *)ship;
- (NSString *) canAcceptShipForDocking:(ShipEntity *)ship;
- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship;
- (BOOL) shipIsInDockingQueue:(ShipEntity *)ship;
- (void) abortDockingForShip:(ShipEntity *)ship;
- (void) abortAllDockings;
- (BOOL) dockingCorridorIsEmpty;
- (void) clearDockingCorridor;
- (void) autoDockShipsOnApproach;
- (unsigned) sanityCheckShipsOnApproach;
- (void) noteDockingForShip:(ShipEntity *)ship;

// Launching
- (BOOL) allowsLaunching;
- (void) setAllowsLaunching:(BOOL)allow;
- (unsigned) countOfShipsInLaunchQueue;
- (unsigned) countOfShipsInLaunchQueueWithPrimaryRole:(NSString *)role;
- (BOOL) allowsLaunchingOf:(ShipEntity *)ship;
- (void) launchShip:(ShipEntity *)ship;
- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority;

// Geometry
- (void) setDimensionsAndCorridor:(BOOL)docking :(BOOL)playerdocking :(BOOL)launching;
- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox)bb;
- (BOOL) isOffCentre;
- (void) setVirtual;

@end
