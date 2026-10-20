/*

oolite-quickjs-compat.js

Compatibility definitions for SpiderMonkey 1.8.5 extensions that OXPs use and
QuickJS-ng lacks. Loaded only by the QuickJS-ng engine, before any other
script, in the global scope. Everything is defined non-enumerable,
as the SpiderMonkey built-ins were.


Oolite
Copyright © 2004-2026 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

(function (global)
{
	"use strict";

	function define(object, name, value)
	{
		if (!Object.prototype.hasOwnProperty.call(object, name))
		{
			Object.defineProperty(object, name, { value: value, writable: true, configurable: true, enumerable: false });
		}
	}

	function quote(string)
	{
		return "\"" + String(string).replace(/[\\"\n\r\t\b\f\v\u0000-\u001f\u2028\u2029]/g, function (c)
		{
			switch (c)
			{
				case "\\": return "\\\\";
				case "\"": return "\\\"";
				case "\n": return "\\n";
				case "\r": return "\\r";
				case "\t": return "\\t";
				case "\b": return "\\b";
				case "\f": return "\\f";
				case "\v": return "\\v";
			}
			var hex = c.charCodeAt(0).toString(16);
			return "\\u" + "0000".substr(hex.length) + hex;
		}) + "\"";
	}

	function isIdentifier(name)
	{
		return /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name);
	}

	// uneval(value): source representation of any value, as in SpiderMonkey.
	function uneval(value, seen)
	{
		switch (typeof value)
		{
			case "undefined": return "(void 0)";
			case "string": return quote(value);
			case "number": return (value === 0 && 1 / value < 0) ? "-0" : String(value);
			case "boolean": return String(value);
			case "symbol": return value.toString();
			case "bigint": return String(value) + "n";
		}
		if (value === null) return "null";
		if (typeof value.toSource === "function" && value.toSource !== Object.prototype.toSource)
		{
			return value.toSource();
		}
		return objectToSource(value, seen);
	}

	function objectToSource(object, seen)
	{
		seen = seen || [];
		if (seen.indexOf(object) !== -1) return "{}"; // SpiderMonkey used sharp variables here.
		seen.push(object);
		try
		{
			var parts = Object.keys(object).map(function (key)
			{
				var name = isIdentifier(key) || /^(0|[1-9][0-9]*)$/.test(key) ? key : quote(key);
				return name + ":" + uneval(object[key], seen);
			});
			return "({" + parts.join(", ") + "})";
		}
		finally
		{
			seen.pop();
		}
	}

	define(global, "uneval", function uneval_(value) { return uneval(value); });

	define(Object.prototype, "toSource", function toSource() { return objectToSource(this); });
	define(Array.prototype, "toSource", function toSource()
	{
		var array = this;
		return "[" + Array.prototype.map.call(array, function (item) { return uneval(item, [array]); }).join(", ") + "]";
	});
	define(String.prototype, "toSource", function toSource() { return "(new String(" + quote(String(this)) + "))"; });
	define(Number.prototype, "toSource", function toSource() { return "(new Number(" + uneval(Number(this)) + "))"; });
	define(Boolean.prototype, "toSource", function toSource() { return "(new Boolean(" + String(Boolean(this.valueOf())) + "))"; });
	define(Date.prototype, "toSource", function toSource() { return "(new Date(" + uneval(this.getTime()) + "))"; });
	define(RegExp.prototype, "toSource", function toSource() { return this.toString(); });
	define(Error.prototype, "toSource", function toSource()
	{
		return "(new " + this.name + "(" + quote(this.message) + ", " + quote(this.fileName || "") + ", " + (this.lineNumber || 0) + "))";
	});
	/*	Rewrite SpiderMonkey 1.8.5 style const declarations as var.

		In SpiderMonkey 1.8.5, const was function-scoped like var and could be
		used before its declaration; modern engines make it block-scoped with a
		temporal dead zone, which breaks some OXPs. Replacing the keyword with
		"var  " (same length, so columns and line numbers are unchanged) restores
		the old scoping; only the read-only check is lost.

		The scanner understands comments, strings, template literals (with nested
		substitutions) and regular expression literals, so only const keywords in
		code are replaced. It is not a full parser: it decides whether "/" starts a
		regular expression from the previous significant token.
	*/
	function oojsRewriteLegacyConst(source)
	{
		if (source.indexOf("const") === -1) return source;

		var out = [];
		var length = source.length;
		var i = 0, last = 0;
		var prevToken = "";           // previous significant token (for the regex/division decision)
		var templateDepth = [];       // brace depth at each open template substitution
		var braceDepth = 0;
		var parenOwners = [];         // token before each open "(", to spot if (...) /re/

		var regexAfterWords = { "return": 1, "typeof": 1, "instanceof": 1, "in": 1, "of": 1, "new": 1, "delete": 1, "void": 1, "throw": 1, "case": 1, "do": 1, "else": 1, "yield": 1, "await": 1 };

		function isIdentStart(c) { return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c === "_" || c === "$" || c > "\x7f"; }
		function isIdentPart(c) { return isIdentStart(c) || (c >= "0" && c <= "9"); }
		function regexAllowed()
		{
			if (prevToken === "") return true;
			if (prevToken === ")" || prevToken === "]" || prevToken === "}") return false;
			if (/^[A-Za-z_$\x80-￿][\w$\x80-￿]*$/.test(prevToken)) return regexAfterWords.hasOwnProperty(prevToken);
			if (/^[0-9.]/.test(prevToken) || prevToken === "string" || prevToken === "template" || prevToken === "regex") return false;
			return true; // operator or punctuation
		}
		function skipString(quote)
		{
			i++;
			while (i < length && source[i] !== quote)
			{
				if (source[i] === "\\") i++;
				else if (source[i] === "\n" && quote !== "`") break;
				i++;
			}
			i++;
		}
		// Scan template text from i (just after ` or }) to the closing ` or an opening ${.
		function scanTemplateText()
		{
			while (i < length)
			{
				var c = source[i];
				if (c === "\\") { i += 2; continue; }
				if (c === "`") { i++; return false; }
				if (c === "$" && source[i + 1] === "{") { i += 2; return true; }
				i++;
			}
			return false;
		}

		while (i < length)
		{
			var c = source[i];
			var next = source[i + 1];

			if (c === " " || c === "\t" || c === "\n" || c === "\r" || c === "\v" || c === "\f" || c === " " || c === "﻿") { i++; continue; }
			if (c === "/" && next === "/") { while (i < length && source[i] !== "\n" && source[i] !== "\r") i++; continue; }
			if (c === "/" && next === "*") { var end = source.indexOf("*/", i + 2); i = end === -1 ? length : end + 2; continue; }
			if (c === "\"" || c === "'") { skipString(c); prevToken = "string"; continue; }
			if (c === "`")
			{
				i++;
				if (scanTemplateText()) { templateDepth.push(braceDepth); prevToken = "{"; braceDepth++; }
				else prevToken = "template";
				continue;
			}
			if (c === "}" && templateDepth.length && templateDepth[templateDepth.length - 1] === braceDepth - 1)
			{
				braceDepth--;
				templateDepth.pop();
				i++;
				if (scanTemplateText()) { templateDepth.push(braceDepth); prevToken = "{"; braceDepth++; }
				else prevToken = "template";
				continue;
			}
			if (c === "/" && regexAllowed())
			{
				i++;
				var inClass = false;
				while (i < length)
				{
					var r = source[i];
					if (r === "\\") { i += 2; continue; }
					if (r === "\n") break;
					if (r === "[") inClass = true;
					else if (r === "]") inClass = false;
					else if (r === "/" && !inClass) { i++; break; }
					i++;
				}
				while (i < length && isIdentPart(source[i])) i++; // flags
				prevToken = "regex";
				continue;
			}
			if (isIdentStart(c))
			{
				var start = i;
				while (i < length && isIdentPart(source[i])) i++;
				var word = source.slice(start, i);
				if (word === "const" && prevToken !== ".")
				{
					// Not an object literal key ({ const: 1 }).
					var j = i;
					while (j < length && /\s/.test(source[j])) j++;
					if (source[j] !== ":")
					{
						out.push(source.slice(last, start), "var  ");
						last = i;
					}
				}
				prevToken = word;
				continue;
			}
			if (c >= "0" && c <= "9" || (c === "." && next >= "0" && next <= "9"))
			{
				while (i < length && /[\w.$]/.test(source[i])) i++;
				prevToken = "0";
				continue;
			}
			if (c === "{") braceDepth++;
			else if (c === "}") braceDepth--;
			else if (c === "(") parenOwners.push(prevToken);
			else if (c === ")")
			{
				var owner = parenOwners.pop();
				if (owner === "if" || owner === "while" || owner === "for" || owner === "with")
				{
					// A statement follows the condition, so "/" starts a regular expression.
					prevToken = ";";
					i++;
					continue;
				}
			}
			prevToken = c;
			i++;
		}

		if (last === 0) return source;
		out.push(source.slice(last));
		return out.join("");
	}

	// Called by the engine on every script before it is compiled (OOJSScript.m).
	define(global, "__ooliteRewriteLegacyConst", oojsRewriteLegacyConst);

	// SpiderMonkey returned decompiled source; QuickJS keeps the original source text.
	define(Function.prototype, "toSource", function toSource() { return Function.prototype.toString.call(this); });
})(globalThis);
