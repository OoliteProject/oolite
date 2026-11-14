/*

GameController+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-zkpmt): the Objective-C GameController, a façade over the
C++ cxx::GameController (GameController.h), for the code that is not converted yet: its callers
(34 files message it by selector), the units of slices 2 and 3 of GameController.mm
(docs/phases/3-slices/GameController.md: the frame loop and deferred calls; start-up, splash and
progress messages, exit and the player file), and the FullScreen category
(SDL/GameController+SDLFullScreen.mm, bead oo-qinv; Core/GameController+FullScreen.mm, Mac-only),
which stay Objective-C methods of this façade until their own beads. Its interface is the one
GameController.h declared before the conversion, copied exactly (same selectors, same types): the
slice 1 selectors, declared by the OOObjCBridge category below, forward to their C++ members in one
line each (GameController+ObjCBridge.mm); the rest stay in the class's @interface, which
GameController.mm's @implementation implements as before (ADR-0056 amendment oo-zkpmt); the
FullScreen category is unchanged. Those methods read and write the state through the @public
_cxxController (amendment oo-bj8 item 2). Imported as the last line of GameController.h; do not
import it directly.

        a caller that is                       holds / passes                       crosses with
        -------------------------------------  -----------------------------------  ------------------------
        still Objective-C                      GameController * (this façade)       nothing: messages as before
        converted (C++)                        cxx::GameController * (the singleton)
          handing the controller to Objective-C                                     oo::ToObjC(controller)
          taking it from Objective-C                                                oo::ToCxx(objcController)

The controller is a singleton: +sharedController answers one façade for the life of the process
(proposed ADR-0056 amendment oo-r7m0, item 5). Never add to this file; converted code does not
message the façade. Deleted by its deletion bead once slices 2 and 3 and the FullScreen category
are converted and no file outside GameController.* names the Objective-C class.

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

#ifndef GAMECONTROLLER_OBJCBRIDGE_H
#define GAMECONTROLLER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface GameController : OOObject {
@public
    oo::Ref<cxx::GameController> _cxxController;
}

- (void)applicationDidFinishLaunching;

#if OOLITE_MAC_COCOA_UI
- (IBAction)showLogAction:(id)sender;
- (IBAction)showLogFolderAction:(id)sender;
- (IBAction)showSnapshotsAction:(id)sender;
- (IBAction)showAddOnsAction:(id)sender;
- (void)recenterVirtualJoystick;
// -snapshotsURLCreatingIfNeeded: is not redeclared here: only the fenced Mac category in
// GameController.mm sends it, after defining it, and its Foundation return type would be a new
// deny-list hit in this new file (the guardrails' file-split limitation).
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

- (void)windowDidResize;

@end

// The slice 1 selectors of the old interface, forwarded to their C++ members by
// GameController+ObjCBridge.mm. A category, so that GameController.mm's @implementation of the
// class (slices 2 and 3, still Objective-C) keeps its name and is complete.
@interface GameController (OOObjCBridge)

+ (GameController*)sharedController;

- (id)init; // a controller of its own, as main.mm makes it (the old -init)

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

- (MyOpenGLView*)gameView;
- (void)setGameView:(MyOpenGLView*)view;

// Slice 2 (bead oo-hn0fw).
- (void)performGameTick:(id)sender;

- (void)startAnimationTimer;
- (void)stopAnimationTimer;

/*	Fire whatever is due now, the game tick first, then one deferred call:
        what the run loop's -limitDateForMode: did for the game while its tick and
        deferred calls were run-loop timers. For code that must let the game tick
        while it blocks the frame loop (the OXZ download callback). See proposed
        ADR-0033 and ADR-0040.
*/
- (void)fireDueTimers;

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

/*	[target performSelector:selector withObject:argument] for a deferred call (OOScheduleDeferredCall):
        false when it raised an OOException, which is caught and its name and reason (the exception's own strings, alive until the pool drains) written out (the
        caller logs them as the Foundation timer did); anything else propagates. The free function
        FireOneDueDeferredCall() calls it (ADR-0056 amendment oo-9ht.139 item 3: its @try/@catch and send
        stay Objective-C here).
*/
bool GameControllerPerformSelectorWithObject(id target, SEL selector, id argument, const char** outName, const char** outReason);

namespace oo {

// The controller's Objective-C façade: its live one, else a new one; autoreleased. nil for null.
GameController* ToObjC(cxx::GameController* controller);

// The C++ controller behind a façade, borrowed; null for nil.
cxx::GameController* ToCxx(GameController* controller);

} // namespace oo

#endif // GAMECONTROLLER_OBJCBRIDGE_H
