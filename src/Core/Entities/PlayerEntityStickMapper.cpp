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

#include "PlayerEntityStickMapper.h"
#include "PlayerEntityControls.h"
#include "PlayerEntityStickProfile.h"
#include "OOJoystickManager.h"
#include "OOTexture.h"
#include "HeadUpDisplay.h"
#include "oofnd/Defaults.hpp"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"


namespace {

// The columns of a row as +arrayWithObjects: took them: up to the first nil.
std::vector<std::string> ColumnsUpToNil(std::initializer_list<std::optional<std::string>> columns)
{
	std::vector<std::string> result;
	for (const std::optional<std::string> &column : columns)
	{
		if (!column.has_value())  break;
		result.push_back(*column);
	}
	return result;
}


// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dict.get<std::string>(key);
}


// -intValue of a value a dictionary held: a string's leading integer, a number truncated.
int IntValueOf(const oo::PList &value)
{
	if (const std::string *string = value.getIf<std::string>())  return oo::str::intValue(*string);
	return static_cast<int>(value.int64Value());
}


// -intValue of the value a dictionary held under key (nil when absent: 0).
int IntValueForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	return value != nullptr ? IntValueOf(*value) : 0;
}


// -boolValue of the value a dictionary held under key (NSString's rule for a string; nil: NO).
bool BoolValueForKey(const oo::PList &dict, std::string_view key)
{
	const oo::PList *value = dict.find(key);
	if (value == nullptr)  return false;
	if (const std::string *string = value->getIf<std::string>())  return oo::defaults_detail::stringBoolValue(*string);
	return value->boolValue();
}


// The string's -length - 5 characters of a stick name, then "..." (UTF-16 units, as before).
std::string TruncatedByFive(const std::string &name)
{
	std::u16string units = oo::utf8ToUtf16(name);
	units.resize(units.size() - 5);
	return oo::utf16ToUtf8(units) + "...";
}


// The -intValue of the part of a GUI key after its first ':' ("Index:3", "More:12").
int NumberAfterColon(const std::string &key)
{
	const std::size_t colon = key.find(':');
	std::string part = colon == std::string::npos ? std::string() : key.substr(colon + 1);
	const std::size_t next = part.find(':');
	if (next != std::string::npos)  part.resize(next);
	return oo::str::intValue(part);
}


// -oo_integerForKey: of an entry that may be absent (nil: 0).
NSInteger IntegerIn(const oo::PList *dict, std::string_view key)
{
	return dict != nullptr ? dict->get<NSInteger>(key) : 0;
}


// stickFunctions entry <index>: a null PList past the end (-objectAtIndex: raised there).
const oo::PList &StickFunctionAt(const std::vector<oo::PList> &entries, NSUInteger index)
{
	static const oo::PList none;
	return (index < entries.size()) ? entries[index] : none;
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

}	// namespace


void PlayerEntity::resetStickFunctions()
{
	stickFunctions.clear();
}


void PlayerEntity::setGuiToStickMapperScreen(unsigned skip)
{
	setGuiToStickMapperScreen(skip, NO);
}

void PlayerEntity::setGuiToStickMapperScreen(unsigned skip, bool resetCurrentRow)
{
	::GuiDisplayGen	*gui = (UNIVERSE != nullptr ? UNIVERSE->getGui() : nullptr);
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();
	const std::vector<std::string>	stickList = stickHandler->listSticks();
	unsigned		stickCount = stickList.size();
	unsigned		i;
	
	OOGUITabStop	tabStop[GUI_MAX_COLUMNS];
	tabStop[0] = 10;
	tabStop[1] = 290;
	tabStop[2] = 400;
	gui->setTabStops(tabStop);
	
	gui_screen = GUI_SCREEN_STICKMAPPER;
	gui->clear();
	gui->setTitle("Configure Joysticks");
	
	for(i=0; i < stickCount; i++)
 	{
		std::string stickNameForThisRow = oo::str::format("Stick %d %s", i+1, stickList[i].c_str());
		// for more than 2 sticks, the stick name rows are populated by more than one name if needed
		std::optional<std::string> stickNameAdditional;
		if (stickCount > 2 && cxx_OOStringWidthInEm(stickNameForThisRow) > 18.0)
		{
			// string is too long, truncate it until its length gets below threshold
			do {
				stickNameForThisRow = TruncatedByFive(stickNameForThisRow);
			} while (cxx_OOStringWidthInEm(stickNameForThisRow) > 18.0);
		}
		unsigned j = i + 2;
		if (j < stickCount)
		{
			stickNameAdditional = oo::str::format("Stick %d %s", j+1, stickList[j].c_str());
			if (cxx_OOStringWidthInEm(*stickNameAdditional) > 11.0)
			{
				// string is too long, truncate it until its length gets below threshold
				do {
				stickNameAdditional = TruncatedByFive(*stickNameAdditional);
				} while (cxx_OOStringWidthInEm(*stickNameAdditional) > 11.0);
			}
		}
		gui->setArray(ColumnsUpToNil({
					   stickNameForThisRow,
					   std::string(),	// skip one column
					   stickNameAdditional }),
			   i + GUI_ROW_STICKNAME);
	}

	gui->setArray(ColumnsUpToNil({ OO_DESC("stickmapper-profile") }), GUI_ROW_STICKPROFILE);
	gui->setKey(std::string(GUI_KEY_OK), GUI_ROW_STICKPROFILE);
	displayFunctionList(gui, skip);
	
	gui->setArray(std::vector<std::string>{ "Select a function and press Enter to modify or 'u' to unset." }, GUI_ROW_INSTRUCT);

	gui->setText(std::optional<std::string>("Space to return to previous screen."), GUI_ROW_INSTRUCT+1, GUI_ALIGN_CENTER);
	
	if (resetCurrentRow)
	{
		gui->setSelectedRow(GUI_ROW_STICKPROFILE);
	}
	if (UNIVERSE != nullptr && UNIVERSE->getGameView() != nullptr)  UNIVERSE->getGameView()->suppressKeysUntilKeyUp();
	gui->setForegroundTextureKey(std::string(status() == STATUS_DOCKED ? "docked_overlay" : "paused_overlay"));
	gui->setBackgroundTextureKey(std::string("settings"));
}


void PlayerEntity::stickMapperInputHandler(::GuiDisplayGen *gui, ::MyOpenGLView *gameView)
{
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();

	// Don't do anything if the user is supposed to be selecting
	// a function - other than look for Escape.
	if(waitingForStickCallback)
	{
		if((gameView != nullptr ? gameView->isDown(27) : false))
		{
			stickHandler->clearCallback();
			gui->setArray(std::vector<std::string>{ "Function setting aborted." }, GUI_ROW_INSTRUCT);
			waitingForStickCallback=NO;
		}

		// Break out now.
		return;
	}
	
	handleGUIUpDownArrowKeys();
	
	if (gui->getSelectedRow() == GUI_ROW_STICKPROFILE && (gameView != nullptr ? gameView->isDown(13) : false))
	{
		setGuiToStickProfileScreen(gui);
		return;
	}
	
	const std::optional<std::string> key = gui->keyForRow(gui->getSelectedRow());
	if (key.has_value() && oo::str::hasPrefix(*key, "Index:"))
		selFunctionIdx=NumberAfterColon(*key);
	else
		selFunctionIdx=-1;

	if((gameView != nullptr ? gameView->isDown(13) : false))
	{
		if (key.has_value() && oo::str::hasPrefix(*key, "More:"))
		{
			int from_function = NumberAfterColon(*key);
			if (from_function < 0)  from_function = 0;
			
			setGuiToStickMapperScreen(from_function);
			if (UNIVERSE->getGui()->getSelectedRow() < 0)
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_FUNCSTART);
			if (from_function == 0)
				UNIVERSE->getGui()->setSelectedRow(GUI_ROW_FUNCSTART + MAX_ROWS_FUNCTIONS - 1);
			return;
		}
		
		const oo::PList &entry = StickFunctionAt(stickFunctions, selFunctionIdx);
		int hw=IntValueForKey(entry, KEY_ALLOWABLE);
		stickHandler->setCallback([this](const oo::PList &hwDict) { updateFunction(hwDict); }, hw);	// was -updateFunction: on the root facade, by name
		
		// Print instructions
		std::string instructions;
		switch(hw)
		{
			case HW_AXIS:
				instructions = "Fully deflect the axis you want to use for this function. Esc aborts.";
				break;
			case HW_BUTTON:
				instructions = "Press the button you want to use for this function. Esc aborts.";
				break;
			default:
				instructions = "Press the button or deflect the axis you want to use for this function.";
		}
		gui->setArray(std::vector<std::string>{ instructions }, GUI_ROW_INSTRUCT);
		waitingForStickCallback=YES;
	}
	
	if((gameView != nullptr ? gameView->isDown('u') : false))
	{
		if (selFunctionIdx >= 0)  removeFunction(selFunctionIdx);
	}
}


// Callback function, called by JoystickHandler when the callback
// is set. The dictionary contains the thing that was pressed/moved.
void PlayerEntity::updateFunction(const oo::PList &hwDict)	// called by name (joystick callback, ADR-0055 item 5)
{
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();
	waitingForStickCallback = NO;
	
	// Right time and the right place?
	if(gui_screen != GUI_SCREEN_STICKMAPPER)
	{
		OO_LOG("joystick.configure.error", "{} called when not on stick mapper screen.", __PRETTY_FUNCTION__);
		return;
	}
	// What moved?
	int function;
	const oo::PList &entry = StickFunctionAt(stickFunctions, selFunctionIdx);
	if(hwDict.get<bool>(std::string(STICK_ISAXIS)))
	{
		function=entry.get<int>(KEY_AXISFN);
		if (function == AXIS_THRUST)
		{
			stickHandler->unsetButtonFunction(BUTTON_INCTHRUST);
			stickHandler->unsetButtonFunction(BUTTON_DECTHRUST);
		}
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		if (function == AXIS_FIELD_OF_VIEW)
		{
			stickHandler->unsetButtonFunction(BUTTON_INC_FIELD_OF_VIEW);
			stickHandler->unsetButtonFunction(BUTTON_DEC_FIELD_OF_VIEW);
		}
#endif
		if (function == AXIS_VIEWX)
		{
			stickHandler->unsetButtonFunction(BUTTON_VIEWPORT);
			stickHandler->unsetButtonFunction(BUTTON_VIEWSTARBOARD);
		}
		if (function == AXIS_VIEWY)
		{
			stickHandler->unsetButtonFunction(BUTTON_VIEWFORWARD);
			stickHandler->unsetButtonFunction(BUTTON_VIEWAFT);
		}
	}
	else
	{
		function = entry.get<int>(KEY_BUTTONFN);
		if (function == BUTTON_INCTHRUST || function == BUTTON_DECTHRUST)
		{
			stickHandler->unsetAxisFunction(AXIS_THRUST);
		}
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
		if (function == BUTTON_INC_FIELD_OF_VIEW || function == BUTTON_DEC_FIELD_OF_VIEW)
		{
			stickHandler->unsetAxisFunction(AXIS_FIELD_OF_VIEW);
		}
#endif
		if (function == BUTTON_VIEWPORT || function == BUTTON_VIEWSTARBOARD)
		{
			stickHandler->unsetAxisFunction(AXIS_VIEWX);
		}
		if (function == BUTTON_VIEWFORWARD || function == BUTTON_VIEWAFT)
		{
			stickHandler->unsetAxisFunction(AXIS_VIEWY);
		}
	}
	// special case for OXP equipment buttons
	if (function >= 10000) 
	{
		std::string key = std::string(CUSTOMEQUIP_BUTTONACTIVATE);
		function -= 10000;
		if (function >= 10000)
		{
			function -= 10000;
			key = std::string(CUSTOMEQUIP_BUTTONMODE);
		}
		// the customEquipActivation entry is edited in place
		if (oo::PList::Dict *custEquipDict = CustomEquipFields(customEquipActivation, function))  (*custEquipDict)[key] = hwDict;
		checkCustomEquipButtons(hwDict, function);
		oo::Defaults::standard().setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
	else 
	{
		stickHandler->setFunction(function, hwDict);
		checkCustomEquipButtons(hwDict, -1);
		stickHandler->saveStickSettings();
	}
	
	// Update the GUI (this will refresh the function list).
	unsigned skip;
	if (selFunctionIdx < MAX_ROWS_FUNCTIONS - 1)
	{
		skip = 0;
	}
	else
	{
		skip = ((selFunctionIdx - 1) / (MAX_ROWS_FUNCTIONS - 2)) * (MAX_ROWS_FUNCTIONS - 2) + 1;
	}
	
	setGuiToStickMapperScreen(skip);
}


void PlayerEntity::checkCustomEquipButtons(const oo::PList &stickFn, int idx)
{
	const std::string stickNumberKey = std::string(STICK_NUMBER);
	const std::string stickAxBtKey = std::string(STICK_AXBUT);
	const std::string activateKey = std::string(CUSTOMEQUIP_BUTTONACTIVATE);
	const std::string modeKey = std::string(CUSTOMEQUIP_BUTTONMODE);
	int i;
	for (i = 0; static_cast<std::size_t>(i) < customEquipActivation.size(); i++)
	{
		if (i != idx) {
			const oo::PList original = customEquipActivation[i];
			oo::PList &custEquip = customEquipActivation[i];	// edited in place
			oo::PList::Dict *custEquipDict = custEquip.getIf<oo::PList::Dict>();
			const oo::PList *bf = original.find(activateKey);
			if (IntegerIn(bf, stickNumberKey) == stickFn.get<NSInteger>(stickNumberKey) &&
				IntegerIn(bf, stickAxBtKey) == stickFn.get<NSInteger>(stickAxBtKey) &&
				custEquip.find(activateKey) != nullptr)
			{
				custEquipDict->erase(activateKey);
			}
			bf = original.find(modeKey);
			if (IntegerIn(bf, stickNumberKey) == stickFn.get<NSInteger>(stickNumberKey) &&
				IntegerIn(bf, stickAxBtKey) == stickFn.get<NSInteger>(stickAxBtKey) &&
				custEquip.find(modeKey) != nullptr)
			{
				custEquipDict->erase(modeKey);
			}
		}
	}
}


void PlayerEntity::removeFunction(int idx)
{
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();
	const oo::PList		&entry = StickFunctionAt(stickFunctions, idx);
	const oo::PList		*butfunc = entry.find(KEY_BUTTONFN);	// -intValue as before
	const oo::PList		*axfunc = entry.find(KEY_AXISFN);
	BOOL				custom = NO;
	selFunctionIdx = idx;
	
	// Some things can have either axis or buttons - make sure we clear
	// both!
	if(butfunc != nullptr)
	{
		// special case for OXP equipment buttons
		if (IntValueOf(*butfunc) >= 10000) 
		{
			int bf = IntValueOf(*butfunc);
			custom = YES;
			std::string key = std::string(CUSTOMEQUIP_BUTTONACTIVATE);
			bf -= 10000;
			if (bf >= 10000)
			{
				bf -= 10000;
				key = std::string(CUSTOMEQUIP_BUTTONMODE);
			}
			// edited in place; both tests reduce to "remove key if present"
			if (oo::PList::Dict *custEquipDict = CustomEquipFields(customEquipActivation, bf))  custEquipDict->erase(key);
		}
		else 
		{
			stickHandler->unsetButtonFunction(IntValueOf(*butfunc));
		}
	}
	if(axfunc != nullptr)
	{
		stickHandler->unsetAxisFunction(IntValueOf(*axfunc));
	}
	if (!custom) 
	{
		stickHandler->saveStickSettings();
	}
	else 
	{
		oo::Defaults::standard().setObject(std::string(KEYCONFIG_CUSTOMEQUIP), oo::PList(customEquipActivation));
	}
	
	unsigned skip;
	if (selFunctionIdx < MAX_ROWS_FUNCTIONS - 1)
		skip = 0;
	else
		skip = ((selFunctionIdx - 1) / (MAX_ROWS_FUNCTIONS - 2)) * (MAX_ROWS_FUNCTIONS - 2) + 1;
	setGuiToStickMapperScreen(skip);
}


void PlayerEntity::displayFunctionList(::GuiDisplayGen *gui, NSUInteger skip)
{
	OOJoystickManager	*stickHandler = OOJoystickManager::sharedStickHandler();
	
	gui->setColor(OOColor::greenColor().get(), GUI_ROW_HEADING);
	gui->setArray(std::vector<std::string>{ "Function", "Assigned to", "Type" }, GUI_ROW_HEADING);

	if(stickFunctions.empty())	// (the list is never empty once built)
	{
		stickFunctions = stickFunctionList();
	}
	const oo::PList assignedAxes = stickHandler->axisFunctions();
	const oo::PList assignedButs = stickHandler->buttonFunctions();
	
	NSUInteger i, n_functions = stickFunctions.size();
	NSInteger n_rows, start_row, previous = 0;
	
	if (skip >= n_functions)
		skip = n_functions - 1;
	
	if (n_functions < MAX_ROWS_FUNCTIONS)
	{
		skip = 0;
		previous = 0;
		n_rows = MAX_ROWS_FUNCTIONS;
		start_row = GUI_ROW_FUNCSTART;
	}
	else
	{
		n_rows = MAX_ROWS_FUNCTIONS  - 1;
		start_row = GUI_ROW_FUNCSTART;
		if (skip > 0)
		{
			n_rows -= 1;
			start_row += 1;
			if (skip > MAX_ROWS_FUNCTIONS)
				previous = skip - (MAX_ROWS_FUNCTIONS - 2);
			else
				previous = 0;
		}
	}
	
	if (n_functions > 0)
	{
		if (skip > 0)
		{
			gui->setColor(OOColor::greenColor().get(), GUI_ROW_FUNCSTART);
			gui->setArray(ColumnsUpToNil({ OO_DESC("gui-back"), std::string(" <-- ") }), GUI_ROW_FUNCSTART);
			gui->setKey(oo::str::format("More:%zd", previous), GUI_ROW_FUNCSTART);
		}
		
		for(i=0; i < (n_functions - skip) && (int)i < n_rows; i++)
		{
			const oo::PList &entry = StickFunctionAt(stickFunctions, i + skip);
			if (entry.find(KEY_HEADER) != nullptr) {
				const std::optional<std::string> header = OptionalStringForKey(entry, KEY_HEADER);
				gui->setArray(ColumnsUpToNil({ header, std::string(), std::string() }), i + start_row);
				gui->setColor(OOColor::cyanColor().get(), i + start_row);
			}
			else
			{
				std::string allowedThings;
				std::optional<std::string> assignment;
				const std::optional<std::string> axFuncKey = OptionalStringForKey(entry, KEY_AXISFN);
				const std::optional<std::string> butFuncKey = OptionalStringForKey(entry, KEY_BUTTONFN);
				// -objectForKey: of a nil key found nothing
				const oo::PList *assignedAxis = axFuncKey.has_value() ? assignedAxes.find(*axFuncKey) : nullptr;
				const oo::PList *assignedButton = butFuncKey.has_value() ? assignedButs.find(*butFuncKey) : nullptr;
				int allowable = entry.get<int>(KEY_ALLOWABLE);
				switch(allowable)
				{
					case HW_AXIS:
						allowedThings="Axis";
						assignment=describeStickDict(assignedAxis);
						break;
					case HW_BUTTON:
						allowedThings="Button";
						int bf; bf = butFuncKey.has_value() ? static_cast<int>(oo::str::longLongValue(*butFuncKey)) : 0;	// -integerValue (nil: 0)
						if (bf < 10000)
						{
							assignment=describeStickDict(assignedButton);
						}
						else
						{
							std::string key = std::string(CUSTOMEQUIP_BUTTONACTIVATE);
							bf -= 10000;
							if (bf >= 10000)
							{
								bf -= 10000;
								key = std::string(CUSTOMEQUIP_BUTTONMODE);
							}
							const oo::PList &custom = CustomEquipEntry(customEquipActivation, bf);
							assignment=describeStickDict(custom.find(key));
						}
						break;
					default:
						allowedThings="Axis/Button";

						// axis has priority
						assignment=describeStickDict(assignedAxis);
						if(!assignment.has_value())
							assignment=describeStickDict(assignedButton);
				}
				
				// Find out what's assigned for this function currently.
				if (!assignment.has_value())
				{
					assignment = "   -   ";
				}

				gui->setArray(ColumnsUpToNil({ OptionalStringForKey(entry, KEY_GUIDESC), assignment, allowedThings }), i + start_row);
				//[gui setKey: GUI_KEY_OK forRow: i + start_row];
				gui->setKey(oo::str::format("Index:%zu", i + skip), i + start_row);
			}
		}
		if (i < n_functions - skip)
		{
			gui->setColor(OOColor::greenColor().get(), start_row + i);
			gui->setArray(ColumnsUpToNil({ OO_DESC("gui-more"), std::string(" --> ") }), start_row + i);
			gui->setKey(oo::str::format("More:%zu", n_rows + skip), start_row + i);
			i++;
		}
		
		gui->setSelectableRange(NSMakeRange(GUI_ROW_STICKPROFILE, i + start_row - GUI_ROW_STICKPROFILE));
	}
	
}


std::optional<std::string> PlayerEntity::describeStickDict(const oo::PList *stickDict)
{
	std::optional<std::string> desc;
	if(stickDict != nullptr)
	{
		// -intValue / -boolValue of the objects the dictionary held, as before
		int thingNumber=IntValueForKey(*stickDict, STICK_AXBUT);
		int stickNumber=IntValueForKey(*stickDict, STICK_NUMBER);
		// Button or axis?
		if(BoolValueForKey(*stickDict, STICK_ISAXIS))
		{
			desc=oo::str::format("Stick %d axis %d",
				  stickNumber+1, thingNumber+1);
		}
		else if(thingNumber >= MAX_REAL_BUTTONS)
		{
			static const char dir[][6] = { "up", "right", "down", "left" };
			desc=oo::str::format("Stick %d hat %d %s",
				  stickNumber+1, (thingNumber - MAX_REAL_BUTTONS) / 4 + 1,
				  dir[thingNumber & 3]);
		}
		else
		{
			desc=oo::str::format("Stick %d button %d",
				  stickNumber+1, thingNumber+1);
		}
	}
	return desc;
}


std::string PlayerEntity::hwToString(int hwFlags)
{
	std::string hwString;
	switch(hwFlags)
	{
		case HW_AXIS:
			hwString = "axis";
			break;
		case HW_BUTTON:
			hwString = "button";
			break;
		default:
			hwString = "axis/button";
	}
	return hwString;   
}


// TODO: This data could be put into a plist (i18n or just modifiable by
// the user). It is otherwise an ugly method, but it'll do for testing.
std::vector<oo::PList> PlayerEntity::stickFunctionList()
{
	std::vector<oo::PList> funcList;

	// propulsion	
	funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-propulsion")));
	funcList.push_back( 
	 makeStickGuiDict(OO_DESC("stickmapper-roll"), HW_AXIS, AXIS_ROLL, STICK_NOFUNCTION));
	funcList.push_back( 
	 makeStickGuiDict(OO_DESC("stickmapper-pitch"), HW_AXIS, AXIS_PITCH, STICK_NOFUNCTION));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-yaw"), HW_AXIS, AXIS_YAW, STICK_NOFUNCTION));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-increase-thrust"), HW_AXIS|HW_BUTTON, AXIS_THRUST, BUTTON_INCTHRUST));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-decrease-thrust"), HW_AXIS|HW_BUTTON, AXIS_THRUST, BUTTON_DECTHRUST));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-fuel-injection"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_FUELINJECT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-hyperspeed"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_HYPERSPEED));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-hyperdrive"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_HYPERDRIVE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-gal-hyperdrive"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_GALACTICDRIVE));

	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-roll/pitch-precision-toggle"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_PRECISION));

	// navigation
	funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-navigation")));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-compass-mode-next"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_COMPASSMODE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-compass-mode-prev"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_COMPASSMODE_PREV));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-scanner-zoom"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_SCANNERZOOM));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-scanner-unzoom"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_SCANNERUNZOOM));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-view-forward"), HW_AXIS|HW_BUTTON, AXIS_VIEWY, BUTTON_VIEWFORWARD));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-view-aft"), HW_AXIS|HW_BUTTON, AXIS_VIEWY, BUTTON_VIEWAFT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-view-port"), HW_AXIS|HW_BUTTON, AXIS_VIEWX, BUTTON_VIEWPORT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-view-starboard"), HW_AXIS|HW_BUTTON, AXIS_VIEWX, BUTTON_VIEWSTARBOARD));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-ext-view-cycle"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_EXTVIEWCYCLE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-toggle-ID"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ID));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-docking-clearance"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_DOCKINGCLEARANCE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-dockcpu"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_DOCKCPU));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-dockcpufast"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_DOCKCPUFAST));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-docking-music"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_DOCKINGMUSIC));

	// offensive
	funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-offensive")));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-weapons-online-toggle"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_WEAPONSONLINETOGGLE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-primary-weapon"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_FIRE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-secondary-weapon"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_LAUNCHMISSILE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-arm-secondary"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ARMMISSILE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-disarm-secondary"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_UNARM));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-target-nearest-incoming-missile"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_TARGETINCOMINGMISSILE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-cycle-secondary"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_CYCLEMISSILE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-next-target"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_NEXTTARGET));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-previous-target"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_PREVTARGET));

	// defensive
	funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-defensive")));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-ECM"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ECM));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-jettison"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_JETTISON));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-rotate-cargo"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ROTATECARGO));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-escape-pod"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ESCAPE));

	// oxp special equip
	funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-special-equip")));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-mfd-select-next"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_MFDSELECTNEXT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-mfd-select-prev"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_MFDSELECTPREV));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-mfd-cycle-next"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_MFDCYCLENEXT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-mfd-cycle-prev"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_MFDCYCLEPREV));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-prime-equipment"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_PRIMEEQUIPMENT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-prime-prev-equipment"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_PRIMEEQUIPMENT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-activate-equipment"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ACTIVATEEQUIPMENT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-mode-equipment"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_MODEEQUIPMENT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-fastactivate-a"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_CLOAK));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-fastactivate-b"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_ENERGYBOMB));

	// misc
	funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-misc")));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-snapshot"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_SNAPSHOT));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-pause"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_PAUSE));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-toggle-hud"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_TOGGLEHUD));
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-comms-log"), HW_BUTTON, STICK_NOFUNCTION, BUTTON_COMMSLOG));
#if OO_FOV_INFLIGHT_CONTROL_ENABLED
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-increase-field-of-view"), HW_AXIS|HW_BUTTON, AXIS_FIELD_OF_VIEW, BUTTON_INC_FIELD_OF_VIEW));	// the member (bead oo-w9pi2)
	funcList.push_back(
	 makeStickGuiDict(OO_DESC("stickmapper-decrease-field-of-view"), HW_AXIS|HW_BUTTON, AXIS_FIELD_OF_VIEW, BUTTON_DEC_FIELD_OF_VIEW));
#endif
	if (customEquipActivation.size() > 0) {
		funcList.push_back(makeStickGuiDictHeader(OO_DESC("stickmapper-header-oxp-equip")));
		int i;
		for (i = 0; static_cast<std::size_t>(i) < customEquipActivation.size(); i++)
		{
			funcList.push_back(
			makeStickGuiDict(oo::str::format("Activate '%s'", OptionalStringForKey(customEquipActivation[i], std::string(CUSTOMEQUIP_EQUIPNAME)).value_or("(null)").c_str()), HW_BUTTON, STICK_NOFUNCTION, (i+10000)));
			funcList.push_back(
			makeStickGuiDict(oo::str::format("Mode '%s'", OptionalStringForKey(customEquipActivation[i], std::string(CUSTOMEQUIP_EQUIPNAME)).value_or("(null)").c_str()), HW_BUTTON, STICK_NOFUNCTION, (i+20000)));
		}

	}
	return funcList;
}


oo::PList PlayerEntity::makeStickGuiDict(const std::string &what, int allowable, int axisfn, int butfn)
{
	oo::PList::Dict guiDict;

	// -length / -substringToIndex: count UTF-16 units
	const std::u16string units = oo::utf8ToUtf16(what);
	guiDict[KEY_GUIDESC] = units.size() > 50 ? oo::utf16ToUtf8(units.substr(0, 28)) + "..." : what;
	guiDict[KEY_ALLOWABLE] = oo::PList::signedInteger(allowable);	// +numberWithInt:
	if(axisfn >= 0)
		guiDict[KEY_AXISFN] = oo::PList::signedInteger(axisfn);
	if(butfn >= 0)
		guiDict[KEY_BUTTONFN] = oo::PList::signedInteger(butfn);
	return oo::PList(std::move(guiDict));
}

oo::PList PlayerEntity::makeStickGuiDictHeader(const std::string &header)
{
	oo::PList::Dict guiDict;
	guiDict[KEY_HEADER] = header;
	guiDict[KEY_ALLOWABLE] = "";
	guiDict[KEY_AXISFN] = "";
	guiDict[KEY_BUTTONFN] = "";
	return oo::PList(std::move(guiDict));
}


