/*

OOPListGameTypes.mm

See OOPListGameTypes.h (bead oo-9ftb).

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

#include "OOPListGameTypes.h"
#include "OOObjCPList.h"
#include "OOStringParsing.h"
#include "OOVector.h"
#include "legacy_random.h"

namespace {

constexpr std::array<std::string_view, 3> kXYZ { "x", "y", "z" };
constexpr std::array<std::string_view, 4> kWXYZ { "w", "x", "y", "z" };

} // namespace

Vector OOVectorFromPList(const oo::PList* value, Vector defaultValue)
{
    Vector result = defaultValue;
    std::array<float, 3> components { };

    switch (oo::plist_get::tupleFrom(value, kXYZ, components)) {
    case oo::plist_get::TupleSource::components:
        result.x = components[0];
        result.y = components[1];
        result.z = components[2];
        break;

    case oo::plist_get::TupleSource::string:
        // Writes result only if a valid vector is found, and logs an error otherwise.
        cxx_ScanVectorFromString(*value->getIf<std::string>(), &result);
        break;

    case oo::plist_get::TupleSource::object: {
        const oo::PList::Object* node = value->getIf<oo::PList::Object>();
        if (OONativeVector* box = (node != nullptr) ? dynamic_cast<OONativeVector*>(node->get()) : nullptr)
            result = box->getVector();
        break;
    }

    case oo::plist_get::TupleSource::none:
        break;
    }

    return result;
}

HPVector OOHPVectorFromPList(const oo::PList* value, HPVector defaultValue)
{
    HPVector result = defaultValue;
    std::array<double, 3> components { };

    switch (oo::plist_get::tupleFrom(value, kXYZ, components)) {
    case oo::plist_get::TupleSource::components:
        result.x = components[0];
        result.y = components[1];
        result.z = components[2];
        break;

    case oo::plist_get::TupleSource::string:
        cxx_ScanHPVectorFromString(*value->getIf<std::string>(), &result);
        break;

    case oo::plist_get::TupleSource::object: // (no native HPVector object: the default)
    case oo::plist_get::TupleSource::none:
        break;
    }

    return result;
}

Quaternion OOQuaternionFromPList(const oo::PList* value, Quaternion defaultValue)
{
    Quaternion result = defaultValue;
    std::array<float, 4> components { };

    switch (oo::plist_get::tupleFrom(value, kWXYZ, components)) {
    case oo::plist_get::TupleSource::components:
        result.w = components[0];
        result.x = components[1];
        result.y = components[2];
        result.z = components[3];
        break;

    case oo::plist_get::TupleSource::string:
        cxx_ScanQuaternionFromString(*value->getIf<std::string>(), &result);
        break;

    case oo::plist_get::TupleSource::object:
    case oo::plist_get::TupleSource::none:
        break;
    }

    return result;
}

oo::PList OOPListFromVector(Vector value)
{
    return oo::plist_get::tuplePList<float, 3>(kXYZ, { value.x, value.y, value.z });
}

oo::PList OOPListFromHPVector(HPVector value)
{
    return oo::plist_get::tuplePList<double, 3>(kXYZ, { value.x, value.y, value.z });
}

oo::PList OOPListFromQuaternion(Quaternion value)
{
    return oo::plist_get::tuplePList<float, 4>(kWXYZ, { value.w, value.x, value.y, value.z });
}

BOOL OOFuzzyBooleanFromPList(const oo::PList* value, float defaultValue)
{
    /*	This will always be NO for negative values and YES for values
            greater than 1, as expected. randf() is always less than 1, so
            < is the correct operator here.
    */
    return randf() < oo::plist_get::fuzzyProbabilityFrom(value, defaultValue);
}
