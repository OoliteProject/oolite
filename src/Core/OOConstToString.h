/*

OOConstToString.h

Convert various sets of integer constants to strings.
To consider: replacing the integer constants with string constants.
 See also: OOConstToJSString.h.

This has grown beyond "const-to-string" at this point.

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
	kOOCargoTypeDefault			= CARGO_NOT_CARGO,
	kOOCommodityTypeDefault		= COMMODITY_UNDEFINED,
	kOOEnergyUnitTypeDefault	= ENERGY_UNIT_NONE,
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
	
	OOOpenGL.h:
	OOShaderSettingFromString()
	OOStringFromShaderSetting()
	OODisplayStringFromShaderSetting()
	
*/

NSString *JSTypeToString(int /* JSType */ type) CONST_FUNC;

NSString *CargoTypeToString(OOCargoType cargo) CONST_FUNC;
OOCargoType StringToCargoType(NSString *string) PURE_FUNC;

NSString *CommodityTypeToString(OOCommodityType commodity) CONST_FUNC;	// returns the commodity identifier
OOCommodityType StringToCommodityType(NSString *string) PURE_FUNC;		// needs commodity identifier

NSString *EnergyUnitTypeToString(OOEnergyUnitType unit) CONST_FUNC;
OOEnergyUnitType StringToEnergyUnitType(NSString *string) PURE_FUNC;

NSString *CommodityDisplayNameForSymbolicName(NSString *symbolicName);
NSString *CommodityDisplayNameForCommodityArray(NSArray *commodityDefinition);

NSString *DisplayStringForMassUnit(OOMassUnit unit);
NSString *DisplayStringForMassUnitForCommodity(OOCommodityType commodity);

NSString *OOStringFromCompassMode(OOCompassMode mode);
OOCompassMode OOCompassModeFromString(NSString *string);

NSString *OOStringFromLegalStatusReason(OOLegalStatusReason reason);

NSString *RouteTypeToString(OORouteType routeType);
OORouteType StringToRouteType(NSString *string);

NSString *DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus) PURE_FUNC;
