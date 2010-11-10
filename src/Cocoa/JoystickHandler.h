/*

JoystickHandler.h

Non-functional JoystickHandler.
This exists to reduce the amount of #ifdefs and duplicated code.


Oolite
Copyright (C) 2004-2010 Giles C Williams and contributors

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

#import <Foundation/Foundation.h>

#define STICK_AXISUNASSIGNED -10.0

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
#if TARGET_INCOMING_MISSILES
  BUTTON_TARGETINCOMINGMISSILE,
#endif
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
  BUTTON_end
} butfn;

// Stick constants
#define MAX_STICKS 4
#define MAX_AXES  16
#define MAX_REAL_BUTTONS  64
#define MAX_HATS  0
#define MAX_BUTTONS (MAX_REAL_BUTTONS + 4 * MAX_HATS)
#define STICK_NOFUNCTION -1
#define STICK_AXISUNASSIGNED -10.0
#define STICK_PRECISIONDIV 98304 // 3 times more precise
#define STICK_NORMALDIV 32768
#define STICK_PRECISIONFAC (STICK_PRECISIONDIV/STICK_NORMALDIV)
#define STICK_DEADZONE	0.05

// Kind of stick device (these are bits - if any more are added,
// the next one is 4 and so on).
#define HW_AXIS 1
#define HW_BUTTON 2

// The threshold at which an axis can trigger a call back.
// The max of abs(axis) is 32767.
#define AXCBTHRESH 20000

// Dictionary keys - used in the defaults file
#define AXIS_SETTINGS @"JoystickAxes"	// NSUserDefaults
#define BUTTON_SETTINGS @"JoystickButs"	// NSUserDefaults
#define STICK_ISAXIS @"isAxis"			// YES=axis NO=button
#define STICK_NUMBER @"stickNum"		// Stick number 0 to 4
#define STICK_AXBUT  @"stickAxBt"		// Axis or button number
#define STICK_FUNCTION @"stickFunc"		// Function of axis/button


@interface JoystickHandler: NSObject
{
	BOOL butstate[BUTTON_end];
}

+ (id) sharedStickHandler;

- (int) getNumSticks;
- (NSPoint) getRollPitchAxis;
- (NSPoint) getViewAxis;
- (double) getAxisState:(int)function;
- (double) getSensitivity;
- (const BOOL *) getAllButtonStates;

@end
