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

#include "PlayerEntityKeyMapper.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityScriptMethods.h"
#include "OOTexture.h"
#include "HeadUpDisplay.h"
#include "ResourceManager.h"
#include "GameController.h"
#include "OOEquipmentType.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"

static NSUInteger key_index;
static long current_row;
static long kbd_row = GUI_ROW_KC_FUNCSTART;
static BOOL has_error = NO;
static BOOL last_shift = NO;


namespace
{

oo::PList selected_entry;					// a copy of the chosen function entry; null: none (was nil)
oo::PList key_list;							// an Array of key-definition Dicts being edited
oo::PList kdic_check;						// keyconfig2.plist's definitions; null until -initCheckingDictionary
std::vector<std::string> nav_keys;			// functions that can't be used with mod keys
std::vector<std::string> camera_keys;		// functions that can't be used with ctrl

// -oo_stringForKey: where the old code could read nil (proposed ADR-0043): a string, or a number's
// -stringValue; nullopt when the key is absent or holds anything else.
std::optional<std::string> OptionalStringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict.get<std::string>(key);
}


// What %@ printed for a string that may be nil.
std::string DescriptionOfString(const std::optional<std::string> &string)
{
	return string ? *string : std::string("(null)");
}


bool Contains(const std::vector<std::string> &list, const std::string &item)
{
	return std::find(list.begin(), list.end(), item) != list.end();
}


// The "keyboard-code" default as -oo_stringForKey:defaultValue:@"default" read it
// (MyOpenGLView+Input.mm).
std::string KeyboardCode(void)
{
	const oo::PList kbdValue = oo::Defaults::standard().object("keyboard-code");
	return oo::PListGet<std::string>::from(kbdValue.isNull() ? nullptr : &kbdValue, "default");
}


// [[s componentsSeparatedByString:@":"] objectAtIndex:1] intValue], for a row key known to hold a ':'.
int SecondFieldIntValue(const std::string &s)
{
	const std::vector<std::string> fields = oo::str::split(s, ":");
	return fields.size() > 1 ? oo::str::intValue(fields[1]) : 0;
}


// A GUI row built with +arrayWithObjects: stopped at the first nil column.
std::vector<std::string> Columns(std::initializer_list<std::optional<std::string>> columns)
{
	std::vector<std::string> result;
	for (const std::optional<std::string> &column : columns)
	{
		if (!column)  break;
		result.push_back(*column);
	}
	return result;
}


// %@ of a string that may be nil, in a runtime format.
oo::str::FormatArg TextArg(const std::optional<std::string> &string)
{
	return string ? oo::str::FormatArg(*string) : oo::str::FormatArg::null();
}


// Inserts or replaces entry <index> of the key list, as -insertObject:atIndex: /
// -replaceObjectAtIndex:withObject: did (an index past the end appends; it used to raise).
void StoreKeyDefinition(NSUInteger index, oo::PList definition)
{
	oo::PList::Array *keys = key_list.getIf<oo::PList::Array>();
	if (keys == nullptr)  return;	// messaging a nil key_list
	if (index >= keys->size())  keys->push_back(std::move(definition));
	else  (*keys)[index] = std::move(definition);
}


// keyFunctions entry <index>; a null PList out of range (-objectAtIndex: raised).
const oo::PList &KeyFunctionAt(const std::vector<oo::PList> &functions, NSInteger index)
{
	static const oo::PList none;
	return (index >= 0 && static_cast<std::size_t>(index) < functions.size()) ? functions[index] : none;
}


// Element <index> of an array; a null PList for anything else.
const oo::PList &ElementAt(const oo::PList &array, std::size_t index)
{
	static const oo::PList none;
	const oo::PList *element = array.at(index);
	return element != nullptr ? *element : none;
}


// A copy of the KeyConfigOverrides default (+dictionaryWithDictionary: of nil was empty).
oo::PList::Dict KeyConfigOverrides(void)
{
	const oo::PList overrides = oo::Defaults::standard().object(std::string(KEYCONFIG_OVERRIDES));
	const oo::PList::Dict *dict = overrides.getIf<oo::PList::Dict>();
	return dict != nullptr ? *dict : oo::PList::Dict();
}


// The keymappings plist for this platform.
std::string KeyMappingsFileName(void)
{
	std::string map;
#if OOLITE_WINDOWS
	map = "keymappings_windows.plist";
#endif
#if OOLITE_LINUX
	map = "keymappings_linux.plist";
#endif
#if OOLITE_MAC_OS_X
	map = "keymappings_mac.plist";
#endif
	return map;
}


// -isEqualToString:@"" on a value that may be absent.
bool IsEmptyString(const oo::PList *value)
{
	const std::string *string = value != nullptr ? value->getIf<std::string>() : nullptr;
	return string != nullptr && string->empty();
}

// customEquipActivation entry <index>: a null PList past the end (-objectAtIndex: raised there).
const oo::PList &CustomEquipEntry(const std::vector<oo::PList> &entries, NSUInteger index)
{
	static const oo::PList none;
	return (index < entries.size()) ? entries[index] : none;
}


// The fields of customEquipActivation entry <index>, edited in place; nullptr past the end or when
// the entry is not a dictionary (its -setObject:forKey: / -removeObjectForKey: raised there).
oo::PList::Dict *CustomEquipFields(std::vector<oo::PList> &entries, NSUInteger index)
{
	return (index < entries.size()) ? entries[index].getIf<oo::PList::Dict>() : nullptr;
}


// keyconfig2_settings' entry for <key>: null when absent (-objectForKey:, nil for a nil key).
oo::PList KeyConfigEntry(const oo::PList::Dict &settings, const std::optional<std::string> &key)
{
	if (!key.has_value())  return oo::PList();
	const auto it = settings.find(*key);
	return (it != settings.end()) ? it->second : oo::PList();
}

}	// namespace


// sets up a copy of the raw keyconfig.plist file so we can run checks against it to tell if a key is set to default
void PlayerEntity::initCheckingDictionary()
{
	const oo::PList kdicmaster = ResourceManager::dictionaryFromFilesNamed("keyconfig2.plist", std::optional<std::string>("Config"), MERGE_BASIC, NO);
	const std::string kbd = KeyboardCode();
	const oo::PList *kdicValue = kdicmaster.get<oo::PList::Dict>(kbd);
	oo::PList::Dict kdic = (kdicValue != nullptr) ? *kdicValue->getIf<oo::PList::Dict>() : oo::PList::Dict();

	for (auto &[key, value] : kdic)
	{
		if (value.isArray())
		{
			value = processKeyCode(value);
		}
	}
	kdic_check = oo::PList(std::move(kdic));

	// these keys can't be used with mod keys
	nav_keys = { "key_roll_left", "key_roll_right", "key_pitch_forward", "key_pitch_back", "key_yaw_left", "key_yaw_right",
		"key_fire_lasers", "key_gui_arrow_up", "key_gui_arrow_down", "key_gui_arrow_right", "key_gui_arrow_left" };
	// these keys can't be used with ctrl
	camera_keys = { "key_custom_view_zoom_out", "key_custom_view_zoom_in", "key_custom_view_roll_left", "key_custom_view_roll_right",
		"key_custom_view_pan_left", "key_custom_view_pan_right", "key_custom_view_rotate_up", "key_custom_view_rotate_down", "key_custom_view_pan_down",
		"key_custom_view_pan_up", "key_custom_view_rotate_left", "key_custom_view_rotate_right" };
}


void PlayerEntity::resetKeyFunctions()
{
	keyFunctions.clear();
}


void PlayerEntity::setGuiToKeyMapperScreen(unsigned skip)
{
	setGuiToKeyMapperScreen(skip, NO);
}

void PlayerEntity::setGuiToKeyMapperScreen(unsigned skip, bool resetCurrentRow)
{
	const std::string kbd = KeyboardCode();

	::GuiDisplayGen *gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOGUIScreenID oldScreen = gui_screen;
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	tabStop[2] = 400;
	gui->setTabStops(tabStop);

	if (!kdic_check) initCheckingDictionary();

	gui_screen = GUI_SCREEN_KEYBOARD;
	BOOL guiChanged = (oldScreen != gui_screen);
	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);

	gui->clear();
	gui->setTitle(std::string("Configure Keyboard"));

	// show keyboard layout
	gui->setArray(Columns({ OO_DESC("oolite-keyconfig-keyboard"), keyboardDescription(kbd) }), GUI_ROW_KC_SELECTKBD);
	gui->setKey(oo::str::format("kbd:%s", kbd.c_str()), GUI_ROW_KC_SELECTKBD);
	gui->setColor(OOColor::yellowColor().get(), GUI_ROW_KC_SELECTKBD);

	displayKeyFunctionList(gui, skip);

	has_error = NO;
	if (!validateAllKeys().empty())
	{
		has_error = YES;
		gui->setText(OO_DESC("oolite-keyconfig-validation-error"), GUI_ROW_KC_ERROR, GUI_ALIGN_CENTER);
		gui->setColor(OOColor::redColor().get(), GUI_ROW_KC_ERROR);

	}
	gui->setArray(Columns({ OO_DESC("oolite-keyconfig-initial-info-1") }), GUI_ROW_KC_INSTRUCT);
	gui->setText(OO_DESC("oolite-keyconfig-initial-info-2"), GUI_ROW_KC_INSTRUCT+1, GUI_ALIGN_CENTER);
	if (has_error)
	{
		gui->setText(OO_DESC("oolite-keyconfig-initial-error"), GUI_ROW_KC_INSTRUCT+2, GUI_ALIGN_CENTER);
	}
	else
	{
		gui->setText(OO_DESC("oolite-keyconfig-initial-info-3"), GUI_ROW_KC_INSTRUCT+2, GUI_ALIGN_CENTER);
	}

	if (resetCurrentRow)
	{
		int offset = 0;
		if (KeyFunctionAt(keyFunctions, skip).find(std::string(KEY_KC_HEADER)) != nullptr) offset = 1;
		gui->setSelectedRow(GUI_ROW_KC_FUNCSTART + offset);
	}
	else 
	{
		gui->setSelectedRow(current_row);
	}

	gui->setForegroundTextureKey(std::string(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
	gui->setBackgroundTextureKey(std::string("keyboardsettings"));

	if (gameView != nullptr)  gameView->clearMouse();
	if (gameView != nullptr)  gameView->clearKeys();
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);

	if (guiChanged) noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::keyMapperInputHandler(::GuiDisplayGen *gui, ::MyOpenGLView *gameView)
{
	handleGUIUpDownArrowKeys();
	BOOL selectKeyPress = (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false));
	if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))  { if (gameView != nullptr)  gameView->clearMouse(); }

	const std::string key = gui->keyForRow(gui->getSelectedRow()).value_or("");	// a nil key has no prefix
	if (oo::str::hasPrefix(key, "Index:"))
		selFunctionIdx=SecondFieldIntValue(key);
	else
		selFunctionIdx=-1;

	if (selectKeyPress)
	{
		if (oo::str::hasPrefix(key, "More:"))
		{
			int from_function = SecondFieldIntValue(key);
			if (from_function < 0)  from_function = 0;

			current_row = GUI_ROW_KC_FUNCSTART;
			if (from_function == 0) current_row = GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1;
			setGuiToKeyMapperScreen(from_function);
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) { if (gameView != nullptr)  gameView->clearMouse(); }
			return;
		}
		if (oo::str::hasPrefix(key, "kbd:"))
		{
			setGuiToKeyboardLayoutScreen(0);
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) { if (gameView != nullptr)  gameView->clearMouse(); }
			return;
		}
		current_row = gui->getSelectedRow();
		selected_entry = KeyFunctionAt(keyFunctions, selFunctionIdx);
		oo::PList definitions;
		if (!entryIsDictCustomEquip(selected_entry))
		{
			definitions = KeyConfigEntry(keyconfig2_settings, OptionalStringForKey(selected_entry, std::string(KEY_KC_DEFINITION)));
		}
		else
		{
			definitions = getCustomEquipArray(selected_entry.get<std::string>(std::string(KEY_KC_DEFINITION)));
		}
		key_list = definitions.isArray() ? definitions : oo::PList(oo::PList::Array());	// -initWithArray:nil was empty
		if (gameView != nullptr)  gameView->clearKeys();	// try to stop key bounces
		setGuiToKeyConfigScreen(YES);
	}

	if ((gameView != nullptr ? gameView->isDown('u') : false))
	{
		// pressed 'u' on an "more" line
		if (oo::str::hasPrefix(key, "More:")) return;

		current_row = gui->getSelectedRow();
		unsetKeySetting(OptionalStringForKey(KeyFunctionAt(keyFunctions, selFunctionIdx), std::string(KEY_KC_DEFINITION)).value_or(""));
		reloadPage();
	}

	if ((gameView != nullptr ? gameView->isDown('r') : false))
	{
		// reset single entry or all
		if (!(gameView != nullptr ? gameView->isCtrlDown() : false)) 
		{
			// pressed 'r' on an "more" line
			if (oo::str::hasPrefix(key, "More:")) return;

			current_row = gui->getSelectedRow();
			
			const std::optional<std::string> delkey = OptionalStringForKey(KeyFunctionAt(keyFunctions, selFunctionIdx), std::string(KEY_KC_DEFINITION));
			deleteKeySetting(delkey.value_or(""));
			// special case - when default activate/mode key set in custom equipment
			if (entryIsCustomEquip(delkey.value_or("")))
			{
				int idx = getCustomEquipIndex(delkey.value_or(""));
				std::optional<std::string> eq;
				std::optional<std::string> lookupKey;
				bool update = false;

				if (oo::str::hasPrefix(delkey.value_or(""), "activate_"))
				{
					eq = oo::str::replaceOccurrences(*delkey, "activate_", "");
					lookupKey = std::string(CUSTOMEQUIP_KEYACTIVATE);
				}
				if (oo::str::hasPrefix(delkey.value_or(""), "mode_"))
				{
					eq = oo::str::replaceOccurrences(*delkey, "mode_", "");
					lookupKey = std::string(CUSTOMEQUIP_KEYMODE);
				}

				::OOEquipmentType	*item = (eq.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*eq).get() : nil);

				// the customEquipActivation entry is edited in place, as before
				oo::PList::Dict *fields = CustomEquipFields(customEquipActivation, idx);
				if ((item != nullptr ? item->defaultActivateKey() : oo::PList()) && lookupKey == std::string(CUSTOMEQUIP_KEYACTIVATE) && fields != nullptr)
				{
					fields->insert_or_assign(*lookupKey, (item != nullptr ? item->defaultActivateKey() : oo::PList()));
					update = true;
				}
				if ((item != nullptr ? item->defaultModeKey() : oo::PList()) && lookupKey == std::string(CUSTOMEQUIP_KEYMODE) && fields != nullptr)
				{
					fields->insert_or_assign(*lookupKey, (item != nullptr ? item->defaultModeKey() : oo::PList()));
					update = true;
				}

				if (update) 
				{
					oo::Defaults &defaults = oo::Defaults::standard();
					defaults.setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
				}
			}
			
			reloadPage();
		}
		else
		{
			setGuiToConfirmClearScreen();
		}
	}
	if ((gameView != nullptr ? gameView->isDown(' ') : false) && !has_error) setGuiToGameOptionsScreen();
}


bool PlayerEntity::entryIsIndexCustomEquip(NSUInteger idx)
{
	return entryIsCustomEquip(KeyFunctionAt(keyFunctions, idx).get<std::string>(std::string(KEY_KC_DEFINITION)));
}


bool PlayerEntity::entryIsDictCustomEquip(const oo::PList &dict)
{
	return entryIsCustomEquip(dict.get<std::string>(std::string(KEY_KC_DEFINITION)));
}

bool PlayerEntity::entryIsCustomEquip(const std::string &entry)
{
	BOOL result = NO;
	if (oo::str::hasPrefix(entry, "activate_") || oo::str::hasPrefix(entry, "mode_"))
		result = YES;
	return result;
}

oo::PList PlayerEntity::getCustomEquipArray(const std::string &key_def)
{
	std::optional<std::string> eq;
	NSUInteger i;
	std::string key;
	if (oo::str::hasPrefix(key_def, "activate_"))
	{
		eq = oo::str::replaceOccurrences(key_def, "activate_", "");
		key = std::string(CUSTOMEQUIP_KEYACTIVATE);
	}
	if (oo::str::hasPrefix(key_def, "mode_"))
	{
		eq = oo::str::replaceOccurrences(key_def, "mode_", "");
		key = std::string(CUSTOMEQUIP_KEYMODE);
	}
	if (!eq) return oo::PList();
	for (i = 0; i < customEquipActivation.size(); i++)
	{
		const oo::PList equip = customEquipActivation[i];
		if (OptionalStringForKey(equip, std::string(CUSTOMEQUIP_EQUIPKEY)) == eq)
		{
			const oo::PList *array = equip.get<oo::PList::Array>(key);	// -oo_arrayForKey:
			return array != nullptr ? *array : oo::PList();
		}
	}
	return oo::PList();
}


NSUInteger PlayerEntity::getCustomEquipIndex(const std::string &key_def)
{
	std::optional<std::string> eq;
	NSUInteger i;
	if (oo::str::hasPrefix(key_def, "activate_"))
	{
		eq = oo::str::replaceOccurrences(key_def, "activate_", "");
	}
	if (oo::str::hasPrefix(key_def, "mode_"))
	{
		eq = oo::str::replaceOccurrences(key_def, "mode_", "");
	}
	if (!eq) return -1;
	for (i = 0; i < customEquipActivation.size(); i++)
	{
		if (OptionalStringForKey(customEquipActivation[i], std::string(CUSTOMEQUIP_EQUIPKEY)) == eq)
		{
			return i;
		}
	}
	return -1;
}


std::optional<std::string> PlayerEntity::getCustomEquipKeyDefType(const std::string &key_def)
{
	if (oo::str::hasPrefix(key_def, "activate_"))
	{
		return std::string(CUSTOMEQUIP_KEYACTIVATE);
	}
	if (oo::str::hasPrefix(key_def, "mode_"))
	{
		return std::string(CUSTOMEQUIP_KEYMODE);
	}
	return std::string();
}


void PlayerEntity::setGuiToKeyConfigScreen()
{
	setGuiToKeyConfigScreen(NO);
}


void PlayerEntity::setGuiToKeyConfigScreen(bool resetSelectedRow)
{
	NSUInteger i = 0;
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIScreenID oldScreen = gui_screen;
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	gui->setTabStops(tabStop);

	gui_screen = GUI_SCREEN_KEYBOARD_CONFIG;
	BOOL guiChanged = (oldScreen != gui_screen);
	gui->clear();
	gui->setTitle(OO_DESC("oolite-keyconfig-update-title"));	// @"%@"

	gui->setArray(Columns({ OO_DESC("oolite-keyconfig-update-function"), OptionalStringForKey(selected_entry, std::string(KEY_KC_GUIDESC)) }), GUI_ROW_KC_UPDATE_FUNCNAME);
	gui->setColor(OOColor::greenColor().get(), GUI_ROW_KC_UPDATE_FUNCNAME);

	std::optional<std::string> keystring;
	std::optional<std::string> keyshift;
	std::optional<std::string> keymod1;
	std::optional<std::string> keymod2;

	OOKeyCode k_int;

	// get each key for the first two item in the selected entry
	for (i = 0; i <= 1; i++)
	{
		keystring = OO_DESC("oolite-keycode-unset");
		keyshift = OO_DESC("oolite-keyconfig-modkey-off");
		keymod1 = OO_DESC("oolite-keyconfig-modkey-off");
		keymod2 = OO_DESC("oolite-keyconfig-modkey-off");

		if (key_list.count() > i)
		{
			const oo::PList &def = *key_list.at(i);
			k_int = (OOKeyCode)def.get<long long>("key");	// -integerValue
			if (k_int > 0)
			{
				keystring = keyCodeDescription(k_int);
				if (def.get<bool>("shift") == YES) keyshift = OO_DESC("oolite-keyconfig-modkey-on");
				if (def.get<bool>("mod1") == YES) keymod1 = OO_DESC("oolite-keyconfig-modkey-on");
				if (def.get<bool>("mod2") == YES) keymod2 = OO_DESC("oolite-keyconfig-modkey-on");
			}
		}

		outputKeyDefinition(keystring.value_or(""), keyshift.value_or(""), keymod1.value_or(""), keymod2.value_or(""), (i * 5));
	}

	const std::string definition = selected_entry.get<std::string>(std::string(KEY_KC_DEFINITION));
	std::optional<std::string> helper = OO_DESC("oolite-keyconfig-update-helper");
	if (Contains(nav_keys, definition))
		helper = oo::str::format("%s %s", DescriptionOfString(helper).c_str(), OO_DESC("oolite-keyconfig-update-navkeys").c_str());
	if (Contains(camera_keys, definition))
		helper = oo::str::format("%s %s", DescriptionOfString(helper).c_str(), OO_DESC("oolite-keyconfig-update-camkeys").c_str());
	gui->addLongText(helper, GUI_ROW_KC_UPDATE_INFO, GUI_ALIGN_LEFT);

	gui->setText("", GUI_ROW_KC_VALIDATION);

	gui->setText(OO_DESC("oolite-keyconfig-update-save"), GUI_ROW_KC_SAVE, GUI_ALIGN_CENTER);
	gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_SAVE);

	gui->setText(OO_DESC("oolite-keyconfig-update-cancel"), GUI_ROW_KC_CANCEL, GUI_ALIGN_CENTER);
	gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_CANCEL);

	gui->setSelectableRange(NSMakeRange(GUI_ROW_KC_KEY, (GUI_ROW_KC_CANCEL - GUI_ROW_KC_KEY) + 1));

	const std::optional<std::string> validate = validateKey(definition, key_list);
	if (validate)
	{
		for (i = 0; i < keyFunctions.size(); i++)
		{
			if (OptionalStringForKey(keyFunctions[i], std::string(KEY_KC_DEFINITION)) == validate)
			{
				gui->setText(oo::str::formatRuntime(OO_DESC("oolite-keyconfig-update-validation-@"), { TextArg(OptionalStringForKey(keyFunctions[i], std::string(KEY_KC_GUIDESC))) }), GUI_ROW_KC_VALIDATION, GUI_ALIGN_CENTER);
				gui->setColor(OOColor::orangeColor().get(), GUI_ROW_KC_VALIDATION);
				break;
			}
		}
	}

	if (resetSelectedRow)
	{
		gui->setSelectedRow(GUI_ROW_KC_KEY);
	}

	gui->setForegroundTextureKey(std::string(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
	gui->setBackgroundTextureKey(std::string("keyboardsettings"));
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();
	if (guiChanged) noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::outputKeyDefinition(const std::string &key, const std::string &shift, const std::string &mod1, const std::string &mod2, NSUInteger skiprows)
{
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::string definition = selected_entry.get<std::string>(std::string(KEY_KC_DEFINITION));

	gui->setArray(Columns({ std::optional<std::string>(skiprows == 0 ? OO_DESC("oolite-keyconfig-update-key") : OO_DESC("oolite-keyconfig-update-alternate")), key }), GUI_ROW_KC_KEY + skiprows);
	gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_KEY + skiprows);

	if (!Contains(nav_keys, definition)) {
		if (!(OO_DESC("oolite-keycode-unset") == key))
		{
			gui->setArray(Columns({ OO_DESC("oolite-keyconfig-update-shift"), shift }), GUI_ROW_KC_SHIFT + skiprows);
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_SHIFT + skiprows);

			// camera movement keys can't use ctrl
			if (!Contains(camera_keys, definition)) {
				gui->setArray(Columns({ OO_DESC("oolite-keyconfig-update-mod1"), mod1 }), GUI_ROW_KC_MOD1 + skiprows);
				gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_MOD1 + skiprows);
			}
			else
			{
				gui->setArray(Columns({ OO_DESC("oolite-keyconfig-update-mod1"), OO_DESC("not-applicable") }), GUI_ROW_KC_MOD1 + skiprows);
			}

#if OOLITE_MAC_OS_X
			[gui cxx_setArray:Columns({ OO_DESC("oolite-keyconfig-update-mod2-mac"), mod2 })
							forRow:GUI_ROW_KC_MOD2 + skiprows];
#else
			gui->setArray(Columns({ OO_DESC("oolite-keyconfig-update-mod2-pc"), mod2 }), GUI_ROW_KC_MOD2 + skiprows);
#endif
			gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_MOD2 + skiprows);
		}
	}
}


void PlayerEntity::handleKeyConfigKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView)
{
	handleGUIUpDownArrowKeys();
	BOOL selectKeyPress = (checkKeyPress(n_key_gui_select)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false));
	if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))  { if (gameView != nullptr)  gameView->clearMouse(); }
	
	if (selectKeyPress && (gui->getSelectedRow() == GUI_ROW_KC_KEY || gui->getSelectedRow() == (GUI_ROW_KC_KEY + 5)))
	{
		key_index = (gui->getSelectedRow() == GUI_ROW_KC_KEY ? 0 : 1);
		setGuiToKeyConfigEntryScreen();
	}

	if (selectKeyPress && (gui->getSelectedRow() == GUI_ROW_KC_SHIFT || gui->getSelectedRow() == (GUI_ROW_KC_SHIFT + 5)))
	{
		updateShiftKeyDefinition("shift", (gui->getSelectedRow() == GUI_ROW_KC_SHIFT ? 0 : 1));
		setGuiToKeyConfigScreen();
	}
	if (selectKeyPress && (gui->getSelectedRow() == GUI_ROW_KC_MOD1 || gui->getSelectedRow() == (GUI_ROW_KC_MOD1 + 5)))
	{
		updateShiftKeyDefinition("mod1", (gui->getSelectedRow() == GUI_ROW_KC_MOD1 ? 0 : 1));
		setGuiToKeyConfigScreen();
	}
	if (selectKeyPress && (gui->getSelectedRow() == GUI_ROW_KC_MOD2 || gui->getSelectedRow() == (GUI_ROW_KC_MOD2 + 5)))
	{
		updateShiftKeyDefinition("mod2", (gui->getSelectedRow() == GUI_ROW_KC_MOD2 ? 0 : 1));
		setGuiToKeyConfigScreen();
	}

	if (selectKeyPress && gui->getSelectedRow() == GUI_ROW_KC_SAVE)
	{
		saveKeySetting(OptionalStringForKey(selected_entry, std::string(KEY_KC_DEFINITION)).value_or(""));
		reloadPage();
	}

	if ((selectKeyPress && gui->getSelectedRow() == GUI_ROW_KC_CANCEL) || (gameView != nullptr ? gameView->isDown(27) : false))
	{
		// esc or Cancel was pressed - get out of here
		reloadPage();
	}
}


void PlayerEntity::setGuiToKeyConfigEntryScreen()
{
	::GuiDisplayGen *gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOGUIScreenID oldScreen = gui_screen;
	gui_screen = GUI_SCREEN_KEYBOARD_ENTRY;
	BOOL guiChanged = (oldScreen != gui_screen);

	// make sure the index we're looking for exists
	oo::PList::Array *keys = key_list.getIf<oo::PList::Array>();
	if (keys != nullptr && keys->size() < (key_index + 1))
	{
		// add the missing element to the array
		keys->push_back(oo::PList(oo::PList::Dict{ { "key", oo::PList("") }, { "shift", oo::PList(false) }, { "mod1", oo::PList(false) }, { "mod2", oo::PList(false) } }));
	}
	const oo::PList *def = key_list.at(key_index);
	//if ([key isEqualToString:@"(not set)"]) key = @"";
	OOKeyCode k_int = (OOKeyCode)(def != nullptr ? def->get<long long>("key") : 0);	// -integerValue
	if (gameView != nullptr)  gameView->resetTypedString();
	if (gameView != nullptr)  gameView->setTypedString((k_int != 0 ? keyCodeDescriptionShort(k_int).value_or(std::string()) : std::string()));
	if (gameView != nullptr)  gameView->setStringInput(gvStringInputAll);

	gui->clear();
	gui->setTitle(OO_DESC("oolite-keyconfig-update-entry-title"));	// @"%@"

	NSUInteger end_row = 21;
	if (getHud() != nullptr && getHud()->getAllowBigGui())
	{
		end_row = 27;
	}

	gui->addLongText(OO_DESC("oolite-keyconfig-update-entry-info"), GUI_ROW_KC_ENTRY_INFO, GUI_ALIGN_LEFT);

	gui->setText(oo::str::formatRuntime(OO_DESC("Key: %@"), { TextArg((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>())) }), end_row, GUI_ALIGN_LEFT);
	gui->setColor(OOColor::cyanColor().get(), end_row);
	gui->setSelectableRange(NSMakeRange(0,0));

	gui->setShowTextCursor(YES);
	gui->setCurrentRow(end_row);

	gui->setForegroundTextureKey(std::string(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
	gui->setBackgroundTextureKey(std::string("keyboardsettings"));
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);

	if (gameView != nullptr)  gameView->clearMouse();
	if (gameView != nullptr)  gameView->clearKeys();
	if (guiChanged) noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::handleKeyConfigEntryKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView)
{
	NSUInteger end_row = 21;
	if (getHud() != nullptr && getHud()->getAllowBigGui()) 
	{
		end_row = 27;
	}

	handleGUIUpDownArrowKeys();
	if ((gameView != nullptr ? gameView->lastKeyWasShifted() : false)) last_shift = YES;

	gui->setText(oo::str::formatRuntime(OO_DESC("Key: %@"), { TextArg((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>())) }), end_row);
	gui->setColor(OOColor::cyanColor().get(), end_row);

	if (checkKeyPress(n_key_gui_select)) 
	{
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
		// update function key
		updateKeyDefinition((gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or(""), key_index);
		if (gameView != nullptr)  gameView->clearKeys();	// try to stop key bounces
		setGuiToKeyConfigScreen(YES);
	}
	if ((gameView != nullptr ? gameView->isDown(27) : false)) // escape
	{
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
		// don't update function key
		setGuiToKeyConfigScreen(YES);
	}
}

// updates the overridden definition of a key to a new keycode value
void PlayerEntity::updateKeyDefinition(const std::string &keystring, NSUInteger index)
{
	const oo::PList *entry = key_list.at(index);
	oo::PList::Dict key_def = (entry != nullptr && entry->isDict()) ? *entry->getIf<oo::PList::Dict>() : oo::PList::Dict();	// a value copy
	key_def["key"] = oo::PList(keystring);
	// auto=turn on shift if the entered key was shifted

	if (last_shift && oo::str::length(keystring) == 1 && !Contains(nav_keys, selected_entry.get<std::string>(std::string(KEY_KC_DEFINITION))))
	{
		key_def["shift"] = oo::PList(true);
	}
	if (!last_shift && oo::str::length(keystring) == 1)
	{
		key_def["shift"] = oo::PList(false);
	}
	last_shift = NO;
	StoreKeyDefinition(index, oo::PList(std::move(key_def)));
	key_list = processKeyCode(key_list);
}


// changes the shift/ctrl/alt state of an overridden definition
void PlayerEntity::updateShiftKeyDefinition(const std::string &key, NSUInteger index)
{
	const oo::PList *entry = key_list.at(index);
	oo::PList key_def = (entry != nullptr && entry->isDict()) ? *entry : oo::PList(oo::PList::Dict());	// a value copy
	oo::PList::Dict &key_fields = *key_def.getIf<oo::PList::Dict>();
	BOOL current = key_def.get<bool>(key);
	BOOL keycode_changed = NO;
	current = !current;
	key_fields[key] = oo::PList(static_cast<bool>(current));
	if (key == "shift")
	{
		// force the key into upper or lower case, to limit invalid key combos as much as possible
		NSInteger k_int = (OOKeyCode)key_def.get<long long>("key");	// -integerValue
		if (k_int > 0)
		{
			const std::optional<std::string> keystring = keyCodeDescription(k_int);
			std::optional<std::string> newstring;
			if (keystring && oo::str::length(*keystring) == 1)
			{
				// try switching the case. for characters that can't be switched (eg 1,2,3,etc), this should do nothing
				if (current)
				{
					newstring = oo::str::uppercase(*keystring);
				}
				else
				{
					newstring = oo::str::lowercase(*keystring);
				}
				if (newstring != keystring)
				{
					key_fields["key"] = oo::PList(*newstring);
					keycode_changed = YES;
				}
			}
		}
	}
	StoreKeyDefinition(index, std::move(key_def));
	if (keycode_changed)
	{
		key_list = processKeyCode(key_list);
	}
}


void PlayerEntity::setGuiToConfirmClearScreen()
{
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOGUIScreenID oldScreen = gui_screen;

	gui_screen = GUI_SCREEN_KEYBOARD_CONFIRMCLEAR;
	BOOL guiChanged = (oldScreen != gui_screen);

	gui->clear();
	gui->setTitle(OO_DESC("oolite-keyconfig-clear-overrides-title"));	// @"%@"

	gui->addLongText(OO_DESC("oolite-keyconfig-clear-overrides"),	// @"%@"
					 GUI_ROW_KC_CONFIRMCLEAR, GUI_ALIGN_LEFT);

	gui->setText(OO_DESC("oolite-keyconfig-clear-yes"), GUI_ROW_KC_CONFIRMCLEAR_YES, GUI_ALIGN_CENTER);
	gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_CONFIRMCLEAR_YES);

	gui->setText(OO_DESC("oolite-keyconfig-clear-no"), GUI_ROW_KC_CONFIRMCLEAR_NO, GUI_ALIGN_CENTER);
	gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_KC_CONFIRMCLEAR_NO);

	gui->setSelectableRange(NSMakeRange(GUI_ROW_KC_CONFIRMCLEAR_YES, 2));
	gui->setSelectedRow(GUI_ROW_KC_CONFIRMCLEAR_NO);

	gui->setForegroundTextureKey(std::string(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
	gui->setBackgroundTextureKey(std::string("keyboardsettings"));

	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearMouse();
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->clearKeys();
	if (guiChanged) noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::handleKeyMapperConfirmClearKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView)
{
	handleGUIUpDownArrowKeys();

	BOOL selectKeyPress = (checkKeyPress(n_key_gui_select)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false));
	if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) { if (gameView != nullptr)  gameView->clearMouse(); }

	// Translation issue: we can't confidently use raw Y and N ascii as shortcuts. It's better to use the load-previous-commander keys.
	const oo::PList *yesValue = UNIVERSE->descriptions()->find("load-previous-commander-yes");
	const oo::PList *noValue = UNIVERSE->descriptions()->find("load-previous-commander-no");
	const std::u16string valueYes = oo::utf8ToUtf16(oo::str::lowercase(oo::PListGet<std::string>::from(yesValue, "y")));
	const std::u16string valueNo = oo::utf8ToUtf16(oo::str::lowercase(oo::PListGet<std::string>::from(noValue, "n")));
	unsigned char cYes, cNo;

	cYes = (valueYes.empty() ? 0 : valueYes[0]) & 0x00ff;	// Use lower byte of unichar.
	cNo = (valueNo.empty() ? 0 : valueNo[0]) & 0x00ff;	// Use lower byte of unichar.
	
	if ((selectKeyPress && (gui->getSelectedRow() == GUI_ROW_KC_CONFIRMCLEAR_YES))||(gameView != nullptr ? gameView->isDown(cYes) : false)||(gameView != nullptr ? gameView->isDown(cYes - 32) : false))
	{
		deleteAllKeySettings();
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
		setGuiToKeyMapperScreen(0, YES);
	}
	
	if ((selectKeyPress && (gui->getSelectedRow() == GUI_ROW_KC_CONFIRMCLEAR_NO))||(gameView != nullptr ? gameView->isDown(27) : false)||(gameView != nullptr ? gameView->isDown(cNo) : false)||(gameView != nullptr ? gameView->isDown(cNo - 32) : false))
	{
		// esc or NO was pressed - get out of here
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
		setGuiToKeyMapperScreen(0, YES);
	}
}


void PlayerEntity::displayKeyFunctionList(::GuiDisplayGen *gui, NSUInteger skip)
{
	gui->setColor(OOColor::greenColor().get(), GUI_ROW_KC_HEADING);
	gui->setArray({ "Function", "Assigned to", "Overrides" }, GUI_ROW_KC_HEADING);

	const oo::PList overrides = loadKeySettings();

	if(keyFunctions.empty())	// the list is never empty once built
	{
		keyFunctions = keyFunctionList();
	}

	NSUInteger i, n_functions = keyFunctions.size();
	NSInteger n_rows, start_row, previous = 0;
	std::optional<std::string> validate;

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
			gui->setColor(OOColor::greenColor().get(), GUI_ROW_KC_FUNCSTART);
			gui->setArray(Columns({ OO_DESC("gui-back"), " <-- " }), GUI_ROW_KC_FUNCSTART);
			gui->setKey(oo::str::format("More:%zd", previous), GUI_ROW_KC_FUNCSTART);
		}
		
		for(i = 0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			const oo::PList &entry = keyFunctions[i + skip];
			if (entry.find(std::string(KEY_KC_HEADER)) != nullptr) {
				const std::optional<std::string> header = OptionalStringForKey(entry, std::string(KEY_KC_HEADER));
				gui->setArray(Columns({ header, "", "" }), i + start_row);
				gui->setColor(OOColor::cyanColor().get(), i + start_row);
			}
			else
			{
				const std::optional<std::string> definition = OptionalStringForKey(entry, std::string(KEY_KC_DEFINITION));
				std::optional<std::string> assignment;
				std::string override;
				if (!entryIsDictCustomEquip(entry))
				{
					// Find out what's assigned for this function currently.
					assignment = (PLAYER != nullptr ? PLAYER->keyBindingDescription2(definition.value_or(std::string())) : std::optional<std::string>());
					override = (definition && overrides.find(*definition) != nullptr ? "Yes" : ""); // work out whether this assignment is overriding the setting in keyconfig2.plist
					validate = validateKey(definition.value_or(""), KeyConfigEntry(keyconfig2_settings, definition));
				}
				else
				{
					const std::optional<std::string> custom_keytype = getCustomEquipKeyDefType(definition.value_or(""));
					NSUInteger idx = getCustomEquipIndex(definition.value_or(""));
					const oo::PList &equip = CustomEquipEntry(customEquipActivation, idx);
					const oo::PList *keyArray = equip.get<oo::PList::Array>(custom_keytype.value_or(""));	// -oo_arrayForKey:
					assignment = (PLAYER != nullptr ? PLAYER->getKeyBindingDescription((keyArray != nullptr ? *keyArray : oo::PList())) : std::optional<std::string>());
					const std::optional<std::string> itemKey = OptionalStringForKey(equip, std::string(CUSTOMEQUIP_EQUIPKEY));
					::OOEquipmentType	*item = itemKey.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*itemKey).get() : nil;
					bool result = true;
					int j, k;
					oo::PList defArray;
					oo::PList compArray;

					if (custom_keytype == std::string(CUSTOMEQUIP_KEYACTIVATE))
					{
						defArray = (item != nullptr ? item->defaultActivateKey() : oo::PList());
						compArray = keyArray != nullptr ? *keyArray : oo::PList();
					}
					if (custom_keytype == std::string(CUSTOMEQUIP_KEYMODE))
					{
						defArray = (item != nullptr ? item->defaultModeKey() : oo::PList());
						compArray = keyArray != nullptr ? *keyArray : oo::PList();
					}
					for (j = 0; static_cast<std::size_t>(j) < defArray.count(); j++)
					{
						for (k = 0; static_cast<std::size_t>(k) < compArray.count(); k++)
						{
							if (!compareKeyEntries(ElementAt(defArray, j), ElementAt(compArray, k)))
							{
								result = false;
								break;
							}
						}
						if (result == false) break;
					}

					override = (!result ? "Yes" : "");
					validate = validateKey(definition.value_or(""), (keyArray != nullptr ? *keyArray : oo::PList()));
				}
				if (!assignment)
				{
					assignment = "   -   ";
				}

				gui->setArray(Columns({ OptionalStringForKey(entry, std::string(KEY_KC_GUIDESC)), assignment, override }), i + start_row);
				gui->setKey(oo::str::format("Index:%zu", i + skip), i + start_row);
				if (validate) 
				{
					gui->setColor(OOColor::orangeColor().get(), i + start_row);
				}
			}
		}
		if (i < n_functions - skip)
		{
			gui->setColor(OOColor::greenColor().get(), start_row + i);
			gui->setArray(Columns({ OO_DESC("gui-more"), " --> " }), start_row + i);
			gui->setKey(oo::str::format("More:%zu", n_rows + skip), start_row + i);
			i++;
		}
		
		gui->setSelectableRange(NSMakeRange(GUI_ROW_KC_SELECTKBD, (i + start_row - GUI_ROW_KC_FUNCSTART) + (GUI_ROW_KC_FUNCSTART - GUI_ROW_KC_SELECTKBD)));
	}
}


std::vector<oo::PList> PlayerEntity::keyFunctionList()
{
	std::vector<oo::PList> funcList;

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-screen-access")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_launch_ship"), "key_launch_ship"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_screen_options"), "key_gui_screen_options"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_screen_equipship"), "key_gui_screen_equipship"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_screen_interfaces"), "key_gui_screen_interfaces"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_screen_status"), "key_gui_screen_status"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_chart_screens"), "key_gui_chart_screens"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_system_data"), "key_gui_system_data"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_market"), "key_gui_market"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-propulsion")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_roll_left"), "key_roll_left"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_roll_right"), "key_roll_right"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_pitch_forward"), "key_pitch_forward"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_pitch_back"), "key_pitch_back"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_yaw_left"), "key_yaw_left"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_yaw_right"), "key_yaw_right"));

	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_increase_speed"), "key_increase_speed"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_decrease_speed"), "key_decrease_speed"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_inject_fuel"), "key_inject_fuel"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_jumpdrive"), "key_jumpdrive"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_hyperspace"), "key_hyperspace"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_galactic_hyperspace"), "key_galactic_hyperspace"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-navigation")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_next_compass_mode"), "key_next_compass_mode"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_prev_compass_mode"), "key_prev_compass_mode"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_scanner_zoom"), "key_scanner_zoom"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_scanner_unzoom"), "key_scanner_unzoom"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_view_forward"), "key_view_forward"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_view_aft"), "key_view_aft"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_view_port"), "key_view_port"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_view_starboard"), "key_view_starboard"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_ident_system"), "key_ident_system"));

	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_docking_clearance_request"), "key_docking_clearance_request"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_autopilot"), "key_autopilot"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_autodock"), "key_autodock"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_docking_music"), "key_docking_music"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-offensive")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_weapons_online_toggle"), "key_weapons_online_toggle"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_fire_lasers"), "key_fire_lasers"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_launch_missile"), "key_launch_missile"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_target_missile"), "key_target_missile"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_untarget_missile"), "key_untarget_missile"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_target_incoming_missile"), "key_target_incoming_missile"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_next_missile"), "key_next_missile"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_next_target"), "key_next_target"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_previous_target"), "key_previous_target"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-defensive")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_ecm"), "key_ecm"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_dump_cargo"), "key_dump_cargo"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_rotate_cargo"), "key_rotate_cargo"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_launch_escapepod"), "key_launch_escapepod"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-special-equip")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_cycle_next_mfd"), "key_cycle_next_mfd"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_cycle_previous_mfd"), "key_cycle_previous_mfd"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_switch_next_mfd"), "key_switch_next_mfd"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_switch_previous_mfd"), "key_switch_previous_mfd"));

	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_prime_next_equipment"), "key_prime_next_equipment"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_prime_previous_equipment"), "key_prime_previous_equipment"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_activate_equipment"), "key_activate_equipment"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_mode_equipment"), "key_mode_equipment"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_fastactivate_equipment_a"), "key_fastactivate_equipment_a"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_fastactivate_equipment_b"), "key_fastactivate_equipment_b"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-chart-screen")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_advanced_nav_array_next"), "key_advanced_nav_array_next"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_advanced_nav_array_previous"), "key_advanced_nav_array_previous"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_home"), "key_map_home"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_end"), "key_map_end"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_info"), "key_map_info"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_zoom_in"), "key_map_zoom_in"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_zoom_out"), "key_map_zoom_out"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_next_system"), "key_map_next_system"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_map_previous_system"), "key_map_previous_system"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_chart_highlight"), "key_chart_highlight"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-planet-info-screen")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_system_home"), "key_system_home"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_system_end"), "key_system_end"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_system_next_system"), "key_system_next_system"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_system_previous_system"), "key_system_previous_system"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-market-screen")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_market_filter_cycle"), "key_market_filter_cycle"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_market_sorter_cycle"), "key_market_sorter_cycle"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_market_buy_one"), "key_market_buy_one"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_market_sell_one"), "key_market_sell_one"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_market_buy_max"), "key_market_buy_max"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_market_sell_max"), "key_market_sell_max"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-misc")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_snapshot"), "key_snapshot"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_pausebutton"), "key_pausebutton"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_show_fps"), "key_show_fps"));
	//[funcList addObject:[self makeKeyGuiDict:OO_DESC("oolite-keydesc-key_bloom_toggle") keyDef:@"key_bloom_toggle"]];
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_mouse_control_roll"), "key_mouse_control_roll"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_mouse_control_yaw"), "key_mouse_control_yaw"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_hud_toggle"), "key_hud_toggle"));
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_inc_field_of_view"), "key_inc_field_of_view"));	// the member (bead oo-w9pi2)
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_dec_field_of_view"), "key_dec_field_of_view"));
#endif
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_comms_log"), "key_comms_log"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-custom-view")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view"), "key_custom_view"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_zoom_in"), "key_custom_view_zoom_in"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_zoom_out"), "key_custom_view_zoom_out"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_roll_left"), "key_custom_view_roll_left"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_roll_right"), "key_custom_view_roll_right"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_pan_left"), "key_custom_view_pan_left"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_pan_right"), "key_custom_view_pan_right"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_pan_up"), "key_custom_view_pan_up"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_pan_down"), "key_custom_view_pan_down"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_rotate_left"), "key_custom_view_rotate_left"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_rotate_right"), "key_custom_view_rotate_right"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_rotate_up"), "key_custom_view_rotate_up"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_custom_view_rotate_down"), "key_custom_view_rotate_down"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-oxz-manager")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_oxzmanager_setfilter"), "key_oxzmanager_setfilter"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_oxzmanager_showinfo"), "key_oxzmanager_showinfo"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_oxzmanager_extract"), "key_oxzmanager_extract"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-gui")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_arrow_left"), "key_gui_arrow_left"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_arrow_right"), "key_gui_arrow_right"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_arrow_up"), "key_gui_arrow_up"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_arrow_down"), "key_gui_arrow_down"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_page_down"), "key_gui_page_down"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_page_up"), "key_gui_page_up"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_gui_select"), "key_gui_select"));

	funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-debug")));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_dump_target_state"), "key_dump_target_state"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_dump_entity_list"), "key_dump_entity_list"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_debug_full"), "key_debug_full"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_debug_collision"), "key_debug_collision"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_debug_console_connect"), "key_debug_console_connect"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_debug_bounding_boxes"), "key_debug_bounding_boxes"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_debug_shaders"), "key_debug_shaders"));
	funcList.push_back(makeKeyGuiDict(OO_DESC("oolite-keydesc-key_debug_off"), "key_debug_off"));

	if (customEquipActivation.size() > 0) 
	{
		funcList.push_back(makeKeyGuiDictHeader(OO_DESC("oolite-keydesc-header-oxp-equip")));
		int i;
		for (i = 0; static_cast<std::size_t>(i) < customEquipActivation.size(); i++)
		{
			const oo::PList equip = customEquipActivation[i];
			const std::string equipName = DescriptionOfString(OptionalStringForKey(equip, std::string(CUSTOMEQUIP_EQUIPNAME)));	// %@: "(null)" for nil
			const std::string equipKey = DescriptionOfString(OptionalStringForKey(equip, std::string(CUSTOMEQUIP_EQUIPKEY)));
			funcList.push_back(makeKeyGuiDict(oo::str::format("Activate '%s'", equipName.c_str()), oo::str::format("activate_%s", equipKey.c_str())));
			funcList.push_back(makeKeyGuiDict(oo::str::format("Mode '%s'", equipName.c_str()), oo::str::format("mode_%s", equipKey.c_str())));
		}
	}
	return funcList;
}


oo::PList PlayerEntity::makeKeyGuiDict(const std::string &what, const std::string &key_def)
{
	// more than 50 UTF-16 units: the first 48 and "...", as -substringToIndex:48 cut it
	const std::u16string units = oo::utf8ToUtf16(what);
	const std::string description = (units.size() > 50) ? oo::utf16ToUtf8(units.substr(0, 48)) + "..." : what;
	oo::PList::Dict guiDict;
	guiDict[std::string(KEY_KC_GUIDESC)] = oo::PList(description);
	guiDict[std::string(KEY_KC_DEFINITION)] = oo::PList(key_def);
	return oo::PList(std::move(guiDict));
}


oo::PList PlayerEntity::makeKeyGuiDictHeader(const std::string &header)
{
	oo::PList::Dict guiDict;
	guiDict[std::string(KEY_KC_HEADER)] = oo::PList(header);
	guiDict[std::string(KEY_KC_GUIDESC)] = oo::PList("");
	guiDict[std::string(KEY_KC_DEFINITION)] = oo::PList("");
	return oo::PList(std::move(guiDict));
}


void PlayerEntity::setGuiToKeyboardLayoutScreen(unsigned skip)
{
	setGuiToKeyboardLayoutScreen(skip, NO);
}


void PlayerEntity::setGuiToKeyboardLayoutScreen(unsigned skip, bool /*resetCurrentRow*/)
{
	::GuiDisplayGen *gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	OOGUIScreenID oldScreen = gui_screen;
	OOGUITabStop tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	gui->setTabStops(tabStop);

	gui_screen = GUI_SCREEN_KEYBOARD_LAYOUT;
	BOOL guiChanged = (oldScreen != gui_screen);

	if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setMouseInteractionModeForUIWithMouseInteraction(YES);

	gui->clear();
	gui->setTitle(std::string("Select Keyboard Layout"));

	displayKeyboardLayoutList(gui, skip);

	gui->setArray(Columns({ OO_DESC("oolite-keyconfig-keyboard-info") }), GUI_ROW_KC_INSTRUCT);

	gui->setSelectedRow(kbd_row);

	gui->setForegroundTextureKey(std::string(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
	gui->setBackgroundTextureKey(std::string("keyboardsettings"));

	if (gameView != nullptr)  gameView->clearMouse();
	if (gameView != nullptr)  gameView->clearKeys();
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);

	if (guiChanged) noteGUIDidChangeFrom(oldScreen, gui_screen);
}


void PlayerEntity::handleKeyboardLayoutEntryKeys(::GuiDisplayGen *gui, ::MyOpenGLView *gameView)
{
	handleGUIUpDownArrowKeys();
	BOOL selectKeyPress = (checkKeyPress(n_key_gui_select) || (gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false));
	if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))  { if (gameView != nullptr)  gameView->clearMouse(); }

	const std::string key = gui->keyForRow(gui->getSelectedRow()).value_or("");	// a nil key has no prefix
	if (selectKeyPress)
	{
		if (oo::str::hasPrefix(key, "More:"))
		{
			int from_function = SecondFieldIntValue(key);
			if (from_function < 0)  from_function = 0;

			current_row = GUI_ROW_KC_FUNCSTART;
			if (from_function == 0) current_row = GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1;
			setGuiToKeyboardLayoutScreen(from_function);
			if ((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) { if (gameView != nullptr)  gameView->clearMouse(); }
			return;
		}

		// update the keyboard code
		NSUInteger idx =SecondFieldIntValue(key);
		const std::optional<std::string> kbd = idx < kbdLayouts.size() ? OptionalStringForKey(kbdLayouts[idx], "key") : std::nullopt;
		oo::Defaults &defaults = oo::Defaults::standard();
		defaults.setObject("keyboard-code", kbd ? oo::PList(*kbd) : oo::PList());
		initKeyConfigSettings();
		initCheckingDictionary();

		if (gameView != nullptr)  gameView->clearKeys();	// try to stop key bounces
		setGuiToKeyMapperScreen(0, YES);
	}
	if ((gameView != nullptr ? gameView->isDown(27) : false)) // escape - return without change
	{
		if (gameView != nullptr)  gameView->clearKeys();	// try to stop key bounces
		setGuiToKeyMapperScreen(0, YES);
	}	
}


std::optional<std::string> PlayerEntity::keyboardDescription(const std::string &kbd)
{
	const oo::PList kmap = ResourceManager::dictionaryFromFilesNamed(KeyMappingsFileName(), std::optional<std::string>("Config"), MERGE_BASIC, NO);
	const oo::PList *sect = kmap.find(kbd);
	return sect != nullptr ? OptionalStringForKey(*sect, "description") : std::nullopt;
}


std::vector<oo::PList> PlayerEntity::keyboardLayoutList()
{
	const oo::PList kmap = ResourceManager::dictionaryFromFilesNamed(KeyMappingsFileName(), std::optional<std::string>("Config"), MERGE_BASIC, NO);
	std::vector<oo::PList> kbdList;
	oo::PList def;

	if (const oo::PList::Dict *layouts = kmap.getIf<oo::PList::Dict>())
	{
		for (const auto &layoutEntry : *layouts)
		{
			const std::string &key = layoutEntry.first;
			// +initWithObjectsAndKeys: stopped at a nil description
			oo::PList::Dict layout;
			layout["key"] = oo::PList(key);
			const std::optional<std::string> description = keyboardDescription(key);
			if (description)  layout["description"] = oo::PList(*description);
			if (key != "default")
			{
				kbdList.push_back(oo::PList(std::move(layout)));
			}
			else
			{
				// key the "default" item separate, so we can add it at the top of the list, rather than getting it sorted
				def = oo::PList(std::move(layout));
			}
		}
	}

	// Sorted by "description", ascending, with -compare:, stably: what the sort descriptor did
	// (bead oo-3rb.20). A missing description never sorted ascending (-compare: to or from nil).
	std::stable_sort(kbdList.begin(), kbdList.end(), [](const oo::PList &a, const oo::PList &b) {
		const std::optional<std::string> descriptionA = OptionalStringForKey(a, "description");
		const std::optional<std::string> descriptionB = OptionalStringForKey(b, "description");
		return descriptionA && descriptionB && oo::str::compare(*descriptionA, *descriptionB) < 0;
	});
	std::vector<oo::PList> sorted;
	sorted.reserve(kbdList.size() + 1);
	sorted.push_back(def);
	sorted.insert(sorted.end(), kbdList.begin(), kbdList.end());

	return sorted;
}


void PlayerEntity::displayKeyboardLayoutList(::GuiDisplayGen *gui, NSUInteger skip)
{
	gui->setColor(OOColor::greenColor().get(), GUI_ROW_KC_HEADING);
	gui->setArray({ "Keyboard layout" }, GUI_ROW_KC_HEADING);

	if (kbdLayouts.empty()) kbdLayouts = keyboardLayoutList();	// never empty once built ("default" first)

	NSUInteger i, n_functions = kbdLayouts.size();
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
			gui->setColor(OOColor::greenColor().get(), GUI_ROW_KC_FUNCSTART);
			gui->setArray(Columns({ OO_DESC("gui-back"), " <-- " }), GUI_ROW_KC_FUNCSTART);
			gui->setKey(oo::str::format("More:%zd", previous), GUI_ROW_KC_FUNCSTART);
		}
		
		const std::string kbd = KeyboardCode();

		for(i = 0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			const oo::PList &entry = kbdLayouts[i + skip];
			const std::optional<std::string> desc = OptionalStringForKey(entry, "description");
			std::string selected;
			if (OptionalStringForKey(entry, "key") == kbd) selected = "Current";
			gui->setArray(Columns({ desc, selected }), i + start_row);
			gui->setKey(oo::str::format("Index:%zu", i + skip), i + start_row);
		}
		if (i < n_functions - skip)
		{
			gui->setColor(OOColor::greenColor().get(), start_row + i);
			gui->setArray(Columns({ OO_DESC("gui-more"), " --> " }), start_row + i);
			gui->setKey(oo::str::format("More:%zu", n_rows + skip), start_row + i);
			i++;
		}
		
		gui->setSelectableRange(NSMakeRange(GUI_ROW_KC_FUNCSTART, i + start_row - GUI_ROW_KC_FUNCSTART));
	}
}


// return an array of all functions currently in conflict
std::vector<std::string> PlayerEntity::validateAllKeys()
{
	std::vector<std::string> failed;
	NSUInteger i;

	for (i = 0; i < keyFunctions.size(); i++)
	{
		const std::optional<std::string> definition = OptionalStringForKey(keyFunctions[i], std::string(KEY_KC_DEFINITION));
		const std::optional<std::string> validate = validateKey(definition.value_or(""), KeyConfigEntry(keyconfig2_settings, definition));
		if (validate)
		{
			failed.push_back(*validate);
		}
	}
	return failed;
}


// validate a single key against any other key that might apply to it
std::optional<std::string> PlayerEntity::validateKey(const std::string &key, const oo::PList &check_keys)
{
	std::optional<std::string> result;	// nullopt: no conflict (was nil)
	
	// need to group keys into validation groups
	const std::vector<std::string> gui_keys = {"key_gui_arrow_left", "key_gui_arrow_right", "key_gui_arrow_up", "key_gui_arrow_down", "key_gui_page_up", 
		"key_gui_page_down", "key_gui_select" };

	if (Contains(gui_keys, key)) 
	{
		result = searchArrayForMatch(gui_keys, key, check_keys);
		if (result) return result;
	}

	const std::vector<std::string> debug_keys = {
		"key_dump_target_state", "key_dump_entity_list", "key_debug_full", "key_debug_collision", "key_debug_console_connect", "key_debug_bounding_boxes", 
		"key_debug_shaders", "key_debug_off" };

	if (Contains(debug_keys, key)) 
	{
		result = searchArrayForMatch(debug_keys, key, check_keys);
		if (result) return result;
	}

	const std::vector<std::string> customview_keys = {
		"key_custom_view", "key_custom_view_zoom_out", "key_custom_view_zoom_in", "key_custom_view_roll_left", "key_custom_view_pan_left", 
		"key_custom_view_roll_right", "key_custom_view_pan_right", "key_custom_view_rotate_up", "key_custom_view_pan_up", "key_custom_view_rotate_down", 
		"key_custom_view_pan_down", "key_custom_view_rotate_left", "key_custom_view_rotate_right" };

	if (Contains(customview_keys, key)) 
	{
		result = searchArrayForMatch(customview_keys, key, check_keys);
		if (result) return result;
	}

	std::vector<std::string> inflight_keys = {
		"key_roll_left", "key_roll_right", "key_pitch_forward", "key_pitch_back", "key_yaw_left", "key_yaw_right", "key_view_forward", "key_view_aft", 
		"key_view_port", "key_view_starboard", "key_increase_speed", "key_decrease_speed", "key_inject_fuel", "key_fire_lasers", "key_weapons_online_toggle", 
		"key_launch_missile", "key_next_missile", "key_ecm", "key_prime_next_equipment", "key_prime_previous_equipment", "key_activate_equipment", 
		"key_mode_equipment", "key_fastactivate_equipment_a", "key_fastactivate_equipment_b", "key_target_incoming_missile", "key_target_missile", 
		"key_untarget_missile", "key_ident_system", "key_scanner_zoom", "key_scanner_unzoom", "key_launch_escapepod", "key_galactic_hyperspace", 
		"key_hyperspace", "key_jumpdrive", "key_dump_cargo", "key_rotate_cargo", "key_autopilot", "key_autodock", "key_docking_clearance_request", 
		"key_snapshot", "key_cycle_next_mfd", "key_cycle_previous_mfd", "key_switch_next_mfd", "key_switch_previous_mfd", 
		"key_next_target", "key_previous_target", "key_comms_log", "key_prev_compass_mode", "key_next_compass_mode", "key_custom_view", 
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		"key_inc_field_of_view", "key_dec_field_of_view", 
#endif
		"key_pausebutton", "key_dump_target_state" };
	
	if (entryIsCustomEquip(key)) {
		NSUInteger i;
		for (i = 0; i < customEquipActivation.size(); i++)
		{
			const std::optional<std::string> equipKey = OptionalStringForKey(customEquipActivation[i], std::string(CUSTOMEQUIP_EQUIPKEY));
			inflight_keys.push_back(oo::str::format("activate_%s", DescriptionOfString(equipKey).c_str()));
			inflight_keys.push_back(oo::str::format("mode_%s", DescriptionOfString(equipKey).c_str()));
		}
	}

	if (Contains(inflight_keys, key)) 
	{
		result = searchArrayForMatch(inflight_keys, key, check_keys);
		if (result) return result;
	}

	const std::vector<std::string> docking_keys = {
		"key_docking_music", "key_autopilot", "key_pausebutton" };

	if (Contains(docking_keys, key)) 
	{
		result = searchArrayForMatch(docking_keys, key, check_keys);
		if (result) return result;
	}

	std::vector<std::string> docked_keys = {"key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status",
		"key_gui_chart_screens", "key_gui_system_data", "key_gui_market" };
	docked_keys.insert(docked_keys.end(), gui_keys.begin(), gui_keys.end());

	if (Contains(docked_keys, key))
	{
		result = searchArrayForMatch(docked_keys, key, check_keys);
		if (result) return result;
	}

	std::vector<std::string> paused_keys = {"key_pausebutton", "key_gui_screen_options", "key_hud_toggle", "key_show_fps", "key_mouse_control_roll",
		"key_mouse_control_yaw" };
	paused_keys.insert(paused_keys.end(), debug_keys.begin(), debug_keys.end());
	paused_keys.insert(paused_keys.end(), customview_keys.begin(), customview_keys.end());

	if (Contains(paused_keys, key))
	{
		result = searchArrayForMatch(paused_keys, key, check_keys);
		if (result) return result;
	}

	const std::vector<std::string> chart_keys = {
		"key_advanced_nav_array_next", "key_advanced_nav_array_previous", "key_map_home", "key_map_end", "key_map_info", 
		"key_map_zoom_in", "key_map_zoom_out", "key_map_next_system", "key_map_previous_system", "key_chart_highlight", 
		"key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status", 
		"key_gui_chart_screens", "key_gui_system_data", "key_gui_market" };

	if (Contains(chart_keys, key))
	{
		result = searchArrayForMatch(chart_keys, key, check_keys);
		if (result) return result;
	}

	const std::vector<std::string> sysinfo_keys = {
		"key_system_home", "key_system_end", "key_system_next_system", "key_system_previous_system", 
		"key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status", 
		"key_gui_chart_screens", "key_gui_system_data", "key_gui_market" };

	if (Contains(sysinfo_keys, key))
	{
		result = searchArrayForMatch(sysinfo_keys, key, check_keys);
		if (result) return result;
	}

	const std::vector<std::string> market_keys = {
		"key_market_filter_cycle", "key_market_sorter_cycle", "key_market_buy_one", "key_market_sell_one", "key_market_buy_max", 
		"key_market_sell_max", "key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status", 
		"key_gui_chart_screens", "key_gui_system_data", "key_gui_market", "key_gui_arrow_up", "key_gui_arrow_down", "key_gui_page_up", 
		"key_gui_page_down", "key_gui_select" };
		
	if (Contains(market_keys, key))
	{
		result = searchArrayForMatch(market_keys, key, check_keys);
		if (result) return result;
	}

	// if we get here, we should be good
	return std::nullopt;
}


// performs a search of all keys in the search_list, and for any key that isn't the one we've passed, check the 
// keys against the values we're passing in. if there's a hit, return the key found
std::optional<std::string> PlayerEntity::searchArrayForMatch(const std::vector<std::string> &search_list, const std::string &key, const oo::PList &check_keys)
{
	NSUInteger j, k;
	for (const std::string &search : search_list)
	{
		// only check other key settings, not the one we've been passed
		if (search != key)
		{
			// get the array from keyconfig2_settings
			// we need to compare all entries to each other to look for any match, as any match would indicate a conflict
			oo::PList current;
			if (!entryIsCustomEquip(search))
			{
				current = KeyConfigEntry(keyconfig2_settings, search);
			}
			else
			{
				NSUInteger idx = getCustomEquipIndex(search);
				const std::optional<std::string> keytype = getCustomEquipKeyDefType(search);
				const oo::PList *field = keytype.has_value() ? CustomEquipEntry(customEquipActivation, idx).find(*keytype) : nullptr;
				current = (field != nullptr) ? *field : oo::PList();
			}
			for (j = 0; j < current.count(); j++)
			{
				for (k = 0; k < check_keys.count(); k++)
				{
					const oo::PList *currentEntry = current.at(j);
					const oo::PList *checkEntry = check_keys.at(k);
					if (compareKeyEntries(currentEntry != nullptr ? *currentEntry : oo::PList(), checkEntry != nullptr ? *checkEntry : oo::PList())) return search;
				}
			}
		}
	}
	return std::nullopt;
}


// compares the currently stored key_list against the base default from keyconfig2.plist
bool PlayerEntity::entryIsEqualToDefault(const std::string &key)
{
	const oo::PList *defValue = kdic_check.find(key);
	const oo::PList def = defValue != nullptr ? *defValue : oo::PList();
	const oo::PList &keys = key_list;
	NSUInteger i;

	if (def.count() != keys.count()) return NO;
	for (i = 0; i < keys.count(); i++)
	{
		const oo::PList *orig = def.at(i);
		const oo::PList *entrd = keys.at(i);
		if (!compareKeyEntries(orig != nullptr ? *orig : oo::PList(), entrd != nullptr ? *entrd : oo::PList())) return NO;
	}
	return YES;
}


// compares two key dictionaries to see if they have the same settings
bool PlayerEntity::compareKeyEntries(const oo::PList &first, const oo::PList &second)
{
	// "key" as -integerValue read it (a string or a number); the modifiers as -boolValue
	if (first.get<long long>("key") == second.get<long long>("key"))
	{
		if (first.get<bool>("shift") == second.get<bool>("shift") &&
			first.get<bool>("mod1") == second.get<bool>("mod1") &&
			first.get<bool>("mod2") == second.get<bool>("mod2"))
			return YES;
	}
	return NO;
}


// saves the currently store key_list to the defaults file and updates the global definition
void PlayerEntity::saveKeySetting(const std::string &key)
{
	// check for a blank entry
	oo::PList::Array *keys = key_list.getIf<oo::PList::Array>();
	if (key_list.count() > 1 && key_list.at(1)->get<long long>("key") == 0)
	{
		keys->erase(keys->begin() + 1);
	}
	// make sure the primary and alternate keys are different
	if (key_list.count() > 1) {
		if (compareKeyEntries(*key_list.at(0), *key_list.at(1)))
		{
			keys->erase(keys->begin() + 1);
		}
	}
	// see if we've set the key settings to blank - in which case, delete the override
	if ((key_list.at(0) != nullptr ? key_list.at(0)->get<long long>("key") : 0) == 0)	// -integerValue
	{
		if (key_list.count() == 1 || (key_list.count() > 1 && IsEmptyString(key_list.at(1)->find("key"))))
		{
			deleteKeySetting(key);
			// reload settings
			initKeyConfigSettings();
			reloadPage();
			return;
		}
	}

	oo::Defaults &defaults = oo::Defaults::standard();

	if (!entryIsCustomEquip(key))
	{
		// if we've got the same settings as the default, revert to the default
		if (entryIsEqualToDefault(key))
		{
			deleteKeySetting(key);
			// reload settings
			initKeyConfigSettings();
			reloadPage();
			return;
		}
		oo::PList::Dict keyconf = KeyConfigOverrides();
		keyconf[key] = key_list;
		defaults.setObject(std::string(KEYCONFIG_OVERRIDES), oo::PList(std::move(keyconf)));
	}
	else
	{
		NSUInteger idx = getCustomEquipIndex(key);
		if (oo::PList::Dict *fields = CustomEquipFields(customEquipActivation, idx))  (*fields)[getCustomEquipKeyDefType(key).value_or("")] = key_list;	// in place
		defaults.setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
	// reload settings
	initKeyConfigSettings();
	reloadPage();
}

// unsets the key setting in the overrides, and updates the global definition
void PlayerEntity::unsetKeySetting(const std::string &key)
{
	oo::Defaults &defaults = oo::Defaults::standard();
	if (!entryIsCustomEquip(key))
	{
		oo::PList::Dict keyconf = KeyConfigOverrides();
		keyconf[key] = oo::PList(oo::PList::Array());	// an empty override
		defaults.setObject(std::string(KEYCONFIG_OVERRIDES), oo::PList(std::move(keyconf)));
	}
	else
	{
		NSUInteger idx = getCustomEquipIndex(key);
		if (oo::PList::Dict *fields = CustomEquipFields(customEquipActivation, idx))  fields->erase(getCustomEquipKeyDefType(key).value_or(""));	// in place
		defaults.setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
	// reload settings
	initKeyConfigSettings();
}


// removes the key setting from the overrides, and updates the global definition
void PlayerEntity::deleteKeySetting(const std::string &key)
{
	oo::Defaults &defaults = oo::Defaults::standard();
	if (!entryIsCustomEquip(key))
	{
		oo::PList::Dict keyconf = KeyConfigOverrides();
		keyconf.erase(key);
		defaults.setObject(std::string(KEYCONFIG_OVERRIDES), oo::PList(std::move(keyconf)));
	}
	else
	{
		// the customEquipActivation entry is edited in place, as before
		const std::optional<std::string> keyDefType = getCustomEquipKeyDefType(key);
		oo::PList::Dict *fields = CustomEquipFields(customEquipActivation, getCustomEquipIndex(key));
		if (fields != nullptr && keyDefType.has_value())  fields->erase(*keyDefType);
		defaults.setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
	// reload settings
	initKeyConfigSettings();
}


// removes all key settings from the overrides, and updates the global definition
void PlayerEntity::deleteAllKeySettings()
{
	oo::Defaults &defaults = oo::Defaults::standard();
	defaults.removeObject(std::string(KEYCONFIG_OVERRIDES));
	if (customEquipActivation.size() > 0)
	{
		NSUInteger i;
		for (i = 0; i < customEquipActivation.size(); i++)
		{
			const std::optional<std::string> eq = OptionalStringForKey(customEquipActivation[i], std::string(CUSTOMEQUIP_EQUIPKEY));
			::OOEquipmentType *item = (eq.has_value() ? OOEquipmentType::equipmentTypeWithIdentifier(*eq).get() : nil);
			oo::PList::Dict *fields = CustomEquipFields(customEquipActivation, i);	// edited in place
			if (fields == nullptr)  continue;
			if ((item != nullptr ? item->defaultActivateKey() : oo::PList()))
				fields->insert_or_assign(std::string(CUSTOMEQUIP_KEYACTIVATE), (item != nullptr ? item->defaultActivateKey() : oo::PList()));
			else
				fields->erase(std::string(CUSTOMEQUIP_KEYACTIVATE));

			if ((item != nullptr ? item->defaultModeKey() : oo::PList()))
				fields->insert_or_assign(std::string(CUSTOMEQUIP_KEYMODE), (item != nullptr ? item->defaultModeKey() : oo::PList()));
			else
				fields->erase(std::string(CUSTOMEQUIP_KEYMODE));
		}
		defaults.setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
	// reload settings
	initKeyConfigSettings();
}


// returns all key settings from the overrides
oo::PList PlayerEntity::loadKeySettings()
{
	return oo::Defaults::standard().object(std::string(KEYCONFIG_OVERRIDES));
}


// reloads the main page at the appropriate page
void PlayerEntity::reloadPage()
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
	
	setGuiToKeyMapperScreen(skip);
}
