/*

ParticleEntity.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "ParticleEntity.h"

#import "Universe.h"
#import "AI.h"
#import "OOColor.h"
#import "OOTexture.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"

#import "ShipEntity.h"
#import "PlayerEntity.h"
#import "PlanetEntity.h"


/*	Entities that can easily be migrated to OOLightParticleEntity:
	PARTICLE_FLASH
*/


typedef enum
{
	PARTICLE_LASER_BEAM			= 160,
	PARTICLE_FLASH				= 230,
	PARTICLE_FRAGBURST			= 250,
	PARTICLE_BURST2				= 270,
	PARTICLE_ENERGY_MINE		= 500,
	PARTICLE_BILLBOARD			= 700,
	PARTICLE_HYPERRING			= 800
} OOParticleType;


@interface ParticleEntity (OOPrivate)

- (void) updateEnergyMine:(double) delta_t;
- (void) updateSpark:(double) delta_t;
- (void) updateLaser:(double) delta_t;
- (void) updateHyperring:(double) delta_t;
- (void) updateFragburst:(double) delta_t;
- (void) updateBurst2:(double) delta_t;
- (void) updateExhaust2:(double) delta_t;
- (void) updateFlash:(double) delta_t;

- (void) drawParticle;
- (void) drawLaser;
- (void) drawExhaust2;
- (void) drawHyperring;
- (void) drawEnergyMine;
- (void) drawFragburst;
- (void) drawBurst2;
- (void) drawBillboard;

- (void) setTexture:(NSString *) filename;
- (void) setParticleType:(OOParticleType) p_type;
- (OOParticleType) particleType;

@end


#ifndef ADDITIVE_BLENDING
#define ADDITIVE_BLENDING	1
#endif

#if ADDITIVE_BLENDING
static inline void BeginAdditiveBlending(BOOL withGL_ONE)
{
//	OOGL(glPushAttrib(GL_COLOR_BUFFER_BIT));
	OOGL(glEnable(GL_BLEND));
	if (withGL_ONE)
	{
		OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
	}
	else
	{
		OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));
	}
}


static inline void EndAdditiveBlending(void)
{
//	OOGL(glPopAttrib());	// Handled by "master" pop in drawEntity:
}

#define GL_ONE_YES	YES
#define GL_ONE_NO	NO
#else
#define BeginAdditiveBlending(x)	do {} while (0)
#define EndAdditiveBlending()	do {} while (0)
#endif


static void DrawQuadForView(GLfloat x, GLfloat y, GLfloat z, GLfloat xx, GLfloat yy);



static Vector circleVertex[65];		// holds vector coordinates for a unit circle

@implementation ParticleEntity

+ (void)initialize
{
	unsigned			i;
	for (i = 0; i < 65; i++)
	{
		circleVertex[i].x = sin(i * M_PI / 32.0);
		circleVertex[i].y = cos(i * M_PI / 32.0);
		circleVertex[i].z = 0.0;
	}
}


- (id) init
{
	if ((self = [super init]))
	{
		[self setStatus:STATUS_EFFECT];
		
		basefile = @"Particle";
		[self setTexture:@"blur256.png"];
		[self setColor:[OOColor greenColor]];
		
		size = NSMakeSize(32.0,32.0);
		collision_radius = 32.0;
	}
	return self;
}


- (id) initLaserFromShip:(ShipEntity *) srcEntity view:(OOViewID) view offset:(Vector)offset
{
	ShipEntity			*ship = [srcEntity rootShipEntity];
	BoundingBox 		bbox = [srcEntity boundingBox];
	float				midx = 0.5 * (bbox.max.x + bbox.min.x);
	float				midz = 0.5 * (bbox.max.z + bbox.min.z);
	
	self = [super init];
	if (self == nil)  goto FAIL;
	
#ifndef NDEBUG
	if (![srcEntity isShip])  goto FAIL;
	if (ship == nil)  goto FAIL;
#endif
	
	[self setStatus:STATUS_EFFECT];
	
	Vector middle = make_vector(midx, 0.5 * (bbox.max.y + bbox.min.y), midz);
	if (ship == srcEntity) 
	{
		// main laser offset
		position = vector_add([ship position],OOVectorMultiplyMatrix(offset, [ship drawRotationMatrix]));
	}
	else
	{
		// subentity laser
		position = [srcEntity absolutePositionForSubentityOffset:middle];
	}
	
	orientation = [ship normalOrientation];
	Vector v_up = vector_up_from_quaternion(orientation);
	Vector v_forward = vector_forward_from_quaternion(orientation);
	Vector v_right = vector_right_from_quaternion(orientation);
	velocity = vector_multiply_scalar(v_forward, [ship flightSpeed]);
	
	Vector	viewOffset;
	switch (view)
	{
		default:
		case VIEW_AFT:
			quaternion_rotate_about_axis(&orientation, v_up, M_PI);	
		case VIEW_FORWARD:
			viewOffset = vector_multiply_scalar(v_forward, midz);
			break;

		case VIEW_PORT:
			quaternion_rotate_about_axis(&orientation, v_up, M_PI/2.0);
			viewOffset = vector_multiply_scalar(v_right, midx);
			break;
			
		case VIEW_STARBOARD:
			quaternion_rotate_about_axis(&orientation, v_up, -M_PI/2.0);
			viewOffset = vector_multiply_scalar(v_right, midx);
			break;
	}
	position = vector_add(position, viewOffset);
	rotMatrix = OOMatrixForQuaternionRotation(orientation);
	
	time_counter = 0.0;
	
	particle_type = PARTICLE_LASER_BEAM;
	
	[self setColor:[OOColor redColor]];
	
	duration = PARTICLE_LASER_DURATION;
	
	[self setOwner:ship];
	
	collision_radius = [srcEntity weaponRange];
	
	return self;
	
FAIL:
	[self release];
	return nil;
}


- (id) initEnergyMineFromShip:(ShipEntity *) ship
{
	if (ship == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		time_counter = 0.0;
		duration = 20.0;
		position = ship->position;
		
		[self setVelocity: kZeroVector];
		
		[self setColor:[OOColor blueColor]];
		
		alpha = 0.5;
		collision_radius = 0;
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_MINE;
		
		particle_type = PARTICLE_ENERGY_MINE;
		
		[self setOwner:[ship owner]];
	}
	
	return self;
}


- (id) initHyperringFromShip:(ShipEntity *) ship
{
	if (ship == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		time_counter = 0.0;
		duration = 2.0;
		size.width = ship->collision_radius * 0.5;
		size.height = size.width * 1.25;
		ring_inner_radius = size.width;
		ring_outer_radius = size.height;
		position = ship->position;
		[self setOrientation:ship->orientation];
		[self setVelocity:[ship velocity]];
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_NO_DRAW;
		
		particle_type = PARTICLE_HYPERRING;
		
		[self setOwner:ship];
	}
	
	return self;
}


- (id) initFragburstSize:(GLfloat) fragSize fromPosition:(Vector) fragPos
{
	if ((self = [super init]))
	{
		int speed_low = 100;
		int speed_high = 400;
		int n_fragments = 0.4 * fragSize;
		if (n_fragments > 63)  n_fragments = 63;	// must also be less than MAX_FACES_PER_ENTITY
		n_fragments |= 12;
		int i;
		
		basefile = @"Particle";
		[self setTexture:@"blur256.png"];
		
		size = NSMakeSize(fragSize, fragSize);
		
		vertexCount = n_fragments;
		time_counter = 0.0;
		duration = 1.5;
		position = fragPos;
		[self setColor:[OOColor colorWithCalibratedHue:0.12 + 0.08 * randf() saturation:1.0 brightness:1.0 alpha:1.0]]; // yellow/orange (0.12) through yellow (0.1667) to yellow/slightly green (0.20)
		
		for (i = 0 ; i < n_fragments; i++)
		{
			GLfloat speed = speed_low + 0.5 * (randf()+randf()) * (speed_high - speed_low);	// speed tends toward mean of speed_high and speed_low
			vertices[i] = kZeroVector;	// position
			vertex_normal[i] = make_vector(randf() - 0.5, randf() - 0.5, randf() - 0.5);
			vertex_normal[i] = vector_normal(vertex_normal[i]);
			vertex_normal[i].x *= speed;	// velocity
			vertex_normal[i].y *= speed;
			vertex_normal[i].z *= speed;
			Vector col = make_vector(color_fv[0] * 0.1 * (9.5 + randf()), color_fv[1] * 0.1 * (9.5 + randf()), color_fv[2] * 0.1 * (9.5 + randf()));
			col = vector_normal(col);
			faces[i].red	= col.x;
			faces[i].green	= col.y;
			faces[i].blue	= col.z;
			faces[i].normal.x = 16.0 * speed_low / speed;
		}
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_NO_DRAW;
		
		particle_type = PARTICLE_FRAGBURST;
		
		collision_radius = 0;
		energy = 0;
	}
	
	return self;
}


- (id) initBurst2Size:(GLfloat) burstSize fromPosition:(Vector) fragPos
{
	if ((self = [super init]))
	{
		int speed_low = 1 + burstSize * 0.5;
		int speed_high = speed_low * 4;
		int n_fragments = 0.2 * burstSize;
		if (n_fragments > 15)  n_fragments = 15;	// must also be less than MAX_FACES_PER_ENTITY
		n_fragments |= 3;
		int i;
		
		basefile = @"Particle";
		[self setTexture:@"blur256.png"];
		
		size = NSMakeSize(burstSize, burstSize);
		
		vertexCount = n_fragments;
		time_counter = 0.0;
		duration = 1.0;
		position = fragPos;
		
		[self setColor:[[OOColor yellowColor] blendedColorWithFraction:0.5 ofColor:[OOColor whiteColor]]];
		
		for (i = 0 ; i < n_fragments; i++)
		{
			GLfloat speed = speed_low + 0.5 * (randf()+randf()) * (speed_high - speed_low);	// speed tends toward mean of speed_high and speed_low
			vertices[i] = kZeroVector;	// position
			vertex_normal[i] = make_vector(randf() - 0.5, randf() - 0.5, randf() - 0.5);
			vertex_normal[i] = vector_normal(vertex_normal[i]);
			vertex_normal[i].x *= speed;	// velocity
			vertex_normal[i].y *= speed;
			vertex_normal[i].z *= speed;
			Vector col = make_vector(color_fv[0] * 0.1 * (9.5 + randf()), color_fv[1] * 0.1 * (9.5 + randf()), color_fv[2] * 0.1 * (9.5 + randf()));
			col = vector_normal(col);
			faces[i].red = col.x;
			faces[i].green = col.y;
			faces[i].blue = col.z;
			faces[i].normal.z = 1.0;
		}
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_NO_DRAW;
		
		particle_type = PARTICLE_BURST2;
		
		collision_radius = 0;
		energy = 0;
	}
	
	return self;
}

// used exclusively for explosion flashes
- (id) initFlashSize:(GLfloat) flashSize fromPosition:(Vector) fragPos
{
	self = [self initFlashSize:flashSize fromPosition:fragPos color:[OOColor whiteColor]];
	if (self != nil)
	{
		if (growth_rate < 6000.0)  growth_rate = 6000.0;
		duration = 0.4;
	}
	
	return self;
}

// used for laser flashes
- (id) initFlashSize:(GLfloat) flashSize fromPosition:(Vector) fragPos color:(OOColor*) flashColor
{
	if ((self = [super init]))
	{
		basefile = @"Particle";
		[self setTexture:@"flare256.png"];
		
		size = NSMakeSize(flashSize, flashSize);
		
		growth_rate = 150.0 * flashSize; // if average flashSize is 80 then this is 12000
		
		time_counter = 0.0;
		duration = 0.3;
		position = fragPos;
		
		[self setColor:flashColor];
		color_fv[3] = 1.0;
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_NO_DRAW;
		
		particle_type = PARTICLE_FLASH;
		
		collision_radius = 0;
		energy = 0;
		
		[self setVelocity: kZeroVector];
	}
	return self;
}

// used for background billboards
- (id) initBillboard:(NSSize) billSize withTexture:(NSString*) textureFile
{
	if ((self = [super init]))
	{
		basefile = @"Particle";
		[self setTexture:textureFile];
		if (texture == nil)
		{
			[self release];
			return nil;
		}
		
		size = billSize;
		
		time_counter = 0.0;
		duration = 0.0;	//infinite
		
		[self setColor:[OOColor whiteColor]];
		color_fv[3] = 1.0;
		
		[self setStatus:STATUS_EFFECT];
		scanClass = CLASS_NO_DRAW;
		
		particle_type = PARTICLE_BILLBOARD;
		
		collision_radius = 0;
		energy = 0;
		
		[self setVelocity: kZeroVector];
		[self setPosition: make_vector(0.0f, 0.0f, 640.0f)];
	}
	return self;
}


- (void) dealloc
{
	[texture release];
	[color release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
#ifndef NDEBUG
	NSString *type_string = nil;
	switch ([self particleType])
	{
#define CASE(x) case x: type_string = @#x; break;
		CASE(PARTICLE_LASER_BEAM);
		CASE(PARTICLE_FLASH);
		CASE(PARTICLE_FRAGBURST);
		CASE(PARTICLE_BURST2);
		CASE(PARTICLE_ENERGY_MINE);
		CASE(PARTICLE_BILLBOARD);
		CASE(PARTICLE_HYPERRING);
	}
	if (type_string == nil)  type_string = [NSString stringWithFormat:@"UNKNOWN (%i)", particle_type];
	
	return [NSString stringWithFormat:@"%@ ttl: %.3fs", type_string, duration - time_counter];
#else
	return [NSString stringWithFormat:@"ttl: %.3fs", duration - time_counter];
#endif
}


- (BOOL) canCollide
{
	if (particle_type == PARTICLE_ENERGY_MINE)
	{
		return time_counter > 0.05;
	}
	return NO;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (particle_type == PARTICLE_ENERGY_MINE)
		return YES;
	if (other == [self owner])
		return NO;
	return ![other isParticle];
}


- (void) setTexture:(NSString *)name
{
	if (name != nil)
	{
		[texture autorelease];
		texture = [[OOTexture textureWithName:name inFolder:@"Textures"] retain];
	}
}


- (void) setColor:(OOColor *) a_color
{
	if (!a_color)  return;
	
	OOColor *rgbColor = a_color;

	[color release];
	color = [rgbColor retain];

	color_fv[0] = [color redComponent];
	color_fv[1] = [color greenComponent];
	color_fv[2] = [color blueComponent];
}



- (void) setParticleType:(OOParticleType) p_type
{
	particle_type = p_type;
}


- (OOParticleType) particleType
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


- (void) update:(OOTimeDelta) delta_t
{
	[super update:delta_t];

	time_counter += delta_t;

	if (UNIVERSE)
	{
		switch ([self particleType])
		{
			case PARTICLE_FRAGBURST:
			case PARTICLE_BURST2:
			case PARTICLE_FLASH:
				{
					PlayerEntity *player = [PlayerEntity sharedPlayer];
					assert(player != nil);
					rotMatrix = [player drawRotationMatrix];
				}
				break;
			default:
				break;
				
		}
		switch ([self particleType])
		{
			case PARTICLE_HYPERRING:
				[self updateHyperring:delta_t];
				break;

			case PARTICLE_LASER_BEAM:
				[self updateLaser:delta_t];
				break;
				
			case PARTICLE_ENERGY_MINE:
				[self updateEnergyMine:delta_t];
				break;

			case PARTICLE_FRAGBURST:
				[self updateFragburst:delta_t];
				break;

			case PARTICLE_BURST2:
				[self updateBurst2:delta_t];
				break;

			case PARTICLE_FLASH:
				[self updateFlash:delta_t];
				break;

			case PARTICLE_BILLBOARD:
				break;
			
			default:
				OOLog(@"particle.unknown", @"Invalid particle %@, removing.", self);
				[UNIVERSE removeEntity:self];
		}
	}

}


- (void) updateEnergyMine:(double) delta_t
{
	// new billboard routine (working at last!)
	PlayerEntity	*player = [PlayerEntity sharedPlayer];
	assert(player != nil);
	rotMatrix = OOMatrixForBillboard(position, [player position]);
	
	GLfloat tf = time_counter / duration;
	GLfloat stf = tf * tf;
	GLfloat expansion_speed = 0.0;
	if (time_counter > 0)
		expansion_speed = 240 + 10 / (tf * tf);
	if (expansion_speed > 1000.0)
		expansion_speed = 1000.0;
	
	velocity.z = expansion_speed;
	
	collision_radius += delta_t * expansion_speed;		// expand
//	energy = 10000 - 9000 * tf;	// 10000 -> 1000
	energy = delta_t * (100000 - 90000 * tf);	// adjusted to take into account delta_t

	alpha = 0.5 * ((0.025 / tf) + 1.0 - stf);
	if (alpha > 1.0)	alpha = 1.0;
	color_fv[0] = 1.0 - 5.0 * tf;
	if (color_fv[0] > 1.0)	color_fv[0] = 1.0;
	if (color_fv[0] < 0.0)	color_fv[0] = 0.25 * tf * randf();
	color_fv[1] = 1.0 - 5.0 * tf;
	if (color_fv[1] > 1.0)	color_fv[1] = 1.0;
	if (color_fv[1] < 0.0)	color_fv[1] = 0.0;
	
	// manageCollisions
	if ([collidingEntities count] > 0)
	{
		unsigned i;
		for (i = 0; i < [collidingEntities count]; i++)
		{
			Entity *	e = (Entity *)[collidingEntities objectAtIndex:i];
			[e takeEnergyDamage:energy from:self becauseOf:[self owner]];
		}
	}
	
	// expire after ttl
	if (time_counter > duration)	// until the timer runs out!
		[UNIVERSE removeEntity:self];
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
		[UNIVERSE removeEntity:self];
}


- (void) updateLaser:(double) delta_t
{
	position.x += velocity.x * delta_t;
	position.y += velocity.y * delta_t;
	position.z += velocity.z * delta_t;
	alpha = (duration - time_counter) / PARTICLE_LASER_DURATION;
	if (time_counter > duration)
		[UNIVERSE removeEntity:self];
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
		[UNIVERSE removeEntity:self];
}


- (void) updateFragburst:(double) delta_t
{
	int i;
	
	for (i = 0 ; i < vertexCount; i++)
	{
		GLfloat du = 0.5 + 0.03125 * (32 - i);
		GLfloat alf = 1.0 - time_counter / du;
		if (alf < 0.0)	alf = 0.0;
		if (alf > 1.0)	alf = 1.0;
		faces[i].normal.z = alf;
		vertices[i].x += vertex_normal[i].x * delta_t;
		vertices[i].y += vertex_normal[i].y * delta_t;
		vertices[i].z += vertex_normal[i].z * delta_t;
	}

	// disappear eventually
	if (time_counter > duration)
		[UNIVERSE removeEntity:self];
}


- (void) updateBurst2:(double) delta_t
{
	int i;
	size.width = (1.0 + time_counter) * size.height;	// current size vs starting size
	
	GLfloat di = 1.0 / (vertexCount - 1);
	for (i = 0 ; i < vertexCount; i++)
	{
		GLfloat du = duration * (0.5 + di * i);
		GLfloat alf = 1.0 - time_counter / du;
		if (alf < 0.0)	alf = 0.0;
		if (alf > 1.0)	alf = 1.0;
		faces[i].normal.z = alf;
		vertices[i].x += vertex_normal[i].x * delta_t;
		vertices[i].y += vertex_normal[i].y * delta_t;
		vertices[i].z += vertex_normal[i].z * delta_t;
	}

	// disappear eventually
	if (time_counter > duration)
		[UNIVERSE removeEntity:self];
}


- (void) updateFlash:(double) delta_t
{
	GLfloat tf = duration * 0.667;
	GLfloat tf1 = duration - tf;

	// move as necessary
	position.x += velocity.x * delta_t;
	position.y += velocity.y * delta_t;
	position.z += velocity.z * delta_t;

	// scale up
	size.width += delta_t * growth_rate;
	size.height = size.width;

	// fade up
	if ((time_counter)&&(time_counter < tf))
		alpha = time_counter/tf;

	// fade out
	if (time_counter > tf)
		alpha = (duration - time_counter)/tf1;

	// disappear eventually
	if (time_counter > duration)
		[UNIVERSE removeEntity:self];

}


- (void) drawEntity:(BOOL) immediate:(BOOL) translucent;
{
	if ([UNIVERSE breakPatternHide])  return;
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	if (translucent)
	{
		switch ([self particleType])
		{
			case PARTICLE_LASER_BEAM:
				[self drawLaser];
				break;
				
			case PARTICLE_HYPERRING:
				[self drawHyperring];
				break;
				
			case PARTICLE_ENERGY_MINE:
				[self drawEnergyMine];
				break;
				
			case PARTICLE_FRAGBURST:
				[self drawFragburst];
				break;
				
			case PARTICLE_BURST2:
				[self drawBurst2];
				break;
				
			case PARTICLE_BILLBOARD:
				[self drawBillboard];
				break;
				
			default:
				[self drawParticle];
				break;
		}
	}
	
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"ParticleEntity after drawing %@ %@", self);
}


- (void) drawParticle
{
	int viewdir;

	GLfloat	xx = 0.5 * size.width;
	GLfloat	yy = 0.5 * size.height;

	alpha = OOClamp_0_1_f(alpha);
	color_fv[3] = alpha;
	
	// movies:
	// draw data required xx, yy, color_fv[0], color_fv[1], color_fv[2]
	
	OOGL(glEnable(GL_TEXTURE_2D));
	
	OOGL(glColor4fv(color_fv));
	
	OOGL(glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, color_fv));
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND));
	
	[texture apply];
	
	BeginAdditiveBlending(GL_ONE_YES);

	OOGLBEGIN(GL_QUADS);

	viewdir = [UNIVERSE viewDirection];

	switch (viewdir)
	{
		case VIEW_FORWARD:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, -xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, -xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, -xx);

			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, -xx);
			break;
			
		case	VIEW_AFT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(xx, -yy, xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(-xx, -yy, xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(-xx, yy, xx);

			glTexCoord2f(0.0, 0.0);
			glVertex3f(xx, yy, xx);
			break;

		case	VIEW_STARBOARD:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(-xx, -yy, -xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(-xx, yy, -xx);

			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, xx);
			break;

		case	VIEW_PORT:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(xx, -yy, -xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, xx);

			glTexCoord2f(0.0, 0.0);
			glVertex3f(xx, yy, -xx);
			break;

		case	VIEW_CUSTOM:
			{
				PlayerEntity *player = [PlayerEntity sharedPlayer];
				Vector vi = [player customViewRightVector];		vi.x *= xx;	vi.y *= xx;	vi.z *= xx;
				Vector vj = [player customViewUpVector];		vj.x *= yy;	vj.y *= yy;	vj.z *= yy;
				Vector vk = [player customViewForwardVector];	vk.x *= xx;	vk.y *= xx;	vk.z *= xx;
				glTexCoord2f(0.0, 1.0);
				glVertex3f(-vi.x -vj.x -vk.x, -vi.y -vj.y -vk.y, -vi.z -vj.z -vk.z);
				glTexCoord2f(1.0, 1.0);
				glVertex3f(+vi.x -vj.x -vk.x, +vi.y -vj.y -vk.y, +vi.z -vj.z -vk.z);
				glTexCoord2f(1.0, 0.0);
				glVertex3f(+vi.x +vj.x -vk.x, +vi.y +vj.y -vk.y, +vi.z +vj.z -vk.z);
				glTexCoord2f(0.0, 0.0);
				glVertex3f(-vi.x +vj.x -vk.x, -vi.y +vj.y -vk.y, -vi.z +vj.z -vk.z);
			}
			break;
		
		default:
			glTexCoord2f(0.0, 1.0);
			glVertex3f(-xx, -yy, -xx);

			glTexCoord2f(1.0, 1.0);
			glVertex3f(xx, -yy, -xx);

			glTexCoord2f(1.0, 0.0);
			glVertex3f(xx, yy, -xx);

			glTexCoord2f(0.0, 0.0);
			glVertex3f(-xx, yy, -xx);
			break;
	}
	OOGLEND();
	
	EndAdditiveBlending();
	OOGL(glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE));
}


- (void) drawLaser
{
	color_fv[3]		= 0.75;  // set alpha
	
	OOGL(glDisable(GL_CULL_FACE));	// face culling
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glColor4fv(color_fv));
	
	BeginAdditiveBlending(GL_ONE_NO);

	OOGLBEGIN(GL_QUADS);
		glVertex3f(0.25, 0.0, 0.0);
		glVertex3f(0.25, 0.0, collision_radius);
		glVertex3f(-0.25, 0.0, collision_radius);
		glVertex3f(-0.25, 0.0, 0.0);
		
		glVertex3f(0.0, 0.25, 0.0);
		glVertex3f(0.0, 0.25, collision_radius);
		glVertex3f(0.0, -0.25, collision_radius);
		glVertex3f(0.0, -0.25, 0.0);
	OOGLEND();
	
	EndAdditiveBlending();
}


- (void) drawHyperring
{
	int i;
	GLfloat aleph = (alpha < 2.0) ? alpha*0.5: 1.0;

	GLfloat ex_em_hi[4]		= {0.6, 0.8, 1.0, aleph};   // pale blue
	GLfloat ex_em_lo[4]		= {0.2, 0.0, 1.0, 0.0};		// purplish-blue-black
	
	OOGL(glPushMatrix());
	OOGL(glDisable(GL_CULL_FACE));			// face culling
	OOGL(glDisable(GL_TEXTURE_2D));
	OOGL(glShadeModel(GL_SMOOTH));
	
	BeginAdditiveBlending(GL_ONE_YES);
	
	// movies:
	// draw data required ring_inner_radius, ring_outer_radius

	OOGLBEGIN(GL_TRIANGLE_STRIP);
	for (i = 0; i < 65; i++)
	{
		glColor4fv(ex_em_lo);
		glVertex3f(ring_inner_radius*circleVertex[i].x, ring_inner_radius*circleVertex[i].y, ring_inner_radius*circleVertex[i].z);
		glColor4fv(ex_em_hi);
		glVertex3f(ring_outer_radius*circleVertex[i].x, ring_outer_radius*circleVertex[i].y, ring_outer_radius*circleVertex[i].z);
	}
	OOGLEND();
	
	OOGL(glPopMatrix());
	
	EndAdditiveBlending();
}


- (void) drawEnergyMine
{
	double szd = sqrt(zero_distance);

	color_fv[3]		= alpha;  // set alpha

	OOGL(glDisable(GL_CULL_FACE));	// face culling
	OOGL(glDisable(GL_TEXTURE_2D));
	
	BeginAdditiveBlending(GL_ONE_YES);

	int step = 4;

	OOGL(glColor4fv(color_fv));
	OOGLBEGIN(GL_TRIANGLE_FAN);
		GLDrawBallBillboard(collision_radius, step, szd);
	OOGLEND();
	
	EndAdditiveBlending();
}


- (void) drawFragburst
{
	int i;

	OOGL(glEnable(GL_TEXTURE_2D));
	[texture apply];
	OOGL(glPushMatrix());
	
	BeginAdditiveBlending(GL_ONE_YES);

	OOGLBEGIN(GL_QUADS);
	for (i = 0; i < vertexCount; i++)
	{
		glColor4f(faces[i].red, faces[i].green, faces[i].blue, faces[i].normal.z);
		DrawQuadForView(vertices[i].x, vertices[i].y, vertices[i].z, faces[i].normal.x, faces[i].normal.x);
	}
	OOGLEND();
	
	EndAdditiveBlending();
	
	OOGL(glPopMatrix());
}


- (void) drawBurst2
{
	int i;

	OOGL(glEnable(GL_TEXTURE_2D));
	[texture apply];
	OOGL(glPushMatrix());
	
	BeginAdditiveBlending(GL_ONE_YES);

	OOGLBEGIN(GL_QUADS);
	for (i = 0; i < vertexCount; i++)
	{
		glColor4f(faces[i].red, faces[i].green, faces[i].blue, faces[i].normal.z);
		DrawQuadForView(vertices[i].x, vertices[i].y, vertices[i].z, size.width, size.width);
	}
	OOGLEND();
	
	EndAdditiveBlending();
	
	OOGL(glPopMatrix());
}


- (void) drawBillboard
{	
	OOGL(glColor4fv(color_fv));
	OOGL(glEnable(GL_TEXTURE_2D));
	[texture apply];
	OOGL(glPushMatrix());

	OOGLBEGIN(GL_QUADS);
		DrawQuadForView(position.x, position.y, position.z, size.width, size.height);
	OOGLEND();

	OOGL(glPopMatrix());
}


static void DrawQuadForView(GLfloat x, GLfloat y, GLfloat z, GLfloat xx, GLfloat yy)
{
	int viewdir = [UNIVERSE viewDirection];

	switch (viewdir)
	{
		case VIEW_FORWARD:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x-xx, y-yy, z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x+xx, y-yy, z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x+xx, y+yy, z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x-xx, y+yy, z);
		case	VIEW_AFT:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x+xx, y-yy, z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x-xx, y-yy, z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x-xx, y+yy, z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x+xx, y+yy, z);
			break;
		case	VIEW_STARBOARD:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x, y-yy, z+xx);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x, y-yy, z-xx);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x, y+yy, z-xx);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x, y+yy, z+xx);
			break;
		case	VIEW_PORT:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x, y-yy, z-xx);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x, y-yy, z+xx);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x, y+yy, z+xx);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x, y+yy, z-xx);
			break;
		case	VIEW_CUSTOM:
		{
			PlayerEntity *player = [PlayerEntity sharedPlayer];
			Vector vi = [player customViewRightVector];		vi.x *= xx;	vi.y *= xx;	vi.z *= xx;
			Vector vj = [player customViewUpVector];		vj.x *= yy;	vj.y *= yy;	vj.z *= yy;
			glTexCoord2f(0.0, 1.0);	glVertex3f(x - vi.x - vj.x, y - vi.y - vj.y, z - vi.z - vj.z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x + vi.x - vj.x, y + vi.y - vj.y, z + vi.z - vj.z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x + vi.x + vj.x, y + vi.y + vj.y, z + vi.z + vj.z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x - vi.x + vj.x, y - vi.y + vj.y, z - vi.z + vj.z);
			break;
		}
		default:
			glTexCoord2f(0.0, 1.0);	glVertex3f(x-xx, y-yy, z);
			glTexCoord2f(1.0, 1.0);	glVertex3f(x+xx, y-yy, z);
			glTexCoord2f(1.0, 0.0);	glVertex3f(x+xx, y+yy, z);
			glTexCoord2f(0.0, 0.0);	glVertex3f(x-xx, y+yy, z);
			break;
	}
}


- (BOOL) isParticle
{
	return YES;
}

@end


@implementation Entity (OOParticleExtensions)

- (BOOL)isParticle
{
	return NO;
}

@end
