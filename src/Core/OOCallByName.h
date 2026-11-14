/*

OOCallByName.h

Calling a method the game names at run time (an AI action, a legacy-script
action or query, a HUD dial, a deferred call) with C++ arguments.
Foundation-free.

A method called by name has one of its dispatcher's signatures; OOCallByName
reads the method's type encoding and calls it through an IMP of exactly that
type:

        call                                     the method may be                        result
        ---------------------------------------  ---------------------------------------  -----------------
        OOCallByName(target, sel)                - (void) sel                              null PList
                                                 - (oo::PList) sel                         what it returns
        OOCallByName(target, sel, "text")        - (void) sel:(const std::string &)s       null PList
                                                 - (oo::PList) sel:(const std::string &)s  what it returns
        OOCallByName(target, sel, plist)         - (void) sel:(const oo::PList &)p         null PList

A scalar result (BOOL, float...) or an object result (the ship a launch action
returns) is ignored: no dispatcher reads one (OOJSCall calls an
object-returning method itself). A method with an object (id) parameter is not
called (see below). A string argument reaches a (const oo::PList &) parameter
as a string PList; a PList argument reaches a (const std::string &) parameter
only when it is a string.

        dispatcher                                                  argument        result
        ----------------------------------------------------------  --------------  -----------
        AI actions, deferred AI calls (AI.mm), legacy-script        none or string  void / PList
        actions, ship.call() (OOJSCall.mm)
        legacy-script queries (*_string, *_number, *_bool),         none            PList (a string
        expander [selector] keys                                                    or a number)
        HUD dials (HeadUpDisplay.mm), joystick callbacks            PList           void

An entity's method is called by its name through oo::CallEntityByName (below):
the AI's actions and messages and the legacy script engine.

A method with an id parameter that takes the argument as an object
is logged (callByName.badSignature) and not called.

A nil target does nothing (as messaging nil). A target that does not answer
<selector>, or whose method has no signature above, is logged
(callByName.unknownSelector / callByName.badSignature) and not called; the
result is a null PList. A forwarding proxy (an entity's weak reference) is
followed.

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

#include "oofnd/objc/OOObject.h"

// extern "C++": reachable from inside an extern "C" block, as OOLogging.h is.
extern "C++" {

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

// The signatures above are the entity call's (below).

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
    void ScheduleEntityCall(Entity* entity, void (*call)(Entity* entity), double delay);

} // namespace oo

} // extern "C++"
