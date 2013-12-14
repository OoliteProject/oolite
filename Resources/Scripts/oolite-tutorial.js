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

	/* Number of substages in each stage */
	this.$tutorialStages = [
		3, // stage 0: mission screen, post-launch cleanup, intro message
		25, // stage 1: HUD displays
		11, // stage 2: scanner and views
		6, // stage 3: basic flight challenge
		0, // stage 4: (not yet started)
	];

	this.$shipList = [];

	missionVariables.oolite_tutorial_deaths = 0;
	missionVariables.oolite_tutorial_asteroids = 0;
	missionVariables.oolite_tutorial_asteroids_win = 0;
	missionVariables.oolite_tutorial_asteroids_result = expandMissionText("oolite-tutorial-end-notry");

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
	}


	this.shipLaunchedFromStation = function(station)
	{
		if (this.$tutorialStage == 0 && this.$tutorialSubstage == 1)
		{	
			station.position = station.position.add([0,0,1E7]);
			station.remove();
			this._nextItem();
		}
	}

	
	this.shipTakingDamage = function(amount, whom, type)
	{
		if (amount >= player.ship.energy)
		{
			player.ship.position = system.locationFromCode("OUTER_SYSTEM_OFFPLANE");
			--this.$tutorialStage;
			this.$tutorialSubstage = 9999;
			player.ship.dealEnergyDamage(1,10000,0);
			this._playSound("bigbang.ogg");
			player.consoleMessage(expandMissionText("oolite-tutorial-no-death"));
			missionVariables.oolite_tutorial_deaths++;
			this._nextItem(); // will call nextSection, which will reset energy
		}
	}


	this.playerStartedJumpCountdown = function()
	{
		player.ship.cancelHyperspaceCountdown();
		player.consoleMessage(expandMissionText("oolite-tutorial-no-witchspace"));
	}

	this._playSound = function(snd)
	{
		this.$tutorialSound.stop();
		this.$tutorialSound.sound = snd;
		this.$tutorialSound.play();
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
		this._setFrameCallback(null);
		player.ship.hudHidden = false;
		for (i=this.$shipList.length-1;i>=0;i--)
		{
			if (this.$shipList[i] && this.$shipList[i].isShip)
			{
				this.$shipList[i].remove();
			}
		}
		var fc = addFrameCallback(function(delta)
								  {
									  player.ship.velocity = player.ship.thrustVector;
									  removeFrameCallback(fc);
								  });

	}

	this._addShips = function(role,num,pos,rad)
	{
		var arr = system.addShips(role,num,pos,rad);
		this.$shipList = this.$shipList.concat(arr);
		return arr;
	}

	/* Tutorial stages */

	// __stage0sub1 not needed

	this.__stage0sub2 = function()
	{
		this._setInstructions("oolite-tutorial-0-2");
	}
	
	this.__stage1sub0 = function()
	{
		this._hideHUDItems();
		this._setInstructions("oolite-tutorial-1-0");
	}

	this.__stage1sub1 = function()
	{
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

	this.__stage2sub8 = function()
	{
		this._setInstructions("oolite-tutorial-2-8");
		this._addShips("oolite-tutorial-buoy",1,player.ship.position,10E3);
		var miss = this._addShips("missile",1,player.ship.position,10E3)[0];
		miss.setAI("nullAI.plist");
		var mine = this._addShips("energy-bomb",1,player.ship.position,10E3)[0];
		mine.setAI("nullAI.plist");
	}


	this.__stage2sub9 = function()
	{
		this._setInstructions("oolite-tutorial-2-9");
	}

	this.__stage2sub10 = function()
	{
		this._setInstructions("oolite-tutorial-2-10");
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
	}

	this.__stage3sub5 = function()
	{
		this._setFrameCallback("");
		this.$tutorialStage--;
		this._nextSection();
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
		this._setInstructions("oolite-tutorial-end-mfd");

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