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
#import "OOCollectionExtractors.h"


#if OOLITE_MAC_OS_X	// TEMP, should be used for SDL too

#if OOLITE_MAC_OS_X

#import "OOMacSnowLeopardFullScreenController.h"
#import "OOMacSystemStandardFullScreenController.h"
#import "OOPrimaryWindow.h"


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
	NSDictionary *currentMode = [fullScreenController currentDisplayMode];
	NSUInteger width = [currentMode oo_unsignedIntegerForKey:kOODisplayWidth];
	NSUInteger height = [currentMode oo_unsignedIntegerForKey:kOODisplayHeight];
	NSUInteger refresh = [currentMode oo_unsignedIntegerForKey:kOODisplayRefreshRate];
	
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	width = [userDefaults oo_unsignedIntegerForKey:@"display_width" defaultValue:width];
	height = [userDefaults oo_unsignedIntegerForKey:@"display_height" defaultValue:height];
	refresh = [userDefaults oo_unsignedIntegerForKey:@"display_refresh" defaultValue:refresh];
	
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
	
	[[NSUserDefaults standardUserDefaults] setBool:value forKey:@"fullscreen"];
	
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
		NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
		
		[userDefaults setInteger:width			forKey:@"display_width"];
		[userDefaults setInteger:height			forKey:@"display_height"];
		[userDefaults setInteger:refreshRate	forKey:@"display_refresh"];
		
		[userDefaults synchronize];
		
		return YES;
	}
	else
	{
		return NO;
	}
}


- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh
{
	return [_fullScreenController findDisplayModeForWidth:d_width height:d_height refreshRate:d_refresh];
}


- (NSArray *) displayModes
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
