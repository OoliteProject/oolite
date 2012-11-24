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


/*	OS X apps are permitted to assume 800x600 screens. Under OS X, we always
	start up in windowed mode. Therefore, the default size fits an 800x600
	screen and leaves space for the menu bar and title bar.
*/
#define DISPLAY_DEFAULT_WIDTH	800
#define DISPLAY_DEFAULT_HEIGHT	540
#define DISPLAY_DEFAULT_REFRESH	75


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

- (void) beginFullScreenMode;
- (void) runFullScreenModalEventLoopInner;

- (void) recenterCursor;

- (void) hideCursor;
- (void) showCursor;

@end


@implementation OOMacLegacyFullScreenController

@synthesize delegate = _delegate;
@synthesize fullScreenDisplayMode = _fullScreenDisplayMode;
@synthesize originalDisplayMode = _originalDisplayMode;
@synthesize fullScreenContext = _fullScreenContext;


- (id) initWithGameView:(MyOpenGLView *)view
{
	if ((self = [super initWithGameView:view]))
	{
		NSArray				*modes = nil;
		NSDictionary		*mode = nil, *mode2 = nil;
		NSUInteger			modeWidth, modeHeight, color;
		NSUInteger			modeWidth2, modeHeight2, color2;
		bool				stretched, stretched2, interlaced, interlaced2;
		float				modeRefresh, modeRefresh2;
		bool				deleteFirst;
		
		// Initial settings are current settings of screen.
		NSDictionary *currentMode = (NSDictionary *)CGDisplayCurrentMode(kCGDirectMainDisplay);
		_width = [currentMode oo_unsignedIntegerForKey:kOODisplayWidth];
		_height = [currentMode oo_unsignedIntegerForKey:kOODisplayHeight];
		_refresh = [currentMode oo_unsignedIntegerForKey:kOODisplayRefreshRate];
		
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
		NSUInteger modeIndex, mode2Index;
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
					deleteFirst = false;
					if (color < color2)  deleteFirst = true;
					else if (color == color2)
					{
						if (stretched && !stretched2)  deleteFirst = true;
						else if (stretched == stretched2)
						{
							if (interlaced && !interlaced2)  deleteFirst = true;
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
	DESTROY(_displayModes);
	DESTROY(_originalDisplayMode);
	DESTROY(_fullScreenDisplayMode);
	DESTROY(_fullScreenContext);
	
	[super dealloc];
}


- (BOOL) inFullScreenMode
{
	return _state != kStateNotFullScreen;
}


- (NSString *) stateString
{
	// TEMP - for display.macLegacy (Also, there's a temp display.macLegacy in logcontrol.plist)
	NSString *result = nil;
	switch (_state)
	{
		case kStateNotFullScreen: result = @"kStateNotFullScreen"; break;
		case kStateNominallyFullScreen: result = @"kStateNominallyFullScreen"; break;
		case kStateActuallyFullScreen: result = @"kStateActuallyFullScreen"; break;
	}
	if (result == nil)  result = [NSString stringWithFormat:@"<unknown state %i>", _state];
	
	if (_stayInFullScreenMode)  result = [result stringByAppendingString:@", stayInFullScreenMode"];
	if (_callSuspendAction)  result = [result stringByAppendingString:@", callSuspendAction"];
	if (_switchRez)  result = [result stringByAppendingString:@", switchRez"];
	if (_cursorHidden)  result = [result stringByAppendingString:@", cursorHidden"];
	
	return result;
}


- (void) setFullScreenMode:(BOOL)value
{
	OODebugLog(@"display.macLegacy.state", @"-setFullScreenMode:%@ called in state %@.", value ? @"YES" : @"NO", self.stateString);
	OOLogIndentIf(@"display.macLegacy");
	
	if (!value && self.fullScreenMode)
	{
		OODebugLog(@"display.macLegacy.state", @"Should switch FROM full screen mode; _stayInFullScreenMode set to NO.");
		_stayInFullScreenMode = false;
	}
	else if (value && !self.fullScreenMode)
	{
		OODebugLog(@"display.macLegacy.state", @"Should switch TO full screen mode; calling -beginFullScreenMode.");
		OOLogIndentIf(@"display.macLegacy");
		[self beginFullScreenMode];
		OOLogOutdentIf(@"display.macLegacy");
	}
	OOLogOutdentIf(@"display.macLegacy");
}

- (NSArray *) displayModes
{
	return [NSArray arrayWithArray:_displayModes];
}


- (NSUInteger) indexOfCurrentDisplayMode
{
	NSDictionary *mode = [self findDisplayModeForWidth:_width height:_height refreshRate:_refresh];
	if (mode == nil)  return NSNotFound;
	else  return [_displayModes indexOfObject:mode];
}


- (BOOL) setDisplayWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(NSUInteger)refresh
{
	OODebugLog(@"display.macLegacy.state", @"%@ called in state %@.", NSStringFromSelector(_cmd), self.stateString);
	NSDictionary *mode = [self findDisplayModeForWidth:width height:height refreshRate:refresh];
	if (mode != nil)
	{
		_width = width;
		_height = height;
		_refresh = refresh;
		self.fullScreenDisplayMode = mode;
		
		if (self.fullScreenMode)
		{
			// Trigger mode switch.
			_stayInFullScreenMode = false;
			_switchRez = true;
		}
		
		return YES;
	}
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(NSUInteger)refresh
{
	OODebugLog(@"display.macLegacy.state", @"%@ called in state %@.", NSStringFromSelector(_cmd), self.stateString);
	
	for (NSDictionary *mode in _displayModes)
	{
		NSUInteger modeWidth = [mode oo_unsignedIntegerForKey:kOODisplayWidth];
		NSUInteger modeHeight = [mode oo_unsignedIntegerForKey:kOODisplayHeight];
		NSUInteger modeRefresh = [mode oo_unsignedIntegerForKey:kOODisplayRefreshRate];
		
		if ((modeWidth == width) && (modeHeight == height) && (modeRefresh == refresh))
		{
			return mode;
		}
	}
	return nil;
}


- (void) runFullScreenModalEventLoop
{
	OODebugLog(@"display.macLegacy.state", @"%@ called in state %@.", NSStringFromSelector(_cmd), self.stateString);
	NSAssert(_state == kStateNominallyFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	@try
	{
		[self runFullScreenModalEventLoopInner];
		
	}
	@finally
	{
		_state = kStateNotFullScreen;
		self.fullScreenContext = nil;
	}
	
	OODebugLog(@"display.macLegacy.state", @"%@ exiting in state %@.", NSStringFromSelector(_cmd), self.stateString);
}


- (void) suspendFullScreen
{
	OODebugLog(@"display.macLegacy.state", @"%@ called in state %@.", NSStringFromSelector(_cmd), self.stateString);
	NSAssert(_state != kStateNotFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	_stayInFullScreenMode = false;
	_callSuspendAction = true;
	
	OODebugLog(@"display.macLegacy.state", @"%@ exiting in state %@.", NSStringFromSelector(_cmd), self.stateString);
}


#pragma mark - Actual full screen mode handling

- (void) beginFullScreenMode
{
	OODebugLog(@"display.macLegacy.state", @"%@ called in state %@.", NSStringFromSelector(_cmd), self.stateString);
	NSAssert(_state == kStateNotFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	NSAutoreleasePool *setupPool = [NSAutoreleasePool new];
	
	self.fullScreenDisplayMode = [self findDisplayModeForWidth:_width height:_height refreshRate:_refresh];
	if (self.fullScreenDisplayMode == nil)
	{
		OOLogERR(@"display.mode.noneFound", @"Unable to find suitable full screen mode.");
		return;
	}
	
	self.originalDisplayMode = (NSDictionary *)CGDisplayCurrentMode(kCGDirectMainDisplay);
	
	OODebugLog(@"display.macLegacy.state", @"In -beginFullScreenMode; target mode found, switching state to nominally full screen.");
	
	_state = kStateNominallyFullScreen;
	_callSuspendAction = false;
	
	// empty the event queue and strip all keys - stop problems with hangover keys
	while ([NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES] != NULL)  {}
	[self.gameView clearKeys];
	[self.gameView clearCommandF];	// Avoid immediately switching back to windowed mode.
	
	[setupPool drain];
	
	OODebugLog(@"display.macLegacy.state", @"%@ exiting in state %@.", NSStringFromSelector(_cmd), self.stateString);
}


- (void) runFullScreenModalEventLoopInner
{
	OODebugLog(@"display.macLegacy.state", @"%@ called in state %@.", NSStringFromSelector(_cmd), self.stateString);
	NSAssert(_state == kStateNominallyFullScreen, @"Internal usage error: %s called in wrong state.", __FUNCTION__);
	
	int32_t mouseX = 0, mouseY = 0;
	
	MyOpenGLView *gameView = self.gameView;
	
	NSMutableData *attrData = [[gameView.pixelFormatAttributes mutableCopy] autorelease];
	NSOpenGLPixelFormatAttribute *attrs = [attrData mutableBytes];
	NSAssert(attrs[0] == NSOpenGLPFAWindow, @"Pixel format does not meet expectations.");
	attrs[0] = NSOpenGLPFAFullScreen;
	
	NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
	[pixelFormat autorelease];
	
	OODebugLog(@"display.macLegacy.state", @"Entering outer full screen loop in state %@.", self.stateString);
	OOLogIndentIf(@"display.macLegacy");
	
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
		
		/*	Take control of the display where we're about to go full-screen.
			this stops windows from being shuffled around.
		*/
		OODebugLog(@"display.macLegacy.capture", @"Capturing all displays.");
		CGDisplayErr err = CGCaptureAllDisplays();
		if (err != CGDisplayNoErr)
		{
			OOLogERR(@"display.context.create.failed", @"Failed to capture displays.");
			return;
		}
		
		// switch resolution!
		OODebugLog(@"display.macLegacy.switch", @"Switching to display mode %@", self.fullScreenDisplayMode);
		err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)self.fullScreenDisplayMode);
		if (err != CGDisplayNoErr)
		{
			OOLogERR(@"display.mode.switch.failed", @"Unable to change display for full-screen mode.");
			return;
		}
		
		// Hide the cursor.
		[self hideCursor];
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
		OODebugLog(@"display.macLegacy.setSwapInterval", @"Setting swap interval to 1.");
		CGLContextObj cglContext = CGLGetCurrentContext();
		GLint savedSwapInterval;
		CGLGetParameter(cglContext, kCGLCPSwapInterval, &savedSwapInterval);
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &(GLint){1});
		
		/*	Tell the scene the dimensions of the area it's going to render to,
			so it can set up an appropriate viewport and viewing transformation.
		*/
		[gameView initialiseGLWithSize:(NSSize){ _width, _height }];
		[UNIVERSE forceLightSwitch];	// Avoid lighting glitch when switching to full screen. FIXME: can we move this to MyOpenGLView so we don't need to know about Universe here?
		
		/*	Now that we've got the screen, we enter a loop in which we
			alternately process input events and computer and render the next
			frame of our animation. The shift here is from a model in which we
			passively receive events handed to us by the AppKit to one in which
			we are actively driving event processing.
		*/
		_stayInFullScreenMode = true;
		
		bool pastFirstMouseDelta = false;
		
		OODebugLog(@"display.macLegacy.state", @"Entering main full screen loop in state %@.", self.stateString);
		OOLogIndentIf(@"display.macLegacy");
		
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
						pastFirstMouseDelta = false;
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
							pastFirstMouseDelta = true;
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
			[self.delegate handleFullScreenFrameTick];
			
			[context flushBuffer];
			
			// Clean up any autoreleased objects that were created this time through the loop.
			[pool drain];
		}
		
		OOLogOutdentIf(@"display.macLegacy");
		OODebugLog(@"display.macLegacy.state", @"Exited main full screen loop in state %@.", self.stateString);
		
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
		OODebugLog(@"display.macLegacy.setSwapInterval", @"Restoring old swap interval (%i).", savedSwapInterval);
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &savedSwapInterval);
		
		// Exit full-screen mode and release our full-screen NSOpenGLContext.
		[NSOpenGLContext clearCurrentContext];
		[context clearDrawable];
		self.fullScreenContext = nil;
		
		if (!_switchRez)
		{
			// set screen resolution back to the original one (windowed mode).
			OODebugLog(@"display.macLegacy.switch", @"Switching back to original display mode %@", self.originalDisplayMode);
			err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)self.originalDisplayMode);
			if (err != CGDisplayNoErr)
			{
				OOLog(@"display.mode.switch.failed", @"***** Unable to change display for windowed mode.");
				return;
			}
			
			// show the cursor
			[self showCursor];
			
			// Release control of the displays.
			OODebugLog(@"display.macLegacy.capture", @"Releasing display capture.");
			CGReleaseAllDisplays();
		}
		
		_state = kStateNominallyFullScreen;
		
		/*	Mark our view as needing drawing. (The animation has advanced while
			we were in full-screen mode, so its current contents are stale.)
		*/
		[gameView setNeedsDisplay:YES];
		
		if (_callSuspendAction)
		{
			OODebugLog(@"display.macLegacy.state", @"callSuspendAction set; calling delegate handleFullScreenSuspendedAction.");
			_callSuspendAction = false;
			[self.delegate handleFullScreenSuspendedAction];
		}
		else
		{
			if (_switchRez)
			{
				OODebugLog(@"display.macLegacy.state", @"switchRez set; calling delegate scheduleFullScreenModeRestart.");
				_switchRez = false;
				[self.delegate scheduleFullScreenModeRestart];
			}
			
			break;
		}
	}
	
	OOLogOutdentIf(@"display.macLegacy");
	OODebugLog(@"display.macLegacy.state", @"Exited outer full screen loop in state %@.", self.stateString);
	
	_state = kStateNotFullScreen;
		
	OODebugLog(@"display.macLegacy.state", @"%@ exiting in state %@.", NSStringFromSelector(_cmd), self.stateString);
}


- (void) recenterCursor
{
	CGDisplayMoveCursorToPoint(kCGDirectMainDisplay, (CGPoint){ _width / 2.0f, _height / 2.0f });
}


- (void) hideCursor
{
	if (!_cursorHidden)
	{
		OODebugLog(@"display.macLegacy.cursor", @"Hiding cursor.");
		CGDisplayHideCursor(kCGDirectMainDisplay);
		_cursorHidden = true;
	}
}


- (void) showCursor
{
	if (_cursorHidden)
	{
		OODebugLog(@"display.macLegacy.cursor", @"Showing cursor.");
		CGDisplayShowCursor(kCGDirectMainDisplay);
		_cursorHidden = false;
	}
}

@end


static NSComparisonResult CompareDisplayModes(id arg1, id arg2, void *context)
{
	NSDictionary *mode1 = arg1;
	NSDictionary *mode2 = arg2;
	NSUInteger size1, size2;
	
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
