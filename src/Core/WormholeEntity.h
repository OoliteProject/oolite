//
//  WormholeEntity.h
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Wed 26 Oct 2005.
 *  Copyright (c) 2005 for aegidian.org. All rights reserved.
 *

Copyright (c) 2005, Giles C Williams
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
