/*
 
 oolite-constrictor-pilot.js
 
 Character script for Constrictor Hunt mission.
 
 
 Oolite
 Copyright © 2004-2010 Giles C Williams and contributors
 
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



this.name			= "oolite-constrictor-pilot";
this.author			= "Eric Walch";
this.copyright		= "© 2008-2010 the Oolite team.";
this.version		= "1.77.1";


this.unloadCharacter = function ()
{
    switch (missionVariables.conhunt)
	{
		case "CONSTRICTOR_DESTROYED":
		{
			/*
			 print congratulatory message from the Imperial Navy
			 award a special bounty
			 */
			player.addMessageToArrivalReport(expandMissionText("constrictor_hunt_thief_captured"));
			player.credits += 1000;
			break;
		}
		case "STAGE_1":
		{
			// Pilot was scooped, but the ship is still intact. Mission continues.
			player.addMessageToArrivalReport(expandMissionText("constrictor_hunt_thief_captured2"));
			break;
		}
		default:
		{
			// was not a pilot from a mission ship. Probably created by a like_ship reference. Create generic message.
			player.addMessageToArrivalReport(expandMissionText("constrictor_hunt_pilot_captured"));
			player.credits += 250;
			break;
		}
	}
	
}
