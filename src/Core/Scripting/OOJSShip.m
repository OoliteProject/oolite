/*

OOJSShip.m

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

#import "OOJSShip.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJSEquipmentInfo.h"
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
#import "PlayerEntityContracts.h"
#import "OOEquipmentType.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"


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
static JSBool ShipAbandonShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipAddPassenger(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipAwardContract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipCanAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSetEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSelectNewMissile(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipFireMissile(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSetCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSetMaterials(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipSetShaders(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);
static JSBool ShipExitSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult);

static BOOL RemoveOrExplodeShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult, BOOL explode);
static BOOL ValidateContracts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult, BOOL isCargo);


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
	kShip_aftWeapon,			// the ship's aft weapon, equipmentType, read only
	kShip_AI,					// AI state machine name, string, read/write
	kShip_AIState,				// AI state machine state, string, read/write
	kShip_beaconCode,			// beacon code, string, read-only (should probably be read/write, but the beacon list needs to be maintained.)
	kShip_bounty,				// bounty, unsigned int, read/write
	kShip_cargoSpaceAvailable,	// free cargo space, integer, read-only
	kShip_cargoSpaceCapacity,	// maximum cargo, integer, read-only
	kShip_cargoSpaceUsed,		// cargo on board, integer, read-only
	kShip_contracts,			// cargo contracts contracts, array - strings & whatnot, read only
	kShip_desiredSpeed,			// AI desired flight speed, double, read/write
	kShip_displayName,			// name displayed on screen, string, read-only
	kShip_entityPersonality,	// per-ship random number, int, read-only
	kShip_equipment,			// the ship's equipment, array of EquipmentInfo, read only
	kShip_escortGroup,			// group, ShipGroup, read-only
	kShip_escorts,				// deployed escorts, array of Ship, read-only
	kShip_forwardWeapon,		// the ship's forward weapon, equipmentType, read only
	kShip_fuel,					// fuel, float, read/write
	kShip_fuelChargeRate,		// fuel scoop rate & charge multiplier, float, read-only
	kShip_group,				// group, ShipGroup, read/write
	kShip_hasHostileTarget,		// has hostile target, boolean, read-only
	kShip_hasSuspendedAI,		// AI has suspended states, boolean, read-only
	kShip_heatInsulation,		// hull heat insulation, double, read/write
	kShip_isBeacon,				// is beacon, boolean, read-only
	kShip_isBoulder,			// is a boulder (generates splinters), boolean, read/write
	kShip_isCargo,				// contains cargo, boolean, read-only
	kShip_isCloaked,			// cloaked, boolean, read/write (if cloaking device installed)
	kShip_isDerelict,			// is an abandoned ship, boolean, read-only
	kShip_isFrangible,			// frangible, boolean, read-only
	kShip_isJamming,			// jamming scanners, boolean, read/write (if jammer installed)
	kShip_isMine,				// is mine, boolean, read-only
	kShip_isMissile,			// is missile, boolean, read-only
	kShip_isPirate,				// is pirate, boolean, read-only
	kShip_isPirateVictim,		// is pirate victim, boolean, read-only
	kShip_isPlayer,				// is player, boolean, read-only
	kShip_isPolice,				// is police, boolean, read-only
	kShip_isRock,				// is a rock (hermits included), boolean, read-only
	kShip_isThargoid,			// is thargoid, boolean, read-only
	kShip_isTrader,				// is trader, boolean, read-only
	kShip_isWeapon,				// is missile or mine, boolean, read-only
	kShip_lightsActive,			// flasher/shader light flag, boolean, read/write
	kShip_maxSpeed,				// maximum flight speed, double, read-only
	kShip_maxThrust,			// maximum thrust, double, read-only
	kShip_missileCapacity,		// max missiles capacity, integer, read-only
	kShip_missiles,				// the ship's missiles / external storage, array of equipmentTypes, read only
	kShip_name,					// name, string, read-only
	kShip_passengerCapacity,	// amount of passenger space on ship, integer, read-only
	kShip_passengerCount,		// number of passengers on ship, integer, read-only
	kShip_passengers,			// passengers contracts, array - strings & whatnot, read only
	kShip_portWeapon,			// the ship's port weapon, equipmentType, read only
	kShip_potentialCollider,	// "proximity alert" ship, Entity, read-only
	kShip_primaryRole,			// Primary role, string, read/write
	kShip_reportAIMessages,		// report AI messages, boolean, read/write
	kShip_roleProbabilities,	// roles and probabilities, dictionary, read-only
	kShip_roles,				// roles, array, read-only
	kShip_savedCoordinates,		// coordinates in system space for AI use, Vector, read/write
	kShip_scannerDisplayColor1,	// color of lollipop shown on scanner, array, read/write
	kShip_scannerDisplayColor2,	// color of lollipop shown on scanner when flashing, array, read/write
	kShip_scannerRange,			// scanner range, double, read-only
	kShip_script,				// script, Script, read-only
	kShip_scriptInfo,			// arbitrary data for scripts, dictionary, read-only
	kShip_speed,				// current flight speed, double, read-only
	kShip_starboardWeapon,		// the ship's starboard weapon, equipmentType, read only
	kShip_subEntities,			// subentities, array of Ship, read-only
	kShip_target,				// target, Ship, read/write
	kShip_temperature,			// hull temperature, double, read/write
	kShip_thrust,				// the ship's thrust, double, read/write
	kShip_thrustVector,			// thrust-related component of velocity, vector, read-only
	kShip_trackCloseContacts,	// generate close contact events, boolean, read/write
	kShip_velocity,				// velocity, vector, read/write
	kShip_weaponRange,			// weapon range, double, read-only
	kShip_withinStationAegis,	// within main station aegis, boolean, read/write
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
	{ "fuelChargeRate",			kShip_fuelChargeRate,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasHostileTarget",		kShip_hasHostileTarget,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasSuspendedAI",			kShip_hasSuspendedAI,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "heatInsulation",			kShip_heatInsulation,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isBeacon",				kShip_isBeacon,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isCloaked",				kShip_isCloaked,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isCargo",				kShip_isCargo,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isDerelict",				kShip_isDerelict,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isFrangible",			kShip_isFrangible,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isJamming",				kShip_isJamming,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isMine",					kShip_isMine,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isMissile",				kShip_isMissile,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPirate",				kShip_isPirate,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPirateVictim",			kShip_isPirateVictim,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlayer",				kShip_isPlayer,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPolice",				kShip_isPolice,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isRock",					kShip_isRock,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isBoulder",				kShip_isBoulder,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isThargoid",				kShip_isThargoid,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isTrader",				kShip_isTrader,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isWeapon",				kShip_isWeapon,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cargoSpaceUsed",			kShip_cargoSpaceUsed,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cargoSpaceCapacity",		kShip_cargoSpaceCapacity,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cargoSpaceAvailable",	kShip_cargoSpaceAvailable,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
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
	{ "passengerCount",			kShip_passengerCount,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "passengerCapacity",		kShip_passengerCapacity,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "missileCapacity",		kShip_missileCapacity,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "savedCoordinates",		kShip_savedCoordinates,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "equipment",				kShip_equipment,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "forwardWeapon",			kShip_forwardWeapon,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "aftWeapon",				kShip_aftWeapon,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "portWeapon",				kShip_portWeapon,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "starboardWeapon",		kShip_starboardWeapon,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "missiles",				kShip_missiles,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "passengers",				kShip_passengers,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
// contracts instead of cargo to distinguish them from the manifest
	{ "contracts",				kShip_contracts,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scannerDisplayColor1",	kShip_scannerDisplayColor1,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scannerDisplayColor2",	kShip_scannerDisplayColor2,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "maxThrust",				kShip_maxThrust,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "thrust",					kShip_thrust,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "lightsActive",			kShip_lightsActive,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "velocity",				kShip_velocity,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "thrustVector",			kShip_thrustVector,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ 0 }
};


static JSFunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "abandonShip",			ShipAbandonShip,			0 },
	{ "addPassenger",			ShipAddPassenger,			0 },	// Documented as PlayerShip
	{ "awardContract",			ShipAwardContract,			0 },	// Documented as PlayerShip
	{ "awardEquipment",			ShipAwardEquipment,			1 },
	{ "canAwardEquipment",		ShipCanAwardEquipment,		1 },
	{ "commsMessage",			ShipCommsMessage,			1 },
	{ "deployEscorts",			ShipDeployEscorts,			0 },
	{ "dockEscorts",			ShipDockEscorts,			0 },
	{ "dumpCargo",				ShipDumpCargo,				0 },
	{ "ejectItem",				ShipEjectItem,				1 },
	{ "ejectSpecificItem",		ShipEjectSpecificItem,		1 },
	{ "equipmentStatus",		ShipEquipmentStatus,		1 },
	{ "exitAI",					ShipExitAI,					0 },
	{ "exitSystem",				ShipExitSystem,				0 },
	{ "explode",				ShipExplode,				0 },
	{ "fireECM",				ShipFireECM,				0 },
	{ "fireMissile",			ShipFireMissile,			0 },
	{ "hasRole",				ShipHasRole,				1 },
	{ "reactToAIMessage",		ShipReactToAIMessage,		1 },
	{ "remove",					ShipRemove,					0 },
	{ "removeEquipment",		ShipRemoveEquipment,		1 },
	{ "runLegacyScriptActions",	ShipRunLegacyScriptActions,	2 },	// Deliberately not documented
	{ "selectNewMissile",		ShipSelectNewMissile,		0 },
	{ "setAI",					ShipSetAI,					1 },
	{ "setCargo",				ShipSetCargo,				1 },
	{ "setEquipmentStatus",		ShipSetEquipmentStatus,		2 },
	{ "setMaterials",			ShipSetMaterials,			1 },
	{ "setScript",				ShipSetScript,				1 },
	{ "setShaders",				ShipSetShaders,				2 },
	{ "spawn",					ShipSpawn,					1 },
	// spawnOne() is defined in the prefix script.
	{ "switchAI",				ShipSwitchAI,				1 },
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
		
		case kShip_fuelChargeRate:
			OK = JS_NewDoubleValue(context, [entity fuelChargeRate], outValue);
			break;

		case kShip_bounty:
			*outValue = INT_TO_JSVAL([entity bounty]);
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
			
		case kShip_cargoSpaceCapacity:
			*outValue = INT_TO_JSVAL([entity maxCargo]);
			OK = YES;
			break;
			
		case kShip_cargoSpaceUsed:
			*outValue = INT_TO_JSVAL([entity maxCargo] - [entity availableCargoSpace]);
			OK = YES;
			break;
			
		case kShip_cargoSpaceAvailable:
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
			
		case kShip_isRock:
			*outValue = BOOLToJSVal([entity scanClass] == CLASS_ROCK);	// hermits and asteroids!
			OK = YES;
			break;
			
		case kShip_isBoulder:
			*outValue = BOOLToJSVal([entity isBoulder]);
			OK = YES;
			break;
			
		case kShip_isCargo:
			*outValue = BOOLToJSVal([entity scanClass] == CLASS_CARGO && [entity commodityAmount] > 0);
			OK = YES;
			break;
			
		case kShip_isDerelict:
			*outValue = BOOLToJSVal([entity isHulk]);
			OK = YES;
			break;
			
		case kShip_scriptInfo:
			result = [entity scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than undefined
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

		case kShip_missileCapacity:
			*outValue = INT_TO_JSVAL([entity missileCapacity]);
			OK = YES;
			break;
		
		case kShip_savedCoordinates:
			OK = VectorToJSValue(context, [entity coordinates], outValue);
			break;
		
		case kShip_equipment:
			result = [entity equipmentListForScripting];
			break;
			
		case kShip_forwardWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_FORWARD];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_aftWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_AFT];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_portWeapon:		// for future expansion
			result = [entity weaponTypeForFacing:WEAPON_FACING_PORT];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_starboardWeapon: // for future expansion
			result = [entity weaponTypeForFacing:WEAPON_FACING_STARBOARD];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_missiles:
			result = [entity missilesList];
			break;
		
		case kShip_passengers:
			result = [entity passengerListForScripting];
			break;
		
		case kShip_contracts:
			result = [entity contractListForScripting];
			break;
			
		case kShip_scannerDisplayColor1:
			result = [[entity scannerDisplayColor1] normalizedArray];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShip_scannerDisplayColor2:
			result = [[entity scannerDisplayColor2] normalizedArray];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_maxThrust:
			OK = JS_NewDoubleValue(context, [entity maxThrust], outValue);
			break;
			
		case kShip_thrust:
			OK = JS_NewDoubleValue(context, [entity thrust], outValue);
			break;
			
		case kShip_lightsActive:
			*outValue = BOOLToJSVal([entity lightsActive]);
			OK = YES;
			break;
			
		case kShip_velocity:
			OK = VectorToJSValue(context, [entity velocity], outValue);
			break;
			
		case kShip_thrustVector:
			OK = VectorToJSValue(context, [entity thrustVector], outValue);
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
	OOColor						*colorForScript = nil;
	
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
			if (JSVAL_IS_NULL(*value))
			{
				[entity setTargetForScript:nil];
				OK = YES;
			}
			else if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
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
		
		case kShip_isBoulder:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setIsBoulder:bValue];
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
		
		case kShip_savedCoordinates:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setCoordinate:vValue];
				OK = YES;
			}
			break;
			
		case kShip_scannerDisplayColor1:
			colorForScript = [OOColor colorWithDescription:JSValueToObject(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setScannerDisplayColor1:colorForScript];
				OK = YES;
			}
			break;
			
		case kShip_scannerDisplayColor2:
			colorForScript = [OOColor colorWithDescription:JSValueToObject(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setScannerDisplayColor2:colorForScript];
				OK = YES;
			}
			break;
			
		case kShip_thrust:
			if ([entity isPlayer])
			{
				OOReportJSError(context, @"Ship.%@ [setter]: cannot set %@ for player.", @"thrust", @"thrust");
			}
			else
			{
				if (JS_ValueToNumber(context, *value, &fValue))
				{
					[entity setThrust:OOClamp_0_max_f(fValue, [entity maxThrust])];
					OK = YES;
				}
			}
			break;
			
		case kShip_lightsActive:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				if (bValue)  [entity switchLightsOn];
				else  [entity switchLightsOff];
				OK = YES;
			}
			break;
			
		case kShip_velocity:
			if (JSValueToVector(context, *value, &vValue))
			{
				/*	Silliness: the ship's velocity vector is the sum of the
					thrust vector and a base velocity. Here we find the
					thrust vector (and any other weird vectors that may be
					added into the mix) and alter the base velocity to get
					the requested total velocity.
					-- Ahruman 2010-03-03
				*/
				[entity setTotalVelocity:vValue];
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
	
	[thisEnt reactToAIMessage:message context:@"JavaScript reactToAIMessage()"];
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
		OOReportJSWarningForCaller(context, @"PlayerShip", @"dumpCargo", @"Can't dump cargo while docked, ignoring.");
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
		OOReportJSBadArguments(context, @"Ship", @"spawn", argc, argv, nil, @"role and optional quantity (1 to 64)");
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


// remove([suppressDeathEvent : Boolean = false])
static JSBool ShipRemove(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	JSBool					suppressDeathEvent = NO;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))  return YES;	// stale reference, no-op.
	
	if ([thisEnt isPlayer])
	{
		OOReportJSError(context, @"Cannot remove() player's ship.");
		return NO;
	}
	
	if ( argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, argv[0], &suppressDeathEvent)))
	{
		OOReportJSBadArguments(context, @"Ship", @"remove", argc, argv, nil, @"boolean");
		return NO;
	}

	[thisEnt doScriptEvent:@"shipRemoved" withArgument:[NSNumber numberWithBool:suppressDeathEvent]];

	if (suppressDeathEvent)
	{
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
	BOOL					OK;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))  return YES;	// stale reference, no-op.
	
	OK = [thisEnt fireECM];
	if (!OK)
	{
		OOReportJSWarning(context, @"Ship %@ was requested to fire ECM burst but does not carry ECM equipment.", thisEnt);
	}
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// abandonShip()
static JSBool ShipAbandonShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	BOOL hasPod = [thisEnt hasEscapePod];

	if (hasPod)
	{
		[thisEnt abandonShip];
	}
	
	*outResult = BOOLToJSVal(hasPod);
	return YES;
}


// addPassenger(name: string, start: int, destination: int, eta: double, fee: double)
static JSBool ShipAddPassenger(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity			*thisEnt = nil;
	BOOL				OK = YES;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	NSString			*name = nil;
	
	if (argc == 5)
	{
		name = JSValToNSString(context, argv[0]);
		if (EXPECT_NOT(name == nil || JSVAL_IS_INT(argv[0])))
		{
			OOReportJSBadArguments(context, @"Ship", @"addPassenger", argc, argv, nil, @"name:string");
			return NO;
		}
		OK = ValidateContracts(context, this, argc, argv, outResult, NO);
		if (!OK) return NO;
		
		if (![thisEnt isPlayer] || [thisEnt passengerCount] >= [thisEnt passengerCapacity])
		{
			OOReportJSWarning(context, @"Ship.%@(): cannot %@.", @"addPassenger", @"add passenger");
			OK = NO;
		}
	}
	else
	{
		OOReportJSBadArguments(context, @"Ship", @"addPassenger", argc, argv, nil, @"name, start, destination, eta, fee");
		return NO;
	}
	
	if (OK)
	{
		jsdouble		eta,fee;
		JS_ValueToNumber(context, argv[3], &eta);
		JS_ValueToNumber(context, argv[4], &fee);
		OK = [(PlayerEntity*)thisEnt addPassenger:name start:JSVAL_TO_INT(argv[1]) destination:JSVAL_TO_INT(argv[2]) eta:eta fee:fee];
	}
	
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double)
static JSBool ShipAwardContract(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity			*thisEnt = nil;
	BOOL				OK = JSVAL_IS_INT(argv[0]);
	NSString 			*key = nil;
	int 				qty = 0;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	if (OK && argc == 6)
	{
		key = JSValToNSString(context, argv[1]);
		if (EXPECT_NOT(key == nil || !JSVAL_IS_STRING(argv[1])))
		{
			OOReportJSBadArguments(context, @"Ship", @"awardContract", argc, argv, nil, @"commodity identifier:string");
			return NO;
		}
		OK = ValidateContracts(context, this, argc, argv, outResult, YES); // always go through validate contracts (cargo)
		if (!OK) return NO;
		
		qty = JSVAL_TO_INT(argv[0]);
		
		if (![thisEnt isPlayer] || qty < 1)
		{
			OOReportJSWarning(context, @"Ship.%@(): cannot %@.", @"awardContract", @"award contract");
			OK = NO;
		}
	}
	else
	{
		if (argc == 6) 
			OOReportJSBadArguments(context, @"Ship", @"awardContract", argc, argv, nil, @"quantity:int");
		else
			OOReportJSBadArguments(context, @"Ship", @"awardContract", argc, argv, nil, @"quantity, commodity, start, destination, eta, fee");
		return NO;
	}
	
	if (OK)
	{
		jsdouble		eta,fee;
		JS_ValueToNumber(context, argv[4], &eta);
		JS_ValueToNumber(context, argv[5], &fee);
		// commodity key is case insensitive.
		OK = [(PlayerEntity*)thisEnt awardContract:qty commodity:key 
									start:JSVAL_TO_INT(argv[2]) destination:JSVAL_TO_INT(argv[3]) eta:eta fee:fee];
	}
	
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// canAwardEquipment(type : equipmentInfoExpression)
static JSBool ShipCanAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						result;
	BOOL						isBerth;
	BOOL						exists;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	key = JSValueToEquipmentKeyRelaxed(context, argv[0], &exists);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"canAwardEquipment", argc, argv, nil, @"equipment type");
		return NO;
	}
	
	if (exists)
	{
		isBerth = [key isEqualToString:@"EQ_PASSENGER_BERTH"];
		// can't add fuel as equipment, can add multiple berths if there's space.
		result = ![key isEqualToString:@"EQ_FUEL"] && (![thisEnt hasEquipmentItem:key] ||
				(isBerth && [thisEnt availableCargoSpace] >= 5));
		if (result)
		{
			if ( ([key isEqualToString:@"EQ_ENERGY_BOMB"] && [OOEquipmentType equipmentTypeWithIdentifier:key] == nil)
				|| (![thisEnt isPlayer] && (isBerth || [key isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"]))
				|| ([key isEqualToString:@"EQ_MISSILE_REMOVAL"] && [thisEnt missileCount] == 0) )
			{
				result = NO;
			}
			else
			{
				result = [thisEnt canAddEquipment:key];
			}
		}
	}
	else
	{
		// Unknown type.
		result = NO;
	}

	
	*outResult = BOOLToJSVal(result);
	return YES;
}


// awardEquipment(type : equipmentInfoExpression)
static JSBool ShipAwardEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						OK = YES;
	BOOL						berth;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	key = JSValueToEquipmentKey(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"awardEquipment", argc, argv, nil, @"equipment type");
		return NO;
	}
	berth = [key isEqualToString:@"EQ_PASSENGER_BERTH"];
	// don't add fuel, but add multiple berths if there's space - missiles are ignored in this check.
	OK = ![key isEqualToString:@"EQ_FUEL"] && (![thisEnt hasEquipmentItem:key] ||
			(berth && [thisEnt availableCargoSpace] >= 5));
			
	
	if (OK)
	{
		// Compatibility: magically transform energy bombs into q-mines.
		if ([key isEqualToString:@"EQ_ENERGY_BOMB"] && [OOEquipmentType equipmentTypeWithIdentifier:key] == nil)
		{
			key = @"EQ_QC_MINE";
		}
		
		if ([thisEnt isPlayer])
		{
			if ([key isEqualToString:@"EQ_MISSILE_REMOVAL"]) [(PlayerEntity*)thisEnt removeMissiles];
			else if (berth || [key isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"]) OK = [(PlayerEntity*)thisEnt changePassengerBerths:(berth ? +1 : -1)];
			// unknown types and EQ_CARGO_BAY are dealt with inside awardEquipment
			else OK = [(PlayerEntity*)thisEnt awardEquipment:key];
		}
		else if([OOEquipmentType equipmentTypeWithIdentifier:key] != nil)
		{
			if ([key isEqualToString:@"EQ_MISSILE_REMOVAL"]) [thisEnt removeMissiles];
			// no passenger handling for NPCs. EQ_CARGO_BAY is dealt with inside addEquipmentItem
			else if (!berth && ![key isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
							OK = [thisEnt addEquipmentItem:key];
			else OK = NO;
		}
	}
	
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// removeEquipment(type : equipmentInfoExpression)
static JSBool ShipRemoveEquipment(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						OK = YES;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	key = JSValueToEquipmentKey(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"removeEquipment", argc, argv, nil, @"equipment type");
		return NO;
	}
	// berths are not in hasOneEquipmentItem
	OK = [thisEnt hasOneEquipmentItem:key includeMissiles:YES] || ([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [thisEnt passengerCapacity] > 0);
	if (OK)
	{
		//exceptions
		if ([key isEqualToString:@"EQ_PASSENGER_BERTH"] || [key isEqualToString:@"EQ_CARGO_BAY"])
		{
			if ([key isEqualToString:@"EQ_PASSENGER_BERTH"])
			{
				if ([thisEnt passengerCapacity] > [thisEnt passengerCount])
				{
					// must be the player's ship!
					if ([thisEnt isPlayer]) [(PlayerEntity*)thisEnt changePassengerBerths:-1];
				}
				else OK = NO;
			}
			else	// EQ_CARGO_BAY
			{
				if ([thisEnt extraCargo] <= [thisEnt availableCargoSpace])
				{
					[thisEnt removeEquipmentItem:key];
				}
				else OK = NO;
			}
		}
		else
			[thisEnt removeEquipmentItem:key];
	}
	
	*outResult = BOOLToJSVal(OK);
	return YES;
}


// setEquipmentStatus(type : equipmentInfoExpression, status : String)
static JSBool ShipSetEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	// equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"
	
	ShipEntity				*thisEnt = nil;
	NSString				*key = nil;
	NSString				*damagedKey = nil;
	NSString				*status = nil;
	BOOL					hasOK = NO, hasDamaged = NO;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	return YES;	// stale reference, no-op.
	
	if (EXPECT_NOT([UNIVERSE strict]))
	{
		// It's OK to have a hard error here since only built-in scripts run in strict mode.
		OOReportJSError(context, @"Cannot set equipment status while in strict mode.");
		return NO;
	}
	
	key = JSValueToEquipmentKey(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setEquipmentStatus", argc, argv, nil, @"equipment type");
		return NO;
	}
	
	status = JSValToNSString(context, argv[1]);
	if (EXPECT_NOT(status == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setEquipmentStatus", argc - 1, argv + 1, nil, @"equipment status");
		return NO;
	}
	
	if (![status isEqualToString:@"EQUIPMENT_OK"] && ![status isEqualToString:@"EQUIPMENT_DAMAGED"])
	{
		OOReportJSErrorForCaller(context, @"Ship", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
		return NO;
	}
	
	damagedKey = [key stringByAppendingString:@"_DAMAGED"];
	hasOK = [thisEnt hasEquipmentItem:key];
	hasDamaged = [thisEnt hasEquipmentItem:damagedKey];
	
	if (([status isEqualToString:@"EQUIPMENT_OK"] && hasDamaged) || ([status isEqualToString:@"EQUIPMENT_DAMAGED"] && hasOK))
	{
		// the implementation is identical between player and ship.
		[thisEnt removeEquipmentItem:key];
		if ([thisEnt isPlayer])
		{
			// these player methods are different to the ship ones.
			[(PlayerEntity*)thisEnt addEquipmentItem:(hasOK ? damagedKey : key)];
			if (hasOK) [(PlayerEntity*)thisEnt doScriptEvent:@"equipmentDamaged" withArgument:key];
			// if player's Docking Computers are set to EQUIPMENT_DAMAGED while on, stop them
			if (hasOK && [key isEqualToString:@"EQ_DOCK_COMP"])  [(PlayerEntity*)thisEnt disengageAutopilot];
		}
		else
		{
			[thisEnt addEquipmentItem:(hasOK ? damagedKey : key)];
			if (hasOK) [thisEnt doScriptEvent:@"equipmentDamaged" withArgument:key];
		}
	}
	
	*outResult = BOOLToJSVal(hasOK || hasDamaged);
	return YES;
}


// equipmentStatus(type : equipmentInfoExpression) : String
static JSBool ShipEquipmentStatus(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	// values returned: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED", @"EQUIPMENT_UNAVAILABLE"
	
	ShipEntity				*thisEnt = nil;
	NSString				*key = nil;
	NSString				*result = @"EQUIPMENT_UNAVAILABLE";
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	// stale reference, no-op.
	{
		*outResult = [result javaScriptValueInContext:context];
		return YES;
	}
	
	key = JSValueToEquipmentKey(context, argv[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"equipmentStatus", argc, argv, nil, @"equipment type");
		return NO;
	}
	
	if([thisEnt hasEquipmentItem:key]) result = @"EQUIPMENT_OK";
	else if([thisEnt hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]]) result = @"EQUIPMENT_DAMAGED";
	
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// selectNewMissile()
static JSBool ShipSelectNewMissile(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*result = @"EQ_MISSILE";
	
	if (JSShipGetShipEntity(context, this, &thisEnt))	// valid ship.
	{
		result = [[thisEnt selectMissile] identifier];
		// if there's a badly defined missile, selectMissile may return nil
		if (result == nil) result = @"EQ_MISSILE";
	}
	
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}


// fireMissile()
static JSBool ShipFireMissile(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity			*thisEnt = nil;
	id					result = nil;
	
	*outResult = [result javaScriptValueInContext:context];
	
	if (!JSShipGetShipEntity(context, this, &thisEnt) || [thisEnt isPlayer])	// stale reference, no-op, or player ship
	{
		return YES;
	}
	
	if (argc > 0) result = [thisEnt fireMissileWithIdentifier:JSValToNSString(context, argv[0]) andTarget:[thisEnt primaryTarget]];
	else result = [thisEnt fireMissile];
	
	*outResult = [result javaScriptValueInContext:context];
	return YES;
}

// setCargo(cargoType : String [, number : count])
static JSBool ShipSetCargo(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	NSString				*cargoType = nil;
	OOCargoType				commodity = CARGO_UNDEFINED;
	int32					count = 1;
	BOOL					gotCount = YES;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	cargoType = JSValToNSString(context, argv[0]);
	if (argc > 1)  gotCount = JS_ValueToInt32(context, argv[1], &count);
	if (EXPECT_NOT(cargoType == nil || !gotCount || count < 1))
	{
		OOReportJSBadArguments(context, @"Ship", @"setCargo", argc, argv, nil, @"cargo name and optional positive quantity");
		return NO;
	}
	
	commodity = [UNIVERSE commodityForName: cargoType];
	if (commodity != CARGO_UNDEFINED)  [thisEnt setCommodityForPod:commodity andAmount:count];
	
	*outResult = BOOLToJSVal(commodity != CARGO_UNDEFINED);
	return YES;
}


// setMaterials(params: dict,[shaders:dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static JSBool ShipSetMaterials(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	JSObject				*params = NULL;
	NSDictionary			*materials;
	NSDictionary			*shaders;
	BOOL					withShaders = NO;
	BOOL 					fromShaders = [@"setShaders" isEqualToString:JSValToNSString(context,*outResult)];
	
	*outResult = JSVAL_FALSE;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	// stale reference, no-op, or player ship
	{
		return YES;
	}
	
	if (JSVAL_IS_NULL(argv[0]) || (!JSVAL_IS_NULL(argv[0]) && !JSVAL_IS_OBJECT(argv[0])))
	{
		OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setMaterials", @"object", [NSString stringWithJavaScriptValue:argv[0] inContext:context]);
		return YES;
	}
	
	if (argc > 1)
	{
		withShaders = YES;
		if (JSVAL_IS_NULL(argv[1]) || (!JSVAL_IS_NULL(argv[1]) && !JSVAL_IS_OBJECT(argv[1])))
		{
			OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.",  @"setMaterials", @"object as second parameter", [NSString stringWithJavaScriptValue:argv[1] inContext:context]);
			withShaders = NO;
		}
	}
	
	if (fromShaders)
	{
		materials = [[thisEnt mesh] materials];
	}
	else
	{
		params = JSVAL_TO_OBJECT(argv[0]);
		materials = JSObjectToObject(context, params);
	}
	
	if (withShaders)
	{
		params = JSVAL_TO_OBJECT(argv[1]);
		shaders = JSObjectToObject(context, params);
	}
	else
	{
		shaders = [[thisEnt mesh] shaders];
	}
	
	NSDictionary 			*shipDict = [thisEnt shipInfoDictionary];

	// First we test to see if we can create the mesh.
	OOMesh *mesh = [OOMesh meshWithName:[shipDict oo_stringForKey:@"model"]
							   cacheKey:nil
					 materialDictionary:materials
					  shadersDictionary:shaders
								 smooth:[shipDict oo_boolForKey:@"smooth" defaultValue:NO]
						   shaderMacros:[[ResourceManager materialDefaults] oo_dictionaryForKey:@"ship-prefix-macros" defaultValue:[NSDictionary dictionary]]
					shaderBindingTarget:thisEnt];
	
	if (mesh == nil)
	{
		return YES;	// failed. Don't change the material.
	}
	
	[thisEnt setMesh:mesh];
	
	*outResult = JSVAL_TRUE;
	return YES;
}


// setShaders(params: dict) 
static JSBool ShipSetShaders(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity				*thisEnt = nil;
	
	*outResult = JSVAL_FALSE;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt))	// stale reference, no-op, or player ship
	{
		return YES;
	}
	
	if (JSVAL_IS_NULL(argv[0]) || (!JSVAL_IS_NULL(argv[0]) && !JSVAL_IS_OBJECT(argv[0])))
	{
		OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setShaders", @"object", [NSString stringWithJavaScriptValue:argv[0] inContext:context]);
		return YES;
	}
	
	// Now let's call setMaterials() with the appropriate parameters.
	argv[1] = argv[0];
	*outResult = [@"setShaders" javaScriptValueInContext:context];
	return ShipSetMaterials(context, this, 2, argv, outResult);
}


// exitSystem([int systemID])
static JSBool ShipExitSystem(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult)
{
	ShipEntity			*thisEnt = nil;
	int32				systemID = -1;
	BOOL				OK = NO;
	
	*outResult = BOOLToJSVal(OK);
	
	if (!JSShipGetShipEntity(context, this, &thisEnt) || [thisEnt isPlayer])	// stale reference, no-op, or player ship
	{
		return YES;
	}
	
	if (argc > 0)
	{
		if (!JS_ValueToInt32(context, argv[0], &systemID) || systemID < 0 || 255 < systemID)
		{
			OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"exitSystem", @"system ID",[NSString stringWithJavaScriptValue:argv[0] inContext:context]);
			return NO;
		}
	}
	
	OK = [thisEnt performHyperSpaceToSpecificSystem:systemID]; 	// -1 == random destination system
	
	*outResult = BOOLToJSVal(OK);

	return YES;
}


static BOOL RemoveOrExplodeShip(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult, BOOL explode)
{
	ShipEntity				*thisEnt = nil;
	
	if (!JSShipGetShipEntity(context, this, &thisEnt)) return YES;	// stale reference, no-op.
	
	if ([thisEnt isPlayer])
	{
		PlayerEntity *player = (PlayerEntity *)thisEnt;
		assert(explode);	// Handled by caller.
		
		if ([player isDocked])
		{
			OOReportJSError(context, @"Cannot explode() player's ship while docked.");
			return NO;
		}
	}
	
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


static BOOL ValidateContracts(JSContext *context, JSObject *this, uintN argc, jsval *argv, jsval *outResult, BOOL isCargo)
{
	unsigned		offset = isCargo ? 2 : 1;
	NSString		*functionName = isCargo ? @"awardContract" : @"addPassenger";
	jsdouble		fValue;
	
	if (!JSVAL_IS_INT(argv[offset]) || JSVAL_TO_INT(argv[offset]) > 255 || JSVAL_TO_INT(argv[offset]) < 0)
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc, argv, nil, @"start:system ID");
		return NO;
	}
	if (!JSVAL_IS_INT(argv[offset + 1]) || JSVAL_TO_INT(argv[offset +1]) > 255 || JSVAL_TO_INT(argv[offset +1]) < 0)
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc, argv, nil, @"destination:system ID");
		return NO;
	}
	if(!JS_ValueToNumber(context, argv[offset + 2], &fValue) || fValue <= [[PlayerEntity sharedPlayer] clockTime])
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc, argv, nil, @"eta:future time");
		return NO;
	}
	if (!JS_ValueToNumber(context, argv[offset + 3], &fValue) || fValue <= 0.0)
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc, argv, nil, @"fee:credits");
		return NO;
	}
	
	return YES;
}
