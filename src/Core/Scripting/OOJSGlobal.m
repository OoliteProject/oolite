/*

OOJSGlobal.m


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

#import "OOJSGlobal.h"
#import "OOJavaScriptEngine.h"

#import "OOJSPlayer.h"
#import "PlayerEntityScriptMethods.h"
#import "OOStringExpander.h"
#import "OOConstToString.h"
#import "OOConstToJSString.h"
#import "OOCollectionExtractors.h"
#import "OOTexture.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "ResourceManager.h"

#import "NSFileManagerOOExtensions.h"


#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)context;

@end

#endif


static NSString * const kOOLogDebugMessage = @"script.debug.message";


static JSBool GlobalGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
#ifndef NDEBUG
static JSBool GlobalSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
#endif

static JSBool GlobalLog(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalExpandDescription(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalExpandMissionText(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalDisplayNameForCommodity(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalRandomName(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetScreenBackground(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetScreenOverlay(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalAutoAIForRole(JSContext *context, uintN argc, jsval *vp);

#ifndef NDEBUG
static JSBool GlobalTakeSnapShot(JSContext *context, uintN argc, jsval *vp);
#endif


static JSClass sGlobalClass =
{
	"Global",
	JSCLASS_GLOBAL_FLAGS,
	
	JS_PropertyStub,
	JS_PropertyStub,
	GlobalGetProperty,
#ifndef NDEBUG
	GlobalSetProperty,
#else
	// No writeable properties in non-debug builds
	JS_StrictPropertyStub,
#endif
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kGlobal_galaxyNumber,		// galaxy number, integer, read-only
	kGlobal_global,				// global.global.global.global, integer, read-only
	kGlobal_guiScreen,			// current GUI screen, string, read-only
#ifndef NDEBUG
	kGlobal_timeAccelerationFactor	// time acceleration, float, read/write
#endif
};


static JSPropertySpec sGlobalProperties[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			kGlobal_galaxyNumber,		OOJS_PROP_READONLY_CB },
	{ "guiScreen",				kGlobal_guiScreen,			OOJS_PROP_READONLY_CB },
#ifndef NDEBUG
	{ "timeAccelerationFactor",	kGlobal_timeAccelerationFactor,	OOJS_PROP_READWRITE_CB },
#endif
	{ 0 }
};


static JSFunctionSpec sGlobalMethods[] =
{
	// JS name							Function								min args
	{ "log",							GlobalLog,							1 },
	{ "autoAIForRole",					GlobalAutoAIForRole,				1 },
	{ "expandDescription",				GlobalExpandDescription,			1 },
	{ "expandMissionText",				GlobalExpandMissionText,			1 },
	{ "displayNameForCommodity",		GlobalDisplayNameForCommodity,		1 },
	{ "randomName",						GlobalRandomName,					0 },
	{ "randomInhabitantsDescription",	GlobalRandomInhabitantsDescription,	1 },
	{ "setScreenBackground",			GlobalSetScreenBackground,			1 },
	{ "setScreenOverlay",				GlobalSetScreenOverlay,				1 },
#ifndef NDEBUG
	{ "takeSnapShot",					GlobalTakeSnapShot,					1 },
#endif
	{ 0 }
};


void CreateOOJSGlobal(JSContext *context, JSObject **outGlobal)
{
	assert(outGlobal != NULL);
	
	*outGlobal = JS_NewCompartmentAndGlobalObject(context, &sGlobalClass, NULL);
	
	JS_SetGlobalObject(context, *outGlobal);
	JS_DefineProperty(context, *outGlobal, "global", OBJECT_TO_JSVAL(*outGlobal), NULL, NULL, OOJS_PROP_READONLY);
}


void SetUpOOJSGlobal(JSContext *context, JSObject *global)
{
	JS_DefineProperties(context, global, sGlobalProperties);
	JS_DefineFunctions(context, global, sGlobalMethods);
}


static JSBool GlobalGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	switch (JSID_TO_INT(propID))
	{
		case kGlobal_galaxyNumber:
			*value = INT_TO_JSVAL([player currentGalaxyID]);
			return YES;
			
		case kGlobal_guiScreen:
			*value = OOJSValueFromGUIScreenID(context, [player guiScreen]);
			return YES;
			
#ifndef NDEBUG
		case kGlobal_timeAccelerationFactor:
			return JS_NewNumberValue(context, [UNIVERSE timeAccelerationFactor], value);
#endif
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sGlobalProperties);
			return NO;
	}
	
	OOJS_NATIVE_EXIT
}


#ifndef NDEBUG
static JSBool GlobalSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	jsdouble					fValue;
	
	switch (JSID_TO_INT(propID))
	{
		case kGlobal_timeAccelerationFactor:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[UNIVERSE setTimeAccelerationFactor:fValue];
				return YES;
			}
			break;
	
		default:
			OOJSReportBadPropertySelector(context, this, propID, sGlobalProperties);
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sGlobalProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}
#endif


// *** Methods ***

// log([messageClass : String,] message : string, ...)
static JSBool GlobalLog(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*message = nil;
	NSString			*messageClass = nil;
	
	if (EXPECT_NOT(argc < 1))
	{
		OOJS_RETURN_VOID;
	}
	if (argc < 2)
	{
		messageClass = kOOLogDebugMessage;
		message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	}
	else
	{
		messageClass = OOStringFromJSValueEvenIfNull(context, OOJS_ARGV[0]);
		if (!OOLogWillDisplayMessagesInClass(messageClass))
		{
			// Do nothing (and short-circuit) if message class is filtered out.
			OOJS_RETURN_VOID;
		}
		
		message = [NSString concatenationOfStringsFromJavaScriptValues:OOJS_ARGV + 1 count:argc - 1 separator:@", " inContext:context];
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	OOLog(messageClass, @"%@", message);
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
											withMessageClass:nil
												   inContext:context];
#endif
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// expandDescription(description : String [, overrides : object (dictionary)]) : String
static JSBool GlobalExpandDescription(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	NSDictionary		*overrides = nil;
	
	if (argc > 0)  string = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"expandDescription", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	string = OOExpandDescriptionString(string, [PLAYER system_seed], overrides, nil, nil, kOOExpandForJavaScript | kOOExpandGoodRNG);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// expandMissionText(textKey : String [, overrides : object (dictionary)]) : String
static JSBool GlobalExpandMissionText(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	NSDictionary		*overrides = nil;
	
	if (argc > 0)  string = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"expandMissionText", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (argc > 1)
	{
		overrides = OOJSDictionaryFromStringTable(context, OOJS_ARGV[1]);
	}
	
	string = [[UNIVERSE missiontext] oo_stringForKey:string];
	string = OOExpandDescriptionString(string, [PLAYER system_seed], overrides, nil, nil, kOOExpandForJavaScript | kOOExpandBackslashN | kOOExpandGoodRNG);
	
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// displayNameForCommodity(commodityName : String) : String
static JSBool GlobalDisplayNameForCommodity(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	
	if (argc > 0)  string = OOStringFromJSValue(context,OOJS_ARGV[0]);
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"displayNameForCommodity", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	OOJS_RETURN_OBJECT(CommodityDisplayNameForSymbolicName(string));
	
	OOJS_NATIVE_EXIT
}


// randomName() : String
static JSBool GlobalRandomName(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	/*	Temporarily set the system generation seed to a "really random" seed,
		so randomName() isn't repeatable.
	*/
	RNG_Seed savedSeed = currentRandomSeed();
	setRandomSeed((RNG_Seed){ Ranrot(), Ranrot(), Ranrot(), Ranrot() });
	
	NSString *result = OOExpand(@"%N");
	
	// Restore seed.
	setRandomSeed(savedSeed);
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// randomInhabitantsDescription() : String
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	Random_Seed			aSeed;
	JSBool				isPlural = YES;
	
	if (argc > 0 && !JS_ValueToBoolean(context, OOJS_ARGV[0], &isPlural))
	{
		OOJSReportBadArguments(context, nil, @"displayNameForCommodity", 1, OOJS_ARGV, nil, @"boolean");
		return NO;
	}
	
	make_pseudo_random_seed(&aSeed);
	string = [UNIVERSE generateSystemInhabitants:aSeed plural:isPlural];
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


// setScreenBackground(descriptor : guiTextureDescriptor) : Boolean
static JSBool GlobalSetScreenBackground(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL			result = NO;
	jsval			value = (argc > 0) ? OOJS_ARGV[0] : JSVAL_NULL;
	
	if (EXPECT_NOT(argc == 0))
	{
		OOJSReportWarning(context, @"Usage error: %@() called with no arguments. Treating as %@(null). This call may fail in a future version of Oolite.", @"setScreenBackground", @"setScreenBackground");
	}
	else if (EXPECT_NOT(JSVAL_IS_VOID(value)))
	{
		OOJSReportBadArguments(context, nil, @"setScreenBackground", 1, &value, nil, @"GUI texture descriptor");
		return NO;
	}
	
	if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		NSDictionary	*descriptor = [gui textureDescriptorFromJSValue:value inContext:context callerDescription:@"setScreenBackground()"];
		
		result = [gui setBackgroundTextureDescriptor:descriptor];
		
		// add some permanence to the override if we're in the equip ship screen
		if (result && [PLAYER guiScreen] == GUI_SCREEN_EQUIP_SHIP)  [PLAYER setEquipScreenBackgroundDescriptor:descriptor];
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// setScreenOverlay(descriptor : guiTextureDescriptor) : Boolean
static JSBool GlobalSetScreenOverlay(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL			result = NO;
	jsval			value = (argc > 0) ? OOJS_ARGV[0] : JSVAL_NULL;
	
	if (EXPECT_NOT(argc == 0))
	{
		OOJSReportWarning(context, @"Usage error: %@() called with no arguments. Treating as %@(null). This call may fail in a future version of Oolite.", @"setScreenOverlay", @"setScreenOverlay");
	}
	else if (EXPECT_NOT(JSVAL_IS_VOID(value)))
	{
		OOJSReportBadArguments(context, nil, @"setScreenOverlay", 1, &value, nil, @"GUI texture descriptor");
		return NO;
	}
	
	if ([UNIVERSE viewDirection] == VIEW_GUI_DISPLAY)
	{
		GuiDisplayGen	*gui = [UNIVERSE gui];
		NSDictionary	*descriptor = [gui textureDescriptorFromJSValue:value inContext:context callerDescription:@"setScreenOverlay()"];
		
		result = [gui setForegroundTextureDescriptor:descriptor];
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


#ifndef NDEBUG
// takeSnapShot([name : alphanumeric String]) : Boolean
static JSBool GlobalTakeSnapShot(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*value = nil;
	NSMutableCharacterSet	*allowedChars = (NSMutableCharacterSet *)[NSMutableCharacterSet alphanumericCharacterSet];
	BOOL					result = NO;	
	
	[allowedChars addCharactersInString:@"_-"];
	
	if (argc > 0)
	{
		value = OOStringFromJSValue(context, OOJS_ARGV[0]);
		if (EXPECT_NOT(value == nil || [value rangeOfCharacterFromSet:[allowedChars invertedSet]].location != NSNotFound))
		{
			OOJSReportBadArguments(context, nil, @"takeSnapShot", argc, OOJS_ARGV, nil, @"alphanumeric string");
			return NO;
		}
	}
	
	NSString				*playerFileDirectory = [[NSFileManager defaultManager] defaultCommanderPath];
	NSDictionary			*attr = [[NSFileManager defaultManager] oo_fileSystemAttributesAtPath:playerFileDirectory];
	
	if (attr != nil)
	{
		double freeSpace = [attr oo_doubleForKey:NSFileSystemFreeSize];
		if (freeSpace < 1073741824) // less than 1 GB free on disk?
		{
			OOJSReportWarning(context, @"takeSnapShot: function disabled when free disk space is less than 1GB.");
			OOJS_RETURN_BOOL(NO);
		}
	}
	
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [[UNIVERSE gameView] snapShot:value];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
#endif

// autoAIForRole(role : String) : String
static JSBool GlobalAutoAIForRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	
	if (argc > 0)  string = OOStringFromJSValue(context,OOJS_ARGV[0]);
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"autoAIForRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}

	NSDictionary *autoAIMap = [ResourceManager dictionaryFromFilesNamed:@"autoAImap.plist" inFolder:@"Config" andMerge:YES];
	NSString *autoAI = [autoAIMap oo_stringForKey:string];

	OOJS_RETURN_OBJECT(autoAI);
	
	OOJS_NATIVE_EXIT
}
