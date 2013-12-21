/*

oolite-tutorial-equipment.js

Equipment script for tutorial.


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
/*global worldScripts*/


"use strict";

this.name = "Tutorial Controls";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";

this.$mode = 0;

this.activated = function()
{
	if (this.$mode == 0)
	{
		worldScripts["oolite-tutorial"]._nextItemEquip();
	} 
	else if (this.$mode == 1)
	{
		worldScripts["oolite-tutorial"]._nextSection();
		this.$mode = 0;
		player.consoleMessage(expandMissionText("oolite-tutorial-controls-mode0"));
	}
	else if (this.$mode == 2)
	{
		worldScripts["oolite-tutorial"]._restartSection();
		this.$mode = 0;
		player.consoleMessage(expandMissionText("oolite-tutorial-controls-mode0"));
	}
}


this.mode = function()
{
	this.$mode = (this.$mode + 1) % 3;

	player.consoleMessage(expandMissionText("oolite-tutorial-controls-mode"+this.$mode));
}