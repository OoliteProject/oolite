/*

bountyHunterLeaderAI.js

Priority-based AI for bounty hunter leaders

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

this.name = "Oolite Bounty Hunter Leader AI";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_listenForDistressCall",true);

	ai.setWaypointGenerator(ai.waypointsSpacelanePatrol);

	ai.setParameter("oolite_personalityMatchesLeader",0.9);
	ai.setCommunicationsRole("hunter");

	ai.setParameter("oolite_friendlyRoles",["oolite-bounty-hunter"]);

	var common = [
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
		/* Check for distress calls */
		{
			condition: ai.conditionHasReceivedDistressCall,
			behaviour: ai.behaviourRespondToDistressCall,
			reconsider: 20
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
		}
	];
	var specific;
	if (this.ship.homeSystem == this.ship.destinationSystem)
	{
		// local patrol
		specific = [
			{
				condition: ai.conditionGroupAttritionReached,
				truebranch: ai.templateReturnToBase(),
				falsebranch: ai.templateLeadHuntingMission()
			}
		];
	}
	else if (this.ship.homeSystem == system.ID && this.ship.fuel == 7)
	{
		// jump to destination system, taking group
		specific = ai.templateWitchspaceJumpOutbound().concat(ai.templateReturnToBase());
	}
	else if (this.ship.homeSystem == system.ID)
	{
		// if not at full fuel, we're probably returning home. Or
		// something went wrong when trying to enter witchspace that
		// needed injectors to fix.
		specific = ai.templateReturnToBase();
	}
	else
	{
		// patrol for a little bit, or until lose too many fighters,
		// then jump home or return to base (unlike pirates, docking
		// at local stations is okay if it's possible)
		specific = [
			{
				condition: ai.conditionGroupAttritionReached,
				truebranch: ai.templateWitchspaceJumpInbound()
			},
			{
				condition: ai.conditionInInterstellarSpace,
				truebranch: ai.templateWitchspaceJumpInbound(),
				falsebranch: ai.templateLeadHuntingMission()
			}
		];
	}

	var fallback = ai.templateWitchspaceJumpAnywhere();

	var priorities = common.concat(specific).concat(fallback);
	ai.setPriorities(priorities);

}