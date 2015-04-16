/*

oolite-ship-library.js

World script handling launching of the ship library


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

this.name = "Oolite Ship Library";
this.description = "This script allows in-game access to the ship library.";
this.author			= "cim";
this.copyright		= "© 2015 the Oolite team.";


this.startUpComplete = this.shipDockedWithStation = this.playerBoughtNewShip = function()
{
	this._initialiseInterface();
}


this._initialiseInterface = function()
{
	if (player.ship.dockedStation)
	{
		var definition = {
			title: expandMissionText("oolite-shiplibrary-interface-title"),
			category: expandMissionText("oolite-shiplibrary-interface-category"),
			summary: expandMissionText("oolite-shiplibrary-interface-summary"),
			callback: this._launchShipLibrary.bind(this)
		};
		player.ship.dockedStation.setInterface("oolite-ship-library",definition);
	}
}


this._launchShipLibrary = function() 
{
	this.$hudHidden = player.ship.hudHidden; // save HUD state
	player.ship.hudHidden = true;

	mission.runShipLibrary();
}


this.guiScreenChanged = function(to, from)
{
	if (from == "GUI_SCREEN_SHIPLIBRARY")
	{
		player.ship.hudHidden = this.$hudHidden; // restore HUD state
	}
}