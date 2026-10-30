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

void OOConstToJSStringInit(JSContext* context);
void OOConstToJSStringDestroy(void);

struct ConstTable;

/*	QuickJS has no JSString type, so the SpiderMonkey OOJSStringFromFoo() and
        OOFooFromJSString() variants are gone; OOJSValueFromFoo() returns an owned
        string value and OOFooFromJSValue() accepts any value (non-strings give
        the default).
*/

// Private functions, don't use directly.
JSValue OOJSValueFromConstantPRIVATE(JSContext* context, NSInteger value, struct ConstTable* table);
NSUInteger OOConstantFromJSValuePRIVATE(JSContext* context, JSValueConst value, struct ConstTable* table, NSInteger defaultValue);

/*	JSValue OOJSValueFromEntityStatus(JSContext *, OOEntityStatus)
        OOEntityStatus OOEntityStatusFromJSValue(JSContext *, JSValueConst)

        Convert between JavaScript strings and OOEntityStatus.
*/
OOINLINE JSValue OOJSValueFromEntityStatus(JSContext* context, OOEntityStatus value)
{
    extern struct ConstTable gOOEntityStatusConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOEntityStatusConstTable);
}

OOINLINE OOEntityStatus OOEntityStatusFromJSValue(JSContext* context, JSValueConst value)
{
    extern struct ConstTable gOOEntityStatusConstTable;
    return (OOEntityStatus)OOConstantFromJSValuePRIVATE(context, value, &gOOEntityStatusConstTable, kOOEntityStatusDefault);
}

/*	JSValue OOJSValueFromScanClass(JSContext *, OOScanClass)
        OOScanClass OOScanClassFromJSValue(JSContext *, JSValueConst)

        Convert between JavaScript strings and OOScanClass.
*/
OOINLINE JSValue OOJSValueFromScanClass(JSContext* context, OOScanClass value)
{
    extern struct ConstTable gOOScanClassConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOScanClassConstTable);
}

OOINLINE OOScanClass OOScanClassFromJSValue(JSContext* context, JSValueConst value)
{
    extern struct ConstTable gOOScanClassConstTable;
    return (OOScanClass)OOConstantFromJSValuePRIVATE(context, value, &gOOScanClassConstTable, kOOScanClassDefault);
}

/*	JSValue OOJSValueFromCompassMode(JSContext *, OOCompassMode)
        OOCompassMode OOCompassModeFromJSValue(JSContext *, JSValueConst)

        Convert between JavaScript strings and OOCompassMode.
*/
OOINLINE JSValue OOJSValueFromCompassMode(JSContext* context, OOCompassMode value)
{
    extern struct ConstTable gOOCompassModeConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOCompassModeConstTable);
}

OOINLINE OOCompassMode OOCompassModeFromJSValue(JSContext* context, JSValueConst value)
{
    extern struct ConstTable gOOCompassModeConstTable;
    return (OOCompassMode)OOConstantFromJSValuePRIVATE(context, value, &gOOCompassModeConstTable, kOOCompassModeDefault);
}

/*	JSValue OOJSValueFromGUIScreenID(JSContext *, OOGUIScreenID)
        OOGUIScreenID OOGUIScreenIDFromJSValue(JSContext *, JSValueConst)

        Convert between JavaScript strings and OOGUIScreenID.
*/
OOINLINE JSValue OOJSValueFromGUIScreenID(JSContext* context, OOGUIScreenID value)
{
    extern struct ConstTable gOOGUIScreenIDConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOGUIScreenIDConstTable);
}

OOINLINE OOGUIScreenID OOGUIScreenIDFromJSValue(JSContext* context, JSValueConst value)
{
    extern struct ConstTable gOOGUIScreenIDConstTable;
    return (OOGUIScreenID)OOConstantFromJSValuePRIVATE(context, value, &gOOGUIScreenIDConstTable, kOOGUIScreenIDDefault);
}

/*	JSValue OOJSValueFromGalacticHyperspaceBehaviour(JSContext *, OOGalacticHyperspaceBehaviour)
        OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSValue(JSContext *, JSValueConst)

        Convert between JavaScript strings and OOGalacticHyperspaceBehaviour.
*/
OOINLINE JSValue OOJSValueFromGalacticHyperspaceBehaviour(JSContext* context, OOGalacticHyperspaceBehaviour value)
{
    extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOGalacticHyperspaceBehaviourConstTable);
}

OOINLINE OOGalacticHyperspaceBehaviour OOGalacticHyperspaceBehaviourFromJSValue(JSContext* context, JSValueConst value)
{
    extern struct ConstTable gOOGalacticHyperspaceBehaviourConstTable;
    return (OOGalacticHyperspaceBehaviour)OOConstantFromJSValuePRIVATE(context, value, &gOOGalacticHyperspaceBehaviourConstTable, kOOGalacticHyperspaceBehaviourDefault);
}

/*	JSValue OOJSValueFromViewID(JSContext *, OOViewID)
        OOViewID OOViewIDFromJSValue(JSContext *, JSValueConst)

        Convert between JavaScript strings and OOViewID.
*/
OOINLINE JSValue OOJSValueFromViewID(JSContext* context, OOViewID value)
{
    extern struct ConstTable gOOViewIDConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOViewIDConstTable);
}

OOINLINE OOViewID OOViewIDFromJSValue(JSContext* context, JSValueConst value)
{
    extern struct ConstTable gOOViewIDConstTable;
    return (OOViewID)OOConstantFromJSValuePRIVATE(context, value, &gOOViewIDConstTable, kOOViewIDDefault);
}

/*	JSValue OOJSValueFromShipDamageType(JSContext *, OOShipDamageType)

        Convert OOShipDamageType to JavaScript strings.
*/
OOINLINE JSValue OOJSValueFromShipDamageType(JSContext* context, OOShipDamageType value)
{
    extern struct ConstTable gOOShipDamageTypeConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOShipDamageTypeConstTable);
}

/*	JSValue OOJSValueFromLegalStatusReason(JSContext *, OOLegalStatusReason)

        Convert OOLegalStatusReason to JavaScript strings.
*/
OOINLINE JSValue OOJSValueFromLegalStatusReason(JSContext* context, OOLegalStatusReason value)
{
    extern struct ConstTable gOOLegalStatusReasonConstTable;
    return OOJSValueFromConstantPRIVATE(context, value, &gOOLegalStatusReasonConstTable);
}
