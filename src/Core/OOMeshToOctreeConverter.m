/*

OOMeshToOctreeConverter.m

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

#import "OOMeshToOctreeConverter.h"


/*
	DESIGN NOTES
	
	OOMeshToOctreeConverter is responsible for analyzing a set of triangles
	from an OOMesh and turning them into an Octree using OOOctreeBuilder. This
	is a relatively heavyweight operation which is run on the main thread when
	loading a ship that isn't cached. Since ship set-up affects startup time
	and in-game stutter, this is performance-critical.
	
	The octree generation algorithm works as follows:
	Given a set of triangles within a bounding cube, and an iteration limit,
	do the following:
	* If the set of triangles is empty, produce an empty octree node.
	* Otherwise, if the iteration limit is reached, produce a solid node.	
	* Otherwise, divide the set of triangles into eight equally-sized child
      cubes (splitting triangles if needed); create an inner node in the octree;
	  and repeat the algorithm for each of the eight children.
	
	OOOctreeBuilder performs a simple structural optimization where an inner
	node whose child nodes are all solid is replaced with a solid node. This
	is effective recursively and very cheap. As such, there is no need for
	OOMeshToOctreeConverter to try to detect this situation.
	
	On a typical cold startup with no OXPs loaded, well over two million octree
	nodes are processed by OOMeshToOctreeConverter. The highest number of nodes
	in existence at once is 53. Our main performance concerns are to minimize
	the amount of memory managment per node and to avoid dynamic dispatch in
	critical areas, while minimizing the number of allocations per node is not
	very important.
	
	The current implementation uses a struct (defined in the header as
	OOMeshToOctreeConverterInternalData, and locally known as GeometryData)
	to store the triangle set. The root GeometryData is an instance variable
	of OOMeshToOctreeConverter, and children are created on the stack while
	iterating.
	
	Up to sixteen triangles can be stored directly in the GeometryData. If more
	than sixteen are needed, a heap-allocated array is used instead. At one
	point, I attempted to be cleverer about the storage using unions and implied
	capacity, but this was significantly slower with only small amounts of stack
	space saved.
	
	Profiling shows that over 93 % of nodes use sixteen or fewer triangles in
	vanilla Oolite. The proportion is lower when using OXPs with more complex
	models.
*/

#import "OOMaths.h"
#import "Octree.h"
#import "OOLogging.h"


// MARK: GeometryData operations.

/*
	GeometryData
	
	Struct tracking a set of triangles. Must be initialized using
	InitGeometryData() before other operations.
	
	capacity is an estimate of the required size. If the number of triangles
	added exceeds kOOMeshToOctreeConverterSmallDataCapacity, the capacity will
	be used as the initial heap-allocated size, unless it's smaller than a
	minimum threshold.
	
	
	Triangle *triangles
		Pointer to the triangle array. Initially points at smallData.
	
	uint_fast32_t count
		The number of triangles currently in the GeometryData.
	
	uint_fast32_t capacity
		The number of slots in triangles. Invariant: count <= capacity.
	
	uint_fast32_t pendingCapacity
		The capacity hint passed to InitGeometryData(). Used by
		AddTriangle_slow().
	
	Triangle smallData[]
		Initial triangle storage. Should not be accessed directly; if it's
		relevant, triangles points to it.
*/
typedef struct OOMeshToOctreeConverterInternalData GeometryData;


/*
	InitGeometryData(data, capacity)
	
	Prepare a GeometryData struct for use.
	The data has to be by reference rather than a return value so that the
	triangles pointer can be pointed into the struct.
*/
OOINLINE void InitGeometryData(GeometryData *data, uint_fast32_t capacity);

/*
	DestroyGeometryData(data)
	
	Deallocates dynamic storage if necessary. Leaves the GeometryData in an
	invalid state.
*/
OOINLINE void DestroyGeometryData(GeometryData *data);

/*
	AddTriangle(data, tri)
	
	Add a triangle to a GeometryData. Will either succeed or abort.
	AddTriangle() is designed so that its fast case will be inlined (at least,
	if assertions are disabled as in Deployment builds) and its slow case will
	not.
	
	
	AddTriangle_slow(data, tri)
	
	Slow path for AddTriangle(), used when more space is needed. Should not
	be called directly. Invariant: may only be called when count == capacity.
*/
OOINLINE void AddTriangle(GeometryData *data, Triangle tri);
static NO_INLINE_FUNC void AddTriangle_slow(GeometryData *data, Triangle tri);

/*
	MaxDimensionFromOrigin(data)
	
	Calculates the half-width of a bounding cube around data centered at the
	origin.
*/
static OOScalar MaxDimensionFromOrigin(GeometryData *data);

/*
	BuildSubOctree(data, builder, halfWidth, depth)
	
	Recursively apply the octree generation algorithm.
		data: input geometry data.
		builder: OOOctreeBuilder where results are accumulated. Each call will
		          write one complete subtree, which may be a single leaf node.
		halfWidth: the half-width of the bounding cube of data.
		depth: recursion limit.
*/
void BuildSubOctree(GeometryData *data, OOOctreeBuilder *builder, OOScalar halfWidth, NSUInteger depth);

/*
	SplitGeometry{X|Y|Z}(data, dPlus, dMinus, offset)
	
	Divide data across its local zero plane perpendicular to the specified axis,
	putting triangles with coordinates >= 0 in dPlus and triangles with
	coordinates <= 0 in dMinus. Triangles will be split if necessary. Generated
	triangles will be offset by the specified amount (half of data's half-width)
	so that the split planes of dPlus and dMinus will be in the middle of their
	data sets.
*/
static void SplitGeometryX(GeometryData *data, GeometryData *dPlus, GeometryData *dMinus, OOScalar x);
static void SplitGeometryY(GeometryData *data, GeometryData *dPlus, GeometryData *dMinus, OOScalar y);
static void SplitGeometryZ(GeometryData *data, GeometryData *dPlus, GeometryData *dMinus, OOScalar z);


// MARK: Inline function bodies.

void InitGeometryData(GeometryData *data, uint_fast32_t capacity)
{
	NSCParameterAssert(data != NULL);
	
	data->count = 0;
	data->capacity = kOOMeshToOctreeConverterSmallDataCapacity;
	data->pendingCapacity = capacity;
	data->triangles = data->smallData;
}


OOINLINE void DestroyGeometryData(GeometryData *data)
{
	NSCParameterAssert(data != 0 && data->capacity >= kOOMeshToOctreeConverterSmallDataCapacity);
	
#if OO_DEBUG
	Triangle * const kScribbleValue = (Triangle *)-1L;
	NSCAssert(data->triangles != kScribbleValue, @"Attempt to destroy a GeometryData twice.");
#endif
	
	if (data->capacity != kOOMeshToOctreeConverterSmallDataCapacity)
	{
		// If capacity is kOOMeshToOctreeConverterSmallDataCapacity, triangles points to smallData.
		free(data->triangles);
	}
	
#if OO_DEBUG
	data->triangles = kScribbleValue;
#endif
}


OOINLINE void AddTriangle(GeometryData *data, Triangle tri)
{
	NSCParameterAssert(data != NULL);
	
	if (data->count < data->capacity)
	{
		data->triangles[data->count++] = tri;
	}
	else
	{
		AddTriangle_slow(data, tri);
	}
}


@implementation OOMeshToOctreeConverter

- (id) initWithCapacity:(NSUInteger)capacity
{
	NSParameterAssert(capacity > 0 && capacity < UINT32_MAX);
	
	if ((self = [super init]))
	{
		InitGeometryData(&_data, (uint_fast32_t)capacity);
	}
	
	return self;
}


- (void) dealloc
{
	DestroyGeometryData(&_data);
	
	[super dealloc];
}


+ (instancetype) converterWithCapacity:(NSUInteger)capacity
{
	return [[[self alloc] initWithCapacity:capacity] autorelease];
}


- (NSString *) descriptionComponents
{
	return [NSString stringWithFormat:@"%u triangles", _data.count];
}


- (void) addTriangle:(Triangle)tri
{
	if (!OOTriangleIsDegenerate(tri))
	{
		AddTriangle(&_data, tri);
	}
}


- (Octree *) findOctreeToDepth:(NSUInteger)depth
{
	OOOctreeBuilder *builder = [[[OOOctreeBuilder alloc] init] autorelease];
	OOScalar halfWidth = 0.5f + MaxDimensionFromOrigin(&_data);	// pad out from geometry by a half meter
	
	BuildSubOctree(&_data, builder, halfWidth, depth);
	
	return [builder buildOctreeWithRadius:halfWidth];
}

@end


static OOScalar MaxDimensionFromOrigin(GeometryData *data)
{
	NSCParameterAssert(data != NULL);
	
	OOScalar		result = 0.0f;
	uint_fast32_t	i, j;
	for (i = 0; i < data->count; i++) for (j = 0; j < 3; j++)
	{
		Vector v = data->triangles[i].v[j];
		
		result = fmax(result, fabs(v.x));
		result = fmax(result, fabs(v.y));
		result = fmax(result, fabs(v.z));
	}
	return result;
}


void BuildSubOctree(GeometryData *data, OOOctreeBuilder *builder, OOScalar halfWidth, NSUInteger depth)
{
	NSCParameterAssert(data != NULL);
	
	OOScalar subHalfWidth = 0.5f * halfWidth;
	
	if (data->count == 0)
	{
		// No geometry here.
		[builder writeEmpty];
		return;
	}
	
	if (halfWidth <= OCTREE_MIN_HALF_WIDTH || depth <= 0)
	{
		// Maximum resolution reached and not full.
		[builder writeSolid];
		return;
	}

	/*
		To avoid reallocations, we want a reasonably pessimistic estimate of
		sub-data size.
		
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
		
		As of r5374, up to 16 entries are stored on the stack and there is no
		benefit to specifying a minimum here any longer.
	*/
	enum
	{
		kFactor = 2
	};
	uint_fast32_t subCapacity = data->count * kFactor;
	
#define DECL_GEOMETRY(NAME, CAP) GeometryData NAME; InitGeometryData(&NAME, CAP);
	
	DECL_GEOMETRY(g_000, subCapacity);
	DECL_GEOMETRY(g_001, subCapacity);
	DECL_GEOMETRY(g_010, subCapacity);
	DECL_GEOMETRY(g_011, subCapacity);
	DECL_GEOMETRY(g_100, subCapacity);
	DECL_GEOMETRY(g_101, subCapacity);
	DECL_GEOMETRY(g_110, subCapacity);
	DECL_GEOMETRY(g_111, subCapacity);
	
	DECL_GEOMETRY(g_xx1, subCapacity);
	DECL_GEOMETRY(g_xx0, subCapacity);
	
	SplitGeometryZ(data, &g_xx1, &g_xx0, subHalfWidth);
	if (g_xx0.count != 0)
	{
		DECL_GEOMETRY(g_x00, subCapacity);
		DECL_GEOMETRY(g_x10, subCapacity);
		
		SplitGeometryY(&g_xx0, &g_x10, &g_x00, subHalfWidth);
		if (g_x00.count != 0)
		{
			SplitGeometryX(&g_x00, &g_100, &g_000, subHalfWidth);
		}
		if (g_x10.count != 0)
		{
			SplitGeometryX(&g_x10, &g_110, &g_010, subHalfWidth);
		}
		DestroyGeometryData(&g_x00);
		DestroyGeometryData(&g_x10);
	}
	if (g_xx1.count != 0)
	{
		DECL_GEOMETRY(g_x01, subCapacity);
		DECL_GEOMETRY(g_x11, subCapacity);
		
		SplitGeometryY(&g_xx1, &g_x11, &g_x01, subHalfWidth);
		if (g_x01.count != 0)
		{
			SplitGeometryX(&g_x01, &g_101, &g_001, subHalfWidth);
		}
		if (g_x11.count != 0)
		{
			SplitGeometryX(&g_x11, &g_111, &g_011, subHalfWidth);
		}
		DestroyGeometryData(&g_x01);
		DestroyGeometryData(&g_x11);
	}
	DestroyGeometryData(&g_xx0);
	DestroyGeometryData(&g_xx1);
	
	[builder beginInnerNode];
	depth--;
	BuildSubOctree(&g_000, builder, subHalfWidth, depth);
	BuildSubOctree(&g_001, builder, subHalfWidth, depth);
	BuildSubOctree(&g_010, builder, subHalfWidth, depth);
	BuildSubOctree(&g_011, builder, subHalfWidth, depth);
	BuildSubOctree(&g_100, builder, subHalfWidth, depth);
	BuildSubOctree(&g_101, builder, subHalfWidth, depth);
	BuildSubOctree(&g_110, builder, subHalfWidth, depth);
	BuildSubOctree(&g_111, builder, subHalfWidth, depth);
	[builder endInnerNode];
	
	DestroyGeometryData(&g_000);
	DestroyGeometryData(&g_001);
	DestroyGeometryData(&g_010);
	DestroyGeometryData(&g_011);
	DestroyGeometryData(&g_100);
	DestroyGeometryData(&g_101);
	DestroyGeometryData(&g_110);
	DestroyGeometryData(&g_111);
}


static void TranslateGeometryX(GeometryData *data, OOScalar offset)
{
	NSCParameterAssert(data != NULL);
	
	// Optimization note: offset is never zero, so no early return.
	
	uint_fast32_t i, count = data->count;
	for (i = 0; i < count; i++)
	{
		data->triangles[i].v[0].x += offset;
		data->triangles[i].v[1].x += offset;
		data->triangles[i].v[2].x += offset;
	}
}


static void TranslateGeometryY(GeometryData *data, OOScalar offset)
{
	NSCParameterAssert(data != NULL);
	
	// Optimization note: offset is never zero, so no early return.
	
	uint_fast32_t i, count = data->count;
	for (i = 0; i < count; i++)
	{
		data->triangles[i].v[0].y += offset;
		data->triangles[i].v[1].y += offset;
		data->triangles[i].v[2].y += offset;
	}
}


static void TranslateGeometryZ(GeometryData *data, OOScalar offset)
{
	NSCParameterAssert(data != NULL);
	
	// Optimization note: offset is never zero, so no early return.
	
	uint_fast32_t i, count = data->count;
	for (i = 0; i < count; i++)
	{
		data->triangles[i].v[0].z += offset;
		data->triangles[i].v[1].z += offset;
		data->triangles[i].v[2].z += offset;
	}
}


static void SplitGeometryX(GeometryData *data, GeometryData *dPlus, GeometryData *dMinus, OOScalar x)
{
	NSCParameterAssert(data != NULL && dPlus != NULL && dMinus != NULL);
	
	// test each triangle splitting against x == 0.0
	uint_fast32_t	i, count = data->count;
	for (i = 0; i < count; i++)
	{
		bool done_tri = false;
		Vector v0 = data->triangles[i].v[0];
		Vector v1 = data->triangles[i].v[1];
		Vector v2 = data->triangles[i].v[2];
		
		if (v0.x >= 0.0f && v1.x >= 0.0f && v2.x >= 0.0f)
		{
			AddTriangle(dPlus, data->triangles[i]);
			done_tri = true;
		}
		else if (v0.x <= 0.0f && v1.x <= 0.0f && v2.x <= 0.0f)
		{
			AddTriangle(dMinus, data->triangles[i]);
			done_tri = true;
		}
		if (!done_tri)	// triangle must cross x == 0.0
		{
			OOScalar i01, i12, i20;
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
			if (v0.x == 0.0f)
			{
				if (v1.x > 0)
				{
					AddTriangle(dPlus, make_triangle(v0, v1, v12));
					AddTriangle(dMinus, make_triangle(v0, v12, v2));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v0, v1, v12));
					AddTriangle(dPlus, make_triangle(v0, v12, v2));
				}
			}
			if (v1.x == 0.0f)
			{
				if (v2.x > 0)
				{
					AddTriangle(dPlus, make_triangle(v1, v2, v20));
					AddTriangle(dMinus, make_triangle(v1, v20, v0));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v1, v2, v20));
					AddTriangle(dPlus, make_triangle(v1, v20, v0));
				}
			}
			if (v2.x == 0.0f)
			{
				if (v0.x > 0)
				{
					AddTriangle(dPlus, make_triangle(v2, v0, v01));
					AddTriangle(dMinus, make_triangle(v2, v01, v1));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v2, v0, v01));
					AddTriangle(dPlus, make_triangle(v2, v01, v1));
				}
			}
			
			if (v0.x > 0.0f && v1.x > 0.0f && v2.x < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v0, v12, v20));
				AddTriangle(dPlus, make_triangle(v0, v1, v12));
				AddTriangle(dMinus, make_triangle(v20, v12, v2));
			}
			
			if (v0.x > 0.0f && v1.x < 0.0f && v2.x > 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v2, v01, v12));
				AddTriangle(dPlus, make_triangle(v2, v0, v01));
				AddTriangle(dMinus, make_triangle(v12, v01, v1));
			}
			
			if (v0.x > 0.0f && v1.x < 0.0f && v2.x < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v20, v0, v01));
				AddTriangle(dMinus, make_triangle(v2, v20, v1));
				AddTriangle(dMinus, make_triangle(v20, v01, v1));
			}
			
			if (v0.x < 0.0f && v1.x > 0.0f && v2.x > 0.0f)
			{
				AddTriangle(dMinus, make_triangle(v01, v20, v0));
				AddTriangle(dPlus, make_triangle(v1, v20, v01));
				AddTriangle(dPlus, make_triangle(v1, v2, v20));
			}
			
			if (v0.x < 0.0f && v1.x > 0.0f && v2.x < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v01, v1, v12));
				AddTriangle(dMinus, make_triangle(v0, v01, v2));
				AddTriangle(dMinus, make_triangle(v01, v12, v2));
			}
			
			if (v0.x < 0.0f && v1.x < 0.0f && v2.x > 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v12, v2, v20));
				AddTriangle(dMinus, make_triangle(v1, v12, v0));
				AddTriangle(dMinus, make_triangle(v12, v20, v0));
			}
		}
	}
	TranslateGeometryX(dPlus, -x);
	TranslateGeometryX(dMinus, x);
}


static void SplitGeometryY(GeometryData *data, GeometryData *dPlus, GeometryData *dMinus, OOScalar y)
{
	NSCParameterAssert(data != NULL && dPlus != NULL && dMinus != NULL);
	
	// test each triangle splitting against y == 0.0
	uint_fast32_t	i, count = data->count;
	for (i = 0; i < count; i++)
	{
		bool done_tri = false;
		Vector v0 = data->triangles[i].v[0];
		Vector v1 = data->triangles[i].v[1];
		Vector v2 = data->triangles[i].v[2];

		if (v0.y >= 0.0f && v1.y >= 0.0f && v2.y >= 0.0f)
		{
			AddTriangle(dPlus, data->triangles[i]);
			done_tri = true;
		}
		if (v0.y <= 0.0f && v1.y <= 0.0f && v2.y <= 0.0f)
		{
			AddTriangle(dMinus, data->triangles[i]);
			done_tri = true;
		}
		if (!done_tri)	// triangle must cross y == 0.0
		{
			OOScalar i01, i12, i20;
			
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
			if (v0.y == 0.0f)
			{
				if (v1.y > 0)
				{
					AddTriangle(dPlus, make_triangle(v0, v1, v12));
					AddTriangle(dMinus, make_triangle(v0, v12, v2));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v0, v1, v12));
					AddTriangle(dPlus, make_triangle(v0, v12, v2));
				}
			}
			if (v1.y == 0.0f)
			{
				if (v2.y > 0)
				{
					AddTriangle(dPlus, make_triangle(v1, v2, v20));
					AddTriangle(dMinus, make_triangle(v1, v20, v0));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v1, v2, v20));
					AddTriangle(dPlus, make_triangle(v1, v20, v0));
				}
			}
			if (v2.y == 0.0f)
			{
				if (v0.y > 0)
				{
					AddTriangle(dPlus, make_triangle(v2, v0, v01));
					AddTriangle(dMinus, make_triangle(v2, v01, v1));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v2, v0, v01));
					AddTriangle(dPlus, make_triangle(v2, v01, v1));
				}
			}
			
			if (v0.y > 0.0f && v1.y > 0.0f && v2.y < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v0, v12, v20));
				AddTriangle(dPlus, make_triangle(v0, v1, v12));
				AddTriangle(dMinus, make_triangle(v20, v12, v2));
			}
			
			if (v0.y > 0.0f && v1.y < 0.0f && v2.y > 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v2, v01, v12));
				AddTriangle(dPlus, make_triangle(v2, v0, v01));
				AddTriangle(dMinus, make_triangle(v12, v01, v1));
			}
			
			if (v0.y > 0.0f && v1.y < 0.0f && v2.y < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v20, v0, v01));
				AddTriangle(dMinus, make_triangle(v2, v20, v1));
				AddTriangle(dMinus, make_triangle(v20, v01, v1));
			}
			
			if (v0.y < 0.0f && v1.y > 0.0f && v2.y > 0.0f)
			{
				AddTriangle(dMinus, make_triangle(v01, v20, v0));
				AddTriangle(dPlus, make_triangle(v1, v20, v01));
				AddTriangle(dPlus, make_triangle(v1, v2, v20));
			}
			
			if (v0.y < 0.0f && v1.y > 0.0f && v2.y < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v01, v1, v12));
				AddTriangle(dMinus, make_triangle(v0, v01, v2));
				AddTriangle(dMinus, make_triangle(v01, v12, v2));
			}
			
			if (v0.y < 0.0f && v1.y < 0.0f && v2.y > 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v12, v2, v20));
				AddTriangle(dMinus, make_triangle(v1, v12, v0));
				AddTriangle(dMinus, make_triangle(v12, v20, v0));
			}			
		}
	}
	TranslateGeometryY(dPlus, -y);
	TranslateGeometryY(dMinus, y);
}


static void SplitGeometryZ(GeometryData *data, GeometryData *dPlus, GeometryData *dMinus, OOScalar z)
{
	NSCParameterAssert(data != NULL && dPlus != NULL && dMinus != NULL);
	
	// test each triangle splitting against z == 0.0
	uint_fast32_t	i, count = data->count;
	for (i = 0; i < count; i++)
	{
		bool done_tri = false;
		Vector v0 = data->triangles[i].v[0];
		Vector v1 = data->triangles[i].v[1];
		Vector v2 = data->triangles[i].v[2];
		
		if (v0.z >= 0.0f && v1.z >= 0.0f && v2.z >= 0.0f)
		{
			AddTriangle(dPlus, data->triangles[i]);
			done_tri = true;
		}
		else if (v0.z <= 0.0f && v1.z <= 0.0f && v2.z <= 0.0f)
		{
			AddTriangle(dMinus, data->triangles[i]);
			done_tri = true;
		}
		if (!done_tri)	// triangle must cross z == 0.0
		{
			OOScalar i01, i12, i20;
			
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
			if (v0.z == 0.0f)
			{
				if (v1.z > 0)
				{
					AddTriangle(dPlus, make_triangle(v0, v1, v12));
					AddTriangle(dMinus, make_triangle(v0, v12, v2));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v0, v1, v12));
					AddTriangle(dPlus, make_triangle(v0, v12, v2));
				}
			}
			if (v1.z == 0.0f)
			{
				if (v2.z > 0)
				{
					AddTriangle(dPlus, make_triangle(v1, v2, v20));
					AddTriangle(dMinus, make_triangle(v1, v20, v0));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v1, v2, v20));
					AddTriangle(dPlus, make_triangle(v1, v20, v0));
				}
			}
			if (v2.z == 0.0f)
			{
				if (v0.z > 0)
				{
					AddTriangle(dPlus, make_triangle(v2, v0, v01));
					AddTriangle(dMinus, make_triangle(v2, v01, v1));
				}
				else
				{
					AddTriangle(dMinus, make_triangle(v2, v0, v01));
					AddTriangle(dPlus, make_triangle(v2, v01, v1));
				}
			}
			
			if (v0.z > 0.0f && v1.z > 0.0f && v2.z < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v0, v12, v20));
				AddTriangle(dPlus, make_triangle(v0, v1, v12));
				AddTriangle(dMinus, make_triangle(v20, v12, v2));
			}
			
			if (v0.z > 0.0f && v1.z < 0.0f && v2.z > 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v2, v01, v12));
				AddTriangle(dPlus, make_triangle(v2, v0, v01));
				AddTriangle(dMinus, make_triangle(v12, v01, v1));
			}
			
			if (v0.z > 0.0f && v1.z < 0.0f && v2.z < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v20, v0, v01));
				AddTriangle(dMinus, make_triangle(v2, v20, v1));
				AddTriangle(dMinus, make_triangle(v20, v01, v1));
			}
			
			if (v0.z < 0.0f && v1.z > 0.0f && v2.z > 0.0f)
			{
				AddTriangle(dMinus, make_triangle(v01, v20, v0));
				AddTriangle(dPlus, make_triangle(v1, v20, v01));
				AddTriangle(dPlus, make_triangle(v1, v2, v20));
			}
			
			if (v0.z < 0.0f && v1.z > 0.0f && v2.z < 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v01, v1, v12));
				AddTriangle(dMinus, make_triangle(v0, v01, v2));
				AddTriangle(dMinus, make_triangle(v01, v12, v2));
			}
			
			if (v0.z < 0.0f && v1.z < 0.0f && v2.z > 0.0f)
			{
				AddTriangle(dPlus, make_triangle(v12, v2, v20));
				AddTriangle(dMinus, make_triangle(v1, v12, v0));
				AddTriangle(dMinus, make_triangle(v12, v20, v0));
			}
		}
	}
	TranslateGeometryZ(dPlus, -z);
	TranslateGeometryZ(dMinus, z);
}


/*
	void AddTriangle_slow(GeometryData *data, Triangle tri)
	
	Slow path for AddTriangle(). Ensure that there is enough space to add a
	triangle, then actually add it.
	
	If no memory has been allocated yet, capacity is
	kOOMeshToOctreeConverterSmallDataCapacity, triangles points at smallData
	and pendingCapacity is the capacity passed to InitGeometryData(). Otherwise,
	triangles is a malloced pointer.
	
	This is marked noinline so that the fast path in AddTriangle() can be
	inlined. Without the attribute, clang (and probably gcc too) will inline
	AddTriangles_slow() into AddTriangle() (because it only has one call site),
	making AddTriangle() too heavy to inline.
*/
static NO_INLINE_FUNC void AddTriangle_slow(GeometryData *data, Triangle tri)
{
	NSCParameterAssert(data != NULL);
	NSCParameterAssert(data->count == data->capacity);
	
	if (data->capacity == kOOMeshToOctreeConverterSmallDataCapacity)
	{
		data->capacity = MAX(data->pendingCapacity, (uint_fast32_t)kOOMeshToOctreeConverterSmallDataCapacity * 2);
		data->triangles = malloc(data->capacity * sizeof(Triangle));
		memcpy(data->triangles, data->smallData, sizeof data->smallData);
	}
	else
	{
		// create more space by doubling the capacity of this geometry.
		data->capacity = 1 + data->capacity * 2;
		data->triangles = realloc(data->triangles, data->capacity * sizeof(Triangle));
		
		// N.b.: we leak here if realloc() failed, but we're about to abort anyway.
	}
	
	if (EXPECT_NOT(data->triangles == NULL))
	{
		OOLog(kOOLogAllocationFailure, @"!!!!! Ran out of memory to allocate more geometry!");
		exit(EXIT_FAILURE);
	}
	
	data->triangles[data->count++] = tri;
}
