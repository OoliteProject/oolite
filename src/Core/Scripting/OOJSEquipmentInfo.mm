/*

OOJSEquipmentInfo.m (QuickJS-ng)


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

#import "OOJSEquipmentInfo.h"
#import "OODebugStandards.h"
#import "OOJSPlayer.h"
#import "OOJavaScriptEngine.h"

#import "OOObjCPList.h"
#include "oofnd/String.hpp"

/*
        C++20 since bead oo-supk, converted the way bead oo-ppc converted OOJSVector.mm (proposed
        ADR-0056 amendment oo-ppc). The JS class was already C++ on QuickJS-ng;
        OOJS_NATIVE_ENTER/EXIT and OOJS_PROFILE_ENTER/EXIT are C++ try/catch and scope guards
        (OOJSEngineNativeWrappers.h); BOOL/YES/NO are bool/true/false. OOEquipmentType
        (OOJavaScriptExtensions), the category on the converted class's façade that owns its _jsSelf
        ivar, became three free functions that take the façade's ivar by reference, and its methods
        moved to OOJSEquipmentInfo+ObjCBridge.mm (amendment oo-6ia4 item 3). OOEquipmentType and
        OOColor, which are C++ since beads oo-fg7i and oo-11m, are reached as cxx:: classes through
        oo::ToCxx/oo::ToObjC (amendment oo-ppc, item 4); the property hooks cross once, and Ask()
        answers what a message to nil answered for the prototype, which has no type.
        JSValueToEquipmentType() still answers the façade, and JSValueToEquipmentKeyRelaxed()'s
        out-parameter stays BOOL *, so their callers compile unchanged. Messages to classes that are
        still Objective-C (PlayerEntity) stay as they are, which is why the file is still .mm until
        Phase 4.
*/

static JSClassID sEquipmentInfoClassID;

static JSValue EquipmentInfoGetProperty(OOJS_GETTER_ARGS);
static JSValue EquipmentInfoSetProperty(OOJS_SETTER_ARGS);

static JSValue EquipmentInfoGetAllEqipment(OOJS_GETTER_ARGS);

namespace {

    // A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
    oo::PList NormalizedColorComponents(cxx::OOColor* color)
    {
        if (color == nullptr)
            return oo::PList();
        oo::PList::Array components;
        for (float component : color->normalizedArray())
            components.push_back(oo::PList::singleReal(component));
        return oo::PList(std::move(components));
    }

    // What the type answers, or what a message to nil answered (0, false, nullopt, null, an empty
    // list) when there is no type: the prototype's case (amendment oo-6ia4 item 2).
    template <typename Result>
    Result Ask(cxx::OOEquipmentType* type, Result (cxx::OOEquipmentType::*member)())
    {
        return type != nullptr ? (type->*member)() : Result { };
    }

    // A string, or null for none (what a Foundation string or nil gave JavaScript).
    oo::PList StringOrNull(const std::optional<std::string>& string)
    {
        return string.has_value() ? oo::PList(*string) : oo::PList();
    }

    // Equipment keys as an array of strings; null for none. They are sorted and unique already, so
    // this is the set they were, in key order (the Foundation set's -allObjects gave hash order).
    oo::PList KeyArrayOrNull(const std::optional<std::vector<std::string>>& keys)
    {
        if (!keys.has_value())
            return oo::PList();
        return oo::PList(oo::PList::Array(keys->begin(), keys->end()));
    }

} // namespace

// Methods
static JSValue EquipmentInfoStaticInfoForKey(OOJS_NATIVE_ARGS);

static JSClassDef sEquipmentInfoClass = {
    .class_name = "EquipmentInfo",
    .finalizer = OOJSObjectWrapperFinalize,
};

enum {
    // Property IDs
    kEquipmentInfo_calculatedPrice,
    kEquipmentInfo_canBeDamaged,
    kEquipmentInfo_canCarryMultiple,
    kEquipmentInfo_damageProbability,
    kEquipmentInfo_description,
    kEquipmentInfo_displayColor,
    kEquipmentInfo_effectiveTechLevel,
    kEquipmentInfo_equipmentKey,
    kEquipmentInfo_fastAffinityDefensive,
    kEquipmentInfo_fastAffinityOffensive,
    kEquipmentInfo_defaultActivateKey,
    kEquipmentInfo_defaultModeKey,
    kEquipmentInfo_incompatibleEquipment,
    kEquipmentInfo_installationTime,
    kEquipmentInfo_isAvailableToAll,
    kEquipmentInfo_isAvailableToNPCs,
    kEquipmentInfo_isAvailableToPlayer,
    kEquipmentInfo_isExternalStore, // is missile or mine
    kEquipmentInfo_isPortableBetweenShips,
    kEquipmentInfo_isVisible,
    kEquipmentInfo_name,
    kEquipmentInfo_price,
    kEquipmentInfo_provides,
    kEquipmentInfo_repairTime,
    kEquipmentInfo_requiredCargoSpace,
    kEquipmentInfo_requiresAnyEquipment,
    kEquipmentInfo_requiresCleanLegalRecord,
    kEquipmentInfo_requiresEmptyPylon,
    kEquipmentInfo_requiresEquipment,
    kEquipmentInfo_requiresFreePassengerBerth,
    kEquipmentInfo_requiresFullFuel,
    kEquipmentInfo_requiresMountedPylon,
    kEquipmentInfo_requiresNonCleanLegalRecord,
    kEquipmentInfo_requiresNonFullFuel,
    kEquipmentInfo_scriptInfo, // arbitrary data for scripts, dictionary, read-only
    kEquipmentInfo_scriptName,
    kEquipmentInfo_techLevel,
    kEquipmentInfo_weaponInfo
};

static const JSCFunctionListEntry sEquipmentInfoProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("calculatedPrice", EquipmentInfoGetProperty, kEquipmentInfo_calculatedPrice),
    OOJS_PROPERTY_RO("canBeDamaged", EquipmentInfoGetProperty, kEquipmentInfo_canBeDamaged),
    OOJS_PROPERTY_RO("canCarryMultiple", EquipmentInfoGetProperty, kEquipmentInfo_canCarryMultiple),
    OOJS_PROPERTY_RO("damageProbability", EquipmentInfoGetProperty, kEquipmentInfo_damageProbability),
    OOJS_PROPERTY_RO("description", EquipmentInfoGetProperty, kEquipmentInfo_description),
    OOJS_PROPERTY_RW("displayColor", EquipmentInfoGetProperty, EquipmentInfoSetProperty, kEquipmentInfo_displayColor),
    OOJS_PROPERTY_RW("effectiveTechLevel", EquipmentInfoGetProperty, EquipmentInfoSetProperty, kEquipmentInfo_effectiveTechLevel),
    OOJS_PROPERTY_RO("equipmentKey", EquipmentInfoGetProperty, kEquipmentInfo_equipmentKey),
    OOJS_PROPERTY_RO("fastAffinityDefensive", EquipmentInfoGetProperty, kEquipmentInfo_fastAffinityDefensive),
    OOJS_PROPERTY_RO("fastAffinityOffensive", EquipmentInfoGetProperty, kEquipmentInfo_fastAffinityOffensive),
    OOJS_PROPERTY_RO("defaultActivateKey", EquipmentInfoGetProperty, kEquipmentInfo_defaultActivateKey),
    OOJS_PROPERTY_RO("defaultModeKey", EquipmentInfoGetProperty, kEquipmentInfo_defaultModeKey),
    OOJS_PROPERTY_RO("incompatibleEquipment", EquipmentInfoGetProperty, kEquipmentInfo_incompatibleEquipment),
    OOJS_PROPERTY_RO("installationTime", EquipmentInfoGetProperty, kEquipmentInfo_installationTime),
    OOJS_PROPERTY_RO("isAvailableToAll", EquipmentInfoGetProperty, kEquipmentInfo_isAvailableToAll),
    OOJS_PROPERTY_RO("isAvailableToNPCs", EquipmentInfoGetProperty, kEquipmentInfo_isAvailableToNPCs),
    OOJS_PROPERTY_RO("isAvailableToPlayer", EquipmentInfoGetProperty, kEquipmentInfo_isAvailableToPlayer),
    OOJS_PROPERTY_RO("isExternalStore", EquipmentInfoGetProperty, kEquipmentInfo_isExternalStore),
    OOJS_PROPERTY_RO("isPortableBetweenShips", EquipmentInfoGetProperty, kEquipmentInfo_isPortableBetweenShips),
    OOJS_PROPERTY_RO("isVisible", EquipmentInfoGetProperty, kEquipmentInfo_isVisible),
    OOJS_PROPERTY_RO("name", EquipmentInfoGetProperty, kEquipmentInfo_name),
    OOJS_PROPERTY_RO("price", EquipmentInfoGetProperty, kEquipmentInfo_price),
    OOJS_PROPERTY_RO("provides", EquipmentInfoGetProperty, kEquipmentInfo_provides),
    OOJS_PROPERTY_RO("repairTime", EquipmentInfoGetProperty, kEquipmentInfo_repairTime),
    OOJS_PROPERTY_RO("requiredCargoSpace", EquipmentInfoGetProperty, kEquipmentInfo_requiredCargoSpace),
    OOJS_PROPERTY_RO("requiresAnyEquipment", EquipmentInfoGetProperty, kEquipmentInfo_requiresAnyEquipment),
    OOJS_PROPERTY_RO("requiresCleanLegalRecord", EquipmentInfoGetProperty, kEquipmentInfo_requiresCleanLegalRecord),
    OOJS_PROPERTY_RO("requiresEmptyPylon", EquipmentInfoGetProperty, kEquipmentInfo_requiresEmptyPylon),
    OOJS_PROPERTY_RO("requiresEquipment", EquipmentInfoGetProperty, kEquipmentInfo_requiresEquipment),
    OOJS_PROPERTY_RO("requiresFreePassengerBerth", EquipmentInfoGetProperty, kEquipmentInfo_requiresFreePassengerBerth),
    OOJS_PROPERTY_RO("requiresFullFuel", EquipmentInfoGetProperty, kEquipmentInfo_requiresFullFuel),
    OOJS_PROPERTY_RO("requiresMountedPylon", EquipmentInfoGetProperty, kEquipmentInfo_requiresMountedPylon),
    OOJS_PROPERTY_RO("requiresNonCleanLegalRecord", EquipmentInfoGetProperty, kEquipmentInfo_requiresNonCleanLegalRecord),
    OOJS_PROPERTY_RO("requiresNonFullFuel", EquipmentInfoGetProperty, kEquipmentInfo_requiresNonFullFuel),
    OOJS_PROPERTY_RO("scriptInfo", EquipmentInfoGetProperty, kEquipmentInfo_scriptInfo),
    OOJS_PROPERTY_RO("scriptName", EquipmentInfoGetProperty, kEquipmentInfo_scriptName),
    OOJS_PROPERTY_RO("techLevel", EquipmentInfoGetProperty, kEquipmentInfo_techLevel),
    OOJS_PROPERTY_RO("weaponInfo", EquipmentInfoGetProperty, kEquipmentInfo_weaponInfo),
};

static const JSCFunctionListEntry sEquipmentInfoMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, OOJSObjectWrapperToString),
};

static const JSCFunctionListEntry sEquipmentInfoStaticMethods[] = {
    // Static property
    OOJS_PROPERTY_RO("allEquipment", EquipmentInfoGetAllEqipment, 0),
    // JS name, min args, function
    JS_CFUNC_DEF("infoForKey", 0, EquipmentInfoStaticInfoForKey),
};

DEFINE_JS_OBJECT_GETTER(JSEquipmentInfoGetEquipmentType, sEquipmentInfoClassID, OOEquipmentType)

// *** Public ***

void InitOOJSEquipmentInfo(JSContext* context, JSValueConst global)
{
    OOJSRegisterClass(&sEquipmentInfoClassID, &sEquipmentInfoClass);
    OOJSInitClass(context, global, sEquipmentInfoClassID, JS_UNDEFINED, OOJSUnconstructableConstruct, 0,
        sEquipmentInfoProperties, OOJS_COUNT(sEquipmentInfoProperties), sEquipmentInfoMethods, OOJS_COUNT(sEquipmentInfoMethods),
        sEquipmentInfoStaticMethods, OOJS_COUNT(sEquipmentInfoStaticMethods));

    OOJSRegisterObjectConverter(sEquipmentInfoClassID, OOJSBasicPrivateObjectConverter);
}

OOEquipmentType* JSValueToEquipmentType(JSContext* context, JSValueConst value)
{
    OOJS_PROFILE_ENTER

    if (JS_IsObject(value)) {
        if (JS_GetClassID(value) == sEquipmentInfoClassID) {
            return (OOEquipmentType*)JS_GetOpaque(value, sEquipmentInfoClassID);
        }
    }

    std::optional<std::string> string = cxx_OOStringFromJSValue(context, value);
    if (string.has_value())
        return oo::ToObjC(cxx::OOEquipmentType::equipmentTypeWithIdentifier(*string));
    return nil;

    OOJS_PROFILE_EXIT
}

std::optional<std::string> JSValueToEquipmentKey(JSContext* context, JSValueConst value)
{
    return Ask(oo::ToCxx(JSValueToEquipmentType(context, value)), &cxx::OOEquipmentType::identifier);
}

std::optional<std::string> JSValueToEquipmentKeyRelaxed(JSContext* context, JSValueConst value, BOOL* outExists)
{
    OOJS_PROFILE_ENTER

    std::optional<std::string> result;
    bool exists = false;
    const oo::PList plistValue = cxx_OOJSPListFromJSValue(context, value);
    id objValue = oo::ObjectIn(plistValue);

    if ([objValue isKindOfClass:[OOEquipmentType class]]) {
        result = oo::ToCxx(static_cast<OOEquipmentType*>(objValue))->identifier();
        exists = true;
    } else if (const std::string* stringValue = plistValue.getIf<std::string>()) {
        /*	To enforce deliberate backwards incompatibility, reject strings
                ending with _DAMAGED unless someone actually named an equip that
                way.
         */
        exists = cxx::OOEquipmentType::equipmentTypeWithIdentifier(*stringValue) != nullptr;
        std::string string = *stringValue;
        if (exists || !oo::str::hasSuffix(string, "_DAMAGED")) {
            result = string;
        }
    }

    if (outExists != NULL)
        *outExists = exists;
    return result;

    OOJS_PROFILE_EXIT
}

// *** Implementation stuff ***

static JSValue EquipmentInfoGetProperty(OOJS_GETTER_ARGS)
{

    OOJS_NATIVE_ENTER(context)

    OOEquipmentType* eqType = nil;
    oo::PList result; // null maps to null
    NSUInteger inst_time;

    if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &eqType)))
        return OOJSNativeFailure(context);
    cxx::OOEquipmentType* type = oo::ToCxx(eqType); // null for the prototype: see Ask()

    switch (magic) {
    case kEquipmentInfo_equipmentKey:
        result = StringOrNull(Ask(type, &cxx::OOEquipmentType::identifier));
        break;

    case kEquipmentInfo_name:
        result = StringOrNull(Ask(type, &cxx::OOEquipmentType::name));
        break;

    case kEquipmentInfo_calculatedPrice:
        if (Ask(type, &cxx::OOEquipmentType::identifier) == "EQ_FUEL") {
            return JS_NewNumber(context, (PLAYER_MAX_FUEL - [OOPlayerForScripting() fuel]) * Ask(type, &cxx::OOEquipmentType::price) * [OOPlayerForScripting() fuelChargeRate]);
        } else if (Ask(type, &cxx::OOEquipmentType::identifier) == "EQ_RENOVATION") {
            return JS_NewNumber(context, [OOPlayerForScripting() renovationCosts]);
        } else {
            return JS_NewNumber(context, (Ask(type, &cxx::OOEquipmentType::identifier).has_value() ? [OOPlayerForScripting() cxx_adjustPriceByScriptForEqKey:*Ask(type, &cxx::OOEquipmentType::identifier) withCurrent:Ask(type, &cxx::OOEquipmentType::price)] : Ask(type, &cxx::OOEquipmentType::price)));
        }
    case kEquipmentInfo_canCarryMultiple:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::canCarryMultiple));

    case kEquipmentInfo_canBeDamaged:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::canBeDamaged));

    case kEquipmentInfo_description:
        result = StringOrNull(Ask(type, &cxx::OOEquipmentType::descriptiveText));
        break;

    case kEquipmentInfo_damageProbability:
        return JS_NewNumber(context, Ask(type, &cxx::OOEquipmentType::damageProbability));

    case kEquipmentInfo_displayColor:
        result = NormalizedColorComponents(Ask(type, &cxx::OOEquipmentType::displayColor).get());
        break;

    case kEquipmentInfo_fastAffinityDefensive:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::fastAffinityDefensive));

    case kEquipmentInfo_fastAffinityOffensive:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::fastAffinityOffensive));

    case kEquipmentInfo_defaultActivateKey:
        result = Ask(type, &cxx::OOEquipmentType::defaultActivateKey);
        break;

    case kEquipmentInfo_defaultModeKey:
        result = Ask(type, &cxx::OOEquipmentType::defaultModeKey);
        break;

    case kEquipmentInfo_techLevel:
        return JS_NewInt32(context, (int32_t)Ask(type, &cxx::OOEquipmentType::techLevel));

    case kEquipmentInfo_effectiveTechLevel:
        return JS_NewInt32(context, (int32_t)Ask(type, &cxx::OOEquipmentType::effectiveTechLevel));

    case kEquipmentInfo_price:
        return JS_NewNumber(context, Ask(type, &cxx::OOEquipmentType::price));

    case kEquipmentInfo_provides: {
        const std::vector<std::string> provides = Ask(type, &cxx::OOEquipmentType::providesForScripting);
        result = oo::PList(oo::PList::Array(provides.begin(), provides.end()));
    } break;

    case kEquipmentInfo_installationTime:
        inst_time = Ask(type, &cxx::OOEquipmentType::installTime);
        if (inst_time == 0) {
            inst_time = Ask(type, &cxx::OOEquipmentType::price) + 600;
        }
        return JS_NewInt32(context, (int32_t)inst_time);

    case kEquipmentInfo_isAvailableToAll:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::isAvailableToAll));

    case kEquipmentInfo_isAvailableToNPCs:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::isAvailableToNPCs));

    case kEquipmentInfo_isAvailableToPlayer:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::isAvailableToPlayer));

    case kEquipmentInfo_repairTime:
        return JS_NewInt32(context, (int32_t)Ask(type, &cxx::OOEquipmentType::repairTime));

    case kEquipmentInfo_requiresEmptyPylon:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresEmptyPylon));

    case kEquipmentInfo_requiresMountedPylon:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresMountedPylon));

    case kEquipmentInfo_requiresCleanLegalRecord:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresCleanLegalRecord));

    case kEquipmentInfo_requiresNonCleanLegalRecord:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresNonCleanLegalRecord));

    case kEquipmentInfo_requiresFreePassengerBerth:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresFreePassengerBerth));

    case kEquipmentInfo_requiresFullFuel:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresFullFuel));

    case kEquipmentInfo_requiresNonFullFuel:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::requiresNonFullFuel));

    case kEquipmentInfo_isExternalStore:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::isMissileOrMine));

    case kEquipmentInfo_isPortableBetweenShips:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::isPortableBetweenShips));

    case kEquipmentInfo_isVisible:
        return OOJSValueFromBOOL(Ask(type, &cxx::OOEquipmentType::isVisible));

    case kEquipmentInfo_requiredCargoSpace:
        return JS_NewInt32(context, (int32_t)Ask(type, &cxx::OOEquipmentType::requiredCargoSpace));

    case kEquipmentInfo_requiresEquipment:
        result = KeyArrayOrNull(Ask(type, &cxx::OOEquipmentType::requiresEquipment));
        break;

    case kEquipmentInfo_requiresAnyEquipment:
        result = KeyArrayOrNull(Ask(type, &cxx::OOEquipmentType::requiresAnyEquipment));
        break;

    case kEquipmentInfo_incompatibleEquipment:
        result = KeyArrayOrNull(Ask(type, &cxx::OOEquipmentType::incompatibleEquipment));
        break;

    case kEquipmentInfo_scriptInfo: {
        const oo::PList info = Ask(type, &cxx::OOEquipmentType::scriptInfo);
        result = info.isNull() ? oo::PList(oo::PList::Dict { }) : info; // empty rather than null
    } break;

    case kEquipmentInfo_scriptName:
        result = oo::PList(Ask(type, &cxx::OOEquipmentType::scriptName).value_or(std::string()));
        break;

    case kEquipmentInfo_weaponInfo:
        result = Ask(type, &cxx::OOEquipmentType::weaponInfo);
        if (result.isNull())
            result = oo::PList(oo::PList::Dict { }); // empty rather than null
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sEquipmentInfoProperties, OOJS_COUNT(sEquipmentInfoProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromPList(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue EquipmentInfoSetProperty(OOJS_SETTER_ARGS)
{

    OOJS_NATIVE_ENTER(context)

    OOEquipmentType* eqType = nil;
    int32_t iValue;
    oo::Ref<cxx::OOColor> colorForScript;

    if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &eqType)))
        return OOJSNativeFailure(context);
    cxx::OOEquipmentType* type = oo::ToCxx(eqType); // null for the prototype: see Ask()

    switch (magic) {
    case kEquipmentInfo_displayColor:
        colorForScript = cxx::OOColor::colorWithDescription(cxx_OOJSPListFromJSValue(context, value));
        if (colorForScript != nullptr || JS_IsNull(value)) {
            if (type != nullptr)
                type->setDisplayColor(colorForScript.get()); // (a message to nil did nothing)
            return JS_UNDEFINED;
        }
        break;
    case kEquipmentInfo_effectiveTechLevel:
        cxx_OOStandardsDeprecated(oo::str::format("TL99 for variable tech level is deprecated for %s", Ask(type, &cxx::OOEquipmentType::identifier).value_or("(null)").c_str()));
        if (!OOEnforceStandards() && Ask(type, &cxx::OOEquipmentType::techLevel) == kOOVariableTechLevel) {
            if (JS_IsNull(value)) {
                // reset mission variable
                [OOPlayerForScripting() cxx_setMissionVariable:oo::PList()
                                                        forKey:"mission_TL_FOR_" + Ask(type, &cxx::OOEquipmentType::identifier).value_or("")];
                return JS_UNDEFINED;
            }
            if (OOJSValueToInt32(context, value, &iValue)) {
                if (iValue < 0)
                    iValue = 0;
                if (15 < iValue && iValue != kOOVariableTechLevel)
                    iValue = 15;
                [OOPlayerForScripting() cxx_setMissionVariable:oo::PList(oo::str::format("%u", iValue))
                                                        forKey:"mission_TL_FOR_" + Ask(type, &cxx::OOEquipmentType::identifier).value_or("")];
                return JS_UNDEFINED;
            }
        } else {
            cxx_OOJSReportWarning(context, "Cannot modify effective tech level for %s, because its base tech level is not 99.", Ask(type, &cxx::OOEquipmentType::identifier).value_or("(null)").c_str());
            return JS_UNDEFINED;
        }
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sEquipmentInfoProperties, OOJS_COUNT(sEquipmentInfoProperties));
        return OOJSNativeFailure(context);
    }

    OOJSReportBadPropertyValue(context, thisObj, magic, sEquipmentInfoProperties, OOJS_COUNT(sEquipmentInfoProperties), value);
    return OOJSNativeFailure(context);

    OOJS_NATIVE_EXIT
}

static JSValue EquipmentInfoGetAllEqipment(OOJS_GETTER_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::vector<oo::ObjCRef<OOEquipmentType*>> facades; // what +cxx_allEquipmentTypes answered
    for (const oo::Ref<cxx::OOEquipmentType>& equipmentType : cxx::OOEquipmentType::allEquipmentTypes())
        facades.emplace_back(oo::ToObjC(equipmentType));
    return OOJSValueFromPList(context, oo::PListFromObjects(facades));

    OOJS_NATIVE_EXIT
}

// The bodies of OOEquipmentType (OOJavaScriptExtensions), which the engine reaches by selector:
// its methods forward to these from OOJSEquipmentInfo+ObjCBridge.mm, passing the façade's _jsSelf
// ivar (amendment oo-6ia4 item 3).

/*	As with SpiderMonkey, the JS object retains the equipment type, and
        _jsSelf is a weak (uncounted) reference to the JS object, cleared by
        -oo_clearJSSelf: when the JS object is finalized.
*/
JSValue OOJSEquipmentInfoJSValueInContext(OOEquipmentType* equipmentType, JSValue& jsSelf, JSContext* context)
{
    if (!JS_IsObject(jsSelf)) {
        JSValue newSelf = JS_NewObjectClass(context, (int)sEquipmentInfoClassID);
        if (JS_IsException(newSelf)) {
            JS_FreeValue(context, JS_GetException(context));
            return JS_NULL;
        }
        JS_SetOpaque(newSelf, [equipmentType retain]);

        // Weak: the caller gets the only reference.
        jsSelf = newSelf;
        return newSelf;
    }

    return JS_DupValue(context, jsSelf);
}

std::optional<std::string> OOJSEquipmentInfoJSClassName(void)
{
    return std::string("EquipmentInfo");
}

void OOJSEquipmentInfoClearJSSelf(JSValue& jsSelf, JSValueConst selfVal)
{
    if (JS_IsObject(jsSelf) && JS_VALUE_GET_PTR(jsSelf) == JS_VALUE_GET_PTR(selfVal))
        jsSelf = JS_UNDEFINED;
}

// *** Static methods ***

// infoForKey(key : String): EquipmentInfo
static JSValue EquipmentInfoStaticInfoForKey(OOJS_NATIVE_ARGS)
{
    OOJS_NATIVE_ENTER(context)

    std::optional<std::string> key;

    if (argc > 0)
        key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
    if (!key.has_value()) {
        cxx_OOJSReportBadArguments(context, "EquipmentInfo", "infoForKey", MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
        return OOJSNativeFailure(context);
    }

    OOJS_RETURN_OBJECT(oo::ToObjC(cxx::OOEquipmentType::equipmentTypeWithIdentifier(*key)));

    OOJS_NATIVE_EXIT
}
