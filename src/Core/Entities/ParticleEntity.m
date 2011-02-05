/*

ParticleEntity.m

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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
#import "OOPlanetEntity.h"


/*	Entities that can easily be migrated to OOLightParticleEntity:
	PARTICLE_FRAGBURST?
	PARTICLE_BURST2?
*/


typedef enum
{
	PARTICLE_FRAGBURST			= 250,
	PARTICLE_BURST2				= 270
} OOParticleType;


#if OOLITE_LEOPARD
#define OOPrivate	// Turn private category into a continuation where possible.
#endif


@interface ParticleEntity (OOPrivate)

- (void) updateFragburst:(double) delta_t;
- (void) updateBurst2:(double) delta_t;

- (void) drawFragburst;
- (void) drawBurst2;

- (void) setTexture:(NSString *) filename;
- (void) setParticleType:(OOParticleType) p_type;
- (OOParticleType) particleType;

@end


OOINLINE void BeginAdditiveBlending(void)
{
	OOGL(glEnable(GL_BLEND));
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE));
}


OOINLINE void EndAdditiveBlending(void)
{
}


static void DrawQuadForView(GLfloat x, GLfloat y, GLfloat z, GLfloat xx, GLfloat yy);


@implementation ParticleEntity

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
		CASE(PARTICLE_FRAGBURST);
		CASE(PARTICLE_BURST2);
	}
	if (type_string == nil)  type_string = [NSString stringWithFormat:@"UNKNOWN (%i)", particle_type];
	
	return [NSString stringWithFormat:@"%@ ttl: %.3fs", type_string, duration - time_counter];
#else
	return [NSString stringWithFormat:@"ttl: %.3fs", duration - time_counter];
#endif
}


- (BOOL) canCollide
{
	return NO;
}


- (BOOL) checkCloseCollisionWith:(Entity *)other
{
	if (other == [self owner])  return NO;
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
	collision_radius = hypotf(size.width, size.height);
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
		PlayerEntity *player = PLAYER;
		assert(player != nil);
		rotMatrix = [player drawRotationMatrix];
		
		switch ([self particleType])
		{
			case PARTICLE_FRAGBURST:
				[self updateFragburst:delta_t];
				break;

			case PARTICLE_BURST2:
				[self updateBurst2:delta_t];
				break;
			
			default:
				OOLog(@"particle.unknown", @"Invalid particle %@, removing.", self);
				[UNIVERSE removeEntity:self];
		}
	}
}


- (void) updateFragburst:(double) delta_t
{
	OOMeshVertexCount i;
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
	size.width = (1.0 + time_counter) * size.height;	// current size vs starting size
	
	GLfloat di = 1.0 / (vertexCount - 1);
	OOMeshVertexCount i;
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


- (void) drawEntity:(BOOL)immediate :(BOOL)translucent
{
	if ([UNIVERSE breakPatternHide])  return;
	
	OOGL(glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT));
	
	if (translucent)
	{
		switch ([self particleType])
		{
			case PARTICLE_FRAGBURST:
				[self drawFragburst];
				break;
				
			case PARTICLE_BURST2:
				[self drawBurst2];
				break;
				
			default:
				OOLog(@"particle.unknown", @"Invalid particle %@, removing.", self);
				[UNIVERSE removeEntity:self];
				break;
		}
	}
	
	OOGL(glPopAttrib());
	
	CheckOpenGLErrors(@"ParticleEntity after drawing %@", self);
}


- (void) drawFragburst
{
	OOGL(glEnable(GL_TEXTURE_2D));
	[texture apply];
	OOGL(glPushMatrix());
	
	BeginAdditiveBlending();

	OOGLBEGIN(GL_QUADS);
	OOMeshVertexCount i;
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
	OOGL(glEnable(GL_TEXTURE_2D));
	[texture apply];
	OOGL(glPushMatrix());
	
	BeginAdditiveBlending();

	OOGLBEGIN(GL_QUADS);
	OOMeshVertexCount i;
	for (i = 0; i < vertexCount; i++)
	{
		glColor4f(faces[i].red, faces[i].green, faces[i].blue, faces[i].normal.z);
		DrawQuadForView(vertices[i].x, vertices[i].y, vertices[i].z, size.width, size.width);
	}
	OOGLEND();
	
	EndAdditiveBlending();
	
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
			PlayerEntity *player = PLAYER;
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


#ifndef NDEBUG
- (NSSet *) allTextures
{
	if (texture)
	{
		return [NSSet setWithObject:texture];
	}
	else
	{
		return nil;
	}
}
#endif

@end


@implementation Entity (OOParticleExtensions)

- (BOOL) isParticle
{
	return NO;
}

@end
