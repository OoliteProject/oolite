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

@implementation JAIcosMesh

- (JAVertexSet*) vertexSet
{
        return _vertexSet;
}

- (NSUInteger) maxIndex
{
        return _maxIndex;
}

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
		_vertexSet = vertexSet;
		
		_indices = [NSMutableArray array];
		if (vertexSet == nil || _indices == nil)  return nil;
	}
	
	return self;
}


- (NSUInteger) faceCount
{
	return [_indices count] / 3;
}


- (void) addTriangle:(JAIcosTriangle *)triangle
{
	if (triangle == nil)  return;
	
	[self addOneVertex:[triangle vertexA]];
	[self addOneVertex:[triangle vertexB]];
	[self addOneVertex:[triangle vertexC]];
}


- (void) addTriangles:(NSArray *)triangles
{
	JAIcosTriangle *triangle;
        unsigned i;
	for (i = 0; i < [triangles count]; i++)
	{
        	triangle = (JAIcosTriangle*)[triangles objectAtIndex: i];
		[self addTriangle:triangle];
	}
}


- (NSArray *) indexArray
{
	return [_indices copy];
}


- (void) addOneVertex:(Vertex)v
{
	NSUInteger index = [[self vertexSet] indexForVertex:v];
	[_indices addObject:[NSNumber numberWithUnsignedInteger:index]];
	if (_maxIndex < index)  _maxIndex = index;
}

@end
