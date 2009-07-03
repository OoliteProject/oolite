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
Copyright © 2004-2009 Giles C Williams and contributors

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
/*global Entity, global, mission, player, Quaternion, Ship, special, system, Vector3D*/


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2009 the Oolite team.";
this.version		= "1.73";


this.global = (function () { return this; } ).call();


/**** Utilities, not intended to be retired ****/

// Ship.spawnOne(): like spawn(role, 1), but returns the ship rather than an array.
Ship.__proto__.spawnOne = function (role)
{
	var result = this.spawn(role, 1);
	return result ? result[0] : null;
};


// mission.runMissionScreen(): one-shot mission screen, until we get a proper MissionScreen class.
mission.runMissionScreen = function (messageKey, backgroundImage, choiceKey, shipKey, musicKey)
{
	mission.showShipModel(shipKey);
	mission.setMusic(musicKey);
	mission.setBackgroundImage(backgroundImage);
	mission.showMissionScreen();
	mission.addMessageTextKey(messageKey);
	if (choiceKey)
	{
		mission.setChoicesKey(choiceKey);
	}
	mission.setBackgroundImage();
	mission.setMusic();
};


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


/**** To be removed after 1.73 ****/
// Ability to pass three numbers instead of vector/array/entity in place of Vector3D, and corresponding for Quaternion.

global.Vector = Vector3D;

this.defineCompatibilityGetter("Ship", "maxCargo", "cargoCapacity");
this.defineCompatibilityGetterAndSetter("Ship", "shipDescription", "name");
this.defineCompatibilityGetterAndSetter("Ship", "shipDisplayName", "displayName");

// Lots of Player properties, including inherited ones, moved to playerShip
this.defineCompatibilitySubGetterAndSetter("player", "ship", "fuelLeakRate");
this.defineCompatibilitySubGetter("player", "ship", "docked");
this.defineCompatibilitySubGetter("player", "ship", "dockedStation");
this.defineCompatibilitySubGetter("player", "ship", "specialCargo");
this.defineCompatibilitySubGetter("player", "ship", "galacticHyperspaceBehaviour");
this.defineCompatibilitySubGetter("player", "ship", "galacticHyperspaceFixedCoords");
this.defineCompatibilitySubMethod("player", "ship", "awardEquipment");
this.defineCompatibilitySubMethod("player", "ship", "removeEquipment");
this.defineCompatibilitySubMethod("player", "ship", "hasEquipment");
this.defineCompatibilitySubMethod("player", "ship", "equipmentStatus");
this.defineCompatibilitySubMethod("player", "ship", "setEquipmentStatus");
this.defineCompatibilitySubMethod("player", "ship", "launch");
this.defineCompatibilitySubMethod("player", "ship", "awardCargo");
this.defineCompatibilitySubMethod("player", "ship", "canAwardCargo");
this.defineCompatibilitySubMethod("player", "ship", "removeAllCargo");
this.defineCompatibilitySubMethod("player", "ship", "useSpecialCargo");
this.defineCompatibilitySubMethod("player", "ship", "setGalacticHyperspaceBehaviour");
this.defineCompatibilitySubMethod("player", "ship", "setGalacticHyperspaceFixedCoords");
this.defineCompatibilitySubMethod("player", "ship", "spawnOne");

this.defineCompatibilitySubGetter("player", "ship", "AI");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "AIState");
this.defineCompatibilitySubGetter("player", "ship", "beaconCode");
//this.defineCompatibilitySubGetterAndSetter("player", "ship", "bounty"); -- bounty is exposed on both player and player.ship
this.defineCompatibilitySubGetter("player", "ship", "entityPersonality");
this.defineCompatibilitySubGetter("player", "ship", "escorts");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "fuel");
this.defineCompatibilitySubGetter("player", "ship", "groupID");
this.defineCompatibilitySubGetter("player", "ship", "hasHostileTarget");
this.defineCompatibilitySubGetter("player", "ship", "hasSuspendedAI");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "heatInsulation");
this.defineCompatibilitySubGetter("player", "ship", "isBeacon");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "isCloaked");
this.defineCompatibilitySubGetter("player", "ship", "isFrangible");
this.defineCompatibilitySubGetter("player", "ship", "isJamming");
this.defineCompatibilitySubGetter("player", "ship", "isPirate");
this.defineCompatibilitySubGetter("player", "ship", "isPirateVictim");
this.defineCompatibilitySubGetter("player", "ship", "isPlayer");
this.defineCompatibilitySubGetter("player", "ship", "isPolice");
this.defineCompatibilitySubGetter("player", "ship", "isThargoid");
this.defineCompatibilitySubGetter("player", "ship", "isTrader");
this.defineCompatibilitySubGetter("player", "ship", "cargoSpaceUsed");
this.defineCompatibilitySubGetter("player", "ship", "cargoCapacity");
this.defineCompatibilitySubGetter("player", "ship", "availableCargoSpace");
this.defineCompatibilitySubGetter("player", "ship", "maxSpeed");
this.defineCompatibilitySubGetter("player", "ship", "potentialCollider");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "primaryRole");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "reportAIMessages");
this.defineCompatibilitySubGetter("player", "ship", "roleProbabilities");
this.defineCompatibilitySubGetter("player", "ship", "roles");
this.defineCompatibilitySubGetter("player", "ship", "scannerRange");
this.defineCompatibilitySubGetter("player", "ship", "scriptInfo");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "shipDescription");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "shipDisplayName");
this.defineCompatibilitySubGetter("player", "ship", "speed");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "desiredSpeed");
this.defineCompatibilitySubGetter("player", "ship", "subEntities");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "target");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "temperature");
this.defineCompatibilitySubGetter("player", "ship", "weaponRange");
this.defineCompatibilitySubGetter("player", "ship", "withinStationAegis");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "trackCloseContacts");
this.defineCompatibilitySubGetter("player", "ship", "passengerCount");
this.defineCompatibilitySubGetter("player", "ship", "passengerCapacity");
this.defineCompatibilitySubMethod("player", "ship", "setScript");
this.defineCompatibilitySubMethod("player", "ship", "setAI");
this.defineCompatibilitySubMethod("player", "ship", "switchAI");
this.defineCompatibilitySubMethod("player", "ship", "exitAI");
this.defineCompatibilitySubMethod("player", "ship", "reactToAIMessage");
this.defineCompatibilitySubMethod("player", "ship", "deployEscorts");
this.defineCompatibilitySubMethod("player", "ship", "dockEscorts");
this.defineCompatibilitySubMethod("player", "ship", "hasRole");
this.defineCompatibilitySubMethod("player", "ship", "ejectItem");
this.defineCompatibilitySubMethod("player", "ship", "ejectSpecificItem");
this.defineCompatibilitySubMethod("player", "ship", "dumpCargo");
this.defineCompatibilitySubMethod("player", "ship", "runLegacyScriptActions");
this.defineCompatibilitySubMethod("player", "ship", "spawn");
this.defineCompatibilitySubMethod("player", "ship", "explode");

this.defineCompatibilitySubGetter("player", "ship", "ID");
this.defineCompatibilitySubGetter("player", "ship", "position");
this.defineCompatibilitySubGetter("player", "ship", "orientation");
this.defineCompatibilitySubGetter("player", "ship", "heading");
this.defineCompatibilitySubGetter("player", "ship", "status");
this.defineCompatibilitySubGetter("player", "ship", "scanClass");
this.defineCompatibilitySubGetter("player", "ship", "mass");
this.defineCompatibilitySubGetter("player", "ship", "owner");
this.defineCompatibilitySubGetterAndSetter("player", "ship", "energy");
this.defineCompatibilitySubGetter("player", "ship", "maxEnergy");
this.defineCompatibilitySubGetter("player", "ship", "isValid");
this.defineCompatibilitySubGetter("player", "ship", "isShip");
this.defineCompatibilitySubGetter("player", "ship", "isStation");
this.defineCompatibilitySubGetter("player", "ship", "isSubEntity");
this.defineCompatibilitySubGetter("player", "ship", "isPlayer");
this.defineCompatibilitySubGetter("player", "ship", "isPlanet");
this.defineCompatibilitySubGetter("player", "ship", "isSun");
this.defineCompatibilitySubGetter("player", "ship", "distanceTravelled");
this.defineCompatibilitySubGetter("player", "ship", "spawnTime");
this.defineCompatibilitySubGetter("player", "ship", "galaxyCoordinates");
this.defineCompatibilitySubGetter("player", "ship", "cursorCoordinates");


player.setPosition = function ()
{
	special.jsWarning("player.setPosition() is deprecated, use player.ship.position = foo instead.");
	this.ship.position = Vector3D.apply(Vector3D, arguments);
};


player.setOrientation = function ()
{
	special.jsWarning("player.setOrientation() is deprecated, use player.ship.orientation = foo instead.");
	this.ship.orientation = Quaternion.apply(Quaternion, arguments);
};


/**** To be removed after 1.74 at the latest ****/
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
