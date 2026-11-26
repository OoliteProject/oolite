/*

OOPListGameTypes.h

The game types OOCollectionExtractors read from and wrote to property-list
objects - Vector, HPVector, Quaternion and the fuzzy boolean - over oo::PList
instead.
The routing and conversions are oofnd's (oo::plist_get::tupleFrom / tuplePList /
fuzzyProbabilityFrom, pinned by tests/unit/oofnd/test_plist_game_tuples.cpp);
this header adds the game's parts: a string is scanned by cxx_Scan*FromString
(which logs a malformed one), a native JS vector object is read, and the fuzzy
boolean draws randf(). OOCollectionExtractors' OO*FromObject forward here.

value == nullptr (or a null PList) is nil. PListGet<Vector> / <HPVector> /
<Quaternion> let a dictionary or array answer get<Vector>(key, fallback) /
at<Vector>(i, fallback) directly; their no-fallback forms default to kZeroVector
/ kZeroHPVector / kIdentityQuaternion, as oo::PListView(dict).get<Vector>(key)
did.

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
#include "oofnd/PListGet.hpp"

Vector OOVectorFromPList(const oo::PList* value,
                         Vector defaultValue);  // OOVectorFromObject
HPVector OOHPVectorFromPList(const oo::PList* value,
                             HPVector defaultValue);  // OOHPVectorFromObject
Quaternion OOQuaternionFromPList(
    const oo::PList* value, Quaternion defaultValue);  // OOQuaternionFromObject

oo::PList OOPListFromVector(
    Vector value);  // OOPropertyListFromVector: {x y z} single-precision reals
oo::PList OOPListFromHPVector(
    HPVector value);  // OOPropertyListFromHPVector: {x y z} doubles
oo::PList OOPListFromQuaternion(
    Quaternion value);  // OOPropertyListFromQuaternion: {w x y z}
                        // single-precision reals

bool OOFuzzyBooleanFromPList(
    const oo::PList* value,
    float defaultValue);  // OOFuzzyBooleanFromObject (draws randf())

namespace oo {

template <>
struct PListGet<Vector> {
  using Result = Vector;
  using Fallback = Vector;
  static Vector defaultFallback() { return kZeroVector; }
  static Vector from(const PList* v, Vector fallback) {
    return OOVectorFromPList(v, fallback);
  }
};

template <>
struct PListGet<HPVector> {
  using Result = HPVector;
  using Fallback = HPVector;
  static HPVector defaultFallback() { return kZeroHPVector; }
  static HPVector from(const PList* v, HPVector fallback) {
    return OOHPVectorFromPList(v, fallback);
  }
};

template <>
struct PListGet<Quaternion> {
  using Result = Quaternion;
  using Fallback = Quaternion;
  static Quaternion defaultFallback() { return kIdentityQuaternion; }
  static Quaternion from(const PList* v, Quaternion fallback) {
    return OOQuaternionFromPList(v, fallback);
  }
};

}  // namespace oo
