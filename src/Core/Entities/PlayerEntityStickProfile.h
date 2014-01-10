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

#import "PlayerEntity.h"
#import "GuiDisplayGen.h"
#import "MyOpenGLView.h"
#import "OOJoystickProfile.h"
#import "Universe.h"

#define GUI_ROW_STICKPROFILE_BACK	18
#define GUI_ROW_STICKPROFILE_AXIS	2
#define GUI_ROW_STICKPROFILE_PROFILE 	3

@interface PlayerEntity (StickProfile)

- (void) setGuiToStickProfileScreen: (GuiDisplayGen *) gui;
- (void) stickProfileInputHandler: (GuiDisplayGen *) gui view: (MyOpenGLView *) gameView;

@end

@interface StickProfileScreen: NSObject
{
@private
	OOJoystickManager *stickHandler;
	OOJoystickAxisProfileManager *profileManager;
	NSUInteger current_axis;
	BOOL axis_key_pressed;
}

- (id) init;
- (void) dealloc;
- (void) setGuiToScreen: (GuiDisplayGen *) gui;
- (void) nextAxis: (GuiDisplayGen *) gui;
- (void) previousAxis: (GuiDisplayGen *) gui;
- (void) nextProfile: (GuiDisplayGen *) gui;
- (void) previousProfile: (GuiDisplayGen *) gui;
- (void) saveSettings;

@end

