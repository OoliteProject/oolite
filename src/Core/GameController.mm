/*

GameController.m

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

#import "GameController.h"
#import "MyOpenGLView.h"
#import "OODebugFlags.h"
#import "OODebugSupport.h"
#import "OOJSFrameCallbacks.h"
#import "OOLogOutputHandler.h"
#import "OOLoggingExtended.h"
#import "OOOXPVerifier.h"
#import "OOOXZManager.h"
#import "OOOpenALController.h"
#import "OOOpenGL.h"
#import "OOOpenGLExtensionManager.h"
#import "OOOpenGLMatrixManager.h"
#import "OOSound.h"
#import "PlayerEntityLoadSave.h"
#import "ResourceManager.h"
#import "Universe.h"
#import "legacy_random.h"
#import <objc/objc-arc.h>
#include <stdlib.h>
#ifdef OO_DEBUG_MONITOR_ENABLED
#import "OODebugTCPConsoleClient.h"
#endif
#ifndef NDEBUG
#import "OOJavaScriptEngine.h"
#endif
#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Log.hpp"
#include "oofnd/ResourcePaths.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"
#include "oofnd/Thread.hpp"
#include "oofnd/objc/OOException.h"
#include <chrono>
#include <thread>

#if OOLITE_MAC_COCOA_UI
#import "JAPersistentFileReference.h"
#import "OOMacJoystickManager.h"
#import "OoliteApp.h"
#import <Sparkle/Sparkle.h>

static void SetUpSparkle(void);
#elif (OOLITE_SDL && defined(OO_DEBUG_MONITOR_ENABLED))
#import "OODebugMonitor.h"
#endif

static GameController* sSharedController = nil;

@interface GameController (OOPrivate)

- (void)cxx_reportUnhandledStartupExceptionName:(const std::string&)name reason:(const std::optional<std::string>&)reason; // reason nullopt: none (was nil)

- (void)doPerformGameTick;

@end

@implementation GameController

+ (GameController*)sharedController
{
    if (sSharedController == nil) {
        sSharedController = [[self alloc] init];
    }
    return sSharedController;
}

- (id)init
{
    if (sSharedController != nil) {
        [self release];
        [OOException raise:OOInternalInconsistencyException format:"%s: expected only one GameController to exist at a time.", __PRETTY_FUNCTION__];
    }

    if ((self = [super init])) {
        _finishedLaunching = NO;
        last_timeInterval = oo::date::monotonicSeconds(); // the frame clock: intervals only (-doPerformGameTick)
        delta_t = 0.01; // one hundredth of a second
        {
            oo::Defaults& prefs = oo::Defaults::standard();
            _animationTimerInterval = prefs.object("animation_timer_interval").isNull() ? MINIMUM_ANIMATION_TICK : prefs.doubleForKey("animation_timer_interval");
        }

        // rather than seeding this with the date repeatedly, seed it
        // once here at startup
        // OO_RANDOM_SEED pins the seed so a run can be reproduced.
        // Downstream component tests depend on it.
        // Unset to keep wall-clock seeding.
        const char* seedEnv = getenv("OO_RANDOM_SEED");
        if (seedEnv != NULL && *seedEnv != '\0') {
            ranrot_srand((uint32_t)strtoul(seedEnv, NULL, 10));
            OO_LOG("rand.seed", "RANROT seeded from OO_RANDOM_SEED={}", seedEnv);
        } else {
            ranrot_srand((uint32_t)oo::date::timeIntervalSince1970()); // reset randomiser with current time
        }

        _splashStart = oo::date::monotonicSeconds();
    }

    return self;
}

- (void)dealloc
{
#if OOLITE_MAC_COCOA_UI
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:UNIVERSE];
#endif

    [gameView release];
    [UNIVERSE release];

    [super dealloc];
}

- (BOOL)isGamePaused
{
    return gameIsPaused;
}

- (void)setGamePaused:(BOOL)value
{
    if (value && !gameIsPaused) {
        _resumeMode = [self mouseInteractionMode];
        [self setMouseInteractionModeForUIWithMouseInteraction:NO];
        [self setEcoQoS:YES];
        gameIsPaused = YES;
        [PLAYER doScriptEvent:OOJSID("gamePaused")];
    } else if (!value && gameIsPaused) {
        [self setMouseInteractionMode:_resumeMode];
        [self setEcoQoS:NO];
        gameIsPaused = NO;
        [PLAYER doScriptEvent:OOJSID("gameResumed")];
    }
}

- (void)setEcoQoS:(BOOL)efficiencyModeRequested
{
#if OOLITE_WINDOWS
#ifdef OO_DEBUG_MONITOR_ENABLED
    /*	A paused game a debug console is driving is not idle (bug oo-37zzy). Efficiency mode puts
            the process in IDLE_PRIORITY_CLASS, which runs only when no other thread wants a CPU: on a
            loaded machine every frame - and so every console command, serviced between frames - then
            waited seconds per GL call (measured: 15-60 s a frame; 0.04 s once the class was put back
            to normal). Stay at normal priority while a console is connected.
    */
    if (efficiencyModeRequested && OODebugTCPConsoleIsWaitingForInput())
        return;
#endif
    if (oo::Defaults::standard().object("ecoqos").isNull() ? YES : oo::Defaults::standard().boolForKey("ecoqos")) {
        BOOL setEfficiencyMode = !!efficiencyModeRequested; // yes or no, not 42
        HANDLE currentProcess = GetCurrentProcess();

        if (EXPECT_NOT(!SetPriorityClass(currentProcess, setEfficiencyMode ? IDLE_PRIORITY_CLASS : NORMAL_PRIORITY_CLASS))) {
            OO_LOG("gameController.setEcoQos", "SetPriorityClass failed with error {}", static_cast<unsigned long>(GetLastError()));
        }

        PROCESS_POWER_THROTTLING_STATE powerThrottling;
        RtlZeroMemory(&powerThrottling, sizeof(powerThrottling));
        powerThrottling.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
        powerThrottling.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED;
        powerThrottling.StateMask = setEfficiencyMode ? PROCESS_POWER_THROTTLING_EXECUTION_SPEED : 0;
        if (EXPECT_NOT(!SetProcessInformation(currentProcess, ProcessPowerThrottling, &powerThrottling, sizeof(powerThrottling)))) {
            OO_LOG("gameController.setEcoQos", "SetProcessInformation failed with error {}", static_cast<unsigned long>(GetLastError()));
        }
    }
#endif
}

- (OOMouseInteractionMode)mouseInteractionMode
{
    return _mouseMode;
}

- (void)setMouseInteractionMode:(OOMouseInteractionMode)mode
{
    OOMouseInteractionMode oldMode = _mouseMode;
    if (mode == oldMode)
        return;

    _mouseMode = mode;
    OO_LOG("input.mouseMode.changed", "Mouse interaction mode changed from {} to {}", OOStringFromMouseInteractionMode(oldMode), OOStringFromMouseInteractionMode(mode));

#if OO_USE_FULLSCREEN_CONTROLLER
    if ([self inFullScreenMode]) {
        [_fullScreenController noteMouseInteractionModeChangedFrom:oldMode to:mode];
    } else
#endif
    {
        [[self gameView] noteMouseInteractionModeChangedFrom:oldMode to:mode];
    }
}

- (void)setMouseInteractionModeForFlight
{
    [self setMouseInteractionMode:[PLAYER isMouseControlOn] ? MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL : MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL];
}

- (void)setMouseInteractionModeForUIWithMouseInteraction:(BOOL)interaction
{
    [self setMouseInteractionMode:interaction ? MOUSE_MODE_UI_SCREEN_WITH_INTERACTION : MOUSE_MODE_UI_SCREEN_NO_INTERACTION];
}

- (MyOpenGLView*)gameView
{
    return gameView;
}

- (void)setGameView:(MyOpenGLView*)view
{
    [gameView release];
    gameView = [view retain];
    [gameView setGameController:self];
    [UNIVERSE setGameView:gameView];
}

- (void)applicationDidFinishLaunching
{
    void* pool = NULL;

    pool = objc_autoreleasePoolPush();

    @try {
        // if not verifying oxps, ensure that gameView is drawn to using beginSplashScreen
        // OpenGL is initialised and that allows textures to initialise too.

#if OO_OXP_VERIFIER_ENABLED

        if ([OOOXPVerifier runVerificationIfRequested]) {
            [self cxx_exitAppWithContext:"OXP verifier run"];
        } else {
            [self beginSplashScreen];
        }

#else
        [self beginSplashScreen];
#endif

#if OOLITE_MAC_COCOA_UI
        [OOJoystickManager setStickHandlerClass:[OOMacJoystickManager class]];
        SetUpSparkle();
#endif

        [self setUpDisplayModes];

        // moved to before the Universe is created
        for (const std::string& expansionPath : expansionPathsToInclude) {
            [ResourceManager cxx_addExternalPath:expansionPath];
        }

        // initialise OXZ manager
        [OOOXZManager sharedManager];

        // moved here to try to avoid initialising this before having an Open GL context
        //[self cxx_logProgress:OO_DESC("Initialising universe")]; // DESC expansions only possible after Universe init
        [[Universe alloc] initWithGameView:gameView];

        [self loadPlayerIfRequired];

        [self cxx_logProgress:""];

        // get the run loop and add the call to performGameTick:
        [self startAnimationTimer];

        [self endSplashScreen];
    }
    @catch (OOException* exception) {
        [self cxx_reportUnhandledStartupExceptionName:std::string([exception name]) reason:std::string([exception reason])];
        exit(EXIT_FAILURE);
    }

    OO_LOG("startup.complete", "========== Loading complete in {:.2f} seconds. ==========", oo::date::monotonicSeconds() - _splashStart);

#if OO_USE_FULLSCREEN_CONTROLLER
    [self setFullScreenMode:oo::Defaults::standard().boolForKey("fullscreen")];
#endif

    _finishedLaunching = YES;

    // Release anything allocated above that is not required.
    objc_autoreleasePoolPop(pool);

#if !OOLITE_MAC_COCOA_UI
    [self runFrameLoop];
#endif
}

- (BOOL)finishedLaunching
{
    return _finishedLaunching;
}

- (void)loadPlayerIfRequired
{
    if (playerFileToLoad.has_value()) {
        [self cxx_logProgress:OO_DESC("loading-player")];
        // fix problem with non-shader lighting when starting skips
        // the splash screen
        [UNIVERSE useGUILightSource:YES];
        [UNIVERSE useGUILightSource:NO];
        [PLAYER loadPlayerFromFile:*playerFileToLoad asNew:NO];
    }
}

- (void)beginSplashScreen
{
#if !OOLITE_MAC_COCOA_UI
    if (!gameView) {
        gameView = [MyOpenGLView alloc];
        [gameView init];
        [gameView setGameController:self];
        [gameView initSplashScreen];
    }
#else
    [gameView updateScreen];
#endif
}

#if !OOLITE_MAC_COCOA_UI // the Mac -performGameTick: is in GameController (MacOSX) at the end of the file

- (void)performGameTick:(id)sender
{
    void* pool = objc_autoreleasePoolPush();

    [gameView pollControls];
    [self doPerformGameTick];

    objc_autoreleasePoolPop(pool);
}

#endif

- (void)doPerformGameTick
{
    @try {
        if (gameIsPaused)
            delta_t = 0.0; // no movement!
        else {
            delta_t = oo::date::monotonicSeconds() - last_timeInterval;
            last_timeInterval += delta_t;
            if (delta_t > MINIMUM_GAME_TICK)
                delta_t = MINIMUM_GAME_TICK; // peg the maximum pause (at 0.5->1.0 seconds) to protect against when the machine sleeps
        }

        [UNIVERSE update:delta_t];
        if (EXPECT_NOT([PLAYER status] == STATUS_RESTART_GAME)) {
            [UNIVERSE reinitAndShowDemo:YES];
        }
        [OOSound update];
        if (!gameIsPaused) {
            OOJSFrameCallbacksInvoke(delta_t);
        }
    }
    @catch (id exception) {
        if ([exception isKindOfClass:[OOException class]]) {
            // -callStackSymbols is Foundation's; an OOException does not answer it (sending it raised
            // out of this handler), so name the exception instead (proposed ADR-0037).
            OOException* ooException = (OOException*)exception;
            OO_LOG("exception.backtrace", "{} : {}", [ooException name], [ooException reason]);
        } else {
            OO_LOG("exception.backtrace", "{}", oo::DescriptionOf(exception)); // no Foundation exception has -callStackSymbols any more (oo-qps.17)
        }
    }

    @
    try {
        [gameView updateScreen];
    }
    @catch (id exception) {
    }
}

/*	The frame loop (ADR-0029 Decision 5; proposed ADR-0033).

        The game tick was a repeating Foundation timer on the main run loop, which
        -applicationDidFinishLaunching: then ran for ever. It is now a deadline on
        std::chrono::steady_clock, created and advanced exactly as GNUstep created
        and advanced that timer's fire date (measured, see the ADR):

        * start: first deadline = now + interval (an interval <= 0 is 0.0001 s);
        * fire when now >= deadline; before the tick runs, the next deadline is
          deadline + interval, plus as many further intervals as needed to pass the
          time sampled just before the tick (a late tick skips, it never bursts);
        * stop/start inside a tick (the save/load critical section) replaces the
          deadline, as a new timer did.

        Each pass of the loop fires what is due (the tick first, then the log
        flush, then up to two deferred calls), then runs the run loop once, up to
        the next deadline, for what still lives on it (OXZ downloads) until its own
        bead takes it off; while the debug console's socket is open, the wait is on
        that socket instead (bead oo-3rb.14).
*/
namespace {
// Held as steady_clock tick counts, as OOLogOutputHandler's flush deadline is: a static
// time_point or duration has a constructor that may throw (bugprone-throwing-static-initialization).
using TickClock = std::chrono::steady_clock;
bool sGameTickScheduled = false;
TickClock::rep sNextGameTick = 0; // ticks since the clock's epoch
TickClock::rep sGameTickInterval = 0; // ticks

TickClock::time_point NextGameTick()
{
    return TickClock::time_point(TickClock::duration(sNextGameTick));
}
}

/*	Deferred calls (bead oo-3rb.57, proposed ADR-0040): Foundation's timed
        performers, which were one-shot timers on the main run loop. Measured
        against gnustep-base 1.31: a performer's fire date is now + delay (a delay
        <= 0 is 0.0001 s, the timer clamp); each run-loop pass fires the first due
        timer in the order the timers were added, twice (-runMode:beforeDate: asks
        -limitDateForMode:'s timer step once itself and once more before it waits),
        so due performers fire in scheduling order whatever their fire dates, at
        most two per pass; one scheduled while firing goes to the back. The
        performer retained target and argument and released them after the call;
        an exception from the call was logged by NSTimer and swallowed, and the
        performer was then never released (it leaked its target and argument).
        Anything else thrown propagated.
*/
namespace {

struct OODeferredCall {
    std::chrono::steady_clock::time_point deadline;
    id target;
    SEL selector;
    id argument;
};

std::vector<OODeferredCall> sDeferredCalls; // in scheduling order

}

void OOScheduleDeferredCall(id target, SEL selector, id argument, NSTimeInterval delay)
{
    if (!oo::thread::isMainThread())
        return;

    if (delay <= 0.0)
        delay = 0.0001; // as the Foundation timer did
    OODeferredCall call = {
        std::chrono::steady_clock::now() + std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(delay)),
        [target retain],
        selector,
        [argument retain]
    };
    sDeferredCalls.push_back(call);
}

namespace {

// One step of the run loop's timer firing: the first due call in scheduling order.
void FireOneDueDeferredCall(void)
{
    const std::chrono::steady_clock::time_point now = std::chrono::steady_clock::now();
    for (std::vector<OODeferredCall>::iterator it = sDeferredCalls.begin(); it != sDeferredCalls.end(); ++it) {
        if (it->deadline <= now) {
            OODeferredCall call = *it;
            sDeferredCalls.erase(it);

            @try {
                [call.target performSelector:call.selector withObject:call.argument];
            }
            @catch (OOException* exception) {
                // The game's own exceptions (ADR-0037): the same line, name and reason bridged.
                OO_LOG("unclassified", "*** NSTimer ignoring exception '{}' (reason '{}') raised during posting of timer with target {} and selector 'fire'", [exception name], [exception reason], oo::str::pointerDescription(call.target));
                return; // target and argument stay retained, as the performer leaked them
            }

            [call.target release];
            [call.argument release];
            return;
        }
    }
}

// The earliest pending deferred call, if any: part of the run loop's wait limit.
bool NextDeferredCallDeadline(std::chrono::steady_clock::time_point* outDeadline)
{
    bool found = false;
    for (const OODeferredCall& call : sDeferredCalls) {
        if (!found || call.deadline < *outDeadline) {
            *outDeadline = call.deadline;
            found = true;
        }
    }
    return found;
}

}

- (void)startAnimationTimer
{
    if (!sGameTickScheduled) {
        NSTimeInterval ti = _animationTimerInterval; // default one two-hundredth of a second (should be a fair bit faster than expected frame rate ~60Hz to avoid problems with phase differences)
        if (ti <= 0.0)
            ti = 0.0001; // as the Foundation timer did

        sGameTickInterval = std::chrono::duration_cast<TickClock::duration>(std::chrono::duration<double>(ti)).count();
        sNextGameTick = TickClock::now().time_since_epoch().count() + sGameTickInterval;
        sGameTickScheduled = true;
    }
}

- (void)stopAnimationTimer
{
    sGameTickScheduled = false;
}

- (void)performGameTickIfDue
{
    if (!sGameTickScheduled)
        return;

    const TickClock::rep now = TickClock::now().time_since_epoch().count();
    if (now < sNextGameTick)
        return;

    TickClock::rep next = sNextGameTick + sGameTickInterval;
    while (next <= now)
        next += sGameTickInterval;
    sNextGameTick = next;

    [self performGameTick:self];
}

- (void)fireDueDeadlines
{
    [self performGameTickIfDue];
    OOLogOutputHandlerFlushIfDue();
}

- (void)fireDueTimers
{
    [self fireDueDeadlines];
    FireOneDueDeferredCall();
}

- (void)runFrameLoop
{
    for (;;) {
        @autoreleasepool {
            [self fireDueDeadlines];
            FireOneDueDeferredCall();
            FireOneDueDeferredCall();

            // Wait for input until the tick or the next deferred call, whichever is first.
            std::chrono::steady_clock::time_point wake;
            bool haveWake = NextDeferredCallDeadline(&wake);
            if (sGameTickScheduled && (!haveWake || NextGameTick() < wake)) {
                wake = NextGameTick();
                haveWake = true;
            }
            // The OXZ download's callbacks, which the run loop delivered (proposed ADR-0044).
            [[OOOXZManager sharedManager] processDownloadEvents];

#ifdef OO_DEBUG_MONITOR_ENABLED
            if (OODebugTCPConsoleIsWaitingForInput()) {
                /*	The debug console's socket is no longer on the run loop (bead oo-3rb.14,
                        proposed ADR-0041): wait on the socket as the run loop waited on the
                        console's streams, handling what arrives before the next deadline.
                */
                double timeout = -1.0;
                if (haveWake) {
                    timeout = std::chrono::duration<double>(wake - std::chrono::steady_clock::now()).count();
                    if (timeout < 0.0)
                        timeout = 0.0;
                }
                OODebugTCPConsoleServiceInput(timeout);
            } else
#endif
            {
                /*	Nothing else to wait on now that the run-loop pump is gone (bead oo-3rb.58,
                        ADR-0033): wait until the next deadline, whole milliseconds rounded up as the
                        run loop's wait was (not std::this_thread: on this toolchain it sleeps in
                        15.6 ms steps whatever the timer resolution, measured). With no deadline at
                        all the pass ends at once, as the run loop returned at once with nothing to
                        wait on.
                */
                if (haveWake) {
                    const double remaining = std::chrono::duration<double>(wake - std::chrono::steady_clock::now()).count();
                    if (remaining > 0.0) {
#if OOLITE_WINDOWS
                        Sleep((DWORD)ceil(remaining * 1000.0));
#else
                        std::this_thread::sleep_for(std::chrono::milliseconds((long long)ceil(remaining * 1000.0)));
#endif
                    }
                }
            }
        }
    }
}

// The Mac-only methods are in the GameController (MacOSX) category at the end of the file.
// -snapshotsURLCreatingIfNeeded: is Mac-only: nothing on SDL called it (bead oo-3rb.13).
#if !OOLITE_MAC_COCOA_UI && !OOLITE_SDL
#error Unknown environment!
#endif

- (void)cxx_logProgress:(const std::string&)message
{
    if (![UNIVERSE doingStartUp])
        return;

#if OOLITE_MAC_COCOA_UI
    [splashProgressTextField setStringValue:oo::NSStringFrom(message)];
    [splashProgressTextField display];
#endif
    if (!message.empty()) {
        OO_LOG("startup.progress", "===== [{:.2f} s] {}", oo::date::monotonicSeconds() - _splashStart, message);
    }
}

#if OO_DEBUG
#if !OOLITE_MAC_COCOA_UI // the Mac arms are in GameController (MacOSX) at the end of the file
- (BOOL)debugMessageTrackingIsOn
{
    return oo::log::willDisplay("startup.progress");
}

- (std::string)cxx_debugMessageCurrentString
{
    return "";
}
#endif

- (void)cxx_debugLogProgress:(const std::string&)message
{
    [self cxx_logProgress:message];
}

namespace {
std::vector<std::string> sMessageStack;
}

- (void)cxx_debugPushProgressMessage:(const std::string&)message
{
    if ([self debugMessageTrackingIsOn]) {
        sMessageStack.push_back([self cxx_debugMessageCurrentString]);
        [self cxx_debugLogProgress:message];
    }

    oo::log::indentIf("startup.progress");
}

- (void)debugPopProgressMessage
{
    oo::log::outdentIf("startup.progress");

    if (!sMessageStack.empty()) {
        const std::string message = sMessageStack.back();
        if (!message.empty())
            [self cxx_logProgress:message];
        sMessageStack.pop_back();
    }
}

#endif

- (void)endSplashScreen
{
    oo::log::logger().setDisplay("startup.progress", false);

#if OOLITE_MAC_COCOA_UI
    // These views will be released when we replace the content view.
    splashProgressTextField = nil;
    splashView = nil;

    [gameWindow setAcceptsMouseMovedEvents:YES];
    [gameWindow setContentView:gameView];
    [gameWindow makeFirstResponder:gameView];
#elif OOLITE_SDL
    [gameView endSplashScreen];
#endif
}

#if OOLITE_SDL
#include <SDL3/SDL_init.h>

- (void)cxx_exitAppWithContext:(const std::string&)context
{
    OO_LOG("exit.context", "Exiting: {}.", context);
#if (OOLITE_SDL && defined(OO_DEBUG_MONITOR_ENABLED))
    [[OODebugMonitor sharedDebugMonitor] applicationWillTerminate];
#endif
#if OOLITE_WINDOWS
    // This should not be required normally but we have to ensure that
    // desktop resolution is restored also on some Intel cards on Win10
    if (![gameView atDesktopResolution]) {
        OO_LOG("gameController.exitApp", "{}", "Restoring desktop resolution.");
        ChangeDisplaySettingsEx(NULL, NULL, NULL, 0, NULL);
    }
#endif
    oo::Defaults::standard().synchronize();
    OO_LOG("gameController.exitApp", "{}", ".GNUstepDefaults synchronized.");
#ifndef NDEBUG
    // Leak check: tears down the JavaScript runtime and logs any objects still alive.
    [[OOJavaScriptEngine sharedEngine] shutDown];
#endif
    OOLoggingTerminate();
    SDL_Quit();
    if (OOOpenALController* controller = OOOpenALController::sharedController())
        controller->shutdown();
    exit(0);
}

#elif !OOLITE_MAC_COCOA_UI
#error Unknown environment!
#endif

- (void)exitAppCommandQ
{
    [self cxx_exitAppWithContext:"Command-Q"];
}

- (void)windowDidResize
{
    [gameView updateScreen];
}

- (std::optional<std::string>)cxx_playerFileToLoad
{
    return playerFileToLoad;
}

- (void)cxx_setPlayerFileToLoad:(const std::string&)filename
{
    playerFileToLoad = std::nullopt;
    if (oo::str::lowercase(oo::str::pathExtension(filename)) == "oolite-save")
        playerFileToLoad = filename;
}

- (std::optional<std::string>)cxx_playerFileDirectory
{
    if (!playerFileDirectory.has_value()) {
        // save-directory via oo::Defaults (ADR-0032 / oo-mwo0 shared store).
        playerFileDirectory = oo::Defaults::standard().stringForKey("save-directory");
        if (playerFileDirectory.has_value() && !oo::fs::fileExists(oo::fs::pathFromUTF8(*playerFileDirectory))) {
            playerFileDirectory = std::nullopt;
        }
        // -[defaultCommanderPath]: OO_SAVEDIR or ~/oolite-saves, create if missing, else home.
        if (!playerFileDirectory.has_value()) {
            const oo::ResourcePaths paths = oo::ResourcePaths::current();
            const oo::fs::Path savedir = paths.saveDirectory();
            const oo::fs::FileType type = oo::fs::fileType(savedir);
            if (type == oo::fs::FileType::none) {
                if (oo::fs::createDirectories(savedir)) {
                    playerFileDirectory = oo::fs::utf8String(savedir);
                } else {
                    OO_LOG_ERR("savedGame.defaultPath.create.failed", "Unable to create '{}'. Saved games will go to the home directory.", oo::fs::utf8String(savedir));
                    playerFileDirectory = oo::fs::utf8String(paths.homeDirectory());
                }
            } else if (type != oo::fs::FileType::directory) {
                OO_LOG_ERR("savedGame.defaultPath.notDirectory", "'{}' is not a directory, saved games will go to the home directory.", oo::fs::utf8String(savedir));
                playerFileDirectory = oo::fs::utf8String(paths.homeDirectory());
            } else {
                playerFileDirectory = oo::fs::utf8String(savedir);
            }
        }
    }

    return playerFileDirectory;
}

- (void)cxx_setPlayerFileDirectory:(const std::optional<std::string>&)filename
{
    std::optional<std::string> directory = filename;
    if (directory.has_value() && oo::str::lowercase(oo::str::pathExtension(*directory)) == "oolite-save") {
        directory = oo::str::deletingLastPathComponent(*directory);
    }

    playerFileDirectory = directory;
    if (directory.has_value())
        oo::Defaults::standard().setObject("save-directory", oo::PList(*directory));
    else
        oo::Defaults::standard().removeObject("save-directory");
}

- (void)cxx_reportUnhandledStartupExceptionName:(const std::string&)name reason:(const std::optional<std::string>&)reason
{
    // %@ of a nil reason printed "(null)", as NSStringOrNil's nil still does.
    OO_LOG("startup.exception", "***** Unhandled exception during startup: {} ({}).", name, reason.value_or("(null)"));

#if OOLITE_MAC_COCOA_UI
    // Display an error alert.
    // TODO: provide better information on reporting bugs in the manual, and refer to it here.
    NSRunCriticalAlertPanel(@"Oolite failed to start up, because an unhandled exception occurred.", @"An exception of type %@ occurred. If this problem persists, please file a bug report.", @"OK", NULL, NULL, oo::NSStringFrom(name));
#endif
}

#ifndef NDEBUG
/*	This method exists purely to suppress Clang static analyzer warnings that
        these ivars are unused (but may be used by categories, which they are).
*/
- (BOOL)suppressClangStuff
{
    return pauseSelector && pauseTarget;
}
#endif

@end

#if OOLITE_MAC_COCOA_UI

/*	The Mac-only methods, gathered verbatim into one category at the end of the file by bead
        oo-q9l2w (a behaviour-neutral pre-split for the Phase 3 conversion; the Windows/SDL translation
        unit is token-for-token unchanged): the menu actions, the snapshots-folder and add-ons helpers,
        the dock menu, -awakeFromNib, the application-delegate methods, and the Mac arms of
        -performGameTick:, -cxx_exitAppWithContext: and the two debug-progress accessors. The fleet never
        compiles this block and does not convert it: Phase 5 writes the Mac layer again (ADR-0009;
        ADR-0056 amendment oo-bgmb item 2; ADR-0043 item 18(b); docs/phases/3-slices/GameController.md).
*/
@implementation GameController (MacOSX)

- (void)performGameTick:(id)sender
{
    [gameView pollControls];
    [self doPerformGameTick];
}

- (void)recenterVirtualJoystick
{
    // FIXME: does this really need to be spread across GameController and MyOpenGLView? -- Ahruman 2011-01-22
    my_mouse_x = my_mouse_y = 0; // center mouse
    [gameView setVirtualJoystick:0.0:0.0];
}

- (IBAction)showLogAction:sender
{
    [[NSWorkspace sharedWorkspace] openFile:[oo::NSStringOrNil(cxx_OOLogHandlerGetLogBasePath()) stringByAppendingPathComponent:@"Previous.log"]];
}

- (IBAction)showLogFolderAction:sender
{
    [[NSWorkspace sharedWorkspace] openFile:oo::NSStringOrNil(cxx_OOLogHandlerGetLogBasePath())];
}

// Helpers to allow -snapshotsURLCreatingIfNeeded: code to be identical here and in dock tile plug-in.
// Same domain as the dock tile plug-in: oo::Defaults (backed by the shared store; ADR-0032 / oo-mwo0).
static id GetPreference(const std::string& key)
{
    return oo::ObjectFromPList(oo::Defaults::standard().object(key));
}

static void SetPreference(const std::string& key, id value)
{
    oo::Defaults::standard().setObject(key, oo::PListFrom(value));
}

static void RemovePreference(const std::string& key)
{
    oo::Defaults::standard().removeObject(key);
}

#define kSnapshotsDirRefKey "snapshots-directory-reference"
#define kSnapshotsDirNameKey "snapshots-directory-name"

- (NSURL*)snapshotsURLCreatingIfNeeded:(BOOL)create
{
    BOOL stale = NO;
    // A JAPersistentFileReference dictionary (not migrated): passed between its functions as is.
    id snapshotDirDict = GetPreference(kSnapshotsDirRefKey);
    NSURL* url = nil;
    const std::string name = OO_DESC("snapshots-directory-name-mac");

    if (!oo::IsNSDictionary(snapshotDirDict))
        snapshotDirDict = nil;
    if (snapshotDirDict != nil) {
        url = JAURLFromPersistentFileReference(snapshotDirDict, kJAPersistentFileReferenceWithoutUI | kJAPersistentFileReferenceWithoutMounting, &stale);
        if (url != nil) {
            const std::string existingName = oo::str::lastPathComponent(oo::StdString([url path]));
            if (oo::str::caseInsensitiveCompare(existingName, name) != 0) {
                // Check name from previous access, because we might have changed localizations.
                id originalOldName = GetPreference(kSnapshotsDirNameKey);
                if (!oo::IsNSString(originalOldName) || oo::str::caseInsensitiveCompare(existingName, oo::StdString(originalOldName)) != 0) {
                    url = nil;
                }
            }

            // did we put the old directory in the trash?
            Boolean inTrash = false;
            const UInt8* utfPath = (const UInt8*)[[url path] UTF8String];

            OSStatus err = DetermineIfPathIsEnclosedByFolder(kOnAppropriateDisk, kTrashFolderType, utfPath, false, &inTrash);
            // if so, create a new directory.
            if (err == noErr && inTrash == true)
                url = nil;
        }
    }

    if (url == nil) {
        std::optional<std::string> path;
        const std::vector<std::string> searchPaths = oo::StringsFrom(NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES));
        if (!searchPaths.empty()) {
            path = oo::str::appendingPathComponent(searchPaths[0], name);
        }
        url = [NSURL fileURLWithPath:oo::NSStringOrNil(path)];

        if (url != nil) {
            stale = YES;
            if (create) {
                if (!oo::fs::fileExists(oo::fs::pathFromUTF8(*path))) {
                    (void)oo::fs::createDirectories(oo::fs::pathFromUTF8(*path));
                }
            }
        }
    }

    if (stale) {
        snapshotDirDict = JAPersistentFileReferenceFromURL(url);
        if (snapshotDirDict != nil) {
            SetPreference(kSnapshotsDirRefKey, snapshotDirDict);
            SetPreference(kSnapshotsDirNameKey, [[url path] lastPathComponent]);
        } else {
            RemovePreference(kSnapshotsDirRefKey);
        }
    }

    return url;
}

- (IBAction)showSnapshotsAction:sender
{
    [[NSWorkspace sharedWorkspace] openURL:[self snapshotsURLCreatingIfNeeded:YES]];
}

- (IBAction)showAddOnsAction:sender
{
    const std::vector<std::string> paths = [ResourceManager cxx_userRootPaths];

    // Look for an AddOns directory that actually contains some AddOns.
    for (const std::string& path : paths) {
        if ([self cxx_addOnsExistAtPath:path]) {
            [self cxx_openPath:path];
            return;
        }
    }

    // If that failed, look for an AddOns directory that actually exists.
    for (const std::string& path : paths) {
        if ([self cxx_isDirectoryAtPath:path]) {
            [self cxx_openPath:path];
            return;
        }
    }

    // None found, create the default path.
    (void)oo::fs::createDirectories(oo::fs::pathFromUTF8(paths.front()));
    [self cxx_openPath:paths.front()];
}

- (BOOL)cxx_isDirectoryAtPath:(const std::string&)path
{
    return oo::fs::isDirectory(oo::fs::pathFromUTF8(path));
}

- (BOOL)cxx_addOnsExistAtPath:(const std::string&)path
{
    if (![self cxx_isDirectoryAtPath:path])
        return NO;

    NSWorkspace* workspace = NSWorkspace.sharedWorkspace;
    // Recursive walk in OS enumeration order (first match wins; not sorted), as the Foundation
    // directory enumerator did.
    const oo::fs::Path root = oo::fs::pathFromUTF8(path);
    std::error_code ec;
    for (std::filesystem::recursive_directory_iterator it(root, ec), end; !ec && it != end; it.increment(ec)) {
        const std::string fullPath = oo::fs::utf8String(it->path());
        const std::optional<std::string> type = oo::OptionalString([workspace typeOfFile:oo::NSStringFrom(fullPath) error:NULL]);
        if ([workspace type:oo::NSStringOrNil(type) conformsToType:@"org.aegidian.oolite.expansion"])
            return YES;
    }

    return NO;
}

- (void)cxx_openPath:(const std::string&)path
{
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:oo::NSStringFrom(path)]];
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem
{
    SEL action = menuItem.action;

    if (action == @selector(showLogAction:)) {
        // the first path is always Resources
        const std::optional<std::string> base = cxx_OOLogHandlerGetLogBasePath();
        if (!base.has_value())
            return NO;
        return oo::fs::fileExists(oo::fs::pathFromUTF8(oo::str::appendingPathComponent(*base, "Previous.log")));
    }

    if (action == @selector(showAddOnsAction:)) {
        // Always enabled in unrestricted mode, to allow users to add OXPs more easily.
        return [ResourceManager cxx_useAddOns].has_value();
    }

    if (action == @selector(showSnapshotsAction:)) {
        const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(oo::StdString([self snapshotsURLCreatingIfNeeded:NO].path)));
        if (type == oo::fs::FileType::none)
            return NO;
        return type == oo::fs::FileType::directory;
    }

    if (action == @selector(toggleFullScreenAction:)) {
        if (_fullScreenController.fullScreenMode) {
            // NOTE: not DESC, because menu titles are not generally localizable.
            menuItem.title = NSLocalizedString(@"Exit Full Screen", NULL);
        } else {
            menuItem.title = NSLocalizedString(@"Enter Full Screen", NULL);
        }
    }

    // default
    return YES;
}

- (NSMenu*)applicationDockMenu:(NSApplication*)sender
{
    return dockMenu;
}

#if OO_DEBUG
- (BOOL)debugMessageTrackingIsOn
{
    return splashProgressTextField != nil;
}

- (std::string)cxx_debugMessageCurrentString
{
    return oo::StdString([splashProgressTextField stringValue]);
}
#endif

// NIB methods
- (void)awakeFromNib
{
    // Set contents of Help window
    const oo::fs::Path readMePath = oo::ResourcePaths::current().builtInResourcesDirectory() / "OoliteReadMe.pdf";
    const std::optional<std::string> path = oo::fs::fileExists(readMePath) ? std::optional<std::string>(oo::fs::utf8String(readMePath)) : std::nullopt;
    if (path.has_value()) {
        PDFDocument* document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:oo::NSStringFrom(*path)]];
        [helpView setDocument:document];
        [document release];
    }
    [helpView setBackgroundColor:[NSColor whiteColor]];
}

// delegate methods
- (BOOL)application:(NSApplication*)theApplication openFile:(id)filename // NSApplicationDelegate's selector, shared with AppKit (proposed ADR-0043): an Objective-C string
{
    const std::string path = oo::StdString(filename);
    const std::string extension = oo::str::pathExtension(path);
    if (extension == "oolite-save") {
        [self cxx_setPlayerFileToLoad:path];
        [self cxx_setPlayerFileDirectory:oo::OptionalString(filename)];
        return YES;
    }
    if (extension == "oxp") {
        if (oo::fs::isDirectory(oo::fs::pathFromUTF8(path))) {
            expansionPathsToInclude.push_back(path);
            return YES;
        }
    }
    return NO;
}

- (void)cxx_exitAppWithContext:(const std::string&)context
{
    [gameView.window orderOut:nil];
    [(OoliteApp*)NSApp setExitContext:oo::NSStringFrom(context)];
    [NSApp terminate:self];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
    [[OOCacheManager sharedCache] finishOngoingFlush];
    OOLoggingTerminate();
    return NSTerminateNow;
}

@end

static void SetUpSparkle(void)
{
#define FEED_URL_BASE "http://www.oolite.org/updates/"
#define TEST_RELEASE_FEED_NAME "oolite-mac-test-release-appcast.xml"
#define DEPLOYMENT_FEED_NAME "oolite-mac-appcast.xml"

#define TEST_RELEASE_FEED_URL (@FEED_URL_BASE TEST_RELEASE_FEED_NAME)
#define DEPLOYMENT_FEED_URL (@FEED_URL_BASE DEPLOYMENT_FEED_NAME)

// Default to test releases in test release or debug builds, and stable releases for deployment builds.
#ifdef NDEBUG
#define DEFAULT_TEST_RELEASE 0
#else
#define DEFAULT_TEST_RELEASE 1
#endif

    BOOL useTestReleases = oo::Defaults::standard().object("use-test-release-updates").isNull()
        ? DEFAULT_TEST_RELEASE
        : oo::Defaults::standard().boolForKey("use-test-release-updates");

    SUUpdater* updater = [SUUpdater sharedUpdater];
    [updater setFeedURL:[NSURL URLWithString:useTestReleases ? TEST_RELEASE_FEED_URL : DEPLOYMENT_FEED_URL]];
}

#endif
