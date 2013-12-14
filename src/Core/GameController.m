/*

GameController.m

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
#import "OOOpenALController.h"
#import "OODebugSupport.h"
#import "legacy_random.h"

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

- (void)reportUnhandledStartupException:(NSException *)exception;

- (void)doPerformGameTick;

@end


@implementation GameController

+ (GameController *) sharedController
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
	
	if ((self = [super init]))
	{
		last_timeInterval = [NSDate timeIntervalSinceReferenceDate];
		delta_t = 0.01; // one hundredth of a second

		// rather than seeding this with the date repeatedly, seed it
		// once here at startup
		ranrot_srand((uint32_t)[[NSDate date] timeIntervalSince1970]);   // reset randomiser with current time
		
		_splashStart = [[NSDate alloc] init];
	}
	
	return self;
}


- (void) dealloc
{
#if OOLITE_MAC_OS_X
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


- (void) setGamePaused:(BOOL)value
{
	if (value && !gameIsPaused)
	{
		_resumeMode = [self mouseInteractionMode];
		[self setMouseInteractionModeForUIWithMouseInteraction:NO];
		gameIsPaused = YES;
	}
	else if (!value && gameIsPaused)
	{
		[self setMouseInteractionMode:_resumeMode];
		gameIsPaused = NO;
	}
}


- (OOMouseInteractionMode) mouseInteractionMode
{
	return _mouseMode;
}


- (void) setMouseInteractionMode:(OOMouseInteractionMode)mode
{
	OOMouseInteractionMode oldMode = _mouseMode;
	if (mode == oldMode)  return;
	
	_mouseMode = mode;
	OOLog(@"input.mouseMode.changed", @"Mouse interaction mode changed from %@ to %@", OOStringFromMouseInteractionMode(oldMode), OOStringFromMouseInteractionMode(mode));
	
#if OO_USE_FULLSCREEN_CONTROLLER
	if ([self inFullScreenMode])
	{
		[_fullScreenController noteMouseInteractionModeChangedFrom:oldMode to:mode];
	}
	else
#endif
	{
		[[self gameView] noteMouseInteractionModeChangedFrom:oldMode to:mode];
	}
}


- (void) setMouseInteractionModeForFlight
{
	[self setMouseInteractionMode:[PLAYER isMouseControlOn] ? MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL : MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL];
}


- (void) setMouseInteractionModeForUIWithMouseInteraction:(BOOL)interaction
{
	[self setMouseInteractionMode:interaction ? MOUSE_MODE_UI_SCREEN_WITH_INTERACTION : MOUSE_MODE_UI_SCREEN_NO_INTERACTION];
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
	
	@try
	{
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
		
		[self setUpDisplayModes];
		
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
	}
	@catch (NSException *exception)
	{
		[self reportUnhandledStartupException:exception];
		exit(EXIT_FAILURE);
	}
	
	OOLog(@"startup.complete", @"========== Loading complete in %.2f seconds. ==========", -[_splashStart timeIntervalSinceNow]);
	
#if OO_USE_FULLSCREEN_CONTROLLER
	[self setFullScreenMode:[[NSUserDefaults standardUserDefaults] boolForKey:@"fullscreen"]];
#endif
	
	// Release anything allocated above that is not required.
	[pool release];
	
#if !OOLITE_MAC_OS_X
	[[NSRunLoop currentRunLoop] run];
#endif
}


- (void) loadPlayerIfRequired
{
	if (playerFileToLoad != nil)
	{
		[self logProgress:DESC(@"loading-player")];
		// fix problem with non-shader lighting when starting skips
		// the splash screen
		[UNIVERSE useGUILightSource:YES];
		[UNIVERSE useGUILightSource:NO];
		[PLAYER loadPlayerFromFile:playerFileToLoad asNew:NO];
	}
}


- (void) beginSplashScreen
{
#if !OOLITE_MAC_OS_X
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
}


#if OOLITE_MAC_OS_X

- (void) performGameTick:(id)sender
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


- (void) doPerformGameTick
{
	@try
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
		if (EXPECT_NOT([PLAYER status] == STATUS_RESTART_GAME))
		{
			[UNIVERSE reinitAndShowDemo:YES];
		}
		if (!gameIsPaused)
		{
			[OOSound update];
			OOJSFrameCallbacksInvoke(delta_t);
		}
	}
	@catch (id exception) 
	{
		OOLog(@"exception.backtrace",@"%@",[exception callStackSymbols]);
	}
	
	@try
	{
		[gameView display];
	}
	@catch (id exception) {}
}


- (void) startAnimationTimer
{
	if (timer == nil)
	{   
		NSTimeInterval ti = 0.01;
		timer = [[NSTimer timerWithTimeInterval:ti target:self selector:@selector(performGameTick:) userInfo:nil repeats:YES] retain];
		
		[[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
#if OOLITE_MAC_OS_X
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


#if OOLITE_MAC_OS_X

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
		NSUInteger	i = 1;
		
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


- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
	SEL action = menuItem.action;
	
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
		if(![[NSFileManager defaultManager] fileExistsAtPath:[self snapshotsURLCreatingIfNeeded:NO].path isDirectory:&pathIsDirectory])
		{
			return NO;
		}
		return pathIsDirectory;
	}
	
	if (action == @selector(toggleFullScreenAction:))
	{
		if (_fullScreenController.fullScreenMode)
		{
			// NOTE: not DESC, because menu titles are not generally localizable.
			menuItem.title = NSLocalizedString(@"Exit Full Screen", NULL);
		}
		else
		{
			menuItem.title = NSLocalizedString(@"Enter Full Screen", NULL);
		}
	}
	
	// default
	return YES;
}


- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	return dockMenu;
}

#elif OOLITE_SDL

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
	if (![UNIVERSE doingStartUp])  return;
	
#if OOLITE_MAC_OS_X
	[splashProgressTextField setStringValue:message];
	[splashProgressTextField display];
	
	OOProfilerPointMarker(message);
#endif
	if([message length] > 0)
	{
		OOLog(@"startup.progress", @"===== [%.2f s] %@", -[_splashStart timeIntervalSinceNow], message);
	}
}


#if OO_DEBUG
#if OOLITE_MAC_OS_X
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
	OOLogOutdentIf(@"startup.progress");
	
	if ([sMessageStack count] > 0)
	{
		NSString *message = [sMessageStack lastObject];
		if ([message length] > 0)  [self logProgress:message];
		[sMessageStack removeLastObject];
	}
}

#endif


- (void) endSplashScreen
{
	OOLogSetDisplayMessagesInClass(@"startup.progress", NO);
	
#if OOLITE_MAC_OS_X
	// These views will be released when we replace the content view.
	splashProgressTextField = nil;
	splashView = nil;
	
	[gameWindow setAcceptsMouseMovedEvents:YES];
	[gameWindow setContentView:gameView];
	[gameWindow makeFirstResponder:gameView];
#elif OOLITE_SDL
	[gameView endSplashScreen];
#endif
}


#if OOLITE_MAC_OS_X

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
	if ([[filename pathExtension] isEqualToString:@"oxp"])
	{
		BOOL dir_test;
		[[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&dir_test];
		if (dir_test)
		{
			if (expansionPathsToInclude == nil)
			{
				expansionPathsToInclude = [[NSMutableArray alloc] init];
			}
			[expansionPathsToInclude addObject:filename];
			return YES;
		}
	}
	return NO;
}


- (void) exitAppWithContext:(NSString *)context
{
	[gameView.window orderOut:nil];
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
	[[OOOpenALController sharedController] shutdown];
	exit(0);
}

#else
	#error Unknown environment!
#endif


- (void) exitAppCommandQ
{
	[self exitAppWithContext:@"Command-Q"];
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
	
	OOGL(glClearDepth(MAX_CLEAR_DEPTH));
	OOGL(glViewport(0, 0, viewSize.width, viewSize.height));
	
	OOGL(glMatrixMode(GL_PROJECTION));
	OOGL(glLoadIdentity());	// reset matrix
	OOGL(glFrustum(-ratio, ratio, -aspect*ratio, aspect*ratio, 1.0, MAX_CLEAR_DEPTH));	// set projection matrix
	
	OOGL(glMatrixMode(GL_MODELVIEW));
	
	OOGL(glDepthFunc(GL_LESS));			// depth buffer
	
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
		
	}
	
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


#ifndef NDEBUG
/*	This method exists purely to suppress Clang static analyzer warnings that
	these ivars are unused (but may be used by categories, which they are).
*/
- (BOOL) suppressClangStuff
{
	return pauseSelector &&
	pauseTarget;
}
#endif

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
