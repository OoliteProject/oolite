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

#include "PlayerEntityLoadSave.h"
#include "PlayerEntityContracts.h"
#include "PlayerEntityControls.h"
#include "PlayerEntitySound.h"

#include "GameController.h"
#include "ResourceManager.h"
#include "OOStringExpander.h"
#include "PlayerEntityControls.h"
#include "ProxyPlayerEntity.h"
#include "ShipEntityAI.h"
#include "OOXMLExtensions.h"
#include "OOSound.h"
#include "OOColor.h"
#include "OOStringParsing.h"
#include "OOPListParsing.h"
#include "StationEntity.h"
#include "OOConstToString.h"
#include "OOShipRegistry.h"
#include "OOTexture.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/FileSystem.hpp"

#include <algorithm>
#include "oofnd/objc/OOAssert.h"
#include "OOPListGameTypes.h"
#include "oofnd/String.hpp"


// Name of modifier key used to issue commands. See also IsCommandModifierKeyDown().
#if OO_USE_CUSTOM_LOAD_SAVE
#define COMMAND_MODIFIER_KEY		"Ctrl"
#endif


namespace
{

uint16_t PersonalityForCommanderDict(const oo::PList &dict);


// -oo_stringForKey:'s value without the Foundation type: a string as is, a number's
// -stringValue, anything else (or nothing) nullopt, as it gave nil.
std::optional<std::string> OptionalStringValue(const oo::PList *value)
{
	if (value == nullptr)  return std::nullopt;
	if (const std::string *string = value->getIf<std::string>())  return *string;
	if (value->isNumber())  return oo::plist_get::numberStringValue(*value);
	return std::nullopt;
}


// [[key componentsSeparatedByString:@":"] oo_intAtIndex:1]: element 1's -intValue, 0 when there is
// none (or no key).
int SecondFieldIntValue(const std::optional<std::string> &key)
{
	if (!key)  return 0;
	const std::vector<std::string> fields = oo::str::split(*key, ":");
	return fields.size() > 1 ? oo::str::intValue(fields[1]) : 0;
}

#if OO_USE_CUSTOM_LOAD_SAVE

// %@ of a string that may be nil, in a runtime format.
oo::str::FormatArg TextArg(const std::optional<std::string> &string)
{
	return string ? oo::str::FormatArg(*string) : oo::str::FormatArg::null();
}


// A saved game's name on the load/save screens: -oo_stringForKey:@"player_save_name"
// defaultValue:[cdr oo_stringForKey:@"player_name"].
std::optional<std::string> CommanderSaveName(const oo::PList &cdr)
{
	std::optional<std::string> name = OptionalStringValue(cdr.find("player_save_name"));
	if (!name)  name = OptionalStringValue(cdr.find("player_name"));
	return name;
}


// -stringByAppendingPathExtension:@"oolite-save": trailing separators ('/' and, as GNUstep on
// Windows, '\\') are dropped first.
std::string SaveFileName(const std::string &name)
{
	std::string result = name;
	while (!result.empty() && (result.back() == '/' || result.back() == '\\'))  result.pop_back();
	return result + ".oolite-save";
}


// -characterAtIndex:0 & 0x00ff: the low byte of the first UTF-16 unit (-characterAtIndex: raised
// on an empty string; 0 here).
unsigned char FirstUnitLowByte(const std::string &string)
{
	const std::u16string units = oo::utf8ToUtf16(string);
	return units.empty() ? 0 : static_cast<unsigned char>(units[0] & 0x00ff);
}

#endif

}	// namespace


#if OO_USE_CUSTOM_LOAD_SAVE

namespace {

/*	Formerly -[MyOpenGLView isCommandModifierKeyDown], the file's category on the view's facade (bead
	oo-rczn, ADR-0056 amendment oo-lmdi8): the view's C++ part answers (no view: NO, as a message to
	nil did).
*/
bool IsCommandModifierKeyDown(::MyOpenGLView *gameView)
{
	MyOpenGLView *view = gameView;
	return view != nullptr && view->isCtrlDown();
}

}	// namespace

#endif


bool PlayerEntity::loadPlayer()
{
	BOOL				OK = YES;
	
#if OO_USE_APPKIT_LOAD_SAVE_ALWAYS
	OK = loadPlayerWithPanel();
#elif OOLITE_USE_APPKIT_LOAD_SAVE
	// OS X: use system open/save dialogs in windowed mode, custom interface in full-screen.
	if ([(UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr) inFullScreenMode])
	{
		setGuiToLoadCommanderScreen();
	}
	else
	{
		OK = loadPlayerWithPanel();
	}
#else
	// Other platforms: use custom interface all the time.
	setGuiToLoadCommanderScreen();
#endif
	return OK;
}


void PlayerEntity::savePlayer()
{
#if OO_USE_APPKIT_LOAD_SAVE_ALWAYS
	savePlayerWithPanel();
#elif OOLITE_USE_APPKIT_LOAD_SAVE
	// OS X: use system open/save dialogs in windowed mode, custom interface in full-screen.
	if ([(UNIVERSE != nullptr ? UNIVERSE->gameController() : nullptr) inFullScreenMode])
	{
		setGuiToSaveCommanderScreen(lastsaveName().value_or(""));	// the member the property read (bead oo-w9pi2)
	}
	else
	{
		savePlayerWithPanel();
	}
#else
	// Other platforms: use custom interface all the time.
	setGuiToSaveCommanderScreen(lastsaveName().value_or(""));
#endif
}

void PlayerEntity::autosavePlayer()
{
	std::optional<std::string>	tmp_path;
	std::optional<std::string>	tmp_name;
	const std::string			dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");

	tmp_name = lastsaveName();
	tmp_path = save_path;
	
	ShipScriptEventNoCx(this, "playerWillSaveGame", OOJSSTR("AUTO_SAVE"));
	
	std::string saveName = lastsaveName().value_or("");
	const std::string autosaveSuffix = OO_DESC("autosave-commander-suffix");

	if (!oo::str::hasSuffix(saveName, autosaveSuffix))
	{
		saveName += autosaveSuffix;
	}
	const std::string savePath = oo::str::appendingPathComponent(dir, saveName + ".oolite-save");	// a plain append, not the path-extension rule

	setLastsaveName(saveName);
	
	try
	{
		writePlayerToPath(savePath);
	}
	catch (...)
	{
		// Suppress exceptions silently. Warning the user about failed autosaves would be pretty unhelpful.
		// (The game's own, oo::Exception since oo-rskgl.1: what @catch (id) caught; anything else goes on up.)
		if (!oo::CurrentOOException())  throw;
	}
	
	if (tmp_path.has_value())
	{
		save_path = *tmp_path;
	}
	setLastsaveName(tmp_name);
}


void PlayerEntity::quicksavePlayer()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	std::optional<std::string>	path;

	path = save_path;
	if (!path)  path = (gameView != nullptr && gameView->getGameController() != nullptr ? gameView->getGameController()->playerFileToLoad() : std::optional<std::string>());
	if (!path)
	{
		OO_LOG("quickSave.failed.noName", "{}", "ERROR no file name returned by [[gameView gameController] playerFileToLoad]");
		OORaiseException("OoliteGameNotSavedException", "ERROR no file name returned by [[gameView gameController] playerFileToLoad]");
	}
	
	ShipScriptEventNoCx(this, "playerWillSaveGame", OOJSSTR("QUICK_SAVE"));

	writePlayerToPath(*path);
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
	setGuiToStatusScreen();
}


void PlayerEntity::setGuiToScenarioScreen(int page)
{
	const oo::PList scenarios = (UNIVERSE != nullptr ? UNIVERSE->scenarios() : oo::PList());
	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
	// GUI stuff
	{
		::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
		OOGUIRow		start_row = GUI_ROW_SCENARIOS_START;
		OOGUIRow		row = start_row;
		BOOL			guiChanged = (gui_screen != GUI_SCREEN_NEWGAME);

		gui->clearAndKeepBackground(!guiChanged);
		gui->setTitle(OO_DESC("oolite-newgame-title"));

		OOGUITabSettings tab_stops;
		tab_stops[0] = 0;
		tab_stops[1] = -480;
		gui->setTabStops(tab_stops);

		unsigned n_rows = GUI_MAX_ROWS_SCENARIOS;
		NSUInteger i, count = scenarios.count();

		gui->setArray({ OO_DESC("oolite-scenario-exit"), " <----- " }, start_row - 2);
		gui->setColor(OOColor::redColor().get(), start_row - 2);
		gui->setKey("exit", start_row - 2);
		

		if (page > 0)
		{
			gui->setArray({ OO_DESC("gui-back"), " <-- " }, start_row - 1);
			gui->setColor(OOColor::greenColor().get(), start_row - 1);
			gui->setKey(oo::str::format("__page:%i",page-1), start_row - 1);
		}

		setShowDemoShips(NO);

		for (i = (NSUInteger)page*n_rows ; i < count && row < start_row + n_rows ; i++)
		{
			const oo::PList *scenario = scenarios.at(i);
			const std::optional<std::string> scenarioTitle = scenario != nullptr ? OptionalStringValue(scenario->find("name")) : std::nullopt;
			const std::string scenarioName = " " + scenarioTitle.value_or("(null)") + " ";	// @" %@ "
			gui->setText(cxx_OOExpand(scenarioName).value_or(std::string()), row);
			gui->setKey(oo::str::format("Scenario:%zu", i), row);
			++row;
		}

		if ((NSUInteger)(page+1) * n_rows < count)
		{
			gui->setArray({ OO_DESC("gui-more"), " --> " }, row);
			gui->setColor(OOColor::greenColor().get(), row);
			gui->setKey(oo::str::format("__page:%i",page+1), row);
			++row;
		}
		
		gui_screen = GUI_SCREEN_NEWGAME;

		gui->setSelectableRange(NSMakeRange(start_row - 2,3 + row - start_row));
		gui->setSelectedRow(start_row);
		showScenarioDetails();
	
		if (guiChanged)
		{
			gui->setBackgroundTextureKey("newgame");
			gui->setForegroundTextureKey("newgame_overlay");
		}
	}
	
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}

void PlayerEntity::addScenarioModel(const std::string &shipKey)
{
	showShipModelWithKey(shipKey, oo::PList(), 0, 1.2, 0.8, 6.4, "scenario");
}


void PlayerEntity::showScenarioDetails()
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::optional<std::string> key = gui->selectedRowKey();
	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();

	if (key && oo::str::hasPrefix(*key, "Scenario"))
	{
		int item = SecondFieldIntValue(key);
		const oo::PList scenarios = (UNIVERSE != nullptr ? UNIVERSE->scenarios() : oo::PList());
		const oo::PList *scenario = scenarios.at(item);
		setShowDemoShips(NO);
		for (NSUInteger i=GUI_ROW_SCENARIOS_DETAIL;i<=27;i++)
		{
			gui->setText("", i);
		}
		if (scenario)
		{
			const std::optional<std::string> scenarioDescription = OptionalStringValue(scenario->find("description"));
			const std::optional<std::string> expandedDescription = scenarioDescription.has_value() ? cxx_OOExpand(*scenarioDescription) : std::nullopt;
			gui->addLongText(expandedDescription, GUI_ROW_SCENARIOS_DETAIL, GUI_ALIGN_LEFT);
			const std::optional<std::string> shipKey = OptionalStringValue(scenario->find("model"));
			if (shipKey)
			{
				addScenarioModel(*shipKey);
				setShowDemoShips(YES);
			}
		}

	}
}


bool PlayerEntity::startScenario()
{
	::GuiDisplayGen* gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::optional<std::string> key = gui->selectedRowKey();

	if (key == "exit")
	{
		// intended to return to main menu
		return NO; 
	}
	if (key && oo::str::hasPrefix(*key, "__page"))
	{
		int page = SecondFieldIntValue(key);
		setGuiToScenarioScreen(page);
		return YES;
	}
	int selection = SecondFieldIntValue(key);

	const oo::PList scenarios = (UNIVERSE != nullptr ? UNIVERSE->scenarios() : oo::PList());
	const oo::PList *scenario = scenarios.at(selection);
	const std::optional<std::string> file = scenario != nullptr ? OptionalStringValue(scenario->find("file")) : std::nullopt;
	if (!file)
	{
		OO_LOG("scenario.init.error", "{}", "No file entry found for scenario");
		return NO;
	}
	const std::optional<std::string> path = ResourceManager::pathForFileNamed(*file, "Scenarios");
	if (!path)
	{
		OO_LOG("scenario.init.error", "Game file not found for scenario {}",*file);
		return NO;
	}
	BOOL result = loadPlayerFromFile(*path, YES);
	if (!result)
	{
		return NO;
	}
	scenarioKey = OptionalStringValue(scenario->find("scenario"));

	// don't drop the save game directory in
	return YES;
}


#if OO_USE_CUSTOM_LOAD_SAVE

std::optional<std::string> PlayerEntity::commanderSelector()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	std::string		dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");
	
	int idx;
	if(handleGUIUpDownArrowKeys())
	{
		int guiSelectedRow=gui->getSelectedRow();
		idx=(guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW && guiSelectedRow != EXITROW)
		{
			showCommanderShip(idx);
		}
		else
		{
			if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
			gui->setText("", CDRDESCROW, GUI_ALIGN_LEFT);
			gui->setText("", CDRDESCROW + 1, GUI_ALIGN_LEFT);
			gui->setText("", CDRDESCROW + 2, GUI_ALIGN_LEFT);
		}

	}
	else
	{
		idx=(gui->getSelectedRow() - STARTROW) + (OOGUIRow)(currentPage * NUMROWS);
	}
	
	// handle page <-- and page --> keys
	if ((checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up)) && (gui->keyForRow(BACKROW) == GUI_KEY_OK))
	{
		currentPage--;
		playMenuPagePrevious();
		lsCommanders(gui, dir, currentPage, std::nullopt);
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
	}
	if ((checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down)) && (gui->keyForRow(MOREROW) == GUI_KEY_OK))
	{
		currentPage++;
		playMenuPageNext();
		lsCommanders(gui, dir, currentPage, std::nullopt);
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
	}
	
	// Enter pressed - find the commander name underneath.
	// ignore Ctrl for the moment - we check for it explicitly later
	if (checkKeyPressIgnoreCtrl(n_key_gui_select, YES)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
	{
		switch (gui->getSelectedRow())
		{
			case EXITROW:
				if (status() == STATUS_START_GAME)
				{
					setGuiToIntroFirstGo(YES);
					return std::nullopt;
				}
				break;
			case BACKROW:
				currentPage--;
				lsCommanders(gui, dir, currentPage, std::nullopt);
				if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
				break;
			case MOREROW:
				currentPage++;
				lsCommanders(gui, dir, currentPage, std::nullopt);
				if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
				break;
			default:
			{
				if (idx < 0 || (std::size_t)idx >= cdrDetailArray.size())  break;	// (-objectAtIndex: raised)
				const oo::PList cdr = cdrDetailArray[idx];
				if (cdr.get<bool>("isSavedGame"))
					return OptionalStringValue(cdr.find("saved_game_path"));
				else
				{
					if (IsCommandModifierKeyDown(gameView)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
					{
						// change directory to the selected path
						const std::string newDir = cdr.get<std::string>("saved_game_path");
						if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setPlayerFileDirectory(newDir);
						dir = newDir;
						currentPage = 0;
						lsCommanders(gui, dir, currentPage, std::nullopt);
						if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
					}
				}
			}
		}
	}
	
	if((gameView != nullptr ? gameView->isDown(27) : false)) // escape key
	{
		setGuiToStatusScreen();
	}
	return std::nullopt;
}


void PlayerEntity::saveCommanderInputHandler()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	std::string		dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");
	
	if (handleGUIUpDownArrowKeys())
	{
		int guiSelectedRow=gui->getSelectedRow();
		int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
		if (guiSelectedRow != MOREROW && guiSelectedRow != BACKROW)
		{
			showCommanderShip(idx);
			if (idx >= 0 && (std::size_t)idx < cdrDetailArray.size() && cdrDetailArray[idx].get<bool>("isSavedGame"))	// don't show things that aren't saved games
				commanderNameString = CommanderSaveName(cdrDetailArray[idx]).value_or("");
			else
				commanderNameString = (gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or("");
		}
		else
		{
			if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
			gui->setText("", CDRDESCROW, GUI_ALIGN_LEFT);
			gui->setText("", CDRDESCROW + 1, GUI_ALIGN_LEFT);
			gui->setText("", CDRDESCROW + 2, GUI_ALIGN_LEFT);
		}
	}
	else
	{
		commanderNameString = (gameView != nullptr ? gameView->getTypedString() : std::optional<std::string>()).value_or("");
	}
	
	if (gameView != nullptr)  gameView->setTypedString(commanderNameString);
	
	gui->setText(oo::str::formatRuntime(OO_DESC("savescreen-commander-name-@"), { commanderNameString }), INPUTROW);
	gui->setColor(OOColor::cyanColor().get(), INPUTROW);
	
	// handle page <-- and page --> keys, and on-screen buttons
	if (((((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && gui->getSelectedRow() == BACKROW) || (checkKeyPress(n_key_gui_arrow_left) || checkKeyPress(n_key_gui_page_up)))
					&& (gui->keyForRow(BACKROW) == GUI_KEY_OK))
	{
		currentPage--;
		lsCommanders(gui, dir, currentPage, std::nullopt);
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
	}
	//
	if (((((gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false) || checkKeyPress(n_key_gui_select)) && gui->getSelectedRow() == MOREROW) || (checkKeyPress(n_key_gui_arrow_right) || checkKeyPress(n_key_gui_page_down)))
					&& (gui->keyForRow(MOREROW) == GUI_KEY_OK))
	{
		currentPage++;
		lsCommanders(gui, dir, currentPage, std::nullopt);
		if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
	}
	
	// ignore Ctrl if pressed together with Enter for the moment - we check for it explicitly immediately after
	if((checkKeyPressIgnoreCtrl(n_key_gui_select, YES)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false)) && !commanderNameString.empty())
	{
		if (IsCommandModifierKeyDown(gameView)||(gameView != nullptr ? gameView->isDown(gvMouseDoubleClick) : false))
		{
			int guiSelectedRow=gui->getSelectedRow();
			int	idx = (guiSelectedRow - STARTROW) + (currentPage * NUMROWS);
			const oo::PList cdr = (idx >= 0 && (std::size_t)idx < cdrDetailArray.size()) ? cdrDetailArray[idx] : oo::PList();	// (-objectAtIndex: raised)
			
			if (!cdr.isNull() && !cdr.get<bool>("isSavedGame"))	// don't open saved games
			{
				// change directory to the selected path
				const std::string newDir = cdr.get<std::string>("saved_game_path");
				if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setPlayerFileDirectory(newDir);
				dir = newDir;
				currentPage = 0;
				lsCommanders(gui, dir, currentPage, std::nullopt);
				if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
			}
		}
		else
		{
			pollControls = YES;
			if (existingNativeSave(commanderNameString))
			{
				if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
				setGuiToOverwriteScreen(commanderNameString);
			}
			else
			{
				nativeSavePlayer(commanderNameString);
				if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
				setGuiToStatusScreen();
			}
		}
	}
	
	if((gameView != nullptr ? gameView->isDown(27) : false)) // escape key
	{
		// get out of here
		pollControls = YES;
		if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetTypedString();
		setGuiToStatusScreen();
	}
}


void PlayerEntity::overwriteCommanderInputHandler()
{
	::MyOpenGLView	*gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	
	handleGUIUpDownArrowKeys();
	
	// Translation issue: we can't confidently use raw Y and N ascii as shortcuts. It's better to use the load-previous-commander keys.
	const std::string valueYes = oo::str::lowercase(OptionalStringValue(UNIVERSE->descriptions()->find("load-previous-commander-yes")).value_or("y"));
	const std::string valueNo = oo::str::lowercase(OptionalStringValue(UNIVERSE->descriptions()->find("load-previous-commander-no")).value_or("n"));
	unsigned char cYes, cNo;
	
	cYes = FirstUnitLowByte(valueYes);	// Use lower byte of unichar.
	cNo = FirstUnitLowByte(valueNo);	// Use lower byte of unichar.
	
	if ((checkKeyPress(n_key_gui_select) && (gui->getSelectedRow() == SAVE_OVERWRITE_YES_ROW))||(gameView != nullptr ? gameView->isDown(cYes) : false)||(gameView != nullptr ? gameView->isDown(cYes - 32) : false))
	{
		pollControls=YES;
		nativeSavePlayer(commanderNameString);
		playSaveOverwriteYes();
		if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
		setGuiToStatusScreen();
	}
	
	if ((checkKeyPress(n_key_gui_select) && (gui->getSelectedRow() == SAVE_OVERWRITE_NO_ROW))||(gameView != nullptr ? gameView->isDown(27) : false)||(gameView != nullptr ? gameView->isDown(cNo) : false)||(gameView != nullptr ? gameView->isDown(cNo - 32) : false))
	{
		// esc or NO was pressed - get out of here
		pollControls=YES;
		playSaveOverwriteNo();
		setGuiToSaveCommanderScreen("");
	}
}

#endif


bool PlayerEntity::loadPlayerFromFile(const std::string &fileToOpen, bool asNew)
{
	/*	TODO: it would probably be better to load by creating a new
		PlayerEntity, verifying that's OK, then replacing the global player.
		
		Actually, it'd be better to separate PlayerEntity into OOPlayer and
		OOPlayerShipEntity. And then move most of OOPlayerShipEntity into
		ShipEntity, and make NPC ships behave more like player ships.
		-- Ahruman
	*/
	
	BOOL			loadedOK = YES;
	oo::PList		fileDic;
	std::optional<std::string>	fail_reason;
	
	if (fileToOpen.empty())	// (was a nil test: every caller passes a non-nil path)
	{
		fail_reason = OO_DESC("loadfailed-no-file-specified");
		loadedOK = NO;
	}
	
	if (loadedOK)
	{
		OO_LOG("load.progress", "{}", "Reading file");
		fileDic = cxx_OOPropertyListFromFile(fileToOpen);
		if (!fileDic.isDict())  fileDic = oo::PList();	// a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
		if (!fileDic.isDict())
		{
			fail_reason = OO_DESC("loadfailed-could-not-load-file");
			loadedOK = NO;
		}
	}

	if (loadedOK)
	{
		OO_LOG("load.progress", "{}", "Restricting scenario");
		std::string scenarioRestrict;
		const std::optional<std::string> savedRestrict = OptionalStringValue(fileDic.find("scenario_restriction"));
		if (savedRestrict)
		{
			scenarioRestrict = *savedRestrict;
		}
		else
		{
			// older save game - use the 'strict' key instead
			BOOL strict = fileDic.get<bool>("strict", NO);
			if (strict)
			{
				scenarioRestrict = std::string(SCENARIO_OXP_DEFINITION_NONE);
			}
			else
			{
				scenarioRestrict = std::string(SCENARIO_OXP_DEFINITION_ALL);
			}
		}

		if (!(UNIVERSE != nullptr ? UNIVERSE->setUseAddOns(scenarioRestrict, YES, YES) : false))
		{
			fail_reason = OO_DESC("loadfailed-saved-game-failed-to-load");
			loadedOK = NO;
		} 
	}
	

	if (loadedOK)
	{
		OO_LOG("load.progress", "{}", "Creating player ship");
		// Check that player ship exists
		const std::optional<std::string>	shipKey = OptionalStringValue(fileDic.find("ship_desc"));
		oo::PList							shipDict;
		
		if (shipKey)  shipDict = OOShipRegistry::sharedRegistry()->shipInfoForKey(*shipKey);
		
		if (shipDict.isNull())
		{
			loadedOK = NO;
			if (shipKey)  fail_reason = oo::str::formatRuntime(OO_DESC("loadfailed-could-not-find-ship-type-@-please-reinstall-the-appropriate-OXP"), { *shipKey });
			else  fail_reason = OO_DESC("loadfailed-invalid-saved-game-no-ship-specified");
		}
	}
	
	if (loadedOK)
	{
		OO_LOG("load.progress", "{}", "Initialising player entity");
		if (!setUpAndConfirmOK(YES, YES))
		{
			fail_reason = OO_DESC("loadfailed-could-not-reset-javascript");
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		OO_LOG("load.progress", "{}", "Loading commander data");
		if (!setCommanderDataFromDictionary(fileDic))
		{
			// this could still be a reset js issue, if switching from strict / unrestricted
			// TODO: use "could not reset js message" if that's the case.
			fail_reason = OO_DESC("loadfailed-could-not-set-up-player-ship");
			loadedOK = NO;
		}
	}
	
	if (loadedOK)
	{
		OO_LOG("load.progress", "{}", "Recording save path");
		if (!asNew)
		{
			save_path = fileToOpen;
		
			if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr && UNIVERSE->getGameView()->getGameController() != nullptr)  UNIVERSE->getGameView()->getGameController()->setPlayerFileToLoad(fileToOpen);
			if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr && UNIVERSE->getGameView()->getGameController() != nullptr)  UNIVERSE->getGameView()->getGameController()->setPlayerFileDirectory(fileToOpen);
		}
	}
	else
	{
		OO_LOG("load.failed", "***** Failed to load saved game \"{}\": {}", oo::str::lastPathComponent(fileToOpen), fail_reason.value_or("unknown error"));
		if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setPlayerFileToLoad("");
		if (UNIVERSE != nullptr)  UNIVERSE->handleGameOver();
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("loadfailed-saved-game-failed-to-load"), 9.0);
		if (fail_reason)  { if (UNIVERSE != nullptr)  UNIVERSE->addMessage(fail_reason, 9.0); }
		return NO;
	}
	
	OO_LOG("load.progress", "{}", "Creating system");
	if (UNIVERSE != nullptr)  UNIVERSE->setTimeAccelerationFactor(TIME_ACCELERATION_FACTOR_DEFAULT);
	if (UNIVERSE != nullptr)  UNIVERSE->setSystemTo(system_id);
	if (UNIVERSE != nullptr)  UNIVERSE->removeAllEntitiesExceptPlayer();
	if (UNIVERSE != nullptr)  UNIVERSE->setGalaxyTo(galaxy_number, YES); // set overridden planet names on long range map
	if (UNIVERSE != nullptr)  UNIVERSE->setUpSpace();
	if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(NO);
	
	OO_LOG("load.progress", "{}", "Resetting player flight variables");
	setDockedAtMainStation();
	::StationEntity *dockedStation = this->dockedStation();
	
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);
	
	if (dockedStation)
	{
		position = (dockedStation != nullptr ? dockedStation->getPosition() : HPVector{});
		setOrientation(kIdentityQuaternion);
		v_forward = vector_forward_from_quaternion(orientation);
		v_right = vector_right_from_quaternion(orientation);
		v_up = vector_up_from_quaternion(orientation);
	}
	
	flightRoll = 0.0;
	flightPitch = 0.0;
	flightYaw = 0.0;
	flightSpeed = 0.0;
	
	setEntityPersonalityInt(PersonalityForCommanderDict(fileDic));
	
	OO_LOG("load.progress", "{}", "Loading system market");
	// dockedStation is always the main station at this point;
	// "localMarket" save key always refers to the main station (system) market
	const oo::PList *market = fileDic.get<oo::PList::Array>("localMarket");
	if (market != nullptr)
	{
		if (dockedStation != nullptr)  dockedStation->setLocalMarket(*market);
	}
	else
	{
		if (dockedStation != nullptr)  dockedStation->initialiseLocalMarket();
	}

	calculateCurrentCargo();
	
	OO_LOG("load.progress", "{}", "Setting scenario key");
	// set scenario key if the scenario allows saving and has one
	const std::optional<std::string> scenario = OptionalStringValue(fileDic.find("scenario_key"));
	scenarioKey.reset();
	if (scenario)
	{
		scenarioKey = *scenario;
	}

	OO_LOG("load.progress", "{}", "Starting JS engine");
	// Remember the savegame target, run js startUp.
	completeSetUpAndSetTarget(NO);
	// run initial system population
	OO_LOG("load.progress", "{}", "Populating initial system");
	if (UNIVERSE != nullptr)  UNIVERSE->populateNormalSpace();

	// might as well start off with a collected JS environment
	OOJavaScriptEngine::sharedEngine()->garbageCollectionOpportunity(YES);
	
	// read saved position vector and primary role, check for an
	// appropriate station at those coordinates, if found, switch
	// docked station to that one.
	const oo::PList *dockedPosNode = fileDic.find("docked_station_position");
	HPVector dockedPos = OOHPVectorFromPList(dockedPosNode, kZeroHPVector);
	const std::string dockedRole = OptionalStringValue(fileDic.find("docked_station_role")).value_or("");
	::StationEntity *saveStation = (UNIVERSE != nullptr ? UNIVERSE->stationWithRole(dockedRole, dockedPos) : nullptr);
	if (saveStation != nil && (saveStation != nullptr ? saveStation->getAllowsSaving() : false))
	{
		setDockedStation(saveStation);
		position = (saveStation != nullptr ? saveStation->getPosition() : HPVector{});
	}
	// and initialise markets for the secondary stations
	const oo::PList *stationMarkets = fileDic.get<oo::PList::Array>("station_markets");
	if (UNIVERSE != nullptr)  UNIVERSE->loadStationMarkets(stationMarkets != nullptr ? *stationMarkets : oo::PList());

	OO_LOG("load.progress", "{}", "Completing JS startup");
	startUpComplete();

	// if the file was specified in the command line at startup, DO NOT suppress the keys!
	if ((UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->finishedLaunching() : false))  { if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp(); }
	if (asNew) 
	{
		gui_screen = GUI_SCREEN_NEWGAME;
	}
	else 
	{
		gui_screen = GUI_SCREEN_LOAD; // force evaluation of new gui screen on startup
	}
	setGuiToStatusScreen();
	if (loadedOK) doWorldEventUntilMissionScreen(OOJSID("missionScreenOpportunity"));  // trigger missionScreenOpportunity immediately after loading
	OO_LOG("load.progress", "{}", "Loading complete");
	return loadedOK;
}


#if OOLITE_USE_APPKIT_LOAD_SAVE

bool PlayerEntity::loadPlayerWithPanel()
{
	NSOpenPanel *oPanel = [NSOpenPanel openPanel];
	
	oPanel.allowsMultipleSelection = NO;
	oPanel.allowedFileTypes = [NSArray arrayWithObject:@"oolite-save"];
	
	if ([oPanel runModal] == NSOKButton)
	{
		NSURL *url = oPanel.URL;
		if (url.isFileURL)
		{
			return loadPlayerFromFile(oo::StdString(url.path), NO);	// the member (bead oo-w9pi2)
		}
	}
	
	return NO;
}


void PlayerEntity::savePlayerWithPanel()
{
	NSSavePanel *sPanel = [NSSavePanel savePanel];
	
	sPanel.allowedFileTypes = [NSArray arrayWithObject:@"oolite-save"];
	sPanel.canSelectHiddenExtension = YES;
	sPanel.nameFieldStringValue = @(lastsaveName().value_or("").c_str());	// the member (bead oo-w9pi2)
	
	if ([sPanel runModal] == NSOKButton)
	{
		NSURL *url = sPanel.URL;
		OOCAssert(url.isFileURL, "Save panel with default configuration should not provide non-file URLs.");
		
		NSString *path = url.path;
		NSString *newName = [path.lastPathComponent stringByDeletingPathExtension];
		
		ShipScriptEventNoCx(this, "playerWillSaveGame", OOJSSTR("STANDARD_SAVE"));
		
		setLastsaveName(oo::StdString(newName));	// the member (bead oo-w9pi2)
		writePlayerToPath(oo::StdString(path));
	}
	setGuiToStatusScreen();
}

#endif


void PlayerEntity::writePlayerToPath(const std::string &path)
{
	std::string		errDesc;
	BOOL			didSave = NO;
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->resetTypedString();

	if (path.empty())
	{
		OO_LOG("save.failed", "***** SAVE ERROR: {} called with nil path.", __PRETTY_FUNCTION__);
		return;
	}

	// The save dictionary as a property list, converted once (its float values stay single reals,
	// written %0.7g as before).
	const oo::PList dict = commanderDataDictionary();
	if (dict.isNull())  errDesc = "could not construct commander data dictionary.";
	else
	{
		didSave = OOWriteXMLPListToFile(dict, path, &errDesc);
	}
	if (didSave)
	{
		if (UNIVERSE != nullptr)  UNIVERSE->clearPreviousMessage();	// allow this to be given time and again
		if (UNIVERSE != nullptr)  UNIVERSE->addMessage(OO_DESC("game-saved"), 2);
		save_path = path;
		if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setPlayerFileToLoad(*save_path);
		if (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr)  UNIVERSE->gameController()->setPlayerFileDirectory(save_path);	// engaged: path, just set
		// no duplicated autosave immediately after a save.
		if (UNIVERSE != nullptr)  UNIVERSE->setAutoSaveNow(NO);
	}
	else
	{
		OO_LOG("save.failed", "***** SAVE ERROR: {}", errDesc);
		OORaiseException("OoliteException", "Attempt to save game to file '%s' failed: %s", path.c_str(), errDesc.c_str());
	}
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
	setGuiToStatusScreen();
}


void PlayerEntity::nativeSavePlayer(const std::string &cdrName)
{
	const std::string dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");
	const std::string savePath = oo::str::appendingPathComponent(dir, SaveFileName(cdrName));

	ShipScriptEventNoCx(this, "playerWillSaveGame", OOJSSTR("STANDARD_SAVE"));

	setLastsaveName(cdrName);
	
	writePlayerToPath(savePath);
}


#if OO_USE_CUSTOM_LOAD_SAVE

void PlayerEntity::setGuiToLoadCommanderScreen()
{
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	const std::string dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");
	
	gui_screen = GUI_SCREEN_LOAD;
	
	gui->clear();
	gui->setTitle(OO_DESC("loadscreen-title"));
	
	currentPage = 0;
	lsCommanders(gui, dir, currentPage, std::nullopt);
	
	gui->setForegroundTextureKey("docked_overlay");
	gui->setBackgroundTextureKey("load_save");
	
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
	
	setShowDemoShips(YES);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::setGuiToSaveCommanderScreen(const std::string &cdrName)
{
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	::MyOpenGLView *gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	const std::string dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");
	
	pollControls = NO;
	gui_screen = GUI_SCREEN_SAVE;
	
	gui->clear();
	gui->setTitle(OO_DESC("savescreen-title"));
	
	currentPage = 0;
	lsCommanders(gui, dir, currentPage, std::nullopt);
	
	gui->setText(OO_DESC("savescreen-commander-name"), INPUTROW);
	gui->setColor(OOColor::cyanColor().get(), INPUTROW);
	gui->setShowTextCursor(YES);
	gui->setCurrentRow(INPUTROW);
	
	gui->setForegroundTextureKey("docked_overlay");
	gui->setBackgroundTextureKey("load_save");
	
	if (gameView != nullptr)  gameView->setTypedString(cdrName);
	if (gameView != nullptr)  gameView->suppressKeysUntilKeyUp();
	
	setShowDemoShips(YES);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(YES);
}


void PlayerEntity::setGuiToOverwriteScreen(const std::string &cdrName)
{
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	::MyOpenGLView*	gameView = (UNIVERSE != nullptr ? UNIVERSE->getGameView() : nullptr);
	
	// Don't poll controls
	pollControls=NO;
	
	gui_screen = GUI_SCREEN_SAVE_OVERWRITE;
	
	gui->clear();
	gui->setTitle(oo::str::formatRuntime(OO_DESC("overwrite-save-commander-@"), { cdrName }));
	
	gui->setText(oo::str::formatRuntime(OO_DESC("overwritescreen-commander-@-already-exists-overwrite-query"), { cdrName }), SAVE_OVERWRITE_WARN_ROW, GUI_ALIGN_CENTER);
	
	gui->setText(OO_DESC("overwritescreen-yes"), SAVE_OVERWRITE_YES_ROW, GUI_ALIGN_CENTER);
	gui->setKey(std::string(GUI_KEY_OK), SAVE_OVERWRITE_YES_ROW);
	
	gui->setText(OO_DESC("overwritescreen-no"), SAVE_OVERWRITE_NO_ROW, GUI_ALIGN_CENTER);
	gui->setKey(std::string(GUI_KEY_OK), SAVE_OVERWRITE_NO_ROW);
	
	gui->setSelectableRange(NSMakeRange(SAVE_OVERWRITE_YES_ROW, 2));
	gui->setSelectedRow(SAVE_OVERWRITE_NO_ROW);
	
	// We can only leave this screen by answering yes or no, or esc. Therefore
	// use a specific overlay, to allow visual reminders of the available options.
	gui->setForegroundTextureKey("overwrite_overlay");
	gui->setBackgroundTextureKey("load_save");
	
	setShowDemoShips(NO);
	if (gameView != nullptr)  gameView->setStringInput(gvStringInputNo);
	if (UNIVERSE != nullptr)  UNIVERSE->enterGUIViewModeWithMouseInteraction(NO);	// FIXME: should be YES, but was NO before introducing new mouse mode stuff. If set to YES, choices can be selected but not activated.
}

void PlayerEntity::lsCommanders(::GuiDisplayGen *gui, const std::string &directory, int page, const std::optional<std::string> &highlightName)
{
	int rangeStart=STARTROW;
	unsigned lastIndex;
	unsigned i;
	int row=STARTROW;
	
	// Commander listing from the save directory's entries as full paths. The old per-entry filter
	// tested `!exists && isDirectory`, which never holds, so it only built the paths.
	std::vector<std::string> cdrArray;
	const oo::fs::Path directoryPath = oo::fs::pathFromUTF8(directory);
	if (oo::fs::fileType(directoryPath) == oo::fs::FileType::directory)
	{
		const auto names = oo::fs::directoryContents(directoryPath);
		if (names)
		{
			for (const std::string &entry : *names)  cdrArray.push_back(oo::str::appendingPathComponent(directory, entry));
		}
	}
	else
	{
		OO_LOG_ERR("savedGame.read.fail.fileNotFound", "File at path '{}' could not be found.", directory);
	}
	
	// get commander details so a brief rundown of the commander's details may
	// be displayed.
	cdrDetailArray.clear();
	
	cdrDetailArray.push_back(oo::PList(oo::PList::Dict{
		{ "isParentFolder", oo::PList("YES") },
		{ "saved_game_path", oo::PList(oo::str::deletingLastPathComponent(directory)) } }));
	
	for (const std::string &path : cdrArray)
	{
		const oo::fs::FileType type = oo::fs::fileType(oo::fs::pathFromUTF8(path));
		
		if (type != oo::fs::FileType::none)
		{
			if (type != oo::fs::FileType::directory && oo::str::lowercase(oo::str::pathExtension(path)) == "oolite-save")
			{
				oo::PList cdr = cxx_OOPropertyListFromFile(path);
				if (!cdr.isDict())  cdr = oo::PList();	// a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
				if (oo::PList::Dict *cdr1 = cdr.getIf<oo::PList::Dict>())
				{
					// okay use the same dictionary but add a 'saved_game_path' attribute
					(*cdr1)["isSavedGame"] = oo::PList("YES");
					(*cdr1)["saved_game_path"] = oo::PList(path);
					cdrDetailArray.push_back(std::move(cdr));
				}
			}
			if (type == oo::fs::FileType::directory && !oo::str::hasPrefix(oo::str::lastPathComponent(path), "."))
			{
				cdrDetailArray.push_back(oo::PList(oo::PList::Dict{
					{ "isFolder", oo::PList("YES") },
					{ "saved_game_path", oo::PList(path) } }));
			}
		}
	}
	
	if(cdrDetailArray.empty())
	{
		// Empty directory; tell the user and exit immediately.
		gui->setText(OO_DESC("loadsavescreen-no-commanders-found"), STARTROW, GUI_ALIGN_CENTER);
		return;
	}

	// sortCommanders: saved_game_path in the locale collation (oo::str::localizedCompare, ICU, as GNUstep sorted it).
	std::stable_sort(cdrDetailArray.begin(), cdrDetailArray.end(), [](const oo::PList &cdr1, const oo::PList &cdr2) {
		return oo::str::localizedCompare(cdr1.get<std::string>("saved_game_path"), cdr2.get<std::string>("saved_game_path")) < 0;
	});
	
	// Do we need to highlight a name?
	int highlightRowOnPage=STARTROW;
	int highlightIdx=0;
	if(highlightName)
	{
		highlightIdx=findIndexOfCommander(*highlightName);
		if(highlightIdx < 0)
		{
			OO_LOG("save.list.commanders.commanderNotFound", "Commander {} doesn't exist, very bad", *highlightName);
			highlightIdx=0;
		}
		
		// figure out what page we need to be on
		page=highlightIdx/NUMROWS;
		highlightRowOnPage=highlightIdx % NUMROWS + STARTROW;
	}
	
	// We now know for certain what page we're on - 
	// set the first index of the first commander on this page.
	unsigned firstIndex=page * NUMROWS;
	
	// Set up the GUI.
	OOGUITabSettings tabStop;
	tabStop[0]=0;
	tabStop[1]=160;
	tabStop[2]=270;
	gui->setTabStops(tabStop);
	
	// clear text lines here
	for (i = EXITROW ; i < ENDROW + 1; i++)
	{
		gui->setText("", i, GUI_ALIGN_LEFT);
		gui->setColor(OOColor::yellowColor().get(), i);
		gui->setKey(std::string(GUI_KEY_SKIP), i);
	}

	gui->setColor(OOColor::greenColor().get(), LABELROW);
	gui->setArray({ OO_DESC("loadsavescreen-commander-name"), OO_DESC("loadsavescreen-rating") }, LABELROW);

	if (page)
	{
		gui->setColor(OOColor::greenColor().get(), STARTROW-1);
		gui->setArray({ OO_DESC("gui-back"), " <-- " }, STARTROW-1);
		gui->setKey(std::string(GUI_KEY_OK), STARTROW-1);
		rangeStart=STARTROW-1;
	}

	if (status() == STATUS_START_GAME)
	{
		gui->setArray({ OO_DESC("oolite-loadsave-exit"), " <----- " }, EXITROW);
		gui->setColor(OOColor::redColor().get(), EXITROW);
		gui->setKey(std::string(GUI_KEY_OK), EXITROW);
		rangeStart = EXITROW;
	}

	
	if (firstIndex + NUMROWS >= cdrDetailArray.size())
	{
		lastIndex=cdrDetailArray.size();
		gui->setSelectableRange(NSMakeRange(rangeStart, rangeStart + NUMROWS + 2));
	}
	else
	{
		lastIndex=(page * NUMROWS) + NUMROWS;
		gui->setColor(OOColor::greenColor().get(), ENDROW);
		gui->setArray({ OO_DESC("gui-more"), " --> " }, ENDROW);
		gui->setKey(std::string(GUI_KEY_OK), ENDROW);
		gui->setSelectableRange(NSMakeRange(rangeStart, MOREROW));
	}
	
	const std::optional<std::string> lastsaveName = this->lastsaveName();
	for (i=firstIndex; i < lastIndex; i++)
	{
		const oo::PList &cdr = cdrDetailArray[i];
		if (cdr.get<bool>("isSavedGame"))
		{
			const std::string ratingDesc = cxx_OODisplayRatingStringFromKillCount(cdr.get<unsigned int>("ship_kills")).value_or("(null)");
			const std::optional<std::string> saveName = CommanderSaveName(cdr);
			gui->setArray({
				" " + saveName.value_or("(null)") + " ",	// @" %@ "
				" " + ratingDesc + " " },
				   row);
			if (lastsaveName && saveName && *lastsaveName == *saveName)
			{
				highlightRowOnPage = row;
			}
			
			gui->setKey(std::string(GUI_KEY_OK), row);
			row++;
		}
		if (cdr.get<bool>("isParentFolder"))
		{
			gui->setArray({ " (..) " + oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) + " ", "" }, row);
			gui->setColor(OOColor::orangeColor().get(), row);
			gui->setKey(std::string(GUI_KEY_OK), row);
			row++;
		}
		if (cdr.get<bool>("isFolder"))
		{
			gui->setArray({ " >> " + oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) + " ", "" }, row);
			gui->setColor(OOColor::orangeColor().get(), row);
			gui->setKey(std::string(GUI_KEY_OK), row);
			row++;
		}
	}
	gui->setSelectedRow(highlightRowOnPage);
	highlightIdx = (highlightRowOnPage - STARTROW) + (currentPage * NUMROWS);
	// show the first ship, this will be the selected row
	showCommanderShip(highlightIdx);
}


// check for an existing saved game...
bool PlayerEntity::existingNativeSave(const std::string &cdrName)
{
	const std::string dir = (UNIVERSE != nullptr && UNIVERSE->gameController() != nullptr ? UNIVERSE->gameController()->playerFileDirectory() : std::optional<std::string>()).value_or("");
	
	const std::string savePath = oo::str::appendingPathComponent(dir, SaveFileName(cdrName));
	return oo::fs::fileExists(oo::fs::pathFromUTF8(savePath));
}


// Get some brief details about the commander file.
void PlayerEntity::showCommanderShip(int cdrArrayIndex)
{
	::GuiDisplayGen *gui=(UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	if (UNIVERSE != nullptr)  UNIVERSE->removeDemoShips();
	if (cdrArrayIndex < 0 || (std::size_t)cdrArrayIndex >= cdrDetailArray.size())  return;	// (-objectAtIndex: raised)
	const oo::PList cdr = cdrDetailArray[cdrArrayIndex];
	
	gui->setText("", CDRDESCROW, GUI_ALIGN_LEFT);
	gui->setText("", CDRDESCROW + 1, GUI_ALIGN_LEFT);
	gui->setText("", CDRDESCROW + 2, GUI_ALIGN_LEFT);
	
	if (cdr.get<bool>("isFolder"))
	{
		const std::string folderDesc = oo::str::formatRuntime(OO_DESC("loadsavescreen-hold-@-and-press-return-to-open-folder-@"), { COMMAND_MODIFIER_KEY, oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) });
		gui->setColor(OOColor::orangeColor().get(), CDRDESCROW);
		gui->addLongText(folderDesc, CDRDESCROW, GUI_ALIGN_LEFT);
		return;
	}
	
	if (cdr.get<bool>("isParentFolder"))
	{
		const std::string folderDesc = oo::str::formatRuntime(OO_DESC("loadsavescreen-hold-@-and-press-return-to-open-parent-folder-@"), { COMMAND_MODIFIER_KEY, oo::str::lastPathComponent(cdr.get<std::string>("saved_game_path")) });
		gui->setColor(OOColor::orangeColor().get(), CDRDESCROW);
		gui->addLongText(folderDesc, CDRDESCROW, GUI_ALIGN_LEFT);
		return;
	}
	gui->setColor(gui->colorFromSetting(std::nullopt, nil).get(), CDRDESCROW);

	if (!cdr.get<bool>("isSavedGame"))  return;	// don't show things that aren't saved games
	
	if (dockedStation() == nil)  setDockedAtMainStation();
	
	// Display the commander's ship.
	const std::optional<std::string>	shipDesc = OptionalStringValue(cdr.find("ship_desc"));
	std::optional<std::string>			shipName;
	oo::PList							shipDict;
	std::string							rating;
	uint16_t							personality = PersonalityForCommanderDict(cdr);
	
	if (shipDesc)  shipDict = OOShipRegistry::sharedRegistry()->shipInfoForKey(*shipDesc);
	if(!shipDict.isNull())
	{
		oo::PList dict = shipDict;
		const oo::PList *subEntStatus = cdr.find("subentities_status");
		// don't add it to the dictionary if there's no subentities_status key
		if (subEntStatus != nullptr && dict.isDict())  (*dict.getIf<oo::PList::Dict>())["subentities_status"] = *subEntStatus;
		showShipyardModel(*shipDesc, dict, personality);
		shipName = OptionalStringValue(shipDict.find("display_name"));
		if (!shipName) shipName = OptionalStringValue(shipDict.find("name"));	// KEY_NAME
	}
	else
	{
		showShipyardModel("oolite-unknown-ship", oo::PList(), personality);
		shipName = OptionalStringValue(cdr.find("ship_name")).value_or("unknown");
		if ((UNIVERSE != nullptr ? UNIVERSE->getUseAddOns() : std::optional<std::string>()) != std::string(SCENARIO_OXP_DEFINITION_ALL))	// nil was not equal either
		{
			*shipName += " - OXPs disabled or not installed";
		}
		else
		{
			*shipName += " - OXP not installed";
		}
	}
	
	// Make a short description of the commander
	const std::string legalDesc = cxx_OODisplayStringFromLegalStatus(cdr.get<int>("legal_status")).value_or("(null)");
	
	rating = cxx_KillCountToRatingAndKillString(cdr.get<unsigned int>("ship_kills"));
	const oo::PList *creditsNode = cdr.find("credits");
	OOCreditsQuantity money = OODeciCreditsFromPList(creditsNode);
	
	// Nikos - Add some more information in the load game screen (current location, galaxy number and timestamp).
	//-------------------------------------------------------------------------------------------------------------------------
	
	int			galNumber;
	std::string	timeStamp;
	// If there is no key containing the name of the current system in
	// the savefile, calculating what it should have been is going to
	// be tricky now that system generation isn't seed based - but
	// this implies a save game well over 5 years old.
	// Leaving the location blank in this case is probably okay
	const std::string	locationName = OptionalStringValue(cdr.find("current_system_name")).value_or("");

	galNumber = cdr.get<int>("galaxy_number") + 1;	// Galaxy numbering starts at 0.

	// %c of a government / economy value 0..23 gives that one UTF-16 unit, U+0000 included (pinned
	// against gnustep-base's -stringWithFormat:, bead oo-3rb.176); oo::str::format keeps the NUL byte.
	std::string locationGov;
	std::string locationEco;
	std::string locationTL;
	if (cdr.find("current_system_techlevel") != nullptr)
	{	
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
	
	gui->addLongText(cdrDesc, CDRDESCROW, GUI_ALIGN_LEFT);
	
}


int PlayerEntity::findIndexOfCommander(const std::string &cdrName)
{
	unsigned i;
	for (i=0; i < cdrDetailArray.size(); i++)
	{
		const std::optional<std::string> currentName = CommanderSaveName(cdrDetailArray[i]);
		if(currentName && cdrName == *currentName)	// -compare: == OOOrderedSame
		{
			return i;
		}
	}
	
	// not found!
	return -1;
}

#endif


namespace
{

uint16_t PersonalityForCommanderDict(const oo::PList &dict)
{
	uint16_t personality = dict.get<unsigned short>("entity_personality", ENTITY_PERSONALITY_INVALID);
	
	if (personality == ENTITY_PERSONALITY_INVALID)
	{
		// For pre-1.74 saved games, generate a default personality based on some hashes.
		// (ooHash of a missing string was a message to nil: 0.)
		const std::optional<std::string> shipDesc = OptionalStringValue(dict.find("ship_desc"));
		const std::optional<std::string> playerName = OptionalStringValue(dict.find("player_name"));
		personality = (shipDesc ? oo::str::ooHash(*shipDesc) : 0) * (playerName ? oo::str::ooHash(*playerName) : 0);
	}
	
	return personality & ENTITY_PERSONALITY_MAX;
}

}	// namespace


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
	if (doubleDeciCredits > 0)
	{
		doubleDeciCredits = round(doubleDeciCredits);
		double threshold = nextafter(kOOMaxCredits, -1);
		
		if (doubleDeciCredits <= threshold)
		{
			return doubleDeciCredits;
		}
		else
		{
			return kOOMaxCredits;
		}
	}
	else
	{
		return 0;
	}
}


OOCreditsQuantity OODeciCreditsFromPList(const oo::PList *value)
{
	if (value != nullptr && value->isReal())	// a real (was a float/double NSNumber, objCType f or d)
	{
		double d = value->doubleValue();
		if (value->isSinglePrecision())  d = static_cast<double>(static_cast<float>(d));	// +numberWithFloat: -doubleValue
		return OODeciCreditsFromDouble(d);
	}
	else
	{
		return oo::plist_get::unsignedLongLongFrom(value, 0);	// the reader OOUnsignedLongLongFromObject forwards to
	}
}
