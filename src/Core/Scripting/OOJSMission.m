/*

OOJSMission.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "PlayerEntityScriptMethods.h"


static JSBool MissionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool MissionShowMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionShowShipModel(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionMarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionAddMessageTextKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetBackgroundImage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetChoicesKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionClearMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

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
	kMission_choice,			// selected option, string, read/write.
	kMission_background,		// mission background image, string, read/write.
	kMission_shipModel,			// mission ship model role, string, read/write.
};


static JSPropertySpec sMissionProperties[] =
{
	// JS name					ID							flags
	{ "choice",					kMission_choice,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	//{ "backgroundImage",		kMission_background,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	//{ "shipModel",				kMission_shipModel,			JSPROP_PERMANENT | JSPROP_ENUMERATE },

	{ 0 }	
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "showMissionScreen",		MissionShowMissionScreen,	0 },
	{ "showShipModel",			MissionShowShipModel,		1 },
	{ "markSystem",				MissionMarkSystem,			1 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ "addMessageTextKey",		MissionAddMessageTextKey,	1 },
	{ "addMessageText",			MissionAddMessageText,		1 },
	{ "setBackgroundImage",		MissionSetBackgroundImage,	1 },
	{ "setMusic",				MissionSetMusic,			1 },
	{ "setChoicesKey",			MissionSetChoicesKey,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ "clearMissionScreen",		MissionClearMissionScreen,	0 },
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
			if (result == nil)  result = [NSNull null];
			break;
			
		case kMission_background:
			result = [player getMissionImage];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kMission_shipModel:
			result = [player getMissionShipModel];
			if (result == nil)  result = [NSNull null];
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Mission", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil) *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
	player = OOPlayerForScripting();
	
	switch (JSVAL_TO_INT(name))
	{
		case kMission_choice:
			if (*value == JSVAL_VOID || *value == JSVAL_NULL)  [player resetMissionChoice];
			else  [player setMissionChoice:[NSString stringWithJavaScriptValue:*value inContext:context]];
			break;
		
		case kMission_background:
			// If value can't be converted to a string -- this will clear the background image.
			[player setMissionImage:JSValToNSString(context,*value)];
			break;
		
		case kMission_shipModel:
			// If value can't be converted to a string -- this will clear the ship model.
			[player showShipModel:JSValToNSString(context, *value)];
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Mission", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


// *** Methods ***

// showMissionScreen()
static JSBool MissionShowMissionScreen(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	
	[player setGuiToMissionScreen];
	
	return YES;
}


// showShipModel(modelName : String)
static JSBool MissionShowShipModel(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	//OOReportJSWarning(context, @"The function Mission.showShipModel is deprecated and will be removed in a future version of Oolite.");
	// If argv[0] can't be converted to a string -- e.g., null or undefined -- this will clear the ship model.
	[player showShipModel:JSValToNSString(context,argv[0])];
	
	return YES;
}


// markSystem(systemCoords : String)
static JSBool MissionMarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player addMissionDestination:params];
	
	return YES;
}


// unmarkSystem(systemCoords : String)
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@" " inContext:context];
	[player removeMissionDestination:params];
	
	return YES;
}


// addMessageTextKey(textKey : String)
static JSBool MissionAddMessageTextKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key = JSValToNSString(context,argv[0]);
	[player addMissionText:key];
	
	return YES;
}


// addMessageText(text : String)
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	
	text = JSValToNSString(context,argv[0]);
	[player addLiteralMissionText:text];
	
	return YES;
}


// setBackgroundImage(imageName : String)
static JSBool MissionSetBackgroundImage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	//OOReportJSWarning(context, @"The function Mission.setBackgroundImage is deprecated and will be removed in a future version of Oolite.");
	if (argc >= 1)  key = JSValToNSString(context,argv[0]);
	[player setMissionImage:key];
	
	return YES;
}


// setMusic(musicName : String)
static JSBool MissionSetMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key =  JSValToNSString(context,argv[0]);
	[player setMissionMusic:key];
	
	return YES;
}


// setChoicesKey(choicesKey : String)
static JSBool MissionSetChoicesKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	key = JSValToNSString(context,argv[0]);
	[player setMissionChoices:key];
	
	return YES;
}


// setInstructionsKey(instructionsKey : String [, missionKey : String])
static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	NSString			*missionKey = nil;
	
	key = JSValToNSString(context,argv[0]);
	if ([key isKindOfClass:[NSNull class]])  key = nil;
	
	if (argc > 1)
	{
		missionKey = [NSString stringWithJavaScriptValue:argv[1] inContext:context];
	}
	else
	{
		missionKey = [[OOJSScript currentlyRunningScript] name];
	}
	
	if (key != nil)
	{
		[player setMissionDescription:key forMission:missionKey];
	}
	else
	{
		[player clearMissionDescriptionForMission:missionKey];
	}
	
	return YES;
}


// clearMissionScreen()
static JSBool MissionClearMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	
	[player clearMissionScreen];
	return YES;
}
