/*

DockEntity.h

ShipEntity subclass representing a dock.

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
#import "StationEntity.h"	// For MAX_DOCKING_STAGES


@interface DockEntity: ShipEntity
{
@private
	NSMutableDictionary		*shipsOnApproach;
	NSMutableArray			*launchQueue;
	double					last_launch_time;
//	double					approach_spacing; // not needed now holding pattern changed
	
	ShipEntity				*id_lock[MAX_DOCKING_STAGES];	// OOWeakReferences to a ShipEntity
	
	Vector  				port_dimensions;
	double					port_corridor;				// corridor length inside station.
	
	BOOL					no_docking_while_launching;
	BOOL					allow_launching;
	BOOL					allow_docking;
	BOOL					disallowed_docking_collides; 
	BOOL					virtual_dock;
}

- (void) clear;

// Docking
- (BOOL) allowsDocking;
- (void) setAllowsDocking:(BOOL)allow;
- (BOOL) disallowedDockingCollides; 
- (void) setDisallowedDockingCollides:(BOOL)ddc;
- (NSUInteger) countOfShipsInDockingQueue;
/**
 * Guides a ship into the dock. 
 * <h3>Possible results:</h3>
 * <ul>
 * <li>null<br/>
 *     if no result can be computed or the last control point is reached
 * <li>Move to station (APPROACH)<br/>
 *     if ship is too far away
 * <li>Move away from station (BACKOFF)<br/>
 *     if ship is too close
 * <li>Move perpendicular to station/dock direction (APPROACH)<br/>
 *     if ship is approaching from wrong side of station
 * <li>Abort (TRY AGAIN LATER)<br/>
 *     if something went wrong until here
 * <li>Hold position (HOLD_POSITION)<br/>
 *     if coordinatesStack is empty or approach is not clear
 * <li>Move to next control point (APPROACH_COORDINATES)<br/>
 *     if control point not within collision radius
 * </ul>
 *
 * <h3>Algorithm:</h3>
 * <ol>
 * <li>If ship is not on approach list and beyond scanner range (25 km?), approach the station
 * <li>Add ship to approach list
 * <li>If ship is within distance of 1000 km between station's and ship's collision radius, move away from station
 * <li>If ship is approaching from behind, move to the side of the station (perpendicular on direction to station and launch vector)
 * <li>If ship is further away than 12000 km, approach the station
 * </ol>
 * <p>Now the ship is in the vicinity of the station in the correct hemispere. Let's guide them in.</p>
 * <ol>
 * <li>Get the coordinatesStack for this ship (the approach path?). If there is a problem, Ship shall hold position
 * <li>If next coordinates (control point) not yet within collision radius, move towards that position
 * <li>Remove control point from stack; get next control point
 * <li>If next 3 stages of approach are clear, move to next position
 * <li>otherwise hold position
 * </ol>
 * 
 * <p>TODO: Where is the detection that the ship has docked?</p>
 * <p>TODO: What are the magic number's units? Is it km (kilometers)?</p>
 */
- (NSDictionary *) dockingInstructionsForShip:(ShipEntity *)ship;
- (NSString *) canAcceptShipForDocking:(ShipEntity *)ship;
- (BOOL) shipIsInDockingCorridor:(ShipEntity *)ship;
- (BOOL) shipIsInDockingQueue:(ShipEntity *)ship;
- (void) abortDockingForShip:(ShipEntity *)ship;
- (void) abortAllDockings;
- (BOOL) dockingCorridorIsEmpty;
- (void) clearDockingCorridor;
- (void) autoDockShipsOnApproach;
- (NSUInteger) pruneAndCountShipsOnApproach;
- (void) noteDockingForShip:(ShipEntity *)ship;

// Launching
- (BOOL) allowsLaunching;
- (void) setAllowsLaunching:(BOOL)allow;
- (NSUInteger) countOfShipsInLaunchQueue;
- (NSUInteger) countOfShipsInLaunchQueueWithPrimaryRole:(NSString *)role;
- (BOOL) allowsLaunchingOf:(ShipEntity *)ship;
- (void) launchShip:(ShipEntity *)ship;
- (void) addShipToLaunchQueue:(ShipEntity *)ship withPriority:(BOOL)priority;

// Geometry
- (void) setDimensionsAndCorridor:(BOOL)docking :(BOOL)ddc :(BOOL)launching;
- (Vector) portUpVectorForShipsBoundingBox:(BoundingBox)bb;
- (BOOL) isOffCentre;
- (void) setVirtual;

@end
