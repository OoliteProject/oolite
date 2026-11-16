/*
	Upgrades the scripts of one OXP, given as a list of { path, data } files
	with paths relative to the OXP root (the folder holding Config/ and
	Scripts/, or the root of an OXZ).

	World scripts (Config/script.js and the scripts listed in
	Config/world-scripts.plist) have one instance; all other scripts are
	treated as having one instance per ship, item or effect.
*/

"use strict";

const { upgradeScript, collectExternalEscapes, scriptName } = require("./upgrade");

/*	Scripts are UTF-8, but a few are Latin-1 (Oolite falls back to it). The
	upgrade only inserts ASCII, so Latin-1 files are edited as Latin-1.
*/
function decode(data)
{
	if (data.length >= 2 && ((data[0] === 0xFF && data[1] === 0xFE) || (data[0] === 0xFE && data[1] === 0xFF))) return null; // UTF-16
	const text = data.toString("utf8");
	if (Buffer.from(text, "utf8").equals(data)) return { text, encoding: "utf8" };
	return { text: data.toString("latin1"), encoding: "latin1" };
}

// File names listed in a world-scripts.plist (OpenStep or XML).
function worldScriptNames(plist)
{
	const names = new Set();
	const pattern = /<string>\s*([^<]+?\.js)\s*<\/string>|"([^"]+?\.js)"|([A-Za-z0-9_.\-]+\.js)/g;
	for (let match; (match = pattern.exec(plist));) names.add((match[1] || match[2] || match[3]).toLowerCase());
	return names;
}

function upgradeOXP(files)
{
	const byPath = new Map(files.map((f) => [f.path.toLowerCase(), f]));
	const worldNames = new Set();
	const plist = byPath.get("config/world-scripts.plist");
	if (plist) for (const name of worldScriptNames(plist.data.toString("utf8"))) worldNames.add(name);

	const scripts = [];
	for (const file of files) {
		const lower = file.path.toLowerCase();
		if (!lower.endsWith(".js")) continue;
		if (!lower.startsWith("config/") && !lower.startsWith("scripts/")) continue;
		const base = lower.slice(lower.lastIndexOf("/") + 1);
		const world = lower === "config/script.js" || (lower.startsWith("scripts/") && worldNames.has(base));
		const decoded = decode(file.data);
		scripts.push({ file, text: decoded && decoded.text, encoding: decoded && decoded.encoding, world });
	}

	// Methods that other scripts in this OXP pass around as values.
	const external = new Map();
	for (const script of scripts) if (script.text !== null) collectExternalEscapes(script.text, external);

	const results = [];
	for (const script of scripts) {
		const report = { path: script.file.path, instances: script.world ? "single" : "multiple" };
		if (script.text === null) {
			results.push({ ...report, status: "not-upgraded", reasons: ["is UTF-16 text"], notes: [], unknownNames: [], changes: null });
			continue;
		}
		const name = scriptName(script.text);
		const escaping = new Set(external.get(name) || []);
		if (!script.world) for (const method of external.get("*") || []) escaping.add(method);
		const result = upgradeScript(script.text, { instances: report.instances, escaping });
		if (result.output !== null) script.file.data = Buffer.from(result.output, script.encoding);
		results.push({ ...report, name, status: result.status, reasons: result.reasons, notes: result.notes, unknownNames: result.unknownNames, changes: result.changes, upgraded: result.output !== null });
	}
	return results;
}

module.exports = { upgradeOXP, worldScriptNames };
