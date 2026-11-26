/*

MyOpenGLView+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-6rb6): the Objective-C MyOpenGLView, a facade over the C++
cxx::MyOpenGLView (MyOpenGLView.h), for the code that is not converted yet: the game controller,
which makes the view with +alloc/-init and drives the splash screen, the universe and every caller
of [UNIVERSE gameView], and the Input category (MyOpenGLView+Input.mm), which is still an
Objective-C category of this facade and reaches the view's state through oo::ToCxx(self) (ADR-0056
amendment oo-3bgz). Its interface is the one MyOpenGLView.h declared before the conversion, copied
exactly (same selectors, same types), less the ivars, which are the C++ class's members. Each method
forwards to its C++ member (slices 1-3, beads oo-6rb6, oo-72cz and oo-299r). Imported by MyOpenGLView.h after the class; do
not import it directly.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  ----------------------------
        still Objective-C                      MyOpenGLView * (this facade)    nothing: messages as before
        converted (C++)                        oo::Ref<cxx::MyOpenGLView>
          handing the view to Objective-C                                      oo::ToObjC(view)
          taking it from Objective-C                                           oo::ToCxx(objcView)

oo::ToObjC gives the view's one live facade (oo::ObjCPeers). Never add to this file; converted code
does not message the facade. Deleted by its deletion bead once no file outside MyOpenGLView* names
the Objective-C class.

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

#ifndef MYOPENGLVIEW_OBJCBRIDGE_H
#define MYOPENGLVIEW_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface MyOpenGLView : OOObject {
@private
    oo::Ref<cxx::MyOpenGLView> _cxxView;
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
- (void)initialiseGLWithSize:(NSSize)v_size;
- (void)updateGLSize:(NSSize)size;

- (void)updateScreen;

- (SDL_DisplayID)getDisplayId;
- (oo::PList)getNativeSize;

- (NSSize)viewSize;
- (NSSize)backingViewSize;
- (GLfloat)display_z;
- (GLfloat)x_offset;
- (GLfloat)y_offset;

- (GameController*)gameController;
- (void)setGameController:(GameController*)controller;

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

- (BOOL)cxx_snapShot:(const std::optional<std::string>&)filename; // nullopt: auto-numbered "oolite-NNN"
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

// Input (bead oo-0806): forwarders for the members other classes send. The rest are cxx::MyOpenGLView's only.
- (void)setStringInput:(enum StringInput)value;
- (void)allowStringInput:(BOOL)value;
- (enum StringInput)allowingStringInput;
- (std::optional<std::string>)cxx_typedString;
- (void)resetTypedString;
- (void)cxx_setTypedString:(const std::string&)value;
- (void)noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode;
- (void)pollControls;
- (void)setVirtualJoystick:(double)vmx vmy:(double)vmy;
- (NSPoint)virtualJoystickPosition;
- (void)clearKeys;
- (void)clearMouse;
- (void)clearKey:(int)theKey;
- (void)resetMouse;
- (BOOL)isAlphabetKeyDown;
- (void)suppressKeysUntilKeyUp; // DJS
- (BOOL)isDown:(int)key;
- (BOOL)isOptDown; // opt == alt key
- (BOOL)isCtrlDown;
- (BOOL)isShiftDown;
- (BOOL)isCapsLockOn;
- (BOOL)lastKeyWasShifted;
- (int)mouseWheelState;
- (float)mouseWheelDelta;
- (void)setMouseWheelDelta:(float)newWheelDelta;
// Command-key combinations need special handling. SDL stubs for these mac functions.
- (BOOL)isCommandQDown;
- (BOOL)isCommandFDown;
- (void)clearCommandF;

@end

namespace oo {

// The view's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
MyOpenGLView* ToObjC(cxx::MyOpenGLView* view);
inline MyOpenGLView* ToObjC(const Ref<cxx::MyOpenGLView>& view) { return ToObjC(view.get()); }
// The C++ view behind a facade, borrowed (the facade retains it); null for nil.
cxx::MyOpenGLView* ToCxx(MyOpenGLView* view);

} // namespace oo

#endif // MYOPENGLVIEW_OBJCBRIDGE_H
