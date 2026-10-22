/*

QuickJS migration probe.

Logs a deterministic dump of what scripts can see, so the same game run can be
diffed between the SpiderMonkey and QuickJS builds. Every line is logged with
message class oojs.probe; tools/js-parity/run_probe.py quits the game when
the probe logs "ready for external quit".

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

	// Objects whose QuickJS ports needed judgement calls.
	$dump("system", system);
	$try("system.info keys", function () { return Object.keys(system.info).sort().join(","); });
	$try("system.info own galaxyID / government / in", function () { return [system.info.hasOwnProperty("galaxyID"), system.info.hasOwnProperty("government"), "government" in system.info]; });
	$try("system.info names count", function () { return Object.getOwnPropertyNames(system.info).length; });
	$try("infoForSystem name", function () { return System.infoForSystem(0, 7).name; });
	$try("system.info set and read", function () { system.info.oojs_probe_key = "x"; return system.info.oojs_probe_key; });
	$try("system.info set null", function () { system.info.oojs_probe_key = null; return system.info.oojs_probe_key; });
	$dump("player", player);
	$try("missionVariables unset", function () { return missionVariables.oojs_probe_unset; });
	$try("missionVariables set/get", function () { missionVariables.oojs_probe = 42; return [missionVariables.oojs_probe, typeof missionVariables.oojs_probe]; });
	$try("missionVariables keys include", function () { return Object.keys(missionVariables).indexOf("oojs_probe") !== -1; });
	$try("missionVariables underscore", function () { missionVariables._oojs = 1; return missionVariables._oojs; });
	$try("worldScripts own probe", function () { return worldScripts.oojs_probe === this || worldScripts.oojs_probe.name; });
	$try("worldScripts keys count", function () { return Object.keys(worldScripts).length; });
	$try("manifest food", function () { return player.ship.manifest.food; });
	$try("manifest keys", function () { return Object.keys(player.ship.manifest).join(","); });
	$try("Timer without new", function () { return Timer(this, function () {}, 1000); });
	$try("Timer with new", function () { var t = new Timer(this, function () {}, 1000); t.stop(); return t.isRunning; });
	$try("oolite.jsVersion", function () { return oolite.jsVersion; });
	$try("Vector3D from entity", function () { return Vector3D(player.ship).squaredDistanceTo(player.ship.position); });
	$try("Quaternion from entity", function () { return Quaternion(player.ship).dot(player.ship.orientation) > 0.999; });
	$try("bad method this", function () { return Ship.prototype.hasRole.call({}, "trader"); });
	// SpiderMonkey 1.8.5 ignored creating properties on primitives even in strict code.
	$try("strict assign to primitive", function () { var s = "x"; s.foo = 1; return s.foo; });
	// SpiderMonkey 1.8.5 const: function-scoped, usable before its declaration.
	$try("legacy const outside block", function () { function f() { if (true) { const k = 5; } return k; } return f(); });
	$try("legacy const before declaration", function () { function g() { var r = typeof c2; const c2 = 1; return r; } return g(); });

	// The hyperspace stage's destination: the neighbour with the most stable government. (Only settable when docked.)
	var destination = system.info.systemsInRange(7).sort(function (a, b) { return (b.government - a.government) || (a.systemID - b.systemID); })[0];
	$try("set targetSystem", function () { player.ship.targetSystem = destination.systemID; return player.ship.targetSystem; });

	// Soak: fly for a while so AI scripts, timers and frame callbacks run; exceptions show in the comparison.
	$p("launching");
	// The soak timer starts once the launch has finished, which takes longer on slow machines.
	this.$after("shipLaunchedFromStation", 300, function () { this.$soakTimer = new Timer(this, this.$endSoak, 3); });
	player.ship.launch();
};

this.$endSoak = function ()
{
	$p("event soakEnd");
	$try("in space", function () { return player.ship.isInSpace; });
	this.$stageSpace();
};

/*	Everything from here on came after the SpiderMonkey removal, and was
	recorded against SpiderMonkey builds of the quickjs-poc branch
	(baseline-spidermonkey-macos.txt) before that became impossible. The probe
	moves through the main game states (flight, hyperspace, docked, galactic
	hyperspace), logging the world-script events that the player's actions
	cause and calling methods whose results do not depend on random traffic.
*/

/*	World-script events whose order and arguments follow from what the probe
	does. Events caused by random traffic (shipSpawned, alertConditionChanged
	and so on) are not recorded, since they differ between runs.
*/
this.$recordedEvents = [
	"shipWillLaunchFromStation", "shipLaunchedFromStation", "shipWillDockWithStation", "shipDockedWithStation",
	"playerStartedJumpCountdown", "playerCancelledJumpCountdown", "playerJumpFailed",
	"shipWillEnterWitchspace", "shipWillExitWitchspace", "shipExitedWitchspace", "playerEnteredNewGalaxy",
	"equipmentAdded", "equipmentRemoved", "missionScreenOpportunity", "missionScreenEnded", "guiScreenChanged",
	"playerEnteredContract", "systemWillPopulate", "playerWillSaveGame", "dayChanged"
];

this.$eventHandlers = {};

this.$recordEvent = function (name, args)
{
	if (!this.$recording) return;
	$p("world event " + name + "(" + Array.prototype.map.call(args, function (a) { return $describe(a, 2); }).join(", ") + ")");
};

this.$recordedEvents.forEach(function (name)
{
	this[name] = function ()
	{
		this.$recordEvent(name, arguments);
		var handler = this.$eventHandlers[name];
		if (handler)
		{
			delete this.$eventHandlers[name];
			handler.apply(this, arguments);
		}
	};
}, this);

// Run fn the next time event name fires, or log a timeout and finish after seconds.
this.$after = function (name, seconds, fn)
{
	var self = this;
	this.$eventHandlers[name] = function ()
	{
		self.$watchdog.stop();
		// Leave the event handler before moving the game on.
		self.$nextTimer = new Timer(self, fn, 0.25);
	};
	this.$watchdog = new Timer(this, function ()
	{
		delete this.$eventHandlers[name];
		$p("timed out waiting for " + name + ", status " + player.ship.status);
		this.$finish();
	}, seconds);
};

this.$stageSpace = function ()
{
	this.$recording = true;
	$p("stage space");
	var ps = player.ship;

	// Maths, with fixed inputs.
	var v = new Vector3D(1, 2, 3), u = new Vector3D(-2, 0.5, 4);
	var q = new Quaternion(1, 0, 0, 0).rotateY(0.5).rotateX(0.25);
	$try("vector add/subtract/multiply", function () { return [v.add(u), v.subtract(u), v.multiply(-1.5)]; });
	$try("vector dot/cross/tripleProduct", function () { return [v.dot(u), v.cross(u), v.tripleProduct(u, [0, 1, 0])]; });
	$try("vector angleTo/distanceTo/magnitude", function () { return [v.angleTo(u), v.distanceTo(u), v.squaredDistanceTo(u), v.magnitude(), v.squaredMagnitude()]; });
	$try("vector direction/rotateBy/rotationTo", function () { return [v.direction(), v.rotateBy(q), v.rotationTo(u), v.rotationTo(u, 0.1)]; });
	$try("vector interpolate", function () { return Vector3D.interpolate(v, u, 0.25); });
	$try("vector from array/string", function () { return [new Vector3D([4, 5, 6]), Vector3D("1 2 3")]; });
	$try("vector random lengths", function () { return [Vector3D.random(5).magnitude() <= 5, Math.round(Vector3D.randomDirection(3).magnitude() * 1e4) / 1e4, Vector3D.randomDirectionAndLength(2).magnitude() <= 2]; });
	$try("vector toString", function () { return v.toString(); });
	$try("vector bad argument", function () { return v.add("not a vector"); });
	$try("quaternion multiply/dot/conjugate", function () { return [q.multiply(q), q.dot(q.conjugate()), q.conjugate()]; });
	$try("quaternion rotate/normalize", function () { return [q.rotate([0, 0, 1], 1.0), q.rotateZ(-0.75), new Quaternion(2, 0, 0, 0).normalize()]; });
	$try("quaternion vectors", function () { return [q.vectorForward(), q.vectorUp(), q.vectorRight()]; });
	$try("quaternion toString/toArray", function () { return [q.toString(), q.toArray()]; });
	$try("quaternion random unit", function () { return Math.round(Quaternion.random().dot(Quaternion.random()) * 0) === 0; });

	// System and galaxy information.
	$try("system id/name/government", function () { return [system.ID, system.name, system.government, system.economy, system.techLevel]; });
	$try("system lookups", function () { return [System.systemNameForID(7), System.systemIDForName("Lave"), System.infoForSystem(1, 7).name]; });
	$try("main bodies", function () { return [system.mainStation, system.mainPlanet.radius, system.sun.radius > 0, system.planets.length]; });
	$try("system.locationFromCode", function () { return system.locationFromCode("WITCHPOINT"); });
	$try("count buoys", function () { return [system.countShipsWithRole("buoy-witchpoint"), system.countShipsWithPrimaryRole("buoy")]; });
	$try("routeToSystem", function () { var r = system.info.routeToSystem(System.infoForSystem(0, 129)); return r && [r.route, Math.round(r.distance * 100) / 100, r.time]; });
	$try("routeToSystem by distance", function () { var r = system.info.routeToSystem(System.infoForSystem(0, 129), "OPTIMIZED_BY_TIME"); return r && r.route.length; });
	$try("distanceToSystem", function () { return system.info.distanceToSystem(System.infoForSystem(0, 129)); });
	$try("systemsInRange", function () { return system.info.systemsInRange(7).map(function (s) { return s.systemID; }).sort(function (a, b) { return a - b; }); });
	$try("filteredSystems", function () { return SystemInfo.filteredSystems(this, function (s) { return s.government === 7 && s.techLevel > 10; }).length; });
	$try("samplePrice", function () { return [system.info.samplePrice("food"), system.info.samplePrice("computers")]; });

	// Spawning near the player, away from random traffic.
	var where = ps.position.add(ps.vectorForward.multiply(8000));
	var group = system.addGroup("asteroid", 3, where, 500);
	$try("addGroup", function () { return group && [group.ships.length, group.leader !== null, group.containsShip(group.ships[0])]; });
	var trader = system.addShips("[adder]", 1, where.add([0, 2000, 0]), 0)[0];
	$try("ship setCargo/cargoList", function () { return [trader.setCargo("food", 2), trader.cargoList.map(function (c) { return c.commodity + ":" + c.quantity; })]; });
	trader.removeEquipment("EQ_ECM"); // Fitted at random.
	$try("ship equipment", function () { return [trader.canAwardEquipment("EQ_ECM"), trader.awardEquipment("EQ_ECM"), trader.equipmentStatus("EQ_ECM"), trader.setEquipmentStatus("EQ_ECM", "EQUIPMENT_DAMAGED"), trader.equipmentStatus("EQ_ECM"), trader.hasEquipmentProviding("EQ_ECM"), trader.removeEquipment("EQ_ECM"), trader.equipmentStatus("EQ_ECM")]; });
	$try("ship bounty", function () { trader.setBounty(25, "probe"); return trader.bounty; });
	$try("ship roles", function () { trader.primaryRole = "oojs-probe"; return [trader.primaryRole, trader.hasRole("oojs-probe"), system.countShipsWithPrimaryRole("oojs-probe")]; });
	$try("ship spawn", function () { var s = trader.spawn("cargopod", 2); return s && s.length; });
	$try("ship AI script", function () { trader.setAI("dumbAI.plist"); trader.switchAI("oolite-traderAI.js"); return trader.AIScript.name; });
	$try("ship script", function () { trader.setScript("oolite-default-ship-script.js"); return trader.script.name; });
	$try("ship dumpCargo", function () { return trader.dumpCargo() !== null; });
	$try("ship explode/stale", function () { var s = trader; s.explode(); return s.isValid; });

	// Player-ship controls.
	$try("player speed/maxSpeed", function () { return [ps.maxSpeed, ps.maxThrust, ps.injectorSpeedFactor]; });
	$try("player compass", function () { return [ps.compassMode, ps.compassTarget]; });
	$try("player scanner zoom", function () { ps.resetScannerZoom(); return ps.scannerDisplayScale; });
	$try("player custom view", function () { return [ps.setCustomView([0, 10, -50], [1, 0, 0, 0], "probe"), ps.viewDirection]; });
	$try("player MFD text", function () { return ps.setMultiFunctionText("oojs_probe", "probe text"); });
	$try("player crosshairs", function () { return ps.crosshairs; });
	$try("player escape pod destination", function () { return player.setEscapePodDestination(null); });

	// Move well clear of the station so nothing blocks the jump, then hyperspace.
	var station = system.mainStation;
	ps.position = station.position.add(station.position.subtract(system.mainPlanet.position).direction().multiply(300000));
	$try("set targetSystem in flight", function () { ps.targetSystem = 0; return ps.targetSystem; });
	$try("begin countdown bad argument", function () { return ps.beginHyperspaceCountdown(2); });
	$try("begin/cancel countdown", function () { var r = ps.beginHyperspaceCountdown(5); ps.cancelHyperspaceCountdown(); return [r, ps.status]; });
	$try("begin countdown", function () { return ps.beginHyperspaceCountdown(5); });
	this.$after("shipExitedWitchspace", 120, this.$stageArrival);
};

this.$stageArrival = function ()
{
	$p("stage arrival");
	var ps = player.ship;
	$try("arrived system", function () { return [system.ID, system.name, galaxyNumber, ps.targetSystem]; });
	$try("fuel after jump", function () { return ps.fuel; });
	$try("arrival bodies", function () { return [system.mainStation !== null, system.mainPlanet !== null, system.countShipsWithRole("buoy-witchpoint")]; });
	$try("previous system", function () { return [system.info.distanceToSystem(System.infoForSystem(galaxyNumber, 7)) > 0]; });
	$try("dockPlayer", function () { return system.mainStation.dockPlayer(); });
	this.$after("shipDockedWithStation", 60, this.$stageDocked);
};

this.$stageDocked = function ()
{
	$p("stage docked");
	var ps = player.ship, station = ps.dockedStation;
	$try("docked at", function () { return [ps.docked, station.isMainStation, ps.status]; });

	// Market and cargo.
	$try("market food", function () { var m = station.market.food; return [typeof m.price, typeof m.quantity, m.legality_export, m.capacity]; });
	$try("setMarketPrice/Quantity", function () { station.setMarketPrice("food", 99); station.setMarketQuantity("food", 7); return [station.market.food.price, station.market.food.quantity]; });
	$try("credits", function () { player.credits = 1000; player.credits += 0.5; return player.credits; });
	$try("manifest set", function () { ps.manifest.food = 3; ps.manifest["computers"] = 1; return [ps.manifest.food, ps.manifest.computers, ps.cargoSpaceUsed, ps.cargoSpaceAvailable]; });
	$try("manifest list", function () { return ps.manifest.list.map(function (c) { return c.commodity + ":" + c.quantity; }); });
	$try("manifest comment", function () { ps.manifest.setComment("food", "probe"); return [ps.manifest.comment("food"), ps.manifest.shortComment("food")]; });
	$try("removeAllCargo", function () { ps.removeAllCargo(); return ps.cargoSpaceUsed; });
	$try("displayNameForCommodity", function () { return [displayNameForCommodity("food"), displayNameForCommodity("gem_stones")]; });

	// Equipment.
	$try("EquipmentInfo", function () { var e = EquipmentInfo.infoForKey("EQ_FUEL_SCOOPS"); return [e.name, e.price, e.techLevel, e.isAvailableToPlayer, e.requiredCargoSpace]; });
	$try("award/remove equipment", function () { return [ps.awardEquipment("EQ_FUEL_SCOOPS"), ps.equipmentStatus("EQ_FUEL_SCOOPS"), ps.removeEquipment("EQ_FUEL_SCOOPS"), ps.equipmentStatus("EQ_FUEL_SCOOPS")]; });
	$try("award unknown equipment", function () { return ps.awardEquipment("EQ_OOJS_NONSENSE"); });
	$try("primed equipment", function () { return ps.setPrimedEquipment("EQ_NONSENSE", true); });

	// Contracts.
	var dest = System.infoForSystem(galaxyNumber, system.ID).systemsInRange(7)[0].systemID;
	$try("addPassenger", function () { return ps.addPassenger("Probe Passenger", system.ID, dest, clock.seconds + 86400, 100); });
	$try("addParcel", function () { return ps.addParcel("Probe parcel", system.ID, dest, clock.seconds + 86400, 50); });
	$try("awardContract", function () { return ps.awardContract(2, "food", system.ID, dest, clock.seconds + 86400, 200); });
	$try("contract lists", function () { return [ps.passengers.length, ps.parcels.length, ps.contracts.length, ps.passengers[0] && ps.passengers[0].name]; });
	$try("removePassenger/Parcel/Contract", function () { return [ps.removePassenger("Probe Passenger"), ps.removeParcel("Probe parcel"), ps.removeContract("food", dest)]; });
	// Reputation changes are partly random, so only their types are compared.
	$try("reputation", function () { player.increaseContractReputation(); player.decreasePassengerReputation(); player.increaseParcelReputation(); return [typeof player.contractReputation, typeof player.passengerReputation, typeof player.parcelReputation]; });

	// Mission state and text.
	$try("mission markSystem", function () { mission.markSystem(dest); mission.markSystem({ system: 3, name: "oojs_probe", markerColor: "redColor" }); mission.unmarkSystem(dest); return Object.keys(mission.markedSystems || {}).length >= 0; });
	$try("mission instructions", function () { mission.setInstructions("Probe instructions", "oojs_probe"); mission.setInstructions(null, "oojs_probe"); return true; });
	$try("expandDescription", function () { return [expandDescription("%H is in galaxy [oojs_probe_nonexistent]"), expandDescription("[credits_word]", {})]; });
	$try("expandMissionText", function () { return expandMissionText("oojs_probe_missing_key"); });
	$try("formatting", function () { return [formatCredits(1234.5, true, true), formatInteger(1234567), clock.clockStringForTime(1000000)]; });
	$try("oolite.compareVersion", function () { return [oolite.compareVersion("1.0"), oolite.compareVersion("99.0")]; });
	$try("Ship data", function () { var d = Ship.shipDataForKey("adder"); return [d.name, d.roles, Ship.keysForRole("oojs-no-such-role")]; });
	$try("Ship keysForRole", function () { return [Ship.keysForRole("adder"), Ship.keysForRole("trader").indexOf("cobra3-trader") !== -1]; });
	$try("setScreenBackground", function () { return [setScreenBackground("oojs-missing.png"), getScreenBackgroundForKey("short_range_chart") !== undefined]; });

	// Mission screen. It stays up until a key press, so the probe launches from it.
	$try("runScreen", function () { return mission.runScreen({ title: "Probe", message: "Probe message", choices: { "1_A": "First", "2_B": "Second" }, screenID: "oojs-probe" }, function (choice) { $p("mission callback " + choice); }); });
	$try("mission screen state", function () { return [ps.guiScreen, mission.screenID]; });
	$try("addMessageText", function () { mission.addMessageText("More probe text"); return true; });

	// Galactic jump, from clear space.
	$try("award galactic drive", function () { return ps.awardEquipment("EQ_GAL_DRIVE"); });
	this.$after("shipLaunchedFromStation", 60, this.$stageGalactic);
	$try("launch from mission screen", function () { ps.launch(); return ps.status; });
};

this.$stageGalactic = function ()
{
	$p("stage galactic");
	var ps = player.ship, station = system.mainStation;
	ps.position = station.position.add(station.position.subtract(system.mainPlanet.position).direction().multiply(300000));
	$try("begin galactic countdown", function () { return ps.beginGalacticHyperspaceCountdown(5); });
	this.$after("playerEnteredNewGalaxy", 120, this.$stageNewGalaxy);
};

this.$stageNewGalaxy = function ()
{
	$p("stage new galaxy");
	$try("galaxy", function () { return [galaxyNumber, player.ship.hasEquipmentProviding("EQ_GAL_DRIVE")]; });
	this.$after("shipExitedWitchspace", 60, function ()
	{
		$try("galaxy system", function () { return [galaxyNumber, system.ID, system.name]; });
		$try("galaxy lookups", function () { return [System.infoForSystem(galaxyNumber, 0).name, System.systemNameForID(0)]; });
		this.$finish();
	});
};

this.$finish = function ()
{
	this.$recording = false;
	/*	run_probe.py quits the game through the debug console when it sees this
		line; quitGame() takes effect after the script returns, so the QuickJS
		build's shutdown leak check runs with no script on the stack.
		quitGame() is the fallback.
	*/
	$p("ready for external quit");
	this.$quitTimer = new Timer(this, function () { log("oojs.probe.quit", "quitting from script"); quitGame(); }, 30);
};
