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
#define GALACTIC_HYPERSPACE_ENTRY(label, val) { .value = GALACTIC_HYPERSPACE_##label, .string = #label },

static TableEntry sOOCompassModeTableEntries[] =
{
	#include "OOCompassMode.tbl"
};

static TableEntry sOOEntityStatusTableEntries[] =
{
	#include "OOEntityStatus.tbl"
};

static TableEntry sOOGalacticHyperspaceBehaviourTableEntries[] =
{
	#include "OOGalacticHyperspaceBehaviour.tbl"
};

static TableEntry sOOGUIScreenIDTableEntries[] =
{
	#include "OOGUIScreenID.tbl"
};

static TableEntry sOOScanClassTableEntries[] =
{
	#include "OOScanClass.tbl"
};

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY


ConstTable gOOCompassModeConstTable = TABLE(sOOCompassModeTableEntries);
ConstTable gOOEntityStatusConstTable = TABLE(sOOEntityStatusTableEntries);
ConstTable gOOGalacticHyperspaceBehaviourConstTable = TABLE(sOOGalacticHyperspaceBehaviourTableEntries);
ConstTable gOOGUIScreenIDConstTable = TABLE(sOOGUIScreenIDTableEntries);
ConstTable gOOScanClassConstTable = TABLE(sOOScanClassTableEntries);

static void InitTable(JSContext *context, ConstTable *table);


// MARK: Initialization

void OOConstToJSStringInit(JSContext *context)
{
	NSCAssert(!sInited, @"OOConstToJSStringInit() called more than once.");
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	
	sUndefinedString = JS_InternString(context, "UNDEFINED");
	
	InitTable(context, &gOOEntityStatusConstTable);
	InitTable(context, &gOOCompassModeConstTable);
	InitTable(context, &gOOGalacticHyperspaceBehaviourConstTable);
	InitTable(context, &gOOGUIScreenIDConstTable);
	InitTable(context, &gOOScanClassConstTable);
	
#ifndef NDEBUG
	sInited = YES;
#endif
}


static int CompareEntries(const void *a, const void *b)
{
	const TableEntry *entA = a;
	const TableEntry *entB = b;
	return entA->value - entB->value;
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
	
	qsort(table->entries, table->count, sizeof *table->entries, CompareEntries);
}


// MARK: Lookup

JSString *OOJSStringFromConstantPRIVATE(JSContext *context, OOInteger value, struct ConstTable *table)
{
	NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	NSCParameterAssert(table != NULL && table->count > 0);
	
	// Binary search.
	OOUInteger min = 0, max = table->count - 1;
	OOInteger current;
	do
	{
		OOUInteger mid = (min + max) / 2;
		current = table->entries[mid].value;
		if (current < value)
		{
			min = mid + 1;
		}
		else if (current > value)
		{
			max = mid - 1;
		}
		else
		{
			return table->entries[mid].string;
		}
	}
	while (min <= max);
	
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
