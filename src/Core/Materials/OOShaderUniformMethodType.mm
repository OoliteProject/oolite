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
        template encodings are read from known methods at runtime, through the same
        call. (Bead oo-3rb.15: this used the method signature object's return type,
        which on this runtime is the same return-type encoding.)
*/

#import "OOShaderUniformMethodType.h"

#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)

#import "OOMaths.h"

static BOOL sInited = NO;
static const char* sTemplates[kOOShaderUniformTypeCount];

static void InitTemplates(void);
static const char* CopyTemplateForSelector(SEL selector);

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

@interface OOShaderUniformTypeMethodSignatureTemplateClass : OOObject

- (float)floatMethod;
- (double)doubleMethod;
- (signed char)signedCharMethod;
- (unsigned char)unsignedCharMethod;
- (signed short)signedShortMethod;
- (unsigned short)unsignedShortMethod;
- (signed int)signedIntMethod;
- (unsigned int)unsignedIntMethod;
- (signed long)signedLongMethod;
- (unsigned long)unsignedLongMethod;
- (Vector)vectorMethod;
- (HPVector)hpvectorMethod;
- (Quaternion)quaternionMethod;
- (OOMatrix)matrixMethod;
- (NSPoint)pointMethod;
- (id)idMethod;

@end

static void InitTemplates(void)
{
#define GET_TEMPLATE(enumValue, sel)                                     \
    do {                                                                 \
        sTemplates[enumValue] = CopyTemplateForSelector(@selector(sel)); \
    } while (0)

    GET_TEMPLATE(kOOShaderUniformTypeChar, signedCharMethod);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedChar, unsignedCharMethod);
    GET_TEMPLATE(kOOShaderUniformTypeShort, signedShortMethod);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedShort, unsignedShortMethod);
    GET_TEMPLATE(kOOShaderUniformTypeInt, signedIntMethod);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedInt, unsignedIntMethod);
    GET_TEMPLATE(kOOShaderUniformTypeLong, signedLongMethod);
    GET_TEMPLATE(kOOShaderUniformTypeUnsignedLong, unsignedLongMethod);
    GET_TEMPLATE(kOOShaderUniformTypeFloat, floatMethod);
    GET_TEMPLATE(kOOShaderUniformTypeDouble, doubleMethod);
    GET_TEMPLATE(kOOShaderUniformTypeVector, vectorMethod);
    GET_TEMPLATE(kOOShaderUniformTypeHPVector, hpvectorMethod);
    GET_TEMPLATE(kOOShaderUniformTypeQuaternion, quaternionMethod);
    GET_TEMPLATE(kOOShaderUniformTypeMatrix, matrixMethod);
    GET_TEMPLATE(kOOShaderUniformTypePoint, pointMethod);
    GET_TEMPLATE(kOOShaderUniformTypeObject, idMethod);

    sInited = YES;
}

static const char* CopyTemplateForSelector(SEL selector)
{
    Method method = class_getInstanceMethod([OOShaderUniformTypeMethodSignatureTemplateClass class], selector);

    // method_copyReturnType() returns a malloc()ed copy, kept for the life of the process.
    return (method != NULL) ? method_copyReturnType(method) : NULL;
}

@implementation OOShaderUniformTypeMethodSignatureTemplateClass : OOObject

- (signed char)signedCharMethod
{
    return 0;
}

- (unsigned char)unsignedCharMethod
{
    return 0;
}

- (signed short)signedShortMethod
{
    return 0;
}

- (unsigned short)unsignedShortMethod
{
    return 0;
}

- (signed int)signedIntMethod
{
    return 0;
}

- (unsigned int)unsignedIntMethod
{
    return 0;
}

- (signed long)signedLongMethod
{
    return 0;
}

- (unsigned long)unsignedLongMethod
{
    return 0;
}

- (float)floatMethod
{
    return 0.0f;
}

- (double)doubleMethod
{
    return 0.0;
}

- (Vector)vectorMethod
{
    Vector v = { 0 };
    return v;
}

- (HPVector)hpvectorMethod
{
    HPVector v = { 0 };
    return v;
}

- (Quaternion)quaternionMethod
{
    Quaternion q = { 0 };
    return q;
}

- (OOMatrix)matrixMethod
{
    return kZeroMatrix;
}

- (NSPoint)pointMethod
{
    return NSZeroPoint;
}

- (id)idMethod
{
    return nil;
}

@end

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
