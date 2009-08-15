/*

WormholeEntity.m

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

#import "WormholeEntity.h"

#import "ParticleEntity.h"
#import "ShipEntity.h"
#import "PlanetEntity.h"
#import "PlayerEntity.h"

#import "Universe.h"
#import "AI.h"
#import "OORoleSet.h"
#import "OOShipRegistry.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"

// Hidden interface
@interface WormholeEntity (Private)

-(WormholeEntity *) init;

@end

// Static local functions
static void DrawWormholeCorona(GLfloat inner_radius, GLfloat outer_radius, int step, GLfloat z_distance, GLfloat *col4v1);


@implementation WormholeEntity (Private)

- (WormholeEntity*)init
{
	if ((self = [super init]))
	{
		witch_mass = 0.0;
		shipsInTransit = [[NSMutableArray arrayWithCapacity:4] retain];
		collision_radius = 0.0;
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_WORMHOLE;
		isWormhole = YES;
		scan_info = WH_SCANINFO_NONE;
		scan_time = 0;
		hasExitPosition = NO;
	}
	return self;
}

@end // Private interface implementation


//
// Public Wormhole Implementation
//

@implementation WormholeEntity

- (WormholeEntity*)initWithDict:(NSDictionary*)dict
{
	assert(dict != nil);

	if ([self init])
	{
		NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

		origin = RandomSeedFromString([dict stringForKey:@"origin_seed"]);
		destination = RandomSeedFromString([dict stringForKey:@"dest_seed"]);

		// We only ever init from dictionary if we're loaded by the player, so
		// by definition we have been scanned
		scan_info = WH_SCANINFO_SCANNED;

		// Remember, times are stored as Ship Clock - but anything
		// saving/restoring wormholes from dictionaries should know this!
		expiry_time = [dict doubleForKey:@"expiry_time"];
		arrival_time = [dict doubleForKey:@"arrival_time"];
		NSDictionary * posDict = [dict objectForKey:@"position"];
		position.x = [posDict floatForKey:@"x"];
		position.y = [posDict floatForKey:@"y"];
		position.z = [posDict floatForKey:@"z"];

		// Setup shipsInTransit
		NSArray * shipDictsArray = [dict arrayForKey:@"ships"];
		NSEnumerator * shipDicts = [shipDictsArray objectEnumerator];
		NSDictionary * currShipDict;
		[shipsInTransit removeAllObjects];
		while ((currShipDict = [shipDicts nextObject]) != nil)
		{
			double time = [currShipDict doubleForKey:@"time_delta"];
			NSDictionary * myShipDict = [currShipDict objectForKey:@"ship"];
			ShipEntity * ship = [ShipEntity alloc];
			ship = [ship initWithDictionary:myShipDict];
			// MKW 20090815 - Check to make sure the ship loaded ok - if not, let's try to load
			//                a compatible alternative.
			if( !ship )
			{
				OOLog(@"wormhole.load.warning", @"Ship '%@' failed to initialize - missing OXP?  Attempting to replace with random ship using roles '%@'.",
						[myShipDict stringForKey:@"name"], [myShipDict stringForKey:@"roles"]);
				OORoleSet * roleSet = [OORoleSet roleSetWithString:[myShipDict stringForKey:@"roles"]];
				NSString * shipRole = [roleSet anyRole];
				NSString * shipKey = [[OOShipRegistry sharedRegistry] randomShipKeyForRole:shipRole];
				if( shipKey )
				{
					ship = [ShipEntity alloc];
					myShipDict = [[OOShipRegistry sharedRegistry] shipInfoForKey:shipKey];
					ship = [ship initWithDictionary:myShipDict];
				}
				if( ship )
				{
					OOLog(@"wormhole.load.warning", @"Loaded alternative ship '%@' with role '%@'.", 
							[ship name], shipRole);
				}
				else
				{
					OOLog(@"wormhole.load.warning", @"Failed to load alternative ship - skipping Wormhole ship.");
				}
			}

			if( ship )
			{
				[shipsInTransit addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					ship, @"ship",
					[NSNumber numberWithDouble:time], @"time",
					nil]];
				[ship release];
			}
			/*
			   [shipsInTransit addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			   [NSNumber numberWithDouble:[currShipDict doubleForKey:@"time_delta"]], @"time",
			   [[ShipEntity alloc] initWithDictionary:[currShipDict objectForKey:@"ship"]], @"ship",
			   nil]];
			   */
		}
		[pool release];
	}
	return self;
}

- (WormholeEntity*) initWormholeTo:(Random_Seed) s_seed fromShip:(ShipEntity *) ship
{
	assert(ship != nil);

	if ((self = [self init]))
	{
		double now = [[PlayerEntity sharedPlayer] clockTimeAdjusted];
		double distance;

		origin = [UNIVERSE systemSeed];
		destination = s_seed;
		distance = distanceBetweenPlanetPositions(destination.d, destination.b, origin.d, origin.b);
		witch_mass = [ship mass];
		expiry_time = now + (witch_mass / WORMHOLE_SHRINK_RATE);
		travel_time = (distance * distance * 3600); // Taken from PlayerEntity.h
		arrival_time = now + travel_time;
		position = [ship position];
		zero_distance = distance2([[PlayerEntity sharedPlayer] position], position);
	}	
	return self;
}


- (BOOL) suckInShip:(ShipEntity *) ship
{
	if (equal_seeds(destination, [UNIVERSE systemSeed]))
		return NO;	// far end of the wormhole!
	
	if (!ship)
		return NO;

	double now = [[PlayerEntity sharedPlayer] clockTimeAdjusted];
	[shipsInTransit addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						ship, @"ship",
						[NSNumber numberWithDouble: now + travel_time - arrival_time], @"time",
						nil]];
	witch_mass += [ship mass];
	expiry_time = now + (witch_mass / WORMHOLE_SHRINK_RATE);
	collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);

	// witchspace entry effects here
	ParticleEntity *ring = [[ParticleEntity alloc] initHyperringFromShip:ship]; // retained
	[UNIVERSE addEntity:ring];
	[ring release];
	ring = [[ParticleEntity alloc] initHyperringFromShip:ship]; // retained
	[ring setSize:NSMakeSize([ring size].width * -2.5 ,[ring size].height * -2.0 )]; // shrinking!
	[UNIVERSE addEntity:ring];
	[ring release];
		
	// Should probably pass the wormhole, but they have no JS representation
	[ship doScriptEvent:@"shipWillEnterWormhole"];
	[[ship getAI] message:@"ENTERED_WITCHSPACE"];
	
	[UNIVERSE removeEntity:ship];
	[[ship getAI] clearStack];	// get rid of any preserved states
		
	return YES;
}


- (void) disgorgeShips
{
	double now = [[PlayerEntity sharedPlayer] clockTimeAdjusted];
	int n_ships = [shipsInTransit count];
	NSMutableArray * shipsStillInTransit = [[NSMutableArray alloc] initWithCapacity:n_ships];
	
	int i;
	for (i = 0; i < n_ships; i++)
	{
		ShipEntity* ship = (ShipEntity*)[(NSDictionary*)[shipsInTransit objectAtIndex:i] objectForKey:@"ship"];
		double	ship_arrival_time = arrival_time + [(NSNumber*)[(NSDictionary*)[shipsInTransit objectAtIndex:i] objectForKey:@"time"] doubleValue];
		double	time_passed = now - ship_arrival_time;

		if (ship_arrival_time > now)
		{
			[shipsStillInTransit addObject:[shipsInTransit objectAtIndex:i]];
		}
		else
		{
			// Only calculate exit position once so that all ships arrive from the same point
			if (!hasExitPosition)
			//if ( vector_equal(position, kZeroVector) )
			{
				hasExitPosition = YES;
				position = [UNIVERSE getWitchspaceExitPosition];
				Quaternion	q1;
				quaternion_set_random(&q1);
				double		d1 = SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
				if (abs(d1) < 500.0)	// no closer than 500m
					d1 += ((d1 > 0.0)? 500.0: -500.0);
				Vector		v1 = vector_forward_from_quaternion(q1);
				position.x += v1.x * d1; // randomise exit position
				position.y += v1.y * d1;
				position.z += v1.z * d1;
			}
			[ship setPosition: position];
			[ship setOrientation: [UNIVERSE getWitchspaceExitRotation]];
			[ship setPitch: 0.0];
			[ship setRoll: 0.0];
		
			[ship setBounty:[ship bounty]/2];	// adjust legal status for new system
		
			if ([ship cargoFlag] == CARGO_FLAG_FULL_PLENTIFUL)
				[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
		
			[UNIVERSE addEntity:ship];
		
			// Should probably pass the wormhole, but they have no JS representation
			[ship doScriptEvent:@"shipExitedWormhole" andReactToAIMessage:@"EXITED WITCHSPACE"];
		
			// update the ships's position
			[ship update: time_passed];
		}
	}
	[shipsInTransit release];
	shipsInTransit = shipsStillInTransit;
}


- (Random_Seed) origin
{
	return origin;
}

- (Random_Seed) destination
{
	return destination;
}

- (double) expiryTime
{
	return expiry_time;
}

- (double) arrivalTime
{
	return arrival_time;
}

- (double) travelTime
{
	return travel_time;
}

- (double) scanTime
{
	return scan_time;
}

- (BOOL) isScanned
{
	return scan_info > WH_SCANINFO_NONE;
}

- (void) setScannedAt:(double)p_scanTime
{
	if( scan_info == WH_SCANINFO_NONE )
	{
		scan_time = p_scanTime;
		scan_info = WH_SCANINFO_SCANNED;
	}
	// else we previously scanned this wormhole
}

- (WORMHOLE_SCANINFO) scanInfo
{
	return scan_info;
}

- (void) setScanInfo:(WORMHOLE_SCANINFO)p_scanInfo
{
	scan_info = p_scanInfo;
}

- (NSArray*) shipsInTransit
{
	return shipsInTransit;
}

- (void) dealloc
{
	[shipsInTransit release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	double now = [UNIVERSE getTime];
	return [NSString stringWithFormat:@"destination: %@ ttl: %.2fs arrival: %@",
		[UNIVERSE getSystemName:destination],
		WORMHOLE_EXPIRES_TIMEINTERVAL - now,
		ClockToString(arrival_time, false)];
}

- (NSString *) identFromShip:(ShipEntity*)ship
{
	assert([ship hasEquipmentItem:@"EQ_WORMHOLE_SCANNER"]);
	if ([self scanInfo] >= WH_SCANINFO_DESTINATION)
		return [NSString stringWithFormat:DESC(@"wormhole-to-@"), [UNIVERSE getSystemName:destination]];
	else
		return DESC(@"wormhole-desc");
}


- (BOOL) canCollide
{
	if (equal_seeds(destination, [UNIVERSE systemSeed]))
	{
		return NO;	// far end of the wormhole!
	}
	return (witch_mass > 0.0);
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return !other->isParticle;
}


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];
	
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
	assert(player != nil);
	rotMatrix = OOMatrixForBillboard(position, [player position]);
	double now = [player clockTimeAdjusted];
	
	if (witch_mass > 0.0)
	{
		witch_mass -= WORMHOLE_SHRINK_RATE * delta_t;
		if (witch_mass < 0.0)
			witch_mass = 0.0;
		collision_radius = 0.5 * M_PI * pow(witch_mass, 1.0/3.0);
		no_draw_distance = collision_radius * collision_radius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
	}

	scanClass = (witch_mass > 0.0)? CLASS_WORMHOLE : CLASS_NO_DRAW;
	
	if (now > expiry_time)
	{
		//position.x = position.y = position.z = 0;
		position = kZeroVector;
		[UNIVERSE removeEntity: self];
	}
}


- (void) drawEntity:(BOOL) immediate :(BOOL) translucent
{	
	if (!UNIVERSE)
		return;
	
	if ([UNIVERSE breakPatternHide])
		return;		// DON'T DRAW DURING BREAK PATTERN
	
	if (zero_distance > no_draw_distance)
		return;	// TOO FAR AWAY TO SEE
		
	if (witch_mass < 0.0)
		return;
	
	if (collision_radius <= 0.0)
		return;
	
	if (translucent)
	{
		// for now, a simple copy of the energy bomb draw routine
		double srzd = sqrt(zero_distance);
		
		GLfloat	color_fv[4] = { 0.0, 0.0, 1.0, 0.25};
		
		glDisable(GL_CULL_FACE);			// face culling
		glDisable(GL_TEXTURE_2D);
		
		glColor4fv(color_fv);
		glBegin(GL_TRIANGLE_FAN);
		//
		GLDrawBallBillboard(collision_radius, 4, srzd);
		//
		glEnd();
				
		DrawWormholeCorona(0.67 * collision_radius, collision_radius, 4, srzd, color_fv);
					
		glEnable(GL_CULL_FACE);			// face culling
	}
	CheckOpenGLErrors(@"WormholeEntity after drawing %@", self);
}


static void DrawWormholeCorona(GLfloat inner_radius, GLfloat outer_radius, int step, GLfloat z_distance, GLfloat *col4v1)
{
	if (outer_radius >= z_distance) // inside the sphere
		return;
	int i;
	
	NSRange				activity = { 0.34, 1.0 };
	
	GLfloat				s0, c0, s1, c1;
	
	GLfloat				r0, r1;
	GLfloat				rv0, rv1, q;
	
	GLfloat				theta, delta, halfStep;
	
	r0 = outer_radius * z_distance / sqrt(z_distance * z_distance - outer_radius * outer_radius); 
	r1 = inner_radius * z_distance / sqrt(z_distance * z_distance - inner_radius * inner_radius); 
	
	delta = step * M_PI / 180.0f;
	halfStep = 0.5f * delta;
	theta = 0.0f;
		
	glBegin(GL_TRIANGLE_STRIP);
	for (i = 0; i < 360; i += step )
	{
		theta += delta;
		
		rv0 = randf();
		rv1 = randf();
		
		q = activity.location + rv0 * activity.length;
		
		s0 = r0 * sinf(theta);
		c0 = r0 * cosf(theta);
		glColor4f(col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
		glVertex3f(s0, c0, 0.0);

		s1 = r1 * sinf(theta - halfStep) * 0.5 * (1.0 + rv1);
		c1 = r1 * cosf(theta - halfStep) * 0.5 * (1.0 + rv1);
		glColor4f(col4v1[0], col4v1[1], col4v1[2], 0.0);
		glVertex3f(s1, c1, 0.0);
		
	}
	// repeat last values to close
	rv0 = randf();
	rv1 = randf();
		
	q = activity.location + rv0 * activity.length;
	
	s0 = 0.0f;	// r0 * sinf(0);
	c0 = r0;	// r0 * cosf(0);
	glColor4f(col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
	glVertex3f(s0, c0, 0.0);

	s1 = r1 * sinf(halfStep) * 0.5 * (1.0 + rv1);
	c1 = r1 * cosf(halfStep) * 0.5 * (1.0 + rv1);
	glColor4f(col4v1[0], col4v1[1], col4v1[2], 0.0);
	glVertex3f(s1, c1, 0.0);
	
	glEnd();
}

- (NSDictionary *)getDict
{
	NSMutableDictionary * myDict = [[NSMutableDictionary dictionary] retain];
	NSString * str = nil;

	str = [NSString stringWithFormat:@"%d %d %d %d %d %d",origin.a, origin.b, origin.c, origin.d, origin.e, origin.f];
	[myDict setObject:str forKey:@"origin_seed"];
	str = [NSString stringWithFormat:@"%d %d %d %d %d %d",destination.a, destination.b, destination.c, destination.d, destination.e, destination.f];
	[myDict setObject:str forKey:@"dest_seed"];
	// Anything converting a wormhole to a dictionary should already have 
	// modified its time to shipClock time
	[myDict setFloat:(expiry_time) forKey:@"expiry_time"];
	[myDict setFloat:(arrival_time) forKey:@"arrival_time"];
	[myDict setObject:[NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithFloat:position.x], @"x", 
		[NSNumber numberWithFloat:position.y], @"y",
		[NSNumber numberWithFloat:position.z], @"z",
		nil] forKey:@"position"];

	NSMutableArray * shipArray = [NSMutableArray arrayWithCapacity:[shipsInTransit count]];
	NSEnumerator * ships = [shipsInTransit objectEnumerator];
	NSDictionary * currShipDict = nil;
	while ((currShipDict = [ships nextObject]) != nil)
	{
		/*
		NSMutableDictionary * myShipDict = [NSMutableDictionary dictionary];
		[myShipDict setFloat:([currShipDict doubleForKey:@"time"]) forKey:@"time_delta"];
		ShipEntity * currShip = (ShipEntity*)[currShipDict objectForKey:@"ship"];
		[myShipDict setObject:[currShip shipInfoDictionary] forKey:@"ship"];
		[shipArray addObject:myShipDict];
		*/
		[shipArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithDouble:[currShipDict doubleForKey:@"time"]], @"time_delta",
			[[currShipDict objectForKey:@"ship"] shipInfoDictionary], @"ship",
			nil]];
	}
	[myDict setObject:shipArray forKey:@"ships"];

	return myDict;
}

@end
