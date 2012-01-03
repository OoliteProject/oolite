/*

OOConcreteTexture.h

Standard implementation of OOTexture. This is an implementation detail, use
OOTexture instead.


Copyright (C) 2007-2012 Jens Ayton and contributors

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

#import "OOTexture.h"


#define OOTEXTURE_RELOADABLE		1


@interface OOConcreteTexture: OOTexture
{
@private
#if OOTEXTURE_RELOADABLE
	NSString				*_path;
#endif
	NSString				*_key;
	uint8_t					_loaded: 1,
							_uploaded: 1,
#if GL_EXT_texture_rectangle
							_isRectTexture: 1,
#endif
#if OO_TEXTURE_CUBE_MAP
							_isCubeMap: 1,
#endif
							_valid: 1;
	uint8_t					_mipLevels;
	
	OOTextureLoader			*_loader;
	
	void					*_bytes;
	GLuint					_textureName;
	uint32_t				_width,
							_height,
							_originalWidth,
							_originalHeight;
	
	OOTextureDataFormat		_format;
	uint32_t				_options;
#if GL_EXT_texture_lod_bias
	GLfloat					_lodBias;
#endif
#if GL_EXT_texture_filter_anisotropic
	float					_anisotropy;
#endif
	
#ifndef NDEBUG
	NSString				*_name;
#endif
}

- (id) initWithLoader:(OOTextureLoader *)loader
				  key:(NSString *)key
			  options:(uint32_t)options
		   anisotropy:(GLfloat)anisotropy
			  lodBias:(GLfloat)lodBias;

- (id)initWithPath:(NSString *)path
			   key:(NSString *)key
		   options:(uint32_t)options
		anisotropy:(float)anisotropy
		   lodBias:(GLfloat)lodBias;

@end
