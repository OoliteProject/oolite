/*

pirateFighterAI.js

Priority-based AI for pirate fighters (guards and extra capacity for
organised pirate gangs)

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

this.name = "Oolite Pirate Fighter AI";
this.version = "1.79";

this.aiStarted = function() {
	this.ai = new worldScripts["oolite-libPriorityAI"].AILib(this.ship);

	ai.setParameter("oolite_flag_watchForCargo",true);

	ai.setCommunicationsRole("pirate");


	ai.setPriorities([
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
		{
			condition: ai.conditionWitchspaceEntryRequested,
			behaviour: ai.behaviourEnterWitchspace,
			reconsider: 15
		},
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsSalvageForGroup,
			truebranch: [
				{
					condition: ai.conditionScannerContainsSalvageForMe,
					configuration: ai.configurationAcquireScannedTarget,
					behaviour: ai.behaviourCollectSalvage,
					reconsider: 20
				},
				// if can't scoop, hang around waiting for the others,
				// unless the entire group has enough cargo
				{
					notcondition: ai.conditionGroupHasEnoughLoot,
					configuration: ai.configurationSetDestinationToGroupLeader,
					behaviour: ai.behaviourApproachDestination,
					reconsider: 15
				}
			]
		},
		/* Stay out of the way of hunters */
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
		},
		/* Follow leader */
		{
			condition: ai.conditionHasMothership,
			configuration: ai.configurationSetDestinationToGroupLeader,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 15
		},
		/* Find a new leader, or return to base */
		{
			condition: ai.conditionScannerContainsPirateLeader,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourJoinTargetGroup,
			reconsider: 10,
			falsebranch: ai.templateReturnToBaseOrPlanet()
		},
		{
			// full of loot, but stuck in system and no friendly stations
			configuration: ai.configurationSetDestinationToWitchpoint,
			// TODO: behaviour search for wormholes
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		}
	]);

}