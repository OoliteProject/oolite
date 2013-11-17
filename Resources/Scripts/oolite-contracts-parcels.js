/*

oolite-contracts-parcels.js

Script for managing parcel contracts
 

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


this.name			= "oolite-contracts-parcels";
this.author			= "cim";
this.copyright		= "© 2012-2013 the Oolite team.";
this.description	= "Parcel delivery contracts.";
this.version		= "1.79";

/**** Configuration options and API ****/

/* OXPs which wish to add a background to the summary pages should
   set this value */
this.$parcelSummaryPageBackground = "";
/* OXPs which wish to add an overlay to the parcel mission screens
   should set this value */
this.$parcelPageOverlay = "";


/* this._addParcelToSystem(parcel)
 * This function adds the defined parcel to the local main station's
 * interface list. A parcel definition is an object with the following
 * parameters, all required:
 * 
 * destination: system ID of destination system
 * sender:      the name of the sender (max 40 chars)
 * description: a short description of the parcel contents (max 40 chars)
 * deadline:    the deadline for delivery, in clock seconds
 * payment:     the payment for delivery on time, in credits
 * 
 * and optionally, the following parameters:
 *
 * skill:       the skill level required by the client (default 0)
 * risk:        the risk involved in carrying it (0-2, default 0)
 * route:       a route object generated with system.info.routeToSystem
 *              describing the route between the source and destination 
 *              systems. (default: generated from destination)
 * 
 * The function will return true if the parcel can be added, false
 * otherwise.
 */
this._addParcelToSystem = function(parcel)
{
	if (!system.mainStation)
	{
		log(this.name,"Contracts require a main station");
		return false;
	}
	if (!parcel.sender || parcel.sender.length > 40)
	{
		log(this.name,"Rejected parcel: sender missing or too long");
		return false;
	}
	if (!parcel.description || parcel.description.length > 40)
	{
		log(this.name,"Rejected parcel: description missing or too long");
		return false;
	}
	if (parcel.destination < 0 || parcel.destination > 255)
	{
		log(this.name,"Rejected parcel: destination missing or invalid");
		return false;
	}
	if (parcel.deadline <= clock.adjustedSeconds)
	{
		log(this.name,"Rejected parcel: deadline invalid");
		return false;
	}
	if (parcel.payment < 0)
	{
		log(this.name,"Rejected parcel: payment invalid");
		return false;
	}
	if (!parcel.route)
	{
		var destinationInfo = System.infoForSystem(galaxyNumber,parcel.destination);
		parcel.route = system.info.routeToSystem(destinationInfo);
		if (!parcel.route)
		{
			log(this.name,"Rejected parcel: route invalid");
			return false;
		}
	}
	if (!parcel.risk)
	{
		parcel.risk = 0;
	}
	if (!parcel.skill)
	{
		parcel.skill = 0;
	}
	else if (parcel.skill > 70)
	{
		parcel.skill = 70;
	}

	this.$parcels.push(parcel);
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
	if (missionVariables.oolite_contracts_parcels)
	{
		this.$parcels = JSON.parse(missionVariables.oolite_contracts_parcels);
		if (this.$parcels[0] && this.$parcels[0].risk === undefined)
		{
			for (var i = 0 ; i < this.$parcels.length ; i++)
			{
				if (this.$parcels[i].risk === undefined)
				{
					this.$parcels[i].risk = 0;
					// ensure that parcel contracts which could be
					// accepted before upgrade can still be accepted
					this.$parcels[i].skill = -50; 
				}
			}
		}
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

// initialise a new parcel contract list for the current system
this._initialiseParcelContractsForSystem = function() 
{
	// clear list
	this.$parcels = [];
	
	// basic range -3 to +9 evenly distributed
	// parcel contracts require less investment than cargo or passenger
	// so fewer are available, though the risk is still there
	var numContracts = Math.floor(Math.random()*13) - 3;
	
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
	if (player.parcelReputationPrecise < 0)
	{
		numContracts += player.parcelReputationPrecise;
	}
	// if they have a very good reputation, increase the numbers
	else if (player.parcelReputationPrecise > 4)
	{
		numContracts += Math.floor(Math.random()*(player.parcelReputationPrecise - 3));
	}
	// always have at least four available for new Jamesons
	if (!missionVariables.oolite_contracts_parcels && numContracts < 4)
	{
		numContracts = 4;
	} 
	// reduce number of places with none whatsoever
	else if (numContracts < 1 && player.parcelReputationPrecise >= 0 && Math.random() < 0.5)
	{
		numContracts = 1;
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
		
		// time allowed for delivery is time taken by "fewest jumps"
		// route, plus 10-110%, plus four hours to make sure all routes
		// are "in time" for a reasonable-length journey in-system.
		var dtime = Math.floor((routeToDestination.time * 3600 * (1.1+(Math.random())))) + 14400;
		parcel.deadline = clock.adjustedSeconds + dtime;

		var newCommander = false;
		if (i < 2 && !missionVariables.oolite_contracts_parcels)
		{
			newCommander = true;
			parcel.risk = 0;
			parcel.description = expandDescription("[parcel-description-safe]");
		}
		else
		{
			parcel.risk = Math.floor(Math.random()*3);
			if (parcel.risk < 2 && destinationInfo.government <= 1 && Math.random() < 0.5)
			{
				parcel.risk++;
			}
			parcel.description = expandDescription("[parcel-description-risk"+parcel.risk+"]");
		}

		// total payment is small for these items.
		parcel.payment = Math.floor(
			// 2-3 credits per LY of route
			(routeToDestination.distance * (2+Math.random())) +
				// additional income for route length based on reputation
				(Math.pow(routeToDestination.route.length,1+(parcel.risk*0.4)+(0.2*player.parcelReputationPrecise))) +
				// small premium for delivery to more dangerous systems
				(2 * Math.pow(7-destinationInfo.government,1.5))
		);
		
		parcel.payment *= (Math.random()+Math.random()+Math.random()+Math.random())/2;
	
		if (!newCommander)
		{
			var prudence = (2*Math.random())-1;

			var desperation = (Math.random()*(0.5+parcel.risk)) * (1+1/(Math.max(0.5,dtime-(routeToDestination.time * 3600))));
			var competency = Math.max(50,(routeToDestination.route.length-1)*(1+(parcel.risk*2)));
			if(parcel.risk == 0)
			{
				competency -= 10;
			}
			parcel.payment = Math.floor(parcel.payment * (1+(0.4*prudence)));
			parcel.payment += (parcel.risk * 200);
			parcel.skill = competency + 20*(prudence-desperation);
		}
		else
		{
			parcel.skill = -1; // always available
		}

		// add parcel to contract list
		this._addParcelToSystem(parcel);
	}
	
}


// this should be called every time the contents of this.$parcels
// changes, as it updates the summary of the interface entry.
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
				var missionConfig = {titleKey: "oolite-contracts-parcels-none-available-title",
													 messageKey: "oolite-contracts-parcels-none-available-message",
													 allowInterrupt: true,
													 screenID: "oolite-contracts-parcels-none",
													 exitScreen: "GUI_SCREEN_INTERFACES"};
				if (this.$parcelSummaryPageBackground != "") {
						missionConfig.background = this.$parcelSummaryPageBackground;
				}
				if (this.$parcelPageOverlay != "") {
						missionConfig.overlay = this.$parcelPageOverlay;
				}
				mission.runScreen(missionConfig);

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
	var playerrep = worldScripts["oolite-contracts-helpers"]._playerSkill(player.parcelReputationPrecise);
	// column 'tab stops'
	var columns = [14,21,28];

	// column header line
	var headline = expandMissionText("oolite-contracts-parcels-column-cargo");
	// pad to correct length to give a table-like layout
	headline += this.$helper._paddingText(headline,columns[0]);
	headline += expandMissionText("oolite-contracts-parcels-column-destination");
	headline += this.$helper._paddingText(headline,columns[1]);
	headline += expandMissionText("oolite-contracts-parcels-column-within");
	headline += this.$helper._paddingText(headline,columns[2]);
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
		optionText += this.$helper._paddingText(optionText, columns[0]);
		optionText += System.infoForSystem(galaxyNumber, parcel.destination).name;
		optionText += this.$helper._paddingText(optionText, columns[1]);
		optionText += this.$helper._timeRemaining(parcel);
		optionText += this.$helper._paddingText(optionText, columns[2]);
		// right-align the fee so that the credits signs line up
		var priceText = formatCredits(parcel.payment,false,true);
		priceText = this.$helper._paddingText(priceText, 2.5)+priceText;
		optionText += priceText
		
		// maximum of seven contracts available, so no need to pad the number
		// in the key to maintain alphabetical order
		// needs to be aligned left to line up with the heading
		options["01_CONTRACT_"+i] = { text: optionText, alignment: "LEFT" };
		
		// if the player isn't good enough
		if (parcel.skill > playerrep)
		{
			options["01_CONTRACT_"+i].color = "darkGrayColor";
		}
		// if there doesn't appear to be sufficient time remaining
		else if (this.$helper._timeRemainingSeconds(parcel) < this.$helper._timeEstimateSeconds(parcel))
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
						 allowInterrupt: true,
						 screenID: "oolite-contracts-parcels-summary",
						 exitScreen: "GUI_SCREEN_INTERFACES",
						 choices: options,
						 initialChoicesKey: initialChoice}; 
	if (this.$parcelSummaryPageBackground != "") {
		missionConfig.background = this.$parcelSummaryPageBackground;
	}
	if (this.$parcelPageOverlay != "") {
		missionConfig.overlay = this.$parcelPageOverlay;
	}

	// now run the mission screen
	mission.runScreen(missionConfig, this._processParcelChoice, this);
	
}


// display the mission screen for the contract detail page
this._parcelContractSinglePage = function()
{
	var playerrep = worldScripts["oolite-contracts-helpers"]._playerSkill(player.parcelReputationPrecise);

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
		"oolite-contracts-parcels-longdesc-destination": this.$helper._systemName(parcel.destination),
		"oolite-contracts-parcels-longdesc-deadline": this.$helper._timeRemaining(parcel),
		"oolite-contracts-parcels-longdesc-time": this.$helper._timeEstimate(parcel),
		"oolite-contracts-parcels-longdesc-payment": formatCredits(parcel.payment,false,true)
	});

	// use a special background
	var backgroundSpecial = "LONG_RANGE_CHART";
	
	// the available options will vary quite a bit, so this rather
	// than a choicesKey in missiontext.plist
	var options = new Object;
	// these are the only options which are always available
	if (parcel.skill <= playerrep)
	{
		options["05_ACCEPT"] = { 
			text: expandMissionText("oolite-contracts-parcels-command-accept") 
		};

		// if there's not much time left, change the option colour as a warning!
		if (this.$helper._timeRemainingSeconds(parcel) < this.$helper._timeEstimateSeconds(parcel))
		{
			options["05_ACCEPT"].color = "orangeColor";
		}
	} else {
		var utype = "both";
		if (player.parcelReputationPrecise*10 >= parcel.skill)
		{
			utype = "kills";
		}
		else if (Math.sqrt(player.score) >= parcel.skill)
		{
			utype = "rep";
		}
		options["05_UNAVAILABLE"] = {
			color: "darkGrayColor",
			unselectable: true,
			text: expandMissionText("oolite-contracts-parcels-command-unavailable-"+utype)
		}
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

	var missionConfig = {
		title: title,
		message: message,
		allowInterrupt: true,
		screenID: "oolite-contracts-parcels-details",
		exitScreen: "GUI_SCREEN_INTERFACES",
		backgroundSpecial: backgroundSpecial,
		choices: options,
		initialChoicesKey: this.$lastChoice
	};

	if (this.$parcelPageOverlay != "") {
		missionConfig.overlay = this.$parcelPageOverlay;
	}

	mission.runScreen(missionConfig,this._processParcelChoice, this);

}


this._processParcelChoice = function(choice)
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
	var desc = expandDescription("[parcel-label]",{
		"oolite-parcel-owner" : parcel.sender,
		"oolite-parcel-contents" : this._formatPackageName(parcel.description)
	});
	player.ship.addParcel(desc,system.ID,parcel.destination,parcel.deadline,parcel.payment,0,parcel.risk);
	
	// remove the parcel from the station list
	this.$parcels.splice(this.$contractIndex,1);

	// update the interface description
	this._updateMainStationInterfacesList();

	this.$helper._soundSuccess();
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

				if (this.$helper._timeRemainingSeconds(this.$parcels[i]) < this.$helper._timeEstimateSeconds(this.$parcels[i]) / 3)
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

// lower-cases the initial letter of the package contents
this._formatPackageName = function(name) {
		return name.charAt(0).toLowerCase() + name.slice(1);
}
