/*

OOCallByName.h

Calling an entity's method that the game names at run time (an AI action, a
legacy-script action or query, a string-expander [selector] key, ship.call(), a
deferred call), with C++ arguments.

oo::CallEntityByName(entity, name [, argument]) looks <name> up in the by-name
table (OOEntityCalledByNameTable.h) and calls the method if it has one of these
forms:

  - no argument: void name() or oo::PList name();
  - a string:    void name(const std::string&) or
                 oo::PList name(const std::string&);
  - a PList:     void name(const oo::PList&).

A void method's call answers a null PList; a PList method's call answers what
it returns. A scalar or object result (the ship a launch action returns) is
ignored: no caller reads one (OOJSCall calls an object-returning method
itself). A string argument reaches a (const oo::PList&) parameter as a string
PList; a PList argument reaches a (const std::string&) parameter only when it
is a string.

A null entity does nothing. A name the entity does not answer, or whose method
has none of the forms above, is logged (callByName.unknownSelector /
callByName.badSignature) and not called; the result is a null PList.

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

#include "oofnd/PList.hpp"
#include "oofnd/objc/OOObject.h"

/*	An entity's method called by name: the same call on the entity's C++
   part. A name in the generated table (OOEntityCalledByNameTable.h) is answered
   by the C++ part it applies to; any other name is logged
   (callByName.unknownSelector / callByName.badSignature) and not called. A
   tabled name that applies but whose signature the call cannot use is logged
   here (callByName.badSignature, with the type encoding without frame
   offsets). A null entity does nothing. Defined in
   OOEntityCalledByName.cpp.
*/
class Entity;

namespace oo {

bool EntityRespondsToName(Entity* entity, const std::string& name);
PList CallEntityByName(Entity* entity, const std::string& name);
PList CallEntityByName(Entity* entity, const std::string& name,
                       const std::string& argument);
PList CallEntityByName(Entity* entity, const std::string& name,
                       const PList& argument);

/*	An entity's method called after <delay> seconds, as
   OOScheduleDeferredCall() does (the afterburner sound's update, a ship's
   cargo dumped a canister at a time). The call holds the entity, and calls
   <call> with it when it fires; <call> asks for the entity's class. A null
   entity schedules nothing. Defined in OOEntityCalledByName.cpp.
*/
void ScheduleEntityCall(Entity* entity, void (*call)(Entity* entity),
                        double delay);

}  // namespace oo
