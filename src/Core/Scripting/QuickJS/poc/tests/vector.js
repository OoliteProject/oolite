/*

vector.js

Vector3D behaviour tests for the QuickJS-ng proof of concept. Expected values
and error messages follow the SpiderMonkey implementation (OOJSVector.m).

*/

"use strict";

this.name = "poc_vector_tests";

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

	// Construction and string conversion
	var v = new Vector3D(1, 2, 3);
	check("toString", v.toString(), "(1, 2, 3)");
	check("toSource", v.toSource(), "Vector3D(1, 2, 3)");
	check("implicit string conversion", "" + v, "(1, 2, 3)");
	check("call without new", Vector3D(1, 2, 3).toString(), "(1, 2, 3)");
	check("construct from array", new Vector3D([4, 5, 6]).toString(), "(4, 5, 6)");
	check("construct from vector", new Vector3D(v).toString(), "(1, 2, 3)");
	check("default construction", new Vector3D().toString(), "(0, 0, 0)");
	check("fractional components", new Vector3D(0.5, -1.25, 1e21).toString(), "(0.5, -1.25, 1e+21)");
	check("instanceof", v instanceof Vector3D, true);
	check("prototype is a zero vector", Vector3D.prototype.toString(), "(0, 0, 0)");

	// Properties
	check("x", v.x, 1);
	check("y", v.y, 2);
	check("z", v.z, 3);
	v.x = 5;
	check("set x", v.x, 5);
	v.y = "7";
	check("set y from string", v.y, 7);
	check("vector after sets", v.toString(), "(5, 7, 3)");
	var keys = [];
	for (var key in v)
	{
		keys.push(key);
	}
	check("enumerable properties", keys.join(","), "x,y,z");

	// Methods
	check("add", new Vector3D(1, 2, 3).add([1, 1, 1]).toString(), "(2, 3, 4)");
	check("subtract", new Vector3D(1, 2, 3).subtract(new Vector3D(1, 1, 1)).toString(), "(0, 1, 2)");
	check("dot", new Vector3D(1, 2, 3).dot([4, 5, 6]), 32);
	check("cross", new Vector3D(1, 0, 0).cross([0, 1, 0]).toString(), "(0, 0, 1)");
	check("magnitude", new Vector3D(3, 4, 0).magnitude(), 5);
	check("squaredMagnitude", new Vector3D(3, 4, 0).squaredMagnitude(), 25);
	check("distanceTo", new Vector3D(0, 0, 0).distanceTo([3, 4, 0]), 5);
	check("squaredDistanceTo", new Vector3D(0, 0, 0).squaredDistanceTo([3, 4, 0]), 25);
	check("direction", new Vector3D(0, 0, 5).direction().toString(), "(0, 0, 1)");
	check("multiply", new Vector3D(1, 2, 3).multiply(2).toString(), "(2, 4, 6)");
	check("angleTo", new Vector3D(1, 0, 0).angleTo([0, 1, 0]), Math.PI / 2);
	check("tripleProduct", new Vector3D(1, 0, 0).tripleProduct([0, 1, 0], [0, 0, 1]), 1);
	check("toArray", JSON.stringify(new Vector3D(1, 2, 3).toArray()), "[1,2,3]");
	check("rotateBy identity", new Vector3D(1, 2, 3).rotateBy(new Quaternion()).toString(), "(1, 2, 3)");
	check("rotationTo returns quaternion", new Vector3D(1, 0, 0).rotationTo([0, 1, 0]) instanceof Quaternion, true);

	// Static methods
	check("interpolate", Vector3D.interpolate([0, 0, 0], [10, 10, 10], 0.5).toString(), "(5, 5, 5)");
	check("random within length", Vector3D.random(10).magnitude() <= 10, true);
	check("randomDirection is unit", Math.abs(Vector3D.randomDirection().magnitude() - 1) < 1e-6, true);
	check("randomDirectionAndLength within length", Vector3D.randomDirectionAndLength(3).magnitude() <= 3, true);

	// Errors
	throws("bad constructor arguments", function () { new Vector3D("a"); },
		"Could not construct vector from parameters (\"a\") -- expected Vector, Entity or array of three numbers.");
	throws("bad add argument", function () { v.add(1); },
		"Vector3D.add: Could not construct vector from parameters (1) -- expected Vector, Entity or array of three numbers.");
	throws("bad multiply argument", function () { v.multiply("x"); },
		"Vector3D.multiply: Expected number, got (\"x\").");
	throws("bad this", function () { Vector3D.prototype.add.call({}, [1, 2, 3]); },
		"Vector3D.add: Invalid target object ([object Object]) -- expected Vector3D.");
	throws("insufficient interpolate arguments", function () { Vector3D.interpolate([0, 0, 0]); },
		"Vector3D.interpolate: Insufficient parameters ([0, 0, 0]) -- expected vector expression, vector expression and number.");

	return failures;
};
