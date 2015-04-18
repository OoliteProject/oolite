/*

oolite-constrictor-hunt-mission.js

Conditions Script for Constrictor Hunt mission.


Oolite
Copyright © 2004-2015 Giles C Williams and contributors

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

this.name = "Oolite Constrictor Ship Library Conditions";
this.author			= "cim";
this.copyright		= "© 2008-2015 the Oolite team.";

this.allowShowLibraryShip = function(key)
{
	if (key != "constrictor")
	{
		// shouldn't happen
		return true;
	}
	if (missionVariables.conhunt) 
	{
		// any state is sufficient
		return true;
	} 
	return false;
}