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
this.author			= "eric walch";
this.copyright		= "© 2008 the Oolite team.";
this.version		= "1.71";


this.missionOffers = function ()
{
	if (guiScreen == "GUI_SCREEN_MISSION" || (mission.choice && mission.choice != ""))  return;
	
	// there will be a "missionScreenEnded" or a "missionChoiceWasReset" in future to react to.
	if (player.dockedStation.isMainStation)
	{
		if (galaxyNumber == 3)
		{
			if (!missionVariables.nova && !missionVariables.novacount)  missionVariables.novacount = 0;
			if (missionVariables.nova == "TWO_HRS_TO_ZERO")
			{
				mission.runMissionScreen("nova_1", "solar.png", "nova_yesno");
				log("nova.missionOffers", "Setting this.novaOffer to \"NOVA_CHOICE\"");
				this.novaOffer = "NOVA_CHOICE";  // use a temporary variable for the offering.
				this.novaMissionTimer.stop();
			}
		}
		if (galaxyNumber == 3 || galaxyNumber == 4)
		{
			if (missionVariables.nova == "NOVA_ESCAPED_SYSTEM")
			{
				player.removeAllCargo();
				player.awardCargo("Gem-Stones", 100);
				mission.runMissionScreen("nova_hero", "solar.png");
				missionVariables.nova = "NOVA_HERO";
				mission.setInstructionsKey();
			}
			if (missionVariables.nova == "NOVA_ESCAPE_POD")
			{
				player.removeAllCargo();  // can only be done while docked.
				missionVariables.nova = "NOVA_HERO";  // not a real hero but other scripts expect this missionend string.
				mission.setInstructionsKey();
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
	if (!this.novaOffer)
	{
		log("nova.choicesEvaluation", "Exiting early because !this.novaOffer.");
		return;
	}
	
	if (this.novaOffer == "NOVA_CHOICE")
	{
		log("nova.choicesEvaluation", "Evaluating this.novaOffer == \"NOVA_CHOICE\"");
		if (mission.choice == "YES")
		{
			log("nova.choicesEvaluation", "mission.choice == YES, player loaded refugees.");
			mission.choice = null;
			player.useSpecialCargo(expandDescription("[oolite-nova-refugees]"));
			mission.setInstructionsKey("nova_missiondesc");
			missionVariables.nova = "NOVA_ESCAPE_HERO";
			player.launch();
			system.mainStation.explode();
			system.setSunNova(30);
			missionVariables.novacount = null;
		}
		else
		{
			log("nova.choicesEvaluation", "mission.choice == " + mission.choice + ", player refused to help.");
			// mission.choice = "NO", or null when player launched without a choice.
			mission.choice = null;
			missionVariables.nova = "NOVA_ESCAPE_COWARD";
			player.commsMessage(expandDescription("[oolite-nova-coward]"), 4.5);
			system.setSunNova(3);
			missionVariables.novacount = null;
		}
		
		delete this.novaOffer;
		log("nova.choicesEvaluation", "deleted this.novaOffer, this.novaOffer is now " + this.novaOffer);
	}
}


// general, used when player enters nova system after mission.
this.sendShipsAway = function()
{
	if (!system.goneNova)
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
	if (player.docked)  this.missionOffers();
}


this.shipWillExitWitchspace = function ()  // call this as soon as possible so other scripts can see it will go nova.
{
	if (galaxyNumber == 3)
	{
		if (missionVariables.novacount)  missionVariables.novacount++;
		if (player.hasEquipment("EQ_GAL_DRIVE") && missionVariables.novacount > 3 && !missionVariables.nova)
		{
			missionVariables.nova = "TWO_HRS_TO_ZERO";
			player.fuelLeakRate = 25;
			system.setSunNova(7200);
			player.consoleMessage(expandDescription("[danger-fuel-leak]"), 4.5);
			player.call("setPlanetinfo:", "market = none");
			player.call("setPlanetinfo:", "sun_gone_nova = YES");
			
			if (this.novaMissionTimer)  this.novaMissionTimer.start();
			else  this.novaMissionTimer = new Timer(this, this.sendShipsAwayForMission, 60, 30);
		}
	}
	if (missionVariables.nova == "NOVA_ESCAPE_HERO")  missionVariables.nova = "NOVA_ESCAPED_SYSTEM";
}


this.shipExitedWitchspace = function()
{
	if (system.goneNova)
	{
		if (this.novaTimer)  this.novaTimer.start();
		else  this.novaTimer = new Timer(this, this.sendShipsAway, 1, 60);
	}
}
