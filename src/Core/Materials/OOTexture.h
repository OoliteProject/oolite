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

#pragma once

#import "OOFoundation.h"

#import "OOOpenGL.h"
#import "OOPixMap.h"
#import "OOWeakReference.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOTextureLoader, OOTextureGenerator;

enum {
    kOOTextureMinFilterDefault = 0x000000UL,
    kOOTextureMinFilterNearest = 0x000001UL,
    kOOTextureMinFilterLinear = 0x000002UL,
    kOOTextureMinFilterMipMap = 0x000003UL,

    kOOTextureMagFilterNearest = 0x000000UL,
    kOOTextureMagFilterLinear = 0x000004UL,

    kOOTextureNoShrink = 0x000010UL,
    kOOTextureExtraShrink = 0x000020UL,
    kOOTextureRepeatS = 0x000040UL,
    kOOTextureRepeatT = 0x000080UL,
    kOOTextureAllowRectTexture = 0x000100UL, // Indicates that GL_TEXTURE_RECTANGLE_EXT may be used instead of GL_TEXTURE_2D. See -texCoordsScale for a discussion of rectangle textures.
    kOOTextureNoFNFMessage = 0x000200UL, // Don't log file not found error
    kOOTextureNeverScale = 0x000400UL, // Don't rescale texture, even if rect textures are not available. This *must not* be used for regular textures, but may be passed to OOTextureLoader when being used for other purposes.
    kOOTextureAlphaMask = 0x000800UL, // Single-channel texture should be GL_ALPHA, not GL_LUMINANCE. No effect for multi-channel textures.
    kOOTextureAllowCubeMap = 0x001000UL,

    kOOTextureSRGBA = 0x002000UL,

    kOOTextureExtractChannelMask = 0x700000UL,
    kOOTextureExtractChannelNone = 0x000000UL,
    kOOTextureExtractChannelR = 0x100000UL, // 001
    kOOTextureExtractChannelG = 0x300000UL, // 011
    kOOTextureExtractChannelB = 0x500000UL, // 101
    kOOTextureExtractChannelA = 0x700000UL, // 111

    kOOTextureMinFilterMask = 0x000003UL,
    kOOTextureMagFilterMask = 0x000004UL,
    kOOTextureFlagsMask = ~(kOOTextureMinFilterMask | kOOTextureMagFilterMask),

    kOOTextureDefaultOptions = kOOTextureMinFilterDefault | kOOTextureMagFilterLinear,

    kOOTextureDefinedFlags = kOOTextureMinFilterMask | kOOTextureMagFilterMask
        | kOOTextureNoShrink
        | kOOTextureExtraShrink
        | kOOTextureAllowRectTexture
        | kOOTextureAllowCubeMap
        | kOOTextureRepeatS
        | kOOTextureRepeatT
        | kOOTextureNoFNFMessage
        | kOOTextureNeverScale
        | kOOTextureAlphaMask
        | kOOTextureSRGBA
        | kOOTextureExtractChannelMask,

    kOOTextureFlagsAllowedForRectangleTexture = kOOTextureDefinedFlags & ~(kOOTextureRepeatS | kOOTextureRepeatT),
    kOOTextureFlagsAllowedForCubeMap = kOOTextureDefinedFlags & ~(kOOTextureRepeatS | kOOTextureRepeatT)
};

typedef uint32_t OOTextureFlags;

#define kOOTextureDefaultAnisotropy 0.5
#define kOOTextureDefaultLODBias -0.25

enum {
    kOOTextureDataInvalid = kOOPixMapInvalidFormat,

    kOOTextureDataRGBA = kOOPixMapRGBA, // GL_RGBA
    kOOTextureDataGrayscale = kOOPixMapGrayscale, // GL_LUMINANCE (or GL_ALPHA with kOOTextureAlphaMask)
    kOOTextureDataGrayscaleAlpha = kOOPixMapGrayscaleAlpha // GL_LUMINANCE_ALPHA
};
typedef OOPixMapFormat OOTextureDataFormat;

/*	Foundation sweep (proposed ADR-0043 Amendments 1-2, bead oo-japz): names and folders are UTF-8
        std::strings (std::optional where the old code accepted nil); texture specifiers and
        configurations are oo::PList (a string or a dictionary; null = nil). The Foundation-typed API
        this header declared moved to OOTexture+FoundationBridge.h (transitional), forwarding to the
        cxx_ API below.
*/
@interface OOTexture : OOWeakRefObject {
#ifdef OO_DEBUG_MONITOR_ENABLED
@protected
    BOOL _trace;
#endif
}

/*	Load a texture, looking in Textures directories.

        NOTE: anisotropy is normalized to the range [0, 1]. 1 means as high an
        anisotropy setting as the hardware supports.

        This method may change; +textureWithConfiguration is generally more
        appropriate.
*/
+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory
                  options:(OOTextureFlags)options
               anisotropy:(GLfloat)anisotropy
                  lodBias:(GLfloat)lodBias;

/*	Equivalent to cxx_textureWithName:name
                                                         inFolder:directory
                                                          options:kOOTextureDefaultOptions
                                                   anisotropy:kOOTextureDefaultAnisotropy
                                                          lodBias:kOOTextureDefaultLODBias
*/
+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory;

/*	Load a texure, looking in Textures directories, using configuration
        dictionary or name. (That is, configuration may be either a dictionary
        or a string.)

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
+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration;
+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration extraOptions:(OOTextureFlags)extraOptions;

/*	Return the "null texture", a texture object representing an empty texture.
        Applying the null texture is equivalent to calling [OOTexture applyNone].
*/
+ (id)nullTexture;

/*	Load a texture from a generator.
 */
+ (id)textureWithGenerator:(OOTextureGenerator*)generator;

//	Load a texture from a generator with option to force an enqueue
+ (id)textureWithGenerator:(OOTextureGenerator*)generator enqueue:(BOOL)enqueue;

/*	Bind the texture to the current texture unit.
        This will block until loading is completed.
*/
- (void)apply;

+ (void)applyNone;

/*	Ensure texture is loaded. This is required because setting up textures
        inside display lists isn't allowed.
*/
- (void)ensureFinishedLoading;

/*	Check whether a texture has loaded. NOTE: this does not do the setup that
        -ensureFinishedLoading does, so -ensureFinishedLoading is still required
        before using the texture in a display list.
*/
- (BOOL)isFinishedLoading;

- (id)cacheKey; // an Objective-C string, or nil. Shared selector (proposed ADR-0043).

/*	Dimensions in pixels.
        This will block until loading is completed.
*/
- (NSSize)dimensions;

/*	Original file dimensions in pixels.
        This will block until loading is completed.
*/
- (NSSize)originalDimensions;

/*	Check whether texture is mip-mapped.
        This will block until loading is completed.
*/
- (BOOL)isMipMapped;

/*	Create a new pixmap with a copy of the texture data. The caller is
        responsible for free()ing the resulting buffer.
*/
- (OOPixMap)copyPixMapRepresentation;

/*	Identify special texture types.
 */
- (BOOL)isRectangleTexture;
- (BOOL)isCubeMap;

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

// Called by OOGraphicsResetManager as necessary.
+ (void)rebindAllTextures;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)setTrace:(BOOL)trace;

+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_cachedTexturesByAge; // youngest first
+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures; // in no particular order

- (size_t)dataSize;

- (id)name; // an Objective-C string. Shared selector (proposed ADR-0043).
#endif

@end

/*	The specifier for object (a string, a dictionary, or null for the default name), or null.
        A dictionary without a string "name" gets defaultName, if given.
*/
oo::PList cxx_OOTextureSpecFromObject(const oo::PList& object, const std::optional<std::string>& defaultName);

uint8_t OOTextureComponentsForFormat(OOTextureDataFormat format);

BOOL OOCubeMapsAvailable(void);

/*	cxx_OOInterpretTextureSpecifier()

        Interpret a texture specifier (string or dictionary). All out parameters
        may be NULL.
*/
BOOL cxx_OOInterpretTextureSpecifier(const oo::PList& specifier, std::string* outName, OOTextureFlags* outOptions, float* outAnisotropy, float* outLODBias, BOOL ignoreExtract);

/*	cxx_OOMakeTextureSpecifier()

        Create a texture specifier (a dictionary).

        If internal is used, an optimized form unsuitable for serialization may be
        used.
*/
oo::PList cxx_OOMakeTextureSpecifier(const std::string& name, OOTextureFlags options, float anisotropy, float lodBias, BOOL internal);

/*	OOApplyTextureOptionDefaults()

        Replace all default/automatic options with their current default values.
*/
OOTextureFlags OOApplyTextureOptionDefaults(OOTextureFlags options);

// Texture specifier keys.
inline constexpr const char* cxx_kOOTextureSpecifierNameKey = "name";
inline constexpr const char* cxx_kOOTextureSpecifierSwizzleKey = "extract_channel";
inline constexpr const char* cxx_kOOTextureSpecifierMinFilterKey = "min_filter";
inline constexpr const char* cxx_kOOTextureSpecifierMagFilterKey = "mag_filter";
inline constexpr const char* cxx_kOOTextureSpecifierNoShrinkKey = "no_shrink";
inline constexpr const char* cxx_kOOTextureSpecifierExtraShrinkKey = "extra_shrink";
inline constexpr const char* cxx_kOOTextureSpecifierRepeatSKey = "repeat_s";
inline constexpr const char* cxx_kOOTextureSpecifierRepeatTKey = "repeat_t";
inline constexpr const char* cxx_kOOTextureSpecifierCubeMapKey = "cube_map";
inline constexpr const char* cxx_kOOTextureSpecifierAnisotropyKey = "anisotropy";
inline constexpr const char* cxx_kOOTextureSpecifierLODBiasKey = "texture_LOD_bias";

// Keys not used in texture setup, but put in specific texture specifiers to simplify plists.
inline constexpr const char* cxx_kOOTextureSpecifierModulateColorKey = "color";
inline constexpr const char* cxx_kOOTextureSpecifierIlluminationModeKey = "illumination_mode";
inline constexpr const char* cxx_kOOTextureSpecifierSelfColorKey = "self_color";
inline constexpr const char* cxx_kOOTextureSpecifierScaleFactorKey = "scale_factor";
inline constexpr const char* cxx_kOOTextureSpecifierBindingKey = "binding";

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed API this header
        declared before bead oo-japz, forwarding to the cxx_ API above, so unmigrated callers compile
        unchanged. Callers move to the cxx_ API in their own sweep beads; the bridge goes in its own bead.
*/
#import "OOTexture+FoundationBridge.h"
