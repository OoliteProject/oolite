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

#import "MyOpenGLView.h"
#import "OOFoundation.h"
#import "OOFunctionAttributes.h"
#import "OOTypes.h"

enum {
    // Values used for unknown strings.
    kOOCargoTypeDefault = CARGO_NOT_CARGO,
    //	kOOCommodityTypeDefault		= COMMODITY_UNDEFINED,
    kOOEnergyUnitTypeDefault = ENERGY_UNIT_NONE,
    kOORouteTypeDefault = OPTIMIZED_BY_JUMPS
};

/*

To avoid pulling in unnecessary headers, some functions defined in
OOConstToString.mm are declared in the header with the appropriate type
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

The Foundation-typed forms of the functions this header declares live in
OOConstToString+FoundationBridge.h (bead oo-nts1); those of the functions above
stay in the headers named until those headers' own sweeps. All of them are
defined in OOConstToString+FoundationBridge.mm, forwarding to the cxx_ forms.

*/

#ifdef __cplusplus
#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

// C++ forms (bead oo-nts1, chunk oo-3rb.160): std::string results (never nil) and const
// std::string & parameters (the old nil arrived as "" and matched nothing: the same defaults).
// The Foundation forms live in OOConstToString+FoundationBridge.h.
std::string cxx_CargoTypeToString(OOCargoType cargo);
OOCargoType cxx_StringToCargoType(const std::string& string);
std::string cxx_EnergyUnitTypeToString(OOEnergyUnitType unit);
OOEnergyUnitType cxx_StringToEnergyUnitType(const std::string& string);
std::string cxx_RouteTypeToString(OORouteType routeType);
OORouteType cxx_StringToRouteType(const std::string& string);
std::string cxx_DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus);
std::string cxx_OOStringFromGraphicsDetail(OOGraphicsDetail detail);
OOGraphicsDetail cxx_OOGraphicsDetailFromString(const std::string& string);
std::string cxx_OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper);
OOHDRToneMapper cxx_OOHDRToneMapperFromString(const std::string& string);
std::string cxx_OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper);
OOSDRToneMapper cxx_OOSDRToneMapperFromString(const std::string& string);

// The .tbl families whose types come from OOTypes.h (chunk oo-3rb.161); the others are declared
// beside their enums in Entity.h, ShipEntity.h and PlayerEntity.h.
std::string cxx_OOStringFromCompassMode(OOCompassMode mode);
OOCompassMode cxx_OOCompassModeFromString(const std::string& string);
std::string cxx_OOStringFromLongRangeChartMode(OOLongRangeChartMode chartMode);
OOLongRangeChartMode cxx_OOLongRangeChartModeFromString(const std::string& string);
std::string cxx_OOStringFromLegalStatusReason(OOLegalStatusReason reason);

// Commodity display strings (chunk oo-3rb.162). A commodity is named by its identifier string.
std::string cxx_CommodityDisplayNameForSymbolicName(const std::string& symbolicName);
std::string cxx_CommodityDisplayNameForCommodityArray(const oo::PList& commodityDefinition); // an array
std::optional<std::string> cxx_DisplayStringForMassUnit(OOMassUnit unit); // nullopt: no description (was nil)
std::optional<std::string> cxx_DisplayStringForMassUnitForCommodity(const std::string& commodity);

// Shader settings (OOShaderSetting is OOOpenGL.h's; chunk oo-3rb.163).
// Programmer-readable shader mode strings.
OOShaderSetting cxx_OOShaderSettingFromString(const std::string& string);
std::string cxx_OOStringFromShaderSetting(OOShaderSetting setting);
// Localized shader mode strings; nullopt: no description (was nil).
std::optional<std::string> cxx_OODisplayStringFromShaderSetting(OOShaderSetting setting);
#endif

/*	TRANSITIONAL (proposed ADR-0043, "Transitional bridges"): the Foundation-typed functions this
        header declared before bead oo-nts1 (chunks oo-3rb.160..163), forwarding to the cxx_ functions,
        so unmigrated callers compile unchanged. Callers move to the cxx_ forms in their own sweep beads.
*/
#import "OOConstToString+FoundationBridge.h"
