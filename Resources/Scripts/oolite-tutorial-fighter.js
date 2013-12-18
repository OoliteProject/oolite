/*

oolite-tutorial-fighter.js

Ship script for Tutorial fighters.


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


this.name			= "oolite-tutorial-fighter";
this.author			= "cim";
this.copyright		= "© 2013-2013 the Oolite team.";
this.version		= "1.79";


this.shipDied = function (killer)
{
	if (killer && killer.isPlayer && (!this.ship.group || this.ship.group.count <= 1))
	{
		worldScripts["oolite-tutorial"]._nextItem();
	}
};
