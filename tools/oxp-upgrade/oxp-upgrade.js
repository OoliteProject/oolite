#!/usr/bin/env node
/*
	oxp-upgrade: upgrades OXP scripts so that Oolite runs them without its
	SpiderMonkey 1.8.5 scope emulation. See README.md.

	Usage:
		oxp-upgrade.js [options] <path>...

	Each path is an .oxz file, an .oxp folder or a single .js file. By
	default upgraded copies are written next to the originals, named
	*.upgraded.oxz, *.upgraded.oxp or *.upgraded.js.

	Options:
		--check       Report only; write nothing.
		--in-place    Overwrite the originals.
		--out=DIR     Write the upgraded copies to DIR.
		--world       Treat single .js files as world scripts (one instance).
		--json        Print the report as JSON.
		--quiet       Only list scripts that weren't upgraded.
*/

"use strict";

const fs = require("fs");
const path = require("path");
const { upgradeOXP } = require("./lib/oxp");
const { upgradeScript } = require("./lib/upgrade");
const zip = require("./lib/zip");

function usage()
{
	process.stderr.write("Usage: oxp-upgrade.js [--check] [--in-place] [--out=DIR] [--world] [--json] [--quiet] <file.oxz|folder.oxp|script.js>...\n");
	process.exit(2);
}

function walk(root, relative = "")
{
	const files = [];
	for (const entry of fs.readdirSync(path.join(root, relative), { withFileTypes: true })) {
		const rel = relative ? `${relative}/${entry.name}` : entry.name;
		if (entry.isDirectory()) files.push(...walk(root, rel));
		else if (entry.isFile()) files.push({ path: rel, data: fs.readFileSync(path.join(root, rel)) });
	}
	return files;
}

function outputPath(input, options)
{
	if (options.inPlace) return input;
	const ext = path.extname(input);
	const name = path.basename(input, ext) + ".upgraded" + ext;
	return path.join(options.out || path.dirname(input), name);
}

function processOXZ(input, options)
{
	const entries = zip.readZip(fs.readFileSync(input));
	const files = entries.filter((e) => !e.name.endsWith("/")).map((e) => ({ path: e.name, data: zip.entryData(e), entry: e }));
	const original = new Map(files.map((f) => [f, f.data]));
	const results = upgradeOXP(files);
	if (!options.check && results.some((r) => r.upgraded)) {
		for (const file of files) if (file.data !== original.get(file)) zip.setEntryData(file.entry, file.data);
		const target = outputPath(input, options);
		fs.writeFileSync(target, zip.writeZip(entries));
		return { results, target };
	}
	return { results, target: null };
}

function processOXP(input, options)
{
	const files = walk(input);
	const original = new Map(files.map((f) => [f, f.data]));
	const results = upgradeOXP(files);
	if (!options.check && results.some((r) => r.upgraded)) {
		const target = outputPath(input, options);
		if (target !== input) fs.cpSync(input, target, { recursive: true });
		for (const file of files) if (file.data !== original.get(file)) fs.writeFileSync(path.join(target, file.path), file.data);
		return { results, target };
	}
	return { results, target: null };
}

function processScript(input, options)
{
	const text = fs.readFileSync(input, "utf8");
	const result = upgradeScript(text, { instances: options.world ? "single" : "multiple" });
	const report = { path: path.basename(input), instances: options.world ? "single" : "multiple", ...result, upgraded: result.output !== null };
	delete report.output;
	let target = null;
	if (!options.check && result.output !== null) {
		target = outputPath(input, options);
		fs.writeFileSync(target, result.output);
	}
	return { results: [report], target };
}

function describe(input, outcome, options)
{
	const lines = [];
	const counts = {};
	for (const r of outcome.results) counts[r.status] = (counts[r.status] || 0) + 1;
	const summary = Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(", ") || "no scripts";
	lines.push(`${input}: ${summary}${outcome.target ? ` -> ${outcome.target}` : ""}`);
	for (const r of outcome.results) {
		if (options.quiet && (r.status === "upgraded" || r.status === "already-upgraded")) continue;
		let detail = `  ${r.path} [${r.instances === "single" ? "world script" : "per-entity script"}]: ${r.status}`;
		if (r.changes && r.status === "upgraded") {
			const c = r.changes;
			detail += ` (${c.thisReferences} this., ${c.aliasReferences} alias, ${c.constKeywords} const)`;
		}
		lines.push(detail);
		for (const reason of r.reasons) lines.push(`    - ${reason}`);
		if (!options.quiet) {
			for (const note of r.notes) lines.push(`    note: ${note}`);
			for (const u of r.unknownNames) lines.push(`    note: line ${u.line}: ${u.name} is not a known global or a property of this script; if another script sets it on this one, change it to this.${u.name}`);
		}
	}
	return lines.join("\n");
}

function main(argv)
{
	const options = { check: false, inPlace: false, out: null, world: false, json: false, quiet: false };
	const inputs = [];
	for (const arg of argv) {
		if (arg === "--check") options.check = true;
		else if (arg === "--in-place") options.inPlace = true;
		else if (arg.startsWith("--out=")) options.out = arg.slice(6);
		else if (arg === "--world") options.world = true;
		else if (arg === "--json") options.json = true;
		else if (arg === "--quiet") options.quiet = true;
		else if (arg === "--help" || arg === "-h") usage();
		else if (arg.startsWith("--")) usage();
		else inputs.push(arg);
	}
	if (inputs.length === 0) usage();
	if (options.out) fs.mkdirSync(options.out, { recursive: true });

	const all = [];
	let failed = false;
	for (const input of inputs) {
		let outcome;
		try {
			const stat = fs.statSync(input);
			if (stat.isDirectory()) outcome = processOXP(input, options);
			else if (/\.oxz$/i.test(input)) outcome = processOXZ(input, options);
			else if (/\.js$/i.test(input)) outcome = processScript(input, options);
			else throw new Error("not an .oxz, .oxp folder or .js file");
		} catch (error) {
			failed = true;
			if (options.json) all.push({ input, error: error.message });
			else process.stderr.write(`${input}: ${error.message}\n`);
			continue;
		}
		if (options.json) all.push({ input, target: outcome.target, scripts: outcome.results });
		else process.stdout.write(describe(input, outcome, options) + "\n");
	}
	if (options.json) process.stdout.write(JSON.stringify(all, null, 2) + "\n");
	process.exitCode = failed ? 1 : 0;
}

main(process.argv.slice(2));
