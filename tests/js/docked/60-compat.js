// Scripts written for SpiderMonkey 1.8.5 (tests/oxp/oolite-test-compat.oxp), loaded at start-up.

function legacy() { return worldScripts["oolite-test-compat"].$findings; }
function quickJS() { return oolite.jsVersionString.indexOf("QuickJS") !== -1; }

test("legacy: bare names resolve through the script object", function ()
{
	assertEqual(legacy().bareName, "from the script object");
	assertEqual(legacy().bareThisName, "oolite-test-compat");
});

test("legacy: top-level var is visible to the script's functions, and local to the script", function ()
{
	assertEqual(legacy().topLevelVar, "script-local");
	// SpiderMonkey made top-level vars global; QuickJS deliberately keeps them local (src/Core/Scripting/README.md).
	assertEqual(legacy().topLevelVarIsGlobal, !quickJS());
});

test("legacy: const is function-scoped and usable before its declaration", function ()
{
	assertEqual(legacy().legacyConst, 7);
	assertEqual(legacy().constBeforeDeclaration, "undefined");
});

test("legacy: toSource", function ()
{
	assertEqual(legacy().toSource, "({a:1})");
});

test("legacy: function source text", function ()
{
	// SpiderMonkey gave decompiled source; QuickJS keeps the original text.
	if (quickJS())  assertEqual(legacy().functionSource, "function (a) { return a * 2; }");
	else  assertType(legacy().functionSource, "string");
});

test("modern: no scope emulation", function ()
{
	if (!quickJS())  return;  // SpiderMonkey has no modern mode.
	var modern = worldScripts["oolite-test-compat-modern"].$findings;
	assertEqual(modern.topLevelVar, "modern-local");
	assertEqual(modern.bareName, "ReferenceError");
	assertEqual(modern.blockConst, "undefined");
	assertEqual(modern.constBeforeDeclaration, "ReferenceError");
});
