/*

pirateInterceptorAI.js

Priority-based AI for pirate interceptors (fly defense for other
pirates)

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

this.name = "Oolite Pirate Interceptor AI";

this.aiStarted = function() {
	this.ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);
        var ai = this.ai;

	ai.setParameter("oolite_flag_surrendersLate",true);
	ai.setParameter("oolite_flag_fightsNearHostileStations",true);

	// to hunt the hunters, go where they go
	var searchalgorithm = ai.conditionScannerContainsHunters;
	var commsrole = "pirate";
	if (this.ship.primaryRole == "pirate-aegis-raider")
	{
		if (worldScripts["oolite-libPriorityAI"]._getCommunicationPersonalities("pirate-aegis-raider").length > 0)
		{
			commsrole = "pirate-aegis-raider";
		}
		searchalgorithm = ai.conditionScannerContainsCleanShip;
		ai.setWaypointGenerator(ai.waypointsStationPatrol);
	}
	else
	{
		if (worldScripts["oolite-libPriorityAI"]._getCommunicationPersonalities("pirate-aegis-raider").length > 0)
		{
			commsrole = "pirate-interceptor";
		}
		ai.setWaypointGenerator(ai.waypointsSpacelanePatrol);
	}

	ai.setParameter("oolite_personalityMatchesLeader",0.95);
	ai.setCommunicationsRole(commsrole);

	ai.setParameter("oolite_friendlyRoles",["oolite-pirate"]);
	
	var common = [
		/* Combat */
		{
			condition: ai.conditionLosingCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		{
			condition: ai.conditionInCombat,
			truebranch: [
				{
					/* If supplies are low, flee */
					condition: ai.conditionSuppliesLow,
					behaviour: ai.behaviourFleeCombat,
					reconsider: 5
				},
				{
					configuration: ai.configurationAcquireCombatTarget,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 10
				}
			]
		},
		{
			/* If supplies are low, return to base */
			condition: ai.conditionSuppliesLow,
			falsebranch: [
				{
					/* don't check odds first, make sure we get at
					 * least a little weapons fire */
					preconfiguration: ai.configurationCheckScanner,
					condition: searchalgorithm, // varied by role above
					configuration: ai.configurationAcquireScannedTarget,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 20 
				},
				{
					condition: ai.conditionScannerContainsShipAttackingPirate,
					configuration: ai.configurationAcquireScannedTarget,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 20 
				}
			]
		}
	];

	var specific;
	if (this.ship.homeSystem == this.ship.destinationSystem)
	{
		/* Patrol waypoints for a bit, then return */
		specific = [
			{
				condition: ai.conditionHasWaypoint,
				configuration: ai.configurationSetDestinationToWaypoint,
				behaviour: ai.behaviourApproachDestination,
				reconsider: 30
			},
			{
				condition: ai.conditionPatrolIsOver,
				truebranch: ai.templateReturnToBaseOrPlanet()
			},
			{
				configuration: ai.configurationSetWaypoint,
				behaviour: ai.behaviourApproachDestination,
				reconsider: 30
			}
		];
	}
	else if (this.ship.homeSystem == system.ID && this.ship.fuel == 7)
	{
		// jump to destination system independently of freighters
		// (since interceptors are just added *with* them, not to
		// their group)
		specific = ai.templateWitchspaceJumpOutbound().concat(ai.templateReturnToBaseOrPlanet());
	}
	else if (this.ship.homeSystem == system.ID)
	{
		// if not at full fuel, we're probably returning home. Or
		// something went wrong when trying to enter witchspace that
		// needed injectors to fix.
		specific = ai.templateReturnToBaseOrPlanet();
	}
	else
	{
		/* Patrol waypoints for a bit, then return */
		specific = [
			{
				condition: ai.conditionHasWaypoint,
				configuration: ai.configurationSetDestinationToWaypoint,
				behaviour: ai.behaviourApproachDestination,
				reconsider: 30
			},
			{
				condition: ai.conditionPatrolIsOver,
				truebranch: ai.templateWitchspaceJumpOutbound()
			},
			{
				configuration: ai.configurationSetWaypoint,
				behaviour: ai.behaviourApproachDestination,
				reconsider: 30
			}
		];
		
	}

	var fallback = ai.templateWitchspaceJumpAnywhere();

	var priorities = common.concat(specific).concat(fallback);

	ai.setPriorities(priorities);

}
