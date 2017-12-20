/*

OOJSMission.m


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

#import "OOJSMission.h"
#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"
#import "OOConstToJSString.h"
#import "OOJSVector.h"

#import "OOJSPlayer.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringExpander.h"
#import "OOCollectionExtractors.h"
#import "OOMusicController.h"
#import "GuiDisplayGen.h"
#import "OODebugStandards.h"

static JSBool MissionGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool MissionMarkSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionUnmarkSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionAddMessageText(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionSetInstructions(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionSetInstructionsKey(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionRunScreen(JSContext *context, uintN argc, jsval *vp);
static JSBool MissionRunShipLibrary(JSContext *context, uintN argc, jsval *vp);

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
	MissionGetProperty,
	MissionSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	kMission_markedSystems,
	kMission_screenID,
	kMission_exitScreen
};


static JSPropertySpec sMissionProperties[] = 
{
	// JS name					ID								flags
	{ "markedSystems", kMission_markedSystems, OOJS_PROP_READONLY_CB },
	{ "screenID", kMission_screenID, OOJS_PROP_READONLY_CB },
	{ "exitScreen", kMission_exitScreen, OOJS_PROP_READWRITE_CB },
	{ 0 }
};


static JSFunctionSpec sMissionMethods[] =
{
	// JS name					Function					min args
	{ "addMessageText",			MissionAddMessageText,		1 },
	{ "markSystem",				MissionMarkSystem,			1 },
	{ "runScreen",				MissionRunScreen,			1 }, // the callback function is optional!
	{ "setInstructions",		MissionSetInstructions,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ "runShipLibrary",			MissionRunShipLibrary,		0 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	sCallbackFunction = JSVAL_NULL;
	sCallbackThis = JSVAL_NULL;
	
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, OOJSUnconstructableConstruct, 0, sMissionProperties, sMissionMethods, NULL, NULL);
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
	@try
	{
		[OOJSScript pushScript:cbScript];
		[engine callJSFunction:cbFunction
					 forObject:cbThis
						  argc:1
						  argv:&argval
						result:&rval];
	}
	@catch (NSException *exception)
	{
		// Squash any exception, allow cleanup to happen and so forth.
		OOLog(kOOLogException, @"Ignoring exception %@:%@ during handling of mission screen completion callback.", [exception name], [exception reason]);
	}
	[OOJSScript popScript:cbScript];
	
	// Manage that memory.
	[cbScript release];
	JS_RemoveValueRoot(context, &cbFunction);
	JS_RemoveObjectRoot(context, &cbThis);
	
	OOJSRelinquishContext(context);
}


static JSBool MissionGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value) 
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)

	id result = nil;
	PlayerEntity		*player = OOPlayerForScripting();

	switch (JSID_TO_INT(propID))
	{
		case kMission_markedSystems:
			result = [player getMissionDestinations];
			if (result == nil)  result = [NSDictionary dictionary];
			result = [result allValues];
			break;

		case kMission_screenID:
			result = [player missionScreenID];
			break;

		case kMission_exitScreen:
			*value = OOJSValueFromGUIScreenID(context, [player missionExitScreen]);
			return YES;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sMissionProperties);
			return NO;
	}

	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	OOGUIScreenID exitScreen;
	PlayerEntity		*player = OOPlayerForScripting();

	switch (JSID_TO_INT(propID))
	{
		case kMission_exitScreen:
			exitScreen = OOGUIScreenIDFromJSValue(context, *value);
			[player setMissionExitScreen:exitScreen];
			return YES;
	
		default:
			OOJSReportBadPropertySelector(context, this, propID, sMissionProperties);
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sMissionProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
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
			OOStandardsDeprecated(@"Use of numbers for mission.markSystem is deprecated");
			if (!OOEnforceStandards())
			{
				[player addMissionDestinationMarker:[player defaultMarker:dest]];
			}
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

	BOOL result = YES;
	for (i=0;i<argc;i++)
	{
		if (JS_ValueToInt32(context, OOJS_ARGV[i], &dest)) 
		{
			OOStandardsDeprecated(@"Use of numbers for mission.unmarkSystem is deprecated");
			if (!OOEnforceStandards())
			{
				if (![player removeMissionDestinationMarker:[player defaultMarker:dest]]) {
					result = NO;
				}
			}
		}
		else // must be object, from above
		{
			JS_ClearPendingException(context); // or JS_ValueToInt32 exception crashes JS engine
			NSDictionary *marker = OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(OOJS_ARGV[i]));
			OOSystemID system = [marker oo_intForKey:@"system" defaultValue:-1];
			if (system >= 0)
			{
				if (![player removeMissionDestinationMarker:marker]) {
					result = NO;
				}
			}
		}
	}
	
	OOJS_RETURN_BOOL(result);
	
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
		OOJS_RETURN_VOID;
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
	NSArray				*texts = nil;
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
	else if (!JSVAL_IS_NULL(OOJS_ARGV[0]) && JSVAL_IS_OBJECT(OOJS_ARGV[0]))
	{
		texts = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[0]);
	}
	else
	{
		text = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	
	if (argc > 1)
	{
		missionKey = OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[1]);
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
	else if (texts != nil && !isKey)
	{
		[player setMissionInstructionsList:texts forMission:missionKey];
	}
	else
	{
		[player clearMissionDescriptionForMission:missionKey];
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


static NSDictionary *GetParameterDictionary(JSContext *context, JSObject *object, const char *key)
{
	jsval value = JSVAL_NULL;
	if (JS_GetProperty(context, object, key, &value))
	{
		if (JSVAL_IS_OBJECT(value))
		{
			return OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(value));
		}
	}
	return nil;
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
	if ([player status] == STATUS_START_GAME)
	{
		// (though no JS should be loaded at this stage, so this
		// check may be obsolete - CIM)
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

		/* CIM 30/12/12: This following line causes problems in certain
		 * cases, but has to be kept for backward
		 * compatibility. Documenting the third argument of
		 * mission.runScreen will at least help people get around it in
		 * multi-world-script mission screens. (Though, since no-one has
		 * complained yet, perhaps I'm the only one who uses them?) */

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
				[player setMissionTitle:OOExpand(message)];
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
	[player setMissionBackgroundSpecial:GetParameterString(context, params, "backgroundSpecial")];

	if (JS_GetProperty(context, params, "customChartZoom", &value) && !JSVAL_IS_VOID(value))
	{
		jsdouble zoom;
		if (JS_ValueToNumber(context, value, &zoom))
		{
			if (zoom >= 1 && zoom <= CHART_MAX_ZOOM)
			{
				[player setCustomChartZoom:zoom];
			}
			else 
			{
				OOJSReportWarning(context, @"Mission.runScreen: invalid customChartZoom value specified.");
				[player setCustomChartZoom:1];
			}
		}
	}
	if (JS_GetProperty(context, params, "customChartCentre", &value) && !JSVAL_IS_VOID(value))
	{
		Vector vValue;
		if (JSValueToVector(context, value, &vValue))
		{
			NSPoint coords = { vValue.x, vValue.y };
			[player setCustomChartCentre:coords];
		}
		else 
		{
			[player setCustomChartCentre:[player galaxy_coordinates]];
			OOJSReportWarning(context, @"Mission.runScreen: invalid value for customChartCentre. Must be valid vector. Defaulting to current location.");
		}
	}
	if (JS_GetProperty(context, params, "customChartCentreInLY", &value) && !JSVAL_IS_VOID(value))
	{
		Vector vValue;
		if (JSValueToVector(context, value, &vValue))
		{
			NSPoint coords = OOInternalCoordinatesFromGalactic(vValue);
			[player setCustomChartCentre:coords];
		}
		else 
		{
			[player setCustomChartCentre:[player galaxy_coordinates]];
			OOJSReportWarning(context, @"Mission.runScreen: invalid value for customChartCentreInLY. Must be valid vector. Defaulting to current location.");
		}
	}

	[UNIVERSE removeDemoShips];	// remove any demoship or miniature planet that may be remaining from previous screens
	
	if ([player status] == STATUS_IN_FLIGHT)
	{
		OOStandardsError(@"Mission screens should not be used while in flight");
		if (OOEnforceStandards())
		{
			return NO;
		}
	}

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

	JSBool allowInterrupt = NO;
	if (JS_GetProperty(context, params, "allowInterrupt", &value) && !JSVAL_IS_VOID(value))
	{
		JS_ValueToBoolean(context, value, &allowInterrupt);
	}

	if (JS_GetProperty(context, params, "exitScreen", &value) && !JSVAL_IS_VOID(value))
	{
		[player setMissionExitScreen:OOGUIScreenIDFromJSValue(context, value)];
	}
	else
	{
		[player setMissionExitScreen:GUI_SCREEN_STATUS];
	}

	if (JS_GetProperty(context, params, "screenID", &value) && !JSVAL_IS_VOID(value))
	{
		[player setMissionScreenID:OOStringFromJSValue(context, value)];
	}
	else
	{
		[player clearMissionScreenID];
	}

	JSBool textEntry = NO;
	if (JS_GetProperty(context, params, "textEntry", &value) && !JSVAL_IS_VOID(value))
	{
		JS_ValueToBoolean(context, value, &textEntry);
	}
	if (textEntry)
	{
		[player setMissionChoiceByTextEntry:YES];
	}
	else
	{
		[player setMissionChoiceByTextEntry:NO];
	}

	// Start the mission screen.
	sCallbackFunction = function;
	[player setGuiToMissionScreenWithCallback:!JSVAL_IS_NULL(sCallbackFunction)];

	// Apply more settings. (These must be done after starting the screen for legacy reasons.)
	if (allowInterrupt)
	{
		[player allowMissionInterrupt];
	}
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
	
	if (!textEntry)
	{
		NSDictionary *choices = GetParameterDictionary(context, params, "choices");
		if (choices == nil)
		{
			[player setMissionChoices:GetParameterString(context, params, "choicesKey")];
		}
		else 
		{
			[player setMissionChoicesDictionary:choices];		
		}
	}

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


static JSBool MissionRunShipLibrary(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity	*player = OOPlayerForScripting();
	BOOL			OK = YES;
	if ([player status] != STATUS_DOCKED)
	{
		OOJSReportWarning(context, @"Mission.runShipLibrary: must be docked.");
		OK = NO;
	}
	else
	{
		[PLAYER setGuiToIntroFirstGo:NO];
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


