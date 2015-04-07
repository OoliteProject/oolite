/*

bountyHunterAI.js

Priority-based AI for bounty hunters

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

// this is the AI version for a local patrol or an assistant
this.name = "Oolite Bounty Hunter AI";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_listenForDistressCall",true);

	ai.setWaypointGenerator(ai.waypointsSpacelanePatrol);

	ai.setParameter("oolite_personalityMatchesLeader",0.9);
	ai.setCommunicationsRole("hunter");

	ai.setParameter("oolite_friendlyRoles",["oolite-bounty-hunter"]);

	ai.setPriorities([
		/* Fight */
		{
			condition: ai.conditionLosingCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		{
			condition: ai.conditionInCombat,
			configuration: ai.configurationAcquireCombatTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 5
		},
		/* Follow leader to witchspace */
		{
			condition: ai.conditionWitchspaceEntryRequested,
			behaviour: ai.behaviourEnterWitchspace,
			reconsider: 15
		},
		{
			condition: ai.conditionInNovaSpace,
			truebranch: ai.templateWitchspaceJumpAnywhere()
		},
		/* Check for distress calls */
		{
			condition: ai.conditionHasReceivedDistressCall,
			behaviour: ai.behaviourRespondToDistressCall,
			reconsider: 20
		},
		/* Regroup if necessary, but act relatively
		 * independently. Bounty hunters are not like police
		 * patrols. */
		{
			preconfiguration: ai.configurationAppointGroupLeader,
			condition: ai.conditionGroupIsSeparated,
			configuration: ai.configurationSetDestinationToGroupLeader,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 15
		},
		/* Check for profitable targets */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsFugitive,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCommenceAttackOnCurrentTarget,
			reconsider: 1
		},
		{
			condition: ai.conditionScannerContainsHuntableOffender,
			configuration: ai.configurationAcquireScannedTarget,
			truebranch: [
				/* if we require bounty hunters to have actual *good*
				 * odds they'll never shoot anything */
				{
					notcondition: ai.conditionCombatOddsBad,
					behaviour: ai.behaviourCommenceAttackOnCurrentTarget,
					reconsider: 1
				}
			]
		},
		/* What about loot? */
		{
			condition: ai.conditionScannerContainsSalvageForMe,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCollectSalvage,
			reconsider: 20
		},
		{
			condition: ai.conditionIsGroupLeader,
			truebranch: ai.templateLeadHuntingMission(),
			/* then follow the group leader */
			falsebranch: [
				{
					behaviour: ai.behaviourFollowGroupLeader,
					reconsider: 15
				}
			],
		}
	].concat(ai.templateWitchspaceJumpAnywhere()));
}