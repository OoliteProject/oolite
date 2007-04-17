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


@implementation OOSingleTextureMaterial

- (id)initWithName:(NSString *)name configuration:(NSDictionary *)configuration
{
	NSDictionary		*texSpec = nil;
	
	self = [super initWithName:name configuration:configuration];
	if (name != nil && self != nil)
	{
		texSpec = [configuration dictionaryForKey:@"texture" defaultValue:nil];
		if (texSpec == nil)
		{
			texSpec = [[configuration arrayForKey:@"textures" defaultValue:nil]
						dictionaryAtIndex:0 defaultValue:nil];
		}
		
		if (texSpec != nil)
		{
			if ([texSpec stringForKey:@"name" defaultValue:nil] == nil)
			{
				// Add name entry to dictionary...
				texSpec = [texSpec mutableCopy];
				[(NSMutableDictionary *)texSpec setObject:name forKey:@"name"];
				[texSpec autorelease];
			}
			
			texture = [OOTexture textureWithConfiguration:texSpec];
		}
		else
		{
			texture = [OOTexture textureWithName:name options:kOOTextureDefaultOptions anisotropy:kOOTextureDefaultAnisotropy lodBias:kOOTextureDefaultLODBias];
		}
		[texture retain];
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

@end
