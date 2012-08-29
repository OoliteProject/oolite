/*

OOSDLJoystickManager.m
By Dylan Smith

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

#import "OOSDLJoystickManager.h"
#import "OOLogging.h"

#define kOOLogUnconvertedNSLog @"unclassified.OOSDLJoystickManager"


@implementation OOSDLJoystickManager

- (id) init
{
	int i;

	// Find and open the sticks. Make sure that we don't fail if more joysticks than MAX_STICKS are detected.
	stickCount = SDL_NumJoysticks();
	OOLog(@"joystick.init", @"Number of joysticks detected: %ld", (long)stickCount);
	if (stickCount > MAX_STICKS)
	{
		stickCount = MAX_STICKS;
		OOLog(@"joystick.init", @"Number of joysticks detected exceeds maximum number of joysticks allowed. Setting number of active joysticks to %d.", MAX_STICKS);
	}
	if(stickCount)
	{
		for(i = 0; i < stickCount; i++)
		{
			// it's doubtful MAX_STICKS will ever get exceeded, but
			// we need to be defensive.
			if(i > MAX_STICKS)
				break;

			stick[i]=SDL_JoystickOpen(i);
			if(!stick[i])
			{
				OOLog(@"joystick.init", @"Failed to open joystick #%d", i);
			}
		}
		SDL_JoystickEventState(SDL_ENABLE);
	}
	return [super init];
}


- (BOOL) handleSDLEvent: (SDL_Event *)evt
{
	BOOL rc=NO;
	switch(evt->type)
	{
		case SDL_JOYAXISMOTION:
			[self decodeAxisEvent: (JoyAxisEvent *)evt];
			rc=YES;
			break;
		case SDL_JOYBUTTONDOWN:
		case SDL_JOYBUTTONUP:
			[self decodeButtonEvent: (JoyButtonEvent *)evt];
			rc=YES;
			break;
		case SDL_JOYHATMOTION:
			[self decodeHatEvent: (JoyHatEvent *)evt];
			rc=YES;
			break;
		default:
			OOLog(@"handleSDLEvent.unknownEvent", @"JoystickHandler was sent an event it doesn't know");
	}
	return rc;
}


// Overrides

- (NSUInteger) joystickCount
{
	return stickCount;
}


- (NSString *) nameOfJoystick:(NSUInteger)stickNumber
{
	return [NSString stringWithUTF8String:SDL_JoystickName((int)stickNumber)];
}


- (int16_t) getAxisWithStick:(NSUInteger) stickNum axis:(NSUInteger) axisNum 
{
	return SDL_JoystickGetAxis(stick[stickNum], axisNum);
}



@end
