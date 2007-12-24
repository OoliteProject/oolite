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
#import "EntityOOJavaScriptExtensions.h"
#import "OORoleSet.h"
#import "OOJSPlayer.h"


static JSObject *sShipPrototype;


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool ShipSetAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSwitchAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipExitAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipReactToAIMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipDeployEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipDockEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipHasRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipRunLegacyScriptActions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);


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
	kShip_shipDescription,		// name, string, read-only
	kShip_roles,				// roles, array, read-only
	kShip_roleProbabilities,	// roles and probabilities, dictionary, read-only
	kShip_primaryRole,			// Primary role, string, read-only
	kShip_AI,					// AI state machine name, string, read/write
	kShip_AIState,				// AI state machine state, string, read/write
	kShip_fuel,					// fuel, float, read/write
	kShip_bounty,				// bounty, unsigned int, read/write
	kShip_subEntities,			// subentities, array of Ship, read-only
	kShip_hasSuspendedAI,		// AI has suspended staes, boolean, read-only
	kShip_target,				// target, Ship, read/write
	kShip_escorts,				// deployed escorts, array of Ship, read-only
	kShip_temperature,			// hull temperature, double, read/write
	kShip_heatInsulation,		// hull heat insulation, double, read/write
	kShip_entityPersonality,	// per-ship random number, int, read-only
	kShip_isBeacon,				// is beacon, boolean, read-only
	kShip_beaconCode,			// beacon code, string, read-only (should probably be read/write, but the beacon list needs to be maintained.)
	kShip_isFrangible,			// frangible, boolean, read-only
	kShip_isCloaked,			// cloaked, boolean, read/write (if cloaking device installed)
	kShip_isJamming,			// jamming scanners, boolean, read/write (if jammer installed)
	kShip_groupID,				// group ID, integer, read-only
	kShip_potentialCollider,	// "proximity alert" ship, Entity, read-only
	kShip_hasHostileTarget,		// has hostile target, boolean, read-only
	kShip_weaponRange,			// weapon range, double, read-only
	kShip_scannerRange,			// scanner range, double, read-only
	kShip_reportAIMessages,		// report AI messages, boolean, read/write
	kShip_withinStationAegis,	// within main station aegis, boolean, read/write
	kShip_maxCargo,				// maximum cargo, integer, read-only
	kShip_speed,				// current flight speed, double, read-only (should probably be read/write, but may interfere with AI behaviour)
	kShip_maxSpeed,				// maximum flight speed, double, read-only
	kShip_script,				// script, Script, read-only
	kShip_isPirate,				// is pirate, boolean, read-only
	kShip_isPlayer,				// is player, boolean, read-only
	kShip_isPolice,				// is police, boolean, read-only
	kShip_isThargoid,			// is thargoid, boolean, read-only
	kShip_isTrader,				// is trader, boolean, read-only
	kShip_isPirateVictim,		// is pirate victim, boolean, read-only
	kShip_scriptInfo			// arbitrary data for scripts, dictionary, read-only
};


static JSPropertySpec sShipProperties[] =
{
	// JS name					ID							flags
	{ "AI",						kShip_AI,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "AIState",				kShip_AIState,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "beaconCode",				kShip_beaconCode,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "bounty",					kShip_bounty,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "entityPersonality",		kShip_entityPersonality,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "escorts",				kShip_escorts,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "fuel",					kShip_fuel,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "groupID",				kShip_groupID,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasHostileTarget",		kShip_hasHostileTarget,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasSuspendedAI",			kShip_hasSuspendedAI,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "heatInsulation",			kShip_heatInsulation,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isBeacon",				kShip_isBeacon,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isCloaked",				kShip_isCloaked,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isFrangible",			kShip_isFrangible,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isJamming",				kShip_isJamming,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPirate",				kShip_isPirate,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPirateVictim",			kShip_isPirateVictim,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlayer",				kShip_isPlayer,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPolice",				kShip_isPolice,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isThargoid",				kShip_isThargoid,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isTrader",				kShip_isTrader,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxCargo",				kShip_maxCargo,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxSpeed",				kShip_maxSpeed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "potentialCollider",		kShip_potentialCollider,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "primaryRole",			kShip_primaryRole,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "reportAIMessages",		kShip_reportAIMessages,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "roleProbabilities",		kShip_roleProbabilities,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "roles",					kShip_roles,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scannerRange",			kShip_scannerRange,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "script",					kShip_script,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scriptInfo",				kShip_scriptInfo,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "shipDescription",		kShip_shipDescription,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "speed",					kShip_speed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "subEntities",			kShip_subEntities,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "target",					kShip_target,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "temperature",			kShip_temperature,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "weaponRange",			kShip_weaponRange,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "withinStationAegis",		kShip_withinStationAegis,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ 0 }
};


static JSFunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "setAI",					ShipSetAI,					1 },
	{ "switchAI",				ShipSwitchAI,				1 },
	{ "exitAI",					ShipExitAI,					0 },
	{ "reactToAIMessage",		ShipReactToAIMessage,		1 },
	{ "deployEscorts",			ShipDeployEscorts,			0 },
	{ "dockEscorts",			ShipDockEscorts,			0 },
	{ "hasRole",				ShipHasRole,				1 },
	{ "runLegacyScriptActions",	ShipRunLegacyScriptActions,	2 },
	{ 0 }
};


void InitOOJSShip(JSContext *context, JSObject *global)
{
    sShipPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sShipClass.base, NULL, 0, sShipProperties, sShipMethods, NULL, NULL);
	JSRegisterObjectConverter(&sShipClass.base, JSBasicPrivateObjectConverter);
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
	if (!JSShipGetShipEntity(context, this, &entity)) return NO;	// NOTE: entity may be nil.
	if (!JS_EnterLocalRootScope(context))  return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kShip_shipDescription:
			result = [entity name];
			break;
		
		case kShip_roles:
			result = [[entity roleSet] sortedRoles];
			break;
		
		case kShip_roleProbabilities:
			result = [[entity roleSet] rolesAndProbabilities];
			break;
		
		case kShip_primaryRole:
			result = [entity primaryRole];
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
		
		case kShip_subEntities:
			result = [entity subEntitiesForScript];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_hasSuspendedAI:
			*outValue = BOOLToJSVal([[entity getAI] hasSuspendedStateMachines]);
			break;
			
		case kShip_target:
			result = [entity primaryTarget];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_escorts:
			result = [entity escorts];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_temperature:
			JS_NewDoubleValue(context, [entity temperature] / SHIP_MAX_CABIN_TEMP, outValue);
			break;
			
		case kShip_heatInsulation:
			JS_NewDoubleValue(context, [entity heatInsulation], outValue);
			break;
			
		case kShip_entityPersonality:
			*outValue = INT_TO_JSVAL([entity entityPersonalityInt]);
			break;
			
		case kShip_isBeacon:
			*outValue = BOOLToJSVal([entity isBeacon]);
			break;
			
		case kShip_beaconCode:
			result = [entity beaconCode];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_isFrangible:
			*outValue = BOOLToJSVal([entity isFrangible]);
			break;
		
		case kShip_isCloaked:
			*outValue = BOOLToJSVal([entity isCloaked]);
			break;
			
		case kShip_isJamming:
			*outValue = BOOLToJSVal([entity isJammingScanning]);
			break;
			
		case kShip_groupID:
			*outValue = INT_TO_JSVAL([entity groupID]);
			break;
		
		case kShip_potentialCollider:
			result = [entity proximity_alert];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_hasHostileTarget:
			*outValue = BOOLToJSVal([entity hasHostileTarget]);
			break;
			
		case kShip_weaponRange:
			JS_NewDoubleValue(context, [entity weaponRange], outValue);
			break;
			
		case kShip_scannerRange:
			JS_NewDoubleValue(context, [entity weaponRange], outValue);
			break;
		
		case kShip_reportAIMessages:
			*outValue = BOOLToJSVal([entity reportAIMessages]);
			break;
		
		case kShip_withinStationAegis:
			*outValue = BOOLToJSVal([entity withinStationAegis]);
			break;
		
		case kShip_maxCargo:
			*outValue = INT_TO_JSVAL([entity maxCargo]);
			break;
			
		case kShip_speed:
			JS_NewDoubleValue(context, [entity flightSpeed], outValue);
			break;
			
		case kShip_maxSpeed:
			JS_NewDoubleValue(context, [entity maxFlightSpeed], outValue);
			break;
			
		case kShip_script:
			result = [entity shipScript];
			if (result == nil)  result = [NSNull null];
				break;
			
		case kShip_isPirate:
			*outValue = BOOLToJSVal([entity isPirate]);
			break;
			
		case kShip_isPolice:
			*outValue = BOOLToJSVal([entity isPolice]);
			break;
			
		case kShip_isThargoid:
			*outValue = BOOLToJSVal([entity isThargoid]);
			break;
			
		case kShip_isTrader:
			*outValue = BOOLToJSVal([entity isTrader]);
			break;
			
		case kShip_isPirateVictim:
			*outValue = BOOLToJSVal([entity isPirateVictim]);
			break;
			
		case kShip_scriptInfo:
			result = [entity scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than NULL
			break;
		
		default:
			OOReportJavaScriptBadPropertySelector(context, @"Ship", JSVAL_TO_INT(name));
			return NO;
	}
	
	if (result != nil)  *outValue = [result javaScriptValueInContext:context];
	JS_LeaveLocalRootScope(context);
	return YES;
}


static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	ShipEntity					*entity = nil;
	ShipEntity					*target = nil;
	NSString					*sValue = nil;
	jsdouble					fValue;
	int32						iValue;
	JSBool						bValue;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (!JSShipGetShipEntity(context, this, &entity)) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kShip_shipDescription:
			if (entity->isPlayer)
			{
				OOReportJavaScriptError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"name", @"name");
			}
			else
			{
				sValue = [NSString stringWithJavaScriptValue:*value inContext:context];
				if (sValue != nil)  [entity setName:sValue];
			}
			break;
		
		case kShip_primaryRole:
			if (entity->isPlayer)
			{
				OOReportJavaScriptError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"primaryRole", @"primary role");
			}
			else
			{
				sValue = [NSString stringWithJavaScriptValue:*value inContext:context];
				if (sValue != nil)  [entity setPrimaryRole:sValue];
			}
			break;
		
		case kShip_AIState:
			if (entity->isPlayer)
			{
				OOReportJavaScriptError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"AIState", @"AI state");
			}
			else
			{
				sValue = [NSString stringWithJavaScriptValue:*value inContext:context];
				if (sValue != nil)  [[entity getAI] setState:sValue];
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
		
		case kShip_target:
			if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
			{
				[entity setTargetForScript:target];
			}
			break;
		
		case kShip_temperature:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOMax_d(fValue, 0.0);
				[entity setTemperature:fValue * SHIP_MAX_CABIN_TEMP];
			}
			break;
		
		case kShip_heatInsulation:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOMax_d(fValue, 0.125);
				[entity setHeatInsulation:fValue * SHIP_MAX_CABIN_TEMP];
			}
			break;
		
		case kShip_isCloaked:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setCloaked:bValue];
			}
			break;
		
		case kShip_reportAIMessages:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setReportAIMessages:bValue];
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
			OOReportJavaScriptError(context, @"Ship.%@(\"%@\"): cannot modify AI for player.", @"setAI", name);
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
			OOReportJavaScriptWarning(context, @"Ship.%@(\"%@\"): cannot modify AI for player.", @"switchAI", name);
		}
	}
	else
	{
		OOReportJavaScriptWarning(context, @"Ship.%@(): no AI state machine specified.", @"switchAI");
	}
	return YES;
}


static JSBool ShipExitAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	AI						*thisAI = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	thisAI = [thisEnt getAI];
	
	if (!thisEnt->isPlayer)
	{
		if ([thisAI hasSuspendedStateMachines])
		{
			[thisAI exitStateMachine];
		}
		else
		{
			OOReportJavaScriptWarning(context, @"Ship.exitAI(): cannot cannot exit current AI state machine because there are no suspended state machines.");
		}
	}
	else
	{
		OOReportJavaScriptWarning(context, @"Ship.exitAI(): cannot modify AI for player.");
	}
	return YES;
}


static JSBool ShipReactToAIMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	message = [NSString stringWithJavaScriptValue:*argv inContext:context];
	
	if (message != nil)
	{
		if (!thisEnt->isPlayer)
		{
			[[thisEnt getAI] reactToMessage:message];
		}
		else
		{
			OOReportJavaScriptWarning(context, @"Ship.%@(\"%@\"): cannot modify AI for player.", @"reactToAIMessage", message);
		}
	}
	else
	{
		OOReportJavaScriptWarning(context, @"Ship.%@(): no message specified.", @"reactToAIMessage");
	}
	return YES;
}


static JSBool ShipDeployEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	[thisEnt deployEscorts];
	return YES;
}


static JSBool ShipDockEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	[thisEnt dockEscorts];
	return YES;
}


static JSBool ShipHasRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	role = [NSString stringWithJavaScriptValue:*argv inContext:context];
	
	*outResult = BOOLToJSVal([thisEnt hasRole:role]);
	return YES;
}


static JSBool ShipRunLegacyScriptActions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	PlayerEntity			*player = nil;
	ShipEntity				*target = nil;
	NSArray					*actions = nil;
	
	player = OOPlayerForScripting();
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	target = JSValueToObject(context, argv[0]);
	if (![target isKindOfClass:[ShipEntity class]])
	{
		OOReportJavaScriptWarning(context, @"First argument of RunLegacyScriptActions must be a Ship.");
		return YES;
	}
	
	actions = JSValueToObject(context, argv[1]);
	if (![actions isKindOfClass:[NSArray class]])
	{
		OOReportJavaScriptWarning(context, @"Second argument of RunLegacyScriptActions must be an Array.");
		return YES;
	}
	
	[player setScriptTarget:thisEnt];
	[player scriptActions:actions forTarget:target];
	
	return YES;
}
