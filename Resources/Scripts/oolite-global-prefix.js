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


"use strict";


this.name			= "oolite-global-prefix";
this.author			= "Jens Ayton";
this.copyright		= "© 2009-2013 the Oolite team.";


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


/*	Mozilla-compatibility polyfills for expansions written against SpiderMonkey (Phase 1 bead
	oo-1gc.6, ADR-0023): toSource()/quote()/uneval(), exactly as tools/oxp-compat-shim ships them
	(bead oo-864), now built in so an expansion whose author is unreachable keeps working without
	the user installing the shim. Each install is guarded, so under SpiderMonkey this is a no-op.
*/
(function ()
{
	// quoteString(): produce a double-quoted, backslash-escaped string
	// literal, the piece both toSource() and quote() need.
	function quoteString(s)
	{
		var out = "\"";
		for (var i = 0; i < s.length; i++)
		{
			var c = s.charAt(i);
			var code = s.charCodeAt(i);
			if (c === "\"" || c === "\\")
			{
				out += "\\" + c;
			}
			else if (c === "\n")
			{
				out += "\\n";
			}
			else if (c === "\r")
			{
				out += "\\r";
			}
			else if (c === "\t")
			{
				out += "\\t";
			}
			else if (code < 0x20 || code === 0x7f)
			{
				var hex = code.toString(16);
				while (hex.length < 2)  hex = "0" + hex;
				out += "\\x" + hex;
			}
			else
			{
				out += c;
			}
		}
		return out + "\"";
	}


	// toSourceValue(): best-effort Object.prototype.toSource()/
	// Array.prototype.toSource() replacement. Recurses through plain
	// objects and arrays; anything else falls back to String(value) inside
	// an eval-safe wrapper where practical, matching the common debug-log
	// use case (logging a data object), not full source reflection.
	function toSourceValue(value, seen)
	{
		if (value === null)  return "null";
		if (value === undefined)  return "undefined";

		var t = typeof value;
		if (t === "string")  return quoteString(value);
		if (t === "number" || t === "boolean")  return String(value);
		if (t === "function")
		{
			return value.name ? "(function " + value.name + "() {...})" : "(function () {...})";
		}

		if (t === "object")
		{
			if (seen.indexOf(value) !== -1)  return "<circular>";
			seen = seen.concat([value]);

			if (Array.isArray(value))
			{
				var items = [];
				for (var i = 0; i < value.length; i++)
				{
					items.push(toSourceValue(value[i], seen));
				}
				return "[" + items.join(", ") + "]";
			}

			var parts = [];
			for (var key in value)
			{
				if (!Object.prototype.hasOwnProperty.call(value, key))  continue;
				parts.push(quoteString(key) + ":" + toSourceValue(value[key], seen));
			}
			return "({" + parts.join(", ") + "})";
		}

		// Unrecognised primitive type (e.g. symbol): fall back to String().
		return String(value);
	}


	// Object.prototype.toSource(): SpiderMonkey removed in Firefox 74.
	if (typeof Object.prototype.toSource !== "function")
	{
		Object.defineProperty(Object.prototype, "toSource", {
			value: function toSource()
			{
				return toSourceValue(this, []);
			},
			writable: true,
			configurable: true,
			enumerable: false
		});
	}

	// Array.prototype.toSource(): same removal; own definition so it wins
	// over the generic Object.prototype one and formats as "[...]" per the
	// historical SpiderMonkey behaviour rather than "({0:..., 1:...})".
	// Own-property test: once Object.prototype.toSource exists, Array.prototype inherits it.
	if (!Object.prototype.hasOwnProperty.call(Array.prototype, "toSource"))
	{
		Object.defineProperty(Array.prototype, "toSource", {
			value: function toSource()
			{
				return toSourceValue(this, []);
			},
			writable: true,
			configurable: true,
			enumerable: false
		});
	}

	// String.prototype.quote(): SpiderMonkey-only, removed in Firefox 37.
	if (typeof String.prototype.quote !== "function")
	{
		Object.defineProperty(String.prototype, "quote", {
			value: function quote()
			{
				return quoteString(this.toString());
			},
			writable: true,
			configurable: true,
			enumerable: false
		});
	}

	// uneval(): SpiderMonkey-only global, removed in Firefox 74. Polyfilled
	// alongside toSource()/quote() since it is the same source-reflection
	// family and the same abandoned expansions that call .toSource() are
	// the ones most likely to also call the bare global.
	if (typeof global.uneval !== "function")
	{
		// Non-enumerable, like SpiderMonkey's own global functions.
		Object.defineProperty(global, "uneval", {
			value: function uneval(value)
			{
				return toSourceValue(value, []);
			},
			writable: true,
			configurable: true,
			enumerable: false
		});
	}
}).call(this);

/*	SpiderMonkey's Array and String "generics" (Array.forEach(array, fn), String.replace(string,
	...)): Mozilla-only statics that call the prototype method with the first argument as `this`.
	Installed only where the engine lacks them, so they are a no-op under SpiderMonkey 1.8.5
	(Phase 1 bead oo-1gc.6, ADR-0023).
*/
(function ()
{
	function installGenerics(ctor, names)
	{
		names.forEach(function (name)
		{
			var method = ctor.prototype[name];
			if (typeof method !== "function" || typeof ctor[name] === "function")  return;
			Object.defineProperty(ctor, name, {
				value: function (self) { return method.apply(self, Array.prototype.slice.call(arguments, 1)); },
				writable: true,
				configurable: true,
				enumerable: false
			});
		});
	}
	installGenerics(Array, ["concat", "every", "filter", "forEach", "indexOf", "join", "lastIndexOf", "map", "pop", "push",
	                        "reduce", "reduceRight", "reverse", "shift", "slice", "some", "sort", "splice", "unshift"]);
	installGenerics(String, ["charAt", "charCodeAt", "concat", "indexOf", "lastIndexOf", "localeCompare", "match", "replace",
	                         "search", "slice", "split", "substr", "substring", "toLocaleLowerCase", "toLocaleUpperCase",
	                         "toLowerCase", "toUpperCase", "trim", "trimLeft", "trimRight"]);
}).call(this);
