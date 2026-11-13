/*	test_GameController.mm
        Unit tests for GameController (src/Core/GameController.h): the
   singleton, pause, EcoQoS, the mouse interaction modes, the game view and
   the launch flag.

        The controller is the application's process-wide singleton. It needs the
   JavaScript engine (its pause events are named by OOJSID) and the player
   (PLAYER), so the test links every game object but main's
   (tests/unit/core/meson.build entry ['*']), defines
   gDebugFlags, points the user's home (HOMEPATH: the defaults) at a scratch
   folder, and stands in a recording object for the player and another for the
   game view (as test_DustEntity does for the player). The universe is nil, so
   what the controller sends it is a message to nil, as before the game starts.
   Nothing is drawn and no window is opened.

        It pins what the controller does: one shared
   object; the launch flag; the game view it keeps (retained) and tells about
   itself; the mouse interaction modes and the view's notes of each change;
   pause and resume (the mode they save and restore, the player's script events,
   and the process priority class EcoQoS sets on Windows); and the full-screen
   members and the player-file paths. The cases call the C++ class, the view a
   C++ subclass of the game's. Run:
   meson test -C build/meson_test test_GameController
*/

#include <process.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "GameController.h"
#include "MyOpenGLView.h"
#include "OOFullScreenController.h"
#include "OOJSPropID.h"
#include "OOJavaScriptEngine.h"
#include "PlayerEntity.h"
#include "oo_test.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/FileSystem.hpp"
#include "oofnd/objc/OOException.h"
#include "EntityManualRefs.h"  // the tests' manual entity references (T095)

// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif

class PlayerEntity;
extern PlayerEntity* gOOPlayer;

// PLAYER: records the script events it is sent and answers whether mouse
// control is on.
class TestPlayer : public PlayerEntity {
 public:
  std::vector<OOJSPropID> _events;
  bool _mouseControlOn = false;

  using PlayerEntity::doScriptEvent;
  void doScriptEvent(OOJSPropID message) override {
    _events.push_back(message);
  }
  bool isMouseControlOn() override { return _mouseControlOn; }
};

// A C++ player under the ship's facade, as PlayerEntity::sharedPlayer() makes
// the game's, retained (+1) as +alloc's object was.
template <class T>
T* NewTestPlayer() {
  std::shared_ptr<T> player = oo::makeShared<T>();
  {
    oo::RetainEntity(oo::MadeEntity(player));
  }
  return player.get();
}

// The game view: records the controller it is given and the mode changes it is
// told of, and answers the screen modes the full-screen members ask for. A C++
// subclass of the game's view, overriding the members it answered, which are
// virtual for it; a view made here never opens SDL.
class TestView : public MyOpenGLView {
 public:
  ::GameController* _controller = nullptr;
  std::vector<std::pair<int, int>> _modeNotes;
  std::vector<oo::PList> _screenModes;
  oo::PList _currentMode;
  bool _inFullScreen = false;
  int _splashEnds = 0;
  int _screenUpdates = 0;

  void setGameController(::GameController* controller) override {
    _controller = controller;
  }
  void noteMouseInteractionModeChangedFrom(
      OOMouseInteractionMode oldMode, OOMouseInteractionMode newMode) override {
    _modeNotes.push_back({(int)oldMode, (int)newMode});
  }
  std::vector<oo::PList> getScreenSizeArray() override { return _screenModes; }
  oo::PList currentScreenMode() override { return _currentMode; }
  NSSize currentScreenSize() override { return NSMakeSize(0, 0); }
  bool inFullScreenMode() override { return _inFullScreen; }
  void endSplashScreen() override { _splashEnds++; }
  void updateScreen() override { _screenUpdates++; }
};

// A deferred call's target: records the arguments it is sent, and raises on
// request. A deferred C++ call holding it and the argument (Call below)
// retains them until it runs.
class TestTarget final : public oo::Object {
 public:
  void record(oo::Object* argument) {
    _calls.push_back(argument != nullptr ? "arg" : "nil");
  }
  void raise(oo::Object* ) {
    _calls.push_back("raise");
    OORaiseException(OOGenericException, "%s", "deferred call failure");
  }

  std::vector<std::string> _calls;
};

// A deferred call's argument.
class TestArgument final : public oo::Object {};

// OOScheduleDeferredCall(target, "record:" or "raise:", argument, delay): the
// call holds target and argument (std::shared_ptr, as the performer retained them)
// until it has run.
void Call(TestTarget* target, void (TestTarget::*method)(oo::Object*),
          oo::Object* argument, double delay) {
  OOScheduleDeferredCall(
      [target = oo::share(target), method,
       argument = oo::share(argument)]() {
        (target.get()->*method)(argument.get());
      },
      delay);
}

// The controller's state is private; GameController.h names this struct its
// friend so the checks below read and set the same members.
struct GameControllerTestAccess {
  static auto& _playerFileToLoad(GameController* controller) {
    return controller->_playerFileToLoad;
  }
  static auto& pauseSelector(GameController* controller) {
    return controller->pauseSelector;
  }
  static auto& pauseTarget(GameController* controller) {
    return controller->pauseTarget;
  }
  static auto& width(GameController* controller) { return controller->width; }
  static auto& height(GameController* controller) { return controller->height; }
  static auto& refresh(GameController* controller) {
    return controller->refresh;
  }
  static auto& fullscreenDisplayMode(GameController* controller) {
    return controller->fullscreenDisplayMode;
  }
  static auto& fullscreen(GameController* controller) {
    return controller->fullscreen;
  }
  static auto& stayInFullScreenMode(GameController* controller) {
    return controller->stayInFullScreenMode;
  }
};

namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;
TestPlayer* sPlayer = nullptr;

// The scratch home and game folder, the engine and the stand-in player, made
// once, before the controller exists.
void SetUp() {
  if (!sRoot.empty()) return;
  sRoot = stdfs::temp_directory_path() /
          ("oo-test-gamecontroller-" +
           std::to_string(static_cast<unsigned long>(::_getpid())));
  stdfs::remove_all(sRoot);
  stdfs::create_directories(sRoot);
  OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
  stdfs::current_path(sRoot);
  stdfs::create_directories(sRoot / "Resources");
  OO_CHECK(
      oo::fs::writeFile(sRoot / "Resources" / "Info-gnustep.plist",
                        oo::Data("{ CFBundleVersion = \"9.9.9-test\"; }", 35),
                        oo::fs::WriteMode::kDirect)
          .has_value());
  (void)OOJavaScriptEngine::sharedEngine();
  sPlayer = NewTestPlayer<TestPlayer>();  // never released
  gOOPlayer = sPlayer;
}

bool SameId(OOJSPropID a, OOJSPropID b) { return a == b; }

oo::PList Mode(int width, int height, int refresh) {
  oo::PList::Dict mode;
  mode[std::string(kOODisplayWidth)] = oo::PList(std::int64_t(width));
  mode[std::string(kOODisplayHeight)] = oo::PList(std::int64_t(height));
  mode[std::string(kOODisplayRefreshRate)] = oo::PList(std::int64_t(refresh));
  return oo::PList(std::move(mode));
}

}  // namespace

OO_TEST(sharedControllerIsOneObject) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    OO_CHECK(controller != nullptr);
    OO_CHECK(::GameController::sharedController() == controller);
    OO_CHECK(!controller->finishedLaunching());
    OO_CHECK(!controller->isGamePaused());
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kUiScreenNoInteraction);
    OO_CHECK(controller->gameView() == nullptr);
    OO_CHECK(!controller->playerFileToLoad().has_value());
  }
}

// main.mm makes the application's controller with alloc/init, apart from
// +sharedController's: once the shared one exists, that raises (and releases
// the receiver).
OO_TEST(secondControllerRaises) {
  SetUp();
  {
    GameController* shared = ::GameController::sharedController();
    bool raised = false;
    try {
      new GameController();
    } catch (const oo::Exception& exception) {
      raised =
          (std::string(exception.name()) == OOInternalInconsistencyException);
    }
    OO_CHECK(raised);
    OO_CHECK(::GameController::sharedController() == shared);
  }
}

OO_TEST(gameViewIsKeptAndToldOfTheController) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    TestView* first = oo::test::NewRetained<TestView>();
    TestView* second = oo::test::NewRetained<TestView>();

    controller->setGameView(first);
    OO_CHECK(controller->gameView() == first);
    OO_CHECK(first->_controller == controller);
    OO_CHECK(first->weak_from_this().use_count() == 2);  // the controller retains its view

    controller->setGameView(second);
    OO_CHECK(controller->gameView() == second);
    OO_CHECK(second->_controller == controller);
    OO_CHECK(first->weak_from_this().use_count() == 1);  // and releases the one it replaces
    OO_CHECK(second->weak_from_this().use_count() == 2);

    controller->setGameView(first);
    oo::test::Release(second);
    oo::test::Release(first);
  }
}

OO_TEST(mouseInteractionModes) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    TestView* view = static_cast<TestView*>(controller->gameView());
    OO_CHECK(view != nullptr);
    view->_modeNotes.clear();

    controller->setMouseInteractionMode(OOMouseInteractionMode::kFlightNoMouseControl);
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kFlightNoMouseControl);
    OO_CHECK_EQ(view->_modeNotes.size(), 1u);
    OO_CHECK(view->_modeNotes.back() ==
             std::make_pair((int)OOMouseInteractionMode::kUiScreenNoInteraction,
                            (int)OOMouseInteractionMode::kFlightNoMouseControl));

    // The same mode again changes nothing and tells nobody.
    controller->setMouseInteractionMode(OOMouseInteractionMode::kFlightNoMouseControl);
    OO_CHECK_EQ(view->_modeNotes.size(), 1u);

    controller->setMouseInteractionModeForUIWithMouseInteraction(true);
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kUiScreenWithInteraction);
    controller->setMouseInteractionModeForUIWithMouseInteraction(false);
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kUiScreenNoInteraction);

    // Flight: the player's mouse control chooses the mode.
    sPlayer->_mouseControlOn = true;
    controller->setMouseInteractionModeForFlight();
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kFlightWithMouseControl);
    sPlayer->_mouseControlOn = false;
    controller->setMouseInteractionModeForFlight();
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kFlightNoMouseControl);

    OO_CHECK_EQ(view->_modeNotes.size(), 5u);
    OO_CHECK(view->_modeNotes.back() ==
             std::make_pair((int)OOMouseInteractionMode::kFlightWithMouseControl,
                            (int)OOMouseInteractionMode::kFlightNoMouseControl));
  }
}

OO_TEST(pauseAndResume) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    controller->setMouseInteractionMode(OOMouseInteractionMode::kFlightWithMouseControl);
    sPlayer->_events.clear();

    controller->setGamePaused(true);
    OO_CHECK(controller->isGamePaused());
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kUiScreenNoInteraction);
    OO_CHECK_EQ(sPlayer->_events.size(), 1u);
    OO_CHECK(!sPlayer->_events.empty() &&
             SameId(sPlayer->_events.back(), OOJSID("gamePaused")));
#if OOLITE_WINDOWS
    // EcoQoS (no "ecoqos" default: on): a paused game runs at idle priority.
    OO_CHECK(GetPriorityClass(GetCurrentProcess()) == IDLE_PRIORITY_CLASS);
#endif

    // Pausing a paused game does nothing.
    controller->setGamePaused(true);
    OO_CHECK_EQ(sPlayer->_events.size(), 1u);

    controller->setGamePaused(false);
    OO_CHECK(!controller->isGamePaused());
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kFlightWithMouseControl);  // the mode it paused in
    OO_CHECK_EQ(sPlayer->_events.size(), 2u);
    OO_CHECK(sPlayer->_events.size() == 2 &&
             SameId(sPlayer->_events.back(), OOJSID("gameResumed")));
#if OOLITE_WINDOWS
    OO_CHECK(GetPriorityClass(GetCurrentProcess()) == NORMAL_PRIORITY_CLASS);
#endif

    // Resuming a running game does nothing.
    controller->setGamePaused(false);
    OO_CHECK_EQ(sPlayer->_events.size(), 2u);

#if OOLITE_WINDOWS
    // "ecoqos" off: EcoQoS leaves the priority alone.
    oo::Defaults::standard().setBool("ecoqos", false);
    controller->setEcoQoS(true);
    OO_CHECK(GetPriorityClass(GetCurrentProcess()) == NORMAL_PRIORITY_CLASS);
    oo::Defaults::standard().removeObject("ecoqos");
#endif
  }
}

// The full-screen category (SDL/GameController+SDLFullScreen.mm): still
// Objective-C, on the state the class keeps.
OO_TEST(fullScreenDisplayModes) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    TestView* view = static_cast<TestView*>(controller->gameView());
    view->_screenModes = {Mode(320, 200, 60), Mode(1024, 768, 60),
                          Mode(1920, 1080, 60), Mode(1920, 1080, 144),
                          Mode(8000, 5000, 30)};
    view->_currentMode = Mode(1920, 1080, 60);
    controller->setUpDisplayModes();

    // The modes the game can use, in the screen's order.
    const oo::PList modes = controller->getDisplayModes();
    OO_CHECK_EQ(modes.count(), 3u);
    OO_CHECK(controller->indexOfCurrentDisplayMode() == 1u);
    OO_CHECK(controller->findDisplayModeForWidth(1920, 1080, 144) ==
             Mode(1920, 1080, 144));
    OO_CHECK(controller->findDisplayModeForWidth(320, 200, 60).isNull());

    OO_CHECK(controller->setDisplayWidth(1024, 768, 60));
    OO_CHECK(controller->indexOfCurrentDisplayMode() == 0u);
    OO_CHECK_EQ(oo::Defaults::standard().integerForKey("display_width"), 1024);
    OO_CHECK_EQ(oo::Defaults::standard().integerForKey("display_height"), 768);
    OO_CHECK(!controller->setDisplayWidth(800, 600, 60));
    OO_CHECK(controller->indexOfCurrentDisplayMode() == 0u);

    view->_inFullScreen = true;
    OO_CHECK(controller->inFullScreenMode());
    view->_inFullScreen = false;
    OO_CHECK(!controller->inFullScreenMode());

    oo::Defaults::standard().setBool("fullscreen", true);
    controller->exitFullScreenMode();
    OO_CHECK(!oo::Defaults::standard().boolForKey("fullscreen"));
  }
}

// The full-screen members: pausing full-screen mode records the call to make
// and leaves full screen.
OO_TEST(fullScreenMembers) {
  SetUp();
  {
    GameController* controller = GameController::sharedController();
    TestView* view = static_cast<TestView*>(controller->gameView());
    view->_screenModes = {Mode(640, 480, 60), Mode(1280, 720, 60),
                          Mode(1280, 720, 75), Mode(9000, 9000, 60)};
    view->_currentMode = Mode(1280, 720, 75);
    controller->setUpDisplayModes();

    OO_CHECK_EQ(controller->getDisplayModes().count(), 3u);
    OO_CHECK(controller->getDisplayModes() == controller->getDisplayModes());
    OO_CHECK_EQ(GameControllerTestAccess::width(controller), 1280u);
    OO_CHECK_EQ(GameControllerTestAccess::height(controller), 720u);
    OO_CHECK_EQ(GameControllerTestAccess::refresh(controller), 75u);
    OO_CHECK(controller->indexOfCurrentDisplayMode() == 2u);
    OO_CHECK(controller->indexOfCurrentDisplayMode() == 2u);
    OO_CHECK(controller->findDisplayModeForWidth(640, 480, 60) ==
             Mode(640, 480, 60));
    OO_CHECK(controller->findDisplayModeForWidth(9000, 9000, 60).isNull());

    OO_CHECK(controller->setDisplayWidth(640, 480, 60));
    OO_CHECK(controller->indexOfCurrentDisplayMode() == 0u);
    OO_CHECK(GameControllerTestAccess::fullscreenDisplayMode(controller) ==
             Mode(640, 480, 60));
    OO_CHECK_EQ(oo::Defaults::standard().integerForKey("display_refresh"), 60);
    OO_CHECK(!controller->setDisplayWidth(1280, 720, 30));
    OO_CHECK_EQ(GameControllerTestAccess::width(controller), 640u);

    // No current mode: the screen's size, refresh unchanged; no match is
    // oo::kNotFound.
    view->_currentMode = oo::PList();
    controller->setUpDisplayModes();
    OO_CHECK_EQ(GameControllerTestAccess::width(controller), 0u);
    OO_CHECK(controller->indexOfCurrentDisplayMode() == oo::kNotFound);

    view->_inFullScreen = true;
    OO_CHECK(controller->inFullScreenMode());
    view->_inFullScreen = false;
    OO_CHECK(!controller->inFullScreenMode());

    controller->setFullScreenMode(true);
    OO_CHECK(GameControllerTestAccess::fullscreen(controller));
    controller->setFullScreenMode(false);
    OO_CHECK(!GameControllerTestAccess::fullscreen(controller));

    GameControllerTestAccess::stayInFullScreenMode(controller) = true;
    oo::Defaults::standard().setBool("fullscreen", true);
    controller->exitFullScreenMode();
    OO_CHECK(!GameControllerTestAccess::stayInFullScreenMode(controller));
    OO_CHECK(!oo::Defaults::standard().boolForKey("fullscreen"));

    TestTarget* target = oo::test::NewRetained<TestTarget>();
    GameControllerTestAccess::stayInFullScreenMode(controller) = true;
    controller->pauseFullScreenModeToPerform("record:", target);
    OO_CHECK(GameControllerTestAccess::pauseSelector(controller) == "record:");
    OO_CHECK(GameControllerTestAccess::pauseTarget(controller) == target);
    OO_CHECK(!GameControllerTestAccess::stayInFullScreenMode(controller));
    controller->pauseFullScreenModeToPerform("raise:", nullptr);
    OO_CHECK(GameControllerTestAccess::pauseSelector(controller) == "raise:");
    OO_CHECK(GameControllerTestAccess::pauseTarget(controller) == nullptr);
    oo::test::Release(target);
  }
}

// The player-file paths.
OO_TEST(playerFilePaths) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    controller->setPlayerFileToLoad("saves/Jameson.oolite-save");
    OO_CHECK(controller->playerFileToLoad() ==
             std::optional<std::string>("saves/Jameson.oolite-save"));
    controller->setPlayerFileToLoad("saves/Jameson.txt");
    OO_CHECK(!controller->playerFileToLoad().has_value());

    controller->setPlayerFileDirectory(
        std::optional<std::string>("C:/games/saves/Jameson.oolite-save"));
    OO_CHECK(controller->playerFileDirectory() ==
             std::optional<std::string>("C:/games/saves"));
    OO_CHECK(oo::Defaults::standard().stringForKey("save-directory") ==
             std::optional<std::string>("C:/games/saves"));
    controller->setPlayerFileDirectory(std::nullopt);
    OO_CHECK(
        !oo::Defaults::standard().stringForKey("save-directory").has_value());
  }
}

// The deferred calls fire from -fireDueTimers, one per
// pass, in order; target and argument are kept until then; an OOException from
// the call is swallowed and the target stays retained (as the Foundation
// performer leaked it). The game tick's timer is never started here (it would
// tick the whole game).
OO_TEST(deferredCalls) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    TestTarget* target = oo::test::NewRetained<TestTarget>();
    TestArgument* argument = oo::test::NewRetained<TestArgument>();

    Call(target, &TestTarget::record, argument, 0.0);
    Call(target, &TestTarget::record, nullptr, -1.0);
    OO_CHECK(target->weak_from_this().use_count() == 3);
    OO_CHECK(argument->weak_from_this().use_count() == 2);
    OO_CHECK(target->_calls.empty());

    // Not due until 0.0001 s have passed.
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    controller->fireDueTimers();
    OO_CHECK(target->_calls == std::vector<std::string>({"arg"}));
    OO_CHECK(argument->weak_from_this().use_count() == 1);
    OO_CHECK(target->weak_from_this().use_count() == 2);
    controller->fireDueTimers();
    OO_CHECK(target->_calls == std::vector<std::string>({"arg", "nil"}));
    OO_CHECK(target->weak_from_this().use_count() == 1);
    controller->fireDueTimers();  // nothing left
    OO_CHECK(target->_calls.size() == 2);

    // A call not yet due stays.
    Call(target, &TestTarget::record, nullptr, 60.0);
    controller->fireDueTimers();
    OO_CHECK(target->_calls.size() == 2);

    // An OOException from the call is swallowed; the target is not released.
    Call(target, &TestTarget::raise, nullptr, 0.0);
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    controller->fireDueTimers();
    OO_CHECK(target->_calls.size() == 3 && target->_calls.back() == "raise");
    OO_CHECK(target->weak_from_this().use_count() ==
             3);  // the leaked +1 and the pending 60 s call's

    // A C++ deferred call shares the performs' queue -
    // due calls run one per pass in scheduling order, what the call captures is
    // kept until it has run, and an OOException from it is swallowed and the
    // call kept (its captures stay, as the performer leaked its target). (The
    // pending 60 s call above is not due.)
    TestTarget* cxxTarget = oo::test::NewRetained<TestTarget>();
    std::vector<std::string> order;
    std::shared_ptr<int> kept = std::make_shared<int>(1);

    OOScheduleDeferredCall([&order, kept]() { order.push_back("cxx"); }, 0.0);
    Call(cxxTarget, &TestTarget::record, nullptr, -1.0);
    OOScheduleDeferredCall(std::function<void()>(),
                           0.0);  // an empty call: nothing scheduled
    OO_CHECK(kept.use_count() == 2);

    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    controller->fireDueTimers();
    OO_CHECK(order == std::vector<std::string>({"cxx"}));
    OO_CHECK(cxxTarget->_calls.empty());
    OO_CHECK(kept.use_count() == 1);
    controller->fireDueTimers();
    OO_CHECK(cxxTarget->_calls == std::vector<std::string>({"nil"}));
    controller->fireDueTimers();  // nothing due
    OO_CHECK(order.size() == 1 && cxxTarget->_calls.size() == 1);

    std::shared_ptr<int> leaked = std::make_shared<int>(2);
    OOScheduleDeferredCall(
        [&order, leaked]() {
          order.push_back("raise");
          OORaiseException(OOGenericException, "%s", "deferred call failure");
        },
        0.0);
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    controller->fireDueTimers();
    OO_CHECK(order.size() == 2 && order.back() == "raise");
    OO_CHECK(leaked.use_count() == 2);  // the call was not destroyed

    oo::test::Release(cxxTarget);

    controller->stopAnimationTimer();
    oo::test::Release(argument);
  }
}

// The splash screen and window messages reach the
// view; with no universe starting up there is no progress line; with no player
// file nothing is loaded.
OO_TEST(splashAndWindow) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    TestView* view = static_cast<TestView*>(controller->gameView());
    OO_CHECK(view != nullptr);
    const int ends = view->_splashEnds, updates = view->_screenUpdates;

    controller->beginSplashScreen();  // a view exists: none is made
    OO_CHECK(controller->gameView() == view);
    controller->endSplashScreen();
    OO_CHECK(view->_splashEnds == ends + 1);
    controller->windowDidResize();
    OO_CHECK(view->_screenUpdates == updates + 1);

    controller->logProgress("progress");  // no universe doing start-up: nothing
    controller->setPlayerFileToLoad("none.txt");
    controller->loadPlayerIfRequired();  // no player file: nothing
    OO_CHECK(!controller->finishedLaunching());
  }
}

// With no save-directory default (or one that does not exist), the
// save directory is OO_SAVEDIR, made if missing.
OO_TEST(saveDirectoryLookup) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    const stdfs::path saves =
        stdfs::temp_directory_path() /
        ("oo-test-gamecontroller-saves-" +
         std::to_string(static_cast<unsigned long>(::_getpid())));
    stdfs::remove_all(saves);
    OO_CHECK(::_putenv_s("OO_SAVEDIR", saves.string().c_str()) == 0);

    controller->setPlayerFileDirectory(std::nullopt);
    const std::optional<std::string> found = controller->playerFileDirectory();
    OO_CHECK(found.has_value() && stdfs::is_directory(saves) &&
             stdfs::equivalent(oo::fs::pathFromUTF8(*found), saves));
    OO_CHECK(controller->playerFileDirectory() == found);  // looked up once

    oo::Defaults::standard().setObject(
        "save-directory", oo::PList(std::string("Z:/no/such/directory")));
    controller->setPlayerFileDirectory(std::nullopt);  // clears the default too
    OO_CHECK(
        !oo::Defaults::standard().stringForKey("save-directory").has_value());
    oo::Defaults::standard().setObject(
        "save-directory", oo::PList(std::string("Z:/no/such/directory")));
    const std::optional<std::string> again = controller->playerFileDirectory();
    OO_CHECK(again.has_value() &&
             stdfs::equivalent(oo::fs::pathFromUTF8(*again), saves));

    controller->setPlayerFileDirectory(std::nullopt);
    stdfs::remove_all(saves);
  }
}

// The C++ controller: one shared object, and the members telling the view of
// the controller and keeping the state they read.
OO_TEST(cxxAPI) {
  SetUp();
  {
    GameController* controller = GameController::sharedController();
    OO_CHECK(controller != nullptr);
    OO_CHECK(GameController::sharedController() == controller);

    // The members tell the view of the controller.
    TestView* view = static_cast<TestView*>(controller->gameView());
    oo::test::Retain(view);  // only the controller holds it
    TestView* other = oo::test::NewRetained<TestView>();
    controller->setGameView(other);
    OO_CHECK(other->_controller == controller);
    OO_CHECK(controller->gameView() == other);
    controller->setGameView(view);
    OO_CHECK(other->weak_from_this().use_count() == 1);
    oo::test::Release(other);
    oo::test::Release(view);

    controller->setMouseInteractionMode(OOMouseInteractionMode::kUiScreenWithInteraction);
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kUiScreenWithInteraction);
    controller->setMouseInteractionModeForUIWithMouseInteraction(false);
    OO_CHECK(controller->mouseInteractionMode() ==
             OOMouseInteractionMode::kUiScreenNoInteraction);

    // The state the members keep.
    controller->setPlayerFileToLoad("x.oolite-save");
    OO_CHECK(GameControllerTestAccess::_playerFileToLoad(controller) ==
             std::optional<std::string>("x.oolite-save"));
    controller->setPlayerFileToLoad("x");
  }
}

// The file to load may be handed back from the member itself (the load does
// this): it is read in full before the member changes, kept or cleared as for
// any other name (found by ASan as a heap-use-after-free in the sanitized
// game's launch).
OO_TEST(playerFileToLoadFromItsOwnValue) {
  SetUp();
  {
    GameController* controller = ::GameController::sharedController();
    controller->setPlayerFileToLoad(
        "saves/a-much-longer-name-than-fits-inline.oolite-save");
    controller->setPlayerFileToLoad(
        *GameControllerTestAccess::_playerFileToLoad(controller));
    OO_CHECK(controller->playerFileToLoad() ==
             std::optional<std::string>(
                 "saves/a-much-longer-name-than-fits-inline.oolite-save"));
    controller->setPlayerFileToLoad("x");
    OO_CHECK(!controller->playerFileToLoad().has_value());
  }
}

OO_TEST_MAIN()
