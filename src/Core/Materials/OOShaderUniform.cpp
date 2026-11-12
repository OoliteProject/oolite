/*

OOShaderUniform.m


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

#include "OOShaderUniform.h"

#include "Entity.h"  // the shader binding targets' informal protocols (-superShaderBindingTarget)

#if OO_SHADERS

#include <string.h>

#include <format>

#include "OOFunctionAttributes.h"
#include "OOMaths.h"
#include "OOOpenGLExtensionManager.h"
#include "OOShaderProgram.h"
#include "OOShaderUniformMethodType.h"
#include "oofnd/String.hpp"

// The public initialisers, each [[self alloc] init...] of the old (self is
// result): a new uniform whose initialiser answered nil is dropped (null)
// instead of released.

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    GLint constValue) {
  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  if (!result->initWithName(uniformName, shaderProgram)) return nullptr;
  {
    result->type = kOOShaderUniformTypeInt;
    result->value.constInt = constValue;
  }

  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    GLfloat constValue) {
  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  if (!result->initWithName(uniformName, shaderProgram)) return nullptr;
  {
    result->type = kOOShaderUniformTypeFloat;
    result->value.constFloat = constValue;
  }

  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    GLfloat constValue[4]) {
  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  if (!result->initWithName(uniformName, shaderProgram)) return nullptr;
  {
    result->type = kOOShaderUniformTypeVector;
    memcpy(result->value.constVector, constValue,
           sizeof result->value.constVector);
  }

  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    OOColor* constValue) {
  if (EXPECT_NOT(constValue == nullptr)) {
    return nullptr;
  }

  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  if (!result->initWithName(uniformName, shaderProgram)) return nullptr;
  {
    result->type = kOOShaderUniformTypeVector;
    result->value.constVector[0] = constValue->redComponent();
    result->value.constVector[1] = constValue->greenComponent();
    result->value.constVector[2] = constValue->blueComponent();
    result->value.constVector[3] = constValue->alphaComponent();
  }

  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    Quaternion constValue, bool asMatrix) {
  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  if (!result->initWithName(uniformName, shaderProgram)) return nullptr;
  {
    if (asMatrix) {
      result->type = kOOShaderUniformTypeMatrix;
      result->value.constMatrix = OOMatrixForQuaternionRotation(constValue);
    } else {
      result->type = kOOShaderUniformTypeVector;
      result->value.constVector[0] = constValue.x;
      result->value.constVector[1] = constValue.y;
      result->value.constVector[2] = constValue.z;
      result->value.constVector[3] = constValue.w;
    }
  }

  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    OOMatrix constValue) {
  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  if (!result->initWithName(uniformName, shaderProgram)) return nullptr;
  {
    result->type = kOOShaderUniformTypeMatrix;
    result->value.constMatrix = constValue;
  }

  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    oo::RefCounted* target, const std::string& property, uint8_t boundType,
    OOShaderCxxBindingGetter get, OOUniformConvertOptions options) {
  /*	The selector initialiser's checks and log line, for a C++ target's
     member: the member's getter replaces the method found by selector, and the
     type is the method's return type it replaced. A target that is itself a
     C++ object has no super target.
  */
  if (EXPECT_NOT(shaderProgram == nullptr || get == nullptr)) return nullptr;
  if (EXPECT_NOT(boundType == kOOShaderUniformTypeInvalid ||
                 boundType >= kOOShaderUniformTypeCount))
    return nullptr;

  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  result->location =
      glGetUniformLocationARB(shaderProgram->program(), uniformName.c_str());
  if (result->location == -1) {
    OO_LOG("shader.uniform.bind.failed",
           "Could not bind uniform \"{}\" to {} (no uniform of that name could "
           "be found).",
           uniformName, property);
    return nullptr;
  }

  result->name = uniformName;
  result->isBinding = true;
  result->convertClamp = oo::Any(options & OOUniformConvertOptions::kClamp);
  result->convertNormalize =
      oo::Any(options & OOUniformConvertOptions::kNormalize);
  result->convertToMatrix =
      oo::Any(options & OOUniformConvertOptions::kToMatrix);
  result->type = boundType;
  result->value.binding.cxxGet = get;
  result->cxxTargetOnly = true;
  result->cxxProperty = property;
  result->cxxTarget = target;
  result->isActiveBinding = target != nullptr;
  return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithEntityTarget(
    const std::string& uniformName, OOShaderProgram* shaderProgram,
    Entity* target, const char* property, OOUniformConvertOptions options) {
  // The selector initialiser's checks and log line, its target the entity: the
  // same checks and log line, which names the class of the entity's object as
  // -[{} {}] did. The property is kept by name, where its selector was looked
  // up (a NULL name gave a NULL selector).
  if (EXPECT_NOT(shaderProgram == nullptr || property == nullptr))
    return nullptr;

  oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
  result->location =
      glGetUniformLocationARB(shaderProgram->program(), uniformName.c_str());
  if (result->location == -1) {
    const OOShaderEntityHooks* hooks = OOShaderEntityHooksIfSet();
    const std::string className =
        (target != nullptr && hooks != nullptr)
            ? hooks->className(target)
            : std::string("(null)");  // its object's class
    OO_LOG("shader.uniform.bind.failed",
           "Could not bind uniform \"{}\" to -[{} {}] (no uniform of that name "
           "could be found).",
           uniformName, className, property);
    return nullptr;
  }

  result->name = uniformName;
  result->isBinding = true;
  result->cxxProperty = property;
  result->convertClamp = oo::Any(options & OOUniformConvertOptions::kClamp);
  result->convertNormalize =
      oo::Any(options & OOUniformConvertOptions::kNormalize);
  result->convertToMatrix =
      oo::Any(options & OOUniformConvertOptions::kToMatrix);
  result->bindToSuper =
      oo::Any(options & OOUniformConvertOptions::kBindToSuperTarget);

  if (target != nullptr) result->setEntityBindingTarget(target);
  return result;
}

OOShaderUniform::~OOShaderUniform() {}

std::optional<std::string> OOShaderUniform::description() {
  std::optional<std::string> valueDesc;
  const char* valueType = nullptr;

  if (isBinding && entityMember) {
    // An entity's member: the class, the entity's address and the property.
    oo::RefCounted* cxxObject = cxxTarget.get();
    if (cxxObject != nullptr)
      valueDesc =
          std::format("[<{} {}> {}]", "Entity",
                      oo::str::pointerDescription(cxxObject), cxxProperty);
    else
      valueDesc = "0";
  } else if (isBinding && cxxTargetOnly) {
    // A C++ target: its address and the member's name.
    oo::RefCounted* cxxObject = cxxTarget.get();
    if (cxxObject != nullptr)
      valueDesc = std::format(
          "[<{}> {}]", oo::str::pointerDescription(cxxObject), cxxProperty);
    else
      valueDesc = "0";
  } else if (isBinding) {
    // Nothing bound (an entity binding no row answered).
    valueDesc = "0";
  } else {
    switch (type) {
      case kOOShaderUniformTypeInt:
        valueDesc = std::format("{}", value.constInt);
        break;

      case kOOShaderUniformTypeFloat:
        valueDesc = std::format("{:g}", value.constFloat);
        break;

      case kOOShaderUniformTypeVector: {
        Vector v = {value.constVector[0], value.constVector[1],
                    value.constVector[2]};
        valueDesc = VectorDescription(v);
      } break;

      case kOOShaderUniformTypeMatrix:
        valueDesc = OOMatrixDescription(value.constMatrix);
        break;
    }
  }

  switch (type) {
    case kOOShaderUniformTypeChar:
    case kOOShaderUniformTypeUnsignedChar:
    case kOOShaderUniformTypeShort:
    case kOOShaderUniformTypeUnsignedShort:
    case kOOShaderUniformTypeInt:
    case kOOShaderUniformTypeUnsignedInt:
    case kOOShaderUniformTypeLong:
    case kOOShaderUniformTypeUnsignedLong:
      valueType = "int";
      break;

    case kOOShaderUniformTypeFloat:
    case kOOShaderUniformTypeDouble:
      valueType = "float";
      break;

    case kOOShaderUniformTypeVector:
    case kOOShaderUniformTypeHPVector:
      valueType = "vec4";
      break;

    case kOOShaderUniformTypeQuaternion:
      valueType = "vec4 (quaternion)";
      break;

    case kOOShaderUniformTypeMatrix:
      valueType = "matrix";
      break;

    case kOOShaderUniformTypePoint:
      valueType = "vec2";
      break;

    case kOOShaderUniformTypeColor:  // what the colour bindings printed while
                                     // they were objects
    case kOOShaderUniformTypeObject:
      valueType = "object-binding";
      break;
  }
  if (valueType == nullptr) valueDesc = "INVALID";
  if (!valueDesc.has_value()) valueDesc = "INVALID";

  /*	Examples:
                  <OOShaderUniform 0xf00>{1: int tex1 = 1;}
                  <OOShaderUniform 0xf00>{3: float laser_heat_level =
     [<ShipEntity 0xba8> laserHeatLevel];} The class is named as a literal.
  */
  return std::format("<{} {}>{{{}: {} {} = {};}}", "OOShaderUniform",
                     oo::str::pointerDescription(this), location,
                     valueType != nullptr ? valueType : "(null)", name,
                     *valueDesc);
}

void OOShaderUniform::apply() {
  if (isBinding) {
    if (isActiveBinding) applyBinding();
  } else
    applySimple();
}

void OOShaderUniform::setEntityBindingTarget(Entity* target) {
  const OOShaderEntityHooks* hooks = OOShaderEntityHooksIfSet();

  if (!isBinding) return;
  if (cxxTargetOnly)
    return;  // a C++ target's member is bound once, by its factory

  /*	The steps for an entity target: the super target followed
     up the entities (superTarget hook), then the member table's row
     for the name, read from the entity.
  */
  entityMember = false;
  if (target != nullptr && hooks != nullptr && bindToSuper) {
    for (;;) {
      Entity* superCandidate = hooks->superTarget(target);
      if (superCandidate == nullptr || superCandidate == target) break;
      target = superCandidate;
    }
  }

  OOShaderMemberBinding memberBinding = {};
  if (target != nullptr && hooks != nullptr &&
      hooks->memberBinding(target, cxxProperty.c_str(), &memberBinding)) {
    value.binding.cxxGet = memberBinding.get;
    cxxTarget = memberBinding.target;
    type = memberBinding.type;
    entityMember = true;
    isActiveBinding = true;
    return;
  }

  /*	No row binds the name for this entity: the entity's object was bound by
     selector, which it did not answer (the member table holds every name the
     object answered), so the binding failed and was logged; with no object (or
     no hooks) nothing was bound or logged.
  */
  value.binding.cxxGet = nullptr;
  cxxTarget = nullptr;
  isActiveBinding = false;
  if (target != nullptr && hooks != nullptr &&
      hooks->className(target) != "(null)") {
    OO_LOG("shader.uniform.bind.failed",
           "Shader could not bind uniform \"{}\" to -[{} {}] ({}).", name,
           hooks->className(target), cxxProperty,
           "target does not respond to selector");
  }
}

// Designated initializer.
bool OOShaderUniform::initWithName(const std::string& uniformName,
                                   OOShaderProgram* shaderProgram) {
  bool OK = true;

  if (EXPECT_NOT(shaderProgram == nullptr)) OK = false;

  // ([super init] could not fail: the object is already constructed.)

  if (OK) {
    location =
        glGetUniformLocationARB(shaderProgram->program(), uniformName.c_str());
    if (location == -1) OK = false;
  }

  if (OK) {
    name = uniformName;
  }

  // [self release]; self = nil where !OK: the factory drops the object.
  return OK;
}

void OOShaderUniform::applySimple() {
  switch (type) {
    case kOOShaderUniformTypeInt:
      OOGL(glUniform1iARB(location, value.constInt));
      break;

    case kOOShaderUniformTypeFloat:
      OOGL(glUniform1fARB(location, value.constFloat));
      break;

    case kOOShaderUniformTypeVector:
      OOGL(glUniform4fvARB(location, 1, value.constVector));
      break;

    case kOOShaderUniformTypeMatrix:
      GLUniformMatrix(location, value.constMatrix);
  }
}

void OOShaderUniform::applyBinding() {
  GLint iVal;
  GLfloat fVal;
  Vector vVal;
  HPVector hpvVal;
  GLfloat expVVal[4];
  OOMatrix mVal;
  Quaternion qVal;
  NSPoint pVal = {};
  bool isInt = false, isFloat = false, isVector = false, isMatrix = false,
       isPoint = false;

  /*	Design note: if the object has been dealloced, or an exception occurs,
          do nothing. Shaders can specify a default value for uniforms, which
          will be used when no setting has been provided by the host program.

          I considered clearing value.binding.object if the underlying object is
          gone, but adding code to save a small amount of spacein a case that
          shouldn't occur in normal usage is silly.
  */
  // A member binding, or a C++ target's, reads its value once, into the field
  // its type uses. Nothing else is bound.
  OOShaderBindingValue member = {};
  if (!cxxTargetOnly && !entityMember) return;
  if (value.binding.cxxGet == nullptr) return;
  {
    // The C++ target (the entity, or the C++ object), held weakly: once it has
    // gone, nothing is set.
    oo::RefCounted* cxxObject = cxxTarget.get();
    if (cxxObject == nullptr) return;
    value.binding.cxxGet(cxxObject, member);
  }

  switch (type) {
    case kOOShaderUniformTypeChar:
    case kOOShaderUniformTypeUnsignedChar:
    case kOOShaderUniformTypeShort:
    case kOOShaderUniformTypeUnsignedShort:
    case kOOShaderUniformTypeInt:
    case kOOShaderUniformTypeUnsignedInt:
    case kOOShaderUniformTypeLong:
    case kOOShaderUniformTypeUnsignedLong:
      iVal = static_cast<GLint>(member.i);
      isInt = true;
      break;

    case kOOShaderUniformTypeFloat:
    case kOOShaderUniformTypeDouble:
      fVal = member.f;
      isFloat = true;
      break;

    case kOOShaderUniformTypeVector:
      vVal = member.v;
      if (convertNormalize) vVal = vector_normal(vVal);
      expVVal[0] = vVal.x;
      expVVal[1] = vVal.y;
      expVVal[2] = vVal.z;
      expVVal[3] = 1.0f;
      isVector = true;
      break;

    case kOOShaderUniformTypeHPVector:
      hpvVal = member.hpv;
      if (convertNormalize) hpvVal = HPvector_normal(hpvVal);
      expVVal[0] = static_cast<GLfloat>(hpvVal.x);
      expVVal[1] = static_cast<GLfloat>(hpvVal.y);
      expVVal[2] = static_cast<GLfloat>(hpvVal.z);
      expVVal[3] = 1.0f;
      isVector = true;
      break;

    case kOOShaderUniformTypeQuaternion:
      qVal = member.q;
      if (convertToMatrix) {
        mVal = OOMatrixForQuaternionRotation(qVal);
        isMatrix = true;
      } else {
        expVVal[0] = qVal.x;
        expVVal[1] = qVal.y;
        expVVal[2] = qVal.z;
        expVVal[3] = qVal.w;
        isVector = true;
      }
      break;

    case kOOShaderUniformTypeMatrix:
      mVal = member.m;
      isMatrix = true;
      break;

    case kOOShaderUniformTypePoint:
      pVal = member.p;
      isPoint = true;
      break;

    case kOOShaderUniformTypeObject:
      // An object that is not a colour: nothing set. (The number-object case
      // went with Foundation: no bindable method returns one; the whitelisted
      // object-valued bindings, laserColor and fogUniform, answer the C++
      // colour: the case below.)
      break;

    case kOOShaderUniformTypeColor:
      if (::OOColor* color = member.color) {
        expVVal[0] = color->redComponent();
        expVVal[1] = color->greenComponent();
        expVVal[2] = color->blueComponent();
        expVVal[3] = color->alphaComponent();
        isVector = true;
      }
      break;
  }

  if (isFloat) {
    if (convertClamp) fVal = OOClamp_0_1_f(fVal);
    OOGL(glUniform1fARB(location, fVal));
  } else if (isInt) {
    if (convertClamp) iVal = iVal ? 1 : 0;
    OOGL(glUniform1iARB(location, iVal));
  } else if (isPoint) {
    GLfloat v2[2] = {static_cast<GLfloat>(pVal.x),
                     static_cast<GLfloat>(pVal.y)};
    OOGL(glUniform2fvARB(location, 1, v2));
  } else if (isVector) {
    OOGL(glUniform4fvARB(location, 1, expVVal));
  } else if (isMatrix) {
    GLUniformMatrix(location, mVal);
  }
}

#endif  // OO_SHADERS
