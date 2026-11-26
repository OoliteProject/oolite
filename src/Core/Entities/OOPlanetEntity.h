/*

OOPlanetEntity.h

Entity subclass representing a planet.

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

#import "OOStellarBody.h"
#if !NEW_PLANETS
#import "PlanetEntity.h"
#else

#import "Entity.h"
#import "OOColor.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

/*	Foundation sweep (proposed ADR-0043, bead oo-eofd): the planet configuration and material
        parameters are oo::PLists (mixed: colours are PList::Object nodes); texture and planet names are
        std::optional (nullopt where they were nil). -textureFileName, -setUpPlanetFromTexture:, -name and
        -setName: are shared selectors and keep id.
*/

@class OOPlanetDrawable, ShipEntity, OOMaterial;

@interface OOPlanetEntity : Entity <OOStellarBody> {
@private
    OOPlanetDrawable* _planetDrawable;
    OOPlanetDrawable* _atmosphereDrawable;
    OOPlanetDrawable* _cloudsShaderDrawable;
    OOPlanetDrawable* _atmosphereShaderDrawable;

    BOOL _miniature;
    OOColor* _airColor;
    OOColor* _illuminationColor;
    float _airColorMixRatio;
    float _airDensity;
    double _mesopause2;

    Vector _rotationAxis;
    float _rotationalVelocity;
    Quaternion _atmosphereOrientation;
    float _atmosphereRotationalVelocity;

    Vector _terminatorThresholdVector;

    unsigned _shuttlesOnGround;
    OOTimeDelta _lastLaunchTime;
    OOTimeDelta _shuttleLaunchInterval;

    oo::PList _materialParameters; // null where it was nil
    std::optional<std::string> _textureName;
    std::optional<std::string> _normSpecMapName;

    std::optional<std::string> _name;
}

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
- (id)textureFileName; // shared selector (proposed ADR-0043): an Objective-C string or nil
- (void)setTextureFileName:(const std::optional<std::string>&)textureName;

- (BOOL)setUpPlanetFromTexture:(id)fileName; // shared selector (proposed ADR-0043): an Objective-C string or nil

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

#endif // NEW_PLANETS
