/*

Octtree.h

Octtree class for collision detection.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "OOMaths.h"

#define	OCTREE_MIN_RADIUS	1.0


#if !defined(OODEBUGLDRAWING_DISABLE) && defined(NDEBUG)
#define OODEBUGLDRAWING_DISABLE 1
#endif


typedef struct
{
	GLfloat				radius;
	int					*octree;	
	unsigned char		*octree_collision;
} Octree_details;


@interface Octree: NSObject
{
@private
	GLfloat			radius;
	int				leafs;
	int				*octree;
	BOOL			hasCollision;
	
	unsigned char	*octree_collision;
}

- (id) initWithRadius:(GLfloat)radius leafCount:(unsigned)leafCount objectRepresentation:(id)objectRepresentation;
- (id) initWithDictionary:(NSDictionary*) dict;

- (GLfloat) radius;
- (int) leafs;
- (int *) octree;
- (BOOL) hasCollision;
- (void) setHasCollision:(BOOL) value;
- (unsigned char *) octree_collision;

- (Octree_details) octreeDetails;

- (Octree *) octreeScaledBy:(GLfloat)factor;

Vector offsetForOctant(int oct, GLfloat r);

#ifndef OODEBUGLDRAWING_DISABLE
- (void) drawOctree;
- (void) drawOctreeCollisions;
#endif

- (GLfloat) isHitByLine: (Vector) v0: (Vector) v1;

- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk;
- (BOOL) isHitByOctree:(Octree*) other withOrigin: (Vector) v0 andIJK: (Triangle) ijk andScales: (GLfloat) s1: (GLfloat) s2;

- (NSDictionary *) dictionaryRepresentation;

- (GLfloat) volume;

- (Vector) randomPoint;


#ifndef NDEBUG
- (size_t) totalSize;
#endif

@end
