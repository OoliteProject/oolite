/*

OOJSShip.m

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

#import "OOJSShip.h"
#import "OOJSEntity.h"
#import "OOJSVector.h"
#import "OOJSEquipmentInfo.h"
#import "OOJavaScriptEngine.h"
#import "ShipEntity.h"
#import "Entity.h"
#import "ShipEntityAI.h"
#import "ShipEntityScriptMethods.h"
#import "AI.h"
#import "OOStringParsing.h"
#import "EntityOOJavaScriptExtensions.h"
#import "OORoleSet.h"
#import "OOJSPlayer.h"
#import "OOShipGroup.h"
#import "OOEquipmentType.h"
#import "ResourceManager.h"
#import "OOCollectionExtractors.h"
#import "OOMesh.h"
#import "OOConstToString.h"


static JSObject *sShipPrototype;


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value);
static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value);

static JSBool ShipSetScript(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSwitchAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipExitAI(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipReactToAIMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSendAIMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDeployEscorts(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDockEscorts(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipHasRole(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEjectItem(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEjectSpecificItem(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDumpCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSpawn(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipDealEnergyDamage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipExplode(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRemove(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRunLegacyScriptActions(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipCommsMessage(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipFireECM(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipAbandonShip(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipCanAwardEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipAwardEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRemoveEquipment(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipRestoreSubEntities(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipEquipmentStatus(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetEquipmentStatus(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSelectNewMissile(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipFireMissile(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetBounty(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetCargo(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetMaterials(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipSetShaders(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipExitSystem(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipUpdateEscortFormation(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipClearDefenseTargets(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipAddDefenseTarget(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGetMaterials(JSContext *context, uintN argc, jsval *vp);
static JSBool ShipGetShaders(JSContext *context, uintN argc, jsval *vp);


static BOOL RemoveOrExplodeShip(JSContext *context, uintN argc, jsval *vp, BOOL explode);
static JSBool ShipSetMaterialsInternal(JSContext *context, uintN argc, jsval *vp, ShipEntity *thisEnt, BOOL fromShaders);



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
	OOJSObjectWrapperFinalize,// finalize
	JSCLASS_NO_OPTIONAL_MEMBERS
};


enum
{
	// Property IDs
	kShip_accuracy,				// the ship's accuracy, float, read/write
	kShip_aftWeapon,			// the ship's aft weapon, equipmentType, read/write
	kShip_AI,					// AI state machine name, string, read/write
	kShip_AIState,				// AI state machine state, string, read/write
	kShip_autoAI,				// bool, read-only, auto_ai from shipdata
	kShip_beaconCode,			// beacon code, string, read/write
	kShip_boundingBox,			// boundingBox, vector, read-only
	kShip_bounty,				// bounty, unsigned int, read/write
	kShip_cargoSpaceAvailable,	// free cargo space, integer, read-only
	kShip_cargoSpaceCapacity,	// maximum cargo, integer, read-only
	kShip_cargoSpaceUsed,		// cargo on board, integer, read-only
	kShip_contracts,			// cargo contracts contracts, array - strings & whatnot, read only
	kShip_commodity,			// commodity of a ship, read only
	kShip_commodityAmount,		// commodityAmount of a ship, read only
	kShip_cloakAutomatic,		// should cloack start by itself or by script, read/write
	kShip_cruiseSpeed,			// desired cruising speed, number, read only
	kShip_dataKey,				// string, read-only, shipdata.plist key
	kShip_defenseTargets,		// array, read-only, defense targets
	kShip_desiredSpeed,			// AI desired flight speed, double, read/write
	kShip_displayName,			// name displayed on screen, string, read/write
	kShip_entityPersonality,	// per-ship random number, int, read-only
	kShip_equipment,			// the ship's equipment, array of EquipmentInfo, read only
	kShip_escortGroup,			// group, ShipGroup, read-only
	kShip_escorts,				// deployed escorts, array of Ship, read-only
	kShip_forwardWeapon,		// the ship's forward weapon, equipmentType, read/write
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
	kShip_isPolice,				// is police, boolean, read-only
	kShip_isRock,				// is a rock (hermits included), boolean, read-only
	kShip_isThargoid,			// is thargoid, boolean, read-only
	kShip_isTrader,				// is trader, boolean, read-only
	kShip_isWeapon,				// is missile or mine, boolean, read-only
	kShip_laserHeatLevel,					// active laser temperature, float, read-only
	kShip_laserHeatLevelAft,					// aft laser temperature, float, read-only
	kShip_laserHeatLevelForward,					// fore laser temperature, float, read-only
	kShip_laserHeatLevelPort,					// port laser temperature, float, read-only
	kShip_laserHeatLevelStarboard,					// starboard laser temperature, float, read-only
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
	kShip_pitch,				// pitch level, float, read-only
	kShip_portWeapon,			// the ship's port weapon, equipmentType, read/write
	kShip_potentialCollider,	// "proximity alert" ship, Entity, read-only
	kShip_primaryRole,			// Primary role, string, read/write
	kShip_reportAIMessages,		// report AI messages, boolean, read/write
	kShip_roleWeights,			// roles and weights, dictionary, read-only
	kShip_roles,				// roles, array, read-only
	kShip_roll,					// roll level, float, read-only
	kShip_savedCoordinates,		// coordinates in system space for AI use, Vector, read/write
	kShip_scannerDisplayColor1,	// color of lollipop shown on scanner, array, read/write
	kShip_scannerDisplayColor2,	// color of lollipop shown on scanner when flashing, array, read/write
	kShip_scannerRange,			// scanner range, double, read-only
	kShip_script,				// script, Script, read-only
	kShip_scriptedMisjump,		// next jump will miss if set to true, boolean, read/write
	kShip_scriptInfo,			// arbitrary data for scripts, dictionary, read-only
	kShip_speed,				// current flight speed, double, read-only
	kShip_starboardWeapon,		// the ship's starboard weapon, equipmentType, read/write
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
	kShip_weaponFacings,		// weapon range, double, read-only
	kShip_weaponRange,			// weapon range, double, read-only
	kShip_withinStationAegis,	// within main station aegis, boolean, read/write
	kShip_yaw,					// yaw level, float, read-only
};


static JSPropertySpec sShipProperties[] =
{
	// JS name					ID							flags
	{ "accuracy",				kShip_accuracy,				OOJS_PROP_READWRITE_CB },
	{ "aftWeapon",				kShip_aftWeapon,			OOJS_PROP_READWRITE_CB },
	{ "AI",						kShip_AI,					OOJS_PROP_READONLY_CB },
	{ "AIState",				kShip_AIState,				OOJS_PROP_READWRITE_CB },
	{ "autoAI",					kShip_autoAI,				OOJS_PROP_READONLY_CB },
	{ "beaconCode",				kShip_beaconCode,			OOJS_PROP_READWRITE_CB },
	{ "boundingBox",			kShip_boundingBox,			OOJS_PROP_READONLY_CB },
	{ "bounty",					kShip_bounty,				OOJS_PROP_READWRITE_CB },
	{ "cargoSpaceUsed",			kShip_cargoSpaceUsed,		OOJS_PROP_READONLY_CB },	// Documented as PlayerShip property because it isn't reliable for NPCs.
	{ "cargoSpaceCapacity",		kShip_cargoSpaceCapacity,	OOJS_PROP_READONLY_CB },
	{ "cargoSpaceAvailable",	kShip_cargoSpaceAvailable,	OOJS_PROP_READONLY_CB },	// Documented as PlayerShip property because it isn't reliable for NPCs.
	// contracts instead of cargo to distinguish them from the manifest
	{ "commodity",				kShip_commodity,			OOJS_PROP_READONLY_CB },
	{ "commodityAmount",		kShip_commodityAmount,		OOJS_PROP_READONLY_CB },
	{ "contracts",				kShip_contracts,			OOJS_PROP_READONLY_CB },
	{ "cloakAutomatic",			kShip_cloakAutomatic,		OOJS_PROP_READWRITE_CB},
	{ "cruiseSpeed",			kShip_cruiseSpeed,			OOJS_PROP_READONLY_CB },
	{ "dataKey",				kShip_dataKey,				OOJS_PROP_READONLY_CB },
	{ "defenseTargets",			kShip_defenseTargets,		OOJS_PROP_READONLY_CB },
	{ "desiredSpeed",			kShip_desiredSpeed,			OOJS_PROP_READWRITE_CB },
	{ "displayName",			kShip_displayName,			OOJS_PROP_READWRITE_CB },
	{ "entityPersonality",		kShip_entityPersonality,	OOJS_PROP_READONLY_CB },
	{ "equipment",				kShip_equipment,			OOJS_PROP_READONLY_CB },
	{ "escorts",				kShip_escorts,				OOJS_PROP_READONLY_CB },
	{ "escortGroup",			kShip_escortGroup,			OOJS_PROP_READONLY_CB },
	{ "forwardWeapon",			kShip_forwardWeapon,		OOJS_PROP_READWRITE_CB },
	{ "fuel",					kShip_fuel,					OOJS_PROP_READWRITE_CB },
	{ "fuelChargeRate",			kShip_fuelChargeRate,		OOJS_PROP_READONLY_CB },
	{ "group",					kShip_group,				OOJS_PROP_READWRITE_CB },
	{ "hasHostileTarget",		kShip_hasHostileTarget,		OOJS_PROP_READONLY_CB },
	{ "hasHyperspaceMotor",		kShip_hasHyperspaceMotor,	OOJS_PROP_READONLY_CB },
	{ "hasSuspendedAI",			kShip_hasSuspendedAI,		OOJS_PROP_READONLY_CB },
	{ "heatInsulation",			kShip_heatInsulation,		OOJS_PROP_READWRITE_CB },
	{ "heading",				kShip_heading,				OOJS_PROP_READONLY_CB },
	{ "isBeacon",				kShip_isBeacon,				OOJS_PROP_READONLY_CB },
	{ "isCloaked",				kShip_isCloaked,			OOJS_PROP_READWRITE_CB },
	{ "isCargo",				kShip_isCargo,				OOJS_PROP_READONLY_CB },
	{ "isDerelict",				kShip_isDerelict,			OOJS_PROP_READONLY_CB },
	{ "isFrangible",			kShip_isFrangible,			OOJS_PROP_READONLY_CB },
	{ "isJamming",				kShip_isJamming,			OOJS_PROP_READONLY_CB },
	{ "isMine",					kShip_isMine,				OOJS_PROP_READONLY_CB },
	{ "isMissile",				kShip_isMissile,			OOJS_PROP_READONLY_CB },
	{ "isPiloted",				kShip_isPiloted,			OOJS_PROP_READONLY_CB },
	{ "isPirate",				kShip_isPirate,				OOJS_PROP_READONLY_CB },
	{ "isPirateVictim",			kShip_isPirateVictim,		OOJS_PROP_READONLY_CB },
	{ "isPolice",				kShip_isPolice,				OOJS_PROP_READONLY_CB },
	{ "isRock",					kShip_isRock,				OOJS_PROP_READONLY_CB },
	{ "isBoulder",				kShip_isBoulder,			OOJS_PROP_READWRITE_CB },
	{ "isThargoid",				kShip_isThargoid,			OOJS_PROP_READONLY_CB },
	{ "isTrader",				kShip_isTrader,				OOJS_PROP_READONLY_CB },
	{ "isWeapon",				kShip_isWeapon,				OOJS_PROP_READONLY_CB },
	{ "laserHeatLevel",					kShip_laserHeatLevel,					OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelAft",					kShip_laserHeatLevelAft,					OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelForward",					kShip_laserHeatLevelForward,					OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelPort",					kShip_laserHeatLevelPort,					OOJS_PROP_READONLY_CB },
	{ "laserHeatLevelStarboard",					kShip_laserHeatLevelStarboard,					OOJS_PROP_READONLY_CB },
	{ "lightsActive",			kShip_lightsActive,			OOJS_PROP_READWRITE_CB },
	{ "maxSpeed",				kShip_maxSpeed,				OOJS_PROP_READONLY_CB },
	{ "maxThrust",				kShip_maxThrust,			OOJS_PROP_READONLY_CB },
	{ "missileCapacity",		kShip_missileCapacity,		OOJS_PROP_READONLY_CB },
	{ "missileLoadTime",		kShip_missileLoadTime,		OOJS_PROP_READWRITE_CB },
	{ "missiles",				kShip_missiles,				OOJS_PROP_READONLY_CB },
	{ "name",					kShip_name,					OOJS_PROP_READWRITE_CB },
	{ "passengerCount",			kShip_passengerCount,		OOJS_PROP_READONLY_CB },
	{ "passengerCapacity",		kShip_passengerCapacity,	OOJS_PROP_READONLY_CB },
	{ "passengers",				kShip_passengers,			OOJS_PROP_READONLY_CB },
	{ "pitch",					kShip_pitch,				OOJS_PROP_READONLY_CB },
	{ "portWeapon",				kShip_portWeapon,			OOJS_PROP_READWRITE_CB },
	{ "potentialCollider",		kShip_potentialCollider,	OOJS_PROP_READONLY_CB },
	{ "primaryRole",			kShip_primaryRole,			OOJS_PROP_READWRITE_CB },
	{ "reportAIMessages",		kShip_reportAIMessages,		OOJS_PROP_READWRITE_CB },
	{ "roleWeights",			kShip_roleWeights,			OOJS_PROP_READONLY_CB },
	{ "roles",					kShip_roles,				OOJS_PROP_READONLY_CB },
	{ "roll",					kShip_roll,					OOJS_PROP_READONLY_CB },
	{ "savedCoordinates",		kShip_savedCoordinates,		OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor1",	kShip_scannerDisplayColor1,	OOJS_PROP_READWRITE_CB },
	{ "scannerDisplayColor2",	kShip_scannerDisplayColor2,	OOJS_PROP_READWRITE_CB },
	{ "scannerRange",			kShip_scannerRange,			OOJS_PROP_READONLY_CB },
	{ "script",					kShip_script,				OOJS_PROP_READONLY_CB },
	{ "scriptedMisjump",		kShip_scriptedMisjump,		OOJS_PROP_READWRITE_CB },
	{ "scriptInfo",				kShip_scriptInfo,			OOJS_PROP_READONLY_CB },
	{ "speed",					kShip_speed,				OOJS_PROP_READONLY_CB },
	{ "starboardWeapon",		kShip_starboardWeapon,		OOJS_PROP_READWRITE_CB },
	{ "subEntities",			kShip_subEntities,			OOJS_PROP_READONLY_CB },
	{ "subEntityCapacity",		kShip_subEntityCapacity,	OOJS_PROP_READONLY_CB },
	{ "target",					kShip_target,				OOJS_PROP_READWRITE_CB },
	{ "temperature",			kShip_temperature,			OOJS_PROP_READWRITE_CB },
	{ "thrust",					kShip_thrust,				OOJS_PROP_READWRITE_CB },
	{ "thrustVector",			kShip_thrustVector,			OOJS_PROP_READWRITE_CB },
	{ "trackCloseContacts",		kShip_trackCloseContacts,	OOJS_PROP_READWRITE_CB },
	{ "vectorForward",			kShip_vectorForward,		OOJS_PROP_READONLY_CB },
	{ "vectorRight",			kShip_vectorRight,			OOJS_PROP_READONLY_CB },
	{ "vectorUp",				kShip_vectorUp,				OOJS_PROP_READONLY_CB },
	{ "velocity",				kShip_velocity,				OOJS_PROP_READWRITE_CB },
	{ "weaponFacings",			kShip_weaponFacings,			OOJS_PROP_READONLY_CB },
	{ "weaponRange",			kShip_weaponRange,			OOJS_PROP_READONLY_CB },
	{ "withinStationAegis",		kShip_withinStationAegis,	OOJS_PROP_READONLY_CB },
	{ "yaw",				kShip_yaw,			OOJS_PROP_READONLY_CB },
	{ 0 }
};


static JSFunctionSpec sShipMethods[] =
{
	// JS name					Function					min args
	{ "abandonShip",			ShipAbandonShip,			0 },
	{ "addDefenseTarget",			ShipAddDefenseTarget,			1 },
	{ "awardEquipment",			ShipAwardEquipment,			1 },
	{ "canAwardEquipment",		ShipCanAwardEquipment,		1 },
	{ "clearDefenseTargets",			ShipClearDefenseTargets,			0 },
	{ "commsMessage",			ShipCommsMessage,			1 },
	{ "dealEnergyDamage",		ShipDealEnergyDamage,		2 },
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
	{ "getMaterials",         ShipGetMaterials,				0 },
	{ "getShaders",            ShipGetShaders,				0 },
	{ "hasRole",				ShipHasRole,				1 },
	{ "reactToAIMessage",		ShipReactToAIMessage,		1 },
	{ "remove",					ShipRemove,					0 },
	{ "removeEquipment",		ShipRemoveEquipment,		1 },
	{ "restoreSubEntities",		ShipRestoreSubEntities,		0 },
	{ "__runLegacyScriptActions", ShipRunLegacyScriptActions, 2 },	// Deliberately not documented
	{ "selectNewMissile",		ShipSelectNewMissile,		0 },
	{ "sendAIMessage",			ShipSendAIMessage,			1 },
	{ "setAI",					ShipSetAI,					1 },
	{ "setBounty",				ShipSetBounty,				2 },
	{ "setCargo",				ShipSetCargo,				1 },
	{ "setEquipmentStatus",		ShipSetEquipmentStatus,		2 },
	{ "setMaterials",			ShipSetMaterials,			1 },
	{ "setScript",				ShipSetScript,				1 },
	{ "setShaders",				ShipSetShaders,				2 },
	{ "spawn",					ShipSpawn,					1 },
	// spawnOne() is defined in the prefix script.
	{ "switchAI",				ShipSwitchAI,				1 },
	{ "updateEscortFormation",	ShipUpdateEscortFormation,	0 },
	{ 0 }
};


DEFINE_JS_OBJECT_GETTER(JSShipGetShipEntity, &sShipClass, sShipPrototype, ShipEntity)


void InitOOJSShip(JSContext *context, JSObject *global)
{
	sShipPrototype = JS_InitClass(context, global, JSEntityPrototype(), &sShipClass, OOJSUnconstructableConstruct, 0, sShipProperties, sShipMethods, NULL, NULL);
	OOJSRegisterObjectConverter(&sShipClass, OOJSBasicPrivateObjectConverter);
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


static JSBool ShipGetProperty(JSContext *context, JSObject *this, jsid propID, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*entity = nil;
	id							result = nil;
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))  return NO;
	if (OOIsStaleEntity(entity)) { *value = JSVAL_VOID; return YES; }
	
	switch (JSID_TO_INT(propID))
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
		
		case kShip_roleWeights:
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

		case kShip_autoAI:
			*value = OOJSValueFromBOOL([entity hasAutoAI]);
			return YES;

		case kShip_accuracy:
			return JS_NewNumberValue(context, [entity accuracy], value);
			
		case kShip_fuel:
			return JS_NewNumberValue(context, [entity fuel] * 0.1, value);
			
		case kShip_fuelChargeRate:
			return JS_NewNumberValue(context, [entity fuelChargeRate], value);
			
		case kShip_bounty:
			*value = INT_TO_JSVAL([entity bounty]);
			return YES;
			
		case kShip_subEntities:
			result = [entity subEntitiesForScript];
			break;
			
		case kShip_subEntityCapacity:
			*value = INT_TO_JSVAL([entity maxShipSubEntities]);
			return YES;
			
		case kShip_hasSuspendedAI:
			*value = OOJSValueFromBOOL([[entity getAI] hasSuspendedStateMachines]);
			return YES;
			
		case kShip_target:
			result = [entity primaryTarget];
			break;
		
		case kShip_defenseTargets:
		{
			unsigned ndts = [entity numDefenseTargets];
			NSMutableArray* targets = [NSMutableArray arrayWithCapacity:ndts];
			for (unsigned i=0;i<ndts;i++)
			{
				Entity *dtarget = [entity getDefenseTarget:i];
				if (dtarget != nil)
				{
					[targets addObject:dtarget];
				}
			}
			result = [NSArray arrayWithArray:targets];
			if ([result count] == 0)  result = nil;
			break;
		}
		case kShip_escorts:
			result = [[entity escortGroup] memberArrayExcludingLeader];
			if ([result count] == 0)  result = nil;
			break;
			
		case kShip_group:
			result = [entity group];
			break;
			
		case kShip_escortGroup:
			result = [entity escortGroup];
			break;
			
		case kShip_temperature:
			return JS_NewNumberValue(context, [entity temperature] / SHIP_MAX_CABIN_TEMP, value);
			
		case kShip_heatInsulation:
			return JS_NewNumberValue(context, [entity heatInsulation], value);
			
		case kShip_heading:
			return VectorToJSValue(context, [entity forwardVector], value);
			
		case kShip_entityPersonality:
			*value = INT_TO_JSVAL([entity entityPersonalityInt]);
			return YES;
			
		case kShip_isBeacon:
			*value = OOJSValueFromBOOL([entity isBeacon]);
			return YES;
			
		case kShip_beaconCode:
			result = [entity beaconCode];
			break;
		
		case kShip_isFrangible:
			*value = OOJSValueFromBOOL([entity isFrangible]);
			return YES;
		
		case kShip_isCloaked:
			*value = OOJSValueFromBOOL([entity isCloaked]);
			return YES;
			
		case kShip_cloakAutomatic:
			*value = OOJSValueFromBOOL([entity hasAutoCloak]);
			return YES;
			
		case kShip_isJamming:
			*value = OOJSValueFromBOOL([entity isJammingScanning]);
			return YES;
		
		case kShip_potentialCollider:
			result = [entity proximityAlert];
			break;
		
		case kShip_hasHostileTarget:
			*value = OOJSValueFromBOOL([entity hasHostileTarget]);
			return YES;
		
		case kShip_hasHyperspaceMotor:
			*value = OOJSValueFromBOOL([entity hasHyperspaceMotor]);
			return YES;
		
		case kShip_weaponRange:
			return JS_NewNumberValue(context, [entity weaponRange], value);

		case kShip_weaponFacings:
			if ([entity isPlayer])
			{
				PlayerEntity *pent = (PlayerEntity*)entity;
				return JS_NewNumberValue(context, [pent availableFacings], value);
			}
			return JS_NewNumberValue(context, [entity weaponFacings], value);
		
		case kShip_scannerRange:
			return JS_NewNumberValue(context, [entity scannerRange], value);
		
		case kShip_reportAIMessages:
			*value = OOJSValueFromBOOL([entity reportAIMessages]);
			return YES;
		
		case kShip_withinStationAegis:
			*value = OOJSValueFromBOOL([entity withinStationAegis]);
			return YES;
			
		case kShip_cargoSpaceCapacity:
			*value = INT_TO_JSVAL([entity maxAvailableCargoSpace]);
			return YES;
			
		case kShip_cargoSpaceUsed:
			*value = INT_TO_JSVAL([entity maxAvailableCargoSpace] - [entity availableCargoSpace]);
			return YES;
			
		case kShip_cargoSpaceAvailable:
			*value = INT_TO_JSVAL([entity availableCargoSpace]);
			return YES;
			
		case kShip_commodity:
			if ([entity commodityAmount] > 0)
			{
				result = CommodityTypeToString([entity commodityType]);
			}
			break;
			
		case kShip_commodityAmount:
			*value = INT_TO_JSVAL([entity commodityAmount]);
			return YES;
			
		case kShip_speed:
			return JS_NewNumberValue(context, [entity flightSpeed], value);
			
		case kShip_cruiseSpeed:
			return JS_NewNumberValue(context, [entity cruiseSpeed], value);

		case kShip_dataKey:
			result = [entity shipDataKey];
			break;
			
		case kShip_desiredSpeed:
			return JS_NewNumberValue(context, [entity desiredSpeed], value);
			
		case kShip_maxSpeed:
			return JS_NewNumberValue(context, [entity maxFlightSpeed], value);
			
		case kShip_script:
			result = [entity shipScript];
			break;
			
		case kShip_isPirate:
			*value = OOJSValueFromBOOL([entity isPirate]);
			return YES;
			
		case kShip_isPolice:
			*value = OOJSValueFromBOOL([entity isPolice]);
			return YES;
			
		case kShip_isThargoid:
			*value = OOJSValueFromBOOL([entity isThargoid]);
			return YES;
			
		case kShip_isTrader:
			*value = OOJSValueFromBOOL([entity isTrader]);
			return YES;
			
		case kShip_isPirateVictim:
			*value = OOJSValueFromBOOL([entity isPirateVictim]);
			return YES;
			
		case kShip_isMissile:
			*value = OOJSValueFromBOOL([entity isMissile]);
			return YES;
			
		case kShip_isMine:
			*value = OOJSValueFromBOOL([entity isMine]);
			return YES;
			
		case kShip_isWeapon:
			*value = OOJSValueFromBOOL([entity isWeapon]);
			return YES;
			
		case kShip_isRock:
			*value = OOJSValueFromBOOL([entity scanClass] == CLASS_ROCK);	// hermits and asteroids!
			return YES;
			
		case kShip_isBoulder:
			*value = OOJSValueFromBOOL([entity isBoulder]);
			return YES;
			
		case kShip_isCargo:
			*value = OOJSValueFromBOOL([entity scanClass] == CLASS_CARGO && [entity commodityAmount] > 0);
			return YES;
			
		case kShip_isDerelict:
			*value = OOJSValueFromBOOL([entity isHulk]);
			return YES;
			
		case kShip_isPiloted:
			*value = OOJSValueFromBOOL([entity isPlayer] || [[entity crew] count] > 0);
			return YES;
			
		case kShip_scriptedMisjump:
			*value = OOJSValueFromBOOL([entity scriptedMisjump]);
			return YES;
			
		case kShip_scriptInfo:
			result = [entity scriptInfo];
			if (result == nil)  result = [NSDictionary dictionary];	// empty rather than null
			break;
			
		case kShip_trackCloseContacts:
			*value = OOJSValueFromBOOL([entity trackCloseContacts]);
			return YES;
			
		case kShip_passengerCount:
			*value = INT_TO_JSVAL([entity passengerCount]);
			return YES;
			
		case kShip_passengerCapacity:
			*value = INT_TO_JSVAL([entity passengerCapacity]);
			return YES;

		case kShip_missileCapacity:
			*value = INT_TO_JSVAL([entity missileCapacity]);
			return YES;
			
		case kShip_missileLoadTime:
			return JS_NewNumberValue(context, [entity missileLoadTime], value);
		
		case kShip_savedCoordinates:
			return VectorToJSValue(context, [entity coordinates], value);
		
		case kShip_equipment:
			result = [entity equipmentListForScripting];
			break;
			
		case kShip_forwardWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_FORWARD];
			break;
		
		case kShip_aftWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_AFT];
			break;
		
		case kShip_portWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_PORT];
			break;
		
		case kShip_starboardWeapon:
			result = [entity weaponTypeForFacing:WEAPON_FACING_STARBOARD];
			break;

		case kShip_laserHeatLevel:
			return JS_NewNumberValue(context, [entity laserHeatLevel], value);

		case kShip_laserHeatLevelAft:
			return JS_NewNumberValue(context, [entity laserHeatLevelAft], value);

		case kShip_laserHeatLevelForward:
			return JS_NewNumberValue(context, [entity laserHeatLevelForward], value);

		case kShip_laserHeatLevelPort:
			return JS_NewNumberValue(context, [entity laserHeatLevelPort], value);

		case kShip_laserHeatLevelStarboard:
			return JS_NewNumberValue(context, [entity laserHeatLevelStarboard], value);
		
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
			break;
			
		case kShip_scannerDisplayColor2:
			result = [[entity scannerDisplayColor2] normalizedArray];
			break;
			
		case kShip_maxThrust:
			return JS_NewNumberValue(context, [entity maxThrust], value);
			
		case kShip_thrust:
			return JS_NewNumberValue(context, [entity thrust], value);
			
		case kShip_lightsActive:
			*value = OOJSValueFromBOOL([entity lightsActive]);
			return YES;
			
		case kShip_vectorRight:
			return VectorToJSValue(context, [entity rightVector], value);
			
		case kShip_vectorForward:
			return VectorToJSValue(context, [entity forwardVector], value);
			
		case kShip_vectorUp:
			return VectorToJSValue(context, [entity upVector], value);
			
		case kShip_velocity:
			return VectorToJSValue(context, [entity velocity], value);
			
		case kShip_thrustVector:
			return VectorToJSValue(context, [entity thrustVector], value);

		case kShip_pitch:
			return JS_NewNumberValue(context, [entity flightPitch], value);

		case kShip_roll:
			return JS_NewNumberValue(context, [entity flightRoll], value);

		case kShip_yaw:
			return JS_NewNumberValue(context, [entity flightYaw], value);
		
		case kShip_boundingBox:
			{
				Vector bbvect;
				BoundingBox box;

				if ([entity isSubEntity])
				{
					box = [entity boundingBox];
				}
				else
				{
					box = [entity totalBoundingBox];
				}
				bounding_box_get_dimensions(box,&bbvect.x,&bbvect.y,&bbvect.z);
				return VectorToJSValue(context, bbvect, value);
			}
			
		default:
			OOJSReportBadPropertySelector(context, this, propID, sShipProperties);
			return NO;
	}
	
	*value = OOJSValueFromNativeObject(context, result);
	return YES;
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipSetProperty(JSContext *context, JSObject *this, jsid propID, JSBool strict, jsval *value)
{
	if (!JSID_IS_INT(propID))  return YES;
	
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*entity = nil;
	ShipEntity					*target = nil;
	NSString					*sValue = nil;
	jsdouble					fValue;
	int32						iValue;
	JSBool						bValue;
	Vector						vValue;
	OOShipGroup					*group = nil;
	OOColor						*colorForScript = nil;
	BOOL exists;
	
	if (EXPECT_NOT(!JSShipGetShipEntity(context, this, &entity)))  return NO;
	if (OOIsStaleEntity(entity))  return YES;
	
	switch (JSID_TO_INT(propID))
	{
		case kShip_name:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setName:sValue];
				return YES;
			}
			break;
			
		case kShip_displayName:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setDisplayName:sValue];
				return YES;
			}
			break;
		
		case kShip_primaryRole:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[entity setPrimaryRole:sValue];
				return YES;
			}
			break;
		
		case kShip_AIState:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue != nil)
			{
				[[entity getAI] setState:sValue];
				return YES;
			}
			break;
		
		case kShip_beaconCode:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			sValue = OOStringFromJSValue(context,*value);
			if (sValue == nil || [sValue length] == 0) 
			{
				if ([entity isBeacon]) 
				{
					[UNIVERSE clearBeacon:entity];
					if ([PLAYER nextBeacon] == entity)
					{
						[PLAYER setCompassMode:COMPASS_MODE_PLANET];
					}
				}
			}
			else 
			{
				if ([entity isBeacon]) 
				{
					[entity setBeaconCode:sValue];
				}
				else // Universe needs to update beacon lists in this case only
				{
					[entity setBeaconCode:sValue];
					[UNIVERSE setNextBeacon:entity];
				}
			}
			return YES;
			break;
			
		case kShip_accuracy:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setAccuracy:fValue];
				return YES;
			}
			break;

		case kShip_fuel:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = OOClamp_0_max_d(fValue, MAX_JUMP_RANGE);
				[entity setFuel:lround(fValue * 10.0)];
				return YES;
			}
			break;
			
		case kShip_bounty:
			if (JS_ValueToInt32(context, *value, &iValue))
			{
				if (iValue < 0)  iValue = 0;
				[entity setBounty:iValue withReason:kOOLegalStatusReasonByScript];
				return YES;
			}
			break;
		
		case kShip_target:
			if (JSVAL_IS_NULL(*value))
			{
				[entity setTargetForScript:nil];
				return YES;
			}
			else if (JSValueToEntity(context, *value, &target) && [target isKindOfClass:[ShipEntity class]])
			{
				[entity setTargetForScript:target];
				return YES;
			}
			break;
			
		case kShip_group:
			group = OOJSNativeObjectOfClassFromJSValue(context, *value, [OOShipGroup class]);
			if (group != nil || JSVAL_IS_NULL(*value))
			{
				[entity setGroup:group];
				return YES;
			}
			break;
		
		case kShip_temperature:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = fmax(fValue, 0.0);
				[entity setTemperature:fValue * SHIP_MAX_CABIN_TEMP];
				return YES;
			}
			break;
		
		case kShip_heatInsulation:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				fValue = fmax(fValue, 0.125);
				[entity setHeatInsulation:fValue];
				return YES;
			}
			break;
		
		case kShip_isCloaked:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setCloaked:bValue];
				return YES;
			}
			break;
			
		case kShip_cloakAutomatic:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setAutoCloak:bValue];
				return YES;
			}
			break;
			
		case kShip_missileLoadTime:
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setMissileLoadTime:fmax(0.0, fValue)];
				return YES;
			}
			break;
		
		case kShip_reportAIMessages:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setReportAIMessages:bValue];
				return YES;
			}
			break;
			
		case kShip_trackCloseContacts:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setTrackCloseContacts:bValue];
				return YES;
			}
			break;
		
		case kShip_isBoulder:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setIsBoulder:bValue];
				return YES;
			}
			break;
			
		case kShip_desiredSpeed:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setDesiredSpeed:fmax(fValue, 0.0)];
				return YES;
			}
			break;
		
		case kShip_savedCoordinates:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setCoordinate:vValue];
				return YES;
			}
			break;
			
		case kShip_scannerDisplayColor1:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setScannerDisplayColor1:colorForScript];
				return YES;
			}
			break;
			
		case kShip_scannerDisplayColor2:
			colorForScript = [OOColor colorWithDescription:OOJSNativeObjectFromJSValue(context, *value)];
			if (colorForScript != nil || JSVAL_IS_NULL(*value))
			{
				[entity setScannerDisplayColor2:colorForScript];
				return YES;
			}
			break;
			
		case kShip_scriptedMisjump:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				[entity setScriptedMisjump:bValue];
				return YES;
			}
			break;
			
		case kShip_thrust:
			if (EXPECT_NOT([entity isPlayer]))  goto playerReadOnly;
			
			if (JS_ValueToNumber(context, *value, &fValue))
			{
				[entity setThrust:OOClamp_0_max_f(fValue, [entity maxThrust])];
				return YES;
			}
			break;
			
		case kShip_lightsActive:
			if (JS_ValueToBoolean(context, *value, &bValue))
			{
				if (bValue)  [entity switchLightsOn];
				else  [entity switchLightsOff];
				return YES;
			}
			break;
			
		case kShip_velocity:
			if (JSValueToVector(context, *value, &vValue))
			{
				[entity setTotalVelocity:vValue];
				return YES;
			}
			break;


		case kShip_portWeapon: 
		case kShip_starboardWeapon:
		case kShip_aftWeapon: 
		case kShip_forwardWeapon: 

			sValue = JSValueToEquipmentKeyRelaxed(context, *value, &exists);
			if (sValue == nil) 
			{
				sValue = @"EQ_WEAPON_NONE";
			}
			int facing = WEAPON_FACING_FORWARD;
			switch (JSID_TO_INT(propID))
			{
				case kShip_aftWeapon: 
					facing = WEAPON_FACING_AFT;
					break;
				case kShip_forwardWeapon: 
					facing = WEAPON_FACING_FORWARD;
					break;
				case kShip_portWeapon: 
					facing = WEAPON_FACING_PORT;
					break;
				case kShip_starboardWeapon:
					facing = WEAPON_FACING_STARBOARD;
					break;
			}
			if ([entity isPlayer])
			{
				[PLAYER setWeaponMount:facing toWeapon:sValue];
			} 
			else
			{
				[entity setWeaponMount:facing toWeapon:sValue];
			}

			return YES;
			break;

		default:
			OOJSReportBadPropertySelector(context, this, propID, sShipProperties);
			return NO;
	}
	
	OOJSReportBadPropertyValue(context, this, propID, sShipProperties, *value);
	return NO;
	
playerReadOnly:
	OOJSReportError(context, @"player.ship.%@ is read-only.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties));
	return NO;

// Not used (yet)
/*
npcReadOnly:
	OOJSReportError(context, @"npc.ship.%@ is read-only.", OOStringFromJSPropertyIDAndSpec(context, propID, sShipProperties));
	return NO;
*/

	OOJS_NATIVE_EXIT
}


// *** Methods ***

#define GET_THIS_SHIP(THISENT) do { \
	if (EXPECT_NOT(!JSShipGetShipEntity(context, OOJS_THIS, &THISENT)))  return NO; /* Exception */ \
	if (OOIsStaleEntity(THISENT))  OOJS_RETURN_VOID; \
} while (0)


// setScript(scriptName : String)
static JSBool ShipSetScript(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setScript", MIN(argc, 1U), OOJS_ARGV, nil, @"string (script name)");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"setScript", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt setShipScript:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// setAI(aiName : String)
static JSBool ShipSetAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setAI", MIN(argc, 1U), OOJS_ARGV, nil, @"string (AI name)");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"setAI", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt setAITo:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// switchAI(aiName : String)
static JSBool ShipSwitchAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*name = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  name = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(name == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"switchAI", MIN(argc, 1U), OOJS_ARGV, nil, @"string (AI name)");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"switchAI", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt switchAITo:name];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// exitAI()
static JSBool ShipExitAI(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	AI						*thisAI = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"exitAI", @"Not valid for player ship.");
		return NO;
	}
	thisAI = [thisEnt getAI];
	
	if ([thisAI hasSuspendedStateMachines])
	{
		if (argc > 0)
		{
			message = OOStringFromJSValue(context, OOJS_ARGV[0]);
		}
		// Else AI will default to RESTARTED.
		
		[thisAI exitStateMachineWithMessage:message];
	}
	else
	{
		OOJSReportWarningForCaller(context, @"Ship", @"exitAI()", @"Cannot exit current AI state machine because there are no suspended state machines.");
	}
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// reactToAIMessage(message : String)
static JSBool ShipReactToAIMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(message == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"reactToAIMessage", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"reactToAIMessage", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt reactToAIMessage:message context:@"JavaScript reactToAIMessage()"];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// sendAIMessage(message : String)
static JSBool ShipSendAIMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	
	GET_THIS_SHIP(thisEnt);
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(message == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"sendAIMessage", MIN(argc, 1U), OOJS_ARGV, nil, @"string");
		return NO;
	}
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"sendAIMessage", @"Not valid for player ship.");
		return NO;
	}
	
	[thisEnt sendAIMessage:message];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// deployEscorts()
static JSBool ShipDeployEscorts(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	[thisEnt deployEscorts];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// dockEscorts()
static JSBool ShipDockEscorts(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	[thisEnt dockEscorts];
	OOJS_RETURN_VOID;
	
	OOJS_NATIVE_EXIT
}


// hasRole(role : String) : Boolean
static JSBool ShipHasRole(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"hasRole", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
		return NO;
	}
	
	OOJS_RETURN_BOOL([thisEnt hasRole:role]);
	
	OOJS_NATIVE_EXIT
}


// ejectItem(role : String) : Ship
static JSBool ShipEjectItem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(role == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"ejectItem", MIN(argc, 1U), OOJS_ARGV, nil, @"string (role)");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([thisEnt ejectShipOfRole:role]);
	
	OOJS_NATIVE_EXIT
}


// ejectSpecificItem(itemKey : String) : Ship
static JSBool ShipEjectSpecificItem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*itemKey = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  itemKey = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(itemKey == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"ejectSpecificItem", MIN(argc, 1U), OOJS_ARGV, nil, @"string (ship key)");
		return NO;
	}
	
	OOJS_RETURN_OBJECT([thisEnt ejectShipOfType:itemKey]);
	
	OOJS_NATIVE_EXIT
}


// dumpCargo() : Ship
static JSBool ShipDumpCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (EXPECT_NOT([thisEnt isPlayer] && [(PlayerEntity *)thisEnt isDocked]))
	{
		OOJSReportWarningForCaller(context, @"PlayerShip", @"dumpCargo", @"Can't dump cargo while docked, ignoring.");
		OOJS_RETURN_NULL;
	}
	
	OOJS_RETURN_OBJECT([thisEnt dumpCargoItem]);
	
	OOJS_NATIVE_EXIT
}


// spawn(role : String [, number : count]) : Array
static JSBool ShipSpawn(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*role = nil;
	int32					count = 1;
	BOOL					gotCount = YES;
	NSArray					*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  role = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 1)  gotCount = JS_ValueToInt32(context, OOJS_ARGV[1], &count);
	if (EXPECT_NOT(role == nil || !gotCount || count < 1 || count > 64))
	{
		OOJSReportBadArguments(context, @"Ship", @"spawn", MIN(argc, 1U), OOJS_ARGV, nil, @"role and optional quantity (1 to 64)");
		return NO;
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	result = [thisEnt spawnShipsWithRole:role count:count];
	OOJS_END_FULL_NATIVE

	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}


// dealEnergyDamage(). Replaces AI's dealEnergyDamageWithinDesiredRange
static JSBool ShipDealEnergyDamage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	jsdouble baseDamage;
	jsdouble range;
	jsdouble velocityBias = 0.0;
	BOOL gotDamage;
	BOOL gotRange;
	BOOL gotVBias;
	GET_THIS_SHIP(thisEnt);

	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"damage and range needed");
		return NO;
	}
	
	gotDamage = JS_ValueToNumber(context, OOJS_ARGV[0], &baseDamage);
	if (EXPECT_NOT(baseDamage < 0))
	{
		OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"damage must be positive");
		return NO;
	}
	gotRange = JS_ValueToNumber(context, OOJS_ARGV[1], &range);
	if (EXPECT_NOT(range < 0))
	{
		OOJSReportBadArguments(context, @"Ship", @"dealEnergyDamage", argc, OOJS_ARGV, nil, @"range must be positive");
		return NO;
	}
	if (argc >= 3) 
	{
		gotVBias = JS_ValueToNumber(context, OOJS_ARGV[2], &velocityBias);
	}

	[thisEnt dealEnergyDamage:(GLfloat)baseDamage atRange:(GLfloat)range withBias:(GLfloat)velocityBias];

	return YES;

	OOJS_NATIVE_EXIT
}


// explode()
static JSBool ShipExplode(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	return RemoveOrExplodeShip(context, argc, vp, YES);
	
	OOJS_NATIVE_EXIT
}


// remove([suppressDeathEvent : Boolean = false])
static JSBool ShipRemove(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	JSBool					suppressDeathEvent = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if ([thisEnt isPlayer])
	{
		OOJSReportError(context, @"Cannot remove() player's ship.");
		return NO;
	}
	
	if (argc > 0 && EXPECT_NOT(!JS_ValueToBoolean(context, OOJS_ARGV[0], &suppressDeathEvent)))
	{
		OOJSReportBadArguments(context, @"Ship", @"remove", argc, OOJS_ARGV, nil, @"boolean");
		return NO;
	}

	[thisEnt doScriptEvent:OOJSID("shipRemoved") withArgument:[NSNumber numberWithBool:suppressDeathEvent]];

	if (suppressDeathEvent)
	{
		[thisEnt removeScript];
	}
	return RemoveOrExplodeShip(context, argc, vp, NO);
	
	OOJS_NATIVE_EXIT
}


// __runLegacyScriptActions(target : Ship, actions : Array)
static JSBool ShipRunLegacyScriptActions(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	PlayerEntity			*player = nil;
	ShipEntity				*target = nil;
	NSArray					*actions = nil;
	
	player = OOPlayerForScripting();
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 1)  actions = OOJSNativeObjectFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(argc != 2 ||
				   !JSVAL_IS_OBJECT(OOJS_ARGV[0]) ||
				   !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &target) ||
				   ![actions isKindOfClass:[NSArray class]]))
	{
		OOJSReportBadArguments(context, @"Ship", @"__runLegacyScriptActions", argc, OOJS_ARGV, nil, @"target and array of actions");
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
static JSBool ShipCommsMessage(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*message = nil;
	ShipEntity				*target = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  message = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(message == nil || (argc > 1 && (!JSVAL_IS_OBJECT(OOJS_ARGV[1]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[1]), &target)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"commsMessage", MIN(argc, 1U), OOJS_ARGV, nil, @"message and optional target");
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
static JSBool ShipFireECM(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	BOOL					OK;
	
	GET_THIS_SHIP(thisEnt);
	
	OK = [thisEnt fireECM];
	if (!OK)
	{
		OOJSReportWarning(context, @"Ship %@ was requested to fire ECM burst but does not carry ECM equipment.", [thisEnt oo_jsDescription]);
	}
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


// abandonShip()
static JSBool ShipAbandonShip(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	OOJS_RETURN_BOOL([thisEnt hasEscapePod] && [thisEnt abandonShip]);
	
	OOJS_NATIVE_EXIT
}


// canAwardEquipment(type : equipmentInfoExpression)
static JSBool ShipCanAwardEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	OOEquipmentType				*eqType = nil;
	BOOL						result;
	BOOL						isBerth;
	BOOL						exists;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  key = JSValueToEquipmentKeyRelaxed(context, OOJS_ARGV[0], &exists);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"canAwardEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type");
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


// awardEquipment(type : equipmentInfoExpression) : Boolean
static JSBool ShipAwardEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	OOEquipmentType				*eqType = nil;
	NSString					*identifier = nil;
	BOOL						OK = YES;
	BOOL						berth;
	BOOL            isRepair = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(eqType == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"awardEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type");
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
				isRepair = [thisEnt hasEquipmentItem:[identifier stringByAppendingString:@"_DAMAGED"]];
				OK = [player addEquipmentItem:identifier withValidation:YES];
				if (OK && isRepair) 
				{
					[player doScriptEvent:OOJSID("equipmentRepaired") withArgument:identifier];
				}
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
				OK = [thisEnt addEquipmentItem:identifier withValidation:YES];	
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
static JSBool ShipRemoveEquipment(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity					*thisEnt = nil;
	NSString					*key = nil;
	BOOL						OK = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"removeEquipment", MIN(argc, 1U), OOJS_ARGV, nil, @"equipment type");
		return NO;
	}
	// berths are not in hasOneEquipmentItem
	OK = [thisEnt hasOneEquipmentItem:key includeMissiles:YES whileLoading:NO] || ([key isEqualToString:@"EQ_PASSENGER_BERTH"] && [thisEnt passengerCapacity] > 0);
	if (!OK)
	{
		// Allow removal of damaged equipment.
		key = [key stringByAppendingString:@"_DAMAGED"];
		OK = [thisEnt hasOneEquipmentItem:key includeMissiles:NO whileLoading:NO];
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


// restoreSubEntities()
static JSBool ShipRestoreSubEntities(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	OOUInteger				numSubEntitiesRestored = 0U;
	
	GET_THIS_SHIP(thisEnt);
	
	OOUInteger subCount = [[thisEnt subEntitiesForScript] count];
	
	[thisEnt clearSubEntities];
	[thisEnt setUpSubEntities];
	
	if ([[thisEnt subEntitiesForScript] count] - subCount > 0)  numSubEntitiesRestored = [[thisEnt subEntitiesForScript] count] - subCount;
	
	// for each subentitiy restored, slightly increase the trade-in factor
	if ([thisEnt isPlayer])  [(PlayerEntity *)thisEnt adjustTradeInFactorBy:(PLAYER_SHIP_SUBENTITY_TRADE_IN_VALUE * numSubEntitiesRestored)];
	
	OOJS_RETURN_BOOL(numSubEntitiesRestored > 0);
	
	OOJS_NATIVE_EXIT
}



// setEquipmentStatus(type : equipmentInfoExpression, status : String)
static JSBool ShipSetEquipmentStatus(JSContext *context, uintN argc, jsval *vp)
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
		OOJSReportError(context, @"Cannot set equipment status while in strict mode.");
		return NO;
	}
	
	if (argc < 2)
	{
		OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", argc, OOJS_ARGV, nil, @"equipment type and status");
		return NO;
	}
	
	eqType = JSValueToEquipmentType(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(eqType == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", 1, &OOJS_ARGV[0], nil, @"equipment type");
		return NO;
	}
	
	status = OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(status == nil))
	{
		OOJSReportBadArguments(context, @"Ship", @"setEquipmentStatus", 1, &OOJS_ARGV[1], nil, @"equipment status");
		return NO;
	}
	
	// EMMSTRAN: use interned strings.
	if (![status isEqualToString:@"EQUIPMENT_OK"] && ![status isEqualToString:@"EQUIPMENT_DAMAGED"])
	{
		OOJSReportErrorForCaller(context, @"Ship", @"setEquipmentStatus", @"Second parameter for setEquipmentStatus must be either \"EQUIPMENT_OK\" or \"EQUIPMENT_DAMAGED\".");
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
				[(PlayerEntity*)thisEnt addEquipmentItem:(hasOK ? damagedKey : key) withValidation:NO];
				if (hasOK)
				{
					[(PlayerEntity*)thisEnt doScriptEvent:OOJSID("equipmentDamaged") withArgument:key];
				}
				else if (hasDamaged)
				{
					[(PlayerEntity*)thisEnt doScriptEvent:OOJSID("equipmentRepaired") withArgument:key];
				}
				
				// if player's Docking Computers are set to EQUIPMENT_DAMAGED while on, stop them
				if (hasOK && [key isEqualToString:@"EQ_DOCK_COMP"])  [(PlayerEntity*)thisEnt disengageAutopilot];
			}
			else
			{
				[thisEnt addEquipmentItem:(hasOK ? damagedKey : key) withValidation:NO];
				if (hasOK) [thisEnt doScriptEvent:OOJSID("equipmentDamaged") withArgument:key];
			}
		}
	}
	else
	{
		if (hasOK && ![status isEqualToString:@"EQUIPMENT_OK"])
		{
			OOJSReportWarning(context, @"Equipment %@ cannot be damaged.", key);
			hasOK = NO;
		}
	}
	
	OOJS_RETURN_BOOL(hasOK || hasDamaged);
	
	OOJS_NATIVE_EXIT
}


// equipmentStatus(type : equipmentInfoExpression) : String
static JSBool ShipEquipmentStatus(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	/*
		Interned string constants.
		Interned strings are guaranteed to survive for the lifetime of the JS
		runtime, which lasts as long as Oolite is running.
	*/
	static jsval strOK, strDamaged, strUnavailable, strUnknown;
	static BOOL inited = NO;
	if (EXPECT_NOT(!inited))
	{
		inited = YES;
		strOK = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_OK"));
		strDamaged = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_DAMAGED"));
		strUnavailable = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_UNAVAILABLE"));
		strUnknown = STRING_TO_JSVAL(JS_InternString(context, "EQUIPMENT_UNKNOWN"));
	}
	
	ShipEntity				*thisEnt = nil;
	NSString				*key = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  key = JSValueToEquipmentKey(context, OOJS_ARGV[0]);
	if (EXPECT_NOT(key == nil))
	{
		if (argc > 0 && JSVAL_IS_STRING(OOJS_ARGV[0]))
		{
			OOJS_RETURN(strUnknown);
		}
		
		OOJSReportBadArguments(context, @"Ship", @"equipmentStatus", MIN(argc, 1U), &OOJS_ARGV[0], nil, @"equipment type");
		return NO;
	}
	
	if ([thisEnt hasEquipmentItem:key includeWeapons:YES whileLoading:NO])  OOJS_RETURN(strOK);
	else if ([thisEnt hasEquipmentItem:[key stringByAppendingString:@"_DAMAGED"]])  OOJS_RETURN(strDamaged);
	
	OOJS_RETURN(strUnavailable);
	
	OOJS_NATIVE_EXIT
}


// selectNewMissile()
static JSBool ShipSelectNewMissile(JSContext *context, uintN argc, jsval *vp)
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
static JSBool ShipFireMissile(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	id					result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  result = [thisEnt fireMissileWithIdentifier:OOStringFromJSValue(context, OOJS_ARGV[0]) andTarget:[thisEnt primaryTarget]];
	else  result = [thisEnt fireMissile];
	
	OOJS_RETURN_OBJECT(result);
	
	OOJS_NATIVE_EXIT
}

// setBounty(amount, reason)
static JSBool ShipSetBounty(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*reason = nil;
	int32					newbounty = 0;
	BOOL					gotBounty = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  gotBounty = JS_ValueToInt32(context, OOJS_ARGV[0], &newbounty);
	if (argc > 1)  reason = OOStringFromJSValue(context, OOJS_ARGV[1]);
	if (EXPECT_NOT(reason == nil || !gotBounty || newbounty < 0))
	{
		OOJSReportBadArguments(context, @"Ship", @"setBounty", argc, OOJS_ARGV, nil, @"new bounty and reason");
		return NO;
	}
	
	[thisEnt setBounty:(OOCreditsQuantity)newbounty withReasonAsString:reason];
	
	return YES;
	
	OOJS_NATIVE_EXIT
}


// setCargo(cargoType : String [, number : count])
static JSBool ShipSetCargo(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	NSString				*cargoType = nil;
	OOCommodityType			commodity = COMMODITY_UNDEFINED;
	int32					count = 1;
	BOOL					gotCount = YES;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc > 0)  cargoType = OOStringFromJSValue(context, OOJS_ARGV[0]);
	if (argc > 1)  gotCount = JS_ValueToInt32(context, OOJS_ARGV[1], &count);
	if (EXPECT_NOT(cargoType == nil || !gotCount || count < 1))
	{
		OOJSReportBadArguments(context, @"Ship", @"setCargo", argc, OOJS_ARGV, nil, @"cargo name and optional positive quantity");
		return NO;
	}
	
	commodity = [UNIVERSE commodityForName:cargoType];
	if (commodity != COMMODITY_UNDEFINED)  [thisEnt setCommodityForPod:commodity andAmount:count];
	
	OOJS_RETURN_BOOL(commodity != COMMODITY_UNDEFINED);
	
	OOJS_NATIVE_EXIT
}


// setMaterials(params: dict, [shaders: dict])  // sets materials dictionary. Optional parameter sets the shaders dictionary too.
static JSBool ShipSetMaterials(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	if (argc < 1)
	{
		OOJSReportBadArguments(context, @"Ship", @"setMaterials", 0, OOJS_ARGV, nil, @"parameter object");
		return NO;
	}
	
	GET_THIS_SHIP(thisEnt);
	
	return ShipSetMaterialsInternal(context, argc, vp, thisEnt, NO);
	
	OOJS_NATIVE_EXIT
}


// setShaders(params: dict) 
static JSBool ShipSetShaders(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity				*thisEnt = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	if (argc < 1)
	{
		OOJSReportBadArguments(context, @"Ship", @"setShaders", 0, OOJS_ARGV, nil, @"parameter object");
		return NO;
	}
	
	if (JSVAL_IS_NULL(OOJS_ARGV[0]) || (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !JSVAL_IS_OBJECT(OOJS_ARGV[0])))
	{
		// EMMSTRAN: JS_ValueToObject() and normal error handling here.
		OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setShaders", @"object", [NSString stringWithJavaScriptValue:OOJS_ARGV[0] inContext:context]);
		OOJS_RETURN_BOOL(NO);
	}
	
	OOJS_ARGV[1] = OOJS_ARGV[0];
	return ShipSetMaterialsInternal(context, argc, vp, thisEnt, YES);
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipSetMaterialsInternal(JSContext *context, uintN argc, jsval *vp, ShipEntity *thisEnt, BOOL fromShaders)
{
	OOJS_PROFILE_ENTER
	
	JSObject				*params = NULL;
	NSDictionary			*materials;
	NSDictionary			*shaders;
	BOOL					withShaders = NO;
	BOOL					success = NO;
	
	GET_THIS_SHIP(thisEnt);
	
	if (JSVAL_IS_NULL(OOJS_ARGV[0]) || (!JSVAL_IS_NULL(OOJS_ARGV[0]) && !JSVAL_IS_OBJECT(OOJS_ARGV[0])))
	{
		OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.", @"setMaterials", @"object", [NSString stringWithJavaScriptValue:OOJS_ARGV[0] inContext:context]);
		OOJS_RETURN_BOOL(NO);
	}
	
	if (argc > 1)
	{
		withShaders = YES;
		if (JSVAL_IS_NULL(OOJS_ARGV[1]) || (!JSVAL_IS_NULL(OOJS_ARGV[1]) && !JSVAL_IS_OBJECT(OOJS_ARGV[1])))
		{
			OOJSReportWarning(context, @"Ship.%@: expected %@ instead of '%@'.",  @"setMaterials", @"object as second parameter", [NSString stringWithJavaScriptValue:OOJS_ARGV[1] inContext:context]);
			withShaders = NO;
		}
	}
	
	if (fromShaders)
	{
		materials = [[thisEnt mesh] materials];
		params = JSVAL_TO_OBJECT(OOJS_ARGV[0]);
		shaders = OOJSNativeObjectFromJSObject(context, params);
	}
	else
	{
		params = JSVAL_TO_OBJECT(OOJS_ARGV[0]);
		materials = OOJSNativeObjectFromJSObject(context, params);
		if (withShaders)
		{
			params = JSVAL_TO_OBJECT(OOJS_ARGV[1]);
			shaders = OOJSNativeObjectFromJSObject(context, params);
		}
		else
		{
			shaders = [[thisEnt mesh] shaders];
		}
	}
	
	OOJS_BEGIN_FULL_NATIVE(context)
	NSDictionary 			*shipDict = [thisEnt shipInfoDictionary];
	
	// First we test to see if we can create the mesh.
	OOMesh *mesh = [OOMesh meshWithName:[shipDict oo_stringForKey:@"model"]
							   cacheKey:nil
					 materialDictionary:materials
					  shadersDictionary:shaders
								 smooth:[shipDict oo_boolForKey:@"smooth" defaultValue:NO]
						   shaderMacros:[[ResourceManager materialDefaults] oo_dictionaryForKey:@"ship-prefix-macros"]
					shaderBindingTarget:thisEnt];
	
	if (mesh != nil)
	{
		[thisEnt setMesh:mesh];
		success = YES;
	}
	OOJS_END_FULL_NATIVE
	
	OOJS_RETURN_BOOL(success);
	
	OOJS_PROFILE_EXIT
}


// exitSystem([int systemID])
static JSBool ShipExitSystem(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_NATIVE_ENTER(context)
	
	ShipEntity			*thisEnt = nil;
	int32				systemID = -1;
	BOOL				OK = NO;
	
	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT([thisEnt isPlayer]))
	{
		OOJSReportErrorForCaller(context, @"Ship", @"exitSystem", @"Not valid for player ship.");
		return NO;
	}
	
	if (argc > 0)
	{
		if (!JS_ValueToInt32(context, OOJS_ARGV[0], &systemID) || systemID < 0 || 255 < systemID)
		{
			OOJSReportBadArguments(context, @"Ship", @"exitSystem", MIN(argc, 1U), OOJS_ARGV, nil, @"system ID");
			return NO;
		}
	}
	
	OK = [thisEnt performHyperSpaceToSpecificSystem:systemID]; 	// -1 == random destination system
	
	OOJS_RETURN_BOOL(OK);
	
	OOJS_NATIVE_EXIT
}


static JSBool ShipUpdateEscortFormation(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt updateEscortFormation];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static BOOL RemoveOrExplodeShip(JSContext *context, uintN argc, jsval *vp, BOOL explode)
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
			OOJSReportError(context, @"Cannot explode() player's ship while docked.");
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

static JSBool ShipClearDefenseTargets(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	GET_THIS_SHIP(thisEnt);
	[thisEnt clearDefenseTargets];
	
	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


static JSBool ShipAddDefenseTarget(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity *thisEnt = nil;
	ShipEntity				*target = nil;

	GET_THIS_SHIP(thisEnt);
	if (EXPECT_NOT(argc == 0 || (argc > 0 && (!JSVAL_IS_OBJECT(OOJS_ARGV[0]) || !JSShipGetShipEntity(context, JSVAL_TO_OBJECT(OOJS_ARGV[0]), &target)))))
	{
		OOJSReportBadArguments(context, @"Ship", @"addDefenseTarget", 1U, OOJS_ARGV, nil, @"target");
		return NO;
	}
	
	[thisEnt addDefenseTarget:target];

	OOJS_RETURN_VOID;
	
	OOJS_PROFILE_EXIT
}


//getMaterials()
static JSBool ShipGetMaterials(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity		*thisEnt = nil;
	NSObject			*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	result = [[thisEnt mesh] materials];
	if (result == nil)  result = [NSDictionary dictionary];
	OOJS_RETURN_OBJECT(result);
	
	OOJS_PROFILE_EXIT
}

//getShaders()
static JSBool ShipGetShaders(JSContext *context, uintN argc, jsval *vp)
{
	OOJS_PROFILE_ENTER
	
	ShipEntity		*thisEnt = nil;
	NSObject		*result = nil;
	
	GET_THIS_SHIP(thisEnt);
	
	result = [[thisEnt mesh] shaders];
	if (result == nil)  result = [NSDictionary dictionary];
	OOJS_RETURN_OBJECT(result);
	
	OOJS_PROFILE_EXIT
}
