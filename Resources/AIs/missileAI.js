/*

missileAI.js

Priority-based AI for missiles

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

this.name = "Oolite Missile AI";
this.version = "1.79";

this.aiStarted = function() {
		var ai = new worldScripts["oolite-libPriorityAI"].PriorityAIController(this.ship);

		ai.setPriorities([
				{
						condition: ai.conditionMissileOutOfFuel,
						behaviour: ai.behaviourMissileSelfDestruct
				},
				{
						condition: ai.conditionHasTarget,
						behaviour: ai.behaviourMissileInterceptTarget,
						reconsider: 5
				},
				/* If target cloaks, go to last known location */
				{
						condition: ai.conditionHasInterceptCoordinates,
						behaviour: ai.behaviourMissileInterceptCoordinates,
						reconsider: 1
				},
				/* Target lost. Self-destruct */
				{
						behaviour: ai.behaviourMissileSelfDestruct
				}
		]);
}

/* ECM response function */
this._ecmProofMissileResponse = function()
{
		if (Math.random() < 0.1) //10% chance per pulse
		{
				if (Math.random() < 0.5)
				{
						// 50% chance responds by detonation
						this.ship.AIScript.shipAchievedDesiredRange();
						return;
				}
				// otherwise explode as normal below
		}
		else // 90% chance unaffected
		{
				return;
		}	
		this.ship.explode();
}