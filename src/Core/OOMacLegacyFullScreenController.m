/*

OOMacLegacyFullScreenController.m


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

#import "OOMacLegacyFullScreenController.h"

#if OOLITE_MAC_OS_X && !OOLITE_64_BIT

#import "GameController.h"
#import "OOCollectionExtractors.h"
#import "MyOpenGLView.h"
#import "Universe.h"


enum
{
	kStateNotFullScreen,		// self.fullScreen = NO
	kStateNominallyFullScreen,	// self.fullScreen = YES, but not in runFullScreenModalEventLoop
	kStateActuallyFullScreen
};


static NSComparisonResult CompareDisplayModes(id arg1, id arg2, void *context);


@interface OOMacLegacyFullScreenController ()

@property (nonatomic, copy) NSDictionary *fullScreenDisplayMode;
@property (nonatomic, copy) NSDictionary *originalDisplayMode;
@property (nonatomic, retain) NSOpenGLContext *fullScreenContext;
@property (nonatomic, copy) OOActionBlock frameAction;
@property (nonatomic, copy) OOActionBlock suspendAction;

- (void) beginFullScreenMode;
- (void) runFullScreenModalEventLoopInner;

- (void) recenterCursor;
- (void) dispatchSuspendAction;

@end


@implementation OOMacLegacyFullScreenController

@synthesize gameView = _gameView;
@synthesize fullScreenDisplayMode = _fullScreenDisplayMode;
@synthesize originalDisplayMode = _originalDisplayMode;
@synthesize fullScreenContext = _fullScreenContext;
@synthesize frameAction = _frameAction;
@synthesize suspendAction = _suspendAction;


- (id) initWithGameView:(MyOpenGLView *)view
{
	if ((self = [super init]))
	{
		NSArray				*modes = nil;
		NSDictionary		*mode = nil, *mode2 = nil;
		OOUInteger			modeWidth, modeHeight, color;
		OOUInteger			modeWidth2, modeHeight2, color2;
		BOOL				stretched, stretched2, interlaced, interlaced2;
		float				modeRefresh, modeRefresh2;
		NSUserDefaults		*userDefaults = nil;
		BOOL				deleteFirst;
		
		_gameView = [view retain];
		
		// Load preferences.
		userDefaults = [NSUserDefaults standardUserDefaults];
		_width = [userDefaults oo_unsignedIntForKey:@"display_width" defaultValue:DISPLAY_DEFAULT_WIDTH];
		_height = [userDefaults oo_unsignedIntForKey:@"display_height" defaultValue:DISPLAY_DEFAULT_HEIGHT];
		_refresh = [userDefaults oo_unsignedIntForKey:@"display_refresh" defaultValue:DISPLAY_DEFAULT_REFRESH];
		
#if 0
		// FIXME: handle in caller.
		_fullScreen = [userDefaults oo_boolForKey:@"fullscreen" defaultValue:NO];
#endif
		
		// Get the list of all available modes
		modes = (NSArray *)CGDisplayAvailableModes(kCGDirectMainDisplay);
		
		// Filter out modes that we don't want
		_displayModes = [[NSMutableArray alloc] init];
		for (mode in modes)
		{
			modeWidth = [mode oo_unsignedIntForKey:kOODisplayWidth];
			modeHeight = [mode oo_unsignedIntForKey:kOODisplayHeight];
			color = [mode oo_unsignedIntForKey:kOODisplayBitsPerPixel];
			
			if (color < DISPLAY_MIN_COLOURS ||
				modeWidth < DISPLAY_MIN_WIDTH ||
				modeWidth > DISPLAY_MAX_WIDTH ||
				modeHeight < DISPLAY_MIN_HEIGHT ||
				modeHeight > DISPLAY_MAX_HEIGHT)
			{
				continue;
			}
			
			[_displayModes addObject:mode];
		}
		
		// Sort the filtered modes
		[_displayModes sortUsingFunction:CompareDisplayModes context:NULL];
		
		// ***JESTER_START*** 11/08/04
		// Powerbooks return several "identical modes" CGDisplayAvailableModes doesn't appear
		// to pick up refresh rates. Logged as Radar 3759831.
		// In order to deal with this, we'll just edit out the duplicates.
		/*
			Bug	011893: restoring old display filtering code because my previous
			assumption that using a set would filter out "duplicates" was broken.
			The modes in question are not actually duplicates. For instance,
			stretched modes look like "duplicates" from Oolite's perspective. The
			Right Thing is to handle stretched modes properly. Also, the bug that
			having "duplicates" causes (bad behaviour in config screen, see bug
			011893) is really down to not tracking the selected display mode index
			explictly.
			Basically, this needs redoing, but shouldn't hold up 1.70.
			-- Ahruman
		*/
		OOUInteger modeIndex, mode2Index;
		for (modeIndex = 0; modeIndex + 1 < [_displayModes count]; modeIndex++)
		{
			mode = [_displayModes objectAtIndex:modeIndex];
			modeWidth = [mode oo_unsignedIntForKey:kOODisplayWidth];
			modeHeight = [mode oo_unsignedIntForKey:kOODisplayHeight];
			modeRefresh = [mode oo_floatForKey:kOODisplayRefreshRate];
			color = [mode oo_unsignedIntForKey:kOODisplayBitsPerPixel];
			stretched = [mode oo_boolForKey:(NSString *)kCGDisplayModeIsStretched];
			interlaced = [mode oo_boolForKey:(NSString *)kCGDisplayModeIsInterlaced];
			
			for (mode2Index = modeIndex + 1; mode2Index < [_displayModes count]; ++mode2Index)
			{
				mode2 = [_displayModes objectAtIndex:mode2Index];
				modeWidth2 = [mode2 oo_unsignedIntForKey:kOODisplayWidth];
				modeHeight2 = [mode2 oo_unsignedIntForKey:kOODisplayHeight];
				modeRefresh2 = [mode2 oo_floatForKey:kOODisplayRefreshRate];
				color2 = [mode oo_unsignedIntForKey:kOODisplayBitsPerPixel];
				stretched2 = [mode2 oo_boolForKey:(NSString *)kCGDisplayModeIsStretched];
				interlaced2 = [mode2 oo_boolForKey:(NSString *)kCGDisplayModeIsInterlaced];
				
				if (modeWidth == modeWidth2 &&
					modeHeight == modeHeight2 &&
					modeRefresh == modeRefresh2)
				{
					/*	Modes are "duplicates" from Oolite's perspective, so one
						needs to be removed. If one has higher colour depth, use
						that one. Otherwise, If one is stretched and the other
						isn't, remove the stretched one. Otherwise, if one is
						interlaced and the other isn't, remove the interlaced one.
						Otherwise, remove the one that comes later in the list.
					*/
					deleteFirst = NO;
					if (color < color2)  deleteFirst = YES;
					else if (color == color2)
					{
						if (stretched && !stretched2)  deleteFirst = YES;
						else if (stretched == stretched2)
						{
							if (interlaced && !interlaced2)  deleteFirst = YES;
						}
					}
					if (deleteFirst)
					{
						[_displayModes removeObjectAtIndex:modeIndex];
						modeIndex--;
						break;
					}
					else
					{
						[_displayModes removeObjectAtIndex:mode2Index];
						mode2Index--;
					}
				}
			}
		}
		
		if ([_displayModes count] == 0)
		{
			[NSException raise:@"OoliteNoDisplayModes"
						format:@"No acceptable display modes could be found!"];
		}
		
		self.fullScreenDisplayMode = [self findDisplayModeForWidth:_width height:_height refreshRate:_refresh];
		if (self.fullScreenDisplayMode == nil)
		{
			// set full screen mode to first available mode
			self.fullScreenDisplayMode = [_displayModes objectAtIndex:0];
			_width = [self.fullScreenDisplayMode oo_unsignedIntegerForKey:kOODisplayWidth];
			_height = [self.fullScreenDisplayMode oo_unsignedIntegerForKey:kOODisplayHeight];
			_refresh = [self.fullScreenDisplayMode oo_unsignedIntegerForKey:kOODisplayRefreshRate];
		}
	}
	
	return self;
}


- (void) dealloc
{
	DESTROY(_gameView);
	DESTROY(_displayModes);
	DESTROY(_originalDisplayMode);
	DESTROY(_fullScreenDisplayMode);
	DESTROY(_fullScreenContext);
	DESTROY(_frameAction);
	DESTROY(_suspendAction);
	
	[super dealloc];
}


- (BOOL) inFullScreenMode
{
	return _state != kStateNotFullScreen;
}


- (void) setFullScreenMode:(BOOL)value
{
	if (!value && self.fullScreenMode)
	{
		// FIXME: default handling in caller?
		[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"fullscreen"];
		_stayInFullScreenMode = NO;
	}
	else if (value && !self.fullScreenMode)
	{
		[self beginFullScreenMode];
	}
}

- (NSArray *) displayModes
{
	return [NSArray arrayWithArray:_displayModes];
}


- (OOUInteger) indexOfCurrentDisplayMode
{
	NSDictionary *mode = [self findDisplayModeForWidth:_width height:_height refreshRate:_refresh];
	if (mode == nil)  return NSNotFound;
	else  return [_displayModes indexOfObject:mode];
}


- (BOOL) setDisplayWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	NSDictionary *mode = [self findDisplayModeForWidth:width height:height refreshRate:refresh];
	if (mode != nil)
	{
		_width = width;
		_height = height;
		_refresh = refresh;
		self.fullScreenDisplayMode = mode;
		
		NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
		
		[userDefaults setInteger:_width   forKey:@"display_width"];
		[userDefaults setInteger:_height  forKey:@"display_height"];
		[userDefaults setInteger:_refresh forKey:@"display_refresh"];
		
		[userDefaults synchronize];
		
		return YES;
	}
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(OOUInteger)width height:(OOUInteger)height refreshRate:(OOUInteger)refresh
{
	for (NSDictionary *mode in _displayModes)
	{
		OOUInteger modeWidth = [mode oo_unsignedIntegerForKey:kOODisplayWidth];
		OOUInteger modeHeight = [mode oo_unsignedIntegerForKey:kOODisplayHeight];
		OOUInteger modeRefresh = [mode oo_unsignedIntegerForKey:kOODisplayRefreshRate];
		
		if ((modeWidth == width) && (modeHeight == height) && (modeRefresh == refresh))
		{
			return mode;
		}
	}
	return nil;
}


- (void) runFullScreenModalEventLoopWithFrameAction:(OOActionBlock)frameAction
{
	NSAssert(_state == kStateNominallyFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	@try
	{
		self.frameAction = frameAction;
		self.suspendAction = nil;
		[self runFullScreenModalEventLoopInner];
		
	}
	@finally
	{
		[self dispatchSuspendAction];
		self.frameAction = nil;
		_state = kStateNotFullScreen;
		self.fullScreenContext = nil;
	}
}


- (void) suspendFullScreenToPerform:(OOActionBlock)action
{
	// To avoid fussy logic in caller, just run the action immediately if not in full screen.
	if (!self.fullScreenMode)
	{
		action();
		return;
	}
	
	OOActionBlock previousAction = self.suspendAction;
	if (previousAction == NULL)
	{
		self.suspendAction = action;
	}
	else
	{
		// Allow queueing multiple actions to perform in-order.
		self.suspendAction = ^{
			previousAction();
			action();
		};
	}
}


#pragma mark - Actual full screen mode handling

- (void) beginFullScreenMode
{
	NSAssert(_state == kStateNotFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	NSAutoreleasePool *setupPool = [NSAutoreleasePool new];
	
	self.fullScreenDisplayMode = [self findDisplayModeForWidth:_width height:_height refreshRate:_refresh];
	if (self.fullScreenDisplayMode == nil)
	{
		OOLogERR(@"display.mode.noneFound", @"Unable to find suitable full screen mode.");
		return;
	}
	
	self.originalDisplayMode = (NSDictionary *)CGDisplayCurrentMode(kCGDirectMainDisplay);
	
	_state = kStateNominallyFullScreen;
	
	// empty the event queue and strip all keys - stop problems with hangover keys
	while ([NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES] != NULL)  {}
	[self.gameView clearKeys];
	[self.gameView clearCommandF];	// Avoid immediately switching back to windowed mode.
	
	[setupPool drain];
}


- (void) runFullScreenModalEventLoopInner
{
	NSAssert(_state == kStateNominallyFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	int32_t mouseX = 0, mouseY = 0;
	
	MyOpenGLView *gameView = self.gameView;
	
	NSMutableData *attrData = [[gameView.pixelFormatAttributes mutableCopy] autorelease];
	NSOpenGLPixelFormatAttribute *attrs = [attrData mutableBytes];
	NSAssert(attrs[0] == NSOpenGLPFAWindow, @"Pixel format does not meet expectations.");
	attrs[0] = NSOpenGLPFAFullScreen;
	
	NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
	[pixelFormat autorelease];
	
	// Outer loop exists to support switching out of full screen mode temporarily to show alerts and such.
	for (;;)
	{
		/*	Create an NSOpenGLContext with the FullScreen pixel format. By
			specifying the non-FullScreen context as our "shareContext", we
			automatically inherit all of the textures, display lists, and other
			OpenGL objects it has defined.
		*/
		NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:gameView.openGLContext];
		self.fullScreenContext = context;
		[context release];
		
		if (context == nil)
		{
			OOLogERR(@"display.context.create.failed", @"Failed to create fullScreenContext.");
			return;
		}
		
		// FIXME: what about this? Caller?
	#if 0
		/*	Pause animation in the OpenGL view. While we're in full-screen
			mode, we'll drive the animation actively
			instead of using a timer callback.
		*/
		if (timer)
			[self stopAnimationTimer];
	#endif
		
		/*	Take control of the display where we're about to go full-screen.
			this stops windows from being shuffled around.
		*/
		CGDisplayErr err = CGCaptureAllDisplays();
		if (err != CGDisplayNoErr)
		{
			OOLogERR(@"display.context.create.failed", @"Failed to capture displays.");
			return;
		}
		
		// switch resolution!
		err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)self.fullScreenDisplayMode);
		if (err != CGDisplayNoErr)
		{
			OOLogERR(@"display.mode.switch.failed", @"Unable to change display for full-screen mode.");
			return;
		}
		
		// Hide the cursor.
		CGDisplayHideCursor(kCGDirectMainDisplay);
		[self recenterCursor];
		
		/*	Enter full-screen mode and make our full-screen context the active
			context for OpenGL commands.
		*/
		[context setFullScreen];
		[context makeCurrentContext];
		
		// We are now officially in full-screen mode.
		_state = kStateActuallyFullScreen;
		
		/*	Save the current swap interval so we can restore it later, and then
			set the new swap interval to lock us to the display's refresh rate.
		*/
		CGLContextObj cglContext = CGLGetCurrentContext();
		GLint savedSwapInterval;
		CGLGetParameter(cglContext, kCGLCPSwapInterval, &savedSwapInterval);
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &(GLint){1});
		
		/*	Tell the scene the dimensions of the area it's going to render to,
			so it can set up an appropriate viewport and viewing transformation.
		*/
		NSLog(@"Current OpenGL context: %@", [NSOpenGLContext currentContext]);
		[gameView initialiseGLWithSize:(NSSize){ _width, _height }];
		[UNIVERSE forceLightSwitch];	// Avoid lighting glitch when switching to full screen. FIXME: can we move this to MyOpenGLView so we don't need to know about Universe here?
		
		/*	Now that we've got the screen, we enter a loop in which we
			alternately process input events and computer and render the next
			frame of our animation. The shift here is from a model in which we
			passively receive events handed to us by the AppKit to one in which
			we are actively driving event processing.
		*/
		_stayInFullScreenMode = YES;
		
		BOOL pastFirstMouseDelta = NO;
		
		OOActionBlock frameAction = self.frameAction;
		if (frameAction == NULL)  frameAction = ^{};
		
		while (_stayInFullScreenMode)
		{
			NSAutoreleasePool *pool = [NSAutoreleasePool new];
			
			// Check for and process input events.
			NSEvent *event = nil;
			while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]))
			{
				switch (event.type)
				{
					case NSLeftMouseDown:
						[gameView mouseDown:event];
						break;
						
					case NSRightMouseDown:
						mouseX = mouseY = 0;
						[gameView setVirtualJoystick:0.0 :0.0];
						pastFirstMouseDelta = NO;
						break;
						
					case NSLeftMouseUp:
						[gameView mouseUp:event];
						break;
						
					case NSMouseMoved:
					case NSLeftMouseDragged:
				//	case NSRightMouseDragged:	// avoid conflict with NSRightMouseDown
					case NSOtherMouseDragged:
					{
						int32_t mouseDx = 0, mouseDy = 0;
						CGGetLastMouseDelta(&mouseDx, &mouseDy);
						if (pastFirstMouseDelta)
						{
							mouseX += mouseDx;
							mouseY += mouseDy;
						}
						else
						{
							pastFirstMouseDelta = YES;
						}
						
						[gameView setVirtualJoystick:(double)mouseX/_width :(double)mouseY/_height];
						[self recenterCursor];
						break;
					}
						
					case NSKeyDown:
						[gameView keyDown:event];
						break;
						
					case NSFlagsChanged:
						[gameView flagsChanged:event];
						break;
						
					case NSKeyUp:
						[gameView keyUp:event];
						break;
						
					default:
						break;
				}
			}
			
			// Update our stuff.
			frameAction();
			
			[context flushBuffer];
			
			// Clean up any autoreleased objects that were created this time through the loop.
			[pool drain];
		}
		
		/*	Clear the front and back framebuffers before switching out of full-
			screen mode. (This is not strictly necessary, but avoids an untidy
			flash of garbage.)
		*/
		OOGL(glClearColor(0.0f, 0.0f, 0.0f, 0.0f));
		OOGL(glClear(GL_COLOR_BUFFER_BIT));
		[context flushBuffer];
		OOGL(glClear(GL_COLOR_BUFFER_BIT));
		[context flushBuffer];
		
		// Restore the previously set swap interval.
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &savedSwapInterval);
		
		// Exit full-screen mode and release our full-screen NSOpenGLContext.
		[NSOpenGLContext clearCurrentContext];
		[context clearDrawable];
		self.fullScreenContext = nil;
		
		if (!_switchRez)
		{
			// set screen resolution back to the original one (windowed mode).
			err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)self.originalDisplayMode);
			if (err != CGDisplayNoErr)
			{
				OOLog(@"display.mode.switch.failed", @"***** Unable to change display for windowed mode.");
				return;
			}
			
			// show the cursor
			CGDisplayShowCursor(kCGDirectMainDisplay);
			
			// Release control of the displays.
			CGReleaseAllDisplays();
		}
		
		_state = kStateNominallyFullScreen;
		
		/*	Mark our view as needing drawing. (The animation has advanced while
			we were in full-screen mode, so its current contents are stale.)
		*/
		[gameView setNeedsDisplay:YES];
		
		if (self.suspendAction != NULL)
		{
			[self dispatchSuspendAction];
		}
		else
		{
			break;
		}
	}
	
	if(_switchRez)
	{
		_switchRez = NO;
		_switchRezDeferred = YES;
	}
	
	_state = kStateNotFullScreen;
}


- (void) recenterCursor
{
	CGDisplayMoveCursorToPoint(kCGDirectMainDisplay, (CGPoint){ _width / 2.0f, _height / 2.0f });
}


- (void) dispatchSuspendAction
{
	OOActionBlock action = self.suspendAction;
	if (action != NULL)
	{
		action();
		self.suspendAction = nil;
	}
}

@end


static NSComparisonResult CompareDisplayModes(id arg1, id arg2, void *context)
{
	NSDictionary *mode1 = (NSDictionary *)arg1;
	NSDictionary *mode2 = (NSDictionary *)arg2;
	OOUInteger size1, size2;
	
	// Sort first on pixel count...
	size1 = [mode1 oo_unsignedIntegerForKey:kOODisplayWidth] * [mode1 oo_unsignedIntegerForKey:kOODisplayHeight];
	size2 = [mode2 oo_unsignedIntegerForKey:kOODisplayWidth] * [mode2 oo_unsignedIntegerForKey:kOODisplayHeight];
	
	// ...then on refresh rate.
	if (size1 == size2)
	{
		size1 = [mode1 oo_unsignedIntegerForKey:kOODisplayRefreshRate];
		size2 = [mode2 oo_unsignedIntegerForKey:kOODisplayRefreshRate];
	}
	
	if (size1 < size2)  return NSOrderedAscending;
	if (size1 > size2)  return NSOrderedDescending;
	return NSOrderedSame;
}

#endif
