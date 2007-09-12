/*

OOJSMission.m


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

#import "OOJSMission.h"
#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"

#import "OOJSPlayer.h"


static JSBool MissionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool MissionShowMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionShowShipModel(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionResetMissionChoice(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionMarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sMissionClass =
{
	"Mission",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	MissionGetProperty,
	MissionSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kMission_choice,			// selected option, string, read-only.
	kMission_missionScreenTextKey, // mission text key, string, write-only. DEPRECATE - should be read/write text plus ability to set or load mission text.
	kMission_imageFileName,		// background image file name, string, write-only. DEPRECATE - should be function setBackgroundImage().
	kMission_musicFileName,		// music file name, string, write-only. DEPRECATE - should be function setMusic().
	kMission_choicesKey,		// mission text key, string, write-only. DEPRECATE - should be function setChoicesKey().
	kMission_instructionsKey,	// mission text key, string, write-only. DEPRECATE - should be function setInstructionsKey().
};


static JSPropertySpec sMissionProperties[] =
{
	// JS name					ID							flags
	{ "choice",					kMission_choice,			JSPROP_PERMANENT | JSPROP_READONLY | JSPROP_ENUMERATE },
	{ "missionScreenTextKey",	kMission_missionScreenTextKey, JSPROP_PERMANENT },
	{ "imageFileName",			kMission_imageFileName,		JSPROP_PERMANENT },
	{ "musicFileName",			kMission_musicFileName,		JSPROP_PERMANENT },
	{ "choicesKey",				kMission_choicesKey,		JSPROP_PERMANENT },
	{ "instructionsKey",		kMission_instructionsKey,	JSPROP_PERMANENT },
	{ 0 }	
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "showMissionScreen",		MissionShowMissionScreen,	0, 0 },
	{ "showShipModel",			MissionShowShipModel,		1, 0 },
	{ "resetMissionChoice",		MissionResetMissionChoice,	0, 0 },
	{ "markSystem",				MissionMarkSystem,			1, 0 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1, 0 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, NULL, 0, sMissionProperties, sMissionMethods, NULL, NULL);
	JS_DefineObject(context, global, "mission", &sMissionClass, missionPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool MissionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	id							result = nil;
	PlayerEntity				*player = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OOPlayerForScripting();
	
	switch (JSVAL_TO_INT(name))
	{
		case kMission_choice:
			result = [player missionChoice_string];
			if (result == nil)  [NSNull null];
			break;
		
		case kMission_missionScreenTextKey:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated and write-only.", @"missionScreenTextKey");
			break;
		
		case kMission_imageFileName:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated and write-only.", @"imageFileName");
			break;
		
		case kMission_musicFileName:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated and write-only.", @"musicFileName");
			break;
		
		case kMission_choicesKey:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated and write-only.", @"choicesKey");
			break;
		
		case kMission_instructionsKey:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated and write-only.", @"instructionsKey");
			break;
	}
	
	if (result != nil) *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = nil;
	NSString					*string = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OOPlayerForScripting();
	
	switch (JSVAL_TO_INT(name))
	{
		case kMission_missionScreenTextKey:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated, use %@ instead.", @"missionScreenTextKey", @"<TBA>");
			[player addMissionText:[NSString stringWithJavaScriptValue:*value inContext:context]];
			break;
		
		case kMission_imageFileName:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated, use %@ instead.", @"imageFileName", @"mission.setBackgroundImage()");
			string = [NSString stringWithJavaScriptValue:*value inContext:context];
			if ([string length] == 0 || JSVAL_IS_NULL(*value))  string = @"None";
			[player setMissionImage:string];
			break;
		
		case kMission_musicFileName:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated, use %@ instead.", @"musicFileName", @"mission.setMusic()");
			string = [NSString stringWithJavaScriptValue:*value inContext:context];
			if ([string length] == 0 || JSVAL_IS_NULL(*value))  string = @"None";
			[player setMissionMusic:string];
		
		case kMission_choicesKey:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated, use %@ instead.", @"choicesKey", @"<TBA>");
			[player setMissionChoices:[NSString stringWithJavaScriptValue:*value inContext:context]];
			break;
			
		case kMission_instructionsKey:
			OOReportJavaScriptWarning(context, @"mission.%@ is deprecated, use %@ instead.", @"choicesKey", @"<TBA>");
			string = [NSString stringWithJavaScriptValue:*value inContext:context];
			if ([string length] == 0 || JSVAL_IS_NULL(*value))
			{
				[player clearMissionDescriptionForMission:[[OOJSScript currentlyRunningScript] name]];
			}
			else
			{
				[player setMissionDescription:string forMission:[[OOJSScript currentlyRunningScript] name]];
			}
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Mission", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool MissionShowMissionScreen(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	
	[player setGuiToMissionScreen];
	
	return JS_TRUE;
}


static JSBool MissionShowShipModel(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	JSString			*jskey = NULL;
	
	if (argc > 0 && JSVAL_IS_STRING(argv[0]))
	{
		jskey = JS_ValueToString(context, argv[0]);
		[player showShipModel: [NSString stringWithCString:JS_GetStringBytes(jskey)]];
	}
	return JS_TRUE;
}


static JSBool MissionResetMissionChoice(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	
	[player resetMissionChoice];
	
	return JS_TRUE;
}


static JSBool MissionMarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player addMissionDestination:params];
	
	return JS_TRUE;
}


static JSBool MissionUnmarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	player = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player removeMissionDestination:params];
	
	return JS_TRUE;
}
