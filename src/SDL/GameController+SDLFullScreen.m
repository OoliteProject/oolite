/*

GameController+SDLFullScreen.m

Full-screen rendering support for SDL targets.


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

#if OOLITE_SDL

#import "MyOpenGLView.h"
#import "Universe.h"
#import "OOFullScreenController.h"


@implementation GameController (FullScreen)

- (void) setUpDisplayModes
{
	NSArray				*modes = [gameView getScreenSizeArray];
	NSDictionary		*mode = nil;
	unsigned	int		modeIndex, modeCount;
	unsigned	int		modeWidth, modeHeight;

	displayModes = [[NSMutableArray alloc] init];
	modeCount = [modes count];
	for (modeIndex = 0; modeIndex < modeCount; modeIndex++)
	{
		mode = [modes objectAtIndex: modeIndex];
		modeWidth = [[mode objectForKey: kOODisplayWidth] intValue];
		modeHeight = [[mode objectForKey: kOODisplayHeight] intValue];
		
		if (modeWidth < DISPLAY_MIN_WIDTH ||
			modeWidth > DISPLAY_MAX_WIDTH ||
			modeHeight < DISPLAY_MIN_HEIGHT ||
			modeHeight > DISPLAY_MAX_HEIGHT)
			continue;
		[displayModes addObject: mode];
	}
	
	NSSize fsmSize = [gameView currentScreenSize];
	width = fsmSize.width;
	height = fsmSize.height;
}


- (void) setFullScreenMode:(BOOL)fsm
{
	fullscreen = fsm;
}


- (void) exitFullScreenMode
{
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"fullscreen"];
	stayInFullScreenMode = NO;
}


- (BOOL) inFullScreenMode
{
	return [gameView inFullScreenMode];
}


- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
	NSDictionary *d_mode = [self findDisplayModeForWidth: d_width Height: d_height Refresh: d_refresh];
	if (d_mode)
	{
		width = d_width;
		height = d_height;
		refresh = d_refresh;
		fullscreenDisplayMode = d_mode;
		
		NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
		
		[userDefaults setInteger:width   forKey:@"display_width"];
		[userDefaults setInteger:height  forKey:@"display_height"];
		[userDefaults setInteger:refresh forKey:@"display_refresh"];
		
		// Manual synchronization is required for SDL And doesn't hurt much for OS X.
		[userDefaults synchronize];
		
		return YES;
	}
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
	int i, modeCount;
	NSDictionary *mode;
	unsigned int modeWidth, modeHeight, modeRefresh;
	
	modeCount = [displayModes count];
	
	for (i = 0; i < modeCount; i++)
	{
		mode = [displayModes objectAtIndex: i];
		modeWidth = [[mode objectForKey:kOODisplayWidth] intValue];
		modeHeight = [[mode objectForKey:kOODisplayHeight] intValue];
		modeRefresh = [[mode objectForKey:kOODisplayRefreshRate] intValue];
		if ((modeWidth == d_width)&&(modeHeight == d_height)&&(modeRefresh == d_refresh))
		{
			return mode;
		}
	}
	return nil;
}


- (NSArray *) displayModes
{
	return [NSArray arrayWithArray:displayModes];
}


- (NSUInteger) indexOfCurrentDisplayMode
{
	NSDictionary	*mode;
	
	mode = [self findDisplayModeForWidth: width Height: height Refresh: refresh];
	if (mode == nil)
		return NSNotFound;
	else
		return [displayModes indexOfObject:mode];

   return NSNotFound;
}


- (void) pauseFullScreenModeToPerform:(SEL) selector onTarget:(id) target
{
	pauseSelector = selector;
	pauseTarget = target;
	stayInFullScreenMode = NO;
}

@end

#endif
