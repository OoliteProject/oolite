/*

OOPListParsing+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-crpp, made by chunk oo-3rb.132).
OOPListParsing's Foundation-typed functions as they were before its sweep, with the same names
and types, forwarding to the cxx_ functions in OOPListParsing.h (the typed wrappers keep their
class test here: they have no twins). It exists so that OOPListParsing's callers compile
unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds no
caller of anything declared here, the bridge bead deletes this file,
OOPListParsing+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOPListParsing.h. Never add to it; never call it from migrated code. oo-qps (the removal of
gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors (OOPListParsing.h)

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

// Imported only from the end of OOPListParsing.h (which declares everything used here); never
// import it directly, and never import OOPListParsing.h from it (a cycle).
#ifndef OOPLISTPARSING_FOUNDATIONBRIDGE_H
#define OOPLISTPARSING_FOUNDATIONBRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// whereFrom is an optional description of the data source, for error reporting.
id OOPropertyListFromData(NSData* data, NSString* whereFrom); // -> cxx_OOPropertyListFromData
id OOPropertyListFromFile(NSString* path); // -> cxx_OOPropertyListFromFile

// Wrappers which ensure that the plist contains the right type of object.
NSDictionary* OODictionaryFromData(NSData* data, NSString* whereFrom);
NSDictionary* OODictionaryFromFile(NSString* path);

NSArray* OOArrayFromData(NSData* data, NSString* whereFrom);
NSArray* OOArrayFromFile(NSString* path);

#ifdef __cplusplus
}
#endif

#endif // OOPLISTPARSING_FOUNDATIONBRIDGE_H
