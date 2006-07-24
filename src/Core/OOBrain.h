//
//  OOBrain.h
//  Oolite
//
//  Created by Giles Williams on 21/07/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#include "OOCocoa.h"

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

- (void)	update:(double) delta_t;

- (void)	observe;	// look around, note ships, wormholes, planets

- (void)	evaluateInstincts;	// calculate priority for each instinct

- (void)	actOnInstincts;	// set ship behaviour from most urgent instinct

@end
