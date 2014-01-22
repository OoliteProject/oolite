/*

	oolite-priorityai.js

	Priority-based Javascript AI library


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

"use strict";

/* AI Library */
this.name = "oolite-libPriorityAI";
this.version = "1.79";
this.copyright		= "© 2008-2013 the Oolite team.";
this.author = "cim";


/* Constructor */

this.PriorityAIController = function(ship)
{
	// the ship property must be read-only
	Object.defineProperty(this,	"ship", {
		value: ship,
		writable: false,
		enumerable: true,
		configurable: true
	});

	this.__cache = {}; // short-term cache
	this.__ltcache = {}; // long-term cache
	this.__ltcachestart = clock.adjustedSeconds+60;
	this.scannerRange = this.ship.scannerRange; // cached
	this.ship.AIScript.oolite_intership = {};
	this.ship.AIScript.oolite_priorityai = this;
	var activeHandlers = [];
	var handlerCache = {};
	var priorityList = null;
	var parameters = {};
	var lastCommSent = 0;
	var lastCommHeard = 0;
	var commsRole = "generic";
	var commsPersonality = "generic";
	var waypointgenerator = null;
	this.playerRole = this.playerRoleAssessment();
	
	/* Cache variables used by utility functions */
	var condmet = true;

	/* Private utility functions. Cannot be called from external code */

	// event handlers which must not be overridden
	function _handlerAIAwoken()
	{
		if (this.ship)
		{
			_reconsider.call(this);
		}
	}


	function _handlerShipDied()
	{
		this.cleanup();
	}


	/* Considers a priority list, potentially recursively */
	function _reconsiderList(priorities) {
		var logging = this.getParameter("oolite_flag_behaviourLogging");
		var pl = priorities.length;
		if (pl == 0)
		{
			log(this.name,"AI '"+this.ship.AIScript.name+"' for ship "+this.ship+" had a branch with no entries. This may be caused by a template function not being executed during priority set up.");
		}
		if (logging)
		{
			log(this.ship.name,"Considering branch with "+pl+" entries");
		}
		for (var i = 0; i < pl; i++)
		{
			if (logging)
			{
				if (priorities[i].label) 
				{
					log(this.ship.name,"Considering: "+priorities[i].label);
				}
				else
				{
					log(this.ship.name,"Considering: entry "+i);
				}
			}
			// always call the preconfiguration function at this point
			// to set up condition parameters
			if (priorities[i].preconfiguration)
			{
				priorities[i].preconfiguration.call(this);
			}
			// allow inverted conditions
			condmet = true;
			if (priorities[i].notcondition)
			{
				 condmet = !priorities[i].notcondition.call(this);
			}
			else if (priorities[i].condition)
			{
				condmet = priorities[i].condition.call(this);
			}
			// absent condition is always true
			if (condmet)
			{
				if (logging)
				{
					log(this.ship.name,"Conditions met");
				}

				// always call the configuration function at this point
				if (priorities[i].configuration)
				{
					priorities[i].configuration.call(this);
				}
				// this is what we're doing
				if (priorities[i].behaviour) 
				{
					if (logging)
					{
						log(this.ship.name,"Executing behaviour");
					}

					if (priorities[i].reconsider) 
					{
						_resetReconsideration.call(this,priorities[i].reconsider);
					}
					return priorities[i].behaviour;
				}
				// otherwise this is what we might be doing
				if (priorities[i].truebranch)
				{
					if (logging)
					{
						log(this.ship.name,"Entering truebranch");
					}

					var branch = _reconsiderList.call(this,priorities[i].truebranch);
					if (branch != null)
					{
						return branch;
					}
					// otherwise nothing in the branch was usable, so move on
				}
			}
			else
			{
				if (priorities[i].falsebranch)
				{
					if (logging)
					{
						log(this.ship.name,"Entering falsebranch");
					}

					var branch = _reconsiderList.call(this,priorities[i].falsebranch);
					if (branch != null)
					{
						return branch;
					}
					// otherwise nothing in the branch was usable, so move on
				}
			}
		}
		if (this.getParameter(logging))
		{
			log(this.ship.name,"Exiting branch");
		}

		return null; // nothing in the list is usable, so return
	};


	/* Only call this from aiAwoken to avoid loops */
	function _reconsider() {
		if (!this.ship || !this.ship.isValid || !this.ship.isInSpace)
		{
			return;
		}
		this.__cache = {}; // clear short-term cache
		// maybe clear long-term cache
		if (this.__ltcachestart < clock.adjustedSeconds)
		{
			this.__ltcache = {};
			this.__ltcachestart = clock.adjustedSeconds + 60;
		}
		if (!this.__ltcache.oolite_nearestStation)
		{
			this.__ltcache.oolite_nearestStation = this.ship.findNearestStation();
		}
		var newBehaviour = _reconsiderList.call(this,priorityList);
		if (newBehaviour == null) {
			log(this.name,"AI '"+this.ship.AIScript.name+"' for ship "+this.ship+" had all priorities fail. All priority based AIs should end with an unconditional entry.");
			return false;
		}

		if (this.getParameter("oolite_flag_behaviourLogging"))
		{
			log(this.ship.name,newBehaviour);
		}
		newBehaviour.call(this);
		return true;
	};


	/* Resets the reconsideration timer. (Can't make it later) */
	function _resetReconsideration(delay)
	{
		if (this.ship)
		{
			var newwake = clock.adjustedSeconds + delay;
			if (this.ship.AIScriptWakeTime > newwake || this.ship.AIScriptWakeTime == 0)
			{
				this.ship.AIScriptWakeTime = newwake;
			}
		}
	};


	/* ****************** General AI functions. ************** */
	
	/* These privileged functions interface with the private functions
	 * and variables. Do not override them. */

	/* The simple implementation of this function requires a lot of
	 * creation and destruction of function objects, which aggravates
	 * the garbage collector. We avoid this where possible by keeping
	 * a cache (pre-binding) of the handler objects, and only
	 * replacing those which have changed. This requires the functions
	 * to be stored where possible as this. variables (or
	 * this.prototype. variables) */
	this.applyHandlers = function(handlers)
	{
		/* This handler must always exist for a priority AI, and must
		 * be set here. */
		handlers.aiAwoken = _handlerAIAwoken;
		/* This handler must always exist for a priority AI, and must
		 * be set here. */
		handlers.shipDied = _handlerShipDied;

		// step 1: go through activeHandlers, and delete those
		// functions from this.ship.AIScript that aren't in the new
		// handler list
		for (var i=activeHandlers.length-1; i >= 0 ; i--)
		{
			if (handlerCache[activeHandlers[i]] != handlers[activeHandlers[i]])
			{
				delete this.ship.AIScript[activeHandlers[i]];
				delete handlerCache[activeHandlers[i]];
			}
		}

		// step 2: go through the keys in handlers and put those handlers
		// into this.ship.AIScript and the keys into activeHandlers
		activeHandlers = Object.keys(handlers);
		for (var i=activeHandlers.length-1; i >= 0 ; i--)
		{
			// unset or not deleted in step 1
			if (!this.ship.AIScript[activeHandlers[i]])
			{
				handlerCache[activeHandlers[i]] = handlers[activeHandlers[i]];
				if(handlers[activeHandlers[i]])
				{
					this.ship.AIScript[activeHandlers[i]] = handlers[activeHandlers[i]].bind(this);
				}
				else
				{
					log(this.name,"AI '"+this.ship.AIScript.name+"' for ship "+this.ship+" had an invalid entry for handler "+activeHandlers[i]+". Skipped.");
				}
			}
		}

	}


	/* Do not call this directly. It is called automatically on ship death. Deliberately not documented. */
	this.cleanup = function()
	{
		// break links to disconnect this from GC roots a little sooner
		delete this.ship.AIScript.oolite_priorityai;
		this.applyHandlers({});
		this.ship.AIScriptWakeTime = 0;
		delete this.ship.AIScript.aiAwoken;
		Object.defineProperty(this,	"ship", {
			value: ship,
			writable: true,
			enumerable: true,
			configurable: true
		});
		delete this.ship;
		delete this.parameters; // might contain entities
	}


	this.clearHandlers = function()
	{
		// delete all handlers to allow rebinding
		activeHandlers = Object.keys(handlerCache);
		for (var i=0; i < activeHandlers.length ; i++)
		{
			delete this.ship.AIScript[activeHandlers[i]];
		}
		handlerCache = {};
		delete this.ship.AIScript.aiAwoken;
		delete this.ship.AIScript.shipDied;
	}


	this.communicate = function(key,params,priority)
	{
		if (!worldScripts["oolite-libPriorityAI"].$commsAllowed)
		{
			// comms temporarily disabled
			return;
		}
		if (priority > 1)
		{
			var send = clock.adjustedSeconds - lastCommSent;
			if (priority == 2)
			{
				if (send < 10)
				{
					return;
				}
			}
			else
			{
				var recv = clock.adjustedSeconds - lastCommHeard;
				if (priority == 3)
				{
					if (recv < 10 || send < 10)
					{
						return;
					}
				}
				else
				{
					if (recv < 60 || send < 60)
					{
						return;
					}
				}
			}
		}
		var template = worldScripts["oolite-libPriorityAI"]._getCommunication(commsRole,commsPersonality,key);
		if (template != "")
		{
			if (params && params.isShip)
			{
				params = this.entityCommsParams(params);
			}
			if (template instanceof Function)
			{
				var message = template(key,params);
			}
			else
			{
				var message = expandDescription(template,params);
			}
			if (message != "")
			{
				this.ship.commsMessage(message);
				lastCommSent = clock.adjustedSeconds;
			}
			else
			{
				// this is for debugging: ordinarily this is legitimate
//				log(this.name,"Empty message for "+key);
			}
		}
	}


	this.getParameter = function(key)
	{
		if (key in parameters)
		{
			return parameters[key];
		}
		return null;
	}


	this.getWaypointGenerator = function()
	{
		return waypointgenerator;
	}


	this.noteCommsHeard = function()
	{
		lastCommHeard = clock.adjustedSeconds;
	}


	/* Requests reconsideration of behaviour ahead of schedule. */
	this.reconsiderNow = function() 
	{
		_resetReconsideration.call(this,0.1);
	}


	this.reconsiderIn = function(delta)
	{
		if (delta >= 0.1)
		{
			_resetReconsideration.call(this,delta);
		}
	}


	this.setCommunicationsRole = function(role)
	{
		commsRole = role;
		// TODO: if personality is generic, pick a new one from the
		// allowed list. If possible use the same as the group leader.
	}


	this.setCommunicationsPersonality = function(personality)
	{
		commsPersonality = personality;
	}

	// parameters created by Oolite must always be prefixed oolite_
	this.setParameter = function(key, value)
	{
		parameters[key] = value;
	}

	this.setPriorities = function(priorities,delay) 
	{
		priorityList = priorities;
		this.clearHandlers();
		this.applyHandlers({});
		if (delay && delay > 0)
		{
			_resetReconsideration.call(this,delay);
		}
		else
		{
			_resetReconsideration.call(this,Math.random());
		}
	}


	// set the waypoint generator function
	this.setWaypointGenerator = function(value)
	{
		waypointgenerator = value;
	}


}; // end object constructor

/* Object prototype */
PriorityAIController.prototype.constructor = PriorityAIController;
PriorityAIController.prototype.name = this.name;

/* ****************** AI utility functions. ************** */

/* These functions provide standard checks for consistency in
 * conditions and other functions. */

PriorityAIController.prototype.allied = function(ship1,ship2)
{
	if (!ship1.isShip || !ship2.isShip)
	{
		return false;
	}
	// ships in same group
	var g1 = ship1.group;
	if (g1 && g1.containsShip(ship2))
	{
		return true;
	}
	if (g1 && g1.leader)
	{
		// ship1 is escort of ship in same group as ship2
		if (g1.leader.group && g1.leader.group.containsShip(ship2))
		{
			return true;
		}
	}
	// or in reverse, ship2 is the escort
	var g2 = ship2.group;
	if (g2 && g2.leader)
	{
		// ship2 is escort of ship in same group as ship1
		if (g2.leader.group && g2.leader.group.containsShip(ship1))
		{
			return true;
		}
	}
	// ship1 is escort of a ship, ship2 is escort of a ship, both
	// those ships are in the same group
	if (g1 && g2 && g1.leader && g2.leader && g1.leader.group && g1.leader.group.containsShip(g2.leader))
	{
		return true;
	}

	// all thargoids are allied with each other
	// all police are allied with each other
	if (ship1.scanClass == "CLASS_THARGOID" || ship1.scanClass == "CLASS_POLICE")
	{
		if (ship1.scanClass == ship2.scanClass)
		{
			return true;
		}
	}
	// Okay, these ships really do have nothing to do with each other...
	return false;
}


PriorityAIController.prototype.broadcastAttackMessage = function(target,code,priority)
{
	var msgcode = "oolite_"+code+"Attack";
	var scan = target.scanClass;
	if (scan == "CLASS_THARGOID") {
		msgcode += "Thargoid";
	} else if (scan == "CLASS_ROCK" || scan == "CLASS_CARGO" || scan == "CLASS_BUOY" || scan == "CLASS_MISSILE" || scan == "CLASS_MINE") {
		msgcode += "Inanimate";
	}
	this.communicate(msgcode,target,priority);
}


PriorityAIController.prototype.broadcastDistressMessage = function()
{
	if (this.__ltcache.oolite_sentDistressMessage)
	{
		return;
	}
	this.__ltcache.oolite_sentDistressMessage = true;
	this.ship.broadcastDistressMessage();
	if (this.ship.AIPrimaryAggressor)
	{
		this.communicate("oolite_makeDistressCall",this.ship.AIPrimaryAggressor,2);
	}
}


PriorityAIController.prototype.checkScannerWithPredicate = function(predicate)
{
	var scan = this.getParameter("oolite_scanResults");
	if (scan == null || predicate == null)
	{
		return false;
	}
	// if current target matches, use that
	if (this.ship.target && predicate.call(this,this.ship.target))
	{
		this.setParameter("oolite_scanResultSpecific",this.ship.target);
		return true;
	}
	var sl = scan.length; 
	// use a random offset so if several ships make the same scan
	// they don't all pick the same target
	var offset = Math.floor(Math.random()*sl);
	for (var i = 0 ; i < sl ; i++)
	{
		var io = (i+offset)%sl;
		if (predicate.call(this,scan[io]))
		{
			// stops ships near the witchpoint beginning an attack on the player
			// before they've even got ship control back
			if (scan[io].status != "STATUS_EXITING_WITCHSPACE")
			{
				this.setParameter("oolite_scanResultSpecific",scan[io]);
				return true;
			}
			else
			{
				// something's coming out; reconsider sooner
				this.reconsiderIn(5);
			}
		}
	}
	return false;
}


PriorityAIController.prototype.cruiseSpeed = function()
{
	if (this.__ltcache.oolite_cruiseSpeed)
	{
		return this.__ltcache.oolite_cruiseSpeed;
	}
	var cruise = this.ship.maxSpeed * 0.8;
	var ignore = this.ship.maxSpeed / 4;
	var grouped = false;
	if (this.ship.group)
	{
		var gs = this.ship.group.ships;
		if (gs.length > 1) 
		{
			grouped = true;
		}
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			var spd = gs[i].maxSpeed;
			if (spd >= ignore && cruise > spd)
			{	
				cruise = spd*0.95;
			}
		}
	}
	if (this.ship.escortGroup)
	{
		var gs = this.ship.escortGroup.ships;
		if (gs.length > 1) 
		{
			grouped = true;
		}
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			var spd = gs[i].maxSpeed;
			if (spd >= ignore && cruise > spd)
			{
				cruise = spd;
			}
		}
	}
	if (!grouped)
	{
		// not in a group, so don't need to slow down for others to catch up
		cruise = this.ship.maxSpeed;
	}
	this.__ltcache.oolite_cruiseSpeed = cruise;
	return cruise;
}


PriorityAIController.prototype.distance = function(entity)
{
	if (!entity)
	{
		return 0;
	}
	if (this.__cache.oolite_position === undefined)
	{
		this.__cache.oolite_position = this.ship.position;
	}
	return this.__cache.oolite_position.distanceTo(entity);
}


// gets a standard comms params object
PriorityAIController.prototype.entityCommsParams = function(entity)
{
	var params = {};
	if (entity)
	{
		if (entity.isShip)
		{
			// TODO: extend the ship object so more precise names can be
			// returned?
			params["oolite_entityClass"] = entity.shipClassName; 
			if (entity.shipUniqueName != "")
			{
				params["oolite_entityName"] = entity.shipUniqueName;
			}
			else
			{
				params["oolite_entityName"] = entity.displayName;
			}
		}
		else if (entity.name)
		{
			params["oolite_entityClass"] = entity.name;
			params["oolite_entityName"] = entity.name;
		}
	}
	return params;
}


PriorityAIController.prototype.fineThreshold = function()
{
	if (!this.__ltcache.oolite_fineThreshold)
	{
		this.__ltcache.oolite_fineThreshold = 50 - (system.info.government * 6);
	}
	return this.__ltcache.oolite_fineThreshold;
}


// May need to move this and hostileStation to native code for efficiency
PriorityAIController.prototype.friendlyStation = function(station)
{
	if (!station || !station.isInSpace)
	{
		return false;
	}
	// home station always friendly unless actually shooting at you
	if (station != this.__ltcache.oolite_homeStation)
	{
		var allegiance = this.stationAllegiance(station);
		// thargoid stations unfriendly to non-thargoid and vice versa
		if (allegiance == "thargoid" && this.ship.scanClass != "CLASS_THARGOID")
		{
			return false;
		}
		if (allegiance != "thargoid" && this.ship.scanClass == "CLASS_THARGOID")
		{
			return false;
		}
		// hunter stations attack any ship without bounty
		if (allegiance == "hunter" && this.ship.bounty > 0)
		{
			return false;
		}
		// galcop stations likely to be hostile to certain ships
		if (allegiance == "galcop" && (this.ship.bounty > this.fineThreshold() || this.ship.isPirate))
		{
			return false;
		}
		// pirate stations hostile to bounty-free ships
		if (allegiance == "pirate" && (this.ship.bounty == 0 || this.shipInRoleCategory(this.ship,"oolite-pirate-victim")))
		{
			return false;
		}
		// pirates won't dock at neutral stations
		if (allegiance == "neutral" && this.ship.isPirate)
		{
			return false;
		}
		// restricted+private stations never count as friendly: AI must use custom routines
		if (allegiance == "restricted" || allegiance == "private")
		{
			return false;
		}
	}
	return (station.target != this.ship || !station.hasHostileTarget);
}


PriorityAIController.prototype.homeStation = function() 
{
	if (this.__ltcache.oolite_homeStation !== undefined)
	{
		return this.__ltcache.oolite_homeStation;
	}
	// home station might be the owner of the ship, or might just
	// be a group member
	if (this.ship.owner && this.ship.owner.isStation && this.friendlyStation(this.ship.owner))
	{
		this.__ltcache.oolite_homeStation = this.ship.owner;
		return this.ship.owner;
	}
	if (this.ship.group)
	{
		var gs = this.ship.group.ships;
		for (var i = gs.length-1 ; i >= 0  ; i--)
		{
			if (gs[i] != this.ship && gs[i].isStation && this.friendlyStation(gs[i]))
			{
				this.__ltcache.oolite_homeStation = gs[i];
				return gs[i];
			}
		}
	}
	this.__ltcache.oolite_homeStation = null;
	return null;
}


// this is mostly, but not entirely, a mirror of friendlyStation to
// get certain things (e.g. pirates) to work, unfortunately, it can't
// be an exact negation
PriorityAIController.prototype.hostileStation = function(station)
{
	if (!station || !station.isInSpace)
	{
		return false;
	}
	// home station not hostile unless actually shooting at you
	if (station != this.__ltcache.oolite_homeStation)
	{

		var allegiance = this.stationAllegiance(station);
		// thargoid stations unfriendly to non-thargoid and vice versa
		if (allegiance == "thargoid" && this.ship.scanClass != "CLASS_THARGOID")
		{
			return true;
		}
		if (allegiance != "thargoid" && this.ship.scanClass == "CLASS_THARGOID")
		{
			return true;
		}
		// hunter stations attack any ship without bounty
		if (allegiance == "hunter" && this.ship.bounty > 0)
		{
			return true;
		}
		// galcop stations likely to be hostile to certain ships
		if (allegiance == "galcop" && (this.ship.bounty > this.fineThreshold() || this.ship.isPirate))
		{
			return true;
		}
		// pirate stations hostile to bounty-free ships
		if (allegiance == "pirate" && (this.ship.bounty == 0 || this.shipInRoleCategory(this.ship,"oolite-pirate-victim")))
		{
			return true;
		}
		// neutral, chaotic and private stations don't count as unfriendly
		// restricted stations should always be considered unfriendly
		if (allegiance == "restricted")
		{
			return true;
		}
		
	}
	return (station.target == this.ship && station.hasHostileTarget);
}


PriorityAIController.prototype.ignorePlayerFriendlyFire = function()
{
	var whom = player.ship;
	if (whom.target == this.ship)
	{
		return false; // was probably intentional
	}
	if (this.getParameter("oolite_lastAssist") == whom)
	{
		// player has helped this ship in this fight so is probably on the same side.
		if (Math.random() < 0.5)
		{
			// don't forgive too often
			this.setParameter("oolite_lastAssist",null);
		}
		return true;
	}
	// don't trust ships with opposite legal status
	if ((this.ship.bounty==0)==(whom.bounty==0))
	{
		// player could have meant to do that
		if (!this.getParameter("oolite_playerFriendlyFireAlready"))
		{
			var friendlyRoles = this.getParameter("oolite_friendlyRoles");
			if (Array.isArray(friendlyRoles))
			{
				for (var i=friendlyRoles.length-1;i>=0;i--)
				{
					if (this.shipInRoleCategory(whom,friendlyRoles[i]))
					{
						// only allow one!
						this.setParameter("oolite_playerFriendlyFireAlready",true);
						return true;
					}
				}
			}
		}
	}
	return false;
}


PriorityAIController.prototype.isAggressive = function(ship)
{
	if (ship && ship.isPlayer)
	{
		return !ship.isFleeing;
	}
	return ship && ship.hasHostileTarget && !ship.isFleeing && !ship.isDerelict;
}


PriorityAIController.prototype.isEscaping = function(ship)
{
	if (this.getParameter("oolite_flag_continueUnlikelyPursuits") != null)
	{
		return false;
	}
	return !this.isAggressive(ship) && this.distance(ship) > 15000 && ship.speed > this.ship.maxSpeed && ship.speed > this.ship.speed;
}


PriorityAIController.prototype.isFighting = function(ship)
{
	if (ship.isPlayer)
	{
		return !ship.isFleeing; // have to assume aggressive
	}
	return ship && ship.target && ship.hasHostileTarget;
}


/* Call just before switching target to a more serious threat, whom is
 * the more serious threat */
PriorityAIController.prototype.noteDistraction = function(whom)
{
	if (this.ship.target)
	{
		if (this.ship.target.script && this.ship.target.script.shipAttackerDistracted)
		{
			this.ship.target.script.shipAttackerDistracted(whom);
		}
		if (this.ship.target.AIScript && this.ship.target.AIScript.shipAttackerDistracted)
		{
			this.ship.target.AIScript.shipAttackerDistracted(whom);
		}
	}
}


PriorityAIController.prototype.oddsAssessment = function()
{
	if (this.__cache.oolite_oddsAssessment)
	{
		return this.__cache.oolite_oddsAssessment;
	}
	var target = this.ship.target;
	if (!target)
	{
		return 10;
	}
	var us = 0;
	var them = 0;
	var i = 0;
	var ship;
	us += this.threatAssessment(this.ship,true)
	var group;
	if ((group = this.ship.group))
	{
		var gs = group.ships;
		for (i = gs.length-1; i >= 0 ; i--)
		{
			ship = gs[i]
			if (ship != this.ship && ship.position.distanceTo(target) < this.scannerRange)
			{
				us += this.threatAssessment(ship,true);
			}
		}
		if (group.leader && group.leader.group != group)
		{
			gs = group.leader.group.ships;
			// don't want escorts running off early
			for (i = gs.length-1; i >= 0 ; i--)
			{
				ship = gs[i];
				if (ship != this.ship && ship.position.distanceTo(target) < this.scannerRange)
				{
					us += this.threatAssessment(ship,true);
				}
			}
		}
	}
	var egroup;
	if ((egroup = this.ship.escortGroup) && egroup != this.ship.group) 
	{
		var gs = egroup.ships;
		for (i = gs.length-1 ; i >= 0 ; i--)
		{
			ship = gs[i];
			if (ship != this.ship && ship.position.distanceTo(target) < this.scannerRange)
			{
				us += this.threatAssessment(ship,true);
			}
		}
	}

	// If the ship is in combat, it's almost certainly assessing a
	// ship which is in combat with it. If the ship is not in combat,
	// use the (usually smaller) non-combat assessment to encourage
	// pile-ons
	var full = this.conditionInCombat();

	them += this.threatAssessment(target,full)
	if (target.group)
	{
		var gs = target.group.ships;
		for (i = gs.length - 1 ; i >= 0 ; i--)
		{
			ship = gs[i]
			if (ship != target && this.distance(ship) < this.scannerRange)
			{
				them += this.threatAssessment(ship,full);
			}
		}
	}
	if (target.escortGroup && target.escortGroup != target.group) 
	{
		var gs = target.escortGroup.ships;
		for (i = gs.length - 1 ; i >= 0 ; i--)
		{
			ship = gs[i]
			if (ship != target && this.distance(ship) < this.scannerRange)
			{
				them += this.threatAssessment(ship,full);
			}
		}
	}
	this.__cache.oolite_oddsAssessment = us/them;		
	return this.__cache.oolite_oddsAssessment;
}


PriorityAIController.prototype.playerRoleAssessment = function()
{
	/* For the player, we pick one entry of their role array at
	 * random when first asked, then preserve it. Group members
	 * will take the role their group leader has set, and keep it
	 * until they get a group leader with different opinions. */
	var role = null;
	// grab role assessment from current group leader
	var leader = null;
	if (this.ship.group && (leader = this.ship.group.leader) && leader.AIScript.oolite_intership)
	{
		// if leader hasn't decided on a role, make them do so
		if (leader.AIScript.oolite_intership.oolite_player_role === undefined)
		{
			leader.AIScript.oolite_intership.oolite_player_role = player.roleWeights[Math.floor(Math.random()*player.roleWeights.length)];
		}
		role = leader.AIScript.oolite_intership.oolite_player_role;
		// save leader's decision
		this.ship.AIScript.oolite_intership.oolite_player_role = role;
	}
	else
	// group leader does not exist or does not have useful AI
	{ 
		// already decided what the player's role is
		if (this.ship.AIScript.oolite_intership.oolite_player_role !== undefined)
		{
			role = this.ship.AIScript.oolite_intership.oolite_player_role;
		}
		else
		{
			role = player.roleWeights[Math.floor(Math.random()*player.roleWeights.length)];
			this.ship.AIScript.oolite_intership.oolite_player_role = role; // save decision
		}
	}
	this.playerRole = role;
}


/* Be very careful with 'passon' parameter to avoid infinite loops */
PriorityAIController.prototype.respondToThargoids = function(whom,passon)
{
	if (this.getParameter("oolite_flag_noSpecialThargoidReaction") != null)
	{
		return false;
	}
	// non-thargoid being attacked by thargoid
	if (this.ship.target && this.ship.target.scanClass != "CLASS_THARGOID")
	{
		if (passon)
		{
			this.noteDistraction(whom);
		}
		this.ship.target = whom; // thargoid gets priority
		if (passon)
		{
			this.ship.requestHelpFromGroup(); // tell the rest!
			this.communicate("oolite_thargoidAttack",whom,2);
		}
	}
	var dts = this.ship.defenseTargets;
	for (var i = 0; i < dts.length ; i++)
	{
		if (dts[i].scanClass != "CLASS_THARGOID" && dts[i].scanClass != "CLASS_MISSILE" && dts[i].scanClass != "CLASS_MINE")
		{
			// safe: dts is a copy of the real data
			this.ship.removeDefenseTarget(dts[i]);
		}
	}
	return true;
}


PriorityAIController.prototype.setWitchspaceRouteTo = function(dest) 
{
	if (!dest)
	{
		return this.configurationSelectWitchspaceDestination();
	}
	if (dest == system.ID)
	{
		this.setParameter("oolite_witchspaceDestination",-1);
		return;
	}
	var info = System.infoForSystem(galaxyNumber,dest);
	if (system.info.distanceToSystem(info) < this.ship.fuel)
	{
		this.setParameter("oolite_witchspaceDestination",dest);
		return;
	}
	else
	{
		var route = system.info.routeToSystem(info);
		if (!route)
		{
			this.setParameter("oolite_witchspaceDestination",-1);
			return;
		}
		var next = route.route[1];
		if (system.info.distanceToSystem(System.infoForSystem(galaxyNumber,next)) < this.ship.fuel)
		{
			this.setParameter("oolite_witchspaceDestination",next);
			return;
		}
		this.setParameter("oolite_witchspaceDestination",null);
	}
}


PriorityAIController.prototype.shipHasRiskyContracts = function(ship) 
{
	var cs = ship.parcels;
	for (var i = cs.length-1; i >= 0 ; i--)
	{
		if (cs[i].risk == 1 && Math.random() < 0.1)
		{
			return true;
		} 
		if (cs[i].risk == 2 && Math.random() < 0.5)
		{
			return true;
		}
	}
	cs = ship.passengers;
	for (i = cs.length-1; i >= 0 ; i--)
	{
		if (cs[i].risk == 1 && Math.random() < 0.1)
		{
			return true;
		} 
		if (cs[i].risk == 2 && Math.random() < 0.5)
		{
			return true;
		}
	}
	return false;
}



/* Check role category membership allowing for player role assessment */
PriorityAIController.prototype.shipInRoleCategory = function(ship,category) 
{
	if (ship.isPlayer)
	{
		// recheck every so often in case we change groups
		if (this.__ltcache.oolite_shipInRoleCategory === undefined)
		{
			this.__ltcache.oolite_shipInRoleCategory = 1;
			this.playerRoleAssessment();
		}
		return Ship.roleIsInCategory(this.playerRole,category);
	}
	else  // NPCs are easier!
	{
		return Ship.roleIsInCategory(ship.primaryRole,category);
	}
}


PriorityAIController.prototype.stationAllegiance = function(station)
{
	if (station.allegiance)
	{
		return station.allegiance;
	}
	else
	{
		var allegiance = "neutral";

		if (station.isMainStation)
		{
			allegiance = "galcop";
		}
		else if (station.scanClass == "CLASS_THARGOID")
		{
			allegiance = "thargoid";
		}
		else if (station.scanClass == "CLASS_MILITARY" || station.scanClass == "CLASS_POLICE")
		{
			allegiance = "hunter";
		}
		else if (station.bounty > 0)
		{
			allegiance = "pirate";
		}
		else
		{
			var ses = station.subEntities;
			for (var i = 0; i < ses.length ; i++)
			{
				if (ses[i].isTurret)
				{
					allegiance = "hunter";
					break;
				}
			}
		}
		if (allegiance == "neutral" && system.mainStation.position.distanceTo(station) < 51200)
		{
			allegiance = "galcop"; // neutral stations in aegis
		}
		// cache default value
		station.allegiance = allegiance;
		return allegiance;
	}
}


PriorityAIController.prototype.threatAssessment = function(ship,full)
{
	if (ship.isStation && this.getParameter("oolite_flag_fightsNearHostileStations"))
	{
		return 1; // mostly ignore stations in assessment
	}
	var ta = worldScripts["oolite-libPriorityAI"]._threatAssessment(ship,full);
	if (!full && ship.isPlayer && ship.alertCondition < 3 && this.playerRole != "player-unknown")
	{
		// we haven't already added on the player's skill bonus, but
		// the player is somewhat known
		ta += Math.pow(player.score,0.33)/10;
	}
	return ta;
}

/* ****************** Condition functions ************** */

/* Conditions. Any function which returns true or false can be used as
 * a condition. They do not have to be part of the AI library, but
 * several common conditions are provided here. */


/*** Combat-related conditions ***/


PriorityAIController.prototype.conditionCascadeDetected = function()
{
	var cpos = this.getParameter("oolite_cascadeDetected");
	if (cpos != null)
	{
		if (this.distance(cpos) < this.scannerRange)
		{
			return true;
		}
		this.setParameter("oolite_cascadeDetected",null);
	}
	return false;
}


PriorityAIController.prototype.conditionCombatOddsTerrible = function()
{
	if (this.getParameter("oolite_flag_surrendersEarly"))
	{
		return this.oddsAssessment() < 0.75;
	}
	else
	{
		return this.oddsAssessment() < 0.375;
	}
}


PriorityAIController.prototype.conditionCombatOddsBad = function()
{
	if (this.getParameter("oolite_flag_surrendersLate"))
	{
		return this.oddsAssessment() < 0.375;
	}
	else
	{
		return this.oddsAssessment() < 0.75;
	}
}


PriorityAIController.prototype.conditionCombatOddsGood = function()
{
	return this.oddsAssessment() >= 1.5;
}


PriorityAIController.prototype.conditionCombatOddsExcellent = function()
{
	return this.oddsAssessment() >= 5.0;
}


// group has taken too many losses
PriorityAIController.prototype.conditionGroupAttritionReached = function()
{
	var group;
	if (!(group = this.ship.group))
	{
		return false;
	}
	var cgp = this.getParameter("oolite_groupPower");
	if (!cgp)
	{
		this.setParameter("oolite_groupPower",group.count);
		return false;
	}
	if (group.count > cgp)
	{
		this.setParameter("oolite_groupPower",group.count);
		return false;
	}
	return group.count < cgp*0.75;
}


PriorityAIController.prototype.conditionGroupSuppliesLow = function()
{
	var group;
	if (!(group = this.ship.group))
	{
		return this.ship.damageAssessment() > 0;
	}
	var assessment = 0;
	var gs = group.ships;
	for (var i = gs.length-1; i >= 0; i--)
	{
		assessment += gs[i].damageAssessment();
	}
	return (assessment > gs.length / 2); // over half ships have low supplies
}


PriorityAIController.prototype.conditionInCombat = function()
{
	if (this.__cache.oolite_conditionInCombat !== undefined)
	{
		return this.__cache.oolite_conditionInCombat;
	}
	this.__cache.oolite_conditionInCombat = (this.ship.alertCondition==3);
	if (!this.__cache.oolite_conditionInCombat)
	{
		delete this.ship.AIScript.oolite_intership.cargodemandpaid;
	}
	return this.__cache.oolite_conditionInCombat;
/*
	if (this.isFighting(this.ship))
	{
		this.__cache.oolite_conditionInCombat = true;
		return true;
	}
	var dts = this.ship.defenseTargets;
	for (var i=dts.length-1; i >= 0; i--)
	{
		if (this.isFighting(dts[i]) && this.distance(dts[i]) < this.scannerRange)
		{
			this.__cache.oolite_conditionInCombat = true;
			return true;
		}
	}
	if (this.ship.group != null)
	{
		var gs = this.ship.group.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (this.isFighting(gs[i]) && this.distance(gs[i]) < this.scannerRange)
			{
				this.__cache.oolite_conditionInCombat = true;
				return true;
			}
		}
	}
	if (this.ship.escortGroup != null)
	{
		var gs = this.ship.escortGroup.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (this.isFighting(gs[i]) && this.distance(gs[i]) < this.scannerRange)
			{
				this.__cache.oolite_conditionInCombat = true;
				return true;
			}
		}
	}
	this.__cache.oolite_conditionInCombat = false;
	delete this.ship.AIScript.oolite_intership.cargodemandpaid;
	return false;
*/
}

/* Ships being attacked are firing back */
PriorityAIController.prototype.conditionInCombatWithHostiles = function()
{
	if (this.isFighting(this.ship) && this.isAggressive(this.ship.target))
	{
		return true;
	}
	var dts = this.ship.defenseTargets;
	for (var i=dts.length-1; i >= 0; i--)
	{
		if (this.isAggressive(dts[i]) && this.distance(dts[i]) < this.scannerRange)
		{
			return true;
		}
		else
		{
			// this is safe to do mid-loop as dts is a copy of the
			// actual defense target list
			this.ship.removeDefenseTarget(dts[i]);
		}
	}
	if (this.ship.group != null)
	{
		var gs = this.ship.group.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (this.isFighting(gs[i]) && this.isAggressive(gs[i].target))
			{
				return true;
			}
		}
	}
	if (this.ship.escortGroup != null)
	{
		var gs = this.ship.escortGroup.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (this.isFighting(gs[i]) && this.isAggressive(gs[i].target))
			{
				return true;
			}
		}
	}
	
	delete this.ship.AIScript.oolite_intership.cargodemandpaid;
	return false;
}


PriorityAIController.prototype.conditionLosingCombat = function()
{
	var cascade = this.getParameter("oolite_cascadeDetected");
	if (cascade != null)
	{
		if (cascade.distanceTo(this.ship) < this.scannerRange)
		{
			return true;
		}
		else
		{
			this.setParameter("oolite_cascadeDetected",null);
		}
	}
	if (!this.conditionInCombat()) 
	{
		this.setParameter("oolite_lastFleeing",null);
		return false;
	}
	var en = this.ship.energy;
	var maxen = this.ship.maxEnergy; 
	if (en == maxen)
	{
		// forget previous defeats
		if (!this.conditionCombatOddsTerrible())
		{
			this.setParameter("oolite_lastFleeing",null);
		}
	}
	if (this.getParameter("oolite_flag_fleesPreemptively") && this.ship.fuel > 0 && this.ship.equipmentStatus("EQ_FUEL_INJECTION") == "EQUIPMENT_OK")
	{
		// ships of this behaviour will run away from anything if they
		// still have fuel
		return true;
	}
	
	var lastThreat = this.getParameter("oolite_lastFleeing");
	if (lastThreat != null && this.distance(lastThreat) < this.scannerRange)
	{
		// the thing that attacked us is still nearby
		return true;
	}
	if (en * 4 < maxen)
	{
		// TODO: adjust threshold based on group odds
		return true; // losing if less than 1/4 energy
	}
	var dts = this.ship.defenseTargets;
	for (var i = dts.length-1 ; i >= 0 ; i--)
	{
		if (dts[i].scanClass == "CLASS_MISSILE" && dts[i].target == this.ship)
		{
			this.ship.target = dts[i]; // specifically flee the missile
			return true;
		}
		if (dts[i].scanClass == "CLASS_MINE" && this.distance(dts[i]) < this.scannerRange)
		{
			return true;
		}
	}
	// if we've dumped cargo or the group leader has, then we're losing
	if (this.ship.AIScript.oolite_intership.cargodemandpaid)
	{
		return true;
	}
	if (this.ship.group && this.ship.group.leader && this.ship.group.leader.AIScript.oolite_intership && this.ship.group.leader.AIScript.oolite_intership.cargodemandpaid)
	{
		return true;
	}
	if (en * 2 < maxen)
	{
		if (this.conditionCombatOddsBad())
		{
			// outnumbered; losing earlier
			return true;
		}
	}
	if (this.conditionCombatOddsTerrible())
	{
		if (!this.ship.isFleeing)
		{
			if (this.ship.group && this.ship.group.leader && this.ship.group.leader == this.ship)
			{
				this.communicate("oolite_groupIsOutnumbered",{},2);
			}
			else
			{
				this.communicate("oolite_groupIsOutnumbered",{},4);
			}
		}
		// badly outnumbered; losing
		return true;
	}

	if (!this.getParameter("oolite_flag_fightsNearHostileStations"))
	{
		if (this.__ltcache.oolite_nearestStation && this.distance(this.__ltcache.oolite_nearestStation) < 51200 && this.hostileStation(this.__ltcache.oolite_nearestStation))
		{
			// if there is a hostile station nearby, probably best to leave
			return true;
		}
	}

	return false; // not losing yet
}


PriorityAIController.prototype.conditionMothershipInCombat = function()
{
	if (this.ship.group)
	{
		var leader = this.ship.group.leader;
		if (leader && leader != this.ship)
		{
			if (this.distance(leader) > this.scannerRange)
			{
				return false; // can't tell
			}
			if (this.isFighting(leader))
			{
				return true;
			}
			var ltarget = leader.target;
			if (ltarget && ltarget.target == leader && ltarget.hasHostileTarget)
			{
				return true;
			}
			var dts = leader.defenseTargets;
			for (var i = dts.length-1 ; i >= 0 ; i--)
			{
				if (dts[i].target == leader && dts[i].hasHostileTarget)
				{
					return true;
				}
			}
			return false;
		}
	}
	// no mothership
	return false;
}


PriorityAIController.prototype.conditionMothershipIsAttacking = function()
{
	if (this.ship.group && this.ship.group.leader != this.ship)
	{
		var leader = this.ship.group.leader;
		if (leader.target && this.isFighting(leader) && this.distance(leader.target) < this.scannerRange)
		{
			return true;
		}
	}
	return false;
}

// as MothershipIsAttacking, but leader.target must be aggressive
PriorityAIController.prototype.conditionMothershipIsAttackingHostileTarget = function()
{
	if (this.ship.group && this.ship.group.leader != this.ship)
	{
		var leader = this.ship.group.leader;
		if (leader.target && this.isFighting(leader) && this.isAggressive(leader.target) && this.distance(leader.target) < this.scannerRange)
		{
			return true;
		}
	}
	return false;
}

PriorityAIController.prototype.conditionMothershipUnderAttack = function()
{
	if (this.ship.group && this.ship.group.leader != this.ship)
	{
		var leader = this.ship.group.leader;
		if (leader.target && leader.target.target == leader && leader.target.hasHostileTarget && this.distance(leader.target) < this.scannerRange)
		{
			return true;
		}
		var dts = leader.defenseTargets;
		for (var i = 0 ; i < dts.length ; i++)
		{
			if (dts[i].target == leader && dts[i].hasHostileTarget && this.distance(dts[i]) < this.scannerRange)
			{
				return true;
			}
		}
		return false;
	}
	else
	{
		return false;
	}
}


PriorityAIController.prototype.conditionSuppliesLow = function()
{
	if (this.__ltcache.oolite_conditionSuppliesLow !== undefined)
	{
		return this.__ltcache.oolite_conditionSuppliesLow;
	}
	this.__ltcache.oolite_conditionSuppliesLow = (this.ship.damageAssessment() > 0);
	return this.__ltcache.oolite_conditionSuppliesLow;
}


/*** Navigation-related conditions ***/


PriorityAIController.prototype.conditionCanWitchspaceOnRoute = function()
{
	if (!this.ship.hasHyperspaceMotor)
	{
		return false;
	}
	var dest = this.getParameter("oolite_witchspaceDestination");
	if (dest == null || dest == -1)
	{
		return false;
	}
	return (system.info.distanceToSystem(System.infoForSystem(galaxyNumber,dest)) <= this.ship.fuel);
}


PriorityAIController.prototype.conditionCanWitchspaceOut = function()
{
	if (!this.ship.hasHyperspaceMotor)
	{
		return false;
	}
	return (system.info.systemsInRange(this.ship.fuel).length > 0);
}


PriorityAIController.prototype.conditionFriendlyStationExists = function()
{
	if (this.__cache.oolite_friendlyStationExists !== undefined)
	{
		return this.__cache.oolite_friendlyStationExists;
	}
	var stations = system.stations;
	for (var i = 0 ; i < stations.length ; i++)
	{
		var station = stations[i];
		if (this.friendlyStation(station))
		{
			this.__cache.oolite_friendlyStationExists = true;
			return true;
		}
	}
	this.__cache.oolite_friendlyStationExists = false;
	return false;
}

PriorityAIController.prototype.conditionFriendlyStationNearby = function()
{
	return this.friendlyStation(this.__ltcache.oolite_nearestStation) && this.distance(this.__ltcache.oolite_nearestStation) < this.scannerRange;
}


PriorityAIController.prototype.conditionGroupIsSeparated = function()
{
	if (!this.ship.group || !this.ship.group.leader)
	{
		return false;
	}
	var leader = this.ship.group.leader;
	if (leader.isStation)
	{
		// can get 2x as far from station
		return (this.distance(leader) > this.scannerRange * 2);
	}
	else
	{
		return (this.distance(leader) > this.scannerRange);
	}
}


PriorityAIController.prototype.conditionHasSelectedPlanet = function()
{
	var planet = this.getParameter("oolite_selectedPlanet");
	if (planet && (!planet.isValid || !planet.isPlanet))
	{
		this.setParameter("oolite_selectedPlanet",null);
		return false;
	}
	return planet != null;
}


PriorityAIController.prototype.conditionHasSelectedStation = function()
{
	var station = this.getParameter("oolite_selectedStation");
	if (station && (!station.isValid || !station.isStation))
	{
		this.setParameter("oolite_selectedStation",null);
		return false;
	}
	return station != null;
}



PriorityAIController.prototype.conditionHomeStationExists = function()
{
	return (this.homeStation() != null);
}


PriorityAIController.prototype.conditionHomeStationNearby = function()
{
	var home = this.homeStation();
	if (home == null)
	{
		return false;
	}
	return this.distance(home) < this.scannerRange;
}


PriorityAIController.prototype.conditionHostileStationNearby = function()
{
	return this.hostileStation(this.__ltcache.oolite_nearestStation) && this.distance(this.__ltcache.oolite_nearestStation) < 51200;
}


PriorityAIController.prototype.conditionInInterstellarSpace = function()
{
	return system.isInterstellarSpace;
}


PriorityAIController.prototype.conditionMainPlanetNearby = function()
{
	if (!system.mainPlanet)
	{
		return false;
	}
	if (this.distance(system.mainPlanet) < system.mainPlanet.radius * 4)
	{
		return true;
	}
	return false;
}


PriorityAIController.prototype.conditionNearDestination = function()
{
	return (this.distance(this.ship.destination) < this.ship.desiredRange);
}


PriorityAIController.prototype.conditionPlayerNearby = function()
{
	return this.distance(player.ship) < this.scannerRange;
}


PriorityAIController.prototype.conditionReadyToSunskim = function()
{
	return (system.sun && this.distance(system.sun) < system.sun.radius * 1.15);
}


PriorityAIController.prototype.conditionSelectedStationNearby = function()
{
	var station = this.getParameter("oolite_selectedStation");
	if (station && this.distance(station) < this.scannerRange)
	{
		return true;
	}
	return false;
}

PriorityAIController.prototype.conditionSelectedStationNearMainPlanet = function()
{
	if (!system.mainPlanet)
	{
		return false;
	}
	var station = this.getParameter("oolite_selectedStation");
	if (station && station.position.distanceTo(system.mainPlanet) < system.mainPlanet.radius * 4)
	{
		return true;
	}
	return false;
}


PriorityAIController.prototype.conditionStationNearby = function()
{
	return this.distance(this.__ltcache.oolite_nearestStation) < this.scannerRange*2;
}


PriorityAIController.prototype.conditionSunskimPossible = function()
{
	return (system.sun && 
			!system.sun.hasGoneNova && 
			!system.sun.isGoingNova && 
			this.ship.fuel < 7 && 
			this.ship.equipmentStatus("EQ_FUEL_SCOOPS") == "EQUIPMENT_OK" &&
			(this.ship.heatInsulation > 1000/this.ship.maxSpeed || this.ship.heatInsulation >= 12));
}


PriorityAIController.prototype.conditionWormholeNearby = function()
{
	var holes = system.wormholes;
	for (var i=holes.length-1; i >= 0 ; i--)
	{
		var hole = holes[i];
		if (hole.expiryTime > clock.adjustedSeconds && this.distance(hole) < this.scannerRange)
		{
			this.__cache.oolite_wormholeNearby = hole;
			return true;
		}
	}
	return false;
}


/*** Pirate conditions ***/


PriorityAIController.prototype.conditionCargoDemandsMet = function()
{
	if (!this.getParameter("oolite_flag_watchForCargo"))
	{
		log(this.name,"AI '"+this.ship.AIScript.name+"' for ship "+this.ship+" is asking if cargo demands are met but has not set 'oolite_flag_watchForCargo'");
		return true;
	}
	var seen = this.getParameter("oolite_cargoDropped");
	if (seen != null)
	{
		var recorder = null;
		var demand = 0;
		if (this.ship.group)
		{
			if (this.ship.group.leader && this.ship.group.leader.AIScript.oolite_intership && this.ship.group.leader.AIScript.oolite_intership.cargodemanded > 0)
			{
				if (this.ship.group.leader.AIScript.oolite_intership.cargodemandmet)
				{
					return true;
				}
				recorder = this.ship.group.leader;
				demand = this.ship.group.leader.AIScript.oolite_intership.cargodemanded;
			}
			else if (this.ship.group.ships[0].AIScript.oolite_intership && this.ship.group.ships[0].AIScript.oolite_intership.cargodemanded > 0)

			{
				demand = this.ship.group.ships[0].AIScript.oolite_intership.cargodemanded;							
				if (this.ship.group.ships[0].AIScript.oolite_intership.cargodemandmet)
				{
					return true;
				}
				recorder = this.ship.group.ships[0];
			}
		}
		else
		{
			if (this.ship.AIScript.oolite_intership.cargodemanded > 0)
			{
				if (this.ship.AIScript.oolite_intership.cargodemandmet)
				{
					return true;
				}
				demand = this.ship.AIScript.oolite_intership.cargodemanded;
				recorder = this.ship;
			}
		}

		if (demand == 0)
		{
			return true; // no demand made
		}
		if (demand <= seen)
		{
			recorder.AIScript.oolite_intership.cargodemandmet = true;
			return true;
		}
	}
	return false;
}


PriorityAIController.prototype.conditionGroupHasEnoughLoot = function()
{
	var used = 0;
	var available = 0;
	if (!this.ship.group)
	{
		used = this.ship.cargoSpaceUsed;
		if (this.ship.equipmentStatus("EQ_FUEL_SCOOPS") == "EQUIPMENT_OK")
		{
			available = this.ship.cargoSpaceAvailable;
		}
	}
	else
	{
		var gs = this.ship.group.ships;
		for (var i = gs.length-1; i >= 0 ; i--)
		{
			used += gs[i].cargoSpaceUsed;
			if (gs[i].equipmentStatus("EQ_FUEL_SCOOPS") == "EQUIPMENT_OK")
			{
				available += gs[i].cargoSpaceAvailable;
			}
		}
	}
	var threshold = 0.33; // normally retreat at 2/3 hold
	if (this.conditionGroupAttritionReached())
	{
		threshold += 0.25; // if losing ships, take off a 1/4 of hold space
	}
	if (this.conditionGroupSuppliesLow())
	{
		threshold += 0.25; // if running out of supplies, take off a 1/4 of hold space
	} 

	if (available < (available+used)*threshold || available == 0)
	{
		return true;
	}
	return false;
}


PriorityAIController.prototype.conditionPiratesCanBePaidOff = function()
{
	if (this.ship.AIScript.oolite_intership.cargodemandpaid)
	{
		return false;
	}
	// TODO: need some way for the player to set this
	if (!this.ship.AIScript.oolite_intership.cargodemand)
	{
		return false;
	}
	if (this.ship.cargoSpaceUsed < this.ship.AIScript.oolite_intership.cargodemand)
	{
		return false;
	}
	return true;
}


/*** Scanner conditions ***/


PriorityAIController.prototype.conditionScannerContainsAssassinationTarget = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.primaryRole == "escape-capsule"; 
	});
}


PriorityAIController.prototype.conditionScannerContainsCleanShip = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return (s.scanClass == "CLASS_NEUTRAL" || s.scanClass == "CLASS_POLICE") && s.bounty == 0; 
	});
}


PriorityAIController.prototype.conditionScannerContainsCourier = function()
{
	return (this.checkScannerWithPredicate(function(s) { 
		return (this.shipInRoleCategory(s,"oolite-courier")) || (s.isPlayer && this.shipHasRiskyContracts(s));
	}));
}


PriorityAIController.prototype.conditionScannerContainsEscapePods = function()
{
	if (!this.conditionCanScoopCargo())
	{
		return false;
	}
	return this.checkScannerWithPredicate(function(s) { 
		return  s.primaryRole == "escape-capsule" && s.isInSpace && s.scanClass == "CLASS_CARGO" && s.velocity.magnitude() < this.ship.maxSpeed; 
	});
}


PriorityAIController.prototype.conditionScannerContainsFineableOffender = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		var threshold = this.fineThreshold();
		return s.isInSpace && s.bounty <= threshold && s.bounty > 0 && !s.markedForFines && (s.scanClass == "CLASS_NEUTRAL" || s.isPlayer) && !s.isDerelict; 
	});
}


PriorityAIController.prototype.conditionScannerContainsFugitive = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.isInSpace && s.bounty > 50 && s.scanClass != "CLASS_CARGO" && s.scanClass != "CLASS_ROCK" && s.scanClass != "CLASS_BUOY"; 
	});
}

PriorityAIController.prototype.conditionScannerContainsHuntableOffender = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		var threshold = this.fineThreshold() / 2;
		return s.isInSpace && s.bounty > threshold && s.scanClass != "CLASS_CARGO" && s.scanClass != "CLASS_ROCK" && s.scanClass != "CLASS_BUOY"; 
	});
}


PriorityAIController.prototype.conditionScannerContainsSeriousOffender = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		var threshold = this.fineThreshold();
		return s.isInSpace && s.bounty > threshold && s.scanClass != "CLASS_CARGO" && s.scanClass != "CLASS_ROCK" && s.scanClass != "CLASS_BUOY"; 
	});
}


PriorityAIController.prototype.conditionScannerContainsHunters = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return (s.primaryRole && this.shipInRoleCategory(s,"oolite-bounty-hunter")) || s.scanClass == "CLASS_POLICE" || (s.isStation && s.isMainStation);
	});
}


PriorityAIController.prototype.conditionScannerContainsLoneVictim = function()
{
	var scan = this.getParameter("oolite_scanResults");
	var others = 0;
	var target = null;
	for (var i = scan.length-1 ; i >= 0 ; i--)
	{
		if (!this.allied(this.ship,scan[i]) && this.shipInRoleCategory(scan[i],"oolite-pirate-victim") && scan[i].cargoSpaceCapacity > 0)
		{
			target = scan[i];
			others++;
		}
	}
	if (others == 1)
	{
		this.setParameter("oolite_scanResultSpecific",target);
		return true;
	}
	return false;
}


PriorityAIController.prototype.conditionScannerContainsMiningOpportunity = function()
{
	// if hold full, no
	if (!this.conditionCanScoopCargo())
	{
		return false;
	}
	// need a mining laser, and for now a forward one
	if (!this.ship.forwardWeapon == "EQ_WEAPON_MINING_LASER")
	{
		return false;
	}
	return this.conditionScannerContainsRocks();
}


PriorityAIController.prototype.conditionScannerContainsNonThargoid = function()
{
	var prioritytargets = this.checkScannerWithPredicate(function(s) { 
		return s.scanClass != "CLASS_THARGOID" && s.scanClass != "CLASS_ROCK" && s.scanClass != "CLASS_CARGO";
	});
	if (prioritytargets) 
	{
		return true;
	}
	return this.checkScannerWithPredicate(function(s) { 
		return s.scanClass != "CLASS_THARGOID";
	});
}


PriorityAIController.prototype.conditionScannerContainsPirateLeader = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.group && s.group.leader == s && this.shipInRoleCategory(s,"oolite-pirate-leader");
	});
}


PriorityAIController.prototype.conditionScannerContainsPirateVictims = function()
{
	var lpv = this.getParameter("oolite_lastPirateVictim");
	return this.checkScannerWithPredicate(function(s) { 
		// is a pirate victim
		// can carry cargo
		// hasn't already paid up
		return s != lpv && this.shipInRoleCategory(s,"oolite-pirate-victim") && s.cargoSpaceCapacity > 0 && (!s.AIScript || !s.AIScript.oolite_intership || !s.AIScript.oolite_intership.cargodemandpaid);
	});
}


PriorityAIController.prototype.conditionScannerContainsReadyThargoidMothership = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.hasRole("thargoid-mothership") && (!s.escortGroup || s.escortGroup.count <= 16);
	});
}


PriorityAIController.prototype.conditionScannerContainsRocks = function()
{
	var scan1 = this.checkScannerWithPredicate(function(s) { 
		return s.isInSpace && s.isBoulder;
	});
	if (scan1)
	{
		return true;
	}
	// no boulders, what about asteroids?
	return this.checkScannerWithPredicate(function(s) { 
		return s.isInSpace && s.hasRole("asteroid");
	});
}


PriorityAIController.prototype.conditionScannerContainsSalvage = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.isInSpace && s.scanClass == "CLASS_CARGO" && s.commodity != null;
	});
}


PriorityAIController.prototype.conditionScannerContainsSalvageForGroup = function()
{
	if (!this.__ltcache.oolite_conditionScannerContainsSalvageForGroup)
	{
		var maxspeed = 0;
		if (this.conditionCanScoopCargo())
		{
			maxspeed = this.ship.maxSpeed;
		}
		if (this.ship.group)
		{
			var gs = this.ship.group.ships;
			for (var i = gs.length-1; i >= 0 ; i--)
			{
				if (gs[i].cargoSpaceAvailable > 0 && gs[i].equipmentStatus("EQ_FUEL_SCOOPS") == "EQUIPMENT_OK" && gs[i].maxSpeed > maxspeed)
				{
					maxspeed = gs[i].maxSpeed;
				}
			}
		}
		this.__ltcache.oolite_conditionScannerContainsSalvageForGroup = maxspeed;
	}
	return this.checkScannerWithPredicate(function(s) { 
		return s.isInSpace && s.scanClass == "CLASS_CARGO" && s.commodity != null && s.velocity.magnitude() < this.__ltcache.oolite_conditionScannerContainsSalvageForGroup; 
	});
}


PriorityAIController.prototype.conditionScannerContainsSalvageForMe = function()
{
	if (!this.conditionCanScoopCargo())
	{
		return false;
	}
	return this.checkScannerWithPredicate(function(s) { 
		return s.isInSpace && s.scanClass == "CLASS_CARGO" && s.commodity != null && s.velocity.magnitude() < this.ship.maxSpeed; 
	});
}


PriorityAIController.prototype.conditionScannerContainsShipAttackingPirate = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.target && s.hasHostileTarget && s.target.isPirate;
	});
}


PriorityAIController.prototype.conditionScannerContainsShipNeedingEscort = function()
{
	if (this.ship.bounty == 0)
	{
		return this.checkScannerWithPredicate(function(s) { 
			return s.scanClass == this.ship.scanClass && s.bounty == 0 && (!s.escortGroup || s.escortGroup.count <= s.maxEscorts);
		});
	}
	else
	{
		return this.checkScannerWithPredicate(function(s) { 
			return s.scanClass == this.ship.scanClass && s.bounty > 0 && (!s.escortGroup || s.escortGroup.count <= s.maxEscorts);
		});
	}
}


PriorityAIController.prototype.conditionScannerContainsSuspiciousShip = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return (s.primaryRole && this.shipInRoleCategory(s,"oolite-police-dislike"));
	});
}


PriorityAIController.prototype.conditionScannerContainsThargoidMothership = function()
{
	return this.checkScannerWithPredicate(function(s) { 
		return s.hasRole("thargoid-mothership");
	});
}


PriorityAIController.prototype.conditionScannerContainsUnspreadMissile = function()
{
	if (!this.getParameter("oolite_flag_autoSpreadMissiles"))
	{
		return false;
	}
	return this.checkScannerWithPredicate(function(s) { 
		var target = this.ship.target;
		return (s.scanClass == "CLASS_MISSILE") && s.target == target && s.owner == this.ship.owner && this.distance(s) < 500 && this.distance(target) > s.position.distanceTo(target);
	});
}


/*** State conditions ***/


PriorityAIController.prototype.conditionAllEscortsInFlight = function()
{
	if (!this.ship.escortGroup)
	{
		return true; // there are no escorts not in flight
	}
	var gs = this.ship.escortGroup.ships;
	for (var i = gs.length-1 ; i >= 0 ; i--)
	{
		if (gs[i].status != "STATUS_IN_FLIGHT")
		{
			return false;
		}
	}
	// if just exited witchspace, escorts might not have rejoined escort
	// group yet.
	if (!this.ship.group)
	{
		return true; 
	}
	var gs = this.ship.group.ships;
	for (var i = gs.length-1 ; i >= 0 ; i--)
	{
		if (gs[i].status != "STATUS_IN_FLIGHT")
		{
			return false;
		}
	}

	return true;
}

PriorityAIController.prototype.conditionCanScoopCargo = function()
{
	if (this.__cache.oolite_conditionCanScoopCargo !== undefined)
	{
		return this.__cache.oolite_conditionCanScoopCargo;
	}
	if (this.ship.cargoSpaceAvailable == 0 || this.ship.equipmentStatus("EQ_FUEL_SCOOPS") != "EQUIPMENT_OK")
	{
		this.__cache.oolite_conditionCanScoopCargo = false;
		return false;
	}
	this.__cache.oolite_conditionCanScoopCargo = true;
	return true;
}


PriorityAIController.prototype.conditionCargoIsProfitableHere = function()
{
	// only consider these values if the ship has a route defined
	if (this.ship.homeSystem != this.ship.destinationSystem)
	{
		// cargo is always considered profitable in the designated
		// destination system (assume they have a prepared buyer)
		if (this.ship.destinationSystem && this.ship.destinationSystem == system.ID)
		{
			return true;
		}
		// cargo is never considered profitable in the designated source
		// system (or you could get ships launching and immediately
		// redocking)
		if (this.ship.homeSystem && this.ship.homeSystem == system.ID)
		{
			return false;
		}
		// and allow ships to be given multi-system trips if wanted
		if (this.getParameter("oolite_flag_noDockingUntilDestination"))
		{
			return false;
		}
	}

	if (!system.mainStation)
	{
		return false;
	}

	if (this.__ltcache.oolite_conditionCargoIsProfitableHere == undefined)
	{
		if (this.ship.cargoSpaceUsed == 0)
		{
			this.__ltcache.oolite_conditionCargoIsProfitableHere = false;
		}
		else
		{
			var cargo = this.ship.cargoList;
			var profit = 0;
			var multiplier = (system.info.economy <= 3)?-1:1;
			var market = system.mainStation.market;
			for (var i = cargo.length-1 ; i >= 0 ; i--)
			{
				var commodity = cargo[i].commodity;
				var quantity = cargo[i].quantity;
				var adjust = market[commodity].marketEcoAdjustPrice * multiplier * quantity / market[commodity].marketMaskPrice;
				profit += adjust;
			}
			
			this.__ltcache.oolite_conditionCargoIsProfitableHere = (profit >= 0);
		}
	}
	return this.__ltcache.oolite_conditionCargoIsProfitableHere;
}


PriorityAIController.prototype.conditionCoinFlip = function()
{
	return (Math.random() < 0.5);
}



PriorityAIController.prototype.conditionGroupLeaderIsStation = function()
{
	return (this.ship.group && this.ship.group.leader && this.ship.group.leader.isStation);
}


PriorityAIController.prototype.conditionHasInterceptCoordinates = function()
{
	return (this.getParameter("oolite_interceptCoordinates") != null);
}


PriorityAIController.prototype.conditionHasMothership = function()
{
	return (this.ship.group && this.ship.group.leader && this.ship.group.leader != this.ship);
}


PriorityAIController.prototype.conditionHasNonThargoidTarget = function()
{
	return (this.ship.target && this.ship.target.scanClass != "CLASS_THARGOID");
}


PriorityAIController.prototype.conditionHasReceivedDistressCall = function()
{
	var aggressor = this.getParameter("oolite_distressAggressor");
	var sender = this.getParameter("oolite_distressSender");
	var ts = this.getParameter("oolite_distressTimestamp");

	if (aggressor == null || !aggressor.isInSpace || sender == null || !sender.isInSpace || this.distance(sender) > this.scannerRange || ts+30 < clock.adjustedSeconds)
	{
		// no, or it has expired
		this.setParameter("oolite_distressAggressor",null);
		this.setParameter("oolite_distressSender",null);
		this.setParameter("oolite_distressTimestamp",null);
		return false;
	}
	return true;
}


PriorityAIController.prototype.conditionHasRememberedTarget = function()
{
	var rt = this.getParameter("oolite_rememberedTarget");

	if (rt != null && (rt.isInSpace || rt.status == "STATUS_ENTERING_WITCHSPACE"))
	{
		return true;
	} 
	else
	{
		this.setParameter("oolite_rememberedTarget",null);
		return false;
	}
}


PriorityAIController.prototype.conditionHasTarget = function()
{
	return this.ship.target != null;
}


PriorityAIController.prototype.conditionHasWaypoint = function()
{
	return this.getParameter("oolite_waypoint") != null;
}


PriorityAIController.prototype.conditionIsActiveThargon = function()
{
	return this.ship.scanClass == "CLASS_THARGOID" && this.ship.hasRole("EQ_THARGON");
}


PriorityAIController.prototype.conditionIsEscorting = function()
{
	if (!this.ship.group || !this.ship.group.leader || this.ship.group.leader == this.ship)
	{
		return false;
	}
	var leader = this.ship.group.leader;
	if (leader.escortGroup && leader.escortGroup.containsShip(this.ship))
	{
		if (leader.status == "STATUS_ENTERING_WITCHSPACE")
		{
			var hole = this.getParameter("oolite_witchspaceWormhole");
			if (hole == null || hole.expiryTime < clock.seconds)
			{
				// has been left behind
				this.configurationLeaveEscortGroup();
				this.setParameter("oolite_witchspaceWormhole",null);
				return false;
			}
		}
		return true;
	}
	return false;
}


PriorityAIController.prototype.conditionIsGroupLeader = function()
{
	if (!this.ship.group)
	{
		return true;
	}
	return (this.ship.group.leader == this.ship);
}


PriorityAIController.prototype.conditionMissileOutOfFuel = function()
{
	var range = 30000; // 30 km default
	if (this.ship.scriptInfo.oolite_missile_range)
	{
		range = this.ship.scriptInfo.oolite_missile_range;
	}
	return range < this.ship.distanceTravelled;
}


PriorityAIController.prototype.conditionPatrolIsOver = function()
{
	return this.ship.distanceTravelled > 200000 || this.conditionSuppliesLow();
}


PriorityAIController.prototype.conditionWitchspaceEntryRequested = function()
{
	return (this.getParameter("oolite_witchspaceWormhole") != null);
}




/* ****************** Behaviour functions ************** */

/* Behaviours. Behaviours are effectively a state definition,
 * defining a set of events and responses. They are aided in this
 * by the 'responses', which mean that the event handlers for the
 * behaviour within the definition can itself be templated.  */



PriorityAIController.prototype.behaviourApproachDestination = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);

	handlers.shipAchievedDesiredRange = this.responseComponent_standard_shipAchievedDesiredRange;

	var waypoints = this.getParameter("oolite_waypoints");
	if (waypoints != null)
	{
		this.ship.destination = waypoints[waypoints.length-1];
		this.ship.desiredRange = 100;
	}
	var blocker = this.ship.checkCourseToDestination();
	if (blocker)
	{
		if (blocker.isPlanet || blocker.isSun)
		{
			// the selected planet can't block
			if (blocker.isSun || this.getParameter("oolite_selectedPlanet") != blocker)
			{
				var dist = this.distance(blocker);
				if (dist < blocker.radius * 1.3)
				{
					if (waypoints == null)
					{
						waypoints = [];
					}
					waypoints.push(this.ship.position.subtract(blocker.position.subtract(this.ship.position)));
					this.ship.destination = waypoints[waypoints.length-1];
					this.ship.desiredRange = 100;
				}
				else if (this.distance(blocker) < blocker.radius * 3)
				{
					if (waypoints == null)
					{
						waypoints = [];
					}
					waypoints.push(this.ship.getSafeCourseToDestination());
					this.ship.destination = waypoints[waypoints.length-1];
					this.ship.desiredRange = 100;
				}
			}
		}
		else if (blocker.isShip)
		{
			if (this.distance(blocker) < this.scannerRange)
			{
				if (!blocker.group || !blocker.group.leader == this.ship)
				{
					// our own escorts are not a blocker!
					if (waypoints == null)
					{
						waypoints = [];
					}
					waypoints.push(this.ship.getSafeCourseToDestination());
					this.ship.destination = waypoints[waypoints.length-1];
					this.ship.desiredRange = 100;
				}
			}
		}
	}
	this.setParameter("oolite_waypoints",waypoints);
	this.applyHandlers(handlers);
	this.ship.performFlyToRangeFromDestination();
}


PriorityAIController.prototype.behaviourAvoidCascadeExplosion = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);

	var cascade = this.getParameter("oolite_cascadeDetected");
	if (cascade != null)
	{
		if (cascade.distanceTo(this.ship) < this.scannerRange)
		{
			if (this.ship.defenseTargets.length > 0 && this.ship.defenseTargets[0].scanClass == "CLASS_MINE")
			{
				// if the mine is still visible, conventional fleeing works
				this.communicate("oolite_quiriumCascade",{},3);
				this.ship.target = this.ship.defenseTargets[0];
				this.ship.desiredRange = 30000;
				this.ship.performFlee();
				return;
			}
			else
			{
				if (this.ship.destination != cascade)
				{
					this.communicate("oolite_quiriumCascade",{},3);
				}
				this.ship.destination = cascade;
				this.ship.desiredRange = 30000;
				this.ship.desiredSpeed = 10*this.ship.maxSpeed;
				this.ship.performFlyToRangeFromDestination();
				return;
			}
		}
		else
		{
			this.setParameter("oolite_cascadeDetected",null);
		}
	}
}


PriorityAIController.prototype.behaviourBecomeInactiveThargon = function()
{
	this.applyHandlers({});
	this.ship.scanClass = "CLASS_CARGO";
	this.ship.target = null;
	this.ship.clearDefenseTargets();
	if (this.ship.group)
	{
		this.ship.group.removeShip(this.ship);
		this.ship.group = null;
	}
	if (this.ship.escortGroup)
	{
		this.ship.escortGroup.removeShip(this.ship);
	}
	this.ship.desiredSpeed = 0;
	this.ship.performStop();
	var nearby = this.ship.checkScanner(true);
	for (var i = 0 ; i < nearby.length ; i++)
	{
		var ship = nearby[i];
		if (ship.target == this.ship && !ship.isPlayer && ship.hasHostileTarget)
		{
			ship.target = null;
		}
		ship.removeDefenseTarget(this.ship);
	}
}


PriorityAIController.prototype.behaviourCollectSalvage = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	handlers.shipScoopedOther = this.responseComponent_standard_shipScoopedOther;
	this.applyHandlers(handlers);
	this.ship.performCollect();
}


PriorityAIController.prototype.behaviourDestroyCurrentTarget = function()
{
	this.setParameter("oolite_witchspaceEntry",null);

	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);

	if (this.getParameter("oolite_flag_noSpecialThargoidReaction") != null)
	{
		if (this.ship.scanClass != "CLASS_THARGOID" && this.ship.target.scanClass != "CLASS_THARGOID" && this.ship.target.target.scanClass == "CLASS_THARGOID")
		{
			this.respondToThargoids(this.ship.target.target,true);
			this.ship.performAttack();
			return;
		}
	}

	
	/* This doesn't work: ships which are removed from the list
	 * because they're unreachable then just end up being reselected the
	 * next time the ship scans for targets. */
	/*
	if (this.getParameter("oolite_flag_continueUnlikelyPursuits") == null)
	{
		if (this.ship.target)
		{
			if (this.isEscaping(this.ship.target))
			{
				this.ship.removeDefenseTarget(this.ship.target);
				this.ship.target = null;
			}
		}
	}
	*/

	if (this.ship.target)
	{
		if (!this.ship.hasHostileTarget)
		{
			// entering attack mode
			this.broadcastAttackMessage(this.ship.target,"beginning",3);
			this.ship.requestHelpFromGroup();
		}
		else 
		{
			this.broadcastAttackMessage(this.ship.target,"continuing",4);
		}
	}
	this.ship.performAttack();
}


// NOTE: this does not, and should not, check whether the station is friendly
PriorityAIController.prototype.behaviourDockWithStation = function()
{
	var station = this.getParameter("oolite_dockingStation");
	this.ship.target = station;
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.responsesAddDocking(handlers);
	this.ship.requestDockingInstructions();
	if (!this.ship.dockingInstructions)
	{
		this.ship.performIdle();
		this.reconsiderNow();
		return;
	}
	switch (this.ship.dockingInstructions.ai_message)
	{
	case "TOO_BIG_TO_DOCK":
	case "DOCKING_REFUSED":
		this.ship.setParameter("oolite_dockingStation",null);
		this.ship.target = null;
		this.reconsiderNow();
		break;
	case "TRY_AGAIN_LATER":
		if (this.distance(station) < 10000)
		{
			this.ship.destination = station.position;
			this.ship.desiredRange = 12500;
			this.ship.desiredSpeed = this.cruiseSpeed();
			this.ship.performFlyToRangeFromDestination();
			break;
		}
		// else fall through
	case "HOLD_POSITION":
		this.communicate("oolite_dockingWait",{},4);
		this.ship.destination = station.position;
		this.ship.performFaceDestination();
		// and will reconsider in a little bit
		break;
	case "APPROACH_COORDINATES":
		if (this.ship.escortGroup && this.ship.escortGroup.count > 1)
		{
			// docking clearance has been granted - can now release escorts
			if (this.ship.dockingInstructions.docking_stage >= 2)
			{
				this.communicate("oolite_dockEscorts",{},3);
				this.ship.dockEscorts();
			}
		}
		// and fall through
	case "APPROACH":				
	case "BACK_OFF":
		this.ship.performFlyToRangeFromDestination();
		break;
	}
	this.applyHandlers(handlers);
}


PriorityAIController.prototype.behaviourEnterWitchspace = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	var wormhole = this.getParameter("oolite_witchspaceWormhole");
	if (wormhole && wormhole.expiryTime < clock.adjustedSeconds)
	{
		// the wormhole we were trying for has expired
		this.setParameter("oolite_witchspaceWormhole",null);
		if (this.ship.group && this.ship.group.leader && this.ship.group.leader.status == "STATUS_ENTERING_WITCHSPACE")
		{
			// left behind, so leave group
			this.ship.group.removeShip(this.ship);
			this.ship.group = null;
		}
	}
	else if (wormhole)
	{

		handlers.playerWillEnterWitchspace = this.responseComponent_trackPlayer_playerWillEnterWitchspace;
		this.ship.destination = wormhole.position;
		this.ship.desiredRange = 0;
		this.ship.desiredSpeed = this.ship.maxSpeed;
		this.ship.performFlyToRangeFromDestination();
		this.applyHandlers(handlers);
		return;
	}

	var destID = this.getParameter("oolite_witchspaceDestination");
	if (destID == null)
	{
		// look for wormholes out of here
		// no systems in range
		handlers.playerWillEnterWitchspace = this.responseComponent_trackPlayer_playerWillEnterWitchspace;
		this.applyHandlers(handlers);
		return;
	}
	else
	{
		handlers.shipWitchspaceBlocked = this.responseComponent_standard_shipWitchspaceBlocked;
		// set up the handlers before trying it
		this.applyHandlers(handlers);
		
		var entry = this.getParameter("oolite_witchspaceEntry");
		// wait for escorts to launch
		if (!this.conditionAllEscortsInFlight())
		{
			this.ship.destination = this.ship.position.add(this.ship.vectorForward.multiply(30000));
			this.ship.desiredRange = 10000;
			this.ship.desiredSpeed = this.cruiseSpeed();
			if (this.ship.checkCourseToDestination())
			{
				this.ship.destination = this.ship.getSafeCourseToDestination();
			}
			this.ship.performFlyToRangeFromDestination();

		}
		else if (entry != null && entry < clock.seconds)
		{
			// this should work
			var result = this.ship.exitSystem(destID);
			// if it doesn't, we'll get blocked
			if (result)
			{
				this.ship.notifyGroupOfWormhole();
				this.setParameter("oolite_witchspaceEntry",null);
			}
		}
		else
		{
			if (entry == null)
			{
				this.communicate("oolite_engageWitchspaceDrive",{},4);
				this.setParameter("oolite_witchspaceEntry",clock.seconds + 15);
			}
			this.ship.destination = this.ship.position.add(this.ship.vectorForward.multiply(30000));
			this.ship.desiredRange = 10000;
			this.ship.desiredSpeed = this.cruiseSpeed();
			if (this.ship.checkCourseToDestination())
			{
				this.ship.destination = this.ship.getSafeCourseToDestination();
			}
			this.ship.performFlyToRangeFromDestination();
		}
	}
}


PriorityAIController.prototype.behaviourEscortMothership = function()
{
	var handlers = {};
	if (this.ship.group.leader)
	{
		this.communicate("oolite_escortFormation",this.ship.group.leader,4);
	}

	this.responsesAddStandard(handlers);
	this.responsesAddEscort(handlers);
	this.applyHandlers(handlers);
	this.ship.desiredRange = 0;
	this.ship.performEscort();
}


PriorityAIController.prototype.behaviourFineCurrentTarget = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
	
	if (this.ship.scanClass == "CLASS_POLICE" && this.ship.target)
	{
		this.communicate("oolite_markForFines",this.ship.target,1);
		
		this.ship.markTargetForFines();
	}

	this.ship.performIdle();
}


PriorityAIController.prototype.behaviourFleeCombat = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);

	var cascade = this.getParameter("oolite_cascadeDetected");
	if (cascade != null)
	{
		if (cascade.distanceTo(this.ship) < this.scannerRange)
		{
			if (this.ship.defenseTargets.length > 0 && this.ship.defenseTargets[0].scanClass == "CLASS_MINE")
			{
				// if the mine is still visible, conventional fleeing works
				this.ship.target = this.ship.defenseTargets[0];
				this.ship.desiredRange = 30000;
				this.ship.performFlee();
				return;
			}
			else
			{
				if (this.ship.destination != cascade)
				{
					this.communicate("oolite_quiriumCascade",{},4);
				}
				this.ship.destination = cascade;
				this.ship.desiredRange = 30000;
				this.ship.desiredSpeed = 10*this.ship.maxSpeed;
				this.ship.performFlyToRangeFromDestination();
				return;
			}
		}
		else
		{
			this.setParameter("oolite_cascadeDetected",null);
		}
	}
	if (!this.ship.target || this.distance(this.ship.target) > this.scannerRange)
	{
		var aggressor = this.ship.AIPrimaryAggressor;
		if (aggressor && aggressor.isInSpace && this.distance(aggressor) < this.scannerRange)
		{
			this.ship.target = aggressor;
		}
		else
		{
			var dts = this.ship.defenseTargets;
			for (var i = 0 ; i < dts.length ; i++)
			{
				if (this.distance(dts[i]) < this.scannerRange && this.isFighting(dts[i]))
				{
					this.ship.target = dts[i];
					break;
				}
			}
		}
	}
	if (this.getParameter("oolite_lastFleeing") != null)
	{
		this.communicate("oolite_continueFleeing",this.ship.target,4);
	}
	else if (this.ship.energy < this.ship.maxEnergy / 4)
	{
		this.communicate("oolite_startFleeing",this.ship.target,3);
	}
	if (this.ship.target)
	{
		this.setParameter("oolite_lastFleeing",this.ship.target);
	}
	
	if (!this.__ltcache.oolite_considerWitchspaceFlee)
	{
		if (this.getParameter("oolite_flag_neverFleeToWitchspace") == null)
		{
			this.__ltcache.oolite_considerWitchspaceFlee = (this.ship.hasHyperspaceMotor && ((system.isInterstellarSpace && this.ship.fuel > 0) || (system.ID != this.ship.homeSystem && system.info.systemsInRange(this.ship.fuel).length > 0)))?1:-1;
		}
		else
		{
			this.__ltcache.oolite_considerWitchspaceFlee = -1;
		}
	}

	if (this.__ltcache.oolite_considerWitchspaceFlee == 1)
	{
		if (!this.__ltcache.oolite_witchspaceflee)
		{
			this.communicate("oolite_engageWitchspaceDriveFlee",{},2);
			this.__ltcache.oolite_witchspaceflee = clock.seconds + 15;
		}
		if (this.__ltcache.oolite_witchspaceflee < clock.seconds)
		{
			if (this.ship.exitSystem())
			{
				this.ship.notifyGroupOfWormhole();
				delete this.__ltcache.oolite_witchspaceflee;
			}
		}
	}

	this.ship.desiredRange = this.scannerRange;
	this.ship.performFlee();
}


/* Follow a ship, including to witchspace */
PriorityAIController.prototype.behaviourFollowCurrentTarget = function()
{
	if (this.ship.target)
	{
		var rt = this.ship.target;
	}
	else
	{
		var rt = this.getParameter("oolite_rememberedTarget");
	}
	if (!rt) {
		return;
	}
	this.ship.destination = rt.position;

	if (rt.status == "STATUS_ENTERING_WITCHSPACE")
	{
		if (this.getParameter("oolite_flag_witchspacePursuit"))
		{
			var pos = rt.position;
			var ws = system.wormholes;
			// most likely to be most recent
			for (var i=ws.length-1; i>=0; i--)
			{
				if (ws[i].position.distanceTo(pos) < 100)
				{
					this.setParameter("oolite_witchspaceWormhole",ws[i]);
					this.setParameter("oolite_rememberedTarget",null);
					break;
				}
			}

			this.ship.desiredRange = 0; // use wormhole
		}
		else
		{
			this.ship.destination = this.ship.position;
			this.ship.target = null;
			this.ship.setParameter("oolite_rememberedTarget",null);
		}
	}
	else
	{
		this.setParameter("oolite_rememberedTarget",rt);
		this.ship.desiredRange = 500+Math.random()*1000;
	}
	this.ship.desiredSpeed = this.ship.maxSpeed;
	this.behaviourApproachDestination();
}


/* Follow the group leader in a less organised way than escorting them */
PriorityAIController.prototype.behaviourFollowGroupLeader = function()
{
	if (!this.ship.group || !this.ship.group.leader)
	{
		var handlers = {};
		this.responsesAddStandard(handlers);
		this.applyHandlers(handlers);
		this.ship.performIdle();
	}
	else
	{
		var gl = this.ship.group.leader;
		this.ship.destination = gl.position.add(gl.vectorForward.multiply(gl.speed*10));
		this.ship.desiredRange = 500+Math.random()*1000;
		this.ship.desiredSpeed = Math.min(this.ship.maxSpeed,gl.speed*1.5);
		this.behaviourApproachDestination();
	}
}


PriorityAIController.prototype.behaviourGuardTarget = function()
{
	if (!this.ship.target)
	{
		this.ship.destination = this.ship.position;						
	}
	else
	{
		this.ship.destination = this.ship.target.position;
	}
	this.ship.desiredSpeed = this.cruiseSpeed();
	this.ship.desiredRange = 2500;
	this.behaviourApproachDestination();
}


PriorityAIController.prototype.behaviourJoinTargetGroup = function()
{
	if (this.ship.target && this.ship.target.group)
	{
		this.ship.target.group.addShip(this.ship);
		this.ship.group = this.ship.target.group;
	}
	this.ship.performIdle();
}


PriorityAIController.prototype.behaviourLandOnPlanet = function()
{
	this.ship.desiredSpeed = this.ship.maxSpeed / 4;
	this.ship.performLandOnPlanet();
	this.ship.AIScriptWakeTime = 0; // cancel reconsiderations
	this.applyHandlers({}); // cancel interruptions
	this.communicate("oolite_landingOnPlanet",{},4);
}


PriorityAIController.prototype.behaviourLeaveVicinityOfDestination = function()
{
	this.ship.desiredRange = 60000;
	this.ship.desiredSpeed = this.ship.maxSpeed;
	this.communicate("oolite_leaveVicinity",this.ship.target,3);
	this.behaviourApproachDestination();
}


PriorityAIController.prototype.behaviourLeaveVicinityOfTarget = function()
{
	if (!this.ship.target)
	{
		this.reconsiderNow();
		return;
	}
	this.ship.destination = this.ship.target.position;
	this.ship.desiredRange = 27500;
	this.ship.desiredSpeed = this.ship.maxSpeed;
	this.communicate("oolite_leaveVicinity",this.ship.target,3);
	this.behaviourApproachDestination();
}


PriorityAIController.prototype.behaviourMineTarget = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
	this.communicate("oolite_mining",{},4);
	this.ship.performMining();
}


PriorityAIController.prototype.behaviourOfferToEscort = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
	
	var possible = this.getParameter("oolite_scanResultSpecific");
	if (possible == null)
	{
		this.reconsiderNow();
	}
	else
	{
		if (this.ship.offerToEscort(possible))
		{
			// accepted
			this.reconsiderNow();
		}
		// if rejected, wait for next scheduled reconsideration
	}
}


PriorityAIController.prototype.behaviourPayOffPirates = function()
{
	this.ship.dumpCargo(this.ship.AIScript.oolite_intership.cargodemand);
	this.communicate("oolite_agreeingToDumpCargo",{"oolite_demandSize":this.ship.AIScript.oolite_intership.cargodemand},1);
	delete this.ship.AIScript.oolite_intership.cargodemand;
	this.ship.AIScript.oolite_intership.cargodemandpaid = true;
	this.behaviourFleeCombat();
}


PriorityAIController.prototype.behaviourReconsider = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
	this.reconsiderNow();
}


// Separate behaviour to EscortMothership in case we want to change it later
// This is the one to catch up with a distant mothership
PriorityAIController.prototype.behaviourRejoinMothership = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.responsesAddEscort(handlers);
	this.applyHandlers(handlers);
	// to consider: should this behaviour use injectors if
	// possible? so few escorts have them that it's probably not
	// worth it.
	this.ship.desiredRange = 0;
	this.ship.performEscort();
}


PriorityAIController.prototype.behaviourRepelCurrentTarget = function()
{
	this.setParameter("oolite_witchspaceEntry",null);

	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
	var target = this.ship.target
	if (!target || !target.isValid || !target.isShip)
	{
		this.reconsiderNow();
		return;
	}

	if (this.getParameter("oolite_flag_noSpecialThargoidReaction") != null)
	{
		if (this.ship.scanClass != "CLASS_THARGOID" && target.scanClass != "CLASS_THARGOID" && target.target.scanClass == "CLASS_THARGOID")
		{
			this.respondToThargoids(target.target,true);
			this.ship.performAttack();
			return;
		}
	}

	if (!this.isAggressive(target))
	{
		// repelling succeeded
		if (this.ship.escortGroup)
		{
			// also tell escorts to stop attacking it
			for (var i = 0 ; i < this.ship.escortGroup.ships.length ; i++)
			{
				this.ship.escortGroup.ships[i].removeDefenseTarget(target);
				if (this.ship.escortGroup.ships[i].target == target)
				{
					this.ship.escortGroup.ships[i].target = null;
				}
			}
		}
		this.ship.removeDefenseTarget(target);
		this.ship.target = null;
	}
	else
	{
		if (!this.ship.hasHostileTarget)
		{
			// entering attack mode
			this.broadcastAttackMessage(this.ship.target,"beginning",3);
			this.ship.requestHelpFromGroup();
		}
		else if (this.ship.target)
		{
			this.broadcastAttackMessage(this.ship.target,"continuing",4);
		}
		if (this.ship.energy == this.ship.maxEnergy && this.getParameter("oolite_flag_escortsCoverRetreat") && this.ship.escortGroup.count > 1)
		{
			// if has escorts, and is not yet taking damage, run and let
			// the escorts take them on
			this.ship.performFlee();
			return;
		}
		this.ship.performAttack();
	}
}


/* Standard "help the innocent" distress call response. Perhaps
 * there should be a 'blood in the water' response available
 * too... */
PriorityAIController.prototype.behaviourRespondToDistressCall = function()
{
	var aggressor = this.getParameter("oolite_distressAggressor");
	var sender = this.getParameter("oolite_distressSender");
	if (aggressor && aggressor.isShip && sender && sender.isShip)
	{
		if (sender.bounty > aggressor.bounty)
		{
			var tmp = sender;
			sender = aggressor;
			aggressor = tmp;
		}
		if (this.distance(aggressor) < this.scannerRange)
		{
			this.ship.target = aggressor;
			this.ship.performAttack();
			this.reconsiderNow();
			this.communicate("oolite_distressResponseAggressor",aggressor,2);
		}
		else
		{ // we can't actually see what's attacking the sender yet
			this.ship.destination = sender.position;
			this.ship.desiredRange = 1000+sender.collisionRadius+this.ship.collisionRadius;
			this.ship.desiredSpeed = 7 * this.ship.maxSpeed; // use injectors if possible
			this.ship.performFlyToRangeFromDestination();
			// and when we next reconsider, hopefully the aggressor will be on the scanner
			this.communicate("oolite_distressResponseSender",sender,2);
		}
	}
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
}


PriorityAIController.prototype.behaviourRobTarget = function()
{
	var demand = null;
	if (this.ship.group && this.ship.group.leader)
	{
		if (this.ship.group.leader.AIScript.oolite_intership && this.ship.group.leader.AIScript.oolite_intership.cargodemanded)
		{
			demand = this.ship.group.leader.AIScript.oolite_intership.cargodemanded;
		}
	}
	else
	{
		if (this.ship.AIScript.oolite_intership.cargodemanded)
		{
			demand = this.ship.AIScript.oolite_intership.cargodemanded;
		}
	}
	if (demand == null)
	{
		var target = this.ship.target;
		var hascargo = target.cargoSpaceCapacity; //cargoSpaceUsed?
		// blowing them up probably gets ~10%, so how much we feel
		// confident in demanding depends on how likely patrols
		// are to come along and interfere.
		demand = (hascargo/20);
		demand = demand * (1+Math.random()+(8-system.info.government)/8);
		// between 5% and 15% of cargo
		if (this.conditionCombatOddsExcellent())
		{
			// if we have overwhelming force, can get away with demanding more
			demand *= 1+Math.random();
			// between 5% and 30% of cargo
		}
		demand = Math.ceil(demand); // round it up so there's always at least 1

		var maxdemand = 0;
		var gc = 1;
		if (!this.ship.group)
		{
			if (this.ship.equipmentStatus("EQ_FUEL_SCOOPS") == "EQUIPMENT_OK")
			{
				maxdemand = this.ship.cargoSpaceAvailable;
			}
		}
		else
		{
			gc = this.ship.group.ships.length;
			for (var i = 0; i < gc ; i++)
			{
				var ship = this.ship.group.ships[i];
				if (ship.equipmentStatus("EQ_FUEL_SCOOPS") == "EQUIPMENT_OK")
				{
					maxdemand += ship.cargoSpaceAvailable;
				}
				else
				{
					gc--; // this ship can't help scoop
				}
			}
		}
		if (demand > maxdemand)
		{
			demand = maxdemand; // don't ask for more than we can carry
		}
		while (demand > gc * 5)
		{
			// asking for more than 5TC each probably means there
			// won't be time to pick it all up anyway
			demand = Math.ceil(demand/2);
		}
		if (demand < 2)
		{
			demand = 2;
		}

		/* Record our demand with the group leader */
		if (this.ship.group && this.ship.group.leader)
		{
			this.ship.group.leader.AIScript.oolite_intership.cargodemanded = demand;
		}
		else
		{
			this.ship.AIScript.oolite_intership.cargodemanded = demand;
		}
		/* Inform the victim of the demand, if possible */
		if (target.AIScript && target.AIScript.oolite_intership)
		{
			target.AIScript.oolite_intership.cargodemand = demand;
		}
		var commsparams = this.entityCommsParams(target);
		commsparams["oolite_demandSize"] = demand;
		this.ship.performAttack(); // must be before the comms message
		this.communicate("oolite_makePirateDemand",commsparams,1);
		this.ship.requestHelpFromGroup();
		// prevents choosing this ship twice in a row
		// either it beat us, or we just robbed it
		this.setParameter("oolite_lastPirateVictim",target);

		/*				}
						else
						{
						log(this.ship.displayName,"Already asked for "+demand); */
	}
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.applyHandlers(handlers);
	this.ship.performAttack();
	this.ship.requestHelpFromGroup();
}


PriorityAIController.prototype.behaviourSunskim = function()
{
	var handlers = {};
	this.responsesAddStandard(handlers);
	this.responsesAddScooping(handlers);
	this.applyHandlers(handlers);
	this.ship.performFlyToRangeFromDestination();
}


PriorityAIController.prototype.behaviourTumble = function()
{
	this.applyHandlers({});
	this.ship.performTumble();
}


/* Missile behaviours: have different standard handler sets */

PriorityAIController.prototype.behaviourMissileInterceptTarget = function()
{
	var handlers = {};
	this.responsesAddMissile(handlers);
	this.applyHandlers(handlers);
	if (this.ship.scriptInfo.oolite_missile_proximity)
	{
		this.ship.desiredRange = this.ship.scriptInfo.oolite_missile_proximity;
	}
	else
	{
		this.ship.desiredRange = 25;					
	}

	this.ship.performIntercept();
}

PriorityAIController.prototype.behaviourMissileInterceptCoordinates = function()
{
	var handlers = {};
	this.responsesAddMissile(handlers);
	this.applyHandlers(handlers);
	if (this.ship.scriptInfo.oolite_missile_proximity)
	{
		this.ship.desiredRange = this.ship.scriptInfo.oolite_missile_proximity;
	}
	else
	{
		this.ship.desiredRange = 25;					
	}
	var dest = this.getParameter("oolite_interceptCoordinates");
	if (dest == null)
	{
		return;
	}
	this.ship.destination = dest
	this.ship.desiredSpeed = this.ship.maxSpeed;
	this.ship.performFlyToRangeFromDestination();
	
	// if we have an intercept target, try to restore it
	var oldtarget = this.getParameter("oolite_interceptTarget");
	if (oldtarget && !oldtarget.isCloaked && oldtarget.isInSpace)
	{
		this.ship.target = oldtarget;
	}
}

PriorityAIController.prototype.behaviourMissileSelfDestruct = function() {
	this.ship.explode();
}



/* Station behaviours: have different standard handler sets */

PriorityAIController.prototype.behaviourStationLaunchDefenseShips = function() 
{
	if (system.sun && (system.sun.isGoingNova || system.sun.hasGoneNova))
	{
		return;
	}
	if (this.ship.target && this.isAggressive(this.ship.target))
	{
		this.ship.alertCondition = 3;
		this.ship.launchDefenseShip();
		this.communicate("oolite_launchDefenseShips",this.ship.target,3);
		this.ship.requestHelpFromGroup();
	}
	else if (this.ship.alertCondition > 1)
	{
		this.ship.alertCondition--;
	}
	var handlers = {};
	this.responsesAddStation(handlers);
	this.applyHandlers(handlers);
}


PriorityAIController.prototype.behaviourStationLaunchMiner = function() 
{
	if (system.sun && (system.sun.isGoingNova || system.sun.hasGoneNova))
	{
		return;
	}
	if (this.ship.alertCondition > 1)
	{
		this.ship.alertCondition--;
	}
	var handlers = {};
	this.responsesAddStation(handlers);
	this.applyHandlers(handlers);
	if (this.ship.group)
	{
		for (var i = 0 ; i < this.ship.group.ships.length ; i++)
		{
			if (this.ship.group.ships[i].primaryRole == "miner")
			{
				// only one in flight at once
				return;
			}
		}
	}
	this.communicate("oolite_launchMiner",this.ship.target,3);
	this.ship.launchMiner();
}


PriorityAIController.prototype.behaviourStationLaunchPatrol = function() 
{
	if (system.sun && (system.sun.isGoingNova || system.sun.hasGoneNova))
	{
		return;
	}
	if (this.ship.alertCondition > 1)
	{
		this.ship.alertCondition--;
	}
	var handlers = {};
	this.responsesAddStation(handlers);
	this.applyHandlers(handlers);

	if (this.ship.group)
	{
		for (var i = 0 ; i < this.ship.group.ships.length ; i++)
		{
			if (this.ship.group.ships[i].primaryRole == this.getParameter("oolite_stationPatrolRole"))
			{
				// only one in flight at once
				return;
			}
		}
	}
	this.communicate("oolite_launchPatrol",this.ship.target,3);
	this.ship.launchPatrol();
}


PriorityAIController.prototype.behaviourStationLaunchSalvager = function() 
{
	if (system.sun && (system.sun.isGoingNova || system.sun.hasGoneNova))
	{
		return;
	}
	if (this.ship.alertCondition > 1)
	{
		this.ship.alertCondition--;
	}
	this.communicate("oolite_launchSalvager",this.ship.target,3);
	this.ship.launchScavenger();
	
	var handlers = {};
	this.responsesAddStation(handlers);
	this.applyHandlers(handlers);
}


PriorityAIController.prototype.behaviourStationManageTraffic = function() 
{
	var handlers = {};
	this.responsesAddStation(handlers);
	this.applyHandlers(handlers);
	// does nothing special in this state, just waits around being a station
}


PriorityAIController.prototype.behaviourStationRespondToDistressCall = function() 
{
	if (system.sun && (system.sun.isGoingNova || system.sun.hasGoneNova))
	{
		return;
	}
	var aggressor = this.getParameter("oolite_distressAggressor");
	var sender = this.getParameter("oolite_distressSender");
	if (sender.bounty > aggressor.bounty)
	{
		var tmp = sender;
		sender = aggressor;
		aggressor = tmp;
	}
	if (this.distance(aggressor) < this.scannerRange)
	{
		this.ship.target = aggressor;
		this.ship.alertCondition = 3;
		this.ship.launchDefenseShip();
		this.communicate("oolite_distressResponseAggressor",aggressor,2);
		this.ship.requestHelpFromGroup();
	}
	else
	{
		this.communicate("oolite_distressResponseSender",sender,3);
	}

	var handlers = {};
	this.responsesAddStation(handlers);
	this.applyHandlers(handlers);
}


/* ****************** Configuration functions ************** */

/* Configurations. Configurations are set up actions for a behaviour
 * or behaviours. They can also be used on a fall-through conditional
 * to set parameters for later tests */

/*** Target acquisition configuration ***/

PriorityAIController.prototype.configurationAcquireCombatTarget = function()
{
	var target = this.ship.target;
	if (target && this.allied(this.ship,target))
	{
		// don't shoot at allies even if they have ended up as a target...
		this.ship.removeDefenseTarget(target);
		this.ship.target = null;
	}
	if (target && (target.scanClass == "CLASS_CARGO" || target.scanClass == "CLASS_BUOY"))
	{
		this.ship.removeDefenseTarget(target);
		this.ship.target = null;
	}
	/* Iff the ship does not currently have a target, select a new one
	 * from the defense target list. */
	if (target)
	{
		if (target.isInSpace)
		{
			return;
		}
		this.ship.removeDefenseTarget(target);
		this.ship.target = null;
	}
	var dts = this.ship.defenseTargets
	var dtsl = dts.length; // we need to iterate up this time
	var scan = this.scannerRange;
	for (var i = 0; i < dtsl ; i++)
	{
		if (this.distance(dts[i]) < scan)
		{
			if (!dts[i].isCloaked)
			{
				this.ship.target = dts[i];
				return;
			}
		}
		else
		{
			this.ship.removeDefenseTarget(dts[i]);
		}
	}
	if (this.ship.group != null)
	{
		var gs = this.ship.group.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (gs[i] != this.ship)
			{
				if (this.isFighting(gs[i]) && this.distance(gs[i].target) < scan && gs[i].target.isShip)
				{
					this.ship.target = gs[i].target;
					return;
				}
			}
		}
	}
	if (this.ship.escortGroup != null)
	{
		var gs = this.ship.escortGroup.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (gs[i] != this.ship)
			{
				if (this.isFighting(gs[i]) && this.distance(gs[i].target) < scan && gs[i].target.isShip)
				{
					this.ship.target = gs[i].target;
					return;
				}
			}
		}
	}
}


PriorityAIController.prototype.configurationAcquireDefensiveEscortTarget = function()
{
	if (this.ship.target && this.allied(this.ship,this.ship.target))
	{
		// don't shoot at allies even if they have ended up as a target...
		this.ship.removeDefenseTarget(this.ship.target);
		this.ship.target = null;
	}
	/* Preserve current target if still fighting (leader can send help
	 * request if needed) */
	if (this.ship.target)
	{
		if (this.ship.target.isInSpace && this.isAggressive(this.ship.target))
		{
			return;
		}
		this.ship.removeDefenseTarget(this.ship.target);
		this.ship.target = null;
	}

	if (this.ship.group && this.ship.group.leader)
	{
		var leader = this.ship.group.leader;
		if (this.isFighting(leader) && leader.target.target == leader && this.distance(leader.target) < this.scannerRange)
		{
			this.ship.target = leader.target;
		}
		else
		{
			var dts = leader.defenseTargets;
			for (var i = 0 ; i < dts.length ; i++)
			{
				if (dts[i].target == leader && this.isAggressive(dts[i]) && this.distance(dts[i]) < this.scannerRange)
				{
					if (!dts[i].isCloaked)
					{
						this.ship.target = dts[i];
					}
				}
			}
		}
	}
}


// TODO: reuse code from AcquireCombatTarget better
PriorityAIController.prototype.configurationAcquireHostileCombatTarget = function()
{
	if (this.ship.target && this.allied(this.ship,this.ship.target))
	{
		// don't shoot at allies even if they have ended up as a target...
		this.ship.removeDefenseTarget(this.ship.target);
		this.ship.target = null;
	}
	/* Iff the ship does not currently have a target, select a new one
	 * from the defense target list. */
	if (this.ship.target)
	{
		if (this.ship.target.isInSpace && this.isAggressive(this.ship.target))
		{
			return;
		}
		this.ship.removeDefenseTarget(this.ship.target);
		this.ship.target = null;
	}
	var dts = this.ship.defenseTargets
	for (var i = 0; i < dts.length ; i++)
	{
		if (this.distance(dts[i]) < this.scannerRange && this.isAggressive(dts[i]))
		{
			if (!dts[i].isCloaked)
			{
				this.ship.target = dts[0];
				return;
			}
		}
	}
	if (this.ship.group != null)
	{
		var gs = this.ship.group.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (gs[i] != this.ship)
			{
				if (this.isFighting(gs[i]) && this.distance(gs[i].target) < this.scannerRange && this.isAggressive(gs[i].target))
				{
					this.ship.target = gs[i].target;
					return;
				}
			}
		}
	}
	if (this.ship.escortGroup != null)
	{
		var gs = this.ship.escortGroup.ships;
		for (var i = gs.length-1 ; i >= 0 ; i--)
		{
			if (gs[i] != this.ship)
			{
				if (this.isFighting(gs[i]) && this.distance(gs[i].target) < this.scannerRange && this.isAggressive(gs[i].target))
				{
					this.ship.target = gs[i].target;
					return;
				}
			}
		}
	}
}


PriorityAIController.prototype.configurationAcquireOffensiveEscortTarget = function()
{
	if (this.ship.target && this.allied(this.ship,this.ship.target))
	{
		// don't shoot at allies even if they have ended up as a target...
		this.ship.removeDefenseTarget(this.ship.target);
		this.ship.target = null;
	}
	/* Preserve current target if still fighting */
	if (this.ship.target)
	{
		if (this.ship.target.isInSpace && this.isAggressive(this.ship.target))
		{
			return;
		}
		this.ship.removeDefenseTarget(this.ship.target);
		this.ship.target = null;
	}

	if (this.ship.group && this.ship.group.leader)
	{ 
		var leader = this.ship.group.leader;
		var lt;
		if ((lt = leader.target) && lt.isShip && leader.hasHostileTarget)
		{
			if (this.distance(lt) < this.scannerRange)
			{
				if (!lt.isCloaked)
				{
					this.ship.target = lt;
					this.ship.addDefenseTarget(lt);
				}
			}
		}
	}
}

PriorityAIController.prototype.configurationAcquirePlayerAsTarget = function()
{
	this.ship.target = player.ship;
}


PriorityAIController.prototype.configurationAcquireScannedTarget = function()
{
	this.ship.target = this.getParameter("oolite_scanResultSpecific");
}


PriorityAIController.prototype.configurationCheckScanner = function()
{
	if (this.getParameter("oolite_flag_scanIgnoresUnpowered") != null)
	{
		this.setParameter("oolite_scanResults",this.ship.checkScanner(true));
	}
	else
	{
		this.setParameter("oolite_scanResults",this.ship.checkScanner());
	}
	this.setParameter("oolite_scanResultSpecific",null);
}


/*** Navigation configuration ***/


PriorityAIController.prototype.configurationSelectPlanet = function()
{
	var possibles = system.planets;
	this.setParameter("oolite_selectedPlanet",possibles[Math.floor(Math.random()*possibles.length)]);
}


PriorityAIController.prototype.configurationSelectRandomTradeStation = function()
{
	var stations = system.stations;
	var chosenStation = null;
	if (this.ship.bounty == 0)
	{
		if (Math.random() < 0.9 && this.friendlyStation(system.mainStation))
		{
			this.setParameter("oolite_selectedStation",system.mainStation);
			return;
		}
	} 
	else if (this.ship.bounty <= this.fineThreshold())
	{
		if (Math.random() < 0.5 && this.friendlyStation(system.mainStation))
		{
			this.setParameter("oolite_selectedStation",system.mainStation);
			return;
		}
	}
	var friendlies = 0;
	for (var i = stations.length -1 ; i >= 0 ; i--)
	{
		var station = stations[i];
		if (this.friendlyStation(station))
		{
			friendlies++;
			// equivalent to filtering the list to only contain
			// friendlies, then picking a random element.
			if (Math.random() < 1/friendlies)
			{
				chosenStation = station;
			}
		}
	}
	this.setParameter("oolite_selectedStation",chosenStation);
	this.communicate("oolite_selectedStation",chosenStation,4);
}


PriorityAIController.prototype.configurationSelectShuttleDestination = function()
{
	var possibles = system.planets.concat(system.stations);
	var destinations1 = [];
	var destinations2 = [];
	for (var i = 0; i < possibles.length ; i++)
	{
		var possible = possibles[i];
		// travel at least a little way
		var distance = this.distance(possible);
		if (distance > possible.collisionRadius + 10000)
		{
			// must be friendly destination and not moving too fast
			if (possible.isPlanet || (this.friendlyStation(possible) && (possible.maxSpeed < this.ship.maxSpeed / 5)))
			{
				if (distance > system.mainPlanet.radius * 5)
				{
					destinations2.push(possible);
				}
				else
				{
					destinations1.push(possible);
				}
			}
		}
	}
	// no nearby destinations
	if (destinations1.length == 0)
	{
		destinations1 = destinations2;
	}
	// no destinations
	if (destinations1.length == 0)
	{
		return;
	}
	var destination = destinations1[Math.floor(Math.random()*destinations1.length)];
	if (destination.isPlanet)
	{
		this.setParameter("oolite_selectedPlanet",destination);
		this.setParameter("oolite_selectedStation",null);
	}
	else
	{
		this.setParameter("oolite_selectedStation",destination);
		this.setParameter("oolite_selectedPlanet",null);
	}
}


PriorityAIController.prototype.configurationSelectWitchspaceDestination = function()
{
	if (!this.ship.hasHyperspaceMotor)
	{
		this.setParameter("oolite_witchspaceDestination",null);
		return;
	}
	var preselected = this.getParameter("oolite_witchspaceDestination");
	if (preselected != system.ID && system.info.distanceToSystem(System.infoForSystem(galaxyNumber,preselected)) <= this.ship.fuel)
	{
		// we've already got a destination
		return;
	}
	var possible = system.info.systemsInRange(this.ship.fuel);
	if (possible.length > 0)
	{
		var selected = possible[Math.floor(Math.random()*possible.length)];
		this.setParameter("oolite_witchspaceDestination",selected.systemID);
		this.communicate("oolite_selectedWitchspaceDestination",{"oolite_witchspaceDestination":selected.name},4);
	}
	else
	{
		this.setParameter("oolite_witchspaceDestination",null);
	}
}


PriorityAIController.prototype.configurationSelectWitchspaceDestinationInbound = function()
{
	if (this.ship.homeSystem == this.ship.destinationSystem)
	{
		return this.configurationSelectWitchspaceDestination();
	}
	this.setWitchspaceRouteTo(this.ship.homeSystem);
}


PriorityAIController.prototype.configurationSelectWitchspaceDestinationOutbound = function()
{
	if (this.ship.homeSystem == this.ship.destinationSystem)
	{
		return this.configurationSelectWitchspaceDestination();
	}
	this.setWitchspaceRouteTo(this.ship.destinationSystem);
}


/*** Destination configuration ***/


PriorityAIController.prototype.configurationMissileAdjustSpread = function()
{
	var near = this.getParameter("oolite_scanResultSpecific");
	if (!near)
	{
		this.ship.destination = this.ship.target.position;
		this.ship.desiredRange = 100;
		this.ship.desiredSpeed = this.ship.maxFlightSpeed;
	}
	else
	{
		this.ship.destination = near.position.add(Vector3D.randomDirection(20));
		this.ship.desiredRange = 1000;
		this.ship.desiredSpeed = this.ship.maxFlightSpeed;
	}
}


PriorityAIController.prototype.configurationSetDestinationToHomeStation = function()
{
	var home = this.homeStation();
	if (home != null)
	{
		this.ship.destination = home.position;
		this.ship.desiredRange = 15000;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
	else
	{
		this.ship.destination = this.ship.position;
		this.ship.desiredRange = 0;
	}
}


PriorityAIController.prototype.configurationSetDestinationToGroupLeader = function()
{
	if (!this.ship.group || !this.ship.group.leader)
	{
		this.ship.destination = this.ship.position;
	}
	else
	{
		this.ship.destination = this.ship.group.leader.position;
	}
	this.ship.desiredRange = 2000;
	this.ship.desiredSpeed = this.ship.maxSpeed;
}


PriorityAIController.prototype.configurationSetDestinationToMainPlanet = function()
{
	if (system.mainPlanet)
	{
		this.ship.destination = system.mainPlanet.position;
		this.ship.desiredRange = system.mainPlanet.radius * 3;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToMainStation = function()
{
	this.ship.destination = system.mainStation.position;
	this.ship.desiredRange = 15000;

	this.ship.desiredSpeed = this.cruiseSpeed();
}


PriorityAIController.prototype.configurationSetDestinationToNearestFriendlyStation = function()
{
	var stations = system.stations;
	var threshold = 1E16;
	var chosenStation = null;
	for (var i = 0 ; i < stations.length ; i++)
	{
		var station = stations[i];
		if (this.friendlyStation(station))
		{
			var distance = this.distance(station);
			if (distance < threshold)
			{
				threshold = distance;
				chosenStation = station;
			}
		}
	}
	if (chosenStation == null)
	{
		this.ship.destination = this.ship.position;
		this.ship.desiredRange = 0;
	}
	else
	{
		this.ship.destination = chosenStation.position;
		this.ship.desiredRange = 15000;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToNearestHostileStation = function()
{
	var stations = system.stations;
	var threshold = 1E16;
	var chosenStation = null;
	for (var i = 0 ; i < stations.length ; i++)
	{
		var station = stations[i];
		if (this.hostileStation(station))
		{
			var distance = this.distance(station);
			if (distance < threshold)
			{
				threshold = distance;
				chosenStation = station;
			}
		}
	}
	if (chosenStation == null)
	{
		this.ship.destination = this.ship.position;
		this.ship.desiredRange = 0;
	}
	else
	{
		this.ship.destination = chosenStation.position;
		this.ship.desiredRange = 15000;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToNearestStation = function()
{
	if (this.__ltcache.oolite_nearestStation)
	{
		this.ship.destination = this.__ltcache.oolite_nearestStation.position;
		this.ship.desiredRange = 15000;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
	else
	{
		this.ship.destination = this.ship.position;
		this.ship.desiredRange = 0;
	}
}

PriorityAIController.prototype.configurationSetDestinationToNearestWormhole = function()
{
	var dist = 1E16;
	var holes = system.wormholes;
	this.ship.desiredRange = 0;
	this.ship.desiredSpeed = this.ship.maxSpeed;
	for (var i=holes.length-1; i >= 0 ; i--)
	{
		var hole = holes[i];
		var hdist = this.distance(hole);
		if (hole.expiryTime > clock.adjustedSeconds && hdist < dist)
		{
			this.ship.destination = hole.position;
			dist = hdist;
		}
	}
	if (dist >= 1E15)
	{
		this.ship.destination = this.ship.position;
		this.ship.desiredRange = 1000;
	}
}


PriorityAIController.prototype.configurationSetDestinationToPirateLurk = function()
{
	var lurk = this.getParameter("oolite_pirateLurk");
	if (lurk != null)
	{
		this.ship.destination = lurk;
	}
	else
	{
		if (this.distance(system.sun) > system.sun.radius*3 && this.distance(system.mainPlanet) > system.mainPlanet.radius * 3)
		{
			var p = this.ship.position;
			// if already on a lane, stay on it
			if (p.z < (system.mainPlanet.position.z - system.mainPlanet.radius*2) && ((p.x * p.x) + (p.y * p.y)) < this.scannerRange * this.scannerRange * 4)
			{
				lurk = p;
			}
			else if (p.subtract(system.mainPlanet).direction().dot(p.subtract(system.sun).direction()) < -0.9)
			{
				lurk = p;
			}
			else if (p.direction().dot(system.sun.position.direction()) > 0.9)
			{
				lurk = p;
			}
		}
		if (lurk == null)
		{
			// not on a lane, or too close to a sun/planet
			var code;
			var choice = Math.random();
			if (choice < 0.7)
			{
				code = "LANE_WP";
			}
			else if (choice < 0.8)
			{
				code = "LANE_PS";
			}
			else if (choice < 0.9)
			{
				code = "LANE_WS";
			}
			else
			{
				code = "WITCHPOINT";
			}
			lurk = system.locationFromCode(code);
		}
		this.setParameter("oolite_pirateLurk",lurk);
	}
	this.ship.desiredRange = 1000;
	this.ship.desiredSpeed = this.cruiseSpeed();
}


PriorityAIController.prototype.configurationSetDestinationToScannedTarget = function()
{
	var ship = this.getParameter("oolite_scanResultSpecific");
	if (ship && ship.isShip)
	{
		this.ship.destination = ship.position;
		this.ship.desiredRange = 4000;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToSelectedPlanet = function()
{
	var planet = this.getParameter("oolite_selectedPlanet");
	if (planet)
	{
		this.ship.destination = planet.position;
		this.ship.desiredRange = planet.radius+100;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToSelectedStation = function()
{
	var station = this.getParameter("oolite_selectedStation");
	if (station)
	{
		this.ship.destination = station.position;
		this.ship.desiredRange = 15000;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToSunskimEnd = function()
{
	if (system.sun)
	{
		var direction = Vector3D.random().cross(this.ship.position.subtract(system.sun.position));
		// 2km parallel to local sun surface for every LY of fuel
		this.ship.destination = this.ship.position.add(direction.multiply(2000*(7-this.ship.fuel)));
		// max sunskim height is sqrt(4/3) radius 
		this.ship.desiredRange = 0;
		this.ship.desiredSpeed = this.ship.maxSpeed;
	}
}


PriorityAIController.prototype.configurationSetDestinationToSunskimStart = function()
{
	if (system.sun)
	{
		this.ship.destination = system.sun.position;
		// max sunskim height is sqrt(4/3) radius 
		this.ship.desiredRange = system.sun.radius * 1.125;
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToWaypoint = function()
{
	if (this.getParameter("oolite_waypoint") != null && this.getParameter("oolite_waypointRange") != null)
	{
		this.ship.destination = this.getParameter("oolite_waypoint");
		this.ship.desiredRange = this.getParameter("oolite_waypointRange");
		this.ship.desiredSpeed = this.cruiseSpeed();
	}
}


PriorityAIController.prototype.configurationSetDestinationToWitchpoint = function()
{
	this.ship.destination = new Vector3D(0,0,0);
	this.ship.desiredRange = 10000;
	this.ship.desiredSpeed = this.cruiseSpeed();
}


PriorityAIController.prototype.configurationSetWaypoint = function()
{
	var gen = this.getWaypointGenerator();
	if(gen != null)
	{
		gen.call(this);
		this.configurationSetDestinationToWaypoint();
	}
}




/*** Docking configurations ***/



PriorityAIController.prototype.configurationSetNearbyFriendlyStationForDocking = function()
{
	if (this.friendlyStation(this.__ltcache.oolite_nearestStation))
	{
		if (this.distance(this.__ltcache.oolite_nearestStation) < this.scannerRange)
		{
			this.setParameter("oolite_dockingStation",this.__ltcache.oolite_nearestStation)
			return;
		}
	}
}


PriorityAIController.prototype.configurationSetHomeStationForDocking = function()
{
	var station = this.homeStation();
	if (station)
	{
		this.setParameter("oolite_dockingStation",station)
		return;
	}
}


PriorityAIController.prototype.configurationSetSelectedStationForDocking = function()
{
	this.setParameter("oolite_dockingStation",this.getParameter("oolite_selectedStation"));
}


/*** Miscellaneous configuration ***/


PriorityAIController.prototype.configurationAppointGroupLeader = function()
{
	if (this.ship.group && !this.ship.group.leader)
	{
		this.ship.group.leader = this.ship.group.ships[0];
		for (var i = 0 ; i < this.ship.group.ships.length ; i++)
		{
			if (this.ship.group.ships[i].hasHyperspaceMotor)
			{
				// bias towards jump-capable ships
				this.ship.group.leader = this.ship.group.ships[i];
				break;
			}
		}
		var leadrole = this.getParameter("oolite_leaderRole")
		if (leadrole != null)
		{
			this.ship.group.leader.primaryRole = leadrole;
		}
	}
}

PriorityAIController.prototype.configurationEscortGroupLeader = function()
{
	if (!this.ship.group || !this.ship.group.leader || this.ship.group.leader == this.ship)
	{
		return;
	}
	if (this.ship.group.leader.escortGroup && this.ship.group.leader.escortGroup.containsShip(this.ship))
	{
		return;
	}
	var escrole = this.getParameter("oolite_escortRole")
	if (escrole != null)
	{
		var oldrole = this.ship.primaryRole;
		this.ship.primaryRole = escrole;
		var accepted = this.ship.offerToEscort(this.ship.group.leader);
		if (!accepted)
		{
			this.ship.primaryRole = oldrole;
		}
	}
	
}


PriorityAIController.prototype.configurationForgetCargoDemand = function()
{
	/*				if (this.ship.group && this.ship.group.leader && this.ship.group.leader.AIScript.oolite_intership.cargodemanded)
					{
					delete this.ship.group.leader.AIScript.oolite_intership.cargodemanded;
					} */ // not sure about this, maybe not needed

	if (this.ship.AIScript.oolite_intership.cargodemanded)
	{
		delete this.ship.AIScript.oolite_intership.cargodemanded;
		delete this.ship.AIScript.oolite_intership.cargodemandmet;
		// and make the group lose the cargo count from the last demand
		if (this.ship.group)
		{
			for (var i = 0 ; i < this.ship.group.ships.length ; i++)
			{
				var ship = this.ship.group.ships[i];
				if (ship.AIScript && ship.AIScript.oolite_priorityai)
				{
					ship.AIScript.oolite_priorityai.setParameter("oolite_cargoDropped",0);
				}
			}
		}
	}
}


PriorityAIController.prototype.configurationLeaveEscortGroup = function()
{
	if (this.ship.group && this.ship.group.leader && this.ship.group.leader != this.ship && this.ship.group.leader.escortGroup && this.ship.group.leader.escortGroup.containsShip(this.ship))
	{
		this.ship.group.leader.escortGroup.removeShip(this.ship);
		if (this.ship.group)
		{
			this.ship.group.removeShip(this.ship);
			this.ship.group = null;
		}
	}
}


PriorityAIController.prototype.configurationLightsOff = function()
{
	this.ship.lightsActive = false;
}


PriorityAIController.prototype.configurationLightsOn = function()
{
	this.ship.lightsActive = true;
}


// remote controlled ships get same accuracy as lead ship
PriorityAIController.prototype.configurationSetRemoteControl = function()
{
	var group = this.ship.group;
	if (group && group.leader)
	{
		this.ship.accuracy = group.leader.accuracy;
	}
}


/*** Station configuration ***/

PriorityAIController.prototype.configurationStationReduceAlertLevel = function() 
{
	if (this.ship.alertCondition > 1)
	{
		this.ship.alertCondition--;
	}
}

PriorityAIController.prototype.configurationStationValidateTarget = function()
{
	if (this.ship.target)
	{
		if(this.distance(this.ship.target) > this.scannerRange)
		{
			// station behaviour does not generally validate target
			this.ship.target = null;
		}
	}
}

/* ****************** Response definition functions ************** */

/* Standard state-machine responses. These set up a set of standard
 * state machine responses where incoming events will cause reasonable
 * default behaviour and often force a reconsideration of
 * priorities. Many behaviours will need to supplement the standard
 * responses with additional definitions. */

PriorityAIController.prototype.responsesAddStandard = function(handlers) 
{
	handlers.approachingPlanetSurface = this.responseComponent_standard_approachingPlanetSurface;
	handlers.cargoDumpedNearby = this.responseComponent_standard_cargoDumpedNearby;
	handlers.cascadeWeaponDetected = this.responseComponent_standard_cascadeWeaponDetected;
	handlers.commsMessageReceived = this.responseComponent_standard_commsMessageReceived;
	handlers.distressMessageReceived = this.responseComponent_standard_distressMessageReceived;
	handlers.escortAccepted = this.responseComponent_standard_escortAccepted;
	handlers.helpRequestReceived = this.responseComponent_standard_helpRequestReceived;
	handlers.offenceCommittedNearby = this.responseComponent_standard_offenceCommittedNearby;
	handlers.shipAcceptedEscort = this.responseComponent_standard_shipAcceptedEscort;
	handlers.shipAttackedOther = this.responseComponent_standard_shipAttackedOther;
	handlers.shipAttackedWithMissile = this.responseComponent_standard_shipAttackedWithMissile;
	handlers.shipAttackerDistracted = this.responseComponent_standard_shipAttackerDistracted;
	handlers.shipBeingAttacked = this.responseComponent_standard_shipBeingAttacked;
	handlers.shipBeingAttackedUnsuccessfully = this.responseComponent_standard_shipBeingAttackedUnsuccessfully;
	handlers.shipFiredMissile = this.responseComponent_standard_shipFiredMissile;
	handlers.shipKilledOther = this.responseComponent_standard_shipKilledOther;
	handlers.shipLaunchedEscapePod = this.responseComponent_standard_shipLaunchedEscapePod;
	handlers.shipLaunchedFromStation = this.responseComponent_standard_shipLaunchedFromStation;
	handlers.shipWillEnterWormhole = this.responseComponent_standard_shipWillEnterWormhole;
	handlers.wormholeSuggested = this.responseComponent_standard_wormholeSuggested;

	// slightly different settings if pursuing to witchspace expected
	if (!this.getParameter("oolite_flag_witchspacePursuit"))
	{
		handlers.shipTargetLost = this.responseComponent_standard_shipTargetLost;
		handlers.playerWillEnterWitchspace = this.responseComponent_standard_playerWillEnterWitchspace;
	}
	else
	{
		handlers.playerWillEnterWitchspace = this.responseComponent_trackPlayer_playerWillEnterWitchspace;
		handlers.shipTargetLost = this.responseComponent_expectWitchspace_shipTargetLost;
	}

	// TODO: more event handlers
}

/* Additional handlers for use while docking */
PriorityAIController.prototype.responsesAddDocking = function(handlers) 
{
	handlers.stationWithdrewDockingClearance = this.responseComponent_docking_stationWithdrewDockingClearance;
	handlers.shipAchievedDesiredRange = this.responseComponent_docking_shipAchievedDesiredRange;
}

/* Override of standard handlers for use while escorting */
PriorityAIController.prototype.responsesAddEscort = function(handlers) 
{
	handlers.helpRequestReceived = this.responseComponent_escort_helpRequestReceived;
	handlers.escortDock = this.responseComponent_escort_escortDock;
}

/* Additional handlers for scooping */
PriorityAIController.prototype.responsesAddScooping = function(handlers)
{
	handlers.shipAchievedDesiredRange = this.responseComponent_scooping_shipAchievedDesiredRange
	handlers.shipScoopedFuel = this.responseComponent_scooping_shipScoopedFuel;
}

// shorter list than before
PriorityAIController.prototype.responsesAddStation = function(handlers) 
{
	handlers.cascadeWeaponDetected = this.responseComponent_station_cascadeWeaponDetected;
	handlers.commsMessageReceived = this.responseComponent_station_commsMessageReceived;
	handlers.distressMessageReceived = this.responseComponent_station_distressMessageReceived;
	handlers.helpRequestReceived = this.responseComponent_station_helpRequestReceived;
	handlers.offenceCommittedNearby = this.responseComponent_station_offenceCommittedNearby;
	handlers.shipAttackedOther = this.responseComponent_station_shipAttackedOther;
	handlers.shipAttackedWithMissile = this.responseComponent_station_shipAttackedWithMissile;
	handlers.shipBeingAttacked = this.responseComponent_station_shipBeingAttacked;
	handlers.shipFiredMissile = this.responseComponent_station_shipFiredMissile;
	handlers.shipKilledOther = this.responseComponent_station_shipKilledOther;
	handlers.shipTargetLost = this.responseComponent_station_shipTargetLost;
}


PriorityAIController.prototype.responsesAddMissile = function(handlers) {
	handlers.commsMessageReceived = this.responseComponent_missile_commsMessageReceived;
	handlers.shipHitByECM = this.responseComponent_missile_shipHitByECM;
	handlers.shipTargetCloaked = this.responseComponent_missile_shipTargetCloaked;
	handlers.shipTargetLost = this.responseComponent_missile_shipTargetLost;
	handlers.shipAchievedDesiredRange = this.responseComponent_missile_shipAchievedDesiredRange;
}


/* ******************* Response components *********************** */

/* Response components. These are standard response component
 * functions which can be passed by reference to save on variable
 * destruction/creation */


PriorityAIController.prototype.responseComponent_standard_approachingPlanetSurface = function()
{
	if (this.getParameter("oolite_flag_allowPlanetaryLanding"))
	{
		this.ship.desiredSpeed = this.ship.maxSpeed / 4;
		this.ship.performLandOnPlanet();
		this.ship.AIScriptWakeTime = 0; // cancel reconsiderations
		this.applyHandlers({}); // cancel interruptions
		this.communicate("oolite_landingOnPlanet",{},4);
	}
	else
	{
		this.reconsiderNow();
	}
}


PriorityAIController.prototype.responseComponent_standard_cargoDumpedNearby = function(cargo,ship)
{
	if (this.getParameter("oolite_flag_watchForCargo"))
	{
		var previously = this.getParameter("oolite_cargoDropped");
		if (previously == null)
		{
			previously = 0;
		}
		previously++;
		this.setParameter("oolite_cargoDropped",previously);
	}
}


PriorityAIController.prototype.responseComponent_standard_cascadeWeaponDetected = function(weapon)
{
	this.ship.clearDefenseTargets();
	this.ship.addDefenseTarget(weapon);
	this.setParameter("oolite_cascadeDetected",weapon.position);
	this.ship.target = weapon;
	this.ship.performFlee();
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_commsMessageReceived = function(message,sender)
{
	/* If the sender is hostile to us, and we're not obviously in
	 * combat, attack the sender: deals with pirate demand case */
	if (sender.target == this.ship && !this.ship.hasHostileTarget && sender.hasHostileTarget)
	{
		this.ship.target = sender;
		this.ship.performAttack();
		this.reconsiderNow();
	}
	this.noteCommsHeard();
}


PriorityAIController.prototype.responseComponent_standard_distressMessageReceived = function(aggressor, sender)
{
	if (this.getParameter("oolite_flag_listenForDistressCall") != true)
	{
		return;
	}
	if (this.ship.scanClass == "CLASS_POLICE" || (this.ship.isStation && this.ship.allegiance == "galcop"))
	{
		if (this.distance(aggressor) < this.scannerRange)
		{
			aggressor.bounty |= 8;
		}
	}
	this.setParameter("oolite_distressAggressor",aggressor);
	this.setParameter("oolite_distressSender",sender);
	this.setParameter("oolite_distressTimestamp",clock.adjustedSeconds);
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_escortAccepted = function(escort)
{
	this.communicate("oolite_escortAccepted",escort,2);
}


// overridden for escorts
PriorityAIController.prototype.responseComponent_standard_helpRequestReceived = function(ally, enemy)
{
	if (this.allied(this.ship,enemy))
	{
		return;
	}
	this.ship.addDefenseTarget(enemy);
	if (enemy.scanClass == "CLASS_MISSILE" && this.distance(enemy) < this.scannerRange && this.ship.equipmentStatus("EQ_ECM") == "EQUIPMENT_OK")
	{
		this.ship.fireECM();
	}
	if (enemy.scanClass == "CLASS_THARGOID" && this.ship.scanClass != "CLASS_THARGOID" && (!this.ship.target || this.ship.target.scanClass != "CLASS_THARGOID"))
	{
		if (this.respondToThargoids(enemy,false))
		{
			this.reconsiderNow();
			return; // not in a combat mode
		}
	}

	if (!this.ship.hasHostileTarget)
	{
		this.reconsiderNow();
		return; // not in a combat mode
	}
	if (ally.energy / ally.maxEnergy < this.ship.energy / this.ship.maxEnergy)
	{
		// not in worse shape than ally
		if (this.ship.target.target != ally && this.ship.target != ally.target)
		{
			// not already helping, go for it...
			this.communicate("oolite_startHelping",enemy,4);
			this.ship.target = enemy;
			this.reconsiderNow();
		}
	}
}


PriorityAIController.prototype.responseComponent_standard_offenceCommittedNearby = function(attacker, victim)
{
	if (this.ship == victim) return; // other handlers can get this one
	if (this.distance(attacker) > this.scannerRange) return; // can't mark what you can't see
	if (this.getParameter("oolite_flag_markOffenders")) 
	{
		if (attacker.bounty == 0 && victim.bounty == 0)
		{
			if ((this.shipInRoleCategory(victim,"oolite-police-dislike") && !this.shipInRoleCategory(attacker,"oolite-police-dislike")) ||
				(this.shipInRoleCategory(attacker,"oolite-police-like") && !this.shipInRoleCategory(victim,"oolite-police-like")))
			{
				if (victim.hasHostileTarget)
				{
					// they're both fighting; it's likely that the
					// attacker is fighting in self-defence; so swap them
					var tmp = victim;
					victim = attacker;
					attacker = tmp;
				}
			}
		}
		if (!attacker.isPlayer && attacker.target != victim)
		{
			// ignore friendly fire if they were aiming at a pirate/assassin
			if (attacker.bounty == 0 && attacker.target && this.shipInRoleCategory(attacker.target,"oolite-police-dislike"))
			{
				// but we might go after the pirate/assassin ourselves in a bit
				this.ship.addDefenseTarget(attacker.target);
				return;
			}
		}
		else if (attacker.isPlayer && this.ignorePlayerFriendlyFire())
		{
			this.communicate("oolite_friendlyFire",attacker,3);
			return;
		}

		if (attacker.bounty & 7 != 7)
		{
			this.communicate("oolite_offenceDetected",attacker,3);
		}
		else
		{
			this.communicate("oolite_offenceDetected",attacker,4);
		}
		attacker.setBounty(attacker.bounty | 7,"seen by police");
		this.ship.addDefenseTarget(attacker);
		this.reconsiderNow();
	}
}


PriorityAIController.prototype.responseComponent_standard_playerWillEnterWitchspace = function()
{
	var wormhole = this.getParameter("oolite_witchspaceWormhole");
	if (wormhole != null && wormhole.isWormhole)
	{
		this.ship.enterWormhole(wormhole);
	} 
}


PriorityAIController.prototype.responseComponent_standard_shipAcceptedEscort = function(mother)
{
	this.communicate("oolite_escortMotherAccepted",mother,2);
}


// not always applied
PriorityAIController.prototype.responseComponent_standard_shipAchievedDesiredRange = function() 
{
	var waypoints = this.getParameter("oolite_waypoints");
	if (waypoints != null)
	{
		if (waypoints.length > 0)
		{
			waypoints.pop();
			if (waypoints.length == 0)
			{
				waypoints = null;
			}
			this.setParameter("oolite_waypoints",waypoints);
		}
	}
	else
	{
		var patrol = this.getParameter("oolite_waypoint");
		if (patrol != null && this.ship.destination.distanceTo(patrol) < 1000+this.getParameter("oolite_waypointRange"))
		{
			// finished patrol to waypoint
			// clear route
			this.communicate("oolite_waypointReached",{},3);
			this.setParameter("oolite_waypoint",null);
			this.setParameter("oolite_waypointRange",null);
			if (this.getParameter("oolite_flag_patrolStation"))
			{
				if (this.ship.group)
				{
					var station = this.ship.group.leader;
					if (station != null && station.isStation)
					{
						this.communicate("oolite_patrolReportIn",station,4);
						this.ship.patrolReportIn(station);
					}
				}
			}
		}
	}
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_shipAttackedOther = function(other)
{
	this.communicate("oolite_hitTarget",other,4);
}


PriorityAIController.prototype.responseComponent_standard_shipAttackedWithMissile = function(missile,whom)
{
	if (this.getParameter("oolite_flag_sendsDistressCalls"))
	{
		this.broadcastDistressMessage();
	}
	if (this.ship.equipmentStatus("EQ_ECM") == "EQUIPMENT_OK")
	{
		this.ship.fireECM();
		this.ship.addDefenseTarget(missile);
		this.ship.addDefenseTarget(whom);
		// but don't reconsider immediately, because the ECM will
		// probably get it
	}
	else
	{
		this.communicate("oolite_incomingMissile",whom,3);
		this.ship.addDefenseTarget(missile);
		this.ship.addDefenseTarget(whom);
		if (this.ship.target && this.ship.target.scanClass == "CLASS_MISSILE")
		{
			// keep fleeing first missile
			var tmp = this.ship.target;
			this.ship.target = missile;
			this.ship.requestHelpFromGroup(); // anyone got an ECM?
			this.ship.target = tmp;
		}
		else
		{
			this.ship.target = missile;
			this.ship.requestHelpFromGroup(); // anyone got an ECM?
		}
		this.reconsiderNow();
	}
}


PriorityAIController.prototype.responseComponent_standard_shipAttackerDistracted = function(whom)
{
	if (this.ship.scanClass != "CLASS_THARGOID" && whom.scanClass == "CLASS_THARGOID" && (!this.ship.target || this.ship.target.scanClass != "CLASS_THARGOID"))
	{
		// frying pan, fire
		if (this.respondToThargoids(whom,false))
		{
			this.reconsiderNow();
			return;
		}
	}

	var last = this.getParameter("oolite_lastAssist");
	if (last != whom)
	{
		if (whom.isPlayer)
		{
			this.communicate("oolite_thanksForHelp",whom,1);
		}
		else
		{
			this.communicate("oolite_thanksForHelp",whom,3);
		}
		if (this.ship.scanClass == "CLASS_POLICE")
		{
			if (whom.scanClass != "CLASS_POLICE" && whom.scanClass != "CLASS_THARGOID" && whom.bounty > 0)
			{
				whom.setBounty(whom.bounty*4/5,"assisting police");
			}
		}
		this.setParameter("oolite_lastAssist",whom);
	}
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_shipBeingAttacked = function(whom)
{
	if (whom.target != this.ship)
	{
		if (!whom.isPlayer)
		{
			// was accidental
			if (this.allied(whom,this.ship))
			{
				this.communicate("oolite_friendlyFire",whom,3);
				// ignore it
				return;
			}
			if (Math.random() > 0.1)
			{
				// usually ignore it anyway as we know they didn't mean to
				return;
			}
		}
		// only ignore the player's friendly fire if already in combat
		else if (this.conditionInCombat() && this.ignorePlayerFriendlyFire())
		{
			// send warning communication
			this.communicate("oolite_friendlyFire",whom,2);
			return;
		}
	}
	if (this.getParameter("oolite_flag_markOffenders"))
	{
		if (this.ship.scanClass == "CLASS_POLICE")
		{
			whom.setBounty(whom.bounty | 15,"attacked police");
		}
		else if (this.ship == system.mainStation)
		{
			whom.setBounty(whom.bounty | 63,"attacked main station");
		}
	}
	if (this.ship.target && !this.ship.hasHostileTarget)
	{
		// don't get confused and shoot the station!
		this.ship.target = null;
	}
	if (this.getParameter("oolite_flag_sendsDistressCalls"))
	{
		this.broadcastDistressMessage();
	}
	if (this.ship.isFleeing)
	{
		this.communicate("oolite_surrender",{},3);
		if (whom.isPlayer && this.ship.AIScript.oolite_intership.cargodemandpaid && this.ship.energy < 16)
		{
			/* Firing on surrendered traders means you're probably
			 * trying to kill them rather than rob them. Prefer
			 * replacing pirate roles. */
			if (!this.__ltcache.oolite_assassinPlayer)
			{
				this.__ltcache.oolite_assassinPlayer = true;
				var pws = player.roleWeights;
				var found = false;
				for (var i=pws.length-1;i>=0;i--)
				{
					if (pws[i] == "pirate")
					{
						player.setPlayerRole("assassin-player",i);
						found = true;
						break;
					}
				}
				if (!found)
				{
					player.setPlayerRole("assassin-player");
				}
			}
		}
	}
	if ((whom.scanClass == "CLASS_THARGOID") && (this.ship.scanClass != "CLASS_THARGOID") && (!this.ship.target || this.ship.target.scanClass != "CLASS_THARGOID"))
	{
		if (this.respondToThargoids(whom,true))
		{
			this.reconsiderNow();
			return;
		}
	}
	if (whom.scanClass != "CLASS_THARGOID" && this.ship.target && this.ship.target.scanClass == "CLASS_THARGOID")
	{
		// now is not a good time. Everything is friendly fire right now...
		return;
	}
	if (this.ship.defenseTargets.indexOf(whom) < 0)
	{
		this.communicate("oolite_newAssailiant",whom,3);
		this.ship.addDefenseTarget(whom);
	}
	else 
	{
		// else we know about this attacker already
		if (this.ship.energy * 4 < this.ship.maxEnergy)
		{
			this.communicate("oolite_attackLowEnergy",whom,2);
			// but at low energy still reconsider
			this.ship.requestHelpFromGroup();
		}
	}
	if (this.ship.hasHostileTarget)
	{
		if (!this.isAggressive(this.ship.target))
		{
			// if our current target is running away, switch targets
			this.noteDistraction(whom);
			this.ship.target = whom;
		}
		else if (this.ship.target.target != this.ship)
		{
			// if our current target isn't aiming at us
			if (Math.random() < 0.2)
			{
				// occasionally switch
				this.noteDistraction(whom);
				this.ship.target = whom;
			}
		}
		else
		{
			// tend to switch to the more dangerous one
			if (this.threatAssessment(whom,true) > this.threatAssessment(this.ship.target,true) * (1+Math.random()))
			{
				this.noteDistraction(whom);
				this.ship.target = whom;
			}
		}
	}
	// TODO: a rep for not accepting surrenders should have an effect here
	else if (whom.isPlayer && !this.ship.AIScript.oolite_intership.cargodemand && !this.ship.AIScript.oolite_intership.cargodemandpaid)
	{
		// don't need to check here: most AIs won't check if a cargo
		// demand exists, so setting it is harmless
		if (this.shipInRoleCategory(whom,"oolite-pirate"))
		{
			this.ship.AIScript.oolite_intership.cargodemand = Math.ceil(this.ship.cargoSpaceCapacity / 10);
		}
		else if (this.shipInRoleCategory(whom,"oolite-assassin"))
		{
			this.ship.AIScript.oolite_intership.cargodemand = Math.ceil(this.ship.cargoSpaceCapacity / 20); // worth a try
		}
		else
		{
			this.ship.AIScript.oolite_intership.cargodemand = Math.ceil(this.ship.cargoSpaceCapacity / 15);
		}
	}

	if (this.ship.escortGroup != null)
	{
		this.ship.requestHelpFromGroup();
	}
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_shipBeingAttackedUnsuccessfully = function(whom)
{
	if (this.getParameter("oolite_flag_sendsDistressCalls"))
	{
		this.broadcastDistressMessage();
	}
	if (this.ship.defenseTargets.indexOf(whom) < 0)
	{
		this.ship.addDefenseTarget(whom);
		this.reconsiderNow();
	}
	// TODO: a rep for not accepting surrenders should have an effect here
	if (!this.ship.hasHostileTarget && whom.isPlayer && !this.ship.AIScript.oolite_intership.cargodemand && !this.ship.AIScript.oolite_intership.cargodemandpaid)
	{
		this.ship.AIScript.oolite_intership.cargodemand = Math.ceil(this.ship.cargoSpaceCapacity / 15);
	}
	if (!this.ship.hasHostileTarget)
	{
		this.ship.target = whom;
		this.ship.performAttack();
		this.ship.requestHelpFromGroup();
	}
}


PriorityAIController.prototype.responseComponent_standard_shipFiredMissile = function(missile,target)
{
	// spread missiles out between targets
	if (this.ship.defenseTargets.length > 1)
	{
		this.ship.removeDefenseTarget(target);
		this.ship.target = null;
		this.reconsiderNow();
	}
	this.communicate("oolite_firedMissile",target,4);
}


PriorityAIController.prototype.responseComponent_standard_shipKilledOther = function(other)
{
	this.communicate("oolite_killedTarget",other,3);
}


PriorityAIController.prototype.responseComponent_standard_shipLaunchedEscapePod = function()
{
	this.communicate("oolite_eject",{},1);
	if (this.getParameter("oolite_flag_selfDestructAbandonedShip") == true)
	{
		if (!this.ship.script.__oolite_self_destruct)
		{
			this.ship.script.__oolite_self_destruct = new Timer(this.ship.script,function(){this.ship.explode()},10);
		}
	}
}


PriorityAIController.prototype.responseComponent_standard_shipLaunchedFromStation = function(station)
{
	// clear the station
	this.ship.destination = station.position;
	this.ship.desiredSpeed = this.cruiseSpeed();
	this.ship.desiredRange = 15000;
	this.ship.performFlyToRangeFromDestination();
}


PriorityAIController.prototype.responseComponent_standard_shipScoopedOther = function(other)
{
	this.communicate("oolite_scoopedCargo",{"oolite_goodsDescription":displayNameForCommodity(other.commodity)},4);
	this.setParameter("oolite_cargoDropped",null);
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_shipTargetLost = function(target)
{
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_standard_shipWillEnterWormhole = function()
{
	this.setParameter("oolite_witchspaceWormhole",null);
	this.applyHandlers({});
}


PriorityAIController.prototype.responseComponent_standard_shipWitchspaceBlocked = function(blocker)
{
	this.communicate("oolite_witchspaceBlocked",blocker,3);
	this.ship.setDestination = blocker.position;
	this.ship.setDesiredRange = 30000;
	this.ship.setDesiredSpeed = this.cruiseSpeed();
	this.ship.performFlyToRangeFromDestination();
	this.setParameter("oolite_witchspaceEntry",null);
	// no reconsidering yet
}


PriorityAIController.prototype.responseComponent_standard_wormholeSuggested = function(hole)
{
	this.ship.destination = hole.position;
	this.ship.desiredRange = 0;
	this.ship.desiredSpeed = this.ship.maxSpeed;
	this.ship.performFlyToRangeFromDestination();
	this.setParameter("oolite_witchspaceWormhole",hole);
	// don't reconsider
}

/* Missile response components */

PriorityAIController.prototype.responseComponent_missile_commsMessageReceived = function(message)
{
	this.noteCommsHeard();
}


PriorityAIController.prototype.responseComponent_missile_shipHitByECM = function()
{
	if (this.ship.scriptInfo.oolite_missile_ecmResponse)
	{
		var fn = this.ship.scriptInfo.oolite_missile_ecmResponse;
		if (this.ship.AIScript[fn])
		{
			this.ship.AIScript[fn]();
			this.reconsiderNow();
			return;
		}
		if (this.ship.script[fn])
		{
			this.ship.script[fn]();
			this.reconsiderNow();
			return;
		}
	}

	/* This section for the hardheads should be an ECM
	 * response function, and that is used in the default
	 * shipdata.plist, but for compatibility with older OXPs
	 * it's also hardcoded here for now.
	 *
	 * OXPs wanting to overrule this for hardheads can set a
	 * response function to do so.
	 */
	if (this.ship.primaryRole == "EQ_HARDENED_MISSILE")
	{
		if (Math.random() < 0.1) //10% chance per pulse
		{
			if (Math.random() < 0.5)
			{
				// 50% chance responds by detonation
				this.ship.AIScript.shipAchievedDesiredRange();
				return;
			}
			// otherwise explode as normal below
		}
		else // 90% chance unaffected
		{
			return;
		}
	}

	this.ship.explode();
}


PriorityAIController.prototype.responseComponent_missile_shipTargetCloaked = function()
{
	this.setParameter("oolite_interceptCoordinates",this.ship.target.position);
	this.setParameter("oolite_interceptTarget",this.ship.target);
	// stops performIntercept sending AchievedDesiredRange
	this.ship.performIdle();
}


PriorityAIController.prototype.responseComponent_missile_shipTargetLost = function()
{
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_missile_shipAchievedDesiredRange = function()
{
	if (this.ship.scriptInfo.oolite_missile_detonation)
	{
		var fn = this.ship.scriptInfo.oolite_missile_detonation;
		if (this.ship.AIScript[fn])
		{
			this.ship.AIScript[fn]();
			this.reconsiderNow();
			return;
		}
		if (this.ship.script[fn])
		{
			this.ship.script[fn]();
			this.reconsiderNow();
			return;
		}
	}
	/* Defaults to standard missile settings, in case they're
	 * not specified in scriptInfo */
	var blastpower = 170;
	var blastradius = 32.5;
	var blastshaping = 0.25;
	if (this.ship.scriptInfo.oolite_missile_blastPower)
	{
		blastpower = this.ship.scriptInfo.oolite_missile_blastPower;
	}
	if (this.ship.scriptInfo.oolite_missile_blastRadius)
	{
		blastradius = this.ship.scriptInfo.oolite_missile_blastRadius;
	}
	if (this.ship.scriptInfo.oolite_missile_blastShaping)
	{
		blastshaping = this.ship.scriptInfo.oolite_missile_blastShaping;
	}
	this.ship.dealEnergyDamage(blastpower,blastradius,blastshaping);
	this.ship.explode();
}


/* Station response components */

PriorityAIController.prototype.responseComponent_station_commsMessageReceived = function(message)
{
	this.noteCommsHeard();
}


PriorityAIController.prototype.responseComponent_station_cascadeWeaponDetected = function(weapon)
{
	this.ship.alertCondition = 3;
	this.reconsiderNow();
};


PriorityAIController.prototype.responseComponent_station_shipAttackedWithMissile = function(missile,whom)
{
	this.ship.alertCondition = 3;
	if (this.ship.equipmentStatus("EQ_ECM") == "EQUIPMENT_OK")
	{
		this.ship.fireECM();
		this.ship.addDefenseTarget(missile);
		this.ship.addDefenseTarget(whom);
		// but don't reconsider immediately
	}
	else
	{
		this.ship.addDefenseTarget(missile);
		this.ship.addDefenseTarget(whom);
		var tmp = this.ship.target;
		this.ship.target = whom;
		this.ship.requestHelpFromGroup();
		this.ship.target = tmp;
		this.reconsiderNow();
	}
};


PriorityAIController.prototype.responseComponent_station_shipBeingAttacked = function(whom)
{
	if (!whom) 
	{
		this.reconsiderNow();
		return;
	}
	if (whom.target != this.ship)
	{
		if (!whom.isPlayer)
		{
			// was accidental
			if (this.allied(whom,this.ship))
			{
				this.communicate("oolite_friendlyFire",whom,4);
				// ignore it
				return;
			}
			if (Math.random() > 0.1)
			{
				// usually ignore it anyway
				return;
			}
		}
		else if (this.ship.alertCondition > 1 && this.ignorePlayerFriendlyFire())
		{
			// send warning communication
			this.communicate("oolite_friendlyFire",whom,2);
			return;
		}
	}
	this.ship.alertCondition = 3;
	if (this.ship.defenseTargets.indexOf(whom) < 0)
	{
		this.ship.addDefenseTarget(whom);
		this.reconsiderNow();
	}
	else 
	{
		// else we know about this attacker already
		if (this.ship.energy * 4 < this.ship.maxEnergy)
		{
			// but at low energy still reconsider
			this.reconsiderNow();
			this.ship.requestHelpFromGroup();
		}
	}
	if (this.ship.hasHostileTarget)
	{
		if (!this.isAggressive(this.ship.target))
		{
			// if our current target is running away, switch targets
			this.ship.target = whom;
		}
		else if (this.ship.target.target != this.ship)
		{
			// if our current target isn't aiming at us
			if (Math.random() < 0.2)
			{
				// occasionally switch
				this.ship.target = whom;
			}
		}
	} else {
		// time to get one
		this.ship.target = whom;
		this.reconsiderNow();
	}
}


PriorityAIController.prototype.responseComponent_station_shipAttackedOther = function(other)
{
	this.communicate("oolite_hitTarget",other,4);
}


PriorityAIController.prototype.responseComponent_station_shipFiredMissile = function(missile,target)
{
	this.communicate("oolite_firedMissile",target,4);
}


PriorityAIController.prototype.responseComponent_station_shipKilledOther = function(other)
{
	this.communicate("oolite_killedTarget",other,3);
}


PriorityAIController.prototype.responseComponent_station_shipTargetLost = function(target)
{
	this.reconsiderNow();
};


PriorityAIController.prototype.responseComponent_station_helpRequestReceived = function(ally, enemy)
{
	this.ship.addDefenseTarget(enemy);
	if (enemy.scanClass == "CLASS_MISSILE" && this.distance(enemy) < this.scannerRange && this.ship.equipmentStatus("EQ_ECM") == "EQUIPMENT_OK")
	{
		this.ship.fireECM();
		return;
	}
	if (!this.ship.alertCondition == 3)
	{
		this.ship.target = enemy;
		this.reconsiderNow();
		return; // not in a combat mode
	}
	this.ship.target = enemy;
}


PriorityAIController.prototype.responseComponent_station_distressMessageReceived = function(aggressor, sender)
{
	if (this.getParameter("oolite_flag_listenForDistressCall") != true)
	{
		return;
	}
	if (this.ship.scanClass == "CLASS_POLICE" || (this.ship.isStation && this.ship.allegiance == "galcop"))
	{
		if (this.distance(aggressor) < this.scannerRange)
		{
			aggressor.setBounty(aggressor.bounty | 8,"attacked innocent");
		}
	}
	this.setParameter("oolite_distressAggressor",aggressor);
	this.setParameter("oolite_distressSender",sender);
	this.setParameter("oolite_distressTimestamp",clock.adjustedSeconds);
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_station_offenceCommittedNearby = function(attacker, victim)
{
	if (this.ship == victim) return; // other handlers can get this one
	if (this.distance(attacker) > this.scannerRange) return; // can't mark what you can't see
	if (this.getParameter("oolite_flag_markOffenders")) 
	{
		if (attacker.bounty == 0 && victim.bounty == 0)
		{
			if ((this.shipInRoleCategory(victim,"oolite-police-dislike") && !this.shipInRoleCategory(attacker,"oolite-police-dislike")) ||
				(this.shipInRoleCategory(attacker,"oolite-police-like") && !this.shipInRoleCategory(victim,"oolite-police-like")))
			{
				if (victim.hasHostileTarget)
				{
					// they're both fighting; it's likely that the
					// attacker is fighting in self-defence; so swap them
					var tmp = victim;
					victim = attacker;
					attacker = tmp;
				}
			}
		}
		if (!attacker.isPlayer && attacker.target != victim)
		{
			// ignore friendly fire if they were aiming at a pirate/assassin
			if (attacker.bounty == 0 && attacker.target && this.shipInRoleCategory(attacker.target,"oolite-police-dislike"))
			{
				// but we might go after the pirate/assassin ourselves in a bit
				this.ship.addDefenseTarget(attacker.target);
				return;
			}
		}
		else if (attacker.isPlayer && this.ignorePlayerFriendlyFire())
		{
			this.communicate("oolite_friendlyFire",attacker,3);
			return;
		}
		attacker.setBounty(attacker.bounty | 7,"seen by police");
		this.ship.addDefenseTarget(attacker);
		if (this.ship.alertCondition < 3)
		{
			this.ship.alertCondition = 3;
			this.ship.target = attacker;
		}
		this.reconsiderNow();
	}
}


/* Non-standard response components */

PriorityAIController.prototype.responseComponent_docking_shipAchievedDesiredRange = function()
{
	var message = this.ship.dockingInstructions.ai_message;
	if (message == "APPROACH" || message == "BACK_OFF" || message == "APPROACH_COORDINATES")
	{
		this.reconsiderNow();
	}
}


PriorityAIController.prototype.responseComponent_docking_stationWithdrewDockingClearance = function()
{
	this.setParameter("oolite_dockingStation",null);
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_escort_escortDock = function()
{
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_escort_helpRequestReceived = function(ally,enemy)
{
	if (this.allied(this.ship,enemy))
	{
		return;
	}
	this.ship.addDefenseTarget(enemy);
	if (enemy.scanClass == "CLASS_MISSILE" && this.distance(enemy) < this.scannerRange && this.ship.equipmentStatus("EQ_ECM") == "EQUIPMENT_OK")
	{
		this.ship.fireECM();
	}
	if (enemy.scanClass == "CLASS_THARGOID" && this.ship.scanClass != "CLASS_THARGOID" && (!this.ship.target || this.ship.target.scanClass != "CLASS_THARGOID"))
	{
		if (this.respondToThargoids(enemy,false))
		{
			this.reconsiderNow();
			return;
		}
	}

	// always help the leader
	if (ally == this.ship.group.leader)
	{
		if (!this.ship.target || !this.ship.hasHostileTarget || this.ship.target.target != ally)
		{
			this.ship.target = enemy;
			this.reconsiderNow();
			return;
		}
	}
	this.ship.addDefenseTarget(enemy);
	if (enemy.scanClass == "CLASS_MISSILE" && this.distance(enemy) < this.scannerRange && this.ship.equipmentStatus("EQ_ECM") == "EQUIPMENT_OK")
	{
		this.ship.fireECM();
		return;
	}
	if (!this.ship.hasHostileTarget)
	{
		this.ship.target = enemy;
		this.ship.performAttack();
		this.reconsiderNow();
		return; // not in a combat mode
	}
	if (ally.energy / ally.maxEnergy < this.ship.energy / this.ship.maxEnergy)
	{
		// not in worse shape than ally
		if (this.ship.target.target != ally && this.ship.target != ally.target)
		{
			// not already helping, go for it...
			this.ship.target = enemy;
			this.reconsiderNow();
		}
	}
}


PriorityAIController.prototype.responseComponent_expectWitchspace_shipTargetLost = function(target)
{
	if (!target)
	{
		target = this.getParameter("oolite_rememberedTarget");
	}
	if (target) {
		var pos = target.position;
		var ws = system.wormholes;
		// most likely to be most recent
		for (var i=ws.length-1; i>=0; i--)
		{
			if (ws[i].position.distanceTo(pos) < 100)
			{
				this.setParameter("oolite_witchspaceWormhole",ws[i]);
				break;
			}
		}
	}
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_scooping_shipAchievedDesiredRange = function()
{
	this.reconsiderNow();
}


PriorityAIController.prototype.responseComponent_scooping_shipScoopedFuel = function()
{
	if (this.ship.fuel == 7)
	{
		this.reconsiderNow();
	}
}


PriorityAIController.prototype.responseComponent_trackPlayer_playerWillEnterWitchspace = function()
{
	var wormhole = this.getParameter("oolite_witchspaceWormhole");
	if (wormhole != null && wormhole.isWormhole)
	{
		this.ship.enterWormhole(wormhole);
	} 
	else
	{
		this.ship.enterWormhole();
	}
}



/* ******************* Templates *************************** */

/* Templates. Common AI priority list fragments which may be useful to
 * multiple AIs. These functions take no parameters and return a
 * list. This can either be used straightforwardly as a truebranch or
 * falsebranch value, or appended to a list using Array.concat() */

PriorityAIController.prototype.templateLeadHuntingMission = function()
{
	return [
		{
			condition: this.conditionInInterstellarSpace,
			truebranch: this.templateWitchspaceJumpAnywhere()
		},
		{
			condition: this.conditionHasWaypoint,
			configuration: this.configurationSetDestinationToWaypoint,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		},
		{
			condition: this.conditionHasSelectedStation,
			truebranch: [
				{
					condition: this.conditionSelectedStationNearby,
					configuration: this.configurationSetSelectedStationForDocking,
					behaviour: this.behaviourDockWithStation,
					reconsider: 30
				},
				{
					condition: this.conditionSelectedStationNearMainPlanet,
					truebranch: [
						{
							notcondition: this.conditionMainPlanetNearby,
							configuration: this.configurationSetDestinationToMainPlanet,
							behaviour: this.behaviourApproachDestination,
							reconsider: 30
						}
					]
				},
				// either the station isn't near the planet, or we are
				{
					configuration: this.configurationSetDestinationToSelectedStation,
					behaviour: this.behaviourApproachDestination,
					reconsider: 30
				}
			]
		},
		{
			condition: this.conditionMainPlanetNearby,
			truebranch: [
				{
					condition: this.conditionPatrolIsOver,
					configuration: this.configurationSelectRandomTradeStation,
					behaviour: this.behaviourReconsider
				}
			]
		},
		/* No patrol route set up. Make one */
		{
			configuration: this.configurationSetWaypoint,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		}
	];
}

PriorityAIController.prototype.templateLeadPirateMission = function()
{
	return [
		{
			label: "Pirate mission",
			preconfiguration: this.configurationForgetCargoDemand,
			condition: this.conditionScannerContainsPirateVictims,
			configuration: this.configurationAcquireScannedTarget,
			truebranch: [
				{
					label: "Check odds",
					condition: this.conditionCombatOddsGood,
					behaviour: this.behaviourRobTarget,
					reconsider: 5
				}
			]
		},
		{
			condition: this.conditionInInterstellarSpace,
			truebranch: this.templateWitchspaceJumpAnywhere()
		},
		{
			/* move to a position on one of the space lanes, preferring lane 1 */
			label: "Lurk",
			configuration: this.configurationSetDestinationToPirateLurk,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		},
	];
}


PriorityAIController.prototype.templateReturnToBase = function()
{
	return [
		{
			label: "Return to base",
			condition: this.conditionHasSelectedStation,
			truebranch: [
				{
					condition: this.conditionSelectedStationNearby,
					configuration: this.configurationSetSelectedStationForDocking,
					behaviour: this.behaviourDockWithStation,
					reconsider: 30
				},
				{
					condition: this.conditionSelectedStationNearMainPlanet,
					truebranch: [
						{
							notcondition: this.conditionMainPlanetNearby,
							configuration: this.configurationSetDestinationToMainPlanet,
							behaviour: this.behaviourApproachDestination,
							reconsider: 30
						}
					]
				},
				// either the station isn't near the planet, or we are
				{
					configuration: this.configurationSetDestinationToSelectedStation,
					behaviour: this.behaviourApproachDestination,
					reconsider: 30
				}
			],
			falsebranch: [
				{
					condition: this.conditionFriendlyStationExists,
					configuration: this.configurationSelectRandomTradeStation,
					behaviour: this.behaviourReconsider
				}
			]
		}
	];


}


PriorityAIController.prototype.templateReturnToBaseOrPlanet = function()
{
	return [
		{
			label: "Return to base or planet",
			condition: this.conditionFriendlyStationNearby,
			configuration: this.configurationSetNearbyFriendlyStationForDocking,
			behaviour: this.behaviourDockWithStation,
			reconsider: 30
		},
		{
			condition: this.conditionFriendlyStationExists,
			configuration: this.configurationSetDestinationToNearestFriendlyStation,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		},
		{
			condition: this.conditionHasSelectedPlanet,
			truebranch: [
				{
					preconfiguration: this.configurationSetDestinationToSelectedPlanet,
					condition: this.conditionNearDestination,
					behaviour: this.behaviourLandOnPlanet
				},
				{
					behaviour: this.behaviourApproachDestination,
					reconsider: 30
				}
			]
		},
		{
			condition: this.conditionPlanetExists,
			configuration: this.configurationSelectPlanet,
			behaviour: this.behaviourReconsider
		},
		{
			condition: this.conditionCanWitchspaceOut,
			configuration: this.configurationSelectWitchspaceDestination,
			behaviour: this.behaviourEnterWitchspace,
			reconsider: 20
		}
	];
}


PriorityAIController.prototype.templateWitchspaceJumpAnywhere = function()
{
	return [
		{
			label: "Wormhole search",
			condition: this.conditionWormholeNearby,
			configuration: this.configurationSetDestinationToNearestWormhole,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		},
		/* Short reconsiders on next two so wormholes aren't missed */
		{
			label: "No wormholes nearby",
			condition: this.conditionCanWitchspaceOut,
			configuration: this.configurationSelectWitchspaceDestination,
			behaviour: this.behaviourEnterWitchspace,
			reconsider: 10
		},
		{
			label: "Lurk around witchpoint",
			configuration: this.configurationSetDestinationToWitchpoint,
			behaviour: this.behaviourApproachDestination,
			reconsider: 10
		}
	];
}


PriorityAIController.prototype.templateWitchspaceJumpInbound = function()
{
	return [
		{
			label: "Jump inbound",
			preconfiguration: this.configurationSelectWitchspaceDestinationInbound,
			condition: this.conditionCanWitchspaceOnRoute,
			behaviour: this.behaviourEnterWitchspace,
			reconsider: 20
		},
		{
			condition: this.conditionReadyToSunskim,
			configuration: this.configurationSetDestinationToSunskimEnd,
			behaviour: this.behaviourSunskim,
			reconsider: 20
		},
		{
			condition: this.conditionSunskimPossible,
			configuration: this.configurationSetDestinationToSunskimStart,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		}
	];
}


PriorityAIController.prototype.templateWitchspaceJumpOutbound = function()
{
	return [
		{
			label: "Jump outbound",
			preconfiguration: this.configurationSelectWitchspaceDestinationOutbound,
			condition: this.conditionCanWitchspaceOnRoute,
			behaviour: this.behaviourEnterWitchspace,
			reconsider: 20
		},
		{
			condition: this.conditionReadyToSunskim,
			configuration: this.configurationSetDestinationToSunskimEnd,
			behaviour: this.behaviourSunskim,
			reconsider: 20
		},
		{
			condition: this.conditionSunskimPossible,
			configuration: this.configurationSetDestinationToSunskimStart,
			behaviour: this.behaviourApproachDestination,
			reconsider: 30
		}
	];
}


/* ******************* Waypoint generators *********************** */

/* Waypoint generators. When these are called, they should set up
 * the next waypoint for the ship. Ideally ships should either
 * reach that waypoint or formally give up on it before asking for
 * the next one, but the generator shouldn't assume that unless
 * it's one written specifically for a particular AI . */

PriorityAIController.prototype.waypointsSpacelanePatrol = function()
{
	var p = this.ship.position;
	var choice = "";
	if (p.magnitude() < 10000)
	{
		// near witchpoint
		if (Math.random() < 0.9)
		{ 
			// mostly return to planet
			choice = "PLANET";
		}
		else
		{
			choice = "SUN";
		}
	}
	else if (p.distanceTo(system.mainPlanet) < system.mainPlanet.radius * 2)
	{
		// near planet
		if (Math.random() < 0.75)
		{ 
			// mostly go to witchpoint
			choice = "WITCHPOINT";
		}
		else
		{
			choice = "SUN";
		}
	}
	else if (p.distanceTo(system.sun) < system.sun.radius * 3)
	{
		// near sun
		if (Math.random() < 0.9)
		{ 
			// mostly return to planet
			choice = "PLANET";
		}
		else
		{
			choice = "SUN";
		}
	}
	else if (p.z < system.mainPlanet.position.z && ((p.x * p.x) + (p.y * p.y)) < this.scannerRange * this.scannerRange * 4)
	{
		// on lane 1
		if (Math.random() < 0.5)
		{
			choice = "PLANET";
		}
		else
		{
			choice = "WITCHPOINT";
		}
	}
	else if (p.subtract(system.mainPlanet).dot(p.subtract(system.sun)) < -0.9)
	{
		// on lane 2
		if (Math.random() < 0.5)
		{
			choice = "PLANET";
		}
		else
		{
			choice = "SUN";
		}
	}
	else if (p.dot(system.sun.position) > 0.9)
	{
		// on lane 3
		if (Math.random() < 0.5)
		{
			choice = "WITCHPOINT";
		}
		else
		{
			choice = "SUN";
		}
	}
	else
	{
		// we're not on any lane. Return to the planet
		choice = "PLANET";
	}
	// having chosen, now set up the next stop on the patrol
	switch (choice) {
	case "WITCHPOINT":
		this.setParameter("oolite_waypoint",new Vector3D(0,0,0));
		this.setParameter("oolite_waypointRange",7500);
		break;
	case "PLANET":
		this.setParameter("oolite_waypoint",system.mainPlanet.position);
		this.setParameter("oolite_waypointRange",system.mainPlanet.radius*2);
		break;
	case "SUN":
		this.setParameter("oolite_waypoint",system.sun.position);
		this.setParameter("oolite_waypointRange",system.sun.radius*2.5);
		break;
	}

}


PriorityAIController.prototype.waypointsStationPatrol = function()
{
	var station = null;
	if (this.ship.group && this.ship.group.leader && this.ship.group.leader.isStation)
	{
		station = this.ship.group.leader;
	}
	if (!station)
	{
		station = system.mainStation;
		if (!station)
		{
			this.setParameter("oolite_waypoint",new Vector3D(0,0,0));
			this.setParameter("oolite_waypointRange",7500);
			return;
		}
	}
	var z = station.vectorForward;
	var tmp = new Vector3D(0,1,0);
	if (system.sun)
	{
		tmp = z.cross(system.sun.position.direction());
	}
	var x = z.cross(tmp);
	var y = z.cross(x);
	// x and y now consistent vectors relative to a rotating station

	var waypoints = [
		station.position.add(x.multiply(25000)),
		station.position.add(y.multiply(25000)),
		station.position.add(x.multiply(-25000)),
		station.position.add(y.multiply(-25000))
	];
	
	var waypoint = waypoints[0];
	for (var i=0;i<=3;i++)
	{
		if (this.distance(waypoints[i]) < 500)
		{
			waypoint = waypoints[(i+1)%4];
			break;
		}
	}
	this.setParameter("oolite_waypoint",waypoint);
	this.setParameter("oolite_waypointRange",100);

}


PriorityAIController.prototype.waypointsWitchpointPatrol = function()
{
	if (this.ship.distanceTravelled > system.mainPlanet.position.z + 200000)
	{
		this.setParameter("oolite_waypoint",system.mainStation.position);
		this.setParameter("oolite_waypointRange",10000);
	}
	else
	{
		var waypoints = [
			new Vector3D(15E3,0,5E3),
			new Vector3D(0,15E3,-5E3),
			new Vector3D(-15E3,0,5E3),
			new Vector3D(0,-15E3,-5E3)
		];
		
		var waypoint = waypoints[0];
		for (var i=0;i<=3;i++)
		{
			if (this.distance(waypoints[i]) < 500)
			{
				waypoint = waypoints[(i+1)%4];
				break;
			}
		}
		this.setParameter("oolite_waypoint",waypoint);
		this.setParameter("oolite_waypointRange",100);
	}

}


/* ********** Communications data ****************/

/* Warning: OXPs should only interact with this through the provided
 * API functions. The internals of data storage may be changed at any
 * time. This data is global. */

this.startUp = function()
{
	// initial definition is just essential communications for now
	this.$commsSettings = {};
	this.$commsAllowed = true;
	this._setCommunications({
		generic: {
			generic: {
				oolite_thanksForHelp: "[oolite-comms-thanksForHelp]",
				oolite_surrender: "[oolite-comms-surrender]"
			}
		},
		trader: { 
			generic: { 
				oolite_acceptPirateDemand: "[oolite-comms-acceptPirateDemand]",
				oolite_makeDistressCall: "[oolite-comms-makeDistressCall]"
			} 
		},
		police: {
			generic: {
				oolite_thanksForHelp: "[oolite-comms-police-thanksForHelp]",
				oolite_markForFines: "[oolite-comms-markForFines]",
				oolite_distressResponseAggressor: "[oolite-comms-distressResponseAggressor]",
				oolite_offenceDetected: "[oolite-comms-offenceDetected]",
			}
		},
		pirate: {
			generic: {
				oolite_makePirateDemand: "[oolite-comms-makePirateDemand]",
			}
		},
		assassin: {
			generic: {
				oolite_beginningAttack: "[oolite-comms-contractAttack]",
			}
		},
		_thargoid: {
			thargoid: {
				oolite_continuingAttack: "[thargoid_curses]"
			}
		}
	});

	/* These are temporary for testing. Remove before release... */
	this.$commsSettings.generic.generic.oolite_continuingAttack = "I've got the [oolite_entityClass]";
	this.$commsSettings.police.generic.oolite_continuingAttack = function(k,p) { return "Targeting the "+p.oolite_entityName+". Cover me."; };
	this.$commsSettings.generic.generic.oolite_beginningAttack = "Die, [oolite_entityName]!";
	this.$commsSettings.police.generic.oolite_beginningAttack = function(k,p) { return "Leave the system or die, "+p.oolite_entityName+"!"; };
	this.$commsSettings.generic.generic.oolite_beginningAttackInanimate = "I've got you this time, [oolite_entityName]!";
	this.$commsSettings.generic.generic.oolite_hitTarget = "Take that, scum.";
	this.$commsSettings.generic.generic.oolite_killedTarget = "[oolite_entityClass] down!";
	this.$commsSettings.pirate.generic.oolite_hitTarget = "Where's the cargo, [oolite_entityName]?";
	this.$commsSettings.generic.generic.oolite_friendlyFire = "Watch where you're shooting, [oolite_entityName]!";
	this.$commsSettings.generic.generic.oolite_eject = "Condition critical! I'm bailing out...";
	this.$commsSettings.generic.generic.oolite_thargoidAttack = "%N! A thargoid warship!";
	this.$commsSettings.generic.generic.oolite_firedMissile = "Dodge this for a bit, [oolite_entityName].";
	this.$commsSettings.generic.generic.oolite_incomingMissile = "Help! Help! Missile!";
	this.$commsSettings.generic.generic.oolite_startHelping = "Hold on! I'm on them.";
	this.$commsSettings.generic.generic.oolite_switchTarget = "I'll get the [oolite_entityClass].";
	this.$commsSettings.generic.generic.oolite_newAssailant = "Where did that [oolite_entityClass] come from?";
	this.$commsSettings.generic.generic.oolite_startFleeing = "I can't take this much longer! I'm getting out of here.";
	this.$commsSettings.generic.generic.oolite_continueFleeing = "I'm still not clear. Someone please help!";
	this.$commsSettings.generic.generic.oolite_groupIsOutnumbered = "Please, let us go!";
	this.$commsSettings.pirate.generic.oolite_groupIsOutnumbered = "Argh! They're tougher than they looked. Break off the attack!"
	this.$commsSettings.generic.generic.oolite_dockingWait = "Bored now.";
	this.$commsSettings.generic.generic.oolite_dockEscorts = "I've got clearance now. Begin your own docking sequences when ready.";
	this.$commsSettings.generic.generic.oolite_mining = "Maybe this one has gems.";
	this.$commsSettings.generic.generic.oolite_quiriumCascade = "Cascade! %N! Get out of here!";
	this.$commsSettings.pirate.generic.oolite_scoopedCargo = "Ah, [oolite_goodsDescription]. We should have shaken them down for more.";
	this.$commsSettings.generic.generic.oolite_agreeingToDumpCargo = "Have it! But please let us go!";
	this.$commsSettings.generic.generic.oolite_engageWitchspaceDrive = "All ships, form up for witchspace jump.";
	this.$commsSettings.generic.generic.oolite_engageWitchspaceDriveFlee = "There's too many of them! Get out of here!";
}



/* Event handler pair to prevent comms from being received while in
 * witchspace tunnel */
this.shipWillEnterWitchspace = function()
{
	this.$commsAllowed = false;
}

this.shipExitedWitchspace = function()
{
	this.$commsAllowed = true;
}



/* Search through communications from most specific to least specific.
 * role+personality
 * "generic"+personality
 * role+"generic"
 * "generic"+"generic"
 * A return value of "" means no communication is set.
 *
 * Roles or personalities starting with _ do not fall back to generic
 */
this._getCommunication = function(role, personality, key)
{
	if (this.$commsSettings[role] && this.$commsSettings[role][personality] && this.$commsSettings[role][personality][key] && this.$commsSettings[role][personality][key] != "")
	{
		return this.$commsSettings[role][personality][key];
	}
	if (role.charAt(0) != "_")
	{
		if (this.$commsSettings["generic"] && this.$commsSettings["generic"][personality] && this.$commsSettings["generic"][personality][key] && this.$commsSettings["generic"][personality][key] != "")
		{
			return this.$commsSettings["generic"][personality][key];
		}
	}
	if (personality.charAt(0) != "_")
	{
		if (this.$commsSettings[role] && this.$commsSettings[role]["generic"] && this.$commsSettings[role]["generic"][key] && this.$commsSettings[role]["generic"][key] != "")
		{
			return this.$commsSettings[role]["generic"][key];
		}
	}
	if (role.charAt(0) != "_" && personality.charAt(0) != "_")
	{
		if (this.$commsSettings["generic"] && this.$commsSettings["generic"]["generic"] && this.$commsSettings["generic"]["generic"][key] && this.$commsSettings["generic"]["generic"][key] != "")
		{
			return this.$commsSettings["generic"]["generic"][key];
		} 
	}
	return "";
}


/* Returns the available personalities for a particular role */
this._getCommunicationPersonalities = function(role)
{
	if (!this.$commsSettings[role])
	{
		return [];
	}
	else
	{
		return Object.keys(this.$commsSettings[role]);
	}
}


/* Set a communication for the specified role, personality and comms
 * key. "generic" is used as a fallback role and personality. */
this._setCommunication = function(role, personality, key, value)
{
	if (!this.$commsSettings[role])
	{
		this.$commsSettings[role] = {};
	}
	if (!this.$commsSettings[role][personality])
	{
		this.$commsSettings[role][personality] = {};
	}
	this.$commsSettings[role][personality][key] = value;
}


/* Bulk setting of communications */
this._setCommunications = function(obj)
{
	var roles = Object.keys(obj);
	for (var i = 0; i<roles.length ; i++)
	{
		var personalities = Object.keys(obj[roles[i]]);
		for (var j = 0; j<personalities.length ; j++)
		{
			var keys = Object.keys(obj[roles[i]][personalities[j]]);
			for (var k = 0; k<keys.length ; k++)
			{
				var val = obj[roles[i]][personalities[j]][keys[k]];
				this._setCommunication(roles[i],personalities[j],keys[k],val);
			}
		}
	}

}

/* Intentionally not documented */
this._threatAssessment = function(ship,full)
{
	// experimenting without this one for a while
	//	full = full || ship.hasHostileTarget || (ship.isPlayer && player.alertCondition == 3);
	return ship.threatAssessment(full);
}