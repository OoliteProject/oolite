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
#import "ResourceManager.h"
#import "GameController.h"

static NSUInteger key_index;
static long current_row;
static long kbd_row = GUI_ROW_KC_FUNCSTART;
static BOOL has_error = NO;
static BOOL last_shift = NO;
static NSDictionary *selected_entry = nil;
static NSMutableArray *key_list = nil;
static NSDictionary *kdic_check = nil;
static NSArray *nav_keys = nil;
static NSArray *camera_keys = nil;

@interface PlayerEntity (KeyMapperInternal)

- (void)resetKeyFunctions;
- (void)updateKeyDefinition:(NSString *)keystring index:(NSUInteger)index;
- (void)updateShiftKeyDefinition:(NSString *)key index:(NSUInteger)index;
- (void)displayKeyFunctionList:(GuiDisplayGen *)gui skip:(NSUInteger)skip;
- (NSString *)keyboardDescription:(NSString *)kbd;
- (void)displayKeyboardLayoutList:(GuiDisplayGen *)gui skip:(NSUInteger)skip;
- (BOOL)entryIsIndexCustomEquip:(NSUInteger)idx;
- (BOOL)entryIsDictCustomEquip:(NSDictionary *)dict;
- (BOOL)entryIsCustomEquip:(NSString *)entry;
- (NSArray *)getCustomEquipArray:(NSString *)key_def;
- (NSString *)getCustomEquipKeyDefType:(NSString *)key_def;
- (NSUInteger)getCustomEquipIndex:(NSString *)key_def;
- (NSArray *)keyFunctionList;
- (NSArray *)validateAllKeys;
- (NSString *)validateKey:(NSString*)key checkKeys:(NSArray*)check_keys;
- (NSString *)searchArrayForMatch:(NSArray *)search_list key:(NSString *)key checkKeys:(NSArray *)check_keys;
- (BOOL)entryIsEqualToDefault:(NSString *)key;
- (BOOL)compareKeyEntries:(NSDictionary *)first second:(NSDictionary *)second;
- (void)saveKeySetting:(NSString *)key;
- (void)unsetKeySetting:(NSString *)key;
- (void)deleteKeySetting:(NSString *)key;
- (void)deleteAllKeySettings;
- (NSDictionary *)loadKeySettings;
- (void) reloadPage;

@end

@implementation PlayerEntity (KeyMapper)

// sets up a copy of the raw keyconfig.plist file so we can run checks against it to tell if a key is set to default
- (void) initCheckingDictionary
{
	NSMutableDictionary *kdicmaster = [NSMutableDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keyconfig2.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *kbd = [defaults oo_stringForKey:@"keyboard-code" defaultValue:@"default"];
	NSMutableDictionary *kdic = [NSMutableDictionary dictionaryWithDictionary:[kdicmaster objectForKey:kbd]];

	NSUInteger i;
	NSArray *keys = nil;
	id key = nil;
	NSArray *def_list = nil;

	keys = [kdic allKeys];
	for (i = 0; i < [keys count]; i++)
	{
		key = [keys objectAtIndex:i];

		if ([[kdic objectForKey: key] isKindOfClass:[NSArray class]])
		{
			def_list = (NSArray*)[kdic objectForKey: key];
			[kdic setObject:[self processKeyCode:def_list] forKey:key];
		}
	}
	[kdic_check release];
	kdic_check = [[NSDictionary alloc] initWithDictionary:kdic];

	// these keys can't be used with mod keys
	[nav_keys release];
	nav_keys = [[NSArray alloc] initWithObjects:@"key_roll_left", @"key_roll_right", @"key_pitch_forward", @"key_pitch_back", @"key_yaw_left", @"key_yaw_right", 
		@"key_fire_lasers", @"key_gui_arrow_up", @"key_gui_arrow_down", @"key_gui_arrow_right", @"key_gui_arrow_left", nil];
	// these keys can't be used with ctrl
	[camera_keys release];
	camera_keys = [[NSArray alloc] initWithObjects:@"key_custom_view_zoom_out", @"key_custom_view_zoom_in", @"key_custom_view_roll_left", @"key_custom_view_roll_right",
		@"key_custom_view_pan_left", @"key_custom_view_pan_right", @"key_custom_view_rotate_up", @"key_custom_view_rotate_down", @"key_custom_view_pan_down",
		@"key_custom_view_pan_up", @"key_custom_view_rotate_left", @"key_custom_view_rotate_right", nil];
}


- (void) resetKeyFunctions
{
	[keyFunctions release];
	keyFunctions = nil;
}


- (void) setGuiToKeyMapperScreen:(unsigned)skip
{
	[self setGuiToKeyMapperScreen:skip resetCurrentRow:NO];
}

- (void) setGuiToKeyMapperScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *kbd = [defaults oo_stringForKey:@"keyboard-code" defaultValue:@"default"];

	GuiDisplayGen *gui = [UNIVERSE gui];
	MyOpenGLView *gameView = [UNIVERSE gameView];
	OOGUIScreenID oldScreen = gui_screen;
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	tabStop[2] = 400;
	[gui setTabStops:tabStop];

	if (!kdic_check) [self initCheckingDictionary];

	gui_screen = GUI_SCREEN_KEYBOARD;
	BOOL guiChanged = (oldScreen != gui_screen);
	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"Configure Keyboard"]];

	// show keyboard layout
	[gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-keyconfig-keyboard"), [self keyboardDescription:kbd], nil] forRow:GUI_ROW_KC_SELECTKBD];
	[gui setKey:[NSString stringWithFormat:@"kbd:%@", kbd] forRow:GUI_ROW_KC_SELECTKBD];
	[gui setColor:[OOColor yellowColor] forRow:GUI_ROW_KC_SELECTKBD];

	[self displayKeyFunctionList:gui skip:skip];

	has_error = NO;
	if ([[self validateAllKeys] count] > 0)
	{
		has_error = YES;
		[gui setText:DESC(@"oolite-keyconfig-validation-error") forRow:GUI_ROW_KC_ERROR align:GUI_ALIGN_CENTER];
		[gui setColor:[OOColor redColor] forRow:GUI_ROW_KC_ERROR];

	}
	[gui setArray:[NSArray arrayWithObject:DESC(@"oolite-keyconfig-initial-info-1")] forRow:GUI_ROW_KC_INSTRUCT];
	[gui setText:DESC(@"oolite-keyconfig-initial-info-2") forRow:GUI_ROW_KC_INSTRUCT+1 align:GUI_ALIGN_CENTER];
	if (has_error)
	{
		[gui setText:DESC(@"oolite-keyconfig-initial-error") forRow:GUI_ROW_KC_INSTRUCT+2 align:GUI_ALIGN_CENTER];
	}
	else
	{
		[gui setText:DESC(@"oolite-keyconfig-initial-info-3") forRow:GUI_ROW_KC_INSTRUCT+2 align:GUI_ALIGN_CENTER];
	}

	if (resetCurrentRow)
	{
		int offset = 0;
		if ([[keyFunctions objectAtIndex:skip] objectForKey:KEY_KC_HEADER]) offset = 1;
		[gui setSelectedRow:GUI_ROW_KC_FUNCSTART + offset];
	}
	else 
	{
		[gui setSelectedRow:current_row];
	}

	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"keyboardsettings"];

	[gameView clearMouse];
	[gameView clearKeys];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

	if (guiChanged) [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}


- (void) keyMapperInputHandler:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView
{
	[self handleGUIUpDownArrowKeys];
	BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || [gameView isDown:gvMouseDoubleClick]);
	if ([gameView isDown:gvMouseDoubleClick])  [gameView clearMouse];

	NSString *key = [gui keyForRow: [gui selectedRow]];
	if ([key hasPrefix:@"Index:"])
		selFunctionIdx=[[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];
	else
		selFunctionIdx=-1;

	if (selectKeyPress)
	{
		if ([key hasPrefix:@"More:"])
		{
			int from_function = [[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];
			if (from_function < 0)  from_function = 0;

			current_row = GUI_ROW_KC_FUNCSTART;
			if (from_function == 0) current_row = GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1;
			[self setGuiToKeyMapperScreen:from_function];
			if ([gameView isDown:gvMouseDoubleClick]) [gameView clearMouse];
			return;
		}
		if ([key hasPrefix:@"kbd:"])
		{
			[self setGuiToKeyboardLayoutScreen:0];
			if ([gameView isDown:gvMouseDoubleClick]) [gameView clearMouse];
			return;
		}
		current_row = [gui selectedRow];
		selected_entry = [keyFunctions objectAtIndex:selFunctionIdx];
		[key_list release];
		if (![self entryIsDictCustomEquip:selected_entry]) 
		{
			key_list = [[NSMutableArray alloc] initWithArray:(NSArray *)[keyconfig2_settings objectForKey:[selected_entry objectForKey:KEY_KC_DEFINITION]] copyItems:YES];
		}
		else 
		{
			key_list = [[NSMutableArray alloc] initWithArray:[self getCustomEquipArray:[selected_entry oo_stringForKey:KEY_KC_DEFINITION]]];
		}
		[gameView clearKeys];	// try to stop key bounces
		[self setGuiToKeyConfigScreen:YES];
	}

	if ([gameView isDown:'u'])
	{
		// pressed 'u' on an "more" line
		if ([key hasPrefix:@"More:"]) return;

		current_row = [gui selectedRow];
		[self unsetKeySetting:[[keyFunctions objectAtIndex:selFunctionIdx] objectForKey:KEY_KC_DEFINITION]];
		[self reloadPage];
	}

	if ([gameView isDown:'r'])
	{
		// reset single entry or all
		if (![gameView isCtrlDown]) 
		{
			// pressed 'r' on an "more" line
			if ([key hasPrefix:@"More:"]) return;

			current_row = [gui selectedRow];
			[self deleteKeySetting:[[keyFunctions objectAtIndex:selFunctionIdx] objectForKey:KEY_KC_DEFINITION]];
			[self reloadPage];
		}
		else
		{
			[self setGuiToConfirmClearScreen];
		}
	}
	if ([gameView isDown:' '] && !has_error) [self setGuiToGameOptionsScreen];
}


- (BOOL) entryIsIndexCustomEquip:(NSUInteger)idx
{
	return [self entryIsCustomEquip:[[keyFunctions objectAtIndex:idx] oo_stringForKey:KEY_KC_DEFINITION]];
}


- (BOOL) entryIsDictCustomEquip:(NSDictionary *)dict
{
	return [self entryIsCustomEquip:[dict oo_stringForKey:KEY_KC_DEFINITION]];
}

- (BOOL) entryIsCustomEquip:(NSString *)entry
{
	BOOL result = NO;
	if ([entry hasPrefix:@"activate_"] || [entry hasPrefix:@"mode_"])
		result = YES;
	return result;
}

- (NSArray *) getCustomEquipArray:(NSString *)key_def
{
	NSString *eq = nil;
	NSUInteger i;
	NSString *key;
	if ([key_def hasPrefix:@"activate_"]) 
	{
		eq = [key_def stringByReplacingOccurrencesOfString:@"activate_" withString:@""];
		key = CUSTOMEQUIP_KEYACTIVATE;
	}
	if ([key_def hasPrefix:@"mode_"]) 
	{
		eq = [key_def stringByReplacingOccurrencesOfString:@"mode_" withString:@""];
		key = CUSTOMEQUIP_KEYMODE;
	}
	if (eq == nil) return nil;
	for (i = 0; i < [customEquipActivation count]; i++)
	{
		if ([[[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPKEY] isEqualToString:eq])
		{
			return [[customEquipActivation objectAtIndex:i] oo_arrayForKey:key];
		}
	}
	return nil;
}


- (NSUInteger) getCustomEquipIndex:(NSString *)key_def
{
	NSString *eq = nil;
	NSUInteger i;
	if ([key_def hasPrefix:@"activate_"]) 
	{
		eq = [key_def stringByReplacingOccurrencesOfString:@"activate_" withString:@""];
	}
	if ([key_def hasPrefix:@"mode_"]) 
	{
		eq = [key_def stringByReplacingOccurrencesOfString:@"mode_" withString:@""];
	}
	if (eq == nil) return -1;
	for (i = 0; i < [customEquipActivation count]; i++)
	{
		if ([[[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPKEY] isEqualToString:eq])
		{
			return i;
		}
	}
	return -1;
}


- (NSString *) getCustomEquipKeyDefType:(NSString *)key_def
{
	if ([key_def hasPrefix:@"activate_"]) 
	{
		return CUSTOMEQUIP_KEYACTIVATE;
	}
	if ([key_def hasPrefix:@"mode_"]) 
	{
		return CUSTOMEQUIP_KEYMODE;
	}
	return @"";
}


- (void) setGuiToKeyConfigScreen
{
	[self setGuiToKeyConfigScreen:NO];
}


- (void) setGuiToKeyConfigScreen:(BOOL)resetSelectedRow
{
	NSUInteger i = 0;
	GuiDisplayGen *gui=[UNIVERSE gui];
	OOGUIScreenID oldScreen = gui_screen;
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	[gui setTabStops:tabStop];

	gui_screen = GUI_SCREEN_KEYBOARD_CONFIG;
	BOOL guiChanged = (oldScreen != gui_screen);
	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"%@", DESC(@"oolite-keyconfig-update-title")]];

	[gui setArray: [NSArray arrayWithObjects: 
								DESC(@"oolite-keyconfig-update-function"), [selected_entry objectForKey: KEY_KC_GUIDESC], nil]
					forRow: GUI_ROW_KC_UPDATE_FUNCNAME];
	[gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_UPDATE_FUNCNAME];

	NSString *keystring = nil;
	NSString *keyshift = nil;
	NSString *keymod1 = nil;
	NSString *keymod2 = nil;

	NSDictionary *def = nil;
	NSString *key = nil;
	OOKeyCode k_int;

	// get each key for the first two item in the selected entry
	for (i = 0; i <= 1; i++)
	{
		keystring = DESC(@"oolite-keycode-unset");
		keyshift = DESC(@"oolite-keyconfig-modkey-off");
		keymod1 = DESC(@"oolite-keyconfig-modkey-off");
		keymod2 = DESC(@"oolite-keyconfig-modkey-off");

		if ([key_list count] > i)
		{
			def = [key_list objectAtIndex:i];
			key = [def objectForKey:@"key"];
			k_int = (OOKeyCode)[key integerValue];
			if (k_int > 0)
			{
				keystring = [self keyCodeDescription:k_int];
				if ([[def objectForKey:@"shift"] boolValue] == YES) keyshift = DESC(@"oolite-keyconfig-modkey-on");
				if ([[def objectForKey:@"mod1"] boolValue] == YES) keymod1 = DESC(@"oolite-keyconfig-modkey-on");
				if ([[def objectForKey:@"mod2"] boolValue] == YES) keymod2 = DESC(@"oolite-keyconfig-modkey-on");
			}
		}

		[self outputKeyDefinition:keystring shift:keyshift mod1:keymod1 mod2:keymod2 skiprows:(i * 5)];
	}

	NSString *helper = DESC(@"oolite-keyconfig-update-helper");
	if ([nav_keys containsObject:[selected_entry objectForKey: KEY_KC_DEFINITION]])
		helper = [NSString stringWithFormat:@"%@ %@", helper, DESC(@"oolite-keyconfig-update-navkeys")];
	if ([camera_keys containsObject:[selected_entry objectForKey: KEY_KC_DEFINITION]])
		helper = [NSString stringWithFormat:@"%@ %@", helper, DESC(@"oolite-keyconfig-update-camkeys")];
	[gui addLongText:helper startingAtRow:GUI_ROW_KC_UPDATE_INFO align:GUI_ALIGN_LEFT];

	[gui setText:@"" forRow:GUI_ROW_KC_VALIDATION];

	[gui setText:DESC(@"oolite-keyconfig-update-save") forRow:GUI_ROW_KC_SAVE align:GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_SAVE];
	
	[gui setText:DESC(@"oolite-keyconfig-update-cancel") forRow:GUI_ROW_KC_CANCEL align:GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_CANCEL];

	[gui setSelectableRange: NSMakeRange(GUI_ROW_KC_KEY, (GUI_ROW_KC_CANCEL - GUI_ROW_KC_KEY) + 1)];

	NSString *validate = [self validateKey:[selected_entry objectForKey:KEY_KC_DEFINITION] checkKeys:key_list];
	if (validate)
	{
		for (i = 0; i < [keyFunctions count]; i++)
		{
			if ([[[keyFunctions objectAtIndex:i] objectForKey:KEY_KC_DEFINITION] isEqualToString:validate])
			{
				[gui setText:[NSString stringWithFormat:DESC(@"oolite-keyconfig-update-validation-@"), (NSString *)[[keyFunctions objectAtIndex:i] objectForKey:KEY_KC_GUIDESC]] 
					forRow:GUI_ROW_KC_VALIDATION align:GUI_ALIGN_CENTER];
				[gui setColor:[OOColor orangeColor] forRow:GUI_ROW_KC_VALIDATION];
				break;
			}
		}
	}

	if (resetSelectedRow)
	{
		[gui setSelectedRow: GUI_ROW_KC_KEY];
	}

	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"keyboardsettings"];
	[[UNIVERSE gameView] clearMouse];
	[[UNIVERSE gameView] clearKeys];
	if (guiChanged) [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}


- (void) outputKeyDefinition:(NSString *)key shift:(NSString *)shift mod1:(NSString *)mod1 mod2:(NSString *)mod2 skiprows:(NSUInteger)skiprows
{
	GuiDisplayGen *gui=[UNIVERSE gui];

	[gui setArray:[NSArray arrayWithObjects: 
								(skiprows == 0 ? DESC(@"oolite-keyconfig-update-key") : DESC(@"oolite-keyconfig-update-alternate")), key, nil]
					forRow:GUI_ROW_KC_KEY + skiprows];
	[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_KEY + skiprows];

	if (![nav_keys containsObject:[selected_entry objectForKey: KEY_KC_DEFINITION]]) {
		if (![key isEqualToString:DESC(@"oolite-keycode-unset")])
		{
			[gui setArray:[NSArray arrayWithObjects: 
										DESC(@"oolite-keyconfig-update-shift"), shift, nil]
							forRow:GUI_ROW_KC_SHIFT + skiprows];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_SHIFT + skiprows];

			// camera movement keys can't use ctrl
			if (![camera_keys containsObject:[selected_entry objectForKey: KEY_KC_DEFINITION]]) {
				[gui setArray:[NSArray arrayWithObjects: 
											DESC(@"oolite-keyconfig-update-mod1"), mod1, nil]
								forRow:GUI_ROW_KC_MOD1 + skiprows];
				[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_MOD1 + skiprows];
			} 
			else 
			{
				[gui setArray:[NSArray arrayWithObjects: 
											DESC(@"oolite-keyconfig-update-mod1"), DESC(@"not-applicable"), nil]
								forRow:GUI_ROW_KC_MOD1 + skiprows];
			}
					
#if OOLITE_MAC_OS_X
			[gui setArray:[NSArray arrayWithObjects: 
										DESC(@"oolite-keyconfig-update-mod2-mac"), mod2, nil]
							forRow:GUI_ROW_KC_MOD2 + skiprows];
#else
			[gui setArray:[NSArray arrayWithObjects: 
										DESC(@"oolite-keyconfig-update-mod2-pc"), mod2, nil]
							forRow: GUI_ROW_KC_MOD2 + skiprows];
#endif
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_MOD2 + skiprows];
		}
	}
}


- (void) handleKeyConfigKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView
{
	[self handleGUIUpDownArrowKeys];
	BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select]||[gameView isDown:gvMouseDoubleClick]);
	if ([gameView isDown:gvMouseDoubleClick])  [gameView clearMouse];
	
	if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_KEY || [gui selectedRow] == (GUI_ROW_KC_KEY + 5)))
	{
		key_index = ([gui selectedRow] == GUI_ROW_KC_KEY ? 0 : 1);
		[self setGuiToKeyConfigEntryScreen];
	}

	if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_SHIFT || [gui selectedRow] == (GUI_ROW_KC_SHIFT + 5)))
	{
		[self updateShiftKeyDefinition:@"shift" index:([gui selectedRow] == GUI_ROW_KC_SHIFT ? 0 : 1)];
		[self setGuiToKeyConfigScreen];
	}
	if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_MOD1 || [gui selectedRow] == (GUI_ROW_KC_MOD1 + 5)))
	{
		[self updateShiftKeyDefinition:@"mod1" index:([gui selectedRow] == GUI_ROW_KC_MOD1 ? 0 : 1)];
		[self setGuiToKeyConfigScreen];
	}
	if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_MOD2 || [gui selectedRow] == (GUI_ROW_KC_MOD2 + 5)))
	{
		[self updateShiftKeyDefinition:@"mod2" index:([gui selectedRow] == GUI_ROW_KC_MOD2 ? 0 : 1)];
		[self setGuiToKeyConfigScreen];
	}

	if (selectKeyPress && [gui selectedRow] == GUI_ROW_KC_SAVE)
	{
		[self saveKeySetting:[selected_entry objectForKey: KEY_KC_DEFINITION]];
		[self reloadPage];
	}

	if ((selectKeyPress && [gui selectedRow] == GUI_ROW_KC_CANCEL) || [gameView isDown:27])
	{
		// esc or Cancel was pressed - get out of here
		[self reloadPage];
	}
}


- (void) setGuiToKeyConfigEntryScreen
{
	GuiDisplayGen *gui = [UNIVERSE gui];
	MyOpenGLView *gameView = [UNIVERSE gameView];
	OOGUIScreenID oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_KEYBOARD_ENTRY;
	BOOL guiChanged = (oldScreen != gui_screen);
	
	// make sure the index we're looking for exists
	if ([key_list count] < (key_index + 1))
	{
		// add the missing element to the array
		NSMutableDictionary *key1 = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"", @"key", [NSNumber numberWithBool:NO], @"shift", [NSNumber numberWithBool:NO], @"mod1", [NSNumber numberWithBool:NO], @"mod2", nil];
		[key_list addObject:key1];
		[key1 release];
	}
	NSDictionary *def = [key_list objectAtIndex:key_index];
	NSString *key = [def objectForKey:@"key"];
	//if ([key isEqualToString:@"(not set)"]) key = @"";
	OOKeyCode k_int = (OOKeyCode)[key integerValue];
	[gameView resetTypedString];
	[gameView setTypedString:(k_int != 0 ? [self keyCodeDescriptionShort:k_int] : @"")];
	[gameView setStringInput:gvStringInputAll];

	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"%@", DESC(@"oolite-keyconfig-update-entry-title")]];
	
	NSUInteger end_row = 21;
	if ([[self hud] allowBigGui]) 
	{
		end_row = 27;
	}

	[gui addLongText:DESC(@"oolite-keyconfig-update-entry-info") startingAtRow:GUI_ROW_KC_ENTRY_INFO align:GUI_ALIGN_LEFT];

	[gui setText:[NSString stringWithFormat:DESC(@"Key: %@"), [gameView typedString]] forRow:end_row align:GUI_ALIGN_LEFT];
	[gui setColor:[OOColor cyanColor] forRow:end_row];
	[gui setSelectableRange:NSMakeRange(0,0)];

	[gui setShowTextCursor:YES];
	[gui setCurrentRow:end_row];

	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"keyboardsettings"];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

	[gameView clearMouse];
	[gameView clearKeys];
	if (guiChanged) [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}


- (void) handleKeyConfigEntryKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView
{
	NSUInteger end_row = 21;
	if ([[self hud] allowBigGui]) 
	{
		end_row = 27;
	}

	[self handleGUIUpDownArrowKeys];
	if ([gameView lastKeyWasShifted]) last_shift = YES;

	[gui setText:
		[NSString stringWithFormat:DESC(@"Key: %@"), [gameView typedString]]
		  forRow: end_row];
	[gui setColor:[OOColor cyanColor] forRow:end_row];

	if ([self checkKeyPress:n_key_gui_select]) 
	{
		[gameView suppressKeysUntilKeyUp];
		// update function key
		[self updateKeyDefinition:[gameView typedString] index:key_index];
		[gameView clearKeys];	// try to stop key bounces
		[self setGuiToKeyConfigScreen:YES];
	}
	if ([gameView isDown:27]) // escape
	{
		[gameView suppressKeysUntilKeyUp];
		// don't update function key
		[self setGuiToKeyConfigScreen:YES];
	}
}

// updates the overridden definition of a key to a new keycode value
- (void) updateKeyDefinition:(NSString *)keystring index:(NSUInteger)index
{
	NSMutableDictionary *key_def = [[NSMutableDictionary alloc] initWithDictionary:(NSDictionary *)[key_list objectAtIndex:index] copyItems:YES];
	[key_def setObject:keystring forKey:@"key"];
	// auto=turn on shift if the entered key was shifted

	if (last_shift && [keystring length] == 1 && ![nav_keys containsObject:[selected_entry objectForKey: KEY_KC_DEFINITION]]) 
	{
		[key_def setObject:[NSNumber numberWithBool:YES] forKey:@"shift"];
	}
	if (!last_shift && [keystring length] == 1)
	{
		[key_def setObject:[NSNumber numberWithBool:NO] forKey:@"shift"];
	}
	last_shift = NO;
	if (index > [key_list count] - 1)
	{
		[key_list insertObject:key_def atIndex:index];
	}
	else 
	{
		[key_list replaceObjectAtIndex:index withObject:key_def];
	}
	[key_def release];
	NSArray *new_array = [self processKeyCode:key_list];
	[key_list release];
	key_list = [[NSMutableArray alloc] initWithArray:new_array copyItems:YES];
	[new_array release];
}


// changes the shift/ctrl/alt state of an overridden definition
- (void) updateShiftKeyDefinition:(NSString *)key index:(NSUInteger)index
{
	NSMutableDictionary *key_def = [[NSMutableDictionary alloc] initWithDictionary:(NSDictionary *)[key_list objectAtIndex:index] copyItems:YES];
	BOOL current = [[key_def objectForKey:key] boolValue];
	current = !current;
	[key_def setObject:[NSNumber numberWithBool:current] forKey:key];
	if (index > [key_list count] - 1)
	{
		[key_list insertObject:key_def atIndex:index];
	}
	else 
	{
		[key_list replaceObjectAtIndex:index withObject:key_def];
	}
	[key_def release];
}


- (void) setGuiToConfirmClearScreen
{
	GuiDisplayGen *gui=[UNIVERSE gui];
	OOGUIScreenID oldScreen = gui_screen;
	
	gui_screen = GUI_SCREEN_KEYBOARD_CONFIRMCLEAR;
	BOOL guiChanged = (oldScreen != gui_screen);
	
	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"%@", DESC(@"oolite-keyconfig-clear-overrides-title")]];
	
	[gui addLongText:[NSString stringWithFormat:@"%@", DESC(@"oolite-keyconfig-clear-overrides")]
								startingAtRow:GUI_ROW_KC_CONFIRMCLEAR align:GUI_ALIGN_LEFT];
	
	[gui setText:DESC(@"oolite-keyconfig-clear-yes") forRow: GUI_ROW_KC_CONFIRMCLEAR_YES align:GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_CONFIRMCLEAR_YES];
	
	[gui setText:DESC(@"oolite-keyconfig-clear-no") forRow:GUI_ROW_KC_CONFIRMCLEAR_NO align:GUI_ALIGN_CENTER];
	[gui setKey:GUI_KEY_OK forRow:GUI_ROW_KC_CONFIRMCLEAR_NO];
	
	[gui setSelectableRange:NSMakeRange(GUI_ROW_KC_CONFIRMCLEAR_YES, 2)];
	[gui setSelectedRow:GUI_ROW_KC_CONFIRMCLEAR_NO];

	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"keyboardsettings"];

	[[UNIVERSE gameView] clearMouse];
	[[UNIVERSE gameView] clearKeys];
	if (guiChanged) [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}


- (void) handleKeyMapperConfirmClearKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView
{
	[self handleGUIUpDownArrowKeys];

	BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select]||[gameView isDown:gvMouseDoubleClick]);
	if ([gameView isDown:gvMouseDoubleClick]) [gameView clearMouse];

	// Translation issue: we can't confidently use raw Y and N ascii as shortcuts. It's better to use the load-previous-commander keys.
	id valueYes = [[[UNIVERSE descriptions] oo_stringForKey:@"load-previous-commander-yes" defaultValue:@"y"] lowercaseString];
	id valueNo = [[[UNIVERSE descriptions] oo_stringForKey:@"load-previous-commander-no" defaultValue:@"n"] lowercaseString];
	unsigned char cYes, cNo;
	
	cYes = [valueYes characterAtIndex: 0] & 0x00ff;	// Use lower byte of unichar.
	cNo = [valueNo characterAtIndex: 0] & 0x00ff;	// Use lower byte of unichar.
	
	if ((selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_CONFIRMCLEAR_YES))||[gameView isDown:cYes]||[gameView isDown:cYes - 32])
	{
		[self deleteAllKeySettings];
		[gameView suppressKeysUntilKeyUp];
		[self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
	}
	
	if ((selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_CONFIRMCLEAR_NO))||[gameView isDown:27]||[gameView isDown:cNo]||[gameView isDown:cNo - 32])
	{
		// esc or NO was pressed - get out of here
		[gameView suppressKeysUntilKeyUp];
		[self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
	}
}


- (void) displayKeyFunctionList:(GuiDisplayGen *)gui skip:(NSUInteger)skip
{
	[gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_HEADING];
	[gui setArray:[NSArray arrayWithObjects:
				   @"Function", @"Assigned to", @"Overrides", nil]
		   forRow:GUI_ROW_KC_HEADING];

	NSDictionary *overrides = [self loadKeySettings];

	if(!keyFunctions)
	{
		keyFunctions = [[self keyFunctionList] retain];
	}

	NSUInteger i, n_functions = [keyFunctions count];
	NSInteger n_rows, start_row, previous = 0;
	NSString *validate = nil;

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
		
		for(i = 0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			NSDictionary *entry = [keyFunctions objectAtIndex:i + skip];
			if ([entry objectForKey:KEY_KC_HEADER]) {
				NSString *header = [entry objectForKey:KEY_KC_HEADER];
				[gui setArray:[NSArray arrayWithObjects:header, @"", @"", nil] forRow:i + start_row];
				[gui setColor:[OOColor cyanColor] forRow:i + start_row];
			}
			else
			{
				NSString *assignment = nil;
				NSString *override = nil;
				if (![self entryIsDictCustomEquip:entry])
				{
					// Find out what's assigned for this function currently.
					assignment = [PLAYER keyBindingDescription2:[entry objectForKey:KEY_KC_DEFINITION]];
					override = ([overrides objectForKey:[entry objectForKey:KEY_KC_DEFINITION]] ? @"Yes" : @""); // work out whether this assignment is overriding the setting in keyconfig2.plist
					validate = [self validateKey:[entry objectForKey:KEY_KC_DEFINITION] checkKeys:(NSArray *)[keyconfig2_settings objectForKey:[entry objectForKey:KEY_KC_DEFINITION]]];
				}
				else 
				{
					NSString *custom_keytype = [self getCustomEquipKeyDefType:[entry oo_stringForKey:KEY_KC_DEFINITION]];
					NSUInteger idx = [self getCustomEquipIndex:[entry oo_stringForKey:KEY_KC_DEFINITION]];
					assignment = [PLAYER getKeyBindingDescription:[[customEquipActivation objectAtIndex:idx] oo_arrayForKey:custom_keytype]];
					override = @"";
					validate = [self validateKey:[entry objectForKey:KEY_KC_DEFINITION] checkKeys:(NSArray *)[[customEquipActivation objectAtIndex:idx] oo_arrayForKey:custom_keytype]];
				}
				if (assignment == nil)
				{
					assignment = @"   -   ";
				}
				
				[gui setArray:[NSArray arrayWithObjects: 
								[entry objectForKey:KEY_KC_GUIDESC], assignment, override, nil]
					forRow:i + start_row];
				[gui setKey:[NSString stringWithFormat:@"Index:%ld", i + skip] forRow:i + start_row];
				if (validate) 
				{
					[gui setColor:[OOColor orangeColor] forRow:i + start_row];
				}
			}
		}
		if (i < n_functions - skip)
		{
			[gui setColor:[OOColor greenColor] forRow:start_row + i];
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:start_row + i];
			[gui setKey:[NSString stringWithFormat:@"More:%ld", n_rows + skip] forRow:start_row + i];
			i++;
		}
		
		[gui setSelectableRange:NSMakeRange(GUI_ROW_KC_SELECTKBD, (i + start_row - GUI_ROW_KC_FUNCSTART) + (GUI_ROW_KC_FUNCSTART - GUI_ROW_KC_SELECTKBD))];
	}
}


- (NSArray *)keyFunctionList
{
	NSMutableArray *funcList = [NSMutableArray array];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-screen-access")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_launch_ship") keyDef:@"key_launch_ship"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_options") keyDef:@"key_gui_screen_options"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_equipship") keyDef:@"key_gui_screen_equipship"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_interfaces") keyDef:@"key_gui_screen_interfaces"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_screen_status") keyDef:@"key_gui_screen_status"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_chart_screens") keyDef:@"key_gui_chart_screens"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_system_data") keyDef:@"key_gui_system_data"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_market") keyDef:@"key_gui_market"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-propulsion")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_roll_left") keyDef:@"key_roll_left"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_roll_right") keyDef:@"key_roll_right"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_pitch_forward") keyDef:@"key_pitch_forward"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_pitch_back") keyDef:@"key_pitch_back"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_yaw_left") keyDef:@"key_yaw_left"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_yaw_right") keyDef:@"key_yaw_right"]];

	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_increase_speed") keyDef:@"key_increase_speed"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_decrease_speed") keyDef:@"key_decrease_speed"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_inject_fuel") keyDef:@"key_inject_fuel"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_jumpdrive") keyDef:@"key_jumpdrive"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_hyperspace") keyDef:@"key_hyperspace"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_galactic_hyperspace") keyDef:@"key_galactic_hyperspace"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-navigation")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_next_compass_mode") keyDef:@"key_next_compass_mode"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_prev_compass_mode") keyDef:@"key_prev_compass_mode"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_scanner_zoom") keyDef:@"key_scanner_zoom"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_scanner_unzoom") keyDef:@"key_scanner_unzoom"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_forward") keyDef:@"key_view_forward"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_aft") keyDef:@"key_view_aft"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_port") keyDef:@"key_view_port"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_view_starboard") keyDef:@"key_view_starboard"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_ident_system") keyDef:@"key_ident_system"]];

	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_docking_clearance_request") keyDef:@"key_docking_clearance_request"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_autopilot") keyDef:@"key_autopilot"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_autodock") keyDef:@"key_autodock"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_docking_music") keyDef:@"key_docking_music"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-offensive")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_weapons_online_toggle") keyDef:@"key_weapons_online_toggle"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_fire_lasers") keyDef:@"key_fire_lasers"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_launch_missile") keyDef:@"key_launch_missile"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_target_missile") keyDef:@"key_target_missile"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_untarget_missile") keyDef:@"key_untarget_missile"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_target_incoming_missile") keyDef:@"key_target_incoming_missile"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_next_missile") keyDef:@"key_next_missile"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_next_target") keyDef:@"key_next_target"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_previous_target") keyDef:@"key_previous_target"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-defensive")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_ecm") keyDef:@"key_ecm"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dump_cargo") keyDef:@"key_dump_cargo"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_rotate_cargo") keyDef:@"key_rotate_cargo"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_launch_escapepod") keyDef:@"key_launch_escapepod"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-special-equip")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_cycle_next_mfd") keyDef:@"key_cycle_next_mfd"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_cycle_previous_mfd") keyDef:@"key_cycle_previous_mfd"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_switch_next_mfd") keyDef:@"key_switch_next_mfd"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_switch_previous_mfd") keyDef:@"key_switch_previous_mfd"]];

	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_prime_next_equipment") keyDef:@"key_prime_next_equipment"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_prime_previous_equipment") keyDef:@"key_prime_previous_equipment"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_activate_equipment") keyDef:@"key_activate_equipment"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_mode_equipment") keyDef:@"key_mode_equipment"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_fastactivate_equipment_a") keyDef:@"key_fastactivate_equipment_a"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_fastactivate_equipment_b") keyDef:@"key_fastactivate_equipment_b"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-chart-screen")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_advanced_nav_array_next") keyDef:@"key_advanced_nav_array_next"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_advanced_nav_array_previous") keyDef:@"key_advanced_nav_array_previous"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_home") keyDef:@"key_map_home"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_end") keyDef:@"key_map_end"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_info") keyDef:@"key_map_info"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_zoom_in") keyDef:@"key_map_zoom_in"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_zoom_out") keyDef:@"key_map_zoom_out"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_next_system") keyDef:@"key_map_next_system"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_map_previous_system") keyDef:@"key_map_previous_system"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_chart_highlight") keyDef:@"key_chart_highlight"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-planet-info-screen")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_home") keyDef:@"key_system_home"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_end") keyDef:@"key_system_end"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_next_system") keyDef:@"key_system_next_system"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_system_previous_system") keyDef:@"key_system_previous_system"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-market-screen")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_filter_cycle") keyDef:@"key_market_filter_cycle"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_sorter_cycle") keyDef:@"key_market_sorter_cycle"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_buy_one") keyDef:@"key_market_buy_one"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_sell_one") keyDef:@"key_market_sell_one"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_buy_max") keyDef:@"key_market_buy_max"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_market_sell_max") keyDef:@"key_market_sell_max"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-misc")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_snapshot") keyDef:@"key_snapshot"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_pausebutton") keyDef:@"key_pausebutton"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_show_fps") keyDef:@"key_show_fps"]];
	//[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_bloom_toggle") keyDef:@"key_bloom_toggle"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_mouse_control_roll") keyDef:@"key_mouse_control_roll"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_mouse_control_yaw") keyDef:@"key_mouse_control_yaw"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_hud_toggle") keyDef:@"key_hud_toggle"]];
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_inc_field_of_view") keyDef:@"key_inc_field_of_view"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dec_field_of_view") keyDef:@"key_dec_field_of_view"]];
#endif
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_comms_log") keyDef:@"key_comms_log"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-custom-view")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view") keyDef:@"key_custom_view"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_zoom_in") keyDef:@"key_custom_view_zoom_in"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_zoom_out") keyDef:@"key_custom_view_zoom_out"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_roll_left") keyDef:@"key_custom_view_roll_left"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_roll_right") keyDef:@"key_custom_view_roll_right"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_left") keyDef:@"key_custom_view_pan_left"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_right") keyDef:@"key_custom_view_pan_right"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_up") keyDef:@"key_custom_view_pan_up"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_pan_down") keyDef:@"key_custom_view_pan_down"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_left") keyDef:@"key_custom_view_rotate_left"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_right") keyDef:@"key_custom_view_rotate_right"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_up") keyDef:@"key_custom_view_rotate_up"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_custom_view_rotate_down") keyDef:@"key_custom_view_rotate_down"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-oxz-manager")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_oxzmanager_setfilter") keyDef:@"key_oxzmanager_setfilter"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_oxzmanager_showinfo") keyDef:@"key_oxzmanager_showinfo"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_oxzmanager_extract") keyDef:@"key_oxzmanager_extract"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-gui")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_left") keyDef:@"key_gui_arrow_left"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_right") keyDef:@"key_gui_arrow_right"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_up") keyDef:@"key_gui_arrow_up"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_arrow_down") keyDef:@"key_gui_arrow_down"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_page_down") keyDef:@"key_gui_page_down"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_page_up") keyDef:@"key_gui_page_up"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_gui_select") keyDef:@"key_gui_select"]];

	[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-debug")]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dump_target_state") keyDef:@"key_dump_target_state"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_dump_entity_list") keyDef:@"key_dump_entity_list"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_full") keyDef:@"key_debug_full"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_collision") keyDef:@"key_debug_collision"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_console_connect") keyDef:@"key_debug_console_connect"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_bounding_boxes") keyDef:@"key_debug_bounding_boxes"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_shaders") keyDef:@"key_debug_shaders"]];
	[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_debug_off") keyDef:@"key_debug_off"]];

	if ([customEquipActivation count] > 0) 
	{
		[funcList addObject:[self makeKeyGuiDictHeader:DESC(@"oolite-keydesc-header-oxp-equip")]];
		int i;
		for (i = 0; i < [customEquipActivation count]; i++)
		{
			[funcList addObject:[self makeKeyGuiDict:[NSString stringWithFormat: @"Activate '%@'", [[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPNAME]] 
				keyDef:[NSString stringWithFormat:@"activate_%@", [[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPKEY]]]];
			[funcList addObject:[self makeKeyGuiDict:[NSString stringWithFormat: @"Mode '%@'", [[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPNAME]] 
				keyDef:[NSString stringWithFormat:@"mode_%@", [[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPKEY]]]];
		}
	}
	return funcList;
}


- (NSDictionary *)makeKeyGuiDict:(NSString *)what keyDef:(NSString*)key_def
{
	NSMutableDictionary *guiDict = [NSMutableDictionary dictionary];
	if ([what length] > 50) what = [[what substringToIndex:48] stringByAppendingString:@"..."];
	[guiDict setObject:what forKey:KEY_KC_GUIDESC];
	[guiDict setObject:key_def forKey:KEY_KC_DEFINITION];
	return guiDict;
}


- (NSDictionary *)makeKeyGuiDictHeader:(NSString *)header
{
	NSMutableDictionary *guiDict = [NSMutableDictionary dictionary];
	[guiDict setObject:header forKey:KEY_KC_HEADER];
	[guiDict setObject:@"" forKey:KEY_KC_GUIDESC];
	[guiDict setObject:@"" forKey:KEY_KC_DEFINITION];
	return guiDict;
}


- (void) setGuiToKeyboardLayoutScreen:(unsigned)skip
{
	[self setGuiToKeyboardLayoutScreen:skip resetCurrentRow:NO];
}


- (void) setGuiToKeyboardLayoutScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow
{
	GuiDisplayGen *gui = [UNIVERSE gui];
	MyOpenGLView *gameView = [UNIVERSE gameView];
	OOGUIScreenID oldScreen = gui_screen;
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	[gui setTabStops:tabStop];

	gui_screen = GUI_SCREEN_KEYBOARD_LAYOUT;
	BOOL guiChanged = (oldScreen != gui_screen);

	[[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

	[gui clear];
	[gui setTitle:[NSString stringWithFormat:@"Select Keyboard Layout"]];

	[self displayKeyboardLayoutList:gui skip:skip];

	[gui setArray:[NSArray arrayWithObject:DESC(@"oolite-keyconfig-keyboard-info")] forRow:GUI_ROW_KC_INSTRUCT];

	[gui setSelectedRow:kbd_row];

	[gui setForegroundTextureKey:[self status] == STATUS_DOCKED ? @"docked_overlay" : @"paused_overlay"];
	[gui setBackgroundTextureKey:@"keyboardsettings"];

	[gameView clearMouse];
	[gameView clearKeys];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

	if (guiChanged) [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}


- (void) handleKeyboardLayoutEntryKeys:(GuiDisplayGen *)gui view:(MyOpenGLView *)gameView
{
	[self handleGUIUpDownArrowKeys];
	BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || [gameView isDown:gvMouseDoubleClick]);
	if ([gameView isDown:gvMouseDoubleClick])  [gameView clearMouse];

	NSString *key = [gui keyForRow: [gui selectedRow]];
	if (selectKeyPress)
	{
		if ([key hasPrefix:@"More:"])
		{
			int from_function = [[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];
			if (from_function < 0)  from_function = 0;

			current_row = GUI_ROW_KC_FUNCSTART;
			if (from_function == 0) current_row = GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1;
			[self setGuiToKeyboardLayoutScreen:from_function];
			if ([gameView isDown:gvMouseDoubleClick]) [gameView clearMouse];
			return;
		}

		// update the keyboard code
		NSUInteger idx =[[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];
		NSString *kbd = [[kbdLayouts objectAtIndex:idx] objectForKey:@"key"];
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setObject:kbd forKey:@"keyboard-code"];
		[self initKeyConfigSettings];
		[self initCheckingDictionary];

		[gameView clearKeys];	// try to stop key bounces
		[self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
	}
	if ([gameView isDown:27]) // escape - return without change
	{
		[gameView clearKeys];	// try to stop key bounces
		[self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
	}	
}


- (NSString *)keyboardDescription:(NSString *)kbd
{
	NSString *map = @"";
#if OOLITE_WINDOWS	
	map = @"keymappings_windows.plist";
#endif
#if OOLITE_LINUX
	map = @"keymappings_linux.plist";
#endif
#if OOLITE_MAC_OS_X
	map = @"keymappings_mac.plist";
#endif
	NSDictionary *kmap = [NSDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:map inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
	NSDictionary *sect = [kmap objectForKey:kbd];
	return [sect objectForKey:@"description"];
}


- (NSArray *)keyboardLayoutList
{
	NSString *map = @"";
#if OOLITE_WINDOWS	
	map = @"keymappings_windows.plist";
#endif
#if OOLITE_LINUX
	map = @"keymappings_linux.plist";
#endif
#if OOLITE_MAC_OS_X
	map = @"keymappings_mac.plist";
#endif
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *kbd = [defaults oo_stringForKey:@"keyboard-code" defaultValue:@"default"];

	NSDictionary *kmap = [NSDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:map inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
	NSMutableArray *kbdList = [NSMutableArray array];
	NSArray *keys = [kmap allKeys];
	NSUInteger i;
	NSDictionary *def = nil;

	for (i = 0; i < [keys count]; i++)
	{
		if (![[keys objectAtIndex:i] isEqualToString:@"default"])
		{
			[kbdList addObject:[[NSDictionary alloc] initWithObjectsAndKeys:[keys objectAtIndex:i], @"key", 
				[self keyboardDescription:[keys objectAtIndex:i]], @"description", 
				([[keys objectAtIndex:i] isEqualToString:kbd] ? @"Current" : @""), @"selected",
				nil]];
		}
		else 
		{
			// key the "default" item separate, so we can add it at the top of the list, rather than getting it sorted
			def = [[NSDictionary alloc] initWithObjectsAndKeys:[keys objectAtIndex:i], @"key", 
				[self keyboardDescription:[keys objectAtIndex:i]], @"description", 
				([[keys objectAtIndex:i] isEqualToString:kbd] ? @"Current" : @""), @"selected",
				nil];
		}
	}

	NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"description" ascending:YES];
	NSArray *sortDescriptors = [NSArray arrayWithObject:sortDescriptor];
	NSMutableArray *sorted = [NSMutableArray arrayWithArray:[kbdList sortedArrayUsingDescriptors:sortDescriptors]];
	[sorted insertObject:def atIndex:0];
	
	[sortDescriptor release];

	return sorted;
}


- (void) displayKeyboardLayoutList:(GuiDisplayGen *)gui skip:(NSUInteger)skip
{
	[gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_HEADING];
	[gui setArray:[NSArray arrayWithObjects:@"Keyboard layout", nil] forRow:GUI_ROW_KC_HEADING];

	if(!kbdLayouts)
	{
		kbdLayouts = [[self keyboardLayoutList] retain];
	}

	NSUInteger i, n_functions = [kbdLayouts count];
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
		
		for(i = 0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			NSDictionary *entry = [kbdLayouts objectAtIndex:i + skip];
			NSString *desc = [entry objectForKey:@"description"];
			NSString *selected = [entry objectForKey:@"selected"];
			[gui setArray:[NSArray arrayWithObjects:desc, selected, nil] forRow:i + start_row];
			[gui setKey:[NSString stringWithFormat:@"Index:%ld", i + skip] forRow:i + start_row];
		}
		if (i < n_functions - skip)
		{
			[gui setColor:[OOColor greenColor] forRow:start_row + i];
			[gui setArray:[NSArray arrayWithObjects:DESC(@"gui-more"), @" --> ", nil] forRow:start_row + i];
			[gui setKey:[NSString stringWithFormat:@"More:%ld", n_rows + skip] forRow:start_row + i];
			i++;
		}
		
		[gui setSelectableRange:NSMakeRange(GUI_ROW_KC_FUNCSTART, i + start_row - GUI_ROW_KC_FUNCSTART)];
	}
}



// return an array of all functions currently in conflict
- (NSArray *) validateAllKeys
{
	NSMutableArray *failed = [[NSMutableArray alloc] init];
	NSString *validate = nil;
	NSUInteger i;

	for (i = 0; i < [keyFunctions count]; i++)
	{
		NSDictionary *entry = [keyFunctions objectAtIndex:i];
		validate = [self validateKey:[entry objectForKey:KEY_KC_DEFINITION] checkKeys:(NSArray *)[keyconfig2_settings objectForKey:[entry objectForKey:KEY_KC_DEFINITION]]];
		if (validate) 
		{
			[failed addObject:validate];
		}
	}
	return [failed copy];
}


// validate a single key against any other key that might apply to it
- (NSString *) validateKey:(NSString *)key checkKeys:(NSArray *)check_keys
{
	NSString *result = nil;
	
	// need to group keys into validation groups
	NSArray *gui_keys = [NSArray arrayWithObjects:@"key_gui_arrow_left", @"key_gui_arrow_right", @"key_gui_arrow_up", @"key_gui_arrow_down", @"key_gui_page_up", 
		@"key_gui_page_down", @"key_gui_select", nil];

	if ([gui_keys containsObject:key]) 
	{
		result = [self searchArrayForMatch:gui_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *debug_keys = [NSArray arrayWithObjects:
		@"key_dump_target_state", @"key_dump_entity_list", @"key_debug_full", @"key_debug_collision", @"key_debug_console_connect", @"key_debug_bounding_boxes", 
		@"key_debug_shaders", @"key_debug_off", nil];

	if ([debug_keys containsObject:key]) 
	{
		result = [self searchArrayForMatch:debug_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *customview_keys = [NSArray arrayWithObjects:
		@"key_custom_view", @"key_custom_view_zoom_out", @"key_custom_view_zoom_in", @"key_custom_view_roll_left", @"key_custom_view_pan_left", 
		@"key_custom_view_roll_right", @"key_custom_view_pan_right", @"key_custom_view_rotate_up", @"key_custom_view_pan_up", @"key_custom_view_rotate_down", 
		@"key_custom_view_pan_down", @"key_custom_view_rotate_left", @"key_custom_view_rotate_right", nil];

	if ([customview_keys containsObject:key]) 
	{
		result = [self searchArrayForMatch:customview_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSMutableArray *inflight_keys = [NSMutableArray arrayWithObjects:
		@"key_roll_left", @"key_roll_right", @"key_pitch_forward", @"key_pitch_back", @"key_yaw_left", @"key_yaw_right", @"key_view_forward", @"key_view_aft", 
		@"key_view_port", @"key_view_starboard", @"key_increase_speed", @"key_decrease_speed", @"key_inject_fuel", @"key_fire_lasers", @"key_weapons_online_toggle", 
		@"key_launch_missile", @"key_next_missile", @"key_ecm", @"key_prime_next_equipment", @"key_prime_previous_equipment", @"key_activate_equipment", 
		@"key_mode_equipment", @"key_fastactivate_equipment_a", @"key_fastactivate_equipment_b", @"key_target_incoming_missile", @"key_target_missile", 
		@"key_untarget_missile", @"key_ident_system", @"key_scanner_zoom", @"key_scanner_unzoom", @"key_launch_escapepod", @"key_galactic_hyperspace", 
		@"key_hyperspace", @"key_jumpdrive", @"key_dump_cargo", @"key_rotate_cargo", @"key_autopilot", @"key_autodock", @"key_docking_clearance_request", 
		@"key_snapshot", @"key_cycle_next_mfd", @"key_cycle_previous_mfd", @"key_switch_next_mfd", @"key_switch_previous_mfd", 
		@"key_next_target", @"key_previous_target", @"key_comms_log", @"key_prev_compass_mode", @"key_next_compass_mode", @"key_custom_view", 
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		@"key_inc_field_of_view", @"key_dec_field_of_view", 
#endif
		@"key_pausebutton", @"key_dump_target_state", nil];
	
	if ([self entryIsCustomEquip:key]) {
		NSUInteger i;
		for (i = 0; i < [customEquipActivation count]; i++)
		{
			[inflight_keys addObject:[NSString stringWithFormat:@"activate_%@", [[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPKEY]]];
			[inflight_keys addObject:[NSString stringWithFormat:@"mode_%@", [[customEquipActivation objectAtIndex:i] oo_stringForKey:CUSTOMEQUIP_EQUIPKEY]]];
		}
	}

	if ([inflight_keys containsObject:key]) 
	{
		result = [self searchArrayForMatch:inflight_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *docking_keys = [NSArray arrayWithObjects:
		@"key_docking_music", @"key_autopilot", @"key_pausebutton", nil];

	if ([docking_keys containsObject:key]) 
	{
		result = [self searchArrayForMatch:docking_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *docked_keys = [
		[NSArray arrayWithObjects:@"key_launch_ship", @"key_gui_screen_options", @"key_gui_screen_equipship", @"key_gui_screen_interfaces", @"key_gui_screen_status", 
		@"key_gui_chart_screens", @"key_gui_system_data", @"key_gui_market", nil]
		arrayByAddingObjectsFromArray:gui_keys];

	if ([docked_keys containsObject:key])
	{
		result = [self searchArrayForMatch:docked_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *paused_keys = [[
		[NSArray arrayWithObjects:@"key_pausebutton", @"key_gui_screen_options", @"key_hud_toggle", @"key_show_fps", @"key_mouse_control_roll", 
		@"key_mouse_control_yaw", nil] 
		arrayByAddingObjectsFromArray:debug_keys]
		arrayByAddingObjectsFromArray:customview_keys];

	if ([paused_keys containsObject:key])
	{
		result = [self searchArrayForMatch:paused_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *chart_keys = [NSArray arrayWithObjects:
		@"key_advanced_nav_array_next", @"key_advanced_nav_array_previous", @"key_map_home", @"key_map_end", @"key_map_info", 
		@"key_map_zoom_in", @"key_map_zoom_out", @"key_map_next_system", @"key_map_previous_system", @"key_chart_highlight", 
		@"key_launch_ship", @"key_gui_screen_options", @"key_gui_screen_equipship", @"key_gui_screen_interfaces", @"key_gui_screen_status", 
		@"key_gui_chart_screens", @"key_gui_system_data", @"key_gui_market", nil];

	if ([chart_keys containsObject:key])
	{
		result = [self searchArrayForMatch:chart_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *sysinfo_keys = [NSArray arrayWithObjects:
		@"key_system_home", @"key_system_end", @"key_system_next_system", @"key_system_previous_system", 
		@"key_launch_ship", @"key_gui_screen_options", @"key_gui_screen_equipship", @"key_gui_screen_interfaces", @"key_gui_screen_status", 
		@"key_gui_chart_screens", @"key_gui_system_data", @"key_gui_market", nil];

	if ([sysinfo_keys containsObject:key])
	{
		result = [self searchArrayForMatch:sysinfo_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	NSArray *market_keys = [NSArray arrayWithObjects:
		@"key_market_filter_cycle", @"key_market_sorter_cycle", @"key_market_buy_one", @"key_market_sell_one", @"key_market_buy_max", 
		@"key_market_sell_max", @"key_launch_ship", @"key_gui_screen_options", @"key_gui_screen_equipship", @"key_gui_screen_interfaces", @"key_gui_screen_status", 
		@"key_gui_chart_screens", @"key_gui_system_data", @"key_gui_market", @"key_gui_arrow_up", @"key_gui_arrow_down", @"key_gui_page_up", 
		@"key_gui_page_down", @"key_gui_select", nil];
		
	if ([market_keys containsObject:key])
	{
		result = [self searchArrayForMatch:market_keys key:key checkKeys:check_keys];
		if (result) return result;
	}

	// if we get here, we should be good
	return nil;
}


// performs a search of all keys in the search_list, and for any key that isn't the one we've passed, check the 
// keys against the values we're passing in. if there's a hit, return the key found
- (NSString *) searchArrayForMatch:(NSArray *)search_list key:(NSString *)key checkKeys:(NSArray *)check_keys
{
	NSString *search = nil;
	NSUInteger i, j, k;
	for (i = 0; i < [search_list count]; i++)
	{
		search = (NSString*)[search_list objectAtIndex:i];
		// only check other key settings, not the one we've been passed
		if (![search isEqualToString:key])
		{
			// get the array from keyconfig2_settings
			// we need to compare all entries to each other to look for any match, as any match would indicate a conflict
			NSArray *current = nil;
			if (![self entryIsCustomEquip:search])
			{
				current = (NSArray *)[keyconfig2_settings objectForKey:search];
			}
			else 
			{
				NSUInteger idx = [self getCustomEquipIndex:search];
				NSString *keytype = [self getCustomEquipKeyDefType:search];
				current = (NSArray *)[[customEquipActivation objectAtIndex:idx] objectForKey:keytype];
			}
			for (j = 0; j < [current count]; j++) 
			{
				for (k = 0; k < [check_keys count]; k++)
				{
					if ([self compareKeyEntries:[current objectAtIndex:j] second:[check_keys objectAtIndex:k]]) return search;
				}
			}
		}
	}
	return nil;
}


// compares the currently stored key_list against the base default from keyconfig2.plist
- (BOOL) entryIsEqualToDefault:(NSString*)key
{
	NSArray *def = (NSArray *)[kdic_check objectForKey:key];
	NSUInteger i;

	if ([def count] != [key_list count]) return NO;
	for (i = 0; i < [key_list count]; i++)
	{
		NSDictionary *orig = (NSDictionary *)[def objectAtIndex:i];
		NSDictionary *entrd = (NSDictionary *)[key_list objectAtIndex:i];
		if (![self compareKeyEntries:orig second:entrd]) return NO;
	}
	return YES;
}


// compares two key dictionaries to see if they have the same settings
- (BOOL) compareKeyEntries:(NSDictionary*)first second:(NSDictionary*)second
{
	if ([(NSString *)[first objectForKey:@"key"] integerValue] == [(NSString *)[second objectForKey:@"key"] integerValue])
	{
		if ([[first objectForKey:@"shift"] boolValue] == [[second objectForKey:@"shift"] boolValue] &&
			[[first objectForKey:@"mod1"] boolValue] == [[second objectForKey:@"mod1"] boolValue] &&
			[[first objectForKey:@"mod2"] boolValue] == [[second objectForKey:@"mod2"] boolValue]) 
			return YES;
	}
	return NO;
}


// saves the currently store key_list to the defaults file and updates the global definition
- (void) saveKeySetting:(NSString*)key
{
	// check for a blank entry
	if ([key_list count] > 1 && [[(NSDictionary*)[key_list objectAtIndex:1] objectForKey:@"key"] integerValue] == 0) 
	{
		[key_list removeObjectAtIndex:1];
	}
	// make sure the primary and alternate keys are different
	if ([key_list count] > 1) {
		if ([self compareKeyEntries:[key_list objectAtIndex:0] second:[key_list objectAtIndex:1]])
		{
			[key_list removeObjectAtIndex:1];
		}
	}
	// see if we've set the key settings to blank - in which case, delete the override
	if ([[(NSDictionary*)[key_list objectAtIndex:0] objectForKey:@"key"] integerValue] == 0)
	{
		if ([key_list count] == 1 || ([key_list count] > 1 && [[(NSDictionary*)[key_list objectAtIndex:1] objectForKey:@"key"] isEqualToString:@""]))
		{
			[self deleteKeySetting:key];
			// reload settings
			[self initKeyConfigSettings];
			[self reloadPage];
			return;
		}
	}

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	if (![self entryIsCustomEquip:key])
	{
		// if we've got the same settings as the default, revert to the default
		if ([self entryIsEqualToDefault:key])
		{
			[self deleteKeySetting:key];
			// reload settings
			[self initKeyConfigSettings];
			[self reloadPage];
			return;
		}
		NSMutableDictionary *keyconf = [NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:KEYCONFIG_OVERRIDES]];
		[keyconf setObject:key_list forKey:key];
		[defaults setObject:keyconf forKey:KEYCONFIG_OVERRIDES];
	}
	else 
	{
		NSUInteger idx = [self getCustomEquipIndex:key];
		NSString *custkey = [self getCustomEquipKeyDefType:key];
		[[customEquipActivation objectAtIndex:idx] setObject:key_list forKey:custkey];
		[defaults setObject:customEquipActivation forKey:KEYCONFIG_CUSTOMEQUIP];
	}
	// reload settings
	[self initKeyConfigSettings];
	[self reloadPage];
}

// unsets the key setting in the overrides, and updates the global definition
- (void) unsetKeySetting:(NSString*)key
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if (![self entryIsCustomEquip:key])
	{
		NSMutableDictionary *keyconf = [NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:KEYCONFIG_OVERRIDES]];
		NSMutableArray *empty = [[NSMutableArray alloc] init];
		[keyconf setObject:empty forKey:key];
		[defaults setObject:keyconf forKey:KEYCONFIG_OVERRIDES];
		[empty release];
	}
	else 
	{
		NSString *custkey = [self getCustomEquipKeyDefType:key];
		[[customEquipActivation objectAtIndex:[self getCustomEquipIndex:key]] removeObjectForKey:custkey];
		[defaults setObject:customEquipActivation forKey:KEYCONFIG_CUSTOMEQUIP];
	}
	// reload settings
	[self initKeyConfigSettings];
}


// removes the key setting from the overrides, and updates the global definition
- (void) deleteKeySetting:(NSString*)key
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if (![self entryIsCustomEquip:key])
	{
		NSMutableDictionary *keyconf = [NSMutableDictionary dictionaryWithDictionary:[defaults objectForKey:KEYCONFIG_OVERRIDES]];
		[keyconf removeObjectForKey:key];
		[defaults setObject:keyconf forKey:KEYCONFIG_OVERRIDES];
	}
	else 
	{
		NSString *custkey = [self getCustomEquipKeyDefType:key];
		[[customEquipActivation objectAtIndex:[self getCustomEquipIndex:key]] removeObjectForKey:custkey];
		[defaults setObject:customEquipActivation forKey:KEYCONFIG_CUSTOMEQUIP];
	}
	// reload settings
	[self initKeyConfigSettings];
}


// removes all key settings from the overrides, and updates the global definition
- (void) deleteAllKeySettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:KEYCONFIG_OVERRIDES];
	if ([customEquipActivation count] > 0)
	{
		NSUInteger i;
		for (i = 0; i < [customEquipActivation count]; i++)
		{
			[[customEquipActivation objectAtIndex:i] removeObjectForKey:CUSTOMEQUIP_KEYACTIVATE];
			[[customEquipActivation objectAtIndex:i] removeObjectForKey:CUSTOMEQUIP_KEYMODE];
		}
		[defaults setObject:customEquipActivation forKey:KEYCONFIG_CUSTOMEQUIP];
	}
	// reload settings
	[self initKeyConfigSettings];
}


// returns all key settings from the overrides
- (NSDictionary *) loadKeySettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults objectForKey:KEYCONFIG_OVERRIDES];
}


// reloads the main page at the appropriate page
- (void) reloadPage
{
	// Update the GUI (this will refresh the function list).
	unsigned skip;
	if (selFunctionIdx < MAX_ROWS_KC_FUNCTIONS - 1)
	{
		skip = 0;
	}
	else
	{
		skip = ((selFunctionIdx - 1) / (MAX_ROWS_KC_FUNCTIONS - 2)) * (MAX_ROWS_KC_FUNCTIONS - 2) + 1;
	}
	
	[self setGuiToKeyMapperScreen:skip];
}

@end