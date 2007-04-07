/*

WormholeEntity.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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
#import "TextureStore.h"
#import "OOStringParsing.h"


@implementation WormholeEntity

- (id) initWormholeTo:(Random_Seed) s_seed fromShip:(ShipEntity *) ship
{
	self = [super init];
	//
	if (!ship)
		return self;
	//
	destination = s_seed;
	//
    time_counter = 0.0;
	//
	expiry_time = time_counter + WORMHOLE_EXPIRES_TIMEINTERVAL;
	//
	witch_mass = 0.0;
	//
	shipsInTransit = [[NSMutableArray arrayWithCapacity:4] retain];
	//
	collision_radius = 0.0;
	//
	status = STATUS_EFFECT;
	scanClass = CLASS_MINE;
	//
	position = [ship position];
    //
	PlayerEntity *player = [PlayerEntity sharedPlayer];
	if (player)
		zero_distance = distance2( player->position, position);
	//
	isWormhole = YES;
	
	return self;
}

- (BOOL) suckInShip:(ShipEntity *) ship
{
	if (equal_seeds( destination, [UNIVERSE systemSeed]))
		return NO;	// far end of the wormhole!
	
	if (ship)
	{
		[shipsInTransit addObject:	[NSDictionary dictionaryWithObjectsAndKeys:
										ship, @"ship",
										[NSNumber numberWithDouble: time_counter], @"time",
										nil]];
		witch_mass += [ship mass];
		expiry_time = time_counter + WORMHOLE_EXPIRES_TIMEINTERVAL;
		collision_radius = 0.5 * M_PI * pow( witch_mass, 1.0/3.0);

		// witchspace entry effects here
		ParticleEntity *ring = [[ParticleEntity alloc] initHyperringFromShip:ship]; // retained
		[UNIVERSE addEntity:ring];
		[ring release];
		ring = [[ParticleEntity alloc] initHyperringFromShip:ship]; // retained
		[ring setSize:NSMakeSize([ring size].width * -2.5 ,[ring size].height * -2.0 )]; // shrinking!
		[UNIVERSE addEntity:ring];
		[ring release];
		
		[[ship getAI] message:@"ENTERED_WITCHSPACE"];
	
		[UNIVERSE removeWithoutRecyclingEntity: ship];
		[[ship getAI] clearStack];	// get rid of any preserved states
		
		//
		return YES;
	}
	// fall through
	return NO;
}

- (void) disgorgeShips
{
	int n_ships = [shipsInTransit count];
	
	int i;
	for (i = 0; i < n_ships; i++)
	{
		ShipEntity* ship = (ShipEntity*)[(NSDictionary*)[shipsInTransit objectAtIndex:i] objectForKey:@"ship"];
		double	time_entered = [(NSNumber*)[(NSDictionary*)[shipsInTransit objectAtIndex:i] objectForKey:@"time"] doubleValue];
		double	time_passed = time_counter - time_entered;

		Vector pos = [UNIVERSE getWitchspaceExitPosition];
		Quaternion	q1;
		quaternion_set_random(&q1);
		double		d1 = SCANNER_MAX_RANGE*((ranrot_rand() % 256)/256.0 - 0.5);
		if (abs(d1) < 500.0)	// no closer than 500m
			d1 += ((d1 > 0.0)? 500.0: -500.0);
		Vector		v1 = vector_forward_from_quaternion(q1);
		pos.x += v1.x * d1; // randomise exit position
		pos.y += v1.y * d1;
		pos.z += v1.z * d1;
		[ship setPosition: pos];
		[ship setQRotation: [UNIVERSE getWitchspaceExitRotation]];
		[ship setPitch: 0.0];
		[ship setRoll: 0.0];
		
		[ship setBounty:[ship getBounty]/2];	// adjust legal status for new system
		
		if ([ship cargoFlag] == CARGO_FLAG_FULL_PLENTIFUL)
			[ship setCargoFlag: CARGO_FLAG_FULL_SCARCE];
		
		[UNIVERSE addEntity:ship];
		
		[[ship getAI] reactToMessage:@"EXITED WITCHSPACE"];
		
		// update the ships's position
		[ship update: time_passed];
	}
}


- (Random_Seed) destination
{
	return destination;
}

- (void) dealloc
{
    if (shipsInTransit)	[shipsInTransit release];
    [super dealloc];
}

- (NSString*) description
{
	NSString* whereto = (UNIVERSE) ? [UNIVERSE getSystemName:destination] : StringFromRandomSeed(destination);
	return [NSString stringWithFormat:@"<WormholeEntity to %@ ttl: %.2fs>", whereto, WORMHOLE_EXPIRES_TIMEINTERVAL - time_counter];
}

- (BOOL) canCollide
{
	if (equal_seeds( destination, [UNIVERSE systemSeed]))
		return NO;	// far end of the wormhole!
	return (witch_mass > 0.0);
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	return !(other->isParticle);
}

- (void) update:(double) delta_t
{
	[super update:delta_t];
	
	Entity* player = [PlayerEntity sharedPlayer];
	if (player)
	{
		// new billboard routine (from Planetentity.m)
		Vector v0 = position;
		Vector p0 = (player)? player->position: kZeroVector;
		v0.x -= p0.x;	v0.y -= p0.y;	v0.z -= p0.z; // vector from player to position
		if (v0.x||v0.y||v0.z)
			v0 = unit_vector(&v0);
		else
			v0.z = 1.0;
		//equivalent of v_forward
		Vector arb1;
		if ((v0.x == 0.0)&&(v0.y == 0.0))
		{
			arb1.x = 1.0;   arb1.y = 0.0; arb1.z = 0.0; // arbitrary axis - not aligned with v0
		}
		else
		{
			arb1.x = 0.0;   arb1.y = 0.0; arb1.z = 1.0;
		}
		Vector v1 = cross_product( v0, arb1 ); // 90 degrees to (v0 x arb1)
		//equivalent of v_right
		Vector v2 = cross_product( v0, v1 );   // 90 degrees to (v0 x v1)
		//equivalent of v_up
		vectors_into_gl_matrix( v0, v1, v2, rotMatrix);
	}
	
	time_counter += delta_t;
	
	if (witch_mass > 0.0)
	{
		witch_mass -= WORMHOLE_SHRINK_RATE * delta_t;
		if (witch_mass < 0.0)
			witch_mass = 0.0;
		collision_radius = 0.5 * M_PI * pow( witch_mass, 1.0/3.0);
		no_draw_distance = collision_radius * collision_radius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
	}

	scanClass = (witch_mass > 0.0)? CLASS_WORMHOLE : CLASS_NO_DRAW;
	
	if (time_counter > expiry_time)
		[UNIVERSE removeEntity: self];
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent;
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
		
		glColor4fv( color_fv);
		glBegin(GL_TRIANGLE_FAN);
		//
		drawBallVertices( collision_radius, 4, srzd);
		//
		glEnd();
				
		drawWormholeCorona( 0.67 * collision_radius, collision_radius, 4, srzd, color_fv);
					
		glEnable(GL_CULL_FACE);			// face culling
	}
	CheckOpenGLErrors(@"after drawing WormholeEntity.");
}

void drawWormholeCorona (double inner_radius, double outer_radius, int step, double z_distance, GLfloat* col4v1)
{
	if (outer_radius >= z_distance) // inside the sphere
		return;
	int i, j, half_step;
	
	half_step = step / 2;
	j = -half_step;
	
	NSRange activity = NSMakeRange(0.34, 1.0);
	
	double s0, c0, s1, c1;
	
	double r0 = outer_radius * z_distance / sqrt( z_distance * z_distance - outer_radius * outer_radius); 
	double r1 = inner_radius * z_distance / sqrt( z_distance * z_distance - inner_radius * inner_radius); 
	GLfloat rv0, rv1, q;
		
	glBegin(GL_TRIANGLE_STRIP);
	for ( i = 0; i < 360; i += step )
	{
		j += step;
		while (j > 360) j-=360;
		
		rv0 = randf();
		rv1 = randf();
		
		q = activity.location + rv0 * activity.length;
		
		s0 = r0 * sin_value[i];
		c0 = r0 * cos_value[i];
		glColor4f( col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
		glVertex3f( s0, c0, 0.0);

		s1 = r1 * sin_value[j] * 0.5 * (1.0 + rv1);
		c1 = r1 * cos_value[j] * 0.5 * (1.0 + rv1);
		glColor4f( col4v1[0], col4v1[1], col4v1[2], 0.0);
		glVertex3f( s1, c1, 0.0);
		
	}
	// repeat last values to close
	rv0 = randf();
	rv1 = randf();
		
	q = activity.location + rv0 * activity.length;
	
	s0 = r0 * sin_value[0];
	c0 = r0 * cos_value[0];
	glColor4f( col4v1[0] * q, col4v1[1] * q, col4v1[2] * q, col4v1[3] * rv0);
	glVertex3f( s0, c0, 0.0);

	s1 = r1 * sin_value[half_step] * 0.5 * (1.0 + rv1);
	c1 = r1 * cos_value[half_step] * 0.5 * (1.0 + rv1);
	glColor4f( col4v1[0], col4v1[1], col4v1[2], 0.0);
	glVertex3f( s1, c1, 0.0);
	
	glEnd();
}

@end
