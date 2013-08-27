/*

pirateInterceptorAI.js

Priority-based AI for pirate interceptors (fly defense for 

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
this.version = "1.79";

this.aiStarted = function() {
	this.ai = new worldScripts["oolite-libPriorityAI"].AILib(this.ship);

	ai.setParameter("oolite_flag_surrendersLate",true);

	// to hunt the hunters, go where they go
	ai.setWaypointGenerator(ai.waypointsSpacelanePatrol);

	ai.setCommunicationsRole("pirate");
	
	var common = [
		/* Combat */
		{
			condition: ai.conditionLosingCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		{
			condition: ai.conditionInCombat,
			configuration: ai.configurationAcquireCombatTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 10
		},
		{
			/* don't check odds first, make sure we get at least a little
			 * weapons fire */
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsHunters,
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

	var fallback = [
		{
			// stuck in system and no friendly stations
			configuration: ai.configurationSetDestinationToWitchpoint,
			// TODO: behaviour search for wormholes
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		}
	];

	var priorities = common.concat(specific).concat(fallback);

	ai.setPriorities(priorities);

}