/*

oolite-populator.js

Built-in system populator settings


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


/*jslint white: true, undef: true, eqeqeq: true, bitwise: true, regexp: true, newcap: true, immed: true */
/*global missionVariables, player*/


"use strict";


this.name			= "oolite-populator";
this.author			= "cim";
this.copyright		= "© 2008-2013 the Oolite team.";
this.version		= "1.79";

/* TO-DO:
 * Buoys need to be given spin (0.15 pitch, 0.1 roll)

 */
this.systemWillPopulate = function() {
		log(this.name,"System populator");

		/* Priority range 0-100 used by Oolite default populator */

		/* Add navigation buoys */
		// for the compass to work properly, the buoys need to be added first,
		// in this order.
		system.setPopulator("oolite-nav-buoy",
												{
														priority: 1,
														location: "COORDINATES",
														coordinates: system.mainStation.position.add(system.mainStation.vectorForward.multiply(10E3)),
														callback: function(pos) {
																var nb = system.addShips("buoy",1,pos,0)[0];
																nb.scanClass = "CLASS_BUOY";
														},
														deterministic: true
												});

		system.setPopulator("oolite-witch-buoy",
												{
														priority: 2,
														location: "COORDINATES",
														coordinates: [0,0,0],
														callback: function(pos) {
																var wb = system.addShips("buoy-witchpoint",1,pos,0)[0];
																wb.scanClass = "CLASS_BUOY";
														},
														deterministic: true
												});
		
		


}

this.interstellarSpaceWillPopulate = function() {
		log(this.name,"Interstellar populator");
		system.setPopulator("oolite-interstellar-thargoids",
												{
														priority: 10,
														location: "WITCHPOINT",
														groupCount: 2+Math.floor(Math.random()*4),
														callback: function(pos) {
																system.addShips("thargoid",1,pos,0);
														}
												});
}