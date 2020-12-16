/*

policeAI.js

Priority-based AI for police

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

this.name = "Oolite Police AI";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_listenForDistressCall",true);
	ai.setParameter("oolite_flag_markOffenders",true);
	ai.setParameter("oolite_flag_fightsNearHostileStations",true);
	ai.setParameter("oolite_flag_selfDestructAbandonedShip",true);

	if (this.ship.primaryRole == "police-station-patrol") 
	{
		ai.setParameter("oolite_leaderRole","police-station-patrol");
		ai.setWaypointGenerator(ai.waypointsStationPatrol);
		ai.setParameter("oolite_flag_patrolStation",true);
	}
	else if (this.ship.primaryRole == "police-witchpoint-patrol") 
	{
		ai.setParameter("oolite_leaderRole","police-witchpoint-patrol");
		ai.setWaypointGenerator(ai.waypointsWitchpointPatrol);
	}
	else
	{
		// chasing a bandit well off the spacelane is almost as good
		// as destroying them
		ai.setParameter("oolite_leaderRole","police");
		ai.setWaypointGenerator(ai.waypointsSpacelanePatrol);
	}

	ai.setParameter("oolite_escortRole","wingman");

	ai.setParameter("oolite_friendlyRoles",["oolite-trader","oolite-bounty-hunter","oolite-scavenger","oolite-shuttle"]);

	ai.setParameter("oolite_personalityMatchesLeader",0.5);
	ai.setCommunicationsRole("police");

	ai.setPriorities([
		/* Fight */
		{ // 0
			preconfiguration: ai.configurationLightsOn,
			condition: ai.conditionLosingCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		{ // 1
			condition: ai.conditionInCombat,
			configuration: ai.configurationAcquireCombatTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 5
		},
		/* Check for distress calls */
		{ // 2
			condition: ai.conditionHasReceivedDistressCall,
			behaviour: ai.behaviourRespondToDistressCall,
			reconsider: 20
		},
		/* Check for offenders */
		{ // 3
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsFugitive,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCommenceAttackOnCurrentTarget,
			reconsider: 1
		},
		{ // 4
			condition: ai.conditionScannerContainsSeriousOffender,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCommenceAttackOnCurrentTarget,
			reconsider: 1
		},
		{ // 5
			preconfiguration: ai.configurationLightsOff,
			condition: ai.conditionScannerContainsFineableOffender,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourFineCurrentTarget,
			reconsider: 10
		},
		/* What about escape pods? */
		{ // 6
			condition: ai.conditionScannerContainsEscapePods,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCollectSalvage,
			reconsider: 20
		},
		/* Regroup if necessary */
		{ // 7
			preconfiguration: ai.configurationAppointGroupLeader,
			condition: ai.conditionGroupIsSeparated,
			configuration: ai.configurationSetDestinationToGroupLeader,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 15
		},
		{ // 8
			condition: ai.conditionGroupLeaderIsStation,
			/* Group leader is the station: a short-range patrol or
			 * defense ship */
			truebranch: [
				{ // 8-T-0
					condition: ai.conditionHasWaypoint,
					configuration: ai.configurationSetDestinationToWaypoint,
					behaviour: ai.behaviourApproachDestination,
					reconsider: 30
				},
				{ // 8-T-1
					condition: ai.conditionPatrolIsOver,
					truebranch: ai.templateReturnToBase()
				},
				/* No patrol route set up. Make one */
				{ // *-T-2
					configuration: ai.configurationSetWaypoint,
					behaviour: ai.behaviourApproachDestination,
					reconsider: 30
				}
			],
			/* Group leader is not station: i.e. this is a long-range
			 * patrol unit */
			falsebranch: [
				{ // 8-F-0
					/* The group leader leads the patrol */
					condition: ai.conditionIsGroupLeader,
					truebranch: [
						{ // 8-F-T-0
							/* Sometimes follow, sometimes not */
							label: "Consider following suspicious?",
							condition: ai.conditionCoinFlip,
							truebranch: [
								/* Suspicious characters */
								{ // 8-F-T-0-T-0
									condition: ai.conditionScannerContainsSuspiciousShip,
									configuration: ai.configurationSetDestinationToScannedTarget,
									behaviour: ai.behaviourApproachDestination,
									reconsider: 20
								}
							]
						},
						/* Nothing interesting here. Patrol for a bit */
						{ // 8-F-T-1
							condition: ai.conditionHasWaypoint,
							configuration: ai.configurationSetDestinationToWaypoint,
							behaviour: ai.behaviourApproachDestination,
							reconsider: 30
						},
						{ // 8-F-T-2
							condition: ai.conditionPatrolIsOver,
							truebranch: [
								{
									condition: ai.conditionMainPlanetNearby,
									truebranch: ai.templateReturnToBase()
								}
							]
						},
						/* No patrol route set up. Make one */
						{ // 8-F-T-3
							configuration: ai.configurationSetWaypoint,
							behaviour: ai.behaviourApproachDestination,
							reconsider: 30
						}
					],
					/* Other ships in the group will set themselves up
					 * as escorts if possible, or looser followers if
					 * not */
					falsebranch: [
						{ // 8-F-F-0
							preconfiguration: ai.configurationEscortGroupLeader,
							condition: ai.conditionIsEscorting,
							behaviour: ai.behaviourEscortMothership,
							reconsider: 30
						},
						/* if we can't set up as an escort */
						{ // 8-F-F-1
							behaviour: ai.behaviourFollowGroupLeader,
							reconsider: 15
						}
					]
				}
			]
		}
	]);

}
