/*

OOSDLJoystickManager.h
By Dylan Smith

JoystickHandler handles joystick events from SDL, and translates them
into the appropriate action via a lookup table. The lookup table is
stored as a simple array rather than an ObjC dictionary since this
will be examined fairly often (once per frame during gameplay).

Conversion methods are provided to convert between the internal
representation and an NSDictionary (for loading/saving user defaults
and for use in areas where portability/ease of coding are more important
than performance such as the GUI)

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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
#import <SDL.h>
#import "OOJoystickManager.h"




@interface OOSDLJoystickManager: OOJoystickManager
{
@private
	SDL_Joystick		*stick[MAX_STICKS];
	OOUInteger			stickCount;
}

- (id) init;
- (BOOL) handleSDLEvent: (SDL_Event *)evt;
- (NSString *) nameOfJoystick:(OOUInteger)stickNumber;
- (int16_t) getAxisWithStick:(OOUInteger) stickNum axis:(OOUInteger) axisNum ;

@end
