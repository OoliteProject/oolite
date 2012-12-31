/*

oolite-trumbles-mission.js

Script for random offers of trumbles.

 
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
/*global guiScreen, mission, missionVariables, player*/


"use strict";


this.name			= "oolite-trumbles";
this.author			= "Jens Ayton";
this.copyright		= "© 2008-2013 the Oolite team.";
this.description	= "Random offers of trumbles.";
this.version		= "1.77";


(function () {
 
var pendingOffer = false;


function cleanUp(script)
{
	delete script.shipDockedWithStation;
	delete script.missionScreenOpportunity;
	delete script.shipWillExitWitchspace;
}


this.startUp = function startUp()
{
	/*	In the pre-JavaScript implementation, the mission variable was set to
		OFFER_MADE while the mission screen was shown. If the player lanched
		in that state, the offer would never be made again -- unless some
		other script used the mission choice keys "YES" or "NO". This
		implementation uses unique choice keys and doesn't change the mission
		variable, which should be more reliable in all cases.
	*/
	if (missionVariables.trumbles === "OFFER_MADE")
	{
		missionVariables.trumbles = "BUY_ME";
	}
	else if (missionVariables.trumbles === "TRUMBLE_BOUGHT")
	{
		cleanUp(this);
	}
	delete this.startUp;
}


this.shipDockedWithStation = function shipDockedWithStation(station)
{
	pendingOffer = false;
	
	if (station.isMainStation)
	{
		if (!missionVariables.trumbles &&
			!missionVariables.novacount)	// So the offers eventually stop for long-time players who keep refusing.
		{
			missionVariables.trumbles = "BUY_ME";
		}
		
		if (missionVariables.trumbles === "BUY_ME" &&
			player.trumbleCount === 0 &&
			Math.random() < 0.2) // 20% chance of trumble being offered.
		{
			pendingOffer = true;
		}
	}
}


this.missionScreenOpportunity = function missionScreenOpportunity()
{
	if (pendingOffer && player.credits > 6553.5)
	{
		pendingOffer = false;
		
		// Show the mission screen.
		mission.runScreen({
			titleKey: "oolite_trumble_title",
			messageKey: "oolite_trumble_offer",
			background: "trumblebox.png",
			choicesKey: "oolite_trumble_offer_yesno"
		},
		function (choice)
		{
			if (choice === "OOLITE_TRUMBLE_YES")
			{
				player.credits -= 30;
				player.ship.awardEquipment("EQ_TRUMBLE");
				
				missionVariables.trumbles = "TRUMBLE_BOUGHT";
				cleanUp(this);
			}
			else
			{
				missionVariables.trumbles = "NOT_NOW";
			}
		});
	}
};


this.shipWillExitWitchspace = function shipWillExitWitchspace()
{
	// If player has rejected a trumble offer, reset trumble mission with 2% probability per jump.
	if (missionVariables.trumbles === "NOT_NOW" && Math.random() < 0.02)
	{
		missionVariables.trumbles = "BUY_ME";
	}
};

}).call(this);
