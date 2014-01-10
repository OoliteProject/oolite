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

#import "PlayerEntity.h"
#import "PlayerEntityStickProfile.h"
#import "PlayerEntityStickMapper.h"
#import "OOJoystickManager.h"
#import "OOJoystickProfile.h"
#import "PlayerEntityControls.h"
#import "PlayerEntitySound.h"

static BOOL stickProfileAxisKey_pressed;
static BOOL stickProfileProfileKey_pressed;

@interface StickProfileScreen (StickProfileInternal)

- (void) showAxis: (GuiDisplayGen *) gui;
- (NSString *) axisName: (int) axis;

@end

@implementation PlayerEntity (StickProfile)

- (void) setGuiToStickProfileScreen: (GuiDisplayGen *) gui
{
	[stickProfileScreen setGuiToScreen: gui];
	gui_screen = GUI_SCREEN_STICKPROFILE;
	return;
}

- (void) stickProfileInputHandler: (GuiDisplayGen *) gui
	view: (MyOpenGLView *) gameView
{
	[self handleGUIUpDownArrowKeys];
	
	if ([gameView isDown:13] && [gui selectedRow] == GUI_ROW_STICKPROFILE_BACK)
	{
		[stickProfileScreen saveSettings];
		[self setGuiToStickMapperScreen: 0];
	}
	switch ([gui selectedRow])
	{
	case GUI_ROW_STICKPROFILE_AXIS:
		if ([gameView isDown:key_gui_arrow_left])
		{
			if (!stickProfileAxisKey_pressed && ![gameView isDown: key_gui_arrow_right])
			{
				[stickProfileScreen previousAxis: gui];
				[self playChangedOption];
				stickProfileAxisKey_pressed = YES;
			}
		}
		else if ([gameView isDown: key_gui_arrow_right])
		{
			if (!stickProfileAxisKey_pressed && ![gameView isDown: key_gui_arrow_left])
			{
				[stickProfileScreen nextAxis: gui];
				[self playChangedOption];
				stickProfileAxisKey_pressed = YES;
			}
		}
		else
		{
			stickProfileAxisKey_pressed = NO;
		}
		break;
		
	case GUI_ROW_STICKPROFILE_PROFILE:
		if ([gameView isDown:key_gui_arrow_left])
		{
			if (!stickProfileProfileKey_pressed && ![gameView isDown: key_gui_arrow_right])
			{
				[stickProfileScreen previousProfile: gui];
				[self playChangedOption];
				stickProfileProfileKey_pressed = YES;
			}
		}
		else if ([gameView isDown: key_gui_arrow_right])
		{
			if (!stickProfileProfileKey_pressed && ![gameView isDown: key_gui_arrow_left])
			{
				[stickProfileScreen nextProfile: gui];
				[self playChangedOption];
				stickProfileProfileKey_pressed = YES;
			}
		}
		else
		{
			stickProfileProfileKey_pressed = NO;
		}
		break;
		
	}
	return;
}

@end

@implementation StickProfileScreen

- (id) init
{
	if ((self = [super init]))
	{
		stickHandler = [OOJoystickManager sharedStickHandler];
		profileManager = [stickHandler getProfileManager];
		current_axis = AXIS_ROLL;
		axis_key_pressed = NO;
	}
	return self;
}

- (void) dealloc
{
	[super dealloc];
	return;
}

- (void) setGuiToScreen: (GuiDisplayGen *) gui
{
	[gui clear];
	[gui setTitle: [NSString stringWithFormat: @"Joystick Profile"]];
	
	[gui setText: @"Back" forRow: GUI_ROW_STICKPROFILE_BACK];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_BACK];
	[self showAxis: gui];
	[gui setSelectableRange: NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK)];
	[gui setSelectedRow: GUI_ROW_STICKPROFILE_BACK];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[PLAYER status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey: @"settings"];
	return;
}


- (void) nextAxis: (GuiDisplayGen *) gui
{
	switch (current_axis)
	{
	case AXIS_ROLL:
		current_axis = AXIS_PITCH;
		break;
	case AXIS_PITCH:
		current_axis = AXIS_YAW;
		break;
	case AXIS_YAW:
	default:
		current_axis = AXIS_ROLL;
	}
	[self showAxis: gui];
	return;
}

- (void) previousAxis: (GuiDisplayGen *) gui
{
	switch (current_axis)
	{
	case AXIS_ROLL:
		current_axis = AXIS_YAW;
		break;
	case AXIS_YAW:
		current_axis = AXIS_PITCH;
		break;
	case AXIS_PITCH:
	default:
		current_axis = AXIS_ROLL;
	}
	[self showAxis: gui];
	return;
}

- (void) nextProfile: (GuiDisplayGen *) gui
{
	NSArray *profileList = [profileManager listProfiles];
	NSUInteger index = [profileList indexOfObject: [profileManager getProfileForAxis: current_axis]];
	if (index == NSNotFound)
	{
		index = 0;
	}
	else
	{
		index++;
		if (index >= [profileList count])
		{
			index = 0;
		}
	}
	[profileManager setProfile: [profileList objectAtIndex: index] forAxis: current_axis ];
	[self showAxis: gui];
	return;
}

- (void) previousProfile: (GuiDisplayGen *) gui
{
	NSArray *profileList = [profileManager listProfiles];
	NSUInteger index = [profileList indexOfObject: [profileManager getProfileForAxis: current_axis]];
	if (index == NSNotFound)
	{
		index = 0;
	}
	else
	{
		if (index == 0)
		{
			index = [profileList count] - 1;
		}
		else
		{
			index--;
		}
	}
	[profileManager setProfile: [profileList objectAtIndex: index] forAxis: current_axis];
	[self showAxis: gui];
	return;
}

- (void) saveSettings
{
	[stickHandler saveStickSettings];
	return;
}

@end

@implementation StickProfileScreen (StickProfileInternal)

- (void) showAxis: (GuiDisplayGen *) gui
{
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 50;
	tabStop[1] = 120;
	[gui setArray: [NSArray arrayWithObjects: @"Axis:", [self axisName: current_axis], nil] forRow: GUI_ROW_STICKPROFILE_AXIS];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_AXIS];
	[gui setArray: [NSArray arrayWithObjects: @"Profile:", [profileManager getProfileForAxis: current_axis], nil] forRow: GUI_ROW_STICKPROFILE_PROFILE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_PROFILE];
	return;
}

- (NSString *) axisName: (int) axis
{
	switch (axis)
	{
	case AXIS_ROLL:
		return @"Roll";
	
	case AXIS_PITCH:
		return @"Pitch";
		
	case AXIS_YAW:
		return @"Yaw";
	}
	return @"";
}

@end

