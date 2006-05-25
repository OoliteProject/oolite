/*

	Oolite

	Octree.h
	
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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "vector.h"

#define	OCTREE_MAX_DEPTH	5
#define	OCTREE_MIN_RADIUS	1.0
// 5 or 6 will be the final working resolution

extern int debug;

@interface Octree : NSObject
{
	GLfloat		radius;
	int			leafs;
	int*		octree;
	BOOL		hasCollision;
	
	unsigned char*		octree_collision;
}

- (GLfloat)	radius;
- (int)		leafs;
- (int*)	octree;
- (unsigned char*)	octree_collision;
- (BOOL)	hasCollision;

- (id) initWithRepresentationOfOctree:(GLfloat) octRadius :(NSObject*) octreeArray :(int) leafsize;
- (id) initWithDictionary:(NSDictionary*) dict;

int copyRepresentationIntoOctree(NSObject* theRep, int* theBuffer, int atLocation, int nextFreeLocation);

- (void) drawOctree;
- (void) drawOctreeFromLocation:(int) loc :(GLfloat) scale :(Vector) offset;

- (void) drawOctreeCollisions;
- (void) drawOctreeCollisionFromLocation:(int) loc :(GLfloat) scale :(Vector) offset;

BOOL	isHitByLine(int* octbuffer, unsigned char* collbuffer, int level, GLfloat rad, Vector v0, Vector v1, Vector off, int face_hit);
- (GLfloat) isHitByLine: (Vector) v0: (Vector) v1;

BOOL	isHitBySphere(int* octbuffer, unsigned char* collbuffer, int level, GLfloat rad, Vector v0, GLfloat sphere_rad, Vector off);
- (BOOL) isHitBySphereOrigin: (Vector) v0: (GLfloat) sphere_radius;

BOOL	isHitByOctree(	int* octbuffer, unsigned char* collbuffer, int level, GLfloat rad,
						Octree* other, int* other_octree, int other_level, Vector v0, GLfloat other_rad, Triangle other_ijk, Vector off);
- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk;

- (NSDictionary*) dict;

@end
