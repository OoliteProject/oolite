/*

OOShaderUniform.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.


This file may also be distributed under the MIT/X11 license:

Copyright (C) 2007 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef NO_SHADERS

#import "OOShaderUniform.h"
#import "OOShaderProgram.h"
#import "OOFunctionAttributes.h"
#import <string.h>
#import "OOMaths.h"
#import "OOOpenGLExtensionManager.h"
#import "OOShaderUniformMethodType.h"


typedef char (*CharReturnMsgSend)(id, SEL);
typedef short (*ShortReturnMsgSend)(id, SEL);
typedef int (*IntReturnMsgSend)(id, SEL);
typedef long (*LongReturnMsgSend)(id, SEL);
typedef float (*FloatReturnMsgSend)(id, SEL);
typedef double (*DoubleReturnMsgSend)(id, SEL);
typedef Vector (*VectorReturnMsgSend)(id, SEL);
typedef Quaternion (*QuaternionReturnMsgSend)(id, SEL);
typedef OOMatrix (*MatrixReturnMsgSend)(id, SEL);
typedef NSPoint (*PointReturnMsgSend)(id, SEL);


OOINLINE BOOL ValidBindingType(OOShaderUniformType type)
{
	return kOOShaderUniformTypeInt <= type && type <= kOOShaderUniformTypeDouble;
}


@interface OOShaderUniform (OOPrivate)

- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram;

- (void)applySimple;
- (void)applyBinding;

@end


@implementation OOShaderUniform

- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram intValue:(GLint)constValue
{
	self = [self initWithName:uniformName shaderProgram:shaderProgram];
	if (self != nil)
	{
		type = kOOShaderUniformTypeInt;
		value.constInt = constValue;
	}
	
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram floatValue:(GLfloat)constValue
{
	self = [self initWithName:uniformName shaderProgram:shaderProgram];
	if (self != nil)
	{
		type = kOOShaderUniformTypeFloat;
		value.constFloat = constValue;
	}
	
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram vectorValue:(Vector)constValue
{
	self = [self initWithName:uniformName shaderProgram:shaderProgram];
	if (self != nil)
	{
		type = kOOShaderUniformTypeVector;
		value.constVector[0] = constValue.x;
		value.constVector[1] = constValue.y;
		value.constVector[2] = constValue.z;
		value.constVector[3] = 1.0f;
	}
	
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram colorValue:(OOColor *)constValue
{
	if (EXPECT_NOT(constValue == nil))
	{
		[self release];
		return nil;
	}
	
	self = [self initWithName:uniformName shaderProgram:shaderProgram];
	if (self != nil)
	{
		type = kOOShaderUniformTypeVector;
		value.constVector[0] = [constValue redComponent];
		value.constVector[1] = [constValue greenComponent];
		value.constVector[2] = [constValue blueComponent];
		value.constVector[3] = [constValue alphaComponent];
	}
	
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram quaternionValue:(Quaternion)constValue asMatrix:(BOOL)asMatrix
{
	self = [self initWithName:uniformName shaderProgram:shaderProgram];
	if (self != nil)
	{
		if (asMatrix)
		{
			type = kOOShaderUniformTypeMatrix;
			value.constMatrix = OOMatrixForQuaternionRotation(constValue);
		}
		else
		{
			type = kOOShaderUniformTypeVector;
			value.constVector[0] = constValue.x;
			value.constVector[1] = constValue.y;
			value.constVector[2] = constValue.z;
			value.constVector[3] = constValue.w;
		}
	}
	
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram matrixValue:(OOMatrix)constValue
{
	self = [self initWithName:uniformName shaderProgram:shaderProgram];
	if (self != nil)
	{
		type = kOOShaderUniformTypeMatrix;
		value.constMatrix = constValue;
	}
	
	return self;
}


- (id)initWithName:(NSString *)uniformName
	 shaderProgram:(OOShaderProgram *)shaderProgram
	 boundToObject:(id<OOWeakReferenceSupport>)target
		  property:(SEL)selector
	convertOptions:(OOUniformConvertOptions)options
{
	BOOL					OK = YES;
	
	if (EXPECT_NOT(uniformName == NULL || shaderProgram == NULL || selector == NULL)) OK = NO;
	
	if (OK)
	{
		self = [super init];
		if (self == nil) OK = NO;
	}
	
	if (OK)
	{
		location = glGetUniformLocationARB([shaderProgram program], [uniformName lossyCString]);
		if (location == -1)
		{
			OK = NO;
			OOLog(@"shader.uniform.bind.failed", @"Could not bind uniform \"%@\" to -[%@ %s] (no uniform of that name could be found).", uniformName, [target class], selector);
		}
	}
	
	// If we're still OK, it's a bindable method.
	if (OK)
	{
		name = [uniformName retain];
		isBinding = YES;
		value.binding.selector = selector;
		
		convertClamp = (options & kOOUniformConvertClamp) != 0;
		convertNormalize = (options & kOOUniformConvertNormalize) != 0;
		convertToMatrix = (options & kOOUniformConvertToMatrix) != 0;
		bindToSuper = (options & kOOUniformBindToSuperTarget) != 0;
		
		if (target != nil)  [self setBindingTarget:target];
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (void)dealloc
{
	[name release];
	if (isBinding)  [value.binding.object release];
	
	[super dealloc];
}


- (NSString *)description
{
	NSString					*valueDesc = nil;
	NSString					*valueType = nil;
	id							object;
	
	if (isBinding)
	{
		object = [value.binding.object weakRefUnderlyingObject];
		if (object != nil)
		{
			valueDesc = [NSString stringWithFormat:@"[<%@ %p> %@]", [object class], value.binding.object, NSStringFromSelector(value.binding.selector)];
		}
		else
		{
			valueDesc = @"0";
		}
	}
	else
	{
		switch (type)
		{
			case kOOShaderUniformTypeInt:
				valueDesc = [NSString stringWithFormat:@"%i", value.constInt];
				break;
			
			case kOOShaderUniformTypeFloat:
				valueDesc = [NSString stringWithFormat:@"%g", value.constFloat];
				break;
		}
	}
	
	switch (type)
	{
		case kOOShaderUniformTypeChar:
		case kOOShaderUniformTypeUnsignedChar:
		case kOOShaderUniformTypeShort:
		case kOOShaderUniformTypeUnsignedShort:
		case kOOShaderUniformTypeInt:
		case kOOShaderUniformTypeUnsignedInt:
		case kOOShaderUniformTypeLong:
		case kOOShaderUniformTypeUnsignedLong:
			valueType = @"int";
			break;
		
		case kOOShaderUniformTypeFloat:
		case kOOShaderUniformTypeDouble:
			valueType = @"float";
			break;
	}
	if (valueType == nil)  valueDesc = @"INVALID";
	if (valueDesc == nil)  valueDesc = @"INVALID";
	
	/*	Examples:
			<OOShaderUniform 0xf00>{1: int tex1 = 1;}
			<OOShaderUniform 0xf00>{3: float laser_heat_level = [<ShipEntity 0xba8> laserHeatLevel];}
	*/
	return [NSString stringWithFormat:@"<%@ %p>{%i: %@ %@ = %@;}", [self class], self, location, valueType, name, valueDesc];
}


- (void)apply
{
	
	if (isBinding)
	{
		if (isActiveBinding)  [self applyBinding];
	}
	else  [self applySimple];
}


- (void)setBindingTarget:(id<OOWeakReferenceSupport>)target
{
	BOOL					OK = YES;
	NSMethodSignature		*signature = nil;
	unsigned				argCount;
	NSString				*methodProblem = nil;
	id<OOWeakReferenceSupport> superCandidate = nil;
	
	if (!isBinding)  return;
	if (EXPECT_NOT([value.binding.object weakRefUnderlyingObject] == [(id)target weakRefUnderlyingObject]))  return;
	
	// Resolve "supertarget" if applicable
	if (bindToSuper)
	{
		for (;;)
		{
			if (![target respondsToSelector:@selector(superShaderBindingTarget)])  break;
			
			superCandidate = [(id)target superShaderBindingTarget];
			if (superCandidate == nil || superCandidate == target)  break;
			target = superCandidate;
		}
	}
	
	[value.binding.object release];
	value.binding.object = [target weakRetain];
	
	if (target == nil)
	{
		isActiveBinding = NO;
		return;
	}
	
	if (OK)
	{
		if (![target respondsToSelector:value.binding.selector])
		{
			methodProblem = @"target does not respond to selector";
			OK = NO;
		}
	}
	
	if (OK)
	{
		value.binding.method = [(id)target methodForSelector:value.binding.selector];
		if (value.binding.method == NULL)
		{
			methodProblem = @"could not retrieve method implementation";
			OK = NO;
		}
	}
	
	if (OK)
	{
		signature = [(id)target methodSignatureForSelector:value.binding.selector];
		if (signature == nil)
		{
			methodProblem = @"could not retrieve method signature";
			OK = NO;
		}
	}
	
	if (OK)
	{
		argCount = [signature numberOfArguments];
		if (argCount != 2)	// "no-arguments" methods actually take two arguments, self and _msg.
		{
			methodProblem = @"only methods which do not require arguments may be bound to";
			OK = NO;
		}
	}
	
	if (OK)
	{
		type = OOShaderUniformTypeFromMethodSignature(signature);
		if (type == kOOShaderUniformTypeInvalid)
		{
			OK = NO;
			methodProblem = [NSString stringWithFormat:@"unsupported type \"%s\"", [signature methodReturnType]];
		}
	}
	
	isActiveBinding = OK;
	if (!OK)  OOLog(@"shader.uniform.bind.failed", @"Shader could not bind uniform \"%@\" to -[%@ %@] (%@).", name, [target class], NSStringFromSelector(value.binding.selector), methodProblem);
}

@end


@implementation OOShaderUniform (OOPrivate)

// Designated initializer.
- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram
{
	BOOL					OK = YES;
	
	if (EXPECT_NOT(uniformName == NULL || shaderProgram == NULL)) OK = NO;
	
	if (OK)
	{
		self = [super init];
		if (self == nil) OK = NO;
	}
	
	if (OK)
	{
		location = glGetUniformLocationARB([shaderProgram program], [uniformName lossyCString]);
		if (location == -1)  OK = NO;
	}
	
	if (OK)
	{
		name = [uniformName copy];
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}

- (void)applySimple
{
	switch (type)
	{
		case kOOShaderUniformTypeInt:
			glUniform1iARB(location, value.constInt);
			break;
		
		case kOOShaderUniformTypeFloat:
			glUniform1fARB(location, value.constFloat);
			break;
		
		case kOOShaderUniformTypeVector:
			glUniform4fvARB(location, 1, value.constVector);
			break;
		
		case kOOShaderUniformTypeMatrix:
			glUniformMatrix4fvARB(location, 1, NO, OOMatrixValuesForOpenGL(value.constMatrix));
	}
}


- (void)applyBinding
{
	
	id							object = nil;
	GLint						iVal;
	GLfloat						fVal;
	Vector						vVal;
	GLfloat						expVVal[4];
	OOMatrix					mVal;
	Quaternion					qVal;
	NSPoint						pVal = {0};
	BOOL						isInt = NO, isFloat = NO, isVector = NO, isMatrix = NO, isPoint = NO;
	id							objVal = nil;
	
	/*	Design note: if the object has been dealloced, or an exception occurs,
		do nothing. Shaders can specify a default value for uniforms, which
		will be used when no setting has been provided by the host program.
		
		I considered clearing value.binding.object if the underlying object is
		gone, but adding code to save a small amount of spacein a case that
		shouldn't occur in normal usage is silly.
	*/
	object = [value.binding.object weakRefUnderlyingObject];
	if (object == nil)  return;
	
	switch (type)
	{
		case kOOShaderUniformTypeChar:
		case kOOShaderUniformTypeUnsignedChar:
			iVal = ((CharReturnMsgSend)value.binding.method)(object, value.binding.selector);
			isInt = YES;
			break;
		
		case kOOShaderUniformTypeShort:
		case kOOShaderUniformTypeUnsignedShort:
			iVal = ((ShortReturnMsgSend)value.binding.method)(object, value.binding.selector);
			isInt = YES;
			break;
		
		case kOOShaderUniformTypeInt:
		case kOOShaderUniformTypeUnsignedInt:
			iVal = ((IntReturnMsgSend)value.binding.method)(object, value.binding.selector);
			isInt = YES;
			break;
		
		case kOOShaderUniformTypeLong:
		case kOOShaderUniformTypeUnsignedLong:
			iVal = ((LongReturnMsgSend)value.binding.method)(object, value.binding.selector);
			isInt = YES;
			break;
		
		case kOOShaderUniformTypeFloat:
			fVal = ((FloatReturnMsgSend)value.binding.method)(object, value.binding.selector);
			isFloat = YES;
			break;
		
		case kOOShaderUniformTypeDouble:
			fVal = ((DoubleReturnMsgSend)value.binding.method)(object, value.binding.selector);
			isFloat = YES;
			break;
		
		case kOOShaderUniformTypeVector:
			vVal = ((VectorReturnMsgSend)value.binding.method)(object, value.binding.selector);
			if (convertNormalize)  vVal = vector_normal(vVal);
			expVVal[0] = vVal.x;
			expVVal[1] = vVal.y;
			expVVal[2] = vVal.z;
			expVVal[3] = 1.0f;
			isVector = YES;
			break;
		
		case kOOShaderUniformTypeQuaternion:
			qVal = ((QuaternionReturnMsgSend)value.binding.method)(object, value.binding.selector);
			if (convertToMatrix)
			{
				mVal = OOMatrixForQuaternionRotation(qVal);
				isMatrix = YES;
			}
			else
			{
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
			objVal = value.binding.method(object, value.binding.selector);
			if ([objVal isKindOfClass:[NSNumber class]])
			{
				fVal = [objVal floatValue];
				isFloat = YES;
			}
			else if ([objVal isKindOfClass:[OOColor class]])
			{
				expVVal[0] = [objVal redComponent];
				expVVal[1] = [objVal greenComponent];
				expVVal[2] = [objVal blueComponent];
				expVVal[3] = [objVal alphaComponent];
				isVector = YES;
			}
			break;
	}
	
	if (isFloat)
	{
		if (convertClamp)  fVal = OOClamp_0_1_f(fVal);
		glUniform1fARB(location, fVal);
	}
	else if (isInt)
	{
		if (convertClamp)  iVal = iVal ? 1 : 0;
		glUniform1iARB(location, iVal);
	}
	else if (isPoint)
	{
		GLfloat v2[2] = { pVal.x, pVal.y };
		glUniform2fvARB(location, 1, v2);
	}
	else if (isVector)
	{
		glUniform4fvARB(location, 1, expVVal);
	}
	else if (isMatrix)
	{
		glUniformMatrix4fvARB(location, 1, NO, OOMatrixValuesForOpenGL(mVal));
	}
}

@end

#endif // NO_SHADERS
