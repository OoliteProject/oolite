/*

OOPolygonSprite.m
Oolite


Copyright (C) 2009 Jens Ayton

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
	strips, we convert those to a single triangle soup since the primitives are
	unlikely to be large enough that using multiple primitives would be a win.
	
	Uniquing vertices and using indices, and using the same vertex array for
	outline and filled mode, would in principle be more efficient, but not
	worth the added complexity in the preprocessing given the simplicity of
	the icons we're likely to encounter.
*/

#undef OO_CHECK_GL_HEAVY
#define OO_CHECK_GL_HEAVY 0

#import "OOPolygonSprite.h"
#import "OOCollectionExtractors.h"
#import "OOMacroOpenGL.h"


#define TESS_TOLERANCE 0.05	// Feature merging factor: higher values merge more features with greater chance of distortion.


@interface OOPolygonSprite (Private)

- (BOOL) loadPolygons:(NSArray *)dataArray;

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
	NSString		*name;
#endif
} TessPolygonData;


static BOOL GrowTessPolygonData(TessPolygonData *data, size_t capacityHint);	// Returns true if capacity grew by at least one.
static BOOL AppendVertex(TessPolygonData *data, NSPoint vertex);


static void APIENTRY SolidBeginCallback(GLenum type, void *polygonData);
static void APIENTRY SolidVertexCallback(void *vertexData, void *polygonData);
static void APIENTRY SolidEndCallback(void *polygonData);

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
		if (![self loadPolygons:dataArray])
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
#ifndef NDEBUG
	DESTROY(_name);
#endif
	
	free(_solidData);
	
	[super dealloc];
}


#ifndef NDEBUG
- (NSString *) descriptionComponents
{
	return _name;
}
#endif


- (void) drawFilled
{
	OO_ENTER_OPENGL();
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glVertexPointer(2, GL_FLOAT, 0, _solidData));
	OOGL(glDrawArrays(GL_TRIANGLES, 0, _solidCount));
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
}


- (BOOL) loadPolygons:(NSArray *)dataArray
{
	NSParameterAssert(dataArray != nil);
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	GLUtesselator *tesselator = NULL;
	
	TessPolygonData polygonData;
	memset(&polygonData, 0, sizeof polygonData);
	polygonData.OK = YES;
#ifndef NDEBUG
	polygonData.name = _name;
#endif
#if !OO_DEBUG
	// For efficiency, grow to more than big enough for most cases to avoid regrowing.
	if (!GrowTessPolygonData(&polygonData, 100))
	{
		polygonData.OK = NO;
		goto END;
	}
#endif
	
	tesselator = gluNewTess();
	if (tesselator == NULL)
	{
		polygonData.OK = NO;
		goto END;
	}
	
	gluTessCallback(tesselator, GLU_TESS_BEGIN_DATA, SolidBeginCallback);
	gluTessCallback(tesselator, GLU_TESS_VERTEX_DATA, SolidVertexCallback);
	gluTessCallback(tesselator, GLU_TESS_END_DATA, SolidEndCallback);
	gluTessCallback(tesselator, GLU_TESS_ERROR_DATA, ErrorCallback);
	gluTessProperty(tesselator, GLU_TESS_TOLERANCE, TESS_TOLERANCE);
	
	gluTessBeginPolygon(tesselator, &polygonData);
	
	OOUInteger contourCount = [dataArray count], contourIndex;
	for (contourIndex = 0; contourIndex < contourCount && polygonData.OK; contourIndex++)
	{
		NSArray *contour = [dataArray oo_arrayAtIndex:contourIndex];
		if (contour == nil)
		{
			polygonData.OK = NO;
			break;
		}
		
		OOUInteger vertexCount = [contour count] / 2, vertexIndex;
		if (vertexCount > 2)
		{
			gluTessBeginContour(tesselator);
			
			for (vertexIndex = 0; vertexIndex < vertexCount && polygonData.OK; vertexIndex++)
			{
				GLdouble vert[3] =
				{
					[contour oo_doubleAtIndex:vertexIndex * 2],
					[contour oo_doubleAtIndex:vertexIndex * 2 + 1],
					0.0
				};
				
				/*	The third parameter to gluTessVertex() is the data
					actually passed to our vertex callback. Since the vertex
					callback isn't called until later, each vertex's data needs
					to have an independent existence. We pack them into
					NSValues here and let NSAutoReleasepool clean up
					afterwards.
				*/
				NSPoint p = { vert[0], vert[1] };
				NSValue *vertValue = [NSValue valueWithPoint:p];
				gluTessVertex(tesselator, vert, vertValue);
			}
			
			gluTessEndContour(tesselator);
		}
	}
	
	gluTessEndPolygon(tesselator);
	
	if (polygonData.OK)
	{
		_solidCount = polygonData.count;
		_solidData = realloc(polygonData.data, polygonData.count * sizeof (GLfloat) * 2);
		if (_solidData != NULL)  polygonData.data = NULL;
		else
		{
			_solidData = polygonData.data;
			if (_solidData == NULL)  polygonData.OK = NO;
		}
	}
	
END:
	free(polygonData.data);
	gluDeleteTess(tesselator);
	[pool release];
	return polygonData.OK;
}

@end


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


static void APIENTRY SolidBeginCallback(GLenum type, void *polygonData)
{
	TessPolygonData *data = polygonData;
	NSCParameterAssert(data != NULL);
	
	data->mode = type;
	data->vCount = 0;
}


static void APIENTRY SolidVertexCallback(void *vertexData, void *polygonData)
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
			OOLog(@"tesselate.vertex.tri", @"%u: %@", vCount, NSStringFromPoint(vertex));
			break;
			
		case GL_TRIANGLE_FAN:
			if (vCount == 0)  data->pending0 = vertex;
			else if (vCount == 1)  data->pending1 = vertex;
			else
			{
				data->OK = AppendVertex(data, data->pending0) &&
						   AppendVertex(data, data->pending1) &&
						   AppendVertex(data, vertex);
				OOLog(@"tesselate.vertex.fan", @"%u: (%@ %@) %@", vCount, NSStringFromPoint(data->pending0), NSStringFromPoint(data->pending1), NSStringFromPoint(vertex));
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
			OOLog(@"tesselate.vertex.strip", @"%u: (%@ %@) %@", vCount, NSStringFromPoint(data->pending0), NSStringFromPoint(data->pending1), NSStringFromPoint(vertex));
				if ((vCount % 2) == 0)  data->pending0 = vertex;
				else  data->pending1 = vertex;
			}
			break;
			
		default:
#ifndef NDEBUG
			OOLog(@"polygonSprite.tesselate.error", @"Unexpected tesselator primitive mode %u.", data->mode);
#endif
			data->OK = NO;
	}
}


static void APIENTRY SolidEndCallback(void *polygonData)
{
	TessPolygonData *data = polygonData;
	NSCParameterAssert(data != NULL);
	
	data->mode = 0;
	data->vCount = 0;
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
