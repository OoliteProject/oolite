/*

OOMaterial.m


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

Copyright (C) 2007-2010 Jens Ayton

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

#import "OOMaterial.h"
#import "OOFunctionAttributes.h"
#import "OOLogging.h"


static OOMaterial *sActiveMaterial = nil;


@implementation OOMaterial

+ (void)setUp
{
	// I thought we'd need this, but the stuff I needed it for turned out to be problematic. Maybe in future. -- Ahruman
}


- (void)dealloc
{
	// Ensure cleanup happens; doing it more than once is safe.
	[self willDealloc];
	
	[super dealloc];
}


- (NSString *)descriptionComponents
{
	return [NSString stringWithFormat:@"\"%@\"", [self name]];
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


+ (OOMaterial *)current
{
	return [[sActiveMaterial retain] autorelease];
}


- (void)ensureFinishedLoading
{
	
}


- (BOOL) isFinishedLoading
{
	return YES;
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	
}


- (BOOL) wantsNormalsAsTextureCoordinates
{
	return NO;
}


#if OO_MULTITEXTURE
- (OOUInteger) countOfTextureUnitsWithBaseCoordinates
{
	return 1;
}
#endif

@end


@implementation OOMaterial (OOSubclassInterface)

- (BOOL)doApply
{
	OOLogGenericSubclassResponsibility();
	return NO;
}


- (void)unapplyWithNext:(OOMaterial *)next;
{
	// Do nothing.
}


- (void)willDealloc
{
	if (EXPECT_NOT(sActiveMaterial == self))
	{
		OOLog(@"shader.dealloc.imbalance", @"***** Material deallocated while active, indicating a retain/release imbalance.");
		[self unapplyWithNext:nil];
		sActiveMaterial = nil;
	}
}

@end
