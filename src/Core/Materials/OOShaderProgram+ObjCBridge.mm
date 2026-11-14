/*

OOShaderProgram+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056): the Objective-C OOShaderProgram facade (see
OOShaderProgram+ObjCBridge.h). Each method forwards in one line. Deleted with
OOShaderProgram+ObjCBridge.h.


Copyright (C) 2007-2013 Jens Ayton

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

#import "OOShaderProgram.h"

#if OO_SHADERS

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOShaderProgram (OOObjCBridgePrivate)

- (id)initWithCxxProgram:(cxx::OOShaderProgram*)program;

@end

@implementation OOShaderProgram

// Inside the @implementation for the private ivar.
OOShaderProgram* oo::ToObjC(cxx::OOShaderProgram* program)
{
    return Peers().peerFor(program, [program] { return [[OOShaderProgram alloc] initWithCxxProgram:program]; });
}

cxx::OOShaderProgram* oo::ToCxx(OOShaderProgram* program)
{
    if (program == nil)
        return nullptr;
    return program->_cxxProgram.get();
}

- (id)initWithCxxProgram:(cxx::OOShaderProgram*)program
{
    self = [super init];
    if (self != nil)
        _cxxProgram = oo::Ref<cxx::OOShaderProgram>(program);
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxProgram.get());
    [super dealloc];
}

// The autoreleased facade keeps the program alive until the pool drains, as the autoreleased
// program did; a cached program answers its live facade (proposed ADR-0056 amendment oo-ct7c).
+ (id)shaderProgramWithVertexShader:(const std::optional<std::string>&)vertexShaderSource
                     fragmentShader:(const std::optional<std::string>&)fragmentShaderSource
                   vertexShaderName:(const std::optional<std::string>&)vertexShaderName
                 fragmentShaderName:(const std::optional<std::string>&)fragmentShaderName
                             prefix:(const std::optional<std::string>&)prefixString
                  attributeBindings:(const oo::PList&)attributeBindings
                           cacheKey:(const std::optional<std::string>&)cacheKey
{
    return oo::ToObjC(cxx::OOShaderProgram::shaderProgramWithVertexShader(vertexShaderSource, fragmentShaderSource, vertexShaderName, fragmentShaderName, prefixString, attributeBindings, cacheKey));
}

+ (id)shaderProgramWithVertexShaderName:(const std::string&)vertexShaderName
                     fragmentShaderName:(const std::string&)fragmentShaderName
                                 prefix:(const std::optional<std::string>&)prefixString
                      attributeBindings:(const oo::PList&)attributeBindings
{
    return oo::ToObjC(cxx::OOShaderProgram::shaderProgramWithVertexShaderName(vertexShaderName, fragmentShaderName, prefixString, attributeBindings));
}

- (void)apply
{
    _cxxProgram->apply();
}
+ (void)applyNone
{
    cxx::OOShaderProgram::applyNone();
}
- (GLhandleARB)program
{
    return _cxxProgram->program();
}

@end

#endif // OO_SHADERS
