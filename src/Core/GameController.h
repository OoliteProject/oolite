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


#pragma once

#include "OOCocoa.h"
#include "oofnd/objc/OOObject.h"
#include "OOFunctionAttributes.h"
#include "OOFullScreenController.h"
#include "OOMouseInteractionMode.h"

#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Ref.hpp"

#include <functional>
#include <optional>
#include <string>
#include <vector>


#if OOLITE_MAC_OS_X
#import <Quartz/Quartz.h>	// For PDFKit.
#endif

#define MINIMUM_GAME_TICK		0.25
// * reduced from 0.5s for tgape * //

#define MINIMUM_ANIMATION_TICK	0.0041667
// 1.0 / (desired framerate cap)


class MyOpenGLView;
class OOFullScreenController;	// C++ since bead oo-bgmb


// TEMP: whether to use separate OOFullScreenController object, will hopefully be used for all builds soon.
#define OO_USE_FULLSCREEN_CONTROLLER	OOLITE_MAC_OS_X


/*	The application controller (bead oo-zkpmt, slice 1 of docs/phases/3-slices/GameController.md):
	the class shell, its state and accessors; the frame loop and deferred calls (slice 2, bead
	oo-hn0fw); start-up, splash and progress messages, exit and the player file (slice 3, bead
	oo-5ah4k); the SDL full-screen members (SDL/GameController+SDLFullScreen.mm, bead oo-qinv), the
	former FullScreen category. The Mac FullScreen category (Core/GameController+FullScreen.mm) and
	the Mac category at the end of GameController.mm are not compiled and are left as they were
	(Phase 5). A global class since the Objective-C façade was deleted (bead oo-9ht.164).
*/
class GameController : public oo::RefCounted
{
public:
	// The shared controller, made on first use; borrowed, never released (proposed ADR-0056
	// amendment oo-r7m0).
	static GameController *sharedController();

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
	void setMouseInteractionModeForFlight();	// Chooses mouse control mode appropriately.
	void setMouseInteractionModeForUIWithMouseInteraction(bool interaction);

	::MyOpenGLView *gameView();
	void setGameView(::MyOpenGLView *view);

#ifndef NDEBUG
	bool suppressClangStuff();
#endif

	// The frame loop (bead oo-hn0fw, slice 2).
#if !OOLITE_MAC_OS_X
	void performGameTick();	// took the unused sender, an Objective-C id, until bead oo-dbz.2
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

	void exitAppWithContext(const std::string &context);
	void exitAppCommandQ();

	// nullopt: no saved game to load (was nil).
	std::optional<std::string> playerFileToLoad();
	void setPlayerFileToLoad(const std::string &filename);	// kept only for a .oolite-save path

	// nullopt: no save directory (was nil). A nullopt argument clears it and the save-directory
	// default, and the next playerFileDirectory() looks it up again (as nil did; "" does not).
	std::optional<std::string> playerFileDirectory();
	void setPlayerFileDirectory(const std::optional<std::string> &filename);

	void loadPlayerIfRequired();

	void beginSplashScreen();
	void logProgress(const std::string &message);
#if OO_DEBUG
	// These take the formatted message, as do OO_DEBUG_PROGRESS / OO_DEBUG_PUSH_PROGRESS below.
	void debugLogProgress(const std::string &message);
	void debugPushProgressMessage(const std::string &message);
	void debugPopProgressMessage();
#endif
	void endSplashScreen();

	void windowDidResize();

#if OOLITE_SDL
	// Full screen (bead oo-qinv, SDL/GameController+SDLFullScreen.mm): the former FullScreen
	// category. -displayModes is getDisplayModes(), as the state has a displayModes (ADR-0056
	// amendment oo-862e item 1).
	void setUpDisplayModes();	// internal use only
	void setFullScreenMode(bool fsm);
	void exitFullScreenMode();	// FIXME: should be setFullScreenMode(false)
	bool inFullScreenMode();
	bool setDisplayWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh);
	oo::PList findDisplayModeForWidth(unsigned int d_width, unsigned int d_height, unsigned int d_refresh);	// a mode dictionary; null: none
	oo::PList getDisplayModes();	// an array of mode dictionaries
	NSUInteger indexOfCurrentDisplayMode();
	void pauseFullScreenModeToPerform(const char *selectorName, oo::RefCounted *target);	// by name since bead oo-xu228.3 (was a SEL); the target C++ since bead oo-4aq6a.4 (was an object on the Objective-C root)
#endif

	// tests/unit/core/test_GameController.mm reads and sets the state below (bead oo-auu6o).
	friend struct GameControllerTestAccess;

private:
	// Internal: the state, read and written by the members above (and by the fenced Mac
	// categories, not compiled). Private again since bead oo-auu6o (public from oo-9ht.164 to it).
#if OOLITE_MAC_OS_X
	NSTextField				*splashProgressTextField = {};
	NSView					*splashView = {};
	NSWindow				*gameWindow = {};
	PDFView					*helpView = {};
	NSMenu					*dockMenu = {};
#endif
	
	::MyOpenGLView			*_gameView = {};	// retained; was gameView, named like its getter
	
	NSTimeInterval			last_timeInterval = {};
	double					delta_t = {};
	
	int						my_mouse_x = {}, my_mouse_y = {};

	std::optional<std::string>	_playerFileDirectory;	// nullopt: not looked up yet, or none (was nil); named so -cxx_playerFileDirectory's member can be playerFileDirectory()
	std::optional<std::string>	_playerFileToLoad;		// nullopt: none (was nil); named so -cxx_playerFileToLoad's member can be playerFileToLoad()
	std::vector<std::string>	expansionPathsToInclude;	// expansion folders opened with the application (Mac)
	
	NSTimeInterval			_animationTimerInterval = {};
	
	NSTimeInterval			_splashStart = {};	// oo::date::monotonicSeconds() at start-up
	
	std::string				pauseSelector = {};	// the selector's name (a SEL until bead oo-xu228.3); "" none
	oo::RefCounted			*pauseTarget = {};	// not retained, as before; never performed on SDL (an OOObject * until bead oo-4aq6a.4)
	
	bool					gameIsPaused = {};
	
	OOMouseInteractionMode	_mouseMode = {};
	OOMouseInteractionMode	_resumeMode = {};
	
// Fullscreen mode stuff.
#if OO_USE_FULLSCREEN_CONTROLLER
	OOFullScreenController	*_fullScreenController = {};
#elif OOLITE_SDL
	NSRect					fsGeometry = {};
	::MyOpenGLView			*switchView = {};
	
	oo::PList::Array		displayModes;			// the usable screen modes, each a mode dictionary
	
	unsigned int			width = {}, height = {};
	unsigned int			refresh = {};
	bool					fullscreen = {};
	oo::PList				originalDisplayMode;	// a mode dictionary; null: none (was nil)
	oo::PList				fullscreenDisplayMode;	// a mode dictionary; null: none (was nil)
	
	bool					stayInFullScreenMode = {};
	bool					_finishedLaunching = {};
#endif

private:
	void doPerformGameTick();
	void performGameTickIfDue();
	void fireDueDeadlines();
	void runFrameLoop();

	void reportUnhandledStartupExceptionName(const std::string &name, const std::optional<std::string> &reason);	// reason nullopt: none (was nil)
#if OO_DEBUG && !OOLITE_MAC_OS_X
	bool debugMessageTrackingIsOn();
	std::string debugMessageCurrentString();
#endif
};



/*	OOScheduleDeferredCall(call, delay): what Foundation's performer-after-delay did (bead oo-3rb.57,
	proposed ADR-0040), for a C++ call (bead oo-pvhrh, ADR-0056 amendment oo-pvhrh). call() runs on the
	first frame-loop pass at least delay seconds from now (a delay <= 0 is 0.0001 s), after that pass's
	tick, and is destroyed after it (what it captures is kept alive until then, as the performer
	retained its target and argument). Due calls fire in the order they were scheduled, at most two
	per pass, as the run loop fired its timers. Main thread only: a call scheduled on another thread
	never fires, as a performer on that thread's never-run run loop did not. An OOException from it is
	caught and logged as the perform's was, and the call is then never destroyed, as the performer
	leaked its target. (The Objective-C form, of a target, a selector and an argument, was deleted by
	bead oo-4aq6a.4: no caller was left.)
*/
void OOScheduleDeferredCall(std::function<void()> call, NSTimeInterval delay);


#if OO_DEBUG
#define OO_DEBUG_PROGRESS(message)		::GameController::sharedController()->debugLogProgress(message)
#define OO_DEBUG_PUSH_PROGRESS(message)	::GameController::sharedController()->debugPushProgressMessage(message)
#define OO_DEBUG_POP_PROGRESS()		::GameController::sharedController()->debugPopProgressMessage()
#else
#define OO_DEBUG_PROGRESS(message)		do {} while (0)
#define OO_DEBUG_PUSH_PROGRESS(message)	do {} while (0)
#define OO_DEBUG_POP_PROGRESS()		do {} while (0)
#endif


