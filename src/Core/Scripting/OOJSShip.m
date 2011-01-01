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
#import "Entity.h"
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


static JSObject *sShipPrototype;


static JSBool ShipGetProperty(OOJS_PROP_ARGS);
static JSBool ShipSetProperty(OOJS_PROP_ARGS);

static JSBool ShipSetScript(OOJS_NATIVE_ARGS);
static JSBool ShipSetAI(OOJS_NATIVE_ARGS);
static JSBool ShipSwitchAI(OOJS_NATIVE_ARGS);
static JSBool ShipExitAI(OOJS_NATIVE_ARGS);
static JSBool ShipReactToAIMessage(OOJS_NATIVE_ARGS);
static JSBool ShipSendAIMessage(OOJS_NATIVE_ARGS);
static JSBool ShipDeployEscorts(OOJS_NATIVE_ARGS);
static JSBool ShipDockEscorts(OOJS_NATIVE_ARGS);
static JSBool ShipHasRole(OOJS_NATIVE_ARGS);
static JSBool ShipEjectItem(OOJS_NATIVE_ARGS);
static JSBool ShipEjectSpecificItem(OOJS_NATIVE_ARGS);
static JSBool ShipDumpCargo(OOJS_NATIVE_ARGS);
static JSBool ShipSpawn(OOJS_NATIVE_ARGS);
static JSBool ShipExplode(OOJS_NATIVE_ARGS);
static JSBool ShipRemove(OOJS_NATIVE_ARGS);
static JSBool ShipRunLegacyScriptActions(OOJS_NATIVE_ARGS);
static JSBool ShipCommsMessage(OOJS_NATIVE_ARGS);
static JSBool ShipFireECM(OOJS_NATIVE_ARGS);
static JSBool ShipAbandonShip(OOJS_NATIVE_ARGS);
static JSBool ShipAddPassenger(OOJS_NATIVE_ARGS);
static JSBool ShipAwardContract(OOJS_NATIVE_ARGS);
static JSBool ShipCanAwardEquipment(OOJS_NATIVE_ARGS);
static JSBool ShipAwardEquipment(OOJS_NATIVE_ARGS);
static JSBool ShipRemoveEquipment(OOJS_NATIVE_ARGS);
static JSBool ShipRemovePassenger(OOJS_NATIVE_ARGS);
static JSBool ShipRestoreSubEntities(OOJS_NATIVE_ARGS);
static JSBool ShipEquipmentStatus(OOJS_NATIVE_ARGS);
static JSBool ShipSetEquipmentStatus(OOJS_NATIVE_ARGS);
static JSBool ShipSelectNewMissile(OOJS_NATIVE_ARGS);
static JSBool ShipFireMissile(OOJS_NATIVE_ARGS);
static JSBool ShipSetCargo(OOJS_NATIVE_ARGS);
static JSBool ShipSetMaterials(OOJS_NATIVE_ARGS);
static JSBool ShipSetShaders(OOJS_NATIVE_ARGS);
static JSBool ShipExitSystem(OOJS_NATIVE_ARGS);

static BOOL RemoveOrExplodeShip(OOJS_NATIVE_ARGS, BOOL explode);
static BOOL ValidateContracts(OOJS_NATIVE_ARGS, BOOL isCargo);
static JSBool ShipSetMaterialsInternal(OOJS_NATIVE_ARGS, ShipEntity *thisEnt, BOOL fromShaders);


static JSClass sShipClass =
{
	"Ship",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,		// addProperty
	JS_PropertyStub,		// delProperty
	ShipGetProperty,		// getProperty
	ShipSetProperty,		// setProperty
	JS_EnumerateStub,		// enumerate
	JS_ResolveStub,			// resolve
	JS_ConvertStub,			// convert
	JSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
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
	kShip_cruiseSpeed,			// desired cruising speed, number, read only
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
	kShip_hasHyperspaceMotor,	// has hyperspace motor, boolean, read-only
	kShip_hasSuspendedAI,		// AI has suspended states, boolean, read-only
	kShip_heading,				// forwardVector of a ship, read-only
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
	kShip_isPiloted,			// is piloted, boolean, read-only (includes stations)
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
	kShip_missileLoadTime,		// missile load time, double, read/write
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
	kShip_subEntityCapacity,	// max subentities for this ship, int, read-only
	kShip_target,				// target, Ship, read/write
	kShip_temperature,			// hull temperature, double, read/write
	kShip_thrust,				// the ship's thrust, double, read/write
	kShip_thrustVector,			// thrust-related component of velocity, vector, read-only
	kShip_trackCloseContacts,	// generate close contact events, boolean, read/write
	kShip_vectorForward,		// forwardVector of a ship, read-only
	kShip_vectorRight,			// rightVector of a ship, read-only
	kShip_vectorUp,				// upVector of a ship, read-only
	kShip_velocity,				// velocity, vector, read/write
	kShip_weaponRange,			// weapon range, double, read-only
	kShip_withinStationAegis,	// within main station aegis, boolean, read/write
};


static JSPropertySpec sShipProperties[] =
{
	// JS name					ID							flags
	{ "aftWeapon",				kShip_aftWeapon,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "AI",						kShip_AI,					JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "AIState",				kShip_AIState,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "beaconCode",				kShip_beaconCode,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "bounty",					kShip_bounty,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "cargoSpaceUsed",			kShip_cargoSpaceUsed,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cargoSpaceCapacity",		kShip_cargoSpaceCapacity,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cargoSpaceAvailable",	kShip_cargoSpaceAvailable,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	// contracts instead of cargo to distinguish them from the manifest
	{ "contracts",				kShip_contracts,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "cruiseSpeed",			kShip_cruiseSpeed,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "desiredSpeed",			kShip_desiredSpeed,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "displayName",			kShip_displayName,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "entityPersonality",		kShip_entityPersonality,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "equipment",				kShip_equipment,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "escorts",				kShip_escorts,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "escortGroup",			kShip_escortGroup,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "forwardWeapon",			kShip_forwardWeapon,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "fuel",					kShip_fuel,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "fuelChargeRate",			kShip_fuelChargeRate,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "group",					kShip_group,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "hasHostileTarget",		kShip_hasHostileTarget,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasHyperspaceMotor",		kShip_hasHyperspaceMotor,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "hasSuspendedAI",			kShip_hasSuspendedAI,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "heatInsulation",			kShip_heatInsulation,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "heading",				kShip_heading,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isBeacon",				kShip_isBeacon,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isCloaked",				kShip_isCloaked,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isCargo",				kShip_isCargo,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isDerelict",				kShip_isDerelict,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isFrangible",			kShip_isFrangible,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isJamming",				kShip_isJamming,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isMine",					kShip_isMine,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isMissile",				kShip_isMissile,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPiloted",				kShip_isPiloted,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPirate",				kShip_isPirate,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPirateVictim",			kShip_isPirateVictim,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPlayer",				kShip_isPlayer,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isPolice",				kShip_isPolice,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isRock",					kShip_isRock,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isBoulder",				kShip_isBoulder,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "isThargoid",				kShip_isThargoid,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isTrader",				kShip_isTrader,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "isWeapon",				kShip_isWeapon,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "lightsActive",			kShip_lightsActive,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "maxSpeed",				kShip_maxSpeed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "maxThrust",				kShip_maxThrust,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "missileCapacity",		kShip_missileCapacity,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "missileLoadTime",		kShip_missileLoadTime,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "missiles",				kShip_missiles,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "name",					kShip_name,					JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "passengerCount",			kShip_passengerCount,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "passengerCapacity",		kShip_passengerCapacity,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "passengers",				kShip_passengers,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "portWeapon",				kShip_portWeapon,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "potentialCollider",		kShip_potentialCollider,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "primaryRole",			kShip_primaryRole,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "reportAIMessages",		kShip_reportAIMessages,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "roleProbabilities",		kShip_roleProbabilities,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "roles",					kShip_roles,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "savedCoordinates",		kShip_savedCoordinates,		JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scannerDisplayColor1",	kShip_scannerDisplayColor1,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scannerDisplayColor2",	kShip_scannerDisplayColor2,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "scannerRange",			kShip_scannerRange,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "script",					kShip_script,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "scriptInfo",				kShip_scriptInfo,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "speed",					kShip_speed,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "starboardWeapon",		kShip_starboardWeapon,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "subEntities",			kShip_subEntities,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "subEntityCapacity",		kShip_subEntityCapacity,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "target",					kShip_target,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "temperature",			kShip_temperature,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "thrust",					kShip_thrust,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "thrustVector",			kShip_thrustVector,			JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "trackCloseContacts",		kShip_trackCloseContacts,	JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "vectorForward",			kShip_vectorForward,		JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "vectorRight",			kShip_vectorRight,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "vectorUp",				kShip_vectorUp,				JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "velocity",				kShip_velocity,				JSPROP_PERMANENT | JSPROP_ENUMERATE },
	{ "weaponRange",			kShip_weaponRange,			JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
	{ "withinStationAegis",		kShip_withinStationAegis,	JSPROP_PERMANENT | JSPROP_ENUMERATE | JSPROP_READONLY },
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
	{ "removePassenger",		ShipRemovePassenger,		1 },	// Documented as PlayerShip
	{ "restoreSubEntities",		ShipRestoreSubEntities,		0 },
	{ "runLegacyScriptActions",	ShipRunLegacyScriptActions,	2 },	// Deliberately not documented
	{ "selectNewMissile",		ShipSelectNewMissile,		0 },
	{ "sendAIMessage",			ShipSendAIMessage,			1 },
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


DEFINE_JS_OBJECT_GETTER(JSShipGetShipEntity, &sShipClass, sShipPrototype, ShipEntity)


void InitOOJSShip(JSContext *context, JSObject *global)
{
	sShipPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sShipClass, NULL, 0, sShipProperties, sShipMethods, NULL, NULL);
	JSRegisterObjectConverter(&sShipClass, JSBasicPrivateObjectConverter);
	OOJSRegisterSubclass(&sShipClass, JSEntityClass());
}


JSClass *JSShipClass(void)
{
	return &sShipClass;
}


JSObject *JSShipPrototype(void)
{
	return sShipPrototype;
}


static JSBool ShipGetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	BOOL						OK = NO;
	ShipEntity					*entity = nil;
	id							result = nil;
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))  return NO;
	if (OOIsStaleEntity(entity)) { *value = JSVAL_VOID; return YES; }
	if (EXPECT_NOT(!JS_EnterLocalRootScope(context)))  return NO;
	
	switch (OOJS_PROPID_INT)
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
			OK = JS_NewDoubleValue(context, [entity fuel] * 0.1, value);
			break;
			
		case kShip_fuelChargeRate:
			OK = JS_NewDoubleValue(context, [entity fuelChargeRate], value);
			break;
			
		case kShip_bounty:
			*value = INT_TO_JSVAL([entity bounty]);
			OK = YES;
			break;
			
		case kShip_subEntities:
			result = [entity subEntitiesForScript];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShip_subEntityCapacity:
			*value = INT_TO_JSVAL([entity maxShipSubEntities]);
			OK = YES;
			break;
			
		case kShip_hasSuspendedAI:
			*value = BOOLToJSVal([[entity getAI] hasSuspendedStateMachines]);
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
			OK = JS_NewDoubleValue(context, [entity temperature] / SHIP_MAX_CABIN_TEMP, value);
			break;
			
		case kShip_heatInsulation:
			OK = JS_NewDoubleValue(context, [entity heatInsulation], value);
			break;
			
		case kShip_heading:
			OK = VectorToJSValue(context, [entity forwardVector], value);
			break;
			
		case kShip_entityPersonality:
			*value = INT_TO_JSVAL([entity entityPersonalityInt]);
			OK = YES;
			break;
			
		case kShip_isBeacon:
			*value = BOOLToJSVal([entity isBeacon]);
			OK = YES;
			break;
			
		case kShip_beaconCode:
			result = [entity beaconCode];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_isFrangible:
			*value = BOOLToJSVal([entity isFrangible]);
			OK = YES;
			break;
		
		case kShip_isCloaked:
			*value = BOOLToJSVal([entity isCloaked]);
			OK = YES;
			break;
			
		case kShip_isJamming:
			*value = BOOLToJSVal([entity isJammingScanning]);
			OK = YES;
			break;
		
		case kShip_potentialCollider:
			result = [entity proximity_alert];
			if (result == nil)  result = [NSNull null];
			break;
		
		case kShip_hasHostileTarget:
			*value = BOOLToJSVal([entity hasHostileTarget]);
			OK = YES;
			break;
		
		case kShip_hasHyperspaceMotor:
			*value = BOOLToJSVal([entity hasHyperspaceMotor]);
			OK = YES;
			break;
		
		case kShip_weaponRange:
			OK = JS_NewDoubleValue(context, [entity weaponRange], value);
			break;
		
		case kShip_scannerRange:
			OK = JS_NewDoubleValue(context, [entity scannerRange], value);
			break;
		
		case kShip_reportAIMessages:
			*value = BOOLToJSVal([entity reportAIMessages]);
			OK = YES;
			break;
		
		case kShip_withinStationAegis:
			*value = BOOLToJSVal([entity withinStationAegis]);
			OK = YES;
			break;
			
		case kShip_cargoSpaceCapacity:
			*value = INT_TO_JSVAL([entity maxCargo]);
			OK = YES;
			break;
			
		case kShip_cargoSpaceUsed:
			*value = INT_TO_JSVAL([entity maxCargo] - [entity availableCargoSpace]);
			OK = YES;
			break;
			
		case kShip_cargoSpaceAvailable:
			*value = INT_TO_JSVAL([entity availableCargoSpace]);
			OK = YES;
			break;
			
		case kShip_speed:
			OK = JS_NewDoubleValue(context, [entity flightSpeed], value);
			break;
			
		case kShip_cruiseSpeed:
			OK = JS_NewDoubleValue(context, [entity cruiseSpeed], value);
			break;
			
		case kShip_desiredSpeed:
			OK = JS_NewDoubleValue(context, [entity desiredSpeed], value);
			break;
			
		case kShip_maxSpeed:
			OK = JS_NewDoubleValue(context, [entity maxFlightSpeed], value);
			break;
			
		case kShip_script:
			result = [entity shipScript];
			if (result == nil)  result = [NSNull null];
			break;
			
		case kShip_isPirate:
			*value = BOOLToJSVal([entity isPirate]);
			OK = YES;
			break;
			
		case kShip_isPlayer:
			*value = BOOLToJSVal([entity isPlayer]);
			OK = YES;
			break;
			
		case kShip_isPolice:
			*value = BOOLToJSVal([entity isPolice]);
			OK = YES;
			break;
			
		case kShip_isThargoid:
			*value = BOOLToJSVal([entity isThargoid]);
			OK = YES;
			break;
			
		case kShip_isTrader:
			*value = BOOLToJSVal([entity isTrader]);
			OK = YES;
			break;
			
		case kShip_isPirateVictim:
			*value = BOOLToJSVal([entity isPirateVictim]);
			OK = YES;
			break;
			
		case kShip_isMissile:
			*value = BOOLToJSVal([entity isMissile]);
			OK = YES;
			break;
			
		case kShip_isMine:
			*value = BOOLToJSVal([entity isMine]);
			OK = YES;
			break;
			
		case kShip_isWeapon:
			*value = BOOLToJSVal([entity isWeapon]);
			OK = YES;
			break;
			
		case kShip_isRock:
			*value = BOOLToJSVal([entity scanClass] == CLASS_ROCK);	// hermits and asteroids!
			OK = YES;
			break;
			
		case kShip_isBoulder:
			*value = BOOLToJSVal([entity isBoulder]);
			OK = YES;
			break;
			
		case kShip_isCargo:
			*value = BOOLToJSVal([entity scanClass] == CLASS_CARGO && [entity commodityAmount] > 0);
			OK = YES;
			break;
			
		case kShip_isDerelict:
			*value = BOOLToJSVal([entity isHulk]);
			OK = YES;
			break;
			
		case kShip_isPiloted:
			*value = BOOLToJSVal([entity isPlayer] || [[entity crew] count] > 0);
			OK = YES;
			break;
			
		case kShip_scriptInfo:
			result = [entity scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than undefined
			break;
			
		case kShip_trackCloseContacts:
			*value = BOOLToJSVal([entity trackCloseContacts]);
			OK = YES;
			break;
			
		case kShip_passengerCount:
			*value = INT_TO_JSVAL([entity passengerCount]);
			OK = YES;
			break;
			
		case kShip_passengerCapacity:
			*value = INT_TO_JSVAL([entity passengerCapacity]);
			OK = YES;
			break;

		case kShip_missileCapacity:
			*value = INT_TO_JSVAL([entity missileCapacity]);
			OK = YES;
			break;
			
		case kShip_missileLoadTime:
			OK = JS_NewDoubleValue(context, [entity missileLoadTime], value);
			break;
		
		case kShip_savedCoordinates:
			OK = VectorToJSValue(context, [entity coordinates], value);
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
			OK = JS_NewDoubleValue(context, [entity maxThrust], value);
			break;
			
		case kShip_thrust:
			OK = JS_NewDoubleValue(context, [entity thrust], value);
			break;
			
		case kShip_lightsActive:
			*value = BOOLToJSVal([entity lightsActive]);
			OK = YES;
			break;
			
		case kShip_vectorRight:
			OK = VectorToJSValue(context, [entity rightVector], value);
			break;
			
		case kShip_vectorForward:
			OK = VectorToJSValue(context, [entity forwardVector], value);
			break;
			
		case kShip_vectorUp:
			OK = VectorToJSValue(context, [entity upVector], value);
			break;
			
		case kShip_velocity:
			OK = VectorToJSValue(context, [entity velocity], value);
			break;
			
		case kShip_thrustVector:
			OK = VectorToJSValue(context, [entity thrustVector], value);
			break;
			
		default:
			OOReportJSBadPropertySelector(context, @"Ship", OOJS_PROPID_INT);
	}
	
	if (result != nil)
	{
		*value = [result javaScriptValueInContext:context];
		OK = YES;
	}
	JS_LeaveLocalRootScope(context);
	return OK;
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipSetProperty(OOJS_PROP_ARGS)
{
	if (!OOJS_PROPID_IS_INT)  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
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
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity))) return NO;
	if (OOIsStaleEntity(entity))  return YES;
	
	switch (OOJS_PROPID_INT)
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
			
		case kShip_missileLoadTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				if (fValue < 0.0)
				{
					OOReportJSError(context, @"Ship.%@ [setter]: cannot set negative missile load time (%fs).", @"missileLoadTime", fValue);
				}
				else
				{
					[entity setMissileLoadTime:fValue];
					OK = YES;
				}
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
			OOReportJSBadPropertySelector(context, @"Ship", OOJS_PROPID_INT);
	}
	if (OK == NO)
	{
		OOReportJSWarning(context, @"Invalid value type for this property. Value not set.");
	}
	return YES;
	
	OOJS_NATIVE_EXIT
}


// *** Methods ***

#define GET_THIS_SHIP(THISENT) do { \
	if (EXPECT_NOT(!JSShipGetShipEntity(context, OOJS_THIS, &THISENT)))  return NO; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID; \
} while (0)


// setScript(scriptName : String)
static JSBool ShipSetScript(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	name = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setScript", argc, OOJS_ARGV, nil, @"script name");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"setScript", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt setShipScript:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setAI(aiName : String)
static JSBool ShipSetAI(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	name = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setAI", argc, OOJS_ARGV, nil, @"AI name");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"setAI", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt setAITo:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// switchAI(aiName : String)
static JSBool ShipSwitchAI(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	name = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(name == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"switchAI", argc, OOJS_ARGV, nil, @"AI name");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"switchAI", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt switchAITo:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// exitAI()
static JSBool ShipExitAI(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	AI						*thisAI = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"exitAI", @"Not valid for player ship.");
		return NO;
	}
	thisAI = [thisEnt getAI];
	
	if (argc > 0)
	{
		message = JSValToNSString(context, OOJS_ARG(0));
	}
	
	if (![thisAI hasSuspendedStateMachines])
	{
		OOReportJSWarningForCaller(context, @"Ship", @"exitAI()", @"Cannot exit current AI state machine because there are no suspended state machines.");
	}
	else
	{
		[thisAI exitStateMachineWithMessage:message];
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// reactToAIMessage(message : String)
static JSBool ShipReactToAIMessage(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	message = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(message == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"reactToAIMessage", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"reactToAIMessage", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt reactToAIMessage:message context:@"JavaScript reactToAIMessage()"];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// sendAIMessage(message : String)
static JSBool ShipSendAIMessage(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	message = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(message == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"sendAIMessage", argc, OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"sendAIMessage", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt sendAIMessage:message];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// deployEscorts()
static JSBool ShipDeployEscorts(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	[thisEnt deployEscorts];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// dockEscorts()
static JSBool ShipDockEscorts(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	[thisEnt dockEscorts];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// hasRole(role : String) : Boolean
static JSBool ShipHasRole(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	role = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"hasRole", argc, OOJS_ARGV, nil, @"role");
		return NO;
	}
	
	OOJS_RETURN_BOOL([thisEnt hasRole:role]);
	
	OOJS_NATIVE_EXIT
}


// ejectItem(role : String) : Ship
static JSBool ShipEjectItem(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	role = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(role == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"ejectItem", argc, OOJS_ARGV, nil, @"role");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([thisEnt ejectShipOfRole:role]);
	
	OOJS_NATIVE_EXIT
}


// ejectSpecificItem(itemKey : String) : Ship
static JSBool ShipEjectSpecificItem(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*itemKey = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	itemKey = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(itemKey == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"ejectSpecificItem", argc, OOJS_ARGV, nil, @"ship key");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([thisEnt ejectShipOfType:itemKey]);
	
	OOJS_NATIVE_EXIT
}


// dumpCargo() : Ship
static JSBool ShipDumpCargo(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	
	if (EXPECT_NOT([thisEnt isPlayer] && [(PlayerEntity *)thisEnt isDocked]))
	{
		OOReportJSWarningForCaller(context, @"PlayerShip", @"dumpCargo", @"Can't dump cargo while docked, ignoring.");
		OOJS_RETURN_NULL;
	}
	
	OOJS_RETURN_OBJECT([thisEnt dumpCargoItem]);
	
	OOJS_NATIVE_EXIT
}


// spawn(role : String [, number : count]) : Array
static JSBool ShipSpawn(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	int32					count = 1;
	BOOL					gotCount = YES;
	NSArray					*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	role = JSValToNSString(context, OOJS_ARG(0));
	if (argc > 1)  gotCount = JS_ValueToInt32(context, OOJS_ARG(1), &count);
	if (EXPECT_NOT(role == nil || !gotCount || count < 1 || count > 64))
	{
		OOReportJSBadArguments(context, @"Ship", @"spawn", argc, OOJS_ARGV, nil, @"role and optional quantity (1 to 64)");
		return NO;
	}
	
	OOJSPauseTimeLimiter();
	result = [thisEnt spawnShipsWithRole:role count:count];
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// explode()
static JSBool ShipExplode(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	return RemoveOrExplodeShip(OOJS_NATIVE_CALLTHROUGH, YES);
	
	OOJS_NATIVE_EXIT
}


// remove([suppressDeathEvent : Boolean = false])
static JSBool ShipRemove(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	JSBool					suppressDeathEvent = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if ([thisEnt isPlayer])
	{
		OOReportJSError(context, @"Cannot remove() player's ship.");
		return NO;
	}
	
	if ( argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARG(0), &suppressDeathEvent)))
	{
		OOReportJSBadArguments(context, @"Ship", @"remove", argc, OOJS_ARGV, nil, @"boolean");
		return NO;
	}

	[thisEnt doScriptEvent:@"shipRemoved" withArgument:[NSNumber numberWithBool:suppressDeathEvent]];

	if (suppressDeathEvent)
	{
		[thisEnt removeScript];
	}
	return RemoveOrExplodeShip(OOJS_NATIVE_CALLTHROUGH, NO);
	
	OOJS_NATIVE_EXIT
}


// runLegacyShipActions(target : Ship, actions : Array)
static JSBool ShipRunLegacyScriptActions(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	PlayerEntity			*player = nil;
	ShipEntity				*target = nil;
	NSArray					*actions = nil;
	
	player = OOPlayerForScripting();
	GET_THIS_SHIP(thisEnt);
	
	actions = JSValueToObject(context, OOJS_ARG(1));
	if (EXPECT_NOT(!JSVAL_IS_OBJECT(OOJS_ARG(0)) ||
				   !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARG(0)), &target) ||
				   ![actions isKindOfClass:[NSArray class]]))
	{
		OOReportJSBadArguments(context, @"Ship", @"runLegacyScriptActions", argc, OOJS_ARGV, nil, @"target and array of actions");
		return NO;
	}
	
	if (target != nil)	// Not stale reference
	{
		[player setScriptTarget:thisEnt];
		[player runUnsanitizedScriptActions:actions
						  allowingAIMethods:YES
							withContextName:[NSString stringWithFormat:@"<ship \"%@\" legacy actions>", [thisEnt name]]
								  forTarget:target];
	}
	
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// commsMessage(message : String[,target : Ship])
static JSBool ShipCommsMessage(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	ShipEntity				*target = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	message = JSValToNSString(context, OOJS_ARG(0));
	if (EXPECT_NOT(message == nil)|| ( argc > 1 && EXPECT_NOT(!JSVAL_IS_OBJECT(OOJS_ARG(1)) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARG(1)), &target))))
	{
		OOReportJSBadArguments(context, @"Ship", @"commsMessage", argc, OOJS_ARGV, nil, @"message and optional target");
		return NO;
	}
	
	if (argc < 2)
	{
		[thisEnt commsMessage:message withUnpilotedOverride:YES];	// generic broadcast
	}
	else if (target != nil)  // Not stale reference
	{
		[thisEnt sendMessage:message toShip:target withUnpilotedOverride:YES];	// ship-to-ship narrowcast
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// fireECM()
static JSBool ShipFireECM(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	BOOL					OK;
	
	GET_THIS_SHIP(thisEnt);
	
	OK = [thisEnt fireECM];
	if (!OK)
	{
		OOReportJSWarning(context, @"Ship %@ was requested to fire ECM burst but does not carry ECM equipment.", thisEnt);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// abandonShip()
static JSBool ShipAbandonShip(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	OOJS_RETURN_BOOL([thisEnt hasEscapePod] && [thisEnt abandonShip]);
	
	OOJS_NATIVE_EXIT
}


// addPassenger(name: string, start: int, destination: int, eta: double, fee: double)
static JSBool ShipAddPassenger(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	BOOL				OK = YES;
	NSString			*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc == 5)
	{
		name = JSValToNSString(context, OOJS_ARG(0));
		if (EXPECT_NOT(name == nil || JSVAL_IS_INT(OOJS_ARG(0))))
		{
			OOReportJSBadArguments(context, @"Ship", @"addPassenger", argc, OOJS_ARGV, nil, @"name:string");
			return NO;
		}
		OK = ValidateContracts(OOJS_NATIVE_CALLTHROUGH, NO);
		if (!OK) return NO;
		
		if (![thisEnt isPlayer] || [thisEnt passengerCount] >= [thisEnt passengerCapacity])
		{
			OOReportJSWarning(context, @"Ship.%@(): cannot %@.", @"addPassenger", @"add passenger");
			OK = NO;
		}
	}
	else
	{
		OOReportJSBadArguments(context, @"Ship", @"addPassenger", argc, OOJS_ARGV, nil, @"name, start, destination, eta, fee");
		return NO;
	}
	
	if (OK)
	{
		jsdouble		eta,fee;
		JS_ValueToNumber(context, OOJS_ARG(3), &eta);
		JS_ValueToNumber(context, OOJS_ARG(4), &fee);
		OK = [(PlayerEntity*)thisEnt addPassenger:name start:JSVAL_TO_INT(OOJS_ARG(1)) destination:JSVAL_TO_INT(OOJS_ARG(2)) eta:eta fee:fee];
		if (!OK) OOReportJSWarning(context, @"Ship.%@(): cannot %@.", @"addPassenger", @"add passenger. Duplicate name perhaps?");
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// awardContract(quantity: int, commodity: string, start: int, destination: int, eta: double, fee: double)
static JSBool ShipAwardContract(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	BOOL				OK = JSVAL_IS_INT(OOJS_ARG(0));
	NSString 			*key = nil;
	int 				qty = 0;
	
	GET_THIS_SHIP(thisEnt);
	
	if (OK && argc == 6)
	{
		key = JSValToNSString(context, OOJS_ARG(1));
		if (EXPECT_NOT(key == nil || !JSVAL_IS_STRING(OOJS_ARG(1))))
		{
			OOReportJSBadArguments(context, @"Ship", @"awardContract", argc, OOJS_ARGV, nil, @"commodity identifier:string");
			return NO;
		}
		OK = ValidateContracts(OOJS_NATIVE_CALLTHROUGH, YES); // always go through validate contracts (cargo)
		if (!OK) return NO;
		
		qty = JSVAL_TO_INT(OOJS_ARG(0));
		
		if (![thisEnt isPlayer] || qty < 1)
		{
			OOReportJSWarning(context, @"Ship.%@(): cannot %@.", @"awardContract", @"award contract");
			OK = NO;
		}
	}
	else
	{
		if (argc == 6) 
		{
			OOReportJSBadArguments(context, @"Ship", @"awardContract", argc, OOJS_ARGV, nil, @"quantity:int");
		}
		else
		{
			OOReportJSBadArguments(context, @"Ship", @"awardContract", argc, OOJS_ARGV, nil, @"quantity, commodity, start, destination, eta, fee");
		}
		return NO;
	}
	
	if (OK)
	{
		jsdouble		eta,fee;
		JS_ValueToNumber(context, OOJS_ARG(4), &eta);
		JS_ValueToNumber(context, OOJS_ARG(5), &fee);
		// commodity key is case insensitive.
		OK = [(PlayerEntity*)thisEnt awardContract:qty commodity:key 
									start:JSVAL_TO_INT(OOJS_ARG(2)) destination:JSVAL_TO_INT(OOJS_ARG(3)) eta:eta fee:fee];
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// canAwardEquipment(type : equipmentInfoExpression)
static JSBool ShipCanAwardEquipment(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	OOEquipmentType				*eqType = nil;
	BOOL						result;
	BOOL						isBerth;
	BOOL						exists;
	
	GET_THIS_SHIP(thisEnt);
	
	key = JSValueToEquipmentKeyRelaxed(context, OOJS_ARG(0), &exists);
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"canAwardEquipment", argc, OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	
	if (exists)
	{
		eqType = [OOEquipmentType equipmentTypeWithIdentifier:key];
		result = YES;
		
		isBerth = [key isEqualToString:@"EQ_PASSENGER_BERTH"];
		// can't add fuel as equipment, can add multiple berths if there's space.
		if ([key isEqualToString:@"EQ_FUEL"])  result = NO;
		
		if (result)  result = [thisEnt canAddEquipment:key];
	}
	else
	{
		// Unknown type.
		result = NO;
	}
	
	OOJS_RETURN_BOOL(result);
	
	OOJS_NATIVE_EXIT
}


// awardEquipment(type : equipmentInfoExpression)
static JSBool ShipAwardEquipment(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	OOEquipmentType				*eqType = nil;
	NSString					*identifier = nil;
	BOOL						OK = YES;
	BOOL						berth;
	
	GET_THIS_SHIP(thisEnt);
	
	eqType = JSValueToEquipmentType(context, OOJS_ARG(0));
	if (EXPECT_NOT(eqType == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"awardEquipment", argc, OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	
	// Check that equipment is permitted.
	identifier = [eqType identifier];
	berth = [identifier isEqualToString:@"EQ_PASSENGER_BERTH"];
	if (berth)
	{
		OK = [thisEnt availableCargoSpace] >= [eqType requiredCargoSpace];
	}
	else if ([identifier isEqualToString:@"EQ_FUEL"])
	{
		OK = NO;
	}
	else
	{
		OK = [eqType canCarryMultiple] || ![thisEnt hasEquipmentItem:identifier];
	}
	
	if (OK)
	{
		if ([thisEnt isPlayer])
		{
			PlayerEntity *player = (PlayerEntity *)thisEnt;
			
			if ([identifier isEqualToString:@"EQ_MISSILE_REMOVAL"])
			{
				[player removeMissiles];
			}
			else if ([eqType isMissileOrMine])
			{
				OK = [player mountMissileWithRole:identifier];
			}
			else if (berth)
			{
				OK = [player changePassengerBerths: +1];
			}
			else if ([identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
			{
				OK = [player changePassengerBerths: -1];
			}
			else
			{
				OK = [player addEquipmentItem:identifier];
			}
		}
		else
		{
			if ([identifier isEqualToString:@"EQ_MISSILE_REMOVAL"])
			{
				[thisEnt removeMissiles];
			}
			// no passenger handling for NPCs. EQ_CARGO_BAY is dealt with inside addEquipmentItem
			else if (!berth && ![identifier isEqualToString:@"EQ_PASSENGER_BERTH_REMOVAL"])
			{
				OK = [thisEnt addEquipmentItem:identifier];	
			}
			else
			{
				OK = NO;
			}
		}
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removeEquipment(type : equipmentInfoExpression)
static JSBool ShipRemoveEquipment(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						OK = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	key = JSValueToEquipmentKey(context, OOJS_ARG(0));
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"removeEquipment", argc, OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	// berths are not in hasOneEquipmentItem
	OK = [thisEnt hasOneEquipmentItem:key includeMissiles:YES] || ([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [thisEnt passengerCapacity] > 0);
	if (!OK)
	{
		// Allow removal of damaged equipment.
		key = [key stringByAppendingString:@"_DAMAGED"];
		OK = [thisEnt hasOneEquipmentItem:key includeMissiles:NO];
	}
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
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// removePassenger(name :string)
static JSBool ShipRemovePassenger(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						OK = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (EXPECT_NOT(!JSVAL_IS_STRING(OOJS_ARG(0))))
	{
		OOReportJSBadArguments(context, @"Ship", @"removePassenger", argc, OOJS_ARGV, nil, @"name");
		return NO;
	}
	
	key = JSValToNSString(context, OOJS_ARG(0));
	OK = [thisEnt passengerCount] > 0 && [key length] > 0;
	
	if (OK)
	{
		// must be the player's ship!
		if ([thisEnt isPlayer]) OK = [(PlayerEntity*)thisEnt removePassenger:key];
		else OK = NO;
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// restoreSubEntities()
static JSBool ShipRestoreSubEntities(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	OOUInteger subCount = [[thisEnt subEntitiesForScript] count];
	
	[thisEnt clearSubEntities];
	[thisEnt setUpSubEntities];
	
	OOJS_RETURN_BOOL([[thisEnt subEntitiesForScript] count] - subCount > 0);
	
	OOJS_NATIVE_EXIT
}



// setEquipmentStatus(type : equipmentInfoExpression, status : String)
static JSBool ShipSetEquipmentStatus(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	// equipment status accepted: @"EQUIPMENT_OK", @"EQUIPMENT_DAMAGED"
	
	ShipEntity				*thisEnt = nil;
	OOEquipmentType			*eqType = nil;
	NSString				*key = nil;
	NSString				*damagedKey = nil;
	NSString				*status = nil;
	BOOL					hasOK = NO, hasDamaged = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (EXPECT_NOT([UNIVERSE strict]))
	{
		// It's OK to have a hard error here since only built-in scripts run in strict mode.
		OOReportJSError(context, @"Cannot set equipment status while in strict mode.");
		return NO;
	}
	
	eqType = JSValueToEquipmentType(context, OOJS_ARG(0));
	if (EXPECT_NOT(eqType == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setEquipmentStatus", argc, OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	
	status = JSValToNSString(context, OOJS_ARG(1));
	if (EXPECT_NOT(status == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"setEquipmentStatus", argc - 1, OOJS_ARGV + 1, nil, @"equipment status");
		return NO;
	}
	
	if (![status isEqualToString:@"EQUIPMENT_OK"] && ![status isEqualToString:@"EQUIPMENT_DAMAGED"])
	{
		OOReportJSErrorForCaller(context, @"Ship", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
		return NO;
	}
	
	key = [eqType identifier];
	hasOK = [thisEnt hasEquipmentItem:key];
	if ([eqType canBeDamaged])
	{
		damagedKey = [key stringByAppendingString:@"_DAMAGED"];
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
	}
	else
	{
		if (hasOK && ![status isEqualToString:@"EQUIPMENT_OK"])
		{
			OOReportJSWarning(context, @"Equipment %@ cannot be damaged.", key);
			hasOK = NO;
		}
	}
	
	OOJS_RETURN_BOOL(hasOK || hasDamaged);
	
	OOJS_NATIVE_EXIT
}


// equipmentStatus(type : equipmentInfoExpression) : String
static JSBool ShipEquipmentStatus(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	/*
		Interned string constants.
		Interned strings are guaranteed to survive for the lifetime of the JS
		runtime, which lasts as long as Oolite is running.
	*/
	static jsval strOK, strDamaged, strUnavailable;
	static BOOL inited = NO;
	if (EXPECT_NOT(!inited))
	{
		inited = YES;
		strOK = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_OK"));
		strDamaged = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_DAMAGED"));
		strUnavailable = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_UNAVAILABLE"));
	}
	
	ShipEntity				*thisEnt = nil;
	NSString				*key = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	key = JSValueToEquipmentKey(context, OOJS_ARG(0));
	if (EXPECT_NOT(key == nil))
	{
		OOReportJSBadArguments(context, @"Ship", @"equipmentStatus", argc, OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	
	if ([thisEnt hasEquipmentItem:key])  OOJS_RETURN(strOK);
	else if ([thisEnt hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]])  OOJS_RETURN(strDamaged);
	
	OOJS_RETURN(strUnavailable);
	
	OOJS_NATIVE_EXIT
}


// selectNewMissile()
static JSBool ShipSelectNewMissile(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	NSString *result = [[thisEnt selectMissile] identifier];
	// if there's a badly defined missile, selectMissile may return nil
	if (result == nil)  result = @"EQ_MISSILE";
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// fireMissile()
static JSBool ShipFireMissile(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	id					result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  result = [thisEnt fireMissileWithIdentifier:JSValToNSString(context, OOJS_ARG(0)) andTarget:[thisEnt primaryTarget]];
	else  result = [thisEnt fireMissile];
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}

// setCargo(cargoType : String [, number : count])
static JSBool ShipSetCargo(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*cargoType = nil;
	OOCargoType				commodity = CARGO_UNDEFINED;
	int32					count = 1;
	BOOL					gotCount = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	cargoType = JSValToNSString(context, OOJS_ARG(0));
	if (argc > 1)  gotCount = JS_ValueToInt32(context, OOJS_ARG(1), &count);
	if (EXPECT_NOT(cargoType == nil || !gotCount || count < 1))
	{
		OOReportJSBadArguments(context, @"Ship", @"setCargo", argc, OOJS_ARGV, nil, @"cargo name and optional positive quantity");
		return NO;
	}
	
	commodity = [UNIVERSE commodityForName:cargoType];
	if (commodity != CARGO_UNDEFINED)  [thisEnt setCommodityForPod:commodity andAmount:count];
	
	OOJS_RETURN_BOOL(commodity != CARGO_UNDEFINED);
	
	OOJS_NATIVE_EXIT
}


// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static JSBool ShipSetMaterials(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	return ShipSetMaterialsInternal(OOJS_NATIVE_CALLTHROUGH, thisEnt, NO);
	
	OOJS_NATIVE_EXIT
}


// setShaders(params: dict) 
static JSBool ShipSetShaders(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (JSVAL_IS_NULL(OOJS_ARG(0)) || (!JSVAL_IS_NULL(OOJS_ARG(0)) && !JSVAL_IS_OBJECT(OOJS_ARG(0))))
	{
		OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setShaders", @"object", [NSString stringWithJavaScriptValue:OOJS_ARG(0) inContext:context]);
		OOJS_RETURN_BOOL(NO);
	}
	
	OOJS_ARG(1) = OOJS_ARG(0);
	return ShipSetMaterialsInternal(OOJS_NATIVE_CALLTHROUGH, thisEnt, YES);
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipSetMaterialsInternal(OOJS_NATIVE_ARGS, ShipEntity *thisEnt, BOOL fromShaders)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*params = NULL;
	NSDictionary			*materials;
	NSDictionary			*shaders;
	BOOL					withShaders = NO;
	BOOL					success = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (JSVAL_IS_NULL(OOJS_ARG(0)) || (!JSVAL_IS_NULL(OOJS_ARG(0)) && !JSVAL_IS_OBJECT(OOJS_ARG(0))))
	{
		OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setMaterials", @"object", [NSString stringWithJavaScriptValue:OOJS_ARG(0) inContext:context]);
		OOJS_RETURN_BOOL(NO);
	}
	
	OOJSPauseTimeLimiter();
	
	if (argc > 1)
	{
		withShaders = YES;
		if (JSVAL_IS_NULL(OOJS_ARG(1)) || (!JSVAL_IS_NULL(OOJS_ARG(1)) && !JSVAL_IS_OBJECT(OOJS_ARG(1))))
		{
			OOReportJSWarning(context, @"Ship.%@: expected %@ instead of '%@'.",  @"setMaterials", @"object as second parameter", [NSString stringWithJavaScriptValue:OOJS_ARG(1) inContext:context]);
			withShaders = NO;
		}
	}
	
	if (fromShaders)
	{
		materials = [[thisEnt mesh] materials];
	}
	else
	{
		params = JSVAL_TO_OBJECT(OOJS_ARG(0));
		materials = JSObjectToObject(context, params);
	}
	
	if (withShaders)
	{
		params = JSVAL_TO_OBJECT(OOJS_ARG(1));
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
	
	if (mesh != nil)
	{
		[thisEnt setMesh:mesh];
		success = YES;
	}
	
	OOJSResumeTimeLimiter();
	
	OOJS_RETURN_BOOL(success);
	
	OOJS_PROFILE_EXIT
}


// exitSystem([int systemID])
static JSBool ShipExitSystem(OOJS_NATIVE_ARGS)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	int32				systemID = -1;
	BOOL				OK = NO;
	
	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOReportJSErrorForCaller(context, @"Ship", @"exitSystem", @"Not valid for player ship.");
		return NO;
	}
	
	if (argc > 0)
	{
		if (!JS_ValueToInt32(context, OOJS_ARG(0), &systemID) || systemID < 0 || 255 < systemID)
		{
			OOReportJSBadArguments(context, @"Ship", @"exitSystem", argc, OOJS_ARGV, nil, @"system ID");
			return NO;
		}
	}
	
	OK = [thisEnt performHyperSpaceToSpecificSystem:systemID]; 	// -1 == random destination system
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static BOOL RemoveOrExplodeShip(OOJS_NATIVE_ARGS, BOOL explode)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		NSCAssert(explode, @"RemoveOrExplodeShip(): shouldn't be called for player with !explode.");	// player.ship.remove() is blocked by caller.
		PlayerEntity *player = (PlayerEntity *)thisEnt;
		
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
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static BOOL ValidateContracts(OOJS_NATIVE_ARGS, BOOL isCargo)
{
	OOJS_PROFILE_ENTER
	
	unsigned		offset = isCargo ? 2 : 1;
	NSString		*functionName = isCargo ? @"awardContract" : @"addPassenger";
	jsdouble		fValue;
	
	if (!JSVAL_IS_INT(OOJS_ARG(offset)) || JSVAL_TO_INT(OOJS_ARG(offset)) > 255 || JSVAL_TO_INT(OOJS_ARG(offset)) < 0)
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc, OOJS_ARGV, nil, @"start:system ID");
		return NO;
	}
	if (!JSVAL_IS_INT(OOJS_ARG(offset + 1)) || JSVAL_TO_INT(OOJS_ARG(offset + 1)) > 255 || JSVAL_TO_INT(OOJS_ARG(offset + 1)) < 0)
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc - 1, OOJS_ARGV + 1, nil, @"destination:system ID");
		return NO;
	}
	if(!JS_ValueToNumber(context, OOJS_ARG(offset + 2), &fValue) || fValue <= [[PlayerEntity sharedPlayer] clockTime])
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc - 2, OOJS_ARGV + 2, nil, @"eta:future time");
		return NO;
	}
	if (!JS_ValueToNumber(context, OOJS_ARG(offset + 3), &fValue) || fValue <= 0.0)
	{
		OOReportJSBadArguments(context, @"Ship", functionName, argc - 3, OOJS_ARGV + 3, nil, @"fee:credits");
		return NO;
	}
	
	return YES;
	
	OOJS_PROFILE_EXIT
}
