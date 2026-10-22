/*
	Helpers for the JavaScript tests in tests/js. run_js_tests.py sends each
	test file to the game's debug console as the body of a function, with this
	file in front of it, and reads back the array that $results ends up as.

	A test file calls test(name, fn) for each test; fn passes unless it throws.
*/

var $results = [];

function test(name, fn)
{
	try
	{
		fn();
		$results.push([name, null]);
	}
	catch (e)
	{
		var where = (e && e.stack) ? "\n" + String(e.stack).split("\n").slice(0, 4).join("\n") : "";
		$results.push([name, String(e) + where]);
	}
}

function $show(value)
{
	if (value instanceof Vector3D || value instanceof Quaternion)  return value.constructor.name + "(" + value.toArray().join(", ") + ")";
	if (typeof value === "string")  return JSON.stringify(value);
	try
	{
		var json = JSON.stringify(value);
		if (json !== undefined)  return json;
	}
	catch (e) {}
	return String(value);
}

function fail(message)
{
	throw new Error(message);
}

function assert(condition, message)
{
	if (!condition)  fail(message || "assertion failed");
}

// Strict equality for primitives; structural (JSON) equality for arrays, plain objects, vectors and quaternions.
function assertEqual(actual, expected, message)
{
	var same;
	if (expected !== null && typeof expected === "object")
	{
		same = $show(actual) === $show(expected);
	}
	else
	{
		same = actual === expected || (expected !== expected && actual !== actual);  // NaN equals NaN here.
	}
	if (!same)  fail((message ? message + ": " : "") + "expected " + $show(expected) + ", got " + $show(actual));
}

function assertClose(actual, expected, tolerance, message)
{
	if (tolerance === undefined)  tolerance = 1e-6;
	if (!(Math.abs(actual - expected) <= tolerance))  fail((message ? message + ": " : "") + "expected " + expected + " ± " + tolerance + ", got " + actual);
}

// Passes if fn throws; pattern, if given, must match the error's message.
function assertThrows(fn, pattern, message)
{
	var error = null, threw = false;
	try
	{
		fn();
	}
	catch (e)
	{
		threw = true;
		error = e;
	}
	if (!threw)  fail((message ? message + ": " : "") + "expected an exception");
	if (pattern && !pattern.test(String(error && error.message !== undefined ? error.message : error)))
	{
		fail((message ? message + ": " : "") + "threw " + error + ", which does not match " + pattern);
	}
}

function assertType(value, type, message)
{
	if (typeof value !== type)  fail((message ? message + ": " : "") + "expected a " + type + ", got " + $show(value) + " (" + typeof value + ")");
}
