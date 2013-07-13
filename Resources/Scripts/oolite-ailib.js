/*

oolite-ailib.js

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

this.AILib = function(ship)
{
		this.ship = ship;
		var activeHandlers = [];
		var priorityList = null;
		var reconsiderationTimer = null;
		var parameters = {};

		/* Private utility functions */

		/* Considers a priority list, potentially recursively */
		function _reconsiderList(priorities) {
				var l = priorities.length;
				for (var i = 0; i < l; i++)
				{
						var priority = priorities[i];
						// always call the preconfiguration function at this point
						// to set up condition parameters
						if (priority.preconfiguration)
						{
								priority.preconfiguration.call(this.ship.AIScript);
						}
						// absent condition is always true
						if (!priority.condition || priority.condition.call(this))
						{
								// always call the configuration function at this point
								if (priority.configuration)
								{
										priority.configuration.call(this.ship.AIScript);
								}
								// this is what we're doing
								if (priority.behaviour) 
								{
										if (priority.reconsider) 
										{
												_resetReconsideration.call(this,priority.reconsider);
										}
										return priority.behaviour;
								}
								// otherwise this is what we might be doing
								if (priority.truebranch)
								{
										var branch = _reconsiderList.call(this,priority.truebranch);
										if (branch != null)
										{
												return branch;
										}
										// otherwise nothing in the branch was usable, so move on
								}
						}
						else
						{
								if (priority.falsebranch)
								{
										var branch = _reconsiderList.call(this,priority.falsebranch);
										if (branch != null)
										{
												return branch;
										}
										// otherwise nothing in the branch was usable, so move on
								}
						}
				}
				return null; // nothing in the list is usable, so return
		};

		/* Resets the reconsideration timer. */
		function _resetReconsideration(delay)
		{
				if (reconsiderationTimer != null)
				{
						reconsiderationTimer.stop();
						reconsiderationTimer = null;
				}
				reconsiderationTimer = new Timer(this, this.reconsider, delay);
		};


		/* ****************** General AI functions ************** */


		this.setPriorities = function(prioritylist) 
		{
				priorityList = prioritylist;
				this.reconsider();
		}

		// parameters created by Oolite must always be prefixed oolite-
		this.setParameter = function(key, value)
		{
				parameters[key] = value;
		}

		this.getParameter = function(key)
		{
				if (key in parameters)
				{
						return parameters[key];
				}
				return null;
		}


		this.reconsider = function() {
				if (reconsiderationTimer != null)
				{
						reconsiderationTimer.stop();
						reconsiderationTimer = null;
				}
				if (!this.ship || !this.ship.isValid || !this.ship.isInSpace)
				{
						return;
				}
				var newBehaviour = _reconsiderList.call(this,priorityList);
				if (newBehaviour == null) {
						log(this.name,"AI '"+this.ship.AIScript.name+"' for ship "+this.ship+" had all priorities fail. All priority based AIs should end with an unconditional entry.");
						return false;
				}

				newBehaviour.call(this);
				return true;
		}

		this.setUpHandlers = function(handlers)
		{
				// step 1: go through activeHandlers, and delete those
				// functions from this.ship.AIScript
				for (var i=0; i < activeHandlers.length ; i++)
				{
						delete this.ship.AIScript[activeHandlers[i]];
				}

				if (handlers.entityDestroyed)
				{
						handlers.oolite_entityDestroyedAux = handlers.entityDestroyed;
				}
				handlers.entityDestroyed = function()
				{
						if (reconsiderationTimer != null)
						{
								reconsiderationTimer.stop();
								reconsiderationTimer = null;
						}
						this.ship.AIScript.oolite_entityDestroyedAux();
				};

				// step 2: go through the keys in handlers and put those handlers
				// into this.ship.AIScript and the keys into activeHandlers
				activeHandlers = Object.keys(handlers);
				for (var i=0; i < activeHandlers.length ; i++)
				{
						this.ship.AIScript[activeHandlers[i]] = handlers[[activeHandlers[i]]].bind(this);
				}

		}

		/* ****************** Condition functions ************** */

		/* Conditions. Any function which returns true or false can be used as
		 * a condition. They do not have to be part of the AI library, but
		 * several common conditions are provided here. */

		this.conditionLosingCombat = function()
		{
				var cascade = this.getParameter("oolite_cascadeDetected");
				if (cascade != null)
				{
						if (cascade.distanceTo(this.ship) < 25600)
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
						if (this.ship.energy == this.ship.maxEnergy)
						{
								// forget previous defeats
								this.setParameter("oolite_lastFleeing",null);
						}
						return false;
				}
				var lastThreat = this.getParameter("oolite_lastFleeing");
				if (lastThreat != null && this.ship.position.distanceTo(lastThreat) < 25600)
				{
						// the thing that attacked us is still nearby
						return true;
				}
				if (this.ship.energy * 4 < this.ship.maxEnergy)
				{
						// TODO: adjust threshold based on group odds
						return true; // losing if less than 1/4 energy
				}
				var dts = this.ship.defenseTargets;
				for (var i = 0 ; i < dts.length ; i++)
				{
						if (dts[i].scanClass == "CLASS_MISSILE" && dts[i].target == this.ship)
						{
								return true;
						}
						if (dts[i].scanClass == "CLASS_MINE")
						{
								return true;
						}
				}
				// TODO: add some reassessment of odds based on group size
				return false; // not losing yet
		}

		this.conditionInCombat = function()
		{
				if (this.ship.target && this.ship.target.target == this.ship && this.ship.target.hasHostileTarget)
				{
						return true;
				}
				var dts = this.ship.defenseTargets;
				for (var i=0; i < dts.length; i++)
				{
						if (dts[i].position.squaredDistanceTo(this.ship) < this.ship.scannerRange * this.ship.scannerRange)
						{
								return true;
						}
				}
				if (this.ship.group != null)
				{
						for (var i = 0 ; i < this.ship.group.length ; i++)
						{
								if (this.ship.group[i].hasHostileTarget)
								{
										return true;
								}
						}
				}
				if (this.ship.escortGroup != null)
				{
						for (var i = 0 ; i < this.ship.escortGroup.length ; i++)
						{
								if (this.ship.escortGroup[i].hasHostileTarget)
								{
										return true;
								}
						}
				}
				return false;
		}


		this.conditionNearDestination = function()
		{
				return (this.ship.destination.squaredDistanceTo(this.ship) < this.ship.desiredRange * this.ship.desiredRange);
		}


		/* ****************** Behaviour functions ************** */

		/* Behaviours. Behaviours are effectively a state definition,
		 * defining a set of events and responses. They are aided in this
		 * by the 'responses', which mean that the event handlers for the
		 * behaviour within the definition can itself be templated.  */

		this.behaviourFleeCombat = function()
		{
				var handlers = {};
				this.responsesAddStandard(handlers);
				this.setUpHandlers(handlers);

				var cascade = this.getParameter("oolite_cascadeDetected");
				if (cascade != null)
				{
						if (cascade.distanceTo(this.ship) < 25600)
						{
								this.ship.destination = cascade;
								this.ship.desiredRange = 30000;
								this.ship.desiredSpeed = 10*this.ship.maxSpeed;
								this.ship.performFlyToRangeFromDestination();
								return;
						}
						else
						{
								this.setParameter("oolite_cascadeDetected",null);
						}
				}
				this.ship.target = this.ship.AIPrimaryAggressor;
				if (this.ship.position.distanceTo(this.ship.target) > 25600)
				{
						var dts = this.ship.defenseTargets;
						for (var i = 0 ; i < dts.length ; i++)
						{
								this.ship.position.distanceTo(dts[i]) < 25600;
								this.ship.target = dts[i];
								break;
						}
				}
				this.setParameter("oolite_lastFleeing",this.ship.target);
				this.ship.performFlee();
		}


		this.behaviourDestroyCurrentTarget = function()
		{
				var handlers = {};
				this.responsesAddStandard(handlers);
				this.setUpHandlers(handlers);
				this.ship.performAttack();
		}


		this.behaviourApproachDestination = function()
		{
				var handlers = {};
				this.responsesAddStandard(handlers);

				handlers.shipAchievedDesiredRange = function() 
				{
						var waypoints = this.getParameter("oolite_waypoints");
						log(this.name,"Reached desired range");
						if (waypoints != null)
						{
								if (waypoints.length > 0)
								{
										waypoints.pop();
										log(this.name,"Reached waypoint");
										if (waypoints.length == 0)
										{
												waypoints = null;
										}
										this.setParameter("oolite_waypoints",waypoints);
								}
						}
						this.reconsider();
				};

				var waypoints = this.getParameter("oolite_waypoints");
				if (waypoints != null)
				{
						this.ship.destination = waypoints[waypoints.length-1];
						this.ship.desiredRange = 1000;
				}
				var blocker = this.ship.checkCourseToDestination();
				if (blocker)
				{
						if (blocker.isPlanet || blocker.isSun)
						{
								if (this.ship.position.distanceTo(blocker) < blocker.radius * 3)
								{
										if (waypoints == null)
										{
												waypoints = [];
										}
										waypoints.push(this.ship.getSafeCourseToDestination());
										log(this.name,"Set new waypoint "+waypoints[waypoints.length-1]);
										this.ship.destination = waypoints[waypoints.length-1];
										this.ship.desiredRange = 1000;
								}
						}
						else if (blocker.isShip)
						{
								if (this.ship.position.distanceTo(blocker) < 25600)
								{
										if (waypoints == null)
										{
												waypoints = [];
										}
										waypoints.push(this.ship.getSafeCourseToDestination());
										this.ship.destination = waypoints[waypoints.length-1];
										this.ship.desiredRange = 1000;
								}
						}
				}
				this.setParameter("oolite_waypoints",waypoints);
				this.setUpHandlers(handlers);
				this.ship.performFlyToRangeFromDestination();
		}

		
		this.behaviourDockWithStation = function()
		{
				var station = this.getParameter("oolite_dockingStation");
				this.ship.target = station;
				var handlers = {};
				this.responsesAddStandard(handlers);
				this.responsesAddDocking(handlers);
				this.ship.requestDockingInstructions();
				switch (this.ship.dockingInstructions.ai_message)
				{
				case "TOO_BIG_TO_DOCK":
				case "DOCKING_REFUSED":
						this.ship.setParameter("oolite_dockingStation",null);
						this.ship.target = null;
						this.reconsider();
						break;
				case "HOLD_POSITION":
				case "TRY_AGAIN_LATER":
						this.ship.destination = this.ship.target.position;
						this.ship.performFaceDestination();
						// and will reconsider in a little bit
						break;
				case "APPROACH":				
				case "APPROACH_COORDINATES":
				case "BACK_OFF":
						this.ship.performFlyToRangeFromDestination();
						break;
				}
				this.setUpHandlers(handlers);
		}

		/* ****************** Configuration functions ************** */

		/* Configurations. Configurations are set up actions for a behaviour
		 * or behaviours. They can also be used on a fall-through conditional
		 * to set parameters for later tests */

		this.configurationAcquireCombatTarget = function()
		{
				/* Iff the ship does not currently have a target, select a new one
				 * from the defense target list. */
				if (this.ship.target && this.ship.target.isInSpace)
				{
						return;
				}
				var dts = this.ship.defenseTargets
				if (dts.length > 0)
				{
						this.ship.target = dts[0];
						return;
				}
				if (this.ship.group != null)
				{
						for (var i = 0 ; i < this.ship.group.length ; i++)
						{
								if (this.ship.group.ships[i] != this.ship)
								{
										if (this.ship.group.ships[i].target && this.ship.group.ships[i].hasHostileTarget)
										{
												this.ship.target = this.ship.group.ships[i].target;
												return;
										}
								}
						}
				}
				if (this.ship.escortGroup != null)
				{
						for (var i = 0 ; i < this.ship.escortGroup.length ; i++)
						{
								if (this.ship.escortGroup.ships[i] != this.ship)
								{
										if (this.ship.escortGroup.ships[i].target && this.ship.escortGroup.ships[i].hasHostileTarget)
										{
												this.ship.target = this.ship.escortGroup.ships[i].target;
												return;
										}
								}
						}
				}
		}


		/* ****************** Response definition functions ************** */

		/* Standard state-machine responses. These set up a set of standard
		 * state machine responses where incoming events will cause reasonable
		 * default behaviour and often force a reconsideration of
		 * priorities. Many behaviours will need to supplement the standard
		 * responses with additional definitions. */

		this.responsesAddStandard = function(handlers) {
				handlers.cascadeWeaponDetected = function(weapon)
				{
						this.ship.clearDefenseTargets();
						this.ship.addDefenseTarget(weapon);
						this.setParameter("oolite_cascadeDetected",weapon.position);
						this.ship.target = weapon;
						this.ship.performFlee();
						this.reconsider();
				};

				handlers.shipAttackedWithMissile = function(missile,whom)
				{
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
								this.reconsider();
						}
				};
				
				handlers.shipBeingAttacked = function(whom)
				{
						if (this.ship.defenseTargets.indexOf(whom) < 0)
						{
								this.ship.addDefenseTarget(whom);
								this.reconsider();
						}
						else 
						{
								// else we know about this attacker already
								if (this.ship.energy * 4 < this.ship.maxEnergy)
								{
										// but at low energy still reconsider
										this.reconsider();
										this.ship.requestHelpFromGroup();
								}
						}
						if (this.ship.escortGroup != null)
						{
								this.ship.requestHelpFromGroup();
						}
				};
				handlers.shipBeingAttackedUnsuccessfully = function(whom)
				{
						if (this.ship.defenseTargets.indexOf(whom) < 0)
						{
								this.ship.addDefenseTarget(whom);
								this.reconsider();
						}
				};
				handlers.shipTargetLost = function(target)
				{
						this.reconsider();
				};
				// TODO: this one needs overriding for escorts
				handlers.helpRequestReceived = function(ally, enemy)
				{
						this.ship.addDefenseTarget(enemy);
						if (!this.ship.hasHostileTarget)
						{
								return; // not in a combat mode
						}
						if (ally.energy / ally.maxEnergy < this.ship.energy / this.ship.maxEnergy)
						{
								// not in worse shape than ally
								if (this.ship.target.target != ally && this.ship.target != ally.target)
								{
										// not already helping, go for it...
										this.ship.target = enemy;
										this.reconsider();
								}
						}
				}
				handlers.approachingPlanetSurface = function()
				{
						this.reconsider();
				}
				// TODO: more event handlers
		}

		this.responsesAddDocking = function(handlers) {
				handlers.stationWithdrewDockingClearance = function()
				{
						this.setParameter("oolite_dockingStation",null);
						this.reconsider();
				};
				
				handlers.shipAchievedDesiredRange = function()
				{
						var message = this.ship.dockingInstructions.ai_message;
						if (message == "APPROACH" || message == "BACK_OFF" || message == "APPROACH_COORDINATES")
						{
								this.reconsider();
						}
				};

		}


}; // end object constructor


/* Object prototype */
AILib.prototype.constructor = AILib;
AILib.prototype.name = this.name;
