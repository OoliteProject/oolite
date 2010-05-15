/*

OOConstToString.h

Convert various sets of integer constants to strings.
To consider: replacing the integer constants with string constants.

This has grown beyond "const-to-string" at this point.

Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import <Foundation/Foundation.h>
#import "OOFunctionAttributes.h"
#import "OOTypes.h"


NSString *EntityStatusToString(OOEntityStatus status) CONST_FUNC;
OOEntityStatus StringToEntityStatus(NSString *string) PURE_FUNC;

NSString *ScanClassToString(OOScanClass scanClass) CONST_FUNC;
OOScanClass StringToScanClass(NSString *string) PURE_FUNC;

#ifdef OO_BRAIN_AI
NSString *InstinctToString(OOInstinctID instinct) CONST_FUNC;
OOInstinctID StringToInstinct(NSString *string) PURE_FUNC;
#endif

NSString *BehaviourToString(OOBehaviour behaviour) CONST_FUNC;

NSString *GovernmentToString(OOGovernmentID government);

NSString *EconomyToString(OOEconomyID economy);

NSString *JSTypeToString(int /* JSType */ type) CONST_FUNC;

NSString *WeaponTypeToString(OOWeaponType weapon) CONST_FUNC;
OOWeaponType StringToWeaponType(NSString *string) PURE_FUNC;

// Weapon strings prefixed with EQ_, used in shipyard.plist.
NSString *WeaponTypeToEquipmentString(OOWeaponType weapon) CONST_FUNC;
OOWeaponType EquipmentStringToWeaponTypeSloppy(NSString *string) PURE_FUNC;	// Uses suffix match for backwards compatibility.
OOWeaponType EquipmentStringToWeaponTypeStrict(NSString *string) PURE_FUNC;

NSString *CargoTypeToString(OOCargoType cargo) CONST_FUNC;
OOCargoType StringToCargoType(NSString *string) PURE_FUNC;

//NSString *CommodityTypeToOldString(OOCommodityType commodity) CONST_FUNC; // returns the old commodity identifier
NSString *CommodityTypeToString(OOCommodityType commodity) CONST_FUNC;	// returns the commodity identifier
OOCommodityType StringToCommodityType(NSString *string) PURE_FUNC;		// needs commodity identifier

NSString *EnergyUnitTypeToString(OOEnergyUnitType unit) CONST_FUNC;
OOEnergyUnitType StringToEnergyUnitType(NSString *string) PURE_FUNC;

NSString *GUIScreenIDToString(OOGUIScreenID screen) CONST_FUNC;
OOEnergyUnitType StringToGUIScreenID(NSString *string) PURE_FUNC;

NSString *KillCountToRatingString(unsigned kills) CONST_FUNC;
NSString *KillCountToRatingAndKillString(unsigned kills) CONST_FUNC;
NSString *LegalStatusToString(int legalStatus) CONST_FUNC;
NSString *AlertConditionToString(OOAlertCondition alertCondition) CONST_FUNC;

// Localized shader mode strings.
NSString *ShaderSettingToDisplayString(OOShaderSetting setting) CONST_FUNC;

// Programmer-readable shader mode strings.
NSString *ShaderSettingToString(OOShaderSetting setting) CONST_FUNC;
OOShaderSetting StringToShaderSetting(NSString *string) PURE_FUNC;

NSString *CommodityDisplayNameForSymbolicName(NSString *symbolicName);
NSString *CommodityDisplayNameForCommodityArray(NSArray *commodityDefinition);

NSString *DisplayStringForMassUnit(OOMassUnit unit);
NSString *DisplayStringForMassUnitForCommodity(OOCargoType commodity);

OOGalacticHyperspaceBehaviour StringToGalacticHyperspaceBehaviour(NSString *string) PURE_FUNC;
NSString *GalacticHyperspaceBehaviourToString(OOGalacticHyperspaceBehaviour behaviour) CONST_FUNC;

NSString *CompassModeToString(OOCompassMode mode);
OOCompassMode StringToCompassMode(NSString *string);

NSString *RouteTypeToString(OORouteType routeType);
OORouteType StringToRouteType(NSString *string);

#if DOCKING_CLEARANCE_ENABLED
NSString *DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus) PURE_FUNC;
#endif
