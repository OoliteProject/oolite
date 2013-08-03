/*

thargletAI.js

Priority-based AI for Tharglet drones

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

this.name = "Oolite Tharglet AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].AILib(this.ship);

	ai.setCommunicationsRole("_thargoid");
	ai.setCommunicationsPersonality("tharglet");

	ai.setPriorities([
		/* Check for mothership */
		{
			condition: ai.conditionHasMothership,
			truebranch: [
				{
					condition: ai.conditionGroupIsSeparated,
					configuration: ai.configurationLeaveEscortGroup,
					behaviour: ai.behaviourReconsider
				},
				{
					condition: ai.conditionCascadeDetected,
					behaviour: ai.behaviourAvoidCascadeExplosion,
					reconsider: 5
				},
				{
					condition: ai.conditionMothershipInCombat,
					configuration: ai.configurationAcquireOffensiveEscortTarget,
					behaviour: ai.behaviourDestroyCurrentTarget,
					reconsider: 5
				},
				{
					behaviour: ai.behaviourEscortMothership,
					reconsider: 5
				}
			],
			falsebranch: [
				{
					preconfiguration: ai.configurationCheckScanner,
					condition: ai.conditionScannerContainsReadyThargoidMothership,
					behaviour: ai.behaviourOfferToEscort,
					reconsider: 5
				},
				{
					condition: ai.conditionIsActiveThargon,
					behaviour: ai.behaviourBecomeInactiveThargon,
					reconsider: 10
				},
				{
					behaviour: ai.behaviourTumble
				}
			]
		}
	]);
}