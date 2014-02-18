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
#import "HeadUpDisplay.h"

#define GUI_ROW_STICKPROFILE_BACK		20
#define GUI_ROW_STICKPROFILE_AXIS		1
#define GUI_ROW_STICKPROFILE_DEADZONE		2
#define GUI_ROW_STICKPROFILE_PROFILE_TYPE	3
#define GUI_ROW_STICKPROFILE_POWER	4
#define GUI_ROW_STICKPROFILE_PARAM	5

static BOOL stickProfileArrow_pressed;

@interface StickProfileScreen (StickProfileInternal)

- (void) showScreen;
- (void) nextAxis;
- (NSString *) currentAxis;
- (void) previousAxis;
- (void) increaseDeadzone;
- (void) decreaseDeadzone;
- (void) nextProfileType;
- (void) previousProfileType;
- (void) IncreasePower;
- (BOOL) currentProfileIsSpline;
- (void) DecreasePower;
- (void) IncreaseParam;
- (void) DecreaseParam;
- (void) saveSettings;
- (void) graphProfile: (GLfloat) alpha at: (Vector) at size: (NSSize) size;
- (void) startEdit;
- (NSString *) profileType;

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
	if ([gameView isDown: gvMouseLeftButton])
	{
		NSPoint mouse_position = NSMakePoint(
			[gameView virtualJoystickPosition].x * [gui size].width,
			[gameView virtualJoystickPosition].y * [gui size].height );
		[stickProfileScreen mouseDown: mouse_position];
	}
	else
	{
		[stickProfileScreen mouseUp];
	}
	if ([gameView isDown: gvDeleteKey])
	{
		[stickProfileScreen deleteSelected];
	}
	[self handleGUIUpDownArrowKeys];
	
	if ([gameView isDown:13] && [gui selectedRow] == GUI_ROW_STICKPROFILE_BACK)
	{
		[stickProfileScreen saveSettings];
		[self setGuiToStickMapperScreen: 0 resetCurrentRow: YES];
	}
	switch ([gui selectedRow])
	{
	case GUI_ROW_STICKPROFILE_AXIS:
		if ([gameView isDown:key_gui_arrow_left])
		{
			if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
			{
				[stickProfileScreen previousAxis];
				stickProfileArrow_pressed = YES;
			}
		}
		else if ([gameView isDown: key_gui_arrow_right])
		{
			if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
			{
				[stickProfileScreen nextAxis];
				stickProfileArrow_pressed = YES;
			}
		}
		else
		{
			stickProfileArrow_pressed = NO;
		}
		break;

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

	case GUI_ROW_STICKPROFILE_PROFILE_TYPE:
		if ([gameView isDown:key_gui_arrow_left])
		{
			if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
			{
				[stickProfileScreen previousProfileType];
				stickProfileArrow_pressed = YES;
			}
		}
		else if ([gameView isDown: key_gui_arrow_right])
		{
			if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
			{
				[stickProfileScreen nextProfileType];
				stickProfileArrow_pressed = YES;
			}
		}
		else
		{
			stickProfileArrow_pressed = NO;
		}
		break;
	}
		
	if (![stickProfileScreen currentProfileIsSpline])
	{
		if ([gui selectedRow] == GUI_ROW_STICKPROFILE_POWER)
		{
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen DecreasePower];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen IncreasePower];
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
					[stickProfileScreen DecreaseParam];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen IncreaseParam];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
		}
	}
	return;
}

- (void) stickProfileGraphAxisProfile: (GLfloat) alpha screenAt: (Vector) screenAt screenSize: (NSSize) screenSize
{

	[stickProfileScreen graphProfile: alpha at: make_vector(screenAt.x - 110.0, screenAt.y - 100, screenAt.z) size: NSMakeSize(220,220)];
	return;
}

@end

@implementation StickProfileScreen

- (id) init
{
	int i, j;
	
	if ((self = [super init]))
	{
		stickHandler = [OOJoystickManager sharedStickHandler];
		current_axis = AXIS_ROLL;
		for (i = 0; i < 3; i++)
		{
			for (j = 0; j < 2; j++)
			{
				profiles[i][j] = nil;
			}
		}
	}
	return self;
}

- (void) dealloc
{
	int i, j;
	for (i = 0; i < 3; i++)
	{
		for (j = 0; j < 2; j++)
		{
			[profiles[i][j] release];
		}
	}
	[super dealloc];
}
- (void) startGui: (GuiDisplayGen *) gui_display_gen
{
	gui = gui_display_gen;
	[self startEdit];
	[gui clear];
	[gui setTitle: [NSString stringWithFormat: DESC(@"oolite-stickprofile-title")]];
	[self showScreen];
	[gui setSelectedRow: GUI_ROW_STICKPROFILE_AXIS];
	return;
}

- (void) mouseDown: (NSPoint) position
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickSplineAxisProfile *spline_profile;
	NSPoint spline_position;
	
	if (![profile isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		return;
	}
	spline_profile = (OOJoystickSplineAxisProfile *)profile;
	spline_position.x = (position.x - graphRect.origin.x - 10) / (graphRect.size.width - 20);
	spline_position.y = (-position.y - graphRect.origin.y - 10) / (graphRect.size.height - 20);
	if (spline_position.x >= 0.0 && spline_position.x <= 1.0 && spline_position.y >= 0.0 && spline_position.y <= 1.0)
	{
		if (dragged_control_point < 0)
		{
			selected_control_point = [spline_profile addControl: spline_position];
			dragged_control_point = selected_control_point;
			double_click_control_point = -1;
		}
		else
		{
			[spline_profile moveControl: dragged_control_point point: spline_position];
		}
		[stickHandler saveStickSettings];
	}
	return;
}

- (void) mouseUp
{
	if (selected_control_point >= 0)
	{
		double_click_control_point = selected_control_point;
	}
	dragged_control_point = -1;
	return;
}

- (void) deleteSelected
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickSplineAxisProfile *spline_profile;
	if ([profile isKindOfClass: [OOJoystickSplineAxisProfile class]] && selected_control_point >= 0)
	{
		spline_profile = (OOJoystickSplineAxisProfile *)profile;
		[spline_profile removeControl: selected_control_point];
		selected_control_point = -1;
		dragged_control_point = -1;
		[stickHandler saveStickSettings];
	}
	return;
}
			

@end

@implementation StickProfileScreen (StickProfileInternal)


- (void) nextAxis
{
	if (current_axis == AXIS_ROLL)
		current_axis = AXIS_PITCH;
	else if (current_axis == AXIS_PITCH)
		current_axis = AXIS_YAW;
	[self showScreen];
	return;
}

- (void) previousAxis
{
	if (current_axis == AXIS_PITCH)
		current_axis = AXIS_ROLL;
	else if (current_axis == AXIS_YAW)
		current_axis = AXIS_PITCH;
	[self showScreen];
	return;
}

- (NSString *) currentAxis
{
	switch (current_axis)
	{
	case AXIS_ROLL:
		return DESC(@"stickmapper-roll");
	
	case AXIS_PITCH:
		return DESC(@"stickmapper-pitch");
		
	case AXIS_YAW:
		return DESC(@"stickmapper-yaw");
	}
	return @"";
}

- (void) increaseDeadzone
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	if (profile)
	{
		[profile setDeadzone: [profile deadzone] + STICK_MAX_DEADZONE / 20];
	}
	[self showScreen];
	return;
}

- (void) decreaseDeadzone
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	if (profile)
	{
		[profile setDeadzone: [profile deadzone] - STICK_MAX_DEADZONE / 20];
	}
	[self showScreen];
	return;
}

- (void) nextProfileType
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	double deadzone;
	
	if ([profile isKindOfClass: [OOJoystickStandardAxisProfile class]])
	{
		deadzone = [profile deadzone];
		[profiles[current_axis][0] release];
		profiles[current_axis][0] = [profile retain];
		if (!profiles[current_axis][1])
		{
			profiles[current_axis][1] = [[OOJoystickSplineAxisProfile alloc] init];
		}
		[profiles[current_axis][1] setDeadzone: deadzone];
		[stickHandler setProfile: profiles[current_axis][1] forAxis: current_axis];
		[stickHandler saveStickSettings];
	}
	[self showScreen];
	return;
}

- (void) previousProfileType
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	double deadzone;
	
	if ([profile isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		deadzone = [profile deadzone];
		[profiles[current_axis][1] release];
		profiles[current_axis][1] = [profile retain];
		if (!profiles[current_axis][0])
		{
			profiles[current_axis][0] = [[OOJoystickStandardAxisProfile alloc] init];
		}
		[profiles[current_axis][0] setDeadzone: deadzone];
		[stickHandler setProfile: profiles[current_axis][0] forAxis: current_axis];
		[stickHandler saveStickSettings];
	}
	[self showScreen];
	return;
}

- (BOOL) currentProfileIsSpline
{
	if ([[stickHandler getProfileForAxis: current_axis] isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		return YES;
	}
	return NO;
}

- (void) IncreasePower
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickStandardAxisProfile *standard_profile;

	if (profile && [profile isKindOfClass: [OOJoystickStandardAxisProfile class]])
	{
		standard_profile = (OOJoystickStandardAxisProfile *) profile;
		[standard_profile setPower: [standard_profile power] + STICKPROFILE_MAX_POWER / 20];
		[stickHandler saveStickSettings];
	}
	[self showScreen];
	return;
}

- (void) DecreasePower
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickStandardAxisProfile *standard_profile;

	if (profile && [profile isKindOfClass: [OOJoystickStandardAxisProfile class]])
	{
		standard_profile = (OOJoystickStandardAxisProfile *) profile;
		[standard_profile setPower: [standard_profile power] - STICKPROFILE_MAX_POWER / 20];
		[stickHandler saveStickSettings];
	}
	[self showScreen];
	return;
}

- (void) IncreaseParam
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickStandardAxisProfile *standard_profile;

	if (profile && [profile isKindOfClass: [OOJoystickStandardAxisProfile class]])
	{
		standard_profile = (OOJoystickStandardAxisProfile *) profile;
		[standard_profile setParameter: [standard_profile parameter] + 0.05];
		[stickHandler saveStickSettings];
	}
	[self showScreen];
	return;
}

- (void) DecreaseParam
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickStandardAxisProfile *standard_profile;

	if (profile && [profile isKindOfClass: [OOJoystickStandardAxisProfile class]])
	{
		standard_profile = (OOJoystickStandardAxisProfile *) profile;
		[standard_profile setParameter: [standard_profile parameter] - 0.05];
		[stickHandler saveStickSettings];
	}
	[self showScreen];
	return;
}

- (void) graphProfile: (GLfloat) alpha at: (Vector) at size: (NSSize) size
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickSplineAxisProfile *spline_profile;
	NSInteger i;
	NSPoint point;
	NSArray *control_points;

	if (!profile) return;
	graphRect = NSMakeRect(at.x, at.y, size.width, size.height);
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
			glVertex3f(at.x+i+10,at.y+10+(size.height-20)*[profile rawValue:((float)i)/(size.width-20)],at.z);
		}
	OOGLEND();
	OOGL(glColor4f(0.5,0.0,0.5,alpha));
	GLDrawFilledOval(at.x+10,at.y+10,at.z,NSMakeSize(4,4),20);
	GLDrawFilledOval(at.x+size.width-10,at.y+size.height-10,at.z,NSMakeSize(4,4),20);
	if ([profile isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		spline_profile = (OOJoystickSplineAxisProfile *)profile;
		control_points = [spline_profile controlPoints];
		for (i = 0; i < (NSInteger)[control_points count]; i++)
		{
			if (i == selected_control_point)
			{
				OOGL(glColor4f(1.0,0.0,0.0,alpha));
			}
			else
			{
				OOGL(glColor4f(0.0,1.0,0.0,alpha));
			}
			point = [[control_points objectAtIndex: i] pointValue];
			GLDrawFilledOval(at.x+10+point.x*(size.width - 20),at.y+10+point.y*(size.height-20),at.z,NSMakeSize(4,4),20);
		}
	}
	OOGL(glColor4f(0.9,0.9,0.0,alpha));
	OODrawStringAligned(DESC(@"oolite-stickprofile-movement"), at.x + size.width - 5, at.y, at.z, NSMakeSize(8,10), YES);
	OODrawString(DESC(@"oolite-stickprofile-response"), at.x, at.y + size.height - 10, at.z, NSMakeSize(8,10));
	return;
}

- (void) startEdit
{
	int i, j;
	
	for (i = 0; i < 3; i++)
	{
		for (j = 0; j < 2; j++)
		{
			[profiles[i][j] release];
			profiles[i][j] = nil;
		}
	}
	current_axis = AXIS_ROLL;
	selected_control_point = -1;
	dragged_control_point = -1;
	double_click_control_point = -1;
	return;
}

- (void) saveSettings
{
	[stickHandler saveStickSettings];
	return;
}

- (void) showScreen
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	OOJoystickStandardAxisProfile *standard_profile;
	NSString *v1 = @"||||||||||||||||||||";
	NSString *v2 = @"....................";
	int bars;
	double value;
	double power;

	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 50;
	tabStop[1] = 140;
	[gui setTabStops:tabStop];
	[gui setArray: [NSArray arrayWithObjects: DESC(@"oolite-stickprofile-axis"), [self currentAxis], nil ] forRow: GUI_ROW_STICKPROFILE_AXIS];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_AXIS];
	value = [profile deadzone];
	bars = (int)(20 * value / STICK_MAX_DEADZONE + 0.5);
	if (bars < 0) bars = 0;
	if (bars > 20) bars = 20;
	[gui setArray: [NSArray arrayWithObjects: DESC(@"oolite-stickprofile-deadzone"),
		[NSString stringWithFormat:
			@"%@%@ (%0.4f)",
			[v1 substringToIndex: bars],
			[v2 substringToIndex: 20 - bars],
			value],
		nil] forRow: GUI_ROW_STICKPROFILE_DEADZONE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_DEADZONE];
	[gui setArray: [NSArray arrayWithObjects: DESC(@"oolite-stickprofile-profile-type"), [self profileType], nil ] forRow: GUI_ROW_STICKPROFILE_PROFILE_TYPE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_PROFILE_TYPE];
	if ([profile isKindOfClass:[OOJoystickStandardAxisProfile class]])
	{
		standard_profile = (OOJoystickStandardAxisProfile*) profile;
		power = [standard_profile power];
		bars = (int)(20*power / STICKPROFILE_MAX_POWER + 0.5);
		if (bars < 0) bars = 0;
		if (bars > 20) bars = 20;
		[gui setArray: [NSArray arrayWithObjects: DESC(@"oolite-stickprofile-range"),
			[NSString stringWithFormat: @"%@%@ (%.1f) ", [v1 substringToIndex: bars], [v2 substringToIndex: 20 - bars], power],
			nil] forRow: GUI_ROW_STICKPROFILE_POWER];
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_POWER];
		value = [standard_profile parameter];
		bars = 20*value;
		if (bars < 0) bars = 0;
		if (bars > 20) bars = 20;
		[gui setArray: [NSArray arrayWithObjects: DESC(@"oolite-stickprofile-sensitivity"),
			[NSString stringWithFormat: @"%@%@ (%0.2f) ", [v1 substringToIndex: bars], [v2 substringToIndex: 20 - bars], value],
			nil] forRow: GUI_ROW_STICKPROFILE_PARAM];
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_PARAM];
		[gui setColor:[OOColor yellowColor] forRow: GUI_ROW_STICKPROFILE_PARAM];
	}
	else
	{
		[gui setText: @"" forRow: GUI_ROW_STICKPROFILE_POWER];
		[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_POWER];
		[gui setText: DESC(@"oolite-stickprofile-spline-instructions") forRow: GUI_ROW_STICKPROFILE_PARAM];
		[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_PARAM];
		[gui setColor:[OOColor magentaColor] forRow: GUI_ROW_STICKPROFILE_PARAM];
	}
	[gui setText: DESC(@"gui-back") forRow: GUI_ROW_STICKPROFILE_BACK];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_BACK];
	[gui setSelectableRange: NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK)];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[PLAYER status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey: @"settings"];
	return;
}

- (NSString *) profileType
{
	OOJoystickAxisProfile *profile = [stickHandler getProfileForAxis: current_axis];
	
	if ([profile isKindOfClass: [OOJoystickStandardAxisProfile class]])
	{
		return DESC(@"oolite-stickprofile-type-standard");
	}
	if ([profile isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		return DESC(@"oolite-stickprofile-type-spline");
	}
	return DESC(@"oolite-stickprofile-type-standard");
}

@end

