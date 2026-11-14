/*

OOStringParsing+FoundationBridge.h

TRANSITIONAL (proposed ADR-0043, "Transitional bridges"; bead oo-1886, made by chunk oo-3rb.124 and
extended by its later chunks). OOStringParsing's Foundation-typed functions as they were before
its sweep, with the same names and types, forwarding to the cxx_ functions in OOStringParsing.h
(ScanTokensFromString has no twin: oo::str::tokens replaces it), and the NSString (OOUtilities)
category, which retires with it (its one caller, OOShaderMaterial.mm, moves to
oo::str::pathHasExtensionIn in its own sweep bead). It exists so that OOStringParsing's callers
compile unchanged; each caller moves to the cxx_ API in its own sweep bead. When `git grep` finds
no caller of anything declared here, the bridge bead deletes this file,
OOStringParsing+FoundationBridge.mm, its line in Core/meson.build and the #import at the end of
OOStringParsing.h. Never add to it outside the oo-1886 chunks; never call it from migrated code.
oo-qps (the removal of gnustep-base) cannot compile while it exists.

Registry: src/oofnd/README.md, "Transitional bridges".

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors (OOStringParsing.h)

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

// Imported only from the end of OOStringParsing.h (which declares everything used here); never
// import it directly, and never import OOStringParsing.h from it (a cycle).
#ifndef OOSTRINGPARSING_FOUNDATIONBRIDGE_H
#define OOSTRINGPARSING_FOUNDATIONBRIDGE_H

// oo-3rb.124: scanners, points, random seeds
#ifdef __cplusplus
extern "C" {
#endif

NSMutableArray* ScanTokensFromString(NSString* values); // no twin: oo::str::tokens

// Note: these functions will leave their out values untouched if they fail (and return NO). They will not log an error if passed a NULL string (but will return NO). This means they can be used to, say, read dictionary entries which might not exist. They also ignore any extra components in the string.
BOOL ScanVectorFromString(NSString* xyzString, Vector* outVector); // -> cxx_ScanVectorFromString
BOOL ScanHPVectorFromString(NSString* xyzString, HPVector* outVector); // -> cxx_ScanHPVectorFromString
BOOL ScanQuaternionFromString(NSString* wxyzString, Quaternion* outQuaternion); // -> cxx_ScanQuaternionFromString
BOOL ScanVectorAndQuaternionFromString(NSString* xyzwxyzString, Vector* outVector, Quaternion* outQuaternion); // -> cxx_ScanVectorAndQuaternionFromString

Vector VectorFromString(NSString* xyzString, Vector defaultValue); // -> cxx_VectorFromString
Quaternion QuaternionFromString(NSString* wxyzString, Quaternion defaultValue); // -> cxx_QuaternionFromString

NSString* StringFromPoint(NSPoint point); // -> cxx_StringFromPoint
NSPoint PointFromString(NSString* xyString); // -> cxx_PointFromString

Random_Seed RandomSeedFromString(NSString* abcdefString); // -> cxx_RandomSeedFromString
NSString* StringFromRandomSeed(Random_Seed seed); // -> cxx_StringFromRandomSeed

#ifdef __cplusplus
}
#endif

// oo-3rb.124: the NSString (OOUtilities) category, retired (oo::str::pathHasExtension /
// pathHasExtensionIn replace it)
@interface NSString (OOUtilities)

// Case-insensitive match of [self pathExtension]
- (BOOL)pathHasExtension:(NSString*)extension;
- (BOOL)pathHasExtensionInArray:(NSArray*)extensions;

@end

// oo-3rb.125: credits, em padding, versions, clock
// (-> cxx_OOStringFromDeciCredits, cxx_OOStringFromIntCredits, cxx_OOCredits, cxx_OOIntCredits,
// cxx_OOPadStringToEms, cxx_ComponentsFromVersionString, cxx_CompareVersions, cxx_ClockToString)
#ifdef __cplusplus
extern "C" {
#endif

NSString* OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits, BOOL includeDecimal, BOOL includeSymbol);

#ifdef __cplusplus
}
#endif

OOINLINE NSString* OOStringFromIntCredits(OOCreditsQuantity integerCredits, BOOL includeSymbol)
{
    return OOStringFromDeciCredits(integerCredits * 10, NO, includeSymbol);
}

OOINLINE NSString* OOCredits(OOCreditsQuantity tenthsOfCredits)
{
    return OOStringFromDeciCredits(tenthsOfCredits, YES, YES);
}
OOINLINE NSString* OOIntCredits(OOCreditsQuantity integerCredits)
{
    return OOStringFromIntCredits(integerCredits, YES);
}

#ifdef __cplusplus
extern "C" {
#endif

NSString* OOPadStringToEms(NSString* string, float numEms);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Given a string of the form 1.2.3.4 (with arbitrarily many components), return an array of unsigned ints.
NSArray* ComponentsFromVersionString(NSString* string);

/*	Compare two arrays of unsigned int NSNumbers, as returned by
        ComponentsFromVersionString().

        Components are ordered from most to least significant, and a missing
        component is treated as 0. Thus "1.7" < "1.60", and "1.2.3.0" == "1.2.3".
*/
NSComparisonResult CompareVersions(NSArray* version1, NSArray* version2);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
extern "C" {
#endif

NSString* ClockToString(double clock, BOOL adjusting);

#ifdef __cplusplus
}
#endif

// oo-3rb.126: GraphViz helpers (-> cxx_EscapedGraphVizString, cxx_GraphVizTokenString)
#if DEBUG_GRAPHVIZ

#ifdef __cplusplus
extern "C" {
#endif

NSString* EscapedGraphVizString(NSString* string);

/*	GraphVizTokenString()
        Generate a C-style identifier. Sequences of invalid characters and
        underscores are replaced with single underscores. If uniqueSet is not nil,
        uniqueness is achieved by appending numbers if necessary.

        This can be used for any C-based langauge, but note that it excludes the
        case-insensitive GraphViz keywords node, edge, graph, digraph, subgraph
        and strict.
*/
NSString* GraphVizTokenString(NSString* string, NSMutableSet* uniqueSet);

#ifdef __cplusplus
}
#endif

#endif

#endif // OOSTRINGPARSING_FOUNDATIONBRIDGE_H
