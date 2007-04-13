/*

OOTexture.m

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

#import "OOTexture.h"
#import "OOTextureLoader.h"
#import "OOCollectionExtractors.h"
#import "Universe.h"
#import "ResourceManager.h"


static NSMutableDictionary	*sInUseTextures = nil;

/*	TODO: add limited-sized OOCache of recently-used textures -- requires
	(re-)adding auto-prune option to OOCache.
	
	Design outline: keep a cache of N recently-accessed textures, which
	retains them, in parallel to the in-use cache. If less than N textures are
	currently in use, the cache will keep additional ones around. Old textures
	which fall out of the cache are released, and if they're not used they
	immediately die; if they are, they stay about (and in sInUseTextures)
	until they're not in use any longer. If something calls for a texture
	which is in sInUseTextures but not the cache, they should get the existing
	one, which should be re-added to the cache.
	-- Ahruman
*/

@interface OOTexture (OOPrivate)

- (id)initWithPath:(NSString *)path key:(NSString *)key options:(uint32_t)options;

@end


@implementation OOTexture

+ (id)textureWithName:(NSString *)name options:(uint32_t)options
{
	NSString				*key = nil;
	OOTexture				*result = nil;
	NSString				*path = nil;
	
	// Work out whether we want mip-mapping.
	if ((options & kOOTextureFilterMask) == kOOTextureFilterDefault)
	{
		if ([UNIVERSE reducedDetail])
		{
			options |= kOOTextureFilterNoMipMap;
		}
		else
		{
			options |= kOOTextureFilterForceMipMap;
		}
	}
	
	// Look for existing texture
	key = [NSString stringWithFormat:@"%@:0x%.4X", name, options];
	result = [[sInUseTextures objectForKey:key] pointerValue];
	if (result == nil)
	{
		path = [ResourceManager pathForFileNamed:name inFolder:@"Textures"];
		if (path == nil)
		{
			OOLog(kOOLogFileNotFound, @"Could not find texture file \"%@\".", name);
			return nil;
		}
		
		// No existing texture, load texture...
		result = [[[OOTexture alloc] initWithPath:path key:key options:options] autorelease];
		
		if (result != nil)
		{
			// ...and remember it. Use an NSValue so sInUseTextures doesn't retain the texture.
			if (sInUseTextures == nil)  sInUseTextures = [[NSMutableDictionary alloc] init];
			[sInUseTextures setObject:[NSValue valueWithPointer:result] forKey:key];
		}
	}
	
	return result;
}


+ (id)textureWithConfiguration:(NSDictionary *)configuration
{
	NSString				*name = nil;
	NSString				*useMipMapString = nil;
	uint32_t				options = 0;
	
	name = [configuration stringForKey:@"name" defaultValue:nil];
	if (name == nil)
	{
		OOLog(@"texture.load", @"Invalid texture configuration dictionary (must specify name):\n%@", configuration);
		return nil;
	}
	
	if ([configuration boolForKey:@"noFilter" defaultValue:NO])
	{
		options |= kOOTextureFilterLinear;
	}
	else
	{
		useMipMapString = [configuration stringForKey:@"mipMap" defaultValue:nil];
		if (useMipMapString != nil)
		{
			if ([useMipMapString isEqualToString:@"never"])  options |= kOOTextureFilterNoMipMap;
			else if ([useMipMapString isEqualToString:@"force"])  options |= kOOTextureFilterForceMipMap;
			// Silently ignore other options; this covers "default"
		}
	}
	
	if ([configuration boolForKey:@"noShrink" defaultValue:NO])
	{
		options |= kOOTextureNoShrink;
	}
	
	if ([configuration boolForKey:@"isNormalMap" defaultValue:NO])
	{
		options |= kOOTextureIsNormalMap;
	}
	
	return [self textureWithName:name options:options];
}


- (id)initWithPath:(NSString *)path key:(NSString *)inKey options:(uint32_t)options
{
	self = [super init];
	if (EXPECT_NOT(self == nil))  return nil;
	
	data.loading.loader = [OOTextureLoader loaderWithPath:path options:options];
	if (EXPECT_NOT(data.loading.loader == nil))
	{
		[self release];
		return nil;
	}
	
	key = [inKey copy];
	
	return self;
}


- (void)dealloc
{
	[sInUseTextures removeObjectForKey:key];
	
	if (loaded)
	{
		if (data.loaded.bytes != NULL) free(data.loaded.bytes);
		if (data.loaded.textureName != 0)  glDeleteTextures(1, &data.loaded.textureName);
	}
	else
	{
		[data.loading.loader release];
	}
	
	[super dealloc];
}


- (NSString *)description
{
	NSString				*stateDesc = nil;
	
	if (loaded)
	{
		if (data.loaded.bytes != NULL)
		{
			stateDesc = [NSString stringWithFormat:@"%u x %u", width, height];
		}
		else
		{
			stateDesc = @"LOAD ERROR";
		}
	}
	else
	{
		stateDesc = @"loading";
	}
	
	return [NSString stringWithFormat:@"<%@ %p{%@, %@}", [self className], self, key, stateDesc];
}


- (void)apply
{
	OOTextureLoader			*loader = nil;
	uint32_t				options;
	
	if (EXPECT_NOT(!loaded))
	{
		loader = data.loading.loader;
		options = data.loading.options;
		
		if ([loader getResult:&data.loaded.bytes width:&width height:&height])
		{
			// TODO: set up texture here
		}
		else
		{
			data.loaded.textureName = 0;
		}
		
		[loader release];
		loaded = YES;
	}
	
	glBindTexture(GL_TEXTURE_2D, data.loaded.textureName);
}

@end
