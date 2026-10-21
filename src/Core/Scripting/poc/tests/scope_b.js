"use strict";

this.name = "poc_scope_b";

const sharedName = "b";
var topLevelVar = "b";

this.check = function ()
{
	return sharedName + topLevelVar + name;
};
