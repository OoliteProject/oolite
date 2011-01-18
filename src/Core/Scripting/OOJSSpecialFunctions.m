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


static JSBool SpecialJSWarning(OOJS_NATIVE_ARGS);
static JSBool SpecialMarkConsoleEntryPoint(OOJS_NATIVE_ARGS);


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
#if OO_NEW_JS
	JS_FreezeObject(context, sSpecialFunctionsObject);
#else
	JS_SealObject(context, sSpecialFunctionsObject, NO);
#endif
}


JSObject *JSSpecialFunctionsObject(void)
{
	return sSpecialFunctionsObject;
}


OOJSValue *JSSpecialFunctionsObjectWrapper(JSContext *context)
{
	return [OOJSValue valueWithJSObject:JSSpecialFunctionsObject() inContext:context];
}


static JSBool SpecialJSWarning(OOJS_NATIVE_ARGS)
{
	OOJS_PROFILE_ENTER	// These functions are exception-safe
	
	OOJSSetWarningOrErrorStackSkip(1);
	OOJSReportWarning(context, @"%@", OOStringFromJSValue(context, OOJS_ARG(0)));
	OOJSSetWarningOrErrorStackSkip(0);
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool SpecialMarkConsoleEntryPoint(OOJS_NATIVE_ARGS)
{
	// First stack frame will be in eval() in console.script.evaluate(), unless someone is playing silly buggers.
	
	JSStackFrame *frame = NULL;
	if (JS_FrameIterator(context, &frame) != NULL)
	{
		OOJSMarkConsoleEvalLocation(context, frame);
	}
	
	return YES;
}
