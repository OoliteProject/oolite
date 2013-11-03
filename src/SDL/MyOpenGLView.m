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

#define kOOLogUnconvertedNSLog @"unclassified.MyOpenGLView"

#include <ctype.h>

@interface MyOpenGLView (OOPrivate)

- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event; // DJS
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
		OOLog(@"display.mode.list.native.failed", @"SDL_GetWMInfo failed, defaulting to 1024x768 for native size");
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
		MoveWindow(SDL_Window,GetSystemMetrics(SM_CXSCREEN)/2,GetSystemMetrics(SM_CYSCREEN)/2,1,1,TRUE); // centre the splash screen

		// Initialise the SDL surface. (need custom SDL.dll)
		surface = SDL_SetVideoMode(firstScreen.width, firstScreen.height, 32, videoModeFlags);

		// Post setVideoMode adjustments.
		currentWindowSize=tmp;
#else
		// Changing the flags can trigger texture bugs.
		surface = SDL_SetVideoMode(8, 8, 32, videoModeFlags);
		if (!surface) {
			return;
		}
#endif
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

	NSArray				*arguments = nil;
	NSEnumerator		*argEnum = nil;
	NSString			*arg = nil;

	arguments = [[NSProcessInfo processInfo] arguments];

	// scan for splash screen overrides: -nosplash || --nosplash , -splash || --splash
	for (argEnum = [arguments objectEnumerator]; (arg = [argEnum nextObject]); )
	{
		if ([arg isEqual:@"-nosplash"] || [arg isEqual:@"--nosplash"])
		{
			showSplashScreen = NO;
			break;	// -nosplash always trumps -splash
		}
		else if ([arg isEqual:@"-splash"] || [arg isEqual:@"--splash"])
		{
			showSplashScreen = YES;
		}
	}

	// TODO: This code up to and including stickHandler really ought
	// not to be in this class.
	OOLog(@"sdl.init", @"initialising SDL");
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

	// Generate the window caption, containing the version number and the date the executable was compiled.
	static char windowCaption[128];
	NSString *versionString = [NSString stringWithFormat:@"Oolite v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];

	strcpy (windowCaption, [versionString UTF8String]);
	strcat (windowCaption, " - "__DATE__);
	SDL_WM_SetCaption (windowCaption, "Oolite");	// Set window title.

#if OOLITE_WINDOWS

	//capture the window handle for later
	static SDL_SysWMinfo wInfo;
	SDL_VERSION(&wInfo.version);
	SDL_GetWMInfo(&wInfo);
	SDL_Window   = wInfo.window;

#endif

	imagesDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Images"];
	icon = SDL_LoadBMP([[imagesDir stringByAppendingPathComponent:@"WMicon.bmp"] UTF8String]);

	if (icon != NULL)
	{
		colorkey = SDL_MapRGB(icon->format, 128, 0, 128);
		SDL_SetColorKey(icon, SDL_SRCCOLORKEY, colorkey);
		SDL_WM_SetIcon(icon, NULL);
	}
	SDL_FreeSurface(icon);

	SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
	SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 32);
	SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
	SDL_GL_SetAttribute(SDL_GL_SWAP_CONTROL, 1);	// V-sync on by default.


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

	OOLog(@"display.mode.list", @"CREATING MODE LIST");
	[self populateFullScreenModelist];
	currentSize = 0;

	// Find what the full screen and windowed settings are.
	[self loadFullscreenSettings];
	[self loadWindowSize];

	// Set up the drawing surface's dimensions.
	firstScreen= (fullScreen) ? [self modeAsSize: currentSize] : currentWindowSize;
	viewSize = firstScreen;	// viewSize must be set prior to splash screen initialization

	OOLog(@"display.initGL",@"Trying 32-bit depth buffer");
	[self createSurface];
	if (surface == NULL)
	{
		// Retry with a 24-bit depth buffer
		OOLog(@"display.initGL",@"Trying 24-bit depth buffer");
		SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
		[self createSurface];
		if (surface == NULL)
		{
			// Still not working? One last go...
			// Retry, allowing 16-bit contexts.
			OOLog(@"display.initGL",@"Trying 16-bit depth buffer");
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
					OOLogWARN(@"display.mode.conflict",@"Possible incompatibility between the splash screen and video drivers detected.");
					OOLogWARN(@"display.mode.conflict",@"Oolite will start without showing the splash screen from now on. Override with 'oolite.exe -splash'");
				}
#endif
				exit(1);
			}
		}
	}

	bounds.size.width = surface->w;
	bounds.size.height = surface->h;

	[self autoShowMouse];

	virtualJoystickPosition = NSMakePoint(0.0,0.0);
	mouseWarped = NO;

	typedString = [[NSMutableString alloc] initWithString:@""];
	allowingStringInput = gvStringInputNo;
	isAlphabetKeyDown = NO;

	timeIntervalAtLastClick = [NSDate timeIntervalSinceReferenceDate];

	m_glContextInitialized = NO;

	return self;
}

- (void) endSplashScreen
{
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

	SDL_Quit();

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
	if(fullScreen)
		[self initialiseGLWithSize:[self modeAsSize: currentSize]];
	else
		[self initialiseGLWithSize: currentWindowSize];
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
		OOLogWARN(@"sdl.gameStart", @"image 'splash.bmp' not found!");
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

	glMatrixMode( GL_PROJECTION );
	glPushMatrix();
	glLoadIdentity();

	glOrtho(0.0f, dest.w , dest.h, 0.0f, -1.0f, 1.0f);

	glMatrixMode( GL_MODELVIEW );
	glPushMatrix();
	glLoadIdentity();

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
		OOLog(@"Sdl.GameStart", @"----- Encoding error within image 'splash.bmp'");
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
	glLoadIdentity();       // reset matrix

	if ( image ) {
		SDL_FreeSurface( image );
	}
	glDeleteTextures(1, &texture);

	glDisable( GL_TEXTURE_2D );
	OOVerifyOpenGLState();
}

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
			//ChangeDisplaySettings(NULL, 0);
	RECT wDC;

	if (fullScreen)
	{

		settings.dmPelsWidth = viewSize.width;
		settings.dmPelsHeight = viewSize.height;
		settings.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
		if(!wasFullScreen) {
			SetWindowLong(SDL_Window,GWL_STYLE,GetWindowLong(SDL_Window,GWL_STYLE) & ~WS_CAPTION & ~WS_THICKFRAME);
		}
		SetForegroundWindow(SDL_Window);
		if (ChangeDisplaySettings(&settings, CDS_FULLSCREEN)==DISP_CHANGE_SUCCESSFUL)
		{
			MoveWindow(SDL_Window, 0, 0, viewSize.width, viewSize.height, TRUE);
		}
		else
		{
			m_glContextInitialized = YES;
			return;
		}

	}
	else if ( wasFullScreen )
	{
			// stop saveWindowSize from reacting to caption & frame
			saveSize=NO;
			ChangeDisplaySettings(NULL, 0);
			SetWindowLong(SDL_Window,GWL_STYLE,GetWindowLong(SDL_Window,GWL_STYLE) | WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX );

			MoveWindow(SDL_Window,(GetSystemMetrics(SM_CXSCREEN)-(int)viewSize.width)/2,
			(GetSystemMetrics(SM_CYSCREEN)-(int)viewSize.height)/2 -16,(int)viewSize.width,(int)viewSize.height,TRUE);

			ShowWindow(SDL_Window,SW_SHOW);
	}

	GetClientRect(SDL_Window, &wDC);

	if (!fullScreen && (bounds.size.width != wDC.right - wDC.left
					|| bounds.size.height != wDC.bottom - wDC.top))
	{
		RECT wDCtemp;

		// MoveWindow is used below to resize the game window when required. The resized window it
		// creates includes the client plus the non-client area. This means that although dimensions
		// capable of containing our wanted client area size are requested, the actual window generated has a
		// slightly smaller client area than intended. We fix this by calculating nonClientAreaCorrection
		// and adding it to the needed size when necessary (i.e. after splash screen or when switching from
		// full screen to window) - Nikos 20091024
		NSSize nonClientAreaCorrection = NSMakeSize(0,0);

		GetWindowRect(SDL_Window, &wDC);
		if (wasFullScreen) // this is true when switching from full screen or when starting in windowed mode after the splash screen has ended
		{
			wDCtemp.top = wDC.top; wDCtemp.bottom = wDC.bottom; wDCtemp.left = wDC.left; wDCtemp.right = wDC.right;
			AdjustWindowRect(&wDCtemp, WS_CAPTION | WS_THICKFRAME, FALSE);
			nonClientAreaCorrection.width = fabs((wDCtemp.right - wDCtemp.left) - (wDC.right - wDC.left));
			nonClientAreaCorrection.height = fabs((wDCtemp.bottom - wDCtemp.top) - (wDC.bottom - wDC.top));
		}
		viewSize.width = wDC.right - wDC.left;
		viewSize.height = wDC.bottom - wDC.top;
		MoveWindow(SDL_Window,wDC.left,wDC.top,viewSize.width + nonClientAreaCorrection.width,viewSize.height + nonClientAreaCorrection.height,TRUE);
		GetClientRect(SDL_Window, &wDC);
	}

	// Reset bounds and viewSize to current values
	bounds.size.width = viewSize.width = wDC.right - wDC.left;
	bounds.size.height = viewSize.height = wDC.bottom - wDC.top;
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
		OOLog(@"pngSaveSurface.info_struct.failed", @"png_create_info_struct error");
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
- (void) supressKeysUntilKeyUp
{
	if (keys[gvMouseDoubleClick] == NO)
   	{
   		supressKeys = YES;
   		[self clearKeys];
   	}
   	else
   	{
   		[self clearMouse];
   	}

}


- (BOOL) isDown: (int) key
{
	if ( supressKeys )
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


- (int) numKeys
{
	return NUM_KEYS;
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


- (void) setKeyboardTo: (NSString *) value
{
#if OOLITE_WINDOWS
	keyboardMap=gvKeyboardAuto;

	if ([value isEqual: @"UK"])
	{
		keyboardMap=gvKeyboardUK;
	}
	else if ([value isEqual: @"US"])
	{
		keyboardMap=gvKeyboardUS;
	}
#endif
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
				}
				break;

			case SDL_MOUSEBUTTONUP:
				mbtn_event = (SDL_MouseButtonEvent*)&event;
				NSTimeInterval timeBetweenClicks = [NSDate timeIntervalSinceReferenceDate] - timeIntervalAtLastClick;
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

				if(allowingStringInput)
				{
					[self handleStringInput: kbd_event];
				}

				// Macro KEYCODE_DOWN_EITHER. Detect the keypress state (with shift or without) and assign appropriate values to the
				// keys array. This way Oolite can use more keys, since now key '3', for example is a different keypress to '#'.
#define KEYCODE_DOWN_EITHER(a,b)	do { \
if (shift) { keys[a] = YES; keys[b] = NO; } else { keys[a] = NO; keys[b] = YES; } \
} while (0)

#if OOLITE_WINDOWS
				/*
					Windows locale patch - Enable backslash in win/UK
				*/
				if (EXPECT_NOT(kbd_event->keysym.scancode==86 && (keyboardMap==gvKeyboardAuto || keyboardMap==gvKeyboardUK)))
				{
					//non-US scancode. If in autodetect, we'll assume UK keyboard.
					KEYCODE_DOWN_EITHER (124, 92);								//	| or \.
				}
				else switch (kbd_event->keysym.sym) {

					case SDLK_BACKSLASH:
						if (keyboardMap==gvKeyboardUK )
						{
							KEYCODE_DOWN_EITHER (126, 35);						// ~ or #
						}
						else if (keyboardMap==gvKeyboardAuto || keyboardMap==gvKeyboardUS)
						{
							KEYCODE_DOWN_EITHER (124, 92); 						// | or \.
						}
						break;
#else
				switch (kbd_event->keysym.sym) {

					case SDLK_BACKSLASH: KEYCODE_DOWN_EITHER (124, 92); break;	// | or \.
#endif
					case SDLK_1: KEYCODE_DOWN_EITHER (33, gvNumberKey1); break;	// ! or 1
#if OOLITE_WINDOWS
					/*
						Windows locale patch - fix shift-2 & shift-3
					*/
					case SDLK_2:
						if (keyboardMap==gvKeyboardUK)
						{
							KEYCODE_DOWN_EITHER (34, gvNumberKey2);				// " or 2
						}
						else
						{
							KEYCODE_DOWN_EITHER (64, gvNumberKey2);             // @ or 2
						}
						break;
					case SDLK_3:
						if (keyboardMap==gvKeyboardUK)
						{
							KEYCODE_DOWN_EITHER (156, gvNumberKey3);            // � or 3
						}
						else
						{
							KEYCODE_DOWN_EITHER (35, gvNumberKey3);             // # or 3
						}
						break;
#else
					case SDLK_2: KEYCODE_DOWN_EITHER (64, gvNumberKey2); break;	// @ or 2
					case SDLK_3: KEYCODE_DOWN_EITHER (35, gvNumberKey3); break;	// # or 3
#endif
					case SDLK_4: KEYCODE_DOWN_EITHER (36, gvNumberKey4); break;	// $ or 4
					case SDLK_5: KEYCODE_DOWN_EITHER (37, gvNumberKey5); break;	// % or 5
					case SDLK_6: KEYCODE_DOWN_EITHER (94, gvNumberKey6); break;	// ^ or 6
					case SDLK_7: KEYCODE_DOWN_EITHER (38, gvNumberKey7); break;	// & or 7
					case SDLK_8: KEYCODE_DOWN_EITHER (42, gvNumberKey8); break;	// * or 8
					case SDLK_9: KEYCODE_DOWN_EITHER (40, gvNumberKey9); break;	// ( or 9
					case SDLK_0: KEYCODE_DOWN_EITHER (41, gvNumberKey0); break;	// ) or 0
					case SDLK_MINUS: KEYCODE_DOWN_EITHER (95, 45); break;		// _ or -
					case SDLK_COMMA: KEYCODE_DOWN_EITHER (60, 44); break;		// < or ,
					case SDLK_EQUALS: KEYCODE_DOWN_EITHER (43, 61); break;		// + or =
					case SDLK_PERIOD: KEYCODE_DOWN_EITHER (62, 46); break;		// > or .
					case SDLK_SLASH: KEYCODE_DOWN_EITHER (63, 47); break;		// ? or /
					case SDLK_a: KEYCODE_DOWN_EITHER (65, 97); break;		// A or a
					case SDLK_b: KEYCODE_DOWN_EITHER (66, 98); break;		// B or b
					case SDLK_c: KEYCODE_DOWN_EITHER (67, 99); break;		// C or c
					case SDLK_d: KEYCODE_DOWN_EITHER (68, 100); break;		// D or d
					case SDLK_e: KEYCODE_DOWN_EITHER (69, 101); break;		// E or e
					case SDLK_f: KEYCODE_DOWN_EITHER (70, 102); break;		// F or f
					case SDLK_g: KEYCODE_DOWN_EITHER (71, 103); break;		// G or g
					case SDLK_h: KEYCODE_DOWN_EITHER (72, 104); break;		// H or h
					case SDLK_i: KEYCODE_DOWN_EITHER (73, 105); break;		// I or i
					case SDLK_j: KEYCODE_DOWN_EITHER (74, 106); break;		// J or j
					case SDLK_k: KEYCODE_DOWN_EITHER (75, 107); break;		// K or k
					case SDLK_l: KEYCODE_DOWN_EITHER (76, 108); break;		// L or l
					case SDLK_m: KEYCODE_DOWN_EITHER (77, 109); break;		// M or m
					case SDLK_n: KEYCODE_DOWN_EITHER (78, 110); break;		// N or n
					case SDLK_o: KEYCODE_DOWN_EITHER (79, 111); break;		// O or o
					case SDLK_p: KEYCODE_DOWN_EITHER (80, 112); break;		// P or p
					case SDLK_q: KEYCODE_DOWN_EITHER (81, 113); break;		// Q or q
					case SDLK_r: KEYCODE_DOWN_EITHER (82, 114); break;		// R or r
					case SDLK_s: KEYCODE_DOWN_EITHER (83, 115); break;		// S or s
					case SDLK_t: KEYCODE_DOWN_EITHER (84, 116); break;		// T or t
					case SDLK_u: KEYCODE_DOWN_EITHER (85, 117); break;		// U or u
					case SDLK_v: KEYCODE_DOWN_EITHER (86, 118); break;		// V or v
					case SDLK_w: KEYCODE_DOWN_EITHER (87, 119); break;		// W or w
					case SDLK_x: KEYCODE_DOWN_EITHER (88, 120); break;		// X or x
					case SDLK_y: KEYCODE_DOWN_EITHER (89, 121); break;		// Y or y
					case SDLK_z: KEYCODE_DOWN_EITHER (90, 122); break;		// Z or z
					case SDLK_SEMICOLON: KEYCODE_DOWN_EITHER(58, 59); break; // : or ;
						//SDLK_BACKQUOTE and SDLK_HASH are special cases. No SDLK_ with code 126 exists.
					case SDLK_HASH: if (!shift) keys[126] = YES; break;		// ~ (really #)
					case SDLK_BACKQUOTE: if (!shift) keys[96] = YES; break;		// `
					case SDLK_QUOTE: keys[39] = YES; break;				// '
					case SDLK_LEFTBRACKET: keys[91] = YES; break;			// [
					case SDLK_RIGHTBRACKET: keys[93] = YES; break;			// ]
					case SDLK_HOME: keys[gvHomeKey] = YES; break;
					case SDLK_END: keys[gvEndKey] = YES; break;
					case SDLK_INSERT: keys[gvInsertKey] = YES; break;
					case SDLK_PAGEUP: keys[gvPageUpKey] = YES; break;
					case SDLK_PAGEDOWN: keys[gvPageDownKey] = YES; break;
					case SDLK_SPACE: keys[32] = YES; break;
					case SDLK_RETURN: keys[13] = YES; break;
					case SDLK_TAB: keys[9] = YES; break;
					case SDLK_UP: keys[gvArrowKeyUp] = YES; break;
					case SDLK_DOWN: keys[gvArrowKeyDown] = YES; break;
					case SDLK_LEFT: keys[gvArrowKeyLeft] = YES; break;
					case SDLK_RIGHT: keys[gvArrowKeyRight] = YES; break;

					case SDLK_KP_MINUS: keys[45] = YES; break; // numeric keypad - key
					case SDLK_KP_PLUS: keys[43] = YES; break; // numeric keypad + key
					case SDLK_KP_ENTER: keys[13] = YES; break;

					case SDLK_KP_MULTIPLY: keys[42] = YES; break;	// *

					case SDLK_KP1: keys[gvNumberPadKey1] = YES; break;
					case SDLK_KP2: keys[gvNumberPadKey2] = YES; break;
					case SDLK_KP3: keys[gvNumberPadKey3] = YES; break;
					case SDLK_KP4: keys[gvNumberPadKey4] = YES; break;
					case SDLK_KP5: keys[gvNumberPadKey5] = YES; break;
					case SDLK_KP6: keys[gvNumberPadKey6] = YES; break;
					case SDLK_KP7: keys[gvNumberPadKey7] = YES; break;
					case SDLK_KP8: keys[gvNumberPadKey8] = YES; break;
					case SDLK_KP9: keys[gvNumberPadKey9] = YES; break;
					case SDLK_KP0: keys[gvNumberPadKey0] = YES; break;

					case SDLK_F1: keys[gvFunctionKey1] = YES; break;
					case SDLK_F2: keys[gvFunctionKey2] = YES; break;
					case SDLK_F3: keys[gvFunctionKey3] = YES; break;
					case SDLK_F4: keys[gvFunctionKey4] = YES; break;
					case SDLK_F5: keys[gvFunctionKey5] = YES; break;
					case SDLK_F6: keys[gvFunctionKey6] = YES; break;
					case SDLK_F7: keys[gvFunctionKey7] = YES; break;
					case SDLK_F8: keys[gvFunctionKey8] = YES; break;
					case SDLK_F9: keys[gvFunctionKey9] = YES; break;
					case SDLK_F10: keys[gvFunctionKey10] = YES; break;

					case SDLK_BACKSPACE:
					case SDLK_DELETE:
						keys[gvDeleteKey] = YES;
						break;

					case SDLK_LSHIFT:
					case SDLK_RSHIFT:
						shift = YES;
						break;

					case SDLK_LCTRL:
					case SDLK_RCTRL:
						ctrl = YES;
						break;

					case SDLK_F12:
						[self toggleScreenMode];
							if([[PlayerEntity sharedPlayer] guiScreen]==GUI_SCREEN_GAMEOPTIONS)
							{
								//refresh play windowed / full screen
								[[PlayerEntity sharedPlayer] setGuiToGameOptionsScreen];
							}
						break;

					case SDLK_ESCAPE:
						if (shift)
						{
							SDL_FreeSurface(surface);
							[gameController exitAppWithContext:@"Shift-escape pressed"];
						}
						else
							keys[27] = YES;
						break;
					default:
						// Numerous cases not handled.
						//OOLog(@"keys.test", @"Keydown scancode: %d", kbd_event->keysym.scancode);
						;
				}
				break;

			case SDL_KEYUP:
				supressKeys = NO;    // DJS
				kbd_event = (SDL_KeyboardEvent*)&event;

#define KEYCODE_UP_BOTH(a,b)	do { \
keys[a] = NO; keys[b] = NO; \
} while (0)

#if OOLITE_WINDOWS
				/*
					Windows locale patch - Enable backslash in win/UK
				*/
				if (EXPECT_NOT(kbd_event->keysym.scancode==86 && (keyboardMap==gvKeyboardAuto || keyboardMap==gvKeyboardUK)))
				{
					//non-US scancode. If in autodetect, we'll assume UK keyboard.
					KEYCODE_UP_BOTH (124, 92); 									// 	| or \.
				}
				else switch (kbd_event->keysym.sym) {

					case SDLK_BACKSLASH:
						if (keyboardMap==gvKeyboardUK )
						{
							KEYCODE_UP_BOTH (126, 35);							// ~ or #
						}
						else if (keyboardMap==gvKeyboardAuto || keyboardMap==gvKeyboardUS)
						{
							KEYCODE_UP_BOTH (124, 92); 							// | or \.
						}
						break;
#else
				switch (kbd_event->keysym.sym) {

					case SDLK_BACKSLASH: KEYCODE_UP_BOTH (124, 92); break;		// | or \.
#endif

					case SDLK_1: KEYCODE_UP_BOTH (33, gvNumberKey1); break;		// ! and 1
#if OOLITE_WINDOWS
					/*
						Windows locale patch - fix shift-2 & shift-3
					*/
					case SDLK_2:
                        if (keyboardMap==gvKeyboardUK)
                        {
							KEYCODE_UP_BOTH (34, gvNumberKey2);				// " or 2
                        }
                        else
                        {
							KEYCODE_UP_BOTH (64, gvNumberKey2);				// @ or 2
                        }
                        break;
                    case SDLK_3:
                        if (keyboardMap==gvKeyboardUK)
                        {
							KEYCODE_UP_BOTH (156, gvNumberKey3);			// � or 3
                        }
                        else
                        {
							KEYCODE_UP_BOTH (35, gvNumberKey3);				// # or 3
                        }
                        break;
#else
					case SDLK_2: KEYCODE_UP_BOTH (64, gvNumberKey2); break;	// @ or 2
					case SDLK_3: KEYCODE_UP_BOTH (35, gvNumberKey3); break;	// # or 3
#endif
					case SDLK_4: KEYCODE_UP_BOTH (36, gvNumberKey4); break;	// $ or 4
					case SDLK_5: KEYCODE_UP_BOTH (37, gvNumberKey5); break;	// % or 5
					case SDLK_6: KEYCODE_UP_BOTH (94, gvNumberKey6); break;	// ^ or 6
					case SDLK_7: KEYCODE_UP_BOTH (38, gvNumberKey7); break;	// & or 7
					case SDLK_8: KEYCODE_UP_BOTH (42, gvNumberKey8); break;	// * or 8
					case SDLK_9: KEYCODE_UP_BOTH (40, gvNumberKey9); break;	// ( or 9
					case SDLK_0: KEYCODE_UP_BOTH (41, gvNumberKey0); break;	// ) or 0
					case SDLK_MINUS: KEYCODE_UP_BOTH (95, 45); break;		// _ and -
					case SDLK_COMMA: KEYCODE_UP_BOTH (60, 44); break;		// < and ,
					case SDLK_EQUALS: KEYCODE_UP_BOTH (43, 61); break;		// + and =
					case SDLK_PERIOD: KEYCODE_UP_BOTH (62, 46); break;		// > and .
					case SDLK_SLASH: KEYCODE_UP_BOTH (63, 47); break;		// ? and /
					case SDLK_a: KEYCODE_UP_BOTH (65, 97); break;			// A and a
					case SDLK_b: KEYCODE_UP_BOTH (66, 98); break;			// B and b
					case SDLK_c: KEYCODE_UP_BOTH (67, 99); break;			// C and c
					case SDLK_d: KEYCODE_UP_BOTH (68, 100); break;			// D and d
					case SDLK_e: KEYCODE_UP_BOTH (69, 101); break;			// E and e
					case SDLK_f: KEYCODE_UP_BOTH (70, 102); break;			// F and f
					case SDLK_g: KEYCODE_UP_BOTH (71, 103); break;			// G and g
					case SDLK_h: KEYCODE_UP_BOTH (72, 104); break;			// H and h
					case SDLK_i: KEYCODE_UP_BOTH (73, 105); break;			// I and i
					case SDLK_j: KEYCODE_UP_BOTH (74, 106); break;			// J and j
					case SDLK_k: KEYCODE_UP_BOTH (75, 107); break;			// K and k
					case SDLK_l: KEYCODE_UP_BOTH (76, 108); break;			// L and l
					case SDLK_m: KEYCODE_UP_BOTH (77, 109); break;			// M and m
					case SDLK_n: KEYCODE_UP_BOTH (78, 110); break;			// N and n
					case SDLK_o: KEYCODE_UP_BOTH (79, 111); break;			// O and o
					case SDLK_p: KEYCODE_UP_BOTH (80, 112); break;			// P and p
					case SDLK_q: KEYCODE_UP_BOTH (81, 113); break;			// Q and q
					case SDLK_r: KEYCODE_UP_BOTH (82, 114); break;			// R and r
					case SDLK_s: KEYCODE_UP_BOTH (83, 115); break;			// S and s
					case SDLK_t: KEYCODE_UP_BOTH (84, 116); break;			// T and t
					case SDLK_u: KEYCODE_UP_BOTH (85, 117); break;			// U and u
					case SDLK_v: KEYCODE_UP_BOTH (86, 118); break;			// V and v
					case SDLK_w: KEYCODE_UP_BOTH (87, 119); break;			// W and w
					case SDLK_x: KEYCODE_UP_BOTH (88, 120); break;			// X and x
					case SDLK_y: KEYCODE_UP_BOTH (89, 121); break;			// Y and y
					case SDLK_z: KEYCODE_UP_BOTH (90, 122); break;			// Z and z
					case SDLK_SEMICOLON: KEYCODE_UP_BOTH(58, 59); break; // : and ;
						//SDLK_BACKQUOTE and SDLK_HASH are special cases. No SDLK_ with code 126 exists.
					case SDLK_HASH: if (!shift) keys[126] = NO; break;		// ~ (really #)
					case SDLK_BACKQUOTE: keys[96] = NO; break;			// `
					case SDLK_QUOTE: keys[39] = NO; break;				// '
					case SDLK_LEFTBRACKET: keys[91] = NO; break;			// [
					case SDLK_RIGHTBRACKET: keys[93] = NO; break;			// ]
					case SDLK_HOME: keys[gvHomeKey] = NO; break;
					case SDLK_END: keys[gvEndKey] = NO; break;
					case SDLK_INSERT: keys[gvInsertKey] = NO; break;
					case SDLK_PAGEUP: keys[gvPageUpKey] = NO; break;
					case SDLK_PAGEDOWN: keys[gvPageDownKey] = NO; break;
					case SDLK_SPACE: keys[32] = NO; break;
					case SDLK_RETURN: keys[13] = NO; break;
					case SDLK_TAB: keys[9] = NO; break;
					case SDLK_UP: keys[gvArrowKeyUp] = NO; break;
					case SDLK_DOWN: keys[gvArrowKeyDown] = NO; break;
					case SDLK_LEFT: keys[gvArrowKeyLeft] = NO; break;
					case SDLK_RIGHT: keys[gvArrowKeyRight] = NO; break;

					case SDLK_KP_MINUS: keys[45] = NO; break; // numeric keypad - key
					case SDLK_KP_PLUS: keys[43] = NO; break; // numeric keypad + key
					case SDLK_KP_ENTER: keys[13] = NO; break;

					case SDLK_KP_MULTIPLY: keys[42] = NO; break;	// *

					case SDLK_KP1: keys[gvNumberPadKey1] = NO; break;
					case SDLK_KP2: keys[gvNumberPadKey2] = NO; break;
					case SDLK_KP3: keys[gvNumberPadKey3] = NO; break;
					case SDLK_KP4: keys[gvNumberPadKey4] = NO; break;
					case SDLK_KP5: keys[gvNumberPadKey5] = NO; break;
					case SDLK_KP6: keys[gvNumberPadKey6] = NO; break;
					case SDLK_KP7: keys[gvNumberPadKey7] = NO; break;
					case SDLK_KP8: keys[gvNumberPadKey8] = NO; break;
					case SDLK_KP9: keys[gvNumberPadKey9] = NO; break;
					case SDLK_KP0: keys[gvNumberPadKey0] = NO; break;

					case SDLK_F1: keys[gvFunctionKey1] = NO; break;
					case SDLK_F2: keys[gvFunctionKey2] = NO; break;
					case SDLK_F3: keys[gvFunctionKey3] = NO; break;
					case SDLK_F4: keys[gvFunctionKey4] = NO; break;
					case SDLK_F5: keys[gvFunctionKey5] = NO; break;
					case SDLK_F6: keys[gvFunctionKey6] = NO; break;
					case SDLK_F7: keys[gvFunctionKey7] = NO; break;
					case SDLK_F8: keys[gvFunctionKey8] = NO; break;
					case SDLK_F9: keys[gvFunctionKey9] = NO; break;
					case SDLK_F10: keys[gvFunctionKey10] = NO; break;

					case SDLK_BACKSPACE:
					case SDLK_DELETE:
						keys[gvDeleteKey] = NO;
						break;

					case SDLK_LSHIFT:
					case SDLK_RSHIFT:
						shift = NO;
						break;

					case SDLK_LCTRL:
					case SDLK_RCTRL:
						ctrl = NO;
						break;

					case SDLK_ESCAPE:
						keys[27] = NO;
						break;

					default:
						// Numerous cases not handled.
						//OOLog(@"keys.test", @"Keyup scancode: %d", kbd_event->keysym.scancode);
						;
				}
				break;

			case SDL_VIDEORESIZE:
			{
				SDL_ResizeEvent *rsevt=(SDL_ResizeEvent *)&event;
				NSSize newSize=NSMakeSize(rsevt->w, rsevt->h);
				[self initialiseGLWithSize: newSize];
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
						[self saveWindowSize: newSize];
					}
				}
#else
				[self saveWindowSize: newSize];
#endif
				break;
			}

			// caused by INTR or someone hitting close
			case SDL_QUIT:
			{
				SDL_FreeSurface(surface);
				[gameController exitAppWithContext:@"SDL_QUIT event received"];
			}
		}
	}
}


// DJS: String input handler. Since for SDL versions we're also handling
// freeform typing this has necessarily got more complex than the non-SDL
// versions.
- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event;
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
		// inputAlpha - limited input for planet find screen
		// alpha keys - either inputAlpha  or inputAll...
		if(key >= SDLK_a && key <= SDLK_z)
		{
			isAlphabetKeyDown=YES;
			// if in inputAlpha, keep in lower case.
			if(shift && allowingStringInput == gvStringInputAll)
			{
				key=toupper(key);
			}
		}

		// full input for load-save screen
		// NB: left-shift could return 0
		if (allowingStringInput == gvStringInputAll && ((key >= SDLK_0 && key <= SDLK_9) || key == SDLK_SPACE))
		{
			isAlphabetKeyDown=YES;
		}

		if(isAlphabetKeyDown)
		{
			[typedString appendFormat:@"%c", key];
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
		OOLog(@"display.mode.list.none", @"SDL didn't return any screen modes");
		return;
	}

	if(modes == (SDL_Rect **)-1)
	{
		OOLog(@"display.mode.list.none", @"SDL claims 'all resolutions available' which is unhelpful in the extreme");
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
			[screenSizes addObject: mode];
			OOLog(@"display.mode.list", @"Added res %d x %d", modes[i]->w, modes[i]->h);
			lastw=modes[i]->w;
			lasth=modes[i]->h;
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
		windowSize=NSMakeSize(800, 600);
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

	// Check if -fullscreen has been passed on the command line. If yes, set it regardless of
	// what is set by .GNUstepDefaults.
   	for (i = 0; i < [cmdline_arguments count]; i++)
   	{
   		if ([[cmdline_arguments objectAtIndex:i] isEqual:@"-fullscreen"]) fullScreen = YES;
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
	OOLog(@"display.mode.unknown", @"Screen size unknown!");
	return NSMakeSize(800, 600);
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
}


- (float) gammaValue
{
	return _gamma;
}


+ (BOOL)pollShiftKey
{
#if OOLITE_WINDOWS
	// SDL_GetModState() does not seem to do exactly what is intended under Windows. For this reason,
	// the GetKeyState Windows API call is used to detect the Shift keypress. -- Nikos.

	return 0 != (GetKeyState(VK_SHIFT) & 0x100);

#else
	return 0 != (SDL_GetModState() & (KMOD_LSHIFT | KMOD_RSHIFT));

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
