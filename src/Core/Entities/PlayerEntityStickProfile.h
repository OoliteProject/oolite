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

#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "OOJoystickProfile.h"
#import "PlayerEntity.h"
#import "Universe.h"
#include "oofnd/Ref.hpp"

@interface PlayerEntity (StickProfile)

- (void)setGuiToStickProfileScreen:(GuiDisplayGen*)gui;
- (void)stickProfileInputHandler:(GuiDisplayGen*)gui view:(MyOpenGLView*)gameView;
- (void)stickProfileGraphAxisProfile:(GLfloat)alpha screenAt:(Vector)screenAt screenSize:(NSSize)screenSize;

@end

namespace cxx {
class OOJoystickManager;
}

/*	C++20 since bead oo-movn (proposed ADR-0056 amendment oo-zffj): the player is the screen's one
        caller (PlayerEntity.mm makes it, the category above drives it), so it has no facade; the
        player keeps it as an oo::Ref. The members after mouseUp() were the file's private
        StickProfileInternal category, which the player's category sent.
*/
class StickProfileScreen : public oo::RefCounted {
public:
    StickProfileScreen(); // -init
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
    cxx::OOJoystickManager* stickHandler = nullptr; // the shared handler, not retained, as before
    NSUInteger current_axis = 0;
    oo::Ref<OOJoystickAxisProfile> profiles[3][2] = { };
    GuiDisplayGen* gui = nil; // not retained, as before
    NSRect graphRect = { };
    NSInteger selected_control_point = 0;
    NSInteger dragged_control_point = 0;
    NSInteger double_click_control_point = 0;
};
