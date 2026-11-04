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
#import "GameController.h"
#import "HeadUpDisplay.h"
#import "OOEquipmentType.h"
#import "OOFoundationBridge.h"
#import "OOPListView.h"
#import "OOJoystickManager.h"
#import "OOTexture.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityScriptMethods.h"
#import "ResourceManager.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/StdLib.hpp"
#include "oofnd/String.hpp"

static NSUInteger key_index;
static long current_row;
static long kbd_row = GUI_ROW_KC_FUNCSTART;
static BOOL has_error = NO;
static BOOL last_shift = NO;

namespace {

oo::PList selected_entry; // a copy of the chosen function entry; null: none (was nil)
oo::PList key_list; // an Array of key-definition Dicts being edited
oo::PList kdic_check; // keyconfig2.plist's definitions; null until -initCheckingDictionary
std::vector<std::string> nav_keys; // functions that can't be used with mod keys
std::vector<std::string> camera_keys; // functions that can't be used with ctrl

// -oo_stringForKey: where the old code could read nil (proposed ADR-0043): a string, or a number's
// -stringValue; nullopt when the key is absent or holds anything else.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

// What %@ printed for a string that may be nil.
std::string DescriptionOfString(const std::optional<std::string>& string)
{
    return string ? *string : std::string("(null)");
}

bool Contains(const std::vector<std::string>& list, const std::string& item)
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
int SecondFieldIntValue(const std::string& s)
{
    const std::vector<std::string> fields = oo::str::split(s, ":");
    return fields.size() > 1 ? oo::str::intValue(fields[1]) : 0;
}

// A GUI row built with +arrayWithObjects: stopped at the first nil column.
std::vector<std::string> Columns(std::initializer_list<std::optional<std::string>> columns)
{
    std::vector<std::string> result;
    for (const std::optional<std::string>& column : columns) {
        if (!column)
            break;
        result.push_back(*column);
    }
    return result;
}

// %@ of a string that may be nil, in a runtime format.
oo::str::FormatArg TextArg(const std::optional<std::string>& string)
{
    return string ? oo::str::FormatArg(*string) : oo::str::FormatArg::null();
}

// Inserts or replaces entry <index> of the key list, as -insertObject:atIndex: /
// -replaceObjectAtIndex:withObject: did (an index past the end appends; it used to raise).
void StoreKeyDefinition(NSUInteger index, oo::PList definition)
{
    oo::PList::Array* keys = key_list.getIf<oo::PList::Array>();
    if (keys == nullptr)
        return; // messaging a nil key_list
    if (index >= keys->size())
        keys->push_back(std::move(definition));
    else
        (*keys)[index] = std::move(definition);
}

// keyFunctions entry <index>; a null PList out of range (-objectAtIndex: raised).
const oo::PList& KeyFunctionAt(const std::vector<oo::PList>& functions, NSInteger index)
{
    static const oo::PList none;
    return (index >= 0 && static_cast<std::size_t>(index) < functions.size()) ? functions[index] : none;
}

// Element <index> of an array; a null PList for anything else.
const oo::PList& ElementAt(const oo::PList& array, std::size_t index)
{
    static const oo::PList none;
    const oo::PList* element = array.at(index);
    return element != nullptr ? *element : none;
}

// A copy of the KeyConfigOverrides default (+dictionaryWithDictionary: of nil was empty).
oo::PList::Dict KeyConfigOverrides(void)
{
    const oo::PList overrides = oo::Defaults::standard().object(oo::StdString(KEYCONFIG_OVERRIDES));
    const oo::PList::Dict* dict = overrides.getIf<oo::PList::Dict>();
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
#if OOLITE_MAC_COCOA_UI
    map = "keymappings_mac.plist";
#endif
    return map;
}

// -isEqualToString:@"" on a value that may be absent.
bool IsEmptyString(const oo::PList* value)
{
    const std::string* string = value != nullptr ? value->getIf<std::string>() : nullptr;
    return string != nullptr && string->empty();
}

// customEquipActivation entry <index>: a null PList past the end (-objectAtIndex: raised there).
const oo::PList& CustomEquipEntry(const std::vector<oo::PList>& entries, NSUInteger index)
{
    static const oo::PList none;
    return (index < entries.size()) ? entries[index] : none;
}

// The fields of customEquipActivation entry <index>, edited in place; nullptr past the end or when
// the entry is not a dictionary (its -setObject:forKey: / -removeObjectForKey: raised there).
oo::PList::Dict* CustomEquipFields(std::vector<oo::PList>& entries, NSUInteger index)
{
    return (index < entries.size()) ? entries[index].getIf<oo::PList::Dict>() : nullptr;
}

// keyconfig2_settings' entry for <key>: null when absent (-objectForKey:, nil for a nil key).
oo::PList KeyConfigEntry(const oo::PList::Dict& settings, const std::optional<std::string>& key)
{
    if (!key.has_value())
        return oo::PList();
    const auto it = settings.find(*key);
    return (it != settings.end()) ? it->second : oo::PList();
}

} // namespace

@interface PlayerEntity (KeyMapperInternal)

- (void)resetKeyFunctions;
- (void)updateKeyDefinition:(const std::string&)keystring index:(NSUInteger)index;
- (void)updateShiftKeyDefinition:(const std::string&)key index:(NSUInteger)index;
- (void)displayKeyFunctionList:(GuiDisplayGen*)gui skip:(NSUInteger)skip;
- (std::optional<std::string>)keyboardDescription:(const std::string&)kbd;
- (void)displayKeyboardLayoutList:(GuiDisplayGen*)gui skip:(NSUInteger)skip;
- (BOOL)entryIsIndexCustomEquip:(NSUInteger)idx;
- (BOOL)entryIsDictCustomEquip:(const oo::PList&)dict;
- (BOOL)entryIsCustomEquip:(const std::string&)entry;
- (oo::PList)getCustomEquipArray:(const std::string&)key_def; // null: none (was nil)
- (std::optional<std::string>)getCustomEquipKeyDefType:(const std::string&)key_def; // always engaged ("" for neither)
- (std::vector<oo::PList>)keyFunctionList;
- (std::vector<std::string>)validateAllKeys;
- (std::optional<std::string>)searchArrayForMatch:(const std::vector<std::string>&)search_list key:(const std::string&)key checkKeys:(const oo::PList&)check_keys;
- (NSUInteger)getCustomEquipIndex:(const std::string&)key_def;
- (BOOL)entryIsEqualToDefault:(const std::string&)key;
- (BOOL)compareKeyEntries:(const oo::PList&)first second:(const oo::PList&)second;
- (void)saveKeySetting:(const std::string&)key;
- (void)unsetKeySetting:(const std::string&)key;
- (void)deleteKeySetting:(const std::string&)key;
- (void)deleteAllKeySettings;
- (oo::PList)loadKeySettings;
- (void)reloadPage;

@end

@implementation PlayerEntity (KeyMapper)

// sets up a copy of the raw keyconfig.plist file so we can run checks against it to tell if a key is set to default
- (void)initCheckingDictionary
{
    const oo::PList kdicmaster = [ResourceManager cxx_dictionaryFromFilesNamed:"keyconfig2.plist" inFolder:std::optional<std::string>("Config") mergeMode:MERGE_BASIC cache:NO];
    const std::string kbd = KeyboardCode();
    const oo::PList* kdicValue = kdicmaster.get<oo::PList::Dict>(kbd);
    oo::PList::Dict kdic = (kdicValue != nullptr) ? *kdicValue->getIf<oo::PList::Dict>() : oo::PList::Dict();

    for (auto& [key, value] : kdic) {
        if (value.isArray()) {
            // -processKeyCode: returns a +1 array
            value = oo::PListFrom(oo::adoptObjC([self processKeyCode:oo::ObjectFromPList(value)]).get());
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

- (void)resetKeyFunctions
{
    keyFunctions.clear();
}

- (void)setGuiToKeyMapperScreen:(unsigned)skip
{
    [self setGuiToKeyMapperScreen:skip resetCurrentRow:NO];
}

- (void)setGuiToKeyMapperScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow
{
    const std::string kbd = KeyboardCode();

    GuiDisplayGen* gui = [UNIVERSE gui];
    MyOpenGLView* gameView = [UNIVERSE gameView];
    OOGUIScreenID oldScreen = gui_screen;
    OOGUITabStop tabStop[GUI_MAX_COLUMNS];
    tabStop[0] = 10;
    tabStop[1] = 290;
    tabStop[2] = 400;
    [gui setTabStops:tabStop];

    if (!kdic_check)
        [self initCheckingDictionary];

    gui_screen = GUI_SCREEN_KEYBOARD;
    BOOL guiChanged = (oldScreen != gui_screen);
    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    [gui clear];
    [gui setTitle:[NSString stringWithFormat:@"%@", DESC(@"oolite-keyconfig-header")]];

    // show keyboard layout
    [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-keyboard")), [self keyboardDescription:kbd] }) forRow:GUI_ROW_KC_SELECTKBD];
    [gui cxx_setKey:oo::str::format("kbd:%s", kbd.c_str()) forRow:GUI_ROW_KC_SELECTKBD];
    [gui setColor:[OOColor yellowColor] forRow:GUI_ROW_KC_SELECTKBD];

    [self displayKeyFunctionList:gui skip:skip];

    has_error = NO;
    if (![self validateAllKeys].empty()) {
        has_error = YES;
        [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-validation-error")) forRow:GUI_ROW_KC_ERROR align:GUI_ALIGN_CENTER];
        [gui setColor:[OOColor redColor] forRow:GUI_ROW_KC_ERROR];
    }
    [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-initial-info-1")) }) forRow:GUI_ROW_KC_INSTRUCT];
    [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-initial-info-2")) forRow:GUI_ROW_KC_INSTRUCT + 1 align:GUI_ALIGN_CENTER];
    if (has_error) {
        [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-initial-error")) forRow:GUI_ROW_KC_INSTRUCT + 2 align:GUI_ALIGN_CENTER];
    } else {
        [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-initial-info-3")) forRow:GUI_ROW_KC_INSTRUCT + 2 align:GUI_ALIGN_CENTER];
    }

    if (resetCurrentRow) {
        int offset = 0;
        if (KeyFunctionAt(keyFunctions, skip).find(oo::StdString(KEY_KC_HEADER)) != nullptr)
            offset = 1;
        [gui setSelectedRow:GUI_ROW_KC_FUNCSTART + offset];
    } else {
        [gui setSelectedRow:current_row];
    }

    [gui cxx_setForegroundTextureKey:std::string([self status] == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")];
    [gui cxx_setBackgroundTextureKey:std::string("keyboardsettings")];

    [gameView clearMouse];
    [gameView clearKeys];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (guiChanged)
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

- (void)keyMapperInputHandler:(GuiDisplayGen*)gui view:(MyOpenGLView*)gameView
{
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
    [self handleGUIUpDownArrowKeys];
    BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT] || [gameView isDown:gvMouseDoubleClick]);
    if ([gameView isDown:gvMouseDoubleClick])
        [gameView clearMouse];

    const std::string key = [gui cxx_keyForRow:[gui selectedRow]].value_or(""); // a nil key has no prefix
    if (oo::str::hasPrefix(key, "Index:"))
        selFunctionIdx = SecondFieldIntValue(key);
    else
        selFunctionIdx = -1;

    if (selectKeyPress) {
        if (oo::str::hasPrefix(key, "More:")) {
            int from_function = SecondFieldIntValue(key);
            if (from_function < 0)
                from_function = 0;

            current_row = GUI_ROW_KC_FUNCSTART;
            if (from_function == 0)
                current_row = GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1;
            [self setGuiToKeyMapperScreen:from_function];
            if ([gameView isDown:gvMouseDoubleClick])
                [gameView clearMouse];
            return;
        }
        if (oo::str::hasPrefix(key, "kbd:")) {
            [self setGuiToKeyboardLayoutScreen:0];
            if ([gameView isDown:gvMouseDoubleClick])
                [gameView clearMouse];
            return;
        }
        current_row = [gui selectedRow];
        selected_entry = KeyFunctionAt(keyFunctions, selFunctionIdx);
        oo::PList definitions;
        if (![self entryIsDictCustomEquip:selected_entry]) {
            definitions = KeyConfigEntry(keyconfig2_settings, OptionalStringForKey(selected_entry, oo::StdString(KEY_KC_DEFINITION)));
        } else {
            definitions = [self getCustomEquipArray:selected_entry.get<std::string>(oo::StdString(KEY_KC_DEFINITION))];
        }
        key_list = definitions.isArray() ? definitions : oo::PList(oo::PList::Array()); // -initWithArray:nil was empty
        [gameView clearKeys]; // try to stop key bounces
        [self setGuiToKeyConfigScreen:YES];
    }

    if ([gameView isDown:'u']) {
        // pressed 'u' on an "more" line
        if (oo::str::hasPrefix(key, "More:"))
            return;

        current_row = [gui selectedRow];
        [self unsetKeySetting:OptionalStringForKey(KeyFunctionAt(keyFunctions, selFunctionIdx), oo::StdString(KEY_KC_DEFINITION)).value_or("")];
        [self reloadPage];
    }

    if ([gameView isDown:'r']) {
        // reset single entry or all
        if (![gameView isCtrlDown]) {
            // pressed 'r' on an "more" line
            if (oo::str::hasPrefix(key, "More:"))
                return;

            current_row = [gui selectedRow];

            const std::optional<std::string> delkey = OptionalStringForKey(KeyFunctionAt(keyFunctions, selFunctionIdx), oo::StdString(KEY_KC_DEFINITION));
            [self deleteKeySetting:delkey.value_or("")];
            // special case - when default activate/mode key set in custom equipment
            if ([self entryIsCustomEquip:delkey.value_or("")]) {
                int idx = [self getCustomEquipIndex:delkey.value_or("")];
                std::optional<std::string> eq;
                std::optional<std::string> lookupKey;
                bool update = false;

                if (oo::str::hasPrefix(delkey.value_or(""), "activate_")) {
                    eq = oo::str::replaceOccurrences(*delkey, "activate_", "");
                    lookupKey = oo::StdString(CUSTOMEQUIP_KEYACTIVATE);
                }
                if (oo::str::hasPrefix(delkey.value_or(""), "mode_")) {
                    eq = oo::str::replaceOccurrences(*delkey, "mode_", "");
                    lookupKey = oo::StdString(CUSTOMEQUIP_KEYMODE);
                }

                OOEquipmentType* item = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(eq)];

                // the customEquipActivation entry is edited in place, as before
                oo::PList::Dict* fields = CustomEquipFields(customEquipActivation, idx);
                if ([item defaultActivateKey] && lookupKey == oo::StdString(CUSTOMEQUIP_KEYACTIVATE) && fields != nullptr) {
                    fields->insert_or_assign(*lookupKey, oo::PListFrom([item defaultActivateKey]));
                    update = true;
                }
                if ([item defaultModeKey] && lookupKey == oo::StdString(CUSTOMEQUIP_KEYMODE) && fields != nullptr) {
                    fields->insert_or_assign(*lookupKey, oo::PListFrom([item defaultModeKey]));
                    update = true;
                }

                if (update) {
                    oo::Defaults& defaults = oo::Defaults::standard();
                    defaults.setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
                }
            }

            [self reloadPage];
        } else {
            [self setGuiToConfirmClearScreen];
        }
    }
    if ([gameView isDown:' '] && !has_error)
        [self setGuiToGameOptionsScreen];
}

- (BOOL)entryIsIndexCustomEquip:(NSUInteger)idx
{
    return [self entryIsCustomEquip:KeyFunctionAt(keyFunctions, idx).get<std::string>(oo::StdString(KEY_KC_DEFINITION))];
}

- (BOOL)entryIsDictCustomEquip:(const oo::PList&)dict
{
    return [self entryIsCustomEquip:dict.get<std::string>(oo::StdString(KEY_KC_DEFINITION))];
}

- (BOOL)entryIsCustomEquip:(const std::string&)entry
{
    BOOL result = NO;
    if (oo::str::hasPrefix(entry, "activate_") || oo::str::hasPrefix(entry, "mode_"))
        result = YES;
    return result;
}

- (oo::PList)getCustomEquipArray:(const std::string&)key_def
{
    std::optional<std::string> eq;
    NSUInteger i;
    std::string key;
    if (oo::str::hasPrefix(key_def, "activate_")) {
        eq = oo::str::replaceOccurrences(key_def, "activate_", "");
        key = oo::StdString(CUSTOMEQUIP_KEYACTIVATE);
    }
    if (oo::str::hasPrefix(key_def, "mode_")) {
        eq = oo::str::replaceOccurrences(key_def, "mode_", "");
        key = oo::StdString(CUSTOMEQUIP_KEYMODE);
    }
    if (!eq)
        return oo::PList();
    for (i = 0; i < customEquipActivation.size(); i++) {
        const oo::PList equip = customEquipActivation[i];
        if (OptionalStringForKey(equip, oo::StdString(CUSTOMEQUIP_EQUIPKEY)) == eq) {
            const oo::PList* array = equip.get<oo::PList::Array>(key); // -oo_arrayForKey:
            return array != nullptr ? *array : oo::PList();
        }
    }
    return oo::PList();
}

- (NSUInteger)getCustomEquipIndex:(const std::string&)key_def
{
    std::optional<std::string> eq;
    NSUInteger i;
    if (oo::str::hasPrefix(key_def, "activate_")) {
        eq = oo::str::replaceOccurrences(key_def, "activate_", "");
    }
    if (oo::str::hasPrefix(key_def, "mode_")) {
        eq = oo::str::replaceOccurrences(key_def, "mode_", "");
    }
    if (!eq)
        return -1;
    for (i = 0; i < customEquipActivation.size(); i++) {
        if (OptionalStringForKey(customEquipActivation[i], oo::StdString(CUSTOMEQUIP_EQUIPKEY)) == eq) {
            return i;
        }
    }
    return -1;
}

- (std::optional<std::string>)getCustomEquipKeyDefType:(const std::string&)key_def
{
    if (oo::str::hasPrefix(key_def, "activate_")) {
        return oo::StdString(CUSTOMEQUIP_KEYACTIVATE);
    }
    if (oo::str::hasPrefix(key_def, "mode_")) {
        return oo::StdString(CUSTOMEQUIP_KEYMODE);
    }
    return std::string();
}

- (void)setGuiToKeyConfigScreen
{
    [self setGuiToKeyConfigScreen:NO];
}

- (void)setGuiToKeyConfigScreen:(BOOL)resetSelectedRow
{
    NSUInteger i = 0;
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIScreenID oldScreen = gui_screen;
    OOGUITabStop tabStop[GUI_MAX_COLUMNS];
    tabStop[0] = 10;
    tabStop[1] = 290;
    [gui setTabStops:tabStop];

    gui_screen = GUI_SCREEN_KEYBOARD_CONFIG;
    BOOL guiChanged = (oldScreen != gui_screen);
    [gui clear];
    [gui setTitle:oo::NSStringFrom(oo::DescriptionOf(DESC(@"oolite-keyconfig-update-title")))]; // @"%@"

    [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-update-function")), OptionalStringForKey(selected_entry, oo::StdString(KEY_KC_GUIDESC)) })
               forRow:GUI_ROW_KC_UPDATE_FUNCNAME];
    [gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_UPDATE_FUNCNAME];

    std::optional<std::string> keystring;
    std::optional<std::string> keyshift;
    std::optional<std::string> keymod1;
    std::optional<std::string> keymod2;

    OOKeyCode k_int;

    // get each key for the first two item in the selected entry
    for (i = 0; i <= 1; i++) {
        keystring = oo::OptionalString(DESC(@"oolite-keycode-unset"));
        keyshift = oo::OptionalString(DESC(@"oolite-keyconfig-modkey-off"));
        keymod1 = oo::OptionalString(DESC(@"oolite-keyconfig-modkey-off"));
        keymod2 = oo::OptionalString(DESC(@"oolite-keyconfig-modkey-off"));

        if (key_list.count() > i) {
            const oo::PList& def = *key_list.at(i);
            k_int = (OOKeyCode)def.get<long long>("key"); // -integerValue
            if (k_int > 0) {
                keystring = oo::OptionalString([self keyCodeDescription:k_int]);
                if (def.get<bool>("shift") == YES)
                    keyshift = oo::OptionalString(DESC(@"oolite-keyconfig-modkey-on"));
                if (def.get<bool>("mod1") == YES)
                    keymod1 = oo::OptionalString(DESC(@"oolite-keyconfig-modkey-on"));
                if (def.get<bool>("mod2") == YES)
                    keymod2 = oo::OptionalString(DESC(@"oolite-keyconfig-modkey-on"));
            }
        }

        [self outputKeyDefinition:keystring.value_or("") shift:keyshift.value_or("") mod1:keymod1.value_or("") mod2:keymod2.value_or("") skiprows:(i * 5)];
    }

    const std::string definition = selected_entry.get<std::string>(oo::StdString(KEY_KC_DEFINITION));
    std::optional<std::string> helper = oo::OptionalString(DESC(@"oolite-keyconfig-update-helper"));
    if (Contains(nav_keys, definition))
        helper = oo::str::format("%s %s", DescriptionOfString(helper).c_str(), oo::DescriptionOf(DESC(@"oolite-keyconfig-update-navkeys")).c_str());
    if (Contains(camera_keys, definition))
        helper = oo::str::format("%s %s", DescriptionOfString(helper).c_str(), oo::DescriptionOf(DESC(@"oolite-keyconfig-update-camkeys")).c_str());
    [gui cxx_addLongText:helper startingAtRow:GUI_ROW_KC_UPDATE_INFO align:GUI_ALIGN_LEFT];

    [gui cxx_setText:"" forRow:GUI_ROW_KC_VALIDATION];

    [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-update-save")) forRow:GUI_ROW_KC_SAVE align:GUI_ALIGN_CENTER];
    [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_SAVE];

    [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-update-cancel")) forRow:GUI_ROW_KC_CANCEL align:GUI_ALIGN_CENTER];
    [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_CANCEL];

    [gui setSelectableRange:NSMakeRange(GUI_ROW_KC_KEY, (GUI_ROW_KC_CANCEL - GUI_ROW_KC_KEY) + 1)];

    const std::optional<std::string> validate = [self validateKey:definition checkKeys:key_list];
    if (validate) {
        for (i = 0; i < keyFunctions.size(); i++) {
            if (OptionalStringForKey(keyFunctions[i], oo::StdString(KEY_KC_DEFINITION)) == validate) {
                [gui cxx_setText:oo::str::formatRuntime(oo::StdString(DESC(@"oolite-keyconfig-update-validation-@")), { TextArg(OptionalStringForKey(keyFunctions[i], oo::StdString(KEY_KC_GUIDESC))) })
                          forRow:GUI_ROW_KC_VALIDATION
                           align:GUI_ALIGN_CENTER];
                [gui setColor:[OOColor orangeColor] forRow:GUI_ROW_KC_VALIDATION];
                break;
            }
        }
    }

    if (resetSelectedRow) {
        [gui setSelectedRow:GUI_ROW_KC_KEY];
    }

    [gui cxx_setForegroundTextureKey:std::string([self status] == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")];
    [gui cxx_setBackgroundTextureKey:std::string("keyboardsettings")];
    [[UNIVERSE gameView] clearMouse];
    [[UNIVERSE gameView] clearKeys];
    if (guiChanged)
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

- (void)outputKeyDefinition:(const std::string&)key shift:(const std::string&)shift mod1:(const std::string&)mod1 mod2:(const std::string&)mod2 skiprows:(NSUInteger)skiprows
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::string definition = selected_entry.get<std::string>(oo::StdString(KEY_KC_DEFINITION));

    [gui cxx_setArray:Columns({ oo::OptionalString(skiprows == 0 ? DESC(@"oolite-keyconfig-update-key") : DESC(@"oolite-keyconfig-update-alternate")), key })
               forRow:GUI_ROW_KC_KEY + skiprows];
    [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_KEY + skiprows];

    if (!Contains(nav_keys, definition)) {
        if (!(oo::OptionalString(DESC(@"oolite-keycode-unset")) == key)) {
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-update-shift")), shift })
                       forRow:GUI_ROW_KC_SHIFT + skiprows];
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_SHIFT + skiprows];

            // camera movement keys can't use ctrl
            if (!Contains(camera_keys, definition)) {
                [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-update-mod1")), mod1 })
                           forRow:GUI_ROW_KC_MOD1 + skiprows];
                [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_MOD1 + skiprows];
            } else {
                [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-update-mod1")), oo::OptionalString(DESC(@"not-applicable")) })
                           forRow:GUI_ROW_KC_MOD1 + skiprows];
            }

#if OOLITE_MAC_COCOA_UI
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-update-mod2-mac")), mod2 })
                       forRow:GUI_ROW_KC_MOD2 + skiprows];
#else
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-update-mod2-pc")), mod2 })
                       forRow:GUI_ROW_KC_MOD2 + skiprows];
#endif
            [gui cxx_setKey:oo::StdString(GUI_KEY_OK)
                     forRow:GUI_ROW_KC_MOD2 + skiprows];
        }
    }
}

- (void)handleKeyConfigKeys:(GuiDisplayGen*)gui view:(MyOpenGLView*)gameView
{
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
    [self handleGUIUpDownArrowKeys];
    BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT] || [gameView isDown:gvMouseDoubleClick]);
    if ([gameView isDown:gvMouseDoubleClick])
        [gameView clearMouse];

    if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_KEY || [gui selectedRow] == (GUI_ROW_KC_KEY + 5))) {
        key_index = ([gui selectedRow] == GUI_ROW_KC_KEY ? 0 : 1);
        [self setGuiToKeyConfigEntryScreen];
    }

    if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_SHIFT || [gui selectedRow] == (GUI_ROW_KC_SHIFT + 5))) {
        [self updateShiftKeyDefinition:"shift" index:([gui selectedRow] == GUI_ROW_KC_SHIFT ? 0 : 1)];
        [self setGuiToKeyConfigScreen];
    }
    if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_MOD1 || [gui selectedRow] == (GUI_ROW_KC_MOD1 + 5))) {
        [self updateShiftKeyDefinition:"mod1" index:([gui selectedRow] == GUI_ROW_KC_MOD1 ? 0 : 1)];
        [self setGuiToKeyConfigScreen];
    }
    if (selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_MOD2 || [gui selectedRow] == (GUI_ROW_KC_MOD2 + 5))) {
        [self updateShiftKeyDefinition:"mod2" index:([gui selectedRow] == GUI_ROW_KC_MOD2 ? 0 : 1)];
        [self setGuiToKeyConfigScreen];
    }

    if (selectKeyPress && [gui selectedRow] == GUI_ROW_KC_SAVE) {
        [self saveKeySetting:OptionalStringForKey(selected_entry, oo::StdString(KEY_KC_DEFINITION)).value_or("")];
        [self reloadPage];
    }

    if ((selectKeyPress && [gui selectedRow] == GUI_ROW_KC_CANCEL) || [gameView isDown:27]) {
        // esc or Cancel was pressed - get out of here
        [self reloadPage];
    }
}

- (void)setGuiToKeyConfigEntryScreen
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    MyOpenGLView* gameView = [UNIVERSE gameView];
    OOGUIScreenID oldScreen = gui_screen;
    gui_screen = GUI_SCREEN_KEYBOARD_ENTRY;
    BOOL guiChanged = (oldScreen != gui_screen);

    // make sure the index we're looking for exists
    oo::PList::Array* keys = key_list.getIf<oo::PList::Array>();
    if (keys != nullptr && keys->size() < (key_index + 1)) {
        // add the missing element to the array
        keys->push_back(oo::PList(oo::PList::Dict { { "key", oo::PList("") }, { "shift", oo::PList(false) }, { "mod1", oo::PList(false) }, { "mod2", oo::PList(false) } }));
    }
    const oo::PList* def = key_list.at(key_index);
    // if ([key isEqualToString:@"(not set)"]) key = @"";
    OOKeyCode k_int = (OOKeyCode)(def != nullptr ? def->get<long long>("key") : 0); // -integerValue
    [gameView resetTypedString];
    [gameView cxx_setTypedString:(k_int != 0 ? oo::StdString([self keyCodeDescriptionShort:k_int]) : std::string())];
    [gameView setStringInput:gvStringInputAll];

    [gui clear];
    [gui setTitle:oo::NSStringFrom(oo::DescriptionOf(DESC(@"oolite-keyconfig-update-entry-title")))]; // @"%@"

    NSUInteger end_row = 21;
    if ([[self hud] allowBigGui]) {
        end_row = 27;
    }

    [gui cxx_addLongText:oo::OptionalString(DESC(@"oolite-keyconfig-update-entry-info")) startingAtRow:GUI_ROW_KC_ENTRY_INFO align:GUI_ALIGN_LEFT];

    [gui setText:[NSString stringWithFormat:@"%@: %@", DESC(@"oolite-keyconfig-update-key"), [gameView typedString]] forRow:end_row align:GUI_ALIGN_LEFT];
    [gui setColor:[OOColor cyanColor] forRow:end_row];
    [gui setSelectableRange:NSMakeRange(0, 0)];

    [gui setShowTextCursor:YES];
    [gui setCurrentRow:end_row];

    [gui cxx_setForegroundTextureKey:std::string([self status] == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")];
    [gui cxx_setBackgroundTextureKey:std::string("keyboardsettings")];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    [gameView clearMouse];
    [gameView clearKeys];
    if (guiChanged)
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

- (void)handleKeyConfigEntryKeys:(GuiDisplayGen*)gui view:(MyOpenGLView*)gameView
{
    NSUInteger end_row = 21;
    if ([[self hud] allowBigGui]) {
        end_row = 27;
    }

    [self handleGUIUpDownArrowKeys];
    if ([gameView lastKeyWasShifted])
        last_shift = YES;

    [gui setText:
            [NSString stringWithFormat:@"%@: %@", DESC(@"oolite-keyconfig-update-key"), [gameView typedString]]
          forRow:end_row];
    [gui setColor:[OOColor cyanColor] forRow:end_row];

    if ([self checkKeyPress:n_key_gui_select]) {
        [gameView suppressKeysUntilKeyUp];
        // update function key
        [self updateKeyDefinition:[gameView cxx_typedString].value_or("") index:key_index];
        [gameView clearKeys]; // try to stop key bounces
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
- (void)updateKeyDefinition:(const std::string&)keystring index:(NSUInteger)index
{
    const oo::PList* entry = key_list.at(index);
    oo::PList::Dict key_def = (entry != nullptr && entry->isDict()) ? *entry->getIf<oo::PList::Dict>() : oo::PList::Dict(); // a value copy
    key_def["key"] = oo::PList(keystring);
    // auto=turn on shift if the entered key was shifted

    if (last_shift && oo::str::length(keystring) == 1 && !Contains(nav_keys, selected_entry.get<std::string>(oo::StdString(KEY_KC_DEFINITION)))) {
        key_def["shift"] = oo::PList(true);
    }
    if (!last_shift && oo::str::length(keystring) == 1) {
        key_def["shift"] = oo::PList(false);
    }
    last_shift = NO;
    StoreKeyDefinition(index, oo::PList(std::move(key_def)));
    // -processKeyCode: returns a +1 array
    key_list = oo::PListFrom(oo::adoptObjC([self processKeyCode:oo::ObjectFromPList(key_list)]).get());
}

// changes the shift/ctrl/alt state of an overridden definition
- (void)updateShiftKeyDefinition:(const std::string&)key index:(NSUInteger)index
{
    const oo::PList* entry = key_list.at(index);
    oo::PList key_def = (entry != nullptr && entry->isDict()) ? *entry : oo::PList(oo::PList::Dict()); // a value copy
    oo::PList::Dict& key_fields = *key_def.getIf<oo::PList::Dict>();
    BOOL current = key_def.get<bool>(key);
    BOOL keycode_changed = NO;
    current = !current;
    key_fields[key] = oo::PList(static_cast<bool>(current));
    if (key == "shift") {
        // force the key into upper or lower case, to limit invalid key combos as much as possible
        NSInteger k_int = (OOKeyCode)key_def.get<long long>("key"); // -integerValue
        if (k_int > 0) {
            const std::optional<std::string> keystring = oo::OptionalString([self keyCodeDescription:k_int]);
            std::optional<std::string> newstring;
            if (keystring && oo::str::length(*keystring) == 1) {
                // try switching the case. for characters that can't be switched (eg 1,2,3,etc), this should do nothing
                if (current) {
                    newstring = oo::str::uppercase(*keystring);
                } else {
                    newstring = oo::str::lowercase(*keystring);
                }
                if (newstring != keystring) {
                    key_fields["key"] = oo::PList(*newstring);
                    keycode_changed = YES;
                }
            }
        }
    }
    StoreKeyDefinition(index, std::move(key_def));
    if (keycode_changed) {
        // -processKeyCode: returns a +1 array
        key_list = oo::PListFrom(oo::adoptObjC([self processKeyCode:oo::ObjectFromPList(key_list)]).get());
    }
}

- (void)setGuiToConfirmClearScreen
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOGUIScreenID oldScreen = gui_screen;

    gui_screen = GUI_SCREEN_KEYBOARD_CONFIRMCLEAR;
    BOOL guiChanged = (oldScreen != gui_screen);

    [gui clear];
    [gui setTitle:oo::NSStringFrom(oo::DescriptionOf(DESC(@"oolite-keyconfig-clear-overrides-title")))]; // @"%@"

    [gui cxx_addLongText:oo::DescriptionOf(DESC(@"oolite-keyconfig-clear-overrides")) // @"%@"
           startingAtRow:GUI_ROW_KC_CONFIRMCLEAR
                   align:GUI_ALIGN_LEFT];

    [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-clear-yes")) forRow:GUI_ROW_KC_CONFIRMCLEAR_YES align:GUI_ALIGN_CENTER];
    [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_CONFIRMCLEAR_YES];

    [gui cxx_setText:oo::OptionalString(DESC(@"oolite-keyconfig-clear-no")) forRow:GUI_ROW_KC_CONFIRMCLEAR_NO align:GUI_ALIGN_CENTER];
    [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_KC_CONFIRMCLEAR_NO];

    [gui setSelectableRange:NSMakeRange(GUI_ROW_KC_CONFIRMCLEAR_YES, 2)];
    [gui setSelectedRow:GUI_ROW_KC_CONFIRMCLEAR_NO];

    [gui cxx_setForegroundTextureKey:std::string([self status] == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")];
    [gui cxx_setBackgroundTextureKey:std::string("keyboardsettings")];

    [[UNIVERSE gameView] clearMouse];
    [[UNIVERSE gameView] clearKeys];
    if (guiChanged)
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

- (void)handleKeyMapperConfirmClearKeys:(GuiDisplayGen*)gui view:(MyOpenGLView*)gameView
{
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
    [self handleGUIUpDownArrowKeys];

    BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT] || [gameView isDown:gvMouseDoubleClick]);
    if ([gameView isDown:gvMouseDoubleClick])
        [gameView clearMouse];

    // Translation issue: we can't confidently use raw Y and N ascii as shortcuts. It's better to use the load-previous-commander keys.
    const oo::PList yesValue = oo::PListFrom([[UNIVERSE descriptions] objectForKey:@"load-previous-commander-yes"]);
    const oo::PList noValue = oo::PListFrom([[UNIVERSE descriptions] objectForKey:@"load-previous-commander-no"]);
    const std::u16string valueYes = oo::utf8ToUtf16(oo::str::lowercase(oo::PListGet<std::string>::from(yesValue.isNull() ? nullptr : &yesValue, "y")));
    const std::u16string valueNo = oo::utf8ToUtf16(oo::str::lowercase(oo::PListGet<std::string>::from(noValue.isNull() ? nullptr : &noValue, "n")));
    unsigned char cYes, cNo;

    cYes = (valueYes.empty() ? 0 : valueYes[0]) & 0x00ff; // Use lower byte of unichar.
    cNo = (valueNo.empty() ? 0 : valueNo[0]) & 0x00ff; // Use lower byte of unichar.

    if ((selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_CONFIRMCLEAR_YES)) || [gameView isDown:cYes] || [gameView isDown:cYes - 32]) {
        [self deleteAllKeySettings];
        [gameView suppressKeysUntilKeyUp];
        [self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
    }

    if ((selectKeyPress && ([gui selectedRow] == GUI_ROW_KC_CONFIRMCLEAR_NO)) || [gameView isDown:27] || [gameView isDown:cNo] || [gameView isDown:cNo - 32]) {
        // esc or NO was pressed - get out of here
        [gameView suppressKeysUntilKeyUp];
        [self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
    }
}

- (void)displayKeyFunctionList:(GuiDisplayGen*)gui skip:(NSUInteger)skip
{
    [gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_HEADING];
    [gui setArray:[NSArray arrayWithObjects:
                          DESC(@"oolite-keyconfig-column-function"), DESC(@"oolite-keyconfig-column-assigned-to"), DESC(@"oolite-keyconfig-column-overrides"), nil]
           forRow:GUI_ROW_KC_HEADING];

    const oo::PList overrides = [self loadKeySettings];

    if (keyFunctions.empty()) // the list is never empty once built
    {
        keyFunctions = [self keyFunctionList];
    }

    NSUInteger i, n_functions = keyFunctions.size();
    NSInteger n_rows, start_row, previous = 0;
    std::optional<std::string> validate;

    if (skip >= n_functions)
        skip = n_functions - 1;

    if (n_functions < MAX_ROWS_KC_FUNCTIONS) {
        skip = 0;
        previous = 0;
        n_rows = MAX_ROWS_KC_FUNCTIONS;
        start_row = GUI_ROW_KC_FUNCSTART;
    } else {
        n_rows = MAX_ROWS_KC_FUNCTIONS - 1;
        start_row = GUI_ROW_KC_FUNCSTART;
        if (skip > 0) {
            n_rows -= 1;
            start_row += 1;
            if (skip > MAX_ROWS_KC_FUNCTIONS)
                previous = skip - (MAX_ROWS_KC_FUNCTIONS - 2);
            else
                previous = 0;
        }
    }

    if (n_functions > 0) {
        if (skip > 0) {
            [gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_FUNCSTART];
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"gui-back")), " <-- " }) forRow:GUI_ROW_KC_FUNCSTART];
            [gui cxx_setKey:oo::str::format("More:%zd", previous) forRow:GUI_ROW_KC_FUNCSTART];
        }

        for (i = 0; i < (n_functions - skip) && (int)i < n_rows; i++) {
            const oo::PList& entry = keyFunctions[i + skip];
            if (entry.find(oo::StdString(KEY_KC_HEADER)) != nullptr) {
                const std::optional<std::string> header = OptionalStringForKey(entry, oo::StdString(KEY_KC_HEADER));
                [gui cxx_setArray:Columns({ header, "", "" }) forRow:i + start_row];
                [gui setColor:[OOColor cyanColor] forRow:i + start_row];
            } else {
                const std::optional<std::string> definition = OptionalStringForKey(entry, oo::StdString(KEY_KC_DEFINITION));
                std::optional<std::string> assignment;
                std::string override;
                if (![self entryIsDictCustomEquip:entry]) {
                    // Find out what's assigned for this function currently.
                    assignment = oo::OptionalString([PLAYER keyBindingDescription2:oo::NSStringOrNil(definition)]);
                    override = (definition && overrides.find(*definition) != nullptr ? "Yes" : ""); // work out whether this assignment is overriding the setting in keyconfig2.plist
                    validate = [self validateKey:definition.value_or("") checkKeys:KeyConfigEntry(keyconfig2_settings, definition)];
                } else {
                    const std::optional<std::string> custom_keytype = [self getCustomEquipKeyDefType:definition.value_or("")];
                    NSUInteger idx = [self getCustomEquipIndex:definition.value_or("")];
                    const oo::PList& equip = CustomEquipEntry(customEquipActivation, idx);
                    const oo::PList* keyArray = equip.get<oo::PList::Array>(custom_keytype.value_or("")); // -oo_arrayForKey:
                    assignment = oo::OptionalString([PLAYER getKeyBindingDescription:(keyArray != nullptr ? oo::ObjectFromPList(*keyArray) : nil)]);
                    OOEquipmentType* item = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(OptionalStringForKey(equip, oo::StdString(CUSTOMEQUIP_EQUIPKEY)))];
                    bool result = true;
                    int j, k;
                    oo::PList defArray;
                    oo::PList compArray;

                    if (custom_keytype == oo::StdString(CUSTOMEQUIP_KEYACTIVATE)) {
                        defArray = oo::PListFrom([item defaultActivateKey]);
                        compArray = keyArray != nullptr ? *keyArray : oo::PList();
                    }
                    if (custom_keytype == oo::StdString(CUSTOMEQUIP_KEYMODE)) {
                        defArray = oo::PListFrom([item defaultModeKey]);
                        compArray = keyArray != nullptr ? *keyArray : oo::PList();
                    }
                    for (j = 0; j < defArray.count(); j++) {
                        for (k = 0; k < compArray.count(); k++) {
                            if (![self compareKeyEntries:ElementAt(defArray, j) second:ElementAt(compArray, k)]) {
                                result = false;
                                break;
                            }
                        }
                        if (result == false)
                            break;
                    }

                    override = (!result ? "Yes" : "");
                    validate = [self validateKey:definition.value_or("") checkKeys:(keyArray != nullptr ? *keyArray : oo::PList())];
                }
                if (!assignment) {
                    assignment = "   -   ";
                }

                [gui cxx_setArray:Columns({ OptionalStringForKey(entry, oo::StdString(KEY_KC_GUIDESC)), assignment, override })
                           forRow:i + start_row];
                [gui cxx_setKey:oo::str::format("Index:%zu", i + skip) forRow:i + start_row];
                if (validate) {
                    [gui setColor:[OOColor orangeColor] forRow:i + start_row];
                }
            }
        }
        if (i < n_functions - skip) {
            [gui setColor:[OOColor greenColor] forRow:start_row + i];
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"gui-more")), " --> " }) forRow:start_row + i];
            [gui cxx_setKey:oo::str::format("More:%zu", n_rows + skip) forRow:start_row + i];
            i++;
        }

        [gui setSelectableRange:NSMakeRange(GUI_ROW_KC_SELECTKBD, (i + start_row - GUI_ROW_KC_FUNCSTART) + (GUI_ROW_KC_FUNCSTART - GUI_ROW_KC_SELECTKBD))];
    }
}

- (std::vector<oo::PList>)keyFunctionList
{
    std::vector<oo::PList> funcList;

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-screen-access"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_launch_ship")) keyDef:"key_launch_ship"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_screen_options")) keyDef:"key_gui_screen_options"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_screen_equipship")) keyDef:"key_gui_screen_equipship"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_screen_interfaces")) keyDef:"key_gui_screen_interfaces"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_screen_status")) keyDef:"key_gui_screen_status"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_chart_screens")) keyDef:"key_gui_chart_screens"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_system_data")) keyDef:"key_gui_system_data"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_market")) keyDef:"key_gui_market"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-propulsion"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_roll_left")) keyDef:"key_roll_left"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_roll_right")) keyDef:"key_roll_right"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_pitch_forward")) keyDef:"key_pitch_forward"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_pitch_back")) keyDef:"key_pitch_back"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_yaw_left")) keyDef:"key_yaw_left"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_yaw_right")) keyDef:"key_yaw_right"]);

    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_increase_speed")) keyDef:"key_increase_speed"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_decrease_speed")) keyDef:"key_decrease_speed"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_inject_fuel")) keyDef:"key_inject_fuel"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_jumpdrive")) keyDef:"key_jumpdrive"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_hyperspace")) keyDef:"key_hyperspace"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_galactic_hyperspace")) keyDef:"key_galactic_hyperspace"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-navigation"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_next_compass_mode")) keyDef:"key_next_compass_mode"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_prev_compass_mode")) keyDef:"key_prev_compass_mode"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_scanner_zoom")) keyDef:"key_scanner_zoom"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_scanner_unzoom")) keyDef:"key_scanner_unzoom"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_view_forward")) keyDef:"key_view_forward"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_view_aft")) keyDef:"key_view_aft"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_view_port")) keyDef:"key_view_port"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_view_starboard")) keyDef:"key_view_starboard"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_ident_system")) keyDef:"key_ident_system"]);

    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_docking_clearance_request")) keyDef:"key_docking_clearance_request"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_autopilot")) keyDef:"key_autopilot"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_autodock")) keyDef:"key_autodock"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_docking_music")) keyDef:"key_docking_music"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-offensive"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_weapons_online_toggle")) keyDef:"key_weapons_online_toggle"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_fire_lasers")) keyDef:"key_fire_lasers"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_launch_missile")) keyDef:"key_launch_missile"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_target_missile")) keyDef:"key_target_missile"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_untarget_missile")) keyDef:"key_untarget_missile"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_target_incoming_missile")) keyDef:"key_target_incoming_missile"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_next_missile")) keyDef:"key_next_missile"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_next_target")) keyDef:"key_next_target"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_previous_target")) keyDef:"key_previous_target"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-defensive"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_ecm")) keyDef:"key_ecm"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_dump_cargo")) keyDef:"key_dump_cargo"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_rotate_cargo")) keyDef:"key_rotate_cargo"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_launch_escapepod")) keyDef:"key_launch_escapepod"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-special-equip"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_cycle_next_mfd")) keyDef:"key_cycle_next_mfd"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_cycle_previous_mfd")) keyDef:"key_cycle_previous_mfd"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_switch_next_mfd")) keyDef:"key_switch_next_mfd"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_switch_previous_mfd")) keyDef:"key_switch_previous_mfd"]);

    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_prime_next_equipment")) keyDef:"key_prime_next_equipment"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_prime_previous_equipment")) keyDef:"key_prime_previous_equipment"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_activate_equipment")) keyDef:"key_activate_equipment"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_mode_equipment")) keyDef:"key_mode_equipment"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_fastactivate_equipment_a")) keyDef:"key_fastactivate_equipment_a"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_fastactivate_equipment_b")) keyDef:"key_fastactivate_equipment_b"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-chart-screen"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_advanced_nav_array_next")) keyDef:"key_advanced_nav_array_next"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_advanced_nav_array_previous")) keyDef:"key_advanced_nav_array_previous"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_home")) keyDef:"key_map_home"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_end")) keyDef:"key_map_end"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_info")) keyDef:"key_map_info"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_zoom_in")) keyDef:"key_map_zoom_in"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_zoom_out")) keyDef:"key_map_zoom_out"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_next_system")) keyDef:"key_map_next_system"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_map_previous_system")) keyDef:"key_map_previous_system"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_chart_highlight")) keyDef:"key_chart_highlight"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-planet-info-screen"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_system_home")) keyDef:"key_system_home"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_system_end")) keyDef:"key_system_end"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_system_next_system")) keyDef:"key_system_next_system"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_system_previous_system")) keyDef:"key_system_previous_system"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-market-screen"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_market_filter_cycle")) keyDef:"key_market_filter_cycle"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_market_sorter_cycle")) keyDef:"key_market_sorter_cycle"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_market_buy_one")) keyDef:"key_market_buy_one"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_market_sell_one")) keyDef:"key_market_sell_one"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_market_buy_max")) keyDef:"key_market_buy_max"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_market_sell_max")) keyDef:"key_market_sell_max"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-misc"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_snapshot")) keyDef:"key_snapshot"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_pausebutton")) keyDef:"key_pausebutton"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_show_fps")) keyDef:"key_show_fps"]);
    //[funcList addObject:[self makeKeyGuiDict:DESC(@"oolite-keydesc-key_bloom_toggle") keyDef:@"key_bloom_toggle"]];
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_mouse_control_roll")) keyDef:"key_mouse_control_roll"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_mouse_control_yaw")) keyDef:"key_mouse_control_yaw"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_hud_toggle")) keyDef:"key_hud_toggle"]);
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_inc_field_of_view")) keyDef:"key_inc_field_of_view"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_dec_field_of_view")) keyDef:"key_dec_field_of_view"]);
#endif
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_comms_log")) keyDef:"key_comms_log"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-custom-view"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view")) keyDef:"key_custom_view"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_zoom_in")) keyDef:"key_custom_view_zoom_in"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_zoom_out")) keyDef:"key_custom_view_zoom_out"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_roll_left")) keyDef:"key_custom_view_roll_left"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_roll_right")) keyDef:"key_custom_view_roll_right"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_pan_left")) keyDef:"key_custom_view_pan_left"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_pan_right")) keyDef:"key_custom_view_pan_right"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_pan_up")) keyDef:"key_custom_view_pan_up"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_pan_down")) keyDef:"key_custom_view_pan_down"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_rotate_left")) keyDef:"key_custom_view_rotate_left"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_rotate_right")) keyDef:"key_custom_view_rotate_right"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_rotate_up")) keyDef:"key_custom_view_rotate_up"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_custom_view_rotate_down")) keyDef:"key_custom_view_rotate_down"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-oxz-manager"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_oxzmanager_setfilter")) keyDef:"key_oxzmanager_setfilter"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_oxzmanager_showinfo")) keyDef:"key_oxzmanager_showinfo"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_oxzmanager_extract")) keyDef:"key_oxzmanager_extract"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-gui"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_arrow_left")) keyDef:"key_gui_arrow_left"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_arrow_right")) keyDef:"key_gui_arrow_right"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_arrow_up")) keyDef:"key_gui_arrow_up"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_arrow_down")) keyDef:"key_gui_arrow_down"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_page_down")) keyDef:"key_gui_page_down"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_page_up")) keyDef:"key_gui_page_up"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_gui_select")) keyDef:"key_gui_select"]);

    funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-debug"))]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_dump_target_state")) keyDef:"key_dump_target_state"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_dump_entity_list")) keyDef:"key_dump_entity_list"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_debug_full")) keyDef:"key_debug_full"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_debug_collision")) keyDef:"key_debug_collision"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_debug_console_connect")) keyDef:"key_debug_console_connect"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_debug_bounding_boxes")) keyDef:"key_debug_bounding_boxes"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_debug_shaders")) keyDef:"key_debug_shaders"]);
    funcList.push_back([self makeKeyGuiDict:oo::StdString(DESC(@"oolite-keydesc-key_debug_off")) keyDef:"key_debug_off"]);

    if (customEquipActivation.size() > 0) {
        funcList.push_back([self makeKeyGuiDictHeader:oo::StdString(DESC(@"oolite-keydesc-header-oxp-equip"))]);
        int i;
        for (i = 0; i < [customEquipActivation count]; i++) {
            [funcList addObject:[self makeKeyGuiDict:[NSString stringWithFormat:@"%@ '%@'", DESC(@"oolite-keyconfig-cust-activate"), oo::PListView([customEquipActivation objectAtIndex:i]).get<NSString*>(CUSTOMEQUIP_EQUIPNAME)]
                                              keyDef:[NSString stringWithFormat:@"activate_%@", oo::PListView([customEquipActivation objectAtIndex:i]).get<NSString*>(CUSTOMEQUIP_EQUIPKEY)]]];
            [funcList addObject:[self makeKeyGuiDict:[NSString stringWithFormat:@"%@ '%@'", DESC(@"oolite-keyconfig-cust-mode"), oo::PListView([customEquipActivation objectAtIndex:i]).get<NSString*>(CUSTOMEQUIP_EQUIPNAME)]
                                              keyDef:[NSString stringWithFormat:@"mode_%@", oo::PListView([customEquipActivation objectAtIndex:i]).get<NSString*>(CUSTOMEQUIP_EQUIPKEY)]]];
        }
    }
    return funcList;
}

- (oo::PList)makeKeyGuiDict:(const std::string&)what keyDef:(const std::string&)key_def
{
    // more than 50 UTF-16 units: the first 48 and "...", as -substringToIndex:48 cut it
    const std::u16string units = oo::utf8ToUtf16(what);
    const std::string description = (units.size() > 50) ? oo::utf16ToUtf8(units.substr(0, 48)) + "..." : what;
    oo::PList::Dict guiDict;
    guiDict[oo::StdString(KEY_KC_GUIDESC)] = oo::PList(description);
    guiDict[oo::StdString(KEY_KC_DEFINITION)] = oo::PList(key_def);
    return oo::PList(std::move(guiDict));
}

- (oo::PList)makeKeyGuiDictHeader:(const std::string&)header
{
    oo::PList::Dict guiDict;
    guiDict[oo::StdString(KEY_KC_HEADER)] = oo::PList(header);
    guiDict[oo::StdString(KEY_KC_GUIDESC)] = oo::PList("");
    guiDict[oo::StdString(KEY_KC_DEFINITION)] = oo::PList("");
    return oo::PList(std::move(guiDict));
}

- (void)setGuiToKeyboardLayoutScreen:(unsigned)skip
{
    [self setGuiToKeyboardLayoutScreen:skip resetCurrentRow:NO];
}

- (void)setGuiToKeyboardLayoutScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    MyOpenGLView* gameView = [UNIVERSE gameView];
    OOGUIScreenID oldScreen = gui_screen;
    OOGUITabStop tabStop[GUI_MAX_COLUMNS];
    tabStop[0] = 10;
    tabStop[1] = 290;
    [gui setTabStops:tabStop];

    gui_screen = GUI_SCREEN_KEYBOARD_LAYOUT;
    BOOL guiChanged = (oldScreen != gui_screen);

    [[UNIVERSE gameController] setMouseInteractionModeForUIWithMouseInteraction:YES];

    [gui clear];
    [gui setTitle:[NSString stringWithFormat:@"%@", DESC(@"oolite-keyconfig-select-kbd")]];

    [self displayKeyboardLayoutList:gui skip:skip];

    [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"oolite-keyconfig-keyboard-info")) }) forRow:GUI_ROW_KC_INSTRUCT];

    [gui setSelectedRow:kbd_row];

    [gui cxx_setForegroundTextureKey:std::string([self status] == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")];
    [gui cxx_setBackgroundTextureKey:std::string("keyboardsettings")];

    [gameView clearMouse];
    [gameView clearKeys];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];

    if (guiChanged)
        [self noteGUIDidChangeFrom:oldScreen to:gui_screen];
}

- (void)handleKeyboardLayoutEntryKeys:(GuiDisplayGen*)gui view:(MyOpenGLView*)gameView
{
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];
    [self handleGUIUpDownArrowKeys];
    BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT] || [gameView isDown:gvMouseDoubleClick]);
    if ([gameView isDown:gvMouseDoubleClick])
        [gameView clearMouse];

    const std::string key = [gui cxx_keyForRow:[gui selectedRow]].value_or(""); // a nil key has no prefix
    if (selectKeyPress) {
        if (oo::str::hasPrefix(key, "More:")) {
            int from_function = SecondFieldIntValue(key);
            if (from_function < 0)
                from_function = 0;

            current_row = GUI_ROW_KC_FUNCSTART;
            if (from_function == 0)
                current_row = GUI_ROW_KC_FUNCSTART + MAX_ROWS_KC_FUNCTIONS - 1;
            [self setGuiToKeyboardLayoutScreen:from_function];
            if ([gameView isDown:gvMouseDoubleClick])
                [gameView clearMouse];
            return;
        }

        // update the keyboard code
        NSUInteger idx = SecondFieldIntValue(key);
        const std::optional<std::string> kbd = idx < kbdLayouts.size() ? OptionalStringForKey(kbdLayouts[idx], "key") : std::nullopt;
        oo::Defaults& defaults = oo::Defaults::standard();
        defaults.setObject("keyboard-code", kbd ? oo::PList(*kbd) : oo::PList());
        [self initKeyConfigSettings];
        [self initCheckingDictionary];

        [gameView clearKeys]; // try to stop key bounces
        [self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
    }
    if ([gameView isDown:27]) // escape - return without change
    {
        [gameView clearKeys]; // try to stop key bounces
        [self setGuiToKeyMapperScreen:0 resetCurrentRow:YES];
    }
}

- (std::optional<std::string>)keyboardDescription:(const std::string&)kbd
{
    const oo::PList kmap = [ResourceManager cxx_dictionaryFromFilesNamed:KeyMappingsFileName() inFolder:std::optional<std::string>("Config") mergeMode:MERGE_BASIC cache:NO];
    const oo::PList* sect = kmap.find(kbd);
    return sect != nullptr ? OptionalStringForKey(*sect, "description") : std::nullopt;
}

- (std::vector<oo::PList>)keyboardLayoutList
{
    const oo::PList kmap = [ResourceManager cxx_dictionaryFromFilesNamed:KeyMappingsFileName() inFolder:std::optional<std::string>("Config") mergeMode:MERGE_BASIC cache:NO];
    std::vector<oo::PList> kbdList;
    oo::PList def;

    if (const oo::PList::Dict* layouts = kmap.getIf<oo::PList::Dict>()) {
        for (const auto& layoutEntry : *layouts) {
            const std::string& key = layoutEntry.first;
            // +initWithObjectsAndKeys: stopped at a nil description
            oo::PList::Dict layout;
            layout["key"] = oo::PList(key);
            const std::optional<std::string> description = [self keyboardDescription:key];
            if (description)
                layout["description"] = oo::PList(*description);
            if (key != "default") {
                kbdList.push_back(oo::PList(std::move(layout)));
            } else {
                // key the "default" item separate, so we can add it at the top of the list, rather than getting it sorted
                def = oo::PList(std::move(layout));
            }
        }
    }

    // Sorted by "description", ascending, with -compare:, stably: what the sort descriptor did
    // (bead oo-3rb.20). A missing description never sorted ascending (-compare: to or from nil).
    std::stable_sort(kbdList.begin(), kbdList.end(), [](const oo::PList& a, const oo::PList& b) {
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

- (void)displayKeyboardLayoutList:(GuiDisplayGen*)gui skip:(NSUInteger)skip
{
    [gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_HEADING];
    [gui setArray:[NSArray arrayWithObjects:DESC(@"oolite-keyconfig-kbd-layout"), nil] forRow:GUI_ROW_KC_HEADING];

    if (kbdLayouts.empty())
        kbdLayouts = [self keyboardLayoutList]; // never empty once built ("default" first)

    NSUInteger i, n_functions = kbdLayouts.size();
    NSInteger n_rows, start_row, previous = 0;

    if (skip >= n_functions)
        skip = n_functions - 1;

    if (n_functions < MAX_ROWS_KC_FUNCTIONS) {
        skip = 0;
        previous = 0;
        n_rows = MAX_ROWS_KC_FUNCTIONS;
        start_row = GUI_ROW_KC_FUNCSTART;
    } else {
        n_rows = MAX_ROWS_KC_FUNCTIONS - 1;
        start_row = GUI_ROW_KC_FUNCSTART;
        if (skip > 0) {
            n_rows -= 1;
            start_row += 1;
            if (skip > MAX_ROWS_KC_FUNCTIONS)
                previous = skip - (MAX_ROWS_KC_FUNCTIONS - 2);
            else
                previous = 0;
        }
    }

    if (n_functions > 0) {
        if (skip > 0) {
            [gui setColor:[OOColor greenColor] forRow:GUI_ROW_KC_FUNCSTART];
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"gui-back")), " <-- " }) forRow:GUI_ROW_KC_FUNCSTART];
            [gui cxx_setKey:oo::str::format("More:%zd", previous) forRow:GUI_ROW_KC_FUNCSTART];
        }

        const std::string kbd = KeyboardCode();

        for (i = 0; i < (n_functions - skip) && (int)i < n_rows; i++) {
            NSDictionary* entry = [kbdLayouts objectAtIndex:i + skip];
            NSString* desc = [entry objectForKey:@"description"];
            NSString* selected = @"";
            if ([[entry objectForKey:@"key"] isEqualToString:kbd])
                selected = DESC(@"oolite-keyconfig-kbd-current");
            [gui setArray:[NSArray arrayWithObjects:desc, selected, nil] forRow:i + start_row];
            [gui setKey:[NSString stringWithFormat:@"Index:%zu", i + skip] forRow:i + start_row];
        }
        if (i < n_functions - skip) {
            [gui setColor:[OOColor greenColor] forRow:start_row + i];
            [gui cxx_setArray:Columns({ oo::OptionalString(DESC(@"gui-more")), " --> " }) forRow:start_row + i];
            [gui cxx_setKey:oo::str::format("More:%zu", n_rows + skip) forRow:start_row + i];
            i++;
        }

        [gui setSelectableRange:NSMakeRange(GUI_ROW_KC_FUNCSTART, i + start_row - GUI_ROW_KC_FUNCSTART)];
    }
}

// return an array of all functions currently in conflict
- (std::vector<std::string>)validateAllKeys
{
    std::vector<std::string> failed;
    NSUInteger i;

    for (i = 0; i < keyFunctions.size(); i++) {
        const std::optional<std::string> definition = OptionalStringForKey(keyFunctions[i], oo::StdString(KEY_KC_DEFINITION));
        const std::optional<std::string> validate = [self validateKey:definition.value_or("") checkKeys:KeyConfigEntry(keyconfig2_settings, definition)];
        if (validate) {
            failed.push_back(*validate);
        }
    }
    return failed;
}

// validate a single key against any other key that might apply to it
- (std::optional<std::string>)validateKey:(const std::string&)key checkKeys:(const oo::PList&)check_keys
{
    std::optional<std::string> result; // nullopt: no conflict (was nil)

    // need to group keys into validation groups
    const std::vector<std::string> gui_keys = { "key_gui_arrow_left", "key_gui_arrow_right", "key_gui_arrow_up", "key_gui_arrow_down", "key_gui_page_up",
        "key_gui_page_down", "key_gui_select" };

    if (Contains(gui_keys, key)) {
        result = [self searchArrayForMatch:gui_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    const std::vector<std::string> debug_keys = {
        "key_dump_target_state", "key_dump_entity_list", "key_debug_full", "key_debug_collision", "key_debug_console_connect", "key_debug_bounding_boxes",
        "key_debug_shaders", "key_debug_off"
    };

    if (Contains(debug_keys, key)) {
        result = [self searchArrayForMatch:debug_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    const std::vector<std::string> customview_keys = {
        "key_custom_view", "key_custom_view_zoom_out", "key_custom_view_zoom_in", "key_custom_view_roll_left", "key_custom_view_pan_left",
        "key_custom_view_roll_right", "key_custom_view_pan_right", "key_custom_view_rotate_up", "key_custom_view_pan_up", "key_custom_view_rotate_down",
        "key_custom_view_pan_down", "key_custom_view_rotate_left", "key_custom_view_rotate_right"
    };

    if (Contains(customview_keys, key)) {
        result = [self searchArrayForMatch:customview_keys key:key checkKeys:check_keys];
        if (result)
            return result;
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
        "key_pausebutton", "key_dump_target_state"
    };

    if ([self entryIsCustomEquip:key]) {
        NSUInteger i;
        for (i = 0; i < customEquipActivation.size(); i++) {
            const std::optional<std::string> equipKey = OptionalStringForKey(customEquipActivation[i], oo::StdString(CUSTOMEQUIP_EQUIPKEY));
            inflight_keys.push_back(oo::str::format("activate_%s", DescriptionOfString(equipKey).c_str()));
            inflight_keys.push_back(oo::str::format("mode_%s", DescriptionOfString(equipKey).c_str()));
        }
    }

    if (Contains(inflight_keys, key)) {
        result = [self searchArrayForMatch:inflight_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    const std::vector<std::string> docking_keys = {
        "key_docking_music", "key_autopilot", "key_pausebutton"
    };

    if (Contains(docking_keys, key)) {
        result = [self searchArrayForMatch:docking_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    std::vector<std::string> docked_keys = { "key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status",
        "key_gui_chart_screens", "key_gui_system_data", "key_gui_market" };
    docked_keys.insert(docked_keys.end(), gui_keys.begin(), gui_keys.end());

    if (Contains(docked_keys, key)) {
        result = [self searchArrayForMatch:docked_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    std::vector<std::string> paused_keys = { "key_pausebutton", "key_gui_screen_options", "key_hud_toggle", "key_show_fps", "key_mouse_control_roll",
        "key_mouse_control_yaw" };
    paused_keys.insert(paused_keys.end(), debug_keys.begin(), debug_keys.end());
    paused_keys.insert(paused_keys.end(), customview_keys.begin(), customview_keys.end());

    if (Contains(paused_keys, key)) {
        result = [self searchArrayForMatch:paused_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    const std::vector<std::string> chart_keys = {
        "key_advanced_nav_array_next", "key_advanced_nav_array_previous", "key_map_home", "key_map_end", "key_map_info",
        "key_map_zoom_in", "key_map_zoom_out", "key_map_next_system", "key_map_previous_system", "key_chart_highlight",
        "key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status",
        "key_gui_chart_screens", "key_gui_system_data", "key_gui_market"
    };

    if (Contains(chart_keys, key)) {
        result = [self searchArrayForMatch:chart_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    const std::vector<std::string> sysinfo_keys = {
        "key_system_home", "key_system_end", "key_system_next_system", "key_system_previous_system",
        "key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status",
        "key_gui_chart_screens", "key_gui_system_data", "key_gui_market"
    };

    if (Contains(sysinfo_keys, key)) {
        result = [self searchArrayForMatch:sysinfo_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    const std::vector<std::string> market_keys = {
        "key_market_filter_cycle", "key_market_sorter_cycle", "key_market_buy_one", "key_market_sell_one", "key_market_buy_max",
        "key_market_sell_max", "key_launch_ship", "key_gui_screen_options", "key_gui_screen_equipship", "key_gui_screen_interfaces", "key_gui_screen_status",
        "key_gui_chart_screens", "key_gui_system_data", "key_gui_market", "key_gui_arrow_up", "key_gui_arrow_down", "key_gui_page_up",
        "key_gui_page_down", "key_gui_select"
    };

    if (Contains(market_keys, key)) {
        result = [self searchArrayForMatch:market_keys key:key checkKeys:check_keys];
        if (result)
            return result;
    }

    // if we get here, we should be good
    return std::nullopt;
}

// performs a search of all keys in the search_list, and for any key that isn't the one we've passed, check the
// keys against the values we're passing in. if there's a hit, return the key found
- (std::optional<std::string>)searchArrayForMatch:(const std::vector<std::string>&)search_list key:(const std::string&)key checkKeys:(const oo::PList&)check_keys
{
    NSUInteger j, k;
    for (const std::string& search : search_list) {
        // only check other key settings, not the one we've been passed
        if (search != key) {
            // get the array from keyconfig2_settings
            // we need to compare all entries to each other to look for any match, as any match would indicate a conflict
            oo::PList current;
            if (![self entryIsCustomEquip:search]) {
                current = KeyConfigEntry(keyconfig2_settings, search);
            } else {
                NSUInteger idx = [self getCustomEquipIndex:search];
                const std::optional<std::string> keytype = [self getCustomEquipKeyDefType:search];
                const oo::PList* field = keytype.has_value() ? CustomEquipEntry(customEquipActivation, idx).find(*keytype) : nullptr;
                current = (field != nullptr) ? *field : oo::PList();
            }
            for (j = 0; j < current.count(); j++) {
                for (k = 0; k < check_keys.count(); k++) {
                    const oo::PList* currentEntry = current.at(j);
                    const oo::PList* checkEntry = check_keys.at(k);
                    if ([self compareKeyEntries:currentEntry != nullptr ? *currentEntry : oo::PList() second:checkEntry != nullptr ? *checkEntry : oo::PList()])
                        return search;
                }
            }
        }
    }
    return std::nullopt;
}

// compares the currently stored key_list against the base default from keyconfig2.plist
- (BOOL)entryIsEqualToDefault:(const std::string&)key
{
    const oo::PList* defValue = kdic_check.find(key);
    const oo::PList def = defValue != nullptr ? *defValue : oo::PList();
    const oo::PList& keys = key_list;
    NSUInteger i;

    if (def.count() != keys.count())
        return NO;
    for (i = 0; i < keys.count(); i++) {
        const oo::PList* orig = def.at(i);
        const oo::PList* entrd = keys.at(i);
        if (![self compareKeyEntries:orig != nullptr ? *orig : oo::PList() second:entrd != nullptr ? *entrd : oo::PList()])
            return NO;
    }
    return YES;
}

// compares two key dictionaries to see if they have the same settings
- (BOOL)compareKeyEntries:(const oo::PList&)first second:(const oo::PList&)second
{
    // "key" as -integerValue read it (a string or a number); the modifiers as -boolValue
    if (first.get<long long>("key") == second.get<long long>("key")) {
        if (first.get<bool>("shift") == second.get<bool>("shift") && first.get<bool>("mod1") == second.get<bool>("mod1") && first.get<bool>("mod2") == second.get<bool>("mod2"))
            return YES;
    }
    return NO;
}

// saves the currently store key_list to the defaults file and updates the global definition
- (void)saveKeySetting:(const std::string&)key
{
    // check for a blank entry
    oo::PList::Array* keys = key_list.getIf<oo::PList::Array>();
    if (key_list.count() > 1 && key_list.at(1)->get<long long>("key") == 0) {
        keys->erase(keys->begin() + 1);
    }
    // make sure the primary and alternate keys are different
    if (key_list.count() > 1) {
        if ([self compareKeyEntries:*key_list.at(0) second:*key_list.at(1)]) {
            keys->erase(keys->begin() + 1);
        }
    }
    // see if we've set the key settings to blank - in which case, delete the override
    if ((key_list.at(0) != nullptr ? key_list.at(0)->get<long long>("key") : 0) == 0) // -integerValue
    {
        if (key_list.count() == 1 || (key_list.count() > 1 && IsEmptyString(key_list.at(1)->find("key")))) {
            [self deleteKeySetting:key];
            // reload settings
            [self initKeyConfigSettings];
            [self reloadPage];
            return;
        }
    }

    oo::Defaults& defaults = oo::Defaults::standard();

    if (![self entryIsCustomEquip:key]) {
        // if we've got the same settings as the default, revert to the default
        if ([self entryIsEqualToDefault:key]) {
            [self deleteKeySetting:key];
            // reload settings
            [self initKeyConfigSettings];
            [self reloadPage];
            return;
        }
        oo::PList::Dict keyconf = KeyConfigOverrides();
        keyconf[key] = key_list;
        defaults.setObject(oo::StdString(KEYCONFIG_OVERRIDES), oo::PList(std::move(keyconf)));
    } else {
        NSUInteger idx = [self getCustomEquipIndex:key];
        if (oo::PList::Dict* fields = CustomEquipFields(customEquipActivation, idx))
            (*fields)[[self getCustomEquipKeyDefType:key].value_or("")] = key_list; // in place
        defaults.setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
    }
    // reload settings
    [self initKeyConfigSettings];
    [self reloadPage];
}

// unsets the key setting in the overrides, and updates the global definition
- (void)unsetKeySetting:(const std::string&)key
{
    oo::Defaults& defaults = oo::Defaults::standard();
    if (![self entryIsCustomEquip:key]) {
        oo::PList::Dict keyconf = KeyConfigOverrides();
        keyconf[key] = oo::PList(oo::PList::Array()); // an empty override
        defaults.setObject(oo::StdString(KEYCONFIG_OVERRIDES), oo::PList(std::move(keyconf)));
    } else {
        NSUInteger idx = [self getCustomEquipIndex:key];
        if (oo::PList::Dict* fields = CustomEquipFields(customEquipActivation, idx))
            fields->erase([self getCustomEquipKeyDefType:key].value_or("")); // in place
        defaults.setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
    }
    // reload settings
    [self initKeyConfigSettings];
}

// removes the key setting from the overrides, and updates the global definition
- (void)deleteKeySetting:(const std::string&)key
{
    oo::Defaults& defaults = oo::Defaults::standard();
    if (![self entryIsCustomEquip:key]) {
        oo::PList::Dict keyconf = KeyConfigOverrides();
        keyconf.erase(key);
        defaults.setObject(oo::StdString(KEYCONFIG_OVERRIDES), oo::PList(std::move(keyconf)));
    } else {
        // the customEquipActivation entry is edited in place, as before
        const std::optional<std::string> keyDefType = [self getCustomEquipKeyDefType:key];
        oo::PList::Dict* fields = CustomEquipFields(customEquipActivation, [self getCustomEquipIndex:key]);
        if (fields != nullptr && keyDefType.has_value())
            fields->erase(*keyDefType);
        defaults.setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
    }
    // reload settings
    [self initKeyConfigSettings];
}

// removes all key settings from the overrides, and updates the global definition
- (void)deleteAllKeySettings
{
    oo::Defaults& defaults = oo::Defaults::standard();
    defaults.removeObject(oo::StdString(KEYCONFIG_OVERRIDES));
    if (customEquipActivation.size() > 0) {
        NSUInteger i;
        for (i = 0; i < customEquipActivation.size(); i++) {
            const std::optional<std::string> eq = OptionalStringForKey(customEquipActivation[i], oo::StdString(CUSTOMEQUIP_EQUIPKEY));
            OOEquipmentType* item = [OOEquipmentType equipmentTypeWithIdentifier:oo::NSStringOrNil(eq)];
            oo::PList::Dict* fields = CustomEquipFields(customEquipActivation, i); // edited in place
            if (fields == nullptr)
                continue;
            if ([item defaultActivateKey])
                fields->insert_or_assign(oo::StdString(CUSTOMEQUIP_KEYACTIVATE), oo::PListFrom([item defaultActivateKey]));
            else
                fields->erase(oo::StdString(CUSTOMEQUIP_KEYACTIVATE));

            if ([item defaultModeKey])
                fields->insert_or_assign(oo::StdString(CUSTOMEQUIP_KEYMODE), oo::PListFrom([item defaultModeKey]));
            else
                fields->erase(oo::StdString(CUSTOMEQUIP_KEYMODE));
        }
        defaults.setObject(oo::StdString(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
    }
    // reload settings
    [self initKeyConfigSettings];
}

// returns all key settings from the overrides
- (oo::PList)loadKeySettings
{
    return oo::Defaults::standard().object(oo::StdString(KEYCONFIG_OVERRIDES));
}

// reloads the main page at the appropriate page
- (void)reloadPage
{
    // Update the GUI (this will refresh the function list).
    unsigned skip;
    if (selFunctionIdx < MAX_ROWS_KC_FUNCTIONS - 1) {
        skip = 0;
    } else {
        skip = ((selFunctionIdx - 1) / (MAX_ROWS_KC_FUNCTIONS - 2)) * (MAX_ROWS_KC_FUNCTIONS - 2) + 1;
    }

    [self setGuiToKeyMapperScreen:skip];
}

@end