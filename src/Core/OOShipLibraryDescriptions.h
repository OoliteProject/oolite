/*

OOShipLibraryDescriptions.h

Default descriptions for ships

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

#import "ShipEntity.h"

static NSString * const kOODemoShipKey			= @"ship";
static NSString * const kOODemoShipName			= @"name"; // set internally only
static NSString * const kOODemoShipClass		= @"class";
static NSString * const kOODemoShipSummary		= @"summary";
static NSString * const kOODemoShipDescription	= @"description";
static NSString * const kOODemoShipShipData		= @"ship_data";
static NSString * const kOODemoShipSpeed		= @"speed";
static NSString * const kOODemoShipTurnRate		= @"turn_rate";
static NSString * const kOODemoShipCargo		= @"cargo";
static NSString * const kOODemoShipGenerator	= @"generator";
static NSString * const kOODemoShipShields		= @"shields";
static NSString * const kOODemoShipWitchspace	= @"witchspace";
static NSString * const kOODemoShipWeapons		= @"weapons";
static NSString * const kOODemoShipSize			= @"size";
static NSString * const kOODemoShipConditions	= @"condition_script";

NSString *OOShipLibraryCategorySingular(NSString *category);
NSString *OOShipLibraryCategoryPlural(NSString *category);

NSString *OOShipLibrarySpeed (ShipEntity *demo_ship);
NSString *OOShipLibraryTurnRate (ShipEntity *demo_ship);
NSString *OOShipLibraryCargo (ShipEntity *demo_ship);
NSString *OOShipLibraryGenerator (ShipEntity *demo_ship);
NSString *OOShipLibraryShields (ShipEntity *demo_ship);
NSString *OOShipLibraryWitchspace (ShipEntity *demo_ship);
NSString *OOShipLibraryWeapons (ShipEntity *demo_ship);
NSString *OOShipLibrarySize (ShipEntity *demo_ship);
