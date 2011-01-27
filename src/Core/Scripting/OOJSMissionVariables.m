/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#import "OOJSMissionVariables.h"
#import "OOJavaScriptEngine.h"
#import "OOIsNumberLiteral.h"

#import "OOJSPlayer.h"


#if OO_NEW_JS
typedef jsid PropertyID;
#define PROP_IS_STRING JSID_IS_STRING
#define PROP_TO_STRING JSID_TO_STRING
#else
typedef jsval PropertyID;
#define PROP_IS_STRING JSVAL_IS_STRING
#define PROP_TO_STRING JSVAL_TO_STRING
#endif

static NSString *KeyForPropertyID(JSContext *context, PropertyID propID)
{
	NSCParameterAssert(PROP_IS_STRING(propID));
	
	NSString *key = OOStringFromJSString(context, PROP_TO_STRING(propID));
	if ([key hasPrefix:@"_"])  return nil;
	return [@"mission_" stringByAppendingString:key];
}


static JSBool MissionVariablesDeleteProperty(OOJS_PROP_ARGS);
static JSBool MissionVariablesGetProperty(OOJS_PROP_ARGS);
static JSBool MissionVariablesSetProperty(OOJS_PROP_ARGS);
static JSBool MissionVariablesEnumerate(JSContext *context, JSObject *object, JSIterateOp enumOp, jsval *state, jsid *idp);

#ifndef NDEBUG
static id MissionVariablesConverter(JSContext *context, JSObject *object);
#endif


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
	
#ifndef NDEBUG
	// Allow callObjC() on missionVariables to call methods on the mission variables dictionary.
	OOJSRegisterObjectConverter(&sMissionVariablesClass, MissionVariablesConverter);
#endif
}


#ifndef NDEBUG
static id MissionVariablesConverter(JSContext *context, JSObject *object)
{
	return [PLAYER missionVariables];
}
#endif


static JSBool MissionVariablesDeleteProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (OOJS_PROPID_IS_STRING)
	{
		NSString *key = KeyForPropertyID(context, propID);
		[player setMissionVariable:nil forKey:key];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesGetProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (OOJS_PROPID_IS_STRING)
	{
		NSString *key = KeyForPropertyID(context, propID);
		if (key == nil)  return YES;
		
		id mvar = [player missionVariableForKey:key];
		
		*value = JSVAL_VOID;
		if ([mvar isKindOfClass:[NSString class]])	// Currently there should only be strings, but we may want to change this.
		{
			if (OOIsNumberLiteral(mvar, YES))
			{
				BOOL OK = JS_NewDoubleValue(context, [mvar doubleValue], value);
				if (!OK) *value = JSVAL_VOID;
			}
		}
		
		if (mvar != nil && JSVAL_IS_VOID(*value))
		{
			*value = [mvar oo_jsValueInContext:context];
		}
		
		if (JSVAL_IS_VOID(*value))
		{
			/*	"undefined" is the normal JS expectation, but "null" is easier
				to deal with. For instance, foo = missionVaraibles.undefinedThing
				is an error if JSVAL_VOID is used, but fine if JSVAL_NULL is
				used.
			*/
			*value = JSVAL_NULL;
		}
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesSetProperty(OOJS_PROP_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (OOJS_PROPID_IS_STRING)
	{
		NSString *key = KeyForPropertyID(context, propID);
		if (key == nil)
		{
			OOJSReportError(context, @"Mission variable names may not begin with an underscore.");
			return NO;
		}
		
		NSString *objValue = OOStringFromJSValue(context, *value);
		
		if ([objValue isKindOfClass:[NSNull class]])  objValue = nil;
		[player setMissionVariable:objValue forKey:key];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesEnumerate(JSContext *context, JSObject *object, JSIterateOp enumOp, jsval *state, jsid *idp)
{
	OOJS_NATIVE_ENTER(context)
	
	NSEnumerator *enumerator = nil;
	
	switch (enumOp)
	{
		case JSENUMERATE_INIT:
#if OO_NEW_JS
		case JSENUMERATE_INIT_ALL:	// For ES5 Object.getOwnPropertyNames(). Since we have no non-enumerable properties, this is the same as _INIT.
#endif
		{
			// -allKeys implicitly makes a copy, which is good since the enumerating code might mutate.
			NSArray *mvars = [[PLAYER missionVariables] allKeys];
			enumerator = [[mvars objectEnumerator] retain];
			*state = PRIVATE_TO_JSVAL(enumerator);
			if (idp != NULL)
			{
#if OO_NEW_JS
				*idp = INT_TO_JSID([mvars count]);
#else
				*idp = INT_TO_JSVAL([mvars count]);
#endif
			}
			return YES;
		}
		
		case JSENUMERATE_NEXT:
		{
			enumerator = JSVAL_TO_PRIVATE(*state);
			for (;;)
			{
				NSString *next = [enumerator nextObject];
				if (next == nil)  break;
				if (![next hasPrefix:@"mission_"])  continue;	// Skip mission instructions, which aren't visible through missionVariables.
				
				next = [next substringFromIndex:8];		// Cut off "mission_".
				
				jsval val = [next oo_jsValueInContext:context];
				return JS_ValueToId(context, val, idp);
			}
			
			// If we got here, we've hit the end of the enumerator.
			*state = JSVAL_NULL;
			// Fall through.
		}
		
		case JSENUMERATE_DESTROY:
		{
			if (enumerator == nil && JSVAL_IS_DOUBLE(*state))
			{
				enumerator = JSVAL_TO_PRIVATE(*state);
			}
			[enumerator release];
			if (idp != NULL)
			{
#if OO_NEW_JS
				*idp = JSID_VOID;
#else
				return JS_ValueToId(context, JSVAL_VOID, idp);
#endif
			}
			return YES;
		}
	}
	
	OOJS_NATIVE_EXIT
}
