/*

oolite-nova-mission.js

Script for nova mission.


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


this.name			= "oolite-nova";
this.author			= "Eric Walch, Jens Ayton, Kaks";
this.copyright		= "© 2008 the Oolite team.";
this.version		= "1.73";


this.missionOffers = function ()
{
	if (guiScreen == "GUI_SCREEN_MISSION" || (mission.choice && mission.choice != "") || !player.ship.docked)  return;
	
	// there will be a "missionScreenEnded" or a "missionChoiceWasReset" in future to react to.
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber == 3)
		{
			if (!missionVariables.nova && !missionVariables.novacount)  missionVariables.novacount = 0;
			if (missionVariables.nova == "TWO_HRS_TO_ZERO")
			{
				mission.runMissionScreen("nova_1", "solar.png", "nova_yesno");
				this.novaOffer = "NOVA_CHOICE";  // use a temporary variable for the offering.
				this.novaMissionTimer.stop();
			}
		}
		if (galaxyNumber == 3 || galaxyNumber == 4)
		{
			if (missionVariables.nova == "NOVA_ESCAPED_SYSTEM")
			{
				player.ship.removeAllCargo();
				player.ship.awardCargo("Gem-Stones", 100);
				mission.runMissionScreen("nova_hero", "solar.png");
				missionVariables.nova = "NOVA_HERO";
				mission.setInstructionsKey(null);
			}
			if (missionVariables.nova == "NOVA_ESCAPE_POD")
			{
				player.ship.removeAllCargo();  // can only be done while docked.
				missionVariables.nova = "NOVA_HERO";  // not a real hero but other scripts expect this missionend string.
				mission.setInstructionsKey(null);
			}
			if (missionVariables.nova == "NOVA_ESCAPE_COWARD")
			{
				missionVariables.nova = "NOVA_HERO";  // not a real hero but other scripts expect this missionend string.
			}
		}
	}
}


this.choiceEvaluation = function()
{
	if (this.novaOffer && this.novaOffer == "NOVA_CHOICE")
	{
		if (mission.choice == "YES")
		{
			player.ship.useSpecialCargo(expandDescription("[oolite-nova-refugees]"));
			mission.setInstructionsKey("nova_missiondesc");
			missionVariables.nova = "NOVA_ESCAPE_HERO";
			player.ship.launch();
			this.blowUpAllStations();
			system.sun.goNova(30);
			missionVariables.novacount = null;
		}
		else
		{
			// mission.choice = "NO", or null when player launched without a choice.
			missionVariables.nova = "NOVA_ESCAPE_COWARD";
			player.commsMessage(expandDescription("[oolite-nova-coward]"), 4.5);
			system.sun.goNova(3);
			missionVariables.novacount = null;
		}
		
		/*	IMPORTANT
			The line "mission.choice = null" causes a missionChoiceWasReset()
			event to occur. Our missionChoiceWasReset() handler calls back into
			choiceEvaluation(). It is therefore imperative that this.novaOffer
			is cleared _before_ mission.choice, or we end up in the else branch
			above.
		*/
		delete this.novaOffer;
		mission.choice = null;
	}
}


// general, used when player enters nova system after mission.
this.sendShipsAway = function()
{
	if (!system.sun.hasGoneNova)
	{
		this.novaTimer.stop();
		return;
	}
	else
	{
		system.sendAllShipsAway();
	}
}


// special, used when player enters nova system during mission.
this.sendShipsAwayForMission = function()
{
	if (missionVariables.nova != "TWO_HRS_TO_ZERO")
	{
		this.novaMissionTimer.stop();
	}
	else
	{
		system.sendAllShipsAway();
	}
}


// Destroy all stations (and carriers) in the system. If we just blow up the
// main one, the player can eject, be rescued and buy fuel without triggering
// the escape pod failure state.
this.blowUpAllStations = function ()
{
	// Find all stations in the system.
	var stations = system.filteredEntities(this, function (entity) { return entity.isStation; });
	
	// Blow them all up.
	stations.forEach(function (entity) { entity.explode(); });
}


/**** Event handlers ****/

this.shipLaunchedEscapePod = function ()
{
	if (missionVariables.nova == "NOVA_ESCAPED_SYSTEM")
	{
		missionVariables.nova = "NOVA_ESCAPE_POD";
	}
}


this.shipDockedWithStation = function ()
{
	this.missionOffers();
}


this.missionScreenEnded = this.missionChoiceWasReset = function ()
{
	this.choiceEvaluation();
	if (player.ship.docked)  this.missionOffers();
}


this.shipWillExitWitchspace = function ()  // call this as soon as possible so other scripts can see it will go nova.
{
	if (galaxyNumber == 3)
	{
		if (missionVariables.novacount)  missionVariables.novacount++;
		if (player.ship.hasEquipment("EQ_GAL_DRIVE") && missionVariables.novacount > 3 && !missionVariables.nova)
		{
			missionVariables.nova = "TWO_HRS_TO_ZERO";
			player.ship.fuelLeakRate = 25;
			system.sun.goNova(7200);
			player.consoleMessage(expandDescription("[danger-fuel-leak]"), 4.5);
			system.info.market = "none";
			system.info.sun_gone_nova = "YES";
			
			if (this.novaMissionTimer)  this.novaMissionTimer.start();
			else  this.novaMissionTimer = new Timer(this, this.sendShipsAwayForMission, 60, 30);
		}
	}
	if (missionVariables.nova == "NOVA_ESCAPE_HERO")  missionVariables.nova = "NOVA_ESCAPED_SYSTEM";
}


this.shipExitedWitchspace = function()
{
	if (system.sun.hasGoneNova)
	{
		if (this.novaTimer)  this.novaTimer.start();
		else  this.novaTimer = new Timer(this, this.sendShipsAway, 1, 60);
	}
}
