/*

oolite-contracts-helpers.js

Helper functions for various types of contracts
 

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
/*global galaxyNumber, missionVariables, system*/


"use strict";


this.name			= "oolite-contracts-helpers";
this.author			= "cim";
this.copyright		= "© 2012-2013 the Oolite team.";
this.description	= "Helper functions for various contracts.";


/* Save and retrieve client names for use in Assassin AIs */
this.startUp = function()
{
	if (missionVariables.oolite_contract_clientnames)
	{
		this.$clientNames = JSON.parse(missionVariables.oolite_contract_clientnames);
	}
	else
	{
		this.$clientNames = [];
		for (var i=0;i<20;i++)
		{
			// one-time initialisation
			this.$clientNames[i] = "";
		}
	}
}


this.playerWillSaveGame = function()
{
	missionVariables.oolite_contract_clientnames = JSON.stringify(this.$clientNames);
}


// set a client name in the random selection
this._setClientName = function(name)
{
	this.$clientNames[Math.floor(Math.random()*20)] = name;
}


// get a random recent (usually) client name
this._getClientName = function()
{
	var idx = Math.floor(Math.random()*20);
	for (var i=0;i<20;i++)
	{
		var name = this.$clientNames[(idx+i)%20];
		if (name != "")
		{
			return name;
		}
	}
	// being requested when no clients recorded, ever!
	// unlikely but might happen
	return expandDescription("%N ")+expandDescription("[nom]");
}




// returns a string containing the necessary number of "hair spaces" to
// pad the currentText string to the specified length in 'em'
this._paddingText = function(currentText, desiredLength)
{
		var hairSpace = String.fromCharCode(31);
		var currentLength = defaultFont.measureString(currentText);
		var hairSpaceLength = defaultFont.measureString(hairSpace);
		// calculate number needed to fill remaining length
		var padsNeeded = Math.floor((desiredLength - currentLength) / hairSpaceLength);
		if (padsNeeded < 1) 
		{
				return "";
		}
		// quick way of generating a repeated string of that number
		return new Array(padsNeeded).join(hairSpace);
}


// gives a text description of the time remaining to deliver this contract
this._timeRemaining = function(contract)
{
		return this._formatTravelTime(this._timeRemainingSeconds(contract));
}


this._timeRemainingSeconds = function(contract) {
		return contract.deadline - clock.seconds;
}


// gives a text description of a reasonable travel time to fulfil contract
this._timeEstimate = function(contract)
{
		// allow 30 minutes in each system on the shortest route
		return this._formatTravelTime(this._timeEstimateSeconds(contract));
}


this._timeEstimateSeconds = function(contract)
{
		return (contract.route.time * 3600) + (contract.route.route.length * 1800);
}


// format the travel time
this._formatTravelTime = function(seconds) {
		// this function uses an hours-only format
		// but provides enough information to use a days&hours format if
		// oolite-contracts-time-format in missiontext.plist is overridden

		// extra minutes are discarded
		var hours = Math.floor(seconds/3600);
		
		var days = Math.floor(hours/24);
		var spareHours = hours % 24;
		
		return expandMissionText("oolite-contracts-time-format",{
				"oolite-contracts-time-format-hours": hours,
				"oolite-contracts-time-format-days": days,
				"oolite-contracts-time-format-spare-hours": spareHours
		});
}


// summarises economy and government in system
this._systemName = function(id)
{
		var info = System.infoForSystem(galaxyNumber,id);
		var name = info.name;
		if(info.concealment < 200) {
			name += " (";
			name += String.fromCharCode(info.government); //chr 0-7 are gov icons
			name += ",";
			name += String.fromCharCode(23-info.economy); //chr 16-23 are eco icons, in reverse order...
			name += ")";
		}
		return name;
}

// sounds
this._soundSuccess = function()
{
		var sound = new SoundSource;
		sound.sound = "[contract-accepted]";
		sound.play();
}

this._soundFailure = function()
{
		var sound = new SoundSource;
		sound.sound = "[contract-rejected]";
		sound.play();
}

// player skill calculation
this._playerSkill = function(rep)
{
	return ((rep*10) + (Math.min(70,Math.sqrt(player.score))))/2;
}