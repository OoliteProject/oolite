/*

OOOpenGLExtensionManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-z1s4): the Objective-C OOOpenGLExtensionManager facade
over cxx::OOOpenGLExtensionManager. Every method forwards to its C++ member. Deleted with
OOOpenGLExtensionManager+ObjCBridge.h.


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

#import "OOOpenGLExtensionManager.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOOpenGLExtensionManager (OOObjCBridgePrivate)

- (id)initWithCxxManager:(cxx::OOOpenGLExtensionManager*)manager;

@end

@implementation OOOpenGLExtensionManager

// Inside the @implementation for the private ivar.
OOOpenGLExtensionManager* oo::ToObjC(cxx::OOOpenGLExtensionManager* manager)
{
    return Peers().peerFor(manager, [manager] { return [[OOOpenGLExtensionManager alloc] initWithCxxManager:manager]; });
}

cxx::OOOpenGLExtensionManager* oo::ToCxx(OOOpenGLExtensionManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxManager.get();
}

- (id)initWithCxxManager:(cxx::OOOpenGLExtensionManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxManager = oo::Ref<cxx::OOOpenGLExtensionManager>(manager);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxManager.get());
    [super dealloc];
}

+ (OOOpenGLExtensionManager*)sharedManager
{
    // One facade for the life of the process, as there was one object (amendment oo-r7m0, item 5).
    static OOOpenGLExtensionManager* facade = nil;
    if (facade == nil)
        facade = [oo::ToObjC(cxx::OOOpenGLExtensionManager::sharedManager()) retain];
    return facade;
}

- (void)reset
{
    _cxxManager->reset();
}
- (BOOL)haveExtension:(const std::string&)extension
{
    return _cxxManager->haveExtension(extension);
}
- (BOOL)shadersSupported
{
    return _cxxManager->shadersSupported();
}
- (BOOL)shadersForceDisabled
{
    return _cxxManager->shadersForceDisabled();
}
- (OOGraphicsDetail)defaultDetailLevel
{
    return _cxxManager->defaultDetailLevel();
}
- (OOGraphicsDetail)maximumDetailLevel
{
    return _cxxManager->maximumDetailLevel();
}
- (GLint)textureImageUnitCount
{
    return _cxxManager->textureImageUnitCount();
}
- (BOOL)vboSupported
{
    return _cxxManager->vboSupported();
}
- (BOOL)fboSupported
{
    return _cxxManager->fboSupported();
}
- (BOOL)textureCombinersSupported
{
    return _cxxManager->textureCombinersSupported();
}
- (GLint)textureUnitCount
{
    return _cxxManager->textureUnitCount();
}
- (NSUInteger)majorVersionNumber
{
    return _cxxManager->majorVersionNumber();
}
- (NSUInteger)minorVersionNumber
{
    return _cxxManager->minorVersionNumber();
}
- (NSUInteger)releaseVersionNumber
{
    return _cxxManager->releaseVersionNumber();
}

- (void)getVersionMajor:(unsigned*)outMajor minor:(unsigned*)outMinor release:(unsigned*)outRelease
{
    _cxxManager->getVersionMajor(outMajor, outMinor, outRelease);
}

- (BOOL)versionIsAtLeastMajor:(unsigned)maj minor:(unsigned)min
{
    return _cxxManager->versionIsAtLeastMajor(maj, min);
}

- (std::optional<std::string>)vendorString
{
    return _cxxManager->vendorString();
}
- (std::optional<std::string>)rendererString
{
    return _cxxManager->rendererString();
}
- (BOOL)usePointSmoothing
{
    return _cxxManager->usePointSmoothing();
}
- (BOOL)useLineSmoothing
{
    return _cxxManager->useLineSmoothing();
}
- (BOOL)useDustShader
{
    return _cxxManager->useDustShader();
}

@end
