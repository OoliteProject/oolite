/*	test_GameController.mm
	Unit tests for GameController (src/Core/GameController.h): bead oo-zkpmt, slice 1 of the Phase 3
	slice plan docs/phases/3-slices/GameController.md (the class shell: the singleton, pause, EcoQoS,
	the mouse interaction modes, the game view and the launch flag), in the house style of the
	OOColor exemplar (proposed ADR-0056).

	The controller is the application's process-wide singleton. It needs the JavaScript engine (its
	pause events are named by OOJSID) and the player (PLAYER), so the test links every game object
	but main's (tests/unit/core/meson.build entry ['*'], amendment oo-44gg), defines gDebugFlags,
	points the user's home (HOMEPATH: the defaults) at a scratch folder, and stands in a recording
	object for the player and another for the game view (as test_DustEntity does for the player).
	The universe is nil, so what the controller sends it is a message to nil, as before the game
	starts. Nothing is drawn and no window is opened.

	It pins what the controller did before the conversion: one shared object; the launch flag; the
	game view it keeps (retained) and tells about itself; the mouse interaction modes and the view's
	notes of each change; pause and resume (the mode they save and restore, the player's script
	events, and the process priority class EcoQoS sets on Windows); and, through the façade, the
	full-screen category (still Objective-C, reading the state the class shell now holds) and the
	player-file paths of slice 3. The expectations were written against the Objective-C API and run
	on the unconverted class first; the façade contract (identity both ways, the C++ members, the
	state the façade's methods read) came with the conversion.
	Run: bash tools/check-core-tests.sh test_GameController
*/

#import "GameController.h"
#import "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#import "OOJavaScriptEngine.h"
#import "OOJSPropID.h"
#import "OOFullScreenController.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/objc/OOException.h"
#include "oofnd/FileSystem.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>
#include <chrono>
#include <thread>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity *gOOPlayer;


// PLAYER: records the script events it is sent and answers whether mouse control is on (C++ since
// bead oo-9ht.177 deleted the Objective-C player).
class TestPlayer : public PlayerEntity
{
public:
	std::vector<OOJSPropID>				_events;
	BOOL								_mouseControlOn = NO;

	using PlayerEntity::doScriptEvent;
	void doScriptEvent(OOJSPropID message) override				{ _events.push_back(message); }
	bool isMouseControlOn() override							{ return _mouseControlOn; }
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	@autoreleasepool
	{
		[oo::NewEntityFacade(player) retain];
	}
	return player.get();
}


// The game view: records the controller it is given and the mode changes it is told of, and
// answers the screen modes the full-screen category asks for.
@interface TestView: OOObject
{
@public
	id									_controller;
	std::vector<std::pair<int, int>>	_modeNotes;
	std::vector<oo::PList>				_screenModes;
	oo::PList							_currentMode;
	BOOL								_inFullScreen;
	int									_splashEnds;
	int									_screenUpdates;
}
@end


@implementation TestView

- (void) setGameController:(id)controller		{ _controller = controller; }
- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
	_modeNotes.push_back({ (int)oldMode, (int)newMode });
}
- (std::vector<oo::PList>) getScreenSizeArray	{ return _screenModes; }
- (oo::PList) currentScreenMode					{ return _currentMode; }
- (NSSize) currentScreenSize					{ return NSMakeSize(0, 0); }
- (BOOL) inFullScreenMode						{ return _inFullScreen; }
- (void) endSplashScreen						{ _splashEnds++; }
- (void) updateScreen							{ _screenUpdates++; }

@end


// A deferred call's target: records the arguments it is sent, and raises on request.
@interface TestTarget: OOObject
{
@public
	std::vector<std::string>	_calls;
}
- (void) record:(id)argument;
- (void) raise:(id)argument;
@end


@implementation TestTarget

- (void) record:(id)argument	{ _calls.push_back(argument != nil ? "arg" : "nil"); }
- (void) raise:(id)argument		{ _calls.push_back("raise"); OORaiseException(OOGenericException, "%s", "deferred call failure"); }

@end


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
TestPlayer *sPlayer = nullptr;


// The scratch home and game folder, the engine and the stand-in player, made once, before the
// controller exists.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-gamecontroller-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	stdfs::current_path(sRoot);
	stdfs::create_directories(sRoot / "Resources");
	OO_CHECK(oo::fs::writeFile(sRoot / "Resources" / "Info-gnustep.plist", oo::Data("{ CFBundleVersion = \"9.9.9-test\"; }", 35), oo::fs::WriteMode::direct).has_value());
	(void)[OOJavaScriptEngine sharedEngine];
	sPlayer = NewTestPlayer<TestPlayer>();	// never released
	gOOPlayer = sPlayer;
}


bool SameId(OOJSPropID a, OOJSPropID b)
{
	return a == b;
}


oo::PList Mode(int width, int height, int refresh)
{
	oo::PList::Dict mode;
	mode[std::string(kOODisplayWidth)] = oo::PList(std::int64_t(width));
	mode[std::string(kOODisplayHeight)] = oo::PList(std::int64_t(height));
	mode[std::string(kOODisplayRefreshRate)] = oo::PList(std::int64_t(refresh));
	return oo::PList(std::move(mode));
}

}	// namespace


OO_TEST(sharedControllerIsOneObject)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		OO_CHECK(controller != nil);
		OO_CHECK([GameController sharedController] == controller);
		OO_CHECK(![controller finishedLaunching]);
		OO_CHECK(![controller isGamePaused]);
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_NO_INTERACTION);
		OO_CHECK([controller gameView] == nil);
		OO_CHECK(![controller cxx_playerFileToLoad].has_value());
	}
}


// main.mm makes the application's controller with alloc/init, apart from +sharedController's:
// once the shared one exists, that raises (and releases the receiver).
OO_TEST(secondControllerRaises)
{
	SetUp();
	@autoreleasepool
	{
		GameController *shared = [GameController sharedController];
		bool raised = false;
		@try
		{
			[[GameController alloc] init];
		}
		@catch (OOException *exception)
		{
			raised = (std::string([exception name]) == OOInternalInconsistencyException);
		}
		OO_CHECK(raised);
		OO_CHECK([GameController sharedController] == shared);
	}
}


OO_TEST(gameViewIsKeptAndToldOfTheController)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		TestView *first = [[TestView alloc] init];
		TestView *second = [[TestView alloc] init];

		[controller setGameView:(MyOpenGLView *)first];
		OO_CHECK([controller gameView] == (MyOpenGLView *)first);
		OO_CHECK(first->_controller == controller);
		OO_CHECK([first retainCount] == 2);	// the controller retains its view

		[controller setGameView:(MyOpenGLView *)second];
		OO_CHECK([controller gameView] == (MyOpenGLView *)second);
		OO_CHECK(second->_controller == controller);
		OO_CHECK([first retainCount] == 1);	// and releases the one it replaces
		OO_CHECK([second retainCount] == 2);

		[controller setGameView:(MyOpenGLView *)first];
		[second release];
		[first release];
	}
}


OO_TEST(mouseInteractionModes)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		TestView *view = (TestView *)[controller gameView];
		OO_CHECK(view != nil);
		view->_modeNotes.clear();

		[controller setMouseInteractionMode:MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL];
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL);
		OO_CHECK_EQ(view->_modeNotes.size(), 1u);
		OO_CHECK(view->_modeNotes.back() == std::make_pair((int)MOUSE_MODE_UI_SCREEN_NO_INTERACTION, (int)MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL));

		// The same mode again changes nothing and tells nobody.
		[controller setMouseInteractionMode:MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL];
		OO_CHECK_EQ(view->_modeNotes.size(), 1u);

		[controller setMouseInteractionModeForUIWithMouseInteraction:YES];
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_WITH_INTERACTION);
		[controller setMouseInteractionModeForUIWithMouseInteraction:NO];
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_NO_INTERACTION);

		// Flight: the player's mouse control chooses the mode.
		sPlayer->_mouseControlOn = YES;
		[controller setMouseInteractionModeForFlight];
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL);
		sPlayer->_mouseControlOn = NO;
		[controller setMouseInteractionModeForFlight];
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL);

		OO_CHECK_EQ(view->_modeNotes.size(), 5u);
		OO_CHECK(view->_modeNotes.back() == std::make_pair((int)MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL, (int)MOUSE_MODE_FLIGHT_NO_MOUSE_CONTROL));
	}
}


OO_TEST(pauseAndResume)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		[controller setMouseInteractionMode:MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL];
		sPlayer->_events.clear();

		[controller setGamePaused:YES];
		OO_CHECK([controller isGamePaused]);
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_NO_INTERACTION);
		OO_CHECK_EQ(sPlayer->_events.size(), 1u);
		OO_CHECK(!sPlayer->_events.empty() && SameId(sPlayer->_events.back(), OOJSID("gamePaused")));
#if OOLITE_WINDOWS
		// EcoQoS (no "ecoqos" default: on): a paused game runs at idle priority.
		OO_CHECK(GetPriorityClass(GetCurrentProcess()) == IDLE_PRIORITY_CLASS);
#endif

		// Pausing a paused game does nothing.
		[controller setGamePaused:YES];
		OO_CHECK_EQ(sPlayer->_events.size(), 1u);

		[controller setGamePaused:NO];
		OO_CHECK(![controller isGamePaused]);
		OO_CHECK([controller mouseInteractionMode] == MOUSE_MODE_FLIGHT_WITH_MOUSE_CONTROL);	// the mode it paused in
		OO_CHECK_EQ(sPlayer->_events.size(), 2u);
		OO_CHECK(sPlayer->_events.size() == 2 && SameId(sPlayer->_events.back(), OOJSID("gameResumed")));
#if OOLITE_WINDOWS
		OO_CHECK(GetPriorityClass(GetCurrentProcess()) == NORMAL_PRIORITY_CLASS);
#endif

		// Resuming a running game does nothing.
		[controller setGamePaused:NO];
		OO_CHECK_EQ(sPlayer->_events.size(), 2u);

#if OOLITE_WINDOWS
		// "ecoqos" off: EcoQoS leaves the priority alone.
		oo::Defaults::standard().setBool("ecoqos", false);
		[controller setEcoQoS:YES];
		OO_CHECK(GetPriorityClass(GetCurrentProcess()) == NORMAL_PRIORITY_CLASS);
		oo::Defaults::standard().removeObject("ecoqos");
#endif
	}
}


// The full-screen category (SDL/GameController+SDLFullScreen.mm): still Objective-C, on the state
// the class keeps.
OO_TEST(fullScreenDisplayModes)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		TestView *view = (TestView *)[controller gameView];
		view->_screenModes = { Mode(320, 200, 60), Mode(1024, 768, 60), Mode(1920, 1080, 60), Mode(1920, 1080, 144), Mode(8000, 5000, 30) };
		view->_currentMode = Mode(1920, 1080, 60);
		[controller setUpDisplayModes];

		// The modes the game can use, in the screen's order.
		const oo::PList modes = [controller displayModes];
		OO_CHECK_EQ(modes.count(), 3u);
		OO_CHECK([controller indexOfCurrentDisplayMode] == 1u);
		OO_CHECK([controller findDisplayModeForWidth:1920 Height:1080 Refresh:144] == Mode(1920, 1080, 144));
		OO_CHECK([controller findDisplayModeForWidth:320 Height:200 Refresh:60].isNull());

		OO_CHECK([controller setDisplayWidth:1024 Height:768 Refresh:60]);
		OO_CHECK([controller indexOfCurrentDisplayMode] == 0u);
		OO_CHECK_EQ(oo::Defaults::standard().integerForKey("display_width"), 1024);
		OO_CHECK_EQ(oo::Defaults::standard().integerForKey("display_height"), 768);
		OO_CHECK(![controller setDisplayWidth:800 Height:600 Refresh:60]);
		OO_CHECK([controller indexOfCurrentDisplayMode] == 0u);

		view->_inFullScreen = YES;
		OO_CHECK([controller inFullScreenMode]);
		view->_inFullScreen = NO;
		OO_CHECK(![controller inFullScreenMode]);

		oo::Defaults::standard().setBool("fullscreen", true);
		[controller exitFullScreenMode];
		OO_CHECK(!oo::Defaults::standard().boolForKey("fullscreen"));
	}
}


// The full-screen members (bead oo-qinv): the C++ calls give what the façade's selectors give, on
// the same state, and pausing full-screen mode records the call to make and leaves full screen.
OO_TEST(fullScreenMembers)
{
	SetUp();
	@autoreleasepool
	{
		GameController *facade = [GameController sharedController];
		cxx::GameController *controller = cxx::GameController::sharedController();
		TestView *view = (TestView *)controller->gameView();
		view->_screenModes = { Mode(640, 480, 60), Mode(1280, 720, 60), Mode(1280, 720, 75), Mode(9000, 9000, 60) };
		view->_currentMode = Mode(1280, 720, 75);
		controller->setUpDisplayModes();

		OO_CHECK_EQ(controller->getDisplayModes().count(), 3u);
		OO_CHECK([facade displayModes] == controller->getDisplayModes());
		OO_CHECK_EQ(controller->width, 1280u);
		OO_CHECK_EQ(controller->height, 720u);
		OO_CHECK_EQ(controller->refresh, 75u);
		OO_CHECK(controller->indexOfCurrentDisplayMode() == 2u);
		OO_CHECK([facade indexOfCurrentDisplayMode] == 2u);
		OO_CHECK(controller->findDisplayModeForWidth(640, 480, 60) == Mode(640, 480, 60));
		OO_CHECK(controller->findDisplayModeForWidth(9000, 9000, 60).isNull());

		OO_CHECK(controller->setDisplayWidth(640, 480, 60));
		OO_CHECK(controller->indexOfCurrentDisplayMode() == 0u);
		OO_CHECK(controller->fullscreenDisplayMode == Mode(640, 480, 60));
		OO_CHECK_EQ(oo::Defaults::standard().integerForKey("display_refresh"), 60);
		OO_CHECK(!controller->setDisplayWidth(1280, 720, 30));
		OO_CHECK_EQ(controller->width, 640u);

		// No current mode: the screen's size, refresh unchanged; no match is NSNotFound.
		view->_currentMode = oo::PList();
		controller->setUpDisplayModes();
		OO_CHECK_EQ(controller->width, 0u);
		OO_CHECK(controller->indexOfCurrentDisplayMode() == NSNotFound);

		view->_inFullScreen = YES;
		OO_CHECK(controller->inFullScreenMode());
		view->_inFullScreen = NO;
		OO_CHECK(!controller->inFullScreenMode());

		controller->setFullScreenMode(true);
		OO_CHECK(controller->fullscreen);
		controller->setFullScreenMode(false);
		OO_CHECK(!controller->fullscreen);

		controller->stayInFullScreenMode = true;
		oo::Defaults::standard().setBool("fullscreen", true);
		controller->exitFullScreenMode();
		OO_CHECK(!controller->stayInFullScreenMode);
		OO_CHECK(!oo::Defaults::standard().boolForKey("fullscreen"));

		TestTarget *target = [[TestTarget alloc] init];
		controller->stayInFullScreenMode = true;
		[facade pauseFullScreenModeToPerform:@selector(record:) onTarget:target];
		OO_CHECK(controller->pauseSelector == @selector(record:));
		OO_CHECK(controller->pauseTarget == target);
		OO_CHECK(!controller->stayInFullScreenMode);
		controller->pauseFullScreenModeToPerform(@selector(raise:), nil);
		OO_CHECK(controller->pauseSelector == @selector(raise:));
		OO_CHECK(controller->pauseTarget == nil);
		[target release];
	}
}


// Slice 3's player-file paths, through the façade.
OO_TEST(playerFilePaths)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		[controller cxx_setPlayerFileToLoad:"saves/Jameson.oolite-save"];
		OO_CHECK([controller cxx_playerFileToLoad] == std::optional<std::string>("saves/Jameson.oolite-save"));
		[controller cxx_setPlayerFileToLoad:"saves/Jameson.txt"];
		OO_CHECK(![controller cxx_playerFileToLoad].has_value());

		[controller cxx_setPlayerFileDirectory:std::optional<std::string>("C:/games/saves/Jameson.oolite-save")];
		OO_CHECK([controller cxx_playerFileDirectory] == std::optional<std::string>("C:/games/saves"));
		OO_CHECK(oo::Defaults::standard().stringForKey("save-directory") == std::optional<std::string>("C:/games/saves"));
		[controller cxx_setPlayerFileDirectory:std::nullopt];
		OO_CHECK(!oo::Defaults::standard().stringForKey("save-directory").has_value());
	}
}


// Slice 2 (bead oo-hn0fw): the deferred calls fire from -fireDueTimers, one per pass, in order;
// target and argument are kept until then; an OOException from the call is swallowed and the
// target stays retained (as the Foundation performer leaked it). The game tick's timer is never
// started here (it would tick the whole game).
OO_TEST(deferredCalls)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		TestTarget *target = [[TestTarget alloc] init];
		OOObject *argument = [[OOObject alloc] init];

		OOScheduleDeferredCall(target, @selector(record:), argument, 0.0);
		OOScheduleDeferredCall(target, @selector(record:), nil, -1.0);
		OO_CHECK([target retainCount] == 3);
		OO_CHECK([argument retainCount] == 2);
		OO_CHECK(target->_calls.empty());

		// Not due until 0.0001 s have passed.
		std::this_thread::sleep_for(std::chrono::milliseconds(5));
		[controller fireDueTimers];
		OO_CHECK(target->_calls == std::vector<std::string>({ "arg" }));
		OO_CHECK([argument retainCount] == 1);
		OO_CHECK([target retainCount] == 2);
		[controller fireDueTimers];
		OO_CHECK(target->_calls == std::vector<std::string>({ "arg", "nil" }));
		OO_CHECK([target retainCount] == 1);
		[controller fireDueTimers];	// nothing left
		OO_CHECK(target->_calls.size() == 2);

		// A call not yet due stays.
		OOScheduleDeferredCall(target, @selector(record:), nil, 60.0);
		[controller fireDueTimers];
		OO_CHECK(target->_calls.size() == 2);

		// An OOException from the call is swallowed; the target is not released.
		OOScheduleDeferredCall(target, @selector(raise:), nil, 0.0);
		std::this_thread::sleep_for(std::chrono::milliseconds(5));
		[controller fireDueTimers];
		OO_CHECK(target->_calls.size() == 3 && target->_calls.back() == "raise");
		OO_CHECK([target retainCount] == 3);	// the leaked +1 and the pending 60 s call's

		[controller stopAnimationTimer];
		[argument release];
	}
}


// Slice 3 (bead oo-5ah4k): the splash screen and window messages reach the view; with no universe
// starting up there is no progress line; with no player file nothing is loaded.
OO_TEST(splashAndWindow)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		TestView *view = (TestView *)[controller gameView];
		OO_CHECK(view != nil);
		const int ends = view->_splashEnds, updates = view->_screenUpdates;

		[controller beginSplashScreen];	// a view exists: none is made
		OO_CHECK([controller gameView] == (MyOpenGLView *)view);
		[controller endSplashScreen];
		OO_CHECK(view->_splashEnds == ends + 1);
		[controller windowDidResize];
		OO_CHECK(view->_screenUpdates == updates + 1);

		[controller cxx_logProgress:"progress"];	// no universe doing start-up: nothing
		[controller cxx_setPlayerFileToLoad:"none.txt"];
		[controller loadPlayerIfRequired];			// no player file: nothing
		OO_CHECK(![controller finishedLaunching]);
	}
}


// Slice 3: with no save-directory default (or one that does not exist), the save directory is
// OO_SAVEDIR, made if missing.
OO_TEST(saveDirectoryLookup)
{
	SetUp();
	@autoreleasepool
	{
		GameController *controller = [GameController sharedController];
		const stdfs::path saves = stdfs::temp_directory_path() / ("oo-test-gamecontroller-saves-" + std::to_string(static_cast<unsigned long>(::_getpid())));
		stdfs::remove_all(saves);
		OO_CHECK(::_putenv_s("OO_SAVEDIR", saves.string().c_str()) == 0);

		[controller cxx_setPlayerFileDirectory:std::nullopt];
		const std::optional<std::string> found = [controller cxx_playerFileDirectory];
		OO_CHECK(found.has_value() && stdfs::is_directory(saves) && stdfs::equivalent(oo::fs::pathFromUTF8(*found), saves));
		OO_CHECK([controller cxx_playerFileDirectory] == found);	// looked up once

		oo::Defaults::standard().setObject("save-directory", oo::PList(std::string("Z:/no/such/directory")));
		[controller cxx_setPlayerFileDirectory:std::nullopt];	// clears the default too
		OO_CHECK(!oo::Defaults::standard().stringForKey("save-directory").has_value());
		oo::Defaults::standard().setObject("save-directory", oo::PList(std::string("Z:/no/such/directory")));
		const std::optional<std::string> again = [controller cxx_playerFileDirectory];
		OO_CHECK(again.has_value() && stdfs::equivalent(oo::fs::pathFromUTF8(*again), saves));

		[controller cxx_setPlayerFileDirectory:std::nullopt];
		stdfs::remove_all(saves);
	}
}


// The façade (bead oo-zkpmt): one for the singleton, identity both ways, nil and null, and the C++
// members giving the façade's answers.
OO_TEST(facadeContract)
{
	SetUp();
	@autoreleasepool
	{
		GameController *facade = [GameController sharedController];
		cxx::GameController *controller = cxx::GameController::sharedController();
		OO_CHECK(controller != nullptr);
		OO_CHECK(cxx::GameController::sharedController() == controller);
		OO_CHECK(oo::ToCxx(facade) == controller);
		OO_CHECK(oo::ToObjC(controller) == facade);
		OO_CHECK([GameController sharedController] == facade);
		OO_CHECK(oo::ToCxx(static_cast<GameController *>(nil)) == nullptr);
		OO_CHECK(oo::ToObjC(static_cast<cxx::GameController *>(nullptr)) == nil);

		OO_CHECK(controller->isGamePaused() == (bool)[facade isGamePaused]);
		OO_CHECK(controller->finishedLaunching() == (bool)[facade finishedLaunching]);
		OO_CHECK(controller->gameView() == [facade gameView]);

		// The C++ members tell the view of the façade, which slices 2 and 3 run on.
		TestView *view = [(TestView *)controller->gameView() retain];	// only the controller holds it
		TestView *other = [[TestView alloc] init];
		controller->setGameView((MyOpenGLView *)other);
		OO_CHECK(other->_controller == facade);
		OO_CHECK([facade gameView] == (MyOpenGLView *)other);
		controller->setGameView((MyOpenGLView *)view);
		OO_CHECK([other retainCount] == 1);
		[other release];
		[view release];

		controller->setMouseInteractionMode(MOUSE_MODE_UI_SCREEN_WITH_INTERACTION);
		OO_CHECK([facade mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_WITH_INTERACTION);
		controller->setMouseInteractionModeForUIWithMouseInteraction(false);
		OO_CHECK([facade mouseInteractionMode] == MOUSE_MODE_UI_SCREEN_NO_INTERACTION);

		// The state slices 2 and 3 read through the façade.
		OO_CHECK(facade->_cxxController.get() == controller);
		[facade cxx_setPlayerFileToLoad:"x.oolite-save"];
		OO_CHECK(controller->_playerFileToLoad == std::optional<std::string>("x.oolite-save"));
		[facade cxx_setPlayerFileToLoad:"x"];
	}
}


OO_TEST_MAIN()
