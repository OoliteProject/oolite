/*

OOConstToJSString.m


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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
	NSInteger			value;
	const char			*cString;
	JSString			*jsString;
} TableEntry;

typedef struct ConstTable
{
	NSUInteger			count;
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
#define ENTRY(label, val) { .value = label, .cString = #label },
#define GALACTIC_HYPERSPACE_ENTRY(label, val) { .value = GALACTIC_HYPERSPACE_##label, .cString = #label },
#define DIFF_STRING_ENTRY(label, string) { .value = label, .cString = string },

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

static TableEntry sOOViewIDTableEntries[] =
{
	#include "OOViewID.tbl"
};

static TableEntry sOOShipDamageTypeTableEntries[] =
{
	#include "OOShipDamageType.tbl"
};

static TableEntry sOOLegalStatusReasonTableEntries[] =
{
	#include "OOLegalStatusReason.tbl"
};


#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY
#undef DIFF_STRING_ENTRY


ConstTable gOOCompassModeConstTable					= TABLE(sOOCompassModeTableEntries);
ConstTable gOOEntityStatusConstTable				= TABLE(sOOEntityStatusTableEntries);
ConstTable gOOGalacticHyperspaceBehaviourConstTable	= TABLE(sOOGalacticHyperspaceBehaviourTableEntries);
ConstTable gOOGUIScreenIDConstTable					= TABLE(sOOGUIScreenIDTableEntries);
ConstTable gOOScanClassConstTable					= TABLE(sOOScanClassTableEntries);
ConstTable gOOViewIDConstTable						= TABLE(sOOViewIDTableEntries);
ConstTable gOOShipDamageTypeConstTable				= TABLE(sOOShipDamageTypeTableEntries);
ConstTable gOOLegalStatusReasonConstTable				= TABLE(sOOLegalStatusReasonTableEntries);

static void InitTable(JSContext *context, ConstTable *table);


// MARK: Initialization

void OOConstToJSStringInit(JSContext *context)
{
	NSCAssert(!sInited, @"OOConstToJSStringInit() called while already inited.");
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	
	sUndefinedString = JS_InternString(context, "UNDEFINED");
	
	InitTable(context, &gOOEntityStatusConstTable);
	InitTable(context, &gOOCompassModeConstTable);
	InitTable(context, &gOOGalacticHyperspaceBehaviourConstTable);
	InitTable(context, &gOOGUIScreenIDConstTable);
	InitTable(context, &gOOScanClassConstTable);
	InitTable(context, &gOOViewIDConstTable);
	InitTable(context, &gOOShipDamageTypeConstTable);
	InitTable(context, &gOOLegalStatusReasonConstTable);
	
#ifndef NDEBUG
	sInited = YES;
#endif
}


void OOConstToJSStringDestroy(void)
{
#ifndef NDEBUG
	NSCAssert(sInited, @"OOConstToJSStringDestroy() called while not inited.");
	sInited = NO;
#endif
	// jsString pointers are now officially junk.
}


static int CompareEntries(const void *a, const void *b)
{
	const TableEntry *entA = a;
	const TableEntry *entB = b;
	
	if (entA->value < entB->value)  return -1;
	if (entA->value > entB->value)  return 1;
	return 0;
}


static void InitTable(JSContext *context, ConstTable *table)
{
	NSCParameterAssert(context != NULL && JS_IsInRequest(context) && table != NULL);
	
	NSUInteger i;
	for(i = 0; i < table->count; i++)
	{
		table->entries[i].jsString = JS_InternString(context, table->entries[i].cString);
	}
	
	qsort(table->entries, table->count, sizeof *table->entries, CompareEntries);
}


// MARK: Lookup

JSString *OOJSStringFromConstantPRIVATE(JSContext *context, NSInteger value, struct ConstTable *table)
{
	NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
	NSCParameterAssert(context != NULL && JS_IsInRequest(context));
	NSCParameterAssert(table != NULL && table->count > 0);
	
	// Binary search.
	NSUInteger min = 0, max = table->count - 1;
	NSInteger current;
	do
	{
		NSUInteger mid = (min + max) / 2;
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
			return table->entries[mid].jsString;
		}
	}
	while (min <= max);
	
	return sUndefinedString;
}


NSUInteger OOConstantFromJSStringPRIVATE(JSContext *context, JSString *string, struct ConstTable *table, NSInteger defaultValue)
{
	NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
	NSCParameterAssert(context != NULL && JS_IsInRequest(context) && table != NULL);
	
	// Quick pass: look for pointer-equal string.
	NSUInteger i, count = table->count;
	for(i = 0; i < count; i++)
	{
		if (table->entries[i].jsString == string)
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
			if (JS_CompareStrings(context, string, table->entries[i].jsString, &result) && result == 0)
			{
				return table->entries[i].value;
			}
		}
	}
	
	// Fail.
	return defaultValue;
}


NSUInteger OOConstantFromJSValuePRIVATE(JSContext *context, jsval value, struct ConstTable *table, NSInteger defaultValue)
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
