/*

PlayerEntityKeyMapper.m

Oolite
Copyright (C) 2004-2019 Giles C Williams and contributors

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

#import "PlayerEntityKeyMapper.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityScriptMethods.h"
#import "OOTexture.h"
#import "OOCollectionExtractors.h"
#import "HeadUpDisplay.h"

@interface PlayerEntity (KeyMapperInternal)

- (void)displayKeyFunctionList:(GuiDisplayGen *)gui
					   skip:(NSUInteger) skip;
- (NSArray *)keyFunctionList;
- (void)saveKeySettings;
- (void)loadKeySettings;

@end

@implementation PlayerEntity (KeyMapper)

- (void) setGuiToKeyMapperScreen:(unsigned)skip
{
	[self setGuiToKeyMapperScreen: skip resetCurrentRow: NO];
}

- (void) setGuiToKeyMapperScreen:(unsigned)skip resetCurrentRow: (BOOL) resetCurrentRow
{
	GuiDisplayGen	*gui = [UNIVERSE gui];
	OOGUITabStop	tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	tabStop[2] = 390;
	[gui setTabStops:tabStop];

	gui_screen = GUI_SCREEN_KEYBOARD;
	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"Configure Keyboard"]];

	[self displayKeyFunctionList:gui skip:skip];

	[gui setArray:[NSArray arrayWithObject:@"Select a function and press Enter to modify or 'r' to reset to default."]
		   forRow:GUI_ROW_KC_INSTRUCT];
	[gui setText:@"Press Ctrl+'r' to reset all functions back to default." forRow:GUI_ROW_KC_INSTRUCT+1 align:GUI_ALIGN_CENTER];
	[gui setText:@"Space to return to previous screen." forRow:GUI_ROW_KC_INSTRUCT+2 align:GUI_ALIGN_CENTER];

	[[UNIVERSE gameView] supressKeysUntilKeyUp];
	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"settings"];

}

- (void) keyMapperInputHandler:(GuiDisplayGen *)gui
							view:(MyOpenGLView *)gameView
{

	[self handleGUIUpDownArrowKeys];

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
			
			[self setGuiToKeyMapperScreen:from_function];
			if ([[UNIVERSE gui] selectedRow] < 0)
				[[UNIVERSE gui] setSelectedRow: GUI_ROW_KC_FUNCSTART];
			if (from_function == 0)
				[[UNIVERSE gui] setSelectedRow: GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1];
			return;
		}


	}
}

- (void) displayKeyFunctionList:(GuiDisplayGen *)gui
						skip:(NSUInteger)skip
{
	[gui setColor:[OOColor greenColor] forRow: GUI_ROW_KC_HEADING];
	[gui setArray:[NSArray arrayWithObjects:
				   @"Function", @"Assigned to", @"Overrides", nil]
		   forRow:GUI_ROW_KC_HEADING];

	if(!keyFunctions)
	{
		keyFunctions = [[self keyFunctionList] retain];
	}

	NSUInteger i, n_functions = [keyFunctions count];
	NSInteger n_rows, start_row, previous = 0;
	
	if (skip >= n_functions)
		skip = n_functions - 1;
	
	if (n_functions < MAX_ROWS_KC_FUNCTIONS)
	{
		skip = 0;
		previous = 0;
		n_rows = MAX_ROWS_KC_FUNCTIONS;
		start_row = GUI_ROW_KC_FUNCSTART;
	}
	else
	{
		n_rows = MAX_ROWS_KC_FUNCTIONS  - 1;
		start_row = GUI_ROW_KC_FUNCSTART;
		if (skip > 0)
		{
			n_rows -= 1;
			start_row += 1;
			if (skip > MAX_ROWS_KC_FUNCTIONS)
				previous = skip - (MAX_ROWS_KC_FUNCTIONS - 2);
			else
				previous = 0;
		}
	}
	
	if (n_functions > 0)
	{
		if (skip > 0)
		{
			[gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_FUNCSTART];
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-back"), @" <-- ", nil] forRow:GUI_ROW_KC_FUNCSTART];
			[gui setKey:[NSString stringWithFormat:@"More:%ld", previous] forRow:GUI_ROW_KC_FUNCSTART];
		}
		
		for(i=0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			NSDictionary *entry = [keyFunctions objectAtIndex: i + skip];
			NSString *assignment = [PLAYER keyBindingDescription2:[entry objectForKey:KEY_KC_DEFINITION]];
			NSString *override = @""; // work out whether this assignment is overriding the setting in keyconfig2.plist

			// Find out what's assigned for this function currently.
			if (assignment == nil)
			{
				assignment = @"   -   ";
			}
			
			[gui setArray: [NSArray arrayWithObjects: 
							[entry objectForKey: KEY_KC_GUIDESC], assignment, override, nil]
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
		
		[gui setSelectableRange: NSMakeRange(GUI_ROW_KC_FUNCSTART, i + start_row - GUI_ROW_KC_FUNCSTART)];
	}

}

- (NSArray *)keyFunctionList
{
	NSMutableArray *funcList = [NSMutableArray array];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_launch_ship") keyDef:@"key_launch_ship"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_options") keyDef:@"key_gui_screen_options"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_equipship") keyDef:@"key_gui_screen_equipship"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_interfaces") keyDef:@"key_gui_screen_interfaces"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_status") keyDef:@"key_gui_screen_status"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_chart_screens") keyDef:@"key_gui_chart_screens"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_system_data") keyDef:@"key_gui_system_data"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_market") keyDef:@"key_gui_market"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_left") keyDef:@"key_gui_arrow_left"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_right") keyDef:@"key_gui_arrow_right"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_up") keyDef:@"key_gui_arrow_up"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_down") keyDef:@"key_gui_arrow_down"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_page_down") keyDef:@"key_gui_page_down"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_page_up") keyDef:@"key_gui_page_up"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_select") keyDef:@"key_gui_select"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_roll_left") keyDef:@"key_roll_left"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_roll_right") keyDef:@"key_roll_right"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_pitch_forward") keyDef:@"key_pitch_forward"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_pitch_back") keyDef:@"key_pitch_back"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_yaw_left") keyDef:@"key_yaw_left"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_yaw_right") keyDef:@"key_yaw_right"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_increase_speed") keyDef:@"key_increase_speed"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_decrease_speed") keyDef:@"key_decrease_speed"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_inject_fuel") keyDef:@"key_inject_fuel"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_jumpdrive") keyDef:@"key_jumpdrive"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_hyperspace") keyDef:@"key_hyperspace"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_galactic_hyperspace") keyDef:@"key_galactic_hyperspace"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_prev_compass_mode") keyDef:@"key_prev_compass_mode"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_next_compass_mode") keyDef:@"key_next_compass_mode"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_scanner_zoom") keyDef:@"key_scanner_zoom"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_scanner_unzoom") keyDef:@"key_scanner_unzoom"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_forward") keyDef:@"key_view_forward"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_aft") keyDef:@"key_view_aft"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_port") keyDef:@"key_view_port"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_starboard") keyDef:@"key_view_starboard"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_ident_system") keyDef:@"key_ident_system"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_docking_clearance_request") keyDef:@"key_docking_clearance_request"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_autopilot") keyDef:@"key_autopilot"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_autodock") keyDef:@"key_autodock"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_docking_music") keyDef:@"key_docking_music"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_weapons_online_toggle") keyDef:@"key_weapons_online_toggle"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_fire_lasers") keyDef:@"key_fire_lasers"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_launch_missile") keyDef:@"key_launch_missile"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_target_missile") keyDef:@"key_target_missile"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_untarget_missile") keyDef:@"key_untarget_missile"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_target_incoming_missile") keyDef:@"key_target_incoming_missile"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_next_missile") keyDef:@"key_next_missile"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_next_target") keyDef:@"key_next_target"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_previous_target") keyDef:@"key_previous_target"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_ecm") keyDef:@"key_ecm"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dump_cargo") keyDef:@"key_dump_cargo"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_rotate_cargo") keyDef:@"key_rotate_cargo"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_launch_escapepod") keyDef:@"key_launch_escapepod"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_cycle_next_mfd") keyDef:@"key_cycle_next_mfd"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_cycle_previous_mfd") keyDef:@"key_cycle_previous_mfd"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_switch_next_mfd") keyDef:@"key_switch_next_mfd"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_switch_previous_mfd") keyDef:@"key_switch_previous_mfd"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_prime_next_equipment") keyDef:@"key_prime_next_equipment"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_prime_previous_equipment") keyDef:@"key_prime_previous_equipment"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_activate_equipment") keyDef:@"key_activate_equipment"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_mode_equipment") keyDef:@"key_mode_equipment"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_fastactivate_equipment_a") keyDef:@"key_fastactivate_equipment_a"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_fastactivate_equipment_b") keyDef:@"key_fastactivate_equipment_b"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_snapshot") keyDef:@"key_snapshot"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_pausebutton") keyDef:@"key_pausebutton"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_show_fps") keyDef:@"key_show_fps"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_mouse_control_roll") keyDef:@"key_mouse_control_roll"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_mouse_control_yaw") keyDef:@"key_mouse_control_yaw"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_hud_toggle") keyDef:@"key_hud_toggle"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_inc_field_of_view") keyDef:@"key_inc_field_of_view"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dec_field_of_view") keyDef:@"key_dec_field_of_view"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_comms_log") keyDef:@"key_comms_log"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_advanced_nav_array_next") keyDef:@"key_advanced_nav_array_next"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_advanced_nav_array_previous") keyDef:@"key_advanced_nav_array_previous"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_home") keyDef:@"key_map_home"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_end") keyDef:@"key_map_end"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_info") keyDef:@"key_map_info"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_zoom_in") keyDef:@"key_map_zoom_in"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_zoom_out") keyDef:@"key_map_zoom_out"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_next_system") keyDef:@"key_map_next_system"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_previous_system") keyDef:@"key_map_previous_system"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_chart_highlight") keyDef:@"key_chart_highlight"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_home") keyDef:@"key_system_home"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_end") keyDef:@"key_system_end"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_next_system") keyDef:@"key_system_next_system"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_previous_system") keyDef:@"key_system_previous_system"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_filter_cycle") keyDef:@"key_market_filter_cycle"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_sorter_cycle") keyDef:@"key_market_sorter_cycle"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_buy_one") keyDef:@"key_market_buy_one"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_sell_one") keyDef:@"key_market_sell_one"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_buy_max") keyDef:@"key_market_buy_max"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_sell_max") keyDef:@"key_market_sell_max"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view") keyDef:@"key_custom_view"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_zoom_in") keyDef:@"key_custom_view_zoom_in"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_zoom_out") keyDef:@"key_custom_view_zoom_out"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_roll_left") keyDef:@"key_custom_view_roll_left"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_roll_right") keyDef:@"key_custom_view_roll_right"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_left") keyDef:@"key_custom_view_pan_left"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_right") keyDef:@"key_custom_view_pan_right"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_up") keyDef:@"key_custom_view_pan_up"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_down") keyDef:@"key_custom_view_pan_down"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_left") keyDef:@"key_custom_view_rotate_left"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_right") keyDef:@"key_custom_view_rotate_right"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_up") keyDef:@"key_custom_view_rotate_up"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_down") keyDef:@"key_custom_view_rotate_down"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_oxzmanager_setfilter") keyDef:@"key_oxzmanager_setfilter"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_oxzmanager_showinfo") keyDef:@"key_oxzmanager_showinfo"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_oxzmanager_extract") keyDef:@"key_oxzmanager_extract"]];

	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dump_target_state") keyDef:@"key_dump_target_state"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dump_entity_list") keyDef:@"key_dump_entity_list"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_full") keyDef:@"key_debug_full"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_collision") keyDef:@"key_debug_collision"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_console_connect") keyDef:@"key_debug_console_connect"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_bounding_boxes") keyDef:@"key_debug_bounding_boxes"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_shaders") keyDef:@"key_debug_shaders"]];
	[funcList addObject: [self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_off") keyDef:@"key_debug_off"]];

	return funcList;
}

- (NSDictionary *)makeKeyGuiDict:(NSString *)what keyDef:(NSString*) keyDef
{
	NSMutableDictionary *guiDict = [NSMutableDictionary dictionary];
	if ([what length] > 50)  what = [[what substringToIndex:48] stringByAppendingString:@"..."];
	[guiDict setObject: what  forKey: KEY_KC_GUIDESC];
	[guiDict setObject: keyDef forKey: KEY_KC_DEFINITION];
	return guiDict;
}

- (void) saveKeySettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
}

- (void) loadKeySettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
}

@end