/*

OOShaderProgram+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056): the Objective-C OOShaderProgram, a facade over the C++
cxx::OOShaderProgram (OOShaderProgram.h), for the callers that make and message programs
(DustEntity, and OOShaderMaterial and OOShaderUniform, which keep ::OOShaderProgram while it has a
facade: ADR-0056 amendment oo-rmd7 item 3). Its interface is the one OOShaderProgram.h declared
before the conversion, copied exactly, with one ivar, the C++ program. Imported as the last line of
OOShaderProgram.h; do not import it directly.

oo::ToObjC(oo::ToCxx(p)) == p (oo::ObjCPeers), so a cached program is one facade while it lives.
Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once every caller is C++.


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

#ifndef OOSHADERPROGRAM_OBJCBRIDGE_H
#define OOSHADERPROGRAM_OBJCBRIDGE_H

@interface OOShaderProgram : OOObject {
@private
    oo::Ref<cxx::OOShaderProgram> _cxxProgram;
}

+ (id)shaderProgramWithVertexShader:(const std::optional<std::string>&)vertexShaderSource
                     fragmentShader:(const std::optional<std::string>&)fragmentShaderSource
                   vertexShaderName:(const std::optional<std::string>&)vertexShaderName
                 fragmentShaderName:(const std::optional<std::string>&)fragmentShaderName
                             prefix:(const std::optional<std::string>&)prefixString // String prepended to program source (both vs and fs)
                  attributeBindings:(const oo::PList&)attributeBindings // Maps vertex attribute names to "locations".
                           cacheKey:(const std::optional<std::string>&)cacheKey;

// Loads a shader from a file, caching and sharing shader program instances.
+ (id)shaderProgramWithVertexShaderName:(const std::string&)vertexShaderName
                     fragmentShaderName:(const std::string&)fragmentShaderName
                                 prefix:(const std::optional<std::string>&)prefixString // String prepended to program source (both vs and fs)
                      attributeBindings:(const oo::PList&)attributeBindings; // Maps vertex attribute names to "locations".

- (void)apply;
+ (void)applyNone;

- (GLhandleARB)program;

@end

namespace oo {

// The program's live facade, or a new one; autoreleased. nil for null.
OOShaderProgram* ToObjC(cxx::OOShaderProgram* program);
inline OOShaderProgram* ToObjC(const Ref<cxx::OOShaderProgram>& program) { return ToObjC(program.get()); }

// The C++ program behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOShaderProgram* ToCxx(OOShaderProgram* program);

} // namespace oo

#endif // OOSHADERPROGRAM_OBJCBRIDGE_H
