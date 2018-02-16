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

#import "OOJavaScriptEngine.h"


void OOConstToJSStringInit(JSContext *context);
void OOConstToJSStringDestroy(void);

struct ConstTable;


// Private functions, don't use directly.
JSString *OOJSStringFromConstantPRIVATE(JSContext *context, NSInteger value, struct ConstTable *table);
NSUInteger OOConstantFromJSStringPRIVATE(JSContext *context, JSString *string, struct ConstTable *table, NSInteger defaultValue);
NSUInteger OOConstantFromJSValuePRIVATE(JSContext *context, jsval value, struct ConstTable *table, NSInteger defaultValue);


/*	JSString *OOJSStringFromEntityStatus(JSContext *, OOEntityStatus)
	jsval OOJSValueFromEntityStatus(JSContext *, OOEntityStatus)
	OOEntityStatus OOEntityStatusFromJSString(JSContext *, JSString *)
	OOEntityStatus OOEntityStatusFromJSValue(JSContext *, jsval)
	
	Convert between JavaScript strings and OOEntityStatus.
*/
OOINLINE JSString *OOJSStringFromEntityStatus(JSContext *context, OOEntityStatus value)
{
	extern struct ConstTable gOOEntityStatusConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOEntityStatusConstTable);
}


OOINLINE jsval OOJSValueFromEntityStatus(JSContext *context, OOEntityStatus value)
{
	return STRING_TO_JSVAL(OOJSStringFromEntityStatus(context, value));
}


OOINLINE OOEntityStatus OOEntityStatusFromJSString(JSContext *context, JSString *string)
{
	extern struct ConstTable gOOEntityStatusConstTable;
	return (OOEntityStatus)OOConstantFromJSStringPRIVATE(context, string, &gOOEntityStatusConstTable, kOOEntityStatusDefault);
}


OOINLINE OOEntityStatus OOEntityStatusFromJSValue(JSContext *context, jsval value)
{
	extern struct ConstTable gOOEntityStatusConstTable;
	return (OOEntityStatus)OOConstantFromJSValuePRIVATE(context, value, &gOOEntityStatusConstTable, kOOEntityStatusDefault);
}


/*	JSString *OOJSStringFromScanClass(JSContext *, OOScanClass)
	jsval OOJSValueFromScanClass(JSContext *, OOScanClass)
	OOScanClass OOScanClassFromJSString(JSContext *, JSString *)
	OOScanClass OOScanClassFromJSValue(JSContext *, jsval)
	
	Convert between JavaScript strings and OOScanClass.
*/
OOINLINE JSString *OOJSStringFromScanClass(JSContext *context, OOScanClass value)
{
	extern struct ConstTable gOOScanClassConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOScanClassConstTable);
}


OOINLINE jsval OOJSValueFromScanClass(JSContext *context, OOScanClass value)
{
	return STRING_TO_JSVAL(OOJSStringFromScanClass(context, value));
}


OOINLINE OOScanClass OOScanClassFromJSString(JSContext *context, JSString *string)
{
	extern struct ConstTable gOOScanClassConstTable;
	return (OOScanClass)OOConstantFromJSStringPRIVATE(context, string, &gOOScanClassConstTable, kOOScanClassDefault);
}


OOINLINE OOScanClass OOScanClassFromJSValue(JSContext *context, jsval value)
{
	extern struct ConstTable gOOScanClassConstTable;
	return (OOScanClass)OOConstantFromJSValuePRIVATE(context, value, &gOOScanClassConstTable, kOOScanClassDefault);
}


/*	JSString *OOJSStringFromCompassMode(JSContext *, OOCompassMode)
	jsval OOJSValueFromCompassMode(JSContext *, OOCompassMode)
	OOCompassMode OOCompassModeFromJSString(JSContext *, JSString *)
	OOCompassMode OOCompassModeFromJSValue(JSContext *, jsval)
	
	Convert between JavaScript strings and OOCompassMode.
*/
OOINLINE JSString *OOJSStringFromCompassMode(JSContext *context, OOCompassMode value)
{
	extern struct ConstTable gOOCompassModeConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOCompassModeConstTable);
}


OOINLINE jsval OOJSValueFromCompassMode(JSContext *context, OOCompassMode value)
{
	return STRING_TO_JSVAL(OOJSStringFromCompassMode(context, value));
}


OOINLINE OOCompassMode OOCompassModeFromJSString(JSContext *context, JSString *string)
{
	extern struct ConstTable gOOCompassModeConstTable;
	return (OOCompassMode)OOConstantFromJSStringPRIVATE(context, string, &gOOCompassModeConstTable, kOOCompassModeDefault);
}


OOINLINE OOCompassMode OOCompassModeFromJSValue(JSContext *context, jsval value)
{
	extern struct ConstTable gOOCompassModeConstTable;
	return (OOCompassMode)OOConstantFromJSValuePRIVATE(context, value, &gOOCompassModeConstTable, kOOCompassModeDefault);
}


/*	JSString *OOJSStringFromGUIScreenID(JSContext *, OOGUIScreenID)
	jsval OOJSValueFromGUIScreenID(JSContext *, OOGUIScreenID)
	OOGUIScreenID OOGUIScreenIDFromJSString(JSContext *, JSString *)
	OOGUIScreenID OOGUIScreenIDFromJSValue(JSContext *, jsval)
	
	Convert between JavaScript strings and OOGUIScreenID.
*/
OOINLINE JSString *OOJSStringFromGUIScreenID(JSContext *context, OOGUIScreenID value)
{
	extern struct ConstTable gOOGUIScreenIDConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOGUIScreenIDConstTable);
}


OOINLINE jsval OOJSValueFromGUIScreenID(JSContext *context, OOGUIScreenID value)
{
	return STRING_TO_JSVAL(OOJSStringFromGUIScreenID(context, value));
}


OOINLINE OOGUIScreenID OOGUIScreenIDFromJSString(JSContext *context, JSString *string)
{
	extern struct ConstTable gOOGUIScreenIDConstTable;
	return (OOGUIScreenID)OOConstantFromJSStringPRIVATE(context, string, &gOOGUIScreenIDConstTable, kOOGUIScreenIDDefault);
}


OOINLINE OOGUIScreenID OOGUIScreenIDFromJSValue(JSContext *context, jsval value)
{
	extern struct ConstTable gOOGUIScreenIDConstTable;
	return (OOGUIScreenID)OOConstantFromJSValuePRIVATE(context, value, &gOOGUIScreenIDConstTable, kOOGUIScreenIDDefault);
}



/*	JSString *OOJSStringFromGalacticHyperspaceBehaviour(JSContext *, OOGalacticHyperspaceBehaviour)
	jsval OOJSValueFromGalacticHyperspaceBehaviour(JSContext *, OOGalacticHyperspaceBehaviour)
	OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSString(JSContext *, JSString *)
	OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSValue(JSContext *, jsval)
	
	Convert between JavaScript strings and OOGalacticHyperspaceBehaviour.
*/
OOINLINE JSString *OOJSStringFromGalacticHyperspaceBehaviour(JSContext *context, OOGalacticHyperspaceBehaviour value)
{
	extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOGalacticHyperspaceBehaviourConstTable);
}


OOINLINE jsval OOJSValueFromGalacticHyperspaceBehaviour(JSContext *context, OOGalacticHyperspaceBehaviour value)
{
	return STRING_TO_JSVAL(OOJSStringFromGalacticHyperspaceBehaviour(context, value));
}


OOINLINE OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSString(JSContext *context, JSString *string)
{
	extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
	return (OOGalacticHyperspaceBehaviour)OOConstantFromJSStringPRIVATE(context, string, &gOOGalacticHyperspaceBehaviourConstTable, kOOGalacticHyperspaceBehaviourDefault);
}


OOINLINE OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSValue(JSContext *context, jsval value)
{
	extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
	return (OOGalacticHyperspaceBehaviour)OOConstantFromJSValuePRIVATE(context, value, &gOOGalacticHyperspaceBehaviourConstTable, kOOGalacticHyperspaceBehaviourDefault);
}



/*	JSString *OOJSStringFromViewID(JSContext *, OOViewID)
	jsval OOJSValueFromViewID(JSContext *, OOViewID)
	OOViewID OOViewIDFromJSString(JSContext *, JSString *)
	OOViewID OOViewIDFromJSValue(JSContext *, jsval)
	
	Convert between JavaScript strings and OOViewID.
*/
OOINLINE JSString *OOJSStringFromViewID(JSContext *context, OOViewID value)
{
	extern struct ConstTable gOOViewIDConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOViewIDConstTable);
}


OOINLINE jsval OOJSValueFromViewID(JSContext *context, OOViewID value)
{
	return STRING_TO_JSVAL(OOJSStringFromViewID(context, value));
}


OOINLINE OOViewID OOViewIDFromJSString(JSContext *context, JSString *string)
{
	extern struct ConstTable gOOViewIDConstTable;
	return (OOViewID)OOConstantFromJSStringPRIVATE(context, string, &gOOViewIDConstTable, kOOViewIDDefault);
}


OOINLINE OOViewID OOViewIDFromJSValue(JSContext *context, jsval value)
{
	extern struct ConstTable gOOViewIDConstTable;
	return (OOViewID)OOConstantFromJSValuePRIVATE(context, value, &gOOViewIDConstTable, kOOViewIDDefault);
}



/*	JSString *OOJSStringFromShipDamageType(JSContext *, OOShipDamageType)
	jsval OOJSValueFromShipDamageType(JSContext *, OOShipDamageType)
	
	Convert OOShipDamageType to JavaScript strings.
*/
OOINLINE JSString *OOJSStringFromShipDamageType(JSContext *context, OOShipDamageType value)
{
	extern struct ConstTable gOOShipDamageTypeConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOShipDamageTypeConstTable);
}


OOINLINE jsval OOJSValueFromShipDamageType(JSContext *context, OOShipDamageType value)
{
	return STRING_TO_JSVAL(OOJSStringFromShipDamageType(context, value));
}



OOINLINE JSString *OOJSStringFromLegalStatusReason(JSContext *context, OOLegalStatusReason value)
{
	extern struct ConstTable gOOLegalStatusReasonConstTable;
	return OOJSStringFromConstantPRIVATE(context, value, &gOOLegalStatusReasonConstTable);
}


OOINLINE jsval OOJSValueFromLegalStatusReason(JSContext *context, OOLegalStatusReason value)
{
	return STRING_TO_JSVAL(OOJSStringFromLegalStatusReason(context, value));
}
