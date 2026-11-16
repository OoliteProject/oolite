/*

scope_a.js

World script in the style of Escort Contracts (ec_mother.js) and Bulletin
Board System, which call their own script properties by bare name. Under
SpiderMonkey the script object was on the scope chain, so this worked.

*/

"use strict";

this.name = "poc_scope_a";
this.version = "1.2";

const sharedName = "a"; // Also declared in scope_b.js; must not collide.
var topLevelVar = "a"; // Must stay local to this script.

this.ec_checkformasslock = function (entity)
{
	return entity.massLocked === true;
};

this.$padTextRight = function (text, width)
{
	while (text.length < width)
	{
		text += ".";
	}
	return text;
};

this.startUp = function ()
{
	var filtered = [{ massLocked: true }, { massLocked: false }].filter(ec_checkformasslock);

	// Properties added after loading are found too.
	this.$late = function () { return "late"; };

	var strict;
	try
	{
		undeclaredVariable = 1;
		strict = "sloppy";
	}
	catch (e)
	{
		strict = "strict";
	}

	return [filtered.length, $padTextRight("ab", 4), name, version, sharedName, topLevelVar, typeof global.topLevelVar, $late(), strict, this.name].join("|");
};
