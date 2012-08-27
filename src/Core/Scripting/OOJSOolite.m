/*

OOJSOolite.h

JavaScript proxy for Oolite (for version checking and similar).


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

#import "OOJSOolite.h"
#import "OOJavaScriptEngine.h"
#import "OOStringParsing.h"
#import "OOJSPlayer.h"


static JSBool OoliteGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);

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
	JS_StrictPropertyStub,
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
};


static JSPropertySpec sOoliteProperties[] =
{
	// JS name					ID							flags
	{ "gameSettings",			kOolite_gameSettings,		OOJS_PROP_READONLY_CB },
	{ "jsVersion",				kOolite_jsVersion,			OOJS_PROP_READONLY_CB },
	{ "jsVersionString",		kOolite_jsVersionString,	OOJS_PROP_READONLY_CB },
	{ "version",				kOolite_version,			OOJS_PROP_READONLY_CB },
	{ "versionString",			kOolite_versionString,		OOJS_PROP_READONLY_CB },
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
		
		default:
			OOJSReportBadPropertySelector(context, this, propID, sOoliteProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
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
