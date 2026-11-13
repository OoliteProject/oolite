// The assertion helpers themselves, so that a broken helper cannot make every other test pass.

test("assertEqual compares primitives strictly", function ()
{
	assertEqual(1 + 1, 2);
	assertThrows(function () { assertEqual("2", 2); }, /expected 2, got "2"/);
	assertEqual(NaN, NaN);
});

test("assertEqual compares structures", function ()
{
	assertEqual([1, [2, 3]], [1, [2, 3]]);
	assertEqual(new Vector3D(1, 2, 3), new Vector3D(1, 2, 3));
	assertThrows(function () { assertEqual({ a: 1 }, { a: 2 }); });
});

test("assertThrows fails when nothing is thrown", function ()
{
	var caught = false;
	try { assertThrows(function () {}); } catch (e) { caught = /expected an exception/.test(e.message); }
	assert(caught, "assertThrows did not fail");
	assertThrows(function () { assertThrows(function () { throw new Error("x"); }, /y/); }, /does not match/);
});

test("assert and assertClose", function ()
{
	assert(true);
	assertThrows(function () { assert(false, "boom"); }, /boom/);
	assertClose(0.1 + 0.2, 0.3);
	assertThrows(function () { assertClose(1, 2, 0.5); });
});
