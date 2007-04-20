/*

OOSingleTextureMaterial.h

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

#import "OOSingleTextureMaterial.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"
#import "OOFunctionAttributes.h"


@implementation OOSingleTextureMaterial

- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration
{
	NSDictionary		*texSpec = nil;
	
	self = [super initWithName:name configuration:configuration];
	if (name != nil && self != nil)
	{
		texSpec = [configuration textureSpecifierForKey:@"diffuse_map" defaultName:name];
		texture = [[OOTexture textureWithConfiguration:texSpec] retain];
	}
	
	if (texture == nil)
	{
		[self release];
		return nil;
	}
	
	return self;
}


- (void)dealloc
{
	[self willDealloc];
	[texture release];
	
	[super dealloc];
}


- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p>{%@}", [self class], self, texture];
}


- (BOOL)doApply
{
	if (EXPECT_NOT(![super doApply]))  return NO;
	
	[texture apply];
	return YES;
}


- (void)unapplyWithNext:(OOMaterial *)next
{
	if (![next isKindOfClass:[OOSingleTextureMaterial class]])  [OOTexture applyNone];
	[super unapplyWithNext:next];
}

@end
