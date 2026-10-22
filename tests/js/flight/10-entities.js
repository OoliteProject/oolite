// Spawning, finding and removing ships in flight.

function spawnAhead(role, count, distance)
{
	var ps = player.ship;
	return system.addShips(role, count, ps.position.add(ps.vectorForward.multiply(distance || 10000)), 500);
}

test("player is in flight", function ()
{
	assert(player.ship.isInSpace, "not in space");
	assert(!player.ship.docked, "docked");
	assertEqual(player.ship.status, "STATUS_IN_FLIGHT");
	assert(system.mainStation.isValid, "no main station");
});

test("ships can be spawned, found and removed", function ()
{
	var ships = spawnAhead("[adder]", 2);
	assertEqual(ships.length, 2);
	ships.forEach(function (s) { s.primaryRole = "oolite-test-ship"; });
	assertEqual(system.countShipsWithPrimaryRole("oolite-test-ship"), 2);
	assertEqual(system.shipsWithPrimaryRole("oolite-test-ship").length, 2);
	ships.forEach(function (s) { s.remove(true); });
	assertEqual(system.countShipsWithPrimaryRole("oolite-test-ship"), 0);
	assert(!ships[0].isValid, "removed ship is still valid");
});

test("stale ships fail gracefully", function ()
{
	var s = spawnAhead("[adder]", 1)[0];
	s.remove(true);
	assertEqual(s.isValid, false);
	// Removal takes effect at the end of the frame; until then the ship still answers.
	assertType(String(s), "string");
	assertEqual(s.hasRole("oolite-test-no-such-role"), false);
});

test("groups", function ()
{
	var group = system.addGroup("asteroid", 3, player.ship.position.add([0, 20000, 0]), 1000);
	assertEqual(group.ships.length, 3);
	assert(group.containsShip(group.ships[1]), "containsShip");
	group.ships.forEach(function (s) { s.remove(true); });
});

test("filteredEntities finds the player", function ()
{
	var found = system.filteredEntities(this, function (e) { return e.isPlayer; });
	assertEqual(found.length, 1);
	assertEqual(found[0], player.ship);
	// Searching around an entity leaves that entity out.
	assertEqual(system.filteredEntities(this, function (e) { return e.isPlayer; }, player.ship, 1e9).length, 0);
});

test("spawned ships carry cargo and equipment", function ()
{
	var s = spawnAhead("[adder]", 1)[0];
	s.removeEquipment("EQ_ECM");
	assert(s.awardEquipment("EQ_ECM"), "award");
	assertEqual(s.equipmentStatus("EQ_ECM"), "EQUIPMENT_OK");
	s.setBounty(30, "test");
	assertEqual(s.bounty, 30);
	s.remove(true);
});

test("setCrew rejects bad arguments without crashing", function ()
{
	// SpiderMonkey builds crashed on some of these, so the parity probe's method sweep leaves setCrew out.
	var s = spawnAhead("[adder]", 1)[0];
	[[], [undefined], [null], ["nonsense"], [-1], [NaN], [{}], [[1, 2]]].forEach(function (args)
	{
		try { s.setCrew.apply(s, args); } catch (e) {}
	});
	assert(s.isValid, "the ship was lost");
	assert(s.setCrew({ name: "Test Pilot", short_description: "a test pilot", species: "human" }), "a valid crew was refused");
	assertEqual(s.crew.length, 1);
	s.remove(true);
});
