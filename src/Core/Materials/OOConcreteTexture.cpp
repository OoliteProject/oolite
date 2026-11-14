/*

        OOConcreteTexture.m

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

#include "OOConcreteTexture.h"
#include "OOTextureInternal.h"

#include "OOTextureGenerator.h"
#include "OOTextureLoader.h"

#include "OOCPUInfo.h"
#include "OOLogging.h"
#include "OOMacroOpenGL.h"
#include "OOOpenGLExtensionManager.h"
#include "OOPixMap.h"
#include "ResourceManager.h"
#include "Universe.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

#ifdef OO_DEBUG_MONITOR_ENABLED
#include "OOTextureGenerator.h"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOException.h"
#endif

#if OOLITE_BIG_ENDIAN
#define RGBA_IMAGE_TYPE GL_UNSIGNED_INT_8_8_8_8_REV
#elif OOLITE_LITTLE_ENDIAN
#define RGBA_IMAGE_TYPE GL_UNSIGNED_BYTE
#else
#error Neither OOLITE_BIG_ENDIAN nor OOLITE_LITTLE_ENDIAN is defined as nonzero!
#endif

static BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, GLenum* outFormat, GLenum* outInternalFormat, GLenum* outType);

OOConcreteTexture::OOConcreteTexture(OOTextureLoader* loader,
    const std::optional<std::string>& key,
    uint32_t options,
    GLfloat anisotropy,
    GLfloat lodBias)
{
    _loader = oo::Ref<OOTextureLoader>(loader);
    _options = options;

#if GL_EXT_texture_filter_anisotropic
    _anisotropy = OOClamp_0_1_f(anisotropy) * gOOTextureInfo.anisotropyScale;
#endif
#if GL_EXT_texture_lod_bias
    _lodBias = lodBias;
#endif

#ifdef OO_DEBUG_MONITOR_ENABLED
    // "<" + [loader class] + ">" of a generator: the C++ class's name since bead oo-9ht.118 deleted
    // the generator's facade (ADR-0056 amendment oo-9ht.114 item 4).
    if (dynamic_cast<OOTextureGenerator*>(loader) != nullptr) {
        _name = "<" + loader->className() + ">";
    }
#endif

    _key = key;
}

oo::Ref<OOConcreteTexture> OOConcreteTexture::initWithLoader(OOTextureLoader* loader,
    const std::optional<std::string>& key,
    uint32_t options,
    GLfloat anisotropy,
    GLfloat lodBias)
{
    if (loader == nullptr) {
        return nullptr;
    }

    oo::Ref<OOConcreteTexture> self = oo::adopt(new OOConcreteTexture(loader, key, options, anisotropy, lodBias));

    self->addToCaches();

    return self;
}

oo::Ref<OOConcreteTexture> OOConcreteTexture::initWithPath(const std::string& path,
    const std::optional<std::string>& key,
    uint32_t options,
    float anisotropy,
    GLfloat lodBias)
{
    const oo::Ref<OOTextureLoader> loader = OOTextureLoader::loaderWithPath(path, options);
    if (loader == nullptr) {
        return nullptr;
    }

    oo::Ref<OOConcreteTexture> self = initWithLoader(loader.get(), key, options, anisotropy, lodBias);
    if (self != nullptr) {
#if OOTEXTURE_RELOADABLE
        self->_path = path;
#endif
    }

    return self;
}

OOConcreteTexture::~OOConcreteTexture()
{
#ifdef OO_DEBUG_MONITOR_ENABLED
    // The Objective-C object has gone: the C++ object's address is the one printed.
    OO_LOG(_trace ? "texture.allocTrace.dealloc" : "texture.dealloc", "Deallocating and uncaching texture {}", oo::str::pointerDescription(this));
#endif

#if OOTEXTURE_RELOADABLE
    _path = std::nullopt;
#endif

    if (_loaded) {
        if (_textureName != 0) {
            OO_ENTER_OPENGL();
            OOGL(glDeleteTextures(1, &_textureName));
            _textureName = 0;
        }
        free(_bytes);
        _bytes = NULL;
    }

#ifndef OOTEXTURE_NO_CACHE
    removeFromCaches();
    _key = std::nullopt;
#endif

    _loader = nullptr;

#ifdef OO_DEBUG_MONITOR_ENABLED
    _name = std::nullopt;
#endif
}

std::optional<std::string> OOConcreteTexture::descriptionComponents() const
{
    std::string stateDesc;

    if (_loaded) {
        if (_valid) {
            stateDesc = oo::str::format("%u x %u", _width, _height);
        } else {
            stateDesc = "LOAD ERROR";
        }
    } else {
        stateDesc = "loading";
    }

    return _key.value_or("(null)") + ", " + stateDesc; // "%@, %@": nil printed (null)
}

std::optional<std::string> OOConcreteTexture::shortDescriptionComponents() const
{
    return _key;
}

#ifdef OO_DEBUG_MONITOR_ENABLED
std::optional<std::string> OOConcreteTexture::name()
{
    if (_name.has_value())
        return _name;

    // -lastPathComponent of a nil path is nil, and so is the name.
#if OOTEXTURE_RELOADABLE
    if (!_path.has_value())
        return std::nullopt;
    std::string name = oo::str::lastPathComponent(*_path);
#else
    const std::optional<std::string> key = cacheKey();
    if (!key.has_value())
        return std::nullopt;
    const std::string::size_type colon = key->find(':');
    const std::string head = colon == std::string::npos ? *key : key->substr(0, colon);
    std::string name = oo::str::lastPathComponent(head);
#endif

    const char* channelSuffix = nullptr;
    switch (_options & kOOTextureExtractChannelMask) {
    case kOOTextureExtractChannelR:
        channelSuffix = ":r";
        break;

    case kOOTextureExtractChannelG:
        channelSuffix = ":g";
        break;

    case kOOTextureExtractChannelB:
        channelSuffix = ":b";
        break;

    case kOOTextureExtractChannelA:
        channelSuffix = ":a";
        break;
    }

    if (channelSuffix != nullptr)
        name += channelSuffix;

    return name;
}
#endif

void OOConcreteTexture::apply()
{
    OO_ENTER_OPENGL();

    if (EXPECT_NOT(!_loaded))
        setUpTexture();
    else if (EXPECT_NOT(!_uploaded))
        uploadTexture();
    else
        OOGL(glBindTexture(glTextureTarget(), _textureName));

#if GL_EXT_texture_lod_bias
    if (gOOTextureInfo.textureLODBiasAvailable)
        OOGL(glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, _lodBias));
#endif
}

void OOConcreteTexture::ensureFinishedLoading()
{
    if (!_loaded)
        setUpTexture();
}

bool OOConcreteTexture::isFinishedLoading()
{
    return _loaded || (_loader != nullptr && _loader->isReady()); // a message to nil answered NO
}

std::optional<std::string> OOConcreteTexture::cacheKey()
{
    return _key;
}

NSSize OOConcreteTexture::dimensions()
{
    ensureFinishedLoading();

    return NSMakeSize(_width, _height);
}

NSSize OOConcreteTexture::originalDimensions()
{
    ensureFinishedLoading();

    return NSMakeSize(_originalWidth, _originalHeight);
}

bool OOConcreteTexture::isMipMapped()
{
    ensureFinishedLoading();

    return _mipLevels != 0;
}

OOPixMap OOConcreteTexture::copyPixMapRepresentation()
{
    ensureFinishedLoading();

    OOPixMap px = kOONullPixMap;

    if (_bytes != NULL) {
        // If possible, just copy our existing buffer.
        px = OOMakePixMap(_bytes, _width, _height, _format, 0, 0);
        px = OODuplicatePixMap(px, 0);
    }
#if OOTEXTURE_RELOADABLE
    else {
        // Otherwise, read it back from OpenGL.
        OO_ENTER_OPENGL();

        GLenum format, internalFormat, type;
        if (!DecodeFormat(_format, _options, &format, &internalFormat, &type)) {
            return kOONullPixMap;
        }

        if (!isCubeMap()) {

            px = OOAllocatePixMap(_width, _height, _format, 0, 0);
            if (!OOIsValidPixMap(px))
                return kOONullPixMap;

            glGetTexImage(GL_TEXTURE_2D, 0, format, type, px.pixels);
        }
#if OO_TEXTURE_CUBE_MAP
        else {
            px = OOAllocatePixMap(_width, _width * 6, _format, 0, 0);
            if (!OOIsValidPixMap(px))
                return kOONullPixMap;
            uint8_t* pixels = (uint8_t*)px.pixels;

            unsigned i;
            for (i = 0; i < 6; i++) {
                glGetTexImage(GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, format, type, pixels);
                pixels += OOPixMapBytesPerPixelForFormat(_format) * _width * _width;
            }
        }
#endif
    }
#endif

    return px;
}

bool OOConcreteTexture::isRectangleTexture()
{
#if GL_EXT_texture_rectangle
    return _isRectTexture;
#else
    return false;
#endif
}

bool OOConcreteTexture::isCubeMap()
{
#if OO_TEXTURE_CUBE_MAP
    return _isCubeMap;
#else
    return false;
#endif
}

NSSize OOConcreteTexture::texCoordsScale()
{
#if GL_EXT_texture_rectangle
    if (_loaded) {
        if (!_isRectTexture) {
            return NSMakeSize(1.0f, 1.0f);
        } else {
            return NSMakeSize(_width, _height);
        }
    } else {
        // Not loaded
        if (!(_options & kOOTextureAllowRectTexture)) {
            return NSMakeSize(1.0f, 1.0f);
        } else {
            // Finishing may clear the rectangle texture flag (if the texture turns out to be POT)
            ensureFinishedLoading();
            return texCoordsScale();
        }
    }
#else
    return NSMakeSize(1.0f, 1.0f);
#endif
}

GLint OOConcreteTexture::glTextureName()
{
    ensureFinishedLoading();

    return _textureName;
}

// Private (was the (Private) category).

void OOConcreteTexture::setUpTexture()
{
    OOPixMap pm;

    // This will block until loading is completed, if necessary.
    if (_loader != nullptr && _loader->getResult(&pm, &_format, &_originalWidth, &_originalHeight)) // a message to nil answered NO
    {
        _bytes = pm.pixels;
        _width = pm.width;
        _height = pm.height;

#if OO_TEXTURE_CUBE_MAP
        if (_options & kOOTextureAllowCubeMap && _height == _width * 6 && gOOTextureInfo.cubeMapAvailable) {
            _isCubeMap = YES;
        }
#endif

#if defined(OO_DEBUG_MONITOR_ENABLED) && OOTEXTURE_RELOADABLE
        if (_trace) {
            static unsigned dumpID = 0;
            const std::string name = oo::str::format("tex dump %u \"", ++dumpID) + this->name().value_or("(null)") + "\"";
            OO_LOG("texture.trace.dump", "Dumped traced texture {} to '{}.png'", description(), name);
            OODumpPixMap(pm, name);
        }
#endif

        uploadTexture();
    } else {
        _textureName = 0;
        _valid = NO;
        _uploaded = YES;
    }

    _loaded = YES;

    _loader = nullptr;
}

void OOConcreteTexture::uploadTexture()
{
    GLint filter;
    BOOL mipMap = NO;

    OO_ENTER_OPENGL();

    if (!_uploaded) {
        GLenum texTarget = glTextureTarget();

        OOGL(glGenTextures(1, &_textureName));
        OOGL(glBindTexture(texTarget, _textureName));

        // Select wrap mode
        GLint clampMode = gOOTextureInfo.clampToEdgeAvailable ? GL_CLAMP_TO_EDGE : GL_CLAMP;
        GLint wrapS = (_options & kOOTextureRepeatS) ? GL_REPEAT : clampMode;
        GLint wrapT = (_options & kOOTextureRepeatT) ? GL_REPEAT : clampMode;

#if OO_TEXTURE_CUBE_MAP
        if (texTarget == GL_TEXTURE_CUBE_MAP) {
            wrapS = wrapT = clampMode;
            OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_R, clampMode));
        }
#endif

        OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_S, wrapS));
        OOGL(glTexParameteri(texTarget, GL_TEXTURE_WRAP_T, wrapT));

        // Select min filter
        filter = _options & kOOTextureMinFilterMask;
        if (filter == kOOTextureMinFilterNearest)
            filter = GL_NEAREST;
        else if (filter == kOOTextureMinFilterMipMap) {
            mipMap = YES;
            filter = GL_LINEAR_MIPMAP_LINEAR;
        } else
            filter = GL_LINEAR;
        OOGL(glTexParameteri(texTarget, GL_TEXTURE_MIN_FILTER, filter));

#if GL_EXT_texture_filter_anisotropic
        if (gOOTextureInfo.anisotropyAvailable && mipMap && 1.0 < _anisotropy) {
            OOGL(glTexParameterf(texTarget, GL_TEXTURE_MAX_ANISOTROPY_EXT, _anisotropy));
        }
#endif

        // Select mag filter
        filter = _options & kOOTextureMagFilterMask;
        if (filter == kOOTextureMagFilterNearest)
            filter = GL_NEAREST;
        else
            filter = GL_LINEAR;
        OOGL(glTexParameteri(texTarget, GL_TEXTURE_MAG_FILTER, filter));

        //	if (gOOTextureInfo.clientStorageAvailable)  EnableClientStorage();

        if (texTarget == GL_TEXTURE_2D) {
            uploadTextureDataWithMipMap(mipMap, _format);
            OO_LOG("texture.upload", "Uploaded texture {} ({}x{} pixels, {})", _textureName, _width, _height, _key.value_or("(null)"));
        }
#if OO_TEXTURE_CUBE_MAP
        else if (texTarget == GL_TEXTURE_CUBE_MAP) {
            uploadTextureCubeMapDataWithMipMap(mipMap, _format);
            OO_LOG("texture.upload", "Uploaded cube map texture {} ({}x{}x6 pixels, {})", _textureName, _width, _width, _key.value_or("(null)"));
        }
#endif
        else {
            OORaiseException(OOInternalInconsistencyException, "Unhandled texture target 0x%X.", texTarget);
        }

        _valid = YES;
        _uploaded = YES;

#if OOTEXTURE_RELOADABLE
        if (isReloadable()) {
            free(_bytes);
            _bytes = NULL;
        }
#endif
    }
}

void OOConcreteTexture::uploadTextureDataWithMipMap(bool mipMap, OOTextureDataFormat format)
{
    GLenum glFormat = 0, internalFormat = 0, type = 0;
    unsigned w = _width,
             h = _height,
             level = 0;
    char* bytes = (char*)_bytes;
    uint8_t components = OOTextureComponentsForFormat(format);

    OO_ENTER_OPENGL();

    if (!DecodeFormat(format, _options, &glFormat, &internalFormat, &type))
        return;

    while (0 < w && 0 < h) {
        OOGL(glTexImage2D(GL_TEXTURE_2D, level++, internalFormat, w, h, 0, glFormat, type, bytes));
        if (!mipMap)
            return;
        bytes += w * components * h;
        w >>= 1;
        h >>= 1;
    }

    // Note: we only reach here if (mipMap).
    _mipLevels = level - 1;
    OOGL(glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, _mipLevels));
}

#if OO_TEXTURE_CUBE_MAP
void OOConcreteTexture::uploadTextureCubeMapDataWithMipMap(bool mipMap, OOTextureDataFormat format)
{
    OO_ENTER_OPENGL();

    GLenum glFormat = 0, internalFormat = 0, type = 0;
    if (!DecodeFormat(format, _options, &glFormat, &internalFormat, &type))
        return;
    uint8_t components = OOTextureComponentsForFormat(format);

    // Calculate stride between cube map sides.
    size_t sideSize = _width * _width * components;
    if (mipMap) {
        sideSize = sideSize * 4 / 3;
        sideSize = (sideSize + 15) & ~15;
    }

    unsigned side;
    for (side = 0; side < 6; side++) {
        char* bytes = (char*)_bytes;
        bytes += side * sideSize;

        unsigned w = _width, level = 0;

        while (0 < w) {
            OOGL(glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + side, level++, internalFormat, w, w, 0, glFormat, type, bytes));
            if (!mipMap)
                break;
            bytes += w * w * components;
            w >>= 1;
        }
    }
}
#endif

GLenum OOConcreteTexture::glTextureTarget()
{
    GLenum texTarget = GL_TEXTURE_2D;
#if OO_TEXTURE_CUBE_MAP
    if (_isCubeMap) {
        texTarget = GL_TEXTURE_CUBE_MAP;
    }
#endif
    return texTarget;
}

void OOConcreteTexture::forceRebind()
{
    if (_loaded && _uploaded && _valid) {
        OO_ENTER_OPENGL();

        _uploaded = NO;
        OOGL(glDeleteTextures(1, &_textureName));
        _textureName = 0;

#if OOTEXTURE_RELOADABLE
        if (isReloadable()) {
            OO_LOG("texture.reload", "Reloading texture {}", description());

            free(_bytes);
            _bytes = NULL;
            _loaded = NO;
            _uploaded = NO;
            _valid = NO;

            _loader = OOTextureLoader::loaderWithPath(_path, _options);
        }
#endif
    }
}

#if OOTEXTURE_RELOADABLE

bool OOConcreteTexture::isReloadable()
{
    return _path.has_value();
}

#endif

static BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, GLenum* outFormat, GLenum* outInternalFormat, GLenum* outType)
{
    OOCParameterAssert(outFormat != NULL && outInternalFormat != NULL && outType != NULL);

    switch (format) {
    case kOOTextureDataRGBA:
        *outFormat = GL_RGBA;
        *outInternalFormat = options & kOOTextureSRGBA ? GL_SRGB_ALPHA : GL_RGBA;
        *outType = RGBA_IMAGE_TYPE;
        return YES;

    case kOOTextureDataGrayscale:
        if (options & kOOTextureAlphaMask) {
            *outFormat = GL_ALPHA;
            *outInternalFormat = GL_ALPHA8;
        } else {
            *outFormat = GL_LUMINANCE;
            *outInternalFormat = GL_LUMINANCE8;
        }
        *outType = GL_UNSIGNED_BYTE;
        return YES;

    case kOOTextureDataGrayscaleAlpha:
        *outFormat = GL_LUMINANCE_ALPHA;
        *outInternalFormat = GL_LUMINANCE8_ALPHA8;
        *outType = GL_UNSIGNED_BYTE;
        return YES;

    default:
        OO_LOG(cxx_kOOLogParameterError, "Unexpected texture format {}.", static_cast<unsigned>(format));
        return NO;
    }
}
