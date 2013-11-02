/*

OOTexture.h

Load, track and manage textures. In general, this should be used through an
OOMaterial.

Note: OOTexture is abstract. The factory methods return instances of
OOConcreteTexture, but special-case implementations are possible.


Copyright (C) 2007-2013 Jens Ayton and contributors

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

#import <Foundation/Foundation.h>

#import "OOOpenGL.h"
#import "OOPixMap.h"
#import "OOWeakReference.h"

@class OOTextureLoader, OOTextureGenerator;


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
	kOOTextureNoFNFMessage			= 0x0100UL,	// Don't log file not found error
	kOOTextureNeverScale			= 0x0200UL,	// Don't rescale texture, even if rect textures are not available. This *must not* be used for regular textures, but may be passed to OOTextureLoader when being used for other purposes.
	kOOTextureAlphaMask				= 0x0400UL,	// Single-channel texture should be GL_ALPHA, not GL_LUMINANCE. No effect for multi-channel textures.
	kOOTextureAllowCubeMap			= 0x0800UL,
	
	kOOTextureExtractChannelMask	= 0x7000UL,
	kOOTextureExtractChannelNone	= 0x0000UL,
	kOOTextureExtractChannelR		= 0x1000UL,	// 001
	kOOTextureExtractChannelG		= 0x3000UL,	// 011
	kOOTextureExtractChannelB		= 0x5000UL,	// 101
	kOOTextureExtractChannelA		= 0x7000UL,	// 111
	
	kOOTextureMinFilterMask			= 0x0003UL,
	kOOTextureMagFilterMask			= 0x0004UL,
	kOOTextureFlagsMask				= ~(kOOTextureMinFilterMask | kOOTextureMagFilterMask),
	
	kOOTextureDefaultOptions		= kOOTextureMinFilterDefault | kOOTextureMagFilterLinear,
	
	kOOTextureDefinedFlags			= kOOTextureMinFilterMask | kOOTextureMagFilterMask
									| kOOTextureNoShrink
									| kOOTextureAllowRectTexture
									| kOOTextureAllowCubeMap
									| kOOTextureRepeatS
									| kOOTextureRepeatT
									| kOOTextureNoFNFMessage
									| kOOTextureNeverScale
									| kOOTextureAlphaMask
									| kOOTextureExtractChannelMask,
	
	kOOTextureFlagsAllowedForRectangleTexture =
									kOOTextureDefinedFlags & ~(kOOTextureRepeatS | kOOTextureRepeatT),
	kOOTextureFlagsAllowedForCubeMap =
									kOOTextureDefinedFlags & ~(kOOTextureRepeatS | kOOTextureRepeatT)
};


typedef uint32_t OOTextureFlags;


#define kOOTextureDefaultAnisotropy		0.5
#define kOOTextureDefaultLODBias		-0.25


enum
{
	kOOTextureDataInvalid			= kOOPixMapInvalidFormat,
	
	kOOTextureDataRGBA				= kOOPixMapRGBA,			// GL_RGBA
	kOOTextureDataGrayscale			= kOOPixMapGrayscale,		// GL_LUMINANCE (or GL_ALPHA with kOOTextureAlphaMask)
	kOOTextureDataGrayscaleAlpha	= kOOPixMapGrayscaleAlpha	// GL_LUMINANCE_ALPHA
};
typedef OOPixMapFormat OOTextureDataFormat;


@interface OOTexture: OOWeakRefObject
{
#ifndef NDEBUG
@protected
	BOOL						_trace;
#endif
}

/*	Load a texture, looking in Textures directories.
	
	NOTE: anisotropy is normalized to the range [0, 1]. 1 means as high an
	anisotropy setting as the hardware supports.
	
	This method may change; +textureWithConfiguration is generally more
	appropriate. 
*/
+ (id) textureWithName:(NSString *)name
			  inFolder:(NSString *)directory
			   options:(OOTextureFlags)options
			anisotropy:(GLfloat)anisotropy
			   lodBias:(GLfloat)lodBias;

/*	Equivalent to textureWithName:name
						 inFolder:directory
						  options:kOOTextureDefaultOptions
					   anisotropy:kOOTextureDefaultAnisotropy
						  lodBias:kOOTextureDefaultLODBias
*/
+ (id) textureWithName:(NSString *)name
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
		cube_map			(boolean)
		anisotropy			(real)
		texture_LOD_bias	(real)
		extract_channel		(string, one of "r", "g", "b", "a")
 */
+ (id) textureWithConfiguration:(id)configuration;
+ (id) textureWithConfiguration:(id)configuration extraOptions:(OOTextureFlags)extraOptions;

/*	Return the "null texture", a texture object representing an empty texture.
	Applying the null texture is equivalent to calling [OOTexture applyNone].
*/
+ (id) nullTexture;

/*	Load a texture from a generator.
*/
+ (id) textureWithGenerator:(OOTextureGenerator *)generator;


/*	Bind the texture to the current texture unit.
	This will block until loading is completed.
*/
- (void) apply;

+ (void) applyNone;

/*	Ensure texture is loaded. This is required because setting up textures
	inside display lists isn't allowed.
*/
- (void) ensureFinishedLoading;

/*	Check whether a texture has loaded. NOTE: this does not do the setup that
	-ensureFinishedLoading does, so -ensureFinishedLoading is still required
	before using the texture in a display list.
*/
- (BOOL) isFinishedLoading;

- (NSString *) cacheKey;

/*	Dimensions in pixels.
	This will block until loading is completed.
*/
- (NSSize) dimensions;

/*	Original file dimensions in pixels.
	This will block until loading is completed.
*/
- (NSSize) originalDimensions;

/*	Check whether texture is mip-mapped.
	This will block until loading is completed.
*/
- (BOOL) isMipMapped;

/*	Create a new pixmap with a copy of the texture data. The caller is
	responsible for free()ing the resulting buffer.
*/
- (OOPixMap) copyPixMapRepresentation;

/*	Identify special texture types.
*/
- (BOOL) isRectangleTexture;
- (BOOL) isCubeMap;


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
- (NSSize) texCoordsScale;

/*	OpenGL texture name.
	Not reccomended, but required for legacy TextureStore.
*/
- (GLint) glTextureName;

//	Forget all cached textures so new texture objects will reload.
+ (void) clearCache;

// Called by OOGraphicsResetManager as necessary.
+ (void) rebindAllTextures;

#ifndef NDEBUG
- (void) setTrace:(BOOL)trace;

+ (NSArray *) cachedTexturesByAge;
+ (NSSet *) allTextures;

- (size_t) dataSize;

- (NSString *) name;
#endif

@end


@interface NSDictionary (OOTextureConveniences)
- (NSDictionary *) oo_textureSpecifierForKey:(id)key defaultName:(NSString *)name;
@end

@interface NSArray (OOTextureConveniences)
- (NSDictionary *) oo_textureSpecifierAtIndex:(unsigned)index defaultName:(NSString *)name;
@end

NSDictionary *OOTextureSpecFromObject(id object, NSString *defaultName);


uint8_t OOTextureComponentsForFormat(OOTextureDataFormat format);


BOOL OOCubeMapsAvailable(void);


/*	OOInterpretTextureSpecifier()
	
	Interpret a texture specifier (string or dictionary). All out parameters
	may be NULL.
*/
BOOL OOInterpretTextureSpecifier(id specifier, NSString **outName, OOTextureFlags *outOptions, float *outAnisotropy, float *outLODBias, BOOL ignoreExtract);

/*	OOMakeTextureSpecifier()
	
	Create a texture specifier.
	
	If internal is used, an optimized form unsuitable for serialization may be
	used.
*/
NSDictionary *OOMakeTextureSpecifier(NSString *name, OOTextureFlags options, float anisotropy, float lodBias, BOOL internal);

/*	OOApplyTextureOptionDefaults()
	
	Replace all default/autmatic options with their current default values.
*/
OOTextureFlags OOApplyTextureOptionDefaults(OOTextureFlags options);



// Texture specifier keys.
extern NSString * const kOOTextureSpecifierNameKey;
extern NSString * const kOOTextureSpecifierSwizzleKey;
extern NSString * const kOOTextureSpecifierMinFilterKey;
extern NSString * const kOOTextureSpecifierMagFilterKey;
extern NSString * const kOOTextureSpecifierNoShrinkKey;
extern NSString * const kOOTextureSpecifierRepeatSKey;
extern NSString * const kOOTextureSpecifierRepeatTKey;
extern NSString * const kOOTextureSpecifierCubeMapKey;
extern NSString * const kOOTextureSpecifierAnisotropyKey;
extern NSString * const kOOTextureSpecifierLODBiasKey;

// Keys not used in texture setup, but put in specific texture specifiers to simplify plists.
extern NSString * const kOOTextureSpecifierModulateColorKey;
extern NSString * const kOOTextureSpecifierIlluminationModeKey;
extern NSString * const kOOTextureSpecifierSelfColorKey;
extern NSString * const kOOTextureSpecifierScaleFactorKey;
extern NSString * const kOOTextureSpecifierBindingKey;
