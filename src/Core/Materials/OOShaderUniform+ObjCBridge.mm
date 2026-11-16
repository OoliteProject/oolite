/*

OOShaderUniform+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056): the Objective-C OOShaderUniform facade (see
OOShaderUniform+ObjCBridge.h). Each initialiser runs the C++ factory of the same name and adopts
the result, or answers nil; each method forwards in one line. Deleted with
OOShaderUniform+ObjCBridge.h.


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

#import "OOShaderUniform.h"

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

@interface OOShaderUniform (OOObjCBridgePrivate)

- (id)initWithCxxUniform:(cxx::OOShaderUniform*)uniform;
- (id)initWithNewCxxUniform:(const oo::Ref<cxx::OOShaderUniform>&)uniform;

@end

@implementation OOShaderUniform

// Inside the @implementation for the private ivar.
OOShaderUniform* oo::ToObjC(cxx::OOShaderUniform* uniform)
{
    return Peers().peerFor(uniform, [uniform] { return [[OOShaderUniform alloc] initWithCxxUniform:uniform]; });
}

cxx::OOShaderUniform* oo::ToCxx(OOShaderUniform* uniform)
{
    if (uniform == nil)
        return nullptr;
    return uniform->_cxxUniform.get();
}

// A C++ uniform's facade (oo::ToObjC): only stores it (it runs under the peer table's lock).
- (id)initWithCxxUniform:(cxx::OOShaderUniform*)uniform
{
    self = [super init];
    if (self != nil)
        _cxxUniform = oo::Ref<cxx::OOShaderUniform>(uniform);
    return self;
}

// [[OOShaderUniform alloc] init...]: nil (self released) where the C++ initialiser answered null,
// else the facade of the new uniform (proposed ADR-0056 amendment oo-bhb9 item 3).
- (id)initWithNewCxxUniform:(const oo::Ref<cxx::OOShaderUniform>&)uniform
{
    if (uniform == nullptr) {
        [self release];
        return nil;
    }
    self = [self initWithCxxUniform:uniform.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(uniform.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxUniform.get());
    [super dealloc];
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram intValue:(GLint)constValue
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, constValue)];
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram floatValue:(GLfloat)constValue
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, constValue)];
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram vectorValue:(GLfloat[4])constValue
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, constValue)];
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram colorValue:(OOColor*)constValue
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, oo::ToCxx(constValue))];
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram quaternionValue:(Quaternion)constValue asMatrix:(BOOL)asMatrix
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, constValue, asMatrix)];
}

- (id)initWithName:(const std::string&)uniformName shaderProgram:(OOShaderProgram*)shaderProgram matrixValue:(OOMatrix)constValue
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, constValue)];
}

- (id)initWithName:(const std::string&)uniformName
     shaderProgram:(OOShaderProgram*)shaderProgram
     boundToObject:(id<OOWeakReferenceSupport>)target
          property:(SEL)selector
    convertOptions:(OOUniformConvertOptions)options
{
    return [self initWithNewCxxUniform:cxx::OOShaderUniform::initWithName(uniformName, shaderProgram, target, selector, options)];
}

- (std::optional<std::string>)cxx_description
{
    return _cxxUniform->description();
}
- (void)apply
{
    _cxxUniform->apply();
}
- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
    _cxxUniform->setBindingTarget(target);
}

@end

#endif // OO_SHADERS
