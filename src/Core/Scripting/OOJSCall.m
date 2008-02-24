/*

OOJSCall.h

Basic JavaScript-to-ObjC bridge implementation.

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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

#import "OOJSCall.h"

#import "OOFunctionAttributes.h"
#import "ShipEntity.h"
#import "OOCollectionExtractors.h"


typedef enum
{
	kMethodTypeVoidVoid,
	kMethodTypeObjectVoid,
	kMethodTypeVoidObject,
	kMethodTypeObjectObject,
	kMethodTypeInvalid
} MethodType;


static MethodType GetMethodType(id object, SEL selector);
OOINLINE BOOL MethodExpectsParameter(MethodType type)	{ return type == kMethodTypeVoidObject || type == kMethodTypeObjectObject; }
OOINLINE BOOL MethodReturnsObject(MethodType type)		{ return type == kMethodTypeObjectVoid || type == kMethodTypeObjectObject; }


BOOL OOJSCallObjCObjectMethod(JSContext *context, id object, NSString *jsClassName, uintN argc, jsval *argv, jsval *outResult)
{
	NSString				*selectorString = nil;
	SEL						selector = NULL;
	NSString				*paramString = nil;
	MethodType				type;
	BOOL					haveParameter = NO,
							success = NO;
	id						result = nil;
	
	if ([object isKindOfClass:[ShipEntity class]])
	{
		[[PlayerEntity sharedPlayer] setScriptTarget:object];
	}
	
	selectorString = [NSString stringWithJavaScriptValue:argv[0] inContext:context];
	
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
		
		if (type == kMethodTypeInvalid)
		{
			OOReportJavaScriptError(context, @"%@.call(): method %@ cannot be called from JavaScript.", jsClassName, selectorString);
		}
		else if (MethodExpectsParameter(type) && !haveParameter)
		{
			OOReportJavaScriptError(context, @"%@.call(): method %@ requires a parameter.", jsClassName, selectorString);
		}
		else
		{
			// Method is acceptable.
			if (haveParameter)
			{
				OOLog(@"script.trace.javaScript.call", @"%@.call(%@, \"%@\")", jsClassName, selectorString, paramString);
				OOLogIndentIf(@"script.trace.javaScript.call");
				
				result = [object performSelector:selector withObject:paramString];
				
				OOLogOutdentIf(@"script.trace.javaScript.call");
			}
			else
			{
				OOLog(@"script.trace.javaScript.call", @"%@.call(%@)", jsClassName, selectorString);
				OOLogIndentIf(@"script.trace.javaScript.call");
				
				result = [object performSelector:selector];
				
				OOLogOutdentIf(@"script.trace.javaScript.call");
			}
			success = YES;
			
			if (MethodReturnsObject(type) && outResult != NULL)
			{
				if ([selectorString hasSuffix:@"_bool"])  result = [NSNumber numberWithBool:OOBooleanFromObject(result, NO)];
				*outResult = [result javaScriptValueInContext:context];
			}
		}
	}
	else
	{
		OOReportJavaScriptError(context, @"%@.call(): %@ does not respond to method %@.", jsClassName, object, selectorString);
	}
	
	return success;
}


// Template class providing method signature strings for the four signatures we support.
@interface OOJSCallMethodSignatureTemplateClass: NSObject

- (void)voidVoidMethod;
- (id)objectVoidMethod;
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
	if (SignatureMatch(sig, @selector(objectVoidMethod)))  return kMethodTypeObjectVoid;
	if (SignatureMatch(sig, @selector(voidObjectMethod:)))  return kMethodTypeVoidObject;
	if (SignatureMatch(sig, @selector(objectObjectMethod:)))  return kMethodTypeObjectObject;
	
	return kMethodTypeInvalid;
}


@implementation OOJSCallMethodSignatureTemplateClass: NSObject

- (void)voidVoidMethod
{
}


- (id)objectVoidMethod
{
	return nil;
}


- (void)voidObjectMethod:(id)object
{
}


- (id)objectObjectMethod:(id)object
{
	return nil;
}

@end
