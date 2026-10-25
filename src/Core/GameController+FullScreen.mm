/*

GameController+FullScreen.m


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


#import "GameController.h"
#import "MyOpenGLView.h"


#if OOLITE_MAC_OS_X	// TEMP, should be used for SDL too

#if OOLITE_MAC_OS_X

#import "OOMacSnowLeopardFullScreenController.h"
#import "OOMacSystemStandardFullScreenController.h"
#import "OOPrimaryWindow.h"
#include "oofnd/Defaults.hpp"


@interface GameController (OOPrimaryWindowDelegate) <OOPrimaryWindowDelegate>
@end

#endif


@implementation GameController (FullScreen)

- (void) setUpDisplayModes
{
#if OOLITE_MAC_OS_X
	OOFullScreenController *fullScreenController = nil;
	
#if OO_MAC_SUPPORT_SYSTEM_STANDARD_FULL_SCREEN
	if ([OOMacSystemStandardFullScreenController shouldUseSystemStandardFullScreenController])
	{
		fullScreenController = [[OOMacSystemStandardFullScreenController alloc] initWithGameView:gameView];
	}
#endif
	
	if (fullScreenController == nil)
	{
		fullScreenController = [[OOMacSnowLeopardFullScreenController alloc] initWithGameView:gameView];
	}
#endif
	
	// Load preferred display mode, falling back to current mode if no preferences set.
	const oo::PList currentMode = [fullScreenController currentDisplayMode];
	NSUInteger width = currentMode.get<NSUInteger>(std::string(kOODisplayWidth));
	NSUInteger height = currentMode.get<NSUInteger>(std::string(kOODisplayHeight));
	NSUInteger refresh = currentMode.get<NSUInteger>(std::string(kOODisplayRefreshRate));
	
	oo::Defaults &userDefaults = oo::Defaults::standard();
	width = userDefaults.object("display_width").isNull() ? width : static_cast<NSUInteger>(userDefaults.integerForKey("display_width"));
	height = userDefaults.object("display_height").isNull() ? height : static_cast<NSUInteger>(userDefaults.integerForKey("display_height"));
	refresh = userDefaults.object("display_refresh").isNull() ? refresh : static_cast<NSUInteger>(userDefaults.integerForKey("display_refresh"));
	
	[fullScreenController setDisplayWidth:width height:height refreshRate:refresh];
	
	_fullScreenController = fullScreenController;
}


#if OOLITE_MAC_OS_X

- (IBAction) toggleFullScreenAction:(id)sender
{
	[self setFullScreenMode:![self inFullScreenMode]];
}


- (void) toggleFullScreenCalledForWindow:(OOPrimaryWindow *)window withSender:(id)sender
{
	[self toggleFullScreenAction:sender];
}

#endif


- (BOOL) inFullScreenMode
{
	return [_fullScreenController inFullScreenMode];
}


- (void) setFullScreenMode:(BOOL)value
{
	if (value == [self inFullScreenMode])  return;
	
	oo::Defaults::standard().setBool("fullscreen", value);
	
	if (value)
	{
		[_fullScreenController setFullScreenMode:YES];
	}
	else
	{
		[_fullScreenController setFullScreenMode:NO];
	}
}


- (void) exitFullScreenMode
{
	[self setFullScreenMode:NO];
}


- (BOOL) setDisplayWidth:(unsigned int)width Height:(unsigned int)height Refresh:(unsigned int)refreshRate
{
	if ([_fullScreenController setDisplayWidth:width height:height refreshRate:refreshRate])
	{
		oo::Defaults &userDefaults = oo::Defaults::standard();
		userDefaults.setInteger("display_width", width);
		userDefaults.setInteger("display_height", height);
		userDefaults.setInteger("display_refresh", refreshRate);
		userDefaults.synchronize();
		
		return YES;
	}
	else
	{
		return NO;
	}
}


- (oo::PList) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
	return [_fullScreenController findDisplayModeForWidth:d_width height:d_height refreshRate:d_refresh];
}


- (oo::PList) displayModes
{
	return [_fullScreenController displayModes];
}


- (NSUInteger) indexOfCurrentDisplayMode
{
	return [_fullScreenController indexOfCurrentDisplayMode];
}


- (void) pauseFullScreenModeToPerform:(SEL)selector onTarget:(id)target
{
	[target performSelector:selector];
}

@end

#endif
