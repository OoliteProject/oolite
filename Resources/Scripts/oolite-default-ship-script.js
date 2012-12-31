/*

oolite-default-ship-script.js

Standard ship script; handles legacy foo_actions.


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


"use strict";


this.name			= "oolite-default-ship-script";
this.author			= "Jens Ayton";
this.copyright		= "© 2007-2013 the Oolite team.";
this.description	= "Standard script for ships.";
this.version		= "1.77";


// launch_actions handled on shipSpawned(). For parity with 1.65, launch_actions don’t fire for the main station.
if (this.legacy_launchActions !== undefined && this !== system.mainStation)
{
	this.shipSpawned = function ()
	{
		/*	IMPORTANT: __runLegacyScriptActions() is a private function. It may
			be removed, renamed or have its semantics changed at any time in
			the future. Do not use it in your own scripts.
		*/
		this.ship.__runLegacyScriptActions(this.ship, this.legacy_launchActions);
		
		delete this.shipSpawned;
	};
}


// death_actions handled on shipDied().
if (this.legacy_deathActions !== undefined)
{
	this.shipDied = function ()
	{
		/*	IMPORTANT: __runLegacyScriptActions() is a private function. It may
			be removed, renamed or have its semantics changed at any time in
			the future. Do not use it in your own scripts.
		*/
		this.ship.__runLegacyScriptActions(this.ship, this.legacy_deathActions);
	};
}


// script_actions handled on otherShipDocked() and shipWasScooped().
if (this.legacy_scriptActions !== undefined)
{
	/*	legacy script_actions should be called for stations when the player
		docks, and for cargo pods when they are is scooped. No sane vessel can
		be scooped _and_ docked with. Non-sane vessels are certified insane.
	*/
	this.otherShipDocked = function (docker)
	{
		if (docker.isPlayer)
		{
			/*	IMPORTANT: __runLegacyScriptActions() is a private function. It
				may be removed, renamed or have its semantics changed at any
				time in the future. Do not use it in your own scripts.
			*/
			this.ship.__runLegacyScriptActions(docker, this.legacy_scriptActions);
		}
	};
	this.shipWasScooped = function (scooper)
	{
		/*	IMPORTANT: __runLegacyScriptActions() is a private function. It may
			be removed, renamed or have its semantics changed at any time in
			the future. Do not use it in your own scripts.
		*/
		
		// Note "backwards" call, allowing awardEquipment: and similar to affect the scooper rather than the scoopee.
		scooper.__runLegacyScriptActions(this.ship, this.legacy_scriptActions);
	};
}


// setup_actions handled on script initialization.
if (this.legacy_setupActions !== undefined)
{
	/*	IMPORTANT: __runLegacyScriptActions() is a private function. It may be
		removed, renamed or have its semantics changed at any time in the
		future. Do not use it in your own scripts.
	*/
	this.ship.__runLegacyScriptActions(this.ship, this.legacy_setupActions);
}
