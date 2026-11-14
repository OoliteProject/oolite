/*
	A legacy world script: no "use strict", no "use oolite modern". Under
	SpiderMonkey 1.8.5 the script object was at the head of the scope chain,
	top-level var was local to the script, const was function-scoped and could
	be used before its declaration. The compat tests in tests/js check what
	this script finds.
*/

this.name = "oolite-test-compat";
this.version = "1.0";

var topLevelVar = "script-local";
this.$sharedName = "from the script object";

this.$findings = {};

this.startUp = function ()
{
	// A bare name resolves through the script object.
	this.$findings.bareName = $sharedName;
	this.$findings.bareThisName = name;
	// Top-level var is visible to the script's own functions...
	this.$findings.topLevelVar = topLevelVar;
	// ...but is not a global.
	this.$findings.topLevelVarIsGlobal = (typeof Function("return this")().topLevelVar !== "undefined");
	this.$findings.legacyConst = (function () { if (true) { const k = 7; } return k; })();
	this.$findings.constBeforeDeclaration = (function () { var t = typeof c; const c = 1; return t; })();
	this.$findings.functionSource = (function (a) { return a * 2; }).toString();
	this.$findings.toSource = ({ a: 1 }).toSource();
};

// Run by tests/js/flight/50-compat-setup.js from a timer: the time limiter must stop it.
this.$runaway = function ()
{
	this.$runawayStarted = true;
	for (;;) {}
	this.$runawayFinished = true;
};
