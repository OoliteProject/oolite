/*

oolite-global-prefix.js

This script is run before any other JavaScript script. It is used to implement
parts of the Oolite JavaScript environment in JavaScript.

Do not override this script! Its functionality is likely to change between
Oolite versions, and functionality may move between the Oolite application and
this script.

“special” is an object provided to the script (as a property) that allows
access to functions otherwise internal to Oolite. Currently, this means the
special.jsWarning() function, which writes a warning to the log and, if
applicable, the debug console.


Oolite
Copyright © 2004-2013 Giles C Williams and contributors

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


/*jslint white: true, undef: true, eqeqeq: true, bitwise: false, regexp: true, newcap: true, immed: true */
/*global Entity, global, mission, player, Quaternion, Ship, special, system, Vector3D, SystemInfo, expandMissionText*/


"use strict";


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2009-2013 the Oolite team.";
this.version		= "1.77.1";


(function (special) {

// Utility to define non-enumerable, non-configurable, permanent methods, to match the behaviour of native methods.
function defineMethod(object, name, implementation)
{
	Object.defineProperty(object, name, { value: implementation, writable: false, configurable: false, enumerable: false });
}


/**** Miscellaneous utilities for public consumption ****
	  Note that these are documented as part of the scripting interface.
	  The fact that they’re currently in JavaScript is an implementation
	  detail and subject to change.
*/

// Ship.spawnOne(): like spawn(role, 1), but returns the ship rather than an array.
defineMethod(Ship.prototype, "spawnOne", function spawnOne(role)
{
	var result = this.spawn(role, 1);
	return result ? result[0] : null;
});


// mission.addMessageTextKey(): load mission text from mission.plist and append to mission screen or info screen.
defineMethod(Mission.prototype, "addMessageTextKey", function addMessageTextKey(textKey)
{
	this.addMessageText((textKey ? expandMissionText(textKey) : null));
});


/*	SystemInfo systemsInRange(): return SystemInfos for all systems within a
	certain distance.
*/
defineMethod(SystemInfo.prototype, "systemsInRange", function systemsInRange(range)
{
	if (range === undefined)
	{
		range = 7;
	}
	
	return SystemInfo.filteredSystems(this, function (other)
	{
		return (other.systemID !== this.systemID) && (this.distanceToSystem(other) <= range);
	});
});


/*	Because of messy history, SystemInfo.systemsInRange() is an alias to
	system.info.systemsInRange(). This usage is discouraged and now undocumented.
	(It should have been deprecated for 1.75, but wasn't.)
*/
defineMethod(SystemInfo, "systemsInRange", function systemsInRange(range)
{
    return system.info.systemsInRange(range);
});


/*	system.scrambledPseudoRandomNumber(salt : Number (integer)) : Number
	
	This function converts system.pseudoRandomNumber to an effectively
	arbitrary different value that is also stable per system. Every combination
	of system and salt produces a different number.
	
	This should generally be used in preference to system.pseudoRandomNumber,
	because multiple OXPs using system.pseudoRandomNumber to make the same kind
	of decision will cause unwanted clustering. For example, if three different
	OXPs add a station to a system when system.pseudoRandomNumber <= 0.25,
	their stations will always appear in the same system. If they instead use
	system.scrambledPseudoRandomNumber() with different salt values, there will
	be no obvious correlation between the different stations’ distributions.
*/
defineMethod(System.prototype, "scrambledPseudoRandomNumber", function scrambledPseudoRandomNumber(salt)
{
	// Convert from float in [0..1) with 24 bits of precision to integer.
	var n = Math.floor(this.pseudoRandomNumber * 16777216.0);
	
	// Add salt to enable generation of different sequences.
	n += salt;
	
	// Scramble with basic LCG psuedo-random number generator.
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	
	// Convert from (effectively) 32-bit signed integer to float in [0..1).
	return n / 4294967296.0 + 0.5;
});


/*	worldScriptNames
	
	List of names of world scripts.
*/
Object.defineProperty(global, "worldScriptNames",
{
	enumerable: true,
	get: function ()
	{
		return Object.keys(global.worldScripts);
	}
});


/*	soundSource.playSound(sound : SoundExpression [, count : Number])
	
	Load a sound and play it.
*/
defineMethod(SoundSource.prototype, "playSound", function playSound(sound, count)
{
	this.sound = sound;
	this.play(count);
});


/**** Default implementations of script methods ****/
/*    (Note: oolite-default-ship-script.js methods aren’t inherited.)
*/

const escortPositions =
[
	// V-shape escort pattern
	new Vector3D(-2, 0, -1),
	new Vector3D( 2, 0, -1),
	new Vector3D(-3, 0, -3),
	new Vector3D( 3, 0, -3)

/*
	// X-shape escort pattern
	new Vector3D(-2, 0,  2),
	new Vector3D( 2, 0,  2),
	new Vector3D(-3, 0, -3),
	new Vector3D( 3, 0, -3)
*/
];

const escortPositionCount = escortPositions.length;
const escortSpacingFactor = 3;


Script.prototype.coordinatesForEscortPosition = function default_coordinatesFromEscortPosition(index)
{
	var highPart = Math.floor(index / escortPositionCount) + 1;
	var lowPart = index % escortPositionCount;
	
	var spacing = this.ship.collisionRadius * escortSpacingFactor * highPart;
	
	return escortPositions[lowPart].multiply(spacing);
};


// timeAccelerationFactor is 1 and read-only in end-user builds.
if (global.timeAccelerationFactor === undefined)
{
	Object.defineProperty(global, "timeAccelerationFactor",
	{
		value: 1,
		writable: false,
		configurable: false,
		enumerable: false
	});
}

})(special);
