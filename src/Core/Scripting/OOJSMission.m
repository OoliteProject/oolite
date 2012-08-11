/*

OOJSMission.m


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

#import "OOJSMission.h"
#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"

#import "OOJSPlayer.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOMusicController.h"
#import "GuiDisplayGen.h"


static JSBool MissionMarkSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionMarkedSystems(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionUnmarkSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionAddMessageText(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionSetInstructions(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionSetInstructionsKey(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionRunScreen(JSContext *context, uintN argc, jsval *vp);

static JSBool MissionSetInstructionsInternal(JSContext *context, uintN argc, jsval *vp, BOOL isKey);

//  Mission screen  callback varibables
static jsval			sCallbackFunction;
static jsval			sCallbackThis;
static OOJSScript		*sCallbackScript = nil;

static JSObject			*sMissionObject;

static JSClass sMissionClass =
{
	"Mission",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_StrictPropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "addMessageText",			MissionAddMessageText,		1 },
	{ "markSystem",				MissionMarkSystem,			1 },
	{ "markedSystems",				MissionMarkedSystems,			1 },
	{ "runScreen",				MissionRunScreen,			1 }, // the callback function is optional!
	{ "setInstructions",		MissionSetInstructions,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	sCallbackFunction = JSVAL_NULL;
	sCallbackThis = JSVAL_NULL;
	
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, OOJSUnconstructableConstruct, 0, NULL, sMissionMethods, NULL, NULL);
	sMissionObject = JS_DefineObject(context, global, "mission", &sMissionClass, missionPrototype, OOJS_PROP_READONLY);
	
	// Ensure JS objects are rooted.
	OOJSAddGCValueRoot(context, &sCallbackFunction, "Pending mission callback function");
	OOJSAddGCValueRoot(context, &sCallbackThis, "Pending mission callback this");
}


void MissionRunCallback()
{
	// don't do anything if we don't have a function.
	if (JSVAL_IS_NULL(sCallbackFunction) || JSVAL_IS_VOID(sCallbackFunction))  return;
	
	jsval				argval = JSVAL_VOID;
	jsval				rval = JSVAL_VOID;
	PlayerEntity		*player = OOPlayerForScripting();
	OOJavaScriptEngine	*engine  = [OOJavaScriptEngine sharedEngine];
	JSContext			*context = OOJSAcquireContext();
	
	/*	Create temporarily-rooted local copies of sCallbackFunction and
		sCallbackThis, then clear the statics. This must be done in advance
		since the callback might call runScreen() and clobber the statics.
	*/
	jsval				cbFunction = JSVAL_VOID;
	JSObject			*cbThis = NULL;
	OOJSScript			*cbScript = sCallbackScript;
	
	OOJSAddGCValueRoot(context, &cbFunction, "Mission callback function");
	OOJSAddGCObjectRoot(context, &cbThis, "Mission callback this");
	cbFunction = sCallbackFunction;
	cbScript = sCallbackScript;
	JS_ValueToObject(context, sCallbackThis, &cbThis);
	
	sCallbackScript = nil;
	sCallbackFunction = JSVAL_NULL;
	sCallbackThis = JSVAL_NULL;
	
	argval = OOJSValueFromNativeObject(context, [player missionChoice_string]);
	// now reset the mission choice silently, before calling the callback script.
	[player setMissionChoice:nil withEvent:NO];
	
	// Call the callback.
	NS_DURING
		[OOJSScript pushScript:cbScript];
		[engine callJSFunction:cbFunction
					 forObject:cbThis
						  argc:1
						  argv:&argval
						result:&rval];
	NS_HANDLER
		// Squash any exception, allow cleanup to happen and so forth.
		OOLog(kOOLogException, @"Ignoring exception %@:%@ during handling of mission screen completion callback.", [localException name], [localException reason]);
	NS_ENDHANDLER
	[OOJSScript popScript:cbScript];
	
	// Manage that memory.
	[cbScript release];
	JS_RemoveValueRoot(context, &cbFunction);
	JS_RemoveObjectRoot(context, &cbThis);
	
	OOJSRelinquishContext(context);
}


// *** Methods ***

// markSystem(integer+)
static JSBool MissionMarkSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	unsigned i;
	int dest;

	// two pass. Once to validate, once to apply if they validate
	for (i=0;i<argc;i++)
	{
		if (!JS_ValueToInt32(context, OOJS_ARGV[i], &dest)) 
		{
			JS_ClearPendingException(context); // or JS_ValueToInt32 exception crashes JS engine
			if (!JSVAL_IS_OBJECT(OOJS_ARGV[i]))
			{
				OOJSReportBadArguments(context, @"Mission", @"markSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"numbers or objects");
				return NO;
			}
		}
	}

	for (i=0;i<argc;i++)
	{
		if (JS_ValueToInt32(context, OOJS_ARGV[i], &dest)) 
		{
			[player addMissionDestinationMarker:[player defaultMarker:dest]];
		}
		else // must be object, from above
		{
			JS_ClearPendingException(context); // or JS_ValueToInt32 exception crashes JS engine
			NSDictionary *marker = OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(OOJS_ARGV[i]));
			OOSystemID system = [marker oo_intForKey:@"system" defaultValue:-1];
			if (system >= 0)
			{
				[player addMissionDestinationMarker:marker];
			}
		}
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// unmarkSystem(integer+)
static JSBool MissionUnmarkSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	unsigned i;
	int dest;

	// two pass. Once to validate, once to apply if they validate
	for (i=0;i<argc;i++)
	{
		if (!JS_ValueToInt32(context, OOJS_ARGV[i], &dest)) 
		{
			JS_ClearPendingException(context); // or JS_ValueToInt32 exception crashes JS engine
			if (!JSVAL_IS_OBJECT(OOJS_ARGV[i]))
			{
				OOJSReportBadArguments(context, @"Mission", @"unmarkSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"numbers or objects");
				return NO;
			}
		}
	}

	for (i=0;i<argc;i++)
	{
		if (JS_ValueToInt32(context, OOJS_ARGV[i], &dest)) 
		{
			[player removeMissionDestinationMarker:[player defaultMarker:dest]];
		}
		else // must be object, from above
		{
			JS_ClearPendingException(context); // or JS_ValueToInt32 exception crashes JS engine
			NSDictionary *marker = OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(OOJS_ARGV[i]));
			OOSystemID system = [marker oo_intForKey:@"system" defaultValue:-1];
			if (system >= 0)
			{
				[player removeMissionDestinationMarker:marker];
			}
		}
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// addMessageText(text : String)
static JSBool MissionAddMessageText(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	
	if (EXPECT_NOT(argc == 0))
	{
#if 0
		// EMMSTRAN: fail.
		OOJSReportBadArguments(context, @"Mission", @"addMessageText", argc, OOJS_ARGV, nil, @"string");
		return NO;
#else
		OOJS_RETURN_VOID;
#endif
	}
	
	// Found "FIXME: warning if no mission screen running.",,,
	// However: used routinely by the Constrictor mission in F7, without mission screens.
	text = OOStringFromJSValue(context, OOJS_ARGV[0]);
	[player addLiteralMissionText:text];
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setInstructionsKey(instructionsKey: String [, missionKey : String])
static JSBool MissionSetInstructionsKey(JSContext *context, uintN argc, jsval *vp)
{
	return MissionSetInstructionsInternal(context, argc, vp, YES);
}


// setInstructions(instructions: String [, missionKey : String])
static JSBool MissionSetInstructions(JSContext *context, uintN argc, jsval *vp)
{
	return MissionSetInstructionsInternal(context, argc, vp, NO);
}


static JSBool MissionSetInstructionsInternal(JSContext *context, uintN argc, jsval *vp, BOOL isKey)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	NSString			*missionKey = nil;
	
	if (EXPECT_NOT(argc == 0))
	{
		OOJSReportWarning(context, @"Usage error: mission.%@() called with no arguments. Treating as Mission.%@(null). This call may fail in a future version of Oolite.", isKey ? @"setInstructionsKey" : @"setInstructions", isKey ? @"setInstructionsKey" : @"setInstructions");
	}
	else if (EXPECT_NOT(JSVAL_IS_VOID(OOJS_ARGV[0])))
	{
		OOJSReportBadArguments(context, @"Mission", isKey ? @"setInstructionsKey" : @"setInstructions", 1, OOJS_ARGV, NULL, @"string or null");
		return NO;
	}
	else  text = OOStringFromJSValue(context, OOJS_ARGV[0]);
	
	if (argc > 1)
	{
		missionKey = [NSString stringWithJavaScriptValue:OOJS_ARGV[1] inContext:context];
	}
	else
	{
		missionKey = [[OOJSScript currentlyRunningScript] name];
	}
	
	if (text != nil)
	{
		if (isKey)
		{
			[player setMissionDescription:text forMission:missionKey];
		}
		else
		{
			[player setMissionInstructions:text forMission:missionKey];
		}
	}
	else
	{
		[player clearMissionDescriptionForMission:missionKey];
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


static NSString *GetParameterString(JSContext *context, JSObject *object, const char *key)
{
	jsval value = JSVAL_NULL;
	if (JS_GetProperty(context, object, key, &value))
	{
		return OOStringFromJSValue(context, value);
	}
	return nil;
}


static NSDictionary *GetParameterImageDescriptor(JSContext *context, JSObject *object, const char *key)
{
	jsval value = JSVAL_NULL;
	if (JS_GetProperty(context, object, key, &value))
	{
		return [[UNIVERSE gui] textureDescriptorFromJSValue:value inContext:context callerDescription:@"mission.runScreen()"];
	}
	else
	{
		return nil;
	}
}


// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
static JSBool MissionRunScreen(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	jsval				function = JSVAL_NULL;
	jsval				value = JSVAL_NULL;
	JSObject			*params = NULL;
	
	// No mission screens during intro.
	if ([player guiScreen] == GUI_SCREEN_INTRO1 || [player guiScreen] == GUI_SCREEN_INTRO2)
	{
		OOJS_RETURN_BOOL(NO);
	}
	
	// Validate arguments.
	if (argc < 1 || !JS_ValueToObject(context, OOJS_ARGV[0], &params))
	{
		OOJSReportBadArguments(context, @"mission", @"runScreen", MIN(argc, 1U), &OOJS_ARGV[0], nil, @"parameter object");
		return NO;
	}
	
	if (argc > 1)  function = OOJS_ARGV[1];
	if (!JSVAL_IS_NULL(function) && !OOJSValueIsFunction(context, function))
	{
		OOJSReportBadArguments(context, @"mission", @"runScreen", 1, &OOJS_ARGV[1], nil, @"function");
		return NO;
	}
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	if (!JSVAL_IS_NULL(function))
	{
		sCallbackScript = [[[OOJSScript currentlyRunningScript] weakRefUnderlyingObject] retain];
		if (argc > 2)
		{
			sCallbackThis = OOJS_ARGV[2];
		}
		else
		{
			sCallbackThis = OOJSValueFromNativeObject(context, sCallbackScript);
		}
	}
	
	// Apply settings.
	if (JS_GetProperty(context, params, "title", &value) && !JSVAL_IS_VOID(value))
	{
		[player setMissionTitle:OOStringFromJSValue(context, value)];
	}
	else
	{
		NSString *titleKey = GetParameterString(context, params, "titleKey");
		if (titleKey != nil)
		{
			NSString *message = [[UNIVERSE missiontext] oo_stringForKey:titleKey];
			if (message != nil)
			{
				message = ExpandDescriptionForCurrentSystem(message);
				message = [player replaceVariablesInString:message];
				[player setMissionTitle:message];
			}
			else
			{
				OOJSReportWarning(context, @"Mission.runScreen: titleKey '%@' has no entry in missiontext.plist.", titleKey);
			}
		}
	}
	
	[[OOMusicController	sharedController] setMissionMusic:GetParameterString(context, params, "music")];
	[player setMissionOverlayDescriptor:GetParameterImageDescriptor(context, params, "overlay")];
	[player setMissionBackgroundDescriptor:GetParameterImageDescriptor(context, params, "background")];
	
	[UNIVERSE removeDemoShips];	// remove any demoship or miniature planet that may be remaining from previous screens
	
	ShipEntity *demoShip = nil;
	if (JS_GetProperty(context, params, "model", &value) && !JSVAL_IS_VOID(value))
	{
		if ([player status] == STATUS_IN_FLIGHT && JSVAL_IS_STRING(value))
		{
			OOJSReportWarning(context, @"Mission.runScreen: model cannot be displayed while in flight.");
		}
		else
		{
			NSString *role = OOStringFromJSValue(context, value);
			
			JSBool spinning = YES;
			if (JS_GetProperty(context, params, "spinModel", &value) && !JSVAL_IS_VOID(value))
			{
				JS_ValueToBoolean(context, value, &spinning);
			}
			
		//	[player showShipModel:OOStringFromJSValue(context, value)];
			demoShip = [UNIVERSE makeDemoShipWithRole:role spinning:spinning];
		}
	}
	if (demoShip != nil)
	{
		if (JS_GetProperty(context, params, "modelPersonality", &value) && !JSVAL_IS_VOID(value))
		{
			int personality = 0;
			JS_ValueToInt32(context,value,&personality);
			[demoShip setEntityPersonalityInt:personality];
		}
		jsval demoShipVal = [demoShip oo_jsValueInContext:context];
		JS_SetProperty(context, sMissionObject, "displayModel", &demoShipVal);
	}
	else
	{
		JS_DeleteProperty(context, sMissionObject, "displayModel");
	}

	
	// Start the mission screen.
	sCallbackFunction = function;
	[player setGuiToMissionScreenWithCallback:!JSVAL_IS_NULL(sCallbackFunction)];
	
	// Apply more settings. (These must be done after starting the screen for legacy reasons.)
	NSString *message = GetParameterString(context, params, "message");
	if (message != nil)
	{
		[player addLiteralMissionText:message];
	}
	else
	{
		NSString *messageKey = GetParameterString(context, params, "messageKey");
		if (messageKey != nil)  [player addMissionText:messageKey];
	}
	
	[player setMissionChoices:GetParameterString(context, params, "choicesKey")];
	NSString *firstKey = GetParameterString(context, params, "initialChoicesKey");
	if (firstKey != nil)
	{
		OOGUIRow row = [[UNIVERSE gui] rowForKey:firstKey];
		if (row != -1)
		{
			[[UNIVERSE gui] setSelectedRow:row];
		}
	}
	
	// now clean up!
	[player setMissionOverlayDescriptor:nil];
	[player setMissionBackgroundDescriptor:nil];
	[player setMissionTitle:nil];
	[player setMissionMusic:nil];
	
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(YES);
	
	OOJS_NATIVE_EXIT
}


//getShaders()
static JSBool MissionMarkedSystems(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	PlayerEntity		*player = PLAYER;
	NSObject		*result = nil;
	
	result = [player getMissionDestinations];
	if (result == nil)  result = [NSDictionary dictionary];
	OOJS_RETURN_OBJECT(result);
	
	OOJS_PROFILE_EXIT
}
