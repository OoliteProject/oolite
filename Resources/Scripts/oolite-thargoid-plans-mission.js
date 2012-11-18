/*

oolite-thargoid-plans-mission.js

Script for Thargoid plans mission.


Oolite
Copyright © 2004-2012 Giles C Williams and contributors

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
this.copyright		= "© 2008-2012 the Oolite team.";
this.version		= "1.77";


this._setUpShips = function ()
{
	function addThargoids()
	{
		this._waveCount++; // 5 loops of adding in the legacy script with a script timer.
		if (this._waveCount > 5)
		{
			this._thargoidTimer.stop();
			return;
		}
		if (system.countShipsWithRole("thargoid") < 2)
		{
			system.addShipsToRoute("thargoid", 1, 0.33);
			system.addShipsToRoute("thargoid", 1, 0.66);
		}
		if (system.countShipsWithRole("thargoid") < 5 && Math.random() < 0.5)
		{
			system.addShips("thargoid", 1);
		}
	}
	
	if (missionVariables.thargplans === "RUNNING" && galaxyNumber === 2)
	{
		if (this._thargoidTimer)
		{
			this._thargoidTimer.start();
		}
		else
		{
			this._thargoidTimer = new Timer(this, addThargoids, 10, 10);
		}
	}
};


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
	delete this.shipLaunchedFromStation;
	delete this.shipExitedWitchspace;
};


/**** Event handlers ****/

this.startUp = function ()
{
	this._waveCount = 0;  // should be zero on the first launch after a reset.
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


this.shipLaunchedFromStation = function ()
{
	this._setUpShips();
};


this.shipExitedWitchspace = function ()
{
	this._waveCount = 0;
	this._setUpShips();
};
