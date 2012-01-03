/*

OOBrain.m

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

#import "OOBrain.h"
#import "OOInstinct.h"

#import "Universe.h"
#import "OOConstToString.h"
#import "OOCollectionExtractors.h"

#import "ShipEntity.h"


@implementation OOBrain

- (void)setOwner:(id)anOwner
{
	owner = anOwner;
}


- (void)setShip:(ShipEntity *)aShip
{
	ship = aShip;
}


- (id)owner
{
	return owner;
}


- (ShipEntity *)ship
{
	return ship;
}


- (id)initBrainWithInstincts:(NSDictionary*) instinctDictionary forOwner:(id) anOwner andShip:(ShipEntity*) aShip
{
	NSEnumerator			*instinctEnum = nil;
	NSString				*key = nil;
	OOInstinct				*instinct = nil;
	
	self = [super init];
	
	n_instincts = 0;
	
	for (instinctEnum = [instinctDictionary keyEnumerator]; (key = [instinctEnum nextObject]); )
	{
		OOInstinctID itype = OOInstinctIDFromString(key);
		
		if (itype != INSTINCT_NULL)
		{
			if (n_instincts == MAX_INSTINCTS)
			{
				OOLog(@"brain.full", @"Instinct dictionary has too many instincts, giving up at %@.", key);
				break;
			}
			
			GLfloat iprio = [instinctDictionary oo_floatForKey:key];
			if (iprio != 0.0f)
			{
				instinct = [[OOInstinct alloc] initInstinctOfType:itype ofPriority:iprio forOwner:anOwner withShip:aShip];
				if (instinct != nil)
				{
					instincts[n_instincts++] = instinct;	// retained
				}
			}
		}
	}
	
	time_until_action = randf() * 0.5;
	action_interval = 0.125;

	time_until_observation = randf() * 0.5;
	observe_interval = 0.25;
	
	return self;
}


- (void)update:(OOTimeDelta)delta_t
{
	time_until_observation -= delta_t;
	if (time_until_observation < 0.0)
	{
		time_until_observation += observe_interval;
		[self observe];
	}
	//
	time_until_action -= delta_t;
	if (time_until_action < 0.0)
	{
		time_until_action += action_interval;
		[self evaluateInstincts];
	}
	//
	[self actOnInstincts];
}


- (void)observe	// look around, note ships, wormholes, planets
{
	n_nearby_entities = 0;
	nearby_entities[0] = nil;	// zero list
	
	if (!ship)
		return;
	
	// note nearby collidables and all planets
	//
	Entity* scan;
	GLfloat d2 = 0.0;
	GLfloat scannerRange = SCANNER_MAX_RANGE;
	//
	scan = ship->z_previous;	while ((scan)&&(![scan canCollide]))	scan = scan->z_previous;	// skip non-collidables
	while ((scan)&&(scan->position.z > ship->position.z - scannerRange)&&(n_nearby_entities < MAX_CONSIDERED_ENTITIES))
	{
		if ([scan canCollide])
		{
			d2 = distance2( ship->position, scan->position);
			if (d2 < SCANNER_MAX_RANGE2)
				nearby_entities[n_nearby_entities++] = scan;
		}
		scan = scan->z_previous;	while ((scan)&&(![scan canCollide]))	scan = scan->z_previous;
	}
	while ((scan)&&(n_nearby_entities < MAX_CONSIDERED_ENTITIES))
	{
		if (scan->isPlanet)
			nearby_entities[n_nearby_entities++] = scan;
		scan = scan->z_previous;	while ((scan)&&(!scan->isPlanet))	scan = scan->z_previous;
	}
	//
	scan = ship->z_next;	while ((scan)&&(![scan canCollide]))	scan = scan->z_next;	// skip non-collidables
	while ((scan)&&(scan->position.z < ship->position.z + scannerRange)&&(n_nearby_entities < MAX_CONSIDERED_ENTITIES))
	{
		if ([scan canCollide])
		{
			d2 = distance2( ship->position, scan->position);
			if (d2 < SCANNER_MAX_RANGE2)
				nearby_entities[n_nearby_entities++] = scan;
		}
		scan = scan->z_next;	while ((scan)&&(![scan canCollide]))	scan = scan->z_next;	// skip non-collidables
	}
	while ((scan)&&(n_nearby_entities < MAX_CONSIDERED_ENTITIES))
	{
		if (scan->isPlanet)
			nearby_entities[n_nearby_entities++] = scan;
		scan = scan->z_next;	while ((scan)&&(!scan->isPlanet))	scan = scan->z_next;	// skip non-planets
	}
	//
	nearby_entities[n_nearby_entities] = nil;
}


- (void)evaluateInstincts	// calculate priority for each instinct
{
	int i = 0;
	nearby_entities[n_nearby_entities] = nil;
	GLfloat most_urgent = -99.9;
	for (i = 0; i < n_instincts; i++)
	{
		OOInstinct* instinct = instincts[i];
		if (instinct)
		{
			GLfloat urgency = [instinct evaluateInstinctWithEntities: nearby_entities];
			if (urgency > most_urgent)
			{
				most_urgent = urgency;
				most_urgent_instinct = instinct;
			}
		}
	}
}


- (void)actOnInstincts	// set ship behaviour from most urgent instinct
{
	if (most_urgent_instinct)
	{
		[most_urgent_instinct setShipVars];
	}
	else
	{
		int i = 0;
		GLfloat most_urgent = -99.9;
		for (i = 0; i < n_instincts; i++)
		{
			if (instincts[i])
			{
				GLfloat urgency = [instincts[i] priority];
				if (urgency > most_urgent)
				{
					most_urgent = urgency;
					most_urgent_instinct = instincts[i];
				}
			}
		}
	}
}


- (void)dumpState
{
	OOLog(@"dumpState.brain", @"Instinct count: %u", n_instincts);
	OOLog(@"dumpState.brain", @"Nearby entities: %u", n_nearby_entities);
	if (most_urgent_instinct != nil && OOLogWillDisplayMessagesInClass(@"dumpState.brain.instinct"))
	{
		OOLog(@"dumpState.brain.instinct", @"Most urgent instinct:");
		OOLogPushIndent();
		OOLogIndent();
		NS_DURING
			[most_urgent_instinct dumpState];
		NS_HANDLER
		NS_ENDHANDLER
		OOLogPopIndent();
	}
}

@end
