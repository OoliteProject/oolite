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
#import "OOLogging.h"

#define kOOLogUnconvertedNSLog @"unclassified.OOSDLJoystickManager"

@implementation OOSDLJoystickManager

- (id)init
{
    int i;

    NSMutableDictionary* idMap = [[[NSMutableDictionary alloc] init] autorelease];

    // Find and open the sticks. Make sure that we don't fail if more joysticks than MAX_STICKS are detected.
    SDL_JoystickID* joystickIds = SDL_GetJoysticks(&stickCount);
    OOLog(@"joystick.init", @"Number of joysticks detected: %d", stickCount);
    if (stickCount > MAX_STICKS) {
        stickCount = MAX_STICKS;
        OOLog(@"joystick.init", @"Number of joysticks detected exceeds maximum number of joysticks allowed. Setting number of active joysticks to %d.", MAX_STICKS);
    }
    if (stickCount) {
        for (i = 0; i < stickCount; i++) {
            // it's doubtful MAX_STICKS will ever get exceeded, but
            // we need to be defensive.
            if (i > MAX_STICKS)
                break;

            stick[i] = SDL_OpenJoystick(joystickIds[i]);
            if (stick[i]) {
                [idMap setObject:[NSNumber numberWithInt:i] forKey:[NSString stringWithFormat:@"%d", joystickIds[i]]];
            } else {
                OOLog(@"joystick.init", @"Failed to open joystick #%d", i);
            }
        }
        SDL_SetJoystickEventsEnabled(true);
    }
    SDL_free(joystickIds);
    joystickIdMap = [idMap copy];
    return [super init];
}

- (void)dealloc
{
    [joystickIdMap release];
    [super dealloc];
}

- (NSInteger)getJoystickIndexFromId:(SDL_JoystickID)joystickId
{
    NSNumber* index = [joystickIdMap valueForKey:[NSString stringWithFormat:@"%d", joystickId]];
    if (index) {
        return [index integerValue];
    }
    return -1;
}

- (NSUInteger)joystickCount
{
    return stickCount;
}

- (NSString*)nameOfJoystick:(NSUInteger)stickNumber
{
    if (stickNumber >= stickCount)
        return @"(unknown joystick)";
    return [NSString stringWithUTF8String:SDL_GetJoystickName(stick[stickNumber])];
}

- (int16_t)getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
    return SDL_GetJoystickAxis(stick[stickNum], axisNum);
}

- (SDL_JoyAxisEvent)makeJoyAxisEvent:(SDL_JoyAxisEvent*)sdlevt
{
    SDL_JoyAxisEvent evt;
    evt.type = sdlevt->type;
    evt.which = [self getJoystickIndexFromId:sdlevt->which];
    evt.axis = sdlevt->axis;
    evt.value = sdlevt->value;
    return evt;
}

- (SDL_JoyButtonEvent)makeJoyButtonEvent:(SDL_JoyButtonEvent*)sdlevt
{
    SDL_JoyButtonEvent evt;
    evt.type = sdlevt->type;
    evt.which = [self getJoystickIndexFromId:sdlevt->which];
    evt.button = sdlevt->button;
    evt.down = sdlevt->down;
    return evt;
}

- (SDL_JoyHatEvent)makeJoyHatEvent:(SDL_JoyHatEvent*)sdlevt
{
    SDL_JoyHatEvent evt;
    evt.type = sdlevt->type;
    evt.which = [self getJoystickIndexFromId:sdlevt->which];
    evt.hat = sdlevt->hat;
    evt.value = sdlevt->value;
    return evt;
}

- (void)decodeAxisEvent:(SDL_JoyAxisEvent*)evt
{
    // Which axis moved? Does the value need to be made to fit a
    // certain function? Convert axis value to a double.
    double axisvalue = (double)evt->value;

    // First check if there is a callback and...
    if (cbObject && (cbHardware & HW_AXIS)) {
        // ...then check if axis moved more than AXCBTHRESH - (fix for BUG #17482)
        if (axisvalue > AXCBTHRESH) {
            NSDictionary* fnDict = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithBool:YES], STICK_ISAXIS,
                [NSNumber numberWithInt:evt->which], STICK_NUMBER,
                [NSNumber numberWithInt:evt->axis], STICK_AXBUT,
                nil];
            cbHardware = 0;
            [cbObject performSelector:cbSelector withObject:fnDict];
            cbObject = nil;
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
        OOLog(@"decodeAxisEvent", @"Stick axis out of range - axis was %d", evt->axis);
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

- (void)decodeButtonEvent:(SDL_JoyButtonEvent*)evt
{
    BOOL bs = NO;

    // Is there a callback we need to make?
    if (cbObject && (cbHardware & HW_BUTTON)) {
        NSDictionary* fnDict = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithBool:NO], STICK_ISAXIS,
            [NSNumber numberWithInt:evt->which], STICK_NUMBER,
            [NSNumber numberWithInt:evt->button], STICK_AXBUT,
            nil];
        cbHardware = 0;
        [cbObject performSelector:cbSelector withObject:fnDict];
        cbObject = nil;

        // we are done.
        return;
    }

    // Defensive measure - see comments in the axis handler for why.
    int function;
    if (evt->button < MAX_BUTTONS) {
        function = buttonmap[evt->which][evt->button];
    } else {
        OOLog(@"decodeButtonEvent", @"Joystick button out of range: %d", evt->button);
        return;
    }
    if (evt->type == SDL_EVENT_JOYSTICK_BUTTON_DOWN) {
        bs = YES;
        if (function == BUTTON_PRECISION)
            precisionMode = !precisionMode;
    }
    true_butstate[evt->which][evt->button] = bs;
    if (function >= 0) {
        butstate[function] = bs;
    }
}

- (void)decodeHatEvent:(SDL_JoyHatEvent*)evt
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
            [self decodeButtonEvent:&btn];
        }
    }

    hatstate[evt->which][evt->hat] = evt->value;
}

- (BOOL)handleSDLEvent:(SDL_Event*)evt
{
    BOOL rc = NO;
    switch (evt->type) {
    case SDL_EVENT_GAMEPAD_AXIS_MOTION:
    case SDL_EVENT_JOYSTICK_AXIS_MOTION: {
        SDL_JoyAxisEvent joyEvt = [self makeJoyAxisEvent:(SDL_JoyAxisEvent*)evt];
        if (joyEvt.which >= 0) {
            [self decodeAxisEvent:&joyEvt];
            rc = YES;
        }
        break;
    }

    case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
    case SDL_EVENT_GAMEPAD_BUTTON_UP:
    case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
    case SDL_EVENT_JOYSTICK_BUTTON_UP: {
        SDL_JoyButtonEvent joyEvt = [self makeJoyButtonEvent:(SDL_JoyButtonEvent*)evt];
        if (joyEvt.which >= 0) {
            [self decodeButtonEvent:&joyEvt];
            rc = YES;
        }
        break;
    }

    case SDL_EVENT_JOYSTICK_HAT_MOTION: {
        SDL_JoyHatEvent joyEvt = [self makeJoyHatEvent:(SDL_JoyHatEvent*)evt];
        if (joyEvt.which >= 0) {
            [self decodeHatEvent:&joyEvt];
            rc = YES;
        }
        break;
    }

    default:
        OOLog(@"handleSDLEvent.unknownEvent", @"%@", @"JoystickHandler was sent an event it doesn't know");
    }
    return rc;
}

@end
