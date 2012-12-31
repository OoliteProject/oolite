/*

OOFilteringEnumerator.m
By Jens Ayton


Copyright (C) 2008-2013 Jens Ayton

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

#import "OOFilteringEnumerator.h"


typedef BOOL (*BoolReturnMsgSend)(id, SEL);
typedef BOOL (*BoolReturnWithParamMsgSend)(id, SEL, id);


@implementation OOFilteringEnumerator

+ (id) filterEnumerator:(NSEnumerator *)enumerator withSelector:(SEL)selector
{
	if (selector == NULL)  return [[enumerator retain] autorelease];
	
	return [[[self alloc] initWithUnderlyingEnumerator:enumerator
										  withSelector:selector
										takingArgument:NO
										 argumentValue:nil]
						  autorelease];
}


+ (id) filterEnumerator:(NSEnumerator *)enumerator withSelector:(SEL)selector andArgument:(id)argument
{
	if (selector == NULL)  return [[enumerator retain] autorelease];
	
	return [[[self alloc] initWithUnderlyingEnumerator:enumerator
										  withSelector:selector
										takingArgument:YES
										 argumentValue:argument]
			autorelease];
}

- (id) initWithUnderlyingEnumerator:(NSEnumerator *)enumerator
					   withSelector:(SEL)selector
					 takingArgument:(BOOL)takesArgument
					  argumentValue:(id)argument
{
	self = [super init];
	if (self != nil)
	{
		_underlyingEnum = [enumerator retain];
		_selector = selector;
		_takesArgument = takesArgument;
		if (_takesArgument)
		{
			_argument = [argument retain];
		}
	}
	return self;
}


- (void) dealloc
{
	[_underlyingEnum release];
	[_argument release];
	
	[super dealloc];
}


- (NSString *) descriptionComponents
{
	NSString *subDesc = NSStringFromSelector(_selector);
	if (_takesArgument)
	{
		subDesc = [subDesc stringByAppendingString:[_argument shortDescription]];
	}
	
	return [NSString stringWithFormat:@"%@ matching %@", [_underlyingEnum shortDescription], subDesc];
}


- (NSString *) shortDescriptionComponents
{
	return NSStringFromSelector(_selector);
}


- (id) nextObject
{
	for (;;)
	{
		// Get next object
		id obj = [_underlyingEnum nextObject];
		BOOL filter;
		
		if (obj == nil)
		{
			// End of enumeration
			if (_underlyingEnum != nil)
			{
				[_underlyingEnum release];
				_underlyingEnum = nil;
				[_argument release];
				_argument = nil;
			}
			return nil;
		}
		
		// Check against filter
		IMP predicate = [obj methodForSelector:_selector];
		if (predicate != NULL)
		{
			if (!_takesArgument)
			{
				filter = ((BoolReturnMsgSend)predicate)(obj, _selector);
			}
			else
			{
				filter = ((BoolReturnWithParamMsgSend)predicate)(obj, _selector, _argument);
			}
		}
		else
		{
			// Unsupported method
			filter = NO;
		}
		
		// If object passed, return it.
		if (filter)  return obj;
	}
}

@end


@implementation NSEnumerator (OOFilteringEnumerator)

- (id) filteredWithSelector:(SEL)selector
{
	return [OOFilteringEnumerator filterEnumerator:self withSelector:selector];
}


- (id) filteredWithSelector:(SEL)selector andArgument:(id)argument
{
	return [OOFilteringEnumerator filterEnumerator:self withSelector:selector andArgument:argument];
}

@end


@implementation NSArray (OOFilteringEnumerator)

- (id) objectEnumeratorFilteredWithSelector:(SEL)selector
{
	return [[self objectEnumerator] filteredWithSelector:selector];
}


- (id) objectEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument
{
	return [[self objectEnumerator] filteredWithSelector:selector andArgument:argument];
}

@end


@implementation NSSet (OOFilteringEnumerator)

- (id) objectEnumeratorFilteredWithSelector:(SEL)selector
{
	return [[self objectEnumerator] filteredWithSelector:selector];
}


- (id) objectEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument
{
	return [[self objectEnumerator] filteredWithSelector:selector andArgument:argument];
}

@end


@implementation NSDictionary (OOFilteringEnumerator)

- (id) objectEnumeratorFilteredWithSelector:(SEL)selector
{
	return [[self objectEnumerator] filteredWithSelector:selector];
}


- (id) objectEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument
{
	return [[self objectEnumerator] filteredWithSelector:selector andArgument:argument];
}


- (id) keyEnumeratorFilteredWithSelector:(SEL)selector
{
	return [[self keyEnumerator] filteredWithSelector:selector];
}


- (id) keyEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument
{
	return [[self keyEnumerator] filteredWithSelector:selector andArgument:argument];
}

@end


@implementation NSEnumerator (OOMakeObjectsPerformSelector)

- (void)makeObjectsPerformSelector:(SEL)selector
{
	id object = nil;
	while ((object = [self nextObject]))
	{
		if (selector != NULL && [object respondsToSelector:selector])
		{
			[object performSelector:selector];
		}
	}
}


- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument
{
	id object = nil;
	while ((object = [self nextObject]))
	{
		if (selector != NULL && [object respondsToSelector:selector])
		{
			[object performSelector:selector withObject:argument];
		}
	}
}

@end
