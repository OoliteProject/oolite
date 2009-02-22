/*

MyOpenGLView.h

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

#import "OOCocoa.h"
#import "OOOpenGL.h"

#ifdef GNUSTEP
#include <SDL.h>
#endif

#define MAX_CLEAR_DEPTH		100000000.0
// 100 000 km.

#define NUM_KEYS			320

#define MOUSE_DOUBLE_CLICK_INTERVAL	0.40
#define MOUSE_VIRTSTICKSENSITIVITY 930.0f
#define MOUSEX_MAXIMUM 0.6
#define MOUSEY_MAXIMUM 0.6

@class Entity, GameController, OpenGLSprite;

#ifdef GNUSTEP
@class JoystickHandler;
#define OpenGLViewSuperClass	NSObject
#else
#define OpenGLViewSuperClass	NSOpenGLView
#endif

enum GameViewKeys
{
	gvArrowKeyUp = 255,
	gvArrowKeyDown = 254,
	gvArrowKeyLeft = 253,
	gvArrowKeyRight = 252,
	gvFunctionKey1 = 241,
	gvFunctionKey2 = 242,
	gvFunctionKey3 = 243,
	gvFunctionKey4 = 244,
	gvFunctionKey5 = 245,
	gvFunctionKey6 = 246,
	gvFunctionKey7 = 247,
	gvFunctionKey8 = 248,
	gvFunctionKey9 = 249,
	gvFunctionKey10 = 250,
	gvFunctionKey11 = 251,
	gvMouseLeftButton = 301,
	gvMouseDoubleClick = 303,
	gvHomeKey = 302,
	gvNumberKey0 = 48,
	gvNumberKey1 = 49,
	gvNumberKey2 = 50,
	gvNumberKey3 = 51,
	gvNumberKey4 = 52,
	gvNumberKey5 = 53,
	gvNumberKey6 = 54,
	gvNumberKey7 = 55,
	gvNumberKey8 = 56,
	gvNumberKey9 = 57
};

enum StringInput
{
	gvStringInputNo = 0,
	gvStringInputAlpha = 1,
	gvStringInputAll = 2
};

enum KeyboardType
{
	gvKeyboardAuto,
	gvKeyboardUS,
	gvKeyboardUK
};

extern int debug;

@interface MyOpenGLView : OpenGLViewSuperClass
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

	NSTimeInterval		timeIntervalAtLastClick;
	BOOL				doubleClick;

	NSMutableString		*typedString;

	NSPoint				virtualJoystickPosition;

	NSSize				viewSize;
	GLfloat				display_z;

    double				squareX,squareY;
	NSRect				bounds;

   // Full screen sizes
	NSMutableArray		*screenSizes;
	unsigned			currentSize;
	BOOL				fullScreen;

	// Windowed mode
	NSSize currentWindowSize;
	SDL_Surface* surface;
	JoystickHandler *stickHandler;
	
#if OOLITE_WINDOWS

	BOOL				wasFullScreen;
	BOOL				splashScreen;
	unsigned			keyboardMap;
	HWND 				SDL_Window;

#endif

	NSSize				firstScreen;

   // Mouse mode indicator (for mouse movement model)
   BOOL  mouseInDeltaMode;
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
- (GLfloat) display_z;

- (GameController *) gameController;
- (void) setGameController:(GameController *) controller;

- (void) initialiseGLWithSize:(NSSize) v_size;
- (void) initialiseGLWithSize:(NSSize) v_size useVideoMode:(BOOL) v_mode;

- (void) display;
- (void) updateScreen;
- (void) drawRect:(NSRect)rect;
- (void) updateScreenWithVideoMode:(BOOL) v_mode;

- (void) snapShot;

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
- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event; // DJS
- (JoystickHandler *)getStickHandler; // DJS

- (void) setVirtualJoystick:(double) vmx :(double) vmy;
- (NSPoint) virtualJoystickPosition;

- (void) setKeyboardTo: (NSString *) value;
- (void) clearKeys;
- (void) clearMouse;
- (BOOL) isAlphabetKeyDown;
- (void) supressKeysUntilKeyUp; // DJS
- (BOOL) isDown: (int) key;
- (BOOL) isOptDown;
- (BOOL) isCtrlDown;
- (BOOL) isCommandDown;
- (BOOL) isShiftDown;
- (int) numKeys;

- (void) setMouseInDeltaMode: (BOOL) inDelta;

// Check current state of shift key rather than relying on last event.
- (BOOL)pollShiftKey;
@end
