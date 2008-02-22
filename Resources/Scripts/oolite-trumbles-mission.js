/*

oolite-trumbles-mission.js

Script for random offers of trumbles.

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


this.name			= "oolite-trumbles";
this.author			= "Jens Ayton";
this.copyright		= "© 2007 the Oolite team.";
this.description	= "Random offers of trumbles.";
this.version		= "1.71";


this.startUp = this.reset = function ()
{
	/*	For simplicity, ensure that missionVariables.trumbles is never
		undefined when running the rest of the script. If it could be
		undefined, it would be necessary to test for undefinedness before
		doing any tests on the value, like so:
			if (missionVariables.trumbles && missionVariables.trumbles == "FOO")
	*/
	if (!missionVariables.trumbles)
	{
		missionVariables.trumbles = "";
	}
}


this.shipDockedWithStation = function ()
{
	/*	In the pre-JavaScript implementation, the mission variable was set to
		OFFER_MADE while the mission screen was shown. If the player lanched
		in that state, the offer would never be made again -- unless some
		other script used the mission choice keys "YES" or "NO". This
		implementation uses unique choice keys and doesn't change the mission
		variable, which should be more reliable in all cases.
	*/
	if (missionVariables.trumbles == "OFFER_MADE")  missionVariables.trumbles = "BUY_ME"
	
	if (player.dockedStation.isMainStation &&
		missionVariables.trumbles == "" &&
		!missionVariables.novacount &&		// So the offers eventually stop for long-time players who keep refusing.
		player.credits > 6553.5)
	{
		missionVariables.trumbles = "BUY_ME";
	}
	
	if (missionVariables.trumbles == "BUY_ME" && player.trumbleCount == 0)
	{
		// 20% chance of trumble being offered, if no other script got this dock session first.
		if (guiScreen == "GUI_SCREEN_STATUS"
			&& Math.random() < 0.2)
		{
			// Show the mission screen.
			mission.clearMissionScreen();
			mission.setBackgroundImage("trumblebox.png");
			mission.showMissionScreen();
			mission.addMessageTextKey("oolite_trumble_offer");
			mission.setChoicesKey("oolite_trumble_offer_yesno");
		}
	}
}


this.missionScreenEnded = function ()
{
	if (missionVariables.trumbles == "BUY_ME")
	{
		// Could have been trumble mission screen.
		if (mission.choice == "OOLITE_TRUMBLE_YES")
		{
			// Trumble bought.
			mission.clearMissionScreen();
			missionVariables.trumbles = "TRUMBLE_BOUGHT";
			player.credits -= 30;
			player.awardEquipment("EQ_TRUMBLE");
		}
		else if (mission.choice == "OOLITE_TRUMBLE_NO")
		{
			// Trumble bought.
			mission.clearMissionScreen();
			missionVariables.trumbles = "NOT_NOW";
		}
		// else it was someone else's mission screen, so we do nothing.
	}
}


this.shipWillExitWitchspace = function ()
{
	// If player has rejected a trumble offer, reset trumble mission with 2% probability per jump.
	if (missionVariables.trumbles == "NOT_NOW" && Math.random < 0.02)
	{
		missionVariables.trumbles = "BUY_ME";
	}
}
