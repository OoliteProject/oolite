/*

thargoidAI.js

Priority-based AI for Thargoid warships

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

this.name = "Oolite Thargoid AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].AILib(this.ship);

	ai.setCommunicationsRole("_thargoid");
	ai.setCommunicationsPersonality("thargoid");

	ai.setPriorities([
		/* Fight */
		{
			condition: ai.conditionCascadeDetected,
			behaviour: ai.behaviourAvoidCascadeExplosion,
			reconsider: 5
		},
		{
			condition: ai.conditionHasNonThargoidTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 5
		},
		/* Check for targets */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsNonThargoid,
			configuration: ai.configurationAcquireScannedTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 1
		},
		/* No targets */
		/* Interstellar space is straightforward */
		{
			condition: ai.conditionInInterstellarSpace,
			configuration: ai.configurationSetDestinationToWitchpoint,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 20
		},
		/* Otherwise, look for targets. Mission: harass shipping. */
		{
			configuration: ai.configurationSetDestinationToPirateLurk,
			behaviour: ai.behaviourApproachDestination,
			reconsider: 30
		}
	]);
}