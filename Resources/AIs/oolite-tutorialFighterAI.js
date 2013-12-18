/*

oolite-tutorialFighterAI.js

AI for the tutorial simulated combat

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

this.name = "Oolite Tutorial Fighter AI";
this.version = "1.79";

this.aiStarted = function() {
	var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

	ai.setCommunicationsRole("_tutorial");

	ai.setPriorities([
		/* Fight */
		{
			condition: ai.conditionInCombat,
			configuration: ai.configurationAcquireCombatTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 30 // makes missiles more distracting
		},
		/* Stop following me! */
		{
			condition: ai.conditionPlayerNearby,
			configuration: ai.configurationAcquirePlayerAsTarget,
			behaviour: ai.behaviourDestroyCurrentTarget,
			reconsider: 5
		},
		/* Chase Player */
		{
			configuration: function() {
				this.ship.destination = player.ship.position;
				this.ship.desiredSpeed = 300;
			},
			behaviour: ai.behaviourApproachDestination,
			reconsider: 5
		}
	],3+Math.random()+Math.random());

	
}