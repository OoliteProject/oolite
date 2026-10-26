// Launching from the station.

test("launch events", function ()
{
	assertEventOrder(["shipWillLaunchFromStation", "shipLaunchedFromStation"]);
	assertEqual(eventArgs("shipLaunchedFromStation")[0], system.mainStation.dataKey);
});

test("near the main station after launch", function ()
{
	var d = player.ship.position.distanceTo(system.mainStation);
	assert(d < 20000, "launched " + Math.round(d) + " m from the station");
	assertEqual(player.ship.targetSystem, $state.destination = player.ship.targetSystem);
	assert($state.destination !== system.ID, "no hyperspace destination chosen");
});
