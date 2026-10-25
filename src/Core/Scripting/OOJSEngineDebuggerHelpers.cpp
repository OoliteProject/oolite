/*

OOJSEngineDebuggerHelpers.mm

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

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


/*
	These functions exist to help debugging JavaScript code. They can be called
	directly from gdb, for example:
	
		call (char *)JSValueToStrDbg(someValue)
	
	The functions are:
	
		const char *JSValueToStrDbg(ooscript::Value)
		const char *JSObjectToStrDbg(ooscript::Object)
		const char *JSStringToStrDbg(ooscript::String)
		Converts any JS value/object/JSString to a string, using the complete
		process and potentially calling into SpiderMonkey with a secondory
		context and invoking JS toString() methods. This might mess up
		SpiderMonkey internal state in some cases.
		
		const char *JSValueToStrSafeDbg(ooscript::Value)
		const char *JSObjectToStrSafeDbg(ooscript::Object)
		const char *JSStringToStrSafeDbg(ooscript::String)
		As above, but without calling into SpiderMonkey functions that require
		a context. In particular, as of the FF4b9 version of SpiderMonkey only
		interned strings can be converted, and for objects only the class name
		is provided.
		
		const char *JSIDToStrSafeDbg(ooscript::PropertyId)
		Like JSValueToStrSafeDbg() for jsids. (String jsids must always be
		interned, so this is generally sufficient.)
		
		const char *JSValueTypeDbg(ooscript::Value)
		Returns the type of the ooscript::Value, or the class name if it's an object.
	
	All dynamic strings are autoreleased.
 
	 Another useful function is OOJSDumpStack (results are found in the log):
		
		call OOJSDumpStack(context)
	
	A set of macros can be found in tools/gdb-macros.txt.
	In almost all Oolite functions that deal with JavaScript, there is a single
	ooscript::Context called "context". In engine functions, it's called "cx".
	
	
	In addition to calling them from the debug console, Xcode users might want
	to use them in data formatters (by double-clicking the "Summary" field for
	a variable of the appropriate type). I recommend the following:
	
		ooscript::Value:		{JSValueToStrSafeDbg($VAR)}:s
		ooscript::Value*:		{JSValueToStrSafeDbg(*$VAR)}:s
		ooscript::PropertyId:		{JSIDToStrSafeDbg($VAR)}:s
		ooscript::Object :	{JSObjectToStrSafeDbg($VAR)}:s
		ooscript::String :	{JSStringToStrSafeDbg($VAR)}:s
	
	These, and a variety of Oolite type formatters, can be set up using
	Mac-specific/DataFormatters.
*/


#ifndef NDEBUG

#include "OOJavaScriptEngine.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) per bead oo-4kf, the same way bead oo-sdz
	retargeted OOJSVector.mm (the exemplar for this sweep; see its header comment for the full
	rationale) and bead oo-45g retargeted OOJSQuaternion.mm.

	Every value and id is inspected through the façade's predicates and accessors (bead oo-1gc.3).
	The façade cannot distinguish the engine's internal value and id kinds, so the cases that
	read them directly are gone: the debug-build magic-value switch in JSValueTypeDbg() (array
	hole, args hole, native enumerate, ...), and the empty / zero / object / default-XML-namespace
	id kinds and the raw id bits in JSIDToStrSafeDbg(). Such values now report "unknown". An
	object whose class is not one of Oolite's own (the façade's getClass() answers null for the
	engine's built-in classes) reports "object".

	The public functions keep external linkage on purpose: they are called by name from gdb and
	Xcode data formatters, per this file's own header comment above, never through a declaration
	in a header that clang-tidy's misc-use-internal-linkage could see.
*/

namespace ooscript { }
using ooscript::String;

namespace {
// The text a *SafeDbg function returns stays valid until the next such call (it was an autoreleased
// string's UTF-8 buffer, valid until the pool drained); the debugger prints it straight away.
static const char *DebuggerCString(std::string text)
{
	static std::string sText;
	sText = std::move(text);
	return sText.c_str();
}
} // namespace


const char *JSValueToStrDbg(ooscript::Value val)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	ooscript::Context context = OOJSAcquireContext();
	const std::optional<std::string> text = cxx_OOStringFromJSValueEvenIfNull(context, val);
	const char *result = text.has_value() ? DebuggerCString(*text) : NULL;
	OOJSRelinquishContext(context);
	
	return result;
}


const char *JSObjectToStrDbg(ooscript::Object obj)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	if (obj == NULL)  return "null";
	return JSValueToStrDbg(ooscript::objectValue(obj));
}


const char *JSStringToStrDbg(ooscript::String str)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	if (str == NULL)  return "null";
	return JSValueToStrDbg(ooscript::stringValue(str));
}


const char *JSValueTypeDbg(ooscript::Value val)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	if (ooscript::isInt32(val))		return "integer";
	if (ooscript::isDouble(val))	return "double";
	if (ooscript::isString(val))	return "string";
	if (ooscript::isBoolean(val))	return "boolean";
	if (ooscript::isNull(val))		return "null";
	if (ooscript::isUndefined(val))	return "void";
	if (ooscript::isObjectOrNull(val))
	{
		// Fun fact: although a context is required if the engine is built thread-safe, it isn't actually used.
		const ooscript::ClassDef *objClass = OOJSGetClass(NULL, ooscript::toObject(val));
		return (objClass != NULL) ? objClass->name : "object";
	}
	return "unknown";
}


// Doesn't follow pointers, mess with requests or otherwise poke the SpiderMonkey.
const char *JSValueToStrSafeDbg(ooscript::Value val)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	std::string formatted;
	
	if (ooscript::isInt32(val))			formatted = oo::str::format("%i", ooscript::toInt32(val));
	else if (ooscript::isDouble(val))	formatted = oo::str::format("%g", ooscript::toDouble(val));
	else if (ooscript::isBoolean(val))	formatted = (ooscript::toBoolean(val)) ? "true" : "false";
	else if (ooscript::isString(val))
	{
		ooscript::String string = ooscript::toString(val);
		const ooscript::Char16	*chars = NULL;
		size_t			length = ooscript::getStringLength((string));
		
		if (ooscript::stringHasBeenInterned(nullptr, (string)))
		{
			chars = ooscript::getInternedStringChars((string));
		}
		// Flat strings can be extracted without a context, but cannot be detected.
		
		if (chars == NULL)  formatted = oo::str::format("string [%zu chars]", length);
		else  formatted = oo::utf16ToUtf8(std::u16string_view(chars, length));
	}
	else if (ooscript::isUndefined(val))	return "undefined";
	else							return JSValueTypeDbg(val);
	
	return DebuggerCString(std::move(formatted));
}


const char *JSObjectToStrSafeDbg(ooscript::Object obj)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	if (obj == NULL)  return "null";
	return JSValueToStrSafeDbg(ooscript::objectValue(obj));
}


const char *JSStringToStrSafeDbg(ooscript::String str)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	if (str == NULL)  return "null";
	return JSValueToStrSafeDbg(ooscript::stringValue(str));
}


const char *JSIDToStrSafeDbg(ooscript::PropertyId anID)  // NOLINT(misc-use-internal-linkage): called by name from gdb, see file header.
{
	std::string formatted;
	
	if (ooscript::isInt32Id(anID))			formatted = oo::str::format("%i", ooscript::idToInt32(anID));
	else if (ooscript::isVoidId(anID))	return "void";
	else if (ooscript::isStringId(anID))
	{
		ooscript::String string = ooscript::idToString(anID);
		const ooscript::Char16	*chars = NULL;
		size_t			length = ooscript::getStringLength((string));
		
		if (ooscript::stringHasBeenInterned(nullptr, (string)))
		{
			chars = ooscript::getInternedStringChars((string));
		}
		else
		{
			// Bug; ooscript::PropertyId strings must be interned.
			return "*** uninterned string in ooscript::PropertyId! ***";
		}
		formatted = oo::utf16ToUtf8(std::u16string_view(chars, length));
	}
	else  return "unknown";
	
	return DebuggerCString(std::move(formatted));
}
#endif
