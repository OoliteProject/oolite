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
Copyright © 2004-2008 Giles C Williams and contributors

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


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2008 the Oolite team.";
this.version		= "1.72";


this.global = (function () { return this; } ).call();


/**** Utilities, not intended to be retired ****/

// Ship.spawnOne(): like spawn(role, 1), but returns the ship rather than an array.
Ship.__proto__.spawnOne = function (role)
{
	let result = this.spawn(role, 1);
	if (result)  return result[0];
	else  return null;
}


// mission.runMissionScreen(): one-shot mission screen, until we get a proper MissionScreen class.
mission.runMissionScreen = function (messageKey, backgroundImage, choiceKey, shipKey, musicKey)
{
	mission.showShipModel(shipKey);
	mission.setMusic(musicKey);
	mission.setBackgroundImage(backgroundImage);
	mission.showMissionScreen();
	mission.addMessageTextKey(messageKey);
	if (choiceKey)  mission.setChoicesKey(choiceKey);
	mission.setBackgroundImage();
	mission.setMusic();
}


/**** Backwards-compatibility functions. These will be removed before next stable. ****/

// Define a function that is an alias for another function.
this.defineCompatibilityAlias = function (oldName, newName)
{
	global[oldName] = function ()
	{
		special.jsWarning(oldName + "() is deprecated, use " + newName + "() instead.");
		return global[newName].apply(global, arguments);
	}
}

// Define a read-only property that is an alias for another property.
this.defineCompatibilityGetter = function (constructorName, oldName, newName)
{
	let getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		return this[newName];
	}
	global[constructorName].__proto__.__defineGetter__(oldName, getter);
}

// Define a write-only property that is an alias for another property.
this.defineCompatibilitySetter = function (constructorName, oldName, newName)
{
	let setter = function (value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + newName + " instead.");
		this[newName] = value;
	}
	global[constructorName].__proto__.__defineSetter__(oldName, setter);
}

// Define a read/write property that is an alias for another property.
this.defineCompatibilityGetterAndSetter = function (constructorName, oldName, newName)
{
	this.defineCompatibilityGetter(constructorName, oldName, newName);
	this.defineCompatibilitySetter(constructorName, oldName, newName);
}

// Define a write-only property that is an alias for a function.
this.defineCompatibilityWriteOnly = function (constructorName, oldName, funcName)
{
	let getter = function ()
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated and write-only.");
		return undefined;
	}
	let setter = function (value)
	{
		special.jsWarning(constructorName + "." + oldName + " is deprecated, use " + constructorName + "." + funcName + "() instead.");
		this[funcName](value);
	}
	global[constructorName].__proto__.__defineGetter__(oldName, getter);
	global[constructorName].__proto__.__defineSetter__(oldName, setter);
}

// Define a compatibility getter for a property that's moved to another property.
// Example: to map player.docked to player.ship.docked, this.defineCompatibilitySubGetter("Player", "ship", "docked")
this.defineCompatibilitySubGetter = function (constructorName, subName, propName)
{
	let getter = function ()
	{
		special.jsWarning(constructorName + "." + propName + " is deprecated, use " + constructorName + "." + subName + "." + propName + " instead.");
		return this[subName][propName];
	}
	global[constructorName].__proto__.__defineGetter__(propName, getter);
}

// Define a compatibility setter for a property that's moved to another property.
this.defineCompatibilitySubSetter = function (constructorName, subName, propName)
{
	let setter = function (value)
	{
		special.jsWarning(constructorName + "." + propName + " is deprecated, use " + constructorName + "." + subName + "." + propName + " instead.");
		this[subName][propName] = value;
	}
	global[constructorName].__proto__.__defineSetter__(propName, setter);
}

// Define a compatibility getter and setter for a property that's moved to another property.
this.defineCompatibilitySubGetterAndSetter = function (constructorName, subName, propName)
{
	this.defineCompatibilitySubGetter(constructorName, subName, propName);
	this.defineCompatibilitySubSetter(constructorName, subName, propName);
}

// Like defineCompatibilitySubGetter() et al, for methods.
this.defineCompatibilitySubMethod = function (constructorName, subName, methodName)
{
	global[constructorName][methodName] = function ()
	{
		special.jsWarning(constructorName + "." + methodName + "() is deprecated, use " + constructorName + "." + subName + "." + methodName + "() instead.");
		let sub = this[subName];
		return sub[methodName].apply(sub, arguments);
	}
}


/**** To be removed after 1.72 ****/
this.defineCompatibilityAlias("Log", "log");
this.defineCompatibilityAlias("LogWithClass", "log");	// Note that log() acts like LogWithClass() given multiple parameters, but like Log() given one.
this.defineCompatibilityAlias("ExpandDescription", "expandDescription");
this.defineCompatibilityAlias("RandomName", "randomName");
this.defineCompatibilityAlias("DisplayNameForCommodity", "displayNameForCommodity");

mission.resetMissionChoice = function()
{
	special.jsWarning("mission.resetMissionChoice() is deprecated, use mission.choice = null instead.");
	this.choice = null;
}


system.legacy_spawn = function()
{
	special.jsWarning("system.legacy_spawn() is deprecated (and never worked), use Ship.spawn() instead.");
}


system.setSunNova = function(delay)
{
	special.jsWarning("system.setSunNova() is deprecated, use system.sun.goNova() instead.");
	if (this.sun)  this.sun.goNova(delay);
}


/**** To be removed after 1.73 ****/
this.defineCompatibilityGetter("Ship", "maxCargo", "cargoCapacity");

// Lots of Player properties, including inherited ones, moved to playerShip
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "fuelLeakRate");
this.defineCompatibilitySubGetter("Player", "ship", "docked");
this.defineCompatibilitySubGetter("Player", "ship", "dockedStation");
this.defineCompatibilitySubGetter("Player", "ship", "specialCargo");
this.defineCompatibilitySubGetter("Player", "ship", "galacticHyperspaceBehaviour");
this.defineCompatibilitySubGetter("Player", "ship", "galacticHyperspaceFixedCoords");
this.defineCompatibilitySubMethod("Player", "ship", "awardEquipment");
this.defineCompatibilitySubMethod("Player", "ship", "removeEquipment");
this.defineCompatibilitySubMethod("Player", "ship", "hasEquipment");
this.defineCompatibilitySubMethod("Player", "ship", "equipmentStatus");
this.defineCompatibilitySubMethod("Player", "ship", "setEquipmentStatus");
this.defineCompatibilitySubMethod("Player", "ship", "launch");
this.defineCompatibilitySubMethod("Player", "ship", "awardCargo");
this.defineCompatibilitySubMethod("Player", "ship", "canAwardCargo");
this.defineCompatibilitySubMethod("Player", "ship", "removeAllCargo");
this.defineCompatibilitySubMethod("Player", "ship", "useSpecialCargo");
this.defineCompatibilitySubMethod("Player", "ship", "setGalacticHyperspaceBehaviour");
this.defineCompatibilitySubMethod("Player", "ship", "setGalacticHyperspaceFixedCoords");

this.defineCompatibilitySubGetter("Player", "ship", "AI");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "AIState");
this.defineCompatibilitySubGetter("Player", "ship", "beaconCode");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "bounty");
this.defineCompatibilitySubGetter("Player", "ship", "entityPersonality");
this.defineCompatibilitySubGetter("Player", "ship", "escorts");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "fuel");
this.defineCompatibilitySubGetter("Player", "ship", "groupID");
this.defineCompatibilitySubGetter("Player", "ship", "hasHostileTarget");
this.defineCompatibilitySubGetter("Player", "ship", "hasSuspendedAI");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "heatInsulation");
this.defineCompatibilitySubGetter("Player", "ship", "isBeacon");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "isCloaked");
this.defineCompatibilitySubGetter("Player", "ship", "isFrangible");
this.defineCompatibilitySubGetter("Player", "ship", "isJamming");
this.defineCompatibilitySubGetter("Player", "ship", "isPirate");
this.defineCompatibilitySubGetter("Player", "ship", "isPirateVictim");
this.defineCompatibilitySubGetter("Player", "ship", "isPlayer");
this.defineCompatibilitySubGetter("Player", "ship", "isPolice");
this.defineCompatibilitySubGetter("Player", "ship", "isThargoid");
this.defineCompatibilitySubGetter("Player", "ship", "isTrader");
this.defineCompatibilitySubGetter("Player", "ship", "cargoSpaceUsed");
this.defineCompatibilitySubGetter("Player", "ship", "cargoCapacity");
this.defineCompatibilitySubGetter("Player", "ship", "availableCargoSpace");
this.defineCompatibilitySubGetter("Player", "ship", "maxSpeed");
this.defineCompatibilitySubGetter("Player", "ship", "potentialCollider");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "primaryRole");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "reportAIMessages");
this.defineCompatibilitySubGetter("Player", "ship", "roleProbabilities");
this.defineCompatibilitySubGetter("Player", "ship", "roles");
this.defineCompatibilitySubGetter("Player", "ship", "scannerRange");
this.defineCompatibilitySubGetter("Player", "ship", "scriptInfo");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "shipDescription");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "shipDisplayName");
this.defineCompatibilitySubGetter("Player", "ship", "speed");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "desiredSpeed");
this.defineCompatibilitySubGetter("Player", "ship", "subEntities");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "target");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "temperature");
this.defineCompatibilitySubGetter("Player", "ship", "weaponRange");
this.defineCompatibilitySubGetter("Player", "ship", "withinStationAegis");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "trackCloseContacts");
this.defineCompatibilitySubGetter("Player", "ship", "passengerCount");
this.defineCompatibilitySubGetter("Player", "ship", "passengerCapacity");
this.defineCompatibilitySubMethod("Player", "ship", "setScript");
this.defineCompatibilitySubMethod("Player", "ship", "setAI");
this.defineCompatibilitySubMethod("Player", "ship", "switchAI");
this.defineCompatibilitySubMethod("Player", "ship", "exitAI");
this.defineCompatibilitySubMethod("Player", "ship", "reactToAIMessage");
this.defineCompatibilitySubMethod("Player", "ship", "deployEscorts");
this.defineCompatibilitySubMethod("Player", "ship", "dockEscorts");
this.defineCompatibilitySubMethod("Player", "ship", "hasRole");
this.defineCompatibilitySubMethod("Player", "ship", "ejectItem");
this.defineCompatibilitySubMethod("Player", "ship", "ejectSpecificItem");
this.defineCompatibilitySubMethod("Player", "ship", "dumpCargo");
this.defineCompatibilitySubMethod("Player", "ship", "runLegacyScriptActions");
this.defineCompatibilitySubMethod("Player", "ship", "spawn");
this.defineCompatibilitySubMethod("Player", "ship", "explode");

this.defineCompatibilitySubGetter("Player", "ship", "ID");
this.defineCompatibilitySubGetter("Player", "ship", "position");
this.defineCompatibilitySubGetter("Player", "ship", "orientation");
this.defineCompatibilitySubGetter("Player", "ship", "heading");
this.defineCompatibilitySubGetter("Player", "ship", "status");
this.defineCompatibilitySubGetter("Player", "ship", "scanClass");
this.defineCompatibilitySubGetter("Player", "ship", "mass");
this.defineCompatibilitySubGetter("Player", "ship", "owner");
this.defineCompatibilitySubGetterAndSetter("Player", "ship", "energy");
this.defineCompatibilitySubGetter("Player", "ship", "maxEnergy");
this.defineCompatibilitySubGetter("Player", "ship", "isValid");
this.defineCompatibilitySubGetter("Player", "ship", "isShip");
this.defineCompatibilitySubGetter("Player", "ship", "isStation");
this.defineCompatibilitySubGetter("Player", "ship", "isSubEntity");
this.defineCompatibilitySubGetter("Player", "ship", "isPlayer");
this.defineCompatibilitySubGetter("Player", "ship", "isPlanet");
this.defineCompatibilitySubGetter("Player", "ship", "isSun");
this.defineCompatibilitySubGetter("Player", "ship", "distanceTravelled");
this.defineCompatibilitySubGetter("Player", "ship", "spawnTime");
this.defineCompatibilitySubMethod("Player", "ship", "setPosition");
this.defineCompatibilitySubMethod("Player", "ship", "setOrientation");
