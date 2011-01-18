/*

OOConstToString.h

Convert various sets of integer constants to strings.
To consider: replacing the integer constants with string constants.
 See also: OOConstToJSString.h.

This has grown beyond "const-to-string" at this point.

Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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


enum
{
	// Values used for unknown strings.
	kOOCargoTypeDefault			= CARGO_UNDEFINED,
	kOOCommodityTypeDefault		= COMMODITY_UNDEFINED,
	kOOEnergyUnitTypeDefault	= ENERGY_UNIT_NONE,
	kOOGUIScreenIDDefault		= GUI_SCREEN_MAIN,
	kOOGalacticHyperspaceBehaviourDefault = GALACTIC_HYPERSPACE_BEHAVIOUR_UNKNOWN,
	kOOShaderSettingDefault		= SHADERS_NOT_SUPPORTED,
	kOOCompassModeDefault		= COMPASS_MODE_BASIC,
	kOORouteTypeDefault			= OPTIMIZED_BY_JUMPS
};


/*

To avoid pulling in unnecessary headers, some functions defined in
OOConstToString.m are declared in the header with the appropriate type
declaration, in particular:

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

	OOInstinct.h:
	OOStringFromInstinctID()
	OOInstinctIDFromString()

*/


NSString *ViewIDToString(OOViewID viewID) CONST_FUNC;

NSString *GovernmentToString(OOGovernmentID government);

NSString *EconomyToString(OOEconomyID economy);

NSString *JSTypeToString(int /* JSType */ type) CONST_FUNC;

NSString *CargoTypeToString(OOCargoType cargo) CONST_FUNC;
OOCargoType StringToCargoType(NSString *string) PURE_FUNC;

//NSString *CommodityTypeToOldString(OOCommodityType commodity) CONST_FUNC; // returns the old commodity identifier
NSString *CommodityTypeToString(OOCommodityType commodity) CONST_FUNC;	// returns the commodity identifier
OOCommodityType StringToCommodityType(NSString *string) PURE_FUNC;		// needs commodity identifier

NSString *EnergyUnitTypeToString(OOEnergyUnitType unit) CONST_FUNC;
OOEnergyUnitType StringToEnergyUnitType(NSString *string) PURE_FUNC;

NSString *GUIScreenIDToString(OOGUIScreenID screen) CONST_FUNC;
OOGUIScreenID StringToGUIScreenID(NSString *string) PURE_FUNC;

NSString *KillCountToRatingString(unsigned kills) CONST_FUNC;
NSString *KillCountToRatingAndKillString(unsigned kills) CONST_FUNC;
NSString *LegalStatusToString(int legalStatus) CONST_FUNC;

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
