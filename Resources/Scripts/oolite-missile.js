/*

oolite-missile.js

Ship script for Missiles and Hardheads.


Oolite
Copyright © 2004-2012 Giles C Williams and contributors

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


/*jslint white: true, undef: true, eqeqeq: true, bitwise: true, regexp: true, newcap: true, immed: true */
/*global missionVariables, player*/


"use strict";


this.name			= "oolite-missile";
this.author			= "cim";
this.copyright		= "© 2008-2012 the Oolite team.";
this.version		= "1.77";

this.detonate = function()
{
/* So, the ideal is to deal 260 damage at 25m, but that assumes no
 * relative velocity, and we want to keep that bit of the old behaviour.
 * For a stationary target, the missile will be going at 750
 * For a Cobra III (nominal top speed 350) we probably want +/- 100
 * damage. The typical behaviour is going to be fleeing, which in the
 * framerate-based calculations would put the missile only just inside
 * the boundary, so let's put that as the baseline, and say 400 as
 * closing speed. That gets the original 260 damage.
 * Actually, as the missile spirals, we get less than 400 closing speed
 * in a real fleeing situation, which is fine.
 * Head-on collision doing 460 damage would be 1100 closing
 * speed. Still survivable in an upgraded ship, but really hurts.
 * So, velocityBias is therefore 2/7
 * We then need to cut the non-velocity damage down to compensate, by 800/7
 * So actually 145.7
 * Fleeing also tends to stretch the distance out a bit at low frame
 * rates, so adjust the full-damage radius outwards a little so we
 * don't compensate for the same effect twice. Won't make a difference
 * at high frame-rates unless you get caught by a missile intended for
 * someone else.
 * As a result the maximum radius is 400m, which is bigger than the
 * the original 250m (but the damage past 100m is going to be
 * negligible anyway)
 */
		this.ship.dealEnergyDamage(145.71, 32.5, 0.286); 
		this.ship.explode();
}
