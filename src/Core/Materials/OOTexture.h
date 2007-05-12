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

#import <Foundation/Foundation.h>
#import "OOOpenGL.h"

@class OOTextureLoader;


enum
{
	kOOTextureMinFilterDefault		= 0x0000UL,
	kOOTextureMinFilterNearest		= 0x0001UL,
	kOOTextureMinFilterLinear		= 0x0002UL,
	kOOTextureMinFilterMipMap		= 0x0003UL,
	
	kOOTextureMagFilterNearest		= 0x0000UL,
	kOOTextureMagFilterLinear		= 0x0004UL,
	
	kOOTextureNoShrink				= 0x0010UL,
	kOOTextureRepeatS				= 0x0020UL,
	kOOTextureRepeatT				= 0x0040UL,
	kOOTextureAllowRectTexture		= 0x0080UL,	// Indicates that GL_TEXTURE_RECTANGLE_EXT may be used instead of GL_TEXTURE_2D. See -texCoordsScale for a discussion of rectangle textures.
	kOOTextureSearchInImages		= 0x0100UL,	// Search in Images directories rather than Textures directories.
	
	kOOTextureMinFilterMask			= 0x0003UL,
	kOOTextureMagFilterMask			= 0x0004UL,
	kOOTextureFlagsMask				= ~(kOOTextureMinFilterMask | kOOTextureMagFilterMask),
	
	kOOTextureDefaultOptions		= kOOTextureMinFilterDefault | kOOTextureMagFilterLinear,
	
	kOOTextureDefinedFlags			= kOOTextureMinFilterMask | kOOTextureMagFilterMask
									| kOOTextureNoShrink
#if GL_EXT_texture_rectangle
									| kOOTextureAllowRectTexture
#endif
									| kOOTextureRepeatS
									| kOOTextureRepeatT,
	
	kOOTextureFlagsAllowedForRectangleTexture =
									kOOTextureDefinedFlags & ~(kOOTextureRepeatS | kOOTextureRepeatT)
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
#if GL_EXT_texture_rectangle
			BOOL					isRectTexture;
#endif
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
			 inFolder:(NSString*)directory
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias;

/*	Equivalent to textureWithName:name
						 inFolder:directory
						  options:kOOTextureDefaultOptions
					   anisotropy:kOOTextureDefaultAnisotropy
						  lodBias:kOOTextureDefaultLODBias
*/
+ (id)textureWithName:(NSString *)name
			 inFolder:(NSString*)directory;

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
	This will block until loading is completed.
*/
- (void)apply;

+ (void)applyNone;

/*	Ensure texture is loaded. This is required because setting up textures
	inside display lists isn't allowed.
*/
- (void)ensureFinishedLoading;

/*	Dimensions in pixels.
	This will block until loading is completed.
*/
- (NSSize)dimensions;


/*	Dimensions in texture coordinates.
	
	If kOOTextureAllowRectTexture is set, and GL_EXT_texture_rectangle is
	available, textures whose dimensions are not powers of two will be loaded
	as rectangle textures. Rectangle textures use unnormalized co-ordinates;
	that is, co-oridinates range from 0 to the actual size of the texture
	rather than 0 to 1. Thus, for rectangle textures, -texCoordsScale returns
	-dimensions (with the required wait for loading) for a rectangle texture.
	For non-rectangle textures, (1, 1) is returned without delay. If the
	texture has power-of-two dimensions, it will be loaded as a normal
	texture.
	
	Rectangle textures have additional limitations: kOOTextureMinFilterMipMap
	is not supported (kOOTextureMinFilterLinear will be used instead), and
	kOOTextureRepeatS/kOOTextureRepeatT will be ignored. 
	
	Note that 'rectangle texture' is a misnomer; non-rectangle textures may
	be rectangular, as long as their sides are powers of two. Non-power-of-two
	textures would be more descriptive, but this phrase is used for the
	extension that allows 'normal' textures to have non-power-of-two sides
	without additional restrictions. It is intended that OOTexture should
	support this in future, but this shouldn’t affect the interface, only
	avoid the scaling-to-power-of-two stage.
*/
- (NSSize)texCoordsScale;

/*	OpenGL texture name.
	Not reccomended, but required for legacy TextureStore.
*/
- (GLint)glTextureName;

//	Forget all cached textures so new texture objects will reload.
+ (void)clearCache;

@end


@interface NSDictionary (OOTextureConveniences)
// Returns either a dictionary or a string.
- (id)textureSpecifierForKey:(id)key defaultName:(NSString *)name;
@end

@interface NSArray (OOTextureConveniences)
// Returns either a dictionary or a string.
- (id)textureSpecifierAtIndex:(unsigned)index defaultName:(NSString *)name;
@end

id OOTextureSpecFromObject(id object, NSString *defaultName);
