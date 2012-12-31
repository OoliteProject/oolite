/*

OOJSCall.h

Basic JavaScript-to-ObjC bridge implementation.

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#ifndef NDEBUG


#import "OOJSCall.h"
#import "OOJavaScriptEngine.h"

#import "OOFunctionAttributes.h"
#import "ShipEntity.h"
#import "OOCollectionExtractors.h"
#import "OOShaderUniformMethodType.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"


typedef enum
{
	kMethodTypeInvalid				= kOOShaderUniformTypeInvalid,
	
	kMethodTypeCharVoid				= kOOShaderUniformTypeChar,
	kMethodTypeUnsignedCharVoid		= kOOShaderUniformTypeUnsignedChar,
	kMethodTypeShortVoid			= kOOShaderUniformTypeShort,
	kMethodTypeUnsignedShortVoid	= kOOShaderUniformTypeUnsignedShort,
	kMethodTypeIntVoid				= kOOShaderUniformTypeInt,
	kMethodTypeUnsignedIntVoid		= kOOShaderUniformTypeUnsignedInt,
	kMethodTypeLongVoid				= kOOShaderUniformTypeLong,
	kMethodTypeUnsignedLongVoid		= kOOShaderUniformTypeUnsignedLong,
	kMethodTypeFloatVoid			= kOOShaderUniformTypeFloat,
	kMethodTypeDoubleVoid			= kOOShaderUniformTypeDouble,
	kMethodTypeVectorVoid			= kOOShaderUniformTypeVector,
	kMethodTypeQuaternionVoid		= kOOShaderUniformTypeQuaternion,
	kMethodTypeMatrixVoid			= kOOShaderUniformTypeMatrix,
	kMethodTypePointVoid			= kOOShaderUniformTypePoint,
	
	kMethodTypeObjectVoid			= kOOShaderUniformTypeObject,
	kMethodTypeObjectObject,
	kMethodTypeVoidVoid,
	kMethodTypeVoidObject
} MethodType;


OOINLINE BOOL IsIntegerMethodType(MethodType type)
{
	return (kMethodTypeCharVoid <= type && type <= kMethodTypeUnsignedLongVoid);
}


OOINLINE BOOL IsFloatMethodType(MethodType type)
{
	return (kMethodTypeFloatVoid <= type && type <= kMethodTypeDoubleVoid);
}


static MethodType GetMethodType(id object, SEL selector);
OOINLINE BOOL MethodExpectsParameter(MethodType type)	{ return type == kMethodTypeVoidObject || type == kMethodTypeObjectObject; }


BOOL OOJSCallObjCObjectMethod(JSContext *context, id object, NSString *oo_jsClassName, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_PROFILE_ENTER
	
	NSString				*selectorString = nil;
	SEL						selector = NULL;
	NSString				*paramString = nil;
	MethodType				type;
	BOOL					haveParameter = NO,
							error = NO;
	id						result = nil;
	
	if (argc == 0)
	{
		OOJSReportError(context, @"%@.callObjC(): no selector specified.", oo_jsClassName);
		return NO;
	}
	
	if ([object isKindOfClass:[ShipEntity class]])
	{
		[PLAYER setScriptTarget:object];
	}
	
	selectorString = OOStringFromJSValue(context, argv[0]);
	
	// Join all parameters together with spaces.
	if (1 < argc && [selectorString hasSuffix:@":"])
	{
		haveParameter = YES;
		paramString = [NSString concatenationOfStringsFromJavaScriptValues:argv + 1 count:argc - 1 separator:@" " inContext:context];
	}
	
	selector = NSSelectorFromString(selectorString);
	
	if ([object respondsToSelector:selector])
	{
		// Validate signature.
		type = GetMethodType(object, selector);
		
		if (MethodExpectsParameter(type) && !haveParameter)
		{
			OOJSReportError(context, @"%@.callObjC(): method %@ requires a parameter.", oo_jsClassName, selectorString);
			error = YES;
		}
		else
		{
			IMP method = [object methodForSelector:selector];
			switch (type)
			{
				case kMethodTypeVoidObject:
					[object performSelector:selector withObject:paramString];
					break;
					
				case kMethodTypeObjectObject:
					result = [object performSelector:selector withObject:paramString];
					break;
					
				case kMethodTypeObjectVoid:
					result = [object performSelector:selector];
					if ([selectorString hasSuffix:@"_bool"])  result = [NSNumber numberWithBool:OOBooleanFromObject(result, NO)];
					break;
					
				case kMethodTypeVoidVoid:
					[object performSelector:selector];
					break;
					
				case kMethodTypeCharVoid:
				case kMethodTypeUnsignedCharVoid:
				case kMethodTypeShortVoid:
				case kMethodTypeUnsignedShortVoid:
				case kMethodTypeIntVoid:
				case kMethodTypeUnsignedIntVoid:
				case kMethodTypeLongVoid:
					result = [NSNumber numberWithLongLong:OOCallIntegerMethod(object, selector, method, (OOShaderUniformType)type)];
					break;
					
				case kMethodTypeUnsignedLongVoid:
					result = [NSNumber numberWithUnsignedLongLong:OOCallIntegerMethod(object, selector, method, (OOShaderUniformType)type)];
					break;
					
				case kMethodTypeFloatVoid:
				case kMethodTypeDoubleVoid:
					result = [NSNumber numberWithDouble:OOCallFloatMethod(object, selector, method, (OOShaderUniformType)type)];
					break;
					
				case kMethodTypeVectorVoid:
				{
					Vector v = ((VectorReturnMsgSend)method)(object, selector);
					*outResult = OBJECT_TO_JSVAL(JSVectorWithVector(context, v));
					break;
				}
					
				case kMethodTypeQuaternionVoid:
				{
					Quaternion q = ((QuaternionReturnMsgSend)method)(object, selector);
					*outResult = OBJECT_TO_JSVAL(JSQuaternionWithQuaternion(context, q));
					break;
				}
					
				case kMethodTypeMatrixVoid:
				case kMethodTypePointVoid:
				case kMethodTypeInvalid:
					OOJSReportError(context, @"%@.callObjC(): method %@ cannot be called from JavaScript.", oo_jsClassName, selectorString);
					error = YES;
					break;
			}
			if (result != nil)
			{
				*outResult = [result oo_jsValueInContext:context];
			}
		}
	}
	else
	{
		OOJSReportError(context, @"%@.callObjC(): %@ does not respond to method %@.", oo_jsClassName, [object shortDescription], selectorString);
		error = YES;
	}
	
	return !error;
	
	OOJS_PROFILE_EXIT
}


// Template class providing method signature strings for the four signatures we support.
@interface OOJSCallMethodSignatureTemplateClass: NSObject

- (void)voidVoidMethod;
- (void)voidObjectMethod:(id)object;
- (id)objectObjectMethod:(id)object;

@end


static BOOL SignatureMatch(NSMethodSignature *sig, SEL selector)
{
	NSMethodSignature		*template = nil;
	
	template = [OOJSCallMethodSignatureTemplateClass instanceMethodSignatureForSelector:selector];
	return [sig isEqual:template];
}


static MethodType GetMethodType(id object, SEL selector)
{
	NSMethodSignature *sig = [object methodSignatureForSelector:selector];
	
	if (SignatureMatch(sig, @selector(voidVoidMethod)))  return kMethodTypeVoidVoid;
	if (SignatureMatch(sig, @selector(voidObjectMethod:)))  return kMethodTypeVoidObject;
	if (SignatureMatch(sig, @selector(objectObjectMethod:)))  return kMethodTypeObjectObject;
	
	MethodType type = (MethodType)OOShaderUniformTypeFromMethodSignature(sig);
	if (type != kMethodTypeInvalid)  return type;
	
	return kMethodTypeInvalid;
}


@implementation OOJSCallMethodSignatureTemplateClass: NSObject

- (void)voidVoidMethod {}


- (void)voidObjectMethod:(id)object {}


- (id)objectObjectMethod:(id)object { return nil; }

@end

#endif
