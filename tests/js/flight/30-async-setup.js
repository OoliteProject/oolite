// Things that happen over time; checked after the next phase change (arrived/20-async.js).

test("start a frame callback and a timer", function ()
{
	$state.frames = 0;
	$state.frameTime = 0;
	$state.frameCallback = addFrameCallback(function (delta) { $state.frames++; $state.frameTime += delta; });
	$state.timerFired = 0;
	$state.timer = new Timer(worldScripts["oolite-test-recorder"], function () { $state.timerFired++; }, 0.5, 0.5);
	$state.clockAtLaunch = clock.seconds;
	$state.fuelAtLaunch = player.ship.fuel;
	assert(isValidFrameCallback($state.frameCallback), "frame callback not registered");
	assert($state.timer.isRunning, "timer not running");
});

test("start a timer whose this is the global object", function ()
{
	// In SpiderMonkey such a timer was dropped when it came due; QuickJS crashed (stack overflow) until fixed.
	var global = (function () { return this; })();
	$state.globalTimerFired = 0;
	$state.globalTimer = new Timer(global, function () { $state.globalTimerFired++; }, 0.25);
	assert($state.globalTimer.isRunning, "not running");
});
