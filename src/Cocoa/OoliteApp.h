/*

OoliteApp.h

This is a subclass of NSApplication for Oolite.

It gets around problems with the system intercepting certain events (NSKeyDown
and NSKeyUp) before MyOpenGLView gets to see them, it does this by sending
those events to MyOpenGLView regardless of any other processing NSApplication
will do with them.

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

#import "OOCocoa.h"

@class GameController;


@interface OoliteApp: NSApplication
{
@private
	IBOutlet NSWindow			*_gameWindow;
	IBOutlet GameController		*_gameController;
	NSString					*_exitContext;
}

- (void) setExitContext:(NSString *)exitContext;

@end
