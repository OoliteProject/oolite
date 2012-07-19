/*

OOWeakSet.h

Written by Jens Ayton in 2012 for Oolite.
This code is hereby placed in the public domain.

*/

#import "OOWeakSet.h"
#import "OOCocoa.h"


@interface OOWeakRefUnpackingEnumerator: NSEnumerator
{
@private
	NSEnumerator			*_enumerator;
}

- (id) initWithEnumerator:(NSEnumerator *)enumerator;

+ (id) enumeratorWithCollection:(id)collection;	// Collection must implement -objectEnumerator

@end


@interface OOWeakSet (OOPrivate)

- (void) compact;	// Remove any zeroed entries.

@end


@implementation OOWeakSet

- (id) init
{
	return [self initWithCapacity:0];
}


- (id) initWithCapacity:(OOUInteger)capacity
{
	if ((self = [super init]))
	{
		_objects = [[NSMutableSet alloc] initWithCapacity:capacity];
		if (_objects == NULL)
		{
			[self release];
			return nil;
		}
	}
	return self;
}


+ (id) set
{
	return [[[self alloc] init] autorelease];
}


+ (id) setWithCapacity:(OOUInteger)capacity
{
	return [[[self alloc] initWithCapacity:capacity] autorelease];
}


- (void) dealloc
{
	DESTROY(_objects);
	
	[super dealloc];
}


- (NSString *) description
{
	NSMutableString *result = [NSMutableString stringWithFormat:@"<%@ %p>{", [self class], self];
	NSEnumerator *selfEnum = [self objectEnumerator];
	id object = nil;
	BOOL first = YES;
	while ((object = [selfEnum nextObject]))
	{
		if (!first)  [result appendString:@", "];
		else  first = NO;
		
		NSString *desc = nil;
		if ([object respondsToSelector:@selector(shortDescription)])  desc = [object shortDescription];
		else  desc = [object description];
		
		[result appendString:desc];
	}
	
	[result appendString:@"}"];
	return result;
}


// MARK: Protocol conformance

- (id) copyWithZone:(NSZone *)zone
{
	[self compact];
	OOWeakSet *result = [[OOWeakSet allocWithZone:zone] init];
	[result addObjectsByEnumerating:[self objectEnumerator]];
	return result;
}


- (id) mutableCopyWithZone:(NSZone *)zone
{
	return [self copyWithZone:zone];
}


- (BOOL) isEqual:(id)other
{
	if (![other isKindOfClass:[OOWeakSet class]])  return NO;
	if ([self count] != [other count])  return NO;
	
	BOOL result = YES;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSEnumerator *selfEnum = [self objectEnumerator];
	id object = nil;
	while ((object = [selfEnum nextObject]))
	{
		if (![other containsObject:object])
		{
			result = NO;
			break;
		}
	}
	DESTROY(pool);
	
	return result;
}


// MARK: Meat and potatoes

- (OOUInteger) count
{
	[self compact];
	return [_objects count];
}


- (BOOL) containsObject:(id<OOWeakReferenceSupport>)object
{
	[self compact];
	OOWeakReference *weakObj = [object weakRetain];
	BOOL result = [_objects containsObject:weakObj];
	[weakObj release];
	return result;
}


- (NSEnumerator *) objectEnumerator
{
	return [OOWeakRefUnpackingEnumerator enumeratorWithCollection:_objects];
}


- (void) addObject:(id<OOWeakReferenceSupport>)object
{
	if (object == nil)  return;
	NSAssert([object conformsToProtocol:@protocol(OOWeakReferenceSupport)], @"Attempt to add object to OOWeakSet which does not conform to OOWeakReferenceSupport.");
	
	OOWeakReference *weakObj = [object weakRetain];
	[_objects addObject:weakObj];
	[weakObj release];
}


- (void) removeObject:(id<OOWeakReferenceSupport>)object
{
	OOWeakReference *weakObj = [object weakRetain];
	[_objects removeObject:weakObj];
	[weakObj release];
}


- (void) addObjectsByEnumerating:(NSEnumerator *)enumerator
{
	id object = nil;
	[self compact];
	while ((object = [enumerator nextObject]))
	{
		[self addObject:object];
	}
}


- (void) makeObjectsPerformSelector:(SEL)selector
{
	OOWeakReference *weakRef = nil;
	foreach (weakRef, _objects)
	{
		[[weakRef weakRefUnderlyingObject] performSelector:selector];
	}
}


- (void) makeObjectsPerformSelector:(SEL)selector withObject:(id)argument
{
	OOWeakReference *weakRef = nil;
	foreach (weakRef, _objects)
	{
		[[weakRef weakRefUnderlyingObject] performSelector:selector withObject:argument];
	}
}


- (void) removeAllObjects
{
	[_objects removeAllObjects];
}


- (void) compact
{
	OOWeakReference *weakRef = nil;
	BOOL compactRequired = NO;
	foreach (weakRef, _objects)
	{
		if ([weakRef weakRefUnderlyingObject] == nil)
		{
			compactRequired = YES;
			break;
		}
	}
	
	if (compactRequired)
	{
		NSMutableSet *newObjects = [[NSMutableSet alloc] initWithCapacity:[_objects count]];
		foreach (weakRef, _objects)
		{
			if ([weakRef weakRefUnderlyingObject] != nil)
			{
				[newObjects addObject:weakRef];
			}
		}
		
		[_objects release];
		_objects = newObjects;
	}
}

@end


@implementation OOWeakRefUnpackingEnumerator

- (id) initWithEnumerator:(NSEnumerator *)enumerator
{
	if (enumerator == nil)
	{
		[self release];
		return nil;
	}
	
	if ((self = [super init]))
	{
		_enumerator = [enumerator retain];
	}
	
	return self;
}


+ (id) enumeratorWithCollection:(id)collection
{
	return [[[self alloc] initWithEnumerator:[collection objectEnumerator]] autorelease];
}


- (void) dealloc
{
	[_enumerator release];
	
	[super dealloc];
}


- (id) nextObject
{
	id next = nil;
	while ((next = [_enumerator nextObject]))
	{
		next = [next weakRefUnderlyingObject];
		if (next != nil)  return next;
	}
	
	return nil;
}

@end
