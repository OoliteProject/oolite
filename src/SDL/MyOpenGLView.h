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

#import "OOFoundation.h"
#import "OOMouseInteractionMode.h"
#import "OOOpenGL.h"
#import "OOOpenGLMatrixManager.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

#include <SDL3/SDL_video.h>
#include <string_view>

#define WINDOW_SIZE_DEFAULT_WIDTH 1280
#define WINDOW_SIZE_DEFAULT_HEIGHT 720

#define MIN_FOV_DEG 30.0f
#define MAX_FOV_DEG 80.0f
#define MIN_FOV (tan((MIN_FOV_DEG / 2) * M_PI / 180.0f))
#define MAX_FOV (tan((MAX_FOV_DEG / 2) * M_PI / 180.0f))

#define MIN_HDR_MAXBRIGHTNESS 400.0
#define MAX_HDR_MAXBRIGHTNESS 1000.0

#define MIN_HDR_PAPERWHITE 80.0f
#define MAX_HDR_PAPERWHITE 280.0f

#define MAX_COLOR_SATURATION 2.0f

#define MOUSEX_MAXIMUM 0.6
#define MOUSEY_MAXIMUM 0.6

#define MAX_CLEAR_DEPTH 10000000000.0
// 10 000 000 km.
#define INTERMEDIATE_CLEAR_DEPTH 25000.0
// 100 m.

#define NUM_KEYS 327
#define MOUSE_DOUBLE_CLICK_INTERVAL 0.40
#define OOMOUSEWHEEL_EVENTS_DELAY_INTERVAL 0.05
#define OOMOUSEWHEEL_DELTA 120 // Same as Windows WHEEL_DELTA

#define SNAPSHOTS_PNG_FORMAT 1
inline constexpr std::string_view SNAPSHOTHDR_EXTENSION_EXR = ".exr";
inline constexpr std::string_view SNAPSHOTHDR_EXTENSION_HDR = ".hdr";
#define SNAPSHOTHDR_EXTENSION_DEFAULT SNAPSHOTHDR_EXTENSION_EXR

@class Entity, GameController, OpenGLSprite;

enum GameViewKeys {
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
    gvNumberKey9, // 57
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

enum MouseWheelStatus {
    gvMouseWheelDown = -1,
    gvMouseWheelNeutral,
    gvMouseWheelUp
};

enum StringInput {
    gvStringInputNo = 0,
    gvStringInputAlpha = 1,
    gvStringInputLoadSave = 2,
    gvStringInputAll = 3
};

enum KeyboardType {
    gvKeyboardAuto,
    gvKeyboardUS,
    gvKeyboardUK
};

typedef enum {
    OOHDR_TONEMAPPER_NONE = -1,
    OOHDR_TONEMAPPER_ACES_APPROX = 0,
    OOHDR_TONEMAPPER_DICE,
    OOHDR_TONEMAPPER_UCHIMURA,
    OOHDR_TONEMAPPER_REINHARD
} OOHDRToneMapper;

typedef enum {
    OOSDR_TONEMAPPER_NONE = -1,
    OOSDR_TONEMAPPER_ACES = 0,
    OOSDR_TONEMAPPER_AgX,
    OOSDR_TONEMAPPER_HEJLDAWSON,
    OOSDR_TONEMAPPER_UC2,
    OOSDR_TONEMAPPER_UCHIMURA,
    OOSDR_TONEMAPPER_REINHARD
} OOSDRToneMapper;

extern int debug;

@interface MyOpenGLView : OOObject {
    GameController* gameController;
    BOOL keys[NUM_KEYS];
    int scancode2Unicode[NUM_KEYS];
    oo::PList keyMappings_normal; // the keyboard's mapping_normal / mapping_shifted (null if none)
    oo::PList keyMappings_shifted;

    BOOL suppressKeys; // DJS

    BOOL opt, ctrl, command, shift, lastKeyShifted;
    enum StringInput allowingStringInput;
    BOOL isAlphabetKeyDown;

    int keycodetrans[255];

    NSPoint mouseDragStartPoint;

    BOOL mouseWarped;

    NSTimeInterval timeIntervalAtLastClick;
    NSTimeInterval timeSinceLastMouseWheel;
    BOOL doubleClick;

    std::string typedString; // UTF-8; empty, never nil

    NSPoint virtualJoystickPosition;

    float _mouseVirtualStickSensitivityFactor;

    NSSize viewSize;
    GLfloat display_z;
    GLfloat x_offset, y_offset;

    double squareX, squareY;
    NSRect bounds;

    float _fov;
    BOOL _msaa;

    // Full screen sizes
    std::vector<oo::PList> screenSizes; // mode Dicts: Width, Height (integers), RefreshRate (a single real; the native mode's an integer 0)
    int currentSize; // we need an int!
    BOOL fullScreen;

    // Windowed mode
    NSSize currentWindowSize;

    BOOL showSplashScreen;
    SDL_Window* window;
    SDL_GLContext glContext;
    int bitsPerColorComponent;
    BOOL vSyncPreference;

#if OOLITE_WINDOWS

    BOOL saveSize;
    BOOL atDesktopResolution;
    unsigned keyboardMap; // *** FLAGGED for deletion
    HWND windowHandle;
    RECT lastGoodRect;
    float _hdrMaxBrightness;
    float _hdrPaperWhiteBrightness;
    int _hdrToneMapper;

#endif

    int _sdrToneMapper;

    float _colorSaturation;

    BOOL _hdrOutput;

    BOOL grabMouseStatus;

    NSSize firstScreen;

    OOOpenGLMatrixManager* matrixManager;

    // Mouse mode indicator (for mouse movement model)
    BOOL mouseInDeltaMode;

    float _mouseWheelDelta;
}

/**
 * \ingroup cli
 * Scans the command line for -nosplash, --nosplash, -splash, --splash- -novsync and --novsync arguments.
 */
- (id)init;

- (std::optional<std::string>)getWindowCaption;
- (void)createWindowWithSize:(NSSize)size;
- (void)initSplashScreen;
- (void)endSplashScreen;

- (NSSize)viewSize;
- (NSSize)backingViewSize;
- (GLfloat)display_z;
- (GLfloat)x_offset;
- (GLfloat)y_offset;

- (GameController*)gameController;
- (void)setGameController:(GameController*)controller;

- (void)initialiseGLWithSize:(NSSize)v_size;
- (void)updateGLSize:(NSSize)size;
- (BOOL)isRunningOnPrimaryDisplayDevice;
- (void)getDisplayDimensions:(unsigned*)width height:(unsigned*)height;
#if OOLITE_WINDOWS
- (BOOL)atDesktopResolution;
- (float)hdrMaxBrightness;
- (void)setHDRMaxBrightness:(float)newMaxBrightness;
- (float)hdrPaperWhiteBrightness;
- (void)setHDRPaperWhiteBrightness:(float)newPaperWhiteBrightness;
- (OOHDRToneMapper)hdrToneMapper;
- (void)setHDRToneMapper:(OOHDRToneMapper)newToneMapper;
#endif
- (OOSDRToneMapper)sdrToneMapper;
- (void)setSDRToneMapper:(OOSDRToneMapper)newToneMapper;
- (float)colorSaturation;
- (void)adjustColorSaturation:(float)colorSaturationAdjustment;
- (BOOL)hdrOutput;
- (BOOL)isOutputDisplayHDREnabled;

- (void)grabMouseInsideGameWindow:(BOOL)value;

- (void)cxx_stringToClipboard:(const std::string&)stringToCopy;

- (void)updateScreen;

- (BOOL)cxx_snapShot:(const std::optional<std::string>&)filename; // nullopt: auto-numbered "oolite-NNN"

- (SDL_DisplayID)getDisplayId;
- (oo::PList)getNativeSize;

- (void)setFullScreenMode:(BOOL)fsm;
- (BOOL)inFullScreenMode;
- (void)toggleScreenMode;
- (void)setDisplayMode:(int)mode fullScreen:(BOOL)fsm;

- (void)setScreenSize:(int)sizeIndex;
- (std::vector<oo::PList>)getScreenSizeArray;
- (void)populateFullScreenModelist;
- (NSSize)modeAsSize:(int)sizeIndex;
- (void)saveWindowSize:(NSSize)windowSize;
- (NSSize)loadWindowSize;
- (int)loadFullscreenSettings;
- (int)indexOfDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height
                          Refresh:(unsigned int)d_refresh;
- (NSSize)currentScreenSize;
- (oo::PList)currentScreenMode; // null: no mode

// Command-key combinations need special handling. SDL stubs for these mac functions.

- (void)setFov:(float)value fromFraction:(BOOL)fromFraction;
- (float)fov:(BOOL)inFraction;

- (void)setMsaa:(BOOL)newMsaa;
- (BOOL)msaa;

// Check current state of shift key rather than relying on last event.
+ (BOOL)pollShiftKey;

- (OOOpenGLMatrixManager*)getOpenGLMatrixManager;

#ifndef NDEBUG
// General image-dumping method.
- (void)cxx_dumpRGBAToFileNamed:(const std::string&)name
                          bytes:(uint8_t*)bytes
                          width:(NSUInteger)width
                         height:(NSUInteger)height
                       rowBytes:(NSUInteger)rowBytes;
- (void)cxx_dumpRGBToFileNamed:(const std::string&)name
                         bytes:(uint8_t*)bytes
                         width:(NSUInteger)width
                        height:(NSUInteger)height
                      rowBytes:(NSUInteger)rowBytes;
- (void)cxx_dumpGrayToFileNamed:(const std::string&)name
                          bytes:(uint8_t*)bytes
                          width:(NSUInteger)width
                         height:(NSUInteger)height
                       rowBytes:(NSUInteger)rowBytes;
- (void)cxx_dumpGrayAlphaToFileNamed:(const std::string&)name
                               bytes:(uint8_t*)bytes
                               width:(NSUInteger)width
                              height:(NSUInteger)height
                            rowBytes:(NSUInteger)rowBytes;
// A nullopt name skips that file.
- (void)cxx_dumpRGBAToRGBFileNamed:(const std::optional<std::string>&)rgbName
                  andGrayFileNamed:(const std::optional<std::string>&)grayName
                             bytes:(uint8_t*)bytes
                             width:(NSUInteger)width
                            height:(NSUInteger)height
                          rowBytes:(NSUInteger)rowBytes;
#endif

@end

#import "MyOpenGLView+Input.h"
#include <SDL3/SDL_events.h>
