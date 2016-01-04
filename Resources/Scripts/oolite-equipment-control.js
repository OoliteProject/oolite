/*

oolite-equipment-control.js

World script handling equipment effects


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
/*global worldScripts*/

"use strict";

this.name = "Oolite Equipment Control";
this.description = "This script moves control over certain Oolite equipment items into Javascript to make it more practical for OXPs to vary the effects.";
this.author			= "cim";
this.copyright		= "© 2014-2015 the Oolite team.";


this.$baseline = {};
this.$started = false;

/* Initialise baseline data and equipment */
this.startUp = function()
{
	if (this.startUp)
	{
		delete this.startUp;
	}

	// initialise equipment
	this.playerBoughtNewShip();

	/* Maximum cargo space is already in the save game, so don't
	 * enable these functions until after startup, or it'll get
	 * repeatedly applied.
	 *
	 * Note: the cargo bay can't be damaged in the core game
	 * anyway. The removal function is moderately complex just in case
	 * an OXP offers a way to remove the cargo bay without first doing
	 * validation that this can be done.
	 *
	 * Also may provide a model for conditional removals elsewhere
	 * (though validation before calling removeEquipment is again the
	 * correct approach). Checks here should only be necessary as a
	 * failsafe.
	 */
	this.$equipmentEnable["EQ_CARGO_BAY"] = function(item)
	{
		player.ship.cargoSpaceCapacity += player.ship.extraCargo;
	};

	this.$equipmentDisable["EQ_CARGO_BAY"] = function(item)
	{
		if (player.ship.cargoSpaceAvailable < player.ship.extraCargo)
		{
			/* can't disable this equipment could try throwing out
			 * cargo, but this isn't guaranteed to work because there
			 * might be equipment taking up more than the base space. */
			// so save the current capacity
			var cap = player.ship.cargoSpaceCapacity;
			// add the cargo extension back
			log(this.name,"The large cargo bay was removed when there wasn't enough spare space to contain it. This is probably due to an OXP failing to validate cargo bay removal before trying it. The cargo bay has been restored to prevent inconsistencies.");
			// then reset the cargo space to the right amount
			player.ship.cargoSpaceCapacity = cap;
			// and stop
			return -1; // doesn't disable this function
		}
		player.ship.cargoSpaceCapacity -= player.ship.extraCargo;
	};

};


this.playerBoughtNewShip = function()
{
	this.$started = true;
	this.$baseline.maxEnergy = player.ship.maxEnergy;
	this.$baseline.energyRechargeRate = player.ship.energyRechargeRate;
	this.$baseline.maxForwardShield = player.ship.maxForwardShield;
	this.$baseline.maxAftShield = player.ship.maxAftShield;
	this.$baseline.forwardShieldRechargeRate = player.ship.forwardShieldRechargeRate;
	this.$baseline.aftShieldRechargeRate = player.ship.aftShieldRechargeRate;
	this.$baseline.heatInsulation = player.ship.heatInsulation;

	var eq = player.ship.equipment;
	this.$equipmentEnabled = {};
	for (var i=0; i<eq.length; i++) {
		// reinitialise equipment already on ship
		this.equipmentAdded(eq[i].equipmentKey);
	}
};


/* Remove equipment effects */
this.equipmentRemoved = function(equip)
{
	if (!this.$started)
	{
		return;
	}
	if (this.$equipmentEnabled[equip])
	{
		if (this.$equipmentDisable[equip])
		{
			var info = EquipmentInfo.infoForKey(equip);
//			log(this.name,"Disabling "+info.equipmentKey); //tmp - remove later
			var result = this.$equipmentDisable[equip].bind(this,info)();
			if (result == -1)
			{
				return;
			}
		}
	}
	this.$equipmentEnabled[equip] = 0;
};


/* Add equipment effects */
this.equipmentAdded = function(equip)
{
	if (!this.$started)
	{
		return;
	}
	if (!this.$equipmentEnabled[equip])
	{
		if (this.$equipmentEnable[equip])
		{
			var info = EquipmentInfo.infoForKey(equip);
//			log(this.name,"Enabling "+info.equipmentKey); //tmp - remove later
			var result = this.$equipmentEnable[equip].bind(this,info)();
			if (result == -1)
			{
				return;
			}
		}
	}
	this.$equipmentEnabled[equip] = 1;
};


/* This object prevents duplicate enabling/disabling of items. Do not
 * edit directly. */
this.$equipmentEnabled = {};


/* These objects get filled with control methods. Each control method
 * may be individually overridden by an OXP if necessary, and
 * additional methods for OXP equipment may be added. */
this.$equipmentEnable = {};
this.$equipmentDisable = {};



/* Methods for handling shield boosters / military shield boosters */
this.$equipmentEnable["EQ_SHIELD_BOOSTER"] = this.$equipmentEnable["EQ_NAVAL_SHIELD_BOOSTER"] = function(info)
{
	player.ship.maxForwardShield += parseFloat(info.scriptInfo.oolite_shield_increase);
	player.ship.maxAftShield += parseFloat(info.scriptInfo.oolite_shield_increase);
	player.ship.forwardShieldRechargeRate *= parseFloat(info.scriptInfo.oolite_shield_recharge_multiplier);
	player.ship.aftShieldRechargeRate *= parseFloat(info.scriptInfo.oolite_shield_recharge_multiplier);
	if (player.ship.docked)
	{
		player.ship.aftShield = player.ship.maxAftShield;
		player.ship.forwardShield = player.ship.maxForwardShield;
	}
};


this.$equipmentDisable["EQ_SHIELD_BOOSTER"] = this.$equipmentDisable["EQ_NAVAL_SHIELD_BOOSTER"] = function(info)
{
	player.ship.maxForwardShield -= parseFloat(info.scriptInfo.oolite_shield_increase);
	if (player.ship.forwardShield > player.ship.maxForwardShield)  player.ship.forwardShield = player.ship.maxForwardShield;
	player.ship.maxAftShield -= parseFloat(info.scriptInfo.oolite_shield_increase);
	if (player.ship.aftShield > player.ship.maxAftShield)  player.ship.aftShield = player.ship.maxAftShield;
	player.ship.forwardShieldRechargeRate /= parseFloat(info.scriptInfo.oolite_shield_recharge_multiplier);
	player.ship.aftShieldRechargeRate /= parseFloat(info.scriptInfo.oolite_shield_recharge_multiplier);
	if (player.ship.docked)
	{
		player.ship.aftShield = player.ship.maxAftShield;
		player.ship.forwardShield = player.ship.maxForwardShield;
	}
};


/* Methods for handling (naval) energy units */
this.$equipmentEnable["EQ_ENERGY_UNIT"] = this.$equipmentEnable["EQ_NAVAL_ENERGY_UNIT"] = function(info)
{
	var eboost = (parseFloat(info.scriptInfo.oolite_energy_recharge_multiplier)-1.0)*this.$baseline.energyRechargeRate;
	player.ship.energyRechargeRate += eboost;
};


this.$equipmentDisable["EQ_ENERGY_UNIT"] = this.$equipmentDisable["EQ_NAVAL_ENERGY_UNIT"] = function(info)
{
	var eboost = (parseFloat(info.scriptInfo.oolite_energy_recharge_multiplier)-1.0)*this.$baseline.energyRechargeRate;
	player.ship.energyRechargeRate -= eboost;
};


/* Methods for handling heat shielding */
this.$equipmentEnable["EQ_HEAT_SHIELD"] = function(info)
{
	player.ship.heatInsulation += parseFloat(info.scriptInfo.oolite_heat_insulation_strength);
};


this.$equipmentDisable["EQ_HEAT_SHIELD"] = function(info)
{
	player.ship.heatInsulation -= parseFloat(info.scriptInfo.oolite_heat_insulation_strength);
};