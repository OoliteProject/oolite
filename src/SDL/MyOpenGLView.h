/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

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

extern int debug;

@interface MyOpenGLView : OpenGLViewSuperClass
{
	GameController		*gameController;
#ifndef GNUSTEP
	OpenGLSprite		*splashSprite;
#endif
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

#ifdef GNUSTEP
    double				squareX,squareY;
	NSRect				bounds;

   // Full screen sizes
	NSMutableArray		*screenSizes;
	int					currentSize;
	BOOL				fullScreen;

	// Windowed mode
	NSSize currentWindowSize;
	SDL_Surface* surface;
	JoystickHandler *stickHandler;
#endif
}


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

- (void)drawRect:(NSRect)rect;

- (void) snapShot;

#ifndef GNUSTEP
- (void)mouseDown:(NSEvent *)theEvent;
- (void)mouseUp:(NSEvent *)theEvent;
#else
- (NSRect) bounds;
- (void) display;
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

 - (void) pollControls: (id)sender;
 - (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event; // DJS
 - (JoystickHandler *)getStickHandler; // DJS
#endif

- (void) setVirtualJoystick:(double) vmx :(double) vmy;
- (NSPoint) virtualJoystickPosition;

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
@end
