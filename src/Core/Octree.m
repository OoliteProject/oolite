/*

	Oolite

	Octree.m
	
	Created by Giles Williams on 31/01/2006.


Copyright (c) 2005, Giles C Williams
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

#import "Octree.h"
#import "vector.h"
#import "OOOpenGL.h"

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

- (char*)	octree_collision
{
	return octree_collision;
}

- (BOOL)	hasCollision
{
	return hasCollision;
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
	
//	NSLog(@"---> %d", copyRepresentationIntoOctree( octreeArray, octree, 0, 1));
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

int copyRepresentationIntoOctree(NSObject* theRep, int* theBuffer, int atLocation, int nextFreeLocation)
{
	if ([theRep isKindOfClass:[NSNumber class]])
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
	if ([theRep isKindOfClass:[NSArray class]])
	{
		NSArray* theArray = (NSArray*)theRep;
		int i;
		int theNextSpace = nextFreeLocation + 8;
		for (i = 0; i < 8; i++)
		{
			NSObject* rep = [theArray objectAtIndex:i];
			theNextSpace = copyRepresentationIntoOctree( rep, theBuffer, nextFreeLocation + i, theNextSpace);
		}
		theBuffer[atLocation] = nextFreeLocation;
		return theNextSpace;
	}
	NSLog(@"**** some error creating octree *****");
	return nextFreeLocation;
}

- (void) drawOctree
{
	// it's a series of cubes
	[self drawOctreeFromLocation:0 :radius : make_vector( 0.0f, 0.0f, 0.0f)];
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
		[self drawOctreeFromLocation:octree[loc] + 0 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z - sc)];
		glColor4f( 0.0, 0.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 1 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z + sc)];
		glColor4f( 0.0, 1.0, 0.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 2 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z - sc)];
		glColor4f( 0.0, 1.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 3 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z + sc)];
		glColor4f( 1.0, 0.0, 0.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 4 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z - sc)];
		glColor4f( 1.0, 0.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 5 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z + sc)];
		glColor4f( 1.0, 1.0, 0.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 6 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z - sc)];
		glColor4f( 1.0, 1.0, 1.0, 0.5);	// green translucent
		[self drawOctreeFromLocation:octree[loc] + 7 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z + sc)];
	}
}

- (void) drawOctreeCollisions
{
	// it's a series of cubes
	if (hasCollision)
		[self drawOctreeCollisionFromLocation:0 :radius : make_vector( 0.0f, 0.0f, 0.0f)];
}

- (void) drawOctreeCollisionFromLocation:(int) loc :(GLfloat) scale :(Vector) offset
{
	if (octree[loc] == 0)
		return;
	if ((octree[loc] != 0)&&(octree_collision[loc] != (char)0))	// full - draw
	{
		GLfloat red = (GLfloat)(octree_collision[loc] & 0x01);
		GLfloat green = 0.5 * (GLfloat)(octree_collision[loc] & 0x02);
		GLfloat blue = 0.25 * (GLfloat)(octree_collision[loc] & 0x04);
		glColor4f( red, green, blue, 0.5);	// 50% translucent
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
		[self drawOctreeCollisionFromLocation:octree[loc] + 0 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 1 :sc :make_vector( offset.x - sc, offset.y - sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 2 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 3 :sc :make_vector( offset.x - sc, offset.y + sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 4 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 5 :sc :make_vector( offset.x + sc, offset.y - sc, offset.z + sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 6 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z - sc)];
		[self drawOctreeCollisionFromLocation:octree[loc] + 7 :sc :make_vector( offset.x + sc, offset.y + sc, offset.z + sc)];
	}
}

BOOL hasCollided = NO;
GLfloat hit_dist = 0.0;
BOOL	isHitByLine(int* octbuffer, char* collbuffer, int level, GLfloat rad, Vector v0, Vector v1, Vector off, int face_hit)
{
	// displace the line by the offset
	Vector u0 = make_vector( v0.x + off.x, v0.y + off.y, v0.z + off.z);
	Vector u1 = make_vector( v1.x + off.x, v1.y + off.y, v1.z + off.z);
	
	if (debug_octree)
	{
		NSLog(@"DEBUG octant: [%d] radius: %.2f vs. line: ( %.2f, %.2f, %.2f) - ( %.2f, %.2f, %.2f)", 
		level, rad, u0.x, u0.y, u0.z, u1.x, u1.y, u1.z);
	}

	if (octbuffer[level] == 0)
	{
		if (debug_octree)
			NSLog(@"DEBUG Hit an empty octant: [%d]", level);
		return NO;
	}
	
	if (octbuffer[level] == -1)
	{
		if (debug_octree)
			NSLog(@"DEBUG Hit a solid octant: [%d]", level);
		collbuffer[level] = 2;	// green
		hit_dist = sqrt( u0.x * u0.x + u0.y * u0.y + u0.z * u0.z);
		return YES;
	}
	
	int faces = face_hit;
	if (faces == 0)
		faces = lineCubeIntersection( u0, u1, rad);

	if (faces == 0)
	{
		if (debug_octree)
			NSLog(@"----> Line misses octant: [%d].", level);
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

		if (debug_octree)
			NSLog(@"----> found intersection with face 0x%2x of cube of radius %.2f at ( %.2f, %.2f, %.2f) octant:%d",
				faces, rad, vi.x, vi.y, vi.z, octantIntersected);
	}
	else
	{	
		if (debug_octree)
			NSLog(@"----> inside cube of radius %.2f octant:%d", rad, octantIntersected);
		faces = 0;	// inside the cube!
	}
	
	hasCollided = YES;
	
	collbuffer[level] = 1;	// red
	
	if (debug_octree)
		NSLog(@"----> testing octants...");
	
	int nextlevel = octbuffer[level];
		
	GLfloat rd2 = 0.5 * rad;
	
	// first test the intersected octant, then the three adjacent, then the next three adjacent, the finally the diagonal octant
	int oct0, oct1, oct2, oct3;	// test oct0 then oct1, oct2, oct3 then (7 - oct1), (7 - oct2), (7 - oct3) then (7 - oct0)
	oct0 = octantIntersected;
	oct1 = oct0 ^ 0x01;	// adjacent x
	oct2 = oct0 ^ 0x02;	// adjacent y
	oct3 = oct0 ^ 0x04;	// adjacent z

	Vector moveLine = off;

	if (debug_octree)
		NSLog(@"----> testing first octant hit [+%d]", oct0);
	if (octbuffer[nextlevel + oct0])
	{
		moveLine = make_vector(rd2 - ((oct0 >> 2) & 1) * rad, rd2 - ((oct0 >> 1) & 1) * rad, rd2 - (oct0 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct0, rd2, u0, u1, moveLine, faces)) return YES;	// first octant
	}
		
	// test the three adjacent octants

	if (debug_octree)
		NSLog(@"----> testing next three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	
	if (octbuffer[nextlevel + oct1])
	{
		moveLine = make_vector(rd2 - ((oct1 >> 2) & 1) * rad, rd2 - ((oct1 >> 1) & 1) * rad, rd2 - (oct2 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct1, rd2, u0, u1, moveLine, 0)) return YES;	// second octant
	}
	if (octbuffer[nextlevel + oct2])
	{
		moveLine = make_vector(rd2 - ((oct2 >> 2) & 1) * rad, rd2 - ((oct2 >> 1) & 1) * rad, rd2 - (oct2 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct2, rd2, u0, u1, moveLine, 0)) return YES;	// third octant
	}
	if (octbuffer[nextlevel + oct3])
	{
		moveLine = make_vector(rd2 - ((oct3 >> 2) & 1) * rad, rd2 - ((oct3 >> 1) & 1) * rad, rd2 - (oct3 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct3, rd2, u0, u1, moveLine, 0)) return YES;	// fourth octant
	}
	
	// go to the next four octants
	
	oct0 ^= 0x07;	oct1 ^= 0x07;	oct2 ^= 0x07;	oct3 ^= 0x07;
	
	if (debug_octree)
		NSLog(@"----> testing back three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	
	if (octbuffer[nextlevel + oct1])
	{
		moveLine = make_vector(rd2 - ((oct1 >> 2) & 1) * rad, rd2 - ((oct1 >> 1) & 1) * rad, rd2 - (oct1 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct1, rd2, u0, u1, moveLine, 0)) return YES;	// fifth octant
	}
	if (octbuffer[nextlevel + oct2])
	{
		moveLine = make_vector(rd2 - ((oct2 >> 2) & 1) * rad, rd2 - ((oct2 >> 1) & 1) * rad, rd2 - (oct2 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct2, rd2, u0, u1, moveLine, 0)) return YES;	// sixth octant
	}
	if (octbuffer[nextlevel + oct3])
	{
		moveLine = make_vector(rd2 - ((oct3 >> 2) & 1) * rad, rd2 - ((oct3 >> 1) & 1) * rad, rd2 - (oct3 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct3, rd2, u0, u1, moveLine, 0)) return YES;	// seventh octant
	}
	
	// and check the last octant
	if (debug_octree)
		NSLog(@"----> testing final octant [+%d]", oct0);
	
	if (octbuffer[nextlevel + oct0])
	{
		moveLine = make_vector(rd2 - ((oct0 >> 2) & 1) * rad, rd2 - ((oct0 >> 1) & 1) * rad, rd2 - (oct0 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct0, rd2, u0, u1, moveLine, 0)) return YES;	// last octant
	}
	
	return NO;
}

- (GLfloat) isHitByLine: (Vector) v0: (Vector) v1
{
	int i;
	for (i = 0; i< leafs; i++) octree_collision[i] = (char)0;
	hasCollided = NO;
	//
	if (isHitByLine(octree, octree_collision, 0, radius, v0, v1, make_vector( 0.0f, 0.0f, 0.0f), 0))
	{
		if (debug_octree)
			NSLog(@"DEBUG Hit at distance %.2f\n\n", hit_dist);
		hasCollision = hasCollided;
		return hit_dist;
	}
	else
	{
		if (debug_octree)
			NSLog(@"DEBUG Missed!\n\n", hit_dist);
		hasCollision = hasCollided;
		return 0.0;
	}
}

BOOL	isHitBySphere(int* octbuffer, char* collbuffer, int level, GLfloat rad, Vector v0, GLfloat sphere_rad, Vector off)
{
	// displace the sphere by the offset
	Vector u0 = make_vector( v0.x + off.x, v0.y + off.y, v0.z + off.z);
	
	if (debug_octree)
	{
		NSLog(@"DEBUG octant: [%d] radius: %.2f vs. Sphere: ( %.2f, %.2f, %.2f) r %.2f", 
		level, rad, u0.x, u0.y, u0.z, sphere_rad);
	}

	if (octbuffer[level] == 0)
	{
		if (debug_octree)
			NSLog(@"DEBUG Hit an empty octant: [%d]", level);
		return NO;
	}
	
	if ((u0.x + sphere_rad < -rad)||(u0.x - sphere_rad > rad)||
		(u0.y + sphere_rad < -rad)||(u0.y - sphere_rad > rad)||
		(u0.z + sphere_rad < -rad)||(u0.z - sphere_rad > rad))
	{
		if (debug_octree)
			NSLog(@"----> Sphere misses octant: [%d].", level);
		return NO;
	}
	
	if (octbuffer[level] == -1)
	{
		if (debug_octree)
			NSLog(@"DEBUG Hit a solid octant: [%d]", level);
		collbuffer[level] = 2;	// green
		hit_dist = sqrt( u0.x * u0.x + u0.y * u0.y + u0.z * u0.z);
		return YES;
	}
	
	Vector	v = unit_vector(&u0);	// vector from origin towards sphere
	Vector	u1 = make_vector( u0.x - v.x * sphere_rad, u0.y - v.y * sphere_rad, u0.z - v.z * sphere_rad); // nearest part of sphere to origin
	int		faces = lineCubeIntersection( u0, u1, rad);

	if (faces == 0)
	{
		if (debug_octree)
			NSLog(@"----> Sphere misses octant: [%d].", level);
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

		if (debug_octree)
			NSLog(@"----> found intersection with face 0x%2x of cube of radius %.2f at ( %.2f, %.2f, %.2f) octant:%d",
				faces, rad, vi.x, vi.y, vi.z, octantIntersected);
	}
	else
	{	
		if (debug_octree)
			NSLog(@"----> inside cube of radius %.2f octant:%d", rad, octantIntersected);
		faces = 0;	// inside the cube!
	}
	
	hasCollided = YES;
	
	collbuffer[level] = 1;	// red
	
	if (debug_octree)
		NSLog(@"----> testing octants...");
	
	int nextlevel = octbuffer[level];
		
	GLfloat rd2 = 0.5 * rad;
	
	// first test the intersected octant, then the three adjacent, then the next three adjacent, the finally the diagonal octant
	int oct0, oct1, oct2, oct3;	// test oct0 then oct1, oct2, oct3 then (7 - oct1), (7 - oct2), (7 - oct3) then (7 - oct0)
	oct0 = octantIntersected;
	oct1 = oct0 ^ 0x01;	// adjacent x
	oct2 = oct0 ^ 0x02;	// adjacent y
	oct3 = oct0 ^ 0x04;	// adjacent z

	Vector moveLine = off;

	if (debug_octree)
		NSLog(@"----> testing first octant hit [+%d]", oct0);
	if (octbuffer[nextlevel + oct0])
	{
		moveLine = make_vector(rd2 - ((oct0 >> 2) & 1) * rad, rd2 - ((oct0 >> 1) & 1) * rad, rd2 - (oct0 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct0, rd2, u0, u1, moveLine, faces)) return YES;	// first octant
	}
		
	// test the three adjacent octants

	if (debug_octree)
		NSLog(@"----> testing next three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	
	if (octbuffer[nextlevel + oct1])
	{
		moveLine = make_vector(rd2 - ((oct1 >> 2) & 1) * rad, rd2 - ((oct1 >> 1) & 1) * rad, rd2 - (oct2 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct1, rd2, u0, u1, moveLine, 0)) return YES;	// second octant
	}
	if (octbuffer[nextlevel + oct2])
	{
		moveLine = make_vector(rd2 - ((oct2 >> 2) & 1) * rad, rd2 - ((oct2 >> 1) & 1) * rad, rd2 - (oct2 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct2, rd2, u0, u1, moveLine, 0)) return YES;	// third octant
	}
	if (octbuffer[nextlevel + oct3])
	{
		moveLine = make_vector(rd2 - ((oct3 >> 2) & 1) * rad, rd2 - ((oct3 >> 1) & 1) * rad, rd2 - (oct3 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct3, rd2, u0, u1, moveLine, 0)) return YES;	// fourth octant
	}
	
	// go to the next four octants
	
	oct0 ^= 0x07;	oct1 ^= 0x07;	oct2 ^= 0x07;	oct3 ^= 0x07;
	
	if (debug_octree)
		NSLog(@"----> testing back three octants [+%d] [+%d] [+%d]", oct1, oct2, oct3);
	
	if (octbuffer[nextlevel + oct1])
	{
		moveLine = make_vector(rd2 - ((oct1 >> 2) & 1) * rad, rd2 - ((oct1 >> 1) & 1) * rad, rd2 - (oct1 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct1, rd2, u0, u1, moveLine, 0)) return YES;	// fifth octant
	}
	if (octbuffer[nextlevel + oct2])
	{
		moveLine = make_vector(rd2 - ((oct2 >> 2) & 1) * rad, rd2 - ((oct2 >> 1) & 1) * rad, rd2 - (oct2 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct2, rd2, u0, u1, moveLine, 0)) return YES;	// sixth octant
	}
	if (octbuffer[nextlevel + oct3])
	{
		moveLine = make_vector(rd2 - ((oct3 >> 2) & 1) * rad, rd2 - ((oct3 >> 1) & 1) * rad, rd2 - (oct3 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct3, rd2, u0, u1, moveLine, 0)) return YES;	// seventh octant
	}
	
	// and check the last octant
	if (debug_octree)
		NSLog(@"----> testing final octant [+%d]", oct0);
	
	if (octbuffer[nextlevel + oct0])
	{
		moveLine = make_vector(rd2 - ((oct0 >> 2) & 1) * rad, rd2 - ((oct0 >> 1) & 1) * rad, rd2 - (oct0 & 1) * rad);
		if (isHitByLine(octbuffer, collbuffer, nextlevel + oct0, rd2, u0, u1, moveLine, 0)) return YES;	// last octant
	}
	
	return NO;
}

- (BOOL) isHitBySphereOrigin: (Vector) v0: (GLfloat) sphere_radius
{
	return isHitBySphere(octree, octree_collision, 0, radius, v0, sphere_radius, make_vector( 0.0f, 0.0f, 0.0f));
}

BOOL	isHitByOctree(	int* octbuffer, char* collbuffer, int level, GLfloat rad,
						int* other_octree, int other_level, Vector v0, GLfloat other_rad, Triangle other_ijk, Vector off)
{
	if (debug_octree)
	{
		NSLog(@"DEBUG TESTING octant index: [%d] offset by ( %.2f, %.2f, %.2f)", 
			level, off.x, off.y, off.z);
	}
	
	// displace the cube by the offset
	Vector u0 = make_vector( v0.x + off.x, v0.y + off.y, v0.z + off.z);

	if (debug_octree)
	{
		NSLog(@"DEBUG octant index: [%d] radius: %.2f vs. Octree at: ( %.2f, %.2f, %.2f) r %.2f", 
			level, rad, u0.x, u0.y, u0.z, other_rad);
	}

	if (octbuffer[level] == 0)
	{
		if (debug_octree)
			NSLog(@"DEBUG Octant index: [%d] is empty.", level);
		return NO;
	}
	
	if (!other_octree)
	{
		if (debug_octree)
			NSLog(@"DEBUG other_octree is null");
		return NO;
	}
	
	if (other_octree[other_level] == 0)
	{
		if (debug_octree)
			NSLog(@"DEBUG Other octree from index: [%d] is empty.", other_level);
		return NO;
	}
	
	if (other_rad < rad) // test THIS cube against THAT sphere
	{
		// 'crude and simple' - test sphere against cube...
		if ((u0.x + other_rad < -rad)||(u0.x - other_rad > rad)||
			(u0.y + other_rad < -rad)||(u0.y - other_rad > rad)||
			(u0.z + other_rad < -rad)||(u0.z - other_rad > rad))
		{
			if (debug_octree)
				NSLog(@"----> Octant: [%d]. does not intersect inner sphere of the octree", level);
			return NO;
		}
	}
	else	// test THIS sphere against THAT cube
	{
		GLfloat di = dot_product( other_ijk.v[0], u0);
		GLfloat dj = dot_product( other_ijk.v[1], u0);
		GLfloat dk = dot_product( other_ijk.v[2], u0);
		if ((di + rad < -other_rad)||(di - rad > other_rad)||
			(dj + rad < -other_rad)||(dj - rad > other_rad)||
			(dk + rad < -other_rad)||(dk - rad > other_rad))
		{
			if (debug_octree)
				NSLog(@"----> Octant: [%d]'s inner sphere does not intersect the octree", level);
			return NO;
		}
	}
	
	// from here on, this Octree and the other Octree are considered to be intersecting
	if (octbuffer[level] == -1)
	{
		// we are SOLID - is the other octree?
		if (other_octree[other_level] == -1)
		{
			collbuffer[level] = 1;	// red
			//
			if (debug_octree)
				NSLog(@"DEBUG Octrees collide!");
			return YES;
		}
		// the other octree must be decomposed
		// and each of its octants tested against us
		// (this is the hard bit that uses the ijk vectors to offset u0)
		// if any of them collides with this octant (use level and rad unchanged)
		// then we have a solid collision
		//
		if (debug_octree)
			NSLog(@"----> testing other octants...");
		//
		int		other_nextlevel = other_octree[other_level];
		GLfloat	other_rd2 = 0.5 * other_rad;
		Vector	voff, octantPosition;
		Vector	i = other_ijk.v[0];
		Vector	j = other_ijk.v[1];
		Vector	k = other_ijk.v[2];
		int		oct;
		for (oct = 0; oct < 7; oct++)
		{
			if (other_octree[other_nextlevel + oct])	// don't test empty octants
			{
				voff = make_vector(other_rd2 - ((oct >> 2) & 1) * other_rad, other_rd2 - ((oct >> 1) & 1) * other_rad, other_rd2 - (oct & 1) * other_rad);
				octantPosition.x = u0.x - i.x * voff.x - j.x * voff.y - k.x * voff.z;
				octantPosition.y = u0.y - i.y * voff.x - j.y * voff.y - k.y * voff.z;
				octantPosition.z = u0.z - i.z * voff.x - j.z * voff.y - k.z * voff.z;	// voff is negated here because we're moving the origin, not the cube
				if (isHitByOctree(	octbuffer, collbuffer, level, rad,
									other_octree, other_nextlevel + oct, octantPosition, other_rd2, other_ijk, make_vector( 0.0f, 0.0f, 0.0f))) return YES;	// test octant
			}
		}
		//
		// otherwise
		return NO;
	}
	// we are not solid
	// we must test each of our octants against
	// the other octree, if any of them collide
	// we have a solid collision
	//
	if (debug_octree)
		NSLog(@"----> testing octants...");
	//
	int		nextlevel = octbuffer[level];
	GLfloat	rd2 = 0.5 * rad;
	Vector	octantOffset;
	int		oct;
	for (oct = 0; oct < 7; oct++)
	{
		if (octbuffer[nextlevel + oct])	// don't test empty octants
		{
			octantOffset = make_vector(rd2 - ((oct >> 2) & 1) * rad, rd2 - ((oct >> 1) & 1) * rad, rd2 - (oct & 1) * rad);
			// in the previous tests we put octantOffset into the ijk vectors, here we can use it unchanged
			if (isHitByOctree(	octbuffer, collbuffer, nextlevel + oct, rd2,
								other_octree, other_level, u0, other_rad, other_ijk, octantOffset)) return YES;	// test octant
		}
	}
	// otherwise
	return NO;
	// and we're done!
}

- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk
{
	return hasCollision = isHitByOctree( octree, octree_collision, 0, radius,
								[other octree], 0, v0, [other radius], ijk, make_vector( 0.0f, 0.0f, 0.0f));
}



- (NSDictionary*)	dict;
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithFloat:radius],	@"radius",
		[NSNumber numberWithInt:leafs],		@"leafs",
		[NSData dataWithBytes:(const void *)octree length: leafs * sizeof(int)], @"octree",
		nil];
}

@end
