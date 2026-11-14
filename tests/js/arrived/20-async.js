// The frame callback and timer started in flight/30-async-setup.js ran while flying and jumping.

test("frame callback ran", function ()
{
	assert($state.frames > 10, "only " + $state.frames + " frames");
	assert($state.frameTime > 1, "only " + $state.frameTime + " s of frames");
	removeFrameCallback($state.frameCallback);
	assert(!isValidFrameCallback($state.frameCallback), "callback still registered");
});

test("timer fired repeatedly", function ()
{
	assert($state.timerFired >= 2, "timer fired " + $state.timerFired + " times");
	$state.timer.stop();
});

test("AI scripts ran", function ()
{
	var ai = system.filteredEntities(this, function (e) { return e.isShip && !e.isPlayer && e.AIScript && e.AIScript.name !== "oolite-nullAI.js"; }, player.ship, 1e9);
	assert(ai.length > 0, "no ships with AI scripts in the system");
});

test("a timer whose this is the global object is dropped without firing", function ()
{
	assertEqual($state.globalTimerFired, 0);
	assert(!$state.globalTimer.isRunning, "still running");
});
