/*

oolite-registership.js

Set up ship name and commander name


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


this.name			= "oolite-registership";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";

this.startUp = this.shipWillExitWitchspace = function()
{
	if (system.mainStation)
	{
		system.mainStation.setInterface("oolite-registership",{
			title: expandMissionText("oolite-registership-interface-title"),
			category: expandMissionText("oolite-registership-interface-category"),
			summary: expandMissionText("oolite-registership-interface-summary"),
			callback: this._registerShip.bind(this)
		});
	}
}


this._registerShip = function()
{
	mission.runScreen({
		titleKey: "oolite-registership-title-part1",
		messageKey: "oolite-registership-instructions-part1",
		screenID: "oolite-register",
		exitScreen: "GUI_SCREEN_INTERFACES",
		textEntry: true
	},this._registerShip2.bind(this));
}


this._registerShip2 = function(cdrname)
{
	if (cdrname && cdrname != "")
	{
		player.name = cdrname;
	}
	mission.runScreen({
		titleKey: "oolite-registership-title-part2",
		messageKey: "oolite-registership-instructions-part2",
		screenID: "oolite-register",
		exitScreen: "GUI_SCREEN_INTERFACES",
		textEntry: true
	},this._registerShip3.bind(this));
}


this._registerShip3 = function(shipname)
{
	if (shipname && shipname != "")
	{
		player.ship.shipUniqueName = shipname;
	}
	mission.runScreen({
		titleKey: "oolite-registership-title-part3",
		messageKey: "oolite-registership-instructions-part3",
		exitScreen: "GUI_SCREEN_INTERFACES",
		screenID: "oolite-register",
	});
}

