// The state the standard scenario starts in, and the core world scripts.

test("player starts docked at Lave's main station", function ()
{
	assert(player.ship.docked, "not docked");
	assert(player.ship.dockedStation.isMainStation, "not at the main station");
	assertEqual(galaxyNumber, 0);
	assertEqual(system.ID, 7);
	assertEqual(system.name, "Lave");
	assertEqual(player.ship.status, "STATUS_DOCKED");
});

test("standard commander", function ()
{
	assertEqual(player.ship.dataKey, "cobra3-player");
	assertEqual(player.credits, 100);
	assertEqual(player.legalStatus, "Clean");
	assertEqual(player.score, 0);
	assertEqual(player.ship.fuel, 7);
	assertEqual(player.ship.missiles.length, 3);
});

test("core world scripts are loaded", function ()
{
	var names = Object.keys(worldScripts);
	["oolite-populator", "oolite-contracts-cargo", "oolite-contracts-parcels", "oolite-contracts-passengers",
	 "oolite-constrictor-hunt", "oolite-nova", "oolite-thargoid-plans", "oolite-trumbles", "oolite-libPriorityAI",
	 "oolite-registership", "Oolite Equipment Control", "oolite-primable-equipment-register"].forEach(function (name)
	{
		assert(names.indexOf(name) !== -1, name + " is not loaded");
	});
});

test("world scripts expose their identity", function ()
{
	var pop = worldScripts["oolite-populator"];
	assertEqual(pop.name, "oolite-populator");
	assertType(pop.version, "string");
	assertType(pop.systemWillPopulate, "function");
});

test("global objects exist", function ()
{
	[player, system, missionVariables, worldScripts, mission, oolite, clock, galaxyNumber].forEach(function (o, i)
	{
		assert(o !== undefined && o !== null, "global " + i + " is missing");
	});
	assertType(oolite.version, "object");
	assert(oolite.jsVersionString.indexOf("QuickJS") !== -1, "unexpected engine: " + oolite.jsVersionString);
});

test("clock is consistent", function ()
{
	assertType(clock.seconds, "number");
	assertEqual(clock.days, Math.floor(clock.seconds / 86400));
	assertEqual(clock.clockStringForTime(90061), "0000001:01:01:01");
});
