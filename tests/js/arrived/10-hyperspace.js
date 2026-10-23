// After a hyperspace jump to the neighbouring system chosen while docked.

test("arrived in the destination system", function ()
{
	assertEqual(system.ID, $state.destination);
	assertEqual(galaxyNumber, 0);
	assertEqual(player.ship.status, "STATUS_IN_FLIGHT");
	assert(!system.isInterstellarSpace, "in interstellar space");
});

test("hyperspace events in order", function ()
{
	assertEventOrder(["playerStartedJumpCountdown", "shipWillEnterWitchspace", "systemWillPopulate", "shipWillExitWitchspace", "shipExitedWitchspace"]);
	assertEqual(eventArgs("playerStartedJumpCountdown"), ["standard", 5]);
	assertEqual(eventArgs("shipWillEnterWitchspace"), ["standard jump", $state.destination]);
});

test("the jump used fuel for its distance", function ()
{
	var distance = System.infoForSystem(0, 7).distanceToSystem(system.info);
	assertClose(player.ship.fuel, $state.fuelAtLaunch - distance, 0.051);
});

test("the new system is populated", function ()
{
	assert(system.mainStation && system.mainStation.isValid, "no main station");
	assert(system.mainPlanet && system.mainPlanet.isValid, "no main planet");
	assert(system.sun && system.sun.isValid, "no sun");
	assertEqual(system.countShipsWithRole("buoy-witchpoint"), 1, "witchpoint buoys");
	// Not system.locationFromCode("WITCHPOINT"): that is a random point within scanner range of it.
	var buoy = system.shipsWithRole("buoy-witchpoint")[0];
	assert(player.ship.position.distanceTo(buoy) < 30000, "not near the witchpoint");
});

test("time passed", function ()
{
	assert(clock.seconds > $state.clockAtLaunch, "the clock did not move");
});
