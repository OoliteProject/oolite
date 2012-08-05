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

#if OOLITE_MAC_OS_X && !OOLITE_64_BIT

#import "OOCollectionExtractors.h"
#import "MyOpenGLView.h"
#import "Universe.h"


@implementation GameController (FullScreen)

static NSComparisonResult CompareDisplayModes(id arg1, id arg2, void *context)
{
	NSDictionary *mode1 = (NSDictionary *)arg1;
	NSDictionary *mode2 = (NSDictionary *)arg2;
	int size1, size2;
	
	// Sort first on pixel count
	size1 = [mode1 oo_intForKey:kOODisplayWidth] *
			[mode1 oo_intForKey:kOODisplayHeight];
	size2 = [mode2 oo_intForKey:kOODisplayWidth] *
			[mode2 oo_intForKey:kOODisplayHeight];
	
	// Then on refresh rate
	if (size1 == size2)
	{
		size1 = [mode1 oo_intForKey:kOODisplayRefreshRate];
		size2 = [mode2 oo_intForKey:kOODisplayRefreshRate];
	}

	return (size1 < size2) ? NSOrderedAscending
		 : (size1 > size2) ? NSOrderedDescending
		 : NSOrderedSame;
}


- (void) setUpDisplayModes
{
	unsigned			modeIndex, modeCount;
	NSArray				*modes = nil;
	NSDictionary		*mode = nil, *mode2 = nil;
	unsigned			modeWidth, modeHeight, color;
	unsigned			modeWidth2, modeHeight2, color2;
	BOOL				stretched, stretched2, interlaced, interlaced2;
	float				modeRefresh, modeRefresh2;
	NSUserDefaults		*userDefaults = nil;
	BOOL				deleteFirst;
	
	// Load preferences.
	userDefaults = [NSUserDefaults standardUserDefaults];
	width = [userDefaults oo_intForKey:@"display_width" defaultValue:DISPLAY_DEFAULT_WIDTH];
	height = [userDefaults oo_intForKey:@"display_height" defaultValue:DISPLAY_DEFAULT_HEIGHT];
	refresh = [userDefaults oo_intForKey:@"display_refresh" defaultValue:DISPLAY_DEFAULT_REFRESH];
	fullscreen = [userDefaults oo_boolForKey:@"fullscreen" defaultValue:NO];
	
	// Get the list of all available modes
	modes = (NSArray *)CGDisplayAvailableModes(kCGDirectMainDisplay);
	
	// Filter out modes that we don't want
	displayModes = [[NSMutableArray alloc] init];
	modeCount = [modes count];
	for (modeIndex = 0; modeIndex < modeCount; modeIndex++)
	{
		mode = [modes objectAtIndex: modeIndex];
		modeWidth = [mode oo_unsignedIntForKey:kOODisplayWidth];
		modeHeight = [mode oo_unsignedIntForKey:kOODisplayHeight];
		color = [mode oo_unsignedIntForKey:kOODisplayBitsPerPixel];
	//	modeRefresh = [mode oo_floatForKey:kOODisplayRefreshRate];
		
		if (color < DISPLAY_MIN_COLOURS ||
			modeWidth < DISPLAY_MIN_WIDTH ||
			modeWidth > DISPLAY_MAX_WIDTH ||
			modeHeight < DISPLAY_MIN_HEIGHT ||
			modeHeight > DISPLAY_MAX_HEIGHT)
			continue;
		[displayModes addObject: mode];
	}
	
	// Sort the filtered modes
	[displayModes sortUsingFunction:CompareDisplayModes context:NULL];
	
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
	unsigned int mode2Index = 0;
	for (modeIndex = 0; modeIndex + 1 < [displayModes count]; modeIndex++)
	{
		mode = [displayModes objectAtIndex:modeIndex];
		modeWidth = [mode oo_unsignedIntForKey:kOODisplayWidth];
		modeHeight = [mode oo_unsignedIntForKey:kOODisplayHeight];
		modeRefresh = [mode oo_floatForKey:kOODisplayRefreshRate];
		color = [mode oo_unsignedIntForKey:kOODisplayBitsPerPixel];
		stretched = [mode oo_boolForKey:(NSString *)kCGDisplayModeIsStretched];
		interlaced = [mode oo_boolForKey:(NSString *)kCGDisplayModeIsInterlaced];
		
		for (mode2Index = modeIndex + 1; mode2Index < [displayModes count]; ++mode2Index)
		{
			mode2 = [displayModes objectAtIndex:mode2Index];
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
					[displayModes removeObjectAtIndex:modeIndex];
					modeIndex--;
					break;
				}
				else
				{
					[displayModes removeObjectAtIndex:mode2Index];
					mode2Index--;
				}
			}
		}
	}
	
	if ([displayModes count] == 0)
	{
		[NSException raise:@"OoliteNoDisplayModes"
					format:@"No acceptable display modes could be found!"];
	}
	
	fullscreenDisplayMode = [self findDisplayModeForWidth:width Height:height Refresh:refresh];
	if (fullscreenDisplayMode == nil)
	{
		// set full screen mode to first available mode
		fullscreenDisplayMode = [displayModes objectAtIndex:0];
		width = [[fullscreenDisplayMode objectForKey:kOODisplayWidth] intValue];
		height = [[fullscreenDisplayMode objectForKey:kOODisplayHeight] intValue];
		refresh = [[fullscreenDisplayMode objectForKey:kOODisplayRefreshRate] intValue];
	}
}


- (IBAction) goFullscreen:(id)sender
{
	CGLContextObj	cglContext;
	CGDisplayErr	err;
	GLint			oldSwapInterval;
	GLint			newSwapInterval;
	int32_t			mouse_dx, mouse_dy;
	
	// empty the event queue and strip all keys - stop problems with hangover keys
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		
		while ([NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES] != NULL)  {}
		
		[pool release];
		[gameView clearKeys];
	}
	
	my_mouse_x = my_mouse_y = 0;
	
	for (;;)
	{
		CGPoint centerOfScreen = CGPointMake(width/2.0F,height/2.0F);

		pauseTarget = nil;
		
		//get the appropriate display mode for the selected values
		
		fullscreenDisplayMode = [self findDisplayModeForWidth:width Height:height Refresh:refresh];
		if (fullscreenDisplayMode == nil)
		{
			OOLog(@"display.mode.noneFound", @"***** unable to find suitable full screen mode");
			return;
		}
		
		originalDisplayMode = (NSDictionary *)CGDisplayCurrentMode(kCGDirectMainDisplay);
		
		NSMutableData *attrData = [[[gameView pixelFormatAttributes] mutableCopy] autorelease];
		NSOpenGLPixelFormatAttribute *attrs = [attrData mutableBytes];
		NSAssert(attrs[0] == NSOpenGLPFAWindow, @"Pixel format does not meet expectations. Exiting.");
		attrs[0] = NSOpenGLPFAFullScreen;
		
		GLint rendererID;
		
		// Create the FullScreen NSOpenGLContext with the attributes listed above.
		NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
		
		// Just as a diagnostic, report the renderer ID that this pixel format binds to.  CGLRenderers.h contains a list of known renderers and their corresponding RendererID codes.
		[pixelFormat getValues:&rendererID forAttribute:NSOpenGLPFARendererID forVirtualScreen:0];

		// Create an NSOpenGLContext with the FullScreen pixel format.  By specifying the non-FullScreen context as our "shareContext", we automatically inherit all of the textures, display lists, and other OpenGL objects it has defined.
		fullScreenContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:[gameView openGLContext]];
		DESTROY(pixelFormat);

		if (fullScreenContext == nil)
		{
			OOLog(@"display.context.create.failed", @"***** Failed to create fullScreenContext");
			return;
		}
		

		// Pause animation in the OpenGL view.  While we're in full-screen mode, we'll drive the animation actively
		// instead of using a timer callback.
		if (timer)
			[self stopAnimationTimer];

		// Take control of the display where we're about to go FullScreen.
		// this stops windows from being shuffled around.
		err = CGCaptureAllDisplays();
		if (err != CGDisplayNoErr)
		{
			[fullScreenContext release];
			fullScreenContext = nil;
			return;
		}

		// switch resolution!
		err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)fullscreenDisplayMode);
		if (err != CGDisplayNoErr)
		{
			OOLog(@"display.mode.switch.failed", @"***** Unable to change display for fullscreen mode.");
			return;
		}
		
		// Hide the cursor
		CGDisplayMoveCursorToPoint(kCGDirectMainDisplay,centerOfScreen);
		if (CGCursorIsVisible()) CGDisplayHideCursor(kCGDirectMainDisplay);
		
		// Enter FullScreen mode and make our FullScreen context the active context for OpenGL commands.
		[fullScreenContext setFullScreen];
		[fullScreenContext makeCurrentContext];
		
		// Save the current swap interval so we can restore it later, and then set the new swap interval to lock us to the display's refresh rate.
		cglContext = CGLGetCurrentContext();
		CGLGetParameter(cglContext, kCGLCPSwapInterval, &oldSwapInterval);
		newSwapInterval = 1;
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &newSwapInterval);
		
		fullscreen = YES;
		
		// Tell the scene the dimensions of the area it's going to render to, so it can set up an appropriate viewport and viewing transformation.
		[gameView initialiseGLWithSize:NSMakeSize(width,height)];
		
		// Now that we've got the screen, we enter a loop in which we alternately process input events and computer and render the next frame of our animation.
		// The shift here is from a model in which we passively receive events handed to us by the AppKit to one in which we are actively driving event processing.
		stayInFullScreenMode = YES;
		
		[gameView clearCommandF];	// Avoid immediately switching back to windowed mode.
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"fullscreen"];
		
		[UNIVERSE forceLightSwitch];	// Avoid lighting glitch when switching to full screen.
						
		BOOL past_first_mouse_delta = NO;
		
		while (stayInFullScreenMode)
		{
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

			// Check for and process input events.
			NSEvent *event;
			while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]))
			{
				switch ([event type])
				{
					case NSLeftMouseDown:
						[gameView mouseDown:event];
						break;

					case NSRightMouseDown:
						[self recenterVirtualJoystick];
						past_first_mouse_delta = NO;
						break;

					case NSLeftMouseUp:
						[gameView mouseUp:event];
						break;
					
					case NSMouseMoved:
					case NSLeftMouseDragged:
//					case NSRightMouseDragged:	// avoid conflict with NSRightMouseDown
					case NSOtherMouseDragged:
						CGGetLastMouseDelta(&mouse_dx, &mouse_dy);
						if (past_first_mouse_delta)
						{
							my_mouse_x += mouse_dx;
							my_mouse_y += mouse_dy;
						}
						else  past_first_mouse_delta =YES;
						
						[gameView setVirtualJoystick:(double)my_mouse_x/width :(double)my_mouse_y/height];
						CGDisplayMoveCursorToPoint(kCGDirectMainDisplay,centerOfScreen);
						break;
					
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
			[self performGameTick:self];

			[fullScreenContext flushBuffer];

			// Clean up any autoreleased objects that were created this time through the loop.
			[pool release];
		}
		
		// Clear the front and back framebuffers before switching out of FullScreen mode.
		// (This is not strictly necessary, but avoids an untidy flash of garbage.)
		OOGL(glClearColor(0.0f, 0.0f, 0.0f, 0.0f));
		OOGL(glClear(GL_COLOR_BUFFER_BIT));
		[fullScreenContext flushBuffer];
		OOGL(glClear(GL_COLOR_BUFFER_BIT));
		[fullScreenContext flushBuffer];
		
		// Restore the previously set swap interval.
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &oldSwapInterval);
		
		// Exit fullscreen mode and release our FullScreen NSOpenGLContext.
		[NSOpenGLContext clearCurrentContext];
		[fullScreenContext clearDrawable];
		[fullScreenContext release];
		fullScreenContext = nil;

		if (!_switchRez)
		{
			// set screen resolution back to the original one (windowed mode).
			err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)originalDisplayMode);
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
		
		fullscreen = NO;
		
		// Resume animation timer firings.
		[self startAnimationTimer];
		
		// Mark our view as needing drawing.  (The animation has advanced while we were in FullScreen mode, so its current contents are stale.)
		[gameView setNeedsDisplay:YES];
		
		if (pauseTarget)
		{
			[pauseTarget performSelector:pauseSelector];
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
}


- (void) changeFullScreenResolution
{
	_switchRez = YES;
	stayInFullScreenMode = NO;	// Close the present fullScreenContext before creating the new one.
}


- (void) exitFullScreenMode
{
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"fullscreen"];
	stayInFullScreenMode = NO;
}


- (BOOL) inFullScreenMode
{
	return fullscreen;
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


- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int) d_refresh
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


- (OOUInteger) indexOfCurrentDisplayMode
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
