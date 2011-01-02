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
Copyright © 2004-2010 Giles C Williams and contributors

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


// NOTE: for jslint to work, you must comment out the use of __proto__.
/*jslint white: true, undef: true, eqeqeq: true, bitwise: false, regexp: true, newcap: true, immed: true */
/*global Entity, global, mission, player, Quaternion, Ship, special, system, Vector3D, SystemInfo, expandMissionText*/


"use strict";


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2009-2010 the Oolite team.";
this.version		= "1.75";


/**** Utilities, not intended to be retired ****/

//	Object.getPrototypeOf(): ECMAScript 5th Edition eqivalent to __proto__ extension.
if (typeof Object.getPrototypeOf !== "function")
{
	Object.getPrototypeOf = function (object)
	{
		return object.__proto__;
	};
}


// Ship.spawnOne(): like spawn(role, 1), but returns the ship rather than an array.
Object.getPrototypeOf(Ship).spawnOne = function Ship_spawnOne(role)
{
	var result = this.spawn(role, 1);
	return result ? result[0] : null;
};


// mission.addMessageTextKey(): load mission text from mission.plist and append to mission screen or info screen.
mission.addMessageTextKey = function mission_addMessageTextKey(textKey)
{
	mission.addMessageText((textKey ? expandMissionText(textKey) : null));
};


/*	string.trim(): remove leading and trailing whitespace.
	Implementation by Steve Leviathan, see:
	http://blog.stevenlevithan.com/archives/faster-trim-javascript
	Note: as of ECMAScript 5th Edition, this will be a core language method.
*/
if (typeof String.prototype.trim !== "function")
{
	String.prototype.trim = function String_trim()
	{
		var	str = this.replace(/^\s\s*/, ''),
			 ws = /\s/,
			  i = str.length;
		while (ws.test(str.charAt(--i))) {}
		return str.slice(0, i + 1);
	};
}


/*	SystemInfo.systemsInRange(): return SystemInfos for all systems within a
	certain distance.
*/
SystemInfo.systemsInRange = function SystemInfo_systemsInRange(range)
{
	if (range === undefined)
	{
		range = 7;
	}
	
	// Default to using the current system.
	var thisSystem = system.info;
	
	// If called on an instance instead of the SystemInfo constructor, use that system instead.
	if (this !== SystemInfo)
	{
		if (this.systemID !== undefined && this.distanceToSystem !== undefined)
		{
			thisSystem = this;
		}
		else
		{
			special.jsWarning("systemsInRange() called in the wrong context. Returning empty array.");
			return [];
		}
	}
	
	return SystemInfo.filteredSystems(this, function (other)
	{
		return (other.systemID !== thisSystem.systemID) && (thisSystem.distanceToSystem(other) <= range);
	});
};


/*	system.scrambledPseudoRandom(salt : Number (integer)) : Number
	
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
system.scrambledPseudoRandomNumber = function system_scrambledPseudoRandomNumber(salt)
{
	// Convert from float in [0..1) with 24 bits of precision to integer.
	var n = Math.floor(system.pseudoRandomNumber * 16777216.0);
	
	// Add salt to enable generation of different sequences.
	n += salt;
	
	// Scramble with basic LCG psuedo-random number generator.
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	n = (214013 * n + 2531011) & 0xFFFFFFFF;
	
	// Convert from (effectively) 32-bit signed integer to float in [0..1).
	return n / 4294967296.0 + 0.5;
};


/**** Backwards-compatibility functions. These will be removed before next stable. ****/

// Define a function that is an alias for another function.
this._defineCompatibilityAlias = function (oldName, newName)
{
	global[oldName] = function ()
	{
		special.jsWarning(oldName + "() is deprecated, use " + newName + "() instead.");
		return global[newName].apply(global, arguments);
	};
};

// Define a read-only property that is an alias for another property.
this._defineCompatibilityGetter = function (constructorName, oldName, newName)
{
	var getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		return this[newName];
	};
	Object.getPrototypeOf(global[constructorName]).__defineGetter__(oldName, getter);
};

// Define a write-only property that is an alias for another property.
this._defineCompatibilitySetter = function (constructorName, oldName, newName)
{
	var setter = function (value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		this[newName] = value;
	};
	Object.getPrototypeOf(global[constructorName]).__defineSetter__(oldName, setter);
};

// Define a read/write property that is an alias for another property.
this._defineCompatibilityGetterAndSetter = function (constructorName, oldName, newName)
{
	this._defineCompatibilityGetter(constructorName, oldName, newName);
	this._defineCompatibilitySetter(constructorName, oldName, newName);
};

// Define a write-only property that is an alias for a function.
this._defineCompatibilityWriteOnly = function (constructorName, oldName, funcName)
{
	var getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated and write-only.");
		return undefined;
	};
	var setter = function (value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + funcName + "() instead.");
		this[funcName](value);
	};
	Object.getPrototypeOf(global[constructorName]).__defineGetter__(oldName, getter);
	Object.getPrototypeOf(global[constructorName]).__defineSetter__(oldName, setter);
};

// Define a compatibility getter for a property that's moved to another property.
// Example: to map player.docked to player.ship.docked, this._defineCompatibilitySubGetter("player", "ship", "docked")
this._defineCompatibilitySubGetter = function (singletonName, subName, propName)
{
	var getter = function ()
	{
		special.jsWarning(singletonName + "." + propName + " is deprecated, use " + singletonName + "." + subName + "." + propName + " instead.");
		return this[subName][propName];
	};
	global[singletonName].__defineGetter__(propName, getter);
};

// Define a compatibility setter for a property that's moved to another property.
this._defineCompatibilitySubSetter = function (singletonName, subName, propName)
{
	var setter = function (value)
	{
		special.jsWarning(singletonName + "." + propName + " is deprecated, use " + singletonName + "." + subName + "." + propName + " instead.");
		this[subName][propName] = value;
	};
	global[singletonName].__defineSetter__(propName, setter);
};

// Define a compatibility getter and setter for a property that's moved to another property.
this._defineCompatibilitySubGetterAndSetter = function (singletonName, subName, propName)
{
	this._defineCompatibilitySubGetter(singletonName, subName, propName);
	this._defineCompatibilitySubSetter(singletonName, subName, propName);
};

// Like defineCompatibilitySubGetter() et al, for methods.
this._defineCompatibilitySubMethod = function (singletonName, subName, methodName)
{
	global[singletonName][methodName] = function ()
	{
		special.jsWarning(singletonName + "." + methodName + "() is deprecated, use " + singletonName + "." + subName + "." + methodName + "() instead.");
		var sub = this[subName];
		return sub[methodName].apply(sub, arguments);
	};
};
