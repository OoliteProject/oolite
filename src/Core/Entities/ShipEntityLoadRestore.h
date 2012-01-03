/*

ShipEntityLoadRestore.h

Support for saving and restoring individual non-player ships.


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


@interface ShipEntity (LoadRestore)

/*	Produces a property list representation of a specific ship. Intended for
	use with wormholes, but should probably generalize quite well.
	
	The optional "context" is a mutable dictionary used to synchronise certain
	state when saving multiple ships - currently, groups. It is not a property
	list and does not need to be saved alongside the ships.
*/
- (NSDictionary *) savedShipDictionaryWithContext:(NSMutableDictionary *)context;

/*	Restore a ship from a property list representation generated with
	-savedShipDictionary. If the ship can't be restored and fallback is YES,
	an attempt will be made to generate a new ship with the same primary role.
*/
+ (id) shipRestoredFromDictionary:(NSDictionary *)dictionary useFallback:(BOOL)fallback context:(NSMutableDictionary *)context;

@end
