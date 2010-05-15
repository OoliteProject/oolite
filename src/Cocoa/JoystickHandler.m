/*

JoystickHandler.m

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

#import "JoystickHandler.h"


JoystickHandler *sSharedStickHandler = nil;


@implementation JoystickHandler

+ (id) sharedStickHandler
{
	if (sSharedStickHandler == nil)  sSharedStickHandler = [[JoystickHandler alloc] init];
	return sSharedStickHandler;
}


- (int) getNumSticks
{
	return 0;
}


- (NSPoint) getRollPitchAxis
{
	return NSZeroPoint;
}


- (NSPoint) getViewAxis
{
	return NSZeroPoint;
}


- (double) getAxisState:(int)function
{
	return 0.0;
}


- (double) getSensitivity
{
	return 1.0;
}


- (const BOOL *) getAllButtonStates
{
	return butstate;
}

@end
