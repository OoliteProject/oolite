"use strict";

this.name = "poc_runtime_error";

this.startUp = function ()
{
	var a = 1;
	var b = 2;
	undefinedFunction(a, b); // line 9
};
