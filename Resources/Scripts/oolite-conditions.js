/*

oolite-conditions.js

Conditions script for built-in equipment and ships


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


this.name			= "oolite-conditions";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";


/* contexts: npc, purchase, scripted, newShip, (loading), (damage), (portable) */
this.allowAwardEquipment = function(equipment, ship, context)
{
	if (equipment == "EQ_NAVAL_ENERGY_UNIT")
	{
		// Naval Energy Unit purchase (including repair) by player
		// requires Thargoid Plans complete
		if (context == "purchase" && missionVariables.thargplans != "MISSION_COMPLETE")
		{
			return false;
		}
	}

	if (equipment == "EQ_CLOAKING_DEVICE")
	{
		// Cloaking Device can't be purchased by player, can be repaired
		if (context == "purchase" && player.ship.equipmentStatus("EQ_CLOAKING_DEVICE") != "EQUIPMENT_DAMAGED")
		{
			return false;
		}
		// Never found on ships in shipyards
		if (context == "newShip")
		{
			return false;
		}
	}

	if (equipment == "EQ_OOLITE_TUTORIAL_CONTROLS")
	{
		if (context == "purchase" || context == "npc" || context == "newShip" || context == "scripted")
		{
			return false;
		}
	}

	// OXP hook to allow stations to forbid specific equipment
	if (context == "purchase" && player.ship.dockedStation && player.ship.dockedStation.scriptInfo["oolite-barred-equipment"])
	{
		if (player.ship.dockedStation.scriptInfo["oolite-barred-equipment"].indexOf(equipment) != -1)
		{
			return false;
		}
	}

	// OXP hook to allow ships to forbid specific "available to all" equipment
	if (ship.scriptInfo["oolite-barred-equipment"] && ship.scriptInfo["oolite-barred-equipment"].indexOf(equipment) != -1)
	{
		return false;
	}

	// otherwise allowed
	return true;
}
