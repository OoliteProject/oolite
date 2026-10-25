// Docked with dockPlayer() in the new system.

test("docked at the new system's main station", function ()
{
	assert(player.ship.docked, "not docked");
	assertEqual(player.ship.dockedStation, system.mainStation);
	assertEqual(system.ID, $state.destination);
});

test("docking events in order", function ()
{
	assertEventOrder(["shipWillDockWithStation", "shipDockedWithStation"]);
	assertEqual(eventArgs("shipDockedWithStation")[0], system.mainStation.dataKey);
});

test("the market is this system's", function ()
{
	var food = player.ship.dockedStation.market.food;
	assertType(food.price, "number");
	assert(food.price > 0, "no food price");
});

test("a mission screen can be shown", function ()
{
	$state.missionCallback = "not called";
	var shown = mission.runScreen({ title: "Test", message: "Test message", choices: { "1_YES": "Yes", "2_NO": "No" }, screenID: "oolite-test" },
		function (choice) { $state.missionCallback = choice; });
	assert(shown, "runScreen returned false");
	assertEqual(mission.screenID, "oolite-test");
	assertEqual(eventNames().slice(-1)[0], "guiScreenChanged");
	assertEqual(eventArgs("guiScreenChanged").slice(-2)[0] !== undefined, true);
});
