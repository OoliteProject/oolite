/*

OOJoystickManager.h
By Dylan Smith
modified by Alex Smith and Jens Ayton

JoystickHandler handles joystick events, and translates them
into the appropriate action via a lookup table. The lookup table is
stored as a simple array rather than a dictionary since this
will be examined fairly often (once per frame during gameplay).

Conversion methods are provided to convert between the internal
representation and a property-list dictionary (for loading/saving user defaults
and for use in areas where portability/ease of coding are more important
than performance such as the GUI)

The methods a subclass overrides (joystickCount, nameOfJoystick,
getAxisWithStick) are virtual; -init's body is init(), run after construction
because it reaches those virtual members. Its one subclass is the C++
OOSDLJoystickManager, the shared handler is made by a registered factory
function (was +setStickHandlerClass:) and the stick-mapper callback is a C++
function.


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
#include <array>
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

#include "OOFoundation.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"

// Plain numbers are used here rather than a more complex object because
// these are required very frequently (once per frame) so must be light
// on CPU cycles.
// Controls that can be an axis
inline constexpr int AXIS_ROLL = 0;
inline constexpr int AXIS_PITCH = AXIS_ROLL + 1;
inline constexpr int AXIS_YAW = AXIS_PITCH + 1;
inline constexpr int AXIS_PRECISION = AXIS_YAW + 1;
inline constexpr int AXIS_THRUST = AXIS_PRECISION + 1;
inline constexpr int AXIS_VIEWX = AXIS_THRUST + 1;
inline constexpr int AXIS_VIEWY = AXIS_VIEWX + 1;
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
inline constexpr int AXIS_FIELD_OF_VIEW = AXIS_VIEWY + 1;
inline constexpr int AXIS_end = AXIS_FIELD_OF_VIEW + 1;
#else
inline constexpr int AXIS_end = AXIS_VIEWY + 1;
#endif
// The numbers are the keys of the stick mappings saved in the defaults
// (ENUMKEY), pinned in both configurations.
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
static_assert(AXIS_ROLL == 0);
static_assert(AXIS_PITCH == 1);
static_assert(AXIS_YAW == 2);
static_assert(AXIS_PRECISION == 3);
static_assert(AXIS_THRUST == 4);
static_assert(AXIS_VIEWX == 5);
static_assert(AXIS_VIEWY == 6);
static_assert(AXIS_FIELD_OF_VIEW == 7);
static_assert(AXIS_end == 8);
#else
static_assert(AXIS_ROLL == 0);
static_assert(AXIS_PITCH == 1);
static_assert(AXIS_YAW == 2);
static_assert(AXIS_PRECISION == 3);
static_assert(AXIS_THRUST == 4);
static_assert(AXIS_VIEWX == 5);
static_assert(AXIS_VIEWY == 6);
static_assert(AXIS_end == 7);
#endif

// Controls that can be a button
inline constexpr int BUTTON_INCTHRUST = 0;
inline constexpr int BUTTON_DECTHRUST = BUTTON_INCTHRUST + 1;
inline constexpr int BUTTON_SCANNERZOOM = BUTTON_DECTHRUST + 1;
inline constexpr int BUTTON_SCANNERUNZOOM = BUTTON_SCANNERZOOM + 1;
inline constexpr int BUTTON_JETTISON = BUTTON_SCANNERUNZOOM + 1;
inline constexpr int BUTTON_COMPASSMODE = BUTTON_JETTISON + 1;
inline constexpr int BUTTON_COMMSLOG = BUTTON_COMPASSMODE + 1;
inline constexpr int BUTTON_DOCKCPU = BUTTON_COMMSLOG + 1;
inline constexpr int BUTTON_DOCKCPUFAST = BUTTON_DOCKCPU + 1;
inline constexpr int BUTTON_FUELINJECT = BUTTON_DOCKCPUFAST + 1;
inline constexpr int BUTTON_HYPERSPEED = BUTTON_FUELINJECT + 1;
inline constexpr int BUTTON_HYPERDRIVE = BUTTON_HYPERSPEED + 1;
inline constexpr int BUTTON_GALACTICDRIVE = BUTTON_HYPERDRIVE + 1;
inline constexpr int BUTTON_FIRE = BUTTON_GALACTICDRIVE + 1;
inline constexpr int BUTTON_ARMMISSILE = BUTTON_FIRE + 1;
inline constexpr int BUTTON_LAUNCHMISSILE = BUTTON_ARMMISSILE + 1;
inline constexpr int BUTTON_PRIMEEQUIPMENT = BUTTON_LAUNCHMISSILE + 1;
inline constexpr int BUTTON_ACTIVATEEQUIPMENT = BUTTON_PRIMEEQUIPMENT + 1;
inline constexpr int BUTTON_UNARM = BUTTON_ACTIVATEEQUIPMENT + 1;
inline constexpr int BUTTON_TARGETINCOMINGMISSILE = BUTTON_UNARM + 1;
inline constexpr int BUTTON_CYCLEMISSILE = BUTTON_TARGETINCOMINGMISSILE + 1;
inline constexpr int BUTTON_ENERGYBOMB =
    BUTTON_CYCLEMISSILE + 1;  // now fast activate B
inline constexpr int BUTTON_WEAPONSONLINETOGGLE = BUTTON_ENERGYBOMB + 1;
inline constexpr int BUTTON_ID = BUTTON_WEAPONSONLINETOGGLE + 1;
inline constexpr int BUTTON_ECM = BUTTON_ID + 1;
inline constexpr int BUTTON_ESCAPE = BUTTON_ECM + 1;
inline constexpr int BUTTON_CLOAK = BUTTON_ESCAPE + 1;  // now fast activate A
inline constexpr int BUTTON_PRECISION = BUTTON_CLOAK + 1;
inline constexpr int BUTTON_VIEWFORWARD = BUTTON_PRECISION + 1;
inline constexpr int BUTTON_VIEWAFT = BUTTON_VIEWFORWARD + 1;
inline constexpr int BUTTON_VIEWPORT = BUTTON_VIEWAFT + 1;
inline constexpr int BUTTON_VIEWSTARBOARD = BUTTON_VIEWPORT + 1;
inline constexpr int BUTTON_SNAPSHOT = BUTTON_VIEWSTARBOARD + 1;
inline constexpr int BUTTON_PREVTARGET = BUTTON_SNAPSHOT + 1;
inline constexpr int BUTTON_NEXTTARGET = BUTTON_PREVTARGET + 1;
inline constexpr int BUTTON_MODEEQUIPMENT = BUTTON_NEXTTARGET + 1;
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
inline constexpr int BUTTON_INC_FIELD_OF_VIEW = BUTTON_MODEEQUIPMENT + 1;
inline constexpr int BUTTON_DEC_FIELD_OF_VIEW = BUTTON_INC_FIELD_OF_VIEW + 1;
inline constexpr int BUTTON_DOCKINGCLEARANCE = BUTTON_DEC_FIELD_OF_VIEW + 1;
#else
inline constexpr int BUTTON_DOCKINGCLEARANCE = BUTTON_MODEEQUIPMENT + 1;
#endif
inline constexpr int BUTTON_COMPASSMODE_PREV = BUTTON_DOCKINGCLEARANCE + 1;
inline constexpr int BUTTON_PRIMEEQUIPMENT_PREV = BUTTON_COMPASSMODE_PREV + 1;
inline constexpr int BUTTON_ROTATECARGO = BUTTON_PRIMEEQUIPMENT_PREV + 1;
inline constexpr int BUTTON_MFDSELECTNEXT = BUTTON_ROTATECARGO + 1;
inline constexpr int BUTTON_MFDSELECTPREV = BUTTON_MFDSELECTNEXT + 1;
inline constexpr int BUTTON_MFDCYCLENEXT = BUTTON_MFDSELECTPREV + 1;
inline constexpr int BUTTON_MFDCYCLEPREV = BUTTON_MFDCYCLENEXT + 1;
inline constexpr int BUTTON_EXTVIEWCYCLE = BUTTON_MFDCYCLEPREV + 1;
inline constexpr int BUTTON_DOCKINGMUSIC = BUTTON_EXTVIEWCYCLE + 1;
inline constexpr int BUTTON_PAUSE = BUTTON_DOCKINGMUSIC + 1;
inline constexpr int BUTTON_TOGGLEHUD = BUTTON_PAUSE + 1;
inline constexpr int BUTTON_GUILEFT = BUTTON_TOGGLEHUD + 1;
inline constexpr int BUTTON_GUIRIGHT = BUTTON_GUILEFT + 1;
inline constexpr int BUTTON_GUIUP = BUTTON_GUIRIGHT + 1;
inline constexpr int BUTTON_GUIDOWN = BUTTON_GUIUP + 1;
inline constexpr int BUTTON_GUIPAGEUP = BUTTON_GUIDOWN + 1;
inline constexpr int BUTTON_GUIPAGEDOWN = BUTTON_GUIPAGEUP + 1;
inline constexpr int BUTTON_GUISELECT = BUTTON_GUIPAGEDOWN + 1;
inline constexpr int BUTTON_end = BUTTON_GUISELECT + 1;
// The numbers are the keys of the stick mappings saved in the defaults
// (ENUMKEY), pinned in both configurations.
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
static_assert(BUTTON_INCTHRUST == 0);
static_assert(BUTTON_DECTHRUST == 1);
static_assert(BUTTON_SCANNERZOOM == 2);
static_assert(BUTTON_SCANNERUNZOOM == 3);
static_assert(BUTTON_JETTISON == 4);
static_assert(BUTTON_COMPASSMODE == 5);
static_assert(BUTTON_COMMSLOG == 6);
static_assert(BUTTON_DOCKCPU == 7);
static_assert(BUTTON_DOCKCPUFAST == 8);
static_assert(BUTTON_FUELINJECT == 9);
static_assert(BUTTON_HYPERSPEED == 10);
static_assert(BUTTON_HYPERDRIVE == 11);
static_assert(BUTTON_GALACTICDRIVE == 12);
static_assert(BUTTON_FIRE == 13);
static_assert(BUTTON_ARMMISSILE == 14);
static_assert(BUTTON_LAUNCHMISSILE == 15);
static_assert(BUTTON_PRIMEEQUIPMENT == 16);
static_assert(BUTTON_ACTIVATEEQUIPMENT == 17);
static_assert(BUTTON_UNARM == 18);
static_assert(BUTTON_TARGETINCOMINGMISSILE == 19);
static_assert(BUTTON_CYCLEMISSILE == 20);
static_assert(BUTTON_ENERGYBOMB == 21);
static_assert(BUTTON_WEAPONSONLINETOGGLE == 22);
static_assert(BUTTON_ID == 23);
static_assert(BUTTON_ECM == 24);
static_assert(BUTTON_ESCAPE == 25);
static_assert(BUTTON_CLOAK == 26);
static_assert(BUTTON_PRECISION == 27);
static_assert(BUTTON_VIEWFORWARD == 28);
static_assert(BUTTON_VIEWAFT == 29);
static_assert(BUTTON_VIEWPORT == 30);
static_assert(BUTTON_VIEWSTARBOARD == 31);
static_assert(BUTTON_SNAPSHOT == 32);
static_assert(BUTTON_PREVTARGET == 33);
static_assert(BUTTON_NEXTTARGET == 34);
static_assert(BUTTON_MODEEQUIPMENT == 35);
static_assert(BUTTON_INC_FIELD_OF_VIEW == 36);
static_assert(BUTTON_DEC_FIELD_OF_VIEW == 37);
static_assert(BUTTON_DOCKINGCLEARANCE == 38);
static_assert(BUTTON_COMPASSMODE_PREV == 39);
static_assert(BUTTON_PRIMEEQUIPMENT_PREV == 40);
static_assert(BUTTON_ROTATECARGO == 41);
static_assert(BUTTON_MFDSELECTNEXT == 42);
static_assert(BUTTON_MFDSELECTPREV == 43);
static_assert(BUTTON_MFDCYCLENEXT == 44);
static_assert(BUTTON_MFDCYCLEPREV == 45);
static_assert(BUTTON_EXTVIEWCYCLE == 46);
static_assert(BUTTON_DOCKINGMUSIC == 47);
static_assert(BUTTON_PAUSE == 48);
static_assert(BUTTON_TOGGLEHUD == 49);
static_assert(BUTTON_GUILEFT == 50);
static_assert(BUTTON_GUIRIGHT == 51);
static_assert(BUTTON_GUIUP == 52);
static_assert(BUTTON_GUIDOWN == 53);
static_assert(BUTTON_GUIPAGEUP == 54);
static_assert(BUTTON_GUIPAGEDOWN == 55);
static_assert(BUTTON_GUISELECT == 56);
static_assert(BUTTON_end == 57);
#else
static_assert(BUTTON_INCTHRUST == 0);
static_assert(BUTTON_DECTHRUST == 1);
static_assert(BUTTON_SCANNERZOOM == 2);
static_assert(BUTTON_SCANNERUNZOOM == 3);
static_assert(BUTTON_JETTISON == 4);
static_assert(BUTTON_COMPASSMODE == 5);
static_assert(BUTTON_COMMSLOG == 6);
static_assert(BUTTON_DOCKCPU == 7);
static_assert(BUTTON_DOCKCPUFAST == 8);
static_assert(BUTTON_FUELINJECT == 9);
static_assert(BUTTON_HYPERSPEED == 10);
static_assert(BUTTON_HYPERDRIVE == 11);
static_assert(BUTTON_GALACTICDRIVE == 12);
static_assert(BUTTON_FIRE == 13);
static_assert(BUTTON_ARMMISSILE == 14);
static_assert(BUTTON_LAUNCHMISSILE == 15);
static_assert(BUTTON_PRIMEEQUIPMENT == 16);
static_assert(BUTTON_ACTIVATEEQUIPMENT == 17);
static_assert(BUTTON_UNARM == 18);
static_assert(BUTTON_TARGETINCOMINGMISSILE == 19);
static_assert(BUTTON_CYCLEMISSILE == 20);
static_assert(BUTTON_ENERGYBOMB == 21);
static_assert(BUTTON_WEAPONSONLINETOGGLE == 22);
static_assert(BUTTON_ID == 23);
static_assert(BUTTON_ECM == 24);
static_assert(BUTTON_ESCAPE == 25);
static_assert(BUTTON_CLOAK == 26);
static_assert(BUTTON_PRECISION == 27);
static_assert(BUTTON_VIEWFORWARD == 28);
static_assert(BUTTON_VIEWAFT == 29);
static_assert(BUTTON_VIEWPORT == 30);
static_assert(BUTTON_VIEWSTARBOARD == 31);
static_assert(BUTTON_SNAPSHOT == 32);
static_assert(BUTTON_PREVTARGET == 33);
static_assert(BUTTON_NEXTTARGET == 34);
static_assert(BUTTON_MODEEQUIPMENT == 35);
static_assert(BUTTON_DOCKINGCLEARANCE == 36);
static_assert(BUTTON_COMPASSMODE_PREV == 37);
static_assert(BUTTON_PRIMEEQUIPMENT_PREV == 38);
static_assert(BUTTON_ROTATECARGO == 39);
static_assert(BUTTON_MFDSELECTNEXT == 40);
static_assert(BUTTON_MFDSELECTPREV == 41);
static_assert(BUTTON_MFDCYCLENEXT == 42);
static_assert(BUTTON_MFDCYCLEPREV == 43);
static_assert(BUTTON_EXTVIEWCYCLE == 44);
static_assert(BUTTON_DOCKINGMUSIC == 45);
static_assert(BUTTON_PAUSE == 46);
static_assert(BUTTON_TOGGLEHUD == 47);
static_assert(BUTTON_GUILEFT == 48);
static_assert(BUTTON_GUIRIGHT == 49);
static_assert(BUTTON_GUIUP == 50);
static_assert(BUTTON_GUIDOWN == 51);
static_assert(BUTTON_GUIPAGEUP == 52);
static_assert(BUTTON_GUIPAGEDOWN == 53);
static_assert(BUTTON_GUISELECT == 54);
static_assert(BUTTON_end == 55);
#endif

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
inline constexpr int HW_AXIS = 1;
inline constexpr int HW_BUTTON = 2;

// The threshold at which an axis can trigger a call back.
// The max of abs(axis) is 32767.
#define AXCBTHRESH 20000

// Dictionary keys - used in the defaults file
inline constexpr std::string_view AXIS_SETTINGS =
    "JoystickAxes";  // oo::Defaults key
inline constexpr std::string_view BUTTON_SETTINGS =
    "JoystickButs";  // oo::Defaults key
inline constexpr std::string_view GUI_BUTTON_SETTINGS =
    "GuiJoystickButs";  // oo::Defaults key
inline constexpr std::string_view STICK_ISAXIS =
    "isAxis";  // YES=axis NO=button
inline constexpr std::string_view STICK_NUMBER =
    "stickNum";  // Stick number 0 to 4
inline constexpr std::string_view STICK_AXBUT =
    "stickAxBt";                    // Axis or button number
#define STICK_FUNCTION "stickFunc"  // Function of axis/button
inline constexpr std::string_view STICK_ROLL_AXIS_PROFILE_SETTING =
    "RollAxisProfile";  // Joystick Profiles
inline constexpr std::string_view STICK_PITCH_AXIS_PROFILE_SETTING =
    "PitchAxisProfile";  // Joystick Profiles
inline constexpr std::string_view STICK_YAW_AXIS_PROFILE_SETTING =
    "YawAxisProfile";  // Joystick Profiles
// shortcut to make code more readable when using enum as key for
// a dictionary: a std::string (oofnd/String.hpp)
#define ENUMKEY(x) std::format("{}", static_cast<int>(x))

#include <format>

#include "OOJoystickProfile.h"
#include "oofnd/String.hpp"

class OOJoystickManager : public oo::RefCounted {
 public:
  OOJoystickManager() = default;

  // The shared handler, made on first use by the registered factory (else a
  // plain manager) and init()ed; never null, never destroyed. Was
  // +sharedStickHandler.
  static OOJoystickManager* sharedStickHandler();
  // Registers the platform's handler, before the first sharedStickHandler().
  // Was +setStickHandlerClass: (the class is a function that makes the
  // manager).
  using StickHandlerFactory = oo::Ref<OOJoystickManager> (*)();
  static bool setStickHandlerFactory(StickHandlerFactory factory);

  // General.
  // Note: handleSDLEvent returns a bool (YES we handled it or NO we
  // didn't) so in the future when more handler classes are written,
  // the GameView event loop can just go through an array of handlers
  // until it finds a handler that handles the event.
  void
  init();  // run once, right after construction, by whoever makes the manager

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
  OOJoystickAxisProfile* getProfileForAxis(
      int axis);  // borrowed; null for an axis with none
  void saveProfileForAxis(int axis);
  void loadProfileForAxis(int axis);

  // This one just returns a pointer to the entire state array to
  // allow for multiple lookups with only one call
  const bool* getAllButtonStates();

  // Hardware introspection.
  std::vector<std::string> listSticks();

  // These use property-list dictionaries since they are used outside the game
  // loop and are needed for loading/saving defaults.
  oo::PList axisFunctions();
  oo::PList buttonFunctions();
  oo::PList guiButtonFunctions();

  // Set a callback for the next moved axis/pressed button. hwflags
  // is in the form HW_AXIS | HW_BUTTON (or just one of). The callback is called
  // once, with the stick function's dictionary (was a selector called by name
  // on an object).
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
  virtual std::size_t joystickCount();
  virtual std::optional<std::string> nameOfJoystick(
      std::size_t stickNumber);  // nullopt: the device has no name
  virtual int16_t getAxisWithStick(std::size_t stickNum, std::size_t axisNum);

 private:
  // Setting button and axis functions
  void setFunctionForAxis(int axis, int function, int stickNum);
  void setFunctionForButton(int button, int function, int stickNum);
  void setGuiFunctionForButton(int button, int function, int stickNum);

 protected:
  // Axis/button mapping arrays (the platform manager's event decoders read
  // and set them)
  int8_t axismap[MAX_STICKS][MAX_AXES] = {};
  int8_t buttonmap[MAX_STICKS][MAX_BUTTONS] = {};
  int8_t guibuttonmap[MAX_STICKS][MAX_BUTTONS] = {};
  bool true_butstate[MAX_STICKS][MAX_BUTTONS] = {};
  std::array<double, AXIS_end> axstate = {};
  std::array<bool, BUTTON_end> butstate =
      {};  // still bool: getAllButtonStates() hands
           // unconverted callers a const bool *
  uint8_t hatstate[MAX_STICKS][MAX_HATS] = {};
  bool precisionMode = {};

  // Handle callbacks - the function to call
  // and the hardware (axis or button etc.)
  StickCallback cbCallback = {};  // empty: none (was a nil object)
  char cbHardware = {};
  bool invertPitch = {};

 private:
  oo::Ref<OOJoystickAxisProfile> roll_profile = {};
  oo::Ref<OOJoystickAxisProfile> pitch_profile = {};
  oo::Ref<OOJoystickAxisProfile> yaw_profile = {};
};
