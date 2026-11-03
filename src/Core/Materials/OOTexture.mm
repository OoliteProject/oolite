/*

        OOTexture.m

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

#import "OOTexture.h"
#import "OOConcreteTexture.h"
#import "OONullTexture.h"
#import "OOTextureInternal.h"

#import "OOTextureGenerator.h"
#import "OOTextureLoader.h"

#import "OOCPUInfo.h"
#import "OOCache.h"
#import "OOMacroOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOPListView.h"
#import "OOPixMap.h"
#import "ResourceManager.h"
#import "Universe.h"

#import "OOFoundationBridge.h"
#include "oofnd/StdLib.hpp"

#include "oofnd/String.hpp"

namespace {

// Used only by "internal" specifiers from cxx_OOMakeTextureSpecifier.
const char* const kOOTextureSpecifierFlagValueInternalKey = "_oo_internal_flags";

} // namespace

/*	Texture caching:
        two and a half parallel caching mechanisms are used. sLiveTextureCache
        tracks all live texture objects with cache keys, without retaining them
        (a std::unordered_map of raw pointers keyed by the cache key's UTF-8).

        sAllLiveTextures tracks all textures, including ones without cache keys,
        so that they can be notified of graphics resets. This also holds raw
        pointers to avoid retaining the textures.

        sRecentTextures tracks up to kRecentTexturesCount textures which
        have been used recently, and retains them.

        This means that the number of live texture objects will never fall below
        80% of kRecentTexturesCount (80% comes from the behaviour of OOCache), but
        old textures will eventually be released. If the number of active textures
        exceeds kRecentTexturesCount, all of them will be reusable through
        sLiveTextureCache, but only a most-recently-fetched subset will be kept
        around by the cache when the number drops.

        Note the textures in sRecentTextures are a superset of the textures in
        sLiveTextureCache, and the textures in sLiveTextureCache are a superset
        of sRecentTextures.
*/
enum {
    kRecentTexturesCount = 50
};

// Allocated on first use and never freed, so a texture deallocated during exit never finds them
// destroyed. Were a Foundation mutable dictionary / set of boxed pointers (bead oo-3rb.10).
static std::unordered_map<std::string, OOTexture*>* sLiveTextureCache;
static std::unordered_set<OOTexture*>* sAllLiveTextures;
static OOCache* sRecentTextures;

static BOOL sCheckedExtensions;
OOTextureInfo gOOTextureInfo;

@interface OOTexture (OOPrivate)

- (void)addToCaches;

- (void)forceRebind;

+ (void)checkExtensions;

#ifdef OO_DEBUG_MONITOR_ENABLED
- (id)retainInContext:(const char*)context;
- (void)releaseInContext:(const char*)context;
- (id)autoreleaseInContext:(const char*)context;
#endif

@end

#ifdef OO_DEBUG_MONITOR_ENABLED
namespace {

const char* sGlobalTraceContext = nullptr;

} // namespace

#define SET_TRACE_CONTEXT(str)       \
    do {                             \
        sGlobalTraceContext = (str); \
    } while (0)
#else
#define SET_TRACE_CONTEXT(str) \
    do {                       \
    } while (0)
#endif
#define CLEAR_TRACE_CONTEXT() SET_TRACE_CONTEXT(nullptr)

@implementation OOTexture

+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory
                  options:(OOTextureFlags)options
               anisotropy:(GLfloat)anisotropy
                  lodBias:(GLfloat)lodBias
{
    std::string key;
    OOTexture* result = nil;
    std::optional<std::string> path;
    BOOL noFNF;

    if (EXPECT_NOT(!name.has_value()))
        return nil;
    if (EXPECT_NOT(!sCheckedExtensions))
        [self checkExtensions];

    if (!gOOTextureInfo.anisotropyAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap) {
        anisotropy = 0.0f;
    }
    if (!gOOTextureInfo.textureLODBiasAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap) {
        lodBias = 0.0f;
    }

    noFNF = (options & kOOTextureNoFNFMessage) != 0;
    options = OOApplyTextureOptionDefaults(options & ~kOOTextureNoFNFMessage);

    // Look for existing texture
    key = OOGenerateTextureCacheKey(directory, *name, options, anisotropy, lodBias);
    result = [OOTexture cxx_existingTextureForKey:key];
    if (result == nil) {
        path = oo::OptionalString([ResourceManager pathForFileNamed:oo::NSStringFrom(*name) inFolder:oo::NSStringOrNil(directory)]);
        if (!path.has_value()) {
            if (!noFNF)
                OOLogWARN(kOOLogFileNotFound, @"Could not find texture file \"%@\".", oo::NSStringFrom(*name));
            return nil;
        }

        // No existing texture, load texture.
        result = [[[OOConcreteTexture alloc] initWithPath:*path key:key options:options anisotropy:anisotropy lodBias:lodBias] autorelease];
    }

    return result;
}

+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory
{
    return [self cxx_textureWithName:name
                            inFolder:directory
                             options:kOOTextureDefaultOptions
                          anisotropy:kOOTextureDefaultAnisotropy
                             lodBias:kOOTextureDefaultLODBias];
}

+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration
{
    return [self cxx_textureWithConfiguration:configuration extraOptions:0];
}

+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration extraOptions:(OOTextureFlags)extraOptions
{
    std::string name;
    OOTextureFlags options = 0;
    GLfloat anisotropy = 0.0f;
    GLfloat lodBias = 0.0f;

    if (!cxx_OOInterpretTextureSpecifier(configuration, &name, &options, &anisotropy, &lodBias, NO))
        return nil;

    return [self cxx_textureWithName:name inFolder:"Textures" options:options | extraOptions anisotropy:anisotropy lodBias:lodBias];
}

+ (id)nullTexture
{
    return [OONullTexture sharedNullTexture];
}

+ (id)textureWithGenerator:(OOTextureGenerator*)generator
{
    return [self textureWithGenerator:generator enqueue:NO];
}

+ (id)textureWithGenerator:(OOTextureGenerator*)generator enqueue:(BOOL)enqueue
{
    if (generator == nil)
        return nil;

#ifndef OOTEXTURE_NO_CACHE
    OOTexture* existing = [OOTexture cxx_existingTextureForKey:oo::OptionalString([generator cacheKey])];
    if (existing != nil && !enqueue)
        return [[existing retain] autorelease];
#endif

    if (![generator enqueue]) {
        OOLogERR(@"texture.generator.queue.failed", @"Failed to queue generator %@", generator);
        return nil;
    }
    OOLog(@"texture.generator.queue", @"Queued texture generator %@", generator);

    OOTexture* result = [[[OOConcreteTexture alloc] initWithLoader:generator
                                                               key:oo::OptionalString([generator cacheKey])
                                                           options:OOApplyTextureOptionDefaults([generator textureOptions])
                                                        anisotropy:[generator anisotropy]
                                                           lodBias:[generator lodBias]] autorelease];

    return result;
}

- (id)init
{
    if ((self = [super init])) {
        if (EXPECT_NOT(sAllLiveTextures == NULL))
            sAllLiveTextures = new std::unordered_set<OOTexture*>;
        sAllLiveTextures->insert(self);
    }

    return self;
}

- (void)dealloc
{
    if (sAllLiveTextures != NULL)
        sAllLiveTextures->erase(self);

    [super dealloc];
}

- (void)apply
{
    OOLogGenericSubclassResponsibility();
}

+ (void)applyNone
{
    OO_ENTER_OPENGL();
    OOGL(glBindTexture(GL_TEXTURE_2D, 0));
#if OO_TEXTURE_CUBE_MAP
    if (OOCubeMapsAvailable())
        OOGL(glBindTexture(GL_TEXTURE_CUBE_MAP, 0));
#endif

#if GL_EXT_texture_lod_bias
    if (gOOTextureInfo.textureLODBiasAvailable)
        OOGL(glTexEnvf(GL_TEXTURE_FILTER_CONTROL_EXT, GL_TEXTURE_LOD_BIAS_EXT, 0));
#endif
}

- (void)ensureFinishedLoading
{
}

- (BOOL)isFinishedLoading
{
    return YES;
}

- (id)cacheKey // shared selector (proposed ADR-0043)
{
    return nil;
}

- (NSSize)dimensions
{
    OOLogGenericSubclassResponsibility();
    return NSZeroSize;
}

- (NSSize)originalDimensions
{
    return [self dimensions];
}

- (BOOL)isMipMapped
{
    OOLogGenericSubclassResponsibility();
    return NO;
}

- (struct OOPixMap)copyPixMapRepresentation
{
    return kOONullPixMap;
}

- (BOOL)isRectangleTexture
{
    return NO;
}

- (BOOL)isCubeMap
{
    return NO;
}

- (NSSize)texCoordsScale
{
    return NSMakeSize(1.0, 1.0);
}

- (GLint)glTextureName
{
    OOLogGenericSubclassResponsibility();
    return 0;
}

+ (void)clearCache
{
    /*	Does not clear sAllLiveTextures - that really must refer to all
            live texture objects.
    */
    SET_TRACE_CONTEXT("clearing sLiveTextureCache");
    if (sLiveTextureCache != NULL)
        sLiveTextureCache->clear();

    SET_TRACE_CONTEXT("clearing sRecentTextures");
    [sRecentTextures autorelease];
    sRecentTextures = nil;
    CLEAR_TRACE_CONTEXT();
}

+ (void)rebindAllTextures
{
    // Keeping around unused, cached textures is unhelpful at this point.
    DESTROY(sRecentTextures);

    if (sAllLiveTextures == NULL)
        return;
    // A copy: the set is unordered (as the Foundation set was) and must not change under the loop.
    const std::vector<OOTexture*> textures(sAllLiveTextures->begin(), sAllLiveTextures->end());
    for (OOTexture* texture : textures) {
        [texture forceRebind];
    }
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (void)setTrace:(BOOL)trace
{
    if (trace && !_trace) {
        OOLog(@"texture.allocTrace.begin", @"Started tracing texture %p with retain count %zu.", self, [self retainCount]);
    }
    _trace = trace;
}

+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_cachedTexturesByAge
{
    std::vector<oo::ObjCRef<OOTexture*>> result;
    for (const oo::ObjCRef<id>& texture : [sRecentTextures objectsByAge]) {
        result.emplace_back((OOTexture*)texture.get());
    }
    return result;
}

+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures
{
    std::vector<oo::ObjCRef<OOTexture*>> result;
    if (sAllLiveTextures != NULL) {
        result.reserve(sAllLiveTextures->size());
        for (OOTexture* texture : *sAllLiveTextures) {
            result.emplace_back(texture);
        }
    }

    return result;
}

- (size_t)dataSize
{
    NSSize dimensions = [self dimensions];
    size_t size = dimensions.width * dimensions.height;
    if ([self isCubeMap])
        size *= 6;
    if ([self isMipMapped])
        size = size * 4 / 3;

    return size;
}

- (id)name // shared selector (proposed ADR-0043)
{
    OOLogGenericSubclassResponsibility();
    return nil;
}
#endif

- (void)forceRebind
{
    OOLogGenericSubclassResponsibility();
}

- (void)addToCaches
{
#ifndef OOTEXTURE_NO_CACHE
    const std::optional<std::string> cacheKey = oo::OptionalString([self cacheKey]);
    if (!cacheKey.has_value())
        return;

    // Add self to in-use textures cache, as a raw pointer so the texture isn't retained by the cache.
    if (EXPECT_NOT(sLiveTextureCache == NULL))
        sLiveTextureCache = new std::unordered_map<std::string, OOTexture*>;

    SET_TRACE_CONTEXT("in-use textures cache - SHOULD NOT RETAIN");
    (*sLiveTextureCache)[*cacheKey] = self;
    CLEAR_TRACE_CONTEXT();

    // Add self to recent textures cache.
    if (EXPECT_NOT(sRecentTextures == nil)) {
        sRecentTextures = [[OOCache alloc] init];
        [sRecentTextures setName:@"recent textures"];
        [sRecentTextures setAutoPrune:YES];
        [sRecentTextures setPruneThreshold:kRecentTexturesCount];
    }

    SET_TRACE_CONTEXT("adding to recent textures cache");
    [sRecentTextures setObject:self forKey:oo::NSStringFrom(*cacheKey)];
    CLEAR_TRACE_CONTEXT();
#endif
}

- (void)removeFromCaches
{
#ifndef OOTEXTURE_NO_CACHE
    const std::optional<std::string> cacheKey = oo::OptionalString([self cacheKey]);
    if (!cacheKey.has_value())
        return;

    if (sLiveTextureCache != NULL)
        sLiveTextureCache->erase(*cacheKey);
    if (EXPECT_NOT([sRecentTextures objectForKey:oo::NSStringFrom(*cacheKey)] == self)) {
        /* Experimental for now: I think the recent crash problems may
         * be because if the last reference to a texture is in
         * sRecentTextures, and the texture is regenerated, it
         * replaces the texture, causing a release. Therefore, if this
         * texture *isn't* overretained in the texture cache, the 2009
         * crash avoider will delete its replacement from the cache
         * ... possibly before that texture has been fully added to
         * the cache itself. So, the texture is only removed from the
         * cache by key if it was in it with that key. The extra time
         * needed to generate a planet texture compared with loading a
         * standard one may be why this problem shows up.  - CIM 20140122
         */
        NSAssert2(0, @"Texture retain count error for %@; cacheKey is %@.", self, oo::NSStringFrom(*cacheKey)); // miscount in autorelease
        // The following line is needed in order to avoid crashes when there's a 'texture retain count error'. Please do not delete. -- Kaks 20091221
        [sRecentTextures removeObjectForKey:oo::NSStringFrom(*cacheKey)]; // make sure there's no reference left inside sRecentTexture ( was a show stopper for 1.73)
    }
#endif
}

+ (OOTexture*)cxx_existingTextureForKey:(const std::optional<std::string>&)key
{
#ifndef OOTEXTURE_NO_CACHE
    if (key.has_value()) {
        if (sLiveTextureCache == NULL)
            return nil;
        auto it = sLiveTextureCache->find(*key);
        return (it != sLiveTextureCache->end()) ? it->second : nil;
    }
    return nil;
#else
    return nil;
#endif
}

+ (void)checkExtensions
{
    OO_ENTER_OPENGL();

    sCheckedExtensions = YES;

    OOOpenGLExtensionManager* extMgr = [OOOpenGLExtensionManager sharedManager];
    BOOL ver120 = [extMgr versionIsAtLeastMajor:1 minor:2];
    BOOL ver130 = [extMgr versionIsAtLeastMajor:1 minor:3];

#if GL_EXT_texture_filter_anisotropic
    gOOTextureInfo.anisotropyAvailable = [extMgr haveExtension:"GL_EXT_texture_filter_anisotropic"] ? 1 : 0;
    OOGL(glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &gOOTextureInfo.anisotropyScale));
    gOOTextureInfo.anisotropyScale *= OOClamp_0_1_f(oo::PListView([NSUserDefaults standardUserDefaults]).get<float>(@"texture-anisotropy-scale", 0.5));
#endif

#ifdef GL_CLAMP_TO_EDGE
    gOOTextureInfo.clampToEdgeAvailable = ver120 || [extMgr haveExtension:"GL_SGIS_texture_edge_clamp"];
#endif

#if OO_GL_CLIENT_STORAGE
    gOOTextureInfo.clientStorageAvailable = [extMgr haveExtension:"GL_APPLE_client_storage"] ? 1 : 0;
#endif

    gOOTextureInfo.textureMaxLevelAvailable = ver120 || [extMgr haveExtension:"GL_SGIS_texture_lod"];

#if GL_EXT_texture_lod_bias
    if (oo::PListView([NSUserDefaults standardUserDefaults]).get<BOOL>(@"use-texture-lod-bias", YES)) {
        gOOTextureInfo.textureLODBiasAvailable = [extMgr haveExtension:"GL_EXT_texture_lod_bias"] ? 1 : 0;
    } else {
        gOOTextureInfo.textureLODBiasAvailable = NO;
    }
#endif

#if GL_EXT_texture_rectangle
    gOOTextureInfo.rectangleTextureAvailable = [extMgr haveExtension:"GL_EXT_texture_rectangle"];
#endif

#if OO_TEXTURE_CUBE_MAP
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"disable-cube-maps"]) {
        gOOTextureInfo.cubeMapAvailable = ver130 || [extMgr haveExtension:"GL_ARB_texture_cube_map"];
    } else {
        gOOTextureInfo.cubeMapAvailable = NO;
    }

#endif
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (id)retainInContext:(const char*)context
{
    if (_trace) {
        if (context)
            OOLog(@"texture.allocTrace.retain", @"Texture %p retained (retain count -> %zu) - %@.", self, [self retainCount] + 1, oo::NSStringFrom(context));
        else
            OOLog(@"texture.allocTrace.retain", @"Texture %p retained  (retain count -> %zu).", self, [self retainCount] + 1);
    }

    return [super retain];
}

- (void)releaseInContext:(const char*)context
{
    if (_trace) {
        if (context)
            OOLog(@"texture.allocTrace.release", @"Texture %p released (retain count -> %zu) - %@.", self, [self retainCount] - 1, oo::NSStringFrom(context));
        else
            OOLog(@"texture.allocTrace.release", @"Texture %p released (retain count -> %zu).", self, [self retainCount] - 1);
    }

    [super release];
}

- (id)autoreleaseInContext:(const char*)context
{
    if (_trace) {
        if (context)
            OOLog(@"texture.allocTrace.autoreleased", @"Texture %p autoreleased - %@.", self, oo::NSStringFrom(context));
        else
            OOLog(@"texture.allocTrace.autoreleased", @"Texture %p autoreleased.", self);
    }

    return [super autorelease];
}

- (id)retain
{
    return [self retainInContext:sGlobalTraceContext];
}

- (oneway void)release
{
    [self releaseInContext:sGlobalTraceContext];
}

- (id)autorelease
{
    return [self autoreleaseInContext:sGlobalTraceContext];
}
#endif

@end

oo::PList cxx_OOTextureSpecFromObject(const oo::PList& object, const std::optional<std::string>& defaultName)
{
    oo::PList value = object;
    if (value.isNull()) {
        if (!defaultName.has_value())
            return oo::PList();
        value = oo::PList(*defaultName);
    }
    if (const std::string* name = value.getIf<std::string>()) {
        if (name->empty())
            return oo::PList();
        return oo::PList(oo::PList::Dict { { "name", value } });
    }
    if (!value.isDict())
        return oo::PList();

    // If we're here, it's a dictionary. (A "name" the old -oo_stringForKey: read: a string or a number.)
    const oo::PList* name = value.find("name");
    if (!defaultName.has_value() || (name != nullptr && (name->isString() || name->isNumber())))
        return value;

    // If we get here, there's no "name" key and there is a default, so we fill it in:
    oo::PList::Dict mutableResult = *value.getIf<oo::PList::Dict>();
    mutableResult["name"] = oo::PList(*defaultName);
    return oo::PList(std::move(mutableResult));
}

uint8_t OOTextureComponentsForFormat(OOTextureDataFormat format)
{
    switch (format) {
    case kOOTextureDataRGBA:
        return 4;

    case kOOTextureDataGrayscale:
        return 1;

    case kOOTextureDataGrayscaleAlpha:
        return 2;

    case kOOTextureDataInvalid:
        break;
    }

    return 0;
}

BOOL OOCubeMapsAvailable(void)
{
    return gOOTextureInfo.cubeMapAvailable;
}

BOOL cxx_OOInterpretTextureSpecifier(const oo::PList& specifier, std::string* outName, OOTextureFlags* outOptions, float* outAnisotropy, float* outLODBias, BOOL ignoreExtract)
{
    std::string name;
    OOTextureFlags options = kOOTextureDefaultOptions;
    float anisotropy = kOOTextureDefaultAnisotropy;
    float lodBias = kOOTextureDefaultLODBias;

    if (const std::string* string = specifier.getIf<std::string>()) {
        name = *string;
    } else if (specifier.isDict()) {
        // -oo_stringForKey: gave nil unless the value was a string or a number.
        const oo::PList* nameValue = specifier.find(cxx_kOOTextureSpecifierNameKey);
        if (nameValue == nullptr || !(nameValue->isString() || nameValue->isNumber())) {
            OOLog(@"texture.load.noName", @"Invalid texture configuration dictionary (must specify name):\n%@", oo::ObjectFromPList(specifier));
            return NO;
        }
        name = specifier.get<std::string>(cxx_kOOTextureSpecifierNameKey);

        int quickFlags = specifier.get<int>(kOOTextureSpecifierFlagValueInternalKey, -1);
        if (quickFlags != -1) {
            options = quickFlags;
        } else {
            std::string filterString = specifier.get<std::string>(cxx_kOOTextureSpecifierMinFilterKey, "default");
            if (filterString == "nearest")
                options |= kOOTextureMinFilterNearest;
            else if (filterString == "linear")
                options |= kOOTextureMinFilterLinear;
            else if (filterString == "mipmap")
                options |= kOOTextureMinFilterMipMap;
            else
                options |= kOOTextureMinFilterDefault; // Covers "default"

            filterString = specifier.get<std::string>(cxx_kOOTextureSpecifierMagFilterKey, "default");
            if (filterString == "nearest")
                options |= kOOTextureMagFilterNearest;
            else
                options |= kOOTextureMagFilterLinear; // Covers "default" and "linear"

            if (specifier.get<bool>(cxx_kOOTextureSpecifierNoShrinkKey, false))
                options |= kOOTextureNoShrink;
            if (specifier.get<bool>(cxx_kOOTextureSpecifierExtraShrinkKey, false))
                options |= kOOTextureExtraShrink;
            if (specifier.get<bool>(cxx_kOOTextureSpecifierRepeatSKey, false))
                options |= kOOTextureRepeatS;
            if (specifier.get<bool>(cxx_kOOTextureSpecifierRepeatTKey, false))
                options |= kOOTextureRepeatT;
            if (specifier.get<bool>(cxx_kOOTextureSpecifierCubeMapKey, false))
                options |= kOOTextureAllowCubeMap;

            if (!ignoreExtract) {
                const oo::PList* extractValue = specifier.find("extract_channel");
                if (extractValue != nullptr && (extractValue->isString() || extractValue->isNumber())) {
                    const std::string extractChannel = specifier.get<std::string>("extract_channel");
                    if (extractChannel == "r")
                        options |= kOOTextureExtractChannelR;
                    else if (extractChannel == "g")
                        options |= kOOTextureExtractChannelG;
                    else if (extractChannel == "b")
                        options |= kOOTextureExtractChannelB;
                    else if (extractChannel == "a")
                        options |= kOOTextureExtractChannelA;
                    else {
                        OOLogWARN(@"texture.load.extractChannel.invalid", @"Unknown value \"%@\" for extract_channel in specifier \"%@\" (should be \"r\", \"g\", \"b\" or \"a\").", oo::NSStringFrom(extractChannel), oo::ObjectFromPList(specifier));
                    }
                }
            }
        }
        anisotropy = specifier.get<float>("anisotropy", kOOTextureDefaultAnisotropy);
        lodBias = specifier.get<float>("texture_LOD_bias", kOOTextureDefaultLODBias);
    } else {
        // Bad type
        if (!specifier.isNull())
            OOLog(kOOLogParameterError, @"%s: expected string or dictionary, got %@.", __PRETTY_FUNCTION__, [oo::ObjectFromPList(specifier) class]);
        return NO;
    }

    if (name.empty())
        return NO;

    if (outName != NULL)
        *outName = name;
    if (outOptions != NULL)
        *outOptions = options;
    if (outAnisotropy != NULL)
        *outAnisotropy = anisotropy;
    if (outLODBias != NULL)
        *outLODBias = lodBias;

    return YES;
}

oo::PList cxx_OOMakeTextureSpecifier(const std::string& name, OOTextureFlags options, float anisotropy, float lodBias, BOOL internal)
{
    oo::PList::Dict result;

    result[cxx_kOOTextureSpecifierNameKey] = oo::PList(name);

    // -oo_setFloat:forKey: stored +numberWithFloat:, -oo_setUnsignedInteger: +numberWithUnsignedInteger:.
    if (anisotropy != kOOTextureDefaultAnisotropy)
        result[cxx_kOOTextureSpecifierAnisotropyKey] = oo::PList::singleReal(anisotropy);
    if (lodBias != kOOTextureDefaultLODBias)
        result[cxx_kOOTextureSpecifierLODBiasKey] = oo::PList::singleReal(lodBias);

    if (internal) {
        result[kOOTextureSpecifierFlagValueInternalKey] = oo::PList::unsignedInteger(options);
    } else {
        const char* value = nullptr;
        switch (options & kOOTextureMinFilterMask) {
        case kOOTextureMinFilterDefault:
            break;

        case kOOTextureMinFilterNearest:
            value = "nearest";
            break;

        case kOOTextureMinFilterLinear:
            value = "linear";
            break;

        case kOOTextureMinFilterMipMap:
            value = "mipmap";
            break;
        }
        if (value != nullptr)
            result[cxx_kOOTextureSpecifierNoShrinkKey] = oo::PList(value);

        value = nullptr;
        switch (options & kOOTextureMagFilterMask) {
        case kOOTextureMagFilterNearest:
            value = "nearest";
            break;

        case kOOTextureMagFilterLinear:
            break;
        }
        if (value != nullptr)
            result[cxx_kOOTextureSpecifierMagFilterKey] = oo::PList(value);

        value = nullptr;
        switch (options & kOOTextureExtractChannelMask) {
        case kOOTextureExtractChannelNone:
            break;

        case kOOTextureExtractChannelR:
            value = "r";
            break;

        case kOOTextureExtractChannelG:
            value = "g";
            break;

        case kOOTextureExtractChannelB:
            value = "b";
            break;

        case kOOTextureExtractChannelA:
            value = "a";
            break;
        }
        if (value != nullptr)
            result[cxx_kOOTextureSpecifierSwizzleKey] = oo::PList(value);

        if (options & kOOTextureNoShrink)
            result[cxx_kOOTextureSpecifierNoShrinkKey] = oo::PList(true);
        if (options & kOOTextureRepeatS)
            result[cxx_kOOTextureSpecifierRepeatSKey] = oo::PList(true);
        if (options & kOOTextureRepeatT)
            result[cxx_kOOTextureSpecifierRepeatTKey] = oo::PList(true);
        if (options & kOOTextureAllowCubeMap)
            result[cxx_kOOTextureSpecifierCubeMapKey] = oo::PList(true);
    }

    return oo::PList(std::move(result));
}

OOTextureFlags OOApplyTextureOptionDefaults(OOTextureFlags options)
{
    // Set default flags if needed
    if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterDefault) {
        if ([UNIVERSE reducedDetail]) {
            options |= kOOTextureMinFilterLinear;
        } else {
            options |= kOOTextureMinFilterMipMap;
        }
    }

    if (!gOOTextureInfo.textureMaxLevelAvailable) {
        /*	In the unlikely case of an OpenGL system without GL_SGIS_texture_lod,
         disable mip-mapping completely. Strictly this is only needed for
         non-square textures, but extra logic for such a rare case isn't
         worth it.
         */
        if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap) {
            options ^= kOOTextureMinFilterMipMap ^ kOOTextureMinFilterLinear;
        }
    }

    if (options & kOOTextureAllowRectTexture) {
        // Apply rectangle texture restrictions (regardless of whether rectangle textures are available, for consistency)
        options &= kOOTextureFlagsAllowedForRectangleTexture;
        if ((options & kOOTextureMinFilterMask) == kOOTextureMinFilterMipMap) {
            options = (kOOTextureMinFilterMask & ~kOOTextureMinFilterMask) | kOOTextureMinFilterLinear;
        }

#if GL_EXT_texture_rectangle
        if (!gOOTextureInfo.rectangleTextureAvailable) {
            options &= ~kOOTextureAllowRectTexture;
        }
#else
        options &= ~kOOTextureAllowRectTexture;
#endif
    }

    options &= kOOTextureDefinedFlags;

    return options;
}

std::string OOGenerateTextureCacheKey(const std::optional<std::string>& directory, const std::string& name, OOTextureFlags options, float anisotropy, float lodBias)
{
    if (!gOOTextureInfo.anisotropyAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap) {
        anisotropy = 0.0f;
    }
    if (!gOOTextureInfo.textureLODBiasAvailable || (options & kOOTextureMinFilterMask) != kOOTextureMinFilterMipMap) {
        lodBias = 0.0f;
    }
    options = OOApplyTextureOptionDefaults(options & ~kOOTextureNoFNFMessage);

    return oo::str::format("%s%s%s:0x%.4X/%g/%g", directory.has_value() ? directory->c_str() : "", directory.has_value() ? "/" : "", name.c_str(), options, anisotropy, lodBias);
}

std::string cxx_OOTextureCacheKeyForSpecifier(const oo::PList& specifier)
{
    // Left as initialised when the specifier is not understood (they were uninitialised).
    std::string name;
    OOTextureFlags options = 0;
    float anisotropy = 0.0f;
    float lodBias = 0.0f;

    cxx_OOInterpretTextureSpecifier(specifier, &name, &options, &anisotropy, &lodBias, NO);
    return OOGenerateTextureCacheKey("Textures", name, options, anisotropy, lodBias);
}
