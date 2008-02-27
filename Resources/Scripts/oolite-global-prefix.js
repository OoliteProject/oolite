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
Copyright © 2008 Giles C Williams and contributors

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
this.version		= "1.71";


this.global = (function () { return this; } ).call();


/**** Backwards-compatibility functions. These will be removed before next stable. ****/

// Define a function that is an alias for another function.
this.defineCompatibilityAlias = function (oldName, newName)
{
	global[oldName] = function ()
	{
		special.jsWarning(oldName + "() is deprecated, use " + newName + "() instead.");
		global[newName].apply(global, arguments);
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
		special.jsWarning(constructorName + "." + oldName + " is deprecated and read-only.");
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


// To be removed after 1.72
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


// To be removed after 1.71
Entity.__proto__.valid = function ()
{
	special.jsWarning("Entity.valid() is deprecated, use Entity.isValid property instead.");
	return this.isValid;
}


this.defineCompatibilityGetterAndSetter("Player", "legalStatus", "bounty");

Player.__proto__.__defineGetter__("dockedStationName", function ()
{
	special.jsWarning("Player.dockedStationName is deprecated, use Player.dockedStation.shipDescription instead.");
	return this.dockedStation ? this.dockedStation.shipDescription: null;
});

Player.__proto__.__defineGetter__("dockedAtMainStation", function ()
{
	special.jsWarning("Player.dockedAtMainStation is deprecated, use Player.dockedStation.isMainStation instead.");
	return this.dockedStation && this.dockedStation.isMainStation;
});


global.__defineGetter__("planetNumber", function ()
{
	special.jsWarning("planetNumber is deprecated, use system.ID instead.");
	return system.ID;
});


defineCompatibilityWriteOnly("Mission", "missionScreenTextKey", "addMessageTextKey");
defineCompatibilityWriteOnly("Mission", "imageFileName", "setBackgroundImage");
defineCompatibilityWriteOnly("Mission", "musicFileName", "setMusic");
defineCompatibilityWriteOnly("Mission", "choicesKey", "setChoicesKey");
defineCompatibilityWriteOnly("Mission", "instructionsKey", "setInstructionsKey");
