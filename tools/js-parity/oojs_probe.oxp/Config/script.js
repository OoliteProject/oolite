/*

QuickJS migration probe.

Logs a deterministic dump of what scripts can see, so the same game run can be
diffed between the SpiderMonkey and QuickJS builds. Every line is logged with
message class oojs.probe; the run ends by calling quitGame().

*/

"use strict";

this.name = "oojs_probe";
this.version = "1.0";

this.$p = function (msg)
{
	log("oojs.probe", msg);
};

this.$describe = function (value, depth)
{
	if (depth === undefined) depth = 0;
	if (value === null) return "null";
	var type = typeof value;
	if (type === "undefined") return "undefined";
	if (type === "function") return "function";
	if (type === "number") return String(Math.round(value * 1e6) / 1e6);
	if (type === "string") return JSON.stringify(value);
	if (type === "boolean") return String(value);
	if (Array.isArray(value))
	{
		if (depth > 1) return "[array " + value.length + "]";
		return "[" + value.map(function (item) { return $describe(item, depth + 1); }).join(", ") + "]";
	}
	if (value instanceof Vector3D || value instanceof Quaternion)
	{
		return value.constructor.name + value.toArray().map(function (n) { return Math.round(n * 1e4) / 1e4; }).join(",");
	}
	if (value.isValid !== undefined)
	{
		return "<" + (value.isValid ? (value.dataKey || value.name || "entity") : "stale") + ">";
	}
	if (depth > 1) return "{object}";
	var keys = Object.keys(value).sort();
	return "{" + keys.map(function (key) { return key + ":" + $describe(value[key], depth + 1); }).join(", ") + "}";
};

// Log every enumerable property of an object, sorted, each read guarded.
this.$dump = function (label, object)
{
	var keys = [];
	for (var key in object)
	{
		keys.push(key);
	}
	keys.sort();
	$p(label + " keys: " + keys.length);
	for (var i = 0; i < keys.length; i++)
	{
		var value;
		try
		{
			value = $describe(object[keys[i]]);
		}
		catch (e)
		{
			value = "THREW " + e.name;
		}
		$p(label + "." + keys[i] + " = " + value);
	}
};

this.$try = function (label, fn)
{
	try
	{
		$p(label + " -> " + $describe(fn()));
	}
	catch (e)
	{
		$p(label + " THREW " + e.name + ": " + e.message);
	}
};

this.startUp = function ()
{
	$p("event startUp");
	$p("worldScripts: " + Object.keys(worldScripts).sort().join(","));
};

this.startUpComplete = function ()
{
	$p("event startUpComplete");

	var ship = player.ship;
	$dump("player.ship", ship);
	$dump("station", ship.dockedStation);

	// Entity behaviour that does not depend on the ship type.
	$try("ship isShip/isPlayer/isStation", function () { return [ship.isShip, ship.isPlayer, ship.isStation]; });
	$try("station isStation", function () { return ship.dockedStation.isStation; });
	$try("entity toString", function () { return String(ship).length > 0; });
	$try("set read-only property", function () { ship.isValid = false; return ship.isValid; });
	$try("set maxEnergy invalid", function () { ship.maxEnergy = -1; return ship.maxEnergy; });
	$try("construct Ship", function () { return new Ship(); });
	$try("Ship.prototype.isValid", function () { return Ship.prototype.isValid; });

	// SpiderMonkey extensions and quirks that OXPs can observe.
	$try("JSON vector", function () { return JSON.stringify(new Vector3D(1, 2, 3)); });
	$try("JSON quaternion", function () { return JSON.stringify(new Quaternion(1, 0, 0, 0)); });
	$try("vector own keys", function () { return Object.keys(new Vector3D(1, 2, 3)).join(","); });
	$try("ship hasOwnProperty position", function () { return ship.hasOwnProperty("position"); });
	$try("ship hasOwnProperty hasRole", function () { return ship.hasOwnProperty("hasRole"); });
	// Which prototype levels count as own: PlayerShip (direct), Ship (2nd), Entity (3rd).
	$try("player ship own: PlayerShip/Ship/Entity props", function () { return [ship.hasOwnProperty("fuelLeakRate"), ship.hasOwnProperty("speed"), ship.hasOwnProperty("position")]; });
	$try("player ship own keys count", function () { return Object.keys(ship).length; });
	$try("station own: Station/Ship/Entity props", function () { var st = ship.dockedStation; return [st.hasOwnProperty("isMainStation"), st.hasOwnProperty("speed"), st.hasOwnProperty("position")]; });
	$try("station own keys", function () { return Object.keys(ship.dockedStation).length; });
	$try("JSON keys of station", function () { return Object.keys(JSON.parse(JSON.stringify({ v: new Vector3D(1, 2, 3) })).v).join(","); });
	$try("string toSource", function () { return "abc".toSource(); });
	$try("number toSource", function () { return (5).toSource(); });
	$try("object toSource", function () { return ({ a: 1, b: "x" }).toSource(); });
	$try("array toSource", function () { return [1, "two"].toSource(); });
	$try("uneval undefined", function () { return uneval(undefined); });
	$try("vector toSource", function () { return new Vector3D(1, 2, 3).toSource(); });
	$try("function toString", function () { return (function (a) { return a + 1; }).toString(); });
	$try("for-in integer key order", function () { var keys = []; for (var k in { b: 1, 2: 1, a: 1, 1: 1 }) keys.push(k); return keys.join(","); });

	// A script-spawned ship, then the same ship once removed (stale).
	var spawned = system.addShips("[adder]", 1, ship.dockedStation.position.add([0, 0, 50000]), 0);
	this.$spawned = spawned && spawned[0];
	$try("spawned count", function () { return spawned.length; });
	if (this.$spawned)
	{
		$dump("spawned", this.$spawned);
		var sp = this.$spawned;
		$try("ship own: Ship/Entity props", function () { return [sp.hasOwnProperty("speed"), sp.hasOwnProperty("position")]; });
		$try("ship own keys", function () { return Object.keys(sp).join(","); });
		this.$spawned.remove(true);
	}

	this.$staleTimer = new Timer(this, this.$checkStale, 1);
};

this.$checkStale = function ()
{
	var stale = this.$spawned;
	$p("event staleCheck");
	$try("stale isValid", function () { return stale.isValid; });
	$try("stale position", function () { return stale.position; });
	$try("stale name", function () { return stale.name; });
	$try("stale set position", function () { stale.position = [1, 2, 3]; return stale.position; });
	$try("stale method", function () { return stale.hasRole("trader"); });
	$try("stale toString", function () { return String(stale); });

	$p("quitting");
	quitGame();
};
