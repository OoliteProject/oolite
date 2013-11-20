/*

escortAI.js

Priority-based AI for escorts

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

this.name = "Oolite Escort AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setCommunicationsRole("escort");
	ai.setParameter("oolite_flag_scanIgnoresUnpowered",true);

	ai.setPriorities([
		{
			condition: ai.conditionLosingCombat,
			behaviour: ai.behaviourFleeCombat,
			reconsider: 5
		},
		{
			condition: ai.conditionMothershipInCombat,
			truebranch: [
				{
					condition: ai.conditionMothershipUnderAttack,
					configuration: ai.configurationAcquireDefensiveEscortTarget,
					behaviour: ai.behaviourRepelCurrentTarget,
					reconsider: 5
				},
				{
					condition: ai.conditionMothershipIsAttacking,
					configuration: ai.configurationAcquireOffensiveEscortTarget,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 5
				},
				{
					behaviour: ai.behaviourRejoinMothership,
					reconsider: 5
				}
			]
		},
		{
			// if we're in combat but mothership isn't, then we need
			// to finish this fight off and get back to them
			condition: ai.conditionInCombat,
			configuration: ai.configurationAcquireCombatTarget,
			behaviour: ai.behaviourRepelCurrentTarget,
			reconsider: 5
		},
		{
			condition: ai.conditionWitchspaceEntryRequested,
			behaviour: ai.behaviourEnterWitchspace,
			reconsider: 15
		},
		{
			condition: ai.conditionIsEscorting,
			behaviour: ai.behaviourEscortMothership,
			reconsider: 60
		},
		/* Don't have a mothership */
		{
			condition: ai.conditionFriendlyStationNearby,
			configuration: ai.configurationSetNearbyFriendlyStationForDocking,
			behaviour: ai.behaviourDockWithStation,
			reconsider: 30
		},
		/* And it's not because they just docked either */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsShipNeedingEscort,
			behaviour: ai.behaviourOfferToEscort,
			reconsider: 15
		},
		{
			condition: ai.conditionFriendlyStationExists,
			configuration: ai.configurationSetDestinationToNearestFriendlyStation,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		},
		/* No friendly stations and no nearby ships needing escort */
		{
			condition: ai.conditionCanWitchspaceOut,
			configuration: ai.configurationSelectWitchspaceDestination,
			behaviour: ai.behaviourEnterWitchspace,
			reconsider: 20
		},
		/* And we're stuck here, but something to escort will probably
		 * show up at the witchpoint sooner or later */
		{
			configuration: ai.configurationSetDestinationToWitchpoint,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		}
	]);
}