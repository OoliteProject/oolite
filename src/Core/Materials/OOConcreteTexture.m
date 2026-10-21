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

#import "OOConcreteTexture.h"
#import "OOCPUInfo.h"
#import "OOCollectionExtractors.h"
#import "OOGLStateCompat.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOPixMap.h"
#import "OORendererTexture.h"
#import "OOTextureInternal.h"
#import "OOTextureLoader.h"
#import "ResourceManager.h"
#import "Universe.h"

#ifndef NDEBUG
#import "OOTextureGenerator.h"
#endif

@interface OOConcreteTexture (Private)

- (void)setUpTexture;
- (void)uploadTexture;
- (void)uploadLevels:(const OOTextureDescriptor*)descriptor;

- (GLenum)glTextureTarget;

#if OOTEXTURE_RELOADABLE
- (BOOL)isReloadable;
#endif

@end

static BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, OOTexelFormat* outFormat, bool* outSRGB);

@implementation OOConcreteTexture

- (id)initWithLoader:(OOTextureLoader*)loader
                 key:(NSString*)key
             options:(uint32_t)options
          anisotropy:(GLfloat)anisotropy
             lodBias:(GLfloat)lodBias
{
    if (loader == nil) {
        [self release];
        return nil;
    }

    self = [super init];
    if (EXPECT_NOT(self == nil))
        return nil;

    _loader = [loader retain];
    _options = options;

#if GL_EXT_texture_filter_anisotropic
    _anisotropy = OOClamp_0_1_f(anisotropy) * gOOTextureInfo.anisotropyScale;
#endif
#if GL_EXT_texture_lod_bias
    _lodBias = lodBias;
#endif

#ifndef NDEBUG
    if ([loader isKindOfClass:[OOTextureGenerator class]]) {
        _name = [[NSString alloc] initWithFormat:@"<%@>", [loader class]];
    }
#endif

    _key = [key copy];

    [self addToCaches];

    return self;
}

- (id)initWithPath:(NSString*)path
               key:(NSString*)key
           options:(uint32_t)options
        anisotropy:(float)anisotropy
           lodBias:(GLfloat)lodBias
{
    OOTextureLoader* loader = [OOTextureLoader loaderWithPath:path options:options];
    if (loader == nil) {
        [self release];
        return nil;
    }

    if ((self = [self initWithLoader:loader key:key options:options anisotropy:anisotropy lodBias:lodBias])) {
#if OOTEXTURE_RELOADABLE
        _path = [path retain];
#endif
    }

    return self;
}

- (void)dealloc
{
#ifndef NDEBUG
    OOLog(_trace ? @"texture.allocTrace.dealloc" : @"texture.dealloc", @"Deallocating and uncaching texture %p", self);
#endif

#if OOTEXTURE_RELOADABLE
    DESTROY(_path);
#endif

    if (_loaded) {
        if (_textureName != 0) {
            OO_ENTER_OPENGL();
            OORendererDeleteTexture(_textureName);
            _textureName = 0;
        }
        free(_bytes);
        _bytes = NULL;
    }

#ifndef OOTEXTURE_NO_CACHE
    [self removeFromCaches];
    [_key autorelease];
    _key = nil;
#endif

    DESTROY(_loader);

#ifndef NDEBUG
    DESTROY(_name);
#endif

    [super dealloc];
}

- (NSString*)descriptionComponents
{
    NSString* stateDesc = nil;

    if (_loaded) {
        if (_valid) {
            stateDesc = [NSString stringWithFormat:@"%u x %u", _width, _height];
        } else {
            stateDesc = @"LOAD ERROR";
        }
    } else {
        stateDesc = @"loading";
    }

    return [NSString stringWithFormat:@"%@, %@", _key, stateDesc];
}

- (NSString*)shortDescriptionComponents
{
    return _key;
}

#ifndef NDEBUG
- (NSString*)name
{
    if (_name != nil)
        return _name;

#if OOTEXTURE_RELOADABLE
    NSString* name = [_path lastPathComponent];
#else
    NSString* name = [[[[self cacheKey] componentsSeparatedByString:@":"] objectAtIndex:0] lastPathComponent];
#endif

    NSString* channelSuffix = nil;
    switch (_options & kOOTextureExtractChannelMask) {
    case kOOTextureExtractChannelR:
        channelSuffix = @":r";
        break;

    case kOOTextureExtractChannelG:
        channelSuffix = @":g";
        break;

    case kOOTextureExtractChannelB:
        channelSuffix = @":b";
        break;

    case kOOTextureExtractChannelA:
        channelSuffix = @":a";
        break;
    }

    if (channelSuffix != nil)
        name = [name stringByAppendingString:channelSuffix];

    return name;
}
#endif

- (void)apply
{
    OO_ENTER_OPENGL();

    if (EXPECT_NOT(!_loaded))
        [self setUpTexture];
    else if (EXPECT_NOT(!_uploaded))
        [self uploadTexture];
    else
        OOGLBindTexture([self glTextureTarget], _textureName);

#if GL_EXT_texture_lod_bias
    if (gOOTextureInfo.textureLODBiasAvailable)
        OOGLTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, _lodBias);
#endif
}

- (void)ensureFinishedLoading
{
    if (!_loaded)
        [self setUpTexture];
}

- (BOOL)isFinishedLoading
{
    return _loaded || [_loader isReady];
}

- (NSString*)cacheKey
{
    return _key;
}

- (NSSize)dimensions
{
    [self ensureFinishedLoading];

    return NSMakeSize(_width, _height);
}

- (NSSize)originalDimensions
{
    [self ensureFinishedLoading];

    return NSMakeSize(_originalWidth, _originalHeight);
}

- (BOOL)isMipMapped
{
    [self ensureFinishedLoading];

    return _mipLevels != 0;
}

- (struct OOPixMap)copyPixMapRepresentation
{
    [self ensureFinishedLoading];

    OOPixMap px = kOONullPixMap;

    if (_bytes != NULL) {
        // If possible, just copy our existing buffer.
        px = OOMakePixMap(_bytes, _width, _height, _format, 0, 0);
        px = OODuplicatePixMap(px, 0);
    }
#if OOTEXTURE_RELOADABLE
    else {
        // Otherwise, read it back from the renderer.
        unsigned faces = [self isCubeMap] ? 6 : 1;
        px = OOAllocatePixMap(_width, _height, _format, 0, 0); // cube maps: six faces stacked
        if (!OOIsValidPixMap(px))
            return kOONullPixMap;
        uint8_t* pixels = px.pixels;
        unsigned height = faces == 6 ? _width : _height;
        for (unsigned face = 0; face < faces; face++) {
            OORendererReadTexture(_textureName, face, 0, _width, height, pixels);
            pixels += OOPixMapBytesPerPixelForFormat(_format) * _width * height;
        }
    }
#endif

    return px;
}

- (BOOL)isRectangleTexture
{
#if GL_EXT_texture_rectangle
    return _isRectTexture;
#else
    return NO;
#endif
}

- (BOOL)isCubeMap
{
#if OO_TEXTURE_CUBE_MAP
    return _isCubeMap;
#else
    return NO;
#endif
}

- (NSSize)texCoordsScale
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
            [self ensureFinishedLoading];
            return [self texCoordsScale];
        }
    }
#else
    return NSMakeSize(1.0f, 1.0f);
#endif
}

- (GLint)glTextureName
{
    [self ensureFinishedLoading];

    return _textureName;
}

@end

@implementation OOConcreteTexture (Private)

- (void)setUpTexture
{
    OOPixMap pm;

    // This will block until loading is completed, if necessary.
    if ([_loader getResult:&pm format:&_format originalWidth:&_originalWidth originalHeight:&_originalHeight]) {
        _bytes = pm.pixels;
        _width = pm.width;
        _height = pm.height;

#if OO_TEXTURE_CUBE_MAP
        if (_options & kOOTextureAllowCubeMap && _height == _width * 6 && gOOTextureInfo.cubeMapAvailable) {
            _isCubeMap = YES;
        }
#endif

#if !defined(NDEBUG) && OOTEXTURE_RELOADABLE
        if (_trace) {
            static unsigned dumpID = 0;
            NSString* name = [NSString stringWithFormat:@"tex dump %u \"%@\"", ++dumpID, [self name]];
            OOLog(@"texture.trace.dump", @"Dumped traced texture %@ to \'%@.png\'", self, name);
            OODumpPixMap(pm, name);
        }
#endif

        [self uploadTexture];
    } else {
        _textureName = 0;
        _valid = NO;
        _uploaded = YES;
    }

    _loaded = YES;

    DESTROY(_loader);
}

- (void)uploadTexture
{
    if (!_uploaded) {
        BOOL cube = [self isCubeMap];
        OOTextureDescriptor descriptor = { 0 };
        descriptor.cube = cube;
        descriptor.width = _width;
        descriptor.height = cube ? _width : _height;
        if (!DecodeFormat(_format, _options, &descriptor.format, &descriptor.srgb))
            return;

        BOOL mipMap = NO;
        uint32_t filter = _options & kOOTextureMinFilterMask;
        if (filter == kOOTextureMinFilterNearest)
            descriptor.minFilter = kOOFilterNearest;
        else if (filter == kOOTextureMinFilterMipMap) {
            mipMap = YES;
            descriptor.minFilter = kOOFilterLinearMipmapLinear;
        } else
            descriptor.minFilter = kOOFilterLinear;
        descriptor.magFilter = (_options & kOOTextureMagFilterMask) == kOOTextureMagFilterNearest ? kOOFilterNearest : kOOFilterLinear;
        descriptor.levels = mipMap ? OOTextureMipLevelCount(descriptor.width, descriptor.height) : 1;
        descriptor.repeatS = (_options & kOOTextureRepeatS) != 0;
        descriptor.repeatT = (_options & kOOTextureRepeatT) != 0;
#if GL_EXT_texture_filter_anisotropic
        if (gOOTextureInfo.anisotropyAvailable && mipMap)
            descriptor.anisotropy = _anisotropy;
#endif

        _textureName = OORendererCreateTexture(&descriptor);
        [self uploadLevels:&descriptor];
        if (mipMap && !cube)
            _mipLevels = descriptor.levels - 1;
        OOGLBindTexture([self glTextureTarget], _textureName);

        if (cube)
            OOLog(@"texture.upload", @"Uploaded cube map texture %u (%ux%ux6 pixels, %@)", _textureName, _width, _width, _key);
        else
            OOLog(@"texture.upload", @"Uploaded texture %u (%ux%u pixels, %@)", _textureName, _width, _height, _key);

        _valid = YES;
        _uploaded = YES;

#if OOTEXTURE_RELOADABLE
        if ([self isReloadable]) {
            free(_bytes);
            _bytes = NULL;
        }
#endif
    }
}

- (void)uploadLevels:(const OOTextureDescriptor*)descriptor
{
    uint8_t components = OOTextureComponentsForFormat(_format);
    unsigned faces = descriptor->cube ? 6 : 1;

    // Cube map faces are stored one after another, each followed by its
    // mipmaps and padded to 16 bytes.
    size_t faceSize = (size_t)descriptor->width * descriptor->height * components;
    if (descriptor->levels > 1) {
        faceSize = faceSize * 4 / 3;
        faceSize = (faceSize + 15) & ~(size_t)15;
    }

    for (unsigned face = 0; face < faces; face++) {
        const char* bytes = (const char*)_bytes + face * faceSize;
        unsigned w = descriptor->width, h = descriptor->height;
        for (unsigned level = 0; level < descriptor->levels; level++) {
            OORendererUploadTexture(_textureName, face, level, w, h, bytes);
            bytes += (size_t)w * h * components;
            w >>= 1;
            h >>= 1;
        }
    }
}

- (GLenum)glTextureTarget
{
    GLenum texTarget = GL_TEXTURE_2D;
#if OO_TEXTURE_CUBE_MAP
    if (_isCubeMap) {
        texTarget = GL_TEXTURE_CUBE_MAP;
    }
#endif
    return texTarget;
}

- (void)forceRebind
{
    if (_loaded && _uploaded && _valid) {
        OO_ENTER_OPENGL();

        _uploaded = NO;
        OORendererDeleteTexture(_textureName);
        _textureName = 0;

#if OOTEXTURE_RELOADABLE
        if ([self isReloadable]) {
            OOLog(@"texture.reload", @"Reloading texture %@", self);

            free(_bytes);
            _bytes = NULL;
            _loaded = NO;
            _uploaded = NO;
            _valid = NO;

            _loader = [[OOTextureLoader loaderWithPath:_path options:_options] retain];
        }
#endif
    }
}

#if OOTEXTURE_RELOADABLE

- (BOOL)isReloadable
{
    return _path != nil;
}

#endif

@end

static BOOL DecodeFormat(OOTextureDataFormat format, uint32_t options, OOTexelFormat* outFormat, bool* outSRGB)
{
    NSCParameterAssert(outFormat != NULL && outSRGB != NULL);

    *outSRGB = false;
    switch (format) {
    case kOOTextureDataRGBA:
        *outFormat = kOOTexelRGBA8;
        *outSRGB = (options & kOOTextureSRGBA) != 0;
        return YES;

    case kOOTextureDataGrayscale:
        *outFormat = (options & kOOTextureAlphaMask) ? kOOTexelAlpha8 : kOOTexelGray8;
        return YES;

    case kOOTextureDataGrayscaleAlpha:
        *outFormat = kOOTexelGrayAlpha8;
        return YES;

    default:
        OOLog(kOOLogParameterError, @"Unexpected texture format %u.", format);
        return NO;
    }
}
