/*

Octree.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "Octree.h"
#import "OOMaths.h"
#import "Entity.h"
#import "OOOpenGL.h"
#import "OODebugGLDrawing.h"
#import "OOMacroOpenGL.h"
#import "OODebugFlags.h"
#import "NSObjectOOExtensions.h"
#import "OOCollectionExtractors.h"


#ifndef NDEBUG
#define OctreeDebugLog(format, ...) do { if (EXPECT_NOT(gDebugFlags & DEBUG_OCTREE_LOGGING))  OOLog(@"octree.debug", format, ## __VA_ARGS__); } while (0)
#else
#define OctreeDebugLog(...) do {} while (0)
#define OctreeDebugLog(...) do {} while (0)
#endif


typedef struct
{
	GLfloat				radius;
	const int			*octree;
	unsigned char		*octree_collision;
} Octree_details;


@interface Octree (Private)

#ifndef OODEBUGLDRAWING_DISABLE

- (void) drawOctreeFromLocation:(uint32_t)loc :(GLfloat)scale :(Vector)offset;
- (void) drawOctreeCollisionFromLocation:(uint32_t)loc :(GLfloat)scale :(Vector)offset;

- (BOOL) hasCollision;
- (void) setHasCollision:(BOOL)value;

#endif

- (Octree_details) octreeDetails;

@end


static const int change_oct[] = { 0, 1, 2, 4, 3, 5, 6, 7 };	// used to move from nearest to furthest octant


static BOOL isHitByLine(const int *octbuffer, unsigned char *collbuffer, int level, GLfloat rad, Vector v0, Vector v1, Vector off, int face_hit);
static GLfloat volumeOfOctree(Octree_details octree_details, unsigned depthLimit);
static Vector randomFullNodeFrom(Octree_details details, Vector offset);

static BOOL	isHitByOctree(Octree_details axialDetails, Octree_details otherDetails, Vector delta, Triangle other_ijk);


@implementation Octree

- (id) init
{
	// -init makes no sense, since octrees are immutable.
	[self release];
	[NSException raise:NSInternalInconsistencyException format:@"Call of invalid initializer %s", __FUNCTION__];
	return nil;
}


// Designated initializer.
- (id) initWithData:(NSData *)data
			 radius:(GLfloat)radius
{
	if ((self = [super init]))
	{
		_data = [data copy];
		_radius = radius;
		
		_nodeCount = [_data length] / sizeof *_octree;
		_octree = [_data bytes];
		
		_collisionOctree = calloc(1, _nodeCount);
		if (_octree == NULL || _collisionOctree == NULL)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (id) initWithDictionary:(NSDictionary *)dict
{
	NSData *data = [dict objectForKey:@"octree"];
	if (![data isKindOfClass:[NSData class]] || ([data length] % sizeof (int)) != 0)
	{
		// Invalid representation.
		[self release];
		return nil;
	}
	
	return [self initWithData:data radius:[dict oo_floatForKey:@"radius"]];
}


- (void) dealloc
{
	DESTROY(_data);
	free(_collisionOctree);
	
	[super dealloc];
}


- (BOOL) hasCollision
{
	return _hasCollision;
}


- (void) setHasCollision:(BOOL)value
{
	_hasCollision = !!value;
}


- (Octree_details) octreeDetails
{
	Octree_details details =
	{
		.octree = _octree,
		.radius = _radius,
		.octree_collision = _collisionOctree
	};
	return details;
}


- (Octree *) octreeScaledBy:(GLfloat)factor
{
	// Since octree data is immutable, we can share.
	return [[[Octree alloc] initWithData:_data radius:_radius * factor] autorelease];
}


static Vector offsetForOctant(int oct, GLfloat r)
{
	return make_vector((0.5f - (GLfloat)((oct >> 2) & 1)) * r, (0.5f - (GLfloat)((oct >> 1) & 1)) * r, (0.5f - (GLfloat)(oct & 1)) * r);
}


#ifndef OODEBUGLDRAWING_DISABLE

- (void) drawOctree
{
	OODebugWFState state = OODebugBeginWireframe(NO);
	
	OO_ENTER_OPENGL();
	OOGL(glEnable(GL_BLEND));
	OOGLBEGIN(GL_LINES);
	glColor4f(0.4f, 0.4f, 0.4f, 0.5f);
	
	// it's a series of cubes
	[self drawOctreeFromLocation:0 :_radius : kZeroVector];
	
	OOGLEND();
	
	OODebugEndWireframe(state);
	OOCheckOpenGLErrors(@"Octree after drawing %@", self);
}


#if 0
#define OCTREE_COLOR(r, g, b, a) glColor4f(r, g, b, a)
#else
#define OCTREE_COLOR(r, g, b, a) do {} while (0)
#endif


- (void) drawOctreeFromLocation:(uint32_t)loc :(GLfloat)scale :(Vector)offset
{
	if (_octree[loc] == 0)
	{
		return;
	}
	
	OO_ENTER_OPENGL();
	
	if (_octree[loc] == -1)	// full
	{
		// draw a cube
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		
			
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
	}
	else if (_octree[loc] > 0)
	{
		GLfloat sc = 0.5f * scale;
		OCTREE_COLOR(0.4f, 0.4f, 0.4f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 0 :sc :make_vector(offset.x - sc, offset.y - sc, offset.z - sc)];
		OCTREE_COLOR(0.0f, 0.0f, 1.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 1 :sc :make_vector(offset.x - sc, offset.y - sc, offset.z + sc)];
		OCTREE_COLOR(0.0f, 1.0f, 0.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 2 :sc :make_vector(offset.x - sc, offset.y + sc, offset.z - sc)];
		OCTREE_COLOR(0.0f, 1.0f, 1.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 3 :sc :make_vector(offset.x - sc, offset.y + sc, offset.z + sc)];
		OCTREE_COLOR(1.0f, 0.0f, 0.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 4 :sc :make_vector(offset.x + sc, offset.y - sc, offset.z - sc)];
		OCTREE_COLOR(1.0f, 0.0f, 1.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 5 :sc :make_vector(offset.x + sc, offset.y - sc, offset.z + sc)];
		OCTREE_COLOR(1.0f, 1.0f, 0.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 6 :sc :make_vector(offset.x + sc, offset.y + sc, offset.z - sc)];
		OCTREE_COLOR(1.0f, 1.0f, 1.0f, 0.5f);
		[self drawOctreeFromLocation:loc + _octree[loc] + 7 :sc :make_vector(offset.x + sc, offset.y + sc, offset.z + sc)];
	}
}


static BOOL drawTestForCollisions;

- (void) drawOctreeCollisions
{
	OODebugWFState state = OODebugBeginWireframe(NO);
	
	// it's a series of cubes
	drawTestForCollisions = NO;
	if (_hasCollision)
	{
		[self drawOctreeCollisionFromLocation:0 :_radius :kZeroVector];
	}
	_hasCollision = drawTestForCollisions;
	
	OODebugEndWireframe(state);
	OOCheckOpenGLErrors(@"Octree after drawing collisions for %@", self);
}


- (void) drawOctreeCollisionFromLocation:(uint32_t)loc :(GLfloat)scale :(Vector)offset
{
	if (_octree[loc] == 0)
	{
		return;
	}
	
	if ((_octree[loc] != 0)&&(_collisionOctree[loc] != (unsigned char)0))	// full - draw
	{
		OO_ENTER_OPENGL();
		
		GLfloat red = (GLfloat)(_collisionOctree[loc])/255.0;
		glColor4f(1.0, 0.0, 0.0, red);	// 50% translucent
		
		drawTestForCollisions = YES;
		_collisionOctree[loc]--;
		
		// draw a cube
		OOGL(glDisable(GL_CULL_FACE));		// face culling
		
		OOGL(glDisable(GL_TEXTURE_2D));

		OOGLBEGIN(GL_LINE_STRIP);
			glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
			glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
			glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
			glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
			glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		OOGLEND();
		
		OOGLBEGIN(GL_LINE_STRIP);
			glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
			glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
			glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
			glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
			glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		OOGLEND();
			
		OOGLBEGIN(GL_LINES);
			glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
			glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
			
			glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
			glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
			
			glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
			glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
			
			glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
			glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		OOGLEND();
			
		OOGL(glEnable(GL_CULL_FACE));		// face culling
	}
	if (_octree[loc] > 0)
	{
		GLfloat sc = 0.5f * scale;
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 0 :sc :make_vector(offset.x - sc, offset.y - sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 1 :sc :make_vector(offset.x - sc, offset.y - sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 2 :sc :make_vector(offset.x - sc, offset.y + sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 3 :sc :make_vector(offset.x - sc, offset.y + sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 4 :sc :make_vector(offset.x + sc, offset.y - sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 5 :sc :make_vector(offset.x + sc, offset.y - sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 6 :sc :make_vector(offset.x + sc, offset.y + sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:loc + _octree[loc] + 7 :sc :make_vector(offset.x + sc, offset.y + sc, offset.z + sc)];
	}
}
#endif // OODEBUGLDRAWING_DISABLE


static BOOL isHitByLineSub(const int *octbuffer, unsigned char *collbuffer, int nextLevel, GLfloat rad, GLfloat rd2, Vector v0, Vector v1, int octantMask)
{
	if (octbuffer[nextLevel + octantMask])
	{
		Vector moveLine = offsetForOctant(octantMask, rad);
		return isHitByLine(octbuffer, collbuffer, nextLevel + octantMask, rd2, v0, v1, moveLine, 0);
	}
	else  return NO;
}


static BOOL hasCollided = NO;
static GLfloat hit_dist = 0.0;
static BOOL isHitByLine(const int *octbuffer, unsigned char *collbuffer, int level, GLfloat rad, Vector v0, Vector v1, Vector off, int face_hit)
{
	// displace the line by the offset
	Vector u0 = make_vector(v0.x + off.x, v0.y + off.y, v0.z + off.z);
	Vector u1 = make_vector(v1.x + off.x, v1.y + off.y, v1.z + off.z);
	
	OctreeDebugLog(@"DEBUG octant: [%d] radius: %.2f vs. line: (%.2f, %.2f, %.2f) - (%.2f, %.2f, %.2f)",
		level, rad, u0.x, u0.y, u0.z, u1.x, u1.y, u1.z);

	if (octbuffer[level] == 0)
	{
		OctreeDebugLog(@"DEBUG Hit an empty octant: [%d]", level);
		return NO;
	}
	
	if (octbuffer[level] == -1)
	{
		OctreeDebugLog(@"DEBUG Hit a solid octant: [%d]", level);
		collbuffer[level] = 2;	// green
		hit_dist = sqrt(u0.x * u0.x + u0.y * u0.y + u0.z * u0.z);
		return YES;
	}
	
	int faces = face_hit;
	if (faces == 0)
		faces = lineCubeIntersection(u0, u1, rad);

	if (faces == 0)
	{
		OctreeDebugLog(@"----> Line misses octant: [%d].", level);
		return NO;
	}
	
	int octantIntersected = 0;
	
	if (faces > 0)
	{
		Vector vi = lineIntersectionWithFace(u0, u1, faces, rad);
		
		if (CUBE_FACE_FRONT & faces)
			octantIntersected = ((vi.x < 0.0)? 1: 5) + ((vi.y < 0.0)? 0: 2);
		if (CUBE_FACE_BACK & faces)
			octantIntersected = ((vi.x < 0.0)? 0: 4) + ((vi.y < 0.0)? 0: 2);
		
		if (CUBE_FACE_RIGHT & faces)
			octantIntersected = ((vi.y < 0.0)? 4: 6) + ((vi.z < 0.0)? 0: 1);
		if (CUBE_FACE_LEFT & faces)
			octantIntersected = ((vi.y < 0.0)? 0: 2) + ((vi.z < 0.0)? 0: 1);

		if (CUBE_FACE_TOP & faces)
			octantIntersected = ((vi.x < 0.0)? 2: 6) + ((vi.z < 0.0)? 0: 1);
		if (CUBE_FACE_BOTTOM & faces)
			octantIntersected = ((vi.x < 0.0)? 0: 4) + ((vi.z < 0.0)? 0: 1);

		OctreeDebugLog(@"----> found intersection with face 0x%2x of cube of radius %.2f at (%.2f, %.2f, %.2f) octant:%d",
				faces, rad, vi.x, vi.y, vi.z, octantIntersected);
	}
	else
	{	
		OctreeDebugLog(@"----> inside cube of radius %.2f octant:%d", rad, octantIntersected);
	}
	
	hasCollided = YES;
	
	collbuffer[level] = 1;	// red
	
	OctreeDebugLog(@"----> testing octants...");
	
	int nextLevel = level + octbuffer[level];
		
	GLfloat rd2 = 0.5f * rad;
	
	// first test the intersected octant, then the three adjacent, then the next three adjacent, the finally the diagonal octant
	int oct0, oct1, oct2, oct3;	// test oct0 then oct1, oct2, oct3 then (7 - oct1), (7 - oct2), (7 - oct3) then (7 - oct0)
	oct0 = octantIntersected;
	oct1 = oct0 ^ 0x01;	// adjacent x
	oct2 = oct0 ^ 0x02;	// adjacent y
	oct3 = oct0 ^ 0x04;	// adjacent z
	
	OctreeDebugLog(@"----> testing first octant hit [+%d]", oct0);
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct0))  return YES;	// first octant
		
	// test the three adjacent octants

	OctreeDebugLog(@"----> testing next three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct1))  return YES;	// second octant
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct2))  return YES;	// third octant
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct3))  return YES;	// fourth octant
	
	// go to the next four octants
	
	oct0 ^= 0x07;	oct1 ^= 0x07;	oct2 ^= 0x07;	oct3 ^= 0x07;
	
	OctreeDebugLog(@"----> testing back three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct1))  return YES;	// fifth octant
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct2))  return YES;	// sixth octant
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct3))  return YES;	// seventh octant
	
	// and check the last octant
	OctreeDebugLog(@"----> testing final octant [+%d]", oct0);
	if (isHitByLineSub(octbuffer, collbuffer, nextLevel, rad, rd2, u0, u1, oct0))  return YES;	// last octant
	
	return NO;
}

- (GLfloat) isHitByLine:(Vector)v0 :(Vector)v1
{
	memset(_collisionOctree, 0, _nodeCount * sizeof *_collisionOctree);
	hasCollided = NO;
	
	if (isHitByLine(_octree, _collisionOctree, 0, _radius, v0, v1, kZeroVector, 0))
	{
		OctreeDebugLog(@"DEBUG Hit at distance %.2f", hit_dist);
		_hasCollision = hasCollided;
		return hit_dist;
	}
	else
	{
		OctreeDebugLog(@"DEBUG Missed!");
		_hasCollision = hasCollided;
		return 0.0f;
	}
}


static BOOL isHitByOctree(Octree_details axialDetails,
						  Octree_details otherDetails, Vector otherPosition, Triangle other_ijk)
{
	const int *axialBuffer = axialDetails.octree;
	const int *otherBuffer = otherDetails.octree;

	if (axialBuffer[0] == 0)
	{
		OctreeDebugLog(@"DEBUG Axial octree is empty.");
		return NO;
	}
	
	if (!otherBuffer)
	{
		OctreeDebugLog(@"DEBUG Other octree is undefined.");
		return NO;
	}
	
	if (otherBuffer[0] == 0)
	{
		OctreeDebugLog(@"DEBUG Other octree is empty.");
		return NO;
	}
	
	GLfloat axialRadius = axialDetails.radius;
	GLfloat otherRadius = otherDetails.radius;
	
	if (otherRadius < axialRadius) // test axial cube against other sphere
	{
		// 'crude and simple' - test sphere against cube...
		if ((otherPosition.x + otherRadius < -axialRadius)||(otherPosition.x - otherRadius > axialRadius)||
			(otherPosition.y + otherRadius < -axialRadius)||(otherPosition.y - otherRadius > axialRadius)||
			(otherPosition.z + otherRadius < -axialRadius)||(otherPosition.z - otherRadius > axialRadius))
		{
			OctreeDebugLog(@"----> Other sphere does not intersect axial cube");
			return NO;
		}
	}
	else	// test axial sphere against other cube
	{
		Vector	d2 = vector_flip(otherPosition);
		Vector	axialPosition = resolveVectorInIJK(d2, other_ijk);
		if ((axialPosition.x + axialRadius < -otherRadius)||(axialPosition.x - axialRadius > otherRadius)||
			(axialPosition.y + axialRadius < -otherRadius)||(axialPosition.y - axialRadius > otherRadius)||
			(axialPosition.z + axialRadius < -otherRadius)||(axialPosition.z - axialRadius > otherRadius))
		{
			OctreeDebugLog(@"----> Axial sphere does not intersect other cube");
			return NO;
		}
	}
	
	// from here on, this Octree and the other Octree are considered to be intersecting
	unsigned char	*axialCollisionBuffer = axialDetails.octree_collision;
	unsigned char	*otherCollisionBuffer = otherDetails.octree_collision;
	if (axialBuffer[0] == -1)
	{
		// we are SOLID - is the other octree?
		if (otherBuffer[0] == -1)
		{
			// YES so octrees collide
			axialCollisionBuffer[0] = (unsigned char)255;	// mark
			otherCollisionBuffer[0] = (unsigned char)255;	// mark
			
			OctreeDebugLog(@"DEBUG Octrees collide!");
			return YES;
		}
		// the other octree must be decomposed
		// and each of its octants tested against the axial octree
		// if any of them collides with this octant
		// then we have a solid collision
		
		OctreeDebugLog(@"----> testing other octants...");
		
		// work out the nearest octant to the axial octree
		int	nearest_oct = ((otherPosition.x > 0.0)? 0:4)|((otherPosition.y > 0.0)? 0:2)|((otherPosition.z > 0.0)? 0:1);
		
		int				nextLevel = otherBuffer[0];
		const int		*nextBuffer = &otherBuffer[nextLevel];
		unsigned char	*nextCollisionBuffer = &otherCollisionBuffer[nextLevel];
		Octree_details	nextDetails;
		Vector			voff, nextPosition;
		unsigned		i, oct;
		
		nextDetails.radius = 0.5f * otherRadius;
		for (i = 0; i < 8; i++)
		{
			oct = nearest_oct ^ change_oct[i];	// work from nearest to furthest
			if (nextBuffer[oct])	// don't test empty octants
			{
				nextDetails.octree = &nextBuffer[oct];
				nextDetails.octree_collision = &nextCollisionBuffer[oct];
				
				voff = resolveVectorInIJK(offsetForOctant(oct, otherRadius), other_ijk);
				nextPosition = vector_subtract(otherPosition, voff);
				if (isHitByOctree(axialDetails, nextDetails, nextPosition, other_ijk))	// test octant
					return YES;
			}
		}
		
		// otherwise
		return NO;
	}
	// we are not solid
	// we must test each of our octants against
	// the other octree, if any of them collide
	// we have a solid collision
	
	OctreeDebugLog(@"----> testing axial octants...");
	
	// work out the nearest octant to the other octree
	int	nearest_oct = ((otherPosition.x > 0.0)? 4:0)|((otherPosition.y > 0.0)? 2:0)|((otherPosition.z > 0.0)? 1:0);
	
	int				nextLevel = axialBuffer[0];
	const int		*nextBuffer = &axialBuffer[nextLevel];
	unsigned char	*nextCollisionBuffer = &axialCollisionBuffer[nextLevel];
	Vector			nextPosition;
	Octree_details	nextDetails;
	unsigned		i, oct;
	
	nextDetails.radius = 0.5f * axialRadius;
	for (i = 0; i < 8; i++)
	{
		oct = nearest_oct ^ change_oct[i];	// work from nearest to furthest
		if (nextBuffer[oct])	// don't test empty octants
		{
			nextDetails.octree = &nextBuffer[oct];
			nextDetails.octree_collision = &nextCollisionBuffer[oct];
			
			nextPosition = vector_add(otherPosition, offsetForOctant(oct, axialRadius));
			if (isHitByOctree(nextDetails, otherDetails, nextPosition, other_ijk))
			{
				return YES;	// test octant
			}
		}
	}
	// otherwise we're done!
	return NO;
}


- (BOOL) isHitByOctree:(Octree *)other withOrigin:(Vector)v0 andIJK:(Triangle)ijk
{
	if (other == nil)  return NO;
	
	BOOL hit = isHitByOctree([self octreeDetails], [other octreeDetails], v0, ijk);
	
	_hasCollision = _hasCollision || hit;
	[other setHasCollision: [other hasCollision] || hit];
	
	return hit; 
}


- (BOOL) isHitByOctree:(Octree *)other withOrigin:(Vector)v0 andIJK:(Triangle)ijk andScales:(GLfloat) s1 :(GLfloat)s2
{
	Octree_details details1 = [self octreeDetails];
	Octree_details details2 = [other octreeDetails];
	
	details1.radius *= s1;
	details2.radius *= s2;
	
	BOOL hit = isHitByOctree(details1, details2, v0, ijk);
	
	_hasCollision = _hasCollision || hit;
	[other setHasCollision: [other hasCollision] || hit];
	
	return hit; 
}


- (NSDictionary *) dictionaryRepresentation
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		_data, @"octree",
		[NSNumber numberWithFloat:_radius],	@"radius",
		nil];
}


static GLfloat volumeOfOctree(Octree_details octree_details, unsigned depthLimit)
{
	const int *octBuffer = octree_details.octree;
	GLfloat octRadius = octree_details.radius;
	
	if (octBuffer[0] == 0)
	{
		return 0.0f;
	}
	
	if (octBuffer[0] == -1 || depthLimit == 0)
	{
		return octRadius * octRadius * octRadius;
	}
	depthLimit--;
	
	// We are not empty or solid.
	// We sum the volume of each of our octants.
	GLfloat			sumVolume = 0.0f;
	Octree_details	nextDetails;
	int				nextLevel = octBuffer[0];
	const int		*nextBuffer = &octBuffer[nextLevel];
	unsigned		i;
	
	nextDetails.radius = 0.5f * octRadius;
	nextDetails.octree_collision = NULL;	// Placate static analyzer
	
	for (i = 0; i < 8; i++)
	{
		if (nextBuffer[i])	// don't test empty octants
		{
			nextDetails.octree = &nextBuffer[i];
			sumVolume += volumeOfOctree(nextDetails, depthLimit);
		}
	}
	return sumVolume;
}


- (GLfloat) volume
{
	/*	For backwards compatibility, limit octree iteration for volume
	 calculation to five levels. Raising the limit means lower calculated
	 volumes for large ships.
	 
	 EMMSTRAN: consider raising the limit but fudging mass lock calculations
	 to compensate. See http://aegidian.org/bb/viewtopic.php?f=3&t=9176 .
	 Then again, five levels of iteration might be fine.
	 -- Ahruman 2011-03-10
	 */
	return volumeOfOctree([self octreeDetails], 5);
}


static Vector randomFullNodeFrom(Octree_details details, Vector offset)
{
	const int *octBuffer = details.octree;
	GLfloat octRadius = details.radius;
	
	if (octBuffer[0] == 0)  return offset;
	if (octBuffer[0] == -1)  return offset;
	
	// We are not empty or solid.
	// Pick a location from a random octant.
	Octree_details	nextDetails;
	int				nextLevel = octBuffer[0];
	const int		*nextBuffer = &octBuffer[nextLevel];
	unsigned		i, oct;
	
	nextDetails.radius = 0.5f * octRadius;
	nextDetails.octree_collision = NULL;
	oct = Ranrot() & 7;
	
	for (i = 0; i < 8; i++)
	{
		int octant = oct ^ i;
		if (nextBuffer[octant])	// don't test empty octants
		{
			nextDetails.octree = &nextBuffer[octant];
			Vector voff = vector_add(offset, offsetForOctant(octant, octRadius));
			return randomFullNodeFrom(nextDetails, voff);
		}
	}
	return offset;
}


- (Vector) randomPoint
{
	return randomFullNodeFrom([self octreeDetails], kZeroVector);
}


#ifndef NDEBUG
- (size_t) totalSize
{
	return [self oo_objectSize] + _nodeCount * [_data oo_objectSize] + [_data length] + _nodeCount * sizeof *_collisionOctree;
}
#endif

@end


enum
{
	/*
		Initial capacity of OOOctreeBuilder. 16 KibiEntries is enough to handle
		all but 2 built-in models; I expect similar results for OXPs, since
		geometry detail has limited effect on the octree. Large models with
		higher depth are more likely to need growth.
	*/
	kMinimumBuilderCapacity = 16 << 10
};


@implementation OOOctreeBuilder

// Extract top of state stack.
OOINLINE struct OOOctreeBuildState *State(OOOctreeBuilder *self)
{
	return &self->_stateStack[self->_level];
}


// SetNode(): set the value of an entry in _octree, making space if needed.
static void SetNode_slow(OOOctreeBuilder *self, uint32_t index, int value) NO_INLINE_FUNC;
OOINLINE void SetNode(OOOctreeBuilder *self, uint32_t index, int value)
{
	if (index < self->_capacity)
	{
		self->_octree[index] = value;
	}
	else
	{
		SetNode_slow(self, index, value);
	}
}


// InsertNode(): set the node at the current insertion point, and increment insertion point.
OOINLINE void InsertNode(OOOctreeBuilder *self, int value)
{
	NSCAssert(State(self)->remaining > 0, @"Attempt to add node to a full parent in octree builder.");
	State(self)->remaining--;
	
	SetNode(self, State(self)->insertionPoint++, value);
}


- (id) init
{
	if ((self = [super init]))
	{
		_capacity = kMinimumBuilderCapacity;
		_octree = malloc(_capacity * sizeof *_octree);
		if (_octree == NULL)
		{
			[self release];
			return nil;
		}
		
		/*
			We're initially inserting into the root slot, which must exist and
			takes a single node.
		*/
		_nodeCount = 1;
		State(self)->remaining = 1;
	}
	return self;
}


- (void) dealloc
{
	free(_octree);
	
	[super dealloc];
}


- (Octree *) buildOctreeWithRadius:(GLfloat)radius
{
	NSAssert(State(self)->remaining == 0 && _level == 0, @"Attempt to produce octree from an octree builder in an incomplete state.");
	
	size_t dataSize = _nodeCount * sizeof *_octree;
	int *resized = realloc(_octree, dataSize);
	if (resized == NULL)  resized = _octree;
	
	/*	Hand over the bytes to the data object, which will be used directly by
		the Octree.
	*/
	NSData *data = [NSData dataWithBytesNoCopy:resized
										length:dataSize
								  freeWhenDone:YES];
	
	_octree = NULL;
	_nodeCount = 0;
	_capacity = 0;
	
	return [[[Octree alloc] initWithData:data radius:radius] autorelease];
}


- (void) writeSolid
{
	InsertNode(self, -1);
}


- (void) writeEmpty
{
	InsertNode(self, 0);
}


- (void) beginInnerNode
{
	NSAssert(_level < kMaxOctreeDepth, @"Attempt to build octree exceeding maximum depth.");
	
	// Insert relative offset to next free space.
	uint32_t newInsertionPoint = _nodeCount;
	InsertNode(self, (int)_nodeCount - State(self)->insertionPoint);
	
	/*
		Leave space for eight nodes.
		
		NOTE: this may leave memory uninitialized or leave _nodeCount pointing
		past the end of the buffer. A valid sequence of eight child insertions
		will fix both these problems by writing to all of the new slots.
	*/
	_nodeCount += 8;
	
	// Push state and set up new "stack frame".
	_level++;
	State(self)->insertionPoint = newInsertionPoint;
	State(self)->remaining = 8;
}


- (void) endInnerNode
{
	NSAssert(State(self)->remaining == 0, @"Attempt to end an inner octree node with fewer than eight children.");
	NSAssert1(_level > 0, @"Unbalanced call to %s", __FUNCTION__);
	
	_level--;
	
	/*
		Check if the last eight nodes are solid. If so, we just inserted an
		entirely solid subtree and can fold it into a single solid node. An
		entirely solid subtree will always use the last eight nodes (any solid
		subtrees within a child node will have been folded already), so this
		simple approach to folding will produce an optimal result.
		
		We could do the same for empty nodes, but OOMeshToOctreeConverter will
		never recurse into an empty subtree.
	*/
	
	NSAssert(_nodeCount > 8, @"After ending an inner node, there must be at least eight nodes in buffer.");
	for (uint_fast32_t node = _nodeCount - 8; node < _nodeCount; node++)
	{
		if (_octree[node] != -1)  return;
	}
	
	// If we got here, subtree is solid; fold it into a solid node.
	_octree[State(self)->insertionPoint - 1] = -1;
	_nodeCount -= 8;
}


// Slow path for SetNode() when writing beyond _capacity: expand, then perform set.
static void SetNode_slow(OOOctreeBuilder *self, uint32_t index, int value)
{
	uint32_t newCapacity = MAX(self->_capacity * 2, (uint32_t)kMinimumBuilderCapacity);
	newCapacity = MAX(newCapacity, index + 1);
	
	int *newBuffer = realloc(self->_octree, newCapacity * sizeof *newBuffer);
	if (EXPECT_NOT(newBuffer == NULL))
	{
		[NSException raise:NSMallocException format:@"Failed to allocate memory for octree."];
	}
	
	self->_octree = newBuffer;
	self->_capacity = newCapacity;
	self->_octree[index] = value;
}

@end
