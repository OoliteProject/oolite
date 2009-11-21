//
//  JAIcosMesh.m
//  icosmesh
//
//  Created by Jens Ayton on 2009-11-18.
//  Copyright 2009 Jens Ayton. All rights reserved.
//

#import "JAIcosMesh.h"
#import "JAVertexSet.h"
#import "JAIcosTriangle.h"


@interface JAIcosMesh ()

- (void) addOneVertex:(Vertex)v;

@property (readwrite) JAVertexSet *vertexSet;
@property (readwrite) NSUInteger maxIndex;

@end


@implementation JAIcosMesh

@synthesize vertexSet = _vertexSet, maxIndex = _maxIndex;


- (id) init
{
	return [self initWithVertexSet:nil];
}


+ (id) meshWithVertexSet:(JAVertexSet *)vertexSet
{
	return [[self alloc] initWithVertexSet:vertexSet];
}


- (id) initWithVertexSet:(JAVertexSet *)vertexSet
{
	if ((self = [super init]))
	{
		if (vertexSet == nil)  vertexSet = [[JAVertexSet alloc] init];
		self.vertexSet = vertexSet;
		
		_indices = [NSMutableArray array];
		if (vertexSet == nil || _indices == nil)  return nil;
	}
	
	return self;
}


- (NSUInteger) faceCount
{
	return _indices.count / 3;
}


- (void) addTriangle:(JAIcosTriangle *)triangle
{
	if (triangle == nil)  return;
	
	[self addOneVertex:triangle.vertexA];
	[self addOneVertex:triangle.vertexB];
	[self addOneVertex:triangle.vertexC];
}


- (void) addTriangles:(NSArray *)triangles
{
	for (JAIcosTriangle *triangle in triangles)
	{
		[self addTriangle:triangle];
	}
}


- (NSArray *) indexArray
{
	return [_indices copy];
}


- (void) addOneVertex:(Vertex)v
{
	NSUInteger index = [self.vertexSet indexForVertex:v];
	[_indices addObject:[NSNumber numberWithUnsignedInteger:index]];
	if (self.maxIndex < index)  self.maxIndex = index;
}

@end
