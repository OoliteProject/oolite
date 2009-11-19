/*

oolite-thargoid-plans-mission.js

Script for Thargoid plans mission.


Oolite
Copyright © 2004-2008 Giles C Williams and contributors

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


/*jslint bitwise: true, undef: true, eqeqeq: true, immed: true, newcap: true*/
/*global EquipmentInfo, Timer, galaxyNumber, guiScreen, mission, missionVariables, player, system*/


this.name			= "oolite-thargoid-plans";
this.author			= "Eric Walch";
this.copyright		= "© 2008–2009 the Oolite team.";
this.version		= "1.74";


this.missionOffers = function ()
{
	if (!player.ship.docked)  { return; }
	
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber === 2)
		{
			if (!missionVariables.thargplans &&
				missionVariables.conhunt === "MISSION_COMPLETE" &&
				player.score > 1280 &&
				system.ID !== 83)
			{
				mission.runScreen({titleKey:"thargoid_plans_title", messageKey:"thargoid_plans_brief1"}, null);
				missionVariables.thargplans = "PRELUDE";
				mission.setInstructionsKey("thargoid_plans_info1");
				mission.markSystem(83);
			}
			else if (missionVariables.thargplans === "PRELUDE" &&
				system.ID === 83)
			{
				mission.unmarkSystem(83);
				mission.runScreen({titleKey:"thargoid_plans_title", messageKey:"thargoid_plans_brief2", model: "thargoid"}, null);
				missionVariables.thargplans = "RUNNING";
				mission.setInstructionsKey("thargoid_plans_info2");
				mission.markSystem(36);
			}
			else if (missionVariables.thargplans === "RUNNING" &&
					 system.ID === 36)
			{
				mission.runScreen({titleKey:"thargoid_plans_title", messageKey:"thargoid_plans_debrief", model: "thargoid"}, null);
				player.score += 256; // ship kills
				mission.setInstructions(null);  // reset the mission briefing
				missionVariables.thargplans = "MISSION_COMPLETE";
				// for backward compatibility, hasEquipment doesn't check the damaged version.
				if (player.ship.hasEquipment("EQ_ENERGY_UNIT") || player.ship.hasEquipment("EQ_ENERGY_UNIT_DAMAGED"))
				{
					// remove the specified equipment, either working or damaged version.
					player.ship.removeEquipment("EQ_ENERGY_UNIT");
				}
				player.ship.awardEquipment("EQ_NAVAL_ENERGY_UNIT");
				EquipmentInfo.infoForKey("EQ_NAVAL_ENERGY_UNIT").effectiveTechLevel = 13;
				mission.unmarkSystem(36);
				this.cleanUp();
			}
		}
	}
};


this.addTargoids = function ()
{
	this.loopcount++; // 5 loops of adding in the legacy script with a script timer.
	if (this.loopcount > 5)
	{
		this.targoidTimer.stop();
		return;
	}
	if (system.countShipsWithRole("thargoid") < 2)
	{
		system.legacy_addSystemShips("thargoid", 1, 0.33);
		system.legacy_addSystemShips("thargoid", 1, 0.66);
	}
	if (system.countShipsWithRole("thargoid") < 5 && Math.random() < 0.5)
	{
		system.legacy_addShips("thargoid", 1);
	}
};


this.setUpShips = function ()
{
	if (missionVariables.thargplans === "RUNNING" && galaxyNumber === 2)
	{
		if (this.targoidTimer)
		{
			this.targoidTimer.start();
		}
		else
		{
			this.targoidTimer = new Timer(this, this.addTargoids, 10, 10);
		}
	}
};


this.cleanUp = function()
{
	/*	After the mission is complete, it's good 
		practice to remove the event handlers. The
		less event handlers, the smoother the game 
		experience.
		From 1.74, loading a savegame - or restarting
		the game - reloads all world scripts,including
		all handlers. Calling cleanUp from startUp
		after the mission is finished allows us to keep
		the gaming experience as smooth as possible.
	*/
	delete this.missionScreenOpportunity;
	delete this.shipLaunchedFromStation;
	delete this.shipExitedWitchspace;
}


/**** Event handlers ****/


this.startUp = function ()
{
	this.loopcount = 0;  // should be zero on the first launch after a reset.
	if (missionVariables.thargplans === "MISSION_COMPLETE") { this.cleanUp(); }
};


this.missionScreenOpportunity = function ()
{
	this.missionOffers();
};


this.shipLaunchedFromStation = function ()
{
	this.setUpShips();
};


this.shipExitedWitchspace = function ()
{
	this.loopcount = 0;
	this.setUpShips();
};
