/*

OOConstToString.h

Convert various sets of integer constants to strings.
To consider: replacing the integer constants with string constants.

This has grown beyond "const-to-string" at this point.

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

NSString *InstinctToString(OOInstinctID instinct) CONST_FUNC;
OOInstinctID StringToInstinct(NSString *string) PURE_FUNC;

NSString *BehaviourToString(OOBehaviour behaviour) CONST_FUNC;

NSString *GovernmentToString(OOGovernmentID government);

NSString *EconomyToString(OOEconomyID economy);

NSString *JSTypeToString(int /* JSType */ type) CONST_FUNC;

NSString *WeaponTypeToString(OOWeaponType weapon) CONST_FUNC;
OOWeaponType StringToWeaponType(NSString *string) PURE_FUNC;

// Weapon strings prefixed with EQ_, used in shipyard.plist.
NSString *WeaponTypeToEquipmentString(OOWeaponType weapon) CONST_FUNC;
OOWeaponType EquipmentStringToWeaponType(NSString *string) PURE_FUNC;

NSString *CargoTypeToString(OOCargoType cargo) CONST_FUNC;
OOCargoType StringToCargoType(NSString *string) PURE_FUNC;

NSString *EnergyUnitTypeToString(OOEnergyUnitType unit) CONST_FUNC;
OOEnergyUnitType StringToEnergyUnitType(NSString *string) PURE_FUNC;

NSString *GUIScreenIDToString(OOGUIScreenID screen) CONST_FUNC;
OOEnergyUnitType StringToGUIScreenID(NSString *string) PURE_FUNC;

NSString *KillCountToRatingString(unsigned kills) CONST_FUNC;
NSString *KillCountToRatingAndKillString(unsigned kills) CONST_FUNC;
NSString *LegalStatusToString(int legalStatus) CONST_FUNC;
NSString *AlertConditionToString(OOAlertCondition alertCondition) CONST_FUNC;

NSString *ShaderSettingToDisplayString(OOShaderSetting setting) CONST_FUNC;

NSString *CommodityDisplayNameForSymbolicName(NSString *symbolicName);
NSString *CommodityDisplayNameForCommodityArray(NSArray *commodityDefinition);

NSString *DisplayStringForMassUnit(OOMassUnit unit);
NSString *DisplayStringForMassUnitForCommodity(OOCargoType commodity);
