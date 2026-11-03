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

#import "OOFunctionAttributes.h"
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOShaderUniformMethodType.h"
#import "ShipEntity.h"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

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
    kMethodTypeVoidObject,
    kMethodTypePListVoid
} MethodType;

static MethodType GetMethodType(id object, SEL selector);

namespace {
OOINLINE bool MethodExpectsParameter(MethodType type) { return type == kMethodTypeVoidObject || type == kMethodTypeObjectObject; }
} // namespace

bool OOJSCallObjCObjectMethod(JSContext* context, id object, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult)
{
    OOJS_PROFILE_ENTER

    std::optional<std::string> selectorString;
    SEL selector = NULL;
    std::optional<std::string> paramString;
    MethodType type;
    bool haveParameter = false,
         error = false;
    oo::PList result; // null for none

    if (argc == 0) {
        cxx_OOJSReportError(context, "%s.callObjC(): no selector specified.", oo_jsClassName.c_str());
        return false;
    }

    if ([object isKindOfClass:[ShipEntity class]]) {
        [PLAYER setScriptTarget:object];
    }

    selectorString = cxx_OOStringFromJSValue(context, argv[0]);

    // Join all parameters together with spaces.
    if (1 < argc && selectorString.has_value() && oo::str::hasSuffix(*selectorString, ":")) {
        haveParameter = true;
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
            error = true;
        } else {
            IMP method = [object methodForSelector:selector];
            switch (type) {
            case kMethodTypeVoidObject:
            case kMethodTypeObjectObject:
                // Called by name with the joined string (ADR-0055 item 5); a void method gives null.
                result = OOCallByName(object, selector, *paramString);
                break;

            case kMethodTypeObjectVoid:
            case kMethodTypePListVoid:
                if (type == kMethodTypePListVoid)
                    result = OOCallByName(object, selector);
                // An object result (a ship, a colour) is its PList::Object node, as oo::PListFrom()
                // made of it; OOCallByName ignores an object result (ADR-0055 Amendment 2).
                else
                    result = oo::PListObject(((id (*)(id, SEL))method)(object, selector));
                if (selectorString.has_value() && oo::str::hasSuffix(*selectorString, "_bool")) {
                    // OOBooleanFromObject(result, false): a string or number reads as oo::plist_get::boolFrom
                    // does (bead oo-2764); any other object answers -boolValue / -intValue if it can.
                    id resultObject = oo::ObjectIn(result);
                    bool boolResult = false;
                    if (result.type() != oo::PList::Type::Object)
                        boolResult = oo::plist_get::boolFrom(!result.isNull() ? &result : nullptr, false);
                    else if ([resultObject respondsToSelector:OOSelectorFromName("boolValue")])
                        boolResult = [(id<OOJSCallScalarValues>)resultObject boolValue];
                    else if ([resultObject respondsToSelector:OOSelectorFromName("intValue")])
                        boolResult = [(id<OOJSCallScalarValues>)resultObject intValue] != 0;
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
                    error = true;
                } else {
                    *outResult = vectorValue;
                }
                break;
            }

            case kMethodTypeQuaternionVoid: {
                Quaternion q = ((QuaternionReturnMsgSend)method)(object, selector);
                JSValue quaternionValue = JSQuaternionWithQuaternion(context, q);
                if (JS_IsException(quaternionValue)) {
                    error = true;
                } else {
                    *outResult = quaternionValue;
                }
                break;
            }

            case kMethodTypeMatrixVoid:
            case kMethodTypePointVoid:
            case kMethodTypeInvalid:
                cxx_OOJSReportError(context, "%s.callObjC(): method %s cannot be called from JavaScript.", oo_jsClassName.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
                error = true;
                break;
            }
            if (!result.isNull()) {
                *outResult = OOJSValueFromPList(context, result); // a Foundation result's PList form, as OOJSValueFromNativeObject gave it (ADR-0051)
            }
        }
    } else {
        cxx_OOJSReportError(context, "%s.callObjC(): %s does not respond to method %s.", oo_jsClassName.c_str(), oo::ShortDescriptionOf(object).c_str(), (selectorString ? selectorString->c_str() : "(null)"));
        error = true;
    }

    return !error;

    OOJS_PROFILE_EXIT
}

namespace {
static bool SameTypeEncoding(char* a, char* b)
{
    bool result = (a != NULL && b != NULL && strcmp(a, b) == 0);
    free(a);
    free(b);
    return result;
}
} // namespace

/*	Whether method has the same signature as the template's method for selector: the same
        return type and the same argument types, as the method signature objects' -isEqual:
        compared them (bead oo-3rb.15; offsets and frame size are not compared).
*/
namespace {
static bool SignatureMatch(Method method, SEL selector)
{
    Method methodTemplate = class_getInstanceMethod([OOJSCallMethodSignatureTemplateClass class], selector);

    if (method == NULL || methodTemplate == NULL)
        return false;

    unsigned argCount = method_getNumberOfArguments(method);
    if (argCount != method_getNumberOfArguments(methodTemplate))
        return false;
    if (!SameTypeEncoding(method_copyReturnType(method), method_copyReturnType(methodTemplate)))
        return false;
    for (unsigned i = 0; i < argCount; i++) {
        if (!SameTypeEncoding(method_copyArgumentType(method, i), method_copyArgumentType(methodTemplate, i)))
            return false;
    }
    return true;
}
} // namespace

static MethodType GetMethodType(id object, SEL selector)
{
    Method method = class_getInstanceMethod(object_getClass(object), selector);

    if (SignatureMatch(method, OOSelectorFromName("voidVoidMethod")))
        return kMethodTypeVoidVoid;
    // The C++ signatures of a selector called by name (ADR-0055 item 5), which OOCallByName calls:
    // the joined string argument, a PList result. oo-qps.72 deleted the id-parameter forms
    // (-voidObjectMethod:, -objectObjectMethod:): OOCallByName no longer passes an object.
    if (SignatureMatch(method, OOSelectorFromName("voidStringMethod:")))
        return kMethodTypeVoidObject;
    if (SignatureMatch(method, OOSelectorFromName("pListStringMethod:")))
        return kMethodTypeObjectObject;
    if (SignatureMatch(method, OOSelectorFromName("pListVoidMethod")))
        return kMethodTypePListVoid;

    MethodType type = (MethodType)OOShaderUniformTypeFromMethod(method);
    if (type != kMethodTypeInvalid)
        return type;

    return kMethodTypeInvalid;
}

#endif
