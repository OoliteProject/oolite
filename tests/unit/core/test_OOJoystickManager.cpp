/*	test_OOJoystickManager.mm
	Unit tests for OOJoystickManager (src/Core/OOJoystickManager.h): bead oo-6bux, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056), as the root of a
	hierarchy whose one subclass (the SDL manager's facade) is still Objective-C (Amendment 1,
	bead oo-cwz; the subclass's side is amendment oo-o89).

	The manager keeps the stick-to-function tables, decodes stick events into axis and button
	states, reports the next moved axis or pressed button to a callback, and loads and saves the
	tables and the axis profiles in the user defaults. The test points the defaults' home (HOMEPATH)
	at a scratch folder before they are first read, so nothing of the user's is read or written.
	The expectations were written against the Objective-C API and run on the unconverted class
	first; they ran through the facade until beads oo-9ht.69 and oo-9ht.2 deleted it, and now call
	the same C++ members. They cover: the default mapping; axis decoding (normalised, thrust, view, raw, out of
	range, the profiles and precision mode); buttons and hats; reassigning and unsetting
	functions; the callback for both kinds of hardware; saving and reloading the tables and both
	kinds of profile; a subclass's overrides reached by the base (also from -init) and [super
	...]; the shared handler of a registered factory.
	Run: bash tools/check-core-tests.sh
*/

#include "OOJoystickManager.h"

#include "oofnd/Defaults.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <process.h>
#include <filesystem>
#include <string>
#include <vector>


// What the callback reports to (was an Objective-C object whose -stickPicked: was called by name;
// the callback is a C++ function since bead oo-9ht.69).
struct StickCallbackTarget
{
	oo::PList	_picked;
	int			_calls = 0;

	void stickPicked(const oo::PList &stickFn)
	{
		_picked = stickFn;
		_calls++;
	}

	OOJoystickManager::StickCallback callback()
	{
		return [this](const oo::PList &stickFn) { stickPicked(stickFn); };
	}
};


// A subclass as the platform managers are: two sticks, the second nameless, whose axis 1 reads
// half way. It does not override listSticks() or the setters, so the base's run on its answers.
// (An Objective-C subclass of the facade until bead oo-9ht.69.)
class TestStickManager : public OOJoystickManager
{
public:
	NSUInteger joystickCount() override
	{
		return 2;
	}

	std::optional<std::string> nameOfJoystick(NSUInteger stickNumber) override
	{
		if (stickNumber == 1)  return std::nullopt;
		return "stick " + std::to_string(stickNumber);
	}

	int16_t getAxisWithStick(NSUInteger /*stickNum*/, NSUInteger axisNum) override
	{
		return axisNum == 1 ? 16384 : 0;
	}

	std::optional<std::string> superNameOfJoystick(NSUInteger stickNumber)
	{
		return OOJoystickManager::nameOfJoystick(stickNumber);
	}
};


namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


// The scratch home, set once, before the defaults are first read.
oo::Defaults &Defaults()
{
	if (sRoot.empty())
	{
		sRoot = stdfs::temp_directory_path() / ("oo-test-joystickmanager-" + std::to_string(static_cast<unsigned long>(::_getpid())));
		stdfs::remove_all(sRoot);
		stdfs::create_directories(sRoot);
		OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	}
	return oo::Defaults::standard();
}


void ClearStickDefaults()
{
	oo::Defaults &defaults = Defaults();
	for (std::string_view key : { AXIS_SETTINGS, BUTTON_SETTINGS, STICK_ROLL_AXIS_PROFILE_SETTING, STICK_PITCH_AXIS_PROFILE_SETTING, STICK_YAW_AXIS_PROFILE_SETTING })
	{
		defaults.removeObject(key);
	}
}


oo::PList StickFn(bool isAxis, int stick, int axisOrButton)
{
	oo::PList::Dict fn;
	fn[std::string(STICK_ISAXIS)] = oo::PList(isAxis);
	fn[std::string(STICK_NUMBER)] = oo::PList(stick);
	fn[std::string(STICK_AXBUT)] = oo::PList(axisOrButton);
	return oo::PList(std::move(fn));
}


oo::PList Functions(std::initializer_list<std::pair<int, oo::PList>> entries)
{
	oo::PList::Dict result;
	for (const auto &[function, fn] : entries)  result[ENUMKEY(function)] = fn;
	return oo::PList(std::move(result));
}


JoyAxisEvent Axis(int stick, int axis, int value)
{
	JoyAxisEvent evt = {};
	evt.type = static_cast<decltype(evt.type)>(JOYAXISMOTION);
	evt.which = stick;
	evt.axis = axis;
	evt.value = value;
	return evt;
}


JoyButtonEvent Button(int stick, int button, bool down)
{
	JoyButtonEvent evt = {};
	evt.type = static_cast<decltype(evt.type)>(down ? JOYBUTTONDOWN : JOYBUTTONUP);
	evt.which = stick;
	evt.button = button;
	evt.down = down;
	return evt;
}


JoyHatEvent Hat(int stick, int hat, int value)
{
	JoyHatEvent evt = {};
	evt.type = static_cast<decltype(evt.type)>(JOYHAT_MOTION);
	evt.which = stick;
	evt.hat = hat;
	evt.value = value;
	return evt;
}


// [[OOJoystickManager alloc] init]: made, then -init's body.
oo::Ref<OOJoystickManager> NewManager()
{
	Defaults();
	oo::Ref<OOJoystickManager> manager = oo::makeRef<OOJoystickManager>();
	manager->init();
	return manager;
}


oo::Ref<TestStickManager> NewTestStickManager()
{
	oo::Ref<TestStickManager> manager = oo::makeRef<TestStickManager>();
	manager->init();
	return manager;
}


// The registered factory: it makes the manager; sharedStickHandler() runs init().
oo::Ref<OOJoystickManager> MakeTestStickManager()
{
	return oo::makeRef<TestStickManager>();
}

}	// namespace


OO_TEST(defaultMapping)
{
	ClearStickDefaults();
	{
		oo::Ref<OOJoystickManager> manager = NewManager();
		OO_CHECK(manager != nullptr);

		// No hardware in the base class.
		OO_CHECK(manager->joystickCount() == 0);
		OO_CHECK(manager->nameOfJoystick(0) == std::optional<std::string>("Dummy joystick"));
		OO_CHECK(manager->getAxisWithStick(0, 0) == 0);
		OO_CHECK(manager->listSticks().empty());

		// Nothing saved: stick 0's axes 0/1 are roll/pitch, its buttons 0/1 fire/missile.
		OO_CHECK(manager->axisFunctions() == Functions({ { AXIS_ROLL, StickFn(true, 0, 0) }, { AXIS_PITCH, StickFn(true, 0, 1) } }));
		OO_CHECK(manager->buttonFunctions() == Functions({ { BUTTON_FIRE, StickFn(false, 0, 0) }, { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) } }));

		// Every axis is unassigned until an event or a setting gives it a value.
		OO_CHECK(manager->getAxisState(AXIS_ROLL) == STICK_AXISUNASSIGNED);
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == STICK_AXISUNASSIGNED);
		OO_CHECK(manager->rollPitchAxis().x == STICK_AXISUNASSIGNED && manager->rollPitchAxis().y == STICK_AXISUNASSIGNED);
		OO_CHECK(manager->viewAxis().x == STICK_AXISUNASSIGNED && manager->viewAxis().y == STICK_AXISUNASSIGNED);
		OO_CHECK(manager->getSensitivity() == 1.0);
		bool anyButton = false;
		for (int i = 0; i < BUTTON_end; i++)  anyButton = anyButton || manager->getButtonState(i);
		OO_CHECK(!anyButton);

		// Roll, pitch and yaw have standard profiles; nothing else has one.
		OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile *>(manager->getProfileForAxis(AXIS_ROLL)) != nullptr);
		OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile *>(manager->getProfileForAxis(AXIS_PITCH)) != nullptr);
		OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile *>(manager->getProfileForAxis(AXIS_YAW)) != nullptr);
		OO_CHECK(manager->getProfileForAxis(AXIS_THRUST) == nullptr);
	}
}


OO_TEST(decodesAxes)
{
	ClearStickDefaults();
	{
		oo::Ref<OOJoystickManager> manager = NewManager();

		// Assigning reads the axis now (the base reads 0) and moves the function off its old axis.
		manager->setFunction(AXIS_ROLL, StickFn(true, 0, 2));
		manager->setFunction(AXIS_THRUST, StickFn(true, 1, 3));
		manager->setFunction(AXIS_VIEWX, StickFn(true, 0, 4));
		manager->setFunction(AXIS_PRECISION, StickFn(true, 0, 5));
		OO_CHECK(manager->axisFunctions() == Functions({ { AXIS_ROLL, StickFn(true, 0, 2) }, { AXIS_PITCH, StickFn(true, 0, 1) }, { AXIS_THRUST, StickFn(true, 1, 3) },
			{ AXIS_VIEWX, StickFn(true, 0, 4) }, { AXIS_PRECISION, StickFn(true, 0, 5) } }));
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == 0.5);
		OO_CHECK(manager->getAxisState(AXIS_VIEWX) == 0.0);

		JoyAxisEvent evt = Axis(0, 2, 16384);
		manager->decodeAxisEvent(&evt);
		OOJoystickAxisProfile *roll = manager->getProfileForAxis(AXIS_ROLL);
		const double rollValue = roll->value(0.5);
		OO_CHECK(rollValue > 0.0);
		OO_CHECK(manager->getAxisState(AXIS_ROLL) == rollValue);
		OO_CHECK(manager->rollPitchAxis().x == rollValue);

		evt = Axis(1, 3, -32768);
		manager->decodeAxisEvent(&evt);
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == 1.0);
		evt = Axis(1, 3, 32767);
		manager->decodeAxisEvent(&evt);
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == (float)(65536 - (32767.0 + 32768)) / 65536);

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
		JoyButtonEvent press = Button(0, 5, true);
		manager->decodeButtonEvent(&press);
		OO_CHECK(manager->getSensitivity() == STICK_PRECISIONFAC);
		OO_CHECK(manager->getAxisState(AXIS_ROLL) == rollValue / STICK_PRECISIONFAC);
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == (float)(65536 - (32767.0 + 32768)) / 65536);
		manager->decodeButtonEvent(&press);
		OO_CHECK(manager->getSensitivity() == 1.0);
		OO_CHECK(manager->getAxisState(AXIS_ROLL) == rollValue);

		// Unsetting a function unassigns its axis.
		manager->unsetAxisFunction(AXIS_ROLL);
		OO_CHECK(manager->getAxisState(AXIS_ROLL) == STICK_AXISUNASSIGNED);
		OO_CHECK(manager->axisFunctions() == Functions({ { AXIS_PITCH, StickFn(true, 0, 1) }, { AXIS_THRUST, StickFn(true, 1, 3) },
			{ AXIS_VIEWX, StickFn(true, 0, 4) }, { AXIS_PRECISION, StickFn(true, 0, 5) } }));
	}
}


OO_TEST(decodesButtonsAndHats)
{
	ClearStickDefaults();
	{
		oo::Ref<OOJoystickManager> manager = NewManager();

		JoyButtonEvent evt = Button(0, 0, true);
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

		// An unmapped button is tracked per stick only; one out of range is ignored.
		evt = Button(2, 9, true);
		manager->decodeButtonEvent(&evt);
		OO_CHECK(manager->isButtonDown(9, 2));
		evt = Button(0, MAX_BUTTONS, true);
		manager->decodeButtonEvent(&evt);

		// Moving a function to another button frees the old one.
		manager->setFunction(BUTTON_FIRE, StickFn(false, 1, 3));
		OO_CHECK(manager->buttonFunctions() == Functions({ { BUTTON_FIRE, StickFn(false, 1, 3) }, { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) } }));
		evt = Button(1, 3, true);
		manager->decodeButtonEvent(&evt);
		OO_CHECK(manager->getButtonState(BUTTON_FIRE));
		manager->unsetButtonFunction(BUTTON_LAUNCHMISSILE);
		OO_CHECK(manager->buttonFunctions() == Functions({ { BUTTON_FIRE, StickFn(false, 1, 3) } }));

		// A hat is four buttons past the real ones, four per stick, one bit each.
		manager->setFunction(BUTTON_ID, StickFn(false, 1, MAX_REAL_BUTTONS + 4 + 2));
		JoyHatEvent hat = Hat(1, 0, JOYHAT_DOWN | JOYHAT_RIGHT);
		manager->decodeHatEvent(&hat);
		OO_CHECK(manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 1, 1));
		OO_CHECK(manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 2, 1));
		OO_CHECK(!manager->isButtonDown(MAX_REAL_BUTTONS + 4 + 0, 1));
		OO_CHECK(manager->getButtonState(BUTTON_ID));
		hat = Hat(1, 0, JOYHAT_RIGHT);
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
		OO_CHECK(manager->buttonFunctions() == Functions({ { BUTTON_FIRE, StickFn(false, 0, 0) }, { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) } }));
	}
}


OO_TEST(callsBackForTheNextStickControl)
{
	ClearStickDefaults();
	{
		oo::Ref<OOJoystickManager> manager = NewManager();
		StickCallbackTarget target;
		manager->setFunction(AXIS_YAW, StickFn(true, 0, 2));

		// An axis callback ignores buttons, and an axis moved less than the threshold.
		manager->setCallback(target.callback(), HW_AXIS);
		JoyButtonEvent press = Button(0, 0, true);
		manager->decodeButtonEvent(&press);
		OO_CHECK(target._calls == 0);
		OO_CHECK(manager->getButtonState(BUTTON_FIRE));
		JoyAxisEvent evt = Axis(0, 2, AXCBTHRESH);
		manager->decodeAxisEvent(&evt);
		OO_CHECK(target._calls == 0);
		OO_CHECK(manager->getAxisState(AXIS_YAW) == manager->getProfileForAxis(AXIS_YAW)->value(0.0));	// nor decoded
		evt = Axis(1, 2, AXCBTHRESH + 1);
		manager->decodeAxisEvent(&evt);
		OO_CHECK(target._calls == 1);
		OO_CHECK(target._picked == StickFn(true, 1, 2));

		// Once only: the next movement is decoded.
		evt = Axis(0, 2, 32767);
		manager->decodeAxisEvent(&evt);
		OO_CHECK(target._calls == 1);
		OO_CHECK(manager->getAxisState(AXIS_YAW) == manager->getProfileForAxis(AXIS_YAW)->value(32767.0 / STICK_NORMALDIV));

		// A button callback.
		manager->setCallback(target.callback(), HW_AXIS | HW_BUTTON);
		JoyButtonEvent release = Button(3, 7, false);
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


OO_TEST(savesAndLoadsSettings)
{
	ClearStickDefaults();
	oo::Defaults &defaults = Defaults();
	{
		oo::Ref<OOJoystickManager> manager = NewManager();
		manager->setFunction(AXIS_YAW, StickFn(true, 1, 6));
		manager->setFunction(BUTTON_ECM, StickFn(false, 2, 11));

		oo::Ref<OOJoystickStandardAxisProfile> standard = oo::makeRef<OOJoystickStandardAxisProfile>();
		standard->setDeadzone(0.0625);
		standard->setPower(2.5);
		standard->setParameter(0.75);
		manager->setProfile(standard.get(), AXIS_ROLL);
		OO_CHECK(manager->getProfileForAxis(AXIS_ROLL) == standard.get());

		oo::Ref<OOJoystickSplineAxisProfile> spline = oo::makeRef<OOJoystickSplineAxisProfile>();
		spline->setDeadzone(0.03125);
		spline->addControl(NSMakePoint(0.25, 0.5));
		spline->addControl(NSMakePoint(0.5, 0.625));
		manager->setProfile(spline.get(), AXIS_PITCH);
		manager->setProfile(spline.get(), AXIS_THRUST);	// not a profiled axis: ignored
		OO_CHECK(manager->getProfileForAxis(AXIS_THRUST) == nullptr);

		manager->saveStickSettings();
		OO_CHECK(defaults.object(AXIS_SETTINGS) == manager->axisFunctions());
		OO_CHECK(defaults.object(BUTTON_SETTINGS) == manager->buttonFunctions());

		const oo::PList roll = defaults.object(STICK_ROLL_AXIS_PROFILE_SETTING);
		OO_CHECK(roll.get<std::string>("Type") == "Standard");
		OO_CHECK(roll.get<double>("Deadzone") == 0.0625 && roll.get<double>("Power") == 2.5 && roll.get<double>("Parameter") == 0.75);
		const oo::PList pitch = defaults.object(STICK_PITCH_AXIS_PROFILE_SETTING);
		OO_CHECK(pitch.get<std::string>("Type") == "Spline");
		OO_CHECK(pitch.get<double>("Deadzone") == 0.03125);
		const oo::PList *points = pitch.get<oo::PList::Array>("ControlPoints");
		OO_CHECK(points != nullptr && points->count() == spline->controlPoints().size());
		OO_CHECK(defaults.object(STICK_YAW_AXIS_PROFILE_SETTING).get<std::string>("Type") == "Standard");

		// A new manager reads them all back.
		oo::Ref<OOJoystickManager> loaded = NewManager();
		OO_CHECK(loaded->axisFunctions() == manager->axisFunctions());
		OO_CHECK(loaded->buttonFunctions() == manager->buttonFunctions());
		OOJoystickAxisProfile *loadedRoll = loaded->getProfileForAxis(AXIS_ROLL);
		OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile *>(loadedRoll) != nullptr);
		OO_CHECK(loadedRoll->deadzone() == 0.0625);
		OO_CHECK(static_cast<OOJoystickStandardAxisProfile *>(loadedRoll)->power() == 2.5);
		OO_CHECK(static_cast<OOJoystickStandardAxisProfile *>(loadedRoll)->parameter() == 0.75);
		OOJoystickAxisProfile *loadedPitch = loaded->getProfileForAxis(AXIS_PITCH);
		OO_CHECK(dynamic_cast<OOJoystickSplineAxisProfile *>(loadedPitch) != nullptr);
		OO_CHECK(loadedPitch->deadzone() == 0.03125);
		OO_CHECK(static_cast<OOJoystickSplineAxisProfile *>(loadedPitch)->controlPoints().size() == spline->controlPoints().size());
		for (double x : { 0.1, 0.3, 0.6, 0.9 })  OO_CHECK(loadedPitch->value(x) == spline->value(x));

		// Saved functions replace the default mapping, buttons included.
		OO_CHECK(loaded->getAxisState(AXIS_YAW) == loaded->getProfileForAxis(AXIS_YAW)->value(0.0));
		JoyButtonEvent press = Button(0, 0, true);
		loaded->decodeButtonEvent(&press);
		OO_CHECK(loaded->getButtonState(BUTTON_FIRE));	// still saved on stick 0 button 0
		loaded->unsetButtonFunction(BUTTON_FIRE);
		loaded->saveStickSettings();
		oo::Ref<OOJoystickManager> noFire = NewManager();
		OO_CHECK(noFire->buttonFunctions() == Functions({ { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) }, { BUTTON_ECM, StickFn(false, 2, 11) } }));
	}
	ClearStickDefaults();
}


OO_TEST(subclassOverrides)
{
	ClearStickDefaults();
	Defaults().setObject(AXIS_SETTINGS, Functions({ { AXIS_THRUST, StickFn(true, 0, 1) } }));
	{
		// -init reads the saved functions through the subclass's axis reader.
		oo::Ref<TestStickManager> manager = NewTestStickManager();
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == 0.25);
		OO_CHECK(manager->joystickCount() == 2);
		OO_CHECK(manager->listSticks() == std::vector<std::string>({ "stick 0", "" }));
		OO_CHECK(manager->superNameOfJoystick(1) == std::optional<std::string>("Dummy joystick"));

		manager->setFunction(AXIS_ROLL, StickFn(true, 0, 1));
		const double half = manager->getProfileForAxis(AXIS_ROLL)->value(0.5);
		OO_CHECK(manager->getAxisState(AXIS_ROLL) == half);
		// The default mapping (no buttons were saved) took the thrust's axis for pitch without
		// unassigning the thrust, so the thrust keeps the value it read.
		OO_CHECK(manager->getAxisState(AXIS_THRUST) == 0.25);

		// What the subclass does not override is the base's.
		JoyButtonEvent press = Button(1, 1, true);
		manager->decodeButtonEvent(&press);
		OO_CHECK(manager->isButtonDown(1, 1));
	}
	ClearStickDefaults();
}


OO_TEST(sharedHandlerOfTheRegisteredClass)
{
	ClearStickDefaults();
	{
		OO_CHECK(OOJoystickManager::setStickHandlerFactory(MakeTestStickManager));
		OOJoystickManager *shared = OOJoystickManager::sharedStickHandler();
		OO_CHECK(dynamic_cast<TestStickManager *>(shared) != nullptr);
		OO_CHECK(OOJoystickManager::sharedStickHandler() == shared);
		OO_CHECK(shared->joystickCount() == 2);
	}
}


OO_TEST(cleanUp)
{
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
}


OO_TEST_MAIN()
