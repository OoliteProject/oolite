/*

oolite-contracts-parcels.js

Script for managing parcel contracts
 

Oolite
Copyright © 2004-2012 Giles C Williams and contributors

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


this.name			= "oolite-contracts-parcels";
this.author			= "cim";
this.copyright		= "© 2012 the Oolite team.";
this.description	= "Parcel delivery contracts.";
this.version		= "1.77";

/* Configuration options */

// OXPs which wish to add a background to the summary pages should
// set this value
this.$parcelSummaryPageBackground = "";


/* Event handlers */

this.startUp = function() 
{
		// stored contents of local main station's parcel contract list
		if (missionVariables.oolite_contracts_parcels)
		{
				this.$parcels = JSON.parse(missionVariables.oolite_contracts_parcels);
		}
		else
		{
				this._initialiseParcelContractsForSystem();
		}

		this._updateMainStationInterfacesList();
}


this.shipWillExitWitchspace = function()
{
		if (!system.isInterstellarSpace && !system.sun.hasGoneNova && system.mainStation)
		{
				// must be a regular system with a main station
				this._initialiseParcelContractsForSystem();
				this._updateMainStationInterfacesList();
		}
}


this.playerWillSaveGame = function()
{
		// encode the contract list to a string for storage in the savegame
		missionVariables.oolite_contracts_parcels = JSON.stringify(this.$parcels);
}


// if the player launches from within the mission screens, reset their
// destination system and HUD settings, which the mission screens may
// have affected.
this.shipWillLaunchFromStation = function() {
		if (this.$suspendedDestination) {
				player.ship.targetSystem = this.$suspendedDestination;
				player.ship.hudHidden = this.$suspendedHUD;
		}
}


/* Interface functions */

// initialise a new parcel contract list for the current system
this._initialiseParcelContractsForSystem = function() 
{
		// clear list
		this.$parcels = [];
		
		// basic range -1 to +3 evenly distributed
		// parcel contracts require far less investment than cargo or passenger
		// so fewer are available
		var numContracts = Math.floor(Math.random()*5) - 1;
		
		// larger systems more likely to have contracts, smaller less likely
		if (system.info.population > 50) 
		{
				numContracts++;
		}
		else if (system.info.population < 30)
		{
				numContracts--;
		}
		// if the player has a bad reputation, reduce the available contract number
		if (player.parcelReputation < 0)
		{
				numContracts += player.parcelReputation;
		}
		// if they have a very good reputation, increase the numbers
		else if (player.parcelReputation > 4)
		{
				numContracts += (player.parcelReputation - 4);
		}
		// always have at least two available for new Jamesons
		if (!missionVariables.oolite_contracts_parcels && numContracts < 2)
		{
				numContracts = 2;
		}

		for (var i = 0; i < numContracts; i++)
		{
				var parcel = new Object;

				// pick a random system to take the parcel to
				var destination = Math.floor(Math.random()*256);

				// discard if chose the current system
				if (destination === system.ID) 
				{
						continue;
				}

				// get the SystemInfo object for the destination
				var destinationInfo = System.infoForSystem(galaxyNumber,destination);
				
				// check that a route to the destination exists
				var routeToDestination = system.info.routeToSystem(destinationInfo);

				// if the system cannot be reached, discard the parcel
				if (!routeToDestination)
				{
						continue;
				}
				
				// we now have a valid destination, so generate the rest of
				// the parcel details

				parcel.destination = destination;
				// we'll need this again later, and route calculation is slow
				parcel.route = routeToDestination;

				parcel.sender = randomName()+" "+randomName();
				parcel.description = expandDescription("[parcel-description]");
				

				// time allowed for delivery is time taken by "fewest jumps"
				// route, plus 10-60%, plus one day
				parcel.deadline = clock.seconds + Math.floor((routeToDestination.time * 3600 * 1.1+(Math.random()/2))) + 86400;

				// total payment is small for these items.
				parcel.payment = Math.floor(
						// 2-3 credits per LY of route
						(routeToDestination.distance * (2+Math.random())) +
						// additional income for route length based on reputation
						(Math.pow(routeToDestination.route.length,1+(0.1*player.parcelReputation))) +
						// small premium for delivery to more dangerous systems
						(2 * Math.pow(7-destinationInfo.government,1.5))
				);

				// add parcel to contract list
				this.$parcels.push(parcel);
		}
		
}

// this should be called every time the contents of this.$parcelContracts
// change, as it updates the summary of the interface entry.
this._updateMainStationInterfacesList = function()
{
		if (this.$parcels.length === 0)
		{
				// no contracts, remove interface if it exists
				system.mainStation.setInterface("oolite-contracts-parcels",null);
		}
		else
		{
				var title = expandMissionText("oolite-contracts-parcels-interface-title",{
						"oolite-contracts-parcels-interface-title-count": this.$parcels.length
				});

				system.mainStation.setInterface("oolite-contracts-parcels",{
						title: title,
						category: expandMissionText("oolite-contracts-parcels-interface-category"),
						summary: expandMissionText("oolite-contracts-parcels-interface-summary"),
						callback: this._parcelContractsScreens.bind(this)
						// could alternatively use "cbThis: this" parameter instead of bind()
				});
		}
}


// if the interface is activated, this function is run.
this._parcelContractsScreens = function(interfaceKey)
{
		// the interfaceKey parameter is not used here, but would be useful if
		// this callback managed more than one interface entry

		this._validateParcels();

		// set up variables used to remember state on the mission screens
		this.$suspendedDestination = null;
		this.$suspendedHUD = false;
		this.$contractIndex = 0;
		this.$routeMode = "LONG_RANGE_CHART_SHORTEST";
		this.$lastOptionChosen = "06_EXIT";

		// start on the summary page if more than one contract is available
		var summary = (this.$parcels.length > 1);

		this._parcelContractsDisplay(summary);
}


// this function is called after the player makes a choice which keeps
// them in the system, and also on initial entry to the system
// to select the appropriate mission screen and display it
this._parcelContractsDisplay = function(summary) {

		// Again. Has to be done on every call to this function, but also
		// has to be done at the start.
		this._validateParcels(); 

		// if there are no parcels (usually because the player has taken
		// the last one) display a message and quit.
		if (this.$parcels.length === 0)
		{
				mission.runScreen({titleKey: "oolite-contracts-parcels-none-available-title",
													 messageKey: "oolite-contracts-parcels-none-available-message"});
				// no callback, just exits contracts system
				return;
		}

		// make sure that the 'currently selected contract' pointer
		// is in bounds
		if (this.$contractIndex >= this.$parcels.length)
		{
				this.$contractIndex = 0;
		}
		else if (this.$contractIndex < 0)
		{
				this.$contractIndex = this.$parcels.length - 1;
		}
		// sub functions display either summary or detail screens
		if (summary)
		{
				this._parcelContractSummaryPage();
		}
		else
		{
				this._parcelContractSinglePage();
		}

}


// display the mission screen for the summary page
this._parcelContractSummaryPage = function()
{
		// column 'tab stops'
		var columns = [14,21,28];

		// column header line
		var headline = expandMissionText("oolite-contracts-parcels-column-cargo");
		// pad to correct length to give a table-like layout
		headline += this._paddingText(headline,columns[0]);
		headline += expandMissionText("oolite-contracts-parcels-column-destination");
		headline += this._paddingText(headline,columns[1]);
		headline += expandMissionText("oolite-contracts-parcels-column-within");
		headline += this._paddingText(headline,columns[2]);
		headline += expandMissionText("oolite-contracts-parcels-column-fee");
		// required because of way choices are displayed.
		headline = " "+headline;

		// setting options dynamically; one contract per line
		var options = new Object;
		var i;
		for (i=0; i<this.$parcels.length; i++)
		{
				// temp variable to simplify following code
				var parcel = this.$parcels[i];
				// write the parcel description, padded to line up with the headers
				var optionText = parcel.description;
				optionText += this._paddingText(optionText, columns[0]);
				optionText += System.infoForSystem(galaxyNumber, parcel.destination).name;
				optionText += this._paddingText(optionText, columns[1]);
				optionText += this._timeRemaining(parcel);
				optionText += this._paddingText(optionText, columns[2]);
				// right-align the fee so that the credits signs line up
				var priceText = formatCredits(parcel.payment,false,true);
				priceText = this._paddingText(priceText, 2.5)+priceText;
				optionText += priceText
				
				// maximum of seven contracts available, so no need to pad the number
				// in the key to maintain alphabetical order
				// needs to be aligned left to line up with the heading
				options["01_CONTRACT_"+i] = { text: optionText, alignment: "LEFT" };
				
				// if there doesn't appear to be sufficient time remaining
				if (this._timeRemainingSeconds(parcel) < this._timeEstimateSeconds(parcel))
				{
						options["01_CONTRACT_"+i].color = "orangeColor";
				}
		}
		// if we've come from the detail screen, make sure the last
		// contract shown there is selected here
		var initialChoice = ["01_CONTRACT_"+this.$contractIndex];

		// next, an empty string gives an unselectable row
		options["02_SPACER"] = ""; 

		// numbered 06 to match the option of the same function in the other branch
		options["06_EXIT"] = expandMissionText("oolite-contracts-parcels-command-quit");
		
		// now need to add further spacing to fill the remaining rows, or
		// the options will end up at the bottom of the screen.
		var rowsToFill = 21;
		if (player.ship.hudHidden)
		{
				rowsToFill = 27;
		}

		for (i = 4 + this.$parcels.length; i < rowsToFill ; i++)
		{
				// each key needs to be unique at this stage.
				options["07_SPACER_"+i] = ""; 
		}

		var missionConfig = {titleKey: "oolite-contracts-parcels-title-summary",
												 message: headline,
												 choices: options,
												 initialChoicesKey: initialChoice}; 
		if (this.$parcelSummaryPageBackground != "") {
				missionConfig.background = this.$parcelSummaryPageBackground;
		}

		// now run the mission screen
		mission.runScreen(missionConfig, this._processParcelChoice);
		
}


// display the mission screen for the contract detail page
this._parcelContractSinglePage = function()
{
		// temp variable to simplify code
		var parcel = this.$parcels[this.$contractIndex];

		// This mission screen uses the long range chart as a backdrop.
		// This means that the first 18 lines are taken up by the chart,
		// and we can't put text there without overwriting the chart.
		// We therefore need to hide the player's HUD, to get the full 27
		// lines.

		if (!player.ship.hudHidden)
		{
				this.$suspendedHUD = true; // note that we hid it, for later
				player.ship.hudHidden = true;
		}

		// We also set the player's witchspace destination temporarily
		// so we need to store the old one in a variable to reset it later
		this.$suspendedDestination = player.ship.targetSystem;

		// That done, we can set the player's destination so the map looks
		// right.
		player.ship.targetSystem = parcel.destination;

		// start with 18 blank lines, since we don't want to overlap the chart
		var message = new Array(18).join("\n");
		
		message += expandMissionText("oolite-contracts-parcels-long-description",{
				"oolite-contracts-parcels-longdesc-sender": parcel.sender,
				"oolite-contracts-parcels-longdesc-contents": this._formatPackageName(parcel.description),
				"oolite-contracts-parcels-longdesc-destination": System.infoForSystem(galaxyNumber,parcel.destination).name,
				"oolite-contracts-parcels-longdesc-deadline": this._timeRemaining(parcel),
				"oolite-contracts-parcels-longdesc-time": this._timeEstimate(parcel),
				"oolite-contracts-parcels-longdesc-payment": formatCredits(parcel.payment,false,true)
		});

		// use a special background
		var backgroundSpecial = "LONG_RANGE_CHART";
		
		// the available options will vary quite a bit, so this rather
		// than a choicesKey in missiontext.plist
		var options = new Object;
		// these are the only options which are always available
		options["05_ACCEPT"] = { 
				text: expandMissionText("oolite-contracts-parcels-command-accept") 
		};

		// if there's not much time left, change the option colour as a warning!
		if (this._timeRemainingSeconds(parcel) < this._timeEstimateSeconds(parcel))
		{
				options["05_ACCEPT"].color = "orangeColor";
		}


		options["06_EXIT"] = expandMissionText("oolite-contracts-parcels-command-quit");
		// if the ship has a working advanced nav array, can switch
		// between 'quickest' and 'shortest' routes
		// (and also upgrade the special background)
		if (player.ship.equipmentStatus("EQ_ADVANCED_NAVIGATIONAL_ARRAY") === "EQUIPMENT_OK")
		{
				backgroundSpecial = this.$routeMode;
				if (this.$routeMode === "LONG_RANGE_CHART_SHORTEST")
				{
						options["01_MODE"] = expandMissionText("oolite-contracts-parcels-command-ana-quickest");
				}
				else
				{
						options["01_MODE"] = expandMissionText("oolite-contracts-parcels-command-ana-shortest");
				}
		}
		// if there's more than one, need options for forward, back, and listing
		if (this.$parcels.length > 1)
		{
				options["02_BACK"] = expandMissionText("oolite-contracts-parcels-command-back");
				options["03_NEXT"] = expandMissionText("oolite-contracts-parcels-command-next");
				options["04_LIST"] = expandMissionText("oolite-contracts-parcels-command-list");
		}
		else
		{
				// if not, we may need to set a different choice
				// we never want 05_ACCEPT to end up selected initially
				if (this.$lastChoice === "02_BACK" || this.$lastChoice === "03_NEXT" || this.$lastChoice === "04_LIST")
				{
						this.$lastChoice = "06_EXIT";
				}
		}

		var title = expandMissionText("oolite-contracts-parcels-title-detail",{
				"oolite-contracts-parcels-title-detail-number": this.$contractIndex+1,
				"oolite-contracts-parcels-title-detail-total": this.$parcels.length
		});

		// finally, after all that setup, actually create the mission screen

		mission.runScreen({
				title: title,
				message: message,
//				background: this.$longRangeChartBackground,
				backgroundSpecial: backgroundSpecial,
				choices: options,
				initialChoicesKey: this.$lastChoice
		},this._processParcelChoice);

}


this._processParcelChoice = function(choice)
{
		// firstly, restore the HUD and witchspace destination if
		// necessary, and clear the stashed values
		if (this.$suspendedDestination !== null)
		{
				player.ship.targetSystem = this.$suspendedDestination;
				this.$suspendedDestination = null;
		}
		if (this.$suspendedHUD)
		{
				player.ship.hudHidden = false;
				this.$suspendedHUD = false;
		}

		if (choice === null)
		{
				// can occur if ship launches mid mission screen
				return;
		}

		// now process the various choices
		if (choice.match(/^01_CONTRACT_/))
		{
				// contract selected from summary page
				// set the index to that contract, and show details
				var index = parseInt(choice.slice(12));
				this.$contractIndex = index;
				this.$lastChoice = "04_LIST";
				this._parcelContractsDisplay(false);
		}
		else if (choice === "01_MODE")
		{
				// advanced navigation array mode flip
				this.$routeMode = (this.$routeMode === "LONG_RANGE_CHART_SHORTEST")?"LONG_RANGE_CHART_QUICKEST":"LONG_RANGE_CHART_SHORTEST";
				this.$lastChoice = "01_MODE";
				this._parcelContractsDisplay(false);
		}
		else if (choice === "02_BACK")
		{
				// reduce contract index (parcelContractsDisplay manages wraparound)
				this.$contractIndex--;
				this.$lastChoice = "02_BACK";
				this._parcelContractsDisplay(false);
		}
		else if (choice === "03_NEXT")
		{
				// increase contract index (parcelContractsDisplay manages wraparound)
				this.$contractIndex++;
				this.$lastChoice = "03_NEXT";
				this._parcelContractsDisplay(false);
		}
		else if (choice === "04_LIST")
		{
				// display the summary page
				this._parcelContractsDisplay(true);
		}
		else if (choice === "05_ACCEPT")
		{
				this._acceptContract();
				// do not leave the setting as accept for the next contract!
				this.$lastChoice = "03_NEXT"; 
				this._parcelContractsDisplay(false);
		}
		// if we get this far without having called parcelContractsDisplay
		// that means either 'exit' or an unrecognised option was chosen
}


// move a parcel from the contracts list to the player's ship
this._acceptContract = function()
{
		var parcel = this.$parcels[this.$contractIndex];

		// give the parcel to the player
		player.ship.addParcel(parcel.sender+"'s "+this._formatPackageName(parcel.description),system.ID,parcel.destination,parcel.deadline,parcel.payment);
		
		// remove the parcel from the station list
		this.$parcels.splice(this.$contractIndex,1);

		// update the interface description
		this._updateMainStationInterfacesList();
}


// removes any expired parcels
this._validateParcels = function() 
{
		var c = this.$parcels.length-1;
		var removed = false;
		// iterate downwards so we can safely remove as we go
		for (var i=c;i>=0;i--)
		{
				// if the time remaining is less than 1/3 of the estimated
				// delivery time, even in the best case it's probably not
				// going to get there.

				if (this._timeRemainingSeconds(this.$parcels[i]) < this._timeEstimateSeconds(this.$parcels[i]) / 3)
				{
						// remove it
						this.$parcels.splice(i,1);
						removed = true;
				}
		}
		if (removed) 
		{
				// update the interface description if we removed any
				this._updateMainStationInterfacesList();
		}
}


/* Utility functions */

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


// gives a text description of the time remaining to deliver this parcel
this._timeRemaining = function(parcel)
{
		return this._formatTravelTime(this._timeRemainingSeconds(parcel));
}


this._timeRemainingSeconds = function(parcel) {
		return parcel.deadline - clock.seconds;
}


// gives a text description of a reasonable travel time to deliver this parcel
this._timeEstimate = function(parcel)
{
		// allow 30 minutes in each system on the shortest route
		return this._formatTravelTime(this._timeEstimateSeconds(parcel));
}


this._timeEstimateSeconds = function(parcel)
{
		return (parcel.route.time * 3600) + (parcel.route.route.length * 1800);
}


// format the travel time
this._formatTravelTime = function(seconds) {
		// this function uses an hours-only format
		// but provides enough information to use a days&hours format if
		// oolite-contracts-parcels-time-format in missiontext.plist is overridden

		// extra minutes are discarded
		var hours = Math.floor(seconds/3600);
		
		var days = Math.floor(hours/24);
		var spareHours = hours % 24;
		
		return expandMissionText("oolite-contracts-parcels-time-format",{
				"oolite-contracts-parcels-time-format-hours": hours,
				"oolite-contracts-parcels-time-format-days": days,
				"oolite-contracts-parcels-time-format-spare-hours": spareHours
		});
}

// lower-cases the initial letter of the package contents
this._formatPackageName = function(name) {
		return name.charAt(0).toLowerCase() + name.slice(1);
}


