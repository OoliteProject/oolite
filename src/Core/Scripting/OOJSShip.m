/*

OOJSShip.m

Oolite
Copyright (C) 2004-2009 Giles C Williams and contributors

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
#import "OOJSVector.h"
#import "OOJavaScriptEngine.h"
#import "ShipEntity.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#import "PlayerEntityScriptMethods.h"
#import "AI.h"
#import "OOStringParsing.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OORoleSet.h"
#import "OOJSPlayer.h"
#import "OOShipGroup.h"


DEFINE_JS_OBJECT_GETTER(JSShipGetShipEntity, ShipEntity)


static JSObject *sShipPrototype;


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsval name, jsval *outValue);
static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value);

static JSBool ShipSetScript(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSetAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSwitchAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipExitAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipReactToAIMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipDeployEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipDockEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipHasRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipEjectItem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipEjectSpecificItem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipDumpCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSpawn(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipExplode(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipRemove(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipRunLegacyScriptActions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipCommsMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipFireECM(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipHasEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipAbandonShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

static BOOL RemoveOrExplodeShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult, BOOL explode);


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
	JSObjectWrapperEquality,	// equality
	NULL,						// outerObject
	NULL,						// innerObject
	JSCLASS_NO_RESERVED_MEMBERS
};


enum
{
	// Property IDs
	kShip_name,					// name, string, read-only
	kShip_displayName,			// name displayed on screen, string, read-only
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
	kShip_group,				// group, ShipGroup, read/write
	kShip_escortGroup,			// group, ShipGroup, read-only
	kShip_temperature,			// hull temperature, double, read/write
	kShip_heatInsulation,		// hull heat insulation, double, read/write
	kShip_entityPersonality,	// per-ship random number, int, read-only
	kShip_isBeacon,				// is beacon, boolean, read-only
	kShip_beaconCode,			// beacon code, string, read-only (should probably be read/write, but the beacon list needs to be maintained.)
	kShip_isFrangible,			// frangible, boolean, read-only
	kShip_isCloaked,			// cloaked, boolean, read/write (if cloaking device installed)
	kShip_isJamming,			// jamming scanners, boolean, read/write (if jammer installed)
	kShip_potentialCollider,	// "proximity alert" ship, Entity, read-only
	kShip_hasHostileTarget,		// has hostile target, boolean, read-only
	kShip_weaponRange,			// weapon range, double, read-only
	kShip_scannerRange,			// scanner range, double, read-only
	kShip_reportAIMessages,		// report AI messages, boolean, read/write
	kShip_withinStationAegis,	// within main station aegis, boolean, read/write
	kShip_cargoCapacity,		// maximum cargo, integer, read-only
	kShip_cargoSpaceUsed,		// cargo on board, integer, read-only
	kShip_availableCargoSpace,	// free cargo space, integer, read-only
	kShip_speed,				// current flight speed, double, read-only
	kShip_desiredSpeed,			// AI desired flight speed, double, read/write
	kShip_maxSpeed,				// maximum flight speed, double, read-only
	kShip_script,				// script, Script, read-only
	kShip_isPirate,				// is pirate, boolean, read-only
	kShip_isPlayer,				// is player, boolean, read-only
	kShip_isPolice,				// is police, boolean, read-only
	kShip_isThargoid,			// is thargoid, boolean, read-only
	kShip_isTrader,				// is trader, boolean, read-only
	kShip_isPirateVictim,		// is pirate victim, boolean, read-only
	kShip_isMissile,			// is missile, boolean, read-only
	kShip_isMine,				// is mine, boolean, read-only
	kShip_isWeapon,				// is missile or mine, boolean, read-only
	kShip_scriptInfo,			// arbitrary data for scripts, dictionary, read-only
	kShip_trackCloseContacts,	// generate close contact events, boolean, read/write
	kShip_passengerCount,		// number of passengers on ship, integer, read-only
	kShip_passengerCapacity,		// amount of passenger space on ship, integer, read-only
	kShip_coordinates,			// position in system space, Vector, read/write
	
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
	{ "group",					kShip_group,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "escortGroup",			kShip_escortGroup,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "fuel",					kShip_fuel,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
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
	{ "isMissile",				kShip_isMissile,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isMine",					kShip_isMine,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isWeapon",				kShip_isWeapon,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
// "cargo" reserved for array of cargo pods or similar.
	{ "cargoSpaceUsed",			kShip_cargoSpaceUsed,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cargoCapacity",			kShip_cargoCapacity,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "availableCargoSpace",	kShip_availableCargoSpace,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxSpeed",				kShip_maxSpeed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "potentialCollider",		kShip_potentialCollider,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "primaryRole",			kShip_primaryRole,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "reportAIMessages",		kShip_reportAIMessages,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "roleProbabilities",		kShip_roleProbabilities,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "roles",					kShip_roles,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scannerRange",			kShip_scannerRange,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "script",					kShip_script,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scriptInfo",				kShip_scriptInfo,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",					kShip_name,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "displayName",			kShip_displayName,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "speed",					kShip_speed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "desiredSpeed",			kShip_desiredSpeed,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "subEntities",			kShip_subEntities,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "target",					kShip_target,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "temperature",			kShip_temperature,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "weaponRange",			kShip_weaponRange,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "withinStationAegis",		kShip_withinStationAegis,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "trackCloseContacts",		kShip_trackCloseContacts,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
// "passengers" reserved for array of characters or similar.
	{ "passengerCount",			kShip_passengerCount,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "passengerCapacity",		kShip_passengerCapacity,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "coordinates",			kShip_coordinates,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "setScript",				ShipSetScript,				1 },
	{ "setAI",					ShipSetAI,					1 },
	{ "switchAI",				ShipSwitchAI,				1 },
	{ "exitAI",					ShipExitAI,					0 },
	{ "reactToAIMessage",		ShipReactToAIMessage,		1 },
	{ "deployEscorts",			ShipDeployEscorts,			0 },
	{ "dockEscorts",			ShipDockEscorts,			0 },
	{ "hasRole",				ShipHasRole,				1 },
	{ "ejectItem",				ShipEjectItem,				1 },
	{ "ejectSpecificItem",		ShipEjectSpecificItem,		1 },
	{ "dumpCargo",				ShipDumpCargo,				0 },
	{ "runLegacyScriptActions",	ShipRunLegacyScriptActions,	2 },
	{ "spawn",					ShipSpawn,					1 },
	{ "explode",				ShipExplode,				0 },
	{ "remove",					ShipRemove,					0 },
	{ "commsMessage",			ShipCommsMessage,			1 },
	{ "fireECM",				ShipFireECM,				0 },
	{ "hasEquipment",			ShipHasEquipment,			1 },
	{ "abandonShip",			ShipAbandonShip,			0 },
	{ 0 }
};


void InitOOJSShip(JSContext *context, JSObject *global)
{
	sShipPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sShipClass.base, NULL, 0, sShipProperties, sShipMethods, NULL, NULL);
	JSRegisterObjectConverter(&sShipClass.base, JSBasicPrivateObjectConverter);
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
	BOOL						OK = NO;
	ShipEntity					*entity = nil;
	id							result = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity))) return NO;	// NOTE: entity may be nil.
	if (EXPECT_NOT(!JS_EnterLocalRootScope(context)))  return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kShip_name:
			result = [entity name];
			break;
			
		case kShip_displayName:
			result = [entity displayName];
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
			OK = JS_NewDoubleValue(context, [entity fuel] * 0.1, outValue);
			break;
		
		case kShip_bounty:
			*outValue = INT_TO_JSVAL([entity legalStatus]);
			OK = YES;
			break;
		
		case kShip_subEntities:
			result = [entity subEntitiesForScript];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_hasSuspendedAI:
			*outValue = BOOLToJSVal([[entity getAI] hasSuspendedStateMachines]);
			OK = YES;
			break;
			
		case kShip_target:
			result = [entity primaryTarget];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_escorts:
			// FIXME: use implemention in oolite-global-prefix.js once ShipGroup works.
			result = [[entity escortGroup] memberArrayExcludingLeader];
			if ([result count] == 0)  result = [NSNull null];
			break;
			
		case kShip_group:
			result = [entity group];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShip_escortGroup:
			result = [entity escortGroup];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShip_temperature:
			OK = JS_NewDoubleValue(context, [entity temperature] / SHIP_MAX_CABIN_TEMP, outValue);
			break;
			
		case kShip_heatInsulation:
			OK = JS_NewDoubleValue(context, [entity heatInsulation], outValue);
			break;
			
		case kShip_entityPersonality:
			*outValue = INT_TO_JSVAL([entity entityPersonalityInt]);
			OK = YES;
			break;
			
		case kShip_isBeacon:
			*outValue = BOOLToJSVal([entity isBeacon]);
			OK = YES;
			break;
			
		case kShip_beaconCode:
			result = [entity beaconCode];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_isFrangible:
			*outValue = BOOLToJSVal([entity isFrangible]);
			OK = YES;
			break;
		
		case kShip_isCloaked:
			*outValue = BOOLToJSVal([entity isCloaked]);
			OK = YES;
			break;
			
		case kShip_isJamming:
			*outValue = BOOLToJSVal([entity isJammingScanning]);
			OK = YES;
			break;
		
		case kShip_potentialCollider:
			result = [entity proximity_alert];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_hasHostileTarget:
			*outValue = BOOLToJSVal([entity hasHostileTarget]);
			OK = YES;
			break;
			
		case kShip_weaponRange:
			OK = JS_NewDoubleValue(context, [entity weaponRange], outValue);
			break;
			
		case kShip_scannerRange:
			OK = JS_NewDoubleValue(context, [entity scannerRange], outValue);
			break;
		
		case kShip_reportAIMessages:
			*outValue = BOOLToJSVal([entity reportAIMessages]);
			OK = YES;
			break;
		
		case kShip_withinStationAegis:
			*outValue = BOOLToJSVal([entity withinStationAegis]);
			OK = YES;
			break;
			
		case kShip_cargoCapacity:
			*outValue = INT_TO_JSVAL([entity maxCargo]);
			OK = YES;
			break;
			
		case kShip_cargoSpaceUsed:
			*outValue = INT_TO_JSVAL([entity maxCargo] - [entity availableCargoSpace]);
			OK = YES;
			break;
			
		case kShip_availableCargoSpace:
			*outValue = INT_TO_JSVAL([entity availableCargoSpace]);
			OK = YES;
			break;
			
		case kShip_speed:
			OK = JS_NewDoubleValue(context, [entity flightSpeed], outValue);
			break;
			
		case kShip_desiredSpeed:
			OK = JS_NewDoubleValue(context, [entity desiredSpeed], outValue);
			break;
			
		case kShip_maxSpeed:
			OK = JS_NewDoubleValue(context, [entity maxFlightSpeed], outValue);
			break;
			
		case kShip_script:
			result = [entity shipScript];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShip_isPirate:
			*outValue = BOOLToJSVal([entity isPirate]);
			OK = YES;
			break;
			
		case kShip_isPlayer:
			*outValue = BOOLToJSVal([entity isPlayer]);
			OK = YES;
			break;
			
		case kShip_isPolice:
			*outValue = BOOLToJSVal([entity isPolice]);
			OK = YES;
			break;
			
		case kShip_isThargoid:
			*outValue = BOOLToJSVal([entity isThargoid]);
			OK = YES;
			break;
			
		case kShip_isTrader:
			*outValue = BOOLToJSVal([entity isTrader]);
			OK = YES;
			break;
			
		case kShip_isPirateVictim:
			*outValue = BOOLToJSVal([entity isPirateVictim]);
			OK = YES;
			break;
			
		case kShip_isMissile:
			*outValue = BOOLToJSVal([entity isMissile]);
			OK = YES;
			break;
			
		case kShip_isMine:
			*outValue = BOOLToJSVal([entity isMine]);
			OK = YES;
			break;
			
		case kShip_isWeapon:
			*outValue = BOOLToJSVal([entity isWeapon]);
			OK = YES;
			break;
			
		case kShip_scriptInfo:
			result = [entity scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than NULL
			break;
			
		case kShip_trackCloseContacts:
			*outValue = BOOLToJSVal([entity trackCloseContacts]);
			OK = YES;
			break;
			
		case kShip_passengerCount:
			*outValue = INT_TO_JSVAL([entity passengerCount]);
			OK = YES;
			break;
			
		case kShip_passengerCapacity:
			*outValue = INT_TO_JSVAL([entity passengerCapacity]);
			OK = YES;
			break;
		
		case kShip_coordinates:
			OK = VectorToJSValue(context, [entity coordinates], outValue); // @@@@ should be coordinates
			break;
		
		default:
			OOReportJSBadPropertySelector(context, @"Ship", JSVAL_TO_INT(name));
	}
	
	if (result != nil)
	{
		*outValue = [result javaScriptValueInContext:context];
		OK = YES;
	}
	JS_LeaveLocalRootScope(context);
	return OK;
}


static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsval name, jsval *value)
{
	BOOL						OK = NO;
	ShipEntity					*entity = nil;
	ShipEntity					*target = nil;
	NSString					*sValue = nil;
	jsdouble					fValue;
	int32						iValue;
	JSBool						bValue;
	Vector						vValue;
	OOShipGroup					*group = nil;
	
	if (!JSVAL_IS_INT(name))  return YES;
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity))) return NO;
	
	switch (JSVAL_TO_INT(name))
	{
		case kShip_name:
			if ([entity isPlayer])
			{
				OOReportJSError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"name", @"name");
			}
			else
			{
				sValue = JSValToNSString(context,*value);
				if (sValue != nil)
				{
					[entity setName:sValue];
					OK = YES;
				}
			}
			break;
			
		case kShip_displayName:
			if ([entity isPlayer])
			{
				OOReportJSError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"displayName", @"displayName");
			}
			else
			{
				sValue = JSValToNSString(context,*value);
				if (sValue != nil)
				{
					[entity setDisplayName:sValue];
					OK = YES;
				}
			}
			break;
		
		case kShip_primaryRole:
			if ([entity isPlayer])
			{
				OOReportJSError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"primaryRole", @"primary role");
			}
			else
			{
				sValue = JSValToNSString(context,*value);
				if (sValue != nil)
				{
					[entity setPrimaryRole:sValue];
					OK = YES;
				}
			}
			break;
		
		case kShip_AIState:
			if ([entity isPlayer])
			{
				OOReportJSError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"AIState", @"AI state");
			}
			else
			{
				sValue = JSValToNSString(context,*value);
				if (sValue != nil)
				{
					[[entity getAI] setState:sValue];
					OK = YES;
				}
			}
			break;
		
		case kShip_fuel:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, 7.0);
				[entity setFuel:lround(fValue * 10.0)];
				OK = YES;
			}
			break;
			
		case kShip_bounty:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setBounty:iValue];
				OK = YES;
			}
			break;
		
		case kShip_target:
			if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
			{
				[entity setTargetForScript:target];
				OK = YES;
			}
			break;
			
		case kShip_group:
			group = JSValueToObjectOfClass(context, *value, [OOShipGroup class]);
			if (group != nil || JSVAL_IS_NULL(*value))
			{
				[entity setGroup:group];
				OK = YES;
			}
			break;
		
		case kShip_temperature:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOMax_d(fValue, 0.0);
				[entity setTemperature:fValue * SHIP_MAX_CABIN_TEMP];
				OK = YES;
			}
			break;
		
		case kShip_heatInsulation:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOMax_d(fValue, 0.125);
				[entity setHeatInsulation:fValue];
				OK = YES;
			}
			break;
		
		case kShip_isCloaked:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setCloaked:bValue];
				OK = YES;
			}
			break;
		
		case kShip_reportAIMessages:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setReportAIMessages:bValue];
				OK = YES;
			}
			break;
			
		case kShip_trackCloseContacts:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setTrackCloseContacts:bValue];
				OK = YES;
			}
			break;
		
		case kShip_desiredSpeed:
			if ([entity isPlayer])
			{
				OOReportJSError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"desiredSpeed", @"desired speed");
			}
			else
			{
				if (JS_ValueToNumber(context, *value, &fValue))
				{
					[entity setDesiredSpeed:fmax(fValue, 0.0)];
					OK = YES;
				}
			}
			break;
		
		case kShip_coordinates:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setCoordinate:vValue];
				OK = YES;
			}
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Ship", JSVAL_TO_INT(name));
	}
	if (OK == NO)
	{
		OOReportJSWarning(context, @"Invalid value type for this property. Value not set.");
	}
	return OK;
}


// *** Methods ***

// setScript(scriptName : String)
static JSBool ShipSetScript(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setScript", argc, argv, nil, @"script name");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"setScript", @"Cannot change script for player.");
		return NO;
	}
	
	[thisEnt setShipScript:name];
	return YES;
}


// setAI(aiName : String)
static JSBool ShipSetAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setAI", argc, argv, nil, @"AI name");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"setAI", @"Cannot modify AI for player.");
		return NO;
	}
	
	[thisEnt setAITo:name];
	return YES;
}


// switchAI(aiName : String)
static JSBool ShipSwitchAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	name = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"switchAI", argc, argv, nil, @"AI name");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"switchAI", @"Cannot modify AI for player.");
		return NO;
	}
	
	[thisEnt switchAITo:name];
	return YES;
}


// exitAI()
static JSBool ShipExitAI(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	AI						*thisAI = nil;
	NSString				*message = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"exitAI", @"Cannot modify AI for player.");
		return NO;
	}
	thisAI = [thisEnt getAI];
	
	if (argc > 0)
	{
		message = JSValToNSString(context, argv[0]);
	}
	
	if (![thisAI hasSuspendedStateMachines])
	{
		OOReportJSWarningForCaller(context, @"Ship", @"exitAI()", @"Cannot exit current AI state machine because there are no suspended state machines.");
	}
	else
	{
		[thisAI exitStateMachineWithMessage:message];
	}
	return YES;
}


// reactToAIMessage(message : String)
static JSBool ShipReactToAIMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	message = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(message == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"reactToAIMessage", argc, argv, nil, @"message");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"reactToAIMessage", @"Cannot modify AI for player.");
		return NO;
	}
	
	[thisEnt reactToAIMessage:message];
	return YES;
}


// deployEscorts()
static JSBool ShipDeployEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	[thisEnt deployEscorts];
	return YES;
}


// dockEscorts()
static JSBool ShipDockEscorts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	[thisEnt dockEscorts];
	return YES;
}


// hasRole(role : String) : Boolean
static JSBool ShipHasRole(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	role = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"hasRole", argc, argv, nil, @"role");
		return NO;
	}
	
	*outResult = BOOLToJSVal([thisEnt hasRole:role]);
	return YES;
}


// ejectItem(role : String) : Ship
static JSBool ShipEjectItem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	ShipEntity				*result = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	role = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"ejectItem", argc, argv, nil, @"role");
		return NO;
	}
	
	result = [thisEnt ejectShipOfRole:role];
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// ejectSpecificItem(itemKey : String) : Ship
static JSBool ShipEjectSpecificItem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*itemKey = nil;
	ShipEntity				*result = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	itemKey = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(itemKey == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"ejectSpecificItem", argc, argv, nil, @"ship key");
		return NO;
	}
	
	result = [thisEnt ejectShipOfType:itemKey];
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// dumpCargo() : Ship
static JSBool ShipDumpCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	ShipEntity				*result = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	if ([thisEnt isPlayer] && [(PlayerEntity *)thisEnt isDocked])
	{
		OOReportJSWarningForCaller(context, @"Player", @"dumpCargo", @"Can't dump cargo while docked, ignoring.");
		return YES;
	}
	
	result = [thisEnt dumpCargoItem];
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// spawn(role : String [, number : count]) : Array
static JSBool ShipSpawn(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	int32					count = 1;
	BOOL					gotCount = YES;
	NSArray					*result = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	role = JSValToNSString(context, argv[0]);
	if (argc > 1)  gotCount = JS_ValueToInt32(context, argv[1], &count);
	if (EXPECT_NOT(role == nil || !gotCount || count < 1 || count > 64))
	{
		OOReportJSBadArguments(context, @"Ship", @"spawn", argc, argv, nil, @"role and optional positive count no greater than 64");
		return NO;
	}
	
	result = [thisEnt spawnShipsWithRole:role count:count];
	
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// explode()
static JSBool ShipExplode(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	return RemoveOrExplodeShip(context, this, argc, argv, outResult, YES);
}


// remove()
static JSBool ShipRemove(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	JSBool					removeDeathActions = NO;
	if (!JSShipGetShipEntity(context, this, &thisEnt) ) return YES;	// stale reference, no-op.
	if ([thisEnt isPlayer]) return NO;
	
	if ( argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, argv[0], &removeDeathActions)))
	{
		OOReportJSBadArguments(context, @"Ship", @"remove", argc, argv, nil, @"boolean");
		return NO;
	}

	[thisEnt doScriptEvent:@"shipRemoved" withArgument:[NSNumber numberWithBool:removeDeathActions]];

	if (removeDeathActions)
	{
		//OOReportJSWarning(context, @"Ship.remove(): all death actions will now be removed from %@", thisEnt);
		[thisEnt removeScript];
	}
	return RemoveOrExplodeShip(context, this, argc, argv, outResult, NO);
}


// runLegacyShipActions(target : Ship, actions : Array)
static JSBool ShipRunLegacyScriptActions(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	PlayerEntity			*player = nil;
	ShipEntity				*target = nil;
	NSArray					*actions = nil;
	
	player = OOPlayerForScripting();
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	actions = JSValueToObject(context, argv[1]);
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(argv[0]) ||
				   !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(argv[0]), &target) ||
				   ![actions isKindOfClass:[NSArray class]]))
	{
		OOReportJSBadArguments(context, @"Ship", @"runLegacyScriptActions", argc, argv, nil, @"target and array of actions");
		return NO;
	}
	
	[player setScriptTarget:thisEnt];
	[player runUnsanitizedScriptActions:actions
					  allowingAIMethods:YES
						withContextName:[NSString stringWithFormat:@"<ship \"%@\" legacy actions>", [thisEnt name]]
							  forTarget:target];
	
	return YES;
}


// commsMessage(message : String)
static JSBool ShipCommsMessage(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	message = JSValToNSString(context, *argv);
	if (EXPECT_NOT(message == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"commsMessage", argc, argv, nil, @"message");
		return NO;
	}
	
	if (![thisEnt isPlayer])
	{
		[thisEnt commsMessage:message withUnpilotedOverride:YES];
	}
	return YES;
}


// fireECM()
static JSBool ShipFireECM(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))  return YES;	// stale reference, no-op.
	
	if (![thisEnt fireECM])
	{
		OOReportJSWarning(context, @"Ship %@ was requested to fire ECM burst but does not carry ECM equipment.", thisEnt);
	}
	return YES;
}


// hasEquipment(key : String [, includeWeapons : Boolean]) : Boolean
static JSBool ShipHasEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	JSBool						includeWeapons = YES;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	key = JSValToNSString(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"hasEquipment", argc, argv, nil, @"equipment key");
		return NO;
	}
	
	if (argc > 1)
	{
		if (EXPECT_NOT(!JS_ValueToBoolean(context, argv[1], &includeWeapons)))
		{
			OOReportJSBadArguments(context, @"Ship", @"hasEquipment", argc - 1, argv + 1, nil, @"boolean");
			return NO;
		}
	}
	
	*outResult = BOOLToJSVal([thisEnt hasEquipmentItem:key includeWeapons:includeWeapons]);
	return YES;
}


static BOOL RemoveOrExplodeShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult, BOOL explode)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	if (!explode && [thisEnt isPlayer])  return YES;	// Silently fail on player.ship.remove()
	
	if (thisEnt == (ShipEntity *)[UNIVERSE station])
	{
		// Allow exploding of main station (e.g. nova mission)
		[UNIVERSE unMagicMainStation];
	}
	
	[thisEnt setSuppressExplosion:!explode];
	[thisEnt setEnergy:1];
	[thisEnt takeEnergyDamage:500000000.0 from:nil becauseOf:nil];
	
	return YES;
}


static JSBool ShipAbandonShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	BOOL hasPod = [thisEnt hasEscapePod];

	if (hasPod)
	{
		[thisEnt abandonShip];
	}
	
	*outResult = BOOLToJSVal(hasPod);
	return YES;
}
