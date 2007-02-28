/*

WormholeEntity.h

Entity subclass representing a wormhole between systems. (This is -- to use
technical terminology -- the blue blobby thing you see hanging in space. The
purple tunnel is RingEntity.)

For Oolite
Copyright (C) 2005  Giles C Williams

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

#import <Foundation/Foundation.h>

#import "Entity.h"

#define WORMHOLE_EXPIRES_TIMEINTERVAL	900.0
#define WORMHOLE_SHRINK_RATE			4000.0

@class ShipEntity, Universe;

@interface WormholeEntity : Entity {

	double			time_counter, expiry_time;
	
	Random_Seed		destination;
	
	NSMutableArray*	shipsInTransit;
	
	double			witch_mass;
	
}

- (id) initWormholeTo:(Random_Seed) s_seed fromShip:(ShipEntity *) ship;

- (BOOL) suckInShip:(ShipEntity *) ship;
- (void) disgorgeShips;

- (Random_Seed) destination;

void drawWormholeCorona (double inner_radius, double outer_radius, int step, double z_distance, GLfloat* col4v1);

@end
