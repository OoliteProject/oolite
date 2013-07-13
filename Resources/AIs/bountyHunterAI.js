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

		/* Communications currently for debugging purposes. Need to either
		 * be removed or given a much bigger set of phrases to choose from
		 * before 1.79 */
		ai.setCommunication("oolite_spacelanePatrol","Setting course for the [p1]");
		ai.setCommunication("oolite_distressResponseSender","Hold on, [p1]!");
		ai.setCommunication("oolite_distressResponseAggressor","[p1]. Cease your attack or be destroyed!");
		ai.setCommunication("oolite_beginningAttack","Scan confirms criminal status of [p1]. Commencing attack run");
		ai.setCommunication("oolite_quiriumCascade","%N! Q-bomb!");
		ai.setCommunication("oolite_friendlyFire","Hey! Watch where you're shooting, [p1].");

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
						behaviour: ai.behaviourDestroyCurrentTarget,
						reconsider: 1
				},
				/* What about loot? */
				{
						condition: ai.conditionScannerContainsSalvage,
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
						condition: ai.conditionHasPatrolRoute,
						configuration: ai.configurationSetDestinationFromPatrolRoute,
						behaviour: ai.behaviourApproachDestination,
						reconsider: 30
				},
				/* No patrol route set up. Make one */
				{
						configuration: ai.configurationMakeSpacelanePatrolRoute,
						behaviour: ai.behaviourApproachDestination,
						reconsider: 30
				}
		]);
}