/*

OOConstToJSString.m


Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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

#include "OOConstToJSString.h"


/*
	Each type of constant has its own lookup table, which is a linear list of
	TableEntry structs plus a count.
	
	The list is statically initialized with the constant values and C strings.
	OOConstToJSStringInit() (through InitTable()) replaces the C strings with
	interned JSStrings (hence the void * type). These are subsequently
	constant and no other strings with the same value should occur, i.e. they
	should be comparable with pointer equality. Because I'm paranoid, we fall
	back to full string comparison if this fails.
	
	Lookups are currently linear. Requiring the .tbl files to be in sort order
	and binary searching for const-to-string comparison would be more efficient
	for the much more common case, but with tables this small I'm not sure
	bsearch() would be a win and I can't be bothered to write and test it
	properly right now.
	
	ConstTables are globals, which are accessed as local externs in the inlines
	in the header. All the advantages of globals with most of the advantages
	of encapsulation, sorta.
	
	-- Ahruman 2011-01-15
*/

typedef struct
{
	OOInteger			value;
	void				*string;
} TableEntry;

typedef struct ConstTable
{
	OOUInteger			count;
	TableEntry			*entries;
} ConstTable;

#define TABLE(entries) { sizeof entries / sizeof *entries, entries }


#ifndef NDEBUG
static BOOL sInited = NO;
#endif

/*
	The interned string "UNDEFINED", returned by OOJSStringFromConstantPRIVATE()
	if passed a bogus constant value.
*/
static JSString *sUndefinedString;


/*	
	Initialize table contents (with C strings, see above) from table files.
*/
#define ENTRY(label, val) { .value = label, .string = #label },

static TableEntry sOOEntityStatusTableEntries[] =
{
	#include "OOEntityStatus.tbl"
};

static TableEntry sOOScanClassTableEntries[] =
{
	#include "OOScanClass.tbl"
};

#undef ENTRY


ConstTable gOOEntityStatusConstTable = TABLE(sOOEntityStatusTableEntries);
ConstTable gOOScanClassConstTable = TABLE(sOOScanClassTableEntries);

static void InitTable(JSContext *context, ConstTable *table);


// MARK: Initialization

void OOConstToJSStringInit(JSContext *context)
{
	NSCAssert(!sInited, @"OOConstToJSStringInit() called more than once.");
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	
	sUndefinedString = JS_InternString(context, "UNDEFINED");
	
	InitTable(context, &gOOEntityStatusConstTable);
	InitTable(context, &gOOScanClassConstTable);
	
#ifndef NDEBUG
	sInited = YES;
#endif
}


static void InitTable(JSContext *context, ConstTable *table)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context) && table != NULL);
	
	OOUInteger i;
	for(i = 0; i < table->count; i++)
	{
		const char *cString = table->entries[i].string;
		JSString *jsString = JS_InternString(context, cString);
		
		table->entries[i].string = jsString;
	}
}


// MARK: Lookup

JSString *OOJSStringFromConstantPRIVATE(JSContext *context, OOInteger value, struct ConstTable *table)
{
	NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
	NSCParameterAssert(context != NULL && JS_IsInRequest(context) && table != NULL);
	
	OOUInteger i, count = table->count;
	for(i = 0; i < count; i++)
	{
		if (table->entries[i].value == value)
		{
			return table->entries[i].string;
		}
	}
	
	return sUndefinedString;
}


OOUInteger OOConstantFromJSStringPRIVATE(JSContext *context, JSString *string, struct ConstTable *table, OOInteger defaultValue)
{
	NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
	NSCParameterAssert(context != NULL && JS_IsInRequest(context) && table != NULL);
	
	// Quick pass: look for pointer-equal string.
	OOUInteger i, count = table->count;
	for(i = 0; i < count; i++)
	{
		if (table->entries[i].string == string)
		{
			return table->entries[i].value;
		}
	}
	
	
	// Slow pass: use string comparison. This is expected to fail.
	if (string != NULL)
	{
		for(i = 0; i < count; i++)
		{
			int32 result;
			if (OOJSCompareStrings(context, string, table->entries[i].string, &result) && result == 0)
			{
				return table->entries[i].value;
			}
		}
	}
	
	// Fail.
	return defaultValue;
}


OOUInteger OOConstantFromJSValuePRIVATE(JSContext *context, jsval value, struct ConstTable *table, OOInteger defaultValue)
{
	if (EXPECT(JSVAL_IS_STRING(value)))
	{
		return OOConstantFromJSStringPRIVATE(context, JSVAL_TO_STRING(value), table, defaultValue);
	}
	else
	{
		return defaultValue;
	}

}
