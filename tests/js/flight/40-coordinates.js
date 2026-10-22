// Legacy coordinate systems (Vector3D.toCoordinateSystem/fromCoordinateSystem), which need the current system.

test("coordinate systems round-trip", function ()
{
	var v = player.ship.position;
	["wpm", "wpu", "wsm", "wsu", "pwm", "pwu", "psm", "psu", "swm", "swu", "spm", "spu"].forEach(function (cs)
	{
		var there = v.toCoordinateSystem(cs);
		assert(there instanceof Vector3D, cs + " did not give a vector");
		var back = there.fromCoordinateSystem(cs);
		assert(back.distanceTo(v) < 1, cs + ": " + v + " came back as " + back);
	});
});

test("coordinate systems reject bad arguments", function ()
{
	var v = new Vector3D(1, 2, 3);
	assertThrows(function () { v.toCoordinateSystem(); }, /expected coordinate system/);
	assertThrows(function () { v.fromCoordinateSystem(); }, /expected coordinate system/);
});
