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

std::string OOStringFromEntityStatus(OOEntityStatus value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromBehaviour(OOBehaviour value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("** BEHAVIOUR UNKNOWN **")
                      : std::string(name);
}

std::string OOStringFromCompassMode(OOCompassMode value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromLongRangeChartMode(OOLongRangeChartMode value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromGalacticHyperspaceBehaviour(
    OOGalacticHyperspaceBehaviour value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromGUIScreenID(OOGUIScreenID value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromScanClass(OOScanClass value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromShipDamageType(OOShipDamageType value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

std::string OOStringFromLegalStatusReason(OOLegalStatusReason value) {
  const std::string_view name = OOEnumName(value);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

OOEntityStatus OOEntityStatusFromString(const std::string& string) {
  return kOOEntityStatusTable.value(string).value_or(kOOEntityStatusDefault);
}

OOCompassMode OOCompassModeFromString(const std::string& string) {
  return kOOCompassModeTable.value(string).value_or(kOOCompassModeDefault);
}

OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromString(
    const std::string& string) {
  if (const std::optional<OOGalacticHyperspaceBehaviour> value =
          kOOGalacticHyperspaceBehaviourTable.value(string))
    return *value;

  // Transparently (but inefficiently) support american spelling. FIXME: remove
  // in EMMSTRAN.
  if (oo::str::hasPrefix(string, "BEHAVIOR_")) {
    return OOGalacticHyperspaceBehaviourFromString("BEHAVIOUR_" +
                                                   string.substr(9));
  }

  return kOOGalacticHyperspaceBehaviourDefault;
}

OOGUIScreenID OOGUIScreenIDFromString(const std::string& string) {
  return kOOGUIScreenIDTable.value(string).value_or(kOOGUIScreenIDDefault);
}

OOScanClass OOScanClassFromString(const std::string& string) {
  return kOOScanClassTable.value(string).value_or(kOOScanClassDefault);
}

OOLongRangeChartMode OOLongRangeChartModeFromString(const std::string& string) {
  return kOOLongRangeChartModeTable.value(string).value_or(
      kOOLongRangeChartModeDefault);
}

std::string RouteTypeToString(OORouteType routeType) {
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

std::optional<std::string> OODisplayStringFromGovernmentID(
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

std::optional<std::string> OODisplayStringFromEconomyID(OOEconomyID economy) {
  const oo::PList* stringsEntry = UNIVERSE->descriptions()->find("economy");
  const oo::PList strings =
      (stringsEntry != nullptr) ? *stringsEntry : oo::PList();
  if (strings.isArray() && economy < strings.count()) {
    if (const std::string* value = strings.at(economy)->getIf<std::string>())
      return *value;
  }

  return std::nullopt;
}

std::optional<std::string> OOStringFromWeaponType(OOWeaponType weapon) {
  if (weapon == nullptr) {
    return "EQ_WEAPON_NONE";
  } else {
    return weapon->identifier();
  }
}

OOWeaponType OOWeaponTypeFromString(const std::string& string) {
  return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}

std::optional<std::string> OOEquipmentIdentifierFromWeaponType(
    OOWeaponType weapon) {
  // No weapon: a message to nil answered a zeroed std::optional, no identifier.
  OOEquipmentType* type = weapon;
  return (type != nullptr) ? type->identifier() : std::nullopt;
}

OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(
    const std::string& string) {
  // The weapon type is borrowed: the registry holds it.
  std::shared_ptr<OOEquipmentType> w =
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
OOWeaponType OOWeaponTypeFromEquipmentIdentifierLegacy(
    const std::string& string) {
  if (oo::str::intValue(string) > 0) {
    switch (oo::str::intValue(string)) {
      case 2:
        return OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_PULSE_LASER");
      case 3:
        return OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_BEAM_LASER");
      case 4:
        return OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_MINING_LASER");
      case 5:
        return OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_MILITARY_LASER");
      case 10:
        return OOWeaponTypeFromEquipmentIdentifierSloppy(
            "EQ_WEAPON_THARGOID_LASER");
      default:
        return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
    }
  }
  return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}

OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(
    const std::string& string) {
  // there is no difference between the two any more
  return OOWeaponTypeFromEquipmentIdentifierSloppy(string);
}

std::string CargoTypeToString(OOCargoType cargo) {
  const std::string_view name = OOEnumName(cargo);
  return name.empty() ? std::string("Unknown cargo") : std::string(name);
}

OOCargoType StringToCargoType(const std::string& string) {
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

  return kOOCargoTypeDefault;
}

std::string EnergyUnitTypeToString(OOEnergyUnitType unit) {
  const std::string_view name = OOEnumName(unit);
  return name.empty() ? std::string("Unsupported energy unit")
                      : std::string(name);
}

OOEnergyUnitType StringToEnergyUnitType(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOEnergyUnitType, OOEnergyUnitType::kNone,
                        OOEnergyUnitType::kNormal, OOEnergyUnitType::kNaval,
                        OOEnergyUnitType::kNormalDamaged,
                        OOEnergyUnitType::kNavalDamaged>();
  if (const std::optional<OOEnergyUnitType> value = kNames.value(string))
    return *value;

  return kOOEnergyUnitTypeDefault;
}

std::optional<std::string> OODisplayRatingStringFromKillCount(unsigned kills) {
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

std::string KillCountToRatingAndKillString(unsigned kills) {
  // %@ of a nil rating printed "(null)".
  const std::optional<std::string> rating =
      OODisplayRatingStringFromKillCount(kills);
  return std::format("{}   ({})",
                     rating.has_value() ? rating->c_str() : "(null)", kills);
}

std::optional<std::string> OODisplayStringFromLegalStatus(int legalStatus) {
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

std::optional<std::string> OODisplayStringFromAlertCondition(
    OOAlertCondition alertCondition) {
  const oo::PList* conditionNamesEntry =
      UNIVERSE->descriptions()->find("condition");
  const oo::PList conditionNames =
      (conditionNamesEntry != nullptr) ? *conditionNamesEntry : oo::PList();
  return DescriptionStringAt(conditionNames, oo::ToUnderlying(alertCondition));
}

std::optional<std::string> OODisplayStringFromShaderSetting(
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

std::string OOStringFromShaderSetting(OOShaderSetting setting) {
  const std::string_view name = OOEnumName(setting);
  return name.empty() ? std::string("UNDEFINED") : std::string(name);
}

OOShaderSetting OOShaderSettingFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOShaderSetting, OOShaderSetting::kOff,
                        OOShaderSetting::kSimple, OOShaderSetting::kFull,
                        OOShaderSetting::kNotSupported>();
  if (const std::optional<OOShaderSetting> value = kNames.value(string))
    return *value;

  return kOOShaderSettingDefault;
}

std::string CommodityDisplayNameForSymbolicName(
    const std::string& symbolicName) {
  // -descriptionForKey: was NSStringOrNil of -descriptionForKey:, so
  // nullopt reads as before.
  const std::optional<std::string> ret =
      (UNIVERSE != nullptr
           ? UNIVERSE->descriptionForKey("commodity-name " +
                                         oo::str::lowercase(symbolicName))
           : std::optional<std::string>());
  return ret.has_value() ? *ret : symbolicName;
}

std::string CommodityDisplayNameForCommodityArray(
    const oo::PList& commodityDefinition) {
  return CommodityDisplayNameForSymbolicName(
      commodityDefinition.at<std::string>(MARKET_NAME));
}

std::optional<std::string> DisplayStringForMassUnit(OOMassUnit unit) {
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

std::optional<std::string> DisplayStringForMassUnitForCommodity(
    const std::string& commodity) {
  // No market: -massUnitForGood: sent to nil answered 0, OOMassUnit::kTons.
  OOCommodityMarket* market =
      (UNIVERSE != nullptr ? UNIVERSE->getCommodityMarket() : nullptr);
  return DisplayStringForMassUnit((market != nullptr)
                                      ? market->massUnitForGood(commodity)
                                      : OOMassUnit::kTons);
}

OORouteType StringToRouteType(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OORouteType, OORouteType::kNone, OORouteType::kJumps,
                        OORouteType::kTime>();
  if (const std::optional<OORouteType> value = kNames.value(string))
    return *value;

  return kOORouteTypeDefault;
}

std::string DockingClearanceStatusToString(
    OODockingClearanceStatus dockingClearanceStatus) {
  const std::string_view name = OOEnumName(dockingClearanceStatus);
  return name.empty() ? std::string("DOCKING_CLEARANCE_STATUS_UNKNOWN")
                      : std::string(name);
}

std::string OOStringFromGraphicsDetail(OOGraphicsDetail detail) {
  const std::string_view name = OOEnumName(detail);
  return name.empty() ? std::string("DETAIL_LEVEL_UNKNOWN") : std::string(name);
}

OOGraphicsDetail OOGraphicsDetailFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOGraphicsDetail, OOGraphicsDetail::kMinimum,
                        OOGraphicsDetail::kNormal, OOGraphicsDetail::kShaders,
                        OOGraphicsDetail::kExtras>();
  if (const std::optional<OOGraphicsDetail> value = kNames.value(string))
    return *value;

  return OOGraphicsDetail::kMinimum;
}

std::string OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper) {
  const std::string_view name = OOEnumName(toneMapper);
  return name.empty() ? std::string("OOHDR_TONEMAPPER_UNDEFINED")
                      : std::string(name);
}

OOHDRToneMapper OOHDRToneMapperFromString(const std::string& string) {
  static constexpr auto kNames =
      oo::MakeEnumTable<OOHDRToneMapper, OOHDRToneMapper::kNone,
                        OOHDRToneMapper::kAcesApprox, OOHDRToneMapper::kDice,
                        OOHDRToneMapper::kUchimura,
                        OOHDRToneMapper::kReinhard>();
  if (const std::optional<OOHDRToneMapper> value = kNames.value(string))
    return *value;

  return OOHDRToneMapper::kAcesApprox;
}

std::string OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper) {
  const std::string_view name = OOEnumName(toneMapper);
  return name.empty() ? std::string("OOSDR_TONEMAPPER_UNDEFINED")
                      : std::string(name);
}

OOSDRToneMapper OOSDRToneMapperFromString(const std::string& string) {
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
