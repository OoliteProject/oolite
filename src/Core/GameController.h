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
#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

#include <optional>
#include <string>
#include <vector>

#if OOLITE_MAC_COCOA_UI
#import <Quartz/Quartz.h> // For PDFKit.
#endif

#define MINIMUM_GAME_TICK 0.25
// * reduced from 0.5s for tgape * //

#define MINIMUM_ANIMATION_TICK 0.0041667
// 1.0 / (desired framerate cap)

@class MyOpenGLView;
class OOFullScreenController; // C++ since bead oo-bgmb

// TEMP: whether to use separate OOFullScreenController object, will hopefully be used for all builds soon.
#define OO_USE_FULLSCREEN_CONTROLLER OOLITE_MAC_COCOA_UI

namespace cxx {

/*	The application controller (bead oo-zkpmt, slice 1 of docs/phases/3-slices/GameController.md):
        the class shell, its state and accessors; the frame loop and deferred calls (slice 2, bead
        oo-hn0fw); start-up, splash and progress messages, exit and the player file (slice 3, bead
        oo-5ah4k); the SDL full-screen members (SDL/GameController+SDLFullScreen.mm, bead oo-qinv), the
        former FullScreen category. The Mac FullScreen category (Core/GameController+FullScreen.mm) is
        not compiled and stays an Objective-C category of the façade (GameController+ObjCBridge.h).
*/
class GameController : public oo::RefCounted {
public:
    // The shared controller, made on first use; borrowed, never released (proposed ADR-0056
    // amendment oo-r7m0).
    static GameController* sharedController();

    GameController();
    ~GameController();

    bool finishedLaunching();

    bool isGamePaused();
    void setGamePaused(bool value);

    /*
      Eco Quality of Service currently implemented only on Windows.
      It sets the game to low power consumption mode when it loses
      focus or is paused. When EcoQoS is active:
      - Windows schedules the appliation on more efficient CPU cores
      - The CPU is kept at a more efficient clock frequency

      On non-Windows platforms it is a no-op.
    */
    void setEcoQoS(bool efficiencyModeRequested);

    OOMouseInteractionMode mouseInteractionMode();
    void setMouseInteractionMode(OOMouseInteractionMode mode);
    void setMouseInteractionModeForFlight(); // Chooses mouse control mode appropriately.
    void setMouseInteractionModeForUIWithMouseInteraction(bool interaction);

    ::MyOpenGLView* gameView();
    void setGameView(::MyOpenGLView* view);

#ifndef NDEBUG
    bool suppressClangStuff();
#endif

    // The frame loop (bead oo-hn0fw, slice 2).
#if !OOLITE_MAC_COCOA_UI
    void performGameTick(id sender);
#endif
    void startAnimationTimer();
    void stopAnimationTimer();

    /*	Fire whatever is due now, the game tick first, then one deferred call:
            what the run loop's -limitDateForMode: did for the game while its tick and
            deferred calls were run-loop timers. For code that must let the game tick
            while it blocks the frame loop (the OXZ download callback). See proposed
            ADR-0033 and ADR-0040.
    */
    void fireDueTimers();

    // Start-up, splash and progress messages, exit, player file (bead oo-5ah4k, slice 3).
    void applicationDidFinishLaunching();

    void exitAppWithContext(const std::string& context);
    void exitAppCommandQ();

    // nullopt: no saved game to load (was nil).
    std::optional<std::string> playerFileToLoad();
    void setPlayerFileToLoad(const std::string& filename); // kept only for a .oolite-save path

    // nullopt: no save directory (was nil). A nullopt argument clears it and the save-directory
    // default, and the next playerFileDirectory() looks it up again (as nil did; "" does not).
    std::optional<std::string> playerFileDirectory();
    void setPlayerFileDirectory(const std::optional<std::string>& filename);

    void loadPlayerIfRequired();

    void beginSplashScreen();
    void logProgress(const std::string& message);
#if OO_DEBUG
    // These take the formatted message, as do OO_DEBUG_PROGRESS / OO_DEBUG_PUSH_PROGRESS below.
    void debugLogProgress(const std::string& message);
    void debugPushProgressMessage(const std::string& message);
    void debugPopProgressMessage();
#endif
    void endSplashScreen();

    void windowDidResize();

#if OOLITE_SDL
    // Full screen (SDL/GameController+SDLFullScreen.mm): the former FullScreen category.
    // -displayModes is getDisplayModes(), as the state has a displayModes.
    void setUpDisplayModes(); // internal use only
    void setFullScreenMode(bool fsm);
    void exitFullScreenMode(); // FIXME: should be setFullScreenMode(false)
    bool inFullScreenMode();
    bool setDisplayWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh);
    oo::PList findDisplayModeForWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh); // a mode dictionary; null: none
    oo::PList getDisplayModes(); // an array of mode dictionaries
    NSUInteger indexOfCurrentDisplayMode();
    void pauseFullScreenModeToPerform(SEL selector, id target);
#endif

    // Internal: the state, read and written by the members above (and by the fenced Mac
    // FullScreen category of the façade through _cxxController).
#if OOLITE_MAC_COCOA_UI
    NSTextField* splashProgressTextField = { };
    NSView* splashView = { };
    NSWindow* gameWindow = { };
    PDFView* helpView = { };
    NSMenu* dockMenu = { };
#endif

    ::MyOpenGLView* _gameView = { }; // retained; was gameView, named like its getter

    NSTimeInterval last_timeInterval = { };
    double delta_t = { };

    int my_mouse_x = { }, my_mouse_y = { };

    std::optional<std::string> _playerFileDirectory; // nullopt: not looked up yet, or none (was nil); named so -cxx_playerFileDirectory's member can be playerFileDirectory()
    std::optional<std::string> _playerFileToLoad; // nullopt: none (was nil); named so -cxx_playerFileToLoad's member can be playerFileToLoad()
    std::vector<std::string> expansionPathsToInclude; // expansion folders opened with the application (Mac)

    NSTimeInterval _animationTimerInterval = { };

    NSTimeInterval _splashStart = { }; // oo::date::monotonicSeconds() at start-up

    SEL pauseSelector = { };
    OOObject* pauseTarget = { };

    bool gameIsPaused = { };

    OOMouseInteractionMode _mouseMode = { };
    OOMouseInteractionMode _resumeMode = { };

// Fullscreen mode stuff.
#if OO_USE_FULLSCREEN_CONTROLLER
    OOFullScreenController* _fullScreenController = { };
#elif OOLITE_SDL
    NSRect fsGeometry = { };
    ::MyOpenGLView* switchView = { };

    oo::PList::Array displayModes; // the usable screen modes, each a mode dictionary

    unsigned int width = { }, height = { };
    unsigned int refresh = { };
    bool fullscreen = { };
    oo::PList originalDisplayMode; // a mode dictionary; null: none (was nil)
    oo::PList fullscreenDisplayMode; // a mode dictionary; null: none (was nil)

    bool stayInFullScreenMode = { };
    bool _finishedLaunching = { };
#endif

private:
    void doPerformGameTick();
    void performGameTickIfDue();
    void fireDueDeadlines();
    void runFrameLoop();

    void reportUnhandledStartupExceptionName(const std::string& name, const std::optional<std::string>& reason); // reason nullopt: none (was nil)
#if OO_DEBUG && !OOLITE_MAC_COCOA_UI
    bool debugMessageTrackingIsOn();
    std::string debugMessageCurrentString();
#endif
};

} // namespace cxx

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
#define OO_DEBUG_PROGRESS(message) [[::GameController sharedController] cxx_debugLogProgress:message]
#define OO_DEBUG_PUSH_PROGRESS(message) [[::GameController sharedController] cxx_debugPushProgressMessage:message]
#define OO_DEBUG_POP_PROGRESS() [[::GameController sharedController] debugPopProgressMessage]
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

// Transitional: the Objective-C GameController, for code not yet converted. Deleted, with namespace
// cxx above, by the bridge's deletion bead.
#import "GameController+ObjCBridge.h"
