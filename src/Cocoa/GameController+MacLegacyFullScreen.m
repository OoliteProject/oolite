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

#if OOLITE_MAC_LEGACY_FULLSCREEN

#import "OOMacLegacyFullScreenController.h"
#if OOLITE_MAC_LEGACY_FULLSCREEN
#import "Universe.h"
#endif


@implementation GameController (FullScreen)

- (void) setUpDisplayModes
{
	_fullScreenController = [[OOMacLegacyFullScreenController alloc] initWithGameView:gameView];
}


- (IBAction) goFullscreen:(id)sender
{
	[_fullScreenController setFullScreenMode:YES];
#if OOLITE_MAC_LEGACY_FULLSCREEN
	if (_fullScreenController.fullScreenMode)
	{
		[(OOMacLegacyFullScreenController *)_fullScreenController runFullScreenModalEventLoopWithFrameAction:^{
			[self performGameTick:self];
			[UNIVERSE drawUniverse];
		}];
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


- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int)d_height Refresh:(unsigned int) d_refresh
{
	return [_fullScreenController setDisplayWidth:d_width height:d_height refreshRate:d_refresh];
}


- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
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
	[(OOMacLegacyFullScreenController *)_fullScreenController suspendFullScreenToPerform:^{
		[target performSelector:selector];
	}];
}

@end

#endif
