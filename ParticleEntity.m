//
//  ParticleEntity.m
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
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

#import "SkyEntity.h"
#import "entities.h"

#import "Universe.h"
#import "AI.h"
#import "TextureStore.h"

@implementation ParticleEntity

static Vector   circleVertex[65];		// holds vector coordinates for a unit circle

- (id) init
{    
    self = [super init];
    //
    quaternion_set_identity(&q_rotation);
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
    position.x = 0.0;
    position.y = 0.0;
    position.z = 0.0;
	//
	status = STATUS_EFFECT;
	time_counter = 0.0;
	//
	particle_type = PARTICLE_TEST;
	//
	basefile = @"Particle";
	textureNameString   = @"blur256.png";
	[self setColor:[NSColor greenColor]];
	//
	texName = 0;
	[self initialiseTexture: textureNameString];
	size = NSMakeSize(32.0,32.0);
	//
	owner = NO_TARGET;
	//
	collision_radius = 32.0;
	//
	int i;
	for (i = 0; i < 65; i++)
	{
		circleVertex[i].x = sin(i * PI / 32.0);
		circleVertex[i].y = cos(i * PI / 32.0);
		circleVertex[i].z = 0.0;
	}
	//
	isParticle = YES;
	//
    return self;
}

- (id) initLaserFromShip:(ShipEntity *) ship view:(int) view
{
    self = [super init];
	//
	if (!ship)
		return self;
    //
	status = STATUS_EFFECT;
    position = ship->position;
	q_rotation = ship->q_rotation;
	if ((ship)&&(ship->isPlayer))
		q_rotation.w = -q_rotation.w;   //reverse view direction for the player
	Vector v_up = vector_up_from_quaternion(q_rotation);
	Vector v_forward = vector_forward_from_quaternion(q_rotation);
	Vector v_right = vector_right_from_quaternion(q_rotation);
	double distance;
	switch (view)
	{
		case VIEW_FORWARD :
			distance = [ship getBoundingBox].max_z;
			position.x += distance * v_forward.x;	position.y += distance * v_forward.y;	position.z += distance * v_forward.z;
			break;
		case VIEW_AFT :
			quaternion_rotate_about_axis(&q_rotation, v_up, PI);
			distance = [ship getBoundingBox].min_z;
			position.x += distance * v_forward.x;	position.y += distance * v_forward.y;	position.z += distance * v_forward.z;
			break;
		case VIEW_PORT :
			quaternion_rotate_about_axis(&q_rotation, v_up, PI/2.0);
			distance = [ship getBoundingBox].min_x;
			position.x += distance * v_right.x;	position.y += distance * v_right.y;	position.z += distance * v_right.z;
			break;
		case VIEW_STARBOARD :
			quaternion_rotate_about_axis(&q_rotation, v_up, -PI/2.0);
			distance = [ship getBoundingBox].max_x;
			position.x += distance * v_right.x;	position.y += distance * v_right.y;	position.z += distance * v_right.z;
			break;
	}
    quaternion_into_gl_matrix(q_rotation, rotMatrix);
    //
	if ((ship)&&(ship->isPlayer))
	{
		position.x -= WEAPON_OFFSET_DOWN * v_up.x;	position.y -= WEAPON_OFFSET_DOWN * v_up.y;	position.z -= WEAPON_OFFSET_DOWN * v_up.z;	// offset below the view line
	}
	//
	time_counter = 0.0;
	//
	particle_type = PARTICLE_LASER_BEAM_RED;
	//
	[self setColor:[NSColor redColor]];
	//
	duration = PARTICLE_LASER_DURATION;
	//
	[self setOwner:ship];
	//
	collision_radius = [ship weapon_range];
	//
	isParticle = YES;
	//
    return self;
}

- (id) initExhaustFromShip:(ShipEntity *) ship offsetVector:(Vector) offset scaleVector:(Vector) scale
{
    int i;
	
	self = [super init];	// sets rotMatrix and q_rotation to initial identities
    //
	status = STATUS_EFFECT;

	// set a smooth shaded model :
	is_smooth_shaded = YES;
	[self setModel:@"exhaust.dat"];
	
	// adjust vertices according to scale
	//
	for (i = 0; i < n_vertices; i++)
	{
		alpha_for_vertex[i] = 1.0 + (vertices[i].z / 10.0);	// gives the alpha value at that point...
		vertices[i].x *= scale.x;
		vertices[i].y *= scale.y;
		vertices[i].z *= scale.z;
	}
	
	position.x = offset.x;  // position is relative to owner
	position.y = offset.y;
	position.z = offset.z;
	
	particle_type = PARTICLE_EXHAUST;
	//
	[self setOwner:ship];
	//
	collision_radius = [self findCollisionRadius];
	//
	isParticle = YES;
	//
    return self;
}

- (id) initExhaustFromShip:(ShipEntity *) ship details:(NSString *) details
{
    int i;
	NSArray *values = [details componentsSeparatedByString:@" "];
	if ([values count] != 6)
		return nil;
	Vector offset, scale;
	offset.x = [(NSString *)[values objectAtIndex:0] doubleValue];
	offset.y = [(NSString *)[values objectAtIndex:1] doubleValue];
	offset.z = [(NSString *)[values objectAtIndex:2] doubleValue];
	scale.x = [(NSString *)[values objectAtIndex:3] doubleValue];
	scale.y = [(NSString *)[values objectAtIndex:4] doubleValue];
	scale.z = [(NSString *)[values objectAtIndex:5] doubleValue];
	
	self = [super init];
    //
	status = STATUS_EFFECT;
	
//	NSLog(@"Adding an exhaust to a %@ at ( %3.1f, %3.1f, %3.1f)", [ship name], offset.x, offset.y, offset.z);
	
	// set a smooth shaded model :
	is_smooth_shaded = YES;
	[self setModel:@"exhaust.dat"];
	
	// adjust vertices according to scale
	//
	for (i = 0; i < n_vertices; i++)
	{
		alpha_for_vertex[i] = 1.0 + (vertices[i].z / 10.0);	// gives the alpha value at that point...
		vertices[i].x *= scale.x;
		vertices[i].y *= scale.y;
		vertices[i].z *= scale.z;
	}

	position.x = offset.x;  // position is relative to owner
	position.y = offset.y;
	position.z = offset.z;
	
	particle_type = PARTICLE_EXHAUST;
	//
	[self setOwner:ship];
	//	
	collision_radius = [self findCollisionRadius];
	//
	isParticle = YES;
	//
    return self;
}

- (id) initECMMineFromShip:(ShipEntity *) ship
{
	self = [super init];
	if (!ship)
		return self;
    //
    time_counter = 0.0;
	activation_time = 0.5;
	duration = 2.0;
	position = ship->position;
	//
	status = STATUS_EFFECT;
	scan_class = CLASS_NO_DRAW;
	//
	//NSLog(@"```firing ECM at ( %3.1f, %3.1f, %3.1f)", position.x, position.y, position.z);
	//
	particle_type = PARTICLE_ECM_MINE;
	//
	[self setOwner:ship];
	//
	isParticle = YES;
	//
	return self;
}

- (id) initEnergyMineFromShip:(ShipEntity *) ship
{
	self = [super init];
	//
	if (!ship)
		return self;
    //
    time_counter = 0.0;
	duration = 20.0;
	position = ship->position;
	//
	[self setVelocity:make_vector( 0, 0, 0)];
	//
	[self setColor:[NSColor blueColor]];
	//
	alpha = 0.5;
	collision_radius = 0;
	//
	status = STATUS_EFFECT;
	scan_class = CLASS_MINE;
	//
//	NSLog(@"```firing Energy Bomb at ( %3.1f, %3.1f, %3.1f)", position.x, position.y, position.z);
	//
	particle_type = PARTICLE_ENERGY_MINE;
	//
	[self setOwner:[ship owner]];
	//
	isParticle = YES;
	//
	return self;
}

- (id) initHyperringFromShip:(ShipEntity *) ship
{
	self = [super init];
    //
    time_counter = 0.0;
	duration = 2.0;
	if (!ship)
	{
		NSLog(@"ERROR - initHyperringFromShip:NULL");
		return self;
	}
	size.width = ship->collision_radius * 0.5;
	size.height = size.width * 1.25;
	ring_inner_radius = size.width;
	ring_outer_radius = size.height;
	position = ship->position;
	[self setQRotation:ship->q_rotation];
	[self setVelocity:[ship getVelocity]];
	//
	status = STATUS_EFFECT;
	scan_class = CLASS_NO_DRAW;
	//
	particle_type = PARTICLE_HYPERRING;
	int i;
	for (i = 0; i < 65; i++)
	{
		circleVertex[i].x = sin(i * PI / 32.0);
		circleVertex[i].y = cos(i * PI / 32.0);
		circleVertex[i].z = 0.0;
	}
	//
	[self setOwner:ship];
	//
	isParticle = YES;
	//
    return self;
}

- (id) initFragburstFromPosition:(Vector) fragPos
{
	int speed_low = 200;
	int speed_high = 800;
	int n_fragments = 32;
	int i;
	//
	self = [super init];
    //
	basefile = @"Particle";
	textureNameString   = @"blur256.png";
	//
	texName = 0;
	[self initialiseTexture: textureNameString];
	size = NSMakeSize(32.0,32.0);
	//
	n_vertices = n_fragments;
    time_counter = 0.0;
	duration = 1.5;
	position = fragPos;
	//
	for (i = 0 ; i < n_vertices; i++)
	{
		int speed = (ranrot_rand() % (speed_high - speed_low)) + speed_low;
		vertices[i] = make_vector(0,0,0);
		vertex_normal[i].x = (ranrot_rand() % speed) - speed / 2;
		vertex_normal[i].y = (ranrot_rand() % speed) - speed / 2;
		vertex_normal[i].z = (ranrot_rand() % speed) - speed / 2;
	}
	//
	status = STATUS_EFFECT;
	scan_class = CLASS_NO_DRAW;
	//
	particle_type = PARTICLE_FRAGBURST;
	//
	collision_radius = 0;
	energy = 0;
	[self setColor:[NSColor yellowColor]];
	owner = NO_TARGET;
	//
	isParticle = YES;
	//
    return self;
}

- (void) dealloc
{
    if (textureNameString)	[textureNameString release];
    if (color)				[color release];
    [super dealloc];
}

- (BOOL) canCollide
{
	switch (particle_type)
	{
		case PARTICLE_TEST :
		case PARTICLE_LASER_BEAM_RED :
		case PARTICLE_LASER_BEAM :
		case PARTICLE_EXPLOSION :
		case PARTICLE_SHOT_EXPIRED :
		case PARTICLE_EXHAUST :
		case PARTICLE_HYPERRING :
		case PARTICLE_FLASHER :
		case PARTICLE_MARKER :
		case PARTICLE_ECM_MINE :
		case PARTICLE_SPARK :
		case PARTICLE_FRAGBURST :
			return NO;
			break;
		default :
			return (time_counter > 0.05);	// can't collide for the first .05s
			break;
	}
}

- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (particle_type == PARTICLE_ENERGY_MINE)
		return YES;
	if (other == [self owner])
		return NO;
	return !(other->isParticle);
}


- (void) setTexture:(NSString *) filename
{
    if (filename)
	{
		if (textureNameString)	[textureNameString release];
		textureNameString = filename;
		[textureNameString retain];
		[self initialiseTexture: textureNameString];
	}
}

- (void) setColor:(NSColor *) a_color
{
	if (!a_color)
		return;
	NSColor *rgbColor = [a_color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	
	if (color)				[color release];
	color = [rgbColor retain];

	color_fv[0] = [color redComponent];
	color_fv[1] = [color greenComponent];
	color_fv[2] = [color blueComponent];
}



- (void) setParticleType:(int) p_type
{
	particle_type = p_type;
}


- (int) particleType
{
	return particle_type;
}


- (void) setDuration:(double) dur
{
	duration = dur;
	time_counter = 0.0;
}

- (void) setSize:(NSSize) siz
{
	size = siz;
	collision_radius = sqrt (size.width * size.width + size.height * size.height);
	no_draw_distance = collision_radius * collision_radius * NO_DRAW_DISTANCE_FACTOR * NO_DRAW_DISTANCE_FACTOR;
}

- (NSSize) size
{
	return size;
}

- (void) initialiseTexture: (NSString *) name
{
    if (universe)
	{
         texName = [[universe textureStore] getTextureNameFor:name];
	}
}

- (void) update:(double) delta_t
{
//	NSLog(@"DEBUG update for %@",self);
	[super update:delta_t];
	
	time_counter += delta_t;
	
	if (universe)
	{
		switch (particle_type)
		{
			case PARTICLE_TEST :
			case PARTICLE_SHOT_EXPIRED :
			case PARTICLE_SHOT_YELLOW_PLASMA :
			case PARTICLE_SPARK :
			case PARTICLE_SHOT_GREEN_PLASMA :
			case PARTICLE_MARKER :
			case PARTICLE_FLASHER :
			case PARTICLE_SHOT_PLASMA :
			case PARTICLE_EXPLOSION :
			case PARTICLE_FRAGBURST :
				{
					Entity* player = [universe entityZero];
					if (!texName)
						[self initialiseTexture: textureNameString];
					if (player)
					{
						q_rotation = player->q_rotation;
						q_rotation.w = -q_rotation.w;
						quaternion_into_gl_matrix(q_rotation, rotMatrix);
					}
				}
				break;
		}
		switch (particle_type)
		{
			case PARTICLE_TEST :
				alpha = (sin(time_counter) + 2.0) / 3.0;
				break;
			
			case PARTICLE_EXPLOSION :
				[self updateExplosion:delta_t];
				break;
			
			case PARTICLE_HYPERRING :
				[self updateHyperring:delta_t];
				break;
			
			case PARTICLE_LASER_BEAM_RED :
			case PARTICLE_LASER_BEAM :
				[self updateLaser:delta_t];
				break;
			
			case PARTICLE_EXHAUST :
				break;
			
			case PARTICLE_ECM_MINE :
				[self updateECMMine:delta_t];
				break;
			
			case PARTICLE_ENERGY_MINE :
				[self updateEnergyMine:delta_t];
				break;
			
			case PARTICLE_FLASHER :
				[self updateFlasher:delta_t];
				break;
			
			case PARTICLE_SPARK :
				[self updateSpark:delta_t];
				break;
			
			case PARTICLE_FRAGBURST :
				[self updateFragburst:delta_t];
				break;
			
			case PARTICLE_SHOT_EXPIRED :
			case PARTICLE_SHOT_YELLOW_PLASMA :
			case PARTICLE_SHOT_GREEN_PLASMA :
			case PARTICLE_MARKER :
			case PARTICLE_SHOT_PLASMA :
				[self updateShot:delta_t];
				break;
		}
	}

}

- (void) updateExplosion:(double) delta_t
{
	[self setSize:NSMakeSize((1.0 + time_counter)*64.0,(1.0 + time_counter)*64.0)];
	alpha = (duration - time_counter);
	if (time_counter > duration)
		[universe removeEntity:self];
}

- (void) updateFlasher:(double) delta_t
{
//	NSLog(@"DEBUG updating flasher %@",self);
	alpha = 0.5 * sin(duration * PI * (time_counter + energy)) + 0.5;
}

- (void) updateECMMine:(double) delta_t
{
	if (time_counter > activation_time)
	{
		// do ecm stuff
		double radius = 0.5 * activation_time * SCANNER_MAX_RANGE;
		if (radius > SCANNER_MAX_RANGE)
			radius = SCANNER_MAX_RANGE;
		NSArray* targets = [universe getEntitiesWithinRange:radius ofEntity:self];
		if ([targets count] > 0)
		{
			int i;
			for (i = 0; i < [targets count]; i++)
			{
				Entity *e2 = [targets objectAtIndex:i];
				if (e2->isShip)
					[[(ShipEntity *)e2 getAI] reactToMessage:@"ECM"];
			}
		}
		activation_time += 0.5; // go off every half second
	}
	if (time_counter > duration)	// until the timer runs out!
		[universe removeEntity:self];
}

- (void) updateEnergyMine:(double) delta_t
{
	// new billboard routine (working at last!)
	Entity*	player = [universe entityZero];
	Vector v0 = position;
	Vector p0 = (player)? player->position : make_vector(0,0,0);
	v0.x -= p0.x;	v0.y -= p0.y;	v0.z -= p0.z; // vector from player to position
	
	v0 = unit_vector(&v0);
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
	//
	// end of new billboard routine
	
	double tf = time_counter / duration;
	double stf = tf * tf;
//	double srtf = sqrt(tf);
	double expansion_speed;
	if (time_counter > 0)
		expansion_speed = 240 + 10 / (tf * tf);
	if (expansion_speed > 1000.0)
		expansion_speed = 1000.0;
		
	velocity.z = expansion_speed;
	
	collision_radius += delta_t * expansion_speed;		// expand
	energy = 10000 - 9000 * tf;	// 10000 -> 1000
	
	alpha = 0.5 * ((0.025 / tf) + 1.0 - stf);
	if (alpha > 1.0)	alpha = 1.0;
	color_fv[0] = 1.0 - 5.0 * tf;
	if (color_fv[0] > 1.0)	color_fv[0] = 1.0;
	if (color_fv[0] < 0.0)	color_fv[0] = 0.25 * tf * randf();
	color_fv[1] = 1.0 - 5.0 * tf;
	if (color_fv[1] > 1.0)	color_fv[1] = 1.0;
	if (color_fv[1] < 0.0)	color_fv[1] = 0.0;
	if ([collidingEntities count] > 0)
	{
		int i;
		for (i = 0; i < [collidingEntities count]; i++)
		{
			Entity *	e = (Entity *)[collidingEntities objectAtIndex:i];
			[e takeEnergyDamage:energy from:self becauseOf:[self owner]];
//			if (e->isShip)
//			{
//				ShipEntity*	s = (ShipEntity*)e;
//				NSLog(@"DEBUG ENERGY BOMB Doing %.3f energy damage to %@ %d", energy, [s name], [s universal_id]);
//			}
		}
	}
	if (time_counter > duration)	// until the timer runs out!
		[universe removeEntity:self];
}

- (void) updateShot:(double) delta_t
{
	if ([collidingEntities count] > 0)
	{
		int i;
		for (i = 0; i < [collidingEntities count]; i++)
		{
			Entity *	e = (Entity *)[collidingEntities objectAtIndex:i];
			if (e != [self owner])
			{
//				NSLog(@"DEBUG %@ taking damage from %@", e, [self owner]);
				[e takeEnergyDamage:energy from:self becauseOf:[self owner]];
				velocity.x = 0.0;
				velocity.y = 0.0;
				velocity.z = 0.0;
				[self setColor:[NSColor redColor]];
				[self setSize:NSMakeSize(64.0,64.0)];
				duration = 2.0;
				time_counter = 0.0;
				particle_type = PARTICLE_EXPLOSION;
			}
		}
	}
	position.x += velocity.x * delta_t;
	position.y += velocity.y * delta_t;
	position.z += velocity.z * delta_t;
	alpha = (duration - time_counter);
	if (time_counter > duration)
		[universe removeEntity:self];
}

- (void) updateSpark:(double) delta_t
{
	position.x += velocity.x * delta_t;
	position.y += velocity.y * delta_t;
	position.z += velocity.z * delta_t;

	alpha = (duration - time_counter) / duration;
	if (alpha < 0.0)	alpha = 0.0;
	if (alpha > 1.0)	alpha = 1.0;
	
	// fade towards transparent red
	color_fv[0] = alpha * [color redComponent]		+ (1.0 - alpha) * 1.0;
	color_fv[1] = alpha * [color greenComponent];//	+ (1.0 - alpha) * 0.0;
	color_fv[2] = alpha * [color blueComponent];//	+ (1.0 - alpha) * 0.0;
	
	// disappear eventually
	if (time_counter > duration)
		[universe removeEntity:self];
}

- (void) updateLaser:(double) delta_t
{
	position.x += velocity.x * delta_t;
	position.y += velocity.y * delta_t;
	position.z += velocity.z * delta_t;
	alpha = (duration - time_counter) / PARTICLE_LASER_DURATION;
	if (time_counter > duration)
		[universe removeEntity:self];
}

- (void) updateHyperring:(double) delta_t
{
	position.x += velocity.x * delta_t;
	position.y += velocity.y * delta_t;
	position.z += velocity.z * delta_t;
	alpha = (duration - time_counter) / PARTICLE_LASER_DURATION;
	ring_inner_radius += delta_t * size.width * 1.1;
	ring_outer_radius += delta_t * size.height;
	if (time_counter > duration)
		[universe removeEntity:self];
}

- (void) updateFragburst:(double) delta_t
{
	int i;
//	int n_sparks = 48 * (duration - time_counter) / duration;
	//
	for (i = 0 ; i < n_vertices; i++)
	{
		GLfloat du = 0.5 + 0.03125 * (32 - i);
		GLfloat alf = 1.0 - time_counter / du;
		if (alf < 0.0)	alf = 0.0;
		if (alf > 1.0)	alf = 1.0;
		faces[i].red = alf * color_fv[0] + 1.0 - alf;
		faces[i].blue = alf;
		vertices[i].x += vertex_normal[i].x * delta_t;
		vertices[i].y += vertex_normal[i].y * delta_t;
		vertices[i].z += vertex_normal[i].z * delta_t;
	}
//	// disappear some sparks
//	if ((n_sparks > 0)&&(n_sparks < n_vertices))
//		n_vertices = n_sparks;
	
	// disappear eventually
	if (time_counter > duration)
		[universe removeEntity:self];
}

- (void) drawEntity:(BOOL) immediate :(BOOL) translucent;
{
	if ([universe breakPatternHide])   return;		// DON'T DRAW DURING BREAK PATTERN
	
	if ((particle_type == PARTICLE_FLASHER)&&(zero_distance > no_draw_distance))	return;	// TOO FAR AWAY TO SEE
	
	if (translucent)
	{
		switch (particle_type)
		{
			case PARTICLE_LASER_BEAM_RED :
				[self drawLaser];
				break;
			
			case PARTICLE_EXHAUST :
				[self drawExhaust: immediate];
				break;
				
			case PARTICLE_HYPERRING :
				[self drawHyperring];
				break;
				
			case PARTICLE_ECM_MINE :
				// not a visible entity
				break;
				
			case PARTICLE_ENERGY_MINE :
				[self drawEnergyMine];
				break;

			case PARTICLE_FRAGBURST :
				[self drawFragburst];
				break;
				
			default :
				[self drawParticle];
				break;
		}
	}
}

- (void) drawSubEntity:(BOOL) immediate :(BOOL) translucent
{
//	if (particle_type == PARTICLE_EXHAUST)
//	{
//		[super drawSubEntity:immediate :translucent];
//		return;
//	}
	if (particle_type == PARTICLE_EXHAUST)
	{
		if (translucent)
		{
			glPushMatrix();

			// position and orientation is relative to owner
			
			//NSLog(@"DEBUG drawing passive subentity at %.3f, %.3f, %.3f", position.x, position.y, position.z);
			
			glTranslated( position.x, position.y, position.z);
			glMultMatrixf(rotMatrix);
			
			[self drawExhaust:immediate];
				
			glPopMatrix();
		}
		
		return;
	}

	Entity* my_owner = [universe entityForUniversalID:owner];

	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
		//
		zero_distance = my_owner->zero_distance;
		if (zero_distance > no_draw_distance)
			return; // TOO FAR AWAY TO DRAW
	}
	
	if ((particle_type == PARTICLE_FLASHER)&&(status != STATUS_INACTIVE))
	{
		Vector abspos = position;  // in control of it's own orientation
		Entity*		father = my_owner;
		GLfloat*	r_mat = [father rotationMatrix];
		while (father)
		{
			mult_vector_gl_matrix(&abspos, r_mat);
			Vector pos = father->position;
			abspos.x += pos.x;	abspos.y += pos.y;	abspos.z += pos.z;
			if ([father owner] != father)
				father = [father owner];
			else
				father = nil;
			r_mat = [father rotationMatrix];
		}
		glPopMatrix();  // restore zero!
		glPushMatrix();
				// position and orientation is absolute
		glTranslated( abspos.x, abspos.y, abspos.z);
		glMultMatrixf(rotMatrix);
		
		[self drawEntity:immediate :translucent];
	}
}


- (void) drawParticle
{
    int viewdir;
	
	double  xx = size.width / 2.0;
	double  yy = size.height / 2.0;
	
	if (alpha < 0.0)
        alpha = 0.0;	// clamp the alpha value
    if (alpha > 1.0)
        alpha = 1.0;	// clamp the alpha value

    color_fv[3] = alpha;
    
	// movies:
	// draw data required xx, yy, color_fv[0], color_fv[1], color_fv[2]
	
	glDisable(GL_LIGHTING);
	glEnable(GL_TEXTURE_2D);
	glPushMatrix();
	
	if (particle_type == PARTICLE_FLASHER)
		glColor4f( color_fv[0], color_fv[1], color_fv[2], alpha);
	else
		glColor4f(1.0, 1.0, 1.0, alpha);
	
	glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, color_fv);

	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);

	glBindTexture(GL_TEXTURE_2D, texName);
	glBegin(GL_QUADS);
	
	viewdir = [universe viewDir];
	
	switch (viewdir)
	{
		case	VIEW_AFT :
			glTexCoord2f(0.0, 1.0);
			glVertex3f(xx, -yy, 0);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(-xx, -yy, 0);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(-xx, yy, 0);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(xx, yy, 0);
			break;
			
		case	VIEW_STARBOARD :
			glTexCoord2f(0.0, 1.0);
			glVertex3f(0, -yy, xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(0, -yy, -xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(0, yy, -xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(0, yy, xx);
			break;
			
		case	VIEW_PORT :
			glTexCoord2f(0.0, 1.0);
			glVertex3f(0, -yy, -xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(0, -yy, xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(0, yy, xx);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(0, yy, -xx);
			break;
			
		default :
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, 0);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, 0);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, 0);
			
			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, 0);
			break;
	}

	glEnd();
	
	glPopMatrix();
	glDisable(GL_TEXTURE_2D);
	glEnable(GL_LIGHTING);
}

- (void) drawLaser
{
	GLfloat flat_ambdiff[4]		= {1.0, 1.0, 1.0, 1.0};   // for alpha
	GLfloat lase_ambdiff[4]		= {0.0, 0.0, 0.0, 1.0};   // for alpha
    GLfloat mat_no[4]		= {0.0, 0.0, 0.0, 1.0};   // nothing
	double  lase_alpha = 0.75;
	
	color_fv[3]		= lase_alpha;  // set alpha
	lase_ambdiff[3] = lase_alpha;  // set alpha
	
	glDisable(GL_CULL_FACE);			// face culling
		
//	NSLog(@"drawing laser %.0f long with lase_ambdiff (%0.3f, %0.3f, %0.3f, %0.3f) color_fv (%0.3f, %0.3f, %0.3f, %0.3f)", collision_radius,
//		lase_ambdiff[0], lase_ambdiff[1], lase_ambdiff[2], lase_ambdiff[3],
//		color_fv[0], color_fv[1], color_fv[2], color_fv[3]);
	
//	//state check
//	NSLog(@"DEBUG OpenGL state check: GL_COLOR_MATERIAL : %@",
//		(glIsEnabled(GL_COLOR_MATERIAL) == GL_TRUE)? @"YES":@"NO");
	
	// movies:
	// draw data required collision_radius, color_fv[0], color_fv[1], color_fv[2]
	
	glDisable(GL_LIGHTING);
	
	glEnable( GL_COLOR_MATERIAL);
	glColorMaterial( GL_FRONT_AND_BACK, GL_EMISSION);
	glColor4fv( color_fv);
	
	glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, mat_no);
	glMaterialfv( GL_FRONT_AND_BACK, GL_SPECULAR, mat_no);
//	glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, color_fv);
	
	glBegin(GL_QUADS);
	
	glVertex3f(0.25, 0.0, 0.0);
	glVertex3f(0.25, 0.0, collision_radius);
	glVertex3f(-0.25, 0.0, collision_radius);
	glVertex3f(-0.25, 0.0, 0.0);
	
	glVertex3f(0.0, 0.25, 0.0);
	glVertex3f(0.0, 0.25, collision_radius);
	glVertex3f(0.0, -0.25, collision_radius);
	glVertex3f(0.0, -0.25, 0.0);
	
	glEnd();
	
	glDisable( GL_COLOR_MATERIAL);
	
	glMaterialfv( GL_FRONT_AND_BACK, GL_EMISSION, mat_no);
	glMaterialfv( GL_FRONT_AND_BACK, GL_SPECULAR, mat_no);
	glMaterialfv( GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff);
	
	glEnable( GL_LIGHTING);
	
	glEnable(GL_CULL_FACE);			// face culling
}

- (void) drawExhaust:(BOOL) immediate
{
    int fi, vi;
	
	GLfloat flat_ambdiff[4] = {1.0, 1.0, 1.0, 1.0};   // flat white
	GLfloat ex_ambdiff[4]	= {0.0, 0.0, 0.0, 1.0};   // flat black
	GLfloat ex_emissive[4]	= {0.6, 0.8, 1.0, 0.9};   // pale blue
    GLfloat no_mat[4]		= {0.0, 0.0, 0.0, 1.0};   // flat black
	
	ShipEntity  *ship =(ShipEntity *)[universe entityForUniversalID:owner];
	int dam = [ship damage];
	double flare_length = [ship speed_factor];
	
	if (!ship)
	{
//		NSLog(@"DEBUG exhaust '%@' has no owner", self);
		return;
	}
	
	if (flare_length == 0.0)	// don't draw if there's no fire!
	{
//		NSLog(@"DEBUG ship '%@' has no exhaust because of no speed", [ship name]);
		return;
	}
	
	double flare_factor = flare_length * ex_emissive[3];
	double red_factor = flare_length * ex_emissive[0] * (ranrot_rand() % 11) * 0.1;	// random fluctuations
	double green_factor = flare_length * ex_emissive[1];
	//double blue_factor = flare_length * ex_emissive[2];
	
	if (flare_length > 1.0)	// afterburner!
	{
		red_factor = 1.5;
		flare_length = 1.0 + 0.25 * flare_length;
	}
	
	if ((ranrot_rand() % 50) < dam - 50)   // flicker the damaged engines
		red_factor = 0.0;
	if ((ranrot_rand() % 40) < dam - 60)
		green_factor = 0.0;
	if ((ranrot_rand() % 25) < dam - 75)
		flare_factor = 0.0;
	
	if (flare_length < 0.1)   flare_length = 0.1;	

	// movies:
	// draw data required flare_factor, red_factor, green_factor, flare_length
	
	if (basefile)
	{
		glDisable(GL_CULL_FACE);			// face culling
		glShadeModel(GL_SMOOTH);
		
//		glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, ex_zero);	// causes TIGER BLACK TEXTURE PROBLEM?
		glBegin(GL_TRIANGLES);
		for (fi = 0; fi < n_faces; fi++)
		{
			for (vi = 0; vi < 3; vi++)
			{
				int v = faces[fi].vertex[vi];
				ex_ambdiff[3] = flare_factor * alpha_for_vertex[v];		// fade alpha towards rear of exhaust
				ex_emissive[3] = flare_factor * alpha_for_vertex[v];	// fade alpha towards rear of exhaust
				ex_emissive[1] = green_factor * alpha_for_vertex[v];	// diminish green part towards rear of exhaust
				ex_emissive[0] = red_factor * alpha_for_vertex[v];		// diminish red part towards rear of exhaust
				glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, ex_ambdiff);
				glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, ex_emissive);
				glNormal3f(vertex_normal[v].x,vertex_normal[v].y,vertex_normal[v].z);
				glVertex3f(vertices[v].x, vertices[v].y, vertices[v].z * flare_length);
			}
			
		}
		glEnd();
		glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff);
		glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, no_mat);

		glEnable(GL_CULL_FACE);			// face culling
	}
}

- (void) drawHyperring
{
    int i;
	GLfloat aleph = (alpha*0.5 < 1.0) ? alpha*0.5 : 1.0;
	
    GLfloat ex_zero[4]		= {0.0, 0.0, 0.0, 1.0};		// black
	GLfloat flat_ambdiff[4] = {1.0, 1.0, 1.0, 1.0};		// flat
	GLfloat ex_ambdiff[4]	= {0.0, 0.0, 0.0, aleph};		// black
	GLfloat ex_em_hi[4]		= {0.6, 0.8, 1.0, aleph};   // pale blue
	GLfloat ex_em_lo[4]		= {0.2, 0.0, 1.0, 0.0};		// purplish-blue-black
	
	glPushMatrix();
	glDisable(GL_CULL_FACE);			// face culling
	glShadeModel(GL_SMOOTH);

	//NSLog(@"... drawing hyppering inner_radius:%.1f  alpha:%.2f", ring_inner_radius, aleph);
	
	// movies:
	// draw data required ring_inner_radius, ring_outer_radius
	
	glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, ex_zero);
	glBegin(GL_TRIANGLE_STRIP);
	for (i = 0; i < 65; i++)
	{
		glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, ex_em_lo);
		glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, ex_em_lo);
		glVertex3f( ring_inner_radius*circleVertex[i].x, ring_inner_radius*circleVertex[i].y, ring_inner_radius*circleVertex[i].z );
		glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, ex_ambdiff);
		glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, ex_em_hi);
		glVertex3f( ring_outer_radius*circleVertex[i].x, ring_outer_radius*circleVertex[i].y, ring_outer_radius*circleVertex[i].z );
	}
	glEnd();
	glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, ex_zero);
	glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff);

	glEnable(GL_CULL_FACE);			// face culling
	glPopMatrix();
}

- (void) drawEnergyMine
{
	double szd = sqrt(zero_distance);
	
	GLfloat flat_ambdiff[4]		= {1.0, 1.0, 1.0, 1.0};   // for alpha
	GLfloat bomb_ambdiff[4]		= {0.0, 0.0, 0.0, 1.0};   // for alpha
    GLfloat bomb_zero[4]		= {0.0, 0.0, 0.0, 1.0};   // nothing
	
	color_fv[3]		= alpha;  // set alpha
	bomb_ambdiff[3] = alpha;  // set alpha
	
	glDisable(GL_CULL_FACE);			// face culling
	
	glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, bomb_ambdiff);
	glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, color_fv);
	
	int step = 4;

	drawBall( collision_radius, step, szd);
	
//	NSLog(@"DEBUG ENERGY BOMB radius: %.3f, expansion: %.3f, color: [ %.3f, %.3f, %.3f, %.3f]", collision_radius, velocity.z, color_fv[0], color_fv[1], color_fv[2], alpha);
	
	glMaterialfv(GL_FRONT_AND_BACK, GL_EMISSION, bomb_zero);
	glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE, flat_ambdiff);
	
	glEnable(GL_CULL_FACE);			// face culling
}

- (void) drawFragburst
{
    int viewdir, i;
	GLfloat	colr[4];
	
	GLfloat  xx = size.width / 2.0;
	GLfloat  yy = size.height / 2.0;
	
	viewdir = [universe viewDir];
	
	glDisable(GL_LIGHTING);
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);
	glBindTexture(GL_TEXTURE_2D, texName);
	glPushMatrix();

	glBegin(GL_QUADS);
	for (i = 0; i < n_vertices; i++)
	{
		colr[0] = faces[i].red;
		colr[1] = color_fv[1];
		colr[2] = color_fv[2];
		colr[3] = faces[i].blue;
		glColor4f(1.0, 1.0, 1.0, faces[i].blue);
		glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, colr);
		
		GLfloat x = vertices[i].x;
		GLfloat y = vertices[i].y;
		GLfloat z = vertices[i].z;
		switch (viewdir)
		{
			case	VIEW_AFT :
				glTexCoord2f(0.0, 1.0);	glVertex3f(x+xx, y-yy, z);
				glTexCoord2f(1.0, 1.0);	glVertex3f(x-xx, y-yy, z);
				glTexCoord2f(1.0, 0.0);	glVertex3f(x-xx, y+yy, z);
				glTexCoord2f(0.0, 0.0);	glVertex3f(x+xx, y+yy, z);
				break;
			case	VIEW_STARBOARD :
				glTexCoord2f(0.0, 1.0);	glVertex3f(x, y-yy, z+xx);
				glTexCoord2f(1.0, 1.0);	glVertex3f(x, y-yy, z-xx);
				glTexCoord2f(1.0, 0.0);	glVertex3f(x, y+yy, z-xx);
				glTexCoord2f(0.0, 0.0);	glVertex3f(x, y+yy, z+xx);
				break;
			case	VIEW_PORT :
				glTexCoord2f(0.0, 1.0);	glVertex3f(x, y-yy, z-xx);
				glTexCoord2f(1.0, 1.0);	glVertex3f(x, y-yy, z+xx);
				glTexCoord2f(1.0, 0.0);	glVertex3f(x, y+yy, z+xx);
				glTexCoord2f(0.0, 0.0);	glVertex3f(x, y+yy, z-xx);
				break;
			default :
				glTexCoord2f(0.0, 1.0);	glVertex3f(x-xx, y-yy, z);
				glTexCoord2f(1.0, 1.0);	glVertex3f(x+xx, y-yy, z);
				glTexCoord2f(1.0, 0.0);	glVertex3f(x+xx, y+yy, z);
				glTexCoord2f(0.0, 0.0);	glVertex3f(x-xx, y+yy, z);
				break;
		}
	}
	glEnd();
	
	glPopMatrix();
	glDisable(GL_TEXTURE_2D);
	glEnable(GL_LIGHTING);
}

@end
