/*

GameController.m

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
#import "Universe.h"
#import "ResourceManager.h"
#import "MyOpenGLView.h"
#import "OOSound.h"
#import "OOOpenGL.h"
#import "PlayerEntityLoadSave.h"
#include <stdlib.h>
#import "OOCollectionExtractors.h"
#import "OOOXPVerifier.h"
#import "OOLoggingExtended.h"
#import "NSFileManagerOOExtensions.h"
#import "OOLogOutputHandler.h"
#import "OODebugFlags.h"
#import "OOJSFrameCallbacks.h"
#import "OOOpenGLExtensionManager.h"

#define kOOLogUnconvertedNSLog @"unclassified.GameController"

#if OOLITE_MAC_OS_X
#import "JAPersistentFileReference.h"
#import <Sparkle/Sparkle.h>
#import "OoliteApp.h"
#import "OOMacJoystickManager.h"

static void SetUpSparkle(void);
#elif (OOLITE_GNUSTEP && !defined(NDEBUG))
#import "OODebugMonitor.h"
#endif


static GameController *sSharedController = nil;


@interface GameController (OOPrivate)

- (void) getDisplayModes;

- (void)reportUnhandledStartupException:(NSException *)exception;

- (void)performGameTick:(id)userInfo;
- (void)doPerformGameTick;

@end


@implementation GameController

+ (id) sharedController
{
	if (sSharedController == nil)
	{
		sSharedController = [[self alloc] init];
	}
	return sSharedController;
}


- (id) init
{
	if (sSharedController != nil)
	{
		[self release];
		[NSException raise:NSInternalInconsistencyException format:@"%s: expected only one GameController to exist at a time.", __PRETTY_FUNCTION__];
	}
	
	self = [super init];
	
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


- (BOOL) isGamePaused
{
	return gameIsPaused;
}


- (void) pauseGame
{
	gameIsPaused = YES;
}


- (void) unpauseGame
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
	[gameView setGameController:self];
	[UNIVERSE setGameView:gameView];
}


- (void) applicationDidFinishLaunching:(NSNotification *)notification
{
	NSAutoreleasePool	*pool = nil;
	unsigned			i;
	
	pool = [[NSAutoreleasePool alloc] init];
	
	NS_DURING
		// if not verifying oxps, ensure that gameView is drawn to using beginSplashScreen
		// OpenGL is initialised and that allows textures to initialise too.

#if OO_OXP_VERIFIER_ENABLED

		if ([OOOXPVerifier runVerificationIfRequested])
		{
			[self exitAppWithContext:@"OXP verifier run"];
		}
		else 
		{
			[self beginSplashScreen];
		}
		
#else
		[self beginSplashScreen];
#endif
		
#if OOLITE_MAC_OS_X
	[OOJoystickManager setStickHandlerClass:[OOMacJoystickManager class]];
	SetUpSparkle();
#endif
		
		[self getDisplayModes];
		
		// moved to before the Universe is created
		if (expansionPathsToInclude)
		{
			for (i = 0; i < [expansionPathsToInclude count]; i++)
			{
				[ResourceManager addExternalPath: (NSString*)[expansionPathsToInclude objectAtIndex: i]];
			}
		}
		
		// moved here to try to avoid initialising this before having an Open GL context
		//[self logProgress:DESC(@"Initialising universe")]; // DESC expansions only possible after Universe init
		[[Universe alloc] initWithGameView:gameView];
		
		[self loadPlayerIfRequired];
		
		[self logProgress:@""];
		
		// get the run loop and add the call to performGameTick:
		[self startAnimationTimer];
		
		[self endSplashScreen];
	NS_HANDLER
		[self reportUnhandledStartupException:localException];
		exit(EXIT_FAILURE);
	NS_ENDHANDLER
	
	OOLog(@"loading.complete", @"========== Loading complete. ==========");
	
	// Release anything allocated above that is not required.
	[pool release];
#if OOLITE_HAVE_APPKIT
	if (fullscreen) [self goFullscreen:nil];
#else
	[[NSRunLoop currentRunLoop] run];
#endif
}


- (void) loadPlayerIfRequired
{
	if (playerFileToLoad != nil)
	{
		[self logProgress:DESC(@"loading-player")];
		[PLAYER loadPlayerFromFile:playerFileToLoad];
	}
}


- (void) beginSplashScreen
{
#if !OOLITE_HAVE_APPKIT
	if(!gameView)
	{
		gameView = [MyOpenGLView alloc];
		[gameView init];
		[gameView setGameController:self];
		[gameView initSplashScreen];
	}
#else
	[gameView updateScreen];
#endif
	
	_splashStart = [[NSDate alloc] init];
}


#if OOLITE_HAVE_APPKIT
static BOOL _switchRez = NO, _switchRezDeferred = NO;


- (void) performGameTick:(id)userInfo
{
	if (EXPECT_NOT(_switchRezDeferred)) 
	{
		_switchRezDeferred = NO;
		[self goFullscreen:nil];
	}
	else [self doPerformGameTick];
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


- (void) doPerformGameTick
{
	NS_DURING
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
		if (!gameIsPaused)
		{
			[OOSound update];
			OOJSFrameCallbacksInvoke(delta_t);
		}
		
#if OOLITE_HAVE_APPKIT
		if (fullscreen)
		{
			[UNIVERSE drawUniverse];
			NS_VOIDRETURN;
		}
#endif
	NS_HANDLER
	NS_ENDHANDLER
	
	NS_DURING
		if (gameView != nil)  [gameView display];
		else  OOLog(kOOLogInconsistentState, @"***** gameView not set : delta_t %f",(float)delta_t);
	NS_HANDLER
	NS_ENDHANDLER
}


- (void) startAnimationTimer
{
	if (timer == nil)
	{   
		NSTimeInterval ti = 0.01;
		timer = [[NSTimer timerWithTimeInterval:ti target:self selector:@selector(performGameTick:) userInfo:nil repeats:YES] retain];
		
		[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
#if OOLITE_HAVE_APPKIT
		[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
#endif
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
static NSComparisonResult CompareDisplayModes(id arg1, id arg2, void *context)
{
	NSDictionary *mode1 = (NSDictionary *)arg1;
	NSDictionary *mode2 = (NSDictionary *)arg2;
	int size1, size2;
	
	// Sort first on pixel count
	size1 = [[mode1 objectForKey:kOODisplayWidth] intValue] *
			[[mode1 objectForKey:kOODisplayHeight] intValue];
	size2 = [[mode2 objectForKey:kOODisplayWidth] intValue] *
			[[mode2 objectForKey:kOODisplayHeight] intValue];

	// Then on refresh rate
	if (size1 == size2)
	{
		size1 = (int)[[mode1 objectForKey:kOODisplayRefreshRate] intValue];
		size2 = (int)[[mode2 objectForKey:kOODisplayRefreshRate] intValue];
	}

	return (size1 < size2) ? NSOrderedAscending
		 : (size1 > size2) ? NSOrderedDescending
		 : NSOrderedSame;
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


- (void) recenterVirtualJoystick
{
	// FIXME: does this really need to be spread across GameController and MyOpenGLView? -- Ahruman 2011-01-22
	my_mouse_x = my_mouse_y = 0;	// center mouse
	[gameView setVirtualJoystick:0.0 :0.0];
}


- (IBAction) showLogAction:sender
{
	[[NSWorkspace sharedWorkspace] openFile:[OOLogHandlerGetLogBasePath() stringByAppendingPathComponent:@"Previous.log"]];
}


- (IBAction) showLogFolderAction:sender
{
	[[NSWorkspace sharedWorkspace] openFile:OOLogHandlerGetLogBasePath()];
}


// Helpers to allow -snapshotsURLCreatingIfNeeded: code to be identical here and in dock tile plug-in.
static id GetPreference(NSString *key, Class expectedClass)
{
	id result = [[NSUserDefaults standardUserDefaults] objectForKey:key];
	if (expectedClass != Nil && ![result isKindOfClass:expectedClass])  result = nil;
	
	return result;
}


static void SetPreference(NSString *key, id value)
{
	[[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
}


static void RemovePreference(NSString *key)
{
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}


#define kSnapshotsDirRefKey		@"snapshots-directory-reference"
#define kSnapshotsDirNameKey	@"snapshots-directory-name"

- (NSURL *) snapshotsURLCreatingIfNeeded:(BOOL)create
{
	BOOL			stale = NO;
	NSDictionary	*snapshotDirDict = GetPreference(kSnapshotsDirRefKey, [NSDictionary class]);
	NSURL			*url = nil;
	NSString		*name = DESC(@"snapshots-directory-name-mac");
	
	if (snapshotDirDict != nil)
	{
		url = JAURLFromPersistentFileReference(snapshotDirDict, kJAPersistentFileReferenceWithoutUI | kJAPersistentFileReferenceWithoutMounting, &stale);
		if (url != nil)
		{
			NSString *existingName = [[url path] lastPathComponent];
			if ([existingName compare:name options:NSCaseInsensitiveSearch] != 0)
			{
				// Check name from previous access, because we might have changed localizations.
				NSString *originalOldName = GetPreference(kSnapshotsDirNameKey, [NSString class]);
				if (originalOldName == nil || [existingName compare:originalOldName options:NSCaseInsensitiveSearch] != 0)
				{
					url = nil;
				}
			}
			
			// did we put the old directory in the trash?
			Boolean inTrash = false;
			const UInt8* utfPath = (UInt8*)[[url path] UTF8String];
			
			OSStatus err = DetermineIfPathIsEnclosedByFolder(kOnAppropriateDisk, kTrashFolderType, utfPath, false, &inTrash);
			// if so, create a new directory.
			if (err == noErr && inTrash == true) url = nil;
		}
	}
	
	if (url == nil)
	{
		NSString *path = nil;
		NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
		if ([searchPaths count] > 0)
		{
			path = [[searchPaths objectAtIndex:0] stringByAppendingPathComponent:name];
		}
		url = [NSURL fileURLWithPath:path];
		
		if (url != nil)
		{
			stale = YES;
			if (create)
			{
				NSFileManager *fmgr = [NSFileManager defaultManager];
				if (![fmgr fileExistsAtPath:path])
				{
					[fmgr oo_createDirectoryAtPath:path attributes:nil];
				}
			}
		}
	}
	
	if (stale)
	{
		snapshotDirDict = JAPersistentFileReferenceFromURL(url);
		if (snapshotDirDict != nil)
		{
			SetPreference(kSnapshotsDirRefKey, snapshotDirDict);
			SetPreference(kSnapshotsDirNameKey, [[url path] lastPathComponent]);
		}
		else
		{
			RemovePreference(kSnapshotsDirRefKey);
		}
	}
	
	return url;
}


- (IBAction) showSnapshotsAction:sender
{
	[[NSWorkspace sharedWorkspace] openURL:[self snapshotsURLCreatingIfNeeded:YES]];
}


- (IBAction) showAddOnsAction:sender
{
	if ([[ResourceManager paths] count] > 1)
	{
		// Show the first populated AddOns folder (paths are in order of preference, path[0] is always Resources).
		[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:(NSString *)[[ResourceManager paths] objectAtIndex:1]]];
	}
	else
	{
		// No AddOns at all. Show the first existing AddOns folder (paths are in order of preference, etc...).
		BOOL		pathIsDirectory;
		NSString	*path = nil;
		uint		i = 1;
		
		while (i < [[ResourceManager rootPaths] count])
		{
			path = (NSString *)[[ResourceManager rootPaths] objectAtIndex:i];
			if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&pathIsDirectory] && pathIsDirectory) break;
			// else
			i++;
		} 
		if (i < [[ResourceManager rootPaths] count]) [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
	}
}


- (void) changeFullScreenResolution
{
	_switchRez = YES;
	stayInFullScreenMode = NO;	// Close the present fullScreenContext before creating the new one.
}


- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	SEL action = [menuItem action];
	
	if (action == @selector(showLogAction:))
	{
		// the first path is always Resources
		return ([[NSFileManager defaultManager] fileExistsAtPath:[OOLogHandlerGetLogBasePath() stringByAppendingPathComponent:@"Previous.log"]]);
	}
	
	if (action == @selector(showAddOnsAction:))
	{
		// Always enabled in unrestricted mode, to allow users to add OXPs more easily.
		return [ResourceManager useAddOns];
	}
	
	if (action == @selector(showSnapshotsAction:))
	{
		BOOL	pathIsDirectory;
		if(![[NSFileManager defaultManager] fileExistsAtPath:[[self snapshotsURLCreatingIfNeeded:NO] path] isDirectory:&pathIsDirectory]) return NO;
		return pathIsDirectory;
	}
	
	// default
	return YES;
}


- (BOOL) inFullScreenMode
{
	return fullscreen;
}


- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	return dockMenu;
}

#elif OOLITE_SDL

- (void) getDisplayModes
{
	NSArray *modes = [gameView getScreenSizeArray];
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


- (BOOL) inFullScreenMode
{
	return [gameView inFullScreenMode];
}


- (NSURL *) snapshotsURLCreatingIfNeeded:(BOOL)create
{
	NSURL *url = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:DESC(@"snapshots-directory-name")]];
	
	if (create)
	{
		NSString *path = [url path];
		NSFileManager *fmgr = [NSFileManager defaultManager];
		if (![fmgr fileExistsAtPath:path])
		{
			[fmgr createDirectoryAtPath:path attributes:nil];
		}
	}
	return url;
}

#else
	#error Unknown environment!
#endif

- (void) logProgress:(NSString *)message
{
#if OOLITE_HAVE_APPKIT
	[splashProgressTextField setStringValue:message];	[splashProgressTextField display];
#endif
	OOLog(@"startup.progress", @"===== [%.2f s] %@", -[_splashStart timeIntervalSinceNow], message);
}


#if OO_DEBUG
#if OOLITE_HAVE_APPKIT
- (BOOL) debugMessageTrackingIsOn
{
	return splashProgressTextField != nil;
}


- (NSString *) debugMessageCurrentString
{
	return [splashProgressTextField stringValue];
}
#else
- (BOOL) debugMessageTrackingIsOn
{
	return OOLogWillDisplayMessagesInClass(@"startup.progress");
}


- (NSString *) debugMessageCurrentString
{
	return @"";
}
#endif

- (void) debugLogProgress:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	[self debugLogProgress:format arguments:args];
	va_end(args);
}


- (void) debugLogProgress:(NSString *)format arguments:(va_list)arguments
{
	NSString *message = [[[NSString alloc] initWithFormat:format arguments:arguments] autorelease];
	[self logProgress:message];
}


static NSMutableArray *sMessageStack;

- (void) debugPushProgressMessage:(NSString *)format, ...
{
	if ([self debugMessageTrackingIsOn])
	{
		if (sMessageStack == nil)  sMessageStack = [[NSMutableArray alloc] init];
		[sMessageStack addObject:[self debugMessageCurrentString]];
		
		va_list args;
		va_start(args, format);
		[self debugLogProgress:format arguments:args];
		va_end(args);
	}
	
	OOLogIndentIf(@"startup.progress");
}


- (void) debugPopProgressMessage
{
	if ([sMessageStack count] > 0)
	{
		OOLogOutdentIf(@"startup.progress");
		
		NSString *message = [sMessageStack lastObject];
		if ([message length] > 0)  [self logProgress:message];
		[sMessageStack removeLastObject];
	}
}

#endif


- (void) endSplashScreen
{
	OOLogSetDisplayMessagesInClass(@"startup.progress", NO);
	
#if OOLITE_HAVE_APPKIT
	// These views will be released when we replace the content view.
	splashProgressTextField = nil;
	splashView = nil;
	progressBar = nil;
	
	[gameWindow setAcceptsMouseMovedEvents:YES];
	[gameWindow setContentView:gameView];
	[gameWindow makeFirstResponder:gameView];
#elif OOLITE_SDL
	[gameView endSplashScreen];
#endif
}


#if OOLITE_HAVE_APPKIT

- (void) setProgressBarValue:(float)value
{
	[progressBar setDoubleValue:value];
	[progressBar display];
}


// NIB methods
- (void)awakeFromNib
{
	NSString				*path = nil;
	
	// Set contents of Help window
	path = [[NSBundle mainBundle] pathForResource:@"OoliteReadMe" ofType:@"pdf"];
	if (path != nil)
	{
		PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
		[helpView setDocument:document];
		[document release];
	}
	[helpView setBackgroundColor:[NSColor whiteColor]];
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
	if ([[filename pathExtension] isEqualToString:@"oxp"] ||
		[[filename pathExtension] isEqual:@"oolite_expansion_pack"])
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


- (void) exitAppWithContext:(NSString *)context
{
	[(OoliteApp *)NSApp setExitContext:context];
	[NSApp terminate:self];
}


- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	[[OOCacheManager sharedCache] finishOngoingFlush];
	OOLoggingTerminate();
	return NSTerminateNow;
}

#elif OOLITE_SDL

- (void) setProgressBarValue:(float)value
{}


- (void) exitAppWithContext:(NSString *)context
{
	OOLog(@"exit.context", @"Exiting: %@.", context);
#if (OOLITE_GNUSTEP && !defined(NDEBUG))
	[[OODebugMonitor sharedDebugMonitor] applicationWillTerminate];
#endif
	[[NSUserDefaults standardUserDefaults] synchronize];
	OOLog(@"gameController.exitApp",@".GNUstepDefaults synchronized.");
	OOLoggingTerminate();
	SDL_Quit();
	exit(0);
}

#else
	#error Unknown environment!
#endif


- (void) exitAppCommandQ
{
	[self exitAppWithContext:@"Command-Q"];
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

- (void) exitFullScreenMode
{
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"fullscreen"];
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
	[gameView updateScreen];
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
	if ([[[filename pathExtension] lowercaseString] isEqual:@"oolite-save"])
		playerFileToLoad = [filename copy];
}


- (NSString *) playerFileDirectory
{
	if (playerFileDirectory == nil)
	{
		playerFileDirectory = [[NSUserDefaults standardUserDefaults] stringForKey:@"save-directory"];
		if (playerFileDirectory != nil && ![[NSFileManager defaultManager] fileExistsAtPath:playerFileDirectory])
		{
			playerFileDirectory = nil;
		}
		if (playerFileDirectory == nil)  playerFileDirectory = [[NSFileManager defaultManager] defaultCommanderPath];
		
		[playerFileDirectory retain];
	}
	
	return playerFileDirectory;
}


- (void) setPlayerFileDirectory:(NSString *)filename
{	
	if (playerFileDirectory != nil)
	{
		[playerFileDirectory autorelease];
		playerFileDirectory = nil;
	}
	
	if ([[[filename pathExtension] lowercaseString] isEqual:@"oolite-save"])
	{
		filename = [filename stringByDeletingLastPathComponent];
	}
	
	playerFileDirectory = [filename retain];
	[[NSUserDefaults standardUserDefaults] setObject:filename forKey:@"save-directory"];
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


- (void)setUpBasicOpenGLStateWithSize:(NSSize)viewSize
{
	OOOpenGLExtensionManager	*extMgr = [OOOpenGLExtensionManager sharedManager];
	
	float	ratio = 0.5;
	float   aspect = viewSize.height/viewSize.width;
	
	OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
	OOGL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
	OOGL(glShadeModel(GL_FLAT));
	
	OOGL(glClearDepth(MAX_CLEAR_DEPTH));
	OOGL(glViewport(0, 0, viewSize.width, viewSize.height));
	
	OOGL(glMatrixMode(GL_PROJECTION));
	OOGL(glLoadIdentity());	// reset matrix
	OOGL(glFrustum(-ratio, ratio, -aspect*ratio, aspect*ratio, 1.0, MAX_CLEAR_DEPTH));	// set projection matrix
	
	OOGL(glMatrixMode(GL_MODELVIEW));
	
	OOGL(glEnable(GL_DEPTH_TEST));		// depth buffer
	OOGL(glDepthFunc(GL_LESS));			// depth buffer
	
	OOGL(glFrontFace(GL_CCW));			// face culling - front faces are AntiClockwise!
	OOGL(glCullFace(GL_BACK));			// face culling
	OOGL(glEnable(GL_CULL_FACE));			// face culling
	
	OOGL(glEnable(GL_BLEND));									// alpha blending
	OOGL(glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA));	// alpha blending
	
	if (UNIVERSE)
	{
		[UNIVERSE setLighting];
	}
	else
	{
		GLfloat black[4] =	{0.0, 0.0, 0.0, 1.0};
		GLfloat	white[] =	{1.0, 1.0, 1.0, 1.0};
		GLfloat	stars_ambient[] =	{0.25, 0.2, 0.25, 1.0};
		
		OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, black));
		OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, white));
		OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, white));
		OOGL(glLightfv(GL_LIGHT1, GL_POSITION, black));
		OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
		
		OOGL(glEnable(GL_LIGHT1));		// lighting
		
	}
	OOGL(glEnable(GL_LIGHTING));		// lighting
	
	if ([extMgr usePointSmoothing])  OOGL(glEnable(GL_POINT_SMOOTH));
	if ([extMgr useLineSmoothing])  OOGL(glEnable(GL_LINE_SMOOTH));
	
	// world's simplest OpenGL optimisations...
#if GL_APPLE_transform_hint
	if ([extMgr haveExtension:@"GL_APPLE_transform_hint"])
	{
		OOGL(glHint(GL_TRANSFORM_HINT_APPLE, GL_FASTEST));
	}
#endif
	
	OOGL(glDisable(GL_NORMALIZE));
	OOGL(glDisable(GL_RESCALE_NORMAL));
	
#if GL_VERSION_1_2
	// For OpenGL 1.2 or later, we want GL_SEPARATE_SPECULAR_COLOR all the time.
	if ([extMgr versionIsAtLeastMajor:1 minor:2])
	{
		OOGL(glLightModeli(GL_LIGHT_MODEL_COLOR_CONTROL, GL_SEPARATE_SPECULAR_COLOR));
	}
#endif
}

@end


#if OOLITE_MAC_OS_X

static void SetUpSparkle(void)
{
#define FEED_URL_BASE			"http://www.oolite.org/updates/"
#define TEST_RELEASE_FEED_NAME	"oolite-mac-test-release-appcast.xml"
#define DEPLOYMENT_FEED_NAME	"oolite-mac-appcast.xml"

#define TEST_RELEASE_FEED_URL	(@ FEED_URL_BASE TEST_RELEASE_FEED_NAME)
#define DEPLOYMENT_FEED_URL		(@ FEED_URL_BASE DEPLOYMENT_FEED_NAME)

// Default to test releases in test release or debug builds, and stable releases for deployment builds.
#ifdef NDEBUG
#define DEFAULT_TEST_RELEASE	0
#else
#define DEFAULT_TEST_RELEASE	1
#endif
	
	BOOL useTestReleases = [[NSUserDefaults standardUserDefaults] oo_boolForKey:@"use-test-release-updates"
																   defaultValue:DEFAULT_TEST_RELEASE];
	
	SUUpdater *updater = [SUUpdater sharedUpdater];
	[updater setFeedURL:[NSURL URLWithString:useTestReleases ? TEST_RELEASE_FEED_URL : DEPLOYMENT_FEED_URL]];
}

#endif
