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
#import "OOSystemDescriptionManager.h"
#import "NSFileManagerOOExtensions.h"
#import "OOJSGuiScreenKeyDefinition.h"

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
static JSBool GlobalKeyBindingDescription(JSContext *context, uintN argc, jsval *vp); 
static JSBool GlobalExpandMissionText(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalDisplayNameForCommodity(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalRandomName(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetScreenBackground(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetScreenOverlay(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalGetScreenBackgroundForKey(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetScreenBackgroundForKey(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalAutoAIForRole(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalPauseGame(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalGetGuiColorSettingForKey(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetGuiColorSettingForKey(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetExtraGuiScreenKeys(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalClearExtraGuiScreenKeys(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalGetColorSaturation(JSContext *context, uintN argc, jsval *vp);
static JSBool GlobalSetColorSaturation(JSContext *context, uintN argc, jsval *vp);

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
	kGlobal_postFX,				// current post processing effect, integer, read/write
#ifndef NDEBUG
	kGlobal_timeAccelerationFactor	// time acceleration, float, read/write
#endif
};


static JSPropertySpec sGlobalProperties[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			kGlobal_galaxyNumber,		OOJS_PROP_READONLY_CB },
	{ "guiScreen",				kGlobal_guiScreen,			OOJS_PROP_READONLY_CB },
	{ "postFX",				kGlobal_postFX,			OOJS_PROP_READWRITE_CB },
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
	{ "getScreenBackgroundForKey",      GlobalGetScreenBackgroundForKey,    1 },
	{ "setScreenBackgroundForKey",      GlobalSetScreenBackgroundForKey,    2 },
	{ "setScreenOverlay",				GlobalSetScreenOverlay,				1 },
	{ "getGuiColorSettingForKey",       GlobalGetGuiColorSettingForKey,     1 },
	{ "setGuiColorSettingForKey",       GlobalSetGuiColorSettingForKey,     2 },
	{ "keyBindingDescription",       	GlobalKeyBindingDescription,		1 },
 	{ "getColorSaturation",				GlobalGetColorSaturation,			0 },
	{ "setColorSaturation",				GlobalSetColorSaturation,				1 },
	{ "setExtraGuiScreenKeys",			GlobalSetExtraGuiScreenKeys,		2 },
	{ "clearExtraGuiScreenKeys",		GlobalClearExtraGuiScreenKeys,		2 },

#ifndef NDEBUG
	{ "takeSnapShot",					GlobalTakeSnapShot,					1 },
#endif
	{ "pauseGame",						GlobalPauseGame,					0 },
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
			
		case kGlobal_postFX:
			*value = INT_TO_JSVAL([UNIVERSE currentPostFX]);
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
	int32					iValue;
	
	switch (JSID_TO_INT(propID))
	{
		case kGlobal_postFX:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				iValue = MAX(iValue, 0);
				[UNIVERSE setCurrentPostFX:iValue];
				return YES;
			}
			break;
			
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
	string = OOExpandDescriptionString(kNilRandomSeed, string, overrides, nil, nil, kOOExpandForJavaScript | kOOExpandGoodRNG);
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}

static JSBool GlobalKeyBindingDescription(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*string = nil;
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (argc > 0)  string = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (string == nil)
	{
		OOJSReportBadArguments(context, nil, @"keyBindingDescription", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	string = [player keyBindingDescription2:string];
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
	string = OOExpandDescriptionString(kNilRandomSeed, string, overrides, nil, nil, kOOExpandForJavaScript | kOOExpandBackslashN | kOOExpandGoodRNG);
	
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
		OOJSReportBadArguments(context, nil, @"randomInhabitantsDescription", 1, OOJS_ARGV, nil, @"boolean");
		return NO;
	}
	
	make_pseudo_random_seed(&aSeed);
	string = [UNIVERSE getSystemInhabitants:Ranrot()%OO_SYSTEMS_PER_GALAXY plural:isPlural];
	OOJS_RETURN_OBJECT(string);
	
	OOJS_NATIVE_EXIT
}


static JSBool GlobalClearExtraGuiScreenKeys(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	BOOL				result = NO;
	PlayerEntity		*player = OOPlayerForScripting();

	if (EXPECT_NOT(argc < 2))
	{
		OOJSReportBadArguments(context, nil, @"setExtraGuiScreenKeys", 0, OOJS_ARGV, nil, @"missing arguments");
		return NO;
	}

	NSString *key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil || [key isEqualToString:@""]))
	{
		OOJSReportBadArguments(context, nil, @"clearExtraGuiScreenKeys", 1, OOJS_ARGV, nil, @"key");
		return NO;
	}

	OOGUIScreenID gui = OOGUIScreenIDFromJSValue(context, OOJS_ARGV[1]);
	if (!gui)
	{
		OOJSReportBadArguments(context, nil, @"clearExtraGuiScreenKeys", 0, OOJS_ARGV, nil, @"guiScreen invalid entry");
		return NO;
	}

	[player clearExtraGuiScreenKeys:gui key:key];

	result = YES;
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}

static JSBool GlobalSetExtraGuiScreenKeys(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)

	BOOL				result = NO;
	jsval				callback = JSVAL_NULL;
	JSObject			*callbackThis = NULL;
	jsval				value = JSVAL_NULL;
	NSString			*key = nil;
	OOGUIScreenID 		gui;
	NSDictionary		*keydefs = NULL;
	JSObject			*params = NULL;
	PlayerEntity		*player = OOPlayerForScripting();

	if (EXPECT_NOT(argc < 1))
	{
		OOJSReportBadArguments(context, nil, @"setExtraGuiScreenKeys", 0, OOJS_ARGV, nil, @"key, definition");
		return NO;
	}
	key = OOStringFromJSValue(context, OOJS_ARGV[0]);

	// Validate arguments.
	if (argc < 2 || !JS_ValueToObject(context, OOJS_ARGV[1], &params))
	{
		OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], nil, @"key, definition: definition is not a valid dictionary.");
		return NO;
	}

	if (JS_GetProperty(context, params, "guiScreen", &value) == JS_FALSE || JSVAL_IS_VOID(value))
	{
		OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], nil, @"key, definition: must have a 'guiScreen' property.");
		return NO;
	}

	gui = OOGUIScreenIDFromJSValue(context, value);
	// gui will be 0 for invalid screen id's as well as GUI_SCREEN_MAIN
	if (gui == 0 || gui == GUI_SCREEN_LOAD || gui == GUI_SCREEN_SAVE || gui == GUI_SCREEN_STICKMAPPER || gui == GUI_SCREEN_OXZMANAGER || 
		gui == GUI_SCREEN_NEWGAME || gui == GUI_SCREEN_SAVE_OVERWRITE || gui == GUI_SCREEN_KEYBOARD || gui == GUI_SCREEN_STICKPROFILE || gui == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR ||
		gui == GUI_SCREEN_KEYBOARD_CONFIG || gui == GUI_SCREEN_KEYBOARD_ENTRY || gui == GUI_SCREEN_KEYBOARD_LAYOUT)
	{
		OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], nil, @"key, definition: 'guiScreen' property must be a permitted and valid GUI_SCREEN idenfifier.");
		return NO;
	}

	if (JS_GetProperty(context, params, "registerKeys", &value) == JS_FALSE || JSVAL_IS_VOID(value))
	{
		OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], nil, @"key, definition: must have a 'registerKeys' property.");
		return NO;
	}
	if (!JSVAL_IS_NULL(value))
	{
		if (JSVAL_IS_OBJECT(value))
		{
			keydefs = OOJSNativeObjectFromJSObject(context, JSVAL_TO_OBJECT(value));
		}
		else 
		{
			OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], nil, @"key, definition: registerKeys is not a valid dictionary.");
			return NO;
		}
	}

	if (JS_GetProperty(context, params, "callback", &callback) == JS_FALSE || JSVAL_IS_VOID(callback))
	{
		OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], NULL, @"key, definition; must have a 'callback' property.");
		return NO;
	}
	if (!OOJSValueIsFunction(context,callback))
	{
		OOJSReportBadArguments(context, @"global", @"setExtraGuiScreenKeys", 2, &OOJS_ARGV[1], NULL, @"key, definition; 'callback' property must be a function.");
		return NO;
	}

	OOJSGuiScreenKeyDefinition* definition = [[OOJSGuiScreenKeyDefinition alloc] init];
	[definition setName:key];
	[definition setRegisterKeys:keydefs];
	[definition setCallback:callback];

	// get callback 'this'
	if (JS_GetProperty(context, params, "cbThis", &value) == JS_TRUE && !JSVAL_IS_VOID(value))
	{
		JS_ValueToObject(context, value, &callbackThis);
		[definition setCallbackThis:callbackThis];
		// can do .bind(this) for callback instead
	}

	result = [player setExtraGuiScreenKeys:gui definition:definition];
	[definition release];

	OOJS_RETURN_BOOL(result);
	
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


static JSBool GlobalGetScreenBackgroundForKey(JSContext *context, uintN argc, jsval *vp) 
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(argc == 0))
	{
		OOJSReportBadArguments(context, nil, @"getScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"missing arguments");
		return NO;
	}
	NSString		*key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil || [key isEqualToString:@""]))
	{
		OOJSReportBadArguments(context, nil, @"getScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"key");
		return NO;
	}
	NSDictionary *descriptor = [UNIVERSE screenTextureDescriptorForKey:key];

	OOJS_RETURN_OBJECT(descriptor);
	
	OOJS_NATIVE_EXIT
} 

// setScreenBackgroundDefault (key : NSString, descriptor : guiTextureDescriptor) : boolean
static JSBool GlobalSetScreenBackgroundForKey(JSContext *context, uintN argc, jsval *vp) 
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL			result = NO;
	
	if (EXPECT_NOT(argc < 2))
	{
		OOJSReportBadArguments(context, nil, @"setScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"missing arguments");
		return NO;
	}

	NSString		*key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	jsval			value = OOJS_ARGV[1];
	if (EXPECT_NOT(key == nil || [key isEqualToString:@""]))
	{
		OOJSReportBadArguments(context, nil, @"setScreenBackgroundDefault", 0, OOJS_ARGV, nil, @"key");
		return NO;
	}

	GuiDisplayGen	*gui = [UNIVERSE gui];
	NSDictionary	*descriptor = [gui textureDescriptorFromJSValue:value inContext:context callerDescription:@"setScreenBackgroundDefault()"];
	
	[UNIVERSE setScreenTextureDescriptorForKey:key descriptor:descriptor];
	result = YES;
	
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


static JSBool GlobalGetGuiColorSettingForKey(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(argc == 0))
	{
		OOJSReportBadArguments(context, nil, @"getGuiColorForKey", 0, OOJS_ARGV, nil, @"missing arguments");
		return NO;
	}
	NSString		*key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil || [key isEqualToString:@""]))
	{
		OOJSReportBadArguments(context, nil, @"getGuiColorForKey", 0, OOJS_ARGV, nil, @"key");
		return NO;
	}
	if ([key rangeOfString:@"color"].location == NSNotFound)
	{
		OOJSReportBadArguments(context, nil, @"getGuiColorForKey", 0, OOJS_ARGV, nil, @"valid color key setting");
		return NO;
	}

	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOColor *col = [gui colorFromSetting:key defaultValue:nil];

	OOJS_RETURN_OBJECT([col normalizedArray]);
	
	OOJS_NATIVE_EXIT
}


// setGuiColorForKey(descriptor : OOColor) : boolean
static JSBool GlobalSetGuiColorSettingForKey(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL			result = NO;
	OOColor			*col = nil;
	
	if (EXPECT_NOT(argc != 2))
	{
		OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 0, OOJS_ARGV, nil, @"missing arguments");
		return NO;
	}

	NSString		*key = OOStringFromJSValue(context, OOJS_ARGV[0]);
	jsval			value = OOJS_ARGV[1];
	if (EXPECT_NOT(key == nil || [key isEqualToString:@""]))
	{
		OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 0, OOJS_ARGV, nil, @"key");
		return NO;
	}
	if ([key rangeOfString:@"color"].location == NSNotFound)
	{
		OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 0, OOJS_ARGV, nil, @"valid color key setting");
		return NO;
	}

	if (!JSVAL_IS_NULL(value))
	{
		col = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, value)];
		if (col == nil)
		{
			OOJSReportBadArguments(context, nil, @"setGuiColorForKey", 1, OOJS_ARGV, nil, @"color descriptor");
			return NO;
		}
	}

	GuiDisplayGen	*gui = [UNIVERSE gui];
	[gui setGuiColorSettingFromKey:key color:col];
	result = YES;
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// getColorSaturation()
static JSBool GlobalGetColorSaturation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJS_RETURN_OBJECT([NSNumber numberWithFloat:[[UNIVERSE gameView] colorSaturation]]);
	
	OOJS_NATIVE_EXIT
}


// setColorSaturation([desiredSaturation : Number])
static JSBool GlobalSetColorSaturation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	jsdouble	desiredColorSaturation = 0;
	
	if (argc < 1 || EXPECT_NOT(!JS_ValueToNumber(context, OOJS_ARGV[0], &desiredColorSaturation)))  return NO;
	
	MyOpenGLView *gameView = [UNIVERSE gameView];
	float currentColorSaturation = [gameView colorSaturation];
	[gameView adjustColorSaturation:desiredColorSaturation - currentColorSaturation];
	
	OOJS_RETURN_VOID;
	
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

// pauseGame() : Boolean
static JSBool GlobalPauseGame(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL			result = NO;
	PlayerEntity	*player = PLAYER;
	
	if (player)
	{
		OOGUIScreenID guiScreen = [player guiScreen];
		
		if 	(guiScreen != GUI_SCREEN_LONG_RANGE_CHART &&
			 guiScreen != GUI_SCREEN_MISSION &&
			 guiScreen != GUI_SCREEN_REPORT &&
			 guiScreen != GUI_SCREEN_KEYBOARD_ENTRY &&
			 guiScreen != GUI_SCREEN_SAVE)
		{
			[UNIVERSE pauseGame];
			result = YES;
		}
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}
