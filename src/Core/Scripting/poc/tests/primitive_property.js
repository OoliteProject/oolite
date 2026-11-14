/*

primitive_property.js

Creating a property on a primitive value in strict code. SpiderMonkey 1.8.5
silently ignored it, and OXPs rely on that (Route Planner did); ES5+ requires
a TypeError. The bundled QuickJS-ng carries upstream #768's patch
(subprojects/packagefiles/quickjs-ng/0001-oolite-primitive-property-assignment.patch)
to keep SpiderMonkey's behaviour.

*/

"use strict";

this.name = "poc_primitive_property";

this.startUp = function ()
{
	var s = "text";
	s.oolite = 1; // ignored: no TypeError
	var n = 42;
	n.oolite = 2;
	var b = true;
	b.oolite = 3;
	// Nothing was created, and the values are unchanged.
	return [typeof s.oolite, typeof n.oolite, typeof b.oolite, s, n, b].join("|");
};
