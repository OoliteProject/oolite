/*

OOJSConsole.m


Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#include <stdint.h>

#import "OOJSEngineTimeManagement.h"
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
#import "ResourceManager.h"


@interface Entity (OODebugInspector)

// Method added by inspector in Debug OXP under OS X only.
- (void) inspect;

@end


NSString *OOPlatformDescription(void);


static JSObject *sConsolePrototype = NULL;
static JSObject *sConsoleSettingsPrototype = NULL;


static JSBool ConsoleGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ConsoleSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
static void ConsoleFinalize(JSContext *context, JSObject *this);

// Methods
static JSBool ConsoleConsoleMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleClearConsole(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleScriptStack(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleInspectEntity(JSContext *context, uintN argc, jsval *vp);
#if OO_DEBUG
static JSBool ConsoleCallObjCMethod(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleSetUpCallObjC(JSContext *context, uintN argc, jsval *vp);
#endif
static JSBool ConsoleIsExecutableJavaScript(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleDisplayMessagesInClass(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleSetDisplayMessagesInClass(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleWriteLogMarker(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleWriteMemoryStats(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleGarbageCollect(JSContext *context, uintN argc, jsval *vp);
#if DEBUG
static JSBool ConsoleDumpNamedRoots(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleDumpHeap(JSContext *context, uintN argc, jsval *vp);
#endif
#if OOJS_PROFILE
static JSBool ConsoleProfile(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleGetProfile(JSContext *context, uintN argc, jsval *vp);
static JSBool ConsoleTrace(JSContext *context, uintN argc, jsval *vp);
#endif

static JSBool ConsoleSettingsDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ConsoleSettingsGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ConsoleSettingsSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

#if OOJS_PROFILE
static JSBool PerformProfiling(JSContext *context, NSString *nominalFunction, uintN argc, jsval *argv, jsval *rval, BOOL trace, OOTimeProfile **profile);
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
	kConsole_ignoreDroppedPackets,				// boolean (default false), read/write
	kConsole_pedanticMode,						// JS pedantic mode (JS_STRICT flag, not the same as "use strict"), boolean (default true), read/write
	kConsole_showErrorLocations,				// Show error/warning source locations, boolean (default true), read/write
	kConsole_dumpStackForErrors,				// Write stack dump when reporting error/exception, boolean (default false), read/write
	kConsole_dumpStackForWarnings,				// Write stack dump when reporting warning, boolean (default false), read/write
	
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
	{ "debugFlags",							kConsole_debugFlags,						OOJS_PROP_READWRITE_CB },
	{ "shaderMode",							kConsole_shaderMode,						OOJS_PROP_READWRITE_CB },
	{ "maximumShaderMode",					kConsole_maximumShaderMode,					OOJS_PROP_READONLY_CB },
	{ "reducedDetailMode",					kConsole_reducedDetailMode,					OOJS_PROP_READWRITE_CB },
	{ "displayFPS",							kConsole_displayFPS,						OOJS_PROP_READWRITE_CB },
	{ "platformDescription",				kConsole_platformDescription,				OOJS_PROP_READONLY_CB },
	{ "pedanticMode",						kConsole_pedanticMode,						OOJS_PROP_READWRITE_CB },
	{ "ignoreDroppedPackets",				kConsole_ignoreDroppedPackets,				OOJS_PROP_READWRITE_CB },
	{ "__showErrorLocations",				kConsole_showErrorLocations,				OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "__dumpStackForErrors",				kConsole_dumpStackForErrors,				OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "__dumpStackForWarnings",				kConsole_dumpStackForWarnings,				OOJS_PROP_HIDDEN_READWRITE_CB },
	{ "glVendorString",						kConsole_glVendorString,					OOJS_PROP_READONLY_CB },
	{ "glRendererString",					kConsole_glRendererString,					OOJS_PROP_READONLY_CB },
	{ "glFixedFunctionTextureUnitCount",	kConsole_glFixedFunctionTextureUnitCount,	OOJS_PROP_READONLY_CB },
	{ "glFragmentShaderTextureUnitCount",	kConsole_glFragmentShaderTextureUnitCount,	OOJS_PROP_READONLY_CB },
	
#define DEBUG_FLAG_DECL(x) { #x, kConsole_##x, OOJS_PROP_READONLY_CB }
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
#if OO_DEBUG
	{ "__setUpCallObjC",				ConsoleSetUpCallObjC,				1 },
#endif
	{ "isExecutableJavaScript",			ConsoleIsExecutableJavaScript,		2 },
	{ "displayMessagesInClass",			ConsoleDisplayMessagesInClass,		1 },
	{ "setDisplayMessagesInClass",		ConsoleSetDisplayMessagesInClass,	2 },
	{ "writeLogMarker",					ConsoleWriteLogMarker,				0 },
	{ "writeMemoryStats",				ConsoleWriteMemoryStats,			0 },
	{ "garbageCollect",					ConsoleGarbageCollect,				0 },
#if DEBUG
	{ "dumpNamedRoots",					ConsoleDumpNamedRoots,				0 },
	{ "dumpHeap",						ConsoleDumpHeap,					0 },
#endif
#if OOJS_PROFILE
	{ "profile",						ConsoleProfile,						1 },
	{ "getProfile",						ConsoleGetProfile,					1 },
	{ "trace",							ConsoleTrace,						1 },
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
	sConsolePrototype = JS_InitClass(context, global, NULL, &sConsoleClass, OOJSUnconstructableConstruct, 0, sConsoleProperties, sConsoleMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sConsoleClass, OOJSBasicPrivateObjectConverter);
	
	sConsoleSettingsPrototype = JS_InitClass(context, global, NULL, &sConsoleSettingsClass, OOJSUnconstructableConstruct, 0, NULL, NULL, NULL, NULL);
	OOJSRegisterObjectConverter(&sConsoleSettingsClass, OOJSBasicPrivateObjectConverter);
}


void OOJSConsoleDestroy(void)
{
	sConsolePrototype = NULL;
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


static JSBool ConsoleGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	switch (JSID_TO_INT(propID))
	{
#ifndef NDEBUG
		case kConsole_debugFlags:
			*value = INT_TO_JSVAL(gDebugFlags);
			break;
#endif		
			
		case kConsole_shaderMode:
			// EMMSTRAN: if still relevant, OOConstToJSString-ify.
			*value = OOJSValueFromNativeObject(context, OOStringFromShaderSetting([UNIVERSE shaderEffectsLevel]));
			break;
			
		case kConsole_maximumShaderMode:
			*value = OOJSValueFromNativeObject(context, OOStringFromShaderSetting([[OOOpenGLExtensionManager sharedManager] maximumShaderSetting]));
			break;
			
		case kConsole_reducedDetailMode:
			*value = OOJSValueFromBOOL([UNIVERSE reducedDetail]);
			break;
			
		case kConsole_displayFPS:
			*value = OOJSValueFromBOOL([UNIVERSE displayFPS]);
			break;
			
		case kConsole_platformDescription:
			*value = OOJSValueFromNativeObject(context, OOPlatformDescription());
			break;
			
		case kConsole_pedanticMode:
			{
				uint32_t options = JS_GetOptions(context);
				*value = OOJSValueFromBOOL(options & JSOPTION_STRICT);
			}
			break;
			
		case kConsole_ignoreDroppedPackets:
			*value = OOJSValueFromBOOL([[OODebugMonitor sharedDebugMonitor] TCPIgnoresDroppedPackets]);
			break;
			
		case kConsole_showErrorLocations:
			*value = OOJSValueFromBOOL([[OOJavaScriptEngine sharedEngine] showErrorLocations]);
			break;
			
		case kConsole_dumpStackForErrors:
			*value = OOJSValueFromBOOL([[OOJavaScriptEngine sharedEngine] dumpStackForErrors]);
			break;
			
		case kConsole_dumpStackForWarnings:
			*value = OOJSValueFromBOOL([[OOJavaScriptEngine sharedEngine] dumpStackForWarnings]);
			break;
			
		case kConsole_glVendorString:
			*value = OOJSValueFromNativeObject(context, [[OOOpenGLExtensionManager sharedManager] vendorString]);
			break;
			
		case kConsole_glRendererString:
			*value = OOJSValueFromNativeObject(context, [[OOOpenGLExtensionManager sharedManager] rendererString]);
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
			OOJSReportBadPropertySelector(context, this, propID, sConsoleProperties);
			return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	int32						iValue;
	NSString					*sValue = nil;
	JSBool						bValue = NO;
	
	switch (JSID_TO_INT(propID))
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
			sValue = OOStringFromJSValue(context, *value);
			if (sValue != nil)
			{
				OOJS_BEGIN_FULL_NATIVE(context)
				OOShaderSetting setting = OOShaderSettingFromString(sValue);
				[UNIVERSE setShaderEffectsLevel:setting transiently:YES];
				OOJS_END_FULL_NATIVE
			}
			break;
			
		case kConsole_reducedDetailMode:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				OOJS_BEGIN_FULL_NATIVE(context)
				[UNIVERSE setReducedDetail:bValue transiently:YES];
				OOJS_END_FULL_NATIVE
			}
			break;
			
		case kConsole_displayFPS:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[UNIVERSE setDisplayFPS:bValue];
			}
			break;
			
		case kConsole_pedanticMode:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				uint32_t options = JS_GetOptions(context);
				if (bValue)  options |= JSOPTION_STRICT;
				else  options &= ~JSOPTION_STRICT;
				
				JS_SetOptions(context, options);
			}
			break;
			
		case kConsole_ignoreDroppedPackets:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[OODebugMonitor sharedDebugMonitor] setTCPIgnoresDroppedPackets:bValue];
			}
			break;
			
		case kConsole_showErrorLocations:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[OOJavaScriptEngine sharedEngine] setShowErrorLocations:bValue];
			}
			break;
			
		case kConsole_dumpStackForErrors:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[OOJavaScriptEngine sharedEngine] setDumpStackForErrors:bValue];
			}
			break;
			
		case kConsole_dumpStackForWarnings:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[[OOJavaScriptEngine sharedEngine] setDumpStackForWarnings:bValue];
			}
			break;
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sConsoleProperties);
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


static JSBool ConsoleSettingsDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	id					monitor = nil;
	
	if (!JSID_IS_STRING(propID))  return NO;
	key = OOStringFromJSString(context, JSID_TO_STRING(propID));
	
	monitor = OOJSNativeObjectFromJSObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	[monitor setConfigurationValue:nil forKey:key];
	*value = JSVAL_TRUE;
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleSettingsGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_STRING(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	id					settingValue = nil;
	id					monitor = nil;
	
	key = OOStringFromJSString(context, JSID_TO_STRING(propID));
	
	monitor = OOJSNativeObjectFromJSObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	settingValue = [monitor configurationValueForKey:key];
	if (settingValue != NULL)  *value = [settingValue oo_jsValueInContext:context];
	else  *value = JSVAL_VOID;
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleSettingsSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_STRING(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	NSString			*key = nil;
	id					settingValue = nil;
	id					monitor = nil;
	
	key = OOStringFromJSString(context, JSID_TO_STRING(propID));
	
	monitor = OOJSNativeObjectFromJSObject(context, this);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	if (JSVAL_IS_NULL(*value) || JSVAL_IS_VOID(*value))
	{
		[monitor setConfigurationValue:nil forKey:key];
	}
	else
	{
		settingValue = OOJSNativeObjectFromJSValue(context, *value);
		if (settingValue != nil)
		{
			[monitor setConfigurationValue:settingValue forKey:key];
		}
		else
		{
			OOJSReportWarning(context, @"debugConsole.settings: could not convert %@ to native object.", OOStringFromJSValue(context, *value));
		}
	}
	OOJSResumeTimeLimiter();
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

// function consoleMessage(colorCode : String, message : String [, emphasisStart : Number, emphasisLength : Number]) : void
static JSBool ConsoleConsoleMessage(JSContext *context, uintN argc, jsval *vp)
{
	NSRange				emphasisRange = {0, 0};
	
	OOJS_NATIVE_ENTER(context)
	
	id					monitor = nil;
	NSString			*colorKey = nil,
						*message = nil;
	jsdouble			location, length;
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	monitor = OOJSNativeObjectOfClassFromJSObject(context, OOJS_THIS, [OODebugMonitor class]);
	if (monitor == nil)
	{
		OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		OOJSResumeTimeLimiter();
		return NO;
	}
	
	if (argc > 0) colorKey = OOStringFromJSValue(context,OOJS_ARGV[0]);
	if (argc > 1) message = OOStringFromJSValue(context,OOJS_ARGV[1]);
	
	if (argc > 3)
	{
		// Attempt to get two numbers, specifying an emphasis range.
		if (JS_ValueToNumber(context, OOJS_ARGV[2], &location) &&
			JS_ValueToNumber(context, OOJS_ARGV[3], &length))
		{
			emphasisRange = (NSRange){location, length};
		}
	}
	
	if (message == nil)
	{
		if (colorKey == nil)
		{
			OOJSReportWarning(context, @"Console.consoleMessage() called with no parameters.");
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
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function clearConsole() : void
static JSBool ConsoleClearConsole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	id					monitor = nil;
	
	monitor = OOJSNativeObjectFromJSObject(context, OOJS_THIS);
	if (![monitor isKindOfClass:[OODebugMonitor class]])
	{
		OOJSReportError(context, @"Expected OODebugMonitor, got %@ in %s. %@", [monitor class], __PRETTY_FUNCTION__, @"This is an internal error, please report it.");
		return NO;
	}
	
	[monitor clearJSConsole];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function scriptStack() : Array
static JSBool ConsoleScriptStack(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJS_RETURN_OBJECT([OOJSScript scriptStack]);
	
	OOJS_NATIVE_EXIT
}


// function inspectEntity(entity : Entity) : void
static JSBool ConsoleInspectEntity(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	Entity				*entity = nil;
	
	if (JSValueToEntity(context, OOJS_ARGV[0], &entity))
	{
		OOJS_BEGIN_FULL_NATIVE(context)
		if ([entity respondsToSelector:@selector(inspect)])
		{
			[entity inspect];
		}
		OOJS_END_FULL_NATIVE
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


#if OO_DEBUG
// function callObjC(selector : String [, ...]) : Object
static JSBool ConsoleCallObjCMethod(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	id						object = nil;
	jsval					result;
	BOOL					OK;
	
	object = OOJSNativeObjectFromJSObject(context, OOJS_THIS);
	if (object == nil)
	{
		OOJSReportError(context, @"Attempt to call __callObjCMethod() for non-Objective-C object %@.", OOStringFromJSValueEvenIfNull(context, JS_THIS(context, vp)));
		return NO;
	}
	
	OOJSPauseTimeLimiter();
	result = JSVAL_VOID;
	OK = OOJSCallObjCObjectMethod(context, object, [object oo_jsClassName], argc, OOJS_ARGV, &result);
	OOJSResumeTimeLimiter();
	
	OOJS_SET_RVAL(result);
	return OK;
	
	OOJS_NATIVE_EXIT
}


// function __setUpCallObjC(object) -- object is expected to be Object.prototye.
static JSBool ConsoleSetUpCallObjC(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(OOJS_ARGV[0])))
	{
		OOJSReportBadArguments(context, @"Console", @"__setUpCallObjC", argc, OOJS_ARGV, nil, @"Object.prototype");
		return NO;
	}
	
	JSObject *obj = JSVAL_TO_OBJECT(OOJS_ARGV[0]);
	JS_DefineFunction(context, obj, "callObjC", ConsoleCallObjCMethod, 1, OOJS_METHOD_READONLY);
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}
#endif


// function isExecutableJavaScript(this : Object, string : String) : Boolean
static JSBool ConsoleIsExecutableJavaScript(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL					result = NO;
	JSObject				*target = NULL;
	
	if (argc < 2 || !JS_ValueToObject(context, OOJS_ARGV[0], &target) || !JSVAL_IS_STRING(OOJS_ARGV[1]))
	{
		OOJS_RETURN_BOOL(NO);	// Fail silently
	}
	
	// Not OOJS_BEGIN_FULL_NATIVE() - we use JSAPI while paused.
	OOJSPauseTimeLimiter();
	
	// FIXME: this must be possible using just JSAPI functions.
	NSString *string = OOStringFromJSValue(context, OOJS_ARGV[1]);
	NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
	result = JS_BufferIsCompilableUnit(context, target, [stringData bytes], [stringData length]);
	
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(YES);
	
	OOJS_NATIVE_EXIT
}


// function displayMessagesInClass(class : String) : Boolean
static JSBool ConsoleDisplayMessagesInClass(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*messageClass = nil;
	
	messageClass = OOStringFromJSValue(context, OOJS_ARGV[0]);
	OOJS_RETURN_BOOL(messageClass != nil && OOLogWillDisplayMessagesInClass(messageClass));
	
	OOJS_NATIVE_EXIT
}


// function setDisplayMessagesInClass(class : String, flag : Boolean) : void
static JSBool ConsoleSetDisplayMessagesInClass(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSString				*messageClass = nil;
	JSBool					flag;
	
	messageClass = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (messageClass != nil && JS_ValueToBoolean(context, OOJS_ARGV[1], &flag))
	{
		OOLogSetDisplayMessagesInClass(messageClass, flag);
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function writeLogMarker() : void
static JSBool ConsoleWriteLogMarker(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOLogInsertMarker();
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function writeMemoryStats() : void
static JSBool ConsoleWriteMemoryStats(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	OOJS_BEGIN_FULL_NATIVE(context)
	[[OODebugMonitor sharedDebugMonitor] dumpMemoryStatistics];
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// function garbageCollect() : string
static JSBool ConsoleGarbageCollect(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	uint32_t bytesBefore = JS_GetGCParameter(JS_GetRuntime(context), JSGC_BYTES);
	JS_GC(context);
	uint32_t bytesAfter = JS_GetGCParameter(JS_GetRuntime(context), JSGC_BYTES);
	
	OOJS_RETURN_OBJECT(([NSString stringWithFormat:@"Bytes before: %u Bytes after: %u", bytesBefore, bytesAfter]));
	
	OOJS_NATIVE_EXIT
}


#if DEBUG
typedef struct
{
	JSContext		*context;
	FILE			*file;
} DumpCallbackData;

static void DumpCallback(const char *name, void *rp, JSGCRootType type, void *datap)
{
	assert(type == JS_GC_ROOT_VALUE_PTR || type == JS_GC_ROOT_GCTHING_PTR);
	
	DumpCallbackData *data = datap;
	
	const char *typeString = "unknown type";
	jsval value;
	switch (type)
	{
		case JS_GC_ROOT_VALUE_PTR:
			typeString = "value";
			value = *(jsval *)rp;
			break;
			
		case JS_GC_ROOT_GCTHING_PTR:
			typeString = "gc-thing";
			value = OBJECT_TO_JSVAL(*(JSObject **)rp);
	}
	
	fprintf(data->file, "%s @ %p (%s): %s\n", name, rp, typeString, [OOJSDescribeValue(data->context, value, NO) UTF8String]);
}


static JSBool ConsoleDumpNamedRoots(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	BOOL OK = NO;
	NSString *path = [[ResourceManager diagnosticFileLocation] stringByAppendingPathComponent:@"js-roots.txt"];
	FILE *file = fopen([path UTF8String], "w");
	if (file != NULL)
	{
		DumpCallbackData data =
		{
			.context = context,
			.file = file
		};
		JS_DumpNamedRoots(JS_GetRuntime(context), DumpCallback, &data);
		fclose(file);
		OK = YES;
	}
	
	[pool release];
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static JSBool ConsoleDumpHeap(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	BOOL OK = NO;
	NSString *path = [[ResourceManager diagnosticFileLocation] stringByAppendingPathComponent:@"js-heaps.txt"];
	FILE *file = fopen([path UTF8String], "w");
	if (file != NULL)
	{
		OK = JS_DumpHeap(context, file, NULL, 0, NULL, SIZE_MAX, NULL);
		fclose(file);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}
#endif


#if OOJS_PROFILE

// function profile(func : function [, Object this = debugConsole.script]) : String
static JSBool ConsoleProfile(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		OOJSReportError(context, @"Profiling functions may not be called while already profiling.");
		return NO;
	}
	
	NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
	OOTimeProfile		*profile = nil;
	
	JSBool result = PerformProfiling(context, @"profile", argc, OOJS_ARGV, NULL, NO, &profile);
	if (result)
	{
		OOJS_SET_RVAL(OOJSValueFromNativeObject(context, [profile description]));
	}
	
	[pool release];
	return result;
	
	OOJS_NATIVE_EXIT
}


// function getProfile(func : function [, Object this = debugConsole.script]) : Object { totalTime : Number, jsTime : Number, extensionTime : Number }
static JSBool ConsoleGetProfile(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		OOJSReportError(context, @"Profiling functions may not be called while already profiling.");
		return NO;
	}
	
	NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
	OOTimeProfile		*profile = nil;
	
	JSBool result = PerformProfiling(context, @"getProfile", argc, OOJS_ARGV, NULL, NO, &profile);
	if (result)
	{
		OOJS_SET_RVAL(OOJSValueFromNativeObject(context, profile));
	}
	
	[pool release];
	return result;
	
	OOJS_NATIVE_EXIT
}


// function trace(func : function [, Object this = debugConsole.script]) : [return type of func]
static JSBool ConsoleTrace(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	if (EXPECT_NOT(OOJSIsProfiling()))
	{
		OOJSReportError(context, @"Profiling functions may not be called while already profiling.");
		return NO;
	}
	
	NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
	jsval				rval;
	
	JSBool result = PerformProfiling(context, @"trace", argc, OOJS_ARGV, &rval, YES, NULL);
	if (result)
	{
		OOJS_SET_RVAL(rval);
	}
	
	[pool release];
	return result;
	
	OOJS_NATIVE_EXIT
}


static JSBool PerformProfiling(JSContext *context, NSString *nominalFunction, uintN argc, jsval *argv, jsval *outRval, BOOL trace, OOTimeProfile **outProfile)
{
	// Get function.
	jsval function = argv[0];
	if (!OOJSValueIsFunction(context, function))
	{
		OOJSReportBadArguments(context, @"Console", nominalFunction, 1, argv, nil, @"function");
		return NO;
	}
	
	// Get "this" object.
	jsval this;
	if (argc > 1)  this = argv[1];
	else
	{
		jsval debugConsole = OOJSValueFromNativeObject(context, [OODebugMonitor sharedDebugMonitor]);
		assert(JSVAL_IS_OBJECT(debugConsole) && !JSVAL_IS_NULL(debugConsole));
		JS_GetProperty(context, JSVAL_TO_OBJECT(debugConsole), "script", &this);
	}
	
	JSObject *thisObj;
	if (!JS_ValueToObject(context, this, &thisObj))  thisObj = NULL;
	
	jsval ignored;
	if (outRval == NULL)  outRval = &ignored;
	
	// Fiddle with time limiter.
	// We want to save the current limit, reset the limiter, and set the time limit to a long time.
#define LONG_TIME (1e7)	// A long time - 115.7 days - but, crucially, finite.
	
	OOTimeDelta originalLimit = OOJSGetTimeLimiterLimit();
	OOJSSetTimeLimiterLimit(LONG_TIME);
	OOJSResetTimeLimiter();
	
	OOJSBeginProfiling(trace);
	
	// Call the function.
	BOOL result = JS_CallFunctionValue(context, thisObj, function, 0, NULL, outRval);
	
	// Get results.
	OOTimeProfile *profile = OOJSEndProfiling();
	if (outProfile != NULL)  *outProfile = profile;
	
	// Restore original timer state.
	OOJSSetTimeLimiterLimit(originalLimit);
	OOJSResetTimeLimiter();
	
	JS_ReportPendingException(context);
	
	return result;
}

#endif // OOJS_PROFILE

#endif /* OO_EXCLUDE_DEBUG_SUPPORT */
