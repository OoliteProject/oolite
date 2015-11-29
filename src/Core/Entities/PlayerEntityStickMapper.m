/*

PlayerEntityStickMapper.m

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

#import "PlayerEntityStickMapper.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityStickProfile.h"
#import "OOJoystickManager.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"

@interface PlayerEntity (StickMapperInternal)

- (void) removeFunction:(int)selFunctionIdx;
- (NSArray *)stickFunctionList;
- (void)displayFunctionList:(GuiDisplayGen *)gui
					   skip:(NSUInteger) skip;
- (NSString *)describeStickDict:(NSDictionary *)stickDict;
- (NSString *)hwToString:(int)hwFlags;

@end


@implementation PlayerEntity (StickMapper)

- (void) setGuiToStickMapperScreen:(unsigned)skip
{
	[self setGuiToStickMapperScreen: skip resetCurrentRow: NO];
}

- (void) setGuiToStickMapperScreen:(unsigned)skip resetCurrentRow: (BOOL) resetCurrentRow
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	NSArray			*stickList = [stickHandler listSticks];
	unsigned		i;
	
	OOGUITabStop	tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 50;
	tabStop[1] = 210;
	tabStop[2] = 320;
	[gui setTabStops:tabStop];
	
	gui_screen = GUI_SCREEN_STICKMAPPER;
	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"Configure Joysticks"]];
	
	for(i=0; i < [stickList count]; i++)
	{
		[gui setArray:[NSArray arrayWithObjects:
					   [NSString stringWithFormat: @"Stick %d", i+1],
					   [stickList objectAtIndex: i],
					   nil]
			   forRow:i + GUI_ROW_STICKNAME];
	}

	[gui setArray: [NSArray arrayWithObjects: DESC(@"stickmapper-profile"), nil] forRow: GUI_ROW_STICKPROFILE];
	[gui setKey: GUI_KEY_OK forRow: GUI_ROW_STICKPROFILE];
	[self displayFunctionList:gui skip:skip];
	
	[gui setArray:[NSArray arrayWithObject:@"Select a function and press Enter to modify or 'u' to unset."]
		   forRow:GUI_ROW_INSTRUCT];
	
	if (resetCurrentRow)
	{
		[gui setSelectedRow: GUI_ROW_STICKPROFILE];
	}
	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"settings"];
}


- (void) stickMapperInputHandler:(GuiDisplayGen *)gui
							view:(MyOpenGLView *)gameView
{
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];

	// Don't do anything if the user is supposed to be selecting
	// a function - other than look for Escape.
	if(waitingForStickCallback)
	{
		if([gameView isDown: 27])
		{
			[stickHandler clearCallback];
			[gui setArray: [NSArray arrayWithObjects:
							@"Function setting aborted.", nil]
				   forRow: GUI_ROW_INSTRUCT];
			waitingForStickCallback=NO;
		}
		
		// Break out now.
		return;
	}
	
	[self handleGUIUpDownArrowKeys];
	
	if ([gui selectedRow] == GUI_ROW_STICKPROFILE && [gameView isDown: 13])
	{
		[self setGuiToStickProfileScreen: gui];
		return;
	}
	
	NSString* key = [gui keyForRow: [gui selectedRow]];
	if ([key hasPrefix:@"Index:"])
		selFunctionIdx=[[[key componentsSeparatedByString:@":"] objectAtIndex: 1] intValue];
	else
		selFunctionIdx=-1;

	if([gameView isDown: 13])
	{
		if ([key hasPrefix:@"More:"])
		{
			int from_function = [[[key componentsSeparatedByString:@":"] objectAtIndex: 1] intValue];
			if (from_function < 0)  from_function = 0;
			
			[self setGuiToStickMapperScreen:from_function];
			if ([[UNIVERSE gui] selectedRow] < 0)
				[[UNIVERSE gui] setSelectedRow: GUI_ROW_FUNCSTART];
			if (from_function == 0)
				[[UNIVERSE gui] setSelectedRow: GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1];
			return;
		}
		
		NSDictionary *entry=[stickFunctions objectAtIndex: selFunctionIdx];
		int hw=[(NSNumber *)[entry objectForKey: KEY_ALLOWABLE] intValue];
		[stickHandler setCallback: @selector(updateFunction:)
						   object: self 
						 hardware: hw];
		
		// Print instructions
		NSString *instructions;
		switch(hw)
		{
			case HW_AXIS:
				instructions = @"Fully deflect the axis you want to use for this function. Esc aborts.";
				break;
			case HW_BUTTON:
				instructions = @"Press the button you want to use for this function. Esc aborts.";
				break;
			default:
				instructions = @"Press the button or deflect the axis you want to use for this function.";
		}
		[gui setArray: [NSArray arrayWithObjects: instructions, nil] forRow: GUI_ROW_INSTRUCT];
		waitingForStickCallback=YES;
	}
	
	if([gameView isDown: 'u'])
	{
		if (selFunctionIdx >= 0)  [self removeFunction: selFunctionIdx];
	}
}


// Callback function, called by JoystickHandler when the callback
// is set. The dictionary contains the thing that was pressed/moved.
- (void) updateFunction: (NSDictionary *)hwDict
{
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	waitingForStickCallback = NO;
	
	// Right time and the right place?
	if(gui_screen != GUI_SCREEN_STICKMAPPER)
	{
		OOLog(@"joystick.configure.error", @"%s called when not on stick mapper screen.", __PRETTY_FUNCTION__);
		return;
	}
	
	// What moved?
	int function;
	NSDictionary *entry = [stickFunctions objectAtIndex:selFunctionIdx];
	if([hwDict oo_boolForKey:STICK_ISAXIS])
	{
		function=[entry oo_intForKey: KEY_AXISFN];
		if (function == AXIS_THRUST)
		{
			[stickHandler unsetButtonFunction:BUTTON_INCTHRUST];
			[stickHandler unsetButtonFunction:BUTTON_DECTHRUST];
		}
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		if (function == AXIS_FIELD_OF_VIEW)
		{
			[stickHandler unsetButtonFunction:BUTTON_INC_FIELD_OF_VIEW];
			[stickHandler unsetButtonFunction:BUTTON_DEC_FIELD_OF_VIEW];
		}
#endif
		if (function == AXIS_VIEWX)
		{
			[stickHandler unsetButtonFunction:BUTTON_VIEWPORT];
			[stickHandler unsetButtonFunction:BUTTON_VIEWSTARBOARD];
		}
		if (function == AXIS_VIEWY)
		{
			[stickHandler unsetButtonFunction:BUTTON_VIEWFORWARD];
			[stickHandler unsetButtonFunction:BUTTON_VIEWAFT];
		}
	}
	else
	{
		function = [entry oo_intForKey:KEY_BUTTONFN];
		if (function == BUTTON_INCTHRUST || function == BUTTON_DECTHRUST)
		{
			[stickHandler unsetAxisFunction:AXIS_THRUST];
		}
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		if (function == BUTTON_INC_FIELD_OF_VIEW || function == BUTTON_DEC_FIELD_OF_VIEW)
		{
			[stickHandler unsetAxisFunction:AXIS_FIELD_OF_VIEW];
		}
#endif
		if (function == BUTTON_VIEWPORT || function == BUTTON_VIEWSTARBOARD)
		{
			[stickHandler unsetAxisFunction:AXIS_VIEWX];
		}
		if (function == BUTTON_VIEWFORWARD || function == BUTTON_VIEWAFT)
		{
			[stickHandler unsetAxisFunction:AXIS_VIEWY];
		}
	}
	[stickHandler setFunction:function withDict:hwDict];
	[stickHandler saveStickSettings];
	
	// Update the GUI (this will refresh the function list).
	unsigned skip;
	if (selFunctionIdx < MAX_ROWS_FUNCTIONS - 1)
	{
		skip = 0;
	}
	else
	{
		skip = ((selFunctionIdx - 1) / (MAX_ROWS_FUNCTIONS - 2)) * (MAX_ROWS_FUNCTIONS - 2) + 1;
	}
	
	[self setGuiToStickMapperScreen:skip];
}


- (void) removeFunction:(int)idx
{
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	NSDictionary		*entry = [stickFunctions objectAtIndex:idx];
	NSNumber			*butfunc = [entry objectForKey:KEY_BUTTONFN];
	NSNumber			*axfunc = [entry objectForKey:KEY_AXISFN];
	selFunctionIdx = idx;
	
	// Some things can have either axis or buttons - make sure we clear
	// both!
	if(butfunc)
	{
		[stickHandler unsetButtonFunction:[butfunc intValue]];
	}
	if(axfunc)
	{
		[stickHandler unsetAxisFunction:[axfunc intValue]];
	}
	[stickHandler saveStickSettings];
	
	unsigned skip;
	if (selFunctionIdx < MAX_ROWS_FUNCTIONS - 1)
		skip = 0;
	else
		skip = ((selFunctionIdx - 1) / (MAX_ROWS_FUNCTIONS - 2)) * (MAX_ROWS_FUNCTIONS - 2) + 1;
	[self setGuiToStickMapperScreen: skip];
}


- (void) displayFunctionList:(GuiDisplayGen *)gui
						skip:(NSUInteger)skip
{
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	
	[gui setColor:[OOColor greenColor] forRow: GUI_ROW_HEADING];
	[gui setArray:[NSArray arrayWithObjects:
				   @"Function", @"Assigned to", @"Type", nil]
		   forRow:GUI_ROW_HEADING];
	
	if(!stickFunctions)
	{
		stickFunctions = [[self stickFunctionList] retain];
	}
	NSDictionary *assignedAxes = [stickHandler axisFunctions];
	NSDictionary *assignedButs = [stickHandler buttonFunctions];
	
	NSUInteger i, n_functions = [stickFunctions count];
	NSInteger n_rows, start_row, previous = 0;
	
	if (skip >= n_functions)
		skip = n_functions - 1;
	
	if (n_functions < MAX_ROWS_FUNCTIONS)
	{
		skip = 0;
		previous = 0;
		n_rows = MAX_ROWS_FUNCTIONS;
		start_row = GUI_ROW_FUNCSTART;
	}
	else
	{
		n_rows = MAX_ROWS_FUNCTIONS  - 1;
		start_row = GUI_ROW_FUNCSTART;
		if (skip > 0)
		{
			n_rows -= 1;
			start_row += 1;
			if (skip > MAX_ROWS_FUNCTIONS)
				previous = skip - (MAX_ROWS_FUNCTIONS - 2);
			else
				previous = 0;
		}
	}
	
	if (n_functions > 0)
	{
		if (skip > 0)
		{
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_FUNCSTART];
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:GUI_ROW_FUNCSTART];
			[gui setKey:[NSString stringWithFormat:@"More:%ld", previous] forRow:GUI_ROW_FUNCSTART];
		}
		
		for(i=0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			NSString *allowedThings;
			NSString *assignment;
			NSDictionary *entry = [stickFunctions objectAtIndex: i + skip];
			NSString *axFuncKey = [entry oo_stringForKey:KEY_AXISFN];
			NSString *butFuncKey = [entry oo_stringForKey:KEY_BUTTONFN];
			int allowable = [entry oo_intForKey:KEY_ALLOWABLE];
			switch(allowable)
			{
				case HW_AXIS:
					allowedThings=@"Axis";
					assignment=[self describeStickDict:
								[assignedAxes objectForKey: axFuncKey]];
					break;
				case HW_BUTTON:
					allowedThings=@"Button";
					assignment=[self describeStickDict:
								[assignedButs objectForKey: butFuncKey]];
					break;
				default:
					allowedThings=@"Axis/Button";
					
					// axis has priority
					assignment=[self describeStickDict:
								[assignedAxes objectForKey: axFuncKey]];
					if(!assignment)
						assignment=[self describeStickDict:
									[assignedButs objectForKey: butFuncKey]];
			}
			
			// Find out what's assigned for this function currently.
			if (assignment == nil)
			{
				assignment = @"   -   ";
			}
			
			[gui setArray: [NSArray arrayWithObjects: 
							[entry objectForKey: KEY_GUIDESC], assignment, allowedThings, nil]
				   forRow: i + start_row];
			//[gui setKey: GUI_KEY_OK forRow: i + start_row];
			[gui setKey: [NSString stringWithFormat: @"Index:%ld", i + skip] forRow: i + start_row];
		}
		if (i < n_functions - skip)
		{
			[gui setColor: [OOColor greenColor] forRow: start_row + i];
			[gui setArray: [NSArray arrayWithObjects: DESC(@"gui-more"), @" --> ", nil] forRow: start_row + i];
			[gui setKey: [NSString stringWithFormat: @"More:%ld", n_rows + skip] forRow: start_row + i];
			i++;
		}
		
		[gui setSelectableRange: NSMakeRange(GUI_ROW_STICKPROFILE, i + start_row - GUI_ROW_STICKPROFILE)];
	}
	
}


- (NSString *) describeStickDict: (NSDictionary *)stickDict
{
	NSString *desc=nil;
	if(stickDict)
	{
		int thingNumber=[(NSNumber *)[stickDict objectForKey: STICK_AXBUT]
						 intValue];
		int stickNumber=[(NSNumber *)[stickDict objectForKey: STICK_NUMBER]
						 intValue];
		// Button or axis?
		if([(NSNumber *)[stickDict objectForKey: STICK_ISAXIS] boolValue])
		{
			desc=[NSString stringWithFormat: @"Stick %d axis %d",
				  stickNumber+1, thingNumber+1];
		}
		else if(thingNumber >= MAX_REAL_BUTTONS)
		{
			static const char dir[][6] = { "up", "right", "down", "left" };
			desc=[NSString stringWithFormat: @"Stick %d hat %d %s",
				  stickNumber+1, (thingNumber - MAX_REAL_BUTTONS) / 4 + 1,
				  dir[thingNumber & 3]];
		}
		else
		{
			desc=[NSString stringWithFormat: @"Stick %d button %d",
				  stickNumber+1, thingNumber+1];
		}
	}
	return desc;
}


- (NSString *)hwToString: (int)hwFlags
{
	NSString *hwString;
	switch(hwFlags)
	{
		case HW_AXIS:
			hwString = @"axis";
			break;
		case HW_BUTTON:
			hwString = @"button";
			break;
		default:
			hwString = @"axis/button";
	}
	return hwString;   
}


// TODO: This data could be put into a plist (i18n or just modifiable by
// the user). It is otherwise an ugly method, but it'll do for testing.
- (NSArray *)stickFunctionList
{
	NSMutableArray *funcList = [NSMutableArray array];
	
	[funcList addObject: 
	 [self makeStickGuiDict:DESC(@"stickmapper-roll")
				  allowable:HW_AXIS
					 axisfn:AXIS_ROLL
					  butfn:STICK_NOFUNCTION]];
	[funcList addObject: 
	 [self makeStickGuiDict:DESC(@"stickmapper-pitch")
				  allowable:HW_AXIS
					 axisfn:AXIS_PITCH
					  butfn:STICK_NOFUNCTION]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-yaw")
				  allowable:HW_AXIS
					 axisfn:AXIS_YAW
					  butfn:STICK_NOFUNCTION]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-increase-thrust")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_THRUST
					  butfn:BUTTON_INCTHRUST]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-decrease-thrust")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_THRUST
					  butfn:BUTTON_DECTHRUST]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-primary-weapon")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_FIRE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-secondary-weapon")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_LAUNCHMISSILE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-arm-secondary")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_ARMMISSILE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-disarm-secondary")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_UNARM]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-target-nearest-incoming-missile")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_TARGETINCOMINGMISSILE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-cycle-secondary")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_CYCLEMISSILE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-weapons-online-toggle")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_WEAPONSONLINETOGGLE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-prime-equipment")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_PRIMEEQUIPMENT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-activate-equipment")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_ACTIVATEEQUIPMENT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-mode-equipment")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_MODEEQUIPMENT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-fastactivate-a")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_CLOAK]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-fastactivate-b")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_ENERGYBOMB]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-ECM")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_ECM]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-toggle-ID")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_ID]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-previous-target")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_PREVTARGET]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-next-target")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_NEXTTARGET]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-fuel-injection")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_FUELINJECT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-hyperspeed")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_HYPERSPEED]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-hyperdrive")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_HYPERDRIVE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-roll/pitch-precision-toggle")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_PRECISION]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-snapshot")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_SNAPSHOT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-escape-pod")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_ESCAPE]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-scanner-zoom")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_SCANNERZOOM]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-scanner-unzoom")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_SCANNERUNZOOM]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-jettison")
				  allowable:HW_BUTTON
					 axisfn:STICK_NOFUNCTION
					  butfn:BUTTON_JETTISON]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-view-forward")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_VIEWY
					  butfn:BUTTON_VIEWFORWARD]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-view-aft")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_VIEWY
					  butfn:BUTTON_VIEWAFT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-view-port")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_VIEWX
					  butfn:BUTTON_VIEWPORT]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-view-starboard")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_VIEWX
					  butfn:BUTTON_VIEWSTARBOARD]];
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-increase-field-of-view")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_FIELD_OF_VIEW
					  butfn:BUTTON_INC_FIELD_OF_VIEW]];
	[funcList addObject:
	 [self makeStickGuiDict:DESC(@"stickmapper-decrease-field-of-view")
				  allowable:HW_AXIS|HW_BUTTON
					 axisfn:AXIS_FIELD_OF_VIEW
					  butfn:BUTTON_DEC_FIELD_OF_VIEW]];
#endif
	return funcList;
}


- (NSDictionary *)makeStickGuiDict:(NSString *)what
						 allowable:(int)allowable
							axisfn:(int)axisfn
							 butfn:(int)butfn
{
	NSMutableDictionary *guiDict = [NSMutableDictionary dictionary];
	
	if ([what length] > 30)  what = [[what substringToIndex:28] stringByAppendingString:@"..."];
	[guiDict setObject: what  forKey: KEY_GUIDESC];
	[guiDict setObject: [NSNumber numberWithInt: allowable]  
				forKey: KEY_ALLOWABLE];
	if(axisfn >= 0)
		[guiDict setObject: [NSNumber numberWithInt: axisfn]
					forKey: KEY_AXISFN];
	if(butfn >= 0)
		[guiDict setObject: [NSNumber numberWithInt: butfn]
					forKey: KEY_BUTTONFN];
	return guiDict;
}

@end

