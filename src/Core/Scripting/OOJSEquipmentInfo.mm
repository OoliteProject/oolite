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

#import "OOFoundationBridge.h"

static JSClassID sEquipmentInfoClassID;

static JSValue EquipmentInfoGetProperty(OOJS_GETTER_ARGS);
static JSValue EquipmentInfoSetProperty(OOJS_SETTER_ARGS);

static JSValue EquipmentInfoGetAllEqipment(OOJS_GETTER_ARGS);

namespace {

    // A colour's components as its -normalizedArray gave them to JavaScript: floats, null for no colour.
    oo::PList NormalizedColorComponents(OOColor* color)
    {
        if (color == nil)
            return oo::PList();
        oo::PList::Array components;
        for (float component : [color cxx_normalizedArray])
            components.push_back(oo::PList::singleReal(component));
        return oo::PList(std::move(components));
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
        return [OOEquipmentType cxx_equipmentTypeWithIdentifier:*string];
    return nil;

    OOJS_PROFILE_EXIT
}

std::optional<std::string> JSValueToEquipmentKey(JSContext* context, JSValueConst value)
{
    return [JSValueToEquipmentType(context, value) cxx_identifier];
}

std::optional<std::string> JSValueToEquipmentKeyRelaxed(JSContext* context, JSValueConst value, BOOL* outExists)
{
    OOJS_PROFILE_ENTER

    std::optional<std::string> result;
    BOOL exists = NO;
    const oo::PList plistValue = cxx_OOJSPListFromJSValue(context, value);
    id objValue = oo::ObjectIn(plistValue);

    if ([objValue isKindOfClass:[OOEquipmentType class]]) {
        result = [objValue cxx_identifier];
        exists = YES;
    } else if (const std::string* stringValue = plistValue.getIf<std::string>()) {
        /*	To enforce deliberate backwards incompatibility, reject strings
                ending with _DAMAGED unless someone actually named an equip that
                way.
         */
        exists = [OOEquipmentType cxx_equipmentTypeWithIdentifier:*stringValue] != nil;
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
    id result = nil;
    NSUInteger inst_time;

    if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &eqType)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kEquipmentInfo_equipmentKey:
        result = oo::NSStringOrNil([eqType cxx_identifier]);
        break;

    case kEquipmentInfo_name:
        result = oo::NSStringOrNil([eqType cxx_name]);
        break;

    case kEquipmentInfo_calculatedPrice:
        if ([eqType cxx_identifier] == "EQ_FUEL") {
            return JS_NewNumber(context, (PLAYER_MAX_FUEL - [OOPlayerForScripting() fuel]) * [eqType price] * [OOPlayerForScripting() fuelChargeRate]);
        } else if ([eqType cxx_identifier] == "EQ_RENOVATION") {
            return JS_NewNumber(context, [OOPlayerForScripting() renovationCosts]);
        } else {
            return JS_NewNumber(context, ([eqType cxx_identifier].has_value() ? [OOPlayerForScripting() cxx_adjustPriceByScriptForEqKey:*[eqType cxx_identifier] withCurrent:[eqType price]] : [eqType price]));
        }
    case kEquipmentInfo_canCarryMultiple:
        return OOJSValueFromBOOL([eqType canCarryMultiple]);

    case kEquipmentInfo_canBeDamaged:
        return OOJSValueFromBOOL([eqType canBeDamaged]);

    case kEquipmentInfo_description:
        result = oo::NSStringOrNil([eqType cxx_descriptiveText]);
        break;

    case kEquipmentInfo_damageProbability:
        return JS_NewNumber(context, [eqType damageProbability]);

    case kEquipmentInfo_displayColor:
        result = oo::ObjectFromPList(NormalizedColorComponents([eqType displayColor]));
        break;

    case kEquipmentInfo_fastAffinityDefensive:
        return OOJSValueFromBOOL([eqType fastAffinityDefensive]);

    case kEquipmentInfo_fastAffinityOffensive:
        return OOJSValueFromBOOL([eqType fastAffinityOffensive]);

    case kEquipmentInfo_defaultActivateKey:
        result = oo::ObjectFromPList([eqType cxx_defaultActivateKey]);
        break;

    case kEquipmentInfo_defaultModeKey:
        result = oo::ObjectFromPList([eqType cxx_defaultModeKey]);
        break;

    case kEquipmentInfo_techLevel:
        return JS_NewInt32(context, (int32_t)[eqType techLevel]);

    case kEquipmentInfo_effectiveTechLevel:
        return JS_NewInt32(context, (int32_t)[eqType effectiveTechLevel]);

    case kEquipmentInfo_price:
        return JS_NewNumber(context, [eqType price]);

    case kEquipmentInfo_provides:
        result = oo::NSArrayFromStrings([eqType cxx_providesForScripting]);
        break;

    case kEquipmentInfo_installationTime:
        inst_time = [eqType installTime];
        if (inst_time == 0) {
            inst_time = [eqType price] + 600;
        }
        return JS_NewInt32(context, (int32_t)inst_time);

    case kEquipmentInfo_isAvailableToAll:
        return OOJSValueFromBOOL([eqType isAvailableToAll]);

    case kEquipmentInfo_isAvailableToNPCs:
        return OOJSValueFromBOOL([eqType isAvailableToNPCs]);

    case kEquipmentInfo_isAvailableToPlayer:
        return OOJSValueFromBOOL([eqType isAvailableToPlayer]);

    case kEquipmentInfo_repairTime:
        return JS_NewInt32(context, (int32_t)[eqType repairTime]);

    case kEquipmentInfo_requiresEmptyPylon:
        return OOJSValueFromBOOL([eqType requiresEmptyPylon]);

    case kEquipmentInfo_requiresMountedPylon:
        return OOJSValueFromBOOL([eqType requiresMountedPylon]);

    case kEquipmentInfo_requiresCleanLegalRecord:
        return OOJSValueFromBOOL([eqType requiresCleanLegalRecord]);

    case kEquipmentInfo_requiresNonCleanLegalRecord:
        return OOJSValueFromBOOL([eqType requiresNonCleanLegalRecord]);

    case kEquipmentInfo_requiresFreePassengerBerth:
        return OOJSValueFromBOOL([eqType requiresFreePassengerBerth]);

    case kEquipmentInfo_requiresFullFuel:
        return OOJSValueFromBOOL([eqType requiresFullFuel]);

    case kEquipmentInfo_requiresNonFullFuel:
        return OOJSValueFromBOOL([eqType requiresNonFullFuel]);

    case kEquipmentInfo_isExternalStore:
        return OOJSValueFromBOOL([eqType isMissileOrMine]);

    case kEquipmentInfo_isPortableBetweenShips:
        return OOJSValueFromBOOL([eqType isPortableBetweenShips]);

    case kEquipmentInfo_isVisible:
        return OOJSValueFromBOOL([eqType isVisible]);

    case kEquipmentInfo_requiredCargoSpace:
        return JS_NewInt32(context, (int32_t)[eqType requiredCargoSpace]);

    case kEquipmentInfo_requiresEquipment:
        result = [eqType cxx_requiresEquipment].has_value() ? [oo::NSSetFromStrings(*[eqType cxx_requiresEquipment]) allObjects] : nil;
        break;

    case kEquipmentInfo_requiresAnyEquipment:
        result = [eqType cxx_requiresAnyEquipment].has_value() ? [oo::NSSetFromStrings(*[eqType cxx_requiresAnyEquipment]) allObjects] : nil;
        break;

    case kEquipmentInfo_incompatibleEquipment:
        result = [eqType cxx_incompatibleEquipment].has_value() ? [oo::NSSetFromStrings(*[eqType cxx_incompatibleEquipment]) allObjects] : nil;
        break;

    case kEquipmentInfo_scriptInfo: {
        const oo::PList info = [eqType scriptInfo];
        result = oo::ObjectFromPList(info.isNull() ? oo::PList(oo::PList::Dict { }) : info); // empty rather than null
    } break;

    case kEquipmentInfo_scriptName:
        result = oo::NSStringOrNil([eqType cxx_scriptName]);
        if (result == nil)
            result = @"";
        break;

    case kEquipmentInfo_weaponInfo:
        result = oo::ObjectFromPList([eqType cxx_weaponInfo]);
        if (result == nil)
            result = oo::ObjectFromPList(oo::PList(oo::PList::Dict { })); // empty rather than null
        break;

    default:
        OOJSReportBadPropertySelector(context, thisObj, magic, sEquipmentInfoProperties, OOJS_COUNT(sEquipmentInfoProperties));
        return OOJSNativeFailure(context);
    }

    return OOJSValueFromNativeObject(context, result);

    OOJS_NATIVE_EXIT
}

static JSValue EquipmentInfoSetProperty(OOJS_SETTER_ARGS)
{

    OOJS_NATIVE_ENTER(context)

    OOEquipmentType* eqType = nil;
    int32_t iValue;
    OOColor* colorForScript = nil;

    if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &eqType)))
        return OOJSNativeFailure(context);

    switch (magic) {
    case kEquipmentInfo_displayColor:
        colorForScript = [OOColor colorWithDescription:oo::ObjectFromPList(cxx_OOJSPListFromJSValue(context, value))];
        if (colorForScript != nil || JS_IsNull(value)) {
            [eqType setDisplayColor:colorForScript];
            return JS_UNDEFINED;
        }
        break;
    case kEquipmentInfo_effectiveTechLevel:
        cxx_OOStandardsDeprecated(oo::str::format("TL99 for variable tech level is deprecated for %s", [eqType cxx_identifier].value_or("(null)").c_str()));
        if (!OOEnforceStandards() && [eqType techLevel] == kOOVariableTechLevel) {
            if (JS_IsNull(value)) {
                // reset mission variable
                [OOPlayerForScripting() cxx_setMissionVariable:oo::PList()
                                                        forKey:"mission_TL_FOR_" + [eqType cxx_identifier].value_or("")];
                return JS_UNDEFINED;
            }
            if (OOJSValueToInt32(context, value, &iValue)) {
                if (iValue < 0)
                    iValue = 0;
                if (15 < iValue && iValue != kOOVariableTechLevel)
                    iValue = 15;
                [OOPlayerForScripting() cxx_setMissionVariable:oo::PList(oo::str::format("%u", iValue))
                                                        forKey:"mission_TL_FOR_" + [eqType cxx_identifier].value_or("")];
                return JS_UNDEFINED;
            }
        } else {
            cxx_OOJSReportWarning(context, "Cannot modify effective tech level for %s, because its base tech level is not 99.", [eqType cxx_identifier].value_or("(null)").c_str());
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

    return OOJSValueFromNativeObject(context, oo::NSArrayFromObjects([OOEquipmentType cxx_allEquipmentTypes]));

    OOJS_NATIVE_EXIT
}

@implementation OOEquipmentType (OOJavaScriptExtensions)

/*	As with SpiderMonkey, the JS object retains the equipment type, and
        _jsSelf is a weak (uncounted) reference to the JS object, cleared by
        -oo_clearJSSelf: when the JS object is finalized.
*/
- (JSValue)oo_jsValueInContext:(JSContext*)context
{
    if (!JS_IsObject(_jsSelf)) {
        JSValue jsSelf = JS_NewObjectClass(context, (int)sEquipmentInfoClassID);
        if (JS_IsException(jsSelf)) {
            JS_FreeValue(context, JS_GetException(context));
            return JS_NULL;
        }
        JS_SetOpaque(jsSelf, [self retain]);

        // Weak: the caller gets the only reference.
        _jsSelf = jsSelf;
        return jsSelf;
    }

    return JS_DupValue(context, _jsSelf);
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return std::string("EquipmentInfo");
}

- (void)oo_clearJSSelf:(JSValueConst)selfVal
{
    if (JS_IsObject(_jsSelf) && JS_VALUE_GET_PTR(_jsSelf) == JS_VALUE_GET_PTR(selfVal))
        _jsSelf = JS_UNDEFINED;
}

@end

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

    OOJS_RETURN_OBJECT([OOEquipmentType cxx_equipmentTypeWithIdentifier:*key]);

    OOJS_NATIVE_EXIT
}
