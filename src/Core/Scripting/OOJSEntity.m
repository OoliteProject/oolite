/*

OOJSEntity.m

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

#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJSQuaternion.h"
#import "OOJavaScriptEngine.h"
#import "OOConstToString.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OOJSCall.h"

#import "OOJSPlayer.h"
#import "PlayerEntity.h"


static JSObject		*sEntityPrototype;
static NSMutableSet	*sEntitySubClasses;


static JSBool EntityGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool EntitySetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);
static JSBool EntityConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue);
static void EntityFinalize(JSContext *context, JSObject *this);
static JSBool EntityEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual);

// Methods
static JSBool EntitySetPosition(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool EntitySetOrientation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool EntityValid(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool EntityCall(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


static JSExtendedClass sEntityClass =
{
	{
		"Entity",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		EntityGetProperty,		// getProperty
		EntitySetProperty,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		EntityConvert,			// convert
		EntityFinalize,			// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	EntityEquality,				// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kEntity_ID,					// universalID, int, read-only
	kEntity_position,			// position in system space, Vector, read-only
	kEntity_velocity,			// velocity, Vector, read-only
	kEntity_speed,				// speed, double, read-only (magnitude of velocity)
	kEntity_orientation,		// orientation, quaternion, read-write (unimplemented)
	kEntity_heading,			// heading, vector, read-only (like orientation but ignoring twist angle)
	kEntity_status,				// entity status, string, read-only
	kEntity_scanClass,			// scan class, string, read-only
	kEntity_mass,				// mass, double, read-only
	kEntity_owner,				// owner, Entity, read-only. (Parent ship for subentities, station for defense ships, launching ship for missiles etc)
	kEntity_energy,				// energy, double, read-write.
	kEntity_maxEnergy			// maxEnergy, double, read-only.
};


static JSPropertySpec sEntityProperties[] =
{
	// JS name					ID							flags
	{ "ID",						kEntity_ID,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "position",				kEntity_position,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "velocity",				kEntity_velocity,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "speed",					kEntity_speed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "orientation",			kEntity_orientation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "heading",				kEntity_heading,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "status",					kEntity_status,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scanClass",				kEntity_scanClass,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "mass",					kEntity_mass,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "owner",					kEntity_owner,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "energy",					kEntity_energy,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "maxEnergy",				kEntity_maxEnergy,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sEntityMethods[] =
{
	// JS name					Function					min args
	{ "setPosition",			EntitySetPosition,			1 },
	{ "setOrientation",			EntitySetOrientation,		1 },
	{ "valid",					EntityValid,				0 },
	{ "call",					EntityCall,					1 },
	{ 0 }
};


void InitOOJSEntity(JSContext *context, JSObject *global)
{
    sEntityPrototype = JS_InitClass(context, global, NULL, &sEntityClass.base, NULL, 0, sEntityProperties, sEntityMethods, NULL, NULL);
	JSEntityRegisterEntitySubclass(&sEntityClass.base);
}


JSObject *JSEntityWithEntity(JSContext *context, Entity *entity)
{
	JSClass					*class = NULL;
	JSObject				*prototype = NULL;
	JSObject				*result = NULL;
	
	if (entity == nil) return NULL;
	if (context == NULL) context = [[OOJavaScriptEngine sharedEngine] context];
	
	if (entity == [PlayerEntity sharedPlayer])  return JSPlayerObject();
	
	[entity getJSClass:&class andPrototype:&prototype];
	
	result = JS_NewObject(context, class, prototype, NULL);
	if (result != NULL)
	{
		if (!JS_SetPrivate(context, result, [entity weakRetain]))  result = NULL;
	}
	
	return result;
}


BOOL EntityToJSValue(JSContext *context, Entity *entity, jsval *outValue)
{
	JSObject				*object = NULL;
	
	if (outValue == NULL) return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	object = JSEntityWithEntity(context, entity);
	if (object == NULL) return NO;
	
	*outValue = OBJECT_TO_JSVAL(object);
	return YES;
}


BOOL JSValueToEntity(JSContext *context, jsval value, Entity **outEntity)
{
	Entity		*entity = nil;
	
	if (outEntity == NULL) return NO;
	
	if (JSVAL_IS_OBJECT(value))
	{
		return JSEntityGetEntity(context, JSVAL_TO_OBJECT(value), outEntity);
	}
	else if (JSVAL_IS_INT(value))	// Should we accept general numbers? (Currently, UniversalIDs are clamped to [100, 1000].)
	{
		entity = [UNIVERSE entityForUniversalID:JSVAL_TO_INT(value)];
		if (entity && [entity isVisibleToScripts])
		{
			*outEntity = [[entity retain] autorelease];
			return YES;
		}
	}
	
	return NO;
}


BOOL JSEntityGetEntity(JSContext *context, JSObject *entityObj, Entity **outEntity)
{
	OOWeakReference			*proxy = nil;
	
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	if (entityObj == NULL)  return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	// If it is an entity proxy...
	if ([sEntitySubClasses member:[NSValue valueWithPointer:JS_GetClass(entityObj)]] != nil)
	{
		proxy = JS_GetPrivate(context, entityObj);
		if (proxy != nil)
		{
			*outEntity = [proxy weakRefUnderlyingObject];
			return YES;
		}
	}
	
	return NO;
}


JSClass *JSEntityClass(void)
{
	return &sEntityClass.base;
}


JSObject *JSEntityPrototype(void)
{
	return sEntityPrototype;
}


void JSEntityRegisterEntitySubclass(JSClass *theClass)
{
	if (sEntitySubClasses == nil)  sEntitySubClasses = [[NSMutableSet alloc] init];
	[sEntitySubClasses addObject:[NSValue valueWithPointer:theClass]];
}


BOOL EntityFromArgumentList(JSContext *context, NSString *scriptClass, NSString *function, uintN argc, jsval *argv, Entity **outEntity, uintN *outConsumed)
{
	// Sanity checks.
	if (outConsumed != NULL)  *outConsumed = 0;
	if (EXPECT_NOT(argc == 0 || argv == NULL || outEntity == NULL))
	{
		OOLogGenericParameterError();
		return NO;
	}
	
	// Get value, if possible.
	if (EXPECT_NOT(!JSValueToEntity(context, argv[0], outEntity)))
	{
		// Failed; report bad parameters, if given a class and function.
		if (scriptClass != nil && function != nil)
		{
			OOReportJavaScriptWarning(context, @"%@.%@(): expected entity or universal ID, got %@.", scriptClass, function, [NSString stringWithJavaScriptParameters:argv count:1 inContext:context]);
			return NO;
		}
	}
	
	// Success.
	if (outConsumed != NULL)  *outConsumed = 1;
	return YES;
}


static JSBool EntityGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Entity						*entity = nil;
	id							result = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSEntityGetEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kEntity_ID:
			*outValue = INT_TO_JSVAL([entity universalID]);
			break;
		
		case kEntity_position:
			VectorToJSValue(context, [entity position], outValue);
			break;
		
		case kEntity_velocity:
			VectorToJSValue(context, [entity velocity], outValue);
			break;
		
		case kEntity_speed:
			JS_NewDoubleValue(context, magnitude([entity velocity]), outValue);
			break;
		
		case kEntity_orientation:
			QuaternionToJSValue(context, [entity orientation], outValue);
			break;
		
		case kEntity_heading:
			VectorToJSValue(context, vector_forward_from_quaternion(entity->orientation), outValue);
			break;
		
		case kEntity_status:
			result = EntityStatusToString([entity status]);
			break;
		
		case kEntity_scanClass:
			result = EntityStatusToString([entity scanClass]);
			break;
		
		case kEntity_mass:
			JS_NewDoubleValue(context, [entity mass], outValue);
			break;
		
		case kEntity_owner:
			result = [entity owner];
			if (result == entity)
			{
				result = nil;
				*outValue = JSVAL_NULL;
			}
			break;
		
		case kEntity_energy:
			JS_NewDoubleValue(context, [entity energy], outValue);
			break;
		
		case kEntity_maxEnergy:
			JS_NewDoubleValue(context, [entity maxEnergy], outValue);
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Entity", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil) *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool EntitySetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	Entity				*entity = nil;
	double				fValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSEntityGetEntity(context, this, &entity)) return NO;
	
	switch (name)
	{
		case kEntity_energy:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue == OOClamp_0_max_d(fValue, [entity maxEnergy]);
				[entity setEnergy:fValue];
			}
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Entity", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool EntityConvert(JSContext *context, JSObject *this, JSType type, jsval *outValue)
{
	Entity					*entity = nil;
	
	switch (type)
	{
		case JSTYPE_VOID:		// Used for string concatenation.
		case JSTYPE_STRING:
			// Return description of entity
			if (JSEntityGetEntity(context, this, &entity))
			{
				*outValue = [[entity description] javaScriptValueInContext:context];
			}
			else
			{
				*outValue = STRING_TO_JSVAL(JS_InternString(context, "[stale Entity]"));
			}
			return YES;
		
		default:
			// Contrary to what passes for documentation, JS_ConvertStub is not a no-op.
			return JS_ConvertStub(context, this, type, outValue);
	}
}


static void EntityFinalize(JSContext *context, JSObject *this)
{
	OOLog(@"js.entity.temp", @"%@ called for %p", this);
	[(id)JS_GetInstancePrivate(context, this, &sEntityClass.base, NULL) release];
}


static JSBool EntityEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	Entity					*thisEnt, *thatEnt;
	
	// No failures or diagnostic messages.
	JSEntityGetEntity(context, this, &thisEnt);
	JSEntityGetEntity(context, JSVAL_TO_OBJECT(value), &thatEnt);
	
	*outEqual = [thisEnt isEqual:thatEnt];	// Note ![nil isEqual:nil], so two stale entity refs will not be equal.
	return YES;
}


static JSBool EntitySetPosition(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity					*thisEnt;
	Vector					vector;
	
	if (!JSEntityGetEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	if (!VectorFromArgumentList(context, @"Entity", @"setPosition", argc, argv, &vector, NULL))  return YES;
	
	[thisEnt setPosition:vector];
	return YES;
}


static JSBool EntitySetOrientation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity					*thisEnt;
	Quaternion				quaternion;
	
	if (!JSEntityGetEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	if (!QuaternionFromArgumentList(context, @"Entity", @"setOrientation", argc, argv, &quaternion, NULL))  return YES;
	
	[thisEnt setOrientation:quaternion];
	return YES;
}


static JSBool EntityValid(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity					*thisEnt;
	
	*outResult = BOOLToJSVal(JSEntityGetEntity(context, this, &thisEnt));
	return YES;
}


static JSBool EntityCall(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity					*entity = nil;
	
	if (!JSEntityGetEntity(context, this, &entity))  return YES;
	if (entity == nil)  return YES;	// Stale entity
	
	return OOJSCallObjCObjectMethod(context, entity, [entity jsClassName], argc, argv, outResult);
}
