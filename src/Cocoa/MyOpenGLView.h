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


#define MAX_CLEAR_DEPTH		10000000000.0
// 10 000 000 km.
#define INTERMEDIATE_CLEAR_DEPTH		100.0
// 100 m.

#define	MIN_FOV_DEG		30.0f
#define	MAX_FOV_DEG		80.0f
#define MIN_FOV			(tan((MIN_FOV_DEG / 2) * M_PI / 180.0f))
#define MAX_FOV			(tan((MAX_FOV_DEG / 2) * M_PI / 180.0f))

#define NUM_KEYS			320
#define MOUSE_DOUBLE_CLICK_INTERVAL	0.40
#define OOMOUSEWHEEL_EVENTS_DELAY_INTERVAL	0.05

@class Entity, GameController;

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
	gvArrowKeyUp,
	gvMouseLeftButton = 301,
	gvMouseDoubleClick,
	gvHomeKey,
	gvEndKey,
	gvInsertKey,
	gvDeleteKey,
	gvPageUpKey,
	gvPageDownKey,
	gvNumberKey0 = 48,
	gvNumberKey1,
	gvNumberKey2,
	gvNumberKey3,
	gvNumberKey4,
	gvNumberKey5,
	gvNumberKey6,
	gvNumberKey7,
	gvNumberKey8,
	gvNumberKey9,
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

extern int debug;

@interface MyOpenGLView: NSOpenGLView
{
@private
	GameController		*gameController;

	BOOL				keys[NUM_KEYS];
	BOOL				supressKeys;	// DJS

	BOOL				opt, ctrl, command, shift, capsLockOn;
	BOOL				allowingStringInput;
	BOOL				isAlphabetKeyDown;
	BOOL				commandQ;
	BOOL				commandF;
	BOOL				f12;
	
	int					keycodetrans[255];
	
	BOOL				m_glContextInitialized;
	
	NSTimeInterval		timeIntervalAtLastClick;
	NSTimeInterval		timeIntervalAtLastMouseWheel;
	BOOL				doubleClick;
	
	NSMutableString		*typedString;
	
	NSPoint				virtualJoystickPosition;
	enum MouseWheelStatus	_mouseWheelState;
	
	NSSize				viewSize;
	NSSize				backingViewSize;
	GLfloat				display_z;
	GLfloat				x_offset, y_offset;
	
	float				_fov;
	
	int					_virtualScreen;
	NSData				*_pixelFormatAttributes;
	
	OOOpenGLMatrixManager		*matrixManager;

}


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

- (NSData *)pixelFormatAttributes;

- (void) drawRect:(NSRect)rect;
- (void) updateScreen;
- (void) pollControls;

- (void) stringToClipboard:(NSString *)stringToCopy;

- (BOOL) snapShot:(NSString *)filename;

- (void)mouseDown:(NSEvent *)theEvent;
- (void)mouseUp:(NSEvent *)theEvent;
- (void)resetMouse;

- (void) setVirtualJoystick:(double) vmx :(double) vmy;
- (NSPoint) virtualJoystickPosition;

- (void) clearKeys;
- (void) clearMouse;
- (void) clearKey: (int)theKey;
- (BOOL) isAlphabetKeyDown;
- (void) supressKeysUntilKeyUp; // DJS
- (BOOL) isDown: (int) key;
- (BOOL) isOptDown;
- (BOOL) isCtrlDown;
- (BOOL) isCommandDown;
- (BOOL) isShiftDown;
- (BOOL) isCapsLockOn;
- (int) numKeys;
- (int) mouseWheelState;

// Command-key combinations need special handling.
- (BOOL) isCommandQDown;
- (BOOL) isCommandFDown;
- (void) clearCommandF;

// Check current state of shift key rather than relying on last event.
+ (BOOL)pollShiftKey;

- (OOOpenGLMatrixManager *) getOpenGLMatrixManager;

#ifndef NDEBUG
// General image-dumping methods.
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

// Split alpha into separate file.
- (void) dumpRGBAToRGBFileNamed:(NSString *)rgbName
			   andGrayFileNamed:(NSString *)grayName
						  bytes:(uint8_t *)bytes
						  width:(NSUInteger)width
						 height:(NSUInteger)height
					   rowBytes:(NSUInteger)rowBytes;
#endif

// no-ops to allow gamma value to be easily saved/restored
- (void) setGammaValue: (float) value;
- (float) gammaValue;

- (void) setFov:(float)value fromFraction:(BOOL)fromFraction;
- (float) fov:(BOOL)inFraction;

@end
