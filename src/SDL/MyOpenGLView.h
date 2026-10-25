/*

MyOpenGLView.h

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

#pragma once

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOOpenGL.h"
#include "OOMouseInteractionMode.h"
#include "OOOpenGLMatrixManager.h"
#include "oofnd/Ref.hpp"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"


#include <SDL3/SDL_events.h>
#include <SDL3/SDL_video.h>
#include <string_view>

#define WINDOW_SIZE_DEFAULT_WIDTH	1280
#define WINDOW_SIZE_DEFAULT_HEIGHT	720

#define	MIN_FOV_DEG		30.0f
#define	MAX_FOV_DEG		80.0f
#define MIN_FOV			(tan((MIN_FOV_DEG / 2) * M_PI / 180.0f))
#define MAX_FOV			(tan((MAX_FOV_DEG / 2) * M_PI / 180.0f))

#define MIN_HDR_MAXBRIGHTNESS	400.0
#define MAX_HDR_MAXBRIGHTNESS	1000.0

#define MIN_HDR_PAPERWHITE		80.0f
#define MAX_HDR_PAPERWHITE		280.0f

#define MAX_COLOR_SATURATION	2.0f

#define MOUSEX_MAXIMUM 0.6
#define MOUSEY_MAXIMUM 0.6

#define MAX_CLEAR_DEPTH		10000000000.0
// 10 000 000 km.
#define INTERMEDIATE_CLEAR_DEPTH		25000.0
// 100 m.


#define NUM_KEYS			327
#define MOUSE_DOUBLE_CLICK_INTERVAL	0.40
#define OOMOUSEWHEEL_EVENTS_DELAY_INTERVAL	0.05
#define OOMOUSEWHEEL_DELTA	120 // Same as Windows WHEEL_DELTA

#define SNAPSHOTS_PNG_FORMAT		1
inline constexpr std::string_view SNAPSHOTHDR_EXTENSION_EXR	= ".exr";
inline constexpr std::string_view SNAPSHOTHDR_EXTENSION_HDR	= ".hdr";
#define SNAPSHOTHDR_EXTENSION_DEFAULT	SNAPSHOTHDR_EXTENSION_EXR

class Entity;
class GameController;

enum GameViewKeys
{
	gvFunctionKey1 = 256,
	gvFunctionKey2,
	gvFunctionKey3,
	gvFunctionKey4,
	gvFunctionKey5, // 260
	gvFunctionKey6,
	gvFunctionKey7,
	gvFunctionKey8,
	gvFunctionKey9,
	gvFunctionKey10,
	gvFunctionKey11,
	gvArrowKeyRight,
	gvArrowKeyLeft,
	gvArrowKeyDown,
	gvArrowKeyUp, // 270
	gvPauseKey,
	gvPrintScreenKey, // 272
	gvMouseLeftButton = 301,
	gvMouseDoubleClick,
	gvHomeKey,
	gvEndKey,
	gvInsertKey,
	gvDeleteKey,
	gvPageUpKey,
	gvPageDownKey, // 308
	gvBackspaceKey, // 309
	gvNumberKey0 = 48,
	gvNumberKey1,
	gvNumberKey2,
	gvNumberKey3,
	gvNumberKey4,
	gvNumberKey5,
	gvNumberKey6,
	gvNumberKey7,
	gvNumberKey8,
	gvNumberKey9, //57
	gvNumberPadKey0 = 310,
	gvNumberPadKey1,
	gvNumberPadKey2,
	gvNumberPadKey3,
	gvNumberPadKey4,
	gvNumberPadKey5,
	gvNumberPadKey6,
	gvNumberPadKey7,
	gvNumberPadKey8,
	gvNumberPadKey9,
	gvNumberPadKeyDivide, // 320
	gvNumberPadKeyMultiply,
	gvNumberPadKeyMinus,
	gvNumberPadKeyPlus,
	gvNumberPadKeyPeriod,
	gvNumberPadKeyEquals,
	gvNumberPadKeyEnter // 326
};

enum MouseWheelStatus
{
	gvMouseWheelDown = -1,
	gvMouseWheelNeutral,
	gvMouseWheelUp
};

enum StringInput
{
	gvStringInputNo = 0,
	gvStringInputAlpha = 1,
	gvStringInputLoadSave = 2,
	gvStringInputAll = 3
};

enum KeyboardType
{
	gvKeyboardAuto,
	gvKeyboardUS,
	gvKeyboardUK
};

typedef enum
{
	OOHDR_TONEMAPPER_NONE = -1,
	OOHDR_TONEMAPPER_ACES_APPROX = 0,
	OOHDR_TONEMAPPER_DICE,
	OOHDR_TONEMAPPER_UCHIMURA,
	OOHDR_TONEMAPPER_REINHARD
} OOHDRToneMapper;

typedef enum
{
	OOSDR_TONEMAPPER_NONE = -1,
	OOSDR_TONEMAPPER_ACES = 0,
	OOSDR_TONEMAPPER_AgX,
	OOSDR_TONEMAPPER_HEJLDAWSON,
	OOSDR_TONEMAPPER_UC2,
	OOSDR_TONEMAPPER_UCHIMURA,
	OOSDR_TONEMAPPER_REINHARD
} OOSDRToneMapper;

extern int debug;

// The game view: a global class since the Objective-C facade was deleted (bead oo-9ht.153).
class MyOpenGLView : public oo::RefCounted
{
public:
	MyOpenGLView() = default;	// the object -init fills; see init()
	// The members marked virtual are the ones the whole-game tests' recording views answer
	// (test_GameController, test_OOOXZManager, test_OOPlanetDrawable; ADR-0056 amendment oo-9ht.153
	// item 4); nothing in the game overrides them.
	~MyOpenGLView() override;

	/**
	 * \ingroup cli
	 * Scans the command line for -nosplash, --nosplash, -splash, --splash- -novsync and --novsync arguments.
	 */
	// -init's body, run on the new view by its maker (GameController::beginSplashScreen(); amendment
	// oo-3bgz item 3). false where -init answered nil (SDL could not start).
	bool init();
	std::optional<std::string> getWindowCaption();
	void createWindowWithSize(NSSize size);
	void initSplashScreen();
	virtual void endSplashScreen();
	void initialiseGLWithSize(NSSize v_size);
	void updateGLSize(NSSize size);
	virtual void updateScreen();
	SDL_DisplayID getDisplayId();
	oo::PList getNativeSize();

	// Slice 2 (bead oo-72cz): accessors, display modes, settings, display / HDR, FOV and MSAA. A getter
	// named like its member is get<Name> (ADR-0056 amendment oo-862e).
	NSRect getBounds();
	virtual NSSize getViewSize();
	NSSize backingViewSize();
	GLfloat getDisplay_z();
	GLfloat getX_offset();
	GLfloat getY_offset();
	::GameController *getGameController();
	virtual void setGameController(::GameController *controller);
	bool isRunningOnPrimaryDisplayDevice();
#if OOLITE_WINDOWS
	void getDisplayDimensions(unsigned *width, unsigned *height);
	void refreshDarKOrLightMode();
	bool isDarkModeOn();
	bool getAtDesktopResolution();
	float hdrMaxBrightness();
	void setHDRMaxBrightness(float newMaxBrightness);
	float hdrPaperWhiteBrightness();
	void setHDRPaperWhiteBrightness(float newPaperWhiteBrightness);
	OOHDRToneMapper hdrToneMapper();
	void setHDRToneMapper(OOHDRToneMapper newToneMapper);
#endif
	OOSDRToneMapper sdrToneMapper();
	void setSDRToneMapper(OOSDRToneMapper newToneMapper);
	float colorSaturation();
	void adjustColorSaturation(float colorSaturationAdjustment);
	bool hdrOutput();
	bool isOutputDisplayHDREnabled();
	void grabMouseInsideGameWindow(bool value);
	virtual void stringToClipboard(const std::string &stringToCopy);
	void setFullScreenMode(bool fsm);
	virtual bool inFullScreenMode();
	void toggleScreenMode();
	void setDisplayMode(int mode, bool fsm);
	void setScreenSize(int sizeIndex);
	virtual std::vector<oo::PList> getScreenSizeArray();
	void populateFullScreenModelist();
	NSSize modeAsSize(int sizeIndex);
	void saveWindowSize(NSSize windowSize);
	NSSize loadWindowSize();
	int loadFullscreenSettings();
	int indexOfDisplayModeForWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh);
	virtual NSSize currentScreenSize();
	virtual oo::PList currentScreenMode();	// null: no mode
	void setFov(float value, bool fromFraction);
	float fov(bool inFraction);
	void setMsaa(bool newMsaa);
	bool msaa();
	static bool pollShiftKey();
	OOOpenGLMatrixManager *getOpenGLMatrixManager();	// borrowed

	// Slice 3 (bead oo-299r): snapshots and debug image dumps.
	bool snapShot(const std::optional<std::string> &filename);	// nullopt: auto-numbered "oolite-NNN"
#ifndef NDEBUG
	// General image-dumping method.
	void dumpRGBAToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes);
	void dumpRGBToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes);
	void dumpGrayToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes);
	void dumpGrayAlphaToFileNamed(const std::string &name, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes);
	// A nullopt name skips that file.
	void dumpRGBAToRGBFileNamed(const std::optional<std::string> &rgbName, const std::optional<std::string> &grayName, uint8_t *bytes, NSUInteger width, NSUInteger height, NSUInteger rowBytes);
#endif

	// Input (bead oo-0806, MyOpenGLView+Input.mm): the former (Input) category. A getter named like its
	// member is get<Name> (ADR-0056 amendment oo-862e).
	void initKeyMappingData();
	void autoShowMouse();
	void setStringInput(enum StringInput value);
	void allowStringInput(bool value);
	enum StringInput getAllowingStringInput();
	std::optional<std::string> getTypedString();
	virtual void resetTypedString();
	void setTypedString(const std::string &value);
	virtual void noteMouseInteractionModeChangedFrom(OOMouseInteractionMode oldMode, OOMouseInteractionMode newMode);
	void pollControls();
	void setVirtualJoystick(double vmx, double vmy);
	NSPoint getVirtualJoystickPosition();
	void clearKeys();
	void clearMouse();
	void clearKey(int theKey);
	void resetMouse();
	bool getIsAlphabetKeyDown();
	void suppressKeysUntilKeyUp();	// DJS
	bool isDown(int key);
	bool isOptDown();	// opt == alt key
	bool isCtrlDown();
	bool isCommandDown();
	bool isShiftDown();
	bool isCapsLockOn();
	bool lastKeyWasShifted();
	int numKeys();
	int mouseWheelState();
	float mouseWheelDelta();
	void setMouseWheelDelta(float newWheelDelta);
	// Command-key combinations need special handling. SDL stubs for these mac functions.
	bool isCommandQDown();
	bool isCommandFDown();
	void clearCommandF();
	void setMouseInDeltaMode(bool inDelta);
	// DJS: String input handler. Since for SDL versions we're also handling freeform typing this has
	// necessarily got more complex than the non-SDL versions.
	void handleStringInput(SDL_KeyboardEvent *kbd_event, Uint16 key_id);

	// tests/unit/core/test_MyOpenGLView.mm and test_OOOpenGLMatrixManager.mm read and set the state
	// below (bead oo-mlpcc).
	friend struct MyOpenGLViewTestAccess;

private:
	/*	Internal: the view's state, read by the members above and by the other slices. Private again
		since bead oo-mlpcc (public from oo-9ht.153 to it).
	*/
	::GameController		*gameController = {};	// not retained
	bool				keys[NUM_KEYS] = {};
	int					scancode2Unicode[NUM_KEYS] = {};
	oo::PList			keyMappings_normal;		// the keyboard's mapping_normal / mapping_shifted (null if none)
	oo::PList			keyMappings_shifted;
	bool				suppressKeys = {};    // DJS
	bool				opt = {}, ctrl = {}, command = {}, shift = {}, lastKeyShifted = {};
	enum StringInput	allowingStringInput = {};
	bool				isAlphabetKeyDown = {};

	int					keycodetrans[255] = {};

	NSPoint				mouseDragStartPoint = {};
	bool				mouseWarped = {};

	NSTimeInterval		timeIntervalAtLastClick = {};
	NSTimeInterval		timeSinceLastMouseWheel = {};
	bool				doubleClick = {};

	std::string			typedString;	// UTF-8; empty, never nil

	NSPoint				virtualJoystickPosition = {};
	float				_mouseVirtualStickSensitivityFactor = {};

	NSSize				viewSize = {};
	GLfloat				display_z = {};
	GLfloat				x_offset = {}, y_offset = {};

	double				squareX = {}, squareY = {};
	NSRect				bounds = {};

	float				_fov = {};
	bool				_msaa = {};

	// Full screen sizes
	std::vector<oo::PList>	screenSizes;	// mode Dicts: Width, Height (integers), RefreshRate (a single real; the native mode's an integer 0)
	int					currentSize = {};	//we need an int!
	bool				fullScreen = {};

	// Windowed mode
	NSSize				currentWindowSize = {};

	bool				showSplashScreen = {};
	SDL_Window			*splashWindow = {};
	SDL_Window			*window = {};
	SDL_GLContext			glContext = {};
	int				bitsPerColorComponent = {};

	bool				vSyncPreference = {};

#if OOLITE_WINDOWS

	bool				saveSize = {};
	bool				atDesktopResolution = {};
	unsigned			keyboardMap = {}; // *** FLAGGED for deletion
	HWND 				windowHandle = {};
	RECT				lastGoodRect = {};
	float				_hdrMaxBrightness = {};
	float				_hdrPaperWhiteBrightness = {};
	int					_hdrToneMapper = {};

#endif

	int					_sdrToneMapper = {};
	float				_colorSaturation = {};

	bool				_hdrOutput = {};

	bool				grabMouseStatus = {};

	NSSize				firstScreen = {};

	oo::Ref<OOOpenGLMatrixManager>	matrixManager;	// C++ since bead oo-vt0o

	// Mouse mode indicator (for mouse movement model)
	bool				mouseInDeltaMode = {};
	float				_mouseWheelDelta = {};

private:
	void setUpBasicOpenGLStateWithSize();
};

