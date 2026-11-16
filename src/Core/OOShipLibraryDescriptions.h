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

#pragma once

#include "ShipEntity.h"

#include "oofnd/StdLib.hpp"

// shiplibrary.plist keys, UTF-8 (Foundation sweep, proposed ADR-0043): a caller that needs an
// Objective-C key passes oo::NSStringFrom(kOODemoShip...).

static constexpr const char* kOODemoShipKey = "ship";
static constexpr const char* kOODemoShipName = "name"; // set internally only
static constexpr const char* kOODemoShipClass = "class";
static constexpr const char* kOODemoShipSummary = "summary";
static constexpr const char* kOODemoShipDescription = "description";
static constexpr const char* kOODemoShipShipData = "ship_data";
static constexpr const char* kOODemoShipSpeed = "speed";
static constexpr const char* kOODemoShipTurnRate = "turn_rate";
static constexpr const char* kOODemoShipCargo = "cargo";
static constexpr const char* kOODemoShipGenerator = "generator";
static constexpr const char* kOODemoShipShields = "shields";
static constexpr const char* kOODemoShipWitchspace = "witchspace";
static constexpr const char* kOODemoShipWeapons = "weapons";
static constexpr const char* kOODemoShipTurrets = "turrets";
static constexpr const char* kOODemoShipSize = "size";
static constexpr const char* kOODemoShipConditions = "condition_script";

std::string OOShipLibraryCategorySingular(const std::string& category);
std::string OOShipLibraryCategoryPlural(const std::string& category);

std::string OOShipLibrarySpeed(ShipEntity* demo_ship);
std::string OOShipLibraryTurnRate(ShipEntity* demo_ship);
std::string OOShipLibraryCargo(ShipEntity* demo_ship);
std::string OOShipLibraryGenerator(ShipEntity* demo_ship);
std::string OOShipLibraryShields(ShipEntity* demo_ship);
std::string OOShipLibraryWitchspace(ShipEntity* demo_ship);
std::string OOShipLibraryWeapons(ShipEntity* demo_ship);
std::string OOShipLibraryTurrets(ShipEntity* demo_ship);
std::string OOShipLibrarySize(ShipEntity* demo_ship);
