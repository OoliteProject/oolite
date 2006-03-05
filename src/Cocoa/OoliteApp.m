/*

	Oolite

	OoliteApp.m

	Created by Giles Williams on 01/05/2005.


Copyright (c) 2005, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "OoliteApp.h"
#import "GameController.h"
#import "MyOpenGLView.h"

/*--
	This is a subclass of NSApplication for Oolite.
	
	It gets around problems with the system intercepting certain events (NSKeyDown and NSKeyUp)
	before MyOpenGLView gets to see them, it does this by sending those events to MyOpenGLView
	regardless of any other processing NSApplication will do with them.
--*/

@implementation OoliteApp

- (void)sendEvent:(NSEvent *)theEvent
{
	NSEventType		etype = [theEvent type];
	GameController*	gameController = (GameController*)[self delegate];
	MyOpenGLView*	gameView = (MyOpenGLView*)[gameController gameView];
	switch (etype)
	{
		case NSKeyDown:
			[gameView keyDown:theEvent];	// ensure this gets called at least once
			break;
		case NSKeyUp:
			[gameView keyUp:theEvent];		// ensure this gets called at least once
			break;
		default:
			break;
	}
	[super sendEvent:theEvent];				// perform the default event behaviour
}


@end
