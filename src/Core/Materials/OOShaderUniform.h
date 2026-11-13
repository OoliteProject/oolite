/*

OOShaderUniform.h

Manages a uniform variable for OOShaderMaterial.

OOShaderMaterial and DustEntity hold its uniforms as
std::shared_ptr<OOShaderUniform>.


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

#pragma once

#include "OOShaderMaterial.h"

#if OO_SHADERS

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOColor.h"
#include "OOFoundation.h"
#include "OOMaths.h"
#include "oofnd/Ref.hpp"

struct OOShaderBindingValue;  // OOShaderUniformMethodType.h
class Entity;                 // Entity.h: the materials' binding target

/*	A uniform bound to a C++ object's member: the getter reads the member
   into the field its type uses (OOShaderBindingValue), as a member table's row
   does for an entity target. The target is held weakly: once it has gone,
   -apply sets nothing.
*/
typedef void (*OOShaderCxxBindingGetter)(oo::Object* target,
                                         OOShaderBindingValue& outValue);

class OOShaderUniform : public oo::Object {
 public:
  ~OOShaderUniform() override;

  /*	The initialisers, as static factories of the same name: null where the
     initialiser answered nil (no program, no uniform of that name in it, a nil
     colour, no property name).
  */
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      GLint constValue);  // intValue:
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      GLfloat constValue);  // floatValue:
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      GLfloat constValue[4]);  // vectorValue:
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      OOColor* constValue);  // colorValue: Converted to vector
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      Quaternion constValue,
      bool asMatrix);  // quaternionValue:asMatrix: Converted to vector (in xyzw
                       // order, not wxyz!) or rotation matrix.
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      OOMatrix constValue);  // matrixValue:

  /*	"Convert" has different meanings for different types.
          For float and int types, it clamps to the range [0, 1].
          For vector types, it normalizes.
          For quaternions, it converts to rotation matrix (instead of vec4).
  */
  /*	Bound to a C++ target's member: property names the
     member (for the description and the log), type is the uniform type of its
     value (what the deleted selector path read from the bound method's return
     type), get reads it. Null where
     there is no program, no uniform of that name in it, no getter or an
     unbindable type. A null target binds nothing.
  */
  static std::shared_ptr<OOShaderUniform> initWithName(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      oo::Object* target, const std::string& property,
      uint8_t type,  // OOShaderUniformType (OOShaderUniformMethodType.h)
      OOShaderCxxBindingGetter get, OOUniformConvertOptions options);

  /*	Bound to an entity: the materials' binding target is the C++ entity. The
     property is read through the entities' member table where a row binds it
     (OOShaderEntityHooks, OOShaderUniformMethodType.h), the entity held weakly;
          any other name binds nothing and is logged, as the selector path that
     bound the entity's object did once that object had gone. A null target
     binds nothing. The property is named (NULL for none), where it was the
     selector.
  */
  static std::shared_ptr<OOShaderUniform> initWithEntityTarget(
      const std::string& uniformName, OOShaderProgram* shaderProgram,
      Entity* target, const char* property, OOUniformConvertOptions options);

  // The whole of what -description printed.
  std::optional<std::string> description();

  void apply();

  void setEntityBindingTarget(
      Entity* target);  // as initWithEntityTarget() binds

 private:
  OOShaderUniform() = default;

  // Designated initializer (was private too).
  bool initWithName(const std::string& uniformName,
                    OOShaderProgram* shaderProgram);

  void applySimple();
  void applyBinding();

  std::string name = {};
  GLint location = {};
  uint8_t isBinding
      : 1 = {},
        // flags that apply only to bindings:
      isActiveBinding : 1 = {}, convertClamp : 1 = {},
        convertNormalize : 1 = {}, convertToMatrix : 1 = {},
        bindToSuper : 1 = {},
        // bound to a C++ target by its factory, once
      cxxTargetOnly : 1 = {},
        // an entity's member through the table, the entity cxxTarget
      entityMember : 1 = {};
  uint8_t type = {};
  union {
    GLint constInt;
    GLfloat constFloat;
    GLfloat constVector[4];
    OOMatrix constMatrix;
    struct {
      // A C++ target's getter, or the entity's member found in the entities'
      // member table, or NULL where nothing is bound. The C++ object is
      // cxxTarget; the property's name is cxxProperty (an entity binding's
      // too).
      OOShaderCxxBindingGetter cxxGet;
    } binding;
  } value = {};
  std::weak_ptr<oo::Object> cxxTarget = {};
  std::string cxxProperty = {};
};

#endif  // OO_SHADERS
