/*

pirateAI.js

Priority-based AI for pirates

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

this.name = "Oolite Pirate AI";
this.version = "1.79";

this.aiStarted = function() {
	this.ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_watchForCargo",true);

	ai.setCommunicationsRole("pirate");

	ai.setParameter("oolite_friendlyRoles",["oolite-pirate"]);

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
			condition: ai.conditionHostileStationNearby,
			configuration: ai.configurationSetDestinationToNearestStation,
			behaviour: ai.behaviourLeaveVicinityOfDestination,
			reconsider: 20
		},
		{
			condition: ai.conditionScannerContainsHunters,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourLeaveVicinityOfTarget,
			reconsider: 20
		},
		/* Regroup if necessary */
		{
			preconfiguration: ai.configurationAppointGroupLeader,
			condition: ai.conditionGroupIsSeparated,
			configuration: ai.configurationSetDestinationToGroupLeader,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 15
		},
		{
			label: "Enough loot?",
			condition: ai.conditionGroupHasEnoughLoot,
			/* Find a station to dock at */
			truebranch: [
				{
					condition: ai.conditionIsGroupLeader,
					truebranch: ai.templateReturnToBaseOrPlanet()
				},
				/* Once the group leader has docked or landed, another one gets
				 * appointed, and they can decide what to do next */
				{
					behaviour: ai.behaviourFollowGroupLeader,
					reconsider: 15
				}

			],
			/* Look for more loot */
			falsebranch: [
				{
					condition: ai.conditionIsGroupLeader,
					truebranch: ai.templateLeadPirateMission()
				},
				{
					behaviour: ai.behaviourFollowGroupLeader,
					reconsider: 15
				}
			]
		}
	].concat(ai.templateWitchspaceJumpAnywhere()));

}