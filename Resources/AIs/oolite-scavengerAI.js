/*

scavengerAI.js

Priority-based AI for scavengers and miners

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

this.name = "Oolite Scavenger AI";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setCommunicationsRole("scavenger");

	ai.setPriorities([
		/* Fight */
		{
			condition: ai.conditionInCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		/* Don't hang around near hostile stations */
		{
			condition: ai.conditionHostileStationNearby,
			configuration: ai.configurationSetDestinationToNearestHostileStation,
			behaviour: ai.behaviourLeaveVicinityOfDestination,
			reconsider: 20
		},
		/* Is there any loot? */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsSalvageForMe,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourCollectSalvage,
			reconsider: 20
		},
		/* Branch for mining ships: if we can usefully mine asteroids, do so */
		{
			condition: ai.conditionScannerContainsMiningOpportunity,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourMineTarget,
			reconsider: 20
		},
		/* No loot and no safe way to make some; return to base */
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