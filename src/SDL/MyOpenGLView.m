/*

MyOpenGLView.m

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

#import "png.h"
#import "MyOpenGLView.h"

#import "GameController.h"
#import "Universe.h"
#import "OOSDLJoystickManager.h"
#import "SDL_syswm.h"
#import "OOSound.h"
#import "NSFileManagerOOExtensions.h" // to find savedir
#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "PlanetEntity.h"
#import "OOGraphicsResetManager.h"
#import "OOCollectionExtractors.h" // for splash screen settings
#import "OOFullScreenController.h"
#import "ResourceManager.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#import "stb_image_write.h"

#define kOOLogUnconvertedNSLog @"unclassified.MyOpenGLView"

static NSString * kOOLogKeyUp				= @"input.keyMapping.keyPress.keyUp";
static NSString * kOOLogKeyDown				= @"input.keyMapping.keyPress.keyDown";

#include <ctype.h>

#if OOLITE_WINDOWS
#define DWMWA_USE_IMMERSIVE_DARK_MODE	20
HRESULT WINAPI DwmSetWindowAttribute (HWND hwnd, DWORD dwAttribute, LPCVOID pvAttribute, DWORD cbAttribute);
#endif

@interface MyOpenGLView (OOPrivate)

- (void) resetSDLKeyModifiers;
- (void) setWindowBorderless:(BOOL)borderless;
- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event keyID:(Uint16)key_id; // DJS
@end

@implementation MyOpenGLView

+ (NSMutableDictionary *) getNativeSize
{
	NSMutableDictionary *mode=[[NSMutableDictionary alloc] init];
	int nativeDisplayWidth = 1024;
	int nativeDisplayHeight = 768;

#if OOLITE_LINUX
	SDL_SysWMinfo  dpyInfo;
	SDL_VERSION(&dpyInfo.version);
	if(SDL_GetWMInfo(&dpyInfo))
   	{
		nativeDisplayWidth = DisplayWidth(dpyInfo.info.x11.display, 0);
		nativeDisplayHeight = DisplayHeight(dpyInfo.info.x11.display, 0);
		OOLog(@"display.mode.list.native", @"X11 native resolution detected: %d x %d", nativeDisplayWidth, nativeDisplayHeight);
	}
	else
	{
		OOLog(@"display.mode.list.native.failed", @"%@", @"SDL_GetWMInfo failed, defaulting to 1024x768 for native size");
	}
#elif OOLITE_WINDOWS
	nativeDisplayWidth = GetSystemMetrics(SM_CXSCREEN);
	nativeDisplayHeight = GetSystemMetrics(SM_CYSCREEN);
	OOLog(@"display.mode.list.native", @"Windows native resolution detected: %d x %d", nativeDisplayWidth, nativeDisplayHeight);
#else
	OOLog(@"display.mode.list.native.unknown", @"Unknown architecture, defaulting to 1024x768");
#endif
	[mode setValue: [NSNumber numberWithInt: nativeDisplayWidth] forKey:kOODisplayWidth];
	[mode setValue: [NSNumber numberWithInt: nativeDisplayHeight] forKey: kOODisplayHeight];
	[mode setValue: [NSNumber numberWithInt: 0] forKey: kOODisplayRefreshRate];

	return [mode autorelease];
}


- (void) createSurface
{
	// Changing these flags can trigger texture bugs.
	const int videoModeFlags = SDL_HWSURFACE | SDL_OPENGL | SDL_RESIZABLE;

	if (showSplashScreen)
	{
#if OOLITE_WINDOWS
		// Pre setVideoMode adjustments.
		NSSize tmp = currentWindowSize;
		ShowWindow(SDL_Window,SW_SHOWMINIMIZED);
		updateContext = NO;	//don't update the (splash screen) window yet!

		// Initialise the SDL surface. (need custom SDL.dll)
		surface = SDL_SetVideoMode(firstScreen.width, firstScreen.height, 32, videoModeFlags);

		// Post setVideoMode adjustments.
		currentWindowSize=tmp;
#else
		// Changing the flags can trigger texture bugs.
		surface = SDL_SetVideoMode(8, 8, 32, videoModeFlags);
#endif
		if (!surface) {
			return;
		}
	}
	else
	{
#if OOLITE_WINDOWS
		updateContext = YES;
#endif
		surface = SDL_SetVideoMode(firstScreen.width, firstScreen.height, 32, videoModeFlags);
		if (!surface) {
			return;
		}
		// blank the surface / go to fullscreen
		[self initialiseGLWithSize: firstScreen];
	}

	_gamma = 1.0f;
	if (SDL_SetGamma(_gamma, _gamma, _gamma) < 0 )
	{
		char * errStr = SDL_GetError();
		OOLogWARN(@"gamma.set.failed", @"Could not set gamma: %s", errStr);
		// CIM: this doesn't seem to necessarily be fatal. Gamma settings
		// mostly work on mine despite this function failing.
		//	exit(1);
	}
	SDL_EnableUNICODE(1);
}


- (id) init
{
	self = [super init];

	Uint32          colorkey;
	SDL_Surface     *icon=NULL;
	NSString		*imagesDir;

	// SDL splash screen  settings

	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	showSplashScreen = [prefs oo_boolForKey:@"splash-screen" defaultValue:YES];
	BOOL	vSyncPreference = [prefs oo_boolForKey:@"v-sync" defaultValue:YES];
	int 	bitsPerColorComponent = [prefs oo_boolForKey:@"hdr" defaultValue:NO] ? 16 : 8;
	int		vSyncValue;

	NSArray				*arguments = nil;
	NSEnumerator		*argEnum = nil;
	NSString			*arg = nil;
	BOOL				noSplashArgFound = NO;

	[self initKeyMappingData];

	// preload the printscreen key into our translation array because SDLK_PRINTSCREEN isn't available
	scancode2Unicode[55] = gvPrintScreenKey;

	arguments = [[NSProcessInfo processInfo] arguments];

	// scan for splash screen overrides: -nosplash || --nosplash , -splash || --splash
	// scan for V-sync disabling overrides: -novsync || --novsync
	for (argEnum = [arguments objectEnumerator]; (arg = [argEnum nextObject]); )
	{
		if ([arg isEqual:@"-nosplash"] || [arg isEqual:@"--nosplash"])
		{
			showSplashScreen = NO;
			noSplashArgFound = YES;	// -nosplash always trumps -splash
		}
		else if (([arg isEqual:@"-splash"] || [arg isEqual:@"--splash"]) && !noSplashArgFound)
		{
			showSplashScreen = YES;
		}
		
		// if V-sync is disabled at the command line, override the defaults file
		if ([arg isEqual:@"-novsync"] || [arg isEqual:@"--novsync"])  vSyncPreference = NO;
		
		if ([arg isEqual: @"-hdr"])  bitsPerColorComponent = 16;
	}
	
	matrixManager = [[OOOpenGLMatrixManager alloc] init];

	// TODO: This code up to and including stickHandler really ought
	// not to be in this class.
	OOLog(@"sdl.init", @"%@", @"initialising SDL");
	if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK) < 0)
	{
		OOLog(@"sdl.init.failed", @"Unable to init SDL: %s\n", SDL_GetError());
		[self dealloc];
		return nil;
	}

	SDL_putenv ("SDL_VIDEO_WINDOW_POS=center");

	[OOJoystickManager setStickHandlerClass:[OOSDLJoystickManager class]];
	// end TODO

	[OOSound setUp];
	if (![OOSound isSoundOK])  OOLog(@"sound.init", @"%@", @"Sound system disabled.");

	// Generate the window caption, containing the version number and the date the executable was compiled.
	static char windowCaption[128];
	NSString *versionString = [NSString stringWithFormat:@"Oolite v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];

	strcpy (windowCaption, [versionString UTF8String]);
	strcat (windowCaption, " - "__DATE__);
	SDL_WM_SetCaption (windowCaption, "Oolite");	// Set window title.

#if OOLITE_WINDOWS
	// needed for enabling system window manager events, which is needed for handling window movement messages
	SDL_EventState (SDL_SYSWMEVENT, SDL_ENABLE);
	
	//capture the window handle for later
	static SDL_SysWMinfo wInfo;
	SDL_VERSION(&wInfo.version);
	SDL_GetWMInfo(&wInfo);
	SDL_Window   = wInfo.window;
	
	// This must be inited after SDL_Window has been set - we need the main window handle in order to get monitor info
	if (![self getCurrentMonitorInfo:&monitorInfo])
	{
		OOLogWARN(@"display.initGL.monitorInfoWarning", @"Could not get current monitor information.");
	}

	atDesktopResolution = YES;
#endif

	grabMouseStatus = NO;

	imagesDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Images"];
	icon = SDL_LoadBMP([[imagesDir stringByAppendingPathComponent:@"WMicon.bmp"] UTF8String]);

	if (icon != NULL)
	{
		colorkey = SDL_MapRGB(icon->format, 128, 0, 128);
		SDL_SetColorKey(icon, SDL_SRCCOLORKEY, colorkey);
		SDL_WM_SetIcon(icon, NULL);
	}
	SDL_FreeSurface(icon);

	SDL_GL_SetAttribute(SDL_GL_RED_SIZE, bitsPerColorComponent);
	SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, bitsPerColorComponent);
	SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, bitsPerColorComponent);
	SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, bitsPerColorComponent);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	
	_colorSaturation = 1.0f;
	
	_hdrOutput = NO;
#if OOLITE_WINDOWS
	_hdrMaxBrightness = [prefs oo_floatForKey:@"hdr-max-brightness" defaultValue:1000.0f];
	_hdrPaperWhiteBrightness = [prefs oo_floatForKey:@"hdr-paperwhite-brightness" defaultValue:200.0f];
	if (bitsPerColorComponent == 16)
	{
		// SDL.dll built specifically for Oolite required
		SDL_GL_SetAttribute(SDL_GL_PIXEL_TYPE_FLOAT, 1);
		_hdrOutput = YES;
	}
#endif
	
	// V-sync settings - we set here, but can only verify after SDL_SetVideoMode has been called.
	SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, vSyncPreference);	// V-sync on by default.
	OOLog(@"display.initGL", @"V-Sync %@requested.", vSyncPreference ? @"" : @"not ");
	
	/* Multisampling significantly improves graphics quality with
	 * basically no extra programming effort on our part, especially
	 * for curved surfaces like the planet, but is also expensive - in
	 * the worst case the entire scene must be rendered four
	 * times. For now it can be a hidden setting. If early testing
	 * doesn't give any problems (other than speed on low-end graphics
	 * cards) a game options entry might be useful. - CIM, 24 Aug 2013*/
	if ([prefs oo_boolForKey:@"anti-aliasing" defaultValue:NO])
	{
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4);
	}

	OOLog(@"display.mode.list", @"%@", @"CREATING MODE LIST");
	[self populateFullScreenModelist];
	currentSize = 0;

	// Find what the full screen and windowed settings are.
	fullScreen = NO;
	[self loadFullscreenSettings];
	[self loadWindowSize];

	// Set up the drawing surface's dimensions.
	firstScreen= (fullScreen) ? [self modeAsSize: currentSize] : currentWindowSize;
	viewSize = firstScreen;	// viewSize must be set prior to splash screen initialization

	OOLog(@"display.initGL", @"Trying %d-bpcc, 24-bit depth buffer", bitsPerColorComponent);
	[self createSurface];
	
	if (surface == NULL)
	{
		// Retry with hardcoded 8 bits per color component
		OOLog(@"display.initGL", @"%@", @"Trying 8-bpcc, 32-bit depth buffer");
		SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 32);
		[self createSurface];
		
		if (surface == NULL)
		{
			// Still not working? One last go...
			// Retry, allowing 16-bit contexts.
			OOLog(@"display.initGL", @"%@", @"Trying 5-bpcc, 16-bit depth buffer");
			SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 5);
			SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 5);
			SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 5);
			SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
			// and if it's this bad, forget even trying to multisample!
			SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
			SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);

			[self createSurface];

			if (surface == NULL)
			{
				char * errStr = SDL_GetError();
				OOLogERR(@"display.mode.error", @"Could not create display surface: %s", errStr);
#if OOLITE_WINDOWS
				if (showSplashScreen)
				{
					[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"splash-screen"];
					[[NSUserDefaults standardUserDefaults] synchronize];
					OOLogWARN(@"display.mode.conflict",@"Possible incompatibility between the splash screen and video drivers detected.");
					OOLogWARN(@"display.mode.conflict",@"Oolite will start without showing the splash screen from now on. Override with 'oolite.exe -splash'");
				}
#endif
				exit(1);
			}
		}
	}
	
	int testAttrib = -1;
	OOLog(@"display.initGL", @"%@", @"Achieved color / depth buffer sizes (bits):");
	SDL_GL_GetAttribute(SDL_GL_RED_SIZE, &testAttrib);
	OOLog(@"display.initGL", @"Red: %d", testAttrib);
	SDL_GL_GetAttribute(SDL_GL_GREEN_SIZE, &testAttrib);
	OOLog(@"display.initGL", @"Green: %d", testAttrib);
	SDL_GL_GetAttribute(SDL_GL_BLUE_SIZE, &testAttrib);
	OOLog(@"display.initGL", @"Blue: %d", testAttrib);
	SDL_GL_GetAttribute(SDL_GL_ALPHA_SIZE, &testAttrib);
	OOLog(@"display.initGL", @"Alpha: %d", testAttrib);
	SDL_GL_GetAttribute(SDL_GL_DEPTH_SIZE, &testAttrib);
	OOLog(@"display.initGL", @"Depth Buffer: %d", testAttrib);
#if OOLITE_WINDOWS
	SDL_GL_GetAttribute(SDL_GL_PIXEL_TYPE_FLOAT, &testAttrib);
	OOLog(@"display.initGL", @"Pixel type is float : %d", testAttrib);
#endif
	
	// Verify V-sync successfully set - report it if not
	if (vSyncPreference && SDL_GL_GetAttribute(SDL_GL_SWAP_CONTROL, &vSyncValue) == -1)
	{
		OOLogWARN(@"display.initGL", @"Could not enable V-Sync. Please check that your graphics driver supports the %@_swap_control extension.",
					OOLITE_WINDOWS ? @"WGL_EXT" : @"[GLX_SGI/GLX_MESA]");
	}

	bounds.size.width = surface->w;
	bounds.size.height = surface->h;

	[self autoShowMouse];

	virtualJoystickPosition = NSMakePoint(0.0,0.0);
	mouseWarped = NO;

	typedString = [[NSMutableString alloc] initWithString:@""];
	allowingStringInput = gvStringInputNo;
	isAlphabetKeyDown = NO;

	timeIntervalAtLastClick = timeSinceLastMouseWheel = [NSDate timeIntervalSinceReferenceDate];
	
	_mouseWheelDelta = 0.0f;

	m_glContextInitialized = NO;

	return self;
}

- (void) endSplashScreen
{
#if OOLITE_WINDOWS
	if ([self hdrOutput] && ![self isOutputDisplayHDREnabled])
	{
		if (MessageBox(NULL,	"No primary display in HDR mode was detected.\n\n"
							"If you continue, graphics will not be rendered as intended.\n"
							"Click OK to launch anyway, or Cancel to exit.", "oolite.exe - HDR requested",
							MB_OKCANCEL | MB_ICONWARNING) == IDCANCEL)
		{
			exit (1);
		}
	}
#endif // OOLITE_WINDOWS
	
	if (!showSplashScreen) return;

#if OOLITE_WINDOWS

	wasFullScreen = !fullScreen;
	updateContext = YES;
	ShowWindow(SDL_Window,SW_RESTORE);
	[self initialiseGLWithSize: firstScreen];

#else

	int videoModeFlags = SDL_HWSURFACE | SDL_OPENGL;

	videoModeFlags |= (fullScreen) ? SDL_FULLSCREEN : SDL_RESIZABLE;
	surface = SDL_SetVideoMode(firstScreen.width, firstScreen.height, 32, videoModeFlags);

	if (!surface && fullScreen == YES)
	{
		[self setFullScreenMode: NO];
		videoModeFlags &= ~SDL_FULLSCREEN;
		videoModeFlags |= SDL_RESIZABLE;
		surface = SDL_SetVideoMode(currentWindowSize.width, currentWindowSize.height, 32, videoModeFlags);
	}

	SDL_putenv ("SDL_VIDEO_WINDOW_POS=none"); //stop linux from auto centering on resize

	/* MKW 2011.11.11
	 * Eat all SDL events to gobble up any resize events while the
	 * splash-screen was visible.  They affected the main window after 1.74.
	 * TODO: should really process SDL events while showing the splash-screen

	int numEvents = 0;
	*/
	SDL_Event dummyEvent;
	while (SDL_PollEvent(&dummyEvent))
	{
		/* Do nothing; the below is for development info
		numEvents++;
		OOLog(@"display.splash", @"Suppressed splash-screen event %d: %d ", numEvents, dummyEvent.type);
		*/
	}


#endif

	[self updateScreen];
	[self autoShowMouse];
}


- (void) initKeyMappingData
{
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	// load in our keyboard scancode mappings
#if OOLITE_WINDOWS	
	NSDictionary *kmap = [NSDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keymappings_windows.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
#else
	NSDictionary *kmap = [NSDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keymappings_linux.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
#endif
	// get the stored keyboard code from preferences
	NSString *kbd = [prefs oo_stringForKey:@"keyboard-code" defaultValue:@"default"];
	NSDictionary *subset = [kmap objectForKey:kbd];

	[keyMappings_normal release];
	keyMappings_normal = [[subset objectForKey:@"mapping_normal"] copy];
	[keyMappings_shifted release];
	keyMappings_shifted = [[subset objectForKey:@"mapping_shifted"] copy];
}


- (void) dealloc
{
	if (typedString)
		[typedString release];

	if (screenSizes)
		[screenSizes release];

	if (surface != 0)
	{
		SDL_FreeSurface(surface);
		surface = 0;
	}

	if (keyMappings_normal)
		[keyMappings_normal release];
	
	if (keyMappings_shifted)
		[keyMappings_shifted release];

	SDL_Quit();

	if (matrixManager)
	{
		[matrixManager release];
	}

	[super dealloc];
}

- (void) autoShowMouse
{
	//don't touch the 'please wait...' cursor.
	if (fullScreen)
	{
		if (SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE)
			SDL_ShowCursor(SDL_DISABLE);
	}
	else
	{
		if (SDL_ShowCursor(SDL_QUERY) == SDL_DISABLE)
			SDL_ShowCursor(SDL_ENABLE);
	}
}

- (void) setStringInput: (enum StringInput) value
{
	allowingStringInput = value;
}


- (void) allowStringInput: (BOOL) value
{
	if (value)
		allowingStringInput = gvStringInputAlpha;
	else
		allowingStringInput = gvStringInputNo;
}

-(enum StringInput) allowingStringInput
{
	return allowingStringInput;
}


- (NSString *) typedString
{
	return typedString;
}


- (void) resetTypedString
{
	[typedString setString:@""];
}


- (void) setTypedString:(NSString*) value
{
	[typedString setString:value];
}


- (NSRect) bounds
{
	return bounds;
}


- (NSSize) viewSize
{
	return viewSize;
}


- (NSSize) backingViewSize
{
	return viewSize;
}


- (GLfloat) display_z
{
	return display_z;
}


- (GLfloat) x_offset
{
	return x_offset;
}


- (GLfloat) y_offset
{
	return y_offset;
}


- (GameController *) gameController
{
	return gameController;
}


- (void) setGameController:(GameController *) controller
{
	gameController = controller;
}


- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
	[self autoShowMouse];
	[self setMouseInDeltaMode:OOMouseInteractionModeIsFlightMode(newMode)];
}


- (BOOL) inFullScreenMode
{
	return fullScreen;
}

#ifdef GNUSTEP
- (void) setFullScreenMode:(BOOL)fsm
{
	fullScreen = fsm;

	// Save the settings for later.
	[[NSUserDefaults standardUserDefaults]
		setBool: fullScreen forKey:@"fullscreen"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}


- (void) toggleScreenMode
{
	[self setFullScreenMode: !fullScreen];
#if OOLITE_WINDOWS
	[self getCurrentMonitorInfo:&monitorInfo];
#endif
 	if(fullScreen)
	{
#if OOLITE_WINDOWS
		if(![self isRunningOnPrimaryDisplayDevice])
		{
			[self initialiseGLWithSize:NSMakeSize(monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left,
												monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top)];
		}
		else  [self initialiseGLWithSize:[self modeAsSize: currentSize]];
#else
 		[self initialiseGLWithSize:[self modeAsSize: currentSize]];
#endif
	}
	else
		[self initialiseGLWithSize: currentWindowSize];


	// do screen resizing updates
	if ([PlayerEntity sharedPlayer])
	{
		[[PlayerEntity sharedPlayer] doGuiScreenResizeUpdates];
	}
}


- (void) setDisplayMode:(int)mode  fullScreen:(BOOL)fsm
{
	[self setFullScreenMode: fsm];
	currentSize=mode;
	if(fullScreen)
		[self initialiseGLWithSize: [self modeAsSize: mode]];
}


- (int) indexOfCurrentSize
{
	return currentSize;
}


- (void) setScreenSize: (int)sizeIndex
{
	currentSize=sizeIndex;
	if(fullScreen)
		[self initialiseGLWithSize: [self modeAsSize: currentSize]];
}


- (NSMutableArray *)getScreenSizeArray
{
	return screenSizes;
}


- (NSSize) modeAsSize:(int)sizeIndex
{
	NSDictionary *mode=[screenSizes objectAtIndex: sizeIndex];
	return NSMakeSize([[mode objectForKey: kOODisplayWidth] intValue],
        		[[mode objectForKey: kOODisplayHeight] intValue]);
}

#endif

- (void) display
{
	[self updateScreen];
}

- (void) updateScreen
{
	[self drawRect: NSMakeRect(0, 0, viewSize.width, viewSize.height)];
}

- (void) drawRect:(NSRect)rect
{
	[self updateScreenWithVideoMode:YES];
}

- (void) updateScreenWithVideoMode:(BOOL) v_mode
{
	if ((viewSize.width != surface->w)||(viewSize.height != surface->h)) // resized
	{
#if OOLITE_LINUX
		m_glContextInitialized = NO; //probably not needed
#endif
		viewSize.width = surface->w;
		viewSize.height = surface->h;
	}

    if (m_glContextInitialized == NO)
	{
		[self initialiseGLWithSize:viewSize useVideoMode:v_mode];
	}

	if (surface == 0)
		return;

	// do all the drawing!
	//
	if (UNIVERSE)  [UNIVERSE drawUniverse];
	else
	{
		// not set up yet, draw a black screen
		glClearColor( 0.0, 0.0, 0.0, 0.0);
		glClear( GL_COLOR_BUFFER_BIT);
	}

	SDL_GL_SwapBuffers();
}

- (void) initSplashScreen
{
	if (!showSplashScreen) return;

	//too early for OOTexture!
	SDL_Surface     	*image=NULL;
	SDL_Rect			dest;

	NSString		*imagesDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Images"];

	image = SDL_LoadBMP([[imagesDir stringByAppendingPathComponent:@"splash.bmp"] UTF8String]);

	if (image == NULL)
	{
		SDL_FreeSurface(image);
		OOLogWARN(@"sdl.gameStart", @"%@", @"image 'splash.bmp' not found!");
		[self endSplashScreen];
		return;
	}

	dest.x = 0;
	dest.y = 0;
	dest.w = image->w;
	dest.h = image->h;

  #if OOLITE_WINDOWS

	dest.x = (GetSystemMetrics(SM_CXSCREEN)- dest.w)/2;
	dest.y = (GetSystemMetrics(SM_CYSCREEN)-dest.h)/2;
	SetWindowLong(SDL_Window,GWL_STYLE,GetWindowLong(SDL_Window,GWL_STYLE) & ~WS_CAPTION & ~WS_THICKFRAME);
	ShowWindow(SDL_Window,SW_RESTORE);
	MoveWindow(SDL_Window,dest.x,dest.y,dest.w,dest.h,TRUE);

  #else

	/* MKW 2011.11.11
	 * According to Marc using the NOFRAME flag causes trouble under Ubuntu 8.04.
	 *
	 * The current Ubuntu LTS is 10.04, which doesn't seem to have that problem.
	 * 12.04 LTS is going to be released soon, also without apparent problems.
	 * Changed to SDL_NOFRAME, throwing caution to the wind - Kaks 2012.03.23
	 * Took SDL_NOFRAME out, since it still causes strange problems here - cim 2012.04.09
	 */
	 surface = SDL_SetVideoMode(dest.w, dest.h, 32, SDL_HWSURFACE | SDL_OPENGL);

  #endif

	OOSetOpenGLState(OPENGL_STATE_OVERLAY);

	glViewport( 0, 0, dest.w, dest.h);

	glEnable( GL_TEXTURE_2D );
	glClearColor( 0.0f, 0.0f, 0.0f, 0.0f );
	glClear( GL_COLOR_BUFFER_BIT );

	[matrixManager resetProjection];
	[matrixManager orthoLeft: 0.0f right: dest.w bottom: dest.h top: 0.0 near: -1.0 far: 1.0];
	[matrixManager syncProjection];

	[matrixManager resetModelView];
	[matrixManager syncModelView];

	GLuint texture;
	GLenum texture_format;
	GLint  nOfColors;

	// get the number of channels in the SDL image
	nOfColors = image->format->BytesPerPixel;
	if (nOfColors == 4)     // contains an alpha channel
	{
		if (image->format->Rmask == 0x000000ff)
			texture_format = GL_RGBA;
		else
			texture_format = GL_BGRA;
	}
	else if (nOfColors == 3)     // no alpha channel
	{
		if (image->format->Rmask == 0x000000ff)
			texture_format = GL_RGB;
		else
			texture_format = GL_BGR;
	} else {
		SDL_FreeSurface(image);
		OOLog(@"Sdl.GameStart", @"%@", @"----- Encoding error within image 'splash.bmp'");
		[self endSplashScreen];
		return;
	}

	glGenTextures( 1, &texture );
	glBindTexture( GL_TEXTURE_2D, texture );

	// Set the texture's stretching properties
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
	glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );

	// Set the texture image data with the information  from SDL_Surface
	glTexImage2D( GL_TEXTURE_2D, 0, nOfColors, image->w, image->h, 0,
                      texture_format, GL_UNSIGNED_BYTE, image->pixels );

	glBindTexture( GL_TEXTURE_2D, texture );
	glBegin( GL_QUADS );

	glTexCoord2i( 0, 0 );
	glVertex2i( 0, 0 );
	glTexCoord2i( 1, 0 );
	glVertex2i( dest.w, 0 );
	glTexCoord2i( 1, 1 );
	glVertex2i( dest.w, dest.h );
	glTexCoord2i( 0, 1 );
	glVertex2i( 0, dest.h );

	glEnd();

	SDL_GL_SwapBuffers();
	[matrixManager resetModelView];
	[matrixManager syncModelView];

	if ( image ) {
		SDL_FreeSurface( image );
	}
	glDeleteTextures(1, &texture);

	glDisable( GL_TEXTURE_2D );
	OOVerifyOpenGLState();
}


#if OOLITE_WINDOWS
- (MONITORINFOEX) currentMonitorInfo
{
	return monitorInfo;
}


- (BOOL) getCurrentMonitorInfo:(MONITORINFOEX *)mInfo
{
	HMONITOR hMon = MonitorFromWindow(SDL_Window, MONITOR_DEFAULTTOPRIMARY);
	ZeroMemory(mInfo, sizeof(MONITORINFOEX));
	mInfo->cbSize = sizeof(MONITORINFOEX);
	if (GetMonitorInfo (hMon, (LPMONITORINFO)mInfo))
	{
		return YES;
	}
	return NO;
}


- (BOOL) isRunningOnPrimaryDisplayDevice
{
	BOOL result = YES;
	[self getCurrentMonitorInfo:&monitorInfo];
	if (!(monitorInfo.dwFlags & MONITORINFOF_PRIMARY))
	{
		result = NO;
	}
	return result;
}


- (void) grabMouseInsideGameWindow:(BOOL) value
{
	if(value)
	{
		RECT gameWindowRect;
		GetWindowRect(SDL_Window, &gameWindowRect);
		ClipCursor(&gameWindowRect);
	}
	else
	{
		ClipCursor(NULL);
	}
	grabMouseStatus = !!value;
}


- (void) stringToClipboard:(NSString *)stringToCopy
{
	if (stringToCopy)
	{
		const char *clipboardText = [stringToCopy cStringUsingEncoding:NSUTF8StringEncoding];
		const size_t clipboardTextLength = strlen(clipboardText) + 1;
		HGLOBAL clipboardMem = GlobalAlloc(GMEM_MOVEABLE, clipboardTextLength);
		if (clipboardMem)
		{
			memcpy(GlobalLock(clipboardMem), clipboardText, clipboardTextLength);
			GlobalUnlock(clipboardMem);
			OpenClipboard(0);
			EmptyClipboard();
			if (!SetClipboardData(CF_TEXT, clipboardMem))
			{
				OOLog(@"stringToClipboard.failed", @"Failed to copy string %@ to clipboard", stringToCopy);
				// free global allocated memory if clipboard copy failed
				// note: no need to free it if copy succeeded; the OS becomes
				// the owner of the copied memory once SetClipboardData has
				// been executed successfully
				GlobalFree(clipboardMem);
			}
			CloseClipboard();
		}
	}
}


- (void) resetSDLKeyModifiers
{
	// this is used when we regain focus to ensure that all
	// modifier keys are reset to their correct status
	SDLMod modState = SDL_GetModState();
	Uint8 *keyState = SDL_GetKeyState(NULL);
	BYTE keyboardStatus[256];
	#define OO_RESET_SDLKEY_MODIFIER(vkCode, kModCode, sdlkCode)	do {\
	if (keyboardStatus[vkCode] & 0x0080) \
	{ \
		modState |= kModCode; \
		keyState[sdlkCode] = SDL_PRESSED; \
	} \
	else \
	{ \
		modState &= ~kModCode; \
		keyState[sdlkCode] = SDL_RELEASED; \
	} \
	} while(0)
	if (GetKeyboardState(keyboardStatus))
	{
		// A bug noted here https://github.com/libsdl-org/SDL-1.2/issues/449
		// was patched in SDL here https://github.com/libsdl-org/SDL-1.2/commit/09980c67290f11c3d088a6a039c550be83536c81
		// This was replicated in our SDL binary (Windows-deps rev. 36fd5e6),
		// so we no longer need to check the state of Alt when returning to the app.
		// SDL change researched and implemented by Nikos 20220622.
		// Alt key
		//OO_RESET_SDLKEY_MODIFIER(VK_LMENU, KMOD_LALT, SDLK_LALT);
		//OO_RESET_SDLKEY_MODIFIER(VK_RMENU, KMOD_RALT, SDLK_RALT);
		//opt =  (modState & KMOD_LALT || modState & KMOD_RALT);
		
		//Ctrl key
		OO_RESET_SDLKEY_MODIFIER(VK_LCONTROL, KMOD_LCTRL, SDLK_LCTRL);
		OO_RESET_SDLKEY_MODIFIER(VK_RCONTROL, KMOD_RCTRL, SDLK_RCTRL);
		ctrl =  (modState & KMOD_LCTRL || modState & KMOD_RCTRL);
		
		// Shift key
		OO_RESET_SDLKEY_MODIFIER(VK_LSHIFT, KMOD_LSHIFT, SDLK_LSHIFT);
		OO_RESET_SDLKEY_MODIFIER(VK_RSHIFT, KMOD_RSHIFT, SDLK_RSHIFT);
		shift =  (modState & KMOD_LSHIFT || modState & KMOD_RSHIFT);
		
		// Caps Lock key state
		if (GetKeyState(VK_CAPITAL) & 0x0001)
		{
			modState |= KMOD_CAPS;
			keyState[SDLK_CAPSLOCK] = SDL_PRESSED;
		}
		else
		{
			modState &= ~KMOD_CAPS;
			keyState[SDLK_CAPSLOCK] = SDL_RELEASED;
		}
	}
	
	SDL_SetModState(modState);
}


- (void) setWindowBorderless:(BOOL)borderless
{
	LONG currentWindowStyle = GetWindowLong(SDL_Window, GWL_STYLE);
	
	// window already has the desired style?
	if ((!borderless && (currentWindowStyle & WS_CAPTION)) ||
		(borderless && !(currentWindowStyle & WS_CAPTION)))  return;
		
	if (borderless)
	{
		SetWindowLong(SDL_Window, GWL_STYLE, currentWindowStyle & ~WS_CAPTION & ~WS_THICKFRAME);
	}
	else
	{
		SetWindowLong(SDL_Window, GWL_STYLE, currentWindowStyle |
						WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX );
		[self refreshDarKOrLightMode];
	}
	SetWindowPos(SDL_Window, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
}


- (void) refreshDarKOrLightMode
{
	int shouldSetDarkMode = [self isDarkModeOn];
	DwmSetWindowAttribute (SDL_Window, DWMWA_USE_IMMERSIVE_DARK_MODE, &shouldSetDarkMode, sizeof(shouldSetDarkMode));
}


- (BOOL) isDarkModeOn
{
	char buffer[4];
	DWORD bufferSize = sizeof(buffer);
	
	// reading a REG_DWORD value from the Registry
	HRESULT resultRegGetValue = RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
									L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, buffer, &bufferSize);
	if (resultRegGetValue != ERROR_SUCCESS)
	{
		return NO;
	}
	
	// get our 4 obtained bytes into integer little endian format
	int i = (int)(buffer[3] << 24 | buffer[2] << 16 | buffer[1] << 8 | buffer[0]);
	
	// dark mode is 0, light mode is 1
	return i == 0;
}


- (BOOL) atDesktopResolution
{
	return atDesktopResolution;
}


- (BOOL) hdrOutput
{
	return _hdrOutput;
}


- (BOOL) isOutputDisplayHDREnabled
{
	UINT32 pathCount, modeCount;
	DISPLAYCONFIG_PATH_INFO *pPathInfoArray;
	DISPLAYCONFIG_MODE_INFO *pModeInfoArray;
	UINT32 flags = QDC_ONLY_ACTIVE_PATHS | QDC_VIRTUAL_MODE_AWARE;
	LONG tempResult = ERROR_SUCCESS;
	BOOL result = NO;
	
	do
	{
		// determine how many path and mode structures to allocate
		tempResult = GetDisplayConfigBufferSizes(flags, &pathCount, &modeCount);
		
		if (tempResult != ERROR_SUCCESS)
		{
			OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: %d", HRESULT_FROM_WIN32(tempResult));
			return NO;
		}
		
		// allocate the path and mode arrays
		pPathInfoArray = (DISPLAYCONFIG_PATH_INFO *)malloc(pathCount * sizeof(DISPLAYCONFIG_PATH_INFO));
		if (!pPathInfoArray)
		{
			OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: -1");
			return NO;
		}
		
		pModeInfoArray = (DISPLAYCONFIG_MODE_INFO *)malloc(modeCount * sizeof(DISPLAYCONFIG_MODE_INFO));
		if (!pModeInfoArray)
		{
			if (pPathInfoArray)
				free(pPathInfoArray);
			OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: -1");
			return NO;
		}
		
		// get all active paths and their modes
		tempResult = QueryDisplayConfig(flags, &pathCount, pPathInfoArray, &modeCount, pModeInfoArray, NULL);
		
		if (tempResult != ERROR_SUCCESS)
		{
			OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: %d", HRESULT_FROM_WIN32(tempResult));
			return NO;
		}
	
		// the function may have returned fewer paths/modes than estimated
		pPathInfoArray = realloc(pPathInfoArray, pathCount * sizeof(DISPLAYCONFIG_PATH_INFO));
		if (!pPathInfoArray)
		{
			OOLogERR(@"gameView.isOutputDisplayHDREnabled", @"Failed ro reallocate pPathInfoArray");
			exit (1);
		}
		pModeInfoArray = realloc(pModeInfoArray, modeCount * sizeof(DISPLAYCONFIG_MODE_INFO));
		if (!pModeInfoArray)
		{
			OOLogERR(@"gameView.isOutputDisplayHDREnabled", @"Failed to reallocate pModeInfoArray");
			exit (1);
		}
	
		// it's possible that between the call to GetDisplayConfigBufferSizes and QueryDisplayConfig
		// that the display state changed, so loop on the case of ERROR_INSUFFICIENT_BUFFER.
	} while (tempResult == ERROR_INSUFFICIENT_BUFFER);
	
	if (tempResult != ERROR_SUCCESS)
	{
		OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: %d", HRESULT_FROM_WIN32(tempResult));
		return NO;
	}

    // for each active path
	int i;
	for (i = 0; i < pathCount; i++)
	{
		DISPLAYCONFIG_PATH_INFO *path = &pPathInfoArray[i];
		// find the target (monitor) friendly name
		DISPLAYCONFIG_TARGET_DEVICE_NAME targetName = {};
		targetName.header.adapterId = path->targetInfo.adapterId;
		targetName.header.id = path->targetInfo.id;
		targetName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
		targetName.header.size = sizeof(targetName);
		tempResult = DisplayConfigGetDeviceInfo(&targetName.header);
		
		if (tempResult != ERROR_SUCCESS)
		{
			OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: %d", HRESULT_FROM_WIN32(tempResult));
			return NO;
		}
		
		// find the advanced color information
		DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO advColorInfo = {};
		advColorInfo.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
		advColorInfo.header.adapterId = path->targetInfo.adapterId;
		advColorInfo.header.id = path->targetInfo.id;
		advColorInfo.header.size = sizeof(advColorInfo);
		
		tempResult = DisplayConfigGetDeviceInfo(&advColorInfo.header);
		
		if (tempResult != ERROR_SUCCESS)
		{
			OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Code: %d", HRESULT_FROM_WIN32(tempResult));
			return NO;
		}
		
		char saveDeviceName[64];
		wchar_t wcsDeviceID[256];
		DISPLAY_DEVICE dd;
		ZeroMemory(&dd, sizeof(dd));
		dd.cb = sizeof(dd);
		EnumDisplayDevices(NULL, i, &dd, 0);
		BOOL isPrimaryDisplayDevice = dd.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE;
		// second call to EnumDisplayDevices gets us the monitor device ID
		strncpy(saveDeviceName, dd.DeviceName, 33);
		EnumDisplayDevices(saveDeviceName, 0, &dd, 0x00000001);
		mbstowcs(wcsDeviceID, dd.DeviceID, 129);
		
		// we are starting om the primary device, so check that one for advanced color support
		// just to be safe, ensure that the monitor device from QDC being checked is the same as the one from EnumDisplayDevices
		if (isPrimaryDisplayDevice && !wcscmp(targetName.monitorDevicePath, wcsDeviceID) && 
			advColorInfo.advancedColorSupported && advColorInfo.advancedColorEnabled)
		{
			result = YES;
			break;
		}
	}
	
	OOLog(@"gameView.isOutputDisplayHDREnabled", @"HDR display output requested - checking availability: %@", result ? @"YES" : @"NO");
	
	free (pModeInfoArray);
	free (pPathInfoArray);

	return result;
}


- (float) hdrMaxBrightness
{
	return _hdrMaxBrightness;
}


- (void) setHDRMaxBrightness: (float)newMaxBrightness
{
	if (newMaxBrightness < MIN_HDR_MAXBRIGHTNESS)  newMaxBrightness = MIN_HDR_MAXBRIGHTNESS;
	if (newMaxBrightness > MAX_HDR_MAXBRIGHTNESS)  newMaxBrightness = MAX_HDR_MAXBRIGHTNESS;
	_hdrMaxBrightness = newMaxBrightness;
	
	[[NSUserDefaults standardUserDefaults] setFloat:_hdrMaxBrightness forKey:@"hdr-max-brightness"];
}


- (float) hdrPaperWhiteBrightness
{
	return _hdrPaperWhiteBrightness;
}


- (void) setHDRPaperWhiteBrightness: (float)newPaperWhiteBrightness
{
	if (newPaperWhiteBrightness < MIN_HDR_PAPERWHITE)  newPaperWhiteBrightness = MIN_HDR_PAPERWHITE;
	if (newPaperWhiteBrightness > MAX_HDR_PAPERWHITE)  newPaperWhiteBrightness = MAX_HDR_PAPERWHITE;
	_hdrPaperWhiteBrightness = newPaperWhiteBrightness;
	
	[[NSUserDefaults standardUserDefaults] setFloat:_hdrPaperWhiteBrightness forKey:@"hdr-paperwhite-brightness"];
}


#else	// Linus stub methods

// for Linux we assume we are always on the primary monitor for now
- (BOOL) isRunningOnPrimaryDisplayDevice
{
	return YES;
}


- (void) grabMouseInsideGameWindow:(BOOL) value
{
	// do nothing
}


- (void) stringToClipboard:(NSString *)stringToCopy
{
	// TODO: implement string clipboard copy for Linux
}


- (void) resetSDLKeyModifiers
{
	// probably not needed for Linux
}


- (void) setWindowBorderless:(BOOL)borderless
{
	// do nothing on Linux
}


- (BOOL) hdrOutput
{
	return NO;
}


- (BOOL) isOutputDisplayHDREnabled
{
	return NO;
}

#endif //OOLITE_WINDOWS


- (void) initialiseGLWithSize:(NSSize) v_size
{
	[self initialiseGLWithSize:v_size useVideoMode:YES];
}


- (void) initialiseGLWithSize:(NSSize) v_size useVideoMode:(BOOL) v_mode
{
#if OOLITE_LINUX
	NSSize oldViewSize = viewSize;
#endif
	viewSize = v_size;
	OOLog(@"display.initGL", @"Requested a new surface of %d x %d, %@.", (int)viewSize.width, (int)viewSize.height,(fullScreen ? @"fullscreen" : @"windowed"));
	SDL_GL_SwapBuffers();	// clear the buffer before resize
	
#if OOLITE_WINDOWS
	if (!updateContext) return;

	DEVMODE settings;
	settings.dmSize        = sizeof(DEVMODE);
	settings.dmDriverExtra = 0;
	EnumDisplaySettings(0, ENUM_CURRENT_SETTINGS, &settings);
	
	WINDOWPLACEMENT windowPlacement;
	windowPlacement.length = sizeof(WINDOWPLACEMENT);
	GetWindowPlacement(SDL_Window, &windowPlacement);
	
	static BOOL lastWindowPlacementMaximized = NO;
	if (fullScreen && (windowPlacement.showCmd == SW_SHOWMAXIMIZED))
	{
		if (!wasFullScreen)
		{
			lastWindowPlacementMaximized = YES;
		}
	}
	
	if (lastWindowPlacementMaximized)
	{
		windowPlacement.showCmd = SW_SHOWMAXIMIZED;
	}
	
	// are we attempting to go to a different screen resolution? Note: this also takes care of secondary monitor situations because 
	// by design the only resolution available for fullscreen on a secondary display device is its native one - Nikos 20150605
	BOOL changingResolution = 	[self isRunningOnPrimaryDisplayDevice] &&
								((fullScreen && (settings.dmPelsWidth != viewSize.width || settings.dmPelsHeight != viewSize.height)) ||
								(wasFullScreen && (settings.dmPelsWidth != [[[screenSizes objectAtIndex:0] objectForKey: kOODisplayWidth] intValue]
								|| settings.dmPelsHeight != [[[screenSizes objectAtIndex:0] objectForKey: kOODisplayHeight] intValue])));
			
	RECT wDC;

	if (fullScreen)
	{
		/*NOTE: If we ever decide to change the default behaviour of launching
		always on primary monitor to launching on the monitor the program was 
		started on, all that needs to be done is comment out the line below, as
		well as the identical one in the else branch further down.
		Nikos 20141222
	   */
	   [self getCurrentMonitorInfo: &monitorInfo];
		
		settings.dmPelsWidth = viewSize.width;
		settings.dmPelsHeight = viewSize.height;
		settings.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
				
		// just before going fullscreen, save the location of the current window. It
		// may be needed in case of potential attempts to move our fullscreen window
		// in a maximized state (yes, in Windows this is entirely possible).
		if(lastWindowPlacementMaximized)
		{
			CopyRect(&lastGoodRect, &windowPlacement.rcNormalPosition);
			// if maximized, switch to normal placement before going full screen
			windowPlacement.showCmd = SW_SHOWNORMAL;
			SetWindowPlacement(SDL_Window, &windowPlacement);
		}
		else  GetWindowRect(SDL_Window, &lastGoodRect);
		
		// ok, can go fullscreen now
		SetForegroundWindow(SDL_Window);
		if (changingResolution)
		{
			if (ChangeDisplaySettingsEx(monitorInfo.szDevice, &settings, NULL, CDS_FULLSCREEN, NULL) != DISP_CHANGE_SUCCESSFUL)
			{
				m_glContextInitialized = YES;
				OOLogERR(@"displayMode.change.error", @"Could not switch to requested display mode.");
				return;
			}
			atDesktopResolution = settings.dmPelsWidth == [[[screenSizes objectAtIndex:0] objectForKey: kOODisplayWidth] intValue]
								&& settings.dmPelsHeight == [[[screenSizes objectAtIndex:0] objectForKey: kOODisplayHeight] intValue];
		}
		
		MoveWindow(SDL_Window, monitorInfo.rcMonitor.left, monitorInfo.rcMonitor.top, (int)viewSize.width, (int)viewSize.height, TRUE);
		if(!wasFullScreen)
		{
			[self setWindowBorderless:YES];
		}
	}
	
	else if ( wasFullScreen )
	{
		if (changingResolution)
		{
			// restore original desktop resolution
			if (ChangeDisplaySettingsEx(NULL, NULL, NULL, 0, NULL) == DISP_CHANGE_SUCCESSFUL)
			{
				atDesktopResolution = YES;
			}
		}
		
		/*NOTE: If we ever decide to change the default behaviour of launching
		always on primary monitor to launching on the monitor the program was 
		started on, we need to comment out the line below.
		For now, this line is needed for correct positioning of our window in case
		we return from a non-native resolution fullscreen and has to come after the
		display settings have been reverted.
		Nikos 20141222
		*/
		[self getCurrentMonitorInfo: &monitorInfo];
		
		if (lastWindowPlacementMaximized)  CopyRect(&windowPlacement.rcNormalPosition, &lastGoodRect);
		SetWindowPlacement(SDL_Window, &windowPlacement);
		if (!lastWindowPlacementMaximized)
		{
			MoveWindow(SDL_Window,	(monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left - (int)viewSize.width)/2 +
								monitorInfo.rcMonitor.left,
								(monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top - (int)viewSize.height)/2 +
								monitorInfo.rcMonitor.top,
								(int)viewSize.width, (int)viewSize.height, TRUE);
		}
		
		[self setWindowBorderless:NO];
								
		lastWindowPlacementMaximized = NO;
		ShowWindow(SDL_Window,SW_SHOW);
	}
	
	// stop saveWindowSize from reacting to caption & frame if necessary
	saveSize = !wasFullScreen;

	GetClientRect(SDL_Window, &wDC);

	if (!fullScreen && (bounds.size.width != wDC.right - wDC.left
					|| bounds.size.height != wDC.bottom - wDC.top))
	{
		// Resize the game window if needed. When we ask for a W x H
		// window, we intend that the client area be W x H. The actual
		// window itself must become big enough to accomodate an area
		// of such size. 
		if (wasFullScreen)	// this is true when switching from full screen or when starting in windowed mode
							//after the splash screen has ended
		{
			RECT desiredClientRect;
			GetWindowRect(SDL_Window, &desiredClientRect);
			AdjustWindowRect(&desiredClientRect, WS_CAPTION | WS_THICKFRAME, FALSE);
			SetWindowPos(SDL_Window, NULL,	desiredClientRect.left, desiredClientRect.top,
											desiredClientRect.right - desiredClientRect.left,
											desiredClientRect.bottom - desiredClientRect.top, 0);
		}
		GetClientRect(SDL_Window, &wDC);
		viewSize.width = wDC.right - wDC.left;
		viewSize.height = wDC.bottom - wDC.top;
	}

	// Reset bounds and viewSize to current values
	bounds.size.width = viewSize.width = wDC.right - wDC.left;
	bounds.size.height = viewSize.height = wDC.bottom - wDC.top;
	
	if (fullScreen) // bounds on fullscreen coincide with client area, since we are borderless
	{
		bounds.origin.x = monitorInfo.rcMonitor.left;
		bounds.origin.y = monitorInfo.rcMonitor.top;
	}
	wasFullScreen=fullScreen;

#else //OOLITE_LINUX

	int videoModeFlags = SDL_HWSURFACE | SDL_OPENGL;

	if (v_mode == NO)
		videoModeFlags |= SDL_NOFRAME;
	if (fullScreen == YES)
	{
		videoModeFlags |= SDL_FULLSCREEN;
	}
	else
	{
		videoModeFlags |= SDL_RESIZABLE;
	}
	surface = SDL_SetVideoMode((int)viewSize.width, (int)viewSize.height, 32, videoModeFlags);

	if (!surface && fullScreen == YES)
	{
		[self setFullScreenMode: NO];
		viewSize = oldViewSize;
		videoModeFlags &= ~SDL_FULLSCREEN;
		videoModeFlags |= SDL_RESIZABLE;
		surface = SDL_SetVideoMode((int)viewSize.width, (int)viewSize.height, 32, videoModeFlags);
	}

	if (!surface)
	{
	  // we should always have a valid surface, but in case we don't
		OOLogERR(@"display.mode.error",@"Unable to change display mode: %s",SDL_GetError());
		exit(1);
	}

	bounds.size.width = surface->w;
	bounds.size.height = surface->h;

#endif
	OOLog(@"display.initGL", @"Created a new surface of %d x %d, %@.", (int)viewSize.width, (int)viewSize.height,(fullScreen ? @"fullscreen" : @"windowed"));

	if (viewSize.width/viewSize.height > 4.0/3.0) {
		display_z = 480.0 * bounds.size.width/bounds.size.height;
		x_offset = 240.0 * bounds.size.width/bounds.size.height;
		y_offset = 240.0;
	} else {
		display_z = 640.0;
		x_offset = 320.0;
		y_offset = 320.0 * bounds.size.height/bounds.size.width;
	}

	if (surface != 0)  SDL_FreeSurface(surface);

	[self autoShowMouse];

	[[self gameController] setUpBasicOpenGLStateWithSize:viewSize];
	SDL_GL_SwapBuffers();
	squareX = 0.0f;

	m_glContextInitialized = YES;
}


- (float) colorSaturation
{
	return _colorSaturation;
}


- (void) adjustColorSaturation:(float)colorSaturationAdjustment;
{
	_colorSaturation += colorSaturationAdjustment;
	_colorSaturation = OOClamp_0_max_f(_colorSaturation, MAX_COLOR_SATURATION);
}


- (BOOL) snapShot:(NSString *)filename
{
	BOOL snapShotOK = YES;
	SDL_Surface* tmpSurface;

	// backup the previous directory
	NSString* originalDirectory = [[NSFileManager defaultManager] currentDirectoryPath];
	// use the snapshots directory
	[[NSFileManager defaultManager] chdirToSnapshotPath];

	BOOL				withFilename = (filename != nil);
	static unsigned		imageNo = 0;
	unsigned			tmpImageNo = 0;
	NSString			*pathToPic = nil;
	NSString			*baseName = @"oolite";

#if SNAPSHOTS_PNG_FORMAT
	NSString			*extension = @".png";
#else
	NSString			*extension = @".bmp";
#endif

	if (withFilename)
	{
		baseName = filename;
		pathToPic = [filename stringByAppendingString:extension];
	}
	else
	{
		tmpImageNo = imageNo;
	}

	if (withFilename && [[NSFileManager defaultManager] fileExistsAtPath:pathToPic])
	{
		OOLog(@"screenshot.filenameExists", @"Snapshot \"%@%@\" already exists - adding numerical sequence.", pathToPic, extension);
		pathToPic = nil;
	}

	if (pathToPic == nil)
	{
		do
		{
			tmpImageNo++;
			pathToPic = [NSString stringWithFormat:@"%@-%03d%@", baseName, tmpImageNo, extension];
		} while ([[NSFileManager defaultManager] fileExistsAtPath:pathToPic]);
	}

	if (!withFilename)
	{
		imageNo = tmpImageNo;
	}

	OOLog(@"screenshot", @"Saved screen shot \"%@\" (%u x %u pixels).", pathToPic, surface->w, surface->h);

	int pitch = surface->w * 3;
	unsigned char *pixls = malloc(pitch * surface->h);
	int y;
	int off;

	if (surface->w % 4) glPixelStorei(GL_PACK_ALIGNMENT,1);
	else                glPixelStorei(GL_PACK_ALIGNMENT,4);
	for (y=surface->h-1, off=0; y>=0; y--, off+=pitch)
	{
		glReadPixels(0, y, surface->w, 1, GL_RGB, GL_UNSIGNED_BYTE, pixls + off);
	}
	
	tmpSurface=SDL_CreateRGBSurfaceFrom(pixls,surface->w,surface->h,24,surface->w*3,0xFF,0xFF00,0xFF0000,0x0);
#if SNAPSHOTS_PNG_FORMAT
	if(![self pngSaveSurface:pathToPic withSurface:tmpSurface])
	{
		OOLog(@"screenshotPNG", @"Failed to save %@", pathToPic);
		snapShotOK = NO;
	}
#else
	if (SDL_SaveBMP(tmpSurface, [pathToPic UTF8String]) == -1)
	{
		OOLog(@"screenshotBMP", @"Failed to save %@", pathToPic);
		snapShotOK = NO;
	}
#endif
	SDL_FreeSurface(tmpSurface);
	free(pixls);
	
	// if outputting HDR signal, save also a Radiance .hdr snapshot
	if ([self hdrOutput])
	{
		NSString *pathToPicHDR = [pathToPic stringByReplacingString:@".png" withString:@".hdr"];
		OOLog(@"screenshot", @"Saved screen shot \"%@\" (%u x %u pixels).", pathToPicHDR, surface->w, surface->h);
		GLfloat *pixlsf = (GLfloat *)malloc(pitch * surface->h * sizeof(GLfloat));
		for (y=surface->h-1, off=0; y>=0; y--, off+=pitch)
		{
			glReadPixels(0, y, surface->w, 1, GL_RGB, GL_FLOAT, pixlsf + off);
		}
		if (!stbi_write_hdr([pathToPicHDR cStringUsingEncoding:NSUTF8StringEncoding], surface->w, surface->h, 3, pixlsf))
		{
			OOLog(@"screenshotHDR", @"Failed to save %@", pathToPicHDR);
			snapShotOK = NO;
		}
		free(pixlsf);
	}
	
	// return to the previous directory
	[[NSFileManager defaultManager] changeCurrentDirectoryPath:originalDirectory];
	return snapShotOK;
}


#if SNAPSHOTS_PNG_FORMAT
// This method is heavily based on 'Mars, Land of No Mercy' SDL examples, by Angelo "Encelo" Theodorou, see http://encelo.netsons.org/programming/sdl
- (BOOL) pngSaveSurface:(NSString *)fileName withSurface:(SDL_Surface *)surf
{
	FILE *fp;
	png_structp pngPtr;
	png_infop infoPtr;
	int i, colorType;
	png_bytep *rowPointers;

	fp = fopen([fileName UTF8String], "wb");
	if (fp == NULL)
	{
		OOLog(@"pngSaveSurface.fileCreate.failed", @"Failed to create output screenshot file %@", fileName);
		return NO;
	}

	// initialize png structures (no callbacks)
	pngPtr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
	if (pngPtr == NULL)
	{
		return NO;
	}

	infoPtr = png_create_info_struct(pngPtr);
	if (infoPtr == NULL) {
		png_destroy_write_struct(&pngPtr, (png_infopp)NULL);
		OOLog(@"pngSaveSurface.info_struct.failed", @"%@", @"png_create_info_struct error");
		exit(-1);
	}

	if (setjmp(png_jmpbuf(pngPtr)))
	{
		png_destroy_write_struct(&pngPtr, &infoPtr);
		fclose(fp);
		exit(-1);
	}

	png_init_io(pngPtr, fp);

	colorType = PNG_COLOR_MASK_COLOR; /* grayscale not supported */
	if (surf->format->palette)
	{
		colorType |= PNG_COLOR_MASK_PALETTE;
	}
	else if (surf->format->Amask)
	{
		colorType |= PNG_COLOR_MASK_ALPHA;
	}

	png_set_IHDR(pngPtr, infoPtr, surf->w, surf->h, 8, colorType,	PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
	
	// if we are outputting HDR, our backbuffer is linear, so gamma is 1.0. Make sure our png has this info
	// note: some image viewers seem to ignore the gAMA chunk; still, this is better than not having it at all
	if ([self hdrOutput])  png_set_gAMA(pngPtr, infoPtr, 1.0f);

	// write the image
	png_write_info(pngPtr, infoPtr);
	png_set_packing(pngPtr);

	rowPointers = (png_bytep*) malloc(sizeof(png_bytep)*surf->h);
	for (i = 0; i < surf->h; i++)
	{
		rowPointers[i] = (png_bytep)(Uint8 *)surf->pixels + i*surf->pitch;
	}
	png_write_image(pngPtr, rowPointers);
	png_write_end(pngPtr, infoPtr);

	free(rowPointers);
	png_destroy_write_struct(&pngPtr, &infoPtr);
	fclose(fp);

	return YES;
}
#endif	// SNAPSHOTS_PNG_FORMAT


/*     Turn the Cocoa ArrowKeys into our arrow key constants. */
- (int) translateKeyCode: (int) input
{
	int key = input;
	switch ( input )
	{
		case NSUpArrowFunctionKey:
			key = gvArrowKeyUp;
			break;

		case NSDownArrowFunctionKey:
			key = gvArrowKeyDown;
			break;

		case NSLeftArrowFunctionKey:
			key = gvArrowKeyLeft;
			break;

		case NSRightArrowFunctionKey:
			key = gvArrowKeyRight;
			break;

		case NSF1FunctionKey:
			key = gvFunctionKey1;
			break;

		case NSF2FunctionKey:
			key = gvFunctionKey2;
			break;

		case NSF3FunctionKey:
			key = gvFunctionKey3;
			break;

		case NSF4FunctionKey:
			key = gvFunctionKey4;
			break;

		case NSF5FunctionKey:
			key = gvFunctionKey5;
			break;

		case NSF6FunctionKey:
			key = gvFunctionKey6;
			break;

		case NSF7FunctionKey:
			key = gvFunctionKey7;
			break;

		case NSF8FunctionKey:
			key = gvFunctionKey8;
			break;

		case NSF9FunctionKey:
			key = gvFunctionKey9;
			break;

		case NSF10FunctionKey:
			key = gvFunctionKey10;
			break;

		case NSF11FunctionKey:
			key = gvFunctionKey11;
			break;

		case NSHomeFunctionKey:
			key = gvHomeKey;
			break;

		default:
			break;
	}
	return key;
}


- (void) setVirtualJoystick:(double) vmx :(double) vmy
{
	virtualJoystickPosition.x = vmx;
	virtualJoystickPosition.y = vmy;
}


- (NSPoint) virtualJoystickPosition
{
	return virtualJoystickPosition;
}


/////////////////////////////////////////////////////////////

- (void) clearKeys
{
	int i;
	lastKeyShifted = NO;
	for (i = 0; i < [self numKeys]; i++)
		keys[i] = NO;
}


- (void) clearMouse
{
	keys[gvMouseDoubleClick] = NO;
	keys[gvMouseLeftButton] = NO;
	doubleClick = NO;
}


- (void) clearKey: (int)theKey
{
	if (theKey >= 0 && theKey < [self numKeys])
	{
		keys[theKey] = NO;
	}
}


- (void) resetMouse
{
	[self setVirtualJoystick:0.0 :0.0];
	if ([[PlayerEntity sharedPlayer] isMouseControlOn])
	{
		SDL_WarpMouse([self viewSize].width / 2, [self viewSize].height / 2);
		mouseWarped = YES;
	}
}


- (BOOL) isAlphabetKeyDown
{
	return isAlphabetKeyDown = NO;;
}

// DJS: When entering submenus in the gui, it is not helpful if the
// key down that brought you into the submenu is still registered
// as down when we're in. This makes isDown return NO until a key up
// event has been received from SDL.
- (void) suppressKeysUntilKeyUp
{
	if (keys[gvMouseDoubleClick] == NO)
   	{
   		suppressKeys = YES;
   		[self clearKeys];
   	}
   	else
   	{
   		[self clearMouse];
   	}

}


- (BOOL) isDown: (int) key
{
	if ( suppressKeys )
		return NO;
	if ( key < 0 )
		return NO;
	if ( key >= [self numKeys] )
		return NO;
	return keys[key];
}


- (BOOL) isOptDown
{
	return opt;
}


- (BOOL) isCtrlDown
{
	return ctrl;
}


- (BOOL) isCommandDown
{
	return command;
}


- (BOOL) isShiftDown
{
	return shift;
}


- (BOOL) isCapsLockOn
{
	/* Caps Lock state check - This effectively gives us
	   an alternate keyboard state to play with and, in
	   the future, we could assign different behaviours
	   to existing controls, depending on the state of
	   Caps Lock. - Nikos 20160304
	*/
	return (SDL_GetModState() & KMOD_CAPS) == KMOD_CAPS;
}


- (BOOL) lastKeyWasShifted
{
	return lastKeyShifted;
}

- (int) numKeys
{
	return NUM_KEYS;
}


- (int) mouseWheelState
{
	if (_mouseWheelDelta > 0.0f)
		return gvMouseWheelUp;
	else if (_mouseWheelDelta < 0.0f)
		return gvMouseWheelDown;
	else
		return gvMouseWheelNeutral;
}


- (float) mouseWheelDelta
{
	return _mouseWheelDelta / OOMOUSEWHEEL_DELTA;
}


- (void) setMouseWheelDelta: (float) newWheelDelta
{
	_mouseWheelDelta = newWheelDelta * OOMOUSEWHEEL_DELTA;
}


- (BOOL) isCommandQDown
{
	return NO;
}


- (BOOL) isCommandFDown
{
	return NO;
}


- (void) clearCommandF
{
	// SDL stub for the mac function.
}


- (void)pollControls
{
	SDL_Event				event;
	SDL_KeyboardEvent		*kbd_event;
	SDL_MouseButtonEvent	*mbtn_event;
	SDL_MouseMotionEvent	*mmove_event;
	int						mxdelta, mydelta;
	float					mouseVirtualStickSensitivityX = viewSize.width * MOUSEVIRTUALSTICKSENSITIVITYFACTOR;
	float					mouseVirtualStickSensitivityY = viewSize.height * MOUSEVIRTUALSTICKSENSITIVITYFACTOR;
	NSTimeInterval			timeNow = [NSDate timeIntervalSinceReferenceDate];
	Uint16 					key_id;
	int						scan_code;

	while (SDL_PollEvent(&event))
	{
		switch (event.type) {
			case SDL_JOYAXISMOTION:
			case SDL_JOYBUTTONUP:
			case SDL_JOYBUTTONDOWN:
			case SDL_JOYHATMOTION:
				[(OOSDLJoystickManager*)[OOJoystickManager sharedStickHandler] handleSDLEvent: &event];
				break;

			case SDL_MOUSEBUTTONDOWN:
				mbtn_event = (SDL_MouseButtonEvent*)&event;
#if OOLITE_LINUX
				short inDelta = 0;
#else
				// specially built SDL.dll is required for this
				short inDelta = mbtn_event->wheelDelta;
#endif
				switch(mbtn_event->button)
				{
					case SDL_BUTTON_LEFT:
						keys[gvMouseLeftButton] = YES;
						break;
					case SDL_BUTTON_RIGHT:
						// Cocoa version does this in the GameController
						/*
						 The mouseWarped variable is quite important as far as mouse control is concerned. When we
						 reset the virtual joystick (mouse) coordinates, we need to send a WarpMouse call because we
						 must recenter the pointer physically on screen. This goes together with a mouse motion event,
						 so we use mouseWarped to simply ignore handling of motion events in this case. - Nikos 20110721
						*/
						[self resetMouse]; // Will set mouseWarped to YES
						break;
					// mousewheel stuff
#if OOLITE_LINUX
					case SDL_BUTTON_WHEELUP:
						inDelta = OOMOUSEWHEEL_DELTA;
						// allow fallthrough
					case SDL_BUTTON_WHEELDOWN:
						if (inDelta == 0)  inDelta = -OOMOUSEWHEEL_DELTA;
#else
					case SDL_BUTTON_WHEELUP:
					case SDL_BUTTON_WHEELDOWN:
#endif
						if (inDelta > 0)
						{
							if (_mouseWheelDelta >= 0.0f)
								_mouseWheelDelta += inDelta;
							else
								_mouseWheelDelta = 0.0f;
						}
						else if (inDelta < 0)
						{
							if (_mouseWheelDelta <= 0.0f)
								_mouseWheelDelta += inDelta;
							else
								_mouseWheelDelta = 0.0f;
						}
						break;
				}
				break;

			case SDL_MOUSEBUTTONUP:
				mbtn_event = (SDL_MouseButtonEvent*)&event;
				NSTimeInterval timeBetweenClicks = timeNow - timeIntervalAtLastClick;
				timeIntervalAtLastClick += timeBetweenClicks;
				if (mbtn_event->button == SDL_BUTTON_LEFT)
				{
					if (!doubleClick)
					{
						doubleClick = (timeBetweenClicks < MOUSE_DOUBLE_CLICK_INTERVAL);	// One fifth of a second
						keys[gvMouseDoubleClick] = doubleClick;
					}
					keys[gvMouseLeftButton] = NO;
				}
				/* 
				   Mousewheel handling - just note time since last use here and mark as inactive,
				   if needed, at the end of this method. Note that the mousewheel button up event is 
				   kind of special, as in, it is sent at the same time as its corresponding mousewheel
				   button down one - Nikos 20140809
				*/
				if (mbtn_event->button == SDL_BUTTON_WHEELUP || mbtn_event->button == SDL_BUTTON_WHEELDOWN)
				{
					NSTimeInterval timeBetweenMouseWheels = timeNow - timeSinceLastMouseWheel;
					timeSinceLastMouseWheel += timeBetweenMouseWheels;
				}
				break;

			case SDL_MOUSEMOTION:
			{
				// Delta mode is set when the game is in 'flight' mode.
				// In this mode, the mouse movement delta is used rather
				// than absolute position. This is because if the user
				// clicks the right button to recentre the virtual joystick,
				// if we are using absolute joystick positioning, as soon
				// as the player touches the mouse again, the virtual joystick
				// will snap back to the absolute position (which can be
				// annoyingly fatal in battle).
				if(mouseInDeltaMode)
				{
					// possible TODO - make virtual stick sensitivity configurable
					SDL_GetRelativeMouseState(&mxdelta, &mydelta);
					double mxd=(double)mxdelta / mouseVirtualStickSensitivityX;
					double myd=(double)mydelta / mouseVirtualStickSensitivityY;

					if (!mouseWarped) // Standard event, update coordinates
					{
						virtualJoystickPosition.x += mxd;
						virtualJoystickPosition.y += myd;

						// if we excceed the limits, revert changes
						if(fabs(virtualJoystickPosition.x) > MOUSEX_MAXIMUM)
						{
							virtualJoystickPosition.x -= mxd;
						}
						if(fabs(virtualJoystickPosition.y) > MOUSEY_MAXIMUM)
						{
							virtualJoystickPosition.y -= myd;
						}
					}
					else
					{
						// Motion event generated by WarpMouse is ignored and
						// we reset mouseWarped for the next time.
						mouseWarped = NO;
					}
				}
				else
				{
					// Windowed mode. Use the absolute position so the
					// Oolite mouse pointer appears under the X Window System
					// mouse pointer.
					mmove_event = (SDL_MouseMotionEvent*)&event;

					int w=bounds.size.width;
					int h=bounds.size.height;

					if (!mouseWarped) // standard event, handle it
					{
						double mx = mmove_event->x - w/2.0;
						double my = mmove_event->y - h/2.0;
						if (display_z > 640.0)
						{
							mx /= w * MAIN_GUI_PIXEL_WIDTH / display_z;
							my /= h;
						}
						else
						{
							mx /= MAIN_GUI_PIXEL_WIDTH * w / 640.0;
							my /= MAIN_GUI_PIXEL_HEIGHT * w / 640.0;
						}

						[self setVirtualJoystick:mx :my];
					}
					else
					{
						// event coming from WarpMouse ignored, get ready for the next
						mouseWarped = NO;
					}
				}
				break;
			}
			case SDL_KEYDOWN:
				kbd_event = (SDL_KeyboardEvent*)&event;
				key_id = (Uint16)kbd_event->keysym.unicode;
				scan_code = kbd_event->keysym.scancode;

				//char *keychar = SDL_GetKeyName(kbd_event->keysym.sym);
				// deal with modifiers first
				BOOL modifier_pressed = NO;
				BOOL special_key = NO;

				// translate scancode to unicode equiv
				switch (kbd_event->keysym.sym) 
				{
					case SDLK_LSHIFT:
					case SDLK_RSHIFT:
						shift = YES;
						modifier_pressed = YES;
						break;

					case SDLK_LCTRL:
					case SDLK_RCTRL:
						ctrl = YES;
						modifier_pressed = YES;
						break;
						
					case SDLK_LALT:
					case SDLK_RALT:
						opt = YES;
						modifier_pressed = YES;
						break;

					case SDLK_KP0: key_id = (!allowingStringInput ? gvNumberPadKey0 : gvNumberKey0); special_key = YES; break;
					case SDLK_KP1: key_id = (!allowingStringInput ? gvNumberPadKey1 : gvNumberKey1); special_key = YES; break;
					case SDLK_KP2: key_id = (!allowingStringInput ? gvNumberPadKey2 : gvNumberKey2); special_key = YES; break;
					case SDLK_KP3: key_id = (!allowingStringInput ? gvNumberPadKey3 : gvNumberKey3); special_key = YES; break;
					case SDLK_KP4: key_id = (!allowingStringInput ? gvNumberPadKey4 : gvNumberKey4); special_key = YES; break;
					case SDLK_KP5: key_id = (!allowingStringInput ? gvNumberPadKey5 : gvNumberKey5); special_key = YES; break;
					case SDLK_KP6: key_id = (!allowingStringInput ? gvNumberPadKey6 : gvNumberKey6); special_key = YES; break;
					case SDLK_KP7: key_id = (!allowingStringInput ? gvNumberPadKey7 : gvNumberKey7); special_key = YES; break;
					case SDLK_KP8: key_id = (!allowingStringInput ? gvNumberPadKey8 : gvNumberKey8); special_key = YES; break;
					case SDLK_KP9: key_id = (!allowingStringInput ? gvNumberPadKey9 : gvNumberKey9); special_key = YES; break;
					case SDLK_KP_PERIOD: key_id = (!allowingStringInput ? gvNumberPadKeyPeriod : 46); special_key = YES; break;
					case SDLK_KP_DIVIDE: key_id = (!allowingStringInput ? gvNumberPadKeyDivide : 47); special_key = YES; break;
					case SDLK_KP_MULTIPLY: key_id = (!allowingStringInput ? gvNumberPadKeyMultiply : 42); special_key = YES; break;
					case SDLK_KP_MINUS: key_id = (!allowingStringInput ? gvNumberPadKeyMinus : 45); special_key = YES; break;
					case SDLK_KP_PLUS: key_id = (!allowingStringInput ? gvNumberPadKeyPlus : 43); special_key = YES; break;
					case SDLK_KP_EQUALS: key_id = (!allowingStringInput ? gvNumberPadKeyEquals : 61); special_key = YES; break;
					case SDLK_KP_ENTER: key_id = gvNumberPadKeyEnter; special_key = YES; break;
					case SDLK_HOME: key_id = gvHomeKey; special_key = YES; break;
					case SDLK_END: key_id = gvEndKey; special_key = YES; break;
					case SDLK_INSERT: key_id = gvInsertKey; special_key = YES; break;
					case SDLK_PAGEUP: key_id = gvPageUpKey; special_key = YES; break;
					case SDLK_PAGEDOWN: key_id = gvPageDownKey; special_key = YES; break;
					case SDLK_SPACE: key_id = 32; special_key = YES; break;
					case SDLK_RETURN: key_id = 13; special_key = YES; break;
					case SDLK_TAB: key_id = 9; special_key = YES; break;
					case SDLK_UP: key_id = gvArrowKeyUp; special_key = YES; break;
					case SDLK_DOWN: key_id = gvArrowKeyDown; special_key = YES; break;
					case SDLK_LEFT: key_id = gvArrowKeyLeft; special_key = YES; break;
					case SDLK_RIGHT: key_id = gvArrowKeyRight; special_key = YES; break;
					case SDLK_PAUSE: key_id = gvPauseKey; special_key = YES; break;
					case SDLK_BACKSPACE: key_id = gvBackspaceKey; special_key = YES; break;
					case SDLK_DELETE: key_id = gvDeleteKey; special_key = YES; break;
					case SDLK_F1: key_id = gvFunctionKey1; special_key = YES; break;
					case SDLK_F2: key_id = gvFunctionKey2; special_key = YES; break;
					case SDLK_F3: key_id = gvFunctionKey3; special_key = YES; break;
					case SDLK_F4: key_id = gvFunctionKey4; special_key = YES; break;
					case SDLK_F5: key_id = gvFunctionKey5; special_key = YES; break;
					case SDLK_F6: key_id = gvFunctionKey6; special_key = YES; break;
					case SDLK_F7: key_id = gvFunctionKey7; special_key = YES; break;
					case SDLK_F8: key_id = gvFunctionKey8; special_key = YES; break;
					case SDLK_F9: key_id = gvFunctionKey9; special_key = YES; break;
					case SDLK_F10: key_id = gvFunctionKey10; special_key = YES; break;
					case SDLK_F11: key_id = gvFunctionKey11; special_key = YES; break;
					case SDLK_F12:
						key_id = 327;
						[self toggleScreenMode];
						special_key = YES; 
						break;

					case SDLK_ESCAPE:
						if (shift)
						{
							SDL_FreeSurface(surface);
							[gameController exitAppWithContext:@"Shift-escape pressed"];
						}
						else
							key_id = 27;
							special_key = YES; 
						break;
					default:
						//OOLog(@"keys.test", @"Unhandled Keydown scancode with unicode = 0: %d", scan_code);
						;
				}

				// the keyup event doesn't give us the unicode value, so store it here so it can be retrieved on keyup
				// the ctrl key tends to mix up the unicode values, so deal with some special cases
				// we also need (in most cases) to get the character without the impact of caps lock. 
				if (((!special_key && (ctrl || key_id == 0)) || ([self isCapsLockOn] && (!special_key && !allowingStringInput))) && !modifier_pressed) //  
				{
					// ctrl changes alpha characters to control codes (1-26)
					if (ctrl && key_id >=1 && key_id <= 26) 
					{
						if (shift) 
							key_id += 64; // A-Z is from 65, offset by -1 for the scancode start point
						else
							key_id += 96; // a-z is from 97, offset by -1 for the scancode start point
					} 
					else 
					{
						key_id = 0; // reset the value here to force a lookup from the keymappings data
					}
				}

				// if we get here and we still don't have a key id, grab the unicode value from our keymappings dict
				if (key_id == 0) 
				{
					// get unicode value for keycode from keymappings files
					// this handles all the non-functional keys. the function keys are handled in the switch above
					if (!shift)
					{
						NSString *keyNormal = [keyMappings_normal objectForKey:[NSString stringWithFormat:@"%d", scan_code]];
						if (keyNormal) key_id = [keyNormal integerValue];
					}
					else
					{
						NSString *keyShifted = [keyMappings_shifted objectForKey:[NSString stringWithFormat:@"%d", scan_code]];
						if (keyShifted) key_id = [keyShifted integerValue];
					}
				}

				// if we've got the unicode value, we can store it in our array now
				if (key_id > 0) scancode2Unicode[scan_code] = key_id;

				if(allowingStringInput)
				{
					[self handleStringInput:kbd_event keyID:key_id];
				}

				OOLog(kOOLogKeyDown, @"Keydown scancode = %d, unicode = %i, sym = %i, character = %c, shift = %d, ctrl = %d, alt = %d", scan_code, key_id, kbd_event->keysym.sym, key_id, shift, ctrl, opt);
				//OOLog(kOOLogKeyDown, @"Keydown scancode = %d, unicode = %i", kbd_event->keysym.scancode, key_id);

				if (key_id > 0 && key_id <= [self numKeys]) 
				{
					keys[key_id] = YES;
				}
				else 
				{
					//OOLog(@"keys.test", @"Unhandled Keydown scancode/unicode: %d %i", scan_code, key_id);
				}
				break;

			case SDL_KEYUP:
				suppressKeys = NO;    // DJS
				kbd_event = (SDL_KeyboardEvent*)&event;
				scan_code = kbd_event->keysym.scancode;

				// all the work should have been down on the keydown event, so all we need to do is get the unicode value from the array
				key_id = scancode2Unicode[scan_code];

				// deal with modifiers first
				switch (kbd_event->keysym.sym)
				{
					case SDLK_LSHIFT:
					case SDLK_RSHIFT:
						shift = NO;
						break;

					case SDLK_LCTRL:
					case SDLK_RCTRL:
						ctrl = NO;
						break;
						
					case SDLK_LALT:
					case SDLK_RALT:
						opt = NO;
						break;
					default:
						;
				}
				OOLog(kOOLogKeyUp, @"Keyup scancode = %d, unicode = %i, sym = %i, character = %c, shift = %d, ctrl = %d, alt = %d", scan_code, key_id, kbd_event->keysym.sym, key_id, shift, ctrl, opt);
				//OOLog(kOOLogKeyUp, @"Keyup scancode = %d, shift = %d, ctrl = %d, alt = %d", scan_code, shift, ctrl, opt);
				
				// translate scancode to unicode equiv
				switch (kbd_event->keysym.sym) 
				{
					case SDLK_KP0: key_id = (!allowingStringInput ? gvNumberPadKey0 : gvNumberKey0); break;
					case SDLK_KP1: key_id = (!allowingStringInput ? gvNumberPadKey1 : gvNumberKey1); break;
					case SDLK_KP2: key_id = (!allowingStringInput ? gvNumberPadKey2 : gvNumberKey2); break;
					case SDLK_KP3: key_id = (!allowingStringInput ? gvNumberPadKey3 : gvNumberKey3); break;
					case SDLK_KP4: key_id = (!allowingStringInput ? gvNumberPadKey4 : gvNumberKey4); break;
					case SDLK_KP5: key_id = (!allowingStringInput ? gvNumberPadKey5 : gvNumberKey5); break;
					case SDLK_KP6: key_id = (!allowingStringInput ? gvNumberPadKey6 : gvNumberKey6); break;
					case SDLK_KP7: key_id = (!allowingStringInput ? gvNumberPadKey7 : gvNumberKey7); break;
					case SDLK_KP8: key_id = (!allowingStringInput ? gvNumberPadKey8 : gvNumberKey8); break;
					case SDLK_KP9: key_id = (!allowingStringInput ? gvNumberPadKey9 : gvNumberKey9); break;
					case SDLK_KP_PERIOD: key_id = (!allowingStringInput ? gvNumberPadKeyPeriod : 46); break;
					case SDLK_KP_DIVIDE: key_id = (!allowingStringInput ? gvNumberPadKeyDivide : 47); break;
					case SDLK_KP_MULTIPLY: key_id = (!allowingStringInput ? gvNumberPadKeyMultiply : 42); break;
					case SDLK_KP_MINUS: key_id = (!allowingStringInput ? gvNumberPadKeyMinus : 45); break;
					case SDLK_KP_PLUS: key_id = (!allowingStringInput ? gvNumberPadKeyPlus : 43); break;
					case SDLK_KP_EQUALS: key_id = (!allowingStringInput ? gvNumberPadKeyEquals : 61); break;
					case SDLK_KP_ENTER: key_id = gvNumberPadKeyEnter; break;
					case SDLK_HOME: key_id = gvHomeKey; break;
					case SDLK_END: key_id = gvEndKey; break;
					case SDLK_INSERT: key_id = gvInsertKey; break;
					case SDLK_PAGEUP: key_id = gvPageUpKey; break;
					case SDLK_PAGEDOWN: key_id = gvPageDownKey; break;
					case SDLK_SPACE: key_id = 32; break;
					case SDLK_RETURN: key_id = 13; break;
					case SDLK_TAB: key_id = 9; break;
					case SDLK_ESCAPE: key_id = 27; break;
					case SDLK_UP: key_id = gvArrowKeyUp; break;
					case SDLK_DOWN: key_id = gvArrowKeyDown; break;
					case SDLK_LEFT: key_id = gvArrowKeyLeft; break;
					case SDLK_RIGHT: key_id = gvArrowKeyRight; break;
					case SDLK_PAUSE: key_id = gvPauseKey; break;
					case SDLK_F1: key_id = gvFunctionKey1; break;
					case SDLK_F2: key_id = gvFunctionKey2; break;
					case SDLK_F3: key_id = gvFunctionKey3; break;
					case SDLK_F4: key_id = gvFunctionKey4; break;
					case SDLK_F5: key_id = gvFunctionKey5; break;
					case SDLK_F6: key_id = gvFunctionKey6; break;
					case SDLK_F7: key_id = gvFunctionKey7; break;
					case SDLK_F8: key_id = gvFunctionKey8; break;
					case SDLK_F9: key_id = gvFunctionKey9; break;
					case SDLK_F10: key_id = gvFunctionKey10; break;
					case SDLK_F11: key_id = gvFunctionKey11; break;
					case SDLK_F12: key_id = 327; break;
					case SDLK_BACKSPACE: key_id = gvBackspaceKey; break;
					case SDLK_DELETE: key_id = gvDeleteKey; break;

					default:
						//OOLog(@"keys.test", @"Unhandled Keyup scancode with unicode = 0: %d", kbd_event->keysym.scancode);
						;
				}

				if (key_id > 0 && key_id <= [self numKeys]) 
				{
					keys[key_id] = NO;
				}
				else 
				{
					//OOLog(@"keys.test", @"Unhandled Keyup scancode: %d", kbd_event->keysym.scancode);
				}
				break;

			case SDL_VIDEORESIZE:
			{
				SDL_ResizeEvent *rsevt=(SDL_ResizeEvent *)&event;
				NSSize newSize=NSMakeSize(rsevt->w, rsevt->h);
#if OOLITE_WINDOWS
				if (!fullScreen && updateContext)
				{
					if (saveSize == NO)
					{
						// event triggered by caption & frame
						// next event will be a real resize.
						saveSize = YES;
					}
					else
					{
						[self initialiseGLWithSize: newSize];
						[self saveWindowSize: newSize];
					}
				}
#else
				[self initialiseGLWithSize: newSize];
				[self saveWindowSize: newSize];
#endif
				// certain gui screens will require an immediate redraw after
				// a resize event - Nikos 20140129
				if ([PlayerEntity sharedPlayer])
				{
					[[PlayerEntity sharedPlayer] doGuiScreenResizeUpdates];
				}
				break;
			}
			
#if OOLITE_WINDOWS
			// if we minimize the window while in fullscreen (e.g. via
			// Win+M or Win+DownArrow), restore the non-borderless window
			// style before minimuzing and reset it when we return, otherwise
			// there might be issues with the game window remaining stuck on
			// top in some cases (seen with some Intel gfx chips).
			// N.B. active event gain of zero means app is iconified
			case SDL_ACTIVEEVENT:
			{			
				if ((event.active.state & SDL_APPACTIVE) && fullScreen)
				{
					[self setWindowBorderless:event.active.gain];
				}
				break;
			}
			
			// need to track this because the user may move the game window
			// to a secondary monitor, in which case we must potentially
			// refresh the information displayed (e.g. Game Options screen)
			// Nikos - 20140920
			case SDL_SYSWMEVENT:
			{
				DWORD dwLastError = 0;
				switch (event.syswm.msg->msg)
				{
					case WM_WINDOWPOSCHANGING:
						/* if we are in fullscreen mode we normally don't worry about having the window moved.
						   However, when using multiple monitors, one can use hotkey combinations to make the
						   window "jump" from one monitor to the next. We don't want this to happen, so if we
						   detect that our (fullscreen) window has moved, we immediately bring it back to its
						   original position. Nikos - 20140922
						*/
						if (fullScreen)
						{
							RECT rDC;
							
							/* attempting to move our fullscreen window while in maximized state can freak
							   Windows out and the window may not return to its original position properly.
							   Solution: if such a move takes place, first change the window placement to
							   normal, move it normally, then restore its placement to maximized again. 
							   Additionally, the last good known window position seems to be lost in such
							   a case. While at it, update also the coordinates of the non-maximized window
							   so that it can return to its original position - this is why we need lastGoodRect.
							 */
							WINDOWPLACEMENT wp;
							wp.length = sizeof(WINDOWPLACEMENT);
							GetWindowPlacement(SDL_Window, &wp);
							
							GetWindowRect(SDL_Window, &rDC);
							if (rDC.left != monitorInfo.rcMonitor.left || rDC.top != monitorInfo.rcMonitor.top)
							{
								BOOL fullScreenMaximized = NO;
								if (wp.showCmd == SW_SHOWMAXIMIZED && !fullScreenMaximized)
								{
									fullScreenMaximized = YES;
									wp.showCmd = SW_SHOWNORMAL;
									SetWindowPlacement(SDL_Window, &wp);
								}
			
								if (wp.showCmd != SW_SHOWMINIMIZED && wp.showCmd != SW_MINIMIZE)
								{
									MoveWindow(SDL_Window, monitorInfo.rcMonitor.left, monitorInfo.rcMonitor.top,
													(int)viewSize.width, (int)viewSize.height, TRUE);
								}
								
								if (fullScreenMaximized)
								{
									GetWindowPlacement(SDL_Window, &wp);
									wp.showCmd = SW_SHOWMAXIMIZED;
									CopyRect(&wp.rcNormalPosition, &lastGoodRect);
									SetWindowPlacement(SDL_Window, &wp);
								}
							}
							else if (wp.showCmd == SW_SHOWMAXIMIZED)
							{
									CopyRect(&wp.rcNormalPosition, &lastGoodRect);
									SetWindowPlacement(SDL_Window, &wp);
							}
						}
						// it is important that this gets done after we've dealt with possible fullscreen movements,
						// because -doGuiScreenResizeUpdates does itself an update on current monitor
						if ([PlayerEntity sharedPlayer])
						{
							[[PlayerEntity sharedPlayer] doGuiScreenResizeUpdates];
						}
						/*
						 deliberately no break statement here - moving or resizing the window changes its bounds
						 rectangle. Therefore we must check whether to clip the mouse or not inside the newly
						 updated rectangle, so just let it fall through
						*/
						
					case WM_ACTIVATEAPP:
						if(grabMouseStatus)  [self grabMouseInsideGameWindow:YES];
						break;
						
					case WM_SETTINGCHANGE:
						// TODO: we really should be checking the status of event.syswm.msg->lParam here and run our
						// dark / light mode refresh check only if the lParam LPCTSTR matches "ImmersiveColorSet".
						// However, for some reason I cannot get an actual string on lParam. This means that the
						// mode refresh check runs every time something changes the Windows Registry while the game
						// is running. Still, should be OK because our refreshDarKOrLightMode will be transparent in
						// such cases, plus we would not practically expect too many events doing things to the Registry
						// while we are running. If in the future we need to respond to a different event which changes 
						// system settings in real time, then yes, we will have to find a way to decode lParam properly.
						// Nikos, 20230805
						[self refreshDarKOrLightMode];
						break;
						
					case WM_SETFOCUS:
						/*
	`					make sure that all modifier keys like Shift, Alt, Ctrl and Caps Lock
	`					are set correctly to what they should be when we get focus. We have
	`					to do it ourselves because SDL on Windows has problems with this
	`					when focus change events occur, like e.g. Alt-Tab in/out of the
						application
	`					*/
						[self resetSDLKeyModifiers];
						if (!SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL))
						{
							dwLastError = GetLastError();
							OOLog(@"wm_setfocus.message", @"Setting thread priority to time critical failed! (error code: %d)", dwLastError);
						}
						break;
						
					case WM_KILLFOCUS:
						if (!SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_NORMAL))
						{
							dwLastError = GetLastError();
							OOLog(@"wm_killfocus.message", @"Setting thread priority to normal failed! (error code: %d)", dwLastError);
						}
						break;
						
					default:
						;
				}
				break;
			}
#endif

			// caused by INTR or someone hitting close
			case SDL_QUIT:
			{
				SDL_FreeSurface(surface);
				[gameController exitAppWithContext:@"SDL_QUIT event received"];
			}
		}
	}
	// check if enough time has passed since last use of the mousewheel and act
	// if needed
	if (timeNow >= timeSinceLastMouseWheel + OOMOUSEWHEEL_EVENTS_DELAY_INTERVAL)
	{
		_mouseWheelDelta = 0.0f;
	}
}


// DJS: String input handler. Since for SDL versions we're also handling
// freeform typing this has necessarily got more complex than the non-SDL
// versions.
- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event keyID:(Uint16)key_id;
{
	SDLKey key=kbd_event->keysym.sym;

	// Del, Backspace
	if((key == SDLK_BACKSPACE || key == SDLK_DELETE) && [typedString length] > 0)
	{
		// delete
		[typedString deleteCharactersInRange:NSMakeRange([typedString length]-1, 1)];
	}

	isAlphabetKeyDown=NO;

	// TODO: a more flexible mechanism  for max. string length ?
	if([typedString length] < 40)
	{
		lastKeyShifted = shift;
		if (allowingStringInput == gvStringInputAlpha)
		{
			// inputAlpha - limited input for planet find screen
			if(key >= SDLK_a && key <= SDLK_z)
			{
				isAlphabetKeyDown=YES;
				[typedString appendFormat:@"%c", key];
				// if in inputAlpha, keep in lower case.
			}
		}
		else
		{
			//Uint16 unicode = kbd_event->keysym.unicode;
			// printable range
			if (key_id >= 32 && key_id <= 255) // 126
			{
				if ((char)key_id != '/' || allowingStringInput == gvStringInputAll)
				{
					isAlphabetKeyDown=YES;
					[typedString appendFormat:@"%c", key_id];
				}
			}
		}
	}
}


// Full screen mode enumerator.
- (void) populateFullScreenModelist
{
	int i;
	SDL_Rect **modes;
	NSMutableDictionary *mode;

	screenSizes=[[NSMutableArray alloc] init];

	// The default resolution (slot 0) is the resolution we are
	// already in since this is guaranteed to work.
	mode=[MyOpenGLView getNativeSize];
	[screenSizes addObject: mode];

	modes=SDL_ListModes(NULL, SDL_FULLSCREEN|SDL_HWSURFACE);
	if(modes == (SDL_Rect **)NULL)
	{
		OOLog(@"display.mode.list.none", @"%@", @"SDL didn't return any screen modes");
		return;
	}

	if(modes == (SDL_Rect **)-1)
	{
		OOLog(@"display.mode.list.none", @"%@", @"SDL claims 'all resolutions available' which is unhelpful in the extreme");
		return;
	}

	int lastw=[[mode objectForKey: kOODisplayWidth] intValue];
	int lasth=[[mode objectForKey: kOODisplayHeight] intValue];
	for(i=0; modes[i]; i++)
	{
		// SDL_ListModes often lists a mode several times,
		// presumably because each mode has several refresh rates.
		// But the modes pointer is an SDL_Rect which can't represent
		// refresh rates. WHY!?
		if(modes[i]->w != lastw || modes[i]->h != lasth)
		{
			// new resolution, save it
			mode=[NSMutableDictionary dictionary];
			[mode setValue: [NSNumber numberWithInt: (int)modes[i]->w]
					forKey: kOODisplayWidth];
			[mode setValue: [NSNumber numberWithInt: (int)modes[i]->h]
					forKey: kOODisplayHeight];
			[mode setValue: [NSNumber numberWithInt: 0]
					forKey: kOODisplayRefreshRate];
			if (![screenSizes containsObject:mode])
			{
				[screenSizes addObject: mode];
				OOLog(@"display.mode.list", @"Added res %d x %d", modes[i]->w, modes[i]->h);
				lastw=modes[i]->w;
				lasth=modes[i]->h;
			}
		}
	}
}


// Save and restore window sizes to/from defaults.
- (void) saveWindowSize: (NSSize) windowSize
{
	NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
	[defaults setInteger: (int)windowSize.width forKey: @"window_width"];
	[defaults setInteger: (int)windowSize.height forKey: @"window_height"];
	currentWindowSize=windowSize;
}


- (NSSize) loadWindowSize
{
	NSSize windowSize;
	NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
	if([defaults objectForKey:@"window_width"] && [defaults objectForKey:@"window_height"])
	{
		windowSize=NSMakeSize([defaults integerForKey: @"window_width"],
					[defaults integerForKey: @"window_height"]);
	}
	else
	{
		windowSize=NSMakeSize(1024, 576);
	}
	currentWindowSize=windowSize;
	return windowSize;
}


- (int) loadFullscreenSettings
{
	currentSize=0;
	int width=0, height=0, refresh=0;
	unsigned i;

	NSArray* cmdline_arguments = [[NSProcessInfo processInfo] arguments];

	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	if ([userDefaults objectForKey:@"display_width"])
		width = [userDefaults integerForKey:@"display_width"];
	if ([userDefaults objectForKey:@"display_height"])
		height = [userDefaults integerForKey:@"display_height"];
	if ([userDefaults objectForKey:@"display_refresh"])
		refresh = [userDefaults integerForKey:@"display_refresh"];
	if([userDefaults objectForKey:@"fullscreen"])
		fullScreen=[userDefaults boolForKey:@"fullscreen"];

	// Check if -fullscreen or -windowed has been passed on the command line. If yes,
	// set it regardless of what is set by .GNUstepDefaults. If both are found in the
	// arguments list, the one that comes last wins.
	for (i = 0; i < [cmdline_arguments count]; i++)
	{
		if ([[cmdline_arguments objectAtIndex:i] isEqual:@"-fullscreen"]) fullScreen = YES;
		if ([[cmdline_arguments objectAtIndex:i] isEqual:@"-windowed"]) fullScreen = NO;
	}
	
   	if(width && height)
   	{
      		currentSize=[self findDisplayModeForWidth: width Height: height Refresh: refresh];
      		return currentSize;
   	}
   	return currentSize;
}


- (int) findDisplayModeForWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
	int i, modeCount;
	NSDictionary *mode;
	unsigned int modeWidth, modeHeight, modeRefresh;

	modeCount = [screenSizes count];

	for (i = 0; i < modeCount; i++)
	{
		mode = [screenSizes objectAtIndex: i];
		modeWidth = [[mode objectForKey: kOODisplayWidth] intValue];
		modeHeight = [[mode objectForKey: kOODisplayHeight] intValue];
		modeRefresh = [[mode objectForKey: kOODisplayRefreshRate] intValue];
		if ((modeWidth == d_width)&&(modeHeight == d_height)&&(modeRefresh == d_refresh))
		{
			OOLog(@"display.mode.found", @"Found mode %@", mode);
			return i;
		}
	}

	OOLog(@"display.mode.found.failed", @"Failed to find mode: width=%d height=%d refresh=%d", d_width, d_height, d_refresh);
	OOLog(@"display.mode.found.failed.list", @"Contents of list: %@", screenSizes);
	return 0;
}


- (NSSize) currentScreenSize
{
	NSDictionary *mode=[screenSizes objectAtIndex: currentSize];

	if(mode)
	{
		return NSMakeSize([[mode objectForKey: kOODisplayWidth] intValue],
				[[mode objectForKey: kOODisplayHeight] intValue]);
	}
	OOLog(@"display.mode.unknown", @"%@", @"Screen size unknown!");
	return NSMakeSize(1024, 576);
}


- (void) setMouseInDeltaMode: (BOOL) inDelta
{
	mouseInDeltaMode=inDelta;
}


- (void) setGammaValue: (float) value
{
	if (value < 0.2f)  value = 0.2f;
	if (value > 4.0f)  value = 4.0f;

	_gamma = value;
	SDL_SetGamma(_gamma, _gamma, _gamma);
	
	[[NSUserDefaults standardUserDefaults] setFloat:_gamma forKey:@"gamma-value"];
}


- (float) gammaValue
{
	return _gamma;
}


- (void) setFov:(float)value fromFraction:(BOOL)fromFraction
{
	_fov = fromFraction ? value : tan((value / 2) * M_PI / 180);
}


- (float) fov:(BOOL)inFraction
{
	return inFraction ? _fov : 2 * atan(_fov) * 180 / M_PI;
}


- (BOOL) msaa
{
	return _msaa;
}


- (void) setMsaa:(BOOL)newMsaa
{
	_msaa = !!newMsaa;
}


- (OOOpenGLMatrixManager *) getOpenGLMatrixManager
{
	return matrixManager;
}


+ (BOOL)pollShiftKey
{
	return 0 != (SDL_GetModState() & (KMOD_LSHIFT | KMOD_RSHIFT));
}


#ifndef NDEBUG
- (void) dumpRGBAToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 4)  return;

	// use the snapshots directory
	NSString *dumpFile = [[NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR] stringByAppendingPathComponent:@SNAPSHOTDIR];
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.bmp", name]];

	// convert transparency to black before saving to bmp
	SDL_Surface* tmpSurface = SDL_CreateRGBSurfaceFrom(bytes, width, height, 32, rowBytes, 0xFF, 0xFF00, 0xFF0000, 0xFF000000);
	SDL_SaveBMP(tmpSurface, [dumpFile UTF8String]);
	SDL_FreeSurface(tmpSurface);
}


- (void) dumpRGBToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 3)  return;

	// use the snapshots directory
	NSString *dumpFile = [[NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR] stringByAppendingPathComponent:@SNAPSHOTDIR];
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.bmp", name]];

	SDL_Surface* tmpSurface = SDL_CreateRGBSurfaceFrom(bytes, width, height, 24, rowBytes, 0xFF, 0xFF00, 0xFF0000, 0x0);
	SDL_SaveBMP(tmpSurface, [dumpFile UTF8String]);
	SDL_FreeSurface(tmpSurface);
}


- (void) dumpGrayToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width)  return;

	// use the snapshots directory
	NSString *dumpFile = [[NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR] stringByAppendingPathComponent:@SNAPSHOTDIR];
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.bmp", name]];

	SDL_Surface* tmpSurface = SDL_CreateRGBSurfaceFrom(bytes, width, height, 8, rowBytes, 0xFF, 0xFF, 0xFF, 0x0);
	SDL_SaveBMP(tmpSurface, [dumpFile UTF8String]);
	SDL_FreeSurface(tmpSurface);
}


- (void) dumpGrayAlphaToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes
{
	if (name == nil || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 2)  return;

	// use the snapshots directory
	NSString *dumpFile = [[NSHomeDirectory() stringByAppendingPathComponent:@SAVEDIR] stringByAppendingPathComponent:@SNAPSHOTDIR];
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.bmp", name]];

	SDL_Surface* tmpSurface = SDL_CreateRGBSurfaceFrom(bytes, width, height, 16, rowBytes, 0xFF, 0xFF, 0xFF, 0xFF);
	SDL_SaveBMP(tmpSurface, [dumpFile UTF8String]);
	SDL_FreeSurface(tmpSurface);
}


- (void) dumpRGBAToRGBFileNamed:(NSString *)rgbName
			   andGrayFileNamed:(NSString *)grayName
						  bytes:(uint8_t *)bytes
						  width:(NSUInteger)width
						 height:(NSUInteger)height
					   rowBytes:(NSUInteger)rowBytes
{
	if ((rgbName == nil && grayName == nil) || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 4)  return;

	uint8_t				*rgbBytes, *rgbPx, *grayBytes, *grayPx, *srcPx;
	NSUInteger			x, y;
	BOOL				trivalAlpha = YES;

	rgbPx = rgbBytes = malloc(width * height * 3);
	if (rgbBytes == NULL)  return;

	grayPx = grayBytes = malloc(width * height);
	if (grayBytes == NULL)
	{
		free(rgbBytes);
		return;
	}

	for (y = 0; y < height; y++)
	{
		srcPx = bytes + rowBytes * y;

		for (x = 0; x < width; x++)
		{
			*rgbPx++ = *srcPx++;
			*rgbPx++ = *srcPx++;
			*rgbPx++ = *srcPx++;
			trivalAlpha = trivalAlpha && ((*srcPx == 0xFF) || (*srcPx == 0x00));	// Look for any "interesting" pixels in alpha.
			*grayPx++ = *srcPx++;
		}
	}

	[self dumpRGBToFileNamed:rgbName
					   bytes:rgbBytes
					   width:width
					  height:height
					rowBytes:width * 3];
	free(rgbBytes);

	if (!trivalAlpha)
	{
		[self dumpGrayToFileNamed:grayName
							bytes:grayBytes
							width:width
						   height:height
						 rowBytes:width];
	}
	free(grayBytes);
}
#endif

@end
