/*

OOJSMission.m


Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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


static JSBool MissionMarkSystem(OOJS_NATIVE_ARGS);
static JSBool MissionUnmarkSystem(OOJS_NATIVE_ARGS);
static JSBool MissionAddMessageText(OOJS_NATIVE_ARGS);
static JSBool MissionSetInstructions(OOJS_NATIVE_ARGS);
static JSBool MissionSetInstructionsKey(OOJS_NATIVE_ARGS);
static JSBool MissionRunScreen(OOJS_NATIVE_ARGS);

static JSBool MissionSetInstructionsInternal(OOJS_NATIVE_ARGS, BOOL isKey);

//  Mission screen  callback varibables
static jsval			sCallbackFunction;
static jsval			sCallbackThis;
static OOJSScript		*sCallbackScript = nil;

static JSClass sMissionClass =
{
	"Mission",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
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
	{ "unmarkSystem",			MissionUnmarkSystem,		1 },
	{ "runScreen",				MissionRunScreen,			1 }, // the callback function is optional!
	{ "setInstructions",		MissionSetInstructions,		1 },
	{ "setInstructionsKey",		MissionSetInstructionsKey,	1 },
	{ 0 }
};


void InitOOJSMission(JSContext *context, JSObject *global)
{
	sCallbackFunction = JSVAL_NULL;
	sCallbackThis = JSVAL_NULL;
	
	JSObject *missionPrototype = JS_InitClass(context, global, NULL, &sMissionClass, OOJSUnconstructableConstruct, 0, NULL, sMissionMethods, NULL, NULL);
	JS_DefineObject(context, global, "mission", &sMissionClass, missionPrototype, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	
	// Ensure JS objects are rooted.
	OOJSAddGCValueRoot(context, &sCallbackFunction, "Pending mission callback function");
	OOJSAddGCValueRoot(context, &sCallbackThis, "Pending mission callback this");
}


void MissionRunCallback()
{
	// don't do anything if we don't have a function.
	if (JSVAL_IS_NULL(sCallbackFunction))  return;
	
	jsval				argval = JSVAL_VOID;
	jsval				rval = JSVAL_VOID;
	PlayerEntity		*player = OOPlayerForScripting();
	OOJavaScriptEngine	*engine  = [OOJavaScriptEngine sharedEngine];
	JSContext			*context = [engine acquireContext];
	
	/*	Create temporarily-rooted local copies of sCallbackFunction and
		sCallbackThis, then clear the statics. This must be done in advance
		since the callback might call runScreen() and clobber the statics.
	*/
	jsval				cbFunction = JSVAL_VOID;
	JSObject			*cbThis = NULL;
	OOJSScript			*cbScript = sCallbackScript;
	
	JS_BeginRequest(context);
	
	OOJSAddGCValueRoot(context, &cbFunction, "Mission callback function");
	OOJSAddGCObjectRoot(context, &cbThis, "Mission callback this");
	cbFunction = sCallbackFunction;
	cbScript = sCallbackScript;
	JS_ValueToObject(context, sCallbackThis, &cbThis);
	
	sCallbackScript = nil;
	sCallbackFunction = JSVAL_VOID;
	sCallbackThis = JSVAL_VOID;
	
	argval = [[player missionChoice_string] oo_jsValueInContext:context];
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
	
	JS_EndRequest(context);
	[engine releaseContext:context];
}


// *** Methods ***

// markSystem(systemCoords : String)
static JSBool MissionMarkSystem(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:OOJS_ARGV count:argc separator:@" " inContext:context];
	[player addMissionDestination:params];
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// unmarkSystem(systemCoords : String)
static JSBool MissionUnmarkSystem(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*params = nil;
	
	params = [NSString concatenationOfStringsFromJavaScriptValues:OOJS_ARGV count:argc separator:@" " inContext:context];
	[player removeMissionDestination:params];
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// addMessageText(text : String)
static JSBool MissionAddMessageText(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	
	// Found "FIXME: warning if no mission screen running.",,,
	// However: used routinely by the Constrictor mission in F7, without mission screens.
	text = OOStringFromJSValue(context, OOJS_ARG(0));
	[player addLiteralMissionText:text];
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setInstructionsKey(instructionsKey: String [, missionKey : String])
static JSBool MissionSetInstructionsKey(OOJS_NATIVE_ARGS)
{
	return MissionSetInstructionsInternal(OOJS_NATIVE_CALLTHROUGH, YES);
}


// setInstructions(instructions: String [, missionKey : String])
static JSBool MissionSetInstructions(OOJS_NATIVE_ARGS)
{
	return MissionSetInstructionsInternal(OOJS_NATIVE_CALLTHROUGH, NO);
}


static JSBool MissionSetInstructionsInternal(OOJS_NATIVE_ARGS, BOOL isKey)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity		*player = OOPlayerForScripting();
	NSString			*text = nil;
	NSString			*missionKey = nil;
	
	if (argc == 0)
	{
		OOJSReportWarning(context, @"Usage error: mission.%@() called with no arguments. Treating as Mission.%@(null). This call may fail in a future version of Oolite.", isKey ? @"setInstructionsKey" : @"setInstructions", isKey ? @"setInstructionsKey" : @"setInstructions");
	}
	else if (JSVAL_IS_VOID(OOJS_ARG(0)))
	{
		OOJSReportBadArguments(context, @"Mission", isKey ? @"setInstructionsKey" : @"setInstructions", 1, OOJS_ARGV, NULL, @"string or null");
		return NO;
	}
	else  text = OOStringFromJSValue(context, OOJS_ARG(0));
	
	if (argc > 1)
	{
		missionKey = [NSString stringWithJavaScriptValue:OOJS_ARG(1) inContext:context];
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


OOINLINE NSString *GetParameterString(JSContext *context, JSObject *object, const char *key)
{
	jsval value = JSVAL_NULL;
	if (JS_GetProperty(context, object, key, &value))
	{
		return OOStringFromJSValue(context, value);
	}
	return nil;
}


// runScreen(params: dict, callBack:function) - if the callback function is null, emulate the old style runMissionScreen
static JSBool MissionRunScreen(OOJS_NATIVE_ARGS)
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
	if (!JSVAL_IS_OBJECT(OOJS_ARG(0)) || JSVAL_IS_NULL(OOJS_ARG(0)))
	{
		OOJSReportBadArguments(context, @"mission", @"runScreen", argc, OOJS_ARGV, nil, @"parameter object");
		return NO;
	}
	params = JSVAL_TO_OBJECT(OOJS_ARG(0));
	
	if (argc > 1) function = OOJS_ARG(1);
	if (!JSVAL_IS_NULL(function) && !OOJSValueIsFunction(context, function))
	{
		OOJSReportBadArguments(context, @"mission", @"runScreen", argc - 1, OOJS_ARGV + 1, nil, @"function");
		return NO;
	}
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	if (!JSVAL_IS_NULL(function))
	{
		sCallbackScript = [[[OOJSScript currentlyRunningScript] weakRefUnderlyingObject] retain];
		if (argc > 2)
		{
			sCallbackThis = OOJS_ARG(2);
		}
		else
		{
			sCallbackThis = [sCallbackScript oo_jsValueInContext:context];
		}
	}
	
	// Apply settings.
	if (JS_GetProperty(context, params, "title", &value))
	{
		[player setMissionTitle:OOStringFromJSValue(context, value)];
	}
	else
	{
		NSString *titleKey = GetParameterString(context, params, "titleKey");
		if (titleKey != nil)
		{
			titleKey = [[UNIVERSE missiontext] oo_stringForKey:titleKey];
			titleKey = ExpandDescriptionForCurrentSystem(titleKey);
			titleKey = [player replaceVariablesInString:titleKey];
			[player setMissionTitle:titleKey];
		}
	}
	
	[[OOMusicController	sharedController] setMissionMusic:GetParameterString(context, params, "music")];
	[player setMissionImage:GetParameterString(context, params, "overlay")];
	[player setMissionBackground:GetParameterString(context, params, "background")];
	
	if (JS_GetProperty(context, params, "model", &value))
	{
		if ([player status] == STATUS_IN_FLIGHT && JSVAL_IS_STRING(value))
		{
			OOJSReportWarning(context, @"Mission.runScreen: model will not be displayed while in flight.");
		}
		[player showShipModel:OOStringFromJSValue(context, value)];
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
	
	// now clean up!
	[player setMissionImage:nil];
	[player setMissionBackground:nil];
	[player setMissionTitle:nil];
	[player setMissionMusic:nil];
	
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(YES);
	
	OOJS_NATIVE_EXIT
}
