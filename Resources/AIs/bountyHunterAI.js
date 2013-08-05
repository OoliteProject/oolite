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

this.name = "Oolite Bounty Hunter AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].AILib(this.ship);

	ai.setParameter("oolite_flag_listenForDistressCall",true);
	ai.setWaypointGenerator(ai.waypointsSpacelanePatrol);

	ai.setCommunicationsRole("hunter");

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
			behaviour: ai.behaviourDestroyCurrentTarget,
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
					behaviour: ai.behaviourDestroyCurrentTarget,
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
		/* Check we're in a real system */
		{
			condition: ai.conditionInInterstellarSpace,
			configuration: ai.configurationSelectWitchspaceDestination,
			behaviour: ai.behaviourEnterWitchspace,
			reconsider: 20
		},
		/* Nothing interesting here. Patrol for a bit */
		{
			condition: ai.conditionHasWaypoint,
			configuration: ai.configurationSetDestinationToWaypoint,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		},
		/* No patrol route set up. Make one */
		{
			configuration: ai.configurationSetWaypoint,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		}
	]);
}