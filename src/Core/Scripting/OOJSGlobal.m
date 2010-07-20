/*

OOJSGlobal.m


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import "OOJSGlobal.h"
#import "OOJavaScriptEngine.h"

#import "OOJSPlayer.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringParsing.h"
#import "OOConstToString.h"
#import "OOCollectionExtractors.h"
#import "OOTexture.h"
#import "GuiDisplayGen.h"


#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)context;

@end

#endif


extern NSString * const kOOLogDebugMessage;


static JSBool GlobalGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool GlobalSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool GlobalLog(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalExpandDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalExpandMissionText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalDisplayNameForCommodity(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalRandomName(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalSetScreenBackground(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalSetScreenOverlay(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sGlobalClass =
{
	"Global",
	JSCLASS_GLOBAL_FLAGS,
	
	JS_PropertyStub,
	JS_PropertyStub,
	GlobalGetProperty,
	GlobalSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kGlobal_galaxyNumber,		// galaxy number, integer, read-only
	kGlobal_guiScreen,			// current GUI screen, string, read-only
	kGlobal_timeAccelerationFactor	// time acceleration, float, read/write
};


static JSPropertySpec sGlobalProperties[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			kGlobal_galaxyNumber,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "guiScreen",				kGlobal_guiScreen,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "timeAccelerationFactor",	kGlobal_timeAccelerationFactor,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sGlobalMethods[] =
{
	// JS name							Function								min args
	{ "log",							GlobalLog,							1 },
	{ "expandDescription",				GlobalExpandDescription,			1 },
	{ "expandMissionText",				GlobalExpandMissionText,			1 },
	{ "displayNameForCommodity",		GlobalDisplayNameForCommodity,		1 },
	{ "randomName",						GlobalRandomName,					0 },
	{ "randomInhabitantsDescription",	GlobalRandomInhabitantsDescription,	1 },
	{ "setScreenBackground",			GlobalSetScreenBackground,			1 },
	{ "setScreenOverlay",				GlobalSetScreenOverlay,				1 },
	{ 0 }
};


void CreateOOJSGlobal(JSContext *context, JSObject **outGlobal)
{
	assert(outGlobal != NULL);
	
	*outGlobal = JS_NewObject(context, &sGlobalClass, NULL, NULL);
}


void SetUpOOJSGlobal(JSContext *context, JSObject *global)
{
	JS_DefineProperties(context, global, sGlobalProperties);
	JS_DefineFunctions(context, global, sGlobalMethods);
}


static JSBool GlobalGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	id							result = nil;
	
	switch (JSVAL_TO_INT(name))
	{
		case kGlobal_galaxyNumber:
			*outValue = INT_TO_JSVAL([player currentGalaxyID]);
			break;
			
		case kGlobal_guiScreen:
			result = [player gui_screen_string];
			break;
			
		case kGlobal_timeAccelerationFactor:
			JS_NewDoubleValue(context, [UNIVERSE timeAccelerationFactor], outValue);
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Global", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool GlobalSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	if (!JSVAL_IS_INT(name))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	jsdouble					fValue;
	
	switch (JSVAL_TO_INT(name))
	{
		case kGlobal_timeAccelerationFactor:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[UNIVERSE setTimeAccelerationFactor:fValue];
				OK = YES;
			}
			break;
	
		default:
			OOReportJSBadPropertySelector(context, @"Global", JSVAL_TO_INT(name));
	}
	
	return OK;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// log([messageClass : String,] message : string, ...)
static JSBool GlobalLog(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*message = nil;
	NSString			*messageClass = nil;
	
	if (argc < 2)
	{
		messageClass = kOOLogDebugMessage;
		message = JSValToNSString(context,argv[0]);
	}
	else
	{
		messageClass = [NSString stringWithJavaScriptValue:argv[0] inContext:context];
		message = [NSString concatenationOfStringsFromJavaScriptValues:argv + 1 count:argc - 1 separator:@", " inContext:context];
	}
	
	OOJSPauseTimeLimiter();
	OOLog(messageClass, @"%@", message);
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
											withMessageClass:nil
												   inContext:context];
#endif
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// expandDescription(description : String [, overrides : object (dictionary)]) : String
static JSBool GlobalExpandDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	NSDictionary		*overrides = nil;
	
	string = JSValToNSString(context, argv[0]);
	if (string == nil)
	{
		OOReportJSBadArguments(context, @"System", @"expandDescription", argc, argv, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		overrides = JSValueToObjectOfClass(context, argv[1], [NSDictionary class]);
	}
	
	string = ExpandDescriptionsWithOptions(string, [[PlayerEntity sharedPlayer] system_seed], overrides, nil, nil);
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// expandMissionText(textKey : String [, overrides : object (dictionary)]) : String
static JSBool GlobalExpandMissionText(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	NSMutableString		*mString = nil;
	NSDictionary		*overrides = nil;
	
	string = JSValToNSString(context, argv[0]);
	if (string == nil)
	{
		OOReportJSBadArguments(context, @"System", @"expandMissionText", argc, argv, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		overrides = JSValueToObjectOfClass(context, argv[1], [NSDictionary class]);
	}
	
	string = [[UNIVERSE missiontext] oo_stringForKey:string];
	if (string != nil)
	{
		mString = [ExpandDescriptionsWithOptions(string, [[PlayerEntity sharedPlayer] system_seed], overrides, nil, nil) mutableCopy];
		[mString replaceOccurrencesOfString:@"\\n" withString:@"\n" options:0 range:(NSRange){ 0, [mString length] }];
		*outResult = [mString javaScriptValueInContext:context];
		[mString release];
	}
	else
	{
		*outResult = JSVAL_NULL;
	}

	return YES;
	
	OOJS_NATIVE_EXIT
}


// displayNameForCommodity(commodityName : String) : String
static JSBool GlobalDisplayNameForCommodity(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	
	string = JSValToNSString(context,argv[0]);
	if (string == nil)
	{
		OOReportJSBadArguments(context, @"System", @"displayNameForCommodity", argc, argv, nil, @"string");
		return NO;
	}
	string = CommodityDisplayNameForSymbolicName(string);
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// randomName() : String
static JSBool GlobalRandomName(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	
	string = RandomDigrams();
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// randomInhabitantsDescription() : String
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	Random_Seed			aSeed;
	JSBool				isPlural = YES;
	
	if (!JS_ValueToBoolean(context, argv[0], &isPlural))  isPlural = NO;
	
	make_pseudo_random_seed(&aSeed);
	string = [UNIVERSE generateSystemInhabitants:aSeed plural:isPlural];
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// setScreenBackground(name : String) : Boolean
static JSBool GlobalSetScreenBackground(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	*outResult = JSVAL_FALSE;
	NSString 		*value = JSValToNSString(context, argv[0]);
	PlayerEntity	*player = OOPlayerForScripting();
	
	if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)
	{
		*outResult = BOOLEAN_TO_JSVAL([[UNIVERSE gui] setBackgroundTextureName:value]);
		// add some permanence to the override if we're in the equip ship screen
		if (*outResult == JSVAL_TRUE && [player guiScreen] == GUI_SCREEN_EQUIP_SHIP) [player setTempBackground:value];
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// setScreenOverlay(name : String) : Boolean
static JSBool GlobalSetScreenOverlay(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	OOJS_NATIVE_ENTER(context)
	
	*outResult = JSVAL_FALSE;
	NSString 		*value = JSValToNSString(context, argv[0]);
	
	if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)
	{
		*outResult = BOOLEAN_TO_JSVAL([[UNIVERSE gui] setForegroundTextureName:value]);
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}
