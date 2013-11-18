/*

assassinAI.js

Priority-based AI for assassins

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

this.name = "Oolite Assassin AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	if (system.mainStation && system.mainStation.position.distanceTo(this.ship) < 25000 && Math.random() < 0.5)
	{
		// if launching from (near) main station, sometimes hang around the
		// aegis to wait for a launching courier
		ai.setWaypointGenerator(ai.waypointsStationPatrol);
	}
	else
	{
		ai.setWaypointGenerator(ai.waypointsWitchpointPatrol);
	}

	ai.setCommunicationsRole("assassin");

	ai.setParameter("oolite_flag_witchspacePursuit",true);
	ai.setParameter("oolite_flag_surrendersLate",true);

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
		/* Follow targets to witchspace */
		{
			condition: ai.conditionWitchspaceEntryRequested,
			behaviour: ai.behaviourEnterWitchspace,
			reconsider: 15
		},
		{
			condition: ai.conditionHasRememberedTarget,
			behaviour: ai.behaviourFollowCurrentTarget,
			reconsider: 15
		},
		/* Check for couriers */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsCourier,
			truebranch: [
				{
					condition: ai.conditionStationNearby,
					truebranch: [
						{
							configuration: ai.configurationAcquireScannedTarget,
							behaviour: ai.behaviourFollowCurrentTarget,
							reconsider: 15
						}
					],
					falsebranch: [
						{
							preconfiguration: ai.configurationAcquireScannedTarget,
							condition: ai.conditionCombatOddsGood,
							behaviour: ai.behaviourDestroyCurrentTarget,
							reconsider: 1
						}
					]
				}
			]
		},
		/* Shoot the escape pods */
		{
			condition: ai.conditionScannerContainsAssassinationTarget,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 20
		},
		{
			preconfiguration: ai.configurationAppointGroupLeader,
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