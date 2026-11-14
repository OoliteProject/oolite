/*

PlayerEntityStickProfile.h

GUI for managing joystick profile settings

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

#include "PlayerEntity.h"

/* The category PlayerEntity (StickProfile) is members of PlayerEntity,
 * declared in PlayerEntity.h. This header stays for the files that include it.
 */
#include "GuiDisplayGen.h"
#include "MyOpenGLView.h"
#include "OOJoystickProfile.h"
#include "Universe.h"
#include "oofnd/Ref.hpp"

class OOJoystickManager;  // OOJoystickManager.h

/* The player is the screen's one caller (the category above drives it); the
 * player keeps it as an oo::Ref.
 */
class StickProfileScreen : public oo::RefCounted {
 public:
  StickProfileScreen();  // -init
  void startGui(GuiDisplayGen* gui_display_gen);
  void mouseDown(NSPoint position);
  void mouseUp();
  void deleteSelected();

  void showScreen();
  void nextAxis();
  std::optional<std::string> currentAxis();
  void previousAxis();
  void increaseDeadzone();
  void decreaseDeadzone();
  void nextProfileType();
  void previousProfileType();
  void IncreasePower();
  bool currentProfileIsSpline();
  void DecreasePower();
  void IncreaseParam();
  void DecreaseParam();
  void saveSettings();
  void graphProfile(GLfloat alpha, Vector at, NSSize size);
  void startEdit();
  std::optional<std::string> profileType();

 private:
  OOJoystickManager* stickHandler =
      nullptr;  // the shared handler, not retained, as before
  NSUInteger current_axis = 0;
  oo::Ref<OOJoystickAxisProfile> profiles[3][2] = {};
  GuiDisplayGen* gui = nullptr;  // not retained, as before
  NSRect graphRect = {};
  NSInteger selected_control_point = 0;
  NSInteger dragged_control_point = 0;
  NSInteger double_click_control_point = 0;
};
