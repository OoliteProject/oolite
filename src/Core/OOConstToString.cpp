/*

OOConstToString.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version );
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., ); Franklin Street, Fifth Floor, Boston,
MA );-);, USA.

*/

#include "OOConstToString.h"

#include <format>
#include <optional>
#include <string_view>

#include "OOCommodityMarket.h"
#include "OOEnumTable.h"
#include "OOEquipmentType.h"
#include "PlayerEntity.h"
#include "Universe.h"
#include "oofnd/String.hpp"

std::string cxx_OOStringFromEntityStatus(OOEntityStatus value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromBehaviour(OOBehaviour value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("** BEHAVIOUR UNKNOWN **")
                      : std::string(name);
}

std::string cxx_OOStringFromCompassMode(OOCompassMode value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromLongRangeChartMode(OOLongRangeChartMode value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromGalacticHyperspaceBehaviour(
    OOGalacticHyperspaceBehaviour value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromGUIScreenID(OOGUIScreenID value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromScanClass(OOScanClass value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromShipDamageType(OOShipDamageType value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string cxx_OOStringFromLegalStatusReason(OOLegalStatusReason value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

OOEntityStatus cxx_OOEntityStatusFromString(const std::string& string) {
  return kOOEntityStatusTable.value(string).value_or(kOOEntityStatusDefault);
}

OOCompassMode cxx_OOCompassModeFromString(const std::string& string) {
  return kOOCompassModeTable.value(string).value_or(kOOCompassModeDefault);
}

OOGalacticHyperspaceBehaviour cxx_OOGalacticHyperspaceBehaviourFromString(
    const std::string& string) {
  if (const std::optional<OOGalacticHyperspaceBehaviour> value =
          kOOGalacticHyperspaceBehaviourTable.value(string))
    return *value;

  // Transparently (but inefficiently) support american spelling. FIXME: remove
  // in EMMSTRAN.
  if (oo::str::hasPrefix(string, "BEHAVIOR_")) {
    return cxx_OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_" +
                                                       string.substr(9));
  }

  return kOOGalacticHyperspaceBehaviourDefault;
}

OOGUIScreenID cxx_OOGUIScreenIDFromString(const std::string& string) {
  return kOOGUIScreenIDTable.value(string).value_or(kOOGUIScreenIDDefault);
}

OOScanClass cxx_OOScanClassFromString(const std::string& string) {
  return kOOScanClassTable.value(string).value_or(kOOScanClassDefault);
}

OOLongRangeChartMode cxx_OOLongRangeChartModeFromString(
    const std::string& string) {
  return kOOLongRangeChartModeTable.value(string).value_or(
      kOOLongRangeChartModeDefault);
}

std::string cxx_RouteTypeToString(OORouteType routeType) {
  const std::string_view name = OOEnumName(routeType);
  return name.empty() ? std::string("** ROUTE TYPE UNKNOWN **")
                      : std::string(name);
}

namespace {
// PListView's string rule (OOCollectionExtractors' StringForObject): the
// element if it is a string, or a number's -stringValue; nullopt (was nil) for
// anything else or a missing element.
std::optional<std::string> DescriptionStringAt(const oo::PList& strings,
                                               std::size_t index) {
  const oo::PList* value = strings.at(index);
  if (value == nullptr || !(value->isString() || value->isNumber()))
    return std::nullopt;
  return strings.at<std::string>(index);
}
}  // namespace

std::optional<std::string> cxx_OODisplayStringFromGovernmentID(
    OOGovernmentID government) {
  // Only the one sub-array of the descriptions; a missing key reads as the null
  // PList PListFrom(nil) gave.
  const oo::PList* stringsEntry = UNIVERSE->descriptions()->find("government");
  const oo::PList strings =
      (stringsEntry != nullptr) ? *stringsEntry : oo::PList();
  if (strings.isArray() && government < strings.count()) {
    if (const std::string* value = strings.at(government)->getIf<std::string>())
      return *value;
  }

  return std::nullopt;
}

std::optional<std::string> cxx_OODisplayStringFromEconomyID(
    OOEconomyID economy) {
  const oo::PList* stringsEntry = UNIVERSE->descriptions()->find("economy");
  const oo::PList strings =
      (stringsEntry != nullptr) ? *stringsEntry : oo::PList();
  if (strings.isArray() && economy < strings.count()) {
    if (const std::string* value = strings.at(economy)->getIf<std::string>())
      return *value;
  }

  return std::nullopt;
}

std::optional<std::string> cxx_OOStringFromWeaponType(OOWeaponType weapon) {
  if (weapon == nullptr) {
    return "EQ_WEAPON_NONE";
  } else {
    return weapon->identifier();
  }
}

OOWeaponType cxx_OOWeaponTypeFromString(const std::string& string) {
  return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}

std::optional<std::string> cxx_OOEquipmentIdentifierFromWeaponType(
    OOWeaponType weapon) {
  // No weapon: a message to nil answered a zeroed std::optional, no identifier.
  OOEquipmentType* type = weapon;
  return (type != nullptr) ? type->identifier() : std::nullopt;
}

OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
    const std::string& string) {
  // The weapon type is borrowed: the registry holds it.
  oo::Ref<OOEquipmentType> w =
      OOEquipmentType::equipmentTypeWithIdentifier(string);
  if (w == nullptr) {
    if (!oo::str::hasPrefix(string, "EQ_")) {
      w = OOEquipmentType::equipmentTypeWithIdentifier("EQ_" + string);
      if (w != nullptr) {
        return w.get();
      }
    }
    return OOEquipmentType::equipmentTypeWithIdentifier("EQ_WEAPON_NONE").get();
  }
  return w.get();
}

/* Previous save games will have weapon types stored as ints to the
 * various weapon types */
OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(
    const std::string& string) {
  if (oo::str::intValue(string) > 0) {
    switch (oo::str::intValue(string)) {
      case 2:
        return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_PULSE_LASER");
      case 3:
        return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_BEAM_LASER");
      case 4:
        return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_MINING_LASER");
      case 5:
        return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_MILITARY_LASER");
      case 10:
        return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_THARGOID_LASER");
      default:
        return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
    }
  }
  return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}

OOWeaponType cxx_OOWeaponTypeFromEquipmentIdentifierStrict(
    const std::string& string) {
  // there is no difference between the two any more
  return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}

std::string cxx_CargoTypeToString(OOCargoType cargo) {
  const std::string_view name = OOEnumName(cargo);
  return name.empty() ? std::string("Unknown cargo") : std::string(name);
}

OOCargoType cxx_StringToCargoType(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOCargoType, OOCargoType::kNotCargo,
                        OOCargoType::kSlaves, OOCargoType::kAlloy,
                        OOCargoType::kMinerals, OOCargoType::kThargoid,
                        OOCargoType::kRandom, OOCargoType::kScriptedItem,
                        OOCargoType::kCharacter>();
  if (const std::optional<OOCargoType> value = kNames.value(string))
    return *value;

  // Backwards compatibility.
  if (string == "CARGO_CARRIED") return OOCargoType::kRandom;

  return (OOCargoType)kOOCargoTypeDefault;
}

std::string cxx_EnergyUnitTypeToString(OOEnergyUnitType unit) {
  const std::string_view name = OOEnumName(unit);
  return name.empty() ? std::string("Unsupported energy unit")
                      : std::string(name);
}

OOEnergyUnitType cxx_StringToEnergyUnitType(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOEnergyUnitType, OOEnergyUnitType::kNone,
                        OOEnergyUnitType::kNormal, OOEnergyUnitType::kNaval,
                        OOEnergyUnitType::kNormalDamaged,
                        OOEnergyUnitType::kNavalDamaged>();
  if (const std::optional<OOEnergyUnitType> value = kNames.value(string))
    return *value;

  return (OOEnergyUnitType)kOOEnergyUnitTypeDefault;
}

std::optional<std::string> cxx_OODisplayRatingStringFromKillCount(
    unsigned kills) {
  constexpr unsigned kRatingCount = 9;

  const unsigned killThresholds[kRatingCount - 1] = {
      0x0008, 0x0010, 0x0020, 0x0040, 0x0080, 0x0200, 0x0A00, 0x1900};
  unsigned i;

  const oo::PList* ratingNamesEntry = UNIVERSE->descriptions()->find("rating");
  const oo::PList ratingNames =
      (ratingNamesEntry != nullptr) ? *ratingNamesEntry : oo::PList();
  for (i = 0; i < kRatingCount - 1; ++i) {
    if (kills < killThresholds[i]) return DescriptionStringAt(ratingNames, i);
  }

  return DescriptionStringAt(ratingNames, kRatingCount - 1);
}

std::string cxx_KillCountToRatingAndKillString(unsigned kills) {
  // %@ of a nil rating printed "(null)".
  const std::optional<std::string> rating =
      cxx_OODisplayRatingStringFromKillCount(kills);
  return std::format("{}   ({})",
                     rating.has_value() ? rating->c_str() : "(null)", kills);
}

std::optional<std::string> cxx_OODisplayStringFromLegalStatus(int legalStatus) {
  constexpr unsigned kStatusCount = 3;

  const int statusThresholds[kStatusCount - 1] = {1, 51};
  unsigned i;

  const oo::PList* statusNamesEntry =
      UNIVERSE->descriptions()->find("legal_status");
  const oo::PList statusNames =
      (statusNamesEntry != nullptr) ? *statusNamesEntry : oo::PList();
  for (i = 0; i != kStatusCount - 1; ++i) {
    if (legalStatus < statusThresholds[i])
      return DescriptionStringAt(statusNames, i);
  }

  return DescriptionStringAt(statusNames, kStatusCount - 1);
}

std::optional<std::string> cxx_OODisplayStringFromAlertCondition(
    OOAlertCondition alertCondition) {
  const oo::PList* conditionNamesEntry =
      UNIVERSE->descriptions()->find("condition");
  const oo::PList conditionNames =
      (conditionNamesEntry != nullptr) ? *conditionNamesEntry : oo::PList();
  return DescriptionStringAt(conditionNames, oo::ToUnderlying(alertCondition));
}

std::optional<std::string> cxx_OODisplayStringFromShaderSetting(
    OOShaderSetting setting) {
  // DESC() is Universe's description lookup (not migrated yet), converted at
  // the call.
  switch (setting) {
    case OOShaderSetting::kNotSupported:
      return OO_DESC("shaderfx-not-available");
    case OOShaderSetting::kOff:
      return OO_DESC("shaderfx-off");
    case OOShaderSetting::kSimple:
      return OO_DESC("shaderfx-simple");
    case OOShaderSetting::kFull:
      return OO_DESC("shaderfx-full");
  }

  return "??";
}

std::string cxx_OOStringFromShaderSetting(OOShaderSetting setting) {
  const std::string_view name = OOEnumName(setting);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

OOShaderSetting cxx_OOShaderSettingFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOShaderSetting, OOShaderSetting::kOff,
                        OOShaderSetting::kSimple, OOShaderSetting::kFull,
                        OOShaderSetting::kNotSupported>();
  if (const std::optional<OOShaderSetting> value = kNames.value(string))
    return *value;

  return kOOShaderSettingDefault;
}

std::string cxx_CommodityDisplayNameForSymbolicName(
    const std::string& symbolicName) {
  // -descriptionForKey: was NSStringOrNil of -cxx_descriptionForKey:, so
  // nullopt reads as before.
  const std::optional<std::string> ret =
      (UNIVERSE != nullptr
           ? UNIVERSE->descriptionForKey("commodity-name " +
                                         oo::str::lowercase(symbolicName))
           : std::optional<std::string>());
  return ret.has_value() ? *ret : symbolicName;
}

std::string cxx_CommodityDisplayNameForCommodityArray(
    const oo::PList& commodityDefinition) {
  return cxx_CommodityDisplayNameForSymbolicName(
      commodityDefinition.at<std::string>(MARKET_NAME));
}

std::optional<std::string> cxx_DisplayStringForMassUnit(OOMassUnit unit) {
  // DESC() is Universe's description lookup (not migrated yet), converted at
  // the call.
  switch (unit) {
    case OOMassUnit::kTons:
      return OO_DESC("cargo-tons-symbol");
    case OOMassUnit::kKilograms:
      return OO_DESC("cargo-kilograms-symbol");
    case OOMassUnit::kGrams:
      return OO_DESC("cargo-grams-symbol");
    case OOMassUnit::kUnknown:
      break;
  }

  return "??";
}

std::optional<std::string> cxx_DisplayStringForMassUnitForCommodity(
    const std::string& commodity) {
  // No market: -massUnitForGood: sent to nil answered 0, OOMassUnit::kTons.
  OOCommodityMarket* market =
      (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);
  return cxx_DisplayStringForMassUnit((market != nullptr)
                                          ? market->massUnitForGood(commodity)
                                          : OOMassUnit::kTons);
}

OORouteType cxx_StringToRouteType(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OORouteType, OORouteType::kNone, OORouteType::kJumps,
                        OORouteType::kTime>();
  if (const std::optional<OORouteType> value = kNames.value(string))
    return *value;

  return (OORouteType)kOORouteTypeDefault;
}

std::string cxx_DockingClearanceStatusToString(
    OODockingClearanceStatus dockingClearanceStatus) {
  const std::string_view name = OOEnumName(dockingClearanceStatus);
  return name.empty() ? std::string("DOCKING_CLEARANCE_STATUS_UNKNOWN")
                      : std::string(name);
}

std::string cxx_OOStringFromGraphicsDetail(OOGraphicsDetail detail) {
  const std::string_view name = OOEnumName(detail);
  return name.empty() ? std::string("DETAIL_LEVEL_UNKNOWN") : std::string(name);
}

OOGraphicsDetail cxx_OOGraphicsDetailFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOGraphicsDetail, OOGraphicsDetail::kMinimum,
                        OOGraphicsDetail::kNormal, OOGraphicsDetail::kShaders,
                        OOGraphicsDetail::kExtras>();
  if (const std::optional<OOGraphicsDetail> value = kNames.value(string))
    return *value;

  return OOGraphicsDetail::kMinimum;
}

std::string cxx_OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper) {
  const std::string_view name = OOEnumName(toneMapper);
  return name.empty() ? std::string("OOHDR_TONEMAPPER_UNDEFINED")
                      : std::string(name);
}

OOHDRToneMapper cxx_OOHDRToneMapperFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOHDRToneMapper, OOHDRToneMapper::kNone,
                        OOHDRToneMapper::kAcesApprox, OOHDRToneMapper::kDice,
                        OOHDRToneMapper::kUchimura,
                        OOHDRToneMapper::kReinhard>();
  if (const std::optional<OOHDRToneMapper> value = kNames.value(string))
    return *value;

  return OOHDRToneMapper::kAcesApprox;
}

std::string cxx_OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper) {
  const std::string_view name = OOEnumName(toneMapper);
  return name.empty() ? std::string("OOSDR_TONEMAPPER_UNDEFINED")
                      : std::string(name);
}

OOSDRToneMapper cxx_OOSDRToneMapperFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOSDRToneMapper, OOSDRToneMapper::kNone,
                        OOSDRToneMapper::kAces, OOSDRToneMapper::kAgX,
                        OOSDRToneMapper::kHejlDawson, OOSDRToneMapper::kUC2,
                        OOSDRToneMapper::kUchimura,
                        OOSDRToneMapper::kReinhard>();
  if (const std::optional<OOSDRToneMapper> value = kNames.value(string))
    return *value;

  return OOSDRToneMapper::kAces;
}
