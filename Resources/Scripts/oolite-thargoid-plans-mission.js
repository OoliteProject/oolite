/*

oolite-thargoid-plans-mission.js

Script for Thargoid plans mission.


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
/*global EquipmentInfo, Timer, galaxyNumber, guiScreen, mission, missionVariables, player, system*/


"use strict";


this.name			= "oolite-thargoid-plans";
this.author			= "Eric Walch";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";


this._cleanUp = function ()
{
	/*	After the mission is complete, it's good 
		practice to remove the event handlers. The
		less event handlers, the smoother the game 
		experience.
		From 1.74, loading a saved game - or restarting
		the game - reloads all world scripts,including
		all handlers. Calling _cleanUp from startUp
		after the mission is finished allows us to keep
		the gaming experience as smooth as possible.
	*/
	delete this.missionScreenOpportunity;
	delete this.systemWillPopulate;
	delete this.systemWillRepopulate;
};


/**** Event handlers ****/

this.startUp = function ()
{
	if (missionVariables.thargplans === "MISSION_COMPLETE")
	{
		this._cleanUp();
	}
};


this.missionScreenOpportunity = function ()
{
	if (!player.ship.docked)
	{
		return;
	}
	
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber === 2)
		{
			if (!missionVariables.thargplans &&
				missionVariables.conhunt === "MISSION_COMPLETE" &&
				player.score > 1280 &&
				system.ID !== 83)
			{
				mission.runScreen({
					titleKey: "thargoid_plans_title",
					messageKey: "thargoid_plans_brief1"
				});
				missionVariables.thargplans = "PRELUDE";
				mission.setInstructionsKey("thargoid_plans_info1");
				mission.markSystem(83);
			}
			else if (missionVariables.thargplans === "PRELUDE" &&
				system.ID === 83)
			{
				mission.unmarkSystem(83);
				mission.runScreen({
					titleKey: "thargoid_plans_title",
					messageKey: "thargoid_plans_brief2",
					model: "thargoid"
				});
				missionVariables.thargplans = "RUNNING";
				mission.setInstructionsKey("thargoid_plans_info2");
				mission.markSystem(36);
			}
			else if (missionVariables.thargplans === "RUNNING" &&
					 system.ID === 36)
			{
				mission.runScreen({
					titleKey: "thargoid_plans_title",
					messageKey: "thargoid_plans_debrief",
					model: "thargoid"
				});
				player.score += 256; // ship kills
				mission.setInstructions(null);  // reset the mission briefing
				missionVariables.thargplans = "MISSION_COMPLETE";
				// for backward compatibility, remove energy_unit.
				if (player.ship.equipmentStatus("EQ_ENERGY_UNIT") !== "EQUIPMENT_UNAVAILABLE")
				{
					// remove the specified equipment, either working or damaged version.
					player.ship.removeEquipment("EQ_ENERGY_UNIT");
				}
				player.ship.awardEquipment("EQ_NAVAL_ENERGY_UNIT");
				// next line handled by condition script instead
				// EquipmentInfo.infoForKey("EQ_NAVAL_ENERGY_UNIT").effectiveTechLevel = 13;
				clock.addSeconds(EquipmentInfo.infoForKey("EQ_NAVAL_ENERGY_UNIT").price + 600); // time to mount the equipment.
				mission.unmarkSystem(36);
				this._cleanUp();
			}
		}
	}
};


this.systemWillPopulate = function()
{
	if (missionVariables.thargplans === "RUNNING" && galaxyNumber === 2)
	{
		// ensure all normal system population is set up first
		worldScripts["oolite-populator"].systemWillPopulate();

		system.setPopulator("oolite-thargoidplans-mission-a",
		{
			priority: 50,
			location: "LANE_WP",
			groupCount: 2,
			callback: function(pos)
			{
				system.addShips("thargoid", 1, pos, 0);
			}
		});
		system.setPopulator("oolite-thargoidplans-mission-b",
		{
			priority: 50,
			location: "WITCHPOINT",
			groupCount: 1,
			callback: function(pos)
			{
				system.addShips("thargoid", 1, pos, 0);
			}
		});
		this._waveCount = 0;
		this._ambushCount = 0;

		// bring a few extra thargoids in shortly after arrival
		this.systemWillRepopulate = function()
		{
			if (this._waveCount <= 4)
			{
				if (Math.random() < 0.5 && this._ambushCount < 2)
				{		
					this._ambushCount++;
					system.addShips("thargoid", 1);
				}
			}
			else
			{
				delete this.systemWillRepopulate;
			}
			this._waveCount++;
		}

		/* Make sure the player doesn't get too much help from other ships! */
		system.setPopulator("oolite-interceptors-witchpoint",null);
		
	}
	else
	{
		delete this.systemWillRepopulate;
	}
}

