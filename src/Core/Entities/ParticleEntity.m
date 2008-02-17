/*

ParticleEntity.m

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

#import "ParticleEntity.h"

#import "Universe.h"
#import "AI.h"
#import "OOColor.h"
#import "OOTexture.h"
#import "OOStringParsing.h"

#import "ShipEntity.h"
#import "PlayerEntity.h"
#import "PlanetEntity.h"


typedef enum
{
	PARTICLE_TEST				= 1,
	PARTICLE_SPARK				= 102,
	PARTICLE_SHOT_PLASMA		= 110,
	PARTICLE_LASER_BEAM			= 160,
	PARTICLE_EXPLOSION			= 201,
	PARTICLE_FLASH				= 230,
	PARTICLE_FRAGBURST			= 250,
	PARTICLE_BURST2				= 270,
	PARTICLE_EXHAUST			= 300,
	PARTICLE_ECM_MINE			= 400,
	PARTICLE_ENERGY_MINE		= 500,
	PARTICLE_FLASHER			= 600,
	PARTICLE_BILLBOARD			= 700,
	PARTICLE_HYPERRING			= 800
} OOParticleType;


@interface ParticleEntity (OOPrivate)

- (void) updateExplosion:(double) delta_t;
- (void) updateFlasher:(double) delta_t;
- (void) updateECMMine:(double) delta_t;
- (void) updateEnergyMine:(double) delta_t;
- (void) updateShot:(double) delta_t;
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
	glPushAttrib(GL_COLOR_BUFFER_BIT);
	glEnable(GL_BLEND);
	if (withGL_ONE)
	{
		glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	}
	else
	{
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	}
}


static inline void EndAdditiveBlending(void)
{
	glPopAttrib();
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
    self = [super init];
	if (self == nil)  return nil;
	
	time_counter = 0.0;
	
	particle_type = PARTICLE_TEST;
	isParticle = YES;
	status = STATUS_EFFECT;
	
	basefile = @"Particle";
	[self setTexture:@"blur256.png"];
	[self setColor:[OOColor greenColor]];
	
	size = NSMakeSize(32.0,32.0);
	collision_radius = 32.0;
	
	owner = NO_TARGET;
	
    return self;
}


- (id) initLaserFromShip:(ShipEntity *) srcEntity view:(int) view offset:(Vector)offset
{
	ShipEntity			*ship = nil;
	
	self = [super init];
	if (self == nil)  goto FAIL;
	
	if (srcEntity == nil || !srcEntity->isShip)  goto FAIL;
	if (srcEntity->isSubentity)
	{
		ship = [srcEntity owner];
		if (ship == nil || !ship->isShip)  goto FAIL;
	}
	else  ship = srcEntity;
	
	status = STATUS_EFFECT;
	position = ship->position;
	if (ship == srcEntity)  position = ship->position;
	else
	{
		BoundingBox bbox = [srcEntity boundingBox];
		Vector midfrontplane = make_vector(0.5 * (bbox.max.x + bbox.min.x), 0.5 * (bbox.max.y + bbox.min.y), bbox.max.z);
		position = [srcEntity absolutePositionForSubentityOffset:midfrontplane];
	}
	orientation = ship->orientation;
	if (ship->isPlayer)
		orientation.w = -orientation.w;   //reverse view direction for the player
	Vector v_up = vector_up_from_quaternion(orientation);
	Vector v_forward = vector_forward_from_quaternion(orientation);
	Vector v_right = vector_right_from_quaternion(orientation);
	GLfloat fs = [ship flightSpeed];
	velocity = make_vector(v_forward.x * fs, v_forward.y * fs, v_forward.z * fs);
	
	GLfloat distance;
	switch (view)
	{
		default:
		case VIEW_FORWARD:
			distance = [srcEntity boundingBox].max.z;
			position.x += distance * v_forward.x;	position.y += distance * v_forward.y;	position.z += distance * v_forward.z;
			break;
		case VIEW_AFT:
			quaternion_rotate_about_axis(&orientation, v_up, M_PI);
			distance = [srcEntity boundingBox].min.z;
			position.x += distance * v_forward.x;	position.y += distance * v_forward.y;	position.z += distance * v_forward.z;
			break;
		case VIEW_PORT:
			quaternion_rotate_about_axis(&orientation, v_up, M_PI/2.0);
			distance = [srcEntity boundingBox].min.x;
			position.x += distance * v_right.x;	position.y += distance * v_right.y;	position.z += distance * v_right.z;
			break;
		case VIEW_STARBOARD:
			quaternion_rotate_about_axis(&orientation, v_up, -M_PI/2.0);
			distance = [srcEntity boundingBox].max.x;
			position.x += distance * v_right.x;	position.y += distance * v_right.y;	position.z += distance * v_right.z;
			break;
	}
	quaternion_into_gl_matrix(orientation, rotMatrix);
	
	time_counter = 0.0;
	
	particle_type = PARTICLE_LASER_BEAM;
	
	[self setColor:[OOColor redColor]];
	
	duration = PARTICLE_LASER_DURATION;
	
	[self setOwner:ship];
	
	collision_radius = [srcEntity weaponRange];
	
	isParticle = YES;
	
	return self;
	
FAIL:
	[self release];
	return nil;
}


- (id) initExhaustFromShip:(ShipEntity *) ship details:(NSString *) details
{
	NSArray *values = ScanTokensFromString(details);
	if ([values count] != 6)
		return nil;
	Vector offset, scale;
	offset.x = [(NSString *)[values objectAtIndex:0] floatValue];
	offset.y = [(NSString *)[values objectAtIndex:1] floatValue];
	offset.z = [(NSString *)[values objectAtIndex:2] floatValue];
	scale.x = [(NSString *)[values objectAtIndex:3] floatValue];
	scale.y = [(NSString *)[values objectAtIndex:4] floatValue];
	scale.z = [(NSString *)[values objectAtIndex:5] floatValue];

	self = [super init];
    
	status = STATUS_EFFECT;

	exhaustScale = scale;
	
	position = offset;

	particle_type = PARTICLE_EXHAUST;
    
	[self setOwner:ship];
    
	isParticle = YES;
    
    return self;
}


- (id) initECMMineFromShip:(ShipEntity *) ship
{
	self = [super init];
	if (!ship)
		return self;
    
    time_counter = 0.0;
	activation_time = 0.5;
	duration = 2.0;
	position = ship->position;
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_ECM_MINE;
    
	[self setOwner:ship];
    
	isParticle = YES;
    
	return self;
}


- (id) initEnergyMineFromShip:(ShipEntity *) ship
{
	self = [super init];
    
	if (!ship)
		return self;
    
    time_counter = 0.0;
	duration = 20.0;
	position = ship->position;
    
	[self setVelocity: kZeroVector];
    
	[self setColor:[OOColor blueColor]];
    
	alpha = 0.5;
	collision_radius = 0;
    
	status = STATUS_EFFECT;
	scanClass = CLASS_MINE;
    
	particle_type = PARTICLE_ENERGY_MINE;
    
	[self setOwner:[ship owner]];
    
	isParticle = YES;
    
	return self;
}


- (id) initHyperringFromShip:(ShipEntity *) ship
{
	self = [super init];
	if (self == nil || ship == nil)
	{
		[self release];
		return nil;
	}
    
    time_counter = 0.0;
	duration = 2.0;
	size.width = ship->collision_radius * 0.5;
	size.height = size.width * 1.25;
	ring_inner_radius = size.width;
	ring_outer_radius = size.height;
	position = ship->position;
	[self setOrientation:ship->orientation];
	[self setVelocity:[ship velocity]];
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_HYPERRING;
	
	[self setOwner:ship];
    
	isParticle = YES;
    
    return self;
}


- (id) initFragburstSize:(GLfloat) fragSize fromPosition:(Vector) fragPos
{
	int speed_low = 100;
	int speed_high = 400;
	int n_fragments = 0.4 * fragSize;
	if (n_fragments > 63)
		n_fragments = 63;	// must also be less than MAX_FACES_PER_ENTITY
	n_fragments |= 12;
	int i;
    
	self = [super init];
    
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
		vertex_normal[i] = unit_vector(&vertex_normal[i]);
		vertex_normal[i].x *= speed;	// velocity
		vertex_normal[i].y *= speed;
		vertex_normal[i].z *= speed;
		Vector col = make_vector(color_fv[0] * 0.1 * (9.5 + randf()), color_fv[1] * 0.1 * (9.5 + randf()), color_fv[2] * 0.1 * (9.5 + randf()));
		col = unit_vector(&col);
		faces[i].red	= col.x;
		faces[i].green	= col.y;
		faces[i].blue	= col.z;
		faces[i].normal.x = 16.0 * speed_low / speed;
	}
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_FRAGBURST;
    
	collision_radius = 0;
	energy = 0;
	owner = NO_TARGET;
    
	isParticle = YES;
    
    return self;
}


- (id) initBurst2Size:(GLfloat) burstSize fromPosition:(Vector) fragPos
{
	int speed_low = 1 + burstSize * 0.5;
	int speed_high = speed_low * 4;
	int n_fragments = 0.2 * burstSize;
	if (n_fragments > 15)
		n_fragments = 15;	// must also be less than MAX_FACES_PER_ENTITY
	n_fragments |= 3;
	int i;
    
	self = [super init];
    
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
		vertex_normal[i] = unit_vector(&vertex_normal[i]);
		vertex_normal[i].x *= speed;	// velocity
		vertex_normal[i].y *= speed;
		vertex_normal[i].z *= speed;
		Vector col = make_vector(color_fv[0] * 0.1 * (9.5 + randf()), color_fv[1] * 0.1 * (9.5 + randf()), color_fv[2] * 0.1 * (9.5 + randf()));
		col = unit_vector(&col);
		faces[i].red = col.x;
		faces[i].green = col.y;
		faces[i].blue = col.z;
		faces[i].normal.z = 1.0;
	}
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_BURST2;
    
	collision_radius = 0;
	energy = 0;
	owner = NO_TARGET;
    
	isParticle = YES;
    
    return self;
}

// used exclusively for explosion flashes
- (id) initFlashSize:(GLfloat) flashSize fromPosition:(Vector) fragPos
{
    
	self = [super init];
    
	basefile = @"Particle";
	[self setTexture:@"flare256.png"];
    
	size = NSMakeSize(flashSize, flashSize);
    
	growth_rate = 150.0 * flashSize; // if average flashSize is 80 then this is 12000
	if (growth_rate < 6000.0)
		growth_rate = 6000.0;	// put a minimum size on it
    
    time_counter = 0.0;
	duration = 0.4;
	position = fragPos;
    
	[self setColor:[OOColor whiteColor]];
	color_fv[3] = 1.0;
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_FLASH;
    
	collision_radius = 0;
	energy = 0;
	owner = NO_TARGET;
    
	isParticle = YES;
    
	[self setVelocity: kZeroVector];
	
    return self;
}

// used for laser flashes
- (id) initFlashSize:(GLfloat) flashSize fromPosition:(Vector) fragPos color:(OOColor*) flashColor
{
    
	self = [super init];
    
	basefile = @"Particle";
	[self setTexture:@"flare256.png"];
    
	size = NSMakeSize(flashSize, flashSize);
    
	growth_rate = 150.0 * flashSize; // if average flashSize is 80 then this is 12000
    
    time_counter = 0.0;
	duration = 0.3;
	position = fragPos;
    
	[self setColor:flashColor];
	color_fv[3] = 1.0;
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_FLASH;
    
	collision_radius = 0;
	energy = 0;
	owner = NO_TARGET;
    
	isParticle = YES;
    
	[self setVelocity: kZeroVector];
	
    return self;
}

// used for background billboards
- (id) initBillboard:(NSSize) billSize withTexture:(NSString*) textureFile
{
	self = [super init];
    
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
    
	status = STATUS_EFFECT;
	scanClass = CLASS_NO_DRAW;
    
	particle_type = PARTICLE_BILLBOARD;
    
	collision_radius = 0;
	energy = 0;
	owner = NO_TARGET;
    
	isParticle = YES;
    
	[self setVelocity: kZeroVector];
	[self setPosition: make_vector(0.0f, 0.0f, 640.0f)];

    return self;
}


- (id) initFlasherWithSize:(float)inSize frequency:(float)frequency phase:(float)phase
{
	self = [self init];
	if (self != nil)
	{
		[self setSize:NSMakeSize(inSize, inSize)];
		[self setEnergy:phase];
		[self setDuration:frequency];
		particle_type = PARTICLE_FLASHER;
	}
	return self;
}


- (id) initPlasmaShotAt:(Vector)inPosition
			   velocity:(Vector)inVelocity
				 energy:(float)inEnergy
			   duration:(OOTimeDelta)inDuration
				  color:(OOColor *)inColor
{
	self = [self init];
	if (self != nil)
	{
		particle_type = PARTICLE_SHOT_PLASMA;
		[self setPosition:inPosition];
		[self setVelocity:inVelocity];
		[self setScanClass:CLASS_NO_DRAW];
		[self setDuration:inDuration];
		[self setCollisionRadius:2.0];
		[self setEnergy:inEnergy];
		[self setSize:NSMakeSize(12, 12)];
		[self setColor:inColor];
	}
	return self;
}


- (id) initSparkAt:(Vector)inPosition
		  velocity:(Vector)inVelocity
		  duration:(OOTimeDelta)inDuration
			  size:(float)inSize
			 color:(OOColor *)inColor
{
	self = [self init];
	if (self != nil)
	{
		particle_type = PARTICLE_SPARK;
		[self setPosition:inPosition];
		[self setVelocity:inVelocity];
		[self setScanClass:CLASS_NO_DRAW];
		[self setDuration:inDuration];
		[self setCollisionRadius:2.0];
		[self setEnergy:0.0];
		[self setSize:NSMakeSize(inSize, inSize)];
		[self setColor:inColor];
	}
	return self;
}


- (void) dealloc
{
	[texture release];
	[color release];
	
    [super dealloc];
}


- (NSString*) descriptionComponents
{
	NSString* type_string = nil;
	switch ([self particleType])
	{
#define CASE(x) case x: type_string = @#x; break;
		CASE(PARTICLE_TEST);
		CASE(PARTICLE_LASER_BEAM);
		CASE(PARTICLE_SHOT_PLASMA);
		CASE(PARTICLE_SPARK);
		CASE(PARTICLE_EXPLOSION);
		CASE(PARTICLE_FLASH);
		CASE(PARTICLE_FRAGBURST);
		CASE(PARTICLE_BURST2);
		CASE(PARTICLE_EXHAUST);
		CASE(PARTICLE_ECM_MINE);
		CASE(PARTICLE_ENERGY_MINE);
		CASE(PARTICLE_FLASHER);
		CASE(PARTICLE_BILLBOARD);
		CASE(PARTICLE_HYPERRING);
	}
	if (type_string == nil)  type_string = [NSString stringWithFormat:@"UNKNOWN (%i)", particle_type];
	
	return [NSString stringWithFormat:@"%@ ttl: %.3fs", type_string, duration - time_counter];
}


- (BOOL) canCollide
{
	if (particle_type == PARTICLE_SHOT_PLASMA || particle_type == PARTICLE_ENERGY_MINE)
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
	return !(other->isParticle);
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
			case PARTICLE_TEST:
			case PARTICLE_SPARK:
			case PARTICLE_SHOT_PLASMA:
			case PARTICLE_FLASHER:
			case PARTICLE_EXPLOSION:
			case PARTICLE_FRAGBURST:
			case PARTICLE_BURST2:
			case PARTICLE_FLASH:
				{
					PlayerEntity *player = [PlayerEntity sharedPlayer];
					if (player != nil)
					{
						GLfloat* rmix = [player drawRotationMatrix];
						int i = 0;
						for (i = 0; i < 16; i++)				// copy the player's rotation
							rotMatrix[i] = rmix[i];				// Really simple billboard routine
					}
				}
				break;
			
			case PARTICLE_LASER_BEAM:
			case PARTICLE_EXHAUST:
			case PARTICLE_ECM_MINE:
			case PARTICLE_ENERGY_MINE:
			case PARTICLE_BILLBOARD:
			case PARTICLE_HYPERRING:
				break;
		}
		switch ([self particleType])
		{
			case PARTICLE_TEST:
				alpha = (sin(time_counter) + 2.0) / 3.0;
				break;

			case PARTICLE_EXPLOSION:
				[self updateExplosion:delta_t];
				break;

			case PARTICLE_HYPERRING:
				[self updateHyperring:delta_t];
				break;

			case PARTICLE_LASER_BEAM:
				[self updateLaser:delta_t];
				break;
				
			case PARTICLE_EXHAUST:
				[self updateExhaust2:delta_t];
				break;

			case PARTICLE_ECM_MINE:
				[self updateECMMine:delta_t];
				break;

			case PARTICLE_ENERGY_MINE:
				[self updateEnergyMine:delta_t];
				break;

			case PARTICLE_FLASHER:
				[self updateFlasher:delta_t];
				break;

			case PARTICLE_SPARK:
				[self updateSpark:delta_t];
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

			case PARTICLE_SHOT_PLASMA:
				[self updateShot:delta_t];
				break;
			
			default:
				OOLog(@"particle.unknown", @"Invalid particle %@, removing.", self);
				[UNIVERSE removeEntity:self];
		}
	}

}


- (void) updateExplosion:(double) delta_t
{
	float diameter = (1.0 + time_counter)*64.0;
	[self setSize:NSMakeSize(diameter, diameter)];
	alpha = (duration - time_counter);
	if (time_counter > duration)
		[UNIVERSE removeEntity:self];
}


- (void) updateFlasher:(double) delta_t
{
	alpha = 0.5 * sin(duration * M_PI * (time_counter + energy)) + 0.5;
}


- (void) updateECMMine:(double) delta_t
{
	if (time_counter > activation_time)
	{
		// do ecm stuff
		GLfloat radius = 0.5 * activation_time * SCANNER_MAX_RANGE;
		if (radius > SCANNER_MAX_RANGE)
			radius = SCANNER_MAX_RANGE;
		NSArray* targets = [UNIVERSE getEntitiesWithinRange:radius ofEntity:self];
		if ([targets count] > 0)
		{
			unsigned i;
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
		[UNIVERSE removeEntity:self];
}


- (void) updateEnergyMine:(double) delta_t
{
	// new billboard routine (working at last!)
	PlayerEntity *player = [PlayerEntity sharedPlayer];
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

	Vector v1 = cross_product(v0, arb1 ); // 90 degrees to (v0 x arb1)
	//equivalent of v_right

	Vector v2 = cross_product(v0, v1 );   // 90 degrees to (v0 x v1)
	//equivalent of v_up

	vectors_into_gl_matrix(v0, v1, v2, rotMatrix);
    
	// end of new billboard routine

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


- (void) updateShot:(double) delta_t
{
	if ([collidingEntities count] > 0)
	{
		unsigned i;
		for (i = 0; i < [collidingEntities count]; i++)
		{
			Entity *	e = (Entity *)[collidingEntities objectAtIndex:i];
			if (e != [self owner])
			{
				[e takeEnergyDamage:energy from:self becauseOf:[self owner]];
				velocity.x = 0.0;
				velocity.y = 0.0;
				velocity.z = 0.0;
				[self setColor:[OOColor redColor]];
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


- (void) updateExhaust2:(double) delta_t
{
	#if ADDITIVE_BLENDING
		#define OVERALL_ALPHA		0.5f
	#else
		#define OVERALL_ALPHA		1.0f
	#endif
	
	GLfloat ex_emissive[4]	= {0.6, 0.8, 1.0, 0.9 * OVERALL_ALPHA};   // pale blue
	const GLfloat s1[8] = { 0.0, 0.707, 1.0, 0.707, 0.0, -0.707, -1.0, -0.707};
	const GLfloat c1[8] = { 1.0, 0.707, 0.0, -0.707, -1.0, -0.707, 0.0, 0.707};
	ShipEntity  *ship = [UNIVERSE entityForUniversalID:owner];

	if ((!ship)||(!ship->isShip))
		return;

	Quaternion shipQrotation = [ship orientation];
	if (ship->isPlayer) 	shipQrotation.w = -shipQrotation.w;	// WTF sort of silliness is this? -- Ahruman
	
	Frame zero;
	zero.orientation = shipQrotation;
	int dam = [ship damage];
	GLfloat flare_length = [ship speedFactor];

	if (!flare_length)	// don't draw if there's no fire!
		return;

	GLfloat hyper_fade = 8.0f / (8.0f + flare_length * flare_length * flare_length);

	GLfloat flare_factor = flare_length * ex_emissive[3] * hyper_fade;
	GLfloat red_factor = flare_length * ex_emissive[0] * (ranrot_rand() % 11) * 0.1;	// random fluctuations
	GLfloat green_factor = flare_length * ex_emissive[1] * hyper_fade;

	if (flare_length > 1.0)	// afterburner!
	{
		red_factor = 1.5;
		flare_length = 1.0 + 0.25 * flare_length;
	}

	if ((int)(ranrot_rand() % 50) < dam - 50)   // flicker the damaged engines
		red_factor = 0.0;
	if ((int)(ranrot_rand() % 40) < dam - 60)
		green_factor = 0.0;
	if ((int)(ranrot_rand() % 25) < dam - 75)
		flare_factor = 0.0;

	if (flare_length < 0.1)   flare_length = 0.1;
	Vector currentPos = ship->position;
	Vector vfwd = vector_forward_from_quaternion(shipQrotation);
	GLfloat	spd = 0.5 * [ship flightSpeed];
	vfwd = vector_multiply_scalar(vfwd, spd);
	Vector master_i = vector_right_from_quaternion(shipQrotation);
	Vector vi,vj,vk;
	vi = master_i;
	vj = vector_up_from_quaternion(shipQrotation);
	vk = cross_product(vi, vj);
	zero.position = make_vector(	currentPos.x + vi.x * position.x + vj.x * position.y + vk.x * position.z,
									currentPos.y + vi.y * position.x + vj.y * position.y + vk.y * position.z,
									currentPos.z + vi.z * position.x + vj.z * position.y + vk.z * position.z);

//	GLfloat i01 = -0.03;// * flare_length;
//	GLfloat i01 = -0.03 * (1.0 - flare_length);// * flare_length;
	GLfloat i01 = -0.03 * hyper_fade;// * flare_length;
	GLfloat i03 = -0.12;// * flare_length;
	GLfloat i06 = -0.25;// * flare_length;
	GLfloat i08 = -0.32;// * flare_length;
	GLfloat i10 = -0.40;// * flare_length;
	GLfloat q01 = i01/i10;	// factor for trail
	GLfloat q03 = i03/i10;
	GLfloat q06 = i06/i10;
	GLfloat q08 = i08/i10;
	GLfloat r01 = 1.0 - q01;	// factor for jet
	GLfloat r03 = 1.0 - q03;
	GLfloat r06 = 1.0 - q06;
	GLfloat r08 = 1.0 - q08;
	Frame	f01 = [self frameAtTime: i01 fromFrame: zero];
	Vector	b01 = make_vector(r01 * i01 * vfwd.x, r01 * i01 * vfwd.y, r01 * i01 * vfwd.z);
	Frame	f03 = [self frameAtTime: i03 fromFrame: zero];
	Vector	b03 = make_vector(r03 * i03 * vfwd.x, r03 * i03 * vfwd.y, r03 * i03 * vfwd.z);
	Frame	f06 = [self frameAtTime: i06 fromFrame: zero];
	Vector	b06 = make_vector(r06 * i06 * vfwd.x, r06 * i06 * vfwd.y, r06 * i06 * vfwd.z);
	Frame	f08 = [self frameAtTime: i08 fromFrame: zero];
	Vector	b08 = make_vector(r08 * i08 * vfwd.x, r08 * i08 * vfwd.y, r08 * i08 * vfwd.z);
	Frame	f10 = [self frameAtTime: i10 fromFrame: zero];

	int ci = 0;
	int iv = 0;
	int i;
	float r1;
    
	ex_emissive[3] = flare_factor * OVERALL_ALPHA;	// fade alpha towards rear of exhaust
	ex_emissive[1] = green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = red_factor;		// diminish red part towards rear of exhaust
	verts[iv++] = f03.position.x + b03.x;// + zero.k.x * flare_factor * 4.0;
	verts[iv++] = f03.position.y + b03.y;// + zero.k.y * flare_factor * 4.0;
	verts[iv++] = f03.position.z + b03.z;// + zero.k.z * flare_factor * 4.0;
	exhaustBaseColors[ci++] = ex_emissive[0];
	exhaustBaseColors[ci++] = ex_emissive[1];
	exhaustBaseColors[ci++] = ex_emissive[2];
	exhaustBaseColors[ci++] = ex_emissive[3];
    
	ex_emissive[3] = 0.9 * flare_factor * OVERALL_ALPHA;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.9 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.9 * red_factor;		// diminish red part towards rear of exhaust
	Vector k1 = f01.k;
	Vector j1 = cross_product(master_i, k1);
	Vector i1 = cross_product(j1, k1);

	f01.position = make_vector(zero.position.x - vk.x, zero.position.y - vk.y, zero.position.z - vk.z);// 1m out from zero
//	i1 = vi;
//	j1 = vj;	// initial vars

	i1.x *= exhaustScale.x;	i1.y *= exhaustScale.x;	i1.z *= exhaustScale.x;
	j1.x *= exhaustScale.y;	j1.y *= exhaustScale.y;	j1.z *= exhaustScale.y;
	for (i = 0; i < 8; i++)
	{
		verts[iv++] =	f01.position.x + b01.x + s1[i] * i1.x + c1[i] * j1.x;
		verts[iv++] =	f01.position.y + b01.y + s1[i] * i1.y + c1[i] * j1.y;
		verts[iv++] =	f01.position.z + b01.z + s1[i] * i1.z + c1[i] * j1.z;
		exhaustBaseColors[ci++] = ex_emissive[0];
		exhaustBaseColors[ci++] = ex_emissive[1];
		exhaustBaseColors[ci++] = ex_emissive[2];
		exhaustBaseColors[ci++] = ex_emissive[3];
	}
    
	ex_emissive[3] = 0.6 * flare_factor * OVERALL_ALPHA;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.6 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.6 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f03.k;
	j1 = cross_product(master_i, k1);
	i1 = cross_product(j1, k1);
	i1.x *= exhaustScale.x;	i1.y *= exhaustScale.x;	i1.z *= exhaustScale.x;
	j1.x *= exhaustScale.y;	j1.y *= exhaustScale.y;	j1.z *= exhaustScale.y;
	for (i = 0; i < 8; i++)
	{
		r1 = randf();
		verts[iv++] =	f03.position.x + b03.x + s1[i] * i1.x + c1[i] * j1.x + r1 * k1.x;
		verts[iv++] =	f03.position.y + b03.y + s1[i] * i1.y + c1[i] * j1.y + r1 * k1.y;
		verts[iv++] =	f03.position.z + b03.z + s1[i] * i1.z + c1[i] * j1.z + r1 * k1.z;
		exhaustBaseColors[ci++] = ex_emissive[0];
		exhaustBaseColors[ci++] = ex_emissive[1];
		exhaustBaseColors[ci++] = ex_emissive[2];
		exhaustBaseColors[ci++] = ex_emissive[3];
	}
    
	ex_emissive[3] = 0.4 * flare_factor * OVERALL_ALPHA;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.4 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.4 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f06.k;
	j1 = cross_product(master_i, k1);
	i1 = cross_product(j1, k1);
	i1.x *= 0.8 * exhaustScale.x;	i1.y *= 0.8 * exhaustScale.x;	i1.z *= 0.8 * exhaustScale.x;
	j1.x *= 0.8 * exhaustScale.y;	j1.y *= 0.8 * exhaustScale.y;	j1.z *= 0.8 * exhaustScale.y;
	for (i = 0; i < 8; i++)
	{
		r1 = randf();
		verts[iv++] =	f06.position.x + b06.x + s1[i] * i1.x + c1[i] * j1.x + r1 * k1.x;
		verts[iv++] =	f06.position.y + b06.y + s1[i] * i1.y + c1[i] * j1.y + r1 * k1.y;
		verts[iv++] =	f06.position.z + b06.z + s1[i] * i1.z + c1[i] * j1.z + r1 * k1.z;
		exhaustBaseColors[ci++] = ex_emissive[0];
		exhaustBaseColors[ci++] = ex_emissive[1];
		exhaustBaseColors[ci++] = ex_emissive[2];
		exhaustBaseColors[ci++] = ex_emissive[3];
	}
    
	ex_emissive[3] = 0.2 * flare_factor * OVERALL_ALPHA;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.2 * green_factor;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.2 * red_factor;		// diminish red part towards rear of exhaust
	k1 = f08.k;
	j1 = cross_product(master_i, k1);
	i1 = cross_product(j1, k1);
	i1.x *= 0.5 * exhaustScale.x;	i1.y *= 0.5 * exhaustScale.x;	i1.z *= 0.5 * exhaustScale.x;
	j1.x *= 0.5 * exhaustScale.y;	j1.y *= 0.5 * exhaustScale.y;	j1.z *= 0.5 * exhaustScale.y;
	for (i = 0; i < 8; i++)
	{
		r1 = randf();
		verts[iv++] =	f08.position.x + b08.x + s1[i] * i1.x + c1[i] * j1.x + r1 * k1.x;
		verts[iv++] =	f08.position.y + b08.y + s1[i] * i1.y + c1[i] * j1.y + r1 * k1.y;
		verts[iv++] =	f08.position.z + b08.z + s1[i] * i1.z + c1[i] * j1.z + r1 * k1.z;
		exhaustBaseColors[ci++] = ex_emissive[0];
		exhaustBaseColors[ci++] = ex_emissive[1];
		exhaustBaseColors[ci++] = ex_emissive[2];
		exhaustBaseColors[ci++] = ex_emissive[3];
	}
    
	ex_emissive[3] = 0.0;	// fade alpha towards rear of exhaust
	ex_emissive[1] = 0.0;	// diminish green part towards rear of exhaust
	ex_emissive[0] = 0.0;		// diminish red part towards rear of exhaust
	verts[iv++] = f10.position.x;
	verts[iv++] = f10.position.y;
	verts[iv++] = f10.position.z;
	exhaustBaseColors[ci++] = ex_emissive[0];
	exhaustBaseColors[ci++] = ex_emissive[1];
	exhaustBaseColors[ci++] = ex_emissive[2];
	exhaustBaseColors[ci++] = ex_emissive[3];
}


- (void) drawEntity:(BOOL) immediate:(BOOL) translucent;
{
	if (UNIVERSE == nil || [UNIVERSE breakPatternHide])  return;

	if ((particle_type == PARTICLE_FLASHER)&&(zero_distance > no_draw_distance))	return;	// TOO FAR AWAY TO SEE

	if (translucent)
	{
		switch ([self particleType])
		{
			case PARTICLE_LASER_BEAM:
				[self drawLaser];
				break;

			case PARTICLE_EXHAUST:
				[self drawExhaust2];
				break;

			case PARTICLE_HYPERRING:
				[self drawHyperring];
				break;

			case PARTICLE_ECM_MINE:
				// not a visible entity
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

			case PARTICLE_FLASH:
				[self drawParticle];
				break;

			case PARTICLE_BILLBOARD:
				[self drawBillboard];
				break;

			default:
				[self drawParticle];
				break;
		}
	}
	CheckOpenGLErrors(@"ParticleEntity after drawing %@ %@", self);
}


- (void) drawSubEntity:(BOOL) immediate:(BOOL) translucent
{
	if (particle_type == PARTICLE_EXHAUST)
	{
		if (translucent)
			[self drawExhaust2];
		return;
	}

	Entity* my_owner = [UNIVERSE entityForUniversalID:owner];

	if (my_owner)
	{
		// this test provides an opportunity to do simple LoD culling
	    
		zero_distance = my_owner->zero_distance;
		if (zero_distance > no_draw_distance)
			return; // TOO FAR AWAY TO DRAW
	}

	if ((particle_type == PARTICLE_FLASHER)&&(status != STATUS_INACTIVE))
	{
		OOMatrix	temp_matrix;

		Vector		abspos = position;  // in control of it's own orientation
		int			view_dir = [UNIVERSE viewDirection];
		Entity		*last = nil;
		Entity		*father = my_owner;
		OOMatrix	r_mat;
		
		while ((father)&&(father != last))
		{
			r_mat = OOMatrixFromGLMatrix([father drawRotationMatrix]);
			abspos = vector_add(OOVectorMultiplyMatrix(abspos, r_mat), [father position]);
			last = father;
			father = [father owner];
		}

		if (view_dir == VIEW_GUI_DISPLAY)
		{
			if (translucent)
			{
				temp_matrix = OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX);
				glPopMatrix();	glPushMatrix();  // restore zero!
				glTranslatef(abspos.x, abspos.y, abspos.z); // move to absolute position
				GLfloat	xx = 0.5 * size.width;
				GLfloat	yy = 0.5 * size.height;
				
				alpha = OOClamp_0_1_f(alpha);
				
				color_fv[3] = alpha;
				glEnable(GL_TEXTURE_2D);
				glColor4fv(color_fv);
				glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, color_fv);
				glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);
				[texture apply];
				
				glBegin(GL_QUADS);
					glTexCoord2f(0.0, 1.0);
					glVertex3f(-xx, -yy, -xx);

					glTexCoord2f(1.0, 1.0);
					glVertex3f(xx, -yy, -xx);

					glTexCoord2f(1.0, 0.0);
					glVertex3f(xx, yy, -xx);

					glTexCoord2f(0.0, 0.0);
					glVertex3f(-xx, yy, -xx);
					
					
				glEnd();

				GLLoadOOMatrix(temp_matrix);
			}
		}
		else
		{
			temp_matrix = OOMatrixLoadGLMatrix(GL_MODELVIEW_MATRIX);
			glPopMatrix();  // restore zero!
			glPushMatrix();
					// position and orientation is absolute
			GLTranslateOOVector(abspos);
			glMultMatrixf([[PlayerEntity sharedPlayer] drawRotationMatrix]);

			[self drawEntity:immediate:translucent];
			
			GLLoadOOMatrix(temp_matrix);
		}
	}
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

	glEnable(GL_TEXTURE_2D);

	glColor4fv(color_fv);

	glTexEnvfv(GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, color_fv);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);

	[texture apply];
	
	BeginAdditiveBlending(GL_ONE_YES);

	glBegin(GL_QUADS);

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
	glEnd();
	
	EndAdditiveBlending();
}


- (void) drawLaser
{
	color_fv[3]		= 0.75;  // set alpha

	glDisable(GL_CULL_FACE);			// face culling

	glDisable(GL_TEXTURE_2D);

	glColor4fv(color_fv);
	
	BeginAdditiveBlending(GL_ONE_NO);

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
	
	EndAdditiveBlending();

	glEnable(GL_CULL_FACE);			// face culling
}

GLuint tfan1[10] = {	0,	1,	2,	3,	4,	5,	6,	7,	8,	1};		// initial fan 0..9
GLuint qstrip1[18] = {	1,	9,	2,	10,	3,	11,	4,	12,	5,	13,	6,	14,	7,	15,	8,	16,	1,	9};		// first quadstrip 10..27
GLuint qstrip2[18] = {	9,	17,	10,	18,	11,	19,	12,	20,	13,	21,	14,	22,	15,	23,	16,	24,	9,	17};	// second quadstrip 28..45
GLuint qstrip3[18] = {	17,	25,	18,	26,	19,	27,	20,	28,	21,	29,	22,	30,	23,	31,	24,	32,	17,	25};	// third quadstrip 46..63
GLuint tfan2[10] = {	33,	25,	26,	27,	28,	29,	30,	31,	32,	25};	// final fan 64..73

- (void) drawExhaust2
{
	ShipEntity  *ship = [UNIVERSE entityForUniversalID:owner];

	if (!ship)
		return;

	if ([ship speedFactor] <= 0.0)	// don't draw if there's no fire!
		return;

	glPopMatrix();	// restore absolute positioning
	glPushMatrix();	// avoid stack underflow

	glDisable(GL_TEXTURE_2D);
	glDisable(GL_CULL_FACE);		// face culling
	glShadeModel(GL_SMOOTH);
	
	BeginAdditiveBlending(GL_ONE_YES);

	glEnableClientState(GL_VERTEX_ARRAY);
	glVertexPointer(3, GL_FLOAT, 0, verts);
	glEnableClientState(GL_COLOR_ARRAY);
	glColorPointer(4, GL_FLOAT, 0, exhaustBaseColors);
	glDisableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_INDEX_ARRAY);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glDisableClientState(GL_EDGE_FLAG_ARRAY);
    
	glDrawElements(GL_TRIANGLE_FAN, 10, GL_UNSIGNED_INT, tfan1);
	glDrawElements(GL_QUAD_STRIP, 18, GL_UNSIGNED_INT, qstrip1);
	glDrawElements(GL_QUAD_STRIP, 18, GL_UNSIGNED_INT, qstrip2);
	glDrawElements(GL_QUAD_STRIP, 18, GL_UNSIGNED_INT, qstrip3);
	glDrawElements(GL_TRIANGLE_FAN, 10, GL_UNSIGNED_INT, tfan2);

	EndAdditiveBlending();
	
	glEnable(GL_CULL_FACE);		// face culling
	glEnable(GL_TEXTURE_2D);
}


- (void) drawHyperring
{
	int i;
	GLfloat aleph = (alpha < 2.0) ? alpha*0.5: 1.0;

	GLfloat ex_em_hi[4]		= {0.6, 0.8, 1.0, aleph};   // pale blue
	GLfloat ex_em_lo[4]		= {0.2, 0.0, 1.0, 0.0};		// purplish-blue-black

	glPushMatrix();
	glDisable(GL_CULL_FACE);			// face culling
	glDisable(GL_TEXTURE_2D);
	glShadeModel(GL_SMOOTH);
	
	BeginAdditiveBlending(GL_ONE_YES);
	
	// movies:
	// draw data required ring_inner_radius, ring_outer_radius

	glBegin(GL_TRIANGLE_STRIP);
	for (i = 0; i < 65; i++)
	{
		glColor4fv(ex_em_lo);
		glVertex3f(ring_inner_radius*circleVertex[i].x, ring_inner_radius*circleVertex[i].y, ring_inner_radius*circleVertex[i].z );
		glColor4fv(ex_em_hi);
		glVertex3f(ring_outer_radius*circleVertex[i].x, ring_outer_radius*circleVertex[i].y, ring_outer_radius*circleVertex[i].z );
	}
	glEnd();
	
	EndAdditiveBlending();

	glEnable(GL_CULL_FACE);			// face culling
	glPopMatrix();
}


- (void) drawEnergyMine
{
	double szd = sqrt(zero_distance);

	color_fv[3]		= alpha;  // set alpha

	glDisable(GL_CULL_FACE);			// face culling
	glDisable(GL_TEXTURE_2D);
	
	BeginAdditiveBlending(GL_ONE_YES);

	int step = 4;

	glColor4fv(color_fv);
	glBegin(GL_TRIANGLE_FAN);
    
	GLDrawBallBillboard(collision_radius, step, szd);
    
	glEnd();

	EndAdditiveBlending();
	
	glEnable(GL_CULL_FACE);			// face culling
}


- (void) drawFragburst
{
    int i;

	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[texture apply];
	glPushMatrix();
	
	BeginAdditiveBlending(GL_ONE_YES);

	glBegin(GL_QUADS);
	for (i = 0; i < vertexCount; i++)
	{
		glColor4f(faces[i].red, faces[i].green, faces[i].blue, faces[i].normal.z);
		DrawQuadForView(vertices[i].x, vertices[i].y, vertices[i].z, faces[i].normal.x, faces[i].normal.x);
	}
	glEnd();
	
	EndAdditiveBlending();

	glPopMatrix();
	glDisable(GL_TEXTURE_2D);
}


- (void) drawBurst2
{
    int i;

	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[texture apply];
	glPushMatrix();
	
	BeginAdditiveBlending(GL_ONE_YES);

	glBegin(GL_QUADS);
	for (i = 0; i < vertexCount; i++)
	{
		glColor4f(faces[i].red, faces[i].green, faces[i].blue, faces[i].normal.z);
		DrawQuadForView(vertices[i].x, vertices[i].y, vertices[i].z, size.width, size.width);
	}
	glEnd();
	
	EndAdditiveBlending();

	glPopMatrix();
	glDisable(GL_TEXTURE_2D);
}


- (void) drawBillboard
{	
	glColor4fv(color_fv);
	glEnable(GL_TEXTURE_2D);
	glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
	[texture apply];
	glPushMatrix();

	glBegin(GL_QUADS);
		DrawQuadForView(position.x, position.y, position.z, size.width, size.height);
	glEnd();

	glPopMatrix();
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


- (BOOL)isFlasher
{
	return particle_type == PARTICLE_FLASHER;
}


- (BOOL)isExhaust
{
	return particle_type == PARTICLE_EXHAUST;
}

@end


@implementation Entity (OOParticleExtensions)

- (BOOL)isParticle
{
	return isParticle;
}


- (BOOL)isFlasher
{
	return NO;
}


- (BOOL)isExhaust
{
	return NO;
}

@end
