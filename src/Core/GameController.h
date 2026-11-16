/*

GameController.h

Main application controller class.

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

#import "OOFoundation.h"
#import "OOFullScreenController.h"
#import "OOFunctionAttributes.h"
#import "OOMouseInteractionMode.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

#if OOLITE_MAC_COCOA_UI
#import <Quartz/Quartz.h> // For PDFKit.
#endif

#define MINIMUM_GAME_TICK 0.25
// * reduced from 0.5s for tgape * //

#define MINIMUM_ANIMATION_TICK 0.0041667
// 1.0 / (desired framerate cap)

@class MyOpenGLView, OOFullScreenController;

// TEMP: whether to use separate OOFullScreenController object, will hopefully be used for all builds soon.
#define OO_USE_FULLSCREEN_CONTROLLER OOLITE_MAC_COCOA_UI

@interface GameController : OOObject {
@private
#if OOLITE_MAC_COCOA_UI
    IBOutlet NSTextField* splashProgressTextField;
    IBOutlet NSView* splashView;
    IBOutlet NSWindow* gameWindow;
    IBOutlet PDFView* helpView;
    IBOutlet NSMenu* dockMenu;
#endif

    IBOutlet MyOpenGLView* gameView;

    NSTimeInterval last_timeInterval;
    double delta_t;

    int my_mouse_x, my_mouse_y;

    std::optional<std::string> playerFileDirectory; // nullopt: not looked up yet, or none (was nil)
    std::optional<std::string> playerFileToLoad; // nullopt: none (was nil)
    std::vector<std::string> expansionPathsToInclude; // expansion folders opened with the application (Mac)

    NSTimeInterval _animationTimerInterval;

    NSTimeInterval _splashStart; // oo::date::monotonicSeconds() at start-up

    SEL pauseSelector;
    OOObject* pauseTarget;

    BOOL gameIsPaused;

    OOMouseInteractionMode _mouseMode;
    OOMouseInteractionMode _resumeMode;

// Fullscreen mode stuff.
#if OO_USE_FULLSCREEN_CONTROLLER
    OOFullScreenController* _fullScreenController;
#elif OOLITE_SDL
    NSRect fsGeometry;
    MyOpenGLView* switchView;

    oo::PList::Array displayModes; // the usable screen modes, each a mode dictionary

    unsigned int width, height;
    unsigned int refresh;
    BOOL fullscreen;
    oo::PList originalDisplayMode; // a mode dictionary; null: none (was nil)
    oo::PList fullscreenDisplayMode; // a mode dictionary; null: none (was nil)

    BOOL stayInFullScreenMode;
    BOOL _finishedLaunching;
#endif
}

+ (GameController*)sharedController;

- (void)applicationDidFinishLaunching;
- (BOOL)finishedLaunching;

- (BOOL)isGamePaused;
- (void)setGamePaused:(BOOL)value;

/*
  Eco Quality of Service currently implemented only on Windows.
  It sets the game to low power consumption mode when it loses
  focus or is paused. When EcoQoS is active:
  - Windows schedules the appliation on more efficient CPU cores
  - The CPU is kept at a more efficient clock frequency

  On non-Windows platforms it is a no-op.
*/
- (void)setEcoQoS:(BOOL)efficiencyModeRequested;

- (OOMouseInteractionMode)mouseInteractionMode;
- (void)setMouseInteractionMode:(OOMouseInteractionMode)mode;
- (void)setMouseInteractionModeForFlight; // Chooses mouse control mode appropriately.
- (void)setMouseInteractionModeForUIWithMouseInteraction:(BOOL)interaction;

- (void)performGameTick:(id)sender;

#if OOLITE_MAC_COCOA_UI
- (IBAction)showLogAction:(id)sender;
- (IBAction)showLogFolderAction:(id)sender;
- (IBAction)showSnapshotsAction:(id)sender;
- (IBAction)showAddOnsAction:(id)sender;
- (void)recenterVirtualJoystick;
- (NSURL*)snapshotsURLCreatingIfNeeded:(BOOL)create;
#endif

- (void)cxx_exitAppWithContext:(const std::string&)context;
- (void)exitAppCommandQ;

// nullopt: no saved game to load (was nil).
- (std::optional<std::string>)cxx_playerFileToLoad;
- (void)cxx_setPlayerFileToLoad:(const std::string&)filename; // kept only for a .oolite-save path

// nullopt: no save directory (was nil). A nullopt argument clears it and the save-directory
// default, and the next -cxx_playerFileDirectory looks it up again (as nil did; "" does not).
- (std::optional<std::string>)cxx_playerFileDirectory;
- (void)cxx_setPlayerFileDirectory:(const std::optional<std::string>&)filename;

- (void)loadPlayerIfRequired;

- (void)beginSplashScreen;
- (void)cxx_logProgress:(const std::string&)message;
#if OO_DEBUG
// These take the formatted message, as do OO_DEBUG_PROGRESS / OO_DEBUG_PUSH_PROGRESS below.
- (void)cxx_debugLogProgress:(const std::string&)message;
- (void)cxx_debugPushProgressMessage:(const std::string&)message;
- (void)debugPopProgressMessage;
#endif
- (void)endSplashScreen;

- (void)startAnimationTimer;
- (void)stopAnimationTimer;

/*	Fire whatever is due now, the game tick first, then one deferred call:
        what the run loop's -limitDateForMode: did for the game while its tick and
        deferred calls were run-loop timers. For code that must let the game tick
        while it blocks the frame loop (the OXZ download callback). See proposed
        ADR-0033 and ADR-0040.
*/
- (void)fireDueTimers;

- (MyOpenGLView*)gameView;
- (void)setGameView:(MyOpenGLView*)view;

- (void)windowDidResize;

@end

@interface GameController (FullScreen)

#if OO_USE_FULLSCREEN_CONTROLLER
#if OOLITE_MAC_COCOA_UI
- (IBAction)toggleFullScreenAction:(id)sender;
#endif

- (void)setFullScreenMode:(BOOL)value;
#endif

- (void)exitFullScreenMode; // FIXME: should be setFullScreenMode:NO
- (BOOL)inFullScreenMode;

- (BOOL)setDisplayWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh;
- (oo::PList)findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int)d_refresh; // a mode dictionary; null: none (flipped with its family, bead oo-3rb.273)
- (oo::PList)displayModes; // an array of mode dictionaries (flipped with its family, bead oo-3rb.273)
- (NSUInteger)indexOfCurrentDisplayMode;

- (void)pauseFullScreenModeToPerform:(SEL)selector onTarget:(id)target;

// Internal use only.
- (void)setUpDisplayModes;

@end

/*	OOScheduleDeferredCall(target, selector, argument, delay): what Foundation's
        performer-after-delay did (bead oo-3rb.57, proposed ADR-0040). [target
        performSelector:selector withObject:argument] runs on the first frame-loop
        pass at least delay seconds from now (a delay <= 0 is 0.0001 s), after that
        pass's tick; target and argument are retained until then. Due calls fire in
        the order they were scheduled, at most two per pass, as the run loop fired
        its timers. Main thread only: a call scheduled on another thread never fires,
        as a performer on that thread's never-run run loop did not.
*/
void OOScheduleDeferredCall(id target, SEL selector, id argument, NSTimeInterval delay);

#if OO_DEBUG
#define OO_DEBUG_PROGRESS(message) [[GameController sharedController] cxx_debugLogProgress:message]
#define OO_DEBUG_PUSH_PROGRESS(message) [[GameController sharedController] cxx_debugPushProgressMessage:message]
#define OO_DEBUG_POP_PROGRESS() [[GameController sharedController] debugPopProgressMessage]
#else
#define OO_DEBUG_PROGRESS(message) \
    do {                           \
    } while (0)
#define OO_DEBUG_PUSH_PROGRESS(message) \
    do {                                \
    } while (0)
#define OO_DEBUG_POP_PROGRESS() \
    do {                        \
    } while (0)
#endif
