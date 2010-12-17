/*

OOJSConsole.m


Oolite Debug OXP

Copyright (C) 2007-2010 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OO_EXCLUDE_DEBUG_SUPPORT

#import "OOJSConsole.h"
#import "OODebugMonitor.h"
#import <stdint.h>

#import "OOJavaScriptEngine.h"
#import "OOJSScript.h"
#import "OOJSVector.h"
#import "OOJSEntity.h"
#import "OOJSCall.h"
#import "OOLoggingExtended.h"
#import "OOConstToString.h"
#import "OOOpenGLExtensionManager.h"
#import "OODebugFlags.h"
#import "OODebugMonitor.h"
#import "OOProfilingStopwatch.h"


@interface Entity (OODebugInspector)

// Method added by inspector in Debug OXP under OS X only.
- (void) inspect;

@end


NSString *OOPlatformDescription(void);


static JSObject *sConsolePrototype = NULL;
static JSObject *sConsoleSettingsPrototype = NULL;


static JSBool ConsoleGetProperty(OOJS_PROP_ARGS);
static JSBool ConsoleSetProperty(OOJS_PROP_ARGS);
static void ConsoleFinalize(JSContext *context, JSObject *this);

// Methods
static JSBool ConsoleConsoleMessage(OOJS_NATIVE_ARGS);
static JSBool ConsoleClearConsole(OOJS_NATIVE_ARGS);
static JSBool ConsoleScriptStack(OOJS_NATIVE_ARGS);
static JSBool ConsoleInspectEntity(OOJS_NATIVE_ARGS);
static JSBool ConsoleCallObjCMethod(OOJS_NATIVE_ARGS);
static JSBool ConsoleSetUpCallObjC(OOJS_NATIVE_ARGS);
static JSBool ConsoleIsExecutableJavaScript(OOJS_NATIVE_ARGS);
static JSBool ConsoleDisplayMessagesInClass(OOJS_NATIVE_ARGS);
static JSBool ConsoleSetDisplayMessagesInClass(OOJS_NATIVE_ARGS);
static JSBool ConsoleWriteLogMarker(OOJS_NATIVE_ARGS);
static JSBool ConsoleWriteMemoryStats(OOJS_NATIVE_ARGS);
#if OOJS_PROFILE
static JSBool ConsoleProfile(OOJS_NATIVE_ARGS);
static JSBool ConsoleGetProfile(OOJS_NATIVE_ARGS);
#endif

static JSBool ConsoleSettingsDeleteProperty(OOJS_PROP_ARGS);
static JSBool ConsoleSettingsGetProperty(OOJS_PROP_ARGS);
static JSBool ConsoleSettingsSetProperty(OOJS_PROP_ARGS);

#if OOJS_PROFILE
static JSBool PerformProfiling(JSContext *context, NSString *nominalFunction, uintN argc, jsval *argv, OOTimeProfile **profile);
#endif


static JSClass sConsoleClass =
{
	"Console",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,				// addProperty
	JS_PropertyStub,				// delProperty
	ConsoleGetProperty,				// getProperty
	ConsoleSetProperty,				// setProperty
	JS_EnumerateStub,				// enumerate
	JS_ResolveStub,					// resolve
	JS_ConvertStub,					// convert
	ConsoleFinalize,				// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kConsole_debugFlags,						// debug flags, integer, read/write
	kConsole_shaderMode,						// shader mode, symbolic string, read/write
	kConsole_maximumShaderMode,					// highest supported shader mode, symbolic string, read-only
	kConsole_reducedDetailMode,					// reduced detail mode, boolean, read/write
	kConsole_displayFPS,						// display FPS (and related info), boolean, read/write
	kConsole_platformDescription,				// Information about system we're running on in unspecified format, string, read-only
	
	kConsole_glVendorString,					// OpenGL GL_VENDOR string, string, read-only
	kConsole_glRendererString,					// OpenGL GL_RENDERER string, string, read-only
	kConsole_glFixedFunctionTextureUnitCount,	// GL_MAX_TEXTURE_UNITS_ARB, integer, read-only
	kConsole_glFragmentShaderTextureUnitCount,	// GL_MAX_TEXTURE_IMAGE_UNITS_ARB, integer, read-only
	
	// Symbolic constants for debug flags:
	kConsole_DEBUG_LINKED_LISTS,
	kConsole_DEBUG_COLLISIONS,
	kConsole_DEBUG_DOCKING,
	kConsole_DEBUG_OCTREE_LOGGING,
	kConsole_DEBUG_BOUNDING_BOXES,
	kConsole_DEBUG_OCTREE_DRAW,
	kConsole_DEBUG_DRAW_NORMALS,
	kConsole_DEBUG_NO_DUST,
	kConsole_DEBUG_NO_SHADER_FALLBACK,
	kConsole_DEBUG_SHADER_VALIDATION,
	
	kConsole_DEBUG_MISC
};


static JSPropertySpec sConsoleProperties[] =
{
	// JS name								ID											flags
	{ "debugFlags",							kConsole_debugFlags,						JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "shaderMode",							kConsole_shaderMode,						JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "maximumShaderMode",					kConsole_maximumShaderMode,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "reducedDetailMode",					kConsole_reducedDetailMode,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "displayFPS",							kConsole_displayFPS,						JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "platformDescription",				kConsole_platformDescription,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "glVendorString",						kConsole_glVendorString,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "glRendererString",					kConsole_glRendererString,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "glFixedFunctionTextureUnitCount",	kConsole_glFixedFunctionTextureUnitCount,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "glFragmentShaderTextureUnitCount",	kConsole_glFragmentShaderTextureUnitCount,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	
#define DEBUG_FLAG_DECL(x) { #x, kConsole_##x, JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY }
	DEBUG_FLAG_DECL(DEBUG_LINKED_LISTS),
	DEBUG_FLAG_DECL(DEBUG_COLLISIONS),
	DEBUG_FLAG_DECL(DEBUG_DOCKING),
	DEBUG_FLAG_DECL(DEBUG_OCTREE_LOGGING),
	DEBUG_FLAG_DECL(DEBUG_BOUNDING_BOXES),
	DEBUG_FLAG_DECL(DEBUG_OCTREE_DRAW),
	DEBUG_FLAG_DECL(DEBUG_DRAW_NORMALS),
	DEBUG_FLAG_DECL(DEBUG_NO_DUST),
	DEBUG_FLAG_DECL(DEBUG_NO_SHADER_FALLBACK),
	DEBUG_FLAG_DECL(DEBUG_SHADER_VALIDATION),
	
	DEBUG_FLAG_DECL(DEBUG_MISC),
#undef DEBUG_FLAG_DECL
	
	{ 0 }
};


static JSFunctionSpec sConsoleMethods[] =
{
	// JS name							Function							min args
	{ "consoleMessage",					ConsoleConsoleMessage,				2 },
	{ "clearConsole",					ConsoleClearConsole,				0 },
	{ "scriptStack",					ConsoleScriptStack,					0 },
	{ "inspectEntity",					ConsoleInspectEntity,				1 },
	{ "__setUpCallObjC",				ConsoleSetUpCallObjC,				1, JSPROP_READONLY },
	{ "isExecutableJavaScript",			ConsoleIsExecutableJavaScript,		2 },
	{ "displayMessagesInClass",			ConsoleDisplayMessagesInClass,		1 },
	{ "setDisplayMessagesInClass",		ConsoleSetDisplayMessagesInClass,	2 },
	{ "writeLogMarker",					ConsoleWriteLogMarker,				0 },
	{ "writeMemoryStats",				ConsoleWriteMemoryStats,			0 },
#if OOJS_PROFILE
	{ "profile",						ConsoleProfile,						1 },
	{ "getProfile",						ConsoleGetProfile,					1 },
#endif
	{ 0 }
};


static JSClass sConsoleSettingsClass =
{
	"ConsoleSettings",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,				// addProperty
	ConsoleSettingsDeleteProperty,	// delProperty
	ConsoleSettingsGetProperty,		// getProperty
	ConsoleSettingsSetProperty,		// setProperty
	JS_EnumerateStub,				// enumerate. FIXME: this should work.
	JS_ResolveStub,					// resolve
	JS_ConvertStub,					// convert
	ConsoleFinalize,				// finalize (same as Console)
	JSCLASS_NO_OPTIONAL_MEMBERS
};


static void InitOOJSConsole(JSContext *context, JSObject *global)
{
	sConsolePrototype = JS_InitClass(context, global, NULL, &sConsoleClass, NULL, 0, sConsoleProperties, sConsoleMethods, NULL, NULL);
	JSRegisterObjectConverter(&sConsoleClass, JSBasicPrivateObjectConverter);
	
	sConsoleSettingsPrototype = JS_InitClass(context, global, NULL, &sConsoleSettingsClass, NULL, 0, NULL, NULL, NULL, NULL);
	JSRegisterObjectConverter(&sConsoleSettingsClass, JSBasicPrivateObjectConverter);
}


JSObject *DebugMonitorToJSConsole(JSContext *context, OODebugMonitor *monitor)
{
	OOJS_PROFILE_ENTER
	
	OOJavaScriptEngine		*engine = nil;
	JSObject				*object = NULL;
	JSObject				*settingsObject = NULL;
	jsval					value;
	
	NSCAssert(JS_EnterLocalRootScope(context), @"Failed to create JS GC root scope");
	engine = [OOJavaScriptEngine sharedEngine];
	
	if (sConsolePrototype == NULL)
	{
		InitOOJSConsole(context, [engine globalObject]);
	}
	
	// Create Console object
	object = JS_NewObject(context, &sConsoleClass, sConsolePrototype, NULL);
	if (object != NULL)
	{
		if (!JS_SetPrivate(context, object, [monitor weakRetain]))  object = NULL;
	}
	
	if (object != NULL)
	{
		// Create ConsoleSettings object
		settingsObject = JS_NewObject(context, &sConsoleSettingsClass, sConsoleSettingsPrototype, NULL);
		if (settingsObject != NULL)
		{
			if (!JS_SetPrivate(context, settingsObject, [monitor weakRetain]))  settingsObject = NULL;
		}
		if (settingsObject != NULL)
		{
			value = OBJECT_TO_JSVAL(settingsObject);
			if (!JS_SetProperty(context, object, "settings", &value))
			{
				settingsObject = NULL;
			}
		}

		if (settingsObject == NULL)  object = NULL;
	}
	
	JS_LeaveLocalRootScope(context);
	
	return object;
	// Analyzer: object leaked. (x2) [Expected, objects are retained by JS object.]
	
	OOJS_PROFILE_EXIT
}


static JSBool ConsoleGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	switch (OOJS_PROPID_INT)
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			*value = INT_TO_JSVAL(gDebugFlags);
			break;
#endif		
			
		case kConsole_shaderMode:
			*value = [ShaderSettingToString([UNIVERSE shaderEffectsLevel]) javaScriptValueInContext:context];
			break;
			
		case kConsole_maximumShaderMode:
			*value = [ShaderSettingToString([[OOOpenGLExtensionManager sharedManager] maximumShaderSetting]) javaScriptValueInContext:context];
			break;
			
		case kConsole_reducedDetailMode:
			*value = BOOLToJSVal([UNIVERSE reducedDetail]);
			break;
			
		case kConsole_displayFPS:
			*value = BOOLToJSVal([UNIVERSE displayFPS]);
			break;
			
		case kConsole_platformDescription:
			*value = [OOPlatformDescription() javaScriptValueInContext:context];
			break;
			
		case kConsole_glVendorString:
			*value = [[[OOOpenGLExtensionManager sharedManager] vendorString] javaScriptValueInContext:context];
			break;
			
		case kConsole_glRendererString:
			*value = [[[OOOpenGLExtensionManager sharedManager] rendererString] javaScriptValueInContext:context];
			break;
			
		case kConsole_glFixedFunctionTextureUnitCount:
			*value = INT_TO_JSVAL([[OOOpenGLExtensionManager sharedManager] textureUnitCount]);
			break;
			
		case kConsole_glFragmentShaderTextureUnitCount:
			*value = INT_TO_JSVAL([[OOOpenGLExtensionManager sharedManager] textureImageUnitCount]);
			break;
			
#define DEBUG_FLAG_CASE(x) case kConsole_##x: *value = INT_TO_JSVAL(x); break;
		DEBUG_FLAG_CASE(DEBUG_LINKED_LISTS);
		DEBUG_FLAG_CASE(DEBUG_COLLISIONS);
		DEBUG_FLAG_CASE(DEBUG_DOCKING);
		DEBUG_FLAG_CASE(DEBUG_OCTREE_LOGGING);
		DEBUG_FLAG_CASE(DEBUG_BOUNDING_BOXES);
		DEBUG_FLAG_CASE(DEBUG_OCTREE_DRAW);
		DEBUG_FLAG_CASE(DEBUG_DRAW_NORMALS);
		DEBUG_FLAG_CASE(DEBUG_NO_DUST);
		DEBUG_FLAG_CASE(DEBUG_NO_SHADER_FALLBACK);
		DEBUG_FLAG_CASE(DEBUG_SHADER_VALIDATION);
		
		DEBUG_FLAG_CASE(DEBUG_MISC);
#undef DEBUG_FLAG_CASE
			
		default:
			OOReportJSBadPropertySelector(context, @"Console", OOJS_PROPID_INT);
			return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	int32						iValue;
	NSString					*sValue = nil;
	JSBool						bValue = NO;
	
	switch (OOJS_PROPID_INT)
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				gDebugFlags = iValue;
			}
			break;
#endif		
		case kConsole_shaderMode:
			sValue = JSValToNSString(context, *value);
			if (sValue != nil)
			{
				OOJSPauseTimeLimiter();
				OOShaderSetting setting = StringToShaderSetting(sValue);
				[UNIVERSE setShaderEffectsLevel:setting transiently:YES];
				OOJSResumeTimeLimiter();
			}
			break;
			
		case kConsole_reducedDetailMode:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				OOJSPauseTimeLimiter();
				[UNIVERSE setReducedDetail:bValue transiently:YES];
				OOJSResumeTimeLimiter();
			}
			break;
			
		case kConsole_displayFPS:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[UNIVERSE setDisplayFPS:bValue];
			}
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Console", OOJS_PROPID_INT);
			return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static BOOL DoWeDefineAllDebugFlags(enum OODebugFlags flags)  GCC_ATTR((unused));
static BOOL DoWeDefineAllDebugFlags(enum OODebugFlags flags)
{
	/*	This function doesn't do anything, but will generate a warning
		(Enumeration value 'DEBUG_FOO' not handled in switch) if a debug flag
		is added without updating it. The point is that if you get such a
		warning, you should first add a JS symbolic constant for the flag,
		then add it to the switch to supress the warning.
		NOTE: don't add a default: to this switch, or I will have to hurt you.
		-- Ahruman 2010-04-11
	*/
	switch (flags)
	{
		case DEBUG_LINKED_LISTS:
		case DEBUG_COLLISIONS:
		case DEBUG_DOCKING:
		case DEBUG_OCTREE_LOGGING:
		case DEBUG_BOUNDING_BOXES:
		case DEBUG_OCTREE_DRAW:
		case DEBUG_DRAW_NORMALS:
		case DEBUG_NO_DUST:
		case DEBUG_NO_SHADER_FALLBACK:
		case DEBUG_SHADER_VALIDATION:
		
		case DEBUG_MISC:
			return YES;
	}
	
	return NO;
}


static void ConsoleFinalize(JSContext *context, JSObject *this)
{
	OOJS_PROFILE_ENTER
	
	[(id)JS_GetPrivate(context, this) release];
	JS_SetPrivate(context, this, nil);
	
	OOJS_PROFILE_EXIT_VOID
}


static JSBool ConsoleSettingsDeleteProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	id					monitor = nil;
	
	if (!OOJS_PROPID_IS_STRING)  return NO;
	key = [NSString stringWithJavaScriptString:OOJS_PROPID_STRING];
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	[monitor setConfigurationValue:nil forKey:key];
	*value = JSVAL_TRUE;
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleSettingsGetProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	id					settingValue = nil;
	id					monitor = nil;
	
	if (!OOJS_PROPID_IS_STRING)  return YES;
	key = [NSString stringWithJavaScriptString:OOJS_PROPID_STRING];
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	settingValue = [monitor configurationValueForKey:key];
	*value = [settingValue javaScriptValueInContext:context];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleSettingsSetProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	id					settingValue = nil;
	id					monitor = nil;
	
	if (!OOJS_PROPID_IS_STRING)  return YES;
	key = [NSString stringWithJavaScriptString:OOJS_PROPID_STRING];
	
	monitor = JSObjectToObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	OOJSPauseTimeLimiter();
	if (JSVAL_IS_NULL(*value) || JSVAL_IS_VOID(*value))
	{
		[monitor setConfigurationValue:nil forKey:key];
	}
	else
	{
		settingValue = JSValueToObject(context, *value);
		if (settingValue != nil)
		{
			[monitor setConfigurationValue:settingValue forKey:key];
		}
		else
		{
			OOReportJSWarning(context, @"debugConsole.settings: could not convert %@ to native object.", [NSString stringWithJavaScriptValue:*value inContext:context]);
		}
	}
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// function consoleMessage(colorCode : String, message : String [, emphasisStart : Number, emphasisLength : Number]) : void
static JSBool ConsoleConsoleMessage(OOJS_NATIVE_ARGS)
{
	NSRange				emphasisRange = {0, 0};
	
	OOJS_NATIVE_ENTER(context)
	
	id					monitor = nil;
	NSString			*colorKey = nil,
						*message = nil;
	jsdouble			location, length;
	
	OOJSPauseTimeLimiter();
	monitor = JSObjectToObjectOfClass(context, OOJS_THIS, [OODebugMonitor class]);
	if (monitor == nil)
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		OOJSResumeTimeLimiter();
		return NO;
	}
	
	colorKey = JSValToNSString(context,OOJS_ARG(0));
	message = JSValToNSString(context,OOJS_ARG(1));
	
	if (4 <= argc)
	{
		// Attempt to get two numbers, specifying an emphasis range.
		if (JS_ValueToNumber(context, OOJS_ARG(2), &location) &&
			JS_ValueToNumber(context, OOJS_ARG(3), &length))
		{
			emphasisRange = (NSRange){location, length};
		}
	}
	
	if (message == nil)
	{
		if (colorKey == nil)
		{
			OOReportJSWarning(context, @"Console.consoleMessage() called with no parameters.");
		}
		else
		{
			message = colorKey;
			colorKey = @"command-result";
		}
	}
	
	if (message != nil)
	{
		[monitor appendJSConsoleLine:message
							colorKey:colorKey
					   emphasisRange:emphasisRange];
	}
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// function clearConsole() : void
static JSBool ConsoleClearConsole(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	id					monitor = nil;
	
	monitor = JSObjectToObject(context, OOJS_THIS);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOReportJSError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	[monitor clearJSConsole];
	return YES;
	
	OOJS_NATIVE_EXIT
}


// function scriptStack() : Array
static JSBool ConsoleScriptStack(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJS_RETURN_OBJECT([OOJSScript scriptStack]);
	
	OOJS_NATIVE_EXIT
}


// function inspectEntity(entity : Entity) : void
static JSBool ConsoleInspectEntity(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	Entity				*entity = nil;
	
	if (JSValueToEntity(context, OOJS_ARG(0), &entity))
	{
		if ([entity respondsToSelector:@selector(inspect)])
		{
			OOJSPauseTimeLimiter();
			[entity inspect];
			OOJSResumeTimeLimiter();
		}
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// function callObjC(selector : String [, ...]) : Object
static JSBool ConsoleCallObjCMethod(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	id						object = nil;
	
	object = JSObjectToObject(context, OOJS_THIS);
	if (object == nil)
	{
		OOReportJSError(context, @"Attempt to call __callObjCMethod() for non-Objective-C object %@.", [NSString stringWithJavaScriptValue:OOJS_THIS_VAL inContext:context]);
		return NO;
	}
	
	OOJSPauseTimeLimiter();
	BOOL result = OOJSCallObjCObjectMethod(context, object, [object jsClassName], argc, OOJS_ARGV, outResult);
	OOJSResumeTimeLimiter();
	
	return result;
	
	OOJS_NATIVE_EXIT
}


// function __setUpCallObjC(object) -- object is expected to be Object.prototye.
static JSBool ConsoleSetUpCallObjC(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(OOJS_ARG(0))))
	{
		OOReportJSBadArguments(context, @"Console", @"__setUpCallObjC", argc, OOJS_ARGV, nil, @"Object.prototype");
		return NO;
	}
	
	JSObject *obj = JSVAL_TO_OBJECT(OOJS_ARG(0));
	JS_DefineFunction(context, obj, "callObjC", ConsoleCallObjCMethod, 1, JSPROP_PERMANENT | JSPROP_READONLY);
	return YES;
	
	OOJS_NATIVE_EXIT
}


// function isExecutableJavaScript(this : Object, string : String) : Boolean
static JSBool ConsoleIsExecutableJavaScript(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL					result = NO;
	JSObject				*target = NULL;
	
	if (argc < 2)  return YES;
	if (!JS_ValueToObject(context, OOJS_ARG(0), &target) || !JSVAL_IS_STRING(OOJS_ARG(1)))  return YES;	// Fail silently
	
	OOJSPauseTimeLimiter();
#if OO_NEW_JS
	NSString *string = JSValToNSString(context, OOJS_ARG(1));
	const char *utf8 = [string UTF8String];
	result = JS_BufferIsCompilableUnit(context, target, utf8, strlen(utf8));
#else
	JSString *string = JSVAL_TO_STRING(OOJS_ARG(1));
	result = JS_BufferIsCompilableUnit(context, target, JS_GetStringBytes(string), JS_GetStringLength(string));
#endif
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(YES);
	
	OOJS_NATIVE_EXIT
}


// function displayMessagesInClass(class : String) : Boolean
static JSBool ConsoleDisplayMessagesInClass(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*messageClass = nil;
	
	messageClass = [NSString stringWithJavaScriptValue:OOJS_ARG(0) inContext:context];
	OOJS_RETURN_BOOL(OOLogWillDisplayMessagesInClass(messageClass));
	
	OOJS_NATIVE_EXIT
}


// function setDisplayMessagesInClass(class : String, flag : Boolean) : void
static JSBool ConsoleSetDisplayMessagesInClass(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*messageClass = nil;
	JSBool					flag;
	
	messageClass = JSValToNSString(context, OOJS_ARG(0));
	if (messageClass != nil && JS_ValueToBoolean(context, OOJS_ARG(1), &flag))
	{
		OOLogSetDisplayMessagesInClass(messageClass, flag);
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// function writeLogMarker() : void
static JSBool ConsoleWriteLogMarker(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOLogInsertMarker();
	return YES;
	
	OOJS_NATIVE_EXIT
}


// function writeMemoryStats() : void
static JSBool ConsoleWriteMemoryStats(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJSPauseTimeLimiter();
	[[OODebugMonitor sharedDebugMonitor] dumpMemoryStatistics];
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


#if OOJS_PROFILE

// function profile(func : function [, Object this = debugConsole.script]) : String
static JSBool ConsoleProfile(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOTimeProfile *profile = nil;
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		OOReportJSError(context, @"Console.profile() may not be used recursively.");
		return NO;
	}
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	JSBool result = PerformProfiling(context, @"profile", argc, OOJS_ARGV, &profile);
	if (result)
	{
		OOJS_SET_RVAL([[profile description] javaScriptValueInContext:context]);
	}
	
	[pool release];
	return result;
	
	OOJS_NATIVE_EXIT
}


// function getProfile(func : function [, Object this = debugConsole.script]) : Object { totalTime : Number, jsTime : Number, extensionTime : Number }
static JSBool ConsoleGetProfile(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	OOTimeProfile *profile = nil;
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		OOReportJSError(context, @"Console.profile() may not be used recursively.");
		return NO;
	}
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	JSBool result = PerformProfiling(context, @"getProfile", argc, OOJS_ARGV, &profile);
	if (result)
	{
		OOJS_SET_RVAL([[profile description] javaScriptValueInContext:context]);
	}
	
	[pool release];
	return result;
	
	OOJS_NATIVE_EXIT
}


static JSBool PerformProfiling(JSContext *context, NSString *nominalFunction, uintN argc, jsval *argv, OOTimeProfile **profile)
{
	assert(profile != NULL);
	
	// Get function.
	jsval function = argv[0];
	if (!JSVAL_IS_OBJECT(function) || !JS_ObjectIsFunction(context, JSVAL_TO_OBJECT(function)))
	{
		OOReportJSBadArguments(context, @"Console", nominalFunction, 1, argv, nil, @"function");
		return NO;
	}
	
	// Get "this" object.
	jsval this;
	if (argc > 1)  this = argv[1];
	else
	{
		jsval debugConsole = [[OODebugMonitor sharedDebugMonitor] javaScriptValueInContext:context];
		assert(JSVAL_IS_OBJECT(debugConsole));
		JS_GetProperty(context, JSVAL_TO_OBJECT(debugConsole), "script", &this);
	}
	
	JSObject *thisObj;
	if (!JS_ValueToObject(context, this, &thisObj))  thisObj = NULL;
	
	// Fiddle with time limiter.
	// We want to save the current limit, reset the limiter, and set the time limit to a long time.
#define LONG_TIME (1e7)	// A long time - 115.7 days - but, crucially, finite.
	
	OOTimeDelta originalLimit = OOJSGetTimeLimiterLimit();
	OOJSSetTimeLimiterLimit(LONG_TIME);
	OOJSResetTimeLimiter();
	
	OOJSBeginProfiling();
	
	// Call the function.
	jsval ignored;
	BOOL result = JS_CallFunctionValue(context, thisObj, function, 0, NULL, &ignored);
	
	// Get results.
	*profile = OOJSEndProfiling();
	
	// Restore original timer state.
	OOJSSetTimeLimiterLimit(originalLimit);
	OOJSResetTimeLimiter();
	
	JS_ReportPendingException(context);
	
	return result;
}

#endif // OOJS_PROFILE

#endif /* OO_EXCLUDE_DEBUG_SUPPORT */
