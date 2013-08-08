/*

qbombAI.js

Priority-based AI for quirium cascade mines

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

this.name = "Oolite Q-bomb AI";
this.version = "1.79";

this.shipWasDumped = function() {
		// don't need a priority AI for this one
		this.ship.broadcastCascadeImminent();
		this.explosion = new Timer(this,function() {
				this.ship.becomeCascadeExplosion();
		},5);
}

this.shipDied = function() {
		this.explosion.stop();
}