/*

OOJSSpecialFunctions.m


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import "OOJSSpecialFunctions.h"


static JSObject		*sSpecialFunctionsObject;


static JSBool SpecialJSWarning(OOJS_NATIVE_ARGS);


static JSFunctionSpec sSpecialFunctionsMethods[] =
{
	// JS name					Function					min args
	{ "jsWarning",				SpecialJSWarning,			1 },
	{ 0 }
};


void InitOOJSSpecialFunctions(JSContext *context, JSObject *global)
{
	sSpecialFunctionsObject = JS_NewObject(context, NULL, NULL, NULL);
	OOJS_AddGCObjectRoot(context, &sSpecialFunctionsObject, "OOJSSpecialFunctions");
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
	
	OOSetJSWarningOrErrorStackSkip(1);
	OOReportJSWarning(context, @"%@", [NSString stringWithJavaScriptValue:OOJS_ARG(0) inContext:context]);
	OOSetJSWarningOrErrorStackSkip(0);
	return YES;
	
	OOJS_PROFILE_EXIT
}
