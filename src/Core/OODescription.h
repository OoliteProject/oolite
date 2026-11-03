/*

OODescription.h

The description family as C++ text on the Objective-C root (proposed ADR-0055 item 1, bead
oo-qps.31). Foundation-free: it names nothing from gnustep-base, and survives oo-qps.18.

A class describes itself by overriding one method, and every printer wraps it:

        override                              printed by                          as
        ------------------------------------  ----------------------------------  ---------------------------------
        -cxx_descriptionComponents            -cxx_description, oo::DescriptionOf <ClassName 0xnnnnnnnn>{components}
                                              -cxx_oo_jsDescription (JS)          [jsClassName components]
        -cxx_shortDescriptionComponents       -cxx_shortDescription,              <ClassName 0xnnnnnnnn>{components}
                                              oo::ShortDescriptionOf
        -cxx_description (whole text)         oo::DescriptionOf                   whatever it returns

Without components (nullopt, the root's default) the text is <ClassName 0xnnnnnnnn>. The pointer
is oo::str::pointerDescription's (GNUstep's %p: the low 32 bits). A subclass that extends its
superclass's components calls [super cxx_descriptionComponents] and appends to it.

        - (std::optional<std::string>) cxx_descriptionComponents
        {
                return oo::str::format("%g, %g, %g, %g", rgba[0], rgba[1], rgba[2], rgba[3]);
        }

All four return std::optional<std::string>, so a message to nil is a valid nullopt (ADR-0043
fact 1). Phase 3 keeps the signature as virtual std::optional<std::string>
descriptionComponents() const.

oo::DescriptionOf(x) is the text "%@" put in a formatted string for x: "(null)" for nil, the
class name for a class object, -cxx_description for an OOObject; for an oo::PList, what "%@"
printed for its object graph (oo::describe). oo::ShortDescriptionOf(x) is
its short twin. OOConstantString describes itself as its text.

An object not rooted on OOObject (none in the game since oo-3rb.4 / oo-qps.18) describes as
<ClassName 0xnnnnnnnn> in both. The transitional forwarding to legacy id-typed
-description* overrides and the foreign -description fallback were deleted by oo-qps.73.

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

#ifndef OODESCRIPTION_H
#define OODESCRIPTION_H

#import "oofnd/objc/OOConstantString.h"
#import "oofnd/objc/OOObject.h"

// extern "C++" because this header is reached from inside an extern "C" block (OOMaths.h ->
// OOFoundation.h), as OOLogging.h is.
extern "C++" {

#include "oofnd/PListDescription.hpp"
#include "oofnd/StdLib.hpp"

@interface OOObject (OODescription)

// What this object adds between the braces; nullopt for none (the root's default).
- (std::optional<std::string>)cxx_descriptionComponents;
- (std::optional<std::string>)cxx_shortDescriptionComponents;

// <ClassName 0xnnnnnnnn>{components}, or <ClassName 0xnnnnnnnn> without components.
- (std::optional<std::string>)cxx_description;
- (std::optional<std::string>)cxx_shortDescription;

@end

// A string literal describes itself as its text.
@interface OOConstantString (OODescription)

- (std::optional<std::string>)cxx_description;
- (std::optional<std::string>)cxx_shortDescription;

@end

namespace oo {

    // The text "%@" printed for <object>: "(null)" for nil, a class's name, else its description.
    std::string DescriptionOf(id object);

    // The same with -cxx_shortDescription.
    std::string ShortDescriptionOf(id object);

    // <ClassName 0xnnnnnnnn>{components} for <object>; without the braces when <components> is nullopt.
    std::string DescriptionWithComponents(id object, const std::optional<std::string>& components);

    // The text "%@" printed for the property list's object graph (oo::ObjectFromPList of it):
    // oo::describe (oofnd/PListDescription.hpp), GNUstep's -description byte for byte.
    inline std::string DescriptionOf(const oo::PList& plist)
    {
        return describe(plist);
    }

} // namespace oo

} // extern "C++"

#endif // OODESCRIPTION_H
