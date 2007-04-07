/*

OOTypes.h

Various simple types that don't require us to pull in the associated class
headers.

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

#include "OOFunctionAttributes.h"


typedef enum
{
	STATUS_EXPERIMENTAL				= 99,
	STATUS_EFFECT					= 10,
	STATUS_ACTIVE					= 5,
	STATUS_COCKPIT_DISPLAY			= 2,
	STATUS_TEST						= 1,
	STATUS_INACTIVE					= 0,
	STATUS_DEAD						= -1,
	STATUS_START_GAME				= -10,
	STATUS_IN_FLIGHT				= 100,
	STATUS_DOCKED					= 200,
	STATUS_AUTOPILOT_ENGAGED		= 300,
	STATUS_DOCKING					= 401,
	STATUS_LAUNCHING				= 402,
	STATUS_WITCHSPACE_COUNTDOWN 	= 410,
	STATUS_ENTERING_WITCHSPACE  	= 411,
	STATUS_EXITING_WITCHSPACE   	= 412,
	STATUS_ESCAPE_SEQUENCE			= 500,
	STATUS_IN_HOLD					= 600,
	STATUS_BEING_SCOOPED			= 700,
	STATUS_HANDLING_ERROR			= 999
} EntityStatus;


typedef enum
{
	CLASS_NOT_SET					= -1,
	CLASS_NO_DRAW					= 0,
	CLASS_NEUTRAL					= 1,
	CLASS_STATION					= 3,
	CLASS_TARGET					= 4,
	CLASS_CARGO						= 5,
	CLASS_MISSILE					= 6,
	CLASS_ROCK						= 7,
	CLASS_MINE						= 8,
	CLASS_THARGOID					= 9,
	CLASS_BUOY						= 10,
	CLASS_WORMHOLE					= 444,
	CLASS_PLAYER					= 100,
	CLASS_POLICE					= 999,
	CLASS_MILITARY					= 333
} ScanClass;


typedef enum
{
	INSTINCT_NULL					= 0U,
	
	// basic behavioural instincts
	INSTINCT_AVOID_HAZARDS			= 101,
	INSTINCT_FLOCK_ALIKE			= 102,
	
	// threats should be defined
	INSTINCT_FIGHT_OR_FLIGHT		= 103,
	
// 'prey' should be defined
	INSTINCT_ATTACK_PREY			= 105,
	INSTINCT_AVOID_PREDATORS		= 106,
	
	// advanced AI instincts
	INSTINCT_FOLLOW_AI				= 201
} Instinct;


typedef enum
{
	BEHAVIOUR_IDLE							= 0U,
	BEHAVIOUR_TRACK_TARGET					= 1,
//	BEHAVIOUR_FLY_TO_TARGET					= 2,	// Unused
//	BEHAVIOUR_HANDS_OFF						= 3,	// Unused
	BEHAVIOUR_TUMBLE						= 4,
	BEHAVIOUR_STOP_STILL					= 5,
	
	BEHAVIOUR_STATION_KEEPING				= 10,
	
	BEHAVIOUR_ATTACK_TARGET					= 101,
	BEHAVIOUR_ATTACK_FLY_TO_TARGET			= 102,
	BEHAVIOUR_ATTACK_FLY_FROM_TARGET		= 103,
	BEHAVIOUR_RUNNING_DEFENSE				= 104,
	
// fleeing
	BEHAVIOUR_FLEE_TARGET					= 105,
	
// advanced combat...
	BEHAVIOUR_ATTACK_FLY_TO_TARGET_SIX		= 106,
	BEHAVIOUR_ATTACK_MINING_TARGET			= 107,
	
// further advanced combat...
	BEHAVIOUR_ATTACK_FLY_TO_TARGET_TWELVE	= 112,
	
	BEHAVIOUR_AVOID_COLLISION				= 130,
	
	BEHAVIOUR_TRACK_AS_TURRET				= 150,
	
	BEHAVIOUR_FLY_RANGE_FROM_DESTINATION	= 200,
	BEHAVIOUR_FLY_TO_DESTINATION			= 201,
	BEHAVIOUR_FLY_FROM_DESTINATION			= 202,
	BEHAVIOUR_FACE_DESTINATION				= 203,
	
	BEHAVIOUR_FLY_THRU_NAVPOINTS			= 210,
	
	BEHAVIOUR_COLLECT_TARGET				= 300,
	BEHAVIOUR_INTERCEPT_TARGET				= 350,
	
//	BEHAVIOUR_MISSILE_FLY_TO_TARGET			= 901,	// Unused
	
	BEHAVIOUR_FORMATION_FORM_UP				= 501,
	BEHAVIOUR_FORMATION_BREAK				= 502,
	
	BEHAVIOUR_ENERGY_BOMB_COUNTDOWN			= 601,
	
	BEHAVIOUR_TRACTORED						= 701,
	
	BEHAVIOUR_EXPERIMENTAL					= 54321
} Behaviour;


OOINLINE BOOL IsBehaviourHostile(Behaviour behaviour) INLINE_CONST_FUNC;
OOINLINE BOOL IsBehaviourHostile(Behaviour behaviour)
{
	return 100 < behaviour && behaviour < 120;
}


typedef enum
{
	WEAPON_NONE						= 0U,
	WEAPON_PLASMA_CANNON			= 1,
	WEAPON_PULSE_LASER				= 2,
	WEAPON_BEAM_LASER				= 3,
	WEAPON_MINING_LASER				= 4,
	WEAPON_MILITARY_LASER			= 5,
	WEAPON_THARGOID_LASER			= 10
} WeaponType;


typedef enum
{
	AEGIS_NONE,
	AEGIS_CLOSE_TO_PLANET,
	AEGIS_IN_DOCKING_RANGE
} AegisStatus;


typedef enum
{
	CARGO_NOT_CARGO					= -1,
	CARGO_SLAVES					= 3,
	CARGO_ALLOY						= 9,
	CARGO_MINERALS					= 12,
	CARGO_THARGOID					= 16,
	CARGO_RANDOM					= 100,
	CARGO_SCRIPTED_ITEM				= 200,
	CARGO_CHARACTER					= 300
} CargoType;


typedef enum
{
	CARGO_FLAG_NONE					= 400,
	CARGO_FLAG_FULL_PLENTIFUL		= 501,
	CARGO_FLAG_FULL_SCARCE			= 502,
	CARGO_FLAG_PIRATE				= 505,
	CARGO_FLAG_FULL_UNIFORM			= 510,
	CARGO_FLAG_CANISTERS			= 600,
	CARGO_FLAG_FULL_PASSENGERS		= 700
} CargoFlag;


typedef enum
{
	UNITS_TONS,
	UNITS_KILOGRAMS,
	UNITS_GRAMS
} MassUnit;


typedef uint16_t	CargoQuantity;


typedef uint32_t	CreditsQuantity;


typedef uint16_t	KeyCode;


typedef uint16_t UniversalID;	// Valid IDs range from 100 to 1000.
static const UniversalID NO_TARGET = 0;
