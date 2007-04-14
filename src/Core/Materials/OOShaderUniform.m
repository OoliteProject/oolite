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

*/

#ifndef NO_SHADERS

#import "OOShaderUniform.h"
#import "OOShaderProgram.h"
#import "OOFunctionAttributes.h"
#import <string.h>
#import "OOMaths.h"
#import "OOOpenGLExtensionManager.h"


typedef enum
{
	kOOShaderUniformTypeChar,
	kOOShaderUniformTypeShort,
	kOOShaderUniformTypeInt,
	kOOShaderUniformTypeLong,
	kOOShaderUniformTypeFloat,
	kOOShaderUniformTypeDouble
	// Vector and matrix types may be added in future.
} OOShaderUniformType;


typedef char (*CharReturnMsgSend)(id, SEL);
typedef short (*ShortReturnMsgSend)(id, SEL);
typedef int (*IntReturnMsgSend)(id, SEL);
typedef long (*LongReturnMsgSend)(id, SEL);
typedef float (*FloatReturnMsgSend)(id, SEL);
typedef double (*DoubleReturnMsgSend)(id, SEL);


OOINLINE BOOL ValidBindingType(OOShaderUniformType type)
{
	return kOOShaderUniformTypeInt <= type && type <= kOOShaderUniformTypeDouble;
}


@interface OOShaderUniform (OOPrivate)

- (void)applySimple;
- (void)applyBinding;

@end


@implementation OOShaderUniform

- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram intValue:(int)constValue
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
		name = [uniformName retain];
		type = kOOShaderUniformTypeInt;
		value.constInt = constValue;
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram floatValue:(int)constValue
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
		name = [uniformName retain];
		type = kOOShaderUniformTypeFloat;
		value.constFloat = constValue;
	}
	
	if (!OK)
	{
		[self release];
		self = nil;
	}
	return self;
}


- (id)initWithName:(NSString *)uniformName shaderProgram:(OOShaderProgram *)shaderProgram boundToObject:(id<OOWeakReferenceSupport>)source property:(SEL)selector clamped:(BOOL)clamped
{
	BOOL					OK = YES;
	NSMethodSignature		*sig = nil;
	unsigned				argCount;
	NSString				*methodProblem = nil;
	const char				*typeCode = nil;
	
	if (EXPECT_NOT(uniformName == NULL || shaderProgram == NULL || source == nil || selector == NULL)) OK = NO;
	
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
	
	// Check to see if it's a valid method.
	if (OK)
	{
		if (![source respondsToSelector:selector])
		{
			methodProblem = @"target does not respond to selector";
			OK = NO;
		}
	}
	
	if (OK)
	{
		value.binding.method = [(id)source methodForSelector:selector];
		if (value.binding.method == NULL)
		{
			methodProblem = @"could not retrieve method implementation";
			OK = NO;
		}
	}
	
	if (OK)
	{
		sig = [(id)source methodSignatureForSelector:selector];
		if (sig == nil)
		{
			methodProblem = @"could not retrieve method signature";
			OK = NO;
		}
	}
	
	if (OK)
	{
		argCount = [sig numberOfArguments];
		if (argCount != 2)	// "no-arguments" methods actually take two arguments, self and _msg.
		{
			methodProblem = @"only methods which do not require arguments may be bound to";
			OK = NO;
		}
	}
	
	if (OK)
	{
		typeCode = [sig methodReturnType];
		if (0 == strcmp("f", typeCode))  type = kOOShaderUniformTypeFloat;
		else if (0 == strcmp("d", typeCode))  type = kOOShaderUniformTypeDouble;
		else if (0 == strcmp("c", typeCode) || 0 == strcmp("C", typeCode))  type = kOOShaderUniformTypeChar;	// Signed or unsigned
		else if (0 == strcmp("s", typeCode) || 0 == strcmp("S", typeCode))  type = kOOShaderUniformTypeShort;
		else if (0 == strcmp("i", typeCode) || 0 == strcmp("I", typeCode))  type = kOOShaderUniformTypeInt;
		else if (0 == strcmp("l", typeCode) || 0 == strcmp("L", typeCode))  type = kOOShaderUniformTypeLong;
		else
		{
			methodProblem = [NSString stringWithFormat:@"unsupported type \"%s\"", typeCode];
		}
	}
	
	// If we're still OK, it's a bindable method.
	if (OK)
	{
		name = [uniformName retain];
		isBinding = YES;
		value.binding.object = [source weakRetain];
		value.binding.selector = selector;
		value.binding.clamped = clamped;
	}
	
	if (!OK)
	{
		if (methodProblem != nil)
		{
			OOLog(@"shader.uniform.bind.failed", @"***** Shader error: could not bind uniform \"%@\" to -[%@ %s] (%@).", uniformName, [source class], selector, methodProblem);
		}
		
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
		case kOOShaderUniformTypeShort:
		case kOOShaderUniformTypeInt:
		case kOOShaderUniformTypeLong:
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
	
	if (isBinding)  [self applyBinding];
	else  [self applySimple];
}

@end


@implementation OOShaderUniform (OOPrivate)

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
	}
}


- (void)applyBinding
{
	
	id							object = nil;
	int							iVal;
	float						fVal;
	BOOL						fp = NO;
	
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
			iVal = ((CharReturnMsgSend)value.binding.method)(object, value.binding.selector);
			break;
		
		case kOOShaderUniformTypeShort:
			iVal = ((ShortReturnMsgSend)value.binding.method)(object, value.binding.selector);
			break;
		
		case kOOShaderUniformTypeInt:
			iVal = ((IntReturnMsgSend)value.binding.method)(object, value.binding.selector);
			break;
		
		case kOOShaderUniformTypeLong:
			iVal = ((LongReturnMsgSend)value.binding.method)(object, value.binding.selector);
			break;
		
		case kOOShaderUniformTypeFloat:
			fVal = ((FloatReturnMsgSend)value.binding.method)(object, value.binding.selector);
			fp = YES;
			break;
		
		case kOOShaderUniformTypeDouble:
			fVal = ((DoubleReturnMsgSend)value.binding.method)(object, value.binding.selector);
			fp = YES;
			break;
	}
	
	if (!fp)
	{
		if (EXPECT_NOT(value.binding.clamped))  iVal = iVal ? 1 : 0;
		glUniform1iARB(location, iVal);
	}
	else
	{
		if (EXPECT_NOT(value.binding.clamped))  fVal = OOClamp_0_1_f(fVal);
		glUniform1fARB(location, fVal);
	}
}

@end

#endif // NO_SHADERS
