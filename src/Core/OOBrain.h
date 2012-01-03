/*

OOBrain.h

Part of NPC behaviour implementation.

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

#ifdef OO_BRAIN_AI

#import "OOCocoa.h"
#import "OOTypes.h"

#define MAX_CONSIDERED_ENTITIES		32
#define MAX_INSTINCTS				16


@class OOInstinct, Entity, ShipEntity;

@interface OOBrain : NSObject {

	id			owner;
	
	ShipEntity*	ship;
	
	int			n_instincts;
	OOInstinct*	instincts[MAX_INSTINCTS];	// each considered against the nearby_entities - highest priority_out wins!
	
	OOInstinct*	most_urgent_instinct;
	
	int			n_nearby_entities;
	Entity*		nearby_entities[MAX_CONSIDERED_ENTITIES + 1];
	
	double		observe_interval;
	double		time_until_observation;	// countdown
	
	double		action_interval;
	double		time_until_action;	// countdown
	
}

- (void)	setOwner:(id) anOwner;
- (void)	setShip:(ShipEntity*) aShip;

- (id)			owner;
- (ShipEntity*)	ship;

// each instinct has a NSNumber priority
- (id)	initBrainWithInstincts:(NSDictionary*) instinctDictionary forOwner:(id) anOwner andShip:(ShipEntity*) aShip;

- (void)	update:(OOTimeDelta) delta_t;

- (void)	observe;	// look around, note ships, wormholes, planets

- (void)	evaluateInstincts;	// calculate priority for each instinct

- (void)	actOnInstincts;	// set ship behaviour from most urgent instinct

- (void)dumpState;

@end

#endif /* OO_BRAIN_AI */
