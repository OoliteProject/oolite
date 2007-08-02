/*

OOJSShip.m

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

#import "OOJSShip.h"
#import "OOJSEntity.h"
#import "OOJavaScriptEngine.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "AI.h"
#import "OOStringParsing.h"


static JSObject *sShipPrototype;


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool ShipSetAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSwitchAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

static NSArray *ArrayOfRoles(NSString *rolesString);


static JSExtendedClass sShipClass =
{
	{
		"Ship",
		JSCLASS_HAS_PRIVATE | JSCLASS_IS_EXTENDED,
		
		JS_PropertyStub,		// addProperty
		JS_PropertyStub,		// delProperty
		ShipGetProperty,		// getProperty
		ShipSetProperty,		// setProperty
		JS_EnumerateStub,		// enumerate
		JS_ResolveStub,			// resolve
		JS_ConvertStub,			// convert
		JS_FinalizeStub,		// finalize
		JSCLASS_NO_OPTIONAL_MEMBERS
	},
	NULL,						// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kShip_shipDescription,		// name, string, read-only
	kShip_roles,				// roles, array, read-only
	kShip_AI,					// AI state machine name, string, read/write
	kShip_AIState,				// AI state machine state, string, read/write
	kShip_fuel,					// fuel, float, read/write
	kShip_bounty				// bounty, unsigned int, read/write
};


static JSPropertySpec sShipProperties[] =
{
	// JS name					ID							flags
	{ "shipDescription",		kShip_shipDescription,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "roles",					kShip_roles,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "AI",						kShip_AI,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "AIState",				kShip_AIState,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "fuel",					kShip_fuel,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "bounty",					kShip_bounty,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "setAI",					ShipSetAI,					1 },
	{ "switchAI",				ShipSwitchAI,				1 },
	{ 0 }
};


void InitOOJSShip(JSContext *context, JSObject *global)
{
    sShipPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sShipClass.base, NULL, 0, sShipProperties, sShipMethods, NULL, NULL);
	JSEntityRegisterEntitySubclass(&sShipClass.base);
}


BOOL JSShipGetShipEntity(JSContext *context, JSObject *shipObj, ShipEntity **outEntity)
{
	BOOL						result;
	Entity						*entity = nil;
	
	if (outEntity != NULL)  *outEntity = nil;
	
	result = JSEntityGetEntity(context, shipObj, &entity);
	if (!result)  return NO;
	
	if (![entity isKindOfClass:[ShipEntity class]])  return NO;
	
	*outEntity = (ShipEntity *)entity;
	return YES;
}


JSClass *JSShipClass(void)
{
	return &sShipClass.base;
}


JSObject *JSShipPrototype(void)
{
	return sShipPrototype;
}


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue)
{
	ShipEntity					*entity = nil;
	id							result = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSShipGetShipEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kShip_shipDescription:
			result = [entity name];
			break;
		
		case kShip_roles:
			result = ArrayOfRoles([entity roles]);
			break;
			
		case kShip_AI:
			result = [[entity getAI] name];
			break;
			
		case kShip_AIState:
			result = [[entity getAI] state];
			break;
			
		case kShip_fuel:
			JS_NewDoubleValue(context, [entity fuel] * 0.1, outValue);
			break;
		
		case kShip_bounty:
			*outValue = INT_TO_JSVAL([entity legalStatus]);
			break;
			
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Ship", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	return YES;
}


static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	ShipEntity					*entity = nil;
	NSString					*strVal = nil;
	jsdouble					fValue;
	int32						iValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSShipGetShipEntity(context, this, &entity)) return NO;
	
	switch (name)
	{
		case kShip_AIState:
			if (entity->isPlayer)
			{
				OOReportJavaScriptError(context, @"Ship.AIState [setter]: cannot set AI state for player.");
			}
			else
			{
				strVal = [NSString stringWithJavaScriptValue:*value inContext:context];
				if (strVal != nil)  [[entity getAI] setState:strVal];
			}
			break;
		
		case kShip_fuel:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, 7.0);
				[entity setFuel:lround(fValue * 10.0)];
			}
			break;
		
		case kShip_bounty:
			if (JS_ValueToInt32(context, *value, &iValue) && 0 < iValue)
			{
				[entity setBounty:iValue];
			}
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Ship", JSVAL_TO_INT(name));
			return NO;
	}
	
	return YES;
}


static JSBool ShipSetAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = [NSString stringWithJavaScriptValue:*argv inContext:context];
	
	if (name != nil)
	{
		if (!thisEnt->isPlayer)
		{
			[thisEnt setAITo:name];
		}
		else
		{
			OOReportJavaScriptError(context, @"Ship.%@(\"%@\"): cannot set AI for player.", @"setAI", name);
		}
	}
	else
	{
		OOReportJavaScriptError(context, @"Ship.%@(): no AI state machine specified.", @"setAI");
	}
	return YES;
}


static JSBool ShipSwitchAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = [NSString stringWithJavaScriptValue:*argv inContext:context];
	
	if (name != nil)
	{
		if (!thisEnt->isPlayer)
		{
			[thisEnt switchAITo:name];
		}
		else
		{
			OOReportJavaScriptWarning(context, @"Ship.%@(\"%@\"): cannot set AI for player.", @"switchAI", name);
		}
	}
	else
	{
		OOReportJavaScriptWarning(context, @"Ship.%@(): no AI state machine specified.", @"switchAI");
	}
	return YES;
}


static NSArray *ArrayOfRoles(NSString *rolesString)
{
	NSArray					*rawRoles = nil;
	NSMutableArray			*filteredRoles = nil;
	NSAutoreleasePool		*pool = nil;
	unsigned				i, count;
	NSString				*role = nil;
	NSRange					parenRange;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	rawRoles = ScanTokensFromString(rolesString);
	count = [rawRoles count];
	filteredRoles = [NSMutableArray arrayWithCapacity:count];
	
	for (i = 0; i != count; ++i)
	{
		role = [rawRoles objectAtIndex:i];
		// Strip probability from string
		parenRange = [role rangeOfString:@"("];
		if (parenRange.location != NSNotFound)
		{
			role = [role substringToIndex:parenRange.location];
		}
		[filteredRoles addObject:role];
	}
	
	[filteredRoles retain];
	[pool release];
	return filteredRoles;
}
