/*

OOConstToString.h

Convert various sets of integer constants to strings.
To consider: replacing the integer constants with string constants.
 See also: OOConstToJSString.h.

This has grown beyond "const-to-string" at this point.

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

#pragma once

#include "MyOpenGLView.h"
#include "OOFoundation.h"
#include "OOFunctionAttributes.h"
#include "OOTypes.h"

// Values used for unknown strings.
inline constexpr OOCargoType kOOCargoTypeDefault = OOCargoType::kNotCargo;
//	kOOCommodityTypeDefault		= COMMODITY_UNDEFINED,
inline constexpr OOEnergyUnitType kOOEnergyUnitTypeDefault =
    OOEnergyUnitType::kNone;
inline constexpr OORouteType kOORouteTypeDefault = OORouteType::kJumps;

/*

To avoid pulling in unnecessary headers, some functions defined in
OOConstToString.cpp are declared in the header with the appropriate type
declaration, each with its C++ (cxx_) form beside it, in particular:

        Entity.h:
        OOStringFromEntityStatus()
        OOEntityStatusFromString()
        OOStringFromScanClass()
        OOScanClassFromString()

        ShipEntity.h:
        OOStringFromBehaviour()
        OOEquipmentIdentifierFromWeaponType()
        OOWeaponTypeFromEquipmentIdentifierSloppy()
        OOWeaponTypeFromEquipmentIdentifierStrict()
        OOStringFromWeaponType()
        OOWeaponTypeFromString()
        OODisplayStringFromAlertCondition()

        PlayerEntity.h:
        OODisplayRatingStringFromKillCount()
        KillCountToRatingAndKillString()
        OODisplayStringFromLegalStatus()
        OOStringFromGUIScreenID()
        OOGUIScreenIDFromString()
        OOGalacticHyperspaceBehaviourFromString()
        OOStringFromGalacticHyperspaceBehaviour()

        Universe.h:
        OODisplayStringFromGovernmentID()
        OODisplayStringFromEconomyID()

*/

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "oofnd/PList.hpp"

// C++ forms: std::string results (never nil)
// and const std::string & parameters (the old nil arrived as "" and matched
// nothing: the same defaults).
std::string CargoTypeToString(OOCargoType cargo);
OOCargoType StringToCargoType(const std::string& string);
std::string EnergyUnitTypeToString(OOEnergyUnitType unit);
OOEnergyUnitType StringToEnergyUnitType(const std::string& string);
std::string RouteTypeToString(OORouteType routeType);
OORouteType StringToRouteType(const std::string& string);
std::string DockingClearanceStatusToString(
    OODockingClearanceStatus dockingClearanceStatus);
std::string OOStringFromGraphicsDetail(OOGraphicsDetail detail);
OOGraphicsDetail OOGraphicsDetailFromString(const std::string& string);
std::string OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper);
OOHDRToneMapper OOHDRToneMapperFromString(const std::string& string);
std::string OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper);
OOSDRToneMapper OOSDRToneMapperFromString(const std::string& string);

// The .tbl families whose types come from OOTypes.h; the
// others are declared beside their enums in Entity.h, ShipEntity.h and
// PlayerEntity.h.
std::string OOStringFromCompassMode(OOCompassMode mode);
OOCompassMode OOCompassModeFromString(const std::string& string);
std::string OOStringFromLongRangeChartMode(OOLongRangeChartMode chartMode);
OOLongRangeChartMode OOLongRangeChartModeFromString(const std::string& string);
std::string OOStringFromLegalStatusReason(OOLegalStatusReason reason);

// Commodity display strings. A commodity is named by its
// identifier string.
std::string CommodityDisplayNameForSymbolicName(
    const std::string& symbolicName);
std::string CommodityDisplayNameForCommodityArray(
    const oo::PList& commodityDefinition);  // an array
std::optional<std::string> DisplayStringForMassUnit(
    OOMassUnit unit);  // nullopt: no description (was nil)
std::optional<std::string> DisplayStringForMassUnitForCommodity(
    const std::string& commodity);

// Shader settings (OOShaderSetting is OOOpenGL.h's).
// Programmer-readable shader mode strings.
OOShaderSetting OOShaderSettingFromString(const std::string& string);
std::string OOStringFromShaderSetting(OOShaderSetting setting);
// Localized shader mode strings; nullopt: no description (was nil).
std::optional<std::string> OODisplayStringFromShaderSetting(
    OOShaderSetting setting);
