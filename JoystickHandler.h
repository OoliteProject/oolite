//
// JoystickHandler.h
//
// Created for the Oolite-Linux project
//
// Dylan Smith, 2005-09-23
//
// JoystickHandler handles joystick events from SDL, and translates them
// into the appropriate action via a lookup table. The lookup table is
// stored as a simple array rather than an ObjC dictionary since this
// will be examined fairly often (once per frame during gameplay). 
//
// Conversion methods are provided to convert between the internal
// representation and an NSDictionary (for loading/saving user defaults
// and for use in areas where portability/ease of coding are more important
// than performance such as the GUI)
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//

// Enums are used here rather than a more complex ObjC object because
// these are required very frequently (once per frame) so must be light
// on CPU cycles (try and avoid too many objc sendmsgs).
// Controls that can be an axis
enum {
  AXIS_ROLL,
  AXIS_PITCH,
  AXIS_PRECISION,
  AXIS_THRUST,
  AXIS_VIEW,
  AXIS_end
} axfn;

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
  BUTTON_DOCKCPUTARGET,
  BUTTON_FUELINJECT,
  BUTTON_HYPERSPEED,
  BUTTON_HYPERDRIVE,
  BUTTON_GALACTICDRIVE,
  BUTTON_FIRE,
  BUTTON_ARMMISSILE,
  BUTTON_LAUNCHMISSILE,
  BUTTON_UNARM,
  BUTTON_CYCLEMISSILE,
  BUTTON_ENERGYBOMB,
  BUTTON_ID,
  BUTTON_ECM,
  BUTTON_ESCAPE,
  BUTTON_CLOAK,
  BUTTON_PRECISION,
  BUTTON_end
} butfn;

// Stick constants
#define MAX_STICKS 2
#define STICK_NOFUNCTION -1

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

#import <Foundation/Foundation.h>
#import <SDL/SDL.h>

@interface JoystickHandler : NSObject
{
   @protected

      // Axis/button mapping arrays
      int axismap[MAX_STICKS][AXIS_end];
      int buttonmap[MAX_STICKS][BUTTON_end];
      double axstate[AXIS_end];
      BOOL butstate[BUTTON_end];
      SDL_Joystick *stick[MAX_STICKS];
      double precision;
      int numSticks;

      // Handle callbacks - the object, selector to call
      // the desired function, and the hardware (axis or button etc.)
      id cbObject;
      SEL cbSelector;
      int cbFunc;
      char cbHardware;
}

// General.
// Note: handleSDLEvent returns a BOOL (YES we handled it or NO we
// didn't) so in the future when more handler classes are written,
// the GameView event loop can just go through an NSArray of handlers
// until it finds a handler that handles the event.
- (id) init;
- (BOOL) handleSDLEvent: (SDL_Event *)evt;

// Roll/pitch axis
- (NSPoint) getRollPitchAxis;
- (double) getPrecision;

// Setting button and axis functions
- (void) setFunctionForAxis: (int)axis 
                   function: (int)function 
                      stick: (int)stickNum;
- (void) setFunctionForButton: (int)button 
                     function: (int)function
                        stick: (int)stickNum;
// convert a dictionary into the internal function map
- (void) setFunction: (int)function withDict: (NSDictionary *)stickFn;

// Accessors and discovery about the hardware.
// These work directly on the internal lookup table so to be fast
// since they are likely to be called by the game loop.
- (int) getNumSticks;
- (BOOL) getButtonState: (int)function;

// Hardware introspection.
- (NSArray *)listSticks;

// These use NSDictionary/NSArray since they are used outside the game
// loop and are needed for loading/saving defaults.
- (NSDictionary *)getAxisFunctions;
- (NSDictionary *)getButtonFunctions;

// Set a callback for the next moved axis/pressed button. hwflags
// is in the form HW_AXIS | HW_BUTTON (or just one of).
- (void)setCallback: (SEL)selector 
             object: (id)obj 
           hardware: (char)hwflags;
- (void)clearCallback;           

// Methods generally only used by this class.
- (void) setDefaultMapping;
- (void) clearMappings;
- (void) clearStickStates;
- (void) decodeAxisEvent: (SDL_JoyAxisEvent *)evt;
- (void) decodeButtonEvent: (SDL_JoyButtonEvent *)evt;
- (void) saveStickSettings;
- (void) loadStickSettings;

@end
