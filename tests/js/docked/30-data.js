// Ship, equipment and commodity data.

test("every ship's data can be read", function ()
{
	var keys = Ship.keys();
	assert(keys.length > 100, "only " + keys.length + " ship keys");
	keys.forEach(function (key)
	{
		var data = Ship.shipDataForKey(key);
		assert(data !== null && typeof data === "object", "no data for " + key);
	});
	assert(keys.indexOf("cobra3-player") !== -1, "no cobra3-player");
});

test("ship roles", function ()
{
	var traders = Ship.keysForRole("trader");
	assert(traders.length > 5, "only " + traders.length + " traders");
	assertEqual(Ship.keysForRole("oolite-test-no-such-role"), null);
});

test("every equipment item's properties can be read", function ()
{
	var all = EquipmentInfo.allEquipment;
	assert(all.length > 30, "only " + all.length + " equipment items");
	all.forEach(function (eq)
	{
		assertType(eq.equipmentKey, "string");
		assertType(eq.name, "string");
		assertType(eq.price, "number");
		assertType(eq.techLevel, "number");
		assertEqual(EquipmentInfo.infoForKey(eq.equipmentKey).equipmentKey, eq.equipmentKey);
		for (var p in eq)  { var v = eq[p]; }  // No property throws.
	});
});

test("commodities", function ()
{
	var market = player.ship.dockedStation.market;
	var keys = Object.keys(market);
	assert(keys.indexOf("food") !== -1 && keys.indexOf("gem_stones") !== -1, "missing commodities");
	keys.forEach(function (key)
	{
		assertType(market[key].price, "number", key);
		assertType(market[key].quantity, "number", key);
		assertType(displayNameForCommodity(key), "string", key);
	});
});
