/*

OOShaderUniformMethodType.h

Type code declarations and OpenStep implementation agnostic method type
matching for uniform bindings.


Copyright (C) 2007 Jens Ayton

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

#if OO_SHADERS


typedef enum
{
	kOOShaderUniformTypeInvalid,		// Not valid for bindings or constants
	
	kOOShaderUniformTypeChar,			// Binding only
	kOOShaderUniformTypeUnsignedChar,	// Binding only
	kOOShaderUniformTypeShort,			// Binding only
	kOOShaderUniformTypeUnsignedShort,	// Binding only
	kOOShaderUniformTypeInt,			// Binding or constant
	kOOShaderUniformTypeUnsignedInt,	// Binding only
	kOOShaderUniformTypeLong,			// Binding only
	kOOShaderUniformTypeUnsignedLong,	// Binding only
	kOOShaderUniformTypeFloat,			// Binding or constant
	kOOShaderUniformTypeDouble,			// Binding only
	kOOShaderUniformTypeVector,			// Binding or constant
	kOOShaderUniformTypeQuaternion,		// Binding or constant
	kOOShaderUniformTypeMatrix,			// Binding or constant
	kOOShaderUniformTypePoint,			// Binding only
	kOOShaderUniformTypeObject,			// Binding only
	
	kOOShaderUniformTypeCount			// Not valid for bindings or constants
} OOShaderUniformType;


OOShaderUniformType OOShaderUniformTypeFromMethodSignature(NSMethodSignature *signature);

#endif	// OO_SHADERS
