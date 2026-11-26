/*

OOShaderProgram.h

Encapsulates a vertex + fragment shader combo. In general, this should only be
used though OOShaderMaterial. The point of this separation is that more than
one OOShaderMaterial can use the same OOShaderProgram.

C++20 since bead oo-f9zg (proposed ADR-0056). The class is cxx::OOShaderProgram while
OOShaderProgram+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOShaderProgram that its callers make and message; the bridge's deletion bead moves it out of
namespace cxx.

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

#ifndef OOSHADERPROGRAM_H
#define OOSHADERPROGRAM_H

#import "OOFoundation.h"
#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "oofnd/objc/OOObject.h"

#if OO_SHADERS

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-vqvw): shader sources, names, prefix and cache key
        are nil-able strings (std::optional: a missing source means no shader of that kind, an empty
        prefix counts as none). Attribute bindings are a property-list dictionary of attribute name ->
        location (oo::PList, null for none).
*/
namespace cxx {

class OOShaderProgram : public oo::RefCounted {
public:
    ~OOShaderProgram() override;

    // Null where no program could be made (it answered nil).
    static oo::Ref<OOShaderProgram> shaderProgramWithVertexShader(const std::optional<std::string>& vertexShaderSource,
        const std::optional<std::string>& fragmentShaderSource,
        const std::optional<std::string>& vertexShaderName,
        const std::optional<std::string>& fragmentShaderName,
        const std::optional<std::string>& prefixString, // String prepended to program source (both vs and fs)
        const oo::PList& attributeBindings, // Maps vertex attribute names to "locations".
        const std::optional<std::string>& cacheKey);

    // Loads a shader from a file, caching and sharing shader program instances.
    static oo::Ref<OOShaderProgram> shaderProgramWithVertexShaderName(const std::string& vertexShaderName,
        const std::string& fragmentShaderName,
        const std::optional<std::string>& prefixString, // String prepended to program source (both vs and fs)
        const oo::PList& attributeBindings); // Maps vertex attribute names to "locations".

    void apply();
    static void applyNone();

    GLhandleARB program();

private:
    OOShaderProgram() = default;

    bool initWithVertexShaderSource(const std::optional<std::string>& vertexSource,
        const std::optional<std::string>& fragmentSource,
        const std::optional<std::string>& prefixString,
        const std::optional<std::string>& vertexName,
        const std::optional<std::string>& fragmentName,
        const oo::PList& attributeBindings,
        const std::optional<std::string>& key);

    void bindAttributes(const oo::PList& attributeBindings);
    void bindStandardMatrixUniforms();

    // The leading underscore: program() is the getter's name (amendment oo-rdfh).
    GLhandleARB _program = { };
    std::optional<std::string> key = { };
    oo::PList standardMatrixUniformLocations = { };
};

} // namespace cxx

/*	Translate the subset of GLSL 3.30 used by Oolite's post-processing shaders
        to GLSL 1.20 (plus GL_EXT_gpu_shader4). Only top-level declarations are
        rewritten, so in/out parameter qualifiers inside functions are untouched.
   A vertex shader's layout(location = N) inputs are added to attributeBindings.
   The macOS legacy context only supports GLSL 1.20, so
   shaderProgramWithVertexShaderName() calls this there (OOLITE_MACOS); it is
   built everywhere so the unit tests run it.
*/
std::optional<std::string> OOTranslateGLSL330To120(
    const std::optional<std::string>& source, bool isVertexShader,
    oo::PList::Dict& attributeBindings);

// Transitional: the Objective-C OOShaderProgram, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OOShaderProgram+ObjCBridge.h"

#endif // OO_SHADERS

#endif // OOSHADERPROGRAM_H
