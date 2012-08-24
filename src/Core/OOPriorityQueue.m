/*

OOPriorityQueue.m


Copyright (C) 2007-2012 Jens Ayton

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

#include <assert.h>

#import "OOPriorityQueue.h"
#import "OOFunctionAttributes.h"


/*	Capacity grows by 50% each time. kMinCapacity must be at least 2 or Bad
	Things will happen. Some examples of growth patterns based on kMinCapacity:
	2:	2  3  4  6  9  13  19  28  42  63  94  141  211  316  474  711  1066...
	4:	4  6  9  13  19  28  42  63  94  141  211  316  474  711  1066  1599...
	8:	8  12  18  27  40  60  90  135  202  303  454  681  1021  1531  2296...
	16:	16  24  36  54  81  121  181  271  406  609  913  1369  2053  3079...
	32:	32  48  72  108  162  243  364  546  819  1228  1842  2763  4144...
	
	Special cases: when an OOPriorityQueue is copied, the copy's capacity is
	set to the same as its count, which may be less than kMinCapacity. However,
	when it is grown, it will be set to at least kMinCapacity (except in the
	case of a reallocation failure, in which case an attempt will be made to
	grow capacity by one element).
*/
enum
{
	kMinCapacity				= 16
};


/*	Functions to navigate the binary heap.
	Using one-based indices, the following hold:
	* The left child of a node, L(n), is 2n.
	* The right child of a node, R(n), is 2n + 1.
	* The parent of a node, P(n), is n/2 for n > 1.
	
	Using zero-based indices, we must convert to and from one-based indices to
	perform these calculations, giving:
	* Lz(n) = L(n+1)-1 = (2(n+1))-1 = 2n+1
	* Rz(n) = R(n+1)-1 = (2(n+1)+1)-1 = 2n+2
	* Pz(n) = P(n+1)-1 = ((n+1)/2)-1
*/


OOINLINE OOUInteger PQLeftChild(OOUInteger n) INLINE_CONST_FUNC;
OOINLINE OOUInteger PQRightChild(OOUInteger n) INLINE_CONST_FUNC;
OOINLINE OOUInteger PQParent(OOUInteger n) INLINE_CONST_FUNC;

OOINLINE OOUInteger PQLeftChild(OOUInteger n)
{
	return (n << 1) + 1;
}

OOINLINE OOUInteger PQRightChild(OOUInteger n)
{
	return (n << 1) + 2;
}


OOINLINE OOUInteger PQParent(OOUInteger n)
{
	return ((n + 1) >> 1) - 1;
}


typedef NSComparisonResult (*CompareIMP)(id self, SEL _cmd, id other);


OOINLINE NSComparisonResult PQCompare(id a, id b, SEL comparator)
{
	CompareIMP				compare = NULL;
	NSComparisonResult		result;
	
	// This is equivalent to [a performSelector:comparator withObject:b], except the resulting value isn't an object.
	compare = (CompareIMP)[a methodForSelector:comparator];
	result = compare(a, comparator, b);
	return result;
}


// Private priority queue methods.
@interface OOPriorityQueue (Private)

- (void) makeObjectsPerformSelector:(SEL)selector;

- (void) bubbleUpFrom:(OOUInteger)i;
- (void) bubbleDownFrom:(OOUInteger)i;

- (void) growBuffer;
- (void) shrinkBuffer;

- (void)removeObjectAtIndex:(OOUInteger)i;

#if OO_DEBUG
- (void) appendDebugDataToString:(NSMutableString *)string index:(OOUInteger)i depth:(OOUInteger)depth;
#endif

@end


// NSEnumerator subclass to pull objects from queue.
@interface OOPriorityQueueEnumerator: NSEnumerator
{
@private
	OOPriorityQueue			*_queue;
}

- (id) initWithPriorityQueue:(OOPriorityQueue *)queue;

@end


@implementation OOPriorityQueue

+ (instancetype) queueWithComparator:(SEL)comparator
{
	return [[[self alloc] initWithComparator:comparator] autorelease];
}


- (id) initWithComparator:(SEL)comparator
{
	if (comparator == NULL)
	{
		[self release];
		return nil;
	}
	
	self = [super init];
	if (self != nil)
	{
		_comparator = comparator;
	}
	
	return self;
}


- (id) init
{
	return [self initWithComparator:@selector(compare:)];
}


- (void) dealloc
{
	[self makeObjectsPerformSelector:@selector(release)];
	free(_heap);
	
	[super dealloc];
}


- (NSString *) description
{
	return [NSString stringWithFormat:@"<%@ %p>{count=%lu, capacity=%lu}", [self class], self, _count, _capacity];
}


#if OO_DEBUG
- (NSString *) debugDescription
{
	NSMutableString				*result = nil;
	
	result = [NSMutableString string];
	[result appendFormat:@"<%@ %p> (count=%lu, capacity=%lu, comparator=%@)", [self class], self, _count, _capacity, NSStringFromSelector(_comparator)];
	
	if (_count != 0)
	{
		[result appendString:@"\n{\n"];
		[self appendDebugDataToString:result index:0 depth:0];
		[result appendString:@"}"];
	}
	else
	{
		[result appendString:@" {}"];
	}
	return result;
}
#endif


- (BOOL) isEqual:(id)object
{
	OOUInteger					i;
	OOPriorityQueue				*selfCopy = nil, *otherCopy = nil;
	BOOL						identical = YES;
	
	if (object == self)  return YES;
	if (![object isKindOfClass:[self class]])  return NO;
	
	if (_count != [object count])  return NO;
	if (_count == 0)  return YES;
	
	selfCopy = [self copy];
	otherCopy = [object copy];
	i = _count;
	while (i--)
	{
		if (![[selfCopy nextObject] isEqual:[otherCopy nextObject]])
		{
			identical = NO;
			break;
		}
	}
	[selfCopy release];
	[otherCopy release];
	
	return identical;
}


- (OOUInteger) hash
{
	if (_count == 0)  return NSNotFound;
	return _count ^ [_heap[0] hash];
}


- (id) copyWithZone:(NSZone *)zone
{
	OOPriorityQueue				*copy = nil;
	
	copy = [[self class] allocWithZone:zone];
	if (copy != nil)
	{
		copy->_comparator = _comparator;
		copy->_count = _count;
		copy->_capacity = _count;
		
		copy->_heap = malloc(_count * sizeof(id));
		if (copy->_heap != NULL)
		{
			memcpy(copy->_heap, _heap, _count * sizeof(id));
			[copy makeObjectsPerformSelector:@selector(retain)];
		}
		else  if (_count != 0)
		{
			[copy release];
			copy = nil;
		}
	}
	
	return copy;
}


- (void) addObject:(id)object
{
	OOUInteger			i;
	
	// Validate object
	if (object == nil)
	{
		[NSException raise:NSInvalidArgumentException
					format:@"Attempt to insert nil into OOPriorityQueue."];
	}
	
	if (![object respondsToSelector:_comparator])
	{
		[NSException raise:NSInvalidArgumentException
					format:@"Attempt to insert object (%@) which does not support comparator %@ into OOPriorityQueue.",
						   object, NSStringFromSelector(_comparator)];
	}
	
	// Ensure there is sufficent space.
	if (_count == _capacity)  [self growBuffer];
	
	// insert object at end of buffer.
	i = _count++;
	_heap[i] = object;
	
	[self bubbleUpFrom:i];
	[object retain];
}


- (void) removeObject:(id)object
{
	OOUInteger				i;
	
	/*	Perform linear search for object (using comparator). A depth-first
		search could skip leaves of lower priority, but I don't expect this to
		be called very often.
	*/
	
	if (object == nil)  return;
	
	for (i = 0; i < _count; ++i)
	{
		if (PQCompare(object, _heap[i], _comparator) == 0)
		{
			[self removeObjectAtIndex:i];
		}
	}
}


- (void) removeExactObject:(id)object
{
	OOUInteger				i;
	
	if (object == nil)  return;
	
	for (i = 0; i < _count; ++i)
	{
		if (object == _heap[i])
		{
			[self removeObjectAtIndex:i];
		}
	}
}


- (OOUInteger) count
{
	return _count;
}


- (id) nextObject
{
	id result = [self peekAtNextObject];
	[self removeNextObject];
	return result;
}


- (id) peekAtNextObject
{
	if (_count == 0)  return nil;
//	return [[_heap[0] retain] autorelease];
	return _heap[0];
}


- (void) removeNextObject
{
	[self removeObjectAtIndex:0];
}


- (void) addObjects:(id)collection
{
	id					value = nil;
	
	if ([collection respondsToSelector:@selector(objectEnumerator)])  collection = [collection objectEnumerator];
	if (![collection respondsToSelector:@selector(nextObject)])  return;
	
	while ((value = [collection nextObject]))  [self addObject:value];
}


- (NSArray *) sortedObjects
{
	return [[self objectEnumerator] allObjects];
}


- (NSEnumerator *) objectEnumerator
{
	return [[[OOPriorityQueueEnumerator alloc] initWithPriorityQueue:self] autorelease];
}

@end


@implementation OOPriorityQueue (Private)

- (void) makeObjectsPerformSelector:(SEL)selector
{
	OOUInteger				i;
	
	if (selector == NULL)  return;
	
	for (i = 0; i != _count; ++i)
	{
		[_heap[i] performSelector:selector];
	}
}


- (void) bubbleUpFrom:(OOUInteger)i
{
	OOUInteger				pi;
	id						obj = nil, par = nil;
	
	while (0 < i)
	{
		pi = PQParent(i);
		obj = _heap[i];
		par = _heap[pi];
		
		if (PQCompare(obj, par, _comparator) < 0)
		{
			_heap[i] = par;
			_heap[pi] = obj;
			i = pi;
		}
		else  break;
	}
}


- (void) bubbleDownFrom:(OOUInteger)i
{
	OOUInteger				end = _count - 1;
	OOUInteger				li, ri, next;
	id						obj = nil;
	
	obj = _heap[i];
	while (PQLeftChild(i) <= end)
	{
		li = PQLeftChild(i);
		ri = PQRightChild(i);
		
		// If left child has lower priority than right child, or there is only one child...
		if (li == end || PQCompare(_heap[li], _heap[ri], _comparator) < 0)
		{
			next = li;
		}
		else
		{
			next = ri;
		}
		
		if (PQCompare(_heap[next], obj, _comparator) < 0)
		{
			// Exchange parent with lowest-priority child
			_heap[i] = _heap[next];
			_heap[next] = obj;
			i = next;
		}
		else  break;
	}
}


- (void) growBuffer
{
	id					*newBuffer = NULL;
	OOUInteger			newCapacity;
	
	newCapacity = _capacity * 3 / 2;
	if (newCapacity < kMinCapacity)  newCapacity = kMinCapacity;
	
	// Note: realloc(NULL, size) with non-zero size is equivalent to malloc(size), so this is OK starting from a NULL buffer.
	newBuffer = realloc(_heap, newCapacity * sizeof(id));
	if (newBuffer == NULL)
	{
		// Attempt to grow by just one waffer-thin slot.
		newCapacity = _capacity + 1;
		newBuffer = realloc(_heap, newCapacity * sizeof(id));
		
		if (newBuffer == NULL)
		{
			// Failed to grow.
			[NSException raise:NSMallocException
						format:@"Could not expand capacity of OOPriorityQueue."];
		}
	}
	
	_heap = newBuffer;
	_capacity = newCapacity;
	
	assert(_count < _capacity);
}


- (void)shrinkBuffer
{
	OOUInteger			amountToRemove;
	id					*newBuffer = NULL;
	OOUInteger			newCapacity;
	
	if (kMinCapacity < _capacity)
	{
		// Remove two thirds of free space, if at least three slots are free.
		amountToRemove = (_capacity - _count) * 2 / 3;
		if (2 < amountToRemove)
		{
			newCapacity = _capacity - amountToRemove;
			newBuffer = realloc(_heap, newCapacity * sizeof(id));
			if (newBuffer != NULL)
			{
				_heap = newBuffer;
				_capacity = newCapacity;
			}
		}
	}
}


- (void)removeObjectAtIndex:(OOUInteger)i
{
	id					object = nil;
	
	if (_count <= i)  return;
	
	object = _heap[i];
	if (i < --_count)
	{
		// Overwrite object with last object in array
		_heap[i] = _heap[_count];
		
		// Push previously-last object down until tree is partially ordered.
		[self bubbleDownFrom:i];
	}
	else
	{
		// Special case: removing last (or only) object. No bubbling needed.
	}
	
	[object autorelease];
	if (_count * 2 <= _capacity)  [self shrinkBuffer];
}


#if OO_DEBUG
- (void) appendDebugDataToString:(NSMutableString *)string index:(OOUInteger)i depth:(OOUInteger)depth
{
	OOUInteger				spaces;
	
	if (_count <= i)  return;
	
	spaces = 2 + depth;
	while (spaces--)  [string appendString:@"  "];
	[string appendString:[_heap[i] description]];
	[string appendString:@"\n"];
	
	[self appendDebugDataToString:string index:PQLeftChild(i) depth:depth + 1];
	[self appendDebugDataToString:string index:PQRightChild(i) depth:depth + 1];
}
#endif

@end


@implementation OOPriorityQueueEnumerator

- (id) initWithPriorityQueue:(OOPriorityQueue *)queue
{
	if (queue == nil)
	{
		[self release];
		return nil;
	}
	
	self = [super init];
	if (self != nil)
	{
		_queue = [queue retain];
	}
	return self;
}


- (void) dealloc
{
	[_queue release];
	
	[super dealloc];
}


- (id) nextObject
{
	id value = [_queue nextObject];
	if (value == nil)
	{
		// Maintain enumerator semantics by ensuring we don't start returning new values after returning nil.
		[_queue release];
		_queue = nil;
	}
	return value;
}

@end


#if DEBUG_GRAPHVIZ
@implementation OOPriorityQueue (DebugGraphViz)


static NSString *EscapedString(NSString *string)
{
	NSString				*srcStrings[] =
	{
		//Note: backslash must be first.
		@"\\", @"\"", @"\'", @"\r", @"\n", @"\t", nil
	};
	NSString				*subStrings[] =
	{
		//Note: must be same order.
		@"\\\\", @"\\\"", @"\\\'", @"\\r", @"\\n", @"\\t", nil
	};
	
	NSString				**src = srcStrings, **sub = subStrings;
	NSMutableString			*mutable = nil;
	NSString				*result = nil;
	
	mutable = [string mutableCopy];
	while (*src != nil)
	{
		[mutable replaceOccurrencesOfString:*src++
								withString:*sub++
								   options:0
									 range:NSMakeRange(0, [mutable length])];
	}
	
	if ([mutable length] == [string length])
	{
		result = string;
	}
	else
	{
		result = [[mutable copy] autorelease];
	}
	[mutable release];
	return result;
}


- (NSString *) generateGraphViz
{
	NSMutableString			*result = nil;
	OOUInteger				i;
	id						node = nil;
	NSString				*desc = nil;
	
	result = [NSMutableString string];
	
	// Header
	[result appendString:
		@"// OOPriorityQueue partially ordered tree dump\n\n"
		"digraph heap\n"
		"{\n"
		"\tgraph [charset=\"UTF-8\", label=\"OOPriorityQueue heap dump\", labelloc=t, labeljust=l];\n"
		"\tnode [shape=record];\n\t\n\t"];
	
	// Nodes
	for (i = 0; i < _count; ++i)
	{
		node = _heap[i];
		desc = [node description];
		if ([desc length] > 70)
		{
			desc = [[desc substringToIndex:64] stringByAppendingString:@"..."];
		}
		
		[result appendFormat:@"\tnode_%lu [label=\"<f0> | <f1> %@ | <f2>\"];\n", i, EscapedString(desc)];
	}
	
	// Arcs
	for (i = 0; PQLeftChild(i) < _count; ++i)
		{
		[result appendFormat:@"\tnode_%lu:f0 -> node_%lu:f1;\n", i, PQLeftChild(i)];
		if (PQRightChild(i) < _count)  [result appendFormat:@"\tnode_%lu:f2 -> node_%lu:f1;\n", i, PQRightChild(i)];
	}
	
	[result appendString:@"}\n"];
	
	return result;
}


- (void) writeGraphVizToURL:(NSURL *)url
{
	NSString			*graphViz = nil;
	NSData				*data = nil;
	
	graphViz = [self generateGraphViz];
	data = [graphViz dataUsingEncoding:NSUTF8StringEncoding];
	
	if (data != nil)
	{
		[data writeToURL:url atomically:YES];
	}
}


- (void) writeGraphVizToPath:(NSString *)path
{
	[self writeGraphVizToURL:[NSURL fileURLWithPath:path]];
}

@end
#endif
