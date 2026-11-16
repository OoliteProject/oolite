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

#ifndef OOTEXTURE_H
#define OOTEXTURE_H

#import "OOFoundation.h"

#import "OOOpenGL.h"
#import "OOPixMap.h"
#import "OOWeakReference.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObjCRef.h"

@class OOTexture, OOTextureLoader, OOTextureGenerator;

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
        this header declared went through a transitional bridge until its last caller moved to the cxx_
        API below (bead oo-x3ni).

        Phase 3 (bead oo-whzh, proposed ADR-0056 amendments oo-smy and oo-2en): the C++ root of the
        textures. OOConcreteTexture and OONullTexture are still Objective-C subclasses of the facade
        (OOTexture+ObjCBridge.h), so the factories answer the Objective-C texture, retained, and a
        converted caller that keeps a texture keeps that object (amendment oo-smy item 4).
*/
namespace cxx {

class OOTexture : public oo::RefCounted {
public:
    OOTexture(); // was -init: every live texture is known, for graphics resets
    ~OOTexture() override;

    /*	Load a texture, looking in Textures directories.

            NOTE: anisotropy is normalized to the range [0, 1]. 1 means as high an
            anisotropy setting as the hardware supports.

            This method may change; textureWithConfiguration() is generally more
            appropriate. Null for no name, or a file that is not found.
    */
    static oo::ObjCRef<::OOTexture*> textureWithName(const std::optional<std::string>& name,
        const std::optional<std::string>& directory,
        OOTextureFlags options,
        GLfloat anisotropy,
        GLfloat lodBias);

    // Default options, anisotropy and LOD bias.
    static oo::ObjCRef<::OOTexture*> textureWithName(const std::optional<std::string>& name,
        const std::optional<std::string>& directory);

    /*	Load a texure, looking in Textures directories, using configuration
            dictionary or name. (That is, configuration may be either a dictionary
            or a string.) The keys are listed at +cxx_textureWithConfiguration: in
            OOTexture+ObjCBridge.h.
    */
    static oo::ObjCRef<::OOTexture*> textureWithConfiguration(const oo::PList& configuration);
    static oo::ObjCRef<::OOTexture*> textureWithConfiguration(const oo::PList& configuration, OOTextureFlags extraOptions);

    // The "null texture" (OONullTexture's shared instance).
    static oo::ObjCRef<::OOTexture*> nullTexture();

    // Load a texture from a generator, optionally forcing an enqueue.
    static oo::ObjCRef<::OOTexture*> textureWithGenerator(::OOTextureGenerator* generator);
    static oo::ObjCRef<::OOTexture*> textureWithGenerator(::OOTextureGenerator* generator, bool enqueue);

    // Bind the texture to the current texture unit. This will block until loading is completed.
    virtual void apply();

    static void applyNone();

    virtual void ensureFinishedLoading(); // Default: does nothing
    virtual bool isFinishedLoading(); // Default: true
    virtual std::optional<std::string> cacheKey(); // nullopt: not cacheable (the default)

    virtual NSSize dimensions(); // Subclass responsibility
    virtual NSSize originalDimensions(); // Default: dimensions()
    virtual bool isMipMapped(); // Subclass responsibility

    // A new pixmap with a copy of the texture data; the caller free()s it. Default: kOONullPixMap.
    virtual OOPixMap copyPixMapRepresentation();

    virtual bool isRectangleTexture(); // Default: false
    virtual bool isCubeMap(); // Default: false
    virtual NSSize texCoordsScale(); // Default: 1, 1
    virtual GLint glTextureName(); // Subclass responsibility

    // Forget all cached textures so new texture objects will reload.
    static void clearCache();

    // Called by OOGraphicsResetManager as necessary.
    static void rebindAllTextures();

#ifdef OO_DEBUG_MONITOR_ENABLED
    static std::vector<oo::ObjCRef<::OOTexture*>> cachedTexturesByAge(); // youngest first
    static std::vector<oo::ObjCRef<::OOTexture*>> allTextures(); // in no particular order

    size_t dataSize();

    virtual std::optional<std::string> name(); // nullopt: none (bead oo-3rb.289.4)

    void setTrace(bool trace);
#endif

    // What "%@" prints between the braces of <Class 0x...>{...} (OODescription.h), and the short
    // form's. None here, as OOObject answered.
    virtual std::optional<std::string> descriptionComponents() const;
    virtual std::optional<std::string> shortDescriptionComponents() const;

    // Internal: OOTextureInternal.h's subclass interface, for the subclasses.
    virtual void forceRebind(); // Subclass responsibility
    void addToCaches();
    void removeFromCaches(); // Must be called on destruction (while cacheKey() is still valid) for cacheable textures.
    static OOTexture* existingTextureForKey(const std::optional<std::string>& key); // borrowed; null for nullopt

protected:
#ifdef OO_DEBUG_MONITOR_ENABLED
    bool _trace = { }; // was the facade's @protected ivar; the subclasses read it (bead oo-qa7c)
#endif

private:
    static void checkExtensions();
};

} // namespace cxx

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

// Transitional: the Objective-C OOTexture, for callers and subclasses not yet converted.
// Deleted, with namespace cxx above, by the bridge's deletion bead.
#import "OOTexture+ObjCBridge.h"

#endif // OOTEXTURE_H
