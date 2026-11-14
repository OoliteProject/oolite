/*

PlayerEntityStickProfile.m

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

#include "PlayerEntityStickProfile.h"
#include "HeadUpDisplay.h"
#include "OOJoystickManager.h"
#include "OOJoystickProfile.h"
#include "OOMacroOpenGL.h"
#include "OOOpenGL.h"
#include "PlayerEntity.h"
#include "PlayerEntityControls.h"
#include "PlayerEntitySound.h"
#include "PlayerEntityStickMapper.h"

#include "oofnd/String.hpp"

#define GUI_ROW_STICKPROFILE_BACK 20
#define GUI_ROW_STICKPROFILE_AXIS 1
#define GUI_ROW_STICKPROFILE_DEADZONE 2
#define GUI_ROW_STICKPROFILE_PROFILE_TYPE 3
#define GUI_ROW_STICKPROFILE_POWER 4
#define GUI_ROW_STICKPROFILE_PARAM 5

static BOOL stickProfileArrow_pressed;

namespace {

// The columns of a row as +arrayWithObjects: took them: up to the first nil.
std::vector<std::string> ColumnsUpToNil(std::initializer_list<std::optional<std::string>> columns)
{
    std::vector<std::string> result;
    for (const std::optional<std::string>& column : columns) {
        if (!column.has_value())
            break;
        result.push_back(*column);
    }
    return result;
}

// "|||..." / "..." bars: the first `count` characters of a 20-character run of `mark`.
std::string Bars(char mark, int count)
{
    return std::string(static_cast<std::size_t>(count), mark);
}

} // namespace

void PlayerEntity::setGuiToStickProfileScreen(::GuiDisplayGen* gui)
{
    gui_screen = GUI_SCREEN_STICKPROFILE;
    if (stickProfileScreen != nullptr)
        stickProfileScreen->startGui(gui); // a nil screen ignored the message
    return;
}

void PlayerEntity::stickProfileInputHandler(::GuiDisplayGen* gui, ::MyOpenGLView* gameView)
{
    if ((gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false)) {
        NSPoint mouse_position = NSMakePoint(
            (gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint { }).x * gui->size().width,
            (gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint { }).y * gui->size().height);
        if (stickProfileScreen != nullptr)
            stickProfileScreen->mouseDown(mouse_position);
    } else {
        if (stickProfileScreen != nullptr)
            stickProfileScreen->mouseUp();
    }
    if ((gameView != nullptr ? gameView->isDown(gvDeleteKey) : false)) {
        if (stickProfileScreen != nullptr)
            stickProfileScreen->deleteSelected();
    }
    handleGUIUpDownArrowKeys();

    if (checkKeyPress(n_key_gui_select) && gui->getSelectedRow() == GUI_ROW_STICKPROFILE_BACK) {
        if (stickProfileScreen != nullptr)
            stickProfileScreen->saveSettings();
        setGuiToStickMapperScreen(0, YES);
    }
    switch (gui->getSelectedRow()) {
    case GUI_ROW_STICKPROFILE_AXIS:
        if (checkKeyPress(n_key_gui_arrow_left)) {
            if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_right)) {
                if (stickProfileScreen != nullptr)
                    stickProfileScreen->previousAxis();
                stickProfileArrow_pressed = YES;
            }
        } else if (checkKeyPress(n_key_gui_arrow_right)) {
            if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_left)) {
                if (stickProfileScreen != nullptr)
                    stickProfileScreen->nextAxis();
                stickProfileArrow_pressed = YES;
            }
        } else {
            stickProfileArrow_pressed = NO;
        }
        break;

    case GUI_ROW_STICKPROFILE_DEADZONE:
        if (checkKeyPress(n_key_gui_arrow_left)) {
            if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_right)) {
                if (stickProfileScreen != nullptr)
                    stickProfileScreen->decreaseDeadzone();
                stickProfileArrow_pressed = YES;
            }
        } else if (checkKeyPress(n_key_gui_arrow_right)) {
            if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_left)) {
                if (stickProfileScreen != nullptr)
                    stickProfileScreen->increaseDeadzone();
                stickProfileArrow_pressed = YES;
            }
        } else {
            stickProfileArrow_pressed = NO;
        }
        break;

    case GUI_ROW_STICKPROFILE_PROFILE_TYPE:
        if (checkKeyPress(n_key_gui_arrow_left)) {
            if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_right)) {
                if (stickProfileScreen != nullptr)
                    stickProfileScreen->previousProfileType();
                stickProfileArrow_pressed = YES;
            }
        } else if (checkKeyPress(n_key_gui_arrow_right)) {
            if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_left)) {
                if (stickProfileScreen != nullptr)
                    stickProfileScreen->nextProfileType();
                stickProfileArrow_pressed = YES;
            }
        } else {
            stickProfileArrow_pressed = NO;
        }
        break;
    }

    if (!(stickProfileScreen != nullptr && stickProfileScreen->currentProfileIsSpline())) {
        if (gui->getSelectedRow() == GUI_ROW_STICKPROFILE_POWER) {
            if (checkKeyPress(n_key_gui_arrow_left)) {
                if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_right)) {
                    if (stickProfileScreen != nullptr)
                        stickProfileScreen->DecreasePower();
                    stickProfileArrow_pressed = YES;
                }
            } else if (checkKeyPress(n_key_gui_arrow_right)) {
                if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_left)) {
                    if (stickProfileScreen != nullptr)
                        stickProfileScreen->IncreasePower();
                    stickProfileArrow_pressed = YES;
                }
            } else {
                stickProfileArrow_pressed = NO;
            }
        } else if (gui->getSelectedRow() == GUI_ROW_STICKPROFILE_PARAM) {
            if (checkKeyPress(n_key_gui_arrow_left)) {
                if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_right)) {
                    if (stickProfileScreen != nullptr)
                        stickProfileScreen->DecreaseParam();
                    stickProfileArrow_pressed = YES;
                }
            } else if (checkKeyPress(n_key_gui_arrow_right)) {
                if (!stickProfileArrow_pressed && !checkKeyPress(n_key_gui_arrow_left)) {
                    if (stickProfileScreen != nullptr)
                        stickProfileScreen->IncreaseParam();
                    stickProfileArrow_pressed = YES;
                }
            } else {
                stickProfileArrow_pressed = NO;
            }
        }
    }
    return;
}

void PlayerEntity::stickProfileGraphAxisProfile(GLfloat alpha, Vector screenAt, NSSize /*screenSize*/)
{

    if (stickProfileScreen != nullptr)
        stickProfileScreen->graphProfile(alpha, make_vector(screenAt.x - 110.0, screenAt.y - 100, screenAt.z), NSMakeSize(220, 220));
    return;
}

/*	StickProfileScreen (bead oo-movn): the Objective-C class's methods as members, the message syntax
        converted. The stick handler and its profiles are C++ (oo-6bux, oo-fn2f); "is kind of" a
        profile class is a dynamic_cast. GuiDisplayGen, UNIVERSE and PLAYER are still Objective-C and are
        messaged as before.
*/
StickProfileScreen::StickProfileScreen()
{
    stickHandler = OOJoystickManager::sharedStickHandler();
    current_axis = AXIS_ROLL;
    // profiles[][] start null (they were set to nil here).
}

void StickProfileScreen::startGui(GuiDisplayGen* gui_display_gen)
{
    gui = gui_display_gen;
    startEdit();
    gui->clear();
    gui->setTitle(OO_DESC("oolite-stickprofile-title"));
    showScreen();
    gui->setSelectedRow(GUI_ROW_STICKPROFILE_AXIS);
    return;
}

void StickProfileScreen::mouseDown(NSPoint position)
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickSplineAxisProfile* spline_profile;
    NSPoint spline_position;

    spline_profile = dynamic_cast<OOJoystickSplineAxisProfile*>(profile);
    if (spline_profile == nullptr) {
        return;
    }
    spline_position.x = (position.x - graphRect.origin.x - 10) / (graphRect.size.width - 20);
    spline_position.y = (-position.y - graphRect.origin.y - 10) / (graphRect.size.height - 20);
    if (spline_position.x >= 0.0 && spline_position.x <= 1.0 && spline_position.y >= 0.0 && spline_position.y <= 1.0) {
        if (dragged_control_point < 0) {
            selected_control_point = spline_profile->addControl(spline_position);
            dragged_control_point = selected_control_point;
            double_click_control_point = -1;
        } else {
            spline_profile->moveControl(dragged_control_point, spline_position);
        }
        stickHandler->saveStickSettings();
    }
    return;
}

void StickProfileScreen::mouseUp()
{
    if (selected_control_point >= 0) {
        double_click_control_point = selected_control_point;
    }
    dragged_control_point = -1;
    return;
}

void StickProfileScreen::deleteSelected()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickSplineAxisProfile* spline_profile = dynamic_cast<OOJoystickSplineAxisProfile*>(profile);
    if (spline_profile != nullptr && selected_control_point >= 0) {
        spline_profile->removeControl(selected_control_point);
        selected_control_point = -1;
        dragged_control_point = -1;
        stickHandler->saveStickSettings();
    }
    return;
}

void StickProfileScreen::nextAxis()
{
    if (current_axis == AXIS_ROLL)
        current_axis = AXIS_PITCH;
    else if (current_axis == AXIS_PITCH)
        current_axis = AXIS_YAW;
    showScreen();
    return;
}

void StickProfileScreen::previousAxis()
{
    if (current_axis == AXIS_PITCH)
        current_axis = AXIS_ROLL;
    else if (current_axis == AXIS_YAW)
        current_axis = AXIS_PITCH;
    showScreen();
    return;
}

std::optional<std::string> StickProfileScreen::currentAxis()
{
    switch (current_axis) {
    case AXIS_ROLL:
        return OO_DESC("stickmapper-roll");

    case AXIS_PITCH:
        return OO_DESC("stickmapper-pitch");

    case AXIS_YAW:
        return OO_DESC("stickmapper-yaw");
    }
    return std::string();
}

void StickProfileScreen::increaseDeadzone()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    if (profile) {
        profile->setDeadzone(profile->deadzone() + STICK_MAX_DEADZONE / 20);
    }
    showScreen();
    return;
}

void StickProfileScreen::decreaseDeadzone()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    if (profile) {
        profile->setDeadzone(profile->deadzone() - STICK_MAX_DEADZONE / 20);
    }
    showScreen();
    return;
}

void StickProfileScreen::nextProfileType()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    double deadzone;

    if (dynamic_cast<OOJoystickStandardAxisProfile*>(profile) != nullptr) {
        deadzone = profile->deadzone();
        profiles[current_axis][0] = oo::Ref<OOJoystickAxisProfile>(profile);
        if (!profiles[current_axis][1]) {
            profiles[current_axis][1] = oo::makeRef<OOJoystickSplineAxisProfile>();
        }
        profiles[current_axis][1]->setDeadzone(deadzone);
        stickHandler->setProfile(profiles[current_axis][1].get(), current_axis);
        stickHandler->saveStickSettings();
    }
    showScreen();
    return;
}

void StickProfileScreen::previousProfileType()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    double deadzone;

    if (dynamic_cast<OOJoystickSplineAxisProfile*>(profile) != nullptr) {
        deadzone = profile->deadzone();
        profiles[current_axis][1] = oo::Ref<OOJoystickAxisProfile>(profile);
        if (!profiles[current_axis][0]) {
            profiles[current_axis][0] = oo::makeRef<OOJoystickStandardAxisProfile>();
        }
        profiles[current_axis][0]->setDeadzone(deadzone);
        stickHandler->setProfile(profiles[current_axis][0].get(), current_axis);
        stickHandler->saveStickSettings();
    }
    showScreen();
    return;
}

bool StickProfileScreen::currentProfileIsSpline()
{
    if (dynamic_cast<OOJoystickSplineAxisProfile*>(stickHandler->getProfileForAxis(current_axis)) != nullptr) {
        return true;
    }
    return false;
}

void StickProfileScreen::IncreasePower()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickStandardAxisProfile* standard_profile = dynamic_cast<OOJoystickStandardAxisProfile*>(profile);

    if (standard_profile != nullptr) {
        standard_profile->setPower(standard_profile->power() + STICKPROFILE_MAX_POWER / 20);
        stickHandler->saveStickSettings();
    }
    showScreen();
    return;
}

void StickProfileScreen::DecreasePower()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickStandardAxisProfile* standard_profile = dynamic_cast<OOJoystickStandardAxisProfile*>(profile);

    if (standard_profile != nullptr) {
        standard_profile->setPower(standard_profile->power() - STICKPROFILE_MAX_POWER / 20);
        stickHandler->saveStickSettings();
    }
    showScreen();
    return;
}

void StickProfileScreen::IncreaseParam()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickStandardAxisProfile* standard_profile = dynamic_cast<OOJoystickStandardAxisProfile*>(profile);

    if (standard_profile != nullptr) {
        standard_profile->setParameter(standard_profile->parameter() + 0.05);
        stickHandler->saveStickSettings();
    }
    showScreen();
    return;
}

void StickProfileScreen::DecreaseParam()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickStandardAxisProfile* standard_profile = dynamic_cast<OOJoystickStandardAxisProfile*>(profile);

    if (standard_profile != nullptr) {
        standard_profile->setParameter(standard_profile->parameter() - 0.05);
        stickHandler->saveStickSettings();
    }
    showScreen();
    return;
}

void StickProfileScreen::graphProfile(GLfloat alpha, Vector at, NSSize size)
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickSplineAxisProfile* spline_profile;
    NSInteger i;
    NSPoint point;
    std::vector<NSPoint> control_points;

    if (!profile)
        return;
    graphRect = NSMakeRect(at.x, at.y, size.width, size.height);
    OO_ENTER_OPENGL();
    OOGL(glColor4f(0.2, 0.2, 0.5, alpha));
    OOGLBEGIN(GL_QUADS);
    glVertex3f(at.x, at.y, at.z);
    glVertex3f(at.x + size.width, at.y, at.z);
    glVertex3f(at.x + size.width, at.y + size.height, at.z);
    glVertex3f(at.x, at.y + size.height, at.z);
    OOGLEND();
    OOGL(glColor4f(0.9, 0.9, 0.9, alpha));
    OOGL(GLScaledLineWidth(2.0f));
    OOGLBEGIN(GL_LINE_STRIP);
    for (i = 0; i <= size.width - 20; i++) {
        glVertex3f(at.x + i + 10, at.y + 10 + (size.height - 20) * profile->rawValue(((float)i) / (size.width - 20)), at.z);
    }
    OOGLEND();
    OOGL(glColor4f(0.5, 0.0, 0.5, alpha));
    GLDrawFilledOval(at.x + 10, at.y + 10, at.z, NSMakeSize(4, 4), 20);
    GLDrawFilledOval(at.x + size.width - 10, at.y + size.height - 10, at.z, NSMakeSize(4, 4), 20);
    spline_profile = dynamic_cast<OOJoystickSplineAxisProfile*>(profile);
    if (spline_profile != nullptr) {
        control_points = spline_profile->controlPoints();
        for (i = 0; i < (NSInteger)control_points.size(); i++) {
            if (i == selected_control_point) {
                OOGL(glColor4f(1.0, 0.0, 0.0, alpha));
            } else {
                OOGL(glColor4f(0.0, 1.0, 0.0, alpha));
            }
            point = control_points[i];
            GLDrawFilledOval(at.x + 10 + point.x * (size.width - 20), at.y + 10 + point.y * (size.height - 20), at.z, NSMakeSize(4, 4), 20);
        }
    }
    OOGL(glColor4f(0.9, 0.9, 0.0, alpha));
    cxx_OODrawStringAligned(OO_DESC("oolite-stickprofile-movement"), at.x + size.width - 5, at.y, at.z, NSMakeSize(8, 10), YES);
    cxx_OODrawString(OO_DESC("oolite-stickprofile-response"), at.x, at.y + size.height - 10, at.z, NSMakeSize(8, 10));
    return;
}

void StickProfileScreen::startEdit()
{
    int i, j;

    for (i = 0; i < 3; i++) {
        for (j = 0; j < 2; j++) {
            profiles[i][j] = nullptr;
        }
    }
    current_axis = AXIS_ROLL;
    selected_control_point = -1;
    dragged_control_point = -1;
    double_click_control_point = -1;
    return;
}

void StickProfileScreen::saveSettings()
{
    stickHandler->saveStickSettings();
    return;
}

void StickProfileScreen::showScreen()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);
    OOJoystickStandardAxisProfile* standard_profile;
    int bars;
    double value;
    double power;

    OOGUITabStop tabStop[GUI_MAX_COLUMNS];
    tabStop[0] = 50;
    tabStop[1] = 140;
    gui->setTabStops(tabStop);
    gui->setArray(ColumnsUpToNil({ OO_DESC("oolite-stickprofile-axis"), currentAxis() }), GUI_ROW_STICKPROFILE_AXIS);
    gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE_AXIS);
    value = profile != nullptr ? profile->deadzone() : 0.0; // -deadzone sent to nil answered 0
    bars = (int)(20 * value / STICK_MAX_DEADZONE + 0.5);
    if (bars < 0)
        bars = 0;
    if (bars > 20)
        bars = 20;
    gui->setArray(ColumnsUpToNil({ OO_DESC("oolite-stickprofile-deadzone"), oo::str::format("%s%s (%0.4f)", Bars('|', bars).c_str(), Bars('.', 20 - bars).c_str(), value) }), GUI_ROW_STICKPROFILE_DEADZONE);
    gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE_DEADZONE);
    gui->setArray(ColumnsUpToNil({ OO_DESC("oolite-stickprofile-profile-type"), profileType() }), GUI_ROW_STICKPROFILE_PROFILE_TYPE);
    gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE_PROFILE_TYPE);
    standard_profile = dynamic_cast<OOJoystickStandardAxisProfile*>(profile);
    if (standard_profile != nullptr) {
        power = standard_profile->power();
        bars = (int)(20 * power / STICKPROFILE_MAX_POWER + 0.5);
        if (bars < 0)
            bars = 0;
        if (bars > 20)
            bars = 20;
        gui->setArray(ColumnsUpToNil({ OO_DESC("oolite-stickprofile-range"), oo::str::format("%s%s (%.1f) ", Bars('|', bars).c_str(), Bars('.', 20 - bars).c_str(), power) }), GUI_ROW_STICKPROFILE_POWER);
        gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE_POWER);
        value = standard_profile->parameter();
        bars = 20 * value;
        if (bars < 0)
            bars = 0;
        if (bars > 20)
            bars = 20;
        gui->setArray(ColumnsUpToNil({ OO_DESC("oolite-stickprofile-sensitivity"), oo::str::format("%s%s (%0.2f) ", Bars('|', bars).c_str(), Bars('.', 20 - bars).c_str(), value) }), GUI_ROW_STICKPROFILE_PARAM);
        gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE_PARAM);
        gui->setColor(OOColor::yellowColor().get(), GUI_ROW_STICKPROFILE_PARAM);
    } else {
        gui->setText(std::string(), GUI_ROW_STICKPROFILE_POWER);
        gui->setKey(std::string(GUI_KEY_SKIP), GUI_ROW_STICKPROFILE_POWER);
        gui->setText(OO_DESC("oolite-stickprofile-spline-instructions"), GUI_ROW_STICKPROFILE_PARAM);
        gui->setKey(std::string(GUI_KEY_SKIP), GUI_ROW_STICKPROFILE_PARAM);
        gui->setColor(OOColor::magentaColor().get(), GUI_ROW_STICKPROFILE_PARAM);
    }
    gui->setText(OO_DESC("gui-back"), GUI_ROW_STICKPROFILE_BACK);
    gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE_BACK);
    gui->setSelectableRange(NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK));
    if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)
        UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
    gui->setForegroundTextureKey(std::string((PLAYER != nullptr ? PLAYER->status() : OOEntityStatus { }) == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
    gui->setBackgroundTextureKey(std::string("settings"));
    return;
}

std::optional<std::string> StickProfileScreen::profileType()
{
    OOJoystickAxisProfile* profile = stickHandler->getProfileForAxis(current_axis);

    if (dynamic_cast<OOJoystickStandardAxisProfile*>(profile) != nullptr) {
        return OO_DESC("oolite-stickprofile-type-standard");
    }
    if (dynamic_cast<OOJoystickSplineAxisProfile*>(profile) != nullptr) {
        return OO_DESC("oolite-stickprofile-type-spline");
    }
    return OO_DESC("oolite-stickprofile-type-standard");
}
