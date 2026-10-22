/*

quaternion.js

Quaternion behaviour tests for the QuickJS-ng proof of concept. Expected values
and error messages follow the SpiderMonkey implementation (OOJSQuaternion.m).

*/

"use strict";

this.name = "poc_quaternion_tests";

this.runTests = function ()
{
	var failures = 0;

	function check(label, actual, expected)
	{
		if (actual !== expected)
		{
			log("poc.test.failed", label + ": expected " + expected + ", got " + actual);
			failures++;
		}
	}

	function throws(label, fn, expectedMessage)
	{
		try
		{
			fn();
			log("poc.test.failed", label + ": expected an exception");
			failures++;
		}
		catch (e)
		{
			check(label, e.message, expectedMessage);
		}
	}

	function near(a, b)
	{
		return Math.abs(a - b) < 1e-6;
	}

	// Construction and string conversion
	var q = new Quaternion();
	check("identity toString", q.toString(), "(1 + 0i + 0j + 0k)");
	check("toSource", new Quaternion(1, -2, 3, -4).toSource(), "Quaternion(1, -2, 3, -4)");
	check("signed toString", new Quaternion(1, -2, 3, -4).toString(), "(1 - 2i + 3j - 4k)");
	check("construct from array", new Quaternion([0, 1, 0, 0]).toString(), "(0 + 1i + 0j + 0k)");
	check("construct from quaternion", new Quaternion(q).toString(), "(1 + 0i + 0j + 0k)");
	check("call without new", Quaternion(1, 0, 0, 0).toString(), "(1 + 0i + 0j + 0k)");
	check("constructor length", Quaternion.length, 4);
	check("inherits Object.prototype", typeof q.hasOwnProperty, "function");
	check("prototype is a zero quaternion", Quaternion.prototype.toString(), "(0 + 0i + 0j + 0k)");

	// Properties (read back at single precision, as in SpiderMonkey)
	var p = new Quaternion(1, 2, 3, 4);
	check("w", p.w, 1);
	check("z", p.z, 4);
	p.w = 0.1;
	check("set w stored as float", p.w, Math.fround(0.1));
	check("toArray", JSON.stringify(new Quaternion(1, 2, 3, 4).toArray()), "[1,2,3,4]");

	// Methods
	check("multiply by identity", new Quaternion(1, 2, 3, 4).multiply(q).toString(), "(1 + 2i + 3j + 4k)");
	check("dot", new Quaternion(1, 0, 0, 0).dot([1, 0, 0, 0]), 1);
	check("conjugate", new Quaternion(1, 2, 3, 4).conjugate().toString(), "(1 - 2i - 3j - 4k)");
	check("normalize", new Quaternion(2, 0, 0, 0).normalize().toString(), "(1 + 0i + 0j + 0k)");
	check("identity vectorForward", q.vectorForward().toString(), "(0, 0, 1)");
	check("identity vectorUp", q.vectorUp().toString(), "(0, 1, 0)");
	check("identity vectorRight", q.vectorRight().toString(), "(1, 0, 0)");

	var r = q.rotateY(Math.PI / 2);
	var f = r.vectorForward();
	check("rotateY moves forward vector", near(Math.abs(f.x), 1) && near(f.z, 0), true);
	check("rotate without angle is unchanged", q.rotate([0, 1, 0]).toString(), "(1 + 0i + 0j + 0k)");
	check("rotate about axis matches rotateY", near(q.rotate([0, 1, 0], Math.PI / 2).dot(r), 1), true);
	var randomQ = Quaternion.random();
	check("random is unit", near(randomQ.dot(randomQ), 1), true);

	// Errors
	throws("bad constructor arguments", function () { new Quaternion(1, 2); },
		"Could not construct quaternion from parameters (1, 2) -- expected Quaternion, Entity or array of four numbers.");
	throws("bad multiply argument", function () { q.multiply("x"); },
		"Quaternion.multiply: Could not construct quaternion from parameters (\"x\") -- expected Quaternion, Entity or four numbers.");
	throws("bad rotateX argument", function () { q.rotateX(); },
		"Quaternion.rotateX: Expected number, got ().");

	return failures;
};
