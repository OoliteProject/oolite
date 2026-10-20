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
	// SpiderMonkey returned decompiled source; QuickJS keeps the original source text.
	define(Function.prototype, "toSource", function toSource() { return Function.prototype.toString.call(this); });
})(globalThis);
