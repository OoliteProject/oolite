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
							priority: 1,
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
							priority: 2,
							location: "COORDINATES",
							coordinates: [0,0,0],
							callback: function(pos) {
								var wb = system.addShips("buoy-witchpoint",1,pos,0)[0];
								wb.scanClass = "CLASS_BUOY";
								wb.reactToAIMessage("START_TUMBLING");
							},
							deterministic: true
						});


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

	/* Calculate trader hourly rates first, as most other rates depend
	 * on them */
	var freighters = 0; // standard trade ships
	var couriers = 0; // fast parcel couriers or big passenger liners
	var smugglers = 0; // small fast illegal goods traders

	this.$repopulatorFrequencyIncoming.traderFreighters = {};
	this.$repopulatorFrequencyIncoming.traderCouriers = {};
	this.$repopulatorFrequencyIncoming.traderSmugglers = {};
	this.$repopulatorFrequencyOutgoing.traderFreighters = {};

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
		
		this.$repopulatorFrequencyIncoming.traderFreighters[locals[i].systemID] = rate;
		this.$repopulatorFrequencyOutgoing.traderFreighters[locals[i].systemID] = rate;
		freighters += rate;

		second = seconds[i];
		// couriers are non-mirrored
		rate = (60/(10+((14-local.techlevel)*5)))/second.length;
		this.$repopulatorFrequencyIncoming.traderCouriers[locals[i].systemID] = rate;
		couriers += rate;
		// smugglers are non-mirrored
		rate = (60/(10+(local.techlevel*5)))/second.length;
		this.$repopulatorFrequencyIncoming.traderSmugglers[locals[i].systemID] = rate;
		smugglers += rate;
	}
	// and outgoing rates for smugglers/couriers. Don't need to
	// specify destination since all rates are equal
	rate = 60/(10+((14-system.info.techlevel)*5));
	this.$repopulatorFrequencyOutgoing.traderCouriers = rate;
	rate = (60/(10+(system.info.techlevel*5)))/locals.length;
	this.$repopulatorFrequencyOutgoing.traderSmugglers = rate;

	var traders = freighters+couriers+smugglers;
	
	/* Pirate rates next, based partly on trader rates */

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
	if (system.info.government < 6)
	{
		pflight += lrate;
		if (system.info.government < 4)
		{
			pflight += lrate;
			pfmedium += mrate;
			if (system.info.government < 2)
			{
				pflight += lrate*2;
				pfmedium += mrate;
				pfheavy += hrate;
				if (system.info.government < 1)
				{
					pflight *= 1.5;
					pfmedium *= 1.5;
					pfheavy *= 2;
				}
			}
		}
	}
	this.$repopulatorFrequencyOutgoing.pirateIndependents = pindependents;
	this.$repopulatorFrequencyOutgoing.pirateLightPacks = pflight;
	this.$repopulatorFrequencyOutgoing.pirateMediumPacks = pfmedium;
	this.$repopulatorFrequencyOutgoing.pirateHeavyPacks = pfheavy;
	this.$repopulatorFrequencyIncoming.pirateLightPacks = {};
	this.$repopulatorFrequencyIncoming.pirateMediumPacks = {};
	this.$repopulatorFrequencyIncoming.pirateHeavyPacks = {};
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
				this.$repopulatorFrequencyIncoming.pirateLightPacks[local.systemID] = rlight;
				this.$repopulatorFrequencyIncoming.pirateMediumPacks[local.systemID] = rmedium;
				this.$repopulatorFrequencyIncoming.pirateHeavyPacks[local.systemID] = rheavy;
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
		this.$repopulatorFrequencyIncoming.hunterMediumPacks = {};
		this.$repopulatorFrequencyIncoming.hunterHeavyPacks = {};
	}
	
	var hunters = hlight+hmedium+hheavy;
	
	/* Police patrols, also depend on trader+pirate numbers */

	var police = 60/(5*(8-system.info.government));
	if (police > traders + pirates)
	{
		police = traders + pirates;
	}
	police = police / 3;
	/* high-tech systems will send interceptor wings out specifically
	 * to deal with incoming heavy pirate packs */
	var interceptors = 0;
	if (system.info.techlevel >= 9)
	{
		interceptors += pflightremote/2 + pfmediumremote + pfheavyremote*2;
	}

	this.$repopulatorFrequencyOutgoing.PolicePacks = police;
	this.$repopulatorFrequencyOutgoing.PoliceInterceptors = interceptors;
	
	// more common in isolated systems with low hubcount
	var thargoids = this.$repopulatorFrequencyIncoming.thargoidScouts = 1/(locals.length+5);
	// larger strike forces try to disrupt bottleneck systems
	var thargoidstrike = this.$repopulatorFrequencyIncoming.thargoidStrikes = 0;
	if (locals.length > 0)
	{
		// Oresrati's bottleneck status is undefined. The Thargoids
		// don't bother striking at it routinely.
		var connectionset = [locals[0].systemID];
		var sofar = 0;
		do 
		{
			sofar = connectionset.length;
			for (j = 0; j < seconds.length ; j++)
			{
				// if the connected set doesn't already contain this system
				if (connectionset.indexOf(locals[j].systemID) == -1)
				{
					var second = seconds[j];
					for (k = 0; k < second.length ; k++)
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
			thargoidstrike = this.$repopulatorFrequencyIncoming.thargoidStrikes = 0.02;
		}
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
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addFreighter.bind(this)
						});
	system.setPopulator("oolite-freighters-docking",
						{
							priority: 10,
							location: "STATION_AEGIS",
							groupCount: randomise(initial/10),
							callback: this._addFreighter.bind(this)
						});
	initial = couriers/2 * (l1length/600000);
	system.setPopulator("oolite-couriers-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addCourierShort.bind(this)
						});
	initial = couriers/2 * (l3length/600000);
	system.setPopulator("oolite-couriers-route3",
						{
							priority: 10,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addCourierLong.bind(this)
						});
	initial = smugglers * (l1length/600000);
	system.setPopulator("oolite-smugglers",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addSmuggler.bind(this)
						});

	// hunters
	// 5/6 go route 1, and back. 50% faster ships than traders, on average
	initial = hlight * 5/6 * (l1length*2 / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-hunters-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addLightHunter.bind(this)
						});
	initial = hlight * 1/6 * (trilength / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-hunters-triangle",
						{
							priority: 10,
							location: "LANE_WPS",
							groupCount: randomise(initial),
							callback: this._addLightHunter.bind(this)
						});
	initial = hmedium * l1length/900000 * (2/3) * 2/3;
	system.setPopulator("oolite-hunters-medium-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addMediumHunterRemote.bind(this)
						});
	initial = hmedium * l3length/900000 * (2/3) * 1/3;
	system.setPopulator("oolite-hunters-medium-route3",
						{
							priority: 10,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addMediumHunterRemote.bind(this)
						});

	initial = hheavy * l1length/900000 * (2/3) * 2/3;
	system.setPopulator("oolite-hunters-heavy-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addHeavyHunterRemote.bind(this)
						});

	initial = hheavy * l3length/900000 * (2/3) * 1/3;
	system.setPopulator("oolite-hunters-heavy-route3",
						{
							priority: 10,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addHeavyHunterRemote.bind(this)
						});

	// pirates
	// 2/3 to lane 1 (with higher governmental attrition), 1/6 to each of other lanes
	initial = pindependents * ((l1length*2/3)/600000) * (1.0-0.1*system.info.government) * 2/3;
	system.setPopulator("oolite-pirate-independent-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addIndependentPirate.bind(this)
						});
	initial = pindependents * ((l2length*2/3)/600000) * (1.0-0.05*system.info.government) / 6;
	system.setPopulator("oolite-pirate-independent-route2",
						{
							priority: 10,
							location: "LANE_PS",
							groupCount: randomise(initial),
							callback: this._addIndependentPirate.bind(this)
						});
	initial = pindependents * ((l3length*2/3)/600000) * (1.0-0.05*system.info.government) / 6;
	system.setPopulator("oolite-pirate-independent-route3",
						{
							priority: 10,
							location: "LANE_WS",
							groupCount: randomise(initial),
							callback: this._addIndependentPirate.bind(this)
						});

	// pirate packs
	initial = pflight - pflightremote; // domestic source
	system.setPopulator("oolite-pirate-light-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial*3/4),
							callback: this._addLightPirateLocal.bind(this)
						});
	system.setPopulator("oolite-pirate-light-triangle",
						{
							priority: 10,
							location: "LANE_WPS",
							groupCount: randomise(initial*1/4),
							callback: this._addLightPirateLocal.bind(this)
						});
	initial = pflightremote; // other system
	system.setPopulator("oolite-pirate-light-remote",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addLightPirateRemote.bind(this)
						});

	initial = pfmedium - pfmediumremote; // domestic source
	system.setPopulator("oolite-pirate-medium-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial*3/4),
							callback: this._addMediumPirateLocal.bind(this)
						});
	system.setPopulator("oolite-pirate-medium-triangle",
						{
							priority: 10,
							location: "LANE_WPS",
							groupCount: randomise(initial*1/4),
							callback: this._addMediumPirateLocal.bind(this)
						});
	initial = pfmediumremote; // other system
	system.setPopulator("oolite-pirate-medium-remote",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addMediumPirateRemote.bind(this)
						});

	initial = pfheavy - pfheavyremote; // domestic source
	system.setPopulator("oolite-pirate-heavy-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial*3/4),
							callback: this._addHeavyPirateLocal.bind(this)
						});

	system.setPopulator("oolite-pirate-heavy-triangle",
						{
							priority: 10,
							location: "LANE_WPS",
							groupCount: randomise(initial*1/4),
							callback: this._addHeavyPirateLocal.bind(this)
						});

	initial = pfheavyremote; // other system
	system.setPopulator("oolite-pirate-heavy-remote",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addHeavyPirateRemote.bind(this)
						});

	// police
	// 5/6 go route 1, and back. 
	initial = police * 5/6 * (l1length*2 / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-police-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addPolicePatrol.bind(this)
						});

	initial = police * 1/6 * (trilength / 900000) * (1.0-0.1*(7-system.info.government));
	system.setPopulator("oolite-police-triangle",
						{
							priority: 10,
							location: "LANE_WPS",
							groupCount: randomise(initial),
							callback: this._addPolicePatrol.bind(this)
						});

	// interceptors
	initial = interceptors / 2;
	// half on way or returning
	system.setPopulator("oolite-interceptors-route1",
						{
							priority: 10,
							location: "LANE_WP",
							groupCount: randomise(initial),
							callback: this._addInterceptors.bind(this)
						});

	// half on station
	system.setPopulator("oolite-interceptors-witchpoint",
						{
							priority: 10,
							location: "WITCHPOINT",
							groupCount: randomise(initial),
							callback: this._addInterceptors.bind(this)
						});

	// thargoids
	system.setPopulator("oolite-thargoid-scouts",
						{
							priority: 10,
							location: "LANE_WPS",
							groupCount: randomise(thargoids),
							callback: this._addThargoidScout.bind(this)
						});

	system.setPopulator("oolite-thargoid-strike",
						{
							priority: 10,
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
	this._debugP("Police (1)",pset["oolite-police-route1"].groupCount);
	this._debugP("Police (T)",pset["oolite-police-triangle"].groupCount);
	this._debugP("Police (I1)",pset["oolite-interceptors-route1"].groupCount);
	this._debugP("Police (IW)",pset["oolite-interceptors-witchpoint"].groupCount);
	this._debugP("Thargoid (SC)",pset["oolite-thargoid-scouts"].groupCount);
	this._debugP("Thargoid (ST)",pset["oolite-thargoid-strike"].groupCount);








	// and the initial ships are done...
	
	/* Add asteroids */
	var clusters = 2*(1+Math.floor(system.scrambledPseudoRandomNumber(51728)*4));
	var psclusters = 1+(clusters/2);
	clusters = clusters-psclusters;
	
	var addRockCluster = function(pos) 
	{
		var size = 1+Math.floor(system.scrambledPseudoRandomNumber(Math.floor(pos.x))*11);
		var hermit = (system.scrambledPseudoRandomNumber(Math.floor(pos.y))*31) <= size;
		var rocks = system.addShips("asteroid",size,pos,25E3);
		if (hermit) 
		{
			var rh = system.addShips("rockhermit",1,pos,0)[0];
			rh.scanClass = "CLASS_ROCK";
		}
	}

	system.setPopulator("oolite-route1-asteroids",
						{
							priority: 10,
							location: "LANE_WP",
							locationSeed: 51728,
							groupCount: clusters,
							callback: addRockCluster,
							deterministic: true
						});
	system.setPopulator("oolite-route2-asteroids",
						{
							priority: 10,
							location: "LANE_PS",
							locationSeed: 82715,
							groupCount: psclusters,
							callback: addRockCluster,
							deterministic: true
						});
	/* To ensure there's at least one hermit, for pirates to dock at */
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

	// TODO

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

this._addFreighter = function(pos)
{
	var t = system.addShips("trader",1,pos,0);
	if (t[0])
	{
		if (Math.random() < 0.1)
		{
			t[0].bounty = Math.ceil(Math.random()*20);
/*			if (Math.random() < 0.5)
			{
				t[0].switchAI("opportunistAI.js");
			} */ // TODO: this AI
		}
		else
		{
			t[0].bounty = 0;
		}
		t[0].homeSystem = this._weightedNearbyTradeSystem();
		this._setFuel(t[0]);
		t[0].destinationSystem = system.ID;
		t[0].setCargoType("SCARCE_GOODS");
	}
}


this._addCourier = function(pos)
{
	if (this._roleExists("trader-courier"))
	{
		var t = system.addShips("trader-courier",1,pos,0);
	}
	else
	{
		var t = system.addShips("trader",1,pos,0);
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
	return t;
}


this._addCourierShort = function(pos)
{
	var t = this._addCourier(pos);
	if (t[0])
	{
		// don't need to worry at this stage where it came from before that
		t[0].homeSystem = this._nearbySystem(7);
		this._setFuel(t[0]);
		t[0].destinationSystem = system.ID;
		t[0].setCargoType("SCARCE_GOODS");
	}
}


this._addCourierLong = function(pos)
{
	var t = this._addCourier(pos);
	if (t[0])
	{
		// don't need to worry at this stage where it came from before that
		t[0].homeSystem = this._nearbySystem(7);
		this._setFuel(t[0]);
		t[0].destinationSystem = this._nearbySystem(25);
		t[0].setCargoType("SCARCE_GOODS");
	}
}


this._addSmuggler = function(pos)
{
	if (this._roleExists("trader-smuggler"))
	{
		var t = system.addShips("trader-smuggler",1,pos,0);
	}
	else
	{
		var t = system.addShips("trader",1,pos,0);
	}
	if (t[0])
	{
		t[0].bounty = Math.ceil(Math.random()*20);
		t[0].homeSystem = this._nearbySystem(7);
		this._setFuel(t[0]);
		t[0].destinationSystem = system.ID;
		t[0].setCargoType("ILLEGAL_GOODS");
		t[0].awardEquipment("EQ_FUEL_INJECTION"); // smugglers always have injectors
	}
}


this._addLightHunter = function(pos)
{
	var h = system.addGroup("hunter",Math.floor(Math.random()*2)+Math.floor(Math.random()*2)+2,pos,2E3);
	for (var i = 0 ; i < h.ships.length ; i++)
	{
		h.ships[i].bounty = 0;
		h.ships[i].homeSystem = system.ID;
		h.ships[i].destinationSystem = system.ID;
		h.ships[i].AIScript.oolite_intership.initial_group = h.ships.length;
	}
}


this._addMediumHunterLocal = function(pos)
{
	this._addHunterPack(pos,system.ID,system.ID,"hunter-heavy");
}


this._addMediumHunterRemote = function(pos)
{
	this._addHunterPack(pos,this._nearbySafeSystem(2),system.ID,"hunter-heavy");
}


// tmp for testing
this._addMediumHunterOutbound = function(pos)
{
	this._addHunterPack(pos,system.ID,this._nearbyDangerousSystem(1),"hunter-medium");
}


this._addHeavyHunterLocal = function(pos)
{
	this._addHunterPack(pos,system.ID,system.ID,"hunter-medium");
}


this._addHeavyHunterRemote = function(pos)
{
	this._addHunterPack(pos,this._nearbySafeSystem(2),system.ID,"hunter-medium");
}


// tmp for testing
this._addHeavyHunterOutbound = function(pos)
{
	this._addHunterPack(pos,system.ID,this._nearbyDangerousSystem(1),"hunter-heavy");
}


this._addHunterPack = function(pos,home,dest,role)
{
	if (this._roleExists(role))
	{
		var t = system.addShips(role,1,pos,0);
	}
	else
	{
		var t = system.addShips("hunter",1,pos,0);
	}
	if (t[0])
	{
		t[0].bounty = 0;
		t[0].homeSystem = home;
		this._setFuel(t[0]);
		t[0].destinationSystem = dest;
		
		var group = new ShipGroup("hunter group",t[0]);
		t[0].group = group;

		var hs = system.addShips("hunter",1+Math.floor(Math.random()*4)+Math.floor(Math.random()*4),pos,3E3);
		for (var i = 0; i<hs.length; i++)
		{
			hs[i].group = group;
			group.addShip(hs[i]);
			hs[i].bounty = 0;
			hs[i].fuel = 7;
			hs[i].homeSystem = t[0].homeSystem;
			hs[i].destinationSystem = t[0].destinationSystem;
		}
		t[0].switchAI("bountyHunterLeaderAI.js");
	}
}


this._addIndependentPirate = function(pos)
{
	var size = Math.floor(Math.random()*3)+Math.floor(Math.random()*3)+1;
	if (size > 8-system.government)
	{
		size = 1+Math.floor(Math.random()*size);
	}
	var pg = system.addGroup("pirate",size,pos,2.5E3);
	for (var i=0;i<pg.ships.length;i++)
	{
		pg.ships[i].setBounty(20+system.government+size+Math.floor(Math.random()*8),"setup actions");
	}
}


this._addPirateAssistant = function(role,lead)
{
	if (this._roleExists(role))
	{
		var asst = system.addShips(role,1,lead.position,4E3);
	}
	else
	{
		var asst = system.addShips("pirate",1,lead.position,4E3);
	}
	asst[0].homeSystem = lead.homeSystem;
	asst[0].destinationSystem = lead.destinationSystem;
	if (role == "pirate-interceptor")
	{
		asst[0].switchAI("pirateInterceptorAI.js");
		asst[0].setBounty(50+system.government+Math.floor(Math.random()*36),"setup actions");
		// interceptors not actually part of group: they just get the
		// same destinations
	}
	else
	{ 
		asst[0].group = lead.group;
		lead.group.addShip(asst[0]);
		asst[0].switchAI("pirateFighterAI.js");
		asst[0].setBounty(20+system.government+Math.floor(Math.random()*12),"setup actions");
	}
}


this._addPiratePack = function(pos,leader,lf,mf,hf,thug,home,destination)
{
	if (this._roleExists(leader))
	{
		var lead = system.addShips(leader,1,pos,0);		
	}
	else
	{
		log(this.name,"Tried to add "+leader+" but no ships of that role found");
		var lead = system.addShips("pirate",1,pos,0);		
	}
	lead[0].setBounty(60+system.government+Math.floor(Math.random()*8),"setup actions");
	lead[0].homeSystem = home;
	lead[0].destinationSystem = destination;

	var group = new ShipGroup("pirate pack",lead[0]);
	lead[0].group = group;
	for (var i = Math.floor(lf+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-light-fighter",lead[0]);
	}
	for (var i = Math.floor(mf+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-medium-fighter",lead[0]);
	}
	for (var i = Math.floor(hf+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-heavy-fighter",lead[0]);
	}
	for (var i = Math.floor(thug+(0.5+Math.random()-Math.random())); i > 0; i--)
	{
		this._addPirateAssistant("pirate-interceptor",lead[0]);
	}
	lead[0].awardEquipment("EQ_SHIELD_BOOSTER");
	lead[0].awardEquipment("EQ_ECM");
	if (lead[0].aftWeapon != "EQ_WEAPON_MILITARY_LASER")
	{
		lead[0].aftWeapon = "EQ_WEAPON_BEAM_LASER";
	}
	if (lead[0].forwardWeapon != "EQ_WEAPON_MILITARY_LASER")
	{
		lead[0].forwardWeapon = "EQ_WEAPON_BEAM_LASER";
	}
	// next line is temporary for debugging!
	lead[0].displayName = lead[0].name + " - FLAGSHIP";
	this._setFuel(lead[0]);
	lead[0].switchAI("pirateFreighterAI.js");
	return lead[0];
}

this._addLightPirateLocal = function(pos)
{
	var lead = this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,system.ID,system.ID);
}


this._addLightPirateRemote = function(pos)
{
	pos.z = pos.z % 100000;
	var lead = this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,this._nearbyDangerousSystem(system.info.government-1),system.ID);
}


// tmp for testing (needs adjusting to simulate planetary launch *or*
// use a suitable friendly station)
this._addLightPirateOutbound = function(pos)
{
	var lead = this._addPiratePack(pos,"pirate-light-freighter",2,1,-1,0,system.ID,this._nearbySafeSystem(system.info.government+1));
}


this._addMediumPirateLocal = function(pos)
{
	var lead = this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,system.ID,system.ID);
}


this._addMediumPirateRemote = function(pos)
{
	pos.z = pos.z % 100000;
	var lead = this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,this._nearbyDangerousSystem(Math.min(system.info.government-1,3)),system.ID);
}

// tmp for testing (needs adjusting to simulate planetary launch *or*
// use a suitable friendly station)
this._addMediumPirateOutbound = function(pos)
{
	var lead = this._addPiratePack(pos,"pirate-medium-freighter",3,2,0,1,system.ID,this._nearbySafeSystem(system.info.government+1));
}


this._addHeavyPirateLocal = function(pos)
{
	var lead = this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,system.ID,system.ID);
}


this._addHeavyPirateRemote = function(pos)
{
	pos.z = pos.z % 100000;
	var lead = this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,this._nearbyDangerousSystem(Math.min(system.info.government-1,1)),system.ID);
}


// tmp for testing (needs adjusting to simulate planetary launch *or*
// use a suitable friendly station)
this._addHeavyPirateOutbound = function(pos)
{
	var lead = this._addPiratePack(pos,"pirate-heavy-freighter",4,4,2,2,system.ID,this._nearbySafeSystem(system.info.government+1));
}


this._addPolicePatrol = function(pos)
{
	var role = "police";
	if (9+Math.random()*6 < system.info.techLevel)
	{
		role = "interceptor";
	}
	var h = system.addGroup(role,Math.floor(Math.random()*2)+Math.floor(Math.random()*2)+2,pos,2E3);
	for (var i = 0 ; i < h.ships.length ; i++)
	{
		h.ships[i].bounty = 0;
		h.ships[i].homeSystem = system.ID;
		h.ships[i].destinationSystem = system.ID;
		h.ships[i].AIScript.oolite_intership.initial_group = h.ships.length;
	}
}


this._addInterceptors = function(pos)
{
	var h = system.addGroup("interceptor",Math.floor(Math.random()*2)+Math.floor(Math.random()*2)+1+Math.ceil(system.info.techlevel/6),pos,2E3);
	for (var i = 0 ; i < h.ships.length ; i++)
	{
		h.ships[i].bounty = 0;
		// h.ships[i].switchAI("policeWitchpointPatrolAI.js");
		h.ships[i].homeSystem = system.ID;
		h.ships[i].destinationSystem = system.ID;
		h.ships[i].AIScript.oolite_intership.initial_group = h.ships.length;
	}
}


this._addThargoidScout = function(pos)
{
	system.addShips("thargoid",1,pos,0);
}


this._addThargoidStrike = function(pos)
{
	system.addShips("thargoid",Math.floor(5+Math.random()*4),pos,10E3);
}

/* Utility functions */

this._debug = function(msg)
{
	log("universe.populator.information",msg);
}

this._debugP = function(gtype,ct)
{
	log("universe.populator.information",gtype+": "+ct);
}


this._roleExists = function(role)
{
	if (Ship.keysForRole(role) && Ship.keysForRole(role).length > 0)
	{
		return true;
	}
	return false;
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
	if (poss.length > 0)
	{
		var found = 0;
		var id = system.ID
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
	if (poss.length > 0)
	{
		var found = 0;
		var id = system.ID
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