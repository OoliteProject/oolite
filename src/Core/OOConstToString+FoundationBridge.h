/*

OOConstToString+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-nts1, made by its chunk
oo-3rb.160, and chunks oo-3rb.161..163 move their own functions in). The Foundation-typed
functions OOConstToString.h declared before its sweep, with the same names, types and linkage,
forwarding to the cxx_ functions. It exists so that the callers compile unchanged; each caller
moves to the cxx_ forms in its own sweep bead. When `git grep` finds no caller of anything
declared here, the bridge bead deletes this file, OOConstToString+FoundationBridge.mm, its line in
Core/meson.build and the #import at the end of OOConstToString.h. Never add to it; never call it
from migrated code. oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Copyright (C) 2004-2013 Giles C Williams and contributors (OOConstToString.h)

*/

// Imported only from the end of OOConstToString.h (which declares everything used here); never
// import it directly, and never import OOConstToString.h from it (a cycle).
#ifndef OOCONSTTOSTRING_FOUNDATIONBRIDGE_H
#define OOCONSTTOSTRING_FOUNDATIONBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

NSString* CargoTypeToString(OOCargoType cargo) CONST_FUNC;
OOCargoType StringToCargoType(NSString* string) PURE_FUNC;
NSString* EnergyUnitTypeToString(OOEnergyUnitType unit) CONST_FUNC;
OOEnergyUnitType StringToEnergyUnitType(NSString* string) PURE_FUNC;
NSString* RouteTypeToString(OORouteType routeType);
OORouteType StringToRouteType(NSString* string);
NSString* DockingClearanceStatusToString(OODockingClearanceStatus dockingClearanceStatus) PURE_FUNC;
NSString* OOStringFromGraphicsDetail(OOGraphicsDetail detail);
OOGraphicsDetail OOGraphicsDetailFromString(NSString* string);
NSString* OOStringFromHDRToneMapper(OOHDRToneMapper toneMapper);
OOHDRToneMapper OOHDRToneMapperFromString(NSString* string);
NSString* OOStringFromSDRToneMapper(OOSDRToneMapper toneMapper);
OOSDRToneMapper OOSDRToneMapperFromString(NSString* string);

NSString* OOStringFromCompassMode(OOCompassMode mode);
OOCompassMode OOCompassModeFromString(NSString* string);

NSString* OOStringFromLongRangeChartMode(OOLongRangeChartMode chartMode);
OOLongRangeChartMode OOLongRangeChartModeFromString(NSString* string);

NSString* OOStringFromLegalStatusReason(OOLegalStatusReason reason);

NSString* CommodityDisplayNameForSymbolicName(NSString* symbolicName);
NSString* CommodityDisplayNameForCommodityArray(NSArray* commodityDefinition);

NSString* DisplayStringForMassUnit(OOMassUnit unit);
NSString* DisplayStringForMassUnitForCommodity(OOCommodityType commodity);

#ifdef __cplusplus
}
#endif

// Shader settings (OOShaderSetting is OOOpenGL.h's), with C++ linkage as when OOOpenGL.h declared them.
// Programmer-readable shader mode strings.
OOShaderSetting OOShaderSettingFromString(NSString* string);
NSString* OOStringFromShaderSetting(OOShaderSetting setting);
// Localized shader mode strings.
NSString* OODisplayStringFromShaderSetting(OOShaderSetting setting);

#endif // OOCONSTTOSTRING_FOUNDATIONBRIDGE_H
