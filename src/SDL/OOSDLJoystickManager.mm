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

#import "OOSDLJoystickManager.h"
#include "oofnd/Log.hpp"
#include "oofnd/String.hpp"

OOSDLJoystickManager::OOSDLJoystickManager()
{
    int i;

    std::map<std::string, int, std::less<>> idMap;

    // Find and open the sticks. Make sure that we don't fail if more joysticks than MAX_STICKS are detected.
    SDL_JoystickID* joystickIds = SDL_GetJoysticks(&stickCount);
    OO_LOG("joystick.init", "Number of joysticks detected: {}", stickCount);
    if (stickCount > MAX_STICKS) {
        stickCount = MAX_STICKS;
        OO_LOG("joystick.init", "Number of joysticks detected exceeds maximum number of joysticks allowed. Setting number of active joysticks to {}.", MAX_STICKS);
    }
    if (stickCount) {
        for (i = 0; i < stickCount; i++) {
            // it's doubtful MAX_STICKS will ever get exceeded, but
            // we need to be defensive.
            if (i > MAX_STICKS)
                break;

            stick[i] = SDL_OpenJoystick(joystickIds[i]);
            if (stick[i]) {
                idMap[oo::str::format("%d", joystickIds[i])] = i;
            } else {
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
    if (index != joystickIdMap.end()) {
        return index->second;
    }
    return -1;
}

NSUInteger OOSDLJoystickManager::joystickCount()
{
    return stickCount;
}

std::optional<std::string> OOSDLJoystickManager::nameOfJoystick(NSUInteger stickNumber)
{
    if (stickNumber >= static_cast<NSUInteger>(stickCount))
        return std::string("(unknown joystick)");
    const char* name = SDL_GetJoystickName(stick[stickNumber]);
    if (name == NULL)
        return std::nullopt; // no string for a NULL name, as before
    return std::string(name);
}

int16_t OOSDLJoystickManager::getAxisWithStick(NSUInteger stickNum, NSUInteger axisNum)
{
    return SDL_GetJoystickAxis(stick[stickNum], axisNum);
}

SDL_JoyAxisEvent OOSDLJoystickManager::makeJoyAxisEvent(SDL_JoyAxisEvent* sdlevt)
{
    SDL_JoyAxisEvent evt;
    evt.type = sdlevt->type;
    evt.which = getJoystickIndexFromId(sdlevt->which);
    evt.axis = sdlevt->axis;
    evt.value = sdlevt->value;
    return evt;
}

SDL_JoyButtonEvent OOSDLJoystickManager::makeJoyButtonEvent(SDL_JoyButtonEvent* sdlevt)
{
    SDL_JoyButtonEvent evt;
    evt.type = sdlevt->type;
    evt.which = getJoystickIndexFromId(sdlevt->which);
    evt.button = sdlevt->button;
    evt.down = sdlevt->down;
    return evt;
}

SDL_JoyHatEvent OOSDLJoystickManager::makeJoyHatEvent(SDL_JoyHatEvent* sdlevt)
{
    SDL_JoyHatEvent evt;
    evt.type = sdlevt->type;
    evt.which = getJoystickIndexFromId(sdlevt->which);
    evt.hat = sdlevt->hat;
    evt.value = sdlevt->value;
    return evt;
}

bool OOSDLJoystickManager::handleSDLEvent(SDL_Event* evt)
{
    bool rc = false;
    switch (evt->type) {
    case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    case SDL_EVENT_JOYSTICK_AXIS_MOTION: {
        SDL_JoyAxisEvent joyEvt = makeJoyAxisEvent((SDL_JoyAxisEvent*)evt);
        // The index, not joyEvt.which: an unknown stick's -1 is 0xFFFFFFFF in the unsigned
        // SDL_JoystickID, which passed a `which >= 0` test (bead oo-9ht.3).
        if (getJoystickIndexFromId(((SDL_JoyAxisEvent*)evt)->which) >= 0) {
            decodeAxisEvent(&joyEvt);
            rc = true;
        }
        break;
    }

    case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
    case SDL_EVENT_GAMEPAD_BUTTON_UP:
    case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
    case SDL_EVENT_JOYSTICK_BUTTON_UP: {
        SDL_JoyButtonEvent joyEvt = makeJoyButtonEvent((SDL_JoyButtonEvent*)evt);
        if (getJoystickIndexFromId(((SDL_JoyButtonEvent*)evt)->which) >= 0) {
            decodeButtonEvent(&joyEvt);
            rc = true;
        }
        break;
    }

    case SDL_EVENT_JOYSTICK_HAT_MOTION: {
        SDL_JoyHatEvent joyEvt = makeJoyHatEvent((SDL_JoyHatEvent*)evt);
        if (getJoystickIndexFromId(((SDL_JoyHatEvent*)evt)->which) >= 0) {
            decodeHatEvent(&joyEvt);
            rc = true;
        }
        break;
    }

    default:
        OO_LOG("handleSDLEvent.unknownEvent", "{}", "JoystickHandler was sent an event it doesn't know");
    }
    return rc;
}

// The decoders read and set OOJoystickManager's state, this object's own (see
// OOSDLJoystickManager.h).
void OOSDLJoystickManager::decodeAxisEvent(SDL_JoyAxisEvent* evt)
{
    // Which axis moved? Does the value need to be made to fit a
    // certain function? Convert axis value to a double.
    double axisvalue = (double)evt->value;

    // First check if there is a callback and...
    if (cbCallback && (cbHardware & HW_AXIS)) {
        // ...then check if axis moved more than AXCBTHRESH - (fix for BUG #17482)
        if (axisvalue > AXCBTHRESH) {
            oo::PList::Dict fnDict;
            fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(true));
            fnDict[std::string(STICK_NUMBER)] = oo::PList(static_cast<int>(evt->which));
            fnDict[std::string(STICK_AXBUT)] = oo::PList(static_cast<int>(evt->axis));
            cbHardware = 0;
            const StickCallback callback = cbCallback; // a copy: the callback may set another
            callback(oo::PList(std::move(fnDict)));
            cbCallback = nullptr;
        }

        // we are done.
        return;
    }

    // SDL seems to have some bizarre (perhaps a bug) behaviour when
    // events get queued up because the game isn't ready to handle
    // them (perhaps it's loading a commander and initializing the
    // universe, and the main event loop is blocked).
    // What happens is SDL lies about the axis that was triggered. For
    // each queued event it adds 1 to the axis number!! This does
    // not seem to happen with buttons.
    int function;
    if (evt->axis < MAX_AXES) {
        function = axismap[evt->which][evt->axis];
    } else {
        OO_LOG("decodeAxisEvent", "Stick axis out of range - axis was {}", evt->axis);
        return;
    }
    switch (function) {
    case STICK_NOFUNCTION:
        // do nothing
        break;
    case AXIS_THRUST:
        // Normalize the thrust setting.
        axstate[function] = (float)(65536 - (axisvalue + 32768)) / 65536;
        break;
    case AXIS_ROLL:
    case AXIS_PITCH:
    case AXIS_YAW:
    case AXIS_VIEWX:
    case AXIS_VIEWY:
        axstate[function] = axisvalue / STICK_NORMALDIV;
        break;
    // TODO AXIS_FIELD_OF_VIEW
    default:
        // set the state with no modification.
        axstate[function] = axisvalue / 32768;
    }
    if ((function == AXIS_PITCH) && invertPitch)
        axstate[function] = -1.0 * axstate[function];
}

void OOSDLJoystickManager::decodeButtonEvent(SDL_JoyButtonEvent* evt)
{
    bool bs = false;

    // Is there a callback we need to make?
    if (cbCallback && (cbHardware & HW_BUTTON)) {
        oo::PList::Dict fnDict;
        fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(false));
        fnDict[std::string(STICK_NUMBER)] = oo::PList(static_cast<int>(evt->which));
        fnDict[std::string(STICK_AXBUT)] = oo::PList(static_cast<int>(evt->button));
        cbHardware = 0;
        const StickCallback callback = cbCallback; // a copy: the callback may set another
        callback(oo::PList(std::move(fnDict)));
        cbCallback = nullptr;

        // we are done.
        return;
    }

    // Defensive measure - see comments in the axis handler for why.
    int function;
    int guifunction;
    if (evt->button < MAX_BUTTONS) {
        function = buttonmap[evt->which][evt->button];
        guifunction = guibuttonmap[evt->which][evt->button];
    } else {
        OO_LOG("decodeButtonEvent", "Joystick button out of range: {}", evt->button);
        return;
    }
    if (evt->type == SDL_EVENT_JOYSTICK_BUTTON_DOWN) {
        bs = true;
        if (function == BUTTON_PRECISION)
            precisionMode = !precisionMode;
    }
    true_butstate[evt->which][evt->button] = bs;
    if (function >= 0) {
        butstate[function] = bs;
    }
    if (guifunction >= 0) {
        butstate[guifunction] = bs;
    }
}

void OOSDLJoystickManager::decodeHatEvent(SDL_JoyHatEvent* evt)
{
    // HACK: handle this as a set of buttons
    int i;
    SDL_JoyButtonEvent btn;

    btn.which = evt->which;

    for (i = 0; i < 4; ++i) {
        if ((evt->value ^ hatstate[evt->which][evt->hat]) & (1 << i)) {
            btn.type = (evt->value & (1 << i)) ? SDL_EVENT_JOYSTICK_BUTTON_DOWN : SDL_EVENT_JOYSTICK_BUTTON_UP;
            btn.button = MAX_REAL_BUTTONS + i + evt->which * 4;
            btn.down = (evt->value & (1 << i));
            decodeButtonEvent(&btn);
        }
    }

    hatstate[evt->which][evt->hat] = evt->value;
}
