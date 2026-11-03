/*

OOSDLJoystickManager.h
By Dylan Smith

JoystickHandler handles joystick events from SDL, and translates them
into the appropriate action via a lookup table. The lookup table is
stored as a simple array rather than an ObjC dictionary since this
will be examined fairly often (once per frame during gameplay).

Conversion methods are provided to convert between the internal
representation and a property-list dictionary (for loading/saving user defaults
and for use in areas where portability/ease of coding are more important
than performance such as the GUI)

C++20 since bead oo-o89, the Phase 3 platform (SDL/) pattern (proposed ADR-0056, amendment oo-o89).
The SDL half of the joystick manager is cxx::OOSDLJoystickManager. Its superclass,
OOJoystickManager, is still Objective-C, so the Objective-C OOSDLJoystickManager in
OOSDLJoystickManager+ObjCBridge.h (imported at the end of this header) stays the subclass that
superclass creates and messages; it owns the C++ object and forwards its overrides to it.
OOJoystickManager is C++ now (cxx::OOJoystickManager), but this class does not derive from it yet:
its Objective-C facade derives from the Objective-C OOJoystickManager, whose C++ part (an adapter)
holds the superclass's state. The C++ object is made only by that facade's -init. The decoders
(decodeAxisEvent() & co., which decode SDL events, upstream #742) are this class's; they read and
set that state through the facade (oo::ToObjC(this)), as cxx::OOJoystickManager's friend.

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

#ifndef OOSDLJOYSTICKMANAGER_H
#define OOSDLJOYSTICKMANAGER_H

#import "OOFoundation.h"
#import "OOJoystickManager.h"
#import <SDL3/SDL_events.h>

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

namespace cxx {

class OOSDLJoystickManager : public oo::RefCounted {
public:
    OOSDLJoystickManager(); // opens the sticks SDL reports (at most MAX_STICKS)

    bool handleSDLEvent(SDL_Event* evt);
    std::optional<std::string> nameOfJoystick(NSUInteger stickNumber); // nullopt: the device has no name
    int16_t getAxisWithStick(NSUInteger stickNum, NSUInteger axisNum);
    SDL_JoyAxisEvent makeJoyAxisEvent(SDL_JoyAxisEvent* sdlevt);
    SDL_JoyButtonEvent makeJoyButtonEvent(SDL_JoyButtonEvent* sdlevt);
    SDL_JoyHatEvent makeJoyHatEvent(SDL_JoyHatEvent* sdlevt);
    NSInteger getJoystickIndexFromId(SDL_JoystickID joystickId);
    void decodeAxisEvent(SDL_JoyAxisEvent* evt);
    void decodeButtonEvent(SDL_JoyButtonEvent* evt);
    void decodeHatEvent(SDL_JoyHatEvent* evt);

    // Overrides of OOJoystickManager (its facade subclass forwards them here).
    NSUInteger joystickCount();

private:
    // The superclass's C++ part, the state the decoders read and set: that of this object's facade,
    // borrowed; null once the facade is gone (the decoders then do nothing, as a message to nil did).
    cxx::OOJoystickManager* superclassState();

    std::map<std::string, int, std::less<>> joystickIdMap = { }; // "%d" of an SDL joystick id -> stick index (proposed ADR-0043)
    SDL_Joystick* stick[MAX_STICKS] = { };
    int stickCount = { };
};

} // namespace cxx

// Transitional: the Objective-C OOSDLJoystickManager, the OOJoystickManager subclass the
// superclass creates. Deleted, with namespace cxx above, by the bridge's deletion bead once
// OOJoystickManager is C++.
#import "OOSDLJoystickManager+ObjCBridge.h"

#endif // OOSDLJOYSTICKMANAGER_H
