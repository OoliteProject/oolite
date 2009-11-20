#import "icosmesh.h"

@class JAVertexSet, JAIcosTriangle;


@interface JAIcosMesh: NSObject
{
@private
	JAVertexSet				*_vertexSet;
	NSMutableArray			*_indices;
	NSUInteger				_maxIndex;
}

// Vertex set may optionally be specified, so one can be shared between multiple meshes.
+ (id) meshWithVertexSet:(JAVertexSet *)vertexSet;
- (id) initWithVertexSet:(JAVertexSet *)vertexSet;

@property (readonly) JAVertexSet *vertexSet;
@property (readonly) NSUInteger faceCount;
@property (readonly) NSUInteger maxIndex;

- (void) addTriangle:(JAIcosTriangle *)triangle;
- (void) addTriangles:(NSArray *)triangles;

- (NSArray *) indexArray;	// NSArray of faceCount * 3 NSNumbers, being indices into vertexSet.

@end
