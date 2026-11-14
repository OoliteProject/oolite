/*

EntityShaderBindings.m

Extra methods exposed for shader bindings.

C++20 since bead oo-aeev (proposed ADR-0056, amendment oo-9fwb): the category Entity
(ShaderBindings) is members of Entity (Entity.h), defined here. The shader uniforms bind them
through the entities' member table; the category's forwarders
(EntityShaderBindings+ObjCBridge.mm) went with bead oo-9ht.127.


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

#import "Entity.h"
#import "OOPlanetEntity.h"
#import "OOShaderUniformMethodType.h" // the shader binding member table
#import "OOVisualEffectEntity.h"
#import "OOWaypointEntity.h"
#import "PlayerEntity.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "PlayerEntityScriptMethods.h"
#import "ProxyPlayerEntity.h"
#import "ShipEntity.h"

#include <array>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <utility>

// -unsignedIntValue of the number a system-data query returned (nil: 0).
static unsigned UnsignedIntValueOf(const oo::PList& value)
{
    return value.isNumber() ? static_cast<unsigned>(value.int64Value()) : 0;
}

// Clock time.
GLfloat Entity::clock()
{
    return (PLAYER != nullptr ? PLAYER->clockTime() : 0.0);
}

// System "flavour" numbers.
unsigned Entity::pseudoFixedD100()
{
    return (PLAYER != nullptr ? PLAYER->systemPseudoRandom100() : unsigned { });
}

unsigned Entity::pseudoFixedD256()
{
    return (PLAYER != nullptr ? PLAYER->systemPseudoRandom256() : unsigned { });
}

// System attributes.
unsigned Entity::systemGovernment()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemGovernment_number() : oo::PList()));
}

unsigned Entity::systemEconomy()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemEconomy_number() : oo::PList()));
}

unsigned Entity::systemTechLevel()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemTechLevel_number() : oo::PList()));
}

unsigned Entity::systemPopulation()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemPopulation_number() : oo::PList()));
}

unsigned Entity::systemProductivity()
{
    return UnsignedIntValueOf((PLAYER != nullptr ? PLAYER->systemProductivity_number() : oo::PList()));
}

#if OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)

/*	The entities' shader binding member table, moved here from Entity+ObjCBridge.mm, its rows
        receiving the C++ entity: one row per name a shader may bind on an entity
        (shader-uniform-bindings.plist and every other name whitelist.plist permits that the root's
        facade answered), each with its uniform type (the type encoding of the
        method it replaces, so the uniform's type is the one the selector path read), whether it applies
        to this entity (what the root facade's -respondsToSelector: answered for it) and its getter (the method's
        body, unchanged but for the receiver). laserColor has no method and no row: it fails as before.
*/
namespace {

// The parts the rows ask for, as the root's facade asks for them (Entity+ObjCBridge.mm).
ShipEntity* ShipPart(Entity* entity) { return dynamic_cast<ShipEntity*>(entity); }
OOVisualEffectEntity* EffectPart(Entity* entity) { return dynamic_cast<OOVisualEffectEntity*>(entity); }
PlayerEntity* PlayerEntityPart(Entity* entity) { return dynamic_cast<PlayerEntity*>(entity); }
ProxyPlayerEntity* ProxyPart(Entity* entity) { return dynamic_cast<ProxyPlayerEntity*>(entity); }

template <typename R>
void StoreShaderBindingValue(OOShaderBindingValue& out, R value)
{
    if constexpr (std::is_same_v<R, Vector>)
        out.v = value;
    else if constexpr (std::is_same_v<R, HPVector>)
        out.hpv = value;
    else if constexpr (std::is_same_v<R, Quaternion>)
        out.q = value;
    else if constexpr (std::is_same_v<R, OOMatrix>)
        out.m = value;
    else if constexpr (std::is_same_v<R, NSPoint>)
        out.p = value;
    else if constexpr (std::is_same_v<R, OOColor*>)
        out.color = value; // borrowed (fogUniform)
    else if constexpr (std::is_floating_point_v<R>)
        out.f = value;
    // BOOL (signed char): sign-extended, as the selector path's call returning signed char was.
    else if constexpr (std::is_same_v<R, signed char>)
        out.i = value < 0 ? static_cast<long long>(static_cast<unsigned char>(value)) - 256 : static_cast<long long>(static_cast<unsigned char>(value));
    else
        out.i = static_cast<long long>(value); // integers and enums
}

struct EntityShaderBindingRow {
    const char* name;
    const char* encoding; // @encode() of the method's return type
    bool (*answers)(Entity* part);
    void (*get)(Entity* part, OOShaderBindingValue& out);
};

constexpr EntityShaderBindingRow kEntityShaderBindings[] = {
    { "position", @encode(HPVector), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> HPVector { return part->getPosition(); }()); } },
    { "orientation", @encode(Quaternion), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Quaternion { return part->getOrientation(); }()); } },
    { "relativePosition", @encode(Vector), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { return part->relativePosition(); }()); } },
    { "viewpointOffset", @encode(Vector), [](Entity* part) -> bool { return PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->viewpointOffset() : kZeroVector; }()); } },
    { "collisionRadius", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->collisionRadius(); }()); } },
    { "mass", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->getMass(); }()); } },
    { "energy", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->getEnergy(); }()); } },
    { "maxEnergy", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->getMaxEnergy(); }()); } },
    { "universalTime", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->universalTime(); }()); } },
    { "spawnTime", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->getSpawnTime(); }()); } },
    { "timeElapsedSinceSpawn", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->timeElapsedSinceSpawn(); }()); } },
    { "throwingSparks", @encode(BOOL), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { return part->throwingSparks(); }()); } },
    { "clock", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { return part->clock(); }()); } },
    { "pseudoFixedD100", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->pseudoFixedD100(); }()); } },
    { "pseudoFixedD256", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->pseudoFixedD256(); }()); } },
    { "systemGovernment", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->systemGovernment(); }()); } },
    { "systemEconomy", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->systemEconomy(); }()); } },
    { "systemTechLevel", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->systemTechLevel(); }()); } },
    { "systemPopulation", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->systemPopulation(); }()); } },
    { "systemProductivity", @encode(unsigned), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> unsigned { return part->systemProductivity(); }()); } },
    { "isBeacon", @encode(BOOL), [](Entity* part) -> bool { return dynamic_cast<OOWaypointEntity*>(part) != nullptr || ShipPart(part) != nullptr || EffectPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { if (ShipEntity *ship = ShipPart(part)) return ship->isBeacon(); if (OOVisualEffectEntity *effect = EffectPart(part)) return effect->isBeacon(); OOWaypointEntity *waypoint = dynamic_cast<OOWaypointEntity *>(part); return waypoint != nullptr ? waypoint->isBeacon() : NO; }()); } },
    { "isFrangible", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getIsFrangible() : NO; }()); } },
    { "isCloaked", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->isCloaked() : NO; }()); } },
    { "isJammingScanning", @encode(BOOL), [](Entity* part) -> bool { return dynamic_cast<OOWaypointEntity*>(part) != nullptr || ShipPart(part) != nullptr || EffectPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { if (ShipEntity *ship = ShipPart(part)) return ship->isJammingScanning(); if (OOVisualEffectEntity *effect = EffectPart(part)) return effect->isJammingScanning(); OOWaypointEntity *waypoint = dynamic_cast<OOWaypointEntity *>(part); return waypoint != nullptr ? waypoint->isJammingScanning() : NO; }()); } },
    { "hasMilitaryScannerFilter", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->hasMilitaryScannerFilter() : NO; }()); } },
    { "messageTime", @encode(double), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> double { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getMessageTime() : double{}; }()); } },
    { "escortCount", @encode(uint8_t), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> uint8_t { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->escortCount() : uint8_t{}; }()); } },
    { "hasHostileTarget", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->hasHostileTarget() : NO; }()); } },
    { "weaponRange", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getWeaponRange() : GLfloat{}; }()); } },
    { "scannerRange", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getScannerRange() : GLfloat{}; }()); } },
    { "withinStationAegis", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->withinStationAegis() : NO; }()); } },
    { "fuel", @encode(OOFuelQuantity), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> OOFuelQuantity { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getFuel() : OOFuelQuantity{}; }()); } },
    { "flightPitch", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getFlightPitch() : GLfloat{}; }()); } },
    { "flightRoll", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getFlightRoll() : GLfloat{}; }()); } },
    { "flightYaw", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getFlightYaw() : GLfloat{}; }()); } },
    { "flightSpeed", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getFlightSpeed() : GLfloat{}; }()); } },
    { "maxFlightSpeed", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getMaxFlightSpeed() : GLfloat{}; }()); } },
    { "speedFactor", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->speedFactor() : GLfloat{}; }()); } },
    { "damage", @encode(int), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> int { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->damage() : int{}; }()); } },
    { "laserHeatLevel", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->laserHeatLevel() : GLfloat{}; }()); } },
    { "hullHeatLevel", @encode(GLfloat), [](Entity* part) -> bool { return EffectPart(part) != nullptr || ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { if (OOVisualEffectEntity *effect = EffectPart(part)) return effect->hullHeatLevel(); ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->hullHeatLevel() : GLfloat{}; }()); } },
    { "entityPersonality", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->entityPersonality() : GLfloat{}; }()); } },
    { "entityPersonalityInt", @encode(GLint), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLint { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->entityPersonalityInt() : GLint{}; }()); } },
    { "numberOfScannedShips", @encode(int), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> int { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->numberOfScannedShips() : int{}; }()); } },
    { "destination", @encode(HPVector), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> HPVector { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->destination() : kZeroHPVector; }()); } },
    { "rangeToDestination", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->rangeToDestination() : GLfloat{}; }()); } },
    { "rangeToPrimaryTarget", @encode(double), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> double { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->rangeToPrimaryTarget() : double{}; }()); } },
    { "isHulk", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->getIsHulk() : NO; }()); } },
    { "lightsActive", @encode(BOOL), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->lightsActive() : NO; }()); } },
    { "legalStatus", @encode(int), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> int { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->legalStatus() : int{}; }()); } },
    { "velocity", @encode(Vector), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { return part->getVelocity(); }()); } },
    { "missileCapacity", @encode(NSUInteger), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> NSUInteger { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->missileCapacity() : NSUInteger{}; }()); } },
    { "missileCount", @encode(NSUInteger), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> NSUInteger { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->missileCount() : NSUInteger{}; }()); } },
    { "fuelLeakRate", @encode(float), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> float { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->fuelLeakRate(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->fuelLeakRate() : float{}; }()); } },
    { "massLocked", @encode(BOOL), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->massLocked(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->massLocked() : NO; }()); } },
    { "atHyperspeed", @encode(BOOL), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->atHyperspeed(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->atHyperspeed() : NO; }()); } },
    { "dialForwardShield", @encode(GLfloat), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->dialForwardShield(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->dialForwardShield() : GLfloat{}; }()); } },
    { "dialAftShield", @encode(GLfloat), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->dialAftShield(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->dialAftShield() : GLfloat{}; }()); } },
    { "dialMissileStatus", @encode(OOMissileStatus), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> OOMissileStatus { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->dialMissileStatus(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->dialMissileStatus() : OOMissileStatus{}; }()); } },
    { "dialFuelScoopStatus", @encode(OOFuelScoopStatus), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> OOFuelScoopStatus { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->dialFuelScoopStatus(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->dialFuelScoopStatus() : OOFuelScoopStatus{}; }()); } },
    { "compassMode", @encode(OOCompassMode), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> OOCompassMode { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->compassMode(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->getCompassMode() : OOCompassMode{}; }()); } },
    { "dialIdentEngaged", @encode(BOOL), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> BOOL { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->dialIdentEngaged(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->dialIdentEngaged() : NO; }()); } },
    { "alertCondition", @encode(OOAlertCondition), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> OOAlertCondition { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->alertCondition() : OOAlertCondition{}; }()); } },
    { "trumbleCount", @encode(NSUInteger), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> NSUInteger { if (ProxyPlayerEntity *proxy = ProxyPart(part)) return proxy->trumbleCount(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->getTrumbleCount() : NSUInteger{}; }()); } },
    // The other names whitelist.plist permits that the root's facade answered by selector, each
    // with its method's return type, the facade's -respondsToSelector: answer and the method's body.
    // The planet's five (Entity (OOPlanetShaderBindings)):
    { "airColorAsVector", @encode(Vector), [](Entity* part) -> bool { return dynamic_cast<OOPlanetEntity*>(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(part); return planet != nullptr ? planet->airColorAsVector() : kZeroVector; }()); } },
    { "illuminationColorAsVector", @encode(Vector), [](Entity* part) -> bool { return dynamic_cast<OOPlanetEntity*>(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(part); return planet != nullptr ? planet->illuminationColorAsVector() : kZeroVector; }()); } },
    { "airColorMixRatio", @encode(float), [](Entity* part) -> bool { return dynamic_cast<OOPlanetEntity*>(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> float { OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(part); return planet != nullptr ? planet->airColorMixRatio() : 0.0f; }()); } },
    { "airDensity", @encode(float), [](Entity* part) -> bool { return dynamic_cast<OOPlanetEntity*>(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> float { OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(part); return planet != nullptr ? planet->airDensity() : 0.0f; }()); } },
    { "terminatorThresholdVector", @encode(Vector), [](Entity* part) -> bool { return dynamic_cast<OOPlanetEntity*>(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { OOPlanetEntity *planet = dynamic_cast<OOPlanetEntity *>(part); return planet != nullptr ? planet->terminatorThresholdVector() : kZeroVector; }()); } },
    // The root's own:
    { "cameraRelativePosition", @encode(Vector), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { return part->getCameraRelativePosition(); }()); } },
    { "fogUniform", @encode(OOColor*), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> OOColor* { return part->fogUniform().get(); }()); } }, // borrowed: the entity holds it
    // The ship family's, found by name (an effect's part answers the three vectors too):
    { "forwardVector", @encode(Vector), [](Entity* part) -> bool { return EffectPart(part) != nullptr || ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { if (OOVisualEffectEntity *effect = EffectPart(part))  return effect->forwardVector(); ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->forwardVector() : kZeroVector; }()); } },
    { "upVector", @encode(Vector), [](Entity* part) -> bool { return EffectPart(part) != nullptr || ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { if (OOVisualEffectEntity *effect = EffectPart(part))  return effect->upVector(); ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->upVector() : kZeroVector; }()); } },
    { "rightVector", @encode(Vector), [](Entity* part) -> bool { return EffectPart(part) != nullptr || ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { if (OOVisualEffectEntity *effect = EffectPart(part))  return effect->rightVector(); ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->rightVector() : kZeroVector; }()); } },
    { "weaponRecoveryTime", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->weaponRecoveryTime() : GLfloat{}; }()); } },
    { "laserHeatLevelAft", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->laserHeatLevelAft() : GLfloat{}; }()); } },
    { "laserHeatLevelForward", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->laserHeatLevelForward() : GLfloat{}; }()); } },
    { "laserHeatLevelPort", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->laserHeatLevelPort() : GLfloat{}; }()); } },
    { "laserHeatLevelStarboard", @encode(GLfloat), [](Entity* part) -> bool { return ShipPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { ShipEntity *ship = ShipPart(part); return ship != nullptr ? ship->laserHeatLevelStarboard() : GLfloat{}; }()); } },
    { "tradeInFactor", @encode(int), [](Entity* part) -> bool { return ProxyPart(part) != nullptr || PlayerEntityPart(part) != nullptr; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> int { if (ProxyPlayerEntity *proxy = ProxyPart(part))  return proxy->tradeInFactor(); PlayerEntity *player = PlayerEntityPart(part); return player != nullptr ? player->tradeInFactor() : int{}; }()); } },
    // The visual effect's, found by name: the root's facade answers these for any entity (its category's
    // methods; -respondsToSelector: does not restrict them), 0 for any but an effect's part.
    { "shaderFloat1", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { OOVisualEffectEntity *effect = EffectPart(part); return effect != nullptr ? effect->shaderFloat1() : GLfloat{}; }()); } },
    { "shaderFloat2", @encode(GLfloat), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> GLfloat { OOVisualEffectEntity *effect = EffectPart(part); return effect != nullptr ? effect->shaderFloat2() : GLfloat{}; }()); } },
    { "shaderInt1", @encode(int), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> int { OOVisualEffectEntity *effect = EffectPart(part); return effect != nullptr ? effect->shaderInt1() : 0; }()); } },
    { "shaderInt2", @encode(int), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> int { OOVisualEffectEntity *effect = EffectPart(part); return effect != nullptr ? effect->shaderInt2() : 0; }()); } },
    { "shaderVector1", @encode(Vector), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { OOVisualEffectEntity *effect = EffectPart(part); return effect != nullptr ? effect->shaderVector1() : kZeroVector; }()); } },
    { "shaderVector2", @encode(Vector), [](Entity*) -> bool { return true; },
        [](Entity* part, OOShaderBindingValue& out) { StoreShaderBindingValue(out, [part]() -> Vector { OOVisualEffectEntity *effect = EffectPart(part); return effect != nullptr ? effect->shaderVector2() : kZeroVector; }()); } },
};

// The row's getter, given the uniform's target (the entity the lookup answered).
template <size_t I>
void GetShaderBinding(oo::RefCounted* target, OOShaderBindingValue& out)
{
    kEntityShaderBindings[I].get(static_cast<Entity*>(target), out);
}

template <size_t... I>
std::array<OOShaderMemberGetter, sizeof...(I)> ShaderBindingGetters(std::index_sequence<I...>)
{
    return { &GetShaderBinding<I>... };
}

} // namespace

bool EntityShaderMemberBindingFor(Entity* entity, const char* property, OOShaderMemberBinding* outBinding)
{
    if (entity == nullptr || property == nullptr || outBinding == nullptr)
        return false;

    static const std::unordered_map<std::string, size_t> rows = [] {
        std::unordered_map<std::string, size_t> result;
        for (size_t i = 0; i != std::size(kEntityShaderBindings); ++i)
            result.emplace(kEntityShaderBindings[i].name, i);
        return result;
    }();
    static const std::array<OOShaderMemberGetter, std::size(kEntityShaderBindings)> getters = ShaderBindingGetters(std::make_index_sequence<std::size(kEntityShaderBindings)>());

    const auto found = rows.find(property);
    if (found == rows.end())
        return false;
    const EntityShaderBindingRow& row = kEntityShaderBindings[found->second];
    if (!row.answers(entity))
        return false; // the selector path fails as it did
    const OOShaderUniformType type = OOShaderUniformTypeFromEncoding(row.encoding);
    if (type == kOOShaderUniformTypeInvalid)
        return false; // likewise ("unsupported type")
    *outBinding = { type, getters[found->second], entity };
    return true;
}

/*	What the uniforms and the materials ask of a binding target that is an entity, registered so
        that the materials link without the entities. Each answers what the entity's object answered:
        the root facade's methods are the C++ entity's members (the object is deleted).
*/
namespace {

// What the root facade's object answered (it is deleted): the entity's own members, for an
// entity that has its object; nil's answers for one without.
Entity* ShaderSuperTarget(Entity* entity)
{
    // The root facade's -superShaderBindingTarget: the parent entity; nil's for an entity without its object.
    return (oo::WithObject(entity) != nullptr) ? entity->parentEntity() : nullptr;
}

std::string ShaderClassName(Entity* entity)
{
    return (oo::WithObject(entity) != nullptr) ? std::string("Entity") : std::string("(null)"); // its object's class, the root facade
}

std::string ShaderDescription(Entity* entity)
{
    return oo::EntityDescription(entity);
}

bool ShaderMemberBinding(Entity* entity, const char* property, OOShaderMemberBinding* outBinding)
{
    if (oo::WithObject(entity) == nullptr)
        return false; // nil bound nothing
    return EntityShaderMemberBindingFor(entity, property, outBinding);
}

bool ShaderRandomSeed(Entity* entity, uint32_t* outSeed)
{
    // -randomSeedForShaders: the ship family's, found by name (the root's facade answered it for a
    // ship's part, the by-name table's row), and a ship's part's where there
    // was no object to ask.
    ShipEntity* ship = ShipPart(entity);
    if (ship == nullptr)
        return false;
    *outSeed = ship->randomSeedForShaders();
    return true;
}

const bool sShaderEntityHooksRegistered = (OOSetShaderEntityHooks({ &ShaderSuperTarget, &ShaderClassName, &ShaderDescription, &ShaderMemberBinding, &ShaderRandomSeed }), true);

} // namespace

#endif // OO_SHADERS || defined(OO_DEBUG_MONITOR_ENABLED)
