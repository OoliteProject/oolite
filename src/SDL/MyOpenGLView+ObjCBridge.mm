/*

MyOpenGLView+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-6rb6): the Objective-C MyOpenGLView facade. Every method of
every other method forwards likewise, the input ones (bead oo-0806) last; the members are in
MyOpenGLView.mm and MyOpenGLView+Input.mm. See MyOpenGLView+ObjCBridge.h.

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

#import "MyOpenGLView.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface MyOpenGLView (OOObjCBridgePrivate)

- (id)initWithCxxView:(cxx::MyOpenGLView*)view;

@end

@implementation MyOpenGLView

// Inside the @implementation for the private ivar.
MyOpenGLView* oo::ToObjC(cxx::MyOpenGLView* view)
{
    return Peers().peerFor(view, [view] { return [[MyOpenGLView alloc] initWithCxxView:view]; });
}

cxx::MyOpenGLView* oo::ToCxx(MyOpenGLView* view)
{
    if (view == nil)
        return nullptr;
    return view->_cxxView.get();
}

- (id)initWithCxxView:(cxx::MyOpenGLView*)view
{
    self = [super init];
    if (self != nil)
        _cxxView = oo::Ref<cxx::MyOpenGLView>(view);
    return self;
}

// The C++ view is made empty and this facade becomes its peer before -init's body runs (init()),
// because that body sends the facade's display-mode and input methods (amendment oo-3bgz item 3).
- (id)init
{
    self = [super init];
    if (self == nil)
        return nil;

    _cxxView = oo::makeRef<cxx::MyOpenGLView>();
    @autoreleasepool {
        Peers().peerFor(_cxxView.get(), [self] { return [self retain]; });
    }
    if (!_cxxView->init()) {
        [self release];
        return nil;
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxView.get());
    [super dealloc];
}

- (std::optional<std::string>)getWindowCaption
{
    return _cxxView->getWindowCaption();
}

- (void)createWindowWithSize:(NSSize)size
{
    _cxxView->createWindowWithSize(size);
}

- (void)initSplashScreen
{
    _cxxView->initSplashScreen();
}

- (void)endSplashScreen
{
    _cxxView->endSplashScreen();
}

- (void)initialiseGLWithSize:(NSSize)v_size
{
    _cxxView->initialiseGLWithSize(v_size);
}

- (void)updateGLSize:(NSSize)size
{
    _cxxView->updateGLSize(size);
}

- (void)updateScreen
{
    _cxxView->updateScreen();
}

- (SDL_DisplayID)getDisplayId
{
    return _cxxView->getDisplayId();
}

- (oo::PList)getNativeSize
{
    return _cxxView->getNativeSize();
}

// Slice 2 (bead oo-72cz). -bounds was never declared; it is kept for any sender of the selector.
- (NSRect)bounds
{
    return _cxxView->getBounds();
}

- (NSSize)viewSize
{
    return _cxxView->getViewSize();
}

- (NSSize)backingViewSize
{
    return _cxxView->backingViewSize();
}

- (GLfloat)display_z
{
    return _cxxView->getDisplay_z();
}

- (GLfloat)x_offset
{
    return _cxxView->getX_offset();
}

- (GLfloat)y_offset
{
    return _cxxView->getY_offset();
}

- (GameController*)gameController
{
    return _cxxView->getGameController();
}

- (void)setGameController:(GameController*)controller
{
    _cxxView->setGameController(controller);
}

- (BOOL)isRunningOnPrimaryDisplayDevice
{
    return _cxxView->isRunningOnPrimaryDisplayDevice();
}

- (void)getDisplayDimensions:(unsigned*)width height:(unsigned*)height
{
    _cxxView->getDisplayDimensions(width, height);
}

#if OOLITE_WINDOWS
- (BOOL)atDesktopResolution
{
    return _cxxView->getAtDesktopResolution();
}

- (float)hdrMaxBrightness
{
    return _cxxView->hdrMaxBrightness();
}

- (void)setHDRMaxBrightness:(float)newMaxBrightness
{
    _cxxView->setHDRMaxBrightness(newMaxBrightness);
}

- (float)hdrPaperWhiteBrightness
{
    return _cxxView->hdrPaperWhiteBrightness();
}

- (void)setHDRPaperWhiteBrightness:(float)newPaperWhiteBrightness
{
    _cxxView->setHDRPaperWhiteBrightness(newPaperWhiteBrightness);
}

- (OOHDRToneMapper)hdrToneMapper
{
    return _cxxView->hdrToneMapper();
}

- (void)setHDRToneMapper:(OOHDRToneMapper)newToneMapper
{
    _cxxView->setHDRToneMapper(newToneMapper);
}
#endif

- (OOSDRToneMapper)sdrToneMapper
{
    return _cxxView->sdrToneMapper();
}

- (void)setSDRToneMapper:(OOSDRToneMapper)newToneMapper
{
    _cxxView->setSDRToneMapper(newToneMapper);
}

- (float)colorSaturation
{
    return _cxxView->colorSaturation();
}

- (void)adjustColorSaturation:(float)colorSaturationAdjustment
{
    _cxxView->adjustColorSaturation(colorSaturationAdjustment);
}

- (BOOL)hdrOutput
{
    return _cxxView->hdrOutput();
}

- (BOOL)isOutputDisplayHDREnabled
{
    return _cxxView->isOutputDisplayHDREnabled();
}

- (void)grabMouseInsideGameWindow:(BOOL)value
{
    _cxxView->grabMouseInsideGameWindow(value);
}

- (void)cxx_stringToClipboard:(const std::string&)stringToCopy
{
    _cxxView->stringToClipboard(stringToCopy);
}

- (void)setFullScreenMode:(BOOL)fsm
{
    _cxxView->setFullScreenMode(fsm);
}

- (BOOL)inFullScreenMode
{
    return _cxxView->inFullScreenMode();
}

- (void)toggleScreenMode
{
    _cxxView->toggleScreenMode();
}

- (void)setDisplayMode:(int)mode fullScreen:(BOOL)fsm
{
    _cxxView->setDisplayMode(mode, fsm);
}

- (void)setScreenSize:(int)sizeIndex
{
    _cxxView->setScreenSize(sizeIndex);
}

- (std::vector<oo::PList>)getScreenSizeArray
{
    return _cxxView->getScreenSizeArray();
}

- (void)populateFullScreenModelist
{
    _cxxView->populateFullScreenModelist();
}

- (NSSize)modeAsSize:(int)sizeIndex
{
    return _cxxView->modeAsSize(sizeIndex);
}

- (void)saveWindowSize:(NSSize)windowSize
{
    _cxxView->saveWindowSize(windowSize);
}

- (NSSize)loadWindowSize
{
    return _cxxView->loadWindowSize();
}

- (int)loadFullscreenSettings
{
    return _cxxView->loadFullscreenSettings();
}

- (int)indexOfDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height
                          Refresh:(unsigned int)d_refresh
{
    return _cxxView->indexOfDisplayModeForWidth(d_width, d_height, d_refresh);
}

- (NSSize)currentScreenSize
{
    return _cxxView->currentScreenSize();
}

- (oo::PList)currentScreenMode
{
    return _cxxView->currentScreenMode();
}

- (void)setFov:(float)value fromFraction:(BOOL)fromFraction
{
    _cxxView->setFov(value, fromFraction);
}

- (float)fov:(BOOL)inFraction
{
    return _cxxView->fov(inFraction);
}

- (void)setMsaa:(BOOL)newMsaa
{
    _cxxView->setMsaa(newMsaa);
}

- (BOOL)msaa
{
    return _cxxView->msaa();
}

+ (BOOL)pollShiftKey
{
    return cxx::MyOpenGLView::pollShiftKey();
}

- (OOOpenGLMatrixManager*)getOpenGLMatrixManager
{
    return oo::ToObjC(_cxxView->getOpenGLMatrixManager()); // C++ since bead oo-vt0o: its facade
}

// Slice 3 (bead oo-299r).
- (BOOL)cxx_snapShot:(const std::optional<std::string>&)filename
{
    return _cxxView->snapShot(filename);
}

#ifndef NDEBUG
- (void)cxx_dumpRGBAToFileNamed:(const std::string&)name
                          bytes:(uint8_t*)bytes
                          width:(NSUInteger)width
                         height:(NSUInteger)height
                       rowBytes:(NSUInteger)rowBytes
{
    _cxxView->dumpRGBAToFileNamed(name, bytes, width, height, rowBytes);
}

- (void)cxx_dumpRGBToFileNamed:(const std::string&)name
                         bytes:(uint8_t*)bytes
                         width:(NSUInteger)width
                        height:(NSUInteger)height
                      rowBytes:(NSUInteger)rowBytes
{
    _cxxView->dumpRGBToFileNamed(name, bytes, width, height, rowBytes);
}

- (void)cxx_dumpGrayToFileNamed:(const std::string&)name
                          bytes:(uint8_t*)bytes
                          width:(NSUInteger)width
                         height:(NSUInteger)height
                       rowBytes:(NSUInteger)rowBytes
{
    _cxxView->dumpGrayToFileNamed(name, bytes, width, height, rowBytes);
}

- (void)cxx_dumpGrayAlphaToFileNamed:(const std::string&)name
                               bytes:(uint8_t*)bytes
                               width:(NSUInteger)width
                              height:(NSUInteger)height
                            rowBytes:(NSUInteger)rowBytes
{
    _cxxView->dumpGrayAlphaToFileNamed(name, bytes, width, height, rowBytes);
}

- (void)cxx_dumpRGBAToRGBFileNamed:(const std::optional<std::string>&)rgbName
                  andGrayFileNamed:(const std::optional<std::string>&)grayName
                             bytes:(uint8_t*)bytes
                             width:(NSUInteger)width
                            height:(NSUInteger)height
                          rowBytes:(NSUInteger)rowBytes
{
    _cxxView->dumpRGBAToRGBFileNamed(rgbName, grayName, bytes, width, height, rowBytes);
}
#endif

// Input (bead oo-0806)

- (void)setStringInput:(enum StringInput)value
{
    _cxxView->setStringInput(value);
}

- (void)allowStringInput:(BOOL)value
{
    _cxxView->allowStringInput(value);
}

- (enum StringInput)allowingStringInput
{
    return _cxxView->getAllowingStringInput();
}

- (std::optional<std::string>)cxx_typedString
{
    return _cxxView->getTypedString();
}

- (void)resetTypedString
{
    _cxxView->resetTypedString();
}

- (void)cxx_setTypedString:(const std::string&)value
{
    _cxxView->setTypedString(value);
}

- (void)noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
    _cxxView->noteMouseInteractionModeChangedFrom(oldMode, newMode);
}

- (void)pollControls
{
    _cxxView->pollControls();
}

- (void)setVirtualJoystick:(double)vmx vmy:(double)vmy
{
    _cxxView->setVirtualJoystick(vmx, vmy);
}

- (NSPoint)virtualJoystickPosition
{
    return _cxxView->getVirtualJoystickPosition();
}

- (void)clearKeys
{
    _cxxView->clearKeys();
}

- (void)clearMouse
{
    _cxxView->clearMouse();
}

- (void)clearKey:(int)theKey
{
    _cxxView->clearKey(theKey);
}

- (void)resetMouse
{
    _cxxView->resetMouse();
}

- (BOOL)isAlphabetKeyDown
{
    return _cxxView->getIsAlphabetKeyDown();
}

- (void)suppressKeysUntilKeyUp
{
    _cxxView->suppressKeysUntilKeyUp();
}

- (BOOL)isDown:(int)key
{
    return _cxxView->isDown(key);
}

- (BOOL)isOptDown
{
    return _cxxView->isOptDown();
}

- (BOOL)isCtrlDown
{
    return _cxxView->isCtrlDown();
}

- (BOOL)isShiftDown
{
    return _cxxView->isShiftDown();
}

- (BOOL)isCapsLockOn
{
    return _cxxView->isCapsLockOn();
}

- (BOOL)lastKeyWasShifted
{
    return _cxxView->lastKeyWasShifted();
}

- (int)mouseWheelState
{
    return _cxxView->mouseWheelState();
}

- (float)mouseWheelDelta
{
    return _cxxView->mouseWheelDelta();
}

- (void)setMouseWheelDelta:(float)newWheelDelta
{
    _cxxView->setMouseWheelDelta(newWheelDelta);
}

- (BOOL)isCommandQDown
{
    return _cxxView->isCommandQDown();
}

- (BOOL)isCommandFDown
{
    return _cxxView->isCommandFDown();
}

- (void)clearCommandF
{
    _cxxView->clearCommandF();
}

@end
