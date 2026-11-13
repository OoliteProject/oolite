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

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOFoundation.h"
#include "OOMaths.h"
#include "OOTypes.h"
#include "legacy_random.h"

// Tokens of a string: oo::str::tokens (oofnd/String.hpp).

// Note: these functions will leave their out values untouched if they fail (and
// return NO). They will not log an error if passed a null string (nullopt; but
// will return NO). This means they can be used to, say, read dictionary entries
// which might not exist. They also ignore any extra components in the string.
bool ScanVectorFromString(const std::optional<std::string>& xyzString,
                          Vector* outVector);
bool ScanHPVectorFromString(const std::optional<std::string>& xyzString,
                            HPVector* outVector);
bool ScanQuaternionFromString(const std::optional<std::string>& wxyzString,
                              Quaternion* outQuaternion);
bool ScanVectorAndQuaternionFromString(
    const std::optional<std::string>& xyzwxyzString, Vector* outVector,
    Quaternion* outQuaternion);

Vector VectorFromString(const std::optional<std::string>& xyzString,
                        Vector defaultValue);
Quaternion QuaternionFromString(const std::optional<std::string>& wxyzString,
                                Quaternion defaultValue);

std::string StringFromPoint(NSPoint point);
NSPoint PointFromString(const std::string& xyString);

// nullopt is read as nil was (a conversion error, logged, and kNilRandomSeed).
Random_Seed RandomSeedFromString(
    const std::optional<std::string>& abcdefString);
std::string StringFromRandomSeed(Random_Seed seed);

std::string OOStringFromDeciCredits(OOCreditsQuantity tenthsOfCredits,
                                    bool includeDecimal, bool includeSymbol);

OOINLINE std::string OOStringFromIntCredits(OOCreditsQuantity integerCredits,
                                            bool includeSymbol) {
  return OOStringFromDeciCredits(integerCredits * 10, false, includeSymbol);
}

OOINLINE std::string OOCredits(OOCreditsQuantity tenthsOfCredits) {
  return OOStringFromDeciCredits(tenthsOfCredits, true, true);
}
OOINLINE std::string OOIntCredits(OOCreditsQuantity integerCredits) {
  return OOStringFromIntCredits(integerCredits, true);
}

std::string OOPadStringToEms(const std::string& string, float numEms);

// Given a string of the form 1.2.3.4 (with arbitrarily many components), return
// a list of unsigned ints.
std::vector<unsigned> ComponentsFromVersionString(const std::string& string);

/*	Compare two lists of unsigned ints, as returned by
        ComponentsFromVersionString().

        Components are ordered from most to least significant, and a missing
        component is treated as 0. Thus "1.7" < "1.60", and "1.2.3.0" ==
   "1.2.3".
*/
OOComparisonResult CompareVersions(const std::vector<unsigned>& version1,
                                   const std::vector<unsigned>& version2);

std::string ClockToString(double clock, bool adjusting);

#if DEBUG_GRAPHVIZ

std::string EscapedGraphVizString(const std::string& string);

/*	GraphVizTokenString()
        Generate a C-style identifier. Sequences of invalid characters and
        underscores are replaced with single underscores. If uniqueSet is not
   nullptr, uniqueness is achieved by appending numbers if necessary, and the
   result is added to it.

        This can be used for any C-based langauge, but note that it excludes the
        case-insensitive GraphViz keywords node, edge, graph, digraph, subgraph
        and strict.
*/
std::string GraphVizTokenString(const std::string& string,
                                std::set<std::string>* uniqueSet);

#endif
