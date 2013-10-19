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
this.version		= "1.79";

this.startUpComplete = this.shipDockedWithStation = this.playerBoughtEquipment = this.playerBoughtNewShip = function()
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
	for (var i=0;i<equipment.length;i++)
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
	if (choice != "") 
	{
		player.ship.fastEquipmentA = choice;
		if (choice == "ZZZZZZ_OOLITE_EQ_NONE")
		{
			if (player.ship.equipmentStatus("EQ_CLOAKING_DEVICE") == "EQUIPMENT_UNAVAILABLE")
			{
				/* for compatibility, if the player hasn't got the
				 * cloaking device yet, and they set fast-A to none,
				 * set it so that when they get the cloaking device it
				 * takes this slot. */
				player.ship.fastEquipmentA = "EQ_CLOAKING_DEVICE";
			}
		}
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
	if (choice != "") 
	{
		player.ship.fastEquipmentB = choice;
		if (choice == "ZZZZZZ_OOLITE_EQ_NONE")
		{
			if (player.ship.equipmentStatus("EQ_ENERGY_BOMB") == "EQUIPMENT_UNAVAILABLE")
			{
				/* for compatibility, if the player hasn't got the
				 * energy bomb yet, but they've installed an OXP which
				 * recreates it, and they set fast-B to none, set it
				 * so that when they get the energy bomb it takes this
				 * slot. */
				player.ship.fastEquipmentB = "EQ_ENERGY_BOMB";
			}
		}

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