/*

OOJSOolite.h

JavaScript proxy for Oolite (for version checking and similar).


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

#import "OOJSOolite.h"
#import "OOJavaScriptEngine.h"
#import "OOStringParsing.h"
#import "OOJSPlayer.h"
#import "ResourceManager.h"
#import "MyOpenGLView.h"
#import "OOConstToString.h"


static JSBool OoliteGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool OoliteSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static NSString *VersionString(void);
static NSArray *VersionComponents(void);

static JSBool OoliteCompareVersion(JSContext *context, uintN argc, jsval *vp);


static JSClass sOoliteClass =
{
	"Oolite",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	OoliteGetProperty,
	OoliteSetProperty,
	//JS_StrictPropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kOolite_version,			// version number components, array, read-only
	kOolite_versionString,		// version number as string, string, read-only
	kOolite_jsVersion,			// JavaScript version, integer, read-only
	kOolite_jsVersionString,	// JavaScript version as string, string, read-only
	kOolite_gameSettings,		// Various game settings, object, read-only
	kOolite_resourcePaths,		// Paths containing resources, built-in plus oxp/oxz, read-only
	kOolite_colorSaturation,	// Color saturation, integer, read/write
	kOolite_postFX,				// current post processing effect, integer, read/write
	kOolite_hdrToneMapper,		// currently active HDR tone mapper, string, read/write
#ifndef NDEBUG
	kOolite_timeAccelerationFactor,	// time acceleration, float, read/write
#endif
};


static JSPropertySpec sOoliteProperties[] =
{
	// JS name					ID							flags
	{ "gameSettings",			kOolite_gameSettings,		OOJS_PROP_READONLY_CB },
	{ "jsVersion",				kOolite_jsVersion,			OOJS_PROP_READONLY_CB },
	{ "jsVersionString",		kOolite_jsVersionString,	OOJS_PROP_READONLY_CB },
	{ "version",				kOolite_version,			OOJS_PROP_READONLY_CB },
	{ "versionString",			kOolite_versionString,		OOJS_PROP_READONLY_CB },
	{ "resourcePaths",			kOolite_resourcePaths,		OOJS_PROP_READONLY_CB },
	{ "colorSaturation",		kOolite_colorSaturation,	OOJS_PROP_READWRITE_CB },
	{ "postFX",					kOolite_postFX,				OOJS_PROP_READWRITE_CB },
	{ "hdrToneMapper",			kOolite_hdrToneMapper, 		OOJS_PROP_READWRITE_CB },
#ifndef NDEBUG
	{ "timeAccelerationFactor",	kOolite_timeAccelerationFactor,	OOJS_PROP_READWRITE_CB },
#endif
	{ 0 }
};


static JSFunctionSpec sOoliteMethods[] =
{
	// JS name					Function					min args
	{ "compareVersion",			OoliteCompareVersion,		1 },
	{ 0 }
};


void InitOOJSOolite(JSContext *context, JSObject *global)
{
	JSObject *oolitePrototype = JS_InitClass(context, global, NULL, &sOoliteClass, OOJSUnconstructableConstruct, 0, sOoliteProperties, sOoliteMethods, NULL, NULL);
	JS_DefineObject(context, global, "oolite", &sOoliteClass, oolitePrototype, OOJS_PROP_READONLY);
}


static JSBool OoliteGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	id						result = nil;
	MyOpenGLView			*gameView = [UNIVERSE gameView];
	
	switch (JSID_TO_INT(propID))
	{
		case kOolite_version:
			result = VersionComponents();
			break;
		
		case kOolite_versionString:
			result = VersionString();
			break;
		
		case kOolite_jsVersion:
			*value = INT_TO_JSVAL(JS_GetVersion(context));
			return YES;
		
		case kOolite_jsVersionString:
			*value = STRING_TO_JSVAL(JS_NewStringCopyZ(context, JS_VersionToString(JS_GetVersion(context))));
			return YES;
		
		case kOolite_gameSettings:
			result = [UNIVERSE gameSettings];
			break;
			
		case kOolite_resourcePaths:
			result = [ResourceManager paths];
			break;
			
		case kOolite_colorSaturation:
			return JS_NewNumberValue(context, [gameView colorSaturation], value);
			
		case kOolite_postFX:
			*value = INT_TO_JSVAL([UNIVERSE currentPostFX]);
			return YES;
			
		case kOolite_hdrToneMapper:
		{
			NSString *toneMapperStr = @"OOHDR_TONEMAPPER_UNDEFINED";
#if OOLITE_WINDOWS
			if ([gameView hdrOutput])
			{
				toneMapperStr = OOStringFromHDRToneMapper([gameView hdrToneMapper]);
			}
#endif
			result = toneMapperStr;
			break;
		}
			
#ifndef NDEBUG
		case kOolite_timeAccelerationFactor:
			return JS_NewNumberValue(context, [UNIVERSE timeAccelerationFactor], value);
#endif
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sOoliteProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool OoliteSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	jsdouble				fValue;
	int32					iValue;
	NSString				*sValue = nil;
	MyOpenGLView 			*gameView = [UNIVERSE gameView];
	
	switch (JSID_TO_INT(propID))
	{
		case kOolite_colorSaturation:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				float currentColorSaturation = [gameView colorSaturation];
				[gameView adjustColorSaturation:fValue - currentColorSaturation];
				return YES;
			}
			break;
			
		case kOolite_postFX:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				iValue = MAX(iValue, 0);
				[UNIVERSE setCurrentPostFX:iValue];
				return YES;
			}
			break;
			
		case kOolite_hdrToneMapper:
			if (!JSVAL_IS_STRING(*value))  break; // non-string is not allowed
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
#if OOLITE_WINDOWS
				[gameView setHDRToneMapper:OOHDRToneMapperFromString(sValue)];
#endif
				return YES;
			}
			break;
			
#ifndef NDEBUG
		case kOolite_timeAccelerationFactor:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[UNIVERSE setTimeAccelerationFactor:fValue];
				return YES;
			}
			break;
#endif
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sOoliteProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sOoliteProperties, *value);
	return NO;
	
	OOJS_NATIVE_EXIT
}


static NSString *VersionString(void)
{
	return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}


static NSArray *VersionComponents(void)
{
	return ComponentsFromVersionString(VersionString());
}


/*	oolite.compareVersion(versionSpec) : Number
	returns -1 if the current version of Oolite is less than versionSpec, 0 if
	they are equal, and 1 if the current version is newer. versionSpec may be
	a string or an array. Example:
	if (0 < oolite.compareVersion("1.70"))  log("Old version of Oolite!")
	else  this.doStuffThatRequires170()
*/
static JSBool OoliteCompareVersion(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	id						components = nil;
	NSEnumerator			*componentEnum = nil;
	id						component = nil;
	
	if (argc == 0)  OOJS_RETURN_VOID;	// Backwards-compatibility: be overly lenient.
	
	components = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[0]);
	if ([components isKindOfClass:[NSArray class]])
	{
		// Require each element to be a number
		for (componentEnum = [components objectEnumerator]; (component = [componentEnum nextObject]); )
		{
			if (![component isKindOfClass:[NSNumber class]])
			{
				components = nil;
				break;
			}
		}
	}
	else if ([components isKindOfClass:[NSString class]])
	{
		components = ComponentsFromVersionString(components);
	}
	else  components = nil;
	
	if (components != nil)
	{
		OOJS_RETURN_INT((int32_t)CompareVersions(components, VersionComponents()));
	}
	else
	{
		OOJS_RETURN_VOID;
	}
	
	OOJS_NATIVE_EXIT
}
