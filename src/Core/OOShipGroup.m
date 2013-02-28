/*
OOShipGroup.m

IMPLEMENTATION NOTE:
This is implemented as a dynamic array rather than a hash table for the
following reasons:
 *	Ship groups are generally quite small, not motivating a more complex
	implementation.
 *	The code ship groups replace was all array-based and not a significant
	bottleneck.
 *	Ship groups are compacted (i.e., dead weak references removed) as a side
	effect of iteration.
 *	Many uses of ship groups involve iterating over the whole group anyway.


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "ShipEntity.h"
#import "OOShipGroup.h"
#import "OOMaths.h"


enum
{
	kMinSize				= 4,
	kMaxFreeSpace			= 128
};


@interface OOShipGroupEnumerator: NSEnumerator
{
	// ivars are public so ShipGroupIterate() can peek at both these and OOShipGroup's. Naughty!
@public
	OOShipGroup				*_group;
	NSUInteger				_index, _updateCount;
	BOOL					_considerCleanup, _cleanupNeeded;
}

- (id) initWithShipGroup:(OOShipGroup *)group;

- (NSUInteger) index;
- (void) setPerformCleanup:(BOOL)flag;

@end


@interface OOShipGroup (Private)

- (BOOL) resizeTo:(NSUInteger)newCapacity;
- (void) cleanUp;

- (NSUInteger) updateCount;

@end


static id ShipGroupIterate(OOShipGroupEnumerator *enumerator);


@implementation OOShipGroup

- (id) init
{
	return [self initWithName:nil];
}


- (id) initWithName:(NSString *)name
{
	if ((self = [super init]))
	{
		_capacity = kMinSize;
		_members = malloc(sizeof *_members * _capacity);
		if (_members == NULL)
		{
			[self release];
			return nil;
		}
		
		[self setName:name];
	}
	
	return self;
}


+ (instancetype) groupWithName:(NSString *)name
{
	return [[[self alloc] initWithName:name] autorelease];
}


+ (instancetype) groupWithName:(NSString *)name leader:(ShipEntity *)leader
{
	OOShipGroup *result = [self groupWithName:name];
	[result setLeader:leader];
	return result;
}


- (void) dealloc
{
	NSUInteger i;
	
	for (i = 0; i < _count; i++)
	{
		[_members[i] release];
	}
	free(_members);
	[_name release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString *desc = [NSString stringWithFormat:@"%llu ships", (unsigned long long)_count];
	if ([self name] != nil)
	{
		desc = [NSString stringWithFormat:@"\"%@\", %@", [self name], desc];
	}
	if ([self leader] != nil)
	{
		desc = [NSString stringWithFormat:@"%@, leader: %@", desc, [[self leader] shortDescription]];
	}
	return desc;
}


- (NSString *) name
{
	return _name;
}


- (void) setName:(NSString *)name
{
	_updateCount++;
	
	if (_name != name)
	{
		[_name release];
		_name = [name retain];
	}
}


- (ShipEntity *) leader
{
	ShipEntity *result = [_leader weakRefUnderlyingObject];
	
	// If reference is stale, delete weakref object.
	if (result == nil && _leader != nil)
	{
		[_leader release];
		_leader = nil;
	}
	
	return result;
}


- (void) setLeader:(ShipEntity *)leader
{
	_updateCount++;
	
	if (leader != [self leader])
	{
		[_leader release];
		[self addShip:leader];
		_leader = [leader weakRetain];
	}
}


- (NSEnumerator *) objectEnumerator
{
	return [[[OOShipGroupEnumerator alloc] initWithShipGroup:self] autorelease];
}


- (NSEnumerator *) mutationSafeEnumerator
{
	return [[self memberArray] objectEnumerator];
}


- (NSSet *) members
{
	return [NSSet setWithArray:[self memberArray]];
}


- (NSSet *) membersExcludingLeader
{
	return [NSSet setWithArray:[self memberArrayExcludingLeader]];
}


#if OOLITE_FAST_ENUMERATION
- (NSArray *) memberArray
{
	id						*objects = NULL;
	NSUInteger				count = 0;
	NSArray					*result = nil;
	
	if (_count == 0)  return [NSArray array];
	
	objects = malloc(sizeof *objects * _count);
	for (id ship in self)
	{
		objects[count++] = ship;
	}
	
	result = [NSArray arrayWithObjects:objects count:count];
	free(objects);
	
	return result;
}


- (NSArray *) memberArrayExcludingLeader
{
	id						*objects = NULL;
	NSUInteger				count = 0;
	NSArray					*result = nil;
	ShipEntity				*leader = nil;
	
	if (_count == 0)  return [NSArray array];
	leader = self.leader;
	
	objects = malloc(sizeof *objects * _count);
	for (id ship in self)
	{
		if (ship != leader)
		{
			objects[count++] = ship;
		}
	}
	
	result = [NSArray arrayWithObjects:objects count:count];
	free(objects);
	
	return result;
}


- (BOOL) containsShip:(ShipEntity *)ship
{
	ShipEntity				*containedShip = nil;
	
	for (containedShip in self)
	{
		if ([ship isEqual:containedShip])
		{
			return YES;
		}
	}
	
	return NO;
}
#else
- (NSArray *) memberArray
{
	return [[self objectEnumerator] allObjects];
}


- (NSArray *) memberArrayExcludingLeader
{
	id						*objects = NULL;
	NSUInteger				count = 0;
	NSArray					*result = nil;
	NSEnumerator			*shipEnum = nil;
	ShipEntity				*ship = nil;
	ShipEntity				*leader = nil;
	
	if (_count == 0)  return [NSArray array];
	leader = [self leader];
	if (leader == nil)  return [self memberArray];
	
	objects = malloc(sizeof *objects * _count);
	for (shipEnum = [self objectEnumerator]; (ship = [shipEnum nextObject]); )
	{
		if (ship != leader)
		{
			objects[count++] = ship;
		}
	}
	
	result = [NSArray arrayWithObjects:objects count:count];
	free(objects);
	
	return result;
}


- (BOOL) containsShip:(ShipEntity *)ship
{
	OOShipGroupEnumerator	*shipEnum = nil;
	ShipEntity				*containedShip = nil;
	BOOL					result = NO;
	
	shipEnum = (OOShipGroupEnumerator *)[self objectEnumerator];
	[shipEnum setPerformCleanup:NO];
	while ((containedShip = [shipEnum nextObject]))
	{
		if ([ship isEqual:containedShip])
		{
			result = YES;
			break;
		}
	}
	
	// Clean up
	[self cleanUp];
	
	return result;
}
#endif


- (BOOL) addShip:(ShipEntity *)ship
{
	_updateCount++;
	
	if ([self containsShip:ship])  return YES;	// it's in the group already, result!
	
	// Ensure there's space.
	if (_count == _capacity)
	{
		if (![self resizeTo:(_capacity > kMaxFreeSpace) ? (_capacity + kMaxFreeSpace) : (_capacity * 2)])
		{
			if (![self resizeTo:_capacity + 1])
			{
				// Out of memory?
				return NO;
			}
		}
	}
	
	_members[_count++] = [ship weakRetain];
	return YES;
}


- (BOOL) removeShip:(ShipEntity *)ship
{
	OOShipGroupEnumerator	*shipEnum = nil;
	ShipEntity				*containedShip = nil;
	NSUInteger				index;
	BOOL					foundIt = NO;
	
	_updateCount++;
	
	if (ship == [self leader])  [self setLeader:nil];
	
	shipEnum = (OOShipGroupEnumerator *)[self objectEnumerator];
	[shipEnum setPerformCleanup:NO];
	while ((containedShip = [shipEnum nextObject]))
	{
		if ([ship isEqual:containedShip])
		{
			index = [shipEnum index] - 1;
			_members[index] = _members[--_count];
			foundIt = YES;
			
			// Clean up
			[ship setGroup:nil];
			[ship setOwner:ship];
			[self cleanUp];
			break;
		}
	}
	return foundIt;
}

/* TODO post-1.78: profiling indicates this is a noticeable
 * contributor to ShipEntity::update time. Consider optimisation: may
 * be possible to return _count if invalidation of weakref and group
 * removal in ShipEntity::dealloc keeps the data consistent anyway -
 * CIM */

- (NSUInteger) count
{
	NSEnumerator		*memberEnum = nil;
	NSUInteger			result = 0;
	
	if (_count != 0)
	{
		memberEnum = [self objectEnumerator];
		while ([memberEnum nextObject] != nil)  result++;
	}
	
	assert(result == _count);
	
	return result;
}


- (BOOL) isEmpty
{
	if (_count == 0)  return YES;
	
	return [[self objectEnumerator] nextObject] == nil;
}


- (BOOL) resizeTo:(NSUInteger)newCapacity
{
	OOWeakReference			**temp = NULL;
	
	if (newCapacity < _count)  return NO;
	
	temp = realloc(_members, newCapacity * sizeof *_members);
	if (temp == NULL)  return NO;
	
	_members = temp;
	_capacity = newCapacity;
	return YES;
}


- (void) cleanUp
{
	NSUInteger				newCapacity = _capacity;
	
	if (_count >= kMaxFreeSpace)
	{
		if (_capacity > _count + kMaxFreeSpace)
		{
			newCapacity = _count + 1;	// +1 keeps us at powers of two + multiples of kMaxFreespace.
		}
	}
	else
	{
		if (_capacity > _count * 2)
		{
			newCapacity = OORoundUpToPowerOf2_NS(_count);
			if (newCapacity < kMinSize) newCapacity = kMinSize;
		}
	}
	
	if (newCapacity != _capacity)  [self resizeTo:newCapacity];
}


- (NSUInteger) updateCount
{
	return _updateCount;
}


static id ShipGroupIterate(OOShipGroupEnumerator *enumerator)
{
	// The work is done here so that we can have access to both OOShipGroup's and OOShipGroupEnumerator's ivars.
	
	OOShipGroup				*group = enumerator->_group;
	ShipEntity				*result = nil;
	BOOL					cleanupNeeded = NO;
	
	if (enumerator->_updateCount != group->_updateCount)
	{
		[NSException raise:NSGenericException format:@"Collection <OOShipGroup: %p> was mutated while being enumerated.", group];
	}
	
	while (enumerator->_index < group->_count)
	{
		result = [group->_members[enumerator->_index] weakRefUnderlyingObject];
		if (result != nil)
		{
			enumerator->_index++;
			break;
		}
		
		// If we got here, the group contains a stale reference to a dead ship.
		group->_members[enumerator->_index] = group->_members[--group->_count];
		cleanupNeeded = YES;
	}
	
	// Clean-up handling. Only perform actual clean-up at end of iteration.
	if (enumerator->_considerCleanup)
	{
		enumerator->_cleanupNeeded = enumerator->_cleanupNeeded && cleanupNeeded;
		if (enumerator->_cleanupNeeded && result == nil)
		{
			[group cleanUp];
		}
	}
	
	return result;
}


#if OOLITE_FAST_ENUMERATION
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
	NSUInteger				srcIndex, dstIndex = 0;
	ShipEntity				*item = nil;
	BOOL					cleanupNeeded = NO;
	
	srcIndex = state->state;
	while (srcIndex < _count && dstIndex < len)
	{
		item = [_members[srcIndex] weakRefUnderlyingObject];
		if (item != nil)
		{
			stackbuf[dstIndex++] = item;
			srcIndex++;
		}
		else
		{
			_members[srcIndex] = _members[--_count];
			cleanupNeeded = YES;
		}
	}
	
	if (cleanupNeeded)  [self cleanUp];
	
	state->state = srcIndex;
	state->itemsPtr = stackbuf;
	state->mutationsPtr = &_updateCount;
	
	return dstIndex;
}
#endif


/*	This method exists purely to suppress Clang static analyzer warnings that
	this ivar is unused (but may be used by categories, which they are).
	FIXME: there must be a feature macro we can use to avoid actually building
	this into the app, but I can't find it in docs.
*/
- (BOOL) suppressClangStuff
{
	return !_jsSelf;
}

@end


@implementation OOShipGroupEnumerator

- (id) initWithShipGroup:(OOShipGroup *)group
{
	assert(group != nil);
	
	if ((self = [super init]))
	{
		_group = [group retain];
		_considerCleanup = YES;
		_updateCount = [_group updateCount];
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_group);
	
	[super dealloc];
}


- (id) nextObject
{
	return ShipGroupIterate(self);
}


- (NSUInteger) index
{
	return _index;
}


- (void) setPerformCleanup:(BOOL)flag
{
	_considerCleanup = flag;
}

@end
