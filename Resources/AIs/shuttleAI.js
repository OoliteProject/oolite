/*

shuttleAI.js

Priority-based AI for in-system shuttles

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

this.name = "Oolite Shuttle AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_sendsDistressCalls",true);
	ai.setParameter("oolite_flag_allowPlanetaryLanding",true);

	ai.setCommunicationsRole("shuttle");

	ai.setPriorities([
		{
			condition: ai.conditionInCombat,
			behaviour: ai.behaviourFleeCombat
		},
		{
			condition: ai.conditionHostileStationNearby,
			configuration: ai.configurationSetDestinationToNearestStation,
			behaviour: ai.behaviourLeaveVicinityOfDestination,
			reconsider: 20
		},
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
					configuration: ai.configurationSetDestinationToSelectedStation,
					behaviour: ai.behaviourApproachDestination,
					reconsider: 30
				}
			]
		},
		{
			condition: ai.conditionHasSelectedPlanet,
			truebranch: [
				{
					preconfiguration: ai.configurationSetDestinationToSelectedPlanet,
					condition: ai.conditionNearDestination,
					behaviour: ai.behaviourLandOnPlanet
				},
				{
					behaviour: ai.behaviourApproachDestination,
					reconsider: 30
				}
			]
		},
		/* TODO: need to try to hitchhike out! */
		{
			condition: ai.conditionInInterstellarSpace,
			truebranch: ai.templateWitchspaceJumpAnywhere()
		},
		{
			configuration: ai.configurationSelectShuttleDestination,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 1
		}
	]);
}