/*

OOTexture+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-smy and oo-2en): the Objective-C OOTexture facade
over cxx::OOTexture, and the adapter that is an Objective-C texture's C++ part. Every method
forwards in one line. Deleted, with OOTexture+ObjCBridge.h, by the bridge's deletion bead.


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

#import "OODescription.h"
#import "OOTexture.h"
#import "OOTextureInternal.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOObjCPeer.h"
#include "oofnd/objc/OORuntime.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

/*	The C++ part of an Objective-C texture: each virtual member messages the Objective-C object,
        so the subclass's override runs, as it did when the base class was Objective-C. The
        Objective-C object owns this (its _cxxTexture) and is not retained by it; its -dealloc clears
        the pointer, after which the members answer as a message to nil did.
*/
class ObjCTexture final : public cxx::OOTexture {
public:
    explicit ObjCTexture(::OOTexture* owner)
        : _owner(owner)
    {
    }

    ::OOTexture* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    void apply() override { [_owner apply]; }
    void ensureFinishedLoading() override { [_owner ensureFinishedLoading]; }
    bool isFinishedLoading() override { return [_owner isFinishedLoading]; }
    std::optional<std::string> cacheKey() override { return [_owner cxx_cacheKey]; }
    NSSize dimensions() override { return [_owner dimensions]; }
    NSSize originalDimensions() override { return [_owner originalDimensions]; }
    bool isMipMapped() override { return [_owner isMipMapped]; }
    OOPixMap copyPixMapRepresentation() override { return [_owner copyPixMapRepresentation]; }
    bool isRectangleTexture() override { return [_owner isRectangleTexture]; }
    bool isCubeMap() override { return [_owner isCubeMap]; }
    NSSize texCoordsScale() override { return [_owner texCoordsScale]; }
    GLint glTextureName() override { return [_owner glTextureName]; }
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::optional<std::string> name() override { return [_owner cxx_name]; }
#endif
    std::optional<std::string> descriptionComponents() const override { return [_owner cxx_descriptionComponents]; }
    std::optional<std::string> shortDescriptionComponents() const override { return [_owner cxx_shortDescriptionComponents]; }
    void forceRebind() override { [_owner forceRebind]; }

private:
    ::OOTexture* _owner = { }; // Not retained.
};

ObjCTexture* AsObjCTexture(cxx::OOTexture* texture)
{
    return dynamic_cast<ObjCTexture*>(texture);
}

std::string DemangledName(cxx::OOTexture& texture)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(texture).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(texture).name();
    std::free(demangled);
    return result;
}

// The C++ class's name, as [self class] named an Objective-C texture's class ("cxx::" dropped).
std::string ClassName(cxx::OOTexture& texture)
{
    std::string result = DemangledName(texture);
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

/*	The class of a C++ texture's facade: a converted subclass in namespace cxx that its callers
        message by its own selectors has a facade of its own, the Objective-C class of the same name, a
        subclass of this one (amendment oo-up4b item 3). Any other C++ texture (a global class) is an
        OOTexture.
*/
Class FacadeClass(cxx::OOTexture& texture)
{
    const std::string name = DemangledName(texture);
    if (name.starts_with("cxx::")) {
        Class facade = OOClassFromName(std::string_view(name).substr(5));
        if (facade != Nil && [facade isSubclassOfClass:[OOTexture class]])
            return facade;
    }
    return [OOTexture class];
}

} // namespace

@interface OOTexture (OOObjCBridgePrivate)

- (id)initWithCxxTexture:(cxx::OOTexture*)texture;

@end

@implementation OOTexture

// Inside the @implementation for the private ivar.
OOTexture* oo::ToObjC(cxx::OOTexture* texture)
{
    if (ObjCTexture* objCTexture = AsObjCTexture(texture))
        return [[objCTexture->owner() retain] autorelease];
    if (texture == nullptr)
        return nil;
    Class facadeClass = FacadeClass(*texture);
    return Peers().peerFor(texture, [texture, facadeClass] { return [[facadeClass alloc] initWithCxxTexture:texture]; });
}

cxx::OOTexture* oo::ToCxx(OOTexture* texture)
{
    if (texture == nil)
        return nullptr;
    return texture->_cxxTexture.get();
}

/*	The factories answer the Objective-C texture that cxx::OOTexture's make, autoreleased as
        before. A subclass sent them reached these same bodies (no subclass overrides them).
*/
+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory
                  options:(OOTextureFlags)options
               anisotropy:(GLfloat)anisotropy
                  lodBias:(GLfloat)lodBias
{
    return [[cxx::OOTexture::textureWithName(name, directory, options, anisotropy, lodBias).get() retain] autorelease];
}

+ (id)cxx_textureWithName:(const std::optional<std::string>&)name
                 inFolder:(const std::optional<std::string>&)directory
{
    return [[cxx::OOTexture::textureWithName(name, directory).get() retain] autorelease];
}

+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration
{
    return [[cxx::OOTexture::textureWithConfiguration(configuration).get() retain] autorelease];
}

+ (id)cxx_textureWithConfiguration:(const oo::PList&)configuration extraOptions:(OOTextureFlags)extraOptions
{
    return [[cxx::OOTexture::textureWithConfiguration(configuration, extraOptions).get() retain] autorelease];
}

+ (id)nullTexture
{
    return [[cxx::OOTexture::nullTexture().get() retain] autorelease];
}

+ (id)textureWithGenerator:(OOTextureGenerator*)generator
{
    return [[cxx::OOTexture::textureWithGenerator(generator).get() retain] autorelease];
}

+ (id)textureWithGenerator:(OOTextureGenerator*)generator enqueue:(BOOL)enqueue
{
    return [[cxx::OOTexture::textureWithGenerator(generator, enqueue).get() retain] autorelease];
}

// An Objective-C texture: [[X alloc] init] of a subclass (or of this class). Making the C++ part
// makes it one of every live texture, as -init did.
- (id)init
{
    self = [super init];
    if (self != nil)
        _cxxTexture = oo::makeRef<ObjCTexture>(self);
    return self;
}

// A C++ texture's facade (oo::ToObjC).
- (id)initWithCxxTexture:(cxx::OOTexture*)texture
{
    self = [super init];
    if (self != nil)
        _cxxTexture = oo::Ref<cxx::OOTexture>(texture);
    return self;
}

// A converted subclass's facade, made by its initialiser: the new C++ texture, and this is its peer.
- (id)initWithNewCxxTexture:(const oo::Ref<cxx::OOTexture>&)texture
{
    self = [super init];
    if (self != nil) {
        _cxxTexture = texture;
        @autoreleasepool {
            Peers().peerFor(_cxxTexture.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

// Every live texture forgets the C++ part when it is released (its destructor), after this.
- (void)dealloc
{
    if (ObjCTexture* objCTexture = AsObjCTexture(_cxxTexture.get()))
        objCTexture->ownerDeallocated();
    else
        Peers().forget(_cxxTexture.get());
    [super dealloc];
}

// A C++ texture's facade describes itself with the C++ class's name and components.
- (std::optional<std::string>)cxx_description
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return [super cxx_description];
    std::string result = oo::str::format("<%s %s>", ClassName(*_cxxTexture).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxTexture->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

// The short form (OOObject's, with the C++ texture's components; bead oo-qa7c).
- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return [super cxx_shortDescriptionComponents];
    return _cxxTexture->shortDescriptionComponents();
}

+ (void)applyNone
{
    cxx::OOTexture::applyNone();
}

+ (void)clearCache
{
    cxx::OOTexture::clearCache();
}

+ (void)rebindAllTextures
{
    cxx::OOTexture::rebindAllTextures();
}

/*	The overridable methods. On an Objective-C texture these are reached only when the subclass
        does not override them, or by [super ...]: the base class's own member answers. On a C++
        texture's facade the C++ override answers. (-cxx_descriptionComponents is not forwarded:
        OOObject's answers an Objective-C texture, and -cxx_description above a C++ one.)
*/

- (void)apply
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        _cxxTexture->cxx::OOTexture::apply();
    else
        _cxxTexture->apply();
}

- (void)ensureFinishedLoading
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        _cxxTexture->cxx::OOTexture::ensureFinishedLoading();
    else
        _cxxTexture->ensureFinishedLoading();
}

- (BOOL)isFinishedLoading
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::isFinishedLoading();
    return _cxxTexture->isFinishedLoading();
}

- (std::optional<std::string>)cxx_cacheKey
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::cacheKey();
    return _cxxTexture->cacheKey();
}

- (NSSize)dimensions
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::dimensions();
    return _cxxTexture->dimensions();
}

- (NSSize)originalDimensions
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::originalDimensions();
    return _cxxTexture->originalDimensions();
}

- (BOOL)isMipMapped
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::isMipMapped();
    return _cxxTexture->isMipMapped();
}

- (OOPixMap)copyPixMapRepresentation
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::copyPixMapRepresentation();
    return _cxxTexture->copyPixMapRepresentation();
}

- (BOOL)isRectangleTexture
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::isRectangleTexture();
    return _cxxTexture->isRectangleTexture();
}

- (BOOL)isCubeMap
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::isCubeMap();
    return _cxxTexture->isCubeMap();
}

- (NSSize)texCoordsScale
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::texCoordsScale();
    return _cxxTexture->texCoordsScale();
}

- (GLint)glTextureName
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::glTextureName();
    return _cxxTexture->glTextureName();
}

- (void)forceRebind
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        _cxxTexture->cxx::OOTexture::forceRebind();
    else
        _cxxTexture->forceRebind();
}

#ifdef OO_DEBUG_MONITOR_ENABLED
- (std::optional<std::string>)cxx_name
{
    if (AsObjCTexture(_cxxTexture.get()) != nullptr)
        return _cxxTexture->cxx::OOTexture::name();
    return _cxxTexture->name();
}

+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_cachedTexturesByAge
{
    return cxx::OOTexture::cachedTexturesByAge();
}

+ (std::vector<oo::ObjCRef<OOTexture*>>)cxx_allTextures
{
    return cxx::OOTexture::allTextures();
}

- (size_t)dataSize
{
    return _cxxTexture->dataSize();
}

- (void)setTrace:(BOOL)trace
{
    _cxxTexture->setTrace(trace);
}
#endif

@end

// OOTextureInternal.h's subclass interface.
@implementation OOTexture (SubclassInterface)

/*	An Objective-C texture whose initialiser released it before it reached -[OOTexture init] (an
        OOConcreteTexture with no loader) has no C++ part yet when its -dealloc uncaches it: nothing
        is cached, as its nil cache key made the old method do nothing.
*/
- (void)addToCaches
{
    if (_cxxTexture != nullptr)
        _cxxTexture->addToCaches();
}

- (void)removeFromCaches
{
    if (_cxxTexture != nullptr)
        _cxxTexture->removeFromCaches();
}

// The texture unretained, as the live-textures cache answered it (a caller may have no autorelease
// pool): an Objective-C texture, or a C++ texture's live facade. A C++ texture with no live facade
// gets a new one, autoreleased.
+ (OOTexture*)cxx_existingTextureForKey:(const std::optional<std::string>&)key
{
    cxx::OOTexture* texture = cxx::OOTexture::existingTextureForKey(key);
    if (ObjCTexture* objCTexture = AsObjCTexture(texture))
        return objCTexture->owner();
    if (id facade = Peers().livePeer(texture))
        return facade;
    return oo::ToObjC(texture);
}

@end
