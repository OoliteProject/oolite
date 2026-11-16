/*

OOJSSystem+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-9ht.139): the sends of the System binding's converted
natives to classes that are still Objective-C, one per function. See OOJSSystem+ObjCBridge.h.

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

#import "EntityOOJavaScriptExtensions.h"
#import "OOJSPopulatorDefinition.h"
#import "OOJSSystem+ObjCBridge.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "ShipEntity.h"

// --- The player (SystemGetProperty(), SystemSetProperty(), SystemToString(), SystemAddPlanet(),
// SystemAddMoon(), SystemSendAllShipsAway())

OOGalaxyID OOJSSystemPlayerCurrentGalaxyID(PlayerEntity* player) { return [player currentGalaxyID]; }
OOSystemID OOJSSystemPlayerCurrentSystemID(PlayerEntity* player) { return [player currentSystemID]; }
double OOJSSystemPlayerSystemPseudoRandomFloat(PlayerEntity* player) { return [player systemPseudoRandomFloat]; }
unsigned OOJSSystemPlayerSystemPseudoRandom100(PlayerEntity* player) { return [player systemPseudoRandom100]; }
unsigned OOJSSystemPlayerSystemPseudoRandom256(PlayerEntity* player) { return [player systemPseudoRandom256]; }
OOPlanetEntity* OOJSSystemPlayerAddPlanet(PlayerEntity* player, const std::string& planetKey) { return [player cxx_addPlanet:planetKey]; }
OOPlanetEntity* OOJSSystemPlayerAddMoon(PlayerEntity* player, const std::string& moonKey) { return [player cxx_addMoon:moonKey]; }
void OOJSSystemPlayerSendAllShipsAway(PlayerEntity* player) { [player sendAllShipsAway]; }

// --- The entities (SystemGetProperty())

bool OOJSSystemEntityIsVisibleToScripts(Entity* entity) { return [entity isVisibleToScripts]; }

// --- The universe (SystemGetProperty(), SystemSetProperty(), SystemToString(), the counts,
// SystemLocationFromCode(), FindJSVisibleEntities())

bool OOJSSystemUniverseInInterstellarSpace() { return [UNIVERSE inInterstellarSpace]; }
StationEntity* OOJSSystemUniverseStation() { return [UNIVERSE station]; }
OOPlanetEntity* OOJSSystemUniversePlanet() { return [UNIVERSE planet]; }
OOSunEntity* OOJSSystemUniverseSun() { return [UNIVERSE sun]; }
std::vector<oo::ObjCRef<OOPlanetEntity*>> OOJSSystemUniversePlanets() { return [UNIVERSE cxx_planets]; }
std::vector<oo::ObjCRef<StationEntity*>> OOJSSystemUniverseStations() { return [UNIVERSE cxx_stations]; }
std::map<std::string, oo::ObjCRef<OOWaypointEntity*>, std::less<>> OOJSSystemUniverseCurrentWaypoints() { return [UNIVERSE cxx_currentWaypoints]; }
std::vector<oo::ObjCRef<WormholeEntity*>> OOJSSystemUniverseWormholes() { return [UNIVERSE cxx_wormholes]; }

std::vector<oo::ObjCRef<Entity*>> OOJSSystemUniverseFindShipsMatchingPredicate(EntityFilterPredicate predicate, void* parameter, double range, Entity* entity)
{
    return [UNIVERSE cxx_findShipsMatchingPredicate:predicate parameter:parameter inRange:range ofEntity:entity];
}

std::vector<oo::ObjCRef<Entity*>> OOJSSystemUniverseFindVisualEffectsMatchingPredicate(EntityFilterPredicate predicate, void* parameter, double range, Entity* entity)
{
    return [UNIVERSE cxx_findVisualEffectsMatchingPredicate:predicate parameter:parameter inRange:range ofEntity:entity];
}

std::vector<oo::ObjCRef<Entity*>> OOJSSystemUniverseFindEntitiesMatchingPredicate(EntityFilterPredicate predicate, void* parameter, double range, Entity* entity)
{
    return [UNIVERSE cxx_findEntitiesMatchingPredicate:predicate parameter:parameter inRange:range ofEntity:entity];
}

float OOJSSystemUniverseAmbientLightLevel() { return [UNIVERSE ambientLightLevel]; }
void OOJSSystemUniverseSetAmbientLightLevel(float newValue) { [UNIVERSE setAmbientLightLevel:newValue]; }
void OOJSSystemUniverseSetLighting() { [UNIVERSE setLighting]; }
bool OOJSSystemUniverseWitchspaceBreakPattern() { return [UNIVERSE witchspaceBreakPattern]; }
void OOJSSystemUniverseSetWitchspaceBreakPattern(bool newValue) { [UNIVERSE setWitchspaceBreakPattern:newValue]; }
oo::PList OOJSSystemUniverseGetPopulatorSettings() { return [UNIVERSE cxx_getPopulatorSettings]; }
oo::PList OOJSSystemUniverseCurrentSystemData() { return [UNIVERSE cxx_currentSystemData]; }

void OOJSSystemUniverseSetSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string& key, const oo::PList& value, const std::optional<std::string>& manifest, OOSystemLayer layer)
{
    [UNIVERSE cxx_setSystemDataForGalaxy:gnum planet:pnum key:key value:value fromManifest:manifest forLayer:layer];
}

unsigned OOJSSystemUniverseCountShipsWithPrimaryRole(const std::string& role, double range, Entity* entity) { return [UNIVERSE cxx_countShipsWithPrimaryRole:role inRange:range ofEntity:entity]; }
unsigned OOJSSystemUniverseCountShipsWithRole(const std::string& role, double range, Entity* entity) { return [UNIVERSE cxx_countShipsWithRole:role inRange:range ofEntity:entity]; }
unsigned OOJSSystemUniverseCountShipsWithScanClass(OOScanClass scanClass, double range, Entity* entity) { return [UNIVERSE countShipsWithScanClass:scanClass inRange:range ofEntity:entity]; }
HPVector OOJSSystemUniverseLocationByCode(const std::string& code, OOSunEntity* sun, OOPlanetEntity* planet) { return [UNIVERSE cxx_locationByCode:code withSun:sun andPlanet:planet]; }

// --- The ship creators, legacy spawners, static lookups, effects, populators and waypoints
// (SystemLegacy*(), SystemStatic*(), SystemAddVisualEffect(), SystemSetPopulator(),
// SystemSetWaypoint(), SystemAddShipsOrGroup(), SystemAddShipsOrGroupToRoute())

void OOJSSystemUniverseWitchspaceShipWithPrimaryRole(const std::string& role) { [UNIVERSE cxx_witchspaceShipWithPrimaryRole:role]; }
void OOJSSystemUniverseAddShipWithRoleNearRouteOneAt(const std::string& desc, double routeFraction) { [UNIVERSE cxx_addShipWithRole:desc nearRouteOneAt:routeFraction]; }
bool OOJSSystemUniverseSpawnShip(const std::string& shipdesc) { return [UNIVERSE cxx_spawnShip:shipdesc]; }
std::optional<std::string> OOJSSystemUniverseGetSystemName(OOSystemID sys) { return [UNIVERSE cxx_getSystemName:sys]; }
OOSystemID OOJSSystemUniverseFindSystemFromName(const std::string& sysName) { return [UNIVERSE cxx_findSystemFromName:sysName]; }
OOVisualEffectEntity* OOJSSystemUniverseAddVisualEffectAt(HPVector pos, const std::string& key) { return [UNIVERSE cxx_addVisualEffectAt:pos withKey:key]; }
void OOJSSystemUniverseSetPopulatorSetting(const std::string& key, const oo::PList& setting) { [UNIVERSE cxx_setPopulatorSetting:key to:setting]; }
void OOJSSystemUniverseDefineWaypoint(const oo::PList& definition, const std::string& key) { [UNIVERSE cxx_defineWaypoint:definition forKey:key]; }
HPVector OOJSSystemUniverseGetWitchspaceExitPosition() { return [UNIVERSE getWitchspaceExitPosition]; }

std::vector<oo::ObjCRef<ShipEntity*>> OOJSSystemUniverseAddShipsAt(HPVector pos, const std::string& role, unsigned count, GLfloat radius, bool isGroup)
{
    return [UNIVERSE cxx_addShipsAt:pos withRole:role quantity:count withinRadius:radius asGroup:isGroup];
}

std::vector<oo::ObjCRef<ShipEntity*>> OOJSSystemUniverseAddShipsToRoute(const std::string& route, const std::string& role, unsigned count, double routeFraction, bool isGroup)
{
    return [UNIVERSE cxx_addShipsToRoute:route withRole:role quantity:count routeFraction:routeFraction asGroup:isGroup];
}

void OOJSSystemPlayerAddShipsAt(PlayerEntity* player, const std::string& rolesNumberSystemXYZ) { [player addShipsAt:rolesNumberSystemXYZ]; }
void OOJSSystemPlayerAddShipsAtPrecisely(PlayerEntity* player, const std::string& rolesNumberSystemXYZ) { [player addShipsAtPrecisely:rolesNumberSystemXYZ]; }
void OOJSSystemPlayerAddShipsWithinRadius(PlayerEntity* player, const std::string& rolesNumberSystemXYZR) { [player addShipsWithinRadius:rolesNumberSystemXYZR]; }
OOShipGroup* OOJSSystemShipGroup(ShipEntity* ship) { return [ship group]; }
OOJSPopulatorDefinition* OOJSSystemNewPopulatorDefinition() { return [[OOJSPopulatorDefinition alloc] init]; }
