/*

OOShaderUniformMethodType.h

Type code declarations and OpenStep implementation agnostic method type
matching for uniform bindings.


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

#import "OOOpenGLExtensionManager.h"

#if OO_SHADERS || !defined(NDEBUG)

#import "OOMaths.h"


typedef enum
{
	kOOShaderUniformTypeInvalid,			// Not valid for bindings or constants
	
	kOOShaderUniformTypeChar,				// Binding only
	kOOShaderUniformTypeUnsignedChar,		// Binding only
	kOOShaderUniformTypeShort,				// Binding only
	kOOShaderUniformTypeUnsignedShort,		// Binding only
	kOOShaderUniformTypeInt,				// Binding or constant
	kOOShaderUniformTypeUnsignedInt,		// Binding only
	kOOShaderUniformTypeLong,				// Binding only
	kOOShaderUniformTypeUnsignedLong,		// Binding only
	kOOShaderUniformTypeLongLong,			// Binding only
	kOOShaderUniformTypeUnsignedLongLong,	// Binding only
	kOOShaderUniformTypeFloat,				// Binding or constant
	kOOShaderUniformTypeDouble,				// Binding only
	kOOShaderUniformTypeVector,				// Binding or constant
	kOOShaderUniformTypeQuaternion,			// Binding or constant
	kOOShaderUniformTypeMatrix,				// Binding or constant
	kOOShaderUniformTypePoint,				// Binding only
	kOOShaderUniformTypeObject,				// Binding only
	
	kOOShaderUniformTypeCount				// Not valid for bindings or constants
} OOShaderUniformType;


OOShaderUniformType OOShaderUniformTypeFromMethodSignature(NSMethodSignature *signature);

long long OOCallIntegerMethod(id object, SEL selector, IMP method, OOShaderUniformType type);
double OOCallFloatMethod(id object, SEL selector, IMP method, OOShaderUniformType type);


typedef char (*CharReturnMsgSend)(id, SEL);
typedef unsigned char (*UnsignedCharReturnMsgSend)(id, SEL);
typedef short (*ShortReturnMsgSend)(id, SEL);
typedef unsigned short (*UnsignedShortReturnMsgSend)(id, SEL);
typedef int (*IntReturnMsgSend)(id, SEL);
typedef unsigned int (*UnsignedIntReturnMsgSend)(id, SEL);
typedef long (*LongReturnMsgSend)(id, SEL);
typedef unsigned long (*UnsignedLongReturnMsgSend)(id, SEL);
typedef long long (*LongLongReturnMsgSend)(id, SEL);
typedef unsigned long long (*UnsignedLongLongReturnMsgSend)(id, SEL);
typedef float (*FloatReturnMsgSend)(id, SEL);
typedef double (*DoubleReturnMsgSend)(id, SEL);
typedef Vector (*VectorReturnMsgSend)(id, SEL);
typedef Quaternion (*QuaternionReturnMsgSend)(id, SEL);
typedef OOMatrix (*MatrixReturnMsgSend)(id, SEL);
typedef NSPoint (*PointReturnMsgSend)(id, SEL);
typedef id (*ObjectReturnMsgSend)(id, SEL);

#endif	// OO_SHADERS
