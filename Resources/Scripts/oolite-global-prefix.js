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


/*jslint bitwise: true, undef: true, undef: true, eqeqeq: true, newcap: true*/
/*global Entity, global, mission, player, Quaternion, Ship, special, system, Vector3D, SystemInfo*/


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2009 the Oolite team.";
this.version		= "1.74";


this.global = (function () { return this; } ).call();


/**** Utilities, not intended to be retired ****/


// Ship.spawnOne(): like spawn(role, 1), but returns the ship rather than an array.
Ship.__proto__.spawnOne = function (role)
{
	var result = this.spawn(role, 1);
	return result ? result[0] : null;
};


// mission.addMessageTextKey(): load mission text from mission.plist and append to mission screen or info screen.
mission.addMessageTextKey = function(textKey)
{
	mission.addMessageText((textKey ? expandMissionText(textKey) : null));
}


/*	string.trim(): remove leading and trailing whitespace.
	Implementation by Steve Leviathan, see:
	http://blog.stevenlevithan.com/archives/faster-trim-javascript
	Note: as of ECMAScript 5th Edition, this will be a core language method.
*/
String.prototype.trim = function ()
{
	var	str = this.replace(/^\s\s*/, ''),
			  ws = /\s/,
			  i = str.length;
	while (ws.test(str.charAt(--i))){}
	return str.slice(0, i + 1);
};


/*	SystemInfo.systemsInRange(): return SystemInfos for all systems within a
	certain distance.
*/
SystemInfo.systemsInRange = function(range)
{
	if (range === undefined)
	{
		range = 7;
	}
	
	var thisSystem = system.info;
	return SystemInfo.filteredSystems(this, function(other)
	{
		return (other.systemID !== thisSystem.systemID) && (thisSystem.distanceToSystem(other) <= range);
	});
}


/**** Backwards-compatibility functions. These will be removed before next stable. ****/

// Define a function that is an alias for another function.
this.defineCompatibilityAlias = function (oldName, newName)
{
	global[oldName] = function ()
	{
		special.jsWarning(oldName + "() is deprecated, use " + newName + "() instead.");
		return global[newName].apply(global, arguments);
	};
};

// Define a read-only property that is an alias for another property.
this.defineCompatibilityGetter = function (constructorName, oldName, newName)
{
	var getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		return this[newName];
	};
	global[constructorName].__proto__.__defineGetter__(oldName, getter);
};

// Define a write-only property that is an alias for another property.
this.defineCompatibilitySetter = function (constructorName, oldName, newName)
{
	var setter = function (value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		this[newName] = value;
	};
	global[constructorName].__proto__.__defineSetter__(oldName, setter);
};

// Define a read/write property that is an alias for another property.
this.defineCompatibilityGetterAndSetter = function (constructorName, oldName, newName)
{
	this.defineCompatibilityGetter(constructorName, oldName, newName);
	this.defineCompatibilitySetter(constructorName, oldName, newName);
};

// Define a write-only property that is an alias for a function.
this.defineCompatibilityWriteOnly = function (constructorName, oldName, funcName)
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
	global[constructorName].__proto__.__defineGetter__(oldName, getter);
	global[constructorName].__proto__.__defineSetter__(oldName, setter);
};

// Define a compatibility getter for a property that's moved to another property.
// Example: to map player.docked to player.ship.docked, this.defineCompatibilitySubGetter("player", "ship", "docked")
this.defineCompatibilitySubGetter = function (singletonName, subName, propName)
{
	var getter = function ()
	{
		special.jsWarning(singletonName + "." + propName + " is deprecated, use " + singletonName + "." + subName + "." + propName + " instead.");
		return this[subName][propName];
	};
	global[singletonName].__defineGetter__(propName, getter);
};

// Define a compatibility setter for a property that's moved to another property.
this.defineCompatibilitySubSetter = function (singletonName, subName, propName)
{
	var setter = function (value)
	{
		special.jsWarning(singletonName + "." + propName + " is deprecated, use " + singletonName + "." + subName + "." + propName + " instead.");
		this[subName][propName] = value;
	};
	global[singletonName].__defineSetter__(propName, setter);
};

// Define a compatibility getter and setter for a property that's moved to another property.
this.defineCompatibilitySubGetterAndSetter = function (singletonName, subName, propName)
{
	this.defineCompatibilitySubGetter(singletonName, subName, propName);
	this.defineCompatibilitySubSetter(singletonName, subName, propName);
};

// Like defineCompatibilitySubGetter() et al, for methods.
this.defineCompatibilitySubMethod = function (singletonName, subName, methodName)
{
	global[singletonName][methodName] = function ()
	{
		special.jsWarning(singletonName + "." + methodName + "() is deprecated, use " + singletonName + "." + subName + "." + methodName + "() instead.");
		var sub = this[subName];
		return sub[methodName].apply(sub, arguments);
	};
};


/**** To be removed after 1.74 ****/
Entity.__proto__.setPosition = function ()
{
	special.jsWarning("Entity.setPosition() is deprecated, use entity.position = foo instead.");
	this.position = Vector3D.apply(Vector3D, arguments);
};


Entity.__proto__.setOrientation = function ()
{
	special.jsWarning("Entity.setOrientation() is deprecated, use entity.orientation = foo instead.");
	this.orientation = Quaternion.apply(Quaternion, arguments);
};


Planet.__proto__.setTexture = function (texture)
{
	special.jsWarning("Planet.setTexture() is deprecated, use planet.texture = \"foo\" instead.");
	this.texture = texture;
};

// Entity.ID, Entity.entityWithID(), ability to pass an ID instead of an entity


system.__defineGetter__("goingNova", function ()
{
	special.jsWarning("system.goingNova is deprecated, use system.sun.isGoingNova instead.");
	return this.sun.isGoingNova;
});


system.__defineGetter__("goneNova", function ()
{
	special.jsWarning("system.goneNova is deprecated, use system.sun.hasGoneNova instead.");
	return this.sun.hasGoneNova;
});


Ship.__defineGetter__("availableCargoSpace", function ()
{
	special.jsWarning("ship.availableCargoSpace is deprecated, use ship.cargoSpaceAvailable instead.");
	return this.cargoSpaceAvailable;
});


Ship.__defineGetter__("cargoCapacity", function ()
{
	special.jsWarning("ship.cargoCapacity is deprecated, use ship.cargoSpaceCapacity instead.");
	return this.cargoSpaceCapacity;
});


mission.runMissionScreen = function (_messageKey, _backgroundImage, _choiceKey, _shipKey, _musicKey)
{
	special.jsWarning("Mission.runMissionScreen() is deprecated, use Mission.runScreen() instead.");
	// pre-1.74, trying to set mission backgrounds would create background overlays instead: that behaviour is retained here for backward compatibility
	mission.runScreen({music:_musicKey, model:_shipKey, choicesKey:_choiceKey, overlay:_backgroundImage, messageKey:_messageKey});
};

