/*

OOMaterial.m

This is an abstract class; actual materials should be subclasses.

Currently, only shader materials are supported. Direct use of textures should
also be replaced with an OOMaterial subclass.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "OOMaterial.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"

static OOMaterial *sActiveMaterial;


@implementation OOMaterial

- (void)dealloc
{
	// Ensure cleanup happens; doing it more than once is safe.
	[self willDealloc];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%@}", [self className], self, [self name]];
}


- (void)willDealloc
{
	if (EXPECT_NOT(sActiveMaterial == self))
	{
		OOLog(@"shader.dealloc.imbalance", @"***** Material deallocated while active, indicating a retain/release imbalance. Expect imminent crash.");
		[self unapplyWithNext:nil];
		sActiveMaterial = nil;
	}
}


- (NSString *)name
{
	OOLogGenericParameterError();
	return nil;
}


// Make this the current GL shader program.
- (void)apply
{
	[sActiveMaterial unapplyWithNext:self];
	[sActiveMaterial release];
	sActiveMaterial = nil;
	
	if ([self doApply])
	{
		sActiveMaterial = [self retain];
	}
}


+ (void)applyNone
{
	[sActiveMaterial unapplyWithNext:nil];
	[sActiveMaterial release];
	sActiveMaterial = nil;
}


- (void)ensureFinishedLoading
{
	
}


- (void)unapplyWithNext:(OOMaterial *)next;
{
	// Do nothing.
}

@end
