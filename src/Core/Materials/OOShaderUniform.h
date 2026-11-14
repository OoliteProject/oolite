/*

OOShaderUniform.h

Manages a uniform variable for OOShaderMaterial.

C++20 since bead oo-n99o (proposed ADR-0056). The class is cxx::OOShaderUniform while
OOShaderUniform+ObjCBridge.h, imported at the end of this header, keeps the Objective-C
OOShaderUniform that its callers make and message; the bridge's deletion bead moves it out of
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

#ifndef OOSHADERUNIFORM_H
#define OOSHADERUNIFORM_H

#import "OOShaderMaterial.h"

#if OO_SHADERS

#import "OOColor.h"
#import "OOMaths.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

@class OOShaderProgram, OOWeakReference;

namespace cxx {

class OOShaderUniform : public oo::RefCounted {
public:
    ~OOShaderUniform() override;

    /*	The initialisers, as static factories of the same name (proposed ADR-0056 amendment
            oo-novu): null where the initialiser answered nil (no program, no uniform of that name in
            it, a nil colour, no selector).
    */
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, GLint constValue); // intValue:
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, GLfloat constValue); // floatValue:
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, GLfloat constValue[4]); // vectorValue:
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, OOColor* constValue); // colorValue: Converted to vector
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, Quaternion constValue, bool asMatrix); // quaternionValue:asMatrix: Converted to vector (in xyzw order, not wxyz!) or rotation matrix.
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, OOMatrix constValue); // matrixValue:

    /*	"Convert" has different meanings for different types.
            For float and int types, it clamps to the range [0, 1].
            For vector types, it normalizes.
            For quaternions, it converts to rotation matrix (instead of vec4).
    */
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName,
        ::OOShaderProgram* shaderProgram,
        id<OOWeakReferenceSupport> target, // boundToObject:
        SEL selector, // property:
        OOUniformConvertOptions options); // convertOptions:

    // The whole of what -cxx_description printed (amendment oo-3lj8 item 4).
    std::optional<std::string> description();

    void apply();

    void setBindingTarget(id<OOWeakReferenceSupport> target);

private:
    OOShaderUniform() = default;

    // Designated initializer (was private too).
    bool initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram);

    void applySimple();
    void applyBinding();

    std::string name = { };
    GLint location = { };
    uint8_t isBinding : 1 = { },
                        // flags that apply only to bindings:
        isActiveBinding : 1 = { },
                        convertClamp : 1 = { },
                        convertNormalize : 1 = { },
                        convertToMatrix : 1 = { },
                        bindToSuper : 1 = { };
    uint8_t type = { };
    union {
        GLint constInt;
        GLfloat constFloat;
        GLfloat constVector[4];
        OOMatrix constMatrix;
        struct
        {
            ::OOWeakReference* object;
            SEL selector;
            IMP method;
        } binding;
    } value = { };
};

} // namespace cxx

// Transitional: the Objective-C OOShaderUniform, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OOShaderUniform+ObjCBridge.h"

#endif // OO_SHADERS

#endif // OOSHADERUNIFORM_H
