/*

Octree.h

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


@interface Octree: NSObject
{
@private
	GLfloat				_radius;
	uint32_t			_nodeCount;
	const int			*_octree;
	BOOL				_hasCollision;
	
	unsigned char		*_collisionOctree;
	
	NSData				*_data;
}

/*
	- (id) initWithDictionary:
	
	Deserialize an octree from cache representation.
	(To make a new octree, build it with OOOctreeBuilder.)
*/
- (id) initWithDictionary:(NSDictionary *)dictionary;

- (GLfloat) radius;

- (Octree *) octreeScaledBy:(GLfloat)factor;

#ifndef OODEBUGLDRAWING_DISABLE
- (void) drawOctree;
- (void) drawOctreeCollisions;
#endif

- (GLfloat) isHitByLine:(Vector)v0 :(Vector)v1;

- (BOOL) isHitByOctree:(Octree *)other withOrigin:(Vector)origin andIJK:(Triangle)ijk;
- (BOOL) isHitByOctree:(Octree *)other withOrigin:(Vector)origin andIJK:(Triangle)ijk andScales:(GLfloat)s1 :(GLfloat)s2;

- (NSDictionary *) dictionaryRepresentation;

- (GLfloat) volume;

- (Vector) randomPoint;


#ifndef NDEBUG
- (size_t) totalSize;
#endif

@end


enum
{
	kMaxOctreeDepth = 7	// 128x128x128
};


@interface OOOctreeBuilder: NSObject
{
@private
	int					*_octree;
	uint_fast32_t		_nodeCount, _capacity;
	struct OOOctreeBuildState
	{
		uint32_t			insertionPoint;
		uint32_t			remaining;
	}					_stateStack[kMaxOctreeDepth + 1];
	uint_fast8_t		_level;
}

/*
	-buildOctree
	
	Generate an octree with the current data in the builder, and clear the
	builder. If NDEBUG is undefined, throws an exception if the structure of
	the octree is invalid.
*/
- (Octree *) buildOctreeWithRadius:(GLfloat)radius;

/*
	Append nodes to the octree.
	
	There are three types of nodes: solid, empty, and inner nodes.
	An inner node must have exactly eight children, which may be any type of
	node. Exactly one node must be added at root level.
	
	The order of child nodes is defined as follows: the index of a child node
	is a three bit number. The highest bit represents x, the middle bit
	represents y and the low bit represents z. A set bit indicates the high-
	coordinate half of the parent node, and a clear bit indicates the low-
	coordinate half.
	
	For instance, if the parent node is a cube ranging from -1 to 1 on each
	axis, the child 101 (5) represents x 0..1, y -1..0, z 0..1.
*/
- (void) writeSolid;
- (void) writeEmpty;
- (void) beginInnerNode;
- (void) endInnerNode;

@end
