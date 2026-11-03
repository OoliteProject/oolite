/*

OOStringParsing.h

Various functions for interpreting values from strings.

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

#pragma once

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "legacy_random.h"

#include "oofnd/StdLib.hpp"

// Tokens of a string: oo::str::tokens (oofnd/String.hpp).

// Note: these functions will leave their out values untouched if they fail (and return NO). They will not log an error if passed a null string (nullopt; but will return NO). This means they can be used to, say, read dictionary entries which might not exist. They also ignore any extra components in the string.
BOOL cxx_ScanVectorFromString(const std::optional<std::string>& xyzString, Vector* outVector);
BOOL cxx_ScanHPVectorFromString(const std::optional<std::string>& xyzString, HPVector* outVector);
BOOL cxx_ScanQuaternionFromString(const std::optional<std::string>& wxyzString, Quaternion* outQuaternion);
BOOL cxx_ScanVectorAndQuaternionFromString(const std::optional<std::string>& xyzwxyzString, Vector* outVector, Quaternion* outQuaternion);

Vector cxx_VectorFromString(const std::optional<std::string>& xyzString, Vector defaultValue);
Quaternion cxx_QuaternionFromString(const std::optional<std::string>& wxyzString, Quaternion defaultValue);

std::string cxx_StringFromPoint(NSPoint point);
NSPoint cxx_PointFromString(const std::string& xyString);

// nullopt is read as nil was (a conversion error, logged, and kNilRandomSeed).
Random_Seed cxx_RandomSeedFromString(const std::optional<std::string>& abcdefString);
std::string cxx_StringFromRandomSeed(Random_Seed seed);

std::string cxx_OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits, BOOL includeDecimal, BOOL includeSymbol);

OOINLINE std::string cxx_OOStringFromIntCredits(OOCreditsQuantity integerCredits, BOOL includeSymbol)
{
    return cxx_OOStringFromDeciCredits(integerCredits * 10, NO, includeSymbol);
}

OOINLINE std::string cxx_OOCredits(OOCreditsQuantity tenthsOfCredits)
{
    return cxx_OOStringFromDeciCredits(tenthsOfCredits, YES, YES);
}
OOINLINE std::string cxx_OOIntCredits(OOCreditsQuantity integerCredits)
{
    return cxx_OOStringFromIntCredits(integerCredits, YES);
}

std::string cxx_OOPadStringToEms(const std::string& string, float numEms);

// Given a string of the form 1.2.3.4 (with arbitrarily many components), return a list of unsigned ints.
std::vector<unsigned> cxx_ComponentsFromVersionString(const std::string& string);

/*	Compare two lists of unsigned ints, as returned by
        cxx_ComponentsFromVersionString().

        Components are ordered from most to least significant, and a missing
        component is treated as 0. Thus "1.7" < "1.60", and "1.2.3.0" == "1.2.3".
*/
OOComparisonResult cxx_CompareVersions(const std::vector<unsigned>& version1, const std::vector<unsigned>& version2);

std::string cxx_ClockToString(double clock, BOOL adjusting);

#if DEBUG_GRAPHVIZ

std::string cxx_EscapedGraphVizString(const std::string& string);

/*	cxx_GraphVizTokenString()
        Generate a C-style identifier. Sequences of invalid characters and
        underscores are replaced with single underscores. If uniqueSet is not nullptr,
        uniqueness is achieved by appending numbers if necessary, and the result is
        added to it.

        This can be used for any C-based langauge, but note that it excludes the
        case-insensitive GraphViz keywords node, edge, graph, digraph, subgraph
        and strict.
*/
std::string cxx_GraphVizTokenString(const std::string& string, std::set<std::string>* uniqueSet);

#endif
