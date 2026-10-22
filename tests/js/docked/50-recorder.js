// The event recorder (tests/oxp/oolite-test-recorder.oxp) is loaded, and saw the game start.

test("recorder is loaded", function ()
{
	var recorder = worldScripts["oolite-test-recorder"];
	assert(recorder, "the recorder OXP is not loaded");
	assertEqual(recorder.$phase, "docked");
});

test("start-up events were recorded", function ()
{
	assert(eventNames("startup").length > 0, "no start-up events");
});
