/*

oolite-contracts-passengers.js

Script for managing passenger contracts
 

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


this.name			= "oolite-contracts-passengers";
this.author			= "cim";
this.copyright		= "© 2012-2013 the Oolite team.";
this.description	= "Parcel delivery contracts.";
this.version		= "1.79";

/**** Configuration options and API ****/

/* OXPs which wish to add a background to the summary pages should
   set this value */
this.$passengerSummaryPageBackground = "";
/* OXPs which wish to add an overlay to the passenger mission screens
   should set this value */
this.$passengerPageOverlay = "";


/* this._addPassengerToSystem(passenger)
 * This function adds the defined passenger to the local main station's
 * interface list. A passenger definition is an object with the following
 * parameters, all required:
 * 
 * destination: system ID of destination system
 * name:        the name of the passenger (max 40 chars)
 * species:     the species of the passenger (max 40 chars)
 * deadline:    the deadline for delivery, in clock seconds
 * payment:     the payment for delivery on time, in credits
 * 
 * and optionally, the following parameters:
 *
 * skill:       the skill level required by the client (default 0)
 * risk:        the risk level of the contract (0-2, default 0)
 * advance:     the payment for taking the passenger onboard (default 0)
 * route:       a route object generated with system.info.routeToSystem
 *              describing the route between the source and destination 
 *              systems.
 * 
 * If this is not specified, it will be generated automatically.
 * 
 * The function will return true if the passenger can be added, false
 * otherwise.
 */
this._addPassengerToSystem = function(passenger)
{
	if (!system.mainStation)
	{
		log(this.name,"Contracts require a main station");
		return false;
	}
	if (!passenger.name || passenger.name.length > 40)
	{
		log(this.name,"Rejected passenger: name missing or too long");
		return false;
	}
	if (passenger.destination < 0 || passenger.destination > 255)
	{
		log(this.name,"Rejected passenger: destination missing or invalid");
		return false;
	}
	if (passenger.deadline <= clock.adjustedSeconds)
	{
		log(this.name,"Rejected passenger: deadline invalid");
		return false;
	}
	if (passenger.payment < 0)
	{
		log(this.name,"Rejected passenger: payment invalid");
		return false;
	}
	if (!passenger.route)
	{
		var destinationInfo = System.infoForSystem(galaxyNumber,passenger.destination);
		passenger.route = system.info.routeToSystem(destinationInfo);
		if (!passenger.route)
		{
			log(this.name,"Rejected passenger: route invalid");
			return false;
		}
	}
	if (!passenger.advance)
	{
		passenger.advance = 0;
	}
	if (!passenger.risk)
	{
		passenger.risk = 0;
	}
	if (!passenger.skill)
	{
		passenger.skill = 0;
	}
	else if (passenger.skill > 70)
	{
		passenger.skill = 70;
	}

	this.$passengers.push(passenger);
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
		if (missionVariables.oolite_contracts_passengers)
		{
				this.$passengers = JSON.parse(missionVariables.oolite_contracts_passengers);
		}
		else
		{
				this._initialisePassengerContractsForSystem();
		}

		this._updateMainStationInterfacesList();
}


this.shipWillExitWitchspace = function()
{
		if (!system.isInterstellarSpace && !system.sun.hasGoneNova && system.mainStation)
		{
				// must be a regular system with a main station
				this._initialisePassengerContractsForSystem();
				this._updateMainStationInterfacesList();
		}
}


this.playerWillSaveGame = function()
{
		// encode the contract list to a string for storage in the savegame
		missionVariables.oolite_contracts_passengers = JSON.stringify(this.$passengers);
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

// initialise a new passenger contract list for the current system
this._initialisePassengerContractsForSystem = function() 
{
	// clear list
	this.$passengers = [];

	// no point in generating too many, but generally want 5 or more
	// some of them will be discarded later
	var numContracts = Math.floor(5*Math.random()+5*Math.random()+5*Math.random()+(player.passengerReputationPrecise*Math.random()));
	if (player.passengerReputationPrecise >= 0 && numContracts < 5)
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
		var passenger = new Object;

		// pick a random system to take the passenger to
		var destination = Math.floor(Math.random()*256);

		// discard if chose the current system
		if (destination === system.ID) 
		{
			continue;
		}

		// get the SystemInfo object for the destination
		var destinationInfo = System.infoForSystem(galaxyNumber,destination);

		var daysUntilDeparture = 1+(Math.random()*(7+player.passengerReputationPrecise-destinationInfo.government));
		if (daysUntilDeparture <= 0)
		{ 
			// loses some more contracts if reputation negative
			continue;
		}
		
		// check that a route to the destination exists
		var routeToDestination = system.info.routeToSystem(destinationInfo);

		// if the system cannot be reached, ignore this contract
		if (!routeToDestination)
		{
			continue;
		}
		
		// we now have a valid destination, so generate the rest of
		// the parcel details

		passenger.destination = destination;
		// we'll need this again later, and route calculation is slow
		passenger.route = routeToDestination;
		
		if (Math.random() < 0.5) // 50% local inhabitant
		{
			passenger.species = system.info.inhabitant;
		}
		else // 50% random species (which will be 50%ish human)
		{
			passenger.species = System.infoForSystem(galaxyNumber,Math.floor(Math.random()*256)).inhabitant;
		}

		if (passenger.species.match(new RegExp(expandDescription("[human-word]"),"i")))
		{
			passenger.name = expandDescription("%R ")+expandDescription("[nom]");
		}
		else
		{
			passenger.name = randomName()+" "+randomName();
		}

		passenger.risk = Math.floor(Math.random()*3);
		passenger.species = expandDescription("[passenger-description-risk"+passenger.risk+"]")+" "+passenger.species;

		// time allowed for delivery is time taken by "fewest jumps"
		// route, plus timer above. Higher reputation makes longer
		// times available.
		var dtime = Math.floor(daysUntilDeparture*86400)+(passenger.route.time*3600);
		passenger.deadline = clock.adjustedSeconds + dtime;
		if (passenger.risk < 2 && destinationInfo.government <= 1 && Math.random() < 0.5)
		{
			passenger.risk++;
		}
		
		// total payment is:
		passenger.payment = Math.floor(
			// payment per hop (higher at rep > 5)
			5 * Math.pow(routeToDestination.route.length-1, (passenger.risk*0.2) + (player.passengerReputationPrecise > 5 ? 2.45 : 2.3)) +
				// payment by route length
				routeToDestination.distance * (8+(Math.random()*8)) +
				// premium for delivery to more dangerous systems
				(5 * (7-destinationInfo.government) * (7-destinationInfo.government))
		);
		passenger.payment *= (Math.random()+Math.random()+Math.random()+Math.random())/2;

		var prudence = (2*Math.random())-1;
		var desperation = (Math.random()*(0.5+passenger.risk)) * (1+1/(Math.max(0.5,dtime-(routeToDestination.time * 3600))));
		var competency = Math.max(50,(routeToDestination.route.length-1)*(1+(passenger.risk*2)));
		if(passenger.risk == 0)
		{
			competency -= 10;
		}
		passenger.payment = Math.floor(passenger.payment * (1+(0.4*prudence)));
		passenger.payment += (passenger.risk * 200);
		passenger.skill = competency + 20*(prudence-desperation);

		passenger.advance = Math.min(passenger.payment*0.9,Math.max(0,Math.floor(passenger.payment * (0.05 + (0.1*desperation) + (0.02*player.passengerReputationPrecise))))); // some% up front
		passenger.payment -= passenger.advance;

		// add passenger to contract list
		this._addPassengerToSystem(passenger);
	}

}


// this should be called every time the contents of this.$passengers
// changes, as it updates the summary of the interface entry.
this._updateMainStationInterfacesList = function()
{
		if (this.$passengers.length === 0)
		{
				// no contracts, remove interface if it exists
				system.mainStation.setInterface("oolite-contracts-passengers",null);
		}
		else
		{
				var title = expandMissionText("oolite-contracts-passengers-interface-title",{
						"oolite-contracts-passengers-interface-title-count": this.$passengers.length
				});

				system.mainStation.setInterface("oolite-contracts-passengers",{
						title: title,
						category: expandMissionText("oolite-contracts-passengers-interface-category"),
						summary: expandMissionText("oolite-contracts-passengers-interface-summary"),
						callback: this._passengerContractsScreens.bind(this)
						// could alternatively use "cbThis: this" parameter instead of bind()
				});
		}
}


// if the interface is activated, this function is run.
this._passengerContractsScreens = function(interfaceKey)
{
		// the interfaceKey parameter is not used here, but would be useful if
		// this callback managed more than one interface entry

		this._validatePassengers();

		// set up variables used to remember state on the mission screens
		this.$suspendedDestination = null;
		this.$suspendedHUD = false;
		this.$contractIndex = 0;
		this.$routeMode = "LONG_RANGE_CHART_SHORTEST";
		this.$lastOptionChosen = "06_EXIT";

		// start on the summary page if more than one contract is available
		var summary = (this.$passengers.length > 1);

		this._passengerContractsDisplay(summary);
}


// this function is called after the player makes a choice which keeps
// them in the system, and also on initial entry to the system
// to select the appropriate mission screen and display it
this._passengerContractsDisplay = function(summary) {

		// Again. Has to be done on every call to this function, but also
		// has to be done at the start.
		this._validatePassengers(); 

		// if there are no passengers (usually because the player has taken
		// the last one) display a message and quit.
		if (this.$passengers.length === 0)
		{
				var missionConfig = {titleKey: "oolite-contracts-passengers-none-available-title",
														 messageKey: "oolite-contracts-passengers-none-available-message",
														 allowInterrupt: true,
														 screenID: "oolite-contracts-passengers-none",
														 
														 exitScreen: "GUI_SCREEN_INTERFACES"};
				if (this.$passengerSummaryPageBackground != "") {
						missionConfig.background = this.$passengerSummaryPageBackground;
				}
				if (this.$passengerPageOverlay != "") {
						missionConfig.overlay = this.$passengerPageOverlay;
				}
				mission.runScreen(missionConfig);
				// no callback, just exits contracts system
				return;
		}

		// make sure that the 'currently selected contract' pointer
		// is in bounds
		if (this.$contractIndex >= this.$passengers.length)
		{
				this.$contractIndex = 0;
		}
		else if (this.$contractIndex < 0)
		{
				this.$contractIndex = this.$passengers.length - 1;
		}
		// sub functions display either summary or detail screens
		if (summary)
		{
				this._passengerContractSummaryPage();
		}
		else
		{
				this._passengerContractSinglePage();
		}

}


// display the mission screen for the summary page
this._passengerContractSummaryPage = function()
{
	var playerrep = worldScripts["oolite-contracts-helpers"]._playerSkill(player.passengerReputationPrecise);

	// column 'tab stops'
	var columns = [12,18,23,28];

	// column header line
	var headline = expandMissionText("oolite-contracts-passengers-column-name");
	// pad to correct length to give a table-like layout
	headline += this.$helper._paddingText(headline,columns[0]);
	headline += expandMissionText("oolite-contracts-passengers-column-destination");
	headline += this.$helper._paddingText(headline,columns[1]);
	headline += expandMissionText("oolite-contracts-passengers-column-within");
	headline += this.$helper._paddingText(headline,columns[2]);
	headline += expandMissionText("oolite-contracts-passengers-column-advance");
	headline += this.$helper._paddingText(headline,columns[3]);
	headline += expandMissionText("oolite-contracts-passengers-column-fee");
	// required because of way choices are displayed.
	headline = " "+headline;

	// setting options dynamically; one contract per line
	var options = new Object;
	var i;
	for (i=0; i<this.$passengers.length; i++)
	{
		// temp variable to simplify following code
		var passenger = this.$passengers[i];
		// write the passenger description, padded to line up with the headers
		var optionText = passenger.name;
		optionText += this.$helper._paddingText(optionText, columns[0]);
		optionText += System.infoForSystem(galaxyNumber, passenger.destination).name;
		optionText += this.$helper._paddingText(optionText, columns[1]);
		optionText += this.$helper._timeRemaining(passenger);
		optionText += this.$helper._paddingText(optionText, columns[2]);
		// right-align the fee so that the credits signs line up
		var priceText = formatCredits(passenger.advance,false,true);
		priceText = this.$helper._paddingText(priceText, 3)+priceText;
		optionText += priceText
		optionText += this.$helper._paddingText(optionText, columns[3]);
		// right-align the fee so that the credits signs line up
		priceText = formatCredits(passenger.payment,false,true);
		priceText = this.$helper._paddingText(priceText, 3)+priceText;
		optionText += priceText
		
		// need to pad the number in the key to maintain alphabetical order
		var istr = i;
		if (i < 10)
		{
			istr = "0"+i;
		}
		// needs to be aligned left to line up with the heading
		options["01_CONTRACT_"+istr] = { text: optionText, alignment: "LEFT" };

		// if there's no space for extra passengers or the player isn't good enough
		if (passenger.skill > playerrep || player.ship.passengerCapacity <= player.ship.passengerCount)
		{
			options["01_CONTRACT_"+istr].color = "darkGrayColor";
		}
		// if there doesn't appear to be sufficient time remaining
		else if (this.$helper._timeRemainingSeconds(passenger) < this.$helper._timeEstimateSeconds(passenger))
		{
			options["01_CONTRACT_"+istr].color = "orangeColor";
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
	// unless we don't have any space left
	if (player.ship.passengerCapacity <= player.ship.passengerCount)
	{
		initialChoice = "06_EXIT";
	}

	// next, an empty string gives an unselectable row
	options["02_SPACER"] = ""; 

	// numbered 06 to match the option of the same function in the other branch
	options["06_EXIT"] = expandMissionText("oolite-contracts-passengers-command-quit");
	
	// now need to add further spacing to fill the remaining rows, or
	// the options will end up at the bottom of the screen.
	var rowsToFill = 21;
	if (player.ship.hudHidden)
	{
		rowsToFill = 27;
	}

	for (i = 4 + this.$passengers.length; i < rowsToFill ; i++)
	{
		// each key needs to be unique at this stage.
		options["07_SPACER_"+i] = ""; 
	}

	var missionConfig = {titleKey: "oolite-contracts-passengers-title-summary",
						 message: headline,
						 allowInterrupt: true,
						 screenID: "oolite-contracts-passengers-summary",
						 exitScreen: "GUI_SCREEN_INTERFACES",
						 choices: options,
						 initialChoicesKey: initialChoice}; 
	if (this.$passengerSummaryPageBackground != "") {
		missionConfig.background = this.$passengerSummaryPageBackground;
	}
	if (this.$passengerPageOverlay != "") {
		missionConfig.overlay = this.$passengerPageOverlay;
	}

	// now run the mission screen
	mission.runScreen(missionConfig, this._processPassengerChoice, this);
	
}


// display the mission screen for the contract detail page
this._passengerContractSinglePage = function()
{
	var playerrep = worldScripts["oolite-contracts-helpers"]._playerSkill(player.passengerReputationPrecise);

	// temp variable to simplify code
	var passenger = this.$passengers[this.$contractIndex];

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
	player.ship.targetSystem = passenger.destination;

	// start with 18 blank lines, since we don't want to overlap the chart
	var message = new Array(18).join("\n");
	
	message += expandMissionText("oolite-contracts-passengers-long-description",{
		"oolite-contracts-passengers-longdesc-name": passenger.name,
		"oolite-contracts-passengers-longdesc-species": passenger.species,
		"oolite-contracts-passengers-longdesc-destination": this.$helper._systemName(passenger.destination),
		"oolite-contracts-passengers-longdesc-deadline": this.$helper._timeRemaining(passenger),
		"oolite-contracts-passengers-longdesc-time": this.$helper._timeEstimate(passenger),
		"oolite-contracts-passengers-longdesc-payment": formatCredits(passenger.payment,false,true),
		"oolite-contracts-passengers-longdesc-advance": formatCredits(passenger.advance,false,true)
	});

	// use a special background
	var backgroundSpecial = "LONG_RANGE_CHART";
	
	// the available options will vary quite a bit, so this rather
	// than a choicesKey in missiontext.plist
	var options = new Object;
	// this is the only option which is always available
	options["06_EXIT"] = expandMissionText("oolite-contracts-passengers-command-quit");
	
	// if the player has a spare cabin
	if (player.ship.passengerCapacity <= player.ship.passengerCount)
	{
		options["05_UNAVAILABLE"] = {
			text: expandMissionText("oolite-contracts-passengers-command-unavailable"),
			color: "darkGrayColor",
			unselectable: true
		};
	} 
	else if (playerrep >= passenger.skill)
	{
		options["05_ACCEPT"] = { 
			text: expandMissionText("oolite-contracts-passengers-command-accept") 
		};
		
		// if there's not much time left, change the option colour as a warning!
		if (this.$helper._timeRemainingSeconds(passenger) < this.$helper._timeEstimateSeconds(passenger))
		{
			options["05_ACCEPT"].color = "orangeColor";
		}
	}
	else
	{
		var utype = "both";
		if (player.passengerReputationPrecise*10 >= passenger.skill)
		{
			utype = "kills";
		}
		else if (Math.sqrt(player.score) >= passenger.skill)
		{
			utype = "rep";
		}
		options["05_UNAVAILABLE"] = {
			text: expandMissionText("oolite-contracts-passengers-command-unavailable-"+utype),
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
			options["01_MODE"] = expandMissionText("oolite-contracts-passengers-command-ana-quickest");
		}
		else
		{
			options["01_MODE"] = expandMissionText("oolite-contracts-passengers-command-ana-shortest");
		}
	}
	// if there's more than one, need options for forward, back, and listing
	if (this.$passengers.length > 1)
	{
		options["02_BACK"] = expandMissionText("oolite-contracts-passengers-command-back");
		options["03_NEXT"] = expandMissionText("oolite-contracts-passengers-command-next");
		options["04_LIST"] = expandMissionText("oolite-contracts-passengers-command-list");
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

	var title = expandMissionText("oolite-contracts-passengers-title-detail",{
		"oolite-contracts-passengers-title-detail-number": this.$contractIndex+1,
		"oolite-contracts-passengers-title-detail-total": this.$passengers.length
	});

	// finally, after all that setup, actually create the mission screen

	var missionConfig = {
		title: title,
		message: message,
		allowInterrupt: true,
		screenID: "oolite-contracts-passengers-details",
		exitScreen: "GUI_SCREEN_INTERFACES",
		backgroundSpecial: backgroundSpecial,
		choices: options,
		initialChoicesKey: this.$lastChoice
	};

	if (this.$passengerPageOverlay != "") {
		missionConfig.overlay = this.$passengerPageOverlay;
	}

	mission.runScreen(missionConfig,this._processPassengerChoice, this);

}


this._processPassengerChoice = function(choice)
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
				this._passengerContractsDisplay(false);
		}
		else if (choice === "01_MODE")
		{
				// advanced navigation array mode flip
				this.$routeMode = (this.$routeMode === "LONG_RANGE_CHART_SHORTEST")?"LONG_RANGE_CHART_QUICKEST":"LONG_RANGE_CHART_SHORTEST";
				this.$lastChoice = "01_MODE";
				this._passengerContractsDisplay(false);
		}
		else if (choice === "02_BACK")
		{
				// reduce contract index (passengerContractsDisplay manages wraparound)
				this.$contractIndex--;
				this.$lastChoice = "02_BACK";
				this._passengerContractsDisplay(false);
		}
		else if (choice === "03_NEXT")
		{
				// increase contract index (passengerContractsDisplay manages wraparound)
				this.$contractIndex++;
				this.$lastChoice = "03_NEXT";
				this._passengerContractsDisplay(false);
		}
		else if (choice === "04_LIST")
		{
				// display the summary page
				this._passengerContractsDisplay(true);
		}
		else if (choice === "05_ACCEPT")
		{
				this._acceptContract();
				// do not leave the setting as accept for the next contract!
				this.$lastChoice = "03_NEXT"; 
				this._passengerContractsDisplay(false);
		}
		// if we get this far without having called passengerContractsDisplay
		// that means either 'exit' or an unrecognised option was chosen
}


// move a passenger from the contracts list to the player's ship (if possible)
this._acceptContract = function()
{
		var passenger = this.$passengers[this.$contractIndex];

		// give the passenger to the player
		var result = player.ship.addPassenger(passenger.name,system.ID,passenger.destination,passenger.deadline,passenger.payment,passenger.advance);
		
		if (result)
		{
				// pay the advance
				player.credits += passenger.advance;

				// remove the passenger from the station list
				this.$passengers.splice(this.$contractIndex,1);

				// update the interface description
				this._updateMainStationInterfacesList();

				this.$helper._soundSuccess();
		}
		else
		{
				// else must have had another passenger board recently
				// (unlikely, but another OXP could have done it)
				this.$helper._soundFailure();
		}
}


// removes any expired contracts
this._validatePassengers = function() 
{
		var c = this.$passengers.length-1;
		var removed = false;
		// iterate downwards so we can safely remove as we go
		for (var i=c;i>=0;i--)
		{
				// if the time remaining is less than 1/3 of the estimated
				// delivery time, even in the best case it's probably not
				// going to get there.

				if (this.$helper._timeRemainingSeconds(this.$passengers[i]) < this.$helper._timeEstimateSeconds(this.$passengers[i]) / 3)
				{
						// remove it
						this.$passengers.splice(i,1);
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

// lower-cases the initial letter of the package contents
this._formatPackageName = function(name) {
		return name.charAt(0).toLowerCase() + name.slice(1);
}


