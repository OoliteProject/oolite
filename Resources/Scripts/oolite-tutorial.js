/*

oolite-tutorial.js

World script for tutorial.


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
/*global worldScripts, player, missionVariables */


"use strict";

this.name = "oolite-tutorial";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";

this.startUp = function()
{
	if (!missionVariables.oolite_tutorial)
	{
		return;
	}
	log(this.name,"Tutorial mode active");
	// define rest of script now, otherwise it's pointless as it never
	// gets used in normal play

	this.$tutorialStage = 0;
	this.$tutorialSubstage = 0;

	/* Number of substages in each stage */
	this.$tutorialStages = [
		2, // stage 0: mission screen, post-launch cleanup
		10, // stage 1: HUD displays
		1 // stage 2: ...
	]

	// alternative populator
	this.ooliteTutorialWillPopulate = function()
	{
		var addTutorialStation = function(pos)
		{
			system.addShips("oolite-tutorial-station",1,pos,0);
		}

		system.setPopulator("oolite-tutorial-station",
						{
							priority: 5,
							location: "OUTER_SYSTEM_OFFPLANE",
							locationSeed: 600,
							callback: addTutorialStation,
							deterministic: true
						});
	}

	this.ooliteTutorialWillRepopulate = function()
	{
		// nothing yet
	}


	this.missionScreenOpportunity = function()
	{
		if (this.$tutorialStage == 0 && this.$tutorialSubstage == 0)
		{
			player.ship.hudHidden = true;
			mission.runScreen(
				{
					titleKey: "oolite-tutorial-0-0-title",
					messageKey: "oolite-tutorial-0-0-message",
					choicesKey: "oolite-tutorial-0-0-choices",
					screenID: "oolite-tutorial-0-0"
				},function()
				{
					player.ship.launch();
					this._nextItem();
				});
		}
	}


	this.shipLaunchedFromStation = function(station)
	{
		if (this.$tutorialStage == 0 && this.$tutorialSubstage == 1)
		{	
			station.remove();
			this._nextItem();
		}
	}

	// move to the next item in the current tutorial
	this._nextItem = function()
	{
		this.$tutorialSubstage++;
		if (this.$tutorialSubstage >= this.$tutorialStages[this.$tutorialStage])
		{
			this._nextSection();
		}
		else
		{
			var fn = "__stage"+this.$tutorialStage+"sub"+this.$tutorialSubstage;
			if (this[fn])
			{
				this[fn]();
			}
		}
	}


	// move to the next section of the tutorial
	this._nextSection = function()
	{
		this.$tutorialStage++;
		this.$tutorialSubstage = 0;
		var fn = "__stage"+this.$tutorialStage+"sub"+this.$tutorialSubstage;
		if (this[fn])
		{
			this[fn]();
		}
	}


	this._setInstructions = function(key) 
	{
		if (player.ship.multiFunctionDisplays == 0)
		{
			log(this.name,"Installed HUD does not support multi-function displays - unable to show instructions");
		}
		else
		{
			player.ship.setMultiFunctionText("oolite-tutorial",expandMissionText(key),true);
			player.ship.setMultiFunctionDisplay(0,"oolite-tutorial");
		}
	}


	this.$HUDSelectors = ["drawEnergyGauge:","drawForwardShieldBar:","drawAftShieldBar:","drawSpeedBar:","drawRollBar:","drawPitchBar:","drawYellowSurround:","drawFuelBar:","drawCabinTempBar:","drawWeaponTempBar:","drawAltitudeBar:","drawMissileDisplay:","drawStatusLight:","drawClock:","drawCompass:","drawScanner:","drawScannerZoomIndicator:"];
	this.$HUDHighlighter = null;
	this.$HUDHighlighterSelector = null;	
	this.$HUDHighlighterCycles = 10;

	this._showHUDItem = function(selector)
	{
		player.ship.showHUDSelector(selector);
		if (this.$HUDHighlighterSelector)
		{
			player.ship.showHUDSelector(this.$HUDHighlighterSelector);
		}
		this.$HUDHighlighterSelector = selector;
		if (this.$HUDHighlighter)
		{
			this.$HUDHighlighter.stop();
		}
		this.$HUDHighlighterCycles = 10;
		this.$HUDHighlighter = new Timer
		(this,
		 function()
		 {
			 if (this.$HUDHighlighterCycles == 0)
			 {
				 this.$HUDHighlighter.stop();
			 }
			 else if (this.$HUDHighlighterCycles % 2 == 0)
			 {
				 player.ship.hideHUDSelector(this.$HUDHighlighterSelector);
			 }
			 else
			 {
				 player.ship.showHUDSelector(this.$HUDHighlighterSelector);
			 }
			 --this.$HUDHighlighterCycles;
		 },0.5,0.5);
	}

	this._resetHUDItems = function()
	{
		for (var i=0; i<this.$HUDSelectors.length; i++)
		{
			player.ship.showHUDSelector(this.$HUDSelectors[i]);
		}
	}

	this._hideHUDItems = function()
	{
		for (var i=0; i<this.$HUDSelectors.length; i++)
		{
			player.ship.hideHUDSelector(this.$HUDSelectors[i]);
		}
	}

	/* Tutorial stages */

	// __stage0sub1 not needed
	
	this.__stage1sub0 = function()
	{
		this._setInstructions("oolite-tutorial-1-0");
		this._hideHUDItems();
		player.ship.hudHidden = false;
	}

	this.__stage1sub1 = function()
	{
		this._setInstructions("oolite-tutorial-1-1");
		this._showHUDItem("drawEnergyGauge:");
	}

	this.__stage1sub2 = function()
	{
		this._setInstructions("oolite-tutorial-1-2");
	}

	this.__stage1sub3 = function()
	{
		this._setInstructions("oolite-tutorial-1-3");
		player.ship.energy = 1;
	}
	
	this.__stage1sub4 = function()
	{
		this._setInstructions("oolite-tutorial-1-4");
		this._showHUDItem("drawForwardShieldBar:");
	}

	this.__stage1sub5 = function()
	{
		this._setInstructions("oolite-tutorial-1-5");
		this._showHUDItem("drawAftShieldBar:");
	}

	this.__stage1sub6 = function()
	{
		this._setInstructions("oolite-tutorial-1-6");
		player.ship.energy = 256;
		player.ship.forwardShield = 0;
		player.ship.aftShield = 0;
	}
	

	this.__stage2sub0 = function()
	{
		this._resetHUDItems();
	}

}