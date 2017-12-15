/*

oolite-primable-equipment-manager.js

Allocate primable equipment to the two 'fast activate' buttons.


Oolite
Copyright © 2004-2013 Giles C Williams and contributors

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


/*jslint white: true, undef: true, eqeqeq: true, bitwise: true, regexp: true, newcap: true, immed: true */
/*global missionVariables, player*/


"use strict";


this.name			= "oolite-primable-equipment-register";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";

this.$page = 0;

this.startUpComplete = this.shipDockedWithStation = this.playerBoughtNewShip = function()
{
	this._initialiseInterface();
}


this.playerBoughtEquipment = function(eqkey)
{
	this._initialiseInterface();
	this._updatePrimableEquipmentSettings(eqkey,false);
}


this._updatePrimableEquipmentSettings = function(eqkey,quiet)
{
	/* If the player has gained some equipment which is recommended
	 * for fast activation, and the activation slot has nothing in it,
	 * assign to that slot. */
	var info = EquipmentInfo.infoForKey(eqkey);
	
	if (info.fastAffinityDefensive && player.ship.equipmentStatus(player.ship.fastEquipmentA) != "EQUIPMENT_OK" && player.ship.equipmentStatus(player.ship.fastEquipmentA) != "EQUIPMENT_DAMAGED")
	{
		// no installed equipment in fast slot A, so assign this
		player.ship.fastEquipmentA = eqkey;
		if (!quiet)
		{
			player.consoleMessage(expandDescription("[oolite-primablemanager-notify-assign]",{
				"oolite-primable-equipment": info.name,
				"oolite-primable-slot": expandDescription("[oolite-primablemanager-slot-defensive]")
			}),7.5);
			player.consoleMessage(expandDescription("[oolite-primablemanager-notify-setup]"),7.5);
		}
	} 
	else if (info.fastAffinityOffensive && player.ship.equipmentStatus(player.ship.fastEquipmentB) != "EQUIPMENT_OK" && player.ship.equipmentStatus(player.ship.fastEquipmentB) != "EQUIPMENT_DAMAGED")
	{
		// no installed equipment in fast slot B, so assign this
		player.ship.fastEquipmentB = eqkey;
		if (!quiet)
		{
			player.consoleMessage(expandDescription("[oolite-primablemanager-notify-assign]",{
				"oolite-primable-equipment": info.name,
				"oolite-primable-slot": expandDescription("[oolite-primablemanager-slot-offensive]")
			}),7.5);
			player.consoleMessage(expandDescription("[oolite-primablemanager-notify-setup]"),7.5);
		}
	}


}


this._initialiseInterface = function()
{
	if (player.ship.dockedStation)
	{
		var definition = null;
		if (this._equipmentWithScripts().length > 0)
		{
			definition = {
				title: expandMissionText("oolite-primablemanager-interface-title"),
				category: expandMissionText("oolite-primablemanager-interface-category"),
				summary: expandMissionText("oolite-primablemanager-interface-summary"),
				callback: this._configurePrimableEquipment.bind(this)
			};
		}
		player.ship.dockedStation.setInterface("oolite-primable-equipment-manager",definition);
	}
}


this._equipmentWithScripts = function()
{
	var result = [];
	var equipment = player.ship.equipment;
	for (var i=0;i<equipment.length;i++)
	{
		if (equipment[i].scriptName != "")
		{
			result.push(equipment[i]);
		}
	}
	return result;
}


this._nameEquipment = function(key) 
{
	var equipment = this._equipmentWithScripts();
	for (var i=0;i<equipment.length;i++)
	{
		if (equipment[i].equipmentKey == key)
		{
			return equipment[i].name;
		}
	}	
	return expandMissionText("oolite-primablemanager-select-none");
}


this._equipmentChoices = function(current) {
	var choices = {};
	var equipment = this._equipmentWithScripts();
	var chosen = false;
	var choice;

	var rows = this._calculateRows() - 3; // 1 for text line, 1 for "select none", 1 for space
	var addNextPrev = false;
	if (equipment.length > (rows - 2)) 
	{
		addNextPrev = true;
		rows -= 2;
	}
	var start = (this.$page * rows);
	var end = (start + rows) - 1;
	if (end > equipment.length - 1) end = equipment.length - 1;

	// work out if the currently selected item is not visible on the current page and make sure it's always visible
	if (addNextPrev === true) {
		for (var i = 0; i < equipment.length; i++) 
		{
			if (equipment[i].equipmentKey == current) 
			{
				if (i < start || i > end) {
					choice = {
						text: equipment[i].name
					}
					if (equipment[i].equipmentKey == current)
					{
						choice.color = "greenColor";
						choice.text += " "+expandMissionText("oolite-primablemanager-selected-text");
						chosen = true;
					}
					choices[equipment[i].equipmentKey] = choice;
				}
			}
		}
	}
	for (var i=start;i<=end;i++)
	{
		choice = {
			text: equipment[i].name
		}
		if (equipment[i].equipmentKey == current)
		{
			choice.color = "greenColor";
			choice.text += " "+expandMissionText("oolite-primablemanager-selected-text");
			chosen = true;
		}
		choices[equipment[i].equipmentKey] = choice;
	}
	choice = {
		text: expandMissionText("oolite-primablemanager-select-none")
	};
	if (!chosen)
	{
		choice.color = "greenColor";
		choice.text += " "+expandMissionText("oolite-primablemanager-selected-text");
	}
	choices["ZZZZZZ_OOLITE_EQ_NONE"] = choice;

	if (addNextPrev) 
	{
		choice = {
			text: expandMissionText("oolite-primablemanager-next"), 
			unselectable: end >= equipment.length - 1, 
			color: end >= equipment.length - 1 ? "grayColor" : "yellowColor"
		};
		choices["ZZZZZZZ_OOLITE_1_NEXT"] = choice;
		choice = {
			text: expandMissionText("oolite-primablemanager-previous"), 
			unselectable: start <= 0, 
			color: start <= 0 ? "grayColor" : "yellowColor"
		};
		choices["ZZZZZZZ_OOLITE_2_PREV"] = choice;
	}

	return choices;
}

this._initialChoice = function(key)
{
	if (player.ship.equipmentStatus(key) == "EQUIPMENT_OK" || player.ship.equipmentStatus(key) == "EQUIPMENT_DAMAGED")
	{
		return key;
	}
	return "ZZZZZZ_OOLITE_EQ_NONE";
}

this._configurePrimableEquipment = function()
{
	mission.runScreen({
		titleKey: "oolite-primablemanager-page1-title",
		messageKey: "oolite-primablemanager-setup-text",
		choices: this._equipmentChoices(player.ship.fastEquipmentA),
		initialChoicesKey: this._initialChoice(player.ship.fastEquipmentA),
		exitScreen: "GUI_SCREEN_INTERFACES",
		screenID: "oolite-primablemanager"
	},this._configureStage2.bind(this));
}

this._configureStage2 = function(choice)
{
	if (choice === "ZZZZZZZ_OOLITE_1_NEXT") 
	{
		this.$page++;
		this._configurePrimableEquipment();
		return;
	}
	if (choice === "ZZZZZZZ_OOLITE_2_PREV")
	{
		this.$page--;
		this._configurePrimableEquipment();
		return;
	}
	if (choice != "" && choice != null) 
	{
		player.ship.fastEquipmentA = choice;
		this.$page = 0;
	}
	mission.runScreen({
		titleKey: "oolite-primablemanager-page2-title",
		messageKey: "oolite-primablemanager-setup-text",
		choices: this._equipmentChoices(player.ship.fastEquipmentB),
		initialChoicesKey: this._initialChoice(player.ship.fastEquipmentB),
		exitScreen: "GUI_SCREEN_INTERFACES",
		screenID: "oolite-primablemanager"
	},this._configureStage3.bind(this));
}

this._configureStage3 = function(choice)
{
	if (choice === "ZZZZZZZ_OOLITE_1_NEXT") 
	{
		this.$page++;
		this._configureStage2();
		return;
	}
	if (choice === "ZZZZZZZ_OOLITE_2_PREV")
	{
		this.$page--;
		this._configureStage2();
		return;
	}
	if (choice != "" && choice != null) 
	{
		player.ship.fastEquipmentB = choice;
		this.$page = 0;
	}
	var message = expandMissionText("oolite-primablemanager-completed",{
		"oolite-primable-a" : this._nameEquipment(player.ship.fastEquipmentA),
		"oolite-primable-b" : this._nameEquipment(player.ship.fastEquipmentB)
	});

	mission.runScreen({
		titleKey: "oolite-primablemanager-page3-title",
		message: message,
		exitScreen: "GUI_SCREEN_INTERFACES",
		screenID: "oolite-primablemanager"
	});
}

this._calculateRows = function() {
	var p = player.ship;
	var reset = false;
	if (p.hudHidden === true) {
		reset = true;
		p.hudHidden = false;
	}
	var check = p.hudAllowsBigGui;
	if (reset === true) p.hudHidden = true;
	if (check) {
		return 27;
	}
	return 21;
}