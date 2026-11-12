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

#define OO_PLAIN_CPP_UNIT \
  1  // a plain C++ unit: the shared headers' game-unit parts stay out of it
#include "OOConstToJSString.h"

#include <array>
#include <string_view>

#include "oofnd/objc/OOAssert.h"

/*
        Each type of constant has its own lookup table, which is a linear list
   of TableEntry structs plus a count.

        The list is statically initialized with the constant values and C
   strings. OOConstToJSStringInit() (through InitTable()) adds an interned
   JSAtom for each C string. Atoms are interned once per process (they belong to
   the runtime, which survives engine resets) and are never freed. Two atoms are
        equal if and only if their strings are equal, so lookups from JS strings
        compare atoms.

        ConstTables are globals, which are accessed as local externs in the
   inlines in the header. All the advantages of globals with most of the
   advantages of encapsulation, sorta.

        -- Ahruman 2011-01-15
*/

using TableEntry = struct {
  std::ptrdiff_t value;
  const char* cString;
  JSAtom atom;
};

using ConstTable = struct ConstTable {
  std::size_t count;
  TableEntry* entries;
};

#define TABLE(entries) {sizeof(entries) / sizeof *(entries), entries}

// A table's rows as entries: the names are literals, so NUL-terminated.
constexpr const char* NameCString(std::string_view literal) {
  return literal.data();
}

template <class E, std::size_t N>
constexpr std::array<TableEntry, N> EntriesFrom(
    const oo::EnumTable<E, N>& table) {
  std::array<TableEntry, N> entries{};
  for (std::size_t i = 0; i < N; ++i) {
    entries[i] = {.value = oo::ToUnderlying(table.entries[i].first),
                  .cString = NameCString(table.entries[i].second),
                  .atom = JS_ATOM_NULL};
  }
  return entries;
}

// Unconditional, as upstream's: OOCAssert reads it in every flavour.
static bool sInited = false;
static bool sAtomsInterned = false;

/*
        The interned string "UNDEFINED", returned by
   OOJSValueFromConstantPRIVATE() if passed a bogus constant value.
*/
static JSAtom sUndefinedAtom;

/*
        Initialize table contents (with C strings, see above) from table files.
*/
#define ENTRY(label, val) \
  {.value = (label), .cString = #label, .atom = JS_ATOM_NULL},
#define GALACTIC_HYPERSPACE_ENTRY(label, val) \
  {.value = GALACTIC_HYPERSPACE_##label,      \
   .cString = #label,                         \
   .atom = JS_ATOM_NULL},
#define DIFF_STRING_ENTRY(label, string) \
  {.value = (label), .cString = (string), .atom = JS_ATOM_NULL},

static TableEntry sOOCompassModeTableEntries[] = {
#include "OOCompassMode.tbl"
};

static std::array<TableEntry, kOOEntityStatusTable.entries.size()>
    sOOEntityStatusTableEntries = EntriesFrom(kOOEntityStatusTable);

static std::array<TableEntry,
                  kOOGalacticHyperspaceBehaviourTable.entries.size()>
    sOOGalacticHyperspaceBehaviourTableEntries =
        EntriesFrom(kOOGalacticHyperspaceBehaviourTable);

static TableEntry sOOGUIScreenIDTableEntries[] = {
#include "OOGUIScreenID.tbl"
};

static std::array<TableEntry, kOOScanClassTable.entries.size()>
    sOOScanClassTableEntries = EntriesFrom(kOOScanClassTable);

static TableEntry sOOViewIDTableEntries[] = {
#include "OOViewID.tbl"
};

static std::array<TableEntry, kOOShipDamageTypeTable.entries.size()>
    sOOShipDamageTypeTableEntries = EntriesFrom(kOOShipDamageTypeTable);

static std::array<TableEntry, kOOLegalStatusReasonTable.entries.size()>
    sOOLegalStatusReasonTableEntries = EntriesFrom(kOOLegalStatusReasonTable);

static TableEntry sOOLongRangeChartModeTableEntries[] = {
#include "OOLongRangeChartMode.tbl"
};

#undef ENTRY
#undef GALACTIC_HYPERSPACE_ENTRY
#undef DIFF_STRING_ENTRY

ConstTable gOOCompassModeConstTable = TABLE(sOOCompassModeTableEntries);
ConstTable gOOEntityStatusConstTable = {sOOEntityStatusTableEntries.size(),
                                        sOOEntityStatusTableEntries.data()};
ConstTable gOOGalacticHyperspaceBehaviourConstTable = {
    sOOGalacticHyperspaceBehaviourTableEntries.size(),
    sOOGalacticHyperspaceBehaviourTableEntries.data()};
ConstTable gOOGUIScreenIDConstTable = TABLE(sOOGUIScreenIDTableEntries);
ConstTable gOOScanClassConstTable = {sOOScanClassTableEntries.size(),
                                     sOOScanClassTableEntries.data()};
ConstTable gOOViewIDConstTable = TABLE(sOOViewIDTableEntries);
ConstTable gOOShipDamageTypeConstTable = {sOOShipDamageTypeTableEntries.size(),
                                          sOOShipDamageTypeTableEntries.data()};
ConstTable gOOLegalStatusReasonConstTable = {
    sOOLegalStatusReasonTableEntries.size(),
    sOOLegalStatusReasonTableEntries.data()};
ConstTable gOOLongRangeChartModeConstTable =
    TABLE(sOOLongRangeChartModeTableEntries);

static void InitTable(JSContext* context, ConstTable* table);

// MARK: Initialization

void OOConstToJSStringInit(JSContext* context) {
  OOCAssert(!sInited, "OOConstToJSStringInit() called while already inited.");
  OOCParameterAssert(context != nullptr);

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

    sAtomsInterned = true;
  }

  sInited = true;
}

void OOConstToJSStringDestroy() {
  OOCAssert(sInited, "OOConstToJSStringDestroy() called while not inited.");
  sInited = false;
  // The atoms remain valid; they belong to the runtime.
}

static int CompareEntries(const void* a, const void* b) {
  const TableEntry* entA = (const TableEntry*)a;
  const TableEntry* entB = (const TableEntry*)b;

  if (entA->value < entB->value) return -1;
  if (entA->value > entB->value) return 1;
  return 0;
}

static void InitTable(JSContext* context, ConstTable* table) {
  OOCParameterAssert(context != nullptr && table != nullptr);

  std::size_t i;
  for (i = 0; i < table->count; i++) {
    table->entries[i].atom = JS_NewAtom(context, table->entries[i].cString);
  }

  qsort(table->entries, table->count, sizeof *table->entries, CompareEntries);
}

// MARK: Lookup

JSValue OOJSValueFromConstantPRIVATE(JSContext* context, std::ptrdiff_t value,
                                     struct ConstTable* table) {
  OOCAssert(sInited, "%s called before OOConstToJSStringInit().",
            __PRETTY_FUNCTION__);
  OOCParameterAssert(context != nullptr);
  OOCParameterAssert(table != nullptr && table->count > 0);

  // Binary search. (Signed bounds: the SpiderMonkey version underflowed for
  // values below the first entry.)
  std::ptrdiff_t min = 0, max = (std::ptrdiff_t)table->count - 1;
  std::ptrdiff_t current;
  while (min <= max) {
    std::ptrdiff_t mid = (min + max) / 2;
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

std::size_t OOConstantFromJSValuePRIVATE(JSContext* context, JSValueConst value,
                                         struct ConstTable* table,
                                         std::ptrdiff_t defaultValue) {
  OOCAssert(sInited, "%s called before OOConstToJSStringInit().",
            __PRETTY_FUNCTION__);
  OOCParameterAssert(context != nullptr && table != nullptr);

  if (EXPECT_NOT(!JS_IsString(value))) return defaultValue;

  // Interning a string yields the same atom as the table entry with the same
  // contents.
  JSAtom atom = JS_ValueToAtom(context, value);
  if (EXPECT_NOT(atom == JS_ATOM_NULL)) {
    JS_FreeValue(context, JS_GetException(context));
    return defaultValue;
  }

  std::ptrdiff_t result = defaultValue;
  std::size_t i, count = table->count;
  for (i = 0; i < count; i++) {
    if (table->entries[i].atom == atom) {
      result = table->entries[i].value;
      break;
    }
  }

  JS_FreeAtom(context, atom);
  return result;
}
