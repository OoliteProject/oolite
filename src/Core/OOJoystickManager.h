/*

OOJoystickManager.h
By Dylan Smith
modified by Alex Smith and Jens Ayton

JoystickHandler handles joystick events from SDL, and translates them
into the appropriate action via a lookup table. The lookup table is
stored as a simple array rather than an ObjC dictionary since this
will be examined fairly often (once per frame during gameplay).

Conversion methods are provided to convert between the internal
representation and an NSDictionary (for loading/saving user defaults
and for use in areas where portability/ease of coding are more important
than performance such as the GUI)


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

#import "OOCocoa.h"


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
	AXIS_end
};

// Controls that can be a button
enum {
	BUTTON_INCTHRUST,
	BUTTON_DECTHRUST,
	BUTTON_SCANNERZOOM,
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
	BUTTON_ENERGYBOMB,
	BUTTON_WEAPONSONLINETOGGLE,
	BUTTON_ID,
	BUTTON_ECM,
	BUTTON_ESCAPE,
	BUTTON_CLOAK,
	BUTTON_PRECISION,
	BUTTON_VIEWFORWARD,
	BUTTON_VIEWAFT,
	BUTTON_VIEWPORT,
	BUTTON_VIEWSTARBOARD,
	BUTTON_SNAPSHOT,
	BUTTON_PREVTARGET,
	BUTTON_NEXTTARGET,
	BUTTON_end
};

// Stick constants
#define MAX_STICKS 2
#define MAX_AXES  16
#define MAX_REAL_BUTTONS  64
#define MAX_HATS  4
#define MAX_BUTTONS (MAX_REAL_BUTTONS + 4 * MAX_HATS)
#define STICK_NOFUNCTION -1
#define STICK_AXISUNASSIGNED -10.0

// Nonlinear options:
// 0: normal gameplay
// 1: regular normal mode, nonlinear precision mode
// 2: nonlinear normal mode, regular precision mode
// 3: nonlinear both modes, with cubic transform for normal, quintic transform for precision
#define STICK_NONLINEAR_OPTION 1
#define STICK_PRECISIONFAC 3
//STICK_NONLINEAR1 needs to be a double between 0 and 1
#define STICK_NONLINEAR1 0.2
#define STICK_NONLINEAR2 (1.0-STICK_NONLINEAR1)
#define STICK_NORMALDIV 32768
#define STICK_PRECISIONDIV (STICK_PRECISIONFAC*STICK_NORMALDIV)

#if OOLITE_MAC_OS_X
#define STICK_DEADZONE	0.0025
#else
#define STICK_DEADZONE	0.05
#endif

// Kind of stick device (these are bits - if any more are added,
// the next one is 4 and so on).
#define HW_AXIS 1
#define HW_BUTTON 2

// The threshold at which an axis can trigger a call back.
// The max of abs(axis) is 32767.
#define AXCBTHRESH 20000

// Dictionary keys - used in the defaults file
#define AXIS_SETTINGS @"JoystickAxes"  // NSUserDefaults
#define BUTTON_SETTINGS @"JoystickButs" // NSUserDefaults
#define STICK_ISAXIS @"isAxis"      // YES=axis NO=button
#define STICK_NUMBER @"stickNum"    // Stick number 0 to 4
#define STICK_AXBUT  @"stickAxBt"   // Axis or button number
#define STICK_FUNCTION @"stickFunc" // Function of axis/button
// shortcut to make code more readable when using enum as key for
// an NSDictionary
#define ENUMKEY(x) [NSString stringWithFormat: @"%d", x]



//SDL Abstracted constants

#if OOLITE_SDL

#import <SDL.h>

enum
{
	JOYAXISMOTION		= SDL_JOYAXISMOTION,
	JOYBUTTONDOWN		= SDL_JOYBUTTONDOWN,
	JOYBUTTONUP			= SDL_JOYBUTTONUP,
	JOYBUTTON_PRESSED	= SDL_PRESSED,
	JOYBUTTON_RELEASED	= SDL_RELEASED,
	JOYHAT_MOTION		= SDL_JOYHATMOTION,

	JOYHAT_CENTERED		= SDL_HAT_CENTERED,
	JOYHAT_UP			= SDL_HAT_UP,
	JOYHAT_RIGHT		= SDL_HAT_RIGHT,
	JOYHAT_DOWN			= SDL_HAT_DOWN,
	JOYHAT_LEFT			= SDL_HAT_LEFT,
	JOYHAT_RIGHTUP		= SDL_HAT_RIGHTUP,
	JOYHAT_RIGHTDOWN	= SDL_HAT_RIGHTDOWN,
	JOYHAT_LEFTUP		= SDL_HAT_LEFTUP,
	JOYHAT_LEFTDOWN		= SDL_HAT_LEFTDOWN,
};

typedef SDL_JoyButtonEvent JoyButtonEvent;
typedef SDL_JoyAxisEvent JoyAxisEvent;
typedef SDL_JoyHatEvent JoyHatEvent;

#else

enum
{
	JOYAXISMOTION,
	JOYBUTTONDOWN,
	JOYBUTTONUP,
	JOYBUTTON_PRESSED,
	JOYBUTTON_RELEASED,
	JOYHAT_MOTION,
	
	JOYHAT_CENTERED		= 0x00,
	JOYHAT_UP			= 0x01,
	JOYHAT_RIGHT		= 0x02,
	JOYHAT_DOWN			= 0x04,
	JOYHAT_LEFT			= 0x08,
	JOYHAT_RIGHTUP		= (JOYHAT_RIGHT|JOYHAT_UP),
	JOYHAT_RIGHTDOWN	= (JOYHAT_RIGHT|JOYHAT_DOWN),
	JOYHAT_LEFTUP		= (JOYHAT_LEFT|JOYHAT_UP),
	JOYHAT_LEFTDOWN		= (JOYHAT_LEFT|JOYHAT_DOWN),
};

// Abstracted SDL event types
typedef struct
{
	uint32_t		type;
	uint8_t			which;
	uint8_t			axis;
	int				value;
} JoyAxisEvent;

typedef struct
{
	uint32_t		type;
	uint8_t			which;
	uint8_t			button;
	int				state;
	
} JoyButtonEvent;

typedef struct
{
	uint32_t		type;
	uint8_t			which;
	uint8_t			hat;
	uint8_t			value; 
	uint8_t			padding;	
} JoyHatEvent;

#endif //OOLITE_SDL


@interface OOJoystickManager: NSObject 
{
@private
	// Axis/button mapping arrays
	int8_t		axismap[MAX_STICKS][MAX_AXES];
	int8_t		buttonmap[MAX_STICKS][MAX_BUTTONS];
	double		axstate[AXIS_end];
	BOOL		butstate[BUTTON_end];
	uint8_t		hatstate[MAX_STICKS][MAX_HATS];
	BOOL		precisionMode;
	
	// Handle callbacks - the object, selector to call
	// the desired function, and the hardware (axis or button etc.)
	id			cbObject;
	SEL			cbSelector;
	char		cbHardware;
	BOOL		invertPitch;
	double		deadzone;
}

+ (id) sharedStickHandler;
+ (BOOL) setStickHandlerClass:(Class)aClass;

// General.
// Note: handleSDLEvent returns a BOOL (YES we handled it or NO we
// didn't) so in the future when more handler classes are written,
// the GameView event loop can just go through an NSArray of handlers
// until it finds a handler that handles the event.
- (id) init;

// Roll/pitch axis
- (NSPoint) rollPitchAxis;

// View axis
- (NSPoint) viewAxis;

// convert a dictionary into the internal function map
- (void) setFunction:(int)function withDict: (NSDictionary *)stickFn;
- (void) unsetAxisFunction:(int)function;
- (void) unsetButtonFunction:(int)function;

// Accessors and discovery about the hardware.
// These work directly on the internal lookup table so to be fast
// since they are likely to be called by the game loop.
- (NSUInteger) joystickCount;
- (BOOL) getButtonState:(int)function;
- (double) getAxisState:(int)function;
- (double) getSensitivity;
- (double) deadZone;
- (void) setDeadZone: (double)newValue;

// Transform raw axis state into actual axis state
- (double) axisTransform: (double)axisvalue;

// This one just returns a pointer to the entire state array to
// allow for multiple lookups with only one objc_sendMsg
- (const BOOL *) getAllButtonStates;

// Hardware introspection.
- (NSArray *) listSticks;

// These use NSDictionary/NSArray since they are used outside the game
// loop and are needed for loading/saving defaults.
- (NSDictionary *) axisFunctions;
- (NSDictionary *) buttonFunctions;

// Set a callback for the next moved axis/pressed button. hwflags
// is in the form HW_AXIS | HW_BUTTON (or just one of).
- (void)setCallback:(SEL)selector
             object:(id)obj
           hardware:(char)hwflags;
- (void)clearCallback;

// Methods generally only used by this class.
- (void) setDefaultMapping;
- (void) clearMappings;
- (void) clearStickStates;
- (void) clearStickButtonState: (int)stickButton;
- (void) decodeAxisEvent: (JoyAxisEvent *)evt;
- (void) decodeButtonEvent: (JoyButtonEvent *)evt;
- (void) decodeHatEvent: (JoyHatEvent *)evt;
- (void) saveStickSettings;
- (void) loadStickSettings;


//Methods that should be overridden by all subclasses
- (NSString *) nameOfJoystick:(NSUInteger)stickNumber;
- (int16_t) getAxisWithStick:(NSUInteger) stickNum axis:(NSUInteger)axisNum;

@end
