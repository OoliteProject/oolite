/*	test_PlayerEntityStickProfile.mm
	Unit tests for StickProfileScreen (src/Core/Entities/PlayerEntityStickProfile.h): bead oo-movn,
	a Phase 3 conversion in the house style of the OOColor exemplar (proposed ADR-0056), as a class
	with one caller and no facade (amendment oo-zffj): the player keeps it and its stick-profile
	category drives it.

	The screen edits the shared stick handler's roll, pitch and yaw profiles on a GUI: it fills the
	GUI's rows, steps the axis, the dead zone, the profile type (standard or spline, keeping the
	other one for a switch back), the standard profile's power and parameter, and adds, moves and
	deletes a spline's control points under the mouse, saving the handler's settings after each
	change. It does not draw here (-graphProfile:at:size: is OpenGL), so the graph's rectangle is
	the zero one, which places a click at (0, 0) at the spline point (0.5, 0.5).

	The GUI object references Universe and the player, so the test links the whole game but main
	(tests/unit/core/meson.build entry ['*'], amendment oo-44gg) and defines gDebugFlags. UNIVERSE is
	nil: a description lookup answers its key, so the rows show the keys. PLAYER is a stand-in that
	answers -status and takes the GUI's row-changed script event (amendment oo-vt0o item 4); the GUI
	names that event by its JS id, so the test makes the engine's main-thread JS context. The defaults' home (HOMEPATH) is a scratch
	folder, set before they are first read, as in test_OOJoystickManager.
	The expectations were written against the Objective-C class and run on it first; they now
	call the C++ members, which are the same methods.
	Run: bash tools/check-core-tests.sh test_PlayerEntityStickProfile
*/

#include "PlayerEntityStickProfile.h"
#include "PlayerEntity.h"	// PLAYER is C++ (bead oo-9ht.177)
#include "OOJoystickManager.h"
#include "GuiDisplayGen.h"

#include "oofnd/Defaults.hpp"
#include "oofnd/String.hpp"
#include "ooscript/JSEngine.hpp"
#include "oo_test.hpp"

#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <process.h>
#include <string>
#include <vector>


// main.mm defines the debug flags, and the test has its own main.
#ifndef NDEBUG
uint32_t gDebugFlags = 0;
#endif


extern PlayerEntity *gOOPlayer;	// PlayerEntity.mm's, what PLAYER answers
extern ooscript::Context gOOJSMainThreadContext;	// the engine's; OOJSID needs it


// PLAYER: the screen asks it for its status (docked: the root's member, which is not virtual, so the
// player is made docked); the GUI sends it a script event when a row is selected.
class StickProfileTestPlayer : public PlayerEntity	// C++ since bead oo-9ht.177 deleted the Objective-C player
{
public:
	using PlayerEntity::doScriptEvent;
	void doScriptEvent(ooscript::PropertyId /*message*/, const std::vector<oo::PList> & /*arguments*/) override	{  }
};

// [[TestPlayer alloc] init] (bead oo-9ht.177): a C++ player under the ship's facade, as
// PlayerEntity::sharedPlayer() makes the game's, retained (+1) as +alloc's object was.
template <class T>
T *NewTestPlayer()
{
	oo::Ref<T> player = oo::makeRef<T>();
	{
		oo::RetainEntity(oo::MadeEntity(player));
	}
	return player.get();
}




namespace {

namespace stdfs = std::filesystem;

stdfs::path sRoot;


// The scratch home and the stand-in player, set once, before the defaults are first read.
void SetUp()
{
	if (!sRoot.empty())  return;
	sRoot = stdfs::temp_directory_path() / ("oo-test-stickprofile-" + std::to_string(static_cast<unsigned long>(::_getpid())));
	stdfs::remove_all(sRoot);
	stdfs::create_directories(sRoot);
	OO_CHECK(::_putenv_s("HOMEPATH", sRoot.string().c_str()) == 0);
	(void)oo::Defaults::standard();

	gOOPlayer = NewTestPlayer<StickProfileTestPlayer>();
	gOOPlayer->Entity::setStatus(STATUS_DOCKED);	// the root's: what the Objective-C stand-in's -status answered
	gOOJSMainThreadContext = ooscript::newContext(ooscript::newRuntime(8u * 1024u * 1024u), 8192);
}


OOJoystickManager *Handler()
{
	return OOJoystickManager::sharedStickHandler();
}


// A fresh standard profile on each axis, as a first run has.
void ResetProfiles()
{
	for (int axis : { AXIS_ROLL, AXIS_PITCH, AXIS_YAW })
	{
		Handler()->setProfile(oo::makeRef<OOJoystickStandardAxisProfile>().get(), axis);
	}
}


oo::PList Row(std::initializer_list<std::string> columns)
{
	oo::PList::Array result;
	for (const std::string &column : columns)  result.push_back(oo::PList(column));
	return oo::PList(std::move(result));
}


std::string Bars(int count)
{
	return std::string(static_cast<size_t>(count), '|') + std::string(static_cast<size_t>(20 - count), '.');
}


bool Near(double a, double b)
{
	return std::fabs(a - b) < 1e-9;
}


// A screen started on a new GUI, as -setGuiToStickProfileScreen: starts it.
struct Started
{
	oo::Ref<GuiDisplayGen>	gui;
	oo::Ref<StickProfileScreen>	screen;
};


Started Start()
{
	SetUp();
	ResetProfiles();
	Started started;
	started.gui = oo::makeRef<GuiDisplayGen>();
	started.screen = oo::makeRef<StickProfileScreen>();
	started.screen->startGui(started.gui.get());
	return started;
}

}	// namespace


OO_TEST(startShowsTheRollAxisStandardProfile)
{
	{
		Started s = Start();
		oo::Ref<GuiDisplayGen>	gui = s.gui;

		OO_CHECK(gui->getTitle() == std::optional<std::string>("oolite-stickprofile-title"));
		OO_CHECK_EQ(gui->getSelectedRow(), 1);
		OO_CHECK(gui->getSelectableRange().location == 1 && gui->getSelectableRange().length == 20);

		OO_CHECK(gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-roll" }));
		// A new standard profile: dead zone STICK_DEADZONE (half the maximum), power 1, parameter 1.
		OO_CHECK(gui->objectForRow(2) == Row({ "oolite-stickprofile-deadzone", Bars(10) + " (" + oo::str::format("%0.4f", STICK_DEADZONE) + ")" }));
		OO_CHECK(gui->objectForRow(3) == Row({ "oolite-stickprofile-profile-type", "oolite-stickprofile-type-standard" }));
		OO_CHECK(gui->objectForRow(4) == Row({ "oolite-stickprofile-range", Bars(2) + " (1.0) " }));
		OO_CHECK(gui->objectForRow(5) == Row({ "oolite-stickprofile-sensitivity", Bars(20) + " (1.00) " }));
		OO_CHECK(gui->objectForRow(20) == oo::PList(std::string("gui-back")));
		for (int row : { 1, 2, 3, 4, 5, 20 })
		{
			OO_CHECK(gui->keyForRow(row) == std::optional<std::string>(std::string(GUI_KEY_OK)));
		}
	}
}


OO_TEST(theAxisStepsBetweenRollPitchAndYaw)
{
	{
		Started s = Start();

		s.screen->previousAxis();	// roll is the first
		OO_CHECK(s.gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-roll" }));
		s.screen->nextAxis();
		OO_CHECK(s.gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-pitch" }));
		s.screen->nextAxis();
		OO_CHECK(s.gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-yaw" }));
		s.screen->nextAxis();	// yaw is the last
		OO_CHECK(s.gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-yaw" }));
		s.screen->previousAxis();
		OO_CHECK(s.gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-pitch" }));

		// Starting again goes back to roll.
		s.screen->startGui(s.gui.get());
		OO_CHECK(s.gui->objectForRow(1) == Row({ "oolite-stickprofile-axis", "stickmapper-roll" }));
	}
}


OO_TEST(theDeadZoneStepsByATwentiethOfItsMaximumOnTheCurrentAxis)
{
	{
		Started s = Start();
		oo::Ref<OOJoystickAxisProfile> roll(Handler()->getProfileForAxis(AXIS_ROLL));
		oo::Ref<OOJoystickAxisProfile> pitch(Handler()->getProfileForAxis(AXIS_PITCH));

		s.screen->increaseDeadzone();
		OO_CHECK(Near(roll->deadzone(), STICK_DEADZONE + STICK_MAX_DEADZONE / 20));
		OO_CHECK(Near(pitch->deadzone(), STICK_DEADZONE));
		OO_CHECK(s.gui->objectForRow(2) == Row({ "oolite-stickprofile-deadzone", Bars(11) + " (" + oo::str::format("%0.4f", roll->deadzone()) + ")" }));

		s.screen->nextAxis();
		s.screen->decreaseDeadzone();
		s.screen->decreaseDeadzone();
		OO_CHECK(Near(pitch->deadzone(), STICK_DEADZONE - 2 * STICK_MAX_DEADZONE / 20));
		OO_CHECK(Near(roll->deadzone(), STICK_DEADZONE + STICK_MAX_DEADZONE / 20));

		// The profile clamps it at zero.
		for (int i = 0; i < 20; i++)  s.screen->decreaseDeadzone();
		OO_CHECK(pitch->deadzone() == 0.0);
		OO_CHECK(s.gui->objectForRow(2) == Row({ "oolite-stickprofile-deadzone", Bars(0) + " (0.0000)" }));
	}
}


OO_TEST(powerAndParameterStepTheStandardProfile)
{
	{
		Started s = Start();
		oo::Ref<OOJoystickStandardAxisProfile> roll(static_cast<OOJoystickStandardAxisProfile *>(Handler()->getProfileForAxis(AXIS_ROLL)));

		s.screen->IncreasePower();
		s.screen->IncreasePower();
		OO_CHECK(Near(roll->power(), 1.0 + 2 * STICKPROFILE_MAX_POWER / 20));
		OO_CHECK(s.gui->objectForRow(4) == Row({ "oolite-stickprofile-range", Bars(4) + " (2.0) " }));
		s.screen->DecreasePower();
		OO_CHECK(Near(roll->power(), 1.0 + STICKPROFILE_MAX_POWER / 20));

		s.screen->DecreaseParam();
		s.screen->DecreaseParam();
		OO_CHECK(Near(roll->parameter(), 0.9));
		// The bar count is 20 x the parameter truncated, as the screen computes it (17 for 1 - 0.05 - 0.05).
		OO_CHECK(s.gui->objectForRow(5) == Row({ "oolite-stickprofile-sensitivity", Bars(static_cast<int>(20 * roll->parameter())) + " (0.90) " }));
		s.screen->IncreaseParam();
		OO_CHECK(Near(roll->parameter(), 0.95));
	}
}


OO_TEST(theProfileTypeSwitchesAndKeepsTheOtherForTheSwitchBack)
{
	{
		Started s = Start();
		oo::Ref<OOJoystickAxisProfile> standard(Handler()->getProfileForAxis(AXIS_ROLL));
		s.screen->increaseDeadzone();
		const double deadzone = standard->deadzone();

		OO_CHECK(!s.screen->currentProfileIsSpline());
		s.screen->previousProfileType();	// standard is the first
		OO_CHECK(Handler()->getProfileForAxis(AXIS_ROLL) == standard);

		s.screen->nextProfileType();
		oo::Ref<OOJoystickAxisProfile> spline(Handler()->getProfileForAxis(AXIS_ROLL));
		OO_CHECK(dynamic_cast<OOJoystickSplineAxisProfile *>(spline.get()) != nullptr);
		OO_CHECK(s.screen->currentProfileIsSpline());
		OO_CHECK(Near(spline->deadzone(), deadzone));	// the dead zone carries over
		OO_CHECK(s.gui->objectForRow(3) == Row({ "oolite-stickprofile-profile-type", "oolite-stickprofile-type-spline" }));
		OO_CHECK(s.gui->objectForRow(4) == oo::PList(std::string()));
		OO_CHECK(s.gui->keyForRow(4) == std::optional<std::string>(std::string(GUI_KEY_SKIP)));
		OO_CHECK(s.gui->objectForRow(5) == oo::PList(std::string("oolite-stickprofile-spline-instructions")));
		OO_CHECK(s.gui->keyForRow(5) == std::optional<std::string>(std::string(GUI_KEY_SKIP)));

		// Power and parameter do nothing to a spline.
		s.screen->IncreasePower();
		s.screen->DecreaseParam();
		OO_CHECK(Handler()->getProfileForAxis(AXIS_ROLL) == spline);

		s.screen->nextProfileType();	// spline is the last
		OO_CHECK(Handler()->getProfileForAxis(AXIS_ROLL) == spline);

		// Back to the very standard profile it had, and forward to the very spline.
		spline->setDeadzone(0.0);
		s.screen->previousProfileType();
		OO_CHECK(Handler()->getProfileForAxis(AXIS_ROLL) == standard);
		OO_CHECK(standard->deadzone() == 0.0);
		s.screen->nextProfileType();
		OO_CHECK(Handler()->getProfileForAxis(AXIS_ROLL) == spline);

		// Starting again forgets the kept profiles: the next switch makes a new one.
		s.screen->startGui(s.gui.get());
		s.screen->previousProfileType();
		OO_CHECK(Handler()->getProfileForAxis(AXIS_ROLL) != standard);
		OO_CHECK(dynamic_cast<OOJoystickStandardAxisProfile *>(Handler()->getProfileForAxis(AXIS_ROLL)) != nullptr);
	}
}


OO_TEST(theMouseAddsMovesAndDeletesSplinePoints)
{
	{
		Started s = Start();

		// Not a spline: nothing happens.
		s.screen->mouseDown(NSMakePoint(0, 0));
		s.screen->mouseUp();
		s.screen->deleteSelected();
		OO_CHECK(!s.screen->currentProfileIsSpline());

		s.screen->nextProfileType();
		oo::Ref<OOJoystickSplineAxisProfile> spline(static_cast<OOJoystickSplineAxisProfile *>(Handler()->getProfileForAxis(AXIS_ROLL)));
		const int points = spline->countPoints();

		// With the zero graph rectangle, (0, 0) is the spline point (0.5, 0.5).
		s.screen->mouseDown(NSMakePoint(0, 0));
		OO_CHECK_EQ(spline->countPoints(), points + 1);
		const std::vector<NSPoint> added = spline->controlPoints();
		bool found = false;
		for (const NSPoint &point : added)  found = found || (point.x == 0.5 && point.y == 0.5);
		OO_CHECK(found);

		// Dragging moves the same point: (-2, 0) is (0.6, 0.5).
		s.screen->mouseDown(NSMakePoint(-2, 0));
		OO_CHECK_EQ(spline->countPoints(), points + 1);
		found = false;
		for (const NSPoint &point : spline->controlPoints())  found = found || (Near(point.x, 0.6) && point.y == 0.5);
		OO_CHECK(found);

		// A click outside the unit square does nothing: (12, 0) is (-0.1, 0.5).
		s.screen->mouseUp();
		s.screen->mouseDown(NSMakePoint(12, 0));
		OO_CHECK_EQ(spline->countPoints(), points + 1);
		s.screen->mouseUp();

		// The selected point goes; a second delete has nothing selected.
		s.screen->deleteSelected();
		OO_CHECK_EQ(spline->countPoints(), points);
		s.screen->deleteSelected();
		OO_CHECK_EQ(spline->countPoints(), points);
	}
}


OO_TEST(changesAreSavedToTheDefaults)
{
	{
		Started s = Start();
		oo::Defaults::standard().removeObject(std::string(STICK_ROLL_AXIS_PROFILE_SETTING));

		s.screen->nextProfileType();
		OO_CHECK(!oo::Defaults::standard().object(std::string(STICK_ROLL_AXIS_PROFILE_SETTING)).isNull());

		oo::Defaults::standard().removeObject(std::string(STICK_ROLL_AXIS_PROFILE_SETTING));
		s.screen->saveSettings();
		OO_CHECK(!oo::Defaults::standard().object(std::string(STICK_ROLL_AXIS_PROFILE_SETTING)).isNull());
	}
}


OO_TEST_MAIN()
