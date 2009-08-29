/*

OOFilteringEnumerator.h
By Jens Ayton

NSEnumerator which takes an existing enumerator and filters out the objects
that return NO from a given method. The method may take 0 or 1 arguments

Example of use:
	NSArray			*cats = [self cats];
	NSEnumerator	*happyCatEnum = [[cats objectEnumerator] filteredWithSelector:@selector(isHappy)];
	id				happyCat = nil;
	
	while ((happyCat = [happyCatEnum nextObject]))
	{
		...
	}

Filters can be trivially chained. For instance, to get happy red cats, use:
	NSEnumeratore	*happyRedCatEnum = [[[cats objectEnumerator]
										filteredWithSelector:@selector(isHappy)]
										filteredWithSelector:@selector(hasColor:)
												 andArgument:[NSColor redColor]];

Objects that do not respond to the filter selector are treated as if they had
returned NO.

Bonus feature: adds NSArray-like (but non-exception-throwing)
makeObjectsPerformSelector: to all enumerators.


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2008 Jens Ayton

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

#import "OOCocoa.h"


@interface OOFilteringEnumerator: NSEnumerator
{
	NSEnumerator		*_underlyingEnum;
	SEL					_selector;
	id					_argument;
	BOOL				_takesArgument;
}

+ (id) filterEnumerator:(NSEnumerator *)enumerator withSelector:(SEL)selector;
+ (id) filterEnumerator:(NSEnumerator *)enumerator withSelector:(SEL)selector andArgument:(id)argument;

- (id) initWithUnderlyingEnumerator:(NSEnumerator *)enumerator
					   withSelector:(SEL)selector
					 takingArgument:(BOOL)takesArgument
					  argumentValue:(id)argument;

@end


@interface NSEnumerator (OOFilteringEnumerator)

- (id) filteredWithSelector:(SEL)selector;
- (id) filteredWithSelector:(SEL)selector andArgument:(id)argument;

@end


@interface NSArray (OOFilteringEnumerator)

- (id) objectEnumeratorFilteredWithSelector:(SEL)selector;
- (id) objectEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument;

@end


@interface NSSet (OOFilteringEnumerator)

- (id) objectEnumeratorFilteredWithSelector:(SEL)selector;
- (id) objectEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument;

@end


@interface NSDictionary (OOFilteringEnumerator)

- (id) objectEnumeratorFilteredWithSelector:(SEL)selector;
- (id) objectEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument;

- (id) keyEnumeratorFilteredWithSelector:(SEL)selector;
- (id) keyEnumeratorFilteredWithSelector:(SEL)selector andArgument:(id)argument;

@end


@interface NSEnumerator (OOMakeObjectsPerformSelector)

- (void)makeObjectsPerformSelector:(SEL)selector;
- (void)makeObjectsPerformSelector:(SEL)selector withObject:(id)argument;

@end
