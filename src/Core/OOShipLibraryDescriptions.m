/*

OOShipLibraryDescriptions.m

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOShipLibraryDescriptions.h"
#import "OOStringExpander.h"
#import "Universe.h"

NSString *OOShipLibraryCategorySingular(NSString *category)
{
	return OOExpandKey(OOExpand(@"oolite-ship-library-category-[category]", category));
}


NSString *OOShipLibraryCategoryPlural(NSString *category)
{
	return OOExpandKey(OOExpand(@"oolite-ship-library-category-plural-[category]", category));
}


NSString *OOShipLibrarySpeed (ShipEntity *demo_ship)
{
	GLfloat	param = [demo_ship maxFlightSpeed];
	NSString *result = nil;
	if (param <= 1)
	{
		result = DESC(@"oolite-ship-library-speed-stationary");
	}
	else if (param <= 150)
	{
		result = DESC(@"oolite-ship-library-speed-veryslow");
	}
	else if (param <= 250)
	{
		result = DESC(@"oolite-ship-library-speed-slow");
	}
	else if (param <= 325)
	{
		result = DESC(@"oolite-ship-library-speed-average");
	}
	else if (param <= 425)
	{
		result = DESC(@"oolite-ship-library-speed-fast");
	}
	else
	{
		result = DESC(@"oolite-ship-library-speed-veryfast");
	}
	return result;
}


NSString *OOShipLibraryTurnRate (ShipEntity *demo_ship)
{
	GLfloat param = [demo_ship maxFlightRoll] + (2*[demo_ship maxFlightPitch]);
	NSString *result = nil;
	if (param <= 2)
	{
		result = DESC(@"oolite-ship-library-turn-veryslow");
	}
	else if (param <= 2.75)
	{
		result = DESC(@"oolite-ship-library-turn-slow");
	}
	else if (param <= 4.5)
	{
		result = DESC(@"oolite-ship-library-turn-average");
	}
	else if (param <= 6)
	{
		result = DESC(@"oolite-ship-library-turn-fast");
	}
	else
	{
		result = DESC(@"oolite-ship-library-turn-veryfast");
	}
	return result;
}


NSString *OOShipLibraryCargo (ShipEntity *demo_ship)
{
	OOCargoQuantity param = [demo_ship maxAvailableCargoSpace];
	NSString *result = nil;
	if (param == 0)
	{
		result = DESC(@"oolite-ship-library-cargo-none");
	}
	else 
	{
		result = [NSString stringWithFormat:DESC(@"oolite-ship-library-cargo-carried-u"),param];
	}
	return result;
}


NSString *OOShipLibraryGenerator (ShipEntity *demo_ship)
{
	float rate = [demo_ship energyRechargeRate];
	NSString *result = nil;
	if (rate < 2.5)
	{
		result = DESC(@"oolite-ship-library-generator-weak");
	}
	else if (rate < 3.75)
	{
		result = DESC(@"oolite-ship-library-generator-average");
	}
	else
	{
		result = DESC(@"oolite-ship-library-generator-strong");
	}
	return result;
}


NSString *OOShipLibraryShields (ShipEntity *demo_ship)
{
	// when NPCs have actual shields, add those on as well
	float shields = [demo_ship maxEnergy];
	NSString *result = nil;
	if (shields < 128)
	{
		result = DESC(@"oolite-ship-library-shields-veryweak");
	}
	else if (shields < 192)
	{
		result = DESC(@"oolite-ship-library-shields-weak");
	}
	else if (shields < 256)
	{
		result = DESC(@"oolite-ship-library-shields-average");
	}
	else if (shields < 320)
	{
		result = DESC(@"oolite-ship-library-shields-strong");
	}
	else
	{
		result = DESC(@"oolite-ship-library-shields-verystrong");
	}
	return result;
}


NSString *OOShipLibraryWitchspace (ShipEntity *demo_ship)
{
	if ([demo_ship hasHyperspaceMotor])
	{
		return DESC(@"oolite-ship-library-witchspace-yes");
	}
	else
	{
		return DESC(@"oolite-ship-library-witchspace-no");
	}
}


NSString *OOShipLibraryWeapons (ShipEntity *demo_ship)
{
	OOWeaponFacingSet facings = [demo_ship weaponFacings]; 
	NSUInteger fixed = (facings&1)+(facings&2)/2+(facings&4)/4+(facings&8)/8;
	NSUInteger pylons = [demo_ship missileCapacity];
	if (fixed == 0 && pylons == 0)
	{
		return DESC(@"oolite-ship-library-weapons-none");
	}
	return [NSString stringWithFormat:DESC(@"oolite-ship-library-weapons-u-u"),fixed,pylons];
}


NSString *OOShipLibraryTurrets (ShipEntity *demo_ship)
{
	NSUInteger turretCount = [demo_ship turretCount];
	if (turretCount > 0) 
	{
		return [NSString stringWithFormat:DESC(@"oolite-ship-library-turrets-u"), turretCount];
	}
	else 
	{
		return @"";
	}
}


NSString *OOShipLibrarySize (ShipEntity *demo_ship)
{
	BoundingBox bb = [demo_ship totalBoundingBox];
	return [NSString stringWithFormat:DESC(@"oolite-ship-library-size-u-u-u"),(unsigned)(bb.max.x-bb.min.x),(unsigned)(bb.max.y-bb.min.y),(unsigned)(bb.max.z-bb.min.z)];
}
