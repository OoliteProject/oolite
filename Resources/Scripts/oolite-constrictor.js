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


this.name		= "oolite-constrictor";
this.author		= "eric walch";
this.copyright	= "© 2008 the Oolite team.";
this.version	= "1.73";


this.legalPoints = 0;

this.shipSpawned = function ()
{
	this.legalPoints = this.ship.bounty;
	this.ship.bounty = 0;
}


this.shipDied = function (killer)
{
    if(killer.isPlayer)  missionVariables.conhunt = "CONSTRICTOR_DESTROYED";
}


this.checkDistance = function ()
{
	if (player.ship.position.distanceTo(this.ship) < 50000)
	{
		if(this.legalPoints > 0)
		{
			this.ship.bounty = this.legalPoints;
			this.legalPoints = 0;
		}
	}
	else
	{
		if(this.legalPoints == 0)
		{
			this.legalPoints = this.ship.bounty;
			this.ship.bounty = 0;
		}
	}
}
