/*
	Upgrades one OXP script so that it no longer needs Oolite's emulation of
	SpiderMonkey 1.8.5 scoping, and marks it with MARKER so that Oolite runs it
	without that emulation.

	Oolite 1.92 and earlier (SpiderMonkey 1.8.5) put the script object on the
	scope chain, so a script could refer to its own properties by bare name,
	and `const` was function-scoped and usable before its declaration. QuickJS
	builds of Oolite emulate both for unmarked scripts. A marked script must not
	rely on either, so this:

	- replaces every `const` keyword with `var`, exactly as Oolite does for
	  unmarked scripts, so the script behaves as it does now;
	- rewrites each bare reference to a script property as `this.name`, or,
	  inside a nested function whose `this` is something else, as `$script.name`,
	  where `var $script = this;` is added at the start of the enclosing method;
	- adds MARKER to the script's directive prologue.

	Everything added is ES5 and on an existing line, so upgraded scripts still
	run on Oolite 1.92 (which ignores the marker) and line numbers in error
	messages don't change.

	A script is left unchanged, with the reasons reported, if the rewrite can't
	be shown to be safe: for example if it uses `with` or `eval`, adds script
	properties with computed names, or, in a script that has one instance per
	ship (ship, AI, equipment and other non-world scripts), refers to script
	properties from a function that isn't called with the script as `this`.
	A per-method alias works in those scripts, but a top-level one doesn't:
	SpiderMonkey 1.8.5 shares top-level variables between the instances.
*/

"use strict";

const acorn = require("acorn");
const eslintScope = require("eslint-scope");
const { GLOBALS, ENGINE_SCRIPT_PROPERTIES } = require("./names");

const MARKER = "use oolite modern";
const ALIAS_BASE = "$script";
const PARSE_OPTIONS = {
	ecmaVersion: "latest",
	sourceType: "script",
	allowReturnOutsideFunction: true,
	allowHashBang: false,
	locations: true,
	ranges: true,
};

/*	Replace each `const` keyword with `var`. Uses acorn's tokenizer, so
	`const` in strings, comments, regular expressions and property names is
	left alone.
*/
function rewriteConst(text)
{
	const edits = [];
	let previous = null;
	const tokens = [];
	for (const token of acorn.tokenizer(text, PARSE_OPTIONS)) tokens.push(token);
	for (let i = 0; i < tokens.length; i++) {
		const token = tokens[i];
		if (token.type.keyword === "const") {
			const afterDot = previous && (previous.type === acorn.tokTypes.dot || previous.type === acorn.tokTypes.questionDot);
			const next = tokens[i + 1];
			const isKey = next && next.type === acorn.tokTypes.colon;
			if (!afterDot && !isKey) edits.push({ start: token.start, end: token.end, text: "var" });
		}
		previous = token;
	}
	return edits;
}

function applyEdits(text, edits)
{
	const sorted = edits.slice().sort((a, b) => b.start - a.start || b.end - a.end);
	let result = text;
	for (const edit of sorted) result = result.slice(0, edit.start) + edit.text + result.slice(edit.end);
	return result;
}

function forEachChild(node, callback)
{
	for (const key of Object.keys(node)) {
		if (key === "parent") continue;
		const value = node[key];
		if (Array.isArray(value)) {
			for (const item of value) if (item && typeof item.type === "string") callback(item);
		} else if (value && typeof value.type === "string") {
			callback(value);
		}
	}
}

function setParents(root)
{
	const all = [];
	(function visit(node, parent) {
		node.parent = parent;
		all.push(node);
		forEachChild(node, (child) => visit(child, node));
	})(root, null);
	return all;
}

function isFunction(node)
{
	return node.type === "FunctionExpression" || node.type === "FunctionDeclaration" || node.type === "ArrowFunctionExpression";
}

// The node that determines `this` at `node`: the nearest enclosing non-arrow function, or the program.
function thisContext(node)
{
	for (let n = node.parent; n; n = n.parent) {
		if (n.type === "Program") return n;
		if (isFunction(n) && n.type !== "ArrowFunctionExpression") return n;
	}
	return null;
}

function propertyName(member)
{
	if (!member.computed && member.property.type === "Identifier") return member.property.name;
	if (member.computed && member.property.type === "Literal" && typeof member.property.value === "string") return member.property.value;
	return null;
}

function isMember(node, objectName, property)
{
	return node && node.type === "MemberExpression" && !node.computed &&
		node.object.type === "Identifier" && node.object.name === objectName &&
		node.property.type === "Identifier" && node.property.name === property;
}

/*	Whether a function value at `node` may be called later with a `this`
	other than the script. Calls, tests, typeof and so on don't let it
	escape; passing it to an unknown function, storing or returning it do.
	Callback parameters that Oolite calls with a given `this` (Timer,
	mission.runScreen, system.filteredEntities) and .bind/.call/.apply with
	`this` are safe.
*/
function escapes(node)
{
	const parent = node.parent;
	if (!parent) return false;
	switch (parent.type) {
		case "CallExpression":
		case "NewExpression": {
			if (parent.callee === node) return false;
			const index = parent.arguments.indexOf(node);
			const args = parent.arguments;
			const thisArg = (i) => args[i] && args[i].type === "ThisExpression";
			if (parent.type === "NewExpression" && parent.callee.type === "Identifier" && parent.callee.name === "Timer" && index === 1 && thisArg(0)) return false;
			if (isMember(parent.callee, "mission", "runScreen") && index === 1 && (args.length < 3 || thisArg(2))) return false;
			if (isMember(parent.callee, "system", "filteredEntities") && index === 1 && thisArg(0)) return false;
			return true;
		}
		case "MemberExpression": {
			if (parent.object !== node) return false;
			const name = propertyName(parent);
			if (name === "bind" || name === "call" || name === "apply") {
				const call = parent.parent;
				const bound = call && call.type === "CallExpression" && call.callee === parent &&
					call.arguments[0] && call.arguments[0].type === "ThisExpression";
				return !bound;
			}
			return false;
		}
		case "AssignmentExpression": return parent.right === node;
		case "VariableDeclarator": return parent.init === node;
		case "ReturnStatement":
		case "ArrayExpression":
		case "YieldExpression":
		case "SpreadElement":
			return true;
		case "Property": return parent.value === node;
		case "ConditionalExpression":
			return parent.test === node ? false : escapes(parent);
		case "LogicalExpression":
		case "SequenceExpression":
		case "ParenthesizedExpression":
			return escapes(parent);
		case "ArrowFunctionExpression": return parent.body === node;
		default: return false;
	}
}

function prologueEnd(body)
{
	let end = null;
	for (const statement of body) {
		if (statement.type === "ExpressionStatement" && typeof statement.directive === "string") end = statement;
		else break;
	}
	return end;
}

function hasMarker(program)
{
	for (const statement of program.body) {
		if (statement.type === "ExpressionStatement" && typeof statement.directive === "string") {
			if (statement.directive === MARKER) return true;
		} else {
			break;
		}
	}
	return false;
}

function line(node) { return node.loc.start.line; }

function endsWithSemicolon(text, statement) { return text[statement.end - 1] === ";"; }

/*	Static analysis shared by the upgrade and by cross-script escape
	collection. `escapingExternally` holds method names that other scripts
	pass around as values (worldScripts.NAME.method).
*/
function analyse(text, escapingExternally)
{
	const ast = acorn.parse(text, PARSE_OPTIONS);
	const nodes = setParents(ast);
	const blockers = [];
	const notes = [];

	const scopeManager = eslintScope.analyze(ast, { ecmaVersion: 2022, sourceType: "script" });
	const globalScope = scopeManager.globalScope;

	// Method names whose functions may be called with another `this`.
	const escaping = new Set(escapingExternally || []);
	for (const ref of globalScope.through) if (escapes(ref.identifier)) escaping.add(ref.identifier.name);
	for (const node of nodes) {
		if (node.type === "MemberExpression" && node.object.type === "ThisExpression") {
			const name = propertyName(node);
			if (name !== null && escapes(node)) escaping.add(name);
		}
		if (node.type === "WithStatement") blockers.push(`uses a with statement (line ${line(node)})`);
		if (node.type === "AssignmentExpression" && node.left.type === "MemberExpression" &&
			node.left.object.type === "ThisExpression" && propertyName(node.left) === null) {
			blockers.push(`sets a script property with a computed name (line ${line(node)}), so its properties can't all be found`);
		}
		if (node.type === "CallExpression" && node.callee.type === "MemberExpression" &&
			node.callee.object.type === "Identifier" && node.callee.object.name === "Object" &&
			["assign", "defineProperties"].includes(propertyName(node.callee)) &&
			node.arguments[0] && node.arguments[0].type === "ThisExpression") {
			blockers.push(`adds script properties with Object.${propertyName(node.callee)}() (line ${line(node)})`);
		}
		if (node.type === "MemberExpression" && ["toSource"].includes(propertyName(node))) {
			notes.push(`line ${line(node)}: toSource() is a SpiderMonkey extension; it still works in Oolite, but JSON.stringify() is the standard alternative`);
		}
	}

	/*	Safe methods: functions assigned as this.NAME in script context whose
		NAME doesn't escape, and functions called immediately with .call(this).
	*/
	const safeMethodCache = new Map();
	function isScriptContext(context)
	{
		if (!context) return false;
		if (context.type === "Program") return true;
		return isSafeMethod(context);
	}
	function isSafeMethod(fn)
	{
		if (safeMethodCache.has(fn)) return safeMethodCache.get(fn);
		safeMethodCache.set(fn, false); // Guard against cycles.
		const parent = fn.parent;
		let safe = false;
		// (function () { ... }).call(this) or .apply(this, ...): runs once, with the caller's this.
		if (fn.type === "FunctionExpression" && parent && parent.type === "MemberExpression" && parent.object === fn &&
			["call", "apply"].includes(propertyName(parent)) && parent.parent.type === "CallExpression" &&
			parent.parent.callee === parent && parent.parent.arguments[0] && parent.parent.arguments[0].type === "ThisExpression") {
			safe = isScriptContext(thisContext(parent.parent));
		} else if (fn.type === "FunctionExpression" && parent && parent.type === "AssignmentExpression" &&
			parent.operator === "=" && parent.right === fn && parent.left.type === "MemberExpression" &&
			parent.left.object.type === "ThisExpression") {
			const name = propertyName(parent.left);
			safe = name !== null && !escaping.has(name) && isScriptContext(thisContext(parent));
		}
		safeMethodCache.set(fn, safe);
		return safe;
	}

	// Script properties: engine-defined ones plus this.NAME used in script context.
	const scriptProperties = new Set(ENGINE_SCRIPT_PROPERTIES);
	for (const node of nodes) {
		if (node.type === "MemberExpression" && node.object.type === "ThisExpression" && isScriptContext(thisContext(node))) {
			const name = propertyName(node);
			if (name !== null) scriptProperties.add(name);
		}
		if (node.type === "CallExpression" && isMember(node.callee, "Object", "defineProperty") &&
			node.arguments[0] && node.arguments[0].type === "ThisExpression" &&
			node.arguments[1] && node.arguments[1].type === "Literal" && typeof node.arguments[1].value === "string") {
			scriptProperties.add(node.arguments[1].value);
		}
	}

	if (globalScope.through.some((ref) => ref.identifier.name === "eval")) blockers.push("calls eval()");
	if (nodes.some((n) => (n.type === "CallExpression" || n.type === "NewExpression") && n.callee.type === "Identifier" && n.callee.name === "Function")) {
		blockers.push("creates functions with Function()");
	}

	const declared = new Set(globalScope.variables.map((v) => v.name));
	const references = [];
	const unknown = new Map();
	for (const ref of globalScope.through) {
		const id = ref.identifier;
		const name = id.name;
		if (name === "uneval") notes.push(`line ${line(id)}: uneval() is a SpiderMonkey extension; it still works in Oolite, but JSON.stringify() is the standard alternative`);
		if (scriptProperties.has(name) && !declared.has(name)) {
			references.push(ref);
		} else if (!GLOBALS.has(name) && !declared.has(name)) {
			if (!unknown.has(name)) unknown.set(name, line(id));
		}
	}

	return { ast, nodes, blockers, notes, scriptProperties, references, unknown, isScriptContext, isSafeMethod };
}

function uniqueAlias(nodes)
{
	const used = new Set();
	for (const node of nodes) if (node.type === "Identifier") used.add(node.name);
	let alias = ALIAS_BASE;
	for (let i = 2; used.has(alias); i++) alias = ALIAS_BASE + i;
	return alias;
}

/*	options.instances: "single" for world scripts (one instance), "multiple"
	for everything else (the default, since it is the safe assumption).
	options.escaping: method names that other scripts pass around as values.
*/
function upgradeScript(source, options = {})
{
	const singleInstance = options.instances === "single";
	const bom = source.startsWith("﻿") ? "﻿" : "";
	const text = bom ? source.slice(1) : source;
	const result = { status: "not-upgraded", output: null, reasons: [], notes: [], unknownNames: [], changes: { constKeywords: 0, thisReferences: 0, aliasReferences: 0, aliases: 0 } };

	let original;
	try {
		original = acorn.parse(text, PARSE_OPTIONS);
	} catch (error) {
		if (!/has already been declared/.test(error.message)) {
			result.status = "parse-error";
			result.reasons.push(`does not parse: ${error.message}`);
			return result;
		}
	}
	if (original && hasMarker(original)) {
		result.status = "already-upgraded";
		return result;
	}

	let constEdits;
	try {
		constEdits = rewriteConst(text);
	} catch (error) {
		result.status = "parse-error";
		result.reasons.push(`does not parse: ${error.message}`);
		return result;
	}
	const step1 = applyEdits(text, constEdits);
	result.changes.constKeywords = constEdits.length;

	let analysis;
	try {
		analysis = analyse(step1, options.escaping);
	} catch (error) {
		result.status = "parse-error";
		result.reasons.push(`does not parse: ${error.message}`);
		return result;
	}
	const { ast, nodes, blockers, notes, references, unknown, isScriptContext, isSafeMethod } = analysis;
	result.notes.push(...notes);
	result.reasons.push(...blockers);
	for (const [name, lineNumber] of unknown) result.unknownNames.push({ name, line: lineNumber });

	const alias = uniqueAlias(nodes);
	const edits = [];
	const aliasFunctions = new Set();

	for (const ref of references) {
		const id = ref.identifier;
		const parent = id.parent;
		if ((parent.type === "Property" && parent.shorthand) || parent.type === "ArrayPattern" || parent.type === "ObjectPattern" ||
			(parent.type === "Property" && parent.parent.type === "ObjectPattern")) {
			result.reasons.push(`uses script property ${id.name} in a shorthand property or destructuring pattern (line ${line(id)})`);
			continue;
		}
		const context = thisContext(id);
		if (isScriptContext(context)) {
			edits.push({ start: id.start, end: id.start, text: "this." });
			result.changes.thisReferences++;
			continue;
		}
		// Find the nearest enclosing context whose `this` is the script.
		let owner = context;
		while (owner && !isScriptContext(owner)) owner = thisContext(owner);
		if (owner && (owner.type !== "Program" || singleInstance)) {
			aliasFunctions.add(owner);
			edits.push({ start: id.start, end: id.start, text: alias + "." });
			result.changes.aliasReferences++;
		} else {
			result.reasons.push(`refers to script property ${id.name} (line ${line(id)}) inside a function that isn't called with the script as this; ` +
				"in a script with one instance per ship or item this needs a manual change");
		}
	}

	if (result.reasons.length > 0) {
		result.status = "not-upgraded";
		return result;
	}

	// Aliases, added after any directives at the start of each function body (or the script).
	for (const owner of aliasFunctions) {
		if (owner.type === "Program") continue; // Added with the marker below.
		const body = owner.body;
		const directive = prologueEnd(body.body);
		const at = directive ? directive.end : body.start + 1;
		const separator = directive && !endsWithSemicolon(step1, directive) ? ";" : "";
		edits.push({ start: at, end: at, text: `${separator} var ${alias} = this;` });
		result.changes.aliases++;
	}

	let header = ` "${MARKER}";`;
	if (aliasFunctions.has(ast)) {
		header += ` var ${alias} = this;`;
		result.changes.aliases++;
	}
	const directive = prologueEnd(ast.body);
	if (directive) {
		const separator = endsWithSemicolon(step1, directive) ? "" : ";";
		edits.push({ start: directive.end, end: directive.end, text: separator + header });
	} else if (ast.body.length > 0) {
		const at = ast.body[0].start;
		edits.push({ start: at, end: at, text: header.slice(1) + " " });
	} else {
		edits.push({ start: 0, end: 0, text: header.slice(1) });
	}

	const output = applyEdits(step1, edits);

	// Check the result: it must parse, be marked and have no bare script property references left.
	let check;
	try {
		check = analyse(output, options.escaping);
	} catch (error) {
		result.reasons.push(`internal error: the upgraded script does not parse (${error.message})`);
		return result;
	}
	if (!hasMarker(check.ast) || check.references.length !== 0) {
		result.reasons.push("internal error: the upgraded script still has bare script property references");
		return result;
	}

	result.status = "upgraded";
	result.output = bom + output;
	return result;
}

/*	Method names that a script passes around as values of another script's
	properties, as worldScripts.NAME.method or worldScripts["NAME"].method,
	keyed by NAME. Also collects .script.method (ship scripts) under "*".
*/
function collectExternalEscapes(source, into)
{
	let ast;
	try {
		ast = acorn.parse(source.replace(/^﻿/, ""), PARSE_OPTIONS);
	} catch (error) {
		return;
	}
	const nodes = setParents(ast);
	for (const node of nodes) {
		if (node.type !== "MemberExpression") continue;
		const method = propertyName(node);
		if (method === null || !escapes(node)) continue;
		const object = node.object;
		let target = null;
		if (object.type === "MemberExpression" && object.object.type === "Identifier" && object.object.name === "worldScripts") {
			target = propertyName(object);
		} else if (object.type === "MemberExpression" && propertyName(object) === "script") {
			target = "*";
		}
		if (target === null) continue;
		if (!into.has(target)) into.set(target, new Set());
		into.get(target).add(method);
	}
}

// The script's name, from a top-level `this.name = "..."`.
function scriptName(source)
{
	let ast;
	try {
		ast = acorn.parse(source.replace(/^﻿/, ""), PARSE_OPTIONS);
	} catch (error) {
		return null;
	}
	for (const statement of ast.body) {
		const e = statement.expression;
		if (statement.type === "ExpressionStatement" && e.type === "AssignmentExpression" &&
			e.left.type === "MemberExpression" && e.left.object.type === "ThisExpression" &&
			propertyName(e.left) === "name" && e.right.type === "Literal" && typeof e.right.value === "string") {
			return e.right.value;
		}
	}
	return null;
}

module.exports = { MARKER, upgradeScript, collectExternalEscapes, scriptName };
