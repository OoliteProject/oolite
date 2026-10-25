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
Since beads oo-9ht.2 and oo-9ht.69 deleted the Objective-C facades, OOSDLJoystickManager derives
from the C++ OOJoystickManager (the superclass's state and decoders are its own) and is made by
the factory MyOpenGLView registers; the constructor is the old -init's body, which ran before
[super init], so the superclass's init() runs after it (OOJoystickManager::sharedStickHandler()).

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

#include "OOCocoa.h"
#include <SDL3/SDL_events.h>
#include "OOJoystickManager.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"


class OOSDLJoystickManager : public OOJoystickManager
{
public:
	OOSDLJoystickManager();		// opens the sticks SDL reports (at most MAX_STICKS)

	bool handleSDLEvent(SDL_Event *evt);
	std::optional<std::string> nameOfJoystick(NSUInteger stickNumber) override;	// nullopt: the device has no name
	int16_t getAxisWithStick(NSUInteger stickNum, NSUInteger axisNum) override;
	JoyAxisEvent makeJoyAxisEvent(SDL_JoyAxisEvent *sdlevt);
	JoyButtonEvent makeJoyButtonEvent(SDL_JoyButtonEvent *sdlevt);
	JoyHatEvent makeJoyHatEvent(SDL_JoyHatEvent *sdlevt);
	NSInteger getJoystickIndexFromId(SDL_JoystickID joystickId);

	// Overrides of OOJoystickManager.
	NSUInteger joystickCount() override;

private:
	std::map<std::string, int, std::less<>>	joystickIdMap = {};	// "%d" of an SDL joystick id -> stick index (proposed ADR-0043)
	SDL_Joystick		*stick[MAX_STICKS] = {};
	int			stickCount = {};
};

#endif	// OOSDLJOYSTICKMANAGER_H
