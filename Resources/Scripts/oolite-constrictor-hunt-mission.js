/*

oolite-constrictor-hunt-mission.js

Script for Constrictor Hunt mission.


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


// jslint bug: the "laxbreak" setting doesn't reliably work, which causes complaints about case indentation.
/*jslint white: true, laxbreak: true, undef: true, eqeqeq: true, bitwise: true, newcap: true, immed: true */
/*global galaxyNumber, guiScreen, mission, missionVariables, player, system*/


"use strict";


this.name			= "oolite-constrictor-hunt";
this.author			= "Eric Walch";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";


this._cleanUp = function ()
{
	// Remove event handlers.
	delete this.guiScreenChanged;
	delete this.missionScreenOpportunity;
	delete this.systemWillPopulate;
};


/**** Event handlers ****/


this.startUp = function ()
{
	// Remove event handlers once the mission is over.
	if (missionVariables.conhunt === "MISSION_COMPLETE")
	{
		this._cleanUp();
	}
	
	delete this.startUp;
};


this.guiScreenChanged = function ()
{
	if (galaxyNumber < 2 && missionVariables.conhunt === "STAGE_1")
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
	}
};


// this function is potentially called multiple times.
this.missionScreenOpportunity = function ()
{
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber < 2 && !missionVariables.conhunt && player.score > 255)
		{
			// there are no options to deal with, we don't need a callback function.
			mission.runScreen({
				titleKey: "constrictor_hunt_title",
				messageKey: "constrictor_hunt_brief1",
				model: "constrictor"
			});
			if (galaxyNumber === 0)
			{
				mission.addMessageTextKey("constrictor_hunt_brief1a"); // galaxy = 0
				mission.setInstructionsKey("constrictor_hunt_info1a");
			}
			else
			{
				mission.addMessageTextKey("constrictor_hunt_brief1b"); // galaxy = 1
				mission.setInstructionsKey("constrictor_hunt_info1b");
			}
			missionVariables.conhunt = "STAGE_1";
		}
		if (missionVariables.conhunt === "CONSTRICTOR_DESTROYED")  // Variable is set by the ship script
		{
			mission.runScreen({
				titleKey: "constrictor_hunt_title",
				messageKey: "constrictor_hunt_debrief",
				model: "constrictor"
			});
			player.credits += 5000;
			player.bounty = 0;	  // legal status
			player.score += 256;  // ship kills
			mission.setInstructions(null);  // reset the mission briefing
			missionVariables.conhunt = "MISSION_COMPLETE";
			this._cleanUp();
		}
	}
};


this.systemWillPopulate = function()
{
	// galaxy+system parts of this check shouldn't be necessary
	if (galaxyNumber === 1 &&
		system.ID === 193 &&
		missionVariables.conhunt === "STAGE_1")
	{
		// ensure all normal system population is set up first
		worldScripts["oolite-populator"].systemWillPopulate();

		// then add the Constrictor
		system.setPopulator("oolite-constrictor-mission",
			{
				priority: 50,
				location: "WITCHPOINT",
				callback: function(pos)
				{
					var constrictor = system.addShips("constrictor", 1, pos, 0);
					constrictor[0].bounty = 250; // Ensure a bounty, in case it was missing in a custom shipdata.plist.
					// Attach script here and not in shipdata, so that like_ship copies of the constrictor have no mission script,
					// only the version used for the mission will have the script now.
					constrictor[0].setScript("oolite-constrictor.js");
				}
			});

		/* Then remove most ships from the default populator which
		 * might attack the Constrictor. The repopulator will add more
		 * later. */
		system.setPopulator("oolite-interceptors-witchpoint",null);
		system.setPopulator("oolite-hunters-route1",null);
		system.setPopulator("oolite-hunters-medium-route1",null);
		system.setPopulator("oolite-hunters-medium-route3",null);
		system.setPopulator("oolite-hunters-heavy-route1",null);
		system.setPopulator("oolite-hunters-heavy-route3",null);
		system.setPopulator("oolite-police-route1",null);
		
	}
};
