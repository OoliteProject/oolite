/*

defenseShipAI.js

Priority-based AI for defense ships

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

this.name = "Oolite Defense Ship AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setCommunicationsRole("defenseShip");


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
			behaviour: ai.behaviourRepelCurrentTarget,
			reconsider: 5
		},
		{
			condition: ai.conditionMothershipIsAttackingHostileTarget,
			configuration: ai.configurationAcquireCombatTarget,
			behaviour: ai.behaviourRepelCurrentTarget,
			reconsider: 5
		},
		/* Battle is over; return to base */
		{
			condition: ai.conditionHomeStationNearby,
			configuration: ai.configurationSetHomeStationForDocking,
			behaviour: ai.behaviourDockWithStation,
			reconsider: 30
		},
		{
			condition: ai.conditionHomeStationExists,
			configuration: ai.configurationSetDestinationToHomeStation,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		},
		/* Or at least return to somewhere */
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
		}
	].concat(ai.templateWitchspaceJumpAnywhere()));
}