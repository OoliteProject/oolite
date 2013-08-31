/*

rockHermitAI.js

Priority-based AI for rock hermits

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

this.name = "Oolite Rock Hermit AI";
this.version = "1.79";

this.aiStarted = function() {
		var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setCommunicationsRole("station");

		ai.setPriorities([
				/* Fight */
				{
						preconfiguration: ai.configurationStationValidateTarget,
						condition: ai.conditionInCombat,
						behaviour: ai.behaviourStationLaunchDefenseShips,
						reconsider: 5
				},
				/* Scan */
				{
						preconfiguration: ai.configurationCheckScanner,
						condition: ai.conditionScannerContainsRocks,
						behaviour: ai.behaviourStationLaunchMiner,
						reconsider: 60
				},
				{
						configuration: ai.configurationStationReduceAlertLevel,
						behaviour: ai.behaviourStationManageTraffic,
						reconsider: 60
				}
		]);
}