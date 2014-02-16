/*

PlayerEntityControls.m

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

#import "PlayerEntityControls.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "PlayerEntitySound.h"
#import "PlayerEntityLoadSave.h"
#import "PlayerEntityStickMapper.h"
#import "PlayerEntityStickProfile.h"

#import "ShipEntityAI.h"
#import "StationEntity.h"
#import "Universe.h"
#import "OOSunEntity.h"
#import "OOPlanetEntity.h"
#import "GameController.h"
#import "AI.h"
#import "MyOpenGLView.h"
#import "OOSound.h"
#import "OOStringParsing.h"
#import "OOCollectionExtractors.h"
#import "OOOXZManager.h"
#import "OOStringExpander.h"
#import "ResourceManager.h"
#import "HeadUpDisplay.h"
#import "OOConstToString.h"
#import "OOConstToJSString.h"
#import "OOLoggingExtended.h"
#import "OOMusicController.h"
#import "OOTexture.h"
#import "OODebugFlags.h"

#import "OOJoystickManager.h"

#import "OOJSScript.h"
#import "OOEquipmentType.h"

#import "OODebugSupport.h"
#import "OODebugMonitor.h"


static BOOL				jump_pressed;
static BOOL				hyperspace_pressed;
static BOOL				galhyperspace_pressed;
static BOOL				pause_pressed;
static BOOL				prev_compass_mode_pressed;
static BOOL				next_compass_mode_pressed;
static BOOL				next_target_pressed;
static BOOL				previous_target_pressed;
static BOOL				prime_equipment_pressed;
static BOOL				activate_equipment_pressed;
static BOOL				mode_equipment_pressed;
static BOOL				fastactivate_a_pressed;
static BOOL				fastactivate_b_pressed;
static BOOL				next_missile_pressed;
static BOOL				fire_missile_pressed;
static BOOL				target_missile_pressed;
static BOOL				target_incoming_missile_pressed;
static BOOL				ident_pressed;
static BOOL				safety_pressed;
static BOOL				rotateCargo_pressed;
static BOOL				autopilot_key_pressed;
static BOOL				fast_autopilot_key_pressed;
static BOOL				docking_clearance_request_key_pressed;
#ifndef NDEBUG
static BOOL				dump_target_state_pressed;
static BOOL				dump_entity_list_pressed;
#endif
static BOOL				taking_snapshot;
static BOOL				hide_hud_pressed;
static BOOL				f_key_pressed;
static BOOL				m_key_pressed;
static BOOL				pling_pressed;
static BOOL				cursor_moving;
static BOOL				disc_operation_in_progress;
#if OO_RESOLUTION_OPTION
static BOOL				switching_resolution;
#endif
static BOOL				wait_for_key_up;
static BOOL				upDownKeyPressed;
static BOOL				leftRightKeyPressed;
static BOOL				musicModeKeyPressed;
static BOOL				volumeControlPressed;
#if OOLITE_SDL
static BOOL				gammaControlPressed;
#endif
static BOOL				shaderSelectKeyPressed;
static BOOL				selectPressed;
static BOOL				queryPressed;
static BOOL				spacePressed;
static BOOL				switching_chart_screens;
static BOOL				switching_status_screens;
//static BOOL				switching_market_screens;
static BOOL				switching_equipship_screens;
static BOOL				zoom_pressed;
static BOOL				customView_pressed;
static BOOL				weaponsOnlineToggle_pressed;
static BOOL				escapePodKey_pressed;
static BOOL				cycleMFD_pressed;
static BOOL				switchMFD_pressed;

static NSUInteger		searchStringLength;
static double			timeLastKeyPress;
//static OOGUIRow			oldSelection;
static int				saved_view_direction;
static double			saved_script_time;
static int				saved_gui_screen;
static OOWeaponFacing	saved_weapon_facing;
static int 				pressedArrow = 0;
static BOOL				mouse_x_axis_map_to_yaw = NO;
static NSTimeInterval	time_last_frame;


@interface PlayerEntity (OOControlsPrivate)

- (void) pollFlightControls:(double) delta_t;
- (void) pollFlightArrowKeyControls:(double) delta_t;
- (void) pollGuiArrowKeyControls:(double) delta_t;
- (void) handleGameOptionsScreenKeys;
- (void) pollApplicationControls;
- (void) pollCustomViewControls;
- (void) pollViewControls;
- (void) pollGuiScreenControls;
- (void) pollGuiScreenControlsWithFKeyAlias:(BOOL)fKeyAlias;
- (void) handleUndockControl;
- (void) pollGameOverControls:(double) delta_t;
- (void) pollAutopilotControls:(double) delta_t;
- (void) pollDockedControls:(double) delta_t;
- (void) pollDemoControls:(double) delta_t;
- (void) pollMissionInterruptControls;
- (void) handleMissionCallback;
- (void) setGuiToMissionEndScreen;
- (void) switchToThisView:(OOViewID)viewDirection;
- (void) switchToThisView:(OOViewID)viewDirection andProcessWeaponFacing:(BOOL)processWeaponFacing;
- (void) switchToThisView:(OOViewID)viewDirection fromView:(OOViewID)oldViewDirection andProcessWeaponFacing:(BOOL)processWeaponFacing justNotify:(BOOL)justNotify;

- (void) handleAutopilotOn:(BOOL)fastDocking;

// Handlers for individual controls
- (void) handleButtonIdent;
- (void) handleButtonTargetMissile;

@end


@implementation PlayerEntity (Controls)

- (void) initControls
{
	NSMutableDictionary	*kdic = [NSMutableDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keyconfig.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
	
	// pre-process kdic - replace any strings with an integer representing the ASCII value of the first character
	
	unsigned		i;
	NSArray			*keys = nil;
	id				key = nil, value = nil;
	int				iValue;
	unsigned char	keychar;
	NSString		*keystring = nil;
	
#if OOLITE_WINDOWS
	// override windows keyboard autoselect
	[[UNIVERSE gameView] setKeyboardTo:[kdic oo_stringForKey:@"windows_keymap" defaultValue:@"auto"]];
#endif

	keys = [kdic allKeys];
	for (i = 0; i < [keys count]; i++)
	{
		key = [keys objectAtIndex:i];
		value = [kdic objectForKey: key];
		iValue = [value intValue];
		
		//	for '0' '1' '2' '3' '4' '5' '6' '7' '8' '9' - we want to interpret those as strings - not numbers
		//	alphabetical characters and symbols will return an intValue of 0.
		
		if ([value isKindOfClass:[NSString class]] && (iValue < 10))
		{
			keystring = value;
			if ([keystring length] == 1 || (iValue == 0 && [keystring length] != 0))
			{
				keychar = [keystring characterAtIndex: 0] & 0x00ff; // uses lower byte of unichar
			}
			else if (iValue <= 0xFF)  keychar = iValue;
			else continue;
			
			[kdic setObject:[NSNumber numberWithUnsignedChar:keychar] forKey:key];
		}
	}

	// set default keys.
#define LOAD_KEY_SETTING(name, default)	name = [kdic oo_unsignedShortForKey:@#name defaultValue:default]; [kdic setObject:[NSNumber numberWithUnsignedChar:name] forKey:@#name]

#define LOAD_KEY_SETTING_ALIAS(name, oldname, default) name = [kdic oo_unsignedShortForKey:@#name defaultValue:[kdic oo_unsignedShortForKey:@#oldname defaultValue:default]]; [kdic setObject:[NSNumber numberWithUnsignedChar:name] forKey:@#name]

	
	LOAD_KEY_SETTING(key_roll_left,				gvArrowKeyLeft		);
	LOAD_KEY_SETTING(key_roll_right,			gvArrowKeyRight		);
	LOAD_KEY_SETTING(key_pitch_forward,			gvArrowKeyUp		);
	LOAD_KEY_SETTING(key_pitch_back,			gvArrowKeyDown		);
	LOAD_KEY_SETTING(key_yaw_left,				','			);
	LOAD_KEY_SETTING(key_yaw_right,				'.'			);

	LOAD_KEY_SETTING(key_view_forward,			'1'			);
	LOAD_KEY_SETTING(key_view_aft,				'2'			);
	LOAD_KEY_SETTING(key_view_port,				'3'			);
	LOAD_KEY_SETTING(key_view_starboard,		'4'			);

	LOAD_KEY_SETTING(key_gui_screen_status,		'5'			);
	LOAD_KEY_SETTING(key_gui_chart_screens,		'6'			);
	LOAD_KEY_SETTING(key_gui_system_data,		'7'			);
	LOAD_KEY_SETTING(key_gui_market,			'8'			);

	LOAD_KEY_SETTING(key_gui_arrow_left,		gvArrowKeyLeft		);
	LOAD_KEY_SETTING(key_gui_arrow_right,		gvArrowKeyRight		);
	LOAD_KEY_SETTING(key_gui_arrow_up,			gvArrowKeyUp		);
	LOAD_KEY_SETTING(key_gui_arrow_down,		gvArrowKeyDown		);
	
	LOAD_KEY_SETTING(key_increase_speed,		'w'			);
	LOAD_KEY_SETTING(key_decrease_speed,		's'			);
	LOAD_KEY_SETTING(key_inject_fuel,			'i'			);
	
	LOAD_KEY_SETTING(key_fire_lasers,			'a'			);
	LOAD_KEY_SETTING(key_weapons_online_toggle,	'_'			);
	LOAD_KEY_SETTING(key_launch_missile,		'm'			);
	LOAD_KEY_SETTING(key_next_missile,			'y'			);
	LOAD_KEY_SETTING(key_ecm,					'e'			);
	
	LOAD_KEY_SETTING(key_prime_equipment,		'N'			);
	LOAD_KEY_SETTING(key_activate_equipment,	'n'			);
	LOAD_KEY_SETTING(key_mode_equipment,		'b'			);
	LOAD_KEY_SETTING_ALIAS(key_fastactivate_equipment_a, key_cloaking_device,		'0'			);
	LOAD_KEY_SETTING_ALIAS(key_fastactivate_equipment_b, key_energy_bomb,			'\t'		);
	
	LOAD_KEY_SETTING(key_target_missile,		't'			);
	LOAD_KEY_SETTING(key_untarget_missile,		'u'			);
	LOAD_KEY_SETTING(key_target_incoming_missile,	'T'		);
	LOAD_KEY_SETTING(key_ident_system,			'r'			);
	
	LOAD_KEY_SETTING(key_scanner_zoom,			'z'			);
	LOAD_KEY_SETTING(key_scanner_unzoom,		'Z'			);
	
	LOAD_KEY_SETTING(key_launch_escapepod,		27	/* esc */ );
	
	LOAD_KEY_SETTING(key_galactic_hyperspace,	'g'			);
	LOAD_KEY_SETTING(key_hyperspace,			'h'			);
	LOAD_KEY_SETTING(key_jumpdrive,				'j'			);
	
	LOAD_KEY_SETTING(key_dump_cargo,			'd'			);
	LOAD_KEY_SETTING(key_rotate_cargo,			'R'			);
	
	LOAD_KEY_SETTING(key_autopilot,				'c'			);
	LOAD_KEY_SETTING(key_autodock,				'C'			);
	LOAD_KEY_SETTING(key_docking_clearance_request, 'L'		);
	
	LOAD_KEY_SETTING(key_snapshot,				'*'			);
	LOAD_KEY_SETTING(key_docking_music,			's'			);
	
	LOAD_KEY_SETTING(key_advanced_nav_array,	'^'			);
	LOAD_KEY_SETTING(key_map_home,				gvHomeKey	);
	LOAD_KEY_SETTING(key_map_info,				'i'			);
	
	LOAD_KEY_SETTING(key_pausebutton,			'p'			);
	LOAD_KEY_SETTING(key_show_fps,				'F'			);
	LOAD_KEY_SETTING(key_mouse_control,			'M'			);
	LOAD_KEY_SETTING(key_hud_toggle,			'o'			);
	
	LOAD_KEY_SETTING(key_comms_log,				'`'			);
	LOAD_KEY_SETTING(key_prev_compass_mode,		'|'			);
	LOAD_KEY_SETTING(key_next_compass_mode,		'\\'		);
	
	LOAD_KEY_SETTING_ALIAS(key_chart_highlight,	key_contract_info,	'\?'	);
	
	LOAD_KEY_SETTING(key_cycle_mfd,				';'			);
	LOAD_KEY_SETTING(key_switch_mfd,			':'			);

	LOAD_KEY_SETTING(key_next_target,			'+'			);
	LOAD_KEY_SETTING(key_previous_target,		'-'			);
	
	LOAD_KEY_SETTING(key_custom_view,			'v'			);
	
#ifndef NDEBUG
	LOAD_KEY_SETTING(key_dump_target_state,		'H'			);
#endif
	
	if (key_yaw_left == key_roll_left && key_yaw_left == ',')  key_yaw_left = 0;
	if (key_yaw_right == key_roll_right && key_yaw_right == '.')  key_yaw_right = 0;
	
	// other keys are SET and cannot be varied
	[keyconfig_settings release];
	keyconfig_settings = [[NSDictionary alloc] initWithDictionary:kdic];
	
	// Enable polling
	pollControls=YES;
}


- (void) pollControls:(double)delta_t
{
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	NSString *exceptionContext = @"setup";
	
	@try
	{
		if (gameView)
		{
			// poll the gameView keyboard things
			exceptionContext = @"pollApplicationControls";
			[self pollApplicationControls]; // quit command-f etc.
			switch ([self status])
			{
				case STATUS_WITCHSPACE_COUNTDOWN:
				case STATUS_IN_FLIGHT:
					exceptionContext = @"pollFlightControls";
					[self pollFlightControls:delta_t];
					break;
					
				case STATUS_DEAD:
					exceptionContext = @"pollGameOverControls";
					[self pollGameOverControls:delta_t];
					break;
					
				case STATUS_AUTOPILOT_ENGAGED:
					exceptionContext = @"pollAutopilotControls";
					[self pollAutopilotControls:delta_t];
					break;
					
				case STATUS_DOCKED:
					exceptionContext = @"pollDockedControls";
					[self pollDockedControls:delta_t];
					break;
					
				case STATUS_START_GAME:
					exceptionContext = @"pollDemoControls";
					[self pollDemoControls:delta_t];
					break;
					
				default:
					// don't poll extra controls at any other times.
					break;
			}
		}
	}
	@catch (NSException *exception)
	{
		OOLog(kOOLogException, @"***** Exception checking controls [%@]: %@ : %@", exceptionContext, [exception name], [exception reason]);
	}
}

// DJS + aegidian: Moved from the big switch/case block in pollGuiArrowKeyControls
- (BOOL) handleGUIUpDownArrowKeys
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	BOOL			result = NO;
	BOOL			arrow_up = [gameView isDown:key_gui_arrow_up];
	BOOL			arrow_down = [gameView isDown:key_gui_arrow_down];
	BOOL			mouse_click = [gameView isDown:gvMouseLeftButton];
	BOOL			mouse_dbl_click = [gameView isDown:gvMouseDoubleClick];
	
	if (arrow_down)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if ([gui setNextRow: +1])
			{
				result = YES;
			}
			else
			{
				if ([gui setFirstSelectableRow])  result = YES;
			}
			
			if (result && [gui selectableRange].length > 1)  [self playMenuNavigationDown];
			else  [self playMenuNavigationNot];
			
			timeLastKeyPress = script_time;
		}
	}
	
	if (arrow_up)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if ([gui setNextRow: -1])
			{
				result = YES;
			}
			else
			{
				if ([gui setLastSelectableRow])  result = YES;
			}
			
			if (result && [gui selectableRange].length > 1)  [self playMenuNavigationUp];
			else  [self playMenuNavigationNot];

			timeLastKeyPress = script_time;
		}
	}
	
	if (mouse_click)
	{
		if (!upDownKeyPressed)
		{
			int click_row = 0;
			if (UNIVERSE)
				click_row = UNIVERSE->cursor_row;
			if ([gui setSelectedRow:click_row])
			{
				result = YES;
			}
		}
	}
	if (mouse_dbl_click)
	{
		int click_row = 0;
		if (UNIVERSE)
			click_row = UNIVERSE->cursor_row;
		if ([gui setSelectedRow:click_row])
		{
			result = YES;
		}
		else
		{
			// if double-clicked on an unselectable row, clear the
			// state so it doesn't activate whatever was last
			// selected
			[gameView clearMouse];
		}
	}

	
	upDownKeyPressed = (arrow_up || arrow_down || mouse_click);
	
	return result;
}


- (void) targetNewSystem:(int) direction whileTyping:(BOOL) whileTyping
{
	target_system_seed = [[UNIVERSE gui] targetNextFoundSystem:direction];
	cursor_coordinates.x = target_system_seed.d;
	cursor_coordinates.y = target_system_seed.b;
	found_system_seed = target_system_seed;
	if (!whileTyping)
	{
		[self clearPlanetSearchString];
	}
	cursor_moving = YES;
}


- (void) clearPlanetSearchString
{
	[[UNIVERSE gameView] resetTypedString];
	if (planetSearchString)  [planetSearchString release];
	planetSearchString = nil;
}


- (void) targetNewSystem:(int) direction
{
	[self targetNewSystem:direction whileTyping:NO];
}


- (void) switchToMainView
{
	OOGUIScreenID oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_MAIN;
	if (showDemoShips)
	{
		[self setShowDemoShips: NO];
		[UNIVERSE removeDemoShips];
	}
	[(MyOpenGLView *)[UNIVERSE gameView] allowStringInput:NO];
	[UNIVERSE enterGUIViewModeWithMouseInteraction:NO];
	[self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}


- (void) noteSwitchToView:(OOViewID)toView fromView:(OOViewID)fromView
{
	[self switchToThisView:toView fromView:fromView andProcessWeaponFacing:NO justNotify:YES]; // no extra processing needed!
}



-(void) beginWitchspaceCountdown:(int)spin_time
{
	if ([self hasHyperspaceMotor]) 
	{
		if (spin_time == 0) 
		{
			witchspaceCountdown = hyperspaceMotorSpinTime;
		}
		else 
		{
			if (spin_time < 5) 
			{
				witchspaceCountdown = 5;
			} 
			else 
			{
				witchspaceCountdown = spin_time;
			}
		}
		[self setStatus:STATUS_WITCHSPACE_COUNTDOWN];
		[self playStandardHyperspace];
		// say it!
		[UNIVERSE clearPreviousMessage];
		[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"witch-to-@-in-f-seconds"), [UNIVERSE getSystemName:target_system_seed], witchspaceCountdown] forCount:1.0];
		[self doScriptEvent:OOJSID("playerStartedJumpCountdown")
					withArguments:[NSArray arrayWithObjects:@"standard", [NSNumber numberWithFloat:witchspaceCountdown], nil]];
		[UNIVERSE preloadPlanetTexturesForSystem:target_system_seed];
	}
}


-(void) beginWitchspaceCountdown
{
	if ([self hasHyperspaceMotor]) {
		[self beginWitchspaceCountdown:hyperspaceMotorSpinTime];
	}
}


-(void) cancelWitchspaceCountdown
{
	if ([self status] == STATUS_WITCHSPACE_COUNTDOWN) {
		[self setStatus:STATUS_IN_FLIGHT];
		[self playHyperspaceAborted];
	}
	// say it!
	[UNIVERSE clearPreviousMessage];
	[self doScriptEvent:OOJSID("playerCancelledJumpCountdown")];
}


@end


@implementation PlayerEntity (OOControlsPrivate)

- (void) pollApplicationControls
{
	if (!pollControls) return;
	
	NSString *exceptionContext = @"setup";
	
	// does fullscreen / quit / snapshot
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	GameController *gameController = [UNIVERSE gameController];
	
	@try
	{
	//  command-key controls
	#if !OOLITE_MAC_OS_X || !OOLITE_64_BIT	// On 64-bit Macs, these are handled by normal menu shortcuts.
		if ([gameController inFullScreenMode])
		{
			exceptionContext = @"command key controls";
			if ([gameView isCommandFDown])
			{
				[gameView clearCommandF];
				[gameController exitFullScreenMode];
				if (mouse_control_on)
				{
					[UNIVERSE addMessage:DESC(@"mouse-off") forCount:3.0];
					mouse_control_on = NO;
				}
			}
			
			if ([gameView isCommandQDown])
			{
				[gameController pauseFullScreenModeToPerform:@selector(exitAppCommandQ) onTarget:gameController];
			}
		}
	#endif
		
	#if OOLITE_WINDOWS
		if ( ([gameView isDown:'Q']) )
		{
			exceptionContext = @"windows - Q";
			[gameController exitAppWithContext:@"Q pressed [Windows]"];
			exit(0); // Force it
		}
	#endif
		
		// handle pressing Q or [esc] in error-handling mode
		if ([self status] == STATUS_HANDLING_ERROR)
		{
			exceptionContext = @"error handling mode";
			if ([gameView isDown:113]||[gameView isDown:81]||[gameView isDown:27])   // 'q' | 'Q' | esc
			{
				[gameController exitAppWithContext:@"Q or escape pressed in error handling mode"];
			}
		}
		
		if ([gameController isGamePaused])
		{
			// What's the status?
			switch ([self status])
			{
				case STATUS_WITCHSPACE_COUNTDOWN:
				case STATUS_IN_FLIGHT:
				case STATUS_AUTOPILOT_ENGAGED:
				case STATUS_DOCKED:
					// Pause is handled inside their pollControls, no need to unpause.
					break;
					
				default:
					{
						// In all other cases we can't handle pause. Unpause immediately.
						script_time = saved_script_time;
						[gameView allowStringInput:NO];
						if ([UNIVERSE pauseMessageVisible])
						{
							[UNIVERSE clearPreviousMessage];	// remove the 'paused' message.
						}
						[gameController setGamePaused:NO];
					}
					break;
			}
			
		}
		
		// snapshot
		const BOOL *joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
		if ([gameView isDown:key_snapshot] || joyButtonState[BUTTON_SNAPSHOT])   //  '*' key
		{
			exceptionContext = @"snapshot";
			if (!taking_snapshot)
			{
				taking_snapshot = YES;
				[gameView snapShot:nil]; // nil filename so that the program auto-names the snapshot
			}
		}
		else
		{
			taking_snapshot = NO;
		}
		
		// FPS display
		if ([gameView isDown:key_show_fps])   //  'F' key
		{
			exceptionContext = @"toggle FPS";
			if (!f_key_pressed)  [UNIVERSE setDisplayFPS:![UNIVERSE displayFPS]];
			f_key_pressed = YES;
		}
		else
		{
			f_key_pressed = NO;
		}
		
		// Mouse control
		BOOL allowMouseControl;
	#if OO_DEBUG
		allowMouseControl = YES;
	#else
		allowMouseControl = [gameController inFullScreenMode] ||
					[[NSUserDefaults standardUserDefaults] boolForKey:@"mouse-control-in-windowed-mode"];
	#endif
		
		if (allowMouseControl)
		{
			exceptionContext = @"mouse control";
			if ([gameView isDown:key_mouse_control])   //  'M' key
			{
				if (!m_key_pressed)
				{
					mouse_control_on = !mouse_control_on;
					if (mouse_control_on)
					{
						[UNIVERSE addMessage:DESC(@"mouse-on") forCount:3.0];
						/*	Ensure the keyboard pitch override (intended to lock
						 out the joystick if the player runs to the keyboard)
						 is reset */
					#if OOLITE_GNUSTEP
						[gameView resetMouse];
					#endif
						mouse_x_axis_map_to_yaw = [gameView isCtrlDown];
						keyboardRollOverride = mouse_x_axis_map_to_yaw;   // Getafix: set keyboardRollOverride to TRUE only if yaw is mapped to mouse x-axis
						keyboardPitchOverride = NO;
						keyboardYawOverride = !keyboardRollOverride;
					}
					else
					{
						[UNIVERSE addMessage:DESC(@"mouse-off") forCount:3.0];
					}
				}
				if (OOMouseInteractionModeIsFlightMode([gameController mouseInteractionMode]))
				{
					[gameController setMouseInteractionModeForFlight];
				}
				m_key_pressed = YES;
			}
			else
			{
				m_key_pressed = NO;
			}
		}
		else
		{
			if (mouse_control_on)
			{
				mouse_control_on = NO;
				[UNIVERSE addMessage:DESC(@"mouse-off") forCount:3.0];
				
				if (OOMouseInteractionModeIsFlightMode([gameController mouseInteractionMode]))
				{
					[gameController setMouseInteractionModeForFlight];
				}
			}
		}
		
		// HUD toggle
		if ([gameView isDown:key_hud_toggle] && [gameController isGamePaused])	// 'o' key while paused
		{
			exceptionContext = @"toggle HUD";
			if (!hide_hud_pressed)
			{
				HeadUpDisplay *theHUD = [self hud];
				[theHUD setHidden:![theHUD isHidden]];
			}
			hide_hud_pressed = YES;
		}
		else
		{
			hide_hud_pressed = NO;
		}
	}
	@catch (NSException *exception)
	{
		OOLog(kOOLogException, @"***** Exception in pollApplicationControls [%@]: %@ : %@", exceptionContext, [exception name], [exception reason]);
	}
}


- (void) pollFlightControls:(double)delta_t
{
	MyOpenGLView		*gameView = [UNIVERSE gameView];
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	NSString			*exceptionContext = @"setup";
	
	@try
	{
		exceptionContext = @"joystick handling";
		const BOOL *joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
		
		BOOL paused = [[UNIVERSE gameController] isGamePaused];
		double speed_delta = 5.0 * thrust;
		
		if (!paused && gui_screen == GUI_SCREEN_MISSION)
		{
			exceptionContext = @"mission screen";
			OOViewID view = VIEW_NONE;
			
			NSPoint			virtualView = NSZeroPoint;
			double			view_threshold = 0.5;
			
			if ([stickHandler joystickCount])
			{
				virtualView = [stickHandler viewAxis];
				if (virtualView.y == STICK_AXISUNASSIGNED)
					virtualView.y = 0.0;
				if (virtualView.x == STICK_AXISUNASSIGNED)
					virtualView.x = 0.0;
				if (fabs(virtualView.y) >= fabs(virtualView.x))
					virtualView.x = 0.0; // forward/aft takes precedence
				else
					virtualView.y = 0.0;
			}
		
			if (([gameView isDown:gvFunctionKey1] || [gameView isDown:key_view_forward]) || (virtualView.y < -view_threshold) || joyButtonState[BUTTON_VIEWFORWARD])
			{
				view = VIEW_FORWARD;
			}
			if (([gameView isDown:gvFunctionKey2])||([gameView isDown:key_view_aft])||(virtualView.y > view_threshold)||joyButtonState[BUTTON_VIEWAFT])
			{
				view = VIEW_AFT;
			}
			if (([gameView isDown:gvFunctionKey3])||([gameView isDown:key_view_port])||(virtualView.x < -view_threshold)||joyButtonState[BUTTON_VIEWPORT])
			{
				view = VIEW_PORT;
			}
			if (([gameView isDown:gvFunctionKey4])||([gameView isDown:key_view_starboard])||(virtualView.x > view_threshold)||joyButtonState[BUTTON_VIEWSTARBOARD])
			{
				view = VIEW_STARBOARD;
			}
			if (view == VIEW_NONE)
			{
				// still in mission screen, process the input.
				[self pollDemoControls: delta_t];
			}
			else
			{
				[[UNIVERSE gui] clearBackground];
				[self switchToThisView:view];
				if (_missionWithCallback)
				{
					[self doMissionCallback];
				}
				// notify older scripts, but do not trigger missionScreenOpportunity.
				[self doWorldEventUntilMissionScreen:OOJSID("missionScreenEnded")];
			}
		}
		else if (!paused)
		{
			exceptionContext = @"arrow keys";
			// arrow keys
			if ([UNIVERSE displayGUI])
				[self pollGuiArrowKeyControls:delta_t];
			else
				[self pollFlightArrowKeyControls:delta_t];
			
			//  view keys
			[self pollViewControls];
			
			if (OOMouseInteractionModeIsFlightMode([[UNIVERSE gameController] mouseInteractionMode]))
			{
				exceptionContext = @"afterburner";
				if ((joyButtonState[BUTTON_FUELINJECT] || [gameView isDown:key_inject_fuel]) &&
					[self hasFuelInjection] &&
					!hyperspeed_engaged)
				{
					if (fuel > 0 && !afterburner_engaged)
					{
						[UNIVERSE addMessage:DESC(@"fuel-inject-on") forCount:1.5];
						afterburner_engaged = YES;
						[self startAfterburnerSound];
					}
					else
					{
						if (fuel <= 0.0)
							[UNIVERSE addMessage:DESC(@"fuel-out") forCount:1.5];
					}
					afterburner_engaged = (fuel > 0);
				}
				else
					afterburner_engaged = NO;
				
				if ((!afterburner_engaged)&&(afterburnerSoundLooping))
					[self stopAfterburnerSound];
				
				exceptionContext = @"thrust";
				// DJS: Thrust can be an axis or a button. Axis takes precidence.
				double reqSpeed=[stickHandler getAxisState: AXIS_THRUST];
				// Updated DJS original code to fix BUG #17482 - (Getafix 2010/09/13)
				if (([gameView isDown:key_increase_speed] || joyButtonState[BUTTON_INCTHRUST])&&(flightSpeed < maxFlightSpeed)&&(!afterburner_engaged))
				{
					flightSpeed += speed_delta * delta_t;
				}
					
				// ** tgape ** - decrease obviously means no hyperspeed
				if (([gameView isDown:key_decrease_speed] || joyButtonState[BUTTON_DECTHRUST])&&(!afterburner_engaged))
				{
					flightSpeed -= speed_delta * delta_t;
						
					// ** tgape ** - decrease obviously means no hyperspeed
					hyperspeed_engaged = NO;
				}

				NSDictionary *functionForThrustAxis = [[stickHandler axisFunctions] oo_dictionaryForKey:[[NSNumber numberWithInt:AXIS_THRUST] stringValue]];
				if([stickHandler joystickCount] != 0 && functionForThrustAxis != nil)
				{
					if (flightSpeed < maxFlightSpeed * reqSpeed)
					{
						flightSpeed += speed_delta * delta_t;
					}
					if (flightSpeed > maxFlightSpeed * reqSpeed)
					{
						flightSpeed -= speed_delta * delta_t;
					}
				} // DJS: end joystick thrust axis (Getafix - End code update for fixing BUG #17482)
				
				if (!afterburner_engaged && ![self atHyperspeed] && !hyperspeed_engaged)
				{
					flightSpeed = OOClamp_0_max_f(flightSpeed, maxFlightSpeed);
				}
				
				exceptionContext = @"hyperspeed";
				//  hyperspeed controls
				if ([gameView isDown:key_jumpdrive] || joyButtonState[BUTTON_HYPERSPEED])		// 'j'
				{
					if (!jump_pressed)
					{
						if (!hyperspeed_engaged)
						{
							hyperspeed_locked = [self massLocked];
							hyperspeed_engaged = !hyperspeed_locked;
							if (hyperspeed_locked)
							{
								[self playJumpMassLocked];
								[UNIVERSE addMessage:DESC(@"jump-mass-locked") forCount:1.5];
							}
						}
						else
						{
							hyperspeed_engaged = NO;
						}
					}
					jump_pressed = YES;
				}
				else
				{
					jump_pressed = NO;
				}
				
				exceptionContext = @"shoot";
				//  shoot 'a'
				if ((([gameView isDown:key_fire_lasers])||((mouse_control_on)&&([gameView isDown:gvMouseLeftButton]))||joyButtonState[BUTTON_FIRE])&&(shot_time > weapon_reload_time))
				{
					if ([self fireMainWeapon])
					{
						[self playLaserHit:([self shipHitByLaser] != nil) offset:[self currentLaserOffset]];
					}
				}
				
				exceptionContext = @"weapons online toggle";
				// weapons online / offline toggle '_'
				if (([gameView isDown:key_weapons_online_toggle] || joyButtonState[BUTTON_WEAPONSONLINETOGGLE]))
				{
					if (!weaponsOnlineToggle_pressed)
					{
						NSString*	weaponsOnlineToggleMsg;
						
						[self setWeaponsOnline:![self weaponsOnline]];
						weaponsOnlineToggleMsg = [self weaponsOnline] ? DESC(@"weapons-systems-online") : DESC(@"weapons-systems-offline");
						if ([self weaponsOnline])
						{
							[self playWeaponsOnline];
						}
						else
						{
							[self playWeaponsOffline];
						}
						[UNIVERSE addMessage:weaponsOnlineToggleMsg forCount:2.0];
						weaponsOnlineToggle_pressed = YES;
					}
				}
				else  weaponsOnlineToggle_pressed = NO;
				
				exceptionContext = @"missile fire";
				//  shoot 'm'   // launch missile
				if ([gameView isDown:key_launch_missile] || joyButtonState[BUTTON_LAUNCHMISSILE])
				{
					// launch here
					if (!fire_missile_pressed)
					{
						[self fireMissile];
						fire_missile_pressed = YES;
					}
				}
				else  fire_missile_pressed = NO;
				
				exceptionContext = @"next missile";
				//  shoot 'y'   // next missile
				if ([gameView isDown:key_next_missile] || joyButtonState[BUTTON_CYCLEMISSILE])
				{
					if (!ident_engaged && !next_missile_pressed && [self weaponsOnline])
					{
						[self playNextMissileSelected];
						[self selectNextMissile];
					}
					next_missile_pressed = YES;
				}
				else  next_missile_pressed = NO;
				
				exceptionContext = @"next target";
				//	'+' // next target
				if ([gameView isDown:key_next_target] || joyButtonState[BUTTON_NEXTTARGET])
				{
					if ((!next_target_pressed)&&([self hasEquipmentItem:@"EQ_TARGET_MEMORY"]))
					{
						[self moveTargetMemoryBy:+1];
					}
					next_target_pressed = YES;
				}
				else  next_target_pressed = NO;
				
				exceptionContext = @"previous target";
				//	'-' // previous target
				if ([gameView isDown:key_previous_target] || joyButtonState[BUTTON_PREVTARGET])
				{
					if ((!previous_target_pressed)&&([self hasEquipmentItem:@"EQ_TARGET_MEMORY"]))
					{
						[self moveTargetMemoryBy:-1];
					}
					previous_target_pressed = YES;
				}
				else  previous_target_pressed = NO;
				
				exceptionContext = @"ident R";
				//  shoot 'r'   // switch on ident system
				if ([gameView isDown:key_ident_system] || joyButtonState[BUTTON_ID])
				{
					// ident 'on' here
					if (!ident_pressed)
					{
						[self handleButtonIdent];
					}
					ident_pressed = YES;
				}
				else  ident_pressed = NO;
				
				exceptionContext = @"prime equipment";
				// prime equipment 'N' - selects equipment to use with keypress
				if ([gameView isDown:key_prime_equipment] || joyButtonState[BUTTON_PRIMEEQUIPMENT])
				{

					if (!prime_equipment_pressed)
					{

						// cycle through all the relevant equipment.
						NSUInteger c = [eqScripts count];
						
						// if Ctrl is held down at the same time as the prime equipment key,
						// cycle relevant equipment in reverse
						if (![gameView isCtrlDown])
						{
							primedEquipment++;
							if (primedEquipment > c) primedEquipment = 0;
						}
						else
						{
							if (primedEquipment > 0)  primedEquipment--;
							else  primedEquipment = c;
						}
						
						if (primedEquipment == c)
						{
							if (c > 0)
							{
								[self playNextEquipmentSelected];
								[UNIVERSE addMessage:DESC(@"equipment-primed-none") forCount:2.0];
							}
							else [UNIVERSE addMessage:DESC(@"equipment-primed-none-available") forCount:2.0];
						}
						else
						{
							[self playNextEquipmentSelected];
							[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"equipment-primed-@"), [[OOEquipmentType equipmentTypeWithIdentifier:[[eqScripts oo_arrayAtIndex:primedEquipment] oo_stringAtIndex:0]] name]] forCount:2.0];
						}
					}
					prime_equipment_pressed = YES;
				}
				else  prime_equipment_pressed = NO;
				
				exceptionContext = @"activate equipment";
				// activate equipment 'n' - runs the activated() function inside the equipment's script.
				if ([gameView isDown:key_activate_equipment] || joyButtonState[BUTTON_ACTIVATEEQUIPMENT])
				{
					if (!activate_equipment_pressed)
					{
						[self activatePrimableEquipment:primedEquipment withMode:OOPRIMEDEQUIP_ACTIVATED];
					}
					activate_equipment_pressed = YES;
				}
				else  activate_equipment_pressed = NO;
				
				exceptionContext = @"mode equipment";
				// mode equipment 'b' - runs the mode() function inside the equipment's script.
				if ([gameView isDown:key_mode_equipment] || joyButtonState[BUTTON_MODEEQUIPMENT])
				{
					if (!mode_equipment_pressed)
					{
						[self activatePrimableEquipment:primedEquipment withMode:OOPRIMEDEQUIP_MODE];
					}
					mode_equipment_pressed = YES;
				}
				else  mode_equipment_pressed = NO;

				exceptionContext = @"fast equipment A";
				if ([gameView isDown:key_fastactivate_equipment_a] || joyButtonState[BUTTON_CLOAK])
				{
					if (!fastactivate_a_pressed)
					{
						[self activatePrimableEquipment:[self eqScriptIndexForKey:[self fastEquipmentA]] withMode:OOPRIMEDEQUIP_ACTIVATED];
					}
					fastactivate_a_pressed = YES;
				}
				else fastactivate_a_pressed = NO;

				exceptionContext = @"fast equipment B";
				if ([gameView isDown:key_fastactivate_equipment_b] || joyButtonState[BUTTON_ENERGYBOMB])
				{
					if (!fastactivate_b_pressed)
					{
						[self activatePrimableEquipment:[self eqScriptIndexForKey:[self fastEquipmentB]] withMode:OOPRIMEDEQUIP_ACTIVATED];
					}
					fastactivate_b_pressed = YES;
				}
				else fastactivate_b_pressed = NO;


				exceptionContext = @"incoming missile T";
				// target nearest incoming missile 'T' - useful for quickly giving a missile target to turrets
				if ([gameView isDown:key_target_incoming_missile] || joyButtonState[BUTTON_TARGETINCOMINGMISSILE])
				{
					if (!target_incoming_missile_pressed)
					{
						[self targetNearestIncomingMissile];
					}
					target_incoming_missile_pressed = YES;
				}
				else  target_incoming_missile_pressed = NO;
				
				exceptionContext = @"missile T";
				//  shoot 't'   // switch on missile targeting
				if (([gameView isDown:key_target_missile] || joyButtonState[BUTTON_ARMMISSILE])&&(missile_entity[activeMissile]))
				{
					// targeting 'on' here
					if (!target_missile_pressed)
					{
						[self handleButtonTargetMissile];
					}
					target_missile_pressed = YES;
				}
				else  target_missile_pressed = NO;
				
				exceptionContext = @"missile U";
				//  shoot 'u'   // disarm missile targeting
				if ([gameView isDown:key_untarget_missile] || joyButtonState[BUTTON_UNARM])
				{
					if (!safety_pressed)
					{
						//targeting off in both cases!
						if ([self primaryTarget] != nil) [self noteLostTarget];
						DESTROY(_primaryTarget);
						[self safeAllMissiles];
						if (!ident_engaged && [self weaponsOnline])
						{
							[UNIVERSE addMessage:DESC(@"missile-safe") forCount:2.0];
							[self playMissileSafe];
						}
						else
						{
							[UNIVERSE addMessage:DESC(@"ident-off") forCount:2.0];
							[self playIdentOff];
						}
						ident_engaged = NO;
					}
					safety_pressed = YES;
				}
				else  safety_pressed = NO;
				
				exceptionContext = @"ECM";
				//  shoot 'e'   // ECM
				if (([gameView isDown:key_ecm] || joyButtonState[BUTTON_ECM]) && [self hasECM])
				{
					if (!ecm_in_operation)
					{
						if ([self fireECM])
						{
							[self playFiredECMSound];
							[UNIVERSE addMessage:DESC(@"ecm-on") forCount:3.0];
						}
					}
				}
				
			
				exceptionContext = @"escape pod";
				//  shoot 'escape'   // Escape pod launch - NOTE: Allowed at all times, but requires double press within a specific time interval.
							// Double press not available in strict mode or when the "escape-pod-activation-immediate" override is in the 
							// user defaults file.
				if (([gameView isDown:key_launch_escapepod] || joyButtonState[BUTTON_ESCAPE]) && [self hasEscapePod])
				{
					BOOL	goodToLaunch = [[NSUserDefaults standardUserDefaults] boolForKey:@"escape-pod-activation-immediate"];
					static	OOTimeDelta 	escapePodKeyResetTime;
					
					if (!goodToLaunch)
					{
						if (!escapePodKey_pressed)
						{
							escapePodKey_pressed = YES;
							// first keypress will unregister in KEY_REPEAT_INTERVAL seconds
							escapePodKeyResetTime = [NSDate timeIntervalSinceReferenceDate] + KEY_REPEAT_INTERVAL;
							[gameView clearKey:key_launch_escapepod];
							if ([stickHandler joystickCount])
							{
								[stickHandler clearStickButtonState:BUTTON_ESCAPE];
							}
						}
						else
						{
							OOTimeDelta timeNow = [NSDate timeIntervalSinceReferenceDate];
							escapePodKey_pressed = NO;
							if (timeNow < escapePodKeyResetTime)  goodToLaunch = YES;
						}
					}
					if (goodToLaunch)
					{
						[self launchEscapeCapsule];
					}
				}
				
				exceptionContext = @"dump cargo";
				//  shoot 'd'   // Dump Cargo
				if (([gameView isDown:key_dump_cargo] || joyButtonState[BUTTON_JETTISON]) && [cargo count] > 0)
				{
					[self dumpCargo];
				}
				
				exceptionContext = @"rotate cargo";
				//  shoot 'R'   // Rotate Cargo
				if ([gameView isDown:key_rotate_cargo])
				{
					if ((!rotateCargo_pressed)&&([cargo count] > 0))
						[self rotateCargo];
					rotateCargo_pressed = YES;
				}
				else
					rotateCargo_pressed = NO;
				
				exceptionContext = @"autopilot C";
				// autopilot 'c'
				if ([gameView isDown:key_autopilot] || joyButtonState[BUTTON_DOCKCPU])   // look for the 'c' key
				{
					if ([self hasDockingComputer] && (!autopilot_key_pressed))
					{
						[self handleAutopilotOn:false];
					}
					autopilot_key_pressed = YES;
				}
				else
					autopilot_key_pressed = NO;
				
				exceptionContext = @"autopilot shift-C";
				// autopilot 'C' - fast-autopilot
				if ([gameView isDown:key_autodock] || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'C' key
				{
					if ([self hasDockingComputer] && (!fast_autopilot_key_pressed))
					{
						[self handleAutopilotOn:true];
					}
					fast_autopilot_key_pressed = YES;
				}
				else
				{
					fast_autopilot_key_pressed = NO;
				}
				
				exceptionContext = @"docking clearance request";

				if ([gameView isDown:key_docking_clearance_request])
				{
					if (!docking_clearance_request_key_pressed)
					{
						Entity *primeTarget = [self primaryTarget];
						if (primeTarget != nil && [primeTarget isStation] && [primeTarget isKindOfClass:[StationEntity class]])
						{
							NSString *stationDockingClearanceStatus = [(StationEntity*)primeTarget acceptDockingClearanceRequestFrom:self];
							if (stationDockingClearanceStatus != nil)
							{
								[self doScriptEvent:OOJSID("playerRequestedDockingClearance") withArgument:stationDockingClearanceStatus];
							}
						}
					}
					docking_clearance_request_key_pressed = YES;
				}
				else
				{
					docking_clearance_request_key_pressed = NO;
				}
				
				exceptionContext = @"hyperspace";
				// hyperspace 'h'
				if ( ([gameView isDown:key_hyperspace] || joyButtonState[BUTTON_HYPERDRIVE]) &&
					  [self hasHyperspaceMotor] )	// look for the 'h' key
				{
					if (!hyperspace_pressed)
					{
						if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
						{
							[self cancelWitchspaceCountdown];
							if (galactic_witchjump)
							{
								galactic_witchjump = NO;
								[UNIVERSE addMessage:DESC(@"witch-user-galactic-abort") forCount:3.0];
							}
							else
							{
								[UNIVERSE addMessage:DESC(@"witch-user-abort") forCount:3.0];
							}
						}
						else if ([self witchJumpChecklist:false])
						{
							[self beginWitchspaceCountdown:hyperspaceMotorSpinTime];
						}
					}
					hyperspace_pressed = YES;
				}
				else
					hyperspace_pressed = NO;
				
				exceptionContext = @"galactic hyperspace";
				// Galactic hyperspace 'g'
				if (([gameView isDown:key_galactic_hyperspace] || joyButtonState[BUTTON_GALACTICDRIVE]) &&
					([self hasEquipmentItem:@"EQ_GAL_DRIVE"]))// look for the 'g' key
				{
					if (!galhyperspace_pressed)
					{
						if ([self status] == STATUS_WITCHSPACE_COUNTDOWN)
						{
							[self cancelWitchspaceCountdown];
							if (galactic_witchjump)
							{
								galactic_witchjump = NO;
								[UNIVERSE addMessage:DESC(@"witch-user-galactic-abort") forCount:3.0];
							}
							else
							{
								[UNIVERSE addMessage:DESC(@"witch-user-abort") forCount:3.0];
							}
						}
						else
						{
							galactic_witchjump = YES;
							
							// even if we don't have a witchspace motor, we can still do a default galactic jump (!)
							if(EXPECT([self hasHyperspaceMotor])) witchspaceCountdown = hyperspaceMotorSpinTime;
							else witchspaceCountdown = DEFAULT_HYPERSPACE_SPIN_TIME;
							
							[self setStatus:STATUS_WITCHSPACE_COUNTDOWN];
							[self playGalacticHyperspace];
							// say it!
							[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"witch-galactic-in-f-seconds"), witchspaceCountdown] forCount:1.0];
							// FIXME: how to preload target system for hyperspace jump?
							
							[self doScriptEvent:OOJSID("playerStartedJumpCountdown")
								  withArguments:[NSArray arrayWithObjects:@"galactic", [NSNumber numberWithFloat:witchspaceCountdown], nil]];
						}
					}
					galhyperspace_pressed = YES;
				}
				else
					galhyperspace_pressed = NO;


				exceptionContext = @"cycle mfds";
				// ';' // Cycle active MFD
				if ([gameView isDown:key_cycle_mfd])
				{
					if (!cycleMFD_pressed)
					{
						[self cycleMultiFunctionDisplay:activeMFD];
					}
					cycleMFD_pressed = YES;
				}
				else
				{
					cycleMFD_pressed = NO;
				}

				exceptionContext = @"switch mfds";
				//  ':' // Select next MFD
				if ([gameView isDown:key_switch_mfd])
				{
					if ([[self hud] mfdCount] > 1)
					{
						if (!switchMFD_pressed)
						{
							[self selectNextMultiFunctionDisplay];
						}
					}
					switchMFD_pressed = YES;
				}
				else
				{
					switchMFD_pressed = NO;
				}
				
			}
			
	#ifndef NDEBUG
			exceptionContext = @"dump target state";
			if ([gameView isDown:key_dump_target_state])
			{
				if (!dump_target_state_pressed)
				{
					dump_target_state_pressed = YES;
					id target = [self primaryTarget];
					if (target == nil)	target = self;
					[target dumpState];
				}
			}
			else  dump_target_state_pressed = NO;
	#endif
			
			//  text displays
			exceptionContext = @"pollGuiScreenControls";
			[self pollGuiScreenControls];
		}
		else
		{
			// game is paused
			
			// check options menu request
			exceptionContext = @"options menu";
			if (([gameView isDown:gvFunctionKey2] || [gameView isDown:key_view_aft]) && (gui_screen != GUI_SCREEN_OPTIONS))
			{
				[gameView clearKeys];
				[self setGuiToLoadSaveScreen];
			}
			
			#if (ALLOW_CUSTOM_VIEWS_WHILE_PAUSED)
			[self pollCustomViewControls];	// allow custom views during pause
			#endif
			
			if (gui_screen == GUI_SCREEN_OPTIONS || gui_screen == GUI_SCREEN_GAMEOPTIONS || gui_screen == GUI_SCREEN_STICKMAPPER || gui_screen == GUI_SCREEN_STICKPROFILE )
			{
				if ([UNIVERSE pauseMessageVisible]) [[UNIVERSE messageGUI] leaveLastLine];
				else [[UNIVERSE messageGUI] clear];
				NSTimeInterval	time_this_frame = [NSDate timeIntervalSinceReferenceDate];
				OOTimeDelta		time_delta;
				if (![[GameController sharedController] isGamePaused])
				{
					time_delta = time_this_frame - time_last_frame;
					time_last_frame = time_this_frame;
					time_delta = OOClamp_0_max_d(time_delta, MINIMUM_GAME_TICK);
				}
				else
				{
					time_delta = 0.0;
				}
				
				script_time += time_delta;
				[self pollGuiArrowKeyControls:time_delta];
			}
			
			exceptionContext = @"debug keys";
	#ifndef NDEBUG
			// look for debugging keys
			if ([gameView isDown:gvNumberKey0])// look for the '0' key
			{
				if (!dump_entity_list_pressed)
				{
					[UNIVERSE debugDumpEntities];
					gDebugFlags = 0;
					[UNIVERSE addMessage:@"Entity List dumped. Debugging OFF" forCount:3];
				}
				dump_entity_list_pressed = YES;
			}
			else
				dump_entity_list_pressed = NO;
			
			// look for debugging keys
			if ([gameView isDown:'d'])// look for the 'd' key
			{
				gDebugFlags = DEBUG_ALL;
				[UNIVERSE addMessage:@"Full debug ON" forCount:3];
			}
			
			if ([gameView isDown:'b'])// look for the 'b' key
			{
				gDebugFlags |= DEBUG_COLLISIONS;
				[UNIVERSE addMessage:@"Collision debug ON" forCount:3];
			}
			
			if ([gameView isDown:'c'] && ![[OODebugMonitor sharedDebugMonitor] usingPlugInController]) // look for the 'c' key
			{
				// This code is executed only if we're not using the integrated plugin controller
				if (!autopilot_key_pressed)
				{
					if (![[OODebugMonitor sharedDebugMonitor] debuggerConnected])
					{
						OOInitDebugSupport();
						if ([[OODebugMonitor sharedDebugMonitor] debuggerConnected])
							[UNIVERSE addMessage:@"Connected to debug console." forCount:3];
					}
					else
					{
						[[OODebugMonitor sharedDebugMonitor] setDebugger:nil];
						[UNIVERSE addMessage:@"Disconnected from debug console." forCount:3];
					}
				}
				autopilot_key_pressed = YES;
			}
			else
				autopilot_key_pressed = NO;
			
			if ([gameView isDown:'x'])// look for the 'x' key
			{
				gDebugFlags |= DEBUG_BOUNDING_BOXES;
				[UNIVERSE addMessage:@"Bounding box debug ON" forCount:3];
			}
			
			if ([gameView isDown:'s'])// look for the 's' key
			{
				OOLogSetDisplayMessagesInClass(@"$shaderDebugOn", YES);
				[UNIVERSE addMessage:@"Shader debug ON" forCount:3];
			}

			if (([gameView isDown:key_gui_arrow_left] || [gameView isDown:key_gui_arrow_right]) && gui_screen != GUI_SCREEN_GAMEOPTIONS && [UNIVERSE displayFPS])
			{
				if (!leftRightKeyPressed)
				{
					float newTimeAccelerationFactor = [gameView isDown:key_gui_arrow_left] ?
							fmax([UNIVERSE timeAccelerationFactor] / 2.0f, TIME_ACCELERATION_FACTOR_MIN) :
							fmin([UNIVERSE timeAccelerationFactor] * 2.0f, TIME_ACCELERATION_FACTOR_MAX);
					[UNIVERSE setTimeAccelerationFactor:newTimeAccelerationFactor];
				}
				leftRightKeyPressed = YES;
			}
			else
				leftRightKeyPressed = NO;
					
			
			if ([gameView isDown:'n'])// look for the 'n' key
			{
				gDebugFlags = 0;
				[UNIVERSE addMessage:@"All debug flags OFF" forCount:3];
				OOLogSetDisplayMessagesInClass(@"$shaderDebugOn", NO);
			}
	#endif
		}
		
		exceptionContext = @"pause";
		// Pause game 'p'
		if ([gameView isDown:key_pausebutton] && gui_screen != GUI_SCREEN_LONG_RANGE_CHART && gui_screen != GUI_SCREEN_MISSION)// look for the 'p' key
		{
			if (!pause_pressed)
			{
				if (paused)
				{
					script_time = saved_script_time;
					// Reset to correct GUI screen, if we are unpausing from one.
					// Don't set gui_screen here, use setGuis - they also switch backgrounds.
					// No gui switching events will be triggered while still paused.
					switch (saved_gui_screen)
					{
						case GUI_SCREEN_STATUS:
							[self setGuiToStatusScreen];
							break;
						case GUI_SCREEN_SHORT_RANGE_CHART:
							[self setGuiToShortRangeChartScreen];
							break;
						case GUI_SCREEN_MANIFEST:
							[self setGuiToManifestScreen];
							break;
						case GUI_SCREEN_MARKET:
							[self setGuiToMarketScreen];
							break;
						case GUI_SCREEN_SYSTEM_DATA:
							// Do not reset planet rotation if we are already in the system info screen!
							if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
								[self setGuiToSystemDataScreen];
							break;
						default:
							gui_screen = saved_gui_screen;	// make sure we're back to the right screen
							break;
					}
					[gameView allowStringInput:NO];
					[UNIVERSE clearPreviousMessage];
					[UNIVERSE setViewDirection:saved_view_direction];
					currentWeaponFacing = saved_weapon_facing;
					// make sure the light comes from the right direction after resuming from pause!
					if (saved_gui_screen == GUI_SCREEN_SYSTEM_DATA) [UNIVERSE setMainLightPosition:_sysInfoLight];
					[[UNIVERSE gui] setForegroundTextureKey:@"overlay"];
					[[UNIVERSE gameController] setGamePaused:NO];
				}
				else
				{
					saved_view_direction = [UNIVERSE viewDirection];
					saved_script_time = script_time;
					saved_gui_screen = gui_screen;
					saved_weapon_facing = currentWeaponFacing;
					[UNIVERSE pauseGame];	// pause handler
				}
			}
			pause_pressed = YES;
		}
		else
		{
			pause_pressed = NO;
		}
	}
	@catch (NSException *exception)
	{
		OOLog(kOOLogException, @"***** Exception in pollFlightControls [%@]: %@ : %@", exceptionContext, [exception name], [exception reason]);
	}
}


- (void) pollGuiArrowKeyControls:(double) delta_t
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	BOOL			moving = NO;
	double			cursor_speed = 10.0;
	GameController  *controller = [UNIVERSE gameController];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	GUI_ROW_INIT(gui);
	
	// deal with string inputs as necessary
	if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
	{
		[gameView setStringInput: gvStringInputAlpha];
	}
	else if (gui_screen == GUI_SCREEN_SAVE)
	{
		[gameView setStringInput: gvStringInputAll];
	}
	else if (gui_screen == GUI_SCREEN_MISSION && _missionTextEntry)
	{
		[gameView setStringInput: gvStringInputAll];
	}
	else
	{
		[gameView allowStringInput: NO];
	}
	
	switch (gui_screen)
	{
		case GUI_SCREEN_LONG_RANGE_CHART:
			if ([gameView isDown:key_advanced_nav_array])   //  '^' key
			{
				if (!pling_pressed)
				{
					if ([self hasEquipmentItem:@"EQ_ADVANCED_NAVIGATIONAL_ARRAY"])  [gui setShowAdvancedNavArray:YES];
					pling_pressed = YES;
				}
			}
			else
			{
				if (pling_pressed)
				{
					[gui setShowAdvancedNavArray:NO];
					pling_pressed = NO;
				}
			}

			if ([gameView isDown:key_chart_highlight])   // '?' toggle chart colours
			{
				if (!queryPressed)
				{
					OOLongRangeChartMode mode = [self longRangeChartMode];
					if (mode != OOLRC_MODE_TECHLEVEL)
					{
						[self setLongRangeChartMode:mode+1];
					}
					else
					{
						[self setLongRangeChartMode:OOLRC_MODE_NORMAL];
					}
				}
				queryPressed = YES;
			}
			else
			{
				queryPressed = NO;
			}

			if ([self status] != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if ([[gameView typedString] length] > 0)
				{
					planetSearchString = [[[gameView typedString] lowercaseString] retain];
					NSPoint search_coords = [UNIVERSE findSystemCoordinatesWithPrefix:planetSearchString];
					if ((search_coords.x >= 0.0)&&(search_coords.y >= 0.0))
					{
						// always reset the found system index at the beginning of a new search
						if ([planetSearchString length] == 1) [[UNIVERSE gui] targetNextFoundSystem:0];
						
						// Always select the right one out of 2 overlapping systems.
						[self targetNewSystem:0 whileTyping:YES];
					}
					else
					{
						found_system_seed = kNilRandomSeed;
						[self clearPlanetSearchString];
					}
				}
				else
				{
					if ([gameView isDown:gvDeleteKey]) // did we just delete the string ?
					{
						found_system_seed = kNilRandomSeed;
						[UNIVERSE findSystemCoordinatesWithPrefix:@""];
					}
					if (planetSearchString) [planetSearchString release];
					planetSearchString = nil;
				}
				
				moving |= (searchStringLength != [[gameView typedString] length]);
				searchStringLength = [[gameView typedString] length];
			}
		case GUI_SCREEN_SHORT_RANGE_CHART:
			
			show_info_flag = ([gameView isDown:key_map_info]);
			
			// If we have entered this screen with the injectors key pressed, make sure
			// that injectors switch off when we release it - Nikos.
			if (afterburner_engaged && ![gameView isDown:key_inject_fuel])
			{
				afterburner_engaged = NO;
			}
			
			if ([self status] != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if ([gameView isDown:gvMouseLeftButton])
				{
					NSPoint maus = [gameView virtualJoystickPosition];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)
					{
						double		vadjust = 51;
						double		hscale = MAIN_GUI_PIXEL_WIDTH / 64.0;
						double		vscale = MAIN_GUI_PIXEL_HEIGHT / 128.0;
						cursor_coordinates.x = galaxy_coordinates.x + (maus.x * MAIN_GUI_PIXEL_WIDTH) / hscale;
						cursor_coordinates.y = galaxy_coordinates.y + (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale;
					}
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
					{
						double		vadjust = 211;
						double		hadjust = MAIN_GUI_PIXEL_WIDTH / 2.0;
						double		hscale = MAIN_GUI_PIXEL_WIDTH / 256.0;
						double		vscale = MAIN_GUI_PIXEL_HEIGHT / 512.0;
						cursor_coordinates.x = (maus.x * MAIN_GUI_PIXEL_WIDTH + hadjust)/ hscale;
						cursor_coordinates.y = (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale;
					}
					[gameView resetTypedString];
					moving = YES;
				}
				if ([gameView isDown:gvMouseDoubleClick])
				{
					[gameView clearMouse];
					showingLongRangeChart = (gui_screen == GUI_SCREEN_LONG_RANGE_CHART);
					[self noteGUIWillChangeTo:GUI_SCREEN_SYSTEM_DATA];
					[self setGuiToSystemDataScreen];
				}
				if ([gameView isDown:key_map_home])
				{
					[gameView resetTypedString];
					cursor_coordinates = galaxy_coordinates;
					found_system_seed = kNilRandomSeed;
					[UNIVERSE findSystemCoordinatesWithPrefix:@""];
					moving = YES;
				}
				
				BOOL nextSystem = [gameView isShiftDown] && gui_screen == GUI_SCREEN_LONG_RANGE_CHART;
				
				if ([gameView isDown:key_gui_arrow_left])
				{
					if (nextSystem && pressedArrow != key_gui_arrow_left)
					{
						[self targetNewSystem:-1];
						pressedArrow = key_gui_arrow_left;
					}
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.x -= cursor_speed*delta_t;
						if (cursor_coordinates.x < 0.0) cursor_coordinates.x = 0.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == key_gui_arrow_left ? 0 : pressedArrow;
				
				if ([gameView isDown:key_gui_arrow_right])
				{
					if (nextSystem && pressedArrow != key_gui_arrow_right)
					{
						[self targetNewSystem:+1];
						pressedArrow = key_gui_arrow_right;
					}
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.x += cursor_speed*delta_t;
						if (cursor_coordinates.x > 256.0) cursor_coordinates.x = 256.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == key_gui_arrow_right ? 0 : pressedArrow;
				
				if ([gameView isDown:key_gui_arrow_down])
				{
					if (nextSystem && pressedArrow != key_gui_arrow_down)
					{
						[self targetNewSystem:+1];
						pressedArrow = key_gui_arrow_down;
					}
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.y += cursor_speed*delta_t*2.0;
						if (cursor_coordinates.y > 256.0) cursor_coordinates.y = 256.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == key_gui_arrow_down ? 0 : pressedArrow;
				
				if ([gameView isDown:key_gui_arrow_up])
				{
					if (nextSystem && pressedArrow != key_gui_arrow_up)
					{
						[self targetNewSystem:-1];
						pressedArrow = key_gui_arrow_up;
					}	
					else if (!nextSystem)
					{
						[gameView resetTypedString];
						cursor_coordinates.y -= cursor_speed*delta_t*2.0;
						if (cursor_coordinates.y < 0.0) cursor_coordinates.y = 0.0;
						moving = YES;
					}
				}
				else
					pressedArrow =  pressedArrow == key_gui_arrow_up ? 0 : pressedArrow;
				
				if ((cursor_moving)&&(!moving))
				{
					// if found with a search string, don't recalculate! Required for overlapping systems, like Divees & Tezabi in galaxy 5
					if (cursor_coordinates.x != found_system_seed.d && cursor_coordinates.y != found_system_seed.b)
							target_system_seed = [UNIVERSE findSystemAtCoords:cursor_coordinates withGalaxySeed:galaxy_seed];
					cursor_coordinates.x = target_system_seed.d;
					cursor_coordinates.y = target_system_seed.b;
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART) [self setGuiToLongRangeChartScreen];
					if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART) [self setGuiToShortRangeChartScreen];
				}
				cursor_moving = moving;
				if ((cursor_moving)&&(gui_screen == GUI_SCREEN_LONG_RANGE_CHART)) [self setGuiToLongRangeChartScreen]; // update graphics
				if ((cursor_moving)&&(gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)) [self setGuiToShortRangeChartScreen]; // update graphics
			}
			
		case GUI_SCREEN_SYSTEM_DATA:
			break;
			
#if OO_USE_CUSTOM_LOAD_SAVE
			// DJS: Farm off load/save screen options to LoadSave.m
		case GUI_SCREEN_LOAD:
		{
			NSString *commanderFile = [self commanderSelector];
			if(commanderFile)
			{
				// also release the demo ship here (see showShipyardModel and noteGUIDidChangeFrom)
				[demoShip release];
				demoShip = nil;
				
				[self loadPlayerFromFile:commanderFile asNew:NO];
			}
			break;
		}
			
		case GUI_SCREEN_SAVE:
			[self pollGuiScreenControlsWithFKeyAlias:NO];
			if ([gameView isDown:gvFunctionKey1] || [gameView isDown:key_view_forward])  [self handleUndockControl];
			if (gui_screen == GUI_SCREEN_SAVE)
			{
				[self saveCommanderInputHandler];
			}
			else pollControls = YES;
			break;
			
		case GUI_SCREEN_SAVE_OVERWRITE:
			[self overwriteCommanderInputHandler];
			break;
#endif
			
		case GUI_SCREEN_STICKMAPPER:
			[self stickMapperInputHandler: gui view: gameView];

			leftRightKeyPressed = [gameView isDown:key_gui_arrow_right] || [gameView isDown:key_gui_arrow_left];
			if (leftRightKeyPressed)
			{
				NSString *key = [gui keyForRow: [gui selectedRow]];
				if ([gameView isDown:key_gui_arrow_right])
				{
					key = [gui keyForRow:GUI_ROW_FUNCEND];
				}
				if ([gameView isDown:key_gui_arrow_left])
				{
					key = [gui keyForRow:GUI_ROW_FUNCSTART];
				}
				int from_function = 0;
				NSArray *keyComponents = [key componentsSeparatedByString:@":"];
				if ([keyComponents count] > 1)
				{
					from_function = [keyComponents oo_intAtIndex:1];
					if (from_function < 0)  from_function = 0;
					
					[self setGuiToStickMapperScreen:from_function];
					if ([[UNIVERSE gui] selectedRow] < GUI_ROW_FUNCSTART)
					{
						[[UNIVERSE gui] setSelectedRow: GUI_ROW_FUNCSTART];
					}
					if (from_function == 0)
					{
						[[UNIVERSE gui] setSelectedRow: GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1];
					}
				}
			}
			break;
		
		case GUI_SCREEN_STICKPROFILE:
			[self stickProfileInputHandler: gui view: gameView];
			break;
			
		case GUI_SCREEN_GAMEOPTIONS:
			[self handleGameOptionsScreenKeys];
			break;
			
		case GUI_SCREEN_OPTIONS:
			[self handleGUIUpDownArrowKeys];
			OOGUIRow guiSelectedRow = [gui selectedRow];
			BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
			
			if (selectKeyPress)   // 'enter'
			{
				if ((guiSelectedRow == GUI_ROW(,QUICKSAVE))&&(!disc_operation_in_progress))
				{
					@try
					{
						disc_operation_in_progress = YES;
						[self quicksavePlayer];
					}
					@catch (NSException *exception)
					{
						OOLog(kOOLogException, @"\n\n***** Handling exception: %@ : %@ *****\n\n",[exception name], [exception reason]);
						if ([[exception name] isEqual:@"GameNotSavedException"])	// try saving game instead
						{
							OOLog(kOOLogException, @"\n\n***** Trying a normal save instead *****\n\n");
							if ([controller inFullScreenMode])
								[controller pauseFullScreenModeToPerform:@selector(savePlayer) onTarget:self];
							else
								[self savePlayer];
						}
						else
						{
							@throw exception;
						}
					}
				}
				if ((guiSelectedRow == GUI_ROW(,SAVE))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					[self savePlayer];
				}
				if ((guiSelectedRow == GUI_ROW(,LOAD))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					if (![self loadPlayer])
					{
						disc_operation_in_progress = NO;
						[self setGuiToStatusScreen];
					}
				}
				
				
				if ((guiSelectedRow == GUI_ROW(,BEGIN_NEW))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					[UNIVERSE reinitAndShowDemo:YES];
				}
				
				if ([gameView isDown:gvMouseDoubleClick])
					[gameView clearMouse];
			}
			else
			{
				disc_operation_in_progress = NO;
			}
			
#if OOLITE_SDL
			// quit only appears in GNUstep as users aren't
			// used to Cmd-Q equivs. Same goes for window
			// vs fullscreen.
			if ((guiSelectedRow == GUI_ROW(,QUIT)) && selectKeyPress)
			{
				[[UNIVERSE gameController] exitAppWithContext:@"Exit Game selected on options screen"];
			}
#endif
			
			if ((guiSelectedRow == GUI_ROW(,GAMEOPTIONS)) && selectKeyPress)
			{
				[gameView clearKeys];
				[self setGuiToGameOptionsScreen];
			}
			
			break;
			
		case GUI_SCREEN_EQUIP_SHIP:
			if ([self handleGUIUpDownArrowKeys])
			{
				NSString		*itemText = [gui selectedRowText];
				OOWeaponType		weaponType = WEAPON_UNDEFINED;
				
				if ([itemText isEqual:FORWARD_FACING_STRING]) weaponType = forward_weapon_type;
				if ([itemText isEqual:AFT_FACING_STRING]) weaponType = aft_weapon_type;
				if ([itemText isEqual:PORT_FACING_STRING]) weaponType = port_weapon_type;
				if ([itemText isEqual:STARBOARD_FACING_STRING]) weaponType = starboard_weapon_type;
				
				if (weaponType != WEAPON_UNDEFINED)
				{
					BOOL		sameAs = OOWeaponTypeFromEquipmentIdentifierSloppy([gui selectedRowKey]) == weaponType;
					// override showInformation _completely_ with itemText
					if (weaponType == WEAPON_NONE)  itemText = DESC(@"no-weapon-enter-to-install");
					else
					{
						NSString *weaponName = [[OOEquipmentType equipmentTypeWithIdentifier:OOEquipmentIdentifierFromWeaponType(weaponType)] name];
						if (sameAs)  itemText = [NSString stringWithFormat:DESC(@"weapon-installed-@"), weaponName];
						else  itemText = [NSString stringWithFormat:DESC(@"weapon-@-enter-to-replace"), weaponName];
					}
					
					[self showInformationForSelectedUpgradeWithFormatString:itemText];
				}
				else
					[self showInformationForSelectedUpgrade];
			}
			
			if ([gameView isDown:key_gui_arrow_left])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START] hasPrefix:@"More:"])
					{
						[self playMenuPagePrevious];
						[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
						[self buySelectedItem];
					}
					timeLastKeyPress = script_time;
				}
			}
			if ([gameView isDown:key_gui_arrow_right])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1] hasPrefix:@"More:"])
					{
						[self playMenuPageNext];
						[gui setSelectedRow:GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1];
						[self buySelectedItem];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:key_gui_arrow_right]|[gameView isDown:key_gui_arrow_left];
			
			if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])   // 'enter'
			{
				if ([gameView isDown:gvMouseDoubleClick])
				{
					selectPressed = NO;
					[gameView clearMouse];
				}
				if ((!selectPressed)&&([gui selectedRow] > -1))
				{
					[self buySelectedItem];
					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}
			break;
			
		case GUI_SCREEN_INTERFACES:
			if ([self handleGUIUpDownArrowKeys])
			{
				[self showInformationForSelectedInterface];
			}
			if ([gameView isDown:key_gui_arrow_left])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_INTERFACES_START] hasPrefix:@"More:"])
					{
						[self playMenuPagePrevious];
						[gui setSelectedRow:GUI_ROW_INTERFACES_START];
						[self activateSelectedInterface];
					}
					timeLastKeyPress = script_time;
				}
			}
			if ([gameView isDown:key_gui_arrow_right])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1] hasPrefix:@"More:"])
					{
						[self playMenuPageNext];
						[gui setSelectedRow:GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1];
						[self activateSelectedInterface];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:key_gui_arrow_right]|[gameView isDown:key_gui_arrow_left];
			if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])   // 'enter'
			{
				if ([gameView isDown:gvMouseDoubleClick])
				{
					selectPressed = NO;
					[gameView clearMouse];
				}
				if ((!selectPressed)&&([gui selectedRow] > -1))
				{
					[self activateSelectedInterface];
					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}
			break;

		case GUI_SCREEN_MARKET:
			if ([self status] == STATUS_DOCKED)
			{
				[self handleGUIUpDownArrowKeys];
				
				if (([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left])||([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]))
				{
					if ([gameView isDown:key_gui_arrow_right])   // -->
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							if ([self tryBuyingCommodity:item all:[gameView isShiftDown]])
							{
								[self playBuyCommodity];
								[self setGuiToMarketScreen];
							}
							else
							{
								[self playCantBuyCommodity];
							}
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:key_gui_arrow_left])   // <--
					{
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							if ([self trySellingCommodity:item all:[gameView isShiftDown]])
							{
								[self playSellCommodity];
								[self setGuiToMarketScreen];
							}
							else
							{
								[self playCantSellCommodity];
							}
							wait_for_key_up = YES;
						}
					}
					if ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick])   // 'enter'
					{
						if ([gameView isDown:gvMouseDoubleClick])
						{
							wait_for_key_up = NO;
							[gameView clearMouse];
						}
						if (!wait_for_key_up)
						{
							int item = [(NSString *)[gui selectedRowKey] intValue];
							int yours =		[[shipCommodityData oo_arrayAtIndex:item] oo_intAtIndex:1];
							if ([gameView isShiftDown] && [self tryBuyingCommodity:item all:YES])	// buy as much as possible (with Shift)
							{
								[self playBuyCommodity];
								[self setGuiToMarketScreen];
							}
							else if ((yours > 0) && [self trySellingCommodity:item all:YES])	// sell all you can
							{
								[self playSellCommodity];
								[self setGuiToMarketScreen];
							}
							else if ([self tryBuyingCommodity:item all:YES])			// buy as much as possible
							{
								[self playBuyCommodity];
								[self setGuiToMarketScreen];
							}
							else
							{
								[self playCantBuyCommodity];
							}
							wait_for_key_up = YES;
						}
					}
				}
				else
				{
					wait_for_key_up = NO;
				}
			}
			break;
			
		case GUI_SCREEN_REPORT:
			if ([gameView isDown:32])	// spacebar
			{
				if (!spacePressed)
				{
					BOOL reportEnded = ([dockingReport length] == 0);
					[self playDismissedReportScreen];
					if(reportEnded)
					{
						[self setGuiToStatusScreen];
						[self doScriptEvent:OOJSID("reportScreenEnded")];  // last report given. Screen is now free for missionscreens.
						[self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")];
					}
					else
					{
						[self setGuiToDockingReportScreen];
					}

				}
				spacePressed = YES;
			}
			else
				spacePressed = NO;
			break;
		case GUI_SCREEN_STATUS:
			[self handleGUIUpDownArrowKeys];
			if ([gameView isDown:key_gui_arrow_left])
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:STATUS_EQUIPMENT_FIRST_ROW] isEqual:GUI_KEY_OK])
					{
						[gui setSelectedRow:STATUS_EQUIPMENT_FIRST_ROW];
						[self playMenuPagePrevious];
						[gui setStatusPage:-1];
						[self setGuiToStatusScreen];
					}
					timeLastKeyPress = script_time;
				}
			}
			if ([gameView isDown:key_gui_arrow_right])
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:STATUS_EQUIPMENT_FIRST_ROW + STATUS_EQUIPMENT_MAX_ROWS] isEqual:GUI_KEY_OK])
					{
						[gui setSelectedRow:STATUS_EQUIPMENT_FIRST_ROW + STATUS_EQUIPMENT_MAX_ROWS];
						[self playMenuPageNext];
						[gui setStatusPage:+1];
						[self setGuiToStatusScreen];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:key_gui_arrow_right]|[gameView isDown:key_gui_arrow_left];
			
			if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])   // 'enter'
			{
				if ([gameView isDown:gvMouseDoubleClick])
				{
					selectPressed = NO;
					[gameView clearMouse];
				}
				if ((!selectPressed)&&([gui selectedRow] > -1))
				{
					[gui setStatusPage:([gui selectedRow] == STATUS_EQUIPMENT_FIRST_ROW ? -1 : +1)];
					[self setGuiToStatusScreen];

					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}

			break;
		case GUI_SCREEN_MANIFEST:
			[self handleGUIUpDownArrowKeys];
			if ([gameView isDown:key_gui_arrow_left])
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:MANIFEST_SCREEN_ROW_BACK] isEqual:GUI_KEY_OK])
					{
						[gui setSelectedRow:MANIFEST_SCREEN_ROW_BACK];
						[self playMenuPagePrevious];
						[gui setStatusPage:-1];
						[self setGuiToManifestScreen];
					}
					timeLastKeyPress = script_time;
				}
			}
			if ([gameView isDown:key_gui_arrow_right])
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:MANIFEST_SCREEN_ROW_NEXT] isEqual:GUI_KEY_OK])
					{
						[gui setSelectedRow:MANIFEST_SCREEN_ROW_NEXT];
						[self playMenuPageNext];
						[gui setStatusPage:+1];
						[self setGuiToManifestScreen];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:key_gui_arrow_right]|[gameView isDown:key_gui_arrow_left];
			
			if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])   // 'enter'
			{
				if ([gameView isDown:gvMouseDoubleClick])
				{
					selectPressed = NO;
					[gameView clearMouse];
				}
				if ((!selectPressed)&&([gui selectedRow] > -1))
				{
					[gui setStatusPage:([gui selectedRow] == MANIFEST_SCREEN_ROW_BACK ? -1 : +1)];
					[self setGuiToManifestScreen];

					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}

			break;

		case GUI_SCREEN_SHIPYARD:
			if ([self handleGUIUpDownArrowKeys])
			{
				[self showShipyardInfoForSelection];
			}
			
			if ([gameView isDown:key_gui_arrow_left])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_SHIPYARD_START] hasPrefix:@"More:"])
					{
						[self playMenuPagePrevious];
						[gui setSelectedRow:GUI_ROW_SHIPYARD_START];
						[self buySelectedShip];
					}
					timeLastKeyPress = script_time;
				}
			}
			if ([gameView isDown:key_gui_arrow_right])
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ([[gui keyForRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1] hasPrefix:@"More:"])
					{
						[self playMenuPageNext];
						[gui setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
						[self buySelectedShip];
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = [gameView isDown:key_gui_arrow_right]|[gameView isDown:key_gui_arrow_left];
			
			if ([gameView isDown:13])   // 'enter' NOT double-click
			{
				if (!selectPressed)
				{
					// try to buy the ship!
					OOCreditsQuantity money = credits;
					if ([self buySelectedShip])
					{
						if (money != credits)	// money == credits means we skipped to another page, don't do anything
						{
							[UNIVERSE removeDemoShips];
							[self setGuiToStatusScreen];
							[self playBuyShip];
							[self doScriptEvent:OOJSID("playerBoughtNewShip") withArgument:self]; // some equipment.oxp might want to know everything has changed.
						}
					}
					else
					{
						[self playCantBuyShip];
					}
				}
				selectPressed = YES;
			}
			else
			{
				selectPressed = NO;
			}
			if ([gameView isDown:gvMouseDoubleClick])
			{
				if (([gui selectedRow] == GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1) && [[gui keyForRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1] hasPrefix:@"More:"])
				{
					[self playMenuPageNext];
					[gui setSelectedRow:GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1];
					[self buySelectedShip];
				}
				else if (([gui selectedRow] == GUI_ROW_SHIPYARD_START) && [[gui keyForRow:GUI_ROW_SHIPYARD_START] hasPrefix:@"More:"])
				{
					[self playMenuPagePrevious];
					[gui setSelectedRow:GUI_ROW_SHIPYARD_START];
					[self buySelectedShip];
				}
				[gameView clearMouse];
			}

			break;
			
		default:
			break;
	}
	
	// damp any rotations we entered with
	if (flightRoll > 0.0)
	{
		if (flightRoll > delta_t)		[self decrease_flight_roll:delta_t];
		else	flightRoll = 0.0;
	}
	if (flightRoll < 0.0)
	{
		if (flightRoll < -delta_t)		[self increase_flight_roll:delta_t];
		else	flightRoll = 0.0;
	}
	if (flightPitch > 0.0)
	{
		if (flightPitch > delta_t)		[self decrease_flight_pitch:delta_t];
		else	flightPitch = 0.0;
	}
	if (flightPitch < 0.0)
	{
		if (flightPitch < -delta_t)		[self increase_flight_pitch:delta_t];
		else	flightPitch = 0.0;
	}
	if (flightYaw > 0.0) 
	{ 
		if (flightYaw > delta_t)		[self decrease_flight_yaw:delta_t]; 
		else	flightYaw = 0.0; 
	} 
	if (flightYaw < 0.0) 
	{ 
		if (flightYaw < -delta_t)		[self increase_flight_yaw:delta_t]; 
		else	flightYaw = 0.0; 
	} 
}


- (void) handleGameOptionsScreenKeys
{
	MyOpenGLView		*gameView = [UNIVERSE gameView];
	GuiDisplayGen		*gui = [UNIVERSE gui];
	GUI_ROW_INIT(gui);
	
	[self handleGUIUpDownArrowKeys];
	OOGUIRow guiSelectedRow = [gui selectedRow];
	BOOL selectKeyPress = ([gameView isDown:13]||[gameView isDown:gvMouseDoubleClick]);
	if ([gameView isDown:gvMouseDoubleClick])  [gameView clearMouse];
	
	if ((guiSelectedRow == GUI_ROW(GAME,STICKMAPPER)) && selectKeyPress)
	{
		selFunctionIdx = 0;
		[self setGuiToStickMapperScreen: 0];
	}
	
#if OO_RESOLUTION_OPTION
	if (!switching_resolution &&
		guiSelectedRow == GUI_ROW(GAME,DISPLAY) &&
		([gameView isDown:key_gui_arrow_right] || [gameView isDown:key_gui_arrow_left]))
	{
		GameController	*controller = [UNIVERSE gameController];
		int				direction = ([gameView isDown:key_gui_arrow_right]) ? 1 : -1;
		NSInteger		displayModeIndex = [controller indexOfCurrentDisplayMode];
		NSArray			*modes = [controller displayModes];
		
		if (displayModeIndex == (NSInteger)NSNotFound)
		{
			OOLogWARN(@"graphics.mode.notFound", @"couldn't find current fullscreen setting, switching to default.");
			displayModeIndex = 0;
		}
		else
		{
			displayModeIndex = displayModeIndex + direction;
			int count = [modes count];
			if (displayModeIndex < 0)
				displayModeIndex = count - 1;
			if (displayModeIndex >= count)
				displayModeIndex = 0;
		}
		NSDictionary	*mode = [modes objectAtIndex:displayModeIndex];
		int modeWidth = [mode oo_intForKey:kOODisplayWidth];
		int modeHeight = [mode oo_intForKey:kOODisplayHeight];
		int modeRefresh = [mode oo_intForKey:kOODisplayRefreshRate];
		[controller setDisplayWidth:modeWidth Height:modeHeight Refresh:modeRefresh];

		NSString *displayModeString = [self screenModeStringForWidth:modeWidth height:modeHeight refreshRate:modeRefresh];
		
		[self playChangedOption];
		[gui setText:displayModeString	forRow:GUI_ROW(GAME,DISPLAY)  align:GUI_ALIGN_CENTER];
		switching_resolution = YES;
		
#if OOLITE_SDL
		/*	TODO: The gameView for the SDL game currently holds and
		 sets the actual screen resolution (controller just stores
		 it). This probably ought to change. */
		[gameView setScreenSize: displayModeIndex]; // changes fullscreen mode immediately
#endif
	}
	if (switching_resolution && ![gameView isDown:key_gui_arrow_right] && ![gameView isDown:key_gui_arrow_left] && !selectKeyPress)
	{
		switching_resolution = NO;
	}
#endif	// OO_RESOLUTION_OPTION
	
#if OOLITE_SPEECH_SYNTH
	if ((guiSelectedRow == GUI_ROW(GAME,SPEECH))&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:gvArrowKeyLeft])))
	{
		if ([gameView isDown:key_gui_arrow_right] != [self isSpeechOn])
			[self playChangedOption];
		isSpeechOn = [gameView isDown:key_gui_arrow_right];
		NSString *message = DESC(isSpeechOn ? @"gameoptions-spoken-messages-yes" : @"gameoptions-spoken-messages-no");
		[gui setText:message	forRow:GUI_ROW(GAME,SPEECH)  align:GUI_ALIGN_CENTER];
		if (isSpeechOn)
		{
			[UNIVERSE stopSpeaking];
			[UNIVERSE startSpeakingString:message];
		}
	}
#if OOLITE_ESPEAK
	if (guiSelectedRow == GUI_ROW(GAME,SPEECH_LANGUAGE))
	{
		if ([gameView isDown:key_gui_arrow_right] || [gameView isDown:key_gui_arrow_left])
		{
			if (!leftRightKeyPressed && script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL)
			{
				[self playChangedOption];
				if ([gameView isDown:key_gui_arrow_right])
					voice_no = [UNIVERSE nextVoice: voice_no];
				else
					voice_no = [UNIVERSE prevVoice: voice_no];
				[UNIVERSE setVoice: voice_no withGenderM:voice_gender_m];
				NSString *message = [NSString stringWithFormat:DESC(@"gameoptions-voice-@"), [UNIVERSE voiceName: voice_no]];
				[gui setText:message forRow:GUI_ROW(GAME,SPEECH_LANGUAGE) align:GUI_ALIGN_CENTER];
				if (isSpeechOn)
				{
					[UNIVERSE stopSpeaking];
					[UNIVERSE startSpeakingString:[UNIVERSE voiceName: voice_no]];
				}
			}
			leftRightKeyPressed = YES;
		}
		else
			leftRightKeyPressed = NO;
	}

	if (guiSelectedRow == GUI_ROW(GAME,SPEECH_GENDER))
	{
		if ([gameView isDown:key_gui_arrow_right] || [gameView isDown:key_gui_arrow_left])
		{
			if (!leftRightKeyPressed && script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL)
			{
				[self playChangedOption];
				BOOL m = [gameView isDown:key_gui_arrow_right];
				if (m != voice_gender_m)
				{
					voice_gender_m = m;
					[UNIVERSE setVoice:voice_no withGenderM:voice_gender_m];
					NSString *message = [NSString stringWithFormat:DESC(voice_gender_m ? @"gameoptions-voice-M" : @"gameoptions-voice-F")];
					[gui setText:message forRow:GUI_ROW(GAME,SPEECH_GENDER) align:GUI_ALIGN_CENTER];
					if (isSpeechOn)
					{
						[UNIVERSE stopSpeaking];
						[UNIVERSE startSpeakingString:[UNIVERSE voiceName: voice_no]];
					}
				}
			}
			leftRightKeyPressed = YES;
		}
		else
			leftRightKeyPressed = NO;
	}
#endif
#endif
	
	if ((guiSelectedRow == GUI_ROW(GAME,MUSIC))&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:gvArrowKeyLeft])))
	{
		if (!musicModeKeyPressed)
		{
			OOMusicController	*musicController = [OOMusicController sharedController];
			int					initialMode = [musicController mode];
			int					mode = initialMode;
			
			if ([gameView isDown:key_gui_arrow_right])  mode++;
			if ([gameView isDown:key_gui_arrow_left])  mode--;
			
			[musicController setMode:MAX(mode, 0)];
			
			if ((int)[musicController mode] != initialMode)
			{
				[self playChangedOption];
				NSString *message = [NSString stringWithFormat:DESC(@"gameoptions-music-mode-@"), [UNIVERSE descriptionForArrayKey:@"music-mode" index:mode]];
				[gui setText:message forRow:GUI_ROW(GAME,MUSIC)  align:GUI_ALIGN_CENTER];
			}
		}
		musicModeKeyPressed = YES;
	}
	else  musicModeKeyPressed = NO;
	
	if ((guiSelectedRow == GUI_ROW(GAME,AUTOSAVE))&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left])))
	{
		if ([gameView isDown:key_gui_arrow_right] != [UNIVERSE autoSave])
			[self playChangedOption];
		[UNIVERSE setAutoSave:[gameView isDown:key_gui_arrow_right]];
		if ([UNIVERSE autoSave])
		{
			// if just enabled, we want to autosave immediately
			[UNIVERSE setAutoSaveNow:YES];
			[gui setText:DESC(@"gameoptions-autosave-yes")	forRow:GUI_ROW(GAME,AUTOSAVE)  align:GUI_ALIGN_CENTER];
		}
		else
		{
			[UNIVERSE setAutoSaveNow:NO];
			[gui setText:DESC(@"gameoptions-autosave-no")	forRow:GUI_ROW(GAME,AUTOSAVE)  align:GUI_ALIGN_CENTER];
		}
	}

	if ((guiSelectedRow == GUI_ROW(GAME,VOLUME))
		&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left]))
		&&[OOSound respondsToSelector:@selector(masterVolume)])
	{
		if ((!volumeControlPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			BOOL rightKeyDown = [gameView isDown:key_gui_arrow_right];
			BOOL leftKeyDown = [gameView isDown:key_gui_arrow_left];
			double volume = 100.0 * [OOSound masterVolume];
			int vol = (volume / 5.0 + 0.5);
			if (rightKeyDown) vol++;
			if (leftKeyDown) vol--;
			vol = (int)OOClampInteger(vol, 0, 20);
			[OOSound setMasterVolume: 0.05 * vol];
			[self playChangedOption];
#if OOLITE_ESPEAK
			espeak_SetParameter(espeakVOLUME, vol * 5, 0);
#endif
			if (vol > 0)
			{
				NSString* soundVolumeWordDesc = DESC(@"gameoptions-sound-volume");
				NSString* v1_string = @"|||||||||||||||||||||||||";
				NSString* v0_string = @".........................";
				v1_string = [v1_string substringToIndex:vol];
				v0_string = [v0_string substringToIndex:20 - vol];
				[gui setText:[NSString stringWithFormat:@"%@%@%@ ", soundVolumeWordDesc, v1_string, v0_string]
					  forRow:GUI_ROW(GAME,VOLUME)
					   align:GUI_ALIGN_CENTER];
			}
			else
				[gui setText:DESC(@"gameoptions-sound-volume-mute")	forRow:GUI_ROW(GAME,VOLUME)  align:GUI_ALIGN_CENTER];
			timeLastKeyPress = script_time;
		}
		volumeControlPressed = YES;
	}
	else
		volumeControlPressed = NO;
		
#if OOLITE_SDL
	if ((guiSelectedRow == GUI_ROW(GAME,GAMMA))
		&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left])))
	{
		if (!gammaControlPressed)
		{
			BOOL rightKeyDown = [gameView isDown:key_gui_arrow_right];
			BOOL leftKeyDown = [gameView isDown:key_gui_arrow_left];
			float gamma = [gameView gammaValue];
			gamma += (((rightKeyDown && (gamma < 4.0f)) ? 0.2f : 0.0f) - ((leftKeyDown && (gamma > 0.2f)) ? 0.2f : 0.0f));
			if (gamma > 3.95f) gamma = 4.0f;
			if (gamma < 0.25f) gamma = 0.2f;
			[gameView setGammaValue:gamma];
			int gamma5 = gamma * 5;	// avoid rounding errors
			NSString* gammaWordDesc = DESC(@"gameoptions-gamma-value");
			NSString* v1_string = @"|||||||||||||||||||||||||";
			NSString* v0_string = @".........................";
			v1_string = [v1_string substringToIndex:gamma5];
			v0_string = [v0_string substringToIndex:20 - gamma5];
			[gui setText:[NSString stringWithFormat:@"%@%@%@ (%.1f) ", gammaWordDesc, v1_string, v0_string, gamma]	forRow:GUI_ROW(GAME,GAMMA)  align:GUI_ALIGN_CENTER];
		}
		gammaControlPressed = YES;
	}
	else
		gammaControlPressed = NO;
#endif
	
	if ((guiSelectedRow == GUI_ROW(GAME,WIREFRAMEGRAPHICS))&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left])))
	{
		if ([gameView isDown:key_gui_arrow_right] != [UNIVERSE wireframeGraphics])
			[self playChangedOption];
		[UNIVERSE setWireframeGraphics:[gameView isDown:key_gui_arrow_right]];
		if ([UNIVERSE wireframeGraphics])
			[gui setText:DESC(@"gameoptions-wireframe-graphics-yes")  forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS)  align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-wireframe-graphics-no")  forRow:GUI_ROW(GAME,WIREFRAMEGRAPHICS)  align:GUI_ALIGN_CENTER];
	}
	
	if ((guiSelectedRow == GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS))&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left])))
	{
		if ([gameView isDown:key_gui_arrow_right] != [UNIVERSE doProcedurallyTexturedPlanets])
		{
			[UNIVERSE setDoProcedurallyTexturedPlanets:[gameView isDown:key_gui_arrow_right]];
			[self playChangedOption];
			if ([UNIVERSE planet])
			{
				[UNIVERSE setUpPlanet];
			}
		}
		if ([UNIVERSE doProcedurallyTexturedPlanets])
			[gui setText:DESC(@"gameoptions-procedurally-textured-planets-yes")  forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS)  align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-procedurally-textured-planets-no")  forRow:GUI_ROW(GAME,PROCEDURALLYTEXTUREDPLANETS)  align:GUI_ALIGN_CENTER];
	}
	
	
	if (guiSelectedRow == GUI_ROW(GAME,SHADEREFFECTS) && ([gameView isDown:key_gui_arrow_right] || [gameView isDown:key_gui_arrow_left]))
	{
		if (!shaderSelectKeyPressed || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			int direction = ([gameView isDown:key_gui_arrow_right]) ? 1 : -1;
			OOGraphicsDetail detailLevel = [UNIVERSE detailLevel] + direction;
			[UNIVERSE setDetailLevel:detailLevel];
			detailLevel = [UNIVERSE detailLevel];
			
			NSString *shaderEffectsOptionsString = [NSString stringWithFormat:@"gameoptions-detaillevel-%d",detailLevel];
			[gui setText:OOExpandKey(shaderEffectsOptionsString) forRow:GUI_ROW(GAME,SHADEREFFECTS) align:GUI_ALIGN_CENTER];
			[gui setKey:GUI_KEY_OK forRow:GUI_ROW(GAME,SHADEREFFECTS)];

			timeLastKeyPress = script_time;
		}
		shaderSelectKeyPressed = YES;
	}
	else shaderSelectKeyPressed = NO;
	
#if OOLITE_SDL
	if ((guiSelectedRow == GUI_ROW(GAME,DISPLAYSTYLE)) && selectKeyPress)
	{
		[gameView toggleScreenMode];
		// redraw GUI
		[self setGuiToGameOptionsScreen];
	}
#endif

	if ((guiSelectedRow == GUI_ROW(GAME,DOCKINGCLEARANCE))&&(([gameView isDown:key_gui_arrow_right])||([gameView isDown:key_gui_arrow_left])))
	{
		if ([gameView isDown:key_gui_arrow_right] != [UNIVERSE dockingClearanceProtocolActive])
			[self playChangedOption];
		[UNIVERSE setDockingClearanceProtocolActive:[gameView isDown:key_gui_arrow_right]];
		if ([UNIVERSE dockingClearanceProtocolActive])
			[gui setText:DESC(@"gameoptions-docking-clearance-yes")  forRow:GUI_ROW(GAME,DOCKINGCLEARANCE)  align:GUI_ALIGN_CENTER];
		else
			[gui setText:DESC(@"gameoptions-docking-clearance-no")  forRow:GUI_ROW(GAME,DOCKINGCLEARANCE)  align:GUI_ALIGN_CENTER];
	}
	
	if ((guiSelectedRow == GUI_ROW(GAME,BACK)) && selectKeyPress)
	{
		[gameView clearKeys];
		[self setGuiToLoadSaveScreen];
	}
}


- (void) pollCustomViewControls
{
	if ([[UNIVERSE gameView] isDown:key_custom_view])
	{
		if (!customView_pressed && [_customViews count] != 0 && gui_screen != GUI_SCREEN_LONG_RANGE_CHART)
		{
			if ([UNIVERSE viewDirection] == VIEW_CUSTOM)	// already in custom view mode
			{
				// rotate the custom views
				_customViewIndex = (_customViewIndex + 1) % [_customViews count];
			}
	
			[self setCustomViewDataFromDictionary:[_customViews oo_dictionaryAtIndex:_customViewIndex]];
	
			[self switchToThisView:VIEW_CUSTOM andProcessWeaponFacing:NO]; // weapon facing must not change, we just want an external view
		}
		customView_pressed = YES;
	}
	else
		customView_pressed = NO;
}


- (void) pollViewControls
{
	if(!pollControls)
		return;
	
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	OOJoystickManager *stickHandler = [OOJoystickManager sharedStickHandler];
	
	NSPoint			virtualView = NSZeroPoint;
	double			view_threshold = 0.5;
	
	if ([stickHandler joystickCount])
	{
		virtualView = [stickHandler viewAxis];
		if (virtualView.y == STICK_AXISUNASSIGNED)
			virtualView.y = 0.0;
		if (virtualView.x == STICK_AXISUNASSIGNED)
			virtualView.x = 0.0;
		if (fabs(virtualView.y) >= fabs(virtualView.x))
			virtualView.x = 0.0; // forward/aft takes precedence
		else
			virtualView.y = 0.0;
	}
	
	const BOOL *joyButtonState = [stickHandler getAllButtonStates];
	
	//  view keys
	if (([gameView isDown:gvFunctionKey1] || [gameView isDown:key_view_forward]) || (virtualView.y < -view_threshold)||joyButtonState[BUTTON_VIEWFORWARD] || ((([gameView isDown:key_hyperspace] && gui_screen != GUI_SCREEN_LONG_RANGE_CHART) || joyButtonState[BUTTON_HYPERDRIVE]) && [UNIVERSE displayGUI]))
	{
		[self switchToThisView:VIEW_FORWARD];
	}
	if (([gameView isDown:gvFunctionKey2] || [gameView isDown:key_view_aft])||(virtualView.y > view_threshold)||joyButtonState[BUTTON_VIEWAFT])
	{
		[self switchToThisView:VIEW_AFT];
	}
	if (([gameView isDown:gvFunctionKey3] || [gameView isDown:key_view_port])||(virtualView.x < -view_threshold)||joyButtonState[BUTTON_VIEWPORT])
	{
		[self switchToThisView:VIEW_PORT];
	}
	if (([gameView isDown:gvFunctionKey4] || [gameView isDown:key_view_starboard])||(virtualView.x > view_threshold)||joyButtonState[BUTTON_VIEWSTARBOARD])
	{
		[self switchToThisView:VIEW_STARBOARD];
	}
	
	[self pollCustomViewControls];
	
	// Zoom scanner 'z'
	if (([gameView isDown:key_scanner_zoom] && ([gameView allowingStringInput] == gvStringInputNo)) || joyButtonState[BUTTON_SCANNERZOOM]) // look for the 'z' key
	{
		if (!scanner_zoom_rate)
		{
			if ([hud scannerZoom] < 5.0)
			{
				if (([hud scannerZoom] > 1.0)||(!zoom_pressed))
					scanner_zoom_rate = SCANNER_ZOOM_RATE_UP;
			}
			else
			{
				if (!zoom_pressed)	// must release and re-press zoom to zoom back down..
					scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
			}
		}
		zoom_pressed = YES;
	}
	else
		zoom_pressed = NO;
	
	// Unzoom scanner 'Z'
	if ([gameView isDown:key_scanner_unzoom] && ([gameView allowingStringInput] == gvStringInputNo)) // look for the 'Z' key
	{
		if ((!scanner_zoom_rate)&&([hud scannerZoom] > 1.0))
			scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
	}
	
	if (EXPECT([[self hud] isCompassActive]))	// only switch compass modes if there is a compass
	{
		// Compass mode '|'
		if ([gameView isDown:key_prev_compass_mode]) // look for the '|' key
		{
			if ((!prev_compass_mode_pressed)&&(compassMode != COMPASS_MODE_BASIC))
				[self setPrevCompassMode];
			prev_compass_mode_pressed = YES;
		}
		else
		{
			prev_compass_mode_pressed = NO;
		}
		// Compass mode '\'
		if ([gameView isDown:key_next_compass_mode]) // look for the '\' key
		{
			if ((!next_compass_mode_pressed)&&(compassMode != COMPASS_MODE_BASIC))
				[self setNextCompassMode];
			next_compass_mode_pressed = YES;
		}
		else
		{
			next_compass_mode_pressed = NO;
		}
	}
	
	//  show comms log '`'
	if ([gameView isDown:key_comms_log])
	{
		[UNIVERSE showCommsLog: 1.5];
		[hud refreshLastTransmitter];
	}
}


- (void) pollFlightArrowKeyControls:(double)delta_t
{
	MyOpenGLView		*gameView = [UNIVERSE gameView];
	OOJoystickManager	*stickHandler = [OOJoystickManager sharedStickHandler];
	NSUInteger			numSticks = [stickHandler joystickCount];
	NSPoint				virtualStick = NSZeroPoint;
	double				reqYaw = 0.0;
	
	/*	DJS: Handle inputs on the joy roll/pitch axis.
	 Mouse control on takes precidence over joysticks.
	 We have to assume the player has a reason for switching mouse
	 control on if they have a joystick - let them do it. */
	if (mouse_control_on)
	{
		virtualStick=[gameView virtualJoystickPosition];
		double sensitivity = 2.0;
		virtualStick.x *= sensitivity;
		virtualStick.y *= sensitivity;
		reqYaw = virtualStick.x;
	}
	else if (numSticks > 0)
	{
		virtualStick = [stickHandler rollPitchAxis];
		// handle roll separately (fix for BUG #17490)
		if(virtualStick.x == STICK_AXISUNASSIGNED)
		{
			// Not assigned - set to zero.
			virtualStick.x=0;
		}
		else if(virtualStick.x != 0)
		{
			// cancel keyboard override, stick has been waggled
			keyboardRollOverride=NO;
		}
		// handle pitch separately (fix for BUG #17490)
		if(virtualStick.y == STICK_AXISUNASSIGNED)
		{
			// Not assigned - set to zero.
			virtualStick.y=0;
		}
		else if(virtualStick.y != 0)
		{
			// cancel keyboard override, stick has been waggled
			keyboardPitchOverride=NO;
		}
		// handle yaw separately from pitch/roll
		reqYaw = [stickHandler getAxisState: AXIS_YAW];
		if(reqYaw == STICK_AXISUNASSIGNED)
		{
			// Not assigned or deadzoned - set to zero.
			reqYaw=0;
		}
		else if(reqYaw != 0)
		{
			// cancel keyboard override, stick has been waggled
			keyboardYawOverride=NO;
		}
	}
	
	double roll_dampner = ROLL_DAMPING_FACTOR * delta_t;
	double pitch_dampner = PITCH_DAMPING_FACTOR * delta_t;
	double yaw_dampner = YAW_DAMPING_FACTOR * delta_t;
	
	BOOL	isCtrlDown = [gameView isCtrlDown];
	
	double	flightArrowKeyPrecisionFactor = [[NSUserDefaults standardUserDefaults] oo_doubleForKey:@"flight-arrow-key-precision-factor" defaultValue:0.5];
	if (flightArrowKeyPrecisionFactor < 0.05)  flightArrowKeyPrecisionFactor = 0.05;
	if (flightArrowKeyPrecisionFactor > 1.0)  flightArrowKeyPrecisionFactor = 1.0; 
	
	rolling = NO;
	// if we have yaw on the mouse x-axis, then allow using the keyboard roll keys
	if (!mouse_control_on || (mouse_control_on && mouse_x_axis_map_to_yaw))
	{
		if ([gameView isDown:key_roll_left] && [gameView isDown:key_roll_right])
		{
			keyboardRollOverride = YES;
			flightRoll = 0.0;
		}
		else if ([gameView isDown:key_roll_left])
		{
			keyboardRollOverride=YES;
			if (flightRoll > 0.0)  flightRoll = 0.0;
			[self decrease_flight_roll:isCtrlDown ? flightArrowKeyPrecisionFactor*roll_dampner*roll_delta : delta_t*roll_delta];
			rolling = YES;
		}
		else if ([gameView isDown:key_roll_right])
		{
			keyboardRollOverride=YES;
			if (flightRoll < 0.0)  flightRoll = 0.0;
			[self increase_flight_roll:isCtrlDown ? flightArrowKeyPrecisionFactor*roll_dampner*roll_delta : delta_t*roll_delta];
			rolling = YES;
		}
	}
	if(((mouse_control_on && !mouse_x_axis_map_to_yaw) || numSticks) && !keyboardRollOverride)
	{
		stick_roll = max_flight_roll * virtualStick.x;
		if (flightRoll < stick_roll)
		{
			[self increase_flight_roll:delta_t*roll_delta];
			if (flightRoll > stick_roll)
				flightRoll = stick_roll;
		}
		if (flightRoll > stick_roll)
		{
			[self decrease_flight_roll:delta_t*roll_delta];
			if (flightRoll < stick_roll)
				flightRoll = stick_roll;
		}
		rolling = (fabs(virtualStick.x) > 0.0);
	}
	if (!rolling)
	{
		if (flightRoll > 0.0)
		{
			if (flightRoll > roll_dampner)	[self decrease_flight_roll:roll_dampner];
			else	flightRoll = 0.0;
		}
		if (flightRoll < 0.0)
		{
			if (flightRoll < -roll_dampner)   [self increase_flight_roll:roll_dampner];
			else	flightRoll = 0.0;
		}
	}
	
	pitching = NO;
	// we don't care about pitch keyboard overrides when mouse control is on, only when using joystick
	if (!mouse_control_on)
	{
		if ([gameView isDown:key_pitch_back] && [gameView isDown:key_pitch_forward])
		{
			keyboardPitchOverride=YES;
			flightPitch = 0.0;
		}
		else if ([gameView isDown:key_pitch_back])
		{
			keyboardPitchOverride=YES;
			if (flightPitch < 0.0)  flightPitch = 0.0;
			[self increase_flight_pitch:isCtrlDown ? flightArrowKeyPrecisionFactor*pitch_dampner*pitch_delta : delta_t*pitch_delta];
			pitching = YES;
		}
		else if ([gameView isDown:key_pitch_forward])
		{
			keyboardPitchOverride=YES;
			if (flightPitch > 0.0)  flightPitch = 0.0;
			[self decrease_flight_pitch:isCtrlDown ? flightArrowKeyPrecisionFactor*pitch_dampner*pitch_delta : delta_t*pitch_delta];
			pitching = YES;
		}
	}
	if(mouse_control_on || (numSticks && !keyboardPitchOverride))
	{
		stick_pitch = max_flight_pitch * virtualStick.y;
		if (flightPitch < stick_pitch)
		{
			[self increase_flight_pitch:delta_t*pitch_delta];
			if (flightPitch > stick_pitch)
				flightPitch = stick_pitch;
		}
		if (flightPitch > stick_pitch)
		{
			[self decrease_flight_pitch:delta_t*pitch_delta];
			if (flightPitch < stick_pitch)
				flightPitch = stick_pitch;
		}
		pitching = (fabs(virtualStick.y) > 0.0);
	}
	if (!pitching)
	{
		if (flightPitch > 0.0)
		{
			if (flightPitch > pitch_dampner)	[self decrease_flight_pitch:pitch_dampner];
			else	flightPitch = 0.0;
		}
		if (flightPitch < 0.0)
		{
			if (flightPitch < -pitch_dampner)	[self increase_flight_pitch:pitch_dampner];
			else	flightPitch = 0.0;
		}
	}
	
	yawing = NO;
	// if we have roll on the mouse x-axis, then allow using the keyboard yaw keys
	if (!mouse_control_on || (mouse_control_on && !mouse_x_axis_map_to_yaw))
	{
		if ([gameView isDown:key_yaw_left] && [gameView isDown:key_yaw_right])
		{
			keyboardYawOverride=YES;
			flightYaw = 0.0;
		}
		else if ([gameView isDown:key_yaw_left])
		{
			keyboardYawOverride=YES;
			if (flightYaw < 0.0)  flightYaw = 0.0;
			[self increase_flight_yaw:isCtrlDown ? flightArrowKeyPrecisionFactor*yaw_dampner*yaw_delta : delta_t*yaw_delta];
			yawing = YES;
		}
		else if ([gameView isDown:key_yaw_right])
		{
			keyboardYawOverride=YES;
			if (flightYaw > 0.0)  flightYaw = 0.0;
			[self decrease_flight_yaw:isCtrlDown ? flightArrowKeyPrecisionFactor*yaw_dampner*yaw_delta : delta_t*yaw_delta];
			yawing = YES;
		}
	}
	if(((mouse_control_on && mouse_x_axis_map_to_yaw) || numSticks) && !keyboardYawOverride)
	{
		// I think yaw is handled backwards in the code,
		// which is why the negative sign is here.
		stick_yaw = max_flight_yaw * (-reqYaw);
		if (flightYaw < stick_yaw)
		{
			[self increase_flight_yaw:delta_t*yaw_delta];
			if (flightYaw > stick_yaw)
				flightYaw = stick_yaw;
		}
		if (flightYaw > stick_yaw)
		{
			[self decrease_flight_yaw:delta_t*yaw_delta];
			if (flightYaw < stick_yaw)
				flightYaw = stick_yaw;
		}
		yawing = (fabs(reqYaw) > 0.0);
	}
	if (!yawing)
	{
		if (flightYaw > 0.0)
		{
			if (flightYaw > yaw_dampner)	[self decrease_flight_yaw:yaw_dampner];
			else	flightYaw = 0.0;
		}
		if (flightYaw < 0.0)
		{
			if (flightYaw < -yaw_dampner)   [self increase_flight_yaw:yaw_dampner];
			else	flightYaw = 0.0;
		}
	}

}


- (void) pollGuiScreenControls
{
	[self pollGuiScreenControlsWithFKeyAlias:YES];
}


- (void) pollGuiScreenControlsWithFKeyAlias:(BOOL)fKeyAlias
{
	if(!pollControls && fKeyAlias)	// Still OK to run, if we don't use number keys.
		return;
	
	GuiDisplayGen	*gui = [UNIVERSE gui];
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	BOOL			docked_okay = ([self status] == STATUS_DOCKED);
	
	//  text displays
	if ([gameView isDown:gvFunctionKey5] || [gameView isDown:key_gui_screen_status])
	{
		if (!switching_status_screens)
		{
			switching_status_screens = YES;
			if (gui_screen == GUI_SCREEN_STATUS)
			{
				[self noteGUIWillChangeTo:GUI_SCREEN_MANIFEST];
				[self setGuiToManifestScreen];
			}
			else
				[self setGuiToStatusScreen];
			[self checkScript];
		}
	}
	else
	{
		switching_status_screens = NO;
	}
	
	if (([gameView isDown:gvFunctionKey6])||(fKeyAlias && [gameView isDown:key_gui_chart_screens]))
	{
		if  (!switching_chart_screens)
		{
			switching_chart_screens = YES;
			if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART || (gui_screen == GUI_SCREEN_SYSTEM_DATA && showingLongRangeChart))
				[self setGuiToLongRangeChartScreen];
			else
				[self setGuiToShortRangeChartScreen];
		}
	}
	else
	{
		switching_chart_screens = NO;
	}
	
	if (([gameView isDown:gvFunctionKey7])||(fKeyAlias &&[gameView isDown:key_gui_system_data]))
	{
		if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
		{
			showingLongRangeChart = (gui_screen == GUI_SCREEN_LONG_RANGE_CHART);
			[self noteGUIWillChangeTo:GUI_SCREEN_SYSTEM_DATA];
			[self setGuiToSystemDataScreen];
		}
	}
	
	
	if (docked_okay)
	{	
		if ((([gameView isDown:gvFunctionKey2])||(fKeyAlias && [gameView isDown:key_view_aft]))&&(gui_screen != GUI_SCREEN_OPTIONS))
		{
			[gameView clearKeys];
			[self setGuiToLoadSaveScreen];
		}
		
		if (([gameView isDown:gvFunctionKey3])||(fKeyAlias && [gameView isDown:key_view_port]))
		{
			if (!switching_equipship_screens)
			{
				if ([self dockedStation] == nil)  [self setDockedAtMainStation];
				OOGUIScreenID oldScreen = gui_screen;
				
				if ((gui_screen == GUI_SCREEN_EQUIP_SHIP) && [[self dockedStation] hasShipyard])
				{
					[gameView clearKeys];
					[self noteGUIWillChangeTo:GUI_SCREEN_SHIPYARD];
					[self setGuiToShipyardScreen:0];
					[gui setSelectedRow:GUI_ROW_SHIPYARD_START];
					[self showShipyardInfoForSelection];
				}
				else
				{
					[gameView clearKeys];
					[self noteGUIWillChangeTo:GUI_SCREEN_EQUIP_SHIP];
					[self setGuiToEquipShipScreen:0];
					[gui setSelectedRow:GUI_ROW_EQUIPMENT_START];
				}
				
				[self noteGUIDidChangeFrom:oldScreen to:gui_screen]; 
			}
			switching_equipship_screens = YES;
		}
		else
		{
			switching_equipship_screens = NO;
		}
		
		if (([gameView isDown:gvFunctionKey4])||(fKeyAlias && [gameView isDown:key_view_starboard]))
		{
			[self setGuiToInterfacesScreen:0];
			[gui setSelectedRow:GUI_ROW_INTERFACES_START];
		}

		if (([gameView isDown:gvFunctionKey8])||(fKeyAlias && [gameView isDown:key_gui_market]))
		{
			[gameView clearKeys];
			[self noteGUIWillChangeTo:GUI_SCREEN_MARKET];
			[self setGuiToMarketScreen];
			[gui setSelectedRow:GUI_ROW_MARKET_START];
		}
	}
	else
	{
		if ([gameView isDown:gvFunctionKey8] || [gameView isDown:key_gui_market])
		{
			[self noteGUIWillChangeTo:GUI_SCREEN_MARKET];
			[self setGuiToMarketScreen];
			[gui setSelectedRow:GUI_ROW_MARKET_START];
		}
	}
}


- (void) pollGameOverControls:(double)delta_t
{
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	if ([gameView isDown:32])   // look for the spacebar
	{
		if (!spacePressed)
		{
			[UNIVERSE displayMessage:@"" forCount:1.0];
			shot_time = INITIAL_SHOT_TIME;	// forces immediate restart
		}
		spacePressed = YES;
	}
	else
		spacePressed = NO;
}


static BOOL toggling_music;
static BOOL playing_music;
static BOOL autopilot_pause;

- (void) pollAutopilotControls:(double)delta_t
{
	// controls polled while the autopilot is active
	
	MyOpenGLView  *gameView = [UNIVERSE gameView];
	
	if (![[UNIVERSE gameController] isGamePaused])
	{
		//  view keys
		[self pollViewControls];
		
		//  text displays
		[self pollGuiScreenControls];
		
		if ([UNIVERSE displayGUI])
			[self pollGuiArrowKeyControls:delta_t];
		
		const BOOL *joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
		if ([gameView isDown:key_autopilot] || joyButtonState[BUTTON_DOCKCPU]
			|| [gameView isDown:key_autodock] || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'c' and 'C' key
		{
			if ([self hasDockingComputer] && !autopilot_key_pressed)
			{
				[self disengageAutopilot];
				[UNIVERSE addMessage:DESC(@"autopilot-off") forCount:4.5];
			}
			autopilot_key_pressed = YES;
			if ([gameView isDown:key_autodock] || joyButtonState[BUTTON_DOCKCPUFAST])
			{
				fast_autopilot_key_pressed = YES;
			}
		}
		else
		{
			autopilot_key_pressed = NO;
		}
		
		if (([gameView isDown:key_docking_music]))   // look for the 's' key
		{
			if (!toggling_music)
			{
				[[OOMusicController sharedController] toggleDockingMusic];
			}
			toggling_music = YES;
		}
		else
		{
			toggling_music = NO;
		}
		// look for the pause game, 'p' key
		if ([gameView isDown:key_pausebutton] && gui_screen != GUI_SCREEN_LONG_RANGE_CHART && gui_screen != GUI_SCREEN_MISSION)
		{
			if (!autopilot_pause)
			{
				playing_music = [[OOMusicController sharedController] isPlaying];
				if (playing_music)  [[OOMusicController sharedController] toggleDockingMusic];
				// normal flight controls can handle the rest.
				pause_pressed = NO;	// pause button flag must be NO for pollflightControls to react!
				[self pollFlightControls:delta_t];
			}
			autopilot_pause = YES;
		}
		else
		{
			autopilot_pause = NO;
		}
	}
	else
	{
		// paused
		if ([gameView isDown:key_pausebutton])
		{
			if (!autopilot_pause)
			{
				if (playing_music)  [[OOMusicController sharedController] toggleDockingMusic];
			}
			autopilot_pause = YES;
		}
		else
		{
			autopilot_pause = NO;
		}
		// let the normal flight controls handle paused commands.
		[self pollFlightControls:delta_t];
	}
}


- (void) pollDockedControls:(double)delta_t
{
	MyOpenGLView			*gameView = [UNIVERSE gameView];
	GameController			*gameController = [UNIVERSE gameController];
	NSString				*exceptionContext = @"setup";
	
	@try
	{
		// Pause game, 'p' key
		exceptionContext = @"pause key";
		if ([gameView isDown:key_pausebutton] && (gui_screen != GUI_SCREEN_LONG_RANGE_CHART &&
				gui_screen != GUI_SCREEN_MISSION && gui_screen != GUI_SCREEN_REPORT &&
				gui_screen != GUI_SCREEN_SAVE) )
		{
			if (!pause_pressed)
			{
				if ([gameController isGamePaused])
				{
					script_time = saved_script_time;
					[gameView allowStringInput:NO];
					if ([UNIVERSE pauseMessageVisible])
					{
						[UNIVERSE clearPreviousMessage];	// remove the 'paused' message.
					}
					[[UNIVERSE gui] setForegroundTextureKey:@"docked_overlay"];
					[gameController setGamePaused:NO];
				}
				else
				{
					saved_script_time = script_time;
					[[UNIVERSE messageGUI] clear];
					
					[UNIVERSE pauseGame];	// 'paused' handler
				}
			}
			pause_pressed = YES;
		}
		else
		{
			pause_pressed = NO;
		}
		
		if ([gameController isGamePaused]) return;
		
		if(pollControls)
		{
			exceptionContext = @"undock";
			if ([gameView isDown:gvFunctionKey1] || [gameView isDown:key_view_forward])   // look for the f1 key
			{
				if (EXPECT(gui_screen != GUI_SCREEN_MISSION || _missionAllowInterrupt))
				{
					[self handleUndockControl];
				}
			}
		}
		
		//  text displays
		// mission screens
		exceptionContext = @"GUI keys";
		if (gui_screen == GUI_SCREEN_MISSION)
		{
			[self pollDemoControls: delta_t];	// don't switch away from mission screens
		}
		else
		{
			if (gui_screen != GUI_SCREEN_REPORT)[self pollGuiScreenControls];	// don't switch away from report screens
		}
		
		[self pollGuiArrowKeyControls:delta_t];
	}
	@catch (NSException *exception)
	{
		OOLog(kOOLogException, @"***** Exception in pollDockedControls [%@]: %@ : %@", exceptionContext, [exception name], [exception reason]);
	}
}


- (void) handleUndockControl
{
	// FIXME: should this not be in leaveDock:? (Note: leaveDock: is also called from script method launchFromStation and -[StationEntity becomeExplosion]) -- Ahruman 20080308
	[UNIVERSE setUpUniverseFromStation]; // player pre-launch
	if ([self dockedStation] == nil)  [self setDockedAtMainStation];
	
	StationEntity *dockedStation = [self dockedStation];
	if (dockedStation == [UNIVERSE station] && [UNIVERSE autoSaveNow] && !([[UNIVERSE sun] goneNova] || [[UNIVERSE sun] willGoNova]))
	{
		[self autosavePlayer];
	}
	[self launchFromStation];
}


- (void) pollDemoControls:(double)delta_t
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	GuiDisplayGen	*gui = [UNIVERSE gui];
	NSUInteger end_row = 21;
	OOOXZManager *oxzmanager = [OOOXZManager sharedManager];

	switch (gui_screen)
	{
		case GUI_SCREEN_INTRO1:
			[self handleGUIUpDownArrowKeys];

			int row_zero = 21;
			if (!selectPressed)
			{
				if (!disc_operation_in_progress)
				{
					if (([gameView isDown:gvMouseDoubleClick] || [gameView isDown:13]) && [gui selectedRow] == 2+row_zero)
					{
//						[[OOMusicController sharedController] stopThemeMusic];
						disc_operation_in_progress = YES;
						[UNIVERSE removeDemoShips];
						[gui clearBackground];
						if (![self loadPlayer])
						{
							[self setGuiToIntroFirstGo:YES];
						}
						break;
					}
				}
				if (([gameView isDown:gvMouseDoubleClick] || [gameView isDown:13]) && [gui selectedRow] == 1+row_zero)
				{
					missionTextRow = 0;
					[self setGuiToScenarioScreen:0];
				} 
				else if (([gameView isDown:gvMouseDoubleClick] || [gameView isDown:13]) && [gui selectedRow] == 3+row_zero)
				{
					[self setGuiToIntroFirstGo:NO];
				}
				else if (([gameView isDown:gvMouseDoubleClick] || [gameView isDown:13]) && [gui selectedRow] == 4+row_zero)
				{
					[self setGuiToOXZManager];
				}
				else if (([gameView isDown:gvMouseDoubleClick] || [gameView isDown:13]) && [gui selectedRow] == 5+row_zero)
				{
					[[UNIVERSE gameController] exitAppWithContext:@"Exit Game selected on start screen"];
				}
				else
				{
					disc_operation_in_progress = NO;
				}
			}
			selectPressed = [gameView isDown:13];
			if ([gameView isDown:gvMouseDoubleClick])
			{
				[gameView clearMouse];
			}
			break;
			
		case GUI_SCREEN_INTRO2:
			if ([gameView isDown:' '])	//  '<space>'
			{
				[self setGuiToIntroFirstGo:YES];
			}
			if ([gameView isDown:key_gui_arrow_left])	//  '<--'
			{
				if (!upDownKeyPressed)
					[UNIVERSE selectIntro2Previous];
			}
			if ([gameView isDown:key_gui_arrow_right])	//  '-->'
			{
				if (!upDownKeyPressed)
					[UNIVERSE selectIntro2Next];
			}
			upDownKeyPressed = (([gameView isDown:key_gui_arrow_left])||([gameView isDown:key_gui_arrow_right]));
			break;
		
		case GUI_SCREEN_NEWGAME:
			if ([self handleGUIUpDownArrowKeys])
			{
				[self showScenarioDetails];
			}

			if (!selectPressed)
			{
				if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick]) // enter
				{
					if (![self startScenario])
					{
						[UNIVERSE removeDemoShips];
						[self setGuiToIntroFirstGo:YES];
					} 
				}
			}
			selectPressed = [gameView isDown:13];
			if ([gameView isDown:gvMouseDoubleClick] || [gameView isDown:gvMouseLeftButton])
			{
				[gameView clearMouse];
			}
			break;

		case GUI_SCREEN_OXZMANAGER:
			if (EXPECT(![oxzmanager isRestarting]))
			{
				if ([self handleGUIUpDownArrowKeys])
				{
					// only has an effect on install/remove selection screens
					[oxzmanager showOptionsUpdate];
				}
				if ([gameView isDown:key_gui_arrow_left])
				{
					if ((!leftRightKeyPressed))
					{
						[oxzmanager showOptionsPrev];
					}
				}
				if ([gameView isDown:key_gui_arrow_right])
				{
					if ((!leftRightKeyPressed))
					{
						[oxzmanager showOptionsNext];
					}
				}
				leftRightKeyPressed = [gameView isDown:key_gui_arrow_right]|[gameView isDown:key_gui_arrow_left];

				if (!selectPressed)
				{
					if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick]) // enter
					{
						[oxzmanager processSelection];
					}
				}
				selectPressed = [gameView isDown:13];
				if ([gameView isDown:gvMouseDoubleClick] || [gameView isDown:gvMouseLeftButton])
				{
					[gameView clearMouse];
				}
			}
			break;
	

	
		case GUI_SCREEN_MISSION:
			if ([[self hud] isHidden])
			{
				end_row = 27;
			}
			if (_missionTextEntry)
			{
				[self refreshMissionScreenTextEntry];
				if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])	//  '<enter/return>' or double click
				{
					[self setMissionChoice:[gameView typedString]];
					[[OOMusicController sharedController] stopMissionMusic];
					[self playDismissedMissionScreen];
					
					[self handleMissionCallback];
					
					[self checkScript];
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
					[self pollMissionInterruptControls];
				}
			}
			else if ([[gui keyForRow:end_row] isEqual:@"spacebar"])
			{
				if ([gameView isDown:32])	//  '<space>'
				{
					if (!spacePressed)
					{
						[[OOMusicController sharedController] stopMissionMusic];
						
						[self handleMissionCallback];
						
					}
					spacePressed = YES;
				}
				else
				{
					spacePressed = NO;
					[self pollMissionInterruptControls];
				}
			}
			else
			{
				[self handleGUIUpDownArrowKeys];
				
				if ([gameView isDown:13] || [gameView isDown:gvMouseDoubleClick])	//  '<enter/return>' or double click
				{
					if ([gameView isDown:gvMouseDoubleClick])
					{
						selectPressed = NO;
						[gameView clearMouse];
					}
					if (!selectPressed)
					{
						[self setMissionChoice:[gui selectedRowKey]];
						[[OOMusicController sharedController] stopMissionMusic];
						[self playDismissedMissionScreen];
						
						[self handleMissionCallback];
						
						[self checkScript];
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
					[self pollMissionInterruptControls];
				}
			}
			break;
			
#if OO_USE_CUSTOM_LOAD_SAVE
			// DJS: Farm off load/save screen options to LoadSave.m
		case GUI_SCREEN_LOAD:
		{
			NSString *commanderFile = [self commanderSelector];
			if(commanderFile)
			{
				// also release the demo ship here (see showShipyardModel and noteGUIDidChangeFrom)
				[demoShip release];
				demoShip = nil;
				
				[self loadPlayerFromFile:commanderFile asNew:NO];
			}
			break;
		}
#endif

		default:
			break;
	}
}


- (void) pollMissionInterruptControls
{
	if (_missionAllowInterrupt)
	{
		[self pollGuiScreenControls];
		if (gui_screen != GUI_SCREEN_MISSION)
		{
			if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
			{
				[UNIVERSE removeDemoShips];
			}
			[self endMissionScreenAndNoteOpportunity];
		}
	}
}


- (void) handleMissionCallback
{
	[UNIVERSE removeDemoShips];
	[[UNIVERSE gui] clearBackground];

	[self setGuiToMissionEndScreen]; // need this to find out if we call a new mission screen inside callback.
	
	if ([self status] != STATUS_DOCKED) [self switchToThisView:VIEW_FORWARD];

	if (_missionWithCallback)
	{
		[self doMissionCallback];
	}
	
	if ([self status] != STATUS_DOCKED)	// did we launch inside callback? / are we in flight?
	{
		// TODO: This is no longer doing anything because of an 'isDocked' check inside the function. ***** Probably remove it for 1.76
		[self doWorldEventUntilMissionScreen:OOJSID("missionScreenEnded")];	// no opportunity events.
	}
	else
	{
		if (gui_screen != GUI_SCREEN_MISSION) // did we call a new mission screen inside callback?
		{
			// note that this might not be the same end screen as last time...
			[self setGuiToMissionEndScreen];	// if not, update status screen with callback changes, if any.
			[self endMissionScreenAndNoteOpportunity];	// missionScreenEnded, plus opportunity events.
		}
	}
}


- (void) setGuiToMissionEndScreen
{
	MyOpenGLView	*gameView = [UNIVERSE gameView];
	[gameView clearKeys];
	if ([self status] != STATUS_DOCKED)
	{
		// this setting is only applied when not docked
		[self setGuiToStatusScreen];
		return;
	}
	switch (_missionExitScreen)
	{
	case GUI_SCREEN_MANIFEST:
		[self noteGUIWillChangeTo:GUI_SCREEN_MANIFEST];
		[self setGuiToManifestScreen];
		break;
	case GUI_SCREEN_EQUIP_SHIP:
		[self noteGUIWillChangeTo:GUI_SCREEN_EQUIP_SHIP];
		[self setGuiToEquipShipScreen:0];
		break;
	case GUI_SCREEN_SHIPYARD:
		if ([[self dockedStation] hasShipyard])
		{
			[self noteGUIWillChangeTo:GUI_SCREEN_SHIPYARD];
			[self setGuiToShipyardScreen:0];
			[[UNIVERSE gui] setSelectedRow:GUI_ROW_SHIPYARD_START];
			[self showShipyardInfoForSelection];
		}
		else
		{
			// that doesn't work here
			[self setGuiToStatusScreen];
		}
		break;
	case GUI_SCREEN_SHORT_RANGE_CHART:
		[self setGuiToShortRangeChartScreen];
		break;
	case GUI_SCREEN_LONG_RANGE_CHART:
		[self setGuiToLongRangeChartScreen];
		break;
	case GUI_SCREEN_SYSTEM_DATA:
		[self noteGUIWillChangeTo:GUI_SCREEN_SYSTEM_DATA];
		[self setGuiToSystemDataScreen];
		break;
	case GUI_SCREEN_MARKET:
		[self noteGUIWillChangeTo:GUI_SCREEN_MARKET];
		[self setGuiToMarketScreen];
		[[UNIVERSE gui] setSelectedRow:GUI_ROW_MARKET_START];
		break;
	case GUI_SCREEN_INTERFACES:
		[self setGuiToInterfacesScreen:0];
		break;
	case GUI_SCREEN_STATUS:
	default: // invalid screen specifications
		[self setGuiToStatusScreen];
	}
}


- (void) switchToThisView:(OOViewID)viewDirection
{
	[self switchToThisView:viewDirection andProcessWeaponFacing:YES];
}


- (void) switchToThisView:(OOViewID)viewDirection andProcessWeaponFacing:(BOOL)processWeaponFacing
{
	[self switchToThisView:viewDirection fromView:[UNIVERSE viewDirection] andProcessWeaponFacing:processWeaponFacing justNotify:NO];
}


- (void) switchToThisView:(OOViewID)viewDirection fromView:(OOViewID)oldViewDirection andProcessWeaponFacing:(BOOL)processWeaponFacing justNotify:(BOOL)justNotify
{
	if (!justNotify)
	{	
		if ([UNIVERSE displayGUI]) [self switchToMainView];
		[UNIVERSE setViewDirection:viewDirection];
	}
	if (processWeaponFacing)
	{
		OOWeaponFacing facing = WEAPON_FACING_NONE;
		switch (viewDirection)
		{
			case VIEW_FORWARD:
				facing = WEAPON_FACING_FORWARD;
				break;
				
			case VIEW_AFT:
				facing = WEAPON_FACING_AFT;
				break;
				
			case VIEW_PORT:
				facing = WEAPON_FACING_PORT;
				break;
				
			case VIEW_STARBOARD:
				facing = WEAPON_FACING_STARBOARD;
				break;
				
			default:
				break;
		}
		
		if (facing != WEAPON_FACING_NONE)
		{
			currentWeaponFacing = facing;
			[self currentWeaponStats];
		}
		else
		{
			OOLogERR(kOOLogParameterError, @"%s called with processWeaponFacing=YES for non-main view %i.", __FUNCTION__, viewDirection);
		}
	}
	if ((oldViewDirection != viewDirection || viewDirection == VIEW_CUSTOM) && ![[UNIVERSE gameController] isGamePaused])
	{
		JSContext *context = OOJSAcquireContext();
		ShipScriptEvent(context, self, "viewDirectionChanged", OOJSValueFromViewID(context, viewDirection), OOJSValueFromViewID(context, oldViewDirection));
		OOJSRelinquishContext(context);
	}
}


// Called on c or Shift-C
- (void) handleAutopilotOn:(BOOL)fastDocking
{
	NSString	*message = nil;
	
	// Check alert condition - on red alert, abort
	// -- but only for fast docking
	if (fastDocking && ([self alertCondition] == ALERT_CONDITION_RED))
	{
		[self playAutopilotCannotDockWithTarget];
		message = DESC(@"autopilot-red-alert");
		goto abort;
	}
	
	Entity *target = [self primaryTarget];
	// If target isn't dockable, check for nearby stations
	if (![target isStation])
	{
		Universe  *uni        = UNIVERSE;
		Entity    **entities  = uni->sortedEntities;	// grab the public sorted list
		int       nStations   = 0;
		unsigned  i;
		
		for (i = 0; i < uni->n_entities && nStations < 2; i++)
		{
			if (entities[i]->isStation && [entities[i] isKindOfClass:[StationEntity class]] &&
				entities[i]->zero_distance <= SCANNER_MAX_RANGE2)
			{
				nStations++;
				target = entities[i];
			}
		}
		// If inside the Aegis, dock with the main station.
		// If we found one target, dock with it.
		// If outside the Aegis and we found multiple targets, abort.
		
		if ([self withinStationAegis] && legalStatus <= 50)
		{
			target = [UNIVERSE station];
		}
		else if (nStations != 1)
		{
			if (nStations == 0)
			{
				[self playAutopilotOutOfRange];
				message = DESC(@"autopilot-out-of-range");
			}
			else
			{
				[self playAutopilotCannotDockWithTarget];
				message = DESC(@"autopilot-multiple-targets");
			}
			goto abort;
		}
	}
	
	// We found a dockable, check whether we can dock with it
	// NSAssert([target isKindOfClass:[StationEntity class]], @"Expected entity with isStation flag set to be a station.");		// no need for asserts. Tested enough already.
	StationEntity *ts = (StationEntity*)target;
	
	// If station is not transmitting docking instructions, we cannot use autopilot.
	if (![ts allowsAutoDocking])
	{
		[self playAutopilotCannotDockWithTarget];
		message = [NSString stringWithFormat:DESC(@"autopilot-station-@-does-not-allow-autodocking"), [ts displayName]];
	}
	// Deny if station is hostile or player is a fugitive trying to dock at the main station.
	else if ((legalStatus > 50 && ts == [UNIVERSE station]) || [ts isHostileTo:self])
	{
		[self playAutopilotCannotDockWithTarget];
		message = (ts == [UNIVERSE station] ? DESC(@"autopilot-denied") : DESC(@"autopilot-target-docking-instructions-denied"));
	}
	// If we're fast-docking, perform the docking logic
	else if (fastDocking && [ts allowsFastDocking])
	{
		if (legalStatus > 0)
		{
			// there's a slight chance you'll be fined for your past offences when autodocking
			int fine_chance = ranrot_rand() & 0x03ff;	//	0..1023
			int government = 1 + [[UNIVERSE currentSystemData] oo_intForKey:KEY_GOVERNMENT];	// 1..8
			if ([UNIVERSE inInterstellarSpace])  government = 2;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
			fine_chance /= government;
			if (fine_chance < legalStatus)
			{
				[self markForFines];
			}
		}
		[self setDockingClearanceStatus:DOCKING_CLEARANCE_STATUS_GRANTED];
		
		[UNIVERSE forceWitchspaceEntries];
		ship_clock_adjust += 1200.0;			// 20 minutes penalty to enter dock
		ident_engaged = NO;
		[self safeAllMissiles];
		[UNIVERSE setViewDirection:VIEW_FORWARD];
		[self enterDock:ts];
	}
	else
	{
		// Standard docking - engage autopilot
		[self engageAutopilotToStation:ts];
		message = DESC(@"autopilot-on");
	}
	
abort:
	// Clean-up code
	if (message != nil) [UNIVERSE addMessage:message forCount:4.5];
	return;
}


- (void) handleButtonIdent
{
	// Clear current target if we're already in Ident mode
	if (ident_engaged)  [self noteLostTarget];
	
	[self safeAllMissiles];
	ident_engaged = YES;
	if ([self primaryTarget] == nil)
	{
		[self playIdentOn];
		[UNIVERSE addMessage:DESC(@"ident-on") forCount:2.0];
	}
	else
	{
		[self playIdentLockedOn];
		[self printIdentLockedOnForMissile:NO];
	}
}


- (void) handleButtonTargetMissile
{
	if (![self weaponsOnline])
	{
		[self handleButtonIdent];
		return;
	}
	
	// Clear current target if we're already in Missile Targeting mode
	if (missile_status != MISSILE_STATUS_SAFE)
	{
		[self noteLostTarget];
	}
	
	// Arm missile and check for missile lock
	missile_status = MISSILE_STATUS_ARMED;
	if ([missile_entity[activeMissile] isMissile])
	{
		if ([[self primaryTarget] isShip])
		{
			missile_status = MISSILE_STATUS_TARGET_LOCKED;
			[missile_entity[activeMissile] addTarget:[self primaryTarget]];
			[self printIdentLockedOnForMissile:YES];
			[self playMissileLockedOn];
		}
		else
		{
			// if it's nil, that means it was lost earlier
			if ([self primaryTarget] != nil)
			{
				[self noteLostTarget];
			}
			[missile_entity[activeMissile] noteLostTarget];
			[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-armed"), [missile_entity[activeMissile] name]] forCount:2.0];
			[self playMissileArmed];
		}
	}
	else if ([missile_entity[activeMissile] isMine])
	{
		[UNIVERSE addMessage:[NSString stringWithFormat:DESC(@"@-armed"), [missile_entity[activeMissile] name]] forCount:2.0];
		[self playMineArmed];
	}
	ident_engaged = NO;
}

@end
