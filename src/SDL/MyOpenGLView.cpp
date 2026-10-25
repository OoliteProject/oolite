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
#include <SDL3/SDL_timer.h>
#include "png.h"
#include "MyOpenGLView.h"
#include "oofnd/Process.hpp"

#include "GameController.h"
#include "Universe.h"
#include "OOSDLJoystickManager.h"
#include "OOSound.h"
#include "PlayerEntity.h"
#include "GuiDisplayGen.h"
#include "OOStellarBody.h"
#include "OOGraphicsResetManager.h"
#include "OOFullScreenController.h"
#include "ResourceManager.h"
#include "OOConstToString.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"
#include "oofnd/ResourcePaths.hpp"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

// The save and snapshot directory names (moved here when the NSFileManager category header retired, bead oo-pwz0).
#define SAVEDIR "oolite-saves"
#define SNAPSHOTDIR "snapshots"

extern "C" int SaveEXRSnapshot(const char* outfilename, int width, int height, const float* rgb);


#include <ctype.h>
#include "oofnd/Date.hpp"

#if OOLITE_WINDOWS
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE	20
#endif
extern "C" HRESULT WINAPI DwmSetWindowAttribute (HWND hwnd, DWORD dwAttribute, LPCVOID pvAttribute, DWORD cbAttribute);

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


namespace {

// oo_stringForKey:defaultValue: over the user defaults: the value if it is a string, a number's
// -stringValue, else the fallback.
std::string DefaultsString(const char *key, const std::string &fallback)
{
	const oo::PList value = oo::Defaults::standard().object(key);
	return oo::PListGet<std::string>::from(value.isNull() ? nullptr : &value, fallback);
}


// A dictionary's -isEqual: over two mode dictionaries: the same keys, numbers equal by value (the
// native mode's integer RefreshRate 0 equals a mode's single-real 0).
bool SameMode(const oo::PList &a, const oo::PList &b)
{
	const oo::PList::Dict *da = a.getIf<oo::PList::Dict>();
	const oo::PList::Dict *db = b.getIf<oo::PList::Dict>();
	if (da == nullptr || db == nullptr || da->size() != db->size())  return false;
	for (const auto &[key, value] : *da)
	{
		const auto other = db->find(key);
		if (other == db->end() || !value.isNumber() || !other->second.isNumber())  return false;
		if (value.doubleValue() != other->second.doubleValue())  return false;
	}
	return true;
}

} // namespace

SDL_DisplayID MyOpenGLView::getDisplayId()
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
			OO_LOG("sdl.display_id", "Could not get list of displays. Error was: {}", SDL_GetError());
		}
		SDL_free(displayIds);
	}
	return displayId;
}

oo::PList MyOpenGLView::getNativeSize()
{
	oo::PList::Dict mode;
	int nativeDisplayWidth = 1024;
	int nativeDisplayHeight = 768;

	SDL_DisplayID displayId = getDisplayId();
	SDL_Rect boundsRect;
	if (displayId && SDL_GetDisplayUsableBounds(displayId, &boundsRect))
	{
		nativeDisplayWidth = boundsRect.w;
		nativeDisplayHeight = boundsRect.h;
		OO_LOG("display.mode.list.native", "Native display resolution detected: {} x {}", static_cast<int>(nativeDisplayWidth), static_cast<int>(nativeDisplayHeight));
	}
	else
	{
		OO_LOG("display.mode.list.native.failed", "{}", "SDL_GetWMInfo failed, defaulting to 1024x768 for native size");
	}

	mode[std::string(kOODisplayWidth)] = oo::PList(std::int64_t(nativeDisplayWidth));
	mode[std::string(kOODisplayHeight)] = oo::PList(std::int64_t(nativeDisplayHeight));
	mode[std::string(kOODisplayRefreshRate)] = oo::PList(std::int64_t(0));

	return oo::PList(std::move(mode));
}

std::optional<std::string> MyOpenGLView::getWindowCaption()
{
	return oo::str::format("Oolite v%s by %s - %s", OO_VERSION_FULL, OO_BUILDER, OO_BUILD_DATE);
}

void MyOpenGLView::createWindowWithSize(NSSize size)
{
	Uint32          colorkey;
	SDL_Surface     *icon=NULL;
	std::string		imagesDir;

	oo::Defaults &prefs = oo::Defaults::standard();

	OO_LOG("display.initGL", "Trying {}-bpcc, 24-bit depth buffer", static_cast<int>(bitsPerColorComponent));
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

	const oo::PList antiAliasing = prefs.object("anti-aliasing");
	if (oo::PListGet<bool>::from(antiAliasing.isNull() ? nullptr : &antiAliasing, false))
	{
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4);
	}

	const std::string windowCaption = getWindowCaption().value_or(std::string());
	Uint32 windowFlags = SDL_WINDOW_OPENGL | SDL_WINDOW_BORDERLESS | SDL_WINDOW_HIGH_PIXEL_DENSITY;

	// Define modern SDL3 properties for window configuration
	SDL_PropertiesID props = SDL_CreateProperties();
	SDL_SetStringProperty(props, SDL_PROP_WINDOW_CREATE_TITLE_STRING, windowCaption.c_str());
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, size.width);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, size.height);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, windowFlags);

	// Explicit centering properties setup for SDL3
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_X_NUMBER, SDL_WINDOWPOS_CENTERED);
	SDL_SetNumberProperty(props, SDL_PROP_WINDOW_CREATE_Y_NUMBER, SDL_WINDOWPOS_CENTERED);

	window = SDL_CreateWindowWithProperties(props);
	if (!window)
	{
		OO_LOG("display.initGL", "{}", "Trying 8-bpcc, 24-bit depth buffer");
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
		OO_LOG("display.initGL", "{}", "Trying 5-bpcc, 16-bit depth buffer");
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
		OO_LOG_ERR("display.mode.error", "Could not create window: {}", errStr);
		exit(1);
	}
	glContext = SDL_GL_CreateContext(window);
	if (!glContext)
	{
		OO_LOG("sdl.create_context", "{}", "Could not create OpenGL context");
		exit(1);
	}
	SDL_Surface *surface = SDL_GetWindowSurface(window);
	if (!SDL_SetSurfaceColorspace(surface, SDL_COLORSPACE_SRGB_LINEAR))
	{
		OO_LOG_WARN("sdl.use_edr_surface", "{} {}", "Failed to set SDR linear surface - falling back to SDR. Error was:", SDL_GetError());
		SDL_SetSurfaceColorspace(surface, SDL_COLORSPACE_SRGB);
	}

#if OOLITE_WINDOWS
	//capture the window handle for later
	SDL_PropertiesID windowPropertiesId = SDL_GetWindowProperties(window);
	windowHandle = (HWND)SDL_GetPointerProperty(windowPropertiesId, SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
	if (!windowHandle)
	{
		OO_LOG("sdl.window_handle", "{}", "Failed to retrieve window handle");
		exit(1);
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
	refreshDarKOrLightMode();
#endif
#endif //OOLITE_WINDOWS

	imagesDir = oo::fs::utf8String(oo::ResourcePaths::current().builtInResourcesDirectory() / "Images");
	icon = SDL_LoadBMP(oo::str::appendingPathComponent(imagesDir, "WMicon.bmp").c_str());

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
	const oo::PList hdrMaxBrightness = prefs.object("hdr-max-brightness");
	_hdrMaxBrightness = oo::PListGet<float>::from(hdrMaxBrightness.isNull() ? nullptr : &hdrMaxBrightness, 1000.0f);
	const oo::PList hdrPaperWhiteBrightness = prefs.object("hdr-paperwhite-brightness");
	_hdrPaperWhiteBrightness = oo::PListGet<float>::from(hdrPaperWhiteBrightness.isNull() ? nullptr : &hdrPaperWhiteBrightness, 200.0f);
	_hdrToneMapper = cxx_OOHDRToneMapperFromString(DefaultsString("hdr-tone-mapper", "OOHDR_TONEMAPPER_ACES_APPROX"));
#endif

	_sdrToneMapper = cxx_OOSDRToneMapperFromString(DefaultsString("sdr-tone-mapper", "OOSDR_TONEMAPPER_ACES"));

	SDL_SetWindowSurfaceVSync(window, vSyncPreference);
	OO_LOG("display.initGL", "V-Sync {}requested.", vSyncPreference ? "" : "not ");

	int testAttrib = -1;
	OO_LOG("display.initGL", "{}", "Achieved color / depth buffer sizes (bits):");
	SDL_GL_GetAttribute(SDL_GL_RED_SIZE, &testAttrib);
	OO_LOG("display.initGL", "Red: {}", static_cast<int>(testAttrib));
	SDL_GL_GetAttribute(SDL_GL_GREEN_SIZE, &testAttrib);
	OO_LOG("display.initGL", "Green: {}", static_cast<int>(testAttrib));
	SDL_GL_GetAttribute(SDL_GL_BLUE_SIZE, &testAttrib);
	OO_LOG("display.initGL", "Blue: {}", static_cast<int>(testAttrib));
	SDL_GL_GetAttribute(SDL_GL_ALPHA_SIZE, &testAttrib);
	OO_LOG("display.initGL", "Alpha: {}", static_cast<int>(testAttrib));
	SDL_GL_GetAttribute(SDL_GL_DEPTH_SIZE, &testAttrib);
	OO_LOG("display.initGL", "Depth Buffer: {}", static_cast<int>(testAttrib));

	SDL_GL_GetAttribute(SDL_GL_FLOATBUFFERS, &testAttrib);
	OO_LOG("display.initGL", "Pixel type is float : {}", static_cast<int>(testAttrib));

	SDL_PixelFormat format = SDL_GetWindowPixelFormat(window);
	OO_LOG("display.initGL", "Window Pixel Format: {}", SDL_GetPixelFormatName(format));

	// Verify V-sync successfully set - report it if not

	int hasVsync;
	if (vSyncPreference && (!SDL_GetWindowSurfaceVSync(window, &hasVsync) || !hasVsync))
	{
		OO_LOG_WARN("display.initGL", "Could not enable V-Sync. Please check that your graphics driver supports the {}_swap_control extension.", OOLITE_WINDOWS ? "WGL_EXT" : "[GLX_SGI/GLX_MESA]");
	}
	else
	{
		OO_LOG("display.initGL", "{}", "V-Sync set");
	}

	int width, height;
	SDL_GetWindowSizeInPixels(window, &width, &height);
	bounds.size.width = width;
	bounds.size.height = height;

	return;
}

bool MyOpenGLView::init()
{
 	std::string		cmdLineArgsStr = "Startup command: ";

	// SDL splash screen  settings

	oo::Defaults &prefs = oo::Defaults::standard();
	const oo::PList splashScreen = prefs.object("splash-screen");
	showSplashScreen = oo::PListGet<bool>::from(splashScreen.isNull() ? nullptr : &splashScreen, true) ? YES : NO;
	const oo::PList vSync = prefs.object("v-sync");
	vSyncPreference = oo::PListGet<bool>::from(vSync.isNull() ? nullptr : &vSync, true) ? YES : NO;
	const oo::PList hdr = prefs.object("hdr");
	bitsPerColorComponent = oo::PListGet<bool>::from(hdr.isNull() ? nullptr : &hdr, false) ? 16 : 8;

	BOOL				noSplashArgFound = NO;

	initKeyMappingData();

	// preload the printscreen key into our translation array because SDLK_PRINTSCREEN isn't available
	scancode2Unicode[55] = gvPrintScreenKey;

	// scan for splash screen overrides: -nosplash || --nosplash , -splash || --splash
	// scan for V-sync disabling overrides: -novsync || --novsync
	for (const std::string &argument : oo::process::arguments())
	{
		const std::string &arg = argument;
		if (arg == "-nosplash" || arg == "--nosplash")
		{
			showSplashScreen = NO;
			noSplashArgFound = YES;	// -nosplash always trumps -splash
		}
		else if ((arg == "-splash" || arg == "--splash") && !noSplashArgFound)
		{
			showSplashScreen = YES;
		}

		// if V-sync is disabled at the command line, override the defaults file
		if (arg == "-novsync" || arg == "--novsync")  vSyncPreference = NO;

		if (arg == "-hdr")  bitsPerColorComponent = 16;

  		// build the startup command string so that we can log it
		cmdLineArgsStr += arg + " ";
	}

 	OO_LOG("process.args", "{}", cmdLineArgsStr);

#if OOLITE_SPEECH_SYNTH
#if OOLITE_ESPEAK
	if (!SDL_getenv("ESPEAK_DATA_PATH"))
	{
		espeak_Initialize(AUDIO_OUTPUT_PLAYBACK, 100, ResourceManager::builtInPath().value_or(std::string()).c_str(), 0);
	}
	else
	{
		espeak_Initialize(AUDIO_OUTPUT_PLAYBACK, 100, NULL, 0);
	}
#endif
#endif

	matrixManager = oo::makeRef<OOOpenGLMatrixManager>();

	// TODO: This code up to and including stickHandler really ought
	// not to be in this class.
	OO_LOG("sdl.init", "{}", "initialising SDL");
	if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_JOYSTICK | SDL_INIT_GAMEPAD))
	{
		OO_LOG("sdl.init.failed", "Unable to init SDL: {}\n", SDL_GetError());
		return false;	// the maker releases the view (as -init released itself): -dealloc's body is the destructor
	}

	populateFullScreenModelist();

	// Find what the full screen and windowed settings are.
	fullScreen = NO;
	currentSize = 0;
	loadWindowSize();
	loadFullscreenSettings();

	// Set up the drawing surface's dimensions.
	firstScreen = (fullScreen) ? modeAsSize(currentSize) : currentWindowSize;
	viewSize = firstScreen;	// viewSize must be set prior to splash screen initialization

	OOJoystickManager::setStickHandlerFactory([]() -> oo::Ref<OOJoystickManager> { return oo::makeRef<OOSDLJoystickManager>(); });	// was +setStickHandlerClass:
	// end TODO

	OOSound::setUp();
	if (!OOSound::isSoundOK())  OO_LOG("sound.init", "{}", "Sound system disabled.");

	grabMouseStatus = NO;

	OO_LOG("display.mode.list", "{}", "CREATING MODE LIST");

	if (!showSplashScreen)
	{
		// blank the surface / go to fullscreen
		initialiseGLWithSize(firstScreen);
	}

	autoShowMouse();

	virtualJoystickPosition = NSMakePoint(0.0,0.0);
	mouseWarped = NO;

	const oo::PList mouseFlightSensitivity = prefs.object("mouse-flight-sensitivity");
	_mouseVirtualStickSensitivityFactor = OOClamp_0_1_f(oo::PListGet<float>::from(mouseFlightSensitivity.isNull() ? nullptr : &mouseFlightSensitivity, 0.95f));
	// ensure no chance of a divide by zero later on
	if (_mouseVirtualStickSensitivityFactor < 0.005f)  _mouseVirtualStickSensitivityFactor = 0.005f;

	allowingStringInput = gvStringInputNo;
	isAlphabetKeyDown = NO;

	timeIntervalAtLastClick = (NSTimeInterval)SDL_GetTicksNS() / 1e9;	// the clock SDL stamps events on (MyOpenGLView+Input.mm)
	timeSinceLastMouseWheel = oo::date::monotonicSeconds();	// intervals only (MyOpenGLView+Input.mm)

	_mouseWheelDelta = 0.0f;

	return true;
}

void MyOpenGLView::endSplashScreen()
{
#if OOLITE_WINDOWS
	// we need to get through here even if splash screen has not
	// been shown - this method also prepares the main game window
	if (hdrOutput() && !isOutputDisplayHDREnabled())
	{
		if (MessageBox(NULL,	"No primary display in HDR mode was detected.\n\n"
							"If you continue, graphics will not be rendered as intended.\n"
							"Click OK to launch anyway, or Cancel to exit.", "oolite.exe - HDR requested",
							MB_OKCANCEL | MB_ICONWARNING) == IDCANCEL)
		{
			if (gameController != nullptr)  gameController->exitAppWithContext("Cancel selected on no-HDR confirmation dialog");
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
		OO_LOG("display.splash", "Suppressed splash-screen event {}: {} ", static_cast<int>(numEvents), static_cast<int>(dummyEvent.type));
		*/
	}

	initialiseGLWithSize(firstScreen);
	updateScreen();
	autoShowMouse();
}

void MyOpenGLView::updateGLSize(NSSize size)
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

void MyOpenGLView::setUpBasicOpenGLStateWithSize()
{
	OOOpenGLExtensionManager *extMgr = OOOpenGLExtensionManager::sharedManager();

	OOGL(glClearColor(0.0, 0.0, 0.0, 0.0));
	OOGL(glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT));
	OOGL(glClearDepth(1.0));
	OOGL(glDepthFunc(GL_LESS));	// depth buffer

	if (UNIVERSE)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->setLighting();
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

	if (extMgr->usePointSmoothing())
	{
		OOGL(glEnable(GL_POINT_SMOOTH));
	}

	if (extMgr->useLineSmoothing())
	{
		OOGL(glEnable(GL_LINE_SMOOTH));
	}

	OOGL(glDisable(GL_NORMALIZE));
	OOGL(glDisable(GL_RESCALE_NORMAL));

	OOGL(glLightModeli(GL_LIGHT_MODEL_COLOR_CONTROL, GL_SEPARATE_SPECULAR_COLOR));
}

void MyOpenGLView::initialiseGLWithSize(NSSize v_size)
{
	if (!window)
	{
		createWindowWithSize(v_size);
	}

	viewSize = v_size;

	OO_LOG("display.initGL", "Requested a new surface of {} x {}, {}.", static_cast<int>((int)viewSize.width), static_cast<int>((int)viewSize.height), std::string((fullScreen ? "fullscreen" : "windowed")));

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

	updateGLSize(NSMakeSize(pixelWidth, pixelHeight));

	OO_LOG("display.initGL", "Created a new surface of {} x {}, {}.", static_cast<int>((int)viewSize.width), static_cast<int>((int)viewSize.height), std::string((fullScreen ? "fullscreen" : "windowed")));

	autoShowMouse();

	setUpBasicOpenGLStateWithSize();

	SDL_GL_SwapWindow(window);

	squareX = 0.0f;
}

MyOpenGLView::~MyOpenGLView()
{
	if (window)
	{
		SDL_DestroyWindow(window);
	}

	if (glContext)
	{
		SDL_GL_DestroyContext(glContext);
	}

	SDL_Quit();

	// matrixManager is released with the members, after SDL_Quit() as before.
}

void MyOpenGLView::updateScreen()
{
	if (UNIVERSE)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->drawUniverse();  // do all the drawing!
	}
	else
	{
		glClearColor( 0.0, 0.0, 0.0, 0.0);  // not set up yet, draw a black screen
		glClear( GL_COLOR_BUFFER_BIT);
	}

	SDL_GL_SwapWindow(window);
}

void MyOpenGLView::initSplashScreen()
{
	if (!showSplashScreen) return;

	//too early for OOTexture!
	SDL_Surface     	*image=NULL;
	SDL_Rect			dest;

	const std::string	imagesDir = oo::str::appendingPathComponent(ResourceManager::builtInPath().value_or(std::string()), "Images");

	image = SDL_LoadBMP(oo::str::appendingPathComponent(imagesDir, "splash.bmp").c_str());

	if (image == NULL)
	{
		SDL_DestroySurface(image);
		OO_LOG_WARN("sdl.gameStart", "{}", "image 'splash.bmp' not found!");
		endSplashScreen();
		return;
	}

	dest.x = 0;
	dest.y = 0;
	dest.w = image->w;
	dest.h = image->h;

	createWindowWithSize(NSMakeSize(image->w, image->h));
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

	matrixManager->resetProjection();
	matrixManager->orthoLeft(0.0f, 1.0f, 1.0f, 0.0f, -1.0f, 1.0f);
	matrixManager->syncProjection();

	matrixManager->resetModelView();
	matrixManager->syncModelView();

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
		OO_LOG("Sdl.GameStart", "{}", "----- Encoding error within image 'splash.bmp'");
		endSplashScreen();
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
	matrixManager->resetModelView();
	matrixManager->syncModelView();

	if ( image ) {
		SDL_DestroySurface( image );
	}
	glDeleteTextures(1, &texture);

	glDisable( GL_TEXTURE_2D );
	OOVerifyOpenGLState();

	SDL_DestroySurface(image);
	return;
}


// Slice 2 of docs/phases/3-slices/MyOpenGLView.md (bead oo-72cz): accessors, display modes, settings,
// display / HDR, FOV and MSAA.

NSRect MyOpenGLView::getBounds()
{
	return bounds;
}


NSSize MyOpenGLView::getViewSize()
{
	return viewSize;
}


NSSize MyOpenGLView::backingViewSize()
{
	return bounds.size;
}


GLfloat MyOpenGLView::getDisplay_z()
{
	return display_z;
}


GLfloat MyOpenGLView::getX_offset()
{
	return x_offset;
}


GLfloat MyOpenGLView::getY_offset()
{
	return y_offset;
}


::GameController *MyOpenGLView::getGameController()
{
	return gameController;
}


void MyOpenGLView::setGameController(::GameController *controller)
{
	gameController = controller;
}


bool MyOpenGLView::inFullScreenMode()
{
	return fullScreen;
}

#ifdef GNUSTEP_BASE_LIBRARY
void MyOpenGLView::setFullScreenMode(bool fsm)
{
	fullScreen = fsm;

	// Save the settings for later.
	oo::Defaults::standard().setBool("fullscreen", fullScreen);
	oo::Defaults::standard().synchronize();
}


void MyOpenGLView::toggleScreenMode()
{
	setFullScreenMode(!fullScreen);
 	if(fullScreen)
	{
 		initialiseGLWithSize(modeAsSize(currentSize));
	}
	else
	{
		initialiseGLWithSize(currentWindowSize);
#if OOLITE_LINUX
		SDL_HideWindow(window);
    	SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
		SDL_ShowWindow(window);
#endif
	}
}


void MyOpenGLView::setDisplayMode(int mode, bool fsm)
{
	setFullScreenMode(fsm);
	currentSize=mode;
	if(fullScreen)
		initialiseGLWithSize(modeAsSize(mode));
}


void MyOpenGLView::setScreenSize(int sizeIndex)
{
	currentSize=sizeIndex;
	if(fullScreen)
		initialiseGLWithSize(modeAsSize(currentSize));
}


std::vector<oo::PList> MyOpenGLView::getScreenSizeArray()
{
	return screenSizes;
}


NSSize MyOpenGLView::modeAsSize(int sizeIndex)
{
	const oo::PList &mode = screenSizes.at(sizeIndex);
	return NSMakeSize(mode.get<int>(std::string(kOODisplayWidth)),
        		mode.get<int>(std::string(kOODisplayHeight)));
}

#endif




#if OOLITE_WINDOWS
void MyOpenGLView::getDisplayDimensions(unsigned *width, unsigned *height)
{
	SDL_DisplayID displayID = SDL_GetDisplayForWindow(window);

	SDL_Rect displaybounds;
	if (SDL_GetDisplayBounds(displayID, &displaybounds)) {
		if (width)  *width  = (unsigned)displaybounds.w;
		if (height) *height = (unsigned)displaybounds.h;
	}
}

bool MyOpenGLView::isRunningOnPrimaryDisplayDevice()
{
	if (!window) {
		return NO;
    }

	SDL_DisplayID windowDisplayID = SDL_GetDisplayForWindow(window);
	SDL_DisplayID primaryDisplayID = SDL_GetPrimaryDisplay();

	return (windowDisplayID != 0 && windowDisplayID == primaryDisplayID);
}

void MyOpenGLView::grabMouseInsideGameWindow(bool value)
{
	SDL_SetWindowMouseGrab(window, value);
	grabMouseStatus = value;
}


void MyOpenGLView::stringToClipboard(const std::string &stringToCopy)
{
	{
		const char *clipboardText = stringToCopy.c_str();
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
				OO_LOG("stringToClipboard.failed", "Failed to copy string {} to clipboard", stringToCopy);
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


void MyOpenGLView::refreshDarKOrLightMode()
{
	int shouldSetDarkMode = isDarkModeOn();
	DwmSetWindowAttribute (windowHandle, DWMWA_USE_IMMERSIVE_DARK_MODE, &shouldSetDarkMode, sizeof(shouldSetDarkMode));
}


bool MyOpenGLView::isDarkModeOn()
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


bool MyOpenGLView::getAtDesktopResolution()
{
	return atDesktopResolution;
}


bool MyOpenGLView::hdrOutput()
{
	return _hdrOutput;
}


bool MyOpenGLView::isOutputDisplayHDREnabled()
{
	BOOL result = NO;
	SDL_DisplayID displayID = SDL_GetPrimaryDisplay();  // Get the primary display ID
	if (displayID == 0)
	{
		OO_LOG("gameView.isOutputDisplayHDREnabled", "Error! Failed to retrieve primary display ID: {}", SDL_GetError());
		return NO;
	}
	SDL_PropertiesID props = SDL_GetDisplayProperties(displayID);  // Retrieve properties for the target display
	if (props == 0)
	{
		OO_LOG("gameView.isOutputDisplayHDREnabled", "Error! Failed to get display properties: {}", SDL_GetError());
		return NO;
	}
	result = SDL_GetBooleanProperty(props, SDL_PROP_DISPLAY_HDR_ENABLED_BOOLEAN, false);  // Query for HDR enabling
	OO_LOG("gameView.isOutputDisplayHDREnabled", "HDR display output requested - checking availability: {}", result ? "YES" : "NO");
	return result;
}


float MyOpenGLView::hdrMaxBrightness()
{
	return _hdrMaxBrightness;
}


void MyOpenGLView::setHDRMaxBrightness(float newMaxBrightness)
{
	if (newMaxBrightness < MIN_HDR_MAXBRIGHTNESS)  newMaxBrightness = MIN_HDR_MAXBRIGHTNESS;
	if (newMaxBrightness > MAX_HDR_MAXBRIGHTNESS)  newMaxBrightness = MAX_HDR_MAXBRIGHTNESS;
	_hdrMaxBrightness = newMaxBrightness;
	
	oo::Defaults::standard().setFloat("hdr-max-brightness", _hdrMaxBrightness);
}


float MyOpenGLView::hdrPaperWhiteBrightness()
{
	return _hdrPaperWhiteBrightness;
}


void MyOpenGLView::setHDRPaperWhiteBrightness(float newPaperWhiteBrightness)
{
	if (newPaperWhiteBrightness < MIN_HDR_PAPERWHITE)  newPaperWhiteBrightness = MIN_HDR_PAPERWHITE;
	if (newPaperWhiteBrightness > MAX_HDR_PAPERWHITE)  newPaperWhiteBrightness = MAX_HDR_PAPERWHITE;
	_hdrPaperWhiteBrightness = newPaperWhiteBrightness;
	
	oo::Defaults::standard().setFloat("hdr-paperwhite-brightness", _hdrPaperWhiteBrightness);
}


OOHDRToneMapper MyOpenGLView::hdrToneMapper()
{
	return (OOHDRToneMapper)_hdrToneMapper;
}


void MyOpenGLView::setHDRToneMapper(OOHDRToneMapper newToneMapper)
{
	if (newToneMapper > OOHDR_TONEMAPPER_REINHARD)  newToneMapper = OOHDR_TONEMAPPER_REINHARD;
	if (newToneMapper < OOHDR_TONEMAPPER_NONE)  newToneMapper = OOHDR_TONEMAPPER_NONE;
	_hdrToneMapper = newToneMapper;
}


#else	// Linus stub methods

// for Linux we assume we are always on the primary monitor for now
bool MyOpenGLView::isRunningOnPrimaryDisplayDevice()
{
	return YES;
}


void MyOpenGLView::grabMouseInsideGameWindow(bool value)
{
	// do nothing
}


void MyOpenGLView::stringToClipboard(const std::string &stringToCopy)
{
	// TODO: implement string clipboard copy for Linux
}


bool MyOpenGLView::hdrOutput()
{
	return NO;
}


bool MyOpenGLView::isOutputDisplayHDREnabled()
{
	return NO;
}

#endif //OOLITE_WINDOWS


OOSDRToneMapper MyOpenGLView::sdrToneMapper()
{
	return (OOSDRToneMapper)_sdrToneMapper;
}


void MyOpenGLView::setSDRToneMapper(OOSDRToneMapper newToneMapper)
{
	if (newToneMapper > OOSDR_TONEMAPPER_REINHARD)  newToneMapper = OOSDR_TONEMAPPER_REINHARD;
	if (newToneMapper < OOSDR_TONEMAPPER_NONE)  newToneMapper = OOSDR_TONEMAPPER_NONE;
	_sdrToneMapper = newToneMapper;
}


float MyOpenGLView::colorSaturation()
{
	return _colorSaturation;
}


void MyOpenGLView::adjustColorSaturation(float colorSaturationAdjustment)
{
	_colorSaturation += colorSaturationAdjustment;
	_colorSaturation = OOClamp_0_max_f(_colorSaturation, MAX_COLOR_SATURATION);
}


// Full screen mode enumerator.
void MyOpenGLView::populateFullScreenModelist()
{
	int i;
	SDL_DisplayMode **modes;
	SDL_DisplayID displayId = getDisplayId();

	screenSizes.clear();

	// The default resolution (slot 0) is the resolution we are
	// already in since this is guaranteed to work.
	screenSizes.push_back(getNativeSize());

	int displayModeCount;
	modes = SDL_GetFullscreenDisplayModes(displayId, &displayModeCount);
	if(!displayModeCount)
	{
		OO_LOG("display.mode.list.none", "{}", "SDL didn't return any screen modes");
		return;
	}

	for(i=0; i < displayModeCount; i++)
	{
		oo::PList::Dict modeDict;
		modeDict[std::string(kOODisplayWidth)] = oo::PList(std::int64_t((int)modes[i]->w));
		modeDict[std::string(kOODisplayHeight)] = oo::PList(std::int64_t((int)modes[i]->h));
		modeDict[std::string(kOODisplayRefreshRate)] = oo::PList::singleReal((float)(int)modes[i]->refresh_rate);	// +numberWithFloat:
		const oo::PList mode(std::move(modeDict));
		if (std::find_if(screenSizes.begin(), screenSizes.end(), [&](const oo::PList &m) { return SameMode(m, mode); }) == screenSizes.end())
		{
			screenSizes.push_back(mode);
			OO_LOG("display.mode.list", "Added res {} x {}", static_cast<int>(modes[i]->w), static_cast<int>(modes[i]->h));
		}
	}
	SDL_free(modes);
}


// Save and restore window sizes to/from defaults.
void MyOpenGLView::saveWindowSize(NSSize windowSize)
{
	oo::Defaults &defaults = oo::Defaults::standard();
	defaults.setInteger("window_width", (int)windowSize.width);
	defaults.setInteger("window_height", (int)windowSize.height);
	currentWindowSize=windowSize;
}


NSSize MyOpenGLView::loadWindowSize()
{
	NSSize windowSize;
	oo::Defaults &defaults = oo::Defaults::standard();
	if(!defaults.object("window_width").isNull() && !defaults.object("window_height").isNull())
	{
		windowSize=NSMakeSize(defaults.integerForKey("window_width"),
					defaults.integerForKey("window_height"));
	}
	else
	{
		windowSize=NSMakeSize(WINDOW_SIZE_DEFAULT_WIDTH, WINDOW_SIZE_DEFAULT_HEIGHT);
	}
	currentWindowSize=windowSize;
	return windowSize;
}


int MyOpenGLView::loadFullscreenSettings()
{
	currentSize=0;
	int width=0, height=0, refresh=0;
	unsigned i;

	const std::vector<std::string> &cmdline_arguments = oo::process::arguments();

	oo::Defaults &userDefaults = oo::Defaults::standard();
	if (!userDefaults.object("display_width").isNull())
		width = (int)userDefaults.integerForKey("display_width");
	if (!userDefaults.object("display_height").isNull())
		height = (int)userDefaults.integerForKey("display_height");
	if (!userDefaults.object("display_refresh").isNull())
		refresh = (int)userDefaults.integerForKey("display_refresh");
	if(!userDefaults.object("fullscreen").isNull())
		fullScreen=userDefaults.boolForKey("fullscreen") ? YES : NO;

	// Check if -fullscreen or -windowed has been passed on the command line. If yes,
	// set it regardless of what is set by .GNUstepDefaults. If both are found in the
	// arguments list, the one that comes last wins.
	for (i = 0; i < cmdline_arguments.size(); i++)
	{
		if (cmdline_arguments[i] == "-fullscreen") fullScreen = YES;
		if (cmdline_arguments[i] == "-windowed") fullScreen = NO;
	}
	
   	if(width && height)
   	{
      		currentSize=indexOfDisplayModeForWidth(width, height, refresh);
      		return currentSize;
   	}
   	return currentSize;
}


int MyOpenGLView::indexOfDisplayModeForWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh)
{
	int i, modeCount;
	unsigned int modeWidth, modeHeight, modeRefresh;

	modeCount = (int)screenSizes.size();

	for (i = 0; i < modeCount; i++)
	{
		const oo::PList &mode = screenSizes[i];
		modeWidth = mode.get<int>(std::string(kOODisplayWidth));
		modeHeight = mode.get<int>(std::string(kOODisplayHeight));
		modeRefresh = mode.get<int>(std::string(kOODisplayRefreshRate));
		if ((modeWidth == d_width)&&(modeHeight == d_height)&&(modeRefresh == d_refresh))
		{
			OO_LOG("display.mode.found", "Found mode {}", oo::DescriptionOf(mode));
			return i;
		}
	}

	OO_LOG("display.mode.found.failed", "Failed to find mode: width={} height={} refresh={}", static_cast<int>(d_width), static_cast<int>(d_height), static_cast<int>(d_refresh));
	OO_LOG("display.mode.found.failed.list", "Contents of list: {}", oo::DescriptionOf(oo::PList(oo::PList::Array(screenSizes))));
	return 0;
}


NSSize MyOpenGLView::currentScreenSize()
{
	const oo::PList &mode = screenSizes.at(currentSize);

	if(mode)
	{
		return NSMakeSize(mode.get<int>(std::string(kOODisplayWidth)),
				mode.get<int>(std::string(kOODisplayHeight)));
	}
	OO_LOG("display.mode.unknown", "{}", "Screen size unknown!");
	return NSMakeSize(WINDOW_SIZE_DEFAULT_WIDTH, WINDOW_SIZE_DEFAULT_HEIGHT);
}

oo::PList MyOpenGLView::currentScreenMode()
{
	return screenSizes.at(currentSize);
}



void MyOpenGLView::setFov(float value, bool fromFraction)
{
	_fov = fromFraction ? value : tan((value / 2) * M_PI / 180);
}


float MyOpenGLView::fov(bool inFraction)
{
	return inFraction ? _fov : 2 * atan(_fov) * 180 / M_PI;
}


bool MyOpenGLView::msaa()
{
	return _msaa;
}


void MyOpenGLView::setMsaa(bool newMsaa)
{
	_msaa = !!newMsaa;
}


OOOpenGLMatrixManager *MyOpenGLView::getOpenGLMatrixManager()
{
	return matrixManager.get();	// borrowed
}


bool MyOpenGLView::pollShiftKey()
{
#if !OOLITE_WINDOWS
	return 0 != (SDL_GetModState() & (SDL_KMOD_LSHIFT | SDL_KMOD_RSHIFT));
#else
	// SDL_GetModState() does not seem to do exactly what is intended under Windows. For this reason,
	// the GetKeyState Windows API call is used to detect the Shift keypress. -- Nikos.
	return 0 != (GetKeyState(VK_SHIFT) & 0x100);
#endif
}


// Slice 3 of docs/phases/3-slices/MyOpenGLView.md (bead oo-299r): snapshots and debug image dumps.

bool MyOpenGLView::snapShot(const std::optional<std::string> &filename)
{
	BOOL snapShotOK = YES;
	SDL_Surface* tmpSurface;

	// backup the previous directory
	const auto originalDirectory = oo::fs::currentDirectory();
	// use the snapshots directory (mkdir + chdir of ResourcePaths::snapshotDirectory)
	{
		const oo::fs::Path snapshotDir = oo::ResourcePaths::current().snapshotDirectory();
		if (!oo::fs::setCurrentDirectory(snapshotDir))
		{
			if (!oo::fs::createDirectories(snapshotDir))
			{
				OO_LOG("savedSnapshot.defaultPath.create.failed", "Unable to create directory {}", oo::fs::utf8String(snapshotDir));
			}
			else if (!oo::fs::setCurrentDirectory(snapshotDir))
			{
				OO_LOG("savedSnapshot.defaultPath.chdir.failed", "Created {} but couldn't make it the current directory.", oo::fs::utf8String(snapshotDir));
			}
		}
	}

	BOOL				withFilename = filename.has_value();
	static unsigned		imageNo = 0;
	unsigned			tmpImageNo = 0;
	std::optional<std::string>	pathToPic;
	std::string			baseName = "oolite";

#if SNAPSHOTS_PNG_FORMAT
	const std::string	extension = ".png";
#else
	const std::string	extension = ".bmp";
#endif

	if (withFilename)
	{
		baseName = *filename;
		pathToPic = *filename + extension;
	}
	else
	{
		tmpImageNo = imageNo;
	}

	if (withFilename && oo::fs::fileExists(oo::fs::pathFromUTF8(*pathToPic)))
	{
		OO_LOG("screenshot.filenameExists", "Snapshot \"{}{}\" already exists - adding numerical sequence.", *pathToPic, extension);
		pathToPic = std::nullopt;
	}

	if (!pathToPic.has_value())
	{
		do
		{
			tmpImageNo++;
			pathToPic = oo::str::format("%s-%03d%s", baseName.c_str(), tmpImageNo, extension.c_str());
		} while (oo::fs::fileExists(oo::fs::pathFromUTF8(*pathToPic)));
	}

	if (!withFilename)
	{
		imageNo = tmpImageNo;
	}

	SDL_Surface *surface = SDL_GetWindowSurface(window);
	OO_LOG("screenshot", "Saving screen shot \"{}\" ({} x {} pixels).", *pathToPic, static_cast<unsigned>(surface->w), static_cast<unsigned>(surface->h));

	int pitch = surface->pitch;
	unsigned char *pixls = (unsigned char *)malloc(pitch * surface->h);
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
	if(!SDL_SavePNG(tmpSurface, pathToPic->c_str()))
	{
		OO_LOG("screenshotPNG", "Failed to save {}", *pathToPic);
		snapShotOK = NO;
	}
#else
	if (!SDL_SaveBMP(tmpSurface, pathToPic->c_str()))
	{
		OO_LOG("screenshotBMP", "Failed to save {}", *pathToPic);
		snapShotOK = NO;
	}
#endif
	SDL_DestroySurface(tmpSurface);
	free(pixls);

	// if outputting HDR signal, save also either an .exr or a Radiance .hdr snapshot
	if (hdrOutput())
	{
		std::string fileExtension = DefaultsString("hdr-snapshot-format", std::string(SNAPSHOTHDR_EXTENSION_DEFAULT));

		// we accept file extension with or without a leading dot; if it is without, insert it at the beginning now
		if (!oo::str::hasPrefix(fileExtension, "."))  fileExtension = "." + fileExtension;

		if (fileExtension != std::string(SNAPSHOTHDR_EXTENSION_EXR) && fileExtension != std::string(SNAPSHOTHDR_EXTENSION_HDR))
		{
			OO_LOG("screenshotHDR", "Unrecognized HDR file format requested, defaulting to {}", SNAPSHOTHDR_EXTENSION_DEFAULT);
			fileExtension = std::string(SNAPSHOTHDR_EXTENSION_DEFAULT);
		}

		const std::string pathToPicHDR = oo::str::replaceOccurrences(*pathToPic, ".png", fileExtension);
		OO_LOG("screenshot", "Saving screen shot \"{}\" ({} x {} pixels).", pathToPicHDR, static_cast<unsigned>(surface->w), static_cast<unsigned>(surface->h));
		GLfloat *pixlsf = (GLfloat *)malloc(pitch * surface->h * sizeof(GLfloat));
		for (y=surface->h-1, off=0; y>=0; y--, off+=pitch)
		{
			glReadPixels(0, y, surface->w, 1, GL_RGB, GL_FLOAT, pixlsf + off);
		}

		if ((fileExtension == std::string(SNAPSHOTHDR_EXTENSION_EXR) && SaveEXRSnapshot(pathToPicHDR.c_str(), surface->w, surface->h, pixlsf) != 0) //TINYEXR_SUCCESS
			|| (fileExtension == std::string(SNAPSHOTHDR_EXTENSION_HDR) && !stbi_write_hdr(pathToPicHDR.c_str(), surface->w, surface->h, 3, pixlsf)))
		{
			OO_LOG("screenshotHDR", "Failed to save {}", pathToPicHDR);
			snapShotOK = NO;
		}

		free(pixlsf);
	}

	// return to the previous directory
	if (originalDirectory)  (void)oo::fs::setCurrentDirectory(*originalDirectory);
	return snapShotOK;
}




#ifndef NDEBUG
void MyOpenGLView::dumpRGBAToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes)
{
	if (bytes == NULL || width == 0 || height == 0 || rowBytes < width * 4)  return;

	// use the snapshots directory
	std::string dumpFile = oo::str::appendingPathComponent(oo::str::appendingPathComponent(oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory()), SAVEDIR), SNAPSHOTDIR);
	dumpFile = oo::str::appendingPathComponent(dumpFile, name + ".png");

	SDL_Surface* tmpSurface = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_RGBA32, bytes, rowBytes);
	SDL_SavePNG(tmpSurface, dumpFile.c_str());
	SDL_DestroySurface(tmpSurface);
}


void MyOpenGLView::dumpRGBToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes)
{
	if (bytes == NULL || width == 0 || height == 0 || rowBytes < width * 3)  return;

	// use the snapshots directory
	std::string dumpFile = oo::str::appendingPathComponent(oo::str::appendingPathComponent(oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory()), SAVEDIR), SNAPSHOTDIR);
	dumpFile = oo::str::appendingPathComponent(dumpFile, name + ".png");

	SDL_Surface* tmpSurface = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_RGB24, bytes, rowBytes);
	SDL_SavePNG(tmpSurface, dumpFile.c_str());
	SDL_DestroySurface(tmpSurface);
}


void MyOpenGLView::dumpGrayToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes)
{
	if (bytes == NULL || width == 0 || height == 0 || rowBytes < width)  return;

	// use the snapshots directory
	std::string dumpFile = oo::str::appendingPathComponent(oo::str::appendingPathComponent(oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory()), SAVEDIR), SNAPSHOTDIR);
	dumpFile = oo::str::appendingPathComponent(dumpFile, name + ".png");

	SDL_Surface* tmpSurface = SDL_CreateSurface(width, height, SDL_PIXELFORMAT_RGBA32);
	for(int y = 0; static_cast<NSUInteger>(y) < height; y++)
	{
		uint8_t* srcRow = bytes + rowBytes*y;
		uint8_t* dstRow = (uint8_t*)tmpSurface->pixels + y*tmpSurface->pitch;
		for(int x = 0; static_cast<NSUInteger>(x) < width; x++)
		{
			dstRow[4*x + 0] = srcRow[x];
			dstRow[4*x + 1] = srcRow[x];
			dstRow[4*x + 2] = srcRow[x];
			dstRow[4*x + 3] = '\xff';
		}
	}
	SDL_SavePNG(tmpSurface, dumpFile.c_str());
	SDL_DestroySurface(tmpSurface);
}


void MyOpenGLView::dumpGrayAlphaToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes)
{
	if (bytes == NULL || width == 0 || height == 0 || rowBytes < width * 2)  return;

	// use the snapshots directory
	std::string dumpFile = oo::str::appendingPathComponent(oo::str::appendingPathComponent(oo::fs::utf8String(oo::ResourcePaths::current().homeDirectory()), SAVEDIR), SNAPSHOTDIR);
	dumpFile = oo::str::appendingPathComponent(dumpFile, name + ".png");

	SDL_Surface* tmpSurface = SDL_CreateSurface(width, height, SDL_PIXELFORMAT_RGBA32);	// its own pixels, as -dumpGray: never the caller's 2-byte-a-pixel buffer (bead oo-5thb0)
	for(int y = 0; static_cast<NSUInteger>(y) < height; y++)
	{
		uint8_t* srcRow = bytes + rowBytes*y;
		uint8_t* dstRow = (uint8_t*)tmpSurface->pixels + y*tmpSurface->pitch;
		for(int x = 0; static_cast<NSUInteger>(x) < width; x++)
		{
			dstRow[4*x + 0] = srcRow[2*x];
			dstRow[4*x + 1] = srcRow[2*x];
			dstRow[4*x + 2] = srcRow[2*x];
			dstRow[4*x + 3] = srcRow[2*x+1];
		}
	}
	SDL_SavePNG(tmpSurface, dumpFile.c_str());
	SDL_DestroySurface(tmpSurface);
}


void MyOpenGLView::dumpRGBAToRGBFileNamed(const std::optional<std::string> &rgbName, const std::optional<std::string> &grayName, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes)
{
	if ((!rgbName.has_value() && !grayName.has_value()) || bytes == NULL || width == 0 || height == 0 || rowBytes < width * 4)  return;

	uint8_t				*rgbBytes, *rgbPx, *grayBytes, *grayPx, *srcPx;
	NSUInteger			x, y;
	BOOL				trivalAlpha = YES;

	rgbPx = rgbBytes = (uint8_t *)malloc(width * height * 3);
	if (rgbBytes == NULL)  return;

	grayPx = grayBytes = (uint8_t *)malloc(width * height);
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

	if (rgbName.has_value())
	{
		dumpRGBToFileNamed(*rgbName, rgbBytes, width, height, width * 3);
	}
	free(rgbBytes);

	if (!trivalAlpha && grayName.has_value())
	{
		dumpGrayToFileNamed(*grayName, grayBytes, width, height, width);
	}
	free(grayBytes);
}
#endif
