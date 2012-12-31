/*

OOMacSystemStandardFullScreenController.m


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

#import "OOMacSystemStandardFullScreenController.h"

#if OO_MAC_SUPPORT_SYSTEM_STANDARD_FULL_SCREEN


#import "MyOpenGLView.h"
#import "OOLogging.h"
#import "OOPrimaryWindow.h"
#import "OOCollectionExtractors.h"


#ifndef NSAppKitVersionNumber10_7
#define NSAppKitVersionNumber10_7 1138
#endif


#define kFullScreenPresentationMode	  ( NSApplicationPresentationFullScreen | \
										NSApplicationPresentationAutoHideDock | \
										NSApplicationPresentationAutoHideMenuBar )


@implementation OOMacSystemStandardFullScreenController

+ (BOOL) shouldUseSystemStandardFullScreenController
{
	if (floor(NSAppKitVersionNumber) <= NSAppKitVersionNumber10_6)
	{
		// Never on 10.6 or earlier; the necessary API doesn't exist.
		return NO;
	}
	
	// If safe to use, allow override for debugging.
	NSString *override = [[NSUserDefaults standardUserDefaults] stringForKey:@"full-screen-mode-override"];
	if (override != nil)
	{
		if ([override isEqualToString:@"lion"])  return YES;
		if ([override isEqualToString:@"snow-leopard"])  return NO;
	}
	
	if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_7)
	{
		// Always use on 10.8 or later.
		return YES;
	}
	
	return NSScreen.screens.count == 1;	// Use if there's a single screen on 10.7.
}


- (BOOL) inFullScreenMode
{
	return ([NSApp presentationOptions] & NSApplicationPresentationFullScreen) != 0;
}


- (void) setFullScreenMode:(BOOL)value
{
	if (!value == self.fullScreenMode)
	{
		OOPrimaryWindow *window = (OOPrimaryWindow *)self.gameView.window;
		NSAssert([window isKindOfClass:OOPrimaryWindow.class], @"Incorrect UI setup; main game window should be OOPrimaryWindow.");
		
		[window makeKeyAndOrderFront:nil];
		[window standardToggleFullScreen:nil];
	}
}


- (NSArray *) displayModes
{
	NSSize size = self.gameView.window.frame.size;
	NSDictionary *fakeMode = [NSDictionary dictionaryWithObjectsAndKeys:
							  [NSNumber numberWithUnsignedInt:size.width], kOODisplayWidth,
							  [NSNumber numberWithUnsignedInt:size.height], kOODisplayHeight,
							  nil];
	return [NSArray arrayWithObject:fakeMode];
}


- (NSUInteger) indexOfCurrentDisplayMode
{
	return 0;
}


- (BOOL) setDisplayWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(NSUInteger)refresh
{
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(NSUInteger)refresh
{
	NSDictionary *fakeMode = [self.displayModes objectAtIndex:0];
	if (width == [fakeMode oo_unsignedIntegerForKey:kOODisplayWidth] &&
		height == [fakeMode oo_unsignedIntegerForKey:kOODisplayHeight])
	{
		return fakeMode;
	}
	return nil;
}


- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
	[self.gameView noteMouseInteractionModeChangedFrom:oldMode to:newMode];
}

@end

#endif
