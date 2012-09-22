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

#import "Geometry.h"

#import "OOMaths.h"
#import "Octree.h"
#import "OOLogging.h"


@interface Geometry (OOPrivate)

- (id) octreeWithinRadius:(GLfloat)octreeRadius toDepth:(int)depth;

- (BOOL) isConvex;
- (void) setConvex:(BOOL)value;

- (void) translate:(Vector)offset;
- (void) scale:(GLfloat)scalar;

- (void) x_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) x;
- (void) y_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) y;
- (void) z_axisSplitBetween:(Geometry*) g_plus :(Geometry*) g_minus :(GLfloat) z;

- (BOOL) testHasGeometry;
- (BOOL) testIsConvex;
- (BOOL) testCornersWithinGeometry:(GLfloat) corner;
- (GLfloat) findMaxDimensionFromOrigin;

@end


@implementation Geometry

- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%lu triangles, %@", n_triangles, [self testIsConvex] ? @"convex" : @"not convex"];
}


- (id) initWithCapacity:(NSUInteger)amount
{
	if (amount < 1)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		max_triangles = amount;
		triangles = malloc(max_triangles * sizeof(Triangle));	// allocate the required space
		n_triangles = 0;
		isConvex = NO;
	}
	
	return self;
}


- (void) dealloc
{
	free(triangles);	// free up the allocated space
	
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


static inline BOOL OOTriangleIsDegenerate(Triangle tri)
{
	return vector_equal(tri.v[0], tri.v[1]) ||
	       vector_equal(tri.v[1], tri.v[2]) ||
	       vector_equal(tri.v[2], tri.v[0]);
}


// SLOW_CODE This is a relatively costly method. A lot of growing is done despite the 1 + capacity * 2 growth rate.
- (void) addTriangle:(Triangle) tri
{
	// Ignore degenerate triangles.
	if (OOTriangleIsDegenerate(tri))
	{
		return;
	}
	
	// check for no-more-room
	if (EXPECT_NOT(n_triangles == max_triangles))
	{
		// create more space by doubling the capacity of this geometry...
		// OOLog(@"geometry.grow", @"Expanding geometry %p from %lu to %lu triangles.", self, max_triangles, 1 + max_triangles * 2);
		max_triangles = 1 + max_triangles * 2;
		triangles = realloc(triangles, max_triangles * sizeof(Triangle));
		if (EXPECT_NOT(triangles == NULL))
		{
			// N.b.: realloc() leaked here, but we're about to crash anyway.
			OOLog(kOOLogAllocationFailure, @"!!!!! Ran out of memory to allocate more geometry!");
			exit(EXIT_FAILURE);
		}
	}
	triangles[n_triangles++] = tri;
}


- (BOOL) testHasGeometry
{
	return (n_triangles > 0);
}


- (BOOL) testIsConvex
{
	// enumerate over triangles
	// calculate normal for each one
	// then enumerate over vertices relative to a vertex on the triangle
	// and check if they are on the forwardside or coplanar with the triangle
	// if a vertex is on the backside of any triangle then return NO;
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
	// enumerate over triangles
	// calculate normal for each one
	// then enumerate over corners relative to a vertex on the triangle
	// and check if they are on the forwardside or coplanar with the triangle
	// if a corner is on the backside of any triangle then return NO;
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
	//
	GLfloat offset = 0.5f * octreeRadius;
	//
	if (![self testHasGeometry])
	{
		leafcount++;	// nil or zero or 0
		return [NSNumber numberWithBool:NO];	// empty octree
	}
	// there is geometry!
	//
	if ((octreeRadius <= OCTREE_MIN_RADIUS)||(depth <= 0))	// maximum resolution
	{
		leafcount++;	// partially full or -1
		volumecount += octreeRadius * octreeRadius * octreeRadius * 0.5f;
		return [NSNumber numberWithBool:YES];	// at least partially full octree
	}
	//
	if (!isConvex)
		[self testIsConvex]; // check!
	//
	if (isConvex)	// we're convex!
	{
		if ([self testCornersWithinGeometry: octreeRadius])	// all eight corners inside or on!
		{
			leafcount++;	// full or -1
			volumecount += octreeRadius * octreeRadius * octreeRadius;
			return [NSNumber numberWithBool:YES];	// full octree
		}
	}
	//
	// SLOW_CODE -- all these allocations and deallocations are quite costly. Would a bucket allocator work? --ahruman
	Geometry* g_000 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_001 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_010 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_011 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_100 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_101 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_110 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_111 = [(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	//
	Geometry* g_xx1 =	[(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	Geometry* g_xx0 =	[(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
	//
	[self z_axisSplitBetween:g_xx1 :g_xx0 : offset];
	if ([g_xx0 testHasGeometry])
	{
		Geometry* g_x00 =	[(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
		Geometry* g_x10 =	[(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
		//
		[g_xx0 y_axisSplitBetween: g_x10 : g_x00 : offset];
		if ([g_x00 testHasGeometry])
		{
			[g_x00 x_axisSplitBetween:g_100 :g_000 : offset];
			[g_000 setConvex: isConvex];
			[g_100 setConvex: isConvex];
		}
		if ([g_x10 testHasGeometry])
		{
			[g_x10 x_axisSplitBetween:g_110 :g_010 : offset];
			[g_010 setConvex: isConvex];
			[g_110 setConvex: isConvex];
		}
		[g_x00 release];
		[g_x10 release];
	}
	if ([g_xx1 testHasGeometry])
	{
		Geometry* g_x01 =	[(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
		Geometry* g_x11 =	[(Geometry *)[Geometry alloc] initWithCapacity:n_triangles];
		//
		[g_xx1 y_axisSplitBetween: g_x11 : g_x01 :offset];
		if ([g_x01 testHasGeometry])
		{
			[g_x01 x_axisSplitBetween:g_101 :g_001 :offset];
			[g_001 setConvex: isConvex];
			[g_101 setConvex: isConvex];
		}
		if ([g_x11 testHasGeometry])
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


- (void) translate:(Vector)offset
{
	NSInteger	i;
	for (i = 0; i < n_triangles; i++)
	{
		triangles[i].v[0].x += offset.x;
		triangles[i].v[1].x += offset.x;
		triangles[i].v[2].x += offset.x;
		
		triangles[i].v[0].y += offset.y;
		triangles[i].v[1].y += offset.y;
		triangles[i].v[2].y += offset.y;
		
		triangles[i].v[0].z += offset.z;
		triangles[i].v[1].z += offset.z;
		triangles[i].v[2].z += offset.z;
	}
}


- (void) scale:(GLfloat)scalar
{
	NSInteger	i;
	for (i = 0; i < n_triangles; i++)
	{
		triangles[i].v[0].x *= scalar;
		triangles[i].v[1].x *= scalar;
		triangles[i].v[2].x *= scalar;
		triangles[i].v[0].y *= scalar;
		triangles[i].v[1].y *= scalar;
		triangles[i].v[2].y *= scalar;
		triangles[i].v[0].z *= scalar;
		triangles[i].v[1].z *= scalar;
		triangles[i].v[2].z *= scalar;
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
			[g_plus addTriangle: triangles[i]];
			done_tri = YES;
		}
		if ((v0.x <= 0.0)&&(v1.x <= 0.0)&&(v2.x <= 0.0))
		{
			[g_minus addTriangle: triangles[i]];
			done_tri = YES;
		}
		if (!done_tri)	// triangle must cross y == 0.0
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
		
			// cases where a vertex is on the split..
			if (v0.x == 0.0)
			{
				if (v1.x > 0)
				{
					[g_plus addTriangle:make_triangle(v0, v1, v12)];
					[g_minus addTriangle:make_triangle(v0, v12, v2)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v0, v1, v12)];
					[g_plus addTriangle:make_triangle(v0, v12, v2)];
				}
			}
			if (v1.x == 0.0)
			{
				if (v2.x > 0)
				{
					[g_plus addTriangle:make_triangle(v1, v2, v20)];
					[g_minus addTriangle:make_triangle(v1, v20, v0)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v1, v2, v20)];
					[g_plus addTriangle:make_triangle(v1, v20, v0)];
				}
			}
			if (v2.x == 0.0)
			{
				if (v0.x > 0)
				{
					[g_plus addTriangle:make_triangle(v2, v0, v01)];
					[g_minus addTriangle:make_triangle(v2, v01, v1)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v2, v0, v01)];
					[g_plus addTriangle:make_triangle(v2, v01, v1)];
				}
			}
			
			if ((v0.x > 0.0)&&(v1.x > 0.0)&&(v2.x < 0.0))
			{
				[g_plus addTriangle:make_triangle(v0, v12, v20)];
				[g_plus addTriangle:make_triangle(v0, v1, v12)];
				[g_minus addTriangle:make_triangle(v20, v12, v2)];
			}
			
			if ((v0.x > 0.0)&&(v1.x < 0.0)&&(v2.x > 0.0))
			{
				[g_plus addTriangle:make_triangle(v2, v01, v12)];
				[g_plus addTriangle:make_triangle(v2, v0, v01)];
				[g_minus addTriangle:make_triangle(v12, v01, v1)];
			}
			
			if ((v0.x > 0.0)&&(v1.x < 0.0)&&(v2.x < 0.0))
			{
				[g_plus addTriangle:make_triangle(v20, v0, v01)];
				[g_minus addTriangle:make_triangle(v2, v20, v1)];
				[g_minus addTriangle:make_triangle(v20, v01, v1)];
			}
			
			if ((v0.x < 0.0)&&(v1.x > 0.0)&&(v2.x > 0.0))
			{
				[g_minus addTriangle:make_triangle(v01, v20, v0)];
				[g_plus addTriangle:make_triangle(v1, v20, v01)];
				[g_plus addTriangle:make_triangle(v1, v2, v20)];
			}
			
			if ((v0.x < 0.0)&&(v1.x > 0.0)&&(v2.x < 0.0))
			{
				[g_plus addTriangle:make_triangle(v01, v1, v12)];
				[g_minus addTriangle:make_triangle(v0, v01, v2)];
				[g_minus addTriangle:make_triangle(v01, v12, v2)];
			}
			
			if ((v0.x < 0.0)&&(v1.x < 0.0)&&(v2.x > 0.0))
			{
				[g_plus addTriangle:make_triangle(v12, v2, v20)];
				[g_minus addTriangle:make_triangle(v1, v12, v0)];
				[g_minus addTriangle:make_triangle(v12, v20, v0)];
			}			

		}
	}
	[g_plus translate: make_vector(-x, 0.0f, 0.0f)];
	[g_minus translate: make_vector(x, 0.0f, 0.0f)];
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
			[g_plus addTriangle: triangles[i]];
			done_tri = YES;
		}
		if ((v0.y <= 0.0)&&(v1.y <= 0.0)&&(v2.y <= 0.0))
		{
			[g_minus addTriangle: triangles[i]];
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
			
			// cases where a vertex is on the split..
			if (v0.y == 0.0)
			{
				if (v1.y > 0)
				{
					[g_plus addTriangle:make_triangle(v0, v1, v12)];
					[g_minus addTriangle:make_triangle(v0, v12, v2)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v0, v1, v12)];
					[g_plus addTriangle:make_triangle(v0, v12, v2)];
				}
			}
			if (v1.y == 0.0)
			{
				if (v2.y > 0)
				{
					[g_plus addTriangle:make_triangle(v1, v2, v20)];
					[g_minus addTriangle:make_triangle(v1, v20, v0)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v1, v2, v20)];
					[g_plus addTriangle:make_triangle(v1, v20, v0)];
				}
			}
			if (v2.y == 0.0)
			{
				if (v0.y > 0)
				{
					[g_plus addTriangle:make_triangle(v2, v0, v01)];
					[g_minus addTriangle:make_triangle(v2, v01, v1)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v2, v0, v01)];
					[g_plus addTriangle:make_triangle(v2, v01, v1)];
				}
			}
			
			if ((v0.y > 0.0)&&(v1.y > 0.0)&&(v2.y < 0.0))
			{
				[g_plus addTriangle:make_triangle(v0, v12, v20)];
				[g_plus addTriangle:make_triangle(v0, v1, v12)];
				[g_minus addTriangle:make_triangle(v20, v12, v2)];
			}
			
			if ((v0.y > 0.0)&&(v1.y < 0.0)&&(v2.y > 0.0))
			{
				[g_plus addTriangle:make_triangle(v2, v01, v12)];
				[g_plus addTriangle:make_triangle(v2, v0, v01)];
				[g_minus addTriangle:make_triangle(v12, v01, v1)];
			}
			
			if ((v0.y > 0.0)&&(v1.y < 0.0)&&(v2.y < 0.0))
			{
				[g_plus addTriangle:make_triangle(v20, v0, v01)];
				[g_minus addTriangle:make_triangle(v2, v20, v1)];
				[g_minus addTriangle:make_triangle(v20, v01, v1)];
			}
			
			if ((v0.y < 0.0)&&(v1.y > 0.0)&&(v2.y > 0.0))
			{
				[g_minus addTriangle:make_triangle(v01, v20, v0)];
				[g_plus addTriangle:make_triangle(v1, v20, v01)];
				[g_plus addTriangle:make_triangle(v1, v2, v20)];
			}
			
			if ((v0.y < 0.0)&&(v1.y > 0.0)&&(v2.y < 0.0))
			{
				[g_plus addTriangle:make_triangle(v01, v1, v12)];
				[g_minus addTriangle:make_triangle(v0, v01, v2)];
				[g_minus addTriangle:make_triangle(v01, v12, v2)];
			}
			
			if ((v0.y < 0.0)&&(v1.y < 0.0)&&(v2.y > 0.0))
			{
				[g_plus addTriangle:make_triangle(v12, v2, v20)];
				[g_minus addTriangle:make_triangle(v1, v12, v0)];
				[g_minus addTriangle:make_triangle(v12, v20, v0)];
			}			
		}
	}
	[g_plus translate: make_vector(0.0f, -y, 0.0f)];
	[g_minus translate: make_vector(0.0f, y, 0.0f)];
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
			[g_plus addTriangle: triangles[i]];
			done_tri = YES;
		}
		if ((v0.z <= 0.0)&&(v1.z <= 0.0)&&(v2.z <= 0.0))
		{
			[g_minus addTriangle: triangles[i]];
			done_tri = YES;
		}
		if (!done_tri)	// triangle must cross y == 0.0
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
		
			// cases where a vertex is on the split..
			if (v0.z == 0.0)
			{
				if (v1.z > 0)
				{
					[g_plus addTriangle:make_triangle(v0, v1, v12)];
					[g_minus addTriangle:make_triangle(v0, v12, v2)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v0, v1, v12)];
					[g_plus addTriangle:make_triangle(v0, v12, v2)];
				}
			}
			if (v1.z == 0.0)
			{
				if (v2.z > 0)
				{
					[g_plus addTriangle:make_triangle(v1, v2, v20)];
					[g_minus addTriangle:make_triangle(v1, v20, v0)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v1, v2, v20)];
					[g_plus addTriangle:make_triangle(v1, v20, v0)];
				}
			}
			if (v2.z == 0.0)
			{
				if (v0.z > 0)
				{
					[g_plus addTriangle:make_triangle(v2, v0, v01)];
					[g_minus addTriangle:make_triangle(v2, v01, v1)];
				}
				else
				{
					[g_minus addTriangle:make_triangle(v2, v0, v01)];
					[g_plus addTriangle:make_triangle(v2, v01, v1)];
				}
			}
			
			if ((v0.z > 0.0)&&(v1.z > 0.0)&&(v2.z < 0.0))
			{
				[g_plus addTriangle:make_triangle(v0, v12, v20)];
				[g_plus addTriangle:make_triangle(v0, v1, v12)];
				[g_minus addTriangle:make_triangle(v20, v12, v2)];
			}
			
			if ((v0.z > 0.0)&&(v1.z < 0.0)&&(v2.z > 0.0))
			{
				[g_plus addTriangle:make_triangle(v2, v01, v12)];
				[g_plus addTriangle:make_triangle(v2, v0, v01)];
				[g_minus addTriangle:make_triangle(v12, v01, v1)];
			}
			
			if ((v0.z > 0.0)&&(v1.z < 0.0)&&(v2.z < 0.0))
			{
				[g_plus addTriangle:make_triangle(v20, v0, v01)];
				[g_minus addTriangle:make_triangle(v2, v20, v1)];
				[g_minus addTriangle:make_triangle(v20, v01, v1)];
			}
			
			if ((v0.z < 0.0)&&(v1.z > 0.0)&&(v2.z > 0.0))
			{
				[g_minus addTriangle:make_triangle(v01, v20, v0)];
				[g_plus addTriangle:make_triangle(v1, v20, v01)];
				[g_plus addTriangle:make_triangle(v1, v2, v20)];
			}
			
			if ((v0.z < 0.0)&&(v1.z > 0.0)&&(v2.z < 0.0))
			{
				[g_plus addTriangle:make_triangle(v01, v1, v12)];
				[g_minus addTriangle:make_triangle(v0, v01, v2)];
				[g_minus addTriangle:make_triangle(v01, v12, v2)];
			}
			
			if ((v0.z < 0.0)&&(v1.z < 0.0)&&(v2.z > 0.0))
			{
				[g_plus addTriangle:make_triangle(v12, v2, v20)];
				[g_minus addTriangle:make_triangle(v1, v12, v0)];
				[g_minus addTriangle:make_triangle(v12, v20, v0)];
			}			

		}
	}
	[g_plus translate: make_vector(0.0f, 0.0f, -z)];
	[g_minus translate: make_vector(0.0f, 0.0f, z)];
}

@end
