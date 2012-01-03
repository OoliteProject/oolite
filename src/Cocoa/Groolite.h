/*

Groolite.h

Growl integration class. The singleton Groolite object listens for Growl
notifications and reports them by printing to the game communication log. For
more about Growl, see <http://growl.info>.

To do: reimplement using delegate pattern, remove dependency on Growl
framework headers (the framework is not needed at run time).

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

#import <Cocoa/Cocoa.h>

@class GameController;


enum
{
	kGrooliteAllMessages = -2,
	kGrooliteLowPriority,
	kGrooliteMediumPriority,
	kGrooliteHighPriority,
	kGrooliteHighestPriority,
	kGrooliteOff,
	
	kGroolitePriorityMinimum = kGrooliteAllMessages,
	kGroolitePriorityMaximum = kGrooliteOff
};


@interface Groolite: NSObject
{
	NSConnection			*connection;
	IBOutlet GameController	*gameController;
}

+ (NSString *) priorityDescription: (int)min_priority;

+ (BOOL) isEnabled;

@end


/*
	If 1, Groolite is enabled by default and visible in the settings UI.
	
	Turned off in beta 1.75.3 because Growl’s communications protocol will be
	changing in the near future.
*/
#define GROOLITE_VISIBLE		0
