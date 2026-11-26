/*

OOJoystickManager.h
By Dylan Smith
modified by Alex Smith and Jens Ayton

JoystickHandler handles joystick events, and translates them
into the appropriate action via a lookup table. The lookup table is
stored as a simple array rather than an ObjC dictionary since this
will be examined fairly often (once per frame during gameplay).

Conversion methods are provided to convert between the internal
representation and a property-list dictionary (for loading/saving user defaults
and for use in areas where portability/ease of coding are more important
than performance such as the GUI)

C++20 since bead oo-6bux (proposed ADR-0056, Amendment 1 of bead oo-cwz: a hierarchy root). The
methods a subclass overrides (joystickCount, nameOfJoystick, getAxisWithStick) are virtual;
-init's body is init(), run after construction because it reaches those virtual members. Since
the Objective-C facades were deleted the class is global, its one subclass is the C++
OOSDLJoystickManager, the shared handler is made by a registered factory function (was
+setStickHandlerClass:) and the stick-mapper callback is a C++ function (was a selector and an
object). The event decoders are the SDL manager's (upstream #742): they read and set this
class's protected state.


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

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"
#include <functional>
#include <string_view>

// Enums are used here rather than a more complex ObjC object because
// these are required very frequently (once per frame) so must be light
// on CPU cycles (try and avoid too many objc sendmsgs).
// Controls that can be an axis
enum {
    AXIS_ROLL,
    AXIS_PITCH,
    AXIS_YAW,
    AXIS_PRECISION,
    AXIS_THRUST,
    AXIS_VIEWX,
    AXIS_VIEWY,
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    AXIS_FIELD_OF_VIEW,
#endif
    AXIS_end
};

// Controls that can be a button
enum {
    BUTTON_INCTHRUST,
    BUTTON_DECTHRUST,
    BUTTON_SCANNERZOOM,
    BUTTON_SCANNERUNZOOM,
    BUTTON_JETTISON,
    BUTTON_COMPASSMODE,
    BUTTON_COMMSLOG,
    BUTTON_DOCKCPU,
    BUTTON_DOCKCPUFAST,
    BUTTON_FUELINJECT,
    BUTTON_HYPERSPEED,
    BUTTON_HYPERDRIVE,
    BUTTON_GALACTICDRIVE,
    BUTTON_FIRE,
    BUTTON_ARMMISSILE,
    BUTTON_LAUNCHMISSILE,
    BUTTON_PRIMEEQUIPMENT,
    BUTTON_ACTIVATEEQUIPMENT,
    BUTTON_UNARM,
    BUTTON_TARGETINCOMINGMISSILE,
    BUTTON_CYCLEMISSILE,
    BUTTON_ENERGYBOMB, // now fast activate B
    BUTTON_WEAPONSONLINETOGGLE,
    BUTTON_ID,
    BUTTON_ECM,
    BUTTON_ESCAPE,
    BUTTON_CLOAK, // now fast activate A
    BUTTON_PRECISION,
    BUTTON_VIEWFORWARD,
    BUTTON_VIEWAFT,
    BUTTON_VIEWPORT,
    BUTTON_VIEWSTARBOARD,
    BUTTON_SNAPSHOT,
    BUTTON_PREVTARGET,
    BUTTON_NEXTTARGET,
    BUTTON_MODEEQUIPMENT,
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    BUTTON_INC_FIELD_OF_VIEW,
    BUTTON_DEC_FIELD_OF_VIEW,
#endif
    BUTTON_DOCKINGCLEARANCE,
    BUTTON_COMPASSMODE_PREV,
    BUTTON_PRIMEEQUIPMENT_PREV,
    BUTTON_ROTATECARGO,
    BUTTON_MFDSELECTNEXT,
    BUTTON_MFDSELECTPREV,
    BUTTON_MFDCYCLENEXT,
    BUTTON_MFDCYCLEPREV,
    BUTTON_EXTVIEWCYCLE,
    BUTTON_DOCKINGMUSIC,
    BUTTON_PAUSE,
    BUTTON_TOGGLEHUD,
    BUTTON_GUILEFT,
    BUTTON_GUIRIGHT,
    BUTTON_GUIUP,
    BUTTON_GUIDOWN,
    BUTTON_GUIPAGEUP,
    BUTTON_GUIPAGEDOWN,
    BUTTON_GUISELECT,
    BUTTON_end
};

// Stick constants
#define MAX_STICKS 4
#define MAX_AXES 16
#define MAX_REAL_BUTTONS 64
#define MAX_HATS 4
#define MAX_BUTTONS (MAX_REAL_BUTTONS + 4 * MAX_HATS)
#define STICK_NOFUNCTION -1
#define STICK_AXISUNASSIGNED -10.0

#define STICK_PRECISIONFAC 3
#define STICK_NORMALDIV 32768
#define STICK_PRECISIONDIV (STICK_PRECISIONFAC * STICK_NORMALDIV)

#define STICK_DEADZONE 0.05

#define STICK_MAX_DEADZONE (STICK_DEADZONE * 2)

// Kind of stick device (these are bits - if any more are added,
// the next one is 4 and so on).
#define HW_AXIS 1
#define HW_BUTTON 2

// The threshold at which an axis can trigger a call back.
// The max of abs(axis) is 32767.
#define AXCBTHRESH 20000

// Dictionary keys - used in the defaults file
inline constexpr std::string_view AXIS_SETTINGS = "JoystickAxes"; // oo::Defaults key
inline constexpr std::string_view BUTTON_SETTINGS = "JoystickButs"; // oo::Defaults key
inline constexpr std::string_view GUI_BUTTON_SETTINGS = "GuiJoystickButs"; // oo::Defaults key
inline constexpr std::string_view STICK_ISAXIS = "isAxis"; // YES=axis NO=button
inline constexpr std::string_view STICK_NUMBER = "stickNum"; // Stick number 0 to 4
inline constexpr std::string_view STICK_AXBUT = "stickAxBt"; // Axis or button number
#define STICK_FUNCTION @"stickFunc" // Function of axis/button
inline constexpr std::string_view STICK_ROLL_AXIS_PROFILE_SETTING = "RollAxisProfile"; // Joystick Profiles
inline constexpr std::string_view STICK_PITCH_AXIS_PROFILE_SETTING = "PitchAxisProfile"; // Joystick Profiles
inline constexpr std::string_view STICK_YAW_AXIS_PROFILE_SETTING = "YawAxisProfile"; // Joystick Profiles
// shortcut to make code more readable when using enum as key for
// a dictionary: a std::string (oofnd/String.hpp)
#define ENUMKEY(x) oo::str::format("%d", x)

#import "OOJoystickProfile.h"
#include "oofnd/String.hpp"

class OOJoystickManager : public oo::RefCounted {
public:
    OOJoystickManager() = default;

    // The shared handler, made on first use by the registered factory (else a plain manager) and
    // init()ed; never null, never destroyed. Was +sharedStickHandler.
    static OOJoystickManager* sharedStickHandler();
    // Registers the platform's handler, before the first sharedStickHandler(). Was
    // +setStickHandlerClass: (the class is a function that makes the manager).
    using StickHandlerFactory = oo::Ref<OOJoystickManager> (*)();
    static bool setStickHandlerFactory(StickHandlerFactory factory);

    // General.
    // Note: handleSDLEvent returns a BOOL (YES we handled it or NO we
    // didn't) so in the future when more handler classes are written,
    // the GameView event loop can just go through an array of handlers
    // until it finds a handler that handles the event.
    void init(); // -init's body; the facade (or whoever makes the manager) runs it once, right after construction

    // Roll/pitch axis
    NSPoint rollPitchAxis();

    // View axis
    NSPoint viewAxis();

    // convert a dictionary into the internal function map
    void setFunction(int function, const oo::PList& stickFn);
    void unsetAxisFunction(int function);
    void unsetButtonFunction(int function);
    void unsetGuiButtonFunction(int function);

    // Accessors and discovery about the hardware.
    // These work directly on the internal lookup table so to be fast
    // since they are likely to be called by the game loop.
    bool isButtonDown(int button, int stickNum);
    bool getButtonState(int function);
    double getAxisState(int function);
    double getSensitivity();

    // Axis profile handling
    void setProfile(OOJoystickAxisProfile* profile, int axis);
    OOJoystickAxisProfile* getProfileForAxis(int axis); // borrowed; null for an axis with none
    void saveProfileForAxis(int axis);
    void loadProfileForAxis(int axis);

    // This one just returns a pointer to the entire state array to
    // allow for multiple lookups with only one objc_sendMsg
    const BOOL* getAllButtonStates();

    // Hardware introspection.
    std::vector<std::string> listSticks();

    // These use property-list dictionaries since they are used outside the game
    // loop and are needed for loading/saving defaults.
    oo::PList axisFunctions();
    oo::PList buttonFunctions();
    oo::PList guiButtonFunctions();

    // Set a callback for the next moved axis/pressed button. hwflags
    // is in the form HW_AXIS | HW_BUTTON (or just one of). The callback is called once, with the
    // stick function's dictionary (was a selector called by name on an object).
    using StickCallback = std::function<void(const oo::PList&)>;
    void setCallback(StickCallback callback, char hwflags);
    void clearCallback();

    // Methods generally only used by this class.
    void setDefaultMapping();
    void clearMappings();
    void clearStickStates();
    void clearStickButtonState(int stickButton);
    void saveStickSettings();
    void loadStickSettings();

    // Methods that should be overridden by all subclasses
    virtual NSUInteger joystickCount();
    virtual std::optional<std::string> nameOfJoystick(NSUInteger stickNumber); // nullopt: the device has no name
    virtual int16_t getAxisWithStick(NSUInteger stickNum, NSUInteger axisNum);

private:
    // Setting button and axis functions
    void setFunctionForAxis(int axis, int function, int stickNum);
    void setFunctionForButton(int button, int function, int stickNum);
    void setGuiFunctionForButton(int button, int function, int stickNum);

protected:
    // Axis/button mapping arrays (the platform manager's event decoders read
    // and set them, as the Objective-C ivars were)
    int8_t axismap[MAX_STICKS][MAX_AXES] = { };
    int8_t buttonmap[MAX_STICKS][MAX_BUTTONS] = { };
    int8_t guibuttonmap[MAX_STICKS][MAX_BUTTONS] = { };
    bool true_butstate[MAX_STICKS][MAX_BUTTONS] = { };
    double axstate[AXIS_end] = { };
    BOOL butstate[BUTTON_end] = { }; // still BOOL: getAllButtonStates() hands unconverted callers a const BOOL *
    uint8_t hatstate[MAX_STICKS][MAX_HATS] = { };
    bool precisionMode = { };

    // Handle callbacks - the function to call
    // and the hardware (axis or button etc.)
    StickCallback cbCallback = { }; // empty: none (was a nil object)
    char cbHardware = { };
    bool invertPitch = { };

private:
    oo::Ref<OOJoystickAxisProfile> roll_profile = { };
    oo::Ref<OOJoystickAxisProfile> pitch_profile = { };
    oo::Ref<OOJoystickAxisProfile> yaw_profile = { };
};
