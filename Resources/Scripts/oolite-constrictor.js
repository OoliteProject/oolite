/*

oolite-constrictor.js

Ship script for Constrictor Hunt mission.


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
/*global missionVariables, player*/


"use strict";


this.name			= "oolite-constrictor";
this.author			= "Eric Walch";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.77.1";


/*
	To avoid being attacked by other ships, the Constrictor goes legal when
	the player is well out of range. When this happens, the "real" bounty
	is stored in _legalPoints.
*/
this._legalPoints = 0;


this.shipSpawned = function ()
{
	this._legalPoints = this.ship.bounty;
	this.ship.bounty = 0;
	if (this.ship.accuracy < 0)
	{ // make sure it is always reasonably good AI
		this.ship.accuracy = -this.ship.accuracy;
	}
	if (player.score > 512)
	{
		this.ship.awardEquipment("EQ_SHIELD_BOOSTER"); // Player is Dangerous
	}
	if (player.score > 2560)
	{
		this.ship.awardEquipment("EQ_SHIELD_ENHANCER"); // Player is Deadly
	}
	this.ship.energy = this.ship.maxEnergy; // start with all energy banks full.
};


this.shipDied = function (killer)
{
    if (killer.isPlayer)
	{
		missionVariables.conhunt = "CONSTRICTOR_DESTROYED";
	}
};


this._checkDistance = function ()
{
	if (player.ship.position.distanceTo(this.ship) < 50000)
	{
		if (this._legalPoints > 0)
		{
			this.ship.bounty = this._legalPoints;
			this._legalPoints = 0;
		}
	}
	else
	{
		if (this._legalPoints === 0)
		{
			this._legalPoints = this.ship.bounty;
			this.ship.bounty = 0;
		}
	}
};
