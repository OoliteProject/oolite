/*

stationAI.js

Priority-based AI for main stations

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

this.name = "Oolite Main Station AI";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setParameter("oolite_flag_listenForDistressCall",true);
	ai.setParameter("oolite_flag_markOffenders",true);
	ai.setParameter("oolite_stationPatrolRole","police-station-patrol");

	ai.setCommunicationsRole("station");

	ai.setParameter("oolite_friendlyRoles",["oolite-trader","oolite-bounty-hunter","oolite-scavenger","oolite-shuttle"]);

	ai.setPriorities([
		/* Fight */
		{
			preconfiguration: ai.configurationStationValidateTarget,
			condition: ai.conditionInCombat,
			behaviour: ai.behaviourStationLaunchDefenseShips,
			reconsider: 5
		},
		/* Respond to distress calls */
		{
			condition: ai.conditionHasReceivedDistressCall,
			behaviour: ai.behaviourStationRespondToDistressCall,
			reconsider: 20
		},
		/* Scan */
		{
			preconfiguration: ai.configurationCheckScanner,
			condition: ai.conditionScannerContainsSalvage,
			behaviour: ai.behaviourStationLaunchSalvager,
			reconsider: 60 // long delay to avoid launching too many at once
		},
		{
			notcondition: ai.conditionScannerContainsPatrol,
			behaviour: ai.behaviourStationLaunchPatrol,
			reconsider: 60
		},
		{
			configuration: ai.configurationStationReduceAlertLevel,
			behaviour: ai.behaviourStationManageTraffic,
			reconsider: 60
		}
	]);
}