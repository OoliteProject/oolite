/*

PlayerEntityStickMapper.m

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

#import "PlayerEntityStickMapper.h"
#import "HeadUpDisplay.h"
#import "OOFoundationBridge.h"
#import "OOJoystickManager.h"
#import "OOTexture.h"
#import "PlayerEntityControls.h"
#import "PlayerEntityStickProfile.h"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

@interface PlayerEntity (StickMapperInternal)

- (void)resetStickFunctions;
- (void)checkCustomEquipButtons:(const oo::PList&)stickFn ignore:(int)idx;
- (void)removeFunction:(int)selFunctionIdx;
- (std::vector<oo::PList>)stickFunctionList;
- (void)displayFunctionList:(GuiDisplayGen*)gui
                       skip:(NSUInteger)skip;
- (std::optional<std::string>)describeStickDict:(const oo::PList*)stickDict; // nullptr: nil
- (std::string)hwToString:(int)hwFlags;

@end

namespace {

// The columns of a row as +arrayWithObjects: took them: up to the first nil.
std::vector<std::string> ColumnsUpToNil(std::initializer_list<std::optional<std::string>> columns)
{
    std::vector<std::string> result;
    for (const std::optional<std::string>& column : columns) {
        if (!column.has_value())
            break;
        result.push_back(*column);
    }
    return result;
}

// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

// The object a dictionary held under key (nil when absent), for -intValue / -boolValue as before.
id ObjectForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    return value != nullptr ? oo::ObjectFromPList(*value) : nil;
}

// The string's -length - 5 characters of a stick name, then "..." (UTF-16 units, as before).
std::string TruncatedByFive(const std::string& name)
{
    std::u16string units = oo::utf8ToUtf16(name);
    units.resize(units.size() - 5);
    return oo::utf16ToUtf8(units) + "...";
}

// The -intValue of the part of a GUI key after its first ':' ("Index:3", "More:12").
int NumberAfterColon(const std::string& key)
{
    const std::size_t colon = key.find(':');
    std::string part = colon == std::string::npos ? std::string() : key.substr(colon + 1);
    const std::size_t next = part.find(':');
    if (next != std::string::npos)
        part.resize(next);
    return [oo::NSStringFrom(part) intValue];
}

// A mutable copy of a custom equipment entry, as -mutableCopy made (PlayerEntityKeyMapper edits
// these in place).
id MutableObjectFrom(const oo::PList& entry)
{
    return [[oo::ObjectFromPList(entry) mutableCopy] autorelease];
}

// -oo_integerForKey: of an entry that may be absent (nil: 0).
NSInteger IntegerIn(const oo::PList* dict, std::string_view key)
{
    return dict != nullptr ? dict->get<NSInteger>(key) : 0;
}

} // namespace

@implementation PlayerEntity (StickMapper)

- (void)resetStickFunctions
{
    [stickFunctions release];
    stickFunctions = nil;
}

- (void)setGuiToStickMapperScreen:(unsigned)skip
{
    [self setGuiToStickMapperScreen:skip resetCurrentRow:NO];
}

- (void)setGuiToStickMapperScreen:(unsigned)skip resetCurrentRow:(BOOL)resetCurrentRow
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    OOJoystickManager* stickHandler = [OOJoystickManager sharedStickHandler];
    const std::vector<std::string> stickList = [stickHandler listSticks];
    unsigned stickCount = stickList.size();
    unsigned i;

    OOGUITabStop tabStop[GUI_MAX_COLUMNS];
    tabStop[0] = 10;
    tabStop[1] = 290;
    tabStop[2] = 400;
    [gui setTabStops:tabStop];

    gui_screen = GUI_SCREEN_STICKMAPPER;
    [gui clear];
    [gui setTitle:[NSString stringWithFormat:@"%@", DESC(@"stickmapper-header")]];

    for (i = 0; i < stickCount; i++) {
        NSString* stickNameForThisRow = [NSString stringWithFormat:@"%@ %d %@", DESC(@"stickmapper-stick"), i + 1, [stickList objectAtIndex:i]];
        // for more than 2 sticks, the stick name rows are populated by more than one name if needed
        std::optional<std::string> stickNameAdditional;
        if (stickCount > 2 && OOStringWidthInEm(oo::NSStringFrom(stickNameForThisRow)) > 18.0) {
            // string is too long, truncate it until its length gets below threshold
            do {
                stickNameForThisRow = TruncatedByFive(stickNameForThisRow);
            } while (OOStringWidthInEm(oo::NSStringFrom(stickNameForThisRow)) > 18.0);
        }
        unsigned j = i + 2;
        if (j < stickCount) {
            stickNameAdditional = [NSString stringWithFormat:@"%@ %d %@", DESC(@"stickmapper-stick"), j + 1, [stickList objectAtIndex:j]];
            if (OOStringWidthInEm(stickNameAdditional) > 11.0) {
                // string is too long, truncate it until its length gets below threshold
                do {
                    stickNameAdditional = TruncatedByFive(*stickNameAdditional);
                } while (OOStringWidthInEm(oo::NSStringFrom(*stickNameAdditional)) > 11.0);
            }
        }
        [gui cxx_setArray:ColumnsUpToNil({ stickNameForThisRow,
                              std::string(), // skip one column
                              stickNameAdditional })
                   forRow:i + GUI_ROW_STICKNAME];
    }

    [gui cxx_setArray:ColumnsUpToNil({ oo::OptionalString(DESC(@"stickmapper-profile")) }) forRow:GUI_ROW_STICKPROFILE];
    [gui cxx_setKey:oo::StdString(GUI_KEY_OK) forRow:GUI_ROW_STICKPROFILE];
    [self displayFunctionList:gui skip:skip];

    [gui setArray:[NSArray arrayWithObject:DESC(@"stickmapper-help-text-1")]
           forRow:GUI_ROW_INSTRUCT];

    [gui setText:DESC(@"stickmapper-help-text-2") forRow:GUI_ROW_INSTRUCT + 1 align:GUI_ALIGN_CENTER];

    if (resetCurrentRow) {
        [gui setSelectedRow:GUI_ROW_STICKPROFILE];
    }
    [[UNIVERSE gameView] suppressKeysUntilKeyUp];
    [gui cxx_setForegroundTextureKey:std::string([self status] == STATUS_DOCKED ? "docked_overlay" : "paused_overlay")];
    [gui cxx_setBackgroundTextureKey:std::string("settings")];
}

- (void)stickMapperInputHandler:(GuiDisplayGen*)gui
                           view:(MyOpenGLView*)gameView
{
    OOJoystickManager* stickHandler = [OOJoystickManager sharedStickHandler];
    // Don't do anything if the user is supposed to be selecting
    // a function - other than look for Escape.
    if (waitingForStickCallback) {
        if ([gameView isDown:27]) {
            [stickHandler clearCallback];
            [gui setArray:[NSArray arrayWithObjects:
                                  DESC(@"stickmapper-set-aborted"), nil]
                   forRow:GUI_ROW_INSTRUCT];
            waitingForStickCallback = NO;
        }

        // Break out now.
        return;
    }
    const BOOL* joyButtonState = [stickHandler getAllButtonStates];
    [self handleGUIUpDownArrowKeys];
    BOOL selectKeyPress = ([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT] || [gameView isDown:gvMouseDoubleClick]);

    if ([gui selectedRow] == GUI_ROW_STICKPROFILE && selectKeyPress) {
        [self setGuiToStickProfileScreen:gui];
        return;
    }

    const std::optional<std::string> key = [gui cxx_keyForRow:[gui selectedRow]];
    if (key.has_value() && oo::str::hasPrefix(*key, "Index:"))
        selFunctionIdx = NumberAfterColon(*key);
    else
        selFunctionIdx = -1;

    if (selectKeyPress) {
        if ([key hasPrefix:@"More:"]) {
            int from_function = [[[key componentsSeparatedByString:@":"] objectAtIndex:1] intValue];
            if (from_function < 0)
                from_function = 0;

            [self setGuiToStickMapperScreen:from_function];
            if ([[UNIVERSE gui] selectedRow] < 0)
                [[UNIVERSE gui] setSelectedRow:GUI_ROW_FUNCSTART];
            if (from_function == 0)
                [[UNIVERSE gui] setSelectedRow:GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1];
            return;
        }

        // stickFunctions is PlayerEntity's Objective-C array of the function entries.
        const oo::PList entry = oo::PListFrom([stickFunctions objectAtIndex:selFunctionIdx]);
        int hw = [ObjectForKey(entry, KEY_ALLOWABLE) intValue];
        [stickHandler setCallback:@selector(updateFunction:)
                           object:self
                         hardware:hw];

        // Print instructions
        std::string instructions;
        switch (hw) {
        case HW_AXIS:
            instructions = DESC(@"stickmapper-set-help-text-axis");
            break;
        case HW_BUTTON:
            instructions = DESC(@"stickmapper-set-help-text-button");
            break;
        default:
            instructions = DESC(@"stickmapper-set-help-text-either");
        }
        [gui cxx_setArray:std::vector<std::string> { instructions } forRow:GUI_ROW_INSTRUCT];
        waitingForStickCallback = YES;
    }

    if ([gameView isDown:'u']) {
        if (selFunctionIdx >= 0)
            [self removeFunction:selFunctionIdx];
    }
}

// Callback function, called by JoystickHandler when the callback
// is set. The dictionary contains the thing that was pressed/moved.
- (void)updateFunction:(id)hwDictObject // called by name with an Objective-C dictionary
{
    const oo::PList hwDict = oo::PListFrom(hwDictObject);
    OOJoystickManager* stickHandler = [OOJoystickManager sharedStickHandler];
    waitingForStickCallback = NO;

    // Right time and the right place?
    if (gui_screen != GUI_SCREEN_STICKMAPPER) {
        OOLog(@"joystick.configure.error", @"%s called when not on stick mapper screen.", __PRETTY_FUNCTION__);
        return;
    }
    // What moved?
    int function;
    NSDictionary* entry = [stickFunctions objectAtIndex:selFunctionIdx];
    if (oo::PListView(hwDict).get<bool>(STICK_ISAXIS)) {
        function = oo::PListView(entry).get<int>(KEY_AXISFN);
        if (function == AXIS_THRUST) {
            [stickHandler unsetButtonFunction:BUTTON_INCTHRUST];
            [stickHandler unsetButtonFunction:BUTTON_DECTHRUST];
        }
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
        if (function == AXIS_FIELD_OF_VIEW) {
            [stickHandler unsetButtonFunction:BUTTON_INC_FIELD_OF_VIEW];
            [stickHandler unsetButtonFunction:BUTTON_DEC_FIELD_OF_VIEW];
        }
#endif
        if (function == AXIS_VIEWX) {
            [stickHandler unsetButtonFunction:BUTTON_VIEWPORT];
            [stickHandler unsetButtonFunction:BUTTON_VIEWSTARBOARD];
        }
        if (function == AXIS_VIEWY) {
            [stickHandler unsetButtonFunction:BUTTON_VIEWFORWARD];
            [stickHandler unsetButtonFunction:BUTTON_VIEWAFT];
        }
    } else {
        function = entry.get<int>(KEY_BUTTONFN);
        if (function == BUTTON_INCTHRUST || function == BUTTON_DECTHRUST) {
            [stickHandler unsetAxisFunction:AXIS_THRUST];
        }
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
        if (function == BUTTON_INC_FIELD_OF_VIEW || function == BUTTON_DEC_FIELD_OF_VIEW) {
            [stickHandler unsetAxisFunction:AXIS_FIELD_OF_VIEW];
        }
#endif
        if (function == BUTTON_VIEWPORT || function == BUTTON_VIEWSTARBOARD) {
            [stickHandler unsetAxisFunction:AXIS_VIEWX];
        }
        if (function == BUTTON_VIEWFORWARD || function == BUTTON_VIEWAFT) {
            [stickHandler unsetAxisFunction:AXIS_VIEWY];
        }
    }
    // special case for OXP equipment buttons
    if (function >= 10000) {
        std::string key = oo::StdString(CUSTOMEQUIP_BUTTONACTIVATE);
        function -= 10000;
        if (function >= 10000) {
            function -= 10000;
            key = oo::StdString(CUSTOMEQUIP_BUTTONMODE);
        }
        // customEquipActivation is PlayerEntity's Objective-C array of mutable entries.
        oo::PList custEquip = oo::PListFrom([customEquipActivation objectAtIndex:function]);
        if (oo::PList::Dict* custEquipDict = custEquip.getIf<oo::PList::Dict>())
            (*custEquipDict)[key] = hwDict;
        [customEquipActivation replaceObjectAtIndex:function withObject:MutableObjectFrom(custEquip)];
        [self checkCustomEquipButtons:hwDict ignore:function];
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:customEquipActivation forKey:KEYCONFIG_CUSTOMEQUIP];
    } else {
        if (function >= BUTTON_GUILEFT && function <= BUTTON_GUISELECT) {
            [stickHandler setFunction:function withDict:hwDict];
        } else {
            [stickHandler setFunction:function withDict:hwDict];
            [self checkCustomEquipButtons:hwDict ignore:-1];
        }
        [stickHandler saveStickSettings];
    }

    // Update the GUI (this will refresh the function list).
    unsigned skip;
    if (selFunctionIdx < MAX_ROWS_FUNCTIONS - 1) {
        skip = 0;
    } else {
        skip = ((selFunctionIdx - 1) / (MAX_ROWS_FUNCTIONS - 2)) * (MAX_ROWS_FUNCTIONS - 2) + 1;
    }

    [self setGuiToStickMapperScreen:skip];
}

- (void)checkCustomEquipButtons:(const oo::PList&)stickFn ignore:(int)idx
{
    const std::string stickNumberKey = oo::StdString(STICK_NUMBER);
    const std::string stickAxBtKey = oo::StdString(STICK_AXBUT);
    const std::string activateKey = oo::StdString(CUSTOMEQUIP_BUTTONACTIVATE);
    const std::string modeKey = oo::StdString(CUSTOMEQUIP_BUTTONMODE);
    int i;
    for (i = 0; i < [customEquipActivation count]; i++) {
        if (i != idx) {
            const oo::PList original = oo::PListFrom([customEquipActivation objectAtIndex:i]);
            oo::PList custEquip = original;
            oo::PList::Dict* custEquipDict = custEquip.getIf<oo::PList::Dict>();
            const oo::PList* bf = original.find(activateKey);
            if (IntegerIn(bf, stickNumberKey) == stickFn.get<NSInteger>(stickNumberKey) && IntegerIn(bf, stickAxBtKey) == stickFn.get<NSInteger>(stickAxBtKey) && custEquip.find(activateKey) != nullptr) {
                custEquipDict->erase(activateKey);
            }
            bf = original.find(modeKey);
            if (IntegerIn(bf, stickNumberKey) == stickFn.get<NSInteger>(stickNumberKey) && IntegerIn(bf, stickAxBtKey) == stickFn.get<NSInteger>(stickAxBtKey) && custEquip.find(modeKey) != nullptr) {
                custEquipDict->erase(modeKey);
            }
            [customEquipActivation replaceObjectAtIndex:i withObject:MutableObjectFrom(custEquip)];
        }
    }
}

- (void)removeFunction:(int)idx
{
    OOJoystickManager* stickHandler = [OOJoystickManager sharedStickHandler];
    const oo::PList entry = oo::PListFrom([stickFunctions objectAtIndex:idx]);
    id butfunc = ObjectForKey(entry, KEY_BUTTONFN); // -intValue as before
    id axfunc = ObjectForKey(entry, KEY_AXISFN);
    BOOL custom = NO;
    selFunctionIdx = idx;

    // Some things can have either axis or buttons - make sure we clear
    // both!
    if (butfunc) {
        // special case for OXP equipment buttons
        if ([butfunc intValue] >= 10000) {
            int bf = [butfunc intValue];
            custom = YES;
            std::string key = oo::StdString(CUSTOMEQUIP_BUTTONACTIVATE);
            bf -= 10000;
            if (bf >= 10000) {
                bf -= 10000;
                key = oo::StdString(CUSTOMEQUIP_BUTTONMODE);
            }
            oo::PList custEquip = oo::PListFrom([customEquipActivation objectAtIndex:bf]);
            if (oo::PList::Dict* custEquipDict = custEquip.getIf<oo::PList::Dict>())
                custEquipDict->erase(key); // both tests reduce to "remove key if present"
            [customEquipActivation replaceObjectAtIndex:bf withObject:MutableObjectFrom(custEquip)];
        } else {
            [stickHandler unsetButtonFunction:[butfunc intValue]];
        }
    }
    if (axfunc) {
        [stickHandler unsetAxisFunction:[axfunc intValue]];
    }
    if (!custom) {
        [stickHandler saveStickSettings];
    } else {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:customEquipActivation forKey:KEYCONFIG_CUSTOMEQUIP];
    }

    unsigned skip;
    if (selFunctionIdx < MAX_ROWS_FUNCTIONS - 1)
        skip = 0;
    else
        skip = ((selFunctionIdx - 1) / (MAX_ROWS_FUNCTIONS - 2)) * (MAX_ROWS_FUNCTIONS - 2) + 1;
    [self setGuiToStickMapperScreen:skip];
}

- (void)displayFunctionList:(GuiDisplayGen*)gui
                       skip:(NSUInteger)skip
{
    OOJoystickManager* stickHandler = [OOJoystickManager sharedStickHandler];

    [gui setColor:[OOColor greenColor] forRow:GUI_ROW_HEADING];
    [gui setArray:[NSArray arrayWithObjects:
                          DESC(@"stickmapper-column-function"), DESC(@"stickmapper-column-assigned-to"), DESC(@"stickmapper-column-type"), nil]
           forRow:GUI_ROW_HEADING];

    if (!stickFunctions) {
        // PlayerEntity keeps the entries as an Objective-C array.
        stickFunctions = [oo::ObjectFromPList(oo::PList([self stickFunctionList])) retain];
    }
    NSDictionary* assignedAxes = [stickHandler axisFunctions];
    NSDictionary* assignedButs = [stickHandler buttonFunctions];
    NSDictionary* assignedGuiButs = [stickHandler guiButtonFunctions];

    NSUInteger i, n_functions = [stickFunctions count];
    NSInteger n_rows, start_row, previous = 0;

    if (skip >= n_functions)
        skip = n_functions - 1;

    if (n_functions < MAX_ROWS_FUNCTIONS) {
        skip = 0;
        previous = 0;
        n_rows = MAX_ROWS_FUNCTIONS;
        start_row = GUI_ROW_FUNCSTART;
    } else {
        n_rows = MAX_ROWS_FUNCTIONS - 1;
        start_row = GUI_ROW_FUNCSTART;
        if (skip > 0) {
            n_rows -= 1;
            start_row += 1;
            if (skip > MAX_ROWS_FUNCTIONS)
                previous = skip - (MAX_ROWS_FUNCTIONS - 2);
            else
                previous = 0;
        }
    }

    if (n_functions > 0) {
        if (skip > 0) {
            [gui setColor:[OOColor greenColor] forRow:GUI_ROW_FUNCSTART];
            [gui cxx_setArray:ColumnsUpToNil({ oo::OptionalString(DESC(@"gui-back")), std::string(" <-- ") }) forRow:GUI_ROW_FUNCSTART];
            [gui cxx_setKey:oo::str::format("More:%zd", previous) forRow:GUI_ROW_FUNCSTART];
        }

        for (i = 0; i < (n_functions - skip) && (int)i < n_rows; i++) {
            const oo::PList entry = oo::PListFrom([stickFunctions objectAtIndex:i + skip]);
            if (entry.find(KEY_HEADER) != nullptr) {
                const std::optional<std::string> header = OptionalStringForKey(entry, KEY_HEADER);
                [gui cxx_setArray:ColumnsUpToNil({ header, std::string(), std::string() }) forRow:i + start_row];
                [gui setColor:[OOColor cyanColor] forRow:i + start_row];
            } else {
                std::string allowedThings;
                std::optional<std::string> assignment;
                const std::optional<std::string> axFuncKey = OptionalStringForKey(entry, KEY_AXISFN);
                const std::optional<std::string> butFuncKey = OptionalStringForKey(entry, KEY_BUTTONFN);
                // -objectForKey: of a nil key found nothing
                const oo::PList* assignedAxis = axFuncKey.has_value() ? assignedAxes.find(*axFuncKey) : nullptr;
                const oo::PList* assignedButton = butFuncKey.has_value() ? assignedButs.find(*butFuncKey) : nullptr;
                int allowable = entry.get<int>(KEY_ALLOWABLE);
                switch (allowable) {
                case HW_AXIS:
                    allowedThings = DESC(@"stickmapper-allowed-axis");
                    assignment = [self describeStickDict:
                            [assignedAxes objectForKey:axFuncKey]];
                    break;
                case HW_BUTTON:
                    allowedThings = DESC(@"stickmapper-allowed-button");
                    int bf;
                    bf = [oo::NSStringOrNil(butFuncKey) integerValue];
                    if (bf < 10000) {
                        if (bf >= BUTTON_GUILEFT && bf <= BUTTON_GUISELECT) {
                            assignment = [self describeStickDict:
                                [assignedGuiButs objectForKey:butFuncKey]];
                        } else {
                            assignment = [self describeStickDict:
                                [assignedButs objectForKey:butFuncKey]];
                        }
                    } else {
                        std::string key = oo::StdString(CUSTOMEQUIP_BUTTONACTIVATE);
                        bf -= 10000;
                        if (bf >= 10000) {
                            bf -= 10000;
                            key = oo::StdString(CUSTOMEQUIP_BUTTONMODE);
                        }
                        const oo::PList custom = oo::PListFrom([customEquipActivation objectAtIndex:bf]);
                        assignment = [self describeStickDict:custom.find(key)];
                    }
                    break;
                default:
                    allowedThings = DESC(@"stickmapper-allowed-both");

                    // axis has priority
                    assignment = [self describeStickDict:
                            [assignedAxes objectForKey:axFuncKey]];
                    if (!assignment) {
                        int bf = [butFuncKey integerValue];
                        if (bf >= BUTTON_GUILEFT && bf <= BUTTON_GUISELECT) {
                            assignment = [self describeStickDict:
                                [assignedGuiButs objectForKey:butFuncKey]];
                        } else {
                            assignment = [self describeStickDict:
                                [assignedButs objectForKey:butFuncKey]];
                        }
                    }
                }

                // Find out what's assigned for this function currently.
                if (!assignment.has_value()) {
                    assignment = "   -   ";
                }

                [gui cxx_setArray:ColumnsUpToNil({ OptionalStringForKey(entry, KEY_GUIDESC), assignment, allowedThings })
                           forRow:i + start_row];
                //[gui setKey: GUI_KEY_OK forRow: i + start_row];
                [gui cxx_setKey:oo::str::format("Index:%zu", i + skip) forRow:i + start_row];
            }
        }
        if (i < n_functions - skip) {
            [gui setColor:[OOColor greenColor] forRow:start_row + i];
            [gui cxx_setArray:ColumnsUpToNil({ oo::OptionalString(DESC(@"gui-more")), std::string(" --> ") }) forRow:start_row + i];
            [gui cxx_setKey:oo::str::format("More:%zu", n_rows + skip) forRow:start_row + i];
            i++;
        }

        [gui setSelectableRange:NSMakeRange(GUI_ROW_STICKPROFILE, i + start_row - GUI_ROW_STICKPROFILE)];
    }
}

- (std::optional<std::string>)describeStickDict:(const oo::PList*)stickDict
{
    std::optional<std::string> desc;
    if (stickDict != nullptr) {
        // -intValue / -boolValue of the objects the dictionary held, as before
        int thingNumber = [ObjectForKey(*stickDict, oo::StdString(STICK_AXBUT))
            intValue];
        int stickNumber = [ObjectForKey(*stickDict, oo::StdString(STICK_NUMBER))
            intValue];
        // Button or axis?
        if ([(NSNumber*)[stickDict objectForKey:STICK_ISAXIS] boolValue]) {
            desc = [NSString stringWithFormat:@"%@ %d %@ %d", 
                DESC(@"stickmapper-stick"), stickNumber + 1, DESC(@"stickmapper-axis"), thingNumber + 1];
        } else if (thingNumber >= MAX_REAL_BUTTONS) {
            NSString* dir[] = { DESC(@"stickmapper-hat-up"), DESC(@"stickmapper-hat-right"), DESC(@"stickmapper-hat-down"), DESC(@"stickmapper-hat-left") };
            desc = [NSString stringWithFormat:@"%@ %d %@ %d %@", 
                DESC(@"stickmapper-stick"), stickNumber + 1, DESC(@"stickmapper-hat"), (thingNumber - MAX_REAL_BUTTONS) / 4 + 1,
                dir[thingNumber & 3]];
        } else {
            desc = [NSString stringWithFormat:@"%@ %d %@ %d",
                DESC(@"stickmapper-stick"), stickNumber + 1, DESC(@"stickmapper-button"), thingNumber + 1];
        }
    }
    return desc;
}

- (std::string)hwToString:(int)hwFlags
{
    std::string hwString;
    switch (hwFlags) {
    case HW_AXIS:
        hwString = DESC(@"stickmapper-axis");
        break;
    case HW_BUTTON:
        hwString = DESC(@"stickmapper-button");
        break;
    default:
        hwString = DESC(@"stickmapper-axis-button");
    }
    return hwString;
}

// TODO: This data could be put into a plist (i18n or just modifiable by
// the user). It is otherwise an ugly method, but it'll do for testing.
- (std::vector<oo::PList>)stickFunctionList
{
    std::vector<oo::PList> funcList;

    // propulsion
    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-propulsion"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-roll"))
                     allowable:HW_AXIS
                        axisfn:AXIS_ROLL
                         butfn:STICK_NOFUNCTION]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-pitch"))
                     allowable:HW_AXIS
                        axisfn:AXIS_PITCH
                         butfn:STICK_NOFUNCTION]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-yaw"))
                     allowable:HW_AXIS
                        axisfn:AXIS_YAW
                         butfn:STICK_NOFUNCTION]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-increase-thrust"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_THRUST
                         butfn:BUTTON_INCTHRUST]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-decrease-thrust"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_THRUST
                         butfn:BUTTON_DECTHRUST]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-fuel-injection"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_FUELINJECT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-hyperspeed"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_HYPERSPEED]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-hyperdrive"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_HYPERDRIVE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gal-hyperdrive"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GALACTICDRIVE]);

    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-roll/pitch-precision-toggle"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_PRECISION]);

    // navigation
    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-navigation"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-compass-mode-next"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_COMPASSMODE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-compass-mode-prev"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_COMPASSMODE_PREV]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-scanner-zoom"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_SCANNERZOOM]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-scanner-unzoom"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_SCANNERUNZOOM]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-view-forward"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_VIEWY
                         butfn:BUTTON_VIEWFORWARD]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-view-aft"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_VIEWY
                         butfn:BUTTON_VIEWAFT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-view-port"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_VIEWX
                         butfn:BUTTON_VIEWPORT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-view-starboard"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_VIEWX
                         butfn:BUTTON_VIEWSTARBOARD]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-ext-view-cycle"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_EXTVIEWCYCLE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-toggle-ID"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ID]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-docking-clearance"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_DOCKINGCLEARANCE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-dockcpu"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_DOCKCPU]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-dockcpufast"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_DOCKCPUFAST]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-docking-music"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_DOCKINGMUSIC]);

    // offensive
    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-offensive"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-weapons-online-toggle"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_WEAPONSONLINETOGGLE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-primary-weapon"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_FIRE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-secondary-weapon"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_LAUNCHMISSILE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-arm-secondary"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ARMMISSILE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-disarm-secondary"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_UNARM]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-target-nearest-incoming-missile"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_TARGETINCOMINGMISSILE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-cycle-secondary"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_CYCLEMISSILE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-next-target"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_NEXTTARGET]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-previous-target"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_PREVTARGET]);

    // defensive
    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-defensive"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-ECM"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ECM]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-jettison"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_JETTISON]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-rotate-cargo"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ROTATECARGO]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-escape-pod"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ESCAPE]);

    // oxp special equip
    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-special-equip"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-mfd-select-next"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_MFDSELECTNEXT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-mfd-select-prev"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_MFDSELECTPREV]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-mfd-cycle-next"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_MFDCYCLENEXT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-mfd-cycle-prev"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_MFDCYCLEPREV]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-prime-equipment"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_PRIMEEQUIPMENT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-prime-prev-equipment"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_PRIMEEQUIPMENT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-activate-equipment"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ACTIVATEEQUIPMENT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-mode-equipment"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_MODEEQUIPMENT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-fastactivate-a"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_CLOAK]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-fastactivate-b"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_ENERGYBOMB]);

    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-gui"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-left"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUILEFT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-right"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUIRIGHT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-up"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUIUP]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-down"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUIDOWN]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-page-up"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUIPAGEUP]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-page-down"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUIPAGEDOWN]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-gui-select"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_GUISELECT]);

    // misc
    funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-misc"))]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-snapshot"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_SNAPSHOT]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-pause"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_PAUSE]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-toggle-hud"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_TOGGLEHUD]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-comms-log"))
                     allowable:HW_BUTTON
                        axisfn:STICK_NOFUNCTION
                         butfn:BUTTON_COMMSLOG]);
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-increase-field-of-view"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_FIELD_OF_VIEW
                         butfn:BUTTON_INC_FIELD_OF_VIEW]);
    funcList.push_back(
        [self makeStickGuiDict:oo::StdString(DESC(@"stickmapper-decrease-field-of-view"))
                     allowable:HW_AXIS | HW_BUTTON
                        axisfn:AXIS_FIELD_OF_VIEW
                         butfn:BUTTON_DEC_FIELD_OF_VIEW]);
#endif
    if ([customEquipActivation count] > 0) {
        funcList.push_back([self makeStickGuiDictHeader:oo::StdString(DESC(@"stickmapper-header-oxp-equip"))]);
        int i;
        for (i = 0; i < [customEquipActivation count]; i++) {
            [funcList addObject:
                    [self makeStickGuiDict:[NSString stringWithFormat:@"%@ '%@'", DESC(@"stickmapper-cust-activate"), oo::PListView([customEquipActivation objectAtIndex:i]).get<NSString*>(CUSTOMEQUIP_EQUIPNAME)]
                                 allowable:HW_BUTTON
                                    axisfn:STICK_NOFUNCTION
                                     butfn:(i + 10000)]];
            [funcList addObject:
                    [self makeStickGuiDict:[NSString stringWithFormat:@"%@ '%@'", DESC(@"stickmapper-cust-mode"), oo::PListView([customEquipActivation objectAtIndex:i]).get<NSString*>(CUSTOMEQUIP_EQUIPNAME)]
                                 allowable:HW_BUTTON
                                    axisfn:STICK_NOFUNCTION
                                     butfn:(i + 20000)]];
        }
    }
    return funcList;
}

- (oo::PList)makeStickGuiDict:(const std::string&)what
                    allowable:(int)allowable
                       axisfn:(int)axisfn
                        butfn:(int)butfn
{
    oo::PList::Dict guiDict;

    // -length / -substringToIndex: count UTF-16 units
    const std::u16string units = oo::utf8ToUtf16(what);
    guiDict[KEY_GUIDESC] = units.size() > 50 ? oo::utf16ToUtf8(units.substr(0, 28)) + "..." : what;
    guiDict[KEY_ALLOWABLE] = oo::PList::signedInteger(allowable); // +numberWithInt:
    if (axisfn >= 0)
        guiDict[KEY_AXISFN] = oo::PList::signedInteger(axisfn);
    if (butfn >= 0)
        guiDict[KEY_BUTTONFN] = oo::PList::signedInteger(butfn);
    return oo::PList(std::move(guiDict));
}

- (oo::PList)makeStickGuiDictHeader:(const std::string&)header
{
    oo::PList::Dict guiDict;
    guiDict[KEY_HEADER] = header;
    guiDict[KEY_ALLOWABLE] = "";
    guiDict[KEY_AXISFN] = "";
    guiDict[KEY_BUTTONFN] = "";
    return oo::PList(std::move(guiDict));
}

@end
