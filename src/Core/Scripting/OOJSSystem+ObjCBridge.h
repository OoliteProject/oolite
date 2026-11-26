/*

OOJSSystem+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendment oo-9ht.139; beads oo-luhd and oo-yqoa, the slices of
docs/phases/3-slices/OOJSSystem.md): the sends of the System binding's converted natives to classes
that are still Objective-C (the universe and the player), one function per send, named after the
file and the selector, the body the send verbatim. OOJSSystem.mm has no class of its own, so there
is no facade here. Imported by OOJSSystem.mm only.

Never add to this file except a send of that kind. Each function goes with its class's conversion
(Universe, PlayerEntity, and the entity classes it sends a category selector to); the file is
deleted by its deletion bead once none is left.

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

#ifndef OOJSSYSTEM_OBJCBRIDGE_H
#define OOJSSYSTEM_OBJCBRIDGE_H

#import "PlayerEntityScriptMethods.h"
#import "Universe.h"

@class OOJSPopulatorDefinition, OOShipGroup, OOVisualEffectEntity;

// The player, as the property getter and setter, toString() and the planet methods read it.
OOGalaxyID OOJSSystemPlayerCurrentGalaxyID(PlayerEntity* player);
OOSystemID OOJSSystemPlayerCurrentSystemID(PlayerEntity* player);
double OOJSSystemPlayerSystemPseudoRandomFloat(PlayerEntity* player);
unsigned OOJSSystemPlayerSystemPseudoRandom100(PlayerEntity* player);
unsigned OOJSSystemPlayerSystemPseudoRandom256(PlayerEntity* player);
OOPlanetEntity* OOJSSystemPlayerAddPlanet(PlayerEntity* player, const std::string& planetKey);
OOPlanetEntity* OOJSSystemPlayerAddMoon(PlayerEntity* player, const std::string& moonKey);
void OOJSSystemPlayerSendAllShipsAway(PlayerEntity* player);

// -isVisibleToScripts, the category selector each entity class answers (SystemGetProperty()).
bool OOJSSystemEntityIsVisibleToScripts(Entity* entity);

// The universe, as the property getter and setter, the counts and the searches read it.
bool OOJSSystemUniverseInInterstellarSpace();
StationEntity* OOJSSystemUniverseStation();
OOPlanetEntity* OOJSSystemUniversePlanet();
OOSunEntity* OOJSSystemUniverseSun();
std::vector<oo::ObjCRef<OOPlanetEntity*>> OOJSSystemUniversePlanets();
std::vector<oo::ObjCRef<StationEntity*>> OOJSSystemUniverseStations();
std::map<std::string, oo::ObjCRef<OOWaypointEntity*>, std::less<>> OOJSSystemUniverseCurrentWaypoints();
std::vector<oo::ObjCRef<WormholeEntity*>> OOJSSystemUniverseWormholes();
std::vector<oo::ObjCRef<Entity*>> OOJSSystemUniverseFindShipsMatchingPredicate(EntityFilterPredicate predicate, void* parameter, double range, Entity* entity);
std::vector<oo::ObjCRef<Entity*>> OOJSSystemUniverseFindVisualEffectsMatchingPredicate(EntityFilterPredicate predicate, void* parameter, double range, Entity* entity);
std::vector<oo::ObjCRef<Entity*>> OOJSSystemUniverseFindEntitiesMatchingPredicate(EntityFilterPredicate predicate, void* parameter, double range, Entity* entity);
float OOJSSystemUniverseAmbientLightLevel();
void OOJSSystemUniverseSetAmbientLightLevel(float newValue);
void OOJSSystemUniverseSetLighting();
bool OOJSSystemUniverseWitchspaceBreakPattern();
void OOJSSystemUniverseSetWitchspaceBreakPattern(bool newValue);
oo::PList OOJSSystemUniverseGetPopulatorSettings();
oo::PList OOJSSystemUniverseCurrentSystemData();
void OOJSSystemUniverseSetSystemDataForGalaxy(OOGalaxyID gnum, OOSystemID pnum, const std::string& key, const oo::PList& value, const std::optional<std::string>& manifest, OOSystemLayer layer);
unsigned OOJSSystemUniverseCountShipsWithPrimaryRole(const std::string& role, double range, Entity* entity);
unsigned OOJSSystemUniverseCountShipsWithRole(const std::string& role, double range, Entity* entity);
unsigned OOJSSystemUniverseCountShipsWithScanClass(OOScanClass scanClass, double range, Entity* entity);
HPVector OOJSSystemUniverseLocationByCode(const std::string& code, OOSunEntity* sun, OOPlanetEntity* planet);

// The ship creators, legacy spawners, static lookups, effects, populators and waypoints (slice 2).
void OOJSSystemUniverseWitchspaceShipWithPrimaryRole(const std::string& role);
void OOJSSystemUniverseAddShipWithRoleNearRouteOneAt(const std::string& desc, double routeFraction);
bool OOJSSystemUniverseSpawnShip(const std::string& shipdesc);
std::optional<std::string> OOJSSystemUniverseGetSystemName(OOSystemID sys);
OOSystemID OOJSSystemUniverseFindSystemFromName(const std::string& sysName);
OOVisualEffectEntity* OOJSSystemUniverseAddVisualEffectAt(HPVector pos, const std::string& key);
void OOJSSystemUniverseSetPopulatorSetting(const std::string& key, const oo::PList& setting);
void OOJSSystemUniverseDefineWaypoint(const oo::PList& definition, const std::string& key);
HPVector OOJSSystemUniverseGetWitchspaceExitPosition();
std::vector<oo::ObjCRef<ShipEntity*>> OOJSSystemUniverseAddShipsAt(HPVector pos, const std::string& role, unsigned count, GLfloat radius, bool isGroup);
std::vector<oo::ObjCRef<ShipEntity*>> OOJSSystemUniverseAddShipsToRoute(const std::string& route, const std::string& role, unsigned count, double routeFraction, bool isGroup);
void OOJSSystemPlayerAddShipsAt(PlayerEntity* player, const std::string& rolesNumberSystemXYZ);
void OOJSSystemPlayerAddShipsAtPrecisely(PlayerEntity* player, const std::string& rolesNumberSystemXYZ);
void OOJSSystemPlayerAddShipsWithinRadius(PlayerEntity* player, const std::string& rolesNumberSystemXYZR);
OOShipGroup* OOJSSystemShipGroup(ShipEntity* ship);
// [[OOJSPopulatorDefinition alloc] init]: the facade of a new definition, retained (+1).
OOJSPopulatorDefinition* OOJSSystemNewPopulatorDefinition() OO_RETURNS_RETAINED;

#endif // OOJSSYSTEM_OBJCBRIDGE_H
