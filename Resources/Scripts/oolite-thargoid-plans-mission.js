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


this.name		= "oolite-thargoid-plans";
this.author  	= "eric walch";
this.copyright   = "© 2008 the Oolite team.";
this.version 	= "1.73";


this.missionOffers = function ()
{
	if (guiScreen == "GUI_SCREEN_MISSION" || (mission.choice && mission.choice != "") || !player.ship.docked)  return;
	// there will be a "missionScreenEnded" or a "missionChoiceWasReset" in future to react to.
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber == 2)
		{
			if (!missionVariables.thargplans &&
				missionVariables.conhunt == "MISSION_COMPLETE" &&
				player.score > 1280 &&
				system.ID != 83)
			{
				mission.runMissionScreen("thargoid_plans_intro_brief");
				missionVariables.thargplans = "PRELUDE";
				mission.setInstructionsKey("thargplans_short_desc1");
				mission.markSystem(83);
			}
			else if (missionVariables.thargplans == "PRELUDE" &&
				system.ID == 83)
			{
				mission.unmarkSystem(83);
				mission.runMissionScreen("thargoid_plans_main_brief", null, null, "thargoid");
				missionVariables.thargplans = "RUNNING";
				mission.setInstructionsKey("thargplans_short_desc2");
				mission.markSystem(36);
			}
			else if (missionVariables.thargplans == "RUNNING" &&
					 system.ID == 36)
			{
				mission.runMissionScreen("thargoid_plans_debrief", null, null, "thargoid");
				player.score += 256; // ship kills
				mission.setInstructionsKey(null);  // reset the missionbriefing
				missionVariables.thargplans = "MISSION_COMPLETE";
				if (player.ship.hasEquipment("EQ_ENERGY_UNIT"))
				{
					player.ship.removeEquipment("EQ_ENERGY_UNIT");
				}
				else if (player.ship.hasEquipment("EQ_ENERGY_UNIT_DAMAGED"))
				{
					player.ship.removeEquipment("EQ_ENERGY_UNIT_DAMAGED");
				}
				player.ship.awardEquipment("EQ_NAVAL_ENERGY_UNIT");
				EquipmentInfo.infoForKey("EQ_NAVAL_ENERGY_UNIT").effectiveTechLevel = 13;
				mission.unmarkSystem(36);
			}
		}
	}
}


this.addTargoids = function ()
{
	this.loopcount++; // 5 loops of adding in the legacy script with a script timer.
	if (this.loopcount > 5)
	{
		this.targoidTimer.stop;
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
}


this.setUpShips = function ()
{
	if (missionVariables.thargplans == "RUNNING" && galaxyNumber == 2)
	{
		if (this.targoidTimer)  this.targoidTimer.start();
		else  this.targoidTimer = new Timer(this, this.addTargoids, 10, 10);
	}
}


/**** Event handlers ****/
this.startUp = this.reset = function ()
{
	this.loopcount = 0;  // should be zero on the first launch after a reset.
}


this.shipDockedWithStation = function ()
{
	this.missionOffers();
}


this.missionScreenEnded = this.missionChoiceWasReset = function ()
{
	if (!player.ship.docked) return;
	this.missionOffers();
}


this.shipLaunchedFromStation = function ()
{
	this.setUpShips();
}


this.shipExitedWitchspace = function ()
{
	this.loopcount = 0;
	this.setUpShips();
}
