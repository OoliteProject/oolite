/*
	Names the upgrader needs to know about.

	GLOBALS is the union of the global object's own property names in Oolite
	1.92 (SpiderMonkey 1.8.5) and in the QuickJS-ng builds, as logged by the
	game, plus globals that only exist in some setups (the debug console's).
	A bare name in this list is not a script property reference unless the
	script also defines a property of that name.

	ENGINE_SCRIPT_PROPERTIES are set on script objects by Oolite itself
	(ship scripts get `ship`, equipment scripts `equipmentKey` and so on), or
	inherited from the Script prototype. Scripts can refer to them by bare
	name, because the script object is on the scope chain.
*/

"use strict";

const GLOBALS = new Set([
	// ECMAScript and engine built-ins.
	"AggregateError", "Array", "ArrayBuffer", "AsyncDisposableStack", "Atomics", "BigInt", "BigInt64Array",
	"BigUint64Array", "Boolean", "DataView", "Date", "DisposableStack", "Error", "EvalError",
	"FinalizationRegistry", "Float16Array", "Float32Array", "Float64Array", "Function", "Infinity",
	"Int16Array", "Int32Array", "Int8Array", "InternalError", "Iterator", "JSON", "Map", "Math", "NaN",
	"Namespace", "Number", "Object", "Promise", "Proxy", "QName", "RangeError", "ReferenceError", "Reflect",
	"RegExp", "Set", "SharedArrayBuffer", "StopIteration", "String", "SuppressedError", "Symbol",
	"SyntaxError", "TypeError", "URIError", "Uint16Array", "Uint32Array", "Uint8Array",
	"Uint8ClampedArray", "WeakMap", "WeakRef", "WeakSet", "XML", "XMLList", "atob", "btoa", "decodeURI",
	"decodeURIComponent", "encodeURI", "encodeURIComponent", "escape", "eval", "globalThis", "isFinite",
	"isNaN", "isXMLName", "parseFloat", "parseInt", "performance", "queueMicrotask", "undefined",
	"unescape", "uneval",
	// Oolite classes.
	"Clock", "Dock", "Entity", "EquipmentInfo", "ExhaustPlume", "Flasher", "Manifest", "Mission", "Oolite",
	"Planet", "Player", "PlayerShip", "Quaternion", "Script", "Ship", "ShipGroup", "Sound", "SoundSource",
	"Station", "Sun", "System", "SystemInfo", "Timer", "Vector3D", "VisualEffect", "Waypoint", "Wormhole",
	// Oolite global objects and functions.
	"addFrameCallback", "autoAIForRole", "clearExtraGuiScreenKeys", "clock", "defaultFont",
	"displayNameForCommodity", "expandDescription", "expandMissionText", "formatCredits", "formatInteger",
	"galaxyNumber", "getGuiColorSettingForKey", "getScreenBackgroundForKey", "global", "guiScreen",
	"isValidFrameCallback", "keyBindingDescription", "log", "manifest", "mission", "missionVariables",
	"oolite", "pauseGame", "player", "quitGame", "randomInhabitantsDescription", "randomName",
	"removeFrameCallback", "setExtraGuiScreenKeys", "setGuiColorSettingForKey", "setScreenBackground",
	"setScreenBackgroundForKey", "setScreenOverlay", "system", "takeSnapShot", "timeAccelerationFactor",
	"worldScriptNames", "worldScripts",
	// Defined only when the debug console OXP is installed.
	"console", "debugConsole",
]);

const ENGINE_SCRIPT_PROPERTIES = new Set([
	"ship", "equipmentKey", "character", "visualEffect", "legacy_setupActions",
	"oolite_manifest_identifier",
	// The debug console script's privileged helper object.
	"special",
	// Script.prototype
	"coordinatesForEscortPosition", "toString", "constructor",
]);

module.exports = { GLOBALS, ENGINE_SCRIPT_PROPERTIES };
