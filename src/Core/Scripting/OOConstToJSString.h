/*

OOConstToJSString.h

Convert various sets of integer constants to JavaScript strings and back again.
See also: OOConstToString.h.


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

/*	Plain includes (bead oo-9ht.64): this header and OOConstToJSString's translation unit are C++,
	not Objective-C. The script engine facade, OOINLINE, NSInteger/NSUInteger and the constant
	enumerations are all the inlines below need.
*/
#pragma once

#include "ooscript/JSEngine.hpp"
#include "OOFunctionAttributes.h"
#include "OOTypes.h"
#include "OOEntityEnums.h"


#ifdef __cplusplus
extern "C" {
#endif

void OOConstToJSStringInit(ooscript::Context context);
void OOConstToJSStringDestroy(void);

struct ConstTable;


// Private functions, don't use directly.
ooscript::String OOJSStringFromConstantPRIVATE(ooscript::Context context, NSInteger value, struct ConstTable *table);
NSUInteger OOConstantFromJSStringPRIVATE(ooscript::Context context, ooscript::String string, struct ConstTable *table, NSInteger defaultValue);
NSUInteger OOConstantFromJSValuePRIVATE(ooscript::Context context, ooscript::Value value, struct ConstTable *table, NSInteger defaultValue);

#ifdef __cplusplus
}
#endif


/*	ooscript::String OOJSStringFromEntityStatus(ooscript::Context, OOEntityStatus)
	ooscript::Value OOJSValueFromEntityStatus(ooscript::Context, OOEntityStatus)
	OOEntityStatus OOEntityStatusFromJSString(ooscript::Context, ooscript::String)
	OOEntityStatus OOEntityStatusFromJSValue(ooscript::Context, ooscript::Value)
	
	Convert between JavaScript strings and OOEntityStatus.
*/
OOINLINE ooscript::String OOJSStringFromEntityStatus(ooscript::Context context, OOEntityStatus value)
{
	extern struct ConstTable gOOEntityStatusConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOEntityStatusConstTable);
}


OOINLINE ooscript::Value OOJSValueFromEntityStatus(ooscript::Context context, OOEntityStatus value)
{
	return ooscript::stringValue(OOJSStringFromEntityStatus(context, value));
}


OOINLINE OOEntityStatus OOEntityStatusFromJSString(ooscript::Context context, ooscript::String string)
{
	extern struct ConstTable gOOEntityStatusConstTable;
	return (OOEntityStatus)OOConstantFromJSStringPRIVATE(context, string, &gOOEntityStatusConstTable, kOOEntityStatusDefault);
}


OOINLINE OOEntityStatus OOEntityStatusFromJSValue(ooscript::Context context, ooscript::Value value)
{
	extern struct ConstTable gOOEntityStatusConstTable;
	return (OOEntityStatus)OOConstantFromJSValuePRIVATE(context, value, &gOOEntityStatusConstTable, kOOEntityStatusDefault);
}


/*	ooscript::String OOJSStringFromScanClass(ooscript::Context, OOScanClass)
	ooscript::Value OOJSValueFromScanClass(ooscript::Context, OOScanClass)
	OOScanClass OOScanClassFromJSString(ooscript::Context, ooscript::String)
	OOScanClass OOScanClassFromJSValue(ooscript::Context, ooscript::Value)
	
	Convert between JavaScript strings and OOScanClass.
*/
OOINLINE ooscript::String OOJSStringFromScanClass(ooscript::Context context, OOScanClass value)
{
	extern struct ConstTable gOOScanClassConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOScanClassConstTable);
}


OOINLINE ooscript::Value OOJSValueFromScanClass(ooscript::Context context, OOScanClass value)
{
	return ooscript::stringValue(OOJSStringFromScanClass(context, value));
}


OOINLINE OOScanClass OOScanClassFromJSString(ooscript::Context context, ooscript::String string)
{
	extern struct ConstTable gOOScanClassConstTable;
	return (OOScanClass)OOConstantFromJSStringPRIVATE(context, string, &gOOScanClassConstTable, kOOScanClassDefault);
}


OOINLINE OOScanClass OOScanClassFromJSValue(ooscript::Context context, ooscript::Value value)
{
	extern struct ConstTable gOOScanClassConstTable;
	return (OOScanClass)OOConstantFromJSValuePRIVATE(context, value, &gOOScanClassConstTable, kOOScanClassDefault);
}


/*	ooscript::String OOJSStringFromCompassMode(ooscript::Context, OOCompassMode)
	ooscript::Value OOJSValueFromCompassMode(ooscript::Context, OOCompassMode)
	OOCompassMode OOCompassModeFromJSString(ooscript::Context, ooscript::String)
	OOCompassMode OOCompassModeFromJSValue(ooscript::Context, ooscript::Value)
	
	Convert between JavaScript strings and OOCompassMode.
*/
OOINLINE ooscript::String OOJSStringFromCompassMode(ooscript::Context context, OOCompassMode value)
{
	extern struct ConstTable gOOCompassModeConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOCompassModeConstTable);
}


OOINLINE ooscript::Value OOJSValueFromCompassMode(ooscript::Context context, OOCompassMode value)
{
	return ooscript::stringValue(OOJSStringFromCompassMode(context, value));
}


OOINLINE OOCompassMode OOCompassModeFromJSString(ooscript::Context context, ooscript::String string)
{
	extern struct ConstTable gOOCompassModeConstTable;
	return (OOCompassMode)OOConstantFromJSStringPRIVATE(context, string, &gOOCompassModeConstTable, kOOCompassModeDefault);
}


OOINLINE OOCompassMode OOCompassModeFromJSValue(ooscript::Context context, ooscript::Value value)
{
	extern struct ConstTable gOOCompassModeConstTable;
	return (OOCompassMode)OOConstantFromJSValuePRIVATE(context, value, &gOOCompassModeConstTable, kOOCompassModeDefault);
}


/*	ooscript::String OOJSStringFromGUIScreenID(ooscript::Context, OOGUIScreenID)
	ooscript::Value OOJSValueFromGUIScreenID(ooscript::Context, OOGUIScreenID)
	OOGUIScreenID OOGUIScreenIDFromJSString(ooscript::Context, ooscript::String)
	OOGUIScreenID OOGUIScreenIDFromJSValue(ooscript::Context, ooscript::Value)
	
	Convert between JavaScript strings and OOGUIScreenID.
*/
OOINLINE ooscript::String OOJSStringFromGUIScreenID(ooscript::Context context, OOGUIScreenID value)
{
	extern struct ConstTable gOOGUIScreenIDConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOGUIScreenIDConstTable);
}


OOINLINE ooscript::Value OOJSValueFromGUIScreenID(ooscript::Context context, OOGUIScreenID value)
{
	return ooscript::stringValue(OOJSStringFromGUIScreenID(context, value));
}


OOINLINE OOGUIScreenID OOGUIScreenIDFromJSString(ooscript::Context context, ooscript::String string)
{
	extern struct ConstTable gOOGUIScreenIDConstTable;
	return (OOGUIScreenID)OOConstantFromJSStringPRIVATE(context, string, &gOOGUIScreenIDConstTable, kOOGUIScreenIDDefault);
}


OOINLINE OOGUIScreenID OOGUIScreenIDFromJSValue(ooscript::Context context, ooscript::Value value)
{
	extern struct ConstTable gOOGUIScreenIDConstTable;
	return (OOGUIScreenID)OOConstantFromJSValuePRIVATE(context, value, &gOOGUIScreenIDConstTable, kOOGUIScreenIDDefault);
}



/*	ooscript::String OOJSStringFromGalacticHyperspaceBehaviour(ooscript::Context, OOGalacticHyperspaceBehaviour)
	ooscript::Value OOJSValueFromGalacticHyperspaceBehaviour(ooscript::Context, OOGalacticHyperspaceBehaviour)
	OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSString(ooscript::Context, ooscript::String)
	OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSValue(ooscript::Context, ooscript::Value)
	
	Convert between JavaScript strings and OOGalacticHyperspaceBehaviour.
*/
OOINLINE ooscript::String OOJSStringFromGalacticHyperspaceBehaviour(ooscript::Context context, OOGalacticHyperspaceBehaviour value)
{
	extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOGalacticHyperspaceBehaviourConstTable);
}


OOINLINE ooscript::Value OOJSValueFromGalacticHyperspaceBehaviour(ooscript::Context context, OOGalacticHyperspaceBehaviour value)
{
	return ooscript::stringValue(OOJSStringFromGalacticHyperspaceBehaviour(context, value));
}


OOINLINE OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSString(ooscript::Context context, ooscript::String string)
{
	extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
	return (OOGalacticHyperspaceBehaviour)OOConstantFromJSStringPRIVATE(context, string, &gOOGalacticHyperspaceBehaviourConstTable, kOOGalacticHyperspaceBehaviourDefault);
}


OOINLINE OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSValue(ooscript::Context context, ooscript::Value value)
{
	extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
	return (OOGalacticHyperspaceBehaviour)OOConstantFromJSValuePRIVATE(context, value, &gOOGalacticHyperspaceBehaviourConstTable, kOOGalacticHyperspaceBehaviourDefault);
}



/*	ooscript::String OOJSStringFromViewID(ooscript::Context, OOViewID)
	ooscript::Value OOJSValueFromViewID(ooscript::Context, OOViewID)
	OOViewID OOViewIDFromJSString(ooscript::Context, ooscript::String)
	OOViewID OOViewIDFromJSValue(ooscript::Context, ooscript::Value)
	
	Convert between JavaScript strings and OOViewID.
*/
OOINLINE ooscript::String OOJSStringFromViewID(ooscript::Context context, OOViewID value)
{
	extern struct ConstTable gOOViewIDConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOViewIDConstTable);
}


OOINLINE ooscript::Value OOJSValueFromViewID(ooscript::Context context, OOViewID value)
{
	return ooscript::stringValue(OOJSStringFromViewID(context, value));
}


OOINLINE OOViewID OOViewIDFromJSString(ooscript::Context context, ooscript::String string)
{
	extern struct ConstTable gOOViewIDConstTable;
	return (OOViewID)OOConstantFromJSStringPRIVATE(context, string, &gOOViewIDConstTable, kOOViewIDDefault);
}


OOINLINE OOViewID OOViewIDFromJSValue(ooscript::Context context, ooscript::Value value)
{
	extern struct ConstTable gOOViewIDConstTable;
	return (OOViewID)OOConstantFromJSValuePRIVATE(context, value, &gOOViewIDConstTable, kOOViewIDDefault);
}



/*	ooscript::String OOJSStringFromShipDamageType(ooscript::Context, OOShipDamageType)
	ooscript::Value OOJSValueFromShipDamageType(ooscript::Context, OOShipDamageType)
	
	Convert OOShipDamageType to JavaScript strings.
*/
OOINLINE ooscript::String OOJSStringFromShipDamageType(ooscript::Context context, OOShipDamageType value)
{
	extern struct ConstTable gOOShipDamageTypeConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOShipDamageTypeConstTable);
}


OOINLINE ooscript::Value OOJSValueFromShipDamageType(ooscript::Context context, OOShipDamageType value)
{
	return ooscript::stringValue(OOJSStringFromShipDamageType(context, value));
}



OOINLINE ooscript::String OOJSStringFromLegalStatusReason(ooscript::Context context, OOLegalStatusReason value)
{
	extern struct ConstTable gOOLegalStatusReasonConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOLegalStatusReasonConstTable);
}


OOINLINE ooscript::Value OOJSValueFromLegalStatusReason(ooscript::Context context, OOLegalStatusReason value)
{
	return ooscript::stringValue(OOJSStringFromLegalStatusReason(context, value));
}
