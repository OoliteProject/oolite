/*

OODescription.h

oo::DescriptionOf(const oo::PList&): the text "%@" printed for a property
list's object graph, gnustep-base's -description byte for byte (oo::describe,
oofnd/PListDescription.hpp).

An object describes itself through a virtual
std::optional<std::string> descriptionComponents() const: the text is
<ClassName 0xnnnnnnnn>{components}, or <ClassName 0xnnnnnnnn> for nullopt. The
pointer is oo::str::pointerDescription's (GNUstep's %p: the low 32 bits). A
subclass extends its base's components by calling the base and appending.

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

#include "oofnd/PListDescription.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/objc/OOObject.h"

namespace oo {

// The text "%@" printed for the property list's object graph
// (oo::ObjectFromPList of it): oo::describe (oofnd/PListDescription.hpp),
// GNUstep's -description byte for byte.
inline std::string DescriptionOf(const oo::PList& plist) {
  return describe(plist);
}

}  // namespace oo
