/*

OODefaultShaderSynthesizer+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-bm1q): the Objective-C facade over cxx::OODefaultShaderSynthesizer.
See OODefaultShaderSynthesizer+ObjCBridge.h. The shader stages (the Stages category) are implemented
in OODefaultShaderSynthesizer.mm, not here.

Copyright © 2011-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OODefaultShaderSynthesizer.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OODefaultShaderSynthesizer (OOObjCBridgePrivate)

- (id)initWithCxxSynthesizer:(cxx::OODefaultShaderSynthesizer*)synthesizer;

@end

@implementation OODefaultShaderSynthesizer

// Inside the @implementation for the private ivar.
OODefaultShaderSynthesizer* oo::ToObjC(cxx::OODefaultShaderSynthesizer* synthesizer)
{
    return Peers().peerFor(synthesizer, [synthesizer] { return [[OODefaultShaderSynthesizer alloc] initWithCxxSynthesizer:synthesizer]; });
}

cxx::OODefaultShaderSynthesizer* oo::ToCxx(OODefaultShaderSynthesizer* synthesizer)
{
    if (synthesizer == nil)
        return nullptr;
    return synthesizer->_cxxSynthesizer.get();
}

- (id)initWithMaterialConfiguration:(const oo::PList&)configuration
                        materialKey:(const std::optional<std::string>&)materialKey
                         entityName:(const std::optional<std::string>&)name
{
    self = [super init];
    if (self == nil)
        return nil;

    _cxxSynthesizer = oo::makeRef<cxx::OODefaultShaderSynthesizer>(configuration, materialKey, name);
    @autoreleasepool {
        Peers().peerFor(_cxxSynthesizer.get(), [self] { return [self retain]; });
    }
    return self;
}

- (id)initWithCxxSynthesizer:(cxx::OODefaultShaderSynthesizer*)synthesizer
{
    self = [super init];
    if (self != nil)
        _cxxSynthesizer = oo::Ref<cxx::OODefaultShaderSynthesizer>(synthesizer);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxSynthesizer.get());
    [super dealloc];
}

- (BOOL)run
{
    return _cxxSynthesizer->run();
}

- (std::string)vertexShader
{
    return _cxxSynthesizer->vertexShader();
}
- (std::string)fragmentShader
{
    return _cxxSynthesizer->fragmentShader();
}
- (oo::PList)textureSpecifications
{
    return _cxxSynthesizer->textureSpecifications();
}
- (oo::PList)uniformSpecifications
{
    return _cxxSynthesizer->uniformSpecifications();
}

- (std::optional<std::string>)materialKey
{
    return _cxxSynthesizer->materialKey();
}
- (std::optional<std::string>)entityName
{
    return _cxxSynthesizer->entityName();
}

- (void)composeVertexShader
{
    _cxxSynthesizer->composeVertexShader();
}
- (void)composeFragmentShader
{
    _cxxSynthesizer->composeFragmentShader();
}

- (void)appendVariable:(const std::string&)name ofType:(const std::string&)type withPrefix:(const std::string&)prefix to:(std::string&)buffer
{
    _cxxSynthesizer->appendVariable(name, type, prefix, buffer);
}
- (void)addAttribute:(const std::string&)name ofType:(const std::string&)type
{
    _cxxSynthesizer->addAttribute(name, type);
}
- (void)addVarying:(const std::string&)name ofType:(const std::string&)type
{
    _cxxSynthesizer->addVarying(name, type);
}
- (void)addVertexUniform:(const std::string&)name ofType:(const std::string&)type
{
    _cxxSynthesizer->addVertexUniform(name, type);
}
- (void)addFragmentUniform:(const std::string&)name ofType:(const std::string&)type
{
    _cxxSynthesizer->addFragmentUniform(name, type);
}

- (std::optional<std::string>)defineBindingUniform:(const oo::PList&)binding ofType:(const std::string&)type
{
    return _cxxSynthesizer->defineBindingUniform(binding, type);
}

- (std::optional<std::string>)readRGBForTextureSpec:(const oo::PList&)textureSpec mapName:(const std::string&)mapName
{
    return _cxxSynthesizer->readRGBForTextureSpec(textureSpec, mapName);
}
- (std::optional<std::string>)readOneChannelForTextureSpec:(const oo::PList&)textureSpec mapName:(const std::string&)mapName
{
    return _cxxSynthesizer->readOneChannelForTextureSpec(textureSpec, mapName);
}

- (NSUInteger)textureIDForSpec:(const oo::PList&)textureSpec
{
    return _cxxSynthesizer->textureIDForSpec(textureSpec);
}
- (void)setUpOneTexture:(const oo::PList&)textureSpec
{
    _cxxSynthesizer->setUpOneTexture(textureSpec);
}
- (void)getSampleName:(std::string*)outSampleName andSwizzleOp:(std::string*)outSwizzleOp forTextureSpec:(const oo::PList&)textureSpec
{
    _cxxSynthesizer->getSampleName(outSampleName, outSwizzleOp, textureSpec);
}

#ifndef NDEBUG
- (void)performStage:(SEL)stage
{
    _cxxSynthesizer->performStage(stage);
}
#endif

@end

@implementation OODefaultShaderSynthesizer (OOPrivate)

- (NSUInteger)assignIDForTexture:(const oo::PList&)textureSpec
{
    return _cxxSynthesizer->assignIDForTexture(textureSpec);
}

@end
