/*

OOShipLibraryDescriptions.m

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

#import "OOShipLibraryDescriptions.h"
#import "Universe.h"

NSString *OOShipLibrarySpeed (ShipEntity *demo_ship)
{
	GLfloat	param = [demo_ship maxFlightSpeed];
	NSString *result = nil;
	if (param <= 1)
	{
		result = DESC(@"oolite-ship-library-speed-stationary");
	}
	else if (param <= 150)
	{
		result = DESC(@"oolite-ship-library-speed-veryslow");
	}
	else if (param <= 250)
	{
		result = DESC(@"oolite-ship-library-speed-slow");
	}
	else if (param <= 325)
	{
		result = DESC(@"oolite-ship-library-speed-average");
	}
	else if (param <= 425)
	{
		result = DESC(@"oolite-ship-library-speed-fast");
	}
	else
	{
		result = DESC(@"oolite-ship-library-speed-veryfast");
	}
	return result;
}


NSString *OOShipLibraryTurnRate (ShipEntity *demo_ship)
{
	GLfloat param = [demo_ship maxFlightRoll] + (2*[demo_ship maxFlightPitch]);
	NSString *result = nil;
	if (param <= 2)
	{
		result = DESC(@"oolite-ship-library-turn-veryslow");
	}
	else if (param <= 2.75)
	{
		result = DESC(@"oolite-ship-library-turn-slow");
	}
	else if (param <= 4.5)
	{
		result = DESC(@"oolite-ship-library-turn-average");
	}
	else if (param <= 6)
	{
		result = DESC(@"oolite-ship-library-turn-fast");
	}
	else
	{
		result = DESC(@"oolite-ship-library-turn-veryfast");
	}
	return result;
}


NSString *OOShipLibraryCargo (ShipEntity *demo_ship)
{
	OOCargoQuantity param = [demo_ship maxAvailableCargoSpace];
	NSString *result = nil;
	if (param == 0)
	{
		result = DESC(@"oolite-ship-library-cargo-none");
	}
	else 
	{
		result = [NSString stringWithFormat:DESC(@"oolite-ship-library-cargo-carried-u"),param];
	}
	return result;
}
