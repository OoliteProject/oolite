/*

oolite-cloaking-device-mission.js

Script for cloaking device mission.
 

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
/*global galaxyNumber, missionVariables, system*/


"use strict";


this.name			= "oolite-cloaking-device";
this.author			= "Jens Ayton";
this.copyright		= "© 2007-2013 the Oolite team.";
this.description	= "Cloaking device mission in galaxy 5.";
this.version		= "1.79";


this.startUp = function ()
{
	if (missionVariables.cloak !== null)
	{	
		// save time by deleting unused handlers
		delete this.systemWillPopulate;
	}
}

this.systemWillPopulate = function ()
{
	// If we're in galaxy 5...
	if (galaxyNumber === 4)
	{
		// ...and the asp-cloaked's death_actions haven't triggered...
		if (missionVariables.cloak === null)
		{
			// ...then we count of jumps...
			if (!missionVariables.cloakcounter)
			{
				missionVariables.cloakcounter = 1;
			}
			else
			{
				missionVariables.cloakcounter++;
			}
			
			// ...until we reach six or more.
			if (missionVariables.cloakcounter > 6 && system.countShipsWithRole("asp-cloaked") === 0)
			{
				// Then trigger the ambush!
				// ensure all normal system population is set up first
				worldScripts["oolite-populator"].systemWillPopulate();
				system.setPopulator("oolite-cloaking-device-mission",
				{
					priority: 50,
					location: "WITCHPOINT",
					callback: function(pos)
					{
						var asp = system.addShips("asp-cloaked", 1, pos, 0)[0];
						if (asp.escortGroup.count != 3)
						{
							var helpers = system.addShips("asp-pirate", 2, pos, 2E3);
							asp.group = new ShipGroup("asps",asp);
							for (var i = 0; i < 3; i++)
							{
								helpers[i].group = asp.group;
								asp.group.addShip(helpers[i]);
							}
						}
					}
				});
				/* Then remove most ships from the default populator which
				 * might attack the cloaked group. The repopulator will add more
				 * later. */
				system.setPopulator("oolite-interceptors-witchpoint",null);
				system.setPopulator("oolite-hunters-route1",null);
				system.setPopulator("oolite-hunters-medium-route1",null);
				system.setPopulator("oolite-hunters-medium-route3",null);
				system.setPopulator("oolite-hunters-heavy-route1",null);
				system.setPopulator("oolite-hunters-heavy-route3",null);
				system.setPopulator("oolite-police-route1",null);
				
			}								 
		}
	}
};
