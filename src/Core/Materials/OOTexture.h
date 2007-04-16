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
	kOOTextureMinFilterDefault		= 0x0000UL,
	kOOTextureMinFilterNearest		= 0x0001UL,
	kOOTextureMinFilterLinear		= 0x0002UL,
	kOOTextureMinFilterMipMap		= 0x0003UL,
	
	kOOTextureMagFilterNearest		= 0x0010UL,
	kOOTextureMagFilterLinear		= 0x0020UL,
	
	kOOTextureNoShrink				= 0x0100UL,
	kOOTextureRepeatS				= 0x0200UL,
	kOOTextureRepeatT				= 0x0200UL,
	
	kOOTextureMinFilterMask			= 0x000FUL,
	kOOTextureMagFilterMask			= 0x00F0UL,
	kOOTextureFlagsMask				= ~(kOOTextureMinFilterMask | kOOTextureMagFilterMask),
	
	kOOTextureDefaultOptions		= kOOTextureMinFilterDefault | kOOTextureMagFilterLinear,
	kOOTextureDefinedFlags			= 0x0733UL
};


#define kOOTextureDefaultAnisotropy		0.5
#define kOOTextureDefaultLODBias		-0.25


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
#if GL_EXT_texture_filter_anisotropic
			float					anisotropy;
#endif
		}						loading;
		struct
		{
			void					*bytes;
			GLuint					textureName;
			uint32_t				width,
									height;
		}						loaded;
	}						data;
#if GL_EXT_texture_lod_bias
	GLfloat					lodBias;	// Used both before and after loading
#endif
}

/*	Load a texture, looking in Textures directories.
	
	NOTE: anisotropy is normalized to the range [0, 1]. 1 means as high an
	anisotropy setting as the hardware supports.
	
	This method may change; +textureWithConfiguration is generally more
	appropriate. 
*/
+ (id)textureWithName:(NSString *)name
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias;

/*	Equivalent to textureWithName:name
						  options:kOOTextureDefaultOptions
					   anisotropy:kOOTextureDefaultAnisotropy
						  lodBias:kOOTextureDefaultLODBias
*/
+ (id)textureWithName:(NSString *)name;

/*	Load a texure, looking in Textures directories, using configuration
	dictionary or name. (That is, configuration may be either an NSDictionary
	or an NSString.)
	
	Supported keys:
		name				(string, required)
		min_filter			(string, one of "default", "nearest", "linear", "mipmap")
		max_filter			(string, one of "default", "nearest", "linear")
		noShrink			(boolean)
		repeat_s			(boolean)
		repeat_t			(boolean)
		anisotropy			(real)
		texture_LOD_bias	(real)
*/
+ (id)textureWithConfiguration:(id)configuration;

/*	Bind the texture to the current texture unit.
*/
- (void)apply;

/*	Ensure texture is loaded. This is required because setting up textures
	inside display lists isn't allowed.
*/
- (void)ensureFinishedLoading;

@end
