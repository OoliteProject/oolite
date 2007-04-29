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


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
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

#import "OOOpenGLExtensionManager.h"
#import "OOShaderMaterial.h"
#import "OOSingleTextureMaterial.h"
#import "OOCollectionExtractors.h";


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


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%@}", [self className], self, [self name]];
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

@end


@implementation OOMaterial (OOConvenienceCreators)

+ (id)materialWithName:(NSString *)name configuration:(NSDictionary *)configuration macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)object
{
	id						result = nil;
	
#ifndef NO_SHADERS
	if ([[OOOpenGLExtensionManager sharedManager] shadersSupported])
	{
		if ([OOShaderMaterial configurationDictionarySpecifiesShaderMaterial:configuration])
		{
			result = [OOShaderMaterial shaderMaterialWithName:name configuration:configuration macros:macros bindingTarget:object];
		}
	}
#endif
	
	if (result == nil)
	{
		if ([[configuration objectForKey:@"diffuse_map"] isEqual:@""])
		{
			result = [[OOBasicMaterial alloc] initWithName:name configuration:configuration];
		}
		else
		{
			result = [[OOSingleTextureMaterial alloc] initWithName:name configuration:configuration];
		}
		[result autorelease];
	}
	
	return result;
}


+ (id)materialWithName:(NSString *)name materialDictionary:(NSDictionary *)materialDict shadersDictionary:(NSDictionary *)shadersDict macros:(NSDictionary *)macros bindingTarget:(id<OOWeakReferenceSupport>)object
{
	NSDictionary			*configuration = nil;
	
#ifndef NO_SHADERS
	if ([[OOOpenGLExtensionManager sharedManager] shadersSupported])
	{
		configuration = [shadersDict dictionaryForKey:name defaultValue:nil];
	}
#endif
	
	if (configuration == nil)
	{
		configuration = [materialDict dictionaryForKey:name defaultValue:nil];
	}
	
	return [self materialWithName:name configuration:configuration macros:macros bindingTarget:object];
}

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
		OOLog(@"shader.dealloc.imbalance", @"***** Material deallocated while active, indicating a retain/release imbalance. Expect imminent crash.");
		[self unapplyWithNext:nil];
		sActiveMaterial = nil;
	}
}

@end
