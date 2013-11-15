/*

oolite-contracts-cargo.js

Script for managing cargo contracts
 

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


this.name			= "oolite-contracts-cargo";
this.author			= "cim";
this.copyright		= "© 2012-2013 the Oolite team.";
this.description	= "Cargo delivery contracts.";
this.version		= "1.79";

/**** Configuration options and API ****/

/* OXPs which wish to add a background to the summary pages should
   set this value */
this.$cargoSummaryPageBackground = "";
/* OXPs which wish to add an overlay to the cargo mission screens
   should set this value */
this.$cargoPageOverlay = "";


/* this._addCargoContractToSystem(cargo)
 * This function adds the defined cargo contract to the local main station's
 * interface list. A contract definition is an object with the following
 * parameters, all required:
 * 
 * destination: system ID of destination system
 * commodity:   the cargo type
 * size:        the number of units of cargo
 * deadline:    the deadline for delivery, in clock seconds
 * payment:     the payment for delivery on time, in credits
 * 
 * and optionally, the following parameters:
 *
 * deposit:     the deposit payment required by the player (default 0)
 * route:       a route object generated with system.info.routeToSystem
 *              describing the route between the source and destination 
 *              systems.
 * 
 * If this is not specified, it will be generated automatically.
 * 
 * The function will return true if the contract can be added, false
 * otherwise.
 */
this._addCargoContractToSystem = function(cargo)
{
		if (!system.mainStation)
		{
				log(this.name,"Contracts require a main station");
				return false;
		}
		if (cargo.destination < 0 || cargo.destination > 255)
		{
				log(this.name,"Rejected contract: destination missing or invalid");
				return false;
		}
		if (cargo.deadline <= clock.adjustedSeconds)
		{
				log(this.name,"Rejected contract: deadline invalid");
				return false;
		}
		if (cargo.payment < 0)
		{
				log(this.name,"Rejected contract: payment invalid");
				return false;
		}
		if (!cargo.size || cargo.size < 1)
		{
				log(this.name,"Rejected contract: size invalid");
				return false;
		}
		if (!cargo.commodity)
		{
				log(this.name,"Rejected contract: commodity unspecified");
				return false;
		}
		if (!system.mainStation.market[cargo.commodity])
		{
				log(this.name,"Rejected contract: commodity invalid");
				return false;
		}

		if (!cargo.route)
		{
				var destinationInfo = System.infoForSystem(galaxyNumber,cargo.destination);
				cargo.route = system.info.routeToSystem(destinationInfo);
				if (!cargo.route)
				{
						log(this.name,"Rejected contract: route invalid");
						return false;
				}
		}
		if (!cargo.deposit)
		{
				cargo.deposit = 0;
		}
		else if (cargo.deposit >= cargo.payment)
		{
				log(this.name,"Rejected contract: deposit higher than total payment");
				return false;
		}

		this.$contracts.push(cargo);
		this._updateMainStationInterfacesList();
		return true;
}



/**** Internal methods. Do not call these from OXPs as they may change
 **** without warning. ****/

/* Event handlers */

this.startUp = function() 
{
		this.$helper = worldScripts["oolite-contracts-helpers"];

		this.$suspendedDestination = null;
		this.$suspendedHUD = false;

		// stored contents of local main station's parcel contract list
		if (missionVariables.oolite_contracts_cargo)
		{
				this.$contracts = JSON.parse(missionVariables.oolite_contracts_cargo);
		}
		else
		{
				this._initialiseCargoContractsForSystem();
		}

		this._updateMainStationInterfacesList();
}


this.shipWillExitWitchspace = function()
{
		if (!system.isInterstellarSpace && !system.sun.hasGoneNova && system.mainStation)
		{
				// must be a regular system with a main station
				this._initialiseCargoContractsForSystem();
				this._updateMainStationInterfacesList();
		}
}


this.playerWillSaveGame = function()
{
		// encode the contract list to a string for storage in the savegame
		missionVariables.oolite_contracts_cargo = JSON.stringify(this.$contracts);
}


// when the player exits the mission screens, reset their destination
// system and HUD settings, which the mission screens may have
// affected.
this.shipWillLaunchFromStation = function() 
{
		this._resetViews();
}


this.guiScreenWillChange = function(to, from)
{
		this._resetViews();
}


this.guiScreenChanged = function(to, from)
{
		if (to != "GUI_SCREEN_MISSION")
		{
				this._resetViews();
		}
}


/* Interface functions */

// resets HUD and jump destination
this._resetViews = function()
{
		if (this.$suspendedHUD !== false)
		{
				player.ship.hudHidden = false;
				this.$suspendedHUD = false;
		}
		if (this.$suspendedDestination !== null)
		{
				player.ship.targetSystem = this.$suspendedDestination;
				this.$suspendedDestination = null;
		}
}

// initialise a new cargo contract list for the current system
this._initialiseCargoContractsForSystem = function() 
{
		// clear list
		this.$contracts = [];

		// this is not the same algorithm as in 1.76, but should give
		// similar results with comparable efficiency.

		// no point in generating too many, as route-finding is slow
		var numContracts = Math.floor(5*Math.random()+5*Math.random()+5*Math.random()+(player.contractReputationPrecise*Math.random()));
		if (player.contractReputationPrecise >= 0 && numContracts < 5)
		{
				numContracts += 5;
		}
		if (numContracts > 16)
		{
				numContracts = 16;
		}
		else if (numContracts < 0)
		{
				numContracts = 0;
		}
		// some of these possible contracts may be discarded later on

		for (var i = 0; i < numContracts; i++)
		{
				var cargo = new Object;

				// pick a random system to take the goods to
				var destination = Math.floor(Math.random()*256);

				// discard if chose the current system
				if (destination === system.ID) 
				{
						continue;
				}

				// get the SystemInfo object for the destination
				var destinationInfo = System.infoForSystem(galaxyNumber,destination);

				var daysUntilDeparture = 1+(Math.random()*(7+player.contractReputationPrecise-destinationInfo.government));
				if (daysUntilDeparture <= 0)
				{ 
						// loses some more contracts if reputation negative
						continue;
				}
				
				var commodities = Object.keys(system.mainStation.market);
				var attempts = 0;
				do {
						var remotePrice = 0;
						attempts++;
						var commodity = commodities[Math.floor(Math.random()*commodities.length)];
						// sub-tc contracts only available for top rep
						if (system.mainStation.market[commodity].quantityUnit != 0 && player.contractReputationPrecise < 6.5) 
						{
						} 
						// ignore commodities with 0 availability here
						else if (system.mainStation.market[commodity].quantity == 0)
						{
						}
						else
						{
								remotePrice = this._priceForCommodity(system.mainStation.market[commodity],destinationInfo.economy);
						}
				} while (remotePrice < system.mainStation.market[commodity].price/20 && attempts < 10);
				if (attempts == 10)
				{
						// failed to find a good one.
						continue;
				}
				cargo.commodity = commodity;

				var amount = 0;
				while (amount < 30)
				{
						var unitsize = 1;
						// larger unit sizes for kg/g commodities
						if (system.mainStation.market[commodity].quantityUnit == 1)
						{
								unitsize += Math.floor(Math.random()*6)+Math.floor(Math.random()*6)+Math.floor(Math.random()*6);
						}
						else if (system.mainStation.market[commodity].quantityUnit == 2)
						{
								unitsize += Math.floor(Math.random()*16)+Math.floor(Math.random()*11)+Math.floor(Math.random()*6);
						}
						amount += (1+Math.floor(Math.random()*32))*(1+Math.floor(Math.random()*16))*unitsize;
				}

				if (amount > 125 && system.mainStation.market[commodity].quantityUnit == 0)
				{
						// reduce the number of contracts only suitable for Anacondas
						amount = Math.floor(amount/Math.floor(1+(Math.random()*4)));
				}
				cargo.size = amount;

				// adjustment to prices based on quantity (larger = more profitable)
				var discount = Math.min(10+Math.floor(amount/10),35);
				
				var unitPrice = system.mainStation.market[commodity].price * (100-discount) / 1000;
				var localValue = Math.floor(unitPrice * amount);
				remotePrice = remotePrice * (200+discount) / 200;
				var remoteValue = Math.floor(remotePrice * amount);
				var profit = remoteValue-localValue;

				// skip if unprofitable
				if (profit <= 100)
				{
						continue;
				}

				// check that a route to the destination exists
				// route calculation is expensive so leave this check to last
				var routeToDestination = system.info.routeToSystem(destinationInfo);

				// if the system cannot be reached, ignore this contract
				if (!routeToDestination)
				{
						continue;
				}

				// we now have a valid destination, so generate the rest of
				// the parcel details

				cargo.destination = destination;
				// we'll need this again later, and route calculation is slow
				cargo.route = routeToDestination;

				// higher share for transporter for longer routes, less safe systems
				var share = 100 + destinationInfo.government - (10*routeToDestination.route.length);
				if (share < 10) 
				{
						share = 10;
				}
				share = 100-share;
				
				// safety: now multiply the fee by 2 compared with 1.76 contracts
				// prevents exploit discovered by Mad Hollander at
				// http://aegidian.org/bb/viewtopic.php?p=188127
				localValue *= 2;
				// this may need to be raised further

				// absolute value of profit remains the same
				var fee = localValue + Math.floor(profit * (share/100));
				fee -= fee % 20; // round to nearest 20 credits;

				cargo.payment = fee;
				cargo.deposit = localValue - (localValue % 20);
				if (cargo.deposit >= cargo.payment) 
				{
						// rare but not impossible; last safety check
						return;
				}

				// time allowed for delivery is time taken by "fewest jumps"
				// route, plus timer above. Higher reputation makes longer
				// times available.
				cargo.deadline = clock.adjustedSeconds + Math.floor(daysUntilDeparture*86400)+(cargo.route.time*3600);

				// add parcel to contract list
				this._addCargoContractToSystem(cargo);
		}

}


// this should be called every time the contents of this.$parcels
// changes, as it updates the summary of the interface entry.
this._updateMainStationInterfacesList = function()
{
		if (this.$contracts.length === 0)
		{
				// no contracts, remove interface if it exists
				system.mainStation.setInterface("oolite-contracts-cargo",null);
		}
		else
		{
				var title = expandMissionText("oolite-contracts-cargo-interface-title",{
						"oolite-contracts-cargo-interface-title-count": this.$contracts.length
				});

				system.mainStation.setInterface("oolite-contracts-cargo",{
						title: title,
						category: expandMissionText("oolite-contracts-cargo-interface-category"),
						summary: expandMissionText("oolite-contracts-cargo-interface-summary"),
						callback: this._cargoContractsScreens.bind(this)
						// could alternatively use "cbThis: this" parameter instead of bind()
				});
		}
}


// if the interface is activated, this function is run.
this._cargoContractsScreens = function(interfaceKey)
{
		// the interfaceKey parameter is not used here, but would be useful if
		// this callback managed more than one interface entry

		this._validateContracts();

		// set up variables used to remember state on the mission screens
		this.$suspendedDestination = null;
		this.$suspendedHUD = false;
		this.$contractIndex = 0;
		this.$routeMode = "LONG_RANGE_CHART_SHORTEST";
		this.$lastOptionChosen = "06_EXIT";

		// start on the summary page if more than one contract is available
		var summary = (this.$contracts.length > 1);

		this._cargoContractsDisplay(summary);
}


// this function is called after the player makes a choice which keeps
// them in the system, and also on initial entry to the system
// to select the appropriate mission screen and display it
this._cargoContractsDisplay = function(summary) {

		// Again. Has to be done on every call to this function, but also
		// has to be done at the start.
		this._validateContracts(); 

		// if there are no contracts (usually because the player has taken
		// the last one) display a message and quit.
		if (this.$contracts.length === 0)
		{
				var missionConfig = {titleKey: "oolite-contracts-cargo-none-available-title",
													 messageKey: "oolite-contracts-cargo-none-available-message",
													 allowInterrupt: true,
													 screenID: "oolite-contracts-cargo-none",
													 exitScreen: "GUI_SCREEN_INTERFACES"};
				if (this.$cargoSummaryPageBackground != "") {
						missionConfig.background = this.$cargoSummaryPageBackground;
				}
				if (this.$cargoPageOverlay != "") {
						missionConfig.overlay = this.$cargoPageOverlay;
				}
				mission.runScreen(missionConfig);
				// no callback, just exits contracts system
				return;
		}

		// make sure that the 'currently selected contract' pointer
		// is in bounds
		if (this.$contractIndex >= this.$contracts.length)
		{
				this.$contractIndex = 0;
		}
		else if (this.$contractIndex < 0)
		{
				this.$contractIndex = this.$contracts.length - 1;
		}
		// sub functions display either summary or detail screens
		if (summary)
		{
				this._cargoContractSummaryPage();
		}
		else
		{
				this._cargoContractSinglePage();
		}

}


// display the mission screen for the summary page
this._cargoContractSummaryPage = function()
{
		// column 'tab stops'
		var columns = [10,16,21,26];

		// column header line
		var headline = expandMissionText("oolite-contracts-cargo-column-goods");
		// pad to correct length to give a table-like layout
		headline += this.$helper._paddingText(headline,columns[0]);
		headline += expandMissionText("oolite-contracts-cargo-column-destination");
		headline += this.$helper._paddingText(headline,columns[1]);
		headline += expandMissionText("oolite-contracts-cargo-column-within");
		headline += this.$helper._paddingText(headline,columns[2]);
		headline += expandMissionText("oolite-contracts-cargo-column-deposit");
		headline += this.$helper._paddingText(headline,columns[3]);
		headline += expandMissionText("oolite-contracts-cargo-column-fee");
		// required because of way choices are displayed.
		headline = " "+headline;

		// setting options dynamically; one contract per line
		var options = new Object;
		var i;
		var anyWithSpace = false;
		for (i=0; i<this.$contracts.length; i++)
		{
				// temp variable to simplify following code
				var cargo = this.$contracts[i];
				// write the description, padded to line up with the headers
				var optionText = this._descriptionForGoods(cargo);
				optionText += this.$helper._paddingText(optionText, columns[0]);
				optionText += System.infoForSystem(galaxyNumber, cargo.destination).name;
				optionText += this.$helper._paddingText(optionText, columns[1]);
				optionText += this.$helper._timeRemaining(cargo);
				optionText += this.$helper._paddingText(optionText, columns[2]);
				// right-align the fee so that the credits signs line up
				var priceText = formatCredits(cargo.deposit,false,true);
				priceText = this.$helper._paddingText(priceText, 3.25)+priceText;
				optionText += priceText
				optionText += this.$helper._paddingText(optionText, columns[3]);
				// right-align the fee so that the credits signs line up
				priceText = formatCredits(cargo.payment-cargo.deposit,false,true);
				priceText = this.$helper._paddingText(priceText, 3.25)+priceText;
				optionText += priceText
				
				// need to pad the number in the key to maintain alphabetical order
				var istr = i;
				if (i < 10)
				{
						istr = "0"+i;
				}
				// needs to be aligned left to line up with the heading
				options["01_CONTRACT_"+istr] = { text: optionText, alignment: "LEFT" };

				// check if there's space for this contract
				if (!this._hasSpaceFor(cargo))
				{
						options["01_CONTRACT_"+istr].color = "darkGrayColor";
				}
				else
				{
						anyWithSpace = true;
						// if there doesn't appear to be sufficient time remaining
						if (this.$helper._timeRemainingSeconds(cargo) < this.$helper._timeEstimateSeconds(cargo))
						{
								options["01_CONTRACT_"+istr].color = "orangeColor";
						}
				}
		}
		// if we've come from the detail screen, make sure the last
		// contract shown there is selected here
		var icstr = this.$contractIndex;
		if (icstr < 10)
		{
				icstr = "0"+this.$contractIndex;
		}
		var initialChoice = "01_CONTRACT_"+icstr;
		// if none of them have any space...
		if (!anyWithSpace)
		{
				initialChoice = "06_EXIT";
		}

		// next, an empty string gives an unselectable row
		options["02_SPACER"] = ""; 

		// numbered 06 to match the option of the same function in the other branch
		options["06_EXIT"] = expandMissionText("oolite-contracts-cargo-command-quit");
		
		// now need to add further spacing to fill the remaining rows, or
		// the options will end up at the bottom of the screen.
		var rowsToFill = 21;
		if (player.ship.hudHidden)
		{
				rowsToFill = 27;
		}

		for (i = 4 + this.$contracts.length; i < rowsToFill ; i++)
		{
				// each key needs to be unique at this stage.
				options["07_SPACER_"+i] = ""; 
		}

		var missionConfig = {titleKey: "oolite-contracts-cargo-title-summary",
												 message: headline,
												 allowInterrupt: true,
												 screenID: "oolite-contracts-cargo-summary",
												 exitScreen: "GUI_SCREEN_INTERFACES",
												 choices: options,
												 initialChoicesKey: initialChoice}; 
		if (this.$cargoSummaryPageBackground != "") {
				missionConfig.background = this.$cargoSummaryPageBackground;
		}
		if (this.$cargoPageOverlay != "") {
				missionConfig.overlay = this.$cargoPageOverlay;
		}

		// now run the mission screen
		mission.runScreen(missionConfig, this._processCargoChoice, this);
		
}


// display the mission screen for the contract detail page
this._cargoContractSinglePage = function()
{
		// temp variable to simplify code
		var cargo = this.$contracts[this.$contractIndex];

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
		player.ship.targetSystem = cargo.destination;

		// start with 18 blank lines, since we don't want to overlap the chart
		var message = new Array(18).join("\n");
		
		message += expandMissionText("oolite-contracts-cargo-long-description",{
				"oolite-contracts-cargo-longdesc-goods": this._descriptionForGoods(cargo),
				"oolite-contracts-cargo-longdesc-destination": this.$helper._systemName(cargo.destination),
				"oolite-contracts-cargo-longdesc-deadline": this.$helper._timeRemaining(cargo),
				"oolite-contracts-cargo-longdesc-time": this.$helper._timeEstimate(cargo),
				"oolite-contracts-cargo-longdesc-payment": formatCredits(cargo.payment,false,true),
				"oolite-contracts-cargo-longdesc-deposit": formatCredits(cargo.deposit,false,true)
		});

		// use a special background
		var backgroundSpecial = "LONG_RANGE_CHART";
		
		// the available options will vary quite a bit, so this rather
		// than a choicesKey in missiontext.plist
		var options = new Object;
		// this is the only option which is always available
		options["06_EXIT"] = expandMissionText("oolite-contracts-cargo-command-quit");
		
		// if the player has sufficient space
		if (this._hasSpaceFor(cargo))
		{
				options["05_ACCEPT"] = { 
						text: expandMissionText("oolite-contracts-cargo-command-accept") 
				};
				
				// if there's not much time left, change the option colour as a warning!
				if (this.$helper._timeRemainingSeconds(cargo) < this.$helper._timeEstimateSeconds(cargo))
				{
						options["05_ACCEPT"].color = "orangeColor";
				}
		}
		else
		{
				options["05_UNAVAILABLE"] = {
						text: expandMissionText("oolite-contracts-cargo-command-unavailable"),
						color: "darkGrayColor",
						unselectable: true
				};
		}

		// if the ship has a working advanced nav array, can switch
		// between 'quickest' and 'shortest' routes
		// (and also upgrade the special background)
		if (player.ship.equipmentStatus("EQ_ADVANCED_NAVIGATIONAL_ARRAY") === "EQUIPMENT_OK")
		{
				backgroundSpecial = this.$routeMode;
				if (this.$routeMode === "LONG_RANGE_CHART_SHORTEST")
				{
						options["01_MODE"] = expandMissionText("oolite-contracts-cargo-command-ana-quickest");
				}
				else
				{
						options["01_MODE"] = expandMissionText("oolite-contracts-cargo-command-ana-shortest");
				}
		}
		// if there's more than one, need options for forward, back, and listing
		if (this.$contracts.length > 1)
		{
				options["02_BACK"] = expandMissionText("oolite-contracts-cargo-command-back");
				options["03_NEXT"] = expandMissionText("oolite-contracts-cargo-command-next");
				options["04_LIST"] = expandMissionText("oolite-contracts-cargo-command-list");
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

		var title = expandMissionText("oolite-contracts-cargo-title-detail",{
				"oolite-contracts-cargo-title-detail-number": this.$contractIndex+1,
				"oolite-contracts-cargo-title-detail-total": this.$contracts.length
		});

		// finally, after all that setup, actually create the mission screen

		var missionConfig = {
				title: title,
				message: message,
				allowInterrupt: true,
				screenID: "oolite-contracts-cargo-details",
				exitScreen: "GUI_SCREEN_INTERFACES",
				backgroundSpecial: backgroundSpecial,
				choices: options,
				initialChoicesKey: this.$lastChoice
		};

		if (this.$cargoPageOverlay != "") {
				missionConfig.overlay = this.$cargoPageOverlay;
		}

		mission.runScreen(missionConfig,this._processCargoChoice, this);

}


this._processCargoChoice = function(choice)
{
		this._resetViews();
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
				var index = parseInt(choice.slice(12),10);
				this.$contractIndex = index;
				this.$lastChoice = "04_LIST";
				this._cargoContractsDisplay(false);
		}
		else if (choice === "01_MODE")
		{
				// advanced navigation array mode flip
				this.$routeMode = (this.$routeMode === "LONG_RANGE_CHART_SHORTEST")?"LONG_RANGE_CHART_QUICKEST":"LONG_RANGE_CHART_SHORTEST";
				this.$lastChoice = "01_MODE";
				this._cargoContractsDisplay(false);
		}
		else if (choice === "02_BACK")
		{
				// reduce contract index (cargoContractsDisplay manages wraparound)
				this.$contractIndex--;
				this.$lastChoice = "02_BACK";
				this._cargoContractsDisplay(false);
		}
		else if (choice === "03_NEXT")
		{
				// increase contract index (cargoContractsDisplay manages wraparound)
				this.$contractIndex++;
				this.$lastChoice = "03_NEXT";
				this._cargoContractsDisplay(false);
		}
		else if (choice === "04_LIST")
		{
				// display the summary page
				this._cargoContractsDisplay(true);
		}
		else if (choice === "05_ACCEPT")
		{
				this._acceptContract();
				// do not leave the setting as accept for the next contract!
				this.$lastChoice = "03_NEXT"; 
				this._cargoContractsDisplay(false);
		}
		// if we get this far without having called cargoContractsDisplay
		// that means either 'exit' or an unrecognised option was chosen
}


// move goods from the contracts list to the player's ship (if possible)
this._acceptContract = function()
{
		var cargo = this.$contracts[this.$contractIndex];

		if (cargo.deposit > player.credits)
		{
				this.$helper._soundFailure();
				return;
		}

		// give the cargo to the player
		var result = player.ship.awardContract(cargo.size,cargo.commodity,system.ID,cargo.destination,cargo.deadline,cargo.payment,cargo.deposit);
		
		if (result)
		{
				// pay the deposit
				player.credits -= cargo.deposit;

				// remove the contract from the station list
				this.$contracts.splice(this.$contractIndex,1);

				// update the interface description
				this._updateMainStationInterfacesList();

				this.$helper._soundSuccess();
		}
		else
		{
				// else must have had manifest change recently
				// (unlikely, but another OXP could have done it)
				this.$helper._soundFailure();
		}
}


// removes any expired contracts
this._validateContracts = function() 
{
		var c = this.$contracts.length-1;
		var removed = false;
		// iterate downwards so we can safely remove as we go
		for (var i=c;i>=0;i--)
		{
				// if the time remaining is less than 1/3 of the estimated
				// delivery time, even in the best case it's probably not
				// going to get there.

				if (this.$helper._timeRemainingSeconds(this.$contracts[i]) < this.$helper._timeEstimateSeconds(this.$contracts[i]) / 3)
				{
						// remove it
						this.$contracts.splice(i,1);
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

// calculates a sample price for a commodity in a distant system
this._priceForCommodity = function(commodity,economy) 
{
		var rnd = Math.floor(Math.random()*256);
		var price = 0.4*(Math.floor(parseInt(commodity.marketBasePrice,10) + (rnd & parseInt(commodity.marketMaskPrice,10)) + (economy*parseInt(commodity.marketEcoAdjustPrice,10)))&255);
		return price;
}

// description of the cargo
this._descriptionForGoods = function(cargo)
{
		var unit = "tons";
		if (system.mainStation.market[cargo.commodity].quantityUnit == "1")
		{
				unit = "kilograms";
		}
		else if (system.mainStation.market[cargo.commodity].quantityUnit == "2")
		{
				unit = "grams";
		}
				
		return cargo.size+expandDescription("[cargo-"+unit+"-symbol]")+" "+displayNameForCommodity(cargo.commodity);
}

// check if player's ship has space for the cargo and can afford the deposit
this._hasSpaceFor = function(cargo)
{
		if (cargo.deposit > player.credits)
		{
				return false;
		}
		var amountInTC = cargo.size;
		if (system.mainStation.market[cargo.commodity].quantityUnit == "1")
		{
				var spareSafe = 499-(player.ship.manifest[cargo.commodity] % 1000);
				amountInTC -= spareSafe;
				amountInTC = Math.ceil(amountInTC/1000);
				if (amountInTC < 0) 
				{
						amountInTC = 0;
				}
		}
		else if (system.mainStation.market[cargo.commodity].quantityUnit == "2")
		{
				var spareSafe = 499999-(player.ship.manifest[cargo.commodity] % 1000000);
				amountInTC -= spareSafe;
				amountInTC = Math.ceil(amountInTC/1000000);
				if (amountInTC < 0) 
				{
						amountInTC = 0;
				}
		}

		return (amountInTC <= player.ship.cargoSpaceAvailable);
}