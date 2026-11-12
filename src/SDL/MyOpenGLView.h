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

#include <SDL3/SDL_events.h>
#include <SDL3/SDL_video.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "OOEnumFlags.h"
#include "OOFoundation.h"
#include "OOMouseInteractionMode.h"
#include "OOOpenGL.h"
#include "OOOpenGLMatrixManager.h"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/objc/OOObject.h"

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
#define OOMOUSEWHEEL_DELTA 120  // Same as Windows WHEEL_DELTA

#define SNAPSHOTS_PNG_FORMAT 1
inline constexpr std::string_view SNAPSHOTHDR_EXTENSION_EXR = ".exr";
inline constexpr std::string_view SNAPSHOTHDR_EXTENSION_HDR = ".hdr";
#define SNAPSHOTHDR_EXTENSION_DEFAULT SNAPSHOTHDR_EXTENSION_EXR

class Entity;
class GameController;

inline constexpr int gvFunctionKey1 = 256;
inline constexpr int gvFunctionKey2 = gvFunctionKey1 + 1;
inline constexpr int gvFunctionKey3 = gvFunctionKey2 + 1;
inline constexpr int gvFunctionKey4 = gvFunctionKey3 + 1;
inline constexpr int gvFunctionKey5 = gvFunctionKey4 + 1;  // 260
inline constexpr int gvFunctionKey6 = gvFunctionKey5 + 1;
inline constexpr int gvFunctionKey7 = gvFunctionKey6 + 1;
inline constexpr int gvFunctionKey8 = gvFunctionKey7 + 1;
inline constexpr int gvFunctionKey9 = gvFunctionKey8 + 1;
inline constexpr int gvFunctionKey10 = gvFunctionKey9 + 1;
inline constexpr int gvFunctionKey11 = gvFunctionKey10 + 1;
inline constexpr int gvArrowKeyRight = gvFunctionKey11 + 1;
inline constexpr int gvArrowKeyLeft = gvArrowKeyRight + 1;
inline constexpr int gvArrowKeyDown = gvArrowKeyLeft + 1;
inline constexpr int gvArrowKeyUp = gvArrowKeyDown + 1;  // 270
inline constexpr int gvPauseKey = gvArrowKeyUp + 1;
inline constexpr int gvPrintScreenKey = gvPauseKey + 1;  // 272
inline constexpr int gvMouseLeftButton = 301;
inline constexpr int gvMouseDoubleClick = gvMouseLeftButton + 1;
inline constexpr int gvHomeKey = gvMouseDoubleClick + 1;
inline constexpr int gvEndKey = gvHomeKey + 1;
inline constexpr int gvInsertKey = gvEndKey + 1;
inline constexpr int gvDeleteKey = gvInsertKey + 1;
inline constexpr int gvPageUpKey = gvDeleteKey + 1;
inline constexpr int gvPageDownKey = gvPageUpKey + 1;     // 308
inline constexpr int gvBackspaceKey = gvPageDownKey + 1;  // 309
inline constexpr int gvNumberKey0 = 48;
inline constexpr int gvNumberKey1 = gvNumberKey0 + 1;
inline constexpr int gvNumberKey2 = gvNumberKey1 + 1;
inline constexpr int gvNumberKey3 = gvNumberKey2 + 1;
inline constexpr int gvNumberKey4 = gvNumberKey3 + 1;
inline constexpr int gvNumberKey5 = gvNumberKey4 + 1;
inline constexpr int gvNumberKey6 = gvNumberKey5 + 1;
inline constexpr int gvNumberKey7 = gvNumberKey6 + 1;
inline constexpr int gvNumberKey8 = gvNumberKey7 + 1;
inline constexpr int gvNumberKey9 = gvNumberKey8 + 1;  // 57
inline constexpr int gvNumberPadKey0 = 310;
inline constexpr int gvNumberPadKey1 = gvNumberPadKey0 + 1;
inline constexpr int gvNumberPadKey2 = gvNumberPadKey1 + 1;
inline constexpr int gvNumberPadKey3 = gvNumberPadKey2 + 1;
inline constexpr int gvNumberPadKey4 = gvNumberPadKey3 + 1;
inline constexpr int gvNumberPadKey5 = gvNumberPadKey4 + 1;
inline constexpr int gvNumberPadKey6 = gvNumberPadKey5 + 1;
inline constexpr int gvNumberPadKey7 = gvNumberPadKey6 + 1;
inline constexpr int gvNumberPadKey8 = gvNumberPadKey7 + 1;
inline constexpr int gvNumberPadKey9 = gvNumberPadKey8 + 1;
inline constexpr int gvNumberPadKeyDivide = gvNumberPadKey9 + 1;  // 320
inline constexpr int gvNumberPadKeyMultiply = gvNumberPadKeyDivide + 1;
inline constexpr int gvNumberPadKeyMinus = gvNumberPadKeyMultiply + 1;
inline constexpr int gvNumberPadKeyPlus = gvNumberPadKeyMinus + 1;
inline constexpr int gvNumberPadKeyPeriod = gvNumberPadKeyPlus + 1;
inline constexpr int gvNumberPadKeyEquals = gvNumberPadKeyPeriod + 1;
inline constexpr int gvNumberPadKeyEnter = gvNumberPadKeyEquals + 1;  // 326

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

enum KeyboardType { gvKeyboardAuto, gvKeyboardUS, gvKeyboardUK };

enum class OOHDRToneMapper : std::int32_t {
  kNone = -1,
  kAcesApprox = 0,
  kDice,
  kUchimura,
  kReinhard
};
// The numbers the preferences and JS use.
static_assert(oo::ToUnderlying(OOHDRToneMapper::kNone) == -1);
static_assert(oo::ToUnderlying(OOHDRToneMapper::kAcesApprox) == 0);
static_assert(oo::ToUnderlying(OOHDRToneMapper::kDice) == 1);
static_assert(oo::ToUnderlying(OOHDRToneMapper::kUchimura) == 2);
static_assert(oo::ToUnderlying(OOHDRToneMapper::kReinhard) == 3);

// The names the game writes for OOHDRToneMapper (saves, logs and plists).
constexpr std::string_view OOEnumName(OOHDRToneMapper value) noexcept {
  switch (value) {
    case OOHDRToneMapper::kNone:
      return "OOHDR_TONEMAPPER_NONE";
    case OOHDRToneMapper::kAcesApprox:
      return "OOHDR_TONEMAPPER_ACES_APPROX";
    case OOHDRToneMapper::kDice:
      return "OOHDR_TONEMAPPER_DICE";
    case OOHDRToneMapper::kUchimura:
      return "OOHDR_TONEMAPPER_UCHIMURA";
    case OOHDRToneMapper::kReinhard:
      return "OOHDR_TONEMAPPER_REINHARD";
  }
  return {};
}

enum class OOSDRToneMapper : std::int32_t {
  kNone = -1,
  kAces = 0,
  kAgX,
  kHejlDawson,
  kUC2,
  kUchimura,
  kReinhard
};
// The numbers the preferences and JS use.
static_assert(oo::ToUnderlying(OOSDRToneMapper::kNone) == -1);
static_assert(oo::ToUnderlying(OOSDRToneMapper::kAces) == 0);
static_assert(oo::ToUnderlying(OOSDRToneMapper::kAgX) == 1);
static_assert(oo::ToUnderlying(OOSDRToneMapper::kHejlDawson) == 2);
static_assert(oo::ToUnderlying(OOSDRToneMapper::kUC2) == 3);
static_assert(oo::ToUnderlying(OOSDRToneMapper::kUchimura) == 4);
static_assert(oo::ToUnderlying(OOSDRToneMapper::kReinhard) == 5);

// The names the game writes for OOSDRToneMapper (saves, logs and plists).
constexpr std::string_view OOEnumName(OOSDRToneMapper value) noexcept {
  switch (value) {
    case OOSDRToneMapper::kNone:
      return "OOSDR_TONEMAPPER_NONE";
    case OOSDRToneMapper::kAces:
      return "OOSDR_TONEMAPPER_ACES";
    case OOSDRToneMapper::kAgX:
      return "OOSDR_TONEMAPPER_AgX";
    case OOSDRToneMapper::kHejlDawson:
      return "OOSDR_TONEMAPPER_HEJLDAWSON";
    case OOSDRToneMapper::kUC2:
      return "OOSDR_TONEMAPPER_UC2";
    case OOSDRToneMapper::kUchimura:
      return "OOSDR_TONEMAPPER_UCHIMURA";
    case OOSDRToneMapper::kReinhard:
      return "OOSDR_TONEMAPPER_REINHARD";
  }
  return {};
}

extern int debug;

// The game view.
class MyOpenGLView : public oo::RefCounted {
 public:
  MyOpenGLView() = default;  // the object -init fills; see init()
  // The members marked virtual are the ones the whole-game tests' recording
  // views answer (test_GameController, test_OOOXZManager,
  // test_OOPlanetDrawable); nothing in the game overrides them.
  ~MyOpenGLView() override;

  /**
   * \ingroup cli
   * Scans the command line for -nosplash, --nosplash, -splash, --splash-
   * -novsync and --novsync arguments.
   */
  // -init's body, run on the new view by its maker
  // (GameController::beginSplashScreen()). false where -init answered nil (SDL
  // could not start).
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

  // Accessors, display modes, settings, display / HDR, FOV and MSAA. A getter
  // named like its member is get<Name>.
  NSRect getBounds();
  virtual NSSize getViewSize();
  NSSize backingViewSize();
  GLfloat getDisplay_z();
  GLfloat getX_offset();
  GLfloat getY_offset();
  ::GameController* getGameController();
  virtual void setGameController(::GameController* controller);
  bool isRunningOnPrimaryDisplayDevice();
  void getDisplayDimensions(unsigned* width, unsigned* height);
#if OOLITE_WINDOWS
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
  virtual void stringToClipboard(const std::string& stringToCopy);
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
  int indexOfDisplayModeForWidth(unsigned int d_width, unsigned int d_height,
                                 unsigned int d_refresh);
  virtual NSSize currentScreenSize();
  virtual oo::PList currentScreenMode();  // null: no mode
  void setFov(float value, bool fromFraction);
  float fov(bool inFraction);
  void setMsaa(bool newMsaa);
  bool msaa();
  static bool pollShiftKey();
  OOOpenGLMatrixManager* getOpenGLMatrixManager();  // borrowed

  // Snapshots and debug image dumps.
  bool snapShot(const std::optional<std::string>&
                    filename);  // nullopt: auto-numbered "oolite-NNN"
#ifndef NDEBUG
  // General image-dumping method.
  void dumpRGBAToFileNamed(const std::string& name, uint8_t* bytes,
                           std::size_t width, std::size_t height,
                           std::size_t rowBytes);
  void dumpRGBToFileNamed(const std::string& name, uint8_t* bytes,
                          std::size_t width, std::size_t height,
                          std::size_t rowBytes);
  void dumpGrayToFileNamed(const std::string& name, uint8_t* bytes,
                           std::size_t width, std::size_t height,
                           std::size_t rowBytes);
  void dumpGrayAlphaToFileNamed(const std::string& name, uint8_t* bytes,
                                std::size_t width, std::size_t height,
                                std::size_t rowBytes);
  // A nullopt name skips that file.
  void dumpRGBAToRGBFileNamed(const std::optional<std::string>& rgbName,
                              const std::optional<std::string>& grayName,
                              uint8_t* bytes, std::size_t width,
                              std::size_t height, std::size_t rowBytes);
#endif

  // Input (MyOpenGLView+Input.cpp): the former (Input) category. A getter named
  // like its member is get<Name>.
  void initKeyMappingData();
  void autoShowMouse();
  void setStringInput(enum StringInput value);
  void allowStringInput(bool value);
  enum StringInput getAllowingStringInput();
  std::optional<std::string> getTypedString();
  virtual void resetTypedString();
  void setTypedString(const std::string& value);
  virtual void noteMouseInteractionModeChangedFrom(
      OOMouseInteractionMode oldMode, OOMouseInteractionMode newMode);
  void pollControls();
  void setVirtualJoystick(double vmx, double vmy);
  NSPoint getVirtualJoystickPosition();
  void clearKeys();
  void clearMouse();
  void clearKey(int theKey);
  void resetMouse();
  bool getIsAlphabetKeyDown();
  void suppressKeysUntilKeyUp();  // DJS
  bool isDown(int key);
  bool isOptDown();  // opt == alt key
  bool isCtrlDown();
  bool isCommandDown();
  bool isShiftDown();
  bool isCapsLockOn();
  bool lastKeyWasShifted();
  int numKeys();
  int mouseWheelState();
  float mouseWheelDelta();
  void setMouseWheelDelta(float newWheelDelta);
  // Command-key combinations need special handling. SDL stubs for these mac
  // functions.
  bool isCommandQDown();
  bool isCommandFDown();
  void clearCommandF();
  void setMouseInDeltaMode(bool inDelta);
  // DJS: String input handler. Since for SDL versions we're also handling
  // freeform typing this has necessarily got more complex than the non-SDL
  // versions.
  void handleStringInput(SDL_KeyboardEvent* kbd_event, Uint16 key_id);

  // tests/unit/core/test_MyOpenGLView.cpp and test_OOOpenGLMatrixManager.cpp
  // read and set the state below.
  friend struct MyOpenGLViewTestAccess;

 private:
  // Internal: the view's state, read by the members above.
  ::GameController* gameController = {};  // not retained
  bool keys[NUM_KEYS] = {};
  int scancode2Unicode[NUM_KEYS] = {};
  oo::PList keyMappings_normal;  // the keyboard's mapping_normal /
                                 // mapping_shifted (null if none)
  oo::PList keyMappings_shifted;
  bool suppressKeys = {};  // DJS
  bool opt = {}, ctrl = {}, command = {}, shift = {}, lastKeyShifted = {};
  enum StringInput allowingStringInput = {};
  bool isAlphabetKeyDown = {};

  int keycodetrans[255] = {};

  NSPoint mouseDragStartPoint = {};
  bool mouseWarped = {};

  double timeIntervalAtLastClick = {};
  double timeSinceLastMouseWheel = {};
  bool doubleClick = {};

  std::string typedString;  // UTF-8; empty, never nil

  NSPoint virtualJoystickPosition = {};
  float _mouseVirtualStickSensitivityFactor = {};

  NSSize viewSize = {};
  GLfloat display_z = {};
  GLfloat x_offset = {}, y_offset = {};

  double squareX = {}, squareY = {};
  NSRect bounds = {};

  float _fov = {};
  bool _msaa = {};

  // Full screen sizes
  std::vector<oo::PList>
      screenSizes;       // mode Dicts: Width, Height (integers), RefreshRate (a
                         // single real; the native mode's an integer 0)
  int currentSize = {};  // we need an int!
  bool fullScreen = {};

  // Windowed mode
  NSSize currentWindowSize = {};

  bool showSplashScreen = {};
  SDL_Window* window = {};
  SDL_GLContext glContext = {};
  int bitsPerColorComponent = {};

  bool vSyncPreference = {};

#if OOLITE_WINDOWS

  bool saveSize = {};
  bool atDesktopResolution = {};
  unsigned keyboardMap = {};  // *** FLAGGED for deletion
  HWND windowHandle = {};
  RECT lastGoodRect = {};
  float _hdrMaxBrightness = {};
  float _hdrPaperWhiteBrightness = {};
  OOHDRToneMapper _hdrToneMapper = {};

#endif

  OOSDRToneMapper _sdrToneMapper = {};
  float _colorSaturation = {};

  bool _hdrOutput = {};

  bool grabMouseStatus = {};

  NSSize firstScreen = {};

  oo::Ref<OOOpenGLMatrixManager>
      matrixManager;  // Mouse mode indicator (for mouse movement model)
  bool mouseInDeltaMode = {};
  float _mouseWheelDelta = {};

 private:
  void setUpBasicOpenGLStateWithSize();
};
