/*

Octtree.m

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

#import "Octree.h"
#import "OOMaths.h"
#import "Entity.h"
#import "OOOpenGL.h"
#include "legacy_random.h"


#ifndef NDEBUG
#define OctreeDebugLogVerbose(format, ...) do { if (EXPECT_NOT(gDebugFlags & DEBUG_OCTREE_TEXT))  OOLog(@"octree.debug", format, ## __VA_ARGS__); } while (0)
#define OctreeDebugLog(format, ...) do { if (EXPECT_NOT(gDebugFlags & DEBUG_OCTREE))  OOLog(@"octree.debug", format, ## __VA_ARGS__); } while (0)
#else
#define OctreeDebugLogVerbose(...) do {} while (0)
#define OctreeDebugLog(...) do {} while (0)
#endif


@implementation Octree

- (id) init
{
	self = [super init];
	radius = 0;
	leafs = 0;
	octree = malloc(sizeof(int));
	octree_collision = malloc(sizeof(char));
	octree[0] = 0;
	octree_collision[0] = (char)0;
	hasCollision = NO;
	return self;
}

- (void) dealloc
{
	free(octree);
	free(octree_collision);
	[super dealloc];
}

- (GLfloat) radius
{
	return radius;
}

- (int) leafs
{
	return leafs;
}

- (int*) octree
{
	return octree;
}

- (BOOL)	hasCollision
{
	return hasCollision;
}

- (void)	setHasCollision:(BOOL) value
{
	hasCollision = value;
}

- (unsigned char*)	octree_collision
{
	return octree_collision;
}

- (Octree_details)	octreeDetails
{
	Octree_details	details;
	details.octree = octree;
	details.radius = radius;
	details.octree_collision = octree_collision;
	return details;
}

- (id) initWithRepresentationOfOctree:(GLfloat) octRadius :(NSObject*) octreeArray :(int) leafsize
{
	self = [super init];
	
	radius = octRadius;
	leafs = leafsize;
	octree = malloc(leafsize *sizeof(int));
	octree_collision = malloc(leafsize *sizeof(char));
	hasCollision = NO;
	
	int i;
	for (i = 0; i< leafsize; i++)
	{
		octree[i] = 0;
		octree_collision[i] = (char)0;
	}
	
	copyRepresentationIntoOctree( octreeArray, octree, 0, 1);
	
	return self;
}

- (id) initWithDictionary:(NSDictionary*) dict
{
	self = [super init];
	
	radius = [[dict objectForKey:@"radius"] floatValue];
	leafs = [[dict objectForKey:@"leafs"] intValue];
	octree = malloc(leafs *sizeof(int));
	octree_collision = malloc(leafs *sizeof(char));
	int* data = (int*)[(NSData*)[dict objectForKey:@"octree"] bytes];
	hasCollision = NO;
	
	int i;
	for (i = 0; i< leafs; i++)
	{
		octree[i] = data[i];
		octree_collision[i] = (char)0;
	}
	
	return self;
}

- (Octree*) octreeScaledBy:(GLfloat) factor
{
	GLfloat temp = radius;
	radius *= factor;
	Octree* result = [[Octree alloc] initWithDictionary:[self dict]];
	radius = temp;
	return [result autorelease];
}

int copyRepresentationIntoOctree(NSObject* theRep, int* theBuffer, int atLocation, int nextFreeLocation)
{
	if ([theRep isKindOfClass:[NSNumber class]])	// ie. a terminating leaf
	{
		if ([(NSNumber*)theRep intValue] != 0)
		{
			theBuffer[atLocation] = -1;
			return nextFreeLocation;
		}
		else
		{
			theBuffer[atLocation] = 0;
			return nextFreeLocation;
		}
	}
	if ([theRep isKindOfClass:[NSArray class]])		// ie. a subtree
	{
		NSArray* theArray = (NSArray*)theRep;
		int i;
		int theNextSpace = nextFreeLocation + 8;
		for (i = 0; i < 8; i++)
		{
			NSObject* rep = [theArray objectAtIndex:i];
			theNextSpace = copyRepresentationIntoOctree( rep, theBuffer, nextFreeLocation + i, theNextSpace);
		}
		theBuffer[atLocation] = nextFreeLocation - atLocation;	// now a relative reference
		return theNextSpace;
	}
	
	OOLog(@"octree.unarchive.failed", @"**** some error creating octree *****");
	return nextFreeLocation;
}

Vector offsetForOctant(int oct, GLfloat r)
{
	return make_vector(((GLfloat)0.5 - (GLfloat)((oct >> 2) & 1)) * r, ((GLfloat)0.5 - (GLfloat)((oct >> 1) & 1)) * r, ((GLfloat)0.5 - (GLfloat)(oct & 1)) * r);
}

- (void) drawOctree
{
	// it's a series of cubes
	[self drawOctreeFromLocation:0 :radius : kZeroVector];
}

- (void) drawOctreeFromLocation:(int) loc :(GLfloat) scale :(Vector) offset
{
	if (octree[loc] == 0)
		return;
	if (octree[loc] == -1)	// full
	{
		// draw a cube
		glDisable(GL_CULL_FACE);			// face culling
		
		glDisable(GL_TEXTURE_2D);

		glBegin(GL_LINE_STRIP);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		
		glEnd();
		
		glBegin(GL_LINE_STRIP);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glEnd();
			
		glBegin(GL_LINES);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glEnd();
			
		glEnable(GL_CULL_FACE);			// face culling
		return;
	}
	if (octree[loc] > 0)
	{
		GLfloat sc = 0.5 * scale;
		glColor4f( 0.4, 0.4, 0.4, 0.5);	// gray translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 0 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z - sc)];
		glColor4f( 0.0, 0.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 1 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z + sc)];
		glColor4f( 0.0, 1.0, 0.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 2 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z - sc)];
		glColor4f( 0.0, 1.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 3 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z + sc)];
		glColor4f( 1.0, 0.0, 0.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 4 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z - sc)];
		glColor4f( 1.0, 0.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 5 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z + sc)];
		glColor4f( 1.0, 1.0, 0.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 6 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z - sc)];
		glColor4f( 1.0, 1.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:	loc + octree[loc] + 7 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z + sc)];
	}
}

BOOL drawTestForCollisions;
- (void) drawOctreeCollisions
{
	// it's a series of cubes
	drawTestForCollisions = NO;
	if (hasCollision)
		[self drawOctreeCollisionFromLocation:0 :radius : kZeroVector];
	hasCollision = drawTestForCollisions;
}

- (void) drawOctreeCollisionFromLocation:(int) loc :(GLfloat) scale :(Vector) offset
{
	if (octree[loc] == 0)
		return;
	if ((octree[loc] != 0)&&(octree_collision[loc] != (unsigned char)0))	// full - draw
	{
		GLfloat red = (GLfloat)(octree_collision[loc])/255.0;
		glColor4f( 1.0, 0.0, 0.0, red);	// 50% translucent
		
		drawTestForCollisions = YES;
		octree_collision[loc]--;
		
		// draw a cube
		glDisable(GL_CULL_FACE);			// face culling
		
		glDisable(GL_TEXTURE_2D);

		glBegin(GL_LINE_STRIP);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		
		glEnd();
		
		glBegin(GL_LINE_STRIP);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glEnd();
			
		glBegin(GL_LINES);
			
		glVertex3f(-scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glVertex3f(-scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(-scale + offset.x, scale + offset.y, scale + offset.z);
		
		glVertex3f(scale + offset.x, scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, scale + offset.y, scale + offset.z);
		
		glVertex3f(scale + offset.x, -scale + offset.y, -scale + offset.z);
		glVertex3f(scale + offset.x, -scale + offset.y, scale + offset.z);
		
		glEnd();
			
		glEnable(GL_CULL_FACE);			// face culling
	}
	if (octree[loc] > 0)
	{
		GLfloat sc = 0.5 * scale;
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 0 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 1 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 2 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 3 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 4 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 5 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 6 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:	loc + octree[loc] + 7 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z + sc)];
	}
}

BOOL hasCollided = NO;
GLfloat hit_dist = 0.0;
BOOL	isHitByLine(int* octbuffer, unsigned char* collbuffer, int level, GLfloat rad, Vector v0, Vector v1, Vector off, int face_hit)
{
	// displace the line by the offset
	Vector u0 = make_vector( v0.x + off.x, v0.y + off.y, v0.z + off.z);
	Vector u1 = make_vector( v1.x + off.x, v1.y + off.y, v1.z + off.z);
	
	OctreeDebugLogVerbose(@"DEBUG octant: [%d] radius: %.2f vs. line: ( %.2f, %.2f, %.2f) - ( %.2f, %.2f, %.2f)", 
		level, rad, u0.x, u0.y, u0.z, u1.x, u1.y, u1.z);

	if (octbuffer[level] == 0)
	{
		OctreeDebugLogVerbose(@"DEBUG Hit an empty octant: [%d]", level);
		return NO;
	}
	
	if (octbuffer[level] == -1)
	{
		OctreeDebugLogVerbose(@"DEBUG Hit a solid octant: [%d]", level);
		collbuffer[level] = 2;	// green
		hit_dist = sqrt( u0.x * u0.x + u0.y * u0.y + u0.z * u0.z);
		return YES;
	}
	
	int faces = face_hit;
	if (faces == 0)
		faces = lineCubeIntersection( u0, u1, rad);

	if (faces == 0)
	{
		OctreeDebugLogVerbose(@"----> Line misses octant: [%d].", level);
		return NO;
	}
	
	int octantIntersected = 0;
	
	if (faces > 0)
	{
		Vector vi = lineIntersectionWithFace( u0, u1, faces, rad);
		
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

		OctreeDebugLogVerbose(@"----> found intersection with face 0x%2x of cube of radius %.2f at ( %.2f, %.2f, %.2f) octant:%d",
				faces, rad, vi.x, vi.y, vi.z, octantIntersected);
	}
	else
	{	
		OctreeDebugLogVerbose(@"----> inside cube of radius %.2f octant:%d", rad, octantIntersected);
		faces = 0;	// inside the cube!
	}
	
	hasCollided = YES;
	
	collbuffer[level] = 1;	// red
	
	OctreeDebugLogVerbose(@"----> testing octants...");
	
	int nextlevel = level + octbuffer[level];
		
	GLfloat rd2 = 0.5 * rad;
	
	// first test the intersected octant, then the three adjacent, then the next three adjacent, the finally the diagonal octant
	int oct0, oct1, oct2, oct3;	// test oct0 then oct1, oct2, oct3 then (7 - oct1), (7 - oct2), (7 - oct3) then (7 - oct0)
	oct0 = octantIntersected;
	oct1 = oct0 ^ 0x01;	// adjacent x
	oct2 = oct0 ^ 0x02;	// adjacent y
	oct3 = oct0 ^ 0x04;	// adjacent z

	Vector moveLine = off;

	OctreeDebugLogVerbose(@"----> testing first octant hit [+%d]", oct0);
	if (octbuffer[nextlevel + oct0])
	{
		moveLine = offsetForOctant( oct0, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct0, rd2, u0, u1, moveLine, faces)) return YES;	// first octant
	}
		
	// test the three adjacent octants

	OctreeDebugLogVerbose(@"----> testing next three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	
	if (octbuffer[nextlevel + oct1])
	{
		moveLine = offsetForOctant( oct1, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct1, rd2, u0, u1, moveLine, 0)) return YES;	// second octant
	}
	if (octbuffer[nextlevel + oct2])
	{
		moveLine = offsetForOctant( oct2, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct2, rd2, u0, u1, moveLine, 0)) return YES;	// third octant
	}
	if (octbuffer[nextlevel + oct3])
	{
		moveLine = offsetForOctant( oct3, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct3, rd2, u0, u1, moveLine, 0)) return YES;	// fourth octant
	}
	
	// go to the next four octants
	
	oct0 ^= 0x07;	oct1 ^= 0x07;	oct2 ^= 0x07;	oct3 ^= 0x07;
	
	OctreeDebugLogVerbose(@"----> testing back three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	
	if (octbuffer[nextlevel + oct1])
	{
		moveLine = offsetForOctant( oct1, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct1, rd2, u0, u1, moveLine, 0)) return YES;	// fifth octant
	}
	if (octbuffer[nextlevel + oct2])
	{
		moveLine = offsetForOctant( oct2, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct2, rd2, u0, u1, moveLine, 0)) return YES;	// sixth octant
	}
	if (octbuffer[nextlevel + oct3])
	{
		moveLine = offsetForOctant( oct3, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct3, rd2, u0, u1, moveLine, 0)) return YES;	// seventh octant
	}
	
	// and check the last octant
	OctreeDebugLogVerbose(@"----> testing final octant [+%d]", oct0);
	
	if (octbuffer[nextlevel + oct0])
	{
		moveLine = offsetForOctant( oct0, rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct0, rd2, u0, u1, moveLine, 0)) return YES;	// last octant
	}
	
	return NO;
}

- (GLfloat) isHitByLine: (Vector) v0: (Vector) v1
{
	int i;
	for (i = 0; i< leafs; i++) octree_collision[i] = (char)0;
	hasCollided = NO;
	
	if (isHitByLine(octree, octree_collision, 0, radius, v0, v1, kZeroVector, 0))
	{
		OctreeDebugLogVerbose(@"DEBUG Hit at distance %.2f", hit_dist);
		hasCollision = hasCollided;
		return hit_dist;
	}
	else
	{
		OctreeDebugLogVerbose(@"DEBUG Missed!", hit_dist);
		hasCollision = hasCollided;
		return 0.0;
	}
}

int change_oct[] = {	0,	1,	2,	4,	3,	5,	6,	7};	// used to move from nearest to furthest octant

BOOL	isHitByOctree(	Octree_details axialDetails,
						Octree_details otherDetails, Vector otherPosition, Triangle other_ijk)
{
	int*	axialBuffer = axialDetails.octree;
	int*	otherBuffer = otherDetails.octree;

	if (axialBuffer[0] == 0)
	{
		OctreeDebugLogVerbose(@"DEBUG Axial octree is empty.");
		return NO;
	}
	
	if (!otherBuffer)
	{
		OctreeDebugLogVerbose(@"DEBUG Other octree is undefined.");
		return NO;
	}
	
	if (otherBuffer[0] == 0)
	{
		OctreeDebugLogVerbose(@"DEBUG Other octree is empty.");
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
			OctreeDebugLogVerbose(@"----> Other sphere does not intersect axial cube");
			return NO;
		}
	}
	else	// test axial sphere against other cube
	{
		Vector	d2 = make_vector( - otherPosition.x, - otherPosition.y, -otherPosition.z);
		Vector	axialPosition = resolveVectorInIJK( d2, other_ijk);
		if ((axialPosition.x + axialRadius < -otherRadius)||(axialPosition.x - axialRadius > otherRadius)||
			(axialPosition.y + axialRadius < -otherRadius)||(axialPosition.y - axialRadius > otherRadius)||
			(axialPosition.z + axialRadius < -otherRadius)||(axialPosition.z - axialRadius > otherRadius))
		{
			OctreeDebugLogVerbose(@"----> Axial sphere does not intersect other cube");
			return NO;
		}
	}
	
	// from here on, this Octree and the other Octree are considered to be intersecting
	Octree_details	nextDetails;	// for subdivision (may not be required)
	unsigned char*	axialCollisionBuffer = axialDetails.octree_collision;
	unsigned char*	otherCollisionBuffer = otherDetails.octree_collision;
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
		
		OctreeDebugLogVerbose(@"----> testing other octants...");
		
		// work out the nearest octant to the axial octree
		int	nearest_oct = ((otherPosition.x > 0.0)? 0:4)|((otherPosition.y > 0.0)? 0:2)|((otherPosition.z > 0.0)? 0:1);
		
		int				nextLevel			= otherBuffer[0];
		int*			nextBuffer			= &otherBuffer[nextLevel];
		unsigned char*	nextCollisionBuffer	= &otherCollisionBuffer[nextLevel];
		Vector	voff, nextPosition;
		nextDetails.radius = 0.5 * otherRadius;
		int	i, oct;
		for (i = 0; i < 8; i++)
		{
			oct = nearest_oct ^ change_oct[i];	// work from nearest to furthest
			if (nextBuffer[oct])	// don't test empty octants
			{
				nextDetails.octree = &nextBuffer[oct];
				nextDetails.octree_collision = &nextCollisionBuffer[oct];
				
				voff = resolveVectorInIJK( offsetForOctant( oct, otherRadius), other_ijk);
				nextPosition.x = otherPosition.x - voff.x;
				nextPosition.y = otherPosition.y - voff.y;
				nextPosition.z = otherPosition.z - voff.z;
				if (isHitByOctree(	axialDetails, nextDetails, nextPosition, other_ijk))	// test octant
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
	
	OctreeDebugLogVerbose(@"----> testing axial octants...");
	
	// work out the nearest octant to the other octree
	int	nearest_oct = ((otherPosition.x > 0.0)? 4:0)|((otherPosition.y > 0.0)? 2:0)|((otherPosition.z > 0.0)? 1:0);
	
	int		nextLevel = axialBuffer[0];
	int*	nextBuffer = &axialBuffer[nextLevel];
	unsigned char* nextCollisionBuffer = &axialCollisionBuffer[nextLevel];
	nextDetails.radius = 0.5 * axialRadius;
	Vector	voff, nextPosition;
	int		i, oct;
	for (i = 0; i < 8; i++)
	{
		oct = nearest_oct ^ change_oct[i];	// work from nearest to furthest
		if (nextBuffer[oct])	// don't test empty octants
		{
			nextDetails.octree = &nextBuffer[oct];
			nextDetails.octree_collision = &nextCollisionBuffer[oct];
			
			voff = offsetForOctant(oct, axialRadius);
			nextPosition.x = otherPosition.x + voff.x;
			nextPosition.y = otherPosition.y + voff.y;
			nextPosition.z = otherPosition.z + voff.z;
			if (isHitByOctree(	nextDetails, otherDetails, nextPosition, other_ijk))
				return YES;	// test octant
		}
	}
	// otherwise we're done!
	return NO;
}

- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk
{
	BOOL hit = isHitByOctree( [self octreeDetails], [other octreeDetails], v0, ijk);
	
	hasCollision = hasCollision | hit;
	[other setHasCollision: [other hasCollision] | hit];
	
	return hit; 
}

- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk andScales: (GLfloat) s1: (GLfloat) s2
{
	Octree_details details1 = [self octreeDetails];
	Octree_details details2 = [other octreeDetails];
	
	details1.radius *= s1;
	details2.radius *= s2;
	
	BOOL hit = isHitByOctree( details1, details2, v0, ijk);
	
	hasCollision = hasCollision | hit;
	[other setHasCollision: [other hasCollision] | hit];
	
	return hit; 
}



- (NSDictionary*)	dict;
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithFloat:radius],	@"radius",
		[NSNumber numberWithInt:leafs],		@"leafs",
		[NSData dataWithBytes:(const void *)octree length: leafs * sizeof(int)], @"octree",
		nil];
}

- (GLfloat) volume
{
	return volumeOfOctree([self octreeDetails]);
}

GLfloat volumeOfOctree(Octree_details octree_details)
{
	int*	octBuffer = octree_details.octree;
	GLfloat octRadius = octree_details.radius;
	
	if (octBuffer[0] == 0)
		return 0.0f;
	
	if (octBuffer[0] == -1)
		return octRadius * octRadius * octRadius;
	
	// we are not empty or solid
	// we sum the volume of each of our octants
	GLfloat sumVolume = 0.0f;
	Octree_details	nextDetails;	// for subdivision (may not be required)
	int		nextLevel = octBuffer[0];
	int*	nextBuffer = &octBuffer[nextLevel];
	nextDetails.radius = 0.5 * octRadius;
	int		i;
	for (i = 0; i < 8; i++)
	{
		if (nextBuffer[i])	// don't test empty octants
		{
			nextDetails.octree = &nextBuffer[i];
			sumVolume += volumeOfOctree(nextDetails);
		}
	}
	return sumVolume;
}

Vector randomFullNodeFrom( Octree_details details, Vector offset)
{
	int*	octBuffer = details.octree;
	GLfloat octRadius = details.radius;
	
	if (octBuffer[0] == 0)
		return offset;
	
	if (octBuffer[0] == -1)
		return offset;
	
	// we are not empty or solid
	// we sum the volume of each of our octants
	Octree_details	nextDetails;	// for subdivision (may not be required)
	int		nextLevel = octBuffer[0];
	int*	nextBuffer = &octBuffer[nextLevel];
	nextDetails.radius = 0.5 * octRadius;
	int		i, oct;
	oct = ranrot_rand() & 7;
	for (i = 0; i < 8; i++)
	{
		int octant = oct ^ i;
		if (nextBuffer[octant])	// don't test empty octants
		{
			nextDetails.octree = &nextBuffer[octant];
			Vector voff = offsetForOctant( octant, octRadius);
			voff.x += offset.x;
			voff.y += offset.y;
			voff.z += offset.z;
			return randomFullNodeFrom( nextDetails, voff);
		}
	}
	return offset;
}

@end
