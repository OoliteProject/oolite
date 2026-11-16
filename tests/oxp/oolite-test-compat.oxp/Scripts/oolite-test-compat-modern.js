"use strict";
"use oolite modern";

/*
	A modern world script: no scope emulation, so bare names do not resolve
	through the script object, and const is block-scoped.
*/

this.name = "oolite-test-compat-modern";
this.version = "1.0";

var modernTopLevel = "modern-local";
this.$onScript = "on the script object";

this.$findings = {};

this.startUp = function ()
{
	var findings = this.$findings;
	findings.topLevelVar = modernTopLevel;
	try { findings.bareName = $onScript; } catch (e) { findings.bareName = e.name; }
	try { findings.blockConst = (function () { if (true) { const k = 7; } return typeof k; })(); } catch (e) { findings.blockConst = e.name; }
	try { findings.constBeforeDeclaration = (function () { var t = typeof c; const c = 1; return t; })(); } catch (e) { findings.constBeforeDeclaration = e.name; }
};
