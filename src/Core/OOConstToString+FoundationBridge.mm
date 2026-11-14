/*

OOConstToString+FoundationBridge.mm

TRANSITIONAL: see OOConstToString+FoundationBridge.h. Each function forwards to its cxx_
counterpart and converts at the boundary (oo::StdString in: nil arrives as "", which matches no
name, so the same default results; oo::NSStringFrom out).

*/

#import "OOConstToString.h" // declares the bridge functions at its end
#import "OOFoundationBridge.h"
#import "PlayerEntity.h" // Entity.h, ShipEntity.h, PlayerEntity.h declare the .tbl families' old forms
#import "Universe.h" // declares the government and economy names' old forms

NSString* CargoTypeToString(OOCargoType cargo)
{
    return oo::NSStringFrom(cxx_CargoTypeToString(cargo));
}

OOCargoType StringToCargoType(NSString* string)
{
    return cxx_StringToCargoType(oo::StdString(string));
}

NSString* EnergyUnitTypeToString(OOEnergyUnitType unit)
{
    return oo::NSStringFrom(cxx_EnergyUnitTypeToString(unit));
}

OOEnergyUnitType StringToEnergyUnitType(NSString* string)
{
    return cxx_StringToEnergyUnitType(oo::StdString(string));
}

NSString* RouteTypeToString(OORouteType routeType)
{
    return oo::NSStringFrom(cxx_RouteTypeToString(routeType));
}

OORouteType StringToRouteType(NSString* string)
{
    return cxx_StringToRouteType(oo::StdString(string));
}

NSString* DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus)
{
    return oo::NSStringFrom(cxx_DockingClearanceStatusToString(dockingClearanceStatus));
}

NSString* OOStringFromGraphicsDetail(OOGraphicsDetail detail)
{
    return oo::NSStringFrom(cxx_OOStringFromGraphicsDetail(detail));
}

OOGraphicsDetail OOGraphicsDetailFromString(NSString* string)
{
    return cxx_OOGraphicsDetailFromString(oo::StdString(string));
}

NSString* OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper)
{
    return oo::NSStringFrom(cxx_OOStringFromHDRToneMapper(toneMapper));
}

OOHDRToneMapper OOHDRToneMapperFromString(NSString* string)
{
    return cxx_OOHDRToneMapperFromString(oo::StdString(string));
}

NSString* OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper)
{
    return oo::NSStringFrom(cxx_OOStringFromSDRToneMapper(toneMapper));
}

OOSDRToneMapper OOSDRToneMapperFromString(NSString* string)
{
    return cxx_OOSDRToneMapperFromString(oo::StdString(string));
}

NSString* OOStringFromEntityStatus(OOEntityStatus value)
{
    return oo::NSStringFrom(cxx_OOStringFromEntityStatus(value));
}

NSString* OOStringFromBehaviour(OOBehaviour value)
{
    return oo::NSStringFrom(cxx_OOStringFromBehaviour(value));
}

NSString* OOStringFromCompassMode(OOCompassMode value)
{
    return oo::NSStringFrom(cxx_OOStringFromCompassMode(value));
}

NSString* OOStringFromLongRangeChartMode(OOLongRangeChartMode value)
{
    return oo::NSStringFrom(cxx_OOStringFromLongRangeChartMode(value));
}

NSString* OOStringFromGalacticHyperspaceBehaviour(OOGalacticHyperspaceBehaviour value)
{
    return oo::NSStringFrom(cxx_OOStringFromGalacticHyperspaceBehaviour(value));
}

NSString* OOStringFromGUIScreenID(OOGUIScreenID value)
{
    return oo::NSStringFrom(cxx_OOStringFromGUIScreenID(value));
}

NSString* OOStringFromScanClass(OOScanClass value)
{
    return oo::NSStringFrom(cxx_OOStringFromScanClass(value));
}

NSString* OOStringFromShipDamageType(OOShipDamageType value)
{
    return oo::NSStringFrom(cxx_OOStringFromShipDamageType(value));
}

NSString* OOStringFromLegalStatusReason(OOLegalStatusReason value)
{
    return oo::NSStringFrom(cxx_OOStringFromLegalStatusReason(value));
}

OOEntityStatus OOEntityStatusFromString(NSString* string)
{
    return cxx_OOEntityStatusFromString(oo::StdString(string));
}

OOCompassMode OOCompassModeFromString(NSString* string)
{
    return cxx_OOCompassModeFromString(oo::StdString(string));
}

OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromString(NSString* string)
{
    return cxx_OOGalacticHyperspaceBehaviourFromString(oo::StdString(string));
}

OOGUIScreenID OOGUIScreenIDFromString(NSString* string)
{
    return cxx_OOGUIScreenIDFromString(oo::StdString(string));
}

OOScanClass OOScanClassFromString(NSString* string)
{
    return cxx_OOScanClassFromString(oo::StdString(string));
}

OOLongRangeChartMode OOLongRangeChartModeFromString(NSString* string)
{
    return cxx_OOLongRangeChartModeFromString(oo::StdString(string));
}

NSString* OOStringFromWeaponType(OOWeaponType weapon)
{
    return oo::NSStringOrNil(cxx_OOStringFromWeaponType(weapon));
}

OOWeaponType OOWeaponTypeFromString(NSString* string)
{
    return cxx_OOWeaponTypeFromString(oo::StdString(string));
}

NSString* OOEquipmentIdentifierFromWeaponType(OOWeaponType weapon)
{
    return oo::NSStringOrNil(cxx_OOEquipmentIdentifierFromWeaponType(weapon));
}

OOWeaponType OOWeaponTypeFromEquipmentIdentifierSloppy(NSString* string)
{
    return cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(oo::StdString(string));
}

OOWeaponType OOWeaponTypeFromEquipmentIdentifierLegacy(NSString* string)
{
    return cxx_OOWeaponTypeFromEquipmentIdentifierLegacy(oo::StdString(string));
}

OOWeaponType OOWeaponTypeFromEquipmentIdentifierStrict(NSString* string)
{
    return cxx_OOWeaponTypeFromEquipmentIdentifierStrict(oo::StdString(string));
}

NSString* OODisplayStringFromGovernmentID(OOGovernmentID government)
{
    return oo::NSStringOrNil(cxx_OODisplayStringFromGovernmentID(government));
}

NSString* OODisplayStringFromEconomyID(OOEconomyID economy)
{
    return oo::NSStringOrNil(cxx_OODisplayStringFromEconomyID(economy));
}

NSString* OODisplayRatingStringFromKillCount(unsigned kills)
{
    return oo::NSStringOrNil(cxx_OODisplayRatingStringFromKillCount(kills));
}

NSString* KillCountToRatingAndKillString(unsigned kills)
{
    return oo::NSStringFrom(cxx_KillCountToRatingAndKillString(kills));
}

NSString* OODisplayStringFromLegalStatus(int legalStatus)
{
    return oo::NSStringOrNil(cxx_OODisplayStringFromLegalStatus(legalStatus));
}

NSString* OODisplayStringFromAlertCondition(OOAlertCondition alertCondition)
{
    return oo::NSStringOrNil(cxx_OODisplayStringFromAlertCondition(alertCondition));
}

NSString* CommodityDisplayNameForSymbolicName(NSString* symbolicName)
{
    const std::string name = cxx_CommodityDisplayNameForSymbolicName(oo::StdString(symbolicName));
    // The old nil path: a nil name with no description came back as itself.
    if (symbolicName == nil && name.empty())
        return nil;
    return oo::NSStringFrom(name);
}

NSString* CommodityDisplayNameForCommodityArray(NSArray* commodityDefinition)
{
    const oo::PList definition = oo::PListFrom(commodityDefinition);
    const std::string name = cxx_CommodityDisplayNameForCommodityArray(definition);
    // The old nil path: no string or number name in the definition, and no description for it.
    const oo::PList* symbolicName = definition.at(MARKET_NAME);
    const bool hadName = symbolicName != nullptr && (symbolicName->isString() || symbolicName->isNumber());
    if (!hadName && name.empty())
        return nil;
    return oo::NSStringFrom(name);
}

NSString* DisplayStringForMassUnit(OOMassUnit unit)
{
    return oo::NSStringOrNil(cxx_DisplayStringForMassUnit(unit));
}

NSString* DisplayStringForMassUnitForCommodity(OOCommodityType commodity)
{
    return oo::NSStringOrNil(cxx_DisplayStringForMassUnitForCommodity(oo::StdString(commodity)));
}

OOShaderSetting OOShaderSettingFromString(NSString* string)
{
    return cxx_OOShaderSettingFromString(oo::StdString(string));
}

NSString* OOStringFromShaderSetting(OOShaderSetting setting)
{
    return oo::NSStringFrom(cxx_OOStringFromShaderSetting(setting));
}

NSString* OODisplayStringFromShaderSetting(OOShaderSetting setting)
{
    return oo::NSStringOrNil(cxx_OODisplayStringFromShaderSetting(setting));
}
