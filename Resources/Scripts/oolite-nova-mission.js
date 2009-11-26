/*

oolite-nova-mission.js

Script for nova mission.


Oolite
Copyright ¨© 2004-2009 Giles C Williams and contributors

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


/*jslint bitwise: true, undef: true, eqeqeq: true, immed: true, newcap: true*/
/*global Timer, expandDescription, galaxyNumber, guiScreen, mission, missionVariables, player, system*/


this.name			= "oolite-nova";
this.author			= "Eric Walch, Jens Ayton, Kaks";
this.copyright		= "© 2009 the Oolite team.";
this.version		= "1.74";


this.missionOffers = function ()
{
	if (!player.ship.docked)  { return; }

	// Choices are handled inside this.choiceEvaluation.
	if (player.ship.dockedStation.isMainStation)
	{
		if (galaxyNumber === 3)
		{
			if (!missionVariables.nova && !missionVariables.novacount)  { missionVariables.novacount = 0; }
			if (missionVariables.nova === "TWO_HRS_TO_ZERO")
			{
				mission.runScreen({titleKey:"oolite_nova_title", messageKey:"oolite_nova_brief", background:"solar.png", choicesKey:"oolite_nova_yesno"}, this.choiceEvaluation);
				this.novaMissionTimer.stop();
			}
		}
		if (galaxyNumber === 3 || galaxyNumber === 4)
		{
			if (missionVariables.nova === "NOVA_ESCAPED_SYSTEM")
			{
				player.ship.removeAllCargo();
				mission.runScreen({titleKey:"oolite_nova_title", messageKey:"oolite_nova_hero", background:"solar.png"});
				player.ship.manifest["Gem-Stones"] += 100;
				this.endTheMission();
			}
			else if (missionVariables.nova === "NOVA_ESCAPE_POD")
			{
				player.ship.removeAllCargo();  // can only be done while docked.
				mission.runScreen({titleKey:"oolite_nova_title", messageKey:"oolite_nova_disappointed", background:"solar.png"});
				this.endTheMission();
			}
			else if (missionVariables.nova === "NOVA_ESCAPE_OTHER")
			{
				mission.runScreen({titleKey:"oolite_nova_title", messageKey:"oolite_nova_ignored", background:"solar.png"});
				this.endTheMission();
			}
			else if (missionVariables.nova === "NOVA_ESCAPE_COWARD" && !system.sun.isGoingNova && !system.sun.hasGoneNova)
			{
				player.decreaseContractReputation();
				player.decreasePassengerReputation();
				mission.runScreen({titleKey:"oolite_nova_title", messageKey:"oolite_nova_disappointed", background:"solar.png"});
				this.endTheMission();
			}
		}
	}
	else if (missionVariables.nova === "TWO_HRS_TO_ZERO")
	{
		// this is the the nova system, but not the main station.
		player.ship.launch();
		player.commsMessage(expandDescription("[oolite-nova-visit-main]"));
	}
};


this.endTheMission = function()
{
	missionVariables.nova = "NOVA_HERO";  // even if not a hero, other scripts expect this string at mission end.
	mission.setInstructions(null);
	this.cleanUp();
}


this.cleanUp = function()
{
	// mission is over, we don't need most of the event handlers
	// this.shipExitedWitchspace is still needed after the nova mission.
	delete this.shipWillEnterWitchspace;
	delete this.shipWillExitWitchspace;
	delete this.missionScreenOpportunity;
	delete this.shipLaunchedEscapePod;
	delete this.shipLaunchedFromStation;
}


this.choiceEvaluation = function(choice)
{
	if (choice === "YES")
	{
		player.ship.useSpecialCargo(expandDescription("[oolite-nova-refugees]"));
		mission.setInstructionsKey("oolite_nova_info");
		missionVariables.nova = "NOVA_ESCAPE_HERO";
		player.ship.launch();
		this.blowUpAllStations();
		system.sun.goNova(30);
	}
	else
	{
		// mission.choice == "NO", or null when player launched without making a choice.
		missionVariables.nova = "NOVA_ESCAPE_COWARD";
		player.commsMessage(expandDescription("[oolite-nova-coward]"), 4.5);
		system.sun.goNova(9);	// barely enough time to jump out of the system.
	}
	missionVariables.novacount = null;
};


// used when player enters nova system during nova mission.
this.sendShipsAwayForMission = function()
{
	if (missionVariables.nova !== "TWO_HRS_TO_ZERO")
	{
		this.novaMissionTimer.stop();
	}
	else
	{
		system.sendAllShipsAway();
		if(!this.buoyLoaded) {this.witchBuoy = system.shipsWithPrimaryRole("buoy-witchpoint")[0]; this.buoyLoaded = true;}
		if(this.witchBuoy && this.witchBuoy.isValid)
		{
			this.witchBuoy.commsMessage(expandDescription("[oolite-nova-distress-call]"));
		}
	}
};


// Destroy all stations (and carriers) in the system. If we just blow up the
// main one, the player can eject, be rescued and buy fuel without triggering
// the escape pod failure state.
this.blowUpAllStations = function ()
{
	// Find all stations in the system.
	var stations = system.filteredEntities(this, function (entity) { return entity.isStation; });
	
	// Blow them all up.
	stations.forEach(function (entity) { entity.explode(); });
};


// used when player enters nova system after nova mission.
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
};


this.flareUp = function()
{
	system.info.corona_hues=1;
	// This flare up (.25 to .5 flare) will last between 10 and 30 seconds
	this.flareChange(.25 + Math.random()*.25,this.flareDown,Math.random() * 20 + 10);
};


this.flareDown = function()
{
	system.info.corona_hues = .8;
	// This quiet moment  ( .1 to .2 flare ) will last between 30 seconds and 2 minutes
	this.flareChange(.1 + Math.random() * .1,this.flareUp,Math.random() * 90 + 30);
};


this.flareChange = function(toValue,callFunc,callDelay,pass)
{
	this.flareTimer.stop();
	delete this.flareTimer;
	pass = pass || 0;
	if (pass < 5 )
	{
		var f = system.info.corona_flare; 
		system.info.corona_flare = (f < toValue ? toValue*1.5+f : toValue+f*1.5) / 2.5;
		this.flareTimer = new Timer(this, function(){this.flareChange(toValue,callFunc,callDelay,++pass);}, .25);
	}
	else 
	{
		system.info.corona_flare = toValue;
		this.flareTimer = new Timer(this, callFunc, callDelay);
	}
}


/**** Event handlers ****/


this.startUp = function ()
{
	// Remove all event handlers once the mission is over.
	if (missionVariables.nova === "NOVA_HERO") { this.cleanUp(); }
}


this.shipLaunchedEscapePod = function ()
{
	if (missionVariables.nova === "NOVA_ESCAPED_SYSTEM")
	{
		missionVariables.nova = "NOVA_ESCAPE_POD";
	}
};


this.missionScreenOpportunity = function ()
{
	this.missionOffers();
};


this.shipWillEnterWitchspace = function ()
{
	if (this.willGoNova)
	{
		system.info.sun_gone_nova = true;
		delete this.willGoNova;
		// did the player leave the nova system without docking at the main station?
		if (missionVariables.nova === "TWO_HRS_TO_ZERO") missionVariables.nova = "NOVA_ESCAPE_OTHER";
	}
}


this.shipWillExitWitchspace = function ()  // call this as soon as possible so other scripts can see it will go nova.
{
	if (!missionVariables.nova && galaxyNumber === 3)
	{
		if (missionVariables.novacount !== undefined)  { missionVariables.novacount++; }
		if (player.ship.hasEquipment("EQ_GAL_DRIVE") && missionVariables.novacount > 3 && !missionVariables.nova && !system.isInterstellarSpace)
		{
			missionVariables.nova = "TWO_HRS_TO_ZERO";
			player.ship.fuelLeakRate = 25;
			system.sun.goNova(7200);
			this.willGoNova = true;
			player.consoleMessage(expandDescription("[danger-fuel-leak]"), 4.5);
			system.info.market = "none";
			this.buoyLoaded = false;  // w-bouy is not in system yet.

			if (this.novaMissionTimer)
			{
				this.novaMissionTimer.start();
			}
			else
			{
				this.novaMissionTimer = new Timer(this, this.sendShipsAwayForMission, 5, 30);
			}
		}
	}
	if (missionVariables.nova === "NOVA_ESCAPE_HERO")
	{
		missionVariables.nova = "NOVA_ESCAPED_SYSTEM";
	}
};

this.shipLaunchedFromStation = function()
{
	if ((system.sun.isGoingNova || system.sun.hasGoneNova) && missionVariables.nova === "NOVA_ESCAPE_COWARD")
	{
		this.blowUpAllStations();
	}
}

this.shipExitedWitchspace = function()
{
	if (system.sun)
	{
		if (this.flareTimer)
		{
			this.flareTimer.stop();
			delete this.flareTimer;
		}

		if(system.sun.isGoingNova || system.sun.hasGoneNova)
		{
			if (this.novaTimer)
			{
				this.novaTimer.start();
			}
			else
			{
				this.novaTimer = new Timer(this, this.sendShipsAway, 5, 60);
			}
		}
		if(system.sun.isGoingNova) 
		{
			// The first flare up will begin in between 30 seconds and 1 minute
			this.flareTimer = new Timer(this, this.flareUp,  Math.random() * 30 + 30);
		}
	}
};
