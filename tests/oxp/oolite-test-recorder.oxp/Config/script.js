/*

Event recorder for the JavaScript tests (tests/run_js_tests.py).

Records every world-script event, with a short description of its arguments,
into the bucket of the current test phase. The runner calls $begin(phase)
before it moves the game into that phase, so a phase's bucket holds the
events that moving there caused, followed by any its tests cause.

*/

"use strict";

this.name = "oolite-test-recorder";
this.version = "1.0";

this.$phase = "startup";
this.$events = { startup: [] };

this.$begin = function (phase)
{
	this.$phase = phase;
	this.$events[phase] = [];
};

// Event names in the order they were recorded in a phase (default: the current one).
this.$names = function (phase)
{
	return (this.$events[phase || this.$phase] || []).map(function (e) { return e.name; });
};

function describe(value)
{
	if (value === null || value === undefined)  return String(value);
	if (typeof value === "object" && value.isValid !== undefined)  return value.isValid ? (value.dataKey || value.name) : "<stale>";
	if (typeof value === "object")  return Array.isArray(value) ? "[array]" : "{object}";
	return value;
}

[
	"alertConditionChanged", "cargoDumpedNearby", "chartHighlightModeChanged", "commsMessageReceived",
	"compassTargetChanged", "dayChanged", "equipmentAdded", "equipmentDamaged", "equipmentRemoved",
	"equipmentRepaired", "escapePodSequenceOver", "gamePaused", "gameResumed", "guiScreenChanged",
	"guiScreenWillChange", "missionScreenEnded", "missionScreenOpportunity", "playerBoughtCargo",
	"playerBoughtEquipment", "playerBoughtNewShip", "playerCancelledAutoPilot", "playerCancelledJumpCountdown",
	"playerChangedPrimedEquipment", "playerCompletedContract", "playerDockingClearanceGranted",
	"playerDockingRefused", "playerEnteredContract", "playerEnteredNewGalaxy", "playerJumpFailed",
	"playerRequestedDockingClearance", "playerSoldCargo", "playerStartedAutoPilot", "playerStartedJumpCountdown",
	"playerWillSaveGame", "reportScreenEnded", "shipAttackedOther", "shipAttackedWithMissile", "shipBeingAttacked",
	"shipCollided", "shipDockedWithStation", "shipEnteredPlanetaryVicinity", "shipEnteredStationAegis",
	"shipExitedPlanetaryVicinity", "shipExitedStationAegis", "shipExitedWitchspace", "shipFiredMissile",
	"shipKilledOther", "shipLaunchedEscapePod", "shipLaunchedFromStation", "shipScoopedFuel", "shipScoopedOther",
	"shipSpawned", "shipTargetAcquired", "shipTargetDestroyed", "shipTargetLost", "shipWillDockWithStation",
	"shipWillEnterWitchspace", "shipWillExitWitchspace", "shipWillLaunchFromStation", "systemWillPopulate",
	"systemWillRepopulate", "viewDirectionChanged", "weaponsSystemsToggled"
].forEach(function (name)
{
	this[name] = function ()
	{
		var bucket = this.$events[this.$phase];
		if (bucket.length < 2000)  bucket.push({ name: name, args: Array.prototype.map.call(arguments, describe) });
	};
}, this);
