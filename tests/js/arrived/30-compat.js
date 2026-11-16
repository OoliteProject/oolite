// The runaway script started in flight/50-compat-setup.js was stopped, and scripts kept running.

test("the time limiter stopped the runaway script", function ()
{
	var compat = worldScripts["oolite-test-compat"];
	assert(compat.$runawayStarted, "the runaway script did not start");
	assert(!compat.$runawayFinished, "the runaway script finished");
	assert($state.afterRunaway > 0, "timers stopped running after the runaway script");
	$state.afterRunawayTimer.stop();
});
