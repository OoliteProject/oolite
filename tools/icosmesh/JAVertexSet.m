#import "JAVertexSet.h"


@implementation JAVertexSet

- (id) init
{
	if ((self = [super init]))
	{
		_indices = [[NSMutableDictionary alloc] init];
		_vertices = [[NSMutableArray alloc] init];
		
		if (_indices == NULL || _vertices == NULL)
		{
			[self release];
			return nil;
		}
	}
	
	return self;
}


- (void) dealloc
{
	[_indices release];
	[_vertices release];
	
	[super dealloc];
}


- (NSUInteger) indexForVertex:(Vertex)vertex
{
	NSValue *value = [NSValue value:&vertex withObjCType:@encode(Vertex)];
	NSNumber *number = [_indices objectForKey:value];
	if (number == nil)
	{
		number = [NSNumber numberWithUnsignedInteger:self.count];
		[_indices setObject:number forKey:value];
		[_vertices addObject:value];
	}
	
	return [number unsignedIntegerValue];
}


- (Vertex) vertexAtIndex:(NSUInteger)index
{
	if (index >= self.count)
	{
		[NSException raise:NSRangeException format:@"%s: attempt to access element %u of %u", __FUNCTION__, index, self.count];
	}
	
	Vertex result;
	[[_vertices objectAtIndex:index] getValue:&result];
	return result;
}


- (NSUInteger) count
{
	return _vertices.count;
}


- (NSArray *) positionArray
{
	unsigned i, count = self.count;
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count * 3];
	for (i = 0; i < count; i++)
	{
		Vertex v = [self vertexAtIndex:i];
		[result addObject:[NSNumber numberWithDouble:v.v.x]];
		[result addObject:[NSNumber numberWithDouble:v.v.y]];
		[result addObject:[NSNumber numberWithDouble:v.v.z]];
	}
	return result;
}


- (NSArray *) texCoordArray
{
	unsigned i, count = self.count;
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:count * 2];
	for (i = 0; i < count; i++)
	{
		Vertex v = [self vertexAtIndex:i];
		[result addObject:[NSNumber numberWithDouble:v.s]];
		[result addObject:[NSNumber numberWithDouble:v.t]];
	}
	return result;
}

@end
