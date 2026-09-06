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

#include <SDL3/SDL_init.h>
#import "png.h"
#import "MyOpenGLView.h"
#import "MyOpenGLView+Input.h"

#import "GameController.h"
#import "Universe.h"
#import "OOSDLJoystickManager.h"
#import "OOSound.h"
#import "NSFileManagerOOExtensions.h" // to find savedir
#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "PlanetEntity.h"
#import "OOGraphicsResetManager.h"
#import "OOCollectionExtractors.h" // for splash screen settings
#import "OOFullScreenController.h"
#import "ResourceManager.h"
#import "OOConstToString.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#import "stb_image_write.h"

#define kOOLogUnconvertedNSLog @"unclassified.MyOpenGLView"

extern int SaveEXRSnapshot(const char* outfilename, int width, int height, const float* rgb);


#include <ctype.h>

#if OOLITE_WINDOWS
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE	20
#endif
HRESULT WINAPI DwmSetWindowAttribute (HWND hwnd, DWORD dwAttribute, LPCVOID pvAttribute, DWORD cbAttribute);

#define USE_UNDOCUMENTED_DARKMODE_API	1

#if USE_UNDOCUMENTED_DARKMODE_API
#ifndef LOAD_LIBRARY_SEARCH_SYSTEM32
#define LOAD_LIBRARY_SEARCH_SYSTEM32	0x00000800
#endif
typedef DWORD(WINAPI* pfnSetPreferredAppMode)(DWORD appMode);
enum PreferredAppMode
{
    Default,
    AllowDark,
    ForceDark,
    ForceLight,
    Max
};
#endif
#endif //OOLITE_WINDOWS

@interface MyOpenGLView (OOPrivate)

@end

@implementation MyOpenGLView

- (SDL_DisplayID) getDisplayId
{
	SDL_DisplayID displayId = 0;
	if (window)
	{
		displayId  = SDL_GetDisplayForWindow(window);
	}
	else
	{
		int displayCount;
		SDL_DisplayID *displayIds = SDL_GetDisplays(&displayCount);
		if (displayIds)
		{
			displayId = displayIds[0];
		}
		else
		{
			OOLog(@"sdl.display_id", @"Could not get list of displays. Error was: %s", SDL_GetError());
		}
		SDL_free(displayIds);
	}
	return displayId;
}

- (NSMutableDictionary *) getNativeSize
{
	NSMutableDictionary *mode=[[NSMutableDictionary alloc] init];
	int nativeDisplayWidth = 1024;
	int nativeDisplayHeight = 768;

#if OOLITE_LINUX
	SDL_DisplayID displayId = [self getDisplayId];
	SDL_Rect boundsRect;
	if (displayId && SDL_GetDisplayUsableBounds(displayId, &boundsRect))
	{
		nativeDisplayWidth = boundsRect.w;
		nativeDisplayHeight = boundsRect.h;
		OOLog(@"display.mode.list.native", @"Native display resolution detected: %d x %d", nativeDisplayWidth, nativeDisplayHeight);
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

- (NSString*) getWindowCaption
{
	NSString *caption = [NSString stringWithFormat:@"Oolite v%@ by %@ - %@", @OO_VERSION_FULL, @OO_BUILDER, @OO_BUILD_DATE];
	return [[caption retain] autorelease];
}

- (void) createWindowWithSize: (NSSize) size
{
	Uint32          colorkey;
	SDL_Surface     *icon=NULL;
	NSString		*imagesDir;

	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];

	OOLog(@"display.initGL", @"Trying %d-bpcc, 24-bit depth buffer", bitsPerColorComponent);
	if (bitsPerColorComponent > 8)
	{
		SDL_GL_SetAttribute(SDL_GL_FLOATBUFFERS, 1);
		_hdrOutput = YES;
	}
	else
	{
		SDL_GL_SetAttribute(SDL_GL_RED_SIZE, bitsPerColorComponent);
		SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, bitsPerColorComponent);
		SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, bitsPerColorComponent);
		SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, bitsPerColorComponent);
		_hdrOutput = NO;
	}
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	
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

	NSString *windowCaption = [self getWindowCaption];
	Uint32 windowFlags = SDL_WINDOW_OPENGL | SDL_WINDOW_BORDERLESS | SDL_WINDOW_HIGH_PIXEL_DENSITY;

	// Define modern SDL3 properties for window configuration
	SDL_PropertiesID props = SDL_CreateProperties();
	SDL_SetStringProperty(props, SDL_PROP_WINDOW_CREATE_TITLE_STRING, [windowCaption UTF8String]);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, size.width);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, size.height);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, windowFlags);

	// Explicit centering properties setup for SDL3
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_X_NUMBER, SDL_WINDOWPOS_CENTERED);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_Y_NUMBER, SDL_WINDOWPOS_CENTERED);

	window = SDL_CreateWindowWithProperties(props);
	if (!window)
	{
		OOLog(@"display.initGL", @"%@", @"Trying 8-bpcc, 24-bit depth buffer");
		SDL_GL_SetAttribute(SDL_GL_FLOATBUFFERS, 0);
		SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
		SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
		window = SDL_CreateWindowWithProperties(props);
		_hdrOutput = NO;
	}

	if (!window)
	{
		OOLog(@"display.initGL", @"%@", @"Trying 5-bpcc, 16-bit depth buffer");
		SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 5);
		SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 5);
		SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 5);
		SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
		// and if it's this bad, forget even trying to multisample!
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 0);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 0);
		window = SDL_CreateWindowWithProperties(props);
	}

	// Clean up properties block
	SDL_DestroyProperties(props);

	if (!window)
	{
		const char * errStr = SDL_GetError();
		OOLogERR(@"display.mode.error", @"Could not create window: %s", errStr);
		exit(1);
	}
	glContext = SDL_GL_CreateContext(window);
	if (!glContext)
	{
		OOLog(@"sdl.create_context", @"%@", @"Could not create OpenGL context");
		exit(1);
	}
	SDL_Surface *surface = SDL_GetWindowSurface(window);
	if (!SDL_SetSurfaceColorspace(surface, SDL_COLORSPACE_SRGB_LINEAR))
	{
		OOLogWARN(@"sdl.use_edr_surface", @"%@ %s", @"Failed to set SDR linear surface - falling back to SDR. Error was:", SDL_GetError());
		SDL_SetSurfaceColorspace(surface, SDL_COLORSPACE_SRGB);
	}

#if OOLITE_WINDOWS
	//capture the window handle for later
	SDL_PropertiesID windowPropertiesId = SDL_GetWindowProperties(window);
	windowHandle = SDL_GetPointerProperty(windowPropertiesId, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
	if (!windowHandle)
	{
		OOLog(@"sdl.window_handle", @"%@", @"Failed to retrieve window handle");
		exit(1);
	}

	// This must be inited after windowHandle has been set - we need the main window handle in order to get monitor info
	if (![self getCurrentMonitorInfo:&monitorInfo])
	{
		OOLogWARN(@"display.initGL.monitorInfoWarning", @"Could not get current monitor information.");
	}

	atDesktopResolution = YES;

#if USE_UNDOCUMENTED_DARKMODE_API
	// dark mode stuff - this is mainly for the winodw titlebar's context menu
	HMODULE hUxTheme = LoadLibraryExW(L"uxtheme.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
	if (hUxTheme)
	{
		// hack alert! ordinal 135 is undocumented and could change in a future version of Windows
		pfnSetPreferredAppMode SetPreferredAppMode = (pfnSetPreferredAppMode)GetProcAddress(hUxTheme, MAKEINTRESOURCEA(135));
		if (SetPreferredAppMode)  SetPreferredAppMode(AllowDark);
		FreeLibrary(hUxTheme);
	}
	[self refreshDarKOrLightMode];
#endif
#endif //OOLITE_WINDOWS

	imagesDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Images"];
	icon = SDL_LoadBMP([[imagesDir stringByAppendingPathComponent:@"WMicon.bmp"] UTF8String]);

	if (icon != NULL)
	{
		const SDL_PixelFormatDetails *pixelFormat = SDL_GetPixelFormatDetails(icon->format);
		const SDL_Palette *palette = SDL_GetSurfacePalette(icon);
		colorkey = SDL_MapRGB(pixelFormat, palette, 128, 0, 128);
		SDL_SetSurfaceColorKey(icon, YES, colorkey);
		SDL_SetWindowIcon(window, icon);
	}
	SDL_DestroySurface(icon);

	_colorSaturation = 1.0f;

#if OOLITE_WINDOWS
	_hdrMaxBrightness = [prefs oo_floatForKey:@"hdr-max-brightness" defaultValue:1000.0f];
	_hdrPaperWhiteBrightness = [prefs oo_floatForKey:@"hdr-paperwhite-brightness" defaultValue:200.0f];
	_hdrToneMapper = OOHDRToneMapperFromString([prefs oo_stringForKey:@"hdr-tone-mapper" defaultValue:@"OOHDR_TONEMAPPER_ACES_APPROX"]);
#endif

	_sdrToneMapper = OOSDRToneMapperFromString([prefs oo_stringForKey:@"sdr-tone-mapper" defaultValue:@"OOSDR_TONEMAPPER_ACES"]);

	SDL_SetWindowSurfaceVSync(window, vSyncPreference);
	OOLog(@"display.initGL", @"V-Sync %@requested.", vSyncPreference ? @"" : @"not ");

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

	SDL_GL_GetAttribute(SDL_GL_FLOATBUFFERS, &testAttrib);
	OOLog(@"display.initGL", @"Pixel type is float : %d", testAttrib);

#if OOLITE_WINDOWS
  	OOLog(@"display.initGL", @"Pixel format index: %d", GetPixelFormat(GetDC(windowHandle)));
#endif

	// Verify V-sync successfully set - report it if not

	int hasVsync;
	if (vSyncPreference && (!SDL_GetWindowSurfaceVSync(window, &hasVsync) || !hasVsync))
	{
		OOLogWARN(@"display.initGL", @"Could not enable V-Sync. Please check that your graphics driver supports the %@_swap_control extension.",
					OOLITE_WINDOWS ? @"WGL_EXT" : @"[GLX_SGI/GLX_MESA]");
	}
	else
	{
		OOLog(@"display.initGL", @"%@", @"V-Sync set");
	}

	int width, height;
	SDL_GetWindowSizeInPixels(window, &width, &height);
	bounds.size.width = width;
	bounds.size.height = height;

	return;
}

- (id) init
{
	self = [super init];

 	NSString		*cmdLineArgsStr = @"Startup command: ";

	// SDL splash screen  settings

	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	showSplashScreen = [prefs oo_boolForKey:@"splash-screen" defaultValue:YES];
	vSyncPreference = [prefs oo_boolForKey:@"v-sync" defaultValue:YES];
	bitsPerColorComponent = [prefs oo_boolForKey:@"hdr" defaultValue:NO] ? 16 : 8;

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

  		// build the startup command string so that we can log it
		cmdLineArgsStr = [cmdLineArgsStr stringByAppendingFormat:@"%@ ", arg];
	}

 	OOLog(@"process.args", @"%@", cmdLineArgsStr);

#if OOLITE_SPEECH_SYNTH
#if OOLITE_ESPEAK
	if (!SDL_getenv("ESPEAK_DATA_PATH"))
	{
		espeak_Initialize(AUDIO_OUTPUT_PLAYBACK, 100, [[ResourceManager builtInPath] UTF8String], 0);
	}
	else
	{
		espeak_Initialize(AUDIO_OUTPUT_PLAYBACK, 100, NULL, 0);
	}
#endif
#endif

	matrixManager = [[OOOpenGLMatrixManager alloc] init];

	// TODO: This code up to and including stickHandler really ought
	// not to be in this class.
	OOLog(@"sdl.init", @"%@", @"initialising SDL");
	if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD))
	{
		OOLog(@"sdl.init.failed", @"Unable to init SDL: %s\n", SDL_GetError());
		[self dealloc];
		return nil;
	}

	[self populateFullScreenModelist];

	// Find what the full screen and windowed settings are.
	fullScreen = NO;
	currentSize = 0;
	[self loadWindowSize];
	[self loadFullscreenSettings];

	// Set up the drawing surface's dimensions.
	firstScreen = (fullScreen) ? [self modeAsSize: currentSize] : currentWindowSize;
	viewSize = firstScreen;	// viewSize must be set prior to splash screen initialization

	[OOJoystickManager setStickHandlerClass:[OOSDLJoystickManager class]];
	// end TODO

	[OOSound setUp];
	if (![OOSound isSoundOK])  OOLog(@"sound.init", @"%@", @"Sound system disabled.");

	grabMouseStatus = NO;

	OOLog(@"display.mode.list", @"%@", @"CREATING MODE LIST");

	if (!showSplashScreen)
	{
		// blank the surface / go to fullscreen
		[self initialiseGLWithSize: firstScreen];
	}

	[self autoShowMouse];

	virtualJoystickPosition = NSMakePoint(0.0,0.0);
	mouseWarped = NO;

	_mouseVirtualStickSensitivityFactor = OOClamp_0_1_f([prefs oo_floatForKey:@"mouse-flight-sensitivity" defaultValue:0.95f]);
	// ensure no chance of a divide by zero later on
	if (_mouseVirtualStickSensitivityFactor < 0.005f)  _mouseVirtualStickSensitivityFactor = 0.005f;

	typedString = [[NSMutableString alloc] initWithString:@""];
	allowingStringInput = gvStringInputNo;
	isAlphabetKeyDown = NO;

	timeIntervalAtLastClick = timeSinceLastMouseWheel = [NSDate timeIntervalSinceReferenceDate];

	_mouseWheelDelta = 0.0f;

	return self;
}

- (void) endSplashScreen
{
#if OOLITE_WINDOWS
	// we need to get through here even if splash screen has not
	// been shown - this method also prepares the main game window
	if ([self hdrOutput] && ![self isOutputDisplayHDREnabled])
	{
		if (MessageBox(NULL,	"No primary display in HDR mode was detected.\n\n"
							"If you continue, graphics will not be rendered as intended.\n"
							"Click OK to launch anyway, or Cancel to exit.", "oolite.exe - HDR requested",
							MB_OKCANCEL | MB_ICONWARNING) == IDCANCEL)
		{
			[gameController exitAppWithContext:@"Cancel selected on no-HDR confirmation dialog"];
		}
	}

#endif
	SDL_SetWindowResizable(window, true);
	SDL_SetWindowBordered(window, true);
    if (!showSplashScreen)  return;

	if (fullScreen)
	{
		SDL_SetWindowFullscreen(window, true);
	}
	else
	{
		SDL_HideWindow(window);
		SDL_SetWindowFullscreen(window, false);
		SDL_SetWindowSize(window, firstScreen.width, firstScreen.height);
    	SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
		SDL_ShowWindow(window);
	}

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

	[self initialiseGLWithSize:firstScreen];
	[self updateScreen];
	[self autoShowMouse];
}

- (void) updateGLSize:(NSSize) size
{
	bounds.size = size;
	viewSize = size;

	if (bounds.size.width / bounds.size.height > 4.0 / 3.0)
	{
		display_z = 480.0 * bounds.size.width / bounds.size.height;
		x_offset = 240.0 * bounds.size.width / bounds.size.height;
		y_offset = 240.0;
	}
	else
	{
		display_z = 640.0;
		x_offset = 320.0;
		y_offset = 320.0 * bounds.size.height / bounds.size.width;
	}

	float ratio = 0.5;
	float aspect = bounds.size.height / bounds.size.width;

	OOGL(glViewport(0, 0, bounds.size.width, bounds.size.height));
	OOGLResetProjection();
	OOGLFrustum(-ratio, ratio, -aspect * ratio, aspect * ratio, 1.0, MAX_CLEAR_DEPTH);
}


- (void) setUpBasicOpenGLStateWithSize
{
	OOOpenGLExtensionManager *extMgr = [OOOpenGLExtensionManager sharedManager];

	OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
	OOGL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
	OOGL(glClearDepth(1.0));
	OOGL(glDepthFunc(GL_LESS));	// depth buffer

	if (UNIVERSE)
	{
		[UNIVERSE setLighting];
	}
	else
	{
		GLfloat black[4]        = {0.0, 0.0, 0.0, 1.0};
		GLfloat white[]         = {1.0, 1.0, 1.0, 1.0};
		GLfloat stars_ambient[] = {0.25, 0.2, 0.25, 1.0};

		OOGL(glLightfv(GL_LIGHT1, GL_AMBIENT, black));
		OOGL(glLightfv(GL_LIGHT1, GL_SPECULAR, white));
		OOGL(glLightfv(GL_LIGHT1, GL_DIFFUSE, white));
		OOGL(glLightfv(GL_LIGHT1, GL_POSITION, black));
		OOGL(glLightModelfv(GL_LIGHT_MODEL_AMBIENT, stars_ambient));
	}

	if ([extMgr usePointSmoothing])
	{
		OOGL(glEnable(GL_POINT_SMOOTH));
	}

	if ([extMgr useLineSmoothing])
	{
		OOGL(glEnable(GL_LINE_SMOOTH));
	}

	OOGL(glDisable(GL_NORMALIZE));
	OOGL(glDisable(GL_RESCALE_NORMAL));

	OOGL(glLightModeli(GL_LIGHT_MODEL_COLOR_CONTROL, GL_SEPARATE_SPECULAR_COLOR));
}


- (void) initialiseGLWithSize:(NSSize) v_size
{
	if (!window)
	{
		[self createWindowWithSize:v_size];
	}

	viewSize = v_size;

	OOLog(@"display.initGL", @"Requested a new surface of %d x %d, %@.", (int)viewSize.width, (int)viewSize.height,
	    (fullScreen ? @"fullscreen" : @"windowed"));

	SDL_GL_SwapWindow(window);	// clear the buffer before resize

	SDL_SetWindowFullscreen(window, fullScreen);

	if (!fullScreen)
	{
		SDL_SetWindowSize(window, viewSize.width, viewSize.height);
		SDL_SetWindowBordered(window, YES);
	}
#if OOLITE_WINDOWS
	else	// Hack for Windows SDL3 pause issue: https://github.com/libsdl-org/SDL/issues/12791
	{		// Occurs on some systems eg. when going fullscreen -> window or vice versa
		LONG currentWindowStyle = GetWindowLong(windowHandle, GWL_STYLE);
		currentWindowStyle &= ~WS_POPUP;
		SetWindowLong(windowHandle, GWL_STYLE, currentWindowStyle);
	}
#endif

	int pixelWidth, pixelHeight;
	SDL_GetWindowSizeInPixels(window, &pixelWidth, &pixelHeight);

	[self updateGLSize:NSMakeSize(pixelWidth, pixelHeight)];

	OOLog(@"display.initGL",
		  @"Created a new surface of %d x %d, %@.",
		  (int)viewSize.width,
		  (int)viewSize.height,
		  (fullScreen ? @"fullscreen" : @"windowed"));

	[self autoShowMouse];

	[self setUpBasicOpenGLStateWithSize];

	SDL_GL_SwapWindow(window);

	squareX = 0.0f;
}


- (void) dealloc
{
	if (typedString)
		[typedString release];

	if (screenSizes)
		[screenSizes release];

	if (window)
	{
		SDL_DestroyWindow(window);
	}

	if (glContext)
	{
		SDL_GL_DestroyContext(glContext);
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
	return bounds.size;
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


- (BOOL) inFullScreenMode
{
	return fullScreen;
}

#ifdef GNUSTEP_BASE_LIBRARY
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
 	if(fullScreen)
	{
 		[self initialiseGLWithSize:[self modeAsSize: currentSize]];
	}
	else
	{
		[self initialiseGLWithSize: currentWindowSize];
#if OOLITE_LINUX
		SDL_HideWindow(window);
    	SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
		SDL_ShowWindow(window);
#endif
	}
}


- (void) setDisplayMode:(int)mode  fullScreen:(BOOL)fsm
{
	[self setFullScreenMode: fsm];
	currentSize=mode;
	if(fullScreen)
		[self initialiseGLWithSize: [self modeAsSize: mode]];
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

- (void) updateScreen
{
	if (UNIVERSE)
	{
		[UNIVERSE drawUniverse];  // do all the drawing!
	}
	else
	{
		glClearColor( 0.0, 0.0, 0.0, 0.0);  // not set up yet, draw a black screen
		glClear( GL_COLOR_BUFFER_BIT);
	}

	SDL_GL_SwapWindow(window);
}

- (void) initSplashScreen
{
	if (!showSplashScreen) return;

	//too early for OOTexture!
	SDL_Surface     	*image=NULL;
	SDL_Rect			dest;

	NSString		*imagesDir = [[ResourceManager builtInPath] stringByAppendingPathComponent:@"Images"];

	image = SDL_LoadBMP([[imagesDir stringByAppendingPathComponent:@"splash.bmp"] UTF8String]);

	if (image == NULL)
	{
		SDL_DestroySurface(image);
		OOLogWARN(@"sdl.gameStart", @"%@", @"image 'splash.bmp' not found!");
		[self endSplashScreen];
		return;
	}

	dest.x = 0;
	dest.y = 0;
	dest.w = image->w;
	dest.h = image->h;

	[self createWindowWithSize: NSMakeSize(image->w, image->h)];
	OOSetOpenGLState(OPENGL_STATE_OVERLAY);
	float pixelDensity = SDL_GetWindowPixelDensity(window);
	if (pixelDensity == 0.0f)
	{
		pixelDensity = 1.0f;
	}

	glViewport( 0, 0, dest.w * pixelDensity, dest.h * pixelDensity);

	glEnable( GL_TEXTURE_2D );
	glClearColor( 0.0f, 0.0f, 0.0f, 0.0f );
	glClear( GL_COLOR_BUFFER_BIT );

	[matrixManager resetProjection];
	[matrixManager orthoLeft: 0.0f right: 1.0f bottom: 1.0f top: 0.0f near: -1.0f far: 1.0f];
	[matrixManager syncProjection];

	[matrixManager resetModelView];
	[matrixManager syncModelView];

	GLuint texture;
	GLenum texture_format;
	GLint  nOfColors;

	// get the number of channels in the SDL image
	const SDL_PixelFormatDetails *pixelFormat = SDL_GetPixelFormatDetails(image->format);
	nOfColors = pixelFormat->bytes_per_pixel;
	if (nOfColors == 4)     // contains an alpha channel
	{
		if (pixelFormat->Rmask == 0x000000ff)
			texture_format = GL_RGBA;
		else
			texture_format = GL_BGRA;
	}
	else if (nOfColors == 3)     // no alpha channel
	{
		if (pixelFormat->Rmask == 0x000000ff)
			texture_format = GL_RGB;
		else
			texture_format = GL_BGR;
	} else {
		SDL_DestroySurface(image);
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
	glVertex2i( 1, 0 );
	glTexCoord2i( 1, 1 );
	glVertex2i( 1, 1 );
	glTexCoord2i( 0, 1 );
	glVertex2i( 0, 1 );

	glEnd();
	glFinish();

	SDL_GL_SwapWindow(window);
	[matrixManager resetModelView];
	[matrixManager syncModelView];

	if ( image ) {
		SDL_DestroySurface( image );
	}
	glDeleteTextures(1, &texture);

	glDisable( GL_TEXTURE_2D );
	OOVerifyOpenGLState();

	SDL_DestroySurface(image);
	return;
}


#if OOLITE_WINDOWS
- (MONITORINFOEX) currentMonitorInfo
{
	return monitorInfo;
}


- (BOOL) getCurrentMonitorInfo:(MONITORINFOEX *)mInfo
{
	HMONITOR hMon = MonitorFromWindow(windowHandle, MONITOR_DEFAULTTOPRIMARY);
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
		GetWindowRect(windowHandle, &gameWindowRect);
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


- (void) refreshDarKOrLightMode
{
	int shouldSetDarkMode = [self isDarkModeOn];
	DwmSetWindowAttribute (windowHandle, DWMWA_USE_IMMERSIVE_DARK_MODE, &shouldSetDarkMode, sizeof(shouldSetDarkMode));
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
	BOOL result = NO;
	SDL_DisplayID displayID = SDL_GetPrimaryDisplay();  // Get the primary display ID
	if (displayID == 0)
	{
		OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Failed to retrieve primary display ID: %s", SDL_GetError());
		return NO;
	}
	SDL_PropertiesID props = SDL_GetDisplayProperties(displayID);  // Retrieve properties for the target display
	if (props == 0)
	{
		OOLog(@"gameView.isOutputDisplayHDREnabled", @"Error! Failed to get display properties: %s", SDL_GetError());
		return NO;
	}
	result = SDL_GetBooleanProperty(props, SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN, false);  // Query for HDR enabling
	OOLog(@"gameView.isOutputDisplayHDREnabled", @"HDR display output requested - checking availability: %@", result ? @"YES" : @"NO");
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


- (OOHDRToneMapper) hdrToneMapper
{
	return _hdrToneMapper;
}


- (void) setHDRToneMapper: (OOHDRToneMapper)newToneMapper
{
	if (newToneMapper > OOHDR_TONEMAPPER_REINHARD)  newToneMapper = OOHDR_TONEMAPPER_REINHARD;
	if (newToneMapper < OOHDR_TONEMAPPER_NONE)  newToneMapper = OOHDR_TONEMAPPER_NONE;
	_hdrToneMapper = newToneMapper;
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


- (BOOL) hdrOutput
{
	return NO;
}


- (BOOL) isOutputDisplayHDREnabled
{
	return NO;
}

#endif //OOLITE_WINDOWS


- (OOSDRToneMapper) sdrToneMapper
{
	return _sdrToneMapper;
}


- (void) setSDRToneMapper: (OOSDRToneMapper)newToneMapper
{
	if (newToneMapper > OOSDR_TONEMAPPER_REINHARD)  newToneMapper = OOSDR_TONEMAPPER_REINHARD;
	if (newToneMapper < OOSDR_TONEMAPPER_NONE)  newToneMapper = OOSDR_TONEMAPPER_NONE;
	_sdrToneMapper = newToneMapper;
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

	SDL_Surface *surface = SDL_GetWindowSurface(window);
	OOLog(@"screenshot", @"Saving screen shot \"%@\" (%u x %u pixels).", pathToPic, surface->w, surface->h);

	int pitch = surface->pitch;
	unsigned char *pixls = malloc(pitch * surface->h);
	int y;
	int off;

	if (surface->w % 4) glPixelStorei(GL_PACK_ALIGNMENT,1);
	else                glPixelStorei(GL_PACK_ALIGNMENT,4);
	for (y=surface->h-1, off=0; y>=0; y--, off+=pitch)
	{
		glReadPixels(0, y, surface->w, 1, GL_BGRA, GL_UNSIGNED_BYTE, pixls + off);
	}
	
	tmpSurface = SDL_CreateSurfaceFrom(surface->w, surface->h, surface->format, pixls, surface->pitch);
#if SNAPSHOTS_PNG_FORMAT
	if(!SDL_SavePNG(tmpSurface, [pathToPic UTF8String]))
	{
		OOLog(@"screenshotPNG", @"Failed to save %@", pathToPic);
		snapShotOK = NO;
	}
#else
	if (!SDL_SaveBMP(tmpSurface, [pathToPic UTF8String]))
	{
		OOLog(@"screenshotBMP", @"Failed to save %@", pathToPic);
		snapShotOK = NO;
	}
#endif
	SDL_DestroySurface(tmpSurface);
	free(pixls);
	
	// if outputting HDR signal, save also either an .exr or a Radiance .hdr snapshot
	if ([self hdrOutput])
	{
		NSString *fileExtension = [[NSUserDefaults standardUserDefaults] oo_stringForKey:@"hdr-snapshot-format" defaultValue:SNAPSHOTHDR_EXTENSION_DEFAULT];
		
		// we accept file extension with or without a leading dot; if it is without, insert it at the beginning now
		if (![[fileExtension substringToIndex:1] isEqual:@"."])  fileExtension = [@"." stringByAppendingString:fileExtension];
		
		if (![fileExtension isEqual:SNAPSHOTHDR_EXTENSION_EXR] && ![fileExtension isEqual:SNAPSHOTHDR_EXTENSION_HDR])
		{
			OOLog(@"screenshotHDR", @"Unrecognized HDR file format requested, defaulting to %@", SNAPSHOTHDR_EXTENSION_DEFAULT);
			fileExtension = SNAPSHOTHDR_EXTENSION_DEFAULT;
		}
		
		NSString *pathToPicHDR = [pathToPic stringByReplacingString:@".png" withString:fileExtension];
		OOLog(@"screenshot", @"Saving screen shot \"%@\" (%u x %u pixels).", pathToPicHDR, surface->w, surface->h);
		GLfloat *pixlsf = (GLfloat *)malloc(pitch * surface->h * sizeof(GLfloat));
		for (y=surface->h-1, off=0; y>=0; y--, off+=pitch)
		{
			glReadPixels(0, y, surface->w, 1, GL_RGB, GL_FLOAT, pixlsf + off);
		}
		
		if (([fileExtension isEqual:SNAPSHOTHDR_EXTENSION_EXR] && SaveEXRSnapshot([pathToPicHDR cStringUsingEncoding:NSUTF8StringEncoding], surface->w, surface->h, pixlsf) != 0) //TINYEXR_SUCCESS
			|| ([fileExtension isEqual:SNAPSHOTHDR_EXTENSION_HDR] && !stbi_write_hdr([pathToPicHDR cStringUsingEncoding:NSUTF8StringEncoding], surface->w, surface->h, 3, pixlsf)))
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




// Full screen mode enumerator.
- (void) populateFullScreenModelist
{
	int i;
	SDL_DisplayMode **modes;
	NSMutableDictionary *mode;
	SDL_DisplayID displayId = [self getDisplayId];

	screenSizes=[[NSMutableArray alloc] init];

	// The default resolution (slot 0) is the resolution we are
	// already in since this is guaranteed to work.
	mode=[self getNativeSize];
	[screenSizes addObject: mode];

	int displayModeCount;
	modes = SDL_GetFullscreenDisplayModes(displayId, &displayModeCount);
	if(!displayModeCount)
	{
		OOLog(@"display.mode.list.none", @"%@", @"SDL didn't return any screen modes");
		return;
	}

	for(i=0; i < displayModeCount; i++)
	{
		mode = [NSMutableDictionary dictionary];
		[mode setValue: [NSNumber numberWithInt: (int)modes[i]->w]
				forKey: kOODisplayWidth];
		[mode setValue: [NSNumber numberWithInt: (int)modes[i]->h]
				forKey: kOODisplayHeight];
		[mode setValue: [NSNumber numberWithFloat: (int)modes[i]->refresh_rate]
				forKey: kOODisplayRefreshRate];
		if (![screenSizes containsObject:mode])
		{
			[screenSizes addObject: mode];
			OOLog(@"display.mode.list", @"Added res %d x %d", modes[i]->w, modes[i]->h);
		}
	}
	SDL_free(modes);
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
		windowSize=NSMakeSize(WINDOW_SIZE_DEFAULT_WIDTH, WINDOW_SIZE_DEFAULT_HEIGHT);
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
	return NSMakeSize(WINDOW_SIZE_DEFAULT_WIDTH, WINDOW_SIZE_DEFAULT_HEIGHT);
}

- (NSDictionary *) currentScreenMode
{
	NSDictionary *mode=[screenSizes objectAtIndex: currentSize];
	return [[mode retain] autorelease];
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
#if !OOLITE_WINDOWS
	return 0 != (SDL_GetModState() & (SDL_KMOD_LSHIFT | SDL_KMOD_RSHIFT));
#else
	// SDL_GetModState() does not seem to do exactly what is intended under Windows. For this reason,
	// the GetKeyState Windows API call is used to detect the Shift keypress. -- Nikos.
	return 0 != (GetKeyState(VK_SHIFT) & 0x100);
#endif
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
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.png", name]];

	SDL_Surface* tmpSurface = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_RGBA32, bytes, rowBytes);
	SDL_SavePNG(tmpSurface, [dumpFile UTF8String]);
	SDL_DestroySurface(tmpSurface);
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
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.png", name]];

	SDL_Surface* tmpSurface = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_RGB24, bytes, rowBytes);
	SDL_SavePNG(tmpSurface, [dumpFile UTF8String]);
	SDL_DestroySurface(tmpSurface);
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
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.png", name]];

	SDL_Surface* tmpSurface = SDL_CreateSurface(width, height, SDL_PIXELFORMAT_RGBA32);
	for(int y = 0; y < height; y++)
	{
		uint8_t* srcRow = bytes + rowBytes*y;
		uint8_t* dstRow = (uint8_t*)tmpSurface->pixels + y*tmpSurface->pitch;
		for(int x = 0; x < width; x++)
		{
			dstRow[4*x + 0] = srcRow[x];
			dstRow[4*x + 1] = srcRow[x];
			dstRow[4*x + 2] = srcRow[x];
			dstRow[4*x + 3] = '\xff';
		}
	}
	SDL_SavePNG(tmpSurface, [dumpFile UTF8String]);
	SDL_DestroySurface(tmpSurface);
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
	dumpFile = [dumpFile stringByAppendingPathComponent: [NSString stringWithFormat:@"%@.png", name]];

	SDL_Surface* tmpSurface = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_RGBA32, bytes, rowBytes);
	for(int y = 0; y < height; y++)
	{
		uint8_t* srcRow = bytes + rowBytes*y;
		uint8_t* dstRow = (uint8_t*)tmpSurface->pixels + y*tmpSurface->pitch;
		for(int x = 0; x < width; x++)
		{
			dstRow[4*x + 0] = srcRow[2*x];
			dstRow[4*x + 1] = srcRow[2*x];
			dstRow[4*x + 2] = srcRow[2*x];
			dstRow[4*x + 3] = srcRow[2*x+1];
		}
	}
	SDL_SavePNG(tmpSurface, [dumpFile UTF8String]);
	SDL_DestroySurface(tmpSurface);
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
