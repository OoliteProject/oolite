/*

oolite-constrictor-hunt-mission.js

Script for Constrictor hunt mission.


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
/*global galaxyNumber, guiScreen, mission, missionVariables, player, system*/


this.name			= "oolite-constrictor-hunt";
this.author			= "Eric Walch";
this.copyright		= "© 2008–2009 the Oolite team.";
this.version		= "1.73";


this.addToScreen = function ()
{
	if (guiScreen === "GUI_SCREEN_SYSTEM_DATA")
	{
		if (galaxyNumber === 0)
		{
			switch (system.ID)
			{
				case 28:
				case 36:
				case 150:
					mission.addMessageTextKey("constrictor_hunt_0_" + system.ID);
					break;
					
				default:
					break;
			}
		}
		if (galaxyNumber === 1)
		{
			switch (system.ID)
			{
				case 3:
				case 5:
				case 16:
				case 26:
				case 32:
				case 68:
				case 106:
				case 107:
				case 162:
				case 164:
				case 184:
				case 192:
				case 220:
					mission.addMessageTextKey("constrictor_hunt_1_A");
					break;
					
				case 253:
				case 79:
				case 53:
				case 118:
				case 193:
					mission.addMessageTextKey("constrictor_hunt_1_" + system.ID);
					break;
					
				default:
					break;
			}
		}
	}
};


this.missionOffers = function ()
{
	if (guiScreen === "GUI_SCREEN_MISSION" || (mission.choice && mission.choice !== "") || !player.ship.docked)  { return; }
	
	// there will be a "missionScreenEnded" or a "missionChoiceWasReset" in future to react to.
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber < 2 && !missionVariables.conhunt && player.score > 255)
		{
			mission.runMissionScreen("constrictor_hunt_brief1", null, null, "constrictor");
			if (galaxyNumber === 0)
			{
				mission.addMessageTextKey("constrictor_hunt_brief1a"); // galaxy = 0
				mission.setInstructionsKey("conhunt_short_desc1");
			}
			else
			{
				mission.addMessageTextKey("constrictor_hunt_brief1b"); // galaxy = 1
				mission.setInstructionsKey("conhunt_short_desc1b");
			}
			missionVariables.conhunt = "STAGE_1";
			// mission.setInstructionsKey("conhunt_short_desc1");
		}
		if (missionVariables.conhunt === "CONSTRICTOR_DESTROYED")  // Variable is set by the ship-script
		{
			mission.runMissionScreen("constrictor_hunt_debrief", null, null, "constrictor");
			player.credits += 5000;
			player.bounty = 0;	  // legal status
			player.score += 256;  // ship kills
			mission.setInstructionsKey(null);  // reset the missionbriefing
			missionVariables.conhunt = "MISSION_COMPLETE";
		}
	}
};


this.setUpShips = function ()
{
	if (galaxyNumber === 1 &&
		system.ID === 193 &&
		missionVariables.conhunt === "STAGE_1" &&
		system.countShipsWithRole("constrictor") === 0)
	{
		system.legacy_addShips("constrictor", 1);
	}
};


/**** Event handlers ****/

this.guiScreenChanged = function ()
{
	if (galaxyNumber < 2 && missionVariables.conhunt === "STAGE_1")
	{
		this.addToScreen();
	}
};


this.shipDockedWithStation = function ()
{
	this.missionOffers();
};


this.missionScreenEnded = this.missionChoiceWasReset = function ()
{
	if (!player.ship.docked)  { return; }
	this.missionOffers();
};


this.shipExitedWitchspace = this.shipLaunchedFromStation = function ()
{
	this.setUpShips();
};
