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
this.startUp = this.playerBoughtNewShip = function()
{
	this.$started = true;
	this.$baseline.maxEnergy = player.ship.maxEnergy;
	this.$baseline.energyRechargeRate = player.ship.energyRechargeRate;
	this.$baseline.maxForwardShield = player.ship.maxForwardShield;
	this.$baseline.maxAftShield = player.ship.maxAftShield;
	this.$baseline.forwardShieldRechargeRate = player.ship.forwardShieldRechargeRate;
	this.$baseline.aftShieldRechargeRate = player.ship.aftShieldRechargeRate;

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
			log(this.name,"Disabling "+info.equipmentKey); //tmp - remove later
			this.$equipmentDisable[equip].bind(this,info)();
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
			log(this.name,"Enabling "+info.equipmentKey); //tmp - remove later
			this.$equipmentEnable[equip].bind(this,info)();
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
	player.ship.maxAftShield -= parseFloat(info.scriptInfo.oolite_shield_increase);
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
	log(this.name,this.name);
	var eboost = (parseFloat(info.scriptInfo.oolite_energy_recharge_multiplier)-1.0)*this.$baseline.energyRechargeRate;
	player.ship.energyRechargeRate += eboost;
};


this.$equipmentDisable["EQ_ENERGY_UNIT"] = this.$equipmentDisable["EQ_NAVAL_ENERGY_UNIT"] = function(info)
{
	var eboost = (parseFloat(info.scriptInfo.oolite_energy_recharge_multiplier)-1.0)*this.$baseline.energyRechargeRate;
	player.ship.energyRechargeRate -= eboost;
};