/*

OOJSMissionVariables.h

JavaScript mission variables object.


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

#import "OOJSMissionVariables.h"
#import "OOJavaScriptEngine.h"
#import "OOIsNumberLiteral.h"

#import "OOJSPlayer.h"


static NSString *KeyForPropertyID(JSContext *context, jsid propID)
{
	NSCParameterAssert(JSID_IS_STRING(propID));
	
	NSString *key = OOStringFromJSString(context, JSID_TO_STRING(propID));
	if ([key hasPrefix:@"_"])  return nil;
	return [@"mission_" stringByAppendingString:key];
}


static JSBool MissionVariablesDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool MissionVariablesGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool MissionVariablesSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);
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
	JS_DefineObject(context, global, "missionVariables", &sMissionVariablesClass, NULL, OOJS_PROP_READONLY);
	
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


static JSBool MissionVariablesDeleteProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSID_IS_STRING(propID))
	{
		NSString *key = KeyForPropertyID(context, propID);
		[player setMissionVariable:nil forKey:key];
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSID_IS_STRING(propID))
	{
		NSString *key = KeyForPropertyID(context, propID);
		if (key == nil)  return YES;
		
		id mvar = [player missionVariableForKey:key];
		
		if ([mvar isKindOfClass:[NSString class]])	// Currently there should only be strings, but we may want to change this.
		{
			if (OOIsNumberLiteral(mvar, YES))
			{
				return JS_NewNumberValue(context, [mvar doubleValue], value);
			}
		}
		
		*value = OOJSValueFromNativeObject(context, mvar);
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool MissionVariablesSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	OOJS_NATIVE_ENTER(context)
	
	PlayerEntity				*player = OOPlayerForScripting();
	
	if (JSID_IS_STRING(propID))
	{
		NSString *key = KeyForPropertyID(context, propID);
		if (key == nil)
		{
			OOJSReportError(context, @"Invalid mission variable name \"%@\".", [OOStringFromJSID(propID) escapedForJavaScriptLiteral]);
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
		case JSENUMERATE_INIT_ALL:	// For ES5 Object.getOwnPropertyNames(). Since we have no non-enumerable properties, this is the same as _INIT.
		{
			// -allKeys implicitly makes a copy, which is good since the enumerating code might mutate.
			NSArray *mvars = [[PLAYER missionVariables] allKeys];
			enumerator = [[mvars objectEnumerator] retain];
			*state = PRIVATE_TO_JSVAL(enumerator);
			
			OOUInteger count = [mvars count];
			assert(count <= INT32_MAX);
			if (idp != NULL)  *idp = INT_TO_JSID((uint32_t)count);
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
			
			if (idp != NULL)  *idp = JSID_VOID;
			return YES;
		}
	}
	
	OOJS_NATIVE_EXIT
}
