// After launching from the mission screen and making a galactic jump.

test("the mission screen ended when the player launched", function ()
{
	assert(eventNames().indexOf("shipWillLaunchFromStation") !== -1, "no launch");
	assertEqual($state.missionCallback, null, "mission callback");
});

test("in galaxy 2", function ()
{
	assertEqual(galaxyNumber, 1);
	assertEqual(player.ship.status, "STATUS_IN_FLIGHT");
	assertEqual(player.ship.equipmentStatus("EQ_GAL_DRIVE"), "EQUIPMENT_UNAVAILABLE", "the galactic hyperdrive is used up");
});

test("galactic jump events", function ()
{
	assertEventOrder(["shipWillEnterWitchspace", "playerEnteredNewGalaxy", "shipWillExitWitchspace", "shipExitedWitchspace"]);
	assertEqual(eventArgs("shipWillEnterWitchspace")[0], "galactic jump");
	assertEqual(eventArgs("playerEnteredNewGalaxy"), [1]);
});

test("this galaxy's systems are readable, the old galaxy's coordinates are not", function ()
{
	var here = System.infoForSystem(1, system.ID);
	assertType(here.coordinates, "object");
	assertEqual(System.systemNameForID(system.ID), system.name);
	assertThrows(function () { return System.infoForSystem(0, 7).coordinates; }, /other galaxies/);
});
