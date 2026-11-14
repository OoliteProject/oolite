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

#include "OOShipLibraryDescriptions.h"
#include "OOStringExpander.h"
#include "Universe.h"

#include "oofnd/String.hpp"

namespace {

/*	cxx_OOExpandKey(cxx_OOExpand("<pattern>[category]", category)): the category is handed to the
        expander as the one-entry argument dictionary the macro builds from the variable's name. A key
        that expanded to nothing expands to nothing (""), as a nil key did.
*/
std::string ExpandCategoryKey(const char* pattern, const std::string& category)
{
    const std::optional<std::string> key = cxx_OOExpand(pattern, category);
    return key.has_value() ? cxx_OOExpandKey(*key).value_or(std::string()) : std::string();
}

} // namespace

std::string OOShipLibraryCategorySingular(const std::string& category)
{
    return ExpandCategoryKey("oolite-ship-library-category-[category]", category);
}

std::string OOShipLibraryCategoryPlural(const std::string& category)
{
    return ExpandCategoryKey("oolite-ship-library-category-plural-[category]", category);
}

std::string OOShipLibrarySpeed(ShipEntity* demo_ship)
{
    GLfloat param = (demo_ship ? demo_ship->maxFlightSpeed : 0);
    std::string result;
    if (param <= 1) {
        result = OO_DESC("oolite-ship-library-speed-stationary");
    } else if (param <= 150) {
        result = OO_DESC("oolite-ship-library-speed-veryslow");
    } else if (param <= 250) {
        result = OO_DESC("oolite-ship-library-speed-slow");
    } else if (param <= 325) {
        result = OO_DESC("oolite-ship-library-speed-average");
    } else if (param <= 425) {
        result = OO_DESC("oolite-ship-library-speed-fast");
    } else {
        result = OO_DESC("oolite-ship-library-speed-veryfast");
    }
    return result;
}

std::string OOShipLibraryTurnRate(ShipEntity* demo_ship)
{
    GLfloat param = (demo_ship ? demo_ship->maxFlightRoll() + (2 * demo_ship->maxFlightPitch()) : 0);
    std::string result;
    if (param <= 2) {
        result = OO_DESC("oolite-ship-library-turn-veryslow");
    } else if (param <= 2.75) {
        result = OO_DESC("oolite-ship-library-turn-slow");
    } else if (param <= 4.5) {
        result = OO_DESC("oolite-ship-library-turn-average");
    } else if (param <= 6) {
        result = OO_DESC("oolite-ship-library-turn-fast");
    } else {
        result = OO_DESC("oolite-ship-library-turn-veryfast");
    }
    return result;
}

std::string OOShipLibraryCargo(ShipEntity* demo_ship)
{
    OOCargoQuantity param = (demo_ship ? demo_ship->maxAvailableCargoSpace() : 0);
    std::string result;
    if (param == 0) {
        result = OO_DESC("oolite-ship-library-cargo-none");
    } else {
        result = oo::str::format(OO_DESC("oolite-ship-library-cargo-carried-u").c_str(), param);
    }
    return result;
}

std::string OOShipLibraryGenerator(ShipEntity* demo_ship)
{
    float rate = (demo_ship ? demo_ship->energyRechargeRate() : 0);
    std::string result;
    if (rate < 2.5) {
        result = OO_DESC("oolite-ship-library-generator-weak");
    } else if (rate < 3.75) {
        result = OO_DESC("oolite-ship-library-generator-average");
    } else {
        result = OO_DESC("oolite-ship-library-generator-strong");
    }
    return result;
}

std::string OOShipLibraryShields(ShipEntity* demo_ship)
{
    // when NPCs have actual shields, add those on as well
    float shields = (demo_ship ? demo_ship->maxEnergy : 0);
    std::string result;
    if (shields < 128) {
        result = OO_DESC("oolite-ship-library-shields-veryweak");
    } else if (shields < 192) {
        result = OO_DESC("oolite-ship-library-shields-weak");
    } else if (shields < 256) {
        result = OO_DESC("oolite-ship-library-shields-average");
    } else if (shields < 320) {
        result = OO_DESC("oolite-ship-library-shields-strong");
    } else {
        result = OO_DESC("oolite-ship-library-shields-verystrong");
    }
    return result;
}

std::string OOShipLibraryWitchspace(ShipEntity* demo_ship)
{
    if ((demo_ship && demo_ship->hasHyperspaceMotor())) {
        return OO_DESC("oolite-ship-library-witchspace-yes");
    } else {
        return OO_DESC("oolite-ship-library-witchspace-no");
    }
}

std::string OOShipLibraryWeapons(ShipEntity* demo_ship)
{
    OOWeaponFacingSet facings = demo_ship ? demo_ship->weaponFacings() : OOWeaponFacingSet(0);
    NSUInteger fixed = (facings & 1) + (facings & 2) / 2 + (facings & 4) / 4 + (facings & 8) / 8;
    NSUInteger pylons = (demo_ship ? demo_ship->missileCapacity() : 0);
    if (fixed == 0 && pylons == 0) {
        return OO_DESC("oolite-ship-library-weapons-none");
    }
    return oo::str::format(OO_DESC("oolite-ship-library-weapons-u-u").c_str(), fixed, pylons);
}

std::string OOShipLibraryTurrets(ShipEntity* demo_ship)
{
    NSUInteger turretCount = (demo_ship ? demo_ship->turretCount() : 0);
    if (turretCount > 0) {
        return oo::str::format(OO_DESC("oolite-ship-library-turrets-u").c_str(), turretCount);
    } else {
        return "";
    }
}

std::string OOShipLibrarySize(ShipEntity* demo_ship)
{
    BoundingBox bb = { };
    if (demo_ship)
        bb = demo_ship->totalBoundingBox;
    return oo::str::format(OO_DESC("oolite-ship-library-size-u-u-u").c_str(), (unsigned)(bb.max.x - bb.min.x), (unsigned)(bb.max.y - bb.min.y), (unsigned)(bb.max.z - bb.min.z));
}
