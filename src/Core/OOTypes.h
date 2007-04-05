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
	INSTINCT_NULL					= 0,
	
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


typedef uint32_t UniversalID;
