/* AI Library */
this.name = "oolite-libPriorityAI";
this.version = "1.79";

/* Constructor */

this.AILib = function(ship)
{
		this.ship = ship;
		var activeHandlers = [];
		var priorityList = null;
		var reconsiderationTimer = null;
		var parameters = {};

		/* Private utility functions */

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
						log(this.name,"AI ("+this.ship.AIScript.name+") had all priorities fail. All priority based AIs should end with an unconditional entry.");
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
				if (!this.conditionInCombat()) 
				{
						return false;
				}
				if (this.ship.energy * 4 < this.ship.maxEnergy)
				{
						// TODO: adjust threshold based on entityPersonality,
						// accuracy, and tactical situation (especially: is there
						// something which has caused us to flee still nearby)
						return true; // losing if less than 1/4 energy
				}
				// TODO: if there's a missile on the defense target list and
				// it's pointed at us, we're losing (if the ECM worked, then
				// we can go back to normal in a few seconds)

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
				// TODO: check if other group members are in combat 
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
				// TODO: select a random hostile instead if primary aggressor
				// is out of range
				this.ship.target = this.ship.AIPrimaryAggressor;
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
				}
				// TODO: pick a target of another group member
		}


		/* ****************** Response definition functions ************** */

		/* Standard state-machine responses. These set up a set of standard
		 * state machine responses where incoming events will cause reasonable
		 * default behaviour and often force a reconsideration of
		 * priorities. Many behaviours will need to supplement the standard
		 * responses with additional definitions. */

		this.responsesAddStandard = function(handlers) {
				//				"cascadeWeaponDetected" : TODO
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
								}
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
