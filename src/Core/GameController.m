/*

GameController.m

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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


- (int) indexOfCurrentDisplayMode
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
		[UNIVERSE drawFromEntity:0];
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
static int CompareDisplayModes(id arg1, id arg2, void *context)
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
	NSDictionary		*mode = nil;
	unsigned			modeWidth, modeHeight, color;
	NSUserDefaults		*userDefaults = nil;
	NSMutableSet		*modesSet = nil;
	
	// Load preferences.
	userDefaults = [NSUserDefaults standardUserDefaults];
	width = [userDefaults intForKey:@"display_width" defaultValue:DISPLAY_DEFAULT_WIDTH];
	height = [userDefaults intForKey:@"display_height" defaultValue:DISPLAY_DEFAULT_HEIGHT];
	refresh = [userDefaults intForKey:@"display_refresh" defaultValue:DISPLAY_DEFAULT_REFRESH];
	
	// Get the list of all available modes
	modes = (NSArray *)CGDisplayAvailableModes(kCGDirectMainDisplay);
	
	// Filter out modes that we don't want
	modesSet = [NSMutableSet set];
	modeCount = [modes count];
	for (modeIndex = 0; modeIndex < modeCount; modeIndex++)
	{
		mode = [modes objectAtIndex: modeIndex];
		modeWidth = [mode unsignedIntForKey:kOODisplayWidth];
		modeHeight = [mode unsignedIntForKey:kOODisplayHeight];
		color = [mode unsignedIntForKey:kOODisplayBitsPerPixel];

		if ((color < DISPLAY_MIN_COLOURS)||(modeWidth < DISPLAY_MIN_WIDTH)||(modeWidth > DISPLAY_MAX_WIDTH)||(modeHeight < DISPLAY_MIN_HEIGHT)||(modeHeight > DISPLAY_MAX_HEIGHT))
			continue;
		[modesSet addObject:mode];	// Use a set here to remove duplicate modes generated for some displays.
	}
	
	// Sort the filtered modes
	displayModes = [[modesSet allObjects] mutableCopy];
	[displayModes sortUsingFunction: CompareDisplayModes context: NULL];
	
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
		CGPoint centerOfScreen = CGPointMake(width/2.0,height/2.0);

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
		glClearColor(0.0, 0.0, 0.0, 0.0);
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


#if OOLITE_MAC_OS_X


- (void) playiTunesPlaylist:(NSString *)playlist_name
{
	NSString *ootunesScriptString = [NSString stringWithFormat:@"tell application \"iTunes\"\nif playlist \"%@\" exists then\nset song repeat of playlist \"%@\" to all\nset shuffle of playlist \"%@\" to true\nplay some track of playlist \"%@\"\nend if\nend tell", playlist_name, playlist_name, playlist_name, playlist_name];
	NSAppleScript *ootunesScript = [[NSAppleScript alloc] initWithSource:ootunesScriptString];
	NSDictionary *errDict = nil;
	[ootunesScript executeAndReturnError:&errDict];
	if (errDict)
		OOLog(@"iTunesIntegration.failed", @"ootunes returned :%@", [errDict description]);
	[ootunesScript release]; 
}


- (void) pauseiTunes
{
	NSString *ootunesScriptString = [NSString stringWithFormat:@"tell application \"iTunes\"\npause\nend tell"];
	NSAppleScript *ootunesScript = [[NSAppleScript alloc] initWithSource:ootunesScriptString];
	NSDictionary *errDict = nil;
	[ootunesScript executeAndReturnError:&errDict];
	if (errDict)
		OOLog(@"iTunesIntegration.failed", @"ootunes returned :%@", [errDict description]);
	[ootunesScript release]; 
}

#else

- (void) playiTunesPlaylist:(NSString *)playlist_name
{}


- (void) pauseiTunes
{}

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


