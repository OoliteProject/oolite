// Frame callbacks and timers (registration only; the tests cannot wait for frames).

test("frame callbacks can be added and removed", function ()
{
	var id = addFrameCallback(function (delta) {});
	assert(isValidFrameCallback(id), "callback not valid");
	removeFrameCallback(id);
	assert(!isValidFrameCallback(id), "callback still valid");
	assertThrows(function () { addFrameCallback("not a function"); });
});

test("timers can be started and stopped", function ()
{
	var t = new Timer(this, function () {}, 1000, 1000);
	assert(t.isRunning, "not running");
	t.stop();
	assert(!t.isRunning, "still running");
	t.start();
	assert(t.isRunning, "not restarted");
	t.stop();
});

test("targeting", function ()
{
	var ps = player.ship;
	var rock = system.addShips("asteroid", 1, ps.position.add(ps.vectorForward.multiply(8000)), 0)[0];
	ps.target = rock;
	assertEqual(ps.target, rock);
	ps.target = null;
	assertEqual(ps.target, null);
	rock.remove(true);
});
