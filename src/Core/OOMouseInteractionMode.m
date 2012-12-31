/*

OOMouseInteractionMode.m


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

#import "OOMouseInteractionMode.h"


NSString *OOStringFromMouseInteractionMode(OOMouseInteractionMode mode)
{
	switch (mode)
	{
		case MOUSE_MODE_UI_SCREEN_NO_INTERACTION:	return @"UI_SCREEN_NO_INTERACTION";
		case MOUSE_MODE_UI_SCREEN_WITH_INTERACTION:	return @"UI_SCREEN_WITH_INTERACTION";
		case MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL:	return @"FLIGHT_NO_MOUSE_CONTROL";
		case MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL:	return @"FLIGHT_WITH_MOUSE_CONTROL";
	}
	
	return [NSString stringWithFormat:@"<unknown mode %u>", mode];
}


BOOL OOMouseInteractionModeIsUIScreen(OOMouseInteractionMode mode)
{
	switch (mode)
	{
		case MOUSE_MODE_UI_SCREEN_NO_INTERACTION:	return YES;
		case MOUSE_MODE_UI_SCREEN_WITH_INTERACTION:	return YES;
		case MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL:	return NO;
		case MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL:	return NO;
	}
	
	return NO;
}


BOOL OOMouseInteractionModeIsFlightMode(OOMouseInteractionMode mode)
{
	switch (mode)
	{
		case MOUSE_MODE_UI_SCREEN_NO_INTERACTION:	return NO;
		case MOUSE_MODE_UI_SCREEN_WITH_INTERACTION:	return NO;
		case MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL:	return YES;
		case MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL:	return YES;
	}
	
	return NO;
}
