/*

pirateFreighterAI.js

Priority-based AI for pirate freighters leading large pirate groups

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

this.name = "Oolite Pirate Freighter AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_watchForCargo",true);

	ai.setCommunicationsRole("pirate");

	ai.setParameter("oolite_friendlyRoles",["oolite-pirate"]);

	// combat and looting behaviour same at all stages
	var common = [
		/* Combat */
		{
			condition: ai.conditionLosingCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		{
			label: "Cargo demands met?",
			condition: ai.conditionCargoDemandsMet,
			/* Let them go if they've dropped enough cargo and stop firing back */
			truebranch: [
				{
					condition: ai.conditionInCombatWithHostiles,
					configuration: ai.configurationAcquireHostileCombatTarget,
					behaviour: ai.behaviourRepelCurrentTarget,
					reconsider: 5
				}
			],
			falsebranch: [
				{
					condition: ai.conditionInCombat,
					configuration: ai.configurationAcquireCombatTarget,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 5
				}
			]
		},
		/* Collect loot. Don't worry too much about other group
		 * members. If they pick up stuff too that's good, but this is
		 * the ship with the hold... */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsSalvageForMe,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCollectSalvage,
			reconsider: 20
		},
		/* Stay away from dangerous stations */
		{
			condition: ai.conditionHostileStationNearby,
			configuration: ai.configurationSetDestinationToNearestStation,
			behaviour: ai.behaviourLeaveVicinityOfDestination,
			reconsider: 20
		},
		/* Are there hunters about? Avoid, or destroy if safe to do so. */
		{
			condition: ai.conditionScannerContainsHunters,
			configuration: ai.configurationAcquireScannedTarget,
			truebranch: [
				{
					condition: ai.conditionCombatOddsExcellent,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 10
				},
				{
					behaviour: ai.behaviourLeaveVicinityOfTarget,
					reconsider: 20
				}
			]
		}
	];

	var specific;
	if (this.ship.homeSystem == this.ship.destinationSystem)
	{
		// local piracy
		specific = [
			{
				label: "Enough loot?",
				condition: ai.conditionGroupHasEnoughLoot,
				truebranch: ai.templateReturnToBaseOrPlanet(),
				falsebranch: ai.templateLeadPirateMission()
			}
		];
	}
	else if (this.ship.homeSystem == system.ID && this.ship.fuel == 7)
	{
		// jump to destination system, taking group
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
		// pirate work, until enough cargo gathered or lose too many
		// fighters, then jump home. if we're in witchspace, just jump
		// home immediately!
		specific = [
			{
				condition: ai.conditionGroupHasEnoughLoot,
				truebranch: ai.templateWitchspaceJumpInbound()
			},
			{
				condition: ai.conditionGroupAttritionReached,
				truebranch: ai.templateWitchspaceJumpInbound()
			},
			{
				condition: ai.conditionInInterstellarSpace,
				truebranch: ai.templateWitchspaceJumpOutbound(),
				falsebranch: ai.templateLeadPirateMission()
			}
		];
	}

	var fallback = ai.templateWitchspaceJumpAnywhere();

	var priorities = common.concat(specific).concat(fallback);
	ai.setPriorities(priorities);
}