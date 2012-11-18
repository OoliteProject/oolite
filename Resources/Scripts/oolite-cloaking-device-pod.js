/*
 
 oolite-cloaking-device-pod.js
 
 Ship script for cloaking device cargo pod.
 
 
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
/*global player*/


"use strict";


this.name			= "oolite-cloaking-device-pod";
this.author			= "Jens Ayton";
this.copyright		= "© 2007-2012 the Oolite team.";
this.version		= "1.77";


this.shipWasScooped = function (scooper)
{
	if (scooper.equipmentStatus("EQ_CLOAKING_DEVICE") !== "EQUIPMENT_OK")
	{
		scooper.awardEquipment("EQ_CLOAKING_DEVICE");
	}
	else if (scooper.isPlayer)
	{
		// Should probably award 100 gold to non-player ships too, but they don’t have a manifest at the moment.
		player.ship.manifest.gold += 100;
	}
	
	// now handled by condition script	
	/*	if (scooper.isPlayer)
	{
		// effectiveTechLevel 15 makes it repairable at a level 15 system.
		// Level 15 systems only exist in G1 (1x), G2 (1x), G5 (1x), G6 (1x) and G7 (2x)
		EquipmentInfo.infoForKey("EQ_CLOAKING_DEVICE").effectiveTechLevel = 15;
	} */
};
