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


static JSBool EntityGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool EntitySetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

// Methods
static JSBool EntitySetPosition(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool EntitySetOrientation(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool EntityValid(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool EntityCall(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

// Static methods
static JSBool EntityStaticEntityWithID(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


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
		JS_ConvertStub,			// convert
		JSObjectWrapperFinalize,// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	JSEntityEquality,			// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kEntity_ID,					// universalID, int, read-only
	kEntity_position,			// position in system space, Vector, read-only
	kEntity_orientation,		// orientation, quaternion, read-write
	kEntity_heading,			// heading, vector, read-only (like orientation but ignoring twist angle)
	kEntity_status,				// entity status, string, read-only
	kEntity_scanClass,			// scan class, string, read-only
	kEntity_mass,				// mass, double, read-only
	kEntity_owner,				// owner, Entity, read-only. (Parent ship for subentities, station for defense ships, launching ship for missiles etc)
	kEntity_energy,				// energy, double, read-write.
	kEntity_maxEnergy,			// maxEnergy, double, read-only.
	kEntity_isValid,			// is not stale, boolean, read-only.
	kEntity_isShip,				// is ship, boolean, read-only.
	kEntity_isStation,			// is station, boolean, read-only.
	kEntity_isSubEntity,		// is subentity, boolean, read-only.
	kEntity_isPlayer,			// is player, boolean, read-only.
	kEntity_isPlanet,			// is planet, boolean, read-only.
	kEntity_distanceTravelled,	// distance travelled, double, read-only.
	kEntity_spawnTime,			// spawn time, double, read-only.
};


static JSPropertySpec sEntityProperties[] =
{
	// JS name					ID							flags
	{ "ID",						kEntity_ID,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "position",				kEntity_position,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "orientation",			kEntity_orientation,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "heading",				kEntity_heading,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "status",					kEntity_status,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scanClass",				kEntity_scanClass,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "mass",					kEntity_mass,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "owner",					kEntity_owner,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "energy",					kEntity_energy,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "maxEnergy",				kEntity_maxEnergy,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isValid",				kEntity_isValid,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isShip",					kEntity_isShip,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isStation",				kEntity_isStation,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isSubEntity",			kEntity_isSubEntity,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlayer",				kEntity_isPlayer,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlanet",				kEntity_isPlanet,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "distanceTravelled",		kEntity_distanceTravelled,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "spawnTime",				kEntity_spawnTime,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sEntityMethods[] =
{
	// JS name					Function					min args
	{ "toString",				JSObjectWrapperToString,	0 },
	{ "setPosition",			EntitySetPosition,			1 },
	{ "setOrientation",			EntitySetOrientation,		1 },
	{ "valid",					EntityValid,				0 },
	{ "call",					EntityCall,					1 },
	{ 0 }
};


static JSFunctionSpec sEntityStaticMethods[] =
{
	// JS name					Function					min args
	{ "entityWithID",			EntityStaticEntityWithID,	1 },
	{ 0 }
};


void InitOOJSEntity(JSContext *context, JSObject *global)
{
    sEntityPrototype = JS_InitClass(context, global, NULL, &sEntityClass.base, NULL, 0, sEntityProperties, sEntityMethods, NULL, sEntityStaticMethods);
	JSRegisterObjectConverter(&sEntityClass.base, JSBasicPrivateObjectConverter);
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
	if (outEntity == NULL)  return NO;
	*outEntity = nil;
	if (entityObj == NULL)  return NO;
	if (EXPECT_NOT(context == NULL))  context = [[OOJavaScriptEngine sharedEngine] context];
	
	*outEntity = JSObjectToObject(context, entityObj);
	if ([*outEntity isKindOfClass:[Entity class]])  return YES;
	
	*outEntity = nil;
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


JSBool JSEntityEquality(JSContext *context, JSObject *this, jsval value, JSBool *outEqual)
{
	Entity					*thisEnt, *thatEnt;
	
	// No failures or diagnostic messages.
	JSEntityGetEntity(context, this, &thisEnt);
	JSValueToEntity(context, value, &thatEnt);
	
	*outEqual = [thisEnt isEqual:thatEnt];	// Note ![nil isEqual:nil], so two stale entity refs will not be equal.
	return YES;
}


static JSBool EntityGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	Entity						*entity = nil;
	id							result = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSEntityGetEntity(context, this, &entity)) return NO;	// NOTE: entity may be nil.
	
	switch (JSVAL_TO_INT(name))
	{
		case kEntity_ID:
			*outValue = INT_TO_JSVAL([entity universalID]);
			break;
		
		case kEntity_position:
			VectorToJSValue(context, [entity position], outValue);
			break;
		
		case kEntity_orientation:
			QuaternionToJSValue(context, [entity orientation], outValue);
			break;
		
		case kEntity_heading:
			if (entity != nil)
			{
				VectorToJSValue(context, vector_forward_from_quaternion(entity->orientation), outValue);
			}
			break;
		
		case kEntity_status:
			result = EntityStatusToString([entity status]);
			break;
		
		case kEntity_scanClass:
			result = ScanClassToString([entity scanClass]);
			break;
		
		case kEntity_mass:
			JS_NewDoubleValue(context, [entity mass], outValue);
			break;
		
		case kEntity_owner:
			result = [entity owner];
			if (result == entity)  result = nil;
			if (result == nil)  *outValue = JSVAL_NULL;
			break;
		
		case kEntity_energy:
			JS_NewDoubleValue(context, [entity energy], outValue);
			break;
		
		case kEntity_maxEnergy:
			JS_NewDoubleValue(context, [entity maxEnergy], outValue);
			break;
		
		case kEntity_isValid:
			*outValue = BOOLToJSVal(entity != nil);
			break;
		
		case kEntity_isShip:
			*outValue = BOOLToJSVal([entity isShip]);
			break;
		
		case kEntity_isStation:
			*outValue = BOOLToJSVal([entity isStation]);
			break;
			
		case kEntity_isSubEntity:
			*outValue = BOOLToJSVal([entity isSubEntity]);
			break;
		
		case kEntity_isPlayer:
			*outValue = BOOLToJSVal([entity isPlayer]);
			break;
		
		case kEntity_isPlanet:
			*outValue = BOOLToJSVal([entity isPlanet]);
			break;
		
		case kEntity_distanceTravelled:
			JS_NewDoubleValue(context, [entity distanceTravelled], outValue);
			break;
		
		case kEntity_spawnTime:
			JS_NewDoubleValue(context, [entity spawnTime], outValue);
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
	
	switch (JSVAL_TO_INT(name))
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


// *** Methods ***

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
	
	OOReportJavaScriptWarning(context, @"Player.%@ is deprecated, use Player.%@ instead.", @"valid()", @"isValid property");
	*outResult = BOOLToJSVal(JSEntityGetEntity(context, this, &thisEnt) && thisEnt != nil);
	return YES;
}


static JSBool EntityCall(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity					*entity = nil;
	
	if (!JSEntityGetEntity(context, this, &entity))  return YES;
	if (entity == nil)  return YES;	// Stale entity
	
	return OOJSCallObjCObjectMethod(context, entity, [entity jsClassName], argc, argv, outResult);
}


static JSBool EntityStaticEntityWithID(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	Entity					*result = nil;
	int32					ID;
	
	if (JS_ValueToInt32(context, *argv, &ID))
	{
		result = [UNIVERSE entityForUniversalID:ID];
	}
	
	if (result != nil)  *outResult = [result javaScriptValueInContext:context];
	return YES;
}
