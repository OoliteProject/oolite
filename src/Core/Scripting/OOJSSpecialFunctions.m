/*

OOJSSpecialFunctions.m


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

#import <jsdbgapi.h>
#import "OOJSSpecialFunctions.h"


static JSObject		*sSpecialFunctionsObject;


static JSBool SpecialJSWarning(JSContext *context, uintN argc, jsval *vp);
#ifndef NDEBUG
static JSBool SpecialMarkConsoleEntryPoint(JSContext *context, uintN argc, jsval *vp);
#endif


static JSFunctionSpec sSpecialFunctionsMethods[] =
{
	// JS name					Function						min args
	{ "jsWarning",				SpecialJSWarning,				1 },
#ifndef NDEBUG
	{ "markConsoleEntryPoint",	SpecialMarkConsoleEntryPoint,	0 },
#endif
	{ 0 }
};


void InitOOJSSpecialFunctions(JSContext *context, JSObject *global)
{
	sSpecialFunctionsObject = JS_NewObject(context, NULL, NULL, NULL);
	OOJSAddGCObjectRoot(context, &sSpecialFunctionsObject, "OOJSSpecialFunctions");
	JS_DefineFunctions(context, sSpecialFunctionsObject, sSpecialFunctionsMethods);
	
	JS_FreezeObject(context, sSpecialFunctionsObject);
}


JSObject *JSSpecialFunctionsObject(void)
{
	return sSpecialFunctionsObject;
}


OOJSValue *JSSpecialFunctionsObjectWrapper(JSContext *context)
{
	return [OOJSValue valueWithJSObject:JSSpecialFunctionsObject() inContext:context];
}


static JSBool SpecialJSWarning(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER	// These functions are exception-safe
	
	if (EXPECT_NOT(argc < 1))
	{
		OOJSReportBadArguments(context, @"special", @"jsWarning", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	
	OOJSSetWarningOrErrorStackSkip(1);
	OOJSReportWarning(context, @"%@", OOStringFromJSValue(context, OOJS_ARGV[0]));
	OOJSSetWarningOrErrorStackSkip(0);
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


#ifndef NDEBUG
static JSBool SpecialMarkConsoleEntryPoint(JSContext *context, uintN argc, jsval *vp)
{
	// First stack frame will be in eval() in console.script.evaluate(), unless someone is playing silly buggers.
	
	JSStackFrame *frame = NULL;
	if (JS_FrameIterator(context, &frame) != NULL)
	{
		OOJSMarkConsoleEvalLocation(context, frame);
	}
	
	OOJS_RETURN_VOID;
}
#endif
