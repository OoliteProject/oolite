/*

GameController.m

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

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
#import "Universe.h"
#import "ResourceManager.h"
#import "MyOpenGLView.h"
#import "OOSound.h"
#import "OOOpenGL.h"
#import "PlayerEntityLoadSave.h"
#import <stdlib.h>
#import "OOCollectionExtractors.h"
#import "OOOXPVerifier.h"
#import "OOLoggingExtended.h"

#define kOOLogUnconvertedNSLog @"unclassified.GameController"


static GameController *sSharedController = nil;


@interface GameController (OOPrivate)

- (void) getDisplayModes;

- (void)reportUnhandledStartupException:(NSException *)exception;

- (void)performGameTick:(id)userInfo;
- (void)doPerformGameTick;

@end


@implementation GameController

+ (id)sharedController
{
	if (sSharedController == nil)  [[self alloc] init];
	return sSharedController;
}


- (id) init
{
	if (sSharedController != nil)
	{
		[self release];
		[NSException raise:NSInternalInconsistencyException format:@"%s: expected only one GameController to exist at a time.", __FUNCTION__];
	}
	
	self = [super init];
	sSharedController = self;
	
	last_timeInterval = [NSDate timeIntervalSinceReferenceDate];
	delta_t = 0.01; // one hundredth of a second
	//
	my_mouse_x = my_mouse_y = 0;
	//
	playerFileToLoad = nil;
	playerFileDirectory = nil;
	expansionPathsToInclude = nil;
	pauseSelector = (SEL)nil;
	pauseTarget = nil;
	gameIsPaused = NO;
	
	return self;
}


- (void) dealloc
{
#if OOLITE_HAVE_APPKIT
	[[[NSWorkspace sharedWorkspace] notificationCenter]	removeObserver:UNIVERSE];
#endif
	
	[timer release];
	[gameView release];
	[UNIVERSE release];
	
	[playerFileToLoad release];
	[playerFileDirectory release];
	[expansionPathsToInclude release];
	
	[super dealloc];
}


- (BOOL) gameIsPaused
{
	return gameIsPaused;
}


- (void) pause_game
{
	gameIsPaused = YES;
}


- (void) unpause_game
{
	gameIsPaused = NO;
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


- (NSArray *) displayModes
{
	return [NSArray arrayWithArray:displayModes];
}


- (MyOpenGLView *) gameView
{
	return gameView;
}


- (void) setGameView:(MyOpenGLView *)view
{
	[gameView release];
	gameView = [view retain];
	[UNIVERSE setGameView:gameView];
	[gameView setGameController:self];
}


- (void) applicationDidFinishLaunching:(NSNotification *)notification
{
	NSAutoreleasePool	*pool = nil;
	unsigned			i;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	NS_DURING
#if !OOLITE_HAVE_APPKIT
		gameView = [MyOpenGLView alloc];
		[gameView init];
		[gameView setGameController:self];
#endif
		
		// ensure the gameView is drawn to, so OpenGL is initialised and so textures can initialse.
		[gameView drawRect:[gameView bounds]];
		
		[self beginSplashScreen];
		
#if OO_OXP_VERIFIER_ENABLED
		if ([OOOXPVerifier runVerificationIfRequested])
		{
			[self exitApp];
		}
#endif
		
		[self logProgress:@"getting display modes..."];
		[self getDisplayModes];
		
		// moved to before the Universe is created
		if (expansionPathsToInclude)
		{
			[self logProgress:@"loading selected expansion packs..."];
			for (i = 0; i < [expansionPathsToInclude count]; i++)
			{
				[ResourceManager addExternalPath: (NSString*)[expansionPathsToInclude objectAtIndex: i]];
			}
		}
		
		// moved here to try to avoid initialising this before having an Open GL context
		[self logProgress:@"initialising universe..."];
		[[Universe alloc] initWithGameView:gameView];
		
		[self logProgress:@"loading player..."];
		[self loadPlayerIfRequired];
		
		// get the run loop and add the call to performGameTick:
		[self startAnimationTimer];
		
		[self endSplashScreen];
	NS_HANDLER
		[self reportUnhandledStartupException:localException];
		exit(EXIT_FAILURE);
	NS_ENDHANDLER
	
	// Release anything allocated above that is not required.
	[pool release];
	
#if !OOLITE_HAVE_APPKIT
	[[NSRunLoop currentRunLoop] run];
#endif
}


- (void) loadPlayerIfRequired
{
	if (playerFileToLoad)
	{
		PlayerEntity	*player = [PlayerEntity sharedPlayer];
		[player loadPlayerFromFile:playerFileToLoad];
		[player setStatus:STATUS_DOCKED];
		[player setGuiToStatusScreen];
	}
}


- (void) beginSplashScreen
{
	// Nothing to do
}


#if OOLITE_HAVE_APPKIT

- (void) performGameTick:(id)userInfo
{
	[self doPerformGameTick];
}

#else

- (void) performGameTick:(id)sender
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[gameView pollControls];
	[self doPerformGameTick];
	
	[pool release];
	
}

#endif


- (void)doPerformGameTick
{
	if (gameIsPaused)
		delta_t = 0.0;  // no movement!
	else
	{
		delta_t = [NSDate timeIntervalSinceReferenceDate] - last_timeInterval;
		last_timeInterval += delta_t;
		if (delta_t > MINIMUM_GAME_TICK)
			delta_t = MINIMUM_GAME_TICK;		// peg the maximum pause (at 0.5->1.0 seconds) to protect against when the machine sleeps	
	}
	
	[UNIVERSE update:delta_t];
	[OOSound update];
	
#if OOLITE_HAVE_APPKIT
	if (fullscreen)
	{
		[UNIVERSE drawUniverse];
		return;
	}
#endif

	if (gameView != nil)  [gameView display];
	else  OOLog(kOOLogInconsistentState, @"***** gameView not set : delta_t %f",(float)delta_t);
}


- (void) startAnimationTimer
{
	if (timer == nil)
	{   
		NSTimeInterval ti = 0.01;
		timer = [[NSTimer timerWithTimeInterval:ti target:self selector:@selector(performGameTick:) userInfo:nil repeats:YES] retain];
		[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
	}
}


- (void) stopAnimationTimer
{
	if (timer != nil)
	{
		[timer invalidate];
		[timer release];
		timer = nil;
	}
}


#if OOLITE_MAC_OS_X && !OOLITE_SDL
static OOInteger CompareDisplayModes(id arg1, id arg2, void *context)
{
   // TODO: If fullscreen mode is practical in GNUstep
	NSDictionary *mode1 = (NSDictionary *)arg1;
	NSDictionary *mode2 = (NSDictionary *)arg2;
	int size1, size2;
	
	// Sort first on pixel count
	size1 = [[mode1 objectForKey:kOODisplayWidth] intValue] *
			[[mode1 objectForKey:kOODisplayHeight] intValue];
	size2 = [[mode2 objectForKey:kOODisplayWidth] intValue] *
			[[mode2 objectForKey:kOODisplayHeight] intValue];
	if (size1 != size2)  return size1 - size2;

	// Then on refresh rate
	return (int)[[mode1 objectForKey:kOODisplayRefreshRate] intValue] -
		   (int)[[mode2 objectForKey:kOODisplayRefreshRate] intValue];
}


- (void) getDisplayModes
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
	width = [userDefaults intForKey:@"display_width" defaultValue:DISPLAY_DEFAULT_WIDTH];
	height = [userDefaults intForKey:@"display_height" defaultValue:DISPLAY_DEFAULT_HEIGHT];
	refresh = [userDefaults intForKey:@"display_refresh" defaultValue:DISPLAY_DEFAULT_REFRESH];
	
	// Get the list of all available modes
	modes = (NSArray *)CGDisplayAvailableModes(kCGDirectMainDisplay);
	
	// Filter out modes that we don't want
	displayModes = [[NSMutableArray alloc] init];
	modeCount = [modes count];
	for (modeIndex = 0; modeIndex < modeCount; modeIndex++)
	{
		mode = [modes objectAtIndex: modeIndex];
		modeWidth = [mode unsignedIntForKey:(NSString *)kCGDisplayWidth];
		modeHeight = [mode unsignedIntForKey:(NSString *)kCGDisplayHeight];
		color = [mode unsignedIntForKey:(NSString *)kCGDisplayBitsPerPixel];
		modeRefresh = [mode floatForKey:(NSString *)kCGDisplayRefreshRate];
		
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
		modeWidth = [mode unsignedIntForKey:(NSString *)kCGDisplayWidth];
		modeHeight = [mode unsignedIntForKey:(NSString *)kCGDisplayHeight];
		modeRefresh = [mode floatForKey:(NSString *)kCGDisplayRefreshRate];
		color = [mode unsignedIntForKey:(NSString *)kCGDisplayBitsPerPixel];
		stretched = [mode boolForKey:(NSString *)kCGDisplayModeIsStretched];
		interlaced = [mode boolForKey:(NSString *)kCGDisplayModeIsInterlaced];
		
		for (mode2Index = modeIndex + 1; mode2Index < [displayModes count]; ++mode2Index)
		{
			mode2 = [displayModes objectAtIndex:mode2Index];
			modeWidth2 = [mode2 unsignedIntForKey:(NSString *)kCGDisplayWidth];
			modeHeight2 = [mode2 unsignedIntForKey:(NSString *)kCGDisplayHeight];
			modeRefresh2 = [mode2 floatForKey:(NSString *)kCGDisplayRefreshRate];
			color2 = [mode unsignedIntForKey:(NSString *)kCGDisplayBitsPerPixel];
			stretched2 = [mode2 boolForKey:(NSString *)kCGDisplayModeIsStretched];
			interlaced2 = [mode2 boolForKey:(NSString *)kCGDisplayModeIsInterlaced];
			
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


- (IBAction) goFullscreen:(id) sender
{
	CGLContextObj	cglContext;
	CGDisplayErr	err;
	GLint			oldSwapInterval;
	GLint			newSwapInterval;
	CGMouseDelta	mouse_dx, mouse_dy;
	
	// empty the event queue and strip all keys - stop problems with hangover keys
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSEvent *event;
		while ((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantPast] inMode:NSDefaultRunLoopMode dequeue:YES]));
		[pool release];
		[gameView clearKeys];
	}
		
	pauseTarget = sender;
	
	my_mouse_x = my_mouse_y = 0;
	
	while (pauseTarget)
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
		
		// Pixel Format Attributes for the FullScreen NSOpenGLContext
		NSOpenGLPixelFormatAttribute attrs[] = {

			// Specify that we want a full-screen OpenGL context.
			NSOpenGLPFAFullScreen,
//			// and that we want a windowed OpenGL context.
//			NSOpenGLPFAWindow,

			// We may be on a multi-display system (and each screen may be driven by a different renderer), so we need to specify which screen we want to take over.
			// For this demo, we'll specify the main screen.
			NSOpenGLPFAScreenMask, CGDisplayIDToOpenGLDisplayMask(kCGDirectMainDisplay),

			// Specifying "NoRecovery" gives us a context that cannot fall back to the software renderer.
			//This makes the View-based context a compatible with the fullscreen context, enabling us to use the "shareContext"
			// feature to share textures, display lists, and other OpenGL objects between the two.
			NSOpenGLPFANoRecovery,
			
			// Attributes Common to FullScreen and non-FullScreen
			NSOpenGLPFACompliant,
			
			NSOpenGLPFAColorSize, 32,
			NSOpenGLPFADepthSize, 32,
			NSOpenGLPFADoubleBuffer,
			NSOpenGLPFAAccelerated,
#if FSAA
			// Need a preference or other sane way to activate this
			NSOpenGLPFASampleBuffers, 1,
			NSOpenGLPFASamples,4,
#endif
			0
		};
		GLint rendererID;

		// Create the FullScreen NSOpenGLContext with the attributes listed above.
		NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
		
		// Just as a diagnostic, report the renderer ID that this pixel format binds to.  CGLRenderers.h contains a list of known renderers and their corresponding RendererID codes.
		[pixelFormat getValues:&rendererID forAttribute:NSOpenGLPFARendererID forVirtualScreen:0];

		// Create an NSOpenGLContext with the FullScreen pixel format.  By specifying the non-FullScreen context as our "shareContext", we automatically inherit all of the textures, display lists, and other OpenGL objects it has defined.
		fullScreenContext = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:[gameView openGLContext]];
		[pixelFormat release];
		pixelFormat = nil;

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
			OOLog(@"display.mode.switch.failed", @"***** Unable to change display mode.");
			return;
		}
		
		// Hide the cursor
		CGDisplayMoveCursorToPoint(kCGDirectMainDisplay,centerOfScreen);
		CGDisplayHideCursor(kCGDirectMainDisplay);
		
		// Enter FullScreen mode and make our FullScreen context the active context for OpenGL commands.
		[fullScreenContext setFullScreen];
		[fullScreenContext makeCurrentContext];
		
		// Save the current swap interval so we can restore it later, and then set the new swap interval to lock us to the display's refresh rate.
		cglContext = CGLGetCurrentContext();
		CGLGetParameter(cglContext, kCGLCPSwapInterval, &oldSwapInterval);
		newSwapInterval = 1;
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &newSwapInterval);

		// Tell the scene the dimensions of the area it's going to render to, so it can set up an appropriate viewport and viewing transformation.
		[gameView initialiseGLWithSize:NSMakeSize(width,height)];
		
		// Now that we've got the screen, we enter a loop in which we alternately process input events and computer and render the next frame of our animation.
		// The shift here is from a model in which we passively receive events handed to us by the AppKit to one in which we are actively driving event processing.
		stayInFullScreenMode = YES;
		
		fullscreen = YES;
						
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
						my_mouse_x = my_mouse_y = 0;	// center mouse
						past_first_mouse_delta = NO;
						[gameView setVirtualJoystick:0.0 :0.0];
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
		glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		[fullScreenContext flushBuffer];
		glClear(GL_COLOR_BUFFER_BIT);
		[fullScreenContext flushBuffer];

		// Restore the previously set swap interval.
		CGLSetParameter(cglContext, kCGLCPSwapInterval, &oldSwapInterval);

		// Exit fullscreen mode and release our FullScreen NSOpenGLContext.
		[NSOpenGLContext clearCurrentContext];
		[fullScreenContext clearDrawable];
		[fullScreenContext release];
		fullScreenContext = nil;

		// switch resolution back!
		err = CGDisplaySwitchToMode(kCGDirectMainDisplay, (CFDictionaryRef)originalDisplayMode);
		if (err != CGDisplayNoErr)
		{
			OOLog(@"display.mode.switch.failed", @"***** Unable to change display mode.");
			return;
		}
		
		// show the cursor
		CGDisplayShowCursor(kCGDirectMainDisplay);
		
		// Release control of the displays.
		CGReleaseAllDisplays();
		
		fullscreen = NO;
				
		// Resume animation timer firings.
		[self startAnimationTimer];

		// Mark our view as needing drawing.  (The animation has advanced while we were in FullScreen mode, so its current contents are stale.)
		[gameView setNeedsDisplay:YES];
		
		if (pauseTarget)
		{
			[pauseTarget performSelector:pauseSelector];
		}
		
	}
}


- (BOOL) inFullScreenMode
{
	return fullscreen;
}

#elif OOLITE_SDL

- (void) getDisplayModes
{
	// SDL code all lives in the gameview.
	displayModes = [gameView getScreenSizeArray];
	NSSize fsmSize = [gameView currentScreenSize];
	width = fsmSize.width;
	height = fsmSize.height;
}


- (NSDictionary *) findDisplayModeForWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
	int modenum=[gameView findDisplayModeForWidth: d_width Height: d_height Refresh: d_refresh];
	return [displayModes objectAtIndex: modenum];
}


- (void) setFullScreenMode:(BOOL)fsm
{
	fullscreen = fsm;
}


- (BOOL) inFullScreenMode
{
	return [gameView inFullScreenMode];
}

#else
	#error Unknown environment!
#endif


#if OOLITE_HAVE_APPKIT

- (void) logProgress:(NSString *)message
{
	[splashProgressTextField setStringValue:message];
	[splashProgressTextField display];
}


- (void) endSplashScreen
{
	[gameWindow setAcceptsMouseMovedEvents:YES];
	[gameWindow setContentView:gameView];
	[gameWindow makeFirstResponder:gameView];
}


// NIB methods
- (void)awakeFromNib
{
	NSString				*path = nil;
	
	// Set contents of Help window
	path = [[NSBundle mainBundle] pathForResource:@"ReadMe" ofType:@"rtfd"];
	if (path != nil)
	{
		[helpView readRTFDFromFile:path];
	}
}


// delegate methods
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename
{
	if ([[filename pathExtension] isEqual:@"oolite-save"])
	{
		[self setPlayerFileToLoad:filename];
		[self setPlayerFileDirectory:filename];
		return YES;
	}
	if ([[filename pathExtension] isEqual:@"oxp"]||[[filename pathExtension] isEqual:@"oolite_expansion_pack"])
	{
		BOOL dir_test;
		[[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&dir_test];
		if (dir_test)
		{
			if (!expansionPathsToInclude)
				expansionPathsToInclude = [[NSMutableArray alloc] initWithCapacity: 4];	// retained
			[expansionPathsToInclude addObject: filename];
			return YES;
		}
	}
	return NO;
}


- (void) exitApp
{
#if OOLITE_GNUSTEP
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ApplicationWillTerminate" object:self];
#endif
	[NSApp terminate:self];
}


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	OOLoggingTerminate();
	return NSTerminateNow;
}

#elif OOLITE_SDL

- (void) logProgress:(NSString *)message
{}

- (void) endSplashScreen
{}


- (void) exitApp
{
	[[NSUserDefaults standardUserDefaults] synchronize];
	OOLog(@"gameController.exitApp",@".GNUstepDefaults synchronized.");
	OOLoggingTerminate();
	SDL_Quit();
	exit(0);
}

#else
	#error Unknown environment!
#endif


- (void) exitFullScreenMode
{
	stayInFullScreenMode = NO;
}


- (void) pauseFullScreenModeToPerform:(SEL) selector onTarget:(id) target
{
	pauseSelector = selector;
	pauseTarget = target;
	stayInFullScreenMode = NO;
}


- (void)windowDidResize:(NSNotification *)aNotification
{
	[gameView drawRect:[gameView bounds]];
}


- (NSString *) playerFileToLoad
{
	return playerFileToLoad;
}


- (void) setPlayerFileToLoad:(NSString *)filename
{
	if (playerFileToLoad)
		[playerFileToLoad autorelease];
	playerFileToLoad = nil;
	if ([[filename pathExtension] isEqual:@"oolite-save"])
		playerFileToLoad = [[NSString stringWithString:filename] retain];
}


- (NSString *) playerFileDirectory
{
	return playerFileDirectory;
}


- (void) setPlayerFileDirectory:(NSString *)filename
{	
	if (playerFileDirectory)
		[playerFileDirectory autorelease];
	playerFileDirectory = nil;
	if ([[filename pathExtension] isEqual:@"oolite-save"])
		playerFileDirectory = [[filename stringByDeletingLastPathComponent] retain];
	else
		playerFileDirectory = [filename retain];
}


- (void)reportUnhandledStartupException:(NSException *)exception
{
	OOLog(@"startup.exception", @"***** Unhandled exception during startup: %@ (%@).", [exception name], [exception reason]);
	
	#if OOLITE_MAC_OS_X
		// Display an error alert.
		// TODO: provide better information on reporting bugs in the manual, and refer to it here.
		NSRunCriticalAlertPanel(@"Oolite failed to start up, because an unhandled exception occurred.", @"An exception of type %@ occurred. If this problem persists, please file a bug report.", @"OK", NULL, NULL, [exception name]);
	#endif
}

@end


