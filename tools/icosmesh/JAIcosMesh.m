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

@end


@implementation JAIcosMesh

- (id) init
{
	return [self initWithVertexSet:nil];
}


+ (id) meshWithVertexSet:(JAVertexSet *)vertexSet
{
	return [[[self alloc] initWithVertexSet:vertexSet] autorelease];
}


- (id) initWithVertexSet:(JAVertexSet *)vertexSet
{
	if ((self = [super init]))
	{
		if (vertexSet == nil)  vertexSet = [[[JAVertexSet alloc] init] autorelease];
		_vertexSet = [vertexSet retain];
		
		_indices = [[NSMutableArray alloc] init];
		if (_vertexSet == nil || _indices == nil)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	[_vertexSet release];
	[_indices release];
	
	[super dealloc];
}


- (JAVertexSet *)vertexSet
{
	return _vertexSet;
}


- (NSUInteger) faceCount
{
	return _indices.count / 3;
}


- (NSUInteger) maxIndex
{
	return _maxIndex;
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
	return [[_indices copy] autorelease];
}


- (void) addOneVertex:(Vertex)v
{
	NSUInteger index = [_vertexSet indexForVertex:v];
	[_indices addObject:[NSNumber numberWithUnsignedInteger:index]];
	if (_maxIndex < index)  _maxIndex = index;
}

@end
