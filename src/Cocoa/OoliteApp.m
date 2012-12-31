/*

OoliteApp.m

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

#import "OoliteApp.h"
#import "GameController.h"
#import "MyOpenGLView.h"


@implementation OoliteApp

- (void)sendEvent:(NSEvent *)theEvent
{
	NSEventType		etype = [theEvent type];
	MyOpenGLView*	gameView = [_gameController gameView];
	
	if ([NSApp keyWindow] == _gameWindow)
	{
		// Ensure key events are handled at least once when game window is key
		switch (etype)
		{
			case NSKeyDown:
				[gameView keyDown:theEvent];
				break;
			
			case NSKeyUp:
				[gameView keyUp:theEvent];
				break;
			
			default:
				break;
		}
	}
	[super sendEvent:theEvent];				// perform the default event behaviour
}


- (void) setExitContext:(NSString *)exitContext
{
	[_exitContext release];
	_exitContext = [exitContext copy];
}


- (void) terminate:(id)sender
{
	if (_exitContext == nil)  [self setExitContext:@"Cocoa terminate event"];
	OOLog(@"exit.context", @"Exiting: %@.", _exitContext);
	[super terminate:sender];
}

@end
