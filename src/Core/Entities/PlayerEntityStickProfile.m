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
#define GUI_ROW_STICKPROFILE_AXIS		2
#define GUI_ROW_STICKPROFILE_PROFILE 		3
#define GUI_ROW_STICKPROFILE_MANAGE		5
#define GUI_ROW_STICKPROFILE_NEW_PROFILE	6
#define GUI_ROW_STICKPROFILE_EDIT_PROFILE	7
#define GUI_ROW_STICKPROFILE_DELETE_PROFILE	8

#define GUI_ROW_STICKPROFILE_EDITNAME	3
#define GUI_ROW_STICKPROFILE_DEADZONE	4
#define GUI_ROW_STICKPROFILE_POWER	5
#define GUI_ROW_STICKPROFILE_PARAM	6

#define STICKPROFILE_SCREEN_MAIN	1
#define STICKPROFILE_SCREEN_EDIT	2
#define STICKPROFILE_SCREEN_DELETE	3

static BOOL stickProfileArrow_pressed;
static BOOL stickProfileEnter_pressed;


@interface StickProfileScreen (StickProfileInternal)

- (void) showProfile: (OOJoystickAxisProfile *) profile gui: (GuiDisplayGen *) gui;
- (void) showScreen: (GuiDisplayGen *) gui;
- (void) showMainScreen: (GuiDisplayGen *) gui;
- (void) showEditScreen: (GuiDisplayGen *) gui;
- (NSString *) axisName: (int) axis;
- (void) nextAxis: (GuiDisplayGen *) gui;
- (void) previousAxis: (GuiDisplayGen *) gui;
- (void) nextProfile: (GuiDisplayGen *) gui;
- (void) previousProfile: (GuiDisplayGen *) gui;
- (void) increaseDeadzone: (GuiDisplayGen *) gui;
- (void) decreaseDeadzone: (GuiDisplayGen *) gui;
- (void) polyIncreasePower: (GuiDisplayGen *) gui;
- (void) polyDecreasePower: (GuiDisplayGen *) gui;
- (void) polyIncreaseParam: (GuiDisplayGen *) gui;
- (void) polyDecreaseParam: (GuiDisplayGen *) gui;
- (BOOL) currentProfileIsPolynomial;
- (BOOL) currentProfileIsSpline;
- (int) currentScreen;
- (NSString *) currentNewType;
- (void) nextNewType: (GuiDisplayGen *) gui;
- (void) previousNewType: (GuiDisplayGen *) gui;
- (NSString *) editProfile;
- (NSString *) deleteProfile;
- (void) nextEditProfile: (GuiDisplayGen *) gui;
- (void) previousEditProfile: (GuiDisplayGen *) gui;
- (void) nextDeleteProfile: (GuiDisplayGen *) gui;
- (void) previousDeleteProfile: (GuiDisplayGen *) gui;
- (void) saveSettings;
- (void) graphProfile: (GLfloat) alpha at: (Vector) at size: (NSSize) size;
- (void) startEdit: (GuiDisplayGen *) gui;
- (void) endEdit: (GuiDisplayGen *) gui;
- (void) editName: (GuiDisplayGen *) gui;
- (void) endEditName: (GuiDisplayGen *) gui;

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
	if ([stickProfileScreen isEditingText])
	{
		if ([gameView isDown: 13])
		{
			[stickProfileScreen endEditName: gui];
		}
		return;
	}
	else
	{
		[self handleGUIUpDownArrowKeys];
	}
	
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
		case GUI_ROW_STICKPROFILE_AXIS:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen previousAxis: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen nextAxis: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
			break;
		
		case GUI_ROW_STICKPROFILE_PROFILE:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen previousProfile: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen nextProfile: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
			break;

		case GUI_ROW_STICKPROFILE_NEW_PROFILE:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen previousNewType: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen nextNewType: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
			break;
	
		case GUI_ROW_STICKPROFILE_EDIT_PROFILE:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen previousEditProfile: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen nextEditProfile: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
			if (!stickProfileEnter_pressed && [gameView isDown: 13])
			{
				[stickProfileScreen startEdit: gui];
				stickProfileEnter_pressed = NO;
			}
			else
			{
				stickProfileEnter_pressed = NO;
			}
			break;
	
		case GUI_ROW_STICKPROFILE_DELETE_PROFILE:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen previousDeleteProfile: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen nextDeleteProfile: gui];
					[self playChangedOption];
					stickProfileArrow_pressed = YES;
				}
			}
			else
			{
				stickProfileArrow_pressed = NO;
			}
			break;
		}
	break;
	
	case STICKPROFILE_SCREEN_EDIT:
		if ([gameView isDown:13] && [gui selectedRow] == GUI_ROW_STICKPROFILE_BACK)
		{
			[stickProfileScreen endEdit: gui];
		}
		switch ([gui selectedRow])
		{
		case GUI_ROW_STICKPROFILE_EDITNAME:
			if (!stickProfileEnter_pressed && [gameView isDown: 13])
			{
				stickProfileEnter_pressed = YES;
				[stickProfileScreen editName: gui];
			}
			else
			{
				stickProfileEnter_pressed = NO;
			}
			break;
		
		case GUI_ROW_STICKPROFILE_DEADZONE:
			if ([gameView isDown:key_gui_arrow_left])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_right])
				{
					[stickProfileScreen decreaseDeadzone: gui];
					stickProfileArrow_pressed = YES;
				}
			}
			else if ([gameView isDown: key_gui_arrow_right])
			{
				if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
				{
					[stickProfileScreen increaseDeadzone: gui];
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
						[stickProfileScreen polyDecreasePower: gui];
						stickProfileArrow_pressed = YES;
					}
				}
				else if ([gameView isDown: key_gui_arrow_right])
				{
					if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
					{
						[stickProfileScreen polyIncreasePower: gui];
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
						[stickProfileScreen polyDecreaseParam: gui];
						stickProfileArrow_pressed = YES;
					}
				}
				else if ([gameView isDown: key_gui_arrow_right])
				{
					if (!stickProfileArrow_pressed && ![gameView isDown: key_gui_arrow_left])
					{
						[stickProfileScreen polyIncreaseParam: gui];
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
		profileManager = [stickHandler getProfileManager];
		current_axis = AXIS_ROLL;
		new_type = STICK_PROFILE_TYPE_POLYNOMIAL;
		edit_profile = nil;
		delete_profile = nil;
		current_edit_profile = nil;
		editing_name = NO;
	}
	return self;
}

- (void) dealloc
{
	[edit_profile release];
	[delete_profile release];
	[current_edit_profile release];
	[super dealloc];
	return;
}

- (void) setGuiToScreen: (GuiDisplayGen *) gui
{
	if (current_edit_profile)
	{
		[current_edit_profile release];
		current_edit_profile = nil;
	}
	current_screen = STICKPROFILE_SCREEN_MAIN;
	[gui clear];
	[gui setTitle: [NSString stringWithFormat: @"Joystick Profile"]];
	[self showScreen: gui];
	[gui setSelectedRow: GUI_ROW_STICKPROFILE_BACK];
	return;
}

- (BOOL) isEditingText
{
	return editing_name;
}

@end

@implementation StickProfileScreen (StickProfileInternal)

- (void) nextAxis: (GuiDisplayGen *) gui
{
	switch (current_axis)
	{
	case AXIS_ROLL:
		current_axis = AXIS_PITCH;
		break;
	case AXIS_PITCH:
	case AXIS_YAW:
		current_axis = AXIS_YAW;
		break;
	default:
		current_axis = AXIS_ROLL;
	}
	[self showScreen: gui];
	return;
}

- (void) previousAxis: (GuiDisplayGen *) gui
{
	switch (current_axis)
	{
	case AXIS_YAW:
		current_axis = AXIS_PITCH;
		break;
	case AXIS_PITCH:
	case AXIS_ROLL:
	default:
		current_axis = AXIS_ROLL;
	}
	[self showScreen: gui];
	return;
}

- (void) nextProfile: (GuiDisplayGen *) gui
{
	NSArray *profileList = [profileManager listProfiles];
	NSUInteger index = [profileList indexOfObject: [profileManager getProfileNameForAxis: current_axis]];
	if (index == NSNotFound)
	{
		index = 0;
	}
	else
	{
		index++;
		if (index >= [profileList count])
		{
			index = [profileList count] - 1;
		}
	}
	[stickHandler setAxisProfileByName: [profileList objectAtIndex: index] forAxis: current_axis ];
	[self showScreen: gui];
	return;
}

- (void) previousProfile: (GuiDisplayGen *) gui
{
	NSArray *profileList = [profileManager listProfiles];
	NSUInteger index = [profileList indexOfObject: [profileManager getProfileNameForAxis: current_axis]];
	if (index == NSNotFound)
	{
		index = 0;
	}
	else
	{
		if (index == 0)
		{
			index = 0;
		}
		else
		{
			index--;
		}
	}
	[stickHandler setAxisProfileByName: [profileList objectAtIndex: index] forAxis: current_axis];
	[self showScreen: gui];
	return;
}

- (void) increaseDeadzone: (GuiDisplayGen *) gui
{
	if (current_edit_profile)
	{
		[current_edit_profile setDeadzone: [current_edit_profile deadzone] + STICKPROFILE_MAX_DEADZONE / 20];
	}
	[self showScreen: gui];
	return;
}

- (void) decreaseDeadzone: (GuiDisplayGen *) gui
{
	if (current_edit_profile)
	{
		[current_edit_profile setDeadzone: [current_edit_profile deadzone] - STICKPROFILE_MAX_DEADZONE / 20];
	}
	[self showScreen: gui];
	return;
}

- (void) polyIncreasePower: (GuiDisplayGen *) gui;
{
	OOJoystickPolynomialAxisProfile *poly_profile;

	if( current_edit_profile && [current_edit_profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *)current_edit_profile;
		if ([poly_profile power] < 20)
			[poly_profile setPower: [poly_profile power] + 1];
	}
	[self showScreen: gui];
	return;
}

- (void) polyDecreasePower: (GuiDisplayGen *) gui;
{
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (current_edit_profile && [current_edit_profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *)current_edit_profile;
		if ([poly_profile power] > 0)
			[poly_profile setPower: [poly_profile power] - 1];
	}
	[self showScreen: gui];
	return;
}

- (void) polyIncreaseParam: (GuiDisplayGen *) gui;
{
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (current_edit_profile && [current_edit_profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *)current_edit_profile;
		[poly_profile setParameter: [poly_profile parameter] + 0.05];
	}
	[self showScreen: gui];
	return;
}

- (void) polyDecreaseParam: (GuiDisplayGen *) gui
{
	OOJoystickPolynomialAxisProfile *poly_profile;

	if (current_edit_profile && [current_edit_profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]])
	{
		poly_profile = (OOJoystickPolynomialAxisProfile *)current_edit_profile;
		[poly_profile setParameter: [poly_profile parameter] - 0.05];
	}
	[self showScreen: gui];
	return;
}

- (BOOL) currentProfileIsPolynomial
{
	return (current_edit_profile && [current_edit_profile isKindOfClass: [OOJoystickPolynomialAxisProfile class]]);
}


- (BOOL) currentProfileIsSpline
{
	return (current_edit_profile && [current_edit_profile isKindOfClass: [OOJoystickSplineAxisProfile class]]);
}

- (int) currentScreen
{
	return current_screen;
}

- (NSString *) currentNewType
{
	switch (new_type)
	{
	case STICK_PROFILE_TYPE_POLYNOMIAL:
		return @"Polynomial";

	case STICK_PROFILE_TYPE_SPLINE:
		return @"Spline";
	
	default:
		new_type = STICK_PROFILE_TYPE_POLYNOMIAL;
		return @"Polynomial";
	}
}

- (void) nextNewType: (GuiDisplayGen *) gui
{
	if (new_type == STICK_PROFILE_TYPE_POLYNOMIAL)
	{
		new_type = STICK_PROFILE_TYPE_SPLINE;
	}
	[self showMainScreen: gui];
}

- (void) previousNewType: (GuiDisplayGen *) gui
{
	if (new_type == STICK_PROFILE_TYPE_SPLINE)
	{
		new_type = STICK_PROFILE_TYPE_POLYNOMIAL;
	}
	[self showMainScreen: gui];
}

- (NSString *) editProfile
{
	NSArray *profile_list = [NSArray arrayWithArray: [profileManager listProfiles]];
	
	if (edit_profile && [profile_list indexOfObject: edit_profile] == NSNotFound)
	{
		[edit_profile release];
		edit_profile = nil;
	}
	
	if (edit_profile == nil)
	{
		if ([profile_list count] > 0)
		{
			edit_profile = [[profile_list objectAtIndex: 0] retain];
		}
	}
	return edit_profile;
}

- (NSString *) deleteProfile
{
	NSArray *profile_list = [NSArray arrayWithArray: [profileManager listProfiles]];
	NSUInteger i;
	
	if (delete_profile && ([profileManager isProfileUsed: delete_profile] || [profile_list indexOfObject: delete_profile] == NSNotFound))
	{
		[delete_profile release];
		delete_profile = nil;
	}
	if (delete_profile == nil)
	{
		for (i = 0; i < [profile_list count]; i++)
		{
			if (![profileManager isProfileUsed: [profile_list objectAtIndex: i]])
				delete_profile = [[profile_list objectAtIndex: i] retain];
		}
	}
	return delete_profile;
}

- (void) nextEditProfile: (GuiDisplayGen *) gui
{
	NSArray *profile_list;
	NSUInteger i;

	if (!edit_profile)
	{
		[self editProfile];
		[self showMainScreen: gui];
		return;
	}
	
	profile_list = [profileManager listProfiles];
	i = [profile_list indexOfObject: edit_profile];
	if (i == NSNotFound)
	{
		[self editProfile];
		[self showMainScreen: gui];
		return;
	}
	
	if (i + 1 < [profile_list count])
	{
		[edit_profile release];
		edit_profile = [[profile_list objectAtIndex: i + 1] retain];
	}
	[self showMainScreen: gui];
	return;
}

- (void) previousEditProfile: (GuiDisplayGen *) gui
{
	NSArray *profile_list;
	NSUInteger i;

	if (!edit_profile)
	{
		[self editProfile];
		[self showMainScreen: gui];
		return;
	}
	
	profile_list = [profileManager listProfiles];
	i = [profile_list indexOfObject: edit_profile];
	if (i == NSNotFound)
	{
		[self editProfile];
		[self showMainScreen: gui];
		return;
	}
	
	if (i > 0)
	{
		[edit_profile release];
		edit_profile = [[profile_list objectAtIndex: i - 1] retain];
	}
	[self showMainScreen: gui];
	return;
}

- (void) nextDeleteProfile: (GuiDisplayGen *) gui
{
	NSArray *profile_list;
	NSUInteger i, j;

	if (!delete_profile)
	{
		[self deleteProfile];
		[self showMainScreen: gui];
		return;
	}
	
	profile_list = [profileManager listProfiles];
	i = [profile_list indexOfObject: delete_profile];
	if (i == NSNotFound)
	{
		[self deleteProfile];
		[self showMainScreen: gui];
		return;
	}
	
	for (j = i + 1; j < [profile_list count]; j++)
	{
		if (![profileManager isProfileUsed: [profile_list objectAtIndex: j]])
		{
			[delete_profile release];
			delete_profile = [[profile_list objectAtIndex: j] retain];
			[self showMainScreen: gui];
			return;
		}
	}
	for (j = i; j >= 0; j--)
	{
		if (![profileManager isProfileUsed: [profile_list objectAtIndex: j]])
		{
			[delete_profile release];
			delete_profile = [[profile_list objectAtIndex: j] retain];
			[self showMainScreen: gui];
			return;
		}
	}
	[delete_profile release];
	delete_profile = nil;
	[self showMainScreen: gui];
	return;
}

- (void) previousDeleteProfile: (GuiDisplayGen *) gui
{
	NSArray *profile_list;
	NSUInteger i, j;

	if (!delete_profile)
	{
		[self deleteProfile];
		[self showMainScreen: gui];
		return;
	}
	
	profile_list = [profileManager listProfiles];
	i = [profile_list indexOfObject: delete_profile];
	if (i == NSNotFound)
	{
		[self deleteProfile];
		[self showMainScreen: gui];
		return;
	}
	
	for (j = i - 1; j >= 0; j--)
	{
		if (![profileManager isProfileUsed: [profile_list objectAtIndex: j]])
		{
			[delete_profile release];
			delete_profile = [[profile_list objectAtIndex: j] retain];
			[self showMainScreen: gui];
			return;
		}
	}
	for (j = i; j < [profile_list count]; j++)
	{
		if (![profileManager isProfileUsed: [profile_list objectAtIndex: j]])
		{
			[delete_profile release];
			delete_profile = [[profile_list objectAtIndex: j] retain];
			[self showMainScreen: gui];
			return;
		}
	}
	[delete_profile release];
	delete_profile = nil;
	[self showMainScreen: gui];
	return;
}

- (void) graphProfile: (GLfloat) alpha at: (Vector) at size: (NSSize) size
{
	OOJoystickAxisProfile *current_profile;
	OOJoystickSplineAxisProfile *spline_profile;
	int i;
	NSPoint point;
	NSArray *control_points;

	switch (current_screen)
	{
	case STICKPROFILE_SCREEN_MAIN:
		current_profile = [profileManager getProfile: [stickHandler getAxisProfileName: current_axis]];
		break;

	case STICKPROFILE_SCREEN_EDIT:
		current_profile = current_edit_profile;
		break;
		
	default:
		return;
	}
	if (!current_profile) return;
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
			glVertex3f(at.x+i+10,at.y+10+(size.height-20)*[current_profile valueNoDeadzone:((float)i)/(size.width-20)],at.z);
		}
	OOGLEND();
	OOGL(glColor4f(1.0,0.0,0.0,alpha));
	GLDrawFilledOval(at.x+10,at.y+10,at.z,NSMakeSize(4,4),20);
	GLDrawFilledOval(at.x+size.width-10,at.y+size.width-10,at.z,NSMakeSize(4,4),20);
	OOGL(glColor4f(0.0,1.0,0.0,alpha));
	if ([current_profile isKindOfClass: [OOJoystickSplineAxisProfile class]])
	{
		spline_profile = (OOJoystickSplineAxisProfile *)current_profile;
		control_points = [spline_profile controlPoints];
		for (i = 0; i < [control_points count]; i++)
		{
			point = [[control_points objectAtIndex: i] pointValue];
			GLDrawFilledOval(at.x+10+point.x*(size.width - 20),at.y+10+point.y*(size.height-20),at.z,NSMakeSize(4,4),20);
		}
	}
	return;
}

- (void) startEdit: (GuiDisplayGen *) gui
{
	if (current_edit_profile)
	{
		[current_edit_profile release];
	}
	[gui clear];
	[gui setTitle: [NSString stringWithFormat: @"Edit Joystick Profile"]];
	current_screen = STICKPROFILE_SCREEN_EDIT;
	current_edit_profile = [[profileManager getProfile: [self editProfile]] retain];
	[self showScreen: gui];
	[gui setSelectedRow: GUI_ROW_STICKPROFILE_EDITNAME];
	return;
}

- (void) endEdit: (GuiDisplayGen *) gui
{
	[current_edit_profile release];
	current_edit_profile = nil;
	[self setGuiToScreen: gui];
}

- (void) editName: (GuiDisplayGen *) gui
{
	MyOpenGLView *gameView = [UNIVERSE gameView];

	[gameView setTypedString: edit_profile];
	editing_name = YES;
	[gui setNoSelectedRow];
	[self showScreen: gui];
}

- (void) endEditName: (GuiDisplayGen *) gui
{
	MyOpenGLView *gameView;
	NSString * new_edit_profile;

	gameView = [UNIVERSE gameView];
	new_edit_profile = [gameView typedString];
	if ([profileManager renameProfile: edit_profile to:new_edit_profile])
	{
		[edit_profile release];
		edit_profile = [new_edit_profile retain];
		[gameView resetTypedString];
		[gameView allowStringInput: NO];
		editing_name = NO;
	}
	[self showScreen: gui];
	if (!editing_name)
	{
		[gui setSelectedRow: GUI_ROW_STICKPROFILE_EDITNAME];
	}
}

- (void) saveSettings
{
	[stickHandler saveStickSettings];
	return;
}

- (void) showScreen: (GuiDisplayGen *) gui
{
	[gui setText: @"Back" forRow: GUI_ROW_STICKPROFILE_BACK];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_BACK];
	switch (current_screen)
	{
	case STICKPROFILE_SCREEN_EDIT:
		[self showEditScreen: gui];
		break;

	case STICKPROFILE_SCREEN_MAIN:
	default:
		[self showMainScreen: gui];
		break;
	}
	[gui setSelectableRange: NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK)];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[PLAYER status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey: @"settings"];
	return;
}

- (void) showMainScreen: (GuiDisplayGen *) gui
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
	[gui setArray: [NSArray arrayWithObjects: @"Axis:", [self axisName: current_axis], nil] forRow: GUI_ROW_STICKPROFILE_AXIS];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_AXIS];
	[gui setArray: [NSArray arrayWithObjects: @"Profile:", [profileManager getProfileNameForAxis: current_axis], nil] forRow: GUI_ROW_STICKPROFILE_PROFILE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_PROFILE];
	[gui setText: @"Manage Profiles" forRow: GUI_ROW_STICKPROFILE_MANAGE];
	[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_MANAGE];
	[gui setColor:[OOColor greenColor] forRow: GUI_ROW_STICKPROFILE_MANAGE];
	[gui setArray: [NSArray arrayWithObjects: @"New:", [self currentNewType], nil] forRow: GUI_ROW_STICKPROFILE_NEW_PROFILE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_NEW_PROFILE];
	if ([self editProfile])
	{
		[gui setArray: [NSArray arrayWithObjects: @"Edit:", edit_profile, nil] forRow: GUI_ROW_STICKPROFILE_EDIT_PROFILE];
		[gui setColor:[OOColor yellowColor] forRow: GUI_ROW_STICKPROFILE_EDIT_PROFILE];
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_EDIT_PROFILE];
	}
	else
	{
		[gui setArray: [NSArray arrayWithObjects: @"Edit:", nil] forRow: GUI_ROW_STICKPROFILE_EDIT_PROFILE];
		[gui setColor:[OOColor grayColor] forRow: GUI_ROW_STICKPROFILE_EDIT_PROFILE];
		[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_EDIT_PROFILE];
	}
	if ([self deleteProfile])
	{
		[gui setArray: [NSArray arrayWithObjects: @"Delete:", delete_profile, nil] forRow: GUI_ROW_STICKPROFILE_DELETE_PROFILE];
		[gui setColor:[OOColor yellowColor] forRow: GUI_ROW_STICKPROFILE_DELETE_PROFILE];
		[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_DELETE_PROFILE];
	}
	else
	{
		[gui setArray: [NSArray arrayWithObjects: @"Delete:", delete_profile, nil] forRow: GUI_ROW_STICKPROFILE_DELETE_PROFILE];
		[gui setColor:[OOColor grayColor] forRow: GUI_ROW_STICKPROFILE_DELETE_PROFILE];
		[gui setKey: GUI_KEY_SKIP forRow: GUI_ROW_STICKPROFILE_DELETE_PROFILE];
	}
	[gui setSelectableRange: NSMakeRange(1, GUI_ROW_STICKPROFILE_BACK)];
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[PLAYER status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey: @"settings"];
	return;
}

- (void) showEditScreen: (GuiDisplayGen *) gui
{
	if (current_edit_profile)
	{
		[self showProfile: current_edit_profile gui: gui];
	}
	return;
}

- (void) showProfile: (OOJoystickAxisProfile *) profile gui: (GuiDisplayGen *) gui
{
	OOJoystickPolynomialAxisProfile *poly_profile;
	NSString *v1 = @"||||||||||||||||||||";
	NSString *v2 = @"....................";
	int bars;
	double value;
	int power;
	MyOpenGLView *gameView = [UNIVERSE gameView];

	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 50;
	tabStop[1] = 120;
	[gui setTabStops:tabStop];
	if (editing_name)
	{
		[gui setText: [NSString stringWithFormat: @"Name: %@", [gameView typedString]] forRow: GUI_ROW_STICKPROFILE_EDITNAME];
		[gui setShowTextCursor: YES];
		[gui setCurrentRow: GUI_ROW_STICKPROFILE_EDITNAME];
	}
	else
	{
		[gui setArray: [NSArray arrayWithObjects: @"Name:", edit_profile, nil] forRow: GUI_ROW_STICKPROFILE_EDITNAME];
		[gui setShowTextCursor: NO];
	}
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE_EDITNAME];
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
		poly_profile = (OOJoystickPolynomialAxisProfile*)profile;
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

