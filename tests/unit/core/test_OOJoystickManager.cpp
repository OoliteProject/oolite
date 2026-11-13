/*	test_OOJoystickManager.mm
        Unit tests for OOJoystickManager (src/Core/OOJoystickManager.h), the
   root of a hierarchy whose one subclass is the SDL manager.

        The manager keeps the stick-to-function tables, decodes stick events
   into axis and button states (the SDL manager decodes, upstream #742: the
   cases that decode use an SDL manager that answers for the hardware as the
   base does), reports the next moved axis or pressed button to a callback, and
   loads and saves the tables and the axis profiles in the user defaults. The
   test points the defaults' home (HOMEPATH) at a scratch folder before they are
   first read, so nothing of the user's is read or written. They call the C++
   members. They cover: the default mapping; axis decoding (normalised, thrust,
   view, raw, out of range, the profiles and precision mode); buttons and hats;
   reassigning and unsetting functions; the callback for both kinds of hardware;
   saving and reloading the tables and both kinds of profile; a subclass's
   overrides reached by the base (also from -init) and [super ...]; the shared
   handler of a registered factory. Run: bash tests/run.sh unit
*/

#include <process.h>

#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "OOJoystickManager.h"
#include "OOSDLJoystickManager.h"
#include "oo_test.hpp"
#include "oofnd/Defaults.hpp"

// What the callback reports to (the callback is a C++ function).
struct StickCallbackTarget {
  oo::PList _picked;
  int _calls = 0;

  void stickPicked(const oo::PList& stickFn) {
    _picked = stickFn;
    _calls++;
  }

  OOJoystickManager::StickCallback callback() {
    return [this](const oo::PList& stickFn) { stickPicked(stickFn); };
  }
};

// A subclass as the platform managers are: two sticks, the second nameless,
// whose axis 1 reads half way. It does not override listSticks() or the
// setters, so the base's run on its answers. It is an SDL manager, which
// decodes the events (upstream #742).
class TestStickManager : public OOSDLJoystickManager {
 public:
  std::size_t joystickCount() override { return 2; }

  std::optional<std::string> nameOfJoystick(std::size_t stickNumber) override {
    if (stickNumber == 1) return std::nullopt;
    return "stick " + std::to_string(stickNumber);
  }

  int16_t getAxisWithStick(std::size_t /*stickNum*/,
                           std::size_t axisNum) override {
    return axisNum == 1 ? 16384 : 0;
  }

  std::optional<std::string> superNameOfJoystick(std::size_t stickNumber) {
    // OOJoystickManager's own member (the SDL manager, its superclass,
    // overrides it).
    return OOJoystickManager::nameOfJoystick(stickNumber);
  }
};

// The SDL manager, which decodes stick events into the base's tables (upstream
// #742), answering for the hardware as the base does (no sticks, "Dummy
// joystick", axes at 0), so the decoding cases see the base's tables only.
class DecodingStickManager : public OOSDLJoystickManager {
 public:
  std::size_t joystickCount() override {
    return OOJoystickManager::joystickCount();
  }

  std::optional<std::string> nameOfJoystick(std::size_t stickNumber) override {
    return OOJoystickManager::nameOfJoystick(stickNumber);
  }

  int16_t getAxisWithStick(std::size_t stickNum, std::size_t axisNum) override {
    return OOJoystickManager::getAxisWithStick(stickNum, axisNum);
  }
};

namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;

// The scratch home, set once, before the defaults are first read.
oo::Defaults& Defaults() {
  if (sRoot.empty()) {
    sRoot = stdfs::temp_directory_path() /
            ("oo-test-joystickmanager-" +
             std::to_string(static_cast<unsigned long>(::_getpid())));
    stdfs::remove_all(sRoot);
    stdfs::create_directories(sRoot);
    OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
  }
  return oo::Defaults::standard();
}

void ClearStickDefaults() {
  oo::Defaults& defaults = Defaults();
  for (std::string_view key :
       {AXIS_SETTINGS, BUTTON_SETTINGS, STICK_ROLL_AXIS_PROFILE_SETTING,
        STICK_PITCH_AXIS_PROFILE_SETTING, STICK_YAW_AXIS_PROFILE_SETTING}) {
    defaults.removeObject(key);
  }
}

oo::PList StickFn(bool isAxis, int stick, int axisOrButton) {
  oo::PList::Dict fn;
  fn[std::string(STICK_ISAXIS)] = oo::PList(isAxis);
  fn[std::string(STICK_NUMBER)] = oo::PList(stick);
  fn[std::string(STICK_AXBUT)] = oo::PList(axisOrButton);
  return oo::PList(std::move(fn));
}

oo::PList Functions(std::initializer_list<std::pair<int, oo::PList>> entries) {
  oo::PList::Dict result;
  for (const auto& [function, fn] : entries) result[ENUMKEY(function)] = fn;
  return oo::PList(std::move(result));
}

// SDL's events, with the stick index where SDL has its id (as
// OOSDLJoystickManager's makeJoy...Event() pass them on).
SDL_JoyAxisEvent Axis(int stick, int axis, int value) {
  SDL_JoyAxisEvent evt = {};
  evt.type = SDL_EVENT_JOYSTICK_AXIS_MOTION;
  evt.which = stick;
  evt.axis = axis;
  evt.value = value;
  return evt;
}

SDL_JoyButtonEvent Button(int stick, int button, bool down) {
  SDL_JoyButtonEvent evt = {};
  evt.type =
      down ? SDL_EVENT_JOYSTICK_BUTTON_DOWN : SDL_EVENT_JOYSTICK_BUTTON_UP;
  evt.which = stick;
  evt.button = button;
  evt.down = down;
  return evt;
}

SDL_JoyHatEvent Hat(int stick, int hat, int value) {
  SDL_JoyHatEvent evt = {};
  evt.type = SDL_EVENT_JOYSTICK_HAT_MOTION;
  evt.which = stick;
  evt.hat = hat;
  evt.value = value;
  return evt;
}

// [[OOJoystickManager alloc] init]: made, then -init's body.
std::shared_ptr<OOJoystickManager> NewManager() {
  Defaults();
  std::shared_ptr<OOJoystickManager> manager = oo::makeRef<OOJoystickManager>();
  manager->init();
  return manager;
}

// The decoding manager, made the same way.
std::shared_ptr<DecodingStickManager> NewDecodingManager() {
  Defaults();
  std::shared_ptr<DecodingStickManager> manager = oo::makeRef<DecodingStickManager>();
  manager->init();
  return manager;
}

std::shared_ptr<TestStickManager> NewTestStickManager() {
  std::shared_ptr<TestStickManager> manager = oo::makeRef<TestStickManager>();
  manager->init();
  return manager;
}

// The registered factory: it makes the manager; sharedStickHandler() runs
// init().
std::shared_ptr<OOJoystickManager> MakeTestStickManager() {
  return oo::makeRef<TestStickManager>();
}

}  // namespace

OO_TEST(defaultMapping) {
  ClearStickDefaults();
  {
    std::shared_ptr<OOJoystickManager> manager = NewManager();
    OO_CHECK(manager != nullptr);

    // No hardware in the base class.
    OO_CHECK(manager->joystickCount() == 0);
    OO_CHECK(manager->nameOfJoystick(0) ==
             std::optional<std::string>("Dummy joystick"));
    OO_CHECK(manager->getAxisWithStick(0, 0) == 0);
    OO_CHECK(manager->listSticks().empty());

    // Nothing saved: stick 0's axes 0/1 are roll/pitch, its buttons 0/1
    // fire/missile.
    OO_CHECK(manager->axisFunctions() ==
             Functions({{AXIS_ROLL, StickFn(true, 0, 0)},
                        {AXIS_PITCH, StickFn(true, 0, 1)}}));
    OO_CHECK(manager->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)}}));

    // Every axis is unassigned until an event or a setting gives it a value.
    OO_CHECK(manager->getAxisState(AXIS_ROLL) == STICK_AXISUNASSIGNED);
    OO_CHECK(manager->getAxisState(AXIS_THRUST) == STICK_AXISUNASSIGNED);
    OO_CHECK(manager->rollPitchAxis().x == STICK_AXISUNASSIGNED &&
             manager->rollPitchAxis().y == STICK_AXISUNASSIGNED);
    OO_CHECK(manager->viewAxis().x == STICK_AXISUNASSIGNED &&
             manager->viewAxis().y == STICK_AXISUNASSIGNED);
    OO_CHECK(manager->getSensitivity() == 1.0);
    bool anyButton = false;
    for (int i = 0; i < BUTTON_end; i++)
      anyButton = anyButton || manager->getButtonState(i);
    OO_CHECK(!anyButton);

    // Roll, pitch and yaw have standard profiles; nothing else has one.
    OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile*>(
                 manager->getProfileForAxis(AXIS_ROLL)) != nullptr);
    OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile*>(
                 manager->getProfileForAxis(AXIS_PITCH)) != nullptr);
    OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile*>(
                 manager->getProfileForAxis(AXIS_YAW)) != nullptr);
    OO_CHECK(manager->getProfileForAxis(AXIS_THRUST) == nullptr);
  }
}

OO_TEST(decodesAxes) {
  ClearStickDefaults();
  {
    std::shared_ptr<DecodingStickManager> manager = NewDecodingManager();

    // Assigning reads the axis now (the base reads 0) and moves the function
    // off its old axis.
    manager->setFunction(AXIS_ROLL, StickFn(true, 0, 2));
    manager->setFunction(AXIS_THRUST, StickFn(true, 1, 3));
    manager->setFunction(AXIS_VIEWX, StickFn(true, 0, 4));
    manager->setFunction(AXIS_PRECISION, StickFn(true, 0, 5));
    OO_CHECK(manager->axisFunctions() ==
             Functions({{AXIS_ROLL, StickFn(true, 0, 2)},
                        {AXIS_PITCH, StickFn(true, 0, 1)},
                        {AXIS_THRUST, StickFn(true, 1, 3)},
                        {AXIS_VIEWX, StickFn(true, 0, 4)},
                        {AXIS_PRECISION, StickFn(true, 0, 5)}}));
    OO_CHECK(manager->getAxisState(AXIS_THRUST) == 0.5);
    OO_CHECK(manager->getAxisState(AXIS_VIEWX) == 0.0);

    SDL_JoyAxisEvent evt = Axis(0, 2, 16384);
    manager->decodeAxisEvent(&evt);
    OOJoystickAxisProfile* roll = manager->getProfileForAxis(AXIS_ROLL);
    const double rollValue = roll->value(0.5);
    OO_CHECK(rollValue > 0.0);
    OO_CHECK(manager->getAxisState(AXIS_ROLL) == rollValue);
    OO_CHECK(manager->rollPitchAxis().x == rollValue);

    evt = Axis(1, 3, -32768);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(manager->getAxisState(AXIS_THRUST) == 1.0);
    evt = Axis(1, 3, 32767);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(manager->getAxisState(AXIS_THRUST) ==
             (float)(65536 - (32767.0 + 32768)) / 65536);

    evt = Axis(0, 4, -32768);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(manager->viewAxis().x == -1.0);
    evt = Axis(0, 5, 8192);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(manager->getAxisState(AXIS_PRECISION) == 0.25);

    // An unassigned axis, and one out of range, change nothing.
    evt = Axis(0, 7, 1000);
    manager->decodeAxisEvent(&evt);
    evt = Axis(0, MAX_AXES, 1000);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(manager->getAxisState(AXIS_ROLL) == rollValue);
    OO_CHECK(manager->getAxisState(AXIS_YAW) == STICK_AXISUNASSIGNED);

    // Precision mode (a button) divides the profiled axes.
    manager->setFunction(BUTTON_PRECISION, StickFn(false, 0, 5));
    SDL_JoyButtonEvent press = Button(0, 5, true);
    manager->decodeButtonEvent(&press);
    OO_CHECK(manager->getSensitivity() == STICK_PRECISIONFAC);
    OO_CHECK(manager->getAxisState(AXIS_ROLL) ==
             rollValue / STICK_PRECISIONFAC);
    OO_CHECK(manager->getAxisState(AXIS_THRUST) ==
             (float)(65536 - (32767.0 + 32768)) / 65536);
    manager->decodeButtonEvent(&press);
    OO_CHECK(manager->getSensitivity() == 1.0);
    OO_CHECK(manager->getAxisState(AXIS_ROLL) == rollValue);

    // Unsetting a function unassigns its axis.
    manager->unsetAxisFunction(AXIS_ROLL);
    OO_CHECK(manager->getAxisState(AXIS_ROLL) == STICK_AXISUNASSIGNED);
    OO_CHECK(manager->axisFunctions() ==
             Functions({{AXIS_PITCH, StickFn(true, 0, 1)},
                        {AXIS_THRUST, StickFn(true, 1, 3)},
                        {AXIS_VIEWX, StickFn(true, 0, 4)},
                        {AXIS_PRECISION, StickFn(true, 0, 5)}}));
  }
}

OO_TEST(decodesButtonsAndHats) {
  ClearStickDefaults();
  {
    std::shared_ptr<DecodingStickManager> manager = NewDecodingManager();

    SDL_JoyButtonEvent evt = Button(0, 0, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(manager->getButtonState(BUTTON_FIRE));
    OO_CHECK(manager->getAllButtonStates()[BUTTON_FIRE]);
    OO_CHECK(manager->isButtonDown(0, 0));
    OO_CHECK(!manager->isButtonDown(0, 1));

    // Clearing the function's state leaves the stick's.
    manager->clearStickButtonState(BUTTON_FIRE);
    OO_CHECK(!manager->getButtonState(BUTTON_FIRE));
    OO_CHECK(manager->isButtonDown(0, 0));
    manager->clearStickButtonState(-1);
    manager->clearStickButtonState(BUTTON_end);

    evt = Button(0, 0, false);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(!manager->isButtonDown(0, 0));

    // An unmapped button is tracked per stick only; one out of range is
    // ignored.
    evt = Button(2, 9, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(manager->isButtonDown(9, 2));
    evt = Button(0, MAX_BUTTONS, true);
    manager->decodeButtonEvent(&evt);

    // Moving a function to another button frees the old one.
    manager->setFunction(BUTTON_FIRE, StickFn(false, 1, 3));
    OO_CHECK(manager->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 1, 3)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)}}));
    evt = Button(1, 3, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(manager->getButtonState(BUTTON_FIRE));
    manager->unsetButtonFunction(BUTTON_LAUNCHMISSILE);
    OO_CHECK(manager->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 1, 3)}}));

    // A hat is four buttons past the real ones, four per stick, one bit each.
    manager->setFunction(BUTTON_ID,
                         StickFn(false, 1, MAX_REAL_BUTTONS + 4 + 2));
    SDL_JoyHatEvent hat = Hat(1, 0, SDL_HAT_DOWN | SDL_HAT_RIGHT);
    manager->decodeHatEvent(&hat);
    OO_CHECK(manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 1, 1));
    OO_CHECK(manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 2, 1));
    OO_CHECK(!manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 0, 1));
    OO_CHECK(manager->getButtonState(BUTTON_ID));
    hat = Hat(1, 0, SDL_HAT_RIGHT);
    manager->decodeHatEvent(&hat);
    OO_CHECK(manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 1, 1));
    OO_CHECK(!manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 2, 1));
    OO_CHECK(!manager->getButtonState(BUTTON_ID));

    manager->clearStickStates();
    OO_CHECK(!manager->getButtonState(BUTTON_FIRE));
    OO_CHECK(!manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 1, 1));
    OO_CHECK(manager->getAxisState(AXIS_PITCH) == STICK_AXISUNASSIGNED);

    manager->clearMappings();
    OO_CHECK(manager->axisFunctions() == oo::PList(oo::PList::Dict()));
    OO_CHECK(manager->buttonFunctions() == oo::PList(oo::PList::Dict()));
    manager->setDefaultMapping();
    OO_CHECK(manager->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)}}));
  }
}

OO_TEST(callsBackForTheNextStickControl) {
  ClearStickDefaults();
  {
    std::shared_ptr<DecodingStickManager> manager = NewDecodingManager();
    StickCallbackTarget target;
    manager->setFunction(AXIS_YAW, StickFn(true, 0, 2));

    // An axis callback ignores buttons, and an axis moved less than the
    // threshold.
    manager->setCallback(target.callback(), HW_AXIS);
    SDL_JoyButtonEvent press = Button(0, 0, true);
    manager->decodeButtonEvent(&press);
    OO_CHECK(target._calls == 0);
    OO_CHECK(manager->getButtonState(BUTTON_FIRE));
    SDL_JoyAxisEvent evt = Axis(0, 2, AXCBTHRESH);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(target._calls == 0);
    OO_CHECK(manager->getAxisState(AXIS_YAW) ==
             manager->getProfileForAxis(AXIS_YAW)->value(0.0));  // nor decoded
    evt = Axis(1, 2, AXCBTHRESH + 1);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(target._calls == 1);
    OO_CHECK(target._picked == StickFn(true, 1, 2));

    // Once only: the next movement is decoded.
    evt = Axis(0, 2, 32767);
    manager->decodeAxisEvent(&evt);
    OO_CHECK(target._calls == 1);
    OO_CHECK(
        manager->getAxisState(AXIS_YAW) ==
        manager->getProfileForAxis(AXIS_YAW)->value(32767.0 / STICK_NORMALDIV));

    // A button callback.
    manager->setCallback(target.callback(), HW_AXIS | HW_BUTTON);
    SDL_JoyButtonEvent release = Button(3, 7, false);
    manager->decodeButtonEvent(&release);
    OO_CHECK(target._calls == 2);
    OO_CHECK(target._picked == StickFn(false, 3, 7));
    manager->decodeButtonEvent(&release);
    OO_CHECK(target._calls == 2);

    // A cleared callback is not called.
    manager->setCallback(target.callback(), HW_BUTTON);
    manager->clearCallback();
    manager->decodeButtonEvent(&press);
    OO_CHECK(target._calls == 2);
  }
}

OO_TEST(savesAndLoadsSettings) {
  ClearStickDefaults();
  oo::Defaults& defaults = Defaults();
  {
    std::shared_ptr<OOJoystickManager> manager = NewManager();
    manager->setFunction(AXIS_YAW, StickFn(true, 1, 6));
    manager->setFunction(BUTTON_ECM, StickFn(false, 2, 11));

    std::shared_ptr<OOJoystickStandardAxisProfile> standard =
        oo::makeRef<OOJoystickStandardAxisProfile>();
    standard->setDeadzone(0.0625);
    standard->setPower(2.5);
    standard->setParameter(0.75);
    manager->setProfile(standard.get(), AXIS_ROLL);
    OO_CHECK(manager->getProfileForAxis(AXIS_ROLL) == standard.get());

    std::shared_ptr<OOJoystickSplineAxisProfile> spline =
        oo::makeRef<OOJoystickSplineAxisProfile>();
    spline->setDeadzone(0.03125);
    spline->addControl(NSMakePoint(0.25, 0.5));
    spline->addControl(NSMakePoint(0.5, 0.625));
    manager->setProfile(spline.get(), AXIS_PITCH);
    manager->setProfile(spline.get(),
                        AXIS_THRUST);  // not a profiled axis: ignored
    OO_CHECK(manager->getProfileForAxis(AXIS_THRUST) == nullptr);

    manager->saveStickSettings();
    OO_CHECK(defaults.object(AXIS_SETTINGS) == manager->axisFunctions());
    OO_CHECK(defaults.object(BUTTON_SETTINGS) == manager->buttonFunctions());

    const oo::PList roll = defaults.object(STICK_ROLL_AXIS_PROFILE_SETTING);
    OO_CHECK(roll.get<std::string>("Type") == "Standard");
    OO_CHECK(roll.get<double>("Deadzone") == 0.0625 &&
             roll.get<double>("Power") == 2.5 &&
             roll.get<double>("Parameter") == 0.75);
    const oo::PList pitch = defaults.object(STICK_PITCH_AXIS_PROFILE_SETTING);
    OO_CHECK(pitch.get<std::string>("Type") == "Spline");
    OO_CHECK(pitch.get<double>("Deadzone") == 0.03125);
    const oo::PList* points = pitch.get<oo::PList::Array>("ControlPoints");
    OO_CHECK(points != nullptr &&
             points->count() == spline->controlPoints().size());
    OO_CHECK(defaults.object(STICK_YAW_AXIS_PROFILE_SETTING)
                 .get<std::string>("Type") == "Standard");

    // A new manager reads them all back.
    std::shared_ptr<DecodingStickManager> loaded = NewDecodingManager();
    OO_CHECK(loaded->axisFunctions() == manager->axisFunctions());
    OO_CHECK(loaded->buttonFunctions() == manager->buttonFunctions());
    OOJoystickAxisProfile* loadedRoll = loaded->getProfileForAxis(AXIS_ROLL);
    OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile*>(loadedRoll) !=
             nullptr);
    OO_CHECK(loadedRoll->deadzone() == 0.0625);
    OO_CHECK(static_cast<OOJoystickStandardAxisProfile*>(loadedRoll)->power() ==
             2.5);
    OO_CHECK(
        static_cast<OOJoystickStandardAxisProfile*>(loadedRoll)->parameter() ==
        0.75);
    OOJoystickAxisProfile* loadedPitch = loaded->getProfileForAxis(AXIS_PITCH);
    OO_CHECK(dynamic_cast<OOJoystickSplineAxisProfile*>(loadedPitch) !=
             nullptr);
    OO_CHECK(loadedPitch->deadzone() == 0.03125);
    OO_CHECK(static_cast<OOJoystickSplineAxisProfile*>(loadedPitch)
                 ->controlPoints()
                 .size() == spline->controlPoints().size());
    for (double x : {0.1, 0.3, 0.6, 0.9})
      OO_CHECK(loadedPitch->value(x) == spline->value(x));

    // Saved functions replace the default mapping, buttons included.
    OO_CHECK(loaded->getAxisState(AXIS_YAW) ==
             loaded->getProfileForAxis(AXIS_YAW)->value(0.0));
    SDL_JoyButtonEvent press = Button(0, 0, true);
    loaded->decodeButtonEvent(&press);
    OO_CHECK(loaded->getButtonState(
        BUTTON_FIRE));  // still saved on stick 0 button 0
    loaded->unsetButtonFunction(BUTTON_FIRE);
    loaded->saveStickSettings();
    std::shared_ptr<OOJoystickManager> noFire = NewManager();
    OO_CHECK(noFire->buttonFunctions() ==
             Functions({{BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)},
                        {BUTTON_ECM, StickFn(false, 2, 11)}}));
  }
  ClearStickDefaults();
}

OO_TEST(subclassOverrides) {
  ClearStickDefaults();
  Defaults().setObject(AXIS_SETTINGS,
                       Functions({{AXIS_THRUST, StickFn(true, 0, 1)}}));
  {
    // -init reads the saved functions through the subclass's axis reader.
    std::shared_ptr<TestStickManager> manager = NewTestStickManager();
    OO_CHECK(manager->getAxisState(AXIS_THRUST) == 0.25);
    OO_CHECK(manager->joystickCount() == 2);
    OO_CHECK(manager->listSticks() ==
             std::vector<std::string>({"stick 0", ""}));
    OO_CHECK(manager->superNameOfJoystick(1) ==
             std::optional<std::string>("Dummy joystick"));

    manager->setFunction(AXIS_ROLL, StickFn(true, 0, 1));
    const double half = manager->getProfileForAxis(AXIS_ROLL)->value(0.5);
    OO_CHECK(manager->getAxisState(AXIS_ROLL) == half);
    // The default mapping (no buttons were saved) took the thrust's axis for
    // pitch without unassigning the thrust, so the thrust keeps the value it
    // read.
    OO_CHECK(manager->getAxisState(AXIS_THRUST) == 0.25);

    // What the subclass does not override is the base's.
    SDL_JoyButtonEvent press = Button(1, 1, true);
    manager->decodeButtonEvent(&press);
    OO_CHECK(manager->isButtonDown(1, 1));
  }
  ClearStickDefaults();
}

OO_TEST(sharedHandlerOfTheRegisteredClass) {
  ClearStickDefaults();
  {
    OO_CHECK(OOJoystickManager::setStickHandlerFactory(MakeTestStickManager));
    OOJoystickManager* shared = OOJoystickManager::sharedStickHandler();
    OO_CHECK(dynamic_cast<TestStickManager*>(shared) != nullptr);
    OO_CHECK(OOJoystickManager::sharedStickHandler() == shared);
    OO_CHECK(shared->joystickCount() == 2);
  }
}

// Upstream #783's GUI table: the functions BUTTON_GUILEFT .. BUTTON_GUISELECT
// live in a second button table of their own, saved under GuiJoystickButs, so
// one button can drive both a flight function and a GUI function.
// clearMappings resets this table with the others (upstream #783 does not, so
// there an unassigned button held 0, BUTTON_INCTHRUST).

namespace {

void ClearGuiStickDefaults() {
  ClearStickDefaults();
  Defaults().removeObject(GUI_BUTTON_SETTINGS);
}

}  // namespace

OO_TEST(guiFunctionsHaveATableOfTheirOwn) {
  ClearGuiStickDefaults();
  {
    std::shared_ptr<OOJoystickManager> manager = NewManager();
    const oo::PList defaultButtons =
        Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                   {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)}});
    OO_CHECK(manager->guiButtonFunctions() == oo::PList(oo::PList::Dict()));

    // A GUI function goes to the GUI table, an ordinary one to the button
    // table; the edges of the GUI range included.
    manager->setFunction(BUTTON_GUISELECT, StickFn(false, 1, 4));
    manager->setFunction(BUTTON_GUILEFT, StickFn(false, 2, 5));
    manager->setFunction(BUTTON_TOGGLEHUD, StickFn(false, 2, 6));
    OO_CHECK(manager->guiButtonFunctions() ==
             Functions({{BUTTON_GUISELECT, StickFn(false, 1, 4)},
                        {BUTTON_GUILEFT, StickFn(false, 2, 5)}}));
    OO_CHECK(manager->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)},
                        {BUTTON_TOGGLEHUD, StickFn(false, 2, 6)}}));
    manager->unsetButtonFunction(BUTTON_TOGGLEHUD);

    // A button can hold a flight function and a GUI function at once.
    manager->setFunction(BUTTON_GUIPAGEDOWN, StickFn(false, 0, 0));
    OO_CHECK(manager->buttonFunctions() == defaultButtons);
    const oo::PList guiFunctions = manager->guiButtonFunctions();
    const oo::PList* pageDown = guiFunctions.find(ENUMKEY(BUTTON_GUIPAGEDOWN));
    OO_CHECK(pageDown != nullptr && *pageDown == StickFn(false, 0, 0));

    // Moving a GUI function frees its old button.
    manager->setFunction(BUTTON_GUISELECT, StickFn(false, 3, 7));
    OO_CHECK(manager->guiButtonFunctions() ==
             Functions({{BUTTON_GUISELECT, StickFn(false, 3, 7)},
                        {BUTTON_GUILEFT, StickFn(false, 2, 5)},
                        {BUTTON_GUIPAGEDOWN, StickFn(false, 0, 0)}}));

    // unsetGuiButtonFunction clears it; unsetButtonFunction (what the stick
    // mapper's remove calls) does not reach the GUI table.
    manager->unsetButtonFunction(BUTTON_GUILEFT);
    const oo::PList afterUnset = manager->guiButtonFunctions();
    OO_CHECK(afterUnset.find(ENUMKEY(BUTTON_GUILEFT)) != nullptr);
    manager->unsetGuiButtonFunction(BUTTON_GUILEFT);
    manager->unsetGuiButtonFunction(BUTTON_GUIPAGEDOWN);
    OO_CHECK(manager->guiButtonFunctions() ==
             Functions({{BUTTON_GUISELECT, StickFn(false, 3, 7)}}));
    OO_CHECK(manager->buttonFunctions() == defaultButtons);

    // clearMappings clears the GUI table too.
    manager->clearMappings();
    OO_CHECK(manager->buttonFunctions() == oo::PList(oo::PList::Dict()));
    OO_CHECK(manager->guiButtonFunctions() == oo::PList(oo::PList::Dict()));
  }
}

OO_TEST(decodesGuiButtons) {
  ClearGuiStickDefaults();
  {
    std::shared_ptr<DecodingStickManager> manager = NewDecodingManager();
    manager->setFunction(BUTTON_GUIDOWN, StickFn(false, 1, 2));
    manager->setFunction(BUTTON_GUISELECT, StickFn(false, 0, 0));  // and fire

    SDL_JoyButtonEvent evt = Button(1, 2, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(manager->getButtonState(BUTTON_GUIDOWN));
    OO_CHECK(manager->getAllButtonStates()[BUTTON_GUIDOWN]);
    OO_CHECK(manager->isButtonDown(2, 1));
    evt = Button(1, 2, false);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(!manager->getButtonState(BUTTON_GUIDOWN));

    // One button, both tables: both functions follow it.
    evt = Button(0, 0, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(manager->getButtonState(BUTTON_FIRE));
    OO_CHECK(manager->getButtonState(BUTTON_GUISELECT));
    evt = Button(0, 0, false);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(!manager->getButtonState(BUTTON_FIRE));
    OO_CHECK(!manager->getButtonState(BUTTON_GUISELECT));

    // A button with no GUI function sets no other state (upstream #783's
    // never-reset table made it drive BUTTON_INCTHRUST).
    evt = Button(2, 9, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(!manager->getButtonState(BUTTON_INCTHRUST));
    evt = Button(0, 1, true);  // the missile button
    manager->decodeButtonEvent(&evt);
    OO_CHECK(manager->getButtonState(BUTTON_LAUNCHMISSILE));
    OO_CHECK(!manager->getButtonState(BUTTON_INCTHRUST));
    evt = Button(0, 1, false);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(!manager->getButtonState(BUTTON_INCTHRUST));

    // A hat's buttons reach the GUI table too (a pad's d-pad).
    manager->setFunction(BUTTON_GUIUP, StickFn(false, 0, MAX_REAL_BUTTONS));
    SDL_JoyHatEvent hat = Hat(0, 0, SDL_HAT_UP);
    manager->decodeHatEvent(&hat);
    OO_CHECK(manager->getButtonState(BUTTON_GUIUP));
    hat = Hat(0, 0, SDL_HAT_CENTERED);
    manager->decodeHatEvent(&hat);
    OO_CHECK(!manager->getButtonState(BUTTON_GUIUP));

    // A pending callback takes the press, as for any button.
    StickCallbackTarget target;
    manager->setCallback(target.callback(), HW_BUTTON);
    evt = Button(1, 2, true);
    manager->decodeButtonEvent(&evt);
    OO_CHECK(target._calls == 1);
    OO_CHECK(!manager->getButtonState(BUTTON_GUIDOWN));
  }
}

OO_TEST(savesAndLoadsGuiButtons) {
  ClearGuiStickDefaults();
  oo::Defaults& defaults = Defaults();
  {
    std::shared_ptr<OOJoystickManager> manager = NewManager();
    manager->setFunction(BUTTON_GUISELECT, StickFn(false, 1, 4));
    manager->setFunction(BUTTON_GUIPAGEUP, StickFn(false, 0, 7));
    manager->setFunction(BUTTON_ECM, StickFn(false, 2, 11));
    manager->saveStickSettings();

    const oo::PList savedGui =
        Functions({{BUTTON_GUISELECT, StickFn(false, 1, 4)},
                   {BUTTON_GUIPAGEUP, StickFn(false, 0, 7)}});
    OO_CHECK(defaults.object(GUI_BUTTON_SETTINGS) == savedGui);
    OO_CHECK(defaults.object(BUTTON_SETTINGS) ==
             Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)},
                        {BUTTON_ECM, StickFn(false, 2, 11)}}));

    // A new manager reads the GUI table back and leaves the flight table as
    // saved.
    std::shared_ptr<DecodingStickManager> loaded = NewDecodingManager();
    OO_CHECK(loaded->guiButtonFunctions() == savedGui);
    OO_CHECK(loaded->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)},
                        {BUTTON_ECM, StickFn(false, 2, 11)}}));
    SDL_JoyButtonEvent evt = Button(1, 4, true);
    loaded->decodeButtonEvent(&evt);
    OO_CHECK(loaded->getButtonState(BUTTON_GUISELECT));

    // GUI settings alone still leave the default flight mapping in place.
    defaults.removeObject(BUTTON_SETTINGS);
    std::shared_ptr<OOJoystickManager> guiOnly = NewManager();
    OO_CHECK(guiOnly->guiButtonFunctions() == savedGui);
    OO_CHECK(guiOnly->buttonFunctions() ==
             Functions({{BUTTON_FIRE, StickFn(false, 0, 0)},
                        {BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1)}}));
  }
  ClearGuiStickDefaults();
}

OO_TEST(cleanUp) {
  std::error_code ignored;
  stdfs::remove_all(sRoot, ignored);
}

OO_TEST_MAIN()
