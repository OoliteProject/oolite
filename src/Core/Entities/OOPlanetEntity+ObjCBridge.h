/*

OOPlanetEntity+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0mxi and oo-ubjo): the Objective-C
OOPlanetEntity, the facade of a converted leaf entity over the C++ cxx::OOPlanetEntity
(OOPlanetEntity.h), kept because the universe and the legacy scripts make planets
([[OOPlanetEntity alloc] initFromDictionary:withAtmosphere:andSeed:forSystem:] and
-initAsMainPlanetForSystem:), and the universe, the player, the ships, the HUD, the scripting
bindings and the shader uniforms (bound to the planet by selector) message it by its own selectors
and as an OOStellarBody. Its interface is the one OOPlanetEntity.h declared before the conversion,
copied exactly, and it has no ivars: the root's _cxxEntity holds its C++ part. Imported as the last
line of OOPlanetEntity.h; do not import it directly. Never add to this file. Deleted by its
deletion bead once its callers are C++.

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

#ifndef OOPLANETENTITY_OBJCBRIDGE_H
#define OOPLANETENTITY_OBJCBRIDGE_H

@interface OOPlanetEntity : Entity <OOStellarBody>

- (id)initAsMainPlanetForSystem:(OOSystemID)s;

- (id)initFromDictionary:(const oo::PList&)dict withAtmosphere:(BOOL)atmosphere andSeed:(Random_Seed)seed forSystem:(OOSystemID)systemID;

- (instancetype)miniatureVersion;

- (double)rotationalVelocity;
- (void)setRotationalVelocity:(double)v;

- (BOOL)planetHasStation;
- (void)launchShuttle;
- (void)welcomeShuttle:(ShipEntity*)shuttle;

- (BOOL)hasAtmosphere;

// FIXME: need material model.
- (std::optional<std::string>)textureFileName; // nullopt: none
- (void)setTextureFileName:(const std::optional<std::string>&)textureName;

- (BOOL)setUpPlanetFromTexture:(const std::optional<std::string>&)fileName; // nullopt: none

- (OOMaterial*)material;
- (OOMaterial*)atmosphereMaterial;
- (OOMaterial*)atmosphereShaderMaterial;

- (BOOL)isFinishedLoading;

- (Vector)airColorAsVector; // visible to shader bindings
- (OOColor*)airColor;
- (void)setAirColor:(OOColor*)newColor;
- (Vector)illuminationColorAsVector; // visible to shader bindings
- (OOColor*)illuminationColor;
- (void)setIlluminationColor:(OOColor*)newColor;
- (float)airColorMixRatio; // visible to shader bindings
- (void)setAirColorMixRatio:(float)newRatio;
- (float)airDensity; // visible to shafer bindings
- (void)setAirDensity:(float)newDensity;

- (void)setTerminatorThresholdVector:(Vector)newTerminatorThresholdVector;
- (Vector)terminatorThresholdVector; // visible to shader bindings

@end

namespace oo {

// The root's crossings, typed (amendment oo-up4b item 3).
inline cxx::OOPlanetEntity* ToCxx(::OOPlanetEntity* entity)
{
    return static_cast<cxx::OOPlanetEntity*>(ToCxx(static_cast<::Entity*>(entity)));
}

inline ::OOPlanetEntity* ToObjC(cxx::OOPlanetEntity* entity)
{
    return (::OOPlanetEntity*)ToObjC(static_cast<cxx::Entity*>(entity));
}

} // namespace oo

#endif // OOPLANETENTITY_OBJCBRIDGE_H
