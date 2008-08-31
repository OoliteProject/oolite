/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#import "OOJSMissionVariables.h"
#import "OOJavaScriptEngine.h"

#import "OOJSPlayer.h"


static NSString *KeyForName(JSContext *context, jsval name)
{
	return [@"mission_" stringByAppendingString:[NSString stringWithJavaScriptValue:name inContext:context]];
}


static JSBool MissionVariablesDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionVariablesGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionVariablesSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);


static JSClass sMissionVariablesClass =
{
	"MissionVariables",
	JSCLASS_IS_ANONYMOUS,
	
	JS_PropertyStub,
	MissionVariablesDeleteProperty,
	MissionVariablesGetProperty,
	MissionVariablesSetProperty,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};


void InitOOJSMissionVariables(JSContext *context, JSObject *global)
{
	JS_DefineObject(context, global, "missionVariables", &sMissionVariablesClass, NULL, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
}


static JSBool MissionVariablesDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = KeyForName(context, name);
		[player setMissionVariable:nil forKey:key];
	}
	return YES;
}


static JSBool MissionVariablesGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = KeyForName(context, name);
		id			value = [player missionVariableForKey:key];
		
		*outValue = JSVAL_VOID;
		if ([value isKindOfClass:[NSString class]])	// Currently there should only be strings, but we may want to change this.
		{
			/*	The point of this code is to try and tell the JS interpreter to treat numeric strings
				as numbers where possible so that standard arithmetic works as you'd expect rather than
				1+1 == "11". So a JSVAL_DOUBLE is returned if possible, otherwise a JSVAL_STRING is returned.
			*/
			
			BOOL	isNumber = NO;
			double	dVal;
			
			dVal = [value doubleValue];
			if (dVal != 0) isNumber = YES;
			else
			{
				NSCharacterSet *notZeroSet = [[NSCharacterSet characterSetWithCharactersInString:@"-0. "] invertedSet];
				if ([value rangeOfCharacterFromSet:notZeroSet].location == NSNotFound) isNumber = YES;
			}
			if (isNumber)
			{
				BOOL OK = JS_NewDoubleValue(context, [value doubleValue], outValue);
				if (!OK) *outValue = JSVAL_VOID;
			}
		}
		
		if (value != nil && *outValue == JSVAL_VOID)
		{
			*outValue = [value javaScriptValueInContext:context];
		}
		
		if (*outValue == JSVAL_VOID)
		{
			/*	"undefined" is the normal JS expectation, but "null" is easier
				to deal with. For instance, foo = missionVaraibles.undefinedThing
				is an error if JSVAL_VOID is used, but fine if JSVAL_NULL is
				used.
			*/
			*outValue = JSVAL_NULL;
		}
	}
	return YES;
}


static JSBool MissionVariablesSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = KeyForName(context, name);
		NSString	*objValue = [NSString stringWithJavaScriptValue:*value inContext:context];
		
		if ([objValue isKindOfClass:[NSNull class]])  objValue = nil;
		[player setMissionVariable:objValue forKey:key];
	}
	return YES;
}
