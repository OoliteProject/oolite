/*

OOJSEngineDebuggerHelpers.m

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
	
		const char *JSValueToStrDbg(jsval)
		const char *JSObjectToStrDbg(JSObject *)
		const char *JSStringToStrDbg(JSString *)
		Converts any JS value/object/JSString to a string, using the complete
		process and potentially calling into SpiderMonkey with a secondory
		context and invoking JS toString() methods. This might mess up
		SpiderMonkey internal state in some cases.
		
		const char *JSValueToStrSafeDbg(jsval)
		const char *JSObjectToStrSafeDbg(JSObject *)
		const char *JSStringToStrSafeDbg(JSString *)
		As above, but without calling into SpiderMonkey functions that require
		a context. In particular, as of the FF4b9 version of SpiderMonkey only
		interned strings can be converted, and for objects only the class name
		is provided.
		
		const char *JSIDToStrSafeDbg(jsid)
		Like JSValueToStrSafeDbg() for jsids. (String jsids must always be
		interned, so this is generally sufficient.)
		
		const char *JSValueTypeDbg(jsval)
		Returns the type of the jsval, or the class name if it's an object.
	
	All dynamic strings are autoreleased.
 
	 Another useful function is OOJSDumpStack (results are found in the log):
		
		call OOJSDumpStack(context)
	
	A set of macros can be found in tools/gdb-macros.txt.
	In almost all Oolite functions that deal with JavaScript, there is a single
	JSContext called "context". In SpiderMonkey functions, it's called "cx".
	
	
	In addition to calling them from the debug console, Xcode users might want
	to use them in data formatters (by double-clicking the "Summary" field for
	a variable of the appropriate type). I recommend the following:
	
		jsval:		{JSValueToStrSafeDbg($VAR)}:s
		jsval*:		{JSValueToStrSafeDbg(*$VAR)}:s
		jsid:		{JSIDToStrSafeDbg($VAR)}:s
		JSObject*:	{JSObjectToStrSafeDbg($VAR)}:s
		JSString*:	{JSStringToStrSafeDbg($VAR)}:s
	
	These, and a variety of Oolite type formatters, can be set up using
	Mac-specific/DataFormatters.
*/


#ifndef NDEBUG

#import "OOJavaScriptEngine.h"


const char *JSValueToStrDbg(jsval val)
{
	JSContext *context = OOJSAcquireContext();
	const char *result = [OOStringFromJSValueEvenIfNull(context, val) UTF8String];
	OOJSRelinquishContext(context);
	
	return result;
}


const char *JSObjectToStrDbg(JSObject *obj)
{
	if (obj == NULL)  return "null";
	return JSValueToStrDbg(OBJECT_TO_JSVAL(obj));
}


const char *JSStringToStrDbg(JSString *str)
{
	if (str == NULL)  return "null";
	return JSValueToStrDbg(STRING_TO_JSVAL(str));
}


const char *JSValueTypeDbg(jsval val)
{
	if (JSVAL_IS_INT(val))		return "integer";
	if (JSVAL_IS_DOUBLE(val))	return "double";
	if (JSVAL_IS_STRING(val))	return "string";
	if (JSVAL_IS_BOOLEAN(val))	return "boolean";
	if (JSVAL_IS_NULL(val))		return "null";
	if (JSVAL_IS_VOID(val))		return "void";
#ifdef JS_USE_JSVAL_JSID_STRUCT_TYPES
	if (JSVAL_IS_MAGIC_IMPL(val))
	{
		switch(val.s.payload.why)
		{
			case JS_ARRAY_HOLE:			return "magic (array hole)";
			case JS_ARGS_HOLE:			return "magic (args hole)";
			case JS_NATIVE_ENUMERATE:	return "magic (native enumerate)";
			case JS_NO_ITER_VALUE:		return "magic (no iter value)";
			case JS_GENERATOR_CLOSING:	return "magic (generator closing)";
			case JS_NO_CONSTANT:		return "magic (no constant)";
			case JS_THIS_POISON:		return "magic (this poison)";
			case JS_ARG_POISON:			return "magic (arg poison)";
			case JS_SERIALIZE_NO_NODE:	return "magic (serialize no node)";
			case JS_GENERIC_MAGIC:		return "magic (generic)";
		};
		return "magic";
	}
#endif
	if (JSVAL_IS_OBJECT(val))  return OOJSGetClass(NULL, JSVAL_TO_OBJECT(val))->name;	// Fun fact: although a context is required if JS_THREADSAFE is defined, it isn't actually used.
	return "unknown";
}


// Doesn't follow pointers, mess with requests or otherwise poke the SpiderMonkey.
const char *JSValueToStrSafeDbg(jsval val)
{
	NSString *formatted = nil;
	
	if (JSVAL_IS_INT(val))			formatted = [NSString stringWithFormat:@"%i", JSVAL_TO_INT(val)];
	else if (JSVAL_IS_DOUBLE(val))	formatted = [NSString stringWithFormat:@"%g", JSVAL_TO_DOUBLE(val)];
	else if (JSVAL_IS_BOOLEAN(val))	formatted = (JSVAL_TO_BOOLEAN(val)) ? @"true" : @"false";
	else if (JSVAL_IS_STRING(val))
	{
		JSString		*string = JSVAL_TO_STRING(val);
		const jschar	*chars = NULL;
		size_t			length = JS_GetStringLength(string);
		
		if (JS_StringHasBeenInterned(string))
		{
			chars = JS_GetInternedStringChars(string);
		}
		// Flat strings can be extracted without a context, but cannot be detected.
		
		if (chars == NULL)  formatted = [NSString stringWithFormat:@"string [%zu chars]", length];
		else  formatted = [NSString stringWithCharacters:chars length:length];
	}
	else if (JSVAL_IS_VOID(val))	return "undefined";
	else							return JSValueTypeDbg(val);
	
	return [formatted UTF8String];
}


const char *JSObjectToStrSafeDbg(JSObject *obj)
{
	if (obj == NULL)  return "null";
	return JSValueToStrSafeDbg(OBJECT_TO_JSVAL(obj));
}


const char *JSStringToStrSafeDbg(JSString *str)
{
	if (str == NULL)  return "null";
	return JSValueToStrSafeDbg(STRING_TO_JSVAL(str));
}


const char *JSIDToStrSafeDbg(jsid anID)
{
	NSString *formatted = nil;
	
	if (JSID_IS_INT(anID))			formatted = [NSString stringWithFormat:@"%i", JSID_TO_INT(anID)];
	else if (JSID_IS_VOID(anID))	return "void";
	else if (JSID_IS_EMPTY(anID))	return "empty";
	else if (JSID_IS_ZERO(anID))	return "0";
	else if (JSID_IS_OBJECT(anID))	return OOJSGetClass(NULL, JSID_TO_OBJECT(anID))->name;
	else if (JSID_IS_DEFAULT_XML_NAMESPACE(anID))  return "default XML namespace";
	else if (JSID_IS_STRING(anID))
	{
		JSString		*string = JSID_TO_STRING(anID);
		const jschar	*chars = NULL;
		size_t			length = JS_GetStringLength(string);
		
		if (JS_StringHasBeenInterned(string))
		{
			chars = JS_GetInternedStringChars(string);
		}
		else
		{
			// Bug; jsid strings must be interned.
			return "*** uninterned string in jsid! ***";
		}
		formatted = [NSString stringWithCharacters:chars length:length];
	}
	else
	{
		formatted = [NSString stringWithFormat:@"unknown <0x%llX>", (long long)JSID_BITS(anID)];
	}
	
	return [formatted UTF8String];
}
#endif
