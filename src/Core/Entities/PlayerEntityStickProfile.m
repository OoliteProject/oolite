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
#import "OOOpenGL.h"
#import "OOMacroOpenGL.h"

#define GUI_ROW_STICKPROFILE_BACK		18
#define GUI_ROW_STICKPROFILE_AXIS_LABEL		1
#define GUI_ROW_STICKPROFILE_ROLL_AXIS		2
#define GUI_ROW_STICKPROFILE_PITCH_AXIS		3
#define GUI_ROW_STICKPROFILE_YAW_AXIS		4

#define GUI_ROW_STICKPROFILE_DEADZONE	4
#define GUI_ROW_STICKPROFILE_POWER	5
#define GUI_ROW_STICKPROFILE_PARAM	6

#define STICKPROFILE_SCREEN_MAIN	1
#define STICKPROFILE_SCREEN_EDIT	2

static BOOL stickProfileArrow_pressed;
static BOOL stickProfileEnter_pressed;

@interface StickProfileScreen (StickProfileInternal)

- (void) showScreen;
- (void) showMainScreen;
- (void) showEditScreen;
- (void) setCurrentAxis: (int) axis;
- (void) nextProfileType;
- (void) previousProfileType;
- (void) increaseDeadzone;
- (void) decreaseDeadzone;
- (void) polyIncreasePower;
- (void) polyDecreasePower;
- (void) polyIncreaseParam;
- (void) polyDecreaseParam;
- (BOOL) currentProfileIsPolynomial;
- (BOOL) currentProfileIsSpline;
- (int) currentScreen;
- (void) saveSettings;
- (void) graphProfile: (GLfloat) alpha at: (Vector) at size: (NSSize) size;
- (void) startEdit;
- (void) endEdit;

@end

@implementation PlayerEntity (StickProfile)

- (void) setGuiToStickProfileScreen: (GuiDisplayGen *) gui
{
	gui_screen = GUI_SCREEN_STICKPROFILE;
	[stickProfileScreen startGui: gui];
	return;
}

- (void) stickProfileInputHandler: (GuiDisplayGen *) gui
	view: (MyOpenGLView *) gameView
{
	[self handleGUIUpDownArrowKeys];
	
	switch ([stickProfileScreen currentScreen])
	{
	case STICKPROFILE_SCREEN_MAIN:
		if ([gameView isDown:13] && [gui selectedRow] == GUI_ROW_STICKPROFILE_BACK)
		{
			[stickProfileScreen saveSettings];
			[self setGuiToStickMapperScreen: 0];
		}
		switch ([gui selectedRow])
		{
		case GUI_ROW_STICKPROFILE_ROLL_AXIS:
			[stickProfileScreen setCurrentAxis: AXIS_ROLL];
			break;
		
		case GUI_ROW_STICKPROFILE_PITCH_AXIS:
			[stickProfileScreen setCurrentAxis: AXIS_PITCH];
			break;
		
		case GUI_ROW_STICKPROFILE_YAW_AXIS:
			[stickProfileScreen setCurrentAxis: AXIS_YAW];
			break;
		}
		break;
	
	case STICKPROFILE_SCREEN_EDIT:
		if ([gameView isDown:13] && [gui selectedRow] == GUI_ROW_STICKPROFILE_BACK)
		{
			[stickProfileScreen endEdit];
		}
		switch ([gui selectedRow])
		{
		case GUI_ROW_STICKPROFILE_DEADZONE:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen decreaseDeadzone];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen increaseDeadzone];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
			break;
	
		}

		if ([stickProfileScreen currentProfileIsPolynomial])
		{
			if ([gui selectedRow] == GUI_ROW_STICKPROFILE_POWER)
			{
				if ([gameView isDown:key_gui_arrow_left])
				{
					if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
					{
						[stickProfileScreen polyDecreasePower];
						stickProfileArrow_pressed = YES;
					}
				}
				else if ([gameView isDown: key_gui_arrow_right])
				{
					if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
					{
						[stickProfileScreen polyIncreasePower];
						stickProfileArrow_pressed = YES;
					}
				}
				else
				{
					stickProfileArrow_pressed = NO;
				}
			}
			else if ([gui selectedRow] == GUI_ROW_STICKPROFILE_PARAM)
			{
				if ([gameView isDown:key_gui_arrow_left])
				{
					if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
					{
						[stickProfileScreen polyDecreaseParam];
						stickProfileArrow_pressed = YES;
					}
				}
				else if ([gameView isDown: key_gui_arrow_right])
				{
					if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
					{
						[stickProfileScreen polyIncreaseParam];
						stickProfileArrow_pressed = YES;
					}
				}
				else
				{
					stickProfileArrow_pressed = NO;
				}
			}
		}
	}
	return;
}

- (void) stickProfileGraphAxisProfile: (GLfloat) alpha screenAt: (Vector) screenAt screenSize: (NSSize) screenSize
{
	switch ([stickProfileScreen currentScreen])
	{
	case STICKPROFILE_SCREEN_MAIN:
		[stickProfileScreen graphProfile: alpha at: make_vector(screenAt.x + screenSize.width/2.0 - 150, screenAt.y + screenSize.height/2.0 - 190, screenAt.z) size: NSMakeSize(150,150)];
		break;
	case STICKPROFILE_SCREEN_EDIT:
		[stickProfileScreen graphProfile: alpha at: make_vector(screenAt.x + screenSize.width/2.0 - 150, screenAt.y + screenSize.height/2.0 - 190, screenAt.z) size: NSMakeSize(150,150)];
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
		current_axis = AXIS_ROLL;
	}
	return self;
}

- (void) startGui: (GuiDisplayGen *) gui_display_gen
{
	gui = gui_display_gen;
	current_screen = STICKPROFILE_SCREEN_MAIN;
	[gui clear];
	[gui setTitle: [NSString stringWithFormat: @"Joystick Profile"]];
	[self showScreen];
	[gui setSelectedRow: GUI_ROW_STICKPROFILE_BACK];
	return;
}

@end

@implementation StickProfileScreen (StickProfileInternal)

- (void) setCurrentAxis: (int) axis
{
	current_axis = axis;
	return;
}

- (void) nextProfileType
{
	switch (current_profile_type)
	{
	case JOYSTICK_PROFILE_TYPE_STANDARD:
		current_profile_type = JOYSTICK_PROFILE_TYPE_POLYNOMIAL;
		break;

	case JOYSTICK_PROFILE_TYPE_POLYNOMIAL:
		current_profile_type = JOYSTICK_PROFILE_TYPE_SPLINE;
		break;
	}
	return;
}

- (void) previousProfileType
{
	switch (current_profile_type)
	{
	case JOYSTICK_PROFILE_TYPE_SPLINE:
		current_profile_type = JOYSTICK_PROFILE_TYPE_POLYNOMIAL;
		break;
	
	case JOYSTICK_PROFILE_TYPE_POLYNOMIAL:
		current_profile_type = JOYSTICK_PROFILE_TYPE_STANDARD;
		break;
	}
	return;
}

- (void) increaseDeadzone
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	if (profile)
	{
		[profile setDeadzone: [profile deadzone] + STICKPROFILE_MAX_DEADZONE / 20];
	}
	[self showScreen];
	return;
}

- (void) decreaseDeadzone
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	if (profile)
	{
		[profile setDeadzone: [profile deadzone] - STICKPROFILE_MAX_DEADZONE / 20];
	}
	[self showScreen];
	return;
}

- (void) polyIncreasePower
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (profile && [profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *) profile;
		if ([poly_profile power] < 20)
			[poly_profile setPower: [poly_profile power] + 1];
	}
	[self showScreen];
	return;
}

- (void) polyDecreasePower
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (profile && [profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *) profile;
		if ([poly_profile power] > 0)
			[poly_profile setPower: [poly_profile power] - 1];
	}
	[self showScreen];
	return;
}

- (void) polyIncreaseParam
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (profile && [profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *) profile;
		[poly_profile setParameter: [poly_profile parameter] + 0.05];
	}
	[self showScreen];
	return;
}

- (void) polyDecreaseParam
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (profile && [profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *) profile;
		[poly_profile setParameter: [poly_profile parameter] - 0.05];
	}
	[self showScreen];
	return;
}

- (BOOL) currentProfileIsPolynomial
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	return (profile && [profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]]);
}


- (BOOL) currentProfileIsSpline
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	return (profile && [profile isKindOfClass: [OOJoystickSplineAxisProfile class]]);
}

- (int) currentScreen
{
	return current_screen;
}


- (void) graphProfile: (GLfloat) alpha at: (Vector) at size: (NSSize) size
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickSplineAxisProfile *spline_profile;
	int i;
	NSPoint point;
	NSArray *control_points;

	if (!profile) return;
	OO_ENTER_OPENGL();
	OOGL(glColor4f(0.2,0.2,0.5,alpha));
	OOGLBEGIN(GL_QUADS);
		glVertex3f(at.x,at.y,at.z);
		glVertex3f(at.x + size.width,at.y,at.z);
		glVertex3f(at.x + size.width,at.y + size.height,at.z);
		glVertex3f(at.x,at.y + size.height,at.z);
	OOGLEND();
	OOGL(glColor4f(0.9,0.9,0.9,alpha));
	OOGL(GLScaledLineWidth(2.0f));
	OOGLBEGIN(GL_LINE_STRIP);
		for (i = 0; i <= size.width - 20; i++)
		{
			glVertex3f(at.x+i+10,at.y+10+(size.height-20)*[profile valueNoDeadzone:((float)i)/(size.width-20)],at.z);
		}
	OOGLEND();
	OOGL(glColor4f(1.0,0.0,0.0,alpha));
	GLDrawFilledOval(at.x+10,at.y+10,at.z,NSMakeSize(4,4),20);
	GLDrawFilledOval(at.x+size.width-10,at.y+size.width-10,at.z,NSMakeSize(4,4),20);
	OOGL(glColor4f(0.0,1.0,0.0,alpha));
	if ([profile isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		spline_profile = (OOJoystickSplineAxisProfile *)profile;
		control_points = [spline_profile controlPoints];
		for (i = 0; i < [control_points count]; i++)
		{
			point = [[control_points objectAtIndex: i] pointValue];
			GLDrawFilledOval(at.x+10+point.x*(size.width - 20),at.y+10+point.y*(size.height-20),at.z,NSMakeSize(4,4),20);
		}
	}
	return;
}

- (void) startEdit
{
	return;
}

- (void) endEdit
{
	return;
}

- (void) saveSettings
{
	[stickHandler saveStickSettings];
	return;
}

- (void) showScreen
{
	[gui setText: @"Back" forRow: GUI_ROW_STICKPROFILE_BACK];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_BACK];
	switch (current_screen)
	{
	case STICKPROFILE_SCREEN_EDIT:
		[self showEditScreen];
		break;

	case STICKPROFILE_SCREEN_MAIN:
	default:
		[self showMainScreen];
		break;
	}
	[gui setSelectableRange: NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK)];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[PLAYER status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey: @"settings"];
	return;
}

- (void) showMainScreen
{
	current_screen = STICKPROFILE_SCREEN_MAIN;

	[gui setText: @"Axis Profiles" forRow: GUI_ROW_STICKPROFILE_AXIS_LABEL];
	[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_AXIS_LABEL];
	[gui setColor:[OOColor greenColor] forRow: GUI_ROW_STICKPROFILE_AXIS_LABEL];
	[gui setText: @"Back" forRow: GUI_ROW_STICKPROFILE_BACK];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_BACK];
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 50;
	tabStop[1] = 120;
	[gui setTabStops:tabStop];
	[gui setSelectableRange: NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK)];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[PLAYER status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey: @"settings"];
	return;
}

- (void) showEditScreen
{
	OOJoystickAxisProfile *profile;
	OOJoystickPolynomialAxisProfile *poly_profile;
	NSString *v1 = @"||||||||||||||||||||";
	NSString *v2 = @"....................";
	int bars;
	double value;
	int power;

	profile = [stickHandler getProfileForAxis: current_axis];
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 50;
	tabStop[1] = 120;
	[gui setTabStops:tabStop];
	value = [profile deadzone];
	bars = 20 * value / STICKPROFILE_MAX_DEADZONE;
	if (bars < 0) bars = 0;
	if (bars > 20) bars = 20;
	[gui setArray: [NSArray arrayWithObjects: @"Deadzone:",
		[NSString stringWithFormat: @"%@%@ (%.3f) ", [v1 substringToIndex:bars], [v2 substringToIndex: 20 - bars], value ],
		nil] forRow: GUI_ROW_STICKPROFILE_DEADZONE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_DEADZONE];
	if ([profile isKindOfClass:[OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile*) profile;
		power = [poly_profile power];
		bars = power;
		if (bars < 0) bars = 0;
		if (bars > 20) bars = 20;
		[gui setArray: [NSArray arrayWithObjects: @"Power:",
			[NSString stringWithFormat: @"%@%@ (%d) ", [v1 substringToIndex: bars], [v2 substringToIndex: 20 - bars], power],
			nil] forRow: GUI_ROW_STICKPROFILE_POWER];
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_POWER];
		value = [poly_profile parameter];
		bars = 20*value;
		if (bars < 0) bars = 0;
		if (bars > 20) bars = 20;
		[gui setArray: [NSArray arrayWithObjects: @"Parameter:",
			[NSString stringWithFormat: @"%@%@ (%0.2f) ", [v1 substringToIndex: bars], [v2 substringToIndex: 20 - bars], value],
			nil] forRow: GUI_ROW_STICKPROFILE_PARAM];
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_PARAM];
	}
	else
	{
		[gui setText: @"" forRow: GUI_ROW_STICKPROFILE_POWER];
		[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_POWER];
		[gui setText: @"" forRow: GUI_ROW_STICKPROFILE_PARAM];
		[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_PARAM];
	}
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

