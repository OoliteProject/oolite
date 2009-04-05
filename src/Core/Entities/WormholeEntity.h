/*

WormholeEntity.h

Entity subclass representing a wormhole between systems. (This is -- to use
technical terminology -- the blue blobby thing you see hanging in space. The
purple tunnel is RingEntity.)

Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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

#import "Entity.h"

#define WORMHOLE_EXPIRES_TIMEINTERVAL	900.0
#define WORMHOLE_SHRINK_RATE			4000.0

@class ShipEntity, Universe;

typedef enum
{
	WH_SCANINFO_NONE = 0,
	WH_SCANINFO_SCANNED,
	WH_SCANINFO_COLLAPSE_TIME,
	WH_SCANINFO_ARRIVAL_TIME,
	WH_SCANINFO_DESTINATION,
	WH_SCANINFO_SHIP,
} WORMHOLE_SCANINFO;

@interface WormholeEntity: Entity
{
	double			expiry_time;	// Time when wormhole entrance closes
	double			travel_time;	// Time taken for a ship to traverse the wormhole
	double			arrival_time;	// Time when wormhole exit opens
	double			scan_time;		// Time when wormhole was scanned
	
	Random_Seed		origin;
	Random_Seed		destination;
	
	NSMutableArray	*shipsInTransit;
	
	double			witch_mass;
	
	WORMHOLE_SCANINFO	scan_info;
	BOOL			hasExitPosition;
}

- (WormholeEntity*) initWithDict:(NSDictionary*)dict;
- (WormholeEntity*) initWormholeTo:(Random_Seed) s_seed fromShip:(ShipEntity *) ship;

- (BOOL) suckInShip:(ShipEntity *) ship;
- (void) disgorgeShips;

- (Random_Seed) origin;
- (Random_Seed) destination;

- (double) expiryTime;	// Time at which the wormholes entrance closes
- (double) arrivalTime;	// Time at which the wormholes exit opens
- (double) travelTime;	// Time needed for a ship to traverse the wormhole
- (double) scanTime;	// Time when wormhole was scanned
- (void) setScannedAt:(double)time;

- (BOOL) isScanned;		// True if the wormhole has been scanned by the player
- (WORMHOLE_SCANINFO) scanInfo; // Stage of scanning
- (void)setScanInfo:(WORMHOLE_SCANINFO) scanInfo;

- (NSArray*) shipsInTransit;

- (NSString *) identFromShip:(ShipEntity*) ship;

- (NSDictionary *)getDict;

@end
