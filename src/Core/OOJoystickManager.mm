/*

OOJoystickManager.m
By Dylan Smith
modified by Alex Smith

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

#import "OOJoystickManager.h"
#import "OOCallByName.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/Log.hpp"

#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"

static Class sStickHandlerClass = Nil;
static id sSharedStickHandler = nil;

@interface OOJoystickManager (Private)

// Setting button and axis functions
- (void)setFunctionForAxis:(int)axis
                  function:(int)function
                     stick:(int)stickNum;

- (void)setFunctionForButton:(int)button
                    function:(int)function
                       stick:(int)stickNum;

@end

@implementation OOJoystickManager

+ (id)sharedStickHandler
{
    if (sSharedStickHandler == nil) {
        if (sStickHandlerClass == Nil)
            sStickHandlerClass = [OOJoystickManager class];
        sSharedStickHandler = [[sStickHandlerClass alloc] init];
    }
    return sSharedStickHandler;
}

+ (BOOL)setStickHandlerClass:(Class)aClass
{
    OOAssert(sStickHandlerClass == nil, "Can't set joystick handler class after joystick handler is initialized.");
    OOParameterAssert(aClass == Nil || [aClass isSubclassOfClass:[OOJoystickManager class]]);

    sStickHandlerClass = aClass;
    return YES;
}

- (id)init
{
    if ((self = [super init])) {
        // set initial values for stick buttons/axes (NO for buttons,
        // STICK_AXISUNASSIGNED for axes). Caution: calling this again
        // after axes have been assigned will set all the axes to
        // STICK_AXISUNASSIGNED so if there is a need to do something
        // like this, then do it some other way, or change this method
        // so it doesn't do that.
        [self clearStickStates];

        // Make some sensible mappings. This also ensures unassigned
        // axes and buttons are set to unassigned (STICK_NOFUNCTION).
        [self loadStickSettings];
        invertPitch = NO;
        precisionMode = NO;
    }
    return self;
}

- (NSPoint)rollPitchAxis
{
    return NSMakePoint([self getAxisState:AXIS_ROLL], [self getAxisState:AXIS_PITCH]);
}

- (NSPoint)viewAxis
{
    return NSMakePoint(axstate[AXIS_VIEWX], axstate[AXIS_VIEWY]);
}

- (BOOL)getButtonState:(int)function
{
    return butstate[function];
}

- (const BOOL*)getAllButtonStates
{
    return butstate;
}

- (BOOL)isButtonDown:(int)button stick:(int)stickNum
{
    return true_butstate[stickNum][button];
}

- (double)getAxisState:(int)function
{
    if (axstate[function] == STICK_AXISUNASSIGNED) {
        return STICK_AXISUNASSIGNED;
    }
    switch (function) {
    case AXIS_ROLL:
        if (precisionMode) {
            return [roll_profile value:axstate[function]] / STICK_PRECISIONFAC;
        } else {
            return [roll_profile value:axstate[function]];
        }
    case AXIS_PITCH:
        if (precisionMode) {
            return [pitch_profile value:axstate[function]] / STICK_PRECISIONFAC;
        } else {
            return [pitch_profile value:axstate[function]];
        }
    case AXIS_YAW:
        if (precisionMode) {
            return [yaw_profile value:axstate[function]] / STICK_PRECISIONFAC;
        } else {
            return [yaw_profile value:axstate[function]];
        }
    default:
        return axstate[function];
    }
}

- (double)getSensitivity
{
    return precisionMode ? STICK_PRECISIONFAC : 1.0;
}

- (void)setProfile:(OOJoystickAxisProfile*)profile forAxis:(int)axis
{
    switch (axis) {
    case AXIS_ROLL:
        [roll_profile release];
        roll_profile = [profile retain];
        break;

    case AXIS_PITCH:
        [pitch_profile release];
        pitch_profile = [profile retain];
        break;

    case AXIS_YAW:
        [yaw_profile release];
        yaw_profile = [profile retain];
        break;
    }
    return;
}

- (OOJoystickAxisProfile*)getProfileForAxis:(int)axis
{
    switch (axis) {
    case AXIS_ROLL:
        return roll_profile;
    case AXIS_PITCH:
        return pitch_profile;
    case AXIS_YAW:
        return yaw_profile;
    }
    return nil;
}

- (void)saveProfileForAxis:(int)axis
{
    oo::Defaults& defaults = oo::Defaults::standard();
    oo::PList::Dict dict;
    OOJoystickAxisProfile* profile;
    OOJoystickStandardAxisProfile* standard_profile;
    OOJoystickSplineAxisProfile* spline_profile;
    std::vector<NSPoint> controlPoints;
    oo::PList::Array points;
    NSPoint point;
    NSUInteger i;

    profile = [self getProfileForAxis:axis];
    if (!profile)
        return;
    dict["Deadzone"] = oo::PList([profile deadzone]);
    if ([profile isKindOfClass:[OOJoystickStandardAxisProfile class]]) {
        standard_profile = (OOJoystickStandardAxisProfile*)profile;
        dict["Type"] = oo::PList("Standard");
        dict["Power"] = oo::PList([standard_profile power]);
        dict["Parameter"] = oo::PList([standard_profile parameter]);
    } else if ([profile isKindOfClass:[OOJoystickSplineAxisProfile class]]) {
        spline_profile = (OOJoystickSplineAxisProfile*)profile;
        dict["Type"] = oo::PList("Spline");
        controlPoints = [spline_profile controlPoints];
        points.reserve(controlPoints.size());
        for (i = 0; i < controlPoints.size(); i++) {
            point = controlPoints[i];
            // +numberWithFloat: as before: single-precision reals, so the defaults file prints them
            // with %.7g (proposed ADR-0043 Amendment 2).
            points.push_back(oo::PList(oo::PList::Array {
                oo::PList::singleReal(static_cast<float>(point.x)),
                oo::PList::singleReal(static_cast<float>(point.y)) }));
        }
        dict["ControlPoints"] = oo::PList(std::move(points));
    } else {
        dict["Type"] = oo::PList("Standard");
    }
    if (axis == AXIS_ROLL) {
        defaults.setObject(std::string(STICK_ROLL_AXIS_PROFILE_SETTING), oo::PList(std::move(dict)));
    } else if (axis == AXIS_PITCH) {
        defaults.setObject(std::string(STICK_PITCH_AXIS_PROFILE_SETTING), oo::PList(std::move(dict)));
    } else if (axis == AXIS_YAW) {
        defaults.setObject(std::string(STICK_YAW_AXIS_PROFILE_SETTING), oo::PList(std::move(dict)));
    }
    return;
}

- (void)loadProfileForAxis:(int)axis
{
    oo::Defaults& defaults = oo::Defaults::standard();
    oo::PList dict;
    OOJoystickStandardAxisProfile* standard_profile;
    OOJoystickSplineAxisProfile* spline_profile;

    if (axis == AXIS_ROLL) {
        dict = defaults.object(std::string(STICK_ROLL_AXIS_PROFILE_SETTING));
    } else if (axis == AXIS_PITCH) {
        dict = defaults.object(std::string(STICK_PITCH_AXIS_PROFILE_SETTING));
    } else if (axis == AXIS_YAW) {
        dict = defaults.object(std::string(STICK_YAW_AXIS_PROFILE_SETTING));
    } else {
        return;
    }

    const oo::PList* type = dict.find("Type");
    if (type != nullptr && type->isString() && *type->getIf<std::string>() == "Standard") {
        standard_profile = [[OOJoystickStandardAxisProfile alloc] init];
        [standard_profile setDeadzone:dict.get<double>("Deadzone")];
        [standard_profile setPower:dict.get<double>("Power")];
        [standard_profile setParameter:dict.get<double>("Parameter")];
        [self setProfile:[standard_profile autorelease] forAxis:axis];
    } else if (type != nullptr && type->isString() && *type->getIf<std::string>() == "Spline") {
        spline_profile = [[OOJoystickSplineAxisProfile alloc] init];
        [spline_profile setDeadzone:dict.get<double>("Deadzone")];
        const oo::PList *points = dict.get<oo::PList::Array>("ControlPoints"), *pointArray;
        NSPoint point;
        NSUInteger i;

        for (i = 0; points != nullptr && i < points->count(); i++) {
            pointArray = points->at<oo::PList::Array>(i);
            if (pointArray != nullptr && pointArray->count() >= 2) {
                point = NSMakePoint(pointArray->at<float>(0), pointArray->at<float>(1));
                [spline_profile addControl:point];
            }
        }
        [self setProfile:[spline_profile autorelease] forAxis:axis];
    } else {
        [self setProfile:[[[OOJoystickStandardAxisProfile alloc] init] autorelease] forAxis:axis];
    }
}

- (std::vector<std::string>)listSticks
{
    NSUInteger i, stickCount = [self joystickCount];

    std::vector<std::string> stickList;
    for (i = 0; i < stickCount; i++) {
        stickList.push_back([self nameOfJoystick:i].value_or(std::string())); // a nameless stick lists as "", as before
    }
    return stickList;
}

- (oo::PList)axisFunctions
{
    int i, j;
    oo::PList::Dict fnList;

    // Add axes
    for (i = 0; i < MAX_AXES; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (axismap[j][i] >= 0) {
                oo::PList::Dict fnDict;
                fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(YES));
                fnDict[std::string(STICK_NUMBER)] = oo::PList(j);
                fnDict[std::string(STICK_AXBUT)] = oo::PList(i);
                fnList[ENUMKEY(axismap[j][i])] = oo::PList(std::move(fnDict));
            }
        }
    }
    return oo::PList(std::move(fnList));
}

- (oo::PList)buttonFunctions
{
    int i, j;
    oo::PList::Dict fnList;

    // Add buttons
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (buttonmap[j][i] >= 0) {
                oo::PList::Dict fnDict;
                fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(NO));
                fnDict[std::string(STICK_NUMBER)] = oo::PList(j);
                fnDict[std::string(STICK_AXBUT)] = oo::PList(i);
                fnList[ENUMKEY(buttonmap[j][i])] = oo::PList(std::move(fnDict));
            }
        }
    }
    return oo::PList(std::move(fnList));
}

- (oo::PList)guiButtonFunctions
{
    int i, j;
    oo::PList::Dict fnList;

    // Add buttons
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (guibuttonmap[j][i] >= 0) {
                oo::PList::Dict fnDict;
                fnDict[std::string(STICK_ISAXIS)] = oo::PList(static_cast<bool>(NO));
                fnDict[std::string(STICK_NUMBER)] = oo::PList(j);
                fnDict[std::string(STICK_AXBUT)] = oo::PList(i);
                fnList[ENUMKEY(guibuttonmap[j][i])] = oo::PList(std::move(fnDict));
            }
        }
    }
    return oo::PList(std::move(fnList));
}

- (void)setFunction:(int)function withDict:(const oo::PList&)stickFn
{
    BOOL isAxis = stickFn.get<bool>(std::string(STICK_ISAXIS)) ? YES : NO;
    int stickNum = stickFn.get<int>(std::string(STICK_NUMBER));
    int stickAxBt = stickFn.get<int>(std::string(STICK_AXBUT));

    if (isAxis) {
        [self setFunctionForAxis:stickAxBt
                        function:function
                           stick:stickNum];
    } else {
        if (function >= BUTTON_GUILEFT && function <= BUTTON_GUISELECT) 
        {
            [self setGuiFunctionForButton:stickAxBt
                          function:function
                             stick:stickNum];
        } 
        else {
            [self setFunctionForButton:stickAxBt
                          function:function
                             stick:stickNum];
        }
    }
}

- (void)setFunctionForAxis:(int)axis
                  function:(int)function
                     stick:(int)stickNum
{
    OOParameterAssert(axis < MAX_AXES && stickNum < MAX_STICKS);

    int16_t axisvalue = [self getAxisWithStick:stickNum axis:axis];
    [self unsetAxisFunction:function];
    axismap[stickNum][axis] = function;

    // initialize the throttle to what it's set to now (or else the
    // commander has to waggle the throttle to wake it up). Other axes
    // set as default.
    if (function == AXIS_THRUST) {
        axstate[function] = (float)(65536 - (axisvalue + 32768)) / 65536;
    } else {
        axstate[function] = (float)axisvalue / STICK_NORMALDIV;
    }
}

- (void)setFunctionForButton:(int)button
                    function:(int)function
                       stick:(int)stickNum
{
    OOParameterAssert(button < MAX_BUTTONS && stickNum < MAX_STICKS);

    int i, j;
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (buttonmap[j][i] == function) {
                buttonmap[j][i] = STICK_NOFUNCTION;
                break;
            }
        }
    }
    buttonmap[stickNum][button] = function;
}

- (void)setGuiFunctionForButton:(int)button
                    function:(int)function
                       stick:(int)stickNum
{
    OOParameterAssert(button < MAX_BUTTONS && stickNum < MAX_STICKS);

    int i, j;
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (guibuttonmap[j][i] == function) {
                guibuttonmap[j][i] = STICK_NOFUNCTION;
                break;
            }
        }
    }
    guibuttonmap[stickNum][button] = function;
}

- (void)unsetAxisFunction:(int)function
{
    int i, j;
    for (i = 0; i < MAX_AXES; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (axismap[j][i] == function) {
                axismap[j][i] = STICK_NOFUNCTION;
                axstate[function] = STICK_AXISUNASSIGNED;
                break;
            }
        }
    }
}

- (void)unsetButtonFunction:(int)function
{
    int i, j;
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (buttonmap[j][i] == function) {
                buttonmap[j][i] = STICK_NOFUNCTION;
                break;
            }
        }
    }
}

- (void)unsetGuiButtonFunction:(int)function
{
    int i, j;
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            if (guibuttonmap[j][i] == function) {
                guibuttonmap[j][i] = STICK_NOFUNCTION;
                break;
            }
        }
    }
}

- (void)setDefaultMapping
{
    // assign the simplest mapping: stick 0 having
    // axis 0/1 being roll/pitch and button 0 being fire, 1 being missile
    // All joysticks should at least have two axes and two buttons.
    axismap[0][0] = AXIS_ROLL;
    axismap[0][1] = AXIS_PITCH;
    buttonmap[0][0] = BUTTON_FIRE;
    buttonmap[0][1] = BUTTON_LAUNCHMISSILE;
}

- (void)clearMappings
{
    memset(axismap, STICK_NOFUNCTION, sizeof axismap);
    memset(buttonmap, STICK_NOFUNCTION, sizeof buttonmap);
}

- (void)clearStickStates
{
    int i, j;
    for (i = 0; i < AXIS_end; i++) {
        axstate[i] = STICK_AXISUNASSIGNED;
    }
    for (i = 0; i < BUTTON_end; i++) {
        butstate[i] = 0;
    }
    for (i = 0; i < MAX_BUTTONS; i++) {
        for (j = 0; j < MAX_STICKS; j++) {
            true_butstate[j][i] = NO;
        }
    }
}

- (void)clearStickButtonState:(int)stickButton
{
    if (stickButton >= 0 && stickButton < BUTTON_end) {
        butstate[stickButton] = 0;
    }
}

- (void)setCallback:(SEL)selector
             object:(id)obj
           hardware:(char)hwflags
{
    cbObject = obj;
    cbSelector = selector;
    cbHardware = hwflags;
}

- (void)clearCallback
{
    cbObject = nil;
    cbHardware = 0;
}

- (void)saveStickSettings
{
    oo::Defaults& defaults = oo::Defaults::standard();

    defaults.setObject(std::string(AXIS_SETTINGS), [self axisFunctions]);
    defaults.setObject(std::string(BUTTON_SETTINGS), [self buttonFunctions]);
    defaults.setObject(std::string(GUI_BUTTON_SETTINGS), [self guiButtonFunctions]);
    [self saveProfileForAxis:AXIS_ROLL];
    [self saveProfileForAxis:AXIS_PITCH];
    [self saveProfileForAxis:AXIS_YAW];
    defaults.synchronize();
}

- (void)loadStickSettings
{
    [self clearMappings];
    oo::Defaults& defaults = oo::Defaults::standard();
    const oo::PList axisSettings = defaults.object(std::string(AXIS_SETTINGS));
    const oo::PList buttonSettings = defaults.object(std::string(BUTTON_SETTINGS));
    const oo::PList guiButtonSettings = defaults.object(std::string(GUI_BUTTON_SETTINGS));
    // Keys are visited in byte order (they came in hash order): where two settings claim the
    // same stick axis or button, the last one still wins (proposed ADR-0043).
    if (axisSettings) {
        if (const oo::PList::Dict* settings = axisSettings.getIf<oo::PList::Dict>()) {
            for (const auto& [key, stickFn] : *settings) {
                [self setFunction:oo::str::intValue(key)
                         withDict:stickFn];
            }
        }
    }
    if (buttonSettings) {
        if (const oo::PList::Dict* settings = buttonSettings.getIf<oo::PList::Dict>()) {
            for (const auto& [key, stickFn] : *settings) {
                [self setFunction:oo::str::intValue(key)
                         withDict:stickFn];
            }
        }
    } else {
        // Nothing to load - set useful defaults
        [self setDefaultMapping];
    }
    if (guiButtonSettings) {
        if (const oo::PList::Dict* settings = guiButtonSettings.getIf<oo::PList::Dict>()) {
            for (const auto& [key, stickFn] : *settings) {
                [self setFunction:oo::str::intValue(key)
                         withDict:stickFn];
            }
        }
    }
    [self loadProfileForAxis:AXIS_ROLL];
    [self loadProfileForAxis:AXIS_PITCH];
    [self loadProfileForAxis:AXIS_YAW];
}

// These get overidden by subclasses
- (NSUInteger)joystickCount
{
    return 0;
}

- (std::optional<std::string>)nameOfJoystick:(NSUInteger)stickNumber
{
    return std::string("Dummy joystick");
}

- (int16_t)getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
    return 0;
}

@end
