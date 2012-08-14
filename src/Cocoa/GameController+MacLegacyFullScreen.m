/*

GameController+MacLegacyFullScreen.m

Full-screen rendering support for 32-bit Mac Oolite.


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


#import "GameController.h"

#if OOLITE_MAC_LEGACY_FULLSCREEN	// TEMP, will become general case

#if OOLITE_MAC_LEGACY_FULLSCREEN
#import "OOMacLegacyFullScreenController.h"
#import "Universe.h"

@interface GameController (OOMacLegacyFullScreenControllerDelegate) <OOMacLegacyFullScreenControllerDelegate>
@end

#endif


@implementation GameController (FullScreen)

- (void) setUpDisplayModes
{
	OOMacLegacyFullScreenController *fullScreenController = [[OOMacLegacyFullScreenController alloc] initWithGameView:gameView];
	fullScreenController.delegate = self;
	_fullScreenController = fullScreenController;
}


- (IBAction) goFullscreen:(id)sender
{
	[_fullScreenController setFullScreenMode:YES];
	
#if OOLITE_MAC_LEGACY_FULLSCREEN
	// Mac legacy controller needs to take over the world. By which I mean the event loop.
	if (_fullScreenController.fullScreenMode)
	{
		[(OOMacLegacyFullScreenController *)_fullScreenController runFullScreenModalEventLoop];
	}
#endif
}


- (void) changeFullScreenResolution
{
	// FIXME
}


- (void) exitFullScreenMode
{
	[_fullScreenController setFullScreenMode:NO];
}


- (BOOL) inFullScreenMode
{
	return [_fullScreenController inFullScreenMode];
}


- (BOOL) setDisplayWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
	return [_fullScreenController setDisplayWidth:d_width height:d_height refreshRate:d_refresh];
}


- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
	return [_fullScreenController findDisplayModeForWidth:d_width height:d_height refreshRate:d_refresh];
}


- (NSArray *) displayModes
{
	return _fullScreenController.displayModes;
}


- (OOUInteger) indexOfCurrentDisplayMode
{
	return _fullScreenController.indexOfCurrentDisplayMode;
}


- (void) pauseFullScreenModeToPerform:(SEL)selector onTarget:(id)target
{
	[pauseTarget release];
	pauseTarget = [target retain];
	pauseSelector = selector;
	
	[(OOMacLegacyFullScreenController *)_fullScreenController suspendFullScreen];
}

@end


#if OOLITE_MAC_LEGACY_FULLSCREEN

@implementation GameController (OOMacLegacyFullScreenControllerDelegate)

- (void) handleFullScreenSuspendedAction
{
	[pauseTarget performSelector:pauseSelector];
	DESTROY(pauseTarget);
	pauseSelector = NULL;
}


- (void) handleFullScreenFrameTick
{
	[self performGameTick:self];
	[UNIVERSE drawUniverse];
}

@end

#endif

#endif
