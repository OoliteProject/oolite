/*

OOTexture.h

Load, track and manage textures. In general, this should be used through an
OOMaterial.

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

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"

@class OOTextureLoader;


enum
{
	kOOTextureFilterDefault			= 0x0000UL,
	kOOTextureFilterLinear			= 0x0001UL,
	kOOTextureFilterNoMipMap		= 0x0002UL,
	kOOTextureFilterForceMipMap		= 0x0003UL,
	
	kOOTextureNoShrink				= 0x0010UL,
	kOOTextureIsNormalMap			= 0x0020UL,
	
	kOOTextureFilterMask			= 0x000FUL,
	kOOTextureFlagsMask				= ~kOOTextureFilterMask
};


@interface OOTexture: NSObject
{
	BOOL					loaded;
	NSString				*key;
	union
	{
		struct
		{
			OOTextureLoader			*loader;
			uint32_t				options;
		}						loading;
		struct
		{
			void					*bytes;
			GLuint					textureName;
		}						loaded;
	}						data;
	uint32_t				width,
							height;
}

/*	Load a texture, looking in Textures directories.
*/
+ (id)textureWithName:(NSString *)name options:(uint32_t)options;

/*	Load a texure, looking in Textures directories, using configuration
	dictionary.
	
	Supported keys:
		name (string, required)
		mipMap (string, optional, one of: "never", "default", "force")
		noFilter (boolean, optional)
		noShrink (boolean, optional)
		isNormalMap (boolean, optional)
*/
+ (id)textureWithConfiguration:(NSDictionary *)configuration;

/*	Bind the texture to the current texture unit.
*/
- (void)apply;

@end
