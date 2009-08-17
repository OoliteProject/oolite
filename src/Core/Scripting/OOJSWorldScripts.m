/*

OOJSWorldScripts.m


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

#import "OOJSWorldScripts.h"
#import "OOJavaScriptEngine.h"
#import "PlayerEntity.h"
#import "OOJSPlayer.h"


static JSBool WorldScriptsGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool WorldScriptsEnumerate(JSContext *cx, JSObject *obj);

static JSBool GetWorldScriptNames(JSContext *context, JSObject *this, jsval name, jsval *outValue);


static JSClass sWorldScriptsClass =
{
	"WorldScripts",
	JSCLASS_IS_ANONYMOUS,
	
	JS_PropertyStub,
	JS_PropertyStub,
	WorldScriptsGetProperty,
	JS_PropertyStub,
	WorldScriptsEnumerate,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


void InitOOJSWorldScripts(JSContext *context, JSObject *global)
{
	JS_DefineObject(context, global, "worldScripts", &sWorldScriptsClass, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
	JS_DefineProperty(context, global, "worldScriptNames", JSVAL_NULL, GetWorldScriptNames, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool WorldScriptsGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*scriptName = nil;
	id							script = nil;
	
	scriptName = JSValToNSString(context, name);
	if (scriptName != nil)
	{
		script = [[player worldScriptsByName] objectForKey:scriptName];
		if (script != nil)
		{
			/*	If script is an OOJSScript, this should return a JS Script
			 object. For other OOScript subclasses, it will return
			 JSVAL_NULL. If no script exists, the value will be
			 JSVAL_VOID.
			 */
			*outValue = [script javaScriptValueInContext:context];
		}
	}
	
	return YES;
}


static JSBool WorldScriptsEnumerate(JSContext *context, JSObject *object)
{
	/*	In order to support enumeration of world scripts (e.g.,
		for (name in worldScripts) { ... }), define each property on demand.
		Since world scripts cannot be deleted, we don't need to worry about
		that case (as in OOJSMissionVariables).
		
		Since WorldScriptsGetProperty() will be called for each access anyway,
		we define the value as null here.
	*/
	
	NSArray					*names = nil;
	NSEnumerator			*nameEnum = nil;
	NSString				*name = nil;
	
	names = [OOPlayerForScripting() worldScriptNames];
	
	for (nameEnum = [names objectEnumerator]; (name = [nameEnum nextObject]); )
	{
		if (!JS_DefineProperty(context, object, [name UTF8String], JSVAL_NULL, WorldScriptsGetProperty, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT))  return NO;
	}
	
	return YES;
}


static JSBool GetWorldScriptNames(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	NSArray					*names = nil;
	
	names = [OOPlayerForScripting() worldScriptNames];
	*outValue = [names javaScriptValueInContext:context];
	
	return YES;
}
