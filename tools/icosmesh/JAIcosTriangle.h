//
//  JAIcosTriangle.h
//  icosmesh
//
//  Created by Jens Ayton on 2009-11-18.
//  Copyright 2009 Jens Ayton. All rights reserved.
//

#import "icosmesh.h"


@interface JAIcosTriangle: NSObject
{
@private
	Vertex					_vertices[3];
}

// Note: order is not guaranteed to be maintained.
+ (id) triangleWithVectorA:(Vector)a b:(Vector)b c:(Vector)c;
- (id) initWithVectorA:(Vector)a b:(Vector)b c:(Vector)c;
- (Vertex) vertexA;
- (Vertex) vertexB;
- (Vertex) vertexC;
- (void) rotate;	// a = b, b = c, c = a
- (void) generateTextureCoordinatesAndBinormals;	// Requires that any polar coordinate is in [0].
- (void) fixUpWinding;


- (NSArray *) subdivide;	// A list of four JAIcosTriangles.

@end
