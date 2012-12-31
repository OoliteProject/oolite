/*

OOCombinedEmissionMapGenerator.h

Generator which renders a single RGB emission map from some combination of
emission_map, emission, illumination_map, illumination_color and
emission_and_illumination_map parameters.


Copyright (C) 2010-2013 Jens Ayton

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


#import "OOTextureGenerator.h"

@class OOColor;


@interface OOCombinedEmissionMapGenerator: OOTextureGenerator
{
@private
	NSString					*_cacheKey;
	
	OOPixMap					_emissionPx;
	OOPixMap					_diffusePx;
	OOPixMap					_illuminationPx;
	OOColor						*_emissionColor;
	OOColor						*_illuminationColor;
	BOOL						_isCombinedMap;
	
	uint32_t					_textureOptions;
	GLfloat						_anisotropy;
	GLfloat						_lodBias;
	
#ifndef NDEBUG
	NSString					*_emissionDesc;
	NSString					*_illuminationDesc;
	NSString					*_diffuseDesc;
#endif
}

// Note: these take ownership of diffuseMap's pixels.
- (id) initWithEmissionMap:(OOTextureLoader *)emissionMapLoader
			 emissionColor:(OOColor *)emissionColor
				diffuseMap:(OOTexture *)diffuseMap
			  diffuseColor:(OOColor *)diffuseColor
		   illuminationMap:(OOTextureLoader *)illuminationMapLoader
		 illuminationColor:(OOColor *)illuminationColor
		  optionsSpecifier:(NSDictionary *)spec;

- (id) initWithEmissionAndIlluminationMap:(OOTextureLoader *)emissionAndIlluminationMapLoader
							   diffuseMap:(OOTexture *)diffuseMap
							 diffuseColor:(OOColor *)diffuseColor
							emissionColor:(OOColor *)emissionColor
						illuminationColor:(OOColor *)illuminationColor
						 optionsSpecifier:(NSDictionary *)spec;

@end
