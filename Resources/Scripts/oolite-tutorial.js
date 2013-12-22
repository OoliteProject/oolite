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

	this.$tutorialSound = new SoundSource;	
	this.$tutorialSpeech = new SoundSource;

	this.$fcb = null;

	this.$tutorialStage = 0;
	this.$tutorialSubstage = 0;
	this.$advanceByEquipment = true;

	/* Number of substages in each stage */
	this.$tutorialStages = [
		3, // stage 0: mission screen, post-launch cleanup, intro message
		25, // stage 1: HUD displays
		12, // stage 2: scanner and views
		6, // stage 3: basic flight challenge
		8, // stage 4: targeting + lasers
		12, // stage 5: missiles + avoidance
		11, // stage 6: combat
		15, // stage 7: docking
		25, // stage 8: status screens
		15 // stage 9: system navigation
	];

	this.$shipList = [];

	missionVariables.oolite_tutorial_deaths = 0;
	missionVariables.oolite_tutorial_asteroids = 0;
	missionVariables.oolite_tutorial_asteroids_win = 0;
	missionVariables.oolite_tutorial_asteroids_result = expandMissionText("oolite-tutorial-end-notry");
	missionVariables.oolite_tutorial_combat_stage = 0;		
	missionVariables.oolite_tutorial_combat_duration = 0;
	missionVariables.oolite_tutorial_combat_result = expandMissionText("oolite-tutorial-end-notry");

	// alternative populator
	this.ooliteTutorialWillPopulate = function()
	{

		system.setPopulator("oolite-nav-buoy",
						{
							priority: 5,
							location: "COORDINATES",
							coordinates: system.mainStation.position.add(system.mainStation.vectorForward.multiply(10E3)),
							callback: function(pos) {
								var nb = system.addShips("buoy",1,pos,0)[0];
								nb.scanClass = "CLASS_BUOY";
								nb.reactToAIMessage("START_TUMBLING");
							},
							deterministic: true
						});

		system.setPopulator("oolite-witch-buoy",
						{
							priority: 10,
							location: "COORDINATES",
							coordinates: [0,0,0],
							callback: function(pos) {
								var wb = system.addShips("buoy-witchpoint",1,pos,0)[0];
								wb.scanClass = "CLASS_BUOY";
								wb.reactToAIMessage("START_TUMBLING");
							},
							deterministic: true
						});

		var addTutorialStation = function(pos)
		{
			system.addShips("oolite-tutorial-station",1,pos,0);
		}

		system.setPopulator("oolite-tutorial-station",
						{
							priority: 5,
/*							location: "OUTER_SYSTEM_OFFPLANE",
							locationSeed: 600, */
							location: "COORDINATES",
							coordinates: new Vector3D(-1294672.125,-7577498,3605521.5),
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
			player.ship.targetSystem = 55;
			player.ship.hudHidden = true;
			player.ship.hideHUDSelector("drawPrimedEquipment:");
			mission.runScreen(
				{
					titleKey: "oolite-tutorial-0-0-title",
					messageKey: "oolite-tutorial-0-0-message",
					choicesKey: "oolite-tutorial-0-0-choices",
					screenID: "oolite-tutorial-0-0"
				},function()
				{
					player.ship.hudHidden = false;
					player.ship.launch();
					this._nextItem();
				});
		}
		else if (this.$tutorialStage == 7 && this.$tutorialSubstage <= 13)
		{
			this._setFrameCallback("");
			mission.runScreen(
				{
					titleKey: "oolite-tutorial-7-13-title",
					messageKey: "oolite-tutorial-7-13-message",
					choicesKey: "oolite-tutorial-7-13-choices",
					screenID: "oolite-tutorial-7-13"
				},function(choice)
				{
					this.$advanceByEquipment = true;
					player.ship.launch();
					// in case the player docked early
					this.$tutorialSubstage = 13;
					if (choice != "01_AGAIN")
					{
						this._nextItem();
					}
				});
		}
		else if (this.$tutorialStage >= 9)
		{
			this._endTutorial();
		}
	}

	this.shipWillDockWithStation = function(station)
	{
		this._setFrameCallback("");
		player.ship.setMultiFunctionText("oolite-tutorial",null);
		this._resetShips(station);
	}


	this.shipLaunchedFromStation = function(station)
	{
		if (this.$tutorialStage == 0 && this.$tutorialSubstage == 1)
		{	
			station.position = station.position.add([0,0,1E7]);
			station.remove(true);
			this._nextItem();
		}
		else if (this.$tutorialStage == 7)
		{
			station.position = station.position.add([0,0,1E7]);
			station.remove(true);
			if (this.$tutorialSubstage != 14)
			{
				this._restartSection();
			}
			else
			{
				this._nextSection();
			}
		}
	}

	
	this.shipTakingDamage = function(amount, whom, type)
	{
		if (amount >= player.ship.energy)
		{
			player.ship.position = system.locationFromCode("OUTER_SYSTEM_OFFPLANE");
			player.ship.dealEnergyDamage(1,10000,0);
			this._playSound("bigbang.ogg");
			player.consoleMessage(expandMissionText("oolite-tutorial-no-death"));
			missionVariables.oolite_tutorial_deaths++;
			this._restartSection(); // will reset energy
		}
	}


	this.shipEnteredPlanetaryVicinity = function(planet)
	{
		if (this.$tutorialStage < 9)
		{
			// you shouldn't be here
			player.ship.position = system.locationFromCode("OUTER_SYSTEM_OFFPLANE");
			this._restartSection();
		}
		else
		{
			if (planet == system.mainPlanet && this.$tutorialSubstage <= 7)
			{
				this.$tutorialSubstage = 7;
				this._nextItem();
			}
			else if (planet == system.sun)
			{
				player.consoleMessage("oolite-tutorial-9-7-sun");
			}
		}
	}

	this.shipEnteredStationAegis = function(station)
	{
		if (this.$tutorialStage < 9)
		{
			// you shouldn't be here
			player.ship.position = system.locationFromCode("OUTER_SYSTEM_OFFPLANE");
			this._restartSection();
		}
		else
		{
			if (this.$tutorialSubstage <= 9)
			{
				this.$tutorialSubstage = 9;
				this._nextItem();
			}
		}
	}


	this.playerStartedJumpCountdown = function()
	{
		player.ship.cancelHyperspaceCountdown();
		player.consoleMessage(expandMissionText("oolite-tutorial-no-witchspace"));
	}



	this.$blockTorus = true;
	this.$blockTorusObj = null;
	this.$blockTorusFCB = addFrameCallback(function(delta)
	{
		if ($blockTorus)
		{
			// doesn't help with injectors, but the player doesn't
			// have those here
			if (player.ship.speed > player.ship.maxSpeed)
			{
				if (!this.$blockTorusObj || !this.$blockTorusObj.isInSpace)
				{
					this.$blockTorusObj = system.addShips("[adder]",1,player.ship.position.add(player.ship.vectorUp.multiply(10000)),0)[0];
					this.$blockTorusObj.scannerDisplayColor1 = [0,0,0,0];
					this.$blockTorusObj.scannerDisplayColor2 = [0,0,0,0];
					this.$blockTorusObj.setAI("nullAI.plist");
					player.consoleMessage(expandMissionText("oolite-tutorial-no-torus"));
				}
			}
			else if (this.$blockTorusObj)
			{
				this.$blockTorusObj.remove(true);
				this.$blockTorusObj = null;
			}
		}
	}.bind(this));


	this._playSound = function(snd)
	{
		this.$tutorialSound.stop();
		this.$tutorialSound.sound = snd;
		this.$tutorialSound.play();
	}

	this._nextItemEquip = function()
	{
		if (this.$advanceByEquipment)
		{
			this._nextItem();
		}
		else
		{
			player.consoleMessage(expandMissionText("oolite-tutorial-no-advance"));
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


	// restart this section of the tutorial
	this._restartSection = function()
	{
		this.$tutorialStage--;
		this._nextSection();
	}

	// move to the next section of the tutorial
	this._nextSection = function()
	{
		this._resetPlayerShip();
		this.$tutorialStage++;
		this.$tutorialSubstage = 0;
		var fn = "__stage"+this.$tutorialStage+"sub"+this.$tutorialSubstage;
		if (this[fn])
		{
			this[fn]();
		}
		else
		{
			this._endTutorial();
		}
	}


	this._setFrameCallback = function(fn)
	{
		if (this.$fcb)
		{
			removeFrameCallback(this.$fcb);
			this.$fcb = null;
		}
		if (fn)
		{
			this.$fcb = addFrameCallback(fn.bind(this));
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
			this.$tutorialSpeech.stop();
			this.$tutorialSpeech.sound = key+".ogg";
			this.$tutorialSpeech.play();
		}
	}

	this._scoreTry = function(key)
	{
		missionVariables["oolite_tutorial_"+key] = expandMissionText("oolite-tutorial-end-try");
	}

	this._scoreWin = function(key)
	{
		missionVariables["oolite_tutorial_"+key] = expandMissionText("oolite-tutorial-end-win");
	}

	this._scoreBonus = function(key)
	{
		missionVariables["oolite_tutorial_"+key] = expandMissionText("oolite-tutorial-end-bonus");
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
		if (selector == "")
		{
			return;
		}
		this.$HUDHighlighterCycles = 6;
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
		this._showHUDItem("");
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


	this._resetPlayerShip = function()
	{
		this.$advanceByEquipment = true;
		player.ship.fuel = 2.0;
		player.ship.energy = 256;		
		player.ship.forwardShield = 128;
		player.ship.aftShield = 128;
		player.ship.forwardWeapon = "EQ_WEAPON_PULSE_LASER";
		for (var i=0;i<4;i++)
		{
			player.ship.removeEquipment("EQ_MISSILE");
		}
		for (i=0;i<3;i++)
		{
			player.ship.awardEquipment("EQ_MISSILE");
		}
		this._resetHUDItems();
		this._resetShips();
		this._setFrameCallback(null);
		player.ship.hideHUDSelector("drawPrimedEquipment:");
		player.ship.hudHidden = false;
		var fc = addFrameCallback(function(delta)
								  {
									  player.ship.velocity = player.ship.thrustVector;
									  removeFrameCallback(fc);
								  });

	}

	// exception parameter used to avoid removing the station the
	// player is docked with
	this._resetShips = function(exception)
	{
		for (var i=this.$shipList.length-1;i>=0;i--)
		{
			if (this.$shipList[i] && this.$shipList[i].isShip)
			{
				if (!exception || exception != this.$shipList[i])
				{
					this.$shipList[i].remove(true);
				}
			}
		}
	}

	// just in case a role has been defined out by OXP
	this.$roleFallbacks = {
		"asteroid" : "[asteroid]",
		"boulder" : "[boulder]",
		"splinter" : "[splinter]",
		"police" : "[viper]",
		"missile" : "[missile]",
		"energy-bomb" : "[qbomb]"
	};

	this._addShips = function(role,num,pos,rad)
	{
		var arr = system.addGroup(role,num,pos,rad);
		if (!arr || arr.ships.length == 0)
		{
			role = this.$roleFallbacks[role];
			if (role)
			{
				arr = system.addGroup(role,num,pos,rad);
			}
		}
		if (!arr || arr.ships.length == 0)
		{
			return [];
		}
		this.$shipList = this.$shipList.concat(arr.ships);
		return arr.ships;
	}

	/* Tutorial stages */

	// __stage0sub1 not needed

	this.__stage0sub2 = function()
	{
		this._setInstructions("oolite-tutorial-0-2");
	}
	
	this.__stage1sub0 = function()
	{
		this._setInstructions("oolite-tutorial-1-0");
	}

	this.__stage1sub1 = function()
	{
		this._hideHUDItems();
		this._setInstructions("oolite-tutorial-1-1");
		this._showHUDItem("drawEnergyGauge:");
	}

	this.__stage1sub2 = function()
	{
		this._setInstructions("oolite-tutorial-1-2");
		this._showHUDItem("");
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
		this._showHUDItem("");
		player.ship.energy = 256;
		player.ship.forwardShield = 0;
		player.ship.aftShield = 0;
	}
	
	this.__stage1sub7 = function()
	{
		player.ship.fuel = 5;
		this._setInstructions("oolite-tutorial-1-7");
		this._showHUDItem("drawYellowSurround:");
		this._showHUDItem("drawFuelBar:");
	}

	this.__stage1sub8 = function()
	{
		this._setInstructions("oolite-tutorial-1-8");
		this._showHUDItem("");
		player.ship.fuelLeakRate = 5;
	}

	this.__stage1sub9 = function()
	{
		this._setInstructions("oolite-tutorial-1-9");
		this._showHUDItem("drawCabinTempBar:");
	}

	this.__stage1sub10 = function()
	{
		this._setInstructions("oolite-tutorial-1-10");
		this._showHUDItem("");
		player.ship.temperature = 0.999;
	}

	this.__stage1sub11 = function()
	{
		this._setInstructions("oolite-tutorial-1-11");
		this._showHUDItem("drawWeaponTempBar:");
	}

	this.__stage1sub12 = function()
	{
		this._setInstructions("oolite-tutorial-1-12");
		this._showHUDItem("");
	}

	this.__stage1sub13 = function()
	{
		this._setInstructions("oolite-tutorial-1-13");
		this._showHUDItem("drawAltitudeBar:");
	}

	this.__stage1sub14 = function()
	{
		this._setInstructions("oolite-tutorial-1-14");
		this._showHUDItem("drawSpeedBar:");
	}

	this.__stage1sub15 = function()
	{
		this._setInstructions("oolite-tutorial-1-15");
		this._showHUDItem("drawRollBar:");
	}

	this.__stage1sub16 = function()
	{
		this._setInstructions("oolite-tutorial-1-16");
		this._showHUDItem("drawPitchBar:");
	}

	this.__stage1sub17 = function()
	{
		this._setInstructions("oolite-tutorial-1-17");
		this._showHUDItem("drawMissileDisplay:");
	}
	
	this.__stage1sub18 = function()
	{
		this._setInstructions("oolite-tutorial-1-18");
		this._showHUDItem("drawScannerZoomIndicator:");
		this._showHUDItem("drawScanner:");
	}

	this.__stage1sub19 = function()
	{
		this._setInstructions("oolite-tutorial-1-19");
		this._showHUDItem("drawCompass:");
	}

	this.__stage1sub20 = function()
	{
		this._setInstructions("oolite-tutorial-1-20");
		this._showHUDItem("drawStatusLight:");
	}

	this.__stage1sub21 = function()
	{
		this._setInstructions("oolite-tutorial-1-21");
		this._showHUDItem("");
	}

	this.__stage1sub22 = function()
	{
		this._setInstructions("oolite-tutorial-1-22");
		this._showHUDItem("drawClock:");
	}

	this.__stage1sub23 = function()
	{
		this._setInstructions("oolite-tutorial-1-23");
		this._showHUDItem("");
		clock.addSeconds(7200);
	}

	this.__stage1sub24 = function()
	{
		this._setInstructions("oolite-tutorial-1-24");
	}

	this.__stage2sub0 = function()
	{
		this._setInstructions("oolite-tutorial-2-0");
	}

	this.__stage2sub1 = function()
	{
		if (player.ship.speed > 0.1)
		{
			player.consoleMessage(expandMissionText("oolite-tutorial-2-1-error"));
			this._setInstructions("oolite-tutorial-2-0");
			--this.$tutorialSubstage;
		}
		else
		{
			this._setInstructions("oolite-tutorial-2-1");
			this._addShips("asteroid",10,player.ship.position,25E3);
		}
	}

	this.__stage2sub2 = function()
	{
		this._setInstructions("oolite-tutorial-2-2");
	}

	this.__stage2sub3 = function()
	{
		this._setInstructions("oolite-tutorial-2-3");
	}

	this.__stage2sub4 = function()
	{
		this._setInstructions("oolite-tutorial-2-4");
	}

	this.__stage2sub5 = function()
	{
		this._setInstructions("oolite-tutorial-2-5");
		this._showHUDItem("drawScannerZoomIndicator:");
	}

	this.__stage2sub6 = function()
	{
		this._setInstructions("oolite-tutorial-2-6");
	}

	this.__stage2sub7 = function()
	{
		this._setInstructions("oolite-tutorial-2-7");
	}

	this.__stage2sub8 = function()
	{
		this._setInstructions("oolite-tutorial-2-8");
		var yellow = this._addShips("[adder]",1,player.ship.position,5E3)[0];
		yellow.setAI("nullAI.plist");
		var red = this._addShips("[adder]",1,player.ship.position,5E3)[0];
		red.setAI("nullAI.plist");
		red.target = player.ship;
		red.thrust = 0;
		red.performFlee();
		var purple = this._addShips("police",1,player.ship.position,5E3)[0];
		purple.setAI("nullAI.plist");
	}


	this.__stage2sub9 = function()
	{
		this._setInstructions("oolite-tutorial-2-9");
		this._addShips("oolite-tutorial-buoy",1,player.ship.position,10E3);
		var miss = this._addShips("missile",1,player.ship.position,10E3)[0];
		miss.setAI("nullAI.plist");
		var mine = this._addShips("energy-bomb",1,player.ship.position,10E3)[0];
		mine.setAI("nullAI.plist");
	}

	this.__stage2sub10 = function()
	{
		this._setInstructions("oolite-tutorial-2-10");
	}

	this.__stage2sub11 = function()
	{
		this._setInstructions("oolite-tutorial-2-11");
	}

	this.__stage3sub0 = function()
	{
		// restart;
		var rocks = system.entitiesWithScanClass("CLASS_ROCK");
		for (var i=rocks.length-1;i>=0;--i)
		{
			rocks[i].remove();
		}
		rocks = system.entitiesWithScanClass("CLASS_CARGO");
		for (i=rocks.length-1;i>=0;--i)
		{
			rocks[i].remove();
		}
		player.ship.forwardWeapon = "EQ_WEAPON_NONE";
		for (i=0;i<3;i++) {
			player.ship.removeEquipment("EQ_MISSILE");
		}
		this._setInstructions("oolite-tutorial-3-0");
	}

	this.__stage3sub1 = function()
	{
		this._setInstructions("oolite-tutorial-3-1");
	}

	this.__stage3sub2 = function()
	{
		var centre = player.ship.position;
		centre.z += 15000;
		var buoy = this._addShips("oolite-tutorial-buoy",1,centre,0)[0];
		this._addShips("asteroid",50,centre,7500);
		this._setInstructions("oolite-tutorial-3-2");
		this._setFrameCallback(function()
		{
			if (player.ship.speed < 1 && centre.distanceTo(player.ship) <= 500)
			{
				this._nextItem();
			}
		});
	}

	this.__stage3sub3 = function()
	{
		var buoy = system.shipsWithPrimaryRole("oolite-tutorial-buoy")[0];
		if (!buoy)
		{
			buoy = this._addShips("oolite-tutorial-buoy",1,player.ship.position.add([0,0,500]),0)[0];
		}
		if (player.ship.speed > 1 || buoy.position.distanceTo(player.ship) > 500)
		{
			player.consoleMessage(expandMissionText("oolite-tutorial-3-3-error"));
			this._setInstructions("oolite-tutorial-3-2");
			--this.$tutorialSubstage;
			return;
		}

		this._setInstructions("oolite-tutorial-3-3");
		this.$advanceByEquipment = false;
		var time = 0;
		var nexttime = 5;
		var atonce = 1;
		buoy.script.shipTakingDamage = function(amount,whom,type)
		{
			buoy.energy = 100000;
			if (!whom.isPlayer)
			{
				whom.explode();
			}
		};
		this._setFrameCallback(function(delta)
		{
			time += delta;
			if (time > nexttime)
			{
				nexttime += 15;
				var asteroids = system.shipsWithPrimaryRole("asteroid",player.ship,10000);
				for (var i=0;i<atonce;++i)
				{
					var asteroid = asteroids[Math.floor(Math.random()*asteroids.length)];
					if (asteroid)
					{
						asteroid.velocity = player.ship.position.subtract(asteroid.position).direction().multiply(200+(20*atonce));
						// not on the hard difficulty
						if (missionVariables.oolite_tutorial_asteroids_win == 0)
						{
							asteroid.scannerDisplayColor1 = "whiteColor";
							asteroid.scannerDisplayColor2 = "redColor";
						}
					}
				}
				++atonce;
				if (buoy.position.distanceTo(player.ship) > 5000)
				{
					player.consoleMessage(expandMissionText("oolite-tutorial-3-3-toofar"),5);
					missionVariables.oolite_tutorial_asteroids = Math.floor(time);
					this._nextItem();
				}
			}
			else if (Math.random() < delta)
			{
				var boulders = system.shipsWithPrimaryRole("boulder",player.ship,10000);
				if (boulders.length > 1)
				{
					boulders[0].explode();
					if (boulders.length > 5)
					{
						boulders[2].explode();
						boulders[1].explode();
					}
				}
				var splinters = system.shipsWithPrimaryRole("splinter",player.ship,10000);
				if (splinters.length > 1)
				{
					splinters[0].explode();
					if (splinters.length > 5)
					{
						splinters[2].explode();
						splinters[1].explode();
					}
				}
				if (buoy.position.distanceTo(player.ship) > 5000)
				{
					player.consoleMessage(expandMissionText("oolite-tutorial-3-3-toofar"),5);
					missionVariables.oolite_tutorial_asteroids = Math.floor(time);
					this._nextItem();
				}
			}

			if (time > 150)
			{
				player.consoleMessage(expandMissionText("oolite-tutorial-3-3-win"),5);
				missionVariables.oolite_tutorial_asteroids = Math.floor(time);
				this._nextItem();
			}
		});
	}

	this.__stage3sub4 = function()
	{
		this._setFrameCallback(function(delta)
	    {
			if (Math.random() < delta)
			{
				var boulders = system.shipsWithPrimaryRole("boulder",player.ship,10000);
				if (boulders.length > 1)
				{
					boulders[0].explode();
					if (boulders.length > 5)
					{
						boulders[2].explode();
						boulders[1].explode();
					}
				}
				var splinters = system.shipsWithPrimaryRole("splinter",player.ship,10000);
				if (splinters.length > 1)
				{
					splinters[0].explode();
					if (splinters.length > 5)
					{
						splinters[2].explode();
						splinters[1].explode();
					}
				}
			}
		});
		if (missionVariables.oolite_tutorial_asteroids >= 150)
		{
			if (missionVariables.oolite_tutorial_asteroids_win >= 1)
			{
				missionVariables.oolite_tutorial_asteroids_win = 2;
				this._setInstructions("oolite-tutorial-3-4b");
			}
			else 
			{
				this._setInstructions("oolite-tutorial-3-4a");
				missionVariables.oolite_tutorial_asteroids_win = 1;
			}
		}
		else
		{
			this._setInstructions("oolite-tutorial-3-4");
		}
		this.$advanceByEquipment = true;
	}

	this.__stage3sub5 = function()
	{
		this._setFrameCallback("");
		if (missionVariables.oolite_tutorial_asteroids_win == 2 || player.ship.speed > 1)
		{
			this._nextSection();
		}
		else
		{
			this._restartSection();
		}
	}


	this.__stage4sub0 = function()
	{
		if (missionVariables.oolite_tutorial_asteroids_win == 1)
		{
			this._scoreWin("asteroids_result");
		}
		else if (missionVariables.oolite_tutorial_asteroids_win >= 2)
		{
			this._scoreBonus("asteroids_result");
		}
		else if (missionVariables.oolite_tutorial_asteroids > 0)
		{
			this._scoreTry("asteroids_result");
		}
		var rocks = system.entitiesWithScanClass("CLASS_ROCK");
		for (var i=rocks.length-1;i>=0;--i)
		{
			rocks[i].remove();
		}
		rocks = system.entitiesWithScanClass("CLASS_CARGO");
		for (i=rocks.length-1;i>=0;--i)
		{
			rocks[i].remove();
		}
		//... move this line to later when there are more sections
		this._setInstructions("oolite-tutorial-4-0");

	}

	this.__stage4sub1 = function()
	{
		this._setInstructions("oolite-tutorial-4-1");
		this._addShips("asteroid",3,player.ship.position,20E3);
	}

	this.__stage4sub2 = function()
	{
		this._setInstructions("oolite-tutorial-4-2");
		this._addShips("splinter",3,player.ship.position,20E3);
	}

	this.__stage4sub3 = function()
	{
		this._setInstructions("oolite-tutorial-4-3");
		this._resetShips();
	}

	this.__stage4sub4 = function()
	{
		this._setInstructions("oolite-tutorial-4-4");
	}

	this.__stage4sub5 = function()
	{
		this._setInstructions("oolite-tutorial-4-5");
		this._addShips("asteroid",5,player.ship.position,20E3);
	}

	this.__stage4sub6 = function()
	{
		this._setInstructions("oolite-tutorial-4-6");
		var ships = this._addShips("boulder",5,player.ship.position,10E3);
		for (var i=0;i<5;i++)
		{
			ships[i].velocity = Vector3D.random(150);
		}
	}

	this.__stage4sub7 = function()
	{
		this._setInstructions("oolite-tutorial-4-7");
		var ships = this._addShips("splinter",5,player.ship.position,10E3);
		for (var i=0;i<5;i++)
		{
			ships[i].velocity = Vector3D.random(150);
		}
	}

	this.__stage5sub0 = function()
	{
		this._setInstructions("oolite-tutorial-5-0");
	}

	this.__stage5sub1 = function()
	{
		this._setInstructions("oolite-tutorial-5-1");
	}

	this.__stage5sub2 = function()
	{
		this._setInstructions("oolite-tutorial-5-2");
		this._addShips("tutorial-asteroid",2,player.ship.position,20E3);
	}

	this.__stage5sub3 = function()
	{
		this._setInstructions("oolite-tutorial-5-3");
	}

	this.__stage5sub4 = function()
	{
		this._setInstructions("oolite-tutorial-5-4");
	}

	this.__stage5sub5 = function()
	{
		this._setInstructions("oolite-tutorial-5-5");
	}

	this.__stage5sub6 = function()
	{
		this._setInstructions("oolite-tutorial-5-6");
	}

	this.__stage5sub7 = function()
	{
		this._setInstructions("oolite-tutorial-5-7");
	}

	this.__stage5sub8 = function()
	{
		this._setInstructions("oolite-tutorial-5-8");
	}

	this.__stage5sub9 = function()
	{
		this._setInstructions("oolite-tutorial-5-9");
	}

	this.__stage5sub10 = function()
	{
		this._setInstructions("oolite-tutorial-5-10");
	}

	this.__stage5sub11 = function()
	{
		this._setInstructions("oolite-tutorial-5-11");
		var adder = this._addShips("[adder]",1,player.ship.position.add([6E3,6E3,6E3]),0)[0];
		adder.target = player.ship;
		adder.fireMissile();
		adder.remove();
	}

	this.__stage6sub0 = function()
	{
		this._setInstructions("oolite-tutorial-6-0");
	}

	this.__stage6sub1 = function()
	{
		this._setInstructions("oolite-tutorial-6-1");
	}

	this._stage6scorer = function()
	{
		missionVariables.oolite_tutorial_combat_stage = this.$tutorialSubstage;
		missionVariables.oolite_tutorial_combat_duration = Math.floor(clock.seconds - this.$combatClock);
	}

	this.__stage6sub2 = function()
	{
		this.$advanceByEquipment = false;
		this._setInstructions("oolite-tutorial-6-2");
		var buoy = this._addShips("oolite-tutorial-buoy",1,player.ship.position,3E3)[0];
		this.$combatClock = clock.seconds;
		buoy.script.shipTakingDamage = function()
		{
			this._stage6scorer();
			this._nextSection();
		}.bind(this);
		/* force buoy to be within scanner range */
		buoy.script.$timer = new Timer (buoy.script,function() {
			if (this.ship.position.distanceTo(player.ship) > 25E3)
			{
				this.ship.position = player.ship.position.add([0,0,10E3]);
			}
		},5,5);


		var target = this._addShips("oolite-tutorial-fighter",1,player.ship.position,10E3);
		target[0].forwardWeapon = "EQ_WEAPON_NONE";
		target[0].accuracy = 5;
	}

	this.__stage6sub3 = function()
	{
		this._setInstructions("oolite-tutorial-6-3");
		var target = this._addShips("oolite-tutorial-fighter",1,player.ship.position,10E3);
		target[0].accuracy = 0;
		this._stage6scorer();
	}

	this.__stage6sub4 = function()
	{
		this._setInstructions("oolite-tutorial-6-4");
		var target = this._addShips("oolite-tutorial-fighter",2,player.ship.position,10E3);
		target[0].accuracy = 0;
		target[1].accuracy = 0;
		this._stage6scorer();
	}
	
	this.__stage6sub5 = function()
	{
		this.$advanceByEquipment = true;
		this._setInstructions("oolite-tutorial-6-5");
		this._stage6scorer();
	}

	this.__stage6sub6 = function()
	{
		this.$advanceByEquipment = false;
		this._setInstructions("oolite-tutorial-6-6");
		var target = this._addShips("oolite-tutorial-fighter",1,player.ship.position,10E3)
		target[0].accuracy = 0;
		target[0].forwardWeapon = "EQ_WEAPON_BEAM_LASER";
		this._stage6scorer();
	}

	this.__stage6sub7 = function()
	{
		this._setInstructions("oolite-tutorial-6-7");
		var target = this._addShips("oolite-tutorial-fighter",2,player.ship.position,10E3)
		target[0].accuracy = 0;
		target[0].forwardWeapon = "EQ_WEAPON_BEAM_LASER";
		target[1].accuracy = 0;
		target[1].forwardWeapon = "EQ_WEAPON_BEAM_LASER";
		this._stage6scorer();
	}

	this.__stage6sub8 = function()
	{
		this.$advanceByEquipment = true;
		this._setInstructions("oolite-tutorial-6-8");
		this._stage6scorer();
	}

	this.__stage6sub9 = function()
	{
		this.$advanceByEquipment = false;
		this._setInstructions("oolite-tutorial-6-9");
		var target = this._addShips("oolite-tutorial-fighter",1,player.ship.position,10E3)
		target[0].accuracy = 6;
		target[0].forwardWeapon = "EQ_WEAPON_BEAM_LASER";
		target[0].awardEquipment("EQ_ECM");
		target[0].awardEquipment("EQ_FUEL_INJECTION");
		target[0].awardEquipment("EQ_SHIELD_BOOSTER");
		this._stage6scorer();
	}

	this.__stage6sub10 = function()
	{
		this.$advanceByEquipment = true;
		this._setInstructions("oolite-tutorial-6-10");
		this._stage6scorer();
	}

	this.__stage7sub0 = function()
	{
		if (missionVariables.oolite_tutorial_combat_stage > 0)
		{
			if (missionVariables.oolite_tutorial_combat_stage > 9)
			{
				this._scoreBonus("combat_result");
			}
			else if (missionVariables.oolite_tutorial_combat_stage > 7)
			{
				this._scoreWin("combat_result");
			}
			else if (missionVariables.oolite_tutorial_combat_stage > 4)
			{
				this._scoreTry("combat_result");
			}
		}

		this._setInstructions("oolite-tutorial-7-0");
	}

	this.__stage7sub1 = function()
	{
		this._setInstructions("oolite-tutorial-7-1");
	}

	this.__stage7sub2 = function()
	{
		this._setInstructions("oolite-tutorial-7-2");
		var station = this._addShips("oolite-tutorial-station",1,player.ship.position,15E3)[0];
		var buoy = this._addShips("oolite-tutorial-buoy",1,station.position.add(station.vectorForward.multiply(10E3)),0)[0];
	}

	this.__stage7sub3 = function()
	{
		this._setInstructions("oolite-tutorial-7-3");
	}

	this.__stage7sub4 = function()
	{
		this._setInstructions("oolite-tutorial-7-4");
	}

	this.__stage7sub5 = function()
	{
		this._setInstructions("oolite-tutorial-7-5");
	}

	this.__stage7sub6 = function()
	{
		this._setInstructions("oolite-tutorial-7-6");
	}

	this.__stage7sub7 = function()
	{
		this._setInstructions("oolite-tutorial-7-7");
	}

	this.__stage7sub8 = function()
	{
		this._setInstructions("oolite-tutorial-7-8");
	}

	this.__stage7sub9 = function()
	{
		this._setInstructions("oolite-tutorial-7-9");
	}

	this.__stage7sub10 = function()
	{
		this._setInstructions("oolite-tutorial-7-10");
	}

	this.__stage7sub11 = function()
	{
		this._setInstructions("oolite-tutorial-7-11");
	}

	this.__stage7sub12 = function()
	{
		this._setInstructions("oolite-tutorial-7-12");
	}

	this.__stage7sub13 = function()
	{
		this.$advanceByEquipment = false;
		this._setFrameCallback(this._dockingMonitor.bind(this));
	}

	this.__stage8sub0 = function()
	{
		this._setInstructions("oolite-tutorial-8-0");
	}

	this.__stage8sub1 = function()
	{
		this._setInstructions("oolite-tutorial-8-1");
	}

	this.__stage8sub2 = function()
	{
		this._setInstructions("oolite-tutorial-8-2");
	}

	this.__stage8sub3 = function()
	{
		this._setInstructions("oolite-tutorial-8-3");
		player.ship.awardEquipment("EQ_HEAT_SHIELD");
		player.ship.awardEquipment("EQ_ENERGY_UNIT");
	}

	this.__stage8sub4 = function()
	{
		this._setInstructions("oolite-tutorial-8-4");
		player.ship.setEquipmentStatus("EQ_HEAT_SHIELD","EQUIPMENT_DAMAGED");
	}

	this.__stage8sub5 = function()
	{
		this._setInstructions("oolite-tutorial-8-5");
	}

	this.__stage8sub6 = function()
	{
		player.ship.manifest.food = 5;
		player.ship.manifest.minerals = 3;
		player.ship.manifest.gold = 13;
		mission.setInstructionsKey("oolite-tutorial-8-6-info",this.name);
		this._setInstructions("oolite-tutorial-8-6");
	}

	this.__stage8sub7 = function()
	{
		this._setInstructions("oolite-tutorial-8-7");
	}

	this.__stage8sub8 = function()
	{
		mission.markSystem(55);
		this._setInstructions("oolite-tutorial-8-8");
	}

	this.__stage8sub9 = function()
	{
		this._setInstructions("oolite-tutorial-8-9");
	}

	this.__stage8sub10 = function()
	{
		this._setInstructions("oolite-tutorial-8-10");
	}

	this.__stage8sub11 = function()
	{
		this._setInstructions("oolite-tutorial-8-11");
	}

	this.__stage8sub12 = function()
	{
		this._setInstructions("oolite-tutorial-8-12");
	}

	this.__stage8sub13 = function()
	{
		this._setInstructions("oolite-tutorial-8-13");
	}

	this.__stage8sub14 = function()
	{
		this._setInstructions("oolite-tutorial-8-14");
	}

	this.__stage8sub15 = function()
	{
		this._setInstructions("oolite-tutorial-8-15");
	}

	this.__stage8sub16 = function()
	{
		this._setInstructions("oolite-tutorial-8-16");
	}

	this.__stage8sub17 = function()
	{
		this._setInstructions("oolite-tutorial-8-17");
	}

	this.__stage8sub18 = function()
	{
		this._setInstructions("oolite-tutorial-8-18");
	}

	this.__stage8sub19 = function()
	{
		this._setInstructions("oolite-tutorial-8-19");
	}

	this.__stage8sub20 = function()
	{
		this._setInstructions("oolite-tutorial-8-20");
	}

	this.__stage8sub21 = function()
	{
		this._setInstructions("oolite-tutorial-8-21");
	}

	this.__stage8sub22 = function()
	{
		this._setInstructions("oolite-tutorial-8-22");
	}

	this.__stage8sub23 = function()
	{
		this._setInstructions("oolite-tutorial-8-23");
	}

	this.__stage8sub24 = function()
	{
		this._setInstructions("oolite-tutorial-8-24");
	}

	this.__stage9sub0 = function()
	{
		player.ship.removeEquipment("EQ_HEAT_SHIELD");
		player.ship.removeEquipment("EQ_ENERGY_UNIT");
		this._setInstructions("oolite-tutorial-9-0");
	}

	this.__stage9sub1 = function()
	{
		this._setInstructions("oolite-tutorial-9-1");
		this.$blockTorus = false;
		player.ship.position = [0,0,-8E3];
	}

	this.__stage9sub2 = function()
	{
		this._setInstructions("oolite-tutorial-9-2");
		this._showHUDItem("drawCompass:");
	}

	this.__stage9sub3 = function()
	{
		this._setInstructions("oolite-tutorial-9-3");
		this._setFrameCallback(function(delta) 
		{
			if (player.ship.speed > player.ship.maxSpeed * 10)
			{
				this._nextItem();
			}
		}.bind(this));
	}

	this.__stage9sub4 = function()
	{
		var accum = 0;
		this._setFrameCallback(function(delta)
		{
			accum += delta;
			if (accum > 20)
			{
				this._nextItem();
			}
		}.bind(this));
		this._setInstructions("oolite-tutorial-9-4");
	}

	this.__stage9sub5 = function()
	{
		this._setFrameCallback("");
		var t = this._addShips("[moray]",1,player.ship.position.add(player.ship.vectorForward.multiply(26E3)),0)[0];
		t.homeSystem = 55;
		t.destinationSystem = 7;
		t.setCargoType("SCARCE_GOODS");
		t.primaryRole = "trader";
		t.setAI("oolite-traderAI.js");
		this._setInstructions("oolite-tutorial-9-5");
	}

	this.__stage9sub6 = function()
	{
		this._setInstructions("oolite-tutorial-9-6");
		player.ship.manifest.textiles = 2;
		player.ship.manifest.radioactives = 3;
	}

	this.__stage9sub7 = function()
	{
		this._resetShips();
		this._setInstructions("oolite-tutorial-9-7");
		this._showHUDItem("drawAltitudeBar:");
	}

	this.__stage9sub8 = function()
	{
		if (system.mainPlanet.position.distanceTo(player.ship) > system.mainPlanet.radius * 3)
		{
			player.consoleMessage(expandMissionText("oolite-tutorial-9-7-toofar"));
			--this.$tutorialSubstage;
		}
		else
		{
			this._setInstructions("oolite-tutorial-9-8");
			this._showHUDItem("drawCompass:");
		}
	}

	this.__stage9sub9 = function()
	{
		this._setInstructions("oolite-tutorial-9-9");
	}

	this.__stage9sub10 = function()
	{
		if (system.mainStation.position.distanceTo(player.ship) > 51200)
		{
			player.consoleMessage(expandMissionText("oolite-tutorial-9-9-toofar"));
			--this.$tutorialSubstage;
		}
		else
		{
			this._setInstructions("oolite-tutorial-9-10");
			this._showHUDItem("drawAegis");
		}
	}


	this.__stage9sub11 = function()
	{
		this.$advanceByEquipment = false;
		this._setInstructions("oolite-tutorial-9-11");
	}

	this._endTutorial = function()
	{
		player.ship.hudHidden = true;
		mission.runScreen(
			{
				titleKey: "oolite-tutorial-end-title",
				messageKey: "oolite-tutorial-end-message",
				choicesKey: "oolite-tutorial-end-choices",
				screenID: "oolite-tutorial-end"
			},function()
			{
				player.endScenario("oolite-tutorial");
			}
		);
	}

}


/* Define this outside the tutorial - it might be useful! */
this._dockingMonitor = function(delta)
{
	var report = "";
	if (!player.ship.target || !player.ship.target.isStation)
	{
		report += "[oolite-tutorial-dock-notarget]";
	}
	else
	{
		// check weapons
		report += "[oolite-tutorial-dock-weapons]";
		if (player.ship.weaponsOnline)
		{
			report += "[oolite-tutorial-dock-weapons-bad]";
		}
		else
		{
			report += "[oolite-tutorial-dock-weapons-good]";
		}
		
		// check clearance
		report += "[oolite-tutorial-dock-clearance]";
		switch (player.dockingClearanceStatus)
		{
		case "DOCKING_CLEARANCE_STATUS_NONE":
			report += "[oolite-tutorial-dock-clearance-bad]";
			break;
		case "DOCKING_CLEARANCE_STATUS_REQUESTED":
			report += "[oolite-tutorial-dock-clearance-wait]";
			break;
		case "DOCKING_CLEARANCE_STATUS_NOT_REQUIRED":
		case "DOCKING_CLEARANCE_STATUS_GRANTED":
			report += "[oolite-tutorial-dock-clearance-good]";
			break;
		case "DOCKING_CLEARANCE_STATUS_TIMING_OUT":
			report += "[oolite-tutorial-dock-clearance-expiring]";
			break;
		}

		// find dock
		var station = player.ship.target;
		var docks = station.subEntities;
		var dock = null;
		for (var i=0;i<docks.length;i++)
		{
			if (docks[i].isDock && docks[i].isQueued(player.ship))
			{
				dock = docks[i];
				break;
			}
		}
		if (dock != null)
		{
			// absolute position of dock
			var dpos = station.position.add(station.vectorRight.multiply(dock.position.x)).add(station.vectorUp.multiply(dock.position.y)).add(station.vectorForward.multiply(dock.position.z));
			// basis vectors in worldspace for dock
			var dor = station.orientation.multiply(dock.orientation);
			var dfwd = dor.vectorForward();
			var dhoriz; var dvert; var shoriz; var svert; var dsize;
			if (dock.boundingBox.y > dock.boundingBox.x)
			{
				// dock basis vectors
				dhoriz = dor.vectorUp();
				dvert = dor.vectorRight();
				// safety margins
				shoriz = (dock.boundingBox.y - player.ship.boundingBox.x)/2;
				svert = (dock.boundingBox.x - player.ship.boundingBox.y)/2;
				dsize = dock.boundingBox.x / 2;
			}
			else
			{
				dvert = dor.vectorUp();
				dhoriz = dor.vectorRight();
				// safety margins
				shoriz = (dock.boundingBox.x - player.ship.boundingBox.x)/2
				svert = (dock.boundingBox.y - player.ship.boundingBox.y)/2;
				dsize = dock.boundingBox.y / 2;
			}
			
			// check approach direction and course
			report += "[oolite-tutorial-dock-approach]";
			var relpos = dpos.subtract(player.ship.position);
			var distance = relpos.magnitude();

			if (player.ship.vectorForward.dot(relpos.direction()) < Math.cos(Math.atan(dsize/distance)) && distance > dock.boundingBox.z)
			{
				report += "[oolite-tutorial-dock-approach-bad]";
			}
			else
			{
				var x = Math.abs(dhoriz.dot(relpos));
				var y = Math.abs(dvert.dot(relpos));
				
				if (x < shoriz && y < svert)
				{
					report += "[oolite-tutorial-dock-approach-good]";
				}
				else if (Math.abs(dfwd.dot(relpos)) > 0.999 && distance > 750)
				{
					report += "[oolite-tutorial-dock-approach-okay]";
				}
				else if (x < shoriz+50 && y < svert+50)
				{
					report += "[oolite-tutorial-dock-approach-okay]";
				}
				else
				{
					report += "[oolite-tutorial-dock-approach-off]";
				}
			}

			// check speed
			report += "[oolite-tutorial-dock-speed]";
			var target = 40;
			if (distance > 1000)
			{
				target = 75;
				if (distance > 2000)
				{
					target = 120;
					if (distance > 4000)
					{
						target = 200;
					}
				}
			}
			if (player.ship.speed > target * 1.5)
			{
				report += "[oolite-tutorial-dock-speed-fast]";
			}
			else if (player.ship.speed < target * 0.5)
			{
				report += "[oolite-tutorial-dock-speed-slow]";
			}
			else
			{
				report += "[oolite-tutorial-dock-speed-good]";
			}

			// check roll
			report += "[oolite-tutorial-dock-roll]";
			var roll = Math.abs(player.ship.vectorRight.dot(dhoriz));
			if (roll > 0.99)
			{
				report += "[oolite-tutorial-dock-roll-good]";
			}
			else if (roll > 0.95)
			{
				report += "[oolite-tutorial-dock-roll-okay]";
			}
			else
			{
				report += "[oolite-tutorial-dock-roll-bad]";
			}


		}
	}
	var result = expandDescription(report);
	player.ship.setMultiFunctionText("oolite-tutorial",result,true);
	player.ship.setMultiFunctionDisplay(0,"oolite-tutorial");
}