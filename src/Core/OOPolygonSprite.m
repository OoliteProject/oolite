/*

OOPolygonSprite.m
Oolite


Copyright (C) 2009-2012 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

/*	Implementation note:
	
	The polygon data is tesselated (on object creation) using a GLU tesselator.
	Although GLU produces a mix of triangles, triangle fans and triangle
	strips, we convert those to a single triangle soup since the polygons are
	unlikely to be large enough that using multiple primitives would be a win.
	
	Uniquing vertices and using indices, and using the same vertex array for
	outline and filled mode, would in principle be more efficient, but not
	worth the added complexity in the preprocessing given the simplicity of
	the icons we're likely to encounter.
*/

#import "OOPolygonSprite.h"
#import "OOCollectionExtractors.h"
#import "OOMacroOpenGL.h"
#import "OOMaths.h"
#import "OOPointMaths.h"
#import "OOGraphicsResetManager.h"


#ifndef APIENTRY
#define APIENTRY
#endif


#define kCosMitreLimit 0.866f			// Approximately cos(30 deg)


@interface OOPolygonSprite (Private) <OOGraphicsResetClient>

- (BOOL) loadPolygons:(NSArray *)dataArray outlineWidth:(float)outlineWidth;

@end


typedef struct
{
	GLfloat			*data;
	size_t			count;				// Number of vertices in use, i.e. half of number of data elements used.
	size_t			capacity;			// Half of number of floats there is space for in data.
	GLenum			mode;				// Current primitive mode.
	size_t			vCount;				// Number of vertices so far in primitive.
	NSPoint			pending0, pending1;	// Used for splitting GL_TRIANGLE_STRIP/GL_TRIANGLE_FAN primitives.
	BOOL			OK;					// Set to false to indicate error.
#ifndef NDEBUG
	BOOL			generatingOutline;
	unsigned		svgID;
	NSString		*name;
	NSMutableString	*debugSVG;
#endif
} TessPolygonData;


static NSArray *DataArrayToPoints(TessPolygonData *data, NSArray *dataArray);
static NSArray *BuildOutlineContour(NSArray *dataArray, GLfloat width, BOOL inner);

static void SubmitVertices(GLUtesselator *tesselator, TessPolygonData *polygonData, NSArray *contour);

static BOOL GrowTessPolygonData(TessPolygonData *data, size_t capacityHint);	// Returns true if capacity grew by at least one.
static BOOL AppendVertex(TessPolygonData *data, NSPoint vertex);

#ifndef NDEBUG
static void SVGDumpBegin(TessPolygonData *data);
static void SVGDumpEnd(TessPolygonData *data);
static void SVGDumpBeginGroup(TessPolygonData *data, NSString *name);
static void SVGDumpEndGroup(TessPolygonData *data);
static void SVGDumpAppendBaseContour(TessPolygonData *data, NSArray *points);
static void SVGDumpBeginPrimitive(TessPolygonData *data);
static void SVGDumpEndPrimitive(TessPolygonData *data);
static void SVGDumpAppendTriangle(TessPolygonData *data, NSPoint v0, NSPoint v1, NSPoint v2);
#else
#define SVGDumpBegin(data) do {} while (0)
#define SVGDumpEnd(data) do {} while (0)
#define SVGDumpBeginGroup(data, name) do {} while (0)
#define SVGDumpEndGroup(data) do {} while (0)
#define SVGDumpAppendBaseContour(data, points) do {} while (0)
#define SVGDumpBeginPrimitive(data) do {} while (0)
#define SVGDumpEndPrimitive(data) do {} while (0)
#define SVGDumpAppendTriangle(data, v0, v1, v2) do {} while (0)
#endif


static void APIENTRY TessBeginCallback(GLenum type, void *polygonData);
static void APIENTRY TessVertexCallback(void *vertexData, void *polygonData);
static void APIENTRY TessCombineCallback(GLdouble	coords[3], void *vertexData[4], GLfloat weight[4], void **outData, void *polygonData);
static void APIENTRY TessEndCallback(void *polygonData);

static void APIENTRY ErrorCallback(GLenum error, void *polygonData);


@implementation OOPolygonSprite

- (id) initWithDataArray:(NSArray *)dataArray outlineWidth:(GLfloat)outlineWidth name:(NSString *)name
{
	if ((self = [super init]))
	{
#ifndef NDEBUG
		_name = [name copy];
#endif
		
		if ([dataArray count] == 0)
		{
			[self release];
			return nil;
		}
		
		// Normalize data to array-of-arrays form.
		if (![[dataArray objectAtIndex:0] isKindOfClass:[NSArray class]])
		{
			dataArray = [NSArray arrayWithObject:dataArray];
		}
		if (![self loadPolygons:dataArray outlineWidth:outlineWidth])
		{
			[self release];
			return nil;
		}
		
		[[OOGraphicsResetManager sharedManager] registerClient:self];
	}
	
	return self;
}


- (void) dealloc
{
	[[OOGraphicsResetManager sharedManager] unregisterClient:self];
	
#ifndef NDEBUG
	DESTROY(_name);
#endif
	free(_solidData);
	free(_outlineData);
	
	[super dealloc];
}


#ifndef NDEBUG
- (NSString *) descriptionComponents
{
	return _name;
}
#endif


- (void) drawWithData:(GLfloat *)data count:(size_t)count VBO:(GLuint *)vbo
{
	if (count == 0)  return;
	NSParameterAssert(vbo != NULL && data != NULL);
	
	OO_ENTER_OPENGL();
	
#if OO_USE_VBO
	BOOL useVBO = [[OOOpenGLExtensionManager sharedManager] vboSupported];
	
	if (useVBO)
	{
		if (*vbo == 0)
		{
			OOGL(glGenBuffersARB(1, vbo));
			if (*vbo != 0)
			{
				OOGL(glBindBufferARB(GL_ARRAY_BUFFER, *vbo));
				OOGL(glBufferDataARB(GL_ARRAY_BUFFER, sizeof (GLfloat) * count * 2, data, GL_STATIC_DRAW));
			}
		}
		else
		{
			OOGL(glBindBufferARB(GL_ARRAY_BUFFER, *vbo));
		}
		if (*vbo != 0)  data = NULL;	// Must pass NULL pointer to glVertexPointer to use VBO.
	}
#endif
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glVertexPointer(2, GL_FLOAT, 0, data));
	OOGL(glDrawArrays(GL_TRIANGLES, 0, count));
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	
#if OO_USE_VBO
	if (useVBO)  OOGL(glBindBufferARB(GL_ARRAY_BUFFER, 0));
#endif
}


- (void) drawFilled
{
#if !OO_USE_VBO
	GLuint _solidVBO;	// Unusued
#endif
	
	[self drawWithData:_solidData count:_solidCount VBO:&_solidVBO];
}


- (void) drawOutline
{
#if !OO_USE_VBO
	GLuint _outlineVBO;	// Unusued
#endif
	
	[self drawWithData:_outlineData count:_outlineCount VBO:&_outlineVBO];
}


- (void)resetGraphicsState
{
#if OO_USE_VBO
	OO_ENTER_OPENGL();
	
	if (_solidVBO != 0)  glDeleteBuffersARB(1, &_solidVBO);
	if (_outlineVBO != 0)  glDeleteBuffersARB(1, &_outlineVBO);
	
	_solidVBO = 0;
	_outlineVBO = 0;
#endif
}


// FIXME: this method is absolutely horrible.
- (BOOL) loadPolygons:(NSArray *)dataArray outlineWidth:(float)outlineWidth
{
	NSParameterAssert(dataArray != nil);
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	GLUtesselator *tesselator = NULL;
	
	TessPolygonData polygonData;
	memset(&polygonData, 0, sizeof polygonData);
	polygonData.OK = YES;
#ifndef NDEBUG
	polygonData.name = _name;
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"polygon-sprite-dump-svg"])  SVGDumpBegin(&polygonData);
#endif
	
	// For efficiency, grow to more than big enough for most cases to avoid regrowing.
	if (!GrowTessPolygonData(&polygonData, 100))
	{
		polygonData.OK = NO;
		goto END;
	}
	
	tesselator = gluNewTess();
	if (tesselator == NULL)
	{
		polygonData.OK = NO;
		goto END;
	}
	
	dataArray = DataArrayToPoints(&polygonData, dataArray);
	
	/*** Tesselate polygon fill ***/
	gluTessCallback(tesselator, GLU_TESS_BEGIN_DATA, TessBeginCallback);
	gluTessCallback(tesselator, GLU_TESS_VERTEX_DATA, TessVertexCallback);
	gluTessCallback(tesselator, GLU_TESS_END_DATA, TessEndCallback);
	gluTessCallback(tesselator, GLU_TESS_ERROR_DATA, ErrorCallback);
	gluTessCallback(tesselator, GLU_TESS_COMBINE_DATA, TessCombineCallback);
	
	gluTessBeginPolygon(tesselator, &polygonData);
	SVGDumpBeginGroup(&polygonData, @"Fill");
	
	NSUInteger contourCount = [dataArray count], contourIndex;
	for (contourIndex = 0; contourIndex < contourCount && polygonData.OK; contourIndex++)
	{
		NSArray *contour = [dataArray oo_arrayAtIndex:contourIndex];
		if (contour == nil)
		{
			polygonData.OK = NO;
			break;
		}
		
		SubmitVertices(tesselator, &polygonData, contour);
	}
	
	gluTessEndPolygon(tesselator);
	SVGDumpEndGroup(&polygonData);
	
	if (polygonData.OK)
	{
		_solidCount = polygonData.count;
		
		if (_solidCount != 0)
		{
			_solidData = realloc(polygonData.data, polygonData.count * sizeof (GLfloat) * 2);
			if (_solidData != NULL)  polygonData.data = NULL;	// realloc succeded.
			else
			{
				// Unlikely, but legal: realloc failed to shrink buffer.
				_solidData = polygonData.data;
				if (_solidData == NULL)  polygonData.OK = NO;
			}
		}
		else
		{
			// Empty polygon.
			_solidData = NULL;
		}
	}
	if (!polygonData.OK)  goto END;
	
	/*** Tesselate polygon outline ***/
	gluDeleteTess(tesselator);
	tesselator = gluNewTess();
	if (tesselator == NULL)
	{
		polygonData.OK = NO;
		goto END;
	}
	
	polygonData.count = 0;
	polygonData.capacity = 0;
	if (!GrowTessPolygonData(&polygonData, 100))
	{
		polygonData.OK = NO;
		goto END;
	}
#ifndef NDEBUG
	polygonData.generatingOutline = YES;
#endif
	
	gluTessCallback(tesselator, GLU_TESS_BEGIN_DATA, TessBeginCallback);
	gluTessCallback(tesselator, GLU_TESS_VERTEX_DATA, TessVertexCallback);
	gluTessCallback(tesselator, GLU_TESS_END_DATA, TessEndCallback);
	gluTessCallback(tesselator, GLU_TESS_ERROR_DATA, ErrorCallback);
	gluTessCallback(tesselator, GLU_TESS_COMBINE_DATA, TessCombineCallback);
	gluTessProperty(tesselator, GLU_TESS_WINDING_RULE, GLU_TESS_WINDING_POSITIVE);
	
	gluTessBeginPolygon(tesselator, &polygonData);
	SVGDumpBeginGroup(&polygonData, @"Outline");
	
	outlineWidth *= 0.5f; // Half the width in, half the width out.
	contourCount = [dataArray count];
	for (contourIndex = 0; contourIndex < contourCount && polygonData.OK; contourIndex++)
	{
		NSArray *contour = [dataArray oo_arrayAtIndex:contourIndex];
		if (contour == nil)
		{
			polygonData.OK = NO;
			break;
		}
	
		SubmitVertices(tesselator, &polygonData, BuildOutlineContour(contour, outlineWidth, NO));
		SubmitVertices(tesselator, &polygonData, BuildOutlineContour(contour, outlineWidth, YES));
	}
	
	gluTessEndPolygon(tesselator);
	SVGDumpEndGroup(&polygonData);
	
	if (polygonData.OK)
	{
		if (polygonData.count != 0)
		{
			_outlineCount = polygonData.count;
			_outlineData = realloc(polygonData.data, polygonData.count * sizeof (GLfloat) * 2);
			if (_outlineData != NULL)  polygonData.data = NULL;	// realloc succeded.
			else
			{
				// Unlikely, but legal: realloc failed to shrink buffer.
				_outlineData = polygonData.data;
				if (_outlineData == NULL)  polygonData.OK = NO;
			}
		}
		else
		{
			// Empty polygon.
			_outlineCount = 0;
			_outlineData = NULL;
		}
	}
	
END:
	SVGDumpEnd(&polygonData);
	free(polygonData.data);
	gluDeleteTess(tesselator);
	[pool release];
#ifndef NDEBUG
	DESTROY(polygonData.debugSVG);
#endif
	return polygonData.OK;
}

@end


static void SubmitVertices(GLUtesselator *tesselator, TessPolygonData *polygonData, NSArray *contour)
{
	NSUInteger vertexCount = [contour count], vertexIndex;
	if (vertexCount > 2)
	{
		gluTessBeginContour(tesselator);
		
		for (vertexIndex = 0; vertexIndex < vertexCount && polygonData->OK; vertexIndex++)
		{
			NSValue *pointValue = [contour objectAtIndex:vertexIndex];
			NSPoint p = [pointValue pointValue];
			GLdouble vert[3] = { p.x, p.y, 0.0 };
			
			gluTessVertex(tesselator, vert, pointValue);
		}
		
		gluTessEndContour(tesselator);
	}
}


static NSArray *DataArrayToPoints(TessPolygonData *data, NSArray *dataArray)
{
	/*	This converts an icon definition in the form of an array of array of
		numbers to internal data in the form of an array of arrays of NSValues
		containing NSPoint data. In addition to repacking the data, it performs
		the following data processing:
		  * Sequences of duplicate vertices are removed (including across the
		    beginning and end, in case of manually closed contours).
		  * Vertices containing nans or infinities are skipped, Just In Case.
		  * The signed area of each contour is calculated; if it is negative,
		    the contour is clockwise, and we need to flip it.
	*/
	
	SVGDumpBeginGroup(data, @"Base contours");
	
	NSUInteger polyIter, polyCount = [dataArray count];
	NSArray *subArrays[polyCount];
	
	for (polyIter = 0; polyIter < polyCount; polyIter++)
	{
		NSArray *polyDef = [dataArray objectAtIndex:polyIter];
		NSUInteger vertIter, vertCount = [polyDef count] / 2;
		NSMutableArray *newPolyDef = [NSMutableArray arrayWithCapacity:vertCount];
		CGFloat area = 0;
		
		CGFloat oldX = [polyDef oo_doubleAtIndex:(vertCount -1) * 2];
		CGFloat oldY = [polyDef oo_doubleAtIndex:(vertCount -1) * 2 + 1];
		
		for (vertIter = 0; vertIter < vertCount; vertIter++)
		{
			CGFloat x = [polyDef oo_doubleAtIndex:vertIter * 2];
			CGFloat y = [polyDef oo_doubleAtIndex:vertIter * 2 + 1];
			
			// Skip bad or duplicate vertices.
			if (x == oldX && y == oldY)  continue;
			if (isnan(x) || isnan(y))  continue;
			if (!isfinite(x) || !isfinite(y))  continue;
			
			area += x * oldY - oldX * y;
			
			oldX = x;
			oldY = y;
			
			[newPolyDef addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
		}
		
		// Eliminate duplicates at ends - the initialization of oldX and oldY will catch one pair, but not extra-silly cases.
		while ([newPolyDef count] > 1 && [[newPolyDef objectAtIndex:0] isEqual:[newPolyDef lastObject]])
		{
			[newPolyDef removeLastObject];
		}
		
		if (area >= 0)
		{
			subArrays[polyIter] = newPolyDef;
		}
		else
		{
			subArrays[polyIter] = [[newPolyDef reverseObjectEnumerator] allObjects];
		}
		
		SVGDumpAppendBaseContour(data, subArrays[polyIter]);
	}
	
	SVGDumpEndGroup(data);
	return [NSArray arrayWithObjects:subArrays count:polyCount];
}


static NSArray *BuildOutlineContour(NSArray *dataArray, GLfloat width, BOOL inner)
{
	NSUInteger i, count = [dataArray count];
	if (count < 2)  return dataArray;
	
	/*
		Generate inner or outer boundary for a contour, offset by the specified
		width inwards/outwards from the line. At anticlockwise (convex) corners
		sharper than acos(kCosMitreLimit), the corner is mitred, i.e. an
		additional line segment is generated so the outline doesn't protrude
		arbitratrily far.
		
		Overview of the maths:
		For each vertex, we consider a normalized vector A from the previous
		vertex and a normalized vector B to the next vertex. (These are always
		defined since the polygons are closed.)
		
		The dot product of A and B is the cosine of the angle, which we compare
		to kCosMitreLimit to determine mitreing. If the dot product is exactly
		1, the vectors are antiparallel and we have a cap; the mitreing case
		handles this implicitly. (The non-mitreing case would result in a
		divide-by-zero.)
		
		Non-mitreing case:
			To position the vertex, we need a vector N normal to the corner.
			We observe that A + B is tangent to the corner, and a 90 degree
			rotation in 2D is trivial. The offset along this line is
			proportional to the secant of the angle between N and the 90 degree
			rotation of A (or B; the angle is by definition the same), or
			width / (N dot rA).
			Since both N and rA are rotated by ninety degrees in the same
			direction, we can cut out both rotations (i.e., using the tangent
			and A) and get the same result.
			
		Mitreing case:
			The two new vertices are the original vertex offset by scale along
			the ninety-degree rotation of A and B respectively.
	*/
	
	NSPoint prev, current, next;
	if (inner)
	{
		prev = [[dataArray objectAtIndex:0] pointValue];
		current = [[dataArray objectAtIndex:count -1] pointValue];
		next = [[dataArray objectAtIndex:count - 2] pointValue];	
	}
	else
	{
		prev = [[dataArray objectAtIndex:count - 1] pointValue];
		current = [[dataArray objectAtIndex:0] pointValue];
		next = [[dataArray objectAtIndex:1] pointValue];
	}
	
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
	
	for (i = 0; i < count; i++)
	{
		NSPoint a = PtNormal(PtSub(current, prev));
		NSPoint b = PtNormal(PtSub(next, current));
		
		CGFloat dot = PtDot(a, b);
		BOOL clockwise = PtCross(a, b) < 0.0f;
		
		if (-dot < kCosMitreLimit || !clockwise)
		{
			// Non-mitreing case.
			NSPoint t = PtNormal(PtAdd(a, b));
			NSPoint v = PtScale(PtRotACW(t), width / PtDot(t, a));
			
			if (!isnan(v.x) && !isnan(v.y))
			{
				[result addObject:[NSValue valueWithPoint:PtAdd(v, current)]];
			}
		}
		else
		{
			// Mitreing case.
			NSPoint v1 = PtScale(PtAdd(PtRotACW(a), a), width);
			NSPoint v2 = PtScale(PtSub(PtRotACW(b), b), width);
			
			if (!isnan(v1.x) && !isnan(v1.y))
			{
				[result addObject:[NSValue valueWithPoint:PtAdd(v1, current)]];
			}
			if (!isnan(v2.x) && !isnan(v2.y))
			{
				[result addObject:[NSValue valueWithPoint:PtAdd(v2, current)]];
			}
		}
		
		prev = current;
		current = next;
		
		if (inner)
		{
			next = [[dataArray objectAtIndex:(count * 2 - 3 - i) % count] pointValue];
		}
		else
		{
			next = [[dataArray objectAtIndex:(i + 2) % count] pointValue];
		}
	}
	
	return result;
}


static BOOL GrowTessPolygonData(TessPolygonData *data, size_t capacityHint)
{
	NSCParameterAssert(data != NULL);
	
	size_t minCapacity = data->capacity + 1;
	size_t desiredCapacity = MAX(capacityHint, minCapacity);
	size_t newCapacity = 0;
	GLfloat *newData = realloc(data->data, desiredCapacity * sizeof (GLfloat) * 2);
	if (newData != NULL)
	{
		newCapacity = desiredCapacity;
	}
	else
	{
		desiredCapacity = minCapacity;
		newData = realloc(data->data, desiredCapacity * sizeof (GLfloat) * 2);
		if (newData != NULL)  newCapacity = desiredCapacity;
	}
	
	if (newData == NULL)  return NO;
	
	NSCAssert(newCapacity > data->capacity, @"Buffer regrow logic error");
	
	data->data = newData;
	data->capacity = newCapacity;
	return YES;
}


static BOOL AppendVertex(TessPolygonData *data, NSPoint vertex)
{
	NSCParameterAssert(data != NULL);
	
	if (data->capacity == data->count && !GrowTessPolygonData(data, data->capacity * 2))  return NO;
	
	data->data[data->count * 2] = vertex.x;
	data->data[data->count * 2 + 1] = vertex.y;
	data->count++;
	return YES;
}


static void APIENTRY TessBeginCallback(GLenum type, void *polygonData)
{
	TessPolygonData *data = polygonData;
	NSCParameterAssert(data != NULL);
	
	data->mode = type;
	data->vCount = 0;
	
	SVGDumpBeginPrimitive(data);
}


static void APIENTRY TessVertexCallback(void *vertexData, void *polygonData)
{
	TessPolygonData *data = polygonData;
	NSValue *vertValue = vertexData;
	NSCParameterAssert(vertValue != NULL && data != NULL);
	if (!data->OK)  return;
	
	NSPoint p = [vertValue pointValue];
	NSPoint vertex = { p.x, p.y };
	size_t vCount = data->vCount++;
	
	switch (data->mode)
	{
		case GL_TRIANGLES:
			data->OK = AppendVertex(data, vertex);
#ifndef NDEBUG
			switch (vCount % 3)
			{
				case 0:
					data->pending0 = vertex;
					break;
					
				case 1:
					data->pending1 = vertex;
					break;
					
				case 2:
					SVGDumpAppendTriangle(data, data->pending0, data->pending1, vertex);
			}
#endif
			break;
			
		case GL_TRIANGLE_FAN:
			if (vCount == 0)  data->pending0 = vertex;
			else if (vCount == 1)  data->pending1 = vertex;
			else
			{
				data->OK = AppendVertex(data, data->pending0) &&
						   AppendVertex(data, data->pending1) &&
						   AppendVertex(data, vertex);
				SVGDumpAppendTriangle(data, data->pending0, data->pending1, vertex);
				data->pending1 = vertex;
			}
			break;
			
		case GL_TRIANGLE_STRIP:
			if (vCount == 0)  data->pending0 = vertex;
			else if (vCount == 1)  data->pending1 = vertex;
			else
			{
				/*	In order to produce consistent winding, the vertex->triangle
					order for GL_TRIANGLE_STRIP is:
					0, 1, 2
					2, 1, 3
					2, 3, 4
					4, 3, 5
					4, 5, 6
					6, 5, 7
					6, 7, 8
					
					Vertices 0 and 1 are special-cased above, and the first
					time we get here it's time for the first triangle, which
					is pending0, pending1, v. v (i.e., vertex 2) then goes into
					pending0.
					For the second triangle, the triangle is again pending0,
					pending1, v, and we then put v (i.e., vertex 3) into
					pending1.
					The third triangle follows the same pattern as the first,
					and the fourthe the same as the second.
					In other words, after storing each triangle, v goes into
					pending0 for even vertex indicies, and pending1 for odd
					vertex indices.
				 */
				data->OK = AppendVertex(data, data->pending0) &&
						   AppendVertex(data, data->pending1) &&
						   AppendVertex(data, vertex);
				SVGDumpAppendTriangle(data, data->pending0, data->pending1, vertex);
				if ((vCount % 2) == 0)  data->pending0 = vertex;
				else  data->pending1 = vertex;
			}
			break;
			
		default:
			OOLog(@"polygonSprite.tesselate.error", @"Unexpected tesselator primitive mode %u.", data->mode);
			data->OK = NO;
	}
}


static void APIENTRY TessCombineCallback(GLdouble	coords[3], void *vertexData[4], GLfloat weight[4], void **outData, void *polygonData)
{
	NSPoint point = { coords[0], coords[1] };
	*outData = [NSValue valueWithPoint:point];
}


static void APIENTRY TessEndCallback(void *polygonData)
{
	TessPolygonData *data = polygonData;
	NSCParameterAssert(data != NULL);
	
	data->mode = 0;
	data->vCount = 0;
	
	SVGDumpEndPrimitive(data);
}


static void APIENTRY ErrorCallback(GLenum error, void *polygonData)
{
	TessPolygonData *data = polygonData;
	NSCParameterAssert(data != NULL);
	
	NSString *name = @"";
#ifndef NDEBUG
	name = [NSString stringWithFormat:@" \"%@\"", data->name];
#endif
	
	char *errStr = (char *)gluErrorString(error);
	
	OOLog(@"polygonSprite.tesselate.error", @"Error %s (%u) while tesselating polygon%@.", errStr, error, name);
	data->OK = NO;
}

#ifndef NDEBUG
#import "ResourceManager.h"
#import "legacy_random.h"

static void SVGDumpBegin(TessPolygonData *data)
{
	DESTROY(data->debugSVG);
	data->debugSVG = [[NSMutableString alloc] initWithString:
	   @"<?xml version=\"1.0\" standalone=\"no\"?>\n"
		"<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" \"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n"
		"<svg viewBox=\"-5 -5 10 10\" version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\">\n"
		"\t<desc>Oolite polygon sprite debug dump.</desc>\n"
		"\t\n"
	];
}


static void SVGDumpEnd(TessPolygonData *data)
{
	if (data->debugSVG == nil)  return;
	
	[data->debugSVG appendString:@"</svg>\n"];
	[ResourceManager writeDiagnosticString:data->debugSVG toFileNamed:[NSString stringWithFormat:@"Polygon Sprites/%@.svg", data->name]];
	DESTROY(data->debugSVG);
}


static void SVGDumpBeginGroup(TessPolygonData *data, NSString *name)
{
	if (data->debugSVG == nil)  return;
	
	[data->debugSVG appendFormat:@"\t<g id=\"%@ %u\">\n", name, data->svgID++];
}


static void SVGDumpEndGroup(TessPolygonData *data)
{
	if (data->debugSVG == nil)  return;
	[data->debugSVG appendString:@"\t</g>\n"];	
}


static void SVGDumpAppendBaseContour(TessPolygonData *data, NSArray *points)
{
	if (data->debugSVG == nil)  return;
	
	NSString *groupName = [NSString stringWithFormat:@"contour %u", data->svgID++];
	[data->debugSVG appendFormat:@"\t\t<g id=\"%@\" stroke=\"#BBB\" fill=\"none\">\n\t\t<path stroke-width=\"0.05\" d=\"", groupName];
	
	NSUInteger i, count = [points count];
	for (i = 0; i < count; i++)
	{
		NSPoint p = [[points objectAtIndex:i] pointValue];
		[data->debugSVG appendFormat:@"%c %f %f ", (i == 0) ? 'M' : 'L', p.x, -p.y];
	}
	
	// Close and add a circle at the first vertex. (SVG has support for end markers, but this isn’t reliable across implementations.)
	NSPoint p = [[points objectAtIndex:0] pointValue];
	[data->debugSVG appendFormat:@"z\"/>\n\t\t\t<circle cx=\"%f\" cy=\"%f\" r=\"0.1\" fill=\"#BBB\" stroke=\"none\"/>\n\t\t</g>\n", p.x, -p.y];
}


static void SVGDumpBeginPrimitive(TessPolygonData *data)
{
	if (data->debugSVG == nil)  return;
	
	NSString *groupName = @"Unknown primitive";
	switch (data->mode)
	{
		case GL_TRIANGLES:
			groupName = @"Triangle soup";
			break;
			
		case GL_TRIANGLE_FAN:
			groupName = @"Triangle fan";
			break;
			
		case GL_TRIANGLE_STRIP:
			groupName = @"Triangle strip";
			break;
	}
	groupName = [groupName stringByAppendingFormat:@" %u", data->svgID++];
	
	// Pick random colour for the primitive.
	uint8_t red = (Ranrot() & 0x3F) + 0x20;
	uint8_t green = (Ranrot() & 0x3F) + 0x20;
	uint8_t blue = (Ranrot() & 0x3F) + 0x20;
	if (!data->generatingOutline)
	{
		red += 0x80;
		green += 0x80;
		blue += 0x80;
	}
	
	[data->debugSVG appendFormat:@"\t\t<g id=\"%@\" fill=\"#%2X%2X%2X\" fill-opacity=\"0.3\" stroke=\"%@\" stroke-width=\"0.01\">\n", groupName, red, green, blue, data->generatingOutline ? @"#060" : @"#008"];
}


static void SVGDumpEndPrimitive(TessPolygonData *data)
{
	if (data->debugSVG == nil)  return;
	[data->debugSVG appendString:@"\t\t</g>\n"];
}


static void SVGDumpAppendTriangle(TessPolygonData *data, NSPoint v0, NSPoint v1, NSPoint v2)
{
	if (data->debugSVG == nil)  return;
	[data->debugSVG appendFormat:@"\t\t\t<path d=\"M %f %f L %f %f L %f %f z\"/>\n", v0.x, -v0.y, v1.x, -v1.y, v2.x, -v2.y];
}
#endif
