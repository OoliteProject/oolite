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
// will be examined fairly often. The table is however converted to
// an NSDictionary and back so it can be saved into the user's defaults
// file.
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//

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

#define MAX_STICKS 4
#define STICK_NOFUNCTION -1
#define STICK_REPORTFUNCTION -2

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

// Accessors
- (int) getNumSticks;
- (int) getButtonState: (int)function;

// Methods generally only used by this class.
- (void) setDefaultMapping;
- (void) clearStickStates;
- (void) decodeAxisEvent: (SDL_JoyAxisEvent *)evt;
- (void) decodeButtonEvent: (SDL_JoyButtonEvent *)evt;

@end
