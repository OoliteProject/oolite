/*

OOJSMission.m


Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"


static JSBool MissionGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool MissionShowMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionShowShipModel(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionMarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionUnmarkSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionAddMessageText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetBackgroundImage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetChoicesKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetInstructions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionClearMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool MissionRunScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

//  Mission screen  callback varibables
static jsval		callbackFunction;
static OOJSScript	*callbackScript;

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
	kMission_title,				// title of mission screen, string.
	kMission_foreground,		// missionforeground image, string.
	kMission_background,		// mission background image, string.
	kMission_3DModel,		// mission 3D model: role, string.
};


static JSPropertySpec sMissionProperties[] =
{
	// JS name					ID							flags
	{ "choice",					kMission_choice,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }	
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "showMissionScreen",		MissionShowMissionScreen,	0 },
	{ "showShipModel",			MissionShowShipModel,		1 },
	{ "markSystem",				MissionMarkSystem,			1 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ "addMessageText",			MissionAddMessageText,		1 },
	{ "setBackgroundImage",		MissionSetBackgroundImage,	1 },
	{ "setMusic",				MissionSetMusic,			1 },
	{ "setChoicesKey",			MissionSetChoicesKey,		1 },
	{ "setInstructions",		MissionSetInstructions,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ "clearMissionScreen",		MissionClearMissionScreen,	0 },
	{ "runScreen",				MissionRunScreen,			0 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, NULL, 0, sMissionProperties, sMissionMethods, NULL, NULL);
	JS_DefineObject(context, global, "mission", &sMissionClass, missionPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}

void MissionRunCallback()
{
	// don't do anything if we don't have a function, or script.
	if(JSVAL_IS_NULL(callbackFunction) || [callbackScript weakRefUnderlyingObject] == nil)
	{
		return;
	}
	jsval				argval = JSVAL_VOID;
	jsval				rval = JSVAL_VOID;
	jsval				function = callbackFunction;
	PlayerEntity		*player = OOPlayerForScripting();
	OOJavaScriptEngine	*engine  = [OOJavaScriptEngine sharedEngine];
	JSContext			*context = [engine acquireContext];
	
	// don't run the same callback function more than once.
	callbackFunction = JSVAL_NULL;
	argval = [[player missionChoice_string] javaScriptValueInContext:context];
	// now reset the mission choice silently, before calling the callback script.
	[player setMissionChoice:nil withEvent:NO];

	// windows DEP fix: use the underlying object!
	[OOJSScript pushScript:[callbackScript weakRefUnderlyingObject]];
	[engine callJSFunction:function
				 forObject:JSVAL_TO_OBJECT([[callbackScript weakRefUnderlyingObject] javaScriptValueInContext:context])
					  argc:1
					  argv:&argval
					result:&rval];
	[OOJSScript popScript:[callbackScript weakRefUnderlyingObject]];
	[engine releaseContext:context];
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
			OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"choice");
			result = [player missionChoice_string];
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
			OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"choice");
			if (*value == JSVAL_VOID || *value == JSVAL_NULL)  [player resetMissionChoice];
			else  [player setMissionChoice:[NSString stringWithJavaScriptValue:*value inContext:context]];
			break;
		
		case kMission_title:
			[player setMissionTitle:JSValToNSString(context,*value)];
			break;
		
		case kMission_foreground:
			// If value can't be converted to a string this will clear the foreground image.
			[player setMissionImage:JSValToNSString(context,*value)];
			break;
		
		case kMission_3DModel:
			// If value can't be converted to a string this will clear the entity (ship) model.
			[player showShipModel:JSValToNSString(context, *value)];
			break;
		
		case kMission_background:
			// If value can't be converted to a string this will clear the background image.
			[player setMissionBackground:JSValToNSString(context,*value)];
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
	
	OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"showMissionScreen");
	[player setGuiToMissionScreen];
	
	return YES;
}


// showShipModel(modelName : String)
static JSBool MissionShowShipModel(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	PlayerEntity		*player = OOPlayerForScripting();
	
	OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"showShipModel");
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
	
	OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"setBackgroundImage");
	// set the foremost background image - backward compatible.
	if (argc >= 1)  key = JSValToNSString(context,argv[0]);
	[player setMissionImage:key];
	
	return YES;
}


// setMusic(musicName : String)
static JSBool MissionSetMusic(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	if (![@"noWarning" isEqualTo:JSValToNSString(context,*outResult)])
		OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"setMusic");
	
	key =  JSValToNSString(context,argv[0]);
	[player setMissionMusic:key];
	
	return YES;
}


// setChoicesKey(choicesKey : String)
static JSBool MissionSetChoicesKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*key = nil;
	
	if (![@"noWarning" isEqualTo:JSValToNSString(context,*outResult)])
		OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"setChoicesKey");
	
	key = JSValToNSString(context,argv[0]);
	[player setMissionChoices:key];
	
	return YES;
}


static JSBool MissionSetInstructionsKey(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	*outResult = [@"textKey" javaScriptValueInContext:context];
	return MissionSetInstructions(context, this, argc, argv, outResult);
}


// setInstructions(instructions: String [, missionKey : String])
static JSBool MissionSetInstructions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	NSString			*missionKey = nil;
	
	text = JSValToNSString(context,argv[0]);
	if ([text isKindOfClass:[NSNull class]])  text = nil;
	
	if (argc > 1)
	{
		missionKey = [NSString stringWithJavaScriptValue:argv[1] inContext:context];
	}
	else
	{
		missionKey = [[OOJSScript currentlyRunningScript] name];
	}
	
	if (text != nil)
	{
		if ([@"textKey" isEqualTo:JSValToNSString(context,*outResult)])
			[player setMissionDescription:text forMission:missionKey];
		else
			[player setMissionInstructions:text forMission:missionKey];
	}
	else
	{
		[player clearMissionDescriptionForMission:missionKey];
	}
	
	*outResult = JSVAL_VOID;	
	return YES;
}


// clearMissionScreen()
static JSBool MissionClearMissionScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	
	OOReportJSWarning(context, @"Mission.%@ is deprecated and will be removed in a future version of Oolite.", @"clearMissionScreen");
	[player clearMissionScreen];
	return YES;
}


// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
static JSBool MissionRunScreen(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	PlayerEntity		*player = OOPlayerForScripting();
	jsval				function = JSVAL_NULL;
	jsval				value = JSVAL_NULL;
	jsval				noWarning = [@"noWarning" javaScriptValueInContext:context];
	JSObject			*params = JS_NewObject(context, NULL, NULL, NULL);;
	NSString			*str;
	
	if ([player guiScreen] == GUI_SCREEN_INTRO1 || [player guiScreen] == GUI_SCREEN_INTRO2)
	{
		*outResult = BOOLToJSVal(NO);
		return YES;
	}
	
	if (argc>0) {
		if (!JSVAL_IS_NULL(argv[0]) && !JSVAL_IS_VOID(argv[0]) && !JSVAL_IS_OBJECT(argv[0]))
		{
			OOReportJSBadArguments(context, @"Mission", @"runScreen", 1, argv, @"Invalid argument", @"object");
			return NO;
		}
		
		if (!JSVAL_IS_NULL(argv[0]) && !JSVAL_IS_VOID(argv[0]) && JSVAL_IS_OBJECT(argv[0])) params = JSVAL_TO_OBJECT(argv[0]);
	}
	
	if (argc > 1) function = argv[1];
	if (!JSVAL_IS_OBJECT(function) || (!JSVAL_IS_NULL(function) && !JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(function))))
	{
		OOReportJSBadArguments(context, @"Mission", @"runScreen", 1, argv + 1, @"Invalid argument", @"function");
		return NO;
	}
	
	str=@"title";
	if (JS_GetProperty(context, params, [str UTF8String], &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_title), &value);
	else
	{
		str=@"titleKey";
		if (JS_GetProperty(context, params, [str UTF8String], &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
		{
			str = [[UNIVERSE missiontext] oo_stringForKey:JSValToNSString(context, value)];
			str = ExpandDescriptionForCurrentSystem(str);
			str = [player replaceVariablesInString:str];
			[player setMissionTitle:str];
		}
	}
	
	str=@"music";
	if (JS_GetProperty(context, params, [str UTF8String], &value))
		MissionSetMusic(context, this, 1, &value, &noWarning);
	
	str=@"foreground";
	if (JS_GetProperty(context, params, [str UTF8String], &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_foreground), &value);
	
	str=@"model";
	if (JS_GetProperty(context, params, [str UTF8String], &value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_3DModel), &value);
	
	str=@"background";
	if (JS_GetProperty(context, params, [str UTF8String], &value))
		MissionSetProperty(context, this, INT_TO_JSVAL(kMission_background), &value);
	
	callbackFunction = function;
	[player setGuiToMissionScreenWithCallback:!JSVAL_IS_NULL(function)]; 
	if (!JSVAL_IS_NULL(function))
	{
		callbackScript = [[OOJSScript currentlyRunningScript] weakRetain];
	}
		
	str=@"message";
	if (JS_GetProperty(context, params, [str UTF8String], &value) && !JSVAL_IS_NULL(value) && !JSVAL_IS_VOID(value))
		[player addLiteralMissionText: JSValToNSString(context, value)];
	else
	{
		str=@"messageKey";
		if (JS_GetProperty(context, params, [str UTF8String], &value))
			[player addMissionText: JSValToNSString(context, value)];
	}
	
	str=@"choicesKey";
	if (JS_GetProperty(context, params, [str UTF8String], &value))
		MissionSetChoicesKey(context, this, 1, &value, &noWarning);
	
	// now clean up!
	value = JSVAL_NULL;
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_foreground), &value);
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_background), &value);
	MissionSetProperty(context, this, INT_TO_JSVAL(kMission_title), &value);
	MissionSetMusic(context, this, 1, &value, &noWarning);
	
	*outResult = BOOLToJSVal(YES);
	return YES;
}
