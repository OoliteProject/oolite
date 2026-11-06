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

#include "OOJSEquipmentInfo.h"

#include "OODebugStandards.h"
#include "OODescription.h"
#include "OOEquipmentType.h"
#include "OOJSPlayer.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

static JSClassID sEquipmentInfoClassID;

static JSValue EquipmentInfoGetProperty(OOJS_GETTER_ARGS);
static JSValue EquipmentInfoSetProperty(OOJS_SETTER_ARGS);

static JSValue EquipmentInfoGetAllEqipment(OOJS_GETTER_ARGS);

namespace {

// A colour's components as its -normalizedArray gave them to JavaScript:
// floats, null for no colour.
oo::PList NormalizedColorComponents(OOColor* color) {
  if (color == nullptr) return oo::PList();
  oo::PList::Array components;
  for (float component : color->normalizedArray())
    components.push_back(oo::PList::singleReal(component));
  return oo::PList(std::move(components));
}

// What the type answers, or what a message to nil answered (0, false, nullopt,
// null, an empty list) when there is no type: the prototype's case.
template <typename Result>
Result Ask(OOEquipmentType* type, Result (OOEquipmentType::*member)()) {
  return type != nullptr ? (type->*member)() : Result{};
}

// A string, or null for none (what a Foundation string or nil gave JavaScript).
oo::PList StringOrNull(const std::optional<std::string>& string) {
  return string.has_value() ? oo::PList(*string) : oo::PList();
}

// Equipment keys as an array of strings; null for none. They are sorted and
// unique already, so this is the set they were, in key order (the Foundation
// set's -allObjects gave hash order).
oo::PList KeyArrayOrNull(const std::optional<std::vector<std::string>>& keys) {
  if (!keys.has_value()) return oo::PList();
  return oo::PList(oo::PList::Array(keys->begin(), keys->end()));
}

}  // namespace

// Methods
static JSValue EquipmentInfoStaticInfoForKey(OOJS_NATIVE_ARGS);
static JSValue EquipmentInfoToString(OOJS_NATIVE_ARGS);

static JSClassDef sEquipmentInfoClass = {
    .class_name = "EquipmentInfo",
    .finalizer = OOJSCxxObjectWrapperFinalize,
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
  kEquipmentInfo_isExternalStore,  // is missile or mine
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
  kEquipmentInfo_scriptInfo,  // arbitrary data for scripts, dictionary,
                              // read-only
  kEquipmentInfo_scriptName,
  kEquipmentInfo_techLevel,
  kEquipmentInfo_weaponInfo
};

static const JSCFunctionListEntry sEquipmentInfoProperties[] = {
    // JS name, getter, setter, ID
    OOJS_PROPERTY_RO("calculatedPrice", EquipmentInfoGetProperty,
                     kEquipmentInfo_calculatedPrice),
    OOJS_PROPERTY_RO("canBeDamaged", EquipmentInfoGetProperty,
                     kEquipmentInfo_canBeDamaged),
    OOJS_PROPERTY_RO("canCarryMultiple", EquipmentInfoGetProperty,
                     kEquipmentInfo_canCarryMultiple),
    OOJS_PROPERTY_RO("damageProbability", EquipmentInfoGetProperty,
                     kEquipmentInfo_damageProbability),
    OOJS_PROPERTY_RO("description", EquipmentInfoGetProperty,
                     kEquipmentInfo_description),
    OOJS_PROPERTY_RW("displayColor", EquipmentInfoGetProperty,
                     EquipmentInfoSetProperty, kEquipmentInfo_displayColor),
    OOJS_PROPERTY_RW("effectiveTechLevel", EquipmentInfoGetProperty,
                     EquipmentInfoSetProperty,
                     kEquipmentInfo_effectiveTechLevel),
    OOJS_PROPERTY_RO("equipmentKey", EquipmentInfoGetProperty,
                     kEquipmentInfo_equipmentKey),
    OOJS_PROPERTY_RO("fastAffinityDefensive", EquipmentInfoGetProperty,
                     kEquipmentInfo_fastAffinityDefensive),
    OOJS_PROPERTY_RO("fastAffinityOffensive", EquipmentInfoGetProperty,
                     kEquipmentInfo_fastAffinityOffensive),
    OOJS_PROPERTY_RO("defaultActivateKey", EquipmentInfoGetProperty,
                     kEquipmentInfo_defaultActivateKey),
    OOJS_PROPERTY_RO("defaultModeKey", EquipmentInfoGetProperty,
                     kEquipmentInfo_defaultModeKey),
    OOJS_PROPERTY_RO("incompatibleEquipment", EquipmentInfoGetProperty,
                     kEquipmentInfo_incompatibleEquipment),
    OOJS_PROPERTY_RO("installationTime", EquipmentInfoGetProperty,
                     kEquipmentInfo_installationTime),
    OOJS_PROPERTY_RO("isAvailableToAll", EquipmentInfoGetProperty,
                     kEquipmentInfo_isAvailableToAll),
    OOJS_PROPERTY_RO("isAvailableToNPCs", EquipmentInfoGetProperty,
                     kEquipmentInfo_isAvailableToNPCs),
    OOJS_PROPERTY_RO("isAvailableToPlayer", EquipmentInfoGetProperty,
                     kEquipmentInfo_isAvailableToPlayer),
    OOJS_PROPERTY_RO("isExternalStore", EquipmentInfoGetProperty,
                     kEquipmentInfo_isExternalStore),
    OOJS_PROPERTY_RO("isPortableBetweenShips", EquipmentInfoGetProperty,
                     kEquipmentInfo_isPortableBetweenShips),
    OOJS_PROPERTY_RO("isVisible", EquipmentInfoGetProperty,
                     kEquipmentInfo_isVisible),
    OOJS_PROPERTY_RO("name", EquipmentInfoGetProperty, kEquipmentInfo_name),
    OOJS_PROPERTY_RO("price", EquipmentInfoGetProperty, kEquipmentInfo_price),
    OOJS_PROPERTY_RO("provides", EquipmentInfoGetProperty,
                     kEquipmentInfo_provides),
    OOJS_PROPERTY_RO("repairTime", EquipmentInfoGetProperty,
                     kEquipmentInfo_repairTime),
    OOJS_PROPERTY_RO("requiredCargoSpace", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiredCargoSpace),
    OOJS_PROPERTY_RO("requiresAnyEquipment", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresAnyEquipment),
    OOJS_PROPERTY_RO("requiresCleanLegalRecord", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresCleanLegalRecord),
    OOJS_PROPERTY_RO("requiresEmptyPylon", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresEmptyPylon),
    OOJS_PROPERTY_RO("requiresEquipment", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresEquipment),
    OOJS_PROPERTY_RO("requiresFreePassengerBerth", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresFreePassengerBerth),
    OOJS_PROPERTY_RO("requiresFullFuel", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresFullFuel),
    OOJS_PROPERTY_RO("requiresMountedPylon", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresMountedPylon),
    OOJS_PROPERTY_RO("requiresNonCleanLegalRecord", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresNonCleanLegalRecord),
    OOJS_PROPERTY_RO("requiresNonFullFuel", EquipmentInfoGetProperty,
                     kEquipmentInfo_requiresNonFullFuel),
    OOJS_PROPERTY_RO("scriptInfo", EquipmentInfoGetProperty,
                     kEquipmentInfo_scriptInfo),
    OOJS_PROPERTY_RO("scriptName", EquipmentInfoGetProperty,
                     kEquipmentInfo_scriptName),
    OOJS_PROPERTY_RO("techLevel", EquipmentInfoGetProperty,
                     kEquipmentInfo_techLevel),
    OOJS_PROPERTY_RO("weaponInfo", EquipmentInfoGetProperty,
                     kEquipmentInfo_weaponInfo),
};

static const JSCFunctionListEntry sEquipmentInfoMethods[] = {
    // JS name, min args, function
    JS_CFUNC_DEF("toString", 0, EquipmentInfoToString),
};

static const JSCFunctionListEntry sEquipmentInfoStaticMethods[] = {
    // Static property
    OOJS_PROPERTY_RO("allEquipment", EquipmentInfoGetAllEqipment, 0),
    // JS name, min args, function
    JS_CFUNC_DEF("infoForKey", 0, EquipmentInfoStaticInfoForKey),
};

namespace {
// DEFINE_JS_OBJECT_GETTER for the C++ type the slot holds (null for the
// prototype).
bool JSEquipmentInfoGetEquipmentType(JSContext* context, JSValueConst inObject,
                                     OOEquipmentType** outObject) {
  return OOJSGetCxxPrivate(context, inObject, sEquipmentInfoClassID, outObject);
}

// OOJSBasicPrivateObjectConverter for the C++ type the slot holds: the type
// itself as an Object node, for the callers of cxx_OOJSPListFromJSValue (null
// for the prototype).
oo::PList EquipmentInfoConverter(JSContext* /*context*/, JSValueConst object) {
  OOEquipmentType* type =
      static_cast<OOEquipmentType*>(static_cast<oo::RefCounted*>(
          JS_GetOpaque(object, sEquipmentInfoClassID)));
  return OOEquipmentTypeObjectNode(type);
}
}  // namespace

// *** Public ***

void InitOOJSEquipmentInfo(JSContext* context, JSValueConst global) {
  OOJSRegisterClass(&sEquipmentInfoClassID, &sEquipmentInfoClass);
  OOJSInitClass(context, global, sEquipmentInfoClassID, JS_UNDEFINED,
                OOJSUnconstructableConstruct, 0, sEquipmentInfoProperties,
                OOJS_COUNT(sEquipmentInfoProperties), sEquipmentInfoMethods,
                OOJS_COUNT(sEquipmentInfoMethods), sEquipmentInfoStaticMethods,
                OOJS_COUNT(sEquipmentInfoStaticMethods));

  OOJSRegisterObjectConverter(sEquipmentInfoClassID, EquipmentInfoConverter);
}

OOEquipmentType* JSValueToEquipmentType(JSContext* context,
                                        JSValueConst value) {
  OOJS_PROFILE_ENTER

  if (JS_IsObject(value)) {
    if (JS_GetClassID(value) == sEquipmentInfoClassID) {
      return static_cast<OOEquipmentType*>(
          static_cast<oo::RefCounted*>(JS_GetOpaque(
              value, sEquipmentInfoClassID)));  // borrowed: the slot holds it
    }
  }

  std::optional<std::string> string = cxx_OOStringFromJSValue(context, value);
  if (string.has_value())
    return OOEquipmentType::equipmentTypeWithIdentifier(*string)
        .get();  // borrowed: the registry holds it
  return nullptr;

  OOJS_PROFILE_EXIT
}

std::optional<std::string> JSValueToEquipmentKey(JSContext* context,
                                                 JSValueConst value) {
  return Ask(JSValueToEquipmentType(context, value),
             &OOEquipmentType::identifier);
}

std::optional<std::string> JSValueToEquipmentKeyRelaxed(JSContext* context,
                                                        JSValueConst value,
                                                        bool* outExists) {
  OOJS_PROFILE_ENTER

  std::optional<std::string> result;
  bool exists = false;
  const oo::PList plistValue = cxx_OOJSPListFromJSValue(context, value);

  if (OOEquipmentType* typeValue = OOEquipmentTypeInObjectNode(plistValue)) {
    result = typeValue->identifier();
    exists = true;
  } else if (const std::string* stringValue = plistValue.getIf<std::string>()) {
    /*	To enforce deliberate backwards incompatibility, reject strings
            ending with _DAMAGED unless someone actually named an equip that
            way.
     */
    exists =
        OOEquipmentType::equipmentTypeWithIdentifier(*stringValue) != nullptr;
    std::string string = *stringValue;
    if (exists || !oo::str::hasSuffix(string, "_DAMAGED")) {
      result = string;
    }
  }

  if (outExists != nullptr) *outExists = exists;
  return result;

  OOJS_PROFILE_EXIT
}

// *** Implementation stuff ***

static JSValue EquipmentInfoGetProperty(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  oo::PList result;  // null maps to null
  NSUInteger inst_time;

  OOEquipmentType* type = nullptr;  // null for the prototype: see Ask()
  if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &type)))
    return OOJSNativeFailure(context);

  switch (magic) {
    case kEquipmentInfo_equipmentKey:
      result = StringOrNull(Ask(type, &OOEquipmentType::identifier));
      break;

    case kEquipmentInfo_name:
      result = StringOrNull(Ask(type, &OOEquipmentType::name));
      break;

    case kEquipmentInfo_calculatedPrice:
      if (Ask(type, &OOEquipmentType::identifier) == "EQ_FUEL") {
        PlayerEntity* player =
            OOPlayerForScripting();  // fuelChargeRate qualified: the final
                                     // overrider, so the binding test stands in
                                     // for it
        return JS_NewNumber(
            context,
            (PLAYER_MAX_FUEL - (player != nullptr ? player->getFuel() : 0)) *
                Ask(type, &OOEquipmentType::price) *
                (player != nullptr ? player->PlayerEntity::fuelChargeRate()
                                   : 0.0f));
      } else if (Ask(type, &OOEquipmentType::identifier) == "EQ_RENOVATION") {
        PlayerEntity* player = OOPlayerForScripting();
        return JS_NewNumber(
            context,
            (player != nullptr ? player->PlayerEntity::renovationCosts()
                               : 0));  // qualified: the final overrider, so the
                                       // binding test stands in for it
      } else {
        PlayerEntity* player = OOPlayerForScripting();
        return JS_NewNumber(
            context, (Ask(type, &OOEquipmentType::identifier).has_value()
                          ? (player != nullptr
                                 ? player->adjustPriceByScriptForEqKey(
                                       *Ask(type, &OOEquipmentType::identifier),
                                       Ask(type, &OOEquipmentType::price))
                                 : 0)
                          : Ask(type, &OOEquipmentType::price)));
      }
    case kEquipmentInfo_canCarryMultiple:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::canCarryMultiple));

    case kEquipmentInfo_canBeDamaged:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::canBeDamaged));

    case kEquipmentInfo_description:
      result = StringOrNull(Ask(type, &OOEquipmentType::descriptiveText));
      break;

    case kEquipmentInfo_damageProbability:
      return JS_NewNumber(context,
                          Ask(type, &OOEquipmentType::damageProbability));

    case kEquipmentInfo_displayColor:
      result = NormalizedColorComponents(
          Ask(type, &OOEquipmentType::displayColor).get());
      break;

    case kEquipmentInfo_fastAffinityDefensive:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::fastAffinityDefensive));

    case kEquipmentInfo_fastAffinityOffensive:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::fastAffinityOffensive));

    case kEquipmentInfo_defaultActivateKey:
      result = Ask(type, &OOEquipmentType::defaultActivateKey);
      break;

    case kEquipmentInfo_defaultModeKey:
      result = Ask(type, &OOEquipmentType::defaultModeKey);
      break;

    case kEquipmentInfo_techLevel:
      return JS_NewInt32(context,
                         (int32_t)Ask(type, &OOEquipmentType::techLevel));

    case kEquipmentInfo_effectiveTechLevel:
      return JS_NewInt32(
          context, (int32_t)Ask(type, &OOEquipmentType::effectiveTechLevel));

    case kEquipmentInfo_price:
      return JS_NewNumber(context, Ask(type, &OOEquipmentType::price));

    case kEquipmentInfo_provides: {
      const std::vector<std::string> provides =
          Ask(type, &OOEquipmentType::providesForScripting);
      result = oo::PList(oo::PList::Array(provides.begin(), provides.end()));
    } break;

    case kEquipmentInfo_installationTime:
      inst_time = Ask(type, &OOEquipmentType::installTime);
      if (inst_time == 0) {
        inst_time = Ask(type, &OOEquipmentType::price) + 600;
      }
      return JS_NewInt32(context, (int32_t)inst_time);

    case kEquipmentInfo_isAvailableToAll:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isAvailableToAll));

    case kEquipmentInfo_isAvailableToNPCs:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isAvailableToNPCs));

    case kEquipmentInfo_isAvailableToPlayer:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::isAvailableToPlayer));

    case kEquipmentInfo_repairTime:
      return JS_NewInt32(context,
                         (int32_t)Ask(type, &OOEquipmentType::repairTime));

    case kEquipmentInfo_requiresEmptyPylon:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresEmptyPylon));

    case kEquipmentInfo_requiresMountedPylon:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::requiresMountedPylon));

    case kEquipmentInfo_requiresCleanLegalRecord:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::requiresCleanLegalRecord));

    case kEquipmentInfo_requiresNonCleanLegalRecord:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::requiresNonCleanLegalRecord));

    case kEquipmentInfo_requiresFreePassengerBerth:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::requiresFreePassengerBerth));

    case kEquipmentInfo_requiresFullFuel:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::requiresFullFuel));

    case kEquipmentInfo_requiresNonFullFuel:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::requiresNonFullFuel));

    case kEquipmentInfo_isExternalStore:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isMissileOrMine));

    case kEquipmentInfo_isPortableBetweenShips:
      return OOJSValueFromBOOL(
          Ask(type, &OOEquipmentType::isPortableBetweenShips));

    case kEquipmentInfo_isVisible:
      return OOJSValueFromBOOL(Ask(type, &OOEquipmentType::isVisible));

    case kEquipmentInfo_requiredCargoSpace:
      return JS_NewInt32(
          context, (int32_t)Ask(type, &OOEquipmentType::requiredCargoSpace));

    case kEquipmentInfo_requiresEquipment:
      result = KeyArrayOrNull(Ask(type, &OOEquipmentType::requiresEquipment));
      break;

    case kEquipmentInfo_requiresAnyEquipment:
      result =
          KeyArrayOrNull(Ask(type, &OOEquipmentType::requiresAnyEquipment));
      break;

    case kEquipmentInfo_incompatibleEquipment:
      result =
          KeyArrayOrNull(Ask(type, &OOEquipmentType::incompatibleEquipment));
      break;

    case kEquipmentInfo_scriptInfo: {
      const oo::PList info = Ask(type, &OOEquipmentType::scriptInfo);
      result = info.isNull() ? oo::PList(oo::PList::Dict{})
                             : info;  // empty rather than null
    } break;

    case kEquipmentInfo_scriptName:
      result = oo::PList(
          Ask(type, &OOEquipmentType::scriptName).value_or(std::string()));
      break;

    case kEquipmentInfo_weaponInfo:
      result = Ask(type, &OOEquipmentType::weaponInfo);
      if (result.isNull())
        result = oo::PList(oo::PList::Dict{});  // empty rather than null
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sEquipmentInfoProperties,
                                    OOJS_COUNT(sEquipmentInfoProperties));
      return OOJSNativeFailure(context);
  }

  return OOJSValueFromPList(context, result);

  OOJS_NATIVE_EXIT
}

static JSValue EquipmentInfoSetProperty(OOJS_SETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  int32_t iValue;
  oo::Ref<OOColor> colorForScript;

  OOEquipmentType* type = nullptr;  // null for the prototype: see Ask()
  if (EXPECT_NOT(!JSEquipmentInfoGetEquipmentType(context, thisObj, &type)))
    return OOJSNativeFailure(context);

  switch (magic) {
    case kEquipmentInfo_displayColor:
      colorForScript = OOColor::colorWithDescription(
          cxx_OOJSPListFromJSValue(context, value));
      if (colorForScript != nullptr || JS_IsNull(value)) {
        if (type != nullptr)
          type->setDisplayColor(
              colorForScript.get());  // (a message to nil did nothing)
        return JS_UNDEFINED;
      }
      break;
    case kEquipmentInfo_effectiveTechLevel:
      cxx_OOStandardsDeprecated(oo::str::format(
          "TL99 for variable tech level is deprecated for %s",
          Ask(type, &OOEquipmentType::identifier).value_or("(null)").c_str()));
      if (!OOEnforceStandards() &&
          Ask(type, &OOEquipmentType::techLevel) == kOOVariableTechLevel) {
        if (JS_IsNull(value)) {
          // reset mission variable
          if (PlayerEntity* player = OOPlayerForScripting())
            player->setMissionVariable(
                oo::PList(),
                "mission_TL_FOR_" +
                    Ask(type, &OOEquipmentType::identifier).value_or(""));
          return JS_UNDEFINED;
        }
        if (OOJSValueToInt32(context, value, &iValue)) {
          if (iValue < 0) iValue = 0;
          if (15 < iValue && iValue != kOOVariableTechLevel) iValue = 15;
          if (PlayerEntity* player = OOPlayerForScripting())
            player->setMissionVariable(
                oo::PList(oo::str::format("%u", iValue)),
                "mission_TL_FOR_" +
                    Ask(type, &OOEquipmentType::identifier).value_or(""));
          return JS_UNDEFINED;
        }
      } else {
        cxx_OOJSReportWarning(
            context,
            "Cannot modify effective tech level for %s, because its base tech "
            "level is not 99.",
            Ask(type, &OOEquipmentType::identifier).value_or("(null)").c_str());
        return JS_UNDEFINED;
      }
      break;

    default:
      OOJSReportBadPropertySelector(context, thisObj, magic,
                                    sEquipmentInfoProperties,
                                    OOJS_COUNT(sEquipmentInfoProperties));
      return OOJSNativeFailure(context);
  }

  OOJSReportBadPropertyValue(context, thisObj, magic, sEquipmentInfoProperties,
                             OOJS_COUNT(sEquipmentInfoProperties), value);
  return OOJSNativeFailure(context);

  OOJS_NATIVE_EXIT
}

static JSValue EquipmentInfoGetAllEqipment(OOJS_GETTER_ARGS) {
  OOJS_NATIVE_ENTER(context)

  return OOJSValueFromPList(context, OOEquipmentTypeObjectNodes(
                                         OOEquipmentType::allEquipmentTypes()));

  OOJS_NATIVE_EXIT
}

// The JS glue of OOEquipmentType (OOJSPrivateObject), which the engine reaches
// through the slot's C++ object or an Object node that holds the type.

/*	As with SpiderMonkey, the JS object retains the equipment type, and
        _jsSelf is a weak (uncounted) reference to the JS object, cleared by
        clearJSSelf() when the JS object is finalized.
*/
JSValue OOEquipmentType::jsValueInContext(JSContext* context) {
  if (!JS_IsObject(_jsSelf)) {
    JSValue newSelf = JS_NewObjectClass(context, (int)sEquipmentInfoClassID);
    if (JS_IsException(newSelf)) {
      JS_FreeValue(context, JS_GetException(context));
      return JS_NULL;
    }
    if (!OOJSSetCxxPrivate(newSelf, this)) {
      JS_FreeValue(context, newSelf);
      return JS_NULL;
    }

    // Weak: the caller gets the only reference.
    _jsSelf = newSelf;
    return newSelf;
  }

  return JS_DupValue(context, _jsSelf);
}

void OOEquipmentType::clearJSSelf(JSValueConst selfVal) {
  if (JS_IsObject(_jsSelf) &&
      JS_VALUE_GET_PTR(_jsSelf) == JS_VALUE_GET_PTR(selfVal))
    _jsSelf = JS_UNDEFINED;
}

// The JS class name and the components.
std::optional<std::string> OOEquipmentType::jsDescription() {
  const std::optional<std::string> components = descriptionComponents();
  const std::string name =
      OOJSEquipmentInfoJSClassName().value_or("EquipmentInfo");
  if (components.has_value())
    return oo::str::format("[%s %s]", name.c_str(), components->c_str());
  return oo::str::format("[object %s]", name.c_str());
}

std::optional<std::string> OOJSEquipmentInfoJSClassName(void) {
  return std::string("EquipmentInfo");
}

// *** Static methods ***

// infoForKey(key : String): EquipmentInfo
static JSValue EquipmentInfoStaticInfoForKey(OOJS_NATIVE_ARGS) {
  OOJS_NATIVE_ENTER(context)

  std::optional<std::string> key;

  if (argc > 0) key = cxx_OOStringFromJSValue(context, OOJS_ARGV[0]);
  if (!key.has_value()) {
    cxx_OOJSReportBadArguments(context, "EquipmentInfo", "infoForKey",
                               MIN(argc, 1), OOJS_ARGV, std::nullopt, "string");
    return OOJSNativeFailure(context);
  }

  OOJS_RETURN(OOJSValueFromCxxObject(
      context, OOEquipmentType::equipmentTypeWithIdentifier(*key).get()));

  OOJS_NATIVE_EXIT
}

// toString(): the C++ type's jsDescription().
static JSValue EquipmentInfoToString(OOJS_NATIVE_ARGS) {
  return OOJSCxxObjectWrapperToString(context, OOJS_THIS,
                                      sEquipmentInfoClassID);
}
