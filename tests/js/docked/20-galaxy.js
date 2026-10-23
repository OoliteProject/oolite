// Every system in every galaxy, through SystemInfo.

test("every system in the galaxy has information", function ()
{
	var g = galaxyNumber;
	{
		for (var s = 0; s < 256; s++)
		{
			var info = System.infoForSystem(g, s);
			assertEqual(info.galaxyID, g, "galaxy of " + g + "/" + s);
			assertEqual(info.systemID, s, "id of " + g + "/" + s);
			assert(typeof info.name === "string" && info.name.length > 0, "name of " + g + "/" + s);
			assert(info.government >= 0 && info.government <= 7, "government of " + info.name);
			assert(info.economy >= 0 && info.economy <= 7, "economy of " + info.name);
			// SystemInfo has the planetinfo.plist keys; System has techLevel.
			assert(info.techlevel >= 0 && info.techlevel <= 15, "tech level of " + info.name);
			assertType(info.coordinates, "object");
		}
	}
});

test("other galaxies' systems have information but no coordinates", function ()
{
	for (var g = 1; g < 8; g++)
	{
		var other = System.infoForSystem(g, 7);
		assertEqual(other.galaxyID, g);
		assert(typeof other.name === "string" && other.name.length > 0, "name in galaxy " + g);
		assertThrows(function () { return other.coordinates; }, /other galaxies/);
	}
});

test("distances are symmetric", function ()
{
	var lave = System.infoForSystem(0, 7);
	lave.systemsInRange(7).forEach(function (other)
	{
		assertClose(lave.distanceToSystem(other), other.distanceToSystem(lave), 1e-9, other.name);
		assert(lave.distanceToSystem(other) <= 7, other.name + " is out of range");
	});
});

test("routes start and end where asked", function ()
{
	var lave = System.infoForSystem(0, 7);
	[0, 50, 100, 129, 200, 255].forEach(function (to)
	{
		var route = lave.routeToSystem(System.infoForSystem(0, to));
		if (route === null)  return;  // Unreachable.
		assertEqual(route.route[0], 7);
		assertEqual(route.route[route.route.length - 1], to);
		assert(route.distance >= lave.distanceToSystem(System.infoForSystem(0, to)) - 1e-9, "route shorter than the straight line to " + to);
	});
});

test("system names and ids round-trip", function ()
{
	for (var s = 0; s < 256; s += 17)
	{
		assertEqual(System.systemIDForName(System.systemNameForID(s)), s);
	}
});

test("system info properties can be set and cleared", function ()
{
	var info = System.infoForSystem(0, 3);
	info.oolite_test_key = "value";
	assertEqual(System.infoForSystem(0, 3).oolite_test_key, "value");
	info.oolite_test_key = null;
	assertEqual(System.infoForSystem(0, 3).oolite_test_key, null);
});
