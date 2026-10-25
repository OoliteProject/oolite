/*

OOSDLJoystickManager.m
By Dylan Smith

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

#include "OOSDLJoystickManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"


OOSDLJoystickManager::OOSDLJoystickManager()
{
	int i;

	std::map<std::string, int, std::less<>> idMap;

	// Find and open the sticks. Make sure that we don't fail if more joysticks than MAX_STICKS are detected.
	SDL_JoystickID *joystickIds = SDL_GetJoysticks(&stickCount);
	OO_LOG("joystick.init", "Number of joysticks detected: {}", stickCount);
	if (stickCount > MAX_STICKS)
	{
		stickCount = MAX_STICKS;
		OO_LOG("joystick.init", "Number of joysticks detected exceeds maximum number of joysticks allowed. Setting number of active joysticks to {}.", MAX_STICKS);
	}
	if(stickCount)
	{
		for(i = 0; i < stickCount; i++)
		{
			// it's doubtful MAX_STICKS will ever get exceeded, but
			// we need to be defensive.
			if(i > MAX_STICKS)
				break;

			stick[i]=SDL_OpenJoystick(joystickIds[i]);
			if(stick[i])
			{
				idMap[oo::str::format("%d", joystickIds[i])] = i;
			}
			else
			{
				OO_LOG("joystick.init", "Failed to open joystick #{}", i);
			}
		}
		SDL_SetJoystickEventsEnabled(true);
	}
	SDL_free(joystickIds);
	joystickIdMap = std::move(idMap);
}


NSInteger OOSDLJoystickManager::getJoystickIndexFromId(SDL_JoystickID joystickId)
{
	const auto index = joystickIdMap.find(oo::str::format("%d", joystickId));
	if (index != joystickIdMap.end())
	{
		return index->second;
	}
	return -1;
}


JoyAxisEvent OOSDLJoystickManager::makeJoyAxisEvent(SDL_JoyAxisEvent *sdlevt)
{
	JoyAxisEvent evt;
	evt.type = sdlevt->type;
	evt.which = getJoystickIndexFromId(sdlevt->which);
	evt.axis = sdlevt->axis;
	evt.value = sdlevt->value;
	return evt;
}

JoyButtonEvent OOSDLJoystickManager::makeJoyButtonEvent(SDL_JoyButtonEvent *sdlevt)
{
	JoyButtonEvent evt;
	evt.type = sdlevt->type;
	evt.which = getJoystickIndexFromId(sdlevt->which);
	evt.button = sdlevt->button;
	evt.down = sdlevt->down;
	return evt;
}


JoyHatEvent OOSDLJoystickManager::makeJoyHatEvent(SDL_JoyHatEvent *sdlevt)
{
	JoyHatEvent evt;
	evt.type = sdlevt->type;
	evt.which = getJoystickIndexFromId(sdlevt->which);
	evt.hat = sdlevt->hat;
	evt.value = sdlevt->value;
	return evt;
}


bool OOSDLJoystickManager::handleSDLEvent(SDL_Event *evt)
{
	bool rc=false;
	switch(evt->type)
	{
		case SDL_EVENT_GAMEPAD_AXIS_MOTION:
		case SDL_EVENT_JOYSTICK_AXIS_MOTION:
		{
			JoyAxisEvent joyEvt = makeJoyAxisEvent((SDL_JoyAxisEvent*)evt);
			// The index, not joyEvt.which: an unknown stick's -1 is 0xFFFFFFFF in the unsigned
			// SDL_JoystickID, which passed a `which >= 0` test (bead oo-9ht.3).
			if (getJoystickIndexFromId(((SDL_JoyAxisEvent*)evt)->which) >= 0)
			{
				decodeAxisEvent(&joyEvt);	// OOJoystickManager's
				rc=true;
			}
			break;
		}

		case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
		case SDL_EVENT_GAMEPAD_BUTTON_UP:
		case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
		case SDL_EVENT_JOYSTICK_BUTTON_UP:
		{
			JoyButtonEvent joyEvt = makeJoyButtonEvent((SDL_JoyButtonEvent*)evt);
			if (getJoystickIndexFromId(((SDL_JoyButtonEvent*)evt)->which) >= 0)
			{
				decodeButtonEvent(&joyEvt);	// OOJoystickManager's
				rc=true;
			}
			break;
		}

		case SDL_EVENT_JOYSTICK_HAT_MOTION:
		{
			JoyHatEvent joyEvt = makeJoyHatEvent((SDL_JoyHatEvent*)evt);
			if (getJoystickIndexFromId(((SDL_JoyHatEvent*)evt)->which) >= 0)
			{
				decodeHatEvent(&joyEvt);	// OOJoystickManager's
				rc=true;
			}
			break;
		}

		default:
			OO_LOG("handleSDLEvent.unknownEvent", "{}", "JoystickHandler was sent an event it doesn't know");
	}
	return rc;
}


// Overrides

NSUInteger OOSDLJoystickManager::joystickCount()
{
	return stickCount;
}


std::optional<std::string> OOSDLJoystickManager::nameOfJoystick(NSUInteger stickNumber)
{
	if (stickNumber >= static_cast<NSUInteger>(stickCount))  return std::string("(unknown joystick)");
	const char *name = SDL_GetJoystickName(stick[stickNumber]);
	if (name == NULL)  return std::nullopt;	// no string for a NULL name, as before
	return std::string(name);
}


int16_t OOSDLJoystickManager::getAxisWithStick(NSUInteger stickNum, NSUInteger axisNum)
{
	return SDL_GetJoystickAxis(stick[stickNum], axisNum);
}

