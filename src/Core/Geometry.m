/*

Geometry.m

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


/*
	PERFORMANCE NOTES
	
	This class has historically been noted for its significant presence in
	startup profiles, and is believed to be a major source of in-game stutter,
	so its performance characteristics are important.
	
	
	The following observations were made in r5352, starting up with no OXPs
	(except Debug.oxp) and no cache, and running through the complete set of
	demo ships.
	
	* In total, 379,344 geometries were allocated.
	* No more than 53 were allocated at a time.
	* 37.3% of them (141,585) never had a triangle added.
	* 51.2% had 4 or fewer triangles. 72.3% had 8 or fewer triangles. 93.3%
      had 16 or fewer triangles.
	* Triangle storage was reallocated 98,809 times.
	* More time was spent in ObjC memory management than C memory management.
	* In total, -addTriangle: was called 2,171,785 times.
	* Degenerate triangles come from input geometry, but don't seem to be
	  generated in inner nodes.
	
	Conclusions:
	* addTriangle: should be a static C function. The degenerate check is only
	  needed for input unless evidence to the contrary emerges.
	* Triangle storage should be lazily allocated.
	* Wasted space in triangle storage is unimportant with only 53 Geometries
	  live at a time, so the splitting code should use a pessimistic heuristic
	  for selecting the capacity of sub-geometries.
	* A pool allocator for Geometries should be helpful.
	* It may be worth putting space for some number of triangles in the
	  Geometry itself (conceptually similar to the standard short string
	  optimization).
	
	All but the last of these is implemented in r5353.
*/


#import "Geometry.h"

#import "OOMaths.h"
#import "Octree.h"
#import "OOLogging.h"


#define USE_ALLOC_POOL			1


#if USE_ALLOC_POOL

#if OOLITE_GNUSTEP
#import <GNUstepBase/GSObjCRuntime.h>


static id objc_constructInstance(Class cls, void *bytes)
{
	id result = bytes;
	result->class_pointer = cls;
	return result;
}


static void *objc_destructInstance(id obj)
{
	return obj;
}

#else
#import <objc/objc-runtime.h>
#endif


typedef struct FreeBlock
{
	struct FreeBlock		*next;
} FreeBlock;

static NSUInteger		sLiveInstancesCount;
static NSMutableSet		*sAllocationChunks;
static size_t			sAllocationSize;
static size_t			sBlocksPerChunk;
static FreeBlock		*sNextFreeBlock;

enum
{
	kTargetPageSize				= 4096
};

#endif


@interface Geometry (OOPrivate)

- (id) octreeWithinRadius:(GLfloat)octreeRadius toDepth:(int)depth;

- (BOOL) isConvex;
- (void) setConvex:(BOOL)value;

- (void) translateX:(OOScalar)offset;
- (void) translateY:(OOScalar)offset;
- (void) translateZ:(OOScalar)offset;

- (void) x_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) x;
- (void) y_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) y;
- (void) z_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) z;

- (BOOL) testIsConvex;
- (BOOL) testCornersWithinGeometry:(GLfloat) corner;
- (GLfloat) findMaxDimensionFromOrigin;

@end


OOINLINE void AddTriangle(Geometry *self, Triangle tri);
static GCC_ATTR((noinline)) void GrowTriangles(Geometry *self);


OOINLINE BOOL OOTriangleIsDegenerate(Triangle tri)
{
	return vector_equal(tri.v[0], tri.v[1]) ||
	vector_equal(tri.v[1], tri.v[2]) ||
	vector_equal(tri.v[2], tri.v[0]);
}


@implementation Geometry

- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%lu triangles, %@", n_triangles, [self testIsConvex] ? @"convex" : @"not convex"];
}


#if USE_ALLOC_POOL
+ (id) alloc
{
	if (sNextFreeBlock == NULL)
	{
		if (sAllocationSize == 0)
		{
			sAllocationSize = class_getInstanceSize(self);
			// Round up to multiple of 16 to meet ObjC runtime alignment requirements.
			sAllocationSize = (sAllocationSize + 0xF) & ~0xF;
			
			sBlocksPerChunk = kTargetPageSize / sAllocationSize;	// At time of writing, 85 on a 64-bit Mac.
		}
		
		/*
			Use a set of mutableDatas to hold on to our allocation blocks, so
			we can easily free them all when allocation count drops to zero.
		*/
		NSMutableData *chunk = [NSMutableData dataWithLength:sAllocationSize * sBlocksPerChunk];
		if (sAllocationChunks == nil)
		{
			sAllocationChunks = [[NSMutableSet alloc] init];
		}
		[sAllocationChunks addObject:chunk];
		
		if (EXPECT_NOT(chunk == nil || sAllocationChunks == nil))
		{
			[NSException raise:NSMallocException format:@"Could not allocate memory for Geometry pool allocator."];
		}
		
		// Divide bytes up into FreeBlocks.
		char *bytes = [chunk mutableBytes];
		for (NSUInteger i = 0; i < sBlocksPerChunk; i++)
		{
			FreeBlock *block = (FreeBlock *)(bytes + i * sAllocationSize);
			block->next = sNextFreeBlock;
			sNextFreeBlock = block;
		}
	}
	
	NSAssert(sNextFreeBlock != NULL, @"Geometry pool allocator failed to grow pool and didn't throw as expected.");
	
	// Grab the first FreeBlock...
	FreeBlock *block = sNextFreeBlock;
	sNextFreeBlock = block->next;
	
	// ...clear it (formally required)...
	memset(block, 0, sAllocationSize);
	
	// ...and turn it into an instance.
	sLiveInstancesCount++;
	return objc_constructInstance(self, block);
}
#endif


- (id) initWithCapacity:(NSUInteger)amount
{
	if (amount < 1)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		/*
			Storage is allocated lazily, since almost 40% of geometries never
			have any triangles added to them.
		*/
		max_triangles = amount;
		n_triangles = 0;
		isConvex = NO;
	}
	
	return self;
}


- (void) dealloc
{
	if (triangles != NULL)
	{
		/*	Free up triangle storage. Because this is called so many times and
			triangles is so often NULL, avoiding the call in those cases is
			worthwhile.
		*/
		free(triangles);
	}
	
#if USE_ALLOC_POOL
	// Do the runtimey bits of deallocing...
	FreeBlock *block = (FreeBlock *)objc_destructInstance(self);
	self = nil;
	
	// ..and return memory to pool.
	block->next = sNextFreeBlock;
	sNextFreeBlock = block;
	
	// Destroy entire pool if there are no live Geometries.
	if (--sLiveInstancesCount == 0)
	{
		DESTROY(sAllocationChunks);
		sNextFreeBlock = NULL;
	}
	
	return;
#endif
	
	[super dealloc];
}


- (BOOL) isConvex
{
	return isConvex;
}


- (void) setConvex:(BOOL) value
{
	isConvex = value;
}


OOINLINE void AddTriangle(Geometry *self, Triangle tri)
{
	if (self->triangles == NULL || self->n_triangles == self->max_triangles)
	{
		GrowTriangles(self);
	}
	
	self->triangles[self->n_triangles++] = tri;
}


- (void) addTriangle:(Triangle)tri
{
	if (!OOTriangleIsDegenerate(tri))
	{
		AddTriangle(self, tri);
	}
}


- (BOOL) testIsConvex
{
	/*	Enumerate over triangles
		calculate normal for each one,
		then enumerate over vertices relative to a vertex on the triangle
		and check if they are on the forwardside or coplanar with the triangle.
		If a vertex is on the backside of any triangle then return NO.
	*/
	NSInteger	i, j;
	for (i = 0; i < n_triangles; i++)
	{
		Vector v0 = triangles[i].v[0];
		Vector vn = calculateNormalForTriangle(&triangles[i]);
		//
		for (j = 0; j < n_triangles; j++)
		{
			if (j != i)
			{
				if ((dot_product(vector_between(v0, triangles[j].v[0]), vn) < -0.001)||
					(dot_product(vector_between(v0, triangles[j].v[1]), vn) < -0.001)||
					(dot_product(vector_between(v0, triangles[j].v[2]), vn) < -0.001))	// within 1mm tolerance
				{
					isConvex = NO;
					return NO;
				}
			}
		}
	}
	isConvex = YES;
	return YES;
}


- (BOOL) testCornersWithinGeometry:(GLfloat)corner
{
	/*	enumerate over triangles
		calculate normal for each one,
		then enumerate over corners relative to a vertex on the triangle
		and check if they are on the forwardside or coplanar with the triangle.
		If a corner is on the backside of any triangle then return NO.
	*/
	NSInteger	i, x, y, z;
	for (i = 0; i < n_triangles; i++)
	{
		Vector v0 = triangles[i].v[0];
		Vector vn = calculateNormalForTriangle(&triangles[i]);
		//
		for (z = -1; z < 2; z += 2) for (y = -1; y < 2; y += 2) for (x = -1; x < 2; x += 2)
		{
			Vector vc = make_vector(corner * x, corner * y, corner * z);
			if (dot_product(vector_between(v0, vc), vn) < -0.001)
			{
				return NO;
			}
		}
	}
	return YES;
}


- (GLfloat) findMaxDimensionFromOrigin
{
	// enumerate over triangles
	GLfloat result = 0.0f;
	NSInteger	i, j;
	for (i = 0; i < n_triangles; i++) for (j = 0; j < 3; j++)
	{
		Vector v = triangles[i].v[j];
		result = fmax(result, v.x);
		result = fmax(result, v.y);
		result = fmax(result, v.z);
	}
	return result;
}


static int leafcount;
static float volumecount;

- (Octree *) findOctreeToDepth:(int)depth
{
	leafcount = 0;
	volumecount = 0.0f;
	
	GLfloat foundRadius = 0.5f + [self findMaxDimensionFromOrigin];	// pad out from geometry by a half meter
	
	NSObject *foundOctree = [self octreeWithinRadius:foundRadius toDepth:depth];
	
	Octree*	octreeRepresentation = [[Octree alloc] initWithRadius:foundRadius leafCount:leafcount objectRepresentation:foundOctree];
	
	return [octreeRepresentation autorelease];
}


- (id) octreeWithinRadius:(GLfloat)octreeRadius toDepth:(int)depth
{
	GLfloat offset = 0.5f * octreeRadius;
	
	if (n_triangles == 0)
	{
		leafcount++;	// nil or zero or 0
		return [NSNumber numberWithBool:NO];	// empty octree
	}
	
	// there is geometry!
	if ((octreeRadius <= OCTREE_MIN_RADIUS)||(depth <= 0))	// maximum resolution
	{
		leafcount++;	// partially full or -1
		volumecount += octreeRadius * octreeRadius * octreeRadius * 0.5f;
		return [NSNumber numberWithBool:YES];	// at least partially full octree
	}
	
	if (!isConvex)
	{
		[self testIsConvex]; // check!
	}
	if (isConvex)	// we're convex!
	{
		if ([self testCornersWithinGeometry: octreeRadius])	// all eight corners inside or on!
		{
			leafcount++;	// full or -1
			volumecount += octreeRadius * octreeRadius * octreeRadius;
			return [NSNumber numberWithBool:YES];	// full octree
		}
	}
	
	/*
		As per performance notes, we want to use a heuristic which keeps the
		number of reallocations needed low with relatively little regard to
		allocation size.
		
		This table shows observed performance for several heuristics using
		vanilla Oolite r5352 (plus instrumentation). Values aren't precisely
		reproducible, but are reasonably stable.
		
		Heuristic: expression used to initialize subCapacity.
		
		PER: number of geometries per reallocation; in other words, a realloc
		     is needed one time per PER geometries.
		
		MEM: high water mark for total memory consumption (triangles arrays
		     only) across all live Geometries.
		
		Heuristic                   PER         MEM
		n_triangles                 3-4         71856
		n_triangles * 2             100         111384
		MAX(n_triangles * 2, 16)    300         111384
		MAX(n_triangles * 2, 21)    500         148512
		n_triangles * 3             500         165744
		MAX(n_triangles * 3, 16)    12000       165744
		MAX(n_triangles * 3, 21)    20000       165744
		
		The value 21 was chosen for reasons which, on reflection, were entirely
		wrong. Performance profiling shows no discernible difference between
		2,16 and 3,21.
	*/
	enum
	{
		kFactor = 3,
		kMinimum = 16
	};
	NSUInteger subCapacity = n_triangles * kFactor;
	if (subCapacity < kMinimum)  subCapacity = kMinimum;
	
	Geometry* g_000 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_001 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_010 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_011 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_100 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_101 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_110 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_111 = [(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	
	Geometry* g_xx1 =	[(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	Geometry* g_xx0 =	[(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
	
	[self z_axisSplitBetween:g_xx1 :g_xx0 : offset];
	if (g_xx0->n_triangles != 0)
	{
		Geometry* g_x00 =	[(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
		Geometry* g_x10 =	[(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
		
		[g_xx0 y_axisSplitBetween: g_x10 : g_x00 : offset];
		if (g_x00->n_triangles != 0)
		{
			[g_x00 x_axisSplitBetween:g_100 :g_000 : offset];
			[g_000 setConvex: isConvex];
			[g_100 setConvex: isConvex];
		}
		if (g_x10->n_triangles != 0)
		{
			[g_x10 x_axisSplitBetween:g_110 :g_010 : offset];
			[g_010 setConvex: isConvex];
			[g_110 setConvex: isConvex];
		}
		[g_x00 release];
		[g_x10 release];
	}
	if (g_xx1->n_triangles != 0)
	{
		Geometry* g_x01 =	[(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
		Geometry* g_x11 =	[(Geometry *)[Geometry alloc] initWithCapacity:subCapacity];
		
		[g_xx1 y_axisSplitBetween: g_x11 : g_x01 :offset];
		if (g_x01->n_triangles != 0)
		{
			[g_x01 x_axisSplitBetween:g_101 :g_001 :offset];
			[g_001 setConvex: isConvex];
			[g_101 setConvex: isConvex];
		}
		if (g_x11->n_triangles != 0)
		{
			[g_x11 x_axisSplitBetween:g_111 :g_011 :offset];
			[g_011 setConvex: isConvex];
			[g_111 setConvex: isConvex];
		}
		[g_x01 release];
		[g_x11 release];
	}
	[g_xx0 release];
	[g_xx1 release];
	
	/*
		Setting up result array has significant cost. Could be optimized with
		a custom array class that short-circuits the retain/release dance.
		-- Ahruman 2012-09-22
	*/
	leafcount++;	// pointer to array
	NSObject* result = [NSArray arrayWithObjects:
		[g_000 octreeWithinRadius: offset toDepth:depth - 1],
		[g_001 octreeWithinRadius: offset toDepth:depth - 1],
		[g_010 octreeWithinRadius: offset toDepth:depth - 1],
		[g_011 octreeWithinRadius: offset toDepth:depth - 1],
		[g_100 octreeWithinRadius: offset toDepth:depth - 1],
		[g_101 octreeWithinRadius: offset toDepth:depth - 1],
		[g_110 octreeWithinRadius: offset toDepth:depth - 1],
		[g_111 octreeWithinRadius: offset toDepth:depth - 1],
		nil];
	[g_000 release];
	[g_001 release];
	[g_010 release];
	[g_011 release];
	[g_100 release];
	[g_101 release];
	[g_110 release];
	[g_111 release];
	
	return result;
}


- (void) translateX:(OOScalar)offset
{
	NSUInteger i, count = (NSUInteger)n_triangles;
	for (i = 0; i < count; i++)
	{
		triangles[i].v[0].x += offset;
		triangles[i].v[1].x += offset;
		triangles[i].v[2].x += offset;
	}
}


- (void) translateY:(OOScalar)offset
{
	NSUInteger i, count = (NSUInteger)n_triangles;
	for (i = 0; i < count; i++)
	{
		triangles[i].v[0].y += offset;
		triangles[i].v[1].y += offset;
		triangles[i].v[2].y += offset;
	}
}


- (void) translateZ:(OOScalar)offset
{
	NSUInteger i, count = (NSUInteger)n_triangles;
	for (i = 0; i < count; i++)
	{
		triangles[i].v[0].z += offset;
		triangles[i].v[1].z += offset;
		triangles[i].v[2].z += offset;
	}
}


- (void) x_axisSplitBetween:(Geometry *)g_plus :(Geometry *)g_minus :(GLfloat)x
{
	// test each triangle splitting against x == 0.0
	//
	NSInteger	i;
	for (i = 0; i < n_triangles; i++)
	{
		BOOL done_tri = NO;
		Vector v0 = triangles[i].v[0];
		Vector v1 = triangles[i].v[1];
		Vector v2 = triangles[i].v[2];
		
		if ((v0.x >= 0.0)&&(v1.x >= 0.0)&&(v2.x >= 0.0))
		{
			AddTriangle(g_plus, triangles[i]);
			done_tri = YES;
		}
		if ((v0.x <= 0.0)&&(v1.x <= 0.0)&&(v2.x <= 0.0))
		{
			AddTriangle(g_minus, triangles[i]);
			done_tri = YES;
		}
		if (!done_tri)	// triangle must cross x == 0.0
		{
			GLfloat i01, i12, i20;
			if (v0.x == v1.x)
				i01 = -1.0f;
			else
				i01 = v0.x / (v0.x - v1.x);
			if (v1.x == v2.x)
				i12 = -1.0f;
			else
				i12 = v1.x / (v1.x - v2.x);
			if (v2.x == v0.x)
				i20 = -1.0f;
			else
				i20 = v2.x / (v2.x - v0.x);
			Vector v01 = make_vector(0.0f, i01 * (v1.y - v0.y) + v0.y, i01 * (v1.z - v0.z) + v0.z);
			Vector v12 = make_vector(0.0f, i12 * (v2.y - v1.y) + v1.y, i12 * (v2.z - v1.z) + v1.z);
			Vector v20 = make_vector(0.0f, i20 * (v0.y - v2.y) + v2.y, i20 * (v0.z - v2.z) + v2.z);
		
			// cases where a vertex is on the split.
			if (v0.x == 0.0)
			{
				if (v1.x > 0)
				{
					AddTriangle(g_plus, make_triangle(v0, v1, v12));
					AddTriangle(g_minus, make_triangle(v0, v12, v2));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v0, v1, v12));
					AddTriangle(g_plus, make_triangle(v0, v12, v2));
				}
			}
			if (v1.x == 0.0)
			{
				if (v2.x > 0)
				{
					AddTriangle(g_plus, make_triangle(v1, v2, v20));
					AddTriangle(g_minus, make_triangle(v1, v20, v0));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v1, v2, v20));
					AddTriangle(g_plus, make_triangle(v1, v20, v0));
				}
			}
			if (v2.x == 0.0)
			{
				if (v0.x > 0)
				{
					AddTriangle(g_plus, make_triangle(v2, v0, v01));
					AddTriangle(g_minus, make_triangle(v2, v01, v1));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v2, v0, v01));
					AddTriangle(g_plus, make_triangle(v2, v01, v1));
				}
			}
			
			if ((v0.x > 0.0)&&(v1.x > 0.0)&&(v2.x < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v0, v12, v20));
				AddTriangle(g_plus, make_triangle(v0, v1, v12));
				AddTriangle(g_minus, make_triangle(v20, v12, v2));
			}
			
			if ((v0.x > 0.0)&&(v1.x < 0.0)&&(v2.x > 0.0))
			{
				AddTriangle(g_plus, make_triangle(v2, v01, v12));
				AddTriangle(g_plus, make_triangle(v2, v0, v01));
				AddTriangle(g_minus, make_triangle(v12, v01, v1));
			}
			
			if ((v0.x > 0.0)&&(v1.x < 0.0)&&(v2.x < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v20, v0, v01));
				AddTriangle(g_minus, make_triangle(v2, v20, v1));
				AddTriangle(g_minus, make_triangle(v20, v01, v1));
			}
			
			if ((v0.x < 0.0)&&(v1.x > 0.0)&&(v2.x > 0.0))
			{
				AddTriangle(g_minus, make_triangle(v01, v20, v0));
				AddTriangle(g_plus, make_triangle(v1, v20, v01));
				AddTriangle(g_plus, make_triangle(v1, v2, v20));
			}
			
			if ((v0.x < 0.0)&&(v1.x > 0.0)&&(v2.x < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v01, v1, v12));
				AddTriangle(g_minus, make_triangle(v0, v01, v2));
				AddTriangle(g_minus, make_triangle(v01, v12, v2));
			}
			
			if ((v0.x < 0.0)&&(v1.x < 0.0)&&(v2.x > 0.0))
			{
				AddTriangle(g_plus, make_triangle(v12, v2, v20));
				AddTriangle(g_minus, make_triangle(v1, v12, v0));
				AddTriangle(g_minus, make_triangle(v12, v20, v0));
			}			

		}
	}
	[g_plus translateX:-x];
	[g_minus translateX:x];
}


- (void) y_axisSplitBetween:(Geometry *)g_plus :(Geometry *)g_minus :(GLfloat)y
{
	// test each triangle splitting against y == 0.0
	//
	NSInteger	i;
	for (i = 0; i < n_triangles; i++)
	{
		BOOL done_tri = NO;
		Vector v0 = triangles[i].v[0];
		Vector v1 = triangles[i].v[1];
		Vector v2 = triangles[i].v[2];

		if ((v0.y >= 0.0)&&(v1.y >= 0.0)&&(v2.y >= 0.0))
		{
			AddTriangle(g_plus, triangles[i]);
			done_tri = YES;
		}
		if ((v0.y <= 0.0)&&(v1.y <= 0.0)&&(v2.y <= 0.0))
		{
			AddTriangle(g_minus, triangles[i]);
			done_tri = YES;
		}
		if (!done_tri)	// triangle must cross y == 0.0
		{
			GLfloat i01, i12, i20;
			if (v0.y == v1.y)
				i01 = -1.0f;
			else
				i01 = v0.y / (v0.y - v1.y);
			if (v1.y == v2.y)
				i12 = -1.0f;
			else
				i12 = v1.y / (v1.y - v2.y);
			if (v2.y == v0.y)
				i20 = -1.0f;
			else
				i20 = v2.y / (v2.y - v0.y);
			Vector v01 = make_vector(i01 * (v1.x - v0.x) + v0.x, 0.0f, i01 * (v1.z - v0.z) + v0.z);
			Vector v12 = make_vector(i12 * (v2.x - v1.x) + v1.x, 0.0f, i12 * (v2.z - v1.z) + v1.z);
			Vector v20 = make_vector(i20 * (v0.x - v2.x) + v2.x, 0.0f, i20 * (v0.z - v2.z) + v2.z);
			
			// cases where a vertex is on the split.
			if (v0.y == 0.0)
			{
				if (v1.y > 0)
				{
					AddTriangle(g_plus, make_triangle(v0, v1, v12));
					AddTriangle(g_minus, make_triangle(v0, v12, v2));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v0, v1, v12));
					AddTriangle(g_plus, make_triangle(v0, v12, v2));
				}
			}
			if (v1.y == 0.0)
			{
				if (v2.y > 0)
				{
					AddTriangle(g_plus, make_triangle(v1, v2, v20));
					AddTriangle(g_minus, make_triangle(v1, v20, v0));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v1, v2, v20));
					AddTriangle(g_plus, make_triangle(v1, v20, v0));
				}
			}
			if (v2.y == 0.0)
			{
				if (v0.y > 0)
				{
					AddTriangle(g_plus, make_triangle(v2, v0, v01));
					AddTriangle(g_minus, make_triangle(v2, v01, v1));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v2, v0, v01));
					AddTriangle(g_plus, make_triangle(v2, v01, v1));
				}
			}
			
			if ((v0.y > 0.0)&&(v1.y > 0.0)&&(v2.y < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v0, v12, v20));
				AddTriangle(g_plus, make_triangle(v0, v1, v12));
				AddTriangle(g_minus, make_triangle(v20, v12, v2));
			}
			
			if ((v0.y > 0.0)&&(v1.y < 0.0)&&(v2.y > 0.0))
			{
				AddTriangle(g_plus, make_triangle(v2, v01, v12));
				AddTriangle(g_plus, make_triangle(v2, v0, v01));
				AddTriangle(g_minus, make_triangle(v12, v01, v1));
			}
			
			if ((v0.y > 0.0)&&(v1.y < 0.0)&&(v2.y < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v20, v0, v01));
				AddTriangle(g_minus, make_triangle(v2, v20, v1));
				AddTriangle(g_minus, make_triangle(v20, v01, v1));
			}
			
			if ((v0.y < 0.0)&&(v1.y > 0.0)&&(v2.y > 0.0))
			{
				AddTriangle(g_minus, make_triangle(v01, v20, v0));
				AddTriangle(g_plus, make_triangle(v1, v20, v01));
				AddTriangle(g_plus, make_triangle(v1, v2, v20));
			}
			
			if ((v0.y < 0.0)&&(v1.y > 0.0)&&(v2.y < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v01, v1, v12));
				AddTriangle(g_minus, make_triangle(v0, v01, v2));
				AddTriangle(g_minus, make_triangle(v01, v12, v2));
			}
			
			if ((v0.y < 0.0)&&(v1.y < 0.0)&&(v2.y > 0.0))
			{
				AddTriangle(g_plus, make_triangle(v12, v2, v20));
				AddTriangle(g_minus, make_triangle(v1, v12, v0));
				AddTriangle(g_minus, make_triangle(v12, v20, v0));
			}			
		}
	}
	[g_plus translateY:-y];
	[g_minus translateY:y];
}


- (void) z_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) z
{
	// test each triangle splitting against z == 0.0
	//
	NSInteger	i;
	for (i = 0; i < n_triangles; i++)
	{
		BOOL done_tri = NO;
		Vector v0 = triangles[i].v[0];
		Vector v1 = triangles[i].v[1];
		Vector v2 = triangles[i].v[2];
		
		if ((v0.z >= 0.0)&&(v1.z >= 0.0)&&(v2.z >= 0.0))
		{
			AddTriangle(g_plus, triangles[i]);
			done_tri = YES;
		}
		if ((v0.z <= 0.0)&&(v1.z <= 0.0)&&(v2.z <= 0.0))
		{
			AddTriangle(g_minus, triangles[i]);
			done_tri = YES;
		}
		if (!done_tri)	// triangle must cross z == 0.0
		{
			GLfloat i01, i12, i20;
			if (v0.z == v1.z)
				i01 = -1.0f;
			else
				i01 = v0.z / (v0.z - v1.z);
			if (v1.z == v2.z)
				i12 = -1.0f;
			else
				i12 = v1.z / (v1.z - v2.z);
			if (v2.z == v0.z)
				i20 = -1.0f;
			else
				i20 = v2.z / (v2.z - v0.z);
			Vector v01 = make_vector(i01 * (v1.x - v0.x) + v0.x, i01 * (v1.y - v0.y) + v0.y, 0.0f);
			Vector v12 = make_vector(i12 * (v2.x - v1.x) + v1.x, i12 * (v2.y - v1.y) + v1.y, 0.0f);
			Vector v20 = make_vector(i20 * (v0.x - v2.x) + v2.x, i20 * (v0.y - v2.y) + v2.y, 0.0f);
		
			// cases where a vertex is on the split.
			if (v0.z == 0.0)
			{
				if (v1.z > 0)
				{
					AddTriangle(g_plus, make_triangle(v0, v1, v12));
					AddTriangle(g_minus, make_triangle(v0, v12, v2));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v0, v1, v12));
					AddTriangle(g_plus, make_triangle(v0, v12, v2));
				}
			}
			if (v1.z == 0.0)
			{
				if (v2.z > 0)
				{
					AddTriangle(g_plus, make_triangle(v1, v2, v20));
					AddTriangle(g_minus, make_triangle(v1, v20, v0));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v1, v2, v20));
					AddTriangle(g_plus, make_triangle(v1, v20, v0));
				}
			}
			if (v2.z == 0.0)
			{
				if (v0.z > 0)
				{
					AddTriangle(g_plus, make_triangle(v2, v0, v01));
					AddTriangle(g_minus, make_triangle(v2, v01, v1));
				}
				else
				{
					AddTriangle(g_minus, make_triangle(v2, v0, v01));
					AddTriangle(g_plus, make_triangle(v2, v01, v1));
				}
			}
			
			if ((v0.z > 0.0)&&(v1.z > 0.0)&&(v2.z < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v0, v12, v20));
				AddTriangle(g_plus, make_triangle(v0, v1, v12));
				AddTriangle(g_minus, make_triangle(v20, v12, v2));
			}
			
			if ((v0.z > 0.0)&&(v1.z < 0.0)&&(v2.z > 0.0))
			{
				AddTriangle(g_plus, make_triangle(v2, v01, v12));
				AddTriangle(g_plus, make_triangle(v2, v0, v01));
				AddTriangle(g_minus, make_triangle(v12, v01, v1));
			}
			
			if ((v0.z > 0.0)&&(v1.z < 0.0)&&(v2.z < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v20, v0, v01));
				AddTriangle(g_minus, make_triangle(v2, v20, v1));
				AddTriangle(g_minus, make_triangle(v20, v01, v1));
			}
			
			if ((v0.z < 0.0)&&(v1.z > 0.0)&&(v2.z > 0.0))
			{
				AddTriangle(g_minus, make_triangle(v01, v20, v0));
				AddTriangle(g_plus, make_triangle(v1, v20, v01));
				AddTriangle(g_plus, make_triangle(v1, v2, v20));
			}
			
			if ((v0.z < 0.0)&&(v1.z > 0.0)&&(v2.z < 0.0))
			{
				AddTriangle(g_plus, make_triangle(v01, v1, v12));
				AddTriangle(g_minus, make_triangle(v0, v01, v2));
				AddTriangle(g_minus, make_triangle(v01, v12, v2));
			}
			
			if ((v0.z < 0.0)&&(v1.z < 0.0)&&(v2.z > 0.0))
			{
				AddTriangle(g_plus, make_triangle(v12, v2, v20));
				AddTriangle(g_minus, make_triangle(v1, v12, v0));
				AddTriangle(g_minus, make_triangle(v12, v20, v0));
			}			

		}
	}
	[g_plus translateZ:-z];
	[g_minus translateZ:z];
}


/*
	void GrowTriangles(Geometry *self)
	
	Ensure there is enough space to add at least one more triangle.
	This is marked noinline so that the fast path in AddTriange() can be
	inlined. Without the attribute, clang (and probably gcc too) will inline
	GrowTriangles() into AddTriangle() (because it only has one call site),
	making AddTriangle() to heavy to inline.
*/
static GCC_ATTR((noinline)) void GrowTriangles(Geometry *self)
{
	if (self->triangles == NULL)
	{
		/*
			Lazily allocate triangle storage, since a significant portion of
			Geometries never have any triangles added to them. Note that
			max_triangles is set to the specified capacity in init even though
			the actual capacity is zero at that point.
			
			Profiling under the same conditions as the performance note at the
			top of the file found that this condition had a hit rate of 11%,
			which counterindicates the use of a branch hint.
		*/
		self->triangles = malloc(self->max_triangles * sizeof(Triangle));
	}
	
	// check for no-more-room.
	if (EXPECT_NOT(self->n_triangles == self->max_triangles))
	{
		// create more space by doubling the capacity of this geometry.
		self->max_triangles = 1 + self->max_triangles * 2;
		self->triangles = realloc(self->triangles, self->max_triangles * sizeof(Triangle));
		
		// N.b.: we leak here if realloc() failed, but we're about to abort anyway.
	}
	
	if (EXPECT_NOT(self->triangles == NULL))
	{
		OOLog(kOOLogAllocationFailure, @"!!!!! Ran out of memory to allocate more geometry!");
		exit(EXIT_FAILURE);
	}
}

@end
