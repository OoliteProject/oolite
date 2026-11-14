/*

OOShaderUniform.h

Manages a uniform variable for OOShaderMaterial.

C++20 since bead oo-n99o (proposed ADR-0056). Its Objective-C facade was deleted by bead oo-9ht.55
(ADR-0056 amendment "deleting a facade"): the class is global, and OOShaderMaterial and DustEntity
hold its uniforms as oo::Ref<OOShaderUniform>.


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

#include "OOShaderMaterial.h"

#if OO_SHADERS

#include "OOColor.h"
#include "OOMaths.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

#include "OOFoundation.h"

struct OOShaderBindingValue; // OOShaderUniformMethodType.h (bead oo-9ht.158)
class Entity; // Entity.h: the materials' binding target (bead oo-9ht.39.6)

/*	A uniform bound to a C++ object's member (bead oo-t0e2m, ADR-0056 amendment oo-t0e2m): the
        getter reads the member into the field its type uses (OOShaderBindingValue), as a member table's
        row does for an Objective-C target. The target is held weakly: once it has gone, -apply sets
        nothing, as for an Objective-C target that has gone.
*/
typedef void (*OOShaderCxxBindingGetter)(oo::RefCounted* target, OOShaderBindingValue& outValue);

class OOShaderUniform : public oo::RefCounted {
public:
    ~OOShaderUniform() override;

    /*	The initialisers, as static factories of the same name (proposed ADR-0056 amendment
            oo-novu): null where the initialiser answered nil (no program, no uniform of that name in
            it, a nil colour, no property name).
    */
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram, GLint constValue); // intValue:
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram, GLfloat constValue); // floatValue:
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram, GLfloat constValue[4]); // vectorValue:
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram, OOColor* constValue); // colorValue: Converted to vector
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram, Quaternion constValue, bool asMatrix); // quaternionValue:asMatrix: Converted to vector (in xyzw order, not wxyz!) or rotation matrix.
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram, OOMatrix constValue); // matrixValue:

    /*	"Convert" has different meanings for different types.
            For float and int types, it clamps to the range [0, 1].
            For vector types, it normalizes.
            For quaternions, it converts to rotation matrix (instead of vec4).
    */
    /*	Bound to a C++ target's member (bead oo-t0e2m): property names the member (for the
            description and the log), type is the uniform type of its value (what the deleted selector
            path read from the bound method's return type), get reads it. (The Objective-C target's
            factory, boundToObject:property:convertOptions:, and its setBindingTarget() went with bead
            oo-4aq6a.7: no game code bound an Objective-C object.) Null where there is no program, no
            uniform of that name in it, no getter or an unbindable type. A null target binds nothing.
    */
    static oo::Ref<OOShaderUniform> initWithName(const std::string& uniformName,
        OOShaderProgram* shaderProgram,
        oo::RefCounted* target,
        const std::string& property,
        uint8_t type, // OOShaderUniformType (OOShaderUniformMethodType.h)
        OOShaderCxxBindingGetter get,
        OOUniformConvertOptions options);

    /*	Bound to an entity (bead oo-9ht.39.6, ADR-0056 amendment oo-9ht.39.6): the materials' binding
            target is the C++ entity. The property is read through the entities' member table where a
            row binds it (OOShaderEntityHooks, OOShaderUniformMethodType.h), the entity held weakly;
            any other name binds nothing and is logged, as the selector path that bound the entity's
            object did once that object had gone (bead oo-dpyk8). A null target binds nothing.
            The property is named (NULL for none), where it was the selector (bead oo-xu228.3.2).
    */
    static oo::Ref<OOShaderUniform> initWithEntityTarget(const std::string& uniformName,
        OOShaderProgram* shaderProgram,
        Entity* target,
        const char* property,
        OOUniformConvertOptions options);

    // The whole of what -cxx_description printed (amendment oo-3lj8 item 4).
    std::optional<std::string> description();

    void apply();

    void setEntityBindingTarget(Entity* target); // bead oo-9ht.39.6: as initWithEntityTarget() binds

private:
    OOShaderUniform() = default;

    // Designated initializer (was private too).
    bool initWithName(const std::string& uniformName, OOShaderProgram* shaderProgram);

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
                        bindToSuper : 1 = { },
                        // bound to a C++ target by its factory, once (bead oo-t0e2m)
        cxxTargetOnly : 1 = { },
                        // an entity's member through the table, the entity cxxTarget (bead oo-9ht.39.6)
        entityMember : 1 = { };
    uint8_t type = { };
    union {
        GLint constInt;
        GLfloat constFloat;
        GLfloat constVector[4];
        OOMatrix constMatrix;
        struct
        {
            // A C++ target's getter (bead oo-t0e2m), or the entity's member found in the entities'
            // member table (bead oo-9ht.39.6), or NULL where nothing is bound. The C++ object is
            // cxxTarget; the property's name is cxxProperty (an entity binding's too, where it was
            // the selector's name until bead oo-4aq6a.7 deleted the Objective-C target).
            OOShaderCxxBindingGetter cxxGet;
        } binding;
    } value = { };
    oo::WeakRef<oo::RefCounted> cxxTarget = { };
    std::string cxxProperty = { };
};

#endif // OO_SHADERS

#endif // OOSHADERUNIFORM_H
