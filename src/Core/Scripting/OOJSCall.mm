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
#import "OOColor.h" // a colour result (kMethodTypeColorVoid)
#import "OOJavaScriptEngine.h"
#import "OOObjCPList.h"
#include "oofnd/objc/OORuntime.h"

#import "OOCallByName.h"
#import "OOEntityCalledByName.h" // the entities' by-name methods, on the C++ entity
#import "OOFunctionAttributes.h"
#import "OOJSCallEntityMethods.h" // callObjC()'s names for an entity (generated)
#import "OOJSQuaternion.h"
#import "OOJSVector.h"
#import "OOShaderUniformMethodType.h"
#import "PlayerEntity.h" // the script target (a C++ member)
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
    kMethodTypeColorVoid = kOOShaderUniformTypeColor, // a colour (OOColor *)

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

namespace {
// The table's row for name; null for a name it does not list.
const OOJSCallEntityMethodRow* EntityMethodNamed(const std::optional<std::string>& name)
{
    if (!name.has_value())
        return nullptr;
    for (const OOJSCallEntityMethodRow& row : kOOJSCallEntityMethods) {
        if (*name == row.name)
            return &row;
    }
    return nullptr;
}

// The row's signature, as GetMethodType() classified the method it was generated from.
MethodType MethodTypeOfRow(const OOJSCallEntityMethodRow& row)
{
    switch (row.form) {
    case OOJSCallEntityMethodForm::VoidVoid:
        return kMethodTypeVoidVoid;
    case OOJSCallEntityMethodForm::VoidString:
        return kMethodTypeVoidObject;
    case OOJSCallEntityMethodForm::PListString:
        return kMethodTypeObjectObject;
    case OOJSCallEntityMethodForm::PListVoid:
        return kMethodTypePListVoid;
    case OOJSCallEntityMethodForm::Typed:
        return (MethodType)OOShaderUniformTypeFromEncoding(row.encoding);
    }
    return kMethodTypeInvalid;
}

// -boolValue, else -intValue, of a "_bool" method's object result, if it answers one (what the
// scalar-value protocol of the deleted bridge declared); false if it answers neither.
bool ScalarBoolValue(id object)
{
    SEL boolValue = OOSelectorFromName("boolValue"), intValue = OOSelectorFromName("intValue");
    if ([object respondsToSelector:boolValue])
        return ((BOOL (*)(id, SEL))(void (*)(void))[object methodForSelector:boolValue])(object, boolValue);
    if ([object respondsToSelector:intValue])
        return ((int (*)(id, SEL))(void (*)(void))[object methodForSelector:intValue])(object, intValue) != 0;
    return false;
}

/*	The call: of any object by its method's signature (OOJSCallObjCObjectMethod), or of an entity
        by the entity table (entityTable): a name the table does not list does not respond, and a listed
        one is called with the table's signature. An entity's by-name methods (the generated table
        OOEntityCalledByNameTable.h) are asked of and called on its C++ part, as the facade answered
        and called them, and so are the facade's own methods the table lists (its rows in
        OOEntityCalledByName.mm): an entity's call has no object (object is nil). Its "does not
        respond" error still names the entity's object, whose address the text holds.
*/
bool CallMethod(JSContext* context, id object, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult, bool entityTable, Entity* entity)
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

    ShipEntity* ship = (entity != nullptr) ? oo::ToShip(entity) : nullptr; // the C++ entity's; no other object is a ship
    if (ship != nullptr) {
        if (PLAYER != nullptr)
            PLAYER->PlayerEntity::setScriptTarget(ship); // qualified: the final overrider, so the binding test stands in for it
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

    if (const OOJSCallEntityMethodRow* row = entityTable ? EntityMethodNamed(selectorString) : nullptr; (!entityTable || row != nullptr) && (entity != nullptr ? oo::EntityRespondsToName(entity, *selectorString) : [object respondsToSelector:selector])) {
        // Validate signature: the table's for an entity, else the method's.
        type = (row != nullptr) ? MethodTypeOfRow(*row) : GetMethodType(object, selector);

        if (MethodExpectsParameter(type) && !haveParameter) {
            cxx_OOJSReportError(context, "%s.callObjC(): method %s requires a parameter.", oo_jsClassName.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
            error = true;
        } else {
            IMP method = (entity == nullptr) ? [object methodForSelector:selector] : nullptr; // an object's call only
            // An entity's method with a numeric, vector, quaternion, colour or object result is called
            // on its C++ part, its result read as the method's was.
            OOEntityByNameValue typed;
            bool byName = false;
            switch (type) {
            case kMethodTypeCharVoid:
            case kMethodTypeUnsignedCharVoid:
            case kMethodTypeShortVoid:
            case kMethodTypeUnsignedShortVoid:
            case kMethodTypeIntVoid:
            case kMethodTypeUnsignedIntVoid:
            case kMethodTypeLongVoid:
            case kMethodTypeUnsignedLongVoid:
            case kMethodTypeFloatVoid:
            case kMethodTypeDoubleVoid:
            case kMethodTypeVectorVoid:
            case kMethodTypeQuaternionVoid:
            case kMethodTypeColorVoid:
            case kMethodTypeObjectVoid:
                // An entity's typed call: the table holds every name callObjC() lists for an entity;
                // one it cannot call leaves the zero values.
                if (entity != nullptr)
                    oo::CallEntityByNameTyped(entity, *selectorString, typed);
                byName = (entity != nullptr);
                break;
            default:
                break;
            }
            switch (type) {
            case kMethodTypeVoidObject:
            case kMethodTypeObjectObject:
                // Called by name with the joined string (ADR-0055 item 5); a void method gives null.
                result = (entity != nullptr) ? oo::CallEntityByName(entity, *selectorString, *paramString) : OOCallByName(object, selector, *paramString);
                break;

            case kMethodTypeColorVoid:
                // A colour result is its PList::Object node, as the colour's facade's was.
                result = OOColorObjectNode(byName ? typed.color : ((ColorReturnMsgSend)(void (*)(void))method)(object, selector));
                if (selectorString.has_value() && oo::str::hasSuffix(*selectorString, "_bool"))
                    result = oo::PList(false); // a colour answered neither -boolValue nor -intValue
                break;

            case kMethodTypeObjectVoid:
            case kMethodTypePListVoid:
                if (type == kMethodTypePListVoid)
                    result = (entity != nullptr) ? oo::CallEntityByName(entity, *selectorString) : OOCallByName(object, selector);
                // An object result (a ship, a colour) is its PList::Object node, as oo::PListFrom()
                // made of it; OOCallByName ignores an object result (ADR-0055 Amendment 2).
                // An entity result is its entity's Object node: the same object, class name,
                // description and JS value as the object's node.
                else if (byName && typed.entity != nullptr)
                    result = oo::EntityObjectNode(typed.entity);
                else
                    result = oo::PListObject(byName ? typed.object : ((id (*)(id, SEL))method)(object, selector));
                if (selectorString.has_value() && oo::str::hasSuffix(*selectorString, "_bool")) {
                    // OOBooleanFromObject(result, false): a string or number reads as oo::plist_get::boolFrom
                    // does (bead oo-2764); any other object answers -boolValue / -intValue if it can.
                    id resultObject = oo::ObjectIn(result);
                    bool boolResult = false;
                    if (result.type() != oo::PList::Type::Object)
                        boolResult = oo::plist_get::boolFrom(!result.isNull() ? &result : nullptr, false);
                    else
                        boolResult = ScalarBoolValue(resultObject);
                    result = oo::PList(boolResult);
                }
                break;

            case kMethodTypeVoidVoid:
                if (entity != nullptr)
                    oo::CallEntityByName(entity, *selectorString);
                else
                    OOCallByName(object, selector);
                break;

            case kMethodTypeCharVoid:
            case kMethodTypeUnsignedCharVoid:
            case kMethodTypeShortVoid:
            case kMethodTypeUnsignedShortVoid:
            case kMethodTypeIntVoid:
            case kMethodTypeUnsignedIntVoid:
            case kMethodTypeLongVoid:
                result = oo::PList::signedInteger(byName ? typed.integer : OOCallIntegerMethod(object, selector, method, (OOShaderUniformType)type));
                break;

            case kMethodTypeUnsignedLongVoid:
                result = oo::PList::unsignedInteger(byName ? typed.integer : OOCallIntegerMethod(object, selector, method, (OOShaderUniformType)type));
                break;

            case kMethodTypeFloatVoid:
            case kMethodTypeDoubleVoid:
                result = oo::PList(static_cast<double>(byName ? typed.real : OOCallFloatMethod(object, selector, method, (OOShaderUniformType)type)));
                break;

            case kMethodTypeVectorVoid: {
                Vector v = byName ? typed.vector : ((VectorReturnMsgSend)(void (*)(void))method)(object, selector);
                JSValue vectorValue = JSVectorWithVector(context, v);
                if (JS_IsException(vectorValue)) {
                    error = true;
                } else {
                    *outResult = vectorValue;
                }
                break;
            }

            case kMethodTypeQuaternionVoid: {
                Quaternion q = byName ? typed.quaternion : ((QuaternionReturnMsgSend)(void (*)(void))method)(object, selector);
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
        // An entity's text names its object, whose address it holds.
        // The entity's object's text comes from the facade, byte for byte.
        std::string described = (entity != nullptr) ? oo::EntityShortDescription(entity) : oo::ShortDescriptionOf(object);
        cxx_OOJSReportError(context, "%s.callObjC(): %s does not respond to method %s.", oo_jsClassName.c_str(), described.c_str(), (selectorString ? selectorString->c_str() : "(null)"));
        error = true;
    }

    return !error;

    OOJS_PROFILE_EXIT
}
} // namespace

bool OOJSCallObjCObjectMethod(JSContext* context, id object, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult)
{
    return CallMethod(context, object, oo_jsClassName, argc, argv, outResult, false, nullptr);
}

bool OOJSCallEntityMethod(JSContext* context, Entity* entity, const std::string& oo_jsClassName, int argc, JSValueConst* argv, JSValue* outResult)
{
    return CallMethod(context, nil, oo_jsClassName, argc, argv, outResult, true, entity); // the C++ entity only
}

/*	Whether method has the signature returnType (self, _cmd[, argument]): the same return type and
        the same argument types, as the method signature objects' -isEqual: compared them (offsets
        and frame size are not compared). The template class whose methods gave these encodings
        went with the bridge: they are @encode() of the same types.
*/
namespace {
static bool SameTypeEncoding(char* copied, const char* expected)
{
    bool result = (copied != NULL && expected != NULL && strcmp(copied, expected) == 0);
    free(copied);
    return result;
}

static bool SignatureMatch(Method method, const char* returnType, const char* argument)
{
    if (method == NULL)
        return false;

    const char* arguments[] = { @encode(id),
        @encode(SEL),
        argument };
    unsigned argCount = method_getNumberOfArguments(method);
    if (argCount != (argument != NULL ? 3u : 2u))
        return false;
    if (!SameTypeEncoding(method_copyReturnType(method), returnType))
        return false;
    for (unsigned i = 0; i < argCount; i++) {
        if (!SameTypeEncoding(method_copyArgumentType(method, i), arguments[i]))
            return false;
    }
    return true;
}
} // namespace

static MethodType GetMethodType(id object, SEL selector)
{
    Method method = class_getInstanceMethod(object_getClass(object), selector);

    if (SignatureMatch(method, @encode(void), NULL))
        return kMethodTypeVoidVoid;
    // The C++ signatures of a selector called by name (ADR-0055 item 5), which OOCallByName calls:
    // the joined string argument, a PList result. oo-qps.72 deleted the id-parameter forms
    // (-voidObjectMethod:, -objectObjectMethod:): OOCallByName no longer passes an object.
    if (SignatureMatch(method, @encode(void), @encode(const std::string&)))
        return kMethodTypeVoidObject;
    if (SignatureMatch(method, @encode(oo::PList), @encode(const std::string&)))
        return kMethodTypeObjectObject;
    if (SignatureMatch(method, @encode(oo::PList), NULL))
        return kMethodTypePListVoid;

    MethodType type = (MethodType)OOShaderUniformTypeFromMethod(method);
    if (type != kMethodTypeInvalid)
        return type;

    return kMethodTypeInvalid;
}

#endif
