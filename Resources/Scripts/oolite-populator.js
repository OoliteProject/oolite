/*

oolite-populator.js

Built-in system populator settings


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
/*global missionVariables, player*/


"use strict";


this.name			= "oolite-populator";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";

/* Basic system population */
this.systemWillPopulate = function() 
{
		/* Priority range 0-99 used by Oolite default populator */

		/* Add navigation buoys */
		// for the compass to work properly, the buoys need to be added first,
		// in this order.
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

		/* Add asteroids */
		var clusters = 2*(1+Math.floor(system.scrambledPseudoRandomNumber(51728)*4));
		var psclusters = 1+(clusters/2);
		clusters = clusters-psclusters;
		
		var addRockCluster = function(pos) 
		{
				var size = 1+Math.floor(system.scrambledPseudoRandomNumber(Math.floor(pos.x))*11);
				var hermit = (system.scrambledPseudoRandomNumber(Math.floor(pos.y))*31) <= size;
				var rocks = system.addShips("asteroid",size,pos,25E3);
				// don't add rock hermits if the sun is about to explode
				if (hermit && !system.sun.isGoingNova) 
				{
						var rh = system.addShips("rockhermit",1,pos,0)[0];
						rh.scanClass = "CLASS_ROCK";
				}
		}

		system.setPopulator("oolite-route1-asteroids",
												{
														priority: 20,
														location: "LANE_WP",
														locationSeed: 51728,
														groupCount: clusters,
														callback: addRockCluster,
														deterministic: true
												});
		system.setPopulator("oolite-route2-asteroids",
												{
														priority: 20,
														location: "LANE_PS",
														locationSeed: 82715,
														groupCount: psclusters,
														callback: addRockCluster,
														deterministic: true
												});

		/* Mainly for nova mission. If the nova script runs first, then
		 * this is set and we stop here. If this script runs first, the
		 * nova mission populator removes the entries this script adds. */
		if (system.sun.isGoingNova)
		{
				return;
		}

		/* Calculate numbers of major groups */
		var gov = system.info.government; // 0=anarchy, 7=corporate
		var eco = system.info.economy; // 0=rich ind, 7=poor ag
		/* Calculate traders */
		var traders = 9 - eco;
		if (gov == 0) 
		{
				traders *= 1.25;
		}
		// randomise with centred distribution
		traders = 1 + traders * (Math.random() + Math.random());
		// trim if too many
		while (traders > 15)
		{
				traders = 1+(Math.random()*traders);
		}
		traders = Math.floor(traders);

		var pstraders = Math.floor((Math.random()*4) + (traders * (Math.random()*32) / 120));
		
		/* Calculate pirates */
		// more in more dangerous systems, more if more traders about
		var pirates = ((traders/3)+Math.random()+Math.random())*(8-gov);
		// randomise with centred distribution
		pirates = 1 + pirates * (Math.random() + Math.random());
		// trim if too many
		while (pirates > 25)
		{
				pirates = 12+(Math.random()*pirates);
		}
		
		var pspirates = pirates * Math.random()*32/120;
		/* old populator allocated these pirates individually to various
		 * packs.  this populator doesn't make it easy to do this the same
		 * way so instead, divide the number of pirates by the expected
		 * pack size to get the number of packs */
		pirates = Math.floor(pirates/2.5);
		pspirates = Math.floor(pspirates/2.5);

		/* Calculate bounty hunters */
		var hunters = (1+gov)*(traders/8);
		// more in anarchy
		if (gov==0)
		{
				hunters *= 1.25;
		}
		// randomise with centred distribution
		hunters = 1 + hunters * (Math.random() + Math.random());
		// trim if too many
		while (hunters > 15)
		{
				hunters = 5+(Math.random()*hunters);
		}
		hunters = Math.ceil(hunters);
		var pshunters = Math.floor(hunters * Math.random()*32/160);
		
		if (hunters+pirates+traders < 10) 
		{
				// too quiet
				hunters += 2;
				pirates += 1;
				traders += 2;
		}
		
		/* Calculate thargoids */
		var thargoids = 0;
		while (Math.random() < 0.065)
		{
				thargoids++;
		}
		
		/* Start adding ship groups */

		/* Add traders */
		system.setPopulator("oolite-route1-traders",
												{
														priority: 20,
														location: "LANE_WP",
														groupCount: traders,
														callback: function(pos) {
																var r1t = system.addShips("trader",1,pos,0)[0];
																r1t.setBounty(0,"setup actions");
														}
												});

		system.setPopulator("oolite-route2-traders",
												{
														priority: 20,
														location: "LANE_PS",
														groupCount: pstraders,
														callback: function(pos) {
																var r2t = system.addShips("sunskim-trader",1,pos,0)[0];
																r2t.setBounty(0,"setup actions");
																// ensure sufficient insulation
																// tested at Aenqute - see [Universe makeSunSkimmer]
																var reqInsulation = 1000/(1+r2t.maxSpeed);
																if (reqInsulation > 12)
																{
																		reqInsulation = 12;
																		// 12 is enough to survive indefinitely
																		// anywhere in non-nova systems
																}
																if (r2t.heatInsulation < reqInsulation)
																{
																		r2t.heatInsulation = reqInsulation;
																}
																r2t.switchAI("traderAI.js");
														}
												});
		
		/* Add pirates */

		system.setPopulator("oolite-route1-pirates",
												{
														priority: 20,
														location: "LANE_WP",
														groupCount: pirates,
														callback: this._addPirates
												});

		system.setPopulator("oolite-route2-pirates",
												{
														priority: 20,
														location: "LANE_PS",
														groupCount: pspirates,
														callback: this._addPirates
												});

		/* Add hunters */
		var addHunter = function(pos) 
		{
				if (Math.random()*8 < system.government)
				{
						// add police
						if (Math.random()*8 < system.techLevel - 6)
						{
								var hunter = system.addShips("interceptor",1,pos,0)[0];
								hunter.primaryRole = "police";
						}
						else
						{
								var hunter = system.addShips("police",1,pos,0)[0];
						}								
						hunter.switchAI("policeAI.js");
				}
				else
				{
						var hunter = system.addShips("hunter",1,pos,0)[0];
						hunter.switchAI("bountyHunterAI.js");

				}
				hunter.setBounty(0,"setup actions");
				return hunter;
		}
		system.setPopulator("oolite-route1-hunters",
												{
														priority: 20,
														location: "LANE_WP",
														groupCount: hunters,
														callback: addHunter
												});

		system.setPopulator("oolite-route2-hunters",
												{
														priority: 20,
														location: "LANE_PS",
														groupCount: hunters,
														callback: function(pos) {
																var hunter = addHunter(pos);
														}
												});
		
		/* Add thargoids */
		system.setPopulator("oolite-route1-thargoids",
												{
														priority: 20,
														location: "LANE_WP",
														groupCount: thargoids,
														callback: function(pos) {
																system.addShips("thargoid",1,pos,0);
														}
												});
		

		/* To ensure there's at least one hermit, for ships avoiding the main station to dock at */
		system.setPopulator("oolite-offlane-hermit",
												{
														priority: 99, // make sure all other core population is done
														location: "PLANET_ORBIT_HIGH",
														locationSeed: 71258,
														groupCount: 1,
														callback: function(pos) {
																if (system.countShipsWithPrimaryRole("rockhermit")==0) {
																		var rh = system.addShips("rockhermit",1,pos,0)[0];
																		rh.scanClass = "CLASS_ROCK";
																		// just the hermit, no other rocks
																}
														},
														deterministic: true
												});

}


// function responsible for replenishing system contents
this.systemWillRepopulate = function()
{
		if (system.sun.isGoingNova)
		{
				return;
		}

		// incoming traders, more frequent in rich economies
		if (Math.random() < 0.06+0.01*(8-system.info.economy)) 
		{
				if (Math.random() < 0.2)
				{
						var newtrader = system.addShips("sunskim-trader",1,[0,0,0],7500)[0];
						var reqIns = 1000/(1+newtrader.maxSpeed);
						if (reqIns > 12) 
						{
								reqIns = 12;
						}
						if (newtrader.heatInsulation < reqIns)
						{
								newtrader.heatInsulation = reqIns;
						}
						newtrader.primaryRole = "trader";
						newtrader.switchAI("traderAI.js");
						// and encourage sunskimming
						newtrader.fuel = Math.random()*2;
						newtrader.setCargoType("PLENTIFUL_GOODS"); 
				}
				else
				{
						var newtrader = system.addShips("trader",1,[0,0,0],7500)[0];
						newtrader.setCargoType("SCARCE_GOODS"); 
				}
				newtrader.setBounty(0,"setup actions");
				return;
		}

		// replace lost patrols (more frequently in safe systems)
		if (Math.random() < 0.05+0.02*(1+system.info.government)) 
		{
				var current = system.countShipsWithPrimaryRole("police");
				var target = system.info.government;
				if (current < target) 
				{
						var newpolice = system.mainStation.launchShipWithRole("police");
						newpolice.switchAI("policeAI.js");
						newpolice.setBounty(0,"setup actions");
				}
				else
				{
						// enough police, add a bounty hunter instead?
						current = system.countShipsWithPrimaryRole("hunter");
						if (system.info.government <= 1)
						{
								target = 4;
						}
						else
						{
								target = system.info.government/2;
						}
						if (current < target)
						{
								var newhunter = system.addShips("hunter",1,[0,0,0],7500)[0];
								newhunter.switchAI("bountyHunterAI.js");
								newhunter.setBounty(0,"setup actions");
						}
				}		
				return;
		}
		
		// replace lost pirates
		if (Math.random() < 0.02*(8-system.info.government))
		{
				var current = system.countShipsWithPrimaryRole("pirate");
				var target = 3*(8-system.info.government);
				if (current < target)
				{
						// temporary hack: pirates don't currently have the AI to fly
						// to their raiding grounds, so for now just magically have
						// them appear on the spacelane when the player isn't looking
						do
						{
								if (Math.random() < 0.15)
								{
										var pos = Vector3D.interpolate(system.sun.position, system.mainPlanet.position, 0.3+Math.random()*0.5);
								}
								else
								{
										var pos = Vector3D.interpolate([0,0,0], system.mainPlanet.position, Math.random()*0.8);
								}
						}
						while (pos.distanceTo(player.ship) < 51200);
						this._addPirates(pos);
				}
				return;
		}

		// Thargoid invasions
		// TODO: Need to think more about how new thargoids get added in.
		if (Math.random() < 0.001)
		{
				system.addShips("thargoid",1,system.planet.position.multiply(0.5),7500);
		}

}


/* And the equivalent functions for interstellar space */

this.interstellarSpaceWillPopulate = function() 
{
		system.setPopulator("oolite-interstellar-thargoids",
												{
														priority: 10,
														location: "WITCHPOINT",
														groupCount: 2+Math.floor(Math.random()*4),
														callback: function(pos) {
																system.addShips("thargoid",1,pos,0);
														}
												});
}

this.interstellarSpaceWillRepopulate = function()
{
		if (system.countShipsWithPrimaryRole("thargoid") < 2)
		{
				if (Math.random() > 0.01)
				{
						system.addShips("thargoid",1,[0,0,0],25600);
				}
				else
				{
						// everyone's getting ambushed today
						system.addShips("trader",1,[0,0,0],6400);
				}
		}
}

/* And finally the default nova system populators */

this.novaSystemWillPopulate = function()
{
		// just burnt-out rubble
		system.setPopulator("oolite-nova-cinders",
												{
														priority: 10,
														location: "WITCHPOINT",
														groupCount: 1,
														callback: function(pos) {
																system.addShips("cinder",10,pos,25600);
																pos.z += 300000;
																system.addShips("cinder",10,pos,25600);
														}
												});

}


/* // no repopulation is needed, but other OXPs could use this function
this.novaSystemWillRepopulate = function()
{

}
*/

/* Utility functions */

this._addPirates = function(pos) 
{
		var size = Math.random()*4;
		if (system.government >= 6)
		{
				size = size/2;
		}
		else if (system.government <= 1)
		{
				size += Math.random()*3;
		}
		size = Math.ceil(size);
		var pg = system.addGroup("pirate",size,pos,2.5E3);
		for (var i=0;i<pg.ships.length;i++)
		{
				pg.ships[i].setBounty(20+system.government+size+Math.floor(Math.random()*8),"setup actions");
//				pg.ships[i].switchAI("pirateAI.js"); // testing only!
		}
}
