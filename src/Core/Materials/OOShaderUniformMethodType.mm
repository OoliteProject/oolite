/*

OOShaderUniformMethodType.m


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

/*
        For shader uniform binding to work, it is necessary to be able to tell the
        return type of a method. This is done by comparing the runtime's return
        type encoding of the method (method_copyReturnType()) to those of methods
        in a template class, one method for each supported return type.

        The encoding is platform-defined, so to stay implementation-agnostic the
        template encodings are the compiler's own, @encode() of each type: what the
        runtime records for a method returning that type. (Bead oo-3rb.15: this used
        the method signature object's return type, which on this runtime is the same
        return-type encoding. Bead oo-41vj: they were read, through the same call,
        from methods of an Objective-C template class that existed only for this;
        proposed ADR-0056 amendment oo-41vj.)
*/

#import "OOShaderUniformMethodType.h"

#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)

#import "OOMaths.h"

static BOOL sInited = NO;
static const char* sTemplates[kOOShaderUniformTypeCount];

static void InitTemplates(void);

OOShaderUniformType OOShaderUniformTypeFromMethod(Method method)
{
    unsigned i;
    char* typeCode = NULL;
    OOShaderUniformType result = kOOShaderUniformTypeInvalid;

    if (EXPECT_NOT(sInited == NO))
        InitTemplates();

    if (EXPECT_NOT(method == NULL))
        return kOOShaderUniformTypeInvalid;
    typeCode = method_copyReturnType(method);
    if (EXPECT_NOT(typeCode == NULL))
        return kOOShaderUniformTypeInvalid;

    for (i = kOOShaderUniformTypeInvalid + 1; i != kOOShaderUniformTypeCount; ++i) {
        if (sTemplates[i] != NULL && strcmp(sTemplates[i], typeCode) == 0) {
            result = (OOShaderUniformType)i;
            break;
        }
    }

    free(typeCode);
    return result;
}

static void InitTemplates(void)
{
// Each was the return type of a template method (-signedCharMethod and so on).
#define GET_TEMPLATE(enumValue, type)          \
    do {                                       \
        sTemplates[enumValue] = @encode(type); \
    } while (0)

    GET_TEMPLATE(kOOShaderUniformTypeChar, signed char);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedChar, unsigned char);
    GET_TEMPLATE(kOOShaderUniformTypeShort, signed short);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedShort, unsigned short);
    GET_TEMPLATE(kOOShaderUniformTypeInt, signed int);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedInt, unsigned int);
    GET_TEMPLATE(kOOShaderUniformTypeLong, signed long);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedLong, unsigned long);
    GET_TEMPLATE(kOOShaderUniformTypeFloat, float);
    GET_TEMPLATE(kOOShaderUniformTypeDouble, double);
    GET_TEMPLATE(kOOShaderUniformTypeVector, Vector);
    GET_TEMPLATE(kOOShaderUniformTypeHPVector, HPVector);
    GET_TEMPLATE(kOOShaderUniformTypeQuaternion, Quaternion);
    GET_TEMPLATE(kOOShaderUniformTypeMatrix, OOMatrix);
    GET_TEMPLATE(kOOShaderUniformTypePoint, NSPoint);
    GET_TEMPLATE(kOOShaderUniformTypeObject, id);

    sInited = YES;
}

long long OOCallIntegerMethod(id object, SEL selector, IMP method, OOShaderUniformType type)
{
    switch (type) {
    case kOOShaderUniformTypeChar:
        return ((CharReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeUnsignedChar:
        return ((UnsignedCharReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeShort:
        return ((ShortReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeUnsignedShort:
        return ((UnsignedShortReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeInt:
        return ((IntReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeUnsignedInt:
        return ((UnsignedIntReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeLong:
        return ((LongReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeUnsignedLong:
        return ((UnsignedLongReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeLongLong:
        return ((LongLongReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeUnsignedLongLong:
        return ((UnsignedLongLongReturnMsgSend)method)(object, selector);

    default:
        return 0;
    }
}

double OOCallFloatMethod(id object, SEL selector, IMP method, OOShaderUniformType type)
{
    switch (type) {
    case kOOShaderUniformTypeFloat:
        return ((FloatReturnMsgSend)method)(object, selector);

    case kOOShaderUniformTypeDouble:
        return ((DoubleReturnMsgSend)method)(object, selector);

    default:
        return 0;
    }
}

#endif // OO_SHADERS
