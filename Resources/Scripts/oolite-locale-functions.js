/*

oolite-locale-functions.js

This script implements certain functionality that may need to be modified when
localizing Oolite, such as number formatting. It’s intended to be overridden
by localization OXPs, and is loaded after oolite-global-prefix.js but before
any “normal” world scripts.


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


this.name			= "oolite-locale-functions";
this.author			= "Jens Ayton";
this.copyright		= "© 2012-2013 the Oolite team.";
this.version		= "1.77";


(function () {

// Simple parameters. For more complex behaviour change, modify the functions that do the work.
const minSepDigits		= +expandDescription("[number-group-threshold]");
const groupSize			= +expandDescription("[number-group-size]");
const maxTotalDigits	= 16;	// This is near the limit of numerical precision.
const maxIntegerValue	= Math.pow(10, maxTotalDigits);
const radix				= expandDescription("[number-decimal-separator]");
const groupSep			= expandDescription("[number-group-separator]");
const currencyFormat	= expandDescription("[@-credits]");


// Utility to define non-enumerable, non-configurable, permanent methods, to match the behaviour of native methods.
// FIXME: not used because global properties are not reset when resetting game.
function defineMethod(object, name, implementation)
{
	Object.defineProperty(object, name, { value: implementation, writable: false, configurable: false, enumerable: false });
}


// Internal method returns a pair [result, isScientificNotation] for the benefit of format[Deci]Credits.
function formatPositiveIntegerInternal (value)
{
	if (value > maxIntegerValue)  return [formatScientificInternal(value), true];
	var digits = value.toString();
	var digitCount = digits.length;
	if (digitCount >= minSepDigits)
	{
		if (digitCount > maxTotalDigits)  return [formatScientificInternal(value), true];
		
		var result = "";
		var empty = true;
		
		while (digitCount > groupSize)
		{
			digitCount -= groupSize;
			
			var group = digits.substr(digitCount, groupSize);
			if (empty)
			{
				result = group;
				empty = false;
			}
			else
			{
				result = group.concat(groupSep, result);
			}
		}
		
		if (digitCount > 0)
		{
			result = digits.substr(0, digitCount).concat(groupSep, result);
		}
	}
	else
	{
		var result = digits;
	}
	
	return [result, false];
}


function formatScientificInternal(value)
{
	return value.toString();
}


global.formatInteger = function formatInteger(value)
{
	var value = Math.round(+value);
	var negative = false;
	if (value < 0)
	{
		negative = true;
		value = -value;
	}
	
	var string = formatPositiveIntegerInternal(value)[0];
	
	if (negative)  string = "-" + string;
	return string;
}


global.formatCredits = function formatCredits(value, includeDeciCredits, includeCurrencySymbol)
{
	var negative = false;
	if (value < 0)
	{
		negative = true;
		value = -value;
	}
	
	value += (includeDeciCredits ? 0.05 : 0.5);
	
	var floor = Math.floor(value);
	var [string, isSciNotation] = formatPositiveIntegerInternal(floor);
	if (includeDeciCredits && !isSciNotation)
	{
		var frac = Math.floor(((value - floor) * 10));
		string = string.concat(radix, frac.toString());
	}
	
	if (includeCurrencySymbol)
	{
		string = currencyFormat.replace("%@", string);
	}
	
	if (negative)  string = "-" + string;
	return string;
}

})();
