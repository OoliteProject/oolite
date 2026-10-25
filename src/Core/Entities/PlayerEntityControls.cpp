/*

PlayerEntityControls.m

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

#include "PlayerEntityControls.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityLegacyScriptEngine.h"
#include "PlayerEntityScriptMethods.h"
#include "PlayerEntitySound.h"
#include "PlayerEntityLoadSave.h"
#include "PlayerEntityStickMapper.h"
#include "PlayerEntityStickProfile.h"
#include "PlayerEntityKeyMapper.h"

#include "ShipEntityAI.h"
#include "StationEntity.h"
#include "DockEntity.h"
#include "Universe.h"
#include "OOSunEntity.h"
#include "OOPlanetEntity.h"
#include "GameController.h"
#include "AI.h"
#include "MyOpenGLView.h"
#include "OOSound.h"
#include "OOStringParsing.h"
#include "OOOXZManager.h"
#include "OOStringExpander.h"
#include "ResourceManager.h"
#include "HeadUpDisplay.h"
#include "OOConstToString.h"
#include "OOConstToJSString.h"
#include "OOLoggingExtended.h"
#include "OOMusicController.h"
#include "OOTexture.h"
#include "OODebugFlags.h"

#include "OOSystemDescriptionManager.h"
#include "OOJoystickManager.h"

#include "OOJSScript.h"
#include "OOEquipmentType.h"
#include "OOJSGuiScreenKeyDefinition.h"

#include "OODebugSupport.h"
#include "OODebugMonitor.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/objc/OOAssert.h"
#include "OOObjCPList.h"
#include "oofnd/String.hpp"

#define CUSTOM_VIEW_ROTATE_SPEED	1.0
#define CUSTOM_VIEW_ZOOM_SPEED		5.0
#define CUSTOM_VIEW_SPEED_REDUCTION_FACTOR	0.3

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
static BOOL				f9_key_pressed;
#if OO_RESOLUTION_OPTION
static BOOL				switching_resolution;
#endif
#if OOLITE_SPEECH_SYNTH
static BOOL				speech_settings_pressed;
#if OOLITE_ESPEAK
static BOOL				speechVoiceSelectKeyPressed;
static BOOL				speechGenderSelectKeyPressed;
#endif
#endif
static BOOL				wait_for_key_up;
static BOOL				upDownKeyPressed;
static BOOL				pageUpDownKeyPressed;
static BOOL				leftRightKeyPressed;
static BOOL				musicModeKeyPressed;
static BOOL				volumeControlPressed;
static BOOL				fovControlPressed;
#if OOLITE_WINDOWS
static BOOL				hdrMaxBrightnessControlPressed;
static BOOL				hdrPaperWhiteControlPressed;
#endif
static BOOL				colorblindModeControlPressed;
static BOOL				shaderSelectKeyPressed;
static BOOL				selectPressed;
static BOOL				queryPressed;
static BOOL				spacePressed;
static BOOL				chartInfoPressed;
static BOOL				switching_chart_screens;
static BOOL				switching_status_screens;
//static BOOL				switching_market_screens;
static BOOL				switching_equipship_screens;
static BOOL				switching_interface_screens;
static BOOL				zoom_pressed;
static BOOL				customView_pressed;
static BOOL				weaponsOnlineToggle_pressed;
static BOOL				escapePodKey_pressed;
static BOOL				cycleMFD_pressed;
static BOOL				switchMFD_pressed;
static BOOL				mouse_left_down;
static BOOL				oxz_manager_pressed;
static BOOL				next_planet_info_pressed;
static BOOL				previous_planet_info_pressed;
static BOOL				home_info_pressed;
static BOOL				target_info_pressed;
static BOOL				extra_key_pressed;
static BOOL				extra_gui_key_pressed;
static NSPoint				mouse_click_position;
static NSPoint				centre_at_mouse_click;


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


namespace
{

// cxx_OOExpandKey(key, ...) with its arguments as a Dict: ints as PList::signedInteger, strings as
// std::string (exemplar OOShipLibraryDescriptions.mm ExpandCategoryKey); nothing expanded is "".
std::string ExpandKeyWithArguments(const char *key, const oo::PList::Dict &args)
{
	return cxx_OOExpandDescriptionString(OOStringExpanderDefaultRandomSeed(), key,
		oo::PList(args), oo::PList(), std::nullopt, kOOExpandKey).value_or(std::string());
}

}	// namespace


void PlayerEntity::initControls()
{
	// all entries in this map must be in lowercase
	keyCodeLookups = {
		{ "arrowleft", gvArrowKeyLeft },
		{ "leftarrow", gvArrowKeyLeft },
		{ "left", gvArrowKeyLeft },
		{ "arrowright", gvArrowKeyRight },
		{ "rightarrow", gvArrowKeyRight },
		{ "right", gvArrowKeyRight },
		{ "arrowup", gvArrowKeyUp },
		{ "uparrow", gvArrowKeyUp },
		{ "up", gvArrowKeyUp },
		{ "arrowdown", gvArrowKeyDown },
		{ "downarrow", gvArrowKeyDown },
		{ "down", gvArrowKeyDown },
		{ "pageup", gvPageUpKey },
		{ "pagedown", gvPageDownKey },
		{ "enter", 13 },
		{ "return", 13 },
		{ "escape", 27 },
		{ "esc", 27 },
		{ "tab", 9 },
		{ "space", 32 },
		{ "spc", 32 },
		{ "home", gvHomeKey },
		{ "end", gvEndKey },
		{ "delete", gvDeleteKey },
		{ "del", gvDeleteKey },
		{ "backspace", gvBackspaceKey },
		{ "backspc", gvBackspaceKey },
		{ "bkspace", gvBackspaceKey },
		{ "bkspc", gvBackspaceKey },
		{ "insert", gvInsertKey },
		{ "ins", gvInsertKey },
		{ "f1", gvFunctionKey1 },
		{ "f2", gvFunctionKey2 },
		{ "f3", gvFunctionKey3 },
		{ "f4", gvFunctionKey4 },
		{ "f5", gvFunctionKey5 },
		{ "f6", gvFunctionKey6 },
		{ "f7", gvFunctionKey7 },
		{ "f8", gvFunctionKey8 },
		{ "f9", gvFunctionKey9 },
		{ "f10", gvFunctionKey10 },
		{ "f11", gvFunctionKey11 },
		{ "pause", gvPauseKey },
		{ "printscreen", gvPrintScreenKey },
		{ "prtscrn", gvPrintScreenKey },
		{ "prntscrn", gvPrintScreenKey },
		{ "prtscn", gvPrintScreenKey },
		{ "numpad0", gvNumberPadKey0 },
		{ "numpad1", gvNumberPadKey1 },
		{ "numpad2", gvNumberPadKey2 },
		{ "numpad3", gvNumberPadKey3 },
		{ "numpad4", gvNumberPadKey4 },
		{ "numpad5", gvNumberPadKey5 },
		{ "numpad6", gvNumberPadKey6 },
		{ "numpad7", gvNumberPadKey7 },
		{ "numpad8", gvNumberPadKey8 },
		{ "numpad9", gvNumberPadKey9 },
		{ "numpad/", gvNumberPadKeyDivide },
		{ "numpaddivide", gvNumberPadKeyDivide },
		{ "numpad*", gvNumberPadKeyMultiply },
		{ "numpadmultiply", gvNumberPadKeyMultiply },
		{ "numpad-", gvNumberPadKeyMinus },
		{ "numpadminus", gvNumberPadKeyMinus },
		{ "numpad+", gvNumberPadKeyPlus },
		{ "numpadplus", gvNumberPadKeyPlus },
		{ "numpad.", gvNumberPadKeyPeriod },
		{ "numpadperiod", gvNumberPadKeyPeriod },
		{ "numpad=", gvNumberPadKeyEquals },
		{ "numpadequals", gvNumberPadKeyEquals },
		{ "numpadenter", gvNumberPadKeyEnter },
	};

	keyShiftText = OO_DESC("oolite-keyconfig-shift");
	keyMod1Text = OO_DESC("oolite-keyconfig-mod1");
#if OOLITE_MAC_OS_X
	keyMod2Text = OO_DESC("oolite-keyconfig-mod2-mac");
#else
	keyMod2Text = OO_DESC("oolite-keyconfig-mod2-pc");
#endif

	initKeyConfigSettings();

	// Enable polling
	pollControls=YES;
}

void PlayerEntity::initKeyConfigSettings()
{
	const oo::PList kdicmaster = ResourceManager::dictionaryFromFilesNamed("keyconfig2.plist", "Config", MERGE_BASIC, NO);
	oo::Defaults &defaults = oo::Defaults::standard();
	// the stored keyboard code (oo_stringForKey:defaultValue: over the value)
	const oo::PList kbdValue = defaults.object("keyboard-code");
	const std::string kbd = oo::PListGet<std::string>::from(kbdValue.isNull() ? nullptr : &kbdValue, "default");
	const oo::PList *kbdDefs = kdicmaster.get<oo::PList::Dict>(kbd);
	oo::PList::Dict kdic2 = (kbdDefs != nullptr) ? *kbdDefs->getIf<oo::PList::Dict>() : oo::PList::Dict();

	for (auto &entry : kdic2)
	{
		if (entry.second.isArray())  entry.second = processKeyCode(entry.second);
	}

	// load custom equipment keys/buttons (the live entries, edited in place)
	const oo::PList savedCustomEquip = defaults.arrayForKey(std::string(KEYCONFIG_CUSTOMEQUIP));
	const oo::PList::Array *customEntries = savedCustomEquip.getIf<oo::PList::Array>();
	customEquipActivation = (customEntries != nullptr) ? *customEntries : std::vector<oo::PList>();
	customActivatePressed.assign(customEquipActivation.size(), NO);
	customModePressed.assign(customEquipActivation.size(), NO);

	// update with overrides from defaults file (unprocessed, as before)
	const oo::PList overrides = defaults.object(std::string(KEYCONFIG_OVERRIDES));
	if (const oo::PList::Dict *dict = overrides.getIf<oo::PList::Dict>())
	{
		for (const auto &entry : *dict)  kdic2[entry.first] = entry.second;
	}

	// the key setting for ivar n_key_<x> is kdic2's entry "key_<x>", or a null PList (nil) when there is none
	const auto keySetting = [&kdic2](std::string_view ivarName) -> oo::PList
	{
		const auto found = kdic2.find(ivarName.substr(2));
		return (found != kdic2.end()) ? found->second : oo::PList();
	};

// by default none of the standard key functions require more than 2 entries, so our macro will limit itself to 2
// also, none of the standard key functions utilise "Alt" (mod2), so we're defaulting that setting
// (the default key definitions were never stored - the array they were added to was nil - so they are not built)
#define LOAD_KEY_SETTING2(name, default_1, shift_1, mod1_1, default_2, shift_2, mod1_2) \
	name = keySetting(#name)

	LOAD_KEY_SETTING2(n_key_roll_left, gvArrowKeyLeft, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_roll_right,	gvArrowKeyRight, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_pitch_forward, gvArrowKeyUp, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_pitch_back, gvArrowKeyDown, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_yaw_left, ',', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_yaw_right, '.', NO, NO, 0, NO, NO);

	LOAD_KEY_SETTING2(n_key_view_forward, '1', NO, NO, gvFunctionKey1, NO, NO);
	LOAD_KEY_SETTING2(n_key_view_aft, '2', NO, NO, gvFunctionKey2, NO, NO);
	LOAD_KEY_SETTING2(n_key_view_port, '3', NO, NO, gvFunctionKey3, NO, NO);
	LOAD_KEY_SETTING2(n_key_view_starboard, '4', NO, NO, gvFunctionKey4, NO, NO);

	LOAD_KEY_SETTING2(n_key_launch_ship, '1', NO, NO, gvFunctionKey1, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_screen_options, '2', NO, NO, gvFunctionKey2, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_screen_equipship, '3', NO, NO, gvFunctionKey3, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_screen_interfaces, '4', NO, NO, gvFunctionKey4, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_screen_status, '5', NO, NO, gvFunctionKey5, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_chart_screens, '6', NO, NO, gvFunctionKey6, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_system_data, '7', NO, NO, gvFunctionKey7, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_market, '8', NO, NO, gvFunctionKey8, NO, NO);

	LOAD_KEY_SETTING2(n_key_gui_arrow_left, gvArrowKeyLeft, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_arrow_right, gvArrowKeyRight, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_arrow_up, gvArrowKeyUp, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_arrow_down, gvArrowKeyDown, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_page_up, gvPageUpKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_page_down, gvPageDownKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_gui_select, 13, NO, NO, gvNumberPadKeyEnter, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_increase_speed, 'w', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_decrease_speed, 's', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_inject_fuel, 'i', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_fire_lasers, 'a', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_weapons_online_toggle, '_', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_launch_missile, 'm', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_next_missile, 'y', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_ecm, 'e', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_prime_next_equipment, 'N', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_prime_previous_equipment, 'N', YES, YES, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_activate_equipment, 'n', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_mode_equipment, 'b', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_fastactivate_equipment_a, '0', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_fastactivate_equipment_b, 9, NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_target_missile, 't', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_untarget_missile, 'u', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_target_incoming_missile, 'T', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_ident_system, 'r', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_scanner_zoom, 'z', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_scanner_unzoom, 'Z', YES, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_launch_escapepod, 27, NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_galactic_hyperspace, 'g', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_hyperspace, 'h', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_jumpdrive, 'j', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_dump_cargo, 'D', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_rotate_cargo, 'R', YES, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_autopilot, 'c', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_autodock, 'C', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_docking_clearance_request, 'L', YES, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_snapshot, '*', YES, NO, gvNumberPadKeyMultiply, NO, NO);
	LOAD_KEY_SETTING2(n_key_docking_music, 's', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_advanced_nav_array_next, '^', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_advanced_nav_array_previous, '^', YES, YES, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_home, gvHomeKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_end, gvEndKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_next_system, gvArrowKeyRight, NO, NO, gvArrowKeyDown, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_previous_system, gvArrowKeyLeft, NO, NO, gvArrowKeyUp, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_zoom_in, gvPageDownKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_zoom_out, gvPageUpKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_map_info, 'i', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_chart_highlight, '?', YES, NO, 0, NO, NO);

	LOAD_KEY_SETTING2(n_key_system_home, gvHomeKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_system_end, gvEndKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_system_next_system, gvArrowKeyRight, NO, NO, gvArrowKeyDown, NO, NO);
	LOAD_KEY_SETTING2(n_key_system_previous_system, gvArrowKeyLeft, NO, NO, gvArrowKeyUp, NO, NO);

	LOAD_KEY_SETTING2(n_key_pausebutton, 'p', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_show_fps, 'F', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_bloom_toggle, gvFunctionKey9, YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_mouse_control_roll, 'M', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_mouse_control_yaw, 'M', YES, YES, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_hud_toggle, 'o', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_comms_log, '`', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_prev_compass_mode, '|', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_next_compass_mode, '\\', NO, NO, 0, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_market_filter_cycle, '?', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_market_sorter_cycle, '/', NO, NO, gvNumberPadKeyDivide, NO, NO);
	LOAD_KEY_SETTING2(n_key_market_buy_one, gvArrowKeyRight, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_market_sell_one, gvArrowKeyLeft, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_market_buy_max, gvArrowKeyRight, YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_market_sell_max, gvArrowKeyLeft, YES, NO, 0, NO, NO);

	LOAD_KEY_SETTING2(n_key_cycle_next_mfd, ';', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_cycle_previous_mfd, ';', NO, YES, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_switch_next_mfd, ':', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_switch_previous_mfd, ':', YES, YES, 0, NO, NO);

	LOAD_KEY_SETTING2(n_key_next_target, '+', YES, NO, gvNumberPadKeyPlus, NO, NO);
	LOAD_KEY_SETTING2(n_key_previous_target, '-', NO, NO, gvNumberPadKeyMinus, NO, NO);
	
	LOAD_KEY_SETTING2(n_key_custom_view, 'v', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_zoom_out, gvPageDownKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_zoom_in, gvPageUpKey, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_roll_left, gvArrowKeyLeft, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_pan_left, gvArrowKeyLeft, YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_roll_right, gvArrowKeyRight, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_pan_right, gvArrowKeyRight, YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_rotate_up, gvArrowKeyUp, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_pan_up, gvArrowKeyUp, YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_rotate_down, gvArrowKeyDown, NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_pan_down, gvArrowKeyDown, YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_rotate_left, ',', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_custom_view_rotate_right, '.', NO, NO, 0, NO, NO);

	LOAD_KEY_SETTING2(n_key_oxzmanager_setfilter, 'f', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_oxzmanager_showinfo, 'i', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_oxzmanager_extract, 'x', NO, NO, 0, NO, NO);
	
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	LOAD_KEY_SETTING2(n_key_inc_field_of_view, 'l', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_dec_field_of_view, 'k', NO, NO, 0, NO, NO);
#endif

#ifndef NDEBUG
	LOAD_KEY_SETTING2(n_key_dump_target_state, 'H', YES, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_dump_entity_list, '0', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_debug_full, 'd', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_debug_collision, 'b', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_debug_console_connect, 'c', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_debug_bounding_boxes, 'x', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_debug_shaders, 's', NO, NO, 0, NO, NO);
	LOAD_KEY_SETTING2(n_key_debug_off, 'n', NO, NO, 0, NO, NO);
#endif

	keyconfig2_settings = std::move(kdic2);
}


oo::PList PlayerEntity::processKeyCode(const oo::PList &key_def)
{
	oo::PList::Array newList;

	for (std::size_t i = 0; i < key_def.count(); i++)
	{
		const oo::PList &def = *key_def.at(i);
		if (def.count() == 0) continue; // skip this if the definition is empty
		const oo::PList *value = def.find("key");
		// -intValue: a string's leading integer, a number truncated, nil 0
		int iValue = 0;
		if (value != nullptr && value->isString())  iValue = oo::str::intValue(*value->getIf<std::string>());
		else if (value != nullptr)  iValue = static_cast<int>(value->int64Value());

		// we're going to fully expand all the shift/mod1/mod2 properties for all the key setting with defaults
		// to avoid the need to check for the presence of a property during game loops
		oo::PList::Dict defNew;
		for (const char *modifier : { "shift", "mod1", "mod2" })
		{
			const oo::PList *setting = def.find(modifier);
			defNew[modifier] = setting != nullptr ? *setting : oo::PList(false);
		}

		//	for '0' '1' '2' '3' '4' '5' '6' '7' '8' '9' - we want to interpret those as strings - not numbers
		//	alphabetical characters and symbols will return an intValue of 0.
		
		if (value != nullptr && value->isString() && (iValue < 10))
		{
			const std::string &keystring = *value->getIf<std::string>();
			const std::size_t length = oo::str::length(keystring);	// UTF-16 units, as -length

			// check for a named lookup
			if (length != 0)
			{
				const auto lookup = keyCodeLookups.find(oo::str::lowercase(keystring));
				int checkVal = lookup != keyCodeLookups.end() ? lookup->second : 0;
				if (checkVal > 0) {
					iValue = checkVal;

					defNew["key"] = oo::PList::unsignedInteger(iValue);	// was +numberWithUnsignedShort:
					newList.push_back(oo::PList(std::move(defNew)));
					continue;
				}
			}

			unsigned char	keychar;
			if (length == 1 || (iValue == 0 && length != 0))
			{
				keychar = oo::utf8ToUtf16(keystring)[0] & 0x00ff; // uses lower byte of unichar
			}
			else if (iValue <= 0xFF) keychar = iValue;
			else {
				OO_LOG_WARN("testing", "continue hit for key {}.", oo::DescriptionOf(nil));
				defNew["key"] = *value;
				newList.push_back(oo::PList(std::move(defNew)));
				continue;
			}
		
			defNew["key"] = oo::PList::unsignedInteger(keychar);	// was +numberWithUnsignedShort:
			newList.push_back(oo::PList(std::move(defNew)));
		} 
		else 
		{
			if (value != nullptr)  defNew["key"] = *value;	// (a missing key raised in -setObject:forKey:)
			newList.push_back(oo::PList(std::move(defNew)));
		}
	}

	return oo::PList(std::move(newList));
}


// special case for navigation keys - these keys cannot use mod keys, so they can't be impacted by multiple keypresses
bool PlayerEntity::checkNavKeyPress(const oo::PList &key_def)
{
	::MyOpenGLView  *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	for (std::size_t i = 0; i < key_def.count(); i++)
	{
		const oo::PList *def = key_def.at(i);
		if (def == nullptr)  continue;	// not an array of definitions
		if ((gameView != nullptr ? gameView->isDown(def->get<int>("key")) : false)) return YES;
	}
	return NO;
}


bool PlayerEntity::checkKeyPress(const oo::PList &key_def)
{
	return checkKeyPress(key_def, NO, NO);
}


bool PlayerEntity::checkKeyPress(const oo::PList &key_def, bool fKey_only)
{
	return checkKeyPress(key_def, fKey_only, NO);
}


bool PlayerEntity::checkKeyPressIgnoreCtrl(const oo::PList &key_def, bool ignore_ctrl)
{
	return checkKeyPress(key_def, NO, ignore_ctrl);
}


bool PlayerEntity::checkKeyPress(const oo::PList &key_def, bool fKey_only, bool ignore_ctrl)
{
	::MyOpenGLView  *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	for (std::size_t i = 0; i < key_def.count(); i++)
	{
		const oo::PList *def = key_def.at(i);
		if (def == nullptr)  continue;	// not an array of definitions
		int keycode = def->get<int>("key");
		// skip normal keys if the fKey_only flag is set
		// note: if the player has remapped the gui screen keys to not include function keys, they will not be able to
		// switch screens directly (they would need to finish the task - ie press enter, or use the escape key to cancel the function)
		// note: the logic below now means that the state of the modifiers must match the requirements for the key binding, including
		// when all settings are off. This means, if the player presses two functions at once, one that requires a modifier and
		// one that doesn't, the one that doesn't will not be triggered.
		if (fKey_only == YES && (keycode < gvFunctionKey1 || keycode > gvFunctionKey11)) continue;
		if ((gameView != nullptr ? gameView->isDown(keycode) : false)
			&& (def->get<bool>("shift") == static_cast<bool>((gameView != nullptr ? gameView->isShiftDown() : false)))
			&& (ignore_ctrl || (def->get<bool>("mod1") == static_cast<bool>((gameView != nullptr ? gameView->isCtrlDown() : false))))
			&& (def->get<bool>("mod2") == static_cast<bool>((gameView != nullptr ? gameView->isOptDown() : false)))
		) return YES;
	}
	return NO;
}


int PlayerEntity::getFirstKeyCode(const oo::PList &key_def)
{
	const oo::PList *def = key_def.at(0);
	return (def != nullptr) ? def->get<int>("key") : 0;
}


void PlayerEntity::getPollControls(double delta_t)
{
	::MyOpenGLView  *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	const char *exceptionContext = "setup";
	
	try
	{
		if (gameView)
		{
			// poll the gameView keyboard things
			exceptionContext = "pollApplicationControls";
			pollApplicationControls(); // quit command-f etc.
			switch (status())
			{
				case STATUS_WITCHSPACE_COUNTDOWN:
				case STATUS_IN_FLIGHT:
					exceptionContext = "pollFlightControls";
					pollFlightControls(delta_t);
					break;
					
				case STATUS_DEAD:
					exceptionContext = "pollGameOverControls";
					pollGameOverControls(delta_t);
					break;
					
				case STATUS_AUTOPILOT_ENGAGED:
					exceptionContext = "pollAutopilotControls";
					pollAutopilotControls(delta_t);
					break;
					
				case STATUS_DOCKED:
					exceptionContext = "pollDockedControls";
					pollDockedControls(delta_t);
					break;
					
				case STATUS_START_GAME:
					exceptionContext = "pollDemoControls";
					pollDemoControls(delta_t);
					break;
					
				default:
					// don't poll extra controls at any other times.
					break;
			}
		}
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG(cxx_kOOLogException, "***** Exception checking controls [{}]: {} : {}", exceptionContext, exception->name(), exception->reason());
	}
}

// The GUI row a mouse click activates (bead oo-3rb.348). UNIVERSE->cursor_row is only recomputed
// when the GUI is RENDERED, so after a stall the motion events and the click arrive in one tick and
// cursor_row is still the row of the last render, not the row under the pointer (a click aimed at
// row 26 activated row 22, which the pointer had crossed on its way). On an interactive GUI screen,
// ask the GUI for the row under the pointer as it is now, with the same maths the render uses.
// The universe, its game controller and view, and the GUI are read through their C++ parts (a nil
// controller or view answered as a message to nil did: no interaction mode, a zero position).
static int ClickedGUIRow(GuiDisplayGen *gui)
{
	Universe *universe = UNIVERSE;
	if (universe == nullptr)  return 0;
	GameController *controller = universe->gameController();
	if (controller != nullptr && controller->mouseInteractionMode() == MOUSE_MODE_UI_SCREEN_WITH_INTERACTION && gui != nullptr)
	{
		MyOpenGLView *view = universe->getGameView();
		return gui->rowAtVirtualJoystickPosition(view != nullptr ? view->getVirtualJoystickPosition() : NSPoint{});
	}
	return universe->cursor_row;
}


// DJS + aegidian: Moved from the big switch/case block in pollGuiArrowKeyControls
bool PlayerEntity::handleGUIUpDownArrowKeys()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	BOOL			result = NO;
	BOOL			arrow_up = checkKeyPress(n_key_gui_arrow_up); 
	BOOL			arrow_down = checkKeyPress(n_key_gui_arrow_down); 
	BOOL			mouse_click = (gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false);
	BOOL			mouse_dbl_click = (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false);

	if (arrow_down)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if (gui->setNextRow(+1))
			{
				result = YES;
			}
			else
			{
				if (gui->setFirstSelectableRow())  result = YES;
			}
			
			if (result && gui->getSelectableRange().length > 1)  playMenuNavigationDown();
			else  playMenuNavigationNot();
			
			timeLastKeyPress = script_time;
		}
	}
	
	if (arrow_up)
	{
		if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			if (gui->setNextRow(-1))
			{
				result = YES;
			}
			else
			{
				if (gui->setLastSelectableRow())  result = YES;
			}

			if (result && gui->getSelectableRange().length > 1)  playMenuNavigationUp();
			else  playMenuNavigationNot();

			timeLastKeyPress = script_time;
		}
	}
	
	if (mouse_click)
	{
		if (!upDownKeyPressed)
		{
			int click_row = ClickedGUIRow(gui);
			if (gui->setSelectedRow(click_row))
			{
				result = YES;
			}
		}
	}
	if (mouse_dbl_click)
	{
		int click_row = ClickedGUIRow(gui);
		if (gui->setSelectedRow(click_row))
		{
			result = YES;
		}
		else
		{
			// if double-clicked on an unselectable row, clear the
			// state so it doesn't activate whatever was last
			// selected
			if (gameView != nullptr)  gameView->clearMouse();
		}
	}

	
	upDownKeyPressed = (arrow_up || arrow_down || mouse_click);
	
	return result;
}


void PlayerEntity::targetNewSystem(int direction, bool whileTyping)
{
	target_system_id = UNIVERSE->getGui()->targetNextFoundSystem(direction);
	setInfoSystemID(target_system_id, YES);
	cursor_coordinates = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(target_system_id, galaxy_number) : NSMakePoint(0, 0));

	found_system_id = target_system_id;
	if (!whileTyping)
	{
		clearPlanetSearchString();
	}
	cursor_moving = YES;
}


void PlayerEntity::clearPlanetSearchString()
{
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetTypedString();
	planetSearchString.reset();
}


void PlayerEntity::targetNewSystem(int direction)
{
	targetNewSystem(direction, NO);
}


void PlayerEntity::switchToMainView()
{
	OOGUIScreenID oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_MAIN;
	if (showDemoShips)
	{
		setShowDemoShips(NO);
		if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
	}
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->allowStringInput(NO);
	if (isMouseControlOn())  { if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetMouse(); }
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);
	noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::noteSwitchToView(OOViewID toView, OOViewID fromView)
{
	switchToThisView(toView, fromView, NO, YES); // no extra processing needed!
}


void PlayerEntity::beginWitchspaceCountdown(int spin_time)
{
	if (hasHyperspaceMotor()) 
	{
		if (spin_time == 0) 
		{
			witchspaceCountdown = hyperspaceMotorSpinTime;
		}
		else 
		{
#ifndef OO_DUMP_PLANETINFO
			if (spin_time < 5) 
			{
				witchspaceCountdown = 5;
			} 
			else 
#endif
			{
				witchspaceCountdown = spin_time;
			}
		}
		setStatus(STATUS_WITCHSPACE_COUNTDOWN);
		playStandardHyperspace();
		// say it!
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		int seconds = round(witchspaceCountdown);
		const std::string destination = (UNIVERSE != nullptr ? UNIVERSE->getSystemName(nextHopTargetSystemID()) : std::optional<std::string>()).value_or("");
		if (UNIVERSE != nullptr)  UNIVERSE->displayCountdownMessage(ExpandKeyWithArguments("witch-to-x-in-y-seconds", { { "seconds", oo::PList::signedInteger(seconds) }, { "destination", oo::PList(destination) } }), 1.0);
		doScriptEvent(OOJSID("playerStartedJumpCountdown"), { oo::PList("standard"), oo::PList::singleReal(static_cast<float>(witchspaceCountdown)) });
		if (UNIVERSE != nullptr)  UNIVERSE->preloadPlanetTexturesForSystem(target_system_id);
	}
}


void PlayerEntity::beginWitchspaceCountdown()
{
	if (hasHyperspaceMotor()) {
		beginWitchspaceCountdown(hyperspaceMotorSpinTime);
	}
}


void PlayerEntity::cancelWitchspaceCountdown()
{
	if (status() == STATUS_WITCHSPACE_COUNTDOWN) {
		setStatus(STATUS_IN_FLIGHT);
		playHyperspaceAborted();
	}
	// say it!
	if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
	doScriptEvent(OOJSID("playerCancelledJumpCountdown"));
}


void PlayerEntity::pollApplicationControls()
{
	if (!pollControls) return;
	
	const char *exceptionContext = "setup";
	
	// does fullscreen / quit / snapshot
	::MyOpenGLView  *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GameController *gameController = (UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr);
	
	BOOL onTextEntryScreen = (gui_screen == GUI_SCREEN_LONG_RANGE_CHART) || (gui_screen == GUI_SCREEN_MISSION) || 
		(gui_screen == GUI_SCREEN_SAVE) || (gui_screen == GUI_SCREEN_OXZMANAGER || (gui_screen == GUI_SCREEN_KEYBOARD_ENTRY));

	try
	{
	//  command-key controls
	#if !OOLITE_MAC_OS_X || !OOLITE_64_BIT	// On 64-bit Macs, these are handled by normal menu shortcuts.
		if ((gameController != nullptr ? gameController->inFullScreenMode() : false))
		{
			exceptionContext = "command key controls";
			if ((gameView != nullptr ? gameView->isCommandFDown() : false))
			{
				if (gameView != nullptr)  gameView->clearCommandF();
				if (gameController != nullptr)  gameController->exitFullScreenMode();
				if (mouse_control_on)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("mouse-off"), 3.0);
					mouse_control_on = NO;
				}
			}
			
			if ((gameView != nullptr ? gameView->isCommandQDown() : false))
			{
				// The target was the controller's object; the controller is C++ (bead oo-9ht.164), and on SDL the pair is kept, never performed: nil.
				if (gameController != nullptr)  gameController->pauseFullScreenModeToPerform("exitAppCommandQ", nil);
			}
		}
	#endif
		
		// handle pressing Q or [esc] in error-handling mode
		if (status() == STATUS_HANDLING_ERROR)
		{
			exceptionContext = "error handling mode";
			if ((gameView != nullptr ? gameView->isDown(113) : false)||(gameView != nullptr ? gameView->isDown(81) : false)||(gameView != nullptr ? gameView->isDown(27) : false))   // 'q' | 'Q' | esc
			{
				if (gameController != nullptr)  gameController->exitAppWithContext("Q or escape pressed in error handling mode");
			}
		}
		
		if ((gameController != nullptr ? gameController->isGamePaused() : false))
		{
			// What's the status?
			switch (status())
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
						if (gameView != nullptr)  gameView->allowStringInput(NO);
						if ((UNIVERSE != nullptr ? UNIVERSE->pauseMessageVisible() : false))
						{
							if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();	// remove the 'paused' message.
						}
						if (gameController != nullptr)  gameController->setGamePaused(NO);
					}
					break;
			}
			
		}
		
		// snapshot
		const BOOL *joyButtonState = OOJoystickManager::sharedStickHandler()->getAllButtonStates();

		if ((checkKeyPress(n_key_snapshot) || joyButtonState[BUTTON_SNAPSHOT]) &&
			((gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}) <= gvStringInputAlpha) && // not while entering text on the keyboard config screens
			!::OOOXZManager::sharedManager()->isAcceptingTextInput())   //  '*' key but not while filtering inside OXZ Manager
		{
			exceptionContext = "snapshot";
			if (!taking_snapshot)
			{
				taking_snapshot = YES;
				if (gameView != nullptr)  gameView->snapShot(std::nullopt); // nil filename so that the program auto-names the snapshot
			}
		}
		else
		{
			taking_snapshot = NO;
		}
		
		// FPS display
		if (!onTextEntryScreen && checkKeyPress(n_key_show_fps))   //  'F' key
		{
			exceptionContext = "toggle FPS";
			if (!f_key_pressed)  { if (UNIVERSE != nullptr)  UNIVERSE->setDisplayFPS(!(UNIVERSE != nullptr ? UNIVERSE->getDisplayFPS() : false)); }
			f_key_pressed = YES;
		}
		else
		{
			f_key_pressed = NO;
		}
		
		// bloom toggle
		if (checkKeyPress(n_key_bloom_toggle))
		{
			if (!f9_key_pressed)
			{
				BOOL oldBloom = (UNIVERSE != nullptr ? UNIVERSE->bloom() : false);
				if (UNIVERSE != nullptr)  UNIVERSE->setBloom(!oldBloom);
			}
			f9_key_pressed = YES;
		}
		else
		{
			f9_key_pressed = NO;
		}
		
		// Mouse control
		BOOL allowMouseControl;
	#if OO_DEBUG
		allowMouseControl = YES;
	#else
		allowMouseControl = (gameController != nullptr ? gameController->inFullScreenMode() : false) ||
					oo::Defaults::standard().boolForKey("mouse-control-in-windowed-mode");
	#endif
		
		if (allowMouseControl)
		{
			exceptionContext = "mouse control";
			if (!onTextEntryScreen && (checkKeyPress(n_key_mouse_control_roll) || checkKeyPress(n_key_mouse_control_yaw)))   //  'M' key
			{
				if (!m_key_pressed)
				{
					mouse_control_on = !mouse_control_on;
					if (mouse_control_on)
					{
						if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("mouse-on"), 3.0);
						/*	Ensure the keyboard pitch override (intended to lock
						 out the joystick if the player runs to the keyboard)
						 is reset */
					#if OOLITE_GNUSTEP
						if (gameView != nullptr)  gameView->resetMouse();
						if (oo::Defaults::standard().boolForKey("grab-mouse-on-mouse-control"))
						{
							if (gameView != nullptr)  gameView->grabMouseInsideGameWindow(YES);
						}
					#endif
						mouse_x_axis_map_to_yaw = checkKeyPress(n_key_mouse_control_yaw);
						keyboardRollOverride = (mouse_x_axis_map_to_yaw != NO);   // Getafix: set keyboardRollOverride to TRUE only if yaw is mapped to mouse x-axis
						keyboardPitchOverride = NO;
						keyboardYawOverride = !keyboardRollOverride;
					}
					else
					{
						if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("mouse-off"), 3.0);
                    #if OOLITE_GNUSTEP
						if (gameView != nullptr)  gameView->grabMouseInsideGameWindow(NO);
                    #endif
					}
				}
				if (OOMouseInteractionModeIsFlightMode((gameController != nullptr ? gameController->mouseInteractionMode() : OOMouseInteractionMode{})))
				{
					if (gameController != nullptr)  gameController->setMouseInteractionModeForFlight();
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
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("mouse-off"), 3.0);
            #if OOLITE_GNUSTEP
				if (gameView != nullptr)  gameView->grabMouseInsideGameWindow(NO);
            #endif
				
				if (OOMouseInteractionModeIsFlightMode((gameController != nullptr ? gameController->mouseInteractionMode() : OOMouseInteractionMode{})))
				{
					if (gameController != nullptr)  gameController->setMouseInteractionModeForFlight();
				}
			}
		}
		
		// HUD toggle
		if ((checkKeyPress(n_key_hud_toggle) || joyButtonState[BUTTON_TOGGLEHUD]) && (gameController != nullptr ? gameController->isGamePaused() : false) && !onTextEntryScreen)	// 'o' key while paused
		{
			exceptionContext = "toggle HUD";
			if (!hide_hud_pressed)
			{
				::HeadUpDisplay *theHUD = getHud();
				theHUD->setHidden(!theHUD->isHidden());
				if (gui_screen == GUI_SCREEN_STATUS)
				{
					// ensure refresh of status page screen if looking at it
					setGuiToStatusScreen();
				}
			}
			hide_hud_pressed = YES;
		}
		else
		{
			hide_hud_pressed = NO;
		}
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG(cxx_kOOLogException, "***** Exception in pollApplicationControls [{}]: {} : {}", exceptionContext, exception->name(), exception->reason());
	}
}


void PlayerEntity::pollFlightControls(double delta_t)
{
	::MyOpenGLView		*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();
	const char			*exceptionContext = "setup";

	try
	{
		exceptionContext = "joystick handling";
		const BOOL *joyButtonState = OOJoystickManager::sharedStickHandler()->getAllButtonStates();
		
		BOOL paused = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false);
		double speed_delta = SHIP_THRUST_FACTOR * thrust;
		
		if (!paused && gui_screen == GUI_SCREEN_MISSION)
		{
			exceptionContext = "mission screen";
			OOViewID view = VIEW_NONE;
			
			NSPoint			virtualView = NSZeroPoint;
			double			view_threshold = 0.5;
			
			if (stickHandler->joystickCount())
			{
				virtualView = stickHandler->viewAxis();
				if (virtualView.y == STICK_AXISUNASSIGNED)
					virtualView.y = 0.0;
				if (virtualView.x == STICK_AXISUNASSIGNED)
					virtualView.x = 0.0;
				if (fabs(virtualView.y) >= fabs(virtualView.x))
					virtualView.x = 0.0; // forward/aft takes precedence
				else
					virtualView.y = 0.0;
			}
		
			if (checkKeyPress(n_key_view_forward) || (virtualView.y < -view_threshold) || joyButtonState[BUTTON_VIEWFORWARD])
			{
				view = VIEW_FORWARD;
			}
			if (checkKeyPress(n_key_view_aft)|(virtualView.y > view_threshold)||joyButtonState[BUTTON_VIEWAFT])
			{
				view = VIEW_AFT;
			}
			if (checkKeyPress(n_key_view_port)||(virtualView.x < -view_threshold)||joyButtonState[BUTTON_VIEWPORT])
			{
				view = VIEW_PORT;
			}
			if (checkKeyPress(n_key_view_starboard)||(virtualView.x > view_threshold)||joyButtonState[BUTTON_VIEWSTARBOARD])
			{
				view = VIEW_STARBOARD;
			}
			if (view == VIEW_NONE)
			{
				// still in mission screen, process the input.
				pollDemoControls(delta_t);
			}
			else
			{
				UNIVERSE->getGui()->clearBackground();
				switchToThisView(view);
				if (_missionWithCallback)
				{
					doMissionCallback();
				}
				// notify older scripts, but do not trigger missionScreenOpportunity.
				doWorldEventUntilMissionScreen(OOJSID("missionScreenEnded"));
			}
		}
		else if (!paused)
		{
			exceptionContext = "arrow keys";
			// arrow keys
			if ((UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false))
				pollGuiArrowKeyControls(delta_t);
			else
				pollFlightArrowKeyControls(delta_t);
			
			//  view keys
			pollViewControls();
			
			if (OOMouseInteractionModeIsFlightMode((UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->mouseInteractionMode() : OOMouseInteractionMode{})))
			{
				exceptionContext = "afterburner";
				if ((joyButtonState[BUTTON_FUELINJECT] || checkKeyPress(n_key_inject_fuel)) &&
					hasFuelInjection() &&
					!hyperspeed_engaged)
				{
					if (fuel > 0 && !afterburner_engaged)
					{
						if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("fuel-inject-on"), 1.5);
						afterburner_engaged = YES;
						startAfterburnerSound();
					}
					else
					{
						if (fuel <= 0.0)
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("fuel-out"), 1.5);
					}
					afterburner_engaged = (fuel > 0);
				}
				else
					afterburner_engaged = NO;
				
				if ((!afterburner_engaged)&&(afterburnerSoundLooping))
					stopAfterburnerSound();
				
				exceptionContext = "thrust";
				// DJS: Thrust can be an axis or a button. Axis takes precidence.
				double reqSpeed=stickHandler->getAxisState(AXIS_THRUST);
				float mouseWheelDeltaFactor = mouse_control_on ? fabs((gameView != nullptr ? gameView->mouseWheelDelta() : 0.0f)) : 1.0f;
				if (mouseWheelDeltaFactor == 0.0f)  mouseWheelDeltaFactor = 1.0f;
				// Updated DJS original code to fix BUG #17482 - (Getafix 2010/09/13)
				if ((checkKeyPress(n_key_increase_speed) ||
						joyButtonState[BUTTON_INCTHRUST] ||
						 ((mouse_control_on)&&((gameView != nullptr ? gameView->mouseWheelState() : 0) == gvMouseWheelUp) && ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) <= VIEW_STARBOARD || !(gameView != nullptr ? gameView->isCapsLockOn() : false))))
					&& (flightSpeed < maxFlightSpeed) && (!afterburner_engaged))
				{
					flightSpeed += speed_delta * delta_t * mouseWheelDeltaFactor;
				}
				
				if ((checkKeyPress(n_key_decrease_speed) ||
						joyButtonState[BUTTON_DECTHRUST] ||
						((mouse_control_on)&&((gameView != nullptr ? gameView->mouseWheelState() : 0) == gvMouseWheelDown) && ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) <= VIEW_STARBOARD || !(gameView != nullptr ? gameView->isCapsLockOn() : false))))
					&& (!afterburner_engaged))
				{
					flightSpeed -= speed_delta * delta_t * mouseWheelDeltaFactor;	
					// ** tgape ** - decrease obviously means no hyperspeed
					hyperspeed_engaged = NO;
				}

				const oo::PList thrustAxes = stickHandler->axisFunctions();
				const oo::PList *functionForThrustAxis = thrustAxes.get<oo::PList::Dict>(std::to_string(AXIS_THRUST));	// nil: absent or not a Dict
				if(stickHandler->joystickCount() != 0 && functionForThrustAxis != nullptr)
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
				
				if (!afterburner_engaged && !atHyperspeed() && !hyperspeed_engaged)
				{
					flightSpeed = OOClamp_0_max_f(flightSpeed, maxFlightSpeed);
				}
				
				exceptionContext = "hyperspeed";
				//  hyperspeed controls
				if (checkKeyPress(n_key_jumpdrive) || joyButtonState[BUTTON_HYPERSPEED])		// 'j'
				{
					if (!jump_pressed)
					{
						if (!hyperspeed_engaged)
						{
							hyperspeed_locked = (massLocked() != NO);
							hyperspeed_engaged = !hyperspeed_locked;
							if (hyperspeed_locked)
							{
								playJumpMassLocked();
								if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("jump-mass-locked"), 1.5);
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
				
				exceptionContext = "shoot";
				//  shoot 'a'
				if (((checkNavKeyPress(n_key_fire_lasers))||((mouse_control_on)&&((gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false)) && ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) <= VIEW_STARBOARD || !(gameView != nullptr ? gameView->isCapsLockOn() : false)))||joyButtonState[BUTTON_FIRE])&&(shot_time > weapon_recharge_rate))
				{
					if (fireMainWeapon())
					{
						playLaserHit((shipHitByLaser() != nil), currentLaserOffset().at(0), (currentWeapon() != nullptr ? currentWeapon()->identifier() : std::optional<std::string>()).value_or(""));
					}
				}
				
				exceptionContext = "weapons online toggle";
				// weapons online / offline toggle '_'
				if ((checkKeyPress(n_key_weapons_online_toggle) || joyButtonState[BUTTON_WEAPONSONLINETOGGLE]))
				{
					if (!weaponsOnlineToggle_pressed)
					{
						std::string	weaponsOnlineToggleMsg;

						setWeaponsOnline(!weaponsOnline());
						weaponsOnlineToggleMsg = (weaponsOnline() ? OO_DESC("weapons-systems-online") : OO_DESC("weapons-systems-offline"));
						if (weaponsOnline())
						{
							playWeaponsOnline();
						}
						else
						{
							playWeaponsOffline();
						}
						if (UNIVERSE != nullptr)  UNIVERSE->addMessage(weaponsOnlineToggleMsg, 2.0);
						doScriptEvent(OOJSID("weaponsSystemsToggled"), { oo::PList(static_cast<bool>(weaponsOnline())) });
						weaponsOnlineToggle_pressed = YES;
					}
				}
				else  weaponsOnlineToggle_pressed = NO;
				
				exceptionContext = "missile fire";
				//  shoot 'm'   // launch missile
				if (checkKeyPress(n_key_launch_missile) || joyButtonState[BUTTON_LAUNCHMISSILE])
				{
					// launch here
					if (!fire_missile_pressed)
					{
						fireMissile();
						fire_missile_pressed = YES;
					}
				}
				else  fire_missile_pressed = NO;
				
				exceptionContext = "next missile";
				//  shoot 'y'   // next missile
				if (checkKeyPress(n_key_next_missile) || joyButtonState[BUTTON_CYCLEMISSILE])
				{
					if (!ident_engaged && !next_missile_pressed && weaponsOnline())
					{
						playNextMissileSelected();
						selectNextMissile();
					}
					next_missile_pressed = YES;
				}
				else  next_missile_pressed = NO;
				
				exceptionContext = "next target";
				//	'+' // next target
				if (checkKeyPress(n_key_next_target) || joyButtonState[BUTTON_NEXTTARGET])
				{
					if ((!next_target_pressed)&&(hasEquipmentItemProviding("EQ_TARGET_MEMORY")))
					{
						moveTargetMemoryBy(+1);
					}
					next_target_pressed = YES;
				}
				else  next_target_pressed = NO;
				
				exceptionContext = "previous target";
				//	'-' // previous target
				if (checkKeyPress(n_key_previous_target) || joyButtonState[BUTTON_PREVTARGET])
				{
					if ((!previous_target_pressed)&&(hasEquipmentItemProviding("EQ_TARGET_MEMORY")))
					{
						moveTargetMemoryBy(-1);
					}
					previous_target_pressed = YES;
				}
				else  previous_target_pressed = NO;
				
				exceptionContext = "ident R";
				//  shoot 'r'   // switch on ident system
				if (checkKeyPress(n_key_ident_system) || joyButtonState[BUTTON_ID])
				{
					// ident 'on' here
					if (!ident_pressed)
					{
						handleButtonIdent();
					}
					ident_pressed = YES;
				}
				else  ident_pressed = NO;
				
				exceptionContext = "prime equipment";
				// prime equipment 'N' - selects equipment to use with keypress
				if (checkKeyPress(n_key_prime_next_equipment) || checkKeyPress(n_key_prime_previous_equipment) || joyButtonState[BUTTON_PRIMEEQUIPMENT] || joyButtonState[BUTTON_PRIMEEQUIPMENT_PREV])
				{

					if (!prime_equipment_pressed)
					{

						// cycle through all the relevant equipment.
						NSUInteger c = eqScripts.size();
						
						// if Ctrl is held down at the same time as the prime equipment key,
						// cycle relevant equipment in reverse
						//if (![gameView isCtrlDown])
						if (!checkKeyPress(n_key_prime_previous_equipment) || joyButtonState[BUTTON_PRIMEEQUIPMENT_PREV])
						{
							primedEquipment++;
							if (primedEquipment > c) primedEquipment = 0;
						}
						else
						{
							if (primedEquipment > 0)  primedEquipment--;
							else  primedEquipment = c;
						}
						
						std::string eqKey;

						if (primedEquipment == c)
						{
							if (c > 0)
							{
								playNextEquipmentSelected();
								if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("equipment-primed-none"), 2.0);
							}
							else { if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("equipment-primed-none-available"), 2.0); }
						}
						else
						{
							playNextEquipmentSelected();
							eqKey = eqScripts[primedEquipment].first;
							const std::string equipmentName = (OOEquipmentType::equipmentTypeWithIdentifier(eqKey).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(eqKey).get()->name() : std::optional<std::string>()).value_or(std::string());
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithArguments("equipment-primed", { { "equipmentName", oo::PList(equipmentName) } }), 2.0);
						}
						doScriptEvent(OOJSID("playerChangedPrimedEquipment"), { oo::PList(eqKey) });
					}
					prime_equipment_pressed = YES;
					
				}
				else  prime_equipment_pressed = NO;
				
				exceptionContext = "activate equipment";
				// activate equipment 'n' - runs the activated() function inside the equipment's script.
				if (checkKeyPress(n_key_activate_equipment) || joyButtonState[BUTTON_ACTIVATEEQUIPMENT])
				{
					if (!activate_equipment_pressed)
					{
						activatePrimableEquipment(primedEquipment, OOPRIMEDEQUIP_ACTIVATED);
					}
					activate_equipment_pressed = YES;
				}
				else  activate_equipment_pressed = NO;
				
				exceptionContext = "mode equipment";
				// mode equipment 'b' - runs the mode() function inside the equipment's script.
				if (checkKeyPress(n_key_mode_equipment) || joyButtonState[BUTTON_MODEEQUIPMENT])
				{
					if (!mode_equipment_pressed)
					{
						activatePrimableEquipment(primedEquipment, OOPRIMEDEQUIP_MODE);
					}
					mode_equipment_pressed = YES;
				}
				else  mode_equipment_pressed = NO;

				exceptionContext = "fast equipment A";
				if (checkKeyPress(n_key_fastactivate_equipment_a) || joyButtonState[BUTTON_CLOAK])
				{
					if (!fastactivate_a_pressed)
					{
						activatePrimableEquipment(eqScriptIndexForKey(fastEquipmentA().value_or("")), OOPRIMEDEQUIP_ACTIVATED);
					}
					fastactivate_a_pressed = YES;
				}
				else fastactivate_a_pressed = NO;

				exceptionContext = "fast equipment B";
				if (checkKeyPress(n_key_fastactivate_equipment_b) || joyButtonState[BUTTON_ENERGYBOMB])
				{
					if (!fastactivate_b_pressed)
					{
						activatePrimableEquipment(eqScriptIndexForKey(fastEquipmentB().value_or("")), OOPRIMEDEQUIP_ACTIVATED);
					}
					fastactivate_b_pressed = YES;
				}
				else fastactivate_b_pressed = NO;

				exceptionContext = "custom equipment";
				// loop through all the objects in the customEquipActivation array
				for (std::size_t i = 0; i < customEquipActivation.size(); i++)
				{
					const oo::PList &item = customEquipActivation[i];
					const std::string equipKey = item.get<std::string>(std::string(CUSTOMEQUIP_EQUIPKEY));
					// check if the player has the equip item installed
					if (hasOneEquipmentItem(equipKey, NO, NO))
					{
						const oo::PList *key_act = item.get<oo::PList::Array>(std::string(CUSTOMEQUIP_KEYACTIVATE));
						const oo::PList *key_mod = item.get<oo::PList::Array>(std::string(CUSTOMEQUIP_KEYMODE));
						const oo::PList *but_act = item.get<oo::PList::Dict>(std::string(CUSTOMEQUIP_BUTTONACTIVATE));
						const oo::PList *but_mod = item.get<oo::PList::Dict>(std::string(CUSTOMEQUIP_BUTTONMODE));
						// if so,
						// check to see if the key or button was pressed for activate
						if ((key_act != nullptr && checkKeyPress(*key_act)) || (but_act != nullptr && OOJoystickManager::sharedStickHandler()->isButtonDown(but_act->get<int>(std::string(STICK_AXBUT)), but_act->get<int>(std::string(STICK_NUMBER)))))
						{
							if (!customActivatePressed[i])
							{
								// initate the activate JS code
								activatePrimableEquipment(eqScriptIndexForKey(equipKey), OOPRIMEDEQUIP_ACTIVATED);
							}
							customActivatePressed[i] = YES;
						}
						else customActivatePressed[i] = NO;

						// check to see if the key or button was pressed for mode
						if ((key_mod != nullptr && checkKeyPress(*key_mod)) || (but_mod != nullptr && OOJoystickManager::sharedStickHandler()->isButtonDown(but_mod->get<int>(std::string(STICK_AXBUT)), but_mod->get<int>(std::string(STICK_NUMBER)))))
						{
							if (!customModePressed[i])
							{
								// initiate the activate JS code
								activatePrimableEquipment(eqScriptIndexForKey(equipKey), OOPRIMEDEQUIP_MODE);
							}
							customModePressed[i] = YES;
						}
						else customModePressed[i] = NO;
					}
				}

				exceptionContext = "incoming missile T";
				// target nearest incoming missile 'T' - useful for quickly giving a missile target to turrets
				if (checkKeyPress(n_key_target_incoming_missile) || joyButtonState[BUTTON_TARGETINCOMINGMISSILE])
				{
					if (!target_incoming_missile_pressed)
					{
						targetNearestIncomingMissile();
					}
					target_incoming_missile_pressed = YES;
				}
				else  target_incoming_missile_pressed = NO;
				
				exceptionContext = "missile T";
				//  shoot 't'   // switch on missile targeting
				if ((checkKeyPress(n_key_target_missile) || joyButtonState[BUTTON_ARMMISSILE])&&(missile_entity[activeMissile]))
				{
					// targeting 'on' here
					if (!target_missile_pressed)
					{
						handleButtonTargetMissile();
					}
					target_missile_pressed = YES;
				}
				else  target_missile_pressed = NO;
				
				exceptionContext = "missile U";
				//  shoot 'u'   // disarm missile targeting
				if (checkKeyPress(n_key_untarget_missile) || joyButtonState[BUTTON_UNARM])
				{
					if (!safety_pressed)
					{
						//targeting off in both cases!
						if (primaryTarget() != nil) noteLostTarget();
						_primaryTarget = nullptr;
						safeAllMissiles();
						if (!ident_engaged && weaponsOnline())
						{
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("missile-safe"), 2.0);
							playMissileSafe();
						}
						else
						{
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("ident-off"), 2.0);
							playIdentOff();
						}
						ident_engaged = NO;
					}
					safety_pressed = YES;
				}
				else  safety_pressed = NO;
				
				exceptionContext = "ECM";
				//  shoot 'e'   // ECM
				if ((checkKeyPress(n_key_ecm) || joyButtonState[BUTTON_ECM]) && hasECM())
				{
					if (!ecm_in_operation)
					{
						if (weaponsOnline() && fireECM())
						{
							playFiredECMSound();
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("ecm-on"), 3.0);
						}
					}
				}
				
			
				exceptionContext = "escape pod";
				//  shoot 'escape'   // Escape pod launch - NOTE: Allowed at all times, but requires double press within a specific time interval.
							// Double press not available in strict mode or when the "escape-pod-activation-immediate" override is in the 
							// user defaults file.
				if ((checkKeyPress(n_key_launch_escapepod) || joyButtonState[BUTTON_ESCAPE]) && hasEscapePod())
				{
					BOOL	goodToLaunch = oo::Defaults::standard().boolForKey("escape-pod-activation-immediate");
					static	OOTimeDelta 	escapePodKeyResetTime;
					
					if (!goodToLaunch)
					{
						if (!escapePodKey_pressed)
						{
							escapePodKey_pressed = YES;
							// first keypress will unregister in KEY_REPEAT_INTERVAL seconds
							escapePodKeyResetTime = oo::date::monotonicSeconds() + KEY_REPEAT_INTERVAL;
							//[gameView clearKey:key_launch_escapepod];
							if (gameView != nullptr)  gameView->clearKey(getFirstKeyCode(n_key_launch_escapepod));
							if (stickHandler->joystickCount())
							{
								stickHandler->clearStickButtonState(BUTTON_ESCAPE);
							}
						}
						else
						{
							OOTimeDelta timeNow = oo::date::monotonicSeconds();	// same clock as escapePodKeyResetTime
							escapePodKey_pressed = NO;
							if (timeNow < escapePodKeyResetTime)  goodToLaunch = YES;
						}
					}
					if (goodToLaunch)
					{
						launchEscapeCapsule();
					}
				}
				
				exceptionContext = "dump cargo";
				//  shoot 'd'   // Dump Cargo
				if ((checkKeyPress(n_key_dump_cargo) || joyButtonState[BUTTON_JETTISON]) && cargoCount() > 0)
				{
					dumpCargo();
				}
				
				exceptionContext = "rotate cargo";
				//  shoot 'R'   // Rotate Cargo
				if (checkKeyPress(n_key_rotate_cargo) || joyButtonState[BUTTON_ROTATECARGO])
				{
					if ((!rotateCargo_pressed)&&(cargoCount() > 0))
						rotateCargo();
					rotateCargo_pressed = YES;
				}
				else
					rotateCargo_pressed = NO;
				
				exceptionContext = "autopilot C";
				// autopilot 'c'
				if (checkKeyPress(n_key_autopilot) || joyButtonState[BUTTON_DOCKCPU])   // look for the 'c' key
				{
					if (hasDockingComputer() && (!autopilot_key_pressed))
					{
						handleAutopilotOn(false);
					}
					autopilot_key_pressed = YES;
				}
				else
					autopilot_key_pressed = NO;
				
				exceptionContext = "autopilot shift-C";
				// autopilot 'C' - fast-autopilot
				if (checkKeyPress(n_key_autodock) || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'C' key
				{
					if (hasDockingComputer() && (!fast_autopilot_key_pressed))
					{
						handleAutopilotOn(true);
					}
					fast_autopilot_key_pressed = YES;
				}
				else
				{
					fast_autopilot_key_pressed = NO;
				}
				
				exceptionContext = "docking clearance request";

				if (checkKeyPress(n_key_docking_clearance_request) || joyButtonState[BUTTON_DOCKINGCLEARANCE])
				{
					if (!docking_clearance_request_key_pressed)
					{
						Entity *primeTarget = primaryTarget();
						performDockingRequest(oo::ToStation(primeTarget));
					}
					docking_clearance_request_key_pressed = YES;
				}
				else
				{
					docking_clearance_request_key_pressed = NO;
				}
				
				exceptionContext = "hyperspace";
				// hyperspace 'h'
				if ( (checkKeyPress(n_key_hyperspace) || joyButtonState[BUTTON_HYPERDRIVE]) &&
					  hasHyperspaceMotor() )	// look for the 'h' key
				{
					if (!hyperspace_pressed)
					{
						if (status() == STATUS_WITCHSPACE_COUNTDOWN)
						{
							cancelWitchspaceCountdown();
							if (galactic_witchjump)
							{
								galactic_witchjump = NO;
								if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-user-galactic-abort"), 3.0);
							}
							else
							{
								if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-user-abort"), 3.0);
							}
						}
						else if (witchJumpChecklist(false))
						{
							beginWitchspaceCountdown(hyperspaceMotorSpinTime);
						}
					}
					hyperspace_pressed = YES;
				}
				else
					hyperspace_pressed = NO;
				
				exceptionContext = "galactic hyperspace";
				// Galactic hyperspace 'g'
				if ((checkKeyPress(n_key_galactic_hyperspace) || joyButtonState[BUTTON_GALACTICDRIVE]) &&
					(hasEquipmentItemProviding("EQ_GAL_DRIVE")))// look for the 'g' key
				{
					if (!galhyperspace_pressed)
					{
						if (status() == STATUS_WITCHSPACE_COUNTDOWN)
						{
							cancelWitchspaceCountdown();
							if (galactic_witchjump)
							{
								galactic_witchjump = NO;
								if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-user-galactic-abort"), 3.0);
							}
							else
							{
								if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("witch-user-abort"), 3.0);
							}
						}
						else
						{
							galactic_witchjump = YES;
							
							// even if we don't have a witchspace motor, we can still do a default galactic jump (!)
							if(EXPECT(hasHyperspaceMotor())) witchspaceCountdown = hyperspaceMotorSpinTime;
							else witchspaceCountdown = DEFAULT_HYPERSPACE_SPIN_TIME;
							
							setStatus(STATUS_WITCHSPACE_COUNTDOWN);
							playGalacticHyperspace();
							// say it!
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage(oo::str::formatRuntime(OO_DESC("witch-galactic-in-f-seconds"), { witchspaceCountdown }), 1.0);
							// FIXME: how to preload target system for hyperspace jump?
							
							doScriptEvent(OOJSID("playerStartedJumpCountdown"), { oo::PList("galactic"), oo::PList::singleReal(static_cast<float>(witchspaceCountdown)) });
						}
					}
					galhyperspace_pressed = YES;
				}
				else
					galhyperspace_pressed = NO;

			}

#if OO_FOV_INFLIGHT_CONTROL_ENABLED
			// Field of view controls
			if (!(UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false))
			{
				if ((checkKeyPress(n_key_inc_field_of_view) || joyButtonState[BUTTON_INC_FIELD_OF_VIEW]) && (fieldOfView < MAX_FOV))
				{
					fieldOfView *= pow(fov_delta, delta_t);
					if (fieldOfView > MAX_FOV)  fieldOfView = MAX_FOV;
				}

				if ((checkKeyPress(n_key_dec_field_of_view) || joyButtonState[BUTTON_DEC_FIELD_OF_VIEW]) && (fieldOfView > MIN_FOV))
				{
					fieldOfView /= pow(fov_delta, delta_t);
					if (fieldOfView < MIN_FOV)  fieldOfView = MIN_FOV;
				}

				const oo::PList fovAxes = stickHandler->axisFunctions();
				const oo::PList *functionForFovAxis = fovAxes.get<oo::PList::Dict>(std::to_string(AXIS_FIELD_OF_VIEW));	// nil: absent or not a Dict
				if (stickHandler->joystickCount() != 0 && functionForFovAxis != nullptr)
				{
					// TODO think reqFov through
					double reqFov = stickHandler->getAxisState(AXIS_FIELD_OF_VIEW);
					if (fieldOfView < maxFieldOfView * reqFov)
					{
						fieldOfView *= pow(fov_delta, delta_t);
						if (fieldOfView > MAX_FOV)  fieldOfView = MAX_FOV;
					}
					if (fieldOfView > maxFieldOfView * reqFov)
					{
						fieldOfView /= pow(fov_delta, delta_t);
						if (fieldOfView < MIN_FOV)  fieldOfView = MIN_FOV;
					}
				}
			}
#endif

	#ifndef NDEBUG
			exceptionContext = "dump target state";
			if (checkKeyPress(n_key_dump_target_state))
			{
				if (!dump_target_state_pressed)
				{
					dump_target_state_pressed = YES;
					Entity *target = primaryTarget();
					if (target == nullptr)	target = this;
					target->dumpState();	// what the facade's -dumpState called (bead oo-9ht.39.18)
				}
			}
			else  dump_target_state_pressed = NO;
	#endif
			
			//  text displays
			exceptionContext = "pollGuiScreenControls";
			pollGuiScreenControls();
		}
		else
		{
			// game is paused
			// check options menu request
			exceptionContext = "options menu";
			if ((checkKeyPress(n_key_gui_screen_options)) && (gui_screen != GUI_SCREEN_OPTIONS) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))
			{
				if (gameView != nullptr)  gameView->clearKeys();
				setGuiToLoadSaveScreen();
			}
			
			#if (ALLOW_CUSTOM_VIEWS_WHILE_PAUSED)
			pollCustomViewControls();	// allow custom views during pause
			#endif
			
			if (gui_screen == GUI_SCREEN_OPTIONS || gui_screen == GUI_SCREEN_GAMEOPTIONS || gui_screen == GUI_SCREEN_STICKMAPPER || 
				gui_screen == GUI_SCREEN_STICKPROFILE || gui_screen == GUI_SCREEN_KEYBOARD || gui_screen == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR ||
				gui_screen == GUI_SCREEN_KEYBOARD_CONFIG || gui_screen == GUI_SCREEN_KEYBOARD_ENTRY || gui_screen == GUI_SCREEN_KEYBOARD_LAYOUT)
			{
				if ((UNIVERSE != nullptr ? UNIVERSE->pauseMessageVisible() : false)) UNIVERSE->messageGUI()->leaveLastLine();
				else UNIVERSE->messageGUI()->clear();
				NSTimeInterval	time_this_frame = oo::date::monotonicSeconds();	// intervals only (time_last_frame)
				OOTimeDelta		time_delta;
				if (!::GameController::sharedController()->isGamePaused())
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
				pollGuiArrowKeyControls(time_delta);
			}
			
			exceptionContext = "debug keys";
	#ifndef NDEBUG
			// look for debugging keys
			if (checkKeyPress(n_key_dump_entity_list) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the '0' key
			{
				if (!dump_entity_list_pressed)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->debugDumpEntities();
					gDebugFlags = 0;
					if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Entity List dumped. Debugging OFF", 3);
				}
				dump_entity_list_pressed = YES;
			}
			else
				dump_entity_list_pressed = NO;
			
			// look for debugging keys
			if (checkKeyPress(n_key_debug_full) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the 'd' key
			{
				gDebugFlags = DEBUG_ALL;
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Full debug ON", 3);
			}
			
			if (checkKeyPress(n_key_debug_collision) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the 'b' key
			{
				gDebugFlags |= DEBUG_COLLISIONS;
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Collision debug ON", 3);
			}
			
			if (checkKeyPress(n_key_debug_console_connect) && !::OODebugMonitor::sharedDebugMonitor()->usingPlugInController() && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{})) // look for the 'c' key
			{
				// This code is executed only if we're not using the integrated plugin controller
				if (!autopilot_key_pressed)
				{
					if (!::OODebugMonitor::sharedDebugMonitor()->debuggerConnected())
					{
						OOInitDebugSupport();
						if (::OODebugMonitor::sharedDebugMonitor()->debuggerConnected())
							if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Connected to debug console.", 3);
					}
					else
					{
						::OODebugMonitor::sharedDebugMonitor()->setDebugger(nullptr);
						if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Disconnected from debug console.", 3);
					}
				}
				autopilot_key_pressed = YES;
			}
			else
				autopilot_key_pressed = NO;
			
			if (checkKeyPress(n_key_debug_bounding_boxes) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the 'x' key
			{
				gDebugFlags |= DEBUG_BOUNDING_BOXES;
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Bounding box debug ON", 3);
			}
			
			if (checkKeyPress(n_key_debug_shaders) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the 's' key
			{
				oo::log::logger().setDisplay("$shaderDebugOn", true);
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage("Shader debug ON", 3);
			}

			if ((checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_arrow_right)) && gui_screen != GUI_SCREEN_GAMEOPTIONS && (UNIVERSE != nullptr ? UNIVERSE->getDisplayFPS() : false) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))
			{
				if (!leftRightKeyPressed)
				{
					float newTimeAccelerationFactor = checkKeyPress(n_key_gui_arrow_left) ?
							fmax((UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0) / 2.0f, TIME_ACCELERATION_FACTOR_MIN) :
							fmin((UNIVERSE != nullptr ? UNIVERSE->getTimeAccelerationFactor() : 0.0) * 2.0f, TIME_ACCELERATION_FACTOR_MAX);
					if (UNIVERSE != nullptr)  UNIVERSE->setTimeAccelerationFactor(newTimeAccelerationFactor);
				}
				leftRightKeyPressed = YES;
			}
			else
				leftRightKeyPressed = NO;
					
			
			if (checkKeyPress(n_key_debug_off) && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the 'n' key
			{
				gDebugFlags = 0;
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage("All debug flags OFF", 3);
				oo::log::logger().setDisplay("$shaderDebugOn", false);
			}
	#endif
		}
		
		exceptionContext = "pause";
		// Pause game 'p'
		if ((checkKeyPress(n_key_pausebutton) || joyButtonState[BUTTON_PAUSE]) && gui_screen != GUI_SCREEN_LONG_RANGE_CHART && gui_screen != GUI_SCREEN_MISSION && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))// look for the 'p' key
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
							setGuiToStatusScreen();
							break;
						case GUI_SCREEN_LONG_RANGE_CHART:
							setGuiToLongRangeChartScreen();
							break;
						case GUI_SCREEN_SHORT_RANGE_CHART:
							setGuiToShortRangeChartScreen();
							break;
						case GUI_SCREEN_MANIFEST:
							setGuiToManifestScreen();
							break;
						case GUI_SCREEN_MARKET:
							setGuiToMarketScreen();
							break;
						case GUI_SCREEN_MARKETINFO:
							setGuiToMarketInfoScreen();
							break;
						case GUI_SCREEN_SYSTEM_DATA:
							// Do not reset planet rotation if we are already in the system info screen!
							if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
								setGuiToSystemDataScreen();
							break;
						default:
							gui_screen = (OOGUIScreenID)saved_gui_screen;	// make sure we're back to the right screen
							break;
					}
					if (gameView != nullptr)  gameView->allowStringInput(NO);
					if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
					if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection((OOViewID)saved_view_direction);
					currentWeaponFacing = saved_weapon_facing;
					// make sure the light comes from the right direction after resuming from pause!
					if (saved_gui_screen == GUI_SCREEN_SYSTEM_DATA) { if (UNIVERSE != nullptr)  UNIVERSE->setMainLightPosition(_sysInfoLight); }
					UNIVERSE->getGui()->setForegroundTextureKey("overlay");
					if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setGamePaused(NO);
				}
				else
				{
					saved_view_direction = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{});
					saved_script_time = script_time;
					saved_gui_screen = gui_screen;
					saved_weapon_facing = currentWeaponFacing;
					if (UNIVERSE != nullptr)  UNIVERSE->pauseGame();	// pause handler
				}
			}
			pause_pressed = YES;
		}
		else
		{
			pause_pressed = NO;
		}
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG(cxx_kOOLogException, "***** Exception in pollFlightControls [{}]: {} : {}", exceptionContext, exception->name(), exception->reason());
	}
}


void PlayerEntity::pollGuiArrowKeyControls(double delta_t)
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	BOOL			moving = NO;
	BOOL			dragging = NO;
	double			cursor_speed = ((gameView != nullptr ? gameView->isCtrlDown() : false) ? 20.0 : 10.0)* chart_zoom;
	::GameController  *controller = (UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	GUI_ROW_INIT(gui);
	
	// deal with string inputs as necessary
	if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
	{
		if (gameView != nullptr)  gameView->setStringInput(gvStringInputAlpha);
	}
	else if (gui_screen == GUI_SCREEN_SAVE)
	{
		if (gameView != nullptr)  gameView->setStringInput(gvStringInputLoadSave);
	}
	else if (gui_screen == GUI_SCREEN_MISSION && _missionTextEntry)
	{
		if (gameView != nullptr)  gameView->setStringInput(gvStringInputAll);
	}
	else if (gui_screen == GUI_SCREEN_KEYBOARD_ENTRY)
	{
		if (gameView != nullptr)  gameView->setStringInput(gvStringInputAll);
	}
#if 0
	// at the moment this function is never called for GUI_SCREEN_OXZMANAGER
	// but putting this here in case we do later
	else if (gui_screen == GUI_SCREEN_OXZMANAGER && ::OOOXZManager::sharedManager()->isAcceptingTextInput())
	{
		[gameView setStringInput: gvStringInputAll];
	}
#endif
	else
	{
		if (gameView != nullptr)  gameView->allowStringInput(NO);
		// If we have entered this screen with the injectors key pressed, make sure
		// that injectors switch off when we release it - Nikos.
		if (afterburner_engaged && !checkKeyPress(n_key_inject_fuel))
		{
			afterburner_engaged = NO;
		}
			
	}
	
	switch (gui_screen)
	{
		case GUI_SCREEN_LONG_RANGE_CHART:

			if (status() != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if (oo::str::length((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or("")) > 0)
				{
					planetSearchString = oo::str::lowercase(*(gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()));
					NSPoint search_coords = (UNIVERSE != nullptr ? UNIVERSE->findSystemCoordinatesWithPrefix(*planetSearchString) : NSPoint{});
					if ((search_coords.x >= 0.0)&&(search_coords.y >= 0.0))
					{
						// always reset the found system index at the beginning of a new search
						if (oo::str::length(*planetSearchString) == 1) UNIVERSE->getGui()->targetNextFoundSystem(0);
						
						// Always select the right one out of 2 overlapping systems.
						targetNewSystem(0, YES);
					}
					else
					{
						found_system_id = -1;
						clearPlanetSearchString();
					}
				}
				else
				{
					if ((gameView != nullptr ? gameView->isDown(gvDeleteKey) : false)) // did we just delete the string ?
					{
						found_system_id = -1;
						if (UNIVERSE != nullptr)  UNIVERSE->findSystemCoordinatesWithPrefix("");
					}
					planetSearchString.reset();
				}
				
				moving |= (searchStringLength != oo::str::length((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or("")));
				searchStringLength = oo::str::length((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or(""));
			}

		case GUI_SCREEN_SHORT_RANGE_CHART:

			if (checkKeyPress(n_key_chart_highlight))
			{
				if (!queryPressed)
				{
					OOLongRangeChartMode mode = getLongRangeChartMode();
					if (mode != OOLRC_MODE_TECHLEVEL)
					{
						setLongRangeChartMode((OOLongRangeChartMode)(mode+1));
					}
					else
					{
						setLongRangeChartMode(OOLRC_MODE_SUNCOLOR);
					}
					doScriptEvent(OOJSID("chartHighlightModeChanged"), { oo::PList(cxx_OOStringFromLongRangeChartMode(getLongRangeChartMode())) });
				}
				queryPressed = YES;
			}
			else
			{
				queryPressed = NO;
			}
			
			if (checkKeyPress(n_key_map_info) && chart_zoom <= CHART_ZOOM_SHOW_LABELS)
			{
				if (!chartInfoPressed)
				{
					show_info_flag = !show_info_flag;
					chartInfoPressed = YES;
				}
			}
			else
			{
				chartInfoPressed = NO;
			}
			
			if (status() != STATUS_WITCHSPACE_COUNTDOWN)
			{
				if (hasEquipmentItemProviding("EQ_ADVANCED_NAVIGATIONAL_ARRAY"))
				{
					if (checkKeyPress(n_key_advanced_nav_array_next) || checkKeyPress(n_key_advanced_nav_array_previous))
					{
						if (!pling_pressed)
						{
							if (checkKeyPress(n_key_advanced_nav_array_previous))
							{
								switch (ANA_mode)
								{
								case OPTIMIZED_BY_NONE:	ANA_mode = OPTIMIZED_BY_TIME;	break;
								case OPTIMIZED_BY_TIME:	ANA_mode = OPTIMIZED_BY_JUMPS;	break;
								default:		ANA_mode = OPTIMIZED_BY_NONE;	break;
								}
							}
							else
							{
								switch (ANA_mode)
								{
								case OPTIMIZED_BY_NONE:	ANA_mode = OPTIMIZED_BY_JUMPS;	break;
								case OPTIMIZED_BY_JUMPS:ANA_mode = OPTIMIZED_BY_TIME;	break;
								default:		ANA_mode = OPTIMIZED_BY_NONE;	break;
								}
							}
							if (ANA_mode == OPTIMIZED_BY_NONE || !infoSystemOnRoute())
							{
								setInfoSystemID(target_system_id, NO);
							}
						}
						pling_pressed = YES;
					}
					else
					{
						pling_pressed = NO;
					}
				}
				else
				{
					ANA_mode = OPTIMIZED_BY_NONE;
				}

				if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
				{
					if (gameView != nullptr)  gameView->clearMouse();
					mouse_left_down = NO;
					noteGUIWillChangeTo(GUI_SCREEN_SYSTEM_DATA);
					showingLongRangeChart = (gui_screen == GUI_SCREEN_LONG_RANGE_CHART);
					setGuiToSystemDataScreen();
					break;
				}
				if ((gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false))
				{
					NSPoint maus = (gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint{});
					double vadjust = MAIN_GUI_PIXEL_HEIGHT/2.0 - CHART_SCREEN_VERTICAL_CENTRE;
					double hscale = MAIN_GUI_PIXEL_WIDTH / (64.0 * chart_zoom);
					double vscale = MAIN_GUI_PIXEL_HEIGHT / (128.0 * chart_zoom);
					if (mouse_left_down == NO)
					{
						NSPoint centre = adjusted_chart_centre();
						centre_at_mouse_click = chart_centre_coordinates;
						mouse_click_position = maus;
						chart_focus_coordinates.x = OOClamp_0_max_f(centre.x + (maus.x * MAIN_GUI_PIXEL_WIDTH) / hscale, 256.0);
						chart_focus_coordinates.y = OOClamp_0_max_f(centre.y + (maus.y * MAIN_GUI_PIXEL_HEIGHT + vadjust) / vscale, 256.0);
						target_chart_focus = chart_focus_coordinates;
					}
					if (fabs(maus.x - mouse_click_position.x)*MAIN_GUI_PIXEL_WIDTH > 2 ||
						fabs(maus.y - mouse_click_position.y)*MAIN_GUI_PIXEL_HEIGHT > 2)
					{
						chart_centre_coordinates.x = OOClamp_0_max_f(centre_at_mouse_click.x - (maus.x - mouse_click_position.x)*MAIN_GUI_PIXEL_WIDTH/hscale, 256.0);
						chart_centre_coordinates.y = OOClamp_0_max_f(centre_at_mouse_click.y - (maus.y - mouse_click_position.y)*MAIN_GUI_PIXEL_HEIGHT/vscale, 256.0);
						target_chart_centre = chart_centre_coordinates;
						dragging = YES;
					}
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
						if (gameView != nullptr)  gameView->resetTypedString();
					mouse_left_down = YES;
				}
				else if (mouse_left_down == YES) 
				{
					NSPoint maus = (gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint{});
					if (fabs(maus.x - mouse_click_position.x)*MAIN_GUI_PIXEL_WIDTH <= 2 &&
						fabs(maus.y - mouse_click_position.y)*MAIN_GUI_PIXEL_HEIGHT <= 2)
					{
						cursor_coordinates = chart_focus_coordinates;
						moving = YES;
					}
					else
					{
						dragging = YES;
					}
					mouse_left_down = NO;
				}
				if (checkKeyPress(n_key_map_home))
				{
					if ((gameView != nullptr ? gameView->isOptDown() : false))
					{
						homeInfoSystem();
						target_chart_focus = galaxy_coordinates;
					}
					else
					{
						if (gameView != nullptr)  gameView->resetTypedString();
						cursor_coordinates = galaxy_coordinates;
						target_chart_focus = cursor_coordinates;
						target_chart_centre = galaxy_coordinates;
						found_system_id = -1;
						if (UNIVERSE != nullptr)  UNIVERSE->findSystemCoordinatesWithPrefix("");
						moving = YES;
					}
				}
				if (checkKeyPress(n_key_map_end))
				{
					targetInfoSystem();
					target_chart_focus = cursor_coordinates;
				}
				if (checkKeyPress(n_key_map_zoom_in) || (gameView != nullptr ? gameView->mouseWheelState() : 0) == gvMouseWheelDown)
				{
					target_chart_zoom *= CHART_ZOOM_SPEED_FACTOR;
					if (target_chart_zoom > CHART_MAX_ZOOM) target_chart_zoom = CHART_MAX_ZOOM;
					saved_chart_zoom = target_chart_zoom;
				}
				if (checkKeyPress(n_key_map_zoom_out) || (gameView != nullptr ? gameView->mouseWheelState() : 0) == gvMouseWheelUp)
				{
					if (gui_screen == GUI_SCREEN_LONG_RANGE_CHART)
					{
						target_chart_zoom = CHART_MAX_ZOOM;
						setGuiToShortRangeChartScreen();
					}
					target_chart_zoom /= CHART_ZOOM_SPEED_FACTOR;
					if (target_chart_zoom < 1.0) target_chart_zoom = 1.0;
					saved_chart_zoom = target_chart_zoom;
					//target_chart_centre = cursor_coordinates;
					target_chart_focus = target_chart_centre;
				}
				
				BOOL nextSystem = (gameView != nullptr ? gameView->isShiftDown() : false);
				BOOL nextSystemOnRoute = (gameView != nullptr ? gameView->isOptDown() : false);
				
				if (checkNavKeyPress(n_key_gui_arrow_left))
				{
					if ((nextSystem || nextSystemOnRoute) && pressedArrow != 1)
					{
						if (nextSystem)
						{
							targetNewSystem(-1);
							target_chart_focus = cursor_coordinates;
						}
						else
						{
							clearPlanetSearchString();
							previousInfoSystem();
							target_chart_focus = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(info_system_id, galaxy_number) : NSMakePoint(0, 0));
						}
						pressedArrow = 1;
					}
					else if (!nextSystem && !nextSystemOnRoute)
					{
						if (gameView != nullptr)  gameView->resetTypedString();
						cursor_coordinates.x -= cursor_speed*delta_t;
						if (cursor_coordinates.x < 0.0) cursor_coordinates.x = 0.0;
						moving = YES;
						target_chart_focus = cursor_coordinates;
					}
				}
				else
					pressedArrow =  pressedArrow == 1 ? 0 : pressedArrow;
				
				if (checkNavKeyPress(n_key_gui_arrow_right))
				{
					if ((nextSystem || nextSystemOnRoute) && pressedArrow != 2)
					{
						if (nextSystem)
						{
							targetNewSystem(+1);
							target_chart_focus = cursor_coordinates;
						}
						else
						{
							clearPlanetSearchString();
							nextInfoSystem();
							target_chart_focus = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(info_system_id, galaxy_number) : NSMakePoint(0, 0));
						}
						pressedArrow = 2;
					}
					else if (!nextSystem && !nextSystemOnRoute)
					{
						if (gameView != nullptr)  gameView->resetTypedString();
						cursor_coordinates.x += cursor_speed*delta_t;
						if (cursor_coordinates.x > 256.0) cursor_coordinates.x = 256.0;
						moving = YES;
						target_chart_focus = cursor_coordinates;
					}
				}
				else
					pressedArrow =  pressedArrow == 2 ? 0 : pressedArrow;
				
				if (checkNavKeyPress(n_key_gui_arrow_down))
				{
					if (nextSystem && pressedArrow != 3)
					{
						targetNewSystem(+1);
						pressedArrow = 3;
					}
					else if (!nextSystem)
					{
						if (gameView != nullptr)  gameView->resetTypedString();
						cursor_coordinates.y += cursor_speed*delta_t*2.0;
						if (cursor_coordinates.y > 256.0) cursor_coordinates.y = 256.0;
						moving = YES;
					}
					target_chart_focus = cursor_coordinates;
				}
				else
					pressedArrow =  pressedArrow == 3 ? 0 : pressedArrow;
				
				if (checkNavKeyPress(n_key_gui_arrow_up))
				{
					if (nextSystem && pressedArrow != 4)
					{
						targetNewSystem(-1);
						pressedArrow = 4;
					}	
					else if (!nextSystem)
					{
						if (gameView != nullptr)  gameView->resetTypedString();
						cursor_coordinates.y -= cursor_speed*delta_t*2.0;
						if (cursor_coordinates.y < 0.0) cursor_coordinates.y = 0.0;
						moving = YES;
					}
					target_chart_focus = cursor_coordinates;
				}
				else
					pressedArrow =  pressedArrow == 4 ? 0 : pressedArrow;
				if ((cursor_moving)&&(!moving))
				{
					if (found_system_id == -1)
					{
						target_system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(cursor_coordinates, galaxy_number, NO) : 0);
						setInfoSystemID(target_system_id, YES);
					}
					else
					{
						// if found with a search string, don't recalculate! Required for overlapping systems, like Divees & Tezabi in galaxy 5
						NSPoint fpos = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(found_system_id, galaxy_number) : NSMakePoint(0, 0));
						if (fpos.x != cursor_coordinates.x && fpos.y != cursor_coordinates.y)
						{
							target_system_id = (UNIVERSE != nullptr ? UNIVERSE->findSystemNumberAtCoords(cursor_coordinates, galaxy_number, NO) : 0);
							setInfoSystemID(target_system_id, YES);
						}
					}
					cursor_coordinates = ((UNIVERSE != nullptr ? UNIVERSE->getSystemManager() : nullptr) != nullptr ? UNIVERSE->getSystemManager()->getCoordinatesForSystem(target_system_id, galaxy_number) : NSMakePoint(0, 0));
				}
				if (chart_focus_coordinates.x - target_chart_centre.x <= -CHART_SCROLL_AT_X*chart_zoom)
				{
					target_chart_centre.x = chart_focus_coordinates.x + CHART_SCROLL_AT_X*chart_zoom;
				}
				else if (chart_focus_coordinates.x - target_chart_centre.x >= CHART_SCROLL_AT_X*chart_zoom)
				{
					target_chart_centre.x = chart_focus_coordinates.x - CHART_SCROLL_AT_X*chart_zoom;
				}
				if (chart_focus_coordinates.y - target_chart_centre.y <= -CHART_SCROLL_AT_Y*chart_zoom)
				{
					target_chart_centre.y = chart_focus_coordinates.y + CHART_SCROLL_AT_Y*chart_zoom;
				}
				else if (chart_focus_coordinates.y - target_chart_centre.y >= CHART_SCROLL_AT_Y*chart_zoom)
				{
					target_chart_centre.y = chart_focus_coordinates.y - CHART_SCROLL_AT_Y*chart_zoom;
				}
				chart_centre_coordinates.x = (3.0*chart_centre_coordinates.x + target_chart_centre.x)/4.0;
				chart_centre_coordinates.y = (3.0*chart_centre_coordinates.y + target_chart_centre.y)/4.0;
				chart_zoom = (3.0*chart_zoom + target_chart_zoom)/4.0;
				chart_focus_coordinates.x = (3.0*chart_focus_coordinates.x + target_chart_focus.x)/4.0;
				chart_focus_coordinates.y = (3.0*chart_focus_coordinates.y + target_chart_focus.y)/4.0;
				if (cursor_moving || dragging) setGuiToChartScreenFrom(gui_screen); // update graphics
				cursor_moving = moving;
			}
			break;
			
		case GUI_SCREEN_SYSTEM_DATA:
			if (checkKeyPress(n_key_system_next_system))
			{
				if (!next_planet_info_pressed)
				{
					nextInfoSystem();
					next_planet_info_pressed = YES;
				}
			}
			else
			{
				next_planet_info_pressed = NO;
			}
			if (checkKeyPress(n_key_system_previous_system))
			{
				if (!previous_planet_info_pressed)
				{
					previousInfoSystem();
					previous_planet_info_pressed = YES;
				}
			}
			else
			{
				previous_planet_info_pressed = NO;
			}
			if (checkKeyPress(n_key_system_home))
			{
				if (!home_info_pressed)
				{
					homeInfoSystem();
					home_info_pressed = YES;
				}
			}
			else
			{
				home_info_pressed = NO;
			}
			if (checkKeyPress(n_key_system_end))
			{
				if (!target_info_pressed)
				{
					targetInfoSystem();
					target_info_pressed = YES;
				}
			}
			else
			{
				target_info_pressed = NO;
			}
			break;
			
#if OO_USE_CUSTOM_LOAD_SAVE
			// DJS: Farm off load/save screen options to LoadSave.m
		case GUI_SCREEN_LOAD:
		{
			const std::optional<std::string> commanderFile = commanderSelector();
			if(commanderFile)
			{
				// also release the demo ship here (see showShipyardModel and noteGUIDidChangeFrom)
				demoShip = nullptr;

				loadPlayerFromFile(*commanderFile, NO);
			}
			break;
		}
			
		case GUI_SCREEN_SAVE:
			pollGuiScreenControlsWithFKeyAlias(NO);
			/* Only F1 works for launch on this screen, not '1' or
			 * whatever it has been bound to */
			if (checkKeyPress(n_key_launch_ship, YES))  handleUndockControl();
			if (gui_screen == GUI_SCREEN_SAVE)
			{
				saveCommanderInputHandler();
			}
			else pollControls = YES;
			break;
			
		case GUI_SCREEN_SAVE_OVERWRITE:
			overwriteCommanderInputHandler();
			break;
#endif
			
		case GUI_SCREEN_STICKMAPPER:
			handleStickMapperScreenKeys();
			break;
		
		case GUI_SCREEN_STICKPROFILE:
			stickProfileInputHandler(gui, gameView);
			break;
			
		case GUI_SCREEN_GAMEOPTIONS:
			handleGameOptionsScreenKeys();
			break;

		case GUI_SCREEN_KEYBOARD:
			handleKeyMapperScreenKeys();
			//if ([gameView isDown:' '])
			//{
			//	[self setGuiToGameOptionsScreen];
			//}
			break;

		case GUI_SCREEN_KEYBOARD_CONFIRMCLEAR:
			handleKeyMapperConfirmClearKeys(gui, gameView);
			break;

		case GUI_SCREEN_KEYBOARD_CONFIG:
			handleKeyConfigKeys(gui, gameView);
			break;

		case GUI_SCREEN_KEYBOARD_ENTRY:
			handleKeyConfigEntryKeys(gui, gameView);
			break;

		case GUI_SCREEN_KEYBOARD_LAYOUT:
			handleKeyboardLayoutKeys();
			break;

		case GUI_SCREEN_SHIPLIBRARY:
			if ((gameView != nullptr ? gameView->isDown(' ') : false))	//  '<space>'
			{
				// viewed in game, return to interfaces as that's where it's accessed from
				setGuiToInterfacesScreen(0);
			}
			if (checkKeyPress(n_key_gui_arrow_up)) //  '<--'
			{
				if (!upDownKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2Previous();
			}
			if (checkKeyPress(n_key_gui_arrow_down)) //  '-->'
			{
				if (!upDownKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2Next();
			}
			upDownKeyPressed = ((checkKeyPress(n_key_gui_arrow_up))||(checkKeyPress(n_key_gui_arrow_down)));

			if (checkKeyPress(n_key_gui_arrow_left)) //  '<--'
			{
				if (!leftRightKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2PreviousCategory();
			}
			if (checkKeyPress(n_key_gui_arrow_right)) //  '-->'
			{
				if (!leftRightKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2NextCategory();
			}
			leftRightKeyPressed = ((checkKeyPress(n_key_gui_arrow_left))||(checkKeyPress(n_key_gui_arrow_right)));

			break;
		case GUI_SCREEN_OPTIONS:
			handleGUIUpDownArrowKeys();
			OOGUIRow guiSelectedRow; guiSelectedRow = gui->getSelectedRow();
			BOOL selectKeyPress; selectKeyPress = (checkKeyPress(n_key_gui_select)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false));

			if (selectKeyPress)   // 'enter'
			{
				if ((guiSelectedRow == GUI_ROW(,QUICKSAVE))&&(!disc_operation_in_progress))
				{
					try
					{
						disc_operation_in_progress = YES;
						quicksavePlayer();
					}
					catch (...)
					{
						const auto exception = oo::CurrentOOException();
						if (!exception)  throw;	// not an OOException: it goes on up, as before
						OO_LOG(cxx_kOOLogException, "\n\n***** Handling exception: {} : {} *****\n\n", exception->name(), exception->reason());
						if (strcmp(exception->name(), "GameNotSavedException") == 0)	// try saving game instead
						{
							OO_LOG(cxx_kOOLogException, "{}", "\n\n***** Trying a normal save instead *****\n\n");
							if ((controller != nullptr ? controller->inFullScreenMode() : false))
							{ if (controller != nullptr)  controller->pauseFullScreenModeToPerform("savePlayer", nil); }	// no target: the SDL build never performs it, and the entity's object no longer answers -savePlayer (bead oo-w9pi2)
							else
								savePlayer();
						}
						else
						{
							throw;
						}
					}
				}
				if ((guiSelectedRow == GUI_ROW(,SAVE))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					savePlayer();
				}
				if ((guiSelectedRow == GUI_ROW(,LOAD))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					if (!loadPlayer())
					{
						disc_operation_in_progress = NO;
						setGuiToStatusScreen();
					}
				}
				
				
				if ((guiSelectedRow == GUI_ROW(,BEGIN_NEW))&&(!disc_operation_in_progress))
				{
					disc_operation_in_progress = YES;
					if (UNIVERSE != nullptr)  UNIVERSE->setUseAddOns(std::string(SCENARIO_OXP_DEFINITION_ALL), NO, YES); // calls reinitAndShowDemo
				}
				
				if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
					if (gameView != nullptr)  gameView->clearMouse();
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
				if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->exitAppWithContext("Exit Game selected on options screen");
			}
#endif
			
			if ((guiSelectedRow == GUI_ROW(,GAMEOPTIONS)) && selectKeyPress)
			{
				if (gameView != nullptr)  gameView->clearKeys();
				setGuiToGameOptionsScreen();
			}
			
			break;
			
		case GUI_SCREEN_EQUIP_SHIP:
			if (handleGUIUpDownArrowKeys())
			{
				std::optional<std::string>	itemText = gui->selectedRowText();	// nil compares unequal, as -isEqual: on nil
				OOWeaponType		weaponType = nil;

				if (itemText == FORWARD_FACING_STRING) weaponType = forward_weapon_type;
				if (itemText == AFT_FACING_STRING) weaponType = aft_weapon_type;
				if (itemText == PORT_FACING_STRING) weaponType = port_weapon_type;
				if (itemText == STARBOARD_FACING_STRING) weaponType = starboard_weapon_type;

				if (weaponType != nil)
				{
					BOOL		sameAs = cxx_OOWeaponTypeFromEquipmentIdentifierSloppy(gui->selectedRowKey().value_or("")) == weaponType;
					// override showInformation _completely_ with itemText
					if ((weaponType != nullptr ? weaponType->identifier() : std::optional<std::string>()) == "EQ_WEAPON_NONE")  itemText = OO_DESC("no-weapon-enter-to-install");
					else
					{
						const std::string weaponName = (OOEquipmentType::equipmentTypeWithIdentifier(cxx_OOEquipmentIdentifierFromWeaponType(weaponType).value_or("")).get() != nullptr ? OOEquipmentType::equipmentTypeWithIdentifier(cxx_OOEquipmentIdentifierFromWeaponType(weaponType).value_or("")).get()->name() : std::optional<std::string>()).value_or(std::string());
						if (sameAs)  itemText = oo::str::formatRuntime(OO_DESC("weapon-installed-@"), { weaponName });
						else  itemText = oo::str::formatRuntime(OO_DESC("weapon-@-enter-to-replace"), { weaponName });
					}

					showInformationForSelectedUpgradeWithFormatString(itemText);
				}
				else
					showInformationForSelectedUpgrade();
			}
			
			if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_EQUIPMENT_START).value_or(""), "More:"))
					{
						playMenuPagePrevious();
						gui->setSelectedRow(GUI_ROW_EQUIPMENT_START);
						buySelectedItem();
					}
					timeLastKeyPress = script_time;
				}
			}
			if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1).value_or(""), "More:"))
					{
						playMenuPageNext();
						gui->setSelectedRow(GUI_ROW_EQUIPMENT_START + GUI_MAX_ROWS_EQUIPMENT - 1);
						buySelectedItem();
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right)|checkKeyPress(n_key_gui_arrow_left)|checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);

			if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
			{
				if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
				{
					selectPressed = NO;
					if (gameView != nullptr)  gameView->clearMouse();
				}
				if ((!selectPressed)&&(gui->getSelectedRow() > -1))
				{
					buySelectedItem();
					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}
			break;
			
		case GUI_SCREEN_INTERFACES:
			if (handleGUIUpDownArrowKeys())
			{
				showInformationForSelectedInterface();
			}
			if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_INTERFACES_START).value_or(""), "More:"))
					{
						playMenuPagePrevious();
						gui->setSelectedRow(GUI_ROW_INTERFACES_START);
						activateSelectedInterface();
					}
					timeLastKeyPress = script_time;
				}
			}
			if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1).value_or(""), "More:"))
					{
						playMenuPageNext();
						gui->setSelectedRow(GUI_ROW_INTERFACES_START + GUI_MAX_ROWS_INTERFACES - 1);
						activateSelectedInterface();
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right)|checkKeyPress(n_key_gui_arrow_left)|checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);
			if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))   // 'enter'
			{
				if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
				{
					selectPressed = NO;
					if (gameView != nullptr)  gameView->clearMouse();
				}
				if ((!selectPressed)&&(gui->getSelectedRow() > -1))
				{
					activateSelectedInterface();
					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}
			break;


		case GUI_SCREEN_MARKETINFO:
			pollMarketScreenControls();
			break;

		case GUI_SCREEN_MARKET:
			pollMarketScreenControls();

			if (checkKeyPress(n_key_market_filter_cycle) || checkKeyPress(n_key_market_sorter_cycle))
			{
				if (!queryPressed)
				{
					queryPressed = YES;
					if (checkKeyPress(n_key_market_filter_cycle))
					{
						if (marketFilterMode >= MARKET_FILTER_MODE_MAX)
						{
							marketFilterMode = MARKET_FILTER_MODE_OFF;
						}
						else
						{
							marketFilterMode = (OOMarketFilterMode)(marketFilterMode + 1);
						}
					}
					else
					{
						if (marketSorterMode >= MARKET_SORTER_MODE_MAX)
						{
							marketSorterMode = MARKET_SORTER_MODE_OFF;
						}
						else
						{
							marketSorterMode = (OOMarketSorterMode)(marketSorterMode + 1);
						}
					}
					playChangedOption();
					setGuiToMarketScreen();
				}
			} 
			else
			{
				queryPressed = NO;
			}

			break;
			
		case GUI_SCREEN_REPORT:
			if ((gameView != nullptr ? gameView->isDown(32) : false))	// spacebar
			{
				if (!spacePressed)
				{
					BOOL reportEnded = dockingReport.empty();
					playDismissedReportScreen();
					if(reportEnded)
					{
						setGuiToStatusScreen();
						doScriptEvent(OOJSID("reportScreenEnded"));  // last report given. Screen is now free for missionscreens.
						doWorldEventUntilMissionScreen(OOJSID("missionScreenOpportunity"));
					}
					else
					{
						setGuiToDockingReportScreen();
					}

				}
				spacePressed = YES;
			}
			else
				spacePressed = NO;
			break;
		case GUI_SCREEN_STATUS:
			handleGUIUpDownArrowKeys();
			if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ((gui->keyForRow(STATUS_EQUIPMENT_FIRST_ROW) == std::string(GUI_KEY_OK)))
					{
						gui->setSelectedRow(STATUS_EQUIPMENT_FIRST_ROW);
						playMenuPagePrevious();
						gui->setStatusPage(-1);
						setGuiToStatusScreen();
					}
					timeLastKeyPress = script_time;
				}
			}
			if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					NSUInteger maxRows = (getHud() != nullptr && getHud()->getAllowBigGui()) ? STATUS_EQUIPMENT_MAX_ROWS + STATUS_EQUIPMENT_BIGGUI_EXTRA_ROWS : STATUS_EQUIPMENT_MAX_ROWS;
					if ((gui->keyForRow(STATUS_EQUIPMENT_FIRST_ROW + maxRows) == std::string(GUI_KEY_OK)))
					{
						gui->setSelectedRow(STATUS_EQUIPMENT_FIRST_ROW + maxRows);
						playMenuPageNext();
						gui->setStatusPage(+1);
						setGuiToStatusScreen();
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right)|checkKeyPress(n_key_gui_arrow_left)|checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);
			
			if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
			{
				if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
				{
					selectPressed = NO;
					if (gameView != nullptr)  gameView->clearMouse();
				}
				if ((!selectPressed)&&(gui->getSelectedRow() > -1))
				{
					gui->setStatusPage((gui->getSelectedRow() == STATUS_EQUIPMENT_FIRST_ROW ? -1 : +1));
					setGuiToStatusScreen();

					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}

			break;
		case GUI_SCREEN_MANIFEST:
			handleGUIUpDownArrowKeys();
			if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
			{

				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ((gui->keyForRow(MANIFEST_SCREEN_ROW_BACK) == std::string(GUI_KEY_OK)))
					{
						gui->setSelectedRow(MANIFEST_SCREEN_ROW_BACK);
						playMenuPagePrevious();
						gui->setStatusPage(-1);
						setGuiToManifestScreen();
					}
					timeLastKeyPress = script_time;
				}
			}
			if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
			{
				OOGUIRow nextRow = MANIFEST_SCREEN_ROW_NEXT;
				if (getHud() != nullptr && (getHud()->isHidden() || getHud()->getAllowBigGui()))
				{
					nextRow += 7;
				}
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if ((gui->keyForRow(nextRow) == std::string(GUI_KEY_OK)))
					{
						gui->setSelectedRow(nextRow);
						playMenuPageNext();
						gui->setStatusPage(+1);
						setGuiToManifestScreen();
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right)|checkKeyPress(n_key_gui_arrow_left)|checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);
			
			if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
			{
				if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
				{
					selectPressed = NO;
					if (gameView != nullptr)  gameView->clearMouse();
				}
				if ((!selectPressed)&&(gui->getSelectedRow() > -1))
				{
					gui->setStatusPage((gui->getSelectedRow() == MANIFEST_SCREEN_ROW_BACK ? -1 : +1));
					setGuiToManifestScreen();

					selectPressed = YES;
				}
			}
			else
			{
				selectPressed = NO;
			}

			break;

		case GUI_SCREEN_SHIPYARD:
			if (handleGUIUpDownArrowKeys())
			{
				showShipyardInfoForSelection();
			}
			
			if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_SHIPYARD_START).value_or(""), "More:"))
					{
						playMenuPagePrevious();
						gui->setSelectedRow(GUI_ROW_SHIPYARD_START);
						buySelectedShip();
					}
					timeLastKeyPress = script_time;
				}
			}
			if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
			{
				if ((!leftRightKeyPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
				{
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1).value_or(""), "More:"))
					{
						playMenuPageNext();
						gui->setSelectedRow(GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1);
						buySelectedShip();
					}
					timeLastKeyPress = script_time;
				}
			}
			leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right)|checkKeyPress(n_key_gui_arrow_left)|checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);
			
			if (checkKeyPress(n_key_gui_select)) // 'enter' NOT double-click
			{
				if (!selectPressed)
				{
					// try to buy the ship!
					const std::optional<std::string> key = gui->keyForRow(gui->getSelectedRow());	// nil compares as ""
					OOCreditsQuantity shipprice = 0;
					if (!oo::str::hasPrefix(key.value_or(""), "More:"))
					{
						shipprice = priceForShipKey(key.value_or(""));
					}

					if (buySelectedShip())
					{
						if (!oo::str::hasPrefix(key.value_or(""), "More:")) // don't do anything if we clicked/selected a "More:" line
						{
							if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
							setGuiToStatusScreen();
							playBuyShip();
							doScriptEvent(OOJSID("playerBoughtNewShip"), { oo::EntityObjectNode(this), oo::PList::unsignedInteger(shipprice) }); // some equipment.oxp might want to know everything has changed.
						}
					}
					else
					{
						playCantBuyShip();
					}
				}
				selectPressed = YES;
			}
			else
			{
				selectPressed = NO;
			}
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
			{
				if ((gui->getSelectedRow() == GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1) && oo::str::hasPrefix(gui->keyForRow(GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1).value_or(""), "More:"))
				{
					playMenuPageNext();
					gui->setSelectedRow(GUI_ROW_SHIPYARD_START + MAX_ROWS_SHIPS_FOR_SALE - 1);
					buySelectedShip();
				}
				else if ((gui->getSelectedRow() == GUI_ROW_SHIPYARD_START) && oo::str::hasPrefix(gui->keyForRow(GUI_ROW_SHIPYARD_START).value_or(""), "More:"))
				{
					playMenuPagePrevious();
					gui->setSelectedRow(GUI_ROW_SHIPYARD_START);
					buySelectedShip();
				}
				if (gameView != nullptr)  gameView->clearMouse();
			}

			break;
			
		default:
			break;
	}

	// check for any extra keys added by scripting
	const auto screenKeys = extraGuiScreenKeys.find(gui_screen);
	const std::vector<oo::Ref<::OOJSGuiScreenKeyDefinition>> keys = (screenKeys != extraGuiScreenKeys.end()) ? screenKeys->second : std::vector<oo::Ref<::OOJSGuiScreenKeyDefinition>>();
	if (!keys.empty()) {
		std::size_t kc = keys.size();
		::OOJSGuiScreenKeyDefinition *definition = nullptr;
		while (kc--) {
			definition = keys[kc].get();
			const oo::PList keydefs = (definition != nullptr) ? definition->registerKeys() : oo::PList();
			const oo::PList::Dict *keydefsDict = keydefs.getIf<oo::PList::Dict>();
			if (keydefsDict == nullptr)  continue;
			for (const auto &[key, keydef] : *keydefsDict)	// byte order (was -allKeys order)
			{
				if (checkKeyPress(keydef)) 
				{
					if (!extra_gui_key_pressed) 
					{
						// do callback
						if (definition)
						{
							if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();
							definition->runCallback(key);
						}
						else
						{
							OO_LOG("interface.missingCallback", "Unable to find callback definition for {} using key {}", ((definition != nullptr) ? definition->name() : std::nullopt).value_or("(null)"), key);
						}
					}
					extra_gui_key_pressed = YES;
				}
				else
					extra_gui_key_pressed = NO;
			}
		}
	}

	// damp any rotations we entered with
	if (flightRoll > 0.0)
	{
		if (flightRoll > delta_t)		decrease_flight_roll(delta_t);
		else	flightRoll = 0.0;
	}
	if (flightRoll < 0.0)
	{
		if (flightRoll < -delta_t)		increase_flight_roll(delta_t);
		else	flightRoll = 0.0;
	}
	if (flightPitch > 0.0)
	{
		if (flightPitch > delta_t)		decrease_flight_pitch(delta_t);
		else	flightPitch = 0.0;
	}
	if (flightPitch < 0.0)
	{
		if (flightPitch < -delta_t)		increase_flight_pitch(delta_t);
		else	flightPitch = 0.0;
	}
	if (flightYaw > 0.0) 
	{ 
		if (flightYaw > delta_t)		decrease_flight_yaw(delta_t); 
		else	flightYaw = 0.0; 
	} 
	if (flightYaw < 0.0) 
	{ 
		if (flightYaw < -delta_t)		increase_flight_yaw(delta_t); 
		else	flightYaw = 0.0; 
	} 
}


void PlayerEntity::pollMarketScreenControls()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);

	if (gui_screen == GUI_SCREEN_MARKET)
	{
		handleGUIUpDownArrowKeys();
		marketSelectedCommodity = gui->selectedRowKey();

		BOOL			page_up = checkKeyPress(n_key_gui_page_up); 
		BOOL			page_down = checkKeyPress(n_key_gui_page_down); 
		if (page_up || page_down) 
		{
			if ((!pageUpDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
			{
				::OOCommodityMarket	*localMarket = this->localMarket();
				const std::vector<std::string> goods = applyMarketSorter(applyMarketFilter(localMarket->goods(), localMarket), localMarket);
				if (goods.size() > 0)
				{
					const std::optional<std::string> selected = marketSelectedCommodity;
					const auto found = selected ? std::find(goods.begin(), goods.end(), *selected) : goods.end();
					NSInteger goodsIndex = (found != goods.end()) ? (found - goods.begin()) : NSNotFound;
					NSInteger offset1 = 0;
					NSInteger offset2 = 0;
					if (gui->keyForRow(GUI_ROW_MARKET_START) == "<<<") offset1 += 1;
					if (gui->keyForRow(GUI_ROW_MARKET_LAST) == ">>>") offset2 += 1;
					if (page_up)
					{
						playMenuPagePrevious();
						// some edge cases
						if (goodsIndex - 16 <= 0) 
						{
							offset1 = 0;
							offset2 = 0;
						}
						if (offset1 == 1 && offset2 == 0 && goodsIndex < (NSInteger)goods.size() - 1 && goodsIndex - 15 > 0) offset2 = 1;
						goodsIndex -= (16 - (offset1 + offset2));
						if (goodsIndex < 0) goodsIndex = 0;
						if (goods.size() <= 17) goodsIndex = 0;
					}
					if (page_down) 
					{
						playMenuPageNext();
						// some edge cases
						if (offset1 == 0 && offset2 == 1 && goodsIndex > 1) offset1 = 1;
						if (offset2 == 1 && goodsIndex + 15 == (NSInteger)goods.size() - 1) offset2 = 0;
						goodsIndex += (16 - (offset1 + offset2));
						if (goodsIndex > ((NSInteger)goods.size() - 1) || goods.size() <= 17) goodsIndex = (NSInteger)goods.size() - 1;
					}
					marketSelectedCommodity = (goodsIndex >= 0 && goodsIndex < (NSInteger)goods.size()) ? std::optional<std::string>(goods[goodsIndex]) : std::nullopt;
					setGuiToMarketScreen();
				}
			} 
			pageUpDownKeyPressed = YES;
			timeLastKeyPress = script_time;
		}
		else {
			pageUpDownKeyPressed = NO;
		}
	}
	else
	{
		// handle up and down slightly differently
		BOOL			arrow_up = checkKeyPress(n_key_gui_arrow_up); 
		BOOL			arrow_down = checkKeyPress(n_key_gui_arrow_down); 
		if (arrow_up || arrow_down)
		{
			if ((!upDownKeyPressed) || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
			{
				::OOCommodityMarket	*localMarket = this->localMarket();
				const std::vector<std::string> goods = applyMarketSorter(applyMarketFilter(localMarket->goods(), localMarket), localMarket);
				if (goods.size() > 0)
				{
					const std::optional<std::string> selected = marketSelectedCommodity;
					const auto found = selected ? std::find(goods.begin(), goods.end(), *selected) : goods.end();
					NSInteger goodsIndex = (found != goods.end()) ? (found - goods.begin()) : NSNotFound;
					if (arrow_down)
					{
						++goodsIndex;
					}
					else
					{
						--goodsIndex;
					}
					if (goodsIndex < 0)
					{
						goodsIndex = (NSInteger)goods.size()-1;
					}
					else if (goodsIndex >= (NSInteger)goods.size())
					{
						goodsIndex = 0;
					}
					marketSelectedCommodity = (goodsIndex >= 0 && goodsIndex < (NSInteger)goods.size()) ? std::optional<std::string>(goods[goodsIndex]) : std::nullopt;
					setGuiToMarketInfoScreen();
				}
			}
			upDownKeyPressed = YES;
			timeLastKeyPress = script_time;
		}
		else
		{
			upDownKeyPressed = NO;
		}
	}

	BOOL isdocked = isDocked();

	if ((checkNavKeyPress(n_key_gui_arrow_right))||(checkNavKeyPress(n_key_gui_arrow_left))||(checkKeyPress(n_key_gui_select)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)))
	{
		if (checkNavKeyPress(n_key_gui_arrow_right))   // -->
		{
			if (!wait_for_key_up)
			{
				if (isdocked && tryBuyingCommodity(marketSelectedCommodity.value_or(std::string()), (gameView != nullptr ? gameView->isShiftDown() : false)))
				{
					playBuyCommodity();
					if (gui_screen == GUI_SCREEN_MARKET)
					{
						setGuiToMarketScreen();
					}
					else
					{
						setGuiToMarketInfoScreen();
					}
				}
				else
				{
					if ((gui->selectedRowKey() == ">>>"))
					{
						playMenuNavigationDown();
						setGuiToMarketScreen();
					}
					else if ((gui->selectedRowKey() == "<<<"))
					{
						playMenuNavigationUp();
						setGuiToMarketScreen();
					}
					else
					{
						playCantBuyCommodity();
					}
				}
				wait_for_key_up = YES;
			}
		}
		if (checkNavKeyPress(n_key_gui_arrow_left))   // <--
		{
			if (!wait_for_key_up)
			{
				if (isdocked && trySellingCommodity(marketSelectedCommodity.value_or(std::string()), (gameView != nullptr ? gameView->isShiftDown() : false)))
				{
					playSellCommodity();
					if (gui_screen == GUI_SCREEN_MARKET)
					{
						setGuiToMarketScreen();
					}
					else
					{
						setGuiToMarketInfoScreen();
					}
				}
				else
				{
					if ((gui->selectedRowKey() == ">>>"))
					{
						playMenuNavigationDown();
						setGuiToMarketScreen();
					}
					else if ((gui->selectedRowKey() == "<<<"))
					{
						playMenuNavigationUp();
						setGuiToMarketScreen();
					}
					else
					{
						playCantSellCommodity();
					}

				}
				wait_for_key_up = YES;
			}
		}
		if ((gui_screen == GUI_SCREEN_MARKET && (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) || checkKeyPress(n_key_gui_select))   // 'enter'
		{
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
			{
				wait_for_key_up = NO;
				if (gameView != nullptr)  gameView->clearMouse();
			}
			if (!wait_for_key_up)
			{
				const std::optional<std::string> item = marketSelectedCommodity;	// Amendment 1 item 10
				OOCargoQuantity yours =	(shipCommodityData != nullptr ? shipCommodityData->quantityForGood(item.value_or("")) : 0);
				if (item == ">>>")
				{
					tryBuyingCommodity(item.value_or(""), YES);
					setGuiToMarketScreen();
				}
				else if (item == "<<<")
				{
					trySellingCommodity(item.value_or(""), YES);
					setGuiToMarketScreen();
				}
				else if (isdocked && (gameView != nullptr ? gameView->isShiftDown() : false) && tryBuyingCommodity(item.value_or(""), YES))	// buy as much as possible (with Shift)
				{
					playBuyCommodity();
					if (gui_screen == GUI_SCREEN_MARKET)
					{
						setGuiToMarketScreen();
					}
					else
					{
						setGuiToMarketInfoScreen();
					}
				}
				else if (isdocked && (yours > 0) && trySellingCommodity(item.value_or(""), YES))	// sell all you can
				{
					playSellCommodity();
					if (gui_screen == GUI_SCREEN_MARKET)
					{
						setGuiToMarketScreen();
					}
					else
					{
						setGuiToMarketInfoScreen();
					}
				}
				else if (isdocked && tryBuyingCommodity(item.value_or(""), YES))			// buy as much as possible
				{
					playBuyCommodity();
					if (gui_screen == GUI_SCREEN_MARKET)
					{
						setGuiToMarketScreen();
					}
					else
					{
						setGuiToMarketInfoScreen();
					}
				}
				else if (isdocked)
				{
					playCantBuyCommodity();
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

void PlayerEntity::handleGameOptionsScreenKeys()
{
	::MyOpenGLView		*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen		*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	GUI_ROW_INIT(gui);
	
	handleGUIUpDownArrowKeys();
	OOGUIRow guiSelectedRow = gui->getSelectedRow();
	BOOL selectKeyPress = (checkKeyPress(n_key_gui_select)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false));
	if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))  { if (gameView != nullptr)  gameView->clearMouse(); }
	
	if ((guiSelectedRow == GUI_ROW(GAME,STICKMAPPER)) && selectKeyPress)
	{
		selFunctionIdx = 0;
		resetStickFunctions(); // reset the list of stick functions, so changes in oxp equipment are reflected
		setGuiToStickMapperScreen(0, YES);
	}
	if ((guiSelectedRow == GUI_ROW(GAME,KEYMAPPER)) && selectKeyPress)
	{
		selFunctionIdx = 0;
		resetKeyFunctions(); // reset the list of key functions, so changes in oxp equipment are reflected
		setGuiToKeyMapperScreen(0, YES);
	}
	
	
#if OOLITE_WINDOWS
	if ((gameView != nullptr ? gameView->hdrOutput() : false))
	{
		if ((guiSelectedRow == GUI_ROW(GAME,HDRMAXBRIGHTNESS))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
		{
			if (!hdrMaxBrightnessControlPressed)
			{
				int			direction = (checkKeyPress(n_key_gui_arrow_right)) ? 1 : -1;
				const oo::PList	*brightnessesValue = UNIVERSE->descriptions()->find("hdr_maxBrightness_array");
				const oo::PList	brightnesses = (brightnessesValue != nullptr && brightnessesValue->isArray()) ? *brightnessesValue : oo::PList();
				// -indexOfObject: with the %d string: only string elements ever matched; not found was NSNotFound narrowed to int
				const std::string	currentBrightness = std::to_string((int)(gameView != nullptr ? gameView->hdrMaxBrightness() : 0.0f));
				int			brightnessIdx = static_cast<int>(NSNotFound);
				for (std::size_t i = 0; i < brightnesses.count(); i++)
				{
					const oo::PList *element = brightnesses.at(i);
					if (element->isString() && *element->getIf<std::string>() == currentBrightness)
					{
						brightnessIdx = static_cast<int>(i);
						break;
					}
				}
				
				if (static_cast<NSInteger>(brightnessIdx) == NSNotFound)
				{
					OO_LOG_WARN("hdr.maxBrightness.notFound", "{}", "couldn't find current max brightness setting, switching to lowest.");
					brightnessIdx = 0;
				}
				
				brightnessIdx += direction;
				int count = static_cast<int>(brightnesses.count());
				if (brightnessIdx < 0)
					brightnessIdx = count - 1;
				if (brightnessIdx >= count)
					brightnessIdx = 0;
				
				int brightnessValue = brightnesses.at<int>(static_cast<std::size_t>(brightnessIdx));
				
				// warp if the value we got is out of expected limits; can be the case if user has
				// manually modified the hdr_maxBrightness_array in descriptions.plist
				if (brightnessValue < MIN_HDR_MAXBRIGHTNESS)  brightnessValue = direction == -1 ? MAX_HDR_MAXBRIGHTNESS : MIN_HDR_MAXBRIGHTNESS;
				if (brightnessValue > MAX_HDR_MAXBRIGHTNESS)  brightnessValue = direction == 1 ? MIN_HDR_MAXBRIGHTNESS : MAX_HDR_MAXBRIGHTNESS;
    				
				if (gameView != nullptr)  gameView->setHDRMaxBrightness((float)brightnessValue);
				const std::string maxBrightnessString = cxx_OOExpandKey("gameoptions-hdr-maxbrightness", brightnessValue).value_or(std::string());
																				
				gui->setText(maxBrightnessString, GUI_ROW(GAME,HDRMAXBRIGHTNESS), GUI_ALIGN_CENTER);
				
				hdrMaxBrightnessControlPressed = YES;
			}
		}
		else
			hdrMaxBrightnessControlPressed = NO;
	}
#endif
	
	
#if OO_RESOLUTION_OPTION
	if (!switching_resolution &&
		guiSelectedRow == GUI_ROW(GAME,DISPLAY) &&
		(checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left)))
	{
		::GameController	*controller = (UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr);
		int				direction = (checkKeyPress(n_key_gui_arrow_right)) ? 1 : -1;
		NSInteger		displayModeIndex = (controller != nullptr ? controller->indexOfCurrentDisplayMode() : 0);
		const oo::PList	modes = (controller != nullptr ? controller->getDisplayModes() : oo::PList());
		
		if (displayModeIndex == (NSInteger)NSNotFound)
		{
			OO_LOG_WARN("graphics.mode.notFound", "{}", "couldn't find current fullscreen setting, switching to default.");
			displayModeIndex = 0;
		}
		
		displayModeIndex = displayModeIndex + direction;
		int count = static_cast<int>(modes.count());
		if (displayModeIndex < 0)
			displayModeIndex = count - 1;
		if (displayModeIndex >= count)
			displayModeIndex = 0;
		
		const oo::PList	*modeEntry = modes.at(static_cast<std::size_t>(displayModeIndex));
		const oo::PList	mode = (modeEntry != nullptr) ? *modeEntry : oo::PList();
		int modeWidth = mode.get<int>(std::string(kOODisplayWidth));
		int modeHeight = mode.get<int>(std::string(kOODisplayHeight));
		int modeRefresh = mode.get<int>(std::string(kOODisplayRefreshRate));
		if (controller != nullptr)  controller->setDisplayWidth(modeWidth, modeHeight, modeRefresh);

		const std::string displayModeString = screenModeStringForWidth(modeWidth, modeHeight, modeRefresh).value_or("");
		
		playChangedOption();
		gui->setText(displayModeString, GUI_ROW(GAME,DISPLAY), GUI_ALIGN_CENTER);
		switching_resolution = YES;
		
#if OOLITE_SDL
		/*	TODO: The gameView for the SDL game currently holds and
		 sets the actual screen resolution (controller just stores
		 it). This probably ought to change. */
		if (gameView != nullptr)  gameView->setScreenSize(displayModeIndex); // changes fullscreen mode immediately
#endif
	}
	if (switching_resolution && !checkKeyPress(n_key_gui_arrow_right) && !checkKeyPress(n_key_gui_arrow_left) && !selectKeyPress)
	{
		switching_resolution = NO;
	}
#endif	// OO_RESOLUTION_OPTION
	
#if OOLITE_SPEECH_SYNTH

	if ((guiSelectedRow == GUI_ROW(GAME,SPEECH))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
	{
		if (!speech_settings_pressed)
		{
			if (checkKeyPress(n_key_gui_arrow_right) && isSpeechOn < OOSPEECHSETTINGS_ALL)
			{
				isSpeechOn = (OOSpeechSettings)(isSpeechOn + 1);
				playChangedOption();
				speech_settings_pressed = YES;
			}
			else if (checkKeyPress(n_key_gui_arrow_left) && isSpeechOn > OOSPEECHSETTINGS_OFF)
			{
				speech_settings_pressed = YES;
				isSpeechOn = (OOSpeechSettings)(isSpeechOn - 1);
				playChangedOption();
			}
			if (speech_settings_pressed)
			{
				std::optional<std::string> message;	// nullopt = no change (was nil)
				switch (isSpeechOn)
				{
				case OOSPEECHSETTINGS_OFF:
					message = OO_DESC("gameoptions-spoken-messages-no");
					break;
				case OOSPEECHSETTINGS_COMMS:
					message = OO_DESC("gameoptions-spoken-messages-comms");
					break;
				case OOSPEECHSETTINGS_ALL:
					message = OO_DESC("gameoptions-spoken-messages-yes");
					break;
				}
				gui->setText(message, GUI_ROW(GAME,SPEECH), GUI_ALIGN_CENTER);

				if (isSpeechOn == OOSPEECHSETTINGS_ALL)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->stopSpeaking();
					if (message.has_value())  { if (UNIVERSE != nullptr)  UNIVERSE->startSpeakingString(*message); }
				}
			}
		}
	}
	else
	{
		speech_settings_pressed = NO;
	}
#if OOLITE_ESPEAK
	if (guiSelectedRow == GUI_ROW(GAME,SPEECH_LANGUAGE))
	{
		if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left))
		{
			if (!speechVoiceSelectKeyPressed || script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL)
			{
				playChangedOption();
				if (checkKeyPress(n_key_gui_arrow_right))
					voice_no = (UNIVERSE != nullptr ? UNIVERSE->nextVoice(voice_no) : 0u);
				else
					voice_no = (UNIVERSE != nullptr ? UNIVERSE->prevVoice(voice_no) : 0u);
				if (UNIVERSE != nullptr)  UNIVERSE->setVoice(voice_no, voice_gender_m);
				const std::string voiceName = (UNIVERSE != nullptr ? UNIVERSE->voiceName(voice_no) : std::optional<std::string>()).value_or("");
				const std::string message = ExpandKeyWithArguments("gameoptions-voice-name", { { "voiceName", oo::PList(voiceName) } });
				gui->setText(message, GUI_ROW(GAME,SPEECH_LANGUAGE), GUI_ALIGN_CENTER);
				if (isSpeechOn == OOSPEECHSETTINGS_ALL)
				{
					if (UNIVERSE != nullptr)  UNIVERSE->stopSpeaking();
					if (const std::optional<std::string> spokenVoiceName = (UNIVERSE != nullptr ? UNIVERSE->voiceName(voice_no) : std::optional<std::string>()))  { if (UNIVERSE != nullptr)  UNIVERSE->startSpeakingString(*spokenVoiceName); }
				}
				timeLastKeyPress = script_time;
			}
			speechVoiceSelectKeyPressed = YES;
		}
		else
			speechVoiceSelectKeyPressed = NO;
	}

	if (guiSelectedRow == GUI_ROW(GAME,SPEECH_GENDER))
	{
		if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left))
		{
			if (!speechGenderSelectKeyPressed)
			{
				playChangedOption();
				BOOL m = checkKeyPress(n_key_gui_arrow_right);
				if (m != voice_gender_m)
				{
					voice_gender_m = m;
					if (UNIVERSE != nullptr)  UNIVERSE->setVoice(voice_no, voice_gender_m);
					const std::string message = OO_DESC(voice_gender_m ? "gameoptions-voice-M" : "gameoptions-voice-F");
					gui->setText(message, GUI_ROW(GAME,SPEECH_GENDER), GUI_ALIGN_CENTER);
					if (isSpeechOn == OOSPEECHSETTINGS_ALL)
					{
						if (UNIVERSE != nullptr)  UNIVERSE->stopSpeaking();
						if (const std::optional<std::string> spokenVoiceName = (UNIVERSE != nullptr ? UNIVERSE->voiceName(voice_no) : std::optional<std::string>()))  { if (UNIVERSE != nullptr)  UNIVERSE->startSpeakingString(*spokenVoiceName); }
					}
				}
			}
			speechGenderSelectKeyPressed = YES;
		}
		else
			speechGenderSelectKeyPressed = NO;
	}
#endif
#endif
	
	if ((guiSelectedRow == GUI_ROW(GAME,MUSIC))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
	{
		if (!musicModeKeyPressed)
		{
			::OOMusicController	*musicController = ::OOMusicController::sharedController();
			int					initialMode = musicController->mode();
			int					mode = initialMode;
			
			if (checkKeyPress(n_key_gui_arrow_right))  mode++;
			if (checkKeyPress(n_key_gui_arrow_left))  mode--;
			
			musicController->setMode((OOMusicMode)MAX(mode, 0));
			
			if ((int)musicController->mode() != initialMode)
			{
				playChangedOption();
				const std::string musicMode = (UNIVERSE != nullptr ? UNIVERSE->descriptionForArrayKey("music-mode", OOMusicController::sharedController()->mode()) : std::optional<std::string>()).value_or("");
				const std::string message = ExpandKeyWithArguments("gameoptions-music-mode", { { "musicMode", oo::PList(musicMode) } });
				gui->setText(message, GUI_ROW(GAME,MUSIC), GUI_ALIGN_CENTER);
			}
		}
		musicModeKeyPressed = YES;
	}
	else  musicModeKeyPressed = NO;
	
	if ((guiSelectedRow == GUI_ROW(GAME,AUTOSAVE))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
	{
		if (checkKeyPress(n_key_gui_arrow_right) != (UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false))
			playChangedOption();
		if (UNIVERSE != nullptr)  UNIVERSE->setAutoSave(checkKeyPress(n_key_gui_arrow_right));
		if ((UNIVERSE != nullptr ? UNIVERSE->getAutoSave() : false))
		{
			// if just enabled, we want to autosave immediately
			if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(YES);
			gui->setText(OO_DESC("gameoptions-autosave-yes"), GUI_ROW(GAME,AUTOSAVE), GUI_ALIGN_CENTER);
		}
		else
		{
			if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(NO);
			gui->setText(OO_DESC("gameoptions-autosave-no"), GUI_ROW(GAME,AUTOSAVE), GUI_ALIGN_CENTER);
		}
	}

	if ((guiSelectedRow == GUI_ROW(GAME,VOLUME))
		&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))	// (+[OOSound respondsToSelector:@selector(masterVolume)] was always YES)
	{
		if ((!volumeControlPressed)||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			BOOL rightKeyDown = checkKeyPress(n_key_gui_arrow_right);
			BOOL leftKeyDown = checkKeyPress(n_key_gui_arrow_left);
			double volume = 100.0 * ::OOSound::masterVolume();
			int vol = (volume / 5.0 + 0.5);
			if (rightKeyDown) vol++;
			if (leftKeyDown) vol--;
			vol = (int)OOClampInteger(vol, 0, 20);
			::OOSound::setMasterVolume(0.05 * vol);
			playChangedOption();
#if OOLITE_ESPEAK
			espeak_SetParameter(espeakVOLUME, vol * 5, 0);
#endif
			if (vol > 0)
			{
				const std::string soundVolumeWordDesc = OO_DESC("gameoptions-sound-volume");
				std::string v1_string = "|||||||||||||||||||||||||";
				std::string v0_string = ".........................";
				v1_string = v1_string.substr(0, static_cast<std::size_t>(vol));
				v0_string = v0_string.substr(0, static_cast<std::size_t>(20 - vol));
				gui->setText(oo::str::format("%s%s%s ", soundVolumeWordDesc.c_str(), v1_string.c_str(), v0_string.c_str()), GUI_ROW(GAME,VOLUME), GUI_ALIGN_CENTER);
			}
			else
				gui->setText(OO_DESC("gameoptions-sound-volume-mute"), GUI_ROW(GAME,VOLUME), GUI_ALIGN_CENTER);
			timeLastKeyPress = script_time;
		}
		volumeControlPressed = YES;
	}
	else
		volumeControlPressed = NO;

	if ((guiSelectedRow == GUI_ROW(GAME,FOV))
		&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
	{
		if (!fovControlPressed ||(script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			BOOL rightKeyDown = checkKeyPress(n_key_gui_arrow_right);
			BOOL leftKeyDown = checkKeyPress(n_key_gui_arrow_left);
			float fov = (gameView != nullptr ? gameView->fov(NO) : 0.0f);
			float fovStep = (MAX_FOV_DEG - MIN_FOV_DEG) / 20.0f;
			fov += (((rightKeyDown && (fov < MAX_FOV_DEG)) ?
						fovStep : 0.0f) - ((leftKeyDown && (fov > MIN_FOV_DEG)) ? fovStep : 0.0f));
			if (fov > MAX_FOV_DEG) fov = MAX_FOV_DEG;
			if (fov < MIN_FOV_DEG) fov = MIN_FOV_DEG;
			if (gameView != nullptr)  gameView->setFov(fov, NO);
			fieldOfView = (gameView != nullptr ? gameView->fov(YES) : 0.0f);
			int fovTicks = (int)((fov - MIN_FOV_DEG) / fovStep);
			const std::string fovWordDesc = OO_DESC("gameoptions-fov-value");
			std::string v1_string = "|||||||||||||||||||||||||";
			std::string v0_string = ".........................";
			v1_string = v1_string.substr(0, static_cast<std::size_t>(fovTicks));
			v0_string = v0_string.substr(0, static_cast<std::size_t>(20 - fovTicks));
			// %c 176 gave U+00B0 (probed on GNUstep base with this toolchain); written as its UTF-8 bytes
			gui->setText(oo::str::format("%s%s%s (%d%s) ", fovWordDesc.c_str(), v1_string.c_str(), v0_string.c_str(), (int)fov, "\xC2\xB0" /*the degrees symbol*/), GUI_ROW(GAME,FOV), GUI_ALIGN_CENTER);
			oo::Defaults::standard().setFloat("fov-value", (gameView != nullptr ? gameView->fov(NO) : 0.0f));
			timeLastKeyPress = script_time;
		}
		fovControlPressed = YES;
	}
	else
		fovControlPressed = NO;

	
	// color blind mode
	if ((guiSelectedRow == GUI_ROW(GAME,COLORBLINDMODE))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
	{
		if (!colorblindModeControlPressed)
		{
			int colorblindMode = (UNIVERSE != nullptr ? UNIVERSE->colorblindMode() : 0);
			if (checkKeyPress(n_key_gui_arrow_right))
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setCurrentPostFX((UNIVERSE != nullptr ? UNIVERSE->nextColorblindMode(colorblindMode) : 0));
			}
			else
			{
				if (UNIVERSE != nullptr)  UNIVERSE->setCurrentPostFX((UNIVERSE != nullptr ? UNIVERSE->prevColorblindMode(colorblindMode) : 0));
			}
			colorblindMode = (UNIVERSE != nullptr ? UNIVERSE->colorblindMode() : 0); // get the updated value
			const oo::PList *colorblindModes = UNIVERSE->descriptions()->find("colorblind_mode");
			const std::string colorblindModeDesc = (colorblindModes != nullptr && colorblindModes->isArray()) ? colorblindModes->at<std::string>(static_cast<std::size_t>((UNIVERSE != nullptr ? UNIVERSE->useShaders() : false) ? colorblindMode : 0)) : std::string();
			const std::string colorblindModeMsg = ExpandKeyWithArguments("gameoptions-colorblind-mode", { { "colorblindModeDesc", oo::PList(colorblindModeDesc) } });
			gui->setText(colorblindModeMsg, GUI_ROW(GAME,COLORBLINDMODE), GUI_ALIGN_CENTER);
		}
		colorblindModeControlPressed = YES;
	}
	else
		colorblindModeControlPressed = NO;
	
	
	if (!(gameView != nullptr ? gameView->hdrOutput() : false))
 	{
		if ((guiSelectedRow == GUI_ROW(GAME,WIREFRAMEGRAPHICS))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
		{
			if (checkKeyPress(n_key_gui_arrow_right) != (UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))
				playChangedOption();
			if (UNIVERSE != nullptr)  UNIVERSE->setWireframeGraphics(checkKeyPress(n_key_gui_arrow_right));
			if ((UNIVERSE != nullptr ? UNIVERSE->getWireframeGraphics() : false))
				gui->setText(OO_DESC("gameoptions-wireframe-graphics-yes"), GUI_ROW(GAME,WIREFRAMEGRAPHICS), GUI_ALIGN_CENTER);
			else
				gui->setText(OO_DESC("gameoptions-wireframe-graphics-no"), GUI_ROW(GAME,WIREFRAMEGRAPHICS), GUI_ALIGN_CENTER);
		}
	}
#if OOLITE_WINDOWS
	else
	{
		if ((guiSelectedRow == GUI_ROW(GAME,HDRPAPERWHITE))
		&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
		{
			if (!hdrPaperWhiteControlPressed)
			{
				BOOL rightKeyDown = checkKeyPress(n_key_gui_arrow_right);
				BOOL leftKeyDown = checkKeyPress(n_key_gui_arrow_left);
				float paperWhite = (gameView != nullptr ? gameView->hdrPaperWhiteBrightness() : 0.0f);
				paperWhite += (((rightKeyDown && (paperWhite < MAX_HDR_PAPERWHITE)) ? 10.0f : 0.0f) - ((leftKeyDown && (paperWhite > MIN_HDR_PAPERWHITE)) ? 10.0f : 0.0f));
				if (paperWhite > MAX_HDR_PAPERWHITE) paperWhite = MAX_HDR_PAPERWHITE;
				if (paperWhite < MIN_HDR_PAPERWHITE) paperWhite = MIN_HDR_PAPERWHITE;
				if (gameView != nullptr)  gameView->setHDRPaperWhiteBrightness(paperWhite);
				int paperWhiteNorm = (int)((paperWhite - MIN_HDR_PAPERWHITE) * 20 / (MAX_HDR_PAPERWHITE - MIN_HDR_PAPERWHITE));
				const std::string paperWhiteWordDesc = OO_DESC("gameoptions-hdr-paperwhite");
				std::string v1_string = "|||||||||||||||||||||||||";
				std::string v0_string = ".........................";
				v1_string = v1_string.substr(0, static_cast<std::size_t>(paperWhiteNorm));
				v0_string = v0_string.substr(0, static_cast<std::size_t>(20 - paperWhiteNorm));
				gui->setText(oo::str::format("%s%s%s (%d) ", paperWhiteWordDesc.c_str(), v1_string.c_str(), v0_string.c_str(), (int)paperWhite), GUI_ROW(GAME,HDRPAPERWHITE), GUI_ALIGN_CENTER);
			}
			hdrPaperWhiteControlPressed = YES;
		}
		else
			hdrPaperWhiteControlPressed = NO;
	}
#endif
	
	
	if (guiSelectedRow == GUI_ROW(GAME,SHADEREFFECTS) && (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left)))
	{
		if (!shaderSelectKeyPressed || (script_time > timeLastKeyPress + KEY_REPEAT_INTERVAL))
		{
			int direction = (checkKeyPress(n_key_gui_arrow_right)) ? 1 : -1;

			/* (Getafix - 2015/05/07)
			Fix bug coincidentally resulting in Graphics Detail value cycling 
			when left arrow is pressed.
			
			OOGraphicsDetail is an enum type and as such it will never go 
			negative. The following code adjusts "direction" to avoid illegal
			detailLevel values.
			
			Perhaps a more elegant solution could be set in place, restructuring 
			in Universe.m the logic behing setDetailLevelDirectly and 
			setDetailLevel, not forgetting to consider Graphic Detail assigned 
			from various sources (i.e. menu, user prefs file, javascript, etc.). 
			This is postponed in order not to risk the recently announced 
			plans for v1.82 release.
			
			Generally we should decide whether the menu values should cycle or 
			not and apply it for all menu entries.
			*/ 
			if ((((UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) == DETAIL_LEVEL_MINIMUM) && (direction == -1)) || 
					(((UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{}) == DETAIL_LEVEL_MAXIMUM) && (direction == 1)))
				direction = 0;
			
			OOGraphicsDetail detailLevel = (OOGraphicsDetail)(UNIVERSE->getDetailLevel() + direction);
			if (UNIVERSE != nullptr)  UNIVERSE->setDetailLevel(detailLevel);
			detailLevel = (UNIVERSE != nullptr ? UNIVERSE->getDetailLevel() : OOGraphicsDetail{});

			const std::string shaderEffectsOptionsString = cxx_OOExpand("gameoptions-detaillevel-[detailLevel]", detailLevel).value_or(std::string());
			gui->setText(ExpandKeyWithArguments(shaderEffectsOptionsString.c_str(), {}), GUI_ROW(GAME,SHADEREFFECTS), GUI_ALIGN_CENTER);
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW(GAME,SHADEREFFECTS));

			timeLastKeyPress = script_time;
			
			// changing detail level may result in changes to other settings too
			// (e.g. colorblind mode status), so refresh the page
			setGuiToGameOptionsScreen();
			gui->setSelectedRow(GUI_ROW(GAME,SHADEREFFECTS));
		}
		shaderSelectKeyPressed = YES;
	}
	else shaderSelectKeyPressed = NO;
	
#if OOLITE_SDL
	if ((guiSelectedRow == GUI_ROW(GAME,DISPLAYSTYLE)) && selectKeyPress)
	{
		if (gameView != nullptr)  gameView->toggleScreenMode();
		// redraw GUI
		setGuiToGameOptionsScreen();
	}
#endif

	if ((guiSelectedRow == GUI_ROW(GAME,DOCKINGCLEARANCE))&&((checkKeyPress(n_key_gui_arrow_right))||(checkKeyPress(n_key_gui_arrow_left))))
	{
		if (checkKeyPress(n_key_gui_arrow_right) != (UNIVERSE != nullptr ? UNIVERSE->dockingClearanceProtocolActive() : false))
			playChangedOption();
		if (UNIVERSE != nullptr)  UNIVERSE->setDockingClearanceProtocolActive(checkKeyPress(n_key_gui_arrow_right));
		if ((UNIVERSE != nullptr ? UNIVERSE->dockingClearanceProtocolActive() : false))
			gui->setText(OO_DESC("gameoptions-docking-clearance-yes"), GUI_ROW(GAME,DOCKINGCLEARANCE), GUI_ALIGN_CENTER);
		else
			gui->setText(OO_DESC("gameoptions-docking-clearance-no"), GUI_ROW(GAME,DOCKINGCLEARANCE), GUI_ALIGN_CENTER);
	}
	
	if ((guiSelectedRow == GUI_ROW(GAME,BACK)) && selectKeyPress)
	{
		if (gameView != nullptr)  gameView->clearKeys();
		setGuiToLoadSaveScreen();
	}
}


void PlayerEntity::handleKeyMapperScreenKeys()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);

	keyMapperInputHandler(gui, gameView);
	leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up) || checkKeyPress(n_key_gui_page_down);
	if (leftRightKeyPressed)
	{
		std::optional<std::string> key = gui->keyForRow(gui->getSelectedRow());
		if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
		{
			key = gui->keyForRow(GUI_ROW_KC_FUNCEND);
		}
		if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
		{
			key = gui->keyForRow(GUI_ROW_KC_FUNCSTART);
		}
		int from_function = 0;
		const std::vector<std::string> keyComponents = key ? oo::str::split(*key, ":") : std::vector<std::string>();	// a nil key has no components
		if (keyComponents.size() > 1)
		{
			from_function = oo::str::intValue(keyComponents[1]);
			if (from_function < 0)  from_function = 0;
			
			setGuiToKeyMapperScreen(from_function, YES);
			if (UNIVERSE->getGui()->getSelectedRow() < GUI_ROW_KC_FUNCSTART)
			{
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_KC_FUNCSTART);
			}
			if (from_function == 0)
			{
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1);
			}
		}
	}
}


void PlayerEntity::handleKeyboardLayoutKeys()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	
	handleKeyboardLayoutEntryKeys(gui, gameView);
	leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up) || checkKeyPress(n_key_gui_page_down);
	if (leftRightKeyPressed)
	{
		std::optional<std::string> key = gui->keyForRow(gui->getSelectedRow());
		if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
		{
			key = gui->keyForRow(GUI_ROW_KC_FUNCEND);
		}
		if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
		{
			key = gui->keyForRow(GUI_ROW_KC_FUNCSTART);
		}
		int from_function = 0;
		const std::vector<std::string> keyComponents = key ? oo::str::split(*key, ":") : std::vector<std::string>();	// a nil key has no components
		if (keyComponents.size() > 1)
		{
			from_function = oo::str::intValue(keyComponents[1]);
			if (from_function < 0)  from_function = 0;
			
			setGuiToKeyboardLayoutScreen(from_function, YES);
			if (UNIVERSE->getGui()->getSelectedRow() < GUI_ROW_KC_FUNCSTART)
			{
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_KC_FUNCSTART);
			}
			if (from_function == 0)
			{
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1);
			}
		}
	}
}


void PlayerEntity::handleStickMapperScreenKeys()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	
	stickMapperInputHandler(gui, gameView);
	leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up) || checkKeyPress(n_key_gui_page_down);
	if (leftRightKeyPressed)
	{
		std::optional<std::string> key = gui->keyForRow(gui->getSelectedRow());
		if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
		{
			key = gui->keyForRow(GUI_ROW_FUNCEND);
		}
		if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
		{
			key = gui->keyForRow(GUI_ROW_FUNCSTART);
		}
		int from_function = 0;
		const std::vector<std::string> keyComponents = key ? oo::str::split(*key, ":") : std::vector<std::string>();	// a nil key has no components
		if (keyComponents.size() > 1)
		{
			from_function = oo::str::intValue(keyComponents[1]);
			if (from_function < 0)  from_function = 0;
			
			setGuiToStickMapperScreen(from_function, YES);
			if (UNIVERSE->getGui()->getSelectedRow() < GUI_ROW_FUNCSTART)
			{
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_FUNCSTART);
			}
			if (from_function == 0)
			{
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1);
			}
		}
	}
	if((gameView != nullptr ? gameView->isDown(' ') : false))  setGuiToGameOptionsScreen();
}


void PlayerEntity::pollCustomViewControls()
{
	static Quaternion viewQuaternion;
	static Vector viewOffset;
	static Vector rotationCenter;
	static Vector up;
	static Vector right;
	static BOOL mouse_clicked = NO;
	static NSPoint mouse_clicked_position;
	static BOOL shift_down;
	static BOOL caps_on = NO;
	static NSTimeInterval last_time = 0.0;
	::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	const BOOL *joyButtonState = OOJoystickManager::sharedStickHandler()->getAllButtonStates();

	if (checkKeyPress(n_key_custom_view) || joyButtonState[BUTTON_EXTVIEWCYCLE])
	{
		if (!customView_pressed && !_customViews.empty() && gui_screen != GUI_SCREEN_LONG_RANGE_CHART && !(gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}))
		{
			if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) == VIEW_CUSTOM)	// already in custom view mode
			{
				// rotate the custom views
				_customViewIndex = (_customViewIndex + 1) % _customViews.size();
			}
	
			const oo::PList customView = (_customViewIndex < _customViews.size()) ? _customViews[_customViewIndex] : oo::PList();
			setCustomViewDataFromDictionary((customView.isDict() ? customView : oo::PList()), YES);	// null unless a Dict
	
			switchToThisView(VIEW_CUSTOM, NO); // weapon facing must not change, we just want an external view
		}
		customView_pressed = YES;
	}
	else
		customView_pressed = NO;
	NSTimeInterval this_time = oo::date::monotonicSeconds();	// intervals only (last_time)
	if ((UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) > VIEW_STARBOARD && (gameView != nullptr ? gameView->isCapsLockOn() : false))
	{
		BOOL ctrl_down = (gameView != nullptr ? gameView->isCtrlDown() : false);
		float customViewZoomSpeed = ctrl_down ? CUSTOM_VIEW_ZOOM_SPEED * CUSTOM_VIEW_SPEED_REDUCTION_FACTOR: CUSTOM_VIEW_ZOOM_SPEED;
		float customViewRotateSpeed = ctrl_down ? CUSTOM_VIEW_ROTATE_SPEED * CUSTOM_VIEW_SPEED_REDUCTION_FACTOR: CUSTOM_VIEW_ROTATE_SPEED;
		
		if (!caps_on)  caps_on = YES;
		
		OOTimeDelta delta_t = this_time - last_time;
		if ((checkKeyPressIgnoreCtrl(n_key_custom_view_zoom_out, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_zoom_in, YES)) || (gameView != nullptr ? gameView->mouseWheelState() : 0) == gvMouseWheelDown)
		{
			customViewZoomOut(pow(customViewZoomSpeed, delta_t));
		}
		if ((checkKeyPressIgnoreCtrl(n_key_custom_view_zoom_in, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_zoom_out, YES)) || (gameView != nullptr ? gameView->mouseWheelState() : 0) == gvMouseWheelUp)
		{
			customViewZoomIn(pow(customViewZoomSpeed, delta_t));
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_roll_left, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_roll_right, YES))
		{
			customViewRollLeft(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_pan_left, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_pan_right, YES))
		{
			customViewPanLeft(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_roll_right, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_roll_left, YES))
		{
			customViewRollRight(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_pan_right, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_pan_left, YES))
		{
			customViewPanRight(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_up, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_down, YES))
		{
			customViewRotateUp(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_pan_down, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_pan_up, YES))
		{
			customViewPanDown(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_down, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_up, YES))
		{
			customViewRotateDown(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_pan_up, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_pan_down, YES))
		{
			customViewPanUp(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_left, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_right, YES))
		{
			customViewRotateLeft(customViewRotateSpeed * delta_t);
		}
		if (checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_right, YES) && !checkKeyPressIgnoreCtrl(n_key_custom_view_rotate_left, YES))
		{
			customViewRotateRight(customViewRotateSpeed * delta_t);
		}
		if ((gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false))
		{
			if(!mouse_clicked || shift_down != (gameView != nullptr ? gameView->isShiftDown() : false))
			{
				mouse_clicked = YES;
				viewQuaternion = (PLAYER != nullptr ? PLAYER->getCustomViewQuaternion() : Quaternion{});
				viewOffset = (PLAYER != nullptr ? PLAYER->getCustomViewOffset() : Vector{});
				rotationCenter = (PLAYER != nullptr ? PLAYER->getCustomViewRotationCenter() : Vector{});
				up = (PLAYER != nullptr ? PLAYER->getCustomViewUpVector() : Vector{});
				right = (PLAYER != nullptr ? PLAYER->getCustomViewRightVector() : Vector{});
				mouse_clicked_position = (gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint{});
				shift_down = (gameView != nullptr ? gameView->isShiftDown() : false);
			}
			NSPoint mouse_position = (gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint{});
			Vector axis = vector_add(vector_multiply_scalar(up, mouse_position.x - mouse_clicked_position.x),
				vector_multiply_scalar(right, mouse_position.y - mouse_clicked_position.y));
			float angle = magnitude(axis);
			axis = vector_normal(axis);
			Quaternion newViewQuaternion = viewQuaternion;
			if ((gameView != nullptr ? gameView->isShiftDown() : false))
			{
				quaternion_rotate_about_axis(&newViewQuaternion, axis, angle);
				if (PLAYER != nullptr)  PLAYER->setCustomViewQuaternion(newViewQuaternion);
				if (PLAYER != nullptr)  PLAYER->setCustomViewRotationCenter(vector_subtract(viewOffset, vector_multiply_scalar((PLAYER != nullptr ? PLAYER->getCustomViewForwardVector() : Vector{}), dot_product((PLAYER != nullptr ? PLAYER->getCustomViewForwardVector() : Vector{}), viewOffset))));
			}
			else
			{
				quaternion_rotate_about_axis(&newViewQuaternion, axis, -angle);
				OOScalar m = magnitude(vector_subtract(viewOffset, rotationCenter));
				if (PLAYER != nullptr)  PLAYER->setCustomViewQuaternion(newViewQuaternion);
				Vector offset = vector_flip((PLAYER != nullptr ? PLAYER->getCustomViewForwardVector() : Vector{}));
				scale_vector(&offset, m / magnitude(offset));
				if (PLAYER != nullptr)  PLAYER->setCustomViewOffset(vector_add(offset, rotationCenter));
			}
		}
		else
		{
			mouse_clicked = NO;
		}
	}
	else
	{
		mouse_clicked = NO;
		if (caps_on)
		{
			caps_on = NO;
			if (isMouseControlOn())  { if (gameView != nullptr)  gameView->resetMouse(); }
		}
	}
	last_time = this_time;
}


void PlayerEntity::pollViewControls()
{
	if(!pollControls)
		return;
	
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOJoystickManager *stickHandler = OOJoystickManager::sharedStickHandler();
	
	NSPoint			virtualView = NSZeroPoint;
	double			view_threshold = 0.5;
	
	if (stickHandler->joystickCount())
	{
		virtualView = stickHandler->viewAxis();
		if (virtualView.y == STICK_AXISUNASSIGNED)
			virtualView.y = 0.0;
		if (virtualView.x == STICK_AXISUNASSIGNED)
			virtualView.x = 0.0;
		if (fabs(virtualView.y) >= fabs(virtualView.x))
			virtualView.x = 0.0; // forward/aft takes precedence
		else
			virtualView.y = 0.0;
	}
	
	const BOOL *joyButtonState = stickHandler->getAllButtonStates();
	
	//  view keys
	if ((checkKeyPress(n_key_view_forward)) || (virtualView.y < -view_threshold)||joyButtonState[BUTTON_VIEWFORWARD] || (((checkKeyPress(n_key_hyperspace) && gui_screen != GUI_SCREEN_LONG_RANGE_CHART) || joyButtonState[BUTTON_HYPERDRIVE]) && (UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false)))
	{
		switchToThisView(VIEW_FORWARD);
	}
	if ((checkKeyPress(n_key_view_aft))||(virtualView.y > view_threshold)||joyButtonState[BUTTON_VIEWAFT])
	{
		switchToThisView(VIEW_AFT);
	}
	if ((checkKeyPress(n_key_view_port))||(virtualView.x < -view_threshold)||joyButtonState[BUTTON_VIEWPORT])
	{
		switchToThisView(VIEW_PORT);
	}
	if ((checkKeyPress(n_key_view_starboard))||(virtualView.x > view_threshold)||joyButtonState[BUTTON_VIEWSTARBOARD])
	{
		switchToThisView(VIEW_STARBOARD);
	}
	
	pollCustomViewControls();
	
	// Zoom scanner 'z'
	if ((checkKeyPress(n_key_scanner_zoom) && ((gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}) == gvStringInputNo)) || joyButtonState[BUTTON_SCANNERZOOM]) // look for the 'z' key
	{
		if (!scanner_zoom_rate)
		{
			if (((hud != nullptr) ? hud->scannerZoom() : 0.0f) < 5.0)	// a nil HUD answered 0
			{
				if ((((hud != nullptr) ? hud->scannerZoom() : 0.0f) > 1.0)||(!zoom_pressed))
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
	if ((checkKeyPress(n_key_scanner_unzoom) && ((gameView != nullptr ? gameView->getAllowingStringInput() : StringInput{}) == gvStringInputNo)) || joyButtonState[BUTTON_SCANNERUNZOOM]) // look for the 'Z' key
	{
		if ((!scanner_zoom_rate)&&(hud != nullptr && hud->scannerZoom() > 1.0))
			scanner_zoom_rate = SCANNER_ZOOM_RATE_DOWN;
	}
	
	if (EXPECT(getHud() != nullptr && getHud()->isCompassActive()))	// only switch compass modes if there is a compass
	{
		// Compass mode '|'
		if (checkKeyPress(n_key_prev_compass_mode) || joyButtonState[BUTTON_COMPASSMODE_PREV]) // look for the '|' key
		{
			if ((!prev_compass_mode_pressed)&&(compassMode != COMPASS_MODE_BASIC))
				setPrevCompassMode();
			prev_compass_mode_pressed = YES;
		}
		else
		{
			prev_compass_mode_pressed = NO;
		}
		// Compass mode '\'
		if (checkKeyPress(n_key_next_compass_mode) || joyButtonState[BUTTON_COMPASSMODE]) // look for the '\' key
		{
			if ((!next_compass_mode_pressed)&&(compassMode != COMPASS_MODE_BASIC))
				setNextCompassMode();
			next_compass_mode_pressed = YES;
		}
		else
		{
			next_compass_mode_pressed = NO;
		}
	}
	
	// ';' // Cycle active MFD
	if (checkKeyPress(n_key_cycle_next_mfd) || checkKeyPress(n_key_cycle_previous_mfd) || joyButtonState[BUTTON_MFDCYCLENEXT] || joyButtonState[BUTTON_MFDCYCLEPREV])
	{
		if (!cycleMFD_pressed)
		{
			//if (![gameView isCtrlDown]) 
			if (!checkKeyPress(n_key_cycle_previous_mfd) || joyButtonState[BUTTON_MFDCYCLEPREV]) 
			{
				cycleNextMultiFunctionDisplay(activeMFD);
			}
			else
			{
				cyclePreviousMultiFunctionDisplay(activeMFD);
			}
		}
		cycleMFD_pressed = YES;
	}
	else
	{
		cycleMFD_pressed = NO;
	}

	//  ':' // Select next MFD
	if (checkKeyPress(n_key_switch_next_mfd) || checkKeyPress(n_key_switch_previous_mfd) || joyButtonState[BUTTON_MFDSELECTNEXT] || joyButtonState[BUTTON_MFDSELECTPREV])
	{
		if (getHud() != nullptr && getHud()->mfdCount() > 1)
		{
			if (!switchMFD_pressed)
			{
				//if (![gameView isCtrlDown])
				if (!checkKeyPress(n_key_switch_previous_mfd) || joyButtonState[BUTTON_MFDSELECTPREV])
				{
					selectNextMultiFunctionDisplay();
				}
				else
				{
					selectPreviousMultiFunctionDisplay();
				}
			}
		}
		switchMFD_pressed = YES;
	}
	else
	{
		switchMFD_pressed = NO;
	}
				

	//  show comms log '`'
	if (checkKeyPress(n_key_comms_log))
	{
		if (UNIVERSE != nullptr)  UNIVERSE->showCommsLog(1.5);
		if (hud != nullptr)  hud->refreshLastTransmitter();
	}
}


void PlayerEntity::pollFlightArrowKeyControls(double delta_t)
{
	::MyOpenGLView		*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();
	NSUInteger			numSticks = stickHandler->joystickCount();
	NSPoint				virtualStick = NSZeroPoint;
	double				reqYaw = 0.0;
	
	/*	DJS: Handle inputs on the joy roll/pitch axis.
	 Mouse control on takes precedence over joysticks.
	 We have to assume the player has a reason for switching mouse
	 control on if they have a joystick - let them do it. */
	if (mouse_control_on)
	{
		virtualStick=(gameView != nullptr ? gameView->getVirtualJoystickPosition() : NSPoint{});
		double sensitivity = 2.0;
		virtualStick.x *= sensitivity;
		virtualStick.y *= sensitivity;
		reqYaw = virtualStick.x;
	}
	else if (numSticks > 0)
	{
		virtualStick = stickHandler->rollPitchAxis();
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
		reqYaw = stickHandler->getAxisState(AXIS_YAW);
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
	BOOL capsLockCustomView = (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}) == VIEW_CUSTOM && (gameView != nullptr ? gameView->isCapsLockOn() : false);
	
	BOOL	isCtrlDown = (gameView != nullptr ? gameView->isCtrlDown() : false);
	
	const oo::PList arrowPrec = oo::Defaults::standard().object("flight-arrow-key-precision-factor");
	double	flightArrowKeyPrecisionFactor = oo::PListGet<double>::from(arrowPrec.isNull() ? nullptr : &arrowPrec, 0.5);
	if (flightArrowKeyPrecisionFactor < 0.05)  flightArrowKeyPrecisionFactor = 0.05;
	if (flightArrowKeyPrecisionFactor > 1.0)  flightArrowKeyPrecisionFactor = 1.0; 
	
	rolling = NO;
	// if we have yaw on the mouse x-axis, then allow using the keyboard roll keys
	if (!mouse_control_on || (mouse_control_on && mouse_x_axis_map_to_yaw))
	{
		if (checkNavKeyPress(n_key_roll_left) && checkNavKeyPress(n_key_roll_right))
		{
			keyboardRollOverride = YES;
			flightRoll = 0.0;
		}
		else if (checkNavKeyPress(n_key_roll_left) && !capsLockCustomView)
		{
			keyboardRollOverride=YES;
			if (flightRoll > 0.0)  flightRoll = 0.0;
			decrease_flight_roll(isCtrlDown ? flightArrowKeyPrecisionFactor*roll_dampner*roll_delta : delta_t*roll_delta);
			rolling = YES;
		}
		else if (checkNavKeyPress(n_key_roll_right) && !capsLockCustomView)
		{
			keyboardRollOverride=YES;
			if (flightRoll < 0.0)  flightRoll = 0.0;
			increase_flight_roll(isCtrlDown ? flightArrowKeyPrecisionFactor*roll_dampner*roll_delta : delta_t*roll_delta);
			rolling = YES;
		}
	}
	if(((mouse_control_on && !mouse_x_axis_map_to_yaw) || numSticks) && !keyboardRollOverride && !capsLockCustomView)
	{
		stick_roll = max_flight_roll * virtualStick.x;
		if (flightRoll < stick_roll)
		{
			increase_flight_roll(delta_t*roll_delta);
			if (flightRoll > stick_roll)
				flightRoll = stick_roll;
		}
		if (flightRoll > stick_roll)
		{
			decrease_flight_roll(delta_t*roll_delta);
			if (flightRoll < stick_roll)
				flightRoll = stick_roll;
		}
		rolling = (fabs(virtualStick.x) > 0.0);
	}
	if (!rolling)
	{
		if (flightRoll > 0.0)
		{
			if (flightRoll > roll_dampner)	decrease_flight_roll(roll_dampner);
			else	flightRoll = 0.0;
		}
		if (flightRoll < 0.0)
		{
			if (flightRoll < -roll_dampner)   increase_flight_roll(roll_dampner);
			else	flightRoll = 0.0;
		}
	}
	
	pitching = NO;
	// we don't care about pitch keyboard overrides when mouse control is on, only when using joystick
	if (!mouse_control_on)
	{
		if (checkNavKeyPress(n_key_pitch_back) && checkNavKeyPress(n_key_pitch_forward))
		{
			keyboardPitchOverride=YES;
			flightPitch = 0.0;
		}
		else if (checkNavKeyPress(n_key_pitch_back) && !capsLockCustomView)
		{
			keyboardPitchOverride=YES;
			if (flightPitch < 0.0)  flightPitch = 0.0;
			increase_flight_pitch(isCtrlDown ? flightArrowKeyPrecisionFactor*pitch_dampner*pitch_delta : delta_t*pitch_delta);
			pitching = YES;
		}
		else if (checkNavKeyPress(n_key_pitch_forward) && !capsLockCustomView)
		{
			keyboardPitchOverride=YES;
			if (flightPitch > 0.0)  flightPitch = 0.0;
			decrease_flight_pitch(isCtrlDown ? flightArrowKeyPrecisionFactor*pitch_dampner*pitch_delta : delta_t*pitch_delta);
			pitching = YES;
		}
	}
	if((mouse_control_on || (numSticks && !keyboardPitchOverride)) && !capsLockCustomView)
	{
		stick_pitch = max_flight_pitch * virtualStick.y;
		if (flightPitch < stick_pitch)
		{
			increase_flight_pitch(delta_t*pitch_delta);
			if (flightPitch > stick_pitch)
				flightPitch = stick_pitch;
		}
		if (flightPitch > stick_pitch)
		{
			decrease_flight_pitch(delta_t*pitch_delta);
			if (flightPitch < stick_pitch)
				flightPitch = stick_pitch;
		}
		pitching = (fabs(virtualStick.y) > 0.0);
	}
	if (!pitching)
	{
		if (flightPitch > 0.0)
		{
			if (flightPitch > pitch_dampner)	decrease_flight_pitch(pitch_dampner);
			else	flightPitch = 0.0;
		}
		if (flightPitch < 0.0)
		{
			if (flightPitch < -pitch_dampner)	increase_flight_pitch(pitch_dampner);
			else	flightPitch = 0.0;
		}
	}
	
	yawing = NO;
	// if we have roll on the mouse x-axis, then allow using the keyboard yaw keys
	if (!mouse_control_on || (mouse_control_on && !mouse_x_axis_map_to_yaw))
	{
		if (checkNavKeyPress(n_key_yaw_left) && checkNavKeyPress(n_key_yaw_right))
		{
			keyboardYawOverride=YES;
			flightYaw = 0.0;
		}
		else if (checkNavKeyPress(n_key_yaw_left) && !capsLockCustomView)
		{
			keyboardYawOverride=YES;
			if (flightYaw < 0.0)  flightYaw = 0.0;
			increase_flight_yaw(isCtrlDown ? flightArrowKeyPrecisionFactor*yaw_dampner*yaw_delta : delta_t*yaw_delta);
			yawing = YES;
		}
		else if (checkNavKeyPress(n_key_yaw_right) && !capsLockCustomView)
		{
			keyboardYawOverride=YES;
			if (flightYaw > 0.0)  flightYaw = 0.0;
			decrease_flight_yaw(isCtrlDown ? flightArrowKeyPrecisionFactor*yaw_dampner*yaw_delta : delta_t*yaw_delta);
			yawing = YES;
		}
	}
	if(((mouse_control_on && mouse_x_axis_map_to_yaw) || numSticks) && !keyboardYawOverride && !capsLockCustomView)
	{
		// I think yaw is handled backwards in the code,
		// which is why the negative sign is here.
		stick_yaw = max_flight_yaw * (-reqYaw);
		if (flightYaw < stick_yaw)
		{
			increase_flight_yaw(delta_t*yaw_delta);
			if (flightYaw > stick_yaw)
				flightYaw = stick_yaw;
		}
		if (flightYaw > stick_yaw)
		{
			decrease_flight_yaw(delta_t*yaw_delta);
			if (flightYaw < stick_yaw)
				flightYaw = stick_yaw;
		}
		yawing = (fabs(reqYaw) > 0.0);
	}
	if (!yawing)
	{
		if (flightYaw > 0.0)
		{
			if (flightYaw > yaw_dampner)	decrease_flight_yaw(yaw_dampner);
			else	flightYaw = 0.0;
		}
		if (flightYaw < 0.0)
		{
			if (flightYaw < -yaw_dampner)   increase_flight_yaw(yaw_dampner);
			else	flightYaw = 0.0;
		}
	}

}


void PlayerEntity::pollGuiScreenControls()
{
	pollGuiScreenControlsWithFKeyAlias(YES);
}


void PlayerEntity::pollGuiScreenControlsWithFKeyAlias(bool fKeyAlias)
{
	if(!pollControls && fKeyAlias)	// Still OK to run, if we don't use number keys.
		return;
	
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	BOOL			docked_okay = (status() == STATUS_DOCKED);
	
	//  text displays
	if (checkKeyPress(n_key_gui_screen_status, !fKeyAlias))
	{
		if (!switching_status_screens)
		{
			switching_status_screens = YES;
			if (gui_screen == GUI_SCREEN_STATUS)
			{
				noteGUIWillChangeTo(GUI_SCREEN_MANIFEST);
				setGuiToManifestScreen();
			}
			else
				setGuiToStatusScreen();
			checkScript();
		}
	}
	else
	{
		switching_status_screens = NO;
	}
	
	if (checkKeyPress(n_key_gui_chart_screens, !fKeyAlias))
	{
		mouse_left_down = NO;
		if (gameView != nullptr)  gameView->clearMouse();
		if  (!switching_chart_screens)
		{
			switching_chart_screens = YES;
			// handles http://aegidian.org/bb/viewtopic.php?p=233189#p233189
			if (EXPECT_NOT(status() == STATUS_WITCHSPACE_COUNTDOWN && gui_screen == GUI_SCREEN_SHORT_RANGE_CHART)) 
			{
				// don't switch to LRC if countdown in progress
				switching_chart_screens = NO;
			}
			else if (gui_screen == GUI_SCREEN_SHORT_RANGE_CHART || (gui_screen == GUI_SCREEN_SYSTEM_DATA && showingLongRangeChart))
			{
				if (target_chart_zoom != CHART_MAX_ZOOM)
				{
					saved_chart_zoom = target_chart_zoom;
				}
				target_chart_zoom = CHART_MAX_ZOOM;
				noteGUIWillChangeTo(GUI_SCREEN_LONG_RANGE_CHART);
				setGuiToLongRangeChartScreen();
			}
			else
			{
				if (target_chart_zoom == CHART_MAX_ZOOM)
				{
					target_chart_zoom = saved_chart_zoom;
				}
				//target_chart_centre = cursor_coordinates = [[UNIVERSE systemManager] getCoordinatesForSystem:target_system_id inGalaxy:galaxy_number];
				noteGUIWillChangeTo(GUI_SCREEN_SHORT_RANGE_CHART);
				setGuiToShortRangeChartScreen();
			}
		}
	}
	else
	{
		switching_chart_screens = NO;
	}
	
	if (checkKeyPress(n_key_gui_system_data, !fKeyAlias))
	{
		if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
		{
			showingLongRangeChart = (gui_screen == GUI_SCREEN_LONG_RANGE_CHART);
			noteGUIWillChangeTo(GUI_SCREEN_SYSTEM_DATA);
			setGuiToSystemDataScreen();
		}
	}

	if (checkKeyPress(n_key_gui_market, !fKeyAlias))
	{
		if (gui_screen != GUI_SCREEN_MARKET)
		{
			if (gameView != nullptr)  gameView->clearKeys();
			gui->setNoSelectedRow();
			noteGUIWillChangeTo(GUI_SCREEN_MARKET);
			setGuiToMarketScreen();
		}
		else
		{
			if (gameView != nullptr)  gameView->clearKeys();
			gui->setNoSelectedRow();
			noteGUIWillChangeTo(GUI_SCREEN_MARKETINFO);
			setGuiToMarketInfoScreen();
		}
	}
	
	
	if (docked_okay)
	{	
		if ((checkKeyPress(n_key_gui_screen_options, !fKeyAlias)) && (gui_screen != GUI_SCREEN_OPTIONS))
		{
			if (gameView != nullptr)  gameView->clearKeys();
			setGuiToLoadSaveScreen();
		}
		
		if (checkKeyPress(n_key_gui_screen_equipship, !fKeyAlias))
		{
			if (!switching_equipship_screens)
			{
				if (dockedStation() == nil)  setDockedAtMainStation();
				OOGUIScreenID oldScreen = gui_screen;
				
				if ((gui_screen == GUI_SCREEN_EQUIP_SHIP) && (dockedStation() != nullptr ? dockedStation()->hasShipyard() : false))
				{
					if (gameView != nullptr)  gameView->clearKeys();
					noteGUIWillChangeTo(GUI_SCREEN_SHIPYARD);
					gui->setNoSelectedRow();
					setGuiToShipyardScreen(0);
					gui->setSelectedRow(GUI_ROW_SHIPYARD_START);
					showShipyardInfoForSelection();
				}
				else
				{
					if (gameView != nullptr)  gameView->clearKeys();
					noteGUIWillChangeTo(GUI_SCREEN_EQUIP_SHIP);
					gui->setNoSelectedRow();
					setGuiToEquipShipScreen(0);
					gui->setSelectedRow(GUI_ROW_EQUIPMENT_START);
				}
				
				noteGUIDidChangeFrom(oldScreen, gui_screen); 
			}
			switching_equipship_screens = YES;
		}
		else
		{
			switching_equipship_screens = NO;
		}
		
		if (checkKeyPress(n_key_gui_screen_interfaces, !fKeyAlias))
		{
			if (!switching_interface_screens) {
				gui->setNoSelectedRow();
				setGuiToInterfacesScreen(0);
				gui->setSelectedRow(GUI_ROW_INTERFACES_START);
			}
			switching_interface_screens = YES;
		}
		else 
		{
			switching_interface_screens = NO;
		}

	}
}


void PlayerEntity::pollGameOverControls(double /*delta_t*/)
{
	::MyOpenGLView  *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	if ((gameView != nullptr ? gameView->isDown(32) : false))   // look for the spacebar
	{
		if (!spacePressed)
		{
			if (UNIVERSE != nullptr)  UNIVERSE->displayMessage("", 1.0);
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

void PlayerEntity::pollAutopilotControls(double delta_t)
{
	// don't do anything if we're configuring the keyboard
	if (gui_screen == GUI_SCREEN_KEYBOARD_ENTRY || gui_screen == GUI_SCREEN_KEYBOARD_CONFIG || gui_screen == GUI_SCREEN_KEYBOARD_LAYOUT || gui_screen == GUI_SCREEN_KEYBOARD || gui_screen == GUI_SCREEN_KEYBOARD_CONFIRMCLEAR) return;

	const BOOL *joyButtonState = OOJoystickManager::sharedStickHandler()->getAllButtonStates();

	// controls polled while the autopilot is active
	if (!(UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false))
	{
		//  view keys
		pollViewControls();
		
		//  text displays
		pollGuiScreenControls();
		
		if ((UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false))
			pollGuiArrowKeyControls(delta_t);
		
		if (checkKeyPress(n_key_autopilot) || joyButtonState[BUTTON_DOCKCPU]
			|| checkKeyPress(n_key_autodock) || joyButtonState[BUTTON_DOCKCPUFAST])   // look for the 'c' and 'C' key
		{
			if (hasDockingComputer() && !autopilot_key_pressed && !fast_autopilot_key_pressed)
			{
				disengageAutopilot();
				if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("autopilot-off"), 4.5);
			}
			autopilot_key_pressed = YES;
			if (checkKeyPress(n_key_autodock) || joyButtonState[BUTTON_DOCKCPUFAST])
			{
				fast_autopilot_key_pressed = YES;
			}
		}
		else
		{
			autopilot_key_pressed = NO;
			fast_autopilot_key_pressed = NO;
		}
		
		if ((checkKeyPress(n_key_docking_music) || joyButtonState[BUTTON_DOCKINGMUSIC]))   // look for the 's' key
		{
			if (!toggling_music)
			{
				OOMusicController::sharedController()->toggleDockingMusic();
			}
			toggling_music = YES;
		}
		else
		{
			toggling_music = NO;
		}
		// look for the pause game, 'p' key
		if ((checkKeyPress(n_key_pausebutton) || joyButtonState[BUTTON_PAUSE]) && gui_screen != GUI_SCREEN_SHORT_RANGE_CHART && gui_screen != GUI_SCREEN_MISSION && gui_screen != GUI_SCREEN_KEYBOARD_ENTRY)
		{
			if (!autopilot_pause)
			{
				playing_music = OOMusicController::sharedController()->isPlaying();
				if (playing_music)  OOMusicController::sharedController()->toggleDockingMusic();
				// normal flight controls can handle the rest.
				pause_pressed = NO;	// pause button flag must be NO for pollflightControls to react!
				pollFlightControls(delta_t);
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
		if (checkKeyPress(n_key_pausebutton) || joyButtonState[BUTTON_PAUSE])
		{
			if (!autopilot_pause)
			{
				if (playing_music)  OOMusicController::sharedController()->toggleDockingMusic();
			}
			autopilot_pause = YES;
		}
		else
		{
			autopilot_pause = NO;
		}
		// let the normal flight controls handle paused commands.
		pollFlightControls(delta_t);
	}
}


void PlayerEntity::pollDockedControls(double delta_t)
{
	::MyOpenGLView			*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GameController			*gameController = (UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr);
	const BOOL *joyButtonState = OOJoystickManager::sharedStickHandler()->getAllButtonStates();
	const char				*exceptionContext = "setup";
	
	try
	{
		// Pause game, 'p' key
		exceptionContext = "pause key";
		if ((checkKeyPress(n_key_pausebutton) || joyButtonState[BUTTON_PAUSE]) && (gui_screen != GUI_SCREEN_LONG_RANGE_CHART &&
				gui_screen != GUI_SCREEN_REPORT &&
				gui_screen != GUI_SCREEN_SAVE && gui_screen != GUI_SCREEN_KEYBOARD_ENTRY) )
		{
  			BOOL isMissionScreenWithTextEntry = gui_screen == GUI_SCREEN_MISSION && _missionTextEntry;
			if (!pause_pressed)
			{
				if ((gameController != nullptr ? gameController->isGamePaused() : false))
				{
					script_time = saved_script_time;
					if (gameView != nullptr)  gameView->allowStringInput(NO);
					if ((UNIVERSE != nullptr ? UNIVERSE->pauseMessageVisible() : false))
					{
						if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();	// remove the 'paused' message.
					}
					UNIVERSE->getGui()->setForegroundTextureKey("docked_overlay");
					if (gameController != nullptr)  gameController->setGamePaused(NO);
				}
				else
				{
    				if (!isMissionScreenWithTextEntry)
					{
						saved_script_time = script_time;
						UNIVERSE->messageGUI()->clear();
						
						if (UNIVERSE != nullptr)  UNIVERSE->pauseGame();	// 'paused' handler
      				}
				}
			}
   			if (!isMissionScreenWithTextEntry)
      		{
				pause_pressed = YES;
    		}
		}
		else
		{
			pause_pressed = NO;
		}
		
		if ((gameController != nullptr ? gameController->isGamePaused() : false)) return;
		
		if(pollControls)
		{
			exceptionContext = "undock";
			if (checkKeyPress(n_key_launch_ship))
			{
				if (EXPECT((gui_screen != GUI_SCREEN_MISSION || _missionAllowInterrupt) && gui_screen != GUI_SCREEN_KEYBOARD_ENTRY))
				{
					handleUndockControl();
				}
			}
		}
		
		//  text displays
		// mission screens
		exceptionContext = "GUI keys";
		if (gui_screen == GUI_SCREEN_MISSION || gui_screen == GUI_SCREEN_KEYBOARD_ENTRY)
		{
			pollDemoControls(delta_t);	// don't switch away from mission screens
		}
		else
		{
			if (gui_screen != GUI_SCREEN_REPORT)pollGuiScreenControls();	// don't switch away from report screens
		}
		
		pollGuiArrowKeyControls(delta_t);
	}
	catch (...)
	{
		const auto exception = oo::CurrentOOException();
		if (!exception)  throw;	// not an OOException: it goes on up, as before
		OO_LOG(cxx_kOOLogException, "***** Exception in pollDockedControls [{}]: {} : {}", exceptionContext, exception->name(), exception->reason());
	}
}


void PlayerEntity::handleUndockControl()
{
	// FIXME: should this not be in leaveDock:? (Note: leaveDock: is also called from script method launchFromStation and -[StationEntity becomeExplosion]) -- Ahruman 20080308
	if (UNIVERSE != nullptr)  UNIVERSE->setUpUniverseFromStation(); // player pre-launch
	if (dockedStation() == nil)  setDockedAtMainStation();
	
	::StationEntity *dockedStation = this->dockedStation();
	if (dockedStation == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr) && (UNIVERSE != nullptr ? UNIVERSE->getAutoSaveNow() : false) && !(((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->goneNova() : false) || ((UNIVERSE != nullptr ? UNIVERSE->sun() : nullptr) != nullptr ? UNIVERSE->sun()->willGoNova() : false)))
	{
		autosavePlayer();
	}
	launchFromStation();
}


void PlayerEntity::pollDemoControls(double /*delta_t*/)
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	NSUInteger end_row = 21;
	::OOOXZManager *oxzmanager = ::OOOXZManager::sharedManager();

	switch (gui_screen)
	{
		case GUI_SCREEN_INTRO1:
			handleGUIUpDownArrowKeys();

			int row_zero; row_zero = 21;
			if (!selectPressed)
			{
				if (!disc_operation_in_progress)
				{
					if (((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && (gui != nullptr ? gui->getSelectedRow() : 0) == 2+row_zero)
					{
						disc_operation_in_progress = YES;
						if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
						gui->clearBackground();
						if (!loadPlayer())
						{
							setGuiToIntroFirstGo(YES);
						}
						break;
					}
				}
				if (((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && (gui != nullptr ? gui->getSelectedRow() : 0) == 1+row_zero)
				{
					missionTextRow = 0;
					setGuiToScenarioScreen(0);
				} 
				else if (((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && (gui != nullptr ? gui->getSelectedRow() : 0) == 3+row_zero)
				{
					setGuiToIntroFirstGo(NO);
				}
				else if (((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && (gui != nullptr ? gui->getSelectedRow() : 0) == 4+row_zero)
				{
					setGuiToGameOptionsScreen();
				}
				else if (((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && (gui != nullptr ? gui->getSelectedRow() : 0) == 5+row_zero)
				{
					setGuiToOXZManager();
				}
				else if (((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && (gui != nullptr ? gui->getSelectedRow() : 0) == 6+row_zero)
				{
					if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->exitAppWithContext("Exit Game selected on start screen");
				}
				else
				{
					disc_operation_in_progress = NO;
				}
			}
			selectPressed = checkKeyPress(n_key_gui_select);
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
			{
				if (gameView != nullptr)  gameView->clearMouse();
			}
			break;
			
		case GUI_SCREEN_GAMEOPTIONS:
			handleGameOptionsScreenKeys();
			break;
			
		case GUI_SCREEN_KEYBOARD:
			//if ([gameView isDown:' '])	//  '<space>'
			//{
			//	[self setGuiToIntroFirstGo:YES];
			//}
			handleKeyMapperScreenKeys();
			break;

		case GUI_SCREEN_KEYBOARD_CONFIRMCLEAR:
			handleKeyMapperConfirmClearKeys(gui, gameView);
			break;

		case GUI_SCREEN_KEYBOARD_CONFIG:
			handleKeyConfigKeys(gui, gameView);
			break;

		case GUI_SCREEN_KEYBOARD_ENTRY:
			handleKeyConfigEntryKeys(gui, gameView);
			break;

		case GUI_SCREEN_KEYBOARD_LAYOUT:
			handleKeyboardLayoutKeys();
			break;

		case GUI_SCREEN_STICKMAPPER:
			handleStickMapperScreenKeys();
			break;
			
		case GUI_SCREEN_STICKPROFILE:
			stickProfileInputHandler(gui, gameView);
			break;

		case GUI_SCREEN_SHIPLIBRARY:
			if ((gameView != nullptr ? gameView->isDown(' ') : false))	//  '<space>'
			{
				// viewed from start screen, return to it
				setGuiToIntroFirstGo(YES);
			}
			if (checkKeyPress(n_key_gui_arrow_up))	//  '<--'
			{
				if (!upDownKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2Previous();
			}
			if (checkKeyPress(n_key_gui_arrow_down))	//  '-->'
			{
				if (!upDownKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2Next();
			}
			upDownKeyPressed = ((checkKeyPress(n_key_gui_arrow_up))||(checkKeyPress(n_key_gui_arrow_down)));

			if (checkKeyPress(n_key_gui_arrow_left))	//  '<--'
			{
				if (!leftRightKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2PreviousCategory();
			}
			if (checkKeyPress(n_key_gui_arrow_right))	//  '-->'
			{
				if (!leftRightKeyPressed)
					if (UNIVERSE != nullptr)  UNIVERSE->selectIntro2NextCategory();
			}
			leftRightKeyPressed = ((checkKeyPress(n_key_gui_arrow_left))||(checkKeyPress(n_key_gui_arrow_right)));
			

			break;
		
		case GUI_SCREEN_NEWGAME:
			if (handleGUIUpDownArrowKeys())
			{
				showScenarioDetails();
			}

			if (!pageUpDownKeyPressed) 
			{
				if (checkKeyPress(n_key_gui_page_up))
				{
					//  find the Back <<< line, select it and press it
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_SCENARIOS_START - 1).value_or(std::string()), "__page")) 
					{
						if (gui->setSelectedRow(GUI_ROW_SCENARIOS_START - 1)) 
						{
							startScenario();
						}
					}

				}
				else if (checkKeyPress(n_key_gui_page_down))
				{
					// find the Next >>> line, select it and press it
					if (oo::str::hasPrefix(gui->keyForRow(GUI_ROW_SCENARIOS_START + GUI_MAX_ROWS_SCENARIOS).value_or(std::string()), "__page")) 
					{
						if (gui->setSelectedRow(GUI_ROW_SCENARIOS_START + GUI_MAX_ROWS_SCENARIOS)) 
						{
							startScenario();
						}
					}
				}
			}
			pageUpDownKeyPressed = checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);

			if (!selectPressed)
			{
				if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) // enter
				{
					if (!startScenario())
					{
						if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
						setGuiToIntroFirstGo(YES);
					} 
				}
			}
			selectPressed = checkKeyPress(n_key_gui_select);
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || (gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false))
			{
				if (gameView != nullptr)  gameView->clearMouse();
			}
			break;

		case GUI_SCREEN_OXZMANAGER:
			// release locks on music on this screen
			OOMusicController::sharedController()->stopThemeMusic();
			if (EXPECT(!oxzmanager->isRestarting()))
			{
				if (oxzmanager->isAcceptingGUIInput())
				{
					if (oxzmanager->isAcceptingTextInput())
					{
						if (gameView != nullptr)  gameView->setStringInput(gvStringInputAll);
						oxzmanager->refreshTextInput((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or(std::string()));
					}
					else
					{
						if (gameView != nullptr)  gameView->allowStringInput(NO);
					}
					if (handleGUIUpDownArrowKeys())
					{
						// only has an effect on install/remove selection screens
						oxzmanager->showOptionsUpdate();
					}
					if (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up))
					{
						if ((!leftRightKeyPressed))
						{
							oxzmanager->processOptionsPrev();
						}
					}
					else if (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down))
					{
						if ((!leftRightKeyPressed))
						{
							oxzmanager->processOptionsNext();
						}
					}
					leftRightKeyPressed = checkKeyPress(n_key_gui_arrow_right)|checkKeyPress(n_key_gui_arrow_left)|checkKeyPress(n_key_gui_page_down)|checkKeyPress(n_key_gui_page_up);

					if (!selectPressed)
					{
						if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) // enter
						{
							if (oxzmanager->isAcceptingTextInput())
							{
								oxzmanager->processTextInput((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or(std::string()));
							}
							else
							{
								oxzmanager->processSelection();
							}
						}
					}
					selectPressed = checkKeyPress(n_key_gui_select);
					if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || (gameView != nullptr ? gameView->isDown(gvMouseLeftButton) : false))
					{
						if (gameView != nullptr)  gameView->clearMouse();
					}
				} // endif isAcceptingGUIInput
				if (checkKeyPress(n_key_oxzmanager_setfilter) ||
					checkKeyPress(n_key_oxzmanager_showinfo) ||
					checkKeyPress(n_key_oxzmanager_extract))
				{
					if (!oxz_manager_pressed)
					{
						oxz_manager_pressed = YES;
						if (checkKeyPress(n_key_oxzmanager_setfilter))
						{
							oxzmanager->processFilterKey();
						}
						else if (checkKeyPress(n_key_oxzmanager_showinfo))
						{
							oxzmanager->processShowInfoKey();
						}
						else if (checkKeyPress(n_key_oxzmanager_extract))
						{
							oxzmanager->processExtractKey();
						}
						
					}
				}
				else
				{
					oxz_manager_pressed = NO;
				}
			}
			break;
	

	
		case GUI_SCREEN_MISSION:
			if (getHud() != nullptr && getHud()->getAllowBigGui())
			{
				end_row = 27;
			}
			if (_missionTextEntry)
			{
				refreshMissionScreenTextEntry();
				if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))	//  '<enter/return>' or double click
				{
					setMissionChoice((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()), std::string("enter"));
					OOMusicController::sharedController()->stopMissionMusic();
					playDismissedMissionScreen();
					
					handleMissionCallback();
					
					checkScript();
					selectPressed = YES;
					pollControls = YES;
				}
				else
				{
					pollControls = NO;
					selectPressed = NO;
					pollMissionInterruptControls();
				}
			}
			else if (gui->keyForRow(end_row) == "spacebar")
			{
				if ((gameView != nullptr ? gameView->isDown(32) : false))	//  '<space>'
				{
					if (!spacePressed)
					{
						OOMusicController::sharedController()->stopMissionMusic();
						handleMissionCallback();
						
					}
					spacePressed = YES;
				}
				else
				{
					spacePressed = NO;
					pollMissionInterruptControls();
				}
			}
			else
			{
				handleGUIUpDownArrowKeys();
				std::string extraKey;	// "": none
				{
					for (const auto &[key, keydef] : extraMissionKeys)	// ORDER-SENSITIVE: byte order of the keys (was -allKeys hash order)
					{
						if (checkKeyPress(keydef)) {
							if (!extra_key_pressed)
							{
								extraKey = key;
							}
							extra_key_pressed = YES;
						}
						else
						extra_key_pressed = NO;
					}
				}
				if (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || !extraKey.empty())	//  '<enter/return>' or double click
				{
					if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
					{
						selectPressed = NO;
						if (gameView != nullptr)  gameView->clearMouse();
					}
					if (!selectPressed)
					{
						if (extraKey.empty()) extraKey = "enter";
						setMissionChoice(gui->selectedRowKey(), extraKey);
						OOMusicController::sharedController()->stopMissionMusic();
						playDismissedMissionScreen();
						
						handleMissionCallback();
						
						checkScript();
					}
					selectPressed = YES;
				}
				else
				{
					selectPressed = NO;
					pollMissionInterruptControls();
				}
			}
			break;
			
#if OO_USE_CUSTOM_LOAD_SAVE
			// DJS: Farm off load/save screen options to LoadSave.m
		case GUI_SCREEN_LOAD:
		{
			const std::optional<std::string> commanderFile = commanderSelector();
			if(commanderFile)
			{
				// also release the demo ship here (see showShipyardModel and noteGUIDidChangeFrom)
				demoShip = nullptr;

				loadPlayerFromFile(*commanderFile, NO);
			}
			break;
		}
#endif

		default:
			break;
	}
}


void PlayerEntity::pollMissionInterruptControls()
{
	if (_missionAllowInterrupt)
	{
		if (gui_screen == GUI_SCREEN_MISSION && _missionTextEntry) 
		{
			pollGuiScreenControlsWithFKeyAlias(NO);
		}
		else {
			pollGuiScreenControls();
		}
		if (gui_screen != GUI_SCREEN_MISSION)
		{
			if (gui_screen != GUI_SCREEN_SYSTEM_DATA)
			{
				if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
			}
			endMissionScreenAndNoteOpportunity();
		}
	}
}


void PlayerEntity::handleMissionCallback()
{
	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
	UNIVERSE->getGui()->clearBackground();

	setGuiToMissionEndScreen(); // need this to find out if we call a new mission screen inside callback.
	
	if (status() != STATUS_DOCKED) switchToThisView(VIEW_FORWARD);

	if (_missionWithCallback)
	{
		doMissionCallback();
	}
	
	if (status() != STATUS_DOCKED)	// did we launch inside callback? / are we in flight?
	{
		// TODO: This is no longer doing anything because of an 'isDocked' check inside the function. ***** Probably remove it for 1.76
		doWorldEventUntilMissionScreen(OOJSID("missionScreenEnded"));	// no opportunity events.
	}
	else
	{
		if (gui_screen != GUI_SCREEN_MISSION) // did we call a new mission screen inside callback?
		{
			// note that this might not be the same end screen as last time...
			setGuiToMissionEndScreen();	// if not, update status screen with callback changes, if any.
			endMissionScreenAndNoteOpportunity();	// missionScreenEnded, plus opportunity events.
		}
	}
}


void PlayerEntity::setGuiToMissionEndScreen()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	if (gameView != nullptr)  gameView->clearKeys();
	if (status() != STATUS_DOCKED)
	{
		// this setting is only applied when not docked
		setGuiToStatusScreen();
		return;
	}
	switch (_missionExitScreen)
	{
	case GUI_SCREEN_MANIFEST:
		noteGUIWillChangeTo(GUI_SCREEN_MANIFEST);
		setGuiToManifestScreen();
		break;
	case GUI_SCREEN_EQUIP_SHIP:
		noteGUIWillChangeTo(GUI_SCREEN_EQUIP_SHIP);
		setGuiToEquipShipScreen(0);
		break;
	case GUI_SCREEN_SHIPYARD:
		if ((dockedStation() != nullptr ? dockedStation()->hasShipyard() : false))
		{
			noteGUIWillChangeTo(GUI_SCREEN_SHIPYARD);
			setGuiToShipyardScreen(0);
			UNIVERSE->getGui()->setSelectedRow(GUI_ROW_SHIPYARD_START);
			showShipyardInfoForSelection();
		}
		else
		{
			// that doesn't work here
			setGuiToStatusScreen();
		}
		break;
	case GUI_SCREEN_LONG_RANGE_CHART:
		setGuiToLongRangeChartScreen();
		break;
	case GUI_SCREEN_SHORT_RANGE_CHART:
		setGuiToShortRangeChartScreen();
		break;
	case GUI_SCREEN_SYSTEM_DATA:
		noteGUIWillChangeTo(GUI_SCREEN_SYSTEM_DATA);
		setGuiToSystemDataScreen();
		break;
	case GUI_SCREEN_MARKET:
		noteGUIWillChangeTo(GUI_SCREEN_MARKET);
		setGuiToMarketScreen();
		break;
	case GUI_SCREEN_MARKETINFO:
		noteGUIWillChangeTo(GUI_SCREEN_MARKETINFO);
		setGuiToMarketInfoScreen();
		break;
	case GUI_SCREEN_INTERFACES:
		setGuiToInterfacesScreen(0);
		break;
	case GUI_SCREEN_STATUS:
	default: // invalid screen specifications
		setGuiToStatusScreen();
	}
}


void PlayerEntity::switchToThisView(OOViewID viewDirection)
{
	switchToThisView(viewDirection, YES);
}


void PlayerEntity::switchToThisView(OOViewID viewDirection, bool processWeaponFacing)
{
	switchToThisView(viewDirection, (UNIVERSE != nullptr ? UNIVERSE->getViewDirection() : OOViewID{}), processWeaponFacing, NO);
}


void PlayerEntity::switchToThisView(OOViewID viewDirection, OOViewID oldViewDirection, bool processWeaponFacing, bool justNotify)
{
	if (!justNotify)
	{	
		if ((UNIVERSE != nullptr ? UNIVERSE->getDisplayGUI() : false)) switchToMainView();
		if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(viewDirection);
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
			currentWeaponStats();
		}
		else
		{
			OO_LOG_ERR(cxx_kOOLogParameterError, "{} called with processWeaponFacing=YES for non-main view {}.", static_cast<const char *>(__FUNCTION__), static_cast<unsigned>(viewDirection));
		}
	}
	if ((oldViewDirection != viewDirection || viewDirection == VIEW_CUSTOM) && !(UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->isGamePaused() : false))
	{
		ooscript::Context context = OOJSAcquireContext();
		ShipScriptEvent(context, this, "viewDirectionChanged", OOJSValueFromViewID(context, viewDirection), OOJSValueFromViewID(context, oldViewDirection));
		OOJSRelinquishContext(context);
	}
}


// Called on c or Shift-C
void PlayerEntity::handleAutopilotOn(bool fastDocking)
{
	// both declared before the first goto (C++ does not jump over their initialisation)
	std::optional<std::string>	message;
	std::string					stationName;

	// Check alert condition - on red alert, abort
	// -- but only for fast docking
	if (fastDocking && (getAlertCondition() == ALERT_CONDITION_RED))
	{
		playAutopilotCannotDockWithTarget();
		message = cxx_OOExpandKey("autopilot-red-alert");
		goto abort;
	}
	
	Entity *target; target = primaryTarget();	// the C++ entities (bead oo-9ht.39.18)
	// If target isn't dockable, check for nearby stations
	if (!(target != nullptr && target->getIsStation()))
	{
		::Universe  *uni        = UNIVERSE;
		Entity    **entities  = uni->sortedEntities;	// grab the public sorted list
		int       nStations   = 0;
		unsigned  i;
		
		for (i = 0; i < uni->n_entities && nStations < 2; i++)
		{
			if (entities[i]->isStation && oo::ToStation(entities[i]) != nullptr &&
				entities[i]->zero_distance <= SCANNER_MAX_RANGE2)
			{
				nStations++;
				target = entities[i];
			}
		}
		// If inside the Aegis, dock with the main station.
		// If we found one target, dock with it.
		// If outside the Aegis and we found multiple targets, abort.
		
		if (withinStationAegis() && legalStatusValue <= 50)
		{
			target = (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr);
		}
		else if (nStations != 1)
		{
			if (nStations == 0)
			{
				playAutopilotOutOfRange();
				message = cxx_OOExpandKey("autopilot-out-of-range");
			}
			else
			{
				playAutopilotCannotDockWithTarget();
				message = cxx_OOExpandKey("autopilot-multiple-targets");
			}
			goto abort;
		}
	}
	
	// We found a dockable, check whether we can dock with it
	// OOAssert([target isKindOfClass:[StationEntity class]], "Expected entity with isStation flag set to be a station.");		// no need for asserts. Tested enough already.
	::StationEntity *ts; ts = oo::ToStation(target);
	stationName = (ts != nullptr ? ts->getDisplayName() : std::optional<std::string>()).value_or("");	// (nil raised in the expansion)
	
	// If station is not transmitting docking instructions, we cannot use autopilot.
	if (!(ts != nullptr ? ts->getAllowsAutoDocking() : false))
	{
		playAutopilotCannotDockWithTarget();
		message = ExpandKeyWithArguments("autopilot-station-does-not-allow-autodocking", { { "stationName", oo::PList(stationName) } });
	}
	// Deny if station is hostile or player is a fugitive trying to dock at the main station.
	else if ((legalStatusValue > 50 && ts == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr)) || (ts != nullptr ? ts->isHostileTo(this) : false))
	{
		playAutopilotCannotDockWithTarget();
		message = ExpandKeyWithArguments((ts == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr)) ? "autopilot-denied" : "autopilot-target-docking-instructions-denied", { { "stationName", oo::PList(stationName) } });
	}
	// If we're fast-docking, perform the docking logic
	else if (fastDocking && (ts != nullptr ? ts->getAllowsFastDocking() : false))
	{
		// check whether there are docks that do not accept docking - even one such dock will result in rejection
		for (const auto &sub : (ts != nullptr ? ts->dockSubEntities() : std::vector<oo::EntityHold>()))
		{
			// TOO_BIG_TO_DOCK issued when docks are scripted to reject docking
			if((oo::ToDock(sub.get()) != nullptr ? oo::ToDock(sub.get())->canAcceptShipForDocking(this) : std::optional<std::string>()) == "TOO_BIG_TO_DOCK")	// a dock's object is a ship's since bead oo-9ht.180
			{
				message = ExpandKeyWithArguments((ts == (UNIVERSE != nullptr ? UNIVERSE->station() : nullptr)) ? "autopilot-denied" : "autopilot-target-docking-instructions-denied", { { "stationName", oo::PList(stationName) } });
				goto abort;
			}
		}
	
		if (legalStatusValue > 0)
		{
			// there's a slight chance you'll be fined for your past offences when autodocking
			int fine_chance = ranrot_rand() & 0x03ff;	//	0..1023
			int government = 1 + (UNIVERSE != nullptr ? UNIVERSE->currentSystemData() : oo::PList()).get<int>(std::string(KEY_GOVERNMENT));	// 1..8
			if ((UNIVERSE != nullptr ? UNIVERSE->inInterstellarSpace() : false))  government = 2;	// equivalent to Feudal. I'm assuming any station in interstellar space is military. -- Ahruman 2008-05-29
			fine_chance /= government;
			if (fine_chance < legalStatusValue)
			{
				markForFines();
			}
		}
		
		setDockingClearanceStatus(DOCKING_CLEARANCE_STATUS_GRANTED);
		
		if (UNIVERSE != nullptr)  UNIVERSE->forceWitchspaceEntries();
		ship_clock_adjust += 1200.0;			// 20 minutes penalty to enter dock
		ident_engaged = NO;
		safeAllMissiles();
		if (UNIVERSE != nullptr)  UNIVERSE->setViewDirection(VIEW_FORWARD);
		enterDock(ts);
	}
	else
	{
		// Standard docking - engage autopilot
		engageAutopilotToStation(ts);
		message = cxx_OOExpandKey("autopilot-on");
	}
	
abort:
	// Clean-up code
	if (message.has_value()) { if (UNIVERSE != nullptr)  UNIVERSE->addMessage(message, 4.5); }
	return;
}


void PlayerEntity::handleButtonIdent()
{
	// Clear current target if we're already in Ident mode
	if (ident_engaged)  noteLostTarget();
	
	safeAllMissiles();
	ident_engaged = YES;
	if (primaryTarget() == nil)
	{
		playIdentOn();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(cxx_OOExpandKey("ident-on"), 2.0);
	}
	else
	{
		playIdentLockedOn();
		printIdentLockedOnForMissile(NO);
	}
}


void PlayerEntity::handleButtonTargetMissile()
{
	if (!weaponsOnline())
	{
		handleButtonIdent();
		return;
	}
	
	// Clear current target if we're already in Missile Targeting mode
	if (missile_status != MISSILE_STATUS_SAFE)
	{
		noteLostTarget();
	}
	
	// Arm missile and check for missile lock
	missile_status = MISSILE_STATUS_ARMED;
	if ((oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getIsMissile() : false))
	{
		if (oo::EntityIsShip(primaryTarget()))
		{
			missile_status = MISSILE_STATUS_TARGET_LOCKED;
			if (oo::ToShip(missile_entity[activeMissile].get()) != nullptr)  oo::ToShip(missile_entity[activeMissile].get())->addTarget(primaryTarget());
			printIdentLockedOnForMissile(YES);
			playMissileLockedOn();
		}
		else
		{
			// if it's nil, that means it was lost earlier
			if (primaryTarget() != nil)
			{
				noteLostTarget();
			}
			if (oo::ToShip(missile_entity[activeMissile].get()) != nullptr)  oo::ToShip(missile_entity[activeMissile].get())->noteLostTarget();
			const std::string weaponName = (oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getName() : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
			if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithArguments("missile-armed", { { "weaponName", oo::PList(weaponName) } }), 2.0);
			playMissileArmed();
		}
	}
	else if ((oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->isMine() : false))
	{
		const std::string weaponName = (oo::ToShip(missile_entity[activeMissile].get()) != nullptr ? oo::ToShip(missile_entity[activeMissile].get())->getName() : std::optional<std::string>()).value_or(std::string());	// (nil raised in the expansion)
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(ExpandKeyWithArguments("mine-armed", { { "weaponName", oo::PList(weaponName) } }), 2.0);
		playMineArmed();
	}
	ident_engaged = NO;
}

