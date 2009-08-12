/*

OOJSGlobal.m


Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
static JSBool GlobalDisplayNameForCommodity(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalRandomName(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


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
	{ "timeAccelerationFactor",		kGlobal_timeAccelerationFactor,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sGlobalMethods[] =
{
	// JS name					Function					min args
	{ "log",					GlobalLog,					1 },
	{ "expandDescription",		GlobalExpandDescription,	1 },
	{ "displayNameForCommodity", GlobalDisplayNameForCommodity, 1 },
	{ "randomName",				GlobalRandomName,			0 },
	{ "randomInhabitantsDescription",	GlobalRandomInhabitantsDescription,	1 },
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
	PlayerEntity				*player = OOPlayerForScripting();
	id							result = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
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
}


static JSBool GlobalSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	jsdouble					fValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	
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
}


// *** Methods ***

// log([messageClass : String,] message : string, ...)
static JSBool GlobalLog(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
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
	OOLog(messageClass, @"%@", message);
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
											withMessageClass:nil
												   inContext:context];
#endif
	
	return YES;
}


// expandDescription(description : String) : String
static JSBool GlobalExpandDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*string = nil;
	
	string = JSValToNSString(context,argv[0]);
	if (string == nil)
	{
		OOReportJSBadArguments(context, @"System", @"expandDescription", argc, argv, nil, @"string");
		return NO;
	}
	string = ExpandDescriptionForCurrentSystem(string);
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
}


// displayNameForCommodity(commodityName : String) : String
static JSBool GlobalDisplayNameForCommodity(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
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
}


// randomName() : String
static JSBool GlobalRandomName(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*string = nil;
	
	string = RandomDigrams();
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
}


// randomInhabitantsDescription() : String
static JSBool GlobalRandomInhabitantsDescription(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*string = nil;
	Random_Seed			aSeed;
	JSBool				isPlural = YES;
	
	if (!JS_ValueToBoolean(context, argv[0], &isPlural))  isPlural = NO;
	
	make_pseudo_random_seed(&aSeed);
	string = [UNIVERSE generateSystemInhabitants:aSeed plural:isPlural];
	*outResult = [string javaScriptValueInContext:context];
	
	return YES;
}
