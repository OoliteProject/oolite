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

#ifdef OO_DEBUG_MONITOR_ENABLED

#import "OOJSCall.h"
#import "OOCallByName.h"
#import "OOJavaScriptEngine.h"
#import "OOObjCPList.h"
#include "oofnd/objc/OORuntime.h"

#import "OOFoundationBridge.h"
#import "OOFunctionAttributes.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOShaderUniformMethodType.h"
#import "ShipEntity.h"
#include "oofnd/PListGet.hpp"

typedef enum {
    kMethodTypeInvalid = kOOShaderUniformTypeInvalid,

    kMethodTypeCharVoid = kOOShaderUniformTypeChar,
    kMethodTypeUnsignedCharVoid = kOOShaderUniformTypeUnsignedChar,
    kMethodTypeShortVoid = kOOShaderUniformTypeShort,
    kMethodTypeUnsignedShortVoid = kOOShaderUniformTypeUnsignedShort,
    kMethodTypeIntVoid = kOOShaderUniformTypeInt,
    kMethodTypeUnsignedIntVoid = kOOShaderUniformTypeUnsignedInt,
    kMethodTypeLongVoid = kOOShaderUniformTypeLong,
    kMethodTypeUnsignedLongVoid = kOOShaderUniformTypeUnsignedLong,
    kMethodTypeFloatVoid = kOOShaderUniformTypeFloat,
    kMethodTypeDoubleVoid = kOOShaderUniformTypeDouble,
    kMethodTypeVectorVoid = kOOShaderUniformTypeVector,
    kMethodTypeQuaternionVoid = kOOShaderUniformTypeQuaternion,
    kMethodTypeMatrixVoid = kOOShaderUniformTypeMatrix,
    kMethodTypePointVoid = kOOShaderUniformTypePoint,

    kMethodTypeObjectVoid = kOOShaderUniformTypeObject,
    kMethodTypeObjectObject,
    kMethodTypeVoidVoid,
    kMethodTypeVoidObject
} MethodType;

static MethodType GetMethodType(id object, SEL selector);
OOINLINE BOOL MethodExpectsParameter(MethodType type) { return type == kMethodTypeVoidObject || type == kMethodTypeObjectObject; }

BOOL OOJSCallObjCObjectMethod(JSContext* context, id object, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult)
{
    OOJS_PROFILE_ENTER

    std::optional<std::string> selectorString;
    SEL selector = NULL;
    std::optional<std::string> paramString;
    MethodType type;
    BOOL haveParameter = NO,
         error = NO;
    oo::PList result; // null for none

    if (argc == 0) {
        cxx_OOJSReportError(context, "%s.callObjC(): no selector specified.", oo_jsClassName.c_str());
        return NO;
    }

    if ([object isKindOfClass:[ShipEntity class]]) {
        [PLAYER setScriptTarget:object];
    }

    selectorString = cxx_OOStringFromJSValue(context, argv[0]);

    // Join all parameters together with spaces.
    if (1 < argc && selectorString.has_value() && oo::str::hasSuffix(*selectorString, ":")) {
        haveParameter = YES;
        // As +concatenationOfStringsFromJavaScriptValues:count:separator:@" " joined them.
        std::string joined;
        for (int i = 1; i < argc; i++) {
            if (i > 1)
                joined += " ";
            joined += cxx_OOStringFromJSValueEvenIfNull(context, argv[i]).value_or(std::string());
        }
        paramString = joined;
    }

    selector = OOSelectorFromName(selectorString.has_value() ? selectorString->c_str() : NULL);

    if ([object respondsToSelector:selector]) {
        // Validate signature.
        type = GetMethodType(object, selector);

        if (MethodExpectsParameter(type) && !haveParameter) {
            cxx_OOJSReportError(context, "%s.callObjC(): method %s requires a parameter.", oo_jsClassName.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
            error = YES;
        } else {
            IMP method = [object methodForSelector:selector];
            switch (type) {
            case kMethodTypeVoidObject:
            case kMethodTypeObjectObject:
                // Called by name with the joined string (ADR-0055 item 5); a void method gives null.
                result = OOCallByName(object, selector, *paramString);
                break;

            case kMethodTypeObjectVoid:
                result = OOCallByName(object, selector);
                if (selectorString.has_value() && oo::str::hasSuffix(*selectorString, "_bool")) {
                    // OOBooleanFromObject(result, NO): a string or number reads as oo::plist_get::boolFrom
                    // does (bead oo-2764); any other object answers -boolValue / -intValue if it can.
                    id resultObject = oo::ObjectIn(result);
                    bool boolResult = NO;
                    if (result.type() != oo::PList::Type::Object)
                        boolResult = oo::plist_get::boolFrom(!result.isNull() ? &result : nullptr, NO);
                    else if ([resultObject respondsToSelector:@selector(boolValue)])
                        boolResult = [resultObject boolValue];
                    else if ([resultObject respondsToSelector:@selector(intValue)])
                        boolResult = [resultObject intValue] != 0;
                    result = oo::PList(boolResult);
                }
                break;

            case kMethodTypeVoidVoid:
                OOCallByName(object, selector);
                break;

            case kMethodTypeCharVoid:
            case kMethodTypeUnsignedCharVoid:
            case kMethodTypeShortVoid:
            case kMethodTypeUnsignedShortVoid:
            case kMethodTypeIntVoid:
            case kMethodTypeUnsignedIntVoid:
            case kMethodTypeLongVoid:
                result = oo::PList::signedInteger(OOCallIntegerMethod(object, selector, method, (OOShaderUniformType)type));
                break;

            case kMethodTypeUnsignedLongVoid:
                result = oo::PList::unsignedInteger(OOCallIntegerMethod(object, selector, method, (OOShaderUniformType)type));
                break;

            case kMethodTypeFloatVoid:
            case kMethodTypeDoubleVoid:
                result = oo::PList(static_cast<double>(OOCallFloatMethod(object, selector, method, (OOShaderUniformType)type)));
                break;

            case kMethodTypeVectorVoid: {
                Vector v = ((VectorReturnMsgSend)method)(object, selector);
                JSValue vectorValue = JSVectorWithVector(context, v);
                if (JS_IsException(vectorValue)) {
                    error = YES;
                } else {
                    *outResult = vectorValue;
                }
                break;
            }

            case kMethodTypeQuaternionVoid: {
                Quaternion q = ((QuaternionReturnMsgSend)method)(object, selector);
                JSValue quaternionValue = JSQuaternionWithQuaternion(context, q);
                if (JS_IsException(quaternionValue)) {
                    error = YES;
                } else {
                    *outResult = quaternionValue;
                }
                break;
            }

            case kMethodTypeMatrixVoid:
            case kMethodTypePointVoid:
            case kMethodTypeInvalid:
                cxx_OOJSReportError(context, "%s.callObjC(): method %s cannot be called from JavaScript.", oo_jsClassName.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
                error = YES;
                break;
            }
            if (!result.isNull()) {
                *outResult = OOJSValueFromPList(context, result); // a Foundation result's PList form, as OOJSValueFromNativeObject gave it (ADR-0051)
            }
        }
    } else {
        cxx_OOJSReportError(context, "%s.callObjC(): %s does not respond to method %s.", oo_jsClassName.c_str(), oo::ShortDescriptionOf(object).c_str(), (selectorString ? selectorString->c_str() : "(null)"));
        error = YES;
    }

    return !error;

    OOJS_PROFILE_EXIT
}

// Template class providing method type encodings for the three signatures matched here.
@interface OOJSCallMethodSignatureTemplateClass : OOObject

- (void)voidVoidMethod;
- (void)voidObjectMethod:(id)object;
- (id)objectObjectMethod:(id)object;

@end

static BOOL SameTypeEncoding(char* a, char* b)
{
    BOOL result = (a != NULL && b != NULL && strcmp(a, b) == 0);
    free(a);
    free(b);
    return result;
}

/*	Whether method has the same signature as the template's method for selector: the same
        return type and the same argument types, as the method signature objects' -isEqual:
        compared them (bead oo-3rb.15; offsets and frame size are not compared).
*/
static BOOL SignatureMatch(Method method, SEL selector)
{
    Method methodTemplate = class_getInstanceMethod([OOJSCallMethodSignatureTemplateClass class], selector);

    if (method == NULL || methodTemplate == NULL)
        return NO;

    unsigned argCount = method_getNumberOfArguments(method);
    if (argCount != method_getNumberOfArguments(methodTemplate))
        return NO;
    if (!SameTypeEncoding(method_copyReturnType(method), method_copyReturnType(methodTemplate)))
        return NO;
    for (unsigned i = 0; i < argCount; i++) {
        if (!SameTypeEncoding(method_copyArgumentType(method, i), method_copyArgumentType(methodTemplate, i)))
            return NO;
    }
    return YES;
}

static MethodType GetMethodType(id object, SEL selector)
{
    Method method = class_getInstanceMethod(object_getClass(object), selector);

    if (SignatureMatch(method, @selector(voidVoidMethod)))
        return kMethodTypeVoidVoid;
    if (SignatureMatch(method, @selector(voidObjectMethod:)))
        return kMethodTypeVoidObject;
    if (SignatureMatch(method, @selector(objectObjectMethod:)))
        return kMethodTypeObjectObject;

    MethodType type = (MethodType)OOShaderUniformTypeFromMethod(method);
    if (type != kMethodTypeInvalid)
        return type;

    return kMethodTypeInvalid;
}

@implementation OOJSCallMethodSignatureTemplateClass : OOObject

- (void)voidVoidMethod
{
}

- (void)voidObjectMethod:(id)object
{
}

- (id)objectObjectMethod:(id)object
{
    return nil;
}

@end

#endif
