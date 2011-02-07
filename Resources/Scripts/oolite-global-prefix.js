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
Copyright © 2004-2011 Giles C Williams and contributors

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
this.copyright		= "© 2009-2011 the Oolite team.";
this.version		= "1.75";


(function (special) {

/**** Built-in in ECMAScript 5, to be removed when Linux builds transition ****/

/*
	Object.defineProperty: subset of ECMAScript 5 standard. In particular, the
	configurable, enumerable and writable properties are not supported.
*/
if (typeof Object.defineProperty !== "function")
{
	Object.defineProperty = function Object_defineProperty(object, property, descriptor)
	{
		if (descriptor.value !== undefined)
		{
			object[property] = descriptor.value;
		}
		else
		{
			if (descriptor.get !== undefined)
			{
				object.__defineGetter__(property, descriptor.get);
			}
			if (descriptor.set !== undefined)
			{
				object.__defineSetter__(property, descriptor.set);
			}
		}
	}
}


//	Object.getPrototypeOf(): ECMAScript 5th Edition eqivalent to __proto__ extension.
if (typeof Object.getPrototypeOf !== "function")
{
	Object.getPrototypeOf = function (object)
	{
		return object.__proto__;
	};
}


/*	Object.keys(): ECMAScript 5th Edition function to get all property keys of an object.
	Compatibility implementation copied from Mozilla developer wiki.
*/
if (typeof Object.keys != "function")
{
	Object.keys = function Object_keys(o)
	{
		var result = [];
		for(var name in o)
		{
			if (o.hasOwnProperty(name))
			result.push(name);
		}
		return result;
	}
}


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

// Array.isArray(object): true if object is an array.
if (typeof Array.isArray !== "function")
{
	Array.isArray = function Array_isArray(object)
	{
		return object && object.constructor === [].constructor;
	}
}


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


/*	SystemInfo.systemsInRange(): return SystemInfos for all systems within a
	certain distance.
*/
defineMethod(SystemInfo, "systemsInRange", function systemsInRange(range)
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
/*    (Note: oolite-default-ship-script.js methods aren’t inherited.
	  TODO: make script subtypes for different types of scriptable thing.
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


/**** Backwards-compatibility functions. These will be removed before next stable. ****/

const failWarning = " This warning will be removed and the script will fail in Oolite 1.75.1.";

// Define a read-only property that is an alias for another property.
function defineCompatibilityGetter(constructorName, oldName, newName)
{
	var getter = function compatibilityGetter()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead." + failWarning);
		return this[newName];
	};
	
	Object.defineProperty(global[constructorName].prototype, oldName, { get: getter });
};


function defineCompatibilityGetterAndSetter(constructorName, oldName, newName)
{
	var getter = function compatibilityGetter()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead." + failWarning);
		return this[newName];
	};
	var setter = function compatibilitySetter(value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead." + failWarning);
		this[newName] = value;
	};
	
	Object.defineProperty(global[constructorName].prototype, oldName, { get: getter, set: setter });
};


defineCompatibilityGetter("Ship", "roleProbabilities", "roleWeights");


if (typeof Object.getOwnPropertyDescriptor == "function")
{
	var isWriteable = function (object, property)
	{
		var descriptor = Object.getOwnPropertyDescriptor(object, property);
		return descriptor.writable || false;
	}
}
else
{
	var isWriteable = function (object, property)
	{
		// No good test. In particular, trying to write a read-only property is not an exception without strict mode.
		return true;
	}
}


function defineSingletonCompatibiltyAccessor(constructorName, singletonName, propertyName, isMethod)
{
	var type = isMethod ? "method" : "property";
	var typedProp = isMethod ? (propertyName + "()") : propertyName;
	var message = "Incorrect usage: " + constructorName + " instance " + type + " “" + propertyName + "” accessed on constructor instead of instance. Replace “" + constructorName + "." + typedProp + "” with “" + singletonName + "." + typedProp + "”." + failWarning;
	
	var descriptor =
	{
		enumerable: false,
		configurable: false,
		
		get: function constructorGetterGlue()
		{
			special.jsWarning(message);
			return global[singletonName][propertyName];
		}
	}
	
	if (!isMethod && isWriteable(global[constructorName].prototype, propertyName))
	{
		descriptor.set = function constructorSetterGlue(value)
		{
			special.jsWarning(message);
			global[singletonName][propertyName] = value;
		}
	}
	
	Object.defineProperty(global[constructorName], propertyName, descriptor);
}


var systemInstanceProperties =
[
	"ID",
//	"name",	// Since a constructor is a function, it already has a non-configurable “name” property.
	"description",
	"inhabitantsDescription",
	"government",
	"governmentDescription",
	"economy",
	"economyDescription",
	"techLevel",
	"population",
	"productivity",
	"isInterstellarSpace",
	"mainStation",
	"mainPlanet",
	"sun",
	"planets",
	"allShips",
	"info",
	"pseudoRandomNumber",
	"pseudoRandom100",
	"pseudoRandom256"
];

var systemInstanceMethods =
[
	"toString",
	"addGroup",
	"addGroupToRoute",
	"addMoon",
	"addPlanet",
	"addShips",
	"addShipsToRoute",
	"countShipsWithPrimaryRole",
	"countShipsWithRole",
	"countEntitiesWithScanClass",
	"entitiesWithScanClass",
	"filteredEntities",
	"sendAllShipsAway",
	"shipsWithPrimaryRole",
	"shipsWithRole",
	"legacy_addShips",
	"legacy_addSystemShips",
	"legacy_addShipsAt",
	"legacy_addShipsAtPrecisely",
	"legacy_addShipsWithinRadius",
	"legacy_spawnShip"
];


var i;
for (i = 0; i < systemInstanceProperties.length; i++)
{
	defineSingletonCompatibiltyAccessor("System", "system", systemInstanceProperties[i], false);
}

for (i = 0; i < systemInstanceMethods.length; i++)
{
	defineSingletonCompatibiltyAccessor("System", "system", systemInstanceMethods[i], true);
}


var playerInstanceProperties =
[
//	"name",	// Since a constructor is a function, it already has a non-configurable “name” property.
	"score",
	"credits",
	"rank",
	"legalStatus",
	"alertCondition",
	"alertTemperature",
	"alertMassLocked",
	"alertAltitude",
	"alertEnergy",
	"alertHostiles",
	"trumbleCount",
	"contractReputation",
	"passengerReputation",
	"dockingClearanceStatus",
	"bounty",
];

var playerInstanceMethods =
[
	"addMessageToArrivalReport",
	"commsMessage",
	"consoleMessage",
	"decreaseContractReputation",
	"decreasePassengerReputation",
	"increaseContractReputation",
	"increasePassengerReputation",
	"setEscapePodDestination"
];


for (i = 0; i < playerInstanceProperties.length; i++)
{
	defineSingletonCompatibiltyAccessor("Player", "player", playerInstanceProperties[i], false);
}

for (i = 0; i < playerInstanceMethods.length; i++)
{
	defineSingletonCompatibiltyAccessor("Player", "player", playerInstanceMethods[i], true);
}

})(special);
