/*

oolite-default-ship-script.js

Standard ship script; handles legacy foo_actions.


Oolite
Copyright © 2007 Giles C Williams and contributors

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


this.name			= "oolite-default-ship-script";
this.author			= "Jens Ayton";
this.copyright		= "© 2007 the Oolite team.";
this.description	= "Standard script for ships.";
this.version		= "1.69.2";


// launch_actions handled on didSpawn().
if (this.legacy_launchActions != undefined)
{
	this.didSpawn = function()
	{
		this.ship.runLegacyScriptActions(this.ship, this.legacy_launchActions);
		
		// These can only be used once; keeping them around after that is pointless.
		delete this.didSpawn;
		delete this.legacy_launchActions;
	}
}


// death_actions handled on didDie().
if (this.legacy_deathActions != undefined)
{
	this.didDie = function()
	{
		this.ship.runLegacyScriptActions(this.ship, this.legacy_deathActions);
	}
}


// script_actions handled on shipDidDock() and wasScooped().
if (this.legacy_scriptActions != undefined)
{
	/*	legacy script_actions should be called for stations when the player
		docks, and for cargo pods when they are is scooped. No sane vessel can
		be scooped _and_ docked with. Non-sane vessels are certified insane.
	*/
	this.shipDidDock = function(docker)
	{
		if (docker == player)
		{
			this.ship.runLegacyScriptActions(docker, this.legacy_scriptActions);
		}
	}
	this.wasScooped = function(scooper)
	{
		// Note "backwards" call, allowing awardEquipment: and similar to affect the scooper rather than the scoopee.
		scooper.runLegacyScriptActions(this.ship, this.legacy_scriptActions);
	}
}


// setup_actions handled on script initialization.
if (this.legacy_setupActions != undefined)
{
	this.ship.runLegacyScriptActions(this.ship, this.legacy_setupActions);
	delete this.legacy_setupActions;
}
