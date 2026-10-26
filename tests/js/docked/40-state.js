// Mission variables, credits, cargo and equipment changes while docked.

test("mission variables keep numbers and strings", function ()
{
	missionVariables.oolite_test_number = 42;
	missionVariables.oolite_test_string = "forty-two";
	assertEqual(missionVariables.oolite_test_number, 42);
	assertEqual(missionVariables.oolite_test_string, "forty-two");
	assert(Object.keys(missionVariables).indexOf("oolite_test_number") !== -1, "not listed");
	missionVariables.oolite_test_number = null;
	missionVariables.oolite_test_string = null;
	assertEqual(missionVariables.oolite_test_number, null);
	assert(Object.keys(missionVariables).indexOf("oolite_test_number") === -1, "still listed");
});

test("credits", function ()
{
	var before = player.credits;
	player.credits += 1234.5;
	assertEqual(player.credits, before + 1234.5);
	player.credits = before;
	assertEqual(player.credits, before);
});

test("cargo manifest", function ()
{
	var ps = player.ship;
	var space = ps.cargoSpaceAvailable;
	ps.manifest.food = 2;
	ps.manifest.computers = 1;
	assertEqual(ps.manifest.food, 2);
	assertEqual(ps.cargoSpaceUsed, 3);
	assertEqual(ps.cargoSpaceAvailable, space - 3);
	assertEqual(ps.manifest.list.length, 2);
	ps.removeAllCargo();
	assertEqual(ps.cargoSpaceUsed, 0);
	assertEqual(ps.manifest.food, 0);
});

test("equipment can be awarded, damaged and removed", function ()
{
	var ps = player.ship;
	assertEqual(ps.equipmentStatus("EQ_FUEL_SCOOPS"), "EQUIPMENT_UNAVAILABLE");
	assert(ps.awardEquipment("EQ_FUEL_SCOOPS"), "award failed");
	assertEqual(ps.equipmentStatus("EQ_FUEL_SCOOPS"), "EQUIPMENT_OK");
	assert(ps.setEquipmentStatus("EQ_FUEL_SCOOPS", "EQUIPMENT_DAMAGED"), "damage failed");
	assertEqual(ps.equipmentStatus("EQ_FUEL_SCOOPS"), "EQUIPMENT_DAMAGED");
	ps.removeEquipment("EQ_FUEL_SCOOPS");
	assertEqual(ps.equipmentStatus("EQ_FUEL_SCOOPS"), "EQUIPMENT_UNAVAILABLE");
	assertThrows(function () { ps.awardEquipment("EQ_OOLITE_TEST_NONSENSE"); }, /expected equipment type/);
});

test("market prices and quantities can be set", function ()
{
	var station = player.ship.dockedStation;
	var food = station.market.food;
	station.setMarketPrice("food", 123);
	station.setMarketQuantity("food", 45);
	assertEqual(station.market.food.price, 123);
	assertEqual(station.market.food.quantity, 45);
	station.setMarketPrice("food", food.price);
	station.setMarketQuantity("food", food.quantity);
});
