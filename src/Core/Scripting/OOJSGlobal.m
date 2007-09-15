/*

OOJSGlobal.m


Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


#if OOJSENGINE_MONITOR_SUPPORT

@interface OOJavaScriptEngine (OOMonitorSupportInternal)

- (void)sendMonitorLogMessage:(NSString *)message
			 withMessageClass:(NSString *)messageClass
					inContext:(JSContext *)context;

@end

#endif


extern NSString * const kOOLogDebugMessage;


static JSBool GlobalGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);

static JSBool GlobalLog(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool GlobalLogWithClass(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSClass sGlobalClass =
{
	"Global",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	GlobalGetProperty,
	JS_PropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


enum
{
	// Property IDs
	kGlobal_galaxyNumber,		// galaxy number, integer, read-only
	kGlobal_planetNumber,		// planet number, integer, read-only
	kGlobal_guiScreen,			// current GUI screen, string, read-only
};


static JSPropertySpec sGlobalProperties[] =
{
	// JS name					ID							flags
	{ "galaxyNumber",			kGlobal_galaxyNumber,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "planetNumber",			kGlobal_planetNumber,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "guiScreen",				kGlobal_guiScreen,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sGlobalMethods[] =
{
	// JS name					Function					min args
	{ "Log",					GlobalLog,					1 },
	{ "LogWithClass",			GlobalLogWithClass,			2 },
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
		
		case kGlobal_planetNumber:
			OOReportJavaScriptWarning(context, @"planetNumber is deprecated, use system.ID instead.");
			*outValue = INT_TO_JSVAL([player currentSystemID]);
			break;
			
		case kGlobal_guiScreen:
			result = [player gui_screen_string];
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Global", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool GlobalLog(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	NSString			*message = nil;
	
	message = [NSString concatenationOfStringsFromJavaScriptValues:argv count:argc separator:@", " inContext:context];
	OOLog(kOOLogDebugMessage, message);
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
											withMessageClass:nil
												   inContext:context];
#endif
	
	return JS_TRUE;
}


static JSBool GlobalLogWithClass(JSContext *context, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	NSString			*msgClass = nil, *message = nil;
	
	msgClass = [NSString stringWithJavaScriptValue:argv[0] inContext:context];
	message = [NSString concatenationOfStringsFromJavaScriptValues:argv + 1 count:argc - 1 separator:@", " inContext:context];
	OOLog(msgClass, message);
	
#if OOJSENGINE_MONITOR_SUPPORT
	[[OOJavaScriptEngine sharedEngine] sendMonitorLogMessage:message
											withMessageClass:msgClass
												   inContext:context];
#endif
	
	return JS_TRUE;
}
