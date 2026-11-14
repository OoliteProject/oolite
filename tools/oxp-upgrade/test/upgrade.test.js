"use strict";

const test = require("node:test");
const assert = require("node:assert");
const { upgradeScript, MARKER } = require("../lib/upgrade");
const { upgradeOXP } = require("../lib/oxp");
const zip = require("../lib/zip");

const world = { instances: "single" };
const perShip = { instances: "multiple" };

function upgraded(source, options = world)
{
	const result = upgradeScript(source, options);
	assert.strictEqual(result.status, "upgraded", result.reasons.join("; "));
	assert.strictEqual(result.output.split("\n").length, source.split("\n").length, "line count changed");
	return result.output;
}

test("adds the marker after existing directives", () => {
	assert.strictEqual(upgraded('"use strict";\nthis.name = "a";\n'), `"use strict"; "${MARKER}";\nthis.name = "a";\n`);
	assert.strictEqual(upgraded('"use strict"\nthis.name = "a";\n'), `"use strict"; "${MARKER}";\nthis.name = "a";\n`);
	assert.strictEqual(upgraded('/* c */\nthis.name = "a";\n'), `/* c */\n"${MARKER}"; this.name = "a";\n`);
});

test("leaves marked scripts alone", () => {
	const once = upgraded('"use strict";\nthis.name = "a";\nthis.f = function () { return name; };\n');
	assert.strictEqual(upgradeScript(once, world).status, "already-upgraded");
});

test("rewrites bare script property references in methods as this.name", () => {
	const out = upgraded(`"use strict";
this.name = "a";
this.$count = 0;
this.startUp = function () { $count++; $helper(name); if (typeof $late === "function") $late(); };
this.$helper = function (x) { return x; };
this.$late = function () {};
`);
	assert.match(out, /this\.\$count\+\+; this\.\$helper\(this\.name\); if \(typeof this\.\$late === "function"\) this\.\$late\(\);/);
});

test("uses a per-method alias inside nested functions", () => {
	const out = upgraded(`"use strict";
this.$limit = 3;
this.startUp = function () {
	return [1, 2, 3, 4].filter(function (n) { return n < $limit; });
};
`, perShip);
	assert.match(out, /this\.startUp = function \(\) \{ var \$script = this;/);
	assert.match(out, /return n < \$script\.\$limit;/);
});

test("puts the alias after a function's own directives", () => {
	const out = upgraded(`this.$x = 1;
this.f = function () { "use strict"; return [0].map(function () { return $x; }); };
`, perShip);
	assert.match(out, /function \(\) \{ "use strict"; var \$script = this;/);
});

test("avoids alias names the script already uses", () => {
	const out = upgraded(`var $script = 1;
this.$x = 1;
this.f = function () { return [0].map(function () { return $x + $script; }); };
`, perShip);
	assert.match(out, /var \$script2 = this;/);
	assert.match(out, /\$script2\.\$x \+ \$script/);
});

test("methods passed as callbacks aren't assumed to get the script as this", () => {
	const source = `"use strict";
this.$frames = 0;
this.$frame = function () { $frames++; };
this.startUp = function () { addFrameCallback(this.$frame); };
`;
	const out = upgraded(source, world);
	assert.match(out, /"use strict"; "use oolite modern"; var \$script = this;/);
	assert.match(out, /this\.\$frame = function \(\) \{ \$script\.\$frames\+\+; \};/);

	const refused = upgradeScript(source, perShip);
	assert.strictEqual(refused.status, "not-upgraded");
	assert.match(refused.reasons[0], /\$frames/);
});

test("callbacks that Oolite calls with the given this are safe", () => {
	const out = upgraded(`"use strict";
this.$n = 0;
this.$tick = function () { $n++; };
this.$done = function () { $n = 0; };
this.startUp = function () {
	this.$timer = new Timer(this, this.$tick, 1, 1);
	mission.runScreen({}, this.$done);
	addFrameCallback(this.$tick.bind(this));
};
`, perShip);
	assert.match(out, /this\.\$tick = function \(\) \{ this\.\$n\+\+; \};/);
	assert.match(out, /this\.\$done = function \(\) \{ this\.\$n = 0; \};/);
});

test("other scripts passing a method around make it unsafe", () => {
	const files = [
		{ path: "Config/script.js", data: Buffer.from('"use strict";\nthis.name = "lib";\nthis.$v = 1;\nthis.$cb = function () { return $v; };\n') },
		{ path: "Scripts/other.js", data: Buffer.from('"use strict";\nthis.name = "other";\nthis.startUp = function () { addFrameCallback(worldScripts.lib.$cb); };\n') },
	];
	const results = upgradeOXP(files);
	assert.strictEqual(results[0].status, "upgraded");
	assert.match(files[0].data.toString(), /\$script\.\$v/);
});

test("treats (function () { ... }).call(this) as script context", () => {
	const out = upgraded(`(function () {
"use strict";
this.name = "lib";
this.$a = 1;
this.f = function () { return $a; };
}).call(this);
`, perShip);
	assert.match(out, /return this\.\$a;/);
});

test("engine-defined properties such as ship are script properties", () => {
	const out = upgraded('"use strict";\nthis.shipDied = function () { log(ship.name); };\n', perShip);
	assert.match(out, /log\(this\.ship\.name\)/);
});

test("does not touch locals, parameters, globals or other objects' properties", () => {
	const source = `"use strict";
this.name = "a";
this.f = function (name) { var ship = player.ship; return name + ship.name + system.name; };
`;
	assert.strictEqual(upgraded(source), source.replace('"use strict";', `"use strict"; "${MARKER}";`));
});

test("rewrites const as var, but not in property names", () => {
	const out = upgraded('"use strict";\nconst a = 1;\nvar o = { const: 1 };\nlog(o.const, "const");\nfor (const k in o) log(k);\n');
	assert.match(out, /^var a = 1;$/m);
	assert.match(out, /\{ const: 1 \}/);
	assert.match(out, /o\.const, "const"/);
	assert.match(out, /for \(var k in o\)/);
});

test("handles legacy const redeclaration", () => {
	const out = upgraded('"use strict";\nconst a = 1;\nconst a = 2;\n');
	assert.match(out, /var a = 1;\nvar a = 2;/);
});

test("refuses scripts that can't be analysed", () => {
	assert.strictEqual(upgradeScript('this.x = 1; eval("x");', world).status, "not-upgraded");
	assert.strictEqual(upgradeScript("with (Math) { this.x = PI; }", world).status, "not-upgraded");
	assert.strictEqual(upgradeScript("var k = 'a'; this[k] = 1;", world).status, "not-upgraded");
	assert.strictEqual(upgradeScript("this.f = function () {", world).status, "parse-error");
	const shorthand = upgradeScript('"use strict";\nthis.$a = 1;\nthis.f = function () { return { $a }; };\n', world);
	assert.strictEqual(shorthand.status, "not-upgraded");
});

test("keeps byte order marks and CRLF line endings", () => {
	const out = upgraded('﻿"use strict";\r\nthis.$a = 1;\r\nthis.f = function () { return $a; };\r\n');
	assert.ok(out.startsWith('﻿"use strict"; "use oolite modern";\r\n'));
	assert.match(out, /return this\.\$a; \};\r\n$/);
});

test("reports SpiderMonkey extensions and unknown names", () => {
	const result = upgradeScript('"use strict";\nthis.f = function (o) { log(o.toSource(), uneval(o), mystery); };\n', world);
	assert.strictEqual(result.status, "upgraded");
	assert.strictEqual(result.notes.length, 2);
	assert.deepStrictEqual(result.unknownNames, [{ name: "mystery", line: 2 }]);
});

test("zip round trip keeps unchanged entries and replaces changed ones", () => {
	const zlib = require("zlib");
	const a = Buffer.from("hello");
	const b = Buffer.from('"use strict";\nthis.name = "x";\n');
	const entry = (name, data, method) => ({
		versionMadeBy: 20, versionNeeded: 20, flags: 0, method, time: 0, date: 0x21, crc: zip.crc32(data),
		compressed: method ? zlib.deflateRawSync(data) : data, compressedSize: 0, size: data.length,
		internalAttributes: 0, externalAttributes: 0, nameBytes: Buffer.from(name), name,
	});
	const entries = [entry("manifest.plist", a, 0), entry("Config/script.js", b, 8)];
	for (const e of entries) e.compressedSize = e.compressed.length;
	const read = zip.readZip(zip.writeZip(entries));
	assert.deepStrictEqual(read.map((e) => e.name), ["manifest.plist", "Config/script.js"]);
	assert.strictEqual(zip.entryData(read[1]).toString(), b.toString());
	zip.setEntryData(read[1], Buffer.from("changed"));
	const again = zip.readZip(zip.writeZip(read));
	assert.strictEqual(zip.entryData(again[0]).toString(), "hello");
	assert.strictEqual(zip.entryData(again[1]).toString(), "changed");
	assert.strictEqual(again[1].crc, zip.crc32(Buffer.from("changed")));
});
