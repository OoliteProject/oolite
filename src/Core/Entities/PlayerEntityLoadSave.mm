/*

 PlayerEntityLoadSave.m

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

#import "PlayerEntityLoadSave.h"
#import "PlayerEntityContracts.h"
#import "PlayerEntityControls.h"
#import "PlayerEntitySound.h"

#import "GameController.h"
#import "OOColor.h"
#import "OOConstToString.h"
#import "OOJavaScriptEngine.h"
#import "OOJoystickManager.h"
#import "OOPListParsing.h"
#import "OOShipRegistry.h"
#import "OOSound.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "OOTexture.h"
#import "OOXMLExtensions.h"
#import "PlayerEntityControls.h"
#import "ProxyPlayerEntity.h"
#import "ResourceManager.h"
#import "ShipEntityAI.h"
#import "StationEntity.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/objc/OOException.h"

#import "OOPListGameTypes.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOAssert.h"
#include <algorithm>

// Name of modifier key used to issue commands. See also -isCommandModifierKeyDown.
#define COMMAND_MODIFIER_KEY "Ctrl"

namespace {

uint16_t PersonalityForCommanderDict(const oo::PList& dict);

// -oo_stringForKey:'s value without the Foundation type: a string as is, a number's
// -stringValue, anything else (or nothing) nullopt, as it gave nil.
std::optional<std::string> OptionalStringValue(const oo::PList* value)
{
    if (value == nullptr)
        return std::nullopt;
    if (const std::string* string = value->getIf<std::string>())
        return *string;
    if (value->isNumber())
        return oo::plist_get::numberStringValue(*value);
    return std::nullopt;
}

// [[key componentsSeparatedByString:@":"] oo_intAtIndex:1]: element 1's -intValue, 0 when there is
// none (or no key).
int SecondFieldIntValue(const std::optional<std::string>& key)
{
    if (!key)
        return 0;
    const std::vector<std::string> fields = oo::str::split(*key, ":");
    return fields.size() > 1 ? oo::str::intValue(fields[1]) : 0;
}

// %@ of a string that may be nil, in a runtime format.
oo::str::FormatArg TextArg(const std::optional<std::string>& string)
{
    return string ? oo::str::FormatArg(*string) : oo::str::FormatArg::null();
}

// A saved game's name on the load/save screens: -oo_stringForKey:@"player_save_name"
// defaultValue:[cdr oo_stringForKey:@"player_name"].
std::optional<std::string> CommanderSaveName(const oo::PList& cdr)
{
    std::optional<std::string> name = OptionalStringValue(cdr.find("player_save_name"));
    if (!name)
        name = OptionalStringValue(cdr.find("player_name"));
    return name;
}

// -stringByAppendingPathExtension:@"oolite-save": trailing separators ('/' and, as GNUstep on
// Windows, '\\') are dropped first.
std::string SaveFileName(const std::string& name)
{
    std::string result = name;
    while (!result.empty() && (result.back() == '/' || result.back() == '\\'))
        result.pop_back();
    return result + ".oolite-save";
}

// -characterAtIndex:0 & 0x00ff: the low byte of the first UTF-16 unit (-characterAtIndex: raised
// on an empty string; 0 here).
unsigned char FirstUnitLowByte(const std::string& string)
{
    const std::u16string units = oo::utf8ToUtf16(string);
    return units.empty() ? 0 : static_cast<unsigned char>(units[0] & 0x00ff);
}

} // namespace

@interface MyOpenGLView (OOLoadSaveExtensions)

- (BOOL)isCommandModifierKeyDown;

@end

@interface PlayerEntity (OOLoadSavePrivate)

- (void)setGuiToLoadCommanderScreen;
- (void)setGuiToSaveCommanderScreen:(const std::string&)cdrName;
- (void)setGuiToOverwriteScreen:(const std::string&)cdrName;
- (void)lsCommanders:(GuiDisplayGen*)gui directory:(const std::string&)directory pageNumber:(int)page highlightName:(const std::optional<std::string>&)highlightName;
- (void)showCommanderShip:(int)cdrArrayIndex;
- (int)findIndexOfCommander:(const std::string&)cdrName;
- (void)nativeSavePlayer:(const std::string&)cdrName;
- (BOOL)existingNativeSave:(const std::string&)cdrName;

- (void)writePlayerToPath:(const std::string&)path;

@end

@implementation PlayerEntity (LoadSave)

- (BOOL)loadPlayer
{
    BOOL OK = YES;

    [self setGuiToLoadCommanderScreen];
    return OK;
}

- (void)savePlayer
{
    [self setGuiToSaveCommanderScreen:[self cxx_lastsaveName].value_or("")];
}

- (void)autosavePlayer
{
    std::optional<std::string> tmp_path;
    std::optional<std::string> tmp_name;
    const std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");

    tmp_name = [self cxx_lastsaveName];
    tmp_path = _cxxPlayer->save_path;

    [self doScriptEvent:OOJSID("playerWillSaveGame") withArgument:@"AUTO_SAVE"];

    std::string saveName = [self cxx_lastsaveName].value_or("");
    const std::string autosaveSuffix = OO_DESC("autosave-commander-suffix");

    if (!oo::str::hasSuffix(saveName, autosaveSuffix)) {
        saveName += autosaveSuffix;
    }
    const std::string savePath = oo::str::appendingPathComponent(dir, saveName + ".oolite-save"); // a plain append, not the path-extension rule

    [self cxx_setLastsaveName:saveName];

    @try {
        [self writePlayerToPath:savePath];
    }
    @catch (id exception) {
        // Suppress exceptions silently. Warning the user about failed autosaves would be pretty unhelpful.
    }

    if (tmp_path.has_value()) {
        _cxxPlayer->save_path = *tmp_path;
    }
    [self cxx_setLastsaveName:tmp_name];
}

- (void)quicksavePlayer
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    std::optional<std::string> path;

    path = _cxxPlayer->save_path;
    if (!path)
        path = [[gameView gameController] cxx_playerFileToLoad];
    if (!path) {
        OO_LOG("quickSave.failed.noName", "{}", "ERROR no file name returned by [[gameView gameController] playerFileToLoad]");
        [OOException raise:"OoliteGameNotSavedException"
                    format:"ERROR no file name returned by [[gameView gameController] playerFileToLoad]"];
    }

    [self doScriptEvent:OOJSID("playerWillSaveGame") withArgument:@"QUICK_SAVE"];

    [self writePlayerToPath:*path];
    [[UNIVERSE gameView] suppressKeysUntilKeyUp];
    [self setGuiToStatusScreen];
}

- (void)setGuiToScenarioScreen:(int)page
{
    const oo::PList scenarios = [UNIVERSE cxx_scenarios];
    [UNIVERSE removeDemoShips];
    // GUI stuff
    {
        GuiDisplayGen* gui = [UNIVERSE gui];
        OOGUIRow start_row = GUI_ROW_SCENARIOS_START;
        OOGUIRow row = start_row;
        BOOL guiChanged = (_cxxPlayer->gui_screen != GUI_SCREEN_NEWGAME);

        [gui clearAndKeepBackground:!guiChanged];
        [gui cxx_setTitle:OO_DESC("oolite-newgame-title")];

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = -480;
        [gui setTabStops:tab_stops];

        unsigned n_rows = GUI_MAX_ROWS_SCENARIOS;
        NSUInteger i, count = scenarios.count();

        [gui cxx_setArray: { OO_DESC("oolite-scenario-exit"), " <----- " } forRow:start_row - 2];
        [gui setColor:[OOColor redColor] forRow:start_row - 2];
        [gui cxx_setKey:"exit" forRow:start_row - 2];

        if (page > 0) {
            [gui cxx_setArray: { OO_DESC("gui-back"), " <-- " } forRow:start_row - 1];
            [gui setColor:[OOColor greenColor] forRow:start_row - 1];
            [gui cxx_setKey:oo::str::format("__page:%i", page - 1) forRow:start_row - 1];
        }

        [self setShowDemoShips:NO];

        for (i = (NSUInteger)page * n_rows; i < count && row < start_row + n_rows; i++) {
            const oo::PList* scenario = scenarios.at(i);
            const std::optional<std::string> scenarioTitle = scenario != nullptr ? OptionalStringValue(scenario->find("name")) : std::nullopt;
            const std::string scenarioName = " " + scenarioTitle.value_or("(null)") + " "; // @" %@ "
            [gui cxx_setText:cxx_OOExpand(scenarioName).value_or(std::string()) forRow:row];
            [gui cxx_setKey:oo::str::format("Scenario:%zu", i) forRow:row];
            ++row;
        }

        if ((NSUInteger)(page + 1) * n_rows < count) {
            [gui cxx_setArray: { OO_DESC("gui-more"), " --> " } forRow:row];
            [gui setColor:[OOColor greenColor] forRow:row];
            [gui cxx_setKey:oo::str::format("__page:%i", page + 1) forRow:row];
            ++row;
        }

        _cxxPlayer->gui_screen = GUI_SCREEN_NEWGAME;

        [gui setSelectableRange:NSMakeRange(start_row - 2, 3 + row - start_row)];
        [gui setSelectedRow:start_row];
        [self showScenarioDetails];

        if (guiChanged) {
            [gui cxx_setBackgroundTextureKey:"newgame"];
            [gui cxx_setForegroundTextureKey:"newgame_overlay"];
        }
    }

    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)addScenarioModel:(const std::string&)shipKey
{
    [self cxx_showShipModelWithKey:shipKey shipData:oo::PList() personality:0 factorX:1.2 factorY:0.8 factorZ:6.4 inContext:"scenario"];
}

- (void)showScenarioDetails
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> key = [gui cxx_selectedRowKey];
    [UNIVERSE removeDemoShips];

    if (key && oo::str::hasPrefix(*key, "Scenario")) {
        int item = SecondFieldIntValue(key);
        const oo::PList scenarios = [UNIVERSE cxx_scenarios];
        const oo::PList* scenario = scenarios.at(item);
        [self setShowDemoShips:NO];
        for (NSUInteger i = GUI_ROW_SCENARIOS_DETAIL; i <= 27; i++) {
            [gui cxx_setText:"" forRow:i];
        }
        if (scenario) {
            const std::optional<std::string> scenarioDescription = OptionalStringValue(scenario->find("description"));
            const std::optional<std::string> expandedDescription = scenarioDescription.has_value() ? cxx_OOExpand(*scenarioDescription) : std::nullopt;
            [gui cxx_addLongText:expandedDescription startingAtRow:GUI_ROW_SCENARIOS_DETAIL align:GUI_ALIGN_LEFT];
            const std::optional<std::string> shipKey = OptionalStringValue(scenario->find("model"));
            if (shipKey) {
                [self addScenarioModel:*shipKey];
                [self setShowDemoShips:YES];
            }
        }
    }
}

- (BOOL)startScenario
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> key = [gui cxx_selectedRowKey];

    if (key == "exit") {
        // intended to return to main menu
        return NO;
    }
    if (key && oo::str::hasPrefix(*key, "__page")) {
        int page = SecondFieldIntValue(key);
        [self setGuiToScenarioScreen:page];
        return YES;
    }
    int selection = SecondFieldIntValue(key);

    const oo::PList scenarios = [UNIVERSE cxx_scenarios];
    const oo::PList* scenario = scenarios.at(selection);
    const std::optional<std::string> file = scenario != nullptr ? OptionalStringValue(scenario->find("file")) : std::nullopt;
    if (!file) {
        OO_LOG("scenario.init.error", "{}", "No file entry found for scenario");
        return NO;
    }
    const std::optional<std::string> path = [ResourceManager cxx_pathForFileNamed:*file inFolder:"Scenarios"];
    if (!path) {
        OO_LOG("scenario.init.error", "Game file not found for scenario {}", *file);
        return NO;
    }
    BOOL result = [self loadPlayerFromFile:*path asNew:YES];
    if (!result) {
        return NO;
    }
    _cxxPlayer->scenarioKey = OptionalStringValue(scenario->find("scenario"));

    // don't drop the save game directory in
    return YES;
}

- (std::optional<std::string>)commanderSelector
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    GuiDisplayGen* gui = [UNIVERSE gui];
    std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];

    int idx;
    if ([self handleGUIUpDownArrowKeys]) {
        int guiSelectedRow = [gui selectedRow];
        idx = (guiSelectedRow - STARTROW) + (_cxxPlayer->currentPage * NUMROWS);
        if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW && guiSelectedRow != EXITROW) {
            [self showCommanderShip:idx];
        } else {
            [UNIVERSE removeDemoShips];
            [gui cxx_setText:"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
            [gui cxx_setText:"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
            [gui cxx_setText:"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
        }

    } else {
        idx = ([gui selectedRow] - STARTROW) + (OOGUIRow)(_cxxPlayer->currentPage * NUMROWS);
    }

    // handle page <-- and page --> keys
    if (([self checkKeyPress:n_key_gui_arrow_left] || [self checkKeyPress:n_key_gui_page_up] || joyButtonState[BUTTON_GUILEFT] || joyButtonState[BUTTON_GUIPAGEUP]) && ([gui cxx_keyForRow:BACKROW] == GUI_KEY_OK)) {
        currentPage--;
        [self playMenuPagePrevious];
        [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }
    if (([self checkKeyPress:n_key_gui_arrow_right] || [self checkKeyPress:n_key_gui_page_down] || joyButtonState[BUTTON_GUIRIGHT] || joyButtonState[BUTTON_GUIPAGEDOWN]) && ([gui cxx_keyForRow:MOREROW] == GUI_KEY_OK)) {
        currentPage++;
        [self playMenuPageNext];
        [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }

    // Enter pressed - find the commander name underneath.
    // ignore Ctrl for the moment - we check for it explicitly later
    if ([self checkKeyPress:n_key_gui_select ignore_ctrl:YES] || [gameView isDown:gvMouseDoubleClick] || joyButtonState[BUTTON_GUISELECT]) {
        switch ([gui selectedRow]) {
        case EXITROW:
            if ([self status] == STATUS_START_GAME) {
                [self setGuiToIntroFirstGo:YES];
                return std::nullopt;
            }
            break;
        case BACKROW:
            _cxxPlayer->currentPage--;
            [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
            [gameView suppressKeysUntilKeyUp];
            break;
        case MOREROW:
            _cxxPlayer->currentPage++;
            [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
            [gameView suppressKeysUntilKeyUp];
            break;
        default: {
            if (idx < 0 || (std::size_t)idx >= _cxxPlayer->cdrDetailArray.size())
                break; // (-objectAtIndex: raised)
            const oo::PList cdr = _cxxPlayer->cdrDetailArray[idx];
            if (cdr.get<bool>("isSavedGame"))
                return OptionalStringValue(cdr.find("saved_game_path"));
            else {
                if ([gameView isCommandModifierKeyDown] || [gameView isDown:gvMouseDoubleClick]) {
                    // change directory to the selected path
                    const std::string newDir = cdr.get<std::string>("saved_game_path");
                    [[UNIVERSE gameController] cxx_setPlayerFileDirectory:newDir];
                    dir = newDir;
                    _cxxPlayer->currentPage = 0;
                    [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
                    [gameView suppressKeysUntilKeyUp];
                }
            }
        }
        }
    }

    if ([gameView isDown:27]) // escape key
    {
        [self setGuiToStatusScreen];
    }
    return std::nullopt;
}

- (void)saveCommanderInputHandler
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    GuiDisplayGen* gui = [UNIVERSE gui];
    std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];

    if ([self handleGUIUpDownArrowKeys]) {
        int guiSelectedRow = [gui selectedRow];
        int idx = (guiSelectedRow - STARTROW) + (_cxxPlayer->currentPage * NUMROWS);
        if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW) {
            [self showCommanderShip:idx];
            if (idx >= 0 && (std::size_t)idx < _cxxPlayer->cdrDetailArray.size() && _cxxPlayer->cdrDetailArray[idx].get<bool>("isSavedGame")) // don't show things that aren't saved games
                _cxxPlayer->commanderNameString = CommanderSaveName(_cxxPlayer->cdrDetailArray[idx]).value_or("");
            else
                _cxxPlayer->commanderNameString = [gameView cxx_typedString].value_or("");
        } else {
            [UNIVERSE removeDemoShips];
            [gui cxx_setText:"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
            [gui cxx_setText:"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
            [gui cxx_setText:"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
        }
    } else {
        _cxxPlayer->commanderNameString = [gameView cxx_typedString].value_or("");
    }

    [gameView cxx_setTypedString:_cxxPlayer->commanderNameString];

    [gui cxx_setText:
            oo::str::formatRuntime(OO_DESC("savescreen-commander-name-@"), { _cxxPlayer->commanderNameString })
              forRow:INPUTROW];
    [gui setColor:[OOColor cyanColor] forRow:INPUTROW];

    // handle page <-- and page --> keys, and on-screen buttons
    if (((([gameView isDown:gvMouseDoubleClick] || [self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT]) && [gui selectedRow] == BACKROW) || ([self checkKeyPress:n_key_gui_arrow_left] || [self checkKeyPress:n_key_gui_page_up]))
        && ([gui cxx_keyForRow:BACKROW] == GUI_KEY_OK)) {
        _cxxPlayer->currentPage--;
        [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }
    //
    if (((([gameView isDown:gvMouseDoubleClick] || [self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT]) && [gui selectedRow] == MOREROW) || ([self checkKeyPress:n_key_gui_arrow_right] || [self checkKeyPress:n_key_gui_page_down]))
        && ([gui cxx_keyForRow:MOREROW] == GUI_KEY_OK)) {
        _cxxPlayer->currentPage++;
        [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }

    // ignore Ctrl if pressed together with Enter for the moment - we check for it explicitly immediately after
    if (([self checkKeyPress:n_key_gui_select ignore_ctrl:YES] || [gameView isDown:gvMouseDoubleClick] || joyButtonState[BUTTON_GUISELECT]) && !commanderNameString.empty()) {
        if ([gameView isCommandModifierKeyDown] || [gameView isDown:gvMouseDoubleClick]) {
            int guiSelectedRow = [gui selectedRow];
            int idx = (guiSelectedRow - STARTROW) + (_cxxPlayer->currentPage * NUMROWS);
            const oo::PList cdr = (idx >= 0 && (std::size_t)idx < _cxxPlayer->cdrDetailArray.size()) ? _cxxPlayer->cdrDetailArray[idx] : oo::PList(); // (-objectAtIndex: raised)

            if (!cdr.isNull() && !cdr.get<bool>("isSavedGame")) // don't open saved games
            {
                // change directory to the selected path
                const std::string newDir = cdr.get<std::string>("saved_game_path");
                [[UNIVERSE gameController] cxx_setPlayerFileDirectory:newDir];
                dir = newDir;
                _cxxPlayer->currentPage = 0;
                [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];
                [gameView suppressKeysUntilKeyUp];
            }
        } else {
            _cxxPlayer->pollControls = YES;
            if ([self existingNativeSave:_cxxPlayer->commanderNameString]) {
                [gameView suppressKeysUntilKeyUp];
                [self setGuiToOverwriteScreen:_cxxPlayer->commanderNameString];
            } else {
                [self nativeSavePlayer:_cxxPlayer->commanderNameString];
                [[UNIVERSE gameView] suppressKeysUntilKeyUp];
                [self setGuiToStatusScreen];
            }
        }
    }

    if ([gameView isDown:27]) // escape key
    {
        // get out of here
        _cxxPlayer->pollControls = YES;
        [[UNIVERSE gameView] resetTypedString];
        [self setGuiToStatusScreen];
    }
}

- (void)overwriteCommanderInputHandler
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    GuiDisplayGen* gui = [UNIVERSE gui];
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];

    [self handleGUIUpDownArrowKeys];

    // Translation issue: we can't confidently use raw Y and N ascii as shortcuts. It's better to use the load-previous-commander keys.
    const std::string valueYes = oo::str::lowercase(OptionalStringValue([UNIVERSE cxx_descriptions]->find("load-previous-commander-yes")).value_or("y"));
    const std::string valueNo = oo::str::lowercase(OptionalStringValue([UNIVERSE cxx_descriptions]->find("load-previous-commander-no")).value_or("n"));
    unsigned char cYes, cNo;

    cYes = FirstUnitLowByte(valueYes); // Use lower byte of unichar.
    cNo = FirstUnitLowByte(valueNo); // Use lower byte of unichar.

    if ((([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT]) && ([gui selectedRow] == SAVE_OVERWRITE_YES_ROW)) || [gameView isDown:cYes] || [gameView isDown:cYes - 32]) {
        pollControls = YES;
        [self nativeSavePlayer:commanderNameString];
        [self playSaveOverwriteYes];
        [[UNIVERSE gameView] suppressKeysUntilKeyUp];
        [self setGuiToStatusScreen];
    }

    if ((([self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT]) && ([gui selectedRow] == SAVE_OVERWRITE_NO_ROW)) || [gameView isDown:27] || [gameView isDown:cNo] || [gameView isDown:cNo - 32]) {
        // esc or NO was pressed - get out of here
        _cxxPlayer->pollControls = YES;
        [self playSaveOverwriteNo];
        [self setGuiToSaveCommanderScreen:""];
    }
}

- (BOOL)loadPlayerFromFile:(const std::string&)fileToOpen asNew:(BOOL)asNew
{
    /*	TODO: it would probably be better to load by creating a new
            PlayerEntity, verifying that's OK, then replacing the global player.

            Actually, it'd be better to separate PlayerEntity into OOPlayer and
            OOPlayerShipEntity. And then move most of OOPlayerShipEntity into
            ShipEntity, and make NPC ships behave more like player ships.
            -- Ahruman
    */

    BOOL loadedOK = YES;
    oo::PList fileDic;
    std::optional<std::string> fail_reason;

    if (fileToOpen.empty()) // (was a nil test: every caller passes a non-nil path)
    {
        fail_reason = OO_DESC("loadfailed-no-file-specified");
        loadedOK = NO;
    }

    if (loadedOK) {
        OO_LOG("load.progress", "{}", "Reading file");
        fileDic = cxx_OOPropertyListFromFile(fileToOpen);
        if (!fileDic.isDict())
            fileDic = oo::PList(); // a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
        if (!fileDic.isDict()) {
            fail_reason = OO_DESC("loadfailed-could-not-load-file");
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OO_LOG("load.progress", "{}", "Restricting scenario");
        std::string scenarioRestrict;
        const std::optional<std::string> savedRestrict = OptionalStringValue(fileDic.find("scenario_restriction"));
        if (savedRestrict) {
            scenarioRestrict = *savedRestrict;
        } else {
            // older save game - use the 'strict' key instead
            BOOL strict = fileDic.get<bool>("strict", NO);
            if (strict) {
                scenarioRestrict = std::string(SCENARIO_OXP_DEFINITION_NONE);
            } else {
                scenarioRestrict = std::string(SCENARIO_OXP_DEFINITION_ALL);
            }
        }

        if (![UNIVERSE cxx_setUseAddOns:scenarioRestrict fromSaveGame:YES forceReinit:YES]) {
            fail_reason = OO_DESC("loadfailed-saved-game-failed-to-load");
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OO_LOG("load.progress", "{}", "Creating player ship");
        // Check that player ship exists
        const std::optional<std::string> shipKey = OptionalStringValue(fileDic.find("ship_desc"));
        oo::PList shipDict;

        if (shipKey)
            shipDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:*shipKey];

        if (shipDict.isNull()) {
            loadedOK = NO;
            if (shipKey)
                fail_reason = oo::str::formatRuntime(OO_DESC("loadfailed-could-not-find-ship-type-@-please-reinstall-the-appropriate-OXP"), { *shipKey });
            else
                fail_reason = OO_DESC("loadfailed-invalid-saved-game-no-ship-specified");
        }
    }

    if (loadedOK) {
        OO_LOG("load.progress", "{}", "Initialising player entity");
        if (![self setUpAndConfirmOK:YES saveGame:YES]) {
            fail_reason = OO_DESC("loadfailed-could-not-reset-javascript");
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OO_LOG("load.progress", "{}", "Loading commander data");
        if (![self cxx_setCommanderDataFromDictionary:fileDic]) {
            // this could still be a reset js issue, if switching from strict / unrestricted
            // TODO: use "could not reset js message" if that's the case.
            fail_reason = OO_DESC("loadfailed-could-not-set-up-player-ship");
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OO_LOG("load.progress", "{}", "Recording save path");
        if (!asNew) {
            _cxxPlayer->save_path = fileToOpen;

            [[[UNIVERSE gameView] gameController] cxx_setPlayerFileToLoad:fileToOpen];
            [[[UNIVERSE gameView] gameController] cxx_setPlayerFileDirectory:fileToOpen];
        }
    } else {
        OO_LOG("load.failed", "***** Failed to load saved game \"{}\": {}", oo::str::lastPathComponent(fileToOpen), fail_reason.value_or("unknown error"));
        [[UNIVERSE gameController] cxx_setPlayerFileToLoad:""];
        [UNIVERSE handleGameOver];
        [UNIVERSE clearPreviousMessage];
        [UNIVERSE cxx_addMessage:OO_DESC("loadfailed-saved-game-failed-to-load") forCount:9.0];
        if (fail_reason)
            [UNIVERSE cxx_addMessage:*fail_reason forCount:9.0];
        return NO;
    }

    OO_LOG("load.progress", "{}", "Creating system");
    [UNIVERSE setTimeAccelerationFactor:TIME_ACCELERATION_FACTOR_DEFAULT];
    [UNIVERSE setSystemTo:_cxxPlayer->system_id];
    [UNIVERSE removeAllEntitiesExceptPlayer];
    [UNIVERSE setGalaxyTo:_cxxPlayer->galaxy_number andReinit:YES]; // set overridden planet names on long range map
    [UNIVERSE setUpSpace];
    [UNIVERSE setAutoSaveNow:NO];

    OO_LOG("load.progress", "{}", "Resetting player flight variables");
    [self setDockedAtMainStation];
    StationEntity* dockedStation = [self dockedStation];

    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    if (dockedStation) {
        _cxxEntity->position = [dockedStation position];
        [self setOrientation:kIdentityQuaternion];
        _cxxShip->v_forward = vector_forward_from_quaternion(_cxxEntity->orientation);
        _cxxShip->v_right = vector_right_from_quaternion(_cxxEntity->orientation);
        _cxxShip->v_up = vector_up_from_quaternion(_cxxEntity->orientation);
    }

    _cxxShip->flightRoll = 0.0;
    _cxxShip->flightPitch = 0.0;
    _cxxShip->flightYaw = 0.0;
    _cxxShip->flightSpeed = 0.0;

    [self setEntityPersonalityInt:PersonalityForCommanderDict(fileDic)];

    OO_LOG("load.progress", "{}", "Loading system market");
    // dockedStation is always the main station at this point;
    // "localMarket" save key always refers to the main station (system) market
    const oo::PList* market = fileDic.get<oo::PList::Array>("localMarket");
    if (market != nullptr) {
        [dockedStation cxx_setLocalMarket:*market];
    } else {
        [dockedStation initialiseLocalMarket];
    }

    [self calculateCurrentCargo];

    OO_LOG("load.progress", "{}", "Setting scenario key");
    // set scenario key if the scenario allows saving and has one
    const std::optional<std::string> scenario = OptionalStringValue(fileDic.find("scenario_key"));
    _cxxPlayer->scenarioKey.reset();
    if (scenario) {
        _cxxPlayer->scenarioKey = *scenario;
    }

    OO_LOG("load.progress", "{}", "Starting JS engine");
    // Remember the savegame target, run js startUp.
    [self completeSetUpAndSetTarget:NO];
    // run initial system population
    OO_LOG("load.progress", "{}", "Populating initial system");
    [UNIVERSE populateNormalSpace];

    // might as well start off with a collected JS environment
    [[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];

    // read saved position vector and primary role, check for an
    // appropriate station at those coordinates, if found, switch
    // docked station to that one.
    const oo::PList* dockedPosNode = fileDic.find("docked_station_position");
    HPVector dockedPos = OOHPVectorFromPList(dockedPosNode, kZeroHPVector);
    const std::string dockedRole = OptionalStringValue(fileDic.find("docked_station_role")).value_or("");
    StationEntity* saveStation = [UNIVERSE cxx_stationWithRole:dockedRole andPosition:dockedPos];
    if (saveStation != nil && [saveStation allowsSaving]) {
        [self setDockedStation:saveStation];
        _cxxEntity->position = [saveStation position];
    }
    // and initialise markets for the secondary stations
    const oo::PList* stationMarkets = fileDic.get<oo::PList::Array>("station_markets");
    [UNIVERSE cxx_loadStationMarkets:stationMarkets != nullptr ? *stationMarkets : oo::PList()];

    OO_LOG("load.progress", "{}", "Completing JS startup");
    [self startUpComplete];

    // if the file was specified in the command line at startup, DO NOT suppress the keys!
    if ([[UNIVERSE gameController] finishedLaunching])
        [[UNIVERSE gameView] suppressKeysUntilKeyUp];
    if (asNew) {
        _cxxPlayer->gui_screen = GUI_SCREEN_NEWGAME;
    } else {
        _cxxPlayer->gui_screen = GUI_SCREEN_LOAD; // force evaluation of new gui screen on startup
    }
    [self setGuiToStatusScreen];
    if (loadedOK)
        [self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")]; // trigger missionScreenOpportunity immediately after loading
    OO_LOG("load.progress", "{}", "Loading complete");
    return loadedOK;
}

@end

@implementation PlayerEntity (OOLoadSavePrivate)

- (void)writePlayerToPath:(const std::string&)path
{
    std::string errDesc;
    BOOL didSave = NO;
    [[UNIVERSE gameView] resetTypedString];

    if (path.empty()) {
        OO_LOG("save.failed", "***** SAVE ERROR: {} called with nil path.", __PRETTY_FUNCTION__);
        return;
    }

    // The save dictionary as a property list, converted once (its float values stay single reals,
    // written %0.7g as before).
    const oo::PList dict = [self cxx_commanderDataDictionary];
    if (dict.isNull())
        errDesc = "could not construct commander data dictionary.";
    else {
        didSave = OOWriteXMLPListToFile(dict, path, &errDesc);
    }
    if (didSave) {
        [UNIVERSE clearPreviousMessage]; // allow this to be given time and again
        [UNIVERSE cxx_addMessage:OO_DESC("game-saved") forCount:2];
        _cxxPlayer->save_path = path;
        [[UNIVERSE gameController] cxx_setPlayerFileToLoad:*_cxxPlayer->save_path];
        [[UNIVERSE gameController] cxx_setPlayerFileDirectory:*_cxxPlayer->save_path];
        // no duplicated autosave immediately after a save.
        [UNIVERSE setAutoSaveNow:NO];
    } else {
        OO_LOG("save.failed", "***** SAVE ERROR: {}", errDesc);
        [OOException raise:"OoliteException"
                    format:"Attempt to save game to file '%s' failed: %s", path.c_str(), errDesc.c_str()];
    }
    [[UNIVERSE gameView] suppressKeysUntilKeyUp];
    [self setGuiToStatusScreen];
}

- (void)nativeSavePlayer:(const std::string&)cdrName
{
    const std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");
    const std::string savePath = oo::str::appendingPathComponent(dir, SaveFileName(cdrName));

    [self doScriptEvent:OOJSID("playerWillSaveGame") withArgument:@"STANDARD_SAVE"];

    [self cxx_setLastsaveName:cdrName];

    [self writePlayerToPath:savePath];
}

- (void)setGuiToLoadCommanderScreen
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");

    _cxxPlayer->gui_screen = GUI_SCREEN_LOAD;

    [gui clear];
    [gui cxx_setTitle:OO_DESC("loadscreen-title")];

    _cxxPlayer->currentPage = 0;
    [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];

    [gui cxx_setForegroundTextureKey:"docked_overlay"];
    [gui cxx_setBackgroundTextureKey:"load_save"];

    [[UNIVERSE gameView] suppressKeysUntilKeyUp];

    [self setShowDemoShips:YES];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)setGuiToSaveCommanderScreen:(const std::string&)cdrName
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    MyOpenGLView* gameView = [UNIVERSE gameView];
    const std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");

    _cxxPlayer->pollControls = NO;
    _cxxPlayer->gui_screen = GUI_SCREEN_SAVE;

    [gui clear];
    [gui cxx_setTitle:OO_DESC("savescreen-title")];

    _cxxPlayer->currentPage = 0;
    [self lsCommanders:gui directory:dir pageNumber:_cxxPlayer->currentPage highlightName:std::nullopt];

    [gui cxx_setText:OO_DESC("savescreen-commander-name") forRow:INPUTROW];
    [gui setColor:[OOColor cyanColor] forRow:INPUTROW];
    [gui setShowTextCursor:YES];
    [gui setCurrentRow:INPUTROW];

    [gui cxx_setForegroundTextureKey:"docked_overlay"];
    [gui cxx_setBackgroundTextureKey:"load_save"];

    [gameView cxx_setTypedString:cdrName];
    [gameView suppressKeysUntilKeyUp];

    [self setShowDemoShips:YES];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)setGuiToOverwriteScreen:(const std::string&)cdrName
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    MyOpenGLView* gameView = [UNIVERSE gameView];

    // Don't poll controls
    _cxxPlayer->pollControls = NO;

    _cxxPlayer->gui_screen = GUI_SCREEN_SAVE_OVERWRITE;

    [gui clear];
    [gui cxx_setTitle:oo::str::formatRuntime(OO_DESC("overwrite-save-commander-@"), { cdrName })];

    [gui cxx_setText:oo::str::formatRuntime(OO_DESC("overwritescreen-commander-@-already-exists-overwrite-query"), { cdrName })
              forRow:SAVE_OVERWRITE_WARN_ROW
               align:GUI_ALIGN_CENTER];

    [gui cxx_setText:OO_DESC("overwritescreen-yes") forRow:SAVE_OVERWRITE_YES_ROW align:GUI_ALIGN_CENTER];
    [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:SAVE_OVERWRITE_YES_ROW];

    [gui cxx_setText:OO_DESC("overwritescreen-no") forRow:SAVE_OVERWRITE_NO_ROW align:GUI_ALIGN_CENTER];
    [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:SAVE_OVERWRITE_NO_ROW];

    [gui setSelectableRange:NSMakeRange(SAVE_OVERWRITE_YES_ROW, 2)];
    [gui setSelectedRow:SAVE_OVERWRITE_NO_ROW];

    // We can only leave this screen by answering yes or no, or esc. Therefore
    // use a specific overlay, to allow visual reminders of the available options.
    [gui cxx_setForegroundTextureKey:"overwrite_overlay"];
    [gui cxx_setBackgroundTextureKey:"load_save"];

    [self setShowDemoShips:NO];
    [gameView setStringInput:gvStringInputNo];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO]; // FIXME: should be YES, but was NO before introducing new mouse mode stuff. If set to YES, choices can be selected but not activated.
}

- (void)lsCommanders:(GuiDisplayGen*)gui
           directory:(const std::string&)directory
          pageNumber:(int)page
       highlightName:(const std::optional<std::string>&)highlightName
{
    int rangeStart = STARTROW;
    unsigned lastIndex;
    unsigned i;
    int row = STARTROW;

    // Commander listing from the save directory's entries as full paths. The old per-entry filter
    // tested `!exists && isDirectory`, which never holds, so it only built the paths.
    std::vector<std::string> cdrArray;
    const oo::fs::Path directoryPath = oo::fs::pathFromUTF8(directory);
    if (oo::fs::fileType(directoryPath) == oo::fs::FileType::directory) {
        const auto names = oo::fs::directoryContents(directoryPath);
        if (names) {
            for (const std::string& entry : *names)
                cdrArray.push_back(oo::str::appendingPathComponent(directory, entry));
        }
    } else {
        OO_LOG_ERR("savedGame.read.fail.fileNotFound", "File at path '{}' could not be found.", directory);
    }

    // get commander details so a brief rundown of the commander's details may
    // be displayed.
    _cxxPlayer->cdrDetailArray.clear();

    _cxxPlayer->cdrDetailArray.push_back(oo::PList(oo::PList::Dict {
        { "isParentFolder", oo::PList("YES") },
        { "saved_game_path", oo::PList(oo::str::deletingLastPathComponent(directory)) } }));

    for (const std::string& path : cdrArray) {
        const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(path));

        if (type != oo::fs::FileType::none) {
            if (type != oo::fs::FileType::directory && oo::str::lowercase(oo::str::pathExtension(path)) == "oolite-save") {
                oo::PList cdr = cxx_OOPropertyListFromFile(path);
                if (!cdr.isDict())
                    cdr = oo::PList(); // a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
                if (oo::PList::Dict* cdr1 = cdr.getIf<oo::PList::Dict>()) {
                    // okay use the same dictionary but add a 'saved_game_path' attribute
                    (*cdr1)["isSavedGame"] = oo::PList("YES");
                    (*cdr1)["saved_game_path"] = oo::PList(path);
                    _cxxPlayer->cdrDetailArray.push_back(std::move(cdr));
                }
            }
            if (type == oo::fs::FileType::directory && !oo::str::hasPrefix(oo::str::lastPathComponent(path), ".")) {
                _cxxPlayer->cdrDetailArray.push_back(oo::PList(oo::PList::Dict {
                    { "isFolder", oo::PList("YES") },
                    { "saved_game_path", oo::PList(path) } }));
            }
        }
    }

    if (_cxxPlayer->cdrDetailArray.empty()) {
        // Empty directory; tell the user and exit immediately.
        [gui cxx_setText:OO_DESC("loadsavescreen-no-commanders-found") forRow:STARTROW align:GUI_ALIGN_CENTER];
        return;
    }

    // sortCommanders: saved_game_path in the locale collation (oo::str::localizedCompare, ICU, as GNUstep sorted it).
    std::stable_sort(_cxxPlayer->cdrDetailArray.begin(), _cxxPlayer->cdrDetailArray.end(), [](const oo::PList& cdr1, const oo::PList& cdr2) {
        return oo::str::localizedCompare(cdr1.get<std::string>("saved_game_path"), cdr2.get<std::string>("saved_game_path")) < 0;
    });

    // Do we need to highlight a name?
    int highlightRowOnPage = STARTROW;
    int highlightIdx = 0;
    if (highlightName) {
        highlightIdx = [self findIndexOfCommander:*highlightName];
        if (highlightIdx < 0) {
            OO_LOG("save.list.commanders.commanderNotFound", "Commander {} doesn't exist, very bad", *highlightName);
            highlightIdx = 0;
        }

        // figure out what page we need to be on
        page = highlightIdx / NUMROWS;
        highlightRowOnPage = highlightIdx % NUMROWS + STARTROW;
    }

    // We now know for certain what page we're on -
    // set the first index of the first commander on this page.
    unsigned firstIndex = page * NUMROWS;

    // Set up the GUI.
    OOGUITabSettings tabStop;
    tabStop[0] = 0;
    tabStop[1] = 160;
    tabStop[2] = 270;
    [gui setTabStops:tabStop];

    // clear text lines here
    for (i = EXITROW; i < ENDROW + 1; i++) {
        [gui cxx_setText:"" forRow:i align:GUI_ALIGN_LEFT];
        [gui setColor:[OOColor yellowColor] forRow:i];
        [gui cxx_setKey:std::string(GUI_KEY_SKIP) forRow:i];
    }

    [gui setColor:[OOColor greenColor] forRow:LABELROW];
    [gui cxx_setArray:{ OO_DESC("loadsavescreen-commander-name"), OO_DESC("loadsavescreen-rating") }
               forRow:LABELROW];

    if (page) {
        [gui setColor:[OOColor greenColor] forRow:STARTROW - 1];
        [gui cxx_setArray:{ OO_DESC("gui-back"), " <-- " }
                   forRow:STARTROW - 1];
        [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:STARTROW - 1];
        rangeStart = STARTROW - 1;
    }

    if ([self status] == STATUS_START_GAME) {
        [gui cxx_setArray:{ OO_DESC("oolite-loadsave-exit"), " <----- " } forRow:EXITROW];
        [gui setColor:[OOColor redColor] forRow:EXITROW];
        [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:EXITROW];
        rangeStart = EXITROW;
    }

    if (firstIndex + NUMROWS >= _cxxPlayer->cdrDetailArray.size()) {
        lastIndex = _cxxPlayer->cdrDetailArray.size();
        [gui setSelectableRange:NSMakeRange(rangeStart, rangeStart + NUMROWS + 2)];
    } else {
        lastIndex = (page * NUMROWS) + NUMROWS;
        [gui setColor:[OOColor greenColor] forRow:ENDROW];
        [gui cxx_setArray:{ OO_DESC("gui-more"), " --> " }
                   forRow:ENDROW];
        [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:ENDROW];
        [gui setSelectableRange:NSMakeRange(rangeStart, MOREROW)];
    }

    const std::optional<std::string> lastsaveName = [self cxx_lastsaveName];
    for (i = firstIndex; i < lastIndex; i++) {
        const oo::PList& cdr = _cxxPlayer->cdrDetailArray[i];
        if (cdr.get<bool>("isSavedGame")) {
            const std::string ratingDesc = cxx_OODisplayRatingStringFromKillCount(cdr.get<unsigned int>("ship_kills")).value_or("(null)");
            const std::optional<std::string> saveName = CommanderSaveName(cdr);
            [gui cxx_setArray:{
                                  " " + saveName.value_or("(null)") + " ", // @" %@ "
                                  " " + ratingDesc + " " }
                       forRow:row];
            if (lastsaveName && saveName && *lastsaveName == *saveName) {
                highlightRowOnPage = row;
            }

            [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:row];
            row++;
        }
        if (cdr.get<bool>("isParentFolder")) {
            [gui cxx_setArray:{
                                  " (..) " + oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) + " ",
                                  "" }
                       forRow:row];
            [gui setColor:[OOColor orangeColor] forRow:row];
            [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:row];
            row++;
        }
        if (cdr.get<bool>("isFolder")) {
            [gui cxx_setArray:{
                                  " >> " + oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) + " ",
                                  "" }
                       forRow:row];
            [gui setColor:[OOColor orangeColor] forRow:row];
            [gui cxx_setKey:std::string(GUI_KEY_OK) forRow:row];
            row++;
        }
    }
    [gui setSelectedRow:highlightRowOnPage];
    highlightIdx = (highlightRowOnPage - STARTROW) + (_cxxPlayer->currentPage * NUMROWS);
    // show the first ship, this will be the selected row
    [self showCommanderShip:highlightIdx];
}

// check for an existing saved game...
- (BOOL)existingNativeSave:(const std::string&)cdrName
{
    const std::string dir = [[UNIVERSE gameController] cxx_playerFileDirectory].value_or("");

    const std::string savePath = oo::str::appendingPathComponent(dir, SaveFileName(cdrName));
    return oo::fs::fileExists(oo::fs::pathFromUTF8(savePath));
}

// Get some brief details about the commander file.
- (void)showCommanderShip:(int)cdrArrayIndex
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    [UNIVERSE removeDemoShips];
    if (cdrArrayIndex < 0 || (std::size_t)cdrArrayIndex >= _cxxPlayer->cdrDetailArray.size())
        return; // (-objectAtIndex: raised)
    const oo::PList cdr = _cxxPlayer->cdrDetailArray[cdrArrayIndex];

    [gui cxx_setText:"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
    [gui cxx_setText:"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
    [gui cxx_setText:"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];

    if (cdr.get<bool>("isFolder")) {
        const std::string folderDesc = oo::str::formatRuntime(OO_DESC("loadsavescreen-hold-@-and-press-return-to-open-folder-@"), { COMMAND_MODIFIER_KEY, oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) });
        [gui setColor:[OOColor orangeColor] forRow:CDRDESCROW];
        [gui cxx_addLongText:folderDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];
        return;
    }

    if (cdr.get<bool>("isParentFolder")) {
        const std::string folderDesc = oo::str::formatRuntime(OO_DESC("loadsavescreen-hold-@-and-press-return-to-open-parent-folder-@"), { COMMAND_MODIFIER_KEY, oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) });
        [gui setColor:[OOColor orangeColor] forRow:CDRDESCROW];
        [gui cxx_addLongText:folderDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];
        return;
    }
    [gui setColor:[gui cxx_colorFromSetting:std::nullopt defaultValue:nil] forRow:CDRDESCROW];

    if (!cdr.get<bool>("isSavedGame"))
        return; // don't show things that aren't saved games

    if ([self dockedStation] == nil)
        [self setDockedAtMainStation];

    // Display the commander's ship.
    const std::optional<std::string> shipDesc = OptionalStringValue(cdr.find("ship_desc"));
    std::optional<std::string> shipName;
    oo::PList shipDict;
    std::string rating;
    uint16_t personality = PersonalityForCommanderDict(cdr);

    if (shipDesc)
        shipDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:*shipDesc];
    if (!shipDict.isNull()) {
        oo::PList dict = shipDict;
        const oo::PList* subEntStatus = cdr.find("subentities_status");
        // don't add it to the dictionary if there's no subentities_status key
        if (subEntStatus != nullptr && dict.isDict())
            (*dict.getIf<oo::PList::Dict>())["subentities_status"] = *subEntStatus;
        [self cxx_showShipyardModel:*shipDesc shipData:dict personality:personality];
        shipName = OptionalStringValue(shipDict.find("display_name"));
        if (!shipName)
            shipName = OptionalStringValue(shipDict.find("name")); // KEY_NAME
    } else {
        [self cxx_showShipyardModel:"oolite-unknown-ship" shipData:oo::PList() personality:personality];
        shipName = OptionalStringValue(cdr.find("ship_name")).value_or("unknown");
        if ([UNIVERSE cxx_useAddOns] != std::string(SCENARIO_OXP_DEFINITION_ALL)) // nil was not equal either
        {
            *shipName += " - OXPs disabled or not installed";
        } else {
            *shipName += " - OXP not installed";
        }
    }

    // Make a short description of the commander
    const std::string legalDesc = cxx_OODisplayStringFromLegalStatus(cdr.get<int>("legal_status")).value_or("(null)");

    rating = cxx_KillCountToRatingAndKillString(cdr.get<unsigned int>("ship_kills"));
    const oo::PList* creditsNode = cdr.find("credits");
    OOCreditsQuantity money = OODeciCreditsFromPList(creditsNode);

    // Nikos - Add some more information in the load game screen (current location, galaxy number and timestamp).
    //-------------------------------------------------------------------------------------------------------------------------

    int galNumber;
    std::string timeStamp;
    // If there is no key containing the name of the current system in
    // the savefile, calculating what it should have been is going to
    // be tricky now that system generation isn't seed based - but
    // this implies a save game well over 5 years old.
    // Leaving the location blank in this case is probably okay
    const std::string locationName = OptionalStringValue(cdr.find("current_system_name")).value_or("");

    galNumber = cdr.get<int>("galaxy_number") + 1; // Galaxy numbering starts at 0.

    // %c of a government / economy value 0..23 gives that one UTF-16 unit, U+0000 included (pinned
    // against gnustep-base's -stringWithFormat:, bead oo-3rb.176); oo::str::format keeps the NUL byte.
    std::string locationGov;
    std::string locationEco;
    std::string locationTL;
    if (cdr.find("current_system_techlevel") != nullptr) {
        locationTL = oo::str::format("%u", cdr.get<unsigned int>("current_system_techlevel") + 1);
        locationGov = oo::str::format("%c", cdr.get<unsigned char>("current_system_government"));
        locationEco = oo::str::format(" %c", (7 - cdr.get<unsigned char>("current_system_economy")) + 16);
    }

    timeStamp = cxx_ClockToString(cdr.get<double>("ship_clock", PLAYER_SHIP_CLOCK_START), NO);

    //-------------------------------------------------------------------------------------------------------------------------

    const std::string cdrDesc = oo::str::formatRuntime(OO_DESC("loadsavescreen-commander-@-rated-@-has-@-legal-status-@-ship-@-location-@-g-@-eco-@-gov-@-tl-@-timestamp-@"),
        { TextArg(OptionalStringValue(cdr.find("player_name"))),
            rating,
            cxx_OOCredits(money),
            legalDesc,
            TextArg(shipName),
            locationName,
            galNumber,
            locationEco,
            locationGov,
            locationTL,
            timeStamp });

    //-------------------------------------------------------------------------------------------------------------------------

    [gui cxx_addLongText:cdrDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];
}

- (int)findIndexOfCommander:(const std::string&)cdrName
{
    unsigned i;
    for (i = 0; i < _cxxPlayer->cdrDetailArray.size(); i++) {
        const std::optional<std::string> currentName = CommanderSaveName(_cxxPlayer->cdrDetailArray[i]);
        if (currentName && cdrName == *currentName) // -compare: == OOOrderedSame
        {
            return i;
        }
    }

    // not found!
    return -1;
}

@end

@implementation MyOpenGLView (OOLoadSaveExtensions)

- (BOOL)isCommandModifierKeyDown
{
    return [self isCtrlDown];
}

@end

namespace {

uint16_t PersonalityForCommanderDict(const oo::PList& dict)
{
    uint16_t personality = dict.get<unsigned short>("entity_personality", ENTITY_PERSONALITY_INVALID);

    if (personality == ENTITY_PERSONALITY_INVALID) {
        // For pre-1.74 saved games, generate a default personality based on some hashes.
        // (ooHash of a missing string was a message to nil: 0.)
        const std::optional<std::string> shipDesc = OptionalStringValue(dict.find("ship_desc"));
        const std::optional<std::string> playerName = OptionalStringValue(dict.find("player_name"));
        personality = (shipDesc ? oo::str::ooHash(*shipDesc) : 0) * (playerName ? oo::str::ooHash(*playerName) : 0);
    }

    return personality & ENTITY_PERSONALITY_MAX;
}

} // namespace

OOCreditsQuantity OODeciCreditsFromDouble(double doubleDeciCredits)
{
    /*	Clamp value to 0..kOOMaxCredits.
            The important bit here is that kOOMaxCredits can't be represented
            exactly as a double, and casting it rounds it up; casting this value
            back to an OOCreditsQuantity truncates it. Comparing value directly to
            kOOMaxCredits promotes kOOMaxCredits to a double, giving us this
            problem.
            nextafter(kOOMaxCredits, -1) gives us the highest non-truncated
            credits value that's representable as a double (namely,
            18 446 744 073 709 549 568 decicredits, or 2047 less than kOOMaxCredits).
            -- Ahruman 2011-02-27
    */
    if (doubleDeciCredits > 0) {
        doubleDeciCredits = round(doubleDeciCredits);
        double threshold = nextafter(kOOMaxCredits, -1);

        if (doubleDeciCredits <= threshold) {
            return doubleDeciCredits;
        } else {
            return kOOMaxCredits;
        }
    } else {
        return 0;
    }
}

OOCreditsQuantity OODeciCreditsFromPList(const oo::PList* value)
{
    if (value != nullptr && value->isReal()) // a real (was a float/double NSNumber, objCType f or d)
    {
        double d = value->doubleValue();
        if (value->isSinglePrecision())
            d = static_cast<double>(static_cast<float>(d)); // +numberWithFloat: -doubleValue
        return OODeciCreditsFromDouble(d);
    } else {
        return oo::plist_get::unsignedLongLongFrom(value, 0); // the reader OOUnsignedLongLongFromObject forwards to
    }
}
