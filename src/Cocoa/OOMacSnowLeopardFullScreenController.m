/*

OOMacSnowLeopardFullScreenController.m


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

#import "OOMacSnowLeopardFullScreenController.h"

#if OOLITE_MAC_OS_X && OOLITE_64_BIT


#import <Carbon/Carbon.h>	// For SetSystemUIMode()
#import "MyOpenGLView.h"
#import "OOLogging.h"
#import "OOFullScreenWindow.h"
#import "OOCollectionExtractors.h"


#define SUPRESS_BLANKING_WINDOWS		( 0 && OO_DEBUG)


@interface OOMacSnowLeopardFullScreenController ()

@property (nonatomic, retain) NSWindow *fullScreenWindow;	// Window on main gameplay screen which contains our OpenGL view in full screen mode.
@property (nonatomic, retain) NSArray *blankingWindows;		// Plain black windows covering other screens if relevant.
@property (nonatomic, retain) NSWindow *standardWindow;		// The main game window, stashed away for use when existing full screen mode.

@property (nonatomic, retain) NSScreen *gameScreen;

- (void) beginFullScreenMode;
- (void) endFullScreenMode;

- (void) setUpBlankingWindowsForScreensOtherThan:(NSScreen *)gameScreen;
- (void) removeBlankingWindows;

@end


@implementation OOMacSnowLeopardFullScreenController

@synthesize fullScreenMode = _fullScreenMode;	// Future note: needs to be explicit because property declaration is inherited.
@synthesize fullScreenWindow = _fullScreenWindow;
@synthesize blankingWindows = _blankingWindows;
@synthesize standardWindow = _standardWindow;
@synthesize gameScreen = _gameScreen;


- (void) dealloc
{
	[self endFullScreenMode];
	
	DESTROY(_fullScreenWindow);
	DESTROY(_blankingWindows);
	DESTROY(_standardWindow);
	DESTROY(_gameScreen);
	
	[super dealloc];
}


- (void) setFullScreenMode:(BOOL)value
{
	if (!value && self.fullScreenMode)
	{
		[self endFullScreenMode];
	}
	else if (value && !self.fullScreenMode)
	{
		[self beginFullScreenMode];
	}
}


- (NSArray *) displayModes
{
	NSSize size = self.fullScreenWindow.frame.size;
	NSDictionary *fakeMode = [NSDictionary dictionaryWithObjectsAndKeys:
							  [NSNumber numberWithUnsignedInt:size.width], kOODisplayWidth,
							  [NSNumber numberWithUnsignedInt:size.height], kOODisplayHeight,
							  nil];
	return [NSArray arrayWithObject:fakeMode];
}


- (OOUInteger) indexOfCurrentDisplayMode
{
	return 0;
}


- (BOOL) setDisplayWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	NSDictionary *fakeMode = [self.displayModes objectAtIndex:0];
	if (width == [fakeMode oo_unsignedIntegerForKey:kOODisplayWidth] &&
		height == [fakeMode oo_unsignedIntegerForKey:kOODisplayHeight])
	{
		return fakeMode;
	}
	return nil;
}


#pragma mark - Actual full screen mode handling

- (void) beginFullScreenMode
{
	NSAssert(!self.fullScreenMode, @"%s called in wrong state.", __FUNCTION__);
	
	// Stash the windowed-mode window so we can restore to it later.
	self.standardWindow = self.gameView.window;
	
	/*
		Set up a full-screen window. Based on OpenGL Programming Guide for Mac
		[developer.apple.com], dated 2012-07-23, "Drawing to the Full Screen".
	*/
	self.gameScreen = self.gameView.window.screen;
	NSRect frame = self.gameScreen.frame;
	OOFullScreenWindow *window = [[OOFullScreenWindow alloc] initWithContentRect:frame
																	   styleMask:NSBorderlessWindowMask
																		 backing:NSBackingStoreBuffered
																		   defer:NO];
	if (window == nil)  return;
	
	self.fullScreenWindow = [window autorelease];
	
	[window setOpaque:YES];
	[window setMovable:YES];
	window.canBecomeKeyWindow = YES;
	window.canBecomeMainWindow = YES;
#if !OO_DEBUG
	/*
		Leaving a full-screen window visible in the background is anti-social,
		but convenient in debug builds.
	*/
	window.hidesOnDeactivate = YES;
#endif
	
	// TODO: handle screen reconfiguration.
	
	[self.standardWindow orderOut:nil];
	window.contentView = self.gameView;
	
	SetSystemUIMode(kUIModeAllSuppressed, kUIOptionDisableMenuBarTransparency);
	[self setUpBlankingWindowsForScreensOtherThan:self.gameScreen];
	
	[window makeKeyAndOrderFront:self];
	OOLog(@"temp", @"%u", window.canBecomeMainWindow);
	
	_fullScreenMode = YES;
	
	// Subscribe to reconfiguration notifications.
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(screenParametersChanged:)
												 name:NSApplicationDidChangeScreenParametersNotification
											   object:NSApp];
}


- (void) endFullScreenMode
{
	NSAssert(self.fullScreenMode, @"%s called in wrong state.", __FUNCTION__);
	
	[self.fullScreenWindow orderOut:nil];
	
	[self removeBlankingWindows];
	SetSystemUIMode(kUIModeNormal, 0);
	
	self.standardWindow.contentView = self.gameView;
	[self.standardWindow makeKeyAndOrderFront:nil];
	
	self.standardWindow = nil;
	self.fullScreenWindow = nil;
	self.gameScreen = nil;
	
	_fullScreenMode = NO;
	
	// Unsubscribe from notifications.
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSApplicationDidChangeScreenParametersNotification
												  object:NSApp];
}


- (void) screenParametersChanged:(NSNotification *)notification
{
	NSAssert(self.fullScreenMode, @"%s called in wrong state.", __FUNCTION__);
	
	[self.fullScreenWindow setFrame:self.gameScreen.frame display:YES];
	[self setUpBlankingWindowsForScreensOtherThan:self.gameScreen];
}


- (void) setUpBlankingWindowsForScreensOtherThan:(NSScreen *)gameScreen
{
#if SUPRESS_BLANKING_WINDOWS
	// Skip blanking windows while debugging.
	return;
#endif
	
	/*
		On muliple-screen systems, fill all screens except the game screen
		with an all-black window. This behaviour has its critics, but it is
		consistent with both traditional Oolite behaviour and Mac OS X 10.7
		and later standard behaviour.
	*/
	
	// Remove any existing blanking windows.
	[self removeBlankingWindows];
	
	NSArray *screens = [NSScreen screens];
	if (screens.count <= 1)
	{
		//	No blanking windows needed on single-screen systems.
		return;
	}
	
	NSMutableArray *windows = [NSMutableArray arrayWithCapacity:screens.count - 1];
	for (NSScreen *screen in screens)
	{
		if ([screen isEqual:gameScreen])  continue;
		
		NSRect frame = screen.frame;
		OOFullScreenWindow *window = [[OOFullScreenWindow alloc] initWithContentRect:frame
																		   styleMask:NSBorderlessWindowMask
																			 backing:NSBackingStoreBuffered
																			   defer:NO];
		
		[window setOpaque:YES];
		[window setMovable:YES];
		window.collectionBehavior = NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;
		window.canBecomeKeyWindow = NO;
		window.canBecomeMainWindow = NO;
		window.hidesOnDeactivate = YES;
		window.backgroundColor = [NSColor blackColor];
		
		[windows addObject:window];
		[window orderFront:nil];
		[window release];
	}
	
	self.blankingWindows = windows;
}


- (void) removeBlankingWindows
{
	for (NSWindow *window in self.blankingWindows)
	{
		[window orderOut:nil];
	}
	self.blankingWindows = nil;
}


- (void) checkWindowVisible:(NSTimer *)timer
{
	NSWindow *window = timer.userInfo;
	OOLog(@"temp.fullScreen", @"Window %@ is %@ on screen %@", window, window.isVisible ? @"visible" : @"INVISIBLE", window.screen);
}

@end

#endif
