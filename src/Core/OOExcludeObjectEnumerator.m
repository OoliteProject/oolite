/*

OOExcludeObjectEnumerator.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOExcludeObjectEnumerator.h"


@implementation OOExcludeObjectEnumerator

- (id) initWithEnumerator:(NSEnumerator *)enumerator
		  excludingObject:(id)object
{
	if ((self = [super init]))
	{
		_enumerator = [enumerator retain];
		_excludeObject = [object retain];
	}
	
	return self;
}


- (void) dealloc
{
	[_enumerator release];
	[_excludeObject release];
	
	[super dealloc];
}


+ (id) enumeratorWithEnumerator:(NSEnumerator *)enumerator
				excludingObject:(id)object
{
	if (object == nil)  return enumerator;
	if (enumerator == nil)  return nil;
	
	return [[[self alloc] initWithEnumerator:enumerator excludingObject:object] autorelease];
}


- (id) nextObject
{
	id result = nil;
	do
	{
		result = [_enumerator nextObject];
	} while (result == _excludeObject && result != nil);
	
	return result;
}

@end


@implementation NSEnumerator (OOExcludingObject)

- (id) ooExcludingObject:(id)object
{
	return [OOExcludeObjectEnumerator enumeratorWithEnumerator:self excludingObject:object];
}

@end
