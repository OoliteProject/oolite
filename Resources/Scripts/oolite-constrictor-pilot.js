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
this.version		= "1.75.3";


this.unloadCharacter = function ()
{
	/*
	 print congratulatory message from the Imperial Navy
	 award a special bounty
	 */
    player.addMessageToArrivalReport(expandMissionText("constrictor_hunt_thief_captured"));
    player.credits += 1000;

}
