#import "icosmesh.h"


@interface JAVertexSet: NSObject
{
@private
	NSMutableDictionary		*_indices;
	NSMutableArray			*_vertices;
}

- (NSUInteger) indexForVertex:(Vertex)vertex;
- (Vertex) vertexAtIndex:(NSUInteger)index;

@property (readonly) NSUInteger count;

- (NSArray *) positionArray;	// Array of 3 * count numbers representing vertex positions
#if OUTPUT_BINORMALS
- (NSArray *) binormalArray;	// Array of 3 * count numbers representing binormals
#endif
- (NSArray *) texCoordArray;	// Array of 2 * count numbers representing texture coordinates

@end
