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

#import "OOCocoa.h"
#import "OOOpenGL.h"
#import "OOMouseInteractionMode.h"
#import "OOOpenGLMatrixManager.h"


#include <SDL.h>

#define	MIN_FOV_DEG		30.0f
#define	MAX_FOV_DEG		80.0f
#define MIN_FOV			(tan((MIN_FOV_DEG / 2) * M_PI / 180.0f))
#define MAX_FOV			(tan((MAX_FOV_DEG / 2) * M_PI / 180.0f))

#define MOUSEVIRTUALSTICKSENSITIVITYFACTOR	0.95f
#define MOUSEX_MAXIMUM 0.6
#define MOUSEY_MAXIMUM 0.6

#define MAX_CLEAR_DEPTH		10000000000.0
// 10 000 000 km.
#define INTERMEDIATE_CLEAR_DEPTH		100.0
// 100 m.


#define NUM_KEYS			320
#define MOUSE_DOUBLE_CLICK_INTERVAL	0.40
#define OOMOUSEWHEEL_EVENTS_DELAY_INTERVAL	0.05

#define SNAPSHOTS_PNG_FORMAT		1

@class Entity, GameController, OpenGLSprite;

enum GameViewKeys
{
	gvFunctionKey1 = 241,
	gvFunctionKey2,
	gvFunctionKey3,
	gvFunctionKey4,
	gvFunctionKey5,
	gvFunctionKey6,
	gvFunctionKey7,
	gvFunctionKey8,
	gvFunctionKey9,
	gvFunctionKey10,
	gvFunctionKey11,
	gvArrowKeyRight,
	gvArrowKeyLeft,
	gvArrowKeyDown,
	gvArrowKeyUp, // 255
	gvMouseLeftButton = 301,
	gvMouseDoubleClick,
	gvHomeKey,
	gvEndKey,
	gvInsertKey,
	gvDeleteKey,
	gvPageUpKey,
	gvPageDownKey, // 308
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
	gvNumberPadKey9 //319
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

extern int debug;

@interface MyOpenGLView : NSObject
{
	GameController		*gameController;
	BOOL				keys[NUM_KEYS];
	BOOL				supressKeys;    // DJS

	BOOL				opt, ctrl, command, shift;
	BOOL				allowingStringInput;
	BOOL				isAlphabetKeyDown;

	int					keycodetrans[255];

	BOOL				m_glContextInitialized;
    NSPoint				mouseDragStartPoint;

	BOOL				mouseWarped;

	NSTimeInterval		timeIntervalAtLastClick;
	NSTimeInterval		timeSinceLastMouseWheel;
	BOOL				doubleClick;

	NSMutableString		*typedString;

	NSPoint				virtualJoystickPosition;

	NSSize				viewSize;
	GLfloat				display_z;
	GLfloat				x_offset, y_offset;

    double				squareX,squareY;
	NSRect				bounds;

	float				_gamma;
	float				_fov;

   // Full screen sizes
	NSMutableArray		*screenSizes;
	int					currentSize;	//we need an int!
	BOOL				fullScreen;

	// Windowed mode
	NSSize				currentWindowSize;
	SDL_Surface			*surface;

	BOOL				showSplashScreen;

#if OOLITE_WINDOWS

	BOOL				wasFullScreen;
	BOOL				updateContext;
	BOOL				saveSize;
	BOOL				atDesktopResolution;
	unsigned			keyboardMap;
	HWND 				SDL_Window;
	MONITORINFOEX		monitorInfo;
	RECT				lastGoodRect;

#endif

	BOOL				grabMouseStatus;

	NSSize				firstScreen;
	
	OOOpenGLMatrixManager		*matrixManager;

   // Mouse mode indicator (for mouse movement model)
   BOOL					mouseInDeltaMode;
   
   int					_mouseWheelState;
}

- (void) initSplashScreen;
- (void) endSplashScreen;
- (void) autoShowMouse;

- (void) setStringInput: (enum StringInput) value;
- (void) allowStringInput: (BOOL) value;
- (enum StringInput) allowingStringInput;
- (NSString *) typedString;
- (void) resetTypedString;
- (void) setTypedString:(NSString*) value;

- (NSSize) viewSize;
- (NSSize) backingViewSize;
- (GLfloat) display_z;
- (GLfloat) x_offset;
- (GLfloat) y_offset;

- (GameController *) gameController;
- (void) setGameController:(GameController *) controller;

- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode;

- (void) initialiseGLWithSize:(NSSize) v_size;
- (void) initialiseGLWithSize:(NSSize) v_size useVideoMode:(BOOL) v_mode;
- (BOOL) isRunningOnPrimaryDisplayDevice;
#if OOLITE_WINDOWS
- (BOOL) getCurrentMonitorInfo:(MONITORINFOEX *)mInfo;
- (MONITORINFOEX) currentMonitorInfo;
- (BOOL) atDesktopResolution;
#endif

- (void) grabMouseInsideGameWindow:(BOOL) value;

- (void) stringToClipboard:(NSString *)stringToCopy;

- (void) drawRect:(NSRect)rect;
- (void) updateScreen;
- (void) updateScreenWithVideoMode:(BOOL) v_mode;
- (void) display;

- (BOOL) snapShot:(NSString *)filename;
#if SNAPSHOTS_PNG_FORMAT
- (BOOL) pngSaveSurface:(NSString *)fileName withSurface:(SDL_Surface *)surf;
#endif

- (NSRect) bounds;
+ (NSMutableDictionary *) getNativeSize;

- (void) setFullScreenMode:(BOOL)fsm;
- (BOOL) inFullScreenMode;
- (void) toggleScreenMode;
- (void) setDisplayMode:(int)mode fullScreen:(BOOL)fsm;

- (int) indexOfCurrentSize;
- (void) setScreenSize: (int)sizeIndex;
- (NSMutableArray *)getScreenSizeArray;
- (void) populateFullScreenModelist;
- (NSSize) modeAsSize: (int)sizeIndex;
- (void) saveWindowSize: (NSSize) windowSize;
- (NSSize) loadWindowSize;
- (int) loadFullscreenSettings;
- (int) findDisplayModeForWidth: (unsigned int) d_width Height:(unsigned int) d_height
                        Refresh: (unsigned int)d_refresh;
- (NSSize) currentScreenSize;

- (void) pollControls;

- (void) setVirtualJoystick:(double) vmx :(double) vmy;
- (NSPoint) virtualJoystickPosition;

- (void) clearKeys;
- (void) clearMouse;
- (void) clearKey: (int)theKey;
- (void) resetMouse;
- (BOOL) isAlphabetKeyDown;
- (void) supressKeysUntilKeyUp; // DJS
- (BOOL) isDown: (int) key;
- (BOOL) isOptDown; // opt == alt key
- (BOOL) isCtrlDown;
- (BOOL) isCommandDown;
- (BOOL) isShiftDown;
- (BOOL) isCapsLockOn;
- (int) numKeys;
- (int) mouseWheelState;

// Command-key combinations need special handling. SDL stubs for these mac functions.
- (BOOL) isCommandQDown;
- (BOOL) isCommandFDown;
- (void) clearCommandF;

- (void) setKeyboardTo: (NSString *) value;
- (void) setMouseInDeltaMode: (BOOL) inDelta;

- (void) setGammaValue: (float) value;
- (float) gammaValue;

- (void) setFov:(float)value fromFraction:(BOOL)fromFraction;
- (float) fov:(BOOL)inFraction;

// Check current state of shift key rather than relying on last event.
+ (BOOL)pollShiftKey;

- (OOOpenGLMatrixManager *) getOpenGLMatrixManager;

#ifndef NDEBUG
// General image-dumping method.
- (void) dumpRGBAToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes;
- (void) dumpRGBToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes;
- (void) dumpGrayToFileNamed:(NSString *)name
					   bytes:(uint8_t *)bytes
					   width:(NSUInteger)width
					  height:(NSUInteger)height
					rowBytes:(NSUInteger)rowBytes;
- (void) dumpGrayAlphaToFileNamed:(NSString *)name
							bytes:(uint8_t *)bytes
							width:(NSUInteger)width
						   height:(NSUInteger)height
						 rowBytes:(NSUInteger)rowBytes;
- (void) dumpRGBAToRGBFileNamed:(NSString *)rgbName
			   andGrayFileNamed:(NSString *)grayName
						  bytes:(uint8_t *)bytes
						  width:(NSUInteger)width
						 height:(NSUInteger)height
					   rowBytes:(NSUInteger)rowBytes;
#endif

@end
