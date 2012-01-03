/*

OOJSWorldScripts.m


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

#import "OOJSWorldScripts.h"
#import "OOJavaScriptEngine.h"
#import "PlayerEntity.h"
#import "OOJSPlayer.h"


static JSBool WorldScriptsGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool WorldScriptsEnumerate(JSContext *cx, JSObject *obj);


static JSClass sWorldScriptsClass =
{
	"WorldScripts",
	0,
	
	JS_PropertyStub,
	JS_PropertyStub,
	WorldScriptsGetProperty,
	JS_StrictPropertyStub,
	WorldScriptsEnumerate,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


void InitOOJSWorldScripts(JSContext *context, JSObject *global)
{
	JS_DefineObject(context, global, "worldScripts", &sWorldScriptsClass, NULL, OOJS_PROP_READONLY);
}


static JSBool WorldScriptsGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	NSString					*scriptName = nil;
	id							script = nil;
	
	if (!JSID_IS_STRING(propID))  return YES;
	scriptName = OOStringFromJSString(context, JSID_TO_STRING(propID));
	
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
			*value = [script oo_jsValueInContext:context];
		}
		else
		{
			*value = JSVAL_VOID;
		}

	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool WorldScriptsEnumerate(JSContext *context, JSObject *object)
{
	OOJS_NATIVE_ENTER(context)
	
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
		if (!JS_DefineProperty(context, object, [name UTF8String], JSVAL_NULL, WorldScriptsGetProperty, NULL, OOJS_PROP_READONLY_CB))  return NO;
	}
	
	return YES;
	
	OOJS_NATIVE_EXIT
}
