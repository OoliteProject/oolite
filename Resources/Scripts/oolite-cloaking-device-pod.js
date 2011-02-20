/*

oolite-cloaking-device-pod.js

Ship script for cloaking device cargo pod.


Oolite
Copyright © 2004-2011 Giles C Williams and contributors

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
this.copyright		= "© 2007-2011 the Oolite team.";
this.version		= "1.75.1";


this.shipWasScooped = function (scooper)
{
	if (scooper.isPlayer)
	{
		if (player.ship.equipmentStatus("EQ_CLOAKING_DEVICE") !== "EQUIPMENT_OK")
		{
			player.ship.awardEquipment("EQ_CLOAKING_DEVICE");
			// Should we make it possible to repair?
			// EquipmentInfo.infoForKey("EQ_CLOAKING_DEVICE").effectiveTechLevel = 14;
		}
		else
		{
			player.ship.awardCargo("Gold", 100);
		}
	}
	// Should probably award 100 gold to non-player ships too, but they don’t have awardCargo at the moment.
};
