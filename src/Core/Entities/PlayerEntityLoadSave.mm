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
#import "OOFoundationBridge.h"
#import "OOJavaScriptEngine.h"
#import "OOJoystickManager.h"
#import "OOPListParsing.h"
#import "OOPListView.h"
#import "OOShipRegistry.h"
#import "OOSound.h"
#import "OOStringBridge.h"
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

std::optional<std::string> OptionalStringValue(id object)
{
    const oo::PList value = oo::PListFrom(object);
    return OptionalStringValue(&value);
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
    [self setGuiToSaveCommanderScreen:oo::StdString([self lastsaveName])];
}

- (void)autosavePlayer
{
    std::optional<std::string> tmp_path;
    std::optional<std::string> tmp_name;
    const std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);

    tmp_name = oo::OptionalString([self lastsaveName]);
    tmp_path = oo::OptionalString(save_path);

    [self doScriptEvent:OOJSID("playerWillSaveGame") withArgument:@"AUTO_SAVE"];

    std::string saveName = oo::StdString([self lastsaveName]);
    const std::string autosaveSuffix = oo::StdString(DESC(@"autosave-commander-suffix"));

    if (!oo::str::hasSuffix(saveName, autosaveSuffix)) {
        saveName += autosaveSuffix;
    }
    const std::string savePath = oo::str::appendingPathComponent(dir, saveName + ".oolite-save"); // a plain append, not the path-extension rule

    [self setLastsaveName:oo::NSStringFrom(saveName)];

    @try {
        [self writePlayerToPath:savePath];
    }
    @catch (id exception) {
        // Suppress exceptions silently. Warning the user about failed autosaves would be pretty unhelpful.
    }

    if (tmp_path.has_value()) {
        [save_path autorelease];
        save_path = [oo::NSStringFrom(*tmp_path) copy];
    }
    [self setLastsaveName:oo::NSStringOrNil(tmp_name)];
}

- (void)quicksavePlayer
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    std::optional<std::string> path;

    path = oo::OptionalString(save_path);
    if (!path)
        path = oo::OptionalString([[gameView gameController] playerFileToLoad]);
    if (!path) {
        OOLog(@"quickSave.failed.noName", @"%@", @"ERROR no file name returned by [[gameView gameController] playerFileToLoad]");
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
    const oo::PList scenarios = oo::PListFrom([UNIVERSE scenarios]);
    [UNIVERSE removeDemoShips];
    // GUI stuff
    {
        GuiDisplayGen* gui = [UNIVERSE gui];
        OOGUIRow start_row = GUI_ROW_SCENARIOS_START;
        OOGUIRow row = start_row;
        BOOL guiChanged = (gui_screen != GUI_SCREEN_NEWGAME);

        [gui clearAndKeepBackground:!guiChanged];
        [gui setTitle:DESC(@"oolite-newgame-title")];

        OOGUITabSettings tab_stops;
        tab_stops[0] = 0;
        tab_stops[1] = -480;
        [gui setTabStops:tab_stops];

        unsigned n_rows = GUI_MAX_ROWS_SCENARIOS;
        NSUInteger i, count = scenarios.count();

        [gui cxx_setArray: { oo::StdString(DESC(@"oolite-scenario-exit")), " <----- " } forRow:start_row - 2];
        [gui setColor:[OOColor redColor] forRow:start_row - 2];
        [gui setKey:@"exit" forRow:start_row - 2];

        if (page > 0) {
            [gui cxx_setArray: { oo::StdString(DESC(@"gui-back")), " <-- " } forRow:start_row - 1];
            [gui setColor:[OOColor greenColor] forRow:start_row - 1];
            [gui cxx_setKey:oo::str::format("__page:%i", page - 1) forRow:start_row - 1];
        }

        [self setShowDemoShips:NO];

        for (i = (NSUInteger)page * n_rows; i < count && row < start_row + n_rows; i++) {
            const oo::PList* scenario = scenarios.at(i);
            const std::optional<std::string> scenarioTitle = scenario != nullptr ? OptionalStringValue(scenario->find("name")) : std::nullopt;
            const std::string scenarioName = " " + scenarioTitle.value_or("(null)") + " "; // @" %@ "
            [gui setText:OOExpand(oo::NSStringFrom(scenarioName)) forRow:row];
            [gui cxx_setKey:oo::str::format("Scenario:%zu", i) forRow:row];
            ++row;
        }

        if ((NSUInteger)(page + 1) * n_rows < count) {
            [gui cxx_setArray: { oo::StdString(DESC(@"gui-more")), " --> " } forRow:row];
            [gui setColor:[OOColor greenColor] forRow:row];
            [gui cxx_setKey:oo::str::format("__page:%i", page + 1) forRow:row];
            ++row;
        }

        gui_screen = GUI_SCREEN_NEWGAME;

        [gui setSelectableRange:NSMakeRange(start_row - 2, 3 + row - start_row)];
        [gui setSelectedRow:start_row];
        [self showScenarioDetails];

        if (guiChanged) {
            [gui setBackgroundTextureKey:@"newgame"];
            [gui setForegroundTextureKey:@"newgame_overlay"];
        }
    }

    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)addScenarioModel:(const std::string&)shipKey
{
    [self showShipModelWithKey:oo::NSStringFrom(shipKey) shipData:nil personality:0 factorX:1.2 factorY:0.8 factorZ:6.4 inContext:@"scenario"];
}

- (void)showScenarioDetails
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::optional<std::string> key = [gui cxx_selectedRowKey];
    [UNIVERSE removeDemoShips];

    if (key && oo::str::hasPrefix(*key, "Scenario")) {
        int item = SecondFieldIntValue(key);
        const oo::PList scenarios = oo::PListFrom([UNIVERSE scenarios]);
        const oo::PList* scenario = scenarios.at(item);
        [self setShowDemoShips:NO];
        for (NSUInteger i = GUI_ROW_SCENARIOS_DETAIL; i <= 27; i++) {
            [gui setText:@"" forRow:i];
        }
        if (scenario) {
            [gui cxx_addLongText:oo::OptionalString(OOExpand(oo::NSStringOrNil(OptionalStringValue(scenario->find("description"))))) startingAtRow:GUI_ROW_SCENARIOS_DETAIL align:GUI_ALIGN_LEFT];
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

    const oo::PList scenarios = oo::PListFrom([UNIVERSE scenarios]);
    const oo::PList* scenario = scenarios.at(selection);
    const std::optional<std::string> file = scenario != nullptr ? OptionalStringValue(scenario->find("file")) : std::nullopt;
    if (!file) {
        OOLog(@"scenario.init.error", @"%@", @"No file entry found for scenario");
        return NO;
    }
    const std::optional<std::string> path = [ResourceManager cxx_pathForFileNamed:*file inFolder:"Scenarios"];
    if (!path) {
        OOLog(@"scenario.init.error", @"Game file not found for scenario %@", oo::NSStringFrom(*file));
        return NO;
    }
    BOOL result = [self loadPlayerFromFile:*path asNew:YES];
    if (!result) {
        return NO;
    }
    [scenarioKey release];
    scenarioKey = [oo::NSStringOrNil(OptionalStringValue(scenario->find("scenario"))) retain];

    // don't drop the save game directory in
    return YES;
}

- (std::optional<std::string>)commanderSelector
{
    MyOpenGLView* gameView = [UNIVERSE gameView];
    GuiDisplayGen* gui = [UNIVERSE gui];
    std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];

    int idx;
    if ([self handleGUIUpDownArrowKeys]) {
        int guiSelectedRow = [gui selectedRow];
        idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
        if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW && guiSelectedRow != EXITROW) {
            [self showCommanderShip:idx];
        } else {
            [UNIVERSE removeDemoShips];
            [gui setText:@"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
            [gui setText:@"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
            [gui setText:@"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
        }

    } else {
        idx = ([gui selectedRow] - STARTROW) + (OOGUIRow)(currentPage * NUMROWS);
    }

    // handle page <-- and page --> keys
    if (([self checkKeyPress:n_key_gui_arrow_left] || [self checkKeyPress:n_key_gui_page_up] || joyButtonState[BUTTON_GUILEFT] || joyButtonState[BUTTON_GUIPAGEUP]) && [[gui keyForRow:BACKROW] isEqual:GUI_KEY_OK]) {
        currentPage--;
        [self playMenuPagePrevious];
        [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }
    if (([self checkKeyPress:n_key_gui_arrow_right] || [self checkKeyPress:n_key_gui_page_down] || joyButtonState[BUTTON_GUIRIGHT] || joyButtonState[BUTTON_GUIPAGEDOWN]) && [[gui keyForRow:MOREROW] isEqual:GUI_KEY_OK]) {
        currentPage++;
        [self playMenuPageNext];
        [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
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
            currentPage--;
            [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
            [gameView suppressKeysUntilKeyUp];
            break;
        case MOREROW:
            currentPage++;
            [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
            [gameView suppressKeysUntilKeyUp];
            break;
        default: {
            if (idx < 0 || (std::size_t)idx >= cdrDetailArray.size())
                break; // (-objectAtIndex: raised)
            const oo::PList cdr = cdrDetailArray[idx];
            if (cdr.get<bool>("isSavedGame"))
                return OptionalStringValue(cdr.find("saved_game_path"));
            else {
                if ([gameView isCommandModifierKeyDown] || [gameView isDown:gvMouseDoubleClick]) {
                    // change directory to the selected path
                    const std::string newDir = cdr.get<std::string>("saved_game_path");
                    [[UNIVERSE gameController] setPlayerFileDirectory:oo::NSStringFrom(newDir)];
                    dir = newDir;
                    currentPage = 0;
                    [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
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
    std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);
    const BOOL* joyButtonState = [[OOJoystickManager sharedStickHandler] getAllButtonStates];

    if ([self handleGUIUpDownArrowKeys]) {
        int guiSelectedRow = [gui selectedRow];
        int idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
        if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW) {
            [self showCommanderShip:idx];
            if (idx >= 0 && (std::size_t)idx < cdrDetailArray.size() && cdrDetailArray[idx].get<bool>("isSavedGame")) // don't show things that aren't saved games
                commanderNameString = CommanderSaveName(cdrDetailArray[idx]).value_or("");
            else
                commanderNameString = [gameView cxx_typedString].value_or("");
        } else {
            [UNIVERSE removeDemoShips];
            [gui setText:@"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
            [gui setText:@"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
            [gui setText:@"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];
        }
    } else {
        commanderNameString = [gameView cxx_typedString].value_or("");
    }

    [gameView cxx_setTypedString:commanderNameString];

    [gui cxx_setText:
            oo::str::formatRuntime(oo::StdString(DESC(@"savescreen-commander-name-@")), { commanderNameString })
              forRow:INPUTROW];
    [gui setColor:[OOColor cyanColor] forRow:INPUTROW];

    // handle page <-- and page --> keys, and on-screen buttons
    if (((([gameView isDown:gvMouseDoubleClick] || [self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT]) && [gui selectedRow] == BACKROW) || ([self checkKeyPress:n_key_gui_arrow_left] || [self checkKeyPress:n_key_gui_page_up]))
        && [[gui keyForRow:BACKROW] isEqual:GUI_KEY_OK]) {
        currentPage--;
        [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }
    //
    if (((([gameView isDown:gvMouseDoubleClick] || [self checkKeyPress:n_key_gui_select] || joyButtonState[BUTTON_GUISELECT]) && [gui selectedRow] == MOREROW) || ([self checkKeyPress:n_key_gui_arrow_right] || [self checkKeyPress:n_key_gui_page_down]))
        && [[gui keyForRow:MOREROW] isEqual:GUI_KEY_OK]) {
        currentPage++;
        [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
        [gameView suppressKeysUntilKeyUp];
    }

    // ignore Ctrl if pressed together with Enter for the moment - we check for it explicitly immediately after
    if (([self checkKeyPress:n_key_gui_select ignore_ctrl:YES] || [gameView isDown:gvMouseDoubleClick] || joyButtonState[BUTTON_GUISELECT]) && !commanderNameString.empty()) {
        if ([gameView isCommandModifierKeyDown] || [gameView isDown:gvMouseDoubleClick]) {
            int guiSelectedRow = [gui selectedRow];
            int idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
            const oo::PList cdr = (idx >= 0 && (std::size_t)idx < cdrDetailArray.size()) ? cdrDetailArray[idx] : oo::PList(); // (-objectAtIndex: raised)

            if (!cdr.isNull() && !cdr.get<bool>("isSavedGame")) // don't open saved games
            {
                // change directory to the selected path
                const std::string newDir = cdr.get<std::string>("saved_game_path");
                [[UNIVERSE gameController] setPlayerFileDirectory:oo::NSStringFrom(newDir)];
                dir = newDir;
                currentPage = 0;
                [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];
                [gameView suppressKeysUntilKeyUp];
            }
        } else {
            pollControls = YES;
            if ([self existingNativeSave:commanderNameString]) {
                [gameView suppressKeysUntilKeyUp];
                [self setGuiToOverwriteScreen:commanderNameString];
            } else {
                [self nativeSavePlayer:commanderNameString];
                [[UNIVERSE gameView] suppressKeysUntilKeyUp];
                [self setGuiToStatusScreen];
            }
        }
    }

    if ([gameView isDown:27]) // escape key
    {
        // get out of here
        pollControls = YES;
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
    const std::string valueYes = oo::str::lowercase(OptionalStringValue([[UNIVERSE descriptions] objectForKey:@"load-previous-commander-yes"]).value_or("y"));
    const std::string valueNo = oo::str::lowercase(OptionalStringValue([[UNIVERSE descriptions] objectForKey:@"load-previous-commander-no"]).value_or("n"));
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
        pollControls = YES;
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
        fail_reason = oo::OptionalString(DESC(@"loadfailed-no-file-specified"));
        loadedOK = NO;
    }

    if (loadedOK) {
        OOLog(@"load.progress", @"%@", @"Reading file");
        fileDic = oo::PListFrom(OODictionaryFromFile(oo::NSStringFrom(fileToOpen)));
        if (!fileDic.isDict()) {
            fail_reason = oo::OptionalString(DESC(@"loadfailed-could-not-load-file"));
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OOLog(@"load.progress", @"%@", @"Restricting scenario");
        std::string scenarioRestrict;
        const std::optional<std::string> savedRestrict = OptionalStringValue(fileDic.find("scenario_restriction"));
        if (savedRestrict) {
            scenarioRestrict = *savedRestrict;
        } else {
            // older save game - use the 'strict' key instead
            BOOL strict = fileDic.get<bool>("strict", NO);
            if (strict) {
                scenarioRestrict = oo::StdString(SCENARIO_OXP_DEFINITION_NONE);
            } else {
                scenarioRestrict = oo::StdString(SCENARIO_OXP_DEFINITION_ALL);
            }
        }

        if (![UNIVERSE setUseAddOns:oo::NSStringFrom(scenarioRestrict) fromSaveGame:YES forceReinit:YES]) {
            fail_reason = oo::OptionalString(DESC(@"loadfailed-saved-game-failed-to-load"));
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OOLog(@"load.progress", @"%@", @"Creating player ship");
        // Check that player ship exists
        const std::optional<std::string> shipKey = OptionalStringValue(fileDic.find("ship_desc"));
        oo::PList shipDict;

        if (shipKey)
            shipDict = [[OOShipRegistry sharedRegistry] cxx_shipInfoForKey:*shipKey];

        if (shipDict.isNull()) {
            loadedOK = NO;
            if (shipKey)
                fail_reason = oo::str::formatRuntime(oo::StdString(DESC(@"loadfailed-could-not-find-ship-type-@-please-reinstall-the-appropriate-OXP")), { *shipKey });
            else
                fail_reason = oo::OptionalString(DESC(@"loadfailed-invalid-saved-game-no-ship-specified"));
        }
    }

    if (loadedOK) {
        OOLog(@"load.progress", @"%@", @"Initialising player entity");
        if (![self setUpAndConfirmOK:YES saveGame:YES]) {
            fail_reason = oo::OptionalString(DESC(@"loadfailed-could-not-reset-javascript"));
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OOLog(@"load.progress", @"%@", @"Loading commander data");
        if (![self setCommanderDataFromDictionary:oo::ObjectFromPList(fileDic)]) {
            // this could still be a reset js issue, if switching from strict / unrestricted
            // TODO: use "could not reset js message" if that's the case.
            fail_reason = oo::OptionalString(DESC(@"loadfailed-could-not-set-up-player-ship"));
            loadedOK = NO;
        }
    }

    if (loadedOK) {
        OOLog(@"load.progress", @"%@", @"Recording save path");
        if (!asNew) {
            [save_path autorelease];
            save_path = [oo::NSStringFrom(fileToOpen) retain];

            [[[UNIVERSE gameView] gameController] setPlayerFileToLoad:oo::NSStringFrom(fileToOpen)];
            [[[UNIVERSE gameView] gameController] setPlayerFileDirectory:oo::NSStringFrom(fileToOpen)];
        }
    } else {
        OOLog(@"load.failed", @"***** Failed to load saved game \"%@\": %@", oo::NSStringFrom(oo::str::lastPathComponent(fileToOpen)), oo::NSStringFrom(fail_reason.value_or("unknown error")));
        [[UNIVERSE gameController] setPlayerFileToLoad:nil];
        [UNIVERSE handleGameOver];
        [UNIVERSE clearPreviousMessage];
        [UNIVERSE addMessage:DESC(@"loadfailed-saved-game-failed-to-load") forCount:9.0];
        if (fail_reason)
            [UNIVERSE addMessage:oo::NSStringFrom(*fail_reason) forCount:9.0];
        return NO;
    }

    OOLog(@"load.progress", @"%@", @"Creating system");
    [UNIVERSE setTimeAccelerationFactor:TIME_ACCELERATION_FACTOR_DEFAULT];
    [UNIVERSE setSystemTo:system_id];
    [UNIVERSE removeAllEntitiesExceptPlayer];
    [UNIVERSE setGalaxyTo:galaxy_number andReinit:YES]; // set overridden planet names on long range map
    [UNIVERSE setUpSpace];
    [UNIVERSE setAutoSaveNow:NO];

    OOLog(@"load.progress", @"%@", @"Resetting player flight variables");
    [self setDockedAtMainStation];
    StationEntity* dockedStation = [self dockedStation];

    [UNIVERSE enterGUIViewModeWithMouseInteraction:NO];

    if (dockedStation) {
        position = [dockedStation position];
        [self setOrientation:kIdentityQuaternion];
        v_forward = vector_forward_from_quaternion(orientation);
        v_right = vector_right_from_quaternion(orientation);
        v_up = vector_up_from_quaternion(orientation);
    }

    flightRoll = 0.0;
    flightPitch = 0.0;
    flightYaw = 0.0;
    flightSpeed = 0.0;

    [self setEntityPersonalityInt:PersonalityForCommanderDict(fileDic)];

    OOLog(@"load.progress", @"%@", @"Loading system market");
    // dockedStation is always the main station at this point;
    // "localMarket" save key always refers to the main station (system) market
    const oo::PList* market = fileDic.get<oo::PList::Array>("localMarket");
    if (market != nullptr) {
        [dockedStation setLocalMarket:oo::ObjectFromPList(*market)];
    } else {
        [dockedStation initialiseLocalMarket];
    }

    [self calculateCurrentCargo];

    OOLog(@"load.progress", @"%@", @"Setting scenario key");
    // set scenario key if the scenario allows saving and has one
    const std::optional<std::string> scenario = OptionalStringValue(fileDic.find("scenario_key"));
    DESTROY(scenarioKey);
    if (scenario) {
        scenarioKey = [oo::NSStringFrom(*scenario) retain];
    }

    OOLog(@"load.progress", @"%@", @"Starting JS engine");
    // Remember the savegame target, run js startUp.
    [self completeSetUpAndSetTarget:NO];
    // run initial system population
    OOLog(@"load.progress", @"%@", @"Populating initial system");
    [UNIVERSE populateNormalSpace];

    // might as well start off with a collected JS environment
    [[OOJavaScriptEngine sharedEngine] garbageCollectionOpportunity:YES];

    // read saved position vector and primary role, check for an
    // appropriate station at those coordinates, if found, switch
    // docked station to that one.
    const oo::PList* dockedPosNode = fileDic.find("docked_station_position");
    HPVector dockedPos = OOHPVectorFromObject(dockedPosNode != nullptr ? oo::ObjectFromPList(*dockedPosNode) : nil, kZeroHPVector);
    const std::string dockedRole = OptionalStringValue(fileDic.find("docked_station_role")).value_or("");
    StationEntity* saveStation = [UNIVERSE stationWithRole:oo::NSStringFrom(dockedRole) andPosition:dockedPos];
    if (saveStation != nil && [saveStation allowsSaving]) {
        [self setDockedStation:saveStation];
        position = [saveStation position];
    }
    // and initialise markets for the secondary stations
    const oo::PList* stationMarkets = fileDic.get<oo::PList::Array>("station_markets");
    [UNIVERSE loadStationMarkets:stationMarkets != nullptr ? oo::ObjectFromPList(*stationMarkets) : nil];

    OOLog(@"load.progress", @"%@", @"Completing JS startup");
    [self startUpComplete];

    // if the file was specified in the command line at startup, DO NOT suppress the keys!
    if ([[UNIVERSE gameController] finishedLaunching])
        [[UNIVERSE gameView] suppressKeysUntilKeyUp];
    if (asNew) {
        gui_screen = GUI_SCREEN_NEWGAME;
    } else {
        gui_screen = GUI_SCREEN_LOAD; // force evaluation of new gui screen on startup
    }
    [self setGuiToStatusScreen];
    if (loadedOK)
        [self doWorldEventUntilMissionScreen:OOJSID("missionScreenOpportunity")]; // trigger missionScreenOpportunity immediately after loading
    OOLog(@"load.progress", @"%@", @"Loading complete");
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
        OOLog(@"save.failed", @"***** SAVE ERROR: %s called with nil path.", __PRETTY_FUNCTION__);
        return;
    }

    // The save dictionary as a property list, converted once (its float values stay single reals,
    // written %0.7g as before).
    const oo::PList dict = oo::PListFrom([self commanderDataDictionary]);
    if (dict.isNull())
        errDesc = "could not construct commander data dictionary.";
    else {
        didSave = OOWriteXMLPListToFile(dict, path, &errDesc);
    }
    if (didSave) {
        [UNIVERSE clearPreviousMessage]; // allow this to be given time and again
        [UNIVERSE addMessage:DESC(@"game-saved") forCount:2];
        [save_path autorelease];
        save_path = [oo::NSStringFrom(path) copy];
        [[UNIVERSE gameController] setPlayerFileToLoad:save_path];
        [[UNIVERSE gameController] setPlayerFileDirectory:save_path];
        // no duplicated autosave immediately after a save.
        [UNIVERSE setAutoSaveNow:NO];
    } else {
        OOLog(@"save.failed", @"***** SAVE ERROR: %@", oo::NSStringFrom(errDesc));
        [OOException raise:"OoliteException"
                    format:"Attempt to save game to file '%s' failed: %s", path.c_str(), errDesc.c_str()];
    }
    [[UNIVERSE gameView] suppressKeysUntilKeyUp];
    [self setGuiToStatusScreen];
}

- (void)nativeSavePlayer:(const std::string&)cdrName
{
    const std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);
    const std::string savePath = oo::str::appendingPathComponent(dir, SaveFileName(cdrName));

    [self doScriptEvent:OOJSID("playerWillSaveGame") withArgument:@"STANDARD_SAVE"];

    [self setLastsaveName:oo::NSStringFrom(cdrName)];

    [self writePlayerToPath:savePath];
}

- (void)setGuiToLoadCommanderScreen
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    const std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);

    gui_screen = GUI_SCREEN_LOAD;

    [gui clear];
    [gui setTitle:DESC(@"loadscreen-title")];

    currentPage = 0;
    [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];

    [gui setForegroundTextureKey:@"docked_overlay"];
    [gui setBackgroundTextureKey:@"load_save"];

    [[UNIVERSE gameView] suppressKeysUntilKeyUp];

    [self setShowDemoShips:YES];
    [UNIVERSE enterGUIViewModeWithMouseInteraction:YES];
}

- (void)setGuiToSaveCommanderScreen:(const std::string&)cdrName
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    MyOpenGLView* gameView = [UNIVERSE gameView];
    const std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);

    pollControls = NO;
    gui_screen = GUI_SCREEN_SAVE;

    [gui clear];
    [gui setTitle:DESC(@"savescreen-title")];

    currentPage = 0;
    [self lsCommanders:gui directory:dir pageNumber:currentPage highlightName:std::nullopt];

    [gui setText:DESC(@"savescreen-commander-name") forRow:INPUTROW];
    [gui setColor:[OOColor cyanColor] forRow:INPUTROW];
    [gui setShowTextCursor:YES];
    [gui setCurrentRow:INPUTROW];

    [gui setForegroundTextureKey:@"docked_overlay"];
    [gui setBackgroundTextureKey:@"load_save"];

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
    pollControls = NO;

    gui_screen = GUI_SCREEN_SAVE_OVERWRITE;

    [gui clear];
    [gui setTitle:oo::NSStringFrom(oo::str::formatRuntime(oo::StdString(DESC(@"overwrite-save-commander-@")), { cdrName }))];

    [gui cxx_setText:oo::str::formatRuntime(oo::StdString(DESC(@"overwritescreen-commander-@-already-exists-overwrite-query")), { cdrName })
              forRow:SAVE_OVERWRITE_WARN_ROW
               align:GUI_ALIGN_CENTER];

    [gui setText:DESC(@"overwritescreen-yes") forRow:SAVE_OVERWRITE_YES_ROW align:GUI_ALIGN_CENTER];
    [gui setKey:GUI_KEY_OK forRow:SAVE_OVERWRITE_YES_ROW];

    [gui setText:DESC(@"overwritescreen-no") forRow:SAVE_OVERWRITE_NO_ROW align:GUI_ALIGN_CENTER];
    [gui setKey:GUI_KEY_OK forRow:SAVE_OVERWRITE_NO_ROW];

    [gui setSelectableRange:NSMakeRange(SAVE_OVERWRITE_YES_ROW, 2)];
    [gui setSelectedRow:SAVE_OVERWRITE_NO_ROW];

    // We can only leave this screen by answering yes or no, or esc. Therefore
    // use a specific overlay, to allow visual reminders of the available options.
    [gui setForegroundTextureKey:@"overwrite_overlay"];
    [gui setBackgroundTextureKey:@"load_save"];

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

    // The retiring NSFileManager (OOExtensions) commander listing, in place: the directory's entries
    // as full paths. Its per-entry filter tested `!exists && isDirectory`, which never holds, so it
    // only built the paths.
    std::vector<std::string> cdrArray;
    const oo::fs::Path directoryPath = oo::fs::pathFromUTF8(directory);
    if (oo::fs::fileType(directoryPath) == oo::fs::FileType::directory) {
        const auto names = oo::fs::directoryContents(directoryPath);
        if (names) {
            for (const std::string& entry : *names)
                cdrArray.push_back(oo::str::appendingPathComponent(directory, entry));
        }
    } else {
        OOLogERR(@"savedGame.read.fail.fileNotFound", @"File at path '%@' could not be found.", oo::NSStringFrom(directory));
    }

    // get commander details so a brief rundown of the commander's details may
    // be displayed.
    cdrDetailArray.clear();

    cdrDetailArray.push_back(oo::PList(oo::PList::Dict {
        { "isParentFolder", oo::PList("YES") },
        { "saved_game_path", oo::PList(oo::str::deletingLastPathComponent(directory)) } }));

    for (const std::string& path : cdrArray) {
        const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(path));

        if (type != oo::fs::FileType::none) {
            if (type != oo::fs::FileType::directory && oo::str::lowercase(oo::str::pathExtension(path)) == "oolite-save") {
                oo::PList cdr = oo::PListFrom(OODictionaryFromFile(oo::NSStringFrom(path)));
                if (oo::PList::Dict* cdr1 = cdr.getIf<oo::PList::Dict>()) {
                    // okay use the same dictionary but add a 'saved_game_path' attribute
                    (*cdr1)["isSavedGame"] = oo::PList("YES");
                    (*cdr1)["saved_game_path"] = oo::PList(path);
                    cdrDetailArray.push_back(std::move(cdr));
                }
            }
            if (type == oo::fs::FileType::directory && !oo::str::hasPrefix(oo::str::lastPathComponent(path), ".")) {
                cdrDetailArray.push_back(oo::PList(oo::PList::Dict {
                    { "isFolder", oo::PList("YES") },
                    { "saved_game_path", oo::PList(path) } }));
            }
        }
    }

    if (cdrDetailArray.empty()) {
        // Empty directory; tell the user and exit immediately.
        [gui setText:DESC(@"loadsavescreen-no-commanders-found") forRow:STARTROW align:GUI_ALIGN_CENTER];
        return;
    }

    // sortCommanders: saved_game_path in the locale collation (oo::str::localizedCompare, ICU, as GNUstep sorted it).
    std::stable_sort(cdrDetailArray.begin(), cdrDetailArray.end(), [](const oo::PList& cdr1, const oo::PList& cdr2) {
        return oo::str::localizedCompare(cdr1.get<std::string>("saved_game_path"), cdr2.get<std::string>("saved_game_path")) < 0;
    });

    // Do we need to highlight a name?
    int highlightRowOnPage = STARTROW;
    int highlightIdx = 0;
    if (highlightName) {
        highlightIdx = [self findIndexOfCommander:*highlightName];
        if (highlightIdx < 0) {
            OOLog(@"save.list.commanders.commanderNotFound", @"Commander %@ doesn't exist, very bad", oo::NSStringFrom(*highlightName));
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
        [gui setText:@"" forRow:i align:GUI_ALIGN_LEFT];
        [gui setColor:[OOColor yellowColor] forRow:i];
        [gui setKey:GUI_KEY_SKIP forRow:i];
    }

    [gui setColor:[OOColor greenColor] forRow:LABELROW];
    [gui cxx_setArray:{ oo::StdString(DESC(@"loadsavescreen-commander-name")), oo::StdString(DESC(@"loadsavescreen-rating")) }
               forRow:LABELROW];

    if (page) {
        [gui setColor:[OOColor greenColor] forRow:STARTROW - 1];
        [gui cxx_setArray:{ oo::StdString(DESC(@"gui-back")), " <-- " }
                   forRow:STARTROW - 1];
        [gui setKey:GUI_KEY_OK forRow:STARTROW - 1];
        rangeStart = STARTROW - 1;
    }

    if ([self status] == STATUS_START_GAME) {
        [gui cxx_setArray:{ oo::StdString(DESC(@"oolite-loadsave-exit")), " <----- " } forRow:EXITROW];
        [gui setColor:[OOColor redColor] forRow:EXITROW];
        [gui setKey:GUI_KEY_OK forRow:EXITROW];
        rangeStart = EXITROW;
    }

    if (firstIndex + NUMROWS >= cdrDetailArray.size()) {
        lastIndex = cdrDetailArray.size();
        [gui setSelectableRange:NSMakeRange(rangeStart, rangeStart + NUMROWS + 2)];
    } else {
        lastIndex = (page * NUMROWS) + NUMROWS;
        [gui setColor:[OOColor greenColor] forRow:ENDROW];
        [gui cxx_setArray:{ oo::StdString(DESC(@"gui-more")), " --> " }
                   forRow:ENDROW];
        [gui setKey:GUI_KEY_OK forRow:ENDROW];
        [gui setSelectableRange:NSMakeRange(rangeStart, MOREROW)];
    }

    const std::optional<std::string> lastsaveName = oo::OptionalString([self lastsaveName]);
    for (i = firstIndex; i < lastIndex; i++) {
        const oo::PList& cdr = cdrDetailArray[i];
        if (cdr.get<bool>("isSavedGame")) {
            const std::string ratingDesc = oo::DescriptionOf(OODisplayRatingStringFromKillCount(cdr.get<unsigned int>("ship_kills")));
            const std::optional<std::string> saveName = CommanderSaveName(cdr);
            [gui cxx_setArray:{
                                  " " + saveName.value_or("(null)") + " ", // @" %@ "
                                  " " + ratingDesc + " " }
                       forRow:row];
            if (lastsaveName && saveName && *lastsaveName == *saveName) {
                highlightRowOnPage = row;
            }

            [gui setKey:GUI_KEY_OK forRow:row];
            row++;
        }
        if (cdr.get<bool>("isParentFolder")) {
            [gui cxx_setArray:{
                                  " (..) " + oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) + " ",
                                  "" }
                       forRow:row];
            [gui setColor:[OOColor orangeColor] forRow:row];
            [gui setKey:GUI_KEY_OK forRow:row];
            row++;
        }
        if (cdr.get<bool>("isFolder")) {
            [gui cxx_setArray:{
                                  " >> " + oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) + " ",
                                  "" }
                       forRow:row];
            [gui setColor:[OOColor orangeColor] forRow:row];
            [gui setKey:GUI_KEY_OK forRow:row];
            row++;
        }
    }
    [gui setSelectedRow:highlightRowOnPage];
    highlightIdx = (highlightRowOnPage - STARTROW) + (currentPage * NUMROWS);
    // show the first ship, this will be the selected row
    [self showCommanderShip:highlightIdx];
}

// check for an existing saved game...
- (BOOL)existingNativeSave:(const std::string&)cdrName
{
    const std::string dir = oo::StdString([[UNIVERSE gameController] playerFileDirectory]);

    const std::string savePath = oo::str::appendingPathComponent(dir, SaveFileName(cdrName));
    return oo::fs::fileExists(oo::fs::pathFromUTF8(savePath));
}

// Get some brief details about the commander file.
- (void)showCommanderShip:(int)cdrArrayIndex
{
    GuiDisplayGen* gui = [UNIVERSE gui];
    [UNIVERSE removeDemoShips];
    if (cdrArrayIndex < 0 || (std::size_t)cdrArrayIndex >= cdrDetailArray.size())
        return; // (-objectAtIndex: raised)
    const oo::PList cdr = cdrDetailArray[cdrArrayIndex];

    [gui setText:@"" forRow:CDRDESCROW align:GUI_ALIGN_LEFT];
    [gui setText:@"" forRow:CDRDESCROW + 1 align:GUI_ALIGN_LEFT];
    [gui setText:@"" forRow:CDRDESCROW + 2 align:GUI_ALIGN_LEFT];

    if (cdr.get<bool>("isFolder")) {
        const std::string folderDesc = oo::str::formatRuntime(oo::StdString(DESC(@"loadsavescreen-hold-@-and-press-return-to-open-folder-@")), { COMMAND_MODIFIER_KEY, oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) });
        [gui setColor:[OOColor orangeColor] forRow:CDRDESCROW];
        [gui cxx_addLongText:folderDesc startingAtRow:CDRDESCROW align:GUI_ALIGN_LEFT];
        return;
    }

    if (cdr.get<bool>("isParentFolder")) {
        const std::string folderDesc = oo::str::formatRuntime(oo::StdString(DESC(@"loadsavescreen-hold-@-and-press-return-to-open-parent-folder-@")), { COMMAND_MODIFIER_KEY, oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) });
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
        [self showShipyardModel:oo::NSStringFrom(*shipDesc) shipData:oo::ObjectFromPList(dict) personality:personality];
        shipName = OptionalStringValue(shipDict.find("display_name"));
        if (!shipName)
            shipName = OptionalStringValue(shipDict.find("name")); // KEY_NAME
    } else {
        [self showShipyardModel:@"oolite-unknown-ship" shipData:nil personality:personality];
        shipName = OptionalStringValue(cdr.find("ship_name")).value_or("unknown");
        if (![[UNIVERSE useAddOns] isEqualToString:SCENARIO_OXP_DEFINITION_ALL]) {
            *shipName += " - OXPs disabled or not installed";
        } else {
            *shipName += " - OXP not installed";
        }
    }

    // Make a short description of the commander
    const std::string legalDesc = oo::DescriptionOf(OODisplayStringFromLegalStatus(cdr.get<int>("legal_status")));

    rating = oo::DescriptionOf(KillCountToRatingAndKillString(cdr.get<unsigned int>("ship_kills")));
    const oo::PList* creditsNode = cdr.find("credits");
    OOCreditsQuantity money = OODeciCreditsFromObject(creditsNode != nullptr ? oo::ObjectFromPList(*creditsNode) : nil);

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

    const std::string cdrDesc = oo::str::formatRuntime(oo::StdString(DESC(@"loadsavescreen-commander-@-rated-@-has-@-legal-status-@-ship-@-location-@-g-@-eco-@-gov-@-tl-@-timestamp-@")),
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
    for (i = 0; i < cdrDetailArray.size(); i++) {
        const std::optional<std::string> currentName = CommanderSaveName(cdrDetailArray[i]);
        if (currentName && cdrName == *currentName) // -compare: == NSOrderedSame
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

OOCreditsQuantity OODeciCreditsFromObject(id object)
{
    if (oo::IsNSNumber(object) && oo::PListFrom(object).isReal()) // float/double NSNumber (objCType f or d)
    {
        return OODeciCreditsFromDouble([object doubleValue]);
    } else {
        return OOUnsignedLongLongFromObject(object, 0);
    }
}
