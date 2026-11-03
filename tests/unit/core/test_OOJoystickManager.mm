/*	test_OOJoystickManager.mm
	Unit tests for OOJoystickManager (src/Core/OOJoystickManager.h): bead oo-6bux, a Phase 3
	conversion in the house style of the OOColor exemplar (proposed ADR-0056), as the root of a
	hierarchy whose one subclass (the SDL manager's facade) is still Objective-C (Amendment 1,
	bead oo-cwz; the subclass's side is amendment oo-o89).

	The manager keeps the stick-to-function tables, decodes stick events into axis and button
	states (the SDL manager decodes, upstream #742: the cases that decode use an SDL manager that
	answers for the hardware as the base does), reports the next moved axis or pressed button to a callback, and loads and saves the
	tables and the axis profiles in the user defaults. The test points the defaults' home (HOMEPATH)
	at a scratch folder before they are first read, so nothing of the user's is read or written.
	The expectations were written against the Objective-C API and run on the unconverted class
	first; they now run through the facade, which is its forwarding test (amendment oo-8kx7 item
	6). They cover: the default mapping; axis decoding (normalised, thrust, view, raw, out of
	range, the profiles and precision mode); buttons and hats; reassigning and unsetting
	functions; the callback for both kinds of hardware; saving and reloading the tables and both
	kinds of profile; a subclass's overrides reached by the base (also from -init) and [super
	...]; the shared handler of a registered class. The facade's contract follows.
	Run: bash tools/check-core-tests.sh
*/

#import "OOJoystickManager.h"
#import "OOSDLJoystickManager.h"

#include "oofnd/Defaults.hpp"
#include "oo_test.hpp"

#include <cstdlib>
#include <process.h>
#include <filesystem>
#include <string>
#include <vector>


@interface StickCallbackTarget: OOObject
{
@public
	oo::PList	_picked;
	int			_calls;
}
- (void) stickPicked:(const oo::PList &)stickFn;
@end


@implementation StickCallbackTarget

- (void) stickPicked:(const oo::PList &)stickFn
{
	_picked = stickFn;
	_calls++;
}

@end


// A subclass as the platform managers are: two sticks, the second nameless, whose axis 1 reads
// half way. It does not override -listSticks or the setters, so the base's run on its answers.
// It is an SDL manager, which decodes the events (upstream #742).
@interface TestStickManager: OOSDLJoystickManager
- (std::optional<std::string>) superNameOfJoystick:(NSUInteger)stickNumber;
@end


@implementation TestStickManager

- (NSUInteger) joystickCount
{
	return 2;
}


- (std::optional<std::string>) nameOfJoystick:(NSUInteger)stickNumber
{
	if (stickNumber == 1)  return std::nullopt;
	return "stick " + std::to_string(stickNumber);
}


- (int16_t) getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
	return axisNum == 1 ? 16384 : 0;
}


- (std::optional<std::string>) superNameOfJoystick:(NSUInteger)stickNumber
{
	// OOJoystickManager's own member (the SDL manager's facade, its superclass, overrides it).
	return oo::ToCxx(static_cast<OOJoystickManager *>(self))->cxx::OOJoystickManager::nameOfJoystick(stickNumber);
}

@end


// The SDL manager, which decodes stick events into the base's tables (upstream #742), answering
// for the hardware as the base does (no sticks, "Dummy joystick", axes at 0), so the decoding
// cases see the base's tables only.
@interface DecodingStickManager: OOSDLJoystickManager
@end


@implementation DecodingStickManager

- (NSUInteger) joystickCount
{
	return oo::ToCxx(static_cast<OOJoystickManager *>(self))->cxx::OOJoystickManager::joystickCount();
}


- (std::optional<std::string>) nameOfJoystick:(NSUInteger)stickNumber
{
	return oo::ToCxx(static_cast<OOJoystickManager *>(self))->cxx::OOJoystickManager::nameOfJoystick(stickNumber);
}


- (int16_t) getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
	return oo::ToCxx(static_cast<OOJoystickManager *>(self))->cxx::OOJoystickManager::getAxisWithStick(stickNum, axisNum);
}

@end


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


// SDL's events, with the stick index where SDL has its id (as OOSDLJoystickManager's
// makeJoy...Event: methods pass them on).
SDL_JoyAxisEvent Axis(int stick, int axis, int value)
{
	SDL_JoyAxisEvent evt = {};
	evt.type = SDL_EVENT_JOYSTICK_AXIS_MOTION;
	evt.which = stick;
	evt.axis = axis;
	evt.value = value;
	return evt;
}


SDL_JoyButtonEvent Button(int stick, int button, bool down)
{
	SDL_JoyButtonEvent evt = {};
	evt.type = down ? SDL_EVENT_JOYSTICK_BUTTON_DOWN : SDL_EVENT_JOYSTICK_BUTTON_UP;
	evt.which = stick;
	evt.button = button;
	evt.down = down;
	return evt;
}


SDL_JoyHatEvent Hat(int stick, int hat, int value)
{
	SDL_JoyHatEvent evt = {};
	evt.type = SDL_EVENT_JOYSTICK_HAT_MOTION;
	evt.which = stick;
	evt.hat = hat;
	evt.value = value;
	return evt;
}


OOJoystickManager *NewManager()
{
	Defaults();
	return [[[OOJoystickManager alloc] init] autorelease];
}


// The decoding manager, made the same way.
DecodingStickManager *NewDecodingManager()
{
	Defaults();
	return [[[DecodingStickManager alloc] init] autorelease];
}

}	// namespace


OO_TEST(defaultMapping)
{
	ClearStickDefaults();
	@autoreleasepool
	{
		OOJoystickManager *manager = NewManager();
		OO_CHECK(manager != nil);

		// No hardware in the base class.
		OO_CHECK([manager joystickCount] == 0);
		OO_CHECK([manager nameOfJoystick:0] == std::optional<std::string>("Dummy joystick"));
		OO_CHECK([manager getAxisWithStick:0 axis:0] == 0);
		OO_CHECK([manager listSticks].empty());

		// Nothing saved: stick 0's axes 0/1 are roll/pitch, its buttons 0/1 fire/missile.
		OO_CHECK([manager axisFunctions] == Functions({ { AXIS_ROLL, StickFn(true, 0, 0) }, { AXIS_PITCH, StickFn(true, 0, 1) } }));
		OO_CHECK([manager buttonFunctions] == Functions({ { BUTTON_FIRE, StickFn(false, 0, 0) }, { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) } }));

		// Every axis is unassigned until an event or a setting gives it a value.
		OO_CHECK([manager getAxisState:AXIS_ROLL] == STICK_AXISUNASSIGNED);
		OO_CHECK([manager getAxisState:AXIS_THRUST] == STICK_AXISUNASSIGNED);
		OO_CHECK([manager rollPitchAxis].x == STICK_AXISUNASSIGNED && [manager rollPitchAxis].y == STICK_AXISUNASSIGNED);
		OO_CHECK([manager viewAxis].x == STICK_AXISUNASSIGNED && [manager viewAxis].y == STICK_AXISUNASSIGNED);
		OO_CHECK([manager getSensitivity] == 1.0);
		bool anyButton = false;
		for (int i = 0; i < BUTTON_end; i++)  anyButton = anyButton || [manager getButtonState:i];
		OO_CHECK(!anyButton);

		// Roll, pitch and yaw have standard profiles; nothing else has one.
		OO_CHECK([[manager getProfileForAxis:AXIS_ROLL] isKindOfClass:[OOJoystickStandardAxisProfile class]]);
		OO_CHECK([[manager getProfileForAxis:AXIS_PITCH] isKindOfClass:[OOJoystickStandardAxisProfile class]]);
		OO_CHECK([[manager getProfileForAxis:AXIS_YAW] isKindOfClass:[OOJoystickStandardAxisProfile class]]);
		OO_CHECK([manager getProfileForAxis:AXIS_THRUST] == nil);
	}
}


OO_TEST(decodesAxes)
{
	ClearStickDefaults();
	@autoreleasepool
	{
		DecodingStickManager *manager = NewDecodingManager();

		// Assigning reads the axis now (the base reads 0) and moves the function off its old axis.
		[manager setFunction:AXIS_ROLL withDict:StickFn(true, 0, 2)];
		[manager setFunction:AXIS_THRUST withDict:StickFn(true, 1, 3)];
		[manager setFunction:AXIS_VIEWX withDict:StickFn(true, 0, 4)];
		[manager setFunction:AXIS_PRECISION withDict:StickFn(true, 0, 5)];
		OO_CHECK([manager axisFunctions] == Functions({ { AXIS_ROLL, StickFn(true, 0, 2) }, { AXIS_PITCH, StickFn(true, 0, 1) }, { AXIS_THRUST, StickFn(true, 1, 3) },
			{ AXIS_VIEWX, StickFn(true, 0, 4) }, { AXIS_PRECISION, StickFn(true, 0, 5) } }));
		OO_CHECK([manager getAxisState:AXIS_THRUST] == 0.5);
		OO_CHECK([manager getAxisState:AXIS_VIEWX] == 0.0);

		SDL_JoyAxisEvent evt = Axis(0, 2, 16384);
		[manager decodeAxisEvent:&evt];
		OOJoystickAxisProfile *roll = [manager getProfileForAxis:AXIS_ROLL];
		const double rollValue = [roll value:0.5];
		OO_CHECK(rollValue > 0.0);
		OO_CHECK([manager getAxisState:AXIS_ROLL] == rollValue);
		OO_CHECK([manager rollPitchAxis].x == rollValue);

		evt = Axis(1, 3, -32768);
		[manager decodeAxisEvent:&evt];
		OO_CHECK([manager getAxisState:AXIS_THRUST] == 1.0);
		evt = Axis(1, 3, 32767);
		[manager decodeAxisEvent:&evt];
		OO_CHECK([manager getAxisState:AXIS_THRUST] == (float)(65536 - (32767.0 + 32768)) / 65536);

		evt = Axis(0, 4, -32768);
		[manager decodeAxisEvent:&evt];
		OO_CHECK([manager viewAxis].x == -1.0);
		evt = Axis(0, 5, 8192);
		[manager decodeAxisEvent:&evt];
		OO_CHECK([manager getAxisState:AXIS_PRECISION] == 0.25);

		// An unassigned axis, and one out of range, change nothing.
		evt = Axis(0, 7, 1000);
		[manager decodeAxisEvent:&evt];
		evt = Axis(0, MAX_AXES, 1000);
		[manager decodeAxisEvent:&evt];
		OO_CHECK([manager getAxisState:AXIS_ROLL] == rollValue);
		OO_CHECK([manager getAxisState:AXIS_YAW] == STICK_AXISUNASSIGNED);

		// Precision mode (a button) divides the profiled axes.
		[manager setFunction:BUTTON_PRECISION withDict:StickFn(false, 0, 5)];
		SDL_JoyButtonEvent press = Button(0, 5, true);
		[manager decodeButtonEvent:&press];
		OO_CHECK([manager getSensitivity] == STICK_PRECISIONFAC);
		OO_CHECK([manager getAxisState:AXIS_ROLL] == rollValue / STICK_PRECISIONFAC);
		OO_CHECK([manager getAxisState:AXIS_THRUST] == (float)(65536 - (32767.0 + 32768)) / 65536);
		[manager decodeButtonEvent:&press];
		OO_CHECK([manager getSensitivity] == 1.0);
		OO_CHECK([manager getAxisState:AXIS_ROLL] == rollValue);

		// Unsetting a function unassigns its axis.
		[manager unsetAxisFunction:AXIS_ROLL];
		OO_CHECK([manager getAxisState:AXIS_ROLL] == STICK_AXISUNASSIGNED);
		OO_CHECK([manager axisFunctions] == Functions({ { AXIS_PITCH, StickFn(true, 0, 1) }, { AXIS_THRUST, StickFn(true, 1, 3) },
			{ AXIS_VIEWX, StickFn(true, 0, 4) }, { AXIS_PRECISION, StickFn(true, 0, 5) } }));
	}
}


OO_TEST(decodesButtonsAndHats)
{
	ClearStickDefaults();
	@autoreleasepool
	{
		DecodingStickManager *manager = NewDecodingManager();

		SDL_JoyButtonEvent evt = Button(0, 0, true);
		[manager decodeButtonEvent:&evt];
		OO_CHECK([manager getButtonState:BUTTON_FIRE]);
		OO_CHECK([manager getAllButtonStates][BUTTON_FIRE]);
		OO_CHECK([manager isButtonDown:0 stick:0]);
		OO_CHECK(![manager isButtonDown:0 stick:1]);

		// Clearing the function's state leaves the stick's.
		[manager clearStickButtonState:BUTTON_FIRE];
		OO_CHECK(![manager getButtonState:BUTTON_FIRE]);
		OO_CHECK([manager isButtonDown:0 stick:0]);
		[manager clearStickButtonState:-1];
		[manager clearStickButtonState:BUTTON_end];

		evt = Button(0, 0, false);
		[manager decodeButtonEvent:&evt];
		OO_CHECK(![manager isButtonDown:0 stick:0]);

		// An unmapped button is tracked per stick only; one out of range is ignored.
		evt = Button(2, 9, true);
		[manager decodeButtonEvent:&evt];
		OO_CHECK([manager isButtonDown:9 stick:2]);
		evt = Button(0, MAX_BUTTONS, true);
		[manager decodeButtonEvent:&evt];

		// Moving a function to another button frees the old one.
		[manager setFunction:BUTTON_FIRE withDict:StickFn(false, 1, 3)];
		OO_CHECK([manager buttonFunctions] == Functions({ { BUTTON_FIRE, StickFn(false, 1, 3) }, { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) } }));
		evt = Button(1, 3, true);
		[manager decodeButtonEvent:&evt];
		OO_CHECK([manager getButtonState:BUTTON_FIRE]);
		[manager unsetButtonFunction:BUTTON_LAUNCHMISSILE];
		OO_CHECK([manager buttonFunctions] == Functions({ { BUTTON_FIRE, StickFn(false, 1, 3) } }));

		// A hat is four buttons past the real ones, four per stick, one bit each.
		[manager setFunction:BUTTON_ID withDict:StickFn(false, 1, MAX_REAL_BUTTONS + 4 + 2)];
		SDL_JoyHatEvent hat = Hat(1, 0, SDL_HAT_DOWN | SDL_HAT_RIGHT);
		[manager decodeHatEvent:&hat];
		OO_CHECK([manager isButtonDown:MAX_REAL_BUTTONS + 4 + 1 stick:1]);
		OO_CHECK([manager isButtonDown:MAX_REAL_BUTTONS + 4 + 2 stick:1]);
		OO_CHECK(![manager isButtonDown:MAX_REAL_BUTTONS + 4 + 0 stick:1]);
		OO_CHECK([manager getButtonState:BUTTON_ID]);
		hat = Hat(1, 0, SDL_HAT_RIGHT);
		[manager decodeHatEvent:&hat];
		OO_CHECK([manager isButtonDown:MAX_REAL_BUTTONS + 4 + 1 stick:1]);
		OO_CHECK(![manager isButtonDown:MAX_REAL_BUTTONS + 4 + 2 stick:1]);
		OO_CHECK(![manager getButtonState:BUTTON_ID]);

		[manager clearStickStates];
		OO_CHECK(![manager getButtonState:BUTTON_FIRE]);
		OO_CHECK(![manager isButtonDown:MAX_REAL_BUTTONS + 4 + 1 stick:1]);
		OO_CHECK([manager getAxisState:AXIS_PITCH] == STICK_AXISUNASSIGNED);

		[manager clearMappings];
		OO_CHECK([manager axisFunctions] == oo::PList(oo::PList::Dict()));
		OO_CHECK([manager buttonFunctions] == oo::PList(oo::PList::Dict()));
		[manager setDefaultMapping];
		OO_CHECK([manager buttonFunctions] == Functions({ { BUTTON_FIRE, StickFn(false, 0, 0) }, { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) } }));
	}
}


OO_TEST(callsBackForTheNextStickControl)
{
	ClearStickDefaults();
	@autoreleasepool
	{
		DecodingStickManager *manager = NewDecodingManager();
		StickCallbackTarget *target = [[[StickCallbackTarget alloc] init] autorelease];
		[manager setFunction:AXIS_YAW withDict:StickFn(true, 0, 2)];

		// An axis callback ignores buttons, and an axis moved less than the threshold.
		[manager setCallback:@selector(stickPicked:) object:target hardware:HW_AXIS];
		SDL_JoyButtonEvent press = Button(0, 0, true);
		[manager decodeButtonEvent:&press];
		OO_CHECK(target->_calls == 0);
		OO_CHECK([manager getButtonState:BUTTON_FIRE]);
		SDL_JoyAxisEvent evt = Axis(0, 2, AXCBTHRESH);
		[manager decodeAxisEvent:&evt];
		OO_CHECK(target->_calls == 0);
		OO_CHECK([manager getAxisState:AXIS_YAW] == [[manager getProfileForAxis:AXIS_YAW] value:0.0]);	// nor decoded
		evt = Axis(1, 2, AXCBTHRESH + 1);
		[manager decodeAxisEvent:&evt];
		OO_CHECK(target->_calls == 1);
		OO_CHECK(target->_picked == StickFn(true, 1, 2));

		// Once only: the next movement is decoded.
		evt = Axis(0, 2, 32767);
		[manager decodeAxisEvent:&evt];
		OO_CHECK(target->_calls == 1);
		OO_CHECK([manager getAxisState:AXIS_YAW] == [[manager getProfileForAxis:AXIS_YAW] value:32767.0 / STICK_NORMALDIV]);

		// A button callback.
		[manager setCallback:@selector(stickPicked:) object:target hardware:HW_AXIS | HW_BUTTON];
		SDL_JoyButtonEvent release = Button(3, 7, false);
		[manager decodeButtonEvent:&release];
		OO_CHECK(target->_calls == 2);
		OO_CHECK(target->_picked == StickFn(false, 3, 7));
		[manager decodeButtonEvent:&release];
		OO_CHECK(target->_calls == 2);

		// A cleared callback is not called.
		[manager setCallback:@selector(stickPicked:) object:target hardware:HW_BUTTON];
		[manager clearCallback];
		[manager decodeButtonEvent:&press];
		OO_CHECK(target->_calls == 2);
	}
}


OO_TEST(savesAndLoadsSettings)
{
	ClearStickDefaults();
	oo::Defaults &defaults = Defaults();
	@autoreleasepool
	{
		OOJoystickManager *manager = NewManager();
		[manager setFunction:AXIS_YAW withDict:StickFn(true, 1, 6)];
		[manager setFunction:BUTTON_ECM withDict:StickFn(false, 2, 11)];

		OOJoystickStandardAxisProfile *standard = [[[OOJoystickStandardAxisProfile alloc] init] autorelease];
		[standard setDeadzone:0.0625];
		[standard setPower:2.5];
		[standard setParameter:0.75];
		[manager setProfile:standard forAxis:AXIS_ROLL];
		OO_CHECK([manager getProfileForAxis:AXIS_ROLL] == standard);

		OOJoystickSplineAxisProfile *spline = [[[OOJoystickSplineAxisProfile alloc] init] autorelease];
		[spline setDeadzone:0.03125];
		[spline addControl:NSMakePoint(0.25, 0.5)];
		[spline addControl:NSMakePoint(0.5, 0.625)];
		[manager setProfile:spline forAxis:AXIS_PITCH];
		[manager setProfile:spline forAxis:AXIS_THRUST];	// not a profiled axis: ignored
		OO_CHECK([manager getProfileForAxis:AXIS_THRUST] == nil);

		[manager saveStickSettings];
		OO_CHECK(defaults.object(AXIS_SETTINGS) == [manager axisFunctions]);
		OO_CHECK(defaults.object(BUTTON_SETTINGS) == [manager buttonFunctions]);

		const oo::PList roll = defaults.object(STICK_ROLL_AXIS_PROFILE_SETTING);
		OO_CHECK(roll.get<std::string>("Type") == "Standard");
		OO_CHECK(roll.get<double>("Deadzone") == 0.0625 && roll.get<double>("Power") == 2.5 && roll.get<double>("Parameter") == 0.75);
		const oo::PList pitch = defaults.object(STICK_PITCH_AXIS_PROFILE_SETTING);
		OO_CHECK(pitch.get<std::string>("Type") == "Spline");
		OO_CHECK(pitch.get<double>("Deadzone") == 0.03125);
		const oo::PList *points = pitch.get<oo::PList::Array>("ControlPoints");
		OO_CHECK(points != nullptr && points->count() == [spline controlPoints].size());
		OO_CHECK(defaults.object(STICK_YAW_AXIS_PROFILE_SETTING).get<std::string>("Type") == "Standard");

		// A new manager reads them all back.
		DecodingStickManager *loaded = NewDecodingManager();
		OO_CHECK([loaded axisFunctions] == [manager axisFunctions]);
		OO_CHECK([loaded buttonFunctions] == [manager buttonFunctions]);
		OOJoystickAxisProfile *loadedRoll = [loaded getProfileForAxis:AXIS_ROLL];
		OO_CHECK([loadedRoll isKindOfClass:[OOJoystickStandardAxisProfile class]]);
		OO_CHECK([loadedRoll deadzone] == 0.0625);
		OO_CHECK([(OOJoystickStandardAxisProfile *)loadedRoll power] == 2.5);
		OO_CHECK([(OOJoystickStandardAxisProfile *)loadedRoll parameter] == 0.75);
		OOJoystickAxisProfile *loadedPitch = [loaded getProfileForAxis:AXIS_PITCH];
		OO_CHECK([loadedPitch isKindOfClass:[OOJoystickSplineAxisProfile class]]);
		OO_CHECK([loadedPitch deadzone] == 0.03125);
		OO_CHECK([(OOJoystickSplineAxisProfile *)loadedPitch controlPoints].size() == [spline controlPoints].size());
		for (double x : { 0.1, 0.3, 0.6, 0.9 })  OO_CHECK([loadedPitch value:x] == [spline value:x]);

		// Saved functions replace the default mapping, buttons included.
		OO_CHECK([loaded getAxisState:AXIS_YAW] == [[loaded getProfileForAxis:AXIS_YAW] value:0.0]);
		SDL_JoyButtonEvent press = Button(0, 0, true);
		[loaded decodeButtonEvent:&press];
		OO_CHECK([loaded getButtonState:BUTTON_FIRE]);	// still saved on stick 0 button 0
		[loaded unsetButtonFunction:BUTTON_FIRE];
		[loaded saveStickSettings];
		OOJoystickManager *noFire = NewManager();
		OO_CHECK([noFire buttonFunctions] == Functions({ { BUTTON_LAUNCHMISSILE, StickFn(false, 0, 1) }, { BUTTON_ECM, StickFn(false, 2, 11) } }));
	}
	ClearStickDefaults();
}


OO_TEST(subclassOverrides)
{
	ClearStickDefaults();
	Defaults().setObject(AXIS_SETTINGS, Functions({ { AXIS_THRUST, StickFn(true, 0, 1) } }));
	@autoreleasepool
	{
		// -init reads the saved functions through the subclass's axis reader.
		TestStickManager *manager = [[[TestStickManager alloc] init] autorelease];
		OO_CHECK([manager getAxisState:AXIS_THRUST] == 0.25);
		OO_CHECK([manager joystickCount] == 2);
		OO_CHECK([manager listSticks] == std::vector<std::string>({ "stick 0", "" }));
		OO_CHECK([manager superNameOfJoystick:1] == std::optional<std::string>("Dummy joystick"));

		[manager setFunction:AXIS_ROLL withDict:StickFn(true, 0, 1)];
		const double half = [[manager getProfileForAxis:AXIS_ROLL] value:0.5];
		OO_CHECK([manager getAxisState:AXIS_ROLL] == half);
		// The default mapping (no buttons were saved) took the thrust's axis for pitch without
		// unassigning the thrust, so the thrust keeps the value it read.
		OO_CHECK([manager getAxisState:AXIS_THRUST] == 0.25);

		// What the subclass does not override is the base's.
		SDL_JoyButtonEvent press = Button(1, 1, true);
		[manager decodeButtonEvent:&press];
		OO_CHECK([manager isButtonDown:1 stick:1]);
	}
	ClearStickDefaults();
}


OO_TEST(sharedHandlerOfTheRegisteredClass)
{
	ClearStickDefaults();
	@autoreleasepool
	{
		OO_CHECK([OOJoystickManager setStickHandlerClass:[TestStickManager class]]);
		id shared = [OOJoystickManager sharedStickHandler];
		OO_CHECK([shared isKindOfClass:[TestStickManager class]]);
		OO_CHECK([OOJoystickManager sharedStickHandler] == shared);
		OO_CHECK([shared joystickCount] == 2);
	}
}


// After the conversion: the C++ manager answers as the facade did, the facade and the C++ object
// cross both ways with one facade per manager, an Objective-C subclass's C++ part reaches its
// overrides, and that part outlives its owner as nil (ADR-0056, Amendment 1 item 8).
OO_TEST(facadeContract)
{
	ClearStickDefaults();
	oo::Ref<cxx::OOJoystickManager> orphan;
	@autoreleasepool
	{
		OOJoystickManager *manager = NewManager();
		cxx::OOJoystickManager *cxxManager = oo::ToCxx(manager);
		OO_CHECK(cxxManager != nullptr);
		OO_CHECK(oo::ToObjC(cxxManager) == manager);
		OO_CHECK(cxxManager->joystickCount() == 0);
		OO_CHECK(cxxManager->axisFunctions() == [manager axisFunctions]);
		// The C++ SDL manager decodes into the state its facade answers from (upstream #742).
		DecodingStickManager *decoding = NewDecodingManager();
		SDL_JoyButtonEvent press = Button(0, 0, true);
		oo::ToCxx(decoding)->decodeButtonEvent(&press);
		OO_CHECK([decoding getButtonState:BUTTON_FIRE]);

		// Profiles cross with their own facades.
		OO_CHECK([manager getProfileForAxis:AXIS_ROLL] == oo::ToObjC(cxxManager->getProfileForAxis(AXIS_ROLL)));
		oo::Ref<cxx::OOJoystickAxisProfile> spline = oo::makeRef<cxx::OOJoystickSplineAxisProfile>();
		cxxManager->setProfile(spline.get(), AXIS_YAW);
		OO_CHECK([[manager getProfileForAxis:AXIS_YAW] isKindOfClass:[OOJoystickSplineAxisProfile class]]);
		OO_CHECK(oo::ToCxx([manager getProfileForAxis:AXIS_YAW]) == spline.get());

		// A C++ manager made by converted code gets one facade, which answers for it.
		oo::Ref<cxx::OOJoystickManager> bare = oo::makeRef<cxx::OOJoystickManager>();
		bare->init();
		OOJoystickManager *facade = oo::ToObjC(bare.get());
		OO_CHECK(facade != nil && oo::ToObjC(bare.get()) == facade);
		OO_CHECK(oo::ToCxx(facade) == bare.get());
		OO_CHECK([facade buttonFunctions] == bare->buttonFunctions());
		OO_CHECK([facade nameOfJoystick:0] == std::optional<std::string>("Dummy joystick"));

		// An Objective-C subclass: its C++ part is not itself, crosses back to it, and its virtual
		// members reach the subclass's overrides.
		TestStickManager *sub = [[TestStickManager alloc] init];
		cxx::OOJoystickManager *part = oo::ToCxx(static_cast<OOJoystickManager *>(sub));
		OO_CHECK(part != nullptr);
		OO_CHECK(oo::ToObjC(part) == sub);
		OO_CHECK(part->joystickCount() == 2);
		OO_CHECK(part->nameOfJoystick(0) == std::optional<std::string>("stick 0"));
		OO_CHECK(part->getAxisWithStick(0, 1) == 16384);
		OO_CHECK(part->listSticks() == std::vector<std::string>({ "stick 0", "" }));
		orphan = oo::Ref<cxx::OOJoystickManager>(part);
		[sub release];
	}
	// Its owner gone, the adapter answers as nil did, and crosses as nil.
	OO_CHECK(orphan->joystickCount() == 0);
	OO_CHECK(orphan->nameOfJoystick(0) == std::nullopt);
	OO_CHECK(orphan->getAxisWithStick(0, 1) == 0);
	@autoreleasepool
	{
		OO_CHECK(oo::ToObjC(orphan.get()) == nil);
	}

	OOJoystickManager *none = nil;
	OO_CHECK(oo::ToCxx(none) == nullptr);
	OO_CHECK(oo::ToObjC(static_cast<cxx::OOJoystickManager *>(nullptr)) == nil);
	OO_CHECK([none joystickCount] == 0);
}


OO_TEST(cleanUp)
{
	std::error_code ignored;
	stdfs::remove_all(sRoot, ignored);
}


OO_TEST_MAIN()
