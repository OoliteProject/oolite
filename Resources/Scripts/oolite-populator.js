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


this.startUp = function()
{
	// for translations
	this.$medicalReg = new RegExp(expandDescription("[medical-word]"),"i");
}


/* Basic system population */
this.systemWillPopulate = function() 
{

	/* Priority range 0-99 used by Oolite default populator */
	// anything added here with priority > 20 will be cancelled by the
	// nova mission populator if necessary

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
			rh.allegiance = this._hermitAllegiance(pos,system.info.government);
		}
	}.bind(this);

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

	/* To ensure there's at least one hermit, for smugglers to dock at */
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
									rh.allegiance = this._hermitAllegiance(pos,system.info.government);
									// just the hermit, no other rocks
								}
							}.bind(this),
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
	var i; var j; var k; var local; var second;

	/* Prepare repopulator information. The populator will calculate
	 * average hourly rates, and then populate the initial system
	 * based on those. The repopulator will add at those rates to try
	 * to maintain a steady state. */
	this.$repopulatorFrequencyIncoming = {};
	this.$repopulatorFrequencyOutgoing = {};

	/* Many traffic densities depend on systems in range. Get once for
	 * use in the rest of the set up */
	var locals = system.info.systemsInRange();
	this.$populatorLocals = locals;
	var seconds = [];
	for (i = 0; i < locals.length ; i++)
	{
		seconds[i] = locals[i].systemsInRange();
	}

	var verylocals = system.info.systemsInRange(3.5);
	this.$populatorVeryLocals = verylocals;
	var veryseconds = [];
	for (i = 0; i < verylocals.length ; i++)
	{
		veryseconds[i] = verylocals[i].systemsInRange(3.5);
	}

	this._debug("G"+(galaxyNumber+1)+": "+system.info.name);
	this._debug("Hub count: "+locals.length+" ("+verylocals.length+")");

	var bottleneck = this._systemIsBottleneck(locals,seconds);

	/* Calculate trader hourly rates first, as most other rates depend
	 * on them */
	var freighters = 0; // standard trade ships
	var couriers = 0; // fast parcel couriers or big passenger liners
	var smugglers = 0; // small fast illegal goods traders

	/* // for now just generate sources and destinations dynamically
	   this.$repopulatorFrequencyIncoming.traderFreighters = {};
	   this.$repopulatorFrequencyIncoming.traderCouriers = {};
	   this.$repopulatorFrequencyIncoming.traderSmugglers = {};
	   this.$repopulatorFrequencyOutgoing.traderFreighters = {};
	*/
	this.$repopulatorFrequencyIncoming.traderFreighters = 0;
	this.$repopulatorFrequencyIncoming.traderCouriers = 0;
	this.$repopulatorFrequencyIncoming.traderSmugglers = 0;
	this.$repopulatorFrequencyOutgoing.traderFreighters = 0;

	for (i = 0; i < locals.length ; i++)
	{
		// standard freighter traffic is mirrored
		local = locals[i];
		// traffic is higher between systems on opposite side of economy
		var ecomatch = -(system.info.economy-3.5)*(local.economy-3.5);
		var trdanger = 0;
		var rate = 0;
		// if either local or remote end is more dangerous than
		// Communist, reduce trader frequency
		if (local.government < 4)
		{
			trdanger = (4-local.government)*2.5;
		}
		if (system.info.government < 4)
		{
			trdanger += (4-system.info.government)*2.5;
		}
		// good economic match: one every 30 minutes if safe
		if (ecomatch > 0)
		{
			rate = 60/(30+trdanger);
		}
		// bad economic match: one every 2 hours if safe
		else
		{
			rate = 60/(120+(trdanger*2));
		}
		
		this.$repopulatorFrequencyIncoming.traderFreighters += rate;
		this.$repopulatorFrequencyOutgoing.traderFreighters += rate;
		freighters += rate;

		second = seconds[i];
		// couriers are non-mirrored
		rate = (20/(10+((14-local.techlevel)*5)))/second.length;
		if (bottleneck)
		{
			couriers *= 1.5; // simulate long-range routes
		}
		this.$repopulatorFrequencyIncoming.traderCouriers += rate;
		couriers += rate;
		// smugglers are non-mirrored
		rate = (20/(10+(local.techlevel*5)))/second.length;
		this.$repopulatorFrequencyIncoming.traderSmugglers += rate;
		smugglers += rate;
	}
	// and outgoing rates for smugglers/couriers. Don't need to
	// specify destination since all rates are equal
	rate = 20/(10+((14-system.info.techlevel)*5));
	this.$repopulatorFrequencyOutgoing.traderCouriers = rate;
	rate = (20/(10+(system.info.techlevel*5)))/locals.length;
	this.$repopulatorFrequencyOutgoing.traderSmugglers = rate;

	var traders = freighters+couriers+smugglers;
	
	/* Pirate rates next, based partly on trader rates */

	if (system.info.government == 0 && system.info.techlevel < 8)
	{
		this.$repopulatorFrequencyOutgoing.pirateAegisRaiders = 1/(8-system.info.techlevel);
	}
	else
	{
		this.$repopulatorFrequencyOutgoing.pirateAegisRaiders = 0;
	}

	// local independent pirate packs
	var pindependents = (1-system.info.government/12)*traders; 
	// organised pirate packs led by increasingly bigger freighters
	var lrate = 3/5; var mrate = 3/8; var hrate = 1/8;
	var pflight = 0;
	var pfmedium = 0;
	var pfheavy = 0;
	var pflightremote = 0;
	var pfmediumremote = 0;
	var pfheavyremote = 0;
	// rates of organised packs go up as government reduces
	if (system.info.government < 6)
	{
		pflight += lrate;
		if (system.info.government < 4)
		{
			pflight += lrate;
			pfmedium += mrate;
			if (system.info.government < 2)
			{
				// additional boost for independent packs in Feudal
				pindependents *= 1.2;
				pflight += lrate*2;
				pfmedium += mrate;
				pfheavy += hrate;
				if (system.info.government < 1)
				{
					pindependents *= 1.2;
					pflight *= 1.5;
					pfmedium *= 1.5;
					pfheavy *= 2;
				}
			}
		}
	}
	while (pindependents > 10)
	{
		pindependents *= 0.5;
	}
	this.$repopulatorFrequencyOutgoing.pirateIndependents = pindependents;
	this.$repopulatorFrequencyOutgoing.pirateLightPacks = pflight;
	this.$repopulatorFrequencyOutgoing.pirateMediumPacks = pfmedium;
	this.$repopulatorFrequencyOutgoing.pirateHeavyPacks = pfheavy;
	this.$repopulatorFrequencyIncoming.pirateLightPacks = 0;
	this.$repopulatorFrequencyIncoming.pirateMediumPacks = 0;
	this.$repopulatorFrequencyIncoming.pirateHeavyPacks = 0;
	if (verylocals.length > 0)
	{
		var found = false;
		// if there's at least one suitable system in range, half the
		// packs will jump out and then come back later.
		for (i = 0; i < verylocals.length ; i++)
		{
			local = verylocals[i];
			if (local.government < system.info.government)
			{
				found = true;
				break;
			}
		}
		if (found)
		{
			this.$repopulatorFrequencyIncoming.pirateLightPacksReturn = pflight/6; // (light packs 1/3 chance of jumping out)
			this.$repopulatorFrequencyIncoming.pirateMediumPacksReturn = pfmedium/2;
			this.$repopulatorFrequencyIncoming.pirateHeavyPacksReturn = pfheavy/2;
		}

		// we might also get packs coming from other nearby systems

		for (i = 0; i < verylocals.length ; i++)
		{
			local = verylocals[i];
			second = veryseconds[i];
			// pirate raids only against more ordered systems
			if (local.government < system.info.government)
			{
				var factor = 0;
				// split raids evenly between all systems in range of remote system
				for (j=0;j<second.length;j++)
				{
					if (local.government < second[j].government)
					{
						factor++;
					}
				}
				// only half generated there go out to raid 
				factor = 1/(factor*2); 
				var rlight = 0;
				var rmedium = 0;
				var rheavy = 0;
				if (local.government < 6)
				{
					rlight += lrate*factor;
					if (local.government < 4)
					{
						rlight += lrate*factor;
						rmedium += mrate*factor;
						if (local.government < 2)
						{
							rlight += lrate*factor;
							rmedium += mrate*factor;
							rheavy += hrate*factor;
							if (local.government < 1)
							{
								rlight *= 1.5;
								rmedium *= 1.5;
								rheavy *= 2.0;
							}
						}
					}
				}
				// light groups much less likely to jump systems
				pflight += rlight/3; pflightremote += rlight/3;
				pfmedium += rmedium; pfmediumremote += rmedium;
				pfheavy += rheavy; pfheavyremote += rheavy;
				this.$repopulatorFrequencyIncoming.pirateLightPacks += rlight/3;
				this.$repopulatorFrequencyIncoming.pirateMediumPacks += rmedium;
				this.$repopulatorFrequencyIncoming.pirateHeavyPacks += rheavy;
			}
		}
	}
	else
	{
		this.$repopulatorFrequencyIncoming.pirateLightPacksReturn = 0;
		this.$repopulatorFrequencyIncoming.pirateMediumPacksReturn = 0;
		this.$repopulatorFrequencyIncoming.pirateHeavyPacksReturn = 0;
	}
	
	var pirates = pindependents + pflight + pfmedium + pfheavy;
	
	/* Now hunters. Total hunter rate dependent on pirate numbers */
	// light fighters, mainly non-witchspace-capable
	// most common in confed/communist systems.
	var hlight = 60/(10+(5*(Math.abs(system.info.government-4.5)-0.5)));
	var hmedium = 0;
	var hheavy = 0;
	if (hlight > pirates * 2)
	{
		hlight = pirates * 2;
	}
	hlight = hlight / 3;
	this.$repopulatorFrequencyOutgoing.hunterLightPacks = hlight;

	this.$repopulatorFrequencyOutgoing.hunterMediumPacks = 0;
	this.$repopulatorFrequencyOutgoing.hunterHeavyPacks = 0;
	this.$repopulatorFrequencyIncoming.hunterMediumPacksReturn = 0;
	this.$repopulatorFrequencyIncoming.hunterHeavyPacksReturn = 0;
	this.$repopulatorFrequencyIncoming.hunterMediumPacks = 0;
	this.$repopulatorFrequencyIncoming.hunterHeavyPacks = 0;

	if (verylocals.length > 0)
	{
		var hmediumremote = 0;
		var hheavyremote = 0;
		if (system.info.government > 5)
		{
			// medium launch from Corp+Demo to Conf-Anar
			for (i=0;i<verylocals.length;i++)
			{
				local = verylocals[i];
				if (local.government <= 5)
				{
					// launch every 30, 2/3 return
					hmedium += 60/45;
					this.$repopulatorFrequencyOutgoing.hunterMediumPacks += 60/30;
					this.$repopulatorFrequencyIncoming.hunterMediumPacksReturn += 60/45;
				}
			}
		}
		else
		{
			// we're receiving them from nearby systems
			for (i=0;i<verylocals.length;i++)
			{
				local = verylocals[i];
				if (local.government > 5)
				{
					hmedium += 2;
					this.$repopulatorFrequencyIncoming.hunterMediumPacks += 60/30;
				}
			}
			
		}
		if (system.info.government > 1)
		{
			// heavy launch from Corp-Mult to Feud+Anar
			for (i=0;i<verylocals.length;i++)
			{
				local = verylocals[i];
				if (local.government <= 1)
				{
					// launch every 60, 2/3 return
					hheavy += 60/90;
					this.$repopulatorFrequencyOutgoing.hunterHeavyPacks += 1;
					this.$repopulatorFrequencyIncoming.hunterHeavyPacksReturn += 60/90;

				}
			}
		}
		else
		{
			// we're receiving them from nearby systems
			for (i=0;i<verylocals.length;i++)
			{
				local = verylocals[i];
				if (local.government > 1)
				{
					hheavy += 1;
					this.$repopulatorFrequencyIncoming.hunterHeavyPacks += 1;
				}
			}
		}
	}
	else
	{
		// no nearby systems. A very small number of medium and heavy
		// packs on local patrol
		hmedium = hlight / 3;
		hheavy = hlight / 10;
		this.$repopulatorFrequencyOutgoing.hunterMediumPacks = hmedium;
		this.$repopulatorFrequencyOutgoing.hunterHeavyPacks = hheavy;
		this.$repopulatorFrequencyIncoming.hunterMediumPacks = 0;
		this.$repopulatorFrequencyIncoming.hunterHeavyPacks = 0;
	}
	
	var hunters = hlight+hmedium+hheavy;
	
	/* Police patrols, also depend on trader+pirate numbers */

	var police = 60/(5*(8-system.info.government));
	if (police > traders + pirates)
	{
		police = traders + pirates;
	}
	police = police / 3;
	if (system.info.government <= 1)
	{
		// no police patrols away from the station - add more bounty
		// hunters instead
		hlight += police;
		hunters += police;
		this.$repopulatorFrequencyOutgoing.hunterLightPacks = hlight;
		police = 0;
	}
	/* high-tech systems will send interceptor wings out specifically
	 * to deal with incoming heavy pirate packs */
	var interceptors = 0;
	if (system.info.techlevel >= 9)
	{
		interceptors += pflightremote/2 + pfmediumremote + pfheavyremote*2;
	}

	this.$repopulatorFrequencyOutgoing.policePacks = police;
	this.$repopulatorFrequencyOutgoing.policeInterceptors = interceptors;

	/* Assassin numbers */
	var assassins = couriers*(Math.random()+Math.random());
	if (bottleneck)
	{
		assassins += couriers;
	}
	assassins = assassins * 2/(system.info.government+1);
	this.$repopulatorFrequencyOutgoing.assassins = assassins;

	/* Thargoid numbers */

	// more common in isolated systems with low hubcount
	var thargoids = this.$repopulatorFrequencyIncoming.thargoidScouts = 1/(locals.length+5);
	// larger strike forces try to disrupt bottleneck systems
	var thargoidstrike = this.$repopulatorFrequencyIncoming.thargoidStrikes = bottleneck ? 0.02 : 0;

	/* Current repopulator frequencies are in groups/hour. Need to
	 * convert to groups/20 seconds */

	k = Object.keys(this.$repopulatorFrequencyIncoming);
	for (i = 0 ; i < k.length ; i++)
	{
		this.$repopulatorFrequencyIncoming[k[i]] = this.$repopulatorFrequencyIncoming[k[i]] / 180;
		this._debugR("Incoming chance: "+k[i]+" = "+this.$repopulatorFrequencyIncoming[k[i]]);
	}
	k = Object.keys(this.$repopulatorFrequencyOutgoing);
	for (i = 0 ; i < k.length ; i++)
	{
		this.$repopulatorFrequencyOutgoing[k[i]] = this.$repopulatorFrequencyOutgoing[k[i]] / 180;
		this._debugR("Outgoing chance: "+k[i]+" = "+this.$repopulatorFrequencyOutgoing[k[i]]);
	}
	

	/* The repopulator frequencies are now set up */
	
	// route 1: witchpoint-planet
	var l1length = system.mainPlanet.position.magnitude();
	// route 2: sun-planet
	var l2length = system.mainPlanet.position.subtract(system.sun.position).magnitude();
	// route 3: witchpoint-sun
	var l3length = system.sun.position.magnitude();
	// triangle: circular patrol between three main points. 1/6 of
	// hunters, police go this way
	var trilength = l1length+l2length+l3length;
	
	this._debug("Routes: "+l1length+" , "+l2length+" , "+l3length);

	/* Calculate initial populations based on approximate attrition
	 * rates and lane lengths */

	function randomise(count)
	{
		count = count*(0.25+0.75*(Math.random()+Math.random()));
		var r = Math.floor(count);
		if (Math.random() < count-r)
		{
			r++;
		}
		return r;
	}

	// traders
	var initial = freighters * (l1length/600000);
	if (system.info.government < 4)
	{
		initial *= (1-0.15*(4-system.info.government));
	}
	system.setPopulator("oolite-freighters",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addFreighter.bind(this)
						});
	system.setPopulator("oolite-freighters-docking",
						{
							priority: 40,
							location: "STATION_AEGIS",
							groupCount: randomise(initial/10),
							callback: this._addFreighter.bind(this)
						});
	initial = couriers/2 * (l1length/600000);
	system.setPopulator("oolite-couriers-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addCourierShort.bind(this)
						});
	initial = couriers/2 * (l3length/600000);
	system.setPopulator("oolite-couriers-route3",
						{
							priority: 40,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addCourierLong.bind(this)
						});
	initial = smugglers * (l1length/600000);
	system.setPopulator("oolite-smugglers",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addSmuggler.bind(this)
						});

	// hunters
	// 5/6 go route 1, and back. 50% faster ships than traders, on average
	initial = hlight * 5/6 * (l1length*2 / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-hunters-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addLightHunter.bind(this)
						});
	initial = hlight * 1/6 * (trilength / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-hunters-triangle",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(initial),
							callback: this._addLightHunter.bind(this)
						});
	initial = hmedium * l1length/900000 * (2/3) * 2/3;
	system.setPopulator("oolite-hunters-medium-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addMediumHunterRemote.bind(this)
						});
	initial = hmedium * l3length/900000 * (2/3) * 1/3;
	system.setPopulator("oolite-hunters-medium-route3",
						{
							priority: 40,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addMediumHunterRemote.bind(this)
						});

	initial = hheavy * l1length/900000 * (2/3) * 2/3;
	system.setPopulator("oolite-hunters-heavy-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addHeavyHunterRemote.bind(this)
						});

	initial = hheavy * l3length/900000 * (2/3) * 1/3;
	system.setPopulator("oolite-hunters-heavy-route3",
						{
							priority: 40,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addHeavyHunterRemote.bind(this)
						});

	// pirates
	// 2/3 to lane 1 (with higher governmental attrition), 1/6 to each of other lanes
	initial = pindependents * ((l1length*2/3)/600000) * (1.0-0.05*system.info.government) * 5/6;
	system.setPopulator("oolite-pirate-independent-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addIndependentPirate.bind(this)
						});
	initial = pindependents * ((l2length*2/3)/600000) * (1.0-0.05*system.info.government) / 12;
	system.setPopulator("oolite-pirate-independent-route2",
						{
							priority: 40,
							location: "LANE_PS",
							groupCount: randomise(initial),
							callback: this._addIndependentPirate.bind(this)
						});
	initial = pindependents * ((l3length*2/3)/600000) * (1.0-0.05*system.info.government) / 12;
	system.setPopulator("oolite-pirate-independent-route3",
						{
							priority: 40,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addIndependentPirate.bind(this)
						});

	// pirate packs
	initial = pflight - pflightremote; // domestic source
	system.setPopulator("oolite-pirate-light-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial*3/4),
							callback: this._addLightPirateLocal.bind(this)
						});
	system.setPopulator("oolite-pirate-light-triangle",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(initial*1/4),
							callback: this._addLightPirateLocal.bind(this)
						});
	initial = pflightremote; // other system
	system.setPopulator("oolite-pirate-light-remote",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addLightPirateRemote.bind(this)
						});

	initial = pfmedium - pfmediumremote; // domestic source
	system.setPopulator("oolite-pirate-medium-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial*3/4),
							callback: this._addMediumPirateLocal.bind(this)
						});
	system.setPopulator("oolite-pirate-medium-triangle",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(initial*1/4),
							callback: this._addMediumPirateLocal.bind(this)
						});
	initial = pfmediumremote; // other system
	system.setPopulator("oolite-pirate-medium-remote",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addMediumPirateRemote.bind(this)
						});

	initial = pfheavy - pfheavyremote; // domestic source
	system.setPopulator("oolite-pirate-heavy-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial*3/4),
							callback: this._addHeavyPirateLocal.bind(this)
						});

	system.setPopulator("oolite-pirate-heavy-triangle",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(initial*1/4),
							callback: this._addHeavyPirateLocal.bind(this)
						});

	initial = pfheavyremote; // other system
	system.setPopulator("oolite-pirate-heavy-remote",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addHeavyPirateRemote.bind(this)
						});
	// assassins
	initial = assassins;
	if (system.info.government < 3)
	{
		// if carrying high-risk contracts through dangerous systems,
		// especially bottlenecks, add some more assassins
		// specifically waiting for the player
		var cs = player.ship.parcels;
		for (var i = cs.length-1; i >= 0 ; i--)
		{
			if (bottleneck)
			{
				if (cs[i].risk == 1 && Math.random() < 0.1)
				{
					initial++;
				} 
				if (cs[i].risk == 2 && Math.random() < 0.5)
				{
					initial++;
				}
			}
			else if (cs[i].destination == system.ID)
			{
				// if you're going to intercept, waiting in the
				// destination system for the package isn't a bad idea
				initial += Math.random()*cs[i].risk;
			}
		}
		cs = player.ship.passengers;
		for (i = cs.length-1; i >= 0 ; i--)
		{
			if (bottleneck)
			{
				if (cs[i].risk == 1 && Math.random() < 0.1)
				{
					initial++;
				} 
				if (cs[i].risk == 2 && Math.random() < 0.5)
				{
					initial++;
				}
			}
			else if (cs[i].destination == system.ID)
			{
				initial += Math.random()*cs[i].risk;
			}
		}
	}
	system.setPopulator("oolite-assassins",
						{
							priority: 40,
							location: "WITCHPOINT",
							groupCount: randomise(initial),
							callback: this._addAssassin.bind(this)
						});
	

	// police
	// 5/6 go route 1, and back. 
	initial = police * 5/6 * (l1length*2 / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-police-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addPolicePatrol.bind(this)
						});

	initial = police * 1/6 * (trilength / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-police-triangle",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(initial),
							callback: this._addPolicePatrol.bind(this)
						});
	system.setPopulator("oolite-police-stationpatrol",
						{
							priority: 40,
							location: "STATION_AEGIS",
							callback: this._addPoliceStationPatrol.bind(this)
						});
	

	// interceptors
	initial = interceptors / 2;
	// half on way or returning
	system.setPopulator("oolite-interceptors-route1",
						{
							priority: 40,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addInterceptors.bind(this)
						});

	// half on station
	system.setPopulator("oolite-interceptors-witchpoint",
						{
							priority: 40,
							location: "WITCHPOINT",
							groupCount: randomise(initial),
							callback: this._addInterceptors.bind(this)
						});

	// thargoids
	system.setPopulator("oolite-thargoid-scouts",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(thargoids),
							callback: this._addThargoidScout.bind(this)
						});

	system.setPopulator("oolite-thargoid-strike",
						{
							priority: 40,
							location: "LANE_WPS",
							groupCount: randomise(thargoidstrike),
							callback: this._addThargoidStrike.bind(this)
						});


	var pset = system.populatorSettings;
	this._debugP("Freighters",pset["oolite-freighters"].groupCount);
	this._debugP("Freighters (D)",pset["oolite-freighters-docking"].groupCount);
	this._debugP("Couriers (1)",pset["oolite-couriers-route1"].groupCount);
	this._debugP("Couriers (3)",pset["oolite-couriers-route3"].groupCount);
	this._debugP("Smugglers",pset["oolite-smugglers"].groupCount);
	this._debugP("Hunters (1)",pset["oolite-hunters-route1"].groupCount);
	this._debugP("Hunters (T)",pset["oolite-hunters-triangle"].groupCount);
	this._debugP("HuntersM (1)",pset["oolite-hunters-medium-route1"].groupCount);
	this._debugP("HuntersM (3)",pset["oolite-hunters-medium-route3"].groupCount);
	this._debugP("HuntersH (1)",pset["oolite-hunters-heavy-route1"].groupCount);
	this._debugP("HuntersH (3)",pset["oolite-hunters-heavy-route3"].groupCount);	
	this._debugP("Pirates (1)",pset["oolite-pirate-independent-route1"].groupCount);
	this._debugP("Pirates (2)",pset["oolite-pirate-independent-route2"].groupCount);
	this._debugP("Pirates (3)",pset["oolite-pirate-independent-route3"].groupCount);	
	this._debugP("Pirates (L1)",pset["oolite-pirate-light-route1"].groupCount);
	this._debugP("Pirates (LT)",pset["oolite-pirate-light-triangle"].groupCount);
	this._debugP("Pirates (LR)",pset["oolite-pirate-light-remote"].groupCount);
	this._debugP("Pirates (M1)",pset["oolite-pirate-medium-route1"].groupCount);
	this._debugP("Pirates (MT)",pset["oolite-pirate-medium-triangle"].groupCount);
	this._debugP("Pirates (MR)",pset["oolite-pirate-medium-remote"].groupCount);
	this._debugP("Pirates (H1)",pset["oolite-pirate-heavy-route1"].groupCount);
	this._debugP("Pirates (HT)",pset["oolite-pirate-heavy-triangle"].groupCount);
	this._debugP("Pirates (HR)",pset["oolite-pirate-heavy-remote"].groupCount);
	this._debugP("Assassins (WP)",pset["oolite-assassins"].groupCount);
	this._debugP("Police (1)",pset["oolite-police-route1"].groupCount);
	this._debugP("Police (T)",pset["oolite-police-triangle"].groupCount);
	this._debugP("Police (I1)",pset["oolite-interceptors-route1"].groupCount);
	this._debugP("Police (IW)",pset["oolite-interceptors-witchpoint"].groupCount);
	this._debugP("Thargoid (SC)",pset["oolite-thargoid-scouts"].groupCount);
	this._debugP("Thargoid (ST)",pset["oolite-thargoid-strike"].groupCount);

	// and the initial ships are done...

}


// function responsible for replenishing system contents
this.systemWillRepopulate = function()
{
	// if main station or planet is missing, something odd has
	// happened, so stop repopulation
	if (system.sun.isGoingNova || !system.mainStation || !system.mainPlanet)
	{
		return;
	}
	/* repopulate incoming traffic */

	// traders
	if (Math.random() < this.$repopulatorFrequencyIncoming.traderFreighters)
	{
		this._debugR("Incoming freighter");
		this._addFreighter(this._wormholePos());
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.traderCouriers)
	{
		this._debugR("Incoming courier");
		if (Math.random() < 0.5)
		{
			this._addCourierShort(this._wormholePos());
		}
		else
		{
			this._addCourierLong(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.traderSmugglers)
	{
		this._debugR("Incoming smuggler");
		this._addSmuggler(this._wormholePos());
	}

	// pirates
	if (Math.random() < this.$repopulatorFrequencyIncoming.pirateLightPacks)
	{
		if (system.countShipsWithPrimaryRole("pirate-light-freighter") < 6)
		{
			this._debugR("Incoming light pirate");
			this._addLightPirateRemote(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.pirateLightPacksReturn)
	{
		if (system.countShipsWithPrimaryRole("pirate-light-freighter") < 6)
		{
			this._debugR("Returning light pirate");
			this._addLightPirateReturn(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.pirateMediumPacks)
	{
		if (system.countShipsWithPrimaryRole("pirate-medium-freighter") < 4)
		{
			this._debugR("Incoming medium pirate");
			this._addMediumPirateRemote(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.pirateMediumPacksReturn)
	{
		if (system.countShipsWithPrimaryRole("pirate-medium-freighter") < 4)
		{
			this._debugR("Returning medium pirate");
			this._addMediumPirateReturn(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.pirateHeavyPacks)
	{
		if (system.countShipsWithPrimaryRole("pirate-heavy-freighter") < 2)
		{
			this._debugR("Incoming heavy pirate");
			this._addHeavyPirateRemote(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.pirateHeavyPacksReturn)
	{
		if (system.countShipsWithPrimaryRole("pirate-heavy-freighter") < 2)
		{
			this._debugR("Returning heavy pirate");
			this._addHeavyPirateReturn(this._wormholePos());
		}
	}

	// hunters
	if (Math.random() < this.$repopulatorFrequencyIncoming.hunterMediumPacks)
	{
		if (system.countShipsWithPrimaryRole("hunter-medium") < 5)
		{
			this._debugR("Incoming medium hunter");
			this._addMediumHunterRemote(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.hunterMediumPacksReturn)
	{
		if (system.countShipsWithPrimaryRole("hunter-medium") < 5)
		{
			this._debugR("Returning medium hunter");
			this._addMediumHunterReturn(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.hunterHeavyPacks)
	{
		if (system.countShipsWithPrimaryRole("hunter-heavy") < 3)
		{
			this._debugR("Incoming heavy hunter");
			this._addHeavyHunterRemote(this._wormholePos());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.hunterHeavyPacksReturn)
	{
		if (system.countShipsWithPrimaryRole("hunter-heavy") < 3)
		{
			this._debugR("Returning heavy hunter");
			this._addHeavyHunterReturn(this._wormholePos());
		}
	}

	// thargoids (do not appear at normal witchpoint)
	if (Math.random() < this.$repopulatorFrequencyIncoming.thargoidScouts)
	{
		this._debugR("Incoming thargoid scout");
		this._addThargoidScout(system.locationFromCode("TRIANGLE"));
	}
	if (Math.random() < this.$repopulatorFrequencyIncoming.thargoidStrike)
	{
		this._debugR("Incoming thargoid strike force");
		this._addThargoidStrike(system.locationFromCode("TRIANGLE"));
	}

	/* repopulate outgoing traffic */

	// traders
	if (Math.random() < this.$repopulatorFrequencyOutgoing.traderFreighters)
	{
		this._debugR("Launching freighter");
		this._addFreighter(this._tradeStation(true));
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.traderCouriers)
	{
		this._debugR("Launching courier");
		if (Math.random() < 0.5)
		{
			this._addCourierShort(this._tradeStation(true));
		}
		else
		{
			this._addCourierLong(this._tradeStation(true));
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.traderSmugglers)
	{
		this._debugR("Launching smuggler");
		this._addSmuggler(this._tradeStation(false));
	}

	// pirates
	if (Math.random() < this.$repopulatorFrequencyOutgoing.pirateIndependents)
	{
		if (system.countShipsWithPrimaryRole("pirate") < 40)
		{
			this._debugR("Launching pirates");
			this._addIndependentPirate(this._pirateLaunch());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.pirateLightPacks)
	{
		if (system.countShipsWithPrimaryRole("pirate-light-freighter") < 6)
		{
			this._debugR("Launching light pirate");
			if (Math.random() < 0.83) // light pirates rarely jump
			{
				this._addLightPirateLocal(this._pirateLaunch());
			}
			else
			{
				this._addLightPirateOutbound(this._pirateLaunch());
			}
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.pirateMediumPacks)
	{
		if (system.countShipsWithPrimaryRole("pirate-medium-freighter") < 4)
		{
			this._debugR("Launching medium pirate");
			if (Math.random() < 0.5)
			{
				this._addMediumPirateLocal(this._pirateLaunch());
			}
			else
			{
				this._addMediumPirateOutbound(this._pirateLaunch());
			}
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.pirateHeavyPacks)
	{
		if (system.countShipsWithPrimaryRole("pirate-heavy-freighter") < 2)
		{
			this._debugR("Launching heavy pirate");
			if (Math.random() < 0.5)
			{
				this._addHeavyPirateLocal(this._pirateLaunch());
			}
			else
			{
				this._addHeavyPirateOutbound(this._pirateLaunch());
			}
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.pirateAegisRaiders)
	{
		this._addAegisRaiders();
	}

	// hunters
	if (Math.random() < this.$repopulatorFrequencyOutgoing.hunterLightPacks)
	{
		if (system.countShipsWithPrimaryRole("hunter") < 30)
		{
			this._debugR("Launching light hunter");
			this._addLightHunter(this._hunterLaunch());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.hunterMediumPacks)
	{
		if (system.countShipsWithPrimaryRole("hunter-medium") < 6)
		{
			this._debugR("Launching medium hunter");
			// outbound falls back to local if no systems in range
			this._addMediumHunterOutbound(this._hunterLaunch());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.hunterHeavyPacks)
	{
		if (system.countShipsWithPrimaryRole("hunter-heavy") < 3)
		{
			this._debugR("Launching heavy hunter");
			// outbound falls back to local if no systems in range
			this._addHeavyHunterOutbound(this._hunterLaunch());
		}
	}
	
	// assassins
	if (Math.random() < this.$repopulatorFrequencyOutgoing.assassins)
	{
		if (system.countShipsWithPrimaryRole("assassin-medium")+system.countShipsWithPrimaryRole("assassin-heavy") < 30)
		{
			this._debugR("Launching assassin");
			this._addAssassin(this._tradeStation(false));
		}
	}

	// police
	if (Math.random() < this.$repopulatorFrequencyOutgoing.policePacks)
	{
		if (system.countShipsWithPrimaryRole("police") < 30)
		{
			this._debugR("Launching police patrol");
			this._addPolicePatrol(this._policeLaunch());
		}
	}
	if (Math.random() < this.$repopulatorFrequencyOutgoing.policeInterceptors)
	{
		if (system.countShipsWithPrimaryRole("police-witchpoint-patrol") < 30)
		{
			this._debugR("Launching police interception patrol");
			this._addInterceptors(this._policeLaunch());
		}
	}

	/* Generic traffic */
	if (Math.random() < 0.005 * system.info.techlevel)
	{
		// TODO: planet launches
		this._debugR("Launching shuttle");
		this._tradeStation(true).launchShuttle();
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

/* Ship addition functions */

/* These functions use this._addShips/_addGroup so "pos" can either be
 * a coordinate or a station, to simplify ship addition */

this._addFreighter = function(pos)
{
	var t = this._addShips("trader",1,pos,0);
	if (t[0])
	{
		var goods;
		if (pos.isStation)
		{
			t[0].homeSystem = system.ID;
			t[0].destinationSystem = this._weightedNearbyTradeSystem();
			goods = "PLENTIFUL_GOODS";
		}
		else
		{
			t[0].homeSystem = this._weightedNearbyTradeSystem();
			this._setFuel(t[0]);
			t[0].destinationSystem = system.ID;
			goods = "SCARCE_GOODS";
			if (Math.random()*8 > system.info.government)
			{
				// may have used some missiles already
				this._setMissiles(t[0],-1);
			}
		}
		// crude, but compatible with the approach in previous versions
		// and now translatable
		if (t[0].name.match(this.$medicalReg)) 
		{
			goods = "MEDICAL_GOODS";
			t[0].bounty = 0;
		}
		else
		{
			// medical ships always clean
			if (Math.random() < 0.05)
			{
				t[0].bounty = Math.ceil(Math.random()*20);
				// half of the offender traders are a bit more sinister
				if (Math.random() < 0.5)
				{
					t[0].switchAI("oolite-traderOpportunistAI.js");
					goods = "PIRATE_GOODS";
				} 
				var eg = t[0].escortGroup.ships;
				for (var i = 0; i < eg.length; i++)
				{
					if (eg[i] != t[0])
					{
						// ensure offender escorts have a bounty
						eg[i].bounty |= 3+Math.floor(Math.random()*12);
					}
				}
			}
			else
			{
				t[0].bounty = 0;
			}
		}
		t[0].setCargoType(goods);

		this._setEscortWeapons(t[0]);
	}
}


this._addCourier = function(pos)
{
	if (this._roleExists("trader-courier"))
	{
		var t = this._addShips("trader-courier",1,pos,0);
	}
	else
	{
		var t = this._addShips("trader",1,pos,0);
	}
	t[0].bounty = 0;
	t[0].heatInsulation = 6;
	if (t.escortGroup)
	{
		var gs = t.escortGroup.ships;
		for (var i=gs.length=1; i>=0; i++)
		{
			gs[i].heatInsulation = 6;
			gs[i].bounty = 0;
		}
	}
	this._setEscortWeapons(t[0]);
	return t;
}


this._addCourierShort = function(pos)
{
	var t = this._addCourier(pos);
	if (t[0])
	{
		// don't need to worry at this stage where it came from before that
		if (pos.isStation)
		{
			t[0].destinationSystem = this._nearbySystem(7);
			t[0].homeSystem = system.ID;
			t[0].setCargoType("PLENTIFUL_GOODS");
		}
		else
		{
			t[0].homeSystem = this._nearbySystem(7);
			this._setFuel(t[0]);
			t[0].destinationSystem = system.ID;
			t[0].setCargoType("SCARCE_GOODS");
		}
	}
}


this._addCourierLong = function(pos)
{
	var t = this._addCourier(pos);
	if (t[0])
	{
		if (pos.isStation)
		{
			t[0].destinationSystem = this._nearbySystem(25);
			t[0].homeSystem = system.ID;
			t[0].setCargoType("PLENTIFUL_GOODS");
		}
		else
		{
			// don't need to worry at this stage where it came from before that
			t[0].homeSystem = this._nearbySystem(7);
			this._setFuel(t[0]);
			t[0].destinationSystem = this._nearbySystem(25);
			t[0].setCargoType("SCARCE_GOODS");
		}
	}
}


this._addSmuggler = function(pos)
{
	if (this._roleExists("trader-smuggler"))
	{
		var t = this._addShips("trader-smuggler",1,pos,0);
	}
	else
	{
		var t = this._addShips("trader",1,pos,0);
	}
	if (t[0])
	{
		t[0].bounty = Math.ceil(Math.random()*20);
		if (t[0].bounty > t[0].cargoSpaceCapacity * 2)
		{
			t[0].bounty = t[0].cargoSpaceCapacity * 2;
		}
		if (pos.isStation)
		{
			t[0].destinationSystem = this._nearbySystem(7);
			t[0].homeSystem = system.ID;
		}
		else
		{
			t[0].homeSystem = this._nearbySystem(7);
			this._setFuel(t[0]);
			t[0].destinationSystem = system.ID;
		}
		t[0].setCargoType("ILLEGAL_GOODS");
		if (t[0].autoWeapons)
		{
			t[0].awardEquipment("EQ_FUEL_INJECTION"); // smugglers always have injectors
		}
		this._setWeapons(t[0],1.2); // rarely good weapons
		this._setEscortWeapons(t[0]);
		var eg = t[0].escortGroup.ships;
		for (var i = 0; i < eg.length; i++)
		{
			if (eg[i] != t[0])
			{
				// ensure smuggler escorts have a bounty
				eg[i].bounty |= 3+Math.floor(Math.random()*12);
			}
		}

	}
}


this._addLightHunter = function(pos)
{
	var h = this._addGroup("hunter",Math.floor(Math.random()*2)+Math.floor(Math.random()*2)+2,pos,2E3);
	for (var i = 0 ; i < h.ships.length ; i++)
	{
		h.ships[i].bounty = 0;
		h.ships[i].homeSystem = system.ID;
		h.ships[i].destinationSystem = system.ID;
		this._setWeapons(h.ships[i],1.5); // mixed weapons
		this._setSkill(h.ships[i],-1); // if they were any good, they'd have signed on with a proper hunting pack
	}
}


this._addMediumHunterRemote = function(pos)
{
	this._addHunterPack(pos,this._nearbySafeSystem(2),system.ID,"hunter-medium",false);
}


this._addMediumHunterReturn = function(pos)
{
	this._addHunterPack(pos,system.ID,this._nearbyDangerousSystem(1),"hunter-medium",true);
}


this._addMediumHunterOutbound = function(pos)
{
	this._addHunterPack(pos,system.ID,this._nearbyDangerousSystem(1),"hunter-medium",false);
}


this._addHeavyHunterRemote = function(pos)
{
	this._addHunterPack(pos,this._nearbySafeSystem(2),system.ID,"hunter-heavy",false);
}


this._addHeavyHunterReturn = function(pos)
{
	this._addHunterPack(pos,system.ID,this._nearbyDangerousSystem(1),"hunter-heavy",true);
}

this._addHeavyHunterOutbound = function(pos)
{
	this._addHunterPack(pos,system.ID,this._nearbyDangerousSystem(1),"hunter-heavy",false);
}


this._addHunterPack = function(pos,home,dest,role,returning)
{
	if (this._roleExists(role))
	{
		var t = this._addShips(role,1,pos,0);
	}
	else
	{
		var t = this._addShips("hunter",1,pos,0);
	}
	if (t[0])
	{
		t[0].bounty = 0;
		t[0].homeSystem = home;
		if (returning)
		{
			this._setMissiles(t[0],-1);
			this._setReturnFuel(t[0]);
		}
		else
		{
			this._setFuel(t[0]);
		}

		t[0].destinationSystem = dest;
		
		var group = new ShipGroup("hunter group",t[0]);
		t[0].group = group;

		var hs = this._addShips("hunter",1+Math.floor(Math.random()*4)+Math.floor(Math.random()*4),pos,3E3);
		for (var i = 0; i<hs.length; i++)
		{
			hs[i].group = group;
			group.addShip(hs[i]);
			hs[i].bounty = 0;
			hs[i].fuel = 7;
			hs[i].homeSystem = t[0].homeSystem;
			hs[i].destinationSystem = t[0].destinationSystem;
			this._setWeapons(hs[i],1.5); // mixed weapons
			if (returning)
			{
				this._setMissiles(hs[i],-1);
			}
		}
		if (role == "hunter-heavy")
		{
			// occasionally give heavy hunters aft lasers
			this._setWeapons(t[0],2.2);
		}
		else
		{
			// usually ensure medium hunters have beam lasers
			this._setWeapons(t[0],1.9);
		}
		this._setSkill(t[0],3); // likely to be good pilot
		t[0].switchAI("oolite-bountyHunterLeaderAI.js");
	}
}


this._addIndependentPirate = function(pos)
{
	// a group < 3 in size is probably too small to actually attack anyone
	// mostly 2-6 groups
	var size = Math.floor(Math.random()*3)+Math.floor(Math.random()*3)+2;
	if (size > 8-system.info.government)
	{
		// in the safer systems may have lost some ships already, though
		size = 1+Math.floor(Math.random()*size);
	}
	var pg = this._addGroup("pirate",size,pos,2.5E3);
	for (var i=0;i<size;i++)
	{
		pg.ships[i].setBounty(20+system.info.government+size+Math.floor(Math.random()*8),"setup actions");
		if (!pos.isStation && !pos.isPlanet)
		{
			pg.ships[i].setCargoType("PIRATE_GOODS");
			if (pg.ships[i].hasHyperspaceMotor)
			{
				this._setWeapons(pg.ships[i],1.75); // bigger ones sometimes well-armed
			}
			else
			{
				this._setWeapons(pg.ships[i],1.3); // rarely well-armed
			}
			// in the safer systems, rarely highly skilled (the
			// skilled ones go elsewhere)
			this._setSkill(pg.ships[i],4-system.info.government);
			if (pos.z) // not if freshly launching
			{
				if (Math.random()*16 < system.info.government)
				{
					this._setMissiles(pg.ships[i],-1);
				}
			}
		}
	}
}


this._addPirateAssistant = function(role,lead,pos)
{
	if (this._roleExists(role))
	{
		var asst = this._addShips(role,1,pos,4E3);
	}
	else
	{
		var asst = this._addShips("pirate",1,pos,4E3);
	}
	asst[0].homeSystem = lead.homeSystem;
	asst[0].destinationSystem = lead.destinationSystem;
	if (role == "pirate-interceptor")
	{
		asst[0].switchAI("oolite-pirateInterceptorAI.js");
		asst[0].setBounty(50+system.government+Math.floor(Math.random()*36),"setup actions");
		// interceptors not actually part of group: they just get the
		// same destinations
		this._setWeapons(asst[0],2.3); // heavily armed
		if (asst[0].autoWeapons)
		{
			asst[0].awardEquipment("EQ_FUEL_INJECTION"); // interceptors always have injectors
		}
	}
	else
	{ 
		asst[0].group = lead.group;
		lead.group.addShip(asst[0]);
		asst[0].switchAI("oolite-pirateFighterAI.js");
		asst[0].setBounty(20+system.government+Math.floor(Math.random()*12),"setup actions");
		if (role == "pirate-light-fighter")
		{
			this._setWeapons(asst[0],1.2); // basic fighters
		}
		else if (role == "pirate-medium-fighter")
		{
			this._setWeapons(asst[0],1.8); // often beam weapons
		}
		else if (role == "pirate-heavy-fighter")
		{
			this._setWeapons(asst[0],2.05); // very rarely aft lasers
		}
	}
}


this._addPiratePack = function(pos,leader,lf,mf,hf,thug,home,destination,returning)
{
	if (this._roleExists(leader))
	{
		var lead = this._addShips(leader,1,pos,0);		
	}
	else
	{
		log(this.name,"Tried to add "+leader+" but no ships of that role found");
		var lead = this._addShips("pirate",1,pos,0);		
	}
	lead[0].setBounty(60+system.government+Math.floor(Math.random()*8),"setup actions");
	lead[0].homeSystem = home;
	lead[0].destinationSystem = destination;

	var group = new ShipGroup("pirate pack",lead[0]);
	lead[0].group = group;
	for (var i = Math.floor(lf+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-light-fighter",lead[0],pos);
	}
	for (var i = Math.floor(mf+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-medium-fighter",lead[0],pos);
	}
	for (var i = Math.floor(hf+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-heavy-fighter",lead[0],pos);
	}
	for (var i = Math.floor(thug+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-interceptor",lead[0],pos);
	}
	if (lead[0].autoWeapons)
	{
		lead[0].awardEquipment("EQ_SHIELD_BOOSTER");
		lead[0].awardEquipment("EQ_ECM");
	}
	this._setWeapons(lead[0],2.8); // usually give aft laser
	this._setSkill(lead[0],3); // likely to be good pilot
	if (returning)
	{
		this._setMissiles(lead[0],-1);
		this._setReturnFuel(lead[0]);
	}
	else
	{
		if (thug > 0)
		{
			// medium and especially heavy may have better missiles
			this._setMissiles(lead[0],thug-0.5);
		}
		this._setFuel(lead[0]);
	}
	if (lead[0].escortGroup)
	{
		var eg = lead[0].escortGroup.ships;
		for (var i = 0; i < eg.length; i++)
		{
			if (eg[i] != lead[0])
			{
				// ensure freighter escorts have a bounty
				eg[i].bounty |= 3+Math.floor(Math.random()*12);
			}
		}
	}
	if (!pos.isStation && !pos.isPlanet)
	{
		lead[0].setCargoType("PIRATE_GOODS");
	}
	this._setEscortWeapons(lead[0]);
	lead[0].switchAI("oolite-pirateFreighterAI.js");
	return lead[0];
}

this._addLightPirateLocal = function(pos)
{
	return this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,system.ID,system.ID,false);
}


this._addLightPirateRemote = function(pos)
{
	pos.z = pos.z % 100000;
	return this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,this._nearbyDangerousSystem(system.info.government-1),system.ID,false);
}



this._addLightPirateOutbound = function(pos)
{
	return this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,system.ID,this._nearbySafeSystem(system.info.government+1),false);
}


this._addLightPirateReturn = function(pos)
{
	return this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,system.ID,this._nearbySafeSystem(system.info.government+1),true);
}


this._addMediumPirateLocal = function(pos)
{
	return this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,system.ID,system.ID,false);
}


this._addMediumPirateRemote = function(pos)
{
	pos.z = pos.z % 100000;
	return this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,this._nearbyDangerousSystem(Math.min(system.info.government-1,3)),system.ID,false);
}

// tmp for testing (needs adjusting to simulate planetary launch *or*
// use a suitable friendly station)
this._addMediumPirateOutbound = function(pos)
{
	return this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,system.ID,this._nearbySafeSystem(system.info.government+1),false);
}


this._addMediumPirateReturn = function(pos)
{
	return this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,system.ID,this._nearbySafeSystem(system.info.government+1),true);
}


this._addHeavyPirateLocal = function(pos)
{
	return this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,system.ID,system.ID,false);
}


this._addHeavyPirateRemote = function(pos)
{
	pos.z = pos.z % 100000;
	return this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,this._nearbyDangerousSystem(Math.min(system.info.government-1,1)),system.ID,false);
}


// tmp for testing (needs adjusting to simulate planetary launch *or*
// use a suitable friendly station)
this._addHeavyPirateOutbound = function(pos)
{
	return this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,system.ID,this._nearbySafeSystem(system.info.government+1),false);
}


this._addHeavyPirateReturn = function(pos)
{
	return this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,system.ID,this._nearbySafeSystem(system.info.government+1),true);
}


this._addAegisRaiders = function()
{
	var g = this._addGroup("pirate-aegis-raider",3+Math.floor(Math.random()*5),system.mainPlanet,3E3);
	var gs = g.ships;
	for (var i=0; i < gs.length ; i++)
	{
		gs[i].setBounty(50+system.government+Math.floor(Math.random()*36),"setup actions")
		this._setWeapons(gs[i],2.7); // very heavily armed
		this._setSkill(gs[i],3); // boost combat skill
		if (gs[i].autoWeapons)
		{
			// raiders need the best equipment
			gs[i].awardEquipment("EQ_FUEL_INJECTION"); 
			gs[i].awardEquipment("EQ_SHIELD_BOOSTER"); 
			gs[i].awardEquipment("EQ_ECM"); 
			gs[i].fuel = 7;
		}
	}
}


this._addAssassin = function(pos)
{
	var role = "assassin-light";
	var extra = 0;
	var ws = 2;
	var g = system.info.government+2;
	if (Math.random() > g / 10)
	{
		role = "assassin-medium";
		extra = 1;
		ws = 2.5;
		if (Math.random() > g / 5)
		{
			role = "assassin-heavy";
			ws = 2.8;
		}
	}
	var main = this._addShips(role,1,pos,0)[0];
	if (main.autoWeapons)
	{
		main.awardEquipment("EQ_FUEL_INJECTION");
		main.awardEquipment("EQ_ECM");
		if (2+Math.random() < ws)
		{
			main.awardEquipment("EQ_SHIELD_BOOSTER"); 
		}
		main.fuel = 7;
		this._setWeapons(main,ws);
		this._setSkill(main,extra);
	}
	//	main.bounty = 1+Math.floor(Math.random()*10);
	main.switchAI("oolite-assassinAI.js");
	if (extra > 0)
	{
		var g = new ShipGroup("assassin group",main);
		main.group = g;
		if (role == "assassin-heavy")
		{
			var extras = this._addShips("assassin-medium",2,pos,3E3);
		}
		else
		{
			var extras = this._addShips("assassin-light",2,pos,3E3);
		}
		for (var i=0;i<2;i++)
		{
			extras[i].group = g;
			g.addShip(extras[i]);
			if (extras[i].autoWeapons)
			{
				extras[i].awardEquipment("EQ_FUEL_INJECTION");
				extras[i].fuel = 7;
				this._setWeapons(extras[i],1.8);
			}
			//			extras[i].bounty = 1+Math.floor(Math.random()*5);
			extras[i].switchAI("oolite-assassinAI.js");
		}
	}
}


this._addPolicePatrol = function(pos)
{
	var role = "police";
	if (9+Math.random()*6 < system.info.techlevel)
	{
		role = "interceptor";
	}
	var h = this._addGroup(role,Math.floor(Math.random()*2)+Math.floor(Math.random()*2)+2,pos,2E3);
	for (var i = 0 ; i < h.ships.length ; i++)
	{
		h.ships[i].bounty = 0;
		h.ships[i].homeSystem = system.ID;
		h.ships[i].destinationSystem = system.ID;
		if (h.ships[i].AIScript.oolite_intership)
		{
			h.ships[i].AIScript.oolite_intership.initial_group = h.ships.length;
		}
		if (system.info.techlevel >= 14)
		{
			this._setMissiles(h.ships[i],1);
		}

	}
}


this._addPoliceStationPatrol = function(pos)
{
	var role = "police";
	if (9+Math.random()*6 < system.info.techlevel)
	{
		role = "interceptor";
	}
	var p = system.addShips(role,1,pos,0)[0];
	p.primaryRole = "police-station-patrol";
	p.group = system.mainStation.group;
	p.group.addShip(p);
	p.switchAI("oolite-policeAI.js");
	p.bounty = 0;
	p.maxEscorts = 16;
	if (system.info.techlevel >= 14)
	{
		this._setMissiles(p,1);
	}

}


this._addInterceptors = function(pos)
{
	var h = this._addGroup("interceptor",Math.floor(Math.random()*2)+Math.floor(Math.random()*2)+1+Math.ceil(system.info.techlevel/6),pos,2E3);
	for (var i = 0 ; i < h.ships.length ; i++)
	{
		h.ships[i].bounty = 0;
		h.ships[i].primaryRole = "police-witchpoint-patrol";
		h.ships[i].maxEscorts = 16;
		h.ships[i].homeSystem = system.ID;
		h.ships[i].destinationSystem = system.ID;
		h.ships[i].switchAI("oolite-policeAI.js");
		// only +1 as core already gives police ships better AI
		this._setSkill(h.ships[i],1);

		if (system.info.techlevel >= 14)
		{
			this._setMissiles(h.ships[i],1);
		}
	}
}


this._addThargoidScout = function(pos)
{
	this._addShips("thargoid",1,pos,0);
}


this._addThargoidStrike = function(pos)
{
	var thargs = this._addShips("thargoid",Math.floor(5+Math.random()*4),pos,10E3);
	for (var i = 0; i < thargs.length ; i++)
	{
		// raiding parties have better pilots
		this._setSkill(thargs[i],1);
	}
}

/* Utility functions */

this._debug = function(msg)
{
	log("universe.populate.information",msg);
}


this._debugP = function(gtype,ct)
{
	log("universe.populate.information",gtype+": "+ct);
}


this._debugR = function(msg)
{
	log("universe.populate.repopulate",msg);
}


this._roleExists = function(role)
{
	if (Ship.keysForRole(role) && Ship.keysForRole(role).length > 0)
	{
		return true;
	}
	return false;
}


/* Run _setWeapons on the escort group */
this._setEscortWeapons = function(mothership)
{
	if (!mothership.escortGroup)
	{
		return;
	}
	var eg = mothership.escortGroup.ships;
	for (var i = eg.length-1 ; i >= 0 ; i--)
	{
		var ship = eg[i];
		if (ship == mothership)
		{
			continue;
		}
		if (!ship.autoWeapons)
		{
			continue;
		}
		var pr = ship.primaryRole;
		if (pr == "escort" || pr == "pirate-light-fighter")
		{
			this._setWeapons(ship,1.3); // usually lightly armed as escorts
		}
		else if (pr == "escort-medium" || pr == "pirate-medium-fighter")
		{
			this._setWeapons(ship,1.8); // usually heavily armed as escorts
		}
		else if (pr == "escort-heavy" || pr == "pirate-heavy-fighter")
		{
			this._setWeapons(ship,2.05); // rarely have an aft laser
		}
	}
}


/* Levels:
 * <= 1: FP
 *    2: FB
 *    3: FB, AB (rare in core)
 *    4: FM, AB (not used in core)
 * >= 5: FM, AM (not used in core)
 * Fractional levels may be one or other (e.g. 2.2 = 80% 2, 20% 3)
 * Side weapons unchanged
 */
this._setWeapons = function(ship,level)
{
	if (!ship.autoWeapons)
	{
		// default is not to change anything
		return false;
	}
	var fwent = ship;
	if (ship.forwardWeapon == null)
	{
		var se = ship.subEntities;
		for (var i=0;i<se.length;i++)
		{
			if (se[i].forwardWeapon != null)
			{
				if (fwent != ship)
				{
					return false; // auto_weapons doesn't work on ships with MFLs
				}
				fwent = se[i];
			}
		}
	}
	var choice = Math.floor(level);
	if (level-Math.floor(level) > Math.random())
	{
		choice++;
	}
	if (choice <= 1)
	{
		fwent.forwardWeapon = "EQ_WEAPON_PULSE_LASER";
		ship.aftWeapon = null;
	}
	else if (choice == 2)
	{
		fwent.forwardWeapon = "EQ_WEAPON_BEAM_LASER";
		ship.aftWeapon = null;
	}
	else if (choice == 3)
	{
		fwent.forwardWeapon = "EQ_WEAPON_BEAM_LASER";
		ship.aftWeapon = "EQ_WEAPON_BEAM_LASER";
	}
	else if (choice == 4)
	{
		fwent.forwardWeapon = "EQ_WEAPON_MILITARY_LASER";
		ship.aftWeapon = "EQ_WEAPON_BEAM_LASER";
	}
	else if (choice >= 5)
	{
		fwent.forwardWeapon = "EQ_WEAPON_MILITARY_LASER";
		ship.aftWeapon = "EQ_WEAPON_MILITARY_LASER";
	}
	//	log(this.name,"Set "+fwent.forwardWeapon+"/"+ship.aftWeapon+" for "+ship.name+" ("+ship.primaryRole+")");
	return true;
}


this._setSkill = function(ship,bias)
{
	if (ship.autoWeapons && ship.accuracy < 5 && bias != 0)
	{
		// shift skill towards end of accuracy range
		var target = 4.99;
		if (bias < 0)
		{
			target = -5;
		}
		var acc = ship.accuracy;
		for (var i=Math.abs(bias) ; i > 0 ; i--)
		{
			acc += (target-acc)*Math.random();
		}
		ship.accuracy = acc;
	}
}


/* Bias:
 * +N = N 50% chances that each normal missile converted to hardened
 * -N = N 50% chances that each normal missile removed
 */
this._setMissiles = function(ship,bias)
{
	if (ship.autoWeapons)
	{
		var chance = Math.pow(0.5,Math.abs(bias));
		for (var i = ship.missiles.length -1 ; i >= 0 ; i--)
		{
			if (ship.missiles[i].primaryRole == "EQ_MISSILE" && chance < Math.random())
			{
				ship.removeEquipment("EQ_MISSILE");
				if (bias > 0)
				{
					ship.awardEquipment("EQ_HARDENED_MISSILE");
				}
			}
		}

	}
}


this._setFuel = function(ship)
{
	if (ship.homeSystem != system.ID)
	{
		ship.fuel = 7-system.info.distanceToSystem(System.infoForSystem(galaxyNumber,ship.homeSystem));
	}
	else 
	{
		ship.fuel = 7;
	}
}


this._setReturnFuel = function(ship)
{
	if (ship.destinationSystem != system.ID)
	{
		ship.fuel = 7-system.info.distanceToSystem(System.infoForSystem(galaxyNumber,ship.destinationSystem));
	}
	else 
	{
		ship.fuel = 7;
	}
}


this._wormholePos = function()
{
	var v = Vector3D.randomDirection().multiply(2000+Math.random()*3000);
	if (v.z < 0 && v.x+v.y < 500)
	{
		v.z = -v.z; // avoid collision risk with witchbuoy
	}
	return v;
}


this._addShips = function(role,num,pos,spread)
{
	if (pos.isStation)
	{
		var result = [];
		for (var i = 0 ; i < num ; i++)
		{
			result.push(pos.launchShipWithRole(role));
		}
		return result;
	}
	else if (pos.isPlanet)
	{
		var result = system.addShips(role,num,pos,spread);
		this._repositionForLaunch(pos,result);
		return result;
	}
	else
	{
		if (pos.z === undefined)
		{
			log(this.name,"Unexpected populator position "+pos+" for "+role+". Please report this error.");
		}
		return system.addShips(role,num,pos,spread);
	}
}

this._addGroup = function(role,num,pos,spread)
{
	if (pos.isStation)
	{
		var group = new ShipGroup;
		for (var i = 0 ; i < num ; i++)
		{
			var ship = pos.launchShipWithRole(role);
			ship.group = group;
			group.addShip(ship);
		}
		return group;
	}
	else if (pos.isPlanet)
	{
		var result = system.addGroup(role,num,pos,spread);
		this._repositionForLaunch(pos,result.ships);
		return result;
	}
	else
	{
		return system.addGroup(role,num,pos,spread);
	}
}


this._repositionForLaunch = function(planet,ships)
{
	var launchvector;
	var launchpos;
	if (planet != system.mainPlanet)
	{
		launchvector = Vector3D.randomDirection();
	}
	else
	{
		if (system.sun.position.subtract(planet.position).dot(system.mainStation.position.subtract(planet.position)) < 0)
		{
			// sun and station on opposite sides of planet; best sneak
			// vector probably the cross product
			launchvector = system.sun.position.subtract(planet.position).cross(system.mainStation.position.subtract(planet.position)).direction();
		}
		else
		{
			// sun and station on same side of planet; best sneak
			// vector probably the negative normalisation of the
			// average
			launchvector = system.sun.position.subtract(planet.position).direction().add(system.mainStation.position.subtract(planet.position).direction()).direction().multiply(-1);
		}
	}
	launchpos = planet.position.add(launchvector.multiply(planet.radius+125));
	for (var i=ships.length -1 ; i >= 0 ; i--)
	{
		var cross = launchvector.cross(Vector3D.randomDirection()).multiply(15000); // perpendicular to surface
		launchvector = launchpos.add(cross).direction();
		launchpos = planet.position.add(launchvector.multiply(planet.radius+250));
		ships[i].position = launchpos;
		ships[i].orientation = launchvector.rotationTo([0, 0, 1]);
		ships[i].velocity = ships[i].vectorForward.multiply(ships[i].maxSpeed);
	}
}


this._hermitAllegiance = function(position,government)
{
	// default hermit status, allows all dockings but pirates will tend to
	// go elsewhere. We set this in shipdata but a shipset might not
	var allegiance = "neutral"; 
	if ((Math.floor(Math.abs(position.z)) % 4) * (Math.floor(Math.abs(position.y)) % 4) > government)
	{
		// pirates will use this hermit for docking and launching, but
		// other ships might too
		allegiance = "chaotic"; 
		if (Math.abs(Math.floor(position.x) % 4) > government+1)
		{
			// in Feudal or Anarchy systems, some of the hermits are
			// so pirate-friendly that legitimate traffic avoids them
			allegiance = "pirate";
		}
	}
	return allegiance;
}

/* System selectors */

this._nearbySystem = function(range)
{
	var poss = this.$populatorLocals;
	if (poss.length == 0)
	{
		return system.ID;
	}
	return poss[Math.floor(Math.random()*poss.length)].systemID;
}


this._nearbyDangerousSystem = function(gov)
{
	var poss = this.$populatorVeryLocals;
	var id = system.ID;
	if (poss.length > 0)
	{
		var found = 0;
		for (var i = 0 ; i < poss.length ; i++)
		{
			if (poss[i].government <= gov)
			{
				found++;
				if (Math.random() < 1/found)
				{
					id = poss[i].systemID;
				}
			}
		}
	}
	return id;
}


this._nearbySafeSystem = function(gov)
{
	var poss = this.$populatorVeryLocals;
	var id = system.ID;
	if (poss.length > 0)
	{
		var found = 0;
		for (var i = 0 ; i < poss.length ; i++)
		{
			if (poss[i].government >= gov)
			{
				found++;
				if (Math.random() < 1/found)
				{
					id = poss[i].systemID;
				}
			}
		}
	}
	return id;
}


this._systemIsBottleneck = function(locals,seconds)
{
	if (locals.length > 0)
	{
		// Oresrati's bottleneck status is undefined. The Thargoids
		// don't bother striking at it routinely.
		var connectionset = [locals[0].systemID];
		var sofar = 0;
		do 
		{
			sofar = connectionset.length;
			for (var j = 0; j < seconds.length ; j++)
			{
				// if the connected set doesn't already contain this system
				if (connectionset.indexOf(locals[j].systemID) == -1)
				{
					var second = seconds[j];
					for (var k = 0; k < second.length ; k++)
					{
						// if the connected set contains a system
						// connected to the system being tested
						if (connectionset.indexOf(second[k].systemID) > -1)
						{
							// add this system to the connection set
							connectionset.push(locals[j].systemID);
							break;
						}
					}
				}
			}
		} 
		while (connectionset.length > sofar);
		// if we didn't add any more, we've connected all we can.
		if (connectionset.length < locals.length)
		{
			// there are still some disconnected, so this is a
			// bottleneck system
			return true;
		}
	}
	return false;
}


this._weightedNearbyTradeSystem = function()
{
	var locals = this.$populatorLocals;
	var weights = [];
	var total = 0;
	for (var i = 0; i < locals.length ; i++)
	{
		var local = locals[i];
		var ecomatch = -(system.info.economy-3.5)*(local.economy-3.5);
		var trdanger = 0;
		var rate = 0;
		// if either local or remote end is more dangerous than
		// Communist, reduce trader frequency
		if (local.government < 4)
		{
			trdanger = (4-local.government)*2.5;
		}
		if (system.info.government < 4)
		{
			trdanger += (4-system.info.government)*2.5;
		}
		if (ecomatch > 0)
		{
			rate = 60/(30+trdanger);
		}
		// bad economic match: one every 2 hours if safe
		else
		{
			rate = 60/(120+(trdanger*2));
		}
		total += rate;
		weights[i] = rate;
	}
	var pick = 0;
	total *= Math.random();
	for (i = 0; i < locals.length ; i++)
	{
		pick += weights[i];
		if (pick >= total)
		{
			return locals[i].systemID;
		}
	}
	// fallback
	return system.ID;
}

/* Station selectors */

// station for launching traders
this._tradeStation = function(usemain)
{
	// usemain biases, but does not guarantee or forbid
	if (usemain && Math.random() < 0.67)
	{
		return system.mainStation;
	}
	var stats = system.stations;
	var stat = system.stations[Math.floor(Math.random()*stats.length)];
	if (stat.hasNPCTraffic)
	{
		if (stat.allegiance == "neutral" || stat.allegiance == "galcop" || stat.allegiance == "chaotic")
		{
			return stat;
		}
	}
	return system.mainStation;
}

// station for launching pirates (or planet)
this._pirateLaunch = function()
{
	var stats = system.stations;
	var stat = system.stations[Math.floor(Math.random()*stats.length)];
	if (stat.hasNPCTraffic)
	{
		if (stat.allegiance == "pirate" || stat.allegiance == "chaotic")
		{
			return stat;
		}
	}
	return system.mainPlanet;
}


// station for launching hunters
this._hunterLaunch = function()
{
	var stats = system.stations;
	var stat = system.stations[Math.floor(Math.random()*stats.length)];
	if (stat.hasNPCTraffic)
	{
		if (stat.allegiance == "hunter" || stat.allegiance == "galcop")
		{
			return stat;
		}
	}
	return system.mainStation;
}


// station for launching police
this._policeLaunch = function()
{
	var stats = system.stations;
	var stat = system.stations[Math.floor(Math.random()*stats.length)];
	if (stat.hasNPCTraffic)
	{
		if (stat.allegiance == "galcop")
		{
			return stat;
		}
	}
	return system.mainStation;
}
