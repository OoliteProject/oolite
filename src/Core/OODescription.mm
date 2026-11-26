/*

OODescription.mm

The description family on the Objective-C root (proposed ADR-0055 item 1, bead oo-qps.31). See
OODescription.h. Foundation-free: this file imports nothing from gnustep-base (the unit test
tests/unit/oofnd/test_objc_description.mm links it against libobjc2 alone).

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

#import "OODescription.h"

#include "oofnd/String.hpp"

#include <objc/runtime.h>

namespace {

// Whether <object> is rooted on OOObject (so it answers the C++ family).
bool IsOOObject(id object)
{
    for (Class cls = object_getClass(object); cls != Nil; cls = class_getSuperclass(cls)) {
        if (cls == [OOObject class])
            return true;
    }
    return false;
}

} // namespace

@implementation OOObject (OODescription)

- (std::optional<std::string>)cxx_descriptionComponents
{
    return std::nullopt;
}

- (std::optional<std::string>)cxx_shortDescriptionComponents
{
    return std::nullopt;
}

- (std::optional<std::string>)cxx_description
{
    return oo::DescriptionWithComponents(self, [self cxx_descriptionComponents]);
}

- (std::optional<std::string>)cxx_shortDescription
{
    return oo::DescriptionWithComponents(self, [self cxx_shortDescriptionComponents]);
}

@end

@implementation OOConstantString (OODescription)

- (std::optional<std::string>)cxx_description
{
    return std::string([self UTF8String]);
}

- (std::optional<std::string>)cxx_shortDescription
{
    return std::string([self UTF8String]);
}

@end

namespace oo {

std::string DescriptionOf(id object)
{
    if (object == nil)
        return "(null)";
    if (class_isMetaClass(object_getClass(object)))
        return class_getName((Class)object);
    if (IsOOObject(object)) {
        return [(OOObject*)object cxx_description].value_or("(null)");
    }
    // An object on another root (nothing in the game since oo-3rb.4 made every literal an
    // OOConstantString and oo-qps.18 unlinked gnustep-base): <ClassName 0xnnnnnnnn>.
    return DescriptionWithComponents(object, std::nullopt);
}

std::string ShortDescriptionOf(id object)
{
    if (object == nil)
        return "(null)";
    if (class_isMetaClass(object_getClass(object)))
        return class_getName((Class)object);
    if (IsOOObject(object)) {
        return [(OOObject*)object cxx_shortDescription].value_or("(null)");
    }
    return DescriptionWithComponents(object, std::nullopt); // another root, as DescriptionOf
}

std::string DescriptionWithComponents(id object, const std::optional<std::string>& components)
{
    std::string result = str::format("<%s %s>", class_getName([object class]), str::pointerDescription(object).c_str());
    if (components.has_value())
        result += "{" + *components + "}";
    return result;
}

} // namespace oo
