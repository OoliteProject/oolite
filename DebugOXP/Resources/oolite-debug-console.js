/*

oolite-debug-console.js

JavaScript section of JavaScript console implementation.

This script is attached to a one-off JavaScript object of type Console, which
represents the Objective-C portion of the implementation. Commands entered
into the console are passed to this script’s consolePerformJSCommand()
function. Since console commands are performed within the context of this
script, they have access to any functions in this script. You can therefore
add debugger commands using a customized version of this script.

The following properties are predefined for the script object:
	console: the console object.

The console object has the following properties and methods:

debugFlags : Number (integer, read/write)
	An integer bit mask specifying various debug options. The flags vary
	between builds, but at the time of writing they are:
		console.DEBUG_LINKED_LISTS
		console.DEBUG_COLLISIONS
		console.DEBUG_DOCKING
		console.DEBUG_OCTREE_LOGGING
		console.DEBUG_BOUNDING_BOXES
		console.DEBUG_OCTREE_DRAW
		console.DEBUG_DRAW_NORMALS
		console.DEBUG_NO_DUST
		console.DEBUG_NO_SHADER_FALLBACK
		console.DEBUG_SHADER_VALIDATION
		
	The current flags can be seen in OODebugFlags.h in the Oolite source code,
	for instance at:
		http://svn.berlios.de/svnroot/repos/oolite-linux/trunk/src/Core/Debug/OODebugFlags.h
		
	For example, to enable rendering of bounding boxes and surface normals,
	you might use:
		console.debugFlags ^= console.DEBUG_BOUNDING_BOXES
		console.debugFlags ^= console.DEBUG_DRAW_NORMALS
	
	Explaining bitwise operations is beyond the scope of this comment, but
	the ^= operator (XOR assign) can be thought of as a “toggle option”
	command.

dumpStackForErrors
	If true, when an error or exception is reported a stack trace will be
	written to the log (if possible). Ignored if not showing error locations.
 
dumpStackForWarnings
	If true, when an warning is reported a stack trace will be written to the
	log (if possible). Ignored if not showing error locations.

platformDescription : String (read-only)
	Information about the system Oolite is running on. The format of this
	string is not guaranteed, do not attempt to parse it.

settings : Object
	A key-value store that is saved persistently. Values from debugConfig.plist
	are used as defaults, and any changed values are stored with the game’s
	preferences.

showErrorLocations
	true if file and line should be shown when reporting JavaScript errors and
	warnings. Default: true.

showErrorLocationsDuringConsoleEval
	Override value for showErrorLocations used while evaluating code entered
	in the console. Default: false. (This information is generally not useful
	for code passed to eval().)

shaderMode : String (read/write)
	A string specifying the current shader mode. One of the following:
		"SHADERS_NOT_SUPPORTED"
		"SHADERS_OFF"
		"SHADERS_SIMPLE"
		"SHADERS_FULL"
	If it is SHADERS_NOT_SUPPORTED, it cannot be set to any other value. If it
	is not SHADERS_NOT_SUPPORTED, it can be set to SHADERS_OFF, SHADERS_SIMPLE
	or SHADERS_FULL, unless maximumShaderMode (see below) is SHADERS_SIMPLE,
	in which case SHADERS_FULL is not allowed.
	
	NOTE: this is equivalent to oolite.gameSettings.shaderEffectsLevel, which
	is available even when the debug console is not active, but is read-only.

maximumShaderMode: String (read-only)
	A string specifying the fanciest available shader mode. One of the following:
		"SHADERS_NOT_SUPPORTED"
		"SHADERS_SIMPLE"
		"SHADERS_FULL"

reducedDetailMode: Boolean (read/write)
	Whether reduced detail mode is in effect (simplifies graphics in various
	ways).

displayFPS : Boolean (read/write)
	Boolean specifying whether FPS (and associated information) should be
	displayed.
 
glVendorString : String (read-only)
glRendererString : String (read-only)
	Information about the OpenGL renderer.

	
function consoleMessage(colorCode : String, message : String [, emphasisStart : Number, emphasisLength : Number])
	Similar to log(), but takes a colour code which is looked up in
	debugConfig.plist. null is equivalent to "general". It can also optionally
	take a range of characters that should be emphasised.

function clearConsole()
	Clear the console.

function inspectEntity(entity : Entity)
	Show inspector palette for entity (Mac OS X only).

function displayMessagesInClass(class : String) : Boolean
	Returns true if the specified log message class is enabled, false otherwise.

function setDisplayMessagesInClass(class : String, flag : Boolean)
	Enable or disable logging of the specified log message class. For example,
	the equivalent of the legacy command debugOn is:
		console.setDisplayMessagesInClass("$scriptDebugOn", true);
	Metaclasses and inheritance work as in logcontrol.plist.
	
function isExecutableJavaScript(code : String) : Boolean
	Used to test whether code is runnable as-is. Returns false if the code has
	unbalanced braces or parentheses. (Used in consolePerformJSCommand() below.)

function profile(func : function [, this : Object]) : String
	Time the specified function, report the time spent in various Oolite
	functions and how much time is excluded from the time limiter mechanism.
	NOTE: while profile() is running, the time limiter is effectively disabled
	(specifically, it's set to ten million seconds).

function getProfile(func : function [, this : Object]) : Object
	Like profile(), but returns an object, which is more amenable to processing
	in scripts. To see the structure of the object, run:
	  console.getProfile(function(){PS.position.add([0, 0, 0])})

function writeLogMarker()
	Writes a separator to the log.


Useful properties of the console script (which can be used directly in the
console, e.g. “log($)”):

$
	The value of the last interesting (non-null, non-undefined) expression
	evaluated by the console. This includes values generated by macros.

result
	Set by some macros, such as :find.


The console script also adds two methods to all entities:
function dumpState()
	Writes information about the entity to the log. (This is the same stuff
	you get if you press 0 while paused, but for a single entity.)

function inspect()
	Calls console.inspectEntity() on the entity (see above; only useful in
	Mac OS X).


Oolite Debug OXP

Copyright © 2007-2012 the Oolite team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/


this.name			= "oolite-debug-console";
this.author			= "Jens Ayton";
this.copyright		= "© 2007-2012 the Oolite team.";
this.description	= "Debug console script.";
this.version		= "1.77";


(function() {

this.inputBuffer	= "";
this.$				= null;


// **** Macros

// Normally, these will be overwritten with macros from the config plist.
this.defaultMacros =
{
	setM:		"setMacro(PARAM)",
	delM:		"deleteMacro(PARAM)",
	showM:		"showMacro(PARAM)"
};
this.macros = {};


// ****  Convenience functions -- copy this script and add your own here.

// List the properties and values of an object.
this.dumpObject = function dumpObject(x)
{
	var description;
	if (typeof x == "object")
	{
		if (Array.isArray(x))  description = prettifyArray(x);
		else  description = prettifyObject(x);
	}
	else  description = prettify(x);
	
	consoleMessage("dumpObject", description);
}


this.protoChain = function protoChain(object)
{
	/*
		Box the value if it’s a primitive, because Object.getPrototypeOf()
		rejects primitives (ECMA-262 Rev. 1, 15.2.3.2, in a flagrant and
		apparently pointless violation of JavaScript’s normal autoboxing
		behaviour.)
	*/
	object = new Object(object);
	
	var result = "", first = true;
	for (;;)
	{
		var proto = Object.getPrototypeOf(object);
		if (!proto)  return result;
		if (!first)  result += ": ";
		else first = false;
		result += proto.constructor.name || "<anonymous>";
		object = proto;
	}
}


this.setColorFromString = function setColorFromString(string, typeName)
{ 
	// Slice of the first component, where components are separated by one or more spaces.
	var [key, value] = string.getOneToken();
	var fullKey = key + "-" + typeName + "-color";
	
	/*	Set the colour. The "var c" stuff is so that JS property lists (like
		{ hue: 240, saturation: 0.12 } will work -- this syntax is only valid
		in assignments.
	*/
	console.settings[fullKey] = eval("var c=" + value + ";c");
	
	consoleMessage("command-result", "Set " + typeName + " colour “" + key + "” to " + value + ".");
}


// ****  Conosole command handler

this.consolePerformJSCommand = function consolePerformJSCommand(command)
{
	var originalCommand = command;
	while (command.charAt(0) == " ")
	{
		command = command.substring(1);
	}
	while (command.length > 1 && command.charAt(command.length - 1) == "\n")
	{
		command = command.substring(0, command.length - 1);
	}
	
	if (command.charAt(0) != ":")
	{
		// No colon prefix, just JavaScript code.
		// Append to buffer, then run if runnable or empty line.
		this.inputBuffer += "\n" + originalCommand;
		if (command == "" || console.isExecutableJavaScript(console, this.inputBuffer))
		{
			// Echo input to console, emphasising the command itself.
			consoleMessage("command", "> " + command, 2, command.length);
			
			command = this.inputBuffer;
			this.inputBuffer = "";
			this.evaluate(command);
		}
		else
		{
			// Echo input to console, emphasising the command itself.
			consoleMessage("command", "_ " + command, 2, command.length);
		}
	}
	else
	{
		// Echo input to console, emphasising the command itself.
		consoleMessage("command", "> " + command, 2, command.length);
		
		// Colon prefix, this is a macro.
		this.performMacro(command);
	}
}


this.prettifyArray = function prettifyArray(value, indent)
{
	// NOTE: value may be an Arguments object.
	var i, length = value.length;
	var result = "[";
	for (i = 0; i < length; i++)
	{
		if (i > 0)  result += ", ";
		result += prettifyElement(value[i], indent);
	}
	result += "]";
	
	return result;
}

this.prettifyObject = function prettifyObject(value, indent)
{
	indent = indent || "";
	var subIndent = indent + "    ";
	
	var appendedAny = false;
	var result = "{";
	var separator = ",\n" + subIndent;
	for (var key in value)
	{
		var propVal = value[key];
		if (propVal === undefined)  continue;
		
		if (appendedAny)  result += separator;
		else  result += "\n" + subIndent;
		
		/*
			Highlighting inherited properties sounds desireable, but in
			practice it’s likely to be confusing since most host objects’
			apparent instance properties are actually inherited accessor-
			based properties.
		*/
		// if (!value.hasOwnProperty(key))  result += ">> ";
		
		// Quote string if necessary.
		if (isClassicIdentifier(key)) result += key;
		else  result += '"' + key.substituteEscapeCodes() + '"';
		
		result += ": " + prettifyElement(propVal, subIndent);
		appendedAny = true;
	}
	if (appendedAny)  result += "\n" + indent;
	result += "}";
	
	return result;
}


this.prettifyFunction = function prettifyFunction(value, indent)
{
	var funcDesc = value.toString();
	if (indent)
	{
		funcDesc = funcDesc.replace(/\n/g, "\n" + indent);
	}
	return funcDesc;
}


this.prettify = function prettify(value, indent)
{
	try
	{
		if (value === undefined)  return "undefined";
		if (value === null)  return "null";
		
		var type = typeof value;
		if (type == "boolean" ||
			type == "number" ||
			type == "xml" ||
			value.constructor === Number ||
			value.constructor === Boolean)
		{
			return value.toString();
		}
		
		if (type == "string" || value.constructor === String)
		{
			return value;
		}
		
		if (type == "function")
		{
			return prettifyFunction(value, indent);
		}
		
		if (Array.isArray(value))  return prettifyArray(value, indent);
		
		var stringValue = value.toString();
		if (stringValue == "[object Object]")
		{
			return prettifyObject(value, indent);
		}
		if (stringValue == "[object Arguments]" && value.length !== undefined)
		{
			return prettifyArray(value, indent);
		}
		
		return stringValue;
	}
	catch (e)
	{
		return value.toString();
	}
}


this.prettifyElement = function prettifyElement(value, indent)
{
	if (value === undefined)  return "undefined";
	if (value === null)  return "null";
	
	if (typeof value == "string" || value.constructor === String)
	{
		return '"' + value.substituteEscapeCodes() + '"';
	}
	
	return prettify(value, indent);
}


// ****  Macro handling

this.setMacro = function setMacro(parameters)
{
	if (!parameters)  return;
	
	// Split at first series of spaces
	var [name, body] = parameters.getOneToken();
	if (defaultMacros[name])
	{
		consoleMessage("macro-error", "Built-in macro " + name + " cannot be replaced.");
		return;
	}
	
	if (body)
	{
		macros[name] = body;
		console.settings["macros"] = macros;
		
		consoleMessage("macro-info", "Set macro :" + name + ".");
	}
	else
	{
		consoleMessage("macro-error", "setMacro(): a macro definition must have a name and a body.");
	}
}


this.deleteMacro = function deleteMacro(parameters)
{
	if (!parameters)  return;
	
	var [name, ] = parameters.getOneToken();
	
	if (name.charAt(0) == ":" && name != ":")  name = name.substring(1);
	
	if (defaultMacros[name])
	{
		consoleMessage("macro-error", "Built-in macro " + name + " cannot be deleted.");
		return;
	}
	
	if (macros[name])
	{
		delete macros[name];
		console.settings["macros"] = macros;
		
		consoleMessage("macro-info", "Deleted macro :" + name + ".");
	}
	else
	{
		consoleMessage("macro-info", "Macro :" + name + " is not defined.");
	}
}


this.listMacro = function listMacro()
{
	var tmp,l=[];
	for (var prop in defaultMacros)
	{
		l.push( ":" + prop);
	}
	l.sort();
	tmp = l.join("\n");
	l=[];
	for (var prop in macros)
	{
		if (!defaultMacros[prop]) l.push( ":" + prop);
	}
	l.sort();
	consoleMessage("macro-list", tmp + l.join("\n"));
}


this.resolveMacro = function resolveMacro(name)
{
	if (defaultMacros[name])  return defaultMacros[name];
	else  if (macros[name])  return macros[name];
	else  return null;
}


this.showMacro = function showMacro(parameters)
{
	if (!parameters)  return;
	
	var [name, ] = parameters.getOneToken();
	
	if (name.charAt(0) == ":" && name != ":")  name = name.substring(1);
	
	var macro = resolveMacro(name);
	if (macro)
	{
		consoleMessage("macro-info", ":" + name + " = " + macro);
	}
	else
	{
		consoleMessage("macro-info", "Macro :" + name + " is not defined.");
	}
}


this.performMacro = function performMacro(command)
{
	if (!command)  return;
	
	// Strip the initial colon
	command = command.substring(1);
	
	// Split at first series of spaces
	var [macroName, parameters] = command.getOneToken();
	var expansion = resolveMacro(macroName);
	if (expansion)
	{
		// Show macro expansion.
		var displayExpansion = expansion;
		if (parameters)
		{
			// Substitute parameter string into display expansion, going from 'foo(PARAM)' to 'foo("parameters")'.
			displayExpansion = displayExpansion.replace(/PARAM/g, '"' + parameters.substituteEscapeCodes() + '"');
		}
		consoleMessage("macro-expansion", "> " + displayExpansion);
		
		// Perform macro.
		this.evaluate(expansion, parameters);
	}
	else
	{
		consoleMessage("unknown-macro", "Macro :" + macroName + " is not defined.");
	}
}


// ****  Utility functions

/*
	Split a string at the first sequence of spaces, returning an array with
	two elements. If there are no spaces, the first element of the result will
	be the input string, and the second will be null. Leading spaces are
	stripped. Examples:
	
	"x y"   -->  ["x", "y"]
	"x   y" -->  ["x", "y"]
	"  x y" -->  ["x", "y"]
	"xy"    -->  ["xy", null]
	" xy"   -->  ["xy", null]
	""      -->  ["", null]
	" "     -->  ["", null]
 */
String.prototype.getOneToken = function getOneToken()
{
	var matcher = /\s+/g;		// Regular expression to match one or more spaces.
	matcher.lastIndex = 0;
	var match = matcher.exec(this);
	
	if (match)
	{
		var token = this.substring(0, match.index);		// Text before spaces
		var tail = this.substring(matcher.lastIndex);	// Text after spaces
		
		if (token.length != 0)  return [token, tail];
		else  return tail.getOneToken();	// Handle leading spaces case. This won't recurse more than once.
	}
	else
	{
		// No spaces
		return [this, null];
	}
}



/*
	Replace special characters in string with escape codes, for displaying a
	string literal as a JavaScript literal. (Used in performMacro() to echo
	macro expansion.)
 */
String.prototype.substituteEscapeCodes = function substituteEscapeCodes()
{
	var string = this.replace(/\\/g, "\\\\");	// Convert \ to \\ -- must be first since we’ll be introducing new \s below.
	
	string = string.replace(/\x08/g, "\\b");	// Backspace to \b
	string = string.replace(/\f/g, "\\f");		// Form feed to \f
	string = string.replace(/\n/g, "\\n");		// Newline to \n
	string = string.replace(/\r/g, "\\r");		// Carriage return to \r
	string = string.replace(/\t/g, "\\t");		// Horizontal tab to \t
	string = string.replace(/\v/g, "\\v");		// Vertical tab to \v
	string = string.replace(/\'/g, '\\\'');		// ' to \'
	string = string.replace(/\"/g, "\\\"");		// " to \"

	return string;
}


this.isClassicIdentifier = function isClassicIdentifier(string)
{
	/*
		JavaScript allows any Unicode letter or digit in an indentifier.
		However, JavaScript regexps don’t have shortcuts for Unicode letters
		and digits. Smort!
		Therefore, this function only returns true for ASCII identifiers.
	*/
	if (!string)  return false;	// Note that the empty string is a falsey value.
	
	if (/[^\w\$]/.test(string))  return false;	// Contains non-identifier characters.
	if (/\d/.test(string[0]))  return false;	// Starts with a digit.
	
	var reservedWords =
	[
	 // ECMAScript 5 keywords.
	 "break",
	 "case",
	 "catch",
	 "continue",
	 "debugger",
	 "default",
	 "delete",
	 "do",
	 "else",
	 "finally",
	 "for",
	 "function",
	 "if",
	 "in",
	 "instanceof",
	 "typeof",
	 "new",
	 "var",
	 "return",
	 "void",
	 "switch",
	 "while",
	 "this",
	 "with",
	 "throw",
	 "try",
	 
	 // Future reserved words.
	 "class",
	 "enum",
	 "extends",
	 "super",
	 "const",
	 "export",
	 "import",
	 
	 // Strict Mode future reserved words.
	 "implements",
	 "let",
	 "private",
	 "public",
	 "interface",
	 "package",
	 "protected",
	 "static",
	 "yield",
	 
	 // Literals.
	 "null",
	 "true",
	 "false",
	 
	 // Not formally reserved, but potentially confusing or with special rules.
	 "undefined",
	 "eval",
	 "arguments"
	];
	if (reservedWords.indexOf(string) != -1)  return false;
	
	return true;
}


// ****  Load-time set-up
 
// Make console globally visible as console (and debugConsole, for backwards compatibility).
global.console = this.console;
Object.defineProperty(global, "debugConsole", { value: console, enumerable: false, configurable: true, writable: true });
console.script = this;


// Load macros.
if (console.settings["macros"])  this.macros = console.settings["macros"];
if (console.settings["default-macros"])  this.defaultMacros = console.settings["default-macros"];


// Implement console.showErrorLocations with persistence.
Object.defineProperty(console, "showErrorLocations",
{
	get: function () { return console.__showErrorLocations },
	set: function (value)  { console.settings["show-error-locations"] = console.__showErrorLocations = !!value; },
	enumerable: true
});
console.__showErrorLocations = console.settings["show-error-locations"];


// Implement console.showErrorLocationsDuringConsoleEval with persistence.
Object.defineProperty(console, "showErrorLocationsDuringConsoleEval",
{
	get: function () { return console.settings["show-error-locations-during-console-eval"] ? true : false; },
	set: function (value)  { console.settings["show-error-locations-during-console-eval"] = !!value; },
	enumerable: true
});


// Implement console.dumpStackForErrors with persistence.
Object.defineProperty(console, "dumpStackForErrors",
{
	get: function () { return console.__dumpStackForErrors },
	set: function (value)  { console.settings["dump-stack-for-errors"] = console.__dumpStackForErrors = !!value; },
	enumerable: true
});
console.__dumpStackForErrors = console.settings["dump-stack-for-errors"];


// Implement console.dumpStackForWarnings with persistence.
Object.defineProperty(console, "dumpStackForWarnings",
{
	get: function () { return console.__dumpStackForWarnings },
	set: function (value)  { console.settings["dump-stack-for-warnings"] = console.__dumpStackForWarnings = !!value; },
	enumerable: true
});
console.__dumpStackForWarnings = console.settings["dump-stack-for-warnings"];


/*	As a convenience, make player, player.ship, system and missionVariables
	available to console commands as short variables:
*/
this.P = player;
this.PS = player.ship;
this.S = system;
this.M = missionVariables;


// Make console.consoleMessage() globally visible
Object.defineProperty (global, "consoleMessage", { value: function consoleMessage()
{
	// Call console.consoleMessage() with console as "this" and all the arguments passed to consoleMessage().
	console.consoleMessage.apply(console, arguments);
}});


// Add inspect() method to all entities, to show inspector palette (Mac OS X only; no effect on other platforms).
Object.defineProperty(Entity.prototype, "inspect", { value: function inspect()
{
	console.inspectEntity(this);
}});


/*
	Add callObjC() method to all objects. In debug builds only, this can be
	used to call an Objective-C method on the Objective-C representation of
	an object. (For entities and some other Oolite-defined objects, this is
	the underlying native object. Most other objects will be converted into
	property list types.)
	
	Supported method types are:
	  * Methods taking no parameters and returning nothing
	  * Methods taking no parameter and returning one of:
		- nothing
		- an object
		- a number
		- a vector or quaternion struct
	  * Methods taking one object parameter and returning nothing
	  * Methods taking one object parameter and returning an object
	
	As a special case, if a method’s name ends with _bool and it returns an
	object, it is parsed as a property list representing a boolean. This
	handles predicate methods from the legacy script system.
*/
if (typeof console.__setUpCallObjC == "function")
{
	console.__setUpCallObjC(Object.prototype);	//not enumerable.
}
else
{
	// not enumerable when disabled too.
	Object.defineProperty(Object.prototype, 'callObjC', {value: function()
		{
			throw Error("callObjC() is disabled.");
		}
	});
}

}).call(this);


/*
	evaluate() is outside the closure specifically to avoid strict mode.
	If evaluate() is compiled in strict mode, all console input will also be
	strict. Also, evaluate() should be as close to the bottom as possible
	because everything from the eval() down is tagged "<console input>" in
	stack dumps, profiles and traces.
*/
this.evaluate = function evaluate(command, PARAM)
{
	var showErrorLocations = console.__showErrorLocations;
	console.__showErrorLocations = console.showErrorLocationsDuringConsoleEval;
	try
	{
		var result = eval(command);
	}
	catch (e)
	{
		// console.__showErrorLocations must be reset _after_ the exception is handed.
		this.resetErrorLocTimer = new Timer(this, function () { console.__showErrorLocations = showErrorLocations; delete this.resetErrorLocTimer; }, 0);
		throw e;
	}
	console.__showErrorLocations = showErrorLocations;
	
	if (result !== undefined)
	{
		if (result === null)  result = "null";
		else  this.$ = result;
		consoleMessage("command-result", prettify(result));
	}
}


// Identify the location of the eval() command above for the debug location formatter.
this.markConsoleEntryPoint = special.markConsoleEntryPoint;
this.evaluate("console.script.markConsoleEntryPoint()");
delete this.markConsoleEntryPoint;
