/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#import "OOJSMissionVariables.h"
#import "OOJavaScriptEngine.h"
#import "OOIsNumberLiteral.h"

#import "OOJSPlayer.h"


static NSString *KeyForName(JSContext *context, jsval name)
{
	NSCParameterAssert(JSVAL_IS_STRING(name));
	
	NSString *key = [NSString stringWithJavaScriptString:JSVAL_TO_STRING(name)];
	if ([key hasPrefix:@"_"])  return nil;
	return [@"mission_" stringByAppendingString:key];
}


static JSBool MissionVariablesDeleteProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionVariablesGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool MissionVariablesSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool MissionVariablesEnumerate(JSContext *cx, JSObject *obj, JSIterateOp enum_op, jsval *statep, jsid *idp);


static JSClass sMissionVariablesClass =
{
	"MissionVariables",
	JSCLASS_NEW_ENUMERATE,
	
	JS_PropertyStub,
	MissionVariablesDeleteProperty,
	MissionVariablesGetProperty,
	MissionVariablesSetProperty,
	(JSEnumerateOp)MissionVariablesEnumerate,
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
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))
	{
		NSString	*key = KeyForName(context, name);
		[player setMissionVariable:nil forKey:key];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))
	{
		NSString *key = KeyForName(context, name);
		if (key == nil)  return YES;
		
		id value = [player missionVariableForKey:key];
		
		*outValue = JSVAL_VOID;
		if ([value isKindOfClass:[NSString class]])	// Currently there should only be strings, but we may want to change this.
		{
			if (OOIsNumberLiteral(value, YES))
			{
				BOOL OK = JS_NewDoubleValue(context, [value doubleValue], outValue);
				if (!OK) *outValue = JSVAL_VOID;
			}
		}
		
		if (value != nil && JSVAL_IS_VOID(*outValue))
		{
			*outValue = [value javaScriptValueInContext:context];
		}
		
		if (JSVAL_IS_VOID(*outValue))
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
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSVAL_IS_STRING(name))
	{
		NSString *key = KeyForName(context, name);
		if (key == nil)
		{
			OOReportJSError(context, @"Mission variable names may not begin with an underscore.");
			return NO;
		}
		
		NSString *objValue = JSValToNSString(context, *value);
		
		if ([objValue isKindOfClass:[NSNull class]])  objValue = nil;
		[player setMissionVariable:objValue forKey:key];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesEnumerate(JSContext *context, JSObject *object, JSIterateOp enumOp, jsval *state, jsid *idp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSEnumerator *mvarEnumerator = JSVAL_TO_PRIVATE(*state);
	
	switch (enumOp)
	{
		case JSENUMERATE_INIT:
		{
			// -allKeys implicitly makes a copy, which is good since the enumerating code might mutate.
			NSArray *mvars = [[[PlayerEntity sharedPlayer] missionVariables] allKeys];
			mvarEnumerator = [[mvars objectEnumerator] retain];
			*state = PRIVATE_TO_JSVAL(mvarEnumerator);
			if (idp != NULL)
			{
				*idp = INT_TO_JSVAL([mvars count]);
			}
			return YES;
		}
		
		case JSENUMERATE_NEXT:
		{
			id next = [mvarEnumerator nextObject];
			if (next != nil)
			{
				NSCAssert1([next hasPrefix:@"mission_"] || next == nil, @"Mission variable key without \"mission_\" prefix: %@.", next);
				next = [next substringFromIndex:8];
				
				jsval val = [next javaScriptValueInContext:context];
				return JS_ValueToId(context, val, idp);
			}
			// else:
			*state = JSVAL_NULL;
			// Fall through.
		}
		
		case JSENUMERATE_DESTROY:
		{
			[mvarEnumerator release];
			if (idp != NULL)  return JS_ValueToId(context, JSVAL_VOID, idp);
			return YES;
		}
	}
	
	OOJS_NATIVE_EXIT
}
