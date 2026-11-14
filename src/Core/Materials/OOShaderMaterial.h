/*

OOShaderMaterial.h

Managers a combination of a shader program, textures and uniforms.

C++20 since bead oo-ja7y (proposed ADR-0056, amendments oo-smy and oo-vl43). Its Objective-C
facade was deleted by bead oo-9ht.46 (ADR-0056 amendment "deleting a facade"): the class is global,
and Objective-C sees one as an OOMaterial (OOBasicMaterial's facade was deleted by bead oo-9ht.33). The two informal protocols on
OOObject that shader binding targets implement (-superShaderBindingTarget, -randomSeedForShaders)
moved with it to their implementers' header, Entity+ObjCBridge.h.


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

#ifndef OOSHADERMATERIAL_H
#define OOSHADERMATERIAL_H

#include "OOBasicMaterial.h"
#include "OOMaths.h"
#include "OOShaderProgram.h"
#include "oofnd/PList.hpp"

#include <map>
#include <optional>
#include <string>
#include <vector>

#if OO_SHADERS

class OOTexture;
class OOShaderUniform;
class Entity; // Entity.h: the binding target (bead oo-9ht.39.6)

enum {
    // Conversion settings for uniform bindings
    kOOUniformConvertClamp = 0x0001U,
    kOOUniformConvertNormalize = 0x0002U,
    kOOUniformConvertToMatrix = 0x0004U,
    kOOUniformBindToSuperTarget = 0x0008U,

    kOOUniformConvertDefaults = kOOUniformConvertToMatrix | kOOUniformBindToSuperTarget
};
typedef uint16_t OOUniformConvertOptions;

class OOShaderMaterial : public OOBasicMaterial {
public:
    ~OOShaderMaterial() override;

    static bool configurationDictionarySpecifiesShaderMaterial(const oo::PList& configuration); // null -> false

    /*	Set up an OOShaderMaterial.

            Configuration should be a dictionary equivalent to an entry in a
            shipdata.plist "shaders" dictionary. Specifically, keys OOShaderMaterial
            will look for are currently:
                    textures			array of texture file names.
                    vertex_shader		name of vertex shader file.
                    fragment_shader		name of fragment shader file.
                    uniforms			dictionary of uniforms. Values are either reals or
                                                            dictionaries containing:
                            type			"int", "texture" or "float"
                            value			number
                    gloss			gloss value of material, float between 0.0 and 1.0, defaults to 0.5

            Macros is a dictionary which is converted to macro definitions and
            prepended to shader source code. It should be used to specify the
            availability if uniforms you tend to register, and other macros such as
            bug fix identifiers. For example, the
            dictionary:
                    { "OO_ENGINE_LEVEL" = 1; }

            will be transformed into:
                    #define OO_ENGINE_LEVEL 1

            Null where the initialiser failed (it answered nil).
    */
    static oo::Ref<OOShaderMaterial> shaderMaterialWithName(const std::optional<std::string>& name,
        const oo::PList& configuration, // null = nil
        const oo::PList& macros, // null = nil
        Entity* target);

    // Runs once, right after construction (proposed ADR-0056, amendment oo-vl43); false where the
    // Objective-C initialiser answered nil.
    bool initWithName(const std::optional<std::string>& name,
        const oo::PList& configuration, // null = nil
        const oo::PList& macros, // null = nil
        Entity* target);

    /*	Bind a uniform to a property of an object.

            property should name a method of source which returns the desired
            value; it will be called every time -apply is, assuming uniformName is
            used in the shader. (If not, OOShaderMaterial will not track the binding.)
            NULL names none, which binds nothing; it was the method's selector until
            bead oo-xu228.3.2.

            A bound method must not take any parameters, and must return one of the
            following types:
                    * Any integer or float type.
                    * A number object.
                    * Vector.
                    * Quaternion.
                    * OOMatrix.
                    * OOColor.

            The "convert" flag has different meanings for different types:
                    * For int, float or a number object, it clamps to the range [0..1].
                    * For Vector, it normalizes.
                    * For Quaternion, it converts to a rotation matrix (instead of a vector).

            NOTE: this method *does not* check against the whitelist. See
            bindSafeUniform() below.
    */
    bool bindUniform(const std::string& uniformName,
        Entity* target,
        const char* property,
        OOUniformConvertOptions options);

    /*	Bind a uniform to a property of an object.

            This is similar to bindUniform(), except
            that it checks against OOUniformBindingPermitted().
    */
    bool bindSafeUniform(const std::string& uniformName,
        Entity* target,
        const std::optional<std::string>& property, // nullopt: no property (not bound)
        OOUniformConvertOptions options);

    /*	Set a uniform value. The five selectors share their first keyword, so they are overloads
            (ADR-0056 item 3); the comment names each one's second keyword.
    */
    void setUniform(const std::string& uniformName, int value); // intValue:
    void setUniform(const std::string& uniformName, float value); // floatValue:
    void setUniform(const std::string& uniformName, GLfloat value[4]); // vectorValue:
    void setUniform(const std::string& uniformName, const oo::PList& value); // vectorObjectValue: Array of four numbers, or something that can be OOVectorFromObject()ed.
    void setUniform(const std::string& uniformName, Quaternion value, bool asMatrix); // quaternionValue:asMatrix:

    /*	Add constant uniforms. Same format as uniforms dictionary of configuration
            parameter to initWithName(). The target parameter is used
            for bindings.

            Additionally, the target may implement the following method, used to seed
            any random bindings:
                    - (uint32_t) randomSeedForShaders;
    */
    void addUniformsFromDictionary(const oo::PList& uniformDefs, Entity* target);

    bool doApply() override;
    void ensureFinishedLoading() override;
    bool isFinishedLoading() override;
    void unapplyWithNext(OOMaterial* next) override;
    size_t objectSize() const override { return sizeof *this; }
    void setBindingTarget(Entity* target) override;
    bool permitSpecular() override;
#ifdef OO_DEBUG_MONITOR_ENABLED
    std::vector<oo::Ref<OOTexture>> allTextures() override;
#endif

private:
    // Convert a "textures" array (texture specifiers) to texture objects.
    std::vector<oo::Ref<OOTexture>> loadTexturesFromArray(const oo::PList& textureSpecs, GLuint max);

    // Load up an array of texture objects.
    void addTexturesFromArray(const std::vector<oo::Ref<OOTexture>>& textureObjects, GLuint max);

    oo::Ref<OOShaderProgram> shaderProgram = { };
    std::map<std::string, oo::Ref<OOShaderUniform>, std::less<>> uniforms; // no `= {}` (GCC, incomplete T; bead oo-1q4); by uniform name (C++ since bead oo-9ht.55 deleted OOShaderUniform's facade)

    uint32_t texCount = { };
    OOTexture** textures = { };
};

enum {
    /*	ID of vertex attribute used for tangents. A fixed ID is used for
            simplicty.
            NOTE: on Nvidia hardware, attribute 15 is aliased to
            gl_MultiTexCoord7. This is not expected to become a problem.
    */
    kTangentAttributeIndex = 15
};

/*	OOUniformBindingPermitted()

        Predicate determining whether a given property may be used as a binding.
        Client code is responsible for implementing this.
*/
BOOL OOUniformBindingPermitted(const std::string& propertyName, Entity* bindingTarget); // the entity (bead oo-9ht.39.6)

// Material specifier dictionary keys.
inline constexpr const char* kOOVertexShaderSourceKey = "_oo_vertex_shader_source";
inline constexpr const char* kOOVertexShaderNameKey = "vertex_shader";
inline constexpr const char* kOOFragmentShaderSourceKey = "_oo_fragment_shader_source";
inline constexpr const char* kOOFragmentShaderNameKey = "fragment_shader";
inline constexpr const char* kOOTexturesKey = "textures";
inline constexpr const char* kOOTextureObjectsKey = "_oo_texture_objects";
inline constexpr const char* kOOUniformsKey = "uniforms";
inline constexpr const char* kOOIsSynthesizedMaterialConfigurationKey = "_oo_is_synthesized_config";
inline constexpr const char* kOOIsSynthesizedMaterialMacrosKey = "_oo_synthesized_material_macros";

#endif // OO_SHADERS

#endif // OOSHADERMATERIAL_H
