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
        OOConstToJSStringInit() (through InitTable()) adds an interned JSAtom for
        each C string. Atoms are interned once per process (they belong to the
        runtime, which survives engine resets) and are never freed. Two atoms are
        equal if and only if their strings are equal, so lookups from JS strings
        compare atoms.

        ConstTables are globals, which are accessed as local externs in the inlines
        in the header. All the advantages of globals with most of the advantages
        of encapsulation, sorta.

        -- Ahruman 2011-01-15
*/

typedef struct
{
    NSInteger value;
    const char* cString;
    JSAtom atom;
} TableEntry;

typedef struct ConstTable {
    NSUInteger count;
    TableEntry* entries;
} ConstTable;

#define TABLE(entries) { sizeof entries / sizeof *entries, entries }

static BOOL sInited = NO;
static BOOL sAtomsInterned = NO;

/*
        The interned string "UNDEFINED", returned by OOJSValueFromConstantPRIVATE()
        if passed a bogus constant value.
*/
static JSAtom sUndefinedAtom;

/*
        Initialize table contents (with C strings, see above) from table files.
*/
#define ENTRY(label, val) { .value = label, .cString = #label },
#define GALACTIC_HYPERSPACE_ENTRY(label, val) { .value = GALACTIC_HYPERSPACE_##label, .cString = #label },
#define DIFF_STRING_ENTRY(label, string) { .value = label, .cString = string },

static TableEntry sOOCompassModeTableEntries[] = {
#include "OOCompassMode.tbl"
};

static TableEntry sOOEntityStatusTableEntries[] = {
#include "OOEntityStatus.tbl"
};

static TableEntry sOOGalacticHyperspaceBehaviourTableEntries[] = {
#include "OOGalacticHyperspaceBehaviour.tbl"
};

static TableEntry sOOGUIScreenIDTableEntries[] = {
#include "OOGUIScreenID.tbl"
};

static TableEntry sOOScanClassTableEntries[] = {
#include "OOScanClass.tbl"
};

static TableEntry sOOViewIDTableEntries[] = {
#include "OOViewID.tbl"
};

static TableEntry sOOShipDamageTypeTableEntries[] = {
#include "OOShipDamageType.tbl"
};

static TableEntry sOOLegalStatusReasonTableEntries[] = {
#include "OOLegalStatusReason.tbl"
};

static TableEntry sOOLongRangeChartModeTableEntries[] = {
#include "OOLongRangeChartMode.tbl"
};

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY
#undef DIFF_STRING_ENTRY

ConstTable gOOCompassModeConstTable = TABLE(sOOCompassModeTableEntries);
ConstTable gOOEntityStatusConstTable = TABLE(sOOEntityStatusTableEntries);
ConstTable gOOGalacticHyperspaceBehaviourConstTable = TABLE(sOOGalacticHyperspaceBehaviourTableEntries);
ConstTable gOOGUIScreenIDConstTable = TABLE(sOOGUIScreenIDTableEntries);
ConstTable gOOScanClassConstTable = TABLE(sOOScanClassTableEntries);
ConstTable gOOViewIDConstTable = TABLE(sOOViewIDTableEntries);
ConstTable gOOShipDamageTypeConstTable = TABLE(sOOShipDamageTypeTableEntries);
ConstTable gOOLegalStatusReasonConstTable = TABLE(sOOLegalStatusReasonTableEntries);
ConstTable gOOLongRangeChartModeConstTable = TABLE(sOOLongRangeChartModeTableEntries);

static void InitTable(JSContext* context, ConstTable* table);

// MARK: Initialization

void OOConstToJSStringInit(JSContext* context)
{
    NSCAssert(!sInited, @"OOConstToJSStringInit() called while already inited.");
    NSCParameterAssert(context != NULL);

    // Atoms survive engine resets, so they only need interning once.
    if (!sAtomsInterned) {
        sUndefinedAtom = JS_NewAtom(context, "UNDEFINED");

        InitTable(context, &gOOEntityStatusConstTable);
        InitTable(context, &gOOCompassModeConstTable);
        InitTable(context, &gOOGalacticHyperspaceBehaviourConstTable);
        InitTable(context, &gOOGUIScreenIDConstTable);
        InitTable(context, &gOOScanClassConstTable);
        InitTable(context, &gOOViewIDConstTable);
        InitTable(context, &gOOShipDamageTypeConstTable);
        InitTable(context, &gOOLegalStatusReasonConstTable);
        InitTable(context, &gOOLongRangeChartModeConstTable);

        sAtomsInterned = YES;
    }

    sInited = YES;
}

void OOConstToJSStringDestroy(void)
{
    NSCAssert(sInited, @"OOConstToJSStringDestroy() called while not inited.");
    sInited = NO;
    // The atoms remain valid; they belong to the runtime.
}

static int CompareEntries(const void* a, const void* b)
{
    const TableEntry* entA = a;
    const TableEntry* entB = b;

    if (entA->value < entB->value)
        return -1;
    if (entA->value > entB->value)
        return 1;
    return 0;
}

static void InitTable(JSContext* context, ConstTable* table)
{
    NSCParameterAssert(context != NULL && table != NULL);

    NSUInteger i;
    for (i = 0; i < table->count; i++) {
        table->entries[i].atom = JS_NewAtom(context, table->entries[i].cString);
    }

    qsort(table->entries, table->count, sizeof *table->entries, CompareEntries);
}

// MARK: Lookup

JSValue OOJSValueFromConstantPRIVATE(JSContext* context, NSInteger value, struct ConstTable* table)
{
    NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
    NSCParameterAssert(context != NULL);
    NSCParameterAssert(table != NULL && table->count > 0);

    // Binary search. (Signed bounds: the SpiderMonkey version underflowed for values below the first entry.)
    NSInteger min = 0, max = (NSInteger)table->count - 1;
    NSInteger current;
    while (min <= max) {
        NSInteger mid = (min + max) / 2;
        current = table->entries[mid].value;
        if (current < value) {
            min = mid + 1;
        } else if (current > value) {
            max = mid - 1;
        } else {
            return JS_AtomToString(context, table->entries[mid].atom);
        }
    }

    return JS_AtomToString(context, sUndefinedAtom);
}

NSUInteger OOConstantFromJSValuePRIVATE(JSContext* context, JSValueConst value, struct ConstTable* table, NSInteger defaultValue)
{
    NSCAssert1(sInited, @"%s called before OOConstToJSStringInit().", __PRETTY_FUNCTION__);
    NSCParameterAssert(context != NULL && table != NULL);

    if (EXPECT_NOT(!JS_IsString(value)))
        return defaultValue;

    // Interning a string yields the same atom as the table entry with the same contents.
    JSAtom atom = JS_ValueToAtom(context, value);
    if (EXPECT_NOT(atom == JS_ATOM_NULL)) {
        JS_FreeValue(context, JS_GetException(context));
        return defaultValue;
    }

    NSInteger result = defaultValue;
    NSUInteger i, count = table->count;
    for (i = 0; i < count; i++) {
        if (table->entries[i].atom == atom) {
            result = table->entries[i].value;
            break;
        }
    }

    JS_FreeAtom(context, atom);
    return result;
}
