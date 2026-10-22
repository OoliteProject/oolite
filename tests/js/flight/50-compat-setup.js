// Ship scripts and the script time limiter; the time limiter is checked in arrived/30-compat.js.
// expect-log: \[script\.javaScript\.timeLimit\]

test("legacy ship scripts: bare names per ship; top-level var per ship (shared under SpiderMonkey)", function ()
{
	var ps = player.ship;
	var ships = system.addShips("oolite-test-compat-ship", 2, ps.position.add(ps.vectorForward.multiply(15000)), 1000);
	assertEqual(ships.length, 2);
	assertEqual(ships[0].script.name, "oolite-test-compat-ship");
	ships[0].script.$tag = "first";
	ships[1].script.$tag = "second";
	assertEqual(ships[0].script.$myTag(), "first");
	assertEqual(ships[1].script.$myTag(), "second");
	assertEqual(ships[0].script.$bump(), 1);
	/*	SpiderMonkey made top-level vars global, so every ship running the script
		shared them; under QuickJS they are local to each ship's copy of the
		script (src/Core/Scripting/README.md).
	*/
	var quickJS = oolite.jsVersionString.indexOf("QuickJS") !== -1;
	assertEqual(ships[1].script.$bump(), quickJS ? 1 : 2, "second ship's count");
	ships.forEach(function (s) { s.remove(true); });
});

test("start a script that never ends, from a timer", function ()
{
	var compat = worldScripts["oolite-test-compat"];
	$state.afterRunaway = 0;
	$state.runawayTimer = new Timer(compat, function () { compat.$runaway(); }, 0.25);
	$state.afterRunawayTimer = new Timer(worldScripts["oolite-test-recorder"], function () { $state.afterRunaway++; }, 1, 1);
});
