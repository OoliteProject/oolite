/*

traderAI.js

Priority-based AI for traders

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

this.name = "Oolite Trader AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].AILib(this.ship);

	ai.setParameter("oolite_flag_sendsDistressCalls",true);

	ai.setCommunicationsRole("trader");


	ai.setPriorities([
		{
			condition: ai.conditionLosingCombat,
			truebranch: [
				{
					condition: ai.conditionPiratesCanBePaidOff,
					behaviour: ai.behaviourPayOffPirates,
					reconsider: 5
				},
				{
					behaviour: ai.behaviourFleeCombat,
					reconsider: 5
				}
			]
		},
		{ 
			condition: ai.conditionInCombat,
			configuration: ai.configurationAcquireCombatTarget,
			// not required to destroy target, just to get it to leave
			behaviour: ai.behaviourRepelCurrentTarget,
			reconsider: 5
		},
		{
			condition: ai.conditionCargoIsProfitableHere,
			// branch to head for station
			truebranch: [
				{
					condition: ai.conditionHasSelectedStation,
					truebranch: [
						{
							condition: ai.conditionSelectedStationNearby,
							configuration: ai.configurationSetSelectedStationForDocking,
							behaviour: ai.behaviourDockWithStation,
							reconsider: 30
						},
						{
							condition: ai.conditionSelectedStationNearMainPlanet,
							truebranch: [
								{
									notcondition: ai.conditionMainPlanetNearby,
									configuration: ai.configurationSetDestinationToMainPlanet,
									behaviour: ai.behaviourApproachDestination,
									reconsider: 30
								}
							]
						},
						// either the station isn't near the planet, or we are
						{
							configuration: ai.configurationSetDestinationToSelectedStation,
							behaviour: ai.behaviourApproachDestination,
							reconsider: 30
						}
					],
					falsebranch: [
						{
							configuration: ai.configurationSelectRandomTradeStation,
							behaviour: ai.behaviourReconsider
						}
					]
				}
			],
			// jump to another system if possible, sunskim if not
			falsebranch: [
				{
					condition: ai.conditionCanWitchspaceOut,
					configuration: ai.configurationSelectWitchspaceDestination,
					behaviour: ai.behaviourEnterWitchspace,
					reconsider: 20
				},
				{
					condition: ai.conditionReadyToSunskim,
					configuration: ai.configurationSetDestinationToSunskimEnd,
					behaviour: ai.behaviourSunskim,
					reconsider: 20
				},
				{
					condition: ai.conditionSunskimPossible,
					configuration: ai.configurationSetDestinationToSunskimStart,
					behaviour: ai.behaviourApproachDestination,
					reconsider: 30
				}
			]
		}, // end of cargoprofitable true/false branches
		{
			// if we're here, the cargo isn't profitable, and we can't
			// witchspace out or sunskim
			condition: ai.conditionInInterstellarSpace,
			configuration: ai.configurationSetDestinationToWitchpoint,
			// TODO: behaviour search for wormholes
			behaviour: ai.behaviourApproachDestination
		},
		{
			condition: ai.conditionFriendlyStationNearby,
			configuration: ai.configurationSetNearbyFriendlyStationForDocking,
			behaviour: ai.behaviourDockWithStation,
			reconsider: 30
		},
		{
			condition: ai.conditionFriendlyStationExists,
			configuration: ai.configurationSetDestinationToNearestFriendlyStation,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		},
		{
			// stuck and no friendly stations
			configuration: ai.configurationSetDestinationToWitchpoint,
			// TODO: behaviour search for wormholes
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		}
	]);
}