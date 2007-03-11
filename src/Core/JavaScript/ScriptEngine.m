/*

ScriptEngine.h

JavaScript support for Oolite
Copyright (C) 2007 David Taylor

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

#import "ScriptEngine.h"
#import "OXPScript.h"

#include <stdio.h>
#include <string.h>

Universe *scriptedUniverse;
JSObject *xglob, *universeObj, *systemObj, *playerObj, *missionObj;

extern OXPScript *currentOXPScript;

NSString *JSValToNSString(JSContext *cx, jsval val) {
	JSString *str = JS_ValueToString(cx, val);
	char *chars = JS_GetStringBytes(str);
	return [NSString stringWithCString:chars];
}

void NSStringToJSVal(JSContext *cx, NSString *string, jsval *vp) {
	const char *strptr = [string cString];
	JSString *js_strptr = JS_NewStringCopyZ(cx, strptr);
	*vp = STRING_TO_JSVAL(js_strptr);
}

void BOOLToJSVal(JSContext *cx, BOOL b, jsval *vp) {
	if (b == YES)
		*vp = BOOLEAN_TO_JSVAL(1);
	else
		*vp = BOOLEAN_TO_JSVAL(0);
}

//===========================================================================
// MissionVars class
//===========================================================================

JSBool MissionVarsGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);
JSBool MissionVarsSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass MissionVars_class = {
	"MissionVars", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,MissionVarsGetProperty,MissionVarsSetProperty,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

JSBool MissionVarsGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	NSDictionary *mission_variables = [playerEntity mission_variables];

	if (JSVAL_IS_STRING(id)) {
		NSString *key = JSValToNSString(cx, id);
		NSString *value = (NSString *)[mission_variables objectForKey:key];
		if (!value)
			*vp = JSVAL_VOID;
		else
		{
			int i;
			int c = [value length];
			BOOL isNumber = YES;
			// The point of this code is to try and tell the JS interpreter to treat numeric strings
			// as numbers where possible so that standard arithmetic works as you'd expect rather than
			// 1+1 == "11". So a JSVAL_DOUBLE is returned if possible, otherwise a JSVAL_STRING is returned.
			NSCharacterSet *numberCharSet = [NSCharacterSet characterSetWithCharactersInString:@"1234567890-."];
			for (i = 0; i < c; i++) {
				if ([numberCharSet characterIsMember:[value characterAtIndex:i]] == NO) {
					isNumber = NO;
					break;
				}
			}
			if (isNumber) {
				jsdouble ds = [value doubleValue];
				JSBool ok = JS_NewDoubleValue(cx, ds, vp);
				if (ok)
					return JS_TRUE;
			}
			const char *name_str = [value cString];
			JSString *js_name = JS_NewStringCopyZ(cx, name_str);
			*vp = STRING_TO_JSVAL(js_name);
		}
	}
	return JS_TRUE;
}

JSBool MissionVarsSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	NSDictionary *mission_variables = [playerEntity mission_variables];

	if (JSVAL_IS_STRING(id)) {
		NSString *key = JSValToNSString(cx, id);
		NSString *value = JSValToNSString(cx, *vp);
		[mission_variables setValue:value forKey:key];
	}
	return JS_TRUE;
}

//===========================================================================
// Global object class
//===========================================================================

JSBool GlobalGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass global_class = {
	"Oolite",0,
	JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum global_propertyIds {
	GLOBAL_GALAXY_NUMBER, GLOBAL_PLANET_NUMBER, GLOBAL_DOCKED_AT_MAIN_STATION, GLOBAL_DOCKED_STATION_NAME, GLOBAL_MISSION_VARS,
	GLOBAL_GUI_SCREEN, GLOBAL_STATUS_STRING
};

JSPropertySpec Global_props[] = {
	{ "GalaxyNumber", GLOBAL_GALAXY_NUMBER, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "PlanetNumber", GLOBAL_PLANET_NUMBER, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "DockedAtMainStation", GLOBAL_DOCKED_AT_MAIN_STATION, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "StationName", GLOBAL_DOCKED_STATION_NAME, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "MissionVars", GLOBAL_MISSION_VARS, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "GUIScreen", GLOBAL_GUI_SCREEN, JSPROP_ENUMERATE, GlobalGetProperty },
	{ "StatusString", GLOBAL_STATUS_STRING, JSPROP_ENUMERATE, GlobalGetProperty },
	{ 0 }
};

//JSBool GlobalEnableLogging(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool GlobalLog(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool GlobalListenForKey(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Global_funcs[] = {
//	{ "EnableLogging", GlobalEnableLogging, 1, 0 },
	{ "Log", GlobalLog, 1, 0 },
	{ "ListenForKey", GlobalListenForKey, 1, 0 },
	{ 0 }
};

JSBool GlobalListenForKey(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	NSString *key = JSValToNSString(cx, argv[0]);
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity mapKey:key toOXP:currentOXPScript];
	return JS_TRUE;
}

/*
JSBool GlobalEnableLogging(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
}
*/

JSBool GlobalLog(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	JSString *str;
	str = JS_ValueToString(cx, argv[0]);
	NSLog(@"%s", JS_GetStringBytes(str));
	return JS_TRUE;
}

JSBool GlobalGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	switch (JSVAL_TO_INT(id)) {
		case GLOBAL_GALAXY_NUMBER:
			*vp = INT_TO_JSVAL([[playerEntity galaxy_number] intValue]);
			break;

		case GLOBAL_PLANET_NUMBER:
			*vp = INT_TO_JSVAL([[playerEntity planet_number] intValue]);
			break;

		case GLOBAL_DOCKED_AT_MAIN_STATION:
			BOOLToJSVal(cx, [[playerEntity dockedAtMainStation_bool] isEqualToString:@"YES"], vp);
			break;

		case GLOBAL_DOCKED_STATION_NAME:
			NSStringToJSVal(cx, [playerEntity dockedStationName_string], vp);
			break;

		case GLOBAL_GUI_SCREEN:
			NSStringToJSVal(cx, [playerEntity gui_screen_string], vp);
			break;

		case GLOBAL_STATUS_STRING:
		NSStringToJSVal(cx, [playerEntity status_string], vp);
			break;

		case GLOBAL_MISSION_VARS: {
			JSObject *mv = JS_DefineObject(cx, xglob, "MissionVars", &MissionVars_class, 0x00, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
			*vp = OBJECT_TO_JSVAL(mv);
			break;
		}
	}
	return JS_TRUE;
}

#import "JSUniverse.h"

//===========================================================================
// Player proxy
//===========================================================================

JSBool PlayerGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);
JSBool PlayerSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass Player_class = {
	"Player", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,PlayerGetProperty,PlayerSetProperty,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum Player_propertyIds {
	PE_SHIP_DESCRIPTION, PE_COMMANDER_NAME, PE_SCORE, PE_CREDITS, PE_LEGAL_STATUS,
	PE_FUEL_LEVEL, PE_FUEL_LEAK_RATE, PE_ALERT_CONDITION, PE_ALERT_FLAGS
};

JSPropertySpec Player_props[] = {
	{ "ShipDescription", PE_SHIP_DESCRIPTION, JSPROP_ENUMERATE },
	{ "Name", PE_COMMANDER_NAME, JSPROP_ENUMERATE },
	{ "Score", PE_SCORE, JSPROP_ENUMERATE },
	{ "Credits", PE_CREDITS, JSPROP_ENUMERATE },
	{ "LegalStatus", PE_LEGAL_STATUS, JSPROP_ENUMERATE },
	{ "Fuel", PE_FUEL_LEVEL, JSPROP_ENUMERATE },
	{ "FuelLeakRate", PE_FUEL_LEAK_RATE, JSPROP_ENUMERATE },
	{ "AlertCondition", PE_ALERT_CONDITION, JSPROP_ENUMERATE },
	{ "AlertFlags", PE_ALERT_FLAGS, JSPROP_ENUMERATE },
	{ 0 }
};

JSBool PlayerAwardEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerRemoveEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerHasEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerLaunch(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerCall(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerAwardCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerRemoveAllCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool PlayerUseSpecialCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Player_funcs[] = {
	{ "AwardEquipment", PlayerAwardEquipment, 1, 0 },
	{ "RemoveEquipment", PlayerRemoveEquipment, 1, 0 },
	{ "HasEquipment", PlayerHasEquipment, 1, 0 },
	{ "Launch", PlayerLaunch, 0, 0 },
	{ "Call", PlayerCall, 2, 0 },
	{ "AwardCargo", PlayerAwardCargo, 2, 0 },
	{ "RemoveAllCargo", PlayerRemoveAllCargo, 0, 0 },
	{ "UseSpecialCargo", PlayerUseSpecialCargo, 1, 0 },
	{ 0 }
};

JSBool PlayerAwardCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 2) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *amount_type = [NSString stringWithFormat:@"%@ %@", JSValToNSString(cx, argv[0]), JSValToNSString(cx, argv[1])];
		[playerEntity awardCargo:amount_type];
	}
	return JS_TRUE;
}

JSBool PlayerRemoveAllCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity removeAllCargo];
	return JS_TRUE;
}

JSBool PlayerUseSpecialCargo(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 1) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		[playerEntity useSpecialCargo:JSValToNSString(cx, argv[0])];
	}
	return JS_TRUE;
}

JSBool PlayerAwardEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[playerEntity awardEquipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}

JSBool PlayerRemoveEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[playerEntity removeEquipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}

JSBool PlayerHasEquipment(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		BOOLToJSVal(cx, [playerEntity has_extra_equipment: [NSString stringWithCString:JS_GetStringBytes(jskey)]], rval);
	}
	return JS_TRUE;
}

JSBool PlayerLaunch(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity launchFromStation];
	return JS_TRUE;
}

JSBool PlayerCall(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0) {
		NSString *selectorString = JSValToNSString(cx, argv[0]);
		// Check if the selector needs a trailing colon to flag an argument will be sent
		if (argc > 1)
			selectorString = [NSString stringWithFormat:@"%@:", selectorString];

		SEL _selector = NSSelectorFromString(selectorString);
		if ([playerEntity respondsToSelector:_selector]) {
			if (argc == 1)
				[playerEntity performSelector:_selector];
			else {
				NSString *valueString = JSValToNSString(cx, argv[1]);
				[playerEntity performSelector:_selector withObject:valueString];
			}
		}
	}

	return JS_TRUE;
}

JSBool PlayerGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	switch (JSVAL_TO_INT(id)) {
		case PE_SHIP_DESCRIPTION:
			NSStringToJSVal(cx, [playerEntity commanderShip_string], vp);
			break;

		case PE_COMMANDER_NAME:
			NSStringToJSVal(cx, [playerEntity commanderName_string], vp);
			break;

		case PE_SCORE:
			JS_NewDoubleValue(cx, [[playerEntity score_number] doubleValue], vp);
			break;

		case PE_LEGAL_STATUS:
			JS_NewDoubleValue(cx, [[playerEntity legalStatus_number] doubleValue], vp);
			break;

		case PE_CREDITS:
			JS_NewDoubleValue(cx, [[playerEntity credits_number] doubleValue], vp);
			break;

		case PE_FUEL_LEVEL:
			JS_NewDoubleValue(cx, [[playerEntity fuel_level_number] doubleValue], vp);
			break;

		case PE_FUEL_LEAK_RATE:
			JS_NewDoubleValue(cx, [[playerEntity fuel_leak_rate_number] doubleValue], vp);
			break;

		case PE_ALERT_CONDITION:
			*vp = INT_TO_JSVAL([playerEntity alert_condition]);
			break;

		case PE_ALERT_FLAGS:
			*vp = INT_TO_JSVAL([playerEntity alert_flags]);
			break;
	}
	return JS_TRUE;
}

JSBool PlayerSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	switch (JSVAL_TO_INT(id)) {
		case PE_SCORE:
			[playerEntity setKills:[JSValToNSString(cx, *vp) intValue]];
			break;

		case PE_LEGAL_STATUS:
			[playerEntity setLegalStatus:JSValToNSString(cx, *vp)];
			break;
		
		case PE_CREDITS:
			[playerEntity setCredits:[JSValToNSString(cx, *vp) intValue]];
			break;

		case PE_FUEL_LEVEL:
			[playerEntity setCredits:(int)([JSValToNSString(cx, *vp) doubleValue] * 10)];
			break;

		case PE_FUEL_LEAK_RATE:
			[playerEntity setLegalStatus:JSValToNSString(cx, *vp)];
			break;
	}
	return JS_TRUE;
}

//===========================================================================
// System (solar system) proxy
//===========================================================================

JSBool SystemGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);
JSBool SystemSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass System_class = {
	"System", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,SystemGetProperty,SystemSetProperty,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum System_propertyIds {
	SYS_ID, SYS_NAME, SYS_DESCRIPTION, SYS_GOING_NOVA, SYS_GONE_NOVA, SYS_GOVT_STR, SYS_GOVT_ID, SYS_ECONOMY_ID,
	SYS_TECH_LVL, SYS_POPULATION, SYS_PRODUCTIVITY, SYS_INHABITANTS
};

JSPropertySpec System_props[] = {
	{ "Id", SYS_ID, JSPROP_ENUMERATE },
	{ "Name", SYS_NAME, JSPROP_ENUMERATE },
	{ "Description", SYS_DESCRIPTION, JSPROP_ENUMERATE },
	{ "InhabitantsDescription", SYS_INHABITANTS, JSPROP_ENUMERATE },
	{ "GoingNova", SYS_GOING_NOVA, JSPROP_ENUMERATE },
	{ "GoneNova", SYS_GONE_NOVA, JSPROP_ENUMERATE },
	{ "GovernmentDescription", SYS_GOVT_STR, JSPROP_ENUMERATE },
	{ "GovernmentId", SYS_GOVT_ID, JSPROP_ENUMERATE },
	{ "EconomyId", SYS_ECONOMY_ID, JSPROP_ENUMERATE },
	{ "TechLevel", SYS_TECH_LVL, JSPROP_ENUMERATE },
	{ "Population", SYS_POPULATION, JSPROP_ENUMERATE },
	{ "Productivity", SYS_PRODUCTIVITY, JSPROP_ENUMERATE },
	{ 0 }
};

JSBool SystemAddPlanet(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool SystemAddMoon(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool SystemSendAllShipsAway(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool SystemSetSunNova(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec System_funcs[] = {
	{ "AddPlanet", SystemAddPlanet, 1, 0 },
	{ "AddMoon", SystemAddMoon, 1, 0 },
	{ "SendAllShipsAway", SystemSendAllShipsAway, 1, 0 },
	{ "SetSunNova", SystemSetSunNova, 1, 0 },
	{ 0 }
};

JSBool SystemAddPlanet(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		NSString *key = JSValToNSString(cx, argv[0]);
		[playerEntity addPlanet:key];
	}
	return JS_TRUE;
}

JSBool SystemAddMoon(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		NSString *key = JSValToNSString(cx, argv[0]);
		[playerEntity addMoon:key];
	}
	return JS_TRUE;
}

JSBool SystemSendAllShipsAway(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity sendAllShipsAway];
	return JS_TRUE;
}

JSBool SystemSetSunNova(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0) {
		NSString *key = JSValToNSString(cx, argv[0]);
		[playerEntity setSunNovaIn:key];
	}
	return JS_TRUE;
}

static Random_Seed currentSystem;
static NSDictionary *planetinfo = nil;

JSBool SystemGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;

	NSString *str;
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (!equal_seeds(currentSystem, playerEntity->system_seed)) {
		//fprintf(stdout, "Current system has changed, regenerating local copy of planetinfo\r\n");
		currentSystem = playerEntity->system_seed;
		if (planetinfo)
			[planetinfo release];

		planetinfo = [[scriptedUniverse generateSystemData:currentSystem] retain];
	}

	switch (JSVAL_TO_INT(id)) {
		case SYS_ID:
			*vp = INT_TO_JSVAL([[playerEntity planet_number] intValue]);
			break;

		case SYS_NAME:
			str = (NSString *)[planetinfo objectForKey:KEY_NAME];
			if (!str)
				str = @"None";
			NSStringToJSVal(cx, str, vp);
			break;

		case SYS_DESCRIPTION:
			str = (NSString *)[planetinfo objectForKey:KEY_DESCRIPTION];
			if (!str)
				str = @"None";
			NSStringToJSVal(cx, str, vp);
			break;

		case SYS_INHABITANTS:
			str = (NSString *)[planetinfo objectForKey:KEY_INHABITANTS];
			if (!str)
				str = @"None";
			NSStringToJSVal(cx, str, vp);
			break;

		case SYS_GOING_NOVA:
			BOOLToJSVal(cx, [[playerEntity sunWillGoNova_bool] isEqualToString:@"YES"], vp);
			break;

		case SYS_GONE_NOVA:
			BOOLToJSVal(cx, [[playerEntity sunGoneNova_bool] isEqualToString:@"YES"], vp);
			break;

		case SYS_GOVT_STR:
			NSStringToJSVal(cx, [playerEntity systemGovernment_string], vp);
			break;

		case SYS_GOVT_ID:
			JS_NewDoubleValue(cx, [[playerEntity systemGovernment_number] doubleValue], vp);
			break;

		case SYS_ECONOMY_ID:
			JS_NewDoubleValue(cx, [[playerEntity systemEconomy_number] doubleValue], vp);
			break;

		case SYS_TECH_LVL:
			JS_NewDoubleValue(cx, [[playerEntity systemTechLevel_number] doubleValue], vp);
			break;

		case SYS_POPULATION:
			JS_NewDoubleValue(cx, [[playerEntity systemPopulation_number] doubleValue], vp);
			break;

		case SYS_PRODUCTIVITY:
			JS_NewDoubleValue(cx, [[playerEntity systemProductivity_number] doubleValue], vp);
			break;
	}
	return JS_TRUE;
}

JSBool SystemSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;
	
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (!equal_seeds(currentSystem, playerEntity->system_seed)) {
		//fprintf(stdout, "Current system has changed, regenerating local copy of planetinfo\r\n");
		currentSystem = playerEntity->system_seed;
		if (planetinfo)
			[planetinfo release];

		planetinfo = [[scriptedUniverse generateSystemData:currentSystem] retain];
	}
	int gn = [[playerEntity galaxy_number] intValue];
	int pn = [[playerEntity planet_number] intValue];

	switch (JSVAL_TO_INT(id)) {
		case SYS_NAME:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_NAME value:JSValToNSString(cx, *vp)];
			break;

			case SYS_DESCRIPTION:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_DESCRIPTION value:JSValToNSString(cx, *vp)];
			break;

		case SYS_INHABITANTS:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_INHABITANTS value:JSValToNSString(cx, *vp)];
			break;
/*
		case SYS_GOING_NOVA:
			//BOOLToJSVal(cx, [[playerEntity sunWillGoNova_bool] isEqualToString:@"YES"], vp);
			break;

		case SYS_GONE_NOVA:
			//BOOLToJSVal(cx, [[playerEntity sunGoneNova_bool] isEqualToString:@"YES"], vp);
			break;
*/
		case SYS_GOVT_ID:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_GOVERNMENT value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_ECONOMY_ID:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_ECONOMY value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_TECH_LVL:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_TECHLEVEL value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_POPULATION:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_POPULATION value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;

		case SYS_PRODUCTIVITY:
			[scriptedUniverse setSystemDataForGalaxy:gn planet:pn key:KEY_PRODUCTIVITY value:[NSNumber numberWithInt:[JSValToNSString(cx, *vp) intValue]]];
			break;
	}
	return JS_TRUE;
}

//===========================================================================
// Mission class
//===========================================================================

JSBool MissionGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);
JSBool MissionSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

JSClass Mission_class = {
	"Mission", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,MissionGetProperty,MissionSetProperty,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

enum Mission_propertyIds {
	MISSION_TEXT, MISSION_MUSIC, MISSION_IMAGE, MISSION_CHOICES, MISSION_CHOICE, MISSION_INSTRUCTIONS
};

JSPropertySpec Mission_props[] = {
	{ "MissionScreenTextKey", MISSION_TEXT, JSPROP_ENUMERATE },
	{ "MusicFilename", MISSION_MUSIC, JSPROP_ENUMERATE },
	{ "ImageFilename", MISSION_IMAGE, JSPROP_ENUMERATE },
	{ "ChoicesKey", MISSION_CHOICES, JSPROP_ENUMERATE },
	{ "Choice", MISSION_CHOICE, JSPROP_ENUMERATE },
	{ "InstructionsKey", MISSION_INSTRUCTIONS, JSPROP_ENUMERATE },
	{ 0 }
};

JSBool MissionShowMissionScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionShowShipModel(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionResetMissionChoice(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionMarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool MissionUnmarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Mission_funcs[] = {
	{ "ShowMissionScreen", MissionShowMissionScreen, 0, 0 },
	{ "ShowShipModel", MissionShowShipModel, 1, 0 },
	{ "ResetMissionChoice", MissionResetMissionChoice, 0, 0 },
	{ "MarkSystem", MissionMarkSystem, 1, 0 },
	{ "UnmarkSystem", MissionUnmarkSystem, 1, 0 },
	{ 0 }
};

JSBool MissionGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;

	NSString *str;
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	switch (JSVAL_TO_INT(id)) {
		case MISSION_CHOICE:
			str = (NSString *)[playerEntity missionChoice_string];
			if (!str)
				str = @"None";
			NSStringToJSVal(cx, str, vp);
			break;
	}
	return JS_TRUE;
}

JSBool MissionSetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {

	if (!JSVAL_IS_INT(id)) return JS_TRUE;

	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

	switch (JSVAL_TO_INT(id)) {
		case MISSION_TEXT: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				[playerEntity addMissionText: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		}
		case MISSION_MUSIC: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				[playerEntity setMissionMusic: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		}
		case MISSION_IMAGE: {
			if (JSVAL_IS_STRING(*vp)) {
				NSString *str = JSValToNSString(cx, *vp);
				if ([str length] == 0)
					str = @"none";
				[playerEntity setMissionImage:str];
			}
			break;
		}
		case MISSION_CHOICES: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				[playerEntity setMissionChoices: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
			}
			break;
		}
		case MISSION_INSTRUCTIONS: {
			if (JSVAL_IS_STRING(*vp)) {
				JSString *jskey = JS_ValueToString(cx, *vp);
				NSString *ins = [NSString stringWithCString:JS_GetStringBytes(jskey)];
				if ([ins length])
					[playerEntity setMissionDescription:ins forMission:[currentOXPScript name]];
				else
					[playerEntity clearMissionDescriptionForMission:[currentOXPScript name]];
			}
			break;
		}
	}
	return JS_TRUE;
}

JSBool MissionShowMissionScreen(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity setGuiToMissionScreen];
	return JS_TRUE;
}

JSBool MissionShowShipModel(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	if (argc > 0 && JSVAL_IS_STRING(argv[0])) {
		JSString *jskey = JS_ValueToString(cx, argv[0]);
		[playerEntity showShipModel: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}

JSBool MissionResetMissionChoice(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
	[playerEntity resetMissionChoice];
	return JS_TRUE;
}

JSBool MissionMarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	return JS_TRUE;
}

JSBool MissionUnmarkSystem(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	return JS_TRUE;
}

void reportJSError(JSContext *cx, const char *message, JSErrorReport *report) {
	NSLog(@"JavaScript error: %s", message);
	NSLog(@"%s:%d: %s", report->filename, report->lineno, report->linebuf);
}

//===========================================================================
// JavaScript engine initialisation and shutdown
//===========================================================================

@implementation ScriptEngine

- (id) initWithUniverse: (Universe *)universe
{
	self = [super init];
	scriptedUniverse = universe;

	/*set up global JS variables, including global and custom objects */

	/* initialize the JS run time, and return result in rt */
	rt = JS_NewRuntime(8L * 1024L * 1024L);

	/* if rt does not have a value, end the program here */
	if (!rt) {
		[super dealloc];
		exit(1); //return nil;
	}

	/* create a context and associate it with the JS run time */
	cx = JS_NewContext(rt, 8192);
	NSLog(@"created context");
	
	/* if cx does not have a value, end the program here */
	if (cx == NULL) {
		[super dealloc];
		exit(1); //return nil;
	}

	JS_SetErrorReporter(cx, reportJSError);

	/* create the global object here */
	glob = JS_NewObject(cx, &global_class, NULL, NULL);
	xglob = glob;

	/* initialize the built-in JS objects and the global object */
	builtins = JS_InitStandardClasses(cx, glob);
	JS_DefineProperties(cx, glob, Global_props);
	JS_DefineFunctions(cx, glob, Global_funcs);

	universeObj = JS_DefineObject(cx, glob, "Universe", &Universe_class, NULL, JSPROP_ENUMERATE);
	//JS_DefineProperties(cx, universeObj, Universe_props);
	JS_DefineFunctions(cx, universeObj, Universe_funcs);

	systemObj = JS_DefineObject(cx, glob, "System", &System_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, systemObj, System_props);
	JS_DefineFunctions(cx, systemObj, System_funcs);

	playerObj = JS_DefineObject(cx, glob, "Player", &Player_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, playerObj, Player_props);
	JS_DefineFunctions(cx, playerObj, Player_funcs);

	missionObj = JS_DefineObject(cx, glob, "Mission", &Mission_class, NULL, JSPROP_ENUMERATE);
	JS_DefineProperties(cx, missionObj, Mission_props);
	JS_DefineFunctions(cx, missionObj, Mission_funcs);

	return self;
}

- (void) dealloc
{
	// free up the OXPScripts too!

	JS_DestroyContext(cx);
	/* Before exiting the application, free the JS run time */
	JS_DestroyRuntime(rt);
	[super dealloc];
}

- (JSContext *) context
{
	return cx;
}

@end
