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

#import "OOShaderUniform.h"
#include "oofnd/objc/OORuntime.h"

#if OO_SHADERS

#import "OOFunctionAttributes.h"
#import "OOMaths.h"
#import "OOOpenGLExtensionManager.h"
#import "OOShaderProgram.h"
#import "OOShaderUniformMethodType.h"
#include <string.h>

#include "oofnd/String.hpp"

namespace cxx {

// The public initialisers, each [[self alloc] init...] of the old (self is result): a new uniform
// whose initialiser answered nil is dropped (null) instead of released.

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, GLint constValue)
{
    oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
    if (!result->initWithName(uniformName, shaderProgram))
        return nullptr;
    {
        result->type = kOOShaderUniformTypeInt;
        result->value.constInt = constValue;
    }

    return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, GLfloat constValue)
{
    oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
    if (!result->initWithName(uniformName, shaderProgram))
        return nullptr;
    {
        result->type = kOOShaderUniformTypeFloat;
        result->value.constFloat = constValue;
    }

    return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, GLfloat constValue[4])
{
    oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
    if (!result->initWithName(uniformName, shaderProgram))
        return nullptr;
    {
        result->type = kOOShaderUniformTypeVector;
        memcpy(result->value.constVector, constValue, sizeof result->value.constVector);
    }

    return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, OOColor* constValue)
{
    if (EXPECT_NOT(constValue == nullptr)) {
        return nullptr;
    }

    oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
    if (!result->initWithName(uniformName, shaderProgram))
        return nullptr;
    {
        result->type = kOOShaderUniformTypeVector;
        result->value.constVector[0] = constValue->redComponent();
        result->value.constVector[1] = constValue->greenComponent();
        result->value.constVector[2] = constValue->blueComponent();
        result->value.constVector[3] = constValue->alphaComponent();
    }

    return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, Quaternion constValue, bool asMatrix)
{
    oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
    if (!result->initWithName(uniformName, shaderProgram))
        return nullptr;
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

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram, OOMatrix constValue)
{
    oo::Ref<OOShaderUniform> result = oo::adopt(new OOShaderUniform());
    if (!result->initWithName(uniformName, shaderProgram))
        return nullptr;
    {
        result->type = kOOShaderUniformTypeMatrix;
        result->value.constMatrix = constValue;
    }

    return result;
}

oo::Ref<OOShaderUniform> OOShaderUniform::initWithName(const std::string& uniformName,
    ::OOShaderProgram* shaderProgram,
    id<OOWeakReferenceSupport> target,
    SEL selector,
    OOUniformConvertOptions options)
{
    BOOL OK = YES;
    oo::Ref<OOShaderUniform> result;

    if (EXPECT_NOT(shaderProgram == NULL || selector == NULL))
        OK = NO;

    if (OK) {
        result = oo::adopt(new OOShaderUniform());
    }

    if (OK) {
        result->location = glGetUniformLocationARB([shaderProgram program], uniformName.c_str());
        if (result->location == -1) {
            OK = NO;
            OO_LOG("shader.uniform.bind.failed", "Could not bind uniform \"{}\" to -[{} {}] (no uniform of that name could be found).", uniformName, oo::DescriptionOf([target class]), OOSelectorName(selector));
        }
    }

    // If we're still OK, it's a bindable method.
    if (OK) {
        result->name = uniformName;
        result->isBinding = YES;
        result->value.binding.selector = selector;

        result->convertClamp = (options & kOOUniformConvertClamp) != 0;
        result->convertNormalize = (options & kOOUniformConvertNormalize) != 0;
        result->convertToMatrix = (options & kOOUniformConvertToMatrix) != 0;
        result->bindToSuper = (options & kOOUniformBindToSuperTarget) != 0;

        if (target != nil)
            result->setBindingTarget(target);
    }

    if (!OK) {
        return nullptr; // [self release]; self = nil
    }
    return result;
}

OOShaderUniform::~OOShaderUniform()
{
    if (isBinding)
        [value.binding.object release];
}

std::optional<std::string> OOShaderUniform::description()
{
    std::optional<std::string> valueDesc;
    const char* valueType = nullptr;
    id object;

    if (isBinding) {
        object = [value.binding.object weakRefUnderlyingObject];
        if (object != nil) {
            valueDesc = oo::str::format("[<%s %s> %s]", oo::DescriptionOf([object class]).c_str(), oo::str::pointerDescription(value.binding.object).c_str(), OOSelectorName(value.binding.selector));
        } else {
            valueDesc = "0";
        }
    } else {
        switch (type) {
        case kOOShaderUniformTypeInt:
            valueDesc = oo::str::format("%i", value.constInt);
            break;

        case kOOShaderUniformTypeFloat:
            valueDesc = oo::str::format("%g", value.constFloat);
            break;

        case kOOShaderUniformTypeVector: {
            Vector v = { value.constVector[0], value.constVector[1], value.constVector[2] };
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

    case kOOShaderUniformTypeObject:
        valueType = "object-binding";
        break;
    }
    if (valueType == nullptr)
        valueDesc = "INVALID";
    if (!valueDesc.has_value())
        valueDesc = "INVALID";

    /*	Examples:
                    <OOShaderUniform 0xf00>{1: int tex1 = 1;}
                    <OOShaderUniform 0xf00>{3: float laser_heat_level = [<ShipEntity 0xba8> laserHeatLevel];}
            The class is named as a literal and the address is the facade's, as [self class] and self
            were (amendments oo-3lj8 item 4 and oo-bhb9 item 6).
    */
    return oo::str::format("<%s %s>{%i: %s %s = %s;}", "OOShaderUniform", oo::str::pointerDescription(oo::ToObjC(this)).c_str(), location, valueType != nullptr ? valueType : "(null)", name.c_str(), valueDesc->c_str());
}

void OOShaderUniform::apply()
{

    if (isBinding) {
        if (isActiveBinding)
            applyBinding();
    } else
        applySimple();
}

void OOShaderUniform::setBindingTarget(id<OOWeakReferenceSupport> target)
{
    BOOL OK = YES;
    Method method = NULL;
    NSUInteger argCount;
    std::string methodProblem;
    id<OOWeakReferenceSupport> superCandidate = nil;

    if (!isBinding)
        return;

    // Resolve "supertarget" if applicable
    if (bindToSuper) {
        for (;;) {
            if (![target respondsToSelector:OOSelectorFromName("superShaderBindingTarget")])
                break;

            superCandidate = [(id)target superShaderBindingTarget];
            if (superCandidate == nil || superCandidate == target)
                break;
            target = superCandidate;
        }
    }

    [value.binding.object release];
    value.binding.object = [target weakRetain];

    if (target == nil) {
        isActiveBinding = NO;
        return;
    }

    if (OK) {
        if (![target respondsToSelector:value.binding.selector]) {
            methodProblem = "target does not respond to selector";
            OK = NO;
        }
    }

    if (OK) {
        value.binding.method = [(id)target methodForSelector:value.binding.selector];
        if (value.binding.method == NULL) {
            methodProblem = "could not retrieve method implementation";
            OK = NO;
        }
    }

    if (OK) {
        method = class_getInstanceMethod(object_getClass((id)target), value.binding.selector);
        if (method == NULL) {
            methodProblem = "could not retrieve method signature";
            OK = NO;
        }
    }

    if (OK) {
        argCount = method_getNumberOfArguments(method);
        if (argCount != 2) // "no-arguments" methods actually take two arguments, self and _msg.
        {
            methodProblem = "only methods which do not require arguments may be bound to";
            OK = NO;
        }
    }

    if (OK) {
        type = OOShaderUniformTypeFromMethod(method);
        if (type == kOOShaderUniformTypeInvalid) {
            OK = NO;
            char* returnType = method_copyReturnType(method);
            methodProblem = oo::str::format("unsupported type \"%s\"", returnType);
            free(returnType);
        }
    }

    isActiveBinding = OK;
    if (!OK)
        OO_LOG("shader.uniform.bind.failed", "Shader could not bind uniform \"{}\" to -[{} {}] ({}).", name, oo::DescriptionOf([target class]), OOSelectorName(value.binding.selector), methodProblem);
}

// Designated initializer.
bool OOShaderUniform::initWithName(const std::string& uniformName, ::OOShaderProgram* shaderProgram)
{
    BOOL OK = YES;

    if (EXPECT_NOT(shaderProgram == NULL))
        OK = NO;

    // ([super init] could not fail: the object is already constructed.)

    if (OK) {
        location = glGetUniformLocationARB([shaderProgram program], uniformName.c_str());
        if (location == -1)
            OK = NO;
    }

    if (OK) {
        name = uniformName;
    }

    // [self release]; self = nil where !OK: the factory drops the object.
    return OK;
}

void OOShaderUniform::applySimple()
{
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

void OOShaderUniform::applyBinding()
{

    id object = nil;
    GLint iVal;
    GLfloat fVal;
    Vector vVal;
    HPVector hpvVal;
    GLfloat expVVal[4];
    OOMatrix mVal;
    Quaternion qVal;
    NSPoint pVal = { 0 };
    BOOL isInt = NO, isFloat = NO, isVector = NO, isMatrix = NO, isPoint = NO;
    id objVal = nil;

    /*	Design note: if the object has been dealloced, or an exception occurs,
            do nothing. Shaders can specify a default value for uniforms, which
            will be used when no setting has been provided by the host program.

            I considered clearing value.binding.object if the underlying object is
            gone, but adding code to save a small amount of spacein a case that
            shouldn't occur in normal usage is silly.
    */
    object = [value.binding.object weakRefUnderlyingObject];
    if (object == nil)
        return;

    switch (type) {
    case kOOShaderUniformTypeChar:
    case kOOShaderUniformTypeUnsignedChar:
    case kOOShaderUniformTypeShort:
    case kOOShaderUniformTypeUnsignedShort:
    case kOOShaderUniformTypeInt:
    case kOOShaderUniformTypeUnsignedInt:
    case kOOShaderUniformTypeLong:
    case kOOShaderUniformTypeUnsignedLong:
        iVal = (GLint)OOCallIntegerMethod(object, value.binding.selector, value.binding.method, (OOShaderUniformType)type);
        isInt = YES;
        break;

    case kOOShaderUniformTypeFloat:
    case kOOShaderUniformTypeDouble:
        fVal = OOCallFloatMethod(object, value.binding.selector, value.binding.method, (OOShaderUniformType)type);
        isFloat = YES;
        break;

    case kOOShaderUniformTypeVector:
        vVal = ((VectorReturnMsgSend)value.binding.method)(object, value.binding.selector);
        if (convertNormalize)
            vVal = vector_normal(vVal);
        expVVal[0] = vVal.x;
        expVVal[1] = vVal.y;
        expVVal[2] = vVal.z;
        expVVal[3] = 1.0f;
        isVector = YES;
        break;

    case kOOShaderUniformTypeHPVector:
        hpvVal = ((HPVectorReturnMsgSend)value.binding.method)(object, value.binding.selector);
        if (convertNormalize)
            hpvVal = HPvector_normal(hpvVal);
        expVVal[0] = (GLfloat)hpvVal.x;
        expVVal[1] = (GLfloat)hpvVal.y;
        expVVal[2] = (GLfloat)hpvVal.z;
        expVVal[3] = 1.0f;
        isVector = YES;
        break;

    case kOOShaderUniformTypeQuaternion:
        qVal = ((QuaternionReturnMsgSend)value.binding.method)(object, value.binding.selector);
        if (convertToMatrix) {
            mVal = OOMatrixForQuaternionRotation(qVal);
            isMatrix = YES;
        } else {
            expVVal[0] = qVal.x;
            expVVal[1] = qVal.y;
            expVVal[2] = qVal.z;
            expVVal[3] = qVal.w;
            isVector = YES;
        }
        break;

    case kOOShaderUniformTypeMatrix:
        mVal = ((MatrixReturnMsgSend)value.binding.method)(object, value.binding.selector);
        isMatrix = YES;
        break;

    case kOOShaderUniformTypePoint:
        pVal = ((PointReturnMsgSend)value.binding.method)(object, value.binding.selector);
        isPoint = YES;
        break;

    case kOOShaderUniformTypeObject:
        objVal = ((ObjectReturnMsgSend)value.binding.method)(object, value.binding.selector);
        // A colour. (The number-object case went with Foundation: no bindable method returns
        // one - the whitelisted object-valued bindings, laserColor and fogUniform, are OOColors.)
        if ([objVal isKindOfClass:[::OOColor class]]) {
            ::OOColor* color = objVal;
            expVVal[0] = [color redComponent];
            expVVal[1] = [color greenComponent];
            expVVal[2] = [color blueComponent];
            expVVal[3] = [color alphaComponent];
            isVector = YES;
        }
        break;
    }

    if (isFloat) {
        if (convertClamp)
            fVal = OOClamp_0_1_f(fVal);
        OOGL(glUniform1fARB(location, fVal));
    } else if (isInt) {
        if (convertClamp)
            iVal = iVal ? 1 : 0;
        OOGL(glUniform1iARB(location, iVal));
    } else if (isPoint) {
        GLfloat v2[2] = { (GLfloat)pVal.x, (GLfloat)pVal.y };
        OOGL(glUniform2fvARB(location, 1, v2));
    } else if (isVector) {
        OOGL(glUniform4fvARB(location, 1, expVVal));
    } else if (isMatrix) {
        GLUniformMatrix(location, mVal);
    }
}

} // namespace cxx

#endif // OO_SHADERS
