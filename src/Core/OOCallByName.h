/*

OOCallByName.h

Calling a method the game names at run time (an AI action, a legacy-script action or query, a HUD
dial, a deferred call) with C++ arguments (proposed ADR-0055 item 5, bead oo-qps.34). It replaces
-performSelector:withObject:, which could only pass and return Objective-C objects. Foundation-free.

A method called by name has one of its dispatcher's signatures; OOCallByName reads the method's
type encoding and calls it through an IMP of exactly that type:

        call                                     the method may be                        result
        ---------------------------------------  ---------------------------------------  -----------------
        OOCallByName(target, sel)                - (void) sel                              null PList
                                                 - (oo::PList) sel                         what it returns
        OOCallByName(target, sel, "text")        - (void) sel:(const std::string &)s       null PList
                                                 - (oo::PList) sel:(const std::string &)s  what it returns
        OOCallByName(target, sel, plist)         - (void) sel:(const oo::PList &)p         null PList

A scalar result (BOOL, float...) or an object result (the ship a launch action returns) is
ignored: no dispatcher reads one (ADR-0055 Amendment 2; OOJSCall calls an object-returning method
itself). A method with an object (id) parameter is not called (see below). A string argument
reaches a (const oo::PList &) parameter as a string PList; a PList argument reaches a
(const std::string &) parameter only when it is a string.

        dispatcher                                                  argument        result
        ----------------------------------------------------------  --------------  -----------
        AI actions, deferred AI calls (AI.mm), legacy-script        none or string  void / PList
        actions, ship.call() (OOJSCall.mm)
        legacy-script queries (*_string, *_number, *_bool),         none            PList (a string
        expander [selector] keys                                                    or a number)
        HUD dials (HeadUpDisplay.mm), joystick callbacks            PList           void

oo-qps.72 deleted the transitional form that passed an id parameter the argument as an
Objective-C object: such a method is logged (callByName.badSignature) and not called.
tools/check-selector-types.py --check --strict-called-by-name rejects an object parameter, or an
id result, on a selector a dispatcher calls by name.

A nil target does nothing (as messaging nil). A target that does not answer <selector>, or whose
method has no signature above, is logged (callByName.unknownSelector / callByName.badSignature)
and not called; the result is a null PList. A forwarding proxy (OOWeakReference) is followed.
Phase 3 replaces the IMP lookup with a map from name to handler; the signatures stay.

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

#ifndef OOCALLBYNAME_H
#define OOCALLBYNAME_H

#import "oofnd/objc/OOObject.h"

// extern "C++": reachable from inside an extern "C" block, as OOLogging.h is.
extern "C++" {

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

oo::PList OOCallByName(id target, SEL selector);
oo::PList OOCallByName(id target, SEL selector, const std::string& argument);
oo::PList OOCallByName(id target, SEL selector, const oo::PList& argument);

// A literal argument is a string (without this, "text" converts to std::string and oo::PList alike).
inline oo::PList OOCallByName(id target, SEL selector, const char* argument)
{
    return OOCallByName(target, selector, std::string(argument));
}

} // extern "C++"

#endif // OOCALLBYNAME_H
